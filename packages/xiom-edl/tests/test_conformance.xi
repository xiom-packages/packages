// XIOM -- xiom.edl conformance tests (22 checks)
// Greenfield package: prove the pure-XIOM xiom.edl module against its
// documented CMX EDL subset, error catalog and round-trip rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: full documents, CRLF/indentation/blank lines and an unterminated
// final line, boundary event numbers and reels, all seven track tokens, cut/
// dissolve/wipe transitions, boundary durations and wipe codes, canonical
// emission byte for byte, parse -> emit -> parse round trips with
// idempotence, line/event index mapping, title and comment raw preservation,
// every documented error (bad event number, out-of-order numbers, bad reel,
// unknown track, bad transition, missing/bad dissolve duration, bad timecode
// shapes including the drop-frame `;`, frame-out-of-range for bases 24/25/30,
// unsupported bases, truncated and trailing fields, unexpected lines),
// out-of-range accessor sentinels, empty documents, and the timecode
// helpers.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq and every Vec element read binds a typed
// local first. Test functions are called directly from main (no indexed
// Vec[fn] dispatch, which miscompiles).

module edl_tests
use xiom.io; use xiom.test; use xiom.edl;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `text` fails to parse at frame base `fps` with exactly `want`.
fn parse_err_is(text: Str, fps: Int, want: Str) -> Bool {
  let r = edl_parse(text, fps);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `text` fails to parse at frame base `fps` with an error message
// starting with `prefix`.
fn parse_err_prefix(text: Str, fps: Int, prefix: Str) -> Bool {
  let r = edl_parse(text, fps);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

// Deep equality over the whole observable surface: line stream, title and
// comments, frame base and every event field.
fn same_edl(a: &Edl, b: &Edl) -> Bool {
  if edl_line_count(a) != edl_line_count(b) { return false; }
  if edl_frame_base(a) != edl_frame_base(b) { return false; }
  var i = 0;
  while i < edl_line_count(a) {
    if edl_line_kind(a, i) != edl_line_kind(b, i) { return false; }
    let ta: Str = edl_line_text(a, i);
    let tb: Str = edl_line_text(b, i);
    if !streq(ta, tb) { return false; }
    i = i + 1;
  }
  if edl_event_count(a) != edl_event_count(b) { return false; }
  var j = 0;
  while j < edl_event_count(a) {
    if edl_event_number(a, j) != edl_event_number(b, j) { return false; }
    if edl_event_transition(a, j) != edl_event_transition(b, j) { return false; }
    if edl_event_duration(a, j) != edl_event_duration(b, j) { return false; }
    if edl_event_wipe(a, j) != edl_event_wipe(b, j) { return false; }
    if edl_event_line(a, j) != edl_event_line(b, j) { return false; }
    let ra: Str = edl_event_reel(a, j);
    let rb: Str = edl_event_reel(b, j);
    if !streq(ra, rb) { return false; }
    let ka: Str = edl_event_track(a, j);
    let kb: Str = edl_event_track(b, j);
    if !streq(ka, kb) { return false; }
    let sia: Str = edl_event_src_in(a, j);
    let sib: Str = edl_event_src_in(b, j);
    if !streq(sia, sib) { return false; }
    let soa: Str = edl_event_src_out(a, j);
    let sob: Str = edl_event_src_out(b, j);
    if !streq(soa, sob) { return false; }
    let ria: Str = edl_event_rec_in(a, j);
    let rib: Str = edl_event_rec_in(b, j);
    if !streq(ria, rib) { return false; }
    let roa: Str = edl_event_rec_out(a, j);
    let rob: Str = edl_event_rec_out(b, j);
    if !streq(roa, rob) { return false; }
    j = j + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let doc = "TITLE Demo Reel\n* opening comment\n; legacy comment\n001 AX V C 00:00:00:00 00:00:05:00 01:00:00:00 01:00:05:00\n002 AX V D 030 00:00:05:00 00:00:08:00 01:00:05:00 01:00:08:00\n* a dissolve\n003 BL V W001 00:00:00:00 00:00:03:00 01:00:08:00 01:00:11:00\n";
  let r = edl_parse(doc, 25);
  var ok = false;
  match r {
    Ok(d) => {
      ok = edl_line_count(&d) == 7;
      if edl_line_kind(&d, 0) != LK_TITLE { ok = false; }
      if edl_line_kind(&d, 1) != LK_COMMENT { ok = false; }
      if edl_line_kind(&d, 2) != LK_COMMENT { ok = false; }
      if edl_line_kind(&d, 3) != LK_EVENT { ok = false; }
      if edl_line_kind(&d, 4) != LK_EVENT { ok = false; }
      if edl_line_kind(&d, 5) != LK_COMMENT { ok = false; }
      if edl_line_kind(&d, 6) != LK_EVENT { ok = false; }
      if !streq(edl_title(&d), "Demo Reel") { ok = false; }
      if edl_title_count(&d) != 1 { ok = false; }
      if edl_comment_count(&d) != 3 { ok = false; }
      if edl_frame_base(&d) != 25 { ok = false; }
      if edl_event_count(&d) != 3 { ok = false; }
      if edl_event_line(&d, 0) != 3 { ok = false; }
      if edl_event_line(&d, 1) != 4 { ok = false; }
      if edl_event_line(&d, 2) != 6 { ok = false; }
      if edl_event_number(&d, 0) != 1 { ok = false; }
      if edl_event_number(&d, 1) != 2 { ok = false; }
      if edl_event_number(&d, 2) != 3 { ok = false; }
      if !streq(edl_event_reel(&d, 0), "AX") { ok = false; }
      if !streq(edl_event_reel(&d, 2), "BL") { ok = false; }
      if !streq(edl_event_track(&d, 1), "V") { ok = false; }
      if edl_event_transition(&d, 0) != TR_CUT { ok = false; }
      if edl_event_transition(&d, 1) != TR_DISSOLVE { ok = false; }
      if edl_event_transition(&d, 2) != TR_WIPE { ok = false; }
      if edl_event_duration(&d, 0) != 0 { ok = false; }
      if edl_event_duration(&d, 1) != 30 { ok = false; }
      if edl_event_wipe(&d, 0) != 0 { ok = false; }
      if edl_event_wipe(&d, 2) != 1 { ok = false; }
      if !streq(edl_event_src_in(&d, 0), "00:00:00:00") { ok = false; }
      if !streq(edl_event_src_out(&d, 1), "00:00:08:00") { ok = false; }
      if !streq(edl_event_rec_in(&d, 2), "01:00:08:00") { ok = false; }
      if !streq(edl_event_rec_out(&d, 2), "01:00:11:00") { ok = false; }
      if !streq(edl_line_text(&d, 0), "Demo Reel") { ok = false; }
      if !streq(edl_line_text(&d, 1), "* opening comment") { ok = false; }
      if !streq(edl_line_text(&d, 2), "; legacy comment") { ok = false; }
      if !streq(edl_line_text(&d, 5), "* a dissolve") { ok = false; }
      if !streq(edl_line_text(&d, 3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full document: title, comments, cut/dissolve/wipe, accessors");
}

fn t2() -> TestResult {
  let doc = "\r\nTITLE X\r\n\r\n\t001  AX\tV  C  00:00:00:00\t00:00:01:00 00:00:00:00 00:00:01:00\r\n";
  let r = edl_parse(doc, 25);
  var ok = false;
  match r {
    Ok(d) => {
      ok = edl_line_count(&d) == 2;
      if !streq(edl_title(&d), "X") { ok = false; }
      if edl_event_count(&d) != 1 { ok = false; }
      if !streq(edl_event_reel(&d, 0), "AX") { ok = false; }
      if !streq(edl_event_rec_out(&d, 0), "00:00:01:00") { ok = false; }
      let got = edl_emit(&d);
      let want = "TITLE X\n001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = edl_parse("TITLE Tail\n001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00", 25);
  match r2 {
    Ok(d2) => {
      if edl_line_count(&d2) != 2 { ok = false; }
      if edl_event_count(&d2) != 1 { ok = false; }
      let got2 = edl_emit(&d2);
      let want2 = "TITLE Tail\n001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
      if !streq(got2, want2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF, indentation, blank lines and an unterminated final line");
}

fn t3() -> TestResult {
  var doc = "001 ABCDEFGH V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  doc = doc + "002 AX A C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  doc = doc + "003 AX A2 C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  doc = doc + "004 AX AA C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  doc = doc + "005 AX B D 001 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  doc = doc + "006 AX A3 D 999 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  doc = doc + "007 AX A4 W001 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  doc = doc + "999 AX V W999 99:59:59:23 99:59:59:23 99:59:59:23 99:59:59:23\n";
  let r = edl_parse(doc, 24);
  var ok = false;
  match r {
    Ok(d) => {
      ok = edl_event_count(&d) == 8;
      if edl_event_number(&d, 0) != 1 { ok = false; }
      if edl_event_number(&d, 7) != 999 { ok = false; }
      if !streq(edl_event_reel(&d, 0), "ABCDEFGH") { ok = false; }
      if !streq(edl_event_track(&d, 0), "V") { ok = false; }
      if !streq(edl_event_track(&d, 1), "A") { ok = false; }
      if !streq(edl_event_track(&d, 2), "A2") { ok = false; }
      if !streq(edl_event_track(&d, 3), "AA") { ok = false; }
      if !streq(edl_event_track(&d, 4), "B") { ok = false; }
      if !streq(edl_event_track(&d, 5), "A3") { ok = false; }
      if !streq(edl_event_track(&d, 6), "A4") { ok = false; }
      if edl_event_duration(&d, 4) != 1 { ok = false; }
      if edl_event_duration(&d, 5) != 999 { ok = false; }
      if edl_event_wipe(&d, 6) != 1 { ok = false; }
      if edl_event_wipe(&d, 7) != 999 { ok = false; }
      if edl_event_timecode_value(&d, 7, TC_SRC_IN) != 99595923 { ok = false; }
      if edl_timecode_part(edl_event_timecode_value(&d, 7, TC_REC_OUT), TCF_HH) != 99 { ok = false; }
      if edl_timecode_part(edl_event_timecode_value(&d, 7, TC_REC_OUT), TCF_MM) != 59 { ok = false; }
      if edl_timecode_part(edl_event_timecode_value(&d, 7, TC_REC_OUT), TCF_SS) != 59 { ok = false; }
      if edl_timecode_part(edl_event_timecode_value(&d, 7, TC_REC_OUT), TCF_FF) != 23 { ok = false; }
      if !streq(edl_event_src_in(&d, 7), "99:59:59:23") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "boundaries: 8-char reel, all tracks, 1/999 dissolve and wipe, 99:59:59:23");
}

fn t4() -> TestResult {
  let tail = " AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  var ok = parse_err_prefix("12" + tail, 25, "edl: bad event number: ");
  if !parse_err_prefix("1234" + tail, 25, "edl: bad event number: ") { ok = false; }
  if !parse_err_prefix("000" + tail, 25, "edl: bad event number: ") { ok = false; }
  if !parse_err_prefix("0A1" + tail, 25, "edl: bad event number: ") { ok = false; }
  if !parse_err_prefix("01A" + tail, 25, "edl: bad event number: ") { ok = false; }
  if !parse_err_prefix("-01" + tail, 25, "edl: unexpected line: ") { ok = false; }
  return assert(ok, "bad event numbers are Err (one/two/four digits, 000, non-digits)");
}

fn t5() -> TestResult {
  let tail = " V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  var ok = parse_err_prefix("001 ABCDEFGHI" + tail, 25, "edl: bad reel: ");
  if !parse_err_prefix("001 AX-1" + tail, 25, "edl: bad reel: ") { ok = false; }
  if !parse_err_prefix("001 AX.Y" + tail, 25, "edl: bad reel: ") { ok = false; }
  if !parse_err_prefix("001 AX!Y" + tail, 25, "edl: bad reel: ") { ok = false; }
  if !parse_err_prefix("001 AX/Y" + tail, 25, "edl: bad reel: ") { ok = false; }
  let r = edl_parse("001 A_1" + tail, 25);
  match r {
    Ok(d) => {
      if !streq(edl_event_reel(&d, 0), "A_1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bad reels are Err; letters, digits and underscore are legal");
}

fn t6() -> TestResult {
  let tail = " C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  var ok = parse_err_prefix("001 AX X" + tail, 25, "edl: unknown track: ");
  if !parse_err_prefix("001 AX v" + tail, 25, "edl: unknown track: ") { ok = false; }
  if !parse_err_prefix("001 AX aa" + tail, 25, "edl: unknown track: ") { ok = false; }
  if !parse_err_prefix("001 AX A5" + tail, 25, "edl: unknown track: ") { ok = false; }
  if !parse_err_prefix("001 AX A2B" + tail, 25, "edl: unknown track: ") { ok = false; }
  return assert(ok, "unknown track tokens are Err (case-sensitive documented set)");
}

fn t7() -> TestResult {
  let tail = " 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  var ok = parse_err_prefix("001 AX V X" + tail, 25, "edl: bad transition: ");
  if !parse_err_prefix("001 AX V DD" + tail, 25, "edl: bad transition: ") { ok = false; }
  if !parse_err_prefix("001 AX V d" + tail, 25, "edl: bad transition: ") { ok = false; }
  if !parse_err_prefix("001 AX V W1" + tail, 25, "edl: bad transition: ") { ok = false; }
  if !parse_err_prefix("001 AX V W12" + tail, 25, "edl: bad transition: ") { ok = false; }
  if !parse_err_prefix("001 AX V W1234" + tail, 25, "edl: bad transition: ") { ok = false; }
  if !parse_err_prefix("001 AX V Wabc" + tail, 25, "edl: bad transition: ") { ok = false; }
  if !parse_err_prefix("001 AX V W000" + tail, 25, "edl: bad transition: ") { ok = false; }
  if !parse_err_prefix("001 AX V W00A" + tail, 25, "edl: bad transition: ") { ok = false; }
  return assert(ok, "bad transitions are Err (C, D and W001..W999 only)");
}

fn t8() -> TestResult {
  let tcs = " 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  var ok = parse_err_is("001 AX V D\n", 25, "edl: missing dissolve duration: 001 AX V D");
  if !parse_err_is("001 AX V D", 25, "edl: missing dissolve duration: 001 AX V D") { ok = false; }
  if !parse_err_prefix("001 AX V D 0" + tcs, 25, "edl: bad dissolve duration: ") { ok = false; }
  if !parse_err_prefix("001 AX V D 1000" + tcs, 25, "edl: bad dissolve duration: ") { ok = false; }
  if !parse_err_prefix("001 AX V D abc" + tcs, 25, "edl: bad dissolve duration: ") { ok = false; }
  if !parse_err_prefix("001 AX V D -30" + tcs, 25, "edl: bad dissolve duration: ") { ok = false; }
  let r = edl_parse("001 AX V D 12" + tcs, 25);
  match r {
    Ok(d) => {
      if edl_event_duration(&d, 0) != 12 { ok = false; }
      let got = edl_emit(&d);
      let want = "001 AX V D 012 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "missing and bad dissolve durations are Err; short durations canonicalize");
}

fn t9() -> TestResult {
  var ok = parse_err_prefix("001 AX V C 0:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ");
  if !parse_err_prefix("001 AX V C 1:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 01:0:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 01:00:0:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 01:00:00:0 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 01:00:00;00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 01.00.00.00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 01:60:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 01:00:60:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 01:00:00:0A 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: bad timecode: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:0X:00\n", 25, "edl: bad timecode: ") { ok = false; }
  return assert(ok, "bad timecode shapes are Err, including the drop-frame `;` separator");
}

fn t10() -> TestResult {
  var ok = parse_err_prefix("001 AX V C 00:00:00:24 00:00:01:00 00:00:00:00 00:00:01:00\n", 24, "edl: frame out of range: ");
  if !parse_err_prefix("001 AX V C 00:00:00:23 00:00:01:00 00:00:00:00 00:00:01:24\n", 24, "edl: frame out of range: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 00:00:00:25 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: frame out of range: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 00:00:00:30 00:00:01:00 00:00:00:00 00:00:01:00\n", 30, "edl: frame out of range: ") { ok = false; }
  let r24 = edl_parse("001 AX V C 00:00:00:23 00:00:01:23 00:00:00:00 00:00:01:00\n", 24);
  match r24 {
    Ok(d) => {
      if !streq(edl_event_src_out(&d, 0), "00:00:01:23") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r25 = edl_parse("001 AX V C 00:00:00:24 00:00:01:24 00:00:00:00 00:00:01:00\n", 25);
  match r25 {
    Ok(d) => {
      if !streq(edl_event_src_out(&d, 0), "00:00:01:24") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r30 = edl_parse("001 AX V C 00:00:00:29 00:00:01:29 00:00:00:00 00:00:01:00\n", 30);
  match r30 {
    Ok(d) => {
      if !streq(edl_event_src_out(&d, 0), "00:00:01:29") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is("", 23, "edl: unsupported frame base: 23") { ok = false; }
  if !parse_err_is("", 0, "edl: unsupported frame base: 0") { ok = false; }
  if !parse_err_is("", 50, "edl: unsupported frame base: 50") { ok = false; }
  if !parse_err_is("", -1, "edl: unsupported frame base: -1") { ok = false; }
  return assert(ok, "frames must be < base for 24/25/30; other bases are Err");
}

fn t11() -> TestResult {
  let e1 = "001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  let e2 = "001 BL A C 00:00:01:00 00:00:02:00 00:00:01:00 00:00:02:00\n";
  var ok = parse_err_is(e1 + e2, 25, "edl: event number out of order: 001 BL A C 00:00:01:00 00:00:02:00 00:00:01:00 00:00:02:00");
  let e0 = "002 BL A C 00:00:01:00 00:00:02:00 00:00:01:00 00:00:02:00\n";
  let e9 = "001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  if !parse_err_prefix(e0 + e9, 25, "edl: event number out of order: ") { ok = false; }
  let r = edl_parse(e1 + "003 BL A C 00:00:01:00 00:00:02:00 00:00:01:00 00:00:02:00\n", 25);
  match r {
    Ok(d) => {
      if edl_event_count(&d) != 2 { ok = false; }
      if edl_event_number(&d, 1) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "event numbers must be strictly increasing; gaps are allowed");
}

fn t12() -> TestResult {
  let doc = "\r\nTITLE  Spaced  Title \r\n*note one\r\n; note two\r\n007 AX V C 00:00:00:00 00:00:05:00 01:00:00:00 01:00:05:00\r\n* mid\r\n008 BL V D 5 01:00:00:00 01:00:02:00 02:00:00:00 02:00:02:00\r\n009 AX A2 W007 00:00:00:00 00:00:01:00 02:00:02:00 02:00:03:00\r\n";
  let r = edl_parse(doc, 25);
  var ok = false;
  match r {
    Ok(d) => {
      let got = edl_emit(&d);
      let want = "TITLE Spaced  Title\n*note one\n; note two\n007 AX V C 00:00:00:00 00:00:05:00 01:00:00:00 01:00:05:00\n* mid\n008 BL V D 005 01:00:00:00 01:00:02:00 02:00:00:00 02:00:02:00\n009 AX A2 W007 00:00:00:00 00:00:01:00 02:00:02:00 02:00:03:00\n";
      ok = streq(got, want);
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emission: single spaces, LF, 3-digit numbers/durations/codes");
}

fn t13() -> TestResult {
  let doc = "TITLE RT\r\n\r\n001 AX V C 00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00\r\n* c\r\n* c2\r\n002 AX AA D 250 00:00:01:00 00:00:03:12 01:00:01:00 01:00:03:12\r\n003 BL V W500 00:00:00:00 00:00:02:00 01:00:03:12 01:00:05:12";
  let r1 = edl_parse(doc, 25);
  var ok = false;
  match r1 {
    Ok(p1) => {
      let s1 = edl_emit(&p1);
      let r2 = edl_parse(s1, 25);
      match r2 {
        Ok(p2) => {
          ok = same_edl(&p1, &p2);
          let s2 = edl_emit(&p2);
          if !streq(s1, s2) { ok = false; }
          if edl_line_count(&p2) != edl_line_count(&p1) { ok = false; }
          if edl_event_count(&p2) != 3 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse round trip; emission is idempotent");
}

fn t14() -> TestResult {
  let r = edl_parse("TITLE T\n001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25);
  var ok = false;
  match r {
    Ok(d) => {
      ok = edl_line_kind(&d, -1) == -1;
      if edl_line_kind(&d, 99) != -1 { ok = false; }
      if !streq(edl_line_text(&d, -1), "") { ok = false; }
      if !streq(edl_line_text(&d, 99), "") { ok = false; }
      if edl_event_number(&d, -1) != -1 { ok = false; }
      if edl_event_number(&d, 5) != -1 { ok = false; }
      if edl_event_transition(&d, 5) != -1 { ok = false; }
      if edl_event_duration(&d, -2) != -1 { ok = false; }
      if edl_event_wipe(&d, 5) != -1 { ok = false; }
      if edl_event_line(&d, 5) != -1 { ok = false; }
      if !streq(edl_event_reel(&d, 5), "") { ok = false; }
      if !streq(edl_event_track(&d, -1), "") { ok = false; }
      if !streq(edl_event_src_in(&d, 5), "") { ok = false; }
      if !streq(edl_event_timecode(&d, 0, 99), "") { ok = false; }
      if edl_event_timecode_value(&d, 0, 99) != -1 { ok = false; }
      if edl_event_timecode_value(&d, 5, TC_SRC_IN) != -1 { ok = false; }
      if edl_timecode_part(-1, TCF_HH) != -1 { ok = false; }
      if edl_timecode_part(0, 99) != -1 { ok = false; }
      if edl_timecode_part(0, -1) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = edl_parse("001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 24);
  match r2 {
    Ok(d2) => {
      if !streq(edl_title(&d2), "") { ok = false; }
      if edl_title_count(&d2) != 0 { ok = false; }
      if edl_comment_count(&d2) != 0 { ok = false; }
      if edl_frame_base(&d2) != 24 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return documented sentinels");
}

fn t15() -> TestResult {
  var ok = false;
  let r = edl_parse("", 25);
  match r {
    Ok(d) => {
      ok = edl_line_count(&d) == 0;
      if edl_event_count(&d) != 0 { ok = false; }
      if edl_title_count(&d) != 0 { ok = false; }
      if edl_comment_count(&d) != 0 { ok = false; }
      if !streq(edl_title(&d), "") { ok = false; }
      if !streq(edl_emit(&d), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = edl_parse("\r\n \t\r\n\n", 24);
  match r2 {
    Ok(d2) => {
      if edl_line_count(&d2) != 0 { ok = false; }
      if !streq(edl_emit(&d2), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and blank-only documents");
}

fn t16() -> TestResult {
  var ok = parse_err_is("FCM: NON-DROP FRAME\n", 25, "edl: unexpected line: FCM: NON-DROP FRAME");
  if !parse_err_is("hello\n", 25, "edl: unexpected line: hello") { ok = false; }
  if !parse_err_is("TITLEX x\n", 25, "edl: unexpected line: TITLEX x") { ok = false; }
  if !parse_err_is("title x\n", 25, "edl: unexpected line: title x") { ok = false; }
  if !parse_err_is("# comment\n", 25, "edl: unexpected line: # comment") { ok = false; }
  if !parse_err_is("TITLE\n", 25, "edl: bad TITLE: TITLE") { ok = false; }
  if !parse_err_is("TITLE   \n", 25, "edl: bad TITLE: TITLE") { ok = false; }
  return assert(ok, "unexpected lines and title-less TITLE are Err; FCM is outside the subset");
}

fn t17() -> TestResult {
  let tcs = " 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
  var ok = parse_err_is("001 AX V\n", 25, "edl: missing field: 001 AX V");
  if !parse_err_is("001 AX V C\n", 25, "edl: missing field: 001 AX V C") { ok = false; }
  if !parse_err_is("001 AX V C 00:00:00:00\n", 25, "edl: missing field: 001 AX V C 00:00:00:00") { ok = false; }
  if !parse_err_is("001 AX V D 030\n", 25, "edl: missing field: 001 AX V D 030") { ok = false; }
  if !parse_err_prefix("001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00 EXTRA\n", 25, "edl: trailing text: ") { ok = false; }
  if !parse_err_prefix("001 AX V C 030 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25, "edl: trailing text: ") { ok = false; }
  if !parse_err_prefix("001 AX V D 030 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00 99\n", 25, "edl: trailing text: ") { ok = false; }
  let r = edl_parse("001 AX V C" + tcs, 25);
  match r {
    Ok(d) => {
      if edl_event_count(&d) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "truncated event lines are missing-field Err; surplus tokens are Err");
}

fn t18() -> TestResult {
  let doc = "TITLE First Title\nTITLE  Second  Title\n*keep   spacing  \n;  leading semicolon text\n001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n* trailing comment\n";
  let r = edl_parse(doc, 25);
  var ok = false;
  match r {
    Ok(d) => {
      ok = edl_title_count(&d) == 2;
      if !streq(edl_title(&d), "First Title") { ok = false; }
      if !streq(edl_line_text(&d, 1), "Second  Title") { ok = false; }
      if !streq(edl_line_text(&d, 2), "*keep   spacing") { ok = false; }
      if !streq(edl_line_text(&d, 3), ";  leading semicolon text") { ok = false; }
      if !streq(edl_line_text(&d, 5), "* trailing comment") { ok = false; }
      if edl_line_count(&d) != 6 { ok = false; }
      let got = edl_emit(&d);
      let want = "TITLE First Title\nTITLE Second  Title\n*keep   spacing\n;  leading semicolon text\n001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n* trailing comment\n";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "titles and comments keep raw text (modulo line trim) and document order");
}

fn t19() -> TestResult {
  let doc = "* head\n001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n* mid\n002 AX V C 00:00:01:00 00:00:02:00 00:00:01:00 00:00:02:00\n* tail\n";
  let r = edl_parse(doc, 25);
  var ok = false;
  match r {
    Ok(d) => {
      ok = edl_line_count(&d) == 5;
      if edl_line_kind(&d, 0) != LK_COMMENT { ok = false; }
      if edl_line_kind(&d, 1) != LK_EVENT { ok = false; }
      if edl_line_kind(&d, 2) != LK_COMMENT { ok = false; }
      if edl_line_kind(&d, 3) != LK_EVENT { ok = false; }
      if edl_line_kind(&d, 4) != LK_COMMENT { ok = false; }
      if edl_event_count(&d) != 2 { ok = false; }
      if edl_comment_count(&d) != 3 { ok = false; }
      if edl_event_line(&d, 0) != 1 { ok = false; }
      if edl_event_line(&d, 1) != 3 { ok = false; }
      if !streq(edl_line_text(&d, 4), "* tail") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments may appear anywhere; event ordinals map to stream lines");
}

fn t20() -> TestResult {
  let doc = "001 AX V C 01:02:03:04 02:03:04:05 03:04:05:06 04:05:06:29\n";
  let r = edl_parse(doc, 30);
  var ok = false;
  match r {
    Ok(d) => {
      let vin = edl_event_timecode_value(&d, 0, TC_SRC_IN);
      let vout = edl_event_timecode_value(&d, 0, TC_SRC_OUT);
      let rin = edl_event_timecode_value(&d, 0, TC_REC_IN);
      let rout = edl_event_timecode_value(&d, 0, TC_REC_OUT);
      ok = vin == 1020304;
      if vout != 2030405 { ok = false; }
      if rin != 3040506 { ok = false; }
      if rout != 4050629 { ok = false; }
      if edl_timecode_part(vin, TCF_HH) != 1 { ok = false; }
      if edl_timecode_part(vin, TCF_MM) != 2 { ok = false; }
      if edl_timecode_part(vin, TCF_SS) != 3 { ok = false; }
      if edl_timecode_part(vin, TCF_FF) != 4 { ok = false; }
      if !streq(edl_event_timecode(&d, 0, TC_REC_OUT), "04:05:06:29") { ok = false; }
      if !streq(edl_event_timecode(&d, 0, TC_SRC_IN), edl_event_src_in(&d, 0)) { ok = false; }
      if !streq(edl_event_timecode(&d, 0, TC_SRC_OUT), edl_event_src_out(&d, 0)) { ok = false; }
      if !streq(edl_event_timecode(&d, 0, TC_REC_IN), edl_event_rec_in(&d, 0)) { ok = false; }
      if !streq(edl_timecode(1, 2, 3, 4), "01:02:03:04") { ok = false; }
      if !streq(edl_timecode(99, 59, 59, 29), "99:59:59:29") { ok = false; }
      if !streq(edl_timecode(100, 0, 0, 7), "99:00:00:07") { ok = false; }
      if EDL_FPS_24 != 24 { ok = false; }
      if EDL_FPS_25 != 25 { ok = false; }
      if EDL_FPS_30 != 30 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "packed timecode values, components and canonical formatting");
}

fn t21() -> TestResult {
  let doc = "001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n002 BL A D 1 00:00:01:00 00:00:02:00 00:00:01:00 00:00:02:00\n";
  let r = edl_parse(doc, 25);
  var ok = false;
  match r {
    Ok(d) => {
      let got = edl_emit(&d);
      let want = "001 AX V C 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n002 BL A D 001 00:00:01:00 00:00:02:00 00:00:01:00 00:00:02:00\n";
      ok = streq(got, want);
      let r2 = edl_parse(got, 25);
      match r2 {
        Ok(d2) => {
          if !same_edl(&d, &d2) { ok = false; }
          if edl_event_number(&d2, 0) != 1 { ok = false; }
          if edl_event_duration(&d2, 1) != 1 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "minimum event number and duration emit as 3 digits and re-parse");
}

fn t22() -> TestResult {
  let r = edl_parse("* note\nTITLE Mixed\n001 AX V W001 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n", 25);
  var ok = false;
  match r {
    Ok(d) => {
      ok = edl_comment_count(&d) == 1;
      if !streq(edl_line_text(&d, 0), "* note") { ok = false; }
      if !streq(edl_line_text(&d, 1), "Mixed") { ok = false; }
      if edl_line_kind(&d, 2) != LK_EVENT { ok = false; }
      if edl_event_wipe(&d, 0) != 1 { ok = false; }
      if edl_event_transition(&d, 0) != TR_WIPE { ok = false; }
      if edl_event_duration(&d, 0) != 0 { ok = false; }
      let got = edl_emit(&d);
      let want = "* note\nTITLE Mixed\n001 AX V W001 00:00:00:00 00:00:01:00 00:00:00:00 00:00:01:00\n";
      if !streq(got, want) { ok = false; }
      let r2 = edl_parse(got, 25);
      match r2 {
        Ok(d2) => {
          if !same_edl(&d, &d2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "wipe pass-through and a comment/title/event document round trip");
}

fn main() -> Int {
  io.println("=== xiom.edl conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.edl: all tests passed");
  } else {
    io.println("xiom.edl: tests failed");
  }
  return failed;
}
