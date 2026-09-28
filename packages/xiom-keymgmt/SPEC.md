# xiom.keymgmt -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.keymgmt`, version `0.1.0`).
Module: `src/keymgmt.xi` (`module xiom.keymgmt`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`). No FFI; no base64 dependency (both base64url and the
PEM base64 codec are self-contained).

## 1. Scope

Key STRUCTURE codecs. The module parses, validates structurally, and
re-renders:

- base64url (RFC 4648 section 5),
- JWK / JWKS JSON (RFC 7517, RFC 7518 parameter shapes, RFC 8037 OKP),
- PKCS#8 `PrivateKeyInfo` / `EncryptedPrivateKeyInfo` (RFC 5958) and SPKI
  `SubjectPublicKeyInfo` (RFC 5280) DER structures,
- PEM armor for the `PRIVATE KEY` / `ENCRYPTED PRIVATE KEY` / `PUBLIC KEY`
  labels (RFC 7468 block shape).

It performs **no cryptography**: no generation, no signature/MAC/KDF code,
no key math, no primality or curve-point checks, no bit-length policy, no
`x5c` certificate decoding. A parsed value is structure, not trust.

## 2. Public API inventory

```xi
pub fn kme_base64url_encode(data: &Vec[UInt8]) -> Str
pub fn kme_base64url_decode(text: Str) -> Result[Vec[UInt8], Str]

pub fn kme_jwk_parse(text: Str) -> Result[Jwk, Str]
pub fn kme_jwk_render(jwk: &Jwk) -> Result[Str, Str]
pub fn kme_jwk_type(jwk: &Jwk) -> Int
pub fn kme_jwk_kty(jwk: &Jwk) -> Str
pub fn kme_jwk_kid(jwk: &Jwk) -> Str
pub fn kme_jwk_use(jwk: &Jwk) -> Str
pub fn kme_jwk_alg(jwk: &Jwk) -> Str
pub fn kme_jwk_crv(jwk: &Jwk) -> Str
pub fn kme_jwk_x5u(jwk: &Jwk) -> Str
pub fn kme_jwk_x5t(jwk: &Jwk) -> Str
pub fn kme_jwk_x5t_s256(jwk: &Jwk) -> Str
pub fn kme_jwk_key_ops_count(jwk: &Jwk) -> Int
pub fn kme_jwk_key_op(jwk: &Jwk, i: Int) -> Str
pub fn kme_jwk_x5c_count(jwk: &Jwk) -> Int
pub fn kme_jwk_x5c(jwk: &Jwk, i: Int) -> Str
pub fn kme_jwk_member_count(jwk: &Jwk) -> Int
pub fn kme_jwk_member(jwk: &Jwk, i: Int) -> Str
pub fn kme_jwk_has_member(jwk: &Jwk, name: Str) -> Bool
pub fn kme_jwk_has_param(jwk: &Jwk, name: Str) -> Bool
pub fn kme_jwk_param_len(jwk: &Jwk, name: Str) -> Int
pub fn kme_jwk_param(jwk: &Jwk, name: Str) -> Vec[UInt8]
pub fn kme_jwk_is_private(jwk: &Jwk) -> Bool
pub fn kme_jwk_check(jwk: &Jwk) -> Result[KmeJwkInfo, Str]
pub fn kme_jwk_info_kind(info: &KmeJwkInfo) -> Int
pub fn kme_jwk_info_is_private(info: &KmeJwkInfo) -> Bool
pub fn kme_jwk_info_param_count(info: &KmeJwkInfo) -> Int
pub fn kme_jwk_oid(jwk: &Jwk) -> Str
pub fn kme_jwk_alg_name(jwk: &Jwk) -> Str
pub fn kme_jwk_curve_oid(jwk: &Jwk) -> Str

pub fn kme_jwks_parse(text: Str) -> Result[Jwks, Str]
pub fn kme_jwks_count(jwks: &Jwks) -> Int
pub fn kme_jwks_key(jwks: &Jwks, i: Int) -> Result[Jwk, Str]
pub fn kme_jwks_lookup(jwks: &Jwks, kid: Str) -> Int

pub fn kme_der_length(data: &Vec[UInt8], off: Int) -> Result[KmeLength, Str]
pub fn kme_der_tlv(data: &Vec[UInt8], off: Int) -> Result[KmeTlv, Str]
pub fn kme_der_tlv_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[KmeTlv, Str]
pub fn kme_der_oid(data: &Vec[UInt8], off: Int) -> Result[KmeOid, Str]
pub fn kme_der_alg_id(data: &Vec[UInt8], off: Int, end: Int) -> Result[KmeAlgorithm, Str]
pub fn kme_pkcs8_parse(data: &Vec[UInt8]) -> Result[KmePrivateKeyInfo, Str]
pub fn kme_pkcs8_encrypted_parse(data: &Vec[UInt8]) -> Result[KmeEncryptedPrivateKeyInfo, Str]
pub fn kme_spki_parse(data: &Vec[UInt8]) -> Result[KmeSpki, Str]

pub fn kme_alg_oid(a: &KmeAlgorithm) -> Str
pub fn kme_alg_name(a: &KmeAlgorithm) -> Str
pub fn kme_alg_params_present(a: &KmeAlgorithm) -> Bool
pub fn kme_alg_params_offset(a: &KmeAlgorithm) -> Int
pub fn kme_alg_params_len(a: &KmeAlgorithm) -> Int
pub fn kme_alg_param_oid(data: &Vec[UInt8], a: &KmeAlgorithm) -> Str
pub fn kme_alg_next(a: &KmeAlgorithm) -> Int

pub fn kme_pkcs8_version(p: &KmePrivateKeyInfo) -> Int
pub fn kme_pkcs8_alg_oid(p: &KmePrivateKeyInfo) -> Str
pub fn kme_pkcs8_alg_params_present(p: &KmePrivateKeyInfo) -> Bool
pub fn kme_pkcs8_alg_param_oid(data: &Vec[UInt8], p: &KmePrivateKeyInfo) -> Str
pub fn kme_pkcs8_key_offset(p: &KmePrivateKeyInfo) -> Int
pub fn kme_pkcs8_key_len(p: &KmePrivateKeyInfo) -> Int
pub fn kme_pkcs8_key_bytes(data: &Vec[UInt8], p: &KmePrivateKeyInfo) -> Vec[UInt8]
pub fn kme_pkcs8_has_attributes(p: &KmePrivateKeyInfo) -> Bool
pub fn kme_pkcs8_attrs_offset(p: &KmePrivateKeyInfo) -> Int
pub fn kme_pkcs8_attrs_len(p: &KmePrivateKeyInfo) -> Int
pub fn kme_pkcs8_next(p: &KmePrivateKeyInfo) -> Int

pub fn kme_epkcs8_alg_oid(e: &KmeEncryptedPrivateKeyInfo) -> Str
pub fn kme_epkcs8_alg_param_oid(data: &Vec[UInt8], e: &KmeEncryptedPrivateKeyInfo) -> Str
pub fn kme_epkcs8_data_offset(e: &KmeEncryptedPrivateKeyInfo) -> Int
pub fn kme_epkcs8_data_len(e: &KmeEncryptedPrivateKeyInfo) -> Int
pub fn kme_epkcs8_data_bytes(data: &Vec[UInt8], e: &KmeEncryptedPrivateKeyInfo) -> Vec[UInt8]
pub fn kme_epkcs8_next(e: &KmeEncryptedPrivateKeyInfo) -> Int

pub fn kme_spki_alg_oid(s: &KmeSpki) -> Str
pub fn kme_spki_alg_params_present(s: &KmeSpki) -> Bool
pub fn kme_spki_alg_param_oid(data: &Vec[UInt8], s: &KmeSpki) -> Str
pub fn kme_spki_unused(s: &KmeSpki) -> Int
pub fn kme_spki_key_offset(s: &KmeSpki) -> Int
pub fn kme_spki_key_len(s: &KmeSpki) -> Int
pub fn kme_spki_key_bytes(data: &Vec[UInt8], s: &KmeSpki) -> Vec[UInt8]
pub fn kme_spki_next(s: &KmeSpki) -> Int

pub fn kme_oid_name(oid: Str) -> Str
pub fn kme_curve_oid(name: Str) -> Str

pub fn kme_pem_unwrap(text: Str) -> Result[KmePem, Str]
pub fn kme_pem_wrap(label: Str, data: &Vec[UInt8]) -> Result[Str, Str]
pub fn kme_pem_label(p: &KmePem) -> Str
pub fn kme_pem_data(p: &KmePem) -> Vec[UInt8]
pub fn kme_label_private_key() -> Str
pub fn kme_label_encrypted_private_key() -> Str
pub fn kme_label_public_key() -> Str
pub fn kme_version() -> Int
```

Constants: `KME_KTY_*` (0 unknown, 1 RSA, 2 EC, 3 OKP, 4 oct), `KME_CRV_*`
(0 unknown, 1 P-256, 2 P-384, 3 P-521, 4 secp256k1, 5 Ed25519, 6 X25519,
7 Ed448, 8 X448), the ten `KME_OID_*` dotted strings, the three
`KME_LABEL_*` strings, `KME_B64_STD`/`KME_B64_URL`,
`KME_JSON_MAX_DEPTH` (16), `KME_CLASS_*` and `KME_TAG_*` DER constants.

## 3. Data model

All values are flat: no `Vec` of structs is used anywhere.

- `KmeLength { len, size }` -- decoded DER length: content length, and the
  number of length-field bytes.
- `KmeTlv { tag_class, constructed, tag_number, header, content, len, next }`
  -- a decoded TLV. `header` is the offset of the first tag byte, `content`
  the offset of the first content byte, `next` the offset just past the
  content (so `next == content + len`).
- `KmeOid { value, header, next }` -- dotted OID string plus its TLV offset.
- `KmeAlgorithm { oid, oid_offset, params_present, params_offset, params_len,
  next }` -- an `AlgorithmIdentifier`; when parameters are present their TLV
  span is `params_offset .. params_offset + params_len` (header included);
  `next` is the offset past the whole SEQUENCE.
- `KmePrivateKeyInfo { version, alg, key_offset, key_len, key_tlv_offset,
  has_attributes, attrs_offset, attrs_len, next }` -- PKCS#8; `key_offset`/
  `key_len` address the privateKey OCTET STRING content, `attrs_*` the `[0]`
  IMPLICIT attributes content (`attrs_offset` is `-1` when absent).
- `KmeEncryptedPrivateKeyInfo { alg, data_offset, data_len, next }`.
- `KmeSpki { alg, unused, key_offset, key_len, next }` -- `unused` is the
  BIT STRING unused-bit count (0..7), `key_offset`/`key_len` the
  subjectPublicKey bytes after the unused-count octet.
- `Jwk { kty, kty_code, kid, use_val, alg, crv, x5u, x5t, x5t_s256, key_ops,
  x5c, n, e, d, p, q, dp, dq, qi, x, y, k, fields }` -- one parsed JWK.
  Scalars are `Str` (`""` when absent); `key_ops`/`x5c` are `Vec[Str]`;
  every parameter is a `Vec[UInt8]` of decoded octets; `fields` lists the
  member names present in input order. (The member `use` is stored as
  `use_val`: `use` is a reserved word in XIOM.)
- `KmeJwkInfo { kind, is_private, param_count }` -- result of
  `kme_jwk_check`.
- `Jwks { text, key_starts, key_ends }` -- the source text plus, per key,
  the `[start, end)` byte span of the key's JSON object.
- `KmePem { label, data }` -- one unwrapped PEM block.

## 4. base64url

Alphabet: `A-Z a-z 0-9 - _` (`-` = 62, `_` = 63). `=` is the pad character.
Encoding is **always unpadded** and total: 3-byte groups produce 4
characters, a final 1/2-byte group produces 2/3 characters, empty input
emits `""`.

Decoding (`kme_base64url_decode`):

1. Empty input is `Ok(empty)`.
2. Any `=` must form one final run of exactly 1 or 2 characters; a character
   after `=` is `bad padding` at that offset.
3. Every character before the padding (or the whole input when unpadded)
   must be in the alphabet; the first offender is `invalid character` at its
   offset.
4. Unpadded input with `n % 4 == 1` is `bad length`; with padding, the data
   length must satisfy `d % 4 == 3` (one `=`) or `d % 4 == 2` (two `=`)
   else `bad padding`.
5. The unused low bits of a final 2- or 3-character group must be zero:
   `acc % 16 == 0` respectively `acc % 4 == 0`, otherwise
   `non-canonical trailing bits`.

Errors are `keymgmt: base64url <message> at offset <n>`.

The PEM codec uses the same decoder in strict mode: standard alphabet
(`+`/`/`), whole-body length a multiple of 4, padding mandatory only when
the data remainder needs it.

## 5. JSON scanner (JWK/JWKS only)

A bounded, byte-oriented scanner (no `xiom.json` dependency):

- Only object and array *containers* are recursed, with a maximum depth of
  `KME_JSON_MAX_DEPTH` (16); deeper input is `nesting too deep`.
- Strings decode `\" \\ \/ \b \f \n \r \t` and `\uXXXX` with surrogate
  pairs; lone surrogates and `\u0000` are rejected (a XIOM `Str` is
  NUL-terminated, so NUL can never enter one).
- Raw control bytes (< 0x20) inside a string are rejected.
- Numbers, `true`, `false` and `null` are scanned for shape but never
  stored.
- Trailing commas are rejected; a literal must match exactly.
- All JSON errors are `keymgmt: json <message> at offset <n>`.

## 6. JWK

### 6.1 Members recognized

| Member | Type | Storage |
|---|---|---|
| `kty` | string | `kty` + `kty_code`; must be `RSA`, `EC`, `OKP` or `oct`. |
| `kid`, `use`, `alg`, `crv`, `x5u`, `x5t`, `x5t#S256` | string | as-is (UTF-8 passthrough). |
| `key_ops` | array of strings | `key_ops`; must be non-empty. |
| `x5c` | array of strings | `x5c` (base64 DER strings, not decoded); must be non-empty. |
| `n,e,d,p,q,dp,dq,qi,x,y,k` | string | base64url-decoded to bytes (leading-zero rejection applies only where documented below). |

Unknown members are skipped when they are syntactically valid JSON.
Duplicate members (by exact name) are rejected. Trailing non-whitespace
after the object is rejected. A JWK without `kty` is rejected.

### 6.2 Validation per kty (`kme_jwk_check`)

- **RSA**: `n` and `e` required, non-empty, minimally encoded big-endian
  (a leading `0x00` byte is `non-minimal`). `d` present means private; then
  the CRT members `p,q,dp,dq,qi` are all-or-nothing: if any is present all
  five are required (each non-empty and minimal). A CRT member without `d`
  is `missing d`.
- **EC**: `crv` required and one of `P-256` (32-byte coordinates), `P-384`
  (48), `P-521` (66), `secp256k1` (32); `x` and `y` required with exactly
  the coordinate size; `d` optional with the same size and marks the key
  private. EC coordinates are fixed-length, so leading zeros are legal.
- **OKP**: `crv` required and one of `Ed25519`/`X25519` (32), `Ed448` (57),
  `X448` (56); `x` required; `d` optional at the same size.
- **oct**: `k` required and non-empty; raw bytes, leading zeros legal;
  `is_private` is always true (the `k` value is the secret).

A curve from the wrong family for the kty is `curve mismatch`. `param_count`
counts the ten parameter members present (0..10).

### 6.3 Private-vs-public detection

`d` present -> private (RSA/EC/OKP); oct -> always private; otherwise public.

### 6.4 Canonical rendering (`kme_jwk_render`)

Members are emitted in this fixed order, each only when present:
`kty`, `kid`, `use`, `key_ops`, `alg`, `crv`, `x`, `y`, `d`, `n`, `e`,
`p`, `q`, `dp`, `dq`, `qi`, `k`, `x5c`, `x5t`, `x5t#S256`, `x5u`.
Parameter values are re-encoded as unpadded base64url; strings are escaped
(`"`, `\`, control bytes as `\u00xx`). The function fails only when
`kty_code` is not one of the four known codes.

### 6.5 Cross-format helpers (structural only)

| JWK | `kme_jwk_oid` | `kme_jwk_alg_name` | `kme_jwk_curve_oid` |
|---|---|---|---|
| RSA | `1.2.840.113549.1.1.1` | `rsaEncryption` | `""` |
| EC | `1.2.840.10045.2.1` | `id-ecPublicKey` | curve OID |
| OKP | curve OID | curve name | curve OID |
| oct | `""` | `""` | `""` |

## 7. JWKS

`kme_jwks_parse` accepts a JSON object whose `"keys"` member is an array of
JSON objects (other members are skipped when valid JSON; the whole text must
be consumed). It stores the source text and each key object's span.
`kme_jwks_count` is the number of spans; `kme_jwks_key` re-parses key `i`
(offsets in errors are absolute in the JWKS text); `kme_jwks_lookup` returns
the first index whose `kid` equals the argument byte-for-byte, or -1, and
skips keys that fail to parse. A missing `keys` member is an error; an empty
array is a valid zero-key JWKS.

## 8. DER structures

### 8.1 TLV walker

`kme_der_tlv` decodes one tag-length-value at an offset: tag class,
constructed bit, tag number (high-tag-number form included, overflow
rejected), minimal definite length (short form, or long form with 1..8
bytes, no leading zero, value >= 128; indefinite `0x80` rejected), and
checks the content against the buffer. `kme_der_tlv_in` additionally
requires the TLV to end at or before an enclosing `end`. Every result
carries byte offsets (`header`, `content`, `len`, `next`).

### 8.2 AlgorithmIdentifier

`kme_der_alg_id` parses `SEQUENCE { OID, ANY OPTIONAL }`; parameters are
recorded as a span (present, offset, TLV length) and must be the last
element. `kme_alg_param_oid` returns the parameters OID only when the
parameters TLV is exactly one OBJECT IDENTIFIER (the namedCurve form);
otherwise `""`.

### 8.3 PrivateKeyInfo (RFC 5958)

```
PrivateKeyInfo ::= SEQUENCE {
  version              INTEGER (0 | 1),
  privateKeyAlgorithm  AlgorithmIdentifier,
  privateKey           OCTET STRING,
  attributes           [0] IMPLICIT Attributes OPTIONAL }
```

The outer SEQUENCE must consume the whole buffer. `version` values other
than 0/1 are `bad pkcs8 version`. The attributes field, when present, must
be context-class constructed tag 0 and last.

### 8.4 EncryptedPrivateKeyInfo

```
EncryptedPrivateKeyInfo ::= SEQUENCE {
  encryptionAlgorithm  AlgorithmIdentifier,
  encryptedData        OCTET STRING }
```

### 8.5 SubjectPublicKeyInfo (RFC 5280)

```
SubjectPublicKeyInfo ::= SEQUENCE {
  algorithm          AlgorithmIdentifier,
  subjectPublicKey   BIT STRING }
```

The BIT STRING must carry the unused-bit count octet (content length >= 1)
with a count of 0..7; `key_offset`/`key_len` address the key bytes after
that octet. The whole buffer must be consumed.

## 9. OID table

| OID | Name |
|---|---|
| `1.2.840.113549.1.1.1` | `rsaEncryption` |
| `1.2.840.10045.2.1` | `id-ecPublicKey` |
| `1.2.840.10045.3.1.7` | `P-256` |
| `1.3.132.0.34` | `P-384` |
| `1.3.132.0.35` | `P-521` |
| `1.3.132.0.10` | `secp256k1` |
| `1.3.101.112` | `Ed25519` |
| `1.3.101.110` | `X25519` |
| `1.3.101.113` | `Ed448` |
| `1.3.101.111` | `X448` |

`kme_oid_name` returns `""` for unknown OIDs; `kme_curve_oid` is the
reverse map for canonical curve names.

## 10. PEM armor

Grammar (one block per call, surrounding empty lines ignored):

```
block      = begin-line LF body-lines end-line [LF]
begin-line = "-----BEGIN " label "-----"
end-line   = "-----END "   label "-----"
label      = "PRIVATE KEY" / "ENCRYPTED PRIVATE KEY" / "PUBLIC KEY"
```

- Lines end at LF or EOF; one CR before LF is removed (CRLF tolerance).
- The label of the BEGIN and END lines must match byte-for-byte.
- Body lines are strict base64: every line except the last is exactly 64
  characters, the last is 1..64; the concatenated length is a multiple of 4
  with canonical padding and zero unused low bits.
- An empty body, a blank line inside the body, a nested BEGIN, text outside
  the block, or EOF before END are errors.
- `kme_pem_wrap` emits the canonical form: BEGIN line, body wrapped at
  exactly 64 characters with LF endings (no body line for empty data), END
  line, trailing LF.

## 11. Error catalog

All messages are `Err` strings. Offset-bearing messages append
` at offset <n>` (decimal, byte offset in the buffer/text being parsed);
the first applicable rule in scan order wins.

### 11.1 base64url (`keymgmt: base64url `)

`bad length`, `invalid character`, `bad padding`,
`non-canonical trailing bits`.

### 11.2 JSON (`keymgmt: json `)

`expected object` is not emitted here (that is a JWK/JWKS message);
the scanner emits: `expected string`, `unterminated string`,
`control character in string`, `invalid escape`, `invalid unicode escape`,
`invalid surrogate`, `NUL character`, `invalid number`, `invalid literal`,
`invalid value`, `expected colon`, `expected comma or brace`,
`expected comma or bracket`, `unterminated object`, `unterminated array`,
`expected array`, `nesting too deep`.

### 11.3 JWK (`keymgmt: jwk `)

`expected object`, `unterminated object`, `expected comma or brace`,
`expected colon`, `missing value`, `duplicate member`, `unsupported kty`,
`missing kty`, `empty array`, `trailing data`;
parameter decode errors are prefixed `keymgmt: jwk <name>: ` + the base64url
catalog.

`kme_jwk_check` errors (no offset; the JWK no longer carries one):
`unsupported kty`, `missing crv`, `unsupported curve <crv>`,
`curve mismatch`, `missing <name>`, `empty <name>`, `non-minimal <name>`,
`<name> length must be <n>`.

### 11.4 JWKS (`keymgmt: jwks `)

`expected object`, `expected colon`, `missing keys`, `duplicate keys`,
`keys not array`, `key not object`, `unterminated array`,
`unterminated object`, `expected comma or bracket`,
`expected comma or brace`, `trailing data`, `index out of range`.

### 11.5 DER (`keymgmt: der `)

`negative offset` (no offset suffix), `truncated tag`, `truncated length`,
`truncated value`, `value overruns container`, `indefinite length`,
`non-minimal length`, `length overflow`, `non-minimal tag`,
`tag number overflow`, `tag mismatch`, `expected sequence`,
`empty integer`, `integer overflow`, `negative integer`,
`non-minimal integer`, `empty oid`, `bad oid`, `truncated oid`,
`non-minimal oid arc`, `oid overflow`, `oid too long`, `trailing data`,
`bad pkcs8 version`, `bad bit string`.

### 11.6 PEM (`keymgmt: pem `)

`no block` (no offset suffix), `unsupported label` (with offset from
`kme_pem_unwrap`, bare from `kme_pem_wrap`), `text outside block`,
`nested block`, `label mismatch`, `bad armor` (a line inside an open block
that starts with five hyphens but is not a well-formed BEGIN/END marker),
`blank line in body`,
`bad body line length`, `invalid base64 character`, `bad length`,
`bad padding`, `non-canonical trailing bits`, `unterminated block`,
`empty body`.

## 12. Test plan

`tests/test_conformance.xi` (module `keymgmt_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality uses
`xiom.string.compare.str_compare` (BUG 17 discipline). All instruments are
synthetic and built in-test: JWK/JWKS JSON by concatenation (parameters via
`kme_base64url_encode`), DER buffers via a local TLV builder. Pinned
base64url vectors are cross-checked against RFC 4648.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | base64url encode | empty, `-_8`, `SGVsbG8`, `Bw`, `AAAA`, `_w` (unpadded). |
| t2 | base64url decode | pinned vectors; padding tolerated; lengths 0..8 round-trip. |
| t3 | base64url rejections | `bad length`, `invalid character` (`!`, `+`, `/`), `bad padding` (misplaced/oversized), `non-canonical trailing bits`. |
| t4 | JWK RSA public | all common members, `key_ops`/`x5c`, typed accessors, check result. |
| t5 | JWK RSA private | CRT all-or-nothing, `missing d`, minimality, empty/missing fields. |
| t6 | JWK EC | P-256 sizes, curve table, private detection, unknown curve, wrong size, missing `y`, family mismatch. |
| t7 | JWK OKP/oct | Ed25519/X25519/Ed448 sizes, `oct` requirements and detection. |
| t8 | JWK malformed | unknown/missing `kty`, duplicates, empty arrays, JSON escapes, NUL, surrogates, nesting depth, trailing data. |
| t9 | JWKS | 3-key document, kid lookup, out-of-range, empty array, missing/duplicated keys, non-object keys, trailing data. |
| t10 | JWK render | exact canonical text, member order, escaping, re-render idempotence. |
| t11 | DER walker | offsets, long length, high tag number, truncation, container overrun, OID decode. |
| t12 | PrivateKeyInfo | RSA and EC walks, attributes, bad version, trailing data, tag mismatch. |
| t13 | EncryptedPrivateKeyInfo | algorithm + data walk, truncation. |
| t14 | SPKI | EC/RSA walks, unused bits, missing unused octet, tag mismatch. |
| t15 | OID table | all ten names and reverse curve lookup. |
| t16 | PEM unwrap | pinned wrap text, CRLF, no trailing LF, three labels, full malformed catalog. |
| t17 | PEM wrap | exact 64-column body, final padded group `/w==`. |
| t18 | PEM round-trip | 64-byte payload across labels and line endings. |
| t19 | accessors | out-of-range neutrals (`""`, `-1`, `0`), labels, version. |
| t20 | cross-format | JWK -> SPKI name/OID mapping for all four kty. |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.keymgmt
# port: PASS (passed=20 failed=0 program_exit=0 exit=0)
```

## 13. Known limitations

- **Structure only** (section 1): no crypto, no semantic validation, no
  key math, no `x5c` decoding, no streaming.
- **Strict canonical inputs**: unpadded-or-canonical-padded base64url,
  minimal RSA integers, exact EC/OKP coordinate sizes, one PEM block with
  64-character body lines.
- **One JSON value per call** and a fixed nesting bound of 16.
- **`kme_jwk_check` errors carry no offset** (the `Jwk` value does not
  retain source offsets; parse-time errors do).
- **Unknown JWK members are dropped** by rendering (they are not
  round-tripped).
- **OID rendering only knows the ten table entries**; unknown OIDs are
  preserved only inside DER (`KmeOid.value`).

## 14. Compiler / stdlib notes (v0.61.3)

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `match`, no `Vec` of
  structs, no `Vec[fn]` dispatch; if/elif chains for dispatch.
- `Ok`/`Err` are constructed only in the leaf helpers (`_ok_*`/`_err_*`).
- Every raw byte read is widened with `(x as Int) & 0xFF`; `Vec[Str]` /
  `Vec[Int]` element reads are bound to typed locals; `Str` comparison goes
  through `str_compare` only.
- No shifts: base64 groups, UTF-8 sequences and big-endian reads use
  multiplication/division/modulo (truncating Int division).
- `&struct.field` is bound to a local before it is passed to a
  `&Vec[UInt8]` parameter.
- The JWK member `use` is stored as `use_val` (`use` is reserved).
- No `Str` reaches `sb_to_str` with a 0x00 byte: JSON rejects NUL at parse
  time and all other strings are built from validated ranges.
