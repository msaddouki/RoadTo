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

export function bearingDeg(a, b) {
  const la1 = rad(a.lat), la2 = rad(b.lat), dLon = rad(b.lon - a.lon);
  const y = Math.sin(dLon) * Math.cos(la2);
  const x = Math.cos(la1) * Math.sin(la2) - Math.sin(la1) * Math.cos(la2) * Math.cos(dLon);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

/** Body of a Valhalla /route request (valhallaRouteRequest in the core). */
export function routeRequest(from, to, { avoid = [], headingDeg = null, language = 'fr-FR', alternates = 0 } = {}) {
  const start = { lat: from.lat, lon: from.lon };
  if (headingDeg !== null && headingDeg !== undefined) Object.assign(start, { heading: Math.round(headingDeg), heading_tolerance: 45 });
  return {
    locations: [start, { lat: to.lat, lon: to.lon }],
    costing: 'auto',
    units: 'kilometers',
    language,
    directions_options: { units: 'kilometers', language },
    // Small squares (~40 m) around closed roads and blocking accidents.
    ...(avoid.length ? { exclude_polygons: avoid.map((p) => square(p, 20)) } : {}),
    ...(alternates > 0 ? { alternates } : {}),
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

/** The route of a Valhalla answer, then its alternatives. */
export function parseRoutes(json) {
  return [parseRoute(json), ...(json.alternates ?? []).filter((a) => a?.trip).map(parseRoute)];
}

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
        verbalAlert: m.verbal_transition_alert_instruction ?? null,
        verbalPre: m.verbal_pre_transition_instruction ?? null,
        verbalPost: m.verbal_post_transition_instruction ?? null,
        isArrival: m.type >= 4 && m.type <= 6,
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

/**
 * [p] projected on the route, on segments [from] to [to]:
 * {segmentIndex, alongM, offsetM, point}, or null for an empty route.
 */
export function projectOnRoute(route, p, { from = 0, to = null } = {}) {
  const { shape, cumulative } = route;
  if (shape.length < 2) return null;
  const end = Math.min(Math.max(to ?? shape.length - 1, 1), shape.length - 1);
  let best = null;
  for (let i = Math.min(Math.max(from, 0), shape.length - 2); i < end; i++) {
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
      best = { segmentIndex: i, alongM: cumulative[i] + t * (cumulative[i + 1] - cumulative[i]), offsetM: d, point: q };
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

/** Distance from the start of the route to the start of maneuver [i]. */
export function maneuverStartM(route, i) {
  return route.cumulative[Math.min(Math.max(route.maneuvers[i].beginShapeIndex, 0), route.shape.length - 1)];
}

/** Length of the shape itself (a few metres off lengthM). */
export const shapeLengthM = (route) => route.cumulative.at(-1) ?? 0;

/** The point [d] metres from the start, along the route. */
export function pointAt(route, d) {
  const { shape, cumulative } = route;
  if (d <= 0) return shape[0];
  if (d >= shapeLengthM(route)) return shape.at(-1);
  let lo = 0, hi = cumulative.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (cumulative[mid] <= d) lo = mid; else hi = mid;
  }
  const seg = cumulative[hi] - cumulative[lo];
  const f = seg === 0 ? 0 : (d - cumulative[lo]) / seg;
  return { lat: shape[lo].lat + (shape[hi].lat - shape[lo].lat) * f, lon: shape[lo].lon + (shape[hi].lon - shape[lo].lon) * f };
}

/** Heading of the route [d] metres from the start. */
export function bearingAt(route, d) {
  const a = pointAt(route, d), b = pointAt(route, d + 15);
  return a.lat === b.lat && a.lon === b.lon ? bearingDeg(pointAt(route, d - 15), a) : bearingDeg(a, b);
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
export async function fetchRoute(baseUrl, from, to, { avoid = [], headingDeg = null, signal, fetchImpl = globalThis.fetch } = {}) {
  return parseRoute(await post(baseUrl, 'route', routeRequest(from, to, { avoid, headingDeg }), { signal, fetchImpl }));
}

/** The engine's route and up to [alternates] others. */
export async function fetchRoutes(baseUrl, from, to, { avoid = [], headingDeg = null, alternates = 2, signal, fetchImpl = globalThis.fetch } = {}) {
  return parseRoutes(await post(baseUrl, 'route', routeRequest(from, to, { avoid, headingDeg, alternates }), { signal, fetchImpl }));
}

/** A request to the Valhalla server; its JSON answer. */
export async function post(baseUrl, action, body, { signal, fetchImpl = globalThis.fetch } = {}) {
  let res;
  try {
    res = await fetchImpl(new URL(action, baseUrl), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
      signal,
    });
  } catch (e) {
    if (e.name === 'AbortError') throw e;
    throw new RoutingError('Serveur d’itinéraire injoignable');
  }
  let json;
  try { json = await res.json(); } catch { throw new RoutingError(`Réponse illisible du serveur d’itinéraire (${res.status})`); }
  if (!res.ok && !json.error) throw new RoutingError(`Erreur du serveur d’itinéraire (${res.status})`);
  return json;
}

/** Encoded polyline (precision 6) of [{lat, lon}]. */
export function encodePolyline(points, precision = 6) {
  const factor = 10 ** precision;
  let out = '', lastLat = 0, lastLon = 0;
  const put = (v) => {
    let n = v < 0 ? ~(v << 1) : v << 1;
    while (n >= 0x20) {
      out += String.fromCharCode((0x20 | (n & 0x1f)) + 63);
      n >>= 5;
    }
    out += String.fromCharCode(n + 63);
  };
  for (const p of points) {
    const lat = Math.round(p.lat * factor), lon = Math.round(p.lon * factor);
    put(lat - lastLat);
    put(lon - lastLon);
    lastLat = lat;
    lastLon = lon;
  }
  return out;
}

/**
 * Posted speed limits along the route (speed_limits.dart in the core), from
 * a trace_attributes answer on the route's own shape (road.js):
 * [{startM, endM, kph, unlimited}], ordered; consecutive equal limits merged.
 */
export function parseSpeedLimits(json) {
  if (typeof json.shape !== 'string' || !Array.isArray(json.edges)) return [];
  const shape = decodePolyline(json.shape);
  if (shape.length < 2) return [];
  const cumulative = [0];
  for (let i = 1; i < shape.length; i++) cumulative.push(cumulative[i - 1] + distanceM(shape[i - 1], shape[i]));
  const at = (index) => cumulative[Math.min(Math.max(Math.trunc(index ?? 0), 0), shape.length - 1)];
  const spans = [];
  for (const e of json.edges) {
    const start = at(e.begin_shape_index), end = at(e.end_shape_index);
    if (end <= start) continue;
    const raw = e.speed_limit;
    const unlimited = raw === 'unlimited';
    const kph = typeof raw === 'number' && raw > 0 && raw < 250 ? Math.round(raw) : null;
    const last = spans.at(-1);
    if (last && last.kph === kph && last.unlimited === unlimited && Math.abs(start - last.endM) < 1) last.endM = end;
    else spans.push({ startM: start, endM: end, kph, unlimited });
  }
  return spans;
}

/** The limit span at [alongM], or null. */
export function limitAt(spans, alongM) {
  let lo = 0, hi = spans.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1, s = spans[mid];
    if (alongM < s.startM) hi = mid - 1;
    else if (alongM >= s.endM) lo = mid + 1;
    else return s;
  }
  return null;
}

/** Over the limit with the usual margin: 5 km/h up to 100, 5 % above. */
export const isOverLimit = (kph, limit) => kph > (limit <= 100 ? limit + 5 : limit * 1.05);

