// XIOM -- xiom.l10n.address conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.l10n.address module against its
// documented template, render, field-inventory and validation contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every fixture is a synthetic address built in-test (no real
// personal or subscriber data). Templates and separators pinned here are the
// ones implemented in the module under test and tabulated in SPEC.md.
//
// BUG 17 note: all Str equality goes through str_compare (via streq); every
// Vec element read is bound to a typed local before use; test dispatch is a
// direct call chain (t1..t22 from main), never a Vec[fn] table.

module l10n_address_tests
use xiom.io; use xiom.test;
use xiom.l10n.address;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Address fixtures
// ---------------------------------------------------------------------------

fn mk(name: Str, org: Str, street1: Str, street2: Str, city: Str, region: Str, postal: Str, cc: Str) -> Address {
  let a = Address{ name: name; organization: org; street1: street1; street2: street2; city: city; region: region; postal_code: postal; country_code: cc };
  return a;
}

fn blank() -> Address {
  return mk("", "", "", "", "", "", "", "");
}

// ---------------------------------------------------------------------------
// Result probes (never compare Str with ==; always return typed locals)
// ---------------------------------------------------------------------------

fn render_ok_eq(country: Str, a: &Address, want: Str) -> Bool {
  match address_render(country, a) {
    Ok(text) => { return streq(text, want); },
    Err(_) => { return false; },
  }
}

fn render_err_is(country: Str, a: &Address, want: Str) -> Bool {
  match address_render(country, a) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn validate_len(country: Str, a: &Address) -> Int {
  let errs = address_validate(country, a);
  return errs.len();
}

fn validate_at(country: Str, a: &Address, i: Int) -> Str {
  let errs = address_validate(country, a);
  if i < 0 { return ""; }
  if i >= errs.len() { return ""; }
  let s: Str = errs[i];
  return s;
}

fn field_count(country: Str) -> Int {
  let inv = address_fields(country);
  return inv.names.len();
}

fn field_name_at(country: Str, i: Int) -> Str {
  let inv = address_fields(country);
  let names: Vec[Str] = inv.names;
  if i < 0 { return ""; }
  if i >= names.len() { return ""; }
  let s: Str = names[i];
  return s;
}

fn field_req_at(country: Str, i: Int) -> Int {
  let inv = address_fields(country);
  let reqs: Vec[Int] = inv.required;
  if i < 0 { return -1; }
  if i >= reqs.len() { return -1; }
  let r: Int = reqs[i];
  return r;
}

fn template_parallel_ok(country: Str) -> Bool {
  let t = address_template(country);
  let f: Vec[Int] = t.slot_field;
  let l: Vec[Int] = t.slot_line;
  let r: Vec[Int] = t.slot_required;
  let s: Vec[Str] = t.slot_sep;
  if f.len() != l.len() { return false; }
  if f.len() != r.len() { return false; }
  if f.len() != s.len() { return false; }
  return f.len() > 0;
}

fn clean_for(country: Str) -> Bool {
  let a = mk("Ada Example", "Example Org", "1 Example Way", "Floor 2", "Exampleton", "EX", "12345", country);
  let errs = address_validate(country, &a);
  if errs.len() != 0 { return false; }
  match address_render(country, &a) {
    Ok(text) => { return text.len() > 0; },
    Err(_) => { return false; },
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let a = mk("Ada Lovelace", "Analytical Engines", "123 Analytical Way", "Suite 200", "Springfield", "IL", "62704", "US");
  let ok = render_ok_eq("US", &a, "Ada Lovelace\nAnalytical Engines\n123 Analytical Way\nSuite 200\nSpringfield, IL 62704");
  return assert(ok, "US: full render is name/org/street1/street2/city,region postal");
}

fn t2() -> TestResult {
  let a = mk("Ada Lovelace", "", "123 Analytical Way", "", "Springfield", "IL", "62704", "US");
  var ok = render_ok_eq("US", &a, "Ada Lovelace\n123 Analytical Way\nSpringfield, IL 62704");
  let b = mk("Ada Lovelace", "", "123 Analytical Way", "Suite 200", "Springfield", "IL", "62704", "US");
  if !render_ok_eq("US", &b, "Ada Lovelace\n123 Analytical Way\nSuite 200\nSpringfield, IL 62704") { ok = false; }
  return assert(ok, "US: absent optional slots vanish without blank lines");
}

fn t3() -> TestResult {
  let a = mk("Ada Lovelace", "", "123 Analytical Way", "", "Springfield", "", "62704", "US");
  var ok = render_err_is("US", &a, "address: missing required field: region");
  let b = mk("Ada Lovelace", "", "", "", "Springfield", "IL", "62704", "US");
  if !render_err_is("US", &b, "address: missing required field: street1") { ok = false; }
  let c = mk("Ada Lovelace", "", "123 Analytical Way", "", "Springfield", "IL", "", "US");
  if !render_err_is("US", &c, "address: missing required field: postal_code") { ok = false; }
  let d = mk("", "", "123 Analytical Way", "", "Springfield", "IL", "62704", "US");
  if !render_err_is("US", &d, "address: missing required field: name") { ok = false; }
  return assert(ok, "US: each absent required field is the first render error");
}

fn t4() -> TestResult {
  let a = blank();
  let errs = address_validate("US", &a);
  var ok = errs.len() == 5;
  if !streq(validate_at("US", &a, 0), "address: missing required field: name") { ok = false; }
  if !streq(validate_at("US", &a, 1), "address: missing required field: street1") { ok = false; }
  if !streq(validate_at("US", &a, 2), "address: missing required field: city") { ok = false; }
  if !streq(validate_at("US", &a, 3), "address: missing required field: region") { ok = false; }
  if !streq(validate_at("US", &a, 4), "address: missing required field: postal_code") { ok = false; }
  return assert(ok, "US: validate lists all absent required fields in slot order");
}

fn t5() -> TestResult {
  let a = mk("Ada Lovelace", "", "123 Analytical Way", "", "", "", "62704", "US");
  let errs = address_validate("US", &a);
  var ok = errs.len() == 2;
  let first: Str = errs[0];
  if !render_err_is("US", &a, first) { ok = false; }
  let b = mk("Ada Lovelace", "", "123 Analytical Way", "", "Springfield", "IL", "62704", "US");
  let ok_errs = address_validate("US", &b);
  if ok_errs.len() != 0 { ok = false; }
  if !render_ok_eq("US", &b, "Ada Lovelace\n123 Analytical Way\nSpringfield, IL 62704") { ok = false; }
  return assert(ok, "validate and render agree: empty list <=> Ok render");
}

fn t6() -> TestResult {
  let a = mk("Grace Hopper", "", "10 Compiler Lane", "", "London", "", "EC1A 1BB", "GB");
  var ok = render_ok_eq("GB", &a, "Grace Hopper\n10 Compiler Lane\nLondon\nEC1A 1BB");
  if !streq(field_name_at("GB", 4), "city") { ok = false; }
  if !streq(field_name_at("GB", 5), "postal_code") { ok = false; }
  return assert(ok, "GB: postcode occupies its own final line");
}

fn t7() -> TestResult {
  let a = mk("Konrad Zuse", "", "Zuseplatz 1", "", "Berlin", "BE", "10115", "DE");
  var ok = render_ok_eq("DE", &a, "Konrad Zuse\nZuseplatz 1\n10115 Berlin");
  if field_count("DE") != 6 { ok = false; }
  if !streq(field_name_at("DE", 4), "postal_code") { ok = false; }
  if !streq(field_name_at("DE", 5), "city") { ok = false; }
  return assert(ok, "DE: postal code precedes the city; region is not a template field");
}

fn t8() -> TestResult {
  let a = mk("Marie Curie", "", "5 Rue Pierre", "", "Paris", "", "75005", "FR");
  var ok = render_ok_eq("FR", &a, "Marie Curie\n5 Rue Pierre\n75005 Paris");
  if field_count("FR") != 6 { ok = false; }
  return assert(ok, "FR: postal code and city share one line");
}

fn t9() -> TestResult {
  let a = mk("Kai Tanaka", "Sakura Labs", "1-1 Chiyoda", "", "Chiyoda", "Tokyo", "100-0001", "JP");
  let ok = render_ok_eq("JP", &a, "100-0001\nTokyo Chiyoda\n1-1 Chiyoda\nSakura Labs\nKai Tanaka");
  return assert(ok, "JP: postal first, region+city inline, recipient last");
}

fn t10() -> TestResult {
  let a = mk("Kai Tanaka", "", "1-1 Chiyoda", "", "Chiyoda", "Tokyo", "100-0001", "JP");
  var ok = render_ok_eq("JP", &a, "100-0001\nTokyo Chiyoda\n1-1 Chiyoda\nKai Tanaka");
  let b = mk("Li Wei", "", "1 Dongsi Street", "", "Dongcheng", "Beijing", "100010", "CN");
  if !render_ok_eq("CN", &b, "100010\nBeijing\nDongcheng\n1 Dongsi Street\nLi Wei") { ok = false; }
  return assert(ok, "JP/CN: big-to-small order with recipient last");
}

fn t11() -> TestResult {
  var ok = streq(field_name_at("US", 0), "name");
  if !streq(field_name_at("JP", 0), "postal_code") { ok = false; }
  if !streq(field_name_at("JP", 6), "name") { ok = false; }
  if !streq(field_name_at("DE", 4), "postal_code") { ok = false; }
  if !streq(field_name_at("DE", 5), "city") { ok = false; }
  if !streq(field_name_at("GB", 5), "postal_code") { ok = false; }
  if !streq(field_name_at("CN", 1), "region") { ok = false; }
  if !streq(field_name_at("CN", 2), "city") { ok = false; }
  return assert(ok, "US/GB/DE/FR/JP/CN field orders differ as specified");
}

fn t12() -> TestResult {
  let a = mk("Ada Lovelace", "", "1 Way", "", "Town", "TS", "12345", "ZZ");
  var ok = render_err_is("ZZ", &a, "address: unknown country: ZZ");
  if !render_err_is("zz", &a, "address: unknown country: ZZ") { ok = false; }
  let b = blank();
  if !render_err_is("", &b, "address: unknown country: ") { ok = false; }
  return assert(ok, "unknown country: render error names the upper-cased code");
}

fn t13() -> TestResult {
  let a = mk("Ada", "", "1 Way", "", "Town", "TS", "12345", "ZZ");
  var ok = validate_len("ZZ", &a) == 1;
  if !streq(validate_at("ZZ", &a, 0), "address: unknown country: ZZ") { ok = false; }
  if field_count("ZZ") != 0 { ok = false; }
  let t = address_template("ZZ");
  let cc: Str = t.country_code;
  if cc.len() != 0 { ok = false; }
  let f: Vec[Int] = t.slot_field;
  if f.len() != 0 { ok = false; }
  let b = blank();
  if validate_len("", &b) != 1 { ok = false; }
  return assert(ok, "unknown country: one validate error, empty fields/template");
}

fn t14() -> TestResult {
  let a = mk("Marie Curie", "", "5 Rue Pierre", "", "Paris", "", "75005", "DE");
  var ok = render_ok_eq("fr", &a, "Marie Curie\n5 Rue Pierre\n75005 Paris");
  if !render_ok_eq("Fr", &a, "Marie Curie\n5 Rue Pierre\n75005 Paris") { ok = false; }
  if !address_supports("us") { ok = false; }
  if !address_supports("Us") { ok = false; }
  if address_supports("XX") { ok = false; }
  return assert(ok, "country selection is ASCII case-insensitive");
}

fn t15() -> TestResult {
  var ok = field_count("US") == 7;
  if !streq(field_name_at("US", 0), "name") { ok = false; }
  if !streq(field_name_at("US", 1), "organization") { ok = false; }
  if !streq(field_name_at("US", 2), "street1") { ok = false; }
  if !streq(field_name_at("US", 3), "street2") { ok = false; }
  if !streq(field_name_at("US", 4), "city") { ok = false; }
  if !streq(field_name_at("US", 5), "region") { ok = false; }
  if !streq(field_name_at("US", 6), "postal_code") { ok = false; }
  if field_req_at("US", 0) != 1 { ok = false; }
  if field_req_at("US", 1) != 0 { ok = false; }
  if field_req_at("US", 2) != 1 { ok = false; }
  if field_req_at("US", 3) != 0 { ok = false; }
  if field_req_at("US", 4) != 1 { ok = false; }
  if field_req_at("US", 5) != 1 { ok = false; }
  if field_req_at("US", 6) != 1 { ok = false; }
  return assert(ok, "US: field inventory names and required flags in render order");
}

fn t16() -> TestResult {
  var ok = field_count("DE") == 6;
  if field_count("GB") != 6 { ok = false; }
  if field_count("IT") != 7 { ok = false; }
  if field_count("JP") != 7 { ok = false; }
  if field_count("CN") != 7 { ok = false; }
  if field_count("BR") != 7 { ok = false; }
  if !streq(field_name_at("IT", 6), "region") { ok = false; }
  if !streq(field_name_at("BR", 4), "postal_code") { ok = false; }
  if field_req_at("FR", 1) != 0 { ok = false; }
  return assert(ok, "field inventories expose each country's shape and flags");
}

fn t17() -> TestResult {
  var ok = address_country_count() == 12;
  if !clean_for("US") { ok = false; }
  if !clean_for("CA") { ok = false; }
  if !clean_for("GB") { ok = false; }
  if !clean_for("DE") { ok = false; }
  if !clean_for("FR") { ok = false; }
  if !clean_for("NL") { ok = false; }
  if !clean_for("IT") { ok = false; }
  if !clean_for("JP") { ok = false; }
  if !clean_for("CN") { ok = false; }
  if !clean_for("AU") { ok = false; }
  if !clean_for("IN") { ok = false; }
  if !clean_for("BR") { ok = false; }
  return assert(ok, "all 12 countries render and validate a complete address");
}

fn t18() -> TestResult {
  let v = address_countries();
  var ok = v.len() == 12;
  let first: Str = v[0];
  let last: Str = v[11];
  if !streq(first, "AU") { ok = false; }
  if !streq(last, "US") { ok = false; }
  return assert(ok, "address_countries lists the 12 codes in sorted order");
}

fn t19() -> TestResult {
  let au = mk("Bindi Example", "", "12 Harbour Road", "", "Sydney", "NSW", "2000", "AU");
  var ok = render_ok_eq("AU", &au, "Bindi Example\n12 Harbour Road\nSydney NSW 2000");
  let ca = mk("Maple Example", "", "100 Bank Street", "", "Ottawa", "ON", "K1A 0B1", "CA");
  if !render_ok_eq("CA", &ca, "Maple Example\n100 Bank Street\nOttawa ON K1A 0B1") { ok = false; }
  let nl = mk("Tulip Example", "", "1 Gracht", "", "Amsterdam", "", "1011 AB", "NL");
  if !render_ok_eq("NL", &nl, "Tulip Example\n1 Gracht\n1011 AB Amsterdam") { ok = false; }
  let it = mk("Roma Example", "", "1 Via Roma", "", "Roma", "RM", "00185", "IT");
  if !render_ok_eq("IT", &it, "Roma Example\n1 Via Roma\n00185 Roma RM") { ok = false; }
  let ind = mk("Asha Example", "", "1 MG Road", "", "Mumbai", "Maharashtra", "400001", "IN");
  if !render_ok_eq("IN", &ind, "Asha Example\n1 MG Road\nMumbai, Maharashtra 400001") { ok = false; }
  let br = mk("Rio Example", "", "1 Avenida", "", "Sao Paulo", "SP", "01000-000", "BR");
  if !render_ok_eq("BR", &br, "Rio Example\n1 Avenida\n01000-000 Sao Paulo - SP") { ok = false; }
  return assert(ok, "AU/CA/NL/IT/IN/BR render their documented in-line separators");
}

fn t20() -> TestResult {
  let de = mk("Konrad Zuse", "", "Zuseplatz 1", "", "Berlin", "", "10115", "DE");
  var ok = render_ok_eq("", &de, "Konrad Zuse\nZuseplatz 1\n10115 Berlin");
  if validate_len("", &de) != 0 { ok = false; }
  let bad = mk("Ada", "", "1 Way", "", "Town", "TS", "12345", "ZZ");
  if !render_err_is("", &bad, "address: unknown country: ZZ") { ok = false; }
  return assert(ok, "empty selector falls back to the address country_code");
}

fn t21() -> TestResult {
  var ok = streq(address_template_summary("US"), "US: 7 slots, 5 lines");
  if !streq(address_template_summary("JP"), "JP: 7 slots, 6 lines") { ok = false; }
  if !streq(address_template_summary("CN"), "CN: 7 slots, 7 lines") { ok = false; }
  if !streq(address_template_summary("DE"), "DE: 6 slots, 5 lines") { ok = false; }
  if !streq(address_template_summary("ZZ"), "address: unknown country: ZZ") { ok = false; }
  if !template_parallel_ok("US") { ok = false; }
  if !template_parallel_ok("CA") { ok = false; }
  if !template_parallel_ok("GB") { ok = false; }
  if !template_parallel_ok("DE") { ok = false; }
  if !template_parallel_ok("FR") { ok = false; }
  if !template_parallel_ok("NL") { ok = false; }
  if !template_parallel_ok("IT") { ok = false; }
  if !template_parallel_ok("JP") { ok = false; }
  if !template_parallel_ok("CN") { ok = false; }
  if !template_parallel_ok("AU") { ok = false; }
  if !template_parallel_ok("IN") { ok = false; }
  if !template_parallel_ok("BR") { ok = false; }
  return assert(ok, "template summaries and parallel-array integrity");
}

fn t22() -> TestResult {
  var ok = streq(address_field_name(0), "name");
  if !streq(address_field_name(6), "postal_code") { ok = false; }
  if !streq(address_field_name(7), "country_code") { ok = false; }
  if !streq(address_field_name(99), "unknown") { ok = false; }
  return assert(ok, "field codes map to canonical names");
}

fn main() -> Int {
  io.println("=== xiom.l10n.address conformance tests ===");
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
    io.println("xiom.l10n.address: all tests passed");
  } else {
    io.println("xiom.l10n.address: tests failed");
  }
  return failed;
}
