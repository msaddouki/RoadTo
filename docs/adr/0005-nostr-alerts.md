# ADR 0005 — Alerts over Nostr, federated relays

- Status: accepted (POC); kinds are provisional and must be frozen before the beta
- Date: 2026-10-12

## Decision

Alerts and "still there?" answers are Nostr events (NIP-01) published to
several relays. Production relays will be strfry with a write-policy plugin
(J3). The repository ships a Dart dev relay (`relay/dev_relay`) that enforces
**the same policy** (`checkWritePolicy` in the core).

### Alert event (kind 4550, provisional)

| Tag | Value | Purpose |
| --- | --- | --- |
| `t` | `accident`, `traffic`, `hazard`, `closure`, `roadworks` (`police` disabled) | type |
| `g` | geohash at 4, 5, 6 and 7 characters | subscription by cell, position |
| `expiration` | Unix timestamp (NIP-40) | lifetime by type |
| `bearing` | heading rounded to 10° (optional) | direction of travel |
| `nonce` | NIP-13 | proof of work, 12 bits |

The content is empty: no free text. The published position is the geohash-7
cell (about 150 m × 150 m), never the exact position.

### "Still there?" answer (kind 4551, provisional)

Tags `e` (alert), `g` (same cells as the alert), `still` (`yes` or `no`),
`expiration` (the alert's), proof of work 8 bits.

### Lifetimes

Traffic jam 30 min, hazard 45 min, accident 60 min, roadworks 12 h, closed
road 6 h.

### Reliability

Computed on each phone (`AlertStore.reliability`): a new alert scores 1 and
wears off with time; each "yes" refreshes it, each "no" weighs more than a
"yes"; one answer per key; authors cannot confirm their own alert. Below 0.35
the alert is hidden.

### Privacy

- A throwaway key per trip signs alerts: two trips cannot be linked by key.
- The long-lived identity (key in Keystore or Keychain) does not sign alerts.
- The dev relay logs no IP address.

### Relay write policy

Allow-listed kinds, valid signature, minimum proof of work, mandatory expiry
bounded by type, valid and consistent geohashes (prefixes of each other, at
most 7 characters), known type, police type refused while the flag is off,
per-connection rate limit.
