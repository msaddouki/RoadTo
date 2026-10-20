// Live alerts: the alerts the relays carry for the area on screen, as the
// app shows them (verified, not expired, trusted enough). Read only.
import maplibregl from 'maplibre-gl';

import { AlertStore, ago, alertFilter } from '../alerts.js';
import { cellsCovering } from '../geohash.js';
import { ICONS } from '../icons.js';
import { RelayPool } from '../relays.js';
import { config, mapStyle, watchColorScheme } from '../site.js';
import { verifyEvent } from '../verify.js';

const status = document.getElementById('status');
const count = document.getElementById('count');
const hint = document.getElementById('hint');

const view = parseView(location.hash) ?? { lat: 45.758, lon: 4.84, zoom: 12 };
const map = new maplibregl.Map({
  container: 'map',
  style: mapStyle(),
  center: [view.lon, view.lat],
  zoom: view.zoom,
  attributionControl: { compact: true },
  hash: false,
});
map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-right');
watchColorScheme((style) => map.setStyle(style));

const store = new AlertStore();
const markers = new Map();
const relays = config().relays;

const pool = new RelayPool(relays, {
  verify: verifyEvent,
  onEvent: (e) => {
    if (store.ingest(e)) scheduleDraw();
  },
  onStatus: (s) => {
    const open = [...s.values()].filter((v) => v === 'open').length;
    status.textContent =
      relays.length === 0
        ? 'Aucun relais configuré'
        : open === 0
          ? 'Connexion aux relais…'
          : `${open} relais connecté${open > 1 ? 's' : ''}`;
    status.dataset.state = open > 0 ? 'open' : 'closed';
  },
});
pool.onStatus(pool.status);
pool.connect();

function subscribe() {
  const b = map.getBounds();
  const cells = cellsCovering({ s: b.getSouth(), w: b.getWest(), n: b.getNorth(), e: b.getEast() });
  hint.hidden = cells !== null;
  if (cells) pool.subscribe(alertFilter(cells));
  history.replaceState(null, '', `#${map.getCenter().lat.toFixed(4)},${map.getCenter().lng.toFixed(4)},${map.getZoom().toFixed(1)}`);
}
map.on('load', subscribe);
map.on('moveend', subscribe);

let pending = null;
function scheduleDraw() {
  pending ??= setTimeout(() => {
    pending = null;
    draw();
  }, 200);
}

function draw() {
  const now = Date.now() / 1000;
  store.purge(now);
  const visible = store.visible(now);
  const ids = new Set(visible.map((a) => a.id));
  for (const [id, m] of markers) {
    if (!ids.has(id)) {
      m.remove();
      markers.delete(id);
    }
  }
  for (const a of visible) {
    if (markers.has(a.id)) continue;
    const el = document.createElement('button');
    el.className = 'pin';
    el.style.setProperty('--pin', a.color);
    el.innerHTML = ICONS[a.type];
    el.setAttribute('aria-label', a.label);
    const popup = new maplibregl.Popup({ offset: 22, closeButton: false }).setDOMContent(details(a));
    popup.on('open', () => popup.setDOMContent(details(a)));
    markers.set(a.id, new maplibregl.Marker({ element: el }).setLngLat([a.lon, a.lat]).setPopup(popup).addTo(map));
  }
  count.textContent = visible.length === 0 ? 'Aucune alerte ici' : `${visible.length} alerte${visible.length > 1 ? 's' : ''}`;
}
setInterval(draw, 30_000);

function details(a) {
  const now = Date.now() / 1000;
  const c = store.stillThere(a.id);
  const el = document.createElement('div');
  el.className = 'popup';
  const title = document.createElement('strong');
  title.textContent = a.label;
  const when = document.createElement('span');
  when.textContent =
    c.count === 0
      ? `Signalé ${ago(now - a.createdAt)}`
      : `Confirmé par ${c.count === 1 ? '1 conducteur' : `${c.count} conducteurs`} · ${ago(now - c.latest)}`;
  const score = document.createElement('meter');
  score.min = 0;
  score.max = 1;
  score.value = store.reliability(a.id, now);
  score.title = 'Fiabilité';
  el.append(title, when, score);
  return el;
}

function parseView(hash) {
  const m = /^#(-?[\d.]+),(-?[\d.]+),([\d.]+)$/.exec(hash);
  return m ? { lat: Number(m[1]), lon: Number(m[2]), zoom: Number(m[3]) } : null;
}
