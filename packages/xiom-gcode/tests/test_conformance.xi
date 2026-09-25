// XIOM -- xiom.gcode conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.gcode module against its SPEC.md: line grammar,
// line numbers, parameter words, comments, checksums, scaling, canonical
// emission, round-trips and the error catalog.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every text check
// below is routed through streq, and Vec element reads are bound with typed
// lets. The checksum fixtures are derived from the XOR definition by xor_str
// and hex2, which are independent of the library implementation.

module gcode_tests
use xiom.io; use xiom.test; use xiom.gcode;
use xiom.string; use xiom.string.compare; use xiom.convert; use xiom.math;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// XOR of every byte of s, widened through & 0xFF (the test-side reference
// implementation of the checksum rule).
fn xor_str(s: Str) -> Int {
  var acc = 0;
  var i = 0;
  while i < s.len() {
    acc = math.bit_xor(acc, ((string.byte_at(s, i) as Int) & 0xFF));
    i = i + 1;
  }
  return acc;
}

// Two uppercase hex digits for 0 <= v <= 255.
fn hex_digit(d: Int) -> Str {
  return string.str_slice("0123456789ABCDEF", d, d + 1);
}

fn hex2(v: Int) -> Str {
  return hex_digit(v / 16) + hex_digit(v % 16);
}

fn ok_int(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let e: Str = r.error;
  return streq(e, want);
}

fn err_is(s: Str, want: Str) -> Bool {
  let r = gcode_parse_line(s);
  if r.is_ok { return false; }
  let e: Str = r.error;
  return streq(e, want);
}

fn text_err_is(t: Str, want: Str) -> Bool {
  let r = gcode_parse(t);
  if r.is_ok { return false; }
  let e: Str = r.error;
  return streq(e, want);
}

// Parse `s` and check the command shape and parameter count.
fn shape_is(s: Str, ln: Int, letter: Str, text: Str, value: Int, scale: Int, params: Int) -> Bool {
  let r = gcode_parse_line(s);
  if !r.is_ok { return false; }
  let l: GcodeLine = r.value;
  if l.blank { return false; }
  if l.line_number != ln { return false; }
  if !streq(l.command_letter, letter) { return false; }
  if !streq(l.command_text, text) { return false; }
  if l.command_value != value { return false; }
  if l.command_scale != scale { return false; }
  if l.param_letters.len() != params { return false; }
  return true;
}

// Parse `s` and check parameter `j`.
fn param_is(s: Str, j: Int, letter: Str, text: Str, value: Int, scale: Int) -> Bool {
  let r = gcode_parse_line(s);
  if !r.is_ok { return false; }
  let l: GcodeLine = r.value;
  if j < 0 || j >= l.param_letters.len() { return false; }
  let lt: Str = l.param_letters[j];
  let tx: Str = l.param_texts[j];
  let vl: Int = l.param_values[j];
  let sc: Int = l.param_scales[j];
  if !streq(lt, letter) { return false; }
  if !streq(tx, text) { return false; }
  if vl != value { return false; }
  if sc != scale { return false; }
  return true;
}

// The line parses as blank and emits the empty string.
fn blank_ok(s: Str) -> Bool {
  let r = gcode_parse_line(s);
  if !r.is_ok { return false; }
  let l: GcodeLine = r.value;
  if !l.blank { return false; }
  let e = gcode_emit(&l);
  return streq(e, "");
}

// Parse `s`, emit it, and compare with `want`.
fn emit_is(s: Str, want: Str) -> Bool {
  let r = gcode_parse_line(s);
  if !r.is_ok { return false; }
  let l: GcodeLine = r.value;
  let e = gcode_emit(&l);
  return streq(e, want);
}

// Structural equality of two lines (letters, values, scales, line number).
fn line_eq(a: &GcodeLine, b: &GcodeLine) -> Bool {
  if a.blank != b.blank { return false; }
  if a.line_number != b.line_number { return false; }
  if !streq(a.command_letter, b.command_letter) { return false; }
  if a.command_value != b.command_value { return false; }
  if a.command_scale != b.command_scale { return false; }
  if a.param_letters.len() != b.param_letters.len() { return false; }
  var j = 0;
  while j < a.param_letters.len() {
    let al: Str = a.param_letters[j];
    let bl: Str = b.param_letters[j];
    if !streq(al, bl) { return false; }
    let av: Int = a.param_values[j];
    let bv: Int = b.param_values[j];
    if av != bv { return false; }
    let asc: Int = a.param_scales[j];
    let bsc: Int = b.param_scales[j];
    if asc != bsc { return false; }
    j = j + 1;
  }
  return true;
}

// parse -> emit -> parse yields the same structure.
fn roundtrip_is(s: Str) -> Bool {
  let r1 = gcode_parse_line(s);
  if !r1.is_ok { return false; }
  let l1: GcodeLine = r1.value;
  let e = gcode_emit(&l1);
  let r2 = gcode_parse_line(e);
  if !r2.is_ok { return false; }
  let l2: GcodeLine = r2.value;
  return line_eq(&l1, &l2);
}

// Command and flat parameter counts of a parsed document.
fn counts_is(t: Str, commands: Int, params: Int) -> Bool {
  let r = gcode_parse(t);
  if !r.is_ok { return false; }
  let p: GcodeProgram = r.value;
  if gcode_command_count(&p) != commands { return false; }
  if gcode_program_param_count(&p) != params { return false; }
  return true;
}

// Check command `i` of a parsed document.
fn program_line_is(t: Str, i: Int, ln: Int, letter: Str, text: Str, value: Int, scale: Int, params: Int) -> Bool {
  let r = gcode_parse(t);
  if !r.is_ok { return false; }
  let p: GcodeProgram = r.value;
  let l = gcode_program_line(&p, i);
  if l.blank { return false; }
  if l.line_number != ln { return false; }
  if !streq(l.command_letter, letter) { return false; }
  if !streq(l.command_text, text) { return false; }
  if l.command_value != value { return false; }
  if l.command_scale != scale { return false; }
  if l.param_letters.len() != params { return false; }
  return true;
}

// Check parameter `j` of command `i` of a parsed document.
fn program_param_is(t: Str, i: Int, j: Int, letter: Str, text: Str, value: Int, scale: Int) -> Bool {
  let r = gcode_parse(t);
  if !r.is_ok { return false; }
  let p: GcodeProgram = r.value;
  let l = gcode_program_line(&p, i);
  if j < 0 || j >= l.param_letters.len() { return false; }
  let lt: Str = l.param_letters[j];
  let tx: Str = l.param_texts[j];
  let vl: Int = l.param_values[j];
  let sc: Int = l.param_scales[j];
  if !streq(lt, letter) { return false; }
  if !streq(tx, text) { return false; }
  if vl != value { return false; }
  if sc != scale { return false; }
  return true;
}

// Emit command `i` of a parsed document and compare with `want`.
fn program_emit_is(t: Str, i: Int, want: Str) -> Bool {
  let r = gcode_parse(t);
  if !r.is_ok { return false; }
  let p: GcodeProgram = r.value;
  let l = gcode_program_line(&p, i);
  let e = gcode_emit(&l);
  return streq(e, want);
}

// --- fixtures ---------------------------------------------------------------

// "G1 X1" XORs to 0x3F; "N10 G0 X0" to 0x50; "G1 (c)" to 0x34. The tests
// both pin these values and recompute them with xor_str.
fn canonical_line() -> Str {
  return "N10 G1 X10.5 Y-3";
}

// --- tests ------------------------------------------------------------------

fn t1() -> TestResult {
  let s = canonical_line();
  var ok = shape_is(s, 10, "G", "1", 1, 0, 2);
  if !param_is(s, 0, "X", "10.5", 105, 1) { ok = false; }
  if !param_is(s, 1, "Y", "-3", -3, 0) { ok = false; }
  let rr = gcode_parse_line(s);
  if !rr.is_ok { ok = false; }
  if rr.is_ok {
    let l: GcodeLine = rr.value;
    if gcode_line_is_blank(&l) { ok = false; }
    if gcode_line_number(&l) != 10 { ok = false; }
    if gcode_command_value(&l) != 1 { ok = false; }
    if gcode_param_count(&l) != 2 { ok = false; }
    if !streq(gcode_param_letter(&l, 1), "Y") { ok = false; }
    if !streq(gcode_param_text(&l, 1), "-3") { ok = false; }
    if gcode_param_value(&l, 1) != -3 { ok = false; }
    if gcode_param_scale(&l, 1) != 0 { ok = false; }
  }
  return assert(ok, "canonical line: N10 G1 X10.5 Y-3");
}

fn t2() -> TestResult {
  let s = "G0.50 X.050 Y+10.50";
  var ok = shape_is(s, -1, "G", "0.50", 50, 2, 2);
  if !param_is(s, 0, "X", ".050", 50, 3) { ok = false; }
  if !param_is(s, 1, "Y", "+10.50", 1050, 2) { ok = false; }
  return assert(ok, "verbatim number text and integer scaling");
}

fn t3() -> TestResult {
  let s = "n5 m3 s1000 x1.5 y-2";
  var ok = shape_is(s, 5, "M", "3", 3, 0, 3);
  if !param_is(s, 0, "S", "1000", 1000, 0) { ok = false; }
  if !param_is(s, 1, "X", "1.5", 15, 1) { ok = false; }
  if !param_is(s, 2, "Y", "-2", -2, 0) { ok = false; }
  return assert(ok, "letters are case-insensitive and normalized uppercase");
}

fn t4() -> TestResult {
  let s = "  \tG1\t X1   Y2 ";
  var ok = shape_is(s, -1, "G", "1", 1, 0, 2);
  if !param_is(s, 0, "X", "1", 1, 0) { ok = false; }
  if !param_is(s, 1, "Y", "2", 2, 0) { ok = false; }
  if !shape_is("G1X1Y2", -1, "G", "1", 1, 0, 2) { ok = false; }
  if !param_is("G1X1Y2", 0, "X", "1", 1, 0) { ok = false; }
  if !param_is("G1X1Y2", 1, "Y", "2", 2, 0) { ok = false; }
  return assert(ok, "whitespace tolerance and adjacent words");
}

fn t5() -> TestResult {
  var ok = shape_is("G1 (rough cut) X1 ; finish", -1, "G", "1", 1, 0, 1);
  if !param_is("G1 (rough cut) X1 ; finish", 0, "X", "1", 1, 0) { ok = false; }
  if !shape_is("(header) G0 X0 (tail)", -1, "G", "0", 0, 0, 1) { ok = false; }
  if !shape_is("G1 (a(b) X1", -1, "G", "1", 1, 0, 1) { ok = false; }
  if !param_is("G1 (a(b) X1", 0, "X", "1", 1, 0) { ok = false; }
  if !emit_is("G1 X1 ; x*3F (y)", "G1 X1") { ok = false; }
  return assert(ok, "semicolon and paren comments, first ')' closes");
}

fn t6() -> TestResult {
  var ok = blank_ok("");
  if !blank_ok("   ") { ok = false; }
  if !blank_ok("\t \r") { ok = false; }
  if !blank_ok("; note") { ok = false; }
  if !blank_ok("(note)") { ok = false; }
  if !blank_ok("()") { ok = false; }
  if !blank_ok(" \t; a (b) ; c") { ok = false; }
  return assert(ok, "empty and comment-only lines are blank and emit \"\"");
}

fn t7() -> TestResult {
  var ok = err_is("N10", "gcode: missing command");
  if !err_is("N10 (c)", "gcode: missing command") { ok = false; }
  if !err_is("N10 ; c", "gcode: missing command") { ok = false; }
  if !err_is("N10*4F", "gcode: missing command") { ok = false; }
  if !streq(hex2(xor_str("N10")), "4F") { ok = false; }
  return assert(ok, "a line number alone has no command");
}

fn t8() -> TestResult {
  var ok = err_is("N G0", "gcode: bad line number");
  if !err_is("N-1 G0", "gcode: bad line number") { ok = false; }
  if !err_is("N1.5 G0", "gcode: bad line number") { ok = false; }
  if !err_is("N+0 G0", "gcode: bad line number") { ok = false; }
  if !err_is("Nx", "gcode: bad line number") { ok = false; }
  if !err_is("N99999999999999999999 G0", "gcode: bad line number") { ok = false; }
  return assert(ok, "line number must be a plain run of digits");
}

fn t9() -> TestResult {
  var ok = err_is("G", "gcode: bad number: G");
  if !err_is("X1.2.3", "gcode: bad number: X1.2.3") { ok = false; }
  if !err_is("X+", "gcode: bad number: X+") { ok = false; }
  if !err_is("Xabc", "gcode: bad number: Xabc") { ok = false; }
  if !err_is(".5", "gcode: bad number: .5") { ok = false; }
  if !err_is("123", "gcode: bad number: 123") { ok = false; }
  if !err_is("G1 X1-2", "gcode: bad number: X1-2") { ok = false; }
  return assert(ok, "malformed and letterless numbers are rejected");
}

fn t10() -> TestResult {
  var ok = err_is("G1 (oops", "gcode: unterminated paren comment");
  if !err_is("G1 X1*3F (oops", "gcode: unterminated paren comment") { ok = false; }
  if !err_is("G1 X1 (", "gcode: unterminated paren comment") { ok = false; }
  return assert(ok, "unterminated paren comments are rejected");
}

fn t11() -> TestResult {
  var ok = err_is("G1 @ X2", "gcode: unexpected character at 3");
  if !err_is("G1 X1 #", "gcode: unexpected character at 6") { ok = false; }
  if !err_is("$G1", "gcode: unexpected character at 0") { ok = false; }
  return assert(ok, "stray bytes report their 0-based line offset");
}

fn t12() -> TestResult {
  var ok = shape_is("G1 X1*3F", -1, "G", "1", 1, 0, 1);
  if !streq(hex2(xor_str("G1 X1")), "3F") { ok = false; }
  let computed = "N10 G0 X0*" + hex2(xor_str("N10 G0 X0"));
  if !shape_is(computed, 10, "G", "0", 0, 0, 1) { ok = false; }
  if !streq(hex2(xor_str("N10 G0 X0")), "50") { ok = false; }
  if !shape_is("G1 X1*3f", -1, "G", "1", 1, 0, 1) { ok = false; }
  if !shape_is("G1 X1*3F ; ok", -1, "G", "1", 1, 0, 1) { ok = false; }
  if !shape_is("G1 X1*3F (ok)", -1, "G", "1", 1, 0, 1) { ok = false; }
  if !shape_is("G1 X1*3F\r", -1, "G", "1", 1, 0, 1) { ok = false; }
  return assert(ok, "checksum accepts either case and trailing comments");
}

fn t13() -> TestResult {
  var ok = shape_is("G1 (c)*34", -1, "G", "1", 1, 0, 0);
  if !streq(hex2(xor_str("G1 (c)")), "34") { ok = false; }
  if !shape_is(" (c) G1*14", -1, "G", "1", 1, 0, 0) { ok = false; }
  if !streq(hex2(xor_str(" (c) G1")), "14") { ok = false; }
  if !err_is("G1 (c)*34 X1", "gcode: trailing garbage") { ok = false; }
  return assert(ok, "checksum XOR covers comments and whitespace");
}

fn t14() -> TestResult {
  var ok = err_is("G1 X1*", "gcode: bad checksum");
  if !err_is("G1 X1*3", "gcode: bad checksum") { ok = false; }
  if !err_is("G1 X1*G1", "gcode: bad checksum") { ok = false; }
  if !err_is("G1 X1* 3F", "gcode: bad checksum") { ok = false; }
  if !err_is("G1 X1**3F", "gcode: bad checksum") { ok = false; }
  return assert(ok, "malformed checksum suffixes");
}

fn t15() -> TestResult {
  var ok = err_is("G1 X1*40", "gcode: checksum mismatch: 40");
  if !err_is("G1 X1*00", "gcode: checksum mismatch: 00") { ok = false; }
  if !err_is("N10*00", "gcode: checksum mismatch: 00") { ok = false; }
  if !shape_is("G1 X1*3F", -1, "G", "1", 1, 0, 1) { ok = false; }
  return assert(ok, "checksum value mismatches quote the suffix");
}

fn t16() -> TestResult {
  var ok = err_is("G1 X1*3F X2", "gcode: trailing garbage");
  if !err_is("G1 X1*3FX", "gcode: trailing garbage") { ok = false; }
  if !err_is("G1 X1*3F*3F", "gcode: trailing garbage") { ok = false; }
  return assert(ok, "only whitespace and comments may follow the checksum");
}

fn t17() -> TestResult {
  let doc = "G0 X0\r\n\n; header\nN2 G1 X1.5 Y-2 ; cut\n";
  var ok = counts_is(doc, 2, 3);
  if !program_line_is(doc, 0, -1, "G", "0", 0, 0, 1) { ok = false; }
  if !program_param_is(doc, 0, 0, "X", "0", 0, 0) { ok = false; }
  if !program_line_is(doc, 1, 2, "G", "1", 1, 0, 2) { ok = false; }
  if !program_param_is(doc, 1, 0, "X", "1.5", 15, 1) { ok = false; }
  if !program_param_is(doc, 1, 1, "Y", "-2", -2, 0) { ok = false; }
  if !program_emit_is(doc, 1, "N2 G1 X1.5 Y-2") { ok = false; }
  return assert(ok, "document parse skips blanks and keeps line order");
}

fn t18() -> TestResult {
  var ok = text_err_is("G1 X1\n\nG2 Y2\nZ\n", "gcode: line 4: bad number: Z");
  if !text_err_is("G1 X1\nN", "gcode: line 2: bad line number") { ok = false; }
  if !text_err_is("G1 X1\n\nG1 X1*00", "gcode: line 3: checksum mismatch: 00") { ok = false; }
  return assert(ok, "document errors carry the 1-based physical line number");
}

fn t19() -> TestResult {
  var ok = emit_is("G01 X+010.50 Y.5", "G1 X10.50 Y0.5");
  if !emit_is("N007 G0 X0", "N7 G0 X0") { ok = false; }
  if !emit_is("m3 s1000", "M3 S1000") { ok = false; }
  if !emit_is("G1 X1*3F", "G1 X1") { ok = false; }
  if !emit_is("(only comment)", "") { ok = false; }
  if !emit_is("G1 X0.000 Y-0.5", "G1 X0.000 Y-0.5") { ok = false; }
  if !emit_is("G1 Y-0.0", "G1 Y0.0") { ok = false; }
  return assert(ok, "canonical emitter normalizes letters and numbers");
}

fn t20() -> TestResult {
  var ok = roundtrip_is("N10 G1 X10.5 Y-3");
  if !roundtrip_is("G0 X.050 Y+10.50") { ok = false; }
  if !roundtrip_is("n5 M3 s1000 x1.5") { ok = false; }
  if !roundtrip_is("(blank)") { ok = false; }
  if !roundtrip_is("G1 X0.000") { ok = false; }
  if !roundtrip_is("G1 X9223372036854775807 Y-9223372036854775807") { ok = false; }
  if !emit_is(canonical_line(), canonical_line()) { ok = false; }
  if !emit_is("G1 X0.000", "G1 X0.000") { ok = false; }
  return assert(ok, "round-trip: emit is a fixed point on canonical text");
}

fn t21() -> TestResult {
  var ok = ok_int(gcode_micro(105, 1), 10500000);
  if !ok_int(gcode_micro(12345, 7), 1234) { ok = false; }
  if !ok_int(gcode_micro(-12345, 7), -1234) { ok = false; }
  if !ok_int(gcode_micro(-3, 0), -3000000) { ok = false; }
  if !ok_int(gcode_micro(5, 6), 5) { ok = false; }
  if !ok_int(gcode_micro(1, 18), 0) { ok = false; }
  if !err_int_is(gcode_micro(9223372036854775807, 0), "gcode: value out of range") { ok = false; }
  if !err_int_is(gcode_micro(-9223372036854775808, 6), "gcode: value out of range") { ok = false; }
  if !err_int_is(gcode_micro(1, -1), "gcode: bad scale") { ok = false; }
  if !err_int_is(gcode_micro(1, 19), "gcode: bad scale") { ok = false; }
  return assert(ok, "gcode_micro scaling and its error paths");
}

fn t22() -> TestResult {
  var ok = param_is("G1 X9223372036854775807", 0, "X", "9223372036854775807", 9223372036854775807, 0);
  if !err_is("G1 X9223372036854775808", "gcode: number too large: X9223372036854775808") { ok = false; }
  if !err_is("X0.1234567890123456789", "gcode: too many fraction digits: X0.1234567890123456789") { ok = false; }
  if !param_is("G0 X0.123456789012345678", 0, "X", "0.123456789012345678", 123456789012345678, 18) { ok = false; }
  return assert(ok, "64-bit magnitude and 18-digit scale boundaries");
}

fn t23() -> TestResult {
  let r = gcode_parse_line("");
  var ok = r.is_ok;
  if !r.is_ok { return assert(false, "blank accessors"); }
  let b: GcodeLine = r.value;
  if gcode_line_number(&b) != -1 { ok = false; }
  if !streq(gcode_command_letter(&b), "") { ok = false; }
  if !streq(gcode_command_text(&b), "") { ok = false; }
  if gcode_command_value(&b) != 0 { ok = false; }
  if gcode_command_scale(&b) != 0 { ok = false; }
  if gcode_param_count(&b) != 0 { ok = false; }
  if !streq(gcode_param_letter(&b, 0), "") { ok = false; }
  if !streq(gcode_param_text(&b, -1), "") { ok = false; }
  if gcode_param_value(&b, 5) != 0 { ok = false; }
  if gcode_param_scale(&b, 5) != 0 { ok = false; }
  let rl = gcode_parse_line("G1 X1");
  if !rl.is_ok { ok = false; }
  if rl.is_ok {
    let l3: GcodeLine = rl.value;
    if !streq(gcode_param_letter(&l3, 99), "") { ok = false; }
    if !streq(gcode_param_letter(&l3, -1), "") { ok = false; }
    if gcode_param_value(&l3, -1) != 0 { ok = false; }
    if gcode_param_scale(&l3, 99) != 0 { ok = false; }
  }
  if !counts_is("", 0, 0) { ok = false; }
  if !counts_is("\n\n; nothing\n", 0, 0) { ok = false; }
  let rp = gcode_parse("G1 X1");
  if !rp.is_ok { ok = false; }
  if rp.is_ok {
    let p: GcodeProgram = rp.value;
    let l = gcode_program_line(&p, 5);
    if !l.blank { ok = false; }
    if gcode_line_number(&l) != -1 { ok = false; }
    let l2 = gcode_program_line(&p, -1);
    if !l2.blank { ok = false; }
  }
  return assert(ok, "out-of-range accessors return documented defaults");
}

fn main() -> Int {
  io.println("=== xiom.gcode conformance tests ===");
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
    io.println("xiom.gcode: all tests passed");
  } else {
    io.println("xiom.gcode: tests failed");
  }
  return failed;
}
