# xiom.keymgmt

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.2` on the XIOM registry.
> **Scope:** key STRUCTURE codecs: base64url, JWK/JWKS (RFC 7517/7518),
> PKCS#8 / SPKI DER structures and PEM armor. No cryptography, no key
> generation, no key math, no validation beyond structure.
> **Deps:** `xiom.std` only. The library imports `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`; the tests add `xiom.test`
> and `xiom.io`. No FFI, nothing else.

## What it is

`xiom.keymgmt` turns key material that exists as JSON, DER or PEM text into
flat, inspectable XIOM values, and turns those values back into canonical
JSON or PEM text. It is deliberately a *structure* codec:

- **base64url** (RFC 4648 section 5): unpadded encoding; decoding tolerates
  canonical padding, rejects characters outside the URL alphabet, rejects
  lengths with `n % 4 == 1`, misplaced or oversized padding, and padded
  groups whose unused low bits are non-zero. Every error names the byte
  offset.
- **JWK** (RFC 7517/7518): a bounded raw-byte JSON scanner parses one key
  object (`kty` RSA / EC / OKP / oct) with the common members `kid`, `use`,
  `key_ops`, `alg`, `x5c` (base64 DER strings), `x5t`, `x5t#S256`, `x5u`;
  parameters are base64url-decoded big-endian octet strings (RSA
  `n,e,d,p,q,dp,dq,qi`; EC `crv,x,y,d`; OKP `crv,x,d`; oct `k`). Typed
  accessors, key type detection, required-field validation per kty and
  private-vs-public detection are provided; `kme_jwk_render` emits canonical
  JSON.
- **JWKS** (RFC 7517 section 5): `{"keys":[...]}` parsing with key count and
  `kid` lookup.
- **PKCS#8 / SPKI** (X.690 TLV walking, no crypto): `PrivateKeyInfo`
  (version 0/1, `AlgorithmIdentifier`, OCTET STRING privateKey, optional
  `[0]` attributes), `EncryptedPrivateKeyInfo` and `SubjectPublicKeyInfo`,
  each decoded with byte offsets; an OID table maps `rsaEncryption`,
  `id-ecPublicKey`, `P-256`, `P-384`, `P-521`, `secp256k1`, `Ed25519`,
  `X25519`, `Ed448` and `X448`.
- **PEM armor** (RFC 7468 block shape): unwrap exactly one `PRIVATE KEY` /
  `ENCRYPTED PRIVATE KEY` / `PUBLIC KEY` block (LF or CRLF, strict canonical
  base64 on 64-character lines) and rewrap canonically.
- **Cross-format helpers**: structural mapping from a JWK to its SPKI
  algorithm name / OID (no key material is converted).

See `SPEC.md` for the exact data model, validation rules and error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `kme_base64url_encode(data)` | `Str` | Unpadded base64url of the bytes. |
| `kme_base64url_decode(text)` | `Result[Vec[UInt8], Str]` | Decode; padding tolerated, canonical checks enforced. |
| `kme_jwk_parse(text)` | `Result[Jwk, Str]` | Parse one JWK object (bounded JSON scanner). |
| `kme_jwk_render(jwk)` | `Result[Str, Str]` | Canonical JSON in a fixed member order. |
| `kme_jwk_type(jwk)` | `Int` | `KME_KTY_RSA` / `KME_KTY_EC` / `KME_KTY_OKP` / `KME_KTY_OCT` / `KME_KTY_UNKNOWN`. |
| `kme_jwk_kty/kid/use/alg/crv/x5u/x5t/x5t_s256(jwk)` | `Str` | Scalar members (`""` when absent; compare with `str_compare`). |
| `kme_jwk_key_ops_count/key_op(jwk, i)` | `Int` / `Str` | `key_ops` accessors (`""` out of range). |
| `kme_jwk_x5c_count/x5c(jwk, i)` | `Int` / `Str` | `x5c` accessors (`""` out of range). |
| `kme_jwk_member_count/member(jwk, i)` | `Int` / `Str` | Member names present, in input order. |
| `kme_jwk_has_member/has_param(jwk, name)` | `Bool` | Presence of a member / of a parameter member. |
| `kme_jwk_param_len(jwk, name)` | `Int` | Decoded parameter length, `-1` when absent. |
| `kme_jwk_param(jwk, name)` | `Vec[UInt8]` | Copy of decoded parameter bytes (empty when absent). |
| `kme_jwk_is_private(jwk)` | `Bool` | `d` present (RSA/EC/OKP); always true for oct. |
| `kme_jwk_check(jwk)` | `Result[KmeJwkInfo, Str]` | kty detection + required-field validation. |
| `kme_jwk_info_kind/is_private/param_count(info)` | `Int` / `Bool` / `Int` | Components of a check result. |
| `kme_jwk_oid(jwk)` | `Str` | Structural SPKI algorithm OID (`""` for oct). |
| `kme_jwk_alg_name(jwk)` | `Str` | Structural SPKI algorithm name. |
| `kme_jwk_curve_oid(jwk)` | `Str` | Named curve OID for EC/OKP (`""` otherwise). |
| `kme_jwks_parse(text)` | `Result[Jwks, Str]` | Parse `{"keys":[...]}`. |
| `kme_jwks_count(jwks)` | `Int` | Number of keys. |
| `kme_jwks_key(jwks, i)` | `Result[Jwk, Str]` | Parse key `i` in full. |
| `kme_jwks_lookup(jwks, kid)` | `Int` | Index of the first key with that `kid`, or `-1`. |
| `kme_der_length/tlv/tlv_in(data, off[, end])` | `Result[KmeLength/KmeTlv, Str]` | DER length and TLV walking with offsets. |
| `kme_der_oid(data, off)` | `Result[KmeOid, Str]` | OID TLV to dotted string. |
| `kme_der_alg_id(data, off, end)` | `Result[KmeAlgorithm, Str]` | `AlgorithmIdentifier` + parameters span. |
| `kme_pkcs8_parse(data)` | `Result[KmePrivateKeyInfo, Str]` | PrivateKeyInfo walk (whole buffer). |
| `kme_pkcs8_encrypted_parse(data)` | `Result[KmeEncryptedPrivateKeyInfo, Str]` | EncryptedPrivateKeyInfo walk. |
| `kme_spki_parse(data)` | `Result[KmeSpki, Str]` | SubjectPublicKeyInfo walk. |
| `kme_alg_*` / `kme_pkcs8_*` / `kme_epkcs8_*` / `kme_spki_*` | accessors | OID, parameters span, key span, attributes, next offsets. |
| `kme_oid_name(oid)` | `Str` | Table: OID -> name (`""` when unknown). |
| `kme_curve_oid(name)` | `Str` | Table: curve name -> OID. |
| `kme_pem_unwrap(text)` | `Result[KmePem, Str]` | Unwrap one supported PEM block. |
| `kme_pem_wrap(label, data)` | `Result[Str, Str]` | Canonical PEM block (64-column body). |
| `kme_pem_label(p)` / `kme_pem_data(p)` | `Str` / `Vec[UInt8]` | Block accessors. |
| `kme_label_private_key/encrypted_private_key/public_key()` | `Str` | Supported PEM labels. |
| `kme_version()` | `Int` | Interface revision (1). |

## Usage

### JWK -> JWKS lookup

```xi
use xiom.keymgmt;

let jwks_text = "{\"keys\":[{\"kty\":\"oct\",\"kid\":\"k1\",\"k\":\"AQAB\"}]}";
let r = kme_jwks_parse(jwks_text);
if r.is_ok {
  let keys: Jwks = r.value;
  let i = kme_jwks_lookup(&keys, "k1");        // 0
  let kr = kme_jwks_key(&keys, i);
  if kr.is_ok {
    let key: Jwk = kr.value;
    let chk = kme_jwk_check(&key);             // kind = KME_KTY_OCT
  }
}
```

### PKCS#8 -> PEM

```xi
use xiom.keymgmt;

// der holds a DER PrivateKeyInfo buffer
let p = kme_pkcs8_parse(&der);
if p.is_ok {
  let info: KmePrivateKeyInfo = p.value;
  let oid = kme_pkcs8_alg_oid(&info);          // e.g. "1.2.840.113549.1.1.1"
  let key = kme_pkcs8_key_bytes(&der, &info);  // privateKey octets
  let armor = kme_pem_wrap("PRIVATE KEY", key);
}
```

All `Str` results that come back from the library should be compared with
`xiom.string.compare.str_compare` (the v0.61.3 `==` trap) — the tests use a
`streq` helper for this.

## Tests

```
& .\scripts\port.ps1 -Package xiom.keymgmt
```

Expected tail:
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`

`tests/test_conformance.xi` builds every synthetic instrument in-test:
base64url vectors (pinned against RFC 4648), JWK/JWKS JSON (parameter
values via `kme_base64url_encode`), DER buffers via a local TLV builder.
Coverage: 20 checks across base64url boundaries, all four kty, required
fields and rejections, JWKS lookup, canonical rendering, the DER walker, the
three PKCS#8/SPKI structures, the OID table and the PEM catalog.

## Scope limits

- **No cryptography**: no signature, MAC, KDF, encryption or verification
  code; no key generation; no key math; no primality or point-on-curve
  checks; no bit-length policy.
- **Structure only**: RSA integers must be minimally encoded (no leading
  `0x00`); EC/OKP `x`/`y`/`d` must have exactly the curve's coordinate size;
  `oct.k` is raw bytes (leading zeros are legal there).
- **One JWK object / one JWKS object per parse call**; no streaming.
- **JWKS keys are re-parsed on demand** (flat storage: the document keeps
  spans, not a `Vec` of structs).
- **PEM**: exactly one block, only the three key labels, canonical base64
  line lengths (64) required.
- **`x5c` entries are stored as strings** (base64 DER), not decoded.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
