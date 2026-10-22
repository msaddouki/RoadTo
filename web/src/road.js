// What the road shows along a route besides its limits, as in the app
// (packages/roadto_core/lib/src/routing/road_details.dart): traffic lights
// ("au feu, tournez à gauche"), streets off it ("prenez la 2e à droite")
// and the lanes to take before a turn. From the routing server, on the
// route's own shape: trace_attributes for the limits, lights and side
// streets, trace_route in OSRM form for the lanes.
import { decodePolyline, distanceM, encodePolyline, maneuverStartM, parseSpeedLimits, post, projectOnRoute } from './routing.js';

/** Nothing known yet (the details come a moment after the route). */
export const NO_DETAILS = Object.freeze({ limits: [], signalsM: [], sideRoads: [], lanes: [] });

/** trace_attributes request for the limits, lights and side streets. */
export function roadAttributesRequest(route) {
  return {
    encoded_polyline: encodePolyline(route.shape),
    costing: 'auto',
    shape_match: 'edge_walk',
    units: 'kilometers',
    filters: {
      attributes: [
        'edge.speed_limit', 'edge.begin_shape_index', 'edge.end_shape_index', 'shape', 'edge.traffic_signal', 'edge.end_heading',
        'node.intersecting_edge.begin_heading', 'node.intersecting_edge.driveability', 'node.intersecting_edge.use',
      ],
      action: 'include',
    },
  };
}

/** trace_route request on the route's shape, answered in OSRM form: the only one with the lanes. */
export function lanesRequest(route, { language = 'fr-FR' } = {}) {
  return {
    encoded_polyline: encodePolyline(route.shape),
    costing: 'auto',
    shape_match: 'edge_walk',
    units: 'kilometers',
    format: 'osrm',
    language,
  };
}

// Streets a driver counts: not car parks, service roads, cycle paths or crossings.
const STREETS = new Set(['road', 'living_street']);
// Lights less than this apart are one junction's; nodes less than this apart are one junction.
const SIGNAL_SPAN_M = 40;
const JUNCTION_SPAN_M = 30;

/** {limits, signalsM, sideRoads: [{alongM, left, right}], lanes: []} from a trace_attributes answer. */
export function parseRoadAttributes(json) {
  const limits = parseSpeedLimits(json);
  if (typeof json.shape !== 'string' || !Array.isArray(json.edges)) return { ...NO_DETAILS, limits };
  const shape = decodePolyline(json.shape);
  if (shape.length < 2) return { ...NO_DETAILS, limits };
  const cumulative = [0];
  for (let i = 1; i < shape.length; i++) cumulative.push(cumulative[i - 1] + distanceM(shape[i - 1], shape[i]));
  const at = (index) => cumulative[Math.min(Math.max(Math.trunc(index ?? 0), 0), shape.length - 1)];

  const signals = [], junctions = [];
  for (const e of json.edges) {
    const end = at(e.end_shape_index);
    if (e.traffic_signal === true) signals.push(end);
    const heading = e.end_heading;
    if (typeof heading !== 'number' || !e.end_node || typeof e.end_node !== 'object') continue;
    let left = false, right = false;
    for (const x of e.end_node.intersecting_edges ?? []) {
      const h = x?.begin_heading;
      if (!STREETS.has(x?.use) || (x.driveability !== 'forward' && x.driveability !== 'both') || typeof h !== 'number') continue;
      // From the way the car comes: negative to the left.
      const turn = ((h - heading + 540) % 360) - 180;
      if (turn <= -30 && turn >= -150) left = true;
      if (turn >= 30 && turn <= 150) right = true;
    }
    if (left || right) junctions.push({ alongM: end, left, right });
  }
  return { limits, signalsM: mergeSignals(signals), sideRoads: mergeJunctions(junctions), lanes: [] };
}

function mergeSignals(along) {
  const out = [];
  let first = null;
  for (const d of [...along].sort((a, b) => a - b)) {
    if (first !== null && d - first <= SIGNAL_SPAN_M) out[out.length - 1] = d;
    else {
      first = d;
      out.push(d);
    }
  }
  return out;
}

function mergeJunctions(junctions) {
  const out = [];
  for (const j of junctions) {
    const last = out.at(-1);
    if (last && j.alongM - last.alongM <= JUNCTION_SPAN_M) out[out.length - 1] = { alongM: last.alongM, left: last.left || j.left, right: last.right || j.right };
    else out.push(j);
  }
  return out;
}

/**
 * The lanes at each junction where only some of them lead the right way, from
 * a trace_route answer in OSRM form, placed on the route:
 * [{alongM, lanes: [{directions, valid, preferred, arrow}]}].
 */
export function parseLanes(json, route) {
  const out = [];
  for (const matching of json?.matchings ?? []) {
    for (const leg of matching?.legs ?? []) {
      for (const step of leg?.steps ?? []) {
        for (const x of step?.intersections ?? []) {
          if (!Array.isArray(x?.lanes) || !Array.isArray(x.location) || x.location.length < 2) continue;
          const lanes = x.lanes.filter((l) => l && typeof l === 'object').map((l) => {
            const first = l.indications?.[0] ?? 'straight';
            return {
              directions: (l.indications ?? []).map(String),
              valid: l.valid === true,
              preferred: l.active === true,
              arrow: String(l.valid === true ? (l.valid_indication ?? first) : first),
            };
          });
          if (lanes.length < 2 || lanes.every((l) => l.valid) || !lanes.some((l) => l.valid)) continue;
          const p = projectOnRoute(route, { lat: x.location[1], lon: x.location[0] });
          if (!p || p.offsetM > 20) continue;
          out.push({ alongM: p.alongM, lanes });
        }
      }
    }
  }
  return out.sort((a, b) => a.alongM - b.alongM);
}

const NUMBERS = { 2: 'deux', 3: 'trois', 4: 'quatre' };

/** Which lanes to take, in words ("les deux voies de gauche"); null when any will do or they are apart. */
export function laneHint(guide) {
  const lanes = guide.lanes;
  const valid = lanes.flatMap((l, i) => (l.valid ? [i] : []));
  if (lanes.length < 2 || valid.length === 0 || valid.length === lanes.length) return null;
  if (valid.at(-1) - valid[0] + 1 !== valid.length) return null;
  const side = valid[0] === 0 ? 'de gauche' : valid.at(-1) === lanes.length - 1 ? 'de droite' : 'du milieu';
  const n = valid.length;
  return n === 1 ? `la voie ${side}` : `les ${NUMBERS[n] ?? n} voies ${side}`;
}

const ORDINALS = { 2: ['2e', 'deuxième'], 3: ['3e', 'troisième'] };
// Turns told with a traffic light: left and right, slight, sharp, U-turns.
const TURNS = new Set([9, 10, 11, 12, 13, 14, 15, 16]);

function cue(label, lead, nth) {
  return {
    label,
    atLight: lead !== null,
    /** Valhalla's words for the turn, with the cue. */
    spoken(text) {
      if (lead !== null) return `${lead}, ${text ? text[0].toLowerCase() + text.slice(1) : text}`;
      return text.replace(/^Tournez à (gauche|droite)/, (_, side) => `Prenez la ${nth} à ${side}`);
    },
  };
}

/**
 * How maneuver [index] is told seen from [alongM]: the light at the turn,
 * counted from here ("Au 2e feu"), else the street on the side of the turn
 * ("2e à gauche"); up to the third. Null otherwise.
 */
export function turnCue(route, details, index, alongM) {
  if (index < 0 || index >= route.maneuvers.length) return null;
  const type = route.maneuvers[index].type;
  if (!TURNS.has(type)) return null;
  const turnM = maneuverStartM(route, index);

  const light = details.signalsM.findIndex((s) => s >= turnM - 50 && s <= turnM + 10);
  if (light >= 0) {
    const before = details.signalsM.slice(0, light).filter((s) => s > alongM).length;
    if (before === 0) return cue('Au feu', 'Au feu', null);
    const o = ORDINALS[before + 1];
    return o ? cue(`Au ${o[0]} feu`, `Au ${o[1]} feu`, null) : null;
  }

  // Plain left and right only: a slight turn is not "the 2nd".
  if (type !== 10 && type !== 15) return null;
  const left = type === 15;
  const before = details.sideRoads.filter(
    (j) => j.alongM > alongM + 5 && j.alongM < turnM - JUNCTION_SPAN_M - 5 && (left ? j.left : j.right),
  ).length;
  const o = ORDINALS[before + 1];
  return o ? cue(`${o[0]} à ${left ? 'gauche' : 'droite'}`, null, o[1]) : null;
}

/** The lanes painted at maneuver [index]'s junction, if any. */
export function lanesFor(route, details, index) {
  if (index < 0 || index >= route.maneuvers.length || route.maneuvers[index].isArrival) return null;
  const turnM = maneuverStartM(route, index);
  let best = null;
  for (const g of details.lanes) {
    const gap = Math.abs(g.alongM - turnM);
    if (gap <= 20 && (best === null || gap < Math.abs(best.alongM - turnM))) best = g;
  }
  return best;
}

/** Both requests at once; the lanes are a plus, the rest stands without them. */
export async function fetchRoadDetails(baseUrl, route, { signal, fetchImpl = globalThis.fetch } = {}) {
  const lanes = post(baseUrl, 'trace_route', lanesRequest(route), { signal, fetchImpl })
    .then((json) => parseLanes(json, route))
    .catch(() => []);
  const details = parseRoadAttributes(await post(baseUrl, 'trace_attributes', roadAttributesRequest(route), { signal, fetchImpl }));
  return { ...details, lanes: await lanes };
}
