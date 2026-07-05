# xiom-bench SPEC

## Package Overview
`xiom-bench` is a structured benchmarking suite for the XIOM language. It provides types for configuring and reporting benchmarks, statistical analysis of timing data, and formatted report generation.

## Modules

### `xiom.bench.types` — Benchmark Data Types
| Type | Fields |
|---|---|
| `BenchConfig` | `iterations: Int; warmup: Int; min_time_ms: Int;` |
| `BenchResult` | `name: Str; total_ms: Int; iterations: Int; ops_per_sec: Int; min_us: Int; max_us: Int; avg_us: Int;` |
| `BenchSuite` | `name: Str; results: Vec[BenchResult];` |

**Constructors:**
- `bench_config_default() -> BenchConfig` — `{ iterations: 1000; warmup: 3; min_time_ms: 100 }`
- `bench_suite_new(name: Str) -> BenchSuite` — empty results list

### `xiom.bench.runner` — Benchmark Execution
| Function | Signature | Description |
|---|---|---|
| `bench_run` | `(name: Str, config: &BenchConfig) -> BenchResult` | Runs benchmark (stub: uses pre-computed timing) |
| `bench_result_new` | `(name: Str, total_ms: Int, iterations: Int) -> BenchResult` | Constructs result with computed metrics |
| `bench_compare` | `(baseline: &BenchResult, candidate: &BenchResult) -> Str` | Percentage comparison report |
| `bench_report_suite` | `(suite: &BenchSuite) -> Str` | Multi-line formatted suite report |
| `bench_ops_per_sec` | `(total_ms: Int, iterations: Int) -> Int` | Throughput calculation |

**Metrics:**
- `ops_per_sec = (iterations * 1000) / total_ms`
- `avg_us = (total_ms * 1000) / iterations`
- `min_us` and `max_us` default to 0 (not measurable in pure XIOM)

### `xiom.bench.stats` — Statistical Functions
| Function | Signature | Notes |
|---|---|---|
| `stats_mean` | `(data: &Vec[Int]) -> Int` | Arithmetic mean, returns 0 for empty |
| `stats_median` | `(data: &Vec[Int]) -> Int` | Requires sorted input |
| `stats_stddev` | `(data: &Vec[Int], mean: Int) -> Int` | Population standard deviation (integer approximation) |
| `stats_percentile` | `(data: &Vec[Int], p: Int) -> Int` | `p` in 0–100, requires sorted input |

**Implementation details:**
- Integer square root via Newton's method for `stats_stddev`.
- Percentile uses linear interpolation: `idx = (p * len) / 100`.
- All iteration is tail-recursive (no `for` loops).

## Error Handling
No fallible operations in this package. All functions return direct values. Edge cases (empty data, zero iterations) return 0 or appropriate defaults.

## Dependencies
- `xiom-std` (0.1.0): Vec, Int, Str, Bool types.

## Design Constraints
- Wall-clock timing is **not available** in pure XIOM. `bench_run` returns results using `config.min_time_ms` as a placeholder. Real timing requires OS-level FFI.
- No `for` loops — all list processing uses tail-recursive helpers.
- No generic constraints or `self` methods.
