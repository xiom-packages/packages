// XIOM -- xiom.cloudlog conformance tests (27 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.cloudlog model against SPEC.md:
// level tables and events, key=value and JSON-ish encode/decode with
// escaping and the exact error catalog, ingest batching with sequence
// watermarks and flush policies, the stream blob and tail consumer with
// checkpoint/replay semantics, the retention store with segment stats,
// retention and compaction policies, and the predicate-tree search with
// deterministic pagination. The final check repeats whole pipelines to pin
// determinism.
//
// All Str equality goes through str_compare: BUG-17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// string comparison below is routed through streq. Vec element reads are
// bound to typed locals. Test dispatch is direct t1()..t27() calls (indexed
// Vec[fn] dispatch miscompiles on the installed compiler).

module cloudlog_tests
use xiom.io; use xiom.test; use xiom.cloudlog;
use xiom.string; use xiom.string.builder; use xiom.string.compare;
use xiom.convert.int;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_eq(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn kv_err(line: Str, want: Str) -> Bool {
  let r = cl_kv_decode(line);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn json_err(text: Str, want: Str) -> Bool {
  let r = cl_json_decode(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// "x" + 0x01 + "y", built through bytes (control bytes cannot be literals).
fn ctrl_msg() -> Str {
  var sb = Vec[UInt8].new();
  sb.push(120u8);
  sb.push(1u8);
  sb.push(121u8);
  return builder.sb_to_str(&sb);
}

fn t1() -> TestResult {
  var ok = streq(cl_level_name(0), "trace");
  if !streq(cl_level_name(1), "debug") { ok = false; }
  if !streq(cl_level_name(2), "info") { ok = false; }
  if !streq(cl_level_name(3), "warn") { ok = false; }
  if !streq(cl_level_name(4), "error") { ok = false; }
  if !streq(cl_level_name(5), "fatal") { ok = false; }
  if !streq(cl_level_name(6), "") { ok = false; }
  if !cl_level_valid(0) { ok = false; }
  if !cl_level_valid(5) { ok = false; }
  if cl_level_valid(-1) { ok = false; }
  if cl_level_valid(6) { ok = false; }
  var i = 0;
  while i <= 5 {
    let rc = cl_level_code(cl_level_name(i));
    if !rc.is_ok { ok = false; }
    elif rc.value != i { ok = false; }
    i = i + 1;
  }
  let bad = cl_level_code("loud");
  if bad.is_ok { ok = false; }
  elif !streq(bad.error, "cloudlog: unknown level: loud") { ok = false; }
  return assert(ok, "level name/code table and bounds 0..5");
}

fn t2() -> TestResult {
  var e = cl_event_new(1000, 4, "boom");
  var ok = e.time_ms == 1000 && e.level == 4 && e.severity == 4;
  if !streq(e.msg, "boom") { ok = false; }
  if !cl_event_set(&mut e, "user", "alice") { ok = false; }
  if !cl_event_set(&mut e, "retry", "3") { ok = false; }
  if cl_event_set(&mut e, "bad key", "x") { ok = false; }
  if cl_event_key_count(&e) != 2 { ok = false; }
  if !streq(cl_event_key(&e, 0), "user") { ok = false; }
  if !streq(cl_event_val(&e, 1), "3") { ok = false; }
  if !cl_event_has_key(&e, "user") { ok = false; }
  if cl_event_has_key(&e, "nope") { ok = false; }
  if !opt_eq(cl_event_get(&e, "user"), "alice") { ok = false; }
  if !opt_none(cl_event_get(&e, "nope")) { ok = false; }
  let full = cl_event_new_full(2, 3, 5, "x");
  if full.severity != 5 { ok = false; }
  return assert(ok, "event construction, attribute set/get and lookups");
}

fn t3() -> TestResult {
  var e = cl_event_new(1000, 2, "hello world");
  let set1 = cl_event_set(&mut e, "user", "alice");
  let want = "time=1000 level=info severity=2 msg=\"hello world\" user=\"alice\"";
  return assert(set1 && streq(cl_kv_encode(&e), want), "kv encode canonical line");
}

fn t4() -> TestResult {
  var e = cl_event_new(42, 4, "a\"b\\c\nd\te");
  let set1 = cl_event_set(&mut e, "path", "C:\\tmp\\x");
  let set2 = cl_event_set(&mut e, "q", "he said \"hi\"");
  let line = cl_kv_encode(&e);
  var ok = set1 && set2;
  if !cl_text_contains(line, "\\n") { ok = false; }
  let r = cl_kv_decode(line);
  match r {
    Ok(d) => {
      if d.time_ms != 42 { ok = false; }
      if d.level != 4 { ok = false; }
      if d.severity != 4 { ok = false; }
      if !streq(d.msg, "a\"b\\c\nd\te") { ok = false; }
      if cl_event_key_count(&d) != 2 { ok = false; }
      if !opt_eq(cl_event_get(&d, "path"), "C:\\tmp\\x") { ok = false; }
      if !opt_eq(cl_event_get(&d, "q"), "he said \"hi\"") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "kv escape round-trip for quote, backslash, newline, tab");
}

fn t5() -> TestResult {
  var ok = kv_err("", "cloudlog: empty line at 0");
  if !kv_err("level=info", "cloudlog: missing time at 10") { ok = false; }
  if !kv_err("time=5 level=loud", "cloudlog: unknown level: loud at 13") { ok = false; }
  if !kv_err("time=1 time=2 level=info", "cloudlog: duplicate key: time at 7") { ok = false; }
  if !kv_err("time=1 level=info msg=\"abc", "cloudlog: unterminated string at 26") { ok = false; }
  if !kv_err("time=1 msg=\"a\"", "cloudlog: missing level at 14") { ok = false; }
  if !kv_err("time=1 level=info msg=\"a\\qb\"", "cloudlog: bad escape at 24") { ok = false; }
  if !kv_err("time=1 level=info severity=9", "cloudlog: bad severity at 27") { ok = false; }
  if !kv_err("time=1 level=info x=1 x=2", "cloudlog: duplicate key: x at 22") { ok = false; }
  return assert(ok, "kv decode error catalog with byte offsets");
}

fn t6() -> TestResult {
  let r = cl_kv_decode("time=-5 level=warn msg=bare-value host=node1");
  var ok = false;
  match r {
    Ok(d) => {
      ok = d.time_ms == -5 && d.level == 3 && d.severity == 3;
      if !streq(d.msg, "bare-value") { ok = false; }
      if !streq(cl_event_key(&d, 0), "host") { ok = false; }
      if !streq(cl_event_val(&d, 0), "node1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = cl_kv_decode("  time=7 severity=5 level=fatal msg=\"x\"  ");
  match r2 {
    Ok(d2) => {
      if d2.severity != 5 { ok = false; }
      if d2.level != 5 { ok = false; }
      if !streq(d2.msg, "x") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "kv bare values, padding, default and explicit severity");
}

fn t7() -> TestResult {
  var e = cl_event_new(1000, 2, "hi");
  let s = cl_event_set(&mut e, "k", "v");
  let want = "{\"time\":1000,\"level\":\"info\",\"severity\":2,\"msg\":\"hi\",\"k\":\"v\"}";
  return assert(s && streq(cl_json_encode(&e), want), "json encode canonical object");
}

fn t8() -> TestResult {
  let want_msg = "a\"b\\c\nd\te" + ctrl_msg();
  var e = cl_event_new(9, 4, want_msg);
  let line = cl_json_encode(&e);
  var ok = cl_text_contains(line, "\\u0001");
  let r = cl_json_decode(line);
  match r {
    Ok(d) => {
      if !streq(d.msg, want_msg) { ok = false; }
      if d.time_ms != 9 || d.level != 4 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let u = cl_json_decode("{\"time\":1,\"level\":\"info\",\"msg\":\"\\u0041\"}");
  match u {
    Ok(d2) => {
      if !streq(d2.msg, "A") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "json escape round-trip and \\u0041 decode");
}

fn t9() -> TestResult {
  var ok = json_err("", "cloudlog: empty document at 0");
  if !json_err("5", "cloudlog: expected object at 0") { ok = false; }
  if !json_err("{\"time\":1,\"level\":\"info\",\"k\":{\"a\":1}}", "cloudlog: unsupported value at 29") { ok = false; }
  if !json_err("{\"time\":1,\"level\":\"info}", "cloudlog: unterminated string at 24") { ok = false; }
  if !json_err("{\"time\":1,\"level\":\"info\",\"msg\":\"a\\qb\"}", "cloudlog: bad escape at 33") { ok = false; }
  if !json_err("{\"time\":1,\"level\":\"info\",\"msg\":\"\\u0080\"}", "cloudlog: unsupported unicode escape at 32") { ok = false; }
  if !json_err("{\"time\":1,\"level\":\"info\"} x", "cloudlog: trailing data at 26") { ok = false; }
  if !json_err("{\"time\":1,\"time\":2,\"level\":\"info\"}", "cloudlog: duplicate key: time at 10") { ok = false; }
  if !json_err("{\"time\" 1}", "cloudlog: expected colon at 8") { ok = false; }
  return assert(ok, "json decode error catalog with byte offsets");
}

fn t10() -> TestResult {
  let r = cl_json_decode("{\"time\":10,\"level\":\"warn\",\"retry\":3,\"cached\":true,\"msg\":\"m\"}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = d.time_ms == 10 && d.level == 3 && d.severity == 3;
      if !streq(d.msg, "m") { ok = false; }
      if !opt_eq(cl_event_get(&d, "retry"), "3") { ok = false; }
      if !opt_eq(cl_event_get(&d, "cached"), "true") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !json_err("{\"time\":1,\"level\":\"info\",\"msg\":5}", "cloudlog: bad string at 31") { ok = false; }
  if !json_err("{\"time\":1,\"level\":4}", "cloudlog: bad level at 18") { ok = false; }
  if !json_err("{\"time\":1,\"level\":\"info\",\"severity\":9}", "cloudlog: bad severity at 36") { ok = false; }
  return assert(ok, "json value types and field type validation");
}

fn t11() -> TestResult {
  var ing = cl_ingest_new(10);
  let c0 = cl_ingest_accept(&mut ing, 10, 100, "a");
  let c1 = cl_ingest_accept(&mut ing, 11, 200, "bb");
  let c2 = cl_ingest_accept(&mut ing, 12, 300, "ccc");
  var ok = c0 == 0 && c1 == 0 && c2 == 0;
  if cl_ingest_watermark(&ing) != 12 { ok = false; }
  if cl_ingest_seen_max(&ing) != 12 { ok = false; }
  if cl_ingest_pending(&ing) != 0 { ok = false; }
  if cl_ingest_count(&ing) != 3 { ok = false; }
  if cl_ingest_accepted(&ing) != 3 { ok = false; }
  if cl_ingest_total_bytes(&ing) != 6 { ok = false; }
  if cl_ingest_first_time(&ing) != 100 { ok = false; }
  if cl_ingest_last_time(&ing) != 300 { ok = false; }
  if cl_ingest_age_ms(&ing, 350) != 250 { ok = false; }
  if cl_ingest_duplicates(&ing) != 0 { ok = false; }
  if cl_ingest_gap_events(&ing) != 0 { ok = false; }
  return assert(ok, "ingest in-order accept, watermark and byte accounting");
}

fn t12() -> TestResult {
  var ing = cl_ingest_new(0);
  let g0 = cl_ingest_accept(&mut ing, 2, 200, "c");
  var ok = g0 == 1;
  if cl_ingest_watermark(&ing) != -1 { ok = false; }
  if cl_ingest_seen_max(&ing) != 2 { ok = false; }
  if cl_ingest_pending(&ing) != 3 { ok = false; }
  let a0 = cl_ingest_accept(&mut ing, 0, 100, "a");
  let a1 = cl_ingest_accept(&mut ing, 1, 150, "b");
  if a0 != 0 || a1 != 0 { ok = false; }
  if cl_ingest_watermark(&ing) != 2 { ok = false; }
  if cl_ingest_pending(&ing) != 0 { ok = false; }
  let dup = cl_ingest_accept(&mut ing, 1, 150, "b2");
  if dup != 2 { ok = false; }
  if cl_ingest_duplicates(&ing) != 1 { ok = false; }
  let emp = cl_ingest_accept(&mut ing, 3, 300, "");
  if emp != 3 { ok = false; }
  let a3 = cl_ingest_accept(&mut ing, 3, 300, "d");
  if a3 != 0 || cl_ingest_watermark(&ing) != 3 { ok = false; }
  if cl_ingest_count(&ing) != 4 { ok = false; }
  if cl_ingest_accepted(&ing) != 4 { ok = false; }
  if cl_ingest_gap_events(&ing) != 1 { ok = false; }
  return assert(ok, "sequence gaps, watermark advance, duplicates, empty rejects");
}

fn t13() -> TestResult {
  var ing = cl_ingest_new(0);
  let empty_pol = CloudFlushPolicy{ max_events: 2; max_bytes: 100; max_age_ms: 1000; };
  let p0 = cl_ingest_plan_flush(&ing, &empty_pol, 100);
  var ok = !p0.should && p0.reason == 0 && p0.count == 0;
  cl_ingest_accept(&mut ing, 0, 100, "aa");
  cl_ingest_accept(&mut ing, 1, 110, "bb");
  let p1 = cl_ingest_plan_flush(&ing, &empty_pol, 115);
  if !p1.should || p1.reason != 1 { ok = false; }
  if p1.count != 2 || p1.bytes != 4 { ok = false; }
  if p1.seq_first != 0 || p1.seq_last != 1 { ok = false; }
  if p1.age_ms != 15 { ok = false; }
  let bytes_pol = CloudFlushPolicy{ max_events: 0; max_bytes: 4; max_age_ms: 0; };
  let p2 = cl_ingest_plan_flush(&ing, &bytes_pol, 115);
  if p2.reason != 2 { ok = false; }
  let age_pol = CloudFlushPolicy{ max_events: 0; max_bytes: 0; max_age_ms: 10; };
  let p3 = cl_ingest_plan_flush(&ing, &age_pol, 115);
  if p3.reason != 3 { ok = false; }
  let all_pol = CloudFlushPolicy{ max_events: 1; max_bytes: 1; max_age_ms: 1; };
  let p4 = cl_ingest_plan_flush(&ing, &all_pol, 115);
  if p4.reason != 1 { ok = false; }
  return assert(ok, "flush policies count/bytes/age triggers and precedence");
}

fn t14() -> TestResult {
  var ing = cl_ingest_new(5);
  cl_ingest_accept(&mut ing, 5, 100, "aa");
  cl_ingest_accept(&mut ing, 6, 150, "bbb");
  let pol = CloudFlushPolicy{ max_events: 0; max_bytes: 0; max_age_ms: 0; };
  let f = cl_ingest_flush(&mut ing, &pol, 200);
  var ok = f.should && f.reason == 4 && f.count == 2 && f.bytes == 5;
  if cl_ingest_count(&ing) != 0 { ok = false; }
  if cl_ingest_total_bytes(&ing) != 0 { ok = false; }
  if cl_ingest_watermark(&ing) != 6 { ok = false; }
  if cl_ingest_accepted(&ing) != 2 { ok = false; }
  let f2 = cl_ingest_flush(&mut ing, &pol, 200);
  if f2.should || f2.reason != 0 { ok = false; }
  return assert(ok, "explicit flush clears content, keeps watermark/counters");
}

fn t15() -> TestResult {
  var st = cl_stream_new();
  let i0 = cl_stream_append(&mut st, 10, "a");
  let i1 = cl_stream_append(&mut st, 20, "bc");
  let i2 = cl_stream_append(&mut st, 30, "d");
  var ok = i0 == 0 && i1 == 1 && i2 == 2;
  if cl_stream_count(&st) != 3 { ok = false; }
  if !streq(cl_stream_line(&st, 1), "bc") { ok = false; }
  if cl_stream_ts(&st, 2) != 30 { ok = false; }
  if cl_stream_byte_len(&st) != 7 { ok = false; }
  if cl_stream_span_ms(&st) != 20 { ok = false; }
  if cl_stream_append(&mut st, 40, "x\ny") != -1 { ok = false; }
  if cl_stream_append(&mut st, 40, "") != -1 { ok = false; }
  if !streq(cl_stream_line(&st, 9), "") { ok = false; }
  return assert(ok, "stream append, record slicing and framing rejects");
}

fn t16() -> TestResult {
  var st = cl_stream_new();
  cl_stream_append(&mut st, 10, "a");
  cl_stream_append(&mut st, 20, "b");
  cl_stream_append(&mut st, 30, "c");
  var t = cl_tail_new(0);
  let r1 = cl_tail_read(&st, &t, 2);
  var ok = r1.count == 2 && r1.from == 0 && r1.next_cursor == 2;
  if r1.idx.len() != 2 { ok = false; }
  let l0: Str = r1.lines[0];
  if !streq(l0, "a") { ok = false; }
  let c0 = cl_tail_commit(&mut t, r1.next_cursor);
  if !c0 { ok = false; }
  if cl_tail_cursor(&t) != 2 || cl_tail_acked(&t) != 2 { ok = false; }
  let r2 = cl_tail_read(&st, &t, 5);
  if r2.count != 1 || r2.next_cursor != 3 { ok = false; }
  let c1 = cl_tail_commit(&mut t, r2.next_cursor);
  let r3 = cl_tail_read(&st, &t, 5);
  if !c1 || r3.count != 0 || r3.next_cursor != 3 { ok = false; }
  if !cl_tail_ok(&st, &t) { ok = false; }
  return assert(ok, "tail read cursor/commit and end-of-stream");
}

fn t17() -> TestResult {
  var st = cl_stream_new();
  cl_stream_append(&mut st, 1, "a");
  cl_stream_append(&mut st, 2, "b");
  cl_stream_append(&mut st, 3, "c");
  var t = cl_tail_new(1);
  var ok = cl_tail_cursor(&t) == 1;
  let c = cl_tail_seek(&mut t, 0);
  if c != 1 { ok = false; }
  let c2 = cl_tail_seek(&mut t, 2);
  if c2 != 2 { ok = false; }
  if cl_tail_retained_from(&t) != 1 { ok = false; }
  let fl = cl_tail_set_retained(&mut t, 2);
  if fl != 2 { ok = false; }
  let r = cl_tail_read(&st, &t, 5);
  if r.truncated || r.from != 2 || r.count != 1 { ok = false; }
  let c3 = cl_tail_commit(&mut t, r.next_cursor);
  if !c3 || !cl_tail_ok(&st, &t) { ok = false; }
  var t2 = cl_tail_new(2);
  cl_tail_seek(&mut t2, 2);
  let fl2 = cl_tail_set_retained(&mut t2, 3);
  if fl2 != 3 { ok = false; }
  let r2 = cl_tail_read(&st, &t2, 5);
  if !r2.truncated || r2.from != 3 || r2.count != 0 { ok = false; }
  if cl_tail_ok(&st, &t2) { ok = false; }
  let c4 = cl_tail_commit(&mut t2, r2.next_cursor);
  if !c4 || !cl_tail_ok(&st, &t2) { ok = false; }
  let c5 = cl_tail_seek(&mut t2, 0);
  if c5 != 3 { ok = false; }
  return assert(ok, "tail retention floor, truncated read and seek clamp");
}

fn t18() -> TestResult {
  var st = cl_stream_new();
  cl_stream_append(&mut st, 10, "r0");
  cl_stream_append(&mut st, 20, "r1");
  cl_stream_append(&mut st, 30, "r2");
  var t = cl_tail_new(0);
  let r1 = cl_tail_read(&st, &t, 2);
  let c1 = cl_tail_commit(&mut t, r1.next_cursor);
  var ok = c1 && cl_tail_acked(&t) == 2 && cl_tail_cursor(&t) == 2;
  let r2 = cl_tail_read(&st, &t, 2);
  if r2.count != 1 { ok = false; }
  let s2 = cl_tail_seek(&mut t, r2.next_cursor);
  if s2 != 3 { ok = false; }
  if cl_tail_lag(&t) != 1 { ok = false; }
  let rp = cl_tail_replay(&st, &t, 5);
  if !rp.replayed || rp.count != 1 || rp.from != 2 { ok = false; }
  let c2 = cl_tail_commit(&mut t, rp.next_cursor);
  if !c2 { ok = false; }
  if cl_tail_lag(&t) != 0 { ok = false; }
  if !cl_tail_ok(&st, &t) { ok = false; }
  let c3 = cl_tail_commit(&mut t, 1);
  if c3 { ok = false; }
  return assert(ok, "at-least-once replay from checkpoint, monotonic commit");
}

fn t19() -> TestResult {
  var s = cl_store_new(2);
  let i0 = cl_store_append(&mut s, 100, 10);
  let i1 = cl_store_append(&mut s, 110, 20);
  let i2 = cl_store_append(&mut s, 120, 30);
  let i3 = cl_store_append(&mut s, 130, 40);
  let i4 = cl_store_append(&mut s, 140, 50);
  var ok = i0 == 0 && i1 == 0 && i2 == 1 && i3 == 1 && i4 == 2;
  if cl_store_segment_count(&s) != 3 { ok = false; }
  if cl_store_live_count(&s) != 3 { ok = false; }
  if cl_store_total_bytes(&s) != 150 { ok = false; }
  if cl_store_total_events(&s) != 5 { ok = false; }
  if cl_store_next_off(&s) != 150 { ok = false; }
  if cl_store_segment_state(&s, 0) != 2 { ok = false; }
  if cl_store_segment_state(&s, 2) != 1 { ok = false; }
  if cl_store_segment_bytes(&s, 0) != 30 { ok = false; }
  if cl_store_segment_events(&s, 1) != 2 { ok = false; }
  if cl_store_segment_span_ms(&s, 0) != 10 { ok = false; }
  if cl_store_oldest_time(&s) != 100 { ok = false; }
  if cl_store_newest_time(&s) != 140 { ok = false; }
  if cl_store_append(&mut s, 150, 0) != -1 { ok = false; }
  return assert(ok, "store segment roll, states and per-segment stats");
}

fn t20() -> TestResult {
  var s = cl_store_new(10);
  cl_store_append(&mut s, 10, 5);
  let si = cl_store_seal(&mut s);
  var ok = si == 0 && cl_store_segment_state(&s, 0) == 2;
  if cl_store_seal(&mut s) != -1 { ok = false; }
  if cl_store_segment_to_off(&s, 0) != 5 { ok = false; }
  if cl_store_segment_from_off(&s, 0) != 0 { ok = false; }
  if cl_store_segment_from_time(&s, 0) != 10 { ok = false; }
  if cl_store_segment_to_time(&s, 0) != 10 { ok = false; }
  if cl_store_segment_state(&s, 9) != -1 { ok = false; }
  if cl_store_segment_bytes(&s, 9) != 0 { ok = false; }
  return assert(ok, "store seal and offset/time accessors");
}

fn t21() -> TestResult {
  var s = cl_store_new(1);
  cl_store_append(&mut s, 100, 100);
  cl_store_append(&mut s, 200, 100);
  cl_store_append(&mut s, 300, 100);
  cl_store_append(&mut s, 400, 100);
  cl_store_append(&mut s, 500, 100);
  let pol = CloudStorePolicy{ max_bytes: 150; max_age_ms: 0; max_segments: 0; max_events: 0; compact_at: 0; compact_to: 0; };
  let r = cl_store_apply_retention(&mut s, &pol, 1000);
  var ok = r.dropped == 4 && r.dropped_bytes == 400 && r.reason == 1;
  if r.keep_from_off != 400 { ok = false; }
  if cl_store_live_count(&s) != 1 { ok = false; }
  if cl_store_total_bytes(&s) != 100 { ok = false; }
  if cl_store_dropped_segments(&s) != 4 { ok = false; }
  if cl_store_dropped_bytes(&s) != 400 { ok = false; }
  if cl_store_segment_state(&s, 0) != 0 { ok = false; }
  return assert(ok, "retention bytes policy drops oldest, keeps newest");
}

fn t22() -> TestResult {
  var s = cl_store_new(1);
  cl_store_append(&mut s, 100, 10);
  cl_store_append(&mut s, 200, 10);
  cl_store_append(&mut s, 300, 10);
  cl_store_append(&mut s, 400, 10);
  let age_pol = CloudStorePolicy{ max_bytes: 0; max_age_ms: 700; max_segments: 0; max_events: 0; compact_at: 0; compact_to: 0; };
  let r1 = cl_store_apply_retention(&mut s, &age_pol, 1000);
  var ok = r1.dropped == 2 && r1.reason == 2 && cl_store_live_count(&s) == 2;
  let seg_pol = CloudStorePolicy{ max_bytes: 0; max_age_ms: 0; max_segments: 1; max_events: 0; compact_at: 0; compact_to: 0; };
  let r2 = cl_store_apply_retention(&mut s, &seg_pol, 1000);
  if r2.dropped != 1 || r2.reason != 3 { ok = false; }
  if cl_store_live_count(&s) != 1 { ok = false; }
  var s2 = cl_store_new(1);
  cl_store_append(&mut s2, 1, 10);
  cl_store_append(&mut s2, 2, 10);
  cl_store_append(&mut s2, 3, 10);
  cl_store_append(&mut s2, 4, 10);
  cl_store_append(&mut s2, 5, 10);
  let ev_pol = CloudStorePolicy{ max_bytes: 0; max_age_ms: 0; max_segments: 0; max_events: 2; compact_at: 0; compact_to: 0; };
  let r3 = cl_store_apply_retention(&mut s2, &ev_pol, 1000);
  if r3.dropped != 3 || r3.reason != 4 { ok = false; }
  if cl_store_total_events(&s2) != 2 { ok = false; }
  if cl_store_live_count(&s2) != 2 { ok = false; }
  return assert(ok, "retention age/segments/events reasons and floors");
}

fn t23() -> TestResult {
  var s = cl_store_new(1);
  cl_store_append(&mut s, 100, 10);
  cl_store_append(&mut s, 200, 10);
  cl_store_append(&mut s, 300, 10);
  cl_store_append(&mut s, 400, 10);
  let pol = CloudStorePolicy{ max_bytes: 0; max_age_ms: 0; max_segments: 0; max_events: 0; compact_at: 2; compact_to: 1; };
  var ok = cl_store_compact_due(&s, &pol);
  let merges = cl_store_compact(&mut s, 2);
  if merges != 2 { ok = false; }
  if cl_store_live_count(&s) != 2 { ok = false; }
  if cl_store_total_bytes(&s) != 40 { ok = false; }
  if cl_store_total_events(&s) != 4 { ok = false; }
  if cl_store_compacted_segments(&s) != 2 { ok = false; }
  if cl_store_dropped_segments(&s) != 0 { ok = false; }
  if cl_store_segment_bytes(&s, 0) != 30 { ok = false; }
  if cl_store_segment_events(&s, 0) != 3 { ok = false; }
  if cl_store_segment_to_off(&s, 0) != 30 { ok = false; }
  if cl_store_segment_from_time(&s, 0) != 100 { ok = false; }
  if cl_store_segment_to_time(&s, 0) != 300 { ok = false; }
  if cl_store_compact_due(&s, &pol) { ok = false; }
  return assert(ok, "store compaction merges oldest segments, keeps totals");
}

fn t24() -> TestResult {
  var l = cl_log_new();
  let r0 = cl_log_add(&mut l, 100, 2, 2, "boot complete");
  let r1 = cl_log_add(&mut l, 200, 4, 4, "db timeout");
  let r2 = cl_log_add(&mut l, 300, 3, 3, "db slow");
  let r3 = cl_log_add(&mut l, 400, 4, 5, "disk failure");
  let r4 = cl_log_add(&mut l, 500, 2, 2, "db recovered");
  cl_log_add_kv(&mut l, r0, "host", "a");
  cl_log_add_kv(&mut l, r1, "host", "a");
  cl_log_add_kv(&mut l, r2, "host", "b");
  cl_log_add_kv(&mut l, r3, "host", "b");
  var p = cl_pred_new();
  let n1 = cl_pred_level(&mut p, 4);
  let n2 = cl_pred_msg_contains(&mut p, "db");
  let n3 = cl_pred_or(&mut p, n1, n2);
  let n4 = cl_pred_sev_ge(&mut p, 4);
  let root = cl_pred_and(&mut p, n3, n4);
  var ok = cl_pred_node_count(&p) == 5;
  if cl_pred_op(&p, root) != 2 { ok = false; }
  if !cl_pred_eval(&p, &l, r1, root) { ok = false; }
  if !cl_pred_eval(&p, &l, r3, root) { ok = false; }
  if cl_pred_eval(&p, &l, r2, root) { ok = false; }
  if cl_pred_eval(&p, &l, r4, root) { ok = false; }
  if cl_pred_eval(&p, &l, 99, root) { ok = false; }
  let tr = cl_pred_time_range(&mut p, 150, 450);
  if !cl_pred_eval(&p, &l, r1, tr) { ok = false; }
  if cl_pred_eval(&p, &l, r0, tr) { ok = false; }
  let k = cl_pred_key_eq(&mut p, "host", "b");
  if !cl_pred_eval(&p, &l, r3, k) { ok = false; }
  if cl_pred_eval(&p, &l, r1, k) { ok = false; }
  let nk = cl_pred_not(&mut p, k);
  if cl_pred_eval(&p, &l, r2, nk) { ok = false; }
  if !cl_pred_eval(&p, &l, r4, nk) { ok = false; }
  if !opt_eq(cl_log_key_get(&l, r2, "host"), "b") { ok = false; }
  if cl_log_count(&l) != 5 { ok = false; }
  if cl_log_time(&l, r3) != 400 || cl_log_level(&l, r3) != 4 { ok = false; }
  return assert(ok, "predicate tree eval: and/or/not, level, sev, msg, key, time");
}

fn t25() -> TestResult {
  var l = cl_log_new();
  var i = 0;
  while i < 6 {
    cl_log_add(&mut l, 100 + i * 100, 2, 2, "m");
    i = i + 1;
  }
  var p = cl_pred_new();
  cl_pred_const(&mut p, true);
  let pg1 = cl_search(&l, &p, 0, 1000, 0, 2);
  var ok = pg1.count == 2 && pg1.matched_total == 6 && pg1.next_start == 2 && pg1.scanned == 6;
  if pg1.hits.len() != 2 { ok = false; }
  let h0: Int = pg1.hits[0];
  let h1: Int = pg1.hits[1];
  if h0 != 0 || h1 != 1 { ok = false; }
  let pg2 = cl_search(&l, &p, 0, 1000, pg1.next_start, 2);
  if pg2.next_start != 4 { ok = false; }
  let h2: Int = pg2.hits[0];
  if h2 != 2 { ok = false; }
  let pg3 = cl_search(&l, &p, 0, 1000, 4, 2);
  if pg3.count != 2 || pg3.next_start != -1 { ok = false; }
  let pg4 = cl_search(&l, &p, 0, 1000, 6, 2);
  if pg4.count != 0 || pg4.matched_total != 6 || pg4.next_start != -1 { ok = false; }
  let pg5 = cl_search(&l, &p, 0, 1000, 0, 0);
  if pg5.count != 0 || pg5.next_start != 0 { ok = false; }
  let pg6 = cl_search(&l, &p, 500, 100, 0, 2);
  if pg6.matched_total != 0 || pg6.next_start != -1 { ok = false; }
  let pg7 = cl_search(&l, &p, 200, 400, 0, 10);
  if pg7.matched_total != 3 || pg7.count != 3 { ok = false; }
  let pg8 = cl_search(&l, &p, 150, 350, 0, 10);
  if pg8.matched_total != 2 { ok = false; }
  if cl_search_count(&l, &p, 200, 400) != 3 { ok = false; }
  return assert(ok, "search pagination, matched totals and time boundaries");
}

fn t26() -> TestResult {
  var e0 = cl_event_new(1000, 2, "started");
  cl_event_set(&mut e0, "svc", "api");
  var e1 = cl_event_new(2000, 4, "failed");
  let l0 = cl_kv_encode(&e0);
  let l1 = cl_kv_encode(&e1);
  var ing = cl_ingest_new(0);
  cl_ingest_assign(&mut ing, 1000, l0);
  cl_ingest_assign(&mut ing, 2000, l1);
  let pol = CloudFlushPolicy{ max_events: 2; max_bytes: 0; max_age_ms: 0; };
  let plan = cl_ingest_plan_flush(&ing, &pol, 2000);
  var ok = plan.should && plan.reason == 1 && plan.count == 2;
  let done = cl_ingest_flush(&mut ing, &pol, 2000);
  if done.count != 2 || cl_ingest_count(&ing) != 0 { ok = false; }
  var st = cl_stream_new();
  cl_stream_append(&mut st, 1000, l0);
  cl_stream_append(&mut st, 2000, l1);
  var t = cl_tail_new(0);
  let rd = cl_tail_read(&st, &t, 5);
  if rd.count != 2 { ok = false; }
  let cm = cl_tail_commit(&mut t, rd.next_cursor);
  if !cm || !cl_tail_ok(&st, &t) { ok = false; }
  let rt = cl_kv_decode(cl_stream_line(&st, 1));
  match rt {
    Ok(d) => {
      if d.time_ms != 2000 || d.level != 4 { ok = false; }
      if !streq(d.msg, "failed") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let jr = cl_json_decode(cl_json_encode(&e1));
  match jr {
    Ok(j) => {
      if j.level != 4 || !streq(j.msg, "failed") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var s = cl_store_new(1);
  cl_store_append(&mut s, 1000, l0.len());
  cl_store_append(&mut s, 2000, l1.len());
  let spol = CloudStorePolicy{ max_bytes: 100000; max_age_ms: 0; max_segments: 0; max_events: 0; compact_at: 0; compact_to: 0; };
  let ret = cl_store_apply_retention(&mut s, &spol, 2000);
  if ret.dropped != 0 || cl_store_live_count(&s) != 2 { ok = false; }
  var lg = cl_log_new();
  let q0 = cl_log_add(&mut lg, e0.time_ms, e0.level, e0.severity, e0.msg);
  let q1 = cl_log_add(&mut lg, e1.time_ms, e1.level, e1.severity, e1.msg);
  cl_log_add_kv(&mut lg, q0, "svc", "api");
  var p = cl_pred_new();
  let n1 = cl_pred_level(&mut p, 4);
  let n2 = cl_pred_sev_ge(&mut p, 4);
  let root = cl_pred_and(&mut p, n1, n2);
  if !cl_pred_eval(&p, &lg, q1, root) { ok = false; }
  if cl_pred_eval(&p, &lg, q0, root) { ok = false; }
  return assert(ok, "end-to-end ingest -> flush -> encode -> stream -> tail -> search");
}

fn pipeline_summary() -> Str {
  var ing = cl_ingest_new(0);
  cl_ingest_assign(&mut ing, 5, "a");
  cl_ingest_assign(&mut ing, 6, "b");
  let pol = CloudFlushPolicy{ max_events: 0; max_bytes: 0; max_age_ms: 0; };
  let f = cl_ingest_flush(&mut ing, &pol, 10);
  var e = cl_event_new(10, 2, "m");
  cl_event_set(&mut e, "k", "v");
  var lg = cl_log_new();
  cl_log_add(&mut lg, 10, 2, 2, "m");
  cl_log_add(&mut lg, 20, 4, 4, "m2");
  var p = cl_pred_new();
  cl_pred_const(&mut p, true);
  let pg = cl_search(&lg, &p, 0, 100, 0, 1);
  return cl_kv_encode(&e) + "|" + cl_json_encode(&e) + "|" + int.int_to_string(f.reason) + "|" + int.int_to_string(pg.count) + "|" + int.int_to_string(cl_ingest_accepted(&ing));
}

fn t27() -> TestResult {
  let a = pipeline_summary();
  let b = pipeline_summary();
  var ok = streq(a, b);
  let want = "time=10 level=info severity=2 msg=\"m\" k=\"v\"|{\"time\":10,\"level\":\"info\",\"severity\":2,\"msg\":\"m\",\"k\":\"v\"}|4|1|2";
  if !streq(a, want) { ok = false; }
  return assert(ok, "deterministic repeated pipeline summary");
}

fn main() -> Int {
  io.println("=== xiom.cloudlog conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.cloudlog: all tests passed");
  } else {
    io.println("xiom.cloudlog: tests failed");
  }
  return failed;
}
