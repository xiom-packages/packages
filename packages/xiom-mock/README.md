# xiom.mock

> **Status:** `incubating` -- conformance-tested (20/20); not yet published to the XIOM registry.
> **Scope:** deterministic expectation, call-recording and verification test
> doubles for explicit calls.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.compare` and
> `xiom.convert`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.mock` is a plain-value test double: declare named expectations with a
cardinality (`exactly N`, `at least N`, `at most N`), record calls as the
code under test makes them, then ask whether the expectations were met.
Matching is by call name and is case-sensitive; arguments are captured as
opaque text so any signature can be logged without generics or function
pointers. Nothing intercepts real calls -- there are no runtime hooks and no
FFI -- so the double is fully deterministic and portable.

- **Expectations** -- `mock_expect` / `mock_expect_at_least` /
  `mock_expect_at_most`, validated (non-empty, non-negative, unique) with
  deterministic `Err`s that never mutate the mock.
- **Recording** -- every call is appended to the log; calls matching an
  expectation grow its actual count; calls matching nothing are also listed
  as unexpected calls.
- **Verification** -- `mock_verified`, `mock_unmet_count` and
  `mock_verify_message` (first unmet expectation, in declaration order);
  `mock_unexpected_message` covers unexpected calls.
- **Reuse** -- `mock_reset` clears the log but keeps expectations;
  `mock_clear` returns the mock to its fresh state.

## API

| Function | Returns | Description |
|---|---|---|
| `mock_new()` | `Mock` | Fresh mock, no expectations, no calls. |
| `mock_expect(m, name, times)` | `Result[Int, Str]` | Exactly `times` calls; `Ok(index)`. |
| `mock_expect_at_least(m, name, times)` | `Result[Int, Str]` | At least `times` calls. |
| `mock_expect_at_most(m, name, times)` | `Result[Int, Str]` | At most `times` calls. |
| `mock_record(m, name, args)` | nothing | Log one call (never rejected). |
| `mock_call_total(m)` | `Int` | Recorded calls. |
| `mock_call_name(m, i)` / `mock_call_args(m, i)` | `Str` | Call log, in order. |
| `mock_call_count(m, name)` | `Int` | Calls with a name (matched or not). |
| `mock_unexpected_count(m)` / `mock_unexpected_name(m, i)` / `mock_unexpected_args(m, i)` | `Int` / `Str` | Calls that matched nothing. |
| `mock_unexpected_message(m)` | `Str` | First unexpected call, `mock: unexpected call '<name>'`. |
| `mock_expectation_count(m)` | `Int` | Declared expectations. |
| `mock_expectation_index(m, name)` | `Int` | Declaration index, `-1` when unknown. |
| `mock_mode(m, name)` | `Int` | `0` exactly, `1` at least, `2` at most, `-1` unknown. |
| `mock_expected(m, name)` / `mock_actual(m, name)` | `Int` | Declared / matched counts, `-1` unknown. |
| `mock_unmet_count(m)` | `Int` | Unsatisfied expectations. |
| `mock_verified(m)` | `Bool` | True when all expectations are met. |
| `mock_verify_message(m)` | `Str` | First unmet expectation; `""` when verified. |
| `mock_reset(m)` | nothing | Clear the log; keep expectations. |
| `mock_clear(m)` | nothing | Forget everything. |

## Usage

```xi
use xiom.mock;
use xiom.io;

fn main() -> Int {
  var m = mock_new();
  mock_expect(&mut m, "GET /users", 1);
  mock_expect_at_most(&mut m, "DELETE", 0);

  mock_record(&mut m, "GET /users", "id=7");
  mock_record(&mut m, "GET /health", "");

  io.println(mock_verified(&m));                    // true
  io.println(mock_actual(&m, "GET /users"));        // 1
  io.println(mock_unexpected_count(&m));            // 1
  io.println(mock_unexpected_message(&m));          // mock: unexpected call 'GET /health'
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.mock
```

Expected tail: 20 `[PASS]` lines, `xiom.mock: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- Explicit calls only: no interception, no runtime hooks, no FFI. The code
  under test must call the mock through recorded helper code.
- Matching is by exact, case-sensitive name; no wildcards, matchers or
  argument-based dispatch (arguments are opaque text).
- Verification checks expectations only; unexpected calls are reported but
  do not fail `mock_verified` -- assert on `mock_unexpected_count`.
- `mock_verify_message` reports the first unmet expectation, not all of
  them; use `mock_unmet_count` for the total.
- No ordering constraints between calls, no concurrency (a mock is a value).
- In-memory only: no file I/O, no FFI.

See `SPEC.md` for the exact semantics, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
