// XIOM -- xiom.micropython conformance suite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage:
//   * every request builder: enter/exit/interrupt/soft-reset and the
//     exec/eval frames (embedded-EOT argument errors included);
//   * raw-REPL enter banners with and without the friendly leading CRLF;
//   * exec frames: stdout, empty output, traceback pass-through, Ctrl-C
//     interrupted output, the empty-command soft reset, and every framing
//     failure (missing OK, missing EOTs, missing prompt);
//   * the friendly-REPL exit prompt and the default-prompt assumption;
//   * line framing for stdout/stderr (CRLF normalization, interior blank
//     lines, trailing-newline handling) and eval value extraction;
//   * the transport leg is SKIP-safe: with no XIOM_MICROPYTHON_PORT the
//     suite stays green on byte traces alone.
//
// Fixtures live in tests/fixtures/*.trace: comment lines start with '#',
// ">HEX" is the host byte sequence and "<HEX" is the device byte sequence.

module micropython_tests

use xiom.io;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;
use xiom.micropython;

const FIXTURES: Str = "tests/fixtures/";

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

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn has(msg: Str, frag: Str) -> Bool {
  return string.str_contains(msg, frag);
}

fn hex_eq(v: &Vec[UInt8], want_hex: Str) -> Bool {
  let hr = hex.hex_decode(want_hex);
  if !hr.is_ok {
    return false;
  }
  let w: Vec[UInt8] = hr.value;
  if w.len() != v.len() {
    return false;
  }
  var i = 0;
  while i < v.len() {
    let a = (v[i] as Int) & 0xFF;
    let b = (w[i] as Int) & 0xFF;
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn hvec(s: Str) -> Vec[UInt8] {
  let hr = hex.hex_decode(s);
  if hr.is_ok {
    return hr.value;
  }
  return Vec[UInt8].new();
}

type TracePair = {
  request: Vec[UInt8];
  response: Vec[UInt8];
}

fn load_trace(name: Str) -> Result[TracePair, Str] {
  let path = FIXTURES + name;
  let fr = io.read_file(path);
  if !fr.is_ok {
    return Err("fixture: cannot read " + path + ": " + fr.error);
  }
  let text: Str = fr.value;
  let lines = string.lines(text);
  var req = Vec[UInt8].new();
  var resp = Vec[UInt8].new();
  var have_req = false;
  var have_resp = false;
  var i = 0;
  while i < lines.len() {
    let line: Str = lines[i];
    if line.len() >= 2 {
      let c0 = (string.byte_at(line, 0) as Int) & 0xFF;
      if c0 == 62 || c0 == 60 {
        let hs = string.str_slice(line, 1, line.len());
        let hr = hex.hex_decode(hs);
        if !hr.is_ok {
          return Err("fixture: bad hex in " + path);
        }
        if c0 == 62 {
          req = hr.value;
          have_req = true;
        } else {
          resp = hr.value;
          have_resp = true;
        }
      }
    }
    i = i + 1;
  }
  if !have_req {
    return Err("fixture: missing request line in " + path);
  }
  if !have_resp {
    return Err("fixture: missing response line in " + path);
  }
  return Ok(TracePair{ request: req; response: resp });
}

fn trace_ok(name: Str) -> Bool {
  let r = load_trace(name);
  return r.is_ok;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn test_fixtures_load() -> Int {
  var ok = true;
  if !trace_ok("enter-friendly.trace") { ok = false; }
  if !trace_ok("enter-already-raw.trace") { ok = false; }
  if !trace_ok("exec-print.trace") { ok = false; }
  if !trace_ok("exec-error.trace") { ok = false; }
  if !trace_ok("exec-interrupt.trace") { ok = false; }
  if !trace_ok("exec-empty-output.trace") { ok = false; }
  if !trace_ok("exec-soft-reset.trace") { ok = false; }
  if !trace_ok("eval-repr.trace") { ok = false; }
  if !trace_ok("exit.trace") { ok = false; }
  return report(ok, "fixtures: 9 byte-trace scripts load");
}

// ---------------------------------------------------------------------------
// Request builders
// ---------------------------------------------------------------------------

fn test_request_controls() -> Int {
  var ok = true;
  let a = mp_repl_enter_request();
  let aok = hex_eq(&a, "01");
  if !aok { ok = false; }
  let b = mp_repl_exit_request();
  let bok = hex_eq(&b, "02");
  if !bok { ok = false; }
  let c = mp_repl_interrupt_request();
  let cok = hex_eq(&c, "03");
  if !cok { ok = false; }
  let d = mp_repl_soft_reset_request();
  let dok = hex_eq(&d, "04");
  if !dok { ok = false; }
  if MP_CTRL_A != 1 { ok = false; }
  if MP_CTRL_B != 2 { ok = false; }
  if MP_CTRL_C != 3 { ok = false; }
  if MP_CTRL_D != 4 { ok = false; }
  if MP_PROMPT != 62 { ok = false; }
  return report(ok, "requests: Ctrl-A/B/C/D and prompt constants byte-exact");
}

fn test_request_exec() -> Int {
  var ok = true;
  let r = mp_repl_exec_request("print(1)");
  let rok = r.is_ok;
  if !rok {
    return report(false, "exec-request: builder failed");
  }
  let v: Vec[UInt8] = r.value;
  let vok = hex_eq(&v, "7072696E7428312904");
  if !vok { ok = false; }
  // empty command is the soft-reset form
  let r2 = mp_repl_exec_request("");
  let r2ok = r2.is_ok;
  if !r2ok {
    ok = false;
  } else {
    let v2: Vec[UInt8] = r2.value;
    let v2ok = hex_eq(&v2, "04");
    if !v2ok { ok = false; }
  }
  return report(ok, "exec-request: code + 0x04; empty code -> 0x04");
}

fn test_request_exec_eot_arg() -> Int {
  let r = mp_repl_exec_request("a\x04b");
  let rok = r.is_ok;
  if rok {
    return report(false, "exec-request-eot: embedded EOT accepted");
  }
  let e: MpError = r.error;
  let k = e.kind;
  let msg: Str = e.message;
  var ok = true;
  if k != MP_ERR_ARG { ok = false; }
  if !has(msg, "EOT") { ok = false; }
  return report(ok, "exec-request-eot: embedded 0x04 -> MP_ERR_ARG");
}

// ---------------------------------------------------------------------------
// Enter / exit
// ---------------------------------------------------------------------------

fn test_parse_enter() -> Int {
  let fr = load_trace("enter-friendly.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "enter: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_enter(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    let re: MpError = rr.error;
    return report(false, "enter: friendly trace rejected (" + re.message + ")");
  }
  var ok = true;
  let used = rr.value;
  let n = tr.response.len();
  if used != n { ok = false; }
  // trailing bytes after the prompt are not consumed
  var t: Vec[UInt8] = tr.response;
  t.push(65);
  let rr2 = mp_parse_enter(&t);
  let r2ok = rr2.is_ok;
  if !r2ok {
    ok = false;
  } else {
    let used2 = rr2.value;
    if used2 != n { ok = false; }
  }
  let fr2 = load_trace("enter-already-raw.trace");
  let f2ok = fr2.is_ok;
  if !f2ok {
    ok = false;
  } else {
    let tr2: TracePair = fr2.value;
    let rr3 = mp_parse_enter(&tr2.response);
    let r3ok = rr3.is_ok;
    if !r3ok {
      ok = false;
    } else {
      let used3 = rr3.value;
      let n3 = tr2.response.len();
      if used3 != n3 { ok = false; }
    }
  }
  return report(ok, "enter: banner + prompt parsed, leading CRLF optional, consumed exact");
}

fn test_parse_enter_errors() -> Int {
  var ok = true;
  let missing = hvec("3E3E3E20");
  let r1 = mp_parse_enter(&missing);
  let r1ok = r1.is_ok;
  if r1ok { ok = false; } else {
    let e1: MpError = r1.error;
    if e1.kind != MP_ERR_FRAMING { ok = false; }
    if !has(e1.message, "banner") { ok = false; }
  }
  let no_prompt = hvec("726177205245504C3B204354524C2D4220746F20657869740D0A");
  let r2 = mp_parse_enter(&no_prompt);
  let r2ok = r2.is_ok;
  if r2ok { ok = false; } else {
    let e2: MpError = r2.error;
    if e2.kind != MP_ERR_FRAMING { ok = false; }
    if !has(e2.message, "prompt") { ok = false; }
  }
  let empty = hvec("");
  let r3 = mp_parse_enter(&empty);
  let r3ok = r3.is_ok;
  if r3ok { ok = false; }
  return report(ok, "enter-errors: missing banner / prompt are framing errors");
}

fn test_parse_exit() -> Int {
  let fr = load_trace("exit.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "exit: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_exit(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    let re: MpError = rr.error;
    return report(false, "exit: friendly prompt rejected (" + re.message + ")");
  }
  var ok = true;
  let used = rr.value;
  let n = tr.response.len();
  if used != n { ok = false; }
  let bad = hvec("0D0A4D6963726F507974686F6E0D0A");
  let rb = mp_parse_exit(&bad);
  let rbok = rb.is_ok;
  if rbok { ok = false; } else {
    let eb: MpError = rb.error;
    if eb.kind != MP_ERR_FRAMING { ok = false; }
  }
  return report(ok, "exit: default >>> prompt parsed; missing prompt framed as error");
}

// ---------------------------------------------------------------------------
// Exec frames
// ---------------------------------------------------------------------------

fn test_parse_exec_ok() -> Int {
  let fr = load_trace("exec-print.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "exec-ok: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_exec(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    let re: MpError = rr.error;
    return report(false, "exec-ok: frame rejected (" + re.message + ")");
  }
  let ex: MpExec = rr.value;
  var ok = true;
  let out: Str = ex.output;
  if !streq(out, "123\r\n") { ok = false; }
  let err: Str = ex.error;
  if err.len() != 0 { ok = false; }
  if ex.soft_reset { ok = false; }
  let n = tr.response.len();
  if ex.consumed != n { ok = false; }
  let eok = mp_exec_ok(ex);
  if !eok { ok = false; }
  // trailing bytes after the prompt are not consumed
  var t: Vec[UInt8] = tr.response;
  t.push(78);
  let rr2 = mp_parse_exec(&t);
  let r2ok = rr2.is_ok;
  if !r2ok {
    ok = false;
  } else {
    let ex2: MpExec = rr2.value;
    if ex2.consumed != n { ok = false; }
  }
  return report(ok, "exec-ok: OK/output/EOT/EOT/prompt parsed; consumed exact; trailing bytes kept");
}

fn test_parse_exec_error() -> Int {
  let fr = load_trace("exec-error.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "exec-error: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_exec(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    let re: MpError = rr.error;
    return report(false, "exec-error: frame rejected (" + re.message + ")");
  }
  let ex: MpExec = rr.value;
  var ok = true;
  let out: Str = ex.output;
  if out.len() != 0 { ok = false; }
  let err: Str = ex.error;
  let want = "Traceback (most recent call last):\r\n  File \"<stdin>\", line 1, in <module>\r\nZeroDivisionError: divide by zero\r\n";
  if !streq(err, want) { ok = false; }
  let n = tr.response.len();
  if ex.consumed != n { ok = false; }
  let eok = mp_exec_ok(ex);
  if eok { ok = false; }
  let fr2 = load_trace("exec-error.trace");
  let f2ok = fr2.is_ok;
  if !f2ok {
    ok = false;
  } else {
    let tr2: TracePair = fr2.value;
    let rr2 = mp_parse_exec(&tr2.response);
    let r2ok = rr2.is_ok;
    if !r2ok {
      ok = false;
    } else {
      let ev = mp_eval_value(rr2.value);
      let evok = ev.is_ok;
      if evok { ok = false; } else {
        let ee: MpError = ev.error;
        if ee.kind != MP_ERR_EXEC { ok = false; }
        if !has(ee.message, "ZeroDivisionError") { ok = false; }
      }
    }
  }
  return report(ok, "exec-error: traceback passed through; exec_ok false; eval reports MP_ERR_EXEC");
}

fn test_parse_exec_interrupt() -> Int {
  let fr = load_trace("exec-interrupt.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "exec-interrupt: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_exec(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    let re: MpError = rr.error;
    return report(false, "exec-interrupt: frame rejected (" + re.message + ")");
  }
  let ex: MpExec = rr.value;
  var ok = true;
  let out: Str = ex.output;
  if !streq(out, "partial") { ok = false; }
  let err: Str = ex.error;
  if !has(err, "KeyboardInterrupt") { ok = false; }
  let n = tr.response.len();
  if ex.consumed != n { ok = false; }
  let eok = mp_exec_ok(ex);
  if eok { ok = false; }
  return report(ok, "exec-interrupt: partial stdout + KeyboardInterrupt traceback preserved");
}

fn test_parse_exec_soft_reset() -> Int {
  var ok = true;
  let fr = load_trace("exec-soft-reset.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "exec-soft-reset: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_exec(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    let re: MpError = rr.error;
    return report(false, "exec-soft-reset: frame rejected (" + re.message + ")");
  }
  let ex: MpExec = rr.value;
  if !ex.soft_reset { ok = false; }
  let out: Str = ex.output;
  if out.len() != 0 { ok = false; }
  let err: Str = ex.error;
  if err.len() != 0 { ok = false; }
  if ex.consumed != 4 { ok = false; }
  let eok = mp_exec_ok(ex);
  if eok { ok = false; }
  // no-output frame is distinct from a soft reset
  let fr2 = load_trace("exec-empty-output.trace");
  let f2ok = fr2.is_ok;
  if !f2ok {
    ok = false;
  } else {
    let tr2: TracePair = fr2.value;
    let rr2 = mp_parse_exec(&tr2.response);
    let r2ok = rr2.is_ok;
    if !r2ok {
      ok = false;
    } else {
      let ex2: MpExec = rr2.value;
      if ex2.soft_reset { ok = false; }
      let o2: Str = ex2.output;
      if o2.len() != 0 { ok = false; }
      let n2 = tr2.response.len();
      if ex2.consumed != n2 { ok = false; }
      let e2ok = mp_exec_ok(ex2);
      if !e2ok { ok = false; }
    }
  }
  return report(ok, "exec-soft-reset: OK CRLF only; empty-output frame stays a normal exec");
}

fn test_parse_exec_framing_errors() -> Int {
  var ok = true;
  let empty = hvec("");
  let r1 = mp_parse_exec(&empty);
  let r1ok = r1.is_ok;
  if r1ok { ok = false; } else {
    let e1: MpError = r1.error;
    if e1.kind != MP_ERR_FRAMING { ok = false; }
  }
  let no_ok = hvec("4E4F");
  let r2 = mp_parse_exec(&no_ok);
  let r2ok = r2.is_ok;
  if r2ok { ok = false; } else {
    let e2: MpError = r2.error;
    if !has(e2.message, "OK") { ok = false; }
  }
  let no_e1 = hvec("4F4B313233");
  let r3 = mp_parse_exec(&no_e1);
  let r3ok = r3.is_ok;
  if r3ok { ok = false; } else {
    let e3: MpError = r3.error;
    if !has(e3.message, "stdout EOT") { ok = false; }
  }
  let no_e2 = hvec("4F4B3132330404");
  let r4 = mp_parse_exec(&no_e2);
  let r4ok = r4.is_ok;
  if r4ok { ok = false; } else {
    let e4: MpError = r4.error;
    if !has(e4.message, "prompt") { ok = false; }
  }
  let no_e2b = hvec("4F4B3104");
  let r5 = mp_parse_exec(&no_e2b);
  let r5ok = r5.is_ok;
  if r5ok { ok = false; } else {
    let e5: MpError = r5.error;
    if !has(e5.message, "stderr EOT") { ok = false; }
  }
  let no_prompt = hvec("4F4B0404");
  let r6 = mp_parse_exec(&no_prompt);
  let r6ok = r6.is_ok;
  if r6ok { ok = false; } else {
    let e6: MpError = r6.error;
    if !has(e6.message, "prompt") { ok = false; }
  }
  return report(ok, "exec-errors: missing OK / stdout EOT / stderr EOT / prompt all framed");
}

// ---------------------------------------------------------------------------
// Line framing and eval
// ---------------------------------------------------------------------------

fn test_lines_framing() -> Int {
  var ok = true;
  let e = mp_lines("");
  if e.len() != 0 { ok = false; }
  let a = mp_lines("a\r\nb\r\n");
  if a.len() != 2 { ok = false; } else {
    if !streq(a[0], "a") { ok = false; }
    if !streq(a[1], "b") { ok = false; }
  }
  let b = mp_lines("a\n\nb");
  if b.len() != 3 { ok = false; } else {
    if !streq(b[0], "a") { ok = false; }
    if b[1].len() != 0 { ok = false; }
    if !streq(b[2], "b") { ok = false; }
  }
  let c = mp_lines("\r\n");
  if c.len() != 1 { ok = false; } else {
    if c[0].len() != 0 { ok = false; }
  }
  let d = mp_lines("abc");
  if d.len() != 1 { ok = false; } else {
    if !streq(d[0], "abc") { ok = false; }
  }
  let tb = mp_lines("Traceback (most recent call last):\r\n  File \"<stdin>\", line 1\r\nValueError: bad\r\n");
  if tb.len() != 3 { ok = false; } else {
    let l0: Str = tb[0];
    let l1: Str = tb[1];
    let l2: Str = tb[2];
    if !streq(l0, "Traceback (most recent call last):") { ok = false; }
    if !streq(l1, "  File \"<stdin>\", line 1") { ok = false; }
    if !streq(l2, "ValueError: bad") { ok = false; }
  }
  return report(ok, "lines: CRLF normalization, interior blanks, trailing LF, traceback frames");
}

fn test_output_error_lines() -> Int {
  let fr = load_trace("exec-interrupt.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "payload-lines: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_exec(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    let re: MpError = rr.error;
    return report(false, "payload-lines: frame rejected (" + re.message + ")");
  }
  var ok = true;
  let ol = mp_output_lines(rr.value);
  if ol.len() != 1 { ok = false; } else {
    if !streq(ol[0], "partial") { ok = false; }
  }
  let rr2 = mp_parse_exec(&tr.response);
  let r2ok = rr2.is_ok;
  if !r2ok {
    ok = false;
  } else {
    let el = mp_error_lines(rr2.value);
    if el.len() != 3 { ok = false; } else {
      let last: Str = el[2];
      if !has(last, "KeyboardInterrupt") { ok = false; }
    }
  }
  return report(ok, "payload-lines: stdout one line; stderr traceback kept as three lines");
}

fn test_eval_requests() -> Int {
  var ok = true;
  let r = mp_eval_request("1+2");
  let rok = r.is_ok;
  if !rok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r.value;
    let vok = hex_eq(&v, "7072696E7428312B322904");
    if !vok { ok = false; }
  }
  let rr = mp_eval_repr_request("1+2");
  let rrok = rr.is_ok;
  if !rrok {
    ok = false;
  } else {
    let v2: Vec[UInt8] = rr.value;
    let v2ok = hex_eq(&v2, "7072696E74287265707228312B32292904");
    if !v2ok { ok = false; }
  }
  let e1 = mp_eval_request("");
  let e1ok = e1.is_ok;
  if e1ok { ok = false; } else {
    let ee1: MpError = e1.error;
    if ee1.kind != MP_ERR_ARG { ok = false; }
  }
  let e2 = mp_eval_repr_request("");
  let e2ok = e2.is_ok;
  if e2ok { ok = false; } else {
    let ee2: MpError = e2.error;
    if ee2.kind != MP_ERR_ARG { ok = false; }
  }
  let e3 = mp_eval_request("1\x042");
  let e3ok = e3.is_ok;
  if e3ok { ok = false; } else {
    let ee3: MpError = e3.error;
    if ee3.kind != MP_ERR_ARG { ok = false; }
  }
  return report(ok, "eval-requests: print(EXPR) / print(repr(EXPR)); empty and EOT rejected");
}

fn test_eval_value() -> Int {
  var ok = true;
  let fr = load_trace("eval-repr.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "eval-value: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_exec(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    let re: MpError = rr.error;
    return report(false, "eval-value: frame rejected (" + re.message + ")");
  }
  let ev = mp_eval_value(rr.value);
  let evok = ev.is_ok;
  if !evok {
    ok = false;
  } else {
    let v: Str = ev.value;
    if !streq(v, "3") { ok = false; }
  }
  let multi = hvec("4F4B610D0A620D0A04043E");
  let mr = mp_parse_exec(&multi);
  let mrok = mr.is_ok;
  if !mrok {
    ok = false;
  } else {
    let mv = mp_eval_value(mr.value);
    let mvok = mv.is_ok;
    if !mvok {
      ok = false;
    } else {
      let ms: Str = mv.value;
      if !streq(ms, "a\r\nb") { ok = false; }
    }
  }
  let empty = hvec("4F4B04043E");
  let er = mp_parse_exec(&empty);
  let erok = er.is_ok;
  if !erok {
    ok = false;
  } else {
    let ev2 = mp_eval_value(er.value);
    let ev2ok = ev2.is_ok;
    if ev2ok { ok = false; } else {
      let ee: MpError = ev2.error;
      if ee.kind != MP_ERR_EXEC { ok = false; }
      if !has(ee.message, "no output") { ok = false; }
    }
  }
  return report(ok, "eval-value: trailing CRLF stripped, internal lines kept, empty output typed");
}

fn test_eval_errors() -> Int {
  var ok = true;
  let fr = load_trace("exec-error.trace");
  let frok = fr.is_ok;
  if !frok {
    let fe: Str = fr.error;
    return report(false, "eval-errors: fixture load (" + fe + ")");
  }
  let tr: TracePair = fr.value;
  let rr = mp_parse_exec(&tr.response);
  let rok = rr.is_ok;
  if !rok {
    ok = false;
  } else {
    let ev = mp_eval_value(rr.value);
    let evok = ev.is_ok;
    if evok { ok = false; } else {
      let ee: MpError = ev.error;
      if ee.kind != MP_ERR_EXEC { ok = false; }
      if !has(ee.message, "Traceback") { ok = false; }
      if !has(ee.message, "ZeroDivisionError") { ok = false; }
    }
  }
  let sr = load_trace("exec-soft-reset.trace");
  let srok = sr.is_ok;
  if !srok {
    ok = false;
  } else {
    let str2: TracePair = sr.value;
    let pr = mp_parse_exec(&str2.response);
    let prok = pr.is_ok;
    if !prok {
      ok = false;
    } else {
      let ev2 = mp_eval_value(pr.value);
      let ev2ok = ev2.is_ok;
      if ev2ok { ok = false; } else {
        let ee2: MpError = ev2.error;
        if !has(ee2.message, "soft reset") { ok = false; }
      }
    }
  }
  return report(ok, "eval-errors: traceback pass-through message; soft reset typed");
}

fn test_exec_ok() -> Int {
  var ok = true;
  let fr = load_trace("exec-print.trace");
  let frok = fr.is_ok;
  if !frok {
    ok = false;
  } else {
    let tr: TracePair = fr.value;
    let rr = mp_parse_exec(&tr.response);
    let rok = rr.is_ok;
    if !rok {
      ok = false;
    } else {
      let eok = mp_exec_ok(rr.value);
      if !eok { ok = false; }
    }
  }
  let fr2 = load_trace("exec-error.trace");
  let f2ok = fr2.is_ok;
  if !f2ok {
    ok = false;
  } else {
    let tr2: TracePair = fr2.value;
    let rr2 = mp_parse_exec(&tr2.response);
    let r2ok = rr2.is_ok;
    if !r2ok {
      ok = false;
    } else {
      let e2 = mp_exec_ok(rr2.value);
      if e2 { ok = false; }
    }
  }
  let fr3 = load_trace("exec-soft-reset.trace");
  let f3ok = fr3.is_ok;
  if !f3ok {
    ok = false;
  } else {
    let tr3: TracePair = fr3.value;
    let rr3 = mp_parse_exec(&tr3.response);
    let r3ok = rr3.is_ok;
    if !r3ok {
      ok = false;
    } else {
      let e3 = mp_exec_ok(rr3.value);
      if e3 { ok = false; }
    }
  }
  return report(ok, "exec-ok: success true; traceback frame and soft reset false");
}

// ---------------------------------------------------------------------------
// Transport leg (SKIP-safe without hardware)
// ---------------------------------------------------------------------------

fn test_transport_skip() -> Int {
  let env = io.env_var("XIOM_MICROPYTHON_PORT");
  let have = env.is_some;
  if !have {
    return report(true, "transport: SKIP -- no XIOM_MICROPYTHON_PORT (byte-trace suite only)");
  }
  let port: Str = env.value;
  let fr = io.open(port, "rb+");
  let frok = fr.is_ok;
  if !frok {
    let fe: IOError = fr.error;
    return report(true, "transport: SKIP -- cannot open " + port + " (" + fe.message + ")");
  }
  let h: Int = fr.value;
  let cr = io.close(h);
  let crok = cr.is_ok;
  return report(crok, "transport: live port " + port + " opened and closed; protocol covered by traces");
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.micropython conformance tests ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + test_fixtures_load();
  failed = failed + test_request_controls();
  failed = failed + test_request_exec();
  failed = failed + test_request_exec_eot_arg();
  failed = failed + test_parse_enter();
  failed = failed + test_parse_enter_errors();
  failed = failed + test_parse_exit();
  failed = failed + test_parse_exec_ok();
  failed = failed + test_parse_exec_error();
  failed = failed + test_parse_exec_interrupt();
  failed = failed + test_parse_exec_soft_reset();
  failed = failed + test_parse_exec_framing_errors();
  failed = failed + test_lines_framing();
  failed = failed + test_output_error_lines();
  failed = failed + test_eval_requests();
  failed = failed + test_eval_value();
  failed = failed + test_eval_errors();
  failed = failed + test_exec_ok();
  failed = failed + test_transport_skip();

  if failed == 0 {
    io.println("xiom.micropython: all tests passed");
  } else {
    io.println("xiom.micropython: tests failed");
  }
  return failed;
}
