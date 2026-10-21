// What every page shares: the site's settings and the map style.

// Online services for routes and search, the ones the app falls back to
// (app/lib/config.dart). Set ROADTO_ROUTING_URL / ROADTO_GEOCODER_URL to
// use your own, and allow them in the Content Security Policy (render.yaml).
const ROUTING_URL = 'https://valhalla1.openstreetmap.de/';
const GEOCODER_URL = 'https://photon.komoot.io/';

/**
 * Relays to read (wss:// in production). Set at deploy time in config.js
 * (window.ROADTO_CONFIG); ?relais=wss://a,wss://b overrides them, to try a
 * relay; on localhost, the development relay. Also the routing and search
 * servers.
 */
export function config() {
  const set = globalThis.ROADTO_CONFIG ?? {};
  const fromQuery = new URLSearchParams(location.search).get('relais');
  const local = ['localhost', '127.0.0.1'].includes(location.hostname) ? ['ws://localhost:7777'] : [];
  const relays = fromQuery ? fromQuery.split(',').map((s) => s.trim()).filter(Boolean) : (set.relays ?? local);
  return { relays, routingUrl: set.routingUrl ?? ROUTING_URL, geocoderUrl: set.geocoderUrl ?? GEOCODER_URL };
}

const dark = () => matchMedia('(prefers-color-scheme: dark)').matches;

/**
 * RoadTo's style (pipeline web_style), day or night as the device is set,
 * with its sprite made absolute as MapLibre requires.
 */
export async function mapStyle() {
  const url = new URL(`styles/roadto-${dark() ? 'night' : 'day'}.json`, location.href);
  const style = await (await fetch(url)).json();
  return { ...style, sprite: new URL(style.sprite, url.href.replace(/styles\/[^/]*$/, '')).href };
}

export function watchColorScheme(onChange) {
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', async () => onChange(await mapStyle()));
}
