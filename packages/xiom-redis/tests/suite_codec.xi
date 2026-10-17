// XIOM -- xiom.redis conformance suite, part 1: RESP2 codec and value model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Codec goldens (exact wire bytes), every RESP2 reply type (simple, error,
// integer, bulk, null bulk, array, null array, nested arrays) with consumed
// counts, the truncated / garbage / cap / depth protocol-error paths, and
// the typed value accessors including the wrong-type error path. All
// fixtures are inline; no upstream files are consumed.
//
// Str equality goes through compare.str_compare (BUG 17 discipline).

module xiom.redis.suite_codec

use xiom.io;
use xiom.test;
use xiom.string.compare;
use xiom.redis;
use xiom.redis.value;
use xiom.redis.resp;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  let n = s.len();
  while i < n {
    let b: UInt8 = s.byte_at(i);
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Decode a Str literal as a whole RESP reply.
fn dec(s: Str) -> Result[RedisValue, RedisError] {
  let b = bytes_of(s);
  return resp_decode(&b, 0);
}

fn kind_of(r: Result[RedisValue, RedisError], k: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: RedisValue = r.value;
  return value_kind(&v) == k;
}

fn text_of(r: Result[RedisValue, RedisError], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: RedisValue = r.value;
  let t = value_text(&v);
  if !t.is_ok {
    return false;
  }
  return streq(t.value, want);
}

fn int_of(r: Result[RedisValue, RedisError], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: RedisValue = r.value;
  let t = value_int(&v);
  if !t.is_ok {
    return false;
  }
  return t.value == want;
}

fn err_of(r: Result[RedisValue, RedisError], kind: Int, code: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: RedisError = r.error;
  return e.kind == kind && e.code == code;
}

fn value_is_nil_of(r: Result[RedisValue, RedisError]) -> Bool {
  if !r.is_ok { return false; }
  let v: RedisValue = r.value;
  return value_is_nil(&v);
}

fn value_is_null_of(r: Result[RedisValue, RedisError]) -> Bool {
  if !r.is_ok { return false; }
  let v: RedisValue = r.value;
  return value_is_null(&v);
}

fn value_maybe_text_of(v: &RedisValue, i: Int) -> Bool {
  let e = value_at(v, i);
  if !e.is_ok { return false; }
  let ev: RedisValue = e.value;
  let m = value_maybe_text(&ev);
  if !m.is_ok { return false; }
  let mt: RedisText = m.value;
  match mt {
    Missing => { return true; },
    Text(_) => { return false; },
  }
}

fn fail_int_of(r: Result[RedisValue, RedisError]) -> Result[Int, RedisError] {
  if !r.is_ok {
    return Err(redis_error(REDIS_ERR_PROTOCOL, 0, "test: decode failed"));
  }
  let v: RedisValue = r.value;
  return value_int(&v);
}

fn fail_text_of(r: Result[RedisValue, RedisError]) -> Result[Str, RedisError] {
  if !r.is_ok {
    return Err(redis_error(REDIS_ERR_PROTOCOL, 0, "test: decode failed"));
  }
  let v: RedisValue = r.value;
  return value_text(&v);
}

fn fail_array_of(r: Result[RedisValue, RedisError]) -> Result[Vec[RedisValue], RedisError] {
  if !r.is_ok {
    return Err(redis_error(REDIS_ERR_PROTOCOL, 0, "test: decode failed"));
  }
  let v: RedisValue = r.value;
  return value_array(&v);
}

fn err_of_kind(r: Result[Int, RedisError], kind: Int) -> Bool {
  if r.is_ok { return false; }
  let e: RedisError = r.error;
  return e.kind == kind;
}

fn err_of_txt_kind(r: Result[Str, RedisError], kind: Int) -> Bool {
  if r.is_ok { return false; }
  let e: RedisError = r.error;
  return e.kind == kind;
}

fn err_of_vals_kind(r: Result[Vec[RedisValue], RedisError], kind: Int) -> Bool {
  if r.is_ok { return false; }
  let e: RedisError = r.error;
  return e.kind == kind;
}

fn err_maybe_of(r: Result[RedisValue, RedisError]) -> Bool {
  if !r.is_ok { return false; }
  let v: RedisValue = r.value;
  let m = value_maybe_text(&v);
  if m.is_ok { return false; }
  let e: RedisError = m.error;
  return e.kind == REDIS_ERR_TYPE;
}

fn maybe_text_of_res(r: Result[RedisValue, RedisError], want: Str) -> Bool {
  if !r.is_ok { return false; }
  let v: RedisValue = r.value;
  let m = value_maybe_text(&v);
  if !m.is_ok { return false; }
  let mt: RedisText = m.value;
  match mt {
    Missing => { return false; },
    Text(s) => { return streq(s, want); },
  }
}

fn arr_copy_ok(r: Result[RedisValue, RedisError]) -> Bool {
  if !r.is_ok { return false; }
  let v: RedisValue = r.value;
  let a = value_array(&v);
  if !a.is_ok { return false; }
  let items: Vec[RedisValue] = a.value;
  return items.len() == 1;
}

// ---------------------------------------------------------------------------
// c1: encode goldens (exact wire bytes)
// ---------------------------------------------------------------------------

fn c1() -> TestResult {
  var ok = true;

  var ping: Vec[Str] = Vec[Str].new();
  ping.push("PING");
  let e1 = resp_encode_command(&ping);
  if !e1.is_ok { ok = false; } else { if !streq(e1.value, "*1\r\n$4\r\nPING\r\n") { ok = false; } }

  var set: Vec[Str] = Vec[Str].new();
  set.push("SET");
  set.push("foo");
  set.push("bar");
  let e2 = resp_encode_command(&set);
  if !e2.is_ok { ok = false; } else { if !streq(e2.value, "*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\nbar\r\n") { ok = false; } }

  // Empty argument is a legal bulk string ($0).
  var echo: Vec[Str] = Vec[Str].new();
  echo.push("ECHO");
  echo.push("");
  let e3 = resp_encode_command(&echo);
  if !e3.is_ok { ok = false; } else { if !streq(e3.value, "*2\r\n$4\r\nECHO\r\n$0\r\n\r\n") { ok = false; } }

  // CRLF inside an argument does not break framing (length-prefixed).
  var raw: Vec[Str] = Vec[Str].new();
  raw.push("ECHO");
  raw.push("a\r\nb");
  let e4 = resp_encode_command(&raw);
  if !e4.is_ok { ok = false; } else { if !streq(e4.value, "*2\r\n$4\r\nECHO\r\n$4\r\na\r\nb\r\n") { ok = false; } }

  // Multi-key form: exact byte length and content.
  var del: Vec[Str] = Vec[Str].new();
  del.push("DEL");
  del.push("k1");
  del.push("k2");
  let e5 = resp_encode_command(&del);
  if !e5.is_ok { ok = false; } else { if !streq(e5.value, "*3\r\n$3\r\nDEL\r\n$2\r\nk1\r\n$2\r\nk2\r\n") { ok = false; } }

  // Empty command is a typed encode error.
  var none: Vec[Str] = Vec[Str].new();
  let e6 = resp_encode_command(&none);
  if e6.is_ok {
    ok = false;
  } else {
    let er: RedisError = e6.error;
    if er.kind != REDIS_ERR_PROTOCOL || er.code != RESP_ERR_EMPTY { ok = false; }
    if !streq(er.message, "redis.resp: empty command (no arguments)") { ok = false; }
  }

  return assert(ok, "codec: encode goldens produce exact wire bytes");
}

// ---------------------------------------------------------------------------
// c2: decode scalars, nulls and consumed counts
// ---------------------------------------------------------------------------

fn c2() -> TestResult {
  var ok = true;

  if !kind_of(dec("+OK\r\n"), REDIS_VALUE_SIMPLE) { ok = false; }
  if !text_of(dec("+PONG\r\n"), "PONG") { ok = false; }
  if !kind_of(dec("-ERR nope\r\n"), REDIS_VALUE_ERROR) { ok = false; }
  let em = dec("-WRONGTYPE bad\r\n");
  if em.is_ok {
    let ev: RedisValue = em.value;
    if !streq(value_error_message(&ev), "WRONGTYPE bad") { ok = false; }
  } else { ok = false; }
  if !int_of(dec(":42\r\n"), 42) { ok = false; }
  if !int_of(dec(":-7\r\n"), -7) { ok = false; }
  if !int_of(dec(":0\r\n"), 0) { ok = false; }
  if !kind_of(dec("$5\r\nhello\r\n"), REDIS_VALUE_BULK) { ok = false; }
  if !text_of(dec("$5\r\nhello\r\n"), "hello") { ok = false; }
  if !text_of(dec("$0\r\n\r\n"), "") { ok = false; }
  if !kind_of(dec("$-1\r\n"), REDIS_VALUE_NIL) { ok = false; }
  if !kind_of(dec("*-1\r\n"), REDIS_VALUE_NULL_ARRAY) { ok = false; }
  if !value_is_nil_of(dec("$-1\r\n")) { ok = false; }
  if !value_is_null_of(dec("*-1\r\n")) { ok = false; }
  if value_is_nil_of(dec("*-1\r\n")) { ok = false; }

  // decode at a non-zero offset and consumed-count reporting.
  let buf = bytes_of("junk*2\r\n$1\r\na\r\n:3\r\n");
  let o = resp_decode_at(&buf, 4);
  match o {
    Done(d) => {
      let used: Int = d.consumed;
      if used != 15 { ok = false; }
      let v: RedisValue = d.value;
      if value_array_len(&v) != 2 { ok = false; }
      let a0 = value_at(&v, 0);
      if !a0.is_ok { ok = false; } else {
        let av: RedisValue = a0.value;
        let at = value_text(&av);
        if !at.is_ok { ok = false; } else { if !streq(at.value, "a") { ok = false; } }
      }
      let a1 = value_at(&v, 1);
      if !a1.is_ok { ok = false; } else {
        let av: RedisValue = a1.value;
        let ai = value_int(&av);
        if !ai.is_ok { ok = false; } else { if ai.value != 3 { ok = false; } }
      }
    },
    NeedMore => { ok = false; },
    Bad(e) => { ok = false; },
  };

  // Decoding at a bad offset is a typed error, not a crash.
  let e = resp_decode(&buf, -1);
  if e.is_ok { ok = false; } else {
    let er: RedisError = e.error;
    if er.kind != REDIS_ERR_PROTOCOL || er.code != RESP_ERR_OFFSET { ok = false; }
  }

  return assert(ok, "codec: decode scalars, nulls and consumed counts");
}

// ---------------------------------------------------------------------------
// c3: nested arrays and mixed payloads
// ---------------------------------------------------------------------------

fn c3() -> TestResult {
  var ok = true;

  let r = dec("*1\r\n*2\r\n+hi\r\n$2\r\nok\r\n");
  if !kind_of(r, REDIS_VALUE_ARRAY) { ok = false; }
  if ok {
    let v: RedisValue = r.value;
    if value_array_len(&v) != 1 { ok = false; }
    let inner = value_at(&v, 0);
    if !inner.is_ok { ok = false; } else {
      let iv: RedisValue = inner.value;
      if value_kind(&iv) != REDIS_VALUE_ARRAY { ok = false; }
      if value_array_len(&iv) != 2 { ok = false; }
      let i0 = value_at(&iv, 0);
      if !i0.is_ok { ok = false; } else {
        let x: RedisValue = i0.value;
        let xt = value_text(&x);
        if !xt.is_ok { ok = false; } else { if !streq(xt.value, "hi") { ok = false; } }
      }
      let i1 = value_at(&iv, 1);
      if !i1.is_ok { ok = false; } else {
        let x: RedisValue = i1.value;
        let xt = value_text(&x);
        if !xt.is_ok { ok = false; } else { if !streq(xt.value, "ok") { ok = false; } }
      }
    }
  }

  let r2 = dec("*3\r\n$1\r\na\r\n$-1\r\n*0\r\n");
  if !kind_of(r2, REDIS_VALUE_ARRAY) { ok = false; }
  if ok {
    let v2: RedisValue = r2.value;
    if value_array_len(&v2) != 3 { ok = false; }
    let m = value_maybe_text_of(&v2, 1);
    if !m { ok = false; }
    let last = value_at(&v2, 2);
    if !last.is_ok { ok = false; } else {
      let lv: RedisValue = last.value;
      if value_array_len(&lv) != 0 { ok = false; }
    }
  }

  return assert(ok, "codec: nested arrays and mixed payloads");
}

// ---------------------------------------------------------------------------
// c4: truncated buffers are typed protocol errors
// ---------------------------------------------------------------------------

fn c4() -> TestResult {
  var ok = true;
  if !err_of(dec("+OK"), REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }
  if !err_of(dec("+OK\r"), REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }
  if !err_of(dec("$5\r\nabc"), REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }
  if !err_of(dec("$5\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }
  if !err_of(dec("*2\r\n$1\r\na\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }
  if !err_of(dec("*2\r\n$1\r\na"), REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }
  if !err_of(dec(""), REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }
  if !err_of(dec("$"), REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }

  // A partial element stream reports NeedMore, not a value.
  let buf = bytes_of("*2\r\n$1\r\na\r\n");
  let o = resp_decode_at(&buf, 0);
  match o {
    Done(d) => { ok = false; },
    NeedMore => {},
    Bad(e) => { ok = false; },
  };
  return assert(ok, "codec: truncated replies are typed protocol errors (RESP_ERR_TRUNCATED)");
}

// ---------------------------------------------------------------------------
// c5: garbage input is rejected with specific codes
// ---------------------------------------------------------------------------

fn c5() -> TestResult {
  var ok = true;
  if !err_of(dec("?oops\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_TYPE) { ok = false; }
  if !err_of(dec("+OK\n"), REDIS_ERR_PROTOCOL, RESP_ERR_TERMINATOR) { ok = false; }
  if !err_of(dec("$5\r\nabcdeXX"), REDIS_ERR_PROTOCOL, RESP_ERR_TERMINATOR) { ok = false; }
  if !err_of(dec(":12x\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_INTEGER) { ok = false; }
  if !err_of(dec(":-\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_INTEGER) { ok = false; }
  if !err_of(dec("$x\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_INTEGER) { ok = false; }
  if !err_of(dec("$-2\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_LENGTH) { ok = false; }
  if !err_of(dec("*-3\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_LENGTH) { ok = false; }
  if !err_of(dec(":99999999999999999999\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_INTEGER) { ok = false; }
  return assert(ok, "codec: garbage input is rejected with specific protocol codes");
}

// ---------------------------------------------------------------------------
// c6: hard caps (size, array length, depth)
// ---------------------------------------------------------------------------

fn c6() -> TestResult {
  var ok = true;

  // Declared bulk length above the cap is rejected before allocation.
  if !err_of(dec("$67108865\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_SIZE) { ok = false; }
  // Declared array length above the element cap.
  if !err_of(dec("*1048577\r\n"), REDIS_ERR_PROTOCOL, RESP_ERR_SIZE) { ok = false; }

  // Depth cap: build 40 nested single-element arrays; must fail with DEPTH.
  var deep: Str = "";
  var i = 0;
  while i < 40 {
    deep = deep + "*1\r\n";
    i = i + 1;
  }
  deep = deep + "+x\r\n";
  if !err_of(dec(deep), REDIS_ERR_PROTOCOL, RESP_ERR_DEPTH) { ok = false; }

  // Shallow nesting (under the cap) still decodes.
  var shallow: Str = "";
  i = 0;
  while i < 8 {
    shallow = shallow + "*1\r\n";
    i = i + 1;
  }
  shallow = shallow + ":9\r\n";
  let r = dec(shallow);
  if !kind_of(r, REDIS_VALUE_ARRAY) { ok = false; }

  return assert(ok, "codec: hard caps on bulk size, array length and nesting depth");
}

// ---------------------------------------------------------------------------
// c7: typed value accessors, including the wrong-type error path
// ---------------------------------------------------------------------------

fn c7() -> TestResult {
  var ok = true;

  let b = dec("$3\r\nabc\r\n");
  if !kind_of(b, REDIS_VALUE_BULK) { ok = false; }
  if !text_of(b, "abc") { ok = false; }
  // Wrong-type accessor: integer of a bulk string.
  if !err_of_kind(fail_int_of(b), REDIS_ERR_TYPE) { ok = false; }
  // A bulk string IS optional text (not an error): it maps to Text "abc".
  if !maybe_text_of_res(b, "abc") { ok = false; }

  let i = dec(":5\r\n");
  if !int_of(i, 5) { ok = false; }
  if !err_of_txt_kind(fail_text_of(i), REDIS_ERR_TYPE) { ok = false; }
  if !err_maybe_of(i) { ok = false; }
  if !err_of_vals_kind(fail_array_of(i), REDIS_ERR_TYPE) { ok = false; }

  let n = dec("$-1\r\n");
  if !err_of_kind(fail_int_of(n), REDIS_ERR_TYPE) { ok = false; }
  let nt = dec("$-1\r\n");
  if nt.is_ok {
    let nv: RedisValue = nt.value;
    let maybe = value_maybe_text(&nv);
    if !maybe.is_ok { ok = false; } else {
      let mt: RedisText = maybe.value;
      match mt {
        Missing => {},
        Text(_) => { ok = false; },
      };
    }
  } else { ok = false; }

  // Out-of-range array access is a typed error, not a crash.
  let arr = dec("*1\r\n:1\r\n");
  if arr.is_ok {
    let av: RedisValue = arr.value;
    let oob = value_at(&av, 5);
    if oob.is_ok { ok = false; } else {
      let e: RedisError = oob.error;
      if e.kind != REDIS_ERR_TYPE { ok = false; }
    }
  } else { ok = false; }

  // value_array copies the whole array.
  if !arr_copy_ok(arr) { ok = false; }

  return assert(ok, "codec: typed accessors and the wrong-type error path");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = c1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = c2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = c3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = c4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = c5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = c6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = c7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  return failed;
}
