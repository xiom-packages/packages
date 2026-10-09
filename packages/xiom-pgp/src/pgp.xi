// XIOM -- xiom.pgp: OpenPGP (RFC 4880/9580 subset) packet + ASCII armor codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, nothing beyond xiom.std) structural OpenPGP codec:
//
//   * `pgp_document_parse` walks a binary OpenPGP stream into a flat packet
//     document. Both header formats are supported: old-format length types
//     0-3 (including the indeterminate type 3 that consumes the rest of the
//     input) and new-format definite lengths (one/two/five octets) and
//     partial body lengths (chunk chains ending in a definite length; the
//     first partial chunk must be at least 512 octets, RFC 4880 4.2.2.4).
//     Every declared length is validated against the buffer before it is
//     used; truncation, reserved tag 0 and invalid tag bytes are rejected
//     with the byte offset of the offending element in the message.
//   * Packet tags 1..63 are framed; the ten tags this package names are
//     Public-Key 6, Public-Subkey 14, Secret-Key 5, Signature 2, User ID 13,
//     User Attribute 17, Literal Data 11, Compressed Data 8, Marker 10 and
//     Trust 12.
//   * `pgp_mpi_decode`/`pgp_mpi_encode` implement the OpenPGP MPI: a
//     two-octet big-endian bit count followed by ceil(bits/8) big-endian
//     value octets. Decoding rejects truncated and non-canonical MPIs
//     (declared bit count not matching the value's highest set bit).
//   * `pgp_signature_v4_decode` parses a v4 signature body (version, type,
//     public-key and hash algorithms, hashed subpacket region, unhashed
//     subpacket region, left16) and frames every subpacket with the
//     1/2/5-octet subpacket length encoding; `pgp_signature_v4_encode`
//     rebuilds the body, and `pgp_subpacket_encode` emits one subpacket.
//   * `pgp_key_v4_decode` parses a v4 key body (creation time, algorithm,
//     MPI key material, optional curve OID) for RSA, ElGamal, DSA, ECDH,
//     ECDSA, EdDSA and the RFC 9580 native curves. Secret material that
//     follows the public MPIs is not parsed; `public_end` marks the split.
//   * ASCII armor: BEGIN/END lines, `Name: value` headers, blank line,
//     base64 payload, optional CRC24 line (`=` + 4 base64 characters) that
//     is validated against poly 0x1864CFB; `pgp_armor_encode` emits the
//     canonical form (64-character base64 lines, LF endings, CRC24 line).
//
// Non-goals: no cryptography of any kind (no RSA/DSA/ECDSA math, no
// hashing, no key validation beyond structure), no packet semantics for
// Literal/Compressed/Trust/Marker bodies, no streaming API.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; state travels by reference; no methods, no
//     lambdas, no Vec[StructType], no Vec[fn] dispatch, no `match`.
//   * Ok/Err for every Result type are constructed only in the tiny leaf
//     helpers below (_ok_doc/_err_doc, _ok_mpi/_err_mpi, _ok_sig/_err_sig,
//     _ok_key/_err_key, _ok_armor/_err_armor, _ok_bytes/_err_bytes,
//     _ok_str/_err_str, _ok_int/_err_int).
//   * every raw byte read is widened with `(x as Int) & 0xFF`; every
//     Vec[Int]/Vec[Str] element read is bound to a typed local first; Str
//     values read from Vec[Str] are compared byte-wise with _str_eq and
//     callers compare with xiom.string.compare.str_compare.
//   * `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
//     expected: such fields are copied into a local first.
//   * no bitwise shifts: powers of two are built by multiplication and
//     fields are split with division and modulo only; ceil(bits/8) is
//     computed as q + (r > 0) with explicit quotient/remainder.
//   * Err messages carry byte offsets produced with xiom.convert.int.

module xiom.pgp

use xiom.string;
use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Canonical base64 body line width in armor output: 64 characters.
pub const PGP_ARMOR_LINE_WIDTH: Int = 64;

/// Largest accepted armor label, in bytes.
pub const PGP_MAX_LABEL: Int = 64;

// --------------------------------------------------
//  Public types (flat storage; parallel Vec fields)
// --------------------------------------------------

/// Parsed OpenPGP packet document: one logical slot per packet, in order.
///
/// `tag[i]` is the packet tag, `format[i]` is 0 for old-format headers and 1
/// for new-format headers, `start[i]` is the packet's offset in the source
/// buffer and `header_len[i]` the number of header bytes before the first
/// body octet. `length_type[i]` is the old length type 0-3 for old format,
/// the length-field width 1/2/5 for new-format definite lengths, and 0 for
/// new-format partial-body packets; `is_partial[i]` is 1 for a partial-body
/// packet and `chunk_count[i]` counts its length chunks (1 otherwise).
/// Packet bodies are copied into the `bodies` pool: packet `i` occupies the
/// `body_len[i]` bytes at `bodies[body_start[i]]`.
///
/// Fields are implementation details; callers use the pgp_packet_*
/// accessors below. Documents are only produced by pgp_document_parse.
pub type PgpDocument = {
  tag: Vec[Int];
  format: Vec[Int];
  start: Vec[Int];
  header_len: Vec[Int];
  length_type: Vec[Int];
  is_partial: Vec[Int];
  chunk_count: Vec[Int];
  body_start: Vec[Int];
  body_len: Vec[Int];
  bodies: Vec[UInt8];
}

/// A decoded OpenPGP MPI within a source buffer: `bits` is the declared bit
/// count, the value octets are the `value_len` bytes at `value_start`, and
/// `next` is the offset one past the MPI (callers continue parsing there).
pub type PgpMpi = {
  bits: Int;
  value_start: Int;
  value_len: Int;
  next: Int;
}

/// Parsed v4 signature body. `body` is a copy of the signature body bytes;
/// `hashed_offset`/`hashed_len` and `unhashed_offset`/`unhashed_len` delimit
/// the two subpacket regions inside `body`; each subpacket `i` occupies the
/// `sub_len[i]` content bytes (type octet plus data) at `sub_start[i]`, with
/// `sub_hashed[i]` = 1 for the hashed region and 0 for the unhashed region.
/// `left16` holds the two trailer octets.
pub type PgpSignature = {
  body: Vec[UInt8];
  version: Int;
  sig_type: Int;
  pubkey_algo: Int;
  hash_algo: Int;
  hashed_offset: Int;
  hashed_len: Int;
  unhashed_offset: Int;
  unhashed_len: Int;
  sub_hashed: Vec[Int];
  sub_start: Vec[Int];
  sub_len: Vec[Int];
  left16: Vec[UInt8];
}

/// Parsed v4 key body. `body` is a copy of the key body bytes; `created` is
/// the 32-bit creation time, `algo` the public-key algorithm. For curve
/// algorithms, `oid_start`/`oid_len` delimit the raw curve OID inside
/// `body`. Each MPI `i` has declared `mpi_bits[i]` and its value octets are
/// the `mpi_value_len[i]` bytes at `mpi_start[i] + 2`. `public_end` is the
/// offset one past the public key material (secret material may follow).
pub type PgpKey = {
  body: Vec[UInt8];
  version: Int;
  created: Int;
  algo: Int;
  oid_start: Int;
  oid_len: Int;
  mpi_start: Vec[Int];
  mpi_bits: Vec[Int];
  mpi_value_len: Vec[Int];
  public_end: Int;
}

/// Decoded ASCII armor block. `label` is the BEGIN/END label, `headers` the
/// raw `Name: value` lines before the blank separator, `data` the decoded
/// payload, and `crc`/`has_crc` the CRC24 state (has_crc = 1 when the input
/// carried a checksum line).
pub type PgpArmor = {
  label: Str;
  headers: Vec[Str];
  data: Vec[UInt8];
  crc: Int;
  has_crc: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[PgpDocument, Str].
fn _ok_doc(v: PgpDocument) -> Result[PgpDocument, Str] {
  return Ok(v);
}

// Err(m) for Result[PgpDocument, Str].
fn _err_doc(m: Str) -> Result[PgpDocument, Str] {
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

// Ok(v) for Result[PgpMpi, Str].
fn _ok_mpi(v: PgpMpi) -> Result[PgpMpi, Str] {
  return Ok(v);
}

// Err(m) for Result[PgpMpi, Str].
fn _err_mpi(m: Str) -> Result[PgpMpi, Str] {
  return Err(m);
}

// Ok(v) for Result[PgpSignature, Str].
fn _ok_sig(v: PgpSignature) -> Result[PgpSignature, Str] {
  return Ok(v);
}

// Err(m) for Result[PgpSignature, Str].
fn _err_sig(m: Str) -> Result[PgpSignature, Str] {
  return Err(m);
}

// Ok(v) for Result[PgpKey, Str].
fn _ok_key(v: PgpKey) -> Result[PgpKey, Str] {
  return Ok(v);
}

// Err(m) for Result[PgpKey, Str].
fn _err_key(m: Str) -> Result[PgpKey, Str] {
  return Err(m);
}

// Ok(v) for Result[PgpArmor, Str].
fn _ok_armor(v: PgpArmor) -> Result[PgpArmor, Str] {
  return Ok(v);
}

// Err(m) for Result[PgpArmor, Str].
fn _err_armor(m: Str) -> Result[PgpArmor, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and text helpers
// --------------------------------------------------

// Byte at `pos` of a byte vector widened to an Int (0..255); callers
// guarantee the bounds.
fn _vb(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Byte at `pos` of a Str widened to an Int (0..255); callers guarantee the
// bounds.
fn _tb(text: Str, pos: Int) -> Int {
  return (string.byte_at(text, pos) as Int) & 0xFF;
}

// Decimal text of an Int (used in every offset-carrying error message).
fn _itos(n: Int) -> Str {
  return convert.int_to_string(n);
}

// 2**k for 0 <= k <= 62, built by multiplication (no shifts).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// ceil(bits / 8) with an explicit quotient/remainder (no shifts).
fn _ceil8(bits: Int) -> Int {
  let q = bits / 8;
  let r = bits % 8;
  if r > 0 {
    return q + 1;
  }
  return q;
}

// Big-endian 16-bit value at `pos`.
fn _uint16(data: &Vec[UInt8], pos: Int) -> Int {
  return _vb(data, pos) * 256 + _vb(data, pos + 1);
}

// Big-endian 32-bit value at `pos`.
fn _uint32(data: &Vec[UInt8], pos: Int) -> Int {
  return _vb(data, pos) * 16777216 + _vb(data, pos + 1) * 65536 + _vb(data, pos + 2) * 256 + _vb(data, pos + 3);
}

// Append the bytes of `s`.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append `len` bytes of `src` starting at `start`.
fn _push_range(out: &mut Vec[UInt8], src: &Vec[UInt8], start: Int, len: Int) {
  var i = 0;
  while i < len {
    out.push(src[start + i]);
    i = i + 1;
  }
}

// True when `a` and `b` are byte-for-byte equal (never `==` on Str values).
fn _str_eq(a: Str, b: Str) -> Bool {
  let n = a.len();
  if n != b.len() {
    return false;
  }
  var i = 0;
  while i < n {
    if _tb(a, i) != _tb(b, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Index of the next LF at or after `pos`, or the text length.
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

// --------------------------------------------------
//  Packet types
// --------------------------------------------------

/// Packet tag of a Public-Key packet. Complexity: O(1).
pub fn pgp_packet_type_public_key() -> Int { return 6; }

/// Packet tag of a Public-Subkey packet. Complexity: O(1).
pub fn pgp_packet_type_public_subkey() -> Int { return 14; }

/// Packet tag of a Secret-Key packet. Complexity: O(1).
pub fn pgp_packet_type_secret_key() -> Int { return 5; }

/// Packet tag of a Signature packet. Complexity: O(1).
pub fn pgp_packet_type_signature() -> Int { return 2; }

/// Packet tag of a User ID packet. Complexity: O(1).
pub fn pgp_packet_type_user_id() -> Int { return 13; }

/// Packet tag of a User Attribute packet. Complexity: O(1).
pub fn pgp_packet_type_user_attribute() -> Int { return 17; }

/// Packet tag of a Literal Data packet. Complexity: O(1).
pub fn pgp_packet_type_literal_data() -> Int { return 11; }

/// Packet tag of a Compressed Data packet. Complexity: O(1).
pub fn pgp_packet_type_compressed_data() -> Int { return 8; }

/// Packet tag of a Marker packet. Complexity: O(1).
pub fn pgp_packet_type_marker() -> Int { return 10; }

/// Packet tag of a Trust packet. Complexity: O(1).
pub fn pgp_packet_type_trust() -> Int { return 12; }

/// Short RFC 4880 name of a packet tag, or "Unknown" for tags this package
/// does not name. Complexity: O(1).
pub fn pgp_packet_type_name(tag: Int) -> Str {
  if tag == 2 { return "Signature"; }
  if tag == 5 { return "Secret-Key"; }
  if tag == 6 { return "Public-Key"; }
  if tag == 8 { return "Compressed Data"; }
  if tag == 10 { return "Marker"; }
  if tag == 11 { return "Literal Data"; }
  if tag == 12 { return "Trust"; }
  if tag == 13 { return "User ID"; }
  if tag == 14 { return "Public-Subkey"; }
  if tag == 17 { return "User Attribute"; }
  return "Unknown";
}

// --------------------------------------------------
//  Document decode
// --------------------------------------------------

/// Parse a binary OpenPGP packet stream into a flat PgpDocument.
///
/// Params: data - the packet bytes.
/// Returns: Ok(document) listing every packet in input order. Old-format
/// headers use length types 0 (one octet), 1 (two octets), 2 (four octets)
/// and 3 (indeterminate: the body runs to the end of the input). New-format
/// headers use definite one/two/five-octet lengths or partial body lengths
/// (a chain of 2**n-octet chunks terminated by a definite length; the first
/// partial chunk must be at least 512 octets). Empty input yields Ok with
/// zero packets.
/// Error case: Err("pgp: ...") on the first violation: a tag byte with bit
/// 7 clear or with reserved tag 0, a truncated header, or a declared body
/// length that runs past the end of the buffer (including every partial
/// chunk). Messages name the byte offset of the offending element.
/// Complexity: O(data.len()).
pub fn pgp_document_parse(data: Vec[UInt8]) -> Result[PgpDocument, Str] {
  var tag = Vec[Int].new();
  var format = Vec[Int].new();
  var start = Vec[Int].new();
  var header_len = Vec[Int].new();
  var length_type = Vec[Int].new();
  var is_partial = Vec[Int].new();
  var chunk_count = Vec[Int].new();
  var body_start = Vec[Int].new();
  var body_len = Vec[Int].new();
  var bodies = Vec[UInt8].new();

  let n = data.len();
  var pos = 0;
  while pos < n {
    let pstart = pos;
    let b0 = _vb(&data, pos);
    if b0 < 128 {
      return _err_doc("pgp: invalid packet tag " + _itos(b0) + " at offset " + _itos(pstart));
    }
    var ptag = 0;
    var pformat = 0;
    if b0 >= 192 {
      ptag = b0 - 192;
      pformat = 1;
    } else {
      ptag = (b0 - 128) / 4;
      pformat = 0;
    }
    if ptag == 0 {
      return _err_doc("pgp: invalid packet tag " + _itos(b0) + " at offset " + _itos(pstart));
    }

    var ltype = 0;
    var partial = 0;
    var chunks = 1;
    var blen = 0;
    var hlen = 0;
    var first_data = 0;
    var packet_end = 0;
    var chunk_starts = Vec[Int].new();
    var chunk_lens = Vec[Int].new();

    if pformat == 0 {
      ltype = b0 % 4;
      var bstart = 0;
      if ltype == 0 {
        bstart = pstart + 2;
        if bstart > n {
          return _err_doc("pgp: truncated packet header at offset " + _itos(pstart + 1));
        }
        blen = _vb(&data, pstart + 1);
      } elif ltype == 1 {
        bstart = pstart + 3;
        if bstart > n {
          return _err_doc("pgp: truncated packet header at offset " + _itos(pstart + 1));
        }
        blen = _uint16(&data, pstart + 1);
      } elif ltype == 2 {
        bstart = pstart + 5;
        if bstart > n {
          return _err_doc("pgp: truncated packet header at offset " + _itos(pstart + 1));
        }
        blen = _uint32(&data, pstart + 1);
      } else {
        bstart = pstart + 1;
        blen = n - bstart;
      }
      if bstart + blen > n {
        return _err_doc("pgp: truncated packet body at offset " + _itos(bstart));
      }
      hlen = bstart - pstart;
      first_data = bstart;
      packet_end = bstart + blen;
      chunk_starts.push(bstart);
      chunk_lens.push(blen);
    } else {
      var p = pstart + 1;
      var first_chunk = 1;
      var pending = 1;
      while pending == 1 {
        if p >= n {
          return _err_doc("pgp: truncated packet header at offset " + _itos(p));
        }
        let l0 = _vb(&data, p);
        var clen = 0;
        var cpartial = 0;
        var lneed = 1;
        if l0 < 192 {
          clen = l0;
          lneed = 1;
        } elif l0 < 224 {
          if p + 2 > n {
            return _err_doc("pgp: truncated packet header at offset " + _itos(p));
          }
          clen = (l0 - 192) * 256 + _vb(&data, p + 1) + 192;
          lneed = 2;
        } elif l0 == 255 {
          if p + 5 > n {
            return _err_doc("pgp: truncated packet header at offset " + _itos(p));
          }
          clen = _uint32(&data, p + 1);
          lneed = 5;
        } else {
          clen = _pow2(l0 - 224);
          lneed = 1;
          cpartial = 1;
        }
        if cpartial == 1 && first_chunk == 1 && clen < 512 {
          return _err_doc("pgp: partial body length below 512 at offset " + _itos(p));
        }
        let data_at = p + lneed;
        if data_at + clen > n {
          return _err_doc("pgp: truncated packet body at offset " + _itos(data_at));
        }
        if first_chunk == 1 {
          first_data = data_at;
          hlen = data_at - pstart;
        }
        chunk_starts.push(data_at);
        chunk_lens.push(clen);
        blen = blen + clen;
        if cpartial == 1 {
          partial = 1;
          chunks = chunks + 1;
          p = data_at + clen;
          first_chunk = 0;
        } else {
          if partial == 0 {
            ltype = lneed;
          }
          packet_end = data_at + clen;
          pending = 0;
        }
      }
    }

    tag.push(ptag);
    format.push(pformat);
    start.push(pstart);
    header_len.push(hlen);
    length_type.push(ltype);
    is_partial.push(partial);
    chunk_count.push(chunks);
    body_start.push(bodies.len());
    body_len.push(blen);
    var ci = 0;
    while ci < chunk_lens.len() {
      let cs: Int = chunk_starts[ci];
      let cl: Int = chunk_lens[ci];
      _push_range(&mut bodies, &data, cs, cl);
      ci = ci + 1;
    }
    pos = packet_end;
  }

  let doc = PgpDocument{
    tag: tag;
    format: format;
    start: start;
    header_len: header_len;
    length_type: length_type;
    is_partial: is_partial;
    chunk_count: chunk_count;
    body_start: body_start;
    body_len: body_len;
    bodies: bodies;
  };
  return _ok_doc(doc);
}

// --------------------------------------------------
//  Document accessors
// --------------------------------------------------

/// Number of packets in `d`. Complexity: O(1).
pub fn pgp_packet_count(d: &PgpDocument) -> Int
  ensures: result == d.tag.len();
{
  return d.tag.len();
}

/// Packet tag of packet `i`; -1 when `i` is out of range. Complexity: O(1).
pub fn pgp_packet_tag(d: &PgpDocument, i: Int) -> Int
  ensures: i < 0 || i >= d.tag.len() => result == -1;
  ensures: result != -1 => i >= 0 && i < d.tag.len();
{
  if i < 0 || i >= d.tag.len() {
    return -1;
  }
  let t: Int = d.tag[i];
  return t;
}

/// Header format of packet `i`: 0 old, 1 new; -1 out of range.
/// Complexity: O(1).
pub fn pgp_packet_format(d: &PgpDocument, i: Int) -> Int {
  if i < 0 || i >= d.format.len() {
    return -1;
  }
  let f: Int = d.format[i];
  return f;
}

/// Offset of packet `i` in the source buffer; -1 out of range.
/// Complexity: O(1).
pub fn pgp_packet_start(d: &PgpDocument, i: Int) -> Int {
  if i < 0 || i >= d.start.len() {
    return -1;
  }
  let v: Int = d.start[i];
  return v;
}

/// Header bytes of packet `i` before the first body octet; -1 out of range.
/// For partial-body packets this is the tag plus the first chunk's length
/// field only. Complexity: O(1).
pub fn pgp_packet_header_len(d: &PgpDocument, i: Int) -> Int {
  if i < 0 || i >= d.header_len.len() {
    return -1;
  }
  let v: Int = d.header_len[i];
  return v;
}

/// Length type of packet `i`: old format 0-3, new-format definite 1/2/5
/// (width of the length field in octets), new-format partial 0; -1 out of
/// range. Complexity: O(1).
pub fn pgp_packet_length_type(d: &PgpDocument, i: Int) -> Int {
  if i < 0 || i >= d.length_type.len() {
    return -1;
  }
  let v: Int = d.length_type[i];
  return v;
}

/// 1 when packet `i` uses partial body lengths, 0 otherwise; -1 out of
/// range. Complexity: O(1).
pub fn pgp_packet_is_partial(d: &PgpDocument, i: Int) -> Int {
  if i < 0 || i >= d.is_partial.len() {
    return -1;
  }
  let v: Int = d.is_partial[i];
  return v;
}

/// Number of length chunks of packet `i` (1 unless partial); -1 out of
/// range. Complexity: O(1).
pub fn pgp_packet_chunk_count(d: &PgpDocument, i: Int) -> Int {
  if i < 0 || i >= d.chunk_count.len() {
    return -1;
  }
  let v: Int = d.chunk_count[i];
  return v;
}

/// Body length in bytes of packet `i`; -1 out of range. Complexity: O(1).
pub fn pgp_packet_body_len(d: &PgpDocument, i: Int) -> Int
  ensures: i < 0 || i >= d.body_len.len() => result == -1;
  ensures: result != -1 => i >= 0 && i < d.body_len.len();
{
  if i < 0 || i >= d.body_len.len() {
    return -1;
  }
  let v: Int = d.body_len[i];
  return v;
}

/// Copy of the body bytes of packet `i`, or an empty vector when `i` is out
/// of range. Complexity: O(len).
pub fn pgp_packet_body(d: &PgpDocument, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= d.body_len.len() || i >= d.body_start.len() {
    return out;
  }
  let off: Int = d.body_start[i];
  let len: Int = d.body_len[i];
  if off < 0 || len < 0 || off + len > d.bodies.len() {
    return out;
  }
  var k = 0;
  while k < len {
    out.push(d.bodies[off + k]);
    k = k + 1;
  }
  return out;
}

// --------------------------------------------------
//  Packet encode
// --------------------------------------------------

/// Encode a new-format definite body length with the shortest form.
///
/// Params: len - body length 0..4294967295 (negative values are encoded as
/// 0).
/// Returns: one octet for 0..191, two octets for 192..8383 and five octets
/// for 8384..4294967295. The encoding is the exact inverse of the parser's
/// new-format definite-length reader.
/// Complexity: O(1).
pub fn pgp_new_length_encode(len: Int) -> Vec[UInt8]
  ensures: len < 0 => result.len() == 1;
  ensures: len >= 0 && len < 192 => result.len() == 1;
  ensures: len >= 192 && len <= 8383 => result.len() == 2;
  ensures: len > 8383 => result.len() == 5;
{
  var out = Vec[UInt8].new();
  var v = len;
  if v < 0 {
    v = 0;
  }
  if v < 192 {
    out.push(v as UInt8);
  } elif v <= 8383 {
    let x = v - 192;
    out.push((x / 256 + 192) as UInt8);
    out.push((x % 256) as UInt8);
  } else {
    out.push(255 as UInt8);
    out.push((v / 16777216) as UInt8);
    out.push(((v / 65536) % 256) as UInt8);
    out.push(((v / 256) % 256) as UInt8);
    out.push((v % 256) as UInt8);
  }
  return out;
}

/// Encode one new-format packet: tag octet, definite length, body.
///
/// Params: tag - packet tag 0..63 (clamped into range); body - the packet
/// body bytes.
/// Returns: the complete packet bytes with the shortest definite length.
/// Complexity: O(body.len()).
pub fn pgp_packet_encode(tag: Int, body: &Vec[UInt8]) -> Vec[UInt8]
  ensures: body.len() < 192 => result.len() == body.len() + 2;
  ensures: body.len() >= 192 && body.len() <= 8383 => result.len() == body.len() + 3;
  ensures: body.len() > 8383 => result.len() == body.len() + 6;
{
  var t = tag;
  if t < 0 {
    t = 0;
  }
  if t > 63 {
    t = 63;
  }
  var out = Vec[UInt8].new();
  out.push((192 + t) as UInt8);
  let lh: Vec[UInt8] = pgp_new_length_encode(body.len());
  _push_bytes(&mut out, &lh);
  _push_bytes(&mut out, body);
  return out;
}

// --------------------------------------------------
//  MPI codec
// --------------------------------------------------

/// Decode the MPI that starts at `offset` of `data`.
///
/// Params: data - the source buffer; offset - index of the two-octet bit
/// count.
/// Returns: Ok(mpi) with the declared bit count, the value range and the
/// offset one past the MPI. The zero MPI (bit count 0, no value octets) is
/// accepted; a non-zero bit count must match the value's highest set bit
/// exactly (no leading zero bits or octets).
/// Error case: Err("pgp: truncated MPI at offset N") when the bit count or
/// the value octets run past the buffer; Err("pgp: non-canonical MPI at
/// offset N") when the declared bit count does not match the value.
/// Complexity: O(1).
pub fn pgp_mpi_decode(data: &Vec[UInt8], offset: Int) -> Result[PgpMpi, Str]
  ensures: offset < 0 || offset + 2 > data.len() => result is Err;
  ensures: result is Ok => offset >= 0 && offset + 2 <= data.len();
{
  let n = data.len();
  if offset < 0 || offset + 2 > n {
    return _err_mpi("pgp: truncated MPI at offset " + _itos(offset));
  }
  let bits = _uint16(data, offset);
  let nbytes = _ceil8(bits);
  if offset + 2 + nbytes > n {
    return _err_mpi("pgp: truncated MPI at offset " + _itos(offset));
  }
  if bits > 0 {
    let k = (bits - 1) % 8;
    let div = _pow2(k);
    let top = _vb(data, offset + 2);
    if (top / div) % 2 != 1 {
      return _err_mpi("pgp: non-canonical MPI at offset " + _itos(offset));
    }
  }
  let m = PgpMpi{
    bits: bits;
    value_start: offset + 2;
    value_len: nbytes;
    next: offset + 2 + nbytes;
  };
  return _ok_mpi(m);
}

/// Encode a big-endian unsigned value as an MPI.
///
/// Params: value - big-endian magnitude; leading zero octets are skipped.
/// Returns: Ok(bytes) with the two-octet bit count followed by the value
/// octets; an all-zero (or empty) value becomes the canonical zero MPI
/// `00 00`.
/// Error case: Err("pgp: MPI too large") when the significant bit length
/// exceeds the 16-bit bit-count field (more than 8191 significant octets).
/// Complexity: O(value.len()).
pub fn pgp_mpi_encode(value: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  ensures: value.len() == 0 => result is Ok;
  ensures: result is Ok => result.value.len() >= 2;
{
  var out = Vec[UInt8].new();
  let n = value.len();
  var s = 0;
  while s < n {
    let b = _vb(value, s);
    if b != 0 {
      break;
    }
    s = s + 1;
  }
  if s == n {
    out.push(0 as UInt8);
    out.push(0 as UInt8);
    return _ok_bytes(out);
  }
  let top = _vb(value, s);
  var k = 7;
  while k > 0 {
    let div = _pow2(k);
    if (top / div) % 2 == 1 {
      break;
    }
    k = k - 1;
  }
  let bits = (n - s - 1) * 8 + k + 1;
  if bits > 65535 {
    return _err_bytes("pgp: MPI too large");
  }
  out.push((bits / 256) as UInt8);
  out.push((bits % 256) as UInt8);
  var i = s;
  while i < n {
    out.push(value[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Copy of the value octets of `m` read from `data`, or an empty vector when
/// the range does not fit. Complexity: O(m.value_len).
pub fn pgp_mpi_value_bytes(data: &Vec[UInt8], m: &PgpMpi) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = data.len();
  let s = m.value_start;
  let len = m.value_len;
  if s < 0 || len < 0 || s + len > n {
    return out;
  }
  var k = 0;
  while k < len {
    out.push(data[s + k]);
    k = k + 1;
  }
  return out;
}

// --------------------------------------------------
//  Subpacket codec
// --------------------------------------------------

/// Encode a subpacket content length with the 1/2/5-octet encoding.
///
/// Params: len - content length in octets (the type octet plus data),
/// 1..4294967295.
/// Returns: Ok(bytes) with the shortest of the one-octet form (< 192), the
/// two-octet form (192..8383) and the five-octet form (>= 8384). Subpacket
/// lengths never use the partial-body encodings (224..254).
/// Error case: Err("pgp: bad subpacket length") when `len` is below 1;
/// Err("pgp: subpacket too large") when `len` exceeds 4294967295.
/// Complexity: O(1).
pub fn pgp_subpacket_length_encode(len: Int) -> Result[Vec[UInt8], Str]
  ensures: len < 1 => result is Err;
  ensures: len > 4294967295 => result is Err;
  ensures: result is Ok => len >= 1 && len <= 4294967295;
{
  var out = Vec[UInt8].new();
  if len < 1 {
    return _err_bytes("pgp: bad subpacket length");
  }
  if len < 192 {
    out.push(len as UInt8);
  } elif len <= 8383 {
    let v = len - 192;
    out.push((v / 256 + 192) as UInt8);
    out.push((v % 256) as UInt8);
  } elif len <= 4294967295 {
    out.push(255 as UInt8);
    out.push((len / 16777216) as UInt8);
    out.push(((len / 65536) % 256) as UInt8);
    out.push(((len / 256) % 256) as UInt8);
    out.push((len % 256) as UInt8);
  } else {
    return _err_bytes("pgp: subpacket too large");
  }
  return _ok_bytes(out);
}

/// Encode one signature subpacket: length header, type octet, payload.
///
/// Params: kind - subpacket type octet 0..255; payload - subpacket data.
/// Returns: Ok(bytes) with the shortest length encoding.
/// Error case: Err("pgp: bad subpacket type") when `kind` is outside
/// 0..255; otherwise the pgp_subpacket_length_encode errors.
/// Complexity: O(payload.len()).
pub fn pgp_subpacket_encode(kind: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if kind < 0 || kind > 255 {
    return _err_bytes("pgp: bad subpacket type");
  }
  let hdr = pgp_subpacket_length_encode(payload.len() + 1);
  if !hdr.is_ok {
    return _err_bytes(hdr.error);
  }
  var out: Vec[UInt8] = hdr.value;
  out.push(kind as UInt8);
  _push_bytes(&mut out, payload);
  return _ok_bytes(out);
}

// Parse the subpacket run [start, start+len) of `body`, appending one entry
// per subpacket to the mirror vectors. `hashed` is stored verbatim in
// sub_hashed. Returns Ok(end offset) or the first framing error.
fn _parse_subpackets(body: &Vec[UInt8], start: Int, len: Int, hashed: Int,
    sub_hashed: &mut Vec[Int], sub_start: &mut Vec[Int],
    sub_len: &mut Vec[Int]) -> Result[Int, Str] {
  let end = start + len;
  var p = start;
  while p < end {
    let l0 = _vb(body, p);
    var clen = 0;
    var need = 0;
    if l0 < 192 {
      clen = l0;
      need = 1;
    } elif l0 < 224 {
      if p + 2 > end {
        return _err_int("pgp: truncated subpacket at offset " + _itos(p));
      }
      clen = (l0 - 192) * 256 + _vb(body, p + 1) + 192;
      need = 2;
    } elif l0 == 255 {
      if p + 5 > end {
        return _err_int("pgp: truncated subpacket at offset " + _itos(p));
      }
      clen = _uint32(body, p + 1);
      need = 5;
    } else {
      return _err_int("pgp: bad subpacket length at offset " + _itos(p));
    }
    if clen < 1 {
      return _err_int("pgp: bad subpacket length at offset " + _itos(p));
    }
    if p + need + clen > end {
      return _err_int("pgp: truncated subpacket at offset " + _itos(p));
    }
    sub_hashed.push(hashed);
    sub_start.push(p + need);
    sub_len.push(clen);
    p = p + need + clen;
  }
  return _ok_int(p);
}

// --------------------------------------------------
//  v4 signature body
// --------------------------------------------------

/// Decode a v4 signature body.
///
/// Params: body - the signature packet body bytes.
/// Returns: Ok(signature) with the version/type/algorithm octets, both
/// subpacket regions framed and the two left16 octets. Every subpacket is
/// recorded with its region flag, content offset and content length; the
/// content includes the subpacket type octet.
/// Error case: Err("pgp: ...") on the first violation:
/// Err("pgp: truncated signature at offset N"), Err("pgp: unsupported
/// signature version N at offset 0"), Err("pgp: truncated hashed
/// subpackets at offset N"), Err("pgp: truncated unhashed subpackets at
/// offset N"), Err("pgp: bad subpacket length at offset N"),
/// Err("pgp: truncated subpacket at offset N") and Err("pgp: trailing
/// signature data at offset N").
/// Complexity: O(body.len()).
pub fn pgp_signature_v4_decode(body: &Vec[UInt8]) -> Result[PgpSignature, Str]
  ensures: body.len() < 10 => result is Err;
  ensures: result is Ok => body.len() >= 10;
{
  let n = body.len();
  if n < 1 {
    return _err_sig("pgp: truncated signature at offset 0");
  }
  let version = _vb(body, 0);
  if version != 4 {
    return _err_sig("pgp: unsupported signature version " + _itos(version) + " at offset 0");
  }
  if n < 4 {
    return _err_sig("pgp: truncated signature at offset " + _itos(n));
  }
  let sig_type = _vb(body, 1);
  let pubkey_algo = _vb(body, 2);
  let hash_algo = _vb(body, 3);
  if n < 6 {
    return _err_sig("pgp: truncated signature at offset " + _itos(n));
  }
  let hashed_len = _uint16(body, 4);
  let hstart = 6;
  if hstart + hashed_len > n {
    return _err_sig("pgp: truncated hashed subpackets at offset " + _itos(hstart));
  }
  var sub_hashed = Vec[Int].new();
  var sub_start = Vec[Int].new();
  var sub_len = Vec[Int].new();
  let r1 = _parse_subpackets(body, hstart, hashed_len, 1, &mut sub_hashed, &mut sub_start, &mut sub_len);
  if !r1.is_ok {
    return _err_sig(r1.error);
  }
  let upos = hstart + hashed_len;
  if upos + 2 > n {
    return _err_sig("pgp: truncated unhashed subpackets at offset " + _itos(upos));
  }
  let unhashed_len = _uint16(body, upos);
  let ustart = upos + 2;
  if ustart + unhashed_len > n {
    return _err_sig("pgp: truncated unhashed subpackets at offset " + _itos(ustart));
  }
  let r2 = _parse_subpackets(body, ustart, unhashed_len, 0, &mut sub_hashed, &mut sub_start, &mut sub_len);
  if !r2.is_ok {
    return _err_sig(r2.error);
  }
  let lpos = ustart + unhashed_len;
  if lpos + 2 > n {
    return _err_sig("pgp: truncated signature at offset " + _itos(lpos));
  }
  if lpos + 2 != n {
    return _err_sig("pgp: trailing signature data at offset " + _itos(lpos + 2));
  }
  var left16 = Vec[UInt8].new();
  left16.push(body[lpos]);
  left16.push(body[lpos + 1]);
  var bcopy = Vec[UInt8].new();
  var k = 0;
  while k < n {
    bcopy.push(body[k]);
    k = k + 1;
  }
  let sig = PgpSignature{
    body: bcopy;
    version: version;
    sig_type: sig_type;
    pubkey_algo: pubkey_algo;
    hash_algo: hash_algo;
    hashed_offset: hstart;
    hashed_len: hashed_len;
    unhashed_offset: ustart;
    unhashed_len: unhashed_len;
    sub_hashed: sub_hashed;
    sub_start: sub_start;
    sub_len: sub_len;
    left16: left16;
  };
  return _ok_sig(sig);
}

/// Encode a v4 signature body from its parts.
///
/// Params: sig_type, pubkey_algo, hash_algo - signature octets 0..255;
/// hashed - pre-encoded hashed subpacket region; unhashed - pre-encoded
/// unhashed subpacket region; left16 - exactly two trailer octets.
/// Returns: Ok(body) with version 4 and both length-prefixed regions.
/// Error case: Err("pgp: bad signature field value") when an algorithm or
/// type octet is outside 0..255; Err("pgp: bad left16 length") when left16
/// is not exactly 2 octets; Err("pgp: subpacket region too long") when a
/// region exceeds 65535 octets.
/// Complexity: O(hashed.len() + unhashed.len()).
pub fn pgp_signature_v4_encode(sig_type: Int, pubkey_algo: Int, hash_algo: Int,
    hashed: &Vec[UInt8], unhashed: &Vec[UInt8], left16: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  ensures: sig_type < 0 || sig_type > 255 => result is Err;
  ensures: pubkey_algo < 0 || pubkey_algo > 255 => result is Err;
  ensures: hash_algo < 0 || hash_algo > 255 => result is Err;
  ensures: left16.len() != 2 => result is Err;
  ensures: hashed.len() > 65535 || unhashed.len() > 65535 => result is Err;
  ensures: result is Ok => left16.len() == 2;
  ensures: result is Ok => hashed.len() <= 65535 && unhashed.len() <= 65535;
{
  if sig_type < 0 || sig_type > 255 {
    return _err_bytes("pgp: bad signature field value");
  }
  if pubkey_algo < 0 || pubkey_algo > 255 {
    return _err_bytes("pgp: bad signature field value");
  }
  if hash_algo < 0 || hash_algo > 255 {
    return _err_bytes("pgp: bad signature field value");
  }
  if left16.len() != 2 {
    return _err_bytes("pgp: bad left16 length");
  }
  if hashed.len() > 65535 || unhashed.len() > 65535 {
    return _err_bytes("pgp: subpacket region too long");
  }
  var out = Vec[UInt8].new();
  out.push(4 as UInt8);
  out.push(sig_type as UInt8);
  out.push(pubkey_algo as UInt8);
  out.push(hash_algo as UInt8);
  out.push((hashed.len() / 256) as UInt8);
  out.push((hashed.len() % 256) as UInt8);
  _push_bytes(&mut out, hashed);
  out.push((unhashed.len() / 256) as UInt8);
  out.push((unhashed.len() % 256) as UInt8);
  _push_bytes(&mut out, unhashed);
  _push_bytes(&mut out, left16);
  return _ok_bytes(out);
}

/// Signature version stored in `s`. Complexity: O(1).
pub fn pgp_signature_version(s: &PgpSignature) -> Int {
  let v: Int = s.version;
  return v;
}

/// Signature type octet stored in `s`. Complexity: O(1).
pub fn pgp_signature_type(s: &PgpSignature) -> Int {
  let v: Int = s.sig_type;
  return v;
}

/// Public-key algorithm octet stored in `s`. Complexity: O(1).
pub fn pgp_signature_pubkey_algo(s: &PgpSignature) -> Int {
  let v: Int = s.pubkey_algo;
  return v;
}

/// Hash algorithm octet stored in `s`. Complexity: O(1).
pub fn pgp_signature_hash_algo(s: &PgpSignature) -> Int {
  let v: Int = s.hash_algo;
  return v;
}

/// Hashed subpacket region length of `s`. Complexity: O(1).
pub fn pgp_signature_hashed_len(s: &PgpSignature) -> Int {
  let v: Int = s.hashed_len;
  return v;
}

/// Unhashed subpacket region length of `s`. Complexity: O(1).
pub fn pgp_signature_unhashed_len(s: &PgpSignature) -> Int {
  let v: Int = s.unhashed_len;
  return v;
}

/// Number of subpackets framed in `s`. Complexity: O(1).
pub fn pgp_signature_subpacket_count(s: &PgpSignature) -> Int {
  return s.sub_len.len();
}

/// 1 when subpacket `i` is in the hashed region, 0 when in the unhashed
/// region; -1 when `i` is out of range. Complexity: O(1).
pub fn pgp_signature_subpacket_hashed(s: &PgpSignature, i: Int) -> Int {
  if i < 0 || i >= s.sub_hashed.len() {
    return -1;
  }
  let v: Int = s.sub_hashed[i];
  return v;
}

/// Content offset (inside the signature body) of subpacket `i`; -1 when `i`
/// is out of range. Complexity: O(1).
pub fn pgp_signature_subpacket_start(s: &PgpSignature, i: Int) -> Int {
  if i < 0 || i >= s.sub_start.len() {
    return -1;
  }
  let v: Int = s.sub_start[i];
  return v;
}

/// Content length of subpacket `i` (type octet plus data); -1 when `i` is
/// out of range. Complexity: O(1).
pub fn pgp_signature_subpacket_len(s: &PgpSignature, i: Int) -> Int {
  if i < 0 || i >= s.sub_len.len() {
    return -1;
  }
  let v: Int = s.sub_len[i];
  return v;
}

/// Copy of the content bytes of subpacket `i`, or an empty vector when `i`
/// is out of range. Complexity: O(len).
pub fn pgp_signature_subpacket_bytes(s: &PgpSignature, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= s.sub_len.len() || i >= s.sub_start.len() {
    return out;
  }
  let off: Int = s.sub_start[i];
  let len: Int = s.sub_len[i];
  if off < 0 || len < 0 || off + len > s.body.len() {
    return out;
  }
  var k = 0;
  while k < len {
    out.push(s.body[off + k]);
    k = k + 1;
  }
  return out;
}

/// Copy of the two left16 octets of `s` (empty when the signature is
/// malformed). Complexity: O(1).
pub fn pgp_signature_left16(s: &PgpSignature) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var k = 0;
  while k < s.left16.len() {
    out.push(s.left16[k]);
    k = k + 1;
  }
  return out;
}

// --------------------------------------------------
//  v4 key body
// --------------------------------------------------

// Public MPI count for a key algorithm: RSA 2, ElGamal 3, DSA 4,
// X9.42 DH 3, ECDH/ECDSA/EdDSA and the RFC 9580 native curves 1; -1 for an
// algorithm this package does not model.
fn _key_mpi_count(algo: Int) -> Int
  ensures: algo >= 1 && algo <= 3 => result == 2;
  ensures: algo == 16 || algo == 20 || algo == 21 => result == 3;
  ensures: algo == 17 => result == 4;
  ensures: algo == 18 || algo == 19 || algo == 22 || algo == 25 || algo == 26 || algo == 27 || algo == 28 => result == 1;
  ensures: result >= -1 && result <= 4;
{
  if algo == 1 || algo == 2 || algo == 3 {
    return 2;
  }
  if algo == 16 || algo == 20 {
    return 3;
  }
  if algo == 17 {
    return 4;
  }
  if algo == 21 {
    return 3;
  }
  if algo == 18 || algo == 19 || algo == 22 {
    return 1;
  }
  if algo == 25 || algo == 26 || algo == 27 || algo == 28 {
    return 1;
  }
  return -1;
}

// True for the curve algorithms whose v4 body carries a one-octet-length
// curve OID before the point MPI (RFC 4880 ECDH/ECDSA/EdDSA).
fn _key_has_oid(algo: Int) -> Bool {
  if algo == 18 || algo == 19 || algo == 22 {
    return true;
  }
  return false;
}

/// Decode a v4 key body.
///
/// Params: body - the key packet body bytes (public part plus, for a
/// Secret-Key packet, any secret material that is left unparsed).
/// Returns: Ok(key) with version, creation time, algorithm and every public
/// MPI; for ECDH/ECDSA/EdDSA the curve OID range is recorded and
/// `public_end` marks the offset one past the public material.
/// Error case: Err("pgp: truncated key at offset N"), Err("pgp: unsupported
/// key version N at offset 0"), Err("pgp: unsupported key algorithm N at
/// offset 5"), Err("pgp: bad curve OID at offset N") and the MPI errors
/// from pgp_mpi_decode (already offset-carrying).
/// Complexity: O(body.len()).
pub fn pgp_key_v4_decode(body: &Vec[UInt8]) -> Result[PgpKey, Str] {
  let n = body.len();
  if n < 1 {
    return _err_key("pgp: truncated key at offset 0");
  }
  let version = _vb(body, 0);
  if version != 4 {
    return _err_key("pgp: unsupported key version " + _itos(version) + " at offset 0");
  }
  if n < 5 {
    return _err_key("pgp: truncated key at offset 1");
  }
  if n < 6 {
    return _err_key("pgp: truncated key at offset 5");
  }
  let created = _uint32(body, 1);
  let algo = _vb(body, 5);
  let count = _key_mpi_count(algo);
  if count < 0 {
    return _err_key("pgp: unsupported key algorithm " + _itos(algo) + " at offset 5");
  }
  var oid_start = 0;
  var oid_len = 0;
  var pos = 6;
  if _key_has_oid(algo) {
    if pos >= n {
      return _err_key("pgp: truncated key at offset " + _itos(pos));
    }
    oid_len = _vb(body, pos);
    if oid_len < 1 {
      return _err_key("pgp: bad curve OID at offset " + _itos(pos));
    }
    pos = pos + 1;
    if pos + oid_len > n {
      return _err_key("pgp: truncated key at offset " + _itos(pos));
    }
    oid_start = pos;
    pos = pos + oid_len;
  }
  var mpi_start = Vec[Int].new();
  var mpi_bits = Vec[Int].new();
  var mpi_value_len = Vec[Int].new();
  var k = 0;
  while k < count {
    let r = pgp_mpi_decode(body, pos);
    if !r.is_ok {
      return _err_key(r.error);
    }
    let m: PgpMpi = r.value;
    mpi_start.push(pos);
    mpi_bits.push(m.bits);
    mpi_value_len.push(m.value_len);
    pos = m.next;
    k = k + 1;
  }
  var bcopy = Vec[UInt8].new();
  k = 0;
  while k < n {
    bcopy.push(body[k]);
    k = k + 1;
  }
  let key = PgpKey{
    body: bcopy;
    version: version;
    created: created;
    algo: algo;
    oid_start: oid_start;
    oid_len: oid_len;
    mpi_start: mpi_start;
    mpi_bits: mpi_bits;
    mpi_value_len: mpi_value_len;
    public_end: pos;
  };
  return _ok_key(key);
}

/// Key version stored in `k`. Complexity: O(1).
pub fn pgp_key_version(k: &PgpKey) -> Int {
  let v: Int = k.version;
  return v;
}

/// Creation time of `k` (32-bit unsigned seconds). Complexity: O(1).
pub fn pgp_key_created(k: &PgpKey) -> Int {
  let v: Int = k.created;
  return v;
}

/// Public-key algorithm of `k`. Complexity: O(1).
pub fn pgp_key_algo(k: &PgpKey) -> Int {
  let v: Int = k.algo;
  return v;
}

/// Number of public MPIs in `k`. Complexity: O(1).
pub fn pgp_key_mpi_count(k: &PgpKey) -> Int {
  return k.mpi_bits.len();
}

/// Declared bit count of MPI `i` of `k`; -1 when `i` is out of range.
/// Complexity: O(1).
pub fn pgp_key_mpi_bits(k: &PgpKey, i: Int) -> Int {
  if i < 0 || i >= k.mpi_bits.len() {
    return -1;
  }
  let v: Int = k.mpi_bits[i];
  return v;
}

/// Value length in octets of MPI `i` of `k`; -1 when `i` is out of range.
/// Complexity: O(1).
pub fn pgp_key_mpi_value_len(k: &PgpKey, i: Int) -> Int {
  if i < 0 || i >= k.mpi_value_len.len() {
    return -1;
  }
  let v: Int = k.mpi_value_len[i];
  return v;
}

/// Copy of the value octets of MPI `i` of `k`, or an empty vector when `i`
/// is out of range. Complexity: O(len).
pub fn pgp_key_mpi_value_bytes(k: &PgpKey, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= k.mpi_start.len() || i >= k.mpi_value_len.len() {
    return out;
  }
  let s: Int = k.mpi_start[i] + 2;
  let len: Int = k.mpi_value_len[i];
  if s < 0 || len < 0 || s + len > k.body.len() {
    return out;
  }
  var j = 0;
  while j < len {
    out.push(k.body[s + j]);
    j = j + 1;
  }
  return out;
}

/// Curve OID length of `k` (0 when the algorithm carries no OID).
/// Complexity: O(1).
pub fn pgp_key_oid_len(k: &PgpKey) -> Int {
  let v: Int = k.oid_len;
  if v < 0 {
    return 0;
  }
  return v;
}

/// Copy of the curve OID octets of `k`, or an empty vector when there is
/// none. Complexity: O(len).
pub fn pgp_key_oid_bytes(k: &PgpKey) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let s: Int = k.oid_start;
  let len: Int = k.oid_len;
  if s < 0 || len < 1 || s + len > k.body.len() {
    return out;
  }
  var j = 0;
  while j < len {
    out.push(k.body[s + j]);
    j = j + 1;
  }
  return out;
}

/// Offset one past the public key material of `k`. Complexity: O(1).
pub fn pgp_key_public_end(k: &PgpKey) -> Int {
  let v: Int = k.public_end;
  return v;
}

// --------------------------------------------------
//  ASCII armor: labels, base64 and CRC24
// --------------------------------------------------

/// The RFC 4648 standard base64 alphabet (64 characters), used by ASCII
/// armor.
/// Complexity: O(1).
pub fn pgp_base64_alphabet() -> Str {
  return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
}

/// The canonical armor label of a PGP message block ("PGP MESSAGE").
/// Complexity: O(1).
pub fn pgp_armor_label_message() -> Str {
  return "PGP MESSAGE";
}

/// The canonical armor label of a public key block
/// ("PGP PUBLIC KEY BLOCK").
/// Complexity: O(1).
pub fn pgp_armor_label_public_key() -> Str {
  return "PGP PUBLIC KEY BLOCK";
}

/// The canonical armor label of a private key block
/// ("PGP PRIVATE KEY BLOCK").
/// Complexity: O(1).
pub fn pgp_armor_label_private_key() -> Str {
  return "PGP PRIVATE KEY BLOCK";
}

/// The canonical armor label of a detached signature block
/// ("PGP SIGNATURE").
/// Complexity: O(1).
pub fn pgp_armor_label_signature() -> Str {
  return "PGP SIGNATURE";
}

/// The canonical armor body line width: 64.
/// Complexity: O(1).
pub fn pgp_armor_line_width() -> Int {
  return PGP_ARMOR_LINE_WIDTH;
}

/// CRC24 of `data` with the OpenPGP parameters: polynomial 0x1864CFB,
/// initial value 0xB704CE, no final xor (CRC-24/OPENPGP).
///
/// Params: data - the bytes to checksum.
/// Returns: the 24-bit checksum (0..16777215). The check value of
/// "123456789" is 0x21CF02.
/// Complexity: O(data.len()).
pub fn pgp_crc24(data: &Vec[UInt8]) -> Int
  ensures: data.len() == 0 => result == 11994318;
  ensures: result >= 0 && result <= 16777215;
{
  var crc = 11994318;
  var i = 0;
  while i < data.len() {
    let b = _vb(data, i);
    crc = crc ^ (b * 65536);
    var k = 0;
    while k < 8 {
      crc = crc * 2;
      if crc >= 16777216 {
        crc = crc ^ 25578747;
      }
      k = k + 1;
    }
    crc = crc % 16777216;
    i = i + 1;
  }
  return crc;
}

// Base64 digit value (0..63) of one encoded byte; -1 when the byte is not
// an alphabet character. '=' is handled by the caller.
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

// Decode the concatenated armor base64 characters. The length must be a
// multiple of 4; '=' may appear only in the final run, with the exact count
// implied by the remainder, and the unused low bits of a padded final group
// must be zero. Empty input decodes to empty bytes.
fn _b64_decode(chars: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let n = chars.len();
  if n == 0 {
    return _ok_bytes(out);
  }
  if n % 4 != 0 {
    return _err_bytes("pgp: armor bad padding");
  }
  var first_pad = -1;
  var k = 0;
  while k < n {
    let b = _vb(chars, k);
    if b == 61 {
      first_pad = k;
      break;
    }
    if _b64_value(b) < 0 {
      return _err_bytes("pgp: armor invalid base64 character");
    }
    k = k + 1;
  }
  var d = n;
  if first_pad >= 0 {
    d = first_pad;
    var j = first_pad;
    while j < n {
      if _vb(chars, j) != 61 {
        return _err_bytes("pgp: armor bad padding");
      }
      j = j + 1;
    }
    let p = n - d;
    if p > 2 {
      return _err_bytes("pgp: armor bad padding");
    }
    if p == 1 && d % 4 != 3 {
      return _err_bytes("pgp: armor bad padding");
    }
    if p == 2 && d % 4 != 2 {
      return _err_bytes("pgp: armor bad padding");
    }
  }
  var acc = 0;
  var count = 0;
  k = 0;
  while k < d {
    acc = acc * 64 + _b64_value(_vb(chars, k));
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
      return _err_bytes("pgp: armor non-canonical trailing bits");
    }
    out.push((acc / 16) as UInt8);
  } elif count == 3 {
    if acc % 4 != 0 {
      return _err_bytes("pgp: armor non-canonical trailing bits");
    }
    out.push((acc / 1024) as UInt8);
    out.push(((acc / 4) % 256) as UInt8);
  } elif count != 0 {
    return _err_bytes("pgp: armor bad padding");
  }
  return _ok_bytes(out);
}

// Emit the bytes of `src` as canonical armor base64 into `out`: 4 characters
// per 3-byte group, '=' padded final group, LF after every
// PGP_ARMOR_LINE_WIDTH characters and after a non-empty final partial line.
fn _b64_emit(src: &Vec[UInt8], out: &mut Vec[UInt8]) {
  let alpha = pgp_base64_alphabet();
  let len = src.len();
  var col = 0;
  var i = 0;
  while i + 3 <= len {
    let b0 = _vb(src, i);
    let b1 = _vb(src, i + 1);
    let b2 = _vb(src, i + 2);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1 / 16));
    out.push(string.byte_at(alpha, (b1 % 16) * 4 + b2 / 64));
    out.push(string.byte_at(alpha, b2 % 64));
    col = col + 4;
    if col == PGP_ARMOR_LINE_WIDTH {
      out.push(10 as UInt8);
      col = 0;
    }
    i = i + 3;
  }
  let rem = len - i;
  if rem == 1 {
    let b0 = _vb(src, i);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16));
    out.push(61 as UInt8);
    out.push(61 as UInt8);
    col = col + 4;
  } elif rem == 2 {
    let b0 = _vb(src, i);
    let b1 = _vb(src, i + 1);
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

// Append the four base64 characters of a 24-bit CRC value.
fn _push_crc4(out: &mut Vec[UInt8], crc: Int) {
  let alpha = pgp_base64_alphabet();
  out.push(string.byte_at(alpha, crc / 262144));
  out.push(string.byte_at(alpha, (crc / 4096) % 64));
  out.push(string.byte_at(alpha, (crc / 64) % 64));
  out.push(string.byte_at(alpha, crc % 64));
}

// True for a label character: printable US-ASCII except space and
// hyphen-minus.
fn _labelchar(b: Int) -> Bool {
  if b >= 33 && b <= 44 {
    return true;
  }
  if b >= 46 && b <= 126 {
    return true;
  }
  return false;
}

// True when the bytes [ls, le) form a valid armor label: 1..PGP_MAX_LABEL
// labelchar bytes with single interior spaces as separators.
fn _label_ok_at(text: Str, ls: Int, le: Int) -> Bool {
  let ln = le - ls;
  if ln < 1 || ln > PGP_MAX_LABEL {
    return false;
  }
  var i = ls;
  while i < le {
    let b = _tb(text, i);
    if b == 32 {
      if i == ls || i + 1 >= le {
        return false;
      }
      if _tb(text, i - 1) == 32 || _tb(text, i + 1) == 32 {
        return false;
      }
    } elif !_labelchar(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the line [start, end) begins with five hyphen-minuses.
fn _dash5(text: Str, start: Int) -> Bool {
  var i = 0;
  while i < 5 {
    if _tb(text, start + i) != 45 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Classify a line [start, end): 0 = not a marker-like line, 1 = valid BEGIN
// marker, 2 = valid END marker, -1 = malformed marker.
fn _marker_kind(text: Str, start: Int, end: Int) -> Int {
  if end - start < 5 {
    return 0;
  }
  if !_dash5(text, start) {
    return 0;
  }
  if end - start < 15 {
    return -1;
  }
  let w0 = _tb(text, start + 5);
  let w1 = _tb(text, start + 6);
  let w2 = _tb(text, start + 7);
  var label_start = -1;
  if w0 == 66 && w1 == 69 && w2 == 71 {
    if _tb(text, start + 8) != 73 || _tb(text, start + 9) != 78 {
      return -1;
    }
    if _tb(text, start + 10) != 32 {
      return -1;
    }
    label_start = start + 11;
  } elif w0 == 69 && w1 == 78 && w2 == 68 {
    if _tb(text, start + 8) != 32 {
      return -1;
    }
    label_start = start + 9;
  } else {
    return -1;
  }
  var k = end - 5;
  while k < end {
    if _tb(text, k) != 45 {
      return -1;
    }
    k = k + 1;
  }
  if !_label_ok_at(text, label_start, end - 5) {
    return -1;
  }
  if label_start == start + 11 {
    return 1;
  }
  return 2;
}

// The label of a valid BEGIN marker line [start, end).
fn _begin_label(text: Str, start: Int, end: Int) -> Str {
  return string.str_slice(text, start + 11, end - 5);
}

// The label of a valid END marker line [start, end).
fn _end_label(text: Str, start: Int, end: Int) -> Str {
  return string.str_slice(text, start + 9, end - 5);
}

// True when the line [start, end) has `Name: value` armor header shape.
fn _is_header_line(text: Str, start: Int, end: Int) -> Bool {
  if end - start < 2 {
    return false;
  }
  var colon = -1;
  var i = start;
  while i < end {
    if _tb(text, i) == 58 {
      colon = i;
      break;
    }
    i = i + 1;
  }
  if colon < 0 || colon == start {
    return false;
  }
  i = start;
  while i < colon {
    let b = _tb(text, i);
    if b < 33 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  i = colon + 1;
  while i < end {
    let b = _tb(text, i);
    if b < 32 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  ASCII armor: decode, encode, accessors
// --------------------------------------------------

/// Parse one ASCII-armored OpenPGP block.
///
/// Params: text - the armor text.
/// Returns: Ok(armor) after the matching END line; empty lines outside the
/// block are ignored, a line without a terminator is accepted, and one CR
/// immediately before an LF is removed. Headers are raw `Name: value` lines
/// before the blank separator; the body is base64; an optional checksum line
/// is `=` followed by four base64 characters and is validated against
/// pgp_crc24. `has_crc` records whether the input carried one.
/// Error case: Err("pgp: armor ...") on the first violation: no block
/// found, malformed block marker, nested block not allowed, text outside
/// blocks, label mismatch, unterminated block, header section not
/// terminated, blank line in body, header after body, invalid base64
/// character, bad padding, non-canonical trailing bits, bad checksum line,
/// checksum mismatch, text after checksum, bad body line length.
/// Complexity: O(text.len()).
pub fn pgp_armor_decode(text: Str) -> Result[PgpArmor, Str]
  ensures: text.len() == 0 => result is Err;
  ensures: result is Ok => text.len() > 0;
{
  let n = text.len();
  var pos = 0;
  var in_block = 0;
  var done = 0;
  var label: Str = "";
  var headers = Vec[Str].new();
  var header_count = 0;
  var body_started = 0;
  var crc_seen = 0;
  var crc = 0;
  var has_crc = 0;
  var chars = Vec[UInt8].new();
  var out_data = Vec[UInt8].new();

  while pos < n {
    let e = _line_end(text, pos);
    var ce = e;
    if ce > pos && _tb(text, ce - 1) == 13 {
      ce = ce - 1;
    }
    if in_block == 0 {
      if ce > pos {
        if done == 1 {
          return _err_armor("pgp: armor text outside blocks");
        }
        let kind = _marker_kind(text, pos, ce);
        if kind == 1 {
          in_block = 1;
          label = _begin_label(text, pos, ce);
          header_count = 0;
          body_started = 0;
          crc_seen = 0;
          crc = 0;
          has_crc = 0;
          chars = Vec[UInt8].new();
        } elif kind == -1 {
          return _err_armor("pgp: armor malformed block marker");
        } else {
          return _err_armor("pgp: armor text outside blocks");
        }
      }
    } else {
      let kind = _marker_kind(text, pos, ce);
      if kind == 2 {
        let elabel: Str = _end_label(text, pos, ce);
        if !_str_eq(label, elabel) {
          return _err_armor("pgp: armor label mismatch");
        }
        if header_count > 0 && body_started == 0 {
          return _err_armor("pgp: armor header section not terminated");
        }
        let dec = _b64_decode(&chars);
        if !dec.is_ok {
          return _err_armor(dec.error);
        }
        out_data = dec.value;
        if has_crc == 1 {
          let want = pgp_crc24(&out_data);
          if want != crc {
            return _err_armor("pgp: armor checksum mismatch");
          }
        }
        done = 1;
        in_block = 0;
      } elif kind == 1 {
        return _err_armor("pgp: armor nested block not allowed");
      } elif kind == -1 {
        return _err_armor("pgp: armor malformed block marker");
      } elif ce == pos {
        if body_started == 0 {
          body_started = 1;
        } else {
          return _err_armor("pgp: armor blank line in body");
        }
      } elif body_started == 0 && _is_header_line(text, pos, ce) {
        let hl: Str = string.str_slice(text, pos, ce);
        headers.push(hl);
        header_count = header_count + 1;
      } elif _tb(text, pos) == 61 {
        if crc_seen == 1 {
          return _err_armor("pgp: armor bad checksum line");
        }
        if ce - pos != 5 {
          return _err_armor("pgp: armor bad checksum line");
        }
        let v0 = _b64_value(_tb(text, pos + 1));
        let v1 = _b64_value(_tb(text, pos + 2));
        let v2 = _b64_value(_tb(text, pos + 3));
        let v3 = _b64_value(_tb(text, pos + 4));
        if v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0 {
          return _err_armor("pgp: armor bad checksum line");
        }
        crc = v0 * 262144 + v1 * 4096 + v2 * 64 + v3;
        has_crc = 1;
        crc_seen = 1;
      } else {
        if crc_seen == 1 {
          return _err_armor("pgp: armor text after checksum");
        }
        if body_started == 0 && header_count > 0 {
          return _err_armor("pgp: armor header section not terminated");
        }
        if body_started == 1 && _is_header_line(text, pos, ce) {
          return _err_armor("pgp: armor header after body");
        }
        body_started = 1;
        if ce - pos > 76 {
          return _err_armor("pgp: armor bad body line length");
        }
        var k = pos;
        while k < ce {
          let b = _tb(text, k);
          if b != 61 && _b64_value(b) < 0 {
            return _err_armor("pgp: armor invalid base64 character");
          }
          chars.push(b as UInt8);
          k = k + 1;
        }
      }
    }
    pos = e + 1;
  }

  if done == 1 {
    let a = PgpArmor{
      label: label;
      headers: headers;
      data: out_data;
      crc: crc;
      has_crc: has_crc;
    };
    return _ok_armor(a);
  }
  if in_block == 1 {
    return _err_armor("pgp: armor unterminated block");
  }
  return _err_armor("pgp: armor no block found");
}

/// Emit the canonical ASCII armor of `a`.
///
/// Params: a - an armor block, normally one returned by pgp_armor_decode.
/// Returns: Ok(text) with the BEGIN line, every stored header line, one
/// blank line, the payload as canonical base64 wrapped at exactly 64
/// characters per line (LF endings, no line for an empty payload), a
/// checksum line `=` + four characters with the CRC24 of the payload, the
/// END line and one trailing LF. The checksum is always emitted; `has_crc`
/// and `crc` are ignored on encode.
/// Error case: Err("pgp: armor invalid label") when the stored label fails
/// the label grammar; Err("pgp: armor bad header line") when a stored header
/// lacks `Name: value` shape.
/// Complexity: O(header + data bytes).
pub fn pgp_armor_encode(a: &PgpArmor) -> Result[Str, Str]
  ensures: a.label.len() == 0 => result is Err;
  ensures: a.label.len() > 64 => result is Err;
{
  let lb: Str = a.label;
  if !_label_ok_at(lb, 0, lb.len()) {
    return _err_str("pgp: armor invalid label");
  }
  let hc = a.headers.len();
  var j = 0;
  while j < hc {
    let hl: Str = a.headers[j];
    if !_is_header_line(hl, 0, hl.len()) {
      return _err_str("pgp: armor bad header line");
    }
    j = j + 1;
  }
  var payload = Vec[UInt8].new();
  j = 0;
  while j < a.data.len() {
    payload.push(a.data[j]);
    j = j + 1;
  }
  var out = Vec[UInt8].new();
  _push_str(&mut out, "-----BEGIN ");
  _push_str(&mut out, lb);
  _push_str(&mut out, "-----");
  out.push(10 as UInt8);
  j = 0;
  while j < hc {
    let hl: Str = a.headers[j];
    _push_str(&mut out, hl);
    out.push(10 as UInt8);
    j = j + 1;
  }
  out.push(10 as UInt8);
  _b64_emit(&payload, &mut out);
  let crc = pgp_crc24(&payload);
  out.push(61 as UInt8);
  _push_crc4(&mut out, crc);
  out.push(10 as UInt8);
  _push_str(&mut out, "-----END ");
  _push_str(&mut out, lb);
  _push_str(&mut out, "-----");
  out.push(10 as UInt8);
  let text: Str = builder.sb_to_str(&out);
  return _ok_str(text);
}

/// Armor label of `a`. The result is a Str: compare it with
/// xiom.string.compare.str_compare. Complexity: O(1).
pub fn pgp_armor_label(a: &PgpArmor) -> Str {
  let lb: Str = a.label;
  return lb;
}

/// Number of stored armor header lines in `a`. Complexity: O(1).
pub fn pgp_armor_header_count(a: &PgpArmor) -> Int {
  return a.headers.len();
}

/// Raw armor header line `j` of `a`, or "" when `j` is out of range. The
/// result is a Str read from a Vec[Str]: compare it with
/// xiom.string.compare.str_compare. Complexity: O(1).
pub fn pgp_armor_header_line(a: &PgpArmor, j: Int) -> Str {
  if j < 0 || j >= a.headers.len() {
    return "";
  }
  let hl: Str = a.headers[j];
  return hl;
}

/// Decoded payload length in bytes of `a`. Complexity: O(1).
pub fn pgp_armor_payload_len(a: &PgpArmor) -> Int {
  return a.data.len();
}

/// Copy of the decoded payload bytes of `a`. Complexity: O(len).
pub fn pgp_armor_payload(a: &PgpArmor) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var k = 0;
  while k < a.data.len() {
    out.push(a.data[k]);
    k = k + 1;
  }
  return out;
}

/// Stored CRC24 of `a` (meaningful when pgp_armor_has_crc is 1).
/// Complexity: O(1).
pub fn pgp_armor_crc(a: &PgpArmor) -> Int {
  let v: Int = a.crc;
  return v;
}

/// 1 when the decoded armor carried a checksum line, 0 otherwise.
/// Complexity: O(1).
pub fn pgp_armor_has_crc(a: &PgpArmor) -> Int {
  let v: Int = a.has_crc;
  return v;
}

// --------------------------------------------------
//  User ID packets and structural key binding
// --------------------------------------------------

/// Decode the body of User ID packet `i` as printable text.
///
/// Params: d - a document; i - a packet index.
/// Returns: Ok(text) when packet `i` is a User ID packet whose body is
/// non-empty and free of control bytes (bytes below 0x20 and DEL 0x7F are
/// rejected; bytes >= 0x80 are accepted as UTF-8 text and are not
/// validated).
/// Error case: Err("pgp: not a user id packet") when `i` is out of range or
/// names another tag; Err("pgp: user id is empty") for an empty body;
/// Err("pgp: user id has a non-printable byte at offset N") otherwise.
/// Complexity: O(body.len()).
pub fn pgp_user_id_text(d: &PgpDocument, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= d.tag.len() {
    return _err_str("pgp: not a user id packet");
  }
  let t: Int = d.tag[i];
  if t != 13 {
    return _err_str("pgp: not a user id packet");
  }
  let body = pgp_packet_body(d, i);
  if body.len() == 0 {
    return _err_str("pgp: user id is empty");
  }
  var k = 0;
  while k < body.len() {
    let b = _vb(&body, k);
    if b < 32 || b == 127 {
      return _err_str("pgp: user id has a non-printable byte at offset " + _itos(k));
    }
    k = k + 1;
  }
  var out = Vec[UInt8].new();
  k = 0;
  while k < body.len() {
    out.push(body[k]);
    k = k + 1;
  }
  let s: Str = builder.sb_to_str(&out);
  return _ok_str(s);
}

/// Index of the nearest key packet before User ID packet `i`: the highest
/// `j < i` whose tag is Secret-Key 5, Public-Key 6 or Public-Subkey 14.
/// Returns -1 when `i` is not a User ID packet or no key packet precedes it.
/// This is the structural key-to-user-id binding; certification signatures
/// are not cryptographically verified by this package. Complexity: O(i).
pub fn pgp_user_id_key_index(d: &PgpDocument, i: Int) -> Int
  ensures: i < 0 || i >= d.tag.len() => result == -1;
  ensures: result != -1 => i >= 0 && i < d.tag.len();
{
  if i < 0 || i >= d.tag.len() {
    return -1;
  }
  let t: Int = d.tag[i];
  if t != 13 {
    return -1;
  }
  var j = i - 1;
  while j >= 0 {
    let tj: Int = d.tag[j];
    if tj == 5 || tj == 6 || tj == 14 {
      return j;
    }
    j = j - 1;
  }
  return -1;
}

/// Index of the binding signature of User ID packet `i`: the index of the
/// Signature packet immediately after it, or -1 when `i` is not a User ID
/// packet or the next packet is not a Signature. Complexity: O(1).
pub fn pgp_user_id_binding_signature(d: &PgpDocument, i: Int) -> Int {
  if i < 0 || i >= d.tag.len() {
    return -1;
  }
  let t: Int = d.tag[i];
  if t != 13 {
    return -1;
  }
  let j = i + 1;
  if j >= d.tag.len() {
    return -1;
  }
  let tj: Int = d.tag[j];
  if tj == 2 {
    return j;
  }
  return -1;
}


