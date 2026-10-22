// RoadTo alerts, as in packages/roadto_core/lib/src/alerts.dart: the event
// format (ADR 0005), the store and its reliability score, read only.
import { decode } from './geohash.js';

export const KIND_ALERT = 4550;
export const KIND_CONFIRMATION = 4551;

const MIN = 60;
export const TYPES = {
  accident: { label: 'Accident', ttl: 60 * MIN, color: '#FF5A5F' },
  traffic: { label: 'Bouchon', ttl: 30 * MIN, color: '#FF9F1C' },
  hazard: { label: 'Danger', ttl: 45 * MIN, color: '#FFE066' },
  closure: { label: 'Route fermée', ttl: 6 * 60 * MIN, color: '#B794F6' },
  roadworks: { label: 'Travaux', ttl: 12 * 60 * MIN, color: '#4CC9F0' },
  // Police stays off until the L130-11 channel exists (plan, J6).
};
const MAX_TTL = Math.max(...Object.values(TYPES).map((t) => t.ttl));

/** How bad a jam is, when the report says (tag `level`), as JamLevel in the core. */
export const JAM_LEVELS = {
  slow: { label: 'Ralenti', kph: 25 },
  jam: { label: 'Bouchon', kph: 10 },
  stopped: { label: 'À l’arrêt', kph: 5 },
};

/**
 * RoadTo's traffic robot (relay/traffic_bot), publishing jams from open
 * data: only its `src` tag is believed (TrafficSources in the core).
 */
export const TRAFFIC_SOURCE_KEYS = ['72207f9f4206976cdbbfe80fddb9fae6cd852459c1f8f1154a4e05d5ff6c235e'];
export const SOURCE_LABELS = { 'bison-fute': 'Bison Futé', grandlyon: 'Métropole de Lyon' };
const MAX_LENGTH_M = 20000;

/** Minimum proof of work (NIP-13), in leading zero bits of the id. */
export const POW = { [KIND_ALERT]: 12, [KIND_CONFIRMATION]: 8 };

export function leadingZeroBits(hex) {
  let bits = 0;
  for (const c of hex) {
    const v = Number.parseInt(c, 16);
    if (v === 0) { bits += 4; continue; }
    return bits + Math.clz32(v) - 28;
  }
  return bits;
}

/** Hidden below this score, as on the phone. */
export const VISIBILITY = 0.35;

const tag = (e, name) => e.tags.find((t) => t[0] === name)?.[1];
const tagValues = (e, name) => e.tags.filter((t) => t[0] === name).map((t) => t[1]);

/** The Nostr filter for alerts and answers in [cells], over their longest lifetime. */
export function alertFilter(cells, now = Date.now() / 1000) {
  return { kinds: [KIND_ALERT, KIND_CONFIRMATION], '#g': [...cells].sort(), since: Math.floor(now - MAX_TTL) };
}

/** A decoded alert, or null when the event is not a valid RoadTo alert. */
export function alertOf(e, trustedSources = TRAFFIC_SOURCE_KEYS) {
  if (e.kind !== KIND_ALERT) return null;
  const code = tag(e, 't');
  const type = TYPES[code];
  const expiresAt = Number.parseInt(tag(e, 'expiration') ?? '', 10);
  const cells = tagValues(e, 'g');
  if (!type || !Number.isFinite(expiresAt) || cells.length === 0) return null;
  const finest = cells.reduce((a, b) => (a.length >= b.length ? a : b));
  let center;
  try { center = decode(finest); } catch { return null; }
  const bearing = Number.parseInt(tag(e, 'bearing') ?? '', 10);
  const traffic = code === 'traffic';
  const level = traffic && JAM_LEVELS[tag(e, 'level')] ? tag(e, 'level') : null;
  const length = Number.parseInt(tag(e, 'length') ?? '', 10);
  const source = trustedSources.includes(e.pubkey) ? (tag(e, 'src') ?? null) : null;
  const prefix = source?.split('/')[0];
  return {
    id: e.id, author: e.pubkey, type: code, label: level ? JAM_LEVELS[level].label : type.label, color: type.color,
    geohash: finest, lat: center.lat, lon: center.lon,
    createdAt: e.created_at, expiresAt, bearing: Number.isFinite(bearing) ? bearing : null,
    level, lengthM: traffic && length > 0 && length <= MAX_LENGTH_M ? length : null,
    source, sourceLabel: source ? (SOURCE_LABELS[prefix] ?? prefix) : null,
  };
}

export class AlertStore {
  #alerts = new Map();
  /** alert id -> author -> {stillThere, at} */
  #answers = new Map();

  /** source ("bison-fute/MQA01.E1") -> its newest alert id. */
  #bySource = new Map();

  constructor({ threshold = VISIBILITY, trustedSources = TRAFFIC_SOURCE_KEYS } = {}) {
    this.threshold = threshold;
    this.trustedSources = trustedSources;
  }

  /** Adds an event; true when it changed what the store knows. */
  ingest(e, now = Date.now() / 1000) {
    const exp = Number.parseInt(tag(e, 'expiration') ?? '', 10);
    if (Number.isFinite(exp) && exp <= now) return false;
    if (leadingZeroBits(e.id ?? '') < (POW[e.kind] ?? Infinity)) return false;
    if (e.kind === KIND_ALERT) {
      const a = alertOf(e, this.trustedSources);
      if (!a || this.#alerts.has(a.id)) return false;
      // A sensor's newest alert replaces the previous one; an older one is late.
      if (a.source) {
        const previous = this.#alerts.get(this.#bySource.get(a.source));
        if (previous) {
          if (previous.createdAt >= a.createdAt) return false;
          this.#alerts.delete(previous.id);
          this.#answers.delete(previous.id);
        }
        this.#bySource.set(a.source, a.id);
      }
      this.#alerts.set(a.id, a);
      return true;
    }
    if (e.kind === KIND_CONFIRMATION) {
      const id = tag(e, 'e'), still = tag(e, 'still');
      if (!id || (still !== 'yes' && still !== 'no')) return false;
      // Authors cannot confirm their own alert.
      if (this.#alerts.get(id)?.author === e.pubkey) return false;
      const byAuthor = this.#answers.get(id) ?? new Map();
      const previous = byAuthor.get(e.pubkey);
      if (previous && previous.at >= e.created_at) return false;
      byAuthor.set(e.pubkey, { stillThere: still === 'yes', at: e.created_at });
      this.#answers.set(id, byAuthor);
      return true;
    }
    return false;
  }

  get(id) { return this.#alerts.get(id); }

  /** 0 to 1: fresh alerts score 1 and wear off; "yes" refreshes, "no" weighs more. */
  reliability(id, now = Date.now() / 1000) {
    const a = this.#alerts.get(id);
    if (!a) return 0;
    const halfLife = TYPES[a.type].ttl / 2;
    const weight = (at) => 0.5 ** ((now - at) / halfLife);
    let yes = 0, no = 0, lastYes = a.createdAt;
    for (const c of (this.#answers.get(id) ?? new Map()).values()) {
      if (c.stillThere) { yes += weight(c.at); if (c.at > lastYes) lastYes = c.at; } else { no += weight(c.at); }
    }
    const freshness = 0.4 + 0.6 * weight(lastYes);
    const support = (1.5 + yes) / (1.5 + yes + 2 * no);
    return freshness * support;
  }

  /** Drivers whose latest answer is "still there", and the latest time. */
  stillThere(id) {
    let count = 0, latest = null;
    for (const c of (this.#answers.get(id) ?? new Map()).values()) {
      if (!c.stillThere) continue;
      count++;
      if (latest === null || c.at > latest) latest = c.at;
    }
    return { count, latest };
  }

  /** Not expired and trusted enough, as the phone shows them. */
  visible(now = Date.now() / 1000) {
    return [...this.#alerts.values()].filter((a) => now < a.expiresAt && this.reliability(a.id, now) >= this.threshold);
  }

  purge(now = Date.now() / 1000) {
    for (const [id, a] of this.#alerts) {
      if (now >= a.expiresAt) { this.#alerts.delete(id); this.#answers.delete(id); }
    }
    for (const [source, id] of this.#bySource) if (!this.#alerts.has(id)) this.#bySource.delete(source);
  }
}

/** "à l'instant", "il y a 4 min", "il y a 2 h". */
export function ago(seconds) {
  const m = Math.floor(seconds / 60);
  if (m < 1) return 'à l’instant';
  if (m < 60) return `il y a ${m} min`;
  return `il y a ${Math.floor(m / 60)} h`;
}
