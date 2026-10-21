import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { AlertStore, alertFilter, alertOf, ago, leadingZeroBits } from '../src/alerts.js';
import { cellsCovering, decode, encode } from '../src/geohash.js';
import { appLink, parsePlace, placeLink } from '../src/links.js';
import { verifyEvent } from '../src/verify.js';

// Reference values from the Dart core (packages/roadto_core/tool/web_fixtures.dart).
const ref = JSON.parse(readFileSync(new URL('./fixtures/core.json', import.meta.url)));

test('geohash: same cells as the app', () => {
  for (const { lat, lon, hash } of ref.geohash) {
    assert.equal(encode(lat, lon, 7), hash);
    const box = decode(hash);
    assert.ok(box.latMin <= lat && lat <= box.latMax && box.lonMin <= lon && lon <= box.lonMax);
  }
});

test('events from the app verify (id and Schnorr signature), tampered ones do not', () => {
  for (const e of ref.events) assert.ok(verifyEvent(e), e.id);
  const tampered = { ...ref.events[0], tags: [...ref.events[0].tags, ['t', 'police']] };
  assert.equal(verifyEvent(tampered), false);
});

test('store: same reliability, same visible alerts, own answers ignored', () => {
  const store = new AlertStore();
  for (const e of ref.events) store.ingest(e, e.created_at + 1);
  for (const [id, values] of Object.entries(ref.reliability)) {
    ref.nows.forEach((now, i) => assert.ok(Math.abs(store.reliability(id, now) - values[i]) < 1e-9, `${id} at ${now}`));
  }
  for (const [now, ids] of Object.entries(ref.visible)) {
    assert.deepEqual(store.visible(Number(now)).map((a) => a.id).sort(), ids);
  }
  for (const [id, count] of Object.entries(ref.stillThere)) assert.equal(store.stillThere(id).count, count);
});

test('alerts: decoded at their finest cell; expired and unmined events refused', () => {
  const a = alertOf(ref.events[0]);
  assert.equal(a.type, 'accident');
  assert.equal(a.geohash.length, 7);
  assert.equal(a.bearing, 90);
  const store = new AlertStore();
  assert.equal(store.ingest(ref.events[0], 4_000_000_000), false, 'expired');
  assert.equal(store.ingest({ ...ref.events[0], id: 'f'.repeat(64) }, ref.events[0].created_at), false, 'no proof of work');
  assert.equal(leadingZeroBits('000f'), 12);
  assert.equal(leadingZeroBits('0010'), 11);
});

test('filter: both kinds, the cells, over the longest lifetime', () => {
  const f = alertFilter(['u05kq', 'u05km'], 100_000);
  assert.deepEqual(f.kinds, [4550, 4551]);
  assert.deepEqual(f['#g'], ['u05km', 'u05kq']);
  assert.equal(f.since, 100_000 - 12 * 3600);
});

test('cells: 5 km cells for a city, 20 km for a region, none for a country', () => {
  const lyon = cellsCovering({ s: 45.70, w: 4.78, n: 45.80, e: 4.92 });
  assert.ok(lyon.length > 1 && lyon.length <= 64);
  assert.ok(lyon.every((c) => c.length === 5));
  assert.ok(lyon.includes(encode(45.7578, 4.832, 5)));
  const region = cellsCovering({ s: 45.0, w: 4.0, n: 46.5, e: 5.6 });
  assert.ok(region.length <= 64 && region.every((c) => c.length === 4));
  assert.equal(cellsCovering({ s: 42, w: -5, n: 51, e: 8 }), null);
});

test('place links: the place stays in the fragment, round trip', () => {
  const link = placeLink('https://roadto.example/', { lat: 45.7578, lon: 4.832, name: 'Place Bellecour' });
  assert.equal(link, 'https://roadto.example/lieu.html#45.75780,4.83200,Place%20Bellecour');
  assert.deepEqual(parsePlace(new URL(link).hash), { lat: 45.7578, lon: 4.832, name: 'Place Bellecour' });
  assert.equal(parsePlace('#91,0'), null);
  assert.equal(parsePlace('#hello'), null);
  assert.equal(appLink({ lat: 45.7578, lon: 4.832, name: 'Gare' }), 'roadto://place?lat=45.75780&lon=4.83200&name=Gare');
});

test('ago', () => {
  assert.equal(ago(30), 'à l’instant');
  assert.equal(ago(4 * 60), 'il y a 4 min');
  assert.equal(ago(2 * 3600 + 5), 'il y a 2 h');
});
