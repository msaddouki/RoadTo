// The home page's phone: RoadTo's map with a trip on it, not interactive.
import maplibregl from 'maplibre-gl';

import { mapStyle } from '../site.js';

const map = new maplibregl.Map({
  container: 'hero-map',
  style: mapStyle(),
  center: [4.8445, 45.7545],
  zoom: 13.3,
  interactive: false,
  attributionControl: false,
});
map.on('load', async () => {
  const line = await (await fetch('demo-route.json')).json();
  map.addSource('route', { type: 'geojson', data: { type: 'Feature', geometry: { type: 'LineString', coordinates: line } } });
  const below = map.getLayer('roadto-labels') ? 'roadto-labels' : undefined;
  const layout = { 'line-cap': 'round', 'line-join': 'round' };
  map.addLayer({ id: 'route-casing', type: 'line', source: 'route', layout, paint: { 'line-color': '#0B3D91', 'line-width': 9 } }, below);
  map.addLayer({ id: 'route', type: 'line', source: 'route', layout, paint: { 'line-color': '#3D8BFF', 'line-width': 6 } }, below);
});
