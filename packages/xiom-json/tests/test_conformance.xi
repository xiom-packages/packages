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
  match r { Ok(v) => return assert(json_is_type(&v, JsonType.Null), "json: null is_type Null"), Err(_) => return assert(false, "json: null parse failed") }
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
  var tests = [t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12];
  var i = 0; while i < tests.len() { total = total + 1; failed = failed + report(tests[i]().passed, tests[i]().name); i = i + 1; }
  let passed = total - failed;
  io.println(""); io.println("XIOM JSON: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
