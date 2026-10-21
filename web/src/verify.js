// Nostr event check (NIP-01): the id is the SHA-256 of the serialized event,
// the signature a BIP-340 Schnorr signature of the id by the pubkey.
import { schnorr } from '@noble/curves/secp256k1';
import { sha256 } from '@noble/hashes/sha256';
import { bytesToHex } from '@noble/hashes/utils';

export function eventId(e) {
  const serial = JSON.stringify([0, e.pubkey, e.created_at, e.kind, e.tags, e.content]);
  return bytesToHex(sha256(new TextEncoder().encode(serial)));
}

export function verifyEvent(e) {
  try {
    return typeof e.id === 'string' && eventId(e) === e.id && schnorr.verify(e.sig, e.id, e.pubkey);
  } catch {
    return false;
  }
}
