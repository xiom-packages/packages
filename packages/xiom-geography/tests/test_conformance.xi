// XIOM -- xiom.geography conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: the country rows are the ISO 3166-1 officially assigned codes
// with their numeric codes, ISO English short names and UN M49 groupings; the
// region rows are the UN M49 codes of SPEC.md (including 010 Antarctica).
// Coordinate fixtures are hand-computed integer micro-degree values, never
// floats: 37.975 degrees is 37975000 micro-degrees, and 37 deg 58 min 30 sec
// is exactly that same value.
//
// BUG 17 note: all Str equality goes through str_compare (via streq); values
// read from Vec[Str] are always bound to typed locals before any comparison.
//
// Compiler note: test dispatch is a direct call chain (t1..t21 from main),
// never a Vec[fn] table. The parallel Vecs of the integrity tests are pushed
// in one arm per row so they cannot drift. UTF-8 symbol inputs are built from
// raw bytes with str_of2/str_of3 so the fixtures do not depend on source
// encoding.

module geography_tests
use xiom.io; use xiom.test;
use xiom.geography;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Str from two raw bytes.
fn str_of2(a: Int, b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

// Str from three raw bytes.
fn str_of3(a: Int, b: Int, c: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return Str::from_utf8(v);
}

// ---------------------------------------------------------------------------
// Country probes
// ---------------------------------------------------------------------------

fn a2_of(code: Str) -> Str {
  match geog_country_by_alpha2(code) {
    Ok(c) => { let v: Str = c.alpha2; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn a3_of(code: Str) -> Str {
  match geog_country_by_alpha2(code) {
    Ok(c) => { let v: Str = c.alpha3; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn num_of(code: Str) -> Str {
  match geog_country_by_alpha2(code) {
    Ok(c) => { let v: Str = c.numeric; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn name_of(code: Str) -> Str {
  match geog_country_by_alpha2(code) {
    Ok(c) => { let v: Str = c.name; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn cont_of(code: Str) -> Str {
  match geog_country_by_alpha2(code) {
    Ok(c) => { let v: Str = c.continent; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn reg_of(code: Str) -> Str {
  match geog_country_by_alpha2(code) {
    Ok(c) => { let v: Str = c.region; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn a2_by_a3(code: Str) -> Str {
  match geog_country_by_alpha3(code) {
    Ok(c) => { let v: Str = c.alpha2; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn a2_by_num(code: Str) -> Str {
  match geog_country_by_numeric(code) {
    Ok(c) => { let v: Str = c.alpha2; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn a2_err_is(code: Str, want: Str) -> Bool {
  match geog_country_by_alpha2(code) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn a3_err_is(code: Str, want: Str) -> Bool {
  match geog_country_by_alpha3(code) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn num_err_is(code: Str, want: Str) -> Bool {
  match geog_country_by_numeric(code) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn at_a2(i: Int) -> Str {
  match geog_country_at(i) {
    Ok(c) => { let v: Str = c.alpha2; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn at_err_is(i: Int, want: Str) -> Bool {
  match geog_country_at(i) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn name_by_code(code: Str) -> Str {
  match geog_country_name_by_code(code) {
    Ok(v) => { return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn name_by_code_err_is(code: Str, want: Str) -> Bool {
  match geog_country_name_by_code(code) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn cont_by_code(code: Str) -> Str {
  match geog_country_continent_by_code(code) {
    Ok(v) => { return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn reg_by_code(code: Str) -> Str {
  match geog_country_region_by_code(code) {
    Ok(v) => { return v; },
    Err(e) => { return ""; },
  }
  return "";
}

// ---------------------------------------------------------------------------
// Region probes
// ---------------------------------------------------------------------------

fn reg_name_of(code: Str) -> Str {
  match geog_region_name_by_code(code) {
    Ok(v) => { return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn reg_parent_of(code: Str) -> Str {
  match geog_region_parent_by_code(code) {
    Ok(v) => { return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn reg_err_is(code: Str, want: Str) -> Bool {
  match geog_region_by_code(code) {
    Ok(r) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn reg_at_code(i: Int) -> Str {
  match geog_region_at(i) {
    Ok(r) => { let v: Str = r.code; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn reg_at_err_is(i: Int, want: Str) -> Bool {
  match geog_region_at(i) {
    Ok(r) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Walk parent links up to the top-level region; "" when the chain is broken.
fn top_of(code: Str) -> Str {
  var cur = code;
  var guard = 0;
  while guard < 4 {
    let p = reg_parent_of(cur);
    if p.len() == 0 { return cur; }
    cur = p;
    guard = guard + 1;
  }
  return "";
}

// ---------------------------------------------------------------------------
// Subdivision probes
// ---------------------------------------------------------------------------

fn sub_country(text: Str) -> Str {
  match geog_subdivision_parse(text) {
    Ok(s) => { let v: Str = s.country; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn sub_part(text: Str) -> Str {
  match geog_subdivision_parse(text) {
    Ok(s) => { let v: Str = s.part; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn sub_raw(text: Str) -> Str {
  match geog_subdivision_parse(text) {
    Ok(s) => { let v: Str = s.raw; return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn sub_canonical(text: Str) -> Str {
  match geog_subdivision_parse(text) {
    Ok(s) => { return geog_subdivision_canonical(&s); },
    Err(e) => { return ""; },
  }
  return "";
}

fn sub_err_is(text: Str, want: Str) -> Bool {
  match geog_subdivision_parse(text) {
    Ok(s) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn sub_fmt(country: Str, part: Str) -> Str {
  match geog_subdivision_format(country, part) {
    Ok(v) => { return v; },
    Err(e) => { return ""; },
  }
  return "";
}

fn sub_fmt_err_is(country: Str, part: Str, want: Str) -> Bool {
  match geog_subdivision_format(country, part) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Coordinate probes
// ---------------------------------------------------------------------------

fn dec_of(text: Str, lat: Bool) -> Int {
  match geog_coord_parse_decimal(text, lat) {
    Ok(v) => { return v; },
    Err(e) => { return -999999999; },
  }
  return -999999999;
}

fn dec_err_is(text: Str, lat: Bool, want: Str) -> Bool {
  match geog_coord_parse_decimal(text, lat) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn dms_of(text: Str, lat: Bool) -> Int {
  match geog_coord_parse_dms(text, lat) {
    Ok(v) => { return v; },
    Err(e) => { return -999999999; },
  }
  return -999999999;
}

fn dms_err_is(text: Str, lat: Bool, want: Str) -> Bool {
  match geog_coord_parse_dms(text, lat) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = geog_country_count() == 249;
  if !streq(at_a2(0), "AD") { ok = false; }
  if !streq(at_a2(248), "ZW") { ok = false; }
  if !at_err_is(249, "geography: index out of range: 249") { ok = false; }
  if !at_err_is(0 - 1, "geography: index out of range: -1") { ok = false; }
  return assert(ok, "country count 249, AD first / ZW last, out-of-range errors");
}

fn t2() -> TestResult {
  var ok = streq(a3_of("GR"), "GRC");
  if !streq(num_of("GR"), "300") { ok = false; }
  if !streq(name_of("GR"), "Greece") { ok = false; }
  if !streq(cont_of("GR"), "150") { ok = false; }
  if !streq(reg_of("GR"), "039") { ok = false; }
  if !streq(a3_of("US"), "USA") { ok = false; }
  if !streq(num_of("US"), "840") { ok = false; }
  if !streq(name_of("US"), "United States of America") { ok = false; }
  if !streq(a3_of("JP"), "JPN") { ok = false; }
  if !streq(num_of("JP"), "392") { ok = false; }
  if !streq(a3_of("BR"), "BRA") { ok = false; }
  if !streq(num_of("BR"), "076") { ok = false; }
  if !streq(a3_of("DE"), "DEU") { ok = false; }
  if !streq(num_of("DE"), "276") { ok = false; }
  return assert(ok, "alpha-2 lookups for GR/US/JP/BR/DE carry alpha-3, numeric, name and regions");
}

fn t3() -> TestResult {
  var ok = streq(a3_of("gr"), "GRC");
  if !streq(a3_of("Gr"), "GRC") { ok = false; }
  if !streq(num_of("us"), "840") { ok = false; }
  if !streq(a2_of("jp"), "JP") { ok = false; }
  if !a2_err_is("G", "geography: bad alpha-2 code: G") { ok = false; }
  if !a2_err_is("USA", "geography: bad alpha-2 code: USA") { ok = false; }
  if !a2_err_is("G1", "geography: bad alpha-2 code: G1") { ok = false; }
  if !a2_err_is("", "geography: bad alpha-2 code: ") { ok = false; }
  if !a2_err_is("ZZ", "geography: unknown country code: ZZ") { ok = false; }
  return assert(ok, "alpha-2 lookup is ASCII case-insensitive; shapes and unknowns error");
}

fn t4() -> TestResult {
  var ok = streq(a2_by_a3("GRC"), "GR");
  if !streq(a2_by_a3("grc"), "GR") { ok = false; }
  if !streq(a2_by_a3("USA"), "US") { ok = false; }
  if !streq(a2_by_a3("JPN"), "JP") { ok = false; }
  if !streq(a2_by_a3("Bra"), "BR") { ok = false; }
  if !streq(a2_by_a3("deu"), "DE") { ok = false; }
  if !a3_err_is("GR", "geography: bad alpha-3 code: GR") { ok = false; }
  if !a3_err_is("GR1", "geography: bad alpha-3 code: GR1") { ok = false; }
  if !a3_err_is("ZZZ", "geography: unknown country code: ZZZ") { ok = false; }
  return assert(ok, "alpha-3 lookup: case-insensitive, shape errors, unknown codes");
}

fn t5() -> TestResult {
  var ok = streq(a2_by_num("300"), "GR");
  if !streq(a2_by_num("840"), "US") { ok = false; }
  if !streq(a2_by_num("392"), "JP") { ok = false; }
  if !streq(a2_by_num("076"), "BR") { ok = false; }
  if !streq(a2_by_num("276"), "DE") { ok = false; }
  if !streq(a2_by_num("008"), "AL") { ok = false; }
  if !streq(a2_by_num("8"), "AL") { ok = false; }
  if !streq(a2_by_num("08"), "AL") { ok = false; }
  if !streq(a2_by_num("86"), "IO") { ok = false; }
  if !num_err_is("", "geography: bad numeric code: ") { ok = false; }
  if !num_err_is("1234", "geography: bad numeric code: 1234") { ok = false; }
  if !num_err_is("3x0", "geography: bad numeric code: 3x0") { ok = false; }
  if !num_err_is("999", "geography: unknown numeric code: 999") { ok = false; }
  return assert(ok, "numeric lookup: zero-padded and short forms, shape errors, unknown codes");
}

fn t6() -> TestResult {
  var ok = geog_country_is_valid_alpha2("GR");
  if !geog_country_is_valid_alpha2("gr") { ok = false; }
  if geog_country_is_valid_alpha2("ZZ") { ok = false; }
  if geog_country_is_valid_alpha2("G") { ok = false; }
  if !geog_country_is_valid_alpha3("grc") { ok = false; }
  if geog_country_is_valid_alpha3("ZZZ") { ok = false; }
  if geog_country_is_valid_alpha3("GR") { ok = false; }
  if !geog_country_is_valid_numeric("300") { ok = false; }
  if !geog_country_is_valid_numeric("8") { ok = false; }
  if geog_country_is_valid_numeric("999") { ok = false; }
  if geog_country_is_valid_numeric("30X") { ok = false; }
  if geog_country_is_valid_numeric("") { ok = false; }
  return assert(ok, "validation predicates accept real keys and reject malformed or unknown ones");
}

fn t7() -> TestResult {
  var ok = geog_region_count() == 30;
  if !streq(reg_name_of("150"), "Europe") { ok = false; }
  if !streq(reg_parent_of("150"), "") { ok = false; }
  if !streq(reg_name_of("039"), "Southern Europe") { ok = false; }
  if !streq(reg_parent_of("039"), "150") { ok = false; }
  if !streq(reg_name_of("010"), "Antarctica") { ok = false; }
  if !streq(reg_parent_of("010"), "") { ok = false; }
  if !streq(reg_name_of("202"), "Sub-Saharan Africa") { ok = false; }
  if !streq(reg_parent_of("202"), "002") { ok = false; }
  if !streq(reg_name_of("419"), "Latin America and the Caribbean") { ok = false; }
  if !streq(reg_parent_of("419"), "019") { ok = false; }
  if !streq(reg_at_code(0), "002") { ok = false; }
  if !streq(reg_at_code(29), "419") { ok = false; }
  if !reg_at_err_is(30, "geography: index out of range: 30") { ok = false; }
  if !reg_at_err_is(0 - 1, "geography: index out of range: -1") { ok = false; }
  if !reg_err_is("999", "geography: unknown region code: 999") { ok = false; }
  if !reg_err_is("15", "geography: bad region code: 15") { ok = false; }
  if !reg_err_is("", "geography: bad region code: ") { ok = false; }
  if !geog_region_is_valid("002") { ok = false; }
  if !geog_region_is_valid("010") { ok = false; }
  if geog_region_is_valid("999") { ok = false; }
  if geog_region_is_valid("2") { ok = false; }
  return assert(ok, "region table: 30 rows, names and parents, including 010 Antarctica");
}

fn t8() -> TestResult {
  var ok = streq(cont_of("GR"), "150");
  if !streq(reg_of("GR"), "039") { ok = false; }
  if !streq(cont_of("US"), "019") { ok = false; }
  if !streq(reg_of("US"), "021") { ok = false; }
  if !streq(cont_of("JP"), "142") { ok = false; }
  if !streq(reg_of("JP"), "030") { ok = false; }
  if !streq(cont_of("BR"), "019") { ok = false; }
  if !streq(reg_of("BR"), "005") { ok = false; }
  if !streq(cont_of("DE"), "150") { ok = false; }
  if !streq(reg_of("DE"), "155") { ok = false; }
  if !streq(cont_of("AQ"), "010") { ok = false; }
  if !streq(reg_of("AQ"), "010") { ok = false; }
  if !streq(cont_of("IN"), "142") { ok = false; }
  if !streq(reg_of("IN"), "034") { ok = false; }
  if !streq(cont_of("AU"), "009") { ok = false; }
  if !streq(reg_of("AU"), "053") { ok = false; }
  if !streq(cont_of("EG"), "002") { ok = false; }
  if !streq(reg_of("EG"), "015") { ok = false; }
  if !streq(cont_of("KZ"), "142") { ok = false; }
  if !streq(reg_of("KZ"), "143") { ok = false; }
  if !streq(cont_of("UM"), "009") { ok = false; }
  if !streq(reg_of("UM"), "057") { ok = false; }
  if !geog_region_is_valid(reg_of("GR")) { ok = false; }
  if !geog_region_is_valid(reg_of("US")) { ok = false; }
  if !geog_region_is_valid(reg_of("AQ")) { ok = false; }
  if !streq(cont_by_code("grc"), "150") { ok = false; }
  if !streq(reg_by_code("300"), "039") { ok = false; }
  if !streq(reg_by_code("bra"), "005") { ok = false; }
  if !streq(reg_by_code("392"), "030") { ok = false; }
  return assert(ok, "country->region mapping: continent + finest region, all resolvable");
}

fn t9() -> TestResult {
  var ok = streq(name_by_code("GR"), "Greece");
  if !streq(name_by_code("grc"), "Greece") { ok = false; }
  if !streq(name_by_code("300"), "Greece") { ok = false; }
  if !streq(name_by_code("8"), "Albania") { ok = false; }
  if !streq(name_by_code("USA"), "United States of America") { ok = false; }
  if !streq(name_by_code("076"), "Brazil") { ok = false; }
  if !name_by_code_err_is("ZZ", "geography: unknown country code: ZZ") { ok = false; }
  if !name_by_code_err_is("999", "geography: unknown country code: 999") { ok = false; }
  return assert(ok, "reverse name accessor: alpha-2/alpha-3/numeric keys in, name out");
}

fn t10() -> TestResult {
  var ok = streq(sub_country("GR-A"), "GR");
  if !streq(sub_part("GR-A"), "A") { ok = false; }
  if !streq(sub_raw("GR-A"), "GR-A") { ok = false; }
  if !streq(sub_country("gr-a"), "GR") { ok = false; }
  if !streq(sub_part("gr-a"), "A") { ok = false; }
  if !streq(sub_raw("gr-a"), "gr-a") { ok = false; }
  if !streq(sub_canonical("gr-a"), "GR-A") { ok = false; }
  if !streq(sub_part("GR-69"), "69") { ok = false; }
  if !streq(sub_canonical("gb-eng"), "GB-ENG") { ok = false; }
  if !streq(sub_country("us-ca"), "US") { ok = false; }
  if !streq(sub_part("US-CA"), "CA") { ok = false; }
  if !geog_subdivision_is_valid("GR-A") { ok = false; }
  if !geog_subdivision_is_valid("gb-eng") { ok = false; }
  return assert(ok, "subdivision parse: CC-SUB accepted, uppercased, raw preserved");
}

fn t11() -> TestResult {
  var ok = sub_err_is("", "geography: empty subdivision");
  if !sub_err_is("GR", "geography: subdivision too short at byte 0") { ok = false; }
  if !sub_err_is("GR-", "geography: subdivision too short at byte 0") { ok = false; }
  if !sub_err_is("1R-A", "geography: bad country letter at byte 0") { ok = false; }
  if !sub_err_is("G1-A", "geography: bad country letter at byte 1") { ok = false; }
  if !sub_err_is("GR.A", "geography: missing hyphen at byte 2") { ok = false; }
  if !sub_err_is("GR-ABCD", "geography: bad subdivision length at byte 3") { ok = false; }
  if !sub_err_is("GR-A!", "geography: bad subdivision character at byte 4") { ok = false; }
  if geog_subdivision_is_valid("GR_") { ok = false; }
  if geog_subdivision_is_valid("") { ok = false; }
  return assert(ok, "subdivision parse errors: lengths, charset and hyphen carry byte offsets");
}

fn t12() -> TestResult {
  var ok = streq(sub_fmt("gr", "a"), "GR-A");
  if !streq(sub_fmt("US", "ca"), "US-CA") { ok = false; }
  if !streq(sub_fmt("gb", "ENG"), "GB-ENG") { ok = false; }
  if !streq(sub_fmt("GR", "69"), "GR-69") { ok = false; }
  if !sub_fmt_err_is("G", "A", "geography: bad country code: G") { ok = false; }
  if !sub_fmt_err_is("USA", "A", "geography: bad country code: USA") { ok = false; }
  if !sub_fmt_err_is("GR", "", "geography: bad subdivision part: ") { ok = false; }
  if !sub_fmt_err_is("GR", "ABCD", "geography: bad subdivision part: ABCD") { ok = false; }
  if !sub_fmt_err_is("GR", "A!", "geography: bad subdivision part: A!") { ok = false; }
  return assert(ok, "subdivision format: canonical uppercase CC-SUB, shape validation");
}

fn t13() -> TestResult {
  var ok = dec_of("37.975", true) == 37975000;
  if dec_of("-37.975", true) != 0 - 37975000 { ok = false; }
  if dec_of("+12.5", true) != 12500000 { ok = false; }
  if dec_of("37.975N", true) != 37975000 { ok = false; }
  if dec_of("37.975n", true) != 37975000 { ok = false; }
  if dec_of("37.975S", true) != 0 - 37975000 { ok = false; }
  if dec_of("S37.975", true) != 0 - 37975000 { ok = false; }
  if dec_of("122.5W", false) != 0 - 122500000 { ok = false; }
  if dec_of("W122.5", false) != 0 - 122500000 { ok = false; }
  if dec_of("90", true) != 90000000 { ok = false; }
  if dec_of("180", false) != 180000000 { ok = false; }
  if dec_of("0.000000", true) != 0 { ok = false; }
  if dec_of("-0.000000", true) != 0 { ok = false; }
  if dec_of("90.000000N", true) != 90000000 { ok = false; }
  return assert(ok, "decimal parse: signs, hemispheres, scaled micro-degrees, negative zero");
}

fn t14() -> TestResult {
  var ok = dec_err_is("", true, "geography: empty input");
  if !dec_err_is("N", true, "geography: missing digits at byte 1") { ok = false; }
  if !dec_err_is("90.000001", true, "geography: latitude out of range at byte 9") { ok = false; }
  if !dec_err_is("180.000001", false, "geography: longitude out of range at byte 10") { ok = false; }
  if !dec_err_is("1234", true, "geography: too many degree digits at byte 3") { ok = false; }
  if !dec_err_is("37.9750001", true, "geography: too many fraction digits at byte 9") { ok = false; }
  if !dec_err_is("37,975", true, "geography: unexpected character at byte 2") { ok = false; }
  if !dec_err_is("37.975x", true, "geography: bad hemisphere at byte 6") { ok = false; }
  if !dec_err_is("37.", true, "geography: missing fraction digits at byte 3") { ok = false; }
  if !dec_err_is("x37", true, "geography: bad hemisphere at byte 0") { ok = false; }
  if !dec_err_is("45E", true, "geography: wrong hemisphere for axis at byte 2") { ok = false; }
  if !dec_err_is("45N", false, "geography: wrong hemisphere for axis at byte 2") { ok = false; }
  if !dec_err_is("-37.975N", true, "geography: hemisphere conflicts with sign at byte 7") { ok = false; }
  if !dec_err_is("N37N", true, "geography: duplicate hemisphere at byte 3") { ok = false; }
  return assert(ok, "decimal parse errors: bounds, shapes, axis and sign conflicts with offsets");
}

fn t15() -> TestResult {
  var ok = streq(geog_coord_format_decimal(37975000), "37.975000");
  if !streq(geog_coord_format_decimal(0 - 37975000), "-37.975000") { ok = false; }
  if !streq(geog_coord_format_decimal(0), "0.000000") { ok = false; }
  if !streq(geog_coord_format_decimal(90000000), "90.000000") { ok = false; }
  if !streq(geog_coord_format_decimal(12500000), "12.500000") { ok = false; }
  if !streq(geog_coord_format_decimal(0 - 122500000), "-122.500000") { ok = false; }
  if !streq(geog_coord_format_decimal(1), "0.000001") { ok = false; }
  if dec_of(geog_coord_format_decimal(37975000), true) != 37975000 { ok = false; }
  if dec_of(geog_coord_format_decimal(0 - 37975000), true) != 0 - 37975000 { ok = false; }
  if dec_of(geog_coord_format_decimal(0), true) != 0 { ok = false; }
  if dec_of(geog_coord_format_decimal(123456789), false) != 123456789 { ok = false; }
  if dec_of(geog_coord_format_decimal(0 - 180000000), false) != 0 - 180000000 { ok = false; }
  return assert(ok, "decimal render: fixed six decimals signed; parse(render(x)) == x");
}

fn t16() -> TestResult {
  let deg = str_of2(194, 176);
  let masc = str_of2(194, 186);
  let prime = str_of3(226, 128, 178);
  let dprime = str_of3(226, 128, 179);
  var ok = dms_of("37" + deg + "58'30\"N", true) == 37975000;
  if dms_of("37d58m30\"N", true) != 37975000 { ok = false; }
  if dms_of("37" + masc + "58'30\"N", true) != 37975000 { ok = false; }
  if dms_of("37" + deg + "58" + prime + "30" + dprime + "N", true) != 37975000 { ok = false; }
  if dms_of("37" + deg + "58'30\"n", true) != 37975000 { ok = false; }
  if dms_of("S37" + deg + "58'30\"", true) != 0 - 37975000 { ok = false; }
  if dms_of("37" + deg + "58'30.5\"N", true) != 37975138 { ok = false; }
  if dms_of("0" + deg + "0'0\"N", true) != 0 { ok = false; }
  if dms_of("90" + deg + "0'0\"N", true) != 90000000 { ok = false; }
  if dms_of("180" + deg + "0'0\"E", false) != 180000000 { ok = false; }
  if dms_of("122" + deg + "30'0\"W", false) != 0 - 122500000 { ok = false; }
  return assert(ok, "DMS parse: symbol variants, hemispheres, exact 37.975 fixture");
}

fn t17() -> TestResult {
  let deg = str_of2(194, 176);
  var ok = dms_err_is("", true, "geography: empty input");
  if !dms_err_is("37 58'30\"N", true, "geography: missing degree symbol at byte 2") { ok = false; }
  if !dms_err_is("37" + deg + "58'60\"N", true, "geography: seconds out of range at byte 7") { ok = false; }
  if !dms_err_is("37" + deg + "60'00\"N", true, "geography: minutes out of range at byte 4") { ok = false; }
  if !dms_err_is("91" + deg + "00'00\"N", true, "geography: latitude out of range at byte 11") { ok = false; }
  if !dms_err_is("180" + deg + "00'00.000001\"E", false, "geography: longitude out of range at byte 19") { ok = false; }
  if !dms_err_is("37" + deg + "58'30\"E", true, "geography: wrong hemisphere for axis at byte 10") { ok = false; }
  if !dms_err_is("37" + deg + "58'30N", true, "geography: missing second symbol at byte 9") { ok = false; }
  if !dms_err_is("37d58m", true, "geography: missing second digits at byte 6") { ok = false; }
  if !dms_err_is("37" + deg + "58'30.0000001\"N", true, "geography: too many fraction digits at byte 16") { ok = false; }
  if !dms_err_is("37" + deg + "58'30.\"N", true, "geography: missing fraction digits at byte 10") { ok = false; }
  return assert(ok, "DMS parse errors: symbols, ranges and bounds carry byte offsets");
}

fn t18() -> TestResult {
  let deg = str_of2(194, 176);
  var ok = streq(geog_coord_format_dms(37975000, true), "37" + deg + "58'30.000000\"N");
  if !streq(geog_coord_format_dms(0 - 37975000, true), "37" + deg + "58'30.000000\"S") { ok = false; }
  if !streq(geog_coord_format_dms(37975000, false), "37" + deg + "58'30.000000\"E") { ok = false; }
  if !streq(geog_coord_format_dms(0 - 122500000, false), "122" + deg + "30'00.000000\"W") { ok = false; }
  if !streq(geog_coord_format_dms(0, true), "0" + deg + "00'00.000000\"N") { ok = false; }
  if !streq(geog_coord_format_dms(0, false), "0" + deg + "00'00.000000\"E") { ok = false; }
  if !streq(geog_coord_format_dms(90000000, true), "90" + deg + "00'00.000000\"N") { ok = false; }
  if !streq(geog_coord_format_dms(180000000, false), "180" + deg + "00'00.000000\"E") { ok = false; }
  if dms_of(geog_coord_format_dms(37975000, true), true) != 37975000 { ok = false; }
  if dms_of(geog_coord_format_dms(0 - 37975000, true), true) != 0 - 37975000 { ok = false; }
  if dms_of(geog_coord_format_dms(1, true), true) != 1 { ok = false; }
  if dms_of(geog_coord_format_dms(0 - 1, true), true) != 0 - 1 { ok = false; }
  if dms_of(geog_coord_format_dms(12345678, true), true) != 12345678 { ok = false; }
  if dms_of(geog_coord_format_dms(999999, false), false) != 999999 { ok = false; }
  if dms_of(geog_coord_format_dms(123456789, false), false) != 123456789 { ok = false; }
  if dms_of(geog_coord_format_dms(0 - 180000000, false), false) != 0 - 180000000 { ok = false; }
  return assert(ok, "DMS render: canonical fixed six-second-decimals; parse(render(x)) == x");
}

fn t19() -> TestResult {
  var a2s = Vec[Str].new();
  var a3s = Vec[Str].new();
  var nums = Vec[Str].new();
  var conts = Vec[Str].new();
  var regs = Vec[Str].new();
  var ok = true;
  var i = 0;
  while i < geog_country_count() {
    match geog_country_at(i) {
      Ok(c) => {
        let v2: Str = c.alpha2;
        let v3: Str = c.alpha3;
        let vn: Str = c.numeric;
        let vc: Str = c.continent;
        let vr: Str = c.region;
        a2s.push(v2);
        a3s.push(v3);
        nums.push(vn);
        conts.push(vc);
        regs.push(vr);
      },
      Err(e) => { ok = false; },
    }
    i = i + 1;
  }
  if a2s.len() != 249 { ok = false; }
  if a3s.len() != 249 { ok = false; }
  if nums.len() != 249 { ok = false; }
  if conts.len() != 249 { ok = false; }
  if regs.len() != 249 { ok = false; }
  i = 0;
  while i < a2s.len() {
    let v2: Str = a2s[i];
    let v3: Str = a3s[i];
    let vn: Str = nums[i];
    let vc: Str = conts[i];
    let vr: Str = regs[i];
    if v2.len() != 2 { ok = false; }
    if v3.len() != 3 { ok = false; }
    if vn.len() != 3 { ok = false; }
    if !geog_country_is_valid_alpha2(v2) { ok = false; }
    if !geog_country_is_valid_alpha3(v3) { ok = false; }
    if !geog_country_is_valid_numeric(vn) { ok = false; }
    if !geog_region_is_valid(vc) { ok = false; }
    if !geog_region_is_valid(vr) { ok = false; }
    if !streq(reg_parent_of(vc), "") { ok = false; }
    if !streq(top_of(vr), vc) { ok = false; }
    if !streq(num_of(v2), vn) { ok = false; }
    if !streq(a2_by_a3(v3), v2) { ok = false; }
    if !streq(a2_by_num(vn), v2) { ok = false; }
    if i > 0 {
      let prev: Str = a2s[i - 1];
      if compare.str_compare(prev, v2) >= 0 { ok = false; }
    }
    var j = i + 1;
    while j < a2s.len() {
      let x2: Str = a2s[j];
      let x3: Str = a3s[j];
      let xn: Str = nums[j];
      if streq(v2, x2) { ok = false; }
      if streq(v3, x3) { ok = false; }
      if streq(vn, xn) { ok = false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return assert(ok, "country integrity: 249 rows, unique 2/3/3 keys, sorted, regions resolve");
}

fn t20() -> TestResult {
  var codes = Vec[Str].new();
  var names = Vec[Str].new();
  var parents = Vec[Str].new();
  var ok = true;
  var i = 0;
  while i < geog_region_count() {
    match geog_region_at(i) {
      Ok(r) => {
        let c: Str = r.code;
        let nm: Str = r.name;
        let p: Str = r.parent;
        codes.push(c);
        names.push(nm);
        parents.push(p);
      },
      Err(e) => { ok = false; },
    }
    i = i + 1;
  }
  if codes.len() != 30 { ok = false; }
  if names.len() != 30 { ok = false; }
  if parents.len() != 30 { ok = false; }
  i = 0;
  while i < codes.len() {
    let c: Str = codes[i];
    let nm: Str = names[i];
    let p: Str = parents[i];
    if c.len() != 3 { ok = false; }
    if nm.len() == 0 { ok = false; }
    if !geog_region_is_valid(c) { ok = false; }
    if p.len() > 0 {
      if !geog_region_is_valid(p) { ok = false; }
      let pp = reg_parent_of(p);
      if pp.len() > 0 {
        let ppp = reg_parent_of(pp);
        if ppp.len() != 0 { ok = false; }
      }
    }
    if i > 0 {
      let prev: Str = codes[i - 1];
      if compare.str_compare(prev, c) >= 0 { ok = false; }
    }
    var j = i + 1;
    while j < codes.len() {
      let c2: Str = codes[j];
      let n2: Str = names[j];
      if streq(c, c2) { ok = false; }
      if streq(nm, n2) { ok = false; }
      j = j + 1;
    }
    i = i + 1;
  }
  var africa = 0;
  var americas = 0;
  var asia = 0;
  var europe = 0;
  var oceania = 0;
  var antarctica = 0;
  var k = 0;
  while k < geog_country_count() {
    match geog_country_at(k) {
      Ok(c) => {
        let vc: Str = c.continent;
        if !geog_region_is_valid(vc) { ok = false; }
        if !streq(reg_parent_of(vc), "") { ok = false; }
        if streq(vc, "002") { africa = africa + 1; }
        if streq(vc, "019") { americas = americas + 1; }
        if streq(vc, "142") { asia = asia + 1; }
        if streq(vc, "150") { europe = europe + 1; }
        if streq(vc, "009") { oceania = oceania + 1; }
        if streq(vc, "010") { antarctica = antarctica + 1; }
      },
      Err(e) => { ok = false; },
    }
    k = k + 1;
  }
  if africa != 60 { ok = false; }
  if americas != 57 { ok = false; }
  if asia != 51 { ok = false; }
  if europe != 51 { ok = false; }
  if oceania != 29 { ok = false; }
  if antarctica != 1 { ok = false; }
  return assert(ok, "region integrity: 30 unique sorted rows, parent chains, continent totals");
}

fn t21() -> TestResult {
  var ok = geog_coord_in_range(90000000, true);
  if !geog_coord_in_range(0 - 90000000, true) { ok = false; }
  if geog_coord_in_range(90000001, true) { ok = false; }
  if geog_coord_in_range(0 - 90000001, true) { ok = false; }
  if !geog_coord_in_range(180000000, false) { ok = false; }
  if !geog_coord_in_range(0 - 180000000, false) { ok = false; }
  if geog_coord_in_range(180000001, false) { ok = false; }
  if !geog_coord_in_range(0, true) { ok = false; }
  if !geog_coord_in_range(123456789, false) { ok = false; }
  if geog_coord_in_range(123456789, true) { ok = false; }
  if !geog_coord_in_range(37975000, true) { ok = false; }
  if !geog_coord_in_range(0 - 122500000, false) { ok = false; }
  return assert(ok, "coordinate range predicate: inclusive axis bounds");
}

fn main() -> Int {
  io.println("=== xiom.geography conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.geography: all tests passed");
  } else {
    io.println("xiom.geography: tests failed");
  }
  return failed;
}
