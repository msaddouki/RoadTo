// Time to arrival, as EtaEstimator in the core
// (packages/roadto_core/lib/src/routing/eta.dart): the engine's time per
// stretch, corrected by the driver's own pace (learned from their trips,
// and of the last minutes) and by the jams reported on the way. The tests
// compare it with the Dart one.
import { bearingAt, maneuverStartM, projectOnRoute, shapeLengthM } from './routing.js';

export const BANDS = ['town', 'road', 'fast'];
export const BAND_LABELS = { town: 'ville', road: 'route', fast: 'voie rapide' };

export const bandOfSpeed = (kph) => (kph < 40 ? 'town' : kph < 75 ? 'road' : 'fast');
const bandOf = (m) => bandOfSpeed(m.timeS <= 0 ? 0 : (m.lengthM / m.timeS) * 3.6);

/** Planned and actual driving time per kind of road ({town: {plannedS, actualS}}). */
export class LearnedPace {
  static MIN_PLANNED_S = 600;
  static HALF_WEIGHT_S = 1800;
  static KEPT_S = 4 * 3600;

  constructor(bands = {}) {
    this.bands = bands;
  }

  factor(band) {
    const s = this.bands[band];
    if (!s || s.plannedS < LearnedPace.MIN_PLANNED_S) return 1;
    const ratio = Math.min(Math.max(s.actualS / s.plannedS, 0.7), 1.5);
    const weight = s.plannedS / (s.plannedS + LearnedPace.HALF_WEIGHT_S);
    return 1 + (ratio - 1) * weight;
  }

  add(trip) {
    const out = { ...this.bands };
    for (const [band, v] of Object.entries(trip)) {
      let s = { plannedS: (out[band]?.plannedS ?? 0) + v.plannedS, actualS: (out[band]?.actualS ?? 0) + v.actualS };
      if (s.plannedS > LearnedPace.KEPT_S) {
        const k = LearnedPace.KEPT_S / s.plannedS;
        s = { plannedS: s.plannedS * k, actualS: s.actualS * k };
      }
      out[band] = s;
    }
    return new LearnedPace(out);
  }

  get isEmpty() {
    return BANDS.every((b) => (this.bands[b]?.plannedS ?? 0) < LearnedPace.MIN_PLANNED_S);
  }

  toJson() {
    return Object.fromEntries(Object.entries(this.bands).map(([b, s]) => [b, [s.plannedS, s.actualS]]));
  }

  static fromJson(json) {
    const bands = {};
    for (const b of BANDS) {
      const v = json?.[b];
      if (Array.isArray(v) && v.length === 2 && v.every((x) => typeof x === 'number')) bands[b] = { plannedS: v[0], actualS: v[1] };
    }
    return new LearnedPace(bands);
  }
}

function maneuverAt(route, alongM) {
  let found = null;
  for (let i = 0; i < route.maneuvers.length; i++) {
    if (maneuverStartM(route, i) <= alongM) found = i;
    else break;
  }
  return found;
}

function plannedKphAt(route, alongM) {
  const i = maneuverAt(route, alongM);
  if (i === null) return 30;
  const m = route.maneuvers[i];
  return m.timeS <= 0 ? 30 : (m.lengthM / m.timeS) * 3.6;
}

/**
 * Jams reported on the route ({alert, alongM, delayS}): about [jamM] crawled
 * at [jamKph] instead of the planned speed; reports heading the other way
 * are for the other side of the road.
 */
export function trafficDelays(route, alerts, { maxOffsetM = 120, jamM = 500, jamKph = 10 } = {}) {
  const out = [];
  for (const a of alerts) {
    if (a.type !== 'traffic') continue;
    const p = projectOnRoute(route, a);
    if (!p || p.offsetM > maxOffsetM) continue;
    if (a.bearing !== null && a.bearing !== undefined) {
      const diff = Math.abs((((bearingAt(route, p.alongM) - a.bearing + 540) % 360) + 360) % 360 - 180);
      if (diff > 60) continue;
    }
    const planned = plannedKphAt(route, p.alongM);
    const extra = jamM / (jamKph / 3.6) - jamM / (Math.max(planned, jamKph) / 3.6);
    out.push({ alert: a, alongM: p.alongM, delayS: Math.round(extra) });
  }
  return out.sort((x, y) => x.alongM - y.alongM);
}

export class EtaEstimator {
  static WINDOW_S = 300;
  static AHEAD_S = 600;

  #window = []; // [atMs, along, raw planned from start]
  #startedAlongM = null;
  #last = null; // {atMs, along}

  constructor(route, { learned = new LearnedPace(), carry = { ratio: 1, weight: 0 } } = {}) {
    this.route = route;
    this.learned = learned;
    this.live = carry;
    /** Driving per kind of road during this trip, to learn from. */
    this.driven = {};
    const n = route.maneuvers.length;
    this.start = route.maneuvers.map((_, i) => maneuverStartM(route, i));
    this.end = this.start.map((_, i) => (i + 1 < n ? this.start[i + 1] : shapeLengthM(route)));
    this.band = route.maneuvers.map(bandOf);
    this.rawTime = route.maneuvers.map((m) => m.timeS);
    this.time = this.rawTime.map((t, i) => t * learned.factor(this.band[i]));
  }

  plannedRemainingS(alongM, { corrected = true } = {}) {
    const times = corrected ? this.time : this.rawTime;
    if (times.length === 0) {
      return this.route.timeS * (1 - Math.min(Math.max(alongM / Math.max(shapeLengthM(this.route), 1), 0), 1));
    }
    let total = 0;
    for (let i = 0; i < times.length; i++) {
      const len = this.end[i] - this.start[i];
      if (alongM <= this.start[i]) total += times[i];
      else if (alongM < this.end[i] && len > 0) total += (times[i] * (this.end[i] - alongM)) / len;
    }
    return total;
  }

  /** A new position (guidance state [g]) at [atMs]. */
  observe(atMs, g) {
    if (g.offRoute || g.arrived) {
      this.#last = null;
      return;
    }
    const along = g.projection.alongM;
    this.#startedAlongM ??= along;
    if (along - this.#startedAlongM < 30) return;
    const raw = this.route.timeS === 0 ? 0 : this.plannedRemainingS(0, { corrected: false }) - this.plannedRemainingS(along, { corrected: false });

    const last = this.#last;
    if (last) {
      const dt = (atMs - last.atMs) / 1000;
      const dPlanned = this.plannedRemainingS(last.along, { corrected: false }) - this.plannedRemainingS(along, { corrected: false });
      if (dt > 0 && dt <= 60 && dPlanned >= 0) {
        const i = maneuverAt(this.route, (last.along + along) / 2) ?? 0;
        const band = this.band.length === 0 ? 'town' : this.band[i];
        const s = this.driven[band] ?? { plannedS: 0, actualS: 0 };
        this.driven[band] = { plannedS: s.plannedS + dPlanned, actualS: s.actualS + dt };
      }
    }
    this.#last = { atMs, along };

    this.#window.push([atMs, along, raw]);
    while (this.#window.length > 2 && (atMs - this.#window[1][0]) / 1000 >= EtaEstimator.WINDOW_S) this.#window.shift();
    const first = this.#window[0];
    const actual = (atMs - first[0]) / 1000;
    const planned = raw - first[2];
    if (planned >= 60 && actual > 0) {
      const i = maneuverAt(this.route, along) ?? 0;
      const f = this.band.length === 0 ? 1 : this.learned.factor(this.band[i]);
      const ratio = Math.min(Math.max(actual / (planned * f), 0.5), 2);
      const weight = Math.min(planned / EtaEstimator.WINDOW_S, 1) * 0.8;
      this.live = { ratio, weight };
    }
  }

  /** Seconds left from [g], the jams still ahead included. */
  remainingS(g, delays = []) {
    const along = g.offRoute ? (this.#last?.along ?? g.projection.alongM) : g.projection.alongM;
    const planned = this.plannedRemainingS(along);
    const near = Math.min(planned, EtaEstimator.AHEAD_S);
    const pace = 1 + (this.live.ratio - 1) * this.live.weight;
    let total = near * pace + (planned - near);
    for (const d of delays) if (d.alongM >= along - 20) total += d.delayS;
    return Math.round(total);
  }

  /** Seconds for the whole trip, before it starts. */
  totalS(delays = []) {
    let total = this.plannedRemainingS(0);
    for (const d of delays) total += d.delayS;
    return Math.round(total);
  }
}

/**
 * The route to take among [routes] (the engine's first): another only when
 * clearly faster with the jams counted (by [minGainS] and 5 %).
 * Returns {route, delays}.
 */
export function fastestWithJams(routes, alerts, { learned = new LearnedPace(), minGainS = 120 } = {}) {
  if (routes.length === 0) throw new Error('no route');
  const timed = routes.map((route) => ({ route, delays: trafficDelays(route, alerts) }));
  const time = (c) => new EtaEstimator(c.route, { learned }).totalS(c.delays);
  const first = timed[0];
  const firstTime = time(first);
  const margin = Math.max(minGainS, Math.round(firstTime * 0.05));
  let best = first, bestTime = firstTime;
  for (const c of timed.slice(1)) {
    const t = time(c);
    if (t <= firstTime - margin && t < bestTime) {
      best = c;
      bestTime = t;
    }
  }
  return best;
}
