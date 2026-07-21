module xiom.bench.types

pub type BenchConfig = {
  iterations: Int;
  warmup: Int;
  min_time_ms: Int;
}

pub type BenchResult = {
  name: Str;
  total_ms: Int;
  iterations: Int;
  ops_per_sec: Int;
  min_us: Int;
  max_us: Int;
  avg_us: Int;
}

pub type BenchSuite = {
  name: Str;
  results: Vec[BenchResult];
}

pub fn bench_config_default() -> BenchConfig {
  return BenchConfig{ iterations: 1000, warmup: 3, min_time_ms: 100 };
}

pub fn bench_suite_new(name: Str) -> BenchSuite {
  return BenchSuite{ name: name, results: Vec[BenchResult].new() };
}
