// XIOM -- xiom.memcached: memcached text and binary protocol codec (no sockets)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no session state) encoder/parser for a
// documented subset of the memcached protocol:
//
//   * text protocol: storage commands (set/add/replace/append/prepend/cas),
//     retrieval (get/gets with one or more keys), delete, incr/decr, touch,
//     stats, flush_all, version and quit, plus the single-line response
//     statuses and the multi-line VALUE/END retrieval response;
//   * binary protocol: the 24-byte header (magic 0x80 request / 0x81
//     response), the GET/SET/ADD/REPLACE/DELETE/INCR/DECR/QUIT/FLUSH/NOOP/
//     VERSION/GETK/GETKQ opcodes, the SET and INCR/DECR extras layouts, the
//     status code table and packet/header parsing with consumed counts.
//
// Every parser takes an explicit byte offset, rejects truncation, bad sizes
// and non-numeric length fields with deterministic Err(Str) messages, and
// reports how many bytes it consumed. Data blocks are binary-safe: payload
// bytes never pass through a Str. See SPEC.md for the byte layout tables,
// the error catalog and the documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside larger functions miscompiles);
//   * free functions only, no Vec[fn], no [T, U] callbacks, no struct methods;
//   * Str values are never compared with `==` (BUG 17: `==` on a Str read
//     from a Vec[Str] lowers to a pointer comparison); every comparison goes
//     through xiom.string.compare;
//   * every byte read from a Vec[UInt8] widens with `(data[pos] as Int) &
//     0xFF` before it enters Int arithmetic or comparisons;
//   * Vec element reads are bound to typed locals first, and `&struct.field`
//     is bound to a local before it is passed to a `&Vec[UInt8]` parameter;
//   * flag extraction uses division/modulo only; no bit shifts are relied on;
//   * output bytes are collected in Vec[UInt8] and text is appended with
//     xiom.string.builder (never through a Str for binary payloads).

module xiom.memcached

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// CRLF framing bytes (UInt8 for direct compares, Int for widened loops).
const _CR: UInt8 = 13u8;
const _LF: UInt8 = 10u8;
const _I_CR: Int = 13;
const _I_LF: Int = 10;
const _I_SPACE: Int = 32;
const _I_DEL: Int = 127;

// Protocol limits. memcached keys are at most 250 bytes; the default maximum
// item size is 1 MiB, which bounds every declared data block.
const _MAX_KEY: Int = 250;
const _MAX_DATA: Int = 1048576;
const _MAX_U32: Int = 4294967295;

// Text verb ids (0 = unknown).
const _V_SET: Int = 1;
const _V_ADD: Int = 2;
const _V_REPLACE: Int = 3;
const _V_APPEND: Int = 4;
const _V_PREPEND: Int = 5;
const _V_CAS: Int = 6;
const _V_GET: Int = 7;
const _V_GETS: Int = 8;
const _V_DELETE: Int = 9;
const _V_INCR: Int = 10;
const _V_DECR: Int = 11;
const _V_TOUCH: Int = 12;
const _V_STATS: Int = 13;
const _V_FLUSH: Int = 14;
const _V_VERSION: Int = 15;
const _V_QUIT: Int = 16;

// Text response status ids (0 = unknown). These are codec-local ids; the
// wire spellings are the tabulated keywords.
const _S_STORED: Int = 1;
const _S_NOT_STORED: Int = 2;
const _S_EXISTS: Int = 3;
const _S_NOT_FOUND: Int = 4;
const _S_DELETED: Int = 5;
const _S_TOUCHED: Int = 6;
const _S_OK: Int = 7;
const _S_ERROR: Int = 8;
const _S_CLIENT_ERROR: Int = 9;
const _S_SERVER_ERROR: Int = 10;
const _S_VERSION: Int = 11;
const _S_END: Int = 12;
const _S_VALUE: Int = 13;

// Binary protocol constants.
const _BIN_REQ: Int = 128;
const _BIN_RES: Int = 129;
const _BIN_HEADER: Int = 24;

// Binary opcodes.
const _BIN_OP_GET: Int = 0;
const _BIN_OP_SET: Int = 1;
const _BIN_OP_ADD: Int = 2;
const _BIN_OP_REPLACE: Int = 3;
const _BIN_OP_DELETE: Int = 4;
const _BIN_OP_INCR: Int = 5;
const _BIN_OP_DECR: Int = 6;
const _BIN_OP_QUIT: Int = 7;
const _BIN_OP_FLUSH: Int = 8;
const _BIN_OP_NOOP: Int = 10;
const _BIN_OP_VERSION: Int = 11;
const _BIN_OP_GETK: Int = 12;
const _BIN_OP_GETKQ: Int = 13;

// Text storage flags: bits 0x2 (compressed) and 0x4 (serialized) are the two
// low flags documented by common client libraries; everything above them is
// the caller's user flags.
const _FLAG_COMPRESSED: Int = 2;
const _FLAG_SERIALIZED: Int = 4;

// ---------------------------------------------------------------------------
// Result constructors (see the module header)
// ---------------------------------------------------------------------------

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

// Ok(v) for Result[(Int, Int), Str].
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] {
  return Ok(v);
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// Ok(v) for Result[TextCommand, Str].
fn _ok_cmd(v: TextCommand) -> Result[TextCommand, Str] {
  return Ok(v);
}

// Err(m) for Result[TextCommand, Str].
fn _err_cmd(m: Str) -> Result[TextCommand, Str] {
  return Err(m);
}

// Ok(v) for Result[TextGetResponse, Str].
fn _ok_get(v: TextGetResponse) -> Result[TextGetResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[TextGetResponse, Str].
fn _err_get(m: Str) -> Result[TextGetResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[BinHeader, Str].
fn _ok_header(v: BinHeader) -> Result[BinHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[BinHeader, Str].
fn _err_header(m: Str) -> Result[BinHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[BinPacket, Str].
fn _ok_packet(v: BinPacket) -> Result[BinPacket, Str] {
  return Ok(v);
}

// Err(m) for Result[BinPacket, Str].
fn _err_packet(m: Str) -> Result[BinPacket, Str] {
  return Err(m);
}

// Ok(v) for Result[BinSetExtras, Str].
fn _ok_setex(v: BinSetExtras) -> Result[BinSetExtras, Str] {
  return Ok(v);
}

// Err(m) for Result[BinSetExtras, Str].
fn _err_setex(m: Str) -> Result[BinSetExtras, Str] {
  return Err(m);
}

// Ok(v) for Result[BinDeltaExtras, Str].
fn _ok_dex(v: BinDeltaExtras) -> Result[BinDeltaExtras, Str] {
  return Ok(v);
}

// Err(m) for Result[BinDeltaExtras, Str].
fn _err_dex(m: Str) -> Result[BinDeltaExtras, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// One parsed memcached text command. `verb` is the canonical lowercase verb
/// (parsing is case-insensitive), `keys` holds every key of a get/gets
/// command or the single key of the other commands, and `consumed` is the
/// number of bytes consumed from the parse offset (the command line plus, for
/// storage commands, the data block and its trailing CRLF). Fields not
/// carried by a verb keep their neutral values: `flags`/`exptime` are 0,
/// `cas_id`/`delta`/`delay` are -1, `noreply` is false, `data` is empty and
/// `arg` is "" (only `stats` sets `arg`).
pub type TextCommand = {
  verb: Str;
  keys: Vec[Vec[UInt8]];
  flags: Int;
  exptime: Int;
  cas_id: Int;
  delta: Int;
  delay: Int;
  noreply: Bool;
  data: Vec[UInt8];
  arg: Str;
  consumed: Int;
}

/// One parsed retrieval response: the `VALUE` header fields and the data
/// blocks. `keys`, `flags` and `cas` are index-aligned (one entry per VALUE
/// line; `cas` is -1 for a `get` response). `pool` concatenates every data
/// block and `spans` holds two Ints per value (start, length into `pool`),
/// so the value count is `keys.len()` and there is no parallel-Vec drift.
/// `consumed` counts from the parse offset through the terminating `END`.
pub type TextGetResponse = {
  keys: Vec[Vec[UInt8]];
  flags: Vec[Int];
  cas: Vec[Int];
  pool: Vec[UInt8];
  spans: Vec[Int];
  consumed: Int;
}

/// One parsed 24-byte binary header. `magic` is 0x80 (request) or 0x81
/// (response); `status` carries the response status and is the vbucket id on
/// requests; `total_body` is the encoded body length and `consumed` is 24.
/// `cas` is limited to 0..2^63-1 (see SPEC.md).
pub type BinHeader = {
  magic: Int;
  opcode: Int;
  key_len: Int;
  extras_len: Int;
  data_type: Int;
  status: Int;
  total_body: Int;
  opaque: Int;
  cas: Int;
  consumed: Int;
}

/// One parsed whole binary packet: the header fields plus the body split into
/// fresh `extras`, `key` and `value` byte vectors. `consumed` is
/// 24 + total_body.
pub type BinPacket = {
  magic: Int;
  opcode: Int;
  key_len: Int;
  extras_len: Int;
  data_type: Int;
  status: Int;
  opaque: Int;
  cas: Int;
  key: Vec[UInt8];
  extras: Vec[UInt8];
  value: Vec[UInt8];
  consumed: Int;
}

/// Decoded SET/ADD/REPLACE extras: `expiration` (wire name expiration) and
/// the client `flags` word.
pub type BinSetExtras = {
  exptime: Int;
  flags: Int;
}

/// Decoded INCR/DECR extras: `delta`, `initial` and `exptime`.
pub type BinDeltaExtras = {
  delta: Int;
  initial: Int;
  exptime: Int;
}

// ---------------------------------------------------------------------------
// Byte and text helpers
// ---------------------------------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// True when a and b are byte-equal (BUG 17 workaround: str_compare).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when a and b are byte-equal, ASCII case-insensitively.
fn _streq_ci(a: Str, b: Str) -> Bool {
  return compare.str_compare_ignore_case(a, b) == 0;
}

// ASCII uppercase of byte c widened to 0..255 (non-letters unchanged).
fn _upper_byte(c: Int) -> Int {
  if c >= 97 && c <= 122 {
    return c - 32;
  }
  return c;
}

// Bytes of an ASCII-only Str (protocol keywords and args, never payloads).
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// ASCII text of a byte vector known to contain no 0x00 byte (BUG 15).
fn _bytes_to_str(v: &Vec[UInt8]) -> Str {
  return builder.sb_to_str(v);
}

// True when the byte vectors are equal.
fn _bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the byte vectors are equal, ASCII case-insensitively.
fn _bytes_eq_ci(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x = (a[i] as Int) & 0xFF;
    let y = (b[i] as Int) & 0xFF;
    if _upper_byte(x) != _upper_byte(y) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Append every byte of `v` to `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append CR LF.
fn _push_crlf(out: &mut Vec[UInt8]) {
  out.push(_CR);
  out.push(_LF);
}

// Append one ASCII space.
fn _push_space(out: &mut Vec[UInt8]) {
  out.push(32 as UInt8);
}

// Fresh empty byte vector (used for the empty key/value arguments).
fn _empty_bytes() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

// Fresh one-key key list.
fn _one_key(key: Vec[UInt8]) -> Vec[Vec[UInt8]] {
  var out = Vec[Vec[UInt8]].new();
  out.push(key);
  return out;
}

// Copy data[start, end) into a fresh byte vector.
fn _slice_copy(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Index of the first ASCII space in [start, end), or `end` when there is
// none.
fn _first_space(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var i = start;
  while i < end {
    let b = _byte(data, i);
    if b == _I_SPACE {
      return i;
    }
    i = i + 1;
  }
  return end;
}

// Index of the CR of the first CRLF at or after `from`, or -1 when the buffer
// ends before a CRLF terminator.
fn _line_crlf(data: &Vec[UInt8], from: Int) -> Int {
  var i = from;
  while i + 1 < data.len() {
    let b = _byte(data, i);
    if b == _I_CR {
      if _byte(data, i + 1) == _I_LF {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// Split a line on single ASCII spaces. Empty tokens (from repeated spaces)
// are preserved, so the callers' numeric/key validation rejects them.
fn _split_tokens(line: &Vec[UInt8]) -> Vec[Vec[UInt8]] {
  var out = Vec[Vec[UInt8]].new();
  var start = 0;
  var i = 0;
  while i <= line.len() {
    var is_sep = i == line.len();
    if !is_sep {
      let b = (line[i] as Int) & 0xFF;
      is_sep = b == _I_SPACE;
    }
    if is_sep {
      var tok = Vec[UInt8].new();
      var j = start;
      while j < i {
        tok.push(line[j]);
        j = j + 1;
      }
      out.push(tok);
      start = i + 1;
    }
    i = i + 1;
  }
  return out;
}

// True when `key` is a legal memcached key for this codec: 1..250 bytes, no
// space (0x20), no C0 control byte and no DEL. Bytes >= 128 pass through, so
// keys are binary-safe.
fn _key_is_valid(key: &Vec[UInt8]) -> Bool {
  if key.len() == 0 || key.len() > _MAX_KEY {
    return false;
  }
  var i = 0;
  while i < key.len() {
    let b = (key[i] as Int) & 0xFF;
    if b <= _I_SPACE || b == _I_DEL {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the byte vector is a single printable ASCII token (no space, no
// control byte, no NUL): the shape of a stats argument.
fn _ascii_arg_ok(v: &Vec[UInt8]) -> Bool {
  if v.len() == 0 {
    return false;
  }
  var i = 0;
  while i < v.len() {
    let b = (v[i] as Int) & 0xFF;
    if b < 33 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Decimal digits only; empty input is invalid.
fn _all_digits(b: &Vec[UInt8]) -> Bool {
  if b.len() == 0 {
    return false;
  }
  var i = 0;
  while i < b.len() {
    let c = (b[i] as Int) & 0xFF;
    if c < 48 || c > 57 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Parse a decimal unsigned 64-bit value into an Int, rejecting non-numeric
// input and anything above 9223372036854775807. Err("memcached: bad
// integer") in every failure case.
fn _parse_u64(b: &Vec[UInt8]) -> Result[Int, Str] {
  if !_all_digits(b) {
    return _err_int("memcached: bad integer");
  }
  var v = 0;
  var i = 0;
  while i < b.len() {
    let c = (b[i] as Int) & 0xFF;
    let d = c - 48;
    if v > 922337203685477580 {
      return _err_int("memcached: bad integer");
    }
    if v == 922337203685477580 && d > 7 {
      return _err_int("memcached: bad integer");
    }
    v = v * 10 + d;
    i = i + 1;
  }
  return _ok_int(v);
}

// Parse a decimal unsigned 32-bit value (0..4294967295).
fn _parse_u32(b: &Vec[UInt8]) -> Result[Int, Str] {
  let r = _parse_u64(b);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Int = r.value;
  if v > _MAX_U32 {
    return _err_int("memcached: bad integer");
  }
  return _ok_int(v);
}

// ---------------------------------------------------------------------------
// Text command verbs
// ---------------------------------------------------------------------------

// Canonical lowercase storage verb -> storage verb id (0 = unknown).
fn _storage_verb_id(s: Str) -> Int {
  if _streq(s, "set") {
    return _V_SET;
  }
  if _streq(s, "add") {
    return _V_ADD;
  }
  if _streq(s, "replace") {
    return _V_REPLACE;
  }
  if _streq(s, "append") {
    return _V_APPEND;
  }
  if _streq(s, "prepend") {
    return _V_PREPEND;
  }
  if _streq(s, "cas") {
    return _V_CAS;
  }
  return 0;
}

// Canonical lowercase verb for an id ("" when the id is unknown).
fn _verb_name(vid: Int) -> Str {
  if vid == _V_SET {
    return "set";
  }
  if vid == _V_ADD {
    return "add";
  }
  if vid == _V_REPLACE {
    return "replace";
  }
  if vid == _V_APPEND {
    return "append";
  }
  if vid == _V_PREPEND {
    return "prepend";
  }
  if vid == _V_CAS {
    return "cas";
  }
  if vid == _V_GET {
    return "get";
  }
  if vid == _V_GETS {
    return "gets";
  }
  if vid == _V_DELETE {
    return "delete";
  }
  if vid == _V_INCR {
    return "incr";
  }
  if vid == _V_DECR {
    return "decr";
  }
  if vid == _V_TOUCH {
    return "touch";
  }
  if vid == _V_STATS {
    return "stats";
  }
  if vid == _V_FLUSH {
    return "flush_all";
  }
  if vid == _V_VERSION {
    return "version";
  }
  if vid == _V_QUIT {
    return "quit";
  }
  return "";
}

// Case-insensitive verb token -> verb id (0 = unknown).
fn _verb_id_bytes(tok: &Vec[UInt8]) -> Int {
  let l_set: Vec[UInt8] = _str_bytes("set");
  if _bytes_eq_ci(tok, &l_set) {
    return _V_SET;
  }
  let l_add: Vec[UInt8] = _str_bytes("add");
  if _bytes_eq_ci(tok, &l_add) {
    return _V_ADD;
  }
  let l_rep: Vec[UInt8] = _str_bytes("replace");
  if _bytes_eq_ci(tok, &l_rep) {
    return _V_REPLACE;
  }
  let l_app: Vec[UInt8] = _str_bytes("append");
  if _bytes_eq_ci(tok, &l_app) {
    return _V_APPEND;
  }
  let l_pre: Vec[UInt8] = _str_bytes("prepend");
  if _bytes_eq_ci(tok, &l_pre) {
    return _V_PREPEND;
  }
  let l_cas: Vec[UInt8] = _str_bytes("cas");
  if _bytes_eq_ci(tok, &l_cas) {
    return _V_CAS;
  }
  let l_get: Vec[UInt8] = _str_bytes("get");
  if _bytes_eq_ci(tok, &l_get) {
    return _V_GET;
  }
  let l_gets: Vec[UInt8] = _str_bytes("gets");
  if _bytes_eq_ci(tok, &l_gets) {
    return _V_GETS;
  }
  let l_del: Vec[UInt8] = _str_bytes("delete");
  if _bytes_eq_ci(tok, &l_del) {
    return _V_DELETE;
  }
  let l_inc: Vec[UInt8] = _str_bytes("incr");
  if _bytes_eq_ci(tok, &l_inc) {
    return _V_INCR;
  }
  let l_dec: Vec[UInt8] = _str_bytes("decr");
  if _bytes_eq_ci(tok, &l_dec) {
    return _V_DECR;
  }
  let l_tou: Vec[UInt8] = _str_bytes("touch");
  if _bytes_eq_ci(tok, &l_tou) {
    return _V_TOUCH;
  }
  let l_sta: Vec[UInt8] = _str_bytes("stats");
  if _bytes_eq_ci(tok, &l_sta) {
    return _V_STATS;
  }
  let l_flu: Vec[UInt8] = _str_bytes("flush_all");
  if _bytes_eq_ci(tok, &l_flu) {
    return _V_FLUSH;
  }
  let l_ver: Vec[UInt8] = _str_bytes("version");
  if _bytes_eq_ci(tok, &l_ver) {
    return _V_VERSION;
  }
  let l_qui: Vec[UInt8] = _str_bytes("quit");
  if _bytes_eq_ci(tok, &l_qui) {
    return _V_QUIT;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Text response statuses
// ---------------------------------------------------------------------------

// Case-insensitive status keyword -> status id (0 = unknown).
fn _status_id_bytes(tok: &Vec[UInt8]) -> Int {
  let l1: Vec[UInt8] = _str_bytes("STORED");
  if _bytes_eq_ci(tok, &l1) {
    return _S_STORED;
  }
  let l2: Vec[UInt8] = _str_bytes("NOT_STORED");
  if _bytes_eq_ci(tok, &l2) {
    return _S_NOT_STORED;
  }
  let l3: Vec[UInt8] = _str_bytes("EXISTS");
  if _bytes_eq_ci(tok, &l3) {
    return _S_EXISTS;
  }
  let l4: Vec[UInt8] = _str_bytes("NOT_FOUND");
  if _bytes_eq_ci(tok, &l4) {
    return _S_NOT_FOUND;
  }
  let l5: Vec[UInt8] = _str_bytes("DELETED");
  if _bytes_eq_ci(tok, &l5) {
    return _S_DELETED;
  }
  let l6: Vec[UInt8] = _str_bytes("TOUCHED");
  if _bytes_eq_ci(tok, &l6) {
    return _S_TOUCHED;
  }
  let l7: Vec[UInt8] = _str_bytes("OK");
  if _bytes_eq_ci(tok, &l7) {
    return _S_OK;
  }
  let l8: Vec[UInt8] = _str_bytes("ERROR");
  if _bytes_eq_ci(tok, &l8) {
    return _S_ERROR;
  }
  let l9: Vec[UInt8] = _str_bytes("CLIENT_ERROR");
  if _bytes_eq_ci(tok, &l9) {
    return _S_CLIENT_ERROR;
  }
  let l10: Vec[UInt8] = _str_bytes("SERVER_ERROR");
  if _bytes_eq_ci(tok, &l10) {
    return _S_SERVER_ERROR;
  }
  let l11: Vec[UInt8] = _str_bytes("VERSION");
  if _bytes_eq_ci(tok, &l11) {
    return _S_VERSION;
  }
  let l12: Vec[UInt8] = _str_bytes("END");
  if _bytes_eq_ci(tok, &l12) {
    return _S_END;
  }
  let l13: Vec[UInt8] = _str_bytes("VALUE");
  if _bytes_eq_ci(tok, &l13) {
    return _S_VALUE;
  }
  return 0;
}

/// Status id of a response keyword (case-insensitive), 0 when unknown:
/// 1 STORED, 2 NOT_STORED, 3 EXISTS, 4 NOT_FOUND, 5 DELETED, 6 TOUCHED,
/// 7 OK, 8 ERROR, 9 CLIENT_ERROR, 10 SERVER_ERROR, 11 VERSION, 12 END,
/// 13 VALUE. Complexity: O(keyword length).
pub fn text_status_id(name: Str) -> Int {
  let b: Vec[UInt8] = _str_bytes(name);
  return _status_id_bytes(&b);
}

/// Canonical keyword for a status id ("UNKNOWN" when the id is unknown).
/// Complexity: O(1).
pub fn text_status_name(sid: Int) -> Str {
  if sid == _S_STORED {
    return "STORED";
  }
  if sid == _S_NOT_STORED {
    return "NOT_STORED";
  }
  if sid == _S_EXISTS {
    return "EXISTS";
  }
  if sid == _S_NOT_FOUND {
    return "NOT_FOUND";
  }
  if sid == _S_DELETED {
    return "DELETED";
  }
  if sid == _S_TOUCHED {
    return "TOUCHED";
  }
  if sid == _S_OK {
    return "OK";
  }
  if sid == _S_ERROR {
    return "ERROR";
  }
  if sid == _S_CLIENT_ERROR {
    return "CLIENT_ERROR";
  }
  if sid == _S_SERVER_ERROR {
    return "SERVER_ERROR";
  }
  if sid == _S_VERSION {
    return "VERSION";
  }
  if sid == _S_END {
    return "END";
  }
  if sid == _S_VALUE {
    return "VALUE";
  }
  return "UNKNOWN";
}

// ---------------------------------------------------------------------------
// Text storage flags
// ---------------------------------------------------------------------------

/// Pack flags with the two documented low bits: bit 0x2 = compressed, bit
/// 0x4 = serialized. `user_flags` must be 0..4294967291 so the sum stays in
/// range (the codec does not mask silently). Complexity: O(1).
pub fn text_flags_pack(user_flags: Int, compressed: Bool, serialized: Bool) -> Int {
  var f = user_flags;
  if compressed {
    f = f + _FLAG_COMPRESSED;
  }
  if serialized {
    f = f + _FLAG_SERIALIZED;
  }
  return f;
}

/// The caller's user flags: `flags` with the documented compressed (0x2) and
/// serialized (0x4) bits cleared. Complexity: O(1).
pub fn text_flags_user(flags: Int) -> Int {
  var u = flags;
  if flags % 4 >= 2 {
    u = u - 2;
  }
  if (flags / 4) % 2 == 1 {
    u = u - 4;
  }
  return u;
}

/// True when the 0x2 (compressed) bit is set. Complexity: O(1).
pub fn text_flags_is_compressed(flags: Int) -> Bool {
  return flags % 4 >= 2;
}

/// True when the 0x4 (serialized) bit is set. Complexity: O(1).
pub fn text_flags_is_serialized(flags: Int) -> Bool {
  return (flags / 4) % 2 == 1;
}

// ---------------------------------------------------------------------------
// Text protocol: encoding
// ---------------------------------------------------------------------------

/// Encode a storage command (set/add/replace/append/prepend/cas). The wire
/// form is `<verb> <key> <flags> <exptime> <bytes> [<cas>] [noreply]CRLF`
/// followed by exactly `data.len()` bytes and CRLF; the data block is
/// binary-safe. `cas_id` must be -1 for every verb except `cas`, which
/// requires a non-negative id.
///
/// Err("memcached: bad storage command") for an unknown verb;
/// Err("memcached: bad key") for empty/over-long keys or keys with a space,
/// control byte or DEL; Err("memcached: bad flags") / Err("memcached: bad
/// exptime") when the value is outside 0..4294967295; Err("memcached: bad
/// cas id") when the cas argument disagrees with the verb.
/// Complexity: O(command size).
pub fn text_encode_storage(cmd: Str, key: &Vec[UInt8], flags: Int, exptime: Int, data: &Vec[UInt8], cas_id: Int, noreply: Bool) -> Result[Vec[UInt8], Str] {
  let vid = _storage_verb_id(cmd);
  if vid == 0 {
    return _err_bytes("memcached: bad storage command");
  }
  if !_key_is_valid(key) {
    return _err_bytes("memcached: bad key");
  }
  if flags < 0 || flags > _MAX_U32 {
    return _err_bytes("memcached: bad flags");
  }
  if exptime < 0 || exptime > _MAX_U32 {
    return _err_bytes("memcached: bad exptime");
  }
  if vid == _V_CAS {
    if cas_id < 0 {
      return _err_bytes("memcached: bad cas id");
    }
  } else {
    if cas_id != -1 {
      return _err_bytes("memcached: bad cas id");
    }
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, _verb_name(vid));
  _push_space(&mut out);
  _push_bytes(&mut out, key);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, flags);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, exptime);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, data.len());
  if vid == _V_CAS {
    _push_space(&mut out);
    builder.sb_push_int(&mut out, cas_id);
  }
  if noreply {
    builder.sb_push_str(&mut out, " noreply");
  }
  _push_crlf(&mut out);
  _push_bytes(&mut out, data);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a `set` command. Complexity: O(command size).
pub fn text_encode_set(key: &Vec[UInt8], flags: Int, exptime: Int, data: &Vec[UInt8], noreply: Bool) -> Result[Vec[UInt8], Str] {
  return text_encode_storage("set", key, flags, exptime, data, -1, noreply);
}

/// Encode an `add` command. Complexity: O(command size).
pub fn text_encode_add(key: &Vec[UInt8], flags: Int, exptime: Int, data: &Vec[UInt8], noreply: Bool) -> Result[Vec[UInt8], Str] {
  return text_encode_storage("add", key, flags, exptime, data, -1, noreply);
}

/// Encode a `replace` command. Complexity: O(command size).
pub fn text_encode_replace(key: &Vec[UInt8], flags: Int, exptime: Int, data: &Vec[UInt8], noreply: Bool) -> Result[Vec[UInt8], Str] {
  return text_encode_storage("replace", key, flags, exptime, data, -1, noreply);
}

/// Encode an `append` command. Complexity: O(command size).
pub fn text_encode_append(key: &Vec[UInt8], flags: Int, exptime: Int, data: &Vec[UInt8], noreply: Bool) -> Result[Vec[UInt8], Str] {
  return text_encode_storage("append", key, flags, exptime, data, -1, noreply);
}

/// Encode a `prepend` command. Complexity: O(command size).
pub fn text_encode_prepend(key: &Vec[UInt8], flags: Int, exptime: Int, data: &Vec[UInt8], noreply: Bool) -> Result[Vec[UInt8], Str] {
  return text_encode_storage("prepend", key, flags, exptime, data, -1, noreply);
}

/// Encode a `cas` command (`cas_id` >= 0). Complexity: O(command size).
pub fn text_encode_cas(key: &Vec[UInt8], flags: Int, exptime: Int, data: &Vec[UInt8], cas_id: Int, noreply: Bool) -> Result[Vec[UInt8], Str] {
  return text_encode_storage("cas", key, flags, exptime, data, cas_id, noreply);
}

/// Encode a retrieval command: `get k1 k2 ...CRLF`, or `gets ...` when
/// `with_cas` is true. At least one valid key is required.
///
/// Err("memcached: bad args") when `keys` is empty; Err("memcached: bad
/// key") for an invalid key. Complexity: O(command size).
pub fn text_encode_get(keys: &Vec[Vec[UInt8]], with_cas: Bool) -> Result[Vec[UInt8], Str] {
  if keys.len() == 0 {
    return _err_bytes("memcached: bad args");
  }
  var out = Vec[UInt8].new();
  if with_cas {
    builder.sb_push_str(&mut out, "gets");
  } else {
    builder.sb_push_str(&mut out, "get");
  }
  var i = 0;
  while i < keys.len() {
    let k: Vec[UInt8] = keys[i];
    if !_key_is_valid(&k) {
      return _err_bytes("memcached: bad key");
    }
    _push_space(&mut out);
    _push_bytes(&mut out, &k);
    i = i + 1;
  }
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a `delete <key> [noreply]CRLF` command.
/// Err("memcached: bad key") for an invalid key. Complexity: O(command size).
pub fn text_encode_delete(key: &Vec[UInt8], noreply: Bool) -> Result[Vec[UInt8], Str] {
  if !_key_is_valid(key) {
    return _err_bytes("memcached: bad key");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "delete");
  _push_space(&mut out);
  _push_bytes(&mut out, key);
  if noreply {
    builder.sb_push_str(&mut out, " noreply");
  }
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode an `incr`/`decr` command: `<verb> <key> <delta> [noreply]CRLF`.
/// `cmd` must be "incr" or "decr" and `delta` must be 0..2^63-1.
///
/// Err("memcached: bad delta command") for an unknown verb;
/// Err("memcached: bad delta") for a negative delta;
/// Err("memcached: bad key") for an invalid key. Complexity: O(command size).
pub fn text_encode_delta(cmd: Str, key: &Vec[UInt8], delta: Int, noreply: Bool) -> Result[Vec[UInt8], Str] {
  if !_streq(cmd, "incr") && !_streq(cmd, "decr") {
    return _err_bytes("memcached: bad delta command");
  }
  if delta < 0 {
    return _err_bytes("memcached: bad delta");
  }
  if !_key_is_valid(key) {
    return _err_bytes("memcached: bad key");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, cmd);
  _push_space(&mut out);
  _push_bytes(&mut out, key);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, delta);
  if noreply {
    builder.sb_push_str(&mut out, " noreply");
  }
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode an `incr` command. Complexity: O(command size).
pub fn text_encode_incr(key: &Vec[UInt8], delta: Int, noreply: Bool) -> Result[Vec[UInt8], Str] {
  return text_encode_delta("incr", key, delta, noreply);
}

/// Encode a `decr` command. Complexity: O(command size).
pub fn text_encode_decr(key: &Vec[UInt8], delta: Int, noreply: Bool) -> Result[Vec[UInt8], Str] {
  return text_encode_delta("decr", key, delta, noreply);
}

/// Encode a `touch <key> <exptime> [noreply]CRLF` command.
///
/// Err("memcached: bad key") for an invalid key; Err("memcached: bad
/// exptime") when `exptime` is outside 0..4294967295.
/// Complexity: O(command size).
pub fn text_encode_touch(key: &Vec[UInt8], exptime: Int, noreply: Bool) -> Result[Vec[UInt8], Str] {
  if !_key_is_valid(key) {
    return _err_bytes("memcached: bad key");
  }
  if exptime < 0 || exptime > _MAX_U32 {
    return _err_bytes("memcached: bad exptime");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "touch");
  _push_space(&mut out);
  _push_bytes(&mut out, key);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, exptime);
  if noreply {
    builder.sb_push_str(&mut out, " noreply");
  }
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a `stats [arg]CRLF` command. `arg` must be empty or a printable
/// ASCII token without spaces.
/// Err("memcached: bad args") for a bad argument. Complexity: O(command size).
pub fn text_encode_stats(arg: Str) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "stats");
  if arg.len() > 0 {
    let ab: Vec[UInt8] = _str_bytes(arg);
    if !_ascii_arg_ok(&ab) {
      return _err_bytes("memcached: bad args");
    }
    _push_space(&mut out);
    _push_bytes(&mut out, &ab);
  }
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a `flush_all [delay] [noreply]CRLF` command. `delay` must be -1
/// (omit the delay) or 0..4294967295.
/// Err("memcached: bad exptime") when `delay` is out of range.
/// Complexity: O(command size).
pub fn text_encode_flush_all(delay: Int, noreply: Bool) -> Result[Vec[UInt8], Str] {
  if delay < -1 || delay > _MAX_U32 {
    return _err_bytes("memcached: bad exptime");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "flush_all");
  if delay >= 0 {
    _push_space(&mut out);
    builder.sb_push_int(&mut out, delay);
  }
  if noreply {
    builder.sb_push_str(&mut out, " noreply");
  }
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a `versionCRLF` command. Complexity: O(1).
pub fn text_encode_version() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "version");
  _push_crlf(&mut out);
  return out;
}

/// Encode a `quitCRLF` command. Complexity: O(1).
pub fn text_encode_quit() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "quit");
  _push_crlf(&mut out);
  return out;
}

// ---------------------------------------------------------------------------
// Text protocol: single-command parsing
// ---------------------------------------------------------------------------

// Parse a storage command (tokens already split); `cr` is the index of the
// CRLF that terminates the command line.
fn _parse_storage_command(data: &Vec[UInt8], off: Int, cr: Int, tokens: &Vec[Vec[UInt8]], vid: Int) -> Result[TextCommand, Str] {
  var base = 5;
  if vid == _V_CAS {
    base = 6;
  }
  let n = tokens.len();
  if n != base && n != base + 1 {
    return _err_cmd("memcached: bad args");
  }
  let noreply = n == base + 1;
  if noreply {
    let last: Vec[UInt8] = tokens[base];
    let l_nr: Vec[UInt8] = _str_bytes("noreply");
    if !_bytes_eq_ci(&last, &l_nr) {
      return _err_cmd("memcached: bad args");
    }
  }
  let key_tok: Vec[UInt8] = tokens[1];
  if !_key_is_valid(&key_tok) {
    return _err_cmd("memcached: bad key");
  }
  let flags_tok: Vec[UInt8] = tokens[2];
  let fr = _parse_u32(&flags_tok);
  if !fr.is_ok {
    return _err_cmd(fr.error);
  }
  let exp_tok: Vec[UInt8] = tokens[3];
  let xr = _parse_u32(&exp_tok);
  if !xr.is_ok {
    return _err_cmd(xr.error);
  }
  let bytes_tok: Vec[UInt8] = tokens[4];
  let br = _parse_u32(&bytes_tok);
  if !br.is_ok {
    return _err_cmd(br.error);
  }
  let bytes: Int = br.value;
  if bytes > _MAX_DATA {
    return _err_cmd("memcached: bad bytes");
  }
  var cas_id = -1;
  if vid == _V_CAS {
    let cas_tok: Vec[UInt8] = tokens[5];
    let crr = _parse_u64(&cas_tok);
    if !crr.is_ok {
      return _err_cmd(crr.error);
    }
    cas_id = crr.value;
  }
  let dstart = cr + 2;
  if dstart + bytes + 2 > data.len() {
    return _err_cmd("memcached: truncated data");
  }
  let cb = _byte(data, dstart + bytes);
  let lb = _byte(data, dstart + bytes + 1);
  if cb != _I_CR || lb != _I_LF {
    return _err_cmd("memcached: bad data block");
  }
  var data_block = Vec[UInt8].new();
  var i = 0;
  while i < bytes {
    data_block.push(data[dstart + i]);
    i = i + 1;
  }
  var keys = Vec[Vec[UInt8]].new();
  keys.push(key_tok);
  var no_delta = -1;
  var no_delay = -1;
  var arg = "";
  return _ok_cmd(TextCommand{
    verb: _verb_name(vid);
    keys: keys;
    flags: fr.value;
    exptime: xr.value;
    cas_id: cas_id;
    delta: no_delta;
    delay: no_delay;
    noreply: noreply;
    data: data_block;
    arg: arg;
    consumed: dstart + bytes + 2 - off;
  });
}

// Parse a get/gets command.
fn _parse_get_command(off: Int, cr: Int, tokens: &Vec[Vec[UInt8]], vid: Int) -> Result[TextCommand, Str] {
  if tokens.len() < 2 {
    return _err_cmd("memcached: bad args");
  }
  var keys = Vec[Vec[UInt8]].new();
  var i = 1;
  while i < tokens.len() {
    let k: Vec[UInt8] = tokens[i];
    if !_key_is_valid(&k) {
      return _err_cmd("memcached: bad key");
    }
    keys.push(k);
    i = i + 1;
  }
  var no_bytes = Vec[UInt8].new();
  return _ok_cmd(TextCommand{
    verb: _verb_name(vid);
    keys: keys;
    flags: 0;
    exptime: 0;
    cas_id: -1;
    delta: -1;
    delay: -1;
    noreply: false;
    data: no_bytes;
    arg: "";
    consumed: cr + 2 - off;
  });
}

// Parse a delete command.
fn _parse_delete_command(off: Int, cr: Int, tokens: &Vec[Vec[UInt8]]) -> Result[TextCommand, Str] {
  let n = tokens.len();
  if n != 2 && n != 3 {
    return _err_cmd("memcached: bad args");
  }
  let noreply = n == 3;
  if noreply {
    let last: Vec[UInt8] = tokens[2];
    let l_nr: Vec[UInt8] = _str_bytes("noreply");
    if !_bytes_eq_ci(&last, &l_nr) {
      return _err_cmd("memcached: bad args");
    }
  }
  let key_tok: Vec[UInt8] = tokens[1];
  if !_key_is_valid(&key_tok) {
    return _err_cmd("memcached: bad key");
  }
  var no_bytes = Vec[UInt8].new();
  return _ok_cmd(TextCommand{
    verb: "delete";
    keys: _one_key(key_tok);
    flags: 0;
    exptime: 0;
    cas_id: -1;
    delta: -1;
    delay: -1;
    noreply: noreply;
    data: no_bytes;
    arg: "";
    consumed: cr + 2 - off;
  });
}

// Parse an incr/decr command.
fn _parse_delta_command(off: Int, cr: Int, tokens: &Vec[Vec[UInt8]], vid: Int) -> Result[TextCommand, Str] {
  let n = tokens.len();
  if n != 3 && n != 4 {
    return _err_cmd("memcached: bad args");
  }
  let noreply = n == 4;
  if noreply {
    let last: Vec[UInt8] = tokens[3];
    let l_nr: Vec[UInt8] = _str_bytes("noreply");
    if !_bytes_eq_ci(&last, &l_nr) {
      return _err_cmd("memcached: bad args");
    }
  }
  let key_tok: Vec[UInt8] = tokens[1];
  if !_key_is_valid(&key_tok) {
    return _err_cmd("memcached: bad key");
  }
  let d_tok: Vec[UInt8] = tokens[2];
  let dr = _parse_u64(&d_tok);
  if !dr.is_ok {
    return _err_cmd(dr.error);
  }
  var no_bytes = Vec[UInt8].new();
  return _ok_cmd(TextCommand{
    verb: _verb_name(vid);
    keys: _one_key(key_tok);
    flags: 0;
    exptime: 0;
    cas_id: -1;
    delta: dr.value;
    delay: -1;
    noreply: noreply;
    data: no_bytes;
    arg: "";
    consumed: cr + 2 - off;
  });
}

// Parse a touch command.
fn _parse_touch_command(off: Int, cr: Int, tokens: &Vec[Vec[UInt8]]) -> Result[TextCommand, Str] {
  let n = tokens.len();
  if n != 3 && n != 4 {
    return _err_cmd("memcached: bad args");
  }
  let noreply = n == 4;
  if noreply {
    let last: Vec[UInt8] = tokens[3];
    let l_nr: Vec[UInt8] = _str_bytes("noreply");
    if !_bytes_eq_ci(&last, &l_nr) {
      return _err_cmd("memcached: bad args");
    }
  }
  let key_tok: Vec[UInt8] = tokens[1];
  if !_key_is_valid(&key_tok) {
    return _err_cmd("memcached: bad key");
  }
  let x_tok: Vec[UInt8] = tokens[2];
  let xr = _parse_u32(&x_tok);
  if !xr.is_ok {
    return _err_cmd(xr.error);
  }
  var no_bytes = Vec[UInt8].new();
  return _ok_cmd(TextCommand{
    verb: "touch";
    keys: _one_key(key_tok);
    flags: 0;
    exptime: xr.value;
    cas_id: -1;
    delta: -1;
    delay: -1;
    noreply: noreply;
    data: no_bytes;
    arg: "";
    consumed: cr + 2 - off;
  });
}

// Parse a stats command.
fn _parse_stats_command(off: Int, cr: Int, tokens: &Vec[Vec[UInt8]]) -> Result[TextCommand, Str] {
  let n = tokens.len();
  if n != 1 && n != 2 {
    return _err_cmd("memcached: bad args");
  }
  var arg = "";
  if n == 2 {
    let a_tok: Vec[UInt8] = tokens[1];
    if !_ascii_arg_ok(&a_tok) {
      return _err_cmd("memcached: bad args");
    }
    arg = _bytes_to_str(&a_tok);
  }
  let empty_keys = Vec[Vec[UInt8]].new();
  var no_bytes = Vec[UInt8].new();
  return _ok_cmd(TextCommand{
    verb: "stats";
    keys: empty_keys;
    flags: 0;
    exptime: 0;
    cas_id: -1;
    delta: -1;
    delay: -1;
    noreply: false;
    data: no_bytes;
    arg: arg;
    consumed: cr + 2 - off;
  });
}

// Parse a flush_all command.
fn _parse_flush_command(off: Int, cr: Int, tokens: &Vec[Vec[UInt8]]) -> Result[TextCommand, Str] {
  let n = tokens.len();
  if n < 1 || n > 3 {
    return _err_cmd("memcached: bad args");
  }
  var delay = -1;
  var noreply = false;
  let l_nr: Vec[UInt8] = _str_bytes("noreply");
  if n == 2 {
    let t: Vec[UInt8] = tokens[1];
    if _bytes_eq_ci(&t, &l_nr) {
      noreply = true;
    } else {
      let dr = _parse_u32(&t);
      if !dr.is_ok {
        return _err_cmd(dr.error);
      }
      delay = dr.value;
    }
  }
  if n == 3 {
    let t: Vec[UInt8] = tokens[2];
    if !_bytes_eq_ci(&t, &l_nr) {
      return _err_cmd("memcached: bad args");
    }
    noreply = true;
    let d_tok: Vec[UInt8] = tokens[1];
    let dr = _parse_u32(&d_tok);
    if !dr.is_ok {
      return _err_cmd(dr.error);
    }
    delay = dr.value;
  }
  let empty_keys = Vec[Vec[UInt8]].new();
  var no_bytes = Vec[UInt8].new();
  return _ok_cmd(TextCommand{
    verb: "flush_all";
    keys: empty_keys;
    flags: 0;
    exptime: 0;
    cas_id: -1;
    delta: -1;
    delay: delay;
    noreply: noreply;
    data: no_bytes;
    arg: "";
    consumed: cr + 2 - off;
  });
}

// Parse version/quit (both take no arguments).
fn _parse_simple_command(off: Int, cr: Int, tokens: &Vec[Vec[UInt8]], vid: Int) -> Result[TextCommand, Str] {
  if tokens.len() != 1 {
    return _err_cmd("memcached: bad args");
  }
  let empty_keys = Vec[Vec[UInt8]].new();
  var no_bytes = Vec[UInt8].new();
  return _ok_cmd(TextCommand{
    verb: _verb_name(vid);
    keys: empty_keys;
    flags: 0;
    exptime: 0;
    cas_id: -1;
    delta: -1;
    delay: -1;
    noreply: false;
    data: no_bytes;
    arg: "";
    consumed: cr + 2 - off;
  });
}

/// Parse exactly one text command starting at `off`, returning the parsed
/// command together with the number of bytes consumed (command line plus the
/// storage data block when present). Trailing bytes in `data` are left for
/// the next call.
///
/// Errors (all deterministic): Err("memcached: negative offset");
/// Err("memcached: truncated line") when no CRLF is in range;
/// Err("memcached: bad command") for an unknown verb;
/// Err("memcached: bad args") for a wrong token count or a stray `noreply`;
/// Err("memcached: bad key") for an invalid key;
/// Err("memcached: bad integer") for a non-numeric or out-of-range length,
/// flags, exptime, delta or cas id; Err("memcached: bad bytes") when the
/// declared data length exceeds 1048576; Err("memcached: truncated data")
/// when the declared data block does not fit the buffer; Err("memcached:
/// bad data block") when the block is not CRLF-terminated.
/// Complexity: O(command size).
pub fn text_parse_command(data: &Vec[UInt8], off: Int) -> Result[TextCommand, Str] {
  if off < 0 {
    return _err_cmd("memcached: negative offset");
  }
  if off >= data.len() {
    return _err_cmd("memcached: truncated line");
  }
  let cr = _line_crlf(data, off);
  if cr < 0 {
    return _err_cmd("memcached: truncated line");
  }
  let line = _slice_copy(data, off, cr);
  let tokens = _split_tokens(&line);
  if tokens.len() == 0 {
    return _err_cmd("memcached: bad command");
  }
  let verb_tok: Vec[UInt8] = tokens[0];
  let vid = _verb_id_bytes(&verb_tok);
  if vid == 0 {
    return _err_cmd("memcached: bad command");
  }
  if vid >= _V_SET && vid <= _V_CAS {
    return _parse_storage_command(data, off, cr, &tokens, vid);
  }
  if vid == _V_GET || vid == _V_GETS {
    return _parse_get_command(off, cr, &tokens, vid);
  }
  if vid == _V_DELETE {
    return _parse_delete_command(off, cr, &tokens);
  }
  if vid == _V_INCR || vid == _V_DECR {
    return _parse_delta_command(off, cr, &tokens, vid);
  }
  if vid == _V_TOUCH {
    return _parse_touch_command(off, cr, &tokens);
  }
  if vid == _V_STATS {
    return _parse_stats_command(off, cr, &tokens);
  }
  if vid == _V_FLUSH {
    return _parse_flush_command(off, cr, &tokens);
  }
  return _parse_simple_command(off, cr, &tokens, vid);
}

// ---------------------------------------------------------------------------
// Text protocol: response parsing
// ---------------------------------------------------------------------------

/// Parse one single-line text response at `off`: the tabulated statuses
/// (`STORED`, `NOT_STORED`, `EXISTS`, `NOT_FOUND`, `DELETED`, `TOUCHED`,
/// `OK`, `ERROR`, `CLIENT_ERROR ...`, `SERVER_ERROR ...`, `VERSION ...`) plus
/// `END` and `VALUE` (the retrieval response handles VALUE lines itself).
/// Returns Ok((status_id, next_offset)) where `next_offset` is the offset
/// just past the CRLF; the detail text of CLIENT_ERROR/SERVER_ERROR/VERSION
/// is the bytes between the first space and the CRLF.
///
/// Err("memcached: negative offset"); Err("memcached: truncated line") when
/// no CRLF is in range; Err("memcached: bad response line") for an unknown
/// keyword. Complexity: O(line length).
pub fn text_parse_status(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str] {
  if off < 0 {
    return _err_pair("memcached: negative offset");
  }
  if off >= data.len() {
    return _err_pair("memcached: truncated line");
  }
  let cr = _line_crlf(data, off);
  if cr < 0 {
    return _err_pair("memcached: truncated line");
  }
  let e = _first_space(data, off, cr);
  let verb = _slice_copy(data, off, e);
  let sid = _status_id_bytes(&verb);
  if sid == 0 {
    return _err_pair("memcached: bad response line");
  }
  return _ok_pair((sid, cr + 2));
}

/// Parse a whole retrieval response at `off`: zero or more
/// `VALUE <key> <flags> <bytes> [<cas>]CRLF <bytes> CRLF` blocks followed by
/// `ENDCRLF`. Zero VALUE lines means a miss. The data blocks are copied
/// verbatim, so payloads are binary-safe.
///
/// Err("memcached: negative offset"); Err("memcached: truncated line") when
/// a line has no CRLF; Err("memcached: truncated response") when the buffer
/// ends before END; Err("memcached: bad response line") for a malformed
/// VALUE or END line; Err("memcached: bad key") for an invalid response key;
/// Err("memcached: bad integer") for a non-numeric flags/bytes/cas field;
/// Err("memcached: bad bytes") when the declared block exceeds 1048576;
/// Err("memcached: truncated data") when a block does not fit;
/// Err("memcached: bad data block") when a block is not CRLF-terminated.
/// Complexity: O(response size).
pub fn text_parse_get_response(data: &Vec[UInt8], off: Int) -> Result[TextGetResponse, Str] {
  if off < 0 {
    return _err_get("memcached: negative offset");
  }
  var pos = off;
  var keys = Vec[Vec[UInt8]].new();
  var flags = Vec[Int].new();
  var cas = Vec[Int].new();
  var spans = Vec[Int].new();
  var pool = Vec[UInt8].new();
  var done = false;
  while !done {
    if pos >= data.len() {
      return _err_get("memcached: truncated response");
    }
    let cr = _line_crlf(data, pos);
    if cr < 0 {
      return _err_get("memcached: truncated line");
    }
    let line = _slice_copy(data, pos, cr);
    let tokens = _split_tokens(&line);
    if tokens.len() == 0 {
      return _err_get("memcached: bad response line");
    }
    let first: Vec[UInt8] = tokens[0];
    let l_end: Vec[UInt8] = _str_bytes("END");
    if _bytes_eq_ci(&first, &l_end) {
      if tokens.len() != 1 {
        return _err_get("memcached: bad response line");
      }
      done = true;
      pos = cr + 2;
    } else {
      let l_value: Vec[UInt8] = _str_bytes("VALUE");
      if !_bytes_eq_ci(&first, &l_value) {
        return _err_get("memcached: bad response line");
      }
      if tokens.len() != 4 && tokens.len() != 5 {
        return _err_get("memcached: bad response line");
      }
      let key_tok: Vec[UInt8] = tokens[1];
      if !_key_is_valid(&key_tok) {
        return _err_get("memcached: bad key");
      }
      let f_tok: Vec[UInt8] = tokens[2];
      let fr = _parse_u32(&f_tok);
      if !fr.is_ok {
        return _err_get(fr.error);
      }
      let b_tok: Vec[UInt8] = tokens[3];
      let br = _parse_u32(&b_tok);
      if !br.is_ok {
        return _err_get(br.error);
      }
      let nbytes: Int = br.value;
      if nbytes > _MAX_DATA {
        return _err_get("memcached: bad bytes");
      }
      var c = -1;
      if tokens.len() == 5 {
        let c_tok: Vec[UInt8] = tokens[4];
        let crr = _parse_u64(&c_tok);
        if !crr.is_ok {
          return _err_get(crr.error);
        }
        c = crr.value;
      }
      let dstart = cr + 2;
      if dstart + nbytes + 2 > data.len() {
        return _err_get("memcached: truncated data");
      }
      let cb = _byte(data, dstart + nbytes);
      let lb = _byte(data, dstart + nbytes + 1);
      if cb != _I_CR || lb != _I_LF {
        return _err_get("memcached: bad data block");
      }
      keys.push(key_tok);
      flags.push(fr.value);
      cas.push(c);
      spans.push(pool.len());
      spans.push(nbytes);
      var i = 0;
      while i < nbytes {
        pool.push(data[dstart + i]);
        i = i + 1;
      }
      pos = dstart + nbytes + 2;
    }
  }
  return _ok_get(TextGetResponse{ keys: keys; flags: flags; cas: cas; pool: pool; spans: spans; consumed: pos - off; });
}

/// Number of VALUE entries in a retrieval response. Complexity: O(1).
pub fn text_values_count(r: &TextGetResponse) -> Int {
  return r.keys.len();
}

/// Key of VALUE entry `i` (empty when `i` is out of range).
/// Complexity: O(key length).
pub fn text_value_key(r: &TextGetResponse, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= r.keys.len() {
    return Vec[UInt8].new();
  }
  let ks: Vec[Vec[UInt8]] = r.keys;
  let k: Vec[UInt8] = ks[i];
  return k;
}

/// Flags of VALUE entry `i` (-1 when `i` is out of range). Complexity: O(1).
pub fn text_value_flags(r: &TextGetResponse, i: Int) -> Int {
  if i < 0 || i >= r.keys.len() {
    return -1;
  }
  let fs: Vec[Int] = r.flags;
  let v: Int = fs[i];
  return v;
}

/// CAS id of VALUE entry `i` (-1 when absent or out of range).
/// Complexity: O(1).
pub fn text_value_cas(r: &TextGetResponse, i: Int) -> Int {
  if i < 0 || i >= r.keys.len() {
    return -1;
  }
  let cs: Vec[Int] = r.cas;
  let v: Int = cs[i];
  return v;
}

/// Data block of VALUE entry `i` (empty when `i` is out of range).
/// Complexity: O(value length).
pub fn text_value_data(r: &TextGetResponse, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= r.keys.len() {
    return Vec[UInt8].new();
  }
  let sp: Vec[Int] = r.spans;
  let start: Int = sp[i * 2];
  let n: Int = sp[i * 2 + 1];
  let pl: Vec[UInt8] = r.pool;
  var out = Vec[UInt8].new();
  var j = 0;
  while j < n {
    out.push(pl[start + j]);
    j = j + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Binary protocol: integer encoding and decoding
// ---------------------------------------------------------------------------

// Append `v` (0..65535) as two big-endian bytes.
fn _push_u16(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append `v` (0..4294967295) as four big-endian bytes.
fn _push_u32(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 16777216) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append `v` (0..2^63-1) as eight big-endian bytes.
fn _push_u64(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 72057594037927936) as UInt8);
  out.push(((v / 281474976710656) % 256) as UInt8);
  out.push(((v / 1099511627776) % 256) as UInt8);
  out.push(((v / 4294967296) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Unsigned big-endian u16 at [pos, pos+2); callers guarantee the bounds.
fn _read_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Unsigned big-endian u32 at [pos, pos+4); callers guarantee the bounds.
fn _read_u32(data: &Vec[UInt8], pos: Int) -> Int {
  return _read_u16(data, pos) * 65536 + _read_u16(data, pos + 2);
}

// Unsigned big-endian u64 at [pos, pos+8) as an Int; callers must have
// rejected a high bit set in the first byte, so the value fits 0..2^63-1.
fn _read_u64(data: &Vec[UInt8], pos: Int) -> Int {
  return _read_u32(data, pos) * 4294967296 + _read_u32(data, pos + 4);
}

// ---------------------------------------------------------------------------
// Binary protocol: opcodes and statuses
// ---------------------------------------------------------------------------

/// True when `opcode` is one of the supported binary opcodes: GET, SET, ADD,
/// REPLACE, DELETE, INCR, DECR, QUIT, FLUSH, NOOP, VERSION, GETK, GETKQ.
/// Complexity: O(1).
pub fn bin_opcode_known(opcode: Int) -> Bool {
  return opcode == _BIN_OP_GET || opcode == _BIN_OP_SET || opcode == _BIN_OP_ADD || opcode == _BIN_OP_REPLACE || opcode == _BIN_OP_DELETE || opcode == _BIN_OP_INCR || opcode == _BIN_OP_DECR || opcode == _BIN_OP_QUIT || opcode == _BIN_OP_FLUSH || opcode == _BIN_OP_NOOP || opcode == _BIN_OP_VERSION || opcode == _BIN_OP_GETK || opcode == _BIN_OP_GETKQ;
}

/// Opcode of a name ("GET", "SET", ... case-insensitive), -1 when unknown.
/// Complexity: O(name length).
pub fn bin_opcode_id(name: Str) -> Int {
  if _streq_ci(name, "GET") {
    return _BIN_OP_GET;
  }
  if _streq_ci(name, "SET") {
    return _BIN_OP_SET;
  }
  if _streq_ci(name, "ADD") {
    return _BIN_OP_ADD;
  }
  if _streq_ci(name, "REPLACE") {
    return _BIN_OP_REPLACE;
  }
  if _streq_ci(name, "DELETE") {
    return _BIN_OP_DELETE;
  }
  if _streq_ci(name, "INCR") {
    return _BIN_OP_INCR;
  }
  if _streq_ci(name, "DECR") {
    return _BIN_OP_DECR;
  }
  if _streq_ci(name, "QUIT") {
    return _BIN_OP_QUIT;
  }
  if _streq_ci(name, "FLUSH") {
    return _BIN_OP_FLUSH;
  }
  if _streq_ci(name, "NOOP") {
    return _BIN_OP_NOOP;
  }
  if _streq_ci(name, "VERSION") {
    return _BIN_OP_VERSION;
  }
  if _streq_ci(name, "GETK") {
    return _BIN_OP_GETK;
  }
  if _streq_ci(name, "GETKQ") {
    return _BIN_OP_GETKQ;
  }
  return -1;
}

/// Canonical uppercase name of an opcode ("UNKNOWN" when unsupported).
/// Complexity: O(1).
pub fn bin_opcode_name(opcode: Int) -> Str {
  if opcode == _BIN_OP_GET {
    return "GET";
  }
  if opcode == _BIN_OP_SET {
    return "SET";
  }
  if opcode == _BIN_OP_ADD {
    return "ADD";
  }
  if opcode == _BIN_OP_REPLACE {
    return "REPLACE";
  }
  if opcode == _BIN_OP_DELETE {
    return "DELETE";
  }
  if opcode == _BIN_OP_INCR {
    return "INCR";
  }
  if opcode == _BIN_OP_DECR {
    return "DECR";
  }
  if opcode == _BIN_OP_QUIT {
    return "QUIT";
  }
  if opcode == _BIN_OP_FLUSH {
    return "FLUSH";
  }
  if opcode == _BIN_OP_NOOP {
    return "NOOP";
  }
  if opcode == _BIN_OP_VERSION {
    return "VERSION";
  }
  if opcode == _BIN_OP_GETK {
    return "GETK";
  }
  if opcode == _BIN_OP_GETKQ {
    return "GETKQ";
  }
  return "UNKNOWN";
}

/// Wire status code of a status name, -1 when unknown. The names follow the
/// conventional short spellings: SUCCESS, NOT_FOUND, EXISTS, TOO_LARGE,
/// INVALID_ARGUMENTS, NOT_STORED, DELTA_BADVAL, NOT_MY_VBUCKET, AUTH_ERROR,
/// AUTH_CONTINUE, UNKNOWN_COMMAND, OUT_OF_MEMORY, NOT_SUPPORTED,
/// INTERNAL_ERROR, BUSY, TEMP_FAILURE. The canonical memcached aliases
/// KEY_ENOENT / KEY_EEXISTS / E2BIG / EINVAL are accepted too.
/// Complexity: O(name length).
pub fn bin_status_id(name: Str) -> Int {
  if _streq_ci(name, "SUCCESS") {
    return 0;
  }
  if _streq_ci(name, "NOT_FOUND") || _streq_ci(name, "KEY_ENOENT") {
    return 1;
  }
  if _streq_ci(name, "EXISTS") || _streq_ci(name, "KEY_EEXISTS") {
    return 2;
  }
  if _streq_ci(name, "TOO_LARGE") || _streq_ci(name, "E2BIG") {
    return 3;
  }
  if _streq_ci(name, "INVALID_ARGUMENTS") || _streq_ci(name, "EINVAL") {
    return 4;
  }
  if _streq_ci(name, "NOT_STORED") {
    return 5;
  }
  if _streq_ci(name, "DELTA_BADVAL") {
    return 6;
  }
  if _streq_ci(name, "NOT_MY_VBUCKET") {
    return 7;
  }
  if _streq_ci(name, "AUTH_ERROR") {
    return 32;
  }
  if _streq_ci(name, "AUTH_CONTINUE") {
    return 33;
  }
  if _streq_ci(name, "UNKNOWN_COMMAND") {
    return 129;
  }
  if _streq_ci(name, "OUT_OF_MEMORY") {
    return 130;
  }
  if _streq_ci(name, "NOT_SUPPORTED") {
    return 131;
  }
  if _streq_ci(name, "INTERNAL_ERROR") {
    return 132;
  }
  if _streq_ci(name, "BUSY") {
    return 133;
  }
  if _streq_ci(name, "TEMP_FAILURE") {
    return 134;
  }
  return -1;
}

/// Canonical name of a 16-bit status code ("UNKNOWN" for codes outside the
/// documented table 0x0000..0x0086). Complexity: O(1).
pub fn bin_status_name(status: Int) -> Str {
  if status == 0 {
    return "SUCCESS";
  }
  if status == 1 {
    return "NOT_FOUND";
  }
  if status == 2 {
    return "EXISTS";
  }
  if status == 3 {
    return "TOO_LARGE";
  }
  if status == 4 {
    return "INVALID_ARGUMENTS";
  }
  if status == 5 {
    return "NOT_STORED";
  }
  if status == 6 {
    return "DELTA_BADVAL";
  }
  if status == 7 {
    return "NOT_MY_VBUCKET";
  }
  if status == 32 {
    return "AUTH_ERROR";
  }
  if status == 33 {
    return "AUTH_CONTINUE";
  }
  if status == 129 {
    return "UNKNOWN_COMMAND";
  }
  if status == 130 {
    return "OUT_OF_MEMORY";
  }
  if status == 131 {
    return "NOT_SUPPORTED";
  }
  if status == 132 {
    return "INTERNAL_ERROR";
  }
  if status == 133 {
    return "BUSY";
  }
  if status == 134 {
    return "TEMP_FAILURE";
  }
  return "UNKNOWN";
}

/// True when `status` is the success code 0x0000. Complexity: O(1).
pub fn bin_status_is_success(status: Int) -> Bool {
  return status == 0;
}

/// True when `extras_len` matches the documented extras layout of
/// `opcode` for the given `magic` (0x80 request, 0x81 response): GETK/GETKQ
/// take no extras and GET responses carry the 4-byte flags word; SET/ADD/
/// REPLACE take the 8-byte expiration+flags block and INCR/DECR the 20-byte
/// delta+initial+expiration block; FLUSH requests accept 0 or 4 bytes.
/// Error responses (status != 0x0000) carry no extras and callers should
/// skip this check for them. Complexity: O(1).
pub fn bin_extras_len_is_valid(magic: Int, opcode: Int, extras_len: Int) -> Bool {
  if magic == _BIN_REQ {
    if opcode == _BIN_OP_SET || opcode == _BIN_OP_ADD || opcode == _BIN_OP_REPLACE {
      return extras_len == 8;
    }
    if opcode == _BIN_OP_INCR || opcode == _BIN_OP_DECR {
      return extras_len == 20;
    }
    if opcode == _BIN_OP_FLUSH {
      return extras_len == 0 || extras_len == 4;
    }
    if opcode == _BIN_OP_GET || opcode == _BIN_OP_DELETE || opcode == _BIN_OP_QUIT || opcode == _BIN_OP_NOOP || opcode == _BIN_OP_VERSION || opcode == _BIN_OP_GETK || opcode == _BIN_OP_GETKQ {
      return extras_len == 0;
    }
    return false;
  }
  if magic == _BIN_RES {
    if opcode == _BIN_OP_GET || opcode == _BIN_OP_GETK || opcode == _BIN_OP_GETKQ {
      return extras_len == 4;
    }
    if opcode == _BIN_OP_INCR || opcode == _BIN_OP_DECR {
      return extras_len == 8;
    }
    if opcode == _BIN_OP_SET || opcode == _BIN_OP_ADD || opcode == _BIN_OP_REPLACE || opcode == _BIN_OP_DELETE || opcode == _BIN_OP_QUIT || opcode == _BIN_OP_FLUSH || opcode == _BIN_OP_NOOP || opcode == _BIN_OP_VERSION {
      return extras_len == 0;
    }
    return false;
  }
  return false;
}

/// Decode the 8-byte SET/ADD/REPLACE extras: u32 exptime then u32 flags.
/// Err("memcached: bad extras length") when the vector is not 8 bytes.
/// Complexity: O(1).
pub fn bin_decode_set_extras(extras: &Vec[UInt8]) -> Result[BinSetExtras, Str] {
  if extras.len() != 8 {
    return _err_setex("memcached: bad extras length");
  }
  let exptime = _read_u32(extras, 0);
  let flags = _read_u32(extras, 4);
  return _ok_setex(BinSetExtras{ exptime: exptime; flags: flags; });
}

/// Decode the 4-byte GET/GETK response extras (the returned item flags).
/// Err("memcached: bad extras length") when the vector is not 4 bytes.
/// Complexity: O(1).
pub fn bin_decode_get_extras(extras: &Vec[UInt8]) -> Result[Int, Str] {
  if extras.len() != 4 {
    return _err_int("memcached: bad extras length");
  }
  return _ok_int(_read_u32(extras, 0));
}

/// Decode the 20-byte INCR/DECR extras: u64 delta, u64 initial, u32 exptime.
/// Values with the top bit set are not representable and are rejected.
///
/// Err("memcached: bad extras length") when the vector is not 20 bytes;
/// Err("memcached: delta out of range") / Err("memcached: initial out of
/// range") when the high bit is set. Complexity: O(1).
pub fn bin_decode_delta_extras(extras: &Vec[UInt8]) -> Result[BinDeltaExtras, Str] {
  if extras.len() != 20 {
    return _err_dex("memcached: bad extras length");
  }
  if _byte(extras, 0) >= 128 {
    return _err_dex("memcached: delta out of range");
  }
  if _byte(extras, 8) >= 128 {
    return _err_dex("memcached: initial out of range");
  }
  let delta = _read_u64(extras, 0);
  let initial = _read_u64(extras, 8);
  let exptime = _read_u32(extras, 16);
  return _ok_dex(BinDeltaExtras{ delta: delta; initial: initial; exptime: exptime; });
}

// ---------------------------------------------------------------------------
// Binary protocol: encoding
// ---------------------------------------------------------------------------

// Build one binary message (request or response). `status` is the response
// status field and is 0 (vbucket) on requests.
fn _bin_message(magic: Int, opcode: Int, status: Int, extras: &Vec[UInt8], key: &Vec[UInt8], value: &Vec[UInt8], cas: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  if magic != _BIN_REQ && magic != _BIN_RES {
    return _err_bytes("memcached: bad magic");
  }
  if !bin_opcode_known(opcode) {
    return _err_bytes("memcached: unknown opcode");
  }
  if status < 0 || status > 65535 {
    return _err_bytes("memcached: bad status");
  }
  if extras.len() > 255 {
    return _err_bytes("memcached: bad extras length");
  }
  if key.len() > 65535 {
    return _err_bytes("memcached: bad key length");
  }
  if cas < 0 {
    return _err_bytes("memcached: bad cas");
  }
  if opaque < 0 || opaque > _MAX_U32 {
    return _err_bytes("memcached: bad opaque");
  }
  if magic == _BIN_REQ {
    if !bin_extras_len_is_valid(_BIN_REQ, opcode, extras.len()) {
      return _err_bytes("memcached: bad extras length");
    }
  } else {
    if status == 0 {
      if !bin_extras_len_is_valid(_BIN_RES, opcode, extras.len()) {
        return _err_bytes("memcached: bad extras length");
      }
    }
  }
  let vmax = _MAX_U32 - extras.len() - key.len();
  if value.len() > vmax {
    return _err_bytes("memcached: bad body length");
  }
  let total = extras.len() + key.len() + value.len();
  var out = Vec[UInt8].new();
  out.push(magic as UInt8);
  out.push(opcode as UInt8);
  _push_u16(&mut out, key.len());
  out.push(extras.len() as UInt8);
  out.push(0 as UInt8);
  _push_u16(&mut out, status);
  _push_u32(&mut out, total);
  _push_u32(&mut out, opaque);
  _push_u64(&mut out, cas);
  _push_bytes(&mut out, extras);
  _push_bytes(&mut out, key);
  _push_bytes(&mut out, value);
  return _ok_bytes(out);
}

/// Encode a binary request (magic 0x80). `extras` must match the documented
/// layout of `opcode`; `cas` and `opaque` are 0..2^63-1 and 0..4294967295
/// (cas 0 means "no compare").
///
/// Err("memcached: unknown opcode"); Err("memcached: bad magic");
/// Err("memcached: bad status") when `status` is outside 0..65535;
/// Err("memcached: bad extras length") / Err("memcached: bad key length")
/// when a field does not fit its wire width or does not match the opcode
/// layout; Err("memcached: bad cas") for a negative cas;
/// Err("memcached: bad opaque") for an opaque outside 0..4294967295;
/// Err("memcached: bad body length") when the body exceeds 4294967295.
/// Complexity: O(packet size).
pub fn bin_encode_request(opcode: Int, key: &Vec[UInt8], extras: &Vec[UInt8], value: &Vec[UInt8], cas: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  return _bin_message(_BIN_REQ, opcode, 0, extras, key, value, cas, opaque);
}

/// Encode a binary response (magic 0x81). `status` is the status code
/// (0..65535); error responses (status != 0) may carry arbitrary extras.
///
/// Errors: same catalog as bin_encode_request, with
/// Err("memcached: bad extras length") applying only when `status` is 0
/// (error responses are exempt from the per-opcode extras layout check).
/// Complexity: O(packet size).
pub fn bin_encode_response(opcode: Int, status: Int, extras: &Vec[UInt8], key: &Vec[UInt8], value: &Vec[UInt8], cas: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  return _bin_message(_BIN_RES, opcode, status, extras, key, value, cas, opaque);
}

/// Encode a GET request (no extras). Complexity: O(packet size).
pub fn bin_encode_get(key: &Vec[UInt8], opaque: Int) -> Result[Vec[UInt8], Str] {
  let ex = _empty_bytes();
  let no_value = _empty_bytes();
  return bin_encode_request(_BIN_OP_GET, key, &ex, &no_value, 0, opaque);
}

/// Encode a GETK request (no extras; responses echo the key).
/// Complexity: O(packet size).
pub fn bin_encode_getk(key: &Vec[UInt8], opaque: Int) -> Result[Vec[UInt8], Str] {
  let ex = _empty_bytes();
  let no_value = _empty_bytes();
  return bin_encode_request(_BIN_OP_GETK, key, &ex, &no_value, 0, opaque);
}

/// Encode a GETKQ request (quiet GETK: no miss response).
/// Complexity: O(packet size).
pub fn bin_encode_getkq(key: &Vec[UInt8], opaque: Int) -> Result[Vec[UInt8], Str] {
  let ex = _empty_bytes();
  let no_value = _empty_bytes();
  return bin_encode_request(_BIN_OP_GETKQ, key, &ex, &no_value, 0, opaque);
}

// Build the 8-byte SET-family extras and encode the request.
fn _encode_storage_request(opcode: Int, key: &Vec[UInt8], value: &Vec[UInt8], flags: Int, exptime: Int, cas: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  if flags < 0 || flags > _MAX_U32 {
    return _err_bytes("memcached: bad flags");
  }
  if exptime < 0 || exptime > _MAX_U32 {
    return _err_bytes("memcached: bad exptime");
  }
  var extras = Vec[UInt8].new();
  _push_u32(&mut extras, exptime);
  _push_u32(&mut extras, flags);
  let ex: Vec[UInt8] = extras;
  return bin_encode_request(opcode, key, &ex, value, cas, opaque);
}

/// Encode a SET request (8-byte exptime+flags extras). `cas` 0 stores
/// unconditionally.
///
/// Err("memcached: bad flags") / Err("memcached: bad exptime") for values
/// outside 0..4294967295; plus the bin_encode_request errors.
/// Complexity: O(packet size).
pub fn bin_encode_set(key: &Vec[UInt8], value: &Vec[UInt8], flags: Int, exptime: Int, cas: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  return _encode_storage_request(_BIN_OP_SET, key, value, flags, exptime, cas, opaque);
}

/// Encode an ADD request. Err catalog as bin_encode_set.
/// Complexity: O(packet size).
pub fn bin_encode_add(key: &Vec[UInt8], value: &Vec[UInt8], flags: Int, exptime: Int, cas: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  return _encode_storage_request(_BIN_OP_ADD, key, value, flags, exptime, cas, opaque);
}

/// Encode a REPLACE request. Err catalog as bin_encode_set.
/// Complexity: O(packet size).
pub fn bin_encode_replace(key: &Vec[UInt8], value: &Vec[UInt8], flags: Int, exptime: Int, cas: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  return _encode_storage_request(_BIN_OP_REPLACE, key, value, flags, exptime, cas, opaque);
}

// Build the 20-byte INCR/DECR extras and encode the request.
fn _encode_delta_request(opcode: Int, key: &Vec[UInt8], delta: Int, initial: Int, exptime: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  if delta < 0 {
    return _err_bytes("memcached: bad delta");
  }
  if initial < 0 {
    return _err_bytes("memcached: bad initial");
  }
  if exptime < 0 || exptime > _MAX_U32 {
    return _err_bytes("memcached: bad exptime");
  }
  var extras = Vec[UInt8].new();
  _push_u64(&mut extras, delta);
  _push_u64(&mut extras, initial);
  _push_u32(&mut extras, exptime);
  let ex: Vec[UInt8] = extras;
  let no_value = _empty_bytes();
  return bin_encode_request(opcode, key, &ex, &no_value, 0, opaque);
}

/// Encode an INCR request (20-byte delta+initial+exptime extras).
/// Err("memcached: bad delta") / Err("memcached: bad initial") for negative
/// values; Err("memcached: bad exptime") outside 0..4294967295.
/// Complexity: O(packet size).
pub fn bin_encode_incr(key: &Vec[UInt8], delta: Int, initial: Int, exptime: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  return _encode_delta_request(_BIN_OP_INCR, key, delta, initial, exptime, opaque);
}

/// Encode a DECR request. Err catalog as bin_encode_incr.
/// Complexity: O(packet size).
pub fn bin_encode_decr(key: &Vec[UInt8], delta: Int, initial: Int, exptime: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  return _encode_delta_request(_BIN_OP_DECR, key, delta, initial, exptime, opaque);
}

/// Encode a DELETE request (no extras). Complexity: O(packet size).
pub fn bin_encode_delete(key: &Vec[UInt8], opaque: Int) -> Result[Vec[UInt8], Str] {
  let ex = _empty_bytes();
  let no_value = _empty_bytes();
  return bin_encode_request(_BIN_OP_DELETE, key, &ex, &no_value, 0, opaque);
}

/// Encode a QUIT request (no extras). Complexity: O(packet size).
pub fn bin_encode_quit(opaque: Int) -> Result[Vec[UInt8], Str] {
  let no_key = _empty_bytes();
  let ex = _empty_bytes();
  let no_value = _empty_bytes();
  return bin_encode_request(_BIN_OP_QUIT, &no_key, &ex, &no_value, 0, opaque);
}

/// Encode a FLUSH request. `expiration` is -1 for "no delay" (0 extras) or
/// 0..4294967295 (4-byte extras).
/// Err("memcached: bad exptime") when out of range.
/// Complexity: O(packet size).
pub fn bin_encode_flush(expiration: Int, opaque: Int) -> Result[Vec[UInt8], Str] {
  if expiration < -1 || expiration > _MAX_U32 {
    return _err_bytes("memcached: bad exptime");
  }
  var extras = Vec[UInt8].new();
  if expiration >= 0 {
    _push_u32(&mut extras, expiration);
  }
  let ex: Vec[UInt8] = extras;
  let no_key = _empty_bytes();
  let no_value = _empty_bytes();
  return bin_encode_request(_BIN_OP_FLUSH, &no_key, &ex, &no_value, 0, opaque);
}

/// Encode a NOOP request (no extras). Complexity: O(packet size).
pub fn bin_encode_noop(opaque: Int) -> Result[Vec[UInt8], Str] {
  let no_key = _empty_bytes();
  let ex = _empty_bytes();
  let no_value = _empty_bytes();
  return bin_encode_request(_BIN_OP_NOOP, &no_key, &ex, &no_value, 0, opaque);
}

/// Encode a binary VERSION request (no extras). Distinct from the text
/// protocol `text_encode_version`. Complexity: O(packet size).
pub fn bin_encode_version(opaque: Int) -> Result[Vec[UInt8], Str] {
  let no_key = _empty_bytes();
  let ex = _empty_bytes();
  let no_value = _empty_bytes();
  return bin_encode_request(_BIN_OP_VERSION, &no_key, &ex, &no_value, 0, opaque);
}

// ---------------------------------------------------------------------------
// Binary protocol: parsing
// ---------------------------------------------------------------------------

/// Parse the 24-byte binary header at `off`. `consumed` is 24; the body of
/// `total_body` bytes follows at off+24.
///
/// Err("memcached: negative offset"); Err("memcached: truncated header")
/// when fewer than 24 bytes are available; Err("memcached: bad magic") when
/// the first byte is not 0x80/0x81; Err("memcached: unknown opcode") for an
/// opcode outside the supported set; Err("memcached: bad data type") for a
/// non-zero data type; Err("memcached: cas out of range") when the 8-byte
/// cas has its top bit set (values above 2^63-1 are not representable).
/// Complexity: O(1).
pub fn bin_parse_header(data: &Vec[UInt8], off: Int) -> Result[BinHeader, Str] {
  if off < 0 {
    return _err_header("memcached: negative offset");
  }
  if data.len() < off + _BIN_HEADER {
    return _err_header("memcached: truncated header");
  }
  let magic = _byte(data, off);
  if magic != _BIN_REQ && magic != _BIN_RES {
    return _err_header("memcached: bad magic");
  }
  let opcode = _byte(data, off + 1);
  if !bin_opcode_known(opcode) {
    return _err_header("memcached: unknown opcode");
  }
  let key_len = _read_u16(data, off + 2);
  let extras_len = _byte(data, off + 4);
  let data_type = _byte(data, off + 5);
  if data_type != 0 {
    return _err_header("memcached: bad data type");
  }
  let status = _read_u16(data, off + 6);
  let total = _read_u32(data, off + 8);
  let opaque = _read_u32(data, off + 12);
  if _byte(data, off + 16) >= 128 {
    return _err_header("memcached: cas out of range");
  }
  let cas = _read_u64(data, off + 16);
  return _ok_header(BinHeader{
    magic: magic;
    opcode: opcode;
    key_len: key_len;
    extras_len: extras_len;
    data_type: data_type;
    status: status;
    total_body: total;
    opaque: opaque;
    cas: cas;
    consumed: _BIN_HEADER;
  });
}

/// Parse one whole binary packet at `off`: the header plus `total_body`
/// bytes of body split into fresh extras, key and value vectors (value
/// length = total_body - extras_len - key_len). `consumed` is
/// 24 + total_body.
///
/// Errors: the bin_parse_header errors, plus Err("memcached: truncated
/// body") when the declared body does not fit; Err("memcached: bad extras
/// length") when extras_len exceeds the body or the extras layout does not
/// match the opcode (responses with a non-zero status are exempt, since
/// error responses carry no extras); Err("memcached: bad key length") when
/// key_len exceeds total_body - extras_len.
/// Complexity: O(packet size).
pub fn bin_parse_packet(data: &Vec[UInt8], off: Int) -> Result[BinPacket, Str] {
  let hr = bin_parse_header(data, off);
  if !hr.is_ok {
    return _err_packet(hr.error);
  }
  let h: BinHeader = hr.value;
  let body_start = off + _BIN_HEADER;
  if data.len() < body_start + h.total_body {
    return _err_packet("memcached: truncated body");
  }
  if h.extras_len > h.total_body {
    return _err_packet("memcached: bad extras length");
  }
  let after_extras = h.total_body - h.extras_len;
  if h.key_len > after_extras {
    return _err_packet("memcached: bad key length");
  }
  var apply_rules = true;
  if h.magic == _BIN_RES {
    if h.status != 0 {
      apply_rules = false;
    }
  }
  if apply_rules {
    if !bin_extras_len_is_valid(h.magic, h.opcode, h.extras_len) {
      return _err_packet("memcached: bad extras length");
    }
  }
  let value_len = after_extras - h.key_len;
  let extras = _slice_copy(data, body_start, body_start + h.extras_len);
  let key = _slice_copy(data, body_start + h.extras_len, body_start + h.extras_len + h.key_len);
  let value = _slice_copy(data, body_start + h.extras_len + h.key_len, body_start + h.extras_len + h.key_len + value_len);
  return _ok_packet(BinPacket{
    magic: h.magic;
    opcode: h.opcode;
    key_len: h.key_len;
    extras_len: h.extras_len;
    data_type: h.data_type;
    status: h.status;
    opaque: h.opaque;
    cas: h.cas;
    key: key;
    extras: extras;
    value: value;
    consumed: _BIN_HEADER + h.total_body;
  });
}
