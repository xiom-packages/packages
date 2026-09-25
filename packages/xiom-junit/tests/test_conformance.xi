// XIOM -- xiom.junit conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: parsing (wrapper and bare roots, suites,
// testcases, outcome elements, attribute quotes and entities, comments/PIs,
// whitespace), all accessors, the error catalog, the canonical emitter and
// parse -> emit -> parse round-trips. All Str equality goes through
// str_compare (BUG 17: `==` on Str values read from Vec[Str] elements lowers
// to a pointer comparison).

module junit_tests
use xiom.io; use xiom.test;
use xiom.string.compare;
use xiom.junit;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Expected error text; false when the parse unexpectedly succeeded.
fn err_is(r_ok: Bool, err: Str, want: Str) -> Bool {
  if r_ok { return false; }
  return streq(err, want);
}

// True when both reports expose the same public model (suite and case fields,
// declared totals and raw times).
fn same_model(a: &JUnitDoc, b: &JUnitDoc) -> Bool {
  if junit_has_wrapper(a) != junit_has_wrapper(b) { return false; }
  if junit_suite_count(a) != junit_suite_count(b) { return false; }
  if junit_case_count(a) != junit_case_count(b) { return false; }
  if junit_total_tests(a) != junit_total_tests(b) { return false; }
  if junit_total_failures(a) != junit_total_failures(b) { return false; }
  if junit_total_errors(a) != junit_total_errors(b) { return false; }
  if junit_total_skipped(a) != junit_total_skipped(b) { return false; }
  if !streq(junit_total_time(a), junit_total_time(b)) { return false; }
  var s = 0;
  while s < junit_suite_count(a) {
    if !streq(junit_suite_name(a, s), junit_suite_name(b, s)) { return false; }
    if junit_suite_tests(a, s) != junit_suite_tests(b, s) { return false; }
    if junit_suite_failures(a, s) != junit_suite_failures(b, s) { return false; }
    if junit_suite_errors(a, s) != junit_suite_errors(b, s) { return false; }
    if junit_suite_skipped(a, s) != junit_suite_skipped(b, s) { return false; }
    if !streq(junit_suite_time(a, s), junit_suite_time(b, s)) { return false; }
    if junit_suite_case_count(a, s) != junit_suite_case_count(b, s) { return false; }
    s = s + 1;
  }
  var i = 0;
  while i < junit_case_count(a) {
    if junit_case_suite(a, i) != junit_case_suite(b, i) { return false; }
    if !streq(junit_case_name(a, i), junit_case_name(b, i)) { return false; }
    if !streq(junit_case_classname(a, i), junit_case_classname(b, i)) { return false; }
    if !streq(junit_case_time(a, i), junit_case_time(b, i)) { return false; }
    if junit_case_outcome(a, i) != junit_case_outcome(b, i) { return false; }
    if !streq(junit_case_message(a, i), junit_case_message(b, i)) { return false; }
    if !streq(junit_case_type(a, i), junit_case_type(b, i)) { return false; }
    if !streq(junit_case_text(a, i), junit_case_text(b, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let src = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites tests=\"3\" failures=\"1\" errors=\"1\" skipped=\"0\" time=\"0.75\">\n  <testsuite name=\"alpha\" tests=\"2\" failures=\"1\" errors=\"0\" skipped=\"0\" time=\"0.1\">\n    <testcase name=\"a1\" classname=\"pkg.A\" time=\"0.05\"/>\n    <testcase name=\"a2\" classname=\"pkg.A\" time=\"0.03\"><failure message=\"boom\" type=\"ValueError\">assert failed</failure></testcase>\n  </testsuite>\n  <testsuite name=\"beta\" tests=\"1\" failures=\"0\" errors=\"1\" skipped=\"0\" time=\"0.2\">\n    <testcase name=\"b1\" classname=\"pkg.B\"><error message=\"network\" type=\"Timeout\">dial tcp</error></testcase>\n  </testsuite>\n</testsuites>";
  let r = junit_parse(src);
  if !r.is_ok { return assert(false, "full report parses"); }
  let d = r.value;
  var ok = junit_has_wrapper(&d);
  if junit_suite_count(&d) != 2 { ok = false; }
  if junit_case_count(&d) != 3 { ok = false; }
  if junit_total_tests(&d) != 3 { ok = false; }
  if junit_total_failures(&d) != 1 { ok = false; }
  if junit_total_errors(&d) != 1 { ok = false; }
  if junit_total_skipped(&d) != 0 { ok = false; }
  if !streq(junit_total_time(&d), "0.75") { ok = false; }
  if !streq(junit_suite_name(&d, 0), "alpha") { ok = false; }
  if !streq(junit_suite_name(&d, 1), "beta") { ok = false; }
  if junit_suite_tests(&d, 0) != 2 { ok = false; }
  if junit_suite_failures(&d, 0) != 1 { ok = false; }
  if junit_suite_errors(&d, 0) != 0 { ok = false; }
  if junit_suite_skipped(&d, 1) != 0 { ok = false; }
  if !streq(junit_suite_time(&d, 1), "0.2") { ok = false; }
  if junit_suite_case_count(&d, 0) != 2 { ok = false; }
  if junit_suite_case_count(&d, 1) != 1 { ok = false; }
  if !streq(junit_case_name(&d, 0), "a1") { ok = false; }
  if !streq(junit_case_classname(&d, 0), "pkg.A") { ok = false; }
  if !streq(junit_case_time(&d, 0), "0.05") { ok = false; }
  if junit_case_outcome(&d, 0) != JUNIT_PASSED { ok = false; }
  if junit_case_suite(&d, 0) != 0 { ok = false; }
  if junit_case_outcome(&d, 1) != JUNIT_FAILURE { ok = false; }
  if !streq(junit_case_message(&d, 1), "boom") { ok = false; }
  if !streq(junit_case_type(&d, 1), "ValueError") { ok = false; }
  if !streq(junit_case_text(&d, 1), "assert failed") { ok = false; }
  if junit_case_outcome(&d, 2) != JUNIT_ERROR { ok = false; }
  if junit_case_suite(&d, 2) != 1 { ok = false; }
  if !streq(junit_case_message(&d, 2), "network") { ok = false; }
  if !streq(junit_case_type(&d, 2), "Timeout") { ok = false; }
  if !streq(junit_case_text(&d, 2), "dial tcp") { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_PASSED) != 1 { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_FAILURE) != 1 { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_ERROR) != 1 { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_SKIPPED) != 0 { ok = false; }
  return assert(ok, "full report: suites, cases, totals and outcomes");
}

fn t2() -> TestResult {
  let r = junit_parse("<testsuite name=\"solo\"><testcase name=\"t1\" classname=\"C\"/></testsuite>");
  if !r.is_ok { return assert(false, "bare testsuite root parses"); }
  let d = r.value;
  var ok = !junit_has_wrapper(&d);
  if junit_suite_count(&d) != 1 { ok = false; }
  if junit_case_count(&d) != 1 { ok = false; }
  if junit_total_tests(&d) != 0 { ok = false; }
  if junit_total_failures(&d) != 0 { ok = false; }
  if !streq(junit_total_time(&d), "") { ok = false; }
  if !streq(junit_suite_name(&d, 0), "solo") { ok = false; }
  if junit_suite_tests(&d, 0) != 0 { ok = false; }
  if !streq(junit_suite_time(&d, 0), "") { ok = false; }
  if !streq(junit_case_name(&d, 0), "t1") { ok = false; }
  if !streq(junit_case_classname(&d, 0), "C") { ok = false; }
  if !streq(junit_case_time(&d, 0), "") { ok = false; }
  if junit_case_outcome(&d, 0) != JUNIT_PASSED { ok = false; }
  if !streq(junit_case_text(&d, 0), "") { ok = false; }
  return assert(ok, "bare root: wrapper totals default to 0/\"\" and case defaults hold");
}

fn t3() -> TestResult {
  let src = "<testsuite name=\"s\"><testcase name=\"p\"/><testcase name=\"f\"><failure/></testcase><testcase name=\"e\"><error message=\"m\"/></testcase><testcase name=\"k\"><skipped message=\"why\" type=\"manual\"/></testcase></testsuite>";
  let r = junit_parse(src);
  if !r.is_ok { return assert(false, "all four outcome forms parse"); }
  let d = r.value;
  var ok = junit_case_count(&d) == 4;
  if junit_case_outcome(&d, 0) != JUNIT_PASSED { ok = false; }
  if junit_case_outcome(&d, 1) != JUNIT_FAILURE { ok = false; }
  if !streq(junit_case_text(&d, 1), "") { ok = false; }
  if junit_case_outcome(&d, 2) != JUNIT_ERROR { ok = false; }
  if !streq(junit_case_message(&d, 2), "m") { ok = false; }
  if !streq(junit_case_type(&d, 2), "") { ok = false; }
  if junit_case_outcome(&d, 3) != JUNIT_SKIPPED { ok = false; }
  if !streq(junit_case_message(&d, 3), "why") { ok = false; }
  if !streq(junit_case_type(&d, 3), "manual") { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_PASSED) != 1 { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_FAILURE) != 1 { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_ERROR) != 1 { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_SKIPPED) != 1 { ok = false; }
  return assert(ok, "self-closing outcome elements set the outcome and empty fields");
}

fn t4() -> TestResult {
  let src = "<testsuite name='a&amp;b' tests='2'><testcase name=\"c&lt;d\" classname=\"&#65;&#x42;&quot;\"/><testcase name='x\"y' classname='&apos;'/></testsuite>";
  let r = junit_parse(src);
  if !r.is_ok { return assert(false, "entity decoding in attributes"); }
  let d = r.value;
  var ok = streq(junit_suite_name(&d, 0), "a&b");
  if junit_suite_tests(&d, 0) != 2 { ok = false; }
  if !streq(junit_case_name(&d, 0), "c<d") { ok = false; }
  if !streq(junit_case_classname(&d, 0), "AB\"") { ok = false; }
  if !streq(junit_case_name(&d, 1), "x\"y") { ok = false; }
  if !streq(junit_case_classname(&d, 1), "'") { ok = false; }
  let u = junit_parse("<testsuite name=\"caf&#233;\"><testcase name=\"&#x4E2D;\"/></testsuite>");
  if !u.is_ok { ok = false; }
  if u.is_ok {
    let ud = u.value;
    if !streq(junit_suite_name(&ud, 0), "café") { ok = false; }
    if !streq(junit_case_name(&ud, 0), "中") { ok = false; }
    if !streq(junit_emit(&ud), "<testsuite name=\"café\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\">\n  <testcase name=\"中\"/>\n</testsuite>\n") { ok = false; }
  }
  return assert(ok, "attributes: both quote styles and named/numeric entities decode");
}

fn t5() -> TestResult {
  let src = "<testsuite name=\"s\"><testcase name=\"c\"><failure message=\"x&amp;y\">a &amp; b &lt; c</failure></testcase></testsuite>";
  let r = junit_parse(src);
  if !r.is_ok { return assert(false, "outcome text is opaque"); }
  let d = r.value;
  var ok = streq(junit_case_message(&d, 0), "x&y");
  if !streq(junit_case_text(&d, 0), "a &amp; b &lt; c") { ok = false; }
  let ml = junit_parse("<testsuite name=\"s\"><testcase name=\"c\"><failure>line1\nline2</failure></testcase></testsuite>");
  if !ml.is_ok { ok = false; }
  if ml.is_ok {
    let md = ml.value;
    if !streq(junit_case_text(&md, 0), "line1\nline2") { ok = false; }
  }
  let lt = junit_parse("<testsuite name=\"s\"><testcase name=\"c\"><failure>a < b</failure></testcase></testsuite>");
  if !lt.is_ok { ok = false; }
  if lt.is_ok {
    let ld = lt.value;
    if !streq(junit_case_text(&ld, 0), "a < b") { ok = false; }
  }
  return assert(ok, "outcome text passes through verbatim (no entity decoding)");
}

fn t6() -> TestResult {
  let src = "<testsuites>\n  <!-- a comment -->\n  <?generated by tests?>\n  <testsuite name=\"s\">\n    <!-- inner -->\n    <testcase name=\"t\"/>\n  </testsuite>\n</testsuites>\n";
  let r = junit_parse(src);
  if !r.is_ok { return assert(false, "whitespace, comments and PIs are skipped"); }
  let d = r.value;
  var ok = junit_suite_count(&d) == 1;
  if junit_case_count(&d) != 1 { ok = false; }
  if !streq(junit_suite_name(&d, 0), "s") { ok = false; }
  if !streq(junit_case_name(&d, 0), "t") { ok = false; }
  return assert(ok, "pretty-printed reports and comments/PIs parse");
}

fn t7() -> TestResult {
  let a = junit_parse("<testsuite name=\"a\"></testcase>");
  var ok = err_is(a.is_ok, a.error, "junit: mismatched closing tag");
  let b = junit_parse("<testsuite name=\"a\"><testcase name=\"t\"></testsuite></testcase>");
  if !err_is(b.is_ok, b.error, "junit: mismatched closing tag") { ok = false; }
  let c = junit_parse("<testsuites></testsuite>");
  if !err_is(c.is_ok, c.error, "junit: mismatched closing tag") { ok = false; }
  let e = junit_parse("</testsuite>");
  if !err_is(e.is_ok, e.error, "junit: mismatched closing tag") { ok = false; }
  return assert(ok, "mismatched and unexpected closing tags are Err");
}

fn t8() -> TestResult {
  let a = junit_parse("<testsuites><widget/></testsuites>");
  var ok = err_is(a.is_ok, a.error, "junit: unknown tag 'widget'");
  let b = junit_parse("<testsuites><testcase name=\"t\"/></testsuites>");
  if !err_is(b.is_ok, b.error, "junit: misplaced tag 'testcase'") { ok = false; }
  let c = junit_parse("<testsuite name=\"a\"><failure/></testsuite>");
  if !err_is(c.is_ok, c.error, "junit: misplaced tag 'failure'") { ok = false; }
  let e = junit_parse("<testsuite name=\"a\"><testsuite name=\"b\"/></testsuite>");
  if !err_is(e.is_ok, e.error, "junit: misplaced tag 'testsuite'") { ok = false; }
  let f = junit_parse("<testsuite name=\"a\"/><testsuite name=\"b\"/>");
  if !err_is(f.is_ok, f.error, "junit: misplaced tag 'testsuite'") { ok = false; }
  return assert(ok, "unknown and misplaced tags are Err");
}

fn t9() -> TestResult {
  let a = junit_parse("<testsuite name=\"a\"><testcase name=\"b\"><testcase name=\"c\"/></testcase></testsuite>");
  return assert(err_is(a.is_ok, a.error, "junit: nested testcase"), "a testcase inside a testcase is Err");
}

fn t10() -> TestResult {
  let a = junit_parse("<testsuite/>");
  var ok = err_is(a.is_ok, a.error, "junit: missing name");
  let b = junit_parse("<testsuite name=\"\"/>");
  if !err_is(b.is_ok, b.error, "junit: missing name") { ok = false; }
  let c = junit_parse("<testsuite name=\"s\"><testcase classname=\"C\"/></testsuite>");
  if !err_is(c.is_ok, c.error, "junit: missing name") { ok = false; }
  return assert(ok, "missing (or empty) suite/testcase name is Err");
}

fn t11() -> TestResult {
  let a = junit_parse("<testsuite name=s/>");
  var ok = err_is(a.is_ok, a.error, "junit: unquoted attribute");
  let b = junit_parse("<testsuite name/>");
  if !err_is(b.is_ok, b.error, "junit: malformed attribute") { ok = false; }
  let c = junit_parse("<testsuite name=\"a\" tests/>");
  if !err_is(c.is_ok, c.error, "junit: malformed attribute") { ok = false; }
  let e = junit_parse("<testsuite name=\"a\" x=1/>");
  if !err_is(e.is_ok, e.error, "junit: unquoted attribute") { ok = false; }
  return assert(ok, "unquoted values and malformed attributes are Err");
}

fn t12() -> TestResult {
  let a = junit_parse("<testsuite name=\"a&amp\"/>");
  var ok = err_is(a.is_ok, a.error, "junit: bad entity");
  let b = junit_parse("<testsuite name=\"a&bogus;\"/>");
  if !err_is(b.is_ok, b.error, "junit: bad entity") { ok = false; }
  let c = junit_parse("<testsuite name=\"a&#xZZ;\"/>");
  if !err_is(c.is_ok, c.error, "junit: bad entity") { ok = false; }
  let e = junit_parse("<testsuite name=\"a&#0;\"/>");
  if !err_is(e.is_ok, e.error, "junit: bad entity") { ok = false; }
  let f = junit_parse("<testsuite name=\"a&;\"/>");
  if !err_is(f.is_ok, f.error, "junit: bad entity") { ok = false; }
  return assert(ok, "unknown, malformed and zero-valued entities are Err");
}

fn t13() -> TestResult {
  let a = junit_parse("junk");
  var ok = err_is(a.is_ok, a.error, "junit: text where elements expected");
  let b = junit_parse("<testsuite name=\"a\">junk</testsuite>");
  if !err_is(b.is_ok, b.error, "junit: text where elements expected") { ok = false; }
  let c = junit_parse("<testsuites>junk</testsuites>");
  if !err_is(c.is_ok, c.error, "junit: text where elements expected") { ok = false; }
  let e = junit_parse("<testsuite name=\"a\"><testcase name=\"t\">junk</testcase></testsuite>");
  if !err_is(e.is_ok, e.error, "junit: text where elements expected") { ok = false; }
  let f = junit_parse("<testsuite name=\"a\"/>junk");
  if !err_is(f.is_ok, f.error, "junit: text where elements expected") { ok = false; }
  return assert(ok, "non-whitespace text where elements are expected is Err");
}

fn t14() -> TestResult {
  let a = junit_parse("");
  var ok = err_is(a.is_ok, a.error, "junit: premature EOF");
  let b = junit_parse("<testsuite name=\"a\"");
  if !err_is(b.is_ok, b.error, "junit: premature EOF") { ok = false; }
  let c = junit_parse("<testsuite name=\"a\" tests=\"1\"");
  if !err_is(c.is_ok, c.error, "junit: premature EOF") { ok = false; }
  let e = junit_parse("<testsuite name=\"a\"><testcase name=\"t\"><failure>oops");
  if !err_is(e.is_ok, e.error, "junit: premature EOF") { ok = false; }
  let f = junit_parse("<testsuite name=\"a\"><testcase name=\"t\"/></testsuite");
  if !err_is(f.is_ok, f.error, "junit: premature EOF") { ok = false; }
  return assert(ok, "EOF inside markup, open elements or outcome text is Err");
}

fn t15() -> TestResult {
  let a = junit_parse("<testsuite name=\"a\" tests=\"x\"/>");
  var ok = err_is(a.is_ok, a.error, "junit: invalid integer attribute");
  let b = junit_parse("<testsuite name=\"a\" tests=\"-1\"/>");
  if !err_is(b.is_ok, b.error, "junit: invalid integer attribute") { ok = false; }
  let c = junit_parse("<testsuite name=\"a\" tests=\"1.5\"/>");
  if !err_is(c.is_ok, c.error, "junit: invalid integer attribute") { ok = false; }
  let e = junit_parse("<testsuites tests=\"x\"><testsuite name=\"a\"/></testsuites>");
  if !err_is(e.is_ok, e.error, "junit: invalid integer attribute") { ok = false; }
  return assert(ok, "non-decimal count attributes are Err");
}

fn t16() -> TestResult {
  let a = junit_parse("<!DOCTYPE testsuites><testsuite name=\"a\"/>");
  var ok = err_is(a.is_ok, a.error, "junit: unsupported markup");
  let b = junit_parse("<testsuite name=\"a\"><![CDATA[x]]></testsuite>");
  if !err_is(b.is_ok, b.error, "junit: unsupported markup") { ok = false; }
  return assert(ok, "DOCTYPE and CDATA markup is rejected");
}

fn t17() -> TestResult {
  let a = junit_parse("<testsuite name=\"a\"><testcase name=\"t\"><failure/><error/></testcase></testsuite>");
  var ok = err_is(a.is_ok, a.error, "junit: misplaced tag 'error'");
  let b = junit_parse("<testsuite name=\"a\"><testcase name=\"t\"><skipped/><failure/></testcase></testsuite>");
  if !err_is(b.is_ok, b.error, "junit: misplaced tag 'failure'") { ok = false; }
  return assert(ok, "a second outcome element on a testcase is Err");
}

fn t18() -> TestResult {
  let src = "<testsuite name=\"s\" tests=\"1\" failures=\"1\" errors=\"0\" skipped=\"0\"><testcase name=\"c\" classname=\"C\" time=\"0.5\"><failure message=\"m &amp; n\" type=\"E\">assert failed: a &gt; b</failure></testcase></testsuite>";
  let r = junit_parse(src);
  if !r.is_ok { return assert(false, "canonical emitter input parses"); }
  let d = r.value;
  let want = "<testsuite name=\"s\" tests=\"1\" failures=\"1\" errors=\"0\" skipped=\"0\">\n  <testcase name=\"c\" classname=\"C\" time=\"0.5\">\n    <failure message=\"m &amp; n\" type=\"E\">assert failed: a &gt; b</failure>\n  </testcase>\n</testsuite>\n";
  let got = junit_emit(&d);
  return assert(streq(got, want), "canonical emit: deterministic order and layout");
}

fn t19() -> TestResult {
  let src = "<testsuites tests=\"4\" failures=\"1\" errors=\"1\" skipped=\"1\" time=\"1.25\">\n  <testsuite name=\"alpha\" tests=\"2\" failures=\"1\" errors=\"0\" skipped=\"0\" time=\"0.1\">\n    <testcase name=\"a1\" classname=\"pkg.A\" time=\"0.05\"/>\n    <testcase name=\"a2\" classname=\"pkg.A\" time=\"0.03\"><failure message=\"m &amp; n\" type=\"VE\">boom &amp; <raw></failure></testcase>\n  </testsuite>\n  <testsuite name=\"beta\" tests=\"2\" failures=\"0\" errors=\"1\" skipped=\"1\" time=\"0.2\">\n    <testcase name=\"b1\" classname=\"pkg.B\"><error message=\"net\" type=\"Timeout\">dial</error></testcase>\n    <testcase name=\"b2\" classname=\"pkg.B\"><skipped/></testcase>\n  </testsuite>\n</testsuites>";
  let r = junit_parse(src);
  if !r.is_ok { return assert(false, "round-trip input parses"); }
  let d = r.value;
  let out1 = junit_emit(&d);
  let r2 = junit_parse(out1);
  if !r2.is_ok { return assert(false, "emitted report reparses"); }
  let d2 = r2.value;
  var ok = same_model(&d, &d2);
  let out2 = junit_emit(&d2);
  if !streq(out1, out2) { ok = false; }
  return assert(ok, "round-trip: parse -> emit -> parse preserves the model and bytes");
}

fn t20() -> TestResult {
  let r = junit_parse("<testsuites/>");
  if !r.is_ok { return assert(false, "empty wrapper parses"); }
  let d = r.value;
  var ok = junit_has_wrapper(&d);
  if junit_suite_count(&d) != 0 { ok = false; }
  if junit_case_count(&d) != 0 { ok = false; }
  let want = "<testsuites tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\">\n</testsuites>\n";
  if !streq(junit_emit(&d), want) { ok = false; }
  return assert(ok, "an empty <testsuites/> wrapper emits canonically");
}

fn t21() -> TestResult {
  let a = junit_parse("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- generated -->\n<testsuite name=\"a\"/>");
  var ok = a.is_ok;
  if a.is_ok {
    let d = a.value;
    if junit_suite_count(&d) != 1 { ok = false; }
    if junit_case_count(&d) != 0 { ok = false; }
  }
  let b = junit_parse("<?pi data?><testsuite name=\"b\"><testcase name=\"t\"/></testsuite>");
  if !b.is_ok { ok = false; }
  if b.is_ok {
    let bd = b.value;
    if junit_case_count(&bd) != 1 { ok = false; }
  }
  return assert(ok, "prolog declaration, comments and PIs are skipped");
}

fn t22() -> TestResult {
  let r = junit_parse("<testsuites/>");
  if !r.is_ok { return assert(false, "empty report for out-of-range accessors"); }
  let d = r.value;
  var ok = streq(junit_suite_name(&d, -1), "");
  if !streq(junit_suite_name(&d, 99), "") { ok = false; }
  if junit_suite_tests(&d, -1) != -1 { ok = false; }
  if junit_suite_case_count(&d, 99) != 0 { ok = false; }
  if !streq(junit_case_name(&d, 99), "") { ok = false; }
  if !streq(junit_case_classname(&d, -1), "") { ok = false; }
  if !streq(junit_case_time(&d, 99), "") { ok = false; }
  if junit_case_outcome(&d, 99) != -1 { ok = false; }
  if junit_case_suite(&d, 99) != -1 { ok = false; }
  if !streq(junit_case_message(&d, 99), "") { ok = false; }
  if !streq(junit_case_type(&d, 99), "") { ok = false; }
  if !streq(junit_case_text(&d, 99), "") { ok = false; }
  if junit_case_count_by_outcome(&d, JUNIT_PASSED) != 0 { ok = false; }
  if junit_case_count_by_outcome(&d, 77) != 0 { ok = false; }
  if !streq(junit_outcome_name(JUNIT_PASSED), "passed") { ok = false; }
  if !streq(junit_outcome_name(JUNIT_FAILURE), "failure") { ok = false; }
  if !streq(junit_outcome_name(JUNIT_ERROR), "error") { ok = false; }
  if !streq(junit_outcome_name(JUNIT_SKIPPED), "skipped") { ok = false; }
  if !streq(junit_outcome_name(9), "") { ok = false; }
  return assert(ok, "out-of-range accessors are safe and outcomes map to names");
}

fn main() -> Int {
  io.println("=== xiom.junit conformance tests ===");
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
    io.println("xiom.junit: all tests passed");
  } else {
    io.println("xiom.junit: tests failed");
  }
  return failed;
}
