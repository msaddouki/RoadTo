// Routes, as the app computes them (packages/roadto_core/lib/src/routing):
// the same Valhalla request, the same shape decoding, the same alerts on the
// way. The site asks an online Valhalla server; the app routes on the phone.

const EARTH_RADIUS_M = 6371008.8;
const rad = (d) => (d * Math.PI) / 180;

export function distanceM(a, b) {
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Types of alerts the route must go around, as in the app (blocksRoad). */
export const BLOCKING = new Set(['accident', 'closure']);

/** Body of a Valhalla /route request (valhallaRouteRequest in the core). */
export function routeRequest(from, to, { avoid = [], language = 'fr-FR' } = {}) {
  return {
    locations: [{ lat: from.lat, lon: from.lon }, { lat: to.lat, lon: to.lon }],
    costing: 'auto',
    units: 'kilometers',
    language,
    directions_options: { units: 'kilometers', language },
    // Small squares (~40 m) around closed roads and blocking accidents.
    ...(avoid.length ? { exclude_polygons: avoid.map((p) => square(p, 20)) } : {}),
  };
}

function square(c, halfM) {
  const dLat = halfM / 111320;
  const dLon = halfM / (111320 * Math.cos(rad(c.lat)));
  return [
    [c.lon - dLon, c.lat - dLat],
    [c.lon + dLon, c.lat - dLat],
    [c.lon + dLon, c.lat + dLat],
    [c.lon - dLon, c.lat + dLat],
    [c.lon - dLon, c.lat - dLat],
  ];
}

/** Encoded polyline (precision 6, Valhalla's) to [{lat, lon}]. */
export function decodePolyline(encoded, precision = 6) {
  const factor = 10 ** precision;
  const points = [];
  let index = 0, lat = 0, lon = 0;
  const next = () => {
    let result = 0, shift = 0, b;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return result & 1 ? ~(result >> 1) : result >> 1;
  };
  while (index < encoded.length) {
    lat += next();
    lon += next();
    points.push({ lat: lat / factor, lon: lon / factor });
  }
  return points;
}

export class RoutingError extends Error {}

/** A Valhalla answer as {shape, maneuvers, lengthM, timeS, cumulative}, legs joined. */
export function parseRoute(json) {
  if (json.error) throw new RoutingError(`${json.error}${json.error_code ? ` (${json.error_code})` : ''}`);
  const trip = json.trip;
  if (!trip) throw new RoutingError('Réponse sans itinéraire');
  const shape = [], maneuvers = [];
  for (const leg of trip.legs) {
    const legShape = decodePolyline(leg.shape);
    // Legs share their junction point.
    const offset = shape.length === 0 ? 0 : shape.length - 1;
    shape.push(...(shape.length === 0 ? legShape : legShape.slice(1)));
    for (const m of leg.maneuvers) {
      maneuvers.push({
        type: m.type,
        instruction: m.instruction ?? '',
        streetNames: m.street_names ?? [],
        beginShapeIndex: offset + m.begin_shape_index,
        lengthM: (m.length ?? 0) * 1000,
        timeS: m.time ?? 0,
      });
    }
  }
  const cumulative = [0];
  for (let i = 1; i < shape.length; i++) cumulative.push(cumulative[i - 1] + distanceM(shape[i - 1], shape[i]));
  return { shape, maneuvers, cumulative, lengthM: trip.summary.length * 1000, timeS: trip.summary.time };
}

/** [p] projected on the route: {alongM, offsetM, point}, or null for an empty route. */
export function projectOnRoute(route, p) {
  const { shape, cumulative } = route;
  if (shape.length < 2) return null;
  let best = null;
  for (let i = 0; i < shape.length - 1; i++) {
    const a = shape[i], b = shape[i + 1];
    // Local equirectangular plane, as projectOnSegment in the core.
    const cosLat = Math.cos(rad(a.lat));
    const bx = (b.lon - a.lon) * cosLat, by = b.lat - a.lat;
    const px = (p.lon - a.lon) * cosLat, py = p.lat - a.lat;
    const len2 = bx * bx + by * by;
    const t = len2 === 0 ? 0 : Math.min(1, Math.max(0, (px * bx + py * by) / len2));
    const q = { lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t };
    const d = distanceM(p, q);
    if (best === null || d < best.offsetM) {
      best = { alongM: cumulative[i] + t * (cumulative[i + 1] - cumulative[i]), offsetM: d, point: q };
    }
  }
  return best;
}

/**
 * Alerts on the route ({alert, distanceM}), in the order the driver meets
 * them: within [maxOffsetM] of it, as alertsAhead in the core, over the
 * whole route.
 */
export function alertsOnRoute(route, alerts, { maxOffsetM = 120 } = {}) {
  const out = [];
  for (const a of alerts) {
    const p = projectOnRoute(route, a);
    if (p === null || p.offsetM > maxOffsetM) continue;
    out.push({ alert: a, distanceM: p.alongM });
  }
  return out.sort((x, y) => x.distanceM - y.distanceM);
}

/** "Accident", "Bouchon ×2": alerts by type, in the order they come. */
export function alertSummary(onRoute) {
  const counts = new Map();
  for (const { alert } of onRoute) {
    const c = counts.get(alert.type) ?? { label: alert.label, color: alert.color, n: 0 };
    c.n++;
    counts.set(alert.type, c);
  }
  return [...counts].map(([type, c]) => ({ type, color: c.color, text: c.n === 1 ? c.label : `${c.label} ×${c.n}` }));
}

/** "12 min", "1 h 05". */
export function durationText(seconds) {
  const m = Math.max(1, Math.round(seconds / 60));
  if (m < 60) return `${m} min`;
  return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}`;
}

/** "85 m", "850 m", "4,2 km", "37 km", as in the app (formatDistance). */
export function distanceText(m) {
  if (m >= 10_000) return `${Math.round(m / 1000)} km`;
  if (m >= 1000) return `${(m / 1000).toFixed(1).replace('.', ',')} km`;
  if (m >= 100) return `${Math.round(m / 10) * 10} m`;
  return `${Math.round(m)} m`;
}

/** [[w, s], [e, n]] of the route, for fitting the map. */
export function bounds(shape) {
  let s = 90, w = 180, n = -90, e = -180;
  for (const p of shape) {
    s = Math.min(s, p.lat); n = Math.max(n, p.lat);
    w = Math.min(w, p.lon); e = Math.max(e, p.lon);
  }
  return [[w, s], [e, n]];
}

/**
 * Client of a Valhalla server. [fetchImpl] for tests.
 */
export async function fetchRoute(baseUrl, from, to, { avoid = [], signal, fetchImpl = globalThis.fetch } = {}) {
  let res;
  try {
    res = await fetchImpl(new URL('route', baseUrl), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(routeRequest(from, to, { avoid })),
      signal,
    });
  } catch (e) {
    if (e.name === 'AbortError') throw e;
    throw new RoutingError('Serveur d’itinéraire injoignable');
  }
  let json;
  try { json = await res.json(); } catch { throw new RoutingError(`Réponse illisible du serveur d’itinéraire (${res.status})`); }
  if (!res.ok && !json.error) throw new RoutingError(`Erreur du serveur d’itinéraire (${res.status})`);
  return parseRoute(json);
}
