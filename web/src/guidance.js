// Turn-by-turn guidance, as GuidanceEngine in the core
// (packages/roadto_core/lib/src/routing/guidance.dart): next maneuver,
// distances, time left, off route, arrival and what to say when. The tests
// replay a drive against the Dart engine's own answers.
import { NO_DETAILS, laneHint, lanesFor, turnCue } from './road.js';
import { maneuverStartM, projectOnRoute, shapeLengthM } from './routing.js';

/** Lanes are shown from this far before the turn. */
export const LANES_WITHIN_M = 1500;

export class GuidanceEngine {
  #segmentHint = 0;
  #lastAlongM = null;
  #offRouteCount = 0;
  #started = false;
  #announced = new Set();

  constructor(route, { offRouteThresholdM = 40, offRouteConfirmations = 3, arrivalThresholdM = 25 } = {}) {
    this.route = route;
    this.offRouteThresholdM = offRouteThresholdM;
    this.offRouteConfirmations = offRouteConfirmations;
    this.arrivalThresholdM = arrivalThresholdM;
    /** Lights, side streets and lanes of the route, once the server sent them (road.js). */
    this.details = NO_DETAILS;
  }

  /**
   * The state after a new position ({lat, lon}):
   * {projection, nextManeuver, nextManeuverIndex, distanceToNextM,
   *  remainingM, remainingS, offRoute, arrived, announcement, cue, lanes}.
   */
  update(position, { speedMps = 0 } = {}) {
    const route = this.route;
    // First where the car can be since the last position (a stretch further
    // on could be closer under an interchange and skip maneuvers), then near
    // the last known segment, then over the rest of the route. Never back.
    const last = this.#lastAlongM;
    const behind = last === null ? 0 : this.#segmentAt(last - 15);
    let proj = null;
    if (last !== null) {
      const reachM = Math.max(80, speedMps * 5);
      const near = projectOnRoute(route, position, { from: behind, to: this.#segmentAt(last + reachM) + 1 });
      if (near && near.offsetM <= this.offRouteThresholdM) proj = near;
    }
    proj ??= projectOnRoute(route, position, { from: Math.max(this.#segmentHint - 2, behind), to: this.#segmentHint + 60 });
    if (proj === null || proj.offsetM > this.offRouteThresholdM) {
      const global = projectOnRoute(route, position, { from: behind });
      if (global && (proj === null || global.offsetM < proj.offsetM)) proj = global;
    }
    if (proj === null) throw new Error('Itinéraire vide');

    const off = proj.offsetM > this.offRouteThresholdM;
    this.#offRouteCount = off ? this.#offRouteCount + 1 : 0;
    if (!off) {
      this.#segmentHint = proj.segmentIndex;
      this.#lastAlongM = proj.alongM;
    }

    const total = shapeLengthM(route);
    const along = proj.alongM;
    const remainingM = Math.max(0, total - along);
    const arrived = remainingM <= this.arrivalThresholdM && !off;

    let nextIdx = null;
    for (let i = 0; i < route.maneuvers.length; i++) {
      if (maneuverStartM(route, i) > along + 3) {
        nextIdx = i;
        break;
      }
    }
    const next = nextIdx === null ? null : route.maneuvers[nextIdx];
    const distanceToNextM = nextIdx === null ? remainingM : maneuverStartM(route, nextIdx) - along;
    const cue = nextIdx === null || off ? null : turnCue(route, this.details, nextIdx, along);
    const lanes = nextIdx === null || off || distanceToNextM > LANES_WITHIN_M ? null : lanesFor(route, this.details, nextIdx);

    // Time left: in proportion to the distance, at the routing engine's speeds.
    const ratio = total === 0 ? 0 : remainingM / total;
    const remainingS = Math.round(route.timeS * ratio);

    let say = null;
    if (!this.#started) {
      this.#started = true;
      const first = route.maneuvers[0] ?? null;
      say = first ? (first.verbalPre ?? first.instruction) : null;
      this.#announced.add('0:pre');
    } else if (arrived) {
      if (this.#add('arrived')) {
        const end = route.maneuvers.at(-1);
        say = end?.isArrival ? (end.verbalPre ?? end.instruction) : 'Vous êtes arrivé.';
      }
    } else if (next && !off) {
      // Close announcement: ~8 s before, at least 60 m, at most 250 m.
      const nearM = Math.min(Math.max(speedMps * 8, 60), 250);
      if (distanceToNextM <= nearM) {
        if (!next.isArrival && this.#add(`${nextIdx}:pre`)) {
          const text = next.verbalPre ?? next.instruction;
          say = this.#withLanes(cue ? cue.spoken(text) : text, nextIdx, lanes);
        }
      } else if (distanceToNextM <= 600 && distanceToNextM > nearM + 150) {
        if (this.#add(`${nextIdx}:alert`)) {
          const text = next.verbalAlert ?? (next.isArrival ? 'vous arrivez à destination' : next.instruction);
          say = this.#withLanes(`Dans ${roundDistance(distanceToNextM)}, ${lowerFirst(cue ? cue.spoken(text) : text)}`, nextIdx, lanes);
        }
      }
    }

    return {
      projection: proj,
      nextManeuver: next,
      nextManeuverIndex: nextIdx,
      distanceToNextM,
      remainingM,
      remainingS,
      offRoute: this.#offRouteCount >= this.offRouteConfirmations,
      arrived,
      announcement: say,
      cue,
      lanes,
    };
  }

  /** [text] and, the first time this maneuver is announced with them known, the lanes to take. */
  #withLanes(text, index, lanes) {
    const hint = lanes ? laneHint(lanes) : null;
    if (hint === null || !this.#add(`${index}:lanes`)) return text;
    const t = text.trimEnd();
    return `${t.endsWith('.') ? t : `${t}.`} Utilisez ${hint}.`;
  }

  #add(key) {
    if (this.#announced.has(key)) return false;
    this.#announced.add(key);
    return true;
  }

  #segmentAt(alongM) {
    const c = this.route.cumulative;
    if (c.length < 2 || alongM <= 0) return 0;
    let lo = 0, hi = c.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (c[mid] <= alongM) lo = mid; else hi = mid;
    }
    return lo;
  }
}

/**
 * The trip camera's zoom (navigationZoom in the core): close in town,
 * further out the faster the car, closer again just before a turn.
 */
export function navigationZoom(speedMps, distanceToTurnM = null) {
  const kph = speedMps * 3.6;
  let zoom = 18 - (Math.min(Math.max(kph - 30, 0), 80) / 80) * 1.8;
  if (distanceToTurnM !== null && distanceToTurnM < 200 && kph < 60) zoom = Math.max(zoom, 18.3);
  return Math.round(zoom * 10) / 10;
}

const lowerFirst = (s) => (s ? s[0].toLowerCase() + s.slice(1) : s);

function roundDistance(m) {
  if (m >= 1000) return `${(m / 1000).toFixed(1).replace('.', ',')} kilomètres`;
  const step = m >= 200 ? 100 : 50;
  return `${Math.round(m / step) * step} mètres`;
}

/** The maneuver after the next one, when it comes within [withinM] (ManeuverBanner.thenOf). */
export function thenOf(route, state, withinM = 800) {
  const i = state.nextManeuverIndex;
  if (i === null || i + 1 >= route.maneuvers.length) return null;
  const gap = maneuverStartM(route, i + 1) - maneuverStartM(route, i);
  return gap <= withinM ? route.maneuvers[i + 1] : null;
}

/** "Arrivée", the street, or the instruction: the banner's big text. */
export const maneuverLabel = (m) => (m.isArrival ? 'Arrivée' : (m.streetNames[0] ?? m.instruction));

/** The icon of a Valhalla maneuver type, as maneuverIcon in the app. */
export function maneuverKind(type) {
  switch (type) {
    case 1: case 2: case 3: return 'start';
    case 4: case 5: case 6: return 'arrive';
    case 9: case 23: return 'slight-right';
    case 10: case 18: case 20: return 'right';
    case 11: return 'sharp-right';
    case 12: return 'uturn-right';
    case 13: return 'uturn-left';
    case 14: return 'sharp-left';
    case 15: case 19: case 21: return 'left';
    case 16: case 24: return 'slight-left';
    case 25: return 'merge';
    case 26: case 27: return 'roundabout';
    case 28: case 29: return 'ferry';
    default: return 'straight';
  }
}

const arrow = (body) =>
  `<svg viewBox="0 0 48 48" width="100%" height="100%" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

/** White arrows for the banner, drawn here (no icon font from a third party). */
export const MANEUVER_ICONS = {
  straight: arrow('<path d="M24 42V8"/><path d="M13 19L24 8l11 11"/>'),
  start: arrow('<path d="M24 6l12 34-12-7-12 7z" fill="currentColor" stroke-width="3"/>'),
  arrive: arrow('<path d="M14 42V7"/><path d="M14 9h22l-5 7 5 7H14" fill="currentColor" stroke-width="3"/>'),
  right: arrow('<path d="M16 42V24a6 6 0 0 1 6-6h18"/><path d="M31 9l9 9-9 9"/>'),
  left: arrow('<path d="M32 42V24a6 6 0 0 0-6-6H8"/><path d="M17 9l-9 9 9 9"/>'),
  'slight-right': arrow('<path d="M18 42V26L34 10"/><path d="M22 10h12v12"/>'),
  'slight-left': arrow('<path d="M30 42V26L14 10"/><path d="M26 10H14v12"/>'),
  'sharp-right': arrow('<path d="M14 6v22l20 14"/><path d="M34 30v12H22"/>'),
  'sharp-left': arrow('<path d="M34 6v22L14 42"/><path d="M14 30v12h12"/>'),
  'uturn-right': arrow('<path d="M12 42V20a10 10 0 0 1 20 0v14"/><path d="M24 27l8 8 8-8"/>'),
  'uturn-left': arrow('<path d="M36 42V20a10 10 0 0 0-20 0v14"/><path d="M8 27l8 8 8-8"/>'),
  merge: arrow('<path d="M14 42c0-12 10-14 10-24V8"/><path d="M34 42c0-8-6-12-10-16"/><path d="M15 17l9-9 9 9"/>'),
  roundabout: arrow('<circle cx="24" cy="22" r="8"/><path d="M24 42V30"/><path d="M32 22h10"/><path d="M37 16l6 6-6 6"/>'),
  // Off the route: a pin with a cross.
  off: arrow('<path d="M24 43s14-13 14-24a14 14 0 0 0-28 0c0 11 14 24 14 24z"/><path d="M19 14l10 10M29 14L19 24"/>'),
  ferry: arrow('<path d="M6 32l4 8h28l4-8z"/><path d="M14 32V20h20v12"/><path d="M24 20V10"/>'),
};
