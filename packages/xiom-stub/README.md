# xiom.stub

> **Status:** `incubating` -- conformance-tested (22/22); not yet published on the XIOM registry.
> **Scope:** ordered programmable test stubs: expectation matchers over method
> names and Int argument tuples, canned return values, failure actions,
> cardinality constraints and structured violation reports.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.compare` and
> `xiom.convert`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.stub` is a plain-value test double you program, not intercept. Declare
ordered expectations -- a method name, an Int argument tuple, a cardinality
(`exactly N`, `at least N`, `at most N`), a canned return value and an
optional failure message -- then have the code under test invoke the stub.
Every invocation is recorded with a sequence number and binds to the first
expectation (declaration order) whose method and argument tuple match and
which still accepts a call. Same-matcher expectations therefore serve
sequential responses, in order.

Verification is structured, not a single boolean: missing calls, unexpected
calls and calls that overtook an unsatisfied earlier expectation (out of
order) are counted, exposed positionally and rendered as exact messages.
Nothing intercepts real calls -- no runtime hooks, no reflection, no
threads, no FFI -- so a stub is fully deterministic and portable.

- **Expectations** -- `stub_expect{0..3}`, `stub_expect_at_least{0..3}`,
  `stub_expect_at_most{0..3}` and `stub_expect_fail{0..3}`; methods must be
  non-empty, counts non-negative, failure messages non-empty. A failed
  declaration never mutates the stub.
- **Invocation** -- `stub_invoke{0..3}` always records the call, updates the
  bound expectation and returns the canned value; a failure action returns
  `Err(message)` verbatim. Strict mode (default) returns `Err` for an
  unmatched call; lenient mode returns `Ok(0)` and still records it.
- **Verification** -- `stub_verified`, `stub_violation_count`,
  `stub_verify_message` and the full `stub_report`, plus per-category
  accessors: missing, extra and out-of-order.
- **Reuse** -- `stub_reset` clears calls and violations but keeps
  expectations; `stub_clear` returns the stub to its fresh state.

## API

`{0..3}` means one arity-specialized function per tuple size (0 to 3 Int
arguments).

| Function | Returns | Description |
|---|---|---|
| `stub_new()` | `Stub` | Fresh strict stub, no expectations, no calls. |
| `stub_expect{0..3}(m, method, [a0[, a1[, a2]]], times, returns)` | `Result[Int, Str]` | Exactly `times` calls; `Ok(index)`. |
| `stub_expect_at_least{0..3}(m, method, [args], times, returns)` | `Result[Int, Str]` | At least `times` calls; accepts extras. |
| `stub_expect_at_most{0..3}(m, method, [args], times, returns)` | `Result[Int, Str]` | At most `times` calls; surplus is unexpected. |
| `stub_expect_fail{0..3}(m, method, [args], message)` | `Result[Int, Str]` | Exactly one failing call; returns `Err(message)`. |
| `stub_invoke{0..3}(m, method, [args])` | `Result[Int, Str]` | Record, bind and respond. |
| `stub_set_lenient(m, on)` / `stub_is_lenient(m)` | nothing / `Bool` | Unmatched-call policy. |
| `stub_expectation_count(m)` | `Int` | Declared expectations. |
| `stub_expect_method(m, i)` | `Str` | Method name; `""` out of range. |
| `stub_expect_mode(m, i)` | `Int` | `0` exactly, `1` at least, `2` at most, `-1` out of range. |
| `stub_expect_times(m, i)` / `stub_expect_actual(m, i)` | `Int` | Declared / matched counts; `-1` out of range. |
| `stub_expect_return(m, i)` | `Int` | Canned return value; `-1` out of range. |
| `stub_expect_has_failure(m, i)` / `stub_expect_failure(m, i)` | `Bool` / `Str` | Failure action, if any. |
| `stub_expect_arg_count(m, i)` / `stub_expect_arg(m, i, k)` | `Int` | Argument tuple; `0` out of range. |
| `stub_expect_met(m, i)` | `Bool` | Whether expectation `i` is satisfied. |
| `stub_call_total(m)` | `Int` | Recorded calls. |
| `stub_call_seq(m, i)` | `Int` | Sequence number (the log position); `-1` out of range. |
| `stub_call_method(m, i)` / `stub_call_arg_count(m, i)` / `stub_call_arg(m, i, k)` | `Str` / `Int` | Call log entry. |
| `stub_call_match(m, i)` / `stub_call_matched(m, i)` | `Int` / `Bool` | Bound expectation index (`-1` when unmatched). |
| `stub_matched_count(m)` / `stub_unmatched_count(m)` | `Int` | Accounting totals. |
| `stub_missing_count(m)` / `stub_missing_index(m, k)` / `stub_missing_message(m, k)` | `Int` / `Int` / `Str` | Unsatisfied expectations. |
| `stub_extra_count(m)` / `stub_extra_call(m, k)` / `stub_extra_message(m, k)` | `Int` / `Int` / `Str` | Unexpected calls. |
| `stub_out_of_order_count(m)` / `stub_out_of_order_call(m, k)` / `stub_out_of_order_expectation(m, k)` / `stub_out_of_order_message(m, k)` | `Int` / `Int` / `Int` / `Str` | Calls that overtook an earlier unsatisfied expectation. |
| `stub_violation_count(m)` | `Int` | Missing + extra + out-of-order. |
| `stub_verified(m)` | `Bool` | True when there are no violations. |
| `stub_verify_message(m)` | `Str` | First violation, missing before extra before out-of-order; `""` when verified. |
| `stub_report(m)` | `Str` | Full structured report, one line per violation; `""` when verified. |
| `stub_reset(m)` / `stub_clear(m)` | nothing | Clear calls and violations / clear everything. |

## Usage

```xi
use xiom.io;
use xiom.stub;

fn main() -> Int {
  var s = stub_new();
  stub_expect1(&mut s, "fetch", 7, 1, 100);              // fetch(7) once -> 100
  stub_expect_fail2(&mut s, "put", 1, 2, "disk full");   // put(1, 2) once -> Err
  stub_expect_at_least0(&mut s, "log", 1, 0);            // log() >= 1 time -> 0

  io.println(stub_invoke1(&mut s, "fetch", 7));  // Ok(100)
  io.println(stub_invoke2(&mut s, "put", 1, 2)); // Err("disk full")
  io.println(stub_invoke0(&mut s, "log"));       // Ok(0)

  io.println(stub_verified(&s));                 // true
  io.println(stub_report(&s));                   // "" -- no violations
  return 0;
}
```

## Install

```
xiom pkg install xiom.stub@0.1.0     # consumer (available once published)
xiom pkg publish                     # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.stub
```

Expected tail: 22 `[PASS]` lines, `xiom.stub: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- Explicit calls only: no interception, no runtime hooks, no reflection, no
  FFI. The code under test must call the stub through recorded helper code.
- Argument matchers are exact Int tuples of arity 0 to 3; there are no
  wildcards, ranges or f64/Str/Bool arguments.
- An at-least expectation never stops accepting calls, so a later
  expectation with the same matcher is unreachable; declare specific
  matchers before general ones.
- Out-of-order detection is per call: a call that binds to expectation `i`
  while any earlier `j < i` is unsatisfied is one violation.
- No concurrency: a stub is a mutable value, not a thread-safe service.
- Reports redact nothing: call arguments are rendered as decimal Ints.

See `SPEC.md` for exact semantics, the violation catalog and the test
matrix. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
