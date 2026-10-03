// XIOM -- xiom.firebird: Firebird wire-protocol structural codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no sockets, no connection state.
//
// A structural codec for the Firebird client/server wire protocol, modelled
// on the published xiom.mysql/xiom.mssql/xiom.db2 approach: it turns the
// bytes a transport would carry into typed XIOM values and back, and never
// performs I/O or looks inside SQL.
//
// Documented subset (constants pinned to the Firebird master sources,
// src/remote/protocol.h and src/remote/protocol.cpp):
//   * canonical XDR field encoding as negotiated with arch_generic: every
//     short/long/enum/unsigned is a 32-bit big-endian word, a counted string
//     ("cstring") is a 32-bit length + bytes + zero padding to 4, and a
//     packet body is [4-byte opcode][fields] with no transport length prefix
//     (packets are self-delimiting; partial receives surface as op_partial);
//   * the opcode registry for the common protocol blocks;
//   * the connect block (op_connect), the accept block (op_accept), the
//     attach/create/service-attach block, the five-word data block, the
//     single-object release block and the start-transaction block.
// Host-native (non-generic) XDR layouts, compression, crypt, status-vector
// bodies, message payloads and authentication are explicit non-goals.
//
// Language notes (XIOM v0.61.3): free functions only; flat parallel Vecs
// instead of Vec[StructType]; Result construction confined to the leaf
// helpers _ok_bytes/_err_*; mutating Vec parameters are passed with an
// explicit &mut at every call site; ntoh-style assembly uses multiplication
// (bitwise mixes are parenthesized on v0.62.x).

module xiom.firebird

use xiom.string;
use xiom.string.compare;
use xiom.convert;

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

// Ok(c) for Result[FbConnect, Str].
fn _ok_connect(c: FbConnect) -> Result[FbConnect, Str] {
  return Ok(c);
}

// Err(m) for Result[FbConnect, Str].
fn _err_connect(m: Str) -> Result[FbConnect, Str] {
  return Err(m);
}

// Ok(a) for Result[FbAccept, Str].
fn _ok_accept(a: FbAccept) -> Result[FbAccept, Str] {
  return Ok(a);
}

// Err(m) for Result[FbAccept, Str].
fn _err_accept(m: Str) -> Result[FbAccept, Str] {
  return Err(m);
}

// Ok(a) for Result[FbAttach, Str].
fn _ok_attach(a: FbAttach) -> Result[FbAttach, Str] {
  return Ok(a);
}

// Err(m) for Result[FbAttach, Str].
fn _err_attach(m: Str) -> Result[FbAttach, Str] {
  return Err(m);
}

// Ok(d) for Result[FbData, Str].
fn _ok_data(d: FbData) -> Result[FbData, Str] {
  return Ok(d);
}

// Err(m) for Result[FbData, Str].
fn _err_data(m: Str) -> Result[FbData, Str] {
  return Err(m);
}

// Ok(o) for Result[FbObject, Str].
fn _ok_object(o: FbObject) -> Result[FbObject, Str] {
  return Ok(o);
}

// Err(m) for Result[FbObject, Str].
fn _err_object(m: Str) -> Result[FbObject, Str] {
  return Err(m);
}

// Ok(t) for Result[FbTransaction, Str].
fn _ok_tran(t: FbTransaction) -> Result[FbTransaction, Str] {
  return Ok(t);
}

// Err(m) for Result[FbTransaction, Str].
fn _err_tran(m: Str) -> Result[FbTransaction, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Limits
// --------------------------------------------------

// Largest 32-bit unsigned field value.
const _FB_U32_MAX: Int = 4294967295;

// Largest 16-bit unsigned field value.
const _FB_U16_MAX: Int = 65535;

// Maximum protocol entries in a connect block (upstream MAX_CNCT_VERSIONS).
const _FB_MAX_VERSIONS: Int = 11;

// Reader states.
const _FB_ERR_NONE: Int = 0;
const _FB_ERR_TRUNCATED: Int = 1;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// The op_connect block (upstream P_CNCT): the client's connect offer.
/// operation is the unused first wire field; cversion is the connect protocol
/// version; client_arch is the P_ARCH value (1 = arch_generic); file is the
/// database path; user_id is the packed user-identification string; the five
/// version arrays are index-aligned and hold one entry per offered protocol
/// (version, architecture, min type, max type, weight).
pub type FbConnect = {
  operation: Int;
  cversion: Int;
  client_arch: Int;
  file: Str;
  user_id: Str;
  protocols: Vec[Int];
  archs: Vec[Int];
  min_types: Vec[Int];
  max_types: Vec[Int];
  weights: Vec[Int];
}

/// The op_accept block (upstream P_ACPT): the server's chosen protocol
/// version, architecture and type.
pub type FbAccept = {
  version: Int;
  architecture: Int;
  ptype: Int;
}

/// The attach/create/service-attach block (upstream P_ATCH): the database
/// object, the file name and the database parameter block.
pub type FbAttach = {
  op: Int;
  database: Int;
  file: Str;
  dpb: Str;
}

/// The data block (upstream P_DATA) used by start/send/receive: request
/// object, incarnation, transaction object, message number and count.
pub type FbData = {
  op: Int;
  request: Int;
  incarnation: Int;
  transaction: Int;
  message_number: Int;
  messages: Int;
}

/// The single-object release block (upstream P_RLSE) used by commit,
/// rollback, detach, blob close and friends.
pub type FbObject = {
  op: Int;
  object: Int;
}

/// The start-transaction / reconnect block (upstream P_STTR): database object
/// and transaction parameter block.
pub type FbTransaction = {
  op: Int;
  database: Int;
  tpb: Str;
}

// --------------------------------------------------
//  Reader (private primitives)
// --------------------------------------------------

// Byte-cursor over one packet with a sticky error flag; after an error every
// read returns 0 without advancing, so a parser can run to completion and
// check the flag once.
type FbReader = {
  bytes: Vec[UInt8];
  pos: Int;
  err: Int;
}

// A reader over `bytes`.
fn _fb_reader(bytes: Vec[UInt8]) -> FbReader {
  return FbReader{ bytes: bytes; pos: 0; err: _FB_ERR_NONE; };
}

// Read one u32 big-endian, or set the truncated flag.
fn _fb_u32(r: &mut FbReader) -> Int {
  let e: Int = r.err;
  if e != _FB_ERR_NONE {
    return 0;
  }
  let p: Int = r.pos;
  if p + 4 > r.bytes.len() {
    r.err = _FB_ERR_TRUNCATED;
    return 0;
  }
  let b0: UInt8 = r.bytes[p];
  let b1: UInt8 = r.bytes[p + 1];
  let b2: UInt8 = r.bytes[p + 2];
  let b3: UInt8 = r.bytes[p + 3];
  r.pos = p + 4;
  return ((b0 as Int) & 255) * 16777216 + ((b1 as Int) & 255) * 65536
    + ((b2 as Int) & 255) * 256 + ((b3 as Int) & 255);
}

// Read one counted string: u32 length, bytes, zero padding to 4.
fn _fb_cstring(r: &mut FbReader) -> Str {
  let e: Int = r.err;
  if e != _FB_ERR_NONE {
    return "";
  }
  let len = _fb_u32(r);
  let e2: Int = r.err;
  if e2 != _FB_ERR_NONE {
    return "";
  }
  let p: Int = r.pos;
  let pad = (4 - len % 4) % 4;
  if p + len + pad > r.bytes.len() {
    r.err = _FB_ERR_TRUNCATED;
    return "";
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    let b: UInt8 = r.bytes[p + i];
    out.push(b);
    i = i + 1;
  }
  r.pos = p + len + pad;
  return Str::from_utf8(out);
}

// Message for a sticky reader error state.
fn _fb_reader_message(err: Int) -> Str {
  if err == _FB_ERR_TRUNCATED {
    return "firebird: truncated packet";
  }
  return "firebird: packet read error";
}

// --------------------------------------------------
//  Writer primitives
// --------------------------------------------------

// Append one u32 big-endian; the caller has validated 0..4294967295.
fn _fb_push_u32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v >> 24) & 255) as UInt8);
  out.push(((v >> 16) & 255) as UInt8);
  out.push(((v >> 8) & 255) as UInt8);
  out.push((v & 255) as UInt8);
}

// Append one counted string with zero padding to 4.
fn _fb_push_cstring(out: &mut Vec[UInt8], s: Str) {
  _fb_push_u32(out, s.len());
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    out.push(b);
    i = i + 1;
  }
  let pad = (4 - s.len() % 4) % 4;
  var p = 0;
  while p < pad {
    out.push(0u8);
    p = p + 1;
  }
}

// Range predicates used by the block emitters.
fn _fb_u32_ok(v: Int) -> Bool {
  return v >= 0 && v <= _FB_U32_MAX;
}

fn _fb_u16_ok(v: Int) -> Bool {
  return v >= 0 && v <= _FB_U16_MAX;
}

// --------------------------------------------------
//  Opcode registry
// --------------------------------------------------

// Name of a protocol opcode, or "" when it is not in the documented table.
// Values are pinned to the upstream P_OP enum (src/remote/protocol.h).
fn _fb_opcode_name(code: Int) -> Str {
  if code == 1 { return "connect"; }
  if code == 2 { return "exit"; }
  if code == 3 { return "accept"; }
  if code == 4 { return "reject"; }
  if code == 6 { return "disconnect"; }
  if code == 9 { return "response"; }
  if code == 19 { return "attach"; }
  if code == 20 { return "create"; }
  if code == 21 { return "detach"; }
  if code == 22 { return "compile"; }
  if code == 23 { return "start"; }
  if code == 24 { return "start_and_send"; }
  if code == 25 { return "send"; }
  if code == 26 { return "receive"; }
  if code == 28 { return "release"; }
  if code == 29 { return "transaction"; }
  if code == 30 { return "commit"; }
  if code == 31 { return "rollback"; }
  if code == 32 { return "prepare"; }
  if code == 33 { return "reconnect"; }
  if code == 34 { return "create_blob"; }
  if code == 35 { return "open_blob"; }
  if code == 36 { return "get_segment"; }
  if code == 37 { return "put_segment"; }
  if code == 38 { return "cancel_blob"; }
  if code == 39 { return "close_blob"; }
  if code == 40 { return "info_database"; }
  if code == 41 { return "info_request"; }
  if code == 42 { return "info_transaction"; }
  if code == 43 { return "info_blob"; }
  if code == 48 { return "que_events"; }
  if code == 49 { return "cancel_events"; }
  if code == 50 { return "commit_retaining"; }
  if code == 51 { return "prepare2"; }
  if code == 52 { return "event"; }
  if code == 53 { return "connect_request"; }
  if code == 54 { return "aux_connect"; }
  if code == 55 { return "ddl"; }
  if code == 62 { return "allocate_statement"; }
  if code == 63 { return "execute"; }
  if code == 64 { return "exec_immediate"; }
  if code == 65 { return "fetch"; }
  if code == 66 { return "fetch_response"; }
  if code == 67 { return "free_statement"; }
  if code == 68 { return "prepare_statement"; }
  if code == 69 { return "set_cursor"; }
  if code == 70 { return "info_sql"; }
  if code == 71 { return "dummy"; }
  if code == 73 { return "start_and_receive"; }
  if code == 74 { return "start_send_and_receive"; }
  if code == 78 { return "sql_response"; }
  if code == 79 { return "transact"; }
  if code == 80 { return "transact_response"; }
  if code == 81 { return "drop_database"; }
  if code == 82 { return "service_attach"; }
  if code == 83 { return "service_detach"; }
  if code == 84 { return "service_info"; }
  if code == 85 { return "service_start"; }
  if code == 86 { return "rollback_retaining"; }
  if code == 89 { return "partial"; }
  if code == 91 { return "cancel"; }
  if code == 92 { return "cont_auth"; }
  if code == 93 { return "ping"; }
  if code == 94 { return "accept_data"; }
  if code == 95 { return "abort_aux_connection"; }
  if code == 99 { return "batch_create"; }
  if code == 100 { return "batch_msg"; }
  if code == 101 { return "batch_exec"; }
  if code == 102 { return "batch_rls"; }
  if code == 103 { return "batch_cs"; }
  if code == 109 { return "batch_cancel"; }
  if code == 110 { return "batch_sync"; }
  if code == 112 { return "fetch_scroll"; }
  if code == 113 { return "info_cursor"; }
  if code == 114 { return "inline_blob"; }
  return "";
}

/// Opcode of a registered block name, or -1.
/// Params: name - the opcode name (for example "connect").
/// Returns: the numeric opcode; -1 when the name is not in the documented
/// table (the commented-out upstream slots are deliberately absent).
/// Error case: none.
/// Complexity: O(table).
pub fn firebird_opcode_of(name: Str) -> Int {
  var c = 0;
  while c < 256 {
    let n = _fb_opcode_name(c);
    if n.len() > 0 && compare.str_compare(n, name) == 0 {
      return c;
    }
    c = c + 1;
  }
  return -1;
}

/// Registered name of a numeric opcode, or "".
/// Params: code - the numeric opcode.
/// Returns: the name; "" when the code is not registered.
/// Error case: none.
/// Complexity: O(table).
pub fn firebird_opcode_name(code: Int) -> Str {
  return _fb_opcode_name(code);
}

/// True when a numeric opcode is registered.
/// Params: code - the numeric opcode.
/// Returns: the flag.
/// Error case: none.
/// Complexity: O(table).
pub fn firebird_opcode_known(code: Int) -> Bool {
  return _fb_opcode_name(code).len() > 0;
}

/// Number of opcodes in the documented table.
/// Params: none.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(table).
pub fn firebird_opcode_count() -> Int {
  var c = 0;
  var n = 0;
  while c < 256 {
    if _fb_opcode_name(c).len() > 0 {
      n = n + 1;
    }
    c = c + 1;
  }
  return n;
}

/// Opcode of a raw packet, or -1 when there are fewer than four bytes.
/// Params: bytes - the packet bytes (the body starts with the 32-bit
/// big-endian opcode).
/// Returns: the opcode; -1 for a short packet.
/// Error case: none.
/// Complexity: O(1).
pub fn firebird_packet_opcode(bytes: &Vec[UInt8]) -> Int {
  if bytes.len() < 4 {
    return -1;
  }
  let b0: UInt8 = bytes[0];
  let b1: UInt8 = bytes[1];
  let b2: UInt8 = bytes[2];
  let b3: UInt8 = bytes[3];
  return ((b0 as Int) & 255) * 16777216 + ((b1 as Int) & 255) * 65536
    + ((b2 as Int) & 255) * 256 + ((b3 as Int) & 255);
}

// --------------------------------------------------
//  Fieldless packets
// --------------------------------------------------

/// Emit a packet whose opcode carries no fields: reject, disconnect, dummy,
/// ping, abort_aux_connection and batch_sync.
/// Params: op - the opcode.
/// Returns: Ok(bytes) with the four opcode bytes.
/// Error case: Err("firebird: not a fieldless opcode <n>") for any other
/// code.
/// Complexity: O(1).
pub fn firebird_empty_packet_emit(op: Int) -> Result[Vec[UInt8], Str] {
  if op != 4 && op != 6 && op != 71 && op != 93 && op != 95 && op != 110 {
    return _err_bytes("firebird: not a fieldless opcode " + int_to_string(op));
  }
  var out = Vec[UInt8].new();
  _fb_push_u32(&mut out, op);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Connect block
// --------------------------------------------------

/// A fresh connect block: operation 0, connect version 3, arch_generic (1),
/// empty file and user id, and no offered protocols.
/// Params: none.
/// Returns: the block.
/// Error case: none.
/// Complexity: O(1).
pub fn firebird_connect_new() -> FbConnect {
  return FbConnect{
    operation: 0;
    cversion: 3;
    client_arch: 1;
    file: "";
    user_id: "";
    protocols: Vec[Int].new();
    archs: Vec[Int].new();
    min_types: Vec[Int].new();
    max_types: Vec[Int].new();
    weights: Vec[Int].new();
  };
}

/// Append one offered protocol entry to all five parallel arrays.
/// Params: c - the block to mutate; protocol - the protocol version
/// (for example 0x800F); arch - the P_ARCH value; min_type / max_type - the
/// protocol type bounds; weight - the preference weight.
/// Returns: nothing.
/// Error case: none (values are stored as given; the emitter validates).
/// Complexity: O(1).
pub fn firebird_connect_add_version(c: &mut FbConnect, protocol: Int, arch: Int, min_type: Int, max_type: Int, weight: Int) {
  c.protocols.push(protocol);
  c.archs.push(arch);
  c.min_types.push(min_type);
  c.max_types.push(max_type);
  c.weights.push(weight);
}

// Shortest of the five version arrays.
fn _fb_version_count(c: &FbConnect) -> Int {
  var n: Int = c.protocols.len();
  if c.archs.len() < n {
    n = c.archs.len();
  }
  if c.min_types.len() < n {
    n = c.min_types.len();
  }
  if c.max_types.len() < n {
    n = c.max_types.len();
  }
  if c.weights.len() < n {
    n = c.weights.len();
  }
  return n;
}

/// Serialize a connect block.
/// Params: c - the block.
/// Returns: Ok(bytes) with the op_connect packet: operation, cversion,
/// client_arch, file, version count, user_id, then five words per version.
/// Error case: Err("firebird: field out of range <v>") when a word exceeds
/// its wire width; Err("firebird: too many connect versions <n>") above 11;
/// Err("firebird: misaligned connect versions") when fewer than all five
/// arrays carry the same number of entries.
/// Complexity: O(total string length).
pub fn firebird_connect_emit(c: &FbConnect) -> Result[Vec[UInt8], Str] {
  let op: Int = c.operation;
  let cv: Int = c.cversion;
  let arch: Int = c.client_arch;
  if !_fb_u32_ok(op) {
    return _err_bytes("firebird: field out of range " + int_to_string(op));
  }
  if !_fb_u16_ok(cv) {
    return _err_bytes("firebird: field out of range " + int_to_string(cv));
  }
  if !_fb_u16_ok(arch) {
    return _err_bytes("firebird: field out of range " + int_to_string(arch));
  }
  if c.protocols.len() > _FB_MAX_VERSIONS {
    return _err_bytes("firebird: too many connect versions " + int_to_string(c.protocols.len()));
  }
  if c.archs.len() != c.protocols.len() || c.min_types.len() != c.protocols.len()
    || c.max_types.len() != c.protocols.len() || c.weights.len() != c.protocols.len() {
    return _err_bytes("firebird: misaligned connect versions");
  }
  var i = 0;
  let n = c.protocols.len();
  while i < n {
    let p: Int = c.protocols[i];
    let a: Int = c.archs[i];
    let mn: Int = c.min_types[i];
    let mx: Int = c.max_types[i];
    let w: Int = c.weights[i];
    if !_fb_u16_ok(p) || !_fb_u16_ok(a) || !_fb_u16_ok(mn) || !_fb_u16_ok(mx) || !_fb_u16_ok(w) {
      return _err_bytes("firebird: field out of range in connect version " + int_to_string(i));
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _fb_push_u32(&mut out, 1);
  _fb_push_u32(&mut out, op);
  _fb_push_u32(&mut out, cv);
  _fb_push_u32(&mut out, arch);
  _fb_push_cstring(&mut out, c.file);
  _fb_push_u32(&mut out, n);
  _fb_push_cstring(&mut out, c.user_id);
  i = 0;
  while i < n {
    let p: Int = c.protocols[i];
    let a: Int = c.archs[i];
    let mn: Int = c.min_types[i];
    let mx: Int = c.max_types[i];
    let w: Int = c.weights[i];
    _fb_push_u32(&mut out, p);
    _fb_push_u32(&mut out, a);
    _fb_push_u32(&mut out, mn);
    _fb_push_u32(&mut out, mx);
    _fb_push_u32(&mut out, w);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Parse a connect block.
/// Params: bytes - the packet.
/// Returns: Ok(FbConnect) with all offered versions; trailing bytes after
/// the block are ignored.
/// Error case: Err("firebird: truncated packet") for a short or cut packet;
/// Err("firebird: unexpected opcode <n>") when the packet is not op_connect;
/// Err("firebird: too many connect versions <n>") above 11.
/// Complexity: O(total string length).
pub fn firebird_connect_parse(bytes: Vec[UInt8]) -> Result[FbConnect, Str] {
  let op = firebird_packet_opcode(&bytes);
  if op < 0 {
    return _err_connect("firebird: truncated packet");
  }
  if op != 1 {
    return _err_connect("firebird: unexpected opcode " + int_to_string(op));
  }
  let r = _fb_reader(bytes);
  _fb_u32(&mut r);
  let operation = _fb_u32(&mut r);
  let cversion = _fb_u32(&mut r);
  let client_arch = _fb_u32(&mut r);
  let file = _fb_cstring(&mut r);
  let count = _fb_u32(&mut r);
  if count > _FB_MAX_VERSIONS {
    return _err_connect("firebird: too many connect versions " + int_to_string(count));
  }
  let user_id = _fb_cstring(&mut r);
  var protocols = Vec[Int].new();
  var archs = Vec[Int].new();
  var min_types = Vec[Int].new();
  var max_types = Vec[Int].new();
  var weights = Vec[Int].new();
  var i = 0;
  while i < count {
    let p = _fb_u32(&mut r);
    let a = _fb_u32(&mut r);
    let mn = _fb_u32(&mut r);
    let mx = _fb_u32(&mut r);
    let w = _fb_u32(&mut r);
    protocols.push(p);
    archs.push(a);
    min_types.push(mn);
    max_types.push(mx);
    weights.push(w);
    i = i + 1;
  }
  let e: Int = r.err;
  if e != _FB_ERR_NONE {
    return _err_connect(_fb_reader_message(e));
  }
  return _ok_connect(FbConnect{
    operation: operation;
    cversion: cversion;
    client_arch: client_arch;
    file: file;
    user_id: user_id;
    protocols: protocols;
    archs: archs;
    min_types: min_types;
    max_types: max_types;
    weights: weights;
  });
}

// --------------------------------------------------
//  Accept block
// --------------------------------------------------

/// Serialize an accept block.
/// Params: version - the chosen protocol version; architecture - the chosen
/// P_ARCH value; ptype - the chosen protocol type.
/// Returns: Ok(bytes) with the op_accept packet.
/// Error case: Err("firebird: field out of range <n>") when a field exceeds
/// 65535.
/// Complexity: O(1).
pub fn firebird_accept_emit(version: Int, architecture: Int, ptype: Int) -> Result[Vec[UInt8], Str] {
  if !_fb_u16_ok(version) {
    return _err_bytes("firebird: field out of range " + int_to_string(version));
  }
  if !_fb_u16_ok(architecture) {
    return _err_bytes("firebird: field out of range " + int_to_string(architecture));
  }
  if !_fb_u16_ok(ptype) {
    return _err_bytes("firebird: field out of range " + int_to_string(ptype));
  }
  var out = Vec[UInt8].new();
  _fb_push_u32(&mut out, 3);
  _fb_push_u32(&mut out, version);
  _fb_push_u32(&mut out, architecture);
  _fb_push_u32(&mut out, ptype);
  return _ok_bytes(out);
}

/// Parse an accept block.
/// Params: bytes - the packet.
/// Returns: Ok(FbAccept).
/// Error case: Err("firebird: truncated packet");
/// Err("firebird: unexpected opcode <n>").
/// Complexity: O(1).
pub fn firebird_accept_parse(bytes: Vec[UInt8]) -> Result[FbAccept, Str] {
  let op = firebird_packet_opcode(&bytes);
  if op < 0 {
    return _err_accept("firebird: truncated packet");
  }
  if op != 3 {
    return _err_accept("firebird: unexpected opcode " + int_to_string(op));
  }
  let r = _fb_reader(bytes);
  _fb_u32(&mut r);
  let version = _fb_u32(&mut r);
  let architecture = _fb_u32(&mut r);
  let ptype = _fb_u32(&mut r);
  let e: Int = r.err;
  if e != _FB_ERR_NONE {
    return _err_accept(_fb_reader_message(e));
  }
  return _ok_accept(FbAccept{ version: version; architecture: architecture; ptype: ptype; });
}

// --------------------------------------------------
//  Attach block
// --------------------------------------------------

// True when `op` may carry an attach block.
fn _fb_attach_op_ok(op: Int) -> Bool {
  return op == 19 || op == 20 || op == 82;
}

/// Serialize an attach/create/service-attach block.
/// Params: op - attach (19), create (20) or service_attach (82);
/// database - the database object; file - the file name; dpb - the database
/// parameter block.
/// Returns: Ok(bytes) with the packet.
/// Error case: Err("firebird: not an attach opcode <n>");
/// Err("firebird: field out of range <n>").
/// Complexity: O(total string length).
pub fn firebird_attach_emit(op: Int, database: Int, file: Str, dpb: Str) -> Result[Vec[UInt8], Str] {
  if !_fb_attach_op_ok(op) {
    return _err_bytes("firebird: not an attach opcode " + int_to_string(op));
  }
  if !_fb_u32_ok(database) {
    return _err_bytes("firebird: field out of range " + int_to_string(database));
  }
  var out = Vec[UInt8].new();
  _fb_push_u32(&mut out, op);
  _fb_push_u32(&mut out, database);
  _fb_push_cstring(&mut out, file);
  _fb_push_cstring(&mut out, dpb);
  return _ok_bytes(out);
}

/// Parse an attach/create/service-attach block.
/// Params: bytes - the packet.
/// Returns: Ok(FbAttach).
/// Error case: Err("firebird: truncated packet");
/// Err("firebird: not an attach opcode <n>").
/// Complexity: O(total string length).
pub fn firebird_attach_parse(bytes: Vec[UInt8]) -> Result[FbAttach, Str] {
  let op = firebird_packet_opcode(&bytes);
  if op < 0 {
    return _err_attach("firebird: truncated packet");
  }
  if !_fb_attach_op_ok(op) {
    return _err_attach("firebird: not an attach opcode " + int_to_string(op));
  }
  let r = _fb_reader(bytes);
  _fb_u32(&mut r);
  let database = _fb_u32(&mut r);
  let file = _fb_cstring(&mut r);
  let dpb = _fb_cstring(&mut r);
  let e: Int = r.err;
  if e != _FB_ERR_NONE {
    return _err_attach(_fb_reader_message(e));
  }
  return _ok_attach(FbAttach{ op: op; database: database; file: file; dpb: dpb; });
}

// --------------------------------------------------
//  Data block
// --------------------------------------------------

// True when `op` may carry a data block.
fn _fb_data_op_ok(op: Int) -> Bool {
  return op == 23 || op == 24 || op == 25 || op == 26 || op == 73 || op == 74;
}

/// Serialize a data block.
/// Params: op - start (23), start_and_send (24), send (25), receive (26),
/// start_and_receive (73) or start_send_and_receive (74); request - the
/// request object; incarnation - its incarnation; transaction - the
/// transaction object; message_number - the message index; messages - the
/// message count.
/// Returns: Ok(bytes) with the packet.
/// Error case: Err("firebird: not a data opcode <n>");
/// Err("firebird: field out of range <n>").
/// Complexity: O(1).
pub fn firebird_data_emit(op: Int, request: Int, incarnation: Int, transaction: Int, message_number: Int, messages: Int) -> Result[Vec[UInt8], Str] {
  if !_fb_data_op_ok(op) {
    return _err_bytes("firebird: not a data opcode " + int_to_string(op));
  }
  if !_fb_u32_ok(request) {
    return _err_bytes("firebird: field out of range " + int_to_string(request));
  }
  if !_fb_u32_ok(incarnation) {
    return _err_bytes("firebird: field out of range " + int_to_string(incarnation));
  }
  if !_fb_u32_ok(transaction) {
    return _err_bytes("firebird: field out of range " + int_to_string(transaction));
  }
  if !_fb_u32_ok(message_number) {
    return _err_bytes("firebird: field out of range " + int_to_string(message_number));
  }
  if !_fb_u32_ok(messages) {
    return _err_bytes("firebird: field out of range " + int_to_string(messages));
  }
  var out = Vec[UInt8].new();
  _fb_push_u32(&mut out, op);
  _fb_push_u32(&mut out, request);
  _fb_push_u32(&mut out, incarnation);
  _fb_push_u32(&mut out, transaction);
  _fb_push_u32(&mut out, message_number);
  _fb_push_u32(&mut out, messages);
  return _ok_bytes(out);
}

/// Parse a data block.
/// Params: bytes - the packet.
/// Returns: Ok(FbData).
/// Error case: Err("firebird: truncated packet");
/// Err("firebird: not a data opcode <n>").
/// Complexity: O(1).
pub fn firebird_data_parse(bytes: Vec[UInt8]) -> Result[FbData, Str] {
  let op = firebird_packet_opcode(&bytes);
  if op < 0 {
    return _err_data("firebird: truncated packet");
  }
  if !_fb_data_op_ok(op) {
    return _err_data("firebird: not a data opcode " + int_to_string(op));
  }
  let r = _fb_reader(bytes);
  _fb_u32(&mut r);
  let request = _fb_u32(&mut r);
  let incarnation = _fb_u32(&mut r);
  let transaction = _fb_u32(&mut r);
  let message_number = _fb_u32(&mut r);
  let messages = _fb_u32(&mut r);
  let e: Int = r.err;
  if e != _FB_ERR_NONE {
    return _err_data(_fb_reader_message(e));
  }
  return _ok_data(FbData{
    op: op;
    request: request;
    incarnation: incarnation;
    transaction: transaction;
    message_number: message_number;
    messages: messages;
  });
}

// --------------------------------------------------
//  Single-object release block
// --------------------------------------------------

// True when `op` may carry a single-object release block.
fn _fb_object_op_ok(op: Int) -> Bool {
  if op == 21 || op == 28 || op == 30 || op == 31 || op == 32 {
    return true;
  }
  if op == 38 || op == 39 || op == 50 || op == 62 || op == 81 {
    return true;
  }
  if op == 83 || op == 86 || op == 102 || op == 109 {
    return true;
  }
  return false;
}

/// Serialize a single-object block.
/// Params: op - detach (21), release (28), commit (30), rollback (31),
/// prepare (32), cancel_blob (38), close_blob (39), commit_retaining (50),
/// allocate_statement (62), drop_database (81), service_detach (83),
/// rollback_retaining (86), batch_rls (102) or batch_cancel (109);
/// object - the object handle.
/// Returns: Ok(bytes) with the packet.
/// Error case: Err("firebird: not a release opcode <n>");
/// Err("firebird: field out of range <n>").
/// Complexity: O(1).
pub fn firebird_object_emit(op: Int, object: Int) -> Result[Vec[UInt8], Str] {
  if !_fb_object_op_ok(op) {
    return _err_bytes("firebird: not a release opcode " + int_to_string(op));
  }
  if !_fb_u32_ok(object) {
    return _err_bytes("firebird: field out of range " + int_to_string(object));
  }
  var out = Vec[UInt8].new();
  _fb_push_u32(&mut out, op);
  _fb_push_u32(&mut out, object);
  return _ok_bytes(out);
}

/// Parse a single-object block.
/// Params: bytes - the packet.
/// Returns: Ok(FbObject).
/// Error case: Err("firebird: truncated packet");
/// Err("firebird: not a release opcode <n>").
/// Complexity: O(1).
pub fn firebird_object_parse(bytes: Vec[UInt8]) -> Result[FbObject, Str] {
  let op = firebird_packet_opcode(&bytes);
  if op < 0 {
    return _err_object("firebird: truncated packet");
  }
  if !_fb_object_op_ok(op) {
    return _err_object("firebird: not a release opcode " + int_to_string(op));
  }
  let r = _fb_reader(bytes);
  _fb_u32(&mut r);
  let object = _fb_u32(&mut r);
  let e: Int = r.err;
  if e != _FB_ERR_NONE {
    return _err_object(_fb_reader_message(e));
  }
  return _ok_object(FbObject{ op: op; object: object; });
}

// --------------------------------------------------
//  Start-transaction block
// --------------------------------------------------

// True when `op` may carry a start-transaction block.
fn _fb_tran_op_ok(op: Int) -> Bool {
  return op == 29 || op == 33;
}

/// Serialize a start-transaction / reconnect block.
/// Params: op - transaction (29) or reconnect (33); database - the database
/// object; tpb - the transaction parameter block.
/// Returns: Ok(bytes) with the packet.
/// Error case: Err("firebird: not a transaction opcode <n>");
/// Err("firebird: field out of range <n>").
/// Complexity: O(total string length).
pub fn firebird_transaction_emit(op: Int, database: Int, tpb: Str) -> Result[Vec[UInt8], Str] {
  if !_fb_tran_op_ok(op) {
    return _err_bytes("firebird: not a transaction opcode " + int_to_string(op));
  }
  if !_fb_u32_ok(database) {
    return _err_bytes("firebird: field out of range " + int_to_string(database));
  }
  var out = Vec[UInt8].new();
  _fb_push_u32(&mut out, op);
  _fb_push_u32(&mut out, database);
  _fb_push_cstring(&mut out, tpb);
  return _ok_bytes(out);
}

/// Parse a start-transaction / reconnect block.
/// Params: bytes - the packet.
/// Returns: Ok(FbTransaction).
/// Error case: Err("firebird: truncated packet");
/// Err("firebird: not a transaction opcode <n>").
/// Complexity: O(total string length).
pub fn firebird_transaction_parse(bytes: Vec[UInt8]) -> Result[FbTransaction, Str] {
  let op = firebird_packet_opcode(&bytes);
  if op < 0 {
    return _err_tran("firebird: truncated packet");
  }
  if !_fb_tran_op_ok(op) {
    return _err_tran("firebird: not a transaction opcode " + int_to_string(op));
  }
  let r = _fb_reader(bytes);
  _fb_u32(&mut r);
  let database = _fb_u32(&mut r);
  let tpb = _fb_cstring(&mut r);
  let e: Int = r.err;
  if e != _FB_ERR_NONE {
    return _err_tran(_fb_reader_message(e));
  }
  return _ok_tran(FbTransaction{ op: op; database: database; tpb: tpb; });
}
