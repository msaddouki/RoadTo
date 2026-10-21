// Settings for this deployment, edited when the site is put online:
//   relays: the RoadTo relays to read (wss://), as set in the app;
//   contact: the address for joining the beta (shown on the home page);
//   routingUrl, geocoderUrl: Valhalla and Photon servers for the route page
//   (public ones when unset).
window.ROADTO_CONFIG = {
  relays: undefined, // e.g. ['wss://relay1.example.org', 'wss://relay2.example.org']
  contact: undefined, // e.g. 'beta@example.org'
};
