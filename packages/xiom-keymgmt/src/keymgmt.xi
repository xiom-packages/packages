// XIOM -- xiom.keymgmt: key structure codecs (JWK/JWKS, PKCS#8/SPKI, PEM)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, nothing beyond xiom.std) key STRUCTURE codec:
//   * base64url (RFC 4648 section 5): encoding is unpadded; decoding tolerates
//     canonical padding, rejects characters outside the URL alphabet, rejects
//     lengths with n % 4 == 1, misplaced or oversized padding, and padded
//     groups whose unused low bits are non-zero. Every error names the byte
//     offset.
//   * JWK (RFC 7517/7518): a bounded raw-byte JSON scanner parses one key
//     object into a flat Jwk value. kty is RSA / EC / OKP / oct; the common
//     members kid, use, key_ops, alg, x5c (base64 DER strings), x5t,
//     x5t#S256 and x5u are preserved; RSA n,e,d,p,q,dp,dq,qi, EC crv/x/y/d,
//     OKP crv/x/d and oct k are base64url-decoded big-endian octet strings.
//     Typed accessors, key type detection, required-field validation per kty
//     and private-vs-public detection are provided; kme_jwk_render emits
//     canonical JSON in a fixed member order.
//   * JWKS (RFC 7517 section 5): {"keys":[...]} parse with count and kid
//     lookup. Keys are stored as spans of the source text and re-parsed on
//     demand (no Vec of structs).
//   * PKCS#8 / SPKI DER structures (X.690 TLV walking, no crypto):
//     PrivateKeyInfo (version 0/1, AlgorithmIdentifier, OCTET STRING
//     privateKey, optional [0] attributes), EncryptedPrivateKeyInfo and
//     SubjectPublicKeyInfo, each decoded into a flat model carrying byte
//     offsets. A dotted-OID table maps rsaEncryption, id-ecPublicKey, the
//     named curves P-256/P-384/P-521/secp256k1 and the OKP curves
//     Ed25519/X25519/Ed448/X448.
//   * PEM armor (RFC 7468 shape) for the PRIVATE KEY / ENCRYPTED PRIVATE KEY
//     / PUBLIC KEY labels: unwrap one block (LF or CRLF, strict canonical
//     base64, 64-character lines) and rewrap canonically with a local codec.
//   * Cross-format helpers map a JWK to its structural algorithm name / OID
//     (no key material is converted).
//
// Deliberate scope limits:
//   * NO cryptography, NO key generation, NO key math, NO signature or
//     certificate verification, NO semantic validation (bit-length policy,
//     primality, point-on-curve, etc. are all out of scope).
//   * Parameter octet strings are opaque big-endian byte strings; only the
//     structural rules in SPEC.md/README.md apply. RSA integers must be
//     minimally encoded (no leading 0x00); EC/OKP x/y/d are fixed-length and
//     leading zeros are legal there (documented).
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no `match`, no Vec of
//     structs, no Vec[fn] dispatch, no table-driven dispatch;
//   * Ok/Err construction is confined to the tiny `_ok_*`/`_err_*` leaf
//     helpers below (constructing Results inside larger functions
//     miscompiles);
//   * every byte read from a Vec[UInt8] or a Str is widened with
//     `(x as Int) & 0xFF` before it enters Int arithmetic;
//   * Str values read from a Vec[Str] are bound to typed locals and compared
//     only through str_compare (the byte-wise `_streq`), never `==`;
//   * no shifts anywhere: base64 groups, UTF-8 sequences and big-endian
//     reads use multiplication/division/modulo;
//   * every parallel Vec is pushed in lockstep; mismatched lengths are
//     treated as malformed input;
//   * `&struct.field` is never passed to a `&Vec[UInt8]` parameter directly;
//     the field is bound to a local first;
//   * no Str is built from bytes that may contain 0x00 (sb_to_str rejects
//     0x00 input by contract); JSON strings reject NUL at parse time.

module xiom.keymgmt

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Key type code: unknown / absent (0).
pub const KME_KTY_UNKNOWN: Int = 0;

/// Key type code: RSA (1).
pub const KME_KTY_RSA: Int = 1;

/// Key type code: EC (2).
pub const KME_KTY_EC: Int = 2;

/// Key type code: OKP (3).
pub const KME_KTY_OKP: Int = 3;

/// Key type code: oct (4).
pub const KME_KTY_OCT: Int = 4;

/// Curve code: unknown (0).
pub const KME_CRV_UNKNOWN: Int = 0;

/// Curve code: P-256 (1).
pub const KME_CRV_P256: Int = 1;

/// Curve code: P-384 (2).
pub const KME_CRV_P384: Int = 2;

/// Curve code: P-521 (3).
pub const KME_CRV_P521: Int = 3;

/// Curve code: secp256k1 (4).
pub const KME_CRV_SECP256K1: Int = 4;

/// Curve code: Ed25519 (5).
pub const KME_CRV_ED25519: Int = 5;

/// Curve code: X25519 (6).
pub const KME_CRV_X25519: Int = 6;

/// Curve code: Ed448 (7).
pub const KME_CRV_ED448: Int = 7;

/// Curve code: X448 (8).
pub const KME_CRV_X448: Int = 8;

/// rsaEncryption OID (1.2.840.113549.1.1.1).
pub const KME_OID_RSA_ENCRYPTION: Str = "1.2.840.113549.1.1.1";

/// id-ecPublicKey OID (1.2.840.10045.2.1).
pub const KME_OID_EC_PUBLIC_KEY: Str = "1.2.840.10045.2.1";

/// Named curve P-256 / prime256v1 / secp256r1 OID (1.2.840.10045.3.1.7).
pub const KME_OID_P256: Str = "1.2.840.10045.3.1.7";

/// Named curve P-384 / secp384r1 OID (1.3.132.0.34).
pub const KME_OID_P384: Str = "1.3.132.0.34";

/// Named curve P-521 / secp521r1 OID (1.3.132.0.35).
pub const KME_OID_P521: Str = "1.3.132.0.35";

/// Named curve secp256k1 OID (1.3.132.0.10).
pub const KME_OID_SECP256K1: Str = "1.3.132.0.10";

/// Ed25519 OID (1.3.101.112).
pub const KME_OID_ED25519: Str = "1.3.101.112";

/// X25519 OID (1.3.101.110).
pub const KME_OID_X25519: Str = "1.3.101.110";

/// Ed448 OID (1.3.101.113).
pub const KME_OID_ED448: Str = "1.3.101.113";

/// X448 OID (1.3.101.111).
pub const KME_OID_X448: Str = "1.3.101.111";

/// PEM label "PRIVATE KEY".
pub const KME_LABEL_PRIVATE_KEY: Str = "PRIVATE KEY";

/// PEM label "ENCRYPTED PRIVATE KEY".
pub const KME_LABEL_ENCRYPTED_PRIVATE_KEY: Str = "ENCRYPTED PRIVATE KEY";

/// PEM label "PUBLIC KEY".
pub const KME_LABEL_PUBLIC_KEY: Str = "PUBLIC KEY";

/// Base64 alphabet mode: standard (A-Z a-z 0-9 + /).
pub const KME_B64_STD: Int = 0;

/// Base64 alphabet mode: URL-safe (A-Z a-z 0-9 - _).
pub const KME_B64_URL: Int = 1;

/// Maximum JSON nesting depth accepted by the JWK/JWKS scanner (16).
pub const KME_JSON_MAX_DEPTH: Int = 16;

/// DER tag class UNIVERSAL.
pub const KME_CLASS_UNIVERSAL: Int = 0;

/// DER tag class APPLICATION.
pub const KME_CLASS_APPLICATION: Int = 1;

/// DER tag class CONTEXT-SPECIFIC.
pub const KME_CLASS_CONTEXT: Int = 2;

/// DER tag class PRIVATE.
pub const KME_CLASS_PRIVATE: Int = 3;

/// Universal DER tag of INTEGER (0x02).
pub const KME_TAG_INTEGER: Int = 2;

/// Universal DER tag of BIT STRING (0x03).
pub const KME_TAG_BIT_STRING: Int = 3;

/// Universal DER tag of OCTET STRING (0x04).
pub const KME_TAG_OCTET_STRING: Int = 4;

/// Universal DER tag of NULL (0x05).
pub const KME_TAG_NULL: Int = 5;

/// Universal DER tag of OBJECT IDENTIFIER (0x06).
pub const KME_TAG_OID: Int = 6;

/// Universal DER tag of SEQUENCE (0x10).
pub const KME_TAG_SEQUENCE: Int = 16;

// --------------------------------------------------
//  Public data model (flat; no Vec of structs)
// --------------------------------------------------

/// A decoded DER length field. `len` is the content length (>= 0) and `size`
/// the number of length-field bytes (1 for the short form, 1 + n for the
/// long form).
pub type KmeLength = {
  len: Int;
  size: Int;
}

/// A decoded DER tag-length-value header. `tag_class` is 0..3, `constructed`
/// the P/C bit, `tag_number` the tag number (high-tag-number form included);
/// `header` is the offset of the first tag byte, `content` the offset of the
/// first content byte, `len` the content length and `next` the offset just
/// past the content.
pub type KmeTlv = {
  tag_class: Int;
  constructed: Bool;
  tag_number: Int;
  header: Int;
  content: Int;
  len: Int;
  next: Int;
}

/// A decoded OBJECT IDENTIFIER as a dotted decimal string, plus `header` (the
/// offset of the OID TLV) and `next` (the offset just past the TLV).
pub type KmeOid = {
  value: Str;
  header: Int;
  next: Int;
}

/// A decoded AlgorithmIdentifier: `oid` (dotted), `oid_offset` (offset of the
/// OID TLV), `params_present` and, when present, the parameters' TLV span
/// (`params_offset`, `params_len`, TLV header included); `next` is the offset
/// just past the whole SEQUENCE.
pub type KmeAlgorithm = {
  oid: Str;
  oid_offset: Int;
  params_present: Bool;
  params_offset: Int;
  params_len: Int;
  next: Int;
}

/// A decoded PKCS#8 PrivateKeyInfo. `version` is 0 or 1, `key_offset`/
/// `key_len` address the privateKey OCTET STRING content in the source
/// buffer, `key_tlv_offset` the OCTET STRING TLV, and the optional
/// [0] IMPLICIT attributes are described by `has_attributes`,
/// `attrs_offset` (content) and `attrs_len`; `next` is the offset just past
/// the outer SEQUENCE.
pub type KmePrivateKeyInfo = {
  version: Int;
  alg: KmeAlgorithm;
  key_offset: Int;
  key_len: Int;
  key_tlv_offset: Int;
  has_attributes: Bool;
  attrs_offset: Int;
  attrs_len: Int;
  next: Int;
}

/// A decoded PKCS#8 EncryptedPrivateKeyInfo: the encryption algorithm, the
/// encryptedData OCTET STRING span and the offset just past the outer
/// SEQUENCE.
pub type KmeEncryptedPrivateKeyInfo = {
  alg: KmeAlgorithm;
  data_offset: Int;
  data_len: Int;
  next: Int;
}

/// A decoded SubjectPublicKeyInfo: the algorithm, the BIT STRING unused-bit
/// count, the subjectPublicKey bytes span (after the unused-bit count octet)
/// and the offset just past the outer SEQUENCE.
pub type KmeSpki = {
  alg: KmeAlgorithm;
  unused: Int;
  key_offset: Int;
  key_len: Int;
  next: Int;
}

/// A parsed JWK key object. Scalar members are stored as Str ("" when
/// absent), `key_ops` and `x5c` as Vec[Str] pools, and every parameter as a
/// byte vector (base64url-decoded, big-endian, verbatim). `fields` lists the
/// member names present in input order (presence + duplicate detection);
/// `key_ops`/`x5c` entries follow input order.
pub type Jwk = {
  kty: Str;
  kty_code: Int;
  kid: Str;
  use_val: Str;
  alg: Str;
  crv: Str;
  x5u: Str;
  x5t: Str;
  x5t_s256: Str;
  key_ops: Vec[Str];
  x5c: Vec[Str];
  n: Vec[UInt8];
  e: Vec[UInt8];
  d: Vec[UInt8];
  p: Vec[UInt8];
  q: Vec[UInt8];
  dp: Vec[UInt8];
  dq: Vec[UInt8];
  qi: Vec[UInt8];
  x: Vec[UInt8];
  y: Vec[UInt8];
  k: Vec[UInt8];
  fields: Vec[Str];
}

/// Result of kme_jwk_check: the detected key type (`kind`), whether the JWK
/// carries private material (`is_private`) and how many parameter members are
/// present (`param_count`, 0..10).
pub type KmeJwkInfo = {
  kind: Int;
  is_private: Bool;
  param_count: Int;
}

/// A parsed JWKS: the source text plus, per key, the [start, end) span of the
/// key's JSON object. Keys are re-parsed by kme_jwks_key.
pub type Jwks = {
  text: Str;
  key_starts: Vec[Int];
  key_ends: Vec[Int];
}

/// One unwrapped PEM block: the label shared by the BEGIN/END lines and the
/// decoded body bytes.
pub type KmePem = {
  label: Str;
  data: Vec[UInt8];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[KmeLength, Str].
fn _ok_len(v: KmeLength) -> Result[KmeLength, Str] {
  return Ok(v);
}

// Err(m) for Result[KmeLength, Str].
fn _err_len(m: Str) -> Result[KmeLength, Str] {
  return Err(m);
}

// Ok(v) for Result[KmeTlv, Str].
fn _ok_tlv(v: KmeTlv) -> Result[KmeTlv, Str] {
  return Ok(v);
}

// Err(m) for Result[KmeTlv, Str].
fn _err_tlv(m: Str) -> Result[KmeTlv, Str] {
  return Err(m);
}

// Ok(v) for Result[KmeOid, Str].
fn _ok_oid(v: KmeOid) -> Result[KmeOid, Str] {
  return Ok(v);
}

// Err(m) for Result[KmeOid, Str].
fn _err_oid(m: Str) -> Result[KmeOid, Str] {
  return Err(m);
}

// Ok(v) for Result[KmeAlgorithm, Str].
fn _ok_alg(v: KmeAlgorithm) -> Result[KmeAlgorithm, Str] {
  return Ok(v);
}

// Err(m) for Result[KmeAlgorithm, Str].
fn _err_alg(m: Str) -> Result[KmeAlgorithm, Str] {
  return Err(m);
}

// Ok(v) for Result[KmePrivateKeyInfo, Str].
fn _ok_pki(v: KmePrivateKeyInfo) -> Result[KmePrivateKeyInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[KmePrivateKeyInfo, Str].
fn _err_pki(m: Str) -> Result[KmePrivateKeyInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[KmeEncryptedPrivateKeyInfo, Str].
fn _ok_epki(v: KmeEncryptedPrivateKeyInfo) -> Result[KmeEncryptedPrivateKeyInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[KmeEncryptedPrivateKeyInfo, Str].
fn _err_epki(m: Str) -> Result[KmeEncryptedPrivateKeyInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[KmeSpki, Str].
fn _ok_spki(v: KmeSpki) -> Result[KmeSpki, Str] {
  return Ok(v);
}

// Err(m) for Result[KmeSpki, Str].
fn _err_spki(m: Str) -> Result[KmeSpki, Str] {
  return Err(m);
}

// Ok(v) for Result[Jwk, Str].
fn _ok_jwk(v: Jwk) -> Result[Jwk, Str] {
  return Ok(v);
}

// Err(m) for Result[Jwk, Str].
fn _err_jwk(m: Str) -> Result[Jwk, Str] {
  return Err(m);
}

// Ok(v) for Result[KmeJwkInfo, Str].
fn _ok_info(v: KmeJwkInfo) -> Result[KmeJwkInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[KmeJwkInfo, Str].
fn _err_info(m: Str) -> Result[KmeJwkInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[Jwks, Str].
fn _ok_jwks(v: Jwks) -> Result[Jwks, Str] {
  return Ok(v);
}

// Err(m) for Result[Jwks, Str].
fn _err_jwks(m: Str) -> Result[Jwks, Str] {
  return Err(m);
}

// Ok(v) for Result[KmePem, Str].
fn _ok_pem(v: KmePem) -> Result[KmePem, Str] {
  return Ok(v);
}

// Err(m) for Result[KmePem, Str].
fn _err_pem(m: Str) -> Result[KmePem, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte / Str helpers
// --------------------------------------------------

// Byte at `pos` of a byte vector widened to an Int (0..255); callers
// guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Byte at `pos` of a Str widened to an Int (0..255); callers guarantee the
// bounds.
fn _tb(text: Str, pos: Int) -> Int {
  return (string.byte_at(text, pos) as Int) & 0xFF;
}

// True when `a` and `b` are byte-for-byte equal (never `==` on Str).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Append the bytes of `s` to `out`.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append the bytes of `v` to `out`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Raw bytes of a Str (one byte per index).
fn _bytes_of_str(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_str(&mut out, s);
  return out;
}

// Str built from data[start, start + n); callers guarantee the bounds. No
// 0x00 byte may be inside the range (sb_to_str contract).
fn _str_from_range(data: &Vec[UInt8], start: Int, n: Int) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < n {
    builder.sb_push_byte(&mut sb, data[start + i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Copy data[start, start + n) into a fresh vector; an out-of-range request
// yields an empty vector.
fn _copy_bytes_checked(data: &Vec[UInt8], start: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if start < 0 || n < 0 || start + n > data.len() {
    return out;
  }
  var i = 0;
  while i < n {
    out.push(data[start + i]);
    i = i + 1;
  }
  return out;
}

// Decimal rendering of `v` appended to `prefix` (used by error messages).
fn _msg_int(prefix: Str, v: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, prefix);
  builder.sb_push_int(&mut sb, v);
  return builder.sb_to_str(&sb);
}

// "`msg` at offset `off`".
fn _at(msg: Str, off: Int) -> Str {
  return _msg_int(msg + " at offset ", off);
}

// True when `t` is a TLV of tag class `cls` and tag number `tag`.
fn _tlv_is(t: &KmeTlv, cls: Int, tag: Int) -> Bool {
  if t.tag_class != cls {
    return false;
  }
  if t.tag_number != tag {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Key type / curve name tables
// --------------------------------------------------

// Key type code of a JWK "kty" string (KME_KTY_UNKNOWN when not one of the
// four supported types).
fn _kty_code(name: Str) -> Int {
  if _streq(name, "RSA") {
    return KME_KTY_RSA;
  }
  if _streq(name, "EC") {
    return KME_KTY_EC;
  }
  if _streq(name, "OKP") {
    return KME_KTY_OKP;
  }
  if _streq(name, "oct") {
    return KME_KTY_OCT;
  }
  return KME_KTY_UNKNOWN;
}

// Curve code of a JWK "crv" string (KME_CRV_UNKNOWN when unknown).
fn _crv_code(name: Str) -> Int {
  if _streq(name, "P-256") {
    return KME_CRV_P256;
  }
  if _streq(name, "P-384") {
    return KME_CRV_P384;
  }
  if _streq(name, "P-521") {
    return KME_CRV_P521;
  }
  if _streq(name, "secp256k1") {
    return KME_CRV_SECP256K1;
  }
  if _streq(name, "Ed25519") {
    return KME_CRV_ED25519;
  }
  if _streq(name, "X25519") {
    return KME_CRV_X25519;
  }
  if _streq(name, "Ed448") {
    return KME_CRV_ED448;
  }
  if _streq(name, "X448") {
    return KME_CRV_X448;
  }
  return KME_CRV_UNKNOWN;
}

// Canonical curve name of a curve code ("" for unknown).
fn _curve_name(code: Int) -> Str {
  if code == KME_CRV_P256 {
    return "P-256";
  }
  if code == KME_CRV_P384 {
    return "P-384";
  }
  if code == KME_CRV_P521 {
    return "P-521";
  }
  if code == KME_CRV_SECP256K1 {
    return "secp256k1";
  }
  if code == KME_CRV_ED25519 {
    return "Ed25519";
  }
  if code == KME_CRV_X25519 {
    return "X25519";
  }
  if code == KME_CRV_ED448 {
    return "Ed448";
  }
  if code == KME_CRV_X448 {
    return "X448";
  }
  return "";
}

// Named curve / algorithm OID of a curve code ("" for unknown).
fn _curve_oid(code: Int) -> Str {
  if code == KME_CRV_P256 {
    return KME_OID_P256;
  }
  if code == KME_CRV_P384 {
    return KME_OID_P384;
  }
  if code == KME_CRV_P521 {
    return KME_OID_P521;
  }
  if code == KME_CRV_SECP256K1 {
    return KME_OID_SECP256K1;
  }
  if code == KME_CRV_ED25519 {
    return KME_OID_ED25519;
  }
  if code == KME_CRV_X25519 {
    return KME_OID_X25519;
  }
  if code == KME_CRV_ED448 {
    return KME_OID_ED448;
  }
  if code == KME_CRV_X448 {
    return KME_OID_X448;
  }
  return "";
}

// Fixed octet-string size of a curve code, in bytes (0 for unknown):
// P-256 32, P-384 48, P-521 66, secp256k1 32, Ed25519 32, X25519 32,
// Ed448 57, X448 56.
fn _crv_size(code: Int) -> Int {
  if code == KME_CRV_P256 {
    return 32;
  }
  if code == KME_CRV_P384 {
    return 48;
  }
  if code == KME_CRV_P521 {
    return 66;
  }
  if code == KME_CRV_SECP256K1 {
    return 32;
  }
  if code == KME_CRV_ED25519 {
    return 32;
  }
  if code == KME_CRV_X25519 {
    return 32;
  }
  if code == KME_CRV_ED448 {
    return 57;
  }
  if code == KME_CRV_X448 {
    return 56;
  }
  return 0;
}

// Curve family: 1 = EC curves, 2 = OKP curves, 0 = unknown.
fn _crv_family(code: Int) -> Int {
  if code == KME_CRV_P256 {
    return 1;
  }
  if code == KME_CRV_P384 {
    return 1;
  }
  if code == KME_CRV_P521 {
    return 1;
  }
  if code == KME_CRV_SECP256K1 {
    return 1;
  }
  if code == KME_CRV_ED25519 {
    return 2;
  }
  if code == KME_CRV_X25519 {
    return 2;
  }
  if code == KME_CRV_ED448 {
    return 2;
  }
  if code == KME_CRV_X448 {
    return 2;
  }
  return 0;
}

// True when `name` is one of the ten JWK parameter member names supported
// here: n, e, d, p, q, dp, dq, qi (RSA), x, y (EC/OKP), k (oct).
fn _is_param_name(name: Str) -> Bool {
  if _streq(name, "n") {
    return true;
  }
  if _streq(name, "e") {
    return true;
  }
  if _streq(name, "d") {
    return true;
  }
  if _streq(name, "p") {
    return true;
  }
  if _streq(name, "q") {
    return true;
  }
  if _streq(name, "dp") {
    return true;
  }
  if _streq(name, "dq") {
    return true;
  }
  if _streq(name, "qi") {
    return true;
  }
  if _streq(name, "x") {
    return true;
  }
  if _streq(name, "y") {
    return true;
  }
  if _streq(name, "k") {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Base64 (self-contained; unpadded encode, tolerant/strict decode)
// --------------------------------------------------

// Base64 digit value (0..63) of one encoded byte under `mode`; -1 when the
// byte is not in the alphabet. '=' (61) is handled by the caller.
fn _b64_digit(b: Int, mode: Int) -> Int {
  if b >= 65 && b <= 90 {
    return b - 65;
  }
  if b >= 97 && b <= 122 {
    return b - 97 + 26;
  }
  if b >= 48 && b <= 57 {
    return b - 48 + 52;
  }
  if mode == KME_B64_STD {
    if b == 43 {
      return 62;
    }
    if b == 47 {
      return 63;
    }
  } else {
    if b == 45 {
      return 62;
    }
    if b == 95 {
      return 63;
    }
  }
  return -1;
}

// Emit data[start, start + n) as UNPADDED base64 under `mode` into `out`.
fn _b64_encode_into(data: &Vec[UInt8], start: Int, n: Int, mode: Int, out: &mut Vec[UInt8]) {
  let std_alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let url_alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  var alpha: Str = url_alpha;
  if mode == KME_B64_STD {
    alpha = std_alpha;
  }
  var i = 0;
  while i + 3 <= n {
    let b0: Int = _byte(data, start + i);
    let b1: Int = _byte(data, start + i + 1);
    let b2: Int = _byte(data, start + i + 2);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1 / 16));
    out.push(string.byte_at(alpha, (b1 % 16) * 4 + b2 / 64));
    out.push(string.byte_at(alpha, b2 % 64));
    i = i + 3;
  }
  let rem = n - i;
  if rem == 1 {
    let b0: Int = _byte(data, start + i);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16));
  } elif rem == 2 {
    let b0: Int = _byte(data, start + i);
    let b1: Int = _byte(data, start + i + 1);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1 / 16));
    out.push(string.byte_at(alpha, (b1 % 16) * 4));
  }
}

// Emit data[start, start + n) as canonical PADDED standard base64 into `out`,
// wrapped with LF after every 64 characters (and after a non-empty final
// partial line). Empty input emits nothing.
fn _b64_emit_wrapped(data: &Vec[UInt8], start: Int, n: Int, out: &mut Vec[UInt8]) {
  let alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  var col = 0;
  var i = 0;
  while i + 3 <= n {
    let b0: Int = _byte(data, start + i);
    let b1: Int = _byte(data, start + i + 1);
    let b2: Int = _byte(data, start + i + 2);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1 / 16));
    out.push(string.byte_at(alpha, (b1 % 16) * 4 + b2 / 64));
    out.push(string.byte_at(alpha, b2 % 64));
    col = col + 4;
    if col == 64 {
      out.push(10 as UInt8);
      col = 0;
    }
    i = i + 3;
  }
  let rem = n - i;
  if rem == 1 {
    let b0: Int = _byte(data, start + i);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16));
    out.push(61 as UInt8);
    out.push(61 as UInt8);
    col = col + 4;
  } elif rem == 2 {
    let b0: Int = _byte(data, start + i);
    let b1: Int = _byte(data, start + i + 1);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1 / 16));
    out.push(string.byte_at(alpha, (b1 % 16) * 4));
    out.push(61 as UInt8);
    col = col + 4;
  }
  if col > 0 {
    out.push(10 as UInt8);
  }
}

// Decode the base64 characters [start, end) of `chars` under `mode`.
//
// strict=false (base64url / JWK): padding is optional but when present must be
// a final run of 1..2 '=' matching the data remainder; the character count
// before padding (or the whole count when unpadded) may be any length except
// n % 4 == 1; padded groups must carry zero unused low bits.
//
// strict=true (PEM): the character count must be a multiple of 4 and padding
// is mandatory when the data remainder needs it (canonical RFC 7468 bodies).
//
// Err messages are `prefix` + "invalid character" / "bad length" /
// "bad padding" / "non-canonical trailing bits", each with the byte offset.
fn _b64_decode_range(chars: &Vec[UInt8], start: Int, end: Int, mode: Int, strict: Bool, prefix: Str) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let n = end - start;
  if n == 0 {
    return _ok_bytes(out);
  }
  var first_pad = -1;
  var k = 0;
  while k < n {
    if _byte(chars, start + k) == 61 {
      first_pad = k;
      break;
    }
    k = k + 1;
  }
  var d = n;
  if first_pad >= 0 {
    d = first_pad;
    var j = first_pad;
    while j < n {
      if _byte(chars, start + j) != 61 {
        return _err_bytes(_at(prefix + "bad padding", start + j));
      }
      j = j + 1;
    }
  }
  k = 0;
  while k < d {
    if _b64_digit(_byte(chars, start + k), mode) < 0 {
      return _err_bytes(_at(prefix + "invalid character", start + k));
    }
    k = k + 1;
  }
  if strict {
    if n % 4 != 0 {
      return _err_bytes(_at(prefix + "bad length", start));
    }
  } else {
    if first_pad < 0 && n % 4 == 1 {
      return _err_bytes(_at(prefix + "bad length", start));
    }
  }
  if first_pad >= 0 {
    let p = n - d;
    if p != 1 && p != 2 {
      return _err_bytes(_at(prefix + "bad padding", start + first_pad));
    }
    if p == 1 && d % 4 != 3 {
      return _err_bytes(_at(prefix + "bad padding", start + first_pad));
    }
    if p == 2 && d % 4 != 2 {
      return _err_bytes(_at(prefix + "bad padding", start + first_pad));
    }
  }
  var acc = 0;
  var count = 0;
  k = 0;
  while k < d {
    acc = acc * 64 + _b64_digit(_byte(chars, start + k), mode);
    count = count + 1;
    if count == 4 {
      out.push((acc / 65536) as UInt8);
      out.push(((acc / 256) % 256) as UInt8);
      out.push((acc % 256) as UInt8);
      acc = 0;
      count = 0;
    }
    k = k + 1;
  }
  if count == 2 {
    if acc % 16 != 0 {
      return _err_bytes(_at(prefix + "non-canonical trailing bits", start + d));
    }
    out.push((acc / 16) as UInt8);
  } elif count == 3 {
    if acc % 4 != 0 {
      return _err_bytes(_at(prefix + "non-canonical trailing bits", start + d));
    }
    out.push((acc / 1024) as UInt8);
    out.push(((acc / 4) % 256) as UInt8);
  } elif count != 0 {
    return _err_bytes(_at(prefix + "bad length", start));
  }
  return _ok_bytes(out);
}

/// Encode bytes as unpadded base64url (RFC 4648 section 5, no '=').
/// Returns: the encoded text ("" for empty input). Never fails.
/// Complexity: O(data.len()).
pub fn kme_base64url_encode(data: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  _b64_encode_into(data, 0, data.len(), KME_B64_URL, &mut out);
  return builder.sb_to_str(&out);
}

/// Decode base64url text (RFC 4648 section 5). Padding is tolerated: a final
/// run of 1..2 '=' is accepted and must match the data remainder; unpadded
/// input of length n is accepted unless n % 4 == 1. Characters outside
/// A-Z a-z 0-9 - _ and '=' are rejected, as are misplaced/oversized padding
/// and padded groups with non-zero unused low bits (canonical check).
/// Returns: Ok(bytes); Err("keymgmt: base64url ...") with the byte offset of
/// the first violation, from the module error catalog in SPEC.md.
/// Complexity: O(text.len()).
pub fn kme_base64url_decode(text: Str) -> Result[Vec[UInt8], Str] {
  var chars = _bytes_of_str(text);
  return _b64_decode_range(&chars, 0, chars.len(), KME_B64_URL, false, "keymgmt: base64url ");
}

// --------------------------------------------------
//  JSON scanner (bounded; JWK/JWKS only)
// --------------------------------------------------

// Skip space, tab, LF and CR at or after `pos`.
fn _json_ws(data: &Vec[UInt8], pos: Int, end: Int) -> Int {
  var i = pos;
  while i < end {
    let b: Int = _byte(data, i);
    if b == 32 || b == 9 || b == 10 || b == 13 {
      i = i + 1;
    } else {
      return i;
    }
  }
  return i;
}

// Hex digit value of one byte (0..15), or -1.
fn _hexval(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if b >= 97 && b <= 102 {
    return b - 97 + 10;
  }
  if b >= 65 && b <= 70 {
    return b - 65 + 10;
  }
  return -1;
}

// Append the UTF-8 encoding of code point `cp` to `out` (cp >= 1; NUL is
// rejected by the caller).
fn _utf8_push(out: &mut Vec[UInt8], cp: Int) {
  if cp < 128 {
    out.push(cp as UInt8);
  } elif cp < 2048 {
    out.push((192 + cp / 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
  } elif cp < 65536 {
    out.push((224 + cp / 4096) as UInt8);
    out.push((128 + (cp / 64) % 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
  } else {
    out.push((240 + cp / 262144) as UInt8);
    out.push((128 + (cp / 4096) % 64) as UInt8);
    out.push((128 + (cp / 64) % 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
  }
}

// Read exactly four hex digits at `pos` as an Int (0..65535).
fn _json_hex4(data: &Vec[UInt8], pos: Int, end: Int) -> Result[Int, Str] {
  if pos + 4 > end {
    return _err_int(_at("keymgmt: json invalid unicode escape", pos));
  }
  var v = 0;
  var i = 0;
  while i < 4 {
    let h = _hexval(_byte(data, pos + i));
    if h < 0 {
      return _err_int(_at("keymgmt: json invalid unicode escape", pos));
    }
    v = v * 16 + h;
    i = i + 1;
  }
  return _ok_int(v);
}

// Decode one JSON escape sequence at `pos` (the backslash) into `out`;
// returns the offset just past the escape. Supports " \ / b f n r t and
// \uXXXX with surrogate pairs. NUL and lone surrogates are rejected.
fn _json_escape(data: &Vec[UInt8], pos: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if pos + 1 >= end {
    return _err_int(_at("keymgmt: json invalid escape", pos));
  }
  let e: Int = _byte(data, pos + 1);
  if e == 34 {
    out.push(34 as UInt8);
    return _ok_int(pos + 2);
  }
  if e == 92 {
    out.push(92 as UInt8);
    return _ok_int(pos + 2);
  }
  if e == 47 {
    out.push(47 as UInt8);
    return _ok_int(pos + 2);
  }
  if e == 98 {
    out.push(8 as UInt8);
    return _ok_int(pos + 2);
  }
  if e == 102 {
    out.push(12 as UInt8);
    return _ok_int(pos + 2);
  }
  if e == 110 {
    out.push(10 as UInt8);
    return _ok_int(pos + 2);
  }
  if e == 114 {
    out.push(13 as UInt8);
    return _ok_int(pos + 2);
  }
  if e == 116 {
    out.push(9 as UInt8);
    return _ok_int(pos + 2);
  }
  if e == 117 {
    let r1 = _json_hex4(data, pos + 2, end);
    if !r1.is_ok {
      return _err_int(r1.error);
    }
    let h1: Int = r1.value;
    var cp = h1;
    var next = pos + 6;
    if h1 >= 55296 && h1 <= 56319 {
      if next + 1 >= end {
        return _err_int(_at("keymgmt: json invalid surrogate", pos));
      }
      if _byte(data, next) != 92 || _byte(data, next + 1) != 117 {
        return _err_int(_at("keymgmt: json invalid surrogate", pos));
      }
      let r2 = _json_hex4(data, next + 2, end);
      if !r2.is_ok {
        return _err_int(r2.error);
      }
      let h2: Int = r2.value;
      if h2 < 56320 || h2 > 57343 {
        return _err_int(_at("keymgmt: json invalid surrogate", pos));
      }
      cp = 65536 + (h1 - 55296) * 1024 + (h2 - 56320);
      next = next + 6;
    } elif h1 >= 56320 && h1 <= 57343 {
      return _err_int(_at("keymgmt: json invalid surrogate", pos));
    }
    if cp == 0 {
      return _err_int(_at("keymgmt: json NUL character", pos));
    }
    _utf8_push(out, cp);
    return _ok_int(next);
  }
  return _err_int(_at("keymgmt: json invalid escape", pos));
}

// Parse one JSON string at `pos` (which must point at '"'), appending the
// decoded bytes to `out`; returns the offset just past the closing quote.
fn _json_string(data: &Vec[UInt8], pos: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if pos >= end || _byte(data, pos) != 34 {
    return _err_int(_at("keymgmt: json expected string", pos));
  }
  var i = pos + 1;
  var done = false;
  while !done {
    if i >= end {
      return _err_int(_at("keymgmt: json unterminated string", pos));
    }
    let b: Int = _byte(data, i);
    if b == 34 {
      done = true;
      i = i + 1;
    } elif b == 92 {
      let er = _json_escape(data, i, end, out);
      if !er.is_ok {
        return _err_int(er.error);
      }
      i = er.value;
    } elif b < 32 {
      return _err_int(_at("keymgmt: json control character in string", i));
    } else {
      out.push(data[i]);
      i = i + 1;
    }
  }
  return _ok_int(i);
}

// Skip one JSON number at `pos`; returns the offset just past it.
fn _json_skip_number(data: &Vec[UInt8], pos: Int, end: Int) -> Result[Int, Str] {
  var i = pos;
  if i < end && _byte(data, i) == 45 {
    i = i + 1;
  }
  if i >= end {
    return _err_int(_at("keymgmt: json invalid number", pos));
  }
  let d0: Int = _byte(data, i);
  if d0 == 48 {
    i = i + 1;
  } elif d0 >= 49 && d0 <= 57 {
    var more = true;
    while more && i < end {
      let d: Int = _byte(data, i);
      if d >= 48 && d <= 57 {
        i = i + 1;
      } else {
        more = false;
      }
    }
  } else {
    return _err_int(_at("keymgmt: json invalid number", pos));
  }
  if i < end && _byte(data, i) == 46 {
    i = i + 1;
    var frac = 0;
    var more = true;
    while more && i < end {
      let d: Int = _byte(data, i);
      if d >= 48 && d <= 57 {
        i = i + 1;
        frac = frac + 1;
      } else {
        more = false;
      }
    }
    if frac == 0 {
      return _err_int(_at("keymgmt: json invalid number", pos));
    }
  }
  if i < end {
    let ex: Int = _byte(data, i);
    if ex == 101 || ex == 69 {
      i = i + 1;
      if i < end && (_byte(data, i) == 43 || _byte(data, i) == 45) {
        i = i + 1;
      }
      var digits = 0;
      var more = true;
      while more && i < end {
        let d: Int = _byte(data, i);
        if d >= 48 && d <= 57 {
          i = i + 1;
          digits = digits + 1;
        } else {
          more = false;
        }
      }
      if digits == 0 {
        return _err_int(_at("keymgmt: json invalid number", pos));
      }
    }
  }
  return _ok_int(i);
}

// Skip any JSON value at `pos`, returning the offset just past it. `depth`
// bounds nesting; objects and arrays recurse.
fn _json_skip_value(data: &Vec[UInt8], pos: Int, end: Int, depth: Int) -> Result[Int, Str] {
  if depth > KME_JSON_MAX_DEPTH {
    return _err_int(_at("keymgmt: json nesting too deep", pos));
  }
  var i = _json_ws(data, pos, end);
  if i >= end {
    return _err_int(_at("keymgmt: json invalid value", i));
  }
  let b: Int = _byte(data, i);
  if b == 34 {
    var scratch = Vec[UInt8].new();
    return _json_string(data, i, end, &mut scratch);
  }
  if b == 123 {
    var j = _json_ws(data, i + 1, end);
    if j < end && _byte(data, j) == 125 {
      return _ok_int(j + 1);
    }
    var done = false;
    while !done {
      var name = Vec[UInt8].new();
      let nr = _json_string(data, j, end, &mut name);
      if !nr.is_ok {
        return _err_int(nr.error);
      }
      j = _json_ws(data, nr.value, end);
      if j >= end || _byte(data, j) != 58 {
        return _err_int(_at("keymgmt: json expected colon", j));
      }
      let vr = _json_skip_value(data, j + 1, end, depth + 1);
      if !vr.is_ok {
        return _err_int(vr.error);
      }
      j = _json_ws(data, vr.value, end);
      if j >= end {
        return _err_int(_at("keymgmt: json unterminated object", i));
      }
      let c: Int = _byte(data, j);
      if c == 44 {
        j = _json_ws(data, j + 1, end);
      } elif c == 125 {
        j = j + 1;
        done = true;
      } else {
        return _err_int(_at("keymgmt: json expected comma or brace", j));
      }
    }
    return _ok_int(j);
  }
  if b == 91 {
    var j = _json_ws(data, i + 1, end);
    if j < end && _byte(data, j) == 93 {
      return _ok_int(j + 1);
    }
    var done = false;
    while !done {
      let vr = _json_skip_value(data, j, end, depth + 1);
      if !vr.is_ok {
        return _err_int(vr.error);
      }
      j = _json_ws(data, vr.value, end);
      if j >= end {
        return _err_int(_at("keymgmt: json unterminated array", i));
      }
      let c: Int = _byte(data, j);
      if c == 44 {
        j = _json_ws(data, j + 1, end);
      } elif c == 93 {
        j = j + 1;
        done = true;
      } else {
        return _err_int(_at("keymgmt: json expected comma or bracket", j));
      }
    }
    return _ok_int(j);
  }
  if b == 116 {
    if i + 4 <= end && _byte(data, i + 1) == 114 && _byte(data, i + 2) == 117 && _byte(data, i + 3) == 101 {
      return _ok_int(i + 4);
    }
    return _err_int(_at("keymgmt: json invalid literal", i));
  }
  if b == 102 {
    if i + 5 <= end && _byte(data, i + 1) == 97 && _byte(data, i + 2) == 108 && _byte(data, i + 3) == 115 && _byte(data, i + 4) == 101 {
      return _ok_int(i + 5);
    }
    return _err_int(_at("keymgmt: json invalid literal", i));
  }
  if b == 110 {
    if i + 4 <= end && _byte(data, i + 1) == 117 && _byte(data, i + 2) == 108 && _byte(data, i + 3) == 108 {
      return _ok_int(i + 4);
    }
    return _err_int(_at("keymgmt: json invalid literal", i));
  }
  if b == 45 || (b >= 48 && b <= 57) {
    return _json_skip_number(data, i, end);
  }
  return _err_int(_at("keymgmt: json invalid value", i));
}

// Parse a JSON array of strings at `pos` into `out` (appended in order);
// returns the offset just past ']'. Empty arrays are allowed here; callers
// decide whether that is meaningful.
fn _json_string_array(data: &Vec[UInt8], pos: Int, end: Int, out: &mut Vec[Str]) -> Result[Int, Str] {
  var i = _json_ws(data, pos, end);
  if i >= end || _byte(data, i) != 91 {
    return _err_int(_at("keymgmt: json expected array", i));
  }
  i = _json_ws(data, i + 1, end);
  if i < end && _byte(data, i) == 93 {
    return _ok_int(i + 1);
  }
  var done = false;
  while !done {
    var ebuf = Vec[UInt8].new();
    let sr = _json_string(data, i, end, &mut ebuf);
    if !sr.is_ok {
      return _err_int(sr.error);
    }
    let s: Str = builder.sb_to_str(&ebuf);
    out.push(s);
    i = _json_ws(data, sr.value, end);
    if i >= end {
      return _err_int(_at("keymgmt: json unterminated array", pos));
    }
    let c: Int = _byte(data, i);
    if c == 44 {
      i = _json_ws(data, i + 1, end);
    } elif c == 93 {
      i = i + 1;
      done = true;
    } else {
      return _err_int(_at("keymgmt: json expected comma or bracket", i));
    }
  }
  return _ok_int(i);
}

// Append `,"name":` (no leading comma for the first member) to `out`.
fn _json_member(out: &mut Vec[UInt8], n: Int, name: Str) {
  if n > 0 {
    out.push(44 as UInt8);
  }
  _json_quote_into(out, name);
  out.push(58 as UInt8);
}

// Append `"s"` to `out`, escaping '"', '\' and control bytes (as \u00xx).
fn _json_quote_into(out: &mut Vec[UInt8], s: Str) {
  let hexa = "0123456789abcdef";
  out.push(34 as UInt8);
  var i = 0;
  while i < s.len() {
    let b = _tb(s, i);
    if b == 34 {
      out.push(92 as UInt8);
      out.push(34 as UInt8);
    } elif b == 92 {
      out.push(92 as UInt8);
      out.push(92 as UInt8);
    } elif b < 32 {
      out.push(92 as UInt8);
      out.push(117 as UInt8);
      out.push(48 as UInt8);
      out.push(48 as UInt8);
      out.push(string.byte_at(hexa, b / 16));
      out.push(string.byte_at(hexa, b % 16));
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  out.push(34 as UInt8);
}

// --------------------------------------------------
//  DER TLV walker (X.690; definite lengths, offsets)
// --------------------------------------------------

// Decode a DER length field at `off`. Short form 0x00..0x7F; long form
// 0x80|n with n in 1..8 minimal big-endian bytes. The indefinite form and
// non-minimal long forms are rejected.
fn _der_length(data: &Vec[UInt8], off: Int) -> Result[KmeLength, Str] {
  if off < 0 {
    return _err_len("keymgmt: der negative offset");
  }
  if off >= data.len() {
    return _err_len(_at("keymgmt: der truncated length", off));
  }
  let b: Int = _byte(data, off);
  if b < 128 {
    return _ok_len(KmeLength{ len: b; size: 1; });
  }
  let n: Int = b - 128;
  if n == 0 {
    return _err_len(_at("keymgmt: der indefinite length", off));
  }
  if n > 8 {
    return _err_len(_at("keymgmt: der length overflow", off));
  }
  if off + 1 + n > data.len() {
    return _err_len(_at("keymgmt: der truncated length", off));
  }
  var v = 0;
  var i = 0;
  while i < n {
    let x: Int = _byte(data, off + 1 + i);
    if i == 0 && x == 0 {
      return _err_len(_at("keymgmt: der non-minimal length", off));
    }
    v = v * 256 + x;
    if v < 0 {
      return _err_len(_at("keymgmt: der length overflow", off));
    }
    i = i + 1;
  }
  if v < 128 {
    return _err_len(_at("keymgmt: der non-minimal length", off));
  }
  return _ok_len(KmeLength{ len: v; size: 1 + n; });
}

// Decode one DER TLV at `off` and check that the declared content fits the
// buffer. The high-tag-number form is decoded; overflow and non-minimal tag
// forms are rejected.
fn _der_tlv(data: &Vec[UInt8], off: Int) -> Result[KmeTlv, Str] {
  if off < 0 {
    return _err_tlv("keymgmt: der negative offset");
  }
  if off >= data.len() {
    return _err_tlv(_at("keymgmt: der truncated tag", off));
  }
  let b: Int = _byte(data, off);
  let tclass: Int = b / 64;
  var constructed = false;
  if (b / 32) % 2 == 1 {
    constructed = true;
  }
  let low: Int = b % 32;
  var tag_number: Int = low;
  var tag_end = off + 1;
  if low == 31 {
    var p = off + 1;
    var first = true;
    var done = false;
    var arcs = 0;
    while !done {
      if p >= data.len() {
        return _err_tlv(_at("keymgmt: der truncated tag", off));
      }
      let x: Int = _byte(data, p);
      if first && x == 128 {
        return _err_tlv(_at("keymgmt: der non-minimal tag", off));
      }
      if first {
        tag_number = 0;
      }
      tag_number = tag_number * 128 + (x % 128);
      if tag_number < 0 {
        return _err_tlv(_at("keymgmt: der tag number overflow", off));
      }
      if x < 128 {
        done = true;
      } else {
        first = false;
        arcs = arcs + 1;
        if arcs > 8 {
          return _err_tlv(_at("keymgmt: der tag number overflow", off));
        }
      }
      p = p + 1;
    }
    tag_end = p;
  }
  let lr = _der_length(data, tag_end);
  if !lr.is_ok {
    return _err_tlv(lr.error);
  }
  let l: KmeLength = lr.value;
  let content = tag_end + l.size;
  let len: Int = l.len;
  if len > data.len() - content {
    return _err_tlv(_at("keymgmt: der truncated value", off));
  }
  return _ok_tlv(KmeTlv{ tag_class: tclass; constructed: constructed; tag_number: tag_number; header: off; content: content; len: len; next: content + len });
}

// Decode one DER TLV at `off` that must not extend past `end` (the end of an
// enclosing container).
fn _der_tlv_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[KmeTlv, Str] {
  if off < 0 {
    return _err_tlv("keymgmt: der negative offset");
  }
  let r = _der_tlv(data, off);
  if !r.is_ok {
    return _err_tlv(r.error);
  }
  let t: KmeTlv = r.value;
  if t.next > end {
    return _err_tlv(_at("keymgmt: der value overruns container", off));
  }
  return _ok_tlv(t);
}

/// Decode a DER length field at `off` (short or minimal long form).
/// Returns: Ok(KmeLength); Err("keymgmt: der ...") with the offset from the
/// module error catalog.
/// Complexity: O(length bytes).
pub fn kme_der_length(data: &Vec[UInt8], off: Int) -> Result[KmeLength, Str] {
  return _der_length(data, off);
}

/// Decode one DER TLV at `off` against the whole buffer.
/// Returns: Ok(KmeTlv) with tag class / constructed / tag number and the
/// header, content, len and next offsets; Err("keymgmt: der ...").
/// Complexity: O(tag + length bytes).
pub fn kme_der_tlv(data: &Vec[UInt8], off: Int) -> Result[KmeTlv, Str] {
  return _der_tlv(data, off);
}

/// Decode one DER TLV at `off` that must end at or before `end`.
/// Returns: Ok(KmeTlv); Err("keymgmt: der value overruns container ...") or
/// the kme_der_tlv catalog.
/// Complexity: O(tag + length bytes).
pub fn kme_der_tlv_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[KmeTlv, Str] {
  return _der_tlv_in(data, off, end);
}

// Non-negative INTEGER content value of data[start, start+n): non-empty, at
// most 8 bytes, no sign bit, minimal encoding.
fn _der_uint_content(data: &Vec[UInt8], start: Int, n: Int, base: Int) -> Result[Int, Str] {
  if n < 1 {
    return _err_int(_at("keymgmt: der empty integer", base));
  }
  if n > 8 {
    return _err_int(_at("keymgmt: der integer overflow", base));
  }
  let b0: Int = _byte(data, start);
  if b0 >= 128 {
    return _err_int(_at("keymgmt: der negative integer", base));
  }
  if n > 1 {
    let b1: Int = _byte(data, start + 1);
    if b0 == 0 && b1 < 128 {
      return _err_int(_at("keymgmt: der non-minimal integer", base));
    }
  }
  var v = 0;
  var i = 0;
  while i < n {
    v = v * 256 + _byte(data, start + i);
    i = i + 1;
  }
  return _ok_int(v);
}

// Dotted string of an OBJECT IDENTIFIER content field [start, start+n).
fn _oid_content(data: &Vec[UInt8], start: Int, n: Int, base: Int) -> Result[Str, Str] {
  if n < 1 {
    return _err_str(_at("keymgmt: der empty oid", base));
  }
  let b0: Int = _byte(data, start);
  if b0 >= 120 {
    return _err_str(_at("keymgmt: der bad oid", base));
  }
  var sb = builder.sb_new();
  builder.sb_push_int(&mut sb, b0 / 40);
  builder.sb_push_byte(&mut sb, 46 as UInt8);
  builder.sb_push_int(&mut sb, b0 % 40);
  var i = start + 1;
  let stop = start + n;
  var arcs = 2;
  while i < stop {
    var arc = 0;
    var count = 0;
    var done = false;
    while !done {
      if i >= stop {
        return _err_str(_at("keymgmt: der truncated oid", base));
      }
      let x: Int = _byte(data, i);
      if count == 0 && x == 128 {
        return _err_str(_at("keymgmt: der non-minimal oid arc", i));
      }
      arc = arc * 128 + (x % 128);
      if arc < 0 {
        return _err_str(_at("keymgmt: der oid overflow", base));
      }
      if x < 128 {
        done = true;
      } else {
        count = count + 1;
        if count > 8 {
          return _err_str(_at("keymgmt: der oid overflow", base));
        }
      }
      i = i + 1;
    }
    builder.sb_push_byte(&mut sb, 46 as UInt8);
    builder.sb_push_int(&mut sb, arc);
    arcs = arcs + 1;
    if arcs > 64 {
      return _err_str(_at("keymgmt: der oid too long", base));
    }
  }
  return _ok_str(builder.sb_to_str(&sb));
}

/// Decode an OBJECT IDENTIFIER TLV at `off` into a dotted decimal string.
/// Returns: Ok(KmeOid) with `value`, `header` (TLV offset) and `next`;
/// Err("keymgmt: der ...") from the catalog.
/// Complexity: O(content bytes).
pub fn kme_der_oid(data: &Vec[UInt8], off: Int) -> Result[KmeOid, Str] {
  let tr = _der_tlv(data, off);
  if !tr.is_ok {
    return _err_oid(tr.error);
  }
  let t: KmeTlv = tr.value;
  if !_tlv_is(&t, KME_CLASS_UNIVERSAL, KME_TAG_OID) {
    return _err_oid(_at("keymgmt: der tag mismatch", off));
  }
  let vr = _oid_content(data, t.content, t.len, t.header);
  if !vr.is_ok {
    return _err_oid(vr.error);
  }
  let v: Str = vr.value;
  return _ok_oid(KmeOid{ value: v; header: t.header; next: t.next });
}

// Decode an AlgorithmIdentifier ::= SEQUENCE { algorithm OID, parameters ANY
// OPTIONAL } at `off` that must end at or before `end`.
fn _der_alg_id(data: &Vec[UInt8], off: Int, end: Int) -> Result[KmeAlgorithm, Str] {
  let tr = _der_tlv_in(data, off, end);
  if !tr.is_ok {
    return _err_alg(tr.error);
  }
  let t: KmeTlv = tr.value;
  if !_tlv_is(&t, KME_CLASS_UNIVERSAL, KME_TAG_SEQUENCE) {
    return _err_alg(_at("keymgmt: der tag mismatch", off));
  }
  let ir = kme_der_oid(data, t.content);
  if !ir.is_ok {
    return _err_alg(ir.error);
  }
  let o: KmeOid = ir.value;
  if o.next > t.next {
    return _err_alg(_at("keymgmt: der value overruns container", t.content));
  }
  var params_present = false;
  var params_offset = -1;
  var params_len = 0;
  if o.next < t.next {
    let pr = _der_tlv_in(data, o.next, t.next);
    if !pr.is_ok {
      return _err_alg(pr.error);
    }
    let p: KmeTlv = pr.value;
    params_present = true;
    params_offset = p.header;
    params_len = p.next - p.header;
    if p.next != t.next {
      return _err_alg(_at("keymgmt: der trailing data", p.next));
    }
  }
  return _ok_alg(KmeAlgorithm{ oid: o.value; oid_offset: o.header; params_present: params_present; params_offset: params_offset; params_len: params_len; next: t.next });
}

/// Decode an AlgorithmIdentifier (SEQUENCE { OID, parameters OPTIONAL }) at
/// `off` that must end at or before `end`.
/// Returns: Ok(KmeAlgorithm); Err("keymgmt: der ...").
/// Complexity: O(algorithm bytes).
pub fn kme_der_alg_id(data: &Vec[UInt8], off: Int, end: Int) -> Result[KmeAlgorithm, Str] {
  return _der_alg_id(data, off, end);
}

// --------------------------------------------------
//  PKCS#8 / SPKI structures
// --------------------------------------------------

/// Parse a DER PrivateKeyInfo (RFC 5958): SEQUENCE { version INTEGER (0/1),
/// privateKeyAlgorithm AlgorithmIdentifier, privateKey OCTET STRING,
/// attributes [0] IMPLICIT OPTIONAL }. The whole buffer must be consumed.
/// Returns: Ok(KmePrivateKeyInfo) with byte offsets; Err("keymgmt: der ...")
/// naming the offending offset.
/// Complexity: O(buffer).
pub fn kme_pkcs8_parse(data: &Vec[UInt8]) -> Result[KmePrivateKeyInfo, Str] {
  let tr = _der_tlv_in(data, 0, data.len());
  if !tr.is_ok {
    return _err_pki(tr.error);
  }
  let t: KmeTlv = tr.value;
  if !_tlv_is(&t, KME_CLASS_UNIVERSAL, KME_TAG_SEQUENCE) {
    return _err_pki(_at("keymgmt: der expected sequence", 0));
  }
  let vr = _der_tlv_in(data, t.content, t.next);
  if !vr.is_ok {
    return _err_pki(vr.error);
  }
  let v: KmeTlv = vr.value;
  if !_tlv_is(&v, KME_CLASS_UNIVERSAL, KME_TAG_INTEGER) {
    return _err_pki(_at("keymgmt: der tag mismatch", v.header));
  }
  let verr = _der_uint_content(data, v.content, v.len, v.header);
  if !verr.is_ok {
    return _err_pki(verr.error);
  }
  let version: Int = verr.value;
  if version != 0 && version != 1 {
    return _err_pki(_at("keymgmt: der bad pkcs8 version", v.header));
  }
  let ar = _der_alg_id(data, v.next, t.next);
  if !ar.is_ok {
    return _err_pki(ar.error);
  }
  let alg: KmeAlgorithm = ar.value;
  let kr = _der_tlv_in(data, alg.next, t.next);
  if !kr.is_ok {
    return _err_pki(kr.error);
  }
  let kt: KmeTlv = kr.value;
  if !_tlv_is(&kt, KME_CLASS_UNIVERSAL, KME_TAG_OCTET_STRING) {
    return _err_pki(_at("keymgmt: der tag mismatch", kt.header));
  }
  var has_attributes = false;
  var attrs_offset = -1;
  var attrs_len = 0;
  var next = kt.next;
  if kt.next < t.next {
    let attr = _der_tlv_in(data, kt.next, t.next);
    if !attr.is_ok {
      return _err_pki(attr.error);
    }
    let a: KmeTlv = attr.value;
    if a.tag_class != KME_CLASS_CONTEXT || a.tag_number != 0 || !a.constructed {
      return _err_pki(_at("keymgmt: der trailing data", a.header));
    }
    has_attributes = true;
    attrs_offset = a.content;
    attrs_len = a.len;
    next = a.next;
  }
  if next != data.len() {
    return _err_pki(_at("keymgmt: der trailing data", next));
  }
  return _ok_pki(KmePrivateKeyInfo{ version: version; alg: alg; key_offset: kt.content; key_len: kt.len; key_tlv_offset: kt.header; has_attributes: has_attributes; attrs_offset: attrs_offset; attrs_len: attrs_len; next: next });
}

/// Parse a DER EncryptedPrivateKeyInfo: SEQUENCE { encryptionAlgorithm
/// AlgorithmIdentifier, encryptedData OCTET STRING }. The whole buffer must
/// be consumed.
/// Returns: Ok(KmeEncryptedPrivateKeyInfo); Err("keymgmt: der ...").
/// Complexity: O(buffer).
pub fn kme_pkcs8_encrypted_parse(data: &Vec[UInt8]) -> Result[KmeEncryptedPrivateKeyInfo, Str] {
  let tr = _der_tlv_in(data, 0, data.len());
  if !tr.is_ok {
    return _err_epki(tr.error);
  }
  let t: KmeTlv = tr.value;
  if !_tlv_is(&t, KME_CLASS_UNIVERSAL, KME_TAG_SEQUENCE) {
    return _err_epki(_at("keymgmt: der expected sequence", 0));
  }
  let ar = _der_alg_id(data, t.content, t.next);
  if !ar.is_ok {
    return _err_epki(ar.error);
  }
  let alg: KmeAlgorithm = ar.value;
  let dr = _der_tlv_in(data, alg.next, t.next);
  if !dr.is_ok {
    return _err_epki(dr.error);
  }
  let dt: KmeTlv = dr.value;
  if !_tlv_is(&dt, KME_CLASS_UNIVERSAL, KME_TAG_OCTET_STRING) {
    return _err_epki(_at("keymgmt: der tag mismatch", dt.header));
  }
  if dt.next != t.next {
    return _err_epki(_at("keymgmt: der trailing data", dt.next));
  }
  if t.next != data.len() {
    return _err_epki(_at("keymgmt: der trailing data", t.next));
  }
  return _ok_epki(KmeEncryptedPrivateKeyInfo{ alg: alg; data_offset: dt.content; data_len: dt.len; next: t.next });
}

/// Parse a DER SubjectPublicKeyInfo (RFC 5280): SEQUENCE { algorithm
/// AlgorithmIdentifier, subjectPublicKey BIT STRING }. The whole buffer must
/// be consumed. The BIT STRING unused-bit count must be 0..7 and at least one
/// content byte (the unused-bit count octet) must be present.
/// Returns: Ok(KmeSpki) with byte offsets; Err("keymgmt: der ...").
/// Complexity: O(buffer).
pub fn kme_spki_parse(data: &Vec[UInt8]) -> Result[KmeSpki, Str] {
  let tr = _der_tlv_in(data, 0, data.len());
  if !tr.is_ok {
    return _err_spki(tr.error);
  }
  let t: KmeTlv = tr.value;
  if !_tlv_is(&t, KME_CLASS_UNIVERSAL, KME_TAG_SEQUENCE) {
    return _err_spki(_at("keymgmt: der expected sequence", 0));
  }
  let ar = _der_alg_id(data, t.content, t.next);
  if !ar.is_ok {
    return _err_spki(ar.error);
  }
  let alg: KmeAlgorithm = ar.value;
  let br = _der_tlv_in(data, alg.next, t.next);
  if !br.is_ok {
    return _err_spki(br.error);
  }
  let bt: KmeTlv = br.value;
  if !_tlv_is(&bt, KME_CLASS_UNIVERSAL, KME_TAG_BIT_STRING) {
    return _err_spki(_at("keymgmt: der tag mismatch", bt.header));
  }
  if bt.len < 1 {
    return _err_spki(_at("keymgmt: der bad bit string", bt.header));
  }
  let unused: Int = _byte(data, bt.content);
  if unused > 7 {
    return _err_spki(_at("keymgmt: der bad bit string", bt.header));
  }
  if bt.next != t.next {
    return _err_spki(_at("keymgmt: der trailing data", bt.next));
  }
  if t.next != data.len() {
    return _err_spki(_at("keymgmt: der trailing data", t.next));
  }
  return _ok_spki(KmeSpki{ alg: alg; unused: unused; key_offset: bt.content + 1; key_len: bt.len - 1; next: t.next });
}

/// OID (dotted) of an AlgorithmIdentifier.
/// Complexity: O(1).
pub fn kme_alg_oid(a: &KmeAlgorithm) -> Str {
  let s: Str = a.oid;
  return s;
}

/// Structural algorithm name of an AlgorithmIdentifier OID ("" when the OID
/// is not in the table): rsaEncryption, id-ecPublicKey, P-256, P-384, P-521,
/// secp256k1, Ed25519, X25519, Ed448, X448.
/// Complexity: O(1).
pub fn kme_alg_name(a: &KmeAlgorithm) -> Str {
  let s: Str = a.oid;
  return kme_oid_name(s);
}

/// True when the AlgorithmIdentifier carries a parameters TLV.
/// Complexity: O(1).
pub fn kme_alg_params_present(a: &KmeAlgorithm) -> Bool {
  return a.params_present;
}

/// Offset of the parameters TLV (-1 when absent).
/// Complexity: O(1).
pub fn kme_alg_params_offset(a: &KmeAlgorithm) -> Int {
  return a.params_offset;
}

/// Total length in bytes of the parameters TLV, header included (0 when
/// absent).
/// Complexity: O(1).
pub fn kme_alg_params_len(a: &KmeAlgorithm) -> Int {
  return a.params_len;
}

/// Offset just past the AlgorithmIdentifier SEQUENCE.
/// Complexity: O(1).
pub fn kme_alg_next(a: &KmeAlgorithm) -> Int {
  return a.next;
}

// Decoded parameters OID of an AlgorithmIdentifier whose parameters TLV is
// an OBJECT IDENTIFIER and spans exactly `len` bytes; "" otherwise.
fn _alg_params_oid(data: &Vec[UInt8], present: Bool, off: Int, len: Int) -> Str {
  if !present {
    return "";
  }
  if off < 0 || len <= 0 {
    return "";
  }
  let r = kme_der_oid(data, off);
  if !r.is_ok {
    return "";
  }
  let o: KmeOid = r.value;
  if o.next != off + len {
    return "";
  }
  let s: Str = o.value;
  return s;
}

/// Parameters OID of an AlgorithmIdentifier when the parameters are an
/// OBJECT IDENTIFIER (namedCurve); "" otherwise (absent, NULL, SEQUENCE, or
/// malformed).
/// Complexity: O(parameters bytes).
pub fn kme_alg_param_oid(data: &Vec[UInt8], a: &KmeAlgorithm) -> Str {
  let present: Bool = a.params_present;
  let off: Int = a.params_offset;
  let len: Int = a.params_len;
  return _alg_params_oid(data, present, off, len);
}

/// PKCS#8 version (0 = v1, 1 = v2).
/// Complexity: O(1).
pub fn kme_pkcs8_version(p: &KmePrivateKeyInfo) -> Int {
  return p.version;
}

/// Algorithm OID (dotted) of a PrivateKeyInfo.
/// Complexity: O(1).
pub fn kme_pkcs8_alg_oid(p: &KmePrivateKeyInfo) -> Str {
  let s: Str = p.alg.oid;
  return s;
}

/// True when the PrivateKeyInfo algorithm carries parameters.
/// Complexity: O(1).
pub fn kme_pkcs8_alg_params_present(p: &KmePrivateKeyInfo) -> Bool {
  return p.alg.params_present;
}

/// Parameters OID of a PrivateKeyInfo algorithm (namedCurve); "" otherwise.
/// Complexity: O(parameters bytes).
pub fn kme_pkcs8_alg_param_oid(data: &Vec[UInt8], p: &KmePrivateKeyInfo) -> Str {
  let present: Bool = p.alg.params_present;
  let off: Int = p.alg.params_offset;
  let len: Int = p.alg.params_len;
  return _alg_params_oid(data, present, off, len);
}

/// Offset of the privateKey OCTET STRING content.
/// Complexity: O(1).
pub fn kme_pkcs8_key_offset(p: &KmePrivateKeyInfo) -> Int {
  return p.key_offset;
}

/// Length of the privateKey OCTET STRING content.
/// Complexity: O(1).
pub fn kme_pkcs8_key_len(p: &KmePrivateKeyInfo) -> Int {
  return p.key_len;
}

/// Copy of the privateKey OCTET STRING content bytes.
/// Complexity: O(key bytes).
pub fn kme_pkcs8_key_bytes(data: &Vec[UInt8], p: &KmePrivateKeyInfo) -> Vec[UInt8] {
  let off: Int = p.key_offset;
  let n: Int = p.key_len;
  return _copy_bytes_checked(data, off, n);
}

/// True when the PrivateKeyInfo carries the optional [0] attributes field.
/// Complexity: O(1).
pub fn kme_pkcs8_has_attributes(p: &KmePrivateKeyInfo) -> Bool {
  return p.has_attributes;
}

/// Offset of the [0] attributes content (-1 when absent).
/// Complexity: O(1).
pub fn kme_pkcs8_attrs_offset(p: &KmePrivateKeyInfo) -> Int {
  return p.attrs_offset;
}

/// Content length of the [0] attributes field (0 when absent).
/// Complexity: O(1).
pub fn kme_pkcs8_attrs_len(p: &KmePrivateKeyInfo) -> Int {
  return p.attrs_len;
}

/// Offset just past the outer PrivateKeyInfo SEQUENCE.
/// Complexity: O(1).
pub fn kme_pkcs8_next(p: &KmePrivateKeyInfo) -> Int {
  return p.next;
}

/// Encryption algorithm OID (dotted) of an EncryptedPrivateKeyInfo.
/// Complexity: O(1).
pub fn kme_epkcs8_alg_oid(e: &KmeEncryptedPrivateKeyInfo) -> Str {
  let s: Str = e.alg.oid;
  return s;
}

/// Parameters OID of the EncryptedPrivateKeyInfo algorithm; "" otherwise.
/// Complexity: O(parameters bytes).
pub fn kme_epkcs8_alg_param_oid(data: &Vec[UInt8], e: &KmeEncryptedPrivateKeyInfo) -> Str {
  let present: Bool = e.alg.params_present;
  let off: Int = e.alg.params_offset;
  let len: Int = e.alg.params_len;
  return _alg_params_oid(data, present, off, len);
}

/// Offset of the encryptedData OCTET STRING content.
/// Complexity: O(1).
pub fn kme_epkcs8_data_offset(e: &KmeEncryptedPrivateKeyInfo) -> Int {
  return e.data_offset;
}

/// Length of the encryptedData OCTET STRING content.
/// Complexity: O(1).
pub fn kme_epkcs8_data_len(e: &KmeEncryptedPrivateKeyInfo) -> Int {
  return e.data_len;
}

/// Copy of the encryptedData OCTET STRING content bytes.
/// Complexity: O(data bytes).
pub fn kme_epkcs8_data_bytes(data: &Vec[UInt8], e: &KmeEncryptedPrivateKeyInfo) -> Vec[UInt8] {
  let off: Int = e.data_offset;
  let n: Int = e.data_len;
  return _copy_bytes_checked(data, off, n);
}

/// Offset just past the outer EncryptedPrivateKeyInfo SEQUENCE.
/// Complexity: O(1).
pub fn kme_epkcs8_next(e: &KmeEncryptedPrivateKeyInfo) -> Int {
  return e.next;
}

/// Algorithm OID (dotted) of a SubjectPublicKeyInfo.
/// Complexity: O(1).
pub fn kme_spki_alg_oid(s: &KmeSpki) -> Str {
  let v: Str = s.alg.oid;
  return v;
}

/// True when the SPKI algorithm carries parameters.
/// Complexity: O(1).
pub fn kme_spki_alg_params_present(s: &KmeSpki) -> Bool {
  return s.alg.params_present;
}

/// Parameters OID of the SPKI algorithm (namedCurve); "" otherwise.
/// Complexity: O(parameters bytes).
pub fn kme_spki_alg_param_oid(data: &Vec[UInt8], s: &KmeSpki) -> Str {
  let present: Bool = s.alg.params_present;
  let off: Int = s.alg.params_offset;
  let len: Int = s.alg.params_len;
  return _alg_params_oid(data, present, off, len);
}

/// BIT STRING unused-bit count of the subjectPublicKey (0..7).
/// Complexity: O(1).
pub fn kme_spki_unused(s: &KmeSpki) -> Int {
  return s.unused;
}

/// Offset of the subjectPublicKey bytes (after the unused-bit count octet).
/// Complexity: O(1).
pub fn kme_spki_key_offset(s: &KmeSpki) -> Int {
  return s.key_offset;
}

/// Length of the subjectPublicKey bytes.
/// Complexity: O(1).
pub fn kme_spki_key_len(s: &KmeSpki) -> Int {
  return s.key_len;
}

/// Copy of the subjectPublicKey bytes.
/// Complexity: O(key bytes).
pub fn kme_spki_key_bytes(data: &Vec[UInt8], s: &KmeSpki) -> Vec[UInt8] {
  let off: Int = s.key_offset;
  let n: Int = s.key_len;
  return _copy_bytes_checked(data, off, n);
}

/// Offset just past the outer SubjectPublicKeyInfo SEQUENCE.
/// Complexity: O(1).
pub fn kme_spki_next(s: &KmeSpki) -> Int {
  return s.next;
}

// --------------------------------------------------
//  OID table
// --------------------------------------------------

/// Structural name of a known OID ("" when unknown): rsaEncryption,
/// id-ecPublicKey, P-256, P-384, P-521, secp256k1, Ed25519, X25519, Ed448,
/// X448.
/// Complexity: O(1).
pub fn kme_oid_name(oid: Str) -> Str {
  if _streq(oid, KME_OID_RSA_ENCRYPTION) {
    return "rsaEncryption";
  }
  if _streq(oid, KME_OID_EC_PUBLIC_KEY) {
    return "id-ecPublicKey";
  }
  if _streq(oid, KME_OID_P256) {
    return "P-256";
  }
  if _streq(oid, KME_OID_P384) {
    return "P-384";
  }
  if _streq(oid, KME_OID_P521) {
    return "P-521";
  }
  if _streq(oid, KME_OID_SECP256K1) {
    return "secp256k1";
  }
  if _streq(oid, KME_OID_ED25519) {
    return "Ed25519";
  }
  if _streq(oid, KME_OID_X25519) {
    return "X25519";
  }
  if _streq(oid, KME_OID_ED448) {
    return "Ed448";
  }
  if _streq(oid, KME_OID_X448) {
    return "X448";
  }
  return "";
}

/// Named curve OID of a canonical curve name ("P-256", "P-384", "P-521",
/// "secp256k1", "Ed25519", "X25519", "Ed448", "X448"); "" when unknown.
/// Complexity: O(1).
pub fn kme_curve_oid(name: Str) -> Str {
  return _curve_oid(_crv_code(name));
}

// --------------------------------------------------
//  JWK parse / render / accessors
// --------------------------------------------------

// Parse one JWK object occupying [start, end) of `data`.
fn _jwk_parse_range(data: &Vec[UInt8], start: Int, end: Int) -> Result[Jwk, Str] {
  var kty: Str = "";
  var kty_code = KME_KTY_UNKNOWN;
  var kid: Str = "";
  var use_val: Str = "";
  var alg: Str = "";
  var crv: Str = "";
  var x5u: Str = "";
  var x5t: Str = "";
  var x5t_s256: Str = "";
  var key_ops = Vec[Str].new();
  var x5c = Vec[Str].new();
  var n = Vec[UInt8].new();
  var e = Vec[UInt8].new();
  var d = Vec[UInt8].new();
  var p = Vec[UInt8].new();
  var q = Vec[UInt8].new();
  var dp = Vec[UInt8].new();
  var dq = Vec[UInt8].new();
  var qi = Vec[UInt8].new();
  var x = Vec[UInt8].new();
  var y = Vec[UInt8].new();
  var k = Vec[UInt8].new();
  var fields = Vec[Str].new();

  var pos = _json_ws(data, start, end);
  if pos >= end || _byte(data, pos) != 123 {
    return _err_jwk(_at("keymgmt: jwk expected object", pos));
  }
  pos = pos + 1;
  var first = true;
  var done = false;
  while !done {
    pos = _json_ws(data, pos, end);
    if pos >= end {
      return _err_jwk(_at("keymgmt: jwk unterminated object", start));
    }
    let b: Int = _byte(data, pos);
    if b == 125 {
      pos = pos + 1;
      done = true;
    } else {
      if !first {
        if b != 44 {
          return _err_jwk(_at("keymgmt: jwk expected comma or brace", pos));
        }
        pos = _json_ws(data, pos + 1, end);
        if pos >= end {
          return _err_jwk(_at("keymgmt: jwk unterminated object", start));
        }
      }
      var name_buf = Vec[UInt8].new();
      let nr = _json_string(data, pos, end, &mut name_buf);
      if !nr.is_ok {
        return _err_jwk(nr.error);
      }
      pos = nr.value;
      let name: Str = builder.sb_to_str(&name_buf);
      var dup = false;
      var j = 0;
      while j < fields.len() {
        let prev: Str = fields[j];
        if _streq(prev, name) {
          dup = true;
        }
        j = j + 1;
      }
      if dup {
        return _err_jwk(_at("keymgmt: jwk duplicate member", pos));
      }
      fields.push(name);
      pos = _json_ws(data, pos, end);
      if pos >= end || _byte(data, pos) != 58 {
        return _err_jwk(_at("keymgmt: jwk expected colon", pos));
      }
      pos = _json_ws(data, pos + 1, end);
      if pos >= end {
        return _err_jwk(_at("keymgmt: jwk missing value", pos));
      }
      if _streq(name, "kty") {
        let vstart = pos;
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        let v: Str = builder.sb_to_str(&vbuf);
        let code = _kty_code(v);
        if code == KME_KTY_UNKNOWN {
          return _err_jwk(_at("keymgmt: jwk unsupported kty", vstart));
        }
        kty = v;
        kty_code = code;
      } elif _streq(name, "kid") {
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        kid = builder.sb_to_str(&vbuf);
      } elif _streq(name, "use") {
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        use_val = builder.sb_to_str(&vbuf);
      } elif _streq(name, "alg") {
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        alg = builder.sb_to_str(&vbuf);
      } elif _streq(name, "crv") {
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        crv = builder.sb_to_str(&vbuf);
      } elif _streq(name, "x5u") {
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        x5u = builder.sb_to_str(&vbuf);
      } elif _streq(name, "x5t") {
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        x5t = builder.sb_to_str(&vbuf);
      } elif _streq(name, "x5t#S256") {
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        x5t_s256 = builder.sb_to_str(&vbuf);
      } elif _streq(name, "key_ops") {
        let astart = pos;
        let ar = _json_string_array(data, pos, end, &mut key_ops);
        if !ar.is_ok {
          return _err_jwk(ar.error);
        }
        pos = ar.value;
        if key_ops.len() == 0 {
          return _err_jwk(_at("keymgmt: jwk empty array", astart));
        }
      } elif _streq(name, "x5c") {
        let astart = pos;
        let ar = _json_string_array(data, pos, end, &mut x5c);
        if !ar.is_ok {
          return _err_jwk(ar.error);
        }
        pos = ar.value;
        if x5c.len() == 0 {
          return _err_jwk(_at("keymgmt: jwk empty array", astart));
        }
      } elif _is_param_name(name) {
        var vbuf = Vec[UInt8].new();
        let vr = _json_string(data, pos, end, &mut vbuf);
        if !vr.is_ok {
          return _err_jwk(vr.error);
        }
        pos = vr.value;
        let pref: Str = "keymgmt: jwk " + name + ": ";
        let dr = _b64_decode_range(&vbuf, 0, vbuf.len(), KME_B64_URL, false, pref);
        if !dr.is_ok {
          return _err_jwk(dr.error);
        }
        let dv: Vec[UInt8] = dr.value;
        if _streq(name, "n") {
          n = dv;
        } elif _streq(name, "e") {
          e = dv;
        } elif _streq(name, "d") {
          d = dv;
        } elif _streq(name, "p") {
          p = dv;
        } elif _streq(name, "q") {
          q = dv;
        } elif _streq(name, "dp") {
          dp = dv;
        } elif _streq(name, "dq") {
          dq = dv;
        } elif _streq(name, "qi") {
          qi = dv;
        } elif _streq(name, "x") {
          x = dv;
        } elif _streq(name, "y") {
          y = dv;
        } elif _streq(name, "k") {
          k = dv;
        }
      } else {
        let sk = _json_skip_value(data, pos, end, 0);
        if !sk.is_ok {
          return _err_jwk(sk.error);
        }
        pos = sk.value;
      }
      first = false;
    }
  }
  pos = _json_ws(data, pos, end);
  if pos != end {
    return _err_jwk(_at("keymgmt: jwk trailing data", pos));
  }
  if kty.len() == 0 {
    return _err_jwk(_at("keymgmt: jwk missing kty", start));
  }
  return _ok_jwk(Jwk{ kty: kty; kty_code: kty_code; kid: kid; use_val: use_val; alg: alg; crv: crv; x5u: x5u; x5t: x5t; x5t_s256: x5t_s256; key_ops: key_ops; x5c: x5c; n: n; e: e; d: d; p: p; q: q; dp: dp; dq: dq; qi: qi; x: x; y: y; k: k; fields: fields });
}

/// Parse one JWK (RFC 7517) JSON object from `text`. kty must be RSA, EC,
/// OKP or oct; the common members kid, use, key_ops, alg, crv, x5c, x5t,
/// x5t#S256, x5u and the parameter members n,e,d,p,q,dp,dq,qi,x,y,k are
/// recognized (parameters are base64url-decoded). Unknown members are skipped
/// when they are valid JSON; duplicate members, unknown kty and empty
/// key_ops/x5c arrays are rejected. Trailing non-whitespace after the object
/// is rejected.
/// Returns: Ok(Jwk); Err("keymgmt: jwk ..." or "keymgmt: json ...") naming
/// the offset.
/// Complexity: O(text.len()).
pub fn kme_jwk_parse(text: Str) -> Result[Jwk, Str] {
  var bytes = _bytes_of_str(text);
  return _jwk_parse_range(&bytes, 0, bytes.len());
}

// Number of parameter members present (0..10).
fn _jwk_param_count(jwk: &Jwk) -> Int {
  var c = 0;
  if kme_jwk_has_member(jwk, "n") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "e") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "d") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "p") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "q") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "dp") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "dq") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "qi") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "x") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "y") {
    c = c + 1;
  }
  if kme_jwk_has_member(jwk, "k") {
    c = c + 1;
  }
  return c;
}

// Structural check of one parameter member: "" when acceptable, otherwise the
// error message. `fixed` > 0 requires exactly that octet length; `minimal`
// rejects a leading 0x00 byte (RSA big-endian integers).
fn _param_check(jwk: &Jwk, name: Str, fixed: Int, minimal: Bool) -> Str {
  let len = kme_jwk_param_len(jwk, name);
  if len < 0 {
    return "keymgmt: jwk missing " + name;
  }
  if len == 0 {
    return "keymgmt: jwk empty " + name;
  }
  if fixed > 0 && len != fixed {
    return _msg_int("keymgmt: jwk " + name + " length must be ", fixed);
  }
  if minimal {
    let v: Vec[UInt8] = kme_jwk_param(jwk, name);
    if v.len() > 0 {
      let b0: Int = _byte(&v, 0);
      if b0 == 0 {
        return "keymgmt: jwk non-minimal " + name;
      }
    }
  }
  return "";
}

/// Detect the key type and validate the structural requirements of the JWK's
/// kty:
///   * RSA: n and e required, non-empty and minimally encoded (no leading
///     0x00); d marks the key private and when present the five CRT members
///     p,q,dp,dq,qi are all-or-nothing (if any is present, all are required);
///     membership is otherwise at most 8 parameter members.
///   * EC: crv required and one of P-256/P-384/P-521/secp256k1; x and y
///     required with exactly the curve's coordinate size; d optional (same
///     size) and marks the key private.
///   * OKP: crv required and one of Ed25519/X25519/Ed448/X448; x required at
///     the curve size; d optional (same size) and marks the key private.
///   * oct: k required and non-empty (leading zeros allowed: raw key bytes);
///     symmetric keys report is_private = true.
/// Returns: Ok(KmeJwkInfo) with kind / is_private / param_count;
/// Err("keymgmt: jwk ...") naming the first violated rule.
/// Complexity: O(parameter bytes).
pub fn kme_jwk_check(jwk: &Jwk) -> Result[KmeJwkInfo, Str] {
  let code: Int = jwk.kty_code;
  if code == KME_KTY_UNKNOWN {
    return _err_info("keymgmt: jwk unsupported kty");
  }
  let count = _jwk_param_count(jwk);
  if code == KME_KTY_RSA {
    let en = _param_check(jwk, "n", 0, true);
    if en.len() > 0 {
      return _err_info(en);
    }
    let ee = _param_check(jwk, "e", 0, true);
    if ee.len() > 0 {
      return _err_info(ee);
    }
    let has_d = kme_jwk_has_member(jwk, "d");
    var crt = 0;
    if kme_jwk_has_member(jwk, "p") {
      crt = crt + 1;
    }
    if kme_jwk_has_member(jwk, "q") {
      crt = crt + 1;
    }
    if kme_jwk_has_member(jwk, "dp") {
      crt = crt + 1;
    }
    if kme_jwk_has_member(jwk, "dq") {
      crt = crt + 1;
    }
    if kme_jwk_has_member(jwk, "qi") {
      crt = crt + 1;
    }
    if !has_d {
      if crt > 0 {
        return _err_info("keymgmt: jwk missing d");
      }
      return _ok_info(KmeJwkInfo{ kind: KME_KTY_RSA; is_private: false; param_count: count });
    }
    let ed = _param_check(jwk, "d", 0, true);
    if ed.len() > 0 {
      return _err_info(ed);
    }
    if crt > 0 {
      let ep = _param_check(jwk, "p", 0, true);
      if ep.len() > 0 {
        return _err_info(ep);
      }
      let eq = _param_check(jwk, "q", 0, true);
      if eq.len() > 0 {
        return _err_info(eq);
      }
      let edp = _param_check(jwk, "dp", 0, true);
      if edp.len() > 0 {
        return _err_info(edp);
      }
      let edq = _param_check(jwk, "dq", 0, true);
      if edq.len() > 0 {
        return _err_info(edq);
      }
      let eqi = _param_check(jwk, "qi", 0, true);
      if eqi.len() > 0 {
        return _err_info(eqi);
      }
    }
    return _ok_info(KmeJwkInfo{ kind: KME_KTY_RSA; is_private: true; param_count: count });
  }
  if code == KME_KTY_EC || code == KME_KTY_OKP {
    let crv: Str = jwk.crv;
    if crv.len() == 0 {
      return _err_info("keymgmt: jwk missing crv");
    }
    let cc = _crv_code(crv);
    if cc == KME_CRV_UNKNOWN {
      return _err_info("keymgmt: jwk unsupported curve " + crv);
    }
    var want = 1;
    if code == KME_KTY_OKP {
      want = 2;
    }
    if _crv_family(cc) != want {
      return _err_info("keymgmt: jwk curve mismatch");
    }
    let size = _crv_size(cc);
    let ex = _param_check(jwk, "x", size, false);
    if ex.len() > 0 {
      return _err_info(ex);
    }
    if code == KME_KTY_EC {
      let ey = _param_check(jwk, "y", size, false);
      if ey.len() > 0 {
        return _err_info(ey);
      }
    }
    if kme_jwk_has_member(jwk, "d") {
      let ed2 = _param_check(jwk, "d", size, false);
      if ed2.len() > 0 {
        return _err_info(ed2);
      }
      return _ok_info(KmeJwkInfo{ kind: code; is_private: true; param_count: count });
    }
    return _ok_info(KmeJwkInfo{ kind: code; is_private: false; param_count: count });
  }
  let ek = _param_check(jwk, "k", 0, false);
  if ek.len() > 0 {
    return _err_info(ek);
  }
  return _ok_info(KmeJwkInfo{ kind: KME_KTY_OCT; is_private: true; param_count: count });
}

/// Key type code reported by a kme_jwk_check result (KME_KTY_*).
/// Complexity: O(1).
pub fn kme_jwk_info_kind(info: &KmeJwkInfo) -> Int {
  return info.kind;
}

/// True when a kme_jwk_check result reports private key material.
/// Complexity: O(1).
pub fn kme_jwk_info_is_private(info: &KmeJwkInfo) -> Bool {
  return info.is_private;
}

/// Number of parameter members (0..10) reported by a kme_jwk_check result.
/// Complexity: O(1).
pub fn kme_jwk_info_param_count(info: &KmeJwkInfo) -> Int {
  return info.param_count;
}

/// True when the JWK carries private material: RSA/EC/OKP when the d member
/// is present, oct always (the k member is the secret itself).
/// Complexity: O(members).
pub fn kme_jwk_is_private(jwk: &Jwk) -> Bool {
  let code: Int = jwk.kty_code;
  if code == KME_KTY_OCT {
    return true;
  }
  if code == KME_KTY_UNKNOWN {
    return false;
  }
  return kme_jwk_has_member(jwk, "d");
}

/// Key type of the parsed JWK as its code (KME_KTY_RSA, KME_KTY_EC,
/// KME_KTY_OKP, KME_KTY_OCT or KME_KTY_UNKNOWN).
/// Complexity: O(1).
pub fn kme_jwk_type(jwk: &Jwk) -> Int {
  return jwk.kty_code;
}

/// The JWK "kty" member string; compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_kty(jwk: &Jwk) -> Str {
  let s: Str = jwk.kty;
  return s;
}

/// The JWK "kid" member ("" when absent); compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_kid(jwk: &Jwk) -> Str {
  let s: Str = jwk.kid;
  return s;
}

/// The JWK "use" member ("" when absent); compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_use(jwk: &Jwk) -> Str {
  let s: Str = jwk.use_val;
  return s;
}

/// The JWK "alg" member ("" when absent); compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_alg(jwk: &Jwk) -> Str {
  let s: Str = jwk.alg;
  return s;
}

/// The JWK "crv" member ("" when absent); compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_crv(jwk: &Jwk) -> Str {
  let s: Str = jwk.crv;
  return s;
}

/// The JWK "x5u" member ("" when absent); compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_x5u(jwk: &Jwk) -> Str {
  let s: Str = jwk.x5u;
  return s;
}

/// The JWK "x5t" member ("" when absent); compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_x5t(jwk: &Jwk) -> Str {
  let s: Str = jwk.x5t;
  return s;
}

/// The JWK "x5t#S256" member ("" when absent); compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_x5t_s256(jwk: &Jwk) -> Str {
  let s: Str = jwk.x5t_s256;
  return s;
}

/// Number of "key_ops" entries.
/// Complexity: O(1).
pub fn kme_jwk_key_ops_count(jwk: &Jwk) -> Int {
  return jwk.key_ops.len();
}

/// "key_ops" entry `i`, or "" when `i` is out of range; compare with
/// str_compare.
/// Complexity: O(1).
pub fn kme_jwk_key_op(jwk: &Jwk, i: Int) -> Str {
  if i < 0 || i >= jwk.key_ops.len() {
    return "";
  }
  let s: Str = jwk.key_ops[i];
  return s;
}

/// Number of "x5c" entries.
/// Complexity: O(1).
pub fn kme_jwk_x5c_count(jwk: &Jwk) -> Int {
  return jwk.x5c.len();
}

/// "x5c" entry `i` (a base64 standard DER certificate string), or "" when
/// `i` is out of range; compare with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_x5c(jwk: &Jwk, i: Int) -> Str {
  if i < 0 || i >= jwk.x5c.len() {
    return "";
  }
  let s: Str = jwk.x5c[i];
  return s;
}

/// Number of JSON members present in input order.
/// Complexity: O(1).
pub fn kme_jwk_member_count(jwk: &Jwk) -> Int {
  return jwk.fields.len();
}

/// Member name `i` in input order, or "" when `i` is out of range; compare
/// with str_compare.
/// Complexity: O(1).
pub fn kme_jwk_member(jwk: &Jwk, i: Int) -> Str {
  if i < 0 || i >= jwk.fields.len() {
    return "";
  }
  let s: Str = jwk.fields[i];
  return s;
}

/// True when a JSON member with this exact name was present in the input.
/// Complexity: O(members).
pub fn kme_jwk_has_member(jwk: &Jwk, name: Str) -> Bool {
  var i = 0;
  while i < jwk.fields.len() {
    let f: Str = jwk.fields[i];
    if _streq(f, name) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// True when `name` is one of the ten parameter members (n, e, d, p, q, dp,
/// dq, qi, x, y, k) AND it was present in the input. Non-parameter names are
/// always false.
/// Complexity: O(members).
pub fn kme_jwk_has_param(jwk: &Jwk, name: Str) -> Bool {
  if !_is_param_name(name) {
    return false;
  }
  return kme_jwk_has_member(jwk, name);
}

/// Decoded octet length of parameter `name`, or -1 when the member is absent
/// or `name` is not a parameter name. A present-but-empty parameter (for
/// example "n":"") returns 0.
/// Complexity: O(param bytes).
pub fn kme_jwk_param_len(jwk: &Jwk, name: Str) -> Int {
  if !kme_jwk_has_member(jwk, name) {
    return -1;
  }
  if _streq(name, "n") {
    let v: Vec[UInt8] = jwk.n;
    return v.len();
  }
  if _streq(name, "e") {
    let v: Vec[UInt8] = jwk.e;
    return v.len();
  }
  if _streq(name, "d") {
    let v: Vec[UInt8] = jwk.d;
    return v.len();
  }
  if _streq(name, "p") {
    let v: Vec[UInt8] = jwk.p;
    return v.len();
  }
  if _streq(name, "q") {
    let v: Vec[UInt8] = jwk.q;
    return v.len();
  }
  if _streq(name, "dp") {
    let v: Vec[UInt8] = jwk.dp;
    return v.len();
  }
  if _streq(name, "dq") {
    let v: Vec[UInt8] = jwk.dq;
    return v.len();
  }
  if _streq(name, "qi") {
    let v: Vec[UInt8] = jwk.qi;
    return v.len();
  }
  if _streq(name, "x") {
    let v: Vec[UInt8] = jwk.x;
    return v.len();
  }
  if _streq(name, "y") {
    let v: Vec[UInt8] = jwk.y;
    return v.len();
  }
  if _streq(name, "k") {
    let v: Vec[UInt8] = jwk.k;
    return v.len();
  }
  return -1;
}

/// Copy of decoded parameter `name` bytes; an absent member or a non-parameter
/// name yields an empty vector.
/// Complexity: O(param bytes).
pub fn kme_jwk_param(jwk: &Jwk, name: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if _streq(name, "n") {
    let src: Vec[UInt8] = jwk.n;
    _push_vec(&mut out, &src);
  } elif _streq(name, "e") {
    let src: Vec[UInt8] = jwk.e;
    _push_vec(&mut out, &src);
  } elif _streq(name, "d") {
    let src: Vec[UInt8] = jwk.d;
    _push_vec(&mut out, &src);
  } elif _streq(name, "p") {
    let src: Vec[UInt8] = jwk.p;
    _push_vec(&mut out, &src);
  } elif _streq(name, "q") {
    let src: Vec[UInt8] = jwk.q;
    _push_vec(&mut out, &src);
  } elif _streq(name, "dp") {
    let src: Vec[UInt8] = jwk.dp;
    _push_vec(&mut out, &src);
  } elif _streq(name, "dq") {
    let src: Vec[UInt8] = jwk.dq;
    _push_vec(&mut out, &src);
  } elif _streq(name, "qi") {
    let src: Vec[UInt8] = jwk.qi;
    _push_vec(&mut out, &src);
  } elif _streq(name, "x") {
    let src: Vec[UInt8] = jwk.x;
    _push_vec(&mut out, &src);
  } elif _streq(name, "y") {
    let src: Vec[UInt8] = jwk.y;
    _push_vec(&mut out, &src);
  } elif _streq(name, "k") {
    let src: Vec[UInt8] = jwk.k;
    _push_vec(&mut out, &src);
  }
  return out;
}

// Append one base64url parameter member to a JSON rendering; returns the new
// member counter.
fn _render_param(out: &mut Vec[UInt8], jwk: &Jwk, name: Str, n: Int) -> Int {
  if kme_jwk_param_len(jwk, name) < 0 {
    return n;
  }
  let v: Vec[UInt8] = kme_jwk_param(jwk, name);
  _json_member(out, n, name);
  out.push(34 as UInt8);
  _b64_encode_into(&v, 0, v.len(), KME_B64_URL, out);
  out.push(34 as UInt8);
  return n + 1;
}

/// Render a JWK as canonical JSON (no pretty printing). Members are emitted
/// in this fixed order when present: kty, kid, use, key_ops, alg, crv, x, y,
/// d, n, e, p, q, dp, dq, qi, k, x5c, x5t, x5t#S256, x5u. Parameter values
/// are re-encoded as unpadded base64url; string values are JSON-escaped.
/// Returns: Ok(json) for a JWK with a known kty_code;
/// Err("keymgmt: jwk unsupported kty") otherwise.
/// Complexity: O(member + parameter bytes).
pub fn kme_jwk_render(jwk: &Jwk) -> Result[Str, Str] {
  let code: Int = jwk.kty_code;
  if code < KME_KTY_RSA || code > KME_KTY_OCT {
    return _err_str("keymgmt: jwk unsupported kty");
  }
  var out = Vec[UInt8].new();
  _push_str(&mut out, "{");
  var n = 0;
  let kty: Str = jwk.kty;
  _json_member(&mut out, n, "kty");
  _json_quote_into(&mut out, kty);
  n = n + 1;
  if kme_jwk_has_member(jwk, "kid") {
    let v: Str = jwk.kid;
    _json_member(&mut out, n, "kid");
    _json_quote_into(&mut out, v);
    n = n + 1;
  }
  if kme_jwk_has_member(jwk, "use") {
    let v: Str = jwk.use_val;
    _json_member(&mut out, n, "use");
    _json_quote_into(&mut out, v);
    n = n + 1;
  }
  let koc = jwk.key_ops.len();
  if koc > 0 {
    _json_member(&mut out, n, "key_ops");
    out.push(91 as UInt8);
    var i = 0;
    while i < koc {
      let op: Str = jwk.key_ops[i];
      if i > 0 {
        out.push(44 as UInt8);
      }
      _json_quote_into(&mut out, op);
      i = i + 1;
    }
    out.push(93 as UInt8);
    n = n + 1;
  }
  if kme_jwk_has_member(jwk, "alg") {
    let v: Str = jwk.alg;
    _json_member(&mut out, n, "alg");
    _json_quote_into(&mut out, v);
    n = n + 1;
  }
  if kme_jwk_has_member(jwk, "crv") {
    let v: Str = jwk.crv;
    _json_member(&mut out, n, "crv");
    _json_quote_into(&mut out, v);
    n = n + 1;
  }
  n = _render_param(&mut out, jwk, "x", n);
  n = _render_param(&mut out, jwk, "y", n);
  n = _render_param(&mut out, jwk, "d", n);
  n = _render_param(&mut out, jwk, "n", n);
  n = _render_param(&mut out, jwk, "e", n);
  n = _render_param(&mut out, jwk, "p", n);
  n = _render_param(&mut out, jwk, "q", n);
  n = _render_param(&mut out, jwk, "dp", n);
  n = _render_param(&mut out, jwk, "dq", n);
  n = _render_param(&mut out, jwk, "qi", n);
  n = _render_param(&mut out, jwk, "k", n);
  let xc = jwk.x5c.len();
  if xc > 0 {
    _json_member(&mut out, n, "x5c");
    out.push(91 as UInt8);
    var i2 = 0;
    while i2 < xc {
      let c: Str = jwk.x5c[i2];
      if i2 > 0 {
        out.push(44 as UInt8);
      }
      _json_quote_into(&mut out, c);
      i2 = i2 + 1;
    }
    out.push(93 as UInt8);
    n = n + 1;
  }
  if kme_jwk_has_member(jwk, "x5t") {
    let v: Str = jwk.x5t;
    _json_member(&mut out, n, "x5t");
    _json_quote_into(&mut out, v);
    n = n + 1;
  }
  if kme_jwk_has_member(jwk, "x5t#S256") {
    let v: Str = jwk.x5t_s256;
    _json_member(&mut out, n, "x5t#S256");
    _json_quote_into(&mut out, v);
    n = n + 1;
  }
  if kme_jwk_has_member(jwk, "x5u") {
    let v: Str = jwk.x5u;
    _json_member(&mut out, n, "x5u");
    _json_quote_into(&mut out, v);
    n = n + 1;
  }
  out.push(125 as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Cross-format helpers (JWK -> SPKI, structural only)
// --------------------------------------------------

/// Structural SPKI algorithm OID for a JWK: rsaEncryption for RSA,
/// id-ecPublicKey for EC, the curve's own OID for OKP (Ed25519, X25519,
/// Ed448, X448); "" for oct and unknown kty.
/// Complexity: O(1).
pub fn kme_jwk_oid(jwk: &Jwk) -> Str {
  let code: Int = jwk.kty_code;
  if code == KME_KTY_RSA {
    return KME_OID_RSA_ENCRYPTION;
  }
  if code == KME_KTY_EC {
    return KME_OID_EC_PUBLIC_KEY;
  }
  if code == KME_KTY_OKP {
    let crv: Str = jwk.crv;
    return _curve_oid(_crv_code(crv));
  }
  return "";
}

/// Structural SPKI algorithm name for a JWK: "rsaEncryption" for RSA,
/// "id-ecPublicKey" for EC, the curve name for OKP; "" for oct and unknown
/// kty.
/// Complexity: O(1).
pub fn kme_jwk_alg_name(jwk: &Jwk) -> Str {
  let code: Int = jwk.kty_code;
  if code == KME_KTY_RSA {
    return "rsaEncryption";
  }
  if code == KME_KTY_EC {
    return "id-ecPublicKey";
  }
  if code == KME_KTY_OKP {
    let crv: Str = jwk.crv;
    return _curve_name(_crv_code(crv));
  }
  return "";
}

/// Structural namedCurve OID for a JWK (EC and OKP); "" otherwise.
/// Complexity: O(1).
pub fn kme_jwk_curve_oid(jwk: &Jwk) -> Str {
  let code: Int = jwk.kty_code;
  if code == KME_KTY_EC || code == KME_KTY_OKP {
    let crv: Str = jwk.crv;
    return _curve_oid(_crv_code(crv));
  }
  return "";
}

// --------------------------------------------------
//  JWKS (RFC 7517 section 5)
// --------------------------------------------------

/// Parse a JWKS document: a JSON object whose "keys" member is an array of
/// JWK objects. Other members are skipped when they are valid JSON. Every
/// array element must be a JSON object (it is not fully JWK-validated here;
/// kme_jwks_key parses it in full). The whole text must be consumed.
/// Returns: Ok(Jwks) storing the source text and each key object's span;
/// Err("keymgmt: jwks ..." or "keymgmt: json ...") naming the offset.
/// Complexity: O(text.len()).
pub fn kme_jwks_parse(text: Str) -> Result[Jwks, Str] {
  var bytes = _bytes_of_str(text);
  let end = bytes.len();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  var seen_keys = false;
  var pos = _json_ws(&bytes, 0, end);
  if pos >= end || _byte(&bytes, pos) != 123 {
    return _err_jwks(_at("keymgmt: jwks expected object", pos));
  }
  pos = _json_ws(&bytes, pos + 1, end);
  if pos < end && _byte(&bytes, pos) == 125 {
    pos = pos + 1;
    pos = _json_ws(&bytes, pos, end);
    if pos != end {
      return _err_jwks(_at("keymgmt: jwks trailing data", pos));
    }
    return _err_jwks("keymgmt: jwks missing keys");
  }
  var done = false;
  while !done {
    pos = _json_ws(&bytes, pos, end);
    var name_buf = Vec[UInt8].new();
    let nr = _json_string(&bytes, pos, end, &mut name_buf);
    if !nr.is_ok {
      return _err_jwks(nr.error);
    }
    let name: Str = builder.sb_to_str(&name_buf);
    pos = _json_ws(&bytes, nr.value, end);
    if pos >= end || _byte(&bytes, pos) != 58 {
      return _err_jwks(_at("keymgmt: jwks expected colon", pos));
    }
    pos = _json_ws(&bytes, pos + 1, end);
    if _streq(name, "keys") {
      if seen_keys {
        return _err_jwks(_at("keymgmt: jwks duplicate keys", pos));
      }
      seen_keys = true;
      if pos >= end || _byte(&bytes, pos) != 91 {
        return _err_jwks(_at("keymgmt: jwks keys not array", pos));
      }
      pos = _json_ws(&bytes, pos + 1, end);
      if pos < end && _byte(&bytes, pos) == 93 {
        pos = pos + 1;
      } else {
        var arr_done = false;
        while !arr_done {
          pos = _json_ws(&bytes, pos, end);
          if pos >= end || _byte(&bytes, pos) != 123 {
            return _err_jwks(_at("keymgmt: jwks key not object", pos));
          }
          let sk = _json_skip_value(&bytes, pos, end, 0);
          if !sk.is_ok {
            return _err_jwks(sk.error);
          }
          starts.push(pos);
          ends.push(sk.value);
          pos = _json_ws(&bytes, sk.value, end);
          if pos >= end {
            return _err_jwks(_at("keymgmt: jwks unterminated array", pos));
          }
          let c: Int = _byte(&bytes, pos);
          if c == 44 {
            pos = _json_ws(&bytes, pos + 1, end);
          } elif c == 93 {
            pos = pos + 1;
            arr_done = true;
          } else {
            return _err_jwks(_at("keymgmt: jwks expected comma or bracket", pos));
          }
        }
      }
    } else {
      let sk2 = _json_skip_value(&bytes, pos, end, 0);
      if !sk2.is_ok {
        return _err_jwks(sk2.error);
      }
      pos = sk2.value;
    }
    pos = _json_ws(&bytes, pos, end);
    if pos >= end {
      return _err_jwks(_at("keymgmt: jwks unterminated object", pos));
    }
    let c2: Int = _byte(&bytes, pos);
    if c2 == 44 {
      pos = _json_ws(&bytes, pos + 1, end);
    } elif c2 == 125 {
      pos = pos + 1;
      done = true;
    } else {
      return _err_jwks(_at("keymgmt: jwks expected comma or brace", pos));
    }
  }
  pos = _json_ws(&bytes, pos, end);
  if pos != end {
    return _err_jwks(_at("keymgmt: jwks trailing data", pos));
  }
  return _ok_jwks(Jwks{ text: text; key_starts: starts; key_ends: ends });
}

/// Number of keys in the JWKS.
/// Complexity: O(1).
pub fn kme_jwks_count(jwks: &Jwks) -> Int {
  return jwks.key_starts.len();
}

/// Parse key `i` of the JWKS in full.
/// Returns: Ok(Jwk) (offsets in the error messages are relative to the JWKS
/// text); Err("keymgmt: jwks index out of range") for a bad index or the
/// kme_jwk_parse catalog.
/// Complexity: O(key text).
pub fn kme_jwks_key(jwks: &Jwks, i: Int) -> Result[Jwk, Str] {
  if i < 0 || i >= jwks.key_starts.len() || i >= jwks.key_ends.len() {
    return _err_jwk("keymgmt: jwks index out of range");
  }
  let start: Int = jwks.key_starts[i];
  let stop: Int = jwks.key_ends[i];
  var bytes = _bytes_of_str(jwks.text);
  return _jwk_parse_range(&bytes, start, stop);
}

/// Index of the first key whose "kid" member equals `kid` byte-for-byte, or
/// -1 when none matches. Keys that fail to parse are skipped.
/// Complexity: O(keys * key text).
pub fn kme_jwks_lookup(jwks: &Jwks, kid: Str) -> Int {
  var i = 0;
  while i < jwks.key_starts.len() {
    let kr = kme_jwks_key(jwks, i);
    if kr.is_ok {
      let key: Jwk = kr.value;
      let k: Str = key.kid;
      if _streq(k, kid) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  PEM armor (PRIVATE KEY / ENCRYPTED PRIVATE KEY / PUBLIC KEY)
// --------------------------------------------------

// Index of the next LF at or after `pos`, or the text length when there is
// none.
fn _line_end(text: Str, pos: Int) -> Int {
  let n = text.len();
  var i = pos;
  while i < n {
    if _tb(text, i) == 10 {
      return i;
    }
    i = i + 1;
  }
  return n;
}

// True when the line [start, end) begins with five hyphen-minuses.
fn _pem_dash5(text: Str, start: Int, end: Int) -> Bool {
  if end - start < 5 {
    return false;
  }
  var i = 0;
  while i < 5 {
    if _tb(text, start + i) != 45 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Label of the line [start, end) when it is exactly "-----BEGIN <label>-----"
// (kind 1) or "-----END <label>-----" (kind 2), where the label is a run of
// A-Z and single spaces; "" otherwise.
fn _pem_marker_label(text: Str, start: Int, end: Int, kind: Int) -> Str {
  let n = end - start;
  if n < 17 {
    return "";
  }
  if !_pem_dash5(text, start, end) {
    return "";
  }
  var ls = start + 11;
  if kind == 1 {
    if _tb(text, start + 5) != 66 {
      return "";
    }
    if _tb(text, start + 6) != 69 {
      return "";
    }
    if _tb(text, start + 7) != 71 {
      return "";
    }
    if _tb(text, start + 8) != 73 {
      return "";
    }
    if _tb(text, start + 9) != 78 {
      return "";
    }
    if _tb(text, start + 10) != 32 {
      return "";
    }
  } else {
    if _tb(text, start + 5) != 69 {
      return "";
    }
    if _tb(text, start + 6) != 78 {
      return "";
    }
    if _tb(text, start + 7) != 68 {
      return "";
    }
    if _tb(text, start + 8) != 32 {
      return "";
    }
    ls = start + 9;
  }
  var j = end - 5;
  while j < end {
    if _tb(text, j) != 45 {
      return "";
    }
    j = j + 1;
  }
  let le = end - 5;
  if ls >= le {
    return "";
  }
  var m = ls;
  while m < le {
    let b = _tb(text, m);
    if b != 32 && (b < 65 || b > 90) {
      return "";
    }
    m = m + 1;
  }
  return string.str_slice(text, ls, le);
}

// True when `label` is one of the three supported PEM labels.
fn _pem_label_supported(label: Str) -> Bool {
  if _streq(label, KME_LABEL_PRIVATE_KEY) {
    return true;
  }
  if _streq(label, KME_LABEL_ENCRYPTED_PRIVATE_KEY) {
    return true;
  }
  if _streq(label, KME_LABEL_PUBLIC_KEY) {
    return true;
  }
  return false;
}

/// Unwrap exactly one PEM armor block whose label is PRIVATE KEY,
/// ENCRYPTED PRIVATE KEY or PUBLIC KEY.
///
/// Lines end at LF or at end of input; one CR before an LF is removed (CRLF
/// normalization). Empty lines outside the block are ignored. The body must
/// be canonical base64: every line except the last is exactly 64 characters,
/// the last is 1..64, the concatenated character count is a multiple of 4 and
/// padding is canonical. Decoding errors carry the text offset.
/// Returns: Ok(KmePem); Err("keymgmt: pem ...") from the catalog in SPEC.md
/// (no block, unsupported label, text outside block, bad armor, blank line in
/// body, bad body line length, invalid base64 character, bad padding,
/// non-canonical trailing bits, label mismatch, unterminated block, empty
/// body).
/// Complexity: O(text.len()).
pub fn kme_pem_unwrap(text: Str) -> Result[KmePem, Str] {
  let n = text.len();
  var pos = 0;
  var in_block = false;
  var label: Str = "";
  var block_start = 0;
  var body = Vec[UInt8].new();
  var prev_len = -1;
  while pos < n {
    let e = _line_end(text, pos);
    var ce = e;
    if ce > pos && _tb(text, ce - 1) == 13 {
      ce = ce - 1;
    }
    if !in_block {
      if ce > pos {
        let bl = _pem_marker_label(text, pos, ce, 1);
        if bl.len() > 0 {
          if !_pem_label_supported(bl) {
            return _err_pem(_at("keymgmt: pem unsupported label", pos));
          }
          in_block = true;
          label = bl;
          block_start = pos;
          body = Vec[UInt8].new();
          prev_len = -1;
        } else {
          let el = _pem_marker_label(text, pos, ce, 2);
          if el.len() > 0 {
            return _err_pem(_at("keymgmt: pem text outside block", pos));
          }
          return _err_pem(_at("keymgmt: pem text outside block", pos));
        }
      }
    } else {
      let bl2 = _pem_marker_label(text, pos, ce, 1);
      if bl2.len() > 0 {
        return _err_pem(_at("keymgmt: pem nested block", pos));
      }
      let el2 = _pem_marker_label(text, pos, ce, 2);
      if el2.len() > 0 {
        if !_streq(el2, label) {
          return _err_pem(_at("keymgmt: pem label mismatch", pos));
        }
        if body.len() == 0 {
          return _err_pem(_at("keymgmt: pem empty body", pos));
        }
        let dr = _b64_decode_range(&body, 0, body.len(), KME_B64_STD, true, "keymgmt: pem ");
        if !dr.is_ok {
          return _err_pem(dr.error);
        }
        let decoded: Vec[UInt8] = dr.value;
        return _ok_pem(KmePem{ label: label; data: decoded });
      }
      if ce == pos {
        return _err_pem(_at("keymgmt: pem blank line in body", pos));
      }
      if _pem_dash5(text, pos, ce) {
        return _err_pem(_at("keymgmt: pem bad armor", pos));
      }
      let llen = ce - pos;
      if prev_len >= 0 && prev_len != 64 {
        return _err_pem(_at("keymgmt: pem bad body line length", pos));
      }
      if llen > 64 {
        return _err_pem(_at("keymgmt: pem bad body line length", pos));
      }
      var k = pos;
      while k < ce {
        let b = _tb(text, k);
        if b != 61 && _b64_digit(b, KME_B64_STD) < 0 {
          return _err_pem(_at("keymgmt: pem invalid base64 character", k));
        }
        body.push(b as UInt8);
        k = k + 1;
      }
      prev_len = llen;
    }
    pos = e + 1;
  }
  if in_block {
    return _err_pem(_at("keymgmt: pem unterminated block", block_start));
  }
  return _err_pem("keymgmt: pem no block");
}

/// Rewrap data as one canonical PEM block: the BEGIN line, standard base64
/// wrapped at exactly 64 characters per line with LF endings (the last line
/// carries the remainder; empty data emits no body line), the END line and
/// one trailing LF.
/// Returns: Ok(text); Err("keymgmt: pem unsupported label") when `label` is
/// not PRIVATE KEY / ENCRYPTED PRIVATE KEY / PUBLIC KEY.
/// Complexity: O(data.len()).
pub fn kme_pem_wrap(label: Str, data: &Vec[UInt8]) -> Result[Str, Str] {
  if !_pem_label_supported(label) {
    return _err_str("keymgmt: pem unsupported label");
  }
  var out = Vec[UInt8].new();
  _push_str(&mut out, "-----BEGIN ");
  _push_str(&mut out, label);
  _push_str(&mut out, "-----");
  out.push(10 as UInt8);
  _b64_emit_wrapped(data, 0, data.len(), &mut out);
  _push_str(&mut out, "-----END ");
  _push_str(&mut out, label);
  _push_str(&mut out, "-----");
  out.push(10 as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

/// Label of an unwrapped PEM block; compare with str_compare.
/// Complexity: O(1).
pub fn kme_pem_label(p: &KmePem) -> Str {
  let s: Str = p.label;
  return s;
}

/// Copy of the decoded body bytes of an unwrapped PEM block.
/// Complexity: O(body bytes).
pub fn kme_pem_data(p: &KmePem) -> Vec[UInt8] {
  let src: Vec[UInt8] = p.data;
  var out = Vec[UInt8].new();
  _push_vec(&mut out, &src);
  return out;
}

/// The "PRIVATE KEY" PEM label.
/// Complexity: O(1).
pub fn kme_label_private_key() -> Str {
  return KME_LABEL_PRIVATE_KEY;
}

/// The "ENCRYPTED PRIVATE KEY" PEM label.
/// Complexity: O(1).
pub fn kme_label_encrypted_private_key() -> Str {
  return KME_LABEL_ENCRYPTED_PRIVATE_KEY;
}

/// The "PUBLIC KEY" PEM label.
/// Complexity: O(1).
pub fn kme_label_public_key() -> Str {
  return KME_LABEL_PUBLIC_KEY;
}

/// Interface revision of this module (1).
/// Complexity: O(1).
pub fn kme_version() -> Int {
  return 1;
}
