// What every page shares: the site's settings and the map style.

/**
 * Relays to read (wss:// in production). Set at deploy time in config.js
 * (window.ROADTO_CONFIG); ?relais=wss://a,wss://b overrides them, to try a
 * relay; on localhost, the development relay.
 */
export function config() {
  const set = globalThis.ROADTO_CONFIG ?? {};
  const fromQuery = new URLSearchParams(location.search).get('relais');
  const local = ['localhost', '127.0.0.1'].includes(location.hostname) ? ['ws://localhost:7777'] : [];
  const relays = fromQuery ? fromQuery.split(',').map((s) => s.trim()).filter(Boolean) : (set.relays ?? local);
  return { relays };
}

const dark = () => matchMedia('(prefers-color-scheme: dark)').matches;

/** RoadTo's style (pipeline web-style), day or night as the device is set. */
export function mapStyle() {
  return new URL(`styles/roadto-${dark() ? 'night' : 'day'}.json`, location.href).href;
}

export function watchColorScheme(onChange) {
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => onChange(mapStyle()));
}
