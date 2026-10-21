// A shared place: shown on the map, with a way to open it in RoadTo.
import * as maplibregl from 'maplibre-gl';

import { appLink, parsePlace } from '../links.js';
import { mapStyle, watchColorScheme } from '../site.js';

const place = parsePlace(location.hash);
const card = document.getElementById('card');
if (!place) {
  card.querySelector('h1').textContent = 'Lien incomplet';
  card.querySelector('.coords').textContent = 'Ce lien ne contient pas de lieu. Demandez à la personne de le partager à nouveau.';
  card.querySelector('.actions').hidden = true;
} else {
  card.querySelector('h1').textContent = place.name ?? 'Lieu partagé';
  card.querySelector('.coords').textContent = `${place.lat.toFixed(5)}, ${place.lon.toFixed(5)}`;
  document.getElementById('open').href = appLink(place);
  document.getElementById('alerts').href = `carte.html#${place.lat.toFixed(4)},${place.lon.toFixed(4)},13.0`;
  document.title = `${place.name ?? 'Lieu partagé'} · RoadTo`;
}

const map = new maplibregl.Map({
  container: 'map',
  style: await mapStyle(),
  center: place ? [place.lon, place.lat] : [4.84, 45.758],
  zoom: place ? 15 : 11,
  attributionControl: { compact: true },
});
watchColorScheme((style) => map.setStyle(style));
if (place) {
  const pin = document.createElement('div');
  pin.className = 'place-pin';
  new maplibregl.Marker({ element: pin, anchor: 'bottom' }).setLngLat([place.lon, place.lat]).addTo(map);
}

const copy = document.getElementById('copy');
copy.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(location.href);
    copy.textContent = 'Lien copié';
  } catch {
    copy.textContent = 'Copiez l’adresse de la page';
  }
});
