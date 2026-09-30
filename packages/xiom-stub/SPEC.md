# xiom.stub -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.stub` (`src/stub.xi`). Pure XIOM, no FFI, no runtime hooks.

## 1. Scope

Ordered programmable test-double stubs as plain values:

- `stub_new` builds an empty, strict stub;
- `stub_expect{0..3}`, `stub_expect_at_least{0..3}`,
  `stub_expect_at_most{0..3}` and `stub_expect_fail{0..3}` declare ordered
  expectations (method, Int argument tuple, cardinality, canned return,
  optional failure message), validating input;
- `stub_invoke{0..3}` records every call, binds it to an expectation and
  returns the programmed response;
- accessors expose the expectation table, the numbered call log and the
  matched/unmatched accounting;
- `stub_verified`, `stub_violation_count`, `stub_verify_message`,
  `stub_report` and the per-category accessors verify;
- `stub_reset` and `stub_clear` reuse or discard a stub.

Only the `behavior` and `record` branches of the package's placeholder
inventory are implemented; there is no interception layer.

## 2. Non-goals

- **No interception**: the code under test must call the stub explicitly;
  there are no runtime hooks, patching, vtables or FFI.
- **No general matchers**: a matcher is an exact method name plus an exact
  Int tuple of arity 0 to 3; no wildcards, ranges or typed values beyond
  `Int`. The canned responses are `Int`/`Str` payloads only.
- **No concurrency**: a stub is a mutable value, not a thread-safe service.
- **No threads, no reflection, no file I/O, no registry integration**;
  in-memory only.
- **No automatic verification**: verification is an explicit call, never a
  destructor or process exit hook.

## 3. Data model

```xi
pub type Stub = {
  methods: Vec[Str];      // expectation method names, declaration order
  modes: Vec[Int];        // 0 exactly, 1 at least, 2 at most
  expected: Vec[Int];     // declared counts (>= 0)
  actual: Vec[Int];       // matched call counts
  returns: Vec[Int];      // canned return values
  fail_set: Vec[Int];     // 0 = success expectation, 1 = failure action
  fail_msgs: Vec[Str];    // failure message ("" when fail_set is 0)
  arg_off: Vec[Int];      // offset of each expectation's tuple in arg_data
  arg_len: Vec[Int];      // arity of each expectation (0..3)
  arg_data: Vec[Int];     // flat argument tuples
  call_methods: Vec[Str]; // every recorded call, in order
  call_off: Vec[Int];     // offset of each call's tuple in call_data
  call_len: Vec[Int];     // arity of each call
  call_data: Vec[Int];    // flat call argument tuples
  call_match: Vec[Int];   // bound expectation index, or -1
  ooo_seq: Vec[Int];      // out-of-order events: call sequence number
  ooo_taken: Vec[Int];    // the overtaken (unsatisfied, earlier) expectation
  ooo_matched: Vec[Int];  // the expectation the call bound to
  extra_seq: Vec[Int];    // unexpected calls: sequence number
  extra_kind: Vec[Int];   // 0 = no matcher at all, 1 = matcher exhausted
  extra_expect: Vec[Int]; // exhausted expectation index (kind 1), else -1
  lenient: Int;           // 0 = strict (default), 1 = lenient
}
```

The nine expectation arrays are index-aligned in declaration order; the
five call arrays are index-aligned in call order. The `ooo_*` and `extra_*`
triples are appended only when the corresponding violation is detected, in
call order. Every accessor clamps to the shortest relevant array, so a
hand-built `Stub` cannot be read out of range. A call's sequence number is
its zero-based position in the call log.

## 4. Semantics

1. **Declaration.** Each `stub_expect*` appends one expectation with mode
   `0` (exactly), `1` (at least) or `2` (at most), the declared count, the
   canned return value and the argument tuple. `stub_expect_fail*` appends
   an exactly-once expectation whose response is `Err(message)`
   (`fail_set = 1`). `Ok(index)` returns the declaration index.
2. **Validation.** A declaration fails with `Err` when the method is empty,
   `times < 0`, or a failure message is empty. A failed declaration never
   mutates the stub. Duplicate matchers are allowed (see rule 5).
3. **Met predicate.** Expectation `i` is met when: mode `0`:
   `actual == expected`; mode `1`: `actual >= expected`; mode `2`: always
   (`actual <= expected` holds by construction, see rule 4).
4. **Binding (first accept).** An invocation binds to the lowest-index
   expectation whose method equals the call method (case-sensitive) and
   whose argument tuple equals the call tuple (same arity, same values) and
   which still accepts a call. `exactly`/`at most` expectations accept
   while `actual < expected`; `at least` expectations always accept.
5. **Sequential responses.** Because binding is first-accept in declaration
   order, two expectations with the same matcher serve successive calls:
   the first fills up, then the second. An `at least` expectation never
   fills up, so a later expectation with the same matcher is unreachable;
   declare specific matchers before general ones.
6. **Invocation and response.** `stub_invoke{0..3}` always appends the call
   to the log, sets `call_match`, and when bound increments the
   expectation's `actual`. The return value is `Ok(returns[idx])` for a
   success expectation, `Err(fail_msgs[idx])` verbatim for a failure
   action. An unmatched call returns `Err` in strict mode and `Ok(0)` in
   lenient mode; either way it is recorded as an extra violation.
7. **Ordering rule.** After a call binds to expectation `i`, the event is
   out of order when some expectation `j < i` is unsatisfied at that
   moment. The lowest such `j` is recorded once per call as
   `(seq, j, i)`. Calls are still counted normally; the violation is an
   independent axis.
8. **Missing calls.** At verification time, every unsatisfied expectation
   (`exactly`/`at least` below its count) is a missing violation, in
   declaration order. `at most` expectations are never missing; surplus
   calls to their matcher appear as extra violations instead.
9. **Unexpected calls.** A call that binds to no accepting expectation is
   an extra violation. `extra_kind` is `0` when no expectation has the
   matcher at all, `1` when a matcher exists but its count is full
   (`extra_expect` names it).
10. **Verification.** `stub_verified` is true when there are no missing,
    extra or out-of-order violations. `stub_violation_count` is their sum.
    `stub_verify_message` returns the first violation in reporting order:
    missing (declaration order), then extra (call order), then
    out-of-order (call order); `""` when verified.
11. **Report.** `stub_report` returns `""` when verified, else a header
    `stub: <n> violation(s):` followed by one line per violation in the
    same reporting order, joined with `\n` and without a trailing newline.
12. **Reset.** `stub_reset` clears the call log, the bound matches, every
    violation and all actual counts (expectations stay declared).
    `stub_clear` clears everything, including the lenient flag, making the
    value equivalent to `stub_new()`.
13. **Determinism.** All operations are pure state transitions over the
    public vectors; the same call sequence always produces the same
    results.

## 5. Violation catalog

All messages start with `stub: `. Argument tuples render as `""` for arity
0, else `(a0)`, `(a0, a1)` or `(a0, a1, a2)` in decimal.

| Condition | Exact message |
|---|---|
| Unsatisfied expectation `i` | `stub: missing call '<m><args>': expected <mode> <n>, got <k>` |
| Unmatched call, no such matcher | `stub: unexpected call '<m><args>' (call #<seq>)` |
| Unmatched call, matcher exhausted | `stub: unexpected call '<m><args>' (call #<seq>): matching expectation #<i> is exhausted` |
| Call bound to `i` while `j < i` unsatisfied | `stub: out-of-order call '<m><args>' (call #<seq>): expectation #<j> '<m><args>' is still unsatisfied` |
| Report header | `stub: <n> violation(s):` |

`<mode>` is `exactly`, `at least` or `at most`. The strict-mode `Err` for
an unmatched call is exactly the corresponding unexpected-call message.

Declaration errors:

| Condition | Exact message |
|---|---|
| Method is `""` | `stub: empty method` |
| `times < 0` | `stub: negative times <n>` |
| `stub_expect_fail*` message is `""` | `stub: empty failure message` |

`stub: arity out of range <n>` exists as an internal guard; the public API
only exposes arities 0 to 3.

## 6. API contract

```xi
pub fn stub_new() -> Stub
pub fn stub_set_lenient(m: &mut Stub, on: Bool)
pub fn stub_is_lenient(m: &Stub) -> Bool
pub fn stub_expect0(m: &mut Stub, method: Str, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect1(m: &mut Stub, method: Str, a0: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect2(m: &mut Stub, method: Str, a0: Int, a1: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_at_least0(m: &mut Stub, method: Str, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_at_least1(m: &mut Stub, method: Str, a0: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_at_least2(m: &mut Stub, method: Str, a0: Int, a1: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_at_least3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_at_most0(m: &mut Stub, method: Str, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_at_most1(m: &mut Stub, method: Str, a0: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_at_most2(m: &mut Stub, method: Str, a0: Int, a1: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_at_most3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int, times: Int, returns: Int) -> Result[Int, Str]
pub fn stub_expect_fail0(m: &mut Stub, method: Str, message: Str) -> Result[Int, Str]
pub fn stub_expect_fail1(m: &mut Stub, method: Str, a0: Int, message: Str) -> Result[Int, Str]
pub fn stub_expect_fail2(m: &mut Stub, method: Str, a0: Int, a1: Int, message: Str) -> Result[Int, Str]
pub fn stub_expect_fail3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int, message: Str) -> Result[Int, Str]
pub fn stub_invoke0(m: &mut Stub, method: Str) -> Result[Int, Str]
pub fn stub_invoke1(m: &mut Stub, method: Str, a0: Int) -> Result[Int, Str]
pub fn stub_invoke2(m: &mut Stub, method: Str, a0: Int, a1: Int) -> Result[Int, Str]
pub fn stub_invoke3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int) -> Result[Int, Str]
pub fn stub_expectation_count(m: &Stub) -> Int
pub fn stub_expect_method(m: &Stub, i: Int) -> Str
pub fn stub_expect_mode(m: &Stub, i: Int) -> Int
pub fn stub_expect_times(m: &Stub, i: Int) -> Int
pub fn stub_expect_actual(m: &Stub, i: Int) -> Int
pub fn stub_expect_return(m: &Stub, i: Int) -> Int
pub fn stub_expect_has_failure(m: &Stub, i: Int) -> Bool
pub fn stub_expect_failure(m: &Stub, i: Int) -> Str
pub fn stub_expect_arg_count(m: &Stub, i: Int) -> Int
pub fn stub_expect_arg(m: &Stub, i: Int, k: Int) -> Int
pub fn stub_expect_met(m: &Stub, i: Int) -> Bool
pub fn stub_call_total(m: &Stub) -> Int
pub fn stub_call_seq(m: &Stub, i: Int) -> Int
pub fn stub_call_method(m: &Stub, i: Int) -> Str
pub fn stub_call_arg_count(m: &Stub, i: Int) -> Int
pub fn stub_call_arg(m: &Stub, i: Int, k: Int) -> Int
pub fn stub_call_match(m: &Stub, i: Int) -> Int
pub fn stub_call_matched(m: &Stub, i: Int) -> Bool
pub fn stub_matched_count(m: &Stub) -> Int
pub fn stub_unmatched_count(m: &Stub) -> Int
pub fn stub_missing_count(m: &Stub) -> Int
pub fn stub_missing_index(m: &Stub, k: Int) -> Int
pub fn stub_missing_message(m: &Stub, k: Int) -> Str
pub fn stub_extra_count(m: &Stub) -> Int
pub fn stub_extra_call(m: &Stub, k: Int) -> Int
pub fn stub_extra_message(m: &Stub, k: Int) -> Str
pub fn stub_out_of_order_count(m: &Stub) -> Int
pub fn stub_out_of_order_call(m: &Stub, k: Int) -> Int
pub fn stub_out_of_order_expectation(m: &Stub, k: Int) -> Int
pub fn stub_out_of_order_message(m: &Stub, k: Int) -> Str
pub fn stub_violation_count(m: &Stub) -> Int
pub fn stub_verified(m: &Stub) -> Bool
pub fn stub_verify_message(m: &Stub) -> Str
pub fn stub_report(m: &Stub) -> Str
pub fn stub_reset(m: &mut Stub)
pub fn stub_clear(m: &mut Stub)
```

Out-of-range conventions: expectation accessors return `""`, `-1`, `0` or
`false` (per type) and never read out of bounds; call accessors do the same;
violation messages return `""`. `stub_unmatched_count` always equals
`stub_extra_count` and `stub_matched_count + stub_unmatched_count` equals
`stub_call_total`. Mutating functions take `&mut Stub` and require an
explicit `&mut` at every call site. Complexity: declarations, binding and
verification are O(expectations); the log accessors are O(1) except
`stub_matched_count`, which is O(calls).

## 7. Test matrix

`tests/test_conformance.xi` (module `stub_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All string comparisons go through `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | fresh stub | sections 3, 4.10 |
| t2 | exactly-N met, canned return | rules 1, 3, 6 |
| t3 | exactly-N too few | rules 3, 8, section 5 |
| t4 | exactly-N surplus | rules 4, 6, 9 |
| t5 | at-least accepts extras | rules 3, 4 |
| t6 | at-least too few | rule 8 |
| t7 | at-most caps; at-most 0 met | rules 3, 4, 8, 9 |
| t8 | sequential responses | rules 4, 5 |
| t9 | tuple matching and call accessors | rules 4, 6 |
| t10 | out-of-order detection | rule 7 |
| t11 | failure action verbatim | rule 6 |
| t12 | lenient vs strict | rule 6 |
| t13 | numbered call log | section 3, rule 6 |
| t14 | declaration validation | rule 2, section 5 |
| t15 | reset keeps expectations | rule 12 |
| t16 | clear returns to fresh | rule 12 |
| t17 | verify_message precedence | rule 10 |
| t18 | full structured report | rule 11, section 5 |
| t19 | matched/unmatched accounting | rules 6, 9 |
| t20 | expectation accessors and clamping | section 6 |
| t21 | reset clears violations; replay | rule 12 |
| t22 | arity-3 tuples and rendering | rules 4, 5, section 5 |

## 8. Known limitations

- No interception or automatic call capture; invocation is explicit.
- Matchers are exact Int tuples of arity 0 to 3; no other value types.
- An at-least expectation can shadow later same-matcher expectations.
- Out-of-order detection reports the lowest unsatisfied earlier
  expectation only; it does not compute an edit-distance minimal reorder.
- A hand-built `Stub` with mismatched parallel arrays is clamped, not
  repaired.
- Canned responses are a single `Int` value or a failure message; there is
  no response sequencing beyond same-matcher expectation order.

## 9. Compiler / stdlib notes (v0.62.1)

Free functions only; flat parallel `Vec`s instead of `Vec[StructType]`;
`Result` construction confined to the leaf helpers `_ok_int` / `_err_int`;
every `Str` element read is bound to a typed local and compared with
`str_compare` (BUG 17); `&mut` parameters are called with an explicit
`&mut` at every call site; `stub_reset` and `stub_clear` reassign whole
`Vec` fields through the mutable reference. Argument tuples are stored in a
single flat `Vec[Int]` with per-entry offset/length arrays, so no nested
vector types are needed. The suite is green on v0.62.1 with
`program_exit=0`.

## 10. Stdlib gaps observed while porting

Helpers that were hand-rolled because `xiom.std` has no equivalent:

- `xiom.convert`: no `bool_to_string`-style helper is needed by the library
  itself, but a generic line-joining helper (join a `Vec[Str]` with a
  separator) is missing from `xiom.string.join` for message building; the
  report builder concatenates manually.
- No `int_tuple` comparison/formatting helpers: tuple equality and
  rendering are built on the flat `Vec[Int]` layout.
- No `Vec[Int]` slice-equality helper: element-wise comparison is manual.
