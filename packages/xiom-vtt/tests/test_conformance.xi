// XIOM -- xiom.vtt conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: signature lines (plain and with trailing
// text), header metadata, cue identifiers, multi-line payloads, settings
// pass-through, NOTE/STYLE/REGION raw blocks, blank-line handling, CRLF
// normalization, empty payload cues, empty tracks, UTF-8 payloads, the
// timestamp grammar (both accepted forms, range checks, canonical
// formatting), the parse error catalog, the cue builder, and every
// accessor including its out-of-range sentinels.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from Vec[Str] lowers to a pointer comparison), and every
// element read goes through a typed local.

module vtt_tests
use xiom.io; use xiom.test; use xiom.vtt;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_is(r: Result[Vtt, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn ok_int(r: Result[Int, Str]) -> Int {
  if !r.is_ok { return -123456789; }
  return r.value;
}

// Structural comparison of two tracks: signature, headers, every cue field,
// payload lines, and the raw blocks. Document order of blocks is not read
// here (there is no order accessor); callers compare vtt_format output for
// that.
fn sub_eq(a: &Vtt, b: &Vtt) -> Bool {
  if !streq(vtt_signature(a), vtt_signature(b)) { return false; }
  if vtt_header_count(a) != vtt_header_count(b) { return false; }
  var i = 0;
  while i < vtt_header_count(a) {
    let xa: Str = vtt_header(a, i);
    let xb: Str = vtt_header(b, i);
    if !streq(xa, xb) { return false; }
    i = i + 1;
  }
  if vtt_cue_count(a) != vtt_cue_count(b) { return false; }
  i = 0;
  while i < vtt_cue_count(a) {
    if vtt_cue_start_ms(a, i) != vtt_cue_start_ms(b, i) { return false; }
    if vtt_cue_end_ms(a, i) != vtt_cue_end_ms(b, i) { return false; }
    if vtt_cue_line_count(a, i) != vtt_cue_line_count(b, i) { return false; }
    let ia: Str = vtt_cue_id(a, i);
    let ib: Str = vtt_cue_id(b, i);
    if !streq(ia, ib) { return false; }
    let sa: Str = vtt_cue_settings(a, i);
    let sb: Str = vtt_cue_settings(b, i);
    if !streq(sa, sb) { return false; }
    let ta: Str = vtt_cue_text(a, i);
    let tb: Str = vtt_cue_text(b, i);
    if !streq(ta, tb) { return false; }
    var j = 0;
    while j < vtt_cue_line_count(a, i) {
      let la: Str = vtt_cue_line(a, i, j);
      let lb: Str = vtt_cue_line(b, i, j);
      if !streq(la, lb) { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  if vtt_block_count(a) != vtt_block_count(b) { return false; }
  i = 0;
  while i < vtt_block_count(a) {
    let ka: Str = vtt_block_kind(a, i);
    let kb: Str = vtt_block_kind(b, i);
    if !streq(ka, kb) { return false; }
    let xa: Str = vtt_block_text(a, i);
    let xb: Str = vtt_block_text(b, i);
    if !streq(xa, xb) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = vtt_parse("WEBVTT\nKind: captions\nLanguage: en\n");
  if !r.is_ok { return assert(false, "signature-only track keeps header metadata"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 0;
  if vtt_header_count(&v) != 2 { ok = false; }
  let h0: Str = vtt_header(&v, 0);
  let h1: Str = vtt_header(&v, 1);
  if !streq(h0, "Kind: captions") { ok = false; }
  if !streq(h1, "Language: en") { ok = false; }
  let sig: Str = vtt_signature(&v);
  if !streq(sig, "WEBVTT") { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, "WEBVTT\nKind: captions\nLanguage: en\n") { ok = false; }
  return assert(ok, "signature-only track keeps header metadata");
}

fn t2() -> TestResult {
  let doc = "WEBVTT - Subtitles by XIOM\n\n00:00:01.000 --> 00:00:02.000\nHello\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "signature trailing text is preserved"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 1;
  let sig: Str = vtt_signature(&v);
  if !streq(sig, "WEBVTT - Subtitles by XIOM") { ok = false; }
  if vtt_cue_start_ms(&v, 0) != 1000 { ok = false; }
  if vtt_cue_end_ms(&v, 0) != 2000 { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "signature trailing text is preserved");
}

fn t3() -> TestResult {
  let doc = "WEBVTT\n\nintro\n00:00:01.000 --> 00:00:02.500\nHello\nWorld\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "cue identifier and multi-line payload"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 1;
  let cid: Str = vtt_cue_id(&v, 0);
  if !streq(cid, "intro") { ok = false; }
  if vtt_cue_start_ms(&v, 0) != 1000 { ok = false; }
  if vtt_cue_end_ms(&v, 0) != 2500 { ok = false; }
  if vtt_cue_line_count(&v, 0) != 2 { ok = false; }
  let l0: Str = vtt_cue_line(&v, 0, 0);
  let l1: Str = vtt_cue_line(&v, 0, 1);
  if !streq(l0, "Hello") { ok = false; }
  if !streq(l1, "World") { ok = false; }
  let txt: Str = vtt_cue_text(&v, 0);
  if !streq(txt, "Hello\nWorld") { ok = false; }
  let stg: Str = vtt_cue_settings(&v, 0);
  if !streq(stg, "") { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "cue identifier and multi-line payload");
}

fn t4() -> TestResult {
  let doc = "WEBVTT\n\nintro 1\n00:00:01.000 \t --> \t00:00:02.000 align:middle line:90%\nHello\n";
  let want = "WEBVTT\n\nintro 1\n00:00:01.000 --> 00:00:02.000 align:middle line:90%\nHello\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "settings pass through; whitespace around the arrow is tolerated"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 1;
  let stg: Str = vtt_cue_settings(&v, 0);
  if !streq(stg, "align:middle line:90%") { ok = false; }
  let cid: Str = vtt_cue_id(&v, 0);
  if !streq(cid, "intro 1") { ok = false; }
  if vtt_cue_start_ms(&v, 0) != 1000 { ok = false; }
  if vtt_cue_end_ms(&v, 0) != 2000 { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, want) { ok = false; }
  return assert(ok, "settings pass through; whitespace around the arrow is tolerated");
}

fn t5() -> TestResult {
  var ok = ok_int(vtt_timestamp_parse("01:02:03.456")) == 3723456;
  if ok_int(vtt_timestamp_parse("01:02.345")) != 62345 { ok = false; }
  if ok_int(vtt_timestamp_parse("99:59:59.999")) != 359999999 { ok = false; }
  if ok_int(vtt_timestamp_parse("00:00:00.000")) != 0 { ok = false; }
  if ok_int(vtt_timestamp_parse("00:00.001")) != 1 { ok = false; }
  return assert(ok, "timestamp forms parse to exact milliseconds");
}

fn t6() -> TestResult {
  var ok = err_int_is(vtt_timestamp_parse("00:60:00.000"), "vtt: timestamp out of range");
  if !err_int_is(vtt_timestamp_parse("00:00:61.000"), "vtt: timestamp out of range") { ok = false; }
  if !err_int_is(vtt_timestamp_parse("60:00.000"), "vtt: timestamp out of range") { ok = false; }
  if !err_int_is(vtt_timestamp_parse("00:00:01,000"), "vtt: bad timestamp shape") { ok = false; }
  if !err_int_is(vtt_timestamp_parse("0:00:01.000"), "vtt: bad timestamp shape") { ok = false; }
  if !err_int_is(vtt_timestamp_parse("00:00:01.00"), "vtt: bad timestamp shape") { ok = false; }
  if !err_int_is(vtt_timestamp_parse("00:0a:01.000"), "vtt: bad timestamp shape") { ok = false; }
  if !err_int_is(vtt_timestamp_parse(""), "vtt: bad timestamp shape") { ok = false; }
  return assert(ok, "timestamp shape and range errors are distinct");
}

fn t7() -> TestResult {
  let bad = "WEBVTT\n\n00:00:05.000 --> 00:00:02.000\nx\n";
  var ok = err_is(vtt_parse(bad), "vtt: end before start");
  let eq = vtt_parse("WEBVTT\n\n00:00:02.000 --> 00:00:02.000\nx\n");
  if !eq.is_ok {
    ok = false;
  } else {
    let v = eq.value;
    if vtt_cue_start_ms(&v, 0) != 2000 { ok = false; }
    if vtt_cue_end_ms(&v, 0) != 2000 { ok = false; }
  }
  return assert(ok, "end before start is Err; equal times are allowed");
}

fn t8() -> TestResult {
  var ok = err_is(vtt_parse(""), "vtt: missing signature");
  if !err_is(vtt_parse("WEBVTTX\n"), "vtt: missing signature") { ok = false; }
  if !err_is(vtt_parse("webvtt\n"), "vtt: missing signature") { ok = false; }
  if !err_is(vtt_parse("WEBVTTx captions\n"), "vtt: missing signature") { ok = false; }
  if !err_is(vtt_parse("00:00:01.000 --> 00:00:02.000\nx\n"), "vtt: missing signature") { ok = false; }
  return assert(ok, "a document without a valid WEBVTT signature is Err");
}

fn t9() -> TestResult {
  var ok = err_is(vtt_parse("WEBVTT\n\njust text\n"), "vtt: cue without timing");
  if !err_is(vtt_parse("WEBVTT\n\nNOTEish\n"), "vtt: cue without timing") { ok = false; }
  let two_before = "WEBVTT\n\nid\nnote\n00:00:01.000 --> 00:00:02.000\nx\n";
  if !err_is(vtt_parse(two_before), "vtt: payload before timing") { ok = false; }
  let split_payload = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nline1\n\nline2\n";
  if !err_is(vtt_parse(split_payload), "vtt: cue without timing") { ok = false; }
  return assert(ok, "cue blocks must start with an optional id then the timing line");
}

fn t10() -> TestResult {
  let comma = "WEBVTT\n\n00:00:01,000 --> 00:00:02.000\nx\n";
  var ok = err_is(vtt_parse(comma), "vtt: bad timestamp shape");
  let end_range = "WEBVTT\n\n00:00:01.000 --> 00:60:02.000\nx\n";
  if !err_is(vtt_parse(end_range), "vtt: timestamp out of range") { ok = false; }
  let short_start = "WEBVTT\n\n0:00:01.000 --> 00:00:02.000\nx\n";
  if !err_is(vtt_parse(short_start), "vtt: bad timestamp shape") { ok = false; }
  let no_end = "WEBVTT\n\n00:00:01.000 --> \nx\n";
  if !err_is(vtt_parse(no_end), "vtt: bad timestamp shape") { ok = false; }
  return assert(ok, "timing-line timestamp errors use the documented messages");
}

fn t11() -> TestResult {
  let doc = "WEBVTT\n\nNOTE a comment\nmore detail\n\n00:00:01.000 --> 00:00:02.000\ntext\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "NOTE blocks are preserved as raw text"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 1;
  if vtt_block_count(&v) != 1 { ok = false; }
  let kind: Str = vtt_block_kind(&v, 0);
  if !streq(kind, "NOTE") { ok = false; }
  let bt: Str = vtt_block_text(&v, 0);
  if !streq(bt, "NOTE a comment\nmore detail") { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, doc) { ok = false; }
  let bare = vtt_parse("WEBVTT\n\nNOTE\n\n00:00:01.000 --> 00:00:02.000\nx\n");
  if !bare.is_ok {
    ok = false;
  } else {
    let vb = bare.value;
    let kb: Str = vtt_block_kind(&vb, 0);
    if !streq(kb, "NOTE") { ok = false; }
  }
  return assert(ok, "NOTE blocks are preserved as raw text");
}

fn t12() -> TestResult {
  let doc = "WEBVTT\n\nSTYLE\n::cue { color: yellow }\n\n00:00:01.000 --> 00:00:02.000\nfirst\n\nREGION\nid:fred width:40%\n\n00:00:03.000 --> 00:00:04.000\nsecond\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "STYLE and REGION blocks are preserved between cues"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 2;
  if vtt_block_count(&v) != 2 { ok = false; }
  let k0: Str = vtt_block_kind(&v, 0);
  let k1: Str = vtt_block_kind(&v, 1);
  if !streq(k0, "STYLE") { ok = false; }
  if !streq(k1, "REGION") { ok = false; }
  let t0: Str = vtt_block_text(&v, 0);
  if !streq(t0, "STYLE\n::cue { color: yellow }") { ok = false; }
  let t1: Str = vtt_block_text(&v, 1);
  if !streq(t1, "REGION\nid:fred width:40%") { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, doc) { ok = false; }
  let r2 = vtt_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let v2 = r2.value;
    let f2: Str = vtt_format(&v2);
    if !streq(f2, doc) { ok = false; }
  }
  return assert(ok, "STYLE and REGION blocks are preserved between cues");
}

fn t13() -> TestResult {
  let crlf = "WEBVTT\r\n\r\n\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nx\r\n\r\n\r\n00:00:03.000 --> 00:00:04.000\r\ny\r\n\r\n";
  let want = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nx\n\n00:00:03.000 --> 00:00:04.000\ny\n";
  let r = vtt_parse(crlf);
  if !r.is_ok { return assert(false, "stray blank lines are skipped; CRLF normalizes to LF"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 2;
  let t0: Str = vtt_cue_text(&v, 0);
  let t1: Str = vtt_cue_text(&v, 1);
  if !streq(t0, "x") { ok = false; }
  if !streq(t1, "y") { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, want) { ok = false; }
  return assert(ok, "stray blank lines are skipped; CRLF normalizes to LF");
}

fn t14() -> TestResult {
  let doc = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n\n00:00:03.000 --> 00:00:04.000\nx\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "a cue may have an empty payload"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 2;
  if vtt_cue_line_count(&v, 0) != 0 { ok = false; }
  let t0: Str = vtt_cue_text(&v, 0);
  if !streq(t0, "") { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, doc) { ok = false; }
  let r2 = vtt_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let v2 = r2.value;
    if !sub_eq(&v, &v2) { ok = false; }
  }
  return assert(ok, "a cue may have an empty payload");
}

fn t15() -> TestResult {
  var ok = streq(vtt_timestamp_format(0), "00:00:00.000");
  if !streq(vtt_timestamp_format(3723456), "01:02:03.456") { ok = false; }
  if !streq(vtt_timestamp_format(62345), "00:01:02.345") { ok = false; }
  if !streq(vtt_timestamp_format(359999999), "99:59:59.999") { ok = false; }
  if !streq(vtt_timestamp_format(-7), "00:00:00.000") { ok = false; }
  if !streq(vtt_timestamp_format(360000000), "100:00:00.000") { ok = false; }
  return assert(ok, "canonical timestamp formatting is HH:MM:SS.mmm");
}

fn t16() -> TestResult {
  let doc = "WEBVTT - Demo\nKind: captions\nLanguage: en\n\nNOTE generated\n\nSTYLE\n::cue { color: lime }\n\nintro\n00:00:01.000 --> 00:00:02.500\nHello\nWorld\n\n00:00:03.000 --> 00:00:04.000 align:start\nsecond\n\nREGION\nid:r1\n\n00:00:05.000 --> 00:00:06.000\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "a full document round-trips parse -> format -> parse"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 3;
  if vtt_header_count(&v) != 2 { ok = false; }
  if vtt_block_count(&v) != 3 { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, doc) { ok = false; }
  let r2 = vtt_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let v2 = r2.value;
    if !sub_eq(&v, &v2) { ok = false; }
    let f2: Str = vtt_format(&v2);
    if !streq(f2, doc) { ok = false; }
  }
  return assert(ok, "a full document round-trips parse -> format -> parse");
}

fn t17() -> TestResult {
  let v0 = vtt_new();
  var ok = vtt_cue_count(&v0) == 0;
  if !streq(vtt_format(&v0), "WEBVTT\n") { ok = false; }
  let r1 = vtt_cue_add(&v0, "", 1000, 2000, "", "Hello\nWorld");
  if !r1.is_ok { return assert(false, "the cue builder appends cues with canonical timing"); }
  let v1 = r1.value;
  let f1: Str = vtt_format(&v1);
  if !streq(f1, "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello\nWorld\n") { ok = false; }
  let r2 = vtt_cue_add(&v1, "intro", 3000, 4000, "align:start", "second");
  if !r2.is_ok { return assert(false, "the cue builder appends cues with canonical timing"); }
  let v2 = r2.value;
  let f2: Str = vtt_format(&v2);
  let want = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello\nWorld\n\nintro\n00:00:03.000 --> 00:00:04.000 align:start\nsecond\n";
  if !streq(f2, want) { ok = false; }
  if vtt_cue_count(&v2) != 2 { ok = false; }
  if vtt_cue_start_ms(&v2, 1) != 3000 { ok = false; }
  if vtt_cue_end_ms(&v2, 1) != 4000 { ok = false; }
  let cid: Str = vtt_cue_id(&v2, 1);
  if !streq(cid, "intro") { ok = false; }
  let stg: Str = vtt_cue_settings(&v2, 1);
  if !streq(stg, "align:start") { ok = false; }
  let txt: Str = vtt_cue_text(&v2, 0);
  if !streq(txt, "Hello\nWorld") { ok = false; }
  if vtt_cue_count(&v0) != 0 { ok = false; }
  let r3 = vtt_parse(f2);
  if !r3.is_ok {
    ok = false;
  } else {
    let v3 = r3.value;
    if !sub_eq(&v2, &v3) { ok = false; }
  }
  return assert(ok, "the cue builder appends cues with canonical timing");
}

fn t18() -> TestResult {
  let v0 = vtt_new();
  var ok = err_is(vtt_cue_add(&v0, "", -1, 500, "", "x"), "vtt: negative time");
  if !err_is(vtt_cue_add(&v0, "", 0, -5, "", "x"), "vtt: negative time") { ok = false; }
  if !err_is(vtt_cue_add(&v0, "", 500, 100, "", "x"), "vtt: end before start") { ok = false; }
  if !err_is(vtt_cue_add(&v0, "a-->b", 0, 100, "", "x"), "vtt: bad cue identifier") { ok = false; }
  if !err_is(vtt_cue_add(&v0, "a\nb", 0, 100, "", "x"), "vtt: bad cue identifier") { ok = false; }
  if !err_is(vtt_cue_add(&v0, "", 0, 100, "align:x\ny", "x"), "vtt: bad settings") { ok = false; }
  if !err_is(vtt_cue_add(&v0, "", 0, 100, "", "a\n\nb"), "vtt: blank payload line") { ok = false; }
  if vtt_cue_count(&v0) != 0 { ok = false; }
  return assert(ok, "the cue builder rejects values WebVTT cannot represent");
}

fn t19() -> TestResult {
  let doc = "WEBVTT\nKind: captions\n\nNOTE c\n\n00:00:01.000 --> 00:00:02.000\npayload\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "accessors return sentinels out of range"); }
  let v = r.value;
  var ok = true;
  let h_lo: Str = vtt_header(&v, -1);
  let h_hi: Str = vtt_header(&v, 99);
  if !streq(h_lo, "") { ok = false; }
  if !streq(h_hi, "") { ok = false; }
  let i_lo: Str = vtt_cue_id(&v, -1);
  let i_hi: Str = vtt_cue_id(&v, 5);
  if !streq(i_lo, "") { ok = false; }
  if !streq(i_hi, "") { ok = false; }
  if vtt_cue_start_ms(&v, -1) != -1 { ok = false; }
  if vtt_cue_start_ms(&v, 5) != -1 { ok = false; }
  if vtt_cue_end_ms(&v, -1) != -1 { ok = false; }
  if vtt_cue_end_ms(&v, 5) != -1 { ok = false; }
  let s_hi: Str = vtt_cue_settings(&v, 5);
  if !streq(s_hi, "") { ok = false; }
  if vtt_cue_line_count(&v, 5) != 0 { ok = false; }
  let l_lo: Str = vtt_cue_line(&v, 0, -1);
  let l_hi: Str = vtt_cue_line(&v, 0, 99);
  if !streq(l_lo, "") { ok = false; }
  if !streq(l_hi, "") { ok = false; }
  let t_hi: Str = vtt_cue_text(&v, 5);
  if !streq(t_hi, "") { ok = false; }
  let b_lo: Str = vtt_block_text(&v, -1);
  let b_hi: Str = vtt_block_kind(&v, 9);
  if !streq(b_lo, "") { ok = false; }
  if !streq(b_hi, "") { ok = false; }
  return assert(ok, "accessors return sentinels out of range");
}

fn t20() -> TestResult {
  let doc = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nhéllo — 世界\nnaïve ✓\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "non-ASCII payload bytes round-trip exactly"); }
  let v = r.value;
  var ok = vtt_cue_line_count(&v, 0) == 2;
  let txt: Str = vtt_cue_text(&v, 0);
  if !streq(txt, "héllo — 世界\nnaïve ✓") { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "non-ASCII payload bytes round-trip exactly");
}

fn t21() -> TestResult {
  let v0 = vtt_new();
  var ok = streq(vtt_format(&v0), "WEBVTT\n");
  if vtt_header_count(&v0) != 0 { ok = false; }
  if vtt_block_count(&v0) != 0 { ok = false; }
  let a = vtt_parse("WEBVTT");
  if !a.is_ok {
    ok = false;
  } else {
    let va = a.value;
    if vtt_cue_count(&va) != 0 { ok = false; }
    if !streq(vtt_format(&va), "WEBVTT\n") { ok = false; }
  }
  let b = vtt_parse("WEBVTT\n");
  if !b.is_ok {
    ok = false;
  } else {
    let vb = b.value;
    if !streq(vtt_format(&vb), "WEBVTT\n") { ok = false; }
  }
  let c = vtt_parse("WEBVTT \n");
  if !c.is_ok {
    ok = false;
  } else {
    let vc = c.value;
    if !streq(vtt_format(&vc), "WEBVTT \n") { ok = false; }
  }
  return assert(ok, "an empty track needs only the signature line");
}

fn t22() -> TestResult {
  let doc = "WEBVTT\nKind: captions\n00:00:01.000 --> 00:00:02.000\nx\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "without a blank line every line is header metadata"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 0;
  if vtt_header_count(&v) != 3 { ok = false; }
  let h1: Str = vtt_header(&v, 1);
  let h2: Str = vtt_header(&v, 2);
  if !streq(h1, "00:00:01.000 --> 00:00:02.000") { ok = false; }
  if !streq(h2, "x") { ok = false; }
  let f: Str = vtt_format(&v);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "without a blank line every line is header metadata");
}

fn t23() -> TestResult {
  let trail = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000 \t\ntrail\n";
  let tight = "WEBVTT\n\n00:00:03.000-->00:00:04.000\ntight\n";
  let r = vtt_parse(trail);
  if !r.is_ok { return assert(false, "missing settings and tight arrows parse; settings stay empty"); }
  let v = r.value;
  var ok = vtt_cue_count(&v) == 1;
  let s0: Str = vtt_cue_settings(&v, 0);
  if !streq(s0, "") { ok = false; }
  let f0: Str = vtt_format(&v);
  if !streq(f0, "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\ntrail\n") { ok = false; }
  let r2 = vtt_parse(tight);
  if !r2.is_ok {
    ok = false;
  } else {
    let v2 = r2.value;
    if vtt_cue_start_ms(&v2, 0) != 3000 { ok = false; }
    if vtt_cue_end_ms(&v2, 0) != 4000 { ok = false; }
    let s1: Str = vtt_cue_settings(&v2, 0);
    if !streq(s1, "") { ok = false; }
    let f1: Str = vtt_format(&v2);
    if !streq(f1, "WEBVTT\n\n00:00:03.000 --> 00:00:04.000\ntight\n") { ok = false; }
  }
  return assert(ok, "missing settings and tight arrows parse; settings stay empty");
}

fn main() -> Int {
  io.println("=== xiom.vtt conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.vtt: all tests passed");
  } else {
    io.println("xiom.vtt: tests failed");
  }
  return failed;
}
