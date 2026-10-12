# ADR 0007 — Identity: a key from a recovery phrase, kept on the phone

- Status: accepted (POC)
- Date: 2026-10-12

## Decision

- The user's identity is a secp256k1 key derived from a **BIP-39 recovery
  phrase** following **NIP-06** (`m/44'/1237'/0'/0/0`). The same words restore
  the same identity on another phone, in RoadTo or in any NIP-06 Nostr client.
- New identities get a 12-word phrase from the **English** BIP-39 list, the
  one other Nostr clients expect; 24-word phrases are accepted on restore.
- The phrase and the derived key are stored in the platform keystore
  (`flutter_secure_storage`: Android Keystore-backed encryption, iOS
  Keychain), never
  sent anywhere.
- The identity key does **not** sign alerts: a throwaway key per trip does
  (ADR 0005), so trips cannot be linked to the person.
- Identities created before this change have no phrase; they keep working,
  and the app suggests creating a new, recoverable one.

## Consequences

- Losing both the phone and the phrase loses the identity: there is no
  account to recover it from, by design.
- To do before the beta: an encrypted file export as an alternative to
  writing words down (plan, J3), and screen-capture protection on the phrase
  screen (Android `FLAG_SECURE`, iOS secure text).
