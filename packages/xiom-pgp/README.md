# xiom.pgp

> **Status:** `stable` -- conformance-tested (22/22); published at `v0.1.0` on the XIOM registry.
> **Scope:** OpenPGP (RFC 4880 / RFC 9580 subset) packet and ASCII armor codec; no cryptography.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`, `xiom.convert`); no FFI.

Pure-XIOM structural codec for OpenPGP data:

- **Packet stream decode** (`pgp_document_parse`): old-format headers
  (length types 0-3, including the indeterminate type 3) and new-format
  headers (definite one/two/five-octet lengths and partial body lengths),
  with every declared length validated against the buffer and every error
  carrying the offending byte offset.
- **Packet tags** named by the package: Public-Key 6, Public-Subkey 14,
  Secret-Key 5, Signature 2, User ID 13, User Attribute 17, Literal Data 11,
  Compressed Data 8, Marker 10, Trust 12 (`pgp_packet_type_name`).
- **MPI codec**: bit-length prefix plus big-endian value bytes, canonical
  bit counts enforced and emitted (`pgp_mpi_decode` / `pgp_mpi_encode`).
- **v4 signature bodies**: hashed and unhashed subpacket regions framed with
  the 1/2/5-octet subpacket length encoding, plus left16
  (`pgp_signature_v4_decode` / `pgp_signature_v4_encode` /
  `pgp_subpacket_encode`).
- **v4 key bodies**: creation time, algorithm, MPIs (RSA, DSA, ElGamal,
  X9.42 DH, ECDH/ECDSA/EdDSA with curve OID, RFC 9580 native curves) and
  the public/secret split (`pgp_key_v4_decode`).
- **User IDs**: printable-text validation and structural key/binding-signature
  lookup (`pgp_user_id_text`, `pgp_user_id_key_index`,
  `pgp_user_id_binding_signature`).
- **ASCII armor**: BEGIN/END labels, `Name: value` headers, blank separator,
  base64 payload and optional CRC24 checksum line validated against
  CRC-24/OPENPGP (poly `0x1864CFB`); canonical emission wraps at 64 columns,
  uses LF endings and always writes the checksum (`pgp_armor_decode` /
  `pgp_armor_encode`).

What it is **not**: no RSA/DSA/ECC arithmetic, no hashing or signature
verification, no key validation beyond structure, no literal/compressed
payload semantics, no streaming API. See `SPEC.md` for the full contract and
the error catalog.

## Quick start

```xi
use xiom.pgp;

let doc = pgp_document_parse(packet_bytes);
if doc.is_ok {
  let d: PgpDocument = doc.value;
  let tag = pgp_packet_tag(&d, 0);
  let body = pgp_packet_body(&d, 0);
}

let armor = pgp_armor_decode(text);
if armor.is_ok {
  let a: PgpArmor = armor.value;
  let payload = pgp_armor_payload(&a);
}
```

## Verification

```powershell
& .\scripts\port.ps1 -Package xiom.pgp
# port: PASS (passed=22 failed=0 program_exit=0 exit=0)
```
