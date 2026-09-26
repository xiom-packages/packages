// XIOM -- xiom.tftp: TFTP packet codec (RFC 1350 + RFC 2347/2348/2349)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets) encoder and decoder for the six TFTP
// packet kinds -- RRQ(1), WRQ(2), DATA(3), ACK(4), ERROR(5) and OACK(6) --
// with the RFC 2347 option extension (RFC 2348 blksize, RFC 2349 timeout
// and tsize, plus pass-through options such as windowsize). All 16-bit
// fields are big-endian.
//
// A parsed packet is one flat TftpPacket value: scalar fields, the
// filename/mode/error-message strings, the DATA payload bytes and two
// parallel option pools (names and values) whose valid index range is
// 0..tftp_option_count(p)-1. There is no Vec[StructType] and no nested
// struct field. Parser errors, the exact-size (no trailing bytes) policy
// and the canonical emitter are specified in SPEC.md.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[fn].
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles);
//     option pools are filled through &mut parameters and never returned
//     inside tuples.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before arithmetic or comparison.
//   * Str values read from Vec[Str] pools are bound to typed locals first,
//     and Str equality is always byte-wise (`_eq_ci`) -- `==` on Str values
//     read from a Vec lowers to a pointer comparison (BUG 17).
//   * &struct.field / &result.value are bound to typed locals before being
//     passed as &Vec / &mut Vec parameters.
//   * all packing is arithmetic (division/modulo); no bitwise operation is
//     applied to a value that may have the sign bit set.
//
// See SPEC.md for the byte layout tables, the mode/option rules, the error
// catalog and the test plan.

module xiom.tftp

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// TFTP opcodes: RFC 1350 section 5 plus OACK from RFC 2347.
pub const TFTP_OPCODE_RRQ: Int = 1;
pub const TFTP_OPCODE_WRQ: Int = 2;
pub const TFTP_OPCODE_DATA: Int = 3;
pub const TFTP_OPCODE_ACK: Int = 4;
pub const TFTP_OPCODE_ERROR: Int = 5;
pub const TFTP_OPCODE_OACK: Int = 6;

// Option bounds: RFC 2348 allows blksize 8..65464; RFC 2349 allows timeout
// 1..255 seconds; tsize is a decimal byte count up to the protocol maximum
// (65535 blocks x 65464 bytes = 4290204840 fits in 32 bits, so 4294967295
// is the documented ceiling).
pub const TFTP_BLKSIZE_MIN: Int = 8;
pub const TFTP_BLKSIZE_MAX: Int = 65464;
pub const TFTP_TIMEOUT_MIN: Int = 1;
pub const TFTP_TIMEOUT_MAX: Int = 255;
pub const TFTP_TSIZE_MAX: Int = 4294967295;

// The classic RFC 1350 block size, still the default when no blksize option
// was negotiated.
pub const TFTP_DEFAULT_BLKSIZE: Int = 512;

// --------------------------------------------------
//  Private constants
// --------------------------------------------------

const _TFTP_MAX_U16: Int = 65535;
const _TFTP_ZERO: Int = 48;    // '0'
const _TFTP_NINE: Int = 57;    // '9'
const _TFTP_UPPER_A: Int = 65; // 'A'
const _TFTP_UPPER_Z: Int = 90; // 'Z'
const _TFTP_SPACE: Int = 32;   // ' '
const _TFTP_TILDE: Int = 126;  // '~'

// --------------------------------------------------
//  Parsed packet
// --------------------------------------------------

/// Parsed TFTP packet. `opcode` is always 1..6 for a value returned by a
/// parser. Fields not owned by that opcode stay at their zero value: for
/// RRQ/WRQ `filename` and canonical lowercase `mode` are set; for DATA
/// `block` and `payload`; for ACK `block`; for ERROR `error_code` and
/// `error_message`; for RRQ/WRQ/OACK `option_names`/`option_values` hold
/// the RFC 2347 TLVs in wire order, `option_values[i]` belonging to
/// `option_names[i]`. The struct is flat: scalars, strings, one payload
/// vector and two parallel option pools with the index range
/// 0..tftp_option_count(p)-1, so it can be copied and passed by reference.
pub type TftpPacket = {
  opcode: Int;
  filename: Str;
  mode: Str;
  block: Int;
  error_code: Int;
  error_message: Str;
  payload: Vec[UInt8];
  option_names: Vec[Str];
  option_values: Vec[Str];
}

// --------------------------------------------------
//  Result leaf helpers (see the module header)
// --------------------------------------------------

// Ok(v) for Result[TftpPacket, Str].
fn _ok_packet(v: TftpPacket) -> Result[TftpPacket, Str] {
  return Ok(v);
}

// Err(m) for Result[TftpPacket, Str].
fn _err_packet(m: Str) -> Result[TftpPacket, Str] {
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
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned 16-bit integer at [pos, pos+2), big-endian. The caller guarantees
// both bytes are in bounds.
fn _u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Append the low 16 bits of `v` in big-endian order. Callers pass a value
// already clamped to 0..65535 with `_clamp_u16`.
fn _push_u16(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Clamp a block number or error code to the unsigned 16-bit range.
fn _clamp_u16(v: Int) -> Int {
  if v < 0 {
    return 0;
  }
  if v > _TFTP_MAX_U16 {
    return _TFTP_MAX_U16;
  }
  return v;
}

// Index of the first 0x00 byte in [start, end), or -1 when there is none.
fn _nul_at(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var i = start;
  while i < end {
    if _byte(data, i) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Copy bytes [start, end) into a fresh vector. The caller guarantees
// 0 <= start <= end <= data.len().
fn _copy_range(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Materialize bytes [start, end) as a Str (one allocation, no validation).
fn _str_between(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  let bytes = _copy_range(data, start, end);
  return builder.sb_to_str(&bytes);
}

// --------------------------------------------------
//  String helpers
// --------------------------------------------------

// Byte `i` of a Str widened to an Int (0..255); callers guarantee bounds.
fn _str_byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True when every byte of `s` is printable ASCII 0x20..0x7E. The empty
// string is trivially printable; emptiness is checked separately.
fn _is_printable(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let c = _str_byte(s, i);
    if c < _TFTP_SPACE || c > _TFTP_TILDE {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ASCII-case-insensitive equality of `s` against the lowercase literal
// `lower`. Used for the three modes and the three known option names, so no
// Str is ever compared with `==` (BUG 17 discipline).
fn _eq_ci(s: Str, lower: Str) -> Bool {
  let n = s.len();
  if n != lower.len() {
    return false;
  }
  var i = 0;
  while i < n {
    var c = _str_byte(s, i);
    if c >= _TFTP_UPPER_A && c <= _TFTP_UPPER_Z {
      c = c + 32;
    }
    if c != _str_byte(lower, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Mode and option rules
// --------------------------------------------------

// The canonical lowercase mode name for a case-insensitive netascii/octet/
// mail `m`, or "" when `m` is none of them. RFC 1350 defines the three
// modes; this codec never translates netascii or mail content.
fn _mode_canonical(m: Str) -> Str {
  if _eq_ci(m, "netascii") {
    return "netascii";
  }
  if _eq_ci(m, "octet") {
    return "octet";
  }
  if _eq_ci(m, "mail") {
    return "mail";
  }
  return "";
}

// Canonical (lowercase) spelling of a known option name; unknown names are
// returned verbatim (pass-through).
fn _option_canonical(name: Str) -> Str {
  if _eq_ci(name, "blksize") {
    return "blksize";
  }
  if _eq_ci(name, "timeout") {
    return "timeout";
  }
  if _eq_ci(name, "tsize") {
    return "tsize";
  }
  return name;
}

// Canonical decimal scanner for option values: one or more ASCII digits,
// no leading zero unless the value is exactly "0". Returns the value when
// it is 0..max, -1 for a syntax error and -2 for a value above `max`.
// Accumulation stops once the running value exceeds `max`, so arbitrarily
// long digit runs cannot overflow.
fn _scan_decimal(s: Str, max: Int) -> Int {
  let n = s.len();
  if n == 0 {
    return -1;
  }
  if n > 1 && _str_byte(s, 0) == _TFTP_ZERO {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let c = _str_byte(s, i);
    if c < _TFTP_ZERO || c > _TFTP_NINE {
      return -1;
    }
    if v <= max {
      v = v * 10 + (c - _TFTP_ZERO);
    }
    i = i + 1;
  }
  if v > max {
    return -2;
  }
  return v;
}

// "" when the TLV (name, value) is acceptable; otherwise the stable error
// text. Known names are matched case-insensitively and range-checked;
// everything else is pass-through, so windowsize and future options are
// carried verbatim with no semantics.
fn _option_error(name: Str, value: Str) -> Str {
  if name.len() == 0 {
    return "tftp: bad option name";
  }
  if !_is_printable(name) {
    return "tftp: bad option name";
  }
  if _eq_ci(name, "blksize") {
    let v = _scan_decimal(value, TFTP_BLKSIZE_MAX);
    if v < TFTP_BLKSIZE_MIN {
      return "tftp: bad block size";
    }
    return "";
  }
  if _eq_ci(name, "timeout") {
    let v = _scan_decimal(value, TFTP_TIMEOUT_MAX);
    if v < TFTP_TIMEOUT_MIN {
      return "tftp: bad option value";
    }
    return "";
  }
  if _eq_ci(name, "tsize") {
    let v = _scan_decimal(value, TFTP_TSIZE_MAX);
    if v < 0 {
      return "tftp: bad option value";
    }
    return "";
  }
  return "";
}

// Validate a parallel option pool pair. "" when the pools have equal
// lengths and every entry is valid; "tftp: option pool mismatch" on drift;
// otherwise the first TLV error in wire order.
fn _options_error(names: &Vec[Str], values: &Vec[Str]) -> Str {
  if names.len() != values.len() {
    return "tftp: option pool mismatch";
  }
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    let vl: Str = values[i];
    let e = _option_error(nm, vl);
    if e.len() > 0 {
      return e;
    }
    i = i + 1;
  }
  return "";
}

// Append a NUL-terminated field: the bytes of `s` followed by 0x00.
fn _push_cstr(out: &mut Vec[UInt8], s: Str) {
  builder.sb_push_str(out, s);
  out.push(0 as UInt8);
}

// Append the option TLVs in pool order, canonicalizing known names.
// Callers validate with `_options_error` first (the pools must not drift).
fn _push_options(out: &mut Vec[UInt8], names: &Vec[Str], values: &Vec[Str]) {
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    let vl: Str = values[i];
    _push_cstr(out, _option_canonical(nm));
    _push_cstr(out, vl);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Encoders
// --------------------------------------------------

// Build an RRQ (opcode 1) or WRQ (opcode 2): opcode, filename, mode and
// option TLVs. Errors: "tftp: bad filename" (empty or non-printable),
// "tftp: bad mode" (not netascii/octet/mail, case-insensitive), then the
// option catalog.
fn _build_rq(op: Int, filename: Str, mode: Str, names: &Vec[Str], values: &Vec[Str]) -> Result[Vec[UInt8], Str] {
  if filename.len() == 0 {
    return _err_bytes("tftp: bad filename");
  }
  if !_is_printable(filename) {
    return _err_bytes("tftp: bad filename");
  }
  let mode_c = _mode_canonical(mode);
  if mode_c.len() == 0 {
    return _err_bytes("tftp: bad mode");
  }
  let oerr = _options_error(names, values);
  if oerr.len() > 0 {
    return _err_bytes(oerr);
  }
  var out = Vec[UInt8].new();
  _push_u16(&mut out, op);
  _push_cstr(&mut out, filename);
  _push_cstr(&mut out, mode_c);
  _push_options(&mut out, names, values);
  return _ok_bytes(out);
}

/// Build a read request (opcode 1): `[u16 1][filename 0x00][mode 0x00]`
/// followed by the option TLVs. `filename` must be non-empty printable
/// ASCII; `mode` is matched case-insensitively against netascii/octet/mail
/// and emitted lowercase; `option_names`/`option_values` are the parallel
/// TLV pools (both empty for a plain request). Errors: "tftp: bad
/// filename", "tftp: bad mode", "tftp: option pool mismatch" and the
/// per-option catalog (see SPEC.md).
/// Complexity: O(filename + mode + option bytes).
pub fn tftp_build_rrq(filename: Str, mode: Str, option_names: &Vec[Str], option_values: &Vec[Str]) -> Result[Vec[UInt8], Str] {
  return _build_rq(TFTP_OPCODE_RRQ, filename, mode, option_names, option_values);
}

/// Build a write request (opcode 2): `[u16 2][filename 0x00][mode 0x00]`
/// followed by the option TLVs. Identical rules to `tftp_build_rrq`.
/// Complexity: O(filename + mode + option bytes).
pub fn tftp_build_wrq(filename: Str, mode: Str, option_names: &Vec[Str], option_values: &Vec[Str]) -> Result[Vec[UInt8], Str] {
  return _build_rq(TFTP_OPCODE_WRQ, filename, mode, option_names, option_values);
}

/// Build a DATA packet (opcode 3): `[u16 3][u16 block][payload]`. `block`
/// is clamped to 0..65535; `payload` may be empty (the legal final block
/// of an exact-multiple transfer) and must be at most TFTP_BLKSIZE_MAX
/// (65464) bytes, the RFC 2348 hard maximum -- Err("tftp: payload too
/// long") otherwise. Content bytes are copied verbatim (0x00 included).
/// Complexity: O(payload).
pub fn tftp_build_data(block: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = payload.len();
  if n > TFTP_BLKSIZE_MAX {
    return _err_bytes("tftp: payload too long");
  }
  var out = Vec[UInt8].new();
  _push_u16(&mut out, TFTP_OPCODE_DATA);
  _push_u16(&mut out, _clamp_u16(block));
  var i = 0;
  while i < n {
    out.push(payload[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Build an ACK packet (opcode 4): `[u16 4][u16 block]`, exactly 4 bytes.
/// `block` is clamped to 0..65535. Complexity: O(1).
pub fn tftp_build_ack(block: Int) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  _push_u16(&mut out, TFTP_OPCODE_ACK);
  _push_u16(&mut out, _clamp_u16(block));
  return _ok_bytes(out);
}

/// Build an ERROR packet (opcode 5): `[u16 5][u16 code][message 0x00]`.
/// `code` is clamped to 0..65535; `message` bytes are copied verbatim (no
/// charset check; see the RFC 1350 code table in `tftp_error_name`).
/// Complexity: O(message).
pub fn tftp_build_error(code: Int, message: Str) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  _push_u16(&mut out, TFTP_OPCODE_ERROR);
  _push_u16(&mut out, _clamp_u16(code));
  _push_cstr(&mut out, message);
  return _ok_bytes(out);
}

/// Build an option acknowledgement (opcode 6): `[u16 6]` followed by the
/// accepted option TLVs and nothing else. At least one TLV is required:
/// Err("tftp: empty OACK") for empty pools; the option catalog otherwise
/// (including "tftp: option pool mismatch").
/// Complexity: O(option bytes).
pub fn tftp_build_oack(option_names: &Vec[Str], option_values: &Vec[Str]) -> Result[Vec[UInt8], Str] {
  let oerr = _options_error(option_names, option_values);
  if oerr.len() > 0 {
    return _err_bytes(oerr);
  }
  if option_names.len() == 0 {
    return _err_bytes("tftp: empty OACK");
  }
  var out = Vec[UInt8].new();
  _push_u16(&mut out, TFTP_OPCODE_OACK);
  _push_options(&mut out, option_names, option_values);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

/// Re-emit a packet canonically from its parsed (or hand-built) form.
/// Dispatches on `opcode` (1..6) and applies the same rules as the
/// per-kind builders: mode and known option names are emitted lowercase,
/// unknown option names and all values verbatim, block numbers and error
/// codes clamped, and the DATA payload must fit TFTP_BLKSIZE_MAX. Any
/// other opcode is Err("tftp: unknown opcode"). Bytes that were canonical
/// on the wire survive parse->emit byte-for-byte; non-canonical casing or
/// unknown filler does not.
/// Complexity: O(packet bytes).
pub fn tftp_emit(p: &TftpPacket) -> Result[Vec[UInt8], Str] {
  let op: Int = p.opcode;
  let fnm: Str = p.filename;
  let md: Str = p.mode;
  let names: Vec[Str] = p.option_names;
  let vals: Vec[Str] = p.option_values;
  if op == TFTP_OPCODE_RRQ || op == TFTP_OPCODE_WRQ {
    return _build_rq(op, fnm, md, &names, &vals);
  }
  if op == TFTP_OPCODE_DATA {
    let pl: Vec[UInt8] = p.payload;
    return tftp_build_data(p.block, &pl);
  }
  if op == TFTP_OPCODE_ACK {
    return tftp_build_ack(p.block);
  }
  if op == TFTP_OPCODE_ERROR {
    let msg: Str = p.error_message;
    return tftp_build_error(p.error_code, msg);
  }
  if op == TFTP_OPCODE_OACK {
    return tftp_build_oack(&names, &vals);
  }
  return _err_bytes("tftp: unknown opcode");
}

// --------------------------------------------------
//  Decoders
// --------------------------------------------------

/// Opcode of `data`: 1 (RRQ), 2 (WRQ), 3 (DATA), 4 (ACK), 5 (ERROR) or
/// 6 (OACK). Err("tftp: short packet") when fewer than 2 bytes are
/// present; Err("tftp: unknown opcode") when the big-endian value is
/// outside 1..6. Complexity: O(1).
pub fn tftp_op(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() < 2 {
    return _err_int("tftp: short packet");
  }
  let op = _u16(data, 0);
  if op < TFTP_OPCODE_RRQ || op > TFTP_OPCODE_OACK {
    return _err_int("tftp: unknown opcode");
  }
  return _ok_int(op);
}

// Walk the option TLV area [start, data.len()) and append canonical names
// and verbatim values to the parallel pools. Returns "" on success or the
// stable error text: "tftp: missing NUL" for an unterminated name or
// value, then the per-option catalog. The pools are caller-owned so
// nothing is returned inside a tuple (v0.61.3 layout discipline).
fn _parse_options(data: &Vec[UInt8], start: Int, names: &mut Vec[Str], values: &mut Vec[Str]) -> Str {
  let total = data.len();
  var pos = start;
  while pos < total {
    let name_nul = _nul_at(data, pos, total);
    if name_nul < 0 {
      return "tftp: missing NUL";
    }
    let value_nul = _nul_at(data, name_nul + 1, total);
    if value_nul < 0 {
      return "tftp: missing NUL";
    }
    let nm: Str = _str_between(data, pos, name_nul);
    let vl: Str = _str_between(data, name_nul + 1, value_nul);
    let e = _option_error(nm, vl);
    if e.len() > 0 {
      return e;
    }
    names.push(_option_canonical(nm));
    values.push(vl);
    pos = value_nul + 1;
  }
  return "";
}

// Shared RRQ/WRQ parser. Precedence: length, opcode kind, filename NUL,
// filename content, mode NUL, mode content, option TLVs. Trailing bytes
// can only be an unterminated option field, which reports "missing NUL".
fn _parse_rq(data: &Vec[UInt8], want_op: Int) -> Result[TftpPacket, Str] {
  let total = data.len();
  if total < 2 {
    return _err_packet("tftp: short packet");
  }
  let op = _u16(data, 0);
  if op != want_op {
    if want_op == TFTP_OPCODE_RRQ {
      return _err_packet("tftp: not an RRQ");
    }
    return _err_packet("tftp: not a WRQ");
  }
  let fn_nul = _nul_at(data, 2, total);
  if fn_nul < 0 {
    return _err_packet("tftp: missing NUL");
  }
  let filename: Str = _str_between(data, 2, fn_nul);
  if filename.len() == 0 {
    return _err_packet("tftp: bad filename");
  }
  if !_is_printable(filename) {
    return _err_packet("tftp: bad filename");
  }
  let mode_nul = _nul_at(data, fn_nul + 1, total);
  if mode_nul < 0 {
    return _err_packet("tftp: missing NUL");
  }
  let mode: Str = _mode_canonical(_str_between(data, fn_nul + 1, mode_nul));
  if mode.len() == 0 {
    return _err_packet("tftp: bad mode");
  }
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  let oerr = _parse_options(data, mode_nul + 1, &mut names, &mut values);
  if oerr.len() > 0 {
    return _err_packet(oerr);
  }
  let empty = Vec[UInt8].new();
  let p: TftpPacket = TftpPacket{
    opcode: want_op;
    filename: filename;
    mode: mode;
    block: 0;
    error_code: 0;
    error_message: "";
    payload: empty;
    option_names: names;
    option_values: values;
  };
  return _ok_packet(p);
}

/// Parse an RRQ (opcode 1) with its trailing option TLVs. The filename
/// must be non-empty printable ASCII and the mode must be a
/// case-insensitively valid netascii/octet/mail, stored canonically
/// lowercase. The whole buffer must be consumed: filename NUL, mode NUL,
/// then complete name/value pairs.
/// Errors: "tftp: short packet", "tftp: not an RRQ" (any other opcode,
/// including unknown values), "tftp: missing NUL", "tftp: bad filename",
/// "tftp: bad mode", then the option catalog.
/// Complexity: O(packet bytes).
pub fn tftp_parse_rrq(data: &Vec[UInt8]) -> Result[TftpPacket, Str] {
  return _parse_rq(data, TFTP_OPCODE_RRQ);
}

/// Parse a WRQ (opcode 2) with its trailing option TLVs. Identical rules
/// to `tftp_parse_rrq`, with "tftp: not a WRQ" for a non-WRQ opcode.
/// Complexity: O(packet bytes).
pub fn tftp_parse_wrq(data: &Vec[UInt8]) -> Result[TftpPacket, Str] {
  return _parse_rq(data, TFTP_OPCODE_WRQ);
}

/// Parse a DATA packet (opcode 3): `block` plus every byte after the
/// 4-byte header as `payload`, copied verbatim (0x00 bytes included). A
/// payload of 0..TFTP_BLKSIZE_MAX bytes is accepted; the classic 512-byte
/// default and any negotiated blksize are session concerns (see
/// `tftp_is_last_block`). Blocks may repeat: a re-sent DATA is accepted
/// like any other, because duplicate/retransmission policy is not part of
/// the codec.
/// Errors: "tftp: short packet" (< 4 bytes), "tftp: not a DATA packet"
/// (other opcode), "tftp: payload too long" (> 65464 bytes).
/// Complexity: O(payload).
pub fn tftp_parse_data(data: &Vec[UInt8]) -> Result[TftpPacket, Str] {
  let total = data.len();
  if total < 2 {
    return _err_packet("tftp: short packet");
  }
  let op = _u16(data, 0);
  if op != TFTP_OPCODE_DATA {
    return _err_packet("tftp: not a DATA packet");
  }
  if total < 4 {
    return _err_packet("tftp: short packet");
  }
  if total - 4 > TFTP_BLKSIZE_MAX {
    return _err_packet("tftp: payload too long");
  }
  let pl: Vec[UInt8] = _copy_range(data, 4, total);
  let names = Vec[Str].new();
  let values = Vec[Str].new();
  let p: TftpPacket = TftpPacket{
    opcode: TFTP_OPCODE_DATA;
    filename: "";
    mode: "";
    block: _u16(data, 2);
    error_code: 0;
    error_message: "";
    payload: pl;
    option_names: names;
    option_values: values;
  };
  return _ok_packet(p);
}

/// Parse an ACK packet (opcode 4). An ACK is exactly 4 bytes: the exact
/// size is enforced, so bytes after the block number are not ignored.
/// Errors: "tftp: short packet" (< 4 bytes), "tftp: not an ACK" (other
/// opcode), "tftp: trailing bytes" (> 4 bytes).
/// Complexity: O(1).
pub fn tftp_parse_ack(data: &Vec[UInt8]) -> Result[TftpPacket, Str] {
  let total = data.len();
  if total < 2 {
    return _err_packet("tftp: short packet");
  }
  let op = _u16(data, 0);
  if op != TFTP_OPCODE_ACK {
    return _err_packet("tftp: not an ACK");
  }
  if total > 4 {
    return _err_packet("tftp: trailing bytes");
  }
  if total < 4 {
    return _err_packet("tftp: short packet");
  }
  let names = Vec[Str].new();
  let values = Vec[Str].new();
  let empty = Vec[UInt8].new();
  let p: TftpPacket = TftpPacket{
    opcode: TFTP_OPCODE_ACK;
    filename: "";
    mode: "";
    block: _u16(data, 2);
    error_code: 0;
    error_message: "";
    payload: empty;
    option_names: names;
    option_values: values;
  };
  return _ok_packet(p);
}

/// Parse an ERROR packet (opcode 5): the 16-bit code plus the
/// NUL-terminated message, which is copied verbatim (any bytes except the
/// terminating 0x00; no charset check). The code is not range-limited
/// here -- `tftp_error_name` maps 0..7 to the RFC 1350 table and anything
/// else to "unknown".
/// Errors: "tftp: short packet" (< 5 bytes), "tftp: not an ERROR packet"
/// (other opcode), "tftp: missing NUL", "tftp: trailing bytes" (bytes
/// after the terminator).
/// Complexity: O(message).
pub fn tftp_parse_error(data: &Vec[UInt8]) -> Result[TftpPacket, Str] {
  let total = data.len();
  if total < 2 {
    return _err_packet("tftp: short packet");
  }
  let op = _u16(data, 0);
  if op != TFTP_OPCODE_ERROR {
    return _err_packet("tftp: not an ERROR packet");
  }
  if total < 5 {
    return _err_packet("tftp: short packet");
  }
  let msg_nul = _nul_at(data, 4, total);
  if msg_nul < 0 {
    return _err_packet("tftp: missing NUL");
  }
  if msg_nul + 1 != total {
    return _err_packet("tftp: trailing bytes");
  }
  let msg: Str = _str_between(data, 4, msg_nul);
  let names = Vec[Str].new();
  let values = Vec[Str].new();
  let empty = Vec[UInt8].new();
  let p: TftpPacket = TftpPacket{
    opcode: TFTP_OPCODE_ERROR;
    filename: "";
    mode: "";
    block: 0;
    error_code: _u16(data, 2);
    error_message: msg;
    payload: empty;
    option_names: names;
    option_values: values;
  };
  return _ok_packet(p);
}

/// Parse an OACK (opcode 6): option TLVs only, with no trailing bytes.
/// At least one complete TLV is required: Err("tftp: empty OACK") for a
/// bare 2-byte packet, "tftp: missing NUL" for a partial TLV, then the
/// option catalog. Known option names are stored canonically lowercase.
/// Complexity: O(option bytes).
pub fn tftp_parse_oack(data: &Vec[UInt8]) -> Result[TftpPacket, Str] {
  let total = data.len();
  if total < 2 {
    return _err_packet("tftp: short packet");
  }
  let op = _u16(data, 0);
  if op != TFTP_OPCODE_OACK {
    return _err_packet("tftp: not an OACK");
  }
  if total == 2 {
    return _err_packet("tftp: empty OACK");
  }
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  let oerr = _parse_options(data, 2, &mut names, &mut values);
  if oerr.len() > 0 {
    return _err_packet(oerr);
  }
  let empty = Vec[UInt8].new();
  let p: TftpPacket = TftpPacket{
    opcode: TFTP_OPCODE_OACK;
    filename: "";
    mode: "";
    block: 0;
    error_code: 0;
    error_message: "";
    payload: empty;
    option_names: names;
    option_values: values;
  };
  return _ok_packet(p);
}

/// Parse any TFTP packet: the opcode decides the shape, then dispatch to
/// the matching per-kind parser. Err("tftp: short packet") for fewer than
/// 2 bytes and Err("tftp: unknown opcode") for an opcode outside 1..6 are
/// reported here; every other error comes from the per-kind parser, whose
/// "not an X" branches are then unreachable.
/// Complexity: O(packet bytes).
pub fn tftp_parse(data: &Vec[UInt8]) -> Result[TftpPacket, Str] {
  let op = tftp_op(data);
  if !op.is_ok {
    return _err_packet(op.error);
  }
  let o: Int = op.value;
  if o == TFTP_OPCODE_RRQ {
    return tftp_parse_rrq(data);
  }
  if o == TFTP_OPCODE_WRQ {
    return tftp_parse_wrq(data);
  }
  if o == TFTP_OPCODE_DATA {
    return tftp_parse_data(data);
  }
  if o == TFTP_OPCODE_ACK {
    return tftp_parse_ack(data);
  }
  if o == TFTP_OPCODE_ERROR {
    return tftp_parse_error(data);
  }
  return tftp_parse_oack(data);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Opcode of a parsed packet (always 1..6). Complexity: O(1).
pub fn tftp_opcode(p: &TftpPacket) -> Int {
  return p.opcode;
}

/// Short uppercase name of an opcode: "RRQ", "WRQ", "DATA", "ACK",
/// "ERROR", "OACK", or "UNKNOWN" for anything else. Complexity: O(1).
pub fn tftp_opcode_name(op: Int) -> Str {
  if op == TFTP_OPCODE_RRQ {
    return "RRQ";
  }
  if op == TFTP_OPCODE_WRQ {
    return "WRQ";
  }
  if op == TFTP_OPCODE_DATA {
    return "DATA";
  }
  if op == TFTP_OPCODE_ACK {
    return "ACK";
  }
  if op == TFTP_OPCODE_ERROR {
    return "ERROR";
  }
  if op == TFTP_OPCODE_OACK {
    return "OACK";
  }
  return "UNKNOWN";
}

/// Filename of an RRQ/WRQ, or "" for every other opcode.
/// Complexity: O(1).
pub fn tftp_filename(p: &TftpPacket) -> Str {
  return p.filename;
}

/// Canonical lowercase mode of an RRQ/WRQ, or "" for every other opcode.
/// Complexity: O(1).
pub fn tftp_mode(p: &TftpPacket) -> Str {
  return p.mode;
}

/// Block number of a DATA/ACK (the raw unsigned 16-bit value), or 0 for
/// every other opcode. Complexity: O(1).
pub fn tftp_block(p: &TftpPacket) -> Int {
  return p.block;
}

/// Raw unsigned 16-bit error code of an ERROR, or 0 for every other
/// opcode. Complexity: O(1).
pub fn tftp_error_code(p: &TftpPacket) -> Int {
  return p.error_code;
}

/// Short lowercase name of an RFC 1350 error code: 0 "not defined",
/// 1 "file not found", 2 "access violation", 3 "disk full",
/// 4 "illegal operation", 5 "unknown transfer id", 6 "file already
/// exists", 7 "no such user"; any other value gives "unknown" (the codec
/// accepts any unsigned 16-bit code). Complexity: O(1).
pub fn tftp_error_name(code: Int) -> Str {
  if code == 0 {
    return "not defined";
  }
  if code == 1 {
    return "file not found";
  }
  if code == 2 {
    return "access violation";
  }
  if code == 3 {
    return "disk full";
  }
  if code == 4 {
    return "illegal operation";
  }
  if code == 5 {
    return "unknown transfer id";
  }
  if code == 6 {
    return "file already exists";
  }
  if code == 7 {
    return "no such user";
  }
  return "unknown";
}

/// Verbatim message of an ERROR, or "" for every other opcode.
/// Complexity: O(1).
pub fn tftp_error_message(p: &TftpPacket) -> Str {
  return p.error_message;
}

/// Number of option TLVs in the packet's pools (RRQ/WRQ/OACK). Returns 0
/// when the two pools somehow differ in length, so the count is always a
/// safe index bound for the option accessors. Complexity: O(1).
pub fn tftp_option_count(p: &TftpPacket) -> Int {
  let n = p.option_names.len();
  if p.option_values.len() != n {
    return 0;
  }
  return n;
}

/// Name of option `i` (wire order), or "" when `i` is outside
/// 0..tftp_option_count(p)-1. Names of known options are canonical
/// lowercase; unknown names are carried verbatim. Complexity: O(1).
pub fn tftp_option_name(p: &TftpPacket, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= p.option_names.len() {
    return "";
  }
  let s: Str = p.option_names[i];
  return s;
}

/// Value of option `i` (wire order), or "" when `i` is outside
/// 0..tftp_option_count(p)-1. Values are always verbatim. Complexity: O(1).
pub fn tftp_option_value(p: &TftpPacket, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= p.option_values.len() {
    return "";
  }
  let s: Str = p.option_values[i];
  return s;
}

/// Number of payload bytes of a DATA packet, or 0 for every other opcode.
/// Complexity: O(1).
pub fn tftp_payload_len(p: &TftpPacket) -> Int {
  return p.payload.len();
}

/// Payload byte `i` as an Int 0..255, or -1 when `i` is outside the
/// payload span 0..tftp_payload_len(p)-1. Complexity: O(1).
pub fn tftp_payload_byte(p: &TftpPacket, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= p.payload.len() {
    return -1;
  }
  return (p.payload[i] as Int) & 0xFF;
}

/// Copy of the payload span as a fresh vector (empty for non-DATA or an
/// empty payload). Complexity: O(payload).
pub fn tftp_payload_copy(p: &TftpPacket) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < p.payload.len() {
    out.push(p.payload[i]);
    i = i + 1;
  }
  return out;
}

/// True when DATA packet `p` is the final block of a transfer at block
/// size `blksize`, i.e. its payload is shorter than one full block. The
/// effective block size is `blksize` when it is within 8..65464 and the
/// classic TFTP_DEFAULT_BLKSIZE (512) otherwise, so a plain
/// `tftp_is_last_block(p, 512)` follows RFC 1350 and a negotiated value
/// follows RFC 2348. Always false for non-DATA packets. Duplicate or
/// re-sent blocks are accepted without state, per the re-sent block
/// policy documented in SPEC.md. Complexity: O(1).
pub fn tftp_is_last_block(p: &TftpPacket, blksize: Int) -> Bool {
  if p.opcode != TFTP_OPCODE_DATA {
    return false;
  }
  var bs = blksize;
  if bs < TFTP_BLKSIZE_MIN || bs > TFTP_BLKSIZE_MAX {
    bs = TFTP_DEFAULT_BLKSIZE;
  }
  return p.payload.len() < bs;
}
