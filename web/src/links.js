// Place links: the place travels in the fragment (after #), which browsers
// never send to the server, so the site does not learn where people meet.
//   lieu.html#45.75780,4.83200,Place%20Bellecour

export function placeLink(base, { lat, lon, name }) {
  const fragment = `${lat.toFixed(5)},${lon.toFixed(5)}${name ? `,${encodeURIComponent(name)}` : ''}`;
  return `${base.replace(/\/$/, '')}/lieu.html#${fragment}`;
}

/** {lat, lon, name} from a fragment, or null when it is not a place. */
export function parsePlace(fragment) {
  const m = /^#?(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)(?:,(.*))?$/.exec(fragment ?? '');
  if (!m) return null;
  const lat = Number(m[1]), lon = Number(m[2]);
  if (Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  let name = null;
  try { name = m[3] ? decodeURIComponent(m[3]).slice(0, 120) : null; } catch { name = null; }
  return { lat, lon, name };
}

/**
 * A route: both ends in the fragment, never sent to the server.
 *   itineraire.html#de=45.75780,4.83200,Bellecour&vers=45.76030,4.85940,Part-Dieu
 * Without "de", the route starts from where the visitor is.
 */
export function routeLink(base, { from, to }) {
  const part = ({ lat, lon, name }) => `${lat.toFixed(5)},${lon.toFixed(5)}${name ? `,${encodeURIComponent(name)}` : ''}`;
  const fragment = [from ? `de=${part(from)}` : null, to ? `vers=${part(to)}` : null].filter(Boolean).join('&');
  return `${base.replace(/\/$/, '')}/itineraire.html${fragment ? `#${fragment}` : ''}`;
}

/** {from, to} from a route fragment; each is a place or null. */
export function parseRoute(fragment) {
  const out = { from: null, to: null };
  for (const piece of (fragment ?? '').replace(/^#/, '').split('&')) {
    const m = /^(de|vers)=(.*)$/.exec(piece);
    if (m) out[m[1] === 'de' ? 'from' : 'to'] = parsePlace(m[2]);
  }
  return out;
}

/** The app's own link for a place (roadto://), opened when RoadTo is installed. */
export function appLink({ lat, lon, name }) {
  const q = new URLSearchParams({ lat: lat.toFixed(5), lon: lon.toFixed(5), ...(name ? { name } : {}) });
  return `roadto://place?${q}`;
}
