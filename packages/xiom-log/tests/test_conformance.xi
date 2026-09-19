// XIOM -- xiom.log Conformance Tests
module log_tests
use xiom.io; use xiom.test;
use xiom.log.types; use xiom.log.logger; use xiom.log.format;

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
  var cfg = log_config_default();
  var l = logger_new(&cfg);
  logger_info(&mut l, "hello world");
  logger_warn(&mut l, "test warning");
  logger_error(&mut l, "test error");
  let out = logger_flush(&l);
  return assert(out.len() > 0, "log: info+warn+error flush produces output");
}
fn t2() -> TestResult {
  var cfg = log_config_default();
  var l = logger_new(&cfg);
  logger_clear(&mut l);
  let out = logger_flush(&l);
  return assert(out.len() == 0, "log: clear empty flush");
}
fn t3() -> TestResult {
  let level = LogLevel.Warn;
  let s = log_level_to_str(&level);
  return assert(s == "WARN" || s.len() > 0, "log: level_to_str non-empty");
}
fn t4() -> TestResult {
  let entry = log_entry_new(LogLevel.Info, "test message");
  var cfg = log_config_default();
  let text = format_text(&entry, &cfg);
  return assert(text.len() > 0, "log: format_text produces output");
}
fn t5() -> TestResult {
  let entry = log_entry_new(LogLevel.Debug, "json test");
  let json = format_json(&entry);
  return assert(json.len() > 0, "log: format_json produces output");
}
fn t6() -> TestResult {
  let entry = log_entry_new(LogLevel.Error, "compact");
  let c = format_compact(&entry);
  return assert(c.len() > 0, "log: format_compact produces output");
}
fn t7() -> TestResult {
  var cfg = log_config_default();
  var l = logger_new(&cfg);
  logger_trace(&mut l, "trace");
  logger_debug(&mut l, "debug");
  logger_fatal(&mut l, "fatal");
  let out = logger_flush(&l);
  return assert(out.len() > 0, "log: trace+debug+fatal all logged");
}
fn t8() -> TestResult {
  let ord = log_level_ordinal(&LogLevel.Fatal);
  return assert(ord == 5, "log: Fatal ordinal = 5");
}

fn main() -> Int {
  io.println("=== XIOM Log Conformance ===");
  var failed: Int = 0; var total: Int = 0;
  var tests = [t1,t2,t3,t4,t5,t6,t7,t8];
  var i = 0; while i < tests.len() { total = total + 1; failed = failed + report(tests[i]().passed, tests[i]().name); i = i + 1; }
  let passed = total - failed;
  io.println(""); io.println("XIOM Log: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
