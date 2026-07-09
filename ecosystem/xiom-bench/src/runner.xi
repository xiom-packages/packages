module xiom.bench.runner

fn bench_ops_per_sec(total_ms: Int, iterations: Int) -> Int {
  if total_ms <= 0 || iterations <= 0 {
    0
  } else {
    (iterations * 1000) / total_ms
  }
}

fn bench_result_new(name: Str, total_ms: Int, iterations: Int) -> BenchResult {
  let ops = bench_ops_per_sec(total_ms, iterations);
  let avg_us = if iterations > 0 { (total_ms * 1000) / iterations } else { 0 };
  BenchResult {
    name: name;
    total_ms: total_ms;
    iterations: iterations;
    ops_per_sec: ops;
    min_us: 0;
    max_us: 0;
    avg_us: avg_us;
  }
}

fn bench_run(name: Str, config: &BenchConfig) -> BenchResult {
  let _ = config;
  bench_result_new(name, config.min_time_ms, config.iterations)
}

fn bench_compare(baseline: &BenchResult, candidate: &BenchResult) -> Str {
  if baseline.ops_per_sec == 0 {
    "Cannot compare: baseline has zero ops/sec"
  } elif candidate.ops_per_sec == 0 {
    "Cannot compare: candidate has zero ops/sec"
  } else {
    let ratio = (candidate.ops_per_sec * 100) / baseline.ops_per_sec;
    let faster = candidate.ops_per_sec > baseline.ops_per_sec;
    if faster {
      candidate.name + " is " + Int_to_str(ratio - 100) + "% faster than " + baseline.name
    } else {
      candidate.name + " is " + Int_to_str(100 - ratio) + "% slower than " + baseline.name
    }
  }
}

fn bench_report_suite(suite: &BenchSuite) -> Str {
  if suite.results.len() == 0 {
    "Benchmark suite '" + suite.name + "': no results"
  } else {
    let header = "Benchmark suite: " + suite.name + "\n" + bench_report_separator();
    bench_report_entries(&suite.results, 0, header)
  }
}

fn bench_report_separator() -> Str {
  "----------------------------------------"
}

fn bench_report_entries(results: &Vec[BenchResult], idx: Int, acc: Str) -> Str {
  if idx >= results.len() {
    acc
  } else {
    let r = &results[idx];
    let line = bench_report_format_result(r);
    let new_acc = acc + "\n" + line;
    bench_report_entries(results, idx + 1, new_acc)
  }
}

fn bench_report_format_result(r: &BenchResult) -> Str {
  r.name
    + " | " + Int_to_str(r.total_ms) + "ms"
    + " | " + Int_to_str(r.iterations) + " iters"
    + " | " + Int_to_str(r.ops_per_sec) + " ops/s"
    + " | avg " + Int_to_str(r.avg_us) + "us"
}
