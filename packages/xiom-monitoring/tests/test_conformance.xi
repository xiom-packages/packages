// XIOM -- xiom.monitoring conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.monitoring module against its SPEC.md:
// value forms and IEEE specials, timestamps, line kinds, HELP escapes,
// labels and escapes, bare metrics, family grouping and declarations,
// histogram/summary rules, exemplars, EOF semantics, lenient error
// collection, byte offsets, and the scaled-integer/float accessors.
//
// Every synthetic exposition is built inside this file; no external fixture
// files. All Str equality goes through compare.str_compare (BUG 17).

module monitoring_tests
use xiom.io; use xiom.test; use xiom.monitoring;
use xiom.string; use xiom.string.compare; use xiom.string.builder;
use xiom.convert.int; use xiom.convert.float;
use xiom.math.constants;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn feq(a: Float64, b: Float64) -> Bool {
  var d = a - b;
  if d < 0.0 {
    d = 0.0 - d;
  }
  return d < 0.000001;
}

fn first_err(text: Str) -> Str {
  let r = mon_parse(text);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => { return e; },
  }
  return "<ok>";
}

fn first_ok(text: Str) -> Bool {
  return mon_parse_ok(text);
}

// Value helpers (mon_parse_value).
fn vkind(text: Str) -> Int {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_kind(&v); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn vmicro(text: Str) -> Int {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_micro(&v); },
    Err(_) => { return -999999999; },
  }
  return -999999999;
}

fn vfloat(text: Str) -> Float64 {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_float(&v); },
    Err(_) => { return -999999999.0; },
  }
  return -999999999.0;
}

fn vraw(text: Str) -> Str {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_raw(&v); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn vover(text: Str) -> Bool {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return v.over; },
    Err(_) => { return false; },
  }
  return false;
}

fn vfinite(text: Str) -> Bool {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_is_finite(&v); },
    Err(_) => { return false; },
  }
  return false;
}

fn vspecial(text: Str) -> Bool {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_is_special(&v); },
    Err(_) => { return false; },
  }
  return false;
}

fn vposinf(text: Str) -> Bool {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_is_pos_inf(&v); },
    Err(_) => { return false; },
  }
  return false;
}

fn vneginf(text: Str) -> Bool {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_is_neg_inf(&v); },
    Err(_) => { return false; },
  }
  return false;
}

fn vnan(text: Str) -> Bool {
  let r = mon_parse_value(text);
  match r {
    Ok(v) => { return mon_value_is_nan(&v); },
    Err(_) => { return false; },
  }
  return false;
}

fn pfloat(text: Str) -> Float64 {
  let r = mon_parse_float(text);
  match r {
    Ok(f) => { return f; },
    Err(_) => { return -999999999.0; },
  }
  return -999999999.0;
}

// parse_line helpers.
fn lkind(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_kind(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn lerr(line: Str) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => { return e; },
  }
  return "<ok>";
}

fn lname(line: Str) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_name(&l); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn ltype(line: Str) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_type(&l); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn lhelp(line: Str) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_help_text(&l); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn lhelpraw(line: Str) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_help_raw(&l); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn lunit(line: Str) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_unit(&l); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn lvraw(line: Str) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_value_raw(&l); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn lvmicro(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_value_micro(&l); },
    Err(_) => { return -999999999; },
  }
  return -999999999;
}

fn lvfloat(line: Str) -> Float64 {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_value_float(&l); },
    Err(_) => { return -999999999.0; },
  }
  return -999999999.0;
}

fn lvkind(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_value_kind(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn lvat(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_value_at(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn lvlen(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_value_len(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn lhas(line: Str) -> Bool {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_has_timestamp(&l); },
    Err(_) => { return false; },
  }
  return false;
}

fn lts(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_timestamp(&l); },
    Err(_) => { return -999999999; },
  }
  return -999999999;
}

fn ltsat(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_ts_at(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn lpart(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_part(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn lnat(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_name_at(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn llcount(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_label_count(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn llname(line: Str, k: Int) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_label_name(&l, k); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn llval(line: Str, k: Int) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_label_value(&l, k); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn llraw(line: Str, k: Int) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_label_value_raw(&l, k); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn llvalueat(line: Str, k: Int) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_label_value_at(&l, k); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn llookup(line: Str, name: Str) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_label_lookup(&l, name); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn lexcount(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_exemplar_count(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn lexlab(line: Str, k: Int) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_exemplar_label_name(&l, k); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn lexval(line: Str, k: Int) -> Str {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_exemplar_label_value(&l, k); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn lexvmicro(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_exemplar_value_micro(&l); },
    Err(_) => { return -999999999; },
  }
  return -999999999;
}

fn lexvkind(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_exemplar_value_kind(&l); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn lexhasts(line: Str) -> Bool {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_exemplar_has_timestamp(&l); },
    Err(_) => { return false; },
  }
  return false;
}

fn lexts(line: Str) -> Int {
  let r = mon_parse_line(line);
  match r {
    Ok(l) => { return mon_line_get_exemplar_timestamp(&l); },
    Err(_) => { return -999999999; },
  }
  return -999999999;
}

// Document helpers (lenient parse; errors visible through errmsg).
fn fcount(text: Str) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_family_count(&d);
}

fn findex(text: Str, name: Str) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_family_index(&d, name);
}

fn ftype(text: Str, name: Str) -> Str {
  let d = mon_parse_lenient(text);
  let f = mon_doc_family_index(&d, name);
  if f < 0 {
    return "<none>";
  }
  return mon_doc_family_type(&d, f);
}

fn fhas(text: Str, name: Str) -> Bool {
  let d = mon_parse_lenient(text);
  let f = mon_doc_family_index(&d, name);
  if f < 0 {
    return false;
  }
  return mon_doc_family_has_type(&d, f);
}

fn fhelp(text: Str, name: Str) -> Str {
  let d = mon_parse_lenient(text);
  let f = mon_doc_family_index(&d, name);
  if f < 0 {
    return "<none>";
  }
  return mon_doc_family_help_text(&d, f);
}

fn fhelpraw(text: Str, name: Str) -> Str {
  let d = mon_parse_lenient(text);
  let f = mon_doc_family_index(&d, name);
  if f < 0 {
    return "<none>";
  }
  return mon_doc_family_help(&d, f);
}

fn funit(text: Str, name: Str) -> Str {
  let d = mon_parse_lenient(text);
  let f = mon_doc_family_index(&d, name);
  if f < 0 {
    return "<none>";
  }
  return mon_doc_family_unit(&d, f);
}

fn fsamples(text: Str, name: Str) -> Int {
  let d = mon_parse_lenient(text);
  let f = mon_doc_family_index(&d, name);
  if f < 0 {
    return -1;
  }
  return mon_doc_family_sample_count(&d, f);
}

fn scount(text: Str) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_count(&d);
}

fn sname(text: Str, i: Int) -> Str {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_name(&d, i);
}

fn spart(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_part(&d, i);
}

fn sfam(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_family(&d, i);
}

fn smicro(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_value_micro(&d, i);
}

fn sraw(text: Str, i: Int) -> Str {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_value_raw(&d, i);
}

fn skind(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_value_kind(&d, i);
}

fn sline(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_line(&d, i);
}

fn sat(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_at(&d, i);
}

fn slen(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_len(&d, i);
}

fn shasts(text: Str, i: Int) -> Bool {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_has_timestamp(&d, i);
}

fn sts(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_timestamp(&d, i);
}

fn slcount(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_label_count(&d, i);
}

fn slabel(text: Str, i: Int, name: Str) -> Str {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_label_lookup(&d, i, name);
}

fn slabelraw(text: Str, i: Int, k: Int) -> Str {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_label_value_raw(&d, i, k);
}

fn spart_of(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_part(&d, i);
}

fn shasle(text: Str, i: Int) -> Bool {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_has_le(&d, i);
}

fn slemicro(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_le_micro(&d, i);
}

fn sleinf(text: Str, i: Int) -> Bool {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_le_inf(&d, i);
}

fn sqmicro(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_quantile_micro(&d, i);
}

fn sqraw(text: Str, i: Int) -> Str {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_quantile_raw(&d, i);
}

fn sexc(text: Str, i: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_sample_exemplar_count(&d, i);
}

fn sexlab(text: Str, i: Int, k: Int, p: Int) -> Str {
  let d = mon_parse_lenient(text);
  return mon_doc_exemplar_label_name(&d, i, k, p);
}

fn sexval(text: Str, i: Int, k: Int, p: Int) -> Str {
  let d = mon_parse_lenient(text);
  return mon_doc_exemplar_label_value(&d, i, k, p);
}

fn sexvmicro(text: Str, i: Int, k: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_exemplar_value_micro(&d, i, k);
}

fn sexvkind(text: Str, i: Int, k: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_exemplar_value_kind(&d, i, k);
}

fn sexhasts(text: Str, i: Int, k: Int) -> Bool {
  let d = mon_parse_lenient(text);
  return mon_doc_exemplar_has_timestamp(&d, i, k);
}

fn sexts(text: Str, i: Int, k: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_exemplar_timestamp(&d, i, k);
}

fn errmsg(text: Str, k: Int) -> Str {
  let d = mon_parse_lenient(text);
  return mon_doc_error_msg(&d, k);
}

fn errline(text: Str, k: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_error_line(&d, k);
}

fn errat(text: Str, k: Int) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_error_at(&d, k);
}

fn ecount(text: Str) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_error_count(&d);
}

fn dlinecount(text: Str) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_line_count(&d);
}

fn dbytecount(text: Str) -> Int {
  let d = mon_parse_lenient(text);
  return mon_doc_byte_count(&d);
}

fn deof(text: Str) -> Bool {
  let d = mon_parse_lenient(text);
  return mon_doc_eof_seen(&d);
}

fn verr(text: Str) -> Str {
  let r = mon_parse_value(text);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => { return e; },
  }
  return "<ok>";
}

fn perr(text: Str) -> Str {
  let r = mon_parse_float(text);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => { return e; },
  }
  return "<ok>";
}

fn t1() -> TestResult {
  var ok = vmicro("0") == 0;
  if vmicro("123") != 123000000 { ok = false; }
  if vmicro("123.456") != 123456000 { ok = false; }
  if vmicro(".5") != 500000 { ok = false; }
  if vmicro("1.") != 1000000 { ok = false; }
  if vmicro("1e3") != 1000000000 { ok = false; }
  if vmicro("1.5e-3") != 1500 { ok = false; }
  if vmicro("-2.5") != -2500000 { ok = false; }
  if vmicro("+7") != 7000000 { ok = false; }
  if vmicro("0.0000001") != 0 { ok = false; }
  if vmicro("1e12") != 1000000000000000000 { ok = false; }
  if vmicro("123.4567899") != 123456789 { ok = false; }
  if vmicro("2.5e-7") != 0 { ok = false; }
  if !vfinite("42") { ok = false; }
  if !streq(vraw("1.5e-3"), "1.5e-3") { ok = false; }
  if !feq(vfloat("2.5"), 2.5) { ok = false; }
  return assert(ok, "value forms parse to exact micro-units and floats");
}

fn t2() -> TestResult {
  var ok = vkind("+Inf") == 1;
  if !vposinf("+Inf") { ok = false; }
  if !vspecial("+Inf") { ok = false; }
  if vfinite("+Inf") { ok = false; }
  if vmicro("+Inf") != 0 { ok = false; }
  if vkind("-Inf") != 2 { ok = false; }
  if !vneginf("-Inf") { ok = false; }
  if vkind("NaN") != 3 { ok = false; }
  if !vnan("NaN") { ok = false; }
  if !vposinf("Inf") { ok = false; }
  if vkind("42") != 0 { ok = false; }
  if !streq(verr("nan"), "monitoring: bad value at 0") { ok = false; }
  if !streq(verr("inf"), "monitoring: bad value at 0") { ok = false; }
  if !streq(verr("NAN"), "monitoring: bad value at 0") { ok = false; }
  let f = pfloat("NaN");
  if f == f { ok = false; }
  if pfloat("+Inf") != infinity() { ok = false; }
  if pfloat("-Inf") != neg_infinity() { ok = false; }
  return assert(ok, "IEEE specials: +Inf, -Inf, Inf, NaN");
}

fn t3() -> TestResult {
  var ok = streq(verr(""), "monitoring: bad value at 0");
  if !streq(verr("abc"), "monitoring: bad value at 0") { ok = false; }
  if !streq(verr("1e"), "monitoring: bad value at 2") { ok = false; }
  if !streq(verr("1.2.3"), "monitoring: bad value at 3") { ok = false; }
  if !streq(verr("+"), "monitoring: bad value at 0") { ok = false; }
  if !streq(verr("12x"), "monitoring: bad value at 2") { ok = false; }
  if !streq(verr("."), "monitoring: bad value at 0") { ok = false; }
  if !vover("1e9999999") { ok = false; }
  if vmicro("1e9999999") != 9223372036854775807 { ok = false; }
  if pfloat("1e9999999") != infinity() { ok = false; }
  if !vover("1234567890123456789012345") { ok = false; }
  if vmicro("1234567890123456789012345") != 9223372036854775807 { ok = false; }
  if vmicro("-1e18") != -9223372036854775807 { ok = false; }
  if vkind("1234567890123456789012345") != 0 { ok = false; }
  return assert(ok, "value rejections with offsets; overflow truncation and saturation");
}

fn t4() -> TestResult {
  var ok = lhas("m 5 1500000000000");
  if lts("m 5 1500000000000") != 1500000000000 { ok = false; }
  if ltsat("m 5 1500000000000") != 4 { ok = false; }
  if lvlen("m 5 1500000000000") != 1 { ok = false; }
  if lts("m 5 1.5") != 1 { ok = false; }
  if lts("m 5 -2.9") != -2 { ok = false; }
  if lhas("m 5") { ok = false; }
  if !streq(lerr("m 5 1e3"), "monitoring: bad timestamp at 5") { ok = false; }
  if !streq(lerr("m 5 99999999999999999999999"), "monitoring: timestamp out of range at 4") { ok = false; }
  if lerr("m 5 1.5") != "<ok>" { ok = false; }
  return assert(ok, "timestamps parse to int64 milliseconds with truncation");
}

fn t5() -> TestResult {
  var ok = lkind("") == 0;
  if lkind("   ") != 0 { ok = false; }
  if lkind("# comment") != 1 { ok = false; }
  if lkind("#") != 1 { ok = false; }
  if lkind("# HELP x doc") != 2 { ok = false; }
  if lkind("# TYPE x counter") != 3 { ok = false; }
  if lkind("# UNIT x seconds") != 4 { ok = false; }
  if lkind("# EOF") != 5 { ok = false; }
  if lkind("x 1") != 6 { ok = false; }
  if !streq(lhelp("# HELP x doc"), "doc") { ok = false; }
  if !streq(ltype("# TYPE x counter"), "counter") { ok = false; }
  if !streq(lunit("# UNIT x seconds"), "seconds") { ok = false; }
  if !streq(lname("# HELP x doc"), "x") { ok = false; }
  return assert(ok, "line kinds: blank, comment, HELP, TYPE, UNIT, EOF, sample");
}

fn t6() -> TestResult {
  let line = "# HELP x a\\nb\\\\c";
  var ok = streq(lhelpraw(line), "a\\nb\\\\c");
  if !streq(lhelp(line), "a" + "\n" + "b\\c") { ok = false; }
  if !streq(lerr("# HELP x bad\\tx"), "monitoring: invalid escape in HELP at 12") { ok = false; }
  if lkind("# nothelp x") != 1 { ok = false; }
  if !streq(lhelp("# HELP x   spaced"), "spaced") { ok = false; }
  if !streq(lhelp("# HELP x"), "") { ok = false; }
  return assert(ok, "HELP text is an escape-aware span (\\n and \\\\)");
}

fn t7() -> TestResult {
  let line = "m{a=\"1\",b=\"x\\\"y\\\\z\\nw\"} 1";
  var ok = llcount(line) == 2;
  if !streq(llname(line, 0), "a") { ok = false; }
  if !streq(llname(line, 1), "b") { ok = false; }
  if !streq(llval(line, 0), "1") { ok = false; }
  if !streq(llval(line, 1), "x\"y\\z\nw") { ok = false; }
  if !streq(llraw(line, 1), "x\\\"y\\\\z\\nw") { ok = false; }
  if llvalueat(line, 0) != 5 { ok = false; }
  if !streq(llookup(line, "a"), "1") { ok = false; }
  if !streq(llookup(line, "A"), "") { ok = false; }
  if !streq(lerr("m{a=\"1\",a=\"2\"} 1"), "monitoring: duplicate label at 8") { ok = false; }
  if !streq(lerr("m{a=\"x\\ty\"} 1"), "monitoring: bad escape at 6") { ok = false; }
  if !streq(lerr("m{a=\"x} 1"), "monitoring: unterminated label value at 5") { ok = false; }
  if !streq(lerr("m{} 1"), "monitoring: empty label set at 2") { ok = false; }
  if !streq(lerr("m{a=\"1\",} 1"), "monitoring: bad label at 8") { ok = false; }
  if !streq(lerr("m{a=1} 1"), "monitoring: bad label quote at 4") { ok = false; }
  if !streq(lerr("m{1a=\"x\"} 1"), "monitoring: bad label name at 2") { ok = false; }
  return assert(ok, "labels: escapes, spans, case-sensitive lookup, rejections");
}

fn t8() -> TestResult {
  var ok = streq(lvraw("m 3.5"), "3.5");
  if lvmicro("m 3.5") != 3500000 { ok = false; }
  if !feq(lvfloat("m 3.5"), 3.5) { ok = false; }
  if lvat("m 3.5") != 2 { ok = false; }
  if llcount("m 3.5") != 0 { ok = false; }
  if lpart("m 3.5") != 0 { ok = false; }
  if !streq(lname("m 3.5"), "m") { ok = false; }
  if lnat("m:colon_1 1") != 0 { ok = false; }
  if !streq(lvraw("m:colon_1 1"), "1") { ok = false; }
  if !streq(lerr("m 1 trailing"), "monitoring: bad timestamp at 4") { ok = false; }
  if !streq(lerr("1bad 1"), "monitoring: bad metric name at 0") { ok = false; }
  if !streq(lerr("m"), "monitoring: missing value at 1") { ok = false; }
  if !streq(lerr("m{a=\"1\"}5"), "monitoring: missing value at 8") { ok = false; }
  return assert(ok, "bare metric form, name charset, missing value and garbage");
}

fn t9() -> TestResult {
  let text = "# HELP http_requests_total Total requests.\n# TYPE http_requests_total counter\n# UNIT http_requests_total requests\nhttp_requests_total{method=\"get\"} 1027\nhttp_requests_total{method=\"post\"} 3 1395066363000\n";
  var ok = fcount(text) == 1;
  if findex(text, "http_requests_total") != 0 { ok = false; }
  if !streq(ftype(text, "http_requests_total"), "counter") { ok = false; }
  if !fhas(text, "http_requests_total") { ok = false; }
  if !streq(fhelp(text, "http_requests_total"), "Total requests.") { ok = false; }
  if !streq(fhelpraw(text, "http_requests_total"), "Total requests.") { ok = false; }
  if !streq(funit(text, "http_requests_total"), "requests") { ok = false; }
  if fsamples(text, "http_requests_total") != 2 { ok = false; }
  if scount(text) != 2 { ok = false; }
  if !streq(sname(text, 1), "http_requests_total") { ok = false; }
  if smicro(text, 0) != 1027000000 { ok = false; }
  if !streq(slabel(text, 0, "method"), "get") { ok = false; }
  if !streq(slabel(text, 1, "method"), "post") { ok = false; }
  if !shasts(text, 1) { ok = false; }
  if sts(text, 1) != 1395066363000 { ok = false; }
  if spart(text, 0) != 0 { ok = false; }
  if !first_ok(text) { ok = false; }
  return assert(ok, "family grouping attaches HELP, TYPE and UNIT");
}

fn t10() -> TestResult {
  let text = "# TYPE x counter\n# TYPE x gauge\nx 1\n";
  var ok = streq(first_err(text), "monitoring: duplicate TYPE for \"x\" at 24");
  if ecount(text) != 1 { ok = false; }
  if errline(text, 0) != 2 { ok = false; }
  if errat(text, 0) != 24 { ok = false; }
  if !streq(ftype(text, "x"), "counter") { ok = false; }
  if scount(text) != 1 { ok = false; }
  if first_ok(text) { ok = false; }
  return assert(ok, "duplicate TYPE is rejected with the second name offset");
}

fn t11() -> TestResult {
  var ok = streq(lerr("# TYPE x bogus"), "monitoring: bad type at 9");
  if !streq(lerr("# TYPE x"), "monitoring: bad type at 8") { ok = false; }
  if !streq(lerr("# TYPE 9x counter"), "monitoring: missing metric name at 7") { ok = false; }
  if lkind("# HELP x") != 2 { ok = false; }
  if !streq(lerr("# HELP"), "monitoring: missing metric name at 6") { ok = false; }
  if !streq(lerr("# UNIT x"), "monitoring: bad unit at 8") { ok = false; }
  if !streq(lerr("# EOF now"), "monitoring: bad EOF at 6") { ok = false; }
  if lkind("# nothelp x") != 1 { ok = false; }
  return assert(ok, "malformed directives report exact offsets");
}

fn t12() -> TestResult {
  let text = "# TYPE h histogram\nh_bucket{le=\"0.5\"} 1\nh_bucket{le=\"1\"} 2\nh_bucket{le=\"+Inf\"} 3\nh_sum 4.5\nh_count 3\n";
  var ok = fcount(text) == 1;
  if !streq(ftype(text, "h"), "histogram") { ok = false; }
  if fsamples(text, "h") != 5 { ok = false; }
  if scount(text) != 5 { ok = false; }
  if spart(text, 0) != 1 { ok = false; }
  if spart(text, 1) != 1 { ok = false; }
  if spart(text, 2) != 1 { ok = false; }
  if spart(text, 3) != 2 { ok = false; }
  if spart(text, 4) != 3 { ok = false; }
  if sfam(text, 4) != 0 { ok = false; }
  if !shasle(text, 0) { ok = false; }
  if slemicro(text, 0) != 500000 { ok = false; }
  if slemicro(text, 1) != 1000000 { ok = false; }
  if !sleinf(text, 2) { ok = false; }
  if shasle(text, 3) { ok = false; }
  if smicro(text, 3) != 4500000 { ok = false; }
  if smicro(text, 4) != 3000000 { ok = false; }
  if !streq(sraw(text, 3), "4.5") { ok = false; }
  if !first_ok(text) { ok = false; }
  return assert(ok, "histogram grouping: bucket/sum/count with le boundaries");
}

fn t13() -> TestResult {
  var ok = streq(first_err("# TYPE h histogram\nh_bucket 1\n"), "monitoring: bucket without le at 19");
  if !streq(first_err("# TYPE h histogram\nh_bucket{le=\"abc\"} 1\n"), "monitoring: bad le at 32") { ok = false; }
  if !streq(first_err("# TYPE h histogram\nh_bucket{le=\"NaN\"} 1\n"), "monitoring: bad le at 32") { ok = false; }
  if !streq(first_err("# TYPE h histogram\nh_bucket{le=\"-Inf\"} 1\n"), "monitoring: bad le at 32") { ok = false; }
  if !streq(first_err("# TYPE h histogram\nh 1\n"), "monitoring: unexpected histogram sample at 19") { ok = false; }
  let dup = "# TYPE h histogram\nh_bucket{le=\"1\"} 1\nh_bucket{le=\"1\"} 2\n";
  if !streq(first_err(dup), "monitoring: duplicate bucket le at 51") { ok = false; }
  let down = "# TYPE h histogram\nh_bucket{le=\"2\"} 1\nh_bucket{le=\"1\"} 2\n";
  if !streq(first_err(down), "monitoring: bucket le out of order at 51") { ok = false; }
  let afterinf = "# TYPE h histogram\nh_bucket{le=\"+Inf\"} 1\nh_bucket{le=\"5\"} 2\n";
  if !streq(first_err(afterinf), "monitoring: bucket le out of order at 54") { ok = false; }
  let good = "# TYPE h histogram\nh_bucket{le=\"1\"} 1\nh_bucket{le=\"2\"} 2\nh_bucket{le=\"+Inf\"} 3\n";
  if !first_ok(good) { ok = false; }
  if scount(good) != 3 { ok = false; }
  return assert(ok, "histogram le rules: required, finite/+Inf, strictly increasing");
}

fn t14() -> TestResult {
  let text = "# TYPE s summary\ns{quantile=\"0.5\"} 1.5\ns{quantile=\"0.99\"} 2.5\ns_sum 4\ns_count 2\n";
  var ok = fcount(text) == 1;
  if !streq(ftype(text, "s"), "summary") { ok = false; }
  if fsamples(text, "s") != 4 { ok = false; }
  if spart(text, 0) != 5 { ok = false; }
  if spart(text, 1) != 5 { ok = false; }
  if spart(text, 2) != 2 { ok = false; }
  if spart(text, 3) != 3 { ok = false; }
  if sqmicro(text, 0) != 500000 { ok = false; }
  if sqmicro(text, 1) != 990000 { ok = false; }
  if !streq(sqraw(text, 0), "0.5") { ok = false; }
  if smicro(text, 0) != 1500000 { ok = false; }
  if smicro(text, 2) != 4000000 { ok = false; }
  if !first_ok(text) { ok = false; }
  if !streq(first_err("# TYPE s summary\ns{quantile=\"1.5\"} 1\n"), "monitoring: bad quantile at 29") { ok = false; }
  if !streq(first_err("# TYPE s summary\ns{quantile=\"abc\"} 1\n"), "monitoring: bad quantile at 29") { ok = false; }
  if !streq(first_err("# TYPE s summary\ns 1\n"), "monitoring: summary sample without quantile at 17") { ok = false; }
  return assert(ok, "summary grouping: quantile/sum/count with range checks");
}

fn t15() -> TestResult {
  let line = "http_request_duration_seconds_bucket{le=\"1\"} 2 # {trace_id=\"abc\"} 1.5 1500000000000";
  var ok = lpart(line) == 1;
  if lexcount(line) != 1 { ok = false; }
  if !streq(lexlab(line, 0), "trace_id") { ok = false; }
  if !streq(lexval(line, 0), "abc") { ok = false; }
  if lexvmicro(line) != 1500000 { ok = false; }
  if !lexhasts(line) { ok = false; }
  if lexts(line) != 1500000000000 { ok = false; }
  if sexc(line, 0) != 1 { ok = false; }
  if !streq(sexlab(line, 0, 0, 0), "trace_id") { ok = false; }
  if !streq(sexval(line, 0, 0, 0), "abc") { ok = false; }
  if sexvmicro(line, 0, 0) != 1500000 { ok = false; }
  if !sexhasts(line, 0, 0) { ok = false; }
  if sexts(line, 0, 0) != 1500000000000 { ok = false; }
  if lexcount("x 1 # {} 2") != 1 { ok = false; }
  if lexvmicro("x 1 # {} 2") != 2000000 { ok = false; }
  if !streq(lerr("x 1 # 2"), "monitoring: bad exemplar at 6") { ok = false; }
  if !streq(lerr("x 1 # {trace_id=\"a\"} bad"), "monitoring: bad exemplar value at 21") { ok = false; }
  if !streq(lexval("x 1 # {k=\"a\\\"b\"} 2", 0), "a\"b") { ok = false; }
  return assert(ok, "exemplars attach to the preceding sample with value and ts");
}

fn t16() -> TestResult {
  let ok1 = "x 1\n# EOF\n";
  var ok = deof(ok1);
  if dlinecount(ok1) != 2 { ok = false; }
  if !first_ok(ok1) { ok = false; }
  if !streq(first_err("x 1\n# EOF\ny 2\n"), "monitoring: sample after EOF at 10") { ok = false; }
  if !streq(first_err("# EOF\n# EOF\n"), "monitoring: duplicate EOF at 6") { ok = false; }
  if !streq(first_err("# EOF x"), "monitoring: bad EOF at 6") { ok = false; }
  if !streq(first_err("# EOF\n# hi\n"), "monitoring: line after EOF at 6") { ok = false; }
  if !first_ok("# EOF\n\n") { ok = false; }
  if deof("x 1\n") { ok = false; }
  return assert(ok, "EOF is exclusive: samples/comments after it are rejected");
}

fn t17() -> TestResult {
  let text = "# TYPE x counter\n# TYPE x gauge\nx 1\noops x\n";
  var ok = ecount(text) == 2;
  if !streq(errmsg(text, 0), "monitoring: duplicate TYPE for \"x\" at 24") { ok = false; }
  if !streq(errmsg(text, 1), "monitoring: bad value at 41") { ok = false; }
  if errline(text, 0) != 2 { ok = false; }
  if errline(text, 1) != 4 { ok = false; }
  if errat(text, 1) != 41 { ok = false; }
  if scount(text) != 1 { ok = false; }
  if sat(text, 0) != 32 { ok = false; }
  if sline(text, 0) != 3 { ok = false; }
  if fcount(text) != 1 { ok = false; }
  if !streq(ftype(text, "x"), "counter") { ok = false; }
  return assert(ok, "lenient walk collects errors with lines/offsets and keeps samples");
}

fn t18() -> TestResult {
  let line = "http_requests_total{method=\"get\",code=\"200\"} 1027 1395066363000";
  var ok = lnat(line) == 0;
  if lvat(line) != 45 { ok = false; }
  if lvlen(line) != 4 { ok = false; }
  if ltsat(line) != 50 { ok = false; }
  if llcount(line) != 2 { ok = false; }
  if !streq(llname(line, 0), "method") { ok = false; }
  if !streq(llname(line, 1), "code") { ok = false; }
  if llvalueat(line, 0) != 28 { ok = false; }
  if llvalueat(line, 1) != 39 { ok = false; }
  if lpart(line) != 0 { ok = false; }
  if sat(line, 0) != 0 { ok = false; }
  if slen(line, 0) != 63 { ok = false; }
  if !streq(slabel(line, 0, "code"), "200") { ok = false; }
  if slcount(line, 0) != 2 { ok = false; }
  if !streq(slabelraw(line, 0, 1), "200") { ok = false; }
  return assert(ok, "byte offsets: name, labels, value and timestamp spans");
}

fn t19() -> TestResult {
  var ok = vmicro("0.000001") == 1;
  if vmicro("0.0000009") != 0 { ok = false; }
  if vmicro("123.456789") != 123456789 { ok = false; }
  if vmicro("-0.5") != -500000 { ok = false; }
  if vmicro("1000000") != 1000000000000 { ok = false; }
  if vmicro("1e18") != 9223372036854775807 { ok = false; }
  if vmicro("0") != 0 { ok = false; }
  if vmicro("-0") != 0 { ok = false; }
  return assert(ok, "micro scaling: truncation toward zero and saturation");
}

fn t20() -> TestResult {
  var ok = feq(pfloat("1.5"), 1.5);
  if !feq(pfloat("1e3"), 1000.0) { ok = false; }
  if !feq(pfloat("-0.25"), -0.25) { ok = false; }
  if !feq(pfloat("0.1"), 0.1) { ok = false; }
  if !feq(pfloat("1."), 1.0) { ok = false; }
  if !feq(lvfloat("m 2.5"), 2.5) { ok = false; }
  if !streq(perr("x"), "monitoring: bad value at 0") { ok = false; }
  return assert(ok, "scalar Float64 helper for raw spans");
}

fn t21() -> TestResult {
  let text = "# TYPE w counter\r\nw_created 1000\r\nw 5\r\n";
  var ok = dlinecount(text) == 3;
  if dbytecount(text) != 39 { ok = false; }
  if deof(text) { ok = false; }
  if fcount(text) != 1 { ok = false; }
  if fsamples(text, "w") != 2 { ok = false; }
  if spart(text, 0) != 4 { ok = false; }
  if spart(text, 1) != 0 { ok = false; }
  if smicro(text, 0) != 1000000000 { ok = false; }
  if sline(text, 0) != 2 { ok = false; }
  if sline(text, 1) != 3 { ok = false; }
  if !streq(sraw(text, 0), "1000") { ok = false; }
  if slabel(text, 0, "x") != "" { ok = false; }
  return assert(ok, "_created is a plain sample; CRLF walk and consumed counts");
}

fn t22() -> TestResult {
  let good = "x_bucket{le=\"1\"} 1\nx_bucket{le=\"2\"} 2\n";
  var ok = first_ok(good);
  if scount(good) != 2 { ok = false; }
  if fcount(good) != 1 { ok = false; }
  if !streq(ftype(good, "x_bucket"), "") { ok = false; }
  if !shasle(good, 0) { ok = false; }
  let bad = "x_bucket{le=\"2\"} 1\nx_bucket{le=\"1\"} 2\n";
  if !streq(first_err(bad), "monitoring: bucket le out of order at 32") { ok = false; }
  if scount(bad) != 1 { ok = false; }
  if slemicro(bad, 0) != 2000000 { ok = false; }
  return assert(ok, "undeclared bucket families still enforce le ordering");
}

fn t23() -> TestResult {
  var ok = true;
  let words = "counter gauge histogram summary untyped info stateset gaugehistogram";
  let w = string.words(words);
  var i = 0;
  while i < w.len() {
    let name: Str = w[i];
    let l = "# TYPE m " + name;
    if lkind(l) != 3 { ok = false; }
    if !streq(ltype(l), name) { ok = false; }
    i = i + 1;
  }
  if !streq(lerr("# TYPE m Counter"), "monitoring: bad type at 9") { ok = false; }
  if lkind("# TYPE m counter ") != 3 { ok = false; }
  if !streq(ltype("# TYPE m gaugehistogram"), "gaugehistogram") { ok = false; }
  return assert(ok, "TYPE catalog: all eight words, case-sensitive, no extra tokens");
}

fn t24() -> TestResult {
  let text = "# TYPE x counter\n# TYPE x gauge\nx 1\n";
  var ok = streq(first_err(text), errmsg(text, 0));
  if ecount(text) != 1 { ok = false; }
  if first_ok(text) { ok = false; }
  if !first_ok("# TYPE x counter\nx 1\n# EOF\n") { ok = false; }
  if !first_ok("") { ok = false; }
  if dlinecount("") != 0 { ok = false; }
  if dbytecount("") != 0 { ok = false; }
  if !first_ok("x 1") { ok = false; }
  return assert(ok, "strict parse is the first lenient error; empty input is valid");
}

fn main() -> Int {
  io.println("=== xiom.monitoring conformance tests ===");
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
    io.println("xiom.monitoring: all tests passed");
  } else {
    io.println("xiom.monitoring: tests failed");
  }
  return failed;
}

