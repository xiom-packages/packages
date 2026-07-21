module xiom.bench.runner

use xiom.bench.types;
use xiom.convert;
use xiom.string;

fn bench_ops_per_sec(total_ms: Int, iterations: Int) -> Int {
  if total_ms <= 0 || iterations <= 0 {
    0
  } else {
    (iterations * 1000) / total_ms
  }
}

fn bench_result_new(name: Str, total_ms: Int, iterations: Int) -> BenchResult {
  var ops = bench_ops_per_sec(total_ms, iterations);
  var avg_us = 0;
  if iterations > 0 {
    avg_us = (total_ms * 1000) / iterations;
  }
  return BenchResult{
    name: name,
    total_ms: total_ms,
    iterations: iterations,
    ops_per_sec: ops,
    min_us: 0,
    max_us: 0,
    avg_us: avg_us,
  };
}

fn bench_run(name: Str, config: &BenchConfig) -> BenchResult {
  return bench_result_new(name, config.min_time_ms, config.iterations);
}

fn bench_compare(baseline: &BenchResult, candidate: &BenchResult) -> Str {
  if baseline.ops_per_sec == 0 {
    return "Cannot compare: baseline has zero ops/sec";
  } elif candidate.ops_per_sec == 0 {
    return "Cannot compare: candidate has zero ops/sec";
  } else {
    var ratio = (candidate.ops_per_sec * 100) / baseline.ops_per_sec;
    var faster = candidate.ops_per_sec > baseline.ops_per_sec;
    if faster {
      var diff_str = xiom.convert.int_to_string(ratio - 100);
      var s0 = xiom.string.str_concat(candidate.name, " is ");
      var s1 = xiom.string.str_concat(s0, diff_str);
      var s2 = xiom.string.str_concat(s1, "% faster than ");
      var s3 = xiom.string.str_concat(s2, baseline.name);
      return s3;
    } else {
      var diff_str = xiom.convert.int_to_string(100 - ratio);
      var s0 = xiom.string.str_concat(candidate.name, " is ");
      var s1 = xiom.string.str_concat(s0, diff_str);
      var s2 = xiom.string.str_concat(s1, "% slower than ");
      var s3 = xiom.string.str_concat(s2, baseline.name);
      return s3;
    }
  }
}

fn bench_report_suite(suite: &BenchSuite) -> Str {
  if suite.results.len() == 0 {
    var s0 = xiom.string.str_concat("Benchmark suite '", suite.name);
    var s1 = xiom.string.str_concat(s0, "': no results");
    return s1;
  } else {
    var s0 = xiom.string.str_concat("Benchmark suite: ", suite.name);
    var s1 = xiom.string.str_concat(s0, "\n");
    var header = xiom.string.str_concat(s1, bench_report_separator());
    return bench_report_entries(&suite.results, 0, header);
  }
}

fn bench_report_separator() -> Str {
  "----------------------------------------"
}

fn bench_report_entries(results: &Vec[BenchResult], idx: Int, acc: Str) -> Str {
  if idx >= results.len() {
    return acc;
  }
  var r = &results[idx];
  var line = bench_report_format_result(r);
  var new_acc = xiom.string.str_concat(acc, "\n");
  var new_acc2 = xiom.string.str_concat(new_acc, line);
  return bench_report_entries(results, idx + 1, new_acc2);
}

fn bench_report_format_result(r: &BenchResult) -> Str {
  var s0 = xiom.string.str_concat(r.name, " | ");
  var s1 = xiom.string.str_concat(s0, xiom.convert.int_to_string(r.total_ms));
  var s2 = xiom.string.str_concat(s1, "ms");
  var s3 = xiom.string.str_concat(s2, " | ");
  var s4 = xiom.string.str_concat(s3, xiom.convert.int_to_string(r.iterations));
  var s5 = xiom.string.str_concat(s4, " iters");
  var s6 = xiom.string.str_concat(s5, " | ");
  var s7 = xiom.string.str_concat(s6, xiom.convert.int_to_string(r.ops_per_sec));
  var s8 = xiom.string.str_concat(s7, " ops/s");
  var s9 = xiom.string.str_concat(s8, " | avg ");
  var s10 = xiom.string.str_concat(s9, xiom.convert.int_to_string(r.avg_us));
  var s11 = xiom.string.str_concat(s10, "us");
  return s11;
}
