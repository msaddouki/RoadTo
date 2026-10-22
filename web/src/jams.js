// Jammed stretches drawn on the map, as the app draws them: the road the
// traffic robot sends with its jams (tag `shape`), orange when slow, red
// when jammed, dark red when stopped, over the roads and the route, under
// the street names.
import { JAM_LEVELS } from './alerts.js';

const SOURCE = 'jams';
const EMPTY = { type: 'FeatureCollection', features: [] };

/** GeoJSON lines of the alerts that carry a stretch and a level. */
export function jamFeatures(alerts) {
  return {
    type: 'FeatureCollection',
    features: alerts
      .filter((a) => a.shape && a.level)
      .map((a) => ({
        type: 'Feature',
        properties: { color: JAM_LEVELS[a.level].color, level: a.level },
        geometry: { type: 'LineString', coordinates: a.shape.map((p) => [p.lon, p.lat]) },
      })),
  };
}

/** The layer, once per style (again after a change of style). */
export function addJamLayer(map) {
  if (map.getSource(SOURCE)) return;
  map.addSource(SOURCE, { type: 'geojson', data: EMPTY });
  const below = map.getLayer('roadto-labels') ? 'roadto-labels' : undefined;
  const layout = { 'line-cap': 'round', 'line-join': 'round' };
  // A dark edge first: the stretch stands out even on an orange motorway.
  map.addLayer(
    {
      id: `${SOURCE}-casing`,
      type: 'line',
      source: SOURCE,
      layout,
      paint: { 'line-color': '#2A0E05', 'line-width': ['interpolate', ['linear'], ['zoom'], 10, 5, 14, 9, 17, 13], 'line-opacity': 0.85 },
    },
    below,
  );
  map.addLayer(
    {
      id: SOURCE,
      type: 'line',
      source: SOURCE,
      layout,
      paint: { 'line-color': ['get', 'color'], 'line-width': ['interpolate', ['linear'], ['zoom'], 10, 3, 14, 6, 17, 9] },
    },
    below,
  );
}

export function drawJams(map, alerts) {
  map.getSource(SOURCE)?.setData(jamFeatures(alerts));
}
