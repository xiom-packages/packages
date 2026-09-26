// XIOM -- xiom.ftp: FTP control-protocol codec (RFC 959)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no session state) parser and canonical
// emitter for the FTP control connection:
//   * commands: "VERB [argument]" CRLF, verbs case-insensitive on input and
//     canonicalized to uppercase, per-verb argument-shape validation
//     (PORT octets, TYPE/MODE/STRU codes, required/optional/no-argument
//     arities, OPTS option/value shape);
//   * replies: "NNN text" single-line and "NNN-..." multiline blocks
//     terminated by a "NNN " line whose code must equal the opening code.
//
// A parsed command is one flat Command value (name/argument/raw). A parsed
// reply is one flat Response value: the reply code, the verbatim raw text
// and two index-aligned pools (per-line reply code or -1, and the physical
// line content without CRLF). Vec[StructType] is unsupported in this
// compiler, so nothing here is a vector of structs. See SPEC.md for the
// grammar, the documented decisions, the error catalog and the test plan.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[fn];
//   * Ok/Err for the two struct payloads are constructed only in the tiny
//     leaf helpers _ok_cmd/_err_cmd/_ok_resp/_err_resp (constructing a
//     Result inside a larger function miscompiles);
//   * every byte read is widened with `(string.byte_at(s, i) as Int) & 0xFF`
//     before arithmetic or comparison;
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on a Str read from a Vec element lowers to a pointer comparison);
//     Vec[Str] and Vec[Int] element reads are bound to typed locals first;
//   * no bitwise operation is applied to a value that may have the sign bit
//     set; all packing is integer division/modulo on non-negative values.

module xiom.ftp

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// RFC 959 command-line cap: at most 512 bytes including the CRLF.
pub const FTP_MAX_COMMAND_BYTES: Int = 512;

// Reply cap enforced by this codec (large enough for real FEAT blocks).
pub const FTP_MAX_RESPONSE_BYTES: Int = 8192;

// --------------------------------------------------
//  Private byte constants and codes
// --------------------------------------------------

const _FTP_CR: UInt8 = 13u8;
const _FTP_LF: UInt8 = 10u8;
const _FTP_SP: UInt8 = 32u8;
const _FTP_DASH: UInt8 = 45u8;
const _FTP_COMMA: UInt8 = 44u8;

// Printable ASCII bounds and ASCII letter bounds (as Int, for comparisons
// against widened byte reads).
const _FTP_SP_I: Int = 32;
const _FTP_DEL_I: Int = 127;
const _FTP_COMMA_I: Int = 44;
const _FTP_ZERO: Int = 48;
const _FTP_NINE: Int = 57;
const _FTP_UPPER_A: Int = 65;
const _FTP_UPPER_Z: Int = 90;
const _FTP_LOWER_A: Int = 97;
const _FTP_LOWER_Z: Int = 122;

// Canonical code letters.
const _FTP_TYPE_A: Int = 65;
const _FTP_TYPE_E: Int = 69;
const _FTP_TYPE_I: Int = 73;
const _FTP_TYPE_L: Int = 76;
const _FTP_MODE_S: Int = 83;
const _FTP_MODE_B: Int = 66;
const _FTP_MODE_C: Int = 67;
const _FTP_STRU_F: Int = 70;
const _FTP_STRU_R: Int = 82;
const _FTP_STRU_P: Int = 80;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed FTP command line.
/// Invariants: `name` is one of the 31 uppercase verbs; `argument` is
/// canonical (see SPEC.md section 5) and empty exactly when the verb takes
/// no argument; `raw` is the verbatim input line with its CRLF.
pub type Command = {
  name: Str;
  argument: Str;
  raw: Str;
}

/// A parsed FTP reply.
/// Invariants: `lines.len() >= 1` and `lines.len() == codes.len()`;
/// `codes[0] == code` and the last entry of `codes` equals `code`; `-1`
/// marks a body line stored verbatim without an `NNN`/`NNN-` prefix;
/// `raw` is the verbatim reply text with all CRLFs.
pub type Response = {
  code: Int;
  raw: Str;
  codes: Vec[Int];
  lines: Vec[Str];
}

// --------------------------------------------------
//  Result leaf helpers (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Command, Str].
fn _ok_cmd(v: Command) -> Result[Command, Str] {
  return Ok(v);
}

// Err(m) for Result[Command, Str].
fn _err_cmd(m: Str) -> Result[Command, Str] {
  return Err(m);
}

// Ok(v) for Result[Response, Str].
fn _ok_resp(v: Response) -> Result[Response, Str] {
  return Ok(v);
}

// Err(m) for Result[Response, Str].
fn _err_resp(m: Str) -> Result[Response, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and string helpers
// --------------------------------------------------

// Byte at `i` widened to 0..255. Callers guarantee the bounds.
fn _sb(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for ASCII '0'..'9'.
fn _is_digit(c: Int) -> Bool {
  return c >= _FTP_ZERO && c <= _FTP_NINE;
}

// True for ASCII 'A'..'Z' and 'a'..'z'.
fn _is_alpha(c: Int) -> Bool {
  if c >= _FTP_UPPER_A && c <= _FTP_UPPER_Z {
    return true;
  }
  return c >= _FTP_LOWER_A && c <= _FTP_LOWER_Z;
}

// ASCII uppercase of `c` (non-letters unchanged).
fn _upper(c: Int) -> Int {
  if c >= _FTP_LOWER_A && c <= _FTP_LOWER_Z {
    return c - 32;
  }
  return c;
}

// True when `c` is not a control byte (0x00-0x1F or 0x7F).
fn _is_printable(c: Int) -> Bool {
  return c >= _FTP_SP_I && c != _FTP_DEL_I;
}

// Byte-wise Str equality through str_compare (BUG 17 discipline).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// One-byte Str for the byte value `c` (0..255).
fn _char_str(c: Int) -> Str {
  var b = Vec[UInt8].new();
  b.push(c as UInt8);
  return builder.sb_to_str(&b);
}

// Uppercase every ASCII letter of `s` (other bytes pass through).
fn _ascii_upper(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(_upper(_sb(s, i)) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// The bytes before the first space in s[0, end), or the whole run when
// there is no space. Used only for the bad-verb error message.
fn _first_word(s: Str, end: Int) -> Str {
  var i = 0;
  while i < end && _sb(s, i) != _FTP_SP_I {
    i = i + 1;
  }
  return string.str_slice(s, 0, i);
}

// Index of the CR of the first CRLF at or after `from`, or -1.
fn _line_end(s: Str, from: Int) -> Int {
  var i = from;
  while i + 1 < s.len() {
    if _sb(s, i) == 13 && _sb(s, i + 1) == 10 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// The 3-digit reply code at the start of `line`, or -1 when the first three
// bytes are not all digits.
fn _line_code(line: Str) -> Int {
  if line.len() < 3 {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < 3 {
    let c = _sb(line, i);
    if !_is_digit(c) {
      return -1;
    }
    v = v * 10 + (c - _FTP_ZERO);
    i = i + 1;
  }
  return v;
}

// The marker byte of a reply-shaped line: 32 for "NNN ", 45 for "NNN-",
// and -1 when the line is not reply-shaped (too short, non-digits, or a
// fourth byte that is neither space nor dash).
fn _reply_marker(line: Str) -> Int {
  if line.len() < 4 {
    return -1;
  }
  if _line_code(line) < 0 {
    return -1;
  }
  let m = _sb(line, 3);
  if m == _FTP_SP_I {
    return _FTP_SP_I;
  }
  if m == 45 {
    return 45;
  }
  return -1;
}

// "" when every byte of `line` is printable, else the control-byte error.
fn _line_control(line: Str) -> Str {
  var i = 0;
  while i < line.len() {
    if !_is_printable(_sb(line, i)) {
      return "ftp: control byte in response line";
    }
    i = i + 1;
  }
  return "";
}

// The text of a reply line after its code and space/dash marker ("" when
// the line is shorter than the marker).
fn _after_code(line: Str) -> Str {
  if line.len() <= 4 {
    return "";
  }
  return string.str_slice(line, 4, line.len());
}

// The 3-digit decimal spelling of `c` (0..999; clamped).
fn _code3(c: Int) -> Str {
  var v = c;
  if v < 0 {
    v = 0;
  }
  if v > 999 {
    v = 999;
  }
  var b = Vec[UInt8].new();
  b.push((48 + v / 100) as UInt8);
  b.push((48 + (v / 10) % 10) as UInt8);
  b.push((48 + v % 10) as UInt8);
  return builder.sb_to_str(&b);
}

// The canonical decimal spelling of a byte value 0..255 (no leading zeros).
fn _dec_byte(v: Int) -> Str {
  var b = Vec[UInt8].new();
  if v >= 100 {
    b.push((48 + v / 100) as UInt8);
  }
  if v >= 10 {
    b.push((48 + (v / 10) % 10) as UInt8);
  }
  b.push((48 + v % 10) as UInt8);
  return builder.sb_to_str(&b);
}

// --------------------------------------------------
//  Verb classification and argument shapes
// --------------------------------------------------

// Argument class of an uppercase verb:
//   0 = unknown, 1 = no argument, 2 = required non-empty argument,
//   3 = optional argument (LIST/NLST/STAT), 4 = required but may be empty
//   (PASS).
fn _verb_kind(name: Str) -> Int {
  if _streq(name, "USER") { return 2; }
  if _streq(name, "PASS") { return 4; }
  if _streq(name, "ACCT") { return 2; }
  if _streq(name, "CWD") { return 2; }
  if _streq(name, "CDUP") { return 1; }
  if _streq(name, "PWD") { return 1; }
  if _streq(name, "QUIT") { return 1; }
  if _streq(name, "PORT") { return 2; }
  if _streq(name, "PASV") { return 1; }
  if _streq(name, "TYPE") { return 2; }
  if _streq(name, "MODE") { return 2; }
  if _streq(name, "STRU") { return 2; }
  if _streq(name, "RETR") { return 2; }
  if _streq(name, "STOR") { return 2; }
  if _streq(name, "STOU") { return 2; }
  if _streq(name, "APPE") { return 2; }
  if _streq(name, "LIST") { return 3; }
  if _streq(name, "NLST") { return 3; }
  if _streq(name, "DELE") { return 2; }
  if _streq(name, "RMD") { return 2; }
  if _streq(name, "MKD") { return 2; }
  if _streq(name, "RNFR") { return 2; }
  if _streq(name, "RNTO") { return 2; }
  if _streq(name, "ABOR") { return 1; }
  if _streq(name, "SYST") { return 1; }
  if _streq(name, "STAT") { return 3; }
  if _streq(name, "FEAT") { return 1; }
  if _streq(name, "OPTS") { return 2; }
  if _streq(name, "SIZE") { return 2; }
  if _streq(name, "MDTM") { return 2; }
  return 0;
}

// Parse the six PORT octets of `arg` into `out` (which must be empty on
// entry); true only for exactly six 1..3 digit fields with values 0..255.
fn _port_values(arg: Str, out: &mut Vec[Int]) -> Bool {
  let n = arg.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  var fields = 0;
  while i <= n {
    var v = 0;
    var k = 0;
    while i < n && _sb(arg, i) != _FTP_COMMA_I {
      let c = _sb(arg, i);
      if !_is_digit(c) {
        return false;
      }
      if k >= 3 {
        return false;
      }
      v = v * 10 + (c - _FTP_ZERO);
      k = k + 1;
      i = i + 1;
    }
    if k == 0 {
      return false;
    }
    if v > 255 {
      return false;
    }
    out.push(v);
    fields = fields + 1;
    if i == n {
      break;
    }
    i = i + 1;
    if i == n {
      return false;
    }
  }
  return fields == 6;
}

// Canonical PORT argument "h1,h2,h3,h4,p1,p2", or "" when malformed.
fn _canon_port(arg: Str) -> Str {
  var vals = Vec[Int].new();
  if !_port_values(arg, &mut vals) {
    return "";
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vals.len() {
    let v: Int = vals[i];
    if i > 0 {
      out.push(_FTP_COMMA);
    }
    builder.sb_push_str(&mut out, _dec_byte(v));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Canonical TYPE argument: "A"|"A N"|"A T"|"A C"|"E"|"E N"|"E T"|"E C"|
// "I"|"L <1-6 digits, no leading zero, >= 1>"; "" when malformed.
fn _canon_type(arg: Str) -> Str {
  let n = arg.len();
  if n == 0 {
    return "";
  }
  let c0 = _upper(_sb(arg, 0));
  if c0 == _FTP_TYPE_L {
    if n < 3 || _sb(arg, 1) != _FTP_SP_I {
      return "";
    }
    let ds = string.str_slice(arg, 2, n);
    let dn = ds.len();
    if dn < 1 || dn > 6 || _sb(ds, 0) == _FTP_ZERO {
      return "";
    }
    var i = 0;
    while i < dn {
      if !_is_digit(_sb(ds, i)) {
        return "";
      }
      i = i + 1;
    }
    return "L " + ds;
  }
  if n == 1 {
    if c0 == _FTP_TYPE_A || c0 == _FTP_TYPE_E || c0 == _FTP_TYPE_I {
      return _char_str(c0);
    }
    return "";
  }
  if n == 3 && _sb(arg, 1) == _FTP_SP_I {
    let c2 = _upper(_sb(arg, 2));
    if (c0 == _FTP_TYPE_A || c0 == _FTP_TYPE_E) && (c2 == 78 || c2 == 84 || c2 == 67) {
      return _char_str(c0) + " " + _char_str(c2);
    }
    return "";
  }
  return "";
}

// Canonical MODE argument "S"|"B"|"C", or "".
fn _canon_mode(arg: Str) -> Str {
  if arg.len() != 1 {
    return "";
  }
  let c = _upper(_sb(arg, 0));
  if c == _FTP_MODE_S || c == _FTP_MODE_B || c == _FTP_MODE_C {
    return _char_str(c);
  }
  return "";
}

// Canonical STRU argument "F"|"R"|"P", or "".
fn _canon_stru(arg: Str) -> Str {
  if arg.len() != 1 {
    return "";
  }
  let c = _upper(_sb(arg, 0));
  if c == _FTP_STRU_F || c == _FTP_STRU_R || c == _FTP_STRU_P {
    return _char_str(c);
  }
  return "";
}

// True for a valid OPTS argument: a non-empty alphanumeric option token,
// optionally followed by exactly one space and a non-empty value.
fn _opts_ok(arg: Str) -> Bool {
  let n = arg.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = _sb(arg, i);
    if !_is_alpha(c) && !_is_digit(c) {
      break;
    }
    i = i + 1;
  }
  if i == 0 {
    return false;
  }
  if i == n {
    return true;
  }
  if _sb(arg, i) != _FTP_SP_I {
    return false;
  }
  return i + 1 < n;
}

// --------------------------------------------------
//  Command parser
// --------------------------------------------------

/// Parse one FTP command line.
/// Params: text - one command line, CRLF terminated, at most 512 bytes.
/// Grammar: `verb [ SP argument ] CRLF`; the verb is 3-4 ASCII letters
/// (case-insensitive), the argument is printable text (space allowed).
/// Returns: Ok(Command) with the verb uppercased and the argument
/// canonicalized per SPEC.md section 5 (PORT octets, TYPE/MODE/STRU codes,
/// OPTS shape) and the verb arity enforced (section 4).
/// Errors: "ftp: command too long", "ftp: missing CRLF", "ftp: empty
/// command", "ftp: control byte in command", "ftp: bad verb: <word>",
/// "ftp: unknown verb: <NAME>" and "ftp: bad argument shape: <NAME>".
/// Complexity: O(len(text)).
pub fn ftp_parse_command(text: Str) -> Result[Command, Str] {
  let n = text.len();
  if n > FTP_MAX_COMMAND_BYTES {
    return _err_cmd("ftp: command too long");
  }
  if n < 2 {
    return _err_cmd("ftp: missing CRLF");
  }
  if _sb(text, n - 2) != 13 || _sb(text, n - 1) != 10 {
    return _err_cmd("ftp: missing CRLF");
  }
  let end = n - 2;
  if end == 0 {
    return _err_cmd("ftp: empty command");
  }
  var i = 0;
  while i < end {
    if !_is_printable(_sb(text, i)) {
      return _err_cmd("ftp: control byte in command");
    }
    i = i + 1;
  }
  var vlen = 0;
  while vlen < end && _is_alpha(_sb(text, vlen)) {
    vlen = vlen + 1;
  }
  if vlen == 0 {
    return _err_cmd("ftp: bad verb: " + _first_word(text, end));
  }
  let name: Str = _ascii_upper(string.str_slice(text, 0, vlen));
  let kind = _verb_kind(name);
  if kind == 0 {
    return _err_cmd("ftp: unknown verb: " + name);
  }
  var has_arg = false;
  var arg = "";
  if vlen < end {
    if _sb(text, vlen) != _FTP_SP_I {
      return _err_cmd("ftp: bad argument shape: " + name);
    }
    has_arg = true;
    arg = string.str_slice(text, vlen + 1, end);
  }
  if kind == 1 {
    if has_arg {
      return _err_cmd("ftp: bad argument shape: " + name);
    }
  } elif kind == 3 {
    if has_arg && arg.len() == 0 {
      return _err_cmd("ftp: bad argument shape: " + name);
    }
  } elif kind == 4 {
    if !has_arg {
      return _err_cmd("ftp: bad argument shape: " + name);
    }
  } else {
    if !has_arg || arg.len() == 0 {
      return _err_cmd("ftp: bad argument shape: " + name);
    }
  }
  if _streq(name, "PORT") {
    let cp = _canon_port(arg);
    if cp.len() == 0 {
      return _err_cmd("ftp: bad argument shape: PORT");
    }
    arg = cp;
  } elif _streq(name, "TYPE") {
    let ct = _canon_type(arg);
    if ct.len() == 0 {
      return _err_cmd("ftp: bad argument shape: TYPE");
    }
    arg = ct;
  } elif _streq(name, "MODE") {
    let cm = _canon_mode(arg);
    if cm.len() == 0 {
      return _err_cmd("ftp: bad argument shape: MODE");
    }
    arg = cm;
  } elif _streq(name, "STRU") {
    let cs = _canon_stru(arg);
    if cs.len() == 0 {
      return _err_cmd("ftp: bad argument shape: STRU");
    }
    arg = cs;
  } elif _streq(name, "OPTS") {
    if !_opts_ok(arg) {
      return _err_cmd("ftp: bad argument shape: OPTS");
    }
  }
  let cmd: Command = Command{ name: name; argument: arg; raw: text; };
  return _ok_cmd(cmd);
}

// --------------------------------------------------
//  Reply parser
// --------------------------------------------------

// Shared tail of the reply parser: consume the multiline reply body that
// starts at `pos` (a line boundary) with opening code `c0`, appending one
// entry per physical line to the parallel pools. "" on success (the
// matching "NNN " terminator was consumed and no trailing bytes remain);
// otherwise the stable error text.
fn _parse_reply_body(text: Str, pos: Int, c0: Int, codes: &mut Vec[Int], lines: &mut Vec[Str]) -> Str {
  let n = text.len();
  var p = pos;
  while p < n {
    let e = _line_end(text, p);
    if e < 0 {
      return "ftp: missing CRLF";
    }
    let line = string.str_slice(text, p, e);
    let ctl = _line_control(line);
    if ctl.len() > 0 {
      return ctl;
    }
    let m = _reply_marker(line);
    if m >= 0 {
      let lc = _line_code(line);
      if lc != c0 {
        return "ftp: multiline code mismatch: " + line;
      }
      codes.push(c0);
      lines.push(line);
      if m == _FTP_SP_I {
        if e + 2 != n {
          return "ftp: trailing data after response";
        }
        return "";
      }
    } else {
      codes.push(-1);
      lines.push(line);
    }
    p = e + 2;
  }
  return "ftp: unterminated multiline response";
}

/// Parse exactly one FTP reply (whole input consumed).
/// Params: text - one single-line or multiline reply, CRLF terminated,
/// at most 8192 bytes.
/// Grammar: `code SP text CRLF` or `code "-" text CRLF *( body-line CRLF )
/// code SP text CRLF`; `code` is three digits and the terminating code must
/// equal the opening code.
/// Returns: Ok(Response) whose `lines`/`codes` pools cover every physical
/// line without its CRLF; body lines that do not start with the opening
/// `NNN ` or `NNN-` are stored verbatim with code -1 (so real FEAT blocks
/// parse). `raw` is the verbatim input.
/// Errors: "ftp: response too long", "ftp: missing CRLF", "ftp: bad code
/// digits: <line>", "ftp: bad response class: <line>", "ftp: malformed
/// response line: <line>", "ftp: control byte in response line",
/// "ftp: multiline code mismatch: <line>", "ftp: unterminated multiline
/// response" and "ftp: trailing data after response".
/// Complexity: O(len(text)).
pub fn ftp_parse_response(text: Str) -> Result[Response, Str] {
  let n = text.len();
  if n > FTP_MAX_RESPONSE_BYTES {
    return _err_resp("ftp: response too long");
  }
  let e1 = _line_end(text, 0);
  if e1 < 0 {
    return _err_resp("ftp: missing CRLF");
  }
  let l0 = string.str_slice(text, 0, e1);
  let c0 = _line_code(l0);
  if c0 < 0 {
    return _err_resp("ftp: bad code digits: " + l0);
  }
  if c0 < 100 || c0 > 599 {
    return _err_resp("ftp: bad response class: " + l0);
  }
  let m0 = _reply_marker(l0);
  if m0 < 0 {
    return _err_resp("ftp: malformed response line: " + l0);
  }
  let ctl0 = _line_control(l0);
  if ctl0.len() > 0 {
    return _err_resp(ctl0);
  }
  var codes = Vec[Int].new();
  var lines = Vec[Str].new();
  codes.push(c0);
  lines.push(l0);
  if m0 == _FTP_SP_I {
    if e1 + 2 != n {
      return _err_resp("ftp: trailing data after response");
    }
    let r: Response = Response{ code: c0; raw: text; codes: codes; lines: lines; };
    return _ok_resp(r);
  }
  let berr = _parse_reply_body(text, e1 + 2, c0, &mut codes, &mut lines);
  if berr.len() > 0 {
    return _err_resp(berr);
  }
  let r2: Response = Response{ code: c0; raw: text; codes: codes; lines: lines; };
  return _ok_resp(r2);
}

// --------------------------------------------------
//  Emitters
// --------------------------------------------------

/// Canonical command text: `name + " " + argument + CRLF` (the space is
/// omitted when the argument is empty); an empty `name` emits "".
/// Complexity: O(len(name) + len(argument)).
pub fn ftp_emit_command(c: &Command) -> Str {
  let name: Str = c.name;
  let arg: Str = c.argument;
  if name.len() == 0 {
    return "";
  }
  if arg.len() == 0 {
    return name + "\r\n";
  }
  return name + " " + arg + "\r\n";
}

/// Canonical reply text from `lines`/`codes`: a coded line is re-emitted as
/// `NNN-<text>` (first/intermediate) or `NNN <text>` (last) and an uncoded
/// line (`-1`) verbatim, each followed by CRLF. A length drift between the
/// pools is tolerated by emitting the line verbatim. `emit(parse(x)) == x`
/// for canonical replies.
/// Complexity: O(total line bytes).
pub fn ftp_emit_response(r: &Response) -> Str {
  let n = r.lines.len();
  if n == 0 {
    return "";
  }
  let last = n - 1;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let line: Str = r.lines[i];
    var coded = false;
    if i < r.codes.len() {
      let lc: Int = r.codes[i];
      if lc >= 0 {
        coded = true;
        builder.sb_push_str(&mut out, _code3(lc));
        if i == last {
          out.push(_FTP_SP);
        } else {
          out.push(_FTP_DASH);
        }
        builder.sb_push_str(&mut out, _after_code(line));
      }
    }
    if !coded {
      builder.sb_push_str(&mut out, line);
    }
    out.push(_FTP_CR);
    out.push(_FTP_LF);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Uppercase verb of a parsed command. Complexity: O(1).
pub fn ftp_command_name(c: &Command) -> Str {
  return c.name;
}

/// Canonical argument text of a parsed command ("" when the verb takes
/// none). Complexity: O(1).
pub fn ftp_command_argument(c: &Command) -> Str {
  return c.argument;
}

/// Verbatim input line of a parsed command, CRLF included. Complexity: O(1).
pub fn ftp_command_raw(c: &Command) -> Str {
  return c.raw;
}

/// The six PORT octets h1..p2 as a fresh Vec[Int]; an empty vector for a
/// non-PORT command or a malformed argument (a parsed PORT is always valid).
/// Complexity: O(len(argument)).
pub fn ftp_port_octets(c: &Command) -> Vec[Int] {
  var out = Vec[Int].new();
  if !_streq(c.name, "PORT") {
    return out;
  }
  if !_port_values(c.argument, &mut out) {
    return Vec[Int].new();
  }
  return out;
}

/// TYPE code letter ("A", "E", "I" or "L"), or "" when the command is not a
/// canonical TYPE. Complexity: O(len(argument)).
pub fn ftp_type_code(c: &Command) -> Str {
  if !_streq(c.name, "TYPE") {
    return "";
  }
  let ct = _canon_type(c.argument);
  if ct.len() == 0 {
    return "";
  }
  let code = _upper(_sb(ct, 0));
  return _char_str(code);
}

/// MODE code letter ("S", "B" or "C"), or "" when the command is not a
/// canonical MODE. Complexity: O(1).
pub fn ftp_mode_code(c: &Command) -> Str {
  if !_streq(c.name, "MODE") {
    return "";
  }
  let cm = _canon_mode(c.argument);
  if cm.len() == 0 {
    return "";
  }
  return cm;
}

/// STRU code letter ("F", "R" or "P"), or "" when the command is not a
/// canonical STRU. Complexity: O(1).
pub fn ftp_stru_code(c: &Command) -> Str {
  if !_streq(c.name, "STRU") {
    return "";
  }
  let cs = _canon_stru(c.argument);
  if cs.len() == 0 {
    return "";
  }
  return cs;
}

/// Reply code of a parsed reply (100..599, equal on every reply-prefixed
/// line). Complexity: O(1).
pub fn ftp_response_code(r: &Response) -> Int {
  return r.code;
}

/// Reply class: code / 100, so exactly 1..5 for a parsed reply.
/// Complexity: O(1).
pub fn ftp_response_class(r: &Response) -> Int {
  return r.code / 100;
}

/// True when the reply has more than one physical line.
/// Complexity: O(1).
pub fn ftp_response_is_multiline(r: &Response) -> Bool {
  return r.lines.len() > 1;
}

/// Number of physical reply lines (always >= 1 for a parsed reply).
/// Complexity: O(1).
pub fn ftp_response_line_count(r: &Response) -> Int {
  return r.lines.len();
}

/// Physical line `i` without its CRLF, or "" when `i` is out of range.
/// Complexity: O(1).
pub fn ftp_response_line(r: &Response, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= r.lines.len() {
    return "";
  }
  let s: Str = r.lines[i];
  return s;
}

/// Code of physical line `i`: the reply code for an `NNN `/`NNN-` line,
/// -1 for an uncoded body line, and -1 when `i` is out of range.
/// Complexity: O(1).
pub fn ftp_response_line_code(r: &Response, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= r.lines.len() {
    return -1;
  }
  if i >= r.codes.len() {
    return -1;
  }
  let c: Int = r.codes[i];
  return c;
}

/// Text of the first reply line after its code and space/dash marker
/// ("" when there is no text). Complexity: O(1).
pub fn ftp_response_text(r: &Response) -> Str {
  if r.lines.len() == 0 {
    return "";
  }
  let l: Str = r.lines[0];
  return _after_code(l);
}

/// Verbatim reply text, all CRLFs included. Complexity: O(1).
pub fn ftp_response_raw(r: &Response) -> Str {
  return r.raw;
}
