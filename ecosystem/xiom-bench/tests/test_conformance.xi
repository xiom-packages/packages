// XIOM — xiom-bench Conformance Tests
// 17 tests covering all public types (BenchConfig, BenchResult, BenchSuite)
// and public functions (bench_config_default, bench_suite_new)
module bench_tests
use xiom.io; use xiom.test; use xiom.bench.types;

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

// ═══ bench_config_default ═══
fn t1() -> TestResult { let c = bench_config_default(); return assert(c.iterations == 1000, "types: default iterations=1000"); }
fn t2() -> TestResult { let c = bench_config_default(); return assert(c.warmup == 3, "types: default warmup=3"); }
fn t3() -> TestResult { let c = bench_config_default(); return assert(c.min_time_ms == 100, "types: default min_time_ms=100"); }
fn t4() -> TestResult { let c = bench_config_default(); return assert(c.iterations > 0, "types: default iterations positive"); }
fn t5() -> TestResult { let c = bench_config_default(); return assert(c.warmup > 0, "types: default warmup positive"); }
fn t6() -> TestResult { let c = bench_config_default(); return assert(c.min_time_ms > 0, "types: default min_time_ms positive"); }

// ═══ bench_suite_new ═══
fn t7() -> TestResult { let s = bench_suite_new("my_bench"); return assert(s.name == "my_bench", "types: suite_new name matches"); }
fn t8() -> TestResult { let s = bench_suite_new("test"); return assert(s.results.len() == 0, "types: suite_new results empty"); }
fn t9() -> TestResult { let s = bench_suite_new(""); return assert(s.results.len() == 0, "types: suite_new empty name results"); }

// ═══ BenchConfig manual construction ═══
fn t10() -> TestResult {
  var c = BenchConfig{ iterations: 500, warmup: 5, min_time_ms: 200 };
  return assert(c.iterations == 500 && c.warmup == 5 && c.min_time_ms == 200, "types: BenchConfig manual fields");
}
fn t11() -> TestResult {
  var c1 = bench_config_default();
  var c2 = BenchConfig{ iterations: 1, warmup: 0, min_time_ms: 1 };
  return assert(c1.iterations == 1000 && c2.iterations == 1, "types: independent config instances");
}

// ═══ BenchResult manual construction ═══
fn t12() -> TestResult {
  var r = BenchResult{ name: "test_fn", total_ms: 50, iterations: 1000, ops_per_sec: 20000, min_us: 10, max_us: 500, avg_us: 50 };
  return assert(r.name == "test_fn" && r.total_ms == 50 && r.iterations == 1000, "types: BenchResult manual fields");
}

// ═══ BenchSuite with results ═══
fn t13() -> TestResult {
  var s = bench_suite_new("suite1");
  var r = BenchResult{ name: "fn_a", total_ms: 10, iterations: 100, ops_per_sec: 10000, min_us: 5, max_us: 200, avg_us: 100 };
  s.results.push(r);
  return assert(s.results.len() == 1 && s.results[0].name == "fn_a", "types: suite push + retrieve result");
}
fn t14() -> TestResult {
  var s = bench_suite_new("suite2");
  var r1 = BenchResult{ name: "a", total_ms: 10, iterations: 100, ops_per_sec: 10000, min_us: 5, max_us: 200, avg_us: 100 };
  var r2 = BenchResult{ name: "b", total_ms: 20, iterations: 200, ops_per_sec: 10000, min_us: 10, max_us: 300, avg_us: 100 };
  s.results.push(r1); s.results.push(r2);
  return assert(s.results.len() == 2, "types: suite push two results");
}
fn t15() -> TestResult {
  var s = bench_suite_new("order");
  var r1 = BenchResult{ name: "first", total_ms: 10, iterations: 100, ops_per_sec: 10000, min_us: 5, max_us: 200, avg_us: 100 };
  var r2 = BenchResult{ name: "second", total_ms: 20, iterations: 200, ops_per_sec: 10000, min_us: 10, max_us: 300, avg_us: 100 };
  s.results.push(r1); s.results.push(r2);
  return assert(s.results[0].name == "first" && s.results[1].name == "second", "types: suite result order preserved");
}
fn t16() -> TestResult {
  var s1 = bench_suite_new("A");
  var s2 = bench_suite_new("B");
  return assert(s1.name != s2.name, "types: independent suite instances");
}
fn t17() -> TestResult {
  var s = bench_suite_new("full");
  var r = BenchResult{ name: "fn", total_ms: 5, iterations: 50, ops_per_sec: 10000, min_us: 1, max_us: 100, avg_us: 100 };
  s.results.push(r);
  return assert(s.name == "full" && s.results[0].name == "fn" && s.results[0].total_ms == 5, "types: full suite round-trip");
}

// ═══ Main ═══
fn main() -> Int {
  io.println("=== XIOM Bench Conformance ===");
  var failed: Int = 0; var total: Int = 0;
  var tests = [t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17];
  var i = 0; while i < tests.len() { total = total + 1; failed = failed + report(tests[i]().passed, tests[i]().name); i = i + 1; }
  let passed = total - failed;
  io.println(""); io.println("XIOM Bench: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
