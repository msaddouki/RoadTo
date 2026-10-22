import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { EtaEstimator, LearnedPace, bandOfSpeed, fastestWithJams, trafficDelays } from '../src/eta.js';
import { GuidanceEngine } from '../src/guidance.js';
import { parseRoute, parseRoutes } from '../src/routing.js';

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)));
// The same estimates from the Dart core (packages/roadto_core/tool/web_fixtures.dart).
const ref = fixture('core.json').route.eta;
const route = parseRoute(fixture('valhalla-route.json'));
const close = (a, b, eps = 1e-6) => Math.abs(a - b) < eps;
const jam = (p, id = 'jam') => ({ id, type: 'traffic', lat: p.lat, lon: p.lon, bearing: null });

test('learned pace: same factors as the app, saved and read back', () => {
  const learned = LearnedPace.fromJson(ref.learned);
  for (const [band, f] of Object.entries(ref.factors)) assert.ok(close(learned.factor(band), f), band);
  assert.deepEqual(LearnedPace.fromJson(JSON.parse(JSON.stringify(learned.toJson()))).bands, learned.bands);
  assert.equal(new LearnedPace().factor('town'), 1);
  assert.equal(new LearnedPace().isEmpty, true);
  assert.deepEqual(LearnedPace.fromJson({ town: 'garbage' }).bands, {});
  assert.equal(bandOfSpeed(25), 'town');
  assert.equal(bandOfSpeed(110), 'fast');
});

test('estimator: same plan, same live pace, same time left at every fix as the app', () => {
  const learned = LearnedPace.fromJson(ref.learned);
  const delays = trafficDelays(route, [jam(ref.jam)]);
  assert.deepEqual(delays.map((d) => d.delayS), ref.delays);
  const eta = new EtaEstimator(route, { learned });
  assert.ok(close(eta.plannedRemainingS(0), ref.plannedS));
  assert.equal(eta.totalS(delays), ref.totalS);
  const engine = new GuidanceEngine(route);
  ref.drive.forEach((want, i) => {
    const g = engine.update({ lat: want.lat, lon: want.lon }, { speedMps: 10 });
    eta.observe(want.atMs, g);
    assert.equal(eta.remainingS(g, delays), want.remainingS, `fix ${i}`);
    assert.ok(close(eta.live.ratio, want.ratio) && close(eta.live.weight, want.weight), `pace at fix ${i}`);
  });
  for (const [band, [planned, actual]] of Object.entries(ref.driven)) {
    assert.ok(close(eta.driven[band].plannedS, planned, 1e-3) && close(eta.driven[band].actualS, actual, 1e-3), band);
  }
});

test('jams: same direction only, traffic only', () => {
  const a = { ...jam(ref.jam), bearing: null };
  assert.equal(trafficDelays(route, [{ ...a, type: 'roadworks' }]).length, 0);
  const along = trafficDelays(route, [a])[0];
  assert.ok(along.delayS > 0);
});

test('alternatives: the same choice as the app', () => {
  const routes = parseRoutes(fixture('valhalla-alternates.json'));
  assert.equal(routes.length, 3);
  assert.equal(routes.indexOf(fastestWithJams(routes, []).route), ref.alternates.noJams);
  assert.equal(routes.indexOf(fastestWithJams(routes, [], { minGainS: 180 }).route), ref.alternates.noJams3min);
  const jams = ref.alternates.jams.map((p, i) => jam(p, `j${i}`));
  assert.equal(routes.indexOf(fastestWithJams(routes, jams).route), ref.alternates.withJams);
});
