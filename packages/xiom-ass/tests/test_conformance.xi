// XIOM -- xiom.ass conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: canonical document parsing with exact
// centisecond times, the default Events format, a custom Format mapping by
// name, first-match field lookup, comments, timestamps (values, digits and
// the shape/range errors), the Events timestamp validation, the script-info
// key/value catalog, dialogue/comment/style-before-Format policies, the
// bad-Format catalog, field count mismatch, extra commas kept in the raw
// last field, raw other sections and canonical section ordering, CRLF and
// header normalization, round-trips, UTF-8/`\N`/override-block raw text,
// field-by-position accessors, a Format without Start/End, the structural
// error catalog (empty input, text before the first section, unterminated and
// bad section names, control bytes), missing [Events] and accessor
// sentinels.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from Vec[Str] lowers to a pointer comparison), and every
// element read goes through a typed local.

module ass_tests
use xiom.io; use xiom.test; use xiom.ass;
use xiom.string.compare;

// Canonical three-section document. ass_format of the parsed value
// reproduces this exact text (tests t17 and t22 use it).
fn canon_doc() -> Str {
  return "[Script Info]\n; comment line\nTitle: Conformance\nScriptType: v4.00+\n\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize\nStyle: Default,Arial,20\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.50,Default,,0,0,0,,Hello, world!\nComment: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,A comment\n";
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_ass_is(r: Result[Ass, Str], want: Str) -> Bool {
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

// Structural comparison of two parsed values: equal section counts and
// byte-equal canonical forms (the formatter writes every stored raw line, so
// equal output plus equal section count pins the stored bytes).
fn same_ass(a: &Ass, b: &Ass) -> Bool {
  if ass_section_count(a) != ass_section_count(b) { return false; }
  let fa: Str = ass_format(a);
  let fb: Str = ass_format(b);
  return streq(fa, fb);
}

// One-event document with the given body after "Dialogue:".
fn one_event(body: Str) -> Str {
  return "[Events]\n" + body + "\n";
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let r = ass_parse(canon_doc());
  if !r.is_ok { return assert(false, "events parse: counts, kinds, times, text and style"); }
  let a: Ass = r.value;
  var ok = ass_section_count(&a) == 3;
  if ass_section_kind(&a, 0) != 0 { ok = false; }
  if ass_section_kind(&a, 1) != 1 { ok = false; }
  if ass_section_kind(&a, 2) != 2 { ok = false; }
  if ass_event_count(&a) != 2 { ok = false; }
  if ass_dialogue_count(&a) != 1 { ok = false; }
  if ass_comment_count(&a) != 1 { ok = false; }
  if ass_event_kind(&a, 0) != 0 { ok = false; }
  if ass_event_kind(&a, 1) != 1 { ok = false; }
  if ass_event_start_cs(&a, 0) != 100 { ok = false; }
  if ass_event_end_cs(&a, 0) != 250 { ok = false; }
  if ass_event_start_cs(&a, 1) != 300 { ok = false; }
  if ass_event_end_cs(&a, 1) != 400 { ok = false; }
  let txt: Str = ass_event_text(&a, 0);
  if !streq(txt, "Hello, world!") { ok = false; }
  let sty: Str = ass_event_style(&a, 0);
  if !streq(sty, "Default") { ok = false; }
  let lyr: Str = ass_event_field(&a, 0, "Layer");
  if !streq(lyr, "0") { ok = false; }
  let nm: Str = ass_event_field(&a, 0, "Name");
  if !streq(nm, "") { ok = false; }
  let txt2: Str = ass_event_text(&a, 1);
  if !streq(txt2, "A comment") { ok = false; }
  if ass_event_field_count(&a, 0) != 10 { ok = false; }
  return assert(ok, "events parse: counts, kinds, times, text and style");
}

fn t2() -> TestResult {
  let doc = "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,One\nComment: 0,0:00:03.00,0:00:03.50,,,0,0,0,,Two\n";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "default Events mapping applies when Format is absent"); }
  let a: Ass = r.value;
  var ok = ass_section_count(&a) == 1;
  if ass_format_field_count(&a, 0) != 10 { ok = false; }
  let f0: Str = ass_format_field(&a, 0, 0);
  let f1: Str = ass_format_field(&a, 0, 1);
  let f9: Str = ass_format_field(&a, 0, 9);
  if !streq(f0, "Layer") { ok = false; }
  if !streq(f1, "Start") { ok = false; }
  if !streq(f9, "Text") { ok = false; }
  if ass_event_start_cs(&a, 0) != 100 { ok = false; }
  if ass_event_end_cs(&a, 0) != 200 { ok = false; }
  if ass_event_start_cs(&a, 1) != 300 { ok = false; }
  if ass_event_end_cs(&a, 1) != 350 { ok = false; }
  let txt: Str = ass_event_text(&a, 0);
  let txt2: Str = ass_event_text(&a, 1);
  if !streq(txt, "One") { ok = false; }
  if !streq(txt2, "Two") { ok = false; }
  let f: Str = ass_format(&a);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "default Events mapping applies when Format is absent");
}

fn t3() -> TestResult {
  let doc = "[Events]\nFormat: End, Start, Style, Text\nDialogue: 0:00:09.00,0:00:08.00,Alt,Hi there\n";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "custom Format maps Start/End/Style/Text by name"); }
  let a: Ass = r.value;
  var ok = ass_format_field_count(&a, 0) == 4;
  let f0: Str = ass_format_field(&a, 0, 0);
  let f1: Str = ass_format_field(&a, 0, 1);
  if !streq(f0, "End") { ok = false; }
  if !streq(f1, "Start") { ok = false; }
  if ass_event_start_cs(&a, 0) != 800 { ok = false; }
  if ass_event_end_cs(&a, 0) != 900 { ok = false; }
  let sty: Str = ass_event_style(&a, 0);
  if !streq(sty, "Alt") { ok = false; }
  let txt: Str = ass_event_text(&a, 0);
  if !streq(txt, "Hi there") { ok = false; }
  let endv: Str = ass_event_field(&a, 0, "End");
  if !streq(endv, "0:00:09.00") { ok = false; }
  let at0: Str = ass_event_field_at(&a, 0, 0);
  if !streq(at0, "0:00:09.00") { ok = false; }
  let f: Str = ass_format(&a);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "custom Format maps Start/End/Style/Text by name");
}

fn t4() -> TestResult {
  let doc = "[Events]\nFormat: Start, End, Text, Text\nDialogue: 0:00:01.00,0:00:02.00,first,second\n";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "duplicate field names: first match wins"); }
  let a: Ass = r.value;
  var ok = ass_event_field_count(&a, 0) == 4;
  if ass_event_start_cs(&a, 0) != 100 { ok = false; }
  if ass_event_end_cs(&a, 0) != 200 { ok = false; }
  let txt: Str = ass_event_text(&a, 0);
  if !streq(txt, "first") { ok = false; }
  let at2: Str = ass_event_field_at(&a, 0, 2);
  let at3: Str = ass_event_field_at(&a, 0, 3);
  if !streq(at2, "first") { ok = false; }
  if !streq(at3, "second") { ok = false; }
  return assert(ok, "duplicate field names: first match wins");
}

fn t5() -> TestResult {
  var ok = ok_int(ass_parse_timestamp("0:00:00.00")) == 0;
  if ok_int(ass_parse_timestamp("0:00:00.01")) != 1 { ok = false; }
  if ok_int(ass_parse_timestamp("1:02:03.45")) != 372345 { ok = false; }
  if ok_int(ass_parse_timestamp("9:59:59.99")) != 3599999 { ok = false; }
  let f0: Str = ass_format_timestamp(0);
  let f1: Str = ass_format_timestamp(372345);
  let f2: Str = ass_format_timestamp(-7);
  let f3: Str = ass_format_timestamp(3599999);
  let f4: Str = ass_format_timestamp(3600000);
  if !streq(f0, "0:00:00.00") { ok = false; }
  if !streq(f1, "1:02:03.45") { ok = false; }
  if !streq(f2, "0:00:00.00") { ok = false; }
  if !streq(f3, "9:59:59.99") { ok = false; }
  if !streq(f4, "10:00:00.00") { ok = false; }
  if !err_int_is(ass_parse_timestamp("00:00:00.00"), "ass: bad timestamp shape") { ok = false; }
  if !err_int_is(ass_parse_timestamp("0:0:00.00"), "ass: bad timestamp shape") { ok = false; }
  if !err_int_is(ass_parse_timestamp("0:00:0.00"), "ass: bad timestamp shape") { ok = false; }
  if !err_int_is(ass_parse_timestamp("0:00:00.0"), "ass: bad timestamp shape") { ok = false; }
  if !err_int_is(ass_parse_timestamp("0:00:00:00"), "ass: bad timestamp shape") { ok = false; }
  if !err_int_is(ass_parse_timestamp(""), "ass: bad timestamp shape") { ok = false; }
  if !err_int_is(ass_parse_timestamp("0:60:00.00"), "ass: timestamp out of range") { ok = false; }
  if !err_int_is(ass_parse_timestamp("0:00:61.00"), "ass: timestamp out of range") { ok = false; }
  return assert(ok, "timestamp digit policy, values and error catalog");
}

fn t6() -> TestResult {
  let badshape = one_event("Dialogue: 0,0:00:1.00,0:00:02.00,S,,0,0,0,,x");
  let badrange = one_event("Dialogue: 0,0:60:00.00,0:00:02.00,S,,0,0,0,,x");
  let badend = one_event("Comment: 0,0:00:01.00,0:00:02.0,S,,0,0,0,,x");
  var ok = err_ass_is(ass_parse(badshape), "ass: bad timestamp shape");
  if !err_ass_is(ass_parse(badrange), "ass: timestamp out of range") { ok = false; }
  if !err_ass_is(ass_parse(badend), "ass: bad timestamp shape") { ok = false; }
  return assert(ok, "Dialogue/Comment Start and End timestamps are validated");
}

fn t7() -> TestResult {
  let dlg = "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\nFormat: Start, End, Text\n";
  let cmt = "[Events]\nComment: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\nFormat: Start, End, Text\n";
  var ok = err_ass_is(ass_parse(dlg), "ass: dialogue before Format");
  if !err_ass_is(ass_parse(cmt), "ass: comment before Format") { ok = false; }
  return assert(ok, "event rows before the Format line are rejected");
}

fn t8() -> TestResult {
  let after = "[V4+ Styles]\nStyle: Default,Arial\nFormat: Name, Fontname\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let none = "[V4 Styles]\nStyle: Default,Arial,20\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  var ok = err_ass_is(ass_parse(after), "ass: style before Format");
  if !err_ass_is(ass_parse(none), "ass: style before Format") { ok = false; }
  return assert(ok, "Style rows need their section's Format declaration");
}

fn t9() -> TestResult {
  let empty = "[V4+ Styles]\nFormat:\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let gap = "[V4+ Styles]\nFormat: Name,,Fontsize\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let dup = "[V4+ Styles]\nFormat: Name\nFormat: Fontname\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  var ok = err_ass_is(ass_parse(empty), "ass: bad Format");
  if !err_ass_is(ass_parse(gap), "ass: bad Format") { ok = false; }
  if !err_ass_is(ass_parse(dup), "ass: bad Format") { ok = false; }
  return assert(ok, "empty, gapped and duplicated Format declarations are bad Format");
}

fn t10() -> TestResult {
  let style_short = "[V4+ Styles]\nFormat: Name, Fontname, Fontsize\nStyle: Default,Arial\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let event_short = one_event("Dialogue: 0,0:00:01.00,0:00:02.00,S");
  let event_ok = one_event("Dialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,a,b,c");
  var ok = err_ass_is(ass_parse(style_short), "ass: field count mismatch");
  if !err_ass_is(ass_parse(event_short), "ass: field count mismatch") { ok = false; }
  let r = ass_parse(event_ok);
  if !r.is_ok {
    ok = false;
  } else {
    let a: Ass = r.value;
    let txt: Str = ass_event_text(&a, 0);
    if !streq(txt, "a,b,c") { ok = false; }
  }
  return assert(ok, "field count is validated; extra commas stay in the last field");
}

fn t11() -> TestResult {
  let noevents = "[Script Info]\nTitle: x\n";
  var ok = err_ass_is(ass_parse(noevents), "ass: missing [Events]");
  if !err_ass_is(ass_parse(""), "ass: empty input") { ok = false; }
  if !err_ass_is(ass_parse("\n\n"), "ass: empty input") { ok = false; }
  if !err_ass_is(ass_parse("\r\n\r\n"), "ass: empty input") { ok = false; }
  return assert(ok, "a document needs an [Events] section; blank-only input is empty");
}

fn t12() -> TestResult {
  let unterminated = "[Events\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let empty_name = "[]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let trailing = "[Events]x\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let before = "Title: x\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  var ok = err_ass_is(ass_parse(unterminated), "ass: unterminated section name");
  if !err_ass_is(ass_parse(empty_name), "ass: bad section name") { ok = false; }
  if !err_ass_is(ass_parse(trailing), "ass: bad section name") { ok = false; }
  if !err_ass_is(ass_parse(before), "ass: text before first section") { ok = false; }
  return assert(ok, "section header shape and text before the first section");
}

fn t13() -> TestResult {
  let ctl = one_event("Dialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,a\u{0001}b");
  let del = "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\u{007F}y\n";
  let tab = "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,a\tb\n";
  var ok = err_ass_is(ass_parse(ctl), "ass: control byte");
  if !err_ass_is(ass_parse(del), "ass: control byte") { ok = false; }
  let r = ass_parse(tab);
  if !r.is_ok {
    ok = false;
  } else {
    let a: Ass = r.value;
    let txt: Str = ass_event_text(&a, 0);
    if !streq(txt, "a\tb") { ok = false; }
  }
  return assert(ok, "C0 bytes and DEL are rejected; TAB is text");
}

fn t14() -> TestResult {
  let doc = "[Script Info]\n; comment\nTitle: First\nTitle: Second\nPlayResX: 640\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "Script Info keys and values are preserved with first-match"); }
  let a: Ass = r.value;
  var ok = ass_info_count(&a) == 3;
  let k0: Str = ass_info_key(&a, 0);
  let v0: Str = ass_info_value(&a, 0);
  let k2: Str = ass_info_key(&a, 2);
  let v2: Str = ass_info_value(&a, 2);
  if !streq(k0, "Title") { ok = false; }
  if !streq(v0, "First") { ok = false; }
  if !streq(k2, "PlayResX") { ok = false; }
  if !streq(v2, "640") { ok = false; }
  let first: Str = ass_info_value_by_key(&a, "Title");
  if !streq(first, "First") { ok = false; }
  let missing: Str = ass_info_value_by_key(&a, "Nope");
  if !streq(missing, "") { ok = false; }
  let badline = "[Script Info]\njust text\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let emptykey = "[Script Info]\n: value\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  if !err_ass_is(ass_parse(badline), "ass: bad script info line") { ok = false; }
  if !err_ass_is(ass_parse(emptykey), "ass: bad script info line") { ok = false; }
  return assert(ok, "Script Info keys and values are preserved with first-match");
}

fn t15() -> TestResult {
  let doc = "[Fonts]\nfontname: X\n; raw line\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,Hi\n";
  let want = "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,Hi\n[Fonts]\nfontname: X\n; raw line\n";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "other sections stay raw and sections emit in kind order"); }
  let a: Ass = r.value;
  var ok = ass_section_count(&a) == 2;
  if ass_section_kind(&a, 0) != 3 { ok = false; }
  if ass_section_kind(&a, 1) != 2 { ok = false; }
  let n0: Str = ass_section_name(&a, 0);
  if !streq(n0, "Fonts") { ok = false; }
  if ass_section_line_count(&a, 0) != 2 { ok = false; }
  let l0: Str = ass_section_line(&a, 0, 0);
  let l1: Str = ass_section_line(&a, 0, 1);
  if !streq(l0, "fontname: X") { ok = false; }
  if !streq(l1, "; raw line") { ok = false; }
  let f: Str = ass_format(&a);
  if !streq(f, want) { ok = false; }
  let r2 = ass_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let b: Ass = r2.value;
    if !same_ass(&a, &b) { ok = false; }
  }
  return assert(ok, "other sections stay raw and sections emit in kind order");
}

fn t16() -> TestResult {
  let doc = "\r\n[ Script Info ]\r\nTitle: T\r\n[ Events ] \t\r\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\r\n";
  let want = "[Script Info]\nTitle: T\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,x\n";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "CRLF, padded headers and leading blanks normalize to LF"); }
  let a: Ass = r.value;
  var ok = ass_section_count(&a) == 2;
  let n0: Str = ass_section_name(&a, 0);
  let n1: Str = ass_section_name(&a, 1);
  if !streq(n0, "Script Info") { ok = false; }
  if !streq(n1, "Events") { ok = false; }
  let f: Str = ass_format(&a);
  if !streq(f, want) { ok = false; }
  return assert(ok, "CRLF, padded headers and leading blanks normalize to LF");
}

fn t17() -> TestResult {
  let r = ass_parse(canon_doc());
  if !r.is_ok { return assert(false, "canonical documents round-trip parse -> format -> parse"); }
  let a: Ass = r.value;
  let f: Str = ass_format(&a);
  var ok = streq(f, canon_doc());
  let r2 = ass_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let b: Ass = r2.value;
    if !same_ass(&a, &b) { ok = false; }
    let f2: Str = ass_format(&b);
    if !streq(f2, canon_doc()) { ok = false; }
  }
  return assert(ok, "canonical documents round-trip parse -> format -> parse");
}

fn t18() -> TestResult {
  let r = ass_parse(canon_doc());
  if !r.is_ok { return assert(false, "accessors return sentinels out of range"); }
  let a: Ass = r.value;
  var ok = true;
  let sn_lo: Str = ass_section_name(&a, -1);
  let sn_hi: Str = ass_section_name(&a, 9);
  if !streq(sn_lo, "") { ok = false; }
  if !streq(sn_hi, "") { ok = false; }
  if ass_section_kind(&a, -1) != -1 { ok = false; }
  if ass_section_kind(&a, 9) != -1 { ok = false; }
  if ass_section_line_count(&a, -1) != 0 { ok = false; }
  if ass_section_line_count(&a, 9) != 0 { ok = false; }
  let sl_lo: Str = ass_section_line(&a, 0, -1);
  let sl_hi: Str = ass_section_line(&a, 0, 99);
  if !streq(sl_lo, "") { ok = false; }
  if !streq(sl_hi, "") { ok = false; }
  if ass_format_field_count(&a, -1) != 0 { ok = false; }
  if ass_format_field_count(&a, 9) != 0 { ok = false; }
  let ff_lo: Str = ass_format_field(&a, 0, -1);
  let ff_hi: Str = ass_format_field(&a, 0, 99);
  if !streq(ff_lo, "") { ok = false; }
  if !streq(ff_hi, "") { ok = false; }
  if ass_info_count(&a) != 2 { ok = false; }
  let ik_lo: Str = ass_info_key(&a, -1);
  let iv_hi: Str = ass_info_value(&a, 9);
  if !streq(ik_lo, "") { ok = false; }
  if !streq(iv_hi, "") { ok = false; }
  let ibk: Str = ass_info_value_by_key(&a, "Missing");
  if !streq(ibk, "") { ok = false; }
  if ass_style_count(&a) != 1 { ok = false; }
  if ass_style_field_count(&a, -1) != 0 { ok = false; }
  let sf_lo: Str = ass_style_field_at(&a, -1, 0);
  let sf_hi: Str = ass_style_field_at(&a, 0, 99);
  let sf_nm: Str = ass_style_field(&a, 0, "Nope");
  if !streq(sf_lo, "") { ok = false; }
  if !streq(sf_hi, "") { ok = false; }
  if !streq(sf_nm, "") { ok = false; }
  if ass_event_kind(&a, -1) != -1 { ok = false; }
  if ass_event_kind(&a, 9) != -1 { ok = false; }
  if ass_event_start_cs(&a, -1) != -1 { ok = false; }
  if ass_event_end_cs(&a, 9) != -1 { ok = false; }
  if ass_event_field_count(&a, -1) != 0 { ok = false; }
  let ef_lo: Str = ass_event_field_at(&a, -1, 0);
  let ef_hi: Str = ass_event_field_at(&a, 0, 99);
  let ef_nm: Str = ass_event_field(&a, 0, "Nope");
  let et_hi: Str = ass_event_text(&a, 9);
  let es_hi: Str = ass_event_style(&a, 9);
  if !streq(ef_lo, "") { ok = false; }
  if !streq(ef_hi, "") { ok = false; }
  if !streq(ef_nm, "") { ok = false; }
  if !streq(et_hi, "") { ok = false; }
  if !streq(es_hi, "") { ok = false; }
  return assert(ok, "accessors return sentinels out of range");
}

fn t19() -> TestResult {
  let doc = "[V4+ Styles]\nFormat: Name, Fontname\nStyle: A,x\n[V4 Styles]\nFormat: Name, Fontname, Encoding\nStyle: B,y,1\n[Events]\nFormat: Start, End, Text\nDialogue: 0:00:01.00,0:00:02.00,one\n[Events]\nFormat: Layer, Start, End, Text\nDialogue: 5,0:00:03.00,0:00:04.00,two\n";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "multiple same-kind sections aggregate with per-section Formats"); }
  let a: Ass = r.value;
  var ok = ass_section_count(&a) == 4;
  if ass_style_count(&a) != 2 { ok = false; }
  if ass_format_field_count(&a, 0) != 2 { ok = false; }
  if ass_format_field_count(&a, 1) != 3 { ok = false; }
  let s0: Str = ass_style_field(&a, 0, "Fontname");
  let s1: Str = ass_style_field(&a, 1, "Encoding");
  if !streq(s0, "x") { ok = false; }
  if !streq(s1, "1") { ok = false; }
  let name1: Str = ass_style_field(&a, 1, "Name");
  if !streq(name1, "B") { ok = false; }
  if ass_event_count(&a) != 2 { ok = false; }
  if ass_event_start_cs(&a, 0) != 100 { ok = false; }
  if ass_event_start_cs(&a, 1) != 300 { ok = false; }
  let lyr: Str = ass_event_field(&a, 1, "Layer");
  let t2: Str = ass_event_text(&a, 1);
  if !streq(lyr, "5") { ok = false; }
  if !streq(t2, "two") { ok = false; }
  if ass_format_field_count(&a, 2) != 3 { ok = false; }
  if ass_format_field_count(&a, 3) != 4 { ok = false; }
  return assert(ok, "multiple same-kind sections aggregate with per-section Formats");
}

fn t20() -> TestResult {
  let names = Vec[Str].new();
  names.push("Events");
  let kinds = Vec[Int].new();
  let starts = Vec[Int].new();
  let ends = Vec[Int].new();
  let lines = Vec[Str].new();
  let a = Ass{
    section_names: names;
    section_kinds: kinds;
    section_starts: starts;
    section_ends: ends;
    section_lines: lines;
    section_fmt_starts: Vec[Int].new();
    section_fmt_ends: Vec[Int].new();
    format_fields: Vec[Str].new();
    info_keys: Vec[Str].new();
    info_values: Vec[Str].new();
    style_sections: Vec[Int].new();
    style_starts: Vec[Int].new();
    style_ends: Vec[Int].new();
    style_fields: Vec[Str].new();
    event_kinds: Vec[Int].new();
    event_sections: Vec[Int].new();
    event_starts: Vec[Int].new();
    event_ends: Vec[Int].new();
    event_fstarts: Vec[Int].new();
    event_fends: Vec[Int].new();
    event_fields: Vec[Str].new();
  };
  var ok = ass_section_count(&a) == 0;
  if ass_style_count(&a) != 0 { ok = false; }
  if ass_event_count(&a) != 0 { ok = false; }
  if ass_info_count(&a) != 0 { ok = false; }
  if ass_dialogue_count(&a) != 0 { ok = false; }
  if ass_comment_count(&a) != 0 { ok = false; }
  let f: Str = ass_format(&a);
  if !streq(f, "") { ok = false; }
  let t: Str = ass_event_text(&a, 0);
  if !streq(t, "") { ok = false; }
  return assert(ok, "drifted vectors are clamped, never read out of bounds");
}

fn t21() -> TestResult {
  let doc = "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,S,,0,0,0,,héllo \\N世界 {\\i1}naïve{\\i0} ✓\n";
  let want = "héllo \\N世界 {\\i1}naïve{\\i0} ✓";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "UTF-8, \\N escapes and override blocks are raw bytes"); }
  let a: Ass = r.value;
  let txt: Str = ass_event_text(&a, 0);
  var ok = streq(txt, want);
  let f: Str = ass_format(&a);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "UTF-8, \\N escapes and override blocks are raw bytes");
}

fn t22() -> TestResult {
  let r = ass_parse(canon_doc());
  if !r.is_ok { return assert(false, "field-by-position accessors expose the raw split"); }
  let a: Ass = r.value;
  var ok = ass_event_field_count(&a, 0) == 10;
  let e0: Str = ass_event_field_at(&a, 0, 0);
  let e1: Str = ass_event_field_at(&a, 0, 1);
  let e2: Str = ass_event_field_at(&a, 0, 2);
  let e9: Str = ass_event_field_at(&a, 0, 9);
  if !streq(e0, "0") { ok = false; }
  if !streq(e1, "0:00:01.00") { ok = false; }
  if !streq(e2, "0:00:02.50") { ok = false; }
  if !streq(e9, "Hello, world!") { ok = false; }
  if ass_style_field_count(&a, 0) != 3 { ok = false; }
  let s0: Str = ass_style_field_at(&a, 0, 0);
  let s1: Str = ass_style_field_at(&a, 0, 1);
  let s2: Str = ass_style_field_at(&a, 0, 2);
  if !streq(s0, "Default") { ok = false; }
  if !streq(s1, "Arial") { ok = false; }
  if !streq(s2, "20") { ok = false; }
  let snm: Str = ass_style_field(&a, 0, "Name");
  if !streq(snm, "Default") { ok = false; }
  return assert(ok, "field-by-position accessors expose the raw split");
}

fn t23() -> TestResult {
  let doc = "[Events]\nFormat: Layer, Style, Text\nDialogue: 3,Alt,just text\n";
  let r = ass_parse(doc);
  if !r.is_ok { return assert(false, "a Format without Start/End disables timestamp parsing"); }
  let a: Ass = r.value;
  var ok = ass_event_count(&a) == 1;
  if ass_event_start_cs(&a, 0) != -1 { ok = false; }
  if ass_event_end_cs(&a, 0) != -1 { ok = false; }
  let lyr: Str = ass_event_field(&a, 0, "Layer");
  let sty: Str = ass_event_style(&a, 0);
  let txt: Str = ass_event_text(&a, 0);
  if !streq(lyr, "3") { ok = false; }
  if !streq(sty, "Alt") { ok = false; }
  if !streq(txt, "just text") { ok = false; }
  return assert(ok, "a Format without Start/End disables timestamp parsing");
}

fn main() -> Int {
  io.println("=== xiom.ass conformance tests ===");
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
    io.println("xiom.ass: all tests passed");
  } else {
    io.println("xiom.ass: tests failed");
  }
  return failed;
}
