import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { GuidanceEngine, MANEUVER_ICONS, maneuverKind, maneuverLabel, thenOf } from '../src/guidance.js';
import {
  bearingAt, decodePolyline, encodePolyline, isOverLimit, limitAt, parseRoute, parseSpeedLimits, pointAt, routeRequest,
  speedLimitsRequest,
} from '../src/routing.js';

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)));
// The same drive through the Dart engine (packages/roadto_core/tool/web_fixtures.dart).
const ref = fixture('core.json').route;
const route = parseRoute(fixture('valhalla-route.json'));
const close = (a, b) => Math.abs(a - b) < 1e-6;

test('guidance: the same drive gives the same states and words as the app', () => {
  const engine = new GuidanceEngine(route);
  ref.drive.forEach((want, t) => {
    const g = engine.update({ lat: want.lat, lon: want.lon }, { speedMps: 50 / 3.6 });
    const at = `fix ${t}`;
    assert.ok(close(g.projection.alongM, want.alongM), `${at}: along ${g.projection.alongM} vs ${want.alongM}`);
    assert.equal(g.nextManeuverIndex, want.next, `${at}: next`);
    assert.ok(close(g.distanceToNextM, want.distanceToNextM), `${at}: distance to next`);
    assert.ok(close(g.remainingM, want.remainingM), `${at}: remaining`);
    assert.equal(g.remainingS, want.remainingS, `${at}: time left`);
    assert.equal(g.offRoute, want.offRoute, `${at}: off route`);
    assert.equal(g.arrived, want.arrived, `${at}: arrived`);
    assert.equal(g.announcement, want.say, `${at}: announcement`);
  });
  assert.ok(ref.drive.some((s) => s.offRoute), 'the drive leaves the route');
  assert.ok(ref.drive.at(-1).arrived, 'and arrives');
});

test('banner: label, the turn after, an icon for every maneuver', () => {
  assert.equal(maneuverLabel(route.maneuvers[1]), 'Place Bellecour');
  assert.equal(maneuverLabel(route.maneuvers.at(-1)), 'Arrivée');
  const engine = new GuidanceEngine(route);
  const g = engine.update(route.shape[0]);
  assert.equal(thenOf(route, g), route.maneuvers[2], 'Bellecour then Colonel Chambonnet, 40 m apart');
  for (const m of route.maneuvers) assert.ok(MANEUVER_ICONS[maneuverKind(m.type)], `type ${m.type}`);
});

test('route geometry: points and headings along it', () => {
  assert.deepEqual(pointAt(route, -5), route.shape[0]);
  assert.deepEqual(pointAt(route, 1e9), route.shape.at(-1));
  // "Conduisez vers le nord": north-north-east here.
  const b = bearingAt(route, 5);
  assert.ok(b > 0 && b < 45, `${b}`);
});

test('speed limits: parsed as the app does, merged, looked up', () => {
  const spans = parseSpeedLimits(ref.trace);
  assert.equal(spans.length, ref.limits.length);
  spans.forEach((s, i) => {
    assert.ok(close(s.startM, ref.limits[i].startM) && close(s.endM, ref.limits[i].endM));
    assert.equal(s.kph, ref.limits[i].kph);
  });
  assert.equal(limitAt(spans, 10).kph, 50);
  assert.equal(limitAt(spans, ref.limits[1].startM + 1).kph, null);
  assert.equal(limitAt(spans, 1e9), null);
  assert.equal(isOverLimit(55, 50), false);
  assert.equal(isOverLimit(56, 50), true);
  assert.equal(isOverLimit(136, 130), false);
  assert.equal(isOverLimit(137, 130), true);
});

test('polyline: encoding round trip, request on the route shape', () => {
  assert.equal(encodePolyline(route.shape), ref.trace.shape);
  assert.deepEqual(decodePolyline(encodePolyline(route.shape)), route.shape);
  const r = speedLimitsRequest(route);
  assert.equal(r.shape_match, 'edge_walk');
  assert.ok(r.filters.attributes.includes('edge.speed_limit'));
  const withHeading = routeRequest({ lat: 1, lon: 2 }, { lat: 3, lon: 4 }, { headingDeg: 87.6 });
  assert.equal(withHeading.locations[0].heading, 88);
  assert.equal(withHeading.locations[0].heading_tolerance, 45);
});
