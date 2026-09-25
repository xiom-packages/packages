// XIOM -- xiom.sarif conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: top-level/run/result/location parsing, key-order
// independence, string escapes (including \uXXXX), the level default and
// summary counts, all accessors (including out-of-range safety), the
// canonical compact emitter, every error family in the SPEC.md catalog, and
// parse -> emit -> parse round-trips. All Str equality goes through
// str_compare (BUG 17: `==` on Str values read from Vec[Str] elements lowers
// to a pointer comparison) and every Vec element read is bound to a typed
// local.
//
// Harness style mirrors xiom.hello / xiom.junit: one fn tN() -> TestResult
// per check, called directly from main; main prints [PASS]/[FAIL] and
// returns the failure count.

module sarif_tests
use xiom.io; use xiom.test;
use xiom.string.compare;
use xiom.sarif;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Expected error text; false when the parse unexpectedly succeeded.
fn err_is(r_ok: Bool, err: Str, want: Str) -> Bool {
  if r_ok { return false; }
  return streq(err, want);
}

// Parse-result error predicate with a diagnostic name.
fn expect_err(r: Result[SarifDoc, Str], want: Str, name: Str) -> TestResult {
  if r.is_ok {
    return assert(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !streq(got, want) {
    return assert(false, name + " (got: " + got + ")");
  }
  return assert(true, name);
}

// True when both reports expose the same public model (schema, runs, results
// and locations, including range ownership and level codes).
fn same_model(a: &SarifDoc, b: &SarifDoc) -> Bool {
  if !streq(sarif_schema(a), sarif_schema(b)) { return false; }
  if sarif_run_count(a) != sarif_run_count(b) { return false; }
  var r = 0;
  while r < sarif_run_count(a) {
    if !streq(sarif_run_driver_name(a, r), sarif_run_driver_name(b, r)) { return false; }
    if sarif_run_result_count(a, r) != sarif_run_result_count(b, r) { return false; }
    r = r + 1;
  }
  if sarif_result_count(a) != sarif_result_count(b) { return false; }
  var i = 0;
  while i < sarif_result_count(a) {
    if sarif_result_run(a, i) != sarif_result_run(b, i) { return false; }
    if !streq(sarif_result_rule_id(a, i), sarif_result_rule_id(b, i)) { return false; }
    if sarif_result_level(a, i) != sarif_result_level(b, i) { return false; }
    if !streq(sarif_result_message(a, i), sarif_result_message(b, i)) { return false; }
    if sarif_result_location_count(a, i) != sarif_result_location_count(b, i) { return false; }
    i = i + 1;
  }
  if sarif_location_count(a) != sarif_location_count(b) { return false; }
  var k = 0;
  while k < sarif_location_count(a) {
    if sarif_location_result(a, k) != sarif_location_result(b, k) { return false; }
    if !streq(sarif_location_uri(a, k), sarif_location_uri(b, k)) { return false; }
    if sarif_location_line(a, k) != sarif_location_line(b, k) { return false; }
    if sarif_location_column(a, k) != sarif_location_column(b, k) { return false; }
    k = k + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let src = "{\n  \"$schema\": \"https://json.schemastore.org/sarif-2.1.0.json\",\n  \"version\": \"2.1.0\",\n  \"runs\": [\n    {\n      \"tool\": { \"driver\": { \"name\": \"linter\" } },\n      \"results\": [\n        {\n          \"ruleId\": \"X001\",\n          \"level\": \"error\",\n          \"message\": { \"text\": \"unused variable\" },\n          \"locations\": [\n            { \"physicalLocation\": { \"artifactLocation\": { \"uri\": \"src/a.xi\" }, \"region\": { \"startLine\": 3, \"startColumn\": 7 } } }\n          ]\n        },\n        {\n          \"message\": { \"text\": \"note text\" },\n          \"locations\": [ { \"physicalLocation\": { \"artifactLocation\": { \"uri\": \"src/b.xi\" } } } ]\n        }\n      ]\n    },\n    {\n      \"tool\": { \"driver\": { \"name\": \"audit\" } }\n    }\n  ]\n}";
  let r = sarif_parse(src);
  if !r.is_ok { return assert(false, "full report parses"); }
  let d: SarifDoc = r.value;
  var ok = streq(sarif_schema(&d), "https://json.schemastore.org/sarif-2.1.0.json");
  if sarif_run_count(&d) != 2 { ok = false; }
  if !streq(sarif_run_driver_name(&d, 0), "linter") { ok = false; }
  if !streq(sarif_run_driver_name(&d, 1), "audit") { ok = false; }
  if sarif_run_result_count(&d, 0) != 2 { ok = false; }
  if sarif_run_result_count(&d, 1) != 0 { ok = false; }
  if sarif_result_count(&d) != 2 { ok = false; }
  if sarif_result_run(&d, 0) != 0 { ok = false; }
  if sarif_result_run(&d, 1) != 0 { ok = false; }
  if !streq(sarif_result_rule_id(&d, 0), "X001") { ok = false; }
  if !streq(sarif_result_rule_id(&d, 1), "") { ok = false; }
  if sarif_result_level(&d, 0) != SARIF_LEVEL_ERROR { ok = false; }
  if sarif_result_level(&d, 1) != SARIF_LEVEL_WARNING { ok = false; }
  if !streq(sarif_result_message(&d, 0), "unused variable") { ok = false; }
  if !streq(sarif_result_message(&d, 1), "note text") { ok = false; }
  if sarif_result_location_count(&d, 0) != 1 { ok = false; }
  if sarif_result_location_count(&d, 1) != 1 { ok = false; }
  if !streq(sarif_result_uri(&d, 0), "src/a.xi") { ok = false; }
  if sarif_result_line(&d, 0) != 3 { ok = false; }
  if sarif_result_column(&d, 0) != 7 { ok = false; }
  if !streq(sarif_result_uri(&d, 1), "src/b.xi") { ok = false; }
  if sarif_result_line(&d, 1) != 0 { ok = false; }
  if sarif_result_column(&d, 1) != 0 { ok = false; }
  if sarif_location_count(&d) != 2 { ok = false; }
  if sarif_location_result(&d, 0) != 0 { ok = false; }
  if sarif_location_result(&d, 1) != 1 { ok = false; }
  if !streq(sarif_location_uri(&d, 0), "src/a.xi") { ok = false; }
  if sarif_location_line(&d, 0) != 3 { ok = false; }
  if sarif_location_column(&d, 0) != 7 { ok = false; }
  if !streq(sarif_location_uri(&d, 1), "src/b.xi") { ok = false; }
  if sarif_location_line(&d, 1) != 0 { ok = false; }
  if sarif_location_column(&d, 1) != 0 { ok = false; }
  if sarif_level_count(&d, SARIF_LEVEL_ERROR) != 1 { ok = false; }
  if sarif_level_count(&d, SARIF_LEVEL_WARNING) != 1 { ok = false; }
  if sarif_level_count(&d, SARIF_LEVEL_NOTE) != 0 { ok = false; }
  return assert(ok, "full report: schema, runs, results, locations and counts");
}

fn t2() -> TestResult {
  let r = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[]}");
  if !r.is_ok { return assert(false, "empty runs parses"); }
  let d: SarifDoc = r.value;
  var ok = streq(sarif_schema(&d), "");
  if sarif_run_count(&d) != 0 { ok = false; }
  if sarif_result_count(&d) != 0 { ok = false; }
  if sarif_location_count(&d) != 0 { ok = false; }
  if !streq(sarif_emit(&d), "{\"version\":\"2.1.0\",\"runs\":[]}") { ok = false; }
  if !streq(sarif_version(), "2.1.0") { ok = false; }
  let u = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}}}]}");
  if !u.is_ok { ok = false; }
  if u.is_ok {
    let e: SarifDoc = u.value;
    if sarif_run_count(&e) != 1 { ok = false; }
    if sarif_result_count(&e) != 0 { ok = false; }
    if !streq(sarif_run_driver_name(&e, 0), "d") { ok = false; }
    if !streq(sarif_emit(&e), "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[]}]}") { ok = false; }
  }
  return assert(ok, "minimal reports: empty runs and a result-less run");
}

fn t3() -> TestResult {
  let src = "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}} , \"results\":[{\"message\":{\"text\":\"m\"}},{\"ruleId\":\"\",\"level\":\"warning\",\"message\":{\"text\":\"\"}}]}]}";
  let r = sarif_parse(src);
  if !r.is_ok { return assert(false, "defaulted results parse"); }
  let d: SarifDoc = r.value;
  var ok = sarif_result_count(&d) == 2;
  if sarif_result_level(&d, 0) != SARIF_LEVEL_WARNING { ok = false; }
  if !streq(sarif_result_rule_id(&d, 0), "") { ok = false; }
  if !streq(sarif_result_message(&d, 0), "m") { ok = false; }
  if sarif_result_location_count(&d, 0) != 0 { ok = false; }
  if !streq(sarif_result_uri(&d, 0), "") { ok = false; }
  if sarif_result_line(&d, 0) != 0 { ok = false; }
  if sarif_result_column(&d, 0) != 0 { ok = false; }
  if sarif_result_run(&d, 0) != 0 { ok = false; }
  if !streq(sarif_result_rule_id(&d, 1), "") { ok = false; }
  if !streq(sarif_result_message(&d, 1), "") { ok = false; }
  return assert(ok, "result defaults: absent level means warning and empty strings are kept");
}

fn t4() -> TestResult {
  let a_src = "{\"runs\":[{\"results\":[{\"locations\":[{\"physicalLocation\":{\"region\":{\"startColumn\":5,\"startLine\":2},\"artifactLocation\":{\"uri\":\"u.xi\"}}}],\"message\":{\"text\":\"m\"},\"level\":\"note\",\"ruleId\":\"R\"}],\"tool\":{\"driver\":{\"name\":\"d\"}}}],\"version\":\"2.1.0\"}";
  let b_src = "{ \"version\" : \"2.1.0\" , \"runs\" : [ { \"tool\" : { \"driver\" : { \"name\" : \"d\" } } , \"results\" : [ { \"ruleId\" : \"R\" , \"level\" : \"note\" , \"message\" : { \"text\" : \"m\" } , \"locations\" : [ { \"physicalLocation\" : { \"artifactLocation\" : { \"uri\" : \"u.xi\" } , \"region\" : { \"startLine\" : 2 , \"startColumn\" : 5 } } } ] } ] } ] }";
  let a = sarif_parse(a_src);
  let b = sarif_parse(b_src);
  if !a.is_ok { return assert(false, "shuffled-key report parses"); }
  if !b.is_ok { return assert(false, "canonical-key report parses"); }
  let da: SarifDoc = a.value;
  let db: SarifDoc = b.value;
  var ok = same_model(&da, &db);
  if !streq(sarif_result_uri(&da, 0), "u.xi") { ok = false; }
  if sarif_result_line(&da, 0) != 2 { ok = false; }
  if sarif_result_column(&da, 0) != 5 { ok = false; }
  if !streq(sarif_emit(&da), sarif_emit(&db)) { ok = false; }
  return assert(ok, "key order and whitespace do not affect the model or emission");
}

fn t5() -> TestResult {
  let src = "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"a\\\"b\\\\c\\/d\\nx\"}},{\"message\":{\"text\":\"\\u0041\\u007e\"}},{\"message\":{\"text\":\"x\\by\\fz\"}}]}]}";
  let r = sarif_parse(src);
  if !r.is_ok { return assert(false, "escaped strings parse"); }
  let d: SarifDoc = r.value;
  var ok = sarif_result_count(&d) == 3;
  if !streq(sarif_result_message(&d, 0), "a\"b\\c/d\nx") { ok = false; }
  if !streq(sarif_result_message(&d, 1), "A~") { ok = false; }
  if !streq(sarif_emit(&d), "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"level\":\"warning\",\"message\":{\"text\":\"a\\\"b\\\\c/d\\nx\"},\"locations\":[]},{\"level\":\"warning\",\"message\":{\"text\":\"A~\"},\"locations\":[]},{\"level\":\"warning\",\"message\":{\"text\":\"x\\by\\fz\"},\"locations\":[]}]}]}") { ok = false; }
  return assert(ok, "string escapes decode and re-emit canonically");
}

fn t6() -> TestResult {
  let src = "{\n  \"$schema\": \"https://json.schemastore.org/sarif-2.1.0.json\",\n  \"version\": \"2.1.0\",\n  \"runs\": [\n    {\n      \"tool\": { \"driver\": { \"name\": \"linter\" } },\n      \"results\": [\n        {\n          \"ruleId\": \"X001\",\n          \"level\": \"error\",\n          \"message\": { \"text\": \"unused variable\" },\n          \"locations\": [\n            { \"physicalLocation\": { \"artifactLocation\": { \"uri\": \"src/a.xi\" }, \"region\": { \"startLine\": 3, \"startColumn\": 7 } } }\n          ]\n        },\n        {\n          \"message\": { \"text\": \"note text\" },\n          \"locations\": [ { \"physicalLocation\": { \"artifactLocation\": { \"uri\": \"src/b.xi\" } } } ]\n        }\n      ]\n    },\n    {\n      \"tool\": { \"driver\": { \"name\": \"audit\" } }\n    }\n  ]\n}";
  let r = sarif_parse(src);
  if !r.is_ok { return assert(false, "emitter input parses"); }
  let d: SarifDoc = r.value;
  let want = "{\"$schema\":\"https://json.schemastore.org/sarif-2.1.0.json\",\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"linter\"}},\"results\":[{\"ruleId\":\"X001\",\"level\":\"error\",\"message\":{\"text\":\"unused variable\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"src/a.xi\"},\"region\":{\"startLine\":3,\"startColumn\":7}}}]},{\"level\":\"warning\",\"message\":{\"text\":\"note text\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"src/b.xi\"}}}]}]},{\"tool\":{\"driver\":{\"name\":\"audit\"}},\"results\":[]}]}";
  return assert(streq(sarif_emit(&d), want), "canonical emit: compact bytes, fixed key order, level always written");
}

fn t7() -> TestResult {
  let src = "{\"$schema\":\"s\",\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"ruleId\":\"\",\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{}}},{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"v\"},\"region\":{\"startColumn\":5}}}]}]}]}";
  let r = sarif_parse(src);
  if !r.is_ok { return assert(false, "normalization input parses"); }
  let d: SarifDoc = r.value;
  let want = "{\"$schema\":\"s\",\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"level\":\"warning\",\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"}}},{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"v\"},\"region\":{\"startColumn\":5}}}]}]}]}";
  var ok = streq(sarif_emit(&d), want);
  if sarif_location_count(&d) != 2 { ok = false; }
  if sarif_location_line(&d, 0) != 0 { ok = false; }
  if sarif_location_column(&d, 1) != 5 { ok = false; }
  if !streq(sarif_result_rule_id(&d, 0), "") { ok = false; }
  return assert(ok, "emit normalizes an empty ruleId, an empty region and a results-less run");
}

fn t8() -> TestResult {
  let src = "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"a\"}},\"results\":[{\"ruleId\":\"R1\",\"level\":\"note\",\"message\":{\"text\":\"m \\\"q\\\"\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u1\"},\"region\":{\"startLine\":1}}},{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u2\"},\"region\":{\"startLine\":9,\"startColumn\":2}}}]},{\"level\":\"none\",\"message\":{\"text\":\"z\"}}]},{\"tool\":{\"driver\":{\"name\":\"b\"}},\"results\":[{\"level\":\"error\",\"message\":{\"text\":\"e\"}}]}]}";
  let r = sarif_parse(src);
  if !r.is_ok { return assert(false, "round-trip input parses"); }
  let d: SarifDoc = r.value;
  let out1 = sarif_emit(&d);
  let r2 = sarif_parse(out1);
  if !r2.is_ok { return assert(false, "emitted report reparses"); }
  let d2: SarifDoc = r2.value;
  var ok = same_model(&d, &d2);
  let out2 = sarif_emit(&d2);
  if !streq(out1, out2) { ok = false; }
  if !streq(sarif_result_message(&d2, 0), "m \"q\"") { ok = false; }
  if sarif_location_column(&d2, 1) != 2 { ok = false; }
  return assert(ok, "round-trip: parse -> emit -> parse preserves the model and the bytes");
}

fn t9() -> TestResult {
  let a = sarif_parse("{\"version\":\"2.0.0\",\"runs\":[]}");
  var ok = err_is(a.is_ok, a.error, "sarif: unsupported version '2.0.0'");
  let b = sarif_parse("{\"version\":\"\",\"runs\":[]}");
  if !err_is(b.is_ok, b.error, "sarif: unsupported version ''") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1\",\"runs\":[]}");
  if !err_is(c.is_ok, c.error, "sarif: unsupported version '2.1'") { ok = false; }
  let d = sarif_parse("{\"version\":\"2.1.0\"}");
  if !err_is(d.is_ok, d.error, "sarif: missing key 'runs'") { ok = false; }
  let e = sarif_parse("{\"runs\":[]}");
  if !err_is(e.is_ok, e.error, "sarif: missing key 'version'") { ok = false; }
  let f = sarif_parse("{}");
  if !err_is(f.is_ok, f.error, "sarif: missing key 'version'") { ok = false; }
  return assert(ok, "version must be exactly 2.1.0 and top-level keys are required");
}

fn t10() -> TestResult {
  let a = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{}]}");
  var ok = err_is(a.is_ok, a.error, "sarif: missing key 'tool'");
  let b = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"results\":[]}]}");
  if !err_is(b.is_ok, b.error, "sarif: missing key 'tool'") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{}}]}");
  if !err_is(c.is_ok, c.error, "sarif: missing key 'driver'") { ok = false; }
  let d = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{}}}]}");
  if !err_is(d.is_ok, d.error, "sarif: missing key 'name'") { ok = false; }
  let e = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"\"}}}]}");
  if !err_is(e.is_ok, e.error, "sarif: empty tool.driver.name") { ok = false; }
  let f = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{}]}]}");
  if !err_is(f.is_ok, f.error, "sarif: missing key 'message'") { ok = false; }
  let g = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{}}]}]}");
  if !err_is(g.is_ok, g.error, "sarif: missing key 'text'") { ok = false; }
  return assert(ok, "missing run, tool, driver, name, message and text keys are Err");
}

fn t11() -> TestResult {
  let a = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{}]}]}]}");
  var ok = err_is(a.is_ok, a.error, "sarif: missing key 'physicalLocation'");
  let b = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{}}]}]}]}");
  if !err_is(b.is_ok, b.error, "sarif: missing key 'artifactLocation'") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{}}}]}]}]}");
  if !err_is(c.is_ok, c.error, "sarif: missing key 'uri'") { ok = false; }
  let d = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{}}]}]}]}");
  if !err_is(d.is_ok, d.error, "sarif: missing key 'artifactLocation'") { ok = false; }
  return assert(ok, "missing location, physicalLocation, artifactLocation and uri keys are Err");
}

fn t12() -> TestResult {
  let a = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[],\"x\":1}");
  var ok = err_is(a.is_ok, a.error, "sarif: unknown key 'x'");
  let b = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"bogus\":1}]}");
  if !err_is(b.is_ok, b.error, "sarif: unknown key 'bogus'") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"},\"version\":\"1\"}}]}");
  if !err_is(c.is_ok, c.error, "sarif: unknown key 'version'") { ok = false; }
  let d = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"snippet\":{}}]}]}");
  if !err_is(d.is_ok, d.error, "sarif: unknown key 'snippet'") { ok = false; }
  let e = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\",\"markdown\":\"*m*\"}}]}]}");
  if !err_is(e.is_ok, e.error, "sarif: unknown key 'markdown'") { ok = false; }
  let f = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"contextRegion\":{}}}]}]}]}");
  if !err_is(f.is_ok, f.error, "sarif: unknown key 'contextRegion'") { ok = false; }
  let g = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\",\"uriBaseId\":\"SRCROOT\"}}}]}]}]}");
  if !err_is(g.is_ok, g.error, "sarif: unknown key 'uriBaseId'") { ok = false; }
  let h = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":1,\"endLine\":2}}}]}]}]}");
  if !err_is(h.is_ok, h.error, "sarif: unknown key 'endLine'") { ok = false; }
  return assert(ok, "unknown keys at every level are Err");
}

fn t13() -> TestResult {
  let a = sarif_parse("{\"version\":\"2.1.0\",\"version\":\"2.1.0\",\"runs\":[]}");
  var ok = err_is(a.is_ok, a.error, "sarif: duplicate key 'version'");
  let b = sarif_parse("{\"$schema\":\"a\",\"$schema\":\"b\",\"version\":\"2.1.0\",\"runs\":[]}");
  if !err_is(b.is_ok, b.error, "sarif: duplicate key '$schema'") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[],\"runs\":[]}");
  if !err_is(c.is_ok, c.error, "sarif: duplicate key 'runs'") { ok = false; }
  let d = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"level\":\"error\",\"level\":\"note\",\"message\":{\"text\":\"m\"}}]}]}");
  if !err_is(d.is_ok, d.error, "sarif: duplicate key 'level'") { ok = false; }
  let e = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"a\",\"text\":\"b\"}}]}]}");
  if !err_is(e.is_ok, e.error, "sarif: duplicate key 'text'") { ok = false; }
  let f = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"a\",\"uri\":\"b\"}}}]}]}]}");
  if !err_is(f.is_ok, f.error, "sarif: duplicate key 'uri'") { ok = false; }
  let g = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":1,\"startLine\":2}}}]}]}]}");
  if !err_is(g.is_ok, g.error, "sarif: duplicate key 'startLine'") { ok = false; }
  return assert(ok, "duplicate keys at every level are Err");
}

fn t14() -> TestResult {
  let a = sarif_parse("{,}");
  var ok = err_is(a.is_ok, a.error, "sarif: expected key at byte 1");
  let b = sarif_parse("{\"version\" \"2.1.0\",\"runs\":[]}");
  if !err_is(b.is_ok, b.error, "sarif: expected ':' at byte 11") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1.0\" \"runs\":[]}");
  if !err_is(c.is_ok, c.error, "sarif: expected ',' or '}' at byte 19") { ok = false; }
  let d = sarif_parse("{\"version\":\"2.1.0\",}");
  if !err_is(d.is_ok, d.error, "sarif: expected key at byte 19") { ok = false; }
  let e = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}}} {\"tool\":{\"driver\":{\"name\":\"e\"}}}]}");
  if !err_is(e.is_ok, e.error, "sarif: expected ',' or ']' at byte 60") { ok = false; }
  let f = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[");
  if !err_is(f.is_ok, f.error, "sarif: unexpected end of input at byte 27") { ok = false; }
  let g = sarif_parse("{\"version\":\"2.1.0\",");
  if !err_is(g.is_ok, g.error, "sarif: unexpected end of input at byte 19") { ok = false; }
  let h = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[]");
  if !err_is(h.is_ok, h.error, "sarif: unexpected end of input at byte 28") { ok = false; }
  let i = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[]}x");
  if !err_is(i.is_ok, i.error, "sarif: trailing data at byte 29") { ok = false; }
  return assert(ok, "structural and separator errors carry exact byte positions");
}

fn t15() -> TestResult {
  let a = sarif_parse("[]");
  var ok = err_is(a.is_ok, a.error, "sarif: expected object at byte 0");
  let b = sarif_parse("{\"version\":\"2.1.0\",\"runs\":{}}");
  if !err_is(b.is_ok, b.error, "sarif: expected array at byte 26") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[42]}");
  if !err_is(c.is_ok, c.error, "sarif: expected object at byte 27") { ok = false; }
  let d = sarif_parse("{\"version\":true,\"runs\":[]}");
  if !err_is(d.is_ok, d.error, "sarif: boolean values are not supported at byte 11") { ok = false; }
  let e = sarif_parse("{\"version\":\"2.1.0\",\"runs\":null}");
  if !err_is(e.is_ok, e.error, "sarif: null values are not supported at byte 26") { ok = false; }
  let f = sarif_parse("{\"version\":42,\"runs\":[]}");
  if !err_is(f.is_ok, f.error, "sarif: expected string at byte 11") { ok = false; }
  let g = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":1.5}}}]}]}]}");
  if !err_is(g.is_ok, g.error, "sarif: float values are not supported at byte 181") { ok = false; }
  let h = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":-1}}}]}]}]}");
  if !err_is(h.is_ok, h.error, "sarif: negative integers are not supported at byte 181") { ok = false; }
  let i = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":01}}}]}]}]}");
  if !err_is(i.is_ok, i.error, "sarif: leading zero in integer at byte 181") { ok = false; }
  let j = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":\"x\"}}}]}]}]}");
  if !err_is(j.is_ok, j.error, "sarif: expected integer at byte 181") { ok = false; }
  let k = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":99999999999999999999}}}]}]}]}");
  if !err_is(k.is_ok, k.error, "sarif: integer out of range at byte 181") { ok = false; }
  return assert(ok, "value-kind errors: expected kinds, booleans, null, float, negative, overflow");
}

fn t16() -> TestResult {
  let a = sarif_parse("{\"version\":\"2.1.0");
  var ok = err_is(a.is_ok, a.error, "sarif: unterminated string at byte 11");
  let b = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"a\\qb\"}}}]}");
  if !err_is(b.is_ok, b.error, "sarif: unsupported escape at byte 56") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"a\\u00G1b\"}}}]}");
  if !err_is(c.is_ok, c.error, "sarif: invalid \\u escape at byte 59") { ok = false; }
  let d = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"a\\u0001b\"}}}]}");
  if !err_is(d.is_ok, d.error, "sarif: non-printable \\u escape at byte 56") { ok = false; }
  let e = sarif_parse("{\"version\":\"a\tb\",\"runs\":[]}");
  if !err_is(e.is_ok, e.error, "sarif: control character in string at byte 13") { ok = false; }
  let f = sarif_parse("{\"version\":\"aéb\",\"runs\":[]}");
  if !err_is(f.is_ok, f.error, "sarif: non-ASCII byte in string at byte 13") { ok = false; }
  let g = sarif_parse("{\"version\":\"a\\");
  if !err_is(g.is_ok, g.error, "sarif: unterminated string at byte 11") { ok = false; }
  return assert(ok, "string errors: unterminated, bad/binary escapes, control and non-ASCII bytes");
}

fn t17() -> TestResult {
  let a = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"level\":\"fatal\",\"message\":{\"text\":\"m\"}}]}]}");
  var ok = err_is(a.is_ok, a.error, "sarif: invalid level 'fatal'");
  let b = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"level\":true,\"message\":{\"text\":\"m\"}}]}]}");
  if !err_is(b.is_ok, b.error, "sarif: boolean values are not supported at byte 79") { ok = false; }
  let c = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":0}}}]}]}]}");
  if !err_is(c.is_ok, c.error, "sarif: startLine must be a positive integer") { ok = false; }
  let d = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":{\"startLine\":1,\"startColumn\":0}}}]}]}]}");
  if !err_is(d.is_ok, d.error, "sarif: startColumn must be a positive integer") { ok = false; }
  let e = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"u\"},\"region\":true}}]}]}]}");
  if !err_is(e.is_ok, e.error, "sarif: boolean values are not supported at byte 168") { ok = false; }
  return assert(ok, "level and region validation: invalid level, boolean values, non-positive line/column");
}

fn t18() -> TestResult {
  let src = "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"m1\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"a\"},\"region\":{\"startLine\":1}}},{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"b\"},\"region\":{\"startLine\":2,\"startColumn\":3}}},{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"c\"}}}]},{\"message\":{\"text\":\"m2\"}}]},{\"tool\":{\"driver\":{\"name\":\"e\"}},\"results\":[{\"message\":{\"text\":\"m3\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"d\"},\"region\":{\"startColumn\":4}}}]}]}]}";
  let r = sarif_parse(src);
  if !r.is_ok { return assert(false, "multi-location report parses"); }
  let d: SarifDoc = r.value;
  var ok = sarif_run_count(&d) == 2;
  if sarif_result_count(&d) != 3 { ok = false; }
  if sarif_location_count(&d) != 4 { ok = false; }
  if sarif_run_result_count(&d, 0) != 2 { ok = false; }
  if sarif_run_result_count(&d, 1) != 1 { ok = false; }
  if sarif_result_location_count(&d, 0) != 3 { ok = false; }
  if sarif_result_location_count(&d, 1) != 0 { ok = false; }
  if sarif_result_location_count(&d, 2) != 1 { ok = false; }
  if sarif_location_result(&d, 0) != 0 { ok = false; }
  if sarif_location_result(&d, 1) != 0 { ok = false; }
  if sarif_location_result(&d, 2) != 0 { ok = false; }
  if sarif_location_result(&d, 3) != 2 { ok = false; }
  if !streq(sarif_location_uri(&d, 0), "a") { ok = false; }
  if !streq(sarif_location_uri(&d, 1), "b") { ok = false; }
  if !streq(sarif_location_uri(&d, 2), "c") { ok = false; }
  if !streq(sarif_location_uri(&d, 3), "d") { ok = false; }
  if sarif_location_line(&d, 0) != 1 { ok = false; }
  if sarif_location_line(&d, 1) != 2 { ok = false; }
  if sarif_location_line(&d, 2) != 0 { ok = false; }
  if sarif_location_column(&d, 1) != 3 { ok = false; }
  if sarif_location_column(&d, 3) != 4 { ok = false; }
  if !streq(sarif_result_uri(&d, 0), "a") { ok = false; }
  if sarif_result_line(&d, 0) != 1 { ok = false; }
  if !streq(sarif_result_uri(&d, 1), "") { ok = false; }
  if !streq(sarif_result_uri(&d, 2), "d") { ok = false; }
  if sarif_result_column(&d, 2) != 4 { ok = false; }
  let out1 = sarif_emit(&d);
  let r2 = sarif_parse(out1);
  if !r2.is_ok { ok = false; }
  if r2.is_ok {
    let d2: SarifDoc = r2.value;
    if !same_model(&d, &d2) { ok = false; }
    if !streq(sarif_emit(&d2), out1) { ok = false; }
  }
  return assert(ok, "location ranges: ownership, first-location accessors and round-trip");
}

fn t19() -> TestResult {
  let r = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[]}");
  if !r.is_ok { return assert(false, "empty report for bounds checks"); }
  let d: SarifDoc = r.value;
  var ok = streq(sarif_run_driver_name(&d, -1), "");
  if !streq(sarif_run_driver_name(&d, 0), "") { ok = false; }
  if !streq(sarif_run_driver_name(&d, 99), "") { ok = false; }
  if sarif_run_result_count(&d, 0) != 0 { ok = false; }
  if sarif_run_result_count(&d, -1) != 0 { ok = false; }
  if sarif_run_result_count(&d, 99) != 0 { ok = false; }
  if sarif_run_level_count(&d, 0, SARIF_LEVEL_ERROR) != 0 { ok = false; }
  if sarif_run_level_count(&d, -1, SARIF_LEVEL_ERROR) != 0 { ok = false; }
  if !streq(sarif_result_rule_id(&d, -1), "") { ok = false; }
  if !streq(sarif_result_rule_id(&d, 0), "") { ok = false; }
  if sarif_result_run(&d, -1) != -1 { ok = false; }
  if sarif_result_run(&d, 0) != -1 { ok = false; }
  if sarif_result_level(&d, -1) != -1 { ok = false; }
  if sarif_result_level(&d, 0) != -1 { ok = false; }
  if !streq(sarif_result_message(&d, -1), "") { ok = false; }
  if sarif_result_location_count(&d, 0) != 0 { ok = false; }
  if !streq(sarif_result_uri(&d, -1), "") { ok = false; }
  if sarif_result_line(&d, -1) != 0 { ok = false; }
  if sarif_result_column(&d, 99) != 0 { ok = false; }
  if !streq(sarif_location_uri(&d, -1), "") { ok = false; }
  if !streq(sarif_location_uri(&d, 0), "") { ok = false; }
  if sarif_location_line(&d, -1) != 0 { ok = false; }
  if sarif_location_column(&d, 0) != 0 { ok = false; }
  if sarif_location_result(&d, -1) != -1 { ok = false; }
  if sarif_location_result(&d, 0) != -1 { ok = false; }
  if sarif_level_count(&d, SARIF_LEVEL_ERROR) != 0 { ok = false; }
  if sarif_level_count(&d, 7) != 0 { ok = false; }
  if !streq(sarif_level_name(SARIF_LEVEL_ERROR), "error") { ok = false; }
  if !streq(sarif_level_name(SARIF_LEVEL_WARNING), "warning") { ok = false; }
  if !streq(sarif_level_name(SARIF_LEVEL_NOTE), "note") { ok = false; }
  if !streq(sarif_level_name(SARIF_LEVEL_NONE), "none") { ok = false; }
  if !streq(sarif_level_name(9), "") { ok = false; }
  if !streq(sarif_schema(&d), "") { ok = false; }
  return assert(ok, "out-of-range accessors are safe and level codes map to names");
}

fn t20() -> TestResult {
  let r = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"r0\"}},\"results\":[{\"level\":\"error\",\"message\":{\"text\":\"a\"}},{\"level\":\"warning\",\"message\":{\"text\":\"b\"}},{\"level\":\"note\",\"message\":{\"text\":\"c\"}}]},{\"tool\":{\"driver\":{\"name\":\"r1\"}},\"results\":[{\"level\":\"none\",\"message\":{\"text\":\"d\"}},{\"level\":\"error\",\"message\":{\"text\":\"e\"}}]}]}");
  if !r.is_ok { return assert(false, "level-count report parses"); }
  let d: SarifDoc = r.value;
  var ok = sarif_level_count(&d, SARIF_LEVEL_ERROR) == 2;
  if sarif_level_count(&d, SARIF_LEVEL_WARNING) != 1 { ok = false; }
  if sarif_level_count(&d, SARIF_LEVEL_NOTE) != 1 { ok = false; }
  if sarif_level_count(&d, SARIF_LEVEL_NONE) != 1 { ok = false; }
  if sarif_level_count(&d, 9) != 0 { ok = false; }
  if sarif_run_level_count(&d, 0, SARIF_LEVEL_ERROR) != 1 { ok = false; }
  if sarif_run_level_count(&d, 0, SARIF_LEVEL_NOTE) != 1 { ok = false; }
  if sarif_run_level_count(&d, 0, SARIF_LEVEL_NONE) != 0 { ok = false; }
  if sarif_run_level_count(&d, 1, SARIF_LEVEL_ERROR) != 1 { ok = false; }
  if sarif_run_level_count(&d, 1, SARIF_LEVEL_WARNING) != 0 { ok = false; }
  if sarif_run_level_count(&d, 99, SARIF_LEVEL_ERROR) != 0 { ok = false; }
  if sarif_run_level_count(&d, 0, 9) != 0 { ok = false; }
  return assert(ok, "level summary counts: totals and per-run counts");
}

fn t21() -> TestResult {
  let r = sarif_parse("{\"$schema\":\"https://ex/2.1.0.json\",\"version\":\"2.1.0\",\"runs\":[]}");
  if !r.is_ok { return assert(false, "schema report parses"); }
  let d: SarifDoc = r.value;
  var ok = streq(sarif_schema(&d), "https://ex/2.1.0.json");
  if !streq(sarif_emit(&d), "{\"$schema\":\"https://ex/2.1.0.json\",\"version\":\"2.1.0\",\"runs\":[]}") { ok = false; }
  let u = sarif_parse("{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"message\":{\"text\":\"\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"\"}}}]}]}]}");
  if !u.is_ok { ok = false; }
  if u.is_ok {
    let e: SarifDoc = u.value;
    if !streq(sarif_schema(&e), "") { ok = false; }
    if sarif_location_count(&e) != 1 { ok = false; }
    if !streq(sarif_location_uri(&e, 0), "") { ok = false; }
    if !streq(sarif_result_message(&e, 0), "") { ok = false; }
    if !streq(sarif_emit(&e), "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"d\"}},\"results\":[{\"level\":\"warning\",\"message\":{\"text\":\"\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"\"}}}]}]}]}") { ok = false; }
  }
  return assert(ok, "$schema pass-through and empty message/uri strings round-trip");
}

fn main() -> Int {
  io.println("=== xiom.sarif conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  failed = failed + report(r1.passed, r1.name);
  let r2 = t2();
  failed = failed + report(r2.passed, r2.name);
  let r3 = t3();
  failed = failed + report(r3.passed, r3.name);
  let r4 = t4();
  failed = failed + report(r4.passed, r4.name);
  let r5 = t5();
  failed = failed + report(r5.passed, r5.name);
  let r6 = t6();
  failed = failed + report(r6.passed, r6.name);
  let r7 = t7();
  failed = failed + report(r7.passed, r7.name);
  let r8 = t8();
  failed = failed + report(r8.passed, r8.name);
  let r9 = t9();
  failed = failed + report(r9.passed, r9.name);
  let r10 = t10();
  failed = failed + report(r10.passed, r10.name);
  let r11 = t11();
  failed = failed + report(r11.passed, r11.name);
  let r12 = t12();
  failed = failed + report(r12.passed, r12.name);
  let r13 = t13();
  failed = failed + report(r13.passed, r13.name);
  let r14 = t14();
  failed = failed + report(r14.passed, r14.name);
  let r15 = t15();
  failed = failed + report(r15.passed, r15.name);
  let r16 = t16();
  failed = failed + report(r16.passed, r16.name);
  let r17 = t17();
  failed = failed + report(r17.passed, r17.name);
  let r18 = t18();
  failed = failed + report(r18.passed, r18.name);
  let r19 = t19();
  failed = failed + report(r19.passed, r19.name);
  let r20 = t20();
  failed = failed + report(r20.passed, r20.name);
  let r21 = t21();
  failed = failed + report(r21.passed, r21.name);
  if failed == 0 {
    io.println("xiom.sarif: all tests passed");
  } else {
    io.println("xiom.sarif: tests failed");
  }
  return failed;
}
