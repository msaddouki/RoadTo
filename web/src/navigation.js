// Guidance in the browser, like the app's trip screen: the next maneuver
// with its distance and the turn after it, the voice, speed and limit,
// alerts ahead, time left and arrival; off route, a new route from where the
// car is. The page must stay open with the screen on: browsers stop the
// location in the background, which is what the app is for.
import * as maplibregl from 'maplibre-gl';

import { EtaEstimator, LearnedPace, fastestWithJams, trafficDelays } from './eta.js';
import { GuidanceEngine, MANEUVER_ICONS, maneuverKind, maneuverLabel, thenOf } from './guidance.js';
import { ICONS } from './icons.js';
import {
  BLOCKING, alertsOnRoute, bearingAt, bearingDeg, distanceM, distanceText, durationText, fetchRoute, fetchRoutes, fetchSpeedLimits,
  isOverLimit, limitAt, pointAt, projectOnRoute, shapeLengthM,
} from './routing.js';

const NAV_SUFFIX = '-nav';
const PACE_KEY = 'roadto.pace';

/** What this visitor's trips taught ([LearnedPace]), kept in this browser only. */
export function loadPace() {
  try {
    return LearnedPace.fromJson(JSON.parse(localStorage.getItem(PACE_KEY) ?? '{}'));
  } catch {
    return new LearnedPace();
  }
}

export function savePace(pace) {
  try {
    if (pace.isEmpty && Object.keys(pace.bands).length === 0) localStorage.removeItem(PACE_KEY);
    else localStorage.setItem(PACE_KEY, JSON.stringify(pace.toJson()));
  } catch {
    // Private mode: learned again next time.
  }
}
const REROUTE_EVERY_MS = 15_000;
const AHEAD_M = 5000;

export class Navigation {
  #engine;
  #eta;
  #driven = {}; // this trip's driving per kind of road, across reroutes
  #jams = [];
  #state = null;
  #fix = null; // {lat, lon, headingDeg, speedMps}
  #watch = null;
  #sim = null;
  #wakeLock = null;
  #limits = [];
  #lastReroute = 0;
  #rerouting = false;
  #avoid = [];
  #follow = true;
  #puck;
  #pins = [];
  #ended = false;

  /**
   * @param map the page's map, with a 'route' source whose features have a
   *   'part' property ('done' or 'ahead')
   * @param route the route to follow (routing.js parseRoute)
   * @param destination {lat, lon, name}
   * @param store the page's AlertStore, kept up to date from the relays
   * @param avoid places the route already goes around ({id, lat, lon})
   * @param onRoute called with each new route (reroute), to read its alerts
   * @param onEnd called once guidance stops
   * @param simulateKmh drive along the route at this speed instead of GPS
   */
  constructor({ map, settings, route, destination, store, avoid = [], learned = new LearnedPace(), onRoute, onEnd, onLearned, simulateKmh = null }) {
    Object.assign(this, { map, settings, route, destination, store, learned, onRoute, onEnd, onLearned, simulateKmh });
    this.#avoid = [...avoid];
    this.#engine = new GuidanceEngine(route);
    this.#eta = new EtaEstimator(route, { learned });
    this.#jams = trafficDelays(route, store.visible());
    this.voice = new Voice();
    this.ui = new NavigationUi(this);
  }

  async start() {
    this.ui.show();
    this.#navLabels(true);
    const el = document.createElement('div');
    el.className = 'puck';
    el.innerHTML = '<svg viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="17" fill="#3D8BFF" stroke="#fff" stroke-width="4"/><path d="M20 9l8 19-8-4.5-8 4.5z" fill="#fff"/></svg>';
    this.#puck = new maplibregl.Marker({ element: el, rotationAlignment: 'map', pitchAlignment: 'map' });
    this.map.on('dragstart', this.#onDrag);
    document.addEventListener('visibilitychange', this.#onVisibility);
    await this.#keepAwake();
    this.#loadLimits(this.route);
    if (this.simulateKmh) this.#simulate();
    else this.#locate();
  }

  stop() {
    if (this.#ended) return;
    this.#ended = true;
    this.#learn();
    if (this.#watch !== null) navigator.geolocation.clearWatch(this.#watch);
    clearInterval(this.#sim);
    this.voice.stop();
    this.#wakeLock?.release().catch(() => {});
    this.#wakeLock = null;
    this.#puck?.remove();
    for (const m of this.#pins.splice(0)) m.remove();
    this.map.off('dragstart', this.#onDrag);
    document.removeEventListener('visibilitychange', this.#onVisibility);
    this.#navLabels(false);
    this.map.easeTo({ pitch: 0, bearing: 0, duration: 600 });
    this.ui.hide();
    this.onEnd?.();
  }

  recenter() {
    this.#follow = true;
    this.ui.following(true);
    this.#camera(true);
  }

  // ---- Positions.

  #locate() {
    if (!navigator.geolocation) {
      this.ui.message('Position indisponible dans ce navigateur');
      return;
    }
    this.ui.message('Recherche de votre position…');
    this.#watch = navigator.geolocation.watchPosition(
      (pos) => {
        const c = pos.coords;
        const here = { lat: c.latitude, lon: c.longitude, at: pos.timestamp };
        const prev = this.#fix;
        // Speed and heading from the device, else from the last fix.
        let speed = Number.isFinite(c.speed) && c.speed !== null ? c.speed : null;
        if (speed === null && prev?.at && pos.timestamp > prev.at) speed = distanceM(prev, here) / ((pos.timestamp - prev.at) / 1000);
        let heading = Number.isFinite(c.heading) && c.heading !== null && (speed ?? 0) > 1 ? c.heading : null;
        if (heading === null && prev && distanceM(prev, here) > 5) heading = bearingDeg(prev, here);
        this.#lastFixAt = Date.now();
        if (this.#positionTrouble) {
          this.#positionTrouble = false;
          this.ui.message('');
        }
        this.#onFix({ ...here, headingDeg: heading ?? prev?.headingDeg ?? null, speedMps: speed ?? 0, accuracyM: c.accuracy });
      },
      (e) => {
        // A late fix now and then is normal: said only when they stop.
        if (e.code !== 1 && Date.now() - this.#lastFixAt < 10_000) return;
        this.#positionTrouble = true;
        this.ui.message(e.code === 1 ? 'Localisation refusée : autorisez-la pour ce site' : 'Position introuvable pour le moment');
      },
      { enableHighAccuracy: true, maximumAge: 1000, timeout: 20_000 },
    );
  }

  /** Drives along the route, one fix a second (for trying the guidance at a desk). */
  #simulate() {
    let along = 0;
    const tick = () => {
      const route = this.route;
      if (this.#simRoute !== route) {
        // After a reroute: the new route starts where the car is.
        this.#simRoute = route;
        along = 0;
      }
      const speed = this.simulateKmh / 3.6;
      const p = pointAt(route, along);
      this.#onFix({ ...p, headingDeg: bearingAt(route, along), speedMps: speed, accuracyM: 5 });
      along = Math.min(along + speed, shapeLengthM(route));
    };
    this.#simRoute = this.route;
    tick();
    this.#sim = setInterval(tick, 1000);
  }

  #simRoute = null;
  #lastFixAt = 0;
  #positionTrouble = false;

  #onFix(fix) {
    if (this.#ended) return;
    this.#fix = fix;
    const g = (this.#state = this.#engine.update(fix, { speedMps: fix.speedMps }));
    this.#eta.observe(Date.now(), g);
    if (g.announcement) this.voice.say(g.announcement);
    this.#drawRouteProgress(g);
    this.#puck.setLngLat([fix.lon, fix.lat]).setRotation(fix.headingDeg ?? 0).addTo(this.map);
    this.#camera(false);
    this.ui.update(g, fix, this.#limitHere(g), this.#ahead(g), this.#remainingS(g));
    if (g.arrived) {
      this.ui.arrived(this.destination);
      clearInterval(this.#sim);
      setTimeout(() => this.stop(), 6000);
    } else if (g.offRoute) {
      this.#reroute('Recalcul de l’itinéraire');
    }
  }

  // ---- Route.

  async #reroute(reason, { force = false } = {}) {
    const fix = this.#fix;
    if (!fix || this.#rerouting || this.#ended) return;
    if (!force && Date.now() - this.#lastReroute < REROUTE_EVERY_MS) return;
    this.#rerouting = true;
    this.#lastReroute = Date.now();
    this.ui.message(reason);
    try {
      let route = await fetchRoute(this.settings.routingUrl, fix, this.destination, { avoid: this.#avoid, headingDeg: fix.headingDeg });
      // Jams on the new route: its alternatives too, as the app does.
      if (trafficDelays(route, this.store.visible()).length) {
        try {
          const all = await fetchRoutes(this.settings.routingUrl, fix, this.destination, { avoid: this.#avoid, headingDeg: fix.headingDeg });
          route = fastestWithJams(all, this.store.visible(), { learned: this.learned }).route;
        } catch {
          // The route found first.
        }
      }
      if (this.#ended) return;
      this.voice.say(reason);
      this.#setRoute(route);
      this.ui.message('');
    } catch {
      this.ui.message('Recalcul impossible pour le moment');
    } finally {
      this.#rerouting = false;
    }
  }

  #setRoute(route) {
    this.route = route;
    this.#bank();
    this.#eta = new EtaEstimator(route, { learned: this.learned, carry: this.#eta.live });
    this.#jams = trafficDelays(route, this.store.visible());
    this.#engine = new GuidanceEngine(route);
    this.#state = null;
    this.#limits = [];
    this.#loadLimits(route);
    this.onRoute?.(route);
    if (this.#fix) this.#onFix(this.#fix);
  }

  async #loadLimits(route) {
    try {
      const limits = await fetchSpeedLimits(this.settings.routingUrl, route);
      if (this.route === route) this.#limits = limits;
    } catch {
      // No limits for this route: no sign.
    }
  }

  #limitHere(g) {
    if (g.offRoute) return null;
    return limitAt(this.#limits, g.projection.alongM);
  }

  #drawRouteProgress(g) {
    const route = this.route;
    const along = g.offRoute ? 0 : g.projection.alongM;
    const done = [], ahead = [[g.projection.point.lon, g.projection.point.lat]];
    for (let i = 0; i < route.shape.length; i++) {
      const p = [route.shape[i].lon, route.shape[i].lat];
      if (route.cumulative[i] <= along) done.push(p);
      else ahead.push(p);
    }
    done.push(ahead[0]);
    const line = (coordinates, part) => ({ type: 'Feature', properties: { part }, geometry: { type: 'LineString', coordinates } });
    this.map.getSource('route')?.setData({
      type: 'FeatureCollection',
      features: [...(done.length > 1 ? [line(done, 'done')] : []), ...(ahead.length > 1 ? [line(ahead, 'ahead')] : [])],
    });
  }

  // ---- Time to arrival.

  #remainingS(g) {
    return this.#eta.remainingS(g, this.#jams);
  }

  /** The current route's driving, kept for the whole trip. */
  #bank() {
    for (const [band, s] of Object.entries(this.#eta.driven)) {
      const t = this.#driven[band] ?? { plannedS: 0, actualS: 0 };
      this.#driven[band] = { plannedS: t.plannedS + s.plannedS, actualS: t.actualS + s.actualS };
    }
    this.#eta.driven = {};
  }

  /** Once the trip ends, its pace joins what was learned; not a simulated one. */
  #learn() {
    this.#bank();
    const planned = Object.values(this.#driven).reduce((s, d) => s + d.plannedS, 0);
    if (this.simulateKmh || planned < 120) return;
    this.learned = this.learned.add(this.#driven);
    savePace(this.learned);
    this.onLearned?.(this.learned);
  }

  /** A jam reported ahead: a clearly faster way from here, if any. */
  async #considerDetour() {
    const fix = this.#fix, g = this.#state;
    if (!fix || !g || this.#rerouting || this.#ended) return;
    if (Date.now() - this.#lastReroute < REROUTE_EVERY_MS) return;
    this.#rerouting = true;
    this.#lastReroute = Date.now();
    const current = this.route;
    try {
      const all = await fetchRoutes(this.settings.routingUrl, fix, this.destination, { avoid: this.#avoid, headingDeg: fix.headingDeg });
      const best = fastestWithJams(all, this.store.visible(), { learned: this.learned });
      const time = new EtaEstimator(best.route, { learned: this.learned, carry: this.#eta.live }).totalS(best.delays);
      const left = this.#remainingS(g);
      if (this.#ended || this.route !== current || left - time < Math.max(120, left * 0.05)) return;
      this.voice.say('Bouchon signalé sur votre route : itinéraire plus rapide');
      this.#setRoute(best.route);
    } catch {
      // The same route, the jam in its time.
    } finally {
      this.#rerouting = false;
    }
  }

  // ---- Alerts.

  #ahead(g) {
    if (g.offRoute) return [];
    const along = g.projection.alongM;
    const list = alertsOnRoute(this.route, this.store.visible())
      .map(({ alert, distanceM: d }) => ({ alert, distanceM: d - along }))
      .filter((a) => a.distanceM >= -20 && a.distanceM <= AHEAD_M)
      .map((a) => ({ ...a, distanceM: Math.max(0, a.distanceM) }));
    this.#drawPins(list);
    return list;
  }

  /** New alerts from the relays: a road blocked ahead means another way. */
  onAlerts() {
    const g = this.#state;
    if (!g || this.#ended) return;
    const known = new Set(this.#jams.map((j) => j.alert.id));
    this.#jams = trafficDelays(this.route, this.store.visible());
    const along = g.offRoute ? 0 : g.projection.alongM;
    if (this.#jams.some((j) => !known.has(j.alert.id) && j.alongM > along)) this.#considerDetour();
    const ahead = this.#ahead(g);
    const fresh = ahead.filter(({ alert }) => BLOCKING.has(alert.type) && !this.#avoid.some((b) => b.id === alert.id));
    if (fresh.length) {
      for (const { alert } of fresh) {
        const p = projectPoint(this.route, alert);
        this.#avoid.push({ id: alert.id, lat: p.lat, lon: p.lon });
      }
      this.#reroute(`${fresh[0].alert.label} signalé sur votre route, recalcul`, { force: true });
      return;
    }
    this.ui.update(g, this.#fix, this.#limitHere(g), ahead, this.#remainingS(g));
  }

  #drawPins(list) {
    const ids = new Set(list.map((a) => a.alert.id));
    const kept = [];
    for (const m of this.#pins) {
      if (ids.has(m._roadtoId)) kept.push(m);
      else m.remove();
    }
    this.#pins = kept;
    for (const { alert: a } of list) {
      if (this.#pins.some((m) => m._roadtoId === a.id)) continue;
      const el = document.createElement('div');
      el.className = 'pin small';
      el.style.setProperty('--pin', a.color);
      el.innerHTML = ICONS[a.type];
      el.title = a.label;
      const m = new maplibregl.Marker({ element: el }).setLngLat([a.lon, a.lat]).addTo(this.map);
      m._roadtoId = a.id;
      this.#pins.push(m);
    }
  }

  // ---- Map.

  #camera(now) {
    const fix = this.#fix;
    if (!fix || !this.#follow) return;
    // Closer in town, further out on fast roads, as in the app.
    const kph = fix.speedMps * 3.6;
    const zoom = kph > 90 ? 15.6 : kph > 60 ? 16.3 : 17;
    const narrow = matchMedia('(max-width: 720px)').matches;
    this.map.easeTo({
      center: [fix.lon, fix.lat],
      bearing: fix.headingDeg ?? this.map.getBearing(),
      pitch: 50,
      zoom,
      // The car low on the screen, the road ahead above it.
      padding: { top: narrow ? 200 : 240, bottom: narrow ? 140 : 120, left: 0, right: 0 },
      duration: now ? 600 : 950,
      easing: (t) => t,
    });
  }

  #onDrag = () => {
    this.#follow = false;
    this.ui.following(false);
  };

  /** Street names in bubbles during a trip, as in the app (labelVisibility). */
  #navLabels(navigating) {
    const ids = new Set((this.map.getStyle()?.layers ?? []).map((l) => l.id));
    for (const id of ids) {
      let visible = null;
      if (id.endsWith(NAV_SUFFIX)) visible = navigating;
      else if (ids.has(`${id}${NAV_SUFFIX}`)) visible = !navigating;
      if (visible !== null) this.map.setLayoutProperty(id, 'visibility', visible ? 'visible' : 'none');
    }
  }

  /** After a change of style (day or night), the labels again. */
  restyled() {
    this.#navLabels(!this.#ended);
  }

  // ---- Screen.

  async #keepAwake() {
    try {
      this.#wakeLock = await navigator.wakeLock?.request('screen');
    } catch {
      this.#wakeLock = null;
    }
    this.ui.awake(Boolean(this.#wakeLock));
  }

  #onVisibility = () => {
    // The lock goes when the page is hidden; back on screen, again.
    if (document.visibilityState === 'visible' && !this.#ended) this.#keepAwake();
  };
}

/** Where an alert meets the route: the place to go around. */
const projectPoint = (route, p) => projectOnRoute(route, p).point;

/** The voice: the browser's French speech, on by default, remembered. */
class Voice {
  constructor() {
    this.on = read('roadto.voice') !== 'off';
  }

  set(on) {
    this.on = on;
    write('roadto.voice', on ? 'on' : 'off');
    if (!on) this.stop();
  }

  say(text) {
    const speech = globalThis.speechSynthesis;
    if (!this.on || !speech || !text) return;
    // The voice never stops the guidance: a browser without it stays silent.
    try {
      const u = new SpeechSynthesisUtterance(text);
      u.lang = 'fr-FR';
      const voice = speech.getVoices().find((v) => v.lang?.startsWith('fr'));
      if (voice) u.voice = voice;
      speech.cancel();
      speech.speak(u);
    } catch {
      // Silent.
    }
  }

  stop() {
    try {
      globalThis.speechSynthesis?.cancel();
    } catch {
      // Silent.
    }
  }
}

function read(key) {
  try { return localStorage.getItem(key); } catch { return null; }
}

function write(key, value) {
  try { localStorage.setItem(key, value); } catch { /* private mode */ }
}

/** The trip screen's panels (itineraire.html, #nav). */
class NavigationUi {
  constructor(nav) {
    this.nav = nav;
    const $ = (id) => document.getElementById(id);
    this.el = {
      root: $('nav'), arrow: $('nav-arrow'), dist: $('nav-dist'), street: $('nav-street'),
      then: $('nav-then'), thenArrow: $('nav-then-arrow'), thenStreet: $('nav-then-street'),
      alert: $('nav-alert'), limit: $('nav-limit'), speed: $('nav-speed'), now: $('nav-now'),
      eta: $('nav-eta'), left: $('nav-left'), message: $('nav-message'),
      stop: $('nav-stop'), voice: $('nav-voice'), recenter: $('nav-recenter'),
      arrived: $('nav-arrived'), arrivedName: $('nav-arrived-name'), awake: $('nav-awake'),
    };
    this.el.stop.onclick = () => nav.stop();
    this.el.recenter.onclick = () => nav.recenter();
    this.el.voice.onclick = () => {
      nav.voice.set(!nav.voice.on);
      this.#voice();
    };
    this.#voice();
  }

  show() {
    this.el.root.hidden = false;
    this.el.arrived.hidden = true;
    document.body.classList.add('navigating');
  }

  hide() {
    this.el.root.hidden = true;
    document.body.classList.remove('navigating');
  }

  #voice() {
    const on = this.nav.voice.on;
    this.el.voice.setAttribute('aria-pressed', String(on));
    this.el.voice.setAttribute('aria-label', on ? 'Couper la voix' : 'Activer la voix');
    this.el.voice.classList.toggle('off', !on);
  }

  message(text) {
    this.el.message.textContent = text;
    this.el.message.hidden = !text;
  }

  following(on) {
    this.el.recenter.hidden = on;
  }

  awake(on) {
    this.el.awake.hidden = on;
  }

  update(g, fix, limit, ahead, remainingS = g.remainingS) {
    const route = this.nav.route;
    const m = g.nextManeuver;
    if (fix && this.el.message.textContent === 'Recherche de votre position…') this.message('');
    this.el.arrow.innerHTML = MANEUVER_ICONS[g.offRoute ? 'off' : g.arrived ? 'arrive' : maneuverKind(m?.type)];
    this.el.dist.textContent = g.offRoute || g.arrived ? '' : distanceText(g.distanceToNextM);
    this.el.street.textContent = g.offRoute
      ? 'Hors itinéraire'
      : g.arrived ? (this.nav.destination.name ?? 'Arrivée') : m ? maneuverLabel(m) : 'Continuez';
    const then = g.offRoute ? null : thenOf(route, g);
    this.el.then.hidden = !then;
    if (then) {
      this.el.thenArrow.innerHTML = MANEUVER_ICONS[maneuverKind(then.type)];
      this.el.thenStreet.textContent = maneuverLabel(then);
    }

    const kph = Math.round((fix?.speedMps ?? 0) * 3.6);
    this.el.now.querySelector('strong').textContent = String(kph);
    const posted = limit?.kph ?? null;
    this.el.limit.hidden = posted === null;
    this.el.limit.textContent = posted ?? '';
    this.el.speed.classList.toggle('over', posted !== null && isOverLimit(kph, posted));

    const first = ahead[0];
    this.el.alert.hidden = !first;
    if (first) {
      const c = this.nav.store.stillThere(first.alert.id);
      this.el.alert.style.setProperty('--pin', first.alert.color);
      this.el.alert.innerHTML = `<span class="icon">${ICONS[first.alert.type]}</span>`;
      const text = document.createElement('span');
      const strong = document.createElement('strong');
      strong.textContent = `${first.alert.label} · ${distanceText(first.distanceM)}`;
      text.append(strong);
      const a = first.alert;
      const length = a.lengthM ? `sur ${distanceText(a.lengthM)}` : null;
      const line = a.sourceLabel
        ? [a.sourceLabel, length].filter(Boolean).join(' · ')
        : [length, c.count > 0 ? `Confirmé par ${c.count === 1 ? '1 conducteur' : `${c.count} conducteurs`}` : null].filter(Boolean).join(' · ');
      if (line) {
        const small = document.createElement('small');
        small.textContent = line;
        text.append(small);
      }
      this.el.alert.append(text);
    }

    const arrival = new Date(Date.now() + remainingS * 1000).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
    this.el.eta.textContent = arrival;
    this.el.left.textContent = g.arrived ? 'Arrivé' : `${durationText(remainingS)} · ${distanceText(g.remainingM)}`;
  }

  arrived(destination) {
    this.el.arrivedName.textContent = destination.name ?? 'Destination';
    this.el.arrived.hidden = false;
  }
}
