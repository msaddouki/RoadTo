"""Ed25519 signatures for region manifests.

The signature is detached: ``manifest.json.sig`` holds the base64 of the raw
64-byte Ed25519 signature over the exact bytes of ``manifest.json``. The app
verifies it against public keys pinned in its configuration.

Two signing backends:

- **Vault Transit** (production, per the plan: signing keys never sit on a
  workstation), when ``VAULT_ADDR``, ``VAULT_TOKEN`` and
  ``ROADTO_VAULT_TRANSIT_KEY`` are set. The key must be of type ed25519.
- **Local key** from ``ROADTO_SIGNING_KEY`` (base64 of the 32-byte private
  seed), for CI secrets and development.
"""

from __future__ import annotations

import base64
import json
import os
import urllib.request

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey


class SigningError(RuntimeError):
    pass


def generate_key() -> tuple[str, str]:
    """Returns (private seed, public key), both base64."""
    key = Ed25519PrivateKey.generate()
    seed = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    return base64.b64encode(seed).decode(), public_key_of(base64.b64encode(seed).decode())


def public_key_of(private_b64: str) -> str:
    key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(private_b64))
    raw = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return base64.b64encode(raw).decode()


def sign_local(data: bytes, private_b64: str) -> tuple[str, str]:
    """Returns (signature, public key), both base64."""
    try:
        key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(private_b64))
    except Exception as e:  # noqa: BLE001 - any decoding problem means a bad secret
        raise SigningError(f"invalid ROADTO_SIGNING_KEY: {e}") from e
    return base64.b64encode(key.sign(data)).decode(), public_key_of(private_b64)


def _vault(method: str, path: str, body: dict | None = None) -> dict:
    addr = os.environ["VAULT_ADDR"].rstrip("/")
    req = urllib.request.Request(
        f"{addr}/v1/{path}",
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"X-Vault-Token": os.environ["VAULT_TOKEN"], "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as res:  # noqa: S310 - operator-provided URL
        return json.load(res)


def sign_vault(data: bytes, key_name: str) -> tuple[str, str]:
    """Signs with Vault Transit. Returns (signature, public key), both base64."""
    res = _vault("POST", f"transit/sign/{key_name}", {"input": base64.b64encode(data).decode()})
    sig = res["data"]["signature"]  # "vault:v<N>:<base64>"
    version = sig.split(":")[1].removeprefix("v")
    keys = _vault("GET", f"transit/keys/{key_name}")["data"]
    if keys.get("type") != "ed25519":
        raise SigningError(f"Vault key {key_name} is {keys.get('type')}, expected ed25519")
    return sig.split(":", 2)[2], keys["keys"][version]["public_key"]


def sign(data: bytes) -> tuple[str, str]:
    """Signs with Vault when configured, otherwise with ROADTO_SIGNING_KEY."""
    if os.environ.get("VAULT_ADDR") and os.environ.get("ROADTO_VAULT_TRANSIT_KEY"):
        return sign_vault(data, os.environ["ROADTO_VAULT_TRANSIT_KEY"])
    private = os.environ.get("ROADTO_SIGNING_KEY")
    if not private:
        raise SigningError("no signing key: set ROADTO_SIGNING_KEY or configure Vault Transit")
    return sign_local(data, private)


def verify(data: bytes, signature_b64: str, public_b64: str) -> bool:
    try:
        Ed25519PublicKey.from_public_bytes(base64.b64decode(public_b64)).verify(base64.b64decode(signature_b64), data)
        return True
    except (InvalidSignature, ValueError):
        return False
