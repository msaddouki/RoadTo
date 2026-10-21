// Route preview, like the app's before "Partir": the route, its time and
// length, and the alerts drivers report on it. Guidance stays in the app:
// "Ouvrir dans RoadTo" hands it the destination.
import * as maplibregl from 'maplibre-gl';

import { AlertStore, alertFilter } from '../alerts.js';
import { searchPlaces } from '../geocoder.js';
import { cellsAlong } from '../geohash.js';
import { ICONS } from '../icons.js';
import { appLink, parseRoute, routeLink } from '../links.js';
import { RelayPool } from '../relays.js';
import {
  BLOCKING, RoutingError, alertSummary, alertsOnRoute, bounds, distanceText, durationText, fetchRoute, projectOnRoute,
} from '../routing.js';
import { config, mapStyle, watchColorScheme } from '../site.js';
import { verifyEvent } from '../verify.js';
import { Navigation } from '../navigation.js';

const settings = config();
const $ = (id) => document.getElementById(id);
const message = $('message');

const ends = parseRoute(location.hash);
const state = {
  from: ends.from, // {lat, lon, name, here?}
  to: ends.to,
  route: null,
  avoid: [], // {id, lat, lon}: where a blocking alert meets the route, to go around
};

const map = new maplibregl.Map({
  container: 'map',
  style: await mapStyle(),
  center: [4.84, 45.758],
  zoom: 11,
  attributionControl: { compact: true },
});
map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-right');

// The route under the street names, as in the app.
const EMPTY = { type: 'FeatureCollection', features: [] };
function addLayers() {
  if (map.getSource('route')) return;
  map.addSource('route', { type: 'geojson', data: routeData() });
  const below = map.getLayer('roadto-labels') ? 'roadto-labels' : undefined;
  const layout = { 'line-cap': 'round', 'line-join': 'round' };
  map.addLayer({ id: 'route-casing', type: 'line', source: 'route', layout, paint: { 'line-color': '#0B3D91', 'line-width': 12 } }, below);
  // During a trip, the part already driven greys out.
  const color = ['match', ['get', 'part'], 'done', '#7A8699', '#3D8BFF'];
  map.addLayer({ id: 'route-line', type: 'line', source: 'route', layout, paint: { 'line-color': color, 'line-width': 8 } }, below);
}
map.on('load', addLayers);
watchColorScheme((style) => {
  map.setStyle(style);
  map.once('styledata', () => {
    addLayers();
    nav?.restyled();
  });
});

function routeData() {
  if (!state.route) return EMPTY;
  return { type: 'Feature', properties: { part: 'ahead' }, geometry: { type: 'LineString', coordinates: state.route.shape.map((p) => [p.lon, p.lat]) } };
}

const endMarkers = { from: null, to: null };
function placeMarker(which) {
  endMarkers[which]?.remove();
  endMarkers[which] = null;
  const p = state[which];
  if (!p) return;
  const el = document.createElement('div');
  el.className = which === 'to' ? 'place-pin' : 'start-pin';
  endMarkers[which] = new maplibregl.Marker({ element: el, anchor: which === 'to' ? 'bottom' : 'center' })
    .setLngLat([p.lon, p.lat])
    .addTo(map);
}

// ---- Search fields, with suggestions from Photon.

const fields = {
  from: { input: $('from'), list: $('from-list') },
  to: { input: $('to'), list: $('to-list') },
};

for (const [which, { input, list }] of Object.entries(fields)) {
  let timer = null, controller = null, results = [], active = -1;
  const close = () => {
    list.hidden = true;
    input.setAttribute('aria-expanded', 'false');
    active = -1;
  };
  const choose = (place) => {
    close();
    setEnd(which, place);
  };
  const render = () => {
    list.replaceChildren(
      ...results.map((r, i) => {
        const li = document.createElement('li');
        li.id = `${which}-option-${i}`;
        li.setAttribute('role', 'option');
        li.setAttribute('aria-selected', String(i === active));
        const name = document.createElement('strong');
        name.textContent = r.name;
        const detail = document.createElement('span');
        detail.textContent = r.detail;
        li.append(name, detail);
        // Before blur, so the click is not lost when the list closes.
        li.addEventListener('pointerdown', (e) => {
          e.preventDefault();
          choose(r);
        });
        return li;
      }),
    );
    list.hidden = results.length === 0;
    input.setAttribute('aria-expanded', String(!list.hidden));
    if (active >= 0) input.setAttribute('aria-activedescendant', `${which}-option-${active}`);
    else input.removeAttribute('aria-activedescendant');
  };
  input.addEventListener('input', () => {
    clearTimeout(timer);
    controller?.abort();
    state[which] = null;
    placeMarker(which);
    if (input.value.trim().length < 3) {
      results = [];
      render();
      return;
    }
    timer = setTimeout(async () => {
      controller = new AbortController();
      const c = map.getCenter();
      try {
        results = await searchPlaces(settings.geocoderUrl, input.value, { near: { lat: c.lat, lon: c.lng }, signal: controller.signal });
        active = -1;
        render();
        say(results.length ? '' : 'Aucun résultat');
      } catch (e) {
        if (e.name !== 'AbortError') say('Recherche indisponible pour le moment', true);
      }
    }, 250);
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (!results.length) return;
      e.preventDefault();
      active = (active + (e.key === 'ArrowDown' ? 1 : -1) + results.length) % results.length;
      render();
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (results.length) choose(results[Math.max(active, 0)]);
    } else if (e.key === 'Escape') {
      close();
    }
  });
  input.addEventListener('blur', close);
}

$('ends').addEventListener('submit', (e) => e.preventDefault());

$('swap').addEventListener('click', () => {
  [state.from, state.to] = [state.to, state.from];
  showEnds();
  update();
});

$('locate').addEventListener('click', () => {
  if (!navigator.geolocation) {
    say('Position indisponible dans ce navigateur', true);
    return;
  }
  say('Recherche de votre position…');
  navigator.geolocation.getCurrentPosition(
    (pos) => {
      say('');
      setEnd('from', { lat: pos.coords.latitude, lon: pos.coords.longitude, name: 'Ma position', here: true });
    },
    () => say('Position refusée ou introuvable : tapez une adresse de départ', true),
    { enableHighAccuracy: true, timeout: 10_000, maximumAge: 60_000 },
  );
});

function setEnd(which, place) {
  state[which] = place;
  showEnds();
  update();
  if (which === 'from' && !state.to) fields.to.input.focus();
}

function showEnds() {
  for (const which of ['from', 'to']) {
    const p = state[which];
    fields[which].input.value = p ? (p.name ?? `${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}`) : '';
    placeMarker(which);
  }
}

function say(text, error = false) {
  message.textContent = text;
  message.classList.toggle('error', error);
}

// ---- The route.

let routeController = null;
async function update() {
  routeController?.abort();
  state.route = null;
  drawRoute();
  // The place you are at stays out of the link: copying it shares the
  // destination only.
  const shared = { from: state.from?.here ? null : state.from, to: state.to };
  history.replaceState(null, '', routeLink('.', shared).replace(/^\.\/itineraire\.html/, location.pathname));
  if (!state.from || !state.to) {
    const only = state.from ?? state.to;
    if (only) map.easeTo({ center: [only.lon, only.lat], zoom: Math.max(map.getZoom(), 14) });
    return;
  }
  state.avoid = [];
  await computeRoute();
}

async function computeRoute() {
  routeController?.abort();
  const controller = (routeController = new AbortController());
  say('Calcul de l’itinéraire…');
  try {
    const ask = (avoid) => fetchRoute(settings.routingUrl, state.from, state.to, { avoid, signal: controller.signal });
    let route;
    try {
      route = await ask(state.avoid);
    } catch (e) {
      // No way around (a closure at the destination): the route through it,
      // flagged as such.
      if (!(e instanceof RoutingError) || state.avoid.length === 0) throw e;
      route = await ask([]);
    }
    if (controller.signal.aborted) return;
    state.route = route;
    say('');
    drawRoute();
    frame();
    listen(route);
  } catch (e) {
    if (e.name === 'AbortError') return;
    say(e instanceof RoutingError ? `Itinéraire impossible : ${e.message}` : 'Itinéraire impossible pour le moment', true);
  }
}

function frame() {
  const narrow = matchMedia('(max-width: 720px)').matches;
  const ui = narrow
    ? { top: $('ends').offsetHeight + 40, bottom: $('trip').offsetHeight + 40, left: 40, right: 40 }
    : { top: 60, bottom: 60, left: $('ends').offsetWidth + 70, right: 70 };
  map.fitBounds(bounds(state.route.shape), { padding: ui, maxZoom: 16, duration: 600 });
}

function drawRoute() {
  map.getSource('route')?.setData(routeData());
  const trip = $('trip');
  trip.hidden = !state.route;
  document.body.classList.toggle('has-trip', Boolean(state.route));
  if (!state.route) {
    drawAlerts([]);
    return;
  }
  const r = state.route;
  $('duration').textContent = durationText(r.timeS);
  const arrival = new Date(Date.now() + r.timeS * 1000).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  $('figures').textContent = `${distanceText(r.lengthM)} · arrivée ${arrival}`;
  $('open').href = appLink(state.to);
  $('steps-title').textContent = `Étapes (${r.maneuvers.length})`;
  $('steps').replaceChildren(
    ...r.maneuvers.map((m) => {
      const li = document.createElement('li');
      li.textContent = m.instruction;
      if (m.lengthM > 0) {
        const d = document.createElement('span');
        d.textContent = distanceText(m.lengthM);
        li.append(' ', d);
      }
      return li;
    }),
  );
  // Blocked places the route now goes around, and those it could not.
  const around = new Set(state.avoid.filter((b) => projectOnRoute(r, b).offsetM > 15).map((b) => b.id));
  const stuck = state.avoid.length - around.size;
  const avoided = $('avoided');
  avoided.hidden = state.avoid.length === 0;
  avoided.textContent = [
    around.size === 1 ? 'L’itinéraire contourne 1 route bloquée signalée.' : around.size > 1 ? `L’itinéraire contourne ${around.size} routes bloquées signalées.` : '',
    stuck > 0 ? 'Aucun détour trouvé pour une route bloquée sur le trajet.' : '',
  ].filter(Boolean).join(' ');
  drawAlerts(alertsOnRoute(r, store.visible()).filter(({ alert }) => !around.has(alert.id)));
}

// ---- Alerts on the way, from the relays.

const store = new AlertStore();
const relays = settings.relays;
const pool = new RelayPool(relays, {
  verify: verifyEvent,
  onEvent: (e) => {
    if (store.ingest(e)) scheduleAlerts();
  },
  onStatus: (s) => {
    const open = [...s.values()].filter((v) => v === 'open').length;
    $('relays').textContent =
      relays.length === 0 ? 'Alertes indisponibles : aucun relais configuré.' : open === 0 ? 'Connexion aux relais d’alertes…' : '';
  },
});
pool.onStatus(pool.status);
pool.connect();

let tooLong = false;
function listen(route) {
  const cells = cellsAlong(route.shape);
  tooLong = cells === null;
  if (cells) pool.subscribe(alertFilter(cells));
  onAlerts();
}

let pending = null;
function scheduleAlerts() {
  pending ??= setTimeout(() => {
    pending = null;
    onAlerts();
  }, 300);
}
setInterval(onAlerts, 30_000);

function onAlerts() {
  store.purge();
  if (nav) {
    nav.onAlerts();
    return;
  }
  if (!state.route) return;
  // A road reported closed or blocked on the way: around it, as the app
  // does. Alerts sit at the centre of their cell (~150 m), often beside
  // the road: the place to avoid is the nearest point of the route.
  const fresh = [];
  for (const a of store.visible()) {
    if (!BLOCKING.has(a.type) || state.avoid.some((b) => b.id === a.id)) continue;
    const p = projectOnRoute(state.route, a);
    if (p && p.offsetM <= 120) fresh.push({ id: a.id, lat: p.point.lat, lon: p.point.lon });
  }
  if (fresh.length) {
    state.avoid = [...state.avoid, ...fresh];
    computeRoute();
    return;
  }
  drawRoute();
}

const pins = [];
function drawAlerts(onRoute) {
  for (const m of pins.splice(0)) m.remove();
  const list = $('on-route');
  if (!state.route) {
    list.replaceChildren();
    return;
  }
  for (const { alert: a } of onRoute) {
    const el = document.createElement('div');
    el.className = 'pin small';
    el.style.setProperty('--pin', a.color);
    el.innerHTML = ICONS[a.type];
    el.title = a.label;
    pins.push(new maplibregl.Marker({ element: el }).setLngLat([a.lon, a.lat]).addTo(map));
  }
  const items = alertSummary(onRoute).map(({ type, color, text }) => {
    const li = document.createElement('li');
    li.style.setProperty('--pin', color);
    const icon = document.createElement('span');
    icon.className = 'icon';
    icon.innerHTML = ICONS[type];
    li.append(icon, text);
    return li;
  });
  if (items.length === 0) {
    const li = document.createElement('li');
    li.className = 'none';
    li.textContent = tooLong ? 'Trajet trop long pour lire les alertes' : 'Aucune alerte signalée sur le trajet';
    items.push(li);
  }
  list.replaceChildren(...items);
}

// ---- Guidance, in the browser.

let nav = null;
// ?simulation (or ?simulation=90 for 90 km/h) drives along the route instead
// of following the GPS, to try the guidance at a desk.
const simulation = new URLSearchParams(location.search).get('simulation');

$('go').addEventListener('click', () => {
  if (!state.route || nav) return;
  for (const m of pins.splice(0)) m.remove();
  endMarkers.from?.getElement().classList.add('faded');
  nav = new Navigation({
    map,
    settings,
    route: state.route,
    destination: state.to,
    store,
    avoid: state.avoid,
    simulateKmh: simulation === null ? null : Number(simulation) || 50,
    onRoute: (route) => {
      state.route = route;
      listen(route);
    },
    onEnd: () => {
      nav = null;
      endMarkers.from?.getElement().classList.remove('faded');
      drawRoute();
      frame();
    },
  });
  nav.start();
});

// ---- Sharing.

const copy = $('copy');
copy.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(location.href);
    copy.textContent = 'Lien copié';
  } catch {
    copy.textContent = 'Copiez l’adresse de la page';
  }
  setTimeout(() => (copy.textContent = 'Copier le lien'), 2500);
});

showEnds();
if (state.from && state.to) update();
else if (state.to) map.jumpTo({ center: [state.to.lon, state.to.lat], zoom: 14 });
// Straight to typing with a keyboard; on phones the keyboard waits for a tap.
if (matchMedia('(pointer: fine)').matches) (state.from ? fields.to : fields.from).input.focus({ preventScroll: true });
