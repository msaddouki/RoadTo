import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { GuidanceEngine, navigationZoom } from '../src/guidance.js';
import {
  fetchRoadDetails, laneHint, lanesFor, lanesRequest, parseLanes, parseRoadAttributes, roadAttributesRequest, turnCue,
} from '../src/road.js';
import { maneuverStartM, parseRoute, shapeLengthM } from '../src/routing.js';

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)));
// The same answers read by the Dart core (packages/roadto_core/tool/web_fixtures.dart).
const ref = fixture('core.json').road;
const route = parseRoute(fixture('valhalla-partdieu.json'));
const details = { ...parseRoadAttributes(fixture('valhalla-partdieu-attributes.json')), lanes: parseLanes(fixture('valhalla-partdieu-lanes.json'), route) };
const close = (a, b) => Math.abs(a - b) < 1e-6;

test('road details: lights, side streets, lanes and limits read as the app reads them', () => {
  assert.equal(details.signalsM.length, ref.signalsM.length);
  details.signalsM.forEach((s, i) => assert.ok(close(s, ref.signalsM[i]), `light ${i}`));
  assert.equal(details.sideRoads.length, ref.sideRoads.length);
  details.sideRoads.forEach((j, i) => {
    const want = ref.sideRoads[i];
    assert.ok(close(j.alongM, want.alongM), `junction ${i}`);
    assert.equal(j.left, want.left);
    assert.equal(j.right, want.right);
  });
  assert.equal(details.lanes.length, ref.lanes.length);
  details.lanes.forEach((g, i) => {
    const want = ref.lanes[i];
    assert.ok(close(g.alongM, want.alongM));
    assert.deepEqual(g.lanes.map((l) => l.arrow), want.arrows);
    assert.deepEqual(g.lanes.map((l) => l.valid), want.valid);
    assert.deepEqual(g.lanes.map((l) => l.preferred), want.preferred);
    assert.equal(laneHint(g), want.hint);
  });
  assert.equal(details.limits.length, ref.limits.length);
  details.limits.forEach((s, i) => assert.equal(s.kph, ref.limits[i].kph));
});

test('turn cues: the light counted, else the street, in the same words', () => {
  ref.cues.forEach((want, k) => {
    const i = k + 1;
    const c = turnCue(route, details, i, want.from);
    assert.equal(c?.label ?? null, want.label, `maneuver ${i}`);
    assert.equal(c?.atLight ?? null, want.atLight, `maneuver ${i}`);
    const m = route.maneuvers[i];
    assert.equal(c ? c.spoken(m.verbalPre ?? m.instruction) : null, want.spoken, `maneuver ${i}`);
    const lanes = lanesFor(route, details, i);
    assert.equal(lanes ? laneHint(lanes) : null, want.lanes, `maneuver ${i}`);
  });
  assert.ok(ref.cues.some((c) => c.label === 'Au 3e feu'));
  assert.ok(ref.cues.some((c) => c.label === '2e à gauche'));
});

test('guidance with the road details: the same words, cues and lanes as the app', () => {
  const engine = new GuidanceEngine(route);
  engine.details = details;
  ref.drive.forEach((want, t) => {
    const g = engine.update({ lat: want.lat, lon: want.lon }, { speedMps: 30 / 3.6 });
    assert.equal(g.announcement, want.say, `fix ${t}`);
    assert.equal(g.cue?.label ?? null, want.cue, `fix ${t}: cue`);
    assert.ok(want.lanesM === null ? g.lanes === null : close(g.lanes.alongM, want.lanesM), `fix ${t}: lanes`);
    assert.equal(navigationZoom(30 / 3.6, g.distanceToNextM), want.zoom, `fix ${t}: zoom`);
  });
  const said = ref.drive.map((s) => s.say).filter(Boolean);
  assert.ok(said.includes('Dans 600 mètres, gardez la gauche pour prendre Pont Wilson. Utilisez les deux voies de gauche.'));
});

test('lanes named by their place across the road, as the app says them', () => {
  const guide = (valid) => ({ lanes: valid.map((v) => ({ valid: v })) });
  const cases = [
    [[false, true], 'la voie de droite'],
    [[false, true, false], 'la voie du milieu'],
    [[false, false, true], 'la première voie à droite'],
    [[false, true, false, false], 'la deuxième voie à gauche'],
    [[false, false, true, false], 'la deuxième voie à droite'],
    [[false, true, true, false], 'les deux voies du milieu'],
    [[true, true, true, false], 'les trois voies de gauche'],
    [[false, true, true, false, false], 'la deuxième ou la troisième voie à gauche'],
    [[true, false, true], null],
    [[true, true], null],
  ];
  for (const [valid, want] of cases) assert.equal(laneHint(guide(valid)), want, JSON.stringify(valid));
});

test('trip camera: closer in town and before a turn', () => {
  for (const kph of [0, 30, 50, 90, 130, 200]) assert.equal(navigationZoom(kph / 3.6), ref.zoom[kph], `${kph} km/h`);
  assert.equal(navigationZoom(40 / 3.6, 150), ref.zoom.turn);
});

test('requests on the route shape; the lanes lost, the rest kept', async () => {
  assert.ok(roadAttributesRequest(route).filters.attributes.includes('edge.traffic_signal'));
  assert.equal(lanesRequest(route).format, 'osrm');
  const asked = [];
  const fetchImpl = async (url) => {
    asked.push(new URL(url).pathname);
    if (url.pathname.endsWith('trace_route')) throw new Error('offline');
    return { ok: true, status: 200, json: async () => fixture('valhalla-partdieu-attributes.json') };
  };
  const got = await fetchRoadDetails('https://valhalla.example/', route, { fetchImpl });
  assert.deepEqual(asked.sort(), ['/trace_attributes', '/trace_route']);
  assert.equal(got.signalsM.length, ref.signalsM.length);
  assert.deepEqual(got.lanes, []);
  assert.ok(maneuverStartM(route, 3) < shapeLengthM(route));
});
