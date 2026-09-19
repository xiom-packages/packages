# xiom.test -- API Reference

Production-grade test framework for the XIOM ecosystem. Provides assertions, suite-based test organization, result aggregation, reporting, and benchmarking.

## Package

- **Name:** `xiom.test`
- **Version:** `0.1.0`
- **Module:** `xiom.test`

## Types

### `TestFailure`

Represents a single test failure.

```
pub type TestFailure = {
  name: Str;
  message: Str;
} derive[Clone]
```

| Field   | Type | Description                     |
|---------|------|---------------------------------|
| `name`  | Str  | Name of the failing test case   |
| `message` | Str | Failure description            |

### `TestResults`

Aggregated results from running one or more test suites.

```
pub type TestResults = {
  passed: Int;
  failed: Int;
  total: Int;
  failures: Vec[TestFailure];
} derive[Clone]
```

| Field     | Type              | Description                |
|-----------|-------------------|----------------------------|
| `passed`  | Int               | Number of passing tests    |
| `failed`  | Int               | Number of failing tests    |
| `total`   | Int               | Total tests executed       |
| `failures`| Vec[TestFailure]  | Detailed failure records   |

### `TestCase`

A single test case with its outcome.

```
pub type TestCase = {
  name: Str;
  passed: Bool;
  message: Str;
}
```

| Field    | Type | Description                         |
|----------|------|-------------------------------------|
| `name`   | Str  | Test case name                      |
| `passed` | Bool | `true` if the assertion passed      |
| `message`| Str  | Descriptive message (used for reports) |

### `TestSuite`

A named collection of test cases.

```
pub type TestSuite = {
  name: Str;
  cases: Vec[TestCase];
}
```

| Field  | Type          | Description                  |
|--------|---------------|------------------------------|
| `name` | Str           | Suite name (displayed in reports) |
| `cases`| Vec[TestCase] | Ordered list of test cases   |

### `BenchResult`

Results from a benchmark run.

```
pub type BenchResult = {
  name: Str;
  iterations: Int;
  elapsed_ms: Int;
  ops_per_sec: Int;
}
```

| Field        | Type | Description                              |
|--------------|------|------------------------------------------|
| `name`       | Str  | Benchmark name                           |
| `iterations` | Int  | Total iterations executed                |
| `elapsed_ms` | Int  | Wall-clock time in milliseconds          |
| `ops_per_sec`| Int  | Computed throughput (iterations * 1000 / ms) |

---

## TestResults Methods

### `TestResults.new() -> TestResults`

Creates a zero-initialized results container.

```
var results = TestResults.new();
```

### `TestResults.merge(other: &TestResults)`

Merges statistics and failures from another results object into this one. Updates `passed`, `failed`, `total`, and appends all failures.

```
results.merge(&other_results);
```

---

## TestSuite Methods

### `TestSuite.new(name: Str) -> TestSuite`

Creates a new empty test suite with the given name.

```
var suite = TestSuite.new("Math Tests");
```

### `TestSuite.add(suite: &mut TestSuite, case: TestCase)`

Adds a test case to the suite. Takes a mutable reference to the suite.

```
TestSuite.add(&suite, assert_eq(2 + 2, 4, "basic addition"));
```

### `TestSuite.run() -> TestResults`

Evaluates all test cases in the suite and returns aggregated results. Called on the suite instance.

```
var results = suite.run();
```

### `TestSuite.failed_count() -> Int`

Returns the number of failed cases currently in the suite (does not run them).

```
var failures = suite.failed_count();
```

### `TestSuite.passed_count() -> Int`

Returns the number of passed cases currently in the suite (does not run them).

```
var passes = suite.passed_count();
```

---

## Assertion Functions

All assertion functions accept a descriptive `msg: Str` and return a `TestCase`. The returned `TestCase.name` and `TestCase.message` are both set to `msg`.

### Integer Assertions

#### `assert_eq(actual: Int, expected: Int, msg: Str) -> TestCase`

Passes if `actual == expected`.

```
var tc = assert_eq(add(2, 3), 5, "add(2, 3) should return 5");
```

#### `assert_ne(actual: Int, expected: Int, msg: Str) -> TestCase`

Passes if `actual != expected`.

```
var tc = assert_ne(add(2, 2), 5, "add(2, 2) should not return 5");
```

#### `assert_lt(actual: Int, expected: Int, msg: Str) -> TestCase`

Passes if `actual < expected`.

```
var tc = assert_lt(value, 100, "value should be less than 100");
```

#### `assert_le(actual: Int, expected: Int, msg: Str) -> TestCase`

Passes if `actual <= expected`.

```
var tc = assert_le(count, max, "count should be at most max");
```

#### `assert_gt(actual: Int, expected: Int, msg: Str) -> TestCase`

Passes if `actual > expected`.

```
var tc = assert_gt(score, 0, "score should be positive");
```

#### `assert_ge(actual: Int, expected: Int, msg: Str) -> TestCase`

Passes if `actual >= expected`.

```
var tc = assert_ge(len, min_len, "length should meet minimum");
```

### Boolean Assertions

#### `assert_true(condition: Bool, msg: Str) -> TestCase`

Passes if `condition` is `true`.

```
var tc = assert_true(is_valid(input), "input should be valid");
```

#### `assert_false(condition: Bool, msg: Str) -> TestCase`

Passes if `condition` is `false`.

```
var tc = assert_false(is_locked, "resource should not be locked");
```

### Option Assertions

#### `assert_some(opt: Option[Int], msg: Str) -> TestCase`

Passes if `opt` is `Some(val)`. Fails if `None`.

```
var tc = assert_some(find_user(42), "user 42 should exist");
```

#### `assert_none(opt: Option[Int], msg: Str) -> TestCase`

Passes if `opt` is `None`. Fails if `Some(val)`.

```
var tc = assert_none(find_user(999), "user 999 should not exist");
```

### Result Assertions

#### `assert_ok(result: Result[Int, Str], msg: Str) -> TestCase`

Passes if `result` is `Ok(val)`. Fails if `Err(e)`.

```
var tc = assert_ok(parse_int("42"), "parse_int(\"42\") should succeed");
```

#### `assert_err(result: Result[Int, Str], msg: Str) -> TestCase`

Passes if `result` is `Err(e)`. Fails if `Ok(val)`.

```
var tc = assert_err(parse_int("abc"), "parse_int(\"abc\") should fail");
```

### String & Bool Equality

#### `assert_eq_str(actual: Str, expected: Str, msg: Str) -> TestCase`

Passes if `actual == expected` using `Str` equality.

```
var tc = assert_eq_str(greet("Kilo"), "Hello, Kilo!", "greeting mismatch");
```

#### `assert_eq_bool(actual: Bool, expected: Bool, msg: Str) -> TestCase`

Passes if `actual == expected`.

```
var tc = assert_eq_bool(a and b, c, "logical expression mismatch");
```

---

## Runner Functions

### `run_suite(suite: &TestSuite) -> TestResults`

Evaluates all cases in a suite and returns aggregated results. Standalone function -- use when you don't want to call the method form.

```
var results = run_suite(&suite);
```

### `run_all(suites: &Vec[TestSuite]) -> TestResults`

Runs multiple suites sequentially and merges results into a single `TestResults`.

```
var all_results = run_all(&all_suites);
```

---

## Reporting Functions

### `report(results: &TestResults) -> Str`

Returns a one-line summary string: `"Test Results: N passed, M failed, T total"`.

```
var summary = report(&results);
```

### `report_verbose(results: &TestResults) -> Str`

Returns a multi-line report including the summary line followed by a list of each failure with its name and message.

```
var full_report = report_verbose(&results);
```

Example output:
```
Test Results: 8 passed, 2 failed, 10 total

Failures:
  - divide by zero: divide(5, 0) should return error
  - negative square root: sqrt(-4) should fail
```

---

## Benchmark Functions

### `bench_result(name: Str, iterations: Int, ms: Int) -> BenchResult`

Creates a `BenchResult` from raw benchmark data. Computes `ops_per_sec` as `(iterations * 1000) / ms`. If `ms` is 0, `ops_per_sec` is set to 0.

```
var b = bench_result("fib(20)", 1000, 42);
```

### `bench_report(result: &BenchResult) -> Str`

Formats a benchmark result as a one-line string.

```
var line = bench_report(&b);
```

Example output:
```
Bench: fib(20) -- 1000 iter, 42 ms, 23809 ops/sec
```

---

## Usage Patterns

### Pattern 1: Single Suite with Inline Assertions

```
var suite = TestSuite.new("Math");
TestSuite.add(&suite, assert_eq(1 + 1, 2, "addition identity"));
TestSuite.add(&suite, assert_eq(2 * 3, 6, "multiplication"));
TestSuite.add(&suite, assert_true(5 > 3, "greater than"));
var results = suite.run();
var out = report(&results);
```

### Pattern 2: Multiple Suites with run_all

```
var math_suite = TestSuite.new("Math");
TestSuite.add(&math_suite, assert_eq(2 + 2, 4, "addition"));

var str_suite = TestSuite.new("Strings");
TestSuite.add(&str_suite, assert_eq_str("hello", "hello", "equality"));

var suites = Vec[TestSuite].new();
suites.push(math_suite);
suites.push(str_suite);

var all = run_all(&suites);
var out = report_verbose(&all);
```

### Pattern 3: Testing Functions That Return Option

```
fn safe_divide(a: Int, b: Int) -> Option[Int] {
  if b == 0 {
    return None;
  }
  return Some(a / b);
}

var suite = TestSuite.new("Division");
TestSuite.add(&suite, assert_some(safe_divide(10, 2), "10/2 should succeed"));
TestSuite.add(&suite, assert_none(safe_divide(10, 0), "10/0 should return None"));
var results = suite.run();
```

### Pattern 4: Testing Functions That Return Result

```
fn parse_int(s: Str) -> Result[Int, Str] {
  if s == "" {
    return Err("empty string");
  }
  return Ok(42);
}

var suite = TestSuite.new("Parsing");
TestSuite.add(&suite, assert_ok(parse_int("42"), "valid number"));
TestSuite.add(&suite, assert_err(parse_int(""), "empty input"));
var results = suite.run();
```

### Pattern 5: Benchmarking

```
var start = now_ms();
var i: Int = 0;
while i < 10000 {
  expensive_computation();
  i = i + 1;
}
var elapsed = now_ms() - start;
var b = bench_result("expensive_computation", 10000, elapsed);
var out = bench_report(&b);
```

---

## Design Conventions

- **No exceptions**: All test outcomes are data (`TestCase.passed: Bool`). Nothing throws.
- **Immutable reports**: `TestResults`, `TestCase`, and `BenchResult` are value types passed by reference where needed.
- **Suite ownership**: Suites own their cases. `run_suite` and `run_all` produce new `TestResults` without mutating suites.
- **Merge semantics**: `TestResults.merge` aggregates both counts and failure lists for cumulative reporting.
