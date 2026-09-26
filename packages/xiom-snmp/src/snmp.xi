// XIOM -- xiom.snmp: ASN.1 BER and SNMPv1/v2c message codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets) decoder and encoder for the wire subset of
// SNMP used by RFC 1157 (SNMPv1) and RFC 3416 (SNMPv2c):
//
//   * BER: one-byte tags, definite short/long-form lengths, signed minimal
//     INTEGER, OCTET STRING, NULL, OBJECT IDENTIFIER and SEQUENCE, plus the
//     SMI application types IpAddress (0x40), Counter32 (0x41), Gauge32
//     (0x42), TimeTicks (0x43), Opaque (0x44) and Counter64 (0x46);
//   * messages: SEQUENCE { INTEGER version, OCTET STRING community, PDU }
//     with version 0 (v1) or 1 (v2c) and PDU tags 0xA0..0xA7, including the
//     Trap v1 field order and the GetBulk non-repeaters / max-repetitions
//     fields, plus error-status and error-index on the request/response
//     forms;
//   * encoding: minimal INTEGER, OBJECT IDENTIFIER and application-type
//     values plus minimal GetRequest and Response messages (one varbind)
//     that parse back byte-identically.
//
// Every malformed input is rejected with a stable Err(Str) that names the
// byte offset of the offending structure. See SPEC.md for the exact error
// catalog and the documented subset.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods and no lambdas;
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles);
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before it enters Int arithmetic, and PDU
//     tags (0xA0..0xA7) are only ever compared as widened Ints;
//   * Vec[Int] element reads are bound to typed locals; no Str value is
//     read out of a Vec or compared in this module (community strings stay
//     Vec[UInt8] because they may hold arbitrary bytes, including NUL);
//   * the message index is flat (parallel Vec[Int] fields) because
//     Vec[StructType] is unsupported, and there is no table-driven
//     dispatch (indexed Vec[fn] calls miscompile).

module xiom.snmp

use xiom.string.builder;

// --------------------------------------------------
//  Protocol constants
// --------------------------------------------------

/// SNMP version field value for SNMPv1 (RFC 1157).
pub const SNMP_VERSION_V1: Int = 0;

/// SNMP version field value for SNMPv2c (RFC 3416).
pub const SNMP_VERSION_V2C: Int = 1;

/// PDU kind of GetRequest (tag 0xA0).
pub const SNMP_PDU_GET_REQUEST: Int = 0;

/// PDU kind of GetNextRequest (tag 0xA1).
pub const SNMP_PDU_GET_NEXT_REQUEST: Int = 1;

/// PDU kind of Response (tag 0xA2).
pub const SNMP_PDU_RESPONSE: Int = 2;

/// PDU kind of SetRequest (tag 0xA3).
pub const SNMP_PDU_SET_REQUEST: Int = 3;

/// PDU kind of the SNMPv1 Trap (tag 0xA4).
pub const SNMP_PDU_TRAP_V1: Int = 4;

/// PDU kind of GetBulkRequest (tag 0xA5, SNMPv2c only).
pub const SNMP_PDU_GET_BULK_REQUEST: Int = 5;

/// PDU kind of InformRequest (tag 0xA6, SNMPv2c only).
pub const SNMP_PDU_INFORM_REQUEST: Int = 6;

/// PDU kind of SNMPv2-Trap (tag 0xA7, SNMPv2c only).
pub const SNMP_PDU_V2_TRAP: Int = 7;

/// BER tag of INTEGER (0x02).
pub const SNMP_TAG_INTEGER: Int = 2;

/// BER tag of OCTET STRING (0x04).
pub const SNMP_TAG_OCTET_STRING: Int = 4;

/// BER tag of NULL (0x05).
pub const SNMP_TAG_NULL: Int = 5;

/// BER tag of OBJECT IDENTIFIER (0x06).
pub const SNMP_TAG_OID: Int = 6;

/// BER tag of SEQUENCE (constructed form, 0x30).
pub const SNMP_TAG_SEQUENCE: Int = 48;

/// SMI application tag of IpAddress (0x40).
pub const SNMP_TAG_IPADDRESS: Int = 64;

/// SMI application tag of Counter32 (0x41).
pub const SNMP_TAG_COUNTER32: Int = 65;

/// SMI application tag of Gauge32 / Unsigned32 (0x42).
pub const SNMP_TAG_GAUGE32: Int = 66;

/// SMI application tag of TimeTicks (0x43).
pub const SNMP_TAG_TIMETICKS: Int = 67;

/// SMI application tag of Opaque (0x44).
pub const SNMP_TAG_OPAQUE: Int = 68;

/// SMI application tag of Counter64 (0x46).
pub const SNMP_TAG_COUNTER64: Int = 70;

/// Largest value representable by the 32-bit SMI application types.
pub const SNMP_MAX_U32: Int = 4294967295;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A decoded BER length field. `len` is the content length (>= 0) and
/// `size` is the number of length-field bytes (1 for the short form,
/// 1 + n for the long form).
pub type BerLength = {
  len: Int;
  size: Int;
}

/// A decoded BER tag-length-value header. `tag` is the full first tag byte
/// (multi-byte tags are rejected), `len` the content length, `size` the
/// tag byte plus the length field, `content` the absolute offset of the
/// first content byte and `next` the offset just past the content
/// (`content + len`).
pub type BerTlv = {
  tag: Int;
  len: Int;
  size: Int;
  content: Int;
  next: Int;
}

/// A decoded INTEGER (or 32-bit application type) value plus `next`, the
/// offset just past the TLV.
pub type BerInt = {
  value: Int;
  next: Int;
}

/// A decoded OCTET STRING (or IpAddress / Opaque) value plus `next`, the
/// offset just past the TLV.
pub type BerBytes = {
  bytes: Vec[UInt8];
  next: Int;
}

/// A decoded OBJECT IDENTIFIER: the full arc list (the first two arcs are
/// the decoded halves of the first subidentifier) plus `next`.
pub type BerOid = {
  arcs: Vec[Int];
  next: Int;
}

/// A decoded SNMP varbind value. `tag` is the BER tag that determines the
/// active field: INTEGER (2) and the application integer types Counter32
/// (65), Gauge32 (66), TimeTicks (67) and Counter64 (70) use `int_val`;
/// OCTET STRING (4), IpAddress (64) and Opaque (68) use `bytes`; OID (6)
/// uses `oid`; NULL (5) uses no field. `next` is the offset just past the
/// value TLV; `snmp_value_encode` ignores `next`.
pub type SnmpValue = {
  tag: Int;
  int_val: Int;
  bytes: Vec[UInt8];
  oid: Vec[Int];
  next: Int;
}

/// A decoded varbind: `name` is the object identifier, `value` the typed
/// value and `next` the offset just past the varbind SEQUENCE.
pub type SnmpVarBind = {
  name: Vec[Int];
  value: SnmpValue;
  next: Int;
}

/// A parsed SNMP message index.
///
/// `version` is 0 or 1; `community` holds the raw community bytes (never a
/// Str: it may carry any byte value including 0x00). `pdu_tag` is
/// 0xA0..0xA7 and `pdu_kind` its low three bits (0..7). `request_id` is -1
/// on Trap v1 (which has none); `error_status`/`error_index` are -1 on Trap
/// v1 and GetBulkRequest (which have none); `non_repeaters` and
/// `max_repetitions` are -1 on every other kind. The trap-only fields
/// (`enterprise`, `agent_addr` 4 bytes, `generic_trap`, `specific_trap`,
/// `timestamp`) keep their zero values on non-trap kinds. `varbind_offsets`
/// holds the absolute offset of each varbind SEQUENCE in wire order; read a
/// varbind with `snmp_varbind_parse` at that offset. `pdu_offset` is the PDU
/// tag byte offset and `next` the offset just past the whole message TLV.
/// Bytes after `next` are ignored by the parser.
pub type SnmpMessage = {
  version: Int;
  community: Vec[UInt8];
  community_offset: Int;
  community_length: Int;
  pdu_tag: Int;
  pdu_kind: Int;
  request_id: Int;
  error_status: Int;
  error_index: Int;
  non_repeaters: Int;
  max_repetitions: Int;
  enterprise: Vec[Int];
  agent_addr: Vec[UInt8];
  generic_trap: Int;
  specific_trap: Int;
  timestamp: Int;
  varbind_offsets: Vec[Int];
  pdu_offset: Int;
  next: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[BerLength, Str].
fn _ok_blen(v: BerLength) -> Result[BerLength, Str] {
  return Ok(v);
}

// Err(m) for Result[BerLength, Str].
fn _err_blen(m: Str) -> Result[BerLength, Str] {
  return Err(m);
}

// Ok(v) for Result[BerTlv, Str].
fn _ok_tlv(v: BerTlv) -> Result[BerTlv, Str] {
  return Ok(v);
}

// Err(m) for Result[BerTlv, Str].
fn _err_tlv(m: Str) -> Result[BerTlv, Str] {
  return Err(m);
}

// Ok(v) for Result[BerInt, Str].
fn _ok_bint(v: BerInt) -> Result[BerInt, Str] {
  return Ok(v);
}

// Err(m) for Result[BerInt, Str].
fn _err_bint(m: Str) -> Result[BerInt, Str] {
  return Err(m);
}

// Ok(v) for Result[BerBytes, Str].
fn _ok_bbytes(v: BerBytes) -> Result[BerBytes, Str] {
  return Ok(v);
}

// Err(m) for Result[BerBytes, Str].
fn _err_bbytes(m: Str) -> Result[BerBytes, Str] {
  return Err(m);
}

// Ok(v) for Result[BerOid, Str].
fn _ok_oid(v: BerOid) -> Result[BerOid, Str] {
  return Ok(v);
}

// Err(m) for Result[BerOid, Str].
fn _err_oid(m: Str) -> Result[BerOid, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_arcs(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_arcs(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[SnmpValue, Str].
fn _ok_value(v: SnmpValue) -> Result[SnmpValue, Str] {
  return Ok(v);
}

// Err(m) for Result[SnmpValue, Str].
fn _err_value(m: Str) -> Result[SnmpValue, Str] {
  return Err(m);
}

// Ok(v) for Result[SnmpVarBind, Str].
fn _ok_vb(v: SnmpVarBind) -> Result[SnmpVarBind, Str] {
  return Ok(v);
}

// Err(m) for Result[SnmpVarBind, Str].
fn _err_vb(m: Str) -> Result[SnmpVarBind, Str] {
  return Err(m);
}

// Ok(v) for Result[SnmpMessage, Str].
fn _ok_msg(v: SnmpMessage) -> Result[SnmpMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[SnmpMessage, Str].
fn _err_msg(m: Str) -> Result[SnmpMessage, Str] {
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

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
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

// Append every byte of `v` to `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append the definite-form BER length of `len` (four bytes or fewer; any
// non-negative Int is accepted). A negative length writes nothing.
fn _push_length(out: &mut Vec[UInt8], len: Int) {
  if len < 0 {
    return;
  }
  if len < 128 {
    out.push(len as UInt8);
    return;
  }
  var low = Vec[UInt8].new();
  var q = len;
  while q > 0 {
    low.push((q % 256) as UInt8);
    q = q / 256;
  }
  out.push((128 + low.len()) as UInt8);
  var i = low.len() - 1;
  while i >= 0 {
    out.push(low[i]);
    i = i - 1;
  }
}

// Render "`msg` at offset `off`" for the error catalog.
fn _at(msg: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, msg);
  builder.sb_push_str(&mut sb, " at offset ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

// Absolute offset of the TLV's first byte: `content` minus the tag and
// length bytes.
fn _tlv_start(t: &BerTlv) -> Int {
  return t.content - t.size;
}

// --------------------------------------------------
//  BER decoding
// --------------------------------------------------

/// Decode the BER length field at `off` (the long form is accepted with any
/// number of length bytes from 1 to 8; the value is not required to use the
/// minimal number of bytes, but the long form may not encode a length that
/// does not fit 63 bits).
///
/// Errors, each naming `off` (the first length byte):
///   * `ber: negative offset` -- off < 0;
///   * `ber: truncated length` -- no length byte, or the declared number of
///     long-form bytes is missing;
///   * `ber: indefinite length` -- the 0x80 byte;
///   * `ber: length overflow` -- more than 8 length bytes, or a long-form
///     value that does not fit a signed 64-bit Int.
/// Complexity: O(length bytes).
pub fn ber_length_decode(data: &Vec[UInt8], off: Int) -> Result[BerLength, Str] {
  if off < 0 {
    return _err_blen("ber: negative offset");
  }
  if off >= data.len() {
    return _err_blen(_at("ber: truncated length", off));
  }
  let b: Int = _byte(data, off);
  if b < 128 {
    return _ok_blen(BerLength{ len: b; size: 1; });
  }
  let n: Int = b - 128;
  if n == 0 {
    return _err_blen(_at("ber: indefinite length", off));
  }
  if n > 8 {
    return _err_blen(_at("ber: length overflow", off));
  }
  if off + 1 + n > data.len() {
    return _err_blen(_at("ber: truncated length", off));
  }
  var v = 0;
  var i = 0;
  while i < n {
    let x: Int = _byte(data, off + 1 + i);
    v = v * 256 + x;
    i = i + 1;
  }
  if v < 0 {
    return _err_blen(_at("ber: length overflow", off));
  }
  return _ok_blen(BerLength{ len: v; size: 1 + n; });
}

/// Decode one BER tag-length-value at `off` and check that the declared
/// content fits the buffer. Only one-byte tags are accepted (the low five
/// bits of the tag byte may not be 11111).
///
/// Errors, each naming `off` (the tag byte):
///   * `ber: negative offset`, `ber: truncated tag` -- no tag byte;
///   * `ber: multi-byte tag` -- a tag whose low five bits are 31;
///   * the `ber_length_decode` catalog (`ber: truncated length`,
///     `ber: indefinite length`, `ber: length overflow`);
///   * `ber: value overruns buffer` -- `content + len > data.len()`.
/// The caller is responsible for checking the TLV against its container
/// (the message parser rejects `ber: value overruns container`).
/// Complexity: O(1) after the length field.
pub fn ber_tlv_decode(data: &Vec[UInt8], off: Int) -> Result[BerTlv, Str] {
  if off < 0 {
    return _err_tlv("ber: negative offset");
  }
  if off >= data.len() {
    return _err_tlv(_at("ber: truncated tag", off));
  }
  let tag: Int = _byte(data, off);
  if tag % 32 == 31 {
    return _err_tlv(_at("ber: multi-byte tag", off));
  }
  let lr = ber_length_decode(data, off + 1);
  if !lr.is_ok {
    return _err_tlv(lr.error);
  }
  let l: BerLength = lr.value;
  let content = off + 1 + l.size;
  let len: Int = l.len;
  if len > data.len() - content {
    return _err_tlv(_at("ber: value overruns buffer", off));
  }
  return _ok_tlv(BerTlv{ tag: tag; len: len; size: 1 + l.size; content: content; next: content + len; });
}

// Decode a TLV at `off` that must not extend past `end` (the end of the
// enclosing container); reports `ber: value overruns container` at `off`.
fn _tlv_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerTlv, Str] {
  let r = ber_tlv_decode(data, off);
  if !r.is_ok {
    return _err_tlv(r.error);
  }
  let t: BerTlv = r.value;
  if t.next > end {
    return _err_tlv(_at("ber: value overruns container", off));
  }
  return _ok_tlv(t);
}

// Signed value of an INTEGER TLV: content must be 1..8 bytes, minimally
// encoded, then sign-extended. Reports at the TLV's first byte.
fn _int_value(data: &Vec[UInt8], t: &BerTlv) -> Result[Int, Str] {
  let n: Int = t.len;
  let start: Int = t.content;
  let base: Int = _tlv_start(t);
  if n < 1 {
    return _err_int(_at("ber: empty integer", base));
  }
  if n > 8 {
    return _err_int(_at("ber: integer overflow", base));
  }
  let b0: Int = _byte(data, start);
  if n > 1 {
    let b1: Int = _byte(data, start + 1);
    if b0 == 0 && b1 < 128 {
      return _err_int(_at("ber: non-minimal integer", base));
    }
    if b0 == 255 && b1 >= 128 {
      return _err_int(_at("ber: non-minimal integer", base));
    }
  }
  var v = 0;
  if b0 >= 128 {
    v = b0 - 256;
  } else {
    v = b0;
  }
  var i = 1;
  while i < n {
    let x: Int = _byte(data, start + i);
    v = v * 256 + x;
    i = i + 1;
  }
  return _ok_int(v);
}

// Unsigned value of an application integer TLV with at most `max_sig`
// significant bytes: content must be non-empty, leading zero bytes are
// skipped (a redundant leading zero is tolerated, as SMI allows) and the
// value must fit a signed 64-bit Int. Reports at the TLV's first byte.
fn _uint_value(data: &Vec[UInt8], t: &BerTlv, max_sig: Int) -> Result[Int, Str] {
  let n: Int = t.len;
  let start: Int = t.content;
  let base: Int = _tlv_start(t);
  if n < 1 {
    return _err_int(_at("ber: empty integer", base));
  }
  var i = 0;
  while i < n {
    let b: Int = _byte(data, start + i);
    if b != 0 {
      break;
    }
    i = i + 1;
  }
  if n - i > max_sig {
    return _err_int(_at("ber: value overflow", base));
  }
  var v = 0;
  var k = i;
  while k < n {
    let x: Int = _byte(data, start + k);
    v = v * 256 + x;
    if v < 0 {
      return _err_int(_at("ber: value overflow", base));
    }
    k = k + 1;
  }
  return _ok_int(v);
}

// Arc list of an OBJECT IDENTIFIER TLV. Every subidentifier is base-128
// with a continuation bit; the first byte of a subidentifier may not be the
// continuation-only 0x80 (non-minimal encoding) and the accumulated value
// must fit a signed 64-bit Int. The first subidentifier is split into the
// first two arcs (X*40 + Y). Reports at the TLV's first byte.
fn _oid_arcs(data: &Vec[UInt8], t: &BerTlv) -> Result[Vec[Int], Str] {
  let n: Int = t.len;
  let start: Int = t.content;
  let base: Int = _tlv_start(t);
  if n < 1 {
    return _err_arcs(_at("ber: empty oid", base));
  }
  var arcs = Vec[Int].new();
  var pos = start;
  let end: Int = start + n;
  var first = true;
  while pos < end {
    let lead: Int = _byte(data, pos);
    if lead == 128 {
      return _err_arcs(_at("ber: non-minimal oid subidentifier", base));
    }
    var v = 0;
    var done = false;
    while pos < end {
      let b: Int = _byte(data, pos);
      pos = pos + 1;
      if v > 72057594037927935 {
        return _err_arcs(_at("ber: oid subidentifier overflow", base));
      }
      v = v * 128 + (b % 128);
      if b < 128 {
        done = true;
        break;
      }
    }
    if !done {
      return _err_arcs(_at("ber: truncated oid subidentifier", base));
    }
    if first {
      if v < 40 {
        arcs.push(0);
        arcs.push(v);
      } elif v < 80 {
        arcs.push(1);
        arcs.push(v - 40);
      } else {
        arcs.push(2);
        arcs.push(v - 80);
      }
      first = false;
    } else {
      arcs.push(v);
    }
  }
  return _ok_arcs(arcs);
}

/// Decode a signed INTEGER at `off` (tag 0x02). Content must be minimally
/// encoded and 1..8 bytes long. Errors: the `ber_tlv_decode` catalog,
/// `ber: tag mismatch` for a non-INTEGER tag, `ber: empty integer`,
/// `ber: integer overflow` (more than 8 content bytes) and
/// `ber: non-minimal integer`; the latter three report the TLV's first
/// byte.
/// Complexity: O(content bytes).
pub fn ber_int_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bint(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != SNMP_TAG_INTEGER {
    return _err_bint(_at("ber: tag mismatch", off));
  }
  let vr = _int_value(data, &t);
  if !vr.is_ok {
    return _err_bint(vr.error);
  }
  let v: Int = vr.value;
  return _ok_bint(BerInt{ value: v; next: t.next; });
}

// Decode an application integer TLV with tag `tag` and at most `max_sig`
// significant bytes (shared by the Counter32/Gauge32/TimeTicks/Counter64
// wrappers). Reports `ber: tag mismatch` at `off`.
fn _uint_decoder(data: &Vec[UInt8], off: Int, tag: Int, max_sig: Int) -> Result[BerInt, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bint(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != tag {
    return _err_bint(_at("ber: tag mismatch", off));
  }
  let vr = _uint_value(data, &t, max_sig);
  if !vr.is_ok {
    return _err_bint(vr.error);
  }
  let v: Int = vr.value;
  return _ok_bint(BerInt{ value: v; next: t.next; });
}

/// Decode an OCTET STRING at `off` (tag 0x04). The content bytes are copied
/// verbatim (no text validation); a zero-length string is valid.
/// Errors: the `ber_tlv_decode` catalog and `ber: tag mismatch` at `off`.
/// Complexity: O(content bytes).
pub fn ber_octet_string_decode(data: &Vec[UInt8], off: Int) -> Result[BerBytes, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bbytes(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != SNMP_TAG_OCTET_STRING {
    return _err_bbytes(_at("ber: tag mismatch", off));
  }
  let b: Vec[UInt8] = _copy_bytes(data, t.content, t.len);
  return _ok_bbytes(BerBytes{ bytes: b; next: t.next; });
}

/// Decode a NULL at `off` (tag 0x05) and return the offset just past it.
/// Errors: the `ber_tlv_decode` catalog, `ber: tag mismatch` at `off` and
/// `ber: bad null` at `off` when the content is non-empty.
/// Complexity: O(1).
pub fn ber_null_decode(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_int(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != SNMP_TAG_NULL {
    return _err_int(_at("ber: tag mismatch", off));
  }
  if t.len != 0 {
    return _err_int(_at("ber: bad null", off));
  }
  return _ok_int(t.next);
}

/// Decode an OBJECT IDENTIFIER at `off` (tag 0x06); see `_oid_arcs` for the
/// boundary rules (first two arcs combined, base-128 subidentifiers,
/// non-minimal encodings rejected).
/// Errors: the `ber_tlv_decode` catalog, `ber: tag mismatch` at `off`, and
/// at the TLV's first byte `ber: empty oid`, `ber: non-minimal oid
/// subidentifier`, `ber: truncated oid subidentifier` and
/// `ber: oid subidentifier overflow`.
/// Complexity: O(content bytes).
pub fn ber_oid_decode(data: &Vec[UInt8], off: Int) -> Result[BerOid, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_oid(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != SNMP_TAG_OID {
    return _err_oid(_at("ber: tag mismatch", off));
  }
  let ar = _oid_arcs(data, &t);
  if !ar.is_ok {
    return _err_oid(ar.error);
  }
  let arcs: Vec[Int] = ar.value;
  return _ok_oid(BerOid{ arcs: arcs; next: t.next; });
}

/// Decode an IpAddress at `off` (tag 0x40); the content must be exactly
/// 4 bytes and is copied verbatim.
/// Errors: the `ber_tlv_decode` catalog, `ber: tag mismatch` at `off` and
/// `ber: bad ipaddress` at `off` for any other content length.
/// Complexity: O(1).
pub fn ber_ipaddress_decode(data: &Vec[UInt8], off: Int) -> Result[BerBytes, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bbytes(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != SNMP_TAG_IPADDRESS {
    return _err_bbytes(_at("ber: tag mismatch", off));
  }
  if t.len != 4 {
    return _err_bbytes(_at("ber: bad ipaddress", off));
  }
  let b: Vec[UInt8] = _copy_bytes(data, t.content, t.len);
  return _ok_bbytes(BerBytes{ bytes: b; next: t.next; });
}

/// Decode an Opaque at `off` (tag 0x44) as raw bytes (any length, including
/// zero). Errors: the `ber_tlv_decode` catalog and `ber: tag mismatch` at
/// `off`. Complexity: O(content bytes).
pub fn ber_opaque_decode(data: &Vec[UInt8], off: Int) -> Result[BerBytes, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bbytes(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != SNMP_TAG_OPAQUE {
    return _err_bbytes(_at("ber: tag mismatch", off));
  }
  let b: Vec[UInt8] = _copy_bytes(data, t.content, t.len);
  return _ok_bbytes(BerBytes{ bytes: b; next: t.next; });
}

/// Decode a Counter32 at `off` (tag 0x41) as an unsigned 0..4294967295
/// value; see `_uint_value` for the leading-zero and overflow rules.
/// Errors: the `ber_tlv_decode` catalog, `ber: tag mismatch` at `off`, and
/// at the TLV's first byte `ber: empty integer` / `ber: value overflow`.
/// Complexity: O(content bytes).
pub fn ber_counter32_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str] {
  return _uint_decoder(data, off, SNMP_TAG_COUNTER32, 4);
}

/// Decode a Gauge32 at `off` (tag 0x42) as an unsigned 0..4294967295
/// value; errors as `ber_counter32_decode`.
/// Complexity: O(content bytes).
pub fn ber_gauge32_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str] {
  return _uint_decoder(data, off, SNMP_TAG_GAUGE32, 4);
}

/// Decode a TimeTicks at `off` (tag 0x43) as an unsigned 0..4294967295
/// value; errors as `ber_counter32_decode`.
/// Complexity: O(content bytes).
pub fn ber_timeticks_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str] {
  return _uint_decoder(data, off, SNMP_TAG_TIMETICKS, 4);
}

/// Decode a Counter64 at `off` (tag 0x46). The wire value is unsigned
/// 0..2^64-1 but this package stores it in a signed 64-bit Int, so values
/// above 9223372036854775807 are rejected as `ber: value overflow`; a
/// redundant leading zero byte is tolerated. Other errors as
/// `ber_counter32_decode`.
/// Complexity: O(content bytes).
pub fn ber_counter64_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str] {
  return _uint_decoder(data, off, SNMP_TAG_COUNTER64, 8);
}

// Decode an INTEGER at `off` that must end at or before `end`; a field that
// crosses its container is `ber: value overruns container` at `off`.
fn _int_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerInt, Str] {
  let r = ber_int_decode(data, off);
  if !r.is_ok {
    return _err_bint(r.error);
  }
  let b: BerInt = r.value;
  if b.next > end {
    return _err_bint(_at("ber: value overruns container", off));
  }
  return _ok_bint(b);
}

// Decode an OBJECT IDENTIFIER at `off` bounded by `end`.
fn _oid_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerOid, Str] {
  let r = ber_oid_decode(data, off);
  if !r.is_ok {
    return _err_oid(r.error);
  }
  let o: BerOid = r.value;
  if o.next > end {
    return _err_oid(_at("ber: value overruns container", off));
  }
  return _ok_oid(o);
}

// Decode an IpAddress at `off` bounded by `end`.
fn _ip_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerBytes, Str] {
  let r = ber_ipaddress_decode(data, off);
  if !r.is_ok {
    return _err_bbytes(r.error);
  }
  let b: BerBytes = r.value;
  if b.next > end {
    return _err_bbytes(_at("ber: value overruns container", off));
  }
  return _ok_bbytes(b);
}

// Decode a TimeTicks at `off` bounded by `end`.
fn _ticks_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerInt, Str] {
  let r = ber_timeticks_decode(data, off);
  if !r.is_ok {
    return _err_bint(r.error);
  }
  let b: BerInt = r.value;
  if b.next > end {
    return _err_bint(_at("ber: value overruns container", off));
  }
  return _ok_bint(b);
}

// --------------------------------------------------
//  BER encoding
// --------------------------------------------------

/// Encode `len` as a definite-form BER length: one byte below 128, else
/// 0x80|n followed by the minimal big-endian value. A negative `len`
/// yields an empty vector.
/// Complexity: O(length bytes).
pub fn ber_length_encode(len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_length(&mut out, len);
  return out;
}

// Minimal big-endian two's complement content bytes of a signed Int.
fn _int_content(value: Int) -> Vec[UInt8] {
  var low = Vec[UInt8].new();
  if value >= 0 {
    var x = value;
    while x > 0 {
      low.push((x % 256) as UInt8);
      x = x / 256;
    }
    if low.len() == 0 {
      low.push(0);
    }
    let top: Int = (low[low.len() - 1] as Int) & 0xFF;
    if top >= 128 {
      low.push(0);
    }
  } else {
    var v = value;
    while true {
      var r = v % 256;
      if r < 0 {
        r = r + 256;
      }
      low.push(r as UInt8);
      let q = (v - r) / 256;
      if q == -1 && r >= 128 {
        break;
      }
      v = q;
    }
  }
  var out = Vec[UInt8].new();
  var i = low.len() - 1;
  while i >= 0 {
    out.push(low[i]);
    i = i - 1;
  }
  return out;
}

// Minimal big-endian content bytes of an unsigned value (0 gives 0x00).
fn _uint_content(value: Int) -> Vec[UInt8] {
  var low = Vec[UInt8].new();
  var x = value;
  while x > 0 {
    low.push((x % 256) as UInt8);
    x = x / 256;
  }
  if low.len() == 0 {
    low.push(0);
  }
  var out = Vec[UInt8].new();
  var i = low.len() - 1;
  while i >= 0 {
    out.push(low[i]);
    i = i - 1;
  }
  return out;
}

/// Encode `value` as a minimally encoded signed INTEGER TLV (tag 0x02).
/// Complexity: O(content bytes).
pub fn ber_int_encode(value: Int) -> Vec[UInt8] {
  var body = _int_content(value);
  var out = Vec[UInt8].new();
  out.push(SNMP_TAG_INTEGER as UInt8);
  _push_length(&mut out, body.len());
  _push_bytes(&mut out, &body);
  return out;
}

/// Encode an unsigned SMI application value as a TLV with tag `tag`.
/// `tag` must be Counter32 (0x41), Gauge32 (0x42), TimeTicks (0x43) or
/// Counter64 (0x46). Errors (no offsets; encoder):
///   * `ber: bad unsigned tag` -- unsupported tag;
///   * `ber: negative unsigned value` -- value < 0;
///   * `ber: value too large` -- a 32-bit type above 4294967295 (Counter64
///     accepts any non-negative Int).
/// Complexity: O(content bytes).
pub fn ber_uint_encode(value: Int, tag: Int) -> Result[Vec[UInt8], Str] {
  if tag != SNMP_TAG_COUNTER32 && tag != SNMP_TAG_GAUGE32 && tag != SNMP_TAG_TIMETICKS && tag != SNMP_TAG_COUNTER64 {
    return _err_bytes("ber: bad unsigned tag");
  }
  if value < 0 {
    return _err_bytes("ber: negative unsigned value");
  }
  if tag != SNMP_TAG_COUNTER64 {
    if value > SNMP_MAX_U32 {
      return _err_bytes("ber: value too large");
    }
  }
  var body = _uint_content(value);
  var out = Vec[UInt8].new();
  out.push(tag as UInt8);
  _push_length(&mut out, body.len());
  _push_bytes(&mut out, &body);
  return _ok_bytes(out);
}

/// Encode `bytes` as an OCTET STRING TLV (tag 0x04), verbatim.
/// Complexity: O(content bytes).
pub fn ber_octet_string_encode(bytes: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(SNMP_TAG_OCTET_STRING as UInt8);
  _push_length(&mut out, bytes.len());
  _push_bytes(&mut out, bytes);
  return out;
}

// Append `v` (>= 0) to `out` as a base-128 subidentifier, high bit set on
// every byte but the last.
fn _push_base128(out: &mut Vec[UInt8], v: Int) {
  var low = Vec[Int].new();
  low.push(v % 128);
  var q = v / 128;
  while q > 0 {
    low.push(q % 128);
    q = q / 128;
  }
  var i = low.len() - 1;
  while i >= 0 {
    let c: Int = low[i];
    if i > 0 {
      out.push((c + 128) as UInt8);
    } else {
      out.push(c as UInt8);
    }
    i = i - 1;
  }
}

/// Encode an OBJECT IDENTIFIER TLV (tag 0x06) from a full arc list. The
/// first two arcs are combined as X*40 + Y; the subidentifiers are
/// base-128. Arc rules: at least two arcs; first arc 0, 1 or 2; second arc
/// 0..39 when the first arc is 0 or 1 (unbounded, but it must not overflow
/// the combination, when the first arc is 2); every arc >= 0.
///
/// Errors (no offsets; encoder): `ber: oid needs two arcs`,
/// `ber: bad first oid arc`, `ber: bad second oid arc`,
/// `ber: negative oid arc`.
/// Complexity: O(arcs).
pub fn ber_oid_encode(arcs: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let n = arcs.len();
  if n < 2 {
    return _err_bytes("ber: oid needs two arcs");
  }
  let a0: Int = arcs[0];
  let a1: Int = arcs[1];
  if a0 < 0 || a0 > 2 {
    return _err_bytes("ber: bad first oid arc");
  }
  if a0 < 2 {
    if a1 < 0 || a1 > 39 {
      return _err_bytes("ber: bad second oid arc");
    }
  } else {
    if a1 < 0 {
      return _err_bytes("ber: bad second oid arc");
    }
    if a1 > 9223372036854775727 {
      return _err_bytes("ber: bad second oid arc");
    }
  }
  var body = Vec[UInt8].new();
  _push_base128(&mut body, a0 * 40 + a1);
  var i = 2;
  while i < n {
    let a: Int = arcs[i];
    if a < 0 {
      return _err_bytes("ber: negative oid arc");
    }
    _push_base128(&mut body, a);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  out.push(SNMP_TAG_OID as UInt8);
  _push_length(&mut out, body.len());
  _push_bytes(&mut out, &body);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  SNMP values
// --------------------------------------------------

/// Decode one varbind value TLV at `off` into a `SnmpValue` (its `tag` is
/// the wire tag). Supported tags: 0x02, 0x04, 0x05, 0x06, 0x40, 0x41,
/// 0x42, 0x43, 0x44, 0x46.
/// Errors: the `ber_tlv_decode` catalog; the per-type errors of the
/// dedicated decoders above (INTEGER minimal encoding, IpAddress length,
/// application overflow, OID rules, `ber: bad null`); and
/// `ber: unsupported value tag` at `off` for any other tag (including
/// SEQUENCE and context tags).
/// Complexity: O(content bytes).
pub fn snmp_value_decode(data: &Vec[UInt8], off: Int) -> Result[SnmpValue, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_value(tr.error);
  }
  let t: BerTlv = tr.value;
  let tag: Int = t.tag;
  if tag == SNMP_TAG_INTEGER {
    let vr = _int_value(data, &t);
    if !vr.is_ok {
      return _err_value(vr.error);
    }
    let v: Int = vr.value;
    return _ok_value(SnmpValue{ tag: tag; int_val: v; bytes: Vec[UInt8].new(); oid: Vec[Int].new(); next: t.next; });
  }
  if tag == SNMP_TAG_OCTET_STRING {
    let b: Vec[UInt8] = _copy_bytes(data, t.content, t.len);
    return _ok_value(SnmpValue{ tag: tag; int_val: 0; bytes: b; oid: Vec[Int].new(); next: t.next; });
  }
  if tag == SNMP_TAG_NULL {
    if t.len != 0 {
      return _err_value(_at("ber: bad null", off));
    }
    return _ok_value(SnmpValue{ tag: tag; int_val: 0; bytes: Vec[UInt8].new(); oid: Vec[Int].new(); next: t.next; });
  }
  if tag == SNMP_TAG_OID {
    let ar = _oid_arcs(data, &t);
    if !ar.is_ok {
      return _err_value(ar.error);
    }
    let arcs: Vec[Int] = ar.value;
    return _ok_value(SnmpValue{ tag: tag; int_val: 0; bytes: Vec[UInt8].new(); oid: arcs; next: t.next; });
  }
  if tag == SNMP_TAG_IPADDRESS {
    if t.len != 4 {
      return _err_value(_at("ber: bad ipaddress", off));
    }
    let b: Vec[UInt8] = _copy_bytes(data, t.content, t.len);
    return _ok_value(SnmpValue{ tag: tag; int_val: 0; bytes: b; oid: Vec[Int].new(); next: t.next; });
  }
  if tag == SNMP_TAG_COUNTER32 || tag == SNMP_TAG_GAUGE32 || tag == SNMP_TAG_TIMETICKS {
    let vr = _uint_value(data, &t, 4);
    if !vr.is_ok {
      return _err_value(vr.error);
    }
    let v: Int = vr.value;
    return _ok_value(SnmpValue{ tag: tag; int_val: v; bytes: Vec[UInt8].new(); oid: Vec[Int].new(); next: t.next; });
  }
  if tag == SNMP_TAG_OPAQUE {
    let b: Vec[UInt8] = _copy_bytes(data, t.content, t.len);
    return _ok_value(SnmpValue{ tag: tag; int_val: 0; bytes: b; oid: Vec[Int].new(); next: t.next; });
  }
  if tag == SNMP_TAG_COUNTER64 {
    let vr = _uint_value(data, &t, 8);
    if !vr.is_ok {
      return _err_value(vr.error);
    }
    let v: Int = vr.value;
    return _ok_value(SnmpValue{ tag: tag; int_val: v; bytes: Vec[UInt8].new(); oid: Vec[Int].new(); next: t.next; });
  }
  return _err_value(_at("ber: unsupported value tag", off));
}

// Wrap `content` in a TLV with tag `tag` and a definite length.
fn _wrap_tlv(tag: Int, content: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(tag as UInt8);
  _push_length(&mut out, content.len());
  _push_bytes(&mut out, content);
  return out;
}

/// Encode a `SnmpValue` as its value TLV. `value.next` is ignored. The tag
/// rules mirror `snmp_value_decode`:
///   * INTEGER (2): minimal signed encoding;
///   * OCTET STRING (4) / Opaque (68): raw bytes;
///   * NULL (5): 0x05 0x00;
///   * OID (6): `ber_oid_encode` rules;
///   * IpAddress (64): length must be 4;
///   * Counter32/Gauge32/TimeTicks (65/66/67): 0..4294967295;
///   * Counter64 (70): any non-negative Int.
/// Errors: `ber: unsupported value tag`, `ber: bad ipaddress`, plus the
/// `ber_uint_encode` and `ber_oid_encode` catalogs.
/// Complexity: O(content bytes).
pub fn snmp_value_encode(value: &SnmpValue) -> Result[Vec[UInt8], Str] {
  let tag: Int = value.tag;
  if tag == SNMP_TAG_INTEGER {
    return _ok_bytes(ber_int_encode(value.int_val));
  }
  if tag == SNMP_TAG_OCTET_STRING {
    let b: Vec[UInt8] = value.bytes;
    return _ok_bytes(ber_octet_string_encode(&b));
  }
  if tag == SNMP_TAG_NULL {
    var out = Vec[UInt8].new();
    out.push(SNMP_TAG_NULL as UInt8);
    out.push(0 as UInt8);
    return _ok_bytes(out);
  }
  if tag == SNMP_TAG_OID {
    let a: Vec[Int] = value.oid;
    return ber_oid_encode(&a);
  }
  if tag == SNMP_TAG_IPADDRESS {
    let b: Vec[UInt8] = value.bytes;
    if b.len() != 4 {
      return _err_bytes("ber: bad ipaddress");
    }
    return _ok_bytes(_wrap_tlv(tag, &b));
  }
  if tag == SNMP_TAG_OPAQUE {
    let b: Vec[UInt8] = value.bytes;
    return _ok_bytes(_wrap_tlv(tag, &b));
  }
  if tag == SNMP_TAG_COUNTER32 || tag == SNMP_TAG_GAUGE32 || tag == SNMP_TAG_TIMETICKS || tag == SNMP_TAG_COUNTER64 {
    return ber_uint_encode(value.int_val, tag);
  }
  return _err_bytes("ber: unsupported value tag");
}

// --------------------------------------------------
//  Varbinds
// --------------------------------------------------

/// Parse one varbind at `off`: SEQUENCE { OBJECT IDENTIFIER name, value }.
/// The value may use any tag supported by `snmp_value_decode`. The returned
/// `next` is the offset just past the SEQUENCE.
/// Errors: the `ber_tlv_decode` / `ber_oid_decode` / `snmp_value_decode`
/// catalogs; `ber: tag mismatch` at `off` when the varbind is not a
/// SEQUENCE; `ber: value overruns container` at the start of a field whose
/// TLV crosses the SEQUENCE end; and `snmp: trailing bytes` when the SEQUENCE
/// declares more bytes than the name and value consume.
/// Complexity: O(name + value bytes).
pub fn snmp_varbind_parse(data: &Vec[UInt8], off: Int) -> Result[SnmpVarBind, Str] {
  let sr = ber_tlv_decode(data, off);
  if !sr.is_ok {
    return _err_vb(sr.error);
  }
  let seq: BerTlv = sr.value;
  if seq.tag != SNMP_TAG_SEQUENCE {
    return _err_vb(_at("ber: tag mismatch", off));
  }
  let nr = ber_oid_decode(data, seq.content);
  if !nr.is_ok {
    return _err_vb(nr.error);
  }
  let nm: BerOid = nr.value;
  if nm.next > seq.next {
    return _err_vb(_at("ber: value overruns container", seq.content));
  }
  let vr = snmp_value_decode(data, nm.next);
  if !vr.is_ok {
    return _err_vb(vr.error);
  }
  let val: SnmpValue = vr.value;
  if val.next > seq.next {
    return _err_vb(_at("ber: value overruns container", nm.next));
  }
  if val.next != seq.next {
    return _err_vb(_at("snmp: trailing bytes", val.next));
  }
  return _ok_vb(SnmpVarBind{ name: nm.arcs; value: val; next: seq.next; });
}

// --------------------------------------------------
//  Messages
// --------------------------------------------------

/// Parse a whole SNMP message at offset 0: SEQUENCE { INTEGER version,
/// OCTET STRING community, PDU }. The version must be 0 (v1) or 1 (v2c).
///
/// PDU layouts:
///   * 0xA0..0xA3 and 0xA6/0xA7 (GetRequest, GetNextRequest, Response,
///     SetRequest, InformRequest, SNMPv2-Trap): request-id, error-status,
///     error-index, variable-bindings;
///   * 0xA4 (Trap v1): enterprise OID, agent-addr IpAddress, generic-trap
///     INTEGER, specific-trap INTEGER, time-stamp TimeTicks,
///     variable-bindings (no request-id / error-status / error-index);
///   * 0xA5 (GetBulkRequest): request-id, non-repeaters, max-repetitions,
///     variable-bindings (no error fields; the second and third integers
///     are exposed as `non_repeaters` / `max_repetitions`).
///
/// The variable-bindings SEQUENCE may hold zero or more varbinds; each is
/// validated through `snmp_varbind_parse` and its absolute offset is stored
/// in `varbind_offsets`. Bytes after the message TLV are ignored.
///
/// Errors: the BER catalogs; `ber: tag mismatch` at offset 0 when the
/// message is not a SEQUENCE; `snmp: unsupported version` at the version
/// TLV; `snmp: bad pdu tag` at the PDU byte when it is outside 0xA0..0xA7;
/// `ber: value overruns container` when any field crosses its container;
/// and `snmp: trailing bytes` when a container declares more bytes than its
/// fields consume.
/// Complexity: O(message bytes).
pub fn snmp_message_parse(data: &Vec[UInt8]) -> Result[SnmpMessage, Str] {
  let mr = ber_tlv_decode(data, 0);
  if !mr.is_ok {
    return _err_msg(mr.error);
  }
  let msg: BerTlv = mr.value;
  if msg.tag != SNMP_TAG_SEQUENCE {
    return _err_msg(_at("ber: tag mismatch", 0));
  }

  let vr = _int_in(data, msg.content, msg.next);
  if !vr.is_ok {
    return _err_msg(vr.error);
  }
  let vb: BerInt = vr.value;
  let version: Int = vb.value;
  if version != SNMP_VERSION_V1 && version != SNMP_VERSION_V2C {
    return _err_msg(_at("snmp: unsupported version", msg.content));
  }

  let cr = ber_octet_string_decode(data, vb.next);
  if !cr.is_ok {
    return _err_msg(cr.error);
  }
  let cb: BerBytes = cr.value;
  if cb.next > msg.next {
    return _err_msg(_at("ber: value overruns container", vb.next));
  }
  if cb.next >= msg.next {
    return _err_msg(_at("ber: truncated tag", cb.next));
  }

  let pdu_off: Int = cb.next;
  let ptag: Int = _byte(data, pdu_off);
  if ptag < 160 || ptag > 167 {
    return _err_msg(_at("snmp: bad pdu tag", pdu_off));
  }

  let pr = ber_tlv_decode(data, pdu_off);
  if !pr.is_ok {
    return _err_msg(pr.error);
  }
  let pdu: BerTlv = pr.value;
  if pdu.next > msg.next {
    return _err_msg(_at("ber: value overruns container", pdu_off));
  }
  if pdu.next != msg.next {
    return _err_msg(_at("snmp: trailing bytes", pdu.next));
  }

  let kind: Int = ptag - 160;
  var request_id = -1;
  var error_status = -1;
  var error_index = -1;
  var non_repeaters = -1;
  var max_repetitions = -1;
  var enterprise = Vec[Int].new();
  var agent_addr = Vec[UInt8].new();
  var generic_trap = 0;
  var specific_trap = 0;
  var timestamp = 0;
  var pos: Int = pdu.content;

  if kind == SNMP_PDU_TRAP_V1 {
    let er = _oid_in(data, pos, pdu.next);
    if !er.is_ok {
      return _err_msg(er.error);
    }
    let e: BerOid = er.value;
    enterprise = e.arcs;
    pos = e.next;
    let ar = _ip_in(data, pos, pdu.next);
    if !ar.is_ok {
      return _err_msg(ar.error);
    }
    let a: BerBytes = ar.value;
    agent_addr = a.bytes;
    pos = a.next;
    let gr = _int_in(data, pos, pdu.next);
    if !gr.is_ok {
      return _err_msg(gr.error);
    }
    let g: BerInt = gr.value;
    generic_trap = g.value;
    pos = g.next;
    let sr = _int_in(data, pos, pdu.next);
    if !sr.is_ok {
      return _err_msg(sr.error);
    }
    let s: BerInt = sr.value;
    specific_trap = s.value;
    pos = s.next;
    let tr = _ticks_in(data, pos, pdu.next);
    if !tr.is_ok {
      return _err_msg(tr.error);
    }
    let ts: BerInt = tr.value;
    timestamp = ts.value;
    pos = ts.next;
  } elif kind == SNMP_PDU_GET_BULK_REQUEST {
    let br1 = _int_in(data, pos, pdu.next);
    if !br1.is_ok {
      return _err_msg(br1.error);
    }
    let b1: BerInt = br1.value;
    request_id = b1.value;
    pos = b1.next;
    let br2 = _int_in(data, pos, pdu.next);
    if !br2.is_ok {
      return _err_msg(br2.error);
    }
    let b2: BerInt = br2.value;
    non_repeaters = b2.value;
    pos = b2.next;
    let br3 = _int_in(data, pos, pdu.next);
    if !br3.is_ok {
      return _err_msg(br3.error);
    }
    let b3: BerInt = br3.value;
    max_repetitions = b3.value;
    pos = b3.next;
  } else {
    let br1 = _int_in(data, pos, pdu.next);
    if !br1.is_ok {
      return _err_msg(br1.error);
    }
    let b1: BerInt = br1.value;
    request_id = b1.value;
    pos = b1.next;
    let br2 = _int_in(data, pos, pdu.next);
    if !br2.is_ok {
      return _err_msg(br2.error);
    }
    let b2: BerInt = br2.value;
    error_status = b2.value;
    pos = b2.next;
    let br3 = _int_in(data, pos, pdu.next);
    if !br3.is_ok {
      return _err_msg(br3.error);
    }
    let b3: BerInt = br3.value;
    error_index = b3.value;
    pos = b3.next;
  }

  let lr = _tlv_in(data, pos, pdu.next);
  if !lr.is_ok {
    return _err_msg(lr.error);
  }
  let list: BerTlv = lr.value;
  if list.tag != SNMP_TAG_SEQUENCE {
    return _err_msg(_at("ber: tag mismatch", pos));
  }
  var vb_offsets = Vec[Int].new();
  var vpos: Int = list.content;
  while vpos < list.next {
    let xr = snmp_varbind_parse(data, vpos);
    if !xr.is_ok {
      return _err_msg(xr.error);
    }
    let x: SnmpVarBind = xr.value;
    if x.next > list.next {
      return _err_msg(_at("ber: value overruns container", vpos));
    }
    vb_offsets.push(vpos);
    vpos = x.next;
  }
  if vpos != list.next {
    return _err_msg(_at("snmp: trailing bytes", vpos));
  }
  if list.next != pdu.next {
    return _err_msg(_at("snmp: trailing bytes", list.next));
  }

  let m = SnmpMessage{
    version: version;
    community: cb.bytes;
    community_offset: cb.next - cb.bytes.len();
    community_length: cb.bytes.len();
    pdu_tag: ptag;
    pdu_kind: kind;
    request_id: request_id;
    error_status: error_status;
    error_index: error_index;
    non_repeaters: non_repeaters;
    max_repetitions: max_repetitions;
    enterprise: enterprise;
    agent_addr: agent_addr;
    generic_trap: generic_trap;
    specific_trap: specific_trap;
    timestamp: timestamp;
    varbind_offsets: vb_offsets;
    pdu_offset: pdu_off;
    next: msg.next;
  };
  return _ok_msg(m);
}

/// Number of varbinds in the parsed index. Complexity: O(1).
pub fn snmp_varbind_count(m: &SnmpMessage) -> Int {
  return m.varbind_offsets.len();
}

/// Absolute offset of the i-th varbind SEQUENCE, or -1 when `i` is
/// negative or >= `snmp_varbind_count(m)`. Complexity: O(1).
pub fn snmp_varbind_offset(m: &SnmpMessage, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.varbind_offsets.len() {
    return -1;
  }
  let off: Int = m.varbind_offsets[i];
  return off;
}

/// PDU tag (0xA0..0xA7) for a PDU kind 0..7, or -1 when the kind is out of
/// range. Complexity: O(1).
pub fn snmp_pdu_tag(kind: Int) -> Int {
  if kind < 0 || kind > 7 {
    return -1;
  }
  return 160 + kind;
}

/// PDU kind (0..7) for a PDU tag 0xA0..0xA7, or -1 otherwise.
/// Complexity: O(1).
pub fn snmp_pdu_kind(tag: Int) -> Int {
  if tag < 160 || tag > 167 {
    return -1;
  }
  return tag - 160;
}

// --------------------------------------------------
//  Message building (minimal one-varbind forms)
// --------------------------------------------------

// Shared builder: SEQUENCE { INTEGER version, OCTET STRING community,
// PDU } with one varbind { oid, value }. `kind` must be 0, 1, 2, 3, 5, 6 or
// 7; the trap form (kind 4) has a different field layout and is not built.
// `error_status` / `error_index` carry the second and third PDU integers
// (for kind 5 they are the non-repeaters / max-repetitions values).
fn _message_build(kind: Int, version: Int, community: &Vec[UInt8], request_id: Int, error_status: Int, error_index: Int, oid: &Vec[Int], value: &SnmpValue) -> Result[Vec[UInt8], Str] {
  if version != SNMP_VERSION_V1 && version != SNMP_VERSION_V2C {
    return _err_bytes("snmp: unsupported version");
  }
  if kind < 0 || kind > 7 {
    return _err_bytes("snmp: bad pdu kind");
  }
  if kind == SNMP_PDU_TRAP_V1 {
    return _err_bytes("snmp: trap build unsupported");
  }
  let oidr = ber_oid_encode(oid);
  if !oidr.is_ok {
    return _err_bytes(oidr.error);
  }
  let oid_tlv: Vec[UInt8] = oidr.value;
  let valr = snmp_value_encode(value);
  if !valr.is_ok {
    return _err_bytes(valr.error);
  }
  let val_tlv: Vec[UInt8] = valr.value;
  var vb_body = Vec[UInt8].new();
  _push_bytes(&mut vb_body, &oid_tlv);
  _push_bytes(&mut vb_body, &val_tlv);
  let vb = _wrap_tlv(SNMP_TAG_SEQUENCE, &vb_body);
  var list_body = Vec[UInt8].new();
  _push_bytes(&mut list_body, &vb);
  let list = _wrap_tlv(SNMP_TAG_SEQUENCE, &list_body);
  var pdu_body = Vec[UInt8].new();
  _push_bytes(&mut pdu_body, &ber_int_encode(request_id));
  _push_bytes(&mut pdu_body, &ber_int_encode(error_status));
  _push_bytes(&mut pdu_body, &ber_int_encode(error_index));
  _push_bytes(&mut pdu_body, &list);
  let pdu = _wrap_tlv(160 + kind, &pdu_body);
  var msg_body = Vec[UInt8].new();
  _push_bytes(&mut msg_body, &ber_int_encode(version));
  let comm = ber_octet_string_encode(community);
  _push_bytes(&mut msg_body, &comm);
  _push_bytes(&mut msg_body, &pdu);
  let msg = _wrap_tlv(SNMP_TAG_SEQUENCE, &msg_body);
  return _ok_bytes(msg);
}

/// Build a minimal GetRequest: one varbind whose value is NULL. `version`
/// must be 0 or 1; `community` is written verbatim. Errors:
/// `snmp: unsupported version`, the `ber_oid_encode` catalog and (through
/// `snmp_value_encode`) none for NULL. The PDU carries request-id
/// `request_id`, error-status 0 and error-index 0.
/// Complexity: O(oid + community bytes).
pub fn snmp_get_request_build(version: Int, community: &Vec[UInt8], request_id: Int, oid: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  var null_val = SnmpValue{ tag: SNMP_TAG_NULL; int_val: 0; bytes: Vec[UInt8].new(); oid: Vec[Int].new(); next: 0; };
  return _message_build(SNMP_PDU_GET_REQUEST, version, community, request_id, 0, 0, oid, &null_val);
}

/// Build a minimal Response: one varbind `{ oid, value }` with error-status
/// 0 and error-index 0. `version` must be 0 or 1; `community` is written
/// verbatim; `value.next` is ignored. Errors: `snmp: unsupported version`,
/// the `ber_oid_encode` catalog and the `snmp_value_encode` catalog.
/// Complexity: O(oid + community + value bytes).
pub fn snmp_response_build(version: Int, community: &Vec[UInt8], request_id: Int, oid: &Vec[Int], value: &SnmpValue) -> Result[Vec[UInt8], Str] {
  return _message_build(SNMP_PDU_RESPONSE, version, community, request_id, 0, 0, oid, value);
}
