-- Offline search index shipped in each region package (places.sqlite).
-- Read by packages/roadto_core (OfflineGeocoder). Bump schema_version in
-- `meta` on any incompatible change.

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE place (
  id          INTEGER PRIMARY KEY,
  -- 'address', 'street', 'place=<value>' or '<key>=<value>' for points of interest
  kind        TEXT    NOT NULL,
  -- NULL for unnamed driver places (fuel, parking...), found by category only
  name        TEXT,
  housenumber TEXT,
  street      TEXT,
  postcode    TEXT,
  city        TEXT,
  lat         REAL    NOT NULL,
  lon         REAL    NOT NULL,
  -- Ranking prior: cities above streets above points of interest above addresses.
  importance  INTEGER NOT NULL DEFAULT 0
);

-- Category search ("nearest fuel station") filters on kind, then on distance.
CREATE INDEX place_kind ON place (kind, lat, lon);

CREATE VIRTUAL TABLE place_fts USING fts5(
  name, street, housenumber, city,
  content = 'place',
  content_rowid = 'id',
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '1 2 3'
);
