// XIOM -- xiom.pki: X.509/PKIX certificate structure parser (DER + PEM)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, nothing beyond xiom.std) structural parser for X.509
// (RFC 5280 / PKIX) certificates. It parses bytes into a flat decoded model;
// it performs NO cryptographic verification, NO chain building, NO name
// matching and NO validity checking. A parsed certificate is structure, not
// trust.
//
// Covered:
//   * DER (X.690) TLV walker: tag class/constructed/tag-number including the
//     high-tag-number form, definite short and long lengths (indefinite and
//     non-minimal long forms are rejected), truncation detection against the
//     buffer and against an enclosing container, nested SEQUENCE/SET;
//   * ASN.1 primitives: BOOLEAN, positive INTEGER, BIT STRING (unused-bit
//     count validated), OCTET STRING, NULL, OBJECT IDENTIFIER (first two
//     arcs plus base-128 continuation arcs rendered as a dotted string),
//     UTF8String / PrintableString / IA5String, UTCTime and GeneralizedTime
//     (structured Y/M/D/h/m/s fields; UTCTime YY < 50 maps to 20YY);
//   * Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm,
//     signatureValue }; TBSCertificate with version [0] EXPLICIT (v1/v2/v3),
//     serialNumber (positive), signature AlgorithmIdentifier, issuer and
//     subject RDNSequences (parallel vectors: rdn index / OID / value tag /
//     value), validity (notBefore/notAfter), subjectPublicKeyInfo (algorithm
//     OID plus key bit length); extensions [3]: basicConstraints (cA flag and
//     pathLenConstraint), keyUsage (divisor/modulo bit decode), extKeyUsage
//     OID list, subjectAltName (dNSName/rfc822Name/URI/iPAddress), and the
//     presence of subjectKeyIdentifier / authorityKeyIdentifier. Unknown
//     extension OIDs are preserved as dotted strings.
//   * pki_pem_to_der: unwrap one `-----BEGIN CERTIFICATE-----` armor block
//     with a strict self-contained base64 decoder (bad armor, bad padding and
//     non-canonical trailing bits are rejected).
//
// Every structural error is a stable Err(Str) naming the byte offset of the
// offending structure. See SPEC.md for the exact catalog and subset.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no `match`, no Vec of
//     structs, no Vec[fn] dispatch, no table-driven dispatch;
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside larger functions miscompiles);
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before it enters Int arithmetic; a byte
//     with the sign bit set is never tested with bit operations;
//   * Str values read from a Vec[Str] are bound to typed locals and compared
//     only through str_compare / the byte-wise _streq (BUG 17 discipline);
//   * no shifts anywhere: bit positions are probed with divisor/modulo
//     arithmetic; multiple-of-128 arithmetic is `v * 128 + (b % 128)`;
//   * every parallel Vec is pushed in lockstep; mismatched lengths are
//     treated as malformed input;
//   * `&struct.field` is bound to a local before it is passed to a
//     `&Vec[UInt8]` parameter.

module xiom.pki

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Tag class UNIVERSAL.
pub const PKI_CLASS_UNIVERSAL: Int = 0;

/// Tag class APPLICATION.
pub const PKI_CLASS_APPLICATION: Int = 1;

/// Tag class CONTEXT-SPECIFIC.
pub const PKI_CLASS_CONTEXT: Int = 2;

/// Tag class PRIVATE.
pub const PKI_CLASS_PRIVATE: Int = 3;

/// Universal tag of BOOLEAN (0x01).
pub const PKI_TAG_BOOLEAN: Int = 1;

/// Universal tag of INTEGER (0x02).
pub const PKI_TAG_INTEGER: Int = 2;

/// Universal tag of BIT STRING (0x03).
pub const PKI_TAG_BIT_STRING: Int = 3;

/// Universal tag of OCTET STRING (0x04).
pub const PKI_TAG_OCTET_STRING: Int = 4;

/// Universal tag of NULL (0x05).
pub const PKI_TAG_NULL: Int = 5;

/// Universal tag of OBJECT IDENTIFIER (0x06).
pub const PKI_TAG_OID: Int = 6;

/// Universal tag of UTF8String (0x0C).
pub const PKI_TAG_UTF8_STRING: Int = 12;

/// Universal tag of SEQUENCE (0x10).
pub const PKI_TAG_SEQUENCE: Int = 16;

/// Universal tag of SET (0x11).
pub const PKI_TAG_SET: Int = 17;

/// Universal tag of PrintableString (0x13).
pub const PKI_TAG_PRINTABLE_STRING: Int = 19;

/// Universal tag of IA5String (0x16).
pub const PKI_TAG_IA5_STRING: Int = 22;

/// Universal tag of UTCTime (0x17).
pub const PKI_TAG_UTC_TIME: Int = 23;

/// Universal tag of GeneralizedTime (0x18).
pub const PKI_TAG_GENERALIZED_TIME: Int = 24;

/// Context tag of the TBSCertificate version field ([0] EXPLICIT).
pub const PKI_TAG_VERSION: Int = 0;

/// Context tag of the TBSCertificate extensions field ([3] EXPLICIT).
pub const PKI_TAG_EXTENSIONS: Int = 3;

/// Context tag of the Extension default FALSE critical flag is universal
/// BOOLEAN; see PKI_TAG_BOOLEAN. Kept as a named alias for readability.
pub const PKI_TAG_CRITICAL: Int = 1;

/// Version number v1 (encoded as 0).
pub const PKI_VERSION_V1: Int = 0;

/// Version number v2 (encoded as 1).
pub const PKI_VERSION_V2: Int = 1;

/// Version number v3 (encoded as 2).
pub const PKI_VERSION_V3: Int = 2;

/// SubjectAltName GeneralName choice rfc822Name ([1] IMPLICIT IA5String).
pub const PKI_SAN_EMAIL: Int = 1;

/// SubjectAltName GeneralName choice dNSName ([2] IMPLICIT IA5String).
pub const PKI_SAN_DNS: Int = 2;

/// SubjectAltName GeneralName choice uniformResourceIdentifier ([6]).
pub const PKI_SAN_URI: Int = 6;

/// SubjectAltName GeneralName choice iPAddress ([7] IMPLICIT OCTET STRING).
pub const PKI_SAN_IP: Int = 7;

/// Largest accepted serialNumber content length in bytes (RFC 5280: no more
/// than 20 octets).
pub const PKI_MAX_SERIAL_BYTES: Int = 20;

/// Largest number of OID arcs accepted while decoding one OBJECT IDENTIFIER
/// (guards against runaway input).
pub const PKI_MAX_OID_ARCS: Int = 64;

/// Dotted extension OID of basicConstraints (2.5.29.19).
pub const PKI_OID_BASIC_CONSTRAINTS: Str = "2.5.29.19";

/// Dotted extension OID of keyUsage (2.5.29.15).
pub const PKI_OID_KEY_USAGE: Str = "2.5.29.15";

/// Dotted extension OID of extKeyUsage (2.5.29.37).
pub const PKI_OID_EXT_KEY_USAGE: Str = "2.5.29.37";

/// Dotted extension OID of subjectAltName (2.5.29.17).
pub const PKI_OID_SUBJECT_ALT_NAME: Str = "2.5.29.17";

/// Dotted extension OID of subjectKeyIdentifier (2.5.29.14).
pub const PKI_OID_SUBJECT_KEY_ID: Str = "2.5.29.14";

/// Dotted extension OID of authorityKeyIdentifier (2.5.29.35).
pub const PKI_OID_AUTHORITY_KEY_ID: Str = "2.5.29.35";

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A decoded DER length field. `len` is the content length (>= 0) and `size`
/// is the number of length-field bytes (1 for the short form, 1 + n for the
/// long form).
pub type DerLength = {
  len: Int;
  size: Int;
}

/// A decoded DER tag-length-value header. `tag_class` is 0..3, `constructed`
/// the P/C bit, `tag_number` the tag number (any size, high-tag-number form
/// included); `header` is the offset of the first tag byte, `content` the
/// offset of the first content byte, `len` the content length and `next` the
/// offset just past the content.
pub type DerTlv = {
  tag_class: Int;
  constructed: Bool;
  tag_number: Int;
  header: Int;
  content: Int;
  len: Int;
  next: Int;
}

/// A decoded BOOLEAN plus `next`, the offset just past the TLV.
pub type DerBool = {
  value: Bool;
  next: Int;
}

/// A decoded non-negative INTEGER: its numeric `value` (fits in 8 content
/// bytes) plus `next`, the offset just past the TLV.
pub type DerUint = {
  value: Int;
  next: Int;
}

/// A decoded BIT STRING. `unused` is the trailing unused-bit count (0..7),
/// `bit_length` the number of significant bits, `offset`/`len` the bit bytes
/// in the source buffer (after the unused-bit count octet) and `next` the
/// offset just past the TLV.
pub type DerBits = {
  unused: Int;
  bit_length: Int;
  offset: Int;
  len: Int;
  next: Int;
}

/// A decoded OCTET STRING (copied verbatim) plus `next`, the offset just
/// past the TLV.
pub type DerBytes = {
  bytes: Vec[UInt8];
  next: Int;
}

/// A decoded OBJECT IDENTIFIER as a dotted decimal string plus `next`, the
/// offset just past the TLV.
pub type DerOid = {
  value: Str;
  next: Int;
}

/// A decoded UTF8String / PrintableString / IA5String value plus `next`, the
/// offset just past the TLV.
pub type DerString = {
  value: Str;
  next: Int;
}

/// A decoded UTCTime or GeneralizedTime as structured fields. `year` is the
/// full four-digit year (UTCTime YY < 50 maps to 20YY, else 19YY), `utc` is
/// true when the source tag was UTCTime, and `next` is the offset just past
/// the TLV. Fields are not calendar-validated beyond basic ranges.
pub type DerTime = {
  year: Int;
  month: Int;
  day: Int;
  hour: Int;
  minute: Int;
  second: Int;
  utc: Bool;
  next: Int;
}

/// A decoded RDNSequence (Name). Attribute i belongs to RDN `rdn_index[i]`
/// and carries `oids[i]` (dotted type OID), `value_tags[i]` (universal tag
/// number of the value, or -1 when the value type is not one of the decoded
/// string types) and `values[i]` (the decoded string, "" for undecoded
/// types). `rdn_count` is the number of SETs.
pub type PkiName = {
  rdn_index: Vec[Int];
  oids: Vec[Str];
  value_tags: Vec[Int];
  values: Vec[Str];
  rdn_count: Int;
  next: Int;
}

/// Decoded extension set. The `oids` / `critical` vectors list every
/// extension in wire order (unknown OIDs preserved as dotted strings).
/// Decoded known extensions fill the flags and payload fields below;
/// `path_len` is -1 when absent. `key_usage` is the keyUsage bits normalized
/// to a left-aligned 16-bit word regardless of whether the BIT STRING used
/// one or two bit bytes: bit 0 (digitalSignature) is 0x8000, bit 8
/// (decipherOnly) is 0x0080, so bit i is probed with divisor/modulo
/// arithmetic via pki_key_usage_has.
pub type PkiExtensions = {
  oids: Vec[Str];
  critical: Vec[Int];
  has_basic_constraints: Bool;
  ca: Bool;
  path_len: Int;
  has_key_usage: Bool;
  key_usage: Int;
  has_ext_key_usage: Bool;
  eku_oids: Vec[Str];
  has_san: Bool;
  san_types: Vec[Int];
  san_values: Vec[Str];
  has_subject_key_id: Bool;
  subject_key_id_hex: Str;
  has_authority_key_id: Bool;
  authority_key_id_hex: Str;
  next: Int;
}

/// A decoded Certificate. Structural only: `serial_hex` is the uppercase hex
/// of the serialNumber content bytes (the leading 0x00 sign pad, when DER
/// required one, is included), `sig_offset`/`sig_len` bound the signature
/// BIT STRING's bit bytes inside the source buffer and `sig_unused` its
/// unused-bit count. `tbs_offset`/`tbs_len` bound the TBS content.
pub type PkiCertificate = {
  version: Int;
  serial_hex: Str;
  serial_len: Int;
  serial_bytes: Vec[UInt8];
  tbs_sig_oid: Str;
  outer_sig_oid: Str;
  issuer: PkiName;
  subject: PkiName;
  not_before: DerTime;
  not_after: DerTime;
  spki_alg_oid: Str;
  spki_key_bits: Int;
  extensions: PkiExtensions;
  tbs_offset: Int;
  tbs_len: Int;
  sig_offset: Int;
  sig_len: Int;
  sig_unused: Int;
  next: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[DerLength, Str].
fn _ok_len(v: DerLength) -> Result[DerLength, Str] {
  return Ok(v);
}

// Err(m) for Result[DerLength, Str].
fn _err_len(m: Str) -> Result[DerLength, Str] {
  return Err(m);
}

// Ok(v) for Result[DerTlv, Str].
fn _ok_tlv(v: DerTlv) -> Result[DerTlv, Str] {
  return Ok(v);
}

// Err(m) for Result[DerTlv, Str].
fn _err_tlv(m: Str) -> Result[DerTlv, Str] {
  return Err(m);
}

// Ok(v) for Result[DerBool, Str].
fn _ok_bool(v: DerBool) -> Result[DerBool, Str] {
  return Ok(v);
}

// Err(m) for Result[DerBool, Str].
fn _err_bool(m: Str) -> Result[DerBool, Str] {
  return Err(m);
}

// Ok(v) for Result[DerUint, Str].
fn _ok_uint(v: DerUint) -> Result[DerUint, Str] {
  return Ok(v);
}

// Err(m) for Result[DerUint, Str].
fn _err_uint(m: Str) -> Result[DerUint, Str] {
  return Err(m);
}

// Ok(v) for Result[DerBits, Str].
fn _ok_bits(v: DerBits) -> Result[DerBits, Str] {
  return Ok(v);
}

// Err(m) for Result[DerBits, Str].
fn _err_bits(m: Str) -> Result[DerBits, Str] {
  return Err(m);
}

// Ok(v) for Result[DerBytes, Str].
fn _ok_dbytes(v: DerBytes) -> Result[DerBytes, Str] {
  return Ok(v);
}

// Err(m) for Result[DerBytes, Str].
fn _err_dbytes(m: Str) -> Result[DerBytes, Str] {
  return Err(m);
}

// Ok(v) for Result[DerOid, Str].
fn _ok_oid(v: DerOid) -> Result[DerOid, Str] {
  return Ok(v);
}

// Err(m) for Result[DerOid, Str].
fn _err_oid(m: Str) -> Result[DerOid, Str] {
  return Err(m);
}

// Ok(v) for Result[DerString, Str].
fn _ok_dstr(v: DerString) -> Result[DerString, Str] {
  return Ok(v);
}

// Err(m) for Result[DerString, Str].
fn _err_dstr(m: Str) -> Result[DerString, Str] {
  return Err(m);
}

// Ok(v) for Result[DerTime, Str].
fn _ok_time(v: DerTime) -> Result[DerTime, Str] {
  return Ok(v);
}

// Err(m) for Result[DerTime, Str].
fn _err_time(m: Str) -> Result[DerTime, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[PkiName, Str].
fn _ok_name(v: PkiName) -> Result[PkiName, Str] {
  return Ok(v);
}

// Err(m) for Result[PkiName, Str].
fn _err_name(m: Str) -> Result[PkiName, Str] {
  return Err(m);
}

// Ok(v) for Result[PkiExtensions, Str].
fn _ok_exts(v: PkiExtensions) -> Result[PkiExtensions, Str] {
  return Ok(v);
}

// Err(m) for Result[PkiExtensions, Str].
fn _err_exts(m: Str) -> Result[PkiExtensions, Str] {
  return Err(m);
}

// Ok(v) for Result[PkiCertificate, Str].
fn _ok_cert(v: PkiCertificate) -> Result[PkiCertificate, Str] {
  return Ok(v);
}

// Err(m) for Result[PkiCertificate, Str].
fn _err_cert(m: Str) -> Result[PkiCertificate, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Copy `n` bytes starting at `start` into a fresh vector; callers guarantee
// `start >= 0`, `n >= 0` and `start + n <= data.len()`.
fn _copy_bytes(data: &Vec[UInt8], start: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(data[start + i]);
    i = i + 1;
  }
  return out;
}

// Render "`msg` at offset `off`" for the error catalog.
fn _at(msg: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, msg);
  builder.sb_push_str(&mut sb, " at offset ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

// True when `a` and `b` are byte-for-byte equal. Never uses `==` on Str
// values (BUG 17 discipline).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Upper-case hex string of data[start, start+n); callers guarantee the
// bounds. The result contains no NUL bytes.
fn _hex_from(data: &Vec[UInt8], start: Int, n: Int) -> Str {
  let alpha = "0123456789ABCDEF";
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b: Int = _byte(data, start + i);
    out.push(string.byte_at(alpha, b / 16));
    out.push(string.byte_at(alpha, b % 16));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// 2^k for 0 <= k <= 30, built by repeated multiplication (no shifts).
fn _pow2(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// --------------------------------------------------
//  DER length / tag / TLV walker
// --------------------------------------------------

/// Decode a DER length field at `off`. The short form is 0x00..0x7F; the
/// long form is 0x80|n followed by n big-endian bytes with n in 1..8. The
/// indefinite form (0x80) is rejected (DER is always definite). Only the
/// minimal long form is accepted: a leading zero length byte or a value
/// below 128 encoded in the long form is `pki: non-minimal length`.
///
/// Errors, each naming `off` (the first length byte):
///   * `pki: negative offset` -- off < 0;
///   * `pki: truncated length` -- no length byte, or the declared number of
///     long-form bytes is missing;
///   * `pki: indefinite length` -- the 0x80 byte;
///   * `pki: long-form length overflow` -- more than 8 length bytes, or a
///     value that does not fit a signed 64-bit Int;
///   * `pki: non-minimal length` -- non-minimal long form.
/// Complexity: O(length bytes).
pub fn der_length_decode(data: &Vec[UInt8], off: Int) -> Result[DerLength, Str] {
  if off < 0 {
    return _err_len("pki: negative offset");
  }
  if off >= data.len() {
    return _err_len(_at("pki: truncated length", off));
  }
  let b: Int = _byte(data, off);
  if b < 128 {
    return _ok_len(DerLength{ len: b; size: 1; });
  }
  let n: Int = b - 128;
  if n == 0 {
    return _err_len(_at("pki: indefinite length", off));
  }
  if n > 8 {
    return _err_len(_at("pki: long-form length overflow", off));
  }
  if off + 1 + n > data.len() {
    return _err_len(_at("pki: truncated length", off));
  }
  var v = 0;
  var i = 0;
  while i < n {
    let x: Int = _byte(data, off + 1 + i);
    if i == 0 && x == 0 {
      return _err_len(_at("pki: non-minimal length", off));
    }
    v = v * 256 + x;
    if v < 0 {
      return _err_len(_at("pki: long-form length overflow", off));
    }
    i = i + 1;
  }
  if v < 128 {
    return _err_len(_at("pki: non-minimal length", off));
  }
  return _ok_len(DerLength{ len: v; size: 1 + n; });
}

/// Decode one DER tag-length-value at `off` and check that the declared
/// content fits the buffer. The tag may use the high-tag-number form (low
/// five bits of the first tag byte 11111, then base-128 bytes); the decoded
/// `tag_number` can be arbitrarily large (overflow is rejected).
///
/// Errors, each naming `off` (the tag byte):
///   * `pki: negative offset`, `pki: truncated tag` -- no tag byte, or an
///     unfinished high-tag-number form;
///   * `pki: non-minimal tag` -- a high-tag-number form starting with a
///     0x80 byte;
///   * `pki: tag number overflow` -- the tag number does not fit an Int;
///   * the `der_length_decode` catalog;
///   * `pki: truncated value` -- `content + len > data.len()`.
/// The caller is responsible for checking the TLV against its enclosing
/// container (`der_tlv_in` reports `pki: value overruns container`).
/// Complexity: O(tag + length bytes).
pub fn der_tlv_decode(data: &Vec[UInt8], off: Int) -> Result[DerTlv, Str] {
  if off < 0 {
    return _err_tlv("pki: negative offset");
  }
  if off >= data.len() {
    return _err_tlv(_at("pki: truncated tag", off));
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
        return _err_tlv(_at("pki: truncated tag", off));
      }
      let x: Int = _byte(data, p);
      if first && x == 128 {
        return _err_tlv(_at("pki: non-minimal tag", off));
      }
      if first {
        tag_number = 0;
      }
      tag_number = tag_number * 128 + (x % 128);
      if tag_number < 0 {
        return _err_tlv(_at("pki: tag number overflow", off));
      }
      if x < 128 {
        done = true;
      } else {
        first = false;
        arcs = arcs + 1;
        if arcs > 8 {
          return _err_tlv(_at("pki: tag number overflow", off));
        }
      }
      p = p + 1;
    }
    tag_end = p;
  }
  let lr = der_length_decode(data, tag_end);
  if !lr.is_ok {
    return _err_tlv(lr.error);
  }
  let l: DerLength = lr.value;
  let content = tag_end + l.size;
  let len: Int = l.len;
  if len > data.len() - content {
    return _err_tlv(_at("pki: truncated value", off));
  }
  return _ok_tlv(DerTlv{ tag_class: tclass; constructed: constructed; tag_number: tag_number; header: off; content: content; len: len; next: content + len; });
}

/// Decode one DER TLV at `off` that must not extend past `end` (the end of
/// the enclosing container). `pki: value overruns container` names `off`
/// when it does. Errors: the `der_tlv_decode` catalog plus that one.
/// Complexity: O(tag + length bytes).
pub fn der_tlv_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerTlv, Str] {
  if off < 0 {
    return _err_tlv("pki: negative offset");
  }
  let r = der_tlv_decode(data, off);
  if !r.is_ok {
    return _err_tlv(r.error);
  }
  let t: DerTlv = r.value;
  if t.next > end {
    return _err_tlv(_at("pki: value overruns container", off));
  }
  return _ok_tlv(t);
}

// The offset of the TLV's first byte (the `header` field, spelled out as a
// helper name for call sites).
fn _tlv_start(t: &DerTlv) -> Int {
  return t.header;
}

// True when `t` is a universal primitive of `tag`.
fn _is_universal(t: &DerTlv, tag: Int) -> Bool {
  if t.tag_class != PKI_CLASS_UNIVERSAL {
    return false;
  }
  if t.tag_number != tag {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  ASN.1 primitives
// --------------------------------------------------

/// Decode a BOOLEAN at `off` (tag 0x01). The content must be exactly one
/// byte; the value is false only for 0x00 (DER requires 0x00 or 0xFF; any
/// non-zero byte is accepted as true, matching BER).
/// Errors: the `der_tlv_decode` catalog, `pki: tag mismatch` at `off` and
/// `pki: bad boolean` at `off` for a content length other than 1.
/// Complexity: O(1).
pub fn der_bool_decode(data: &Vec[UInt8], off: Int) -> Result[DerBool, Str] {
  let tr = der_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bool(tr.error);
  }
  let t: DerTlv = tr.value;
  if !_is_universal(&t, PKI_TAG_BOOLEAN) {
    return _err_bool(_at("pki: tag mismatch", off));
  }
  if t.len != 1 {
    return _err_bool(_at("pki: bad boolean", off));
  }
  let b: Int = _byte(data, t.content);
  var v = false;
  if b != 0 {
    v = true;
  }
  return _ok_bool(DerBool{ value: v; next: t.next; });
}

// Decode a BOOLEAN at `off` that must end at or before `end`.
fn _bool_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerBool, Str] {
  let r = der_bool_decode(data, off);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let b: DerBool = r.value;
  if b.next > end {
    return _err_bool(_at("pki: value overruns container", off));
  }
  return _ok_bool(b);
}

// Non-negative INTEGER value of a 1..8 byte content field [start, start+n):
// the content must not be empty, must not carry a sign-bit-set first byte
// and must be minimally encoded (a leading 0x00 is allowed only when the
// next byte has its high bit set). Reports at `base`.
fn _uint_content(data: &Vec[UInt8], start: Int, n: Int, base: Int) -> Result[Int, Str] {
  if n < 1 {
    return _err_int(_at("pki: empty integer", base));
  }
  if n > 8 {
    return _err_int(_at("pki: integer overflow", base));
  }
  let b0: Int = _byte(data, start);
  if b0 >= 128 {
    return _err_int(_at("pki: negative integer", base));
  }
  if n > 1 {
    let b1: Int = _byte(data, start + 1);
    if b0 == 0 && b1 < 128 {
      return _err_int(_at("pki: non-minimal integer", base));
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

/// Decode a non-negative INTEGER at `off` (tag 0x02); the numeric value must
/// fit in 8 content bytes.
/// Errors: the `der_tlv_decode` catalog, `pki: tag mismatch` at `off`, and
/// at the TLV's first byte `pki: empty integer`, `pki: integer overflow`,
/// `pki: negative integer` and `pki: non-minimal integer`.
/// Complexity: O(content bytes).
pub fn der_integer_decode(data: &Vec[UInt8], off: Int) -> Result[DerUint, Str] {
  let tr = der_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_uint(tr.error);
  }
  let t: DerTlv = tr.value;
  if !_is_universal(&t, PKI_TAG_INTEGER) {
    return _err_uint(_at("pki: tag mismatch", off));
  }
  let vr = _uint_content(data, t.content, t.len, _tlv_start(&t));
  if !vr.is_ok {
    return _err_uint(vr.error);
  }
  let v: Int = vr.value;
  return _ok_uint(DerUint{ value: v; next: t.next; });
}

// Decode a non-negative INTEGER at `off` that must end at or before `end`.
fn _uint_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerUint, Str] {
  let r = der_integer_decode(data, off);
  if !r.is_ok {
    return _err_uint(r.error);
  }
  let u: DerUint = r.value;
  if u.next > end {
    return _err_uint(_at("pki: value overruns container", off));
  }
  return _ok_uint(u);
}

/// Decode a BIT STRING at `off` (tag 0x03). The first content byte is the
/// unused-bit count (0..7); a zero-length content, a count above 7, a count
/// above zero with no bit bytes, or set bits inside the unused region are
/// rejected. `bit_length` is (content bytes - 1) * 8 - unused.
/// Errors: the `der_tlv_decode` catalog, `pki: tag mismatch` at `off`,
/// `pki: empty bit string` at `off`, `pki: bad unused bits` at the count
/// byte, and `pki: non-zero unused bits` at the last bit byte.
/// Complexity: O(1).
pub fn der_bit_string_decode(data: &Vec[UInt8], off: Int) -> Result[DerBits, Str] {
  let tr = der_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bits(tr.error);
  }
  let t: DerTlv = tr.value;
  if !_is_universal(&t, PKI_TAG_BIT_STRING) {
    return _err_bits(_at("pki: tag mismatch", off));
  }
  if t.len < 1 {
    return _err_bits(_at("pki: empty bit string", off));
  }
  let unused: Int = _byte(data, t.content);
  if unused > 7 {
    return _err_bits(_at("pki: bad unused bits", t.content));
  }
  let nbits: Int = t.len - 1;
  if nbits == 0 && unused != 0 {
    return _err_bits(_at("pki: bad unused bits", t.content));
  }
  if nbits > 0 {
    let last: Int = _byte(data, t.content + t.len - 1);
    if last % _pow2(unused) != 0 {
      return _err_bits(_at("pki: non-zero unused bits", t.content + t.len - 1));
    }
  }
  return _ok_bits(DerBits{ unused: unused; bit_length: nbits * 8 - unused; offset: t.content + 1; len: nbits; next: t.next; });
}

// Decode a BIT STRING at `off` that must end at or before `end`.
fn _bits_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerBits, Str] {
  let r = der_bit_string_decode(data, off);
  if !r.is_ok {
    return _err_bits(r.error);
  }
  let b: DerBits = r.value;
  if b.next > end {
    return _err_bits(_at("pki: value overruns container", off));
  }
  return _ok_bits(b);
}

// Big-endian value of the bit bytes [start, start+n); n must be 1..8 so the
// value fits an Int. Reports at `base`.
fn _bits_value(data: &Vec[UInt8], start: Int, n: Int, base: Int) -> Result[Int, Str] {
  if n < 1 {
    return _err_int(_at("pki: empty bit string", base));
  }
  if n > 8 {
    return _err_int(_at("pki: bit string too long", base));
  }
  var v = 0;
  var i = 0;
  while i < n {
    v = v * 256 + _byte(data, start + i);
    i = i + 1;
  }
  return _ok_int(v);
}

/// Decode an OCTET STRING at `off` (tag 0x04). The content bytes are copied
/// verbatim (no text validation); a zero-length string is valid.
/// Errors: the `der_tlv_decode` catalog and `pki: tag mismatch` at `off`.
/// Complexity: O(content bytes).
pub fn der_octet_string_decode(data: &Vec[UInt8], off: Int) -> Result[DerBytes, Str] {
  let tr = der_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_dbytes(tr.error);
  }
  let t: DerTlv = tr.value;
  if !_is_universal(&t, PKI_TAG_OCTET_STRING) {
    return _err_dbytes(_at("pki: tag mismatch", off));
  }
  let b: Vec[UInt8] = _copy_bytes(data, t.content, t.len);
  return _ok_dbytes(DerBytes{ bytes: b; next: t.next; });
}

// Decode an OCTET STRING at `off` that must end at or before `end`.
fn _octets_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerBytes, Str] {
  let r = der_octet_string_decode(data, off);
  if !r.is_ok {
    return _err_dbytes(r.error);
  }
  let b: DerBytes = r.value;
  if b.next > end {
    return _err_dbytes(_at("pki: value overruns container", off));
  }
  return _ok_dbytes(b);
}

/// Decode a NULL at `off` (tag 0x05). The content must be empty.
/// Errors: the `der_tlv_decode` catalog, `pki: tag mismatch` at `off` and
/// `pki: unexpected null content` at `off`.
/// Complexity: O(1).
pub fn der_null_decode(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  let tr = der_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_int(tr.error);
  }
  let t: DerTlv = tr.value;
  if !_is_universal(&t, PKI_TAG_NULL) {
    return _err_int(_at("pki: tag mismatch", off));
  }
  if t.len != 0 {
    return _err_int(_at("pki: unexpected null content", off));
  }
  return _ok_int(t.next);
}

// Decode a NULL at `off` that must end at or before `end`.
fn _null_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[Int, Str] {
  let r = der_null_decode(data, off);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let n: Int = r.value;
  if n > end {
    return _err_int(_at("pki: value overruns container", off));
  }
  return _ok_int(n);
}

// Dotted string of an OBJECT IDENTIFIER content field [start, start+n). The
// first subidentifier is one octet 40*a1 + a2 (a1 in 0..2, so the byte must
// be 0..119); every following arc is base-128 with the high bit as the
// continuation flag. Non-minimal arcs (a leading 0x80) and runs of more than
// PKI_MAX_OID_ARCS arcs are rejected. Reports at `base` (or at the offending
// byte for a non-minimal arc).
fn _oid_content(data: &Vec[UInt8], start: Int, n: Int, base: Int) -> Result[Str, Str] {
  if n < 1 {
    return _err_str(_at("pki: empty oid", base));
  }
  let b0: Int = _byte(data, start);
  if b0 >= 120 {
    return _err_str(_at("pki: bad oid", base));
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
        return _err_str(_at("pki: truncated oid", base));
      }
      let x: Int = _byte(data, i);
      if count == 0 && x == 128 {
        return _err_str(_at("pki: non-minimal oid arc", i));
      }
      arc = arc * 128 + (x % 128);
      if arc < 0 {
        return _err_str(_at("pki: oid overflow", base));
      }
      if x < 128 {
        done = true;
      } else {
        count = count + 1;
        if count > 8 {
          return _err_str(_at("pki: oid overflow", base));
        }
      }
      i = i + 1;
    }
    builder.sb_push_byte(&mut sb, 46 as UInt8);
    builder.sb_push_int(&mut sb, arc);
    arcs = arcs + 1;
    if arcs > PKI_MAX_OID_ARCS {
      return _err_str(_at("pki: oid too long", base));
    }
  }
  return _ok_str(builder.sb_to_str(&sb));
}

/// Decode an OBJECT IDENTIFIER at `off` (tag 0x06) into its dotted decimal
/// string ("1.2.840.113549..."). The first subidentifier is one octet; every
/// later arc is base-128, so multi-byte arcs are decoded. The empty content,
/// a first subidentifier 120..255, a non-minimal arc, an arc run that
/// overflows an Int and more than PKI_MAX_OID_ARCS arcs are errors.
/// Errors: the `der_tlv_decode` catalog, `pki: tag mismatch` at `off` and
/// the `_oid_content` catalog at the TLV's first byte.
/// Complexity: O(content bytes).
pub fn der_oid_decode(data: &Vec[UInt8], off: Int) -> Result[DerOid, Str] {
  let tr = der_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_oid(tr.error);
  }
  let t: DerTlv = tr.value;
  if !_is_universal(&t, PKI_TAG_OID) {
    return _err_oid(_at("pki: tag mismatch", off));
  }
  let vr = _oid_content(data, t.content, t.len, _tlv_start(&t));
  if !vr.is_ok {
    return _err_oid(vr.error);
  }
  let v: Str = vr.value;
  return _ok_oid(DerOid{ value: v; next: t.next; });
}

// Decode an OID at `off` that must end at or before `end`.
fn _oid_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerOid, Str] {
  let r = der_oid_decode(data, off);
  if !r.is_ok {
    return _err_oid(r.error);
  }
  let o: DerOid = r.value;
  if o.next > end {
    return _err_oid(_at("pki: value overruns container", off));
  }
  return _ok_oid(o);
}

// Index of the first invalid UTF-8 byte in data[start, start+n), or -1 when
// the range is valid and NUL-free. A 0x00 byte is reported as invalid because
// a XIOM Str is NUL-terminated at the ABI.
fn _utf8_bad(data: &Vec[UInt8], start: Int, n: Int) -> Int {
  var i = 0;
  while i < n {
    let b: Int = _byte(data, start + i);
    if b == 0 {
      return start + i;
    }
    if b < 128 {
      i = i + 1;
    } else {
      var need = 0;
      if b >= 194 && b <= 223 {
        need = 1;
      } elif b >= 224 && b <= 239 {
        need = 2;
      } elif b >= 240 && b <= 244 {
        need = 3;
      } else {
        return start + i;
      }
      if i + need >= n {
        return start + i;
      }
      var j = 1;
      while j <= need {
        let c: Int = _byte(data, start + i + j);
        if c < 128 || c > 191 {
          return start + i + j;
        }
        j = j + 1;
      }
      let c1: Int = _byte(data, start + i + 1);
      if need == 2 {
        if b == 224 && c1 < 160 {
          return start + i + 1;
        }
        if b == 237 && c1 > 159 {
          return start + i + 1;
        }
      }
      if need == 3 {
        if b == 240 && c1 < 144 {
          return start + i + 1;
        }
        if b == 244 && c1 > 143 {
          return start + i + 1;
        }
      }
      i = i + need + 1;
    }
  }
  return -1;
}

// Decoded Str of a string content field [start, start+n) whose bytes were
// already validated; callers guarantee the bounds. No NUL reaches sb_to_str.
fn _str_of(data: &Vec[UInt8], start: Int, n: Int) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < n {
    builder.sb_push_byte(&mut sb, data[start + i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Decoded Str of a UTF8String / PrintableString / IA5String content field
// with per-character-set validation. Reports the offending byte offset.
fn _string_content(data: &Vec[UInt8], tag: Int, start: Int, n: Int, base: Int) -> Result[Str, Str] {
  if tag == PKI_TAG_UTF8_STRING {
    let bad = _utf8_bad(data, start, n);
    if bad >= 0 {
      return _err_str(_at("pki: bad utf8 string", bad));
    }
  } elif tag == PKI_TAG_PRINTABLE_STRING {
    var i = 0;
    while i < n {
      let b: Int = _byte(data, start + i);
      if b < 32 || b > 126 {
        return _err_str(_at("pki: bad printable string", start + i));
      }
      i = i + 1;
    }
  } elif tag == PKI_TAG_IA5_STRING {
    var i = 0;
    while i < n {
      let b: Int = _byte(data, start + i);
      if b < 1 || b > 127 {
        return _err_str(_at("pki: bad ia5 string", start + i));
      }
      i = i + 1;
    }
  } else {
    return _err_str(_at("pki: unsupported string tag", base));
  }
  return _ok_str(_str_of(data, start, n));
}

/// Decode a UTF8String (0x0C), PrintableString (0x13) or IA5String (0x16)
/// at `off`. UTF8String bytes are UTF-8 validated (overlong forms, surrogates
/// and out-of-range sequences are rejected); PrintableString is restricted to
/// 0x20..0x7E; IA5String to 0x01..0x7F; a 0x00 byte is rejected everywhere
/// because a XIOM Str is NUL-terminated.
/// Errors: the `der_tlv_decode` catalog, `pki: tag mismatch` at `off` and
/// `pki: bad utf8 string` / `pki: bad printable string` /
/// `pki: bad ia5 string` at the offending byte.
/// Complexity: O(content bytes).
pub fn der_string_decode(data: &Vec[UInt8], off: Int) -> Result[DerString, Str] {
  let tr = der_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_dstr(tr.error);
  }
  let t: DerTlv = tr.value;
  if t.tag_class != PKI_CLASS_UNIVERSAL {
    return _err_dstr(_at("pki: tag mismatch", off));
  }
  let tag: Int = t.tag_number;
  if tag != PKI_TAG_UTF8_STRING && tag != PKI_TAG_PRINTABLE_STRING && tag != PKI_TAG_IA5_STRING {
    return _err_dstr(_at("pki: tag mismatch", off));
  }
  let vr = _string_content(data, tag, t.content, t.len, _tlv_start(&t));
  if !vr.is_ok {
    return _err_dstr(vr.error);
  }
  let v: Str = vr.value;
  return _ok_dstr(DerString{ value: v; next: t.next; });
}

// Decode a string at `off` that must end at or before `end`.
fn _string_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerString, Str] {
  let r = der_string_decode(data, off);
  if !r.is_ok {
    return _err_dstr(r.error);
  }
  let s: DerString = r.value;
  if s.next > end {
    return _err_dstr(_at("pki: value overruns container", off));
  }
  return _ok_dstr(s);
}

// Decimal value of the digit at `pos`, or -1 when the byte is not 0x30..0x39.
fn _digit(data: &Vec[UInt8], pos: Int) -> Int {
  let b: Int = _byte(data, pos);
  if b < 48 || b > 57 {
    return -1;
  }
  return b - 48;
}

// Structured time of a UTCTime (tag 23) or GeneralizedTime (tag 24) content
// field. UTCTime is exactly "YYMMDDhhmmssZ" (13 bytes; YY < 50 maps to 20YY,
// else 19YY); GeneralizedTime is exactly "YYYYMMDDhhmmssZ" (15 bytes). Ranges
// are checked (month 1..12, day 1..31, hour 0..23, minute 0..59, second
// 0..59); calendar length is not. Reports at the offending byte.
fn _time_content(data: &Vec[UInt8], tag: Int, start: Int, n: Int, base: Int) -> Result[DerTime, Str] {
  if tag == PKI_TAG_UTC_TIME {
    if n != 13 {
      return _err_time(_at("pki: bad utc time", base));
    }
  } else {
    if n != 15 {
      return _err_time(_at("pki: bad generalized time", base));
    }
  }
  let nsecs = n - 1;
  var i = 0;
  while i < nsecs {
    if _digit(data, start + i) < 0 {
      return _err_time(_at("pki: bad time digit", start + i));
    }
    i = i + 1;
  }
  if _byte(data, start + nsecs) != 90 {
    return _err_time(_at("pki: bad time zone", start + nsecs));
  }
  var year = 0;
  var month = 0;
  var day = 0;
  var hour = 0;
  var minute = 0;
  var second = 0;
  if tag == PKI_TAG_UTC_TIME {
    let yy: Int = _digit(data, start) * 10 + _digit(data, start + 1);
    if yy < 50 {
      year = 2000 + yy;
    } else {
      year = 1900 + yy;
    }
    month = _digit(data, start + 2) * 10 + _digit(data, start + 3);
    day = _digit(data, start + 4) * 10 + _digit(data, start + 5);
    hour = _digit(data, start + 6) * 10 + _digit(data, start + 7);
    minute = _digit(data, start + 8) * 10 + _digit(data, start + 9);
    second = _digit(data, start + 10) * 10 + _digit(data, start + 11);
  } else {
    year = _digit(data, start) * 1000 + _digit(data, start + 1) * 100;
    year = year + _digit(data, start + 2) * 10 + _digit(data, start + 3);
    month = _digit(data, start + 4) * 10 + _digit(data, start + 5);
    day = _digit(data, start + 6) * 10 + _digit(data, start + 7);
    hour = _digit(data, start + 8) * 10 + _digit(data, start + 9);
    minute = _digit(data, start + 10) * 10 + _digit(data, start + 11);
    second = _digit(data, start + 12) * 10 + _digit(data, start + 13);
  }
  if month < 1 || month > 12 {
    return _err_time(_at("pki: bad time month", base));
  }
  if day < 1 || day > 31 {
    return _err_time(_at("pki: bad time day", base));
  }
  if hour > 23 {
    return _err_time(_at("pki: bad time hour", base));
  }
  if minute > 59 {
    return _err_time(_at("pki: bad time minute", base));
  }
  if second > 59 {
    return _err_time(_at("pki: bad time second", base));
  }
  var utc = false;
  if tag == PKI_TAG_UTC_TIME {
    utc = true;
  }
  return _ok_time(DerTime{ year: year; month: month; day: day; hour: hour; minute: minute; second: second; utc: utc; next: 0; });
}

/// Decode a UTCTime (0x17) or GeneralizedTime (0x18) at `off` into
/// structured fields. Only the RFC 5280 certificate shapes are accepted:
/// "YYMMDDhhmmssZ" (13 bytes) and "YYYYMMDDhhmmssZ" (15 bytes), both with a
/// literal 'Z' and no fractional seconds or zone offsets.
/// Errors: the `der_tlv_decode` catalog, `pki: tag mismatch` at `off` and
/// the `_time_content` catalog (reported at the offending byte).
/// Complexity: O(1) (at most 15 bytes).
pub fn der_time_decode(data: &Vec[UInt8], off: Int) -> Result[DerTime, Str] {
  let tr = der_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_time(tr.error);
  }
  let t: DerTlv = tr.value;
  if t.tag_class != PKI_CLASS_UNIVERSAL {
    return _err_time(_at("pki: tag mismatch", off));
  }
  let tag: Int = t.tag_number;
  if tag != PKI_TAG_UTC_TIME && tag != PKI_TAG_GENERALIZED_TIME {
    return _err_time(_at("pki: tag mismatch", off));
  }
  let vr = _time_content(data, tag, t.content, t.len, _tlv_start(&t));
  if !vr.is_ok {
    return _err_time(vr.error);
  }
  let v: DerTime = vr.value;
  return _ok_time(DerTime{ year: v.year; month: v.month; day: v.day; hour: v.hour; minute: v.minute; second: v.second; utc: v.utc; next: t.next; });
}

// Decode a time at `off` that must end at or before `end`.
fn _time_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerTime, Str] {
  let r = der_time_decode(data, off);
  if !r.is_ok {
    return _err_time(r.error);
  }
  let v: DerTime = r.value;
  if v.next > end {
    return _err_time(_at("pki: value overruns container", off));
  }
  return _ok_time(v);
}

// --------------------------------------------------
//  X.509 building blocks
// --------------------------------------------------

/// Decoded SubjectPublicKeyInfo: the algorithm OID and the subjectPublicKey
/// BIT STRING's significant bit length, plus `next`.
pub type PkiSpki = {
  alg_oid: Str;
  key_bits: Int;
  next: Int;
}

/// Decoded basicConstraints: `ca` is the cA flag (default false) and
/// `path_len` is the pathLenConstraint (-1 when absent), plus `next`.
pub type PkiBasicConstraints = {
  ca: Bool;
  path_len: Int;
  next: Int;
}

// Ok(v) for Result[PkiSpki, Str].
fn _ok_spki(v: PkiSpki) -> Result[PkiSpki, Str] {
  return Ok(v);
}

// Err(m) for Result[PkiSpki, Str].
fn _err_spki(m: Str) -> Result[PkiSpki, Str] {
  return Err(m);
}

// Ok(v) for Result[PkiBasicConstraints, Str].
fn _ok_bcp(v: PkiBasicConstraints) -> Result[PkiBasicConstraints, Str] {
  return Ok(v);
}

// Err(m) for Result[PkiBasicConstraints, Str].
fn _err_bcp(m: Str) -> Result[PkiBasicConstraints, Str] {
  return Err(m);
}

// One upper-case hex digit of a 0..15 value.
fn _hex_digit(v: Int) -> UInt8 {
  return string.byte_at("0123456789ABCDEF", v);
}

// Dotted-quad IPv4 text of the four bytes at `start`.
fn _ip4_str(data: &Vec[UInt8], start: Int) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < 4 {
    builder.sb_push_int(&mut sb, _byte(data, start + i));
    if i < 3 {
      builder.sb_push_byte(&mut sb, 46 as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Uncompressed IPv6 text ("2:0:1:...": exactly eight hextets, each without
// leading zeros) of the sixteen bytes at `start`.
fn _ip6_str(data: &Vec[UInt8], start: Int) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < 8 {
    let hi: Int = _byte(data, start + i * 2);
    let lo: Int = _byte(data, start + i * 2 + 1);
    let v: Int = hi * 256 + lo;
    let d0: Int = v / 4096;
    let d1: Int = (v / 256) % 16;
    let d2: Int = (v / 16) % 16;
    let d3: Int = v % 16;
    if d0 > 0 {
      builder.sb_push_byte(&mut sb, _hex_digit(d0));
      builder.sb_push_byte(&mut sb, _hex_digit(d1));
      builder.sb_push_byte(&mut sb, _hex_digit(d2));
      builder.sb_push_byte(&mut sb, _hex_digit(d3));
    } elif d1 > 0 {
      builder.sb_push_byte(&mut sb, _hex_digit(d1));
      builder.sb_push_byte(&mut sb, _hex_digit(d2));
      builder.sb_push_byte(&mut sb, _hex_digit(d3));
    } elif d2 > 0 {
      builder.sb_push_byte(&mut sb, _hex_digit(d2));
      builder.sb_push_byte(&mut sb, _hex_digit(d3));
    } else {
      builder.sb_push_byte(&mut sb, _hex_digit(d3));
    }
    if i < 7 {
      builder.sb_push_byte(&mut sb, 58 as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Serial number content field [start, start+n): 1..PKI_MAX_SERIAL_BYTES
// bytes, positive (no sign-bit-set first byte) and minimally encoded (the
// 0x00 pad is allowed only when the next byte has its high bit set). Reports
// at `base`.
fn _serial_content(data: &Vec[UInt8], start: Int, n: Int, base: Int) -> Result[Vec[UInt8], Str] {
  if n < 1 {
    return _err_bytes(_at("pki: empty serial", base));
  }
  if n > PKI_MAX_SERIAL_BYTES {
    return _err_bytes(_at("pki: serial too long", base));
  }
  let b0: Int = _byte(data, start);
  if b0 >= 128 {
    return _err_bytes(_at("pki: negative serial", base));
  }
  if n > 1 {
    let b1: Int = _byte(data, start + 1);
    if b0 == 0 && b1 < 128 {
      return _err_bytes(_at("pki: non-minimal serial", base));
    }
  }
  return _ok_bytes(_copy_bytes(data, start, n));
}

// AlgorithmIdentifier ::= SEQUENCE { algorithm OBJECT IDENTIFIER, ... }.
// Decodes the algorithm OID and skips (without interpreting) any trailing
// parameter TLVs inside the SEQUENCE; the result's `next` is past the whole
// SEQUENCE.
fn _alg_oid_at(data: &Vec[UInt8], off: Int, end: Int) -> Result[DerOid, Str] {
  let sr = der_tlv_in(data, off, end);
  if !sr.is_ok {
    return _err_oid(sr.error);
  }
  let s: DerTlv = sr.value;
  if !_is_universal(&s, PKI_TAG_SEQUENCE) {
    return _err_oid(_at("pki: bad algorithm identifier", off));
  }
  if s.len == 0 {
    return _err_oid(_at("pki: bad algorithm identifier", off));
  }
  let orv = _oid_in(data, s.content, s.next);
  if !orv.is_ok {
    return _err_oid(orv.error);
  }
  let o: DerOid = orv.value;
  var p = o.next;
  while p < s.next {
    let pt = der_tlv_in(data, p, s.next);
    if !pt.is_ok {
      return _err_oid(pt.error);
    }
    let t: DerTlv = pt.value;
    p = t.next;
  }
  return _ok_oid(DerOid{ value: o.value; next: s.next });
}

// SubjectPublicKeyInfo ::= SEQUENCE { algorithm, subjectPublicKey BIT
// STRING }. Decodes the algorithm OID and the key BIT STRING's bit length.
fn _spki_at(data: &Vec[UInt8], off: Int, end: Int) -> Result[PkiSpki, Str] {
  let sr = der_tlv_in(data, off, end);
  if !sr.is_ok {
    return _err_spki(sr.error);
  }
  let s: DerTlv = sr.value;
  if !_is_universal(&s, PKI_TAG_SEQUENCE) {
    return _err_spki(_at("pki: bad subject public key info", off));
  }
  if s.len == 0 {
    return _err_spki(_at("pki: bad subject public key info", off));
  }
  let ar = _alg_oid_at(data, s.content, s.next);
  if !ar.is_ok {
    return _err_spki(ar.error);
  }
  let a: DerOid = ar.value;
  let br = _bits_in(data, a.next, s.next);
  if !br.is_ok {
    return _err_spki(br.error);
  }
  let b: DerBits = br.value;
  return _ok_spki(PkiSpki{ alg_oid: a.value; key_bits: b.bit_length; next: s.next });
}

// RDNSequence ::= SEQUENCE OF SET OF AttributeTypeAndValue. Every attribute
// is appended to the four parallel vectors with the same 0-based RDN ordinal.
// Values of UTF8String/PrintableString/IA5String are decoded; any other value
// type is recorded as value tag -1 with an empty string.
fn _name_at(data: &Vec[UInt8], off: Int, end: Int) -> Result[PkiName, Str] {
  let sr = der_tlv_in(data, off, end);
  if !sr.is_ok {
    return _err_name(sr.error);
  }
  let s: DerTlv = sr.value;
  if !_is_universal(&s, PKI_TAG_SEQUENCE) {
    return _err_name(_at("pki: bad name", off));
  }
  var rdn_index = Vec[Int].new();
  var oids = Vec[Str].new();
  var value_tags = Vec[Int].new();
  var values = Vec[Str].new();
  var rdn_count = 0;
  var p = s.content;
  while p < s.next {
    let setr = der_tlv_in(data, p, s.next);
    if !setr.is_ok {
      return _err_name(setr.error);
    }
    let set: DerTlv = setr.value;
    if !_is_universal(&set, PKI_TAG_SET) {
      return _err_name(_at("pki: bad rdn set", p));
    }
    if set.len == 0 {
      return _err_name(_at("pki: bad rdn set", p));
    }
    var q = set.content;
    while q < set.next {
      let avr = der_tlv_in(data, q, set.next);
      if !avr.is_ok {
        return _err_name(avr.error);
      }
      let ava: DerTlv = avr.value;
      if !_is_universal(&ava, PKI_TAG_SEQUENCE) {
        return _err_name(_at("pki: bad attribute", q));
      }
      if ava.len == 0 {
        return _err_name(_at("pki: bad attribute", q));
      }
      let orv = _oid_in(data, ava.content, ava.next);
      if !orv.is_ok {
        return _err_name(orv.error);
      }
      let o: DerOid = orv.value;
      if o.next >= ava.next {
        return _err_name(_at("pki: missing attribute value", o.next));
      }
      let vr = der_tlv_in(data, o.next, ava.next);
      if !vr.is_ok {
        return _err_name(vr.error);
      }
      let vt: DerTlv = vr.value;
      if vt.next != ava.next {
        return _err_name(_at("pki: trailing attribute data", vt.next));
      }
      var vtag = -1;
      var vstr = "";
      if vt.tag_class == PKI_CLASS_UNIVERSAL {
        let tag: Int = vt.tag_number;
        if tag == PKI_TAG_UTF8_STRING || tag == PKI_TAG_PRINTABLE_STRING || tag == PKI_TAG_IA5_STRING {
          let strr = _string_content(data, tag, vt.content, vt.len, _tlv_start(&vt));
          if !strr.is_ok {
            return _err_name(strr.error);
          }
          let sv: Str = strr.value;
          vtag = tag;
          vstr = sv;
        }
      }
      rdn_index.push(rdn_count);
      oids.push(o.value);
      value_tags.push(vtag);
      values.push(vstr);
      q = ava.next;
    }
    rdn_count = rdn_count + 1;
    p = set.next;
  }
  return _ok_name(PkiName{ rdn_index: rdn_index; oids: oids; value_tags: value_tags; values: values; rdn_count: rdn_count; next: s.next });
}

// basicConstraints ::= SEQUENCE { cA BOOLEAN DEFAULT FALSE,
// pathLenConstraint INTEGER OPTIONAL }. The extnValue bytes start at `start`
// and end at `end`.
fn _bc_parse(data: &Vec[UInt8], start: Int, stop: Int) -> Result[PkiBasicConstraints, Str] {
  let sr = der_tlv_in(data, start, stop);
  if !sr.is_ok {
    return _err_bcp(sr.error);
  }
  let s: DerTlv = sr.value;
  if !_is_universal(&s, PKI_TAG_SEQUENCE) {
    return _err_bcp(_at("pki: bad basic constraints", start));
  }
  if s.next != stop {
    return _err_bcp(_at("pki: bad basic constraints", s.next));
  }
  var ca = false;
  var path_len = -1;
  var p = s.content;
  while p < s.next {
    let cr = der_tlv_in(data, p, s.next);
    if !cr.is_ok {
      return _err_bcp(cr.error);
    }
    let c: DerTlv = cr.value;
    if _is_universal(&c, PKI_TAG_BOOLEAN) {
      if c.len != 1 {
        return _err_bcp(_at("pki: bad basic constraints", p));
      }
      if _byte(data, c.content) != 0 {
        ca = true;
      }
    } elif _is_universal(&c, PKI_TAG_INTEGER) {
      let irv = _uint_content(data, c.content, c.len, _tlv_start(&c));
      if !irv.is_ok {
        return _err_bcp(irv.error);
      }
      let iv: Int = irv.value;
      path_len = iv;
    } else {
      return _err_bcp(_at("pki: bad basic constraints", p));
    }
    p = c.next;
  }
  return _ok_bcp(PkiBasicConstraints{ ca: ca; path_len: path_len; next: s.next });
}

// extKeyUsage ::= SEQUENCE OF OBJECT IDENTIFIER; appends every dotted OID to
// `out` (in wire order) and returns Ok(0).
fn _eku_parse(data: &Vec[UInt8], start: Int, stop: Int, out: &mut Vec[Str]) -> Result[Int, Str] {
  let sr = der_tlv_in(data, start, stop);
  if !sr.is_ok {
    return _err_int(sr.error);
  }
  let s: DerTlv = sr.value;
  if !_is_universal(&s, PKI_TAG_SEQUENCE) {
    return _err_int(_at("pki: bad ext key usage", start));
  }
  if s.next != stop {
    return _err_int(_at("pki: bad ext key usage", s.next));
  }
  var p = s.content;
  while p < s.next {
    let orv = _oid_in(data, p, s.next);
    if !orv.is_ok {
      return _err_int(orv.error);
    }
    let o: DerOid = orv.value;
    out.push(o.value);
    p = o.next;
  }
  return _ok_int(0);
}

// subjectAltName ::= SEQUENCE OF GeneralName. Decoded choices: rfc822Name
// [1], dNSName [2] and uniformResourceIdentifier [6] (IA5String text) and
// iPAddress [7] (4-byte dotted quad or uncompressed 16-byte IPv6 text). Any
// other choice is recorded with its type number and an empty value. The
// parallel outputs are pushed in lockstep.
fn _san_parse(data: &Vec[UInt8], start: Int, stop: Int, types: &mut Vec[Int], values: &mut Vec[Str]) -> Result[Int, Str] {
  let sr = der_tlv_in(data, start, stop);
  if !sr.is_ok {
    return _err_int(sr.error);
  }
  let s: DerTlv = sr.value;
  if !_is_universal(&s, PKI_TAG_SEQUENCE) {
    return _err_int(_at("pki: bad subject alt name", start));
  }
  if s.next != stop {
    return _err_int(_at("pki: bad subject alt name", s.next));
  }
  var p = s.content;
  while p < s.next {
    let gr = der_tlv_in(data, p, s.next);
    if !gr.is_ok {
      return _err_int(gr.error);
    }
    let g: DerTlv = gr.value;
    if g.tag_class != PKI_CLASS_CONTEXT {
      return _err_int(_at("pki: bad general name", p));
    }
    let gtype: Int = g.tag_number;
    if gtype == PKI_SAN_EMAIL || gtype == PKI_SAN_DNS || gtype == PKI_SAN_URI {
      let strr = _string_content(data, PKI_TAG_IA5_STRING, g.content, g.len, _tlv_start(&g));
      if !strr.is_ok {
        return _err_int(strr.error);
      }
      let sv: Str = strr.value;
      types.push(gtype);
      values.push(sv);
    } elif gtype == PKI_SAN_IP {
      if g.len == 4 {
        let ip: Str = _ip4_str(data, g.content);
        types.push(gtype);
        values.push(ip);
      } elif g.len == 16 {
        let ip6: Str = _ip6_str(data, g.content);
        types.push(gtype);
        values.push(ip6);
      } else {
        return _err_int(_at("pki: bad ip address", _tlv_start(&g)));
      }
    } else {
      types.push(gtype);
      values.push("");
    }
    p = g.next;
  }
  return _ok_int(0);
}

// An extension set with no extensions and every decoded payload neutral.
fn _empty_exts() -> PkiExtensions {
  var oids = Vec[Str].new();
  var critical = Vec[Int].new();
  var eku_oids = Vec[Str].new();
  var san_types = Vec[Int].new();
  var san_values = Vec[Str].new();
  return PkiExtensions{ oids: oids; critical: critical; has_basic_constraints: false; ca: false; path_len: -1; has_key_usage: false; key_usage: 0; has_ext_key_usage: false; eku_oids: eku_oids; has_san: false; san_types: san_types; san_values: san_values; has_subject_key_id: false; subject_key_id_hex: ""; has_authority_key_id: false; authority_key_id_hex: ""; next: 0; };
}

// Upper-case hex string of every byte of `v`; the result contains no NUL
// bytes.
fn _hex_of(v: &Vec[UInt8]) -> Str {
  let alpha = "0123456789ABCDEF";
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b / 16));
    out.push(string.byte_at(alpha, b % 16));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// subjectKeyIdentifier extnValue: exactly one OCTET STRING; the result is the
// uppercase hex of its content. An empty key identifier is rejected.
fn _ski_parse(data: &Vec[UInt8], start: Int, stop: Int) -> Result[Str, Str] {
  let br = _octets_in(data, start, stop);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let b: DerBytes = br.value;
  if b.next != stop {
    return _err_str(_at("pki: bad subject key id", b.next));
  }
  if b.bytes.len() == 0 {
    return _err_str(_at("pki: bad subject key id", start));
  }
  let bytes: Vec[UInt8] = b.bytes;
  return _ok_str(_hex_of(&bytes));
}

// authorityKeyIdentifier extnValue: a SEQUENCE whose keyIdentifier [0]
// primitive field (when present) is captured as uppercase hex; other fields
// are skipped without interpretation. The result is "" when keyIdentifier is
// absent.
fn _aki_parse(data: &Vec[UInt8], start: Int, stop: Int) -> Result[Str, Str] {
  let sr = der_tlv_in(data, start, stop);
  if !sr.is_ok {
    return _err_str(sr.error);
  }
  let s: DerTlv = sr.value;
  if !_is_universal(&s, PKI_TAG_SEQUENCE) {
    return _err_str(_at("pki: bad authority key id", start));
  }
  if s.next != stop {
    return _err_str(_at("pki: bad authority key id", s.next));
  }
  var hex: Str = "";
  var p = s.content;
  while p < s.next {
    let fr = der_tlv_in(data, p, s.next);
    if !fr.is_ok {
      return _err_str(fr.error);
    }
    let f: DerTlv = fr.value;
    if f.tag_class == PKI_CLASS_CONTEXT && f.tag_number == 0 {
      hex = _hex_from(data, f.content, f.len);
    }
    p = f.next;
  }
  return _ok_str(hex);
}

// Extensions ::= [3] EXPLICIT SEQUENCE OF Extension. Decodes every extension
// into the flat PkiExtensions model: oids/critical in wire order (unknown
// OIDs preserved), known payloads into their flags and fields. A malformed
// known extension fails the whole parse with the nested error.
fn _exts_at(data: &Vec[UInt8], off: Int, end: Int) -> Result[PkiExtensions, Str] {
  let tr = der_tlv_in(data, off, end);
  if !tr.is_ok {
    return _err_exts(tr.error);
  }
  let t: DerTlv = tr.value;
  if t.tag_class != PKI_CLASS_CONTEXT || t.tag_number != PKI_TAG_EXTENSIONS || !t.constructed {
    return _err_exts(_at("pki: bad extensions", off));
  }
  if t.len == 0 {
    return _err_exts(_at("pki: bad extensions", off));
  }
  let sr = der_tlv_in(data, t.content, t.next);
  if !sr.is_ok {
    return _err_exts(sr.error);
  }
  let s: DerTlv = sr.value;
  if !_is_universal(&s, PKI_TAG_SEQUENCE) {
    return _err_exts(_at("pki: bad extensions", t.content));
  }
  var oids = Vec[Str].new();
  var critical = Vec[Int].new();
  var has_bc = false;
  var bc_ca = false;
  var bc_path = -1;
  var has_ku = false;
  var ku_bits = 0;
  var has_eku = false;
  var eku_oids = Vec[Str].new();
  var has_san = false;
  var san_types = Vec[Int].new();
  var san_values = Vec[Str].new();
  var has_ski = false;
  var ski_hex: Str = "";
  var has_aki = false;
  var aki_hex: Str = "";
  var p = s.content;
  while p < s.next {
    let extr = der_tlv_in(data, p, s.next);
    if !extr.is_ok {
      return _err_exts(extr.error);
    }
    let ext: DerTlv = extr.value;
    if !_is_universal(&ext, PKI_TAG_SEQUENCE) {
      return _err_exts(_at("pki: bad extension", p));
    }
    if ext.len == 0 {
      return _err_exts(_at("pki: bad extension", p));
    }
    let orv = _oid_in(data, ext.content, ext.next);
    if !orv.is_ok {
      return _err_exts(orv.error);
    }
    let o: DerOid = orv.value;
    let oid_str: Str = o.value;
    var crit = 0;
    var p2 = o.next;
    if p2 >= ext.next {
      return _err_exts(_at("pki: bad extension", p2));
    }
    let fr = der_tlv_in(data, p2, ext.next);
    if !fr.is_ok {
      return _err_exts(fr.error);
    }
    var field: DerTlv = fr.value;
    if _is_universal(&field, PKI_TAG_BOOLEAN) {
      if field.len != 1 {
        return _err_exts(_at("pki: bad extension", p2));
      }
      if _byte(data, field.content) != 0 {
        crit = 1;
      }
      p2 = field.next;
      if p2 >= ext.next {
        return _err_exts(_at("pki: bad extension", p2));
      }
      let fr2 = der_tlv_in(data, p2, ext.next);
      if !fr2.is_ok {
        return _err_exts(fr2.error);
      }
      field = fr2.value;
    }
    if !_is_universal(&field, PKI_TAG_OCTET_STRING) {
      return _err_exts(_at("pki: bad extension", p2));
    }
    if field.next != ext.next {
      return _err_exts(_at("pki: bad extension", field.next));
    }
    let vstart: Int = field.content;
    let vstop: Int = field.next;
    if _streq(oid_str, PKI_OID_BASIC_CONSTRAINTS) {
      let br = _bc_parse(data, vstart, vstop);
      if !br.is_ok {
        return _err_exts(br.error);
      }
      let b: PkiBasicConstraints = br.value;
      has_bc = true;
      bc_ca = b.ca;
      bc_path = b.path_len;
    } elif _streq(oid_str, PKI_OID_KEY_USAGE) {
      let br = _bits_in(data, vstart, vstop);
      if !br.is_ok {
        return _err_exts(br.error);
      }
      let b: DerBits = br.value;
      if b.next != vstop {
        return _err_exts(_at("pki: bad key usage", b.next));
      }
      if b.len < 1 || b.len > 2 {
        return _err_exts(_at("pki: bad key usage", vstart));
      }
      let vrv = _bits_value(data, b.offset, b.len, vstart);
      if !vrv.is_ok {
        return _err_exts(vrv.error);
      }
      let kv: Int = vrv.value;
      has_ku = true;
      if b.len == 1 {
        ku_bits = kv * 256;
      } else {
        ku_bits = kv;
      }
    } elif _streq(oid_str, PKI_OID_EXT_KEY_USAGE) {
      let er = _eku_parse(data, vstart, vstop, &mut eku_oids);
      if !er.is_ok {
        return _err_exts(er.error);
      }
      has_eku = true;
    } elif _streq(oid_str, PKI_OID_SUBJECT_ALT_NAME) {
      let sar = _san_parse(data, vstart, vstop, &mut san_types, &mut san_values);
      if !sar.is_ok {
        return _err_exts(sar.error);
      }
      has_san = true;
    } elif _streq(oid_str, PKI_OID_SUBJECT_KEY_ID) {
      let skr = _ski_parse(data, vstart, vstop);
      if !skr.is_ok {
        return _err_exts(skr.error);
      }
      let sh: Str = skr.value;
      has_ski = true;
      ski_hex = sh;
    } elif _streq(oid_str, PKI_OID_AUTHORITY_KEY_ID) {
      let akr = _aki_parse(data, vstart, vstop);
      if !akr.is_ok {
        return _err_exts(akr.error);
      }
      let ah: Str = akr.value;
      has_aki = true;
      aki_hex = ah;
    }
    oids.push(oid_str);
    critical.push(crit);
    p = ext.next;
  }
  return _ok_exts(PkiExtensions{ oids: oids; critical: critical; has_basic_constraints: has_bc; ca: bc_ca; path_len: bc_path; has_key_usage: has_ku; key_usage: ku_bits; has_ext_key_usage: has_eku; eku_oids: eku_oids; has_san: has_san; san_types: san_types; san_values: san_values; has_subject_key_id: has_ski; subject_key_id_hex: ski_hex; has_authority_key_id: has_aki; authority_key_id_hex: aki_hex; next: s.next });
}

/// Parse one DER X.509 certificate. Structure only: no signature, key,
/// name, extension-criticality or validity semantics are enforced beyond the
/// shapes documented in SPEC.md. The whole buffer must be exactly one
/// Certificate TLV (`pki: trailing data` otherwise).
///
/// Errors: the `der_tlv_decode` catalog and the building-block catalogs above
/// (`pki: bad ...` messages), each naming a byte offset.
/// Complexity: O(data.len()).
pub fn pki_certificate_parse(data: &Vec[UInt8]) -> Result[PkiCertificate, Str] {
  let cr = der_tlv_decode(data, 0);
  if !cr.is_ok {
    return _err_cert(cr.error);
  }
  let c: DerTlv = cr.value;
  if !_is_universal(&c, PKI_TAG_SEQUENCE) || !c.constructed {
    return _err_cert(_at("pki: bad certificate", 0));
  }
  if c.len == 0 {
    return _err_cert(_at("pki: bad certificate", 0));
  }
  if c.next != data.len() {
    return _err_cert(_at("pki: trailing data", c.next));
  }
  let tbsr = der_tlv_in(data, c.content, c.next);
  if !tbsr.is_ok {
    return _err_cert(tbsr.error);
  }
  let tbs: DerTlv = tbsr.value;
  if !_is_universal(&tbs, PKI_TAG_SEQUENCE) {
    return _err_cert(_at("pki: bad tbs certificate", c.content));
  }
  if tbs.len == 0 {
    return _err_cert(_at("pki: bad tbs certificate", c.content));
  }
  var p = tbs.content;
  var version = PKI_VERSION_V1;
  let fr = der_tlv_in(data, p, tbs.next);
  if !fr.is_ok {
    return _err_cert(fr.error);
  }
  let first: DerTlv = fr.value;
  if first.tag_class == PKI_CLASS_CONTEXT && first.tag_number == PKI_TAG_VERSION {
    if !first.constructed {
      return _err_cert(_at("pki: bad version", p));
    }
    if first.len == 0 {
      return _err_cert(_at("pki: bad version", p));
    }
    let vr = _uint_in(data, first.content, first.next);
    if !vr.is_ok {
      return _err_cert(vr.error);
    }
    let v: DerUint = vr.value;
    if v.next != first.next {
      return _err_cert(_at("pki: bad version", v.next));
    }
    if v.value > 2 {
      return _err_cert(_at("pki: bad version", first.content));
    }
    version = v.value;
    p = first.next;
  }
  let serr = der_tlv_in(data, p, tbs.next);
  if !serr.is_ok {
    return _err_cert(serr.error);
  }
  let ser: DerTlv = serr.value;
  if !_is_universal(&ser, PKI_TAG_INTEGER) {
    return _err_cert(_at("pki: bad serial number", p));
  }
  let sb = _serial_content(data, ser.content, ser.len, _tlv_start(&ser));
  if !sb.is_ok {
    return _err_cert(sb.error);
  }
  let serial_bytes: Vec[UInt8] = sb.value;
  let serial_hex: Str = _hex_from(data, ser.content, ser.len);
  p = ser.next;
  let tsigr = _alg_oid_at(data, p, tbs.next);
  if !tsigr.is_ok {
    return _err_cert(tsigr.error);
  }
  let tsig: DerOid = tsigr.value;
  let tsig_oid: Str = tsig.value;
  p = tsig.next;
  let issr = _name_at(data, p, tbs.next);
  if !issr.is_ok {
    return _err_cert(issr.error);
  }
  let issuer: PkiName = issr.value;
  p = issuer.next;
  let valr = der_tlv_in(data, p, tbs.next);
  if !valr.is_ok {
    return _err_cert(valr.error);
  }
  let val: DerTlv = valr.value;
  if !_is_universal(&val, PKI_TAG_SEQUENCE) || val.len == 0 {
    return _err_cert(_at("pki: bad validity", p));
  }
  let nbr = _time_in(data, val.content, val.next);
  if !nbr.is_ok {
    return _err_cert(nbr.error);
  }
  let nb: DerTime = nbr.value;
  if nb.next >= val.next {
    return _err_cert(_at("pki: bad validity", val.next));
  }
  let nar = _time_in(data, nb.next, val.next);
  if !nar.is_ok {
    return _err_cert(nar.error);
  }
  let na: DerTime = nar.value;
  if na.next != val.next {
    return _err_cert(_at("pki: bad validity", na.next));
  }
  p = val.next;
  let subjr = _name_at(data, p, tbs.next);
  if !subjr.is_ok {
    return _err_cert(subjr.error);
  }
  let subject: PkiName = subjr.value;
  p = subject.next;
  let spkir = _spki_at(data, p, tbs.next);
  if !spkir.is_ok {
    return _err_cert(spkir.error);
  }
  let spki: PkiSpki = spkir.value;
  let spki_oid: Str = spki.alg_oid;
  p = spki.next;
  var exts = _empty_exts();
  var exts_parsed = false;
  while p < tbs.next {
    let optr = der_tlv_in(data, p, tbs.next);
    if !optr.is_ok {
      return _err_cert(optr.error);
    }
    let opt: DerTlv = optr.value;
    if opt.tag_class != PKI_CLASS_CONTEXT {
      return _err_cert(_at("pki: bad tbs field", p));
    }
    let on: Int = opt.tag_number;
    if on == PKI_TAG_EXTENSIONS {
      if exts_parsed {
        return _err_cert(_at("pki: duplicate extensions", p));
      }
      if !opt.constructed {
        return _err_cert(_at("pki: bad extensions", p));
      }
      let xr = _exts_at(data, p, tbs.next);
      if !xr.is_ok {
        return _err_cert(xr.error);
      }
      exts = xr.value;
      exts_parsed = true;
      p = opt.next;
      if p != tbs.next {
        return _err_cert(_at("pki: trailing tbs data", p));
      }
    } elif on == 1 || on == 2 {
      p = opt.next;
    } else {
      return _err_cert(_at("pki: bad tbs field", p));
    }
  }
  let osigr = _alg_oid_at(data, p, c.next);
  if !osigr.is_ok {
    return _err_cert(osigr.error);
  }
  let osig: DerOid = osigr.value;
  let osig_oid: Str = osig.value;
  p = osig.next;
  let svr = _bits_in(data, p, c.next);
  if !svr.is_ok {
    return _err_cert(svr.error);
  }
  let sv: DerBits = svr.value;
  if sv.next != c.next {
    return _err_cert(_at("pki: trailing tbs data", sv.next));
  }
  return _ok_cert(PkiCertificate{ version: version; serial_hex: serial_hex; serial_len: serial_bytes.len(); serial_bytes: serial_bytes; tbs_sig_oid: tsig_oid; outer_sig_oid: osig_oid; issuer: issuer; subject: subject; not_before: nb; not_after: na; spki_alg_oid: spki_oid; spki_key_bits: spki.key_bits; extensions: exts; tbs_offset: tbs.content; tbs_len: tbs.len; sig_offset: sv.offset; sig_len: sv.len; sig_unused: sv.unused; next: c.next });
}

// --------------------------------------------------
//  PEM unwrap
// --------------------------------------------------

// Byte at `pos` of a Str widened to an Int (0..255); callers guarantee the
// bounds.
fn _tb(text: Str, pos: Int) -> Int {
  return (string.byte_at(text, pos) as Int) & 0xFF;
}

// Index of the next LF at or after `pos`, or the text length when there is
// none (a final line without a terminator).
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

// True when the line [start, end) is exactly `lit` byte-for-byte.
fn _line_is(text: Str, start: Int, end: Int, lit: Str) -> Bool {
  if end - start != lit.len() {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    if _tb(text, start + i) != _tb(lit, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the first five bytes of [start, end) are hyphen-minuses (i.e.
// the line could be a block marker of some kind).
fn _line_dashed(text: Str, start: Int, end: Int) -> Bool {
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

// Base64 digit value (0..63) of one encoded byte; -1 when the byte is not an
// alphabet character. The pad byte '=' (61) is handled by the caller.
fn _b64_value(b: Int) -> Int {
  if b >= 65 && b <= 90 {
    return b - 65;
  }
  if b >= 97 && b <= 122 {
    return b - 97 + 26;
  }
  if b >= 48 && b <= 57 {
    return b - 48 + 52;
  }
  if b == 43 {
    return 62;
  }
  if b == 47 {
    return 63;
  }
  return -1;
}

// The recorded source offset of body character `k` (callers guarantee the
// bounds).
fn _off_at(offsets: &Vec[Int], k: Int) -> Int {
  let o: Int = offsets[k];
  return o;
}

// Strict base64 decode of `chars` (the body characters) with `offsets`
// giving each character's armor-text offset for error reporting. The count
// must be a multiple of 4; '=' may appear only in the final run with the
// exact count implied by the final group; the unused low bits of a padded
// final group must be zero.
fn _b64_decode(chars: &Vec[UInt8], offsets: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let n = chars.len();
  if n == 0 {
    return _ok_bytes(out);
  }
  if n % 4 != 0 {
    return _err_bytes(_at("pki pem: bad padding", _off_at(offsets, 0)));
  }
  var first_pad = -1;
  var k = 0;
  while k < n {
    let b: Int = (chars[k] as Int) & 0xFF;
    if b == 61 {
      first_pad = k;
      break;
    }
    if _b64_value(b) < 0 {
      return _err_bytes(_at("pki pem: invalid base64 character", _off_at(offsets, k)));
    }
    k = k + 1;
  }
  var d = n;
  if first_pad >= 0 {
    d = first_pad;
    var j = first_pad;
    while j < n {
      let b: Int = (chars[j] as Int) & 0xFF;
      if b != 61 {
        return _err_bytes(_at("pki pem: bad padding", _off_at(offsets, j)));
      }
      j = j + 1;
    }
    let pad = n - d;
    if pad > 2 {
      return _err_bytes(_at("pki pem: bad padding", _off_at(offsets, first_pad)));
    }
    if pad == 1 && d % 4 != 3 {
      return _err_bytes(_at("pki pem: bad padding", _off_at(offsets, first_pad)));
    }
    if pad == 2 && d % 4 != 2 {
      return _err_bytes(_at("pki pem: bad padding", _off_at(offsets, first_pad)));
    }
  }
  var acc = 0;
  var count = 0;
  k = 0;
  while k < d {
    let b: Int = (chars[k] as Int) & 0xFF;
    acc = acc * 64 + _b64_value(b);
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
      return _err_bytes(_at("pki pem: non-canonical trailing bits", _off_at(offsets, d - 1)));
    }
    out.push((acc / 16) as UInt8);
  } elif count == 3 {
    if acc % 4 != 0 {
      return _err_bytes(_at("pki pem: non-canonical trailing bits", _off_at(offsets, d - 1)));
    }
    out.push((acc / 1024) as UInt8);
    out.push(((acc / 4) % 256) as UInt8);
  } elif count != 0 {
    return _err_bytes(_at("pki pem: bad padding", _off_at(offsets, 0)));
  }
  return _ok_bytes(out);
}

/// Unwrap one PEM `-----BEGIN CERTIFICATE-----` ... `-----END CERTIFICATE-----`
/// armor block into DER bytes. LF and CRLF line endings are accepted; empty
/// lines outside the block are ignored; every body line except the last must
/// be exactly 64 characters and the last 1..64; the base64 body must be
/// strict RFC 4648 (canonical padding, zero unused trailing bits).
///
/// Errors (with offsets into `text`, or into the body for base64 content):
///   * `pki pem: no certificate block` -- no BEGIN line at all;
///   * `pki pem: bad armor` -- a non-empty line outside a block, a dashed
///     line that is not the exact marker, an over-long body line, a blank
///     body line or a line longer than 64 characters;
///   * `pki pem: unterminated block` -- EOF before the END line;
///   * `pki pem: text outside block` -- non-empty text after the END line;
///   * `pki pem: invalid base64 character`, `pki pem: bad padding`,
///     `pki pem: non-canonical trailing bits` -- the base64 catalog.
/// Complexity: O(text.len()).
pub fn pki_pem_to_der(text: Str) -> Result[Vec[UInt8], Str] {
  var body = Vec[UInt8].new();
  var offsets = Vec[Int].new();
  var state = 0;
  var prev_len = -1;
  let n = text.len();
  var pos = 0;
  while pos < n {
    let e = _line_end(text, pos);
    var ce = e;
    if ce > pos && _tb(text, ce - 1) == 13 {
      ce = ce - 1;
    }
    if state == 0 {
      if ce > pos {
        if _line_is(text, pos, ce, "-----BEGIN CERTIFICATE-----") {
          state = 1;
        } else {
          return _err_bytes(_at("pki pem: bad armor", pos));
        }
      }
    } elif state == 1 {
      if _line_is(text, pos, ce, "-----END CERTIFICATE-----") {
        state = 2;
      } elif ce == pos {
        return _err_bytes(_at("pki pem: bad armor", pos));
      } elif _line_dashed(text, pos, ce) {
        return _err_bytes(_at("pki pem: bad armor", pos));
      } else {
        let llen = ce - pos;
        if prev_len >= 0 && prev_len != 64 {
          return _err_bytes(_at("pki pem: bad armor", pos));
        }
        if llen > 64 {
          return _err_bytes(_at("pki pem: bad armor", pos));
        }
        var k = pos;
        while k < ce {
          let b = _tb(text, k);
          if b != 61 && _b64_value(b) < 0 {
            return _err_bytes(_at("pki pem: invalid base64 character", k));
          }
          body.push(b as UInt8);
          offsets.push(k);
          k = k + 1;
        }
        prev_len = llen;
      }
    } else {
      if ce > pos {
        return _err_bytes(_at("pki pem: text outside block", pos));
      }
    }
    pos = e + 1;
  }
  if state == 0 {
    return _err_bytes("pki pem: no certificate block");
  }
  if state == 1 {
    return _err_bytes(_at("pki pem: unterminated block", n));
  }
  if body.len() == 0 {
    return _err_bytes("pki pem: empty body");
  }
  return _b64_decode(&body, &offsets);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Interface revision of this parser (1).
/// Complexity: O(1).
pub fn pki_version() -> Int {
  return 1;
}

/// Decoded certificate version: 0 = v1, 1 = v2, 2 = v3.
/// Complexity: O(1).
pub fn pki_certificate_version(c: &PkiCertificate) -> Int {
  return c.version;
}

/// Uppercase hex of the serialNumber content bytes (the DER 0x00 sign pad is
/// included when it was present). Compare with str_compare.
/// Complexity: O(serial bytes).
pub fn pki_serial_hex(c: &PkiCertificate) -> Str {
  let s: Str = c.serial_hex;
  return s;
}

/// serialNumber content length in bytes.
/// Complexity: O(1).
pub fn pki_serial_len(c: &PkiCertificate) -> Int {
  return c.serial_len;
}

/// Copy of the serialNumber content bytes.
/// Complexity: O(serial bytes).
pub fn pki_serial_bytes(c: &PkiCertificate) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  let src: Vec[UInt8] = c.serial_bytes;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

/// The TBS signature AlgorithmIdentifier OID (dotted). Compare with
/// str_compare. Complexity: O(1).
pub fn pki_tbs_signature_oid(c: &PkiCertificate) -> Str {
  let s: Str = c.tbs_sig_oid;
  return s;
}

/// The outer signatureAlgorithm OID (dotted). Compare with str_compare.
/// Complexity: O(1).
pub fn pki_outer_signature_oid(c: &PkiCertificate) -> Str {
  let s: Str = c.outer_sig_oid;
  return s;
}

/// The subjectPublicKeyInfo algorithm OID (dotted). Compare with
/// str_compare. Complexity: O(1).
pub fn pki_spki_algorithm_oid(c: &PkiCertificate) -> Str {
  let s: Str = c.spki_alg_oid;
  return s;
}

/// The subjectPublicKey BIT STRING bit length (unused bits excluded).
/// Complexity: O(1).
pub fn pki_spki_key_bits(c: &PkiCertificate) -> Int {
  return c.spki_key_bits;
}

/// The signatureValue BIT STRING bit length (unused bits excluded).
/// Complexity: O(1).
pub fn pki_signature_bits(c: &PkiCertificate) -> Int {
  return c.sig_len * 8 - c.sig_unused;
}

/// Number of RDNs (SETs) in a decoded Name.
/// Complexity: O(1).
pub fn pki_name_rdn_count(n: &PkiName) -> Int {
  return n.rdn_count;
}

/// Number of AttributeTypeAndValue entries in a decoded Name.
/// Complexity: O(1).
pub fn pki_name_attribute_count(n: &PkiName) -> Int {
  return n.oids.len();
}

/// RDN ordinal of attribute `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn pki_name_rdn_index(n: &PkiName, i: Int) -> Int {
  if i < 0 || i >= n.rdn_index.len() {
    return -1;
  }
  let v: Int = n.rdn_index[i];
  return v;
}

/// Type OID of attribute `i` (dotted), or "" when `i` is out of range.
/// Compare with str_compare. Complexity: O(1).
pub fn pki_name_oid(n: &PkiName, i: Int) -> Str {
  if i < 0 || i >= n.oids.len() {
    return "";
  }
  let v: Str = n.oids[i];
  return v;
}

/// Universal tag number of the value of attribute `i`, or -1 when the type
/// is not decoded or `i` is out of range.
/// Complexity: O(1).
pub fn pki_name_value_tag(n: &PkiName, i: Int) -> Int {
  if i < 0 || i >= n.value_tags.len() {
    return -1;
  }
  let v: Int = n.value_tags[i];
  return v;
}

/// Decoded value of attribute `i`, or "" when the type is not decoded or `i`
/// is out of range. Compare with str_compare. Complexity: O(1).
pub fn pki_name_value(n: &PkiName, i: Int) -> Str {
  if i < 0 || i >= n.values.len() {
    return "";
  }
  let v: Str = n.values[i];
  return v;
}

/// Year field of a decoded time. Complexity: O(1).
pub fn pki_time_year(t: &DerTime) -> Int {
  return t.year;
}

/// Month field of a decoded time (1..12). Complexity: O(1).
pub fn pki_time_month(t: &DerTime) -> Int {
  return t.month;
}

/// Day field of a decoded time (1..31). Complexity: O(1).
pub fn pki_time_day(t: &DerTime) -> Int {
  return t.day;
}

/// Hour field of a decoded time (0..23). Complexity: O(1).
pub fn pki_time_hour(t: &DerTime) -> Int {
  return t.hour;
}

/// Minute field of a decoded time (0..59). Complexity: O(1).
pub fn pki_time_minute(t: &DerTime) -> Int {
  return t.minute;
}

/// Second field of a decoded time (0..59). Complexity: O(1).
pub fn pki_time_second(t: &DerTime) -> Int {
  return t.second;
}

/// True when the decoded time was a UTCTime (false for GeneralizedTime).
/// Complexity: O(1).
pub fn pki_time_is_utc(t: &DerTime) -> Bool {
  return t.utc;
}

/// Number of extensions in wire order (known and unknown).
/// Complexity: O(1).
pub fn pki_extension_count(e: &PkiExtensions) -> Int {
  return e.oids.len();
}

/// Extension OID `i` (dotted), or "" when `i` is out of range. Compare with
/// str_compare. Complexity: O(1).
pub fn pki_extension_oid(e: &PkiExtensions, i: Int) -> Str {
  if i < 0 || i >= e.oids.len() {
    return "";
  }
  let v: Str = e.oids[i];
  return v;
}

/// Critical flag of extension `i` (0 or 1), or 0 when `i` is out of range.
/// Complexity: O(1).
pub fn pki_extension_critical(e: &PkiExtensions, i: Int) -> Int {
  if i < 0 || i >= e.critical.len() {
    return 0;
  }
  let v: Int = e.critical[i];
  return v;
}

/// True when a basicConstraints extension was present.
/// Complexity: O(1).
pub fn pki_basic_constraints_present(e: &PkiExtensions) -> Bool {
  return e.has_basic_constraints;
}

/// True when basicConstraints cA is set.
/// Complexity: O(1).
pub fn pki_ca(e: &PkiExtensions) -> Bool {
  return e.ca;
}

/// basicConstraints pathLenConstraint, or -1 when absent.
/// Complexity: O(1).
pub fn pki_path_len(e: &PkiExtensions) -> Int {
  return e.path_len;
}

/// True when a keyUsage extension was present.
/// Complexity: O(1).
pub fn pki_key_usage_present(e: &PkiExtensions) -> Bool {
  return e.has_key_usage;
}

/// The keyUsage bits as a left-aligned 16-bit word, independent of the wire
/// width: X.509 bit 0 (digitalSignature) is 0x8000 and bit 8 (decipherOnly)
/// is 0x0080. A keyUsage BIT STRING longer than two bit bytes is rejected at
/// parse time.
/// Complexity: O(1).
pub fn pki_key_usage_value(e: &PkiExtensions) -> Int {
  return e.key_usage;
}

/// True when keyUsage bit `bit` (0..8, X.509 numbering) is set. Bit tests use
/// divisor/modulo arithmetic, never shifts or sign-bit tricks.
/// Complexity: O(1).
pub fn pki_key_usage_has(e: &PkiExtensions, bit: Int) -> Bool {
  if bit < 0 || bit > 8 {
    return false;
  }
  let v: Int = e.key_usage;
  let place: Int = _pow2(15 - bit);
  if (v / place) % 2 == 1 {
    return true;
  }
  return false;
}

/// Number of extKeyUsage OIDs.
/// Complexity: O(1).
pub fn pki_ext_key_usage_count(e: &PkiExtensions) -> Int {
  return e.eku_oids.len();
}

/// extKeyUsage OID `i` (dotted), or "" when `i` is out of range. Compare
/// with str_compare. Complexity: O(1).
pub fn pki_ext_key_usage_oid(e: &PkiExtensions, i: Int) -> Str {
  if i < 0 || i >= e.eku_oids.len() {
    return "";
  }
  let v: Str = e.eku_oids[i];
  return v;
}

/// Number of subjectAltName entries.
/// Complexity: O(1).
pub fn pki_san_count(e: &PkiExtensions) -> Int {
  return e.san_types.len();
}

/// GeneralName type of subjectAltName entry `i` (1 email, 2 dNSName, 6 URI,
/// 7 iPAddress, else the raw context tag number), or -1 when out of range.
/// Complexity: O(1).
pub fn pki_san_type(e: &PkiExtensions, i: Int) -> Int {
  if i < 0 || i >= e.san_types.len() {
    return -1;
  }
  let v: Int = e.san_types[i];
  return v;
}

/// Decoded subjectAltName value `i` (text for email/DNS/URI, dotted quad or
/// uncompressed IPv6 text for iPAddress, "" for other types), or "" when out
/// of range. Compare with str_compare. Complexity: O(1).
pub fn pki_san_value(e: &PkiExtensions, i: Int) -> Str {
  if i < 0 || i >= e.san_values.len() {
    return "";
  }
  let v: Str = e.san_values[i];
  return v;
}

/// True when a subjectKeyIdentifier extension was present.
/// Complexity: O(1).
pub fn pki_has_subject_key_id(e: &PkiExtensions) -> Bool {
  return e.has_subject_key_id;
}

/// Uppercase hex of the subjectKeyIdentifier key, or "" when absent.
/// Complexity: O(1).
pub fn pki_subject_key_id_hex(e: &PkiExtensions) -> Str {
  let s: Str = e.subject_key_id_hex;
  return s;
}

/// True when an authorityKeyIdentifier extension was present.
/// Complexity: O(1).
pub fn pki_has_authority_key_id(e: &PkiExtensions) -> Bool {
  return e.has_authority_key_id;
}

/// Uppercase hex of the authorityKeyIdentifier keyIdentifier, or "" when
/// absent (the extension may carry only issuer/serial fields). Complexity:
/// O(1).
pub fn pki_authority_key_id_hex(e: &PkiExtensions) -> Str {
  let s: Str = e.authority_key_id_hex;
  return s;
}
