# xiom.compliance -- API specification

Module `xiom.compliance`. Pure XIOM, no FFI. Dependency: `xiom.std >=0.60.0
<1.0.0` (`xiom.string`, `xiom.convert`). Every function is a free function,
every record is a flat set of parallel `Vec`s, and every loop is bounded by a
vector length, so evaluation terminates in time linear in the input sizes.

This document is the normative description of the behavior implemented in
`src/compliance.xi` and exercised by `tests/test_conformance.xi` (22 checks).

## 1. Constants

Subject kinds:

| Name | Value | Meaning |
|---|---|---|
| `CMPL_INT` | 0 | the predicate reads an integer attribute |
| `CMPL_STR` | 1 | the predicate reads a string attribute |

Integer predicate operators:

| Name | Value | Semantics (`value` = attribute value) |
|---|---|---|
| `CMPL_OP_INT_EQ` | 0 | `value == int_a[i]` |
| `CMPL_OP_INT_NEQ` | 1 | `value != int_a[i]` |
| `CMPL_OP_INT_RANGE` | 2 | `int_a[i] <= value <= int_b[i]` (inclusive both ends) |

String predicate operators (`operand` = `strs[i]`):

| Name | Value | Semantics |
|---|---|---|
| `CMPL_OP_STR_EQ` | 0 | byte-exact `value == operand` (`str_compare == 0`) |
| `CMPL_OP_STR_NEQ` | 1 | byte-exact `value != operand` |
| `CMPL_OP_STR_PREFIX` | 2 | `value` starts with `operand` |
| `CMPL_OP_STR_CONTAINS` | 3 | `value` contains `operand` |

Finding outcomes:

| Name | Value | Meaning |
|---|---|---|
| `CMPL_PASS` | 0 | enabled, predicate satisfied |
| `CMPL_VIOLATION` | 1 | enabled, predicate not satisfied, no active waiver |
| `CMPL_WAIVED` | 2 | enabled, predicate not satisfied, active waiver for the rule id |
| `CMPL_NOT_APPLICABLE` | 3 | disabled rule, attribute missing, or attribute kind mismatch |

Severity scale:

| Name | Value | Weight | Name string |
|---|---|---|---|
| `CMPL_SEV_INFO` | 0 | 1 | `info` |
| `CMPL_SEV_LOW` | 1 | 2 | `low` |
| `CMPL_SEV_MEDIUM` | 2 | 4 | `medium` |
| `CMPL_SEV_HIGH` | 3 | 8 | `high` |
| `CMPL_SEV_CRITICAL` | 4 | 16 | `critical` |

Any other severity code is accepted, rendered as `unknown`, counted in the
report's `other` bucket, and weighs 0.

## 2. Records

### 2.1 `RuleSet`

Nine parallel vectors; rule `i` is the tuple

```
(ids[i], severities[i], subjects[i], attrs[i], ops[i],
 int_a[i], int_b[i], strs[i], enabled[i])
```

- `subjects[i]` is `CMPL_INT` or `CMPL_STR` and selects the predicate family:
  integer rules read `ops[i]` as `CMPL_OP_INT_*` and use `int_a[i]`,
  `int_b[i]`; string rules read `ops[i]` as `CMPL_OP_STR_*` and use
  `strs[i]`. The unused operands are stored as `0` / `""`.
- `enabled[i]` is `1` (enabled) or `0` (disabled); constructors always write
  `1`.
- Invariant: all nine vectors have the same length; `cmpl_rule_int`,
  `cmpl_rule_str` and `cmpl_rule_set_enabled` preserve it. As a defensive
  guard, every read operation uses `cmpl_rule_count(s)` = the **shortest** of
  the nine vectors, so hand-drifted records can never be overrun.

### 2.2 `Evidence`

Four parallel vectors; attribute `i` is

```
(names[i], kinds[i], ints[i], strs[i])
```

- `kinds[i]` is `CMPL_INT` or `CMPL_STR`; the unused typed slot stores `0`
  or `""`.
- Lookup is **first-match by byte-exact name** (`str_compare == 0`).
  Duplicate names are kept; the first entry always wins.
- Invariant: all four vectors are the same length; reads use the shortest.

### 2.3 `WaiverSet`

Two parallel vectors, entries `(rule_ids[j], expiry_ticks[j])`. Duplicates are
kept. Reads use the shortest of the two vectors.

### 2.4 `Findings`

Four parallel vectors, one entry per evaluated rule, in rule order:

```
(rule_ids[i], severities[i], outcomes[i], details[i])
```

`details[i]` is the examined attribute name, or `""` for a disabled rule.
Built only by `cmpl_eval`, which pushes to all four vectors in the same
iteration; reads use the shortest of the four vectors.

## 3. Predicates

### 3.1 `cmpl_pred_int(op, a, b, value) -> Bool`

- `CMPL_OP_INT_EQ`: `value == a`.
- `CMPL_OP_INT_NEQ`: `value != a`.
- `CMPL_OP_INT_RANGE`: `a <= value <= b`, inclusive on both bounds; a
  degenerate range (`a == b`) matches exactly `a`; `a > b` matches nothing.
- Any other `op`: `false`. `b` is ignored by EQ/NEQ. Negative values and
  negative bounds are ordinary integers (two's-complement `Int`, no wrapping
  arithmetic in the predicate).

### 3.2 `cmpl_pred_str(op, operand, value) -> Bool`

- `CMPL_OP_STR_EQ` / `CMPL_OP_STR_NEQ`: byte-exact via
  `xiom.string.str_compare`; comparison is case-sensitive and UTF-8 byte
  based, never locale aware.
- `CMPL_OP_STR_PREFIX`: `value` starts with `operand`.
- `CMPL_OP_STR_CONTAINS`: `value` contains `operand`.
- Empty `operand` is handled directly, without calling the stdlib:
  `PREFIX` and `CONTAINS` are `true` for every `value`, `EQ` is `true` only
  for an empty `value`, `NEQ` is its negation, any other `op` is `false`.
  (This also avoids `xiom.string.index_of`'s `substr.len() > 0` contract,
  which `xiom.string.str_contains` would otherwise trip for an empty needle.)
- Any unknown `op`: `false`.

Neither predicate ever errors; failures are encoded as `false`.

## 4. Construction API

| Function | Returns | Contract |
|---|---|---|
| `cmpl_rules_new()` | `RuleSet` | nine empty vectors |
| `cmpl_rule_int(s, id, sev, attr, op, a, b)` | `Int` | pushes one aligned slot (subject `CMPL_INT`, operand `strs` = `""`, enabled 1); returns `count - 1` |
| `cmpl_rule_str(s, id, sev, attr, op, operand)` | `Int` | pushes one aligned slot (subject `CMPL_STR`, `int_a` = `int_b` = 0, enabled 1); returns `count - 1` |
| `cmpl_rule_count(s)` / `cmpl_rule_id(s,i)` / `cmpl_rule_severity(s,i)` / `cmpl_rule_subject(s,i)` / `cmpl_rule_is_enabled(s,i)` | `Int` / `Str` / `Int` / `Int` / `Bool` | shortest-vector count; sentinels out of range: `0`, `""`, `-1`, `-1`, `false` |
| `cmpl_rule_set_enabled(s, i, on)` | `Bool` | writes `enabled[i]` only; returns `false` (no-op) for `i < 0` or `i >= count` |
| `cmpl_evidence_new()` | `Evidence` | four empty vectors |
| `cmpl_evidence_put_int(e, name, value)` / `cmpl_evidence_put_str(e, name, value)` | `Int` | pushes one aligned, typed slot; returns `count - 1` |
| `cmpl_evidence_count(e)` / `cmpl_evidence_has(e,name)` / `cmpl_evidence_kind(e,name)` | `Int` / `Bool` / `Int` | shortest-vector count; first-match presence; `CMPL_INT`/`CMPL_STR`/`-1` |
| `cmpl_evidence_int(e, name, fallback)` / `cmpl_evidence_str(e, name, fallback)` | `Int` / `Str` | first-match value, or `fallback` when absent or of the wrong kind |
| `cmpl_waivers_new()` | `WaiverSet` | two empty vectors |
| `cmpl_waive(w, rule_id, expiry_tick)` | `Int` | pushes one aligned entry; returns `count - 1` |
| `cmpl_waiver_count(w)` | `Int` | shortest-vector count |

All constructors are append-only, O(1) amortized, and never collapse, sort or
reorder entries. Rule ids and attribute names are opaque byte strings; rule
ids may repeat (each rule still produces its own finding).

## 5. Evaluation

`cmpl_eval(s, e, w, now) -> Findings` iterates `i` over
`0 .. cmpl_rule_count(s) - 1` and emits exactly one finding per rule, pushing
to all four findings vectors in the same iteration (index alignment is an
invariant of the implementation). The outcome for rule `i`:

1. `enabled[i] == 0` -> `CMPL_NOT_APPLICABLE`, detail `""`.
2. attribute `attrs[i]` absent from `e` -> `CMPL_NOT_APPLICABLE`,
   detail `attrs[i]`.
3. `e.kinds[at] != subjects[i]` (kind mismatch) -> `CMPL_NOT_APPLICABLE`,
   detail `attrs[i]`.
4. predicate satisfied (Section 3) -> `CMPL_PASS`, detail `attrs[i]`.
5. predicate not satisfied and `cmpl_waiver_active(w, ids[i], now)` ->
   `CMPL_WAIVED`, detail `attrs[i]`.
6. predicate not satisfied and no active waiver -> `CMPL_VIOLATION`,
   detail `attrs[i]`.

`severities[i]` is copied from the rule verbatim; the severity is never
consulted by evaluation, only by aggregation.

The result depends only on the inputs, not on evaluation order or on the
history of the records. A disabled rule is reported (not skipped) so the
findings vector stays index-aligned with the rule set.

## 6. Waivers

`cmpl_waiver_active(w, rule_id, now) -> Bool` is true iff some entry `j` in
`0 .. cmpl_waiver_count(w) - 1` satisfies:

```
str_compare(w.rule_ids[j], rule_id) == 0  &&  now < w.expiry_ticks[j]
```

- **Expiry is exclusive**: a waiver with `expiry_ticks[j] == now` is already
  expired; it is active for all ticks strictly below its expiry tick.
- Matching is byte-exact, so `R-1` never covers `R-10`.
- Multiple entries for the same rule id are allowed; the rule is waived when
  **any** of them is active, so an expired duplicate can never mask an active
  one.
- Expiry ticks are plain `Int`s; negative ticks and negative "now" behave as
  ordinary integers (a waiver with expiry `<= now` is inactive).
- Waivers never change the outcome of a satisfied rule and never turn a
  violation into a pass; they only relabel it `CMPL_WAIVED`.

## 7. Aggregation

For a `Findings` record `f` (all formulas use `cmpl_findings_len(f)` as the
iteration bound; out-of-range accessors return the sentinels of Section 4):

- `cmpl_count(f, outcome)` = number of `i` with `outcomes[i] == outcome`
  (any `Int` outcome code accepted; unknown codes count 0).
- `cmpl_severity_count(f, outcome, severity)` = number of `i` with both
  `outcomes[i] == outcome` and `severities[i] == severity`.
- `cmpl_is_compliant(f)` = `cmpl_count(f, CMPL_VIOLATION) == 0`. Waived and
  not-applicable findings do not affect compliance.
- `cmpl_severity_weight(sev)` = 1, 2, 4, 8, 16 for severities 0..4; 0 for any
  other code.
- `cmpl_risk_score(f)` = sum of `cmpl_severity_weight(severities[i])` over
  `outcomes[i] == CMPL_VIOLATION` only. Waived findings are excluded by
  design, so a waiver never hides risk implicitly -- the waived weight is
  reported separately.
- `cmpl_waived_score(f)` = sum of `cmpl_severity_weight(severities[i])` over
  `outcomes[i] == CMPL_WAIVED` only.
- `cmpl_severity_name(sev)` / `cmpl_outcome_name(outcome)` = the canonical
  lowercase names of Sections 1; `"unknown"` for any other code.

All scores are non-negative integers; there is no floating point anywhere.

## 8. Canonical report

`cmpl_report(f) -> Str` returns the LF-joined text (no trailing LF):

```
compliance-report v1
findings=<n> pass=<p> violation=<v> waived=<w> not-applicable=<na>
violations critical=<c> high=<h> medium=<m> low=<l> info=<i> other=<o>
score=<s> waived_score=<ws>
<index>|<rule id>|<severity>|<outcome>|<detail>
... one line per finding, index 0, 1, ... <n>-1 ...
```

- `<n>` = `cmpl_findings_len(f)`; `<p>`, `<v>`, `<w>`, `<na>` =
  `cmpl_count` per outcome; `<s>` = risk score; `<ws>` = waived score.
- `<c>`..`<i>` = `cmpl_severity_count(f, CMPL_VIOLATION, ...)` for
  critical/high/medium/low/info; `<o>` = `<v>` minus the sum of those five
  counts (violations whose severity is outside 0..4).
- Each finding line uses the finding's index (`convert.int_to_string`), the
  escaped rule id, `cmpl_severity_name`, `cmpl_outcome_name` and the escaped
  detail.
- **Escaping** (identical grammar to `xiom.audit` export): LF becomes the two
  characters `\n`, `|` becomes `\|`; backslashes are not escaped. The report
  is field-parseable only when ids/details contain neither sequence; the
  header words are fixed literals.
- An empty findings record produces exactly:

```
compliance-report v1
findings=0 pass=0 violation=0 waived=0 not-applicable=0
violations critical=0 high=0 medium=0 low=0 info=0 other=0
score=0 waived_score=0
```

`cmpl_report` is a pure function of `f`: identical findings produce
byte-identical reports (conformance check 17).

## 9. Determinism and termination

- No clocks, randomness, FFI, I/O or global state: every function is a pure
  function of its arguments (mutations are explicit `&mut` writes).
- Every loop is bounded by the shortest relevant vector length or by a
  string's byte length; evaluation is O(rules x (attributes + waiver
  entries + text)) and the conformance suite terminates in well under a
  second on the pinned toolchain.
- Parallel vectors are pushed in lockstep and read through shortest-length
  guards, so drift (a hand-poped vector) can only shorten the effective
  record, never overrun it (conformance check 21).

## 10. Test plan (22 conformance checks)

| # | Area | What it pins |
|---|---|---|
| 1-2 | predicates | int and str operator matrices, inclusive bounds, case sensitivity, unknown ops |
| 3-5 | rules | empty set, sentinel accessors, aligned append in all nine vectors, enable/disable |
| 6 | empty eval | zero findings and the exact zeroed report |
| 7 | evidence | typed puts, first-match, kind mismatch fallbacks, `kind_of`, `has` |
| 8-10 | outcomes | pass / violation / waived paths with risk and waived scores |
| 11-12 | waivers | exclusive expiry, duplicates, eval boundary at `now == expiry` |
| 13 | not-applicable | missing attribute and kind mismatch, with detail names |
| 14 | report | exact canonical report for the mixed fixture |
| 15 | report | `|` -> `\|` and LF -> `\n` escaping in ids and details |
| 16 | aggregation | per-severity counts, `other` bucket, exact risk/waived rollup |
| 17 | determinism | two runs, byte-identical report and outcome sequence |
| 18 | compliance | violated-only semantics; waived-only record stays compliant |
| 19 | robustness | unknown op fails closed; unknown severity weighs 0 but is reported |
| 20 | scale | 100 rules x 60 attributes, aligned vectors, one pass |
| 21 | drift guard | shortest-vector counts for rules and findings |
| 22 | boundaries | negative ranges, degenerate range, empty operands, exact waiver ids |

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.compliance
```

Passing output ends with `xiom.compliance: all tests passed` and
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.
