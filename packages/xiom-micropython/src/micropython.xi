// XIOM -- xiom.micropython: host-side MicroPython raw-REPL protocol client.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (0.1.0): the documented standard raw-REPL wire protocol, host side,
// transport-agnostic. The package builds the exact control/exec frames a
// host writes to a MicroPython device and decodes the response stream:
//
//   * Ctrl-A (0x01) enters the raw REPL; the device answers
//     "\r\nraw REPL; CTRL-B to exit\r\n>" (the leading CRLF appears when
//     coming from the friendly REPL).
//   * An exec write is the UTF-8 code bytes followed by Ctrl-D (0x04).
//     The device acknowledges Ctrl-D with "OK", executes, then emits
//     stdout terminated by 0x04, stderr (tracebacks) terminated by 0x04,
//     and finally the raw prompt ">".
//   * Ctrl-C (0x03) interrupts a running program (the resulting
//     KeyboardInterrupt arrives in the stderr frame) or clears a partial
//     line when the REPL is idle.
//   * Ctrl-B (0x02) leaves the raw REPL for the friendly REPL.
//   * An empty exec (Ctrl-D with no bytes) is a soft reset: the device
//     answers "OK\r\n" and restarts; mp_soft_reset_frame() exposes it
//     explicitly and mp_exec_frame() rejects empty code so the two cannot
//     be confused.
//
// Traceback pass-through is deliberate: the stderr frame is preserved
// verbatim in MpExecResult.error and split into error_lines; nothing is
// parsed away. mp_traceback_exception() extracts the final exception line
// for callers that want it without losing the full traceback.
//
// Transport-agnostic: no socket, serial or FFI code lives here. A consumer
// writes mp_*_frame() bytes to its link and feeds received bytes to
// mp_decoder_feed(); mp_decode_trace()/mp_parse_exec_response() handle a
// complete response slice. An absent link is classified with
// mp_error_absent() (MP_ERR_ABSENT) so device-fleet suites can SKIP
// deterministically instead of failing.
//
// Upstream reference (reference-only, nothing vendored):
// micropython/micropython @ b70ae1aca657bb93e2857dac4e2a2d21a3803200
// (MIT), docs/reference/repl.rst and shared/runtime/pyexec.c; see
// SPEC.md and PROVENANCE.md.

module xiom.micropython

use xiom.string;
use xiom.encoding;

// =========================================================================
// Wire constants
// =========================================================================

/// Ctrl-A: enter the raw REPL.
pub const MP_CTRL_A: Int = 1;
/// Ctrl-B: leave the raw REPL for the friendly REPL.
pub const MP_CTRL_B: Int = 2;
/// Ctrl-C: interrupt the running program (or clear a partial line).
pub const MP_CTRL_C: Int = 3;
/// Ctrl-D: end of exec input / EOF frame terminator / soft reset.
pub const MP_CTRL_D: Int = 4;
/// Ctrl-E: paste-mode entry in the friendly REPL (reserved; not used here).
pub const MP_CTRL_E: Int = 5;

/// Raw-REPL banner (without the leading CRLF a friendly-REPL transition
/// adds). Oracle: pyexec.c raw_repl_reset.
pub const MP_RAW_BANNER: Str = "raw REPL; CTRL-B to exit\r\n";
/// Raw-REPL prompt emitted after the banner and after every response.
pub const MP_RAW_PROMPT: Str = ">";
/// Friendly-REPL prompt (the exit transition ends at this prompt).
pub const MP_FRIENDLY_PROMPT: Str = ">>> ";
/// Positive acknowledgement emitted when Ctrl-D ends an exec write.
pub const MP_OK: Str = "OK";

/// Upper bound on a prelude (banner + prompt) before the decoder declares
/// a framing error. A soft-reset boot log can be long; 4096 bytes is far
/// above any documented banner.
pub const MP_PRELUDE_MAX: Int = 4096;

// =========================================================================
// Decoder states
// =========================================================================

/// Waiting for the raw banner / prompt (or a bare "OK" response slice).
pub const MP_DEC_PRELUDE: Int = 0;
/// Accumulating the two-byte "OK" acknowledgement.
pub const MP_DEC_OK: Int = 1;
/// Collecting stdout until the first 0x04.
pub const MP_DEC_STDOUT: Int = 2;
/// Collecting stderr (tracebacks) until the second 0x04.
pub const MP_DEC_STDERR: Int = 3;
/// Both EOF frames seen; trailing prompt bytes are ignored.
pub const MP_DEC_DONE: Int = 4;
/// An unrecoverable framing error was reported; reset before reuse.
pub const MP_DEC_ERROR: Int = 5;

// =========================================================================
// Typed errors
// =========================================================================

/// No transport/link is present (or opening it failed): the device-fleet
/// SKIP classification. Never a FAIL.
pub const MP_ERR_ABSENT: Int = 0;
/// Transport I/O failed (link closed, write/read error).
pub const MP_ERR_IO: Int = 1;
/// No complete response within the caller's deadline.
pub const MP_ERR_TIMEOUT: Int = 2;
/// Malformed wire framing (missing OK, missing/short EOF frames, no
/// prelude prompt, oversized prelude).
pub const MP_ERR_PROTOCOL: Int = 3;
/// Argument rejected before any frame was produced.
pub const MP_ERR_INVALID_ARG: Int = 4;
/// The device executed but reported a traceback, or an eval produced no
/// value. The traceback itself is passed through in the message.
pub const MP_ERR_EXEC: Int = 5;

/// A typed protocol/client failure. `message` always starts with
/// "micropython: " and is safe to log.
pub type MpError = {
  kind: Int;
  message: Str;
}

/// Build a typed error. `detail` is appended verbatim.
pub fn mp_error(kind: Int, detail: Str) -> MpError {
  return MpError{ kind: kind; message: "micropython: " + detail };
}

/// Stable lower-case name for an error kind ("absent", "io", ...).
pub fn mp_error_name(kind: Int) -> Str {
  if kind == MP_ERR_ABSENT { return "absent"; }
  if kind == MP_ERR_IO { return "io"; }
  if kind == MP_ERR_TIMEOUT { return "timeout"; }
  if kind == MP_ERR_PROTOCOL { return "protocol"; }
  if kind == MP_ERR_INVALID_ARG { return "invalid-arg"; }
  if kind == MP_ERR_EXEC { return "exec"; }
  return "unknown";
}

/// True only for the absent-transport SKIP classification.
pub fn mp_error_is_skip(err: &MpError) -> Bool {
  return err.kind == MP_ERR_ABSENT;
}

/// The canonical absent-link error: suite hosts without the requested
/// transport classify this as SKIP and stay green.
pub fn mp_error_absent(transport: Str) -> MpError {
  return mp_error(MP_ERR_ABSENT, "transport absent: " + transport + " (SKIP)");
}

// =========================================================================
// Decoded exec result
// =========================================================================

/// One complete raw-REPL exec response.
///
/// `ok` is true iff the stderr frame was empty (MicroPython reports an
/// uncaught exception, including KeyboardInterrupt, only on stderr).
/// `output`/`error` preserve the device bytes as text; `output_lines` and
/// `error_lines` are the same text split at CRLF/LF/CR boundaries.
pub type MpExecResult = {
  ok: Bool;
  output: Str;
  error: Str;
  output_lines: Vec[Str];
  error_lines: Vec[Str];
}

/// Incremental raw-REPL response decoder.
///
/// Feed received chunks with mp_decoder_feed(). Reaching
/// MP_DEC_DONE means both EOF frames were seen; mp_decoder_result() then
/// returns the typed result. The decoder does not own a transport and
/// performs no I/O.
pub type MpDecoder = {
  state: Int;
  pre: Vec[UInt8];
  okbuf: Vec[UInt8];
  out: Vec[UInt8];
  err: Vec[UInt8];
  tail: Vec[UInt8];
}

// =========================================================================
// Frame builders (host -> device)
// =========================================================================

fn _one(byte: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(byte as UInt8);
  return v;
}

fn _copy(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

/// Ctrl-C frame: interrupt a running program. When the REPL is idle the
/// device silently clears the pending line (no response frame is due).
pub fn mp_interrupt_frame() -> Vec[UInt8] {
  return _one(MP_CTRL_C);
}

/// Ctrl-A frame: enter the raw REPL. The device replies with the banner
/// and ">" unless it was already in raw mode.
pub fn mp_enter_raw_frame() -> Vec[UInt8] {
  return _one(MP_CTRL_A);
}

/// CR + Ctrl-A frame: the pyboard.py-compatible enter sequence. The CR
/// terminates any partial friendly-REPL line before the mode switch.
pub fn mp_enter_raw_flush_frame() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(13 as UInt8);
  v.push(MP_CTRL_A as UInt8);
  return v;
}

/// Ctrl-B frame: leave the raw REPL for the friendly REPL. The device
/// answers with its banner and the ">>> " prompt.
pub fn mp_exit_raw_frame() -> Vec[UInt8] {
  return _one(MP_CTRL_B);
}

/// Ctrl-D-only frame: the documented soft-reset sequence (empty exec
/// input). The device answers "OK\r\n" and restarts; no stdout/stderr
/// EOF frames follow.
pub fn mp_soft_reset_frame() -> Vec[UInt8] {
  return _one(MP_CTRL_D);
}

fn _code_frame(code: Str) -> Vec[UInt8] {
  var b = encoding.utf8_encode(code);
  b.push(MP_CTRL_D as UInt8);
  return b;
}

/// UTF-8 code bytes followed by Ctrl-D. Empty code is rejected because
/// the device treats it as a soft reset (mp_soft_reset_frame()).
pub fn mp_exec_frame(code: Str) -> Result[Vec[UInt8], MpError] {
  if code.len() == 0 {
    return Err(mp_error(MP_ERR_INVALID_ARG, "exec: empty code is the soft-reset sequence; use mp_soft_reset_frame"));
  }
  return Ok(_code_frame(code));
}

/// `print(<expr>)` + newline + Ctrl-D, matching pyboard.py's eval helper.
pub fn mp_eval_frame(expr: Str) -> Result[Vec[UInt8], MpError] {
  if string.str_trim(expr).len() == 0 {
    return Err(mp_error(MP_ERR_INVALID_ARG, "eval: expression is empty"));
  }
  return mp_exec_frame("print(" + expr + ")\n");
}

/// `print(repr(<expr>))` + newline + Ctrl-D, matching pyboard.py's
/// parse-mode eval helper (the output is a Python literal).
pub fn mp_eval_repr_frame(expr: Str) -> Result[Vec[UInt8], MpError] {
  if string.str_trim(expr).len() == 0 {
    return Err(mp_error(MP_ERR_INVALID_ARG, "eval_repr: expression is empty"));
  }
  return mp_exec_frame("print(repr(" + expr + "))\n");
}

// =========================================================================
// Line framing and traceback pass-through
// =========================================================================

/// Split console text into lines at CRLF, LF or CR. A single trailing
/// newline does not produce a phantom empty last line; interior blank
/// lines are preserved. Empty input yields an empty vector.
pub fn mp_split_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  if text.len() == 0 { return out; }
  let crlf = string.replace(text, "\r\n", "\n");
  let norm = string.replace(crlf, "\r", "\n");
  let parts = string.str_split(norm, "\n");
  var n = parts.len();
  if string.str_ends_with(norm, "\n") { n = n - 1; }
  var i = 0;
  while i < n {
    out.push(parts[i]);
    i = i + 1;
  }
  return out;
}

/// True when the stderr text carries a MicroPython traceback header.
pub fn mp_traceback_is_present(error: Str) -> Bool {
  return string.str_contains(error, "Traceback (most recent call last):");
}

/// Final non-empty line of a traceback ("ValueError: bad"), trimmed.
/// Returns "" for empty stderr. The full traceback remains available in
/// MpExecResult.error -- this helper is a convenience, not a filter.
pub fn mp_traceback_exception(error: Str) -> Str {
  let lines = mp_split_lines(error);
  var i = lines.len();
  while i > 0 {
    i = i - 1;
    let line: Str = lines[i];
    let t = string.str_trim(line);
    if t.len() > 0 { return t; }
  }
  return "";
}

// =========================================================================
// Decoder
// =========================================================================

/// A fresh decoder in MP_DEC_PRELUDE state.
pub fn mp_decoder_new() -> MpDecoder {
  return MpDecoder{
    state: MP_DEC_PRELUDE;
    pre: Vec[UInt8].new();
    okbuf: Vec[UInt8].new();
    out: Vec[UInt8].new();
    err: Vec[UInt8].new();
    tail: Vec[UInt8].new();
  };
}

/// Reset a decoder for the next response. Buffers are cleared.
pub fn mp_decoder_reset(dec: &mut MpDecoder) {
  dec.state = MP_DEC_PRELUDE;
  dec.pre = Vec[UInt8].new();
  dec.okbuf = Vec[UInt8].new();
  dec.out = Vec[UInt8].new();
  dec.err = Vec[UInt8].new();
  dec.tail = Vec[UInt8].new();
}

fn _vec_equals_str(v: &Vec[UInt8], s: Str) -> Bool {
  if v.len() != s.len() { return false; }
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b != c { return false; }
    i = i + 1;
  }
  return true;
}

fn _is_bare_ok(v: &Vec[UInt8]) -> Bool {
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    if b != 13 && b != 10 { break; }
    i = i + 1;
  }
  if v.len() - i != 2 { return false; }
  let a: Int = (v[i] as Int) & 0xFF;
  let b2: Int = (v[i + 1] as Int) & 0xFF;
  return a == 79 && b2 == 75;
}

fn _fail_decoder(dec: &mut MpDecoder, detail: Str) -> Result[Unit, MpError] {
  dec.state = MP_DEC_ERROR;
  return Err(mp_error(MP_ERR_PROTOCOL, detail));
}

/// Feed one received chunk. A protocol violation is returned as a typed
/// MP_ERR_PROTOCOL error and moves the decoder to MP_DEC_ERROR.
pub fn mp_decoder_feed(dec: &mut MpDecoder, chunk: &Vec[UInt8]) -> Result[Unit, MpError] {
  var i = 0;
  while i < chunk.len() {
    let b: Int = (chunk[i] as Int) & 0xFF;

    if dec.state == MP_DEC_DONE {
      dec.tail.push(b as UInt8);
    } else if dec.state == MP_DEC_PRELUDE {
      dec.pre.push(b as UInt8);
      if b == 62 {
        dec.state = MP_DEC_OK;
      } else if _is_bare_ok(&dec.pre) {
        dec.pre = Vec[UInt8].new();
        dec.state = MP_DEC_STDOUT;
      } else if dec.pre.len() > MP_PRELUDE_MAX {
        return _fail_decoder(dec, "banner: no raw-REPL prompt within " + _int_to_str(MP_PRELUDE_MAX) + " bytes");
      }
    } else if dec.state == MP_DEC_OK {
      dec.okbuf.push(b as UInt8);
      if dec.okbuf.len() == 2 {
        if _vec_equals_str(&dec.okbuf, MP_OK) {
          dec.state = MP_DEC_STDOUT;
        } else {
          return _fail_decoder(dec, "response: expected OK acknowledgement");
        }
      }
    } else if dec.state == MP_DEC_STDOUT {
      if b == MP_CTRL_D {
        dec.state = MP_DEC_STDERR;
      } else {
        dec.out.push(b as UInt8);
      }
    } else if dec.state == MP_DEC_STDERR {
      if b == MP_CTRL_D {
        dec.state = MP_DEC_DONE;
      } else {
        dec.err.push(b as UInt8);
      }
    } else {
      return Err(mp_error(MP_ERR_PROTOCOL, "decoder: failed state; reset before reuse"));
    }

    i = i + 1;
  }
  return Ok(());
}

/// True once both EOF frames have been consumed.
pub fn mp_decoder_done(dec: &MpDecoder) -> Bool {
  return dec.state == MP_DEC_DONE;
}

/// Current decoder state (one of the MP_DEC_* constants).
pub fn mp_decoder_state(dec: &MpDecoder) -> Int {
  return dec.state;
}

/// The prelude bytes seen before the raw prompt, as text (typically
/// "\r\nraw REPL; CTRL-B to exit\r\n>"). Empty when the response slice
/// started directly at "OK". Useful for diagnostics.
pub fn mp_decoder_banner(dec: &MpDecoder) -> Str {
  return Str::from_utf8(_copy(dec.pre));
}

fn _result_from(dec: &MpDecoder) -> MpExecResult {
  let out_s = Str::from_utf8(_copy(dec.out));
  let err_s = Str::from_utf8(_copy(dec.err));
  var ok = false;
  if err_s.len() == 0 { ok = true; }
  return MpExecResult{
    ok: ok;
    output: out_s;
    error: err_s;
    output_lines: mp_split_lines(out_s);
    error_lines: mp_split_lines(err_s);
  };
}

/// Typed result of a completed response. An incomplete response is a
/// MP_ERR_PROTOCOL error ("missing EOF frames").
pub fn mp_decoder_result(dec: &MpDecoder) -> Result[MpExecResult, MpError] {
  if dec.state != MP_DEC_DONE {
    return Err(mp_error(MP_ERR_PROTOCOL, "response: incomplete (missing EOF frames)"));
  }
  return Ok(_result_from(dec));
}

/// Decode one complete response slice. The slice may start at the raw
/// banner/prompt or directly at "OK"; trailing friendly bytes after the
/// second EOF are ignored.
pub fn mp_decode_trace(trace: &Vec[UInt8]) -> Result[MpExecResult, MpError] {
  var d = mp_decoder_new();
  let fed = mp_decoder_feed(&mut d, trace);
  if !fed.is_ok { return Err(fed.error); }
  return mp_decoder_result(&d);
}

/// Alias with the wire-level name: parse an exec response.
pub fn mp_parse_exec_response(trace: &Vec[UInt8]) -> Result[MpExecResult, MpError] {
  return mp_decode_trace(trace);
}

/// True when the trace contains a complete response (OK + stdout 0x04 +
/// stderr 0x04). Malformed or partial input is false, never a panic.
pub fn mp_frame_is_complete(trace: &Vec[UInt8]) -> Bool {
  var d = mp_decoder_new();
  let fed = mp_decoder_feed(&mut d, trace);
  if !fed.is_ok { return false; }
  return mp_decoder_done(&d);
}

// =========================================================================
// Eval helpers
// =========================================================================

/// Extract the value printed by an eval frame: the last non-empty stdout
/// line, trimmed. A device traceback becomes MP_ERR_EXEC with the final
/// exception line appended (the full traceback stays in res.error).
pub fn mp_eval_extract(res: &MpExecResult) -> Result[Str, MpError] {
  if !res.ok {
    let exc = mp_traceback_exception(res.error);
    return Err(mp_error(MP_ERR_EXEC, "eval: device raised " + exc));
  }
  var i = res.output_lines.len();
  while i > 0 {
    i = i - 1;
    let line: Str = res.output_lines[i];
    let t = string.str_trim(line);
    if t.len() > 0 { return Ok(t); }
  }
  return Err(mp_error(MP_ERR_EXEC, "eval: expression produced no output"));
}

/// decode + extract: the one-call eval helper for an eval-frame trace.
pub fn mp_eval(trace: &Vec[UInt8]) -> Result[Str, MpError] {
  let r = mp_decode_trace(trace);
  if !r.is_ok { return Err(r.error); }
  return mp_eval_extract(&r.value);
}

// =========================================================================
// Local helpers (BINDINGS-COMPILER-FINDINGS discipline: module-local
// integer formatting avoids import cycles in error paths)
// =========================================================================

fn _int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var x = n;
  if x < 0 { neg = true; x = 0 - x; }
  var digits = "";
  while x > 0 {
    let d = x % 10;
    if d == 0 { digits = "0" + digits; }
    else if d == 1 { digits = "1" + digits; }
    else if d == 2 { digits = "2" + digits; }
    else if d == 3 { digits = "3" + digits; }
    else if d == 4 { digits = "4" + digits; }
    else if d == 5 { digits = "5" + digits; }
    else if d == 6 { digits = "6" + digits; }
    else if d == 7 { digits = "7" + digits; }
    else if d == 8 { digits = "8" + digits; }
    else { digits = "9" + digits; }
    x = x / 10;
  }
  if neg { return "-" + digits; }
  return digits;
}
