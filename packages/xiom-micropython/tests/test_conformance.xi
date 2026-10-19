// XIOM -- xiom.micropython conformance tests.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven byte-trace suite, no hardware. tests/fixtures/*.trace are
// direction-aware scripts (W = host -> device, R = device -> host) whose
// tokens are hex bytes or quoted text with \r \n \t \" \\ \xNN escapes.
// The suite:
//   * pins every frame builder byte-for-byte (Ctrl-C/A/B/D, exec, eval);
//   * decodes every trace, including banner/prompt, bare-OK slices,
//     multiline stdout (CRLF/LF/CR), UTF-8, empty output, compile errors,
//     runtime tracebacks and Ctrl-C during exec;
//   * proves the incremental decoder across one-byte chunk boundaries and
//     split boundaries, including reset/reuse and error states;
//   * pins line framing and traceback pass-through;
//   * exercises the typed error catalog and the absent-transport SKIP path
//     (no live adapter is linked in 0.1.0; XIOM_MICROPYTHON_PORT unset is
//     the normal CI state).
//
// Run: scripts/port.ps1 -Package xiom.micropython -TimeoutSec 300

module micropython_tests

use xiom.io;
use xiom.string;
use xiom.string.compare;
use xiom.encoding;
use xiom.os.process;
use xiom.micropython;

const FIXTURE_DIR: Str = "tests/fixtures/";

pub type Trace = {
  host: Vec[UInt8];
  device: Vec[UInt8];
}

// ---------------------------------------------------------------------------
// Harness helpers
// ---------------------------------------------------------------------------

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn report_skip(name: Str, why: Str) -> Int {
  io.println("  [PASS] " + name + ": SKIP -- " + why);
  io.flush_stdout();
  return 0;
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn contains(a: Str, b: Str) -> Bool {
  return string.str_contains(a, b);
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

fn byte_is(v: &Vec[UInt8], want: Int) -> Bool {
  if v.len() != 1 { return false; }
  let x: Int = (v[0] as Int) & 0xFF;
  return x == want;
}

fn bytes_from(s: Str) -> Vec[UInt8] {
  return encoding.utf8_encode(s);
}

fn concat(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn exec_bytes(code: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let f = mp_exec_frame(code);
  if f.is_ok {
    let fb: Vec[UInt8] = f.value;
    var i = 0;
    while i < fb.len() {
      out.push(fb[i]);
      i = i + 1;
    }
  }
  return out;
}

fn one(byte: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(byte as UInt8);
  return out;
}

// ---------------------------------------------------------------------------
// Fixture trace parser
// ---------------------------------------------------------------------------

fn hex_digit(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 65 && c <= 70 { return c - 55; }
  if c >= 97 && c <= 102 { return c - 87; }
  return -1;
}

fn push_dir(host: &mut Vec[UInt8], dev: &mut Vec[UInt8], is_host: Bool, b: Int) {
  if is_host { host.push(b as UInt8); }
  else { dev.push(b as UInt8); }
}

fn parse_trace_line(line: Str, host: &mut Vec[UInt8], dev: &mut Vec[UInt8]) -> Result[Unit, Str] {
  let s = string.str_trim(line);
  if s.len() == 0 { return Ok(()); }
  if string.str_starts_with(s, "#") { return Ok(()); }

  let dir = string.str_slice(s, 0, 1);
  var is_host = false;
  if streq(dir, "W") { is_host = true; }
  else if streq(dir, "R") { is_host = false; }
  else { return Err("trace: expected W or R"); }

  let n = s.len();
  var i = 1;
  while i < n {
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    if c == 32 || c == 9 {
      i = i + 1;
    } else if c == 34 {
      i = i + 1;
      var closed = false;
      while i < n && !closed {
        let cc = (string.byte_at(s, i) as Int) & 0xFF;
        if cc == 34 {
          closed = true;
          i = i + 1;
        } else if cc == 92 {
          i = i + 1;
          if i >= n { return Err("trace: dangling escape"); }
          let e = (string.byte_at(s, i) as Int) & 0xFF;
          if e == 114 {
            push_dir(host, dev, is_host, 13);
            i = i + 1;
          } else if e == 110 {
            push_dir(host, dev, is_host, 10);
            i = i + 1;
          } else if e == 116 {
            push_dir(host, dev, is_host, 9);
            i = i + 1;
          } else if e == 34 {
            push_dir(host, dev, is_host, 34);
            i = i + 1;
          } else if e == 92 {
            push_dir(host, dev, is_host, 92);
            i = i + 1;
          } else if e == 120 {
            if i + 2 >= n { return Err("trace: short \\x escape"); }
            let h1 = hex_digit((string.byte_at(s, i + 1) as Int) & 0xFF);
            let h2 = hex_digit((string.byte_at(s, i + 2) as Int) & 0xFF);
            if h1 < 0 || h2 < 0 { return Err("trace: bad \\x escape"); }
            push_dir(host, dev, is_host, h1 * 16 + h2);
            i = i + 3;
          } else {
            return Err("trace: unknown escape");
          }
        } else {
          push_dir(host, dev, is_host, cc);
          i = i + 1;
        }
      }
      if !closed { return Err("trace: unterminated quoted text"); }
    } else {
      if i + 1 >= n { return Err("trace: short hex byte"); }
      let h1 = hex_digit((string.byte_at(s, i) as Int) & 0xFF);
      let h2 = hex_digit((string.byte_at(s, i + 1) as Int) & 0xFF);
      if h1 < 0 || h2 < 0 { return Err("trace: bad hex byte"); }
      push_dir(host, dev, is_host, h1 * 16 + h2);
      i = i + 2;
    }
  }
  return Ok(());
}

fn load_trace(name: Str) -> Result[Trace, Str] {
  let r = io.read_file(FIXTURE_DIR + name);
  if !r.is_ok { return Err("fixture read failed: " + name); }
  let text: Str = r.value;
  let lines = string.str_split(text, "\n");
  var host = Vec[UInt8].new();
  var dev = Vec[UInt8].new();
  var i = 0;
  while i < lines.len() {
    let p = parse_trace_line(lines[i], &mut host, &mut dev);
    if !p.is_ok { return Err(p.error); }
    i = i + 1;
  }
  return Ok(Trace{ host: host; device: dev });
}

// ---------------------------------------------------------------------------
// Frame builders
// ---------------------------------------------------------------------------

fn test_wire_constants() -> Int {
  var ok = true;
  if MP_CTRL_A != 1 { ok = false; }
  if MP_CTRL_B != 2 { ok = false; }
  if MP_CTRL_C != 3 { ok = false; }
  if MP_CTRL_D != 4 { ok = false; }
  if MP_CTRL_E != 5 { ok = false; }
  if !streq(MP_RAW_BANNER, "raw REPL; CTRL-B to exit\r\n") { ok = false; }
  if !streq(MP_RAW_PROMPT, ">") { ok = false; }
  if !streq(MP_FRIENDLY_PROMPT, ">>> ") { ok = false; }
  if !streq(MP_OK, "OK") { ok = false; }
  if MP_PRELUDE_MAX != 4096 { ok = false; }
  if MP_DEC_PRELUDE != 0 { ok = false; }
  if MP_DEC_OK != 1 { ok = false; }
  if MP_DEC_STDOUT != 2 { ok = false; }
  if MP_DEC_STDERR != 3 { ok = false; }
  if MP_DEC_DONE != 4 { ok = false; }
  if MP_DEC_ERROR != 5 { ok = false; }
  if MP_ERR_ABSENT != 0 { ok = false; }
  if MP_ERR_IO != 1 { ok = false; }
  if MP_ERR_TIMEOUT != 2 { ok = false; }
  if MP_ERR_PROTOCOL != 3 { ok = false; }
  if MP_ERR_INVALID_ARG != 4 { ok = false; }
  if MP_ERR_EXEC != 5 { ok = false; }
  return report(ok, "constants: control bytes, banner/prompt/OK texts, decoder/error kinds");
}

fn test_frame_builders() -> Int {
  var ok = true;
  if !byte_is(&mp_interrupt_frame(), 3) { ok = false; }
  if !byte_is(&mp_enter_raw_frame(), 1) { ok = false; }
  if !byte_is(&mp_exit_raw_frame(), 2) { ok = false; }
  if !byte_is(&mp_soft_reset_frame(), 4) { ok = false; }
  let flush = mp_enter_raw_flush_frame();
  if flush.len() != 2 { ok = false; } else {
    let b0: Int = (flush[0] as Int) & 0xFF;
    let b1: Int = (flush[1] as Int) & 0xFF;
    if b0 != 13 || b1 != 1 { ok = false; }
  }
  return report(ok, "frames: Ctrl-C, Ctrl-A, CR+Ctrl-A flush, Ctrl-B, Ctrl-D soft reset");
}

fn test_exec_and_eval_frames() -> Int {
  var ok = true;
  let r = mp_exec_frame("print(123)");
  if !r.is_ok { ok = false; } else {
    let f: Vec[UInt8] = r.value;
    let want = concat(&bytes_from("print(123)"), &one(4));
    if !bytes_eq(&f, &want) { ok = false; }
  }

  let multi = mp_exec_frame("a = 1\r\nb = 2");
  if !multi.is_ok { ok = false; } else {
    let f: Vec[UInt8] = multi.value;
    let want = concat(&bytes_from("a = 1\r\nb = 2"), &one(4));
    if !bytes_eq(&f, &want) { ok = false; }
  }

  let utf = mp_exec_frame("print('é')");
  if !utf.is_ok { ok = false; } else {
    let f: Vec[UInt8] = utf.value;
    if f.len() != bytes_from("print('é')").len() + 1 { ok = false; }
    let last: Int = (f[f.len() - 1] as Int) & 0xFF;
    if last != 4 { ok = false; }
  }

  let empty = mp_exec_frame("");
  if empty.is_ok { ok = false; } else {
    if empty.error.kind != MP_ERR_INVALID_ARG { ok = false; }
    if !contains(empty.error.message, "soft-reset") { ok = false; }
  }

  let ev = mp_eval_frame("1 + 1");
  if !ev.is_ok { ok = false; } else {
    let f: Vec[UInt8] = ev.value;
    let want = exec_bytes("print(1 + 1)\n");
    if !bytes_eq(&f, &want) { ok = false; }
  }

  let evr = mp_eval_repr_frame("'x'");
  if !evr.is_ok { ok = false; } else {
    let f: Vec[UInt8] = evr.value;
    let want = exec_bytes("print(repr('x'))\n");
    if !bytes_eq(&f, &want) { ok = false; }
  }

  let ev0 = mp_eval_frame("   ");
  if ev0.is_ok { ok = false; } else {
    if ev0.error.kind != MP_ERR_INVALID_ARG { ok = false; }
  }
  let evr0 = mp_eval_repr_frame("");
  if evr0.is_ok { ok = false; } else {
    if evr0.error.kind != MP_ERR_INVALID_ARG { ok = false; }
  }

  return report(ok, "frames: exec/eval/repr exact bytes; empty input -> INVALID_ARG");
}

// ---------------------------------------------------------------------------
// Fixture sweeps
// ---------------------------------------------------------------------------

fn test_fixture_enter_exec_print() -> Int {
  let t = load_trace("enter-exec-print.trace");
  if !t.is_ok { return report(false, "fixture enter-exec-print (load)"); }
  let tr: Trace = t.value;

  var want = Vec[UInt8].new();
  want.push(1 as UInt8);
  let f = exec_bytes("print(123)");
  var i = 0;
  while i < f.len() {
    want.push(f[i]);
    i = i + 1;
  }
  want.push(2 as UInt8);

  var ok = bytes_eq(&tr.host, &want);
  let r = mp_decode_trace(&tr.device);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if !res.ok { ok = false; }
    if !streq(res.output, "123\r\n") { ok = false; }
    if res.output_lines.len() != 1 { ok = false; }
    if res.output_lines.len() == 1 {
      if !streq(res.output_lines[0], "123") { ok = false; }
    }
    if res.error.len() != 0 { ok = false; }
    if res.error_lines.len() != 0 { ok = false; }
  }
  if !mp_frame_is_complete(&tr.device) { ok = false; }

  let r2 = mp_parse_exec_response(&tr.device);
  if !r2.is_ok { ok = false; } else {
    let res2: MpExecResult = r2.value;
    if !streq(res2.output, "123\r\n") { ok = false; }
  }
  return report(ok, "fixture: enter -> print(123) -> exit (host bytes + decode)");
}

fn test_fixture_multiline() -> Int {
  let t = load_trace("exec-multiline.trace");
  if !t.is_ok { return report(false, "fixture exec-multiline (load)"); }
  let tr: Trace = t.value;
  let want = exec_bytes("print('a'); print('b'); print('c')");
  var ok = bytes_eq(&tr.host, &want);
  let r = mp_decode_trace(&tr.device);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if !res.ok { ok = false; }
    if !streq(res.output, "a\r\nb\r\nc\r") { ok = false; }
    if res.output_lines.len() != 3 { ok = false; } else {
      if !streq(res.output_lines[0], "a") { ok = false; }
      if !streq(res.output_lines[1], "b") { ok = false; }
      if !streq(res.output_lines[2], "c") { ok = false; }
    }
    if res.error.len() != 0 { ok = false; }
  }
  return report(ok, "fixture: bare-OK slice with CRLF/CR line framing");
}

fn test_fixture_traceback() -> Int {
  let t = load_trace("exec-traceback.trace");
  if !t.is_ok { return report(false, "fixture exec-traceback (load)"); }
  let tr: Trace = t.value;
  let want = exec_bytes("raise ValueError('bad')");
  var ok = bytes_eq(&tr.host, &want);
  let r = mp_decode_trace(&tr.device);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if res.ok { ok = false; }
    if res.output.len() != 0 { ok = false; }
    if !mp_traceback_is_present(res.error) { ok = false; }
    if !contains(res.error, "ValueError: bad") { ok = false; }
    let want_err = "Traceback (most recent call last):\r\n  File \"<stdin>\", line 1, in <module>\r\nValueError: bad\r\n";
    if !streq(res.error, want_err) { ok = false; }
    if res.error_lines.len() != 3 { ok = false; } else {
      if !streq(res.error_lines[0], "Traceback (most recent call last):") { ok = false; }
      if !contains(res.error_lines[1], "File \"<stdin>\", line 1") { ok = false; }
      if !streq(res.error_lines[2], "ValueError: bad") { ok = false; }
    }
    if !streq(mp_traceback_exception(res.error), "ValueError: bad") { ok = false; }
    let ev = mp_eval_extract(&res);
    if ev.is_ok { ok = false; } else {
      if ev.error.kind != MP_ERR_EXEC { ok = false; }
      if !contains(ev.error.message, "ValueError: bad") { ok = false; }
    }
  }
  let ev2 = mp_eval(&tr.device);
  if ev2.is_ok { ok = false; } else {
    if ev2.error.kind != MP_ERR_EXEC { ok = false; }
  }
  return report(ok, "fixture: ValueError traceback pass-through + eval error");
}

fn test_fixture_syntax_error() -> Int {
  let t = load_trace("exec-syntax-error.trace");
  if !t.is_ok { return report(false, "fixture exec-syntax-error (load)"); }
  let tr: Trace = t.value;
  let want = exec_bytes("print(");
  var ok = bytes_eq(&tr.host, &want);
  let r = mp_decode_trace(&tr.device);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if res.ok { ok = false; }
    if res.output.len() != 0 { ok = false; }
    if !mp_traceback_is_present(res.error) { ok = false; }
    if !contains(res.error, "SyntaxError: '(' was never closed") { ok = false; }
    if !streq(mp_traceback_exception(res.error), "SyntaxError: '(' was never closed") { ok = false; }
  }
  return report(ok, "fixture: compile SyntaxError keeps the OK + EOF framing");
}

fn test_fixture_interrupt() -> Int {
  let t = load_trace("exec-interrupt.trace");
  if !t.is_ok { return report(false, "fixture exec-interrupt (load)"); }
  let tr: Trace = t.value;
  let code = exec_bytes("while True:\r\n    pass");
  let intr = mp_interrupt_frame();
  let want = concat(&code, &intr);
  var ok = bytes_eq(&tr.host, &want);
  let r = mp_decode_trace(&tr.device);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if res.ok { ok = false; }
    if !mp_traceback_is_present(res.error) { ok = false; }
    if !contains(res.error, "KeyboardInterrupt") { ok = false; }
    if !streq(mp_traceback_exception(res.error), "KeyboardInterrupt:") { ok = false; }
  }
  return report(ok, "fixture: Ctrl-C mid-exec -> KeyboardInterrupt in stderr frame");
}

fn test_fixture_eval_value() -> Int {
  let t = load_trace("eval-value.trace");
  if !t.is_ok { return report(false, "fixture eval-value (load)"); }
  let tr: Trace = t.value;
  var want = Vec[UInt8].new();
  let f = mp_eval_frame("(6 * 7)");
  if !f.is_ok { return report(false, "fixture eval-value (frame)"); }
  let fb: Vec[UInt8] = f.value;
  var i = 0;
  while i < fb.len() {
    want.push(fb[i]);
    i = i + 1;
  }
  var ok = bytes_eq(&tr.host, &want);
  let v = mp_eval(&tr.device);
  if !v.is_ok { ok = false; } else {
    let s: Str = v.value;
    if !streq(s, "42") { ok = false; }
  }
  let r = mp_decode_trace(&tr.device);
  if !r.is_ok { ok = false; } else {
    let ev = mp_eval_extract(&r.value);
    if !ev.is_ok { ok = false; } else {
      let s: Str = ev.value;
      if !streq(s, "42") { ok = false; }
    }
  }
  return report(ok, "fixture: eval helper returns 42 (frame + extract)");
}

fn test_fixture_eval_repr() -> Int {
  let t = load_trace("eval-repr.trace");
  if !t.is_ok { return report(false, "fixture eval-repr (load)"); }
  let tr: Trace = t.value;
  var want = Vec[UInt8].new();
  let f = mp_eval_repr_frame("'xy'");
  if !f.is_ok { return report(false, "fixture eval-repr (frame)"); }
  let fb: Vec[UInt8] = f.value;
  var i = 0;
  while i < fb.len() {
    want.push(fb[i]);
    i = i + 1;
  }
  var ok = bytes_eq(&tr.host, &want);
  let v = mp_eval(&tr.device);
  if !v.is_ok { ok = false; } else {
    let s: Str = v.value;
    if !streq(s, "'xy'") { ok = false; }
  }
  return report(ok, "fixture: repr eval helper returns the Python literal");
}

fn test_fixture_empty_output() -> Int {
  let t = load_trace("exec-empty-output.trace");
  if !t.is_ok { return report(false, "fixture exec-empty-output (load)"); }
  let tr: Trace = t.value;
  let want = exec_bytes("x = 1");
  var ok = bytes_eq(&tr.host, &want);
  let r = mp_decode_trace(&tr.device);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if !res.ok { ok = false; }
    if res.output.len() != 0 { ok = false; }
    if res.output_lines.len() != 0 { ok = false; }
    if res.error_lines.len() != 0 { ok = false; }
    let ev = mp_eval_extract(&res);
    if ev.is_ok { ok = false; } else {
      if ev.error.kind != MP_ERR_EXEC { ok = false; }
      if !contains(ev.error.message, "no output") { ok = false; }
    }
  }
  return report(ok, "fixture: empty stdout decodes cleanly; eval reports no output");
}

fn test_fixture_utf8() -> Int {
  let t = load_trace("exec-utf8.trace");
  if !t.is_ok { return report(false, "fixture exec-utf8 (load)"); }
  let tr: Trace = t.value;
  var ok = true;
  let r = mp_decode_trace(&tr.device);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if !res.ok { ok = false; }
    if !streq(res.output, "héllo\r\n") { ok = false; }
    if res.output_lines.len() != 1 { ok = false; } else {
      if !streq(res.output_lines[0], "héllo") { ok = false; }
    }
  }
  return report(ok, "fixture: UTF-8 stdout bytes survive the framing");
}

// ---------------------------------------------------------------------------
// Line framing / traceback helpers
// ---------------------------------------------------------------------------

fn test_line_framing() -> Int {
  var ok = true;
  if mp_split_lines("").len() != 0 { ok = false; }
  let lf = mp_split_lines("a\nb");
  if lf.len() != 2 { ok = false; } else {
    if !streq(lf[0], "a") { ok = false; }
    if !streq(lf[1], "b") { ok = false; }
  }
  let mixed = mp_split_lines("a\r\nb\nc\r");
  if mixed.len() != 3 { ok = false; } else {
    if !streq(mixed[0], "a") { ok = false; }
    if !streq(mixed[1], "b") { ok = false; }
    if !streq(mixed[2], "c") { ok = false; }
  }
  let blanks = mp_split_lines("a\n\nb\n");
  if blanks.len() != 3 { ok = false; } else {
    if !streq(blanks[0], "a") { ok = false; }
    if !streq(blanks[1], "") { ok = false; }
    if !streq(blanks[2], "b") { ok = false; }
  }
  let only_nl = mp_split_lines("\n");
  if only_nl.len() != 1 { ok = false; } else {
    if !streq(only_nl[0], "") { ok = false; }
  }
  if !streq(mp_traceback_exception(""), "") { ok = false; }
  if !streq(mp_traceback_exception("Traceback (most recent call last):\n  File \"x\"\nKeyError: 7\n"), "KeyError: 7") { ok = false; }
  if mp_traceback_is_present("plain stderr text") { ok = false; }
  if !mp_traceback_is_present("Traceback (most recent call last):\nValueError: x") { ok = false; }
  return report(ok, "line framing: CRLF/LF/CR, blanks, trailing newline, traceback line");
}

// ---------------------------------------------------------------------------
// Incremental decoder
// ---------------------------------------------------------------------------

fn test_chunked_feed() -> Int {
  let t = load_trace("enter-exec-print.trace");
  if !t.is_ok { return report(false, "chunked feed (load)"); }
  let tr: Trace = t.value;

  var d = mp_decoder_new();
  if mp_decoder_state(&d) != MP_DEC_PRELUDE { return report(false, "chunked feed (initial state)"); }
  var chunk = Vec[UInt8].new();
  var i = 0;
  while i < tr.device.len() {
    chunk = Vec[UInt8].new();
    chunk.push(tr.device[i]);
    let fed = mp_decoder_feed(&mut d, &chunk);
    if !fed.is_ok { return report(false, "chunked feed (feed error)"); }
    i = i + 1;
  }
  var ok = mp_decoder_done(&d);
  if mp_decoder_state(&d) != MP_DEC_DONE { ok = false; }
  let r = mp_decoder_result(&d);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if !res.ok { ok = false; }
    if !streq(res.output, "123\r\n") { ok = false; }
  }
  if !contains(mp_decoder_banner(&d), "raw REPL; CTRL-B to exit") { ok = false; }

  mp_decoder_reset(&mut d);
  if mp_decoder_state(&d) != MP_DEC_PRELUDE { ok = false; }
  if mp_decoder_done(&d) { ok = false; }
  if mp_decoder_banner(&d).len() != 0 { ok = false; }

  let t2 = load_trace("exec-traceback.trace");
  if !t2.is_ok { ok = false; } else {
    let tr2: Trace = t2.value;
    var i2 = 0;
    while i2 < tr2.device.len() {
      var c2 = Vec[UInt8].new();
      if i2 + 1 < tr2.device.len() {
        c2.push(tr2.device[i2]);
        c2.push(tr2.device[i2 + 1]);
        i2 = i2 + 2;
      } else {
        c2.push(tr2.device[i2]);
        i2 = i2 + 1;
      }
      let fed2 = mp_decoder_feed(&mut d, &c2);
      if !fed2.is_ok { ok = false; i2 = tr2.device.len(); }
    }
    let r2 = mp_decoder_result(&d);
    if !r2.is_ok { ok = false; } else {
      let res2: MpExecResult = r2.value;
      if res2.ok { ok = false; }
      if !contains(res2.error, "ValueError: bad") { ok = false; }
    }
  }
  return report(ok, "decoder: one-byte chunks, reset/reuse, two-byte chunks");
}

fn test_decoder_states() -> Int {
  var ok = true;
  var d = mp_decoder_new();

  var pre = bytes_from("\r\nraw REPL; CTRL-B to exit\r\n");
  let f1 = mp_decoder_feed(&mut d, &pre);
  if !f1.is_ok { ok = false; }
  if mp_decoder_state(&d) != MP_DEC_PRELUDE { ok = false; }

  let prompt = one(62);
  let f2 = mp_decoder_feed(&mut d, &prompt);
  if !f2.is_ok { ok = false; }
  if mp_decoder_state(&d) != MP_DEC_OK { ok = false; }

  let ack = bytes_from("OK");
  let f3 = mp_decoder_feed(&mut d, &ack);
  if !f3.is_ok { ok = false; }
  if mp_decoder_state(&d) != MP_DEC_STDOUT { ok = false; }

  let out = bytes_from("hello\r\n");
  let f4 = mp_decoder_feed(&mut d, &out);
  if !f4.is_ok { ok = false; }
  if mp_decoder_state(&d) != MP_DEC_STDOUT { ok = false; }

  let eof = one(4);
  let f5 = mp_decoder_feed(&mut d, &eof);
  if !f5.is_ok { ok = false; }
  if mp_decoder_state(&d) != MP_DEC_STDERR { ok = false; }

  let f6 = mp_decoder_feed(&mut d, &eof);
  if !f6.is_ok { ok = false; }
  if mp_decoder_state(&d) != MP_DEC_DONE { ok = false; }
  if !mp_decoder_done(&d) { ok = false; }
  if !contains(mp_decoder_banner(&d), "raw REPL") { ok = false; }

  let tail = bytes_from(">>> ");
  let f7 = mp_decoder_feed(&mut d, &tail);
  if !f7.is_ok { ok = false; }
  if mp_decoder_state(&d) != MP_DEC_DONE { ok = false; }

  let r = mp_decoder_result(&d);
  if !r.is_ok { ok = false; } else {
    let res: MpExecResult = r.value;
    if !streq(res.output, "hello\r\n") { ok = false; }
    if !res.ok { ok = false; }
  }
  return report(ok, "decoder: PRELUDE -> OK -> STDOUT -> STDERR -> DONE, tail ignored");
}

fn test_decoder_errors() -> Int {
  var ok = true;

  let empty = mp_decode_trace(&Vec[UInt8].new());
  if empty.is_ok { ok = false; } else {
    if empty.error.kind != MP_ERR_PROTOCOL { ok = false; }
    if !contains(empty.error.message, "incomplete") { ok = false; }
  }

  var bad = Vec[UInt8].new();
  bad.push(62 as UInt8);
  bad.push(78 as UInt8);
  bad.push(79 as UInt8);
  let badr = mp_decode_trace(&bad);
  if badr.is_ok { ok = false; } else {
    if badr.error.kind != MP_ERR_PROTOCOL { ok = false; }
    if !contains(badr.error.message, "expected OK") { ok = false; }
  }

  var big = Vec[UInt8].new();
  var i = 0;
  while i < 4200 {
    big.push(65 as UInt8);
    i = i + 1;
  }
  let bigr = mp_decode_trace(&big);
  if bigr.is_ok { ok = false; } else {
    if bigr.error.kind != MP_ERR_PROTOCOL { ok = false; }
    if !contains(bigr.error.message, "prompt") { ok = false; }
  }

  if mp_frame_is_complete(&Vec[UInt8].new()) { ok = false; }
  if mp_frame_is_complete(&bad) { ok = false; }

  var d = mp_decoder_new();
  let f = mp_decoder_feed(&mut d, &bad);
  if f.is_ok { ok = false; }
  if mp_decoder_state(&d) != MP_DEC_ERROR { ok = false; }
  let f2 = mp_decoder_feed(&mut d, &one(4));
  if f2.is_ok { ok = false; }
  let r = mp_decoder_result(&d);
  if r.is_ok { ok = false; }

  let ev = mp_eval(&big);
  if ev.is_ok { ok = false; } else {
    if ev.error.kind != MP_ERR_PROTOCOL { ok = false; }
  }

  return report(ok, "decoder: incomplete, bad OK, oversized banner, ERROR state");
}

fn test_prelude_variants() -> Int {
  var ok = true;

  let bare = bytes_from("OKabc\r\n");
  let two_eof = concat(&one(4), &one(4));
  let close = concat(&two_eof, &bytes_from(">"));
  let bare_full = concat(&bare, &close);
  let r1 = mp_decode_trace(&bare_full);
  if !r1.is_ok { ok = false; } else {
    let res1: MpExecResult = r1.value;
    if !streq(res1.output, "abc\r\n") { ok = false; }
  }

  let prompt_only = concat(&one(62), &bare_full);
  let r2 = mp_decode_trace(&prompt_only);
  if !r2.is_ok { ok = false; } else {
    let res2: MpExecResult = r2.value;
    if !streq(res2.output, "abc\r\n") { ok = false; }
  }

  let boot_pre = bytes_from("\r\nMPY: soft reboot\r\nraw REPL; CTRL-B to exit\r\n>OKz\r\n");
  let boot = concat(&boot_pre, &close);
  let r3 = mp_decode_trace(&boot);
  if !r3.is_ok { ok = false; } else {
    let res3: MpExecResult = r3.value;
    if !streq(res3.output, "z\r\n") { ok = false; }
  }

  let padded = concat(&bytes_from("\r\n"), &bare_full);
  let r4 = mp_decode_trace(&padded);
  if !r4.is_ok { ok = false; } else {
    let res4: MpExecResult = r4.value;
    if !streq(res4.output, "abc\r\n") { ok = false; }
  }

  return report(ok, "decoder: bare OK, prompt-only, soft-reboot and CRLF-padded preludes");
}

// ---------------------------------------------------------------------------
// Error catalog / SKIP path
// ---------------------------------------------------------------------------

fn test_error_catalog() -> Int {
  var ok = true;
  if !streq(mp_error_name(MP_ERR_ABSENT), "absent") { ok = false; }
  if !streq(mp_error_name(MP_ERR_IO), "io") { ok = false; }
  if !streq(mp_error_name(MP_ERR_TIMEOUT), "timeout") { ok = false; }
  if !streq(mp_error_name(MP_ERR_PROTOCOL), "protocol") { ok = false; }
  if !streq(mp_error_name(MP_ERR_INVALID_ARG), "invalid-arg") { ok = false; }
  if !streq(mp_error_name(MP_ERR_EXEC), "exec") { ok = false; }
  if !streq(mp_error_name(99), "unknown") { ok = false; }

  let e = mp_error(MP_ERR_IO, "write failed");
  if e.kind != MP_ERR_IO { ok = false; }
  if !streq(e.message, "micropython: write failed") { ok = false; }
  if mp_error_is_skip(&e) { ok = false; }

  let a = mp_error_absent("COM7");
  if !mp_error_is_skip(&a) { ok = false; }
  if !contains(a.message, "COM7") { ok = false; }
  if !contains(a.message, "SKIP") { ok = false; }
  return report(ok, "errors: names, message prefix, skip classification");
}

fn test_absent_transport_skip() -> Int {
  let env = process.env_var("XIOM_MICROPYTHON_PORT");
  if !env.is_some {
    let e = mp_error_absent("uart (XIOM_MICROPYTHON_PORT unset)");
    var ok = true;
    if !mp_error_is_skip(&e) { ok = false; }
    if !contains(e.message, "SKIP") { ok = false; }
    if !ok { return report(false, "absent transport: typed SKIP"); }
    return report_skip("absent transport", "no link/port in this environment; typed MP_ERR_ABSENT SKIP path verified");
  }
  return report_skip("absent transport", "XIOM_MICROPYTHON_PORT is set; live adapter is out of scope for 0.1.0");
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.micropython conformance tests ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + test_wire_constants();
  failed = failed + test_frame_builders();
  failed = failed + test_exec_and_eval_frames();
  failed = failed + test_fixture_enter_exec_print();
  failed = failed + test_fixture_multiline();
  failed = failed + test_fixture_traceback();
  failed = failed + test_fixture_syntax_error();
  failed = failed + test_fixture_interrupt();
  failed = failed + test_fixture_eval_value();
  failed = failed + test_fixture_eval_repr();
  failed = failed + test_fixture_empty_output();
  failed = failed + test_fixture_utf8();
  failed = failed + test_line_framing();
  failed = failed + test_chunked_feed();
  failed = failed + test_decoder_states();
  failed = failed + test_decoder_errors();
  failed = failed + test_prelude_variants();
  failed = failed + test_error_catalog();
  failed = failed + test_absent_transport_skip();

  if failed == 0 {
    io.println("xiom.micropython: all tests passed");
  } else {
    io.println("xiom.micropython: tests failed");
  }
  return failed;
}
