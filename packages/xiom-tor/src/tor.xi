// XIOM -- xiom.tor: Tor link-layer cell structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no crypto, no session state) STRUCTURE
// decoder for Tor channel cells, following the public Tor specifications
// (spec.torproject.org: "Cells (messages on channels)", the VERSIONS/NETINFO
// handshake pages and the RELAY payload pages):
//
//   v3-and-earlier fixed cell : CircID(2) + Command(1) + Body(509) = 512
//   v4-and-later fixed cell   : CircID(4) + Command(1) + Body(509) = 514
//   variable cell             : CircID + Command(1) + Length(2) + Body
//
// What this module does:
//   * parses one cell at a time out of a byte buffer and reports `consumed`,
//     so callers can walk a stream of concatenated cells;
//   * auto-detects the CircID width with the classic nonzero-high-bytes rule
//     and offers tor_parse_cell_v for callers that already know the link
//     version (the robust path: a wide cell with a zero high half, such as
//     NETINFO or DESTROY on a v4 link, cannot be auto-detected);
//   * parses VERSIONS bodies (lists of big-endian u16 link versions) and
//     NETINFO bodies (time, observed address, this party's addresses);
//   * parses the 11-byte RELAY envelope (command, recognized, stream id,
//     digest, length) and decodes the simple typed payloads: BEGIN,
//     CONNECTED, END, SENDME, RESOLVE, RESOLVED.
//
// What this module deliberately does NOT do:
//   * no cryptography: the RELAY digest field, the recognized field and all
//     cell ciphertext are opaque bytes here -- nothing is verified, decrypted
//     or computed;
//   * no circuits, streams, flow control, padding policy or I/O;
//   * no CERTS/AUTH_CHALLENGE/AUTHENTICATE decoding (certificate crypto);
//   * no encoder: the conformance suite builds synthetic cells in-test.
//
// Parse errors carry the start offset of the thing being parsed, relative to
// the buffer handed in: "tor: <what> at <offset>".
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below;
//   * every byte read from a Vec[UInt8] widens with `(data[pos] as Int) &
//     0xFF` before it enters Int arithmetic or comparisons;
//   * Vec reads are bound to typed locals and struct fields are copied into
//     typed locals before they are passed by reference;
//   * free functions only, no match-in-src, no Vec[StructType], no
//     angle-bracket generics, no floats, no `log`.

module xiom.tor

use xiom.string.builder;

// --------------------------------------------------
//  Sizes
// --------------------------------------------------

/// Body length of a fixed-length cell (bytes 3..512 or 5..514).
pub const TOR_CELL_BODY_LEN: Int = 509;

/// Total length of a v3-and-earlier fixed-length cell.
pub const TOR_CELL_NARROW_LEN: Int = 512;

/// Total length of a v4-and-later fixed-length cell.
pub const TOR_CELL_WIDE_LEN: Int = 514;

/// Length of the RELAY envelope header inside a cell body.
pub const TOR_RELAY_HEADER_LEN: Int = 11;

/// Length of the RELAY digest field.
pub const TOR_RELAY_DIGEST_FIELD_LEN: Int = 4;

/// Largest RELAY `data` payload that fits a fixed-length cell body.
pub const TOR_RELAY_MAX_DATA_FIXED: Int = 498;

/// Length of the SENDME version 1 digest field.
pub const TOR_SENDME_DIGEST_LEN: Int = 20;

/// Largest Length field of a variable-length cell (u16).
pub const TOR_MAX_VARIABLE_LEN: Int = 65535;

/// Lowest link protocol version still defined (1 and 2 are obsolete).
pub const TOR_MIN_LINK_VERSION: Int = 3;

/// Body length of a fixed-length cell. Params: none. Returns: 509.
pub fn tor_cell_body_len() -> Int { return TOR_CELL_BODY_LEN; }

/// Total length of a v3-and-earlier fixed-length cell. Params: none.
/// Returns: 512. Error case: none.
pub fn tor_cell_narrow_len() -> Int { return TOR_CELL_NARROW_LEN; }

/// Total length of a v4-and-later fixed-length cell. Params: none.
/// Returns: 514. Error case: none.
pub fn tor_cell_wide_len() -> Int { return TOR_CELL_WIDE_LEN; }

/// Length of the RELAY envelope header (command through length). Params:
/// none. Returns: 11. Error case: none.
pub fn tor_relay_header_len() -> Int { return TOR_RELAY_HEADER_LEN; }

/// Largest RELAY `data` payload in a fixed-length cell (509 - 11). Params:
/// none. Returns: 498. Error case: none.
pub fn tor_relay_max_data_fixed() -> Int { return TOR_RELAY_MAX_DATA_FIXED; }

/// Length of the SENDME version 1 digest. Params: none. Returns: 20.
/// Error case: none.
pub fn tor_sendme_digest_len() -> Int { return TOR_SENDME_DIGEST_LEN; }

/// Largest variable-length cell body (u16 Length). Params: none.
/// Returns: 65535. Error case: none.
pub fn tor_max_variable_len() -> Int { return TOR_MAX_VARIABLE_LEN; }

// --------------------------------------------------
//  Link command ids
// --------------------------------------------------

pub const TOR_LINK_CMD_PADDING: Int = 0;
pub const TOR_LINK_CMD_CREATE: Int = 1;
pub const TOR_LINK_CMD_CREATED: Int = 2;
pub const TOR_LINK_CMD_RELAY: Int = 3;
pub const TOR_LINK_CMD_DESTROY: Int = 4;
pub const TOR_LINK_CMD_CREATE_FAST: Int = 5;
pub const TOR_LINK_CMD_CREATED_FAST: Int = 6;
pub const TOR_LINK_CMD_VERSIONS: Int = 7;
pub const TOR_LINK_CMD_NETINFO: Int = 8;
pub const TOR_LINK_CMD_RELAY_EARLY: Int = 9;
pub const TOR_LINK_CMD_CREATE2: Int = 10;
pub const TOR_LINK_CMD_CREATED2: Int = 11;
pub const TOR_LINK_CMD_PADDING_NEGOTIATE: Int = 12;

// --------------------------------------------------
//  Relay command ids
// --------------------------------------------------

pub const TOR_RELAY_CMD_BEGIN: Int = 1;
pub const TOR_RELAY_CMD_DATA: Int = 2;
pub const TOR_RELAY_CMD_END: Int = 3;
pub const TOR_RELAY_CMD_CONNECTED: Int = 4;
pub const TOR_RELAY_CMD_SENDME: Int = 5;
pub const TOR_RELAY_CMD_EXTEND: Int = 6;
pub const TOR_RELAY_CMD_EXTENDED: Int = 7;
pub const TOR_RELAY_CMD_TRUNCATE: Int = 8;
pub const TOR_RELAY_CMD_TRUNCATED: Int = 9;
pub const TOR_RELAY_CMD_DROP: Int = 10;
pub const TOR_RELAY_CMD_RESOLVE: Int = 11;
pub const TOR_RELAY_CMD_RESOLVED: Int = 12;
pub const TOR_RELAY_CMD_BEGIN_DIR: Int = 13;
pub const TOR_RELAY_CMD_EXTEND2: Int = 14;
pub const TOR_RELAY_CMD_EXTENDED2: Int = 15;

// --------------------------------------------------
//  END reason ids
// --------------------------------------------------

/// Pseudo-reason for an empty END body (treated as REASON_MISC).
pub const TOR_END_REASON_NONE: Int = 0;
pub const TOR_END_REASON_MISC: Int = 1;
pub const TOR_END_REASON_RESOLVEFAILED: Int = 2;
pub const TOR_END_REASON_CONNECTREFUSED: Int = 3;
pub const TOR_END_REASON_EXITPOLICY: Int = 4;
pub const TOR_END_REASON_DESTROY: Int = 5;
pub const TOR_END_REASON_DONE: Int = 6;
pub const TOR_END_REASON_TIMEOUT: Int = 7;
pub const TOR_END_REASON_NOROUTE: Int = 8;
pub const TOR_END_REASON_HIBERNATING: Int = 9;
pub const TOR_END_REASON_INTERNAL: Int = 10;
pub const TOR_END_REASON_RESOURCELIMIT: Int = 11;
pub const TOR_END_REASON_CONNRESET: Int = 12;
pub const TOR_END_REASON_TORPROTOCOL: Int = 13;
pub const TOR_END_REASON_NOTDIRECTORY: Int = 14;

// --------------------------------------------------
//  RESOLVED answer type ids
// --------------------------------------------------

pub const TOR_RESOLVED_TYPE_HOSTNAME: Int = 0;
pub const TOR_RESOLVED_TYPE_IPV4: Int = 4;
pub const TOR_RESOLVED_TYPE_IPV6: Int = 6;
pub const TOR_RESOLVED_TYPE_ERROR_TRANSIENT: Int = 240;
pub const TOR_RESOLVED_TYPE_ERROR_NONTRANSIENT: Int = 241;

// --------------------------------------------------
//  CONNECTED address kind ids
// --------------------------------------------------

pub const TOR_CONNECTED_NONE: Int = 0;
pub const TOR_CONNECTED_IPV4: Int = 4;
pub const TOR_CONNECTED_IPV6: Int = 6;

// --------------------------------------------------
//  Private constants
// --------------------------------------------------

const _TOR_NUL: Int = 0;
const _TOR_COLON: Int = 58;
const _TOR_LBRACKET: Int = 91;
const _TOR_RBRACKET: Int = 93;
const _TOR_DIGIT_0: Int = 48;
const _TOR_DIGIT_9: Int = 57;
const _TOR_PRINTABLE_LO: Int = 32;
const _TOR_PRINTABLE_HI: Int = 126;
const _TOR_VAR_CMD_BASE: Int = 128;
const _TOR_ATYPE_IPV4: Int = 4;
const _TOR_ATYPE_IPV6: Int = 6;
const _TOR_TTL_UNKNOWN: Int = 4294967295;

// --------------------------------------------------
//  Command tables and names
// --------------------------------------------------

/// True when `cmd` is framed as a variable-length cell by this codec:
/// VERSIONS (7) or any command >= 128. All other commands are fixed-length.
/// Params: cmd - a link command id. Returns: the predicate.
/// Error case: none.
pub fn tor_cell_is_variable_cmd(cmd: Int) -> Bool {
  if cmd == TOR_LINK_CMD_VERSIONS { return true; }
  if cmd >= _TOR_VAR_CMD_BASE { return true; }
  return false;
}

/// True when `v` is a link protocol version this codec considers defined:
/// 3, 4, 5, ... (versions 1 and 2 are obsolete and MUST NOT be listed in a
/// VERSIONS cell). Params: v - a link version. Returns: the predicate.
/// Error case: none.
pub fn tor_link_version_valid(v: Int) -> Bool {
  return v >= TOR_MIN_LINK_VERSION;
}

/// Wire name of a link command id, or "UNKNOWN". Params: cmd - a link
/// command id. Returns: the uppercase identifier. Error case: none.
pub fn tor_link_cmd_name(cmd: Int) -> Str {
  if cmd == TOR_LINK_CMD_PADDING { return "PADDING"; }
  if cmd == TOR_LINK_CMD_CREATE { return "CREATE"; }
  if cmd == TOR_LINK_CMD_CREATED { return "CREATED"; }
  if cmd == TOR_LINK_CMD_RELAY { return "RELAY"; }
  if cmd == TOR_LINK_CMD_DESTROY { return "DESTROY"; }
  if cmd == TOR_LINK_CMD_CREATE_FAST { return "CREATE_FAST"; }
  if cmd == TOR_LINK_CMD_CREATED_FAST { return "CREATED_FAST"; }
  if cmd == TOR_LINK_CMD_VERSIONS { return "VERSIONS"; }
  if cmd == TOR_LINK_CMD_NETINFO { return "NETINFO"; }
  if cmd == TOR_LINK_CMD_RELAY_EARLY { return "RELAY_EARLY"; }
  if cmd == TOR_LINK_CMD_CREATE2 { return "CREATE2"; }
  if cmd == TOR_LINK_CMD_CREATED2 { return "CREATED2"; }
  if cmd == TOR_LINK_CMD_PADDING_NEGOTIATE { return "PADDING_NEGOTIATE"; }
  return "UNKNOWN";
}

/// Wire name of a relay command id, or "UNKNOWN". Params: cmd - a relay
/// command id. Returns: the uppercase identifier. Error case: none.
pub fn tor_relay_cmd_name(cmd: Int) -> Str {
  if cmd == TOR_RELAY_CMD_BEGIN { return "BEGIN"; }
  if cmd == TOR_RELAY_CMD_DATA { return "DATA"; }
  if cmd == TOR_RELAY_CMD_END { return "END"; }
  if cmd == TOR_RELAY_CMD_CONNECTED { return "CONNECTED"; }
  if cmd == TOR_RELAY_CMD_SENDME { return "SENDME"; }
  if cmd == TOR_RELAY_CMD_EXTEND { return "EXTEND"; }
  if cmd == TOR_RELAY_CMD_EXTENDED { return "EXTENDED"; }
  if cmd == TOR_RELAY_CMD_TRUNCATE { return "TRUNCATE"; }
  if cmd == TOR_RELAY_CMD_TRUNCATED { return "TRUNCATED"; }
  if cmd == TOR_RELAY_CMD_DROP { return "DROP"; }
  if cmd == TOR_RELAY_CMD_RESOLVE { return "RESOLVE"; }
  if cmd == TOR_RELAY_CMD_RESOLVED { return "RESOLVED"; }
  if cmd == TOR_RELAY_CMD_BEGIN_DIR { return "BEGIN_DIR"; }
  if cmd == TOR_RELAY_CMD_EXTEND2 { return "EXTEND2"; }
  if cmd == TOR_RELAY_CMD_EXTENDED2 { return "EXTENDED2"; }
  return "UNKNOWN";
}

/// Wire name of an END reason id, or "UNKNOWN". Params: reason - an END
/// reason id (0 for the empty-body default). Returns: the uppercase
/// identifier. Error case: none.
pub fn tor_end_reason_name(reason: Int) -> Str {
  if reason == TOR_END_REASON_NONE { return "NONE"; }
  if reason == TOR_END_REASON_MISC { return "MISC"; }
  if reason == TOR_END_REASON_RESOLVEFAILED { return "RESOLVEFAILED"; }
  if reason == TOR_END_REASON_CONNECTREFUSED { return "CONNECTREFUSED"; }
  if reason == TOR_END_REASON_EXITPOLICY { return "EXITPOLICY"; }
  if reason == TOR_END_REASON_DESTROY { return "DESTROY"; }
  if reason == TOR_END_REASON_DONE { return "DONE"; }
  if reason == TOR_END_REASON_TIMEOUT { return "TIMEOUT"; }
  if reason == TOR_END_REASON_NOROUTE { return "NOROUTE"; }
  if reason == TOR_END_REASON_HIBERNATING { return "HIBERNATING"; }
  if reason == TOR_END_REASON_INTERNAL { return "INTERNAL"; }
  if reason == TOR_END_REASON_RESOURCELIMIT { return "RESOURCELIMIT"; }
  if reason == TOR_END_REASON_CONNRESET { return "CONNRESET"; }
  if reason == TOR_END_REASON_TORPROTOCOL { return "TORPROTOCOL"; }
  if reason == TOR_END_REASON_NOTDIRECTORY { return "NOTDIRECTORY"; }
  return "UNKNOWN";
}

/// Wire name of a RESOLVED answer type id, or "UNKNOWN". Params: atype - a
/// RESOLVED type id. Returns: the uppercase identifier. Error case: none.
pub fn tor_resolved_type_name(atype: Int) -> Str {
  if atype == TOR_RESOLVED_TYPE_HOSTNAME { return "HOSTNAME"; }
  if atype == TOR_RESOLVED_TYPE_IPV4 { return "IPV4"; }
  if atype == TOR_RESOLVED_TYPE_IPV6 { return "IPV6"; }
  if atype == TOR_RESOLVED_TYPE_ERROR_TRANSIENT { return "ERROR_TRANSIENT"; }
  if atype == TOR_RESOLVED_TYPE_ERROR_NONTRANSIENT { return "ERROR_NONTRANSIENT"; }
  return "UNKNOWN";
}

// --------------------------------------------------
//  Decoded values
// --------------------------------------------------

/// One decoded cell frame. `wide` is true for the 4-byte-CircID framing,
/// `variable` is true for variable-length framing (command 7 or >= 128),
/// `circ_id` is the big-endian circuit id, `command` the link command byte,
/// `payload` the raw body bytes (509 for fixed cells, `length` for variable
/// cells) and `consumed` the number of bytes the whole cell occupied.
pub type TorCell = {
  wide: Bool;
  variable: Bool;
  circ_id: Int;
  command: Int;
  payload: Vec[UInt8];
  consumed: Int;
}

/// One parsed VERSIONS body. `versions` is the list of big-endian u16 link
/// versions in wire order and `consumed` is the number of body bytes read.
pub type TorVersions = {
  versions: Vec[Int];
  consumed: Int;
}

/// One decoded RELAY envelope. `cmd` is a relay command id, `recognized`
/// the 16-bit recognized field, `stream_id` the 16-bit stream id (0 for
/// circuit-level messages), `digest` the 4 opaque digest bytes (never
/// verified: this module has no crypto), `length` the declared data length,
/// `data` the data bytes and `consumed` the envelope bytes occupied
/// (11 + length).
pub type TorRelay = {
  cmd: Int;
  recognized: Int;
  stream_id: Int;
  digest: Vec[UInt8];
  length: Int;
  data: Vec[UInt8];
  consumed: Int;
}

/// Decoded RELAY BEGIN payload: the destination address bytes with IPv6
/// brackets stripped, the port, and the optional flags word (`has_flags`
/// false means the FLAGS field was absent and `flags` is 0).
pub type TorBegin = {
  addr: Vec[UInt8];
  port: Int;
  flags: Int;
  has_flags: Bool;
}

/// Decoded RELAY CONNECTED payload: `kind` is TOR_CONNECTED_NONE,
/// TOR_CONNECTED_IPV4 or TOR_CONNECTED_IPV6, `addr` is empty or 4 or 16
/// bytes, `ttl` the cache lifetime in seconds (0 for an empty body).
pub type TorConnected = {
  kind: Int;
  addr: Vec[UInt8];
  ttl: Int;
}

/// Decoded RELAY END payload: `reason` is an END reason id (empty bodies
/// become TOR_END_REASON_MISC), `has_addr`/`addr`/`ttl` describe the optional
/// EXITPOLICY address block (ttl 4294967295 when the TTL was absent).
pub type TorEnd = {
  reason: Int;
  has_addr: Bool;
  addr: Vec[UInt8];
  ttl: Int;
}

/// Decoded RELAY SENDME payload. `legacy` is true for an empty body (the
/// v0 form, no version byte). `version` is the first body byte otherwise;
/// version 1 requires a digest of at least 20 bytes, of which `digest`
/// holds the first 20 (the rest of DATA is ignored), while `data_len` is
/// the declared DATA length. The digest is never verified: it is the
/// rolling digest of the triggering DATA-bearing relay cell, and this
/// module is crypto-free. A circuit-level SENDME has stream_id 0; a
/// stream-level SENDME carries the stream id.
pub type TorSendme = {
  version: Int;
  legacy: Bool;
  data_len: Int;
  digest: Vec[UInt8];
}

/// Decoded RELAY RESOLVE payload: the NUL-terminated hostname bytes with
/// the terminator removed.
pub type TorResolve = {
  name: Vec[UInt8];
}

/// Decoded RELAY RESOLVED answer (the first one when several are present):
/// `atype` is a RESOLVED type id, `value` the answer bytes (4 for IPv4, 16
/// for IPv6, a non-terminated DNS name for hostnames) and `ttl` the 32-bit
/// cache lifetime; `consumed` is the answer length (6 + declared value
/// length) so callers can walk multiple answers.
pub type TorResolved = {
  atype: Int;
  value: Vec[UInt8];
  ttl: Int;
  consumed: Int;
}

/// Decoded NETINFO body: `time` is the big-endian timestamp, `other_atype`/
/// `other_addr` the observed peer address, `n_my_addr` the declared count
/// and the parallel `my_atypes`/`my_addrs` lists this party's addresses.
/// `consumed` is the number of bytes the declared fields occupied (trailing
/// bytes are ignored, as the spec requires).
pub type TorNetinfo = {
  time: Int;
  other_atype: Int;
  other_addr: Vec[UInt8];
  n_my_addr: Int;
  my_atypes: Vec[Int];
  my_addrs: Vec[Vec[UInt8]];
  consumed: Int;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

// Ok(v) for Result[TorCell, Str].
fn _ok_cell(v: TorCell) -> Result[TorCell, Str] {
  return Ok(v);
}

// Err(m) for Result[TorCell, Str].
fn _err_cell(m: Str) -> Result[TorCell, Str] {
  return Err(m);
}

// Ok(v) for Result[TorVersions, Str].
fn _ok_versions(v: TorVersions) -> Result[TorVersions, Str] {
  return Ok(v);
}

// Err(m) for Result[TorVersions, Str].
fn _err_versions(m: Str) -> Result[TorVersions, Str] {
  return Err(m);
}

// Ok(v) for Result[TorRelay, Str].
fn _ok_relay(v: TorRelay) -> Result[TorRelay, Str] {
  return Ok(v);
}

// Err(m) for Result[TorRelay, Str].
fn _err_relay(m: Str) -> Result[TorRelay, Str] {
  return Err(m);
}

// Ok(v) for Result[TorBegin, Str].
fn _ok_begin(v: TorBegin) -> Result[TorBegin, Str] {
  return Ok(v);
}

// Err(m) for Result[TorBegin, Str].
fn _err_begin(m: Str) -> Result[TorBegin, Str] {
  return Err(m);
}

// Ok(v) for Result[TorConnected, Str].
fn _ok_connected(v: TorConnected) -> Result[TorConnected, Str] {
  return Ok(v);
}

// Err(m) for Result[TorConnected, Str].
fn _err_connected(m: Str) -> Result[TorConnected, Str] {
  return Err(m);
}

// Ok(v) for Result[TorEnd, Str].
fn _ok_end(v: TorEnd) -> Result[TorEnd, Str] {
  return Ok(v);
}

// Err(m) for Result[TorEnd, Str].
fn _err_end(m: Str) -> Result[TorEnd, Str] {
  return Err(m);
}

// Ok(v) for Result[TorSendme, Str].
fn _ok_sendme(v: TorSendme) -> Result[TorSendme, Str] {
  return Ok(v);
}

// Err(m) for Result[TorSendme, Str].
fn _err_sendme(m: Str) -> Result[TorSendme, Str] {
  return Err(m);
}

// Ok(v) for Result[TorResolve, Str].
fn _ok_resolve(v: TorResolve) -> Result[TorResolve, Str] {
  return Ok(v);
}

// Err(m) for Result[TorResolve, Str].
fn _err_resolve(m: Str) -> Result[TorResolve, Str] {
  return Err(m);
}

// Ok(v) for Result[TorResolved, Str].
fn _ok_resolved(v: TorResolved) -> Result[TorResolved, Str] {
  return Ok(v);
}

// Err(m) for Result[TorResolved, Str].
fn _err_resolved(m: Str) -> Result[TorResolved, Str] {
  return Err(m);
}

// Ok(v) for Result[TorNetinfo, Str].
fn _ok_netinfo(v: TorNetinfo) -> Result[TorNetinfo, Str] {
  return Ok(v);
}

// Err(m) for Result[TorNetinfo, Str].
fn _err_netinfo(m: Str) -> Result[TorNetinfo, Str] {
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

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Decimal text of v for error messages (digits/sign only; never 0x00).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// "<msg> at <off>": the error text convention of this module.
fn _at(msg: Str, off: Int) -> Str {
  return msg + " at " + _int_str(off);
}

// Big-endian u16 at `pos`; callers guarantee the bounds.
fn _u16(data: &Vec[UInt8], pos: Int) -> Int {
  return (_byte(data, pos) << 8) | _byte(data, pos + 1);
}

// Big-endian u32 at `pos`; callers guarantee the bounds.
fn _u32(data: &Vec[UInt8], pos: Int) -> Int {
  return (_byte(data, pos) << 24) | (_byte(data, pos + 1) << 16) |
    (_byte(data, pos + 2) << 8) | _byte(data, pos + 3);
}

// Append data[a, b) to out; callers guarantee the bounds.
fn _copy_span(data: &Vec[UInt8], a: Int, b: Int, out: &mut Vec[UInt8]) {
  var i = a;
  while i < b {
    out.push(data[i]);
    i = i + 1;
  }
}

// Index of the first byte equal to `target` in [from, to), or -1.
fn _find_byte(data: &Vec[UInt8], from: Int, to: Int, target: Int) -> Int {
  var i = from;
  while i < to {
    if _byte(data, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the last byte equal to `target` in [from, to), or -1.
fn _find_last_byte(data: &Vec[UInt8], from: Int, to: Int, target: Int) -> Int {
  var found = -1;
  var i = from;
  while i < to {
    if _byte(data, i) == target {
      found = i;
    }
    i = i + 1;
  }
  return found;
}

// Index of the first NUL in [from, to), or -1.
fn _find_nul(data: &Vec[UInt8], from: Int, to: Int) -> Int {
  return _find_byte(data, from, to, _TOR_NUL);
}

// Parse data[a, b) as a decimal unsigned integer <= cap (no sign, no leading
// spaces). `msg` is the caller's error text for every failure.
fn _parse_dec(data: &Vec[UInt8], a: Int, b: Int, cap: Int, msg: Str) -> Result[Int, Str] {
  if a >= b {
    return _err_int(msg);
  }
  let lim = cap / 10;
  let rem = cap % 10;
  var v: Int = 0;
  var i = a;
  while i < b {
    let c = _byte(data, i);
    if c < _TOR_DIGIT_0 || c > _TOR_DIGIT_9 {
      return _err_int(msg);
    }
    let d = c - _TOR_DIGIT_0;
    if v > lim {
      return _err_int(msg);
    }
    if v == lim && d > rem {
      return _err_int(msg);
    }
    v = v * 10 + d;
    i = i + 1;
  }
  return _ok_int(v);
}

// --------------------------------------------------
//  ASCII conversion (documented narrow helper)
// --------------------------------------------------

// True when byte c is printable ASCII 0x20..0x7E. NUL and all other
// control bytes, plus every byte >= 128, are rejected, so _bytes_to_ascii
// can never hand sb_to_str a 0x00 byte.
fn _ascii_byte_ok(c: Int) -> Bool {
  if c < _TOR_PRINTABLE_LO { return false; }
  if c > _TOR_PRINTABLE_HI { return false; }
  return true;
}

// Decode `v` as printable ASCII text. Empty input yields "".
fn _bytes_to_ascii(v: &Vec[UInt8]) -> Result[Str, Str] {
  let n = v.len();
  if n == 0 {
    return _ok_str("");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let c = _byte(v, i);
    if !_ascii_byte_ok(c) {
      return _err_str("tor: not printable ascii");
    }
    out.push(c as UInt8);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// Decode `v` as printable ASCII text (0x20..0x7E only). This is a
/// convenience for hostnames, IPv4 literals and error strings; binary
/// fields stay Vec[UInt8] everywhere else.
/// Params: v - the bytes to decode.
/// Returns: Ok(text) (empty for empty input).
/// Error case: Err("tor: not printable ascii") when any byte is NUL, a
/// control byte or >= 128. Complexity: O(len(v)).
pub fn tor_ascii_to_str(v: &Vec[UInt8]) -> Result[Str, Str] {
  return _bytes_to_ascii(v);
}

// --------------------------------------------------
//  Cell framing
// --------------------------------------------------

// Finish a cell whose header has been read: `wide` selects the framing,
// `circ`/`cmd` are known, `cmd_end` points just past the command byte.
// Variable-length commands read a u16 Length and that many body bytes;
// fixed-length commands copy CELL_BODY_LEN bytes after the command.
fn _parse_cell_tail(data: &Vec[UInt8], off: Int, wide: Bool, circ: Int, cmd: Int, cmd_end: Int) -> Result[TorCell, Str] {
  let n = data.len();
  if tor_cell_is_variable_cmd(cmd) {
    if n - cmd_end < 2 {
      return _err_cell(_at("tor: variable cell length truncated", off));
    }
    let len = _u16(data, cmd_end);
    let body_off = cmd_end + 2;
    if n - body_off < len {
      return _err_cell(_at("tor: variable cell body truncated", off));
    }
    var body = Vec[UInt8].new();
    _copy_span(data, body_off, body_off + len, &mut body);
    return _ok_cell(TorCell{
      wide: wide;
      variable: true;
      circ_id: circ;
      command: cmd;
      payload: body;
      consumed: body_off + len - off;
    });
  }
  var total = TOR_CELL_NARROW_LEN;
  if wide {
    total = TOR_CELL_WIDE_LEN;
  }
  if n - off < total {
    return _err_cell(_at("tor: fixed cell truncated", off));
  }
  var body2 = Vec[UInt8].new();
  _copy_span(data, cmd_end, cmd_end + TOR_CELL_BODY_LEN, &mut body2);
  return _ok_cell(TorCell{
    wide: wide;
    variable: false;
    circ_id: circ;
    command: cmd;
    payload: body2;
    consumed: total;
  });
}

/// Parse one cell starting at `off`, auto-detecting the CircID width: when
/// either of the first two bytes is nonzero the cell uses the wide (4-byte
/// CircID) framing, otherwise the narrow (2-byte CircID) framing. Commands
/// 7 and >= 128 take the variable-length shape (u16 Length after the
/// command); every other command is fixed-length, and a fixed cell must
/// provide all 512 (narrow) or 514 (wide) bytes.
///
/// Caveat (documented, not a bug): a wide cell whose CircID high half is
/// zero (NETINFO/DESTROY/VERSIONS on a v4 link) is indistinguishable from a
/// narrow cell by this rule; parse it with tor_parse_cell_v using the
/// negotiated link version.
///
/// Params: data - the buffer; off - start offset.
/// Returns: Ok(cell) with `consumed` set so `off + consumed` is the next
/// cell.
/// Error case: Err("tor: <what> at <off>") for an out-of-range offset, a
/// truncated narrow/wide header, a truncated variable length field, a
/// variable body shorter than its Length, or a fixed cell shorter than 512
/// (narrow) / 514 (wide) bytes. Complexity: O(cell length).
pub fn tor_parse_cell(data: &Vec[UInt8], off: Int) -> Result[TorCell, Str] {
  let n = data.len();
  if off < 0 || off > n {
    return _err_cell(_at("tor: cell offset out of range", off));
  }
  if n - off < 3 {
    return _err_cell(_at("tor: cell truncated", off));
  }
  let b0 = _byte(data, off);
  let b1 = _byte(data, off + 1);
  if b0 != 0 || b1 != 0 {
    if n - off < 5 {
      return _err_cell(_at("tor: wide cell header truncated", off));
    }
    let circ = _u32(data, off);
    let cmd = _byte(data, off + 4);
    return _parse_cell_tail(data, off, true, circ, cmd, off + 5);
  }
  let circ2 = _u16(data, off);
  let cmd2 = _byte(data, off + 2);
  return _parse_cell_tail(data, off, false, circ2, cmd2, off + 3);
}

/// Parse one cell starting at `off` for a link whose version is already
/// known: v >= 4 uses the wide framing, v < 4 the narrow one (v 0 is the
/// pre-negotiation VERSIONS case). Unlike tor_parse_cell this is correct
/// for zero-CircID wide cells.
/// Params: data - the buffer; off - start offset; link_version - the
/// negotiated (or currently assumed) link protocol version.
/// Returns: Ok(cell) with `consumed`.
/// Error case: Err("tor: <what> at <off>") for a negative version, an
/// out-of-range offset, truncated headers/bodies or a short fixed cell.
/// Complexity: O(cell length).
pub fn tor_parse_cell_v(data: &Vec[UInt8], off: Int, link_version: Int) -> Result[TorCell, Str] {
  let n = data.len();
  if off < 0 || off > n {
    return _err_cell(_at("tor: cell offset out of range", off));
  }
  if link_version < 0 {
    return _err_cell(_at("tor: negative link version", off));
  }
  if link_version >= 4 {
    if n - off < 5 {
      return _err_cell(_at("tor: wide cell header truncated", off));
    }
    let circ = _u32(data, off);
    let cmd = _byte(data, off + 4);
    return _parse_cell_tail(data, off, true, circ, cmd, off + 5);
  }
  if n - off < 3 {
    return _err_cell(_at("tor: cell truncated", off));
  }
  let circ2 = _u16(data, off);
  let cmd2 = _byte(data, off + 2);
  return _parse_cell_tail(data, off, false, circ2, cmd2, off + 3);
}

// --------------------------------------------------
//  VERSIONS handshake
// --------------------------------------------------

/// Parse a VERSIONS body: a series of big-endian u16 link versions. An
/// empty body is structurally acceptable (consumed 0) but yields no common
/// version in tor_versions_choose.
/// Params: payload - the VERSIONS body bytes; off - start offset.
/// Returns: Ok(versions) with `consumed` (= body length).
/// Error case: Err("tor: versions offset out of range at <off>") or
/// Err("tor: versions body has odd length at <off>"). Complexity: O(n).
pub fn tor_parse_versions(payload: &Vec[UInt8], off: Int) -> Result[TorVersions, Str] {
  let n = payload.len();
  if off < 0 || off > n {
    return _err_versions(_at("tor: versions offset out of range", off));
  }
  let avail = n - off;
  if avail % 2 != 0 {
    return _err_versions(_at("tor: versions body has odd length", off));
  }
  var vs = Vec[Int].new();
  var i = off;
  while i < n {
    let v = _u16(payload, i);
    vs.push(v);
    i = i + 2;
  }
  return _ok_versions(TorVersions{ versions: vs; consumed: avail });
}

/// Highest link version present in both lists that is still defined
/// (>= 3), or 0 when there is no common usable version. Version numbers
/// below 3 are ignored, matching the spec rule that 1 and 2 are obsolete.
/// Params: sent - versions this party sent; recv - versions the peer sent.
/// Returns: the chosen version, or 0.
/// Error case: none. Complexity: O(len(sent) * len(recv)).
pub fn tor_versions_choose(sent: &Vec[Int], recv: &Vec[Int]) -> Int {
  var best = 0;
  var i = 0;
  let sn = sent.len();
  let rn = recv.len();
  while i < sn {
    let s: Int = sent[i];
    if s >= TOR_MIN_LINK_VERSION {
      var j = 0;
      while j < rn {
        let r: Int = recv[j];
        if r == s && s > best {
          best = s;
        }
        j = j + 1;
      }
    }
    i = i + 1;
  }
  return best;
}

// --------------------------------------------------
//  RELAY envelope
// --------------------------------------------------

/// Parse a RELAY envelope at `off`: command(1) + recognized(2) +
/// streamID(2) + digest(4) + length(2) + data(length). The digest is copied
/// out verbatim and never verified (no crypto in this module).
/// Params: payload - the cell body (or any buffer) holding the envelope;
/// off - start offset.
/// Returns: Ok(relay) with `consumed` = 11 + length.
/// Error case: Err("tor: relay offset out of range at <off>") for a bad
/// offset, Err("tor: relay header truncated at <off>") when fewer than 11
/// bytes remain, Err("tor: relay length overrun at <off>") when the
/// declared length exceeds the remaining bytes. Complexity: O(length).
pub fn tor_parse_relay(payload: &Vec[UInt8], off: Int) -> Result[TorRelay, Str] {
  let n = payload.len();
  if off < 0 || off > n {
    return _err_relay(_at("tor: relay offset out of range", off));
  }
  if n - off < TOR_RELAY_HEADER_LEN {
    return _err_relay(_at("tor: relay header truncated", off));
  }
  let cmd = _byte(payload, off);
  let rec = _u16(payload, off + 1);
  let sid = _u16(payload, off + 3);
  var dig = Vec[UInt8].new();
  _copy_span(payload, off + 5, off + 9, &mut dig);
  let len = _u16(payload, off + 9);
  if n - off - TOR_RELAY_HEADER_LEN < len {
    return _err_relay(_at("tor: relay length overrun", off));
  }
  var d = Vec[UInt8].new();
  _copy_span(payload, off + TOR_RELAY_HEADER_LEN, off + TOR_RELAY_HEADER_LEN + len, &mut d);
  return _ok_relay(TorRelay{
    cmd: cmd;
    recognized: rec;
    stream_id: sid;
    digest: dig;
    length: len;
    data: d;
    consumed: TOR_RELAY_HEADER_LEN + len;
  });
}

// --------------------------------------------------
//  Typed RELAY payloads
// --------------------------------------------------

/// Decode a RELAY BEGIN payload: "ADDRESS:PORT" as a NUL-terminated
/// string, followed by an optional 4-byte FLAGS word. IPv6 addresses are
/// bracketed ("[::1]:443") and the brackets are stripped from `addr`; all
/// other addresses are taken up to the last ':' before the terminator.
/// Params: data - the RELAY data bytes.
/// Returns: Ok(begin).
/// Error case: Err("tor: begin ...") for an empty body, a missing NUL, an
/// empty address, a missing ':' port separator, a non-decimal or
/// out-of-range (> 65535) port, or a FLAGS field that is not exactly 4
/// bytes. Port 0 is accepted (the spec recommends 1..65535).
/// Complexity: O(len(data)).
pub fn tor_relay_decode_begin(data: &Vec[UInt8]) -> Result[TorBegin, Str] {
  let n = data.len();
  if n == 0 {
    return _err_begin("tor: begin empty body");
  }
  let nul = _find_nul(data, 0, n);
  if nul < 0 {
    return _err_begin("tor: begin address not terminated");
  }
  if nul == 0 {
    return _err_begin("tor: begin empty address");
  }
  var addr = Vec[UInt8].new();
  var port = 0;
  if _byte(data, 0) == _TOR_LBRACKET {
    let close = _find_byte(data, 1, nul, _TOR_RBRACKET);
    if close < 0 {
      return _err_begin("tor: begin ipv6 address not closed");
    }
    if close == 1 {
      return _err_begin("tor: begin empty address");
    }
    _copy_span(data, 1, close, &mut addr);
    if close + 1 >= nul {
      return _err_begin("tor: begin port missing");
    }
    if _byte(data, close + 1) != _TOR_COLON {
      return _err_begin("tor: begin port missing");
    }
    if close + 2 >= nul {
      return _err_begin("tor: begin port missing");
    }
    let pr = _parse_dec(data, close + 2, nul, 65535, "tor: begin bad port");
    if !pr.is_ok {
      return _err_begin(pr.error);
    }
    let pv: Int = pr.value;
    port = pv;
  } else {
    let colon = _find_last_byte(data, 0, nul, _TOR_COLON);
    if colon < 0 {
      return _err_begin("tor: begin port missing");
    }
    if colon == 0 {
      return _err_begin("tor: begin empty address");
    }
    if colon + 1 >= nul {
      return _err_begin("tor: begin port missing");
    }
    _copy_span(data, 0, colon, &mut addr);
    let pr2 = _parse_dec(data, colon + 1, nul, 65535, "tor: begin bad port");
    if !pr2.is_ok {
      return _err_begin(pr2.error);
    }
    let pv2: Int = pr2.value;
    port = pv2;
  }
  var flags = 0;
  var has_flags = false;
  if nul + 1 < n {
    if n - (nul + 1) != 4 {
      return _err_begin("tor: begin flags must be 4 bytes");
    }
    has_flags = true;
    flags = _u32(data, nul + 1);
  }
  return _ok_begin(TorBegin{ addr: addr; port: port; flags: flags; has_flags: has_flags; });
}

/// Decode a RELAY CONNECTED payload. Accepted bodies: empty (kind NONE),
/// 8 bytes (4 IPv4 octets + 4-byte TTL) and 25 bytes (4 zero octets, type
/// 6, 16 IPv6 octets, 4-byte TTL). Params: data - the RELAY data bytes.
/// Returns: Ok(connected).
/// Error case: Err("tor: connected bad body length") for any other length,
/// Err("tor: connected bad ipv6 marker") when the 25-byte form does not
/// start with four zero octets, Err("tor: connected bad ipv6 type") when
/// the type byte is not 6. Complexity: O(len(data)).
pub fn tor_relay_decode_connected(data: &Vec[UInt8]) -> Result[TorConnected, Str] {
  let n = data.len();
  if n == 0 {
    return _ok_connected(TorConnected{
      kind: TOR_CONNECTED_NONE;
      addr: Vec[UInt8].new();
      ttl: 0;
    });
  }
  if n == 8 {
    var a4 = Vec[UInt8].new();
    _copy_span(data, 0, 4, &mut a4);
    return _ok_connected(TorConnected{
      kind: TOR_CONNECTED_IPV4;
      addr: a4;
      ttl: _u32(data, 4);
    });
  }
  if n == 25 {
    let z0 = _byte(data, 0);
    let z1 = _byte(data, 1);
    let z2 = _byte(data, 2);
    let z3 = _byte(data, 3);
    if z0 != 0 || z1 != 0 || z2 != 0 || z3 != 0 {
      return _err_connected("tor: connected bad ipv6 marker");
    }
    if _byte(data, 4) != _TOR_ATYPE_IPV6 {
      return _err_connected("tor: connected bad ipv6 type");
    }
    var a6 = Vec[UInt8].new();
    _copy_span(data, 5, 21, &mut a6);
    return _ok_connected(TorConnected{
      kind: TOR_CONNECTED_IPV6;
      addr: a6;
      ttl: _u32(data, 21);
    });
  }
  return _err_connected("tor: connected bad body length");
}

/// Decode a RELAY END payload: a reason byte, plus for EXITPOLICY an
/// optional address block. Empty bodies become reason MISC. The EXITPOLICY
/// address block is accepted as 4-byte IPv4 or 16-byte IPv6 followed by a
/// 4-byte TTL; a missing TTL becomes 4294967295 (the spec's absent-TTL
/// default), and any other length is an error.
/// Params: data - the RELAY data bytes.
/// Returns: Ok(end).
/// Error case: Err("tor: end body has trailing bytes") for a non-EXITPOLICY
/// reason with more than one byte, Err("tor: end bad exitpolicy body") for
/// an EXITPOLICY length that is not 0/4/8/16/20 extra bytes.
/// Complexity: O(len(data)).
pub fn tor_relay_decode_end(data: &Vec[UInt8]) -> Result[TorEnd, Str] {
  let n = data.len();
  if n == 0 {
    return _ok_end(TorEnd{
      reason: TOR_END_REASON_MISC;
      has_addr: false;
      addr: Vec[UInt8].new();
      ttl: 0;
    });
  }
  let reason = _byte(data, 0);
  if reason != TOR_END_REASON_EXITPOLICY {
    if n != 1 {
      return _err_end("tor: end body has trailing bytes");
    }
    return _ok_end(TorEnd{
      reason: reason;
      has_addr: false;
      addr: Vec[UInt8].new();
      ttl: 0;
    });
  }
  if n == 1 {
    return _ok_end(TorEnd{
      reason: reason;
      has_addr: false;
      addr: Vec[UInt8].new();
      ttl: 0;
    });
  }
  if n == 5 {
    var ea = Vec[UInt8].new();
    _copy_span(data, 1, 5, &mut ea);
    return _ok_end(TorEnd{ reason: reason; has_addr: true; addr: ea; ttl: _TOR_TTL_UNKNOWN; });
  }
  if n == 9 {
    var ea2 = Vec[UInt8].new();
    _copy_span(data, 1, 5, &mut ea2);
    return _ok_end(TorEnd{ reason: reason; has_addr: true; addr: ea2; ttl: _u32(data, 5); });
  }
  if n == 17 {
    var ea3 = Vec[UInt8].new();
    _copy_span(data, 1, 17, &mut ea3);
    return _ok_end(TorEnd{ reason: reason; has_addr: true; addr: ea3; ttl: _TOR_TTL_UNKNOWN; });
  }
  if n == 21 {
    var ea4 = Vec[UInt8].new();
    _copy_span(data, 1, 17, &mut ea4);
    return _ok_end(TorEnd{ reason: reason; has_addr: true; addr: ea4; ttl: _u32(data, 17); });
  }
  return _err_end("tor: end bad exitpolicy body");
}

/// Decode a RELAY SENDME payload: VERSION(1) + DATA_LEN(2) + DATA. An
/// empty body is the legacy v0 form. Version 1 requires DATA_LEN >= 20 and
/// `digest` gets the first 20 DATA bytes (extra DATA is ignored); other
/// versions are accepted structurally and leave `digest` empty.
/// Params: data - the RELAY data bytes.
/// Returns: Ok(sendme).
/// Error case: Err("tor: sendme header truncated") for a non-empty body
/// shorter than 3 bytes, Err("tor: sendme data overrun") when DATA_LEN
/// exceeds the remaining bytes, Err("tor: sendme digest too short") for
/// version 1 with DATA_LEN < 20. Complexity: O(len(data)).
pub fn tor_relay_decode_sendme(data: &Vec[UInt8]) -> Result[TorSendme, Str] {
  let n = data.len();
  if n == 0 {
    return _ok_sendme(TorSendme{
      version: 0;
      legacy: true;
      data_len: 0;
      digest: Vec[UInt8].new();
    });
  }
  if n < 3 {
    return _err_sendme("tor: sendme header truncated");
  }
  let version = _byte(data, 0);
  let dl = _u16(data, 1);
  if n - 3 < dl {
    return _err_sendme("tor: sendme data overrun");
  }
  var dig = Vec[UInt8].new();
  if version == 1 {
    if dl < TOR_SENDME_DIGEST_LEN {
      return _err_sendme("tor: sendme digest too short");
    }
    _copy_span(data, 3, 3 + TOR_SENDME_DIGEST_LEN, &mut dig);
  }
  return _ok_sendme(TorSendme{
    version: version;
    legacy: false;
    data_len: dl;
    digest: dig;
  });
}

/// Decode a RELAY RESOLVE payload: a NUL-terminated hostname, with the
/// terminator required to be the final byte. Params: data - the RELAY data.
/// Returns: Ok(resolve) with `name` holding the bytes before the NUL.
/// Error case: Err("tor: resolve empty body"), Err("tor: resolve empty
/// name"), Err("tor: resolve name not terminated") or Err("tor: resolve
/// trailing bytes"). Complexity: O(len(data)).
pub fn tor_relay_decode_resolve(data: &Vec[UInt8]) -> Result[TorResolve, Str] {
  let n = data.len();
  if n == 0 {
    return _err_resolve("tor: resolve empty body");
  }
  let nul = _find_nul(data, 0, n);
  if nul < 0 {
    return _err_resolve("tor: resolve name not terminated");
  }
  if nul != n - 1 {
    return _err_resolve("tor: resolve trailing bytes");
  }
  if nul == 0 {
    return _err_resolve("tor: resolve empty name");
  }
  var name = Vec[UInt8].new();
  _copy_span(data, 0, nul, &mut name);
  return _ok_resolve(TorResolve{ name: name; });
}

/// Decode the first RELAY RESOLVED answer: Type(1) + Length(1) +
/// Value(Length) + TTL(4). Known address types are length-checked (IPv4
/// must be 4 bytes, IPv6 16); hostname and error values keep their bytes
/// as-is. `consumed` lets callers walk the remaining answers.
/// Params: data - the RELAY data bytes.
/// Returns: Ok(resolved).
/// Error case: Err("tor: resolved answer truncated") when fewer than 6
/// bytes remain after the header, Err("tor: resolved ipv4 length") or
/// Err("tor: resolved ipv6 length") for a wrong address length.
/// Complexity: O(len(data)).
pub fn tor_relay_decode_resolved(data: &Vec[UInt8]) -> Result[TorResolved, Str] {
  let n = data.len();
  if n < 6 {
    return _err_resolved("tor: resolved answer truncated");
  }
  let atype = _byte(data, 0);
  let alen = _byte(data, 1);
  if n < alen + 6 {
    return _err_resolved("tor: resolved answer truncated");
  }
  if atype == _TOR_ATYPE_IPV4 && alen != 4 {
    return _err_resolved("tor: resolved ipv4 length");
  }
  if atype == _TOR_ATYPE_IPV6 && alen != 16 {
    return _err_resolved("tor: resolved ipv6 length");
  }
  var value = Vec[UInt8].new();
  _copy_span(data, 2, 2 + alen, &mut value);
  return _ok_resolved(TorResolved{
    atype: atype;
    value: value;
    ttl: _u32(data, 2 + alen);
    consumed: alen + 6;
  });
}

// --------------------------------------------------
//  NETINFO handshake body
// --------------------------------------------------

/// Parse a NETINFO body at `off`: TIME(4) + OTHERADDR(atype 1, alen 1,
/// value alen) + NMYADDR(1) + NMYADDR * (atype 1, alen 1, value alen).
/// Trailing bytes are ignored as the spec requires; the declared
/// addresses are copied out without validating atype/alen pairing.
/// Params: data - the NETINFO body; off - start offset.
/// Returns: Ok(netinfo) with `consumed` = bytes of the declared fields.
/// Error case: Err("tor: netinfo <what> at <off>") for an out-of-range
/// offset, a truncated header, or a truncated observed/declared address.
/// Complexity: O(len(data)).
pub fn tor_decode_netinfo(data: &Vec[UInt8], off: Int) -> Result[TorNetinfo, Str] {
  let n = data.len();
  if off < 0 || off > n {
    return _err_netinfo(_at("tor: netinfo offset out of range", off));
  }
  if n - off < 6 {
    return _err_netinfo(_at("tor: netinfo header truncated", off));
  }
  let time = _u32(data, off);
  let oatype = _byte(data, off + 4);
  let oalen = _byte(data, off + 5);
  if n - off - 6 < oalen {
    return _err_netinfo(_at("tor: netinfo other address truncated", off));
  }
  var oaddr = Vec[UInt8].new();
  _copy_span(data, off + 6, off + 6 + oalen, &mut oaddr);
  var i = off + 6 + oalen;
  if i >= n {
    return _err_netinfo(_at("tor: netinfo address count missing", off));
  }
  let nm = _byte(data, i);
  i = i + 1;
  var atypes = Vec[Int].new();
  var addrs = Vec[Vec[UInt8]].new();
  var k = 0;
  while k < nm {
    if n - i < 2 {
      return _err_netinfo(_at("tor: netinfo my address truncated", off));
    }
    let at = _byte(data, i);
    let al = _byte(data, i + 1);
    i = i + 2;
    if n - i < al {
      return _err_netinfo(_at("tor: netinfo my address truncated", off));
    }
    var av = Vec[UInt8].new();
    _copy_span(data, i, i + al, &mut av);
    i = i + al;
    atypes.push(at);
    addrs.push(av);
    k = k + 1;
  }
  return _ok_netinfo(TorNetinfo{
    time: time;
    other_atype: oatype;
    other_addr: oaddr;
    n_my_addr: nm;
    my_atypes: atypes;
    my_addrs: addrs;
    consumed: i - off;
  });
}
