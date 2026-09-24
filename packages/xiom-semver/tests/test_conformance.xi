// XIOM -- xiom.semver conformance tests (32 checks)
// Port task: prove the pure-XIOM xiom.semver module against its documented
// SemVer 2.0 parsing, precedence and single-comparator range contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module semver_tests
use xiom.io; use xiom.test; use xiom.semver;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every string
// check is routed through streq and semver_satisfies_any copies each element
// into a typed local before calling the library.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ok_parse(s: Str) -> Bool {
  match semver_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn nums_are(s: Str, maj: Int, min: Int, pat: Int) -> Bool {
  match semver_parse(s) {
    Ok(v) => { return v.major == maj && v.minor == min && v.patch == pat; },
    Err(e) => { return false; },
  }
}

fn pre_is(s: Str, want: Str) -> Bool {
  match semver_parse(s) {
    Ok(v) => { return streq(v.pre, want); },
    Err(e) => { return false; },
  }
}

fn build_is(s: Str, want: Str) -> Bool {
  match semver_parse(s) {
    Ok(v) => { return streq(v.build, want); },
    Err(e) => { return false; },
  }
}

fn err_is(s: Str, want: Str) -> Bool {
  match semver_parse(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn fmt_is(s: Str, want: Str) -> Bool {
  match semver_parse(s) {
    Ok(v) => { return streq(semver_format(&v), want); },
    Err(e) => { return false; },
  }
}

fn cmp_of(a: Str, b: Str) -> Int {
  let ar = semver_parse(a);
  let br = semver_parse(b);
  match ar {
    Ok(av) => {
      match br {
        Ok(bv) => { return semver_compare(&av, &bv); },
        Err(e) => { return -9; },
      }
    },
    Err(e) => { return -9; },
  }
}

fn is_pre(s: Str, want: Bool) -> Bool {
  match semver_parse(s) {
    Ok(v) => { return semver_is_prerelease(&v) == want; },
    Err(e) => { return false; },
  }
}

fn sat_is(s: Str, range: Str, want: Bool) -> Bool {
  match semver_parse(s) {
    Ok(v) => {
      match semver_satisfies(&v, range) {
        Ok(b) => { return b == want; },
        Err(e) => { return false; },
      }
    },
    Err(e) => { return false; },
  }
}

fn sat_err_is(s: Str, range: Str, want: Str) -> Bool {
  match semver_parse(s) {
    Ok(v) => {
      match semver_satisfies(&v, range) {
        Ok(b) => { return false; },
        Err(e) => { return streq(e, want); },
      }
    },
    Err(e) => { return false; },
  }
}

fn two_ranges(a: Str, b: Str) -> Vec[Str] {
  let v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn any_is(s: Str, ranges: Vec[Str], want: Bool) -> Bool {
  match semver_parse(s) {
    Ok(v) => {
      match semver_satisfies_any(&v, &ranges) {
        Ok(b) => { return b == want; },
        Err(e) => { return false; },
      }
    },
    Err(e) => { return false; },
  }
}

fn any2_is(s: Str, r1: Str, r2: Str, want: Bool) -> Bool {
  return any_is(s, two_ranges(r1, r2), want);
}

fn any_err_is(s: Str, ranges: Vec[Str], want: Str) -> Bool {
  match semver_parse(s) {
    Ok(v) => {
      match semver_satisfies_any(&v, &ranges) {
        Ok(b) => { return false; },
        Err(e) => { return streq(e, want); },
      }
    },
    Err(e) => { return false; },
  }
}

fn t1() -> TestResult {
  var ok = nums_are("1.2.3", 1, 2, 3);
  if !nums_are("0.0.0", 0, 0, 0) { ok = false; }
  if !nums_are("10.20.30", 10, 20, 30) { ok = false; }
  if !pre_is("1.2.3", "") { ok = false; }
  if !build_is("1.2.3", "") { ok = false; }
  return assert(ok, "parse: MAJOR.MINOR.PATCH and zeros");
}

fn t2() -> TestResult {
  var ok = pre_is("1.0.0-alpha.1", "alpha.1");
  if !pre_is("1.0.0-x.7.z.92", "x.7.z.92") { ok = false; }
  if !pre_is("1.0.0-0", "0") { ok = false; }
  if !pre_is("1.0.0-1.2.3", "1.2.3") { ok = false; }
  if !pre_is("1.0.0-alpha-x.1a", "alpha-x.1a") { ok = false; }
  return assert(ok, "parse: pre-release stored as the raw dotted string");
}

fn t3() -> TestResult {
  var ok = build_is("1.0.0+20130313144700", "20130313144700");
  if !build_is("1.0.0+build.01.2", "build.01.2") { ok = false; }
  if !build_is("1.0.0+x-y-z.9", "x-y-z.9") { ok = false; }
  return assert(ok, "parse: build metadata stored raw, leading zeros allowed");
}

fn t4() -> TestResult {
  var ok = pre_is("1.2.3-beta.2+exp.sha.5114f85", "beta.2");
  if !build_is("1.2.3-beta.2+exp.sha.5114f85", "exp.sha.5114f85") { ok = false; }
  if !nums_are("1.2.3-beta.2+exp.sha.5114f85", 1, 2, 3) { ok = false; }
  return assert(ok, "parse: pre-release and build combine");
}

fn t5() -> TestResult {
  var ok = err_is("01.2.3", "semver: leading zero in major: 01.2.3");
  if !err_is("1.02.3", "semver: leading zero in minor: 1.02.3") { ok = false; }
  if !err_is("1.2.03", "semver: leading zero in patch: 1.2.03") { ok = false; }
  if !err_is("1.0.0-01", "semver: leading zero in pre-release identifier: 1.0.0-01") { ok = false; }
  if !err_is("1.0.0-1.007", "semver: leading zero in pre-release identifier: 1.0.0-1.007") { ok = false; }
  if !ok_parse("0.0.0") { ok = false; }
  if !ok_parse("1.0.0-0") { ok = false; }
  if !ok_parse("1.0.0+a.01") { ok = false; }
  return assert(ok, "parse errors: leading zeros in numeric components");
}

fn t6() -> TestResult {
  var ok = err_is("1", "semver: missing minor: 1");
  if !err_is("1.2", "semver: missing patch: 1.2") { ok = false; }
  if !err_is("1.", "semver: missing minor: 1.") { ok = false; }
  if !err_is("1.2.", "semver: missing patch: 1.2.") { ok = false; }
  return assert(ok, "parse errors: missing components");
}

fn t7() -> TestResult {
  var ok = err_is("v1.2.3", "semver: malformed version: v1.2.3");
  if !err_is("1.2.3 ", "semver: malformed version: 1.2.3 ") { ok = false; }
  if !err_is(" 1.2.3", "semver: malformed version:  1.2.3") { ok = false; }
  if !err_is("1.2.3.4", "semver: malformed version: 1.2.3.4") { ok = false; }
  if !err_is("1.2.3-", "semver: empty pre-release identifier: 1.2.3-") { ok = false; }
  if !err_is("1.2.3-alpha..1", "semver: empty pre-release identifier: 1.2.3-alpha..1") { ok = false; }
  if !err_is("1.2.3-alpha_1", "semver: malformed pre-release: 1.2.3-alpha_1") { ok = false; }
  if !err_is("1.2.3+", "semver: empty build identifier: 1.2.3+") { ok = false; }
  if !err_is("1.2.3+build!", "semver: malformed build: 1.2.3+build!") { ok = false; }
  if !err_is("1.2.3-alpha+", "semver: empty build identifier: 1.2.3-alpha+") { ok = false; }
  return assert(ok, "parse errors: junk, spaces and empty identifiers");
}

fn t8() -> TestResult {
  var ok = err_is("", "semver: empty input");
  if !err_is("+", "semver: malformed version: +") { ok = false; }
  if !err_is("-", "semver: malformed version: -") { ok = false; }
  return assert(ok, "parse errors: empty input and bare separators");
}

fn t9() -> TestResult {
  var ok = fmt_is("0.0.0", "0.0.0");
  if !fmt_is("1.2.3", "1.2.3") { ok = false; }
  if !fmt_is("1.0.0-alpha.1", "1.0.0-alpha.1") { ok = false; }
  if !fmt_is("2.0.0+build.5", "2.0.0+build.5") { ok = false; }
  if !fmt_is("1.2.3-beta.2+exp.sha.5114f85", "1.2.3-beta.2+exp.sha.5114f85") { ok = false; }
  if !fmt_is("1.0.0-0", "1.0.0-0") { ok = false; }
  return assert(ok, "format: round-trips canonical strings");
}

fn t10() -> TestResult {
  let m = SemVer{ major: 4; minor: 5; patch: 6; pre: "rc.1"; build: "" };
  let n = SemVer{ major: 0; minor: 9; patch: 12; pre: ""; build: "b.7" };
  var ok = streq(semver_format(&m), "4.5.6-rc.1");
  if !streq(semver_format(&n), "0.9.12+b.7") { ok = false; }
  return assert(ok, "format: prints fields in canonical order");
}

fn t11() -> TestResult {
  var ok = cmp_of("1.2.3", "1.2.3") == 0;
  if cmp_of("1.2.3", "1.2.4") != -1 { ok = false; }
  if cmp_of("1.2.4", "1.2.3") != 1 { ok = false; }
  if cmp_of("1.3.0", "1.2.9") != 1 { ok = false; }
  if cmp_of("2.0.0", "1.9.9") != 1 { ok = false; }
  if cmp_of("0.0.0", "0.0.1") != -1 { ok = false; }
  return assert(ok, "compare: numeric triple ordering");
}

fn t12() -> TestResult {
  var ok = cmp_of("1.0.0+a", "1.0.0") == 0;
  if cmp_of("1.0.0+a", "1.0.0+b") != 0 { ok = false; }
  if cmp_of("1.0.0+b", "1.0.0-alpha") != 1 { ok = false; }
  if cmp_of("1.0.0-alpha+9", "1.0.0-alpha.1+1") != -1 { ok = false; }
  return assert(ok, "compare: build metadata is ignored");
}

fn t13() -> TestResult {
  var ok = cmp_of("1.0.0-alpha", "1.0.0") == -1;
  if cmp_of("1.0.0", "1.0.0-alpha") != 1 { ok = false; }
  if cmp_of("1.0.0-beta.11", "1.0.0") != -1 { ok = false; }
  if cmp_of("1.0.0-0", "1.0.0") != -1 { ok = false; }
  return assert(ok, "compare: release outranks its pre-releases");
}

fn t14() -> TestResult {
  var ok = cmp_of("1.0.0-alpha.1", "1.0.0-alpha.2") == -1;
  if cmp_of("1.0.0-alpha.1", "1.0.0-alpha.beta") != -1 { ok = false; }
  if cmp_of("1.0.0-beta", "1.0.0-beta.2") != -1 { ok = false; }
  if cmp_of("1.0.0-beta.11", "1.0.0-beta.2") != 1 { ok = false; }
  return assert(ok, "compare: identifiers compare left to right");
}

fn t15() -> TestResult {
  var ok = cmp_of("1.0.0-2", "1.0.0-10") == -1;
  if cmp_of("1.0.0-10", "1.0.0-2") != 1 { ok = false; }
  if cmp_of("1.0.0-1.2.3", "1.0.0-1.2.4") != -1 { ok = false; }
  if cmp_of("1.0.0-0", "1.0.0-1") != -1 { ok = false; }
  return assert(ok, "compare: numeric identifiers compare numerically");
}

fn t16() -> TestResult {
  var ok = cmp_of("1.0.0-1", "1.0.0-alpha") == -1;
  if cmp_of("1.0.0-999", "1.0.0-a") != -1 { ok = false; }
  if cmp_of("1.0.0-alpha", "1.0.0-1") != 1 { ok = false; }
  if cmp_of("1.0.0-1.2", "1.0.0-a.b") != -1 { ok = false; }
  return assert(ok, "compare: numeric identifiers sort before alphanumeric");
}

fn t17() -> TestResult {
  var ok = cmp_of("1.0.0-alpha", "1.0.0-alpha.1") == -1;
  if cmp_of("1.0.0-alpha.1", "1.0.0-alpha") != 1 { ok = false; }
  if cmp_of("1.0.0-alpha", "1.0.0-alpha.0") != -1 { ok = false; }
  if cmp_of("1.0.0-alpha.1", "1.0.0-alpha.1") != 0 { ok = false; }
  return assert(ok, "compare: a shorter pre-release list sorts first");
}

fn t18() -> TestResult {
  var ok = is_pre("1.0.0-alpha", true);
  if !is_pre("1.0.0-0", true) { ok = false; }
  if !is_pre("1.0.0", false) { ok = false; }
  if !is_pre("1.0.0+build", false) { ok = false; }
  if !is_pre("1.0.0-rc.1+build", true) { ok = false; }
  return assert(ok, "is_prerelease: true only with a pre-release part");
}

fn t19() -> TestResult {
  var ok = sat_is("1.2.3", "*", true);
  if !sat_is("0.0.1", "*", true) { ok = false; }
  if !sat_is("1.0.0-alpha", "*", true) { ok = false; }
  if !sat_is("9.9.9+build", "*", true) { ok = false; }
  return assert(ok, "range: * matches everything");
}

fn t20() -> TestResult {
  var ok = sat_is("1.2.3", "1.2.3", true);
  if !sat_is("1.2.4", "1.2.3", false) { ok = false; }
  if !sat_is("1.2.3", "=1.2.3", true) { ok = false; }
  if !sat_is("1.2.4", "=1.2.3", false) { ok = false; }
  if !sat_is("1.2.3+build", "1.2.3", true) { ok = false; }
  if !sat_is("1.2.3-alpha", "1.2.3", false) { ok = false; }
  return assert(ok, "range: exact version and = operator");
}

fn t21() -> TestResult {
  var ok = sat_is("1.2.4", ">1.2.3", true);
  if !sat_is("1.2.3", ">1.2.3", false) { ok = false; }
  if !sat_is("1.2.3", ">=1.2.3", true) { ok = false; }
  if !sat_is("1.2.2", ">=1.2.3", false) { ok = false; }
  if !sat_is("2.0.0", ">1.2.3", true) { ok = false; }
  return assert(ok, "range: > and >=");
}

fn t22() -> TestResult {
  var ok = sat_is("1.2.2", "<1.2.3", true);
  if !sat_is("1.2.3", "<1.2.3", false) { ok = false; }
  if !sat_is("1.2.3", "<=1.2.3", true) { ok = false; }
  if !sat_is("1.2.4", "<=1.2.3", false) { ok = false; }
  if !sat_is("0.9.9", "<1.2.3", true) { ok = false; }
  return assert(ok, "range: < and <=");
}

fn t23() -> TestResult {
  var ok = sat_is("1.2.3", "^1.2.3", true);
  if !sat_is("1.9.9", "^1.2.3", true) { ok = false; }
  if !sat_is("1.2.2", "^1.2.3", false) { ok = false; }
  if !sat_is("2.0.0", "^1.2.3", false) { ok = false; }
  if !sat_is("1.2.3+build", "^1.2.3", true) { ok = false; }
  return assert(ok, "range: caret stays inside the major line");
}

fn t24() -> TestResult {
  var ok = sat_is("0.2.3", "^0.2.3", true);
  if !sat_is("0.2.9", "^0.2.3", true) { ok = false; }
  if !sat_is("0.3.0", "^0.2.3", false) { ok = false; }
  if !sat_is("0.0.3", "^0.0.3", true) { ok = false; }
  if !sat_is("0.0.4", "^0.0.3", false) { ok = false; }
  if !sat_is("0.0.9", "^0.0", true) { ok = false; }
  if !sat_is("0.1.0", "^0.0", false) { ok = false; }
  if !sat_is("0.9.9", "^0", true) { ok = false; }
  if !sat_is("1.0.0", "^0", false) { ok = false; }
  return assert(ok, "range: caret zero-major bounds");
}

fn t25() -> TestResult {
  var ok = sat_is("1.2.3", "~1.2.3", true);
  if !sat_is("1.2.9", "~1.2.3", true) { ok = false; }
  if !sat_is("1.3.0", "~1.2.3", false) { ok = false; }
  if !sat_is("1.2.0", "~1.2", true) { ok = false; }
  if !sat_is("1.2.9", "~1.2", true) { ok = false; }
  if !sat_is("1.3.0", "~1.2", false) { ok = false; }
  if !sat_is("1.9.9", "~1", true) { ok = false; }
  if !sat_is("2.0.0", "~1", false) { ok = false; }
  if !sat_is("0.2.5", "~0.2.3", true) { ok = false; }
  if !sat_is("0.3.0", "~0.2.3", false) { ok = false; }
  return assert(ok, "range: tilde full and partial versions");
}

fn t26() -> TestResult {
  var ok = sat_is("1.2.1", ">1.2", true);
  if !sat_is("1.2.0", ">1.2", false) { ok = false; }
  if !sat_is("1.0.0", ">=1", true) { ok = false; }
  if !sat_is("0.9.9", ">=1", false) { ok = false; }
  if !sat_is("1.1.9", "<1.2", true) { ok = false; }
  if !sat_is("1.2.0", "<1.2", false) { ok = false; }
  if !sat_is("1.2.0", "=1.2", true) { ok = false; }
  if !sat_is("1.2.1", "=1.2", false) { ok = false; }
  if !sat_is("1.0.0", "1", true) { ok = false; }
  if !sat_is("1.0.1", "1", false) { ok = false; }
  return assert(ok, "range: comparison operands zero-pad partials");
}

fn t27() -> TestResult {
  var ok = sat_is("1.0.0-alpha", ">=1.0.0-alpha", true);
  if !sat_is("1.0.0", ">=1.0.0-alpha", true) { ok = false; }
  if !sat_is("0.9.9", ">=1.0.0-alpha", false) { ok = false; }
  if !sat_is("1.2.3-beta.1", "^1.2.3-beta.1", true) { ok = false; }
  if !sat_is("1.2.3-beta.2", "^1.2.3-beta.1", true) { ok = false; }
  if !sat_is("1.2.3", "^1.2.3-beta.1", true) { ok = false; }
  if !sat_is("1.2.2", "^1.2.3-beta.1", false) { ok = false; }
  if !sat_is("1.3.0", "^1.2.3-beta.1", true) { ok = false; }
  if !sat_is("2.0.0", "^1.2.3-beta.1", false) { ok = false; }
  if !sat_is("1.2.3-beta.1", "~1.2.3-beta.1", true) { ok = false; }
  if !sat_is("1.2.9", "~1.2.3-beta.1", true) { ok = false; }
  if !sat_is("1.3.0", "~1.2.3-beta.1", false) { ok = false; }
  return assert(ok, "range: pre-release bounds compare by semver order");
}

fn t28() -> TestResult {
  var ok = sat_err_is("1.2.3", "", "semver: empty range");
  if !sat_err_is("1.2.3", ">=1 <2", "semver: malformed range: >=1 <2") { ok = false; }
  if !sat_err_is("1.2.3", "junk", "semver: malformed range: junk") { ok = false; }
  if !sat_err_is("1.2.3", "**", "semver: malformed range: **") { ok = false; }
  if !sat_err_is("1.2.3", "^", "semver: malformed range: ^") { ok = false; }
  if !sat_err_is("1.2.3", "~", "semver: malformed range: ~") { ok = false; }
  if !sat_err_is("1.2.3", ">= 1.2.3", "semver: malformed range: >= 1.2.3") { ok = false; }
  if !sat_err_is("1.2.3", "1.2.3 ", "semver: malformed range: 1.2.3 ") { ok = false; }
  if !sat_err_is("1.2.3", "1.2.3.4", "semver: malformed range: 1.2.3.4") { ok = false; }
  if !sat_err_is("1.2.3", "-1.2.3", "semver: malformed range: -1.2.3") { ok = false; }
  return assert(ok, "range errors: empty, unknown operators, whitespace lists");
}

fn t29() -> TestResult {
  let empty = Vec[Str].new();
  var ok = any_is("1.5.0", empty, false);
  if !any2_is("1.5.0", "^1.0.0", "~2.1.0", true) { ok = false; }
  if !any2_is("2.1.9", "^1.0.0", "~2.1.0", true) { ok = false; }
  if !any2_is("3.0.0", "^1.0.0", "~2.1.0", false) { ok = false; }
  if !any2_is("9.5.0", "^0.0.1", "~9", true) { ok = false; }
  if !any2_is("1.0.0-alpha", "*", "^0.0.1", true) { ok = false; }
  return assert(ok, "satisfies_any: any range satisfies, empty is false");
}

fn t30() -> TestResult {
  var ok = any_err_is("1.5.0", two_ranges("*", ">>1.2.3"), "semver: malformed range: >>1.2.3");
  if !any_err_is("1.5.0", two_ranges(">=1 <2", "*"), "semver: malformed range: >=1 <2") { ok = false; }
  return assert(ok, "satisfies_any: malformed element is an error");
}

fn t31() -> TestResult {
  let max = "9223372036854775807.0.0";
  var ok = nums_are(max, 9223372036854775807, 0, 0);
  if cmp_of(max, "9223372036854775806.0.0") != 1 { ok = false; }
  if cmp_of("9223372036854775806.0.0", max) != -1 { ok = false; }
  if !err_is("9223372036854775808.0.0", "semver: number too large: 9223372036854775808.0.0") { ok = false; }
  if !err_is("99999999999999999999.0.0", "semver: number too large: 99999999999999999999.0.0") { ok = false; }
  if !fmt_is(max, max) { ok = false; }
  return assert(ok, "large numbers: 64-bit components parse, compare and format");
}

fn t32() -> TestResult {
  var ok = cmp_of("1.0.0-99999999999999999999999999999", "1.0.0-100000000000000000000000000000") == -1;
  if cmp_of("1.0.0-100000000000000000000000000000", "1.0.0-100000000000000000000000000000") != 0 { ok = false; }
  if cmp_of("1.0.0-2", "1.0.0-99999999999999999999") != -1 { ok = false; }
  if cmp_of("1.0.0-99999999999999999999", "1.0.0-abc") != -1 { ok = false; }
  return assert(ok, "large numbers: huge numeric pre-release identifiers");
}

fn main() -> Int {
  io.println("=== xiom.semver conformance tests ===");
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
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.semver: all tests passed");
  } else {
    io.println("xiom.semver: tests failed");
  }
  return failed;
}
