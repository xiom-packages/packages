# xiom-bench

Structured benchmarking suite for XIOM.

## Installation

```xiom
deps: { "xiom-bench": "0.1.0" };
```

## Usage

### Quick Benchmark

```xiom
let config = bench_config_default();
let result = bench_result_new("my_operation", 150, 10000);
# result.ops_per_sec → 66666
# result.avg_us     → 15
```

### Comparing Benchmarks

```xiom
let baseline = bench_result_new("v1.0", 200, 5000);
let candidate = bench_result_new("v1.1", 150, 5000);
let report = bench_compare(&baseline, &candidate);
# "v1.1 is 25% faster than v1.0"
```

### Suite Reports

```xiom
let suite = bench_suite_new("JSON Parsing");
suite.results.push(bench_result_new("parse_small", 12, 1000));
suite.results.push(bench_result_new("parse_large", 145, 1000));
let report = bench_report_suite(&suite);
# Benchmark suite: JSON Parsing
# ----------------------------------------
# parse_small | 12ms | 1000 iters | 83333 ops/s | avg 12us
# parse_large | 145ms | 1000 iters | 6896 ops/s | avg 145us
```

### Statistical Analysis

```xiom
let data = vec![10, 20, 20, 30, 100];
let mean = stats_mean(&data);          # 36
let sorted = vec![10, 20, 20, 30, 100];
let median = stats_median(&sorted);    # 20
let stddev = stats_stddev(&sorted, 36); # 32
let p90 = stats_percentile(&sorted, 90); # 100
```

## Modules

| Module | Description |
|---|---|
| `xiom.bench.types` | Benchmark configuration, results, and suite types |
| `xiom.bench.runner` | Execution, comparison, and report formatting |
| `xiom.bench.stats` | Mean, median, standard deviation, percentiles |

## Limitations

- Wall-clock timing requires native backend integration. Pure XIOM benchmarks use pre-computed timing values passed to `bench_result_new`.
- Standard deviation uses integer math — results are approximations.

## License

MIT
