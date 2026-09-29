# xiom.mock -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.mock` (`src/mock.xi`). Pure XIOM, no FFI, no runtime hooks.

## 1. Scope

Deterministic test doubles as plain values:

- `mock_new` builds an empty mock;
- `mock_expect`, `mock_expect_at_least`, `mock_expect_at_most` declare named
  expectations with a cardinality, validating input;
- `mock_record` logs calls and updates the matching expectation, if any;
- accessors expose the expectation table, the call log and the unexpected
  calls;
- `mock_verified` / `mock_unmet_count` / `mock_verify_message` verify;
- `mock_reset` and `mock_clear` reuse or discard a mock.

Only the `expect`, `record` and `verify` branches of the package's placeholder
inventory are implemented.

## 2. Non-goals

- **No interception**: the code under test must call the mock explicitly;
  there are no runtime hooks, patching, vtables or FFI.
- **No argument matching**: `args` is opaque text for logging; dispatch is by
  name only.
- **No ordering constraints**: expected-call sequences are not modelled
  (checks are counts, not chains).
- **No concurrency**: a mock is a mutable value, not a thread-safe service.
- **No return-value stubbing**: this package records and verifies; canned
  responses belong to the separate `xiom.stub` placeholder.
- No FFI, no file I/O, no registry integration; in-memory only.

## 3. Data model

```xi
pub type Mock = {
  names: Vec[Str];            // expectation names, declaration order
  modes: Vec[Int];            // 0 exactly, 1 at least, 2 at most
  expected: Vec[Int];         // declared counts (>= 0)
  actual: Vec[Int];           // matched call counts
  call_names: Vec[Str];       // every recorded call, in order
  call_args: Vec[Str];        // its args text
  unexpected_names: Vec[Str]; // calls matching no expectation, in order
  unexpected_args: Vec[Str];
}
```

The four expectation vectors are index-aligned, as are the two call vectors
and the two unexpected vectors. Every accessor clamps to the shortest
relevant array, so a hand-built `Mock` cannot be read out of range.

## 4. Semantics

1. **Declaration.** Each `mock_expect*` appends one expectation with mode
   `0` (exactly), `1` (at least) or `2` (at most) and the declared count.
   `Ok(index)` returns its declaration index.
2. **Validation.** A declaration fails with `Err` when the name is empty,
   `times < 0`, or the name already exists (case-sensitive). A failed
   declaration never mutates the mock.
3. **Recording.** `mock_record` always appends to the call log. If the name
   matches an expectation (first match, case-sensitive), that expectation's
   actual count grows by 1; otherwise the call is also appended to the
   unexpected lists. Recording is never rejected, even for an empty name.
4. **Cardinality.** Expectation `i` is met when:
   mode `0`: `actual == expected`; mode `1`: `actual >= expected`;
   mode `2`: `actual <= expected`.
5. **Verification.** `mock_verified` is true when every expectation is met.
   `mock_unmet_count` counts unmet expectations. `mock_verify_message`
   returns the first unmet expectation in declaration order as
   `mock: unmet expectation '<name>': expected <mode> <n>, got <m>` and `""`
   when all are met.
6. **Unexpected calls.** They never make `mock_verified` false;
   `mock_unexpected_count`, the positional accessors and
   `mock_unexpected_message` (first entry, `mock: unexpected call '<name>'`)
   report them.
7. **Reset.** `mock_reset` clears the call log, the unexpected lists and all
   actual counts, keeping the declared expectations. `mock_clear` clears
   everything, making the value equivalent to `mock_new()`.
8. **Determinism.** All operations are pure state transitions over the
   public vectors; the same call sequence always produces the same results.

## 5. Error catalog

| Condition | Exact message |
|---|---|
| Expectation name is `""` | `mock: empty name` |
| `times < 0` | `mock: negative times <n>` |
| The name is already declared | `mock: duplicate expectation '<name>'` |

Verification and unexpected-call messages are data, not errors; `mock_record`
has no error path.

## 6. API contract

```xi
pub fn mock_new() -> Mock
pub fn mock_expect(m: &mut Mock, name: Str, times: Int) -> Result[Int, Str]
pub fn mock_expect_at_least(m: &mut Mock, name: Str, times: Int) -> Result[Int, Str]
pub fn mock_expect_at_most(m: &mut Mock, name: Str, times: Int) -> Result[Int, Str]
pub fn mock_record(m: &mut Mock, name: Str, args: Str)
pub fn mock_call_total(m: &Mock) -> Int
pub fn mock_call_name(m: &Mock, i: Int) -> Str
pub fn mock_call_args(m: &Mock, i: Int) -> Str
pub fn mock_call_count(m: &Mock, name: Str) -> Int
pub fn mock_unexpected_count(m: &Mock) -> Int
pub fn mock_unexpected_name(m: &Mock, i: Int) -> Str
pub fn mock_unexpected_args(m: &Mock, i: Int) -> Str
pub fn mock_unexpected_message(m: &Mock) -> Str
pub fn mock_expectation_count(m: &Mock) -> Int
pub fn mock_expectation_index(m: &Mock, name: Str) -> Int
pub fn mock_mode(m: &Mock, name: Str) -> Int
pub fn mock_expected(m: &Mock, name: Str) -> Int
pub fn mock_actual(m: &Mock, name: Str) -> Int
pub fn mock_unmet_count(m: &Mock) -> Int
pub fn mock_verified(m: &Mock) -> Bool
pub fn mock_verify_message(m: &Mock) -> Str
pub fn mock_reset(m: &mut Mock)
pub fn mock_clear(m: &mut Mock)
```

Out-of-range positional accessors return `""`; unknown-name lookups return
`-1` (`mock_expectation_index`, `mock_mode`, `mock_expected`,
`mock_actual`). Complexity: declarations and name lookups are
O(expectations); recording and call counting are O(calls) / O(expectations);
everything else is O(1) except the aggregate checks, which are
O(expectations).

## 7. Test matrix

`tests/test_conformance.xi` (module `mock_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All string comparisons go through `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | fresh mock | section 3 |
| t2 | exactly-N met | rule 4, 5 |
| t3 | exactly-N too few | rule 5 |
| t4 | exactly-N too many | rule 5 |
| t5 | at-least-N | rule 4 |
| t6 | at-most-N | rule 4 |
| t7 | declaration validation | rule 2, section 5 |
| t8 | unexpected recording | rule 3, 6 |
| t9 | call_count vs actual | rule 3 |
| t10 | reset keeps expectations | rule 7 |
| t11 | clear drops everything | rule 7 |
| t12 | call log order and args | rule 3 |
| t13 | unknown-name accessors | section 6 |
| t14 | case sensitivity | rule 2, 3 |
| t15 | first unmet in order | rule 5 |
| t16 | unexpected accessors | rule 6 |
| t17 | all three modes together | rule 4 |
| t18 | reset and replay | rule 7 |
| t19 | expectations-free verification | rule 5, 6 |
| t20 | modes and indexes | section 3, 6 |

## 8. Known limitations

- No call interception or return-value stubbing; recording is explicit.
- No argument matchers, wildcards or ordering constraints.
- Unexpected calls do not fail verification by themselves.
- One mock models counts only; per-call metadata beyond name and args is not
  captured.
- A hand-built `Mock` with mismatched parallel arrays is clamped, not
  repaired.

## 9. Compiler / stdlib notes (v0.62.1)

Free functions only; flat parallel `Vec`s instead of `Vec[StructType]`;
`Result` construction confined to the leaf helpers `_ok_int` / `_err_int`;
every `Str` element read is bound to a typed local and compared with
`str_compare` (BUG 17). Mutating functions take `&mut Mock` and are called
with an explicit `&mut` at every call site. `mock_reset` and `mock_clear`
reassign whole `Vec` fields through the mutable reference, the pattern
already proven in `xiom.ini`. The suite is green on v0.62.1 with
`program_exit=0`.
