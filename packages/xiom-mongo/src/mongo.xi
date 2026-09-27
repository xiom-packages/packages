// XIOM -- xiom.mongo: MongoDB BSON documents and wire-message framing
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no driver state) structural decoder for the
// MongoDB wire protocol and BSON. In scope:
//
//   * BSON documents (spec v1.1): int32 total length, element stream until
//     the 0x00 terminator, cstring keys, and every standard element type --
//     double (raw 8 LE bytes), string, embedded document, array, binary,
//     undefined, ObjectId (12 bytes), bool, UTC datetime (int64 ms), null,
//     regex, javascript, symbol, code-with-scope, int32, timestamp (raw
//     uint64), int64, decimal128 (16 opaque bytes), min-key and max-key --
//     with a nesting depth cap (`bson_max_depth()`).
//   * wire messages: the 16-byte header (int32 messageLength, requestID,
//     responseTo, opCode, all little-endian) followed by the opcode body.
//     OP_MSG (2013) decodes its flag word and both section kinds (kind 0
//     body document, kind 1 document sequence with an identifier);
//     OP_COMPRESSED (2012) decodes originalOpcode + uncompressedSize +
//     compressorId and preserves the compressed payload verbatim; the
//     legacy opcodes OP_QUERY (2004), OP_REPLY (1), OP_INSERT (2002),
//     OP_UPDATE (2001), OP_DELETE (2006), OP_GET_MORE (2005) and
//     OP_KILL_CURSORS (2007) decode their documented fields.
//   * one message per parse with a consumed-byte count, so callers can slice
//     concatenated messages out of a stream; unknown opcodes are preserved
//     raw instead of being rejected; truncation, bad lengths, malformed
//     section framing and malformed BSON are rejected with deterministic
//     Err(Str) messages that carry the byte offset (see SPEC.md).
//
// Non-goals: no BSON encoding, no query/command semantics, no driver, no
// sockets, no authentication, no compression/decompression (OP_COMPRESSED
// payloads stay opaque), no decimal128 value math, no double conversion
// (raw IEEE-754 bytes only; this module never uses Float64) and no
// validation of UTF-8 in BSON strings (payload bytes are opaque).
//
// v0.61.3 notes that shaped this module:
//   * free functions only; Ok/Err construction is confined to the tiny leaf
//     helpers below (constructing Results inside other functions
//     miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic or
//     comparisons; every Vec[Int] element read is bound to a typed local
//     first.
//   * `&struct.field` is never passed where a `&mut Vec[UInt8]` or
//     `&Vec[UInt8]` parameter is expected (that yields an empty vector);
//     ranges are copied into local vectors which are then moved into the
//     owning struct.
//   * little-endian words are decoded with arithmetic
//     (b0 + b1*256 + b2*65536 + b3*16777216), never shifts; two's-complement
//     sign extension is applied only after the unsigned word is exact.
//   * no indexed Vec[fn] dispatch: opcode selection is an if/elif chain.
//   * no Vec[Float64] and no Vec[StructType]: BSON tokens and message
//     scalars live in parallel Vec fields.

module xiom.mongo

use xiom.convert;
use xiom.string;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[BsonDoc, Str].
fn _ok_doc(v: BsonDoc) -> Result[BsonDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[BsonDoc, Str].
fn _err_doc(m: Str) -> Result[BsonDoc, Str] {
  return Err(m);
}

// Ok(v) for Result[MongoMsg, Str].
fn _ok_msg(v: MongoMsg) -> Result[MongoMsg, Str] {
  return Ok(v);
}

// Err(m) for Result[MongoMsg, Str].
fn _err_msg(m: Str) -> Result[MongoMsg, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Decoded BSON document: the source bytes plus a flat token stream.
///
/// Tokens are stored in depth-first pre-order in parallel vectors (one entry
/// per token). Token 0 is the root document container; `kind` holds one of
/// the `bson_kind_*` codes (BSON element type bytes 0x01..0x13 plus 0x7F,
/// 0xFF, and `bson_kind_root_document()` = 100 for a root or scope document
/// container).
///
/// For document and array containers, `first_child[i]` is the first direct
/// element token and `child_count[i]` the number of direct elements; each
/// direct child links to the next one through `next_sibling` (-1 on the
/// last child), because a child's own subtree occupies the tokens
/// immediately after it. For leaves, `first_child` is -1, `next_sibling` is
/// -1 and `child_count` is 0.
///
/// `start`/`end` delimit the whole element token on the wire (the type byte
/// through the end of the value; for containers, through the closing 0x00).
/// `key_start`/`key_end` delimit the element key bytes without the trailing
/// NUL (-1 when the token has no key: the root document and the scope
/// document of a code-with-scope value). `payload_start`/`payload_end`
/// delimit the value payload (string contents without the NUL; binary,
/// ObjectId and decimal128 bytes; the 4/8/16 raw integer bytes; the two
/// regex cstrings including their NULs; the code bytes of a
/// code-with-scope). `value` holds the parsed integer, boolean, declared
/// length, ObjectId/binary length, or the low 32 raw bits of doubles and
/// timestamps; `aux` holds the second 32 raw bits of doubles and timestamps
/// and the binary subtype byte.
///
/// Fields are implementation details; callers should use the free accessors
/// below. Documents are only produced by `bson_parse_document` and
/// `mongo_parse_message`, so the token stream always satisfies the format
/// invariants.
pub type BsonDoc = {
  data: Vec[UInt8];
  kind: Vec[Int];
  parent: Vec[Int];
  first_child: Vec[Int];
  child_count: Vec[Int];
  next_sibling: Vec[Int];
  start: Vec[Int];
  end: Vec[Int];
  key_start: Vec[Int];
  key_end: Vec[Int];
  payload_start: Vec[Int];
  payload_end: Vec[Int];
  value: Vec[Int];
  aux: Vec[Int];
}

/// Decoded wire message: the header scalars, the opcode-specific fields and
/// the BSON documents found in the body.
///
/// `docs` holds one shared token stream over the whole message buffer;
/// `doc_roots` lists the token index of every top-level document in order of
/// appearance (OP_MSG: body document then document-sequence documents;
/// OP_QUERY: query then optional return-fields selector; OP_REPLY: the
/// returned documents; OP_INSERT: the inserted documents; OP_UPDATE:
/// selector then update; OP_DELETE: the selector). Fields that do not apply
/// to the parsed opcode keep -1 (scalars) or an empty vector.
///
/// `sec_kind`/`sec_start`/`sec_end`/`sec_ident` describe OP_MSG sections
/// (kind 0 body, kind 1 document sequence); `payload` carries the opaque
/// body of an unknown opcode or of OP_COMPRESSED; `cursor_ids` lists the
/// OP_KILL_CURSORS cursor IDs. Fields are implementation details; callers
/// should use the free accessors below.
pub type MongoMsg = {
  data: Vec[UInt8];
  message_length: Int;
  request_id: Int;
  response_to: Int;
  opcode: Int;
  body_start: Int;
  body_end: Int;
  flags: Int;
  number_to_skip: Int;
  number_to_return: Int;
  cursor_id: Int;
  starting_from: Int;
  number_returned: Int;
  zero: Int;
  cursor_count: Int;
  namespace: Vec[UInt8];
  orig_opcode: Int;
  uncompressed_size: Int;
  compressor_id: Int;
  payload: Vec[UInt8];
  cursor_ids: Vec[Int];
  docs: BsonDoc;
  doc_roots: Vec[Int];
  body_doc: Int;
  sec_kind: Vec[Int];
  sec_start: Vec[Int];
  sec_end: Vec[Int];
  sec_ident: Vec[Vec[UInt8]];
}

// Internal mutable BSON state: the token vectors plus the cursor. `limit` is
// the exclusive upper bound of the region being parsed (the whole buffer for
// `bson_parse_document`, the message or section end for wire parsing).
type _BsonParser = {
  data: Vec[UInt8];
  limit: Int;
  pos: Int;
  kind: Vec[Int];
  parent: Vec[Int];
  first_child: Vec[Int];
  child_count: Vec[Int];
  next_sibling: Vec[Int];
  start: Vec[Int];
  end: Vec[Int];
  key_start: Vec[Int];
  key_end: Vec[Int];
  payload_start: Vec[Int];
  payload_end: Vec[Int];
  value: Vec[Int];
  aux: Vec[Int];
}

// Internal mutable message state: the header scalars, opcode-specific
// scalars and the document-root / section tables. The BSON tokens live in
// the separate `_BsonParser` that travels alongside this state.
type _MsgParser = {
  message_length: Int;
  request_id: Int;
  response_to: Int;
  opcode: Int;
  body_start: Int;
  body_end: Int;
  flags: Int;
  number_to_skip: Int;
  number_to_return: Int;
  cursor_id: Int;
  starting_from: Int;
  number_returned: Int;
  zero: Int;
  cursor_count: Int;
  namespace: Vec[UInt8];
  orig_opcode: Int;
  uncompressed_size: Int;
  compressor_id: Int;
  payload: Vec[UInt8];
  cursor_ids: Vec[Int];
  doc_roots: Vec[Int];
  body_doc: Int;
  sec_kind: Vec[Int];
  sec_start: Vec[Int];
  sec_end: Vec[Int];
  sec_ident: Vec[Vec[UInt8]];
}

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Documented maximum BSON nesting depth. The top-level document has depth
/// 0; an embedded document or array at depth 100 is the deepest accepted
/// container, and a container at depth 101 is rejected with
/// `bson: nesting depth exceeds limit of 100 at <offset>`.
pub fn bson_max_depth() -> Int {
  return 100;
}

/// Wire-message header size in bytes.
pub fn mongo_header_size() -> Int {
  return 16;
}

/// Token kind code for a root or scope document container.
pub fn bson_kind_root_document() -> Int {
  return 100;
}

/// BSON element type 0x01: double (raw 8 little-endian IEEE-754 bytes).
pub fn bson_kind_double() -> Int {
  return 1;
}

/// BSON element type 0x02: UTF-8 string (int32 length including the NUL).
pub fn bson_kind_string() -> Int {
  return 2;
}

/// BSON element type 0x03: embedded document.
pub fn bson_kind_embedded_document() -> Int {
  return 3;
}

/// BSON element type 0x04: array (an embedded document with numeric keys).
pub fn bson_kind_array() -> Int {
  return 4;
}

/// BSON element type 0x05: binary (int32 length + subtype byte + bytes).
pub fn bson_kind_binary() -> Int {
  return 5;
}

/// BSON element type 0x06: undefined (deprecated, no payload).
pub fn bson_kind_undefined() -> Int {
  return 6;
}

/// BSON element type 0x07: ObjectId (12 bytes).
pub fn bson_kind_object_id() -> Int {
  return 7;
}

/// BSON element type 0x08: boolean (1 byte, 0 or 1).
pub fn bson_kind_bool() -> Int {
  return 8;
}

/// BSON element type 0x09: UTC datetime (int64 milliseconds).
pub fn bson_kind_datetime() -> Int {
  return 9;
}

/// BSON element type 0x0A: null (no payload).
pub fn bson_kind_null() -> Int {
  return 10;
}

/// BSON element type 0x0B: regex (cstring pattern + cstring options).
pub fn bson_kind_regex() -> Int {
  return 11;
}

/// BSON element type 0x0D: javascript code (string layout).
pub fn bson_kind_javascript() -> Int {
  return 13;
}

/// BSON element type 0x0E: symbol (string layout, deprecated).
pub fn bson_kind_symbol() -> Int {
  return 14;
}

/// BSON element type 0x0F: code with scope (int32 total length, code string,
/// scope document).
pub fn bson_kind_code_w_scope() -> Int {
  return 15;
}

/// BSON element type 0x10: int32.
pub fn bson_kind_int32() -> Int {
  return 16;
}

/// BSON element type 0x11: timestamp (raw uint64: low 32 increment, high 32
/// seconds).
pub fn bson_kind_timestamp() -> Int {
  return 17;
}

/// BSON element type 0x12: int64.
pub fn bson_kind_int64() -> Int {
  return 18;
}

/// BSON element type 0x13: decimal128 (16 opaque bytes).
pub fn bson_kind_decimal128() -> Int {
  return 19;
}

/// BSON element type 0xFF: min-key (no payload).
pub fn bson_kind_min_key() -> Int {
  return 255;
}

/// BSON element type 0x7F: max-key (no payload).
pub fn bson_kind_max_key() -> Int {
  return 127;
}

/// Opcode 1: legacy OP_REPLY.
pub fn mongo_op_reply() -> Int {
  return 1;
}

/// Opcode 2001: legacy OP_UPDATE.
pub fn mongo_op_update() -> Int {
  return 2001;
}

/// Opcode 2002: legacy OP_INSERT.
pub fn mongo_op_insert() -> Int {
  return 2002;
}

/// Opcode 2004: legacy OP_QUERY.
pub fn mongo_op_query() -> Int {
  return 2004;
}

/// Opcode 2005: legacy OP_GET_MORE.
pub fn mongo_op_get_more() -> Int {
  return 2005;
}

/// Opcode 2006: legacy OP_DELETE.
pub fn mongo_op_delete() -> Int {
  return 2006;
}

/// Opcode 2007: legacy OP_KILL_CURSORS.
pub fn mongo_op_kill_cursors() -> Int {
  return 2007;
}

/// Opcode 2012: OP_COMPRESSED.
pub fn mongo_op_compressed() -> Int {
  return 2012;
}

/// Opcode 2013: OP_MSG.
pub fn mongo_op_msg() -> Int {
  return 2013;
}

/// OP_MSG flagBits bit 0 (value 1): checksumPresent.
pub fn mongo_msg_flag_checksum_present() -> Int {
  return 1;
}

/// OP_MSG flagBits bit 1 (value 2): moreToCome.
pub fn mongo_msg_flag_more_to_come() -> Int {
  return 2;
}

/// OP_MSG flagBits bit 16 (value 65536): exhaustAllowed.
pub fn mongo_msg_flag_exhaust_allowed() -> Int {
  return 65536;
}

/// Human-readable name of a wire opcode, or "" when the opcode is not part
/// of this codec's known set (such messages are preserved raw).
pub fn mongo_opcode_name(op: Int) -> Str {
  if op == 1 {
    return "OP_REPLY";
  }
  if op == 2001 {
    return "OP_UPDATE";
  }
  if op == 2002 {
    return "OP_INSERT";
  }
  if op == 2004 {
    return "OP_QUERY";
  }
  if op == 2005 {
    return "OP_GET_MORE";
  }
  if op == 2006 {
    return "OP_DELETE";
  }
  if op == 2007 {
    return "OP_KILL_CURSORS";
  }
  if op == 2012 {
    return "OP_COMPRESSED";
  }
  if op == 2013 {
    return "OP_MSG";
  }
  return "";
}

/// Whether `op` is one of the opcodes this codec decodes structurally.
pub fn mongo_opcode_known(op: Int) -> Bool {
  if op == 1 {
    return true;
  }
  if op == 2001 {
    return true;
  }
  if op == 2002 {
    return true;
  }
  if op == 2004 {
    return true;
  }
  if op == 2005 {
    return true;
  }
  if op == 2006 {
    return true;
  }
  if op == 2007 {
    return true;
  }
  if op == 2012 {
    return true;
  }
  if op == 2013 {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Decimal rendering of a non-negative Int (used to build error offsets).
fn _s(n: Int) -> Str {
  return convert.int.int_to_string(n);
}

// Byte at absolute offset `off`, widened to 0..255. The caller guarantees
// `off` is inside the buffer.
fn _byte(p: &_BsonParser, off: Int) -> Int {
  return (p.data[off] as Int) & 0xFF;
}

// Little-endian unsigned 32-bit word at `off` (0..4294967295).
fn _read_u32(p: &_BsonParser, off: Int) -> Int {
  let b0 = _byte(p, off);
  let b1 = _byte(p, off + 1);
  let b2 = _byte(p, off + 2);
  let b3 = _byte(p, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Little-endian signed 32-bit word at `off`.
fn _read_i32(p: &_BsonParser, off: Int) -> Int {
  let u = _read_u32(p, off);
  if u > 2147483647 {
    return u - 4294967296;
  }
  return u;
}

// Little-endian signed 64-bit word at `off`, exact for the whole signed
// 64-bit range: low 32 bits unsigned + high 32 bits signed * 2^32.
fn _read_i64(p: &_BsonParser, off: Int) -> Int {
  let lo = _read_u32(p, off);
  let hi = _read_u32(p, off + 4);
  if hi > 2147483647 {
    return lo + (hi - 4294967296) * 4294967296;
  }
  return lo + hi * 4294967296;
}

// Offset of the first NUL byte at or after `start`, scanning strictly below
// `limit`; -1 when no NUL is present.
fn _scan_cstring(p: &_BsonParser, start: Int, limit: Int) -> Int {
  var i = start;
  while i < limit {
    if _byte(p, i) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Copy bytes [from, to) of the parser buffer into `out`.
fn _push_range(out: &mut Vec[UInt8], p: &_BsonParser, from: Int, to: Int) {
  var i = from;
  while i < to {
    out.push(p.data[i]);
    i = i + 1;
  }
}

// The truncated-value message for an element that starts at `tpos`.
fn _trunc(tpos: Int) -> Str {
  return "bson: truncated element at " + _s(tpos);
}

// --------------------------------------------------
//  Token bookkeeping
// --------------------------------------------------

// Append a placeholder token (kind, parent, start) returning its index; all
// other fields get neutral defaults. Every parallel vector is pushed
// exactly once.
fn _push_token(p: &mut _BsonParser, kind: Int, parent: Int, start: Int) -> Int {
  let idx = p.kind.len();
  p.kind.push(kind);
  p.parent.push(parent);
  p.first_child.push(-1);
  p.child_count.push(0);
  p.next_sibling.push(-1);
  p.start.push(start);
  p.end.push(start);
  p.key_start.push(-1);
  p.key_end.push(-1);
  p.payload_start.push(start);
  p.payload_end.push(start);
  p.value.push(0);
  p.aux.push(0);
  return idx;
}

// Move the parser's token vectors into the public document type, dropping
// the cursor.
fn _finish_doc(p: _BsonParser) -> BsonDoc {
  let data: Vec[UInt8] = p.data;
  let kind: Vec[Int] = p.kind;
  let parent: Vec[Int] = p.parent;
  let first_child: Vec[Int] = p.first_child;
  let child_count: Vec[Int] = p.child_count;
  let next_sibling: Vec[Int] = p.next_sibling;
  let start: Vec[Int] = p.start;
  let end: Vec[Int] = p.end;
  let key_start: Vec[Int] = p.key_start;
  let key_end: Vec[Int] = p.key_end;
  let payload_start: Vec[Int] = p.payload_start;
  let payload_end: Vec[Int] = p.payload_end;
  let value: Vec[Int] = p.value;
  let aux: Vec[Int] = p.aux;
  return BsonDoc{
    data: data;
    kind: kind;
    parent: parent;
    first_child: first_child;
    child_count: child_count;
    next_sibling: next_sibling;
    start: start;
    end: end;
    key_start: key_start;
    key_end: key_end;
    payload_start: payload_start;
    payload_end: payload_end;
    value: value;
    aux: aux;
  };
}

// Fresh BSON parser over `data` with the cursor at 0 and `limit` set to the
// buffer length.
fn _new_bson_parser(data: Vec[UInt8]) -> _BsonParser {
  let limit = data.len();
  return _BsonParser{
    data: data;
    limit: limit;
    pos: 0;
    kind: Vec[Int].new();
    parent: Vec[Int].new();
    first_child: Vec[Int].new();
    child_count: Vec[Int].new();
    next_sibling: Vec[Int].new();
    start: Vec[Int].new();
    end: Vec[Int].new();
    key_start: Vec[Int].new();
    key_end: Vec[Int].new();
    payload_start: Vec[Int].new();
    payload_end: Vec[Int].new();
    value: Vec[Int].new();
    aux: Vec[Int].new();
  };
}

// Fresh message state with every not-applicable scalar at -1 and every
// table empty.
fn _new_msg_parser() -> _MsgParser {
  return _MsgParser{
    message_length: 0;
    request_id: 0;
    response_to: 0;
    opcode: 0;
    body_start: 0;
    body_end: 0;
    flags: -1;
    number_to_skip: -1;
    number_to_return: -1;
    cursor_id: -1;
    starting_from: -1;
    number_returned: -1;
    zero: -1;
    cursor_count: -1;
    namespace: Vec[UInt8].new();
    orig_opcode: -1;
    uncompressed_size: -1;
    compressor_id: -1;
    payload: Vec[UInt8].new();
    cursor_ids: Vec[Int].new();
    doc_roots: Vec[Int].new();
    body_doc: -1;
    sec_kind: Vec[Int].new();
    sec_start: Vec[Int].new();
    sec_end: Vec[Int].new();
    sec_ident: Vec[Vec[UInt8]].new();
  };
}

// --------------------------------------------------
//  BSON decoder
// --------------------------------------------------

// Parse a document container whose length field starts at `at`, bounded by
// `limit`: read and validate the int32 length, create the token (kind 100
// for a root or scope document, or the element's 0x03/0x04 kind), then parse
// the element stream.
fn _parse_document_into(p: &mut _BsonParser, tok: Int, depth: Int, doc_kind: Int, at: Int, limit: Int) -> Result[Int, Str] {
  if depth > bson_max_depth() {
    return _err_int("bson: nesting depth exceeds limit of 100 at " + _s(at));
  }
  if at + 4 > limit {
    return _err_int("bson: truncated document at " + _s(at));
  }
  let len = _read_i32(p, at);
  if len < 5 {
    return _err_int("bson: bad document length " + _s(len) + " at " + _s(at));
  }
  let doc_end = at + len;
  if doc_end > limit {
    return _err_int("bson: truncated document at " + _s(at));
  }
  p.kind[tok] = doc_kind;
  p.payload_start[tok] = at;
  p.payload_end[tok] = doc_end;
  p.value[tok] = len;
  p.pos = at + 4;
  return _parse_doc_body(p, depth, tok, doc_end);
}

// Parse the element stream of a document token `tok` that ends at `doc_end`
// (exclusive; the byte at doc_end - 1 must be the 0x00 terminator). Elements
// are appended as children of `tok` in document order.
fn _parse_doc_body(p: &mut _BsonParser, depth: Int, tok: Int, doc_end: Int) -> Result[Int, Str] {
  var count = 0;
  var first = -1;
  var prev = -1;
  var done = 0;
  while done == 0 {
    if p.pos >= doc_end {
      return _err_int("bson: missing document terminator at " + _s(p.payload_start[tok]));
    }
    let t = _byte(p, p.pos);
    if t == 0 {
      if p.pos != doc_end - 1 {
        return _err_int("bson: bad document length at " + _s(p.payload_start[tok]));
      }
      p.pos = p.pos + 1;
      done = 1;
    } else {
      let el = _parse_element(p, depth + 1, tok, doc_end);
      if !el.is_ok {
        return _err_int(el.error);
      }
      if first == -1 {
        first = el.value;
      }
      if prev >= 0 {
        p.next_sibling[prev] = el.value;
      }
      prev = el.value;
      count = count + 1;
    }
  }
  p.first_child[tok] = first;
  p.child_count[tok] = count;
  p.end[tok] = p.pos;
  return _ok_int(tok);
}

// Parse one element: type byte, cstring key, then the typed value. `depth`
// is the depth of a container value of this element; `limit` is the
// enclosing document end.
fn _parse_element(p: &mut _BsonParser, depth: Int, parent: Int, limit: Int) -> Result[Int, Str] {
  let tpos = p.pos;
  let t = _byte(p, tpos);
  p.pos = tpos + 1;
  let kstart = p.pos;
  let kend = _scan_cstring(p, kstart, limit);
  if kend < 0 {
    return _err_int("bson: unterminated key at " + _s(kstart));
  }
  p.pos = kend + 1;
  let idx = _push_token(p, t, parent, tpos);
  p.key_start[idx] = kstart;
  p.key_end[idx] = kend;
  let vr = _parse_value(p, t, depth, idx, limit, tpos);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  p.end[idx] = p.pos;
  return _ok_int(idx);
}

// Write a string-layout value (types 0x02, 0x0D, 0x0E): int32 length
// including the trailing NUL, then the bytes ending in 0x00. The payload
// covers the content bytes without the NUL; `value` keeps the declared
// length.
fn _parse_string_value(p: &mut _BsonParser, tok: Int, tpos: Int, limit: Int) -> Result[Int, Str] {
  if p.pos + 4 > limit {
    return _err_int(_trunc(tpos));
  }
  let n = _read_i32(p, p.pos);
  if n < 1 {
    return _err_int("bson: bad string length " + _s(n) + " at " + _s(tpos));
  }
  if p.pos + 4 + n > limit {
    return _err_int("bson: truncated string at " + _s(tpos));
  }
  let content_end = p.pos + 4 + n - 1;
  if _byte(p, content_end) != 0 {
    return _err_int("bson: unterminated string at " + _s(tpos));
  }
  p.payload_start[tok] = p.pos + 4;
  p.payload_end[tok] = content_end;
  p.value[tok] = n;
  p.pos = content_end + 1;
  return _ok_int(tok);
}

// Parse the value of element token `tok` (kind `t`) at the cursor. `depth`
// is the container depth to use if the value is an embedded document or
// array; `limit` is the enclosing document end; `tpos` is the element's
// type-byte offset (used in error messages).
fn _parse_value(p: &mut _BsonParser, t: Int, depth: Int, tok: Int, limit: Int, tpos: Int) -> Result[Int, Str] {
  if t == 1 {
    if p.pos + 8 > limit {
      return _err_int(_trunc(tpos));
    }
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos + 8;
    p.value[tok] = _read_u32(p, p.pos);
    p.aux[tok] = _read_u32(p, p.pos + 4);
    p.pos = p.pos + 8;
    return _ok_int(tok);
  }
  if t == 2 {
    return _parse_string_value(p, tok, tpos, limit);
  }
  if t == 3 {
    let at3 = p.pos;
    return _parse_document_into(p, tok, depth, bson_kind_embedded_document(), at3, limit);
  }
  if t == 4 {
    let at4 = p.pos;
    return _parse_document_into(p, tok, depth, bson_kind_array(), at4, limit);
  }
  if t == 5 {
    if p.pos + 5 > limit {
      return _err_int(_trunc(tpos));
    }
    let n = _read_i32(p, p.pos);
    if n < 0 {
      return _err_int("bson: bad binary length " + _s(n) + " at " + _s(tpos));
    }
    if p.pos + 5 + n > limit {
      return _err_int("bson: truncated binary at " + _s(tpos));
    }
    p.payload_start[tok] = p.pos + 5;
    p.payload_end[tok] = p.pos + 5 + n;
    p.value[tok] = n;
    p.aux[tok] = _byte(p, p.pos + 4);
    p.pos = p.pos + 5 + n;
    return _ok_int(tok);
  }
  if t == 6 {
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos;
    return _ok_int(tok);
  }
  if t == 7 {
    if p.pos + 12 > limit {
      return _err_int(_trunc(tpos));
    }
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos + 12;
    p.pos = p.pos + 12;
    return _ok_int(tok);
  }
  if t == 8 {
    if p.pos + 1 > limit {
      return _err_int(_trunc(tpos));
    }
    let b = _byte(p, p.pos);
    if b > 1 {
      return _err_int("bson: bad boolean " + _s(b) + " at " + _s(tpos));
    }
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos + 1;
    p.value[tok] = b;
    p.pos = p.pos + 1;
    return _ok_int(tok);
  }
  if t == 9 {
    if p.pos + 8 > limit {
      return _err_int(_trunc(tpos));
    }
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos + 8;
    p.value[tok] = _read_i64(p, p.pos);
    p.pos = p.pos + 8;
    return _ok_int(tok);
  }
  if t == 10 {
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos;
    return _ok_int(tok);
  }
  if t == 11 {
    let ps = p.pos;
    let pe = _scan_cstring(p, ps, limit);
    if pe < 0 {
      return _err_int("bson: unterminated regex at " + _s(tpos));
    }
    let os = pe + 1;
    let oe = _scan_cstring(p, os, limit);
    if oe < 0 {
      return _err_int("bson: unterminated regex at " + _s(tpos));
    }
    p.payload_start[tok] = ps;
    p.payload_end[tok] = oe + 1;
    p.pos = oe + 1;
    return _ok_int(tok);
  }
  if t == 13 {
    return _parse_string_value(p, tok, tpos, limit);
  }
  if t == 14 {
    return _parse_string_value(p, tok, tpos, limit);
  }
  if t == 15 {
    if p.pos + 4 > limit {
      return _err_int(_trunc(tpos));
    }
    let total = _read_i32(p, p.pos);
    if total < 14 {
      return _err_int("bson: bad code_w_scope length " + _s(total) + " at " + _s(tpos));
    }
    let cend = p.pos + total;
    if cend > limit {
      return _err_int("bson: truncated code_w_scope at " + _s(tpos));
    }
    let str_pos = p.pos + 4;
    if str_pos + 4 > cend {
      return _err_int("bson: truncated code_w_scope at " + _s(tpos));
    }
    let n = _read_i32(p, str_pos);
    if n < 1 {
      return _err_int("bson: bad string length " + _s(n) + " at " + _s(tpos));
    }
    if str_pos + 4 + n > cend {
      return _err_int("bson: truncated code_w_scope at " + _s(tpos));
    }
    let content_end = str_pos + 4 + n - 1;
    if _byte(p, content_end) != 0 {
      return _err_int("bson: unterminated string at " + _s(tpos));
    }
    p.payload_start[tok] = str_pos + 4;
    p.payload_end[tok] = content_end;
    p.value[tok] = total;
    let scope_start = content_end + 1;
    p.pos = scope_start;
    let scope = _parse_scope_document(p, tok, depth, scope_start, cend, tpos, total);
    if !scope.is_ok {
      return _err_int(scope.error);
    }
    p.first_child[tok] = scope.value;
    p.child_count[tok] = 1;
    return _ok_int(tok);
  }
  if t == 16 {
    if p.pos + 4 > limit {
      return _err_int(_trunc(tpos));
    }
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos + 4;
    p.value[tok] = _read_i32(p, p.pos);
    p.pos = p.pos + 4;
    return _ok_int(tok);
  }
  if t == 17 {
    if p.pos + 8 > limit {
      return _err_int(_trunc(tpos));
    }
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos + 8;
    p.value[tok] = _read_u32(p, p.pos);
    p.aux[tok] = _read_u32(p, p.pos + 4);
    p.pos = p.pos + 8;
    return _ok_int(tok);
  }
  if t == 18 {
    if p.pos + 8 > limit {
      return _err_int(_trunc(tpos));
    }
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos + 8;
    p.value[tok] = _read_i64(p, p.pos);
    p.pos = p.pos + 8;
    return _ok_int(tok);
  }
  if t == 19 {
    if p.pos + 16 > limit {
      return _err_int(_trunc(tpos));
    }
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos + 16;
    p.pos = p.pos + 16;
    return _ok_int(tok);
  }
  if t == 127 {
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos;
    return _ok_int(tok);
  }
  if t == 255 {
    p.payload_start[tok] = p.pos;
    p.payload_end[tok] = p.pos;
    return _ok_int(tok);
  }
  return _err_int("bson: unknown element type " + _s(t) + " at " + _s(tpos));
}

// Parse the scope document of a code-with-scope element: it must exactly
// fill [at, cend) and becomes the single child token of the 0x0F element.
fn _parse_scope_document(p: &mut _BsonParser, parent: Int, depth: Int, at: Int, cend: Int, tpos: Int, total: Int) -> Result[Int, Str] {
  if depth > bson_max_depth() {
    return _err_int("bson: nesting depth exceeds limit of 100 at " + _s(at));
  }
  if at + 4 > cend {
    return _err_int("bson: bad code_w_scope length " + _s(total) + " at " + _s(tpos));
  }
  let len = _read_i32(p, at);
  if len < 5 {
    return _err_int("bson: bad document length " + _s(len) + " at " + _s(at));
  }
  if at + len != cend {
    return _err_int("bson: bad code_w_scope length " + _s(total) + " at " + _s(tpos));
  }
  let idx = _push_token(p, bson_kind_root_document(), parent, at);
  p.payload_start[idx] = at;
  p.payload_end[idx] = cend;
  p.value[idx] = len;
  p.pos = at + 4;
  return _parse_doc_body(p, depth, idx, cend);
}

/// Decode one complete BSON document from `data`.
///
/// `data` must contain exactly one document: the int32 length must match the
/// byte count and bytes after the document are rejected. The result is a
/// `BsonDoc` holding the input bytes and the flat token stream; use the
/// `bson_*` accessors to inspect it.
///
/// Errors (all messages start with `bson: ` and, unless noted, embed the
/// byte offset of the offending construct): truncated document; bad document
/// length; missing document terminator; truncated element; unterminated key;
/// bad string length / truncated string / unterminated string; bad binary
/// length / truncated binary; bad boolean; unterminated regex; bad
/// code_w_scope length / truncated code_w_scope; unknown element type;
/// nesting depth exceeds limit of 100; trailing data after document.
/// Complexity: O(data.len()).
pub fn bson_parse_document(data: Vec[UInt8]) -> Result[BsonDoc, Str] {
  var p = _new_bson_parser(data);
  let tok = _push_token(&mut p, bson_kind_root_document(), -1, 0);
  let total = p.data.len();
  let root = _parse_document_into(&mut p, tok, 0, bson_kind_root_document(), 0, total);
  if !root.is_ok {
    return _err_doc(root.error);
  }
  if p.pos != p.data.len() {
    return _err_doc("bson: trailing data after document at " + _s(p.pos));
  }
  return _ok_doc(_finish_doc(p));
}

// --------------------------------------------------
//  BSON accessors
// --------------------------------------------------

/// Number of tokens in the document (1 for an empty root document, plus one
/// token per element at every nesting level).
/// Complexity: O(1).
pub fn bson_token_count(doc: &BsonDoc) -> Int {
  return doc.kind.len();
}

/// Index of the root token: always 0 for a document produced by
/// `bson_parse_document`, or -1 for an empty document.
/// Complexity: O(1).
pub fn bson_root(doc: &BsonDoc) -> Int {
  if doc.kind.len() == 0 {
    return -1;
  }
  return 0;
}

/// Kind code of token `i` (one of the `bson_kind_*` values, plus
/// `bson_kind_root_document()`), or -1 when `i` is outside
/// [0, bson_token_count(doc)).
/// Complexity: O(1).
pub fn bson_kind(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.kind.len() {
    return -1;
  }
  let k: Int = doc.kind[i];
  return k;
}

/// Index of the token that contains token `i`, or -1 for the root token and
/// for an out-of-range `i`.
/// Complexity: O(1).
pub fn bson_parent(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.parent.len() {
    return -1;
  }
  let v: Int = doc.parent[i];
  return v;
}

/// Index of the first direct child of token `i`, or -1 for a leaf token and
/// for an out-of-range `i`.
/// Complexity: O(1).
pub fn bson_first_child(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.first_child.len() {
    return -1;
  }
  let v: Int = doc.first_child[i];
  return v;
}

/// Number of direct children of token `i`, or 0 for a leaf token and for an
/// out-of-range `i`.
/// Complexity: O(1).
pub fn bson_child_count(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.child_count.len() {
    return 0;
  }
  let v: Int = doc.child_count[i];
  return v;
}

/// Index of the n-th direct child of token `i` (0-based), or -1 when `i` is
/// not a container or `n` is outside [0, bson_child_count(doc, i)).
/// Complexity: O(n).
pub fn bson_child(doc: &BsonDoc, i: Int, n: Int) -> Int {
  let count = bson_child_count(doc, i);
  if n < 0 || n >= count {
    return -1;
  }
  var t = bson_first_child(doc, i);
  var k = 0;
  while k < n {
    t = bson_next_sibling(doc, t);
    k = k + 1;
  }
  return t;
}

/// Index of the next direct sibling of token `i` under the same parent, or
/// -1 when `i` is the last direct child (and for out-of-range `i`).
/// Pre-order token indices are not siblings just because they are adjacent,
/// so callers must use this accessor (or `bson_child`) to iterate a
/// container's children.
/// Complexity: O(1).
pub fn bson_next_sibling(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.next_sibling.len() {
    return -1;
  }
  let v: Int = doc.next_sibling[i];
  return v;
}

/// Byte offset of the first byte of token `i` (the type byte for an element,
/// the int32 length for a root/scope document), or -1 when `i` is outside
/// [0, bson_token_count(doc)).
/// Complexity: O(1).
pub fn bson_token_start(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.start.len() {
    return -1;
  }
  let v: Int = doc.start[i];
  return v;
}

/// Byte offset one past the last byte of token `i` (for containers, past the
/// closing 0x00), or -1 when `i` is outside [0, bson_token_count(doc)).
/// Complexity: O(1).
pub fn bson_token_end(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.end.len() {
    return -1;
  }
  let v: Int = doc.end[i];
  return v;
}

/// Byte length of token `i`'s key without the NUL, or -1 when the token has
/// no key (root and scope documents) or `i` is out of range.
/// Complexity: O(1).
pub fn bson_key_len(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.key_start.len() {
    return -1;
  }
  let ks: Int = doc.key_start[i];
  let ke: Int = doc.key_end[i];
  if ks < 0 || ke < ks {
    return -1;
  }
  return ke - ks;
}

/// Copy of token `i`'s key bytes (without the NUL), or an empty vector when
/// the token has no key or `i` is out of range (a valid empty key is
/// indistinguishable; check `bson_key_len` first).
/// Complexity: O(key length).
pub fn bson_key_bytes(doc: &BsonDoc, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if bson_key_len(doc, i) < 0 {
    return out;
  }
  let ks: Int = doc.key_start[i];
  let ke: Int = doc.key_end[i];
  var j = ks;
  while j < ke {
    out.push(doc.data[j]);
    j = j + 1;
  }
  return out;
}

/// Byte length of token `i`'s value payload, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn bson_payload_len(doc: &BsonDoc, i: Int) -> Int {
  if i < 0 || i >= doc.payload_start.len() {
    return -1;
  }
  let ps: Int = doc.payload_start[i];
  let pe: Int = doc.payload_end[i];
  if pe < ps {
    return 0;
  }
  return pe - ps;
}

/// Copy of token `i`'s value payload bytes, or an empty vector when `i` is
/// out of range or the value has no payload.
/// Complexity: O(payload length).
pub fn bson_payload_bytes(doc: &BsonDoc, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= doc.payload_start.len() {
    return out;
  }
  let ps: Int = doc.payload_start[i];
  let pe: Int = doc.payload_end[i];
  var j = ps;
  while j < pe {
    out.push(doc.data[j]);
    j = j + 1;
  }
  return out;
}

/// Parsed integer value of an int32 (0x10), int64 (0x12) or datetime (0x09)
/// token, or 0 when `i` is any other kind or is out of range (check the kind
/// first).
/// Complexity: O(1).
pub fn bson_int_value(doc: &BsonDoc, i: Int) -> Int {
  let k = bson_kind(doc, i);
  if k != bson_kind_int32() && k != bson_kind_int64() && k != bson_kind_datetime() {
    return 0;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Boolean value of a bool token: 1 for true, 0 for false, -1 when `i` is
/// not a bool token or is out of range.
/// Complexity: O(1).
pub fn bson_bool_value(doc: &BsonDoc, i: Int) -> Int {
  if bson_kind(doc, i) != bson_kind_bool() {
    return -1;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Declared byte length of a binary (0x05) token, or -1 when `i` is not a
/// binary token or is out of range.
/// Complexity: O(1).
pub fn bson_binary_len(doc: &BsonDoc, i: Int) -> Int {
  if bson_kind(doc, i) != bson_kind_binary() {
    return -1;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Subtype byte of a binary (0x05) token, or -1 when `i` is not a binary
/// token or is out of range.
/// Complexity: O(1).
pub fn bson_binary_subtype(doc: &BsonDoc, i: Int) -> Int {
  if bson_kind(doc, i) != bson_kind_binary() {
    return -1;
  }
  let v: Int = doc.aux[i];
  return v;
}

/// Copy of an ObjectId (0x07) token's 12 payload bytes, or an empty vector
/// when `i` is not an ObjectId token or is out of range.
/// Complexity: O(1).
pub fn bson_oid_bytes(doc: &BsonDoc, i: Int) -> Vec[UInt8] {
  if bson_kind(doc, i) != bson_kind_object_id() {
    return Vec[UInt8].new();
  }
  return bson_payload_bytes(doc, i);
}

/// Copy of a decimal128 (0x13) token's 16 opaque payload bytes, or an empty
/// vector when `i` is not a decimal128 token or is out of range.
/// Complexity: O(1).
pub fn bson_decimal_bytes(doc: &BsonDoc, i: Int) -> Vec[UInt8] {
  if bson_kind(doc, i) != bson_kind_decimal128() {
    return Vec[UInt8].new();
  }
  return bson_payload_bytes(doc, i);
}

/// Low 32 raw bits of a double (0x01) or timestamp (0x11) token (for a
/// timestamp: the increment), or -1 when `i` is another kind or is out of
/// range. Values are unsigned 32-bit raw words, not floats.
/// Complexity: O(1).
pub fn bson_word_low(doc: &BsonDoc, i: Int) -> Int {
  let k = bson_kind(doc, i);
  if k != bson_kind_double() && k != bson_kind_timestamp() {
    return -1;
  }
  let v: Int = doc.value[i];
  return v;
}

/// High 32 raw bits of a double (0x01) or timestamp (0x11) token (for a
/// timestamp: the seconds), or -1 when `i` is another kind or is out of
/// range. Values are unsigned 32-bit raw words, not floats.
/// Complexity: O(1).
pub fn bson_word_high(doc: &BsonDoc, i: Int) -> Int {
  let k = bson_kind(doc, i);
  if k != bson_kind_double() && k != bson_kind_timestamp() {
    return -1;
  }
  let v: Int = doc.aux[i];
  return v;
}

/// Copy of a string-layout token's content bytes: string (0x02), javascript
/// (0x0D), symbol (0x0E) and the code of code-with-scope (0x0F) -- without
/// the trailing NUL in every case. An empty vector when `i` is another kind
/// or is out of range.
/// Complexity: O(payload length).
pub fn bson_string_bytes(doc: &BsonDoc, i: Int) -> Vec[UInt8] {
  let k = bson_kind(doc, i);
  if k != bson_kind_string() && k != bson_kind_javascript() && k != bson_kind_symbol() && k != bson_kind_code_w_scope() {
    return Vec[UInt8].new();
  }
  return bson_payload_bytes(doc, i);
}

/// Copy of a regex (0x0B) token's pattern bytes (the first cstring, without
/// its NUL), or an empty vector when `i` is not a regex token or is out of
/// range.
/// Complexity: O(payload length).
pub fn bson_regex_pattern_bytes(doc: &BsonDoc, i: Int) -> Vec[UInt8] {
  if bson_kind(doc, i) != bson_kind_regex() {
    return Vec[UInt8].new();
  }
  let ps: Int = doc.payload_start[i];
  let pe: Int = doc.payload_end[i];
  var out = Vec[UInt8].new();
  var j = ps;
  while j < pe {
    let b: UInt8 = doc.data[j];
    if (b as Int) & 0xFF == 0 {
      return out;
    }
    out.push(b);
    j = j + 1;
  }
  return out;
}

/// Copy of a regex (0x0B) token's options bytes (the second cstring, without
/// its NUL), or an empty vector when `i` is not a regex token or is out of
/// range.
/// Complexity: O(payload length).
pub fn bson_regex_options_bytes(doc: &BsonDoc, i: Int) -> Vec[UInt8] {
  if bson_kind(doc, i) != bson_kind_regex() {
    return Vec[UInt8].new();
  }
  let ps: Int = doc.payload_start[i];
  let pe: Int = doc.payload_end[i];
  var out = Vec[UInt8].new();
  var j = ps;
  var seen_nul = 0;
  var done = 0;
  while j < pe && done == 0 {
    let b: UInt8 = doc.data[j];
    if seen_nul == 0 {
      if ((b as Int) & 0xFF) == 0 {
        seen_nul = 1;
      }
    } else {
      if ((b as Int) & 0xFF) == 0 {
        done = 1;
      } else {
        out.push(b);
      }
    }
    j = j + 1;
  }
  return out;
}

/// Index of the first direct child of container token `tok` whose key equals
/// `key` byte-for-byte, or -1 when no child matches (or `tok` is not a
/// container).
/// Complexity: O(children * key length).
pub fn bson_find_key(doc: &BsonDoc, tok: Int, key: &Vec[UInt8]) -> Int {
  let count = bson_child_count(doc, tok);
  var t = bson_first_child(doc, tok);
  var i = 0;
  while i < count {
    if t < 0 {
      return -1;
    }
    let ks: Int = doc.key_start[t];
    let ke: Int = doc.key_end[t];
    if ks >= 0 && ke >= ks && ke - ks == key.len() {
      var same = 1;
      var j = ks;
      while j < ke && same == 1 {
        let db: UInt8 = doc.data[j];
        let kb: UInt8 = key[j - ks];
        if ((db as Int) & 0xFF) != ((kb as Int) & 0xFF) {
          same = 0;
        }
        j = j + 1;
      }
      if same == 1 {
        return t;
      }
    }
    t = bson_next_sibling(doc, t);
    i = i + 1;
  }
  return -1;
}

/// `bson_find_key` with the key given as a `Str` (its UTF-8 bytes are
/// compared).
/// Complexity: O(children * key length).
pub fn bson_find_key_str(doc: &BsonDoc, tok: Int, key: Str) -> Int {
  var kb = Vec[UInt8].new();
  let n = string.str_len(key);
  var i = 0;
  while i < n {
    kb.push(string.byte_at(key, i));
    i = i + 1;
  }
  return bson_find_key(doc, tok, &kb);
}

// --------------------------------------------------
//  Wire-message decoder
// --------------------------------------------------

// Parse a BSON document whose length starts at absolute offset `at`, bounded
// by `limit`, and record its root token in `mp.doc_roots`. `depth` is the
// document's own depth (message-level documents start at 0).
fn _msg_doc_at(mp: &mut _MsgParser, bp: &mut _BsonParser, depth: Int, at: Int, limit: Int) -> Result[Int, Str] {
  bp.pos = at;
  bp.limit = limit;
  let tok = _push_token(bp, bson_kind_root_document(), -1, at);
  let r = _parse_document_into(bp, tok, depth, bson_kind_root_document(), at, limit);
  if !r.is_ok {
    return _err_int(r.error);
  }
  mp.doc_roots.push(tok);
  return _ok_int(tok);
}

// Parse the body of an OP_MSG (2013) message: flagBits then sections (kind 0
// body document, kind 1 document sequence). When the checksumPresent flag
// bit is set, the trailing 4 checksum bytes are excluded from section
// parsing (the checksum value is preserved but not verified).
fn _msg_parse_op_msg(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  if bs + 4 > mp.message_length {
    return _err_int("mongo: truncated message body at " + _s(bs));
  }
  mp.flags = _read_i32(bp, bs);
  if mp.flags % 2 != 0 {
    if mp.message_length - 4 < bs + 4 {
      return _err_int("mongo: truncated checksum at " + _s(bs + 4));
    }
    mp.body_end = mp.message_length - 4;
  }
  let limit0 = mp.body_end;
  var pos = bs + 4;
  var seen_body = 0;
  var seen_section = 0;
  var done = 0;
  while done == 0 {
    if pos >= limit0 {
      done = 1;
    } else {
      let k = _byte(bp, pos);
      if k == 0 {
        if seen_body == 1 {
          return _err_int("mongo: duplicate body section at " + _s(pos));
        }
        seen_body = 1;
        seen_section = 1;
        let sec_at = pos;
        mp.body_doc = mp.doc_roots.len();
        let d = _msg_doc_at(mp, bp, 0, pos + 1, limit0);
        if !d.is_ok {
          return _err_int(d.error);
        }
        pos = bp.pos;
        mp.sec_kind.push(0);
        mp.sec_start.push(sec_at);
        mp.sec_end.push(pos);
        mp.sec_ident.push(Vec[UInt8].new());
      } elif k == 1 {
        if seen_body == 1 {
          return _err_int("mongo: body section is not last at " + _s(pos));
        }
        seen_section = 1;
        if pos + 5 > limit0 {
          return _err_int("mongo: truncated section at " + _s(pos));
        }
        let size = _read_i32(bp, pos + 1);
        if size < 10 {
          return _err_int("mongo: bad section size " + _s(size) + " at " + _s(pos));
        }
        let sec_end = pos + 1 + size;
        if sec_end > limit0 {
          return _err_int("mongo: truncated section at " + _s(pos));
        }
        let ident_start = pos + 5;
        let ident_end = _scan_cstring(bp, ident_start, sec_end);
        if ident_end < 0 {
          return _err_int("mongo: unterminated identifier at " + _s(ident_start));
        }
        var ident = Vec[UInt8].new();
        _push_range(&mut ident, bp, ident_start, ident_end);
        var dpos = ident_end + 1;
        var ndocs = 0;
        while dpos < sec_end {
          let d2 = _msg_doc_at(mp, bp, 0, dpos, sec_end);
          if !d2.is_ok {
            return _err_int(d2.error);
          }
          dpos = bp.pos;
          ndocs = ndocs + 1;
        }
        if ndocs == 0 {
          return _err_int("mongo: empty document sequence at " + _s(pos));
        }
        mp.sec_kind.push(1);
        mp.sec_start.push(pos);
        mp.sec_end.push(sec_end);
        mp.sec_ident.push(ident);
        pos = sec_end;
      } else {
        return _err_int("mongo: unknown section kind " + _s(k) + " at " + _s(pos));
      }
    }
  }
  if seen_section == 0 {
    return _err_int("mongo: missing sections at " + _s(bs + 4));
  }
  return _ok_int(0);
}

// Parse the body of an OP_COMPRESSED (2012) message: originalOpcode,
// uncompressedSize, compressorId, then the compressed payload preserved
// verbatim.
fn _msg_parse_op_compressed(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  let be = mp.body_end;
  if bs + 9 > be {
    return _err_int("mongo: truncated op_compressed header at " + _s(bs));
  }
  mp.orig_opcode = _read_i32(bp, bs);
  mp.uncompressed_size = _read_i32(bp, bs + 4);
  if mp.uncompressed_size < 0 {
    return _err_int("mongo: bad uncompressed size " + _s(mp.uncompressed_size) + " at " + _s(bs + 4));
  }
  mp.compressor_id = _byte(bp, bs + 8);
  let payload_start = bs + 9;
  _push_range(&mut mp.payload, bp, payload_start, be);
  return _ok_int(0);
}

// Read the fullCollectionName cstring of a legacy opcode starting at `at`,
// storing the bytes in `mp.namespace`; returns the offset one past the NUL.
fn _msg_read_namespace(mp: &mut _MsgParser, bp: &_BsonParser, at: Int) -> Result[Int, Str] {
  let ns_end = _scan_cstring(bp, at, mp.body_end);
  if ns_end < 0 {
    return _err_int("mongo: unterminated namespace at " + _s(at));
  }
  if ns_end == at {
    return _err_int("mongo: empty namespace at " + _s(at));
  }
  var ns = Vec[UInt8].new();
  _push_range(&mut ns, bp, at, ns_end);
  mp.namespace = ns;
  return _ok_int(ns_end + 1);
}

// Parse the body of an OP_QUERY (2004) message: flags, fullCollectionName,
// numberToSkip, numberToReturn, the query document and the optional
// returnFieldsSelector document.
fn _msg_parse_op_query(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  let be = mp.body_end;
  if bs + 4 > be {
    return _err_int("mongo: truncated message body at " + _s(bs));
  }
  mp.flags = _read_i32(bp, bs);
  let nsr = _msg_read_namespace(mp, bp, bs + 4);
  if !nsr.is_ok {
    return _err_int(nsr.error);
  }
  var pos = nsr.value;
  if pos + 8 > be {
    return _err_int("mongo: truncated message body at " + _s(pos));
  }
  mp.number_to_skip = _read_i32(bp, pos);
  mp.number_to_return = _read_i32(bp, pos + 4);
  pos = pos + 8;
  let q = _msg_doc_at(mp, bp, 0, pos, be);
  if !q.is_ok {
    return _err_int(q.error);
  }
  pos = bp.pos;
  if pos < be {
    if be - pos < 5 {
      return _err_int("mongo: trailing bytes at " + _s(pos));
    }
    let sel = _msg_doc_at(mp, bp, 0, pos, be);
    if !sel.is_ok {
      return _err_int(sel.error);
    }
    pos = bp.pos;
  }
  if pos != be {
    return _err_int("mongo: trailing bytes at " + _s(pos));
  }
  return _ok_int(0);
}

// Parse the body of an OP_REPLY (1) message: responseFlags, cursorID,
// startingFrom, numberReturned and that many documents.
fn _msg_parse_op_reply(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  let be = mp.body_end;
  if bs + 20 > be {
    return _err_int("mongo: truncated message body at " + _s(bs));
  }
  mp.flags = _read_i32(bp, bs);
  mp.cursor_id = _read_i64(bp, bs + 4);
  mp.starting_from = _read_i32(bp, bs + 12);
  mp.number_returned = _read_i32(bp, bs + 16);
  if mp.number_returned < 0 {
    return _err_int("mongo: bad number_returned " + _s(mp.number_returned) + " at " + _s(bs + 16));
  }
  var pos = bs + 20;
  var i = 0;
  while i < mp.number_returned {
    if pos >= be {
      return _err_int("mongo: truncated document at " + _s(pos));
    }
    let d = _msg_doc_at(mp, bp, 0, pos, be);
    if !d.is_ok {
      return _err_int(d.error);
    }
    pos = bp.pos;
    i = i + 1;
  }
  if pos != be {
    return _err_int("mongo: trailing bytes at " + _s(pos));
  }
  return _ok_int(0);
}

// Parse the body of an OP_INSERT (2002) message: flags, fullCollectionName
// and one or more documents.
fn _msg_parse_op_insert(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  let be = mp.body_end;
  if bs + 4 > be {
    return _err_int("mongo: truncated message body at " + _s(bs));
  }
  mp.flags = _read_i32(bp, bs);
  let nsr = _msg_read_namespace(mp, bp, bs + 4);
  if !nsr.is_ok {
    return _err_int(nsr.error);
  }
  var pos = nsr.value;
  if pos >= be {
    return _err_int("mongo: missing insert documents at " + _s(pos));
  }
  while pos < be {
    let d = _msg_doc_at(mp, bp, 0, pos, be);
    if !d.is_ok {
      return _err_int(d.error);
    }
    pos = bp.pos;
  }
  return _ok_int(0);
}

// Parse the body of an OP_UPDATE (2001) message: ZERO, fullCollectionName,
// flags, selector document, update document.
fn _msg_parse_op_update(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  let be = mp.body_end;
  if bs + 4 > be {
    return _err_int("mongo: truncated message body at " + _s(bs));
  }
  mp.zero = _read_i32(bp, bs);
  if mp.zero != 0 {
    return _err_int("mongo: bad zero field " + _s(mp.zero) + " at " + _s(bs));
  }
  let nsr = _msg_read_namespace(mp, bp, bs + 4);
  if !nsr.is_ok {
    return _err_int(nsr.error);
  }
  var pos = nsr.value;
  if pos + 4 > be {
    return _err_int("mongo: truncated message body at " + _s(pos));
  }
  mp.flags = _read_i32(bp, pos);
  pos = pos + 4;
  let sel = _msg_doc_at(mp, bp, 0, pos, be);
  if !sel.is_ok {
    return _err_int(sel.error);
  }
  pos = bp.pos;
  let upd = _msg_doc_at(mp, bp, 0, pos, be);
  if !upd.is_ok {
    return _err_int(upd.error);
  }
  pos = bp.pos;
  if pos != be {
    return _err_int("mongo: trailing bytes at " + _s(pos));
  }
  return _ok_int(0);
}

// Parse the body of an OP_DELETE (2006) message: ZERO, fullCollectionName,
// flags, selector document.
fn _msg_parse_op_delete(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  let be = mp.body_end;
  if bs + 4 > be {
    return _err_int("mongo: truncated message body at " + _s(bs));
  }
  mp.zero = _read_i32(bp, bs);
  if mp.zero != 0 {
    return _err_int("mongo: bad zero field " + _s(mp.zero) + " at " + _s(bs));
  }
  let nsr = _msg_read_namespace(mp, bp, bs + 4);
  if !nsr.is_ok {
    return _err_int(nsr.error);
  }
  var pos = nsr.value;
  if pos + 4 > be {
    return _err_int("mongo: truncated message body at " + _s(pos));
  }
  mp.flags = _read_i32(bp, pos);
  pos = pos + 4;
  let sel = _msg_doc_at(mp, bp, 0, pos, be);
  if !sel.is_ok {
    return _err_int(sel.error);
  }
  pos = bp.pos;
  if pos != be {
    return _err_int("mongo: trailing bytes at " + _s(pos));
  }
  return _ok_int(0);
}

// Parse the body of an OP_GET_MORE (2005) message: ZERO, fullCollectionName,
// numberToReturn, cursorID.
fn _msg_parse_op_get_more(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  let be = mp.body_end;
  if bs + 4 > be {
    return _err_int("mongo: truncated message body at " + _s(bs));
  }
  mp.zero = _read_i32(bp, bs);
  if mp.zero != 0 {
    return _err_int("mongo: bad zero field " + _s(mp.zero) + " at " + _s(bs));
  }
  let nsr = _msg_read_namespace(mp, bp, bs + 4);
  if !nsr.is_ok {
    return _err_int(nsr.error);
  }
  var pos = nsr.value;
  if pos + 12 > be {
    return _err_int("mongo: truncated message body at " + _s(pos));
  }
  mp.number_to_return = _read_i32(bp, pos);
  mp.cursor_id = _read_i64(bp, pos + 4);
  pos = pos + 12;
  if pos != be {
    return _err_int("mongo: trailing bytes at " + _s(pos));
  }
  return _ok_int(0);
}

// Parse the body of an OP_KILL_CURSORS (2007) message: ZERO, numberOfCursorIDs
// and that many int64 cursor IDs.
fn _msg_parse_op_kill_cursors(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let bs = mp.body_start;
  let be = mp.body_end;
  if bs + 8 > be {
    return _err_int("mongo: truncated message body at " + _s(bs));
  }
  mp.zero = _read_i32(bp, bs);
  if mp.zero != 0 {
    return _err_int("mongo: bad zero field " + _s(mp.zero) + " at " + _s(bs));
  }
  mp.cursor_count = _read_i32(bp, bs + 4);
  if mp.cursor_count < 0 {
    return _err_int("mongo: bad cursor count " + _s(mp.cursor_count) + " at " + _s(bs + 4));
  }
  if bs + 8 + mp.cursor_count * 8 > be {
    return _err_int("mongo: truncated cursor ids at " + _s(bs + 8));
  }
  var pos = bs + 8;
  var i = 0;
  while i < mp.cursor_count {
    let id = _read_i64(bp, pos);
    mp.cursor_ids.push(id);
    pos = pos + 8;
    i = i + 1;
  }
  if pos != be {
    return _err_int("mongo: trailing bytes at " + _s(pos));
  }
  return _ok_int(0);
}

// Dispatch on `mp.opcode` after the header has been validated. Unknown
// opcodes succeed with the body preserved in `mp.payload`.
fn _msg_parse_body(mp: &mut _MsgParser, bp: &mut _BsonParser) -> Result[Int, Str] {
  let op = mp.opcode;
  if op == 2013 {
    return _msg_parse_op_msg(mp, bp);
  }
  if op == 2012 {
    return _msg_parse_op_compressed(mp, bp);
  }
  if op == 2004 {
    return _msg_parse_op_query(mp, bp);
  }
  if op == 1 {
    return _msg_parse_op_reply(mp, bp);
  }
  if op == 2002 {
    return _msg_parse_op_insert(mp, bp);
  }
  if op == 2001 {
    return _msg_parse_op_update(mp, bp);
  }
  if op == 2006 {
    return _msg_parse_op_delete(mp, bp);
  }
  if op == 2005 {
    return _msg_parse_op_get_more(mp, bp);
  }
  if op == 2007 {
    return _msg_parse_op_kill_cursors(mp, bp);
  }
  let rs = mp.body_start;
  let re = mp.body_end;
  _push_range(&mut mp.payload, bp, rs, re);
  return _ok_int(0);
}

/// Parse one complete wire message from the start of `data`.
///
/// The result is a `MongoMsg` whose `message_length` equals the consumed
/// byte count, so a caller can advance a stream by
/// `mongo_msg_consumed(msg)`. Bytes after the declared message length are
/// left unconsumed (concatenated messages are allowed); bytes inside the
/// declared length that the opcode does not use are rejected as trailing
/// bytes.
///
/// Errors (all messages start with `mongo: ` and embed the byte offset of
/// the offending construct): truncated message header; bad message length;
/// truncated message; truncated message body; truncated document; bad
/// document length; missing document terminator; truncated element;
/// unterminated key; bad string length / truncated string / unterminated
/// string; bad binary length / truncated binary; bad boolean; unterminated
/// regex; bad code_w_scope length / truncated code_w_scope; unknown element
/// type; nesting depth exceeds limit of 100; bad section size; duplicate
/// body section; body section is not last; unknown section kind; unterminated
/// identifier / unterminated namespace; empty namespace; empty document
/// sequence; bad zero field; bad number_returned / bad cursor count;
/// truncated cursor ids; truncated op_compressed header; bad uncompressed
/// size; trailing bytes. Opcode-specific BSON messages keep their `bson: `
/// prefix.
/// Complexity: O(data.len()).
pub fn mongo_parse_message(data: Vec[UInt8]) -> Result[MongoMsg, Str] {
  var bp = _new_bson_parser(data);
  var mp = _new_msg_parser();
  let total = bp.data.len();
  if total < mongo_header_size() {
    return _err_msg("mongo: truncated message header at 0");
  }
  mp.message_length = _read_i32(&bp, 0);
  mp.request_id = _read_i32(&bp, 4);
  mp.response_to = _read_i32(&bp, 8);
  mp.opcode = _read_i32(&bp, 12);
  if mp.message_length < mongo_header_size() {
    return _err_msg("mongo: bad message length " + _s(mp.message_length) + " at 0");
  }
  if mp.message_length > total {
    return _err_msg("mongo: truncated message at 0: declared " + _s(mp.message_length) + " bytes, have " + _s(total));
  }
  mp.body_start = mongo_header_size();
  mp.body_end = mp.message_length;
  bp.limit = mp.body_end;
  let r = _msg_parse_body(&mut mp, &mut bp);
  if !r.is_ok {
    return _err_msg(r.error);
  }
  let docs = _finish_doc(bp);
  let data_out: Vec[UInt8] = docs.data;
  return _ok_msg(_finish_msg(mp, docs, data_out));
}

// Assemble the public message value from the parsed scalars, the document
// token stream and the (shared) source bytes.
fn _finish_msg(mp: _MsgParser, docs: BsonDoc, data: Vec[UInt8]) -> MongoMsg {
  let message_length: Int = mp.message_length;
  let request_id: Int = mp.request_id;
  let response_to: Int = mp.response_to;
  let opcode: Int = mp.opcode;
  let body_start: Int = mp.body_start;
  let body_end: Int = mp.body_end;
  let flags: Int = mp.flags;
  let number_to_skip: Int = mp.number_to_skip;
  let number_to_return: Int = mp.number_to_return;
  let cursor_id: Int = mp.cursor_id;
  let starting_from: Int = mp.starting_from;
  let number_returned: Int = mp.number_returned;
  let zero: Int = mp.zero;
  let cursor_count: Int = mp.cursor_count;
  let namespace: Vec[UInt8] = mp.namespace;
  let orig_opcode: Int = mp.orig_opcode;
  let uncompressed_size: Int = mp.uncompressed_size;
  let compressor_id: Int = mp.compressor_id;
  let payload: Vec[UInt8] = mp.payload;
  let cursor_ids: Vec[Int] = mp.cursor_ids;
  let doc_roots: Vec[Int] = mp.doc_roots;
  let body_doc: Int = mp.body_doc;
  let sec_kind: Vec[Int] = mp.sec_kind;
  let sec_start: Vec[Int] = mp.sec_start;
  let sec_end: Vec[Int] = mp.sec_end;
  let sec_ident: Vec[Vec[UInt8]] = mp.sec_ident;
  return MongoMsg{
    data: data;
    message_length: message_length;
    request_id: request_id;
    response_to: response_to;
    opcode: opcode;
    body_start: body_start;
    body_end: body_end;
    flags: flags;
    number_to_skip: number_to_skip;
    number_to_return: number_to_return;
    cursor_id: cursor_id;
    starting_from: starting_from;
    number_returned: number_returned;
    zero: zero;
    cursor_count: cursor_count;
    namespace: namespace;
    orig_opcode: orig_opcode;
    uncompressed_size: uncompressed_size;
    compressor_id: compressor_id;
    payload: payload;
    cursor_ids: cursor_ids;
    docs: docs;
    doc_roots: doc_roots;
    body_doc: body_doc;
    sec_kind: sec_kind;
    sec_start: sec_start;
    sec_end: sec_end;
    sec_ident: sec_ident;
  };
}

// --------------------------------------------------
//  Wire-message accessors
// --------------------------------------------------

/// Bytes consumed by the parsed message: the declared messageLength. Use it
/// to advance past the message when parsing a stream.
/// Complexity: O(1).
pub fn mongo_msg_consumed(msg: &MongoMsg) -> Int {
  return msg.message_length;
}

/// Declared messageLength from the header.
/// Complexity: O(1).
pub fn mongo_msg_message_length(msg: &MongoMsg) -> Int {
  return msg.message_length;
}

/// requestID from the header.
/// Complexity: O(1).
pub fn mongo_msg_request_id(msg: &MongoMsg) -> Int {
  return msg.request_id;
}

/// responseTo from the header.
/// Complexity: O(1).
pub fn mongo_msg_response_to(msg: &MongoMsg) -> Int {
  return msg.response_to;
}

/// opCode from the header.
/// Complexity: O(1).
pub fn mongo_msg_opcode(msg: &MongoMsg) -> Int {
  return msg.opcode;
}

/// Whether the parsed opcode is one this codec decodes structurally (see
/// `mongo_opcode_known`).
/// Complexity: O(1).
pub fn mongo_msg_opcode_known(msg: &MongoMsg) -> Bool {
  return mongo_opcode_known(msg.opcode);
}

/// Human-readable name of the parsed opcode, or "" for an unknown opcode.
/// Complexity: O(1).
pub fn mongo_msg_opcode_name(msg: &MongoMsg) -> Str {
  return mongo_opcode_name(msg.opcode);
}

/// Offset of the first body byte (always `mongo_header_size()`).
/// Complexity: O(1).
pub fn mongo_msg_body_start(msg: &MongoMsg) -> Int {
  return msg.body_start;
}

/// Offset one past the last body byte the opcode parser consumed (for OP_MSG
/// with a checksum, this excludes the trailing 4 checksum bytes).
/// Complexity: O(1).
pub fn mongo_msg_body_end(msg: &MongoMsg) -> Int {
  return msg.body_end;
}

/// Copy of the opcode body bytes (from `body_start` to `body_end`).
/// Complexity: O(body length).
pub fn mongo_msg_body(msg: &MongoMsg) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = msg.body_start;
  while i < msg.body_end {
    out.push(msg.data[i]);
    i = i + 1;
  }
  return out;
}

/// The opcode's main flags word (OP_MSG flagBits, OP_QUERY flags, OP_REPLY
/// responseFlags, OP_INSERT flags, OP_UPDATE flags, OP_DELETE flags), or -1
/// when the opcode has no flags field.
/// Complexity: O(1).
pub fn mongo_msg_flags(msg: &MongoMsg) -> Int {
  return msg.flags;
}

/// numberToSkip of an OP_QUERY message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_number_to_skip(msg: &MongoMsg) -> Int {
  return msg.number_to_skip;
}

/// numberToReturn of an OP_QUERY or OP_GET_MORE message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_number_to_return(msg: &MongoMsg) -> Int {
  return msg.number_to_return;
}

/// cursorID of an OP_REPLY or OP_GET_MORE message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_cursor_id(msg: &MongoMsg) -> Int {
  return msg.cursor_id;
}

/// startingFrom of an OP_REPLY message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_starting_from(msg: &MongoMsg) -> Int {
  return msg.starting_from;
}

/// numberReturned of an OP_REPLY message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_number_returned(msg: &MongoMsg) -> Int {
  return msg.number_returned;
}

/// The ZERO field of an OP_UPDATE, OP_DELETE, OP_GET_MORE or OP_KILL_CURSORS
/// message (always 0 on success), or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_zero(msg: &MongoMsg) -> Int {
  return msg.zero;
}

/// numberOfCursorIDs of an OP_KILL_CURSORS message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_cursor_count(msg: &MongoMsg) -> Int {
  return msg.cursor_count;
}

/// Number of cursor IDs stored by an OP_KILL_CURSORS message (equal to
/// `mongo_msg_cursor_count` on success).
/// Complexity: O(1).
pub fn mongo_msg_cursor_id_count(msg: &MongoMsg) -> Int {
  return msg.cursor_ids.len();
}

/// The n-th OP_KILL_CURSORS cursor ID (0-based), or -1 when `n` is outside
/// [0, mongo_msg_cursor_id_count(msg)).
/// Complexity: O(1).
pub fn mongo_msg_cursor_id_at(msg: &MongoMsg, n: Int) -> Int {
  if n < 0 || n >= msg.cursor_ids.len() {
    return -1;
  }
  let v: Int = msg.cursor_ids[n];
  return v;
}

/// Copy of the fullCollectionName bytes of a legacy message (without the
/// NUL), or an empty vector when the opcode has no namespace field.
/// Complexity: O(namespace length).
pub fn mongo_msg_namespace_bytes(msg: &MongoMsg) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < msg.namespace.len() {
    out.push(msg.namespace[i]);
    i = i + 1;
  }
  return out;
}

/// originalOpcode of an OP_COMPRESSED message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_orig_opcode(msg: &MongoMsg) -> Int {
  return msg.orig_opcode;
}

/// uncompressedSize of an OP_COMPRESSED message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_uncompressed_size(msg: &MongoMsg) -> Int {
  return msg.uncompressed_size;
}

/// compressorId of an OP_COMPRESSED message, or -1 otherwise.
/// Complexity: O(1).
pub fn mongo_msg_compressor_id(msg: &MongoMsg) -> Int {
  return msg.compressor_id;
}

/// Copy of the opaque payload: the compressed bytes of an OP_COMPRESSED
/// message or the body of an unknown opcode; empty otherwise. No
/// decompression is performed.
/// Complexity: O(payload length).
pub fn mongo_msg_payload(msg: &MongoMsg) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < msg.payload.len() {
    out.push(msg.payload[i]);
    i = i + 1;
  }
  return out;
}

/// Copy of the trailing 4 checksum bytes of an OP_MSG whose checksumPresent
/// flag bit is set, or an empty vector otherwise (the checksum value itself
/// is not verified or computed).
/// Complexity: O(1).
pub fn mongo_msg_checksum_bytes(msg: &MongoMsg) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if msg.opcode != 2013 {
    return out;
  }
  if msg.flags % 2 == 0 {
    return out;
  }
  if msg.message_length - 4 < msg.body_start {
    return out;
  }
  var i = msg.message_length - 4;
  while i < msg.message_length {
    out.push(msg.data[i]);
    i = i + 1;
  }
  return out;
}

/// Number of top-level BSON documents found in the message (see
/// `mongo_msg_doc_root` for the ordering).
/// Complexity: O(1).
pub fn mongo_msg_doc_count(msg: &MongoMsg) -> Int {
  return msg.doc_roots.len();
}

/// Token index (into `msg.docs`) of the n-th top-level document of the
/// message, or -1 when `n` is outside [0, mongo_msg_doc_count(msg)).
/// Complexity: O(1).
pub fn mongo_msg_doc_root(msg: &MongoMsg, n: Int) -> Int {
  if n < 0 || n >= msg.doc_roots.len() {
    return -1;
  }
  let v: Int = msg.doc_roots[n];
  return v;
}

/// Index into `msg.doc_roots` of the OP_MSG kind-0 body document, or -1 when
/// the message is not OP_MSG or has no body section.
/// Complexity: O(1).
pub fn mongo_msg_body_doc_index(msg: &MongoMsg) -> Int {
  if msg.opcode != 2013 {
    return -1;
  }
  return msg.body_doc;
}

/// Number of OP_MSG sections (0 for other opcodes).
/// Complexity: O(1).
pub fn mongo_msg_section_count(msg: &MongoMsg) -> Int {
  return msg.sec_kind.len();
}

/// Kind of OP_MSG section `n` (0 body, 1 document sequence), or -1 when `n`
/// is out of range.
/// Complexity: O(1).
pub fn mongo_msg_section_kind(msg: &MongoMsg, n: Int) -> Int {
  if n < 0 || n >= msg.sec_kind.len() {
    return -1;
  }
  let v: Int = msg.sec_kind[n];
  return v;
}

/// Offset of OP_MSG section `n`'s first byte (the kind byte), or -1 when `n`
/// is out of range.
/// Complexity: O(1).
pub fn mongo_msg_section_start(msg: &MongoMsg, n: Int) -> Int {
  if n < 0 || n >= msg.sec_start.len() {
    return -1;
  }
  let v: Int = msg.sec_start[n];
  return v;
}

/// Offset one past OP_MSG section `n`'s last byte, or -1 when `n` is out of
/// range.
/// Complexity: O(1).
pub fn mongo_msg_section_end(msg: &MongoMsg, n: Int) -> Int {
  if n < 0 || n >= msg.sec_end.len() {
    return -1;
  }
  let v: Int = msg.sec_end[n];
  return v;
}

/// Copy of OP_MSG section `n`'s kind-1 identifier bytes (without the NUL),
/// or an empty vector for a kind-0 section and for an out-of-range `n`.
/// Complexity: O(identifier length).
pub fn mongo_msg_section_ident_bytes(msg: &MongoMsg, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if n < 0 || n >= msg.sec_ident.len() {
    return out;
  }
  let ident: Vec[UInt8] = msg.sec_ident[n];
  var i = 0;
  while i < ident.len() {
    out.push(ident[i]);
    i = i + 1;
  }
  return out;
}
