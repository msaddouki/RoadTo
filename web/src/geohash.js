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
