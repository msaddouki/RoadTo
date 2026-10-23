// Address and place search with Photon (OSM), as the app does online
// (PhotonGeocoder in the core): same query, same labels.

/** Photon's answer as [{name, detail, lat, lon}] (parsePhoton in the core). */
export function parsePhoton(json) {
  const out = [];
  for (const f of json.features ?? []) {
    const coords = f.geometry?.coordinates;
    const p = f.properties ?? {};
    if (!coords || coords.length < 2) continue;
    const street = [p.housenumber, p.street].filter((s) => typeof s === 'string').join(' ');
    const name = p.name ?? (street || null);
    if (!name) continue;
    const detail = [p.name != null && street ? street : '', [p.postcode, p.city].filter((s) => typeof s === 'string').join(' ')]
      .filter(Boolean)
      .join(', ');
    out.push({ name, detail, lat: coords[1], lon: coords[0] });
  }
  return out;
}

/** [places] once each by their label, in order: OSM cuts a street into several ways (distinctPlaces in the core). */
export function distinctPlaces(places) {
  const seen = new Set();
  return places.filter((p) => {
    const label = p.detail ? `${p.name}, ${p.detail}` : p.name;
    if (seen.has(label)) return false;
    seen.add(label);
    return true;
  });
}

/** Places matching [query], nearest [near] first; [] under 3 characters. */
export async function searchPlaces(baseUrl, query, { near, limit = 6, signal, fetchImpl = globalThis.fetch } = {}) {
  const q = query.trim();
  if (q.length < 3) return [];
  const url = new URL('api', baseUrl);
  url.search = new URLSearchParams({
    q,
    // A few more: the same street often comes back once per way.
    limit: String(limit + 4),
    lang: 'fr',
    ...(near ? { lat: near.lat.toFixed(4), lon: near.lon.toFixed(4) } : {}),
  });
  const res = await fetchImpl(url, { signal });
  if (!res.ok) throw new Error(`Recherche indisponible (${res.status})`);
  return distinctPlaces(parsePhoton(await res.json())).slice(0, limit);
}
