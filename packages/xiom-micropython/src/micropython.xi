// XIOM -- xiom.micropython: host-side MicroPython raw-REPL protocol client.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// MicroPython's programmable REPL has three modes: friendly, raw and
// raw-paste. This package is the host side of the documented raw REPL
// (docs/reference/repl.rst at the upstream pin):
//   * the control bytes: Ctrl-A (enter raw), Ctrl-B (friendly exit),
//     Ctrl-C (interrupt) and Ctrl-D (end-of-input);
//   * exec framing: command bytes + 0x04, acknowledged by "OK", followed
//     by stdout, 0x04, stderr, 0x04 and the ">" prompt;
//   * the empty-command soft-reset form ("OK\r\n" and a forced exit);
//   * the eval helper (print(EXPR) / print(repr(EXPR)));
//   * line framing for stdout and stderr with traceback pass-through.
//
// The client is transport-agnostic on purpose: it builds the exact byte
// sequence a host must write and parses the exact byte sequence the device
// returns. A UART, USB-CDC, TCP or fixture transport only pumps Vec[UInt8]
// in and out; the package imports no socket, serial or FFI surface. Raw-paste
// mode (0x05 'A' 0x01) is deliberately outside the 0.1.0 subset; see SPEC.md
// for the declared surface and its 100% coverage table.
//
// Upstream reference (UPSTREAM-FIRST): micropython/micropython at
// b70ae1aca657bb93e2857dac4e2a2d21a3803200 (MIT). The protocol rules come
// from docs/reference/repl.rst, shared/runtime/pyexec.c and tools/pyboard.py;
// no upstream code is copied or vendored. See PROVENANCE.md.

module xiom.micropython

use xiom.string;
use xiom.string.builder;

// =========================================================================
// Protocol constants
// =========================================================================

/// Ctrl-A: enter the raw REPL.
pub const MP_CTRL_A: Int = 1;

/// Ctrl-B: leave the raw REPL and return to the friendly REPL.
pub const MP_CTRL_B: Int = 2;

/// Ctrl-C: interrupt the program currently executing on the device.
pub const MP_CTRL_C: Int = 3;

/// Ctrl-D: end of input; terminates every command written in raw mode.
pub const MP_CTRL_D: Int = 4;

/// The raw-REPL prompt byte (">").
pub const MP_PROMPT: Int = 62;

/// MpError kind: the device byte trace violates the declared framing.
pub const MP_ERR_FRAMING: Int = 0;

/// MpError kind: the command ran but the device reported an exception.
pub const MP_ERR_EXEC: Int = 1;

/// MpError kind: a request argument cannot be framed safely.
pub const MP_ERR_ARG: Int = 2;

// =========================================================================
// Types
// =========================================================================

/// A typed client failure. `kind` is one of the MP_ERR_* constants and
/// `message` is human-readable and starts with "mp: ".
pub type MpError = {
  kind: Int;
  message: Str;
}

/// The decoded result of one raw-REPL exec frame:
///   "OK" + output + 0x04 + error + 0x04 + ">"
/// `output` and `error` are byte-for-byte pass-throughs (no decoding,
/// trimming or exception classification). `consumed` is the number of trace
/// bytes up to and including the prompt, so a transport can keep any trailing
/// bytes for the next frame. `soft_reset` marks the empty-command form, whose
/// device reply is "OK\r\n" and a forced exit instead of the two-EOT frame.
pub type MpExec = {
  output: Str;
  error: Str;
  soft_reset: Bool;
  consumed: Int;
}

// =========================================================================
// Small helpers
// =========================================================================

fn _framing(message: Str) -> MpError {
  return MpError{ kind: MP_ERR_FRAMING; message: "mp: " + message };
}

fn _exec_err(message: Str) -> MpError {
  return MpError{ kind: MP_ERR_EXEC; message: "mp: " + message };
}

fn _arg_err(message: Str) -> MpError {
  return MpError{ kind: MP_ERR_ARG; message: "mp: " + message };
}

fn _byte_at(v: &Vec[UInt8], i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= v.len() {
    return -1;
  }
  return (v[i] as Int) & 0xFF;
}

fn _seq_at(v: &Vec[UInt8], at: Int, lit: Str) -> Bool {
  if at < 0 {
    return false;
  }
  if at + lit.len() > v.len() {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    let want = (string.byte_at(lit, i) as Int) & 0xFF;
    if _byte_at(v, at + i) != want {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _find_seq(v: &Vec[UInt8], from: Int, lit: Str) -> Int {
  if lit.len() == 0 {
    return from;
  }
  var i = from;
  while i + lit.len() <= v.len() {
    if _seq_at(v, i, lit) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn _find_byte(v: &Vec[UInt8], from: Int, b: Int) -> Int {
  var i = from;
  while i < v.len() {
    if _byte_at(v, i) == b {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn _bytes_str(v: &Vec[UInt8], from: Int, to: Int) -> Str {
  var sb = builder.sb_new();
  var i = from;
  while i < to {
    builder.sb_push_byte(&mut sb, v[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

fn _append_str(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn _str_has_byte(s: Str, b: Int) -> Bool {
  var i = 0;
  while i < s.len() {
    if ((string.byte_at(s, i) as Int) & 0xFF) == b {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn _trim_trailing_crlf(s: Str) -> Str {
  var end = s.len();
  while end > 0 {
    let b = (string.byte_at(s, end - 1) as Int) & 0xFF;
    if b == 10 || b == 13 {
      end = end - 1;
    } else {
      break;
    }
  }
  if end == s.len() {
    return s;
  }
  return string.str_slice(s, 0, end);
}

fn _single_byte(b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(b);
  return v;
}

// =========================================================================
// Request builders (host -> device)
// =========================================================================

/// The byte sequence that enters the raw REPL: Ctrl-A.
pub fn mp_repl_enter_request() -> Vec[UInt8] {
  return _single_byte(MP_CTRL_A);
}

/// The byte sequence that returns to the friendly REPL: Ctrl-B.
pub fn mp_repl_exit_request() -> Vec[UInt8] {
  return _single_byte(MP_CTRL_B);
}

/// The byte sequence that interrupts running device code: Ctrl-C.
pub fn mp_repl_interrupt_request() -> Vec[UInt8] {
  return _single_byte(MP_CTRL_C);
}

/// The byte sequence for the empty-command soft reset: Ctrl-D with no code.
pub fn mp_repl_soft_reset_request() -> Vec[UInt8] {
  return _single_byte(MP_CTRL_D);
}

/// Frame one raw-REPL command: the UTF-8 bytes of `code` followed by Ctrl-D.
/// An embedded Ctrl-D cannot be represented (the device would execute early),
/// so it is rejected as MP_ERR_ARG. The empty string is allowed and is the
/// upstream soft-reset form; mp_repl_soft_reset_request is the named helper.
pub fn mp_repl_exec_request(code: Str) -> Result[Vec[UInt8], MpError] {
  if _str_has_byte(code, MP_CTRL_D) {
    return Err(_arg_err("command contains EOT (0x04)"));
  }
  var v = Vec[UInt8].new();
  _append_str(&mut v, code);
  v.push(MP_CTRL_D);
  return Ok(v);
}

/// Frame an eval helper command: "print(EXPR)" followed by Ctrl-D. The device
/// prints the value and a newline; mp_eval_value strips the trailing newline.
pub fn mp_eval_request(expr: Str) -> Result[Vec[UInt8], MpError] {
  if expr.len() == 0 {
    return Err(_arg_err("empty eval expression"));
  }
  return mp_repl_exec_request("print(" + expr + ")");
}

/// Frame a repr eval helper command: "print(repr(EXPR))" followed by Ctrl-D.
pub fn mp_eval_repr_request(expr: Str) -> Result[Vec[UInt8], MpError] {
  if expr.len() == 0 {
    return Err(_arg_err("empty eval expression"));
  }
  return mp_repl_exec_request("print(repr(" + expr + "))");
}

// =========================================================================
// Response parsers (device -> host)
// =========================================================================

/// Parse the raw-REPL entry banner and prompt:
///   [\r\n] "raw REPL; CTRL-B to exit\r\n" ">"
/// The leading CRLF is present when entering from the friendly REPL and absent
/// when the device already is in raw mode. Returns the number of bytes up to
/// and including the prompt; trailing bytes are left to the caller.
pub fn mp_parse_enter(trace: &Vec[UInt8]) -> Result[Int, MpError] {
  let banner = "raw REPL; CTRL-B to exit\r\n";
  let at = _find_seq(trace, 0, banner);
  if at < 0 {
    return Err(_framing("raw REPL banner missing"));
  }
  let p = at + banner.len();
  if _byte_at(trace, p) != MP_PROMPT {
    return Err(_framing("raw REPL prompt missing"));
  }
  return Ok(p + 1);
}

/// Parse the friendly-REPL return banner and default prompt (">>> "). The
/// banner text is board-specific and therefore not interpreted; only the
/// default prompt marks the completed transition.
pub fn mp_parse_exit(trace: &Vec[UInt8]) -> Result[Int, MpError] {
  let prompt = ">>> ";
  let at = _find_seq(trace, 0, prompt);
  if at < 0 {
    return Err(_framing("friendly REPL prompt missing"));
  }
  return Ok(at + prompt.len());
}

/// Parse one complete raw-REPL exec frame:
///   "OK" OUTPUT 0x04 ERROR 0x04 ">"
/// The two payloads are returned verbatim; a traceback in ERROR is not
/// classified or truncated. The empty-command soft-reset reply ("OK\r\n" with
/// no EOT anywhere) yields soft_reset=true and consumes "OK\r\n" only.
pub fn mp_parse_exec(trace: &Vec[UInt8]) -> Result[MpExec, MpError] {
  if trace.len() < 2 {
    return Err(_framing("exec response shorter than OK"));
  }
  if !_seq_at(trace, 0, "OK") {
    return Err(_framing("exec response missing OK"));
  }

  // Soft reset: "OK\r\n" and a forced exit; no EOT/second payload follows.
  let crlf = _byte_at(trace, 2) == 13 && _byte_at(trace, 3) == 10;
  if crlf && _find_byte(trace, 0, MP_CTRL_D) < 0 {
    return Ok(MpExec{
      output: "";
      error: "";
      soft_reset: true;
      consumed: 4;
    });
  }

  let e1 = _find_byte(trace, 2, MP_CTRL_D);
  if e1 < 0 {
    return Err(_framing("stdout EOT (0x04) missing"));
  }
  let e2 = _find_byte(trace, e1 + 1, MP_CTRL_D);
  if e2 < 0 {
    return Err(_framing("stderr EOT (0x04) missing"));
  }
  if _byte_at(trace, e2 + 1) != MP_PROMPT {
    return Err(_framing("raw REPL prompt missing after exec"));
  }
  return Ok(MpExec{
    output: _bytes_str(trace, 2, e1);
    error: _bytes_str(trace, e1 + 1, e2);
    soft_reset: false;
    consumed: e2 + 2;
  });
}

// =========================================================================
// Result helpers and line framing
// =========================================================================

/// True when the command completed without a soft reset and without any
/// stderr payload (the upstream pyboard exec_ rule).
pub fn mp_exec_ok(r: MpExec) -> Bool {
  if r.soft_reset {
    return false;
  }
  return r.error.len() == 0;
}

/// Extract the single eval value: the decoded output with trailing CR/LF
/// removed. A soft reset, a non-empty error payload (traceback pass-through)
/// or empty output is a typed MP_ERR_EXEC.
pub fn mp_eval_value(r: MpExec) -> Result[Str, MpError] {
  if r.soft_reset {
    return Err(_exec_err("eval triggered a soft reset"));
  }
  if r.error.len() > 0 {
    return Err(_exec_err("eval raised: " + r.error));
  }
  let value = _trim_trailing_crlf(r.output);
  if value.len() == 0 {
    return Err(_exec_err("eval produced no output"));
  }
  return Ok(value);
}

/// Split a payload into lines: LF is the separator, one trailing CR per line
/// is removed, a final LF does not create an extra empty line, and interior
/// empty lines are preserved (traceback frames stay line-aligned).
pub fn mp_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  if text.len() == 0 {
    return out;
  }
  var start = 0;
  var i = 0;
  while i < text.len() {
    if ((string.byte_at(text, i) as Int) & 0xFF) == 10 {
      var end = i;
      if end > start && ((string.byte_at(text, end - 1) as Int) & 0xFF) == 13 {
        end = end - 1;
      }
      out.push(string.str_slice(text, start, end));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < text.len() {
    out.push(string.str_slice(text, start, text.len()));
  }
  return out;
}

/// The stdout payload of an exec frame, framed into lines.
pub fn mp_output_lines(r: MpExec) -> Vec[Str] {
  return mp_lines(r.output);
}

/// The stderr payload of an exec frame, framed into lines. Traceback text is
/// passed through unchanged apart from CRLF normalization.
pub fn mp_error_lines(r: MpExec) -> Vec[Str] {
  return mp_lines(r.error);
}
