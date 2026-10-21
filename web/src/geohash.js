// Geohash, as in packages/roadto_core/lib/src/geohash.dart.
const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export function encode(lat, lon, precision = 7) {
  let latMin = -90, latMax = 90, lonMin = -180, lonMax = 180;
  let out = '', bit = 0, ch = 0, even = true;
  while (out.length < precision) {
    if (even) {
      const mid = (lonMin + lonMax) / 2;
      if (lon >= mid) { ch = (ch << 1) | 1; lonMin = mid; } else { ch <<= 1; lonMax = mid; }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latMin = mid; } else { ch <<= 1; latMax = mid; }
    }
    even = !even;
    if (++bit === 5) { out += BASE32[ch]; bit = 0; ch = 0; }
  }
  return out;
}

/** {latMin, latMax, lonMin, lonMax, lat, lon} of a cell. */
export function decode(hash) {
  let latMin = -90, latMax = 90, lonMin = -180, lonMax = 180, even = true;
  for (const c of hash) {
    const v = BASE32.indexOf(c);
    if (v < 0) throw new Error(`not a geohash: ${hash}`);
    for (let b = 4; b >= 0; b--) {
      const on = (v >> b) & 1;
      if (even) { const mid = (lonMin + lonMax) / 2; if (on) lonMin = mid; else lonMax = mid; }
      else { const mid = (latMin + latMax) / 2; if (on) latMin = mid; else latMax = mid; }
      even = !even;
    }
  }
  return { latMin, latMax, lonMin, lonMax, lat: (latMin + latMax) / 2, lon: (lonMin + lonMax) / 2 };
}

/**
 * Cells covering a map view (south, west, north, east): precision 5 (about
 * 5 km) like the app, 4 (about 20 km) when that would take more than [max]
 * cells. Alerts carry their cell at precisions 4 to 7 only, so a wider view
 * gets null: too wide to ask the relays.
 */
export function cellsCovering({ s, w, n, e }, max = 64) {
  for (const precision of [5, 4]) {
    const probe = decode(encode(s, w, precision));
    const dLat = probe.latMax - probe.latMin, dLon = probe.lonMax - probe.lonMin;
    const rows = Math.ceil((n - s) / dLat) + 1, cols = Math.ceil((e - w) / dLon) + 1;
    if (rows * cols > max) continue;
    const cells = new Set();
    for (let i = 0; i <= rows; i++) {
      for (let j = 0; j <= cols; j++) {
        cells.add(encode(Math.min(s + i * dLat, n), Math.min(w + j * dLon, e), precision));
      }
    }
    return [...cells].sort();
  }
  return null;
}

/**
 * Cells along a route ([{lat, lon}]), [marginM] on each side: precision 5,
 * or 4 when that would take more than [max] cells; null for a route too
 * long to ask the relays about.
 */
export function cellsAlong(shape, marginM = 150, max = 64) {
  const dLat = marginM / 111320;
  for (const precision of [5, 4]) {
    const cells = new Set();
    for (const p of sample(shape, 500)) {
      const dLon = marginM / (111320 * Math.cos((p.lat * Math.PI) / 180));
      for (const [y, x] of [[0, 0], [dLat, 0], [-dLat, 0], [0, dLon], [0, -dLon]]) cells.add(encode(p.lat + y, p.lon + x, precision));
      if (cells.size > max) break;
    }
    if (cells.size <= max) return [...cells].sort();
  }
  return null;
}

/** The shape's points, plus points every [stepM] on long segments. */
function sample(shape, stepM) {
  const out = [];
  for (let i = 0; i < shape.length; i++) {
    const a = shape[i];
    out.push(a);
    const b = shape[i + 1];
    if (!b) break;
    const dy = (b.lat - a.lat) * 111320, dx = (b.lon - a.lon) * 111320 * Math.cos((a.lat * Math.PI) / 180);
    const n = Math.floor(Math.hypot(dx, dy) / stepM);
    for (let k = 1; k <= n; k++) out.push({ lat: a.lat + ((b.lat - a.lat) * k) / (n + 1), lon: a.lon + ((b.lon - a.lon) * k) / (n + 1) });
  }
  return out;
}
