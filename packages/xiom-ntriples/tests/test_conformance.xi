// XIOM -- xiom.ntriples conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API and error catalog: happy paths for IRIs, blank
// nodes and the three literal flavors; escape decoding and canonical
// re-escaping; UCHAR decoding including the surrogate and range errors; line
// ends (LF, CRLF, CR), blank lines and comments; the flat-storage accessors
// and their out-of-range behavior; the nt_add_triple builder; invalid UTF-8;
// and parse -> emit -> parse round trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq and the field readers.

module ntriples_tests
use xiom.io; use xiom.test; use xiom.ntriples;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Raw-byte strings for bytes a source literal cannot spell (C0 controls and
// invalid UTF-8).
fn bytes1(a: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return Str::from_utf8(v);
}

fn bytes2(a: Int, b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

fn bytes4(a: Int, b: Int, c: Int, d: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  return Str::from_utf8(v);
}

fn bytes5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  v.push(e as UInt8);
  return Str::from_utf8(v);
}

// True when `text` parses and yields exactly `n` triples; false otherwise.
fn count_is(text: Str, n: Int) -> Bool {
  let r = nt_parse(text);
  match r {
    Ok(d) => { return nt_triple_count(&d) == n; },
    Err(_) => { return false; },
  };
  return false;
}

// Triple count of `text`, or -1 on error.
fn count_of(text: Str) -> Int {
  let r = nt_parse(text);
  match r {
    Ok(d) => { return nt_triple_count(&d); },
    Err(_) => { return -1; },
  };
  return -1;
}

// True when `text` parses and fails with exactly the error `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = nt_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  };
  return false;
}

// True when `text` parses to exactly one triple whose eight term fields match.
fn trip_is(text: Str, sk: Str, st: Str, pt: Str, okk: Str, ot: Str, ol: Str, dt: Str) -> Bool {
  let r = nt_parse(text);
  match r {
    Ok(d) => {
      if nt_triple_count(&d) != 1 { return false; }
      if !streq(nt_subject_kind(&d, 0), sk) { return false; }
      if !streq(nt_subject_text(&d, 0), st) { return false; }
      if !streq(nt_predicate(&d, 0), pt) { return false; }
      if !streq(nt_object_kind(&d, 0), okk) { return false; }
      if !streq(nt_object_text(&d, 0), ot) { return false; }
      if !streq(nt_object_lang(&d, 0), ol) { return false; }
      if !streq(nt_object_datatype(&d, 0), dt) { return false; }
      return true;
    },
    Err(_) => { return false; },
  };
  return false;
}

// Canonical emission of `text`, or "<err>" when it does not parse.
fn emit_of(text: Str) -> Str {
  let r = nt_parse(text);
  match r {
    Ok(d) => { return nt_emit(&d); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

// Object text at index i, or "<err>".
fn object_text_of(text: Str, i: Int) -> Str {
  let r = nt_parse(text);
  match r {
    Ok(d) => { return nt_object_text(&d, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

// nt_object_has_datatype(&d, 0) for the first triple, false on error.
fn has_dt_of(text: Str) -> Bool {
  let r = nt_parse(text);
  match r {
    Ok(d) => { return nt_object_has_datatype(&d, 0); },
    Err(_) => { return false; },
  };
  return false;
}

// Field-by-field equality of two documents.
fn docs_eq(a: &NtDocument, b: &NtDocument) -> Bool {
  if nt_triple_count(a) != nt_triple_count(b) { return false; }
  var i = 0;
  while i < nt_triple_count(a) {
    if !streq(nt_subject_kind(a, i), nt_subject_kind(b, i)) { return false; }
    if !streq(nt_subject_text(a, i), nt_subject_text(b, i)) { return false; }
    if !streq(nt_predicate(a, i), nt_predicate(b, i)) { return false; }
    if !streq(nt_object_kind(a, i), nt_object_kind(b, i)) { return false; }
    if !streq(nt_object_text(a, i), nt_object_text(b, i)) { return false; }
    if !streq(nt_object_lang(a, i), nt_object_lang(b, i)) { return false; }
    if !streq(nt_object_datatype(a, i), nt_object_datatype(b, i)) { return false; }
    if nt_object_has_datatype(a, i) != nt_object_has_datatype(b, i) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `text` round-trips: parse -> canonical emit -> parse, equal docs.
fn rt_ok(text: Str) -> Bool {
  let r1 = nt_parse(text);
  match r1 {
    Err(_) => { return false; },
    Ok(d1) => {
      let emitted = nt_emit(&d1);
      let r2 = nt_parse(emitted);
      match r2 {
        Err(_) => { return false; },
        Ok(d2) => { return docs_eq(&d1, &d2); },
      };
    },
  };
  return false;
}

// Common prefix used by the single-line error checks: 22 bytes, so the term
// after it starts at byte 22.
fn pre() -> Str {
  return "<http://a> <http://b> ";
}

fn t1() -> TestResult {
  var ok = count_of("") == 0;
  if !count_is("\n", 0) { ok = false; }
  if !count_is("\n\n\r\n", 0) { ok = false; }
  if !count_is("# comment only\n", 0) { ok = false; }
  if !count_is("   \t # indented comment\r\n", 0) { ok = false; }
  if !streq(emit_of(""), "") { ok = false; }
  return assert(ok, "empty document: blank and comment-only input yields zero triples");
}

fn t2() -> TestResult {
  var ok = trip_is("<http://example.org/s> <http://example.org/p> <http://example.org/o> .",
    "iri", "http://example.org/s", "http://example.org/p", "iri", "http://example.org/o", "", "");
  if !trip_is("<http://a>\t<http://b>\t<http://c>\t.",
      "iri", "http://a", "http://b", "iri", "http://c", "", "") { ok = false; }
  if !trip_is("<http://a><http://b><http://c>.",
      "iri", "http://a", "http://b", "iri", "http://c", "", "") { ok = false; }
  let want = "<http://example.org/s> <http://example.org/p> <http://example.org/o> .\n";
  if !streq(emit_of("<http://example.org/s> <http://example.org/p> <http://example.org/o> ."), want) { ok = false; }
  return assert(ok, "IRI triples: spaces, tabs and adjacent terms; canonical single-space emit");
}

fn t3() -> TestResult {
  var ok = trip_is("_:b1 <http://e/p> _:b2 .", "bnode", "b1", "http://e/p", "bnode", "b2", "", "");
  if !trip_is("_:a.b <http://e/p> _:c-d .", "bnode", "a.b", "http://e/p", "bnode", "c-d", "", "") { ok = false; }
  if !trip_is("<http://e/s> <http://e/p> _:end.", "iri", "http://e/s", "http://e/p", "bnode", "end", "", "") { ok = false; }
  let want = "_:b1 <http://e/p> _:b2 .\n";
  if !streq(emit_of("_:b1 <http://e/p> _:b2 ."), want) { ok = false; }
  return assert(ok, "blank nodes: labels with ':' dots and dashes, trailing dot handling");
}

fn t4() -> TestResult {
  let p = pre();
  var ok = trip_is(p + "\"hello world\" .", "iri", "http://a", "http://b", "literal", "hello world", "", "");
  if !trip_is(p + "\"# not a comment\" .", "iri", "http://a", "http://b", "literal", "# not a comment", "", "") { ok = false; }
  if !trip_is(p + "\"\" .", "iri", "http://a", "http://b", "literal", "", "", "") { ok = false; }
  if !trip_is(p + "\"a\\\"b\" .", "iri", "http://a", "http://b", "literal", "a\"b", "", "") { ok = false; }
  return assert(ok, "plain literals: spaces, '#' as data, empty form, escaped quote");
}

fn t5() -> TestResult {
  let p = pre();
  var ok = trip_is(p + "\"chat\"@fr .", "iri", "http://a", "http://b", "literal", "chat", "fr", "");
  if !trip_is(p + "\"chat\"@EN-us .", "iri", "http://a", "http://b", "literal", "chat", "EN-us", "") { ok = false; }
  if !trip_is(p + "\"chat\"@en-419 .", "iri", "http://a", "http://b", "literal", "chat", "en-419", "") { ok = false; }
  let want = p + "\"chat\"@fr .\n";
  if !streq(emit_of(p + "\"chat\"@fr ."), want) { ok = false; }
  return assert(ok, "language-tagged literals: shape, case preservation, emit");
}

fn t6() -> TestResult {
  let p = pre();
  let dt = "http://www.w3.org/2001/XMLSchema#integer";
  var ok = trip_is(p + "\"42\"^^<" + dt + "> .", "iri", "http://a", "http://b", "literal", "42", "", dt);
  if !streq(emit_of(p + "\"42\"^^<" + dt + "> ."), p + "\"42\"^^<" + dt + "> .\n") { ok = false; }
  if !trip_is(p + "\"x\"^^<> .", "iri", "http://a", "http://b", "literal", "x", "", "") { ok = false; }
  if !has_dt_of(p + "\"x\"^^<> .") { ok = false; }
  if !streq(emit_of(p + "\"x\"^^<> ."), p + "\"x\"^^<> .\n") { ok = false; }
  return assert(ok, "datatype literals: xsd:integer, explicit empty datatype round-trips");
}

fn t7() -> TestResult {
  let p = pre();
  var ok = trip_is(p + "\"a\\nb\" .", "iri", "http://a", "http://b", "literal", "a\nb", "", "");
  if !trip_is(p + "\"a\\tb\" .", "iri", "http://a", "http://b", "literal", "a\tb", "", "") { ok = false; }
  if !trip_is(p + "\"a\\rb\" .", "iri", "http://a", "http://b", "literal", "a\rb", "", "") { ok = false; }
  if !trip_is(p + "\"a\\\\b\" .", "iri", "http://a", "http://b", "literal", "a\\b", "", "") { ok = false; }
  if !streq(emit_of(p + "\"a\\nb\" ."), p + "\"a\\nb\" .\n") { ok = false; }
  if !streq(emit_of(p + "\"a\\tb\" ."), p + "\"a\\tb\" .\n") { ok = false; }
  return assert(ok, "literal escapes: \\n \\t \\r \\\\ decode and re-encode canonically");
}

fn t8() -> TestResult {
  let p = pre();
  var ok = trip_is(p + "\"\\u0041\" .", "iri", "http://a", "http://b", "literal", "A", "", "");
  if !trip_is(p + "\"\\u00e9\" .", "iri", "http://a", "http://b", "literal", bytes2(195, 169), "", "") { ok = false; }
  let emoji = bytes4(240, 159, 152, 128);
  if !trip_is(p + "\"\\U0001F600\" .", "iri", "http://a", "http://b", "literal", emoji, "", "") { ok = false; }
  if !rt_ok(p + "\"\\u00e9\\U0001F600\" .") { ok = false; }
  return assert(ok, "literal UCHAR: \\uXXXX and \\UXXXXXXXX decode to UTF-8 (lowercase hex accepted)");
}

fn t9() -> TestResult {
  var ok = trip_is("<http://e/\\u0041> <http://b> <http://c> .",
    "iri", "http://e/A", "http://b", "iri", "http://c", "", "");
  let emoji = bytes4(240, 159, 152, 128);
  if !trip_is("<http://e/\\U0001F600> <http://b> <http://c> .",
      "iri", "http://e/" + emoji, "http://b", "iri", "http://c", "", "") { ok = false; }
  if !rt_ok("<http://e/\\u0041> <http://b> <http://c> .") { ok = false; }
  if !streq(emit_of("<http://e/\\u0041> <http://b> <http://c> ."), "<http://e/A> <http://b> <http://c> .\n") { ok = false; }
  return assert(ok, "IRI UCHAR: decoding and canonical raw-UTF-8 emit");
}

fn t10() -> TestResult {
  let multi = "# header\r\n\r\n<http://a> <http://b> <http://c> . # trailing\r\n<http://d> <http://e> \"x\" .\n";
  var ok = count_is(multi, 2);
  if !streq(object_text_of(multi, 1), "x") { ok = false; }
  if !streq(emit_of(multi), "<http://a> <http://b> <http://c> .\n<http://d> <http://e> \"x\" .\n") { ok = false; }
  if !count_is("<http://a> <http://b> <http://c> .\r<http://d> <http://e> <http://f> .\r", 2) { ok = false; }
  if !count_is("<http://a> <http://b> <http://c> .\r\n\r\n", 1) { ok = false; }
  if !count_is("<http://a> <http://b> <http://c> . # tail", 1) { ok = false; }
  return assert(ok, "line ends LF/CRLF/CR, comments after triples, trailing EOL runs");
}

fn t11() -> TestResult {
  var ok = parse_err_is("<http://example.org/s", "ntriples: unterminated IRI at 0");
  if !parse_err_is("<http://a> <http://b", "ntriples: unterminated IRI at 11") { ok = false; }
  if !parse_err_is("<http://a/\\", "ntriples: unterminated IRI at 0") { ok = false; }
  return assert(ok, "unterminated IRI: reports the opening '<'");
}

fn t12() -> TestResult {
  let p = pre();
  var ok = parse_err_is(p + "<http://c d> .", "ntriples: missing '>' at 31");
  if !parse_err_is(p + "<http://c<d> .", "ntriples: missing '>' at 31") { ok = false; }
  if !parse_err_is(p + "<http://c\\u0020d> .", "ntriples: missing '>' at 31") { ok = false; }
  return assert(ok, "missing '>': a forbidden byte (or UCHAR) inside an IRIREF is reported at the byte");
}

fn t13() -> TestResult {
  let p = pre();
  var ok = parse_err_is(p + "\"abc", "ntriples: unterminated literal at 22");
  if !parse_err_is(p + "\"abc\\", "ntriples: unterminated literal at 22") { ok = false; }
  return assert(ok, "unterminated literal: reports the opening quote, trailing backslash included");
}

fn t14() -> TestResult {
  let p = pre();
  var ok = parse_err_is(p + "\"\\q\" .", "ntriples: bad escape at 23");
  if !parse_err_is(p + "\"\\u12\" .", "ntriples: bad escape at 23") { ok = false; }
  if !parse_err_is(p + "\"\\uD800\" .", "ntriples: bad escape at 23") { ok = false; }
  if !parse_err_is(p + "\"\\U00110000\" .", "ntriples: bad escape at 23") { ok = false; }
  if !parse_err_is(p + "\"\\u0000\" .", "ntriples: bad escape at 23") { ok = false; }
  if !parse_err_is("<http://e/\\q> <http://b> <http://c> .", "ntriples: bad escape at 10") { ok = false; }
  return assert(ok, "bad escapes: unknown letter, truncated, non-hex, surrogate, out of range, NUL");
}

fn t15() -> TestResult {
  let p = pre();
  var ok = parse_err_is(p + "\"x\"@ .", "ntriples: bad language tag at 25");
  if !parse_err_is(p + "\"x\"@1en .", "ntriples: bad language tag at 25") { ok = false; }
  if !parse_err_is(p + "\"x\"@en- .", "ntriples: bad language tag at 25") { ok = false; }
  if !parse_err_is(p + "\"x\"@en--US .", "ntriples: bad language tag at 25") { ok = false; }
  if !parse_err_is(p + "\"x\"@en_US .", "ntriples: bad language tag at 25") { ok = false; }
  return assert(ok, "bad language tag: empty, leading digit, trailing dash, empty subtag, bad byte");
}

fn t16() -> TestResult {
  let p = pre();
  var ok = parse_err_is("<http://a> <http://b> <http://c>", "ntriples: missing '.' at 32");
  if !parse_err_is("<http://a> <http://b> <http://c> <http://d> .", "ntriples: extra term at 33") { ok = false; }
  if !parse_err_is(p + "\"x\" \"y\" .", "ntriples: extra term at 26") { ok = false; }
  if !parse_err_is("<http://a> <http://b> <http://c> . junk", "ntriples: unexpected byte at 35") { ok = false; }
  if !parse_err_is(p + "@x .", "ntriples: unexpected byte at 22") { ok = false; }
  if !parse_err_is(p + "<http://c>", "ntriples: missing '.' at 32") { ok = false; }
  if !parse_err_is("<http://a>", "ntriples: unexpected end of line at 10") { ok = false; }
  return assert(ok, "terminator errors: missing '.', extra terms, trailing bytes, incomplete triples");
}

fn t17() -> TestResult {
  let p = pre();
  var ok = parse_err_is(p + "\"" + bytes1(255) + "\" .", "ntriples: invalid UTF-8 byte at 23");
  if !parse_err_is(p + "\"" + bytes1(226) + "\" .", "ntriples: invalid UTF-8 byte at 23") { ok = false; }
  if !parse_err_is(p + "\"" + bytes2(226, 65) + "\" .", "ntriples: invalid UTF-8 byte at 23") { ok = false; }
  return assert(ok, "invalid UTF-8: stray 0xFF, truncated sequence and bad continuation are rejected");
}

fn t18() -> TestResult {
  let p = pre();
  var ok = parse_err_is(p + "\"" + bytes1(1) + "\" .", "ntriples: raw control byte in literal at 23");
  if !parse_err_is(p + bytes5(34, 97, 13, 98, 34) + " .", "ntriples: unterminated literal at 22") { ok = false; }
  if !trip_is(p + "\"a\tb\" .", "iri", "http://a", "http://b", "literal", "a\tb", "", "") { ok = false; }
  return assert(ok, "raw control bytes: rejected except TAB; a raw CR ends the line");
}

fn t19() -> TestResult {
  var ok = parse_err_is("_: <http://b> <http://c> .", "ntriples: invalid blank node label at 0");
  if !parse_err_is("_:a b <http://c> .", "ntriples: missing '<' at 4") { ok = false; }
  if !parse_err_is("<http://a> _:b <http://c> .", "ntriples: missing '<' at 11") { ok = false; }
  if !parse_err_is(pre() + "\"x\"^^http://d .", "ntriples: missing '<' at 27") { ok = false; }
  if !parse_err_is(pre() + "\"x\"^^", "ntriples: missing '<' at 27") { ok = false; }
  if !trip_is("_:1x <http://b> <http://c> .", "bnode", "1x", "http://b", "iri", "http://c", "", "") { ok = false; }
  return assert(ok, "blank nodes and predicates: label errors, missing '<' for predicate and datatype");
}

fn t20() -> TestResult {
  let multi = "# c\n<http://a> <http://b> <http://c> .\r\n_:n1 <http://b> \"lit\"@en-GB .\n<http://d> <http://b> \"v\"^^<http://dt> .\n";
  var ok = count_is(multi, 3);
  if !rt_ok(multi) { ok = false; }
  let want = "<http://a> <http://b> <http://c> .\n_:n1 <http://b> \"lit\"@en-GB .\n<http://d> <http://b> \"v\"^^<http://dt> .\n";
  if !streq(emit_of(multi), want) { ok = false; }
  return assert(ok, "round trip: parse -> canonical emit -> parse is stable for mixed documents");
}

fn t21() -> TestResult {
  let p = pre();
  var ok = streq(emit_of(p + "\"\\u001F\" ."), p + "\"\\u001F\" .\n");
  var d = nt_new();
  let added = nt_add_triple(&mut d, "iri", "http://a{b", "http://p", "iri", "http://o", "", "");
  if !added { ok = false; }
  if !streq(nt_emit(&d), "<http://a\\u007Bb> <http://p> <http://o> .\n") { ok = false; }
  var d2 = nt_new();
  if !nt_add_triple(&mut d2, "iri", "http://a", "http://p", "literal", bytes1(31), "", "") { ok = false; }
  if !streq(nt_emit(&d2), "<http://a> <http://p> \"\\u001F\" .\n") { ok = false; }
  if !rt_ok(p + "\"\\u0001\" .") { ok = false; }
  return assert(ok, "canonical escapes: control bytes and forbidden IRI bytes use uppercase hex");
}

fn t22() -> TestResult {
  var d = nt_new();
  var ok = nt_triple_count(&d) == 0;
  if !nt_add_triple(&mut d, "iri", "http://s", "http://p", "literal", "v", "en", "") { ok = false; }
  if nt_triple_count(&d) != 1 { ok = false; }
  if !streq(nt_object_lang(&d, 0), "en") { ok = false; }
  if nt_object_has_datatype(&d, 0) { ok = false; }
  if nt_add_triple(&mut d, "iri", "http://s", "http://p", "literal", "v", "en-", "") { ok = false; }
  if nt_add_triple(&mut d, "literal", "http://s", "http://p", "iri", "http://o", "", "") { ok = false; }
  if nt_add_triple(&mut d, "iri", "http://s", "http://p", "literal", "v", "en", "http://dt") { ok = false; }
  if nt_add_triple(&mut d, "bnode", "a.", "http://p", "iri", "http://o", "", "") { ok = false; }
  if nt_triple_count(&d) != 1 { ok = false; }
  if !nt_add_triple(&mut d, "bnode", "a.b", "http://p", "iri", "http://o", "", "") { ok = false; }
  if !nt_add_triple(&mut d, "iri", "http://s", "http://p", "bnode", "x-y", "", "") { ok = false; }
  if !nt_add_triple(&mut d, "iri", "http://s", "http://p", "literal", "v", "", "http://dt") { ok = false; }
  if nt_triple_count(&d) != 4 { ok = false; }
  if !nt_object_has_datatype(&d, 3) { ok = false; }
  if !streq(nt_subject_text(&d, 1), "a.b") { ok = false; }
  return assert(ok, "nt_add_triple: valid inserts append, invalid inserts return false and do not mutate");
}

fn t23() -> TestResult {
  let p = pre();
  let r = nt_parse(p + "\"x\"@en .");
  match r {
    Ok(d) => {
      var ok = nt_triple_count(&d) == 1;
      if !streq(nt_subject_kind(&d, -1), "") { ok = false; }
      if !streq(nt_subject_kind(&d, 1), "") { ok = false; }
      if !streq(nt_subject_text(&d, 9), "") { ok = false; }
      if !streq(nt_predicate(&d, -3), "") { ok = false; }
      if !streq(nt_object_kind(&d, 2), "") { ok = false; }
      if !streq(nt_object_text(&d, -1), "") { ok = false; }
      if !streq(nt_object_lang(&d, 7), "") { ok = false; }
      if !streq(nt_object_datatype(&d, 1), "") { ok = false; }
      if nt_object_has_datatype(&d, 1) { ok = false; }
      return assert(ok, "accessors: out-of-range indices return \"\"/false");
    },
    Err(_) => { return assert(false, "accessors: valid parse failed"); },
  };
  return assert(false, "unreachable");
}

fn t24() -> TestResult {
  let p = pre();
  let e_acute = bytes2(195, 169);
  let emoji = bytes4(240, 159, 152, 128);
  var ok = trip_is(p + "\"" + e_acute + "\" .", "iri", "http://a", "http://b", "literal", e_acute, "", "");
  if !trip_is(p + "\"" + emoji + "\" .", "iri", "http://a", "http://b", "literal", emoji, "", "") { ok = false; }
  if !trip_is("<http://e/" + e_acute + "> <http://b> <http://c> .",
      "iri", "http://e/" + e_acute, "http://b", "iri", "http://c", "", "") { ok = false; }
  if !rt_ok(p + "\"" + emoji + "\" .") { ok = false; }
  if !streq(emit_of(p + "\"" + e_acute + "\" ."), p + "\"" + e_acute + "\" .\n") { ok = false; }
  return assert(ok, "raw UTF-8: non-ASCII bytes in literals and IRIs pass through and re-emit raw");
}

fn main() -> Int {
  io.println("=== xiom.ntriples conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.ntriples: all tests passed");
  } else {
    io.println("xiom.ntriples: tests failed");
  }
  return failed;
}
