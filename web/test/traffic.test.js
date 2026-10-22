import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { AlertStore, alertOf } from '../src/alerts.js';
import { trafficDelays } from '../src/eta.js';
import { parseRoute } from '../src/routing.js';
import { verifyEvent } from '../src/verify.js';

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)));
// Jams from the traffic robot, made by the Dart core (tool/web_fixtures.dart).
const ref = fixture('core.json').route.sensor;
const route = parseRoute(fixture('valhalla-route.json'));
const [older, newer] = ref.events;

test('a sensor jam: level, length, and its source from the robot only', () => {
  for (const e of ref.events) assert.ok(verifyEvent(e));
  const a = alertOf(newer, [ref.key]);
  assert.equal(a.level, 'stopped');
  assert.equal(a.label, 'À l’arrêt');
  assert.equal(a.lengthM, 1500);
  assert.equal(a.source, 'bison-fute/MY269.D1');
  assert.equal(a.sourceLabel, 'Bison Futé');
  const anyone = alertOf(newer, []);
  assert.equal(anyone.source, null);
  assert.equal(anyone.sourceLabel, null);
  assert.equal(anyone.lengthM, 1500);
});

test('the newest alert of a sensor replaces the previous one', () => {
  const now = newer.created_at + 1;
  const store = new AlertStore({ trustedSources: [ref.key] });
  assert.equal(store.ingest(older, now), true);
  assert.equal(store.ingest(newer, now), true);
  assert.deepEqual(store.visible(now).map((a) => a.id), [newer.id]);
  const again = new AlertStore({ trustedSources: [ref.key] });
  again.ingest(newer, now);
  assert.equal(again.ingest(older, now), false, 'late');
  // Not from the robot: both kept.
  const plain = new AlertStore({ trustedSources: [] });
  plain.ingest(older, now);
  plain.ingest(newer, now);
  assert.equal(plain.visible(now).length, 2);
});

test('its delay, from its level and length, as the app computes it', () => {
  const a = alertOf(newer, [ref.key]);
  assert.deepEqual(trafficDelays(route, [a]).map((d) => d.delayS), [ref.delayS]);
});
