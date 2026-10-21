import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { parsePhoton, searchPlaces } from '../src/geocoder.js';
import { cellsAlong, encode } from '../src/geohash.js';
import { parseRoute as parseRouteLink, routeLink } from '../src/links.js';
import {
  RoutingError, alertSummary, alertsOnRoute, decodePolyline, distanceText, durationText, fetchRoute, parseRoute,
  projectOnRoute, routeRequest,
} from '../src/routing.js';

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)));
// Reference values from the Dart core (packages/roadto_core/tool/web_fixtures.dart).
const ref = fixture('core.json').route;
const answer = fixture('valhalla-route.json');

test('polyline: the reference example, at precision 5', () => {
  const points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', 5);
  assert.deepEqual(points, [{ lat: 38.5, lon: -120.2 }, { lat: 40.7, lon: -120.95 }, { lat: 43.252, lon: -126.453 }]);
});

test('route: parsed as the app parses it', () => {
  const route = parseRoute(answer);
  assert.equal(route.lengthM, ref.lengthM);
  assert.equal(route.timeS, ref.timeS);
  assert.equal(route.shape.length, ref.points);
  assert.ok(Math.abs(route.cumulative.at(-1) - ref.shapeLengthM) < 1e-6);
  assert.deepEqual(route.maneuvers.map((m) => m.beginShapeIndex), ref.maneuvers);
  assert.match(route.maneuvers[1].instruction, /Place Bellecour/);
});

test('route: projections match the app', () => {
  const route = parseRoute(answer);
  for (const p of ref.probes) {
    const got = projectOnRoute(route, p);
    assert.ok(Math.abs(got.alongM - p.alongM) < 1e-6, `along ${p.lat},${p.lon}`);
    assert.ok(Math.abs(got.offsetM - p.offsetM) < 1e-6, `offset ${p.lat},${p.lon}`);
    if (p.offsetM < 1) assert.ok(Math.abs(got.point.lat - p.lat) < 1e-9 && Math.abs(got.point.lon - p.lon) < 1e-9);
  }
});

test('route: errors from the server', () => {
  assert.throws(() => parseRoute({ error: 'No path could be found', error_code: 442 }), RoutingError);
  assert.throws(() => parseRoute({}), /sans itinéraire/);
});

test('alerts on the route: near it, in order, summed up by type', () => {
  const route = parseRoute(answer);
  const [near, far] = ref.probes;
  const alerts = [
    { id: 'b', type: 'traffic', label: 'Bouchon', color: '#FF9F1C', lat: far.lat, lon: far.lon },
    { id: 'a', type: 'traffic', label: 'Bouchon', color: '#FF9F1C', lat: near.lat + 0.0005, lon: near.lon },
    { id: 'c', type: 'accident', label: 'Accident', color: '#FF5A5F', lat: 45.74, lon: 4.8 },
  ];
  const on = alertsOnRoute(route, alerts);
  assert.deepEqual(on.map((x) => x.alert.id), ['a', 'b']);
  assert.deepEqual(alertSummary(on).map((s) => s.text), ['Bouchon ×2']);
});

test('request: as the app sends it, blocked places as small squares', () => {
  const r = routeRequest({ lat: 45.75, lon: 4.83 }, { lat: 45.76, lon: 4.86 }, { avoid: [{ lat: 45.755, lon: 4.84 }] });
  assert.equal(r.costing, 'auto');
  assert.equal(r.language, 'fr-FR');
  assert.equal(r.exclude_polygons.length, 1);
  const ring = r.exclude_polygons[0];
  assert.deepEqual(ring[0], ring.at(-1));
  assert.ok(Math.abs((ring[2][1] - ring[0][1]) * 111320 - 40) < 0.01);
  assert.equal(routeRequest({ lat: 0, lon: 0 }, { lat: 1, lon: 1 }).exclude_polygons, undefined);
});

test('fetch: posts to /route, server errors become RoutingError', async () => {
  let sent;
  const ok = async (url, init) => {
    sent = { url: String(url), body: JSON.parse(init.body) };
    return { ok: true, status: 200, json: async () => answer };
  };
  const route = await fetchRoute('https://valhalla.example/', { lat: 45.7578, lon: 4.832 }, { lat: 45.7606, lon: 4.8594 }, { fetchImpl: ok });
  assert.equal(sent.url, 'https://valhalla.example/route');
  assert.equal(sent.body.locations.length, 2);
  assert.equal(route.lengthM, ref.lengthM);
  const refused = async () => ({ ok: false, status: 400, json: async () => ({ error: 'No path could be found', error_code: 442 }) });
  await assert.rejects(fetchRoute('https://valhalla.example/', { lat: 0, lon: 0 }, { lat: 1, lon: 1 }, { fetchImpl: refused }), /No path/);
  const down = async () => { throw new TypeError('network'); };
  await assert.rejects(fetchRoute('https://valhalla.example/', { lat: 0, lon: 0 }, { lat: 1, lon: 1 }, { fetchImpl: down }), RoutingError);
});

test('texts: distances as in the app, durations', () => {
  for (const [m, text] of Object.entries(ref.formatDistance)) assert.equal(distanceText(Number(m)), text);
  assert.equal(durationText(984.62), '16 min');
  assert.equal(durationText(20), '1 min');
  assert.equal(durationText(3900), '1 h 05');
});

test('cells along the route: every alert within the margin is asked for', () => {
  const route = parseRoute(answer);
  const cells = cellsAlong(route.shape);
  assert.ok(cells.length > 0 && cells.length <= 64);
  assert.ok(cells.every((c) => c.length === 5));
  for (const p of route.shape) assert.ok(cells.includes(encode(p.lat, p.lon, 5)));
  // Lyon to Marseille: 20 km cells. Lyon to Lisbon: too long.
  const line = (a, b, n = 200) => Array.from({ length: n + 1 }, (_, i) => ({ lat: a.lat + ((b.lat - a.lat) * i) / n, lon: a.lon + ((b.lon - a.lon) * i) / n }));
  const south = cellsAlong(line({ lat: 45.76, lon: 4.84 }, { lat: 43.3, lon: 5.37 }));
  assert.ok(south.length <= 64 && south.every((c) => c.length === 4));
  assert.equal(cellsAlong(line({ lat: 45.76, lon: 4.84 }, { lat: 38.72, lon: -9.14 })), null);
});

test('route links: both ends in the fragment, start optional', () => {
  const from = { lat: 45.7578, lon: 4.832, name: 'Place Bellecour' };
  const to = { lat: 45.7606, lon: 4.8594, name: 'Gare Part-Dieu' };
  const link = routeLink('https://roadto.example', { from, to });
  assert.equal(link, 'https://roadto.example/itineraire.html#de=45.75780,4.83200,Place%20Bellecour&vers=45.76060,4.85940,Gare%20Part-Dieu');
  assert.deepEqual(parseRouteLink(new URL(link).hash), { from, to });
  assert.deepEqual(parseRouteLink('#vers=45.76060,4.85940'), { from: null, to: { lat: 45.7606, lon: 4.8594, name: null } });
  assert.deepEqual(parseRouteLink(''), { from: null, to: null });
  assert.equal(routeLink('.', { to }), './itineraire.html#vers=45.76060,4.85940,Gare%20Part-Dieu');
});

test('search: Photon answers as the app labels them', async () => {
  const places = parsePhoton(fixture('photon.json'));
  assert.ok(places.length > 0);
  assert.equal(places[0].name, 'Gare Part-Dieu - Vivier Merle');
  assert.match(places[0].detail, /Lyon/);
  assert.deepEqual(parsePhoton({ features: [{ geometry: { coordinates: [4.8, 45.7] }, properties: { housenumber: '12', street: 'Rue de la République', postcode: '69002', city: 'Lyon' } }] }), [
    { name: '12 Rue de la République', detail: '69002 Lyon', lat: 45.7, lon: 4.8 },
  ]);
  let asked;
  const fetchImpl = async (url) => {
    asked = new URL(url);
    return { ok: true, json: async () => ({ features: [] }) };
  };
  assert.deepEqual(await searchPlaces('https://photon.example/', 'ga', { fetchImpl }), []);
  assert.equal(asked, undefined, 'no request under 3 characters');
  await searchPlaces('https://photon.example/', ' gare ', { near: { lat: 45.76, lon: 4.84 }, fetchImpl });
  assert.equal(asked.pathname, '/api');
  assert.equal(asked.searchParams.get('q'), 'gare');
  assert.equal(asked.searchParams.get('lat'), '45.7600');
});
