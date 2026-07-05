# xiom-test

> Lightweight test framework for XIOM — test suites, assertions, benchmarks, and reporting.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-test provides a complete unit testing and benchmarking framework for XIOM. 14 assertion helpers covering Int, Bool, Str, Option, and Result types, plus test suite organization, verbose reporting, and performance benchmarks.

## Installation
```bash
xiom install xiom-test
```

## Quick Start
```xiom
use xiom.test;

fn test_addition() -> TestSuite {
  var suite = TestSuite.new("math");
  suite.add_case(assert_eq(2 + 2, 4, "basic addition"));
  suite.add_case(assert_true(5 > 3, "comparison"));
  return suite;
}

fn main() -> Int {
  var results = run_suite(&test_addition());
  // results.passed, results.failed
  return 0;
}
```

## API Reference

### Assertions (14 helpers, all return TestCase)
| Function | Checks |
|----------|--------|
| `assert_eq(actual, expected, msg)` | Int equality |
| `assert_ne(actual, expected, msg)` | Int inequality |
| `assert_lt/le/gt/ge(actual, expected, msg)` | Comparisons |
| `assert_true/false(condition, msg)` | Boolean |
| `assert_some/none(opt, msg)` | Option presence |
| `assert_ok/err(result, msg)` | Result success/failure |
| `assert_eq_str(actual, expected, msg)` | String equality |
| `assert_eq_bool(actual, expected, msg)` | Bool equality |

### Test Organization
| Function | Description |
|----------|-------------|
| `TestSuite.new(name)` | Create suite |
| `TestSuite.add(suite, case)` | Add test case |
| `run_suite(suite)` | Run and return results |
| `run_all(suites)` | Run multiple suites |
| `report(results)` | Summary report |
| `report_verbose(results)` | Detailed report with failures |

### Benchmarking
| Function | Description |
|----------|-------------|
| `bench_result(name, iters, ms)` | Create benchmark result |
| `bench_report(result)` | Format benchmark report |

## Production Readiness
| Feature | Status |
|---------|--------|
| 14 assertion types | ✅ Complete |
| TestSuite organization | ✅ Complete |
| Pass/fail reporting | ✅ Complete |
| Verbose failure output | ✅ Complete |
| Multi-suite runner | ✅ Complete |
| Benchmark support | ✅ Complete |
| Test discovery (auto-run) | ❌ Not yet |
| Test fixtures (setup/teardown) | ❌ Not yet |
| Parameterized tests | ❌ Not yet |
| JUnit XML output | ❌ Not yet |

### What's Left
1. **Auto-discovery** — scan for `test_` prefixed functions
2. **Fixtures** — setup/teardown per suite
3. **Parameterized tests** — run same test with multiple inputs
4. **Output formats** — JUnit XML, TAP, JSON

## Build & Run

```bash
xiomc --run myprogram.xi
```

## Dependencies: None (Pure XIOM)
## Links: [xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/xiom-lang/XIOM)
## License: MIT OR Apache-2.0
