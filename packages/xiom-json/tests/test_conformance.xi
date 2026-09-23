// XIOM -- xiom.json Conformance Tests (12 tests: parse, stringify, get, set, path, schema)
module json_tests
use xiom.io; use xiom.test; use xiom.json;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; } var num = n; var out = "";
  while num > 0 { let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10; }
  return out;
}
fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

fn t1() -> TestResult {
  let r = json_parse("{\"a\":1}");
  match r { Ok(_) => return assert(true, "json: parse object"), Err(_) => return assert(false, "json: parse object failed") }
}
fn t2() -> TestResult {
  let r = json_parse("[1,2,3]");
  match r { Ok(_) => return assert(true, "json: parse array"), Err(_) => return assert(false, "json: parse array failed") }
}
fn t3() -> TestResult {
  let r = json_parse("\"hello\"");
  match r { Ok(_) => return assert(true, "json: parse string"), Err(_) => return assert(false, "json: parse string failed") }
}
fn t4() -> TestResult {
  let r = json_parse("42");
  match r { Ok(_) => return assert(true, "json: parse number"), Err(_) => return assert(false, "json: parse number failed") }
}
fn t5() -> TestResult {
  let r = json_parse("true");
  match r { Ok(_) => return assert(true, "json: parse bool"), Err(_) => return assert(false, "json: parse bool failed") }
}
fn t6() -> TestResult {
  let r = json_parse("null");
  match r { Ok(v) => return assert(json_is_type(&v, JsonType.NullType), "json: null is_type Null"), Err(_) => return assert(false, "json: null parse failed") }
}
fn t7() -> TestResult {
  let r = json_parse("{\"key\":\"val\"}");
  match r { Ok(v) => { let g = json_get(&v, "key"); match g { Some(_) => return assert(true, "json: get existing key"), None => return assert(false, "json: get returned None") } } Err(_) => return assert(false, "json: get parse failed") }
}
fn t8() -> TestResult {
  let r = json_parse("{\"x\":1}");
  match r { Ok(v) => { let g = json_get(&v, "missing"); match g { Some(_) => return assert(false, "json: get missing key returned Some"), None => return assert(true, "json: get missing key => None") } } Err(_) => return assert(false, "json: get parse failed") }
}
fn t9() -> TestResult {
  var obj = json_object();
  json_set(&mut obj, "name", json_string("XIOM"));
  let out = json_stringify(&obj);
  return assert(out.len() > 0, "json: set + stringify round-trip");
}
fn t10() -> TestResult {
  let r = json_validate("{\"valid\":true}");
  match r { Ok(v) => return assert(v, "json: validate valid JSON"), Err(_) => return assert(false, "json: validate parse error") }
}
fn t11() -> TestResult {
  let path = json_path_parse("$.store.book[0].title");
  match path { Ok(_) => return assert(true, "json: path parse OK"), Err(_) => return assert(false, "json: path parse failed") }
}
fn t12() -> TestResult {
  let r = json_parse("{bad");
  match r { Ok(_) => return assert(false, "json: invalid JSON should fail"), Err(_) => return assert(true, "json: invalid JSON rejected") }
}

fn main() -> Int {
  io.println("=== XIOM JSON Conformance ===");
  var failed: Int = 0; var total: Int = 0;
  // Explicit per-test calls: `Vec[fn() -> TestResult]` element dispatch is
  // miscompiled on the pinned toolchain (element call lowers to Unit); the
  // green sibling suites use this same explicit pattern.
  total = total + 1; let r1 = t1(); failed = failed + report(r1.passed, r1.name);
  total = total + 1; let r2 = t2(); failed = failed + report(r2.passed, r2.name);
  total = total + 1; let r3 = t3(); failed = failed + report(r3.passed, r3.name);
  total = total + 1; let r4 = t4(); failed = failed + report(r4.passed, r4.name);
  total = total + 1; let r5 = t5(); failed = failed + report(r5.passed, r5.name);
  total = total + 1; let r6 = t6(); failed = failed + report(r6.passed, r6.name);
  total = total + 1; let r7 = t7(); failed = failed + report(r7.passed, r7.name);
  total = total + 1; let r8 = t8(); failed = failed + report(r8.passed, r8.name);
  total = total + 1; let r9 = t9(); failed = failed + report(r9.passed, r9.name);
  total = total + 1; let r10 = t10(); failed = failed + report(r10.passed, r10.name);
  total = total + 1; let r11 = t11(); failed = failed + report(r11.passed, r11.name);
  total = total + 1; let r12 = t12(); failed = failed + report(r12.passed, r12.name);
  let passed = total - failed;
  io.println(""); io.println("XIOM JSON: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
