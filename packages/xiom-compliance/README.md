# xiom.compliance

> **Status:** `incubating` -- conformance-tested (22/22); not yet published on the XIOM registry.
> **Scope:** deterministic compliance rule engine: typed evidence attributes, predicate rule sets, expiring waivers, severity rollup and a canonical text findings report.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_compare`/`byte_at`/`str_slice`/`str_starts_with`/`str_contains` and `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.compliance` evaluates a compliance **rule set** against an **evidence**
record and produces one **finding** per rule: `pass`, `violation`, `waived` or
`not-applicable`. A rule is a typed predicate over a named attribute:

- integer attributes: `eq`, `neq`, inclusive `in-range`;
- string attributes: byte-exact `eq`, `neq`, `prefix`, `contains`.

Nothing is hidden: severities (`info`..`critical`), waivers with an explicit
expiry tick, counts per outcome and per severity, integer risk scores, and a
canonical LF-joined report. There are no floats, no clocks, no FFI and no
global state; the caller supplies the evaluation tick, so a run is fully
deterministic and reproducible from its inputs.

## API

Constants (all `Int`):

| Constant | Value | Meaning |
|---|---|---|
| `CMPL_INT` / `CMPL_STR` | 0 / 1 | predicate subject kind: integer / string attribute |
| `CMPL_OP_INT_EQ` / `CMPL_OP_INT_NEQ` / `CMPL_OP_INT_RANGE` | 0 / 1 / 2 | integer predicate operators |
| `CMPL_OP_STR_EQ` / `CMPL_OP_STR_NEQ` / `CMPL_OP_STR_PREFIX` / `CMPL_OP_STR_CONTAINS` | 0 / 1 / 2 / 3 | string predicate operators |
| `CMPL_PASS` / `CMPL_VIOLATION` / `CMPL_WAIVED` / `CMPL_NOT_APPLICABLE` | 0 / 1 / 2 / 3 | finding outcomes |
| `CMPL_SEV_INFO` .. `CMPL_SEV_CRITICAL` | 0 .. 4 | severity scale |

Types:

| Type | Description |
|---|---|
| `RuleSet` | nine index-aligned parallel vectors, one slot per rule (`ids`, `severities`, `subjects`, `attrs`, `ops`, `int_a`, `int_b`, `strs`, `enabled`) |
| `Evidence` | four index-aligned parallel vectors: `names`, `kinds`, `ints`, `strs` (first-match by name) |
| `WaiverSet` | `rule_ids` and `expiry_ticks`, parallel, duplicates kept |
| `Findings` | four index-aligned parallel vectors, one finding per rule: `rule_ids`, `severities`, `outcomes`, `details` |

Functions:

| Function | Returns | Description |
|---|---|---|
| `cmpl_pred_int(op, a, b, value)` | `Bool` | Integer predicate: `eq` (`value == a`), `neq`, inclusive `range` (`a <= value <= b`); unknown op false. |
| `cmpl_pred_str(op, operand, value)` | `Bool` | String predicate: byte-exact `eq`/`neq`, `prefix`, `contains`; unknown op false. |
| `cmpl_rules_new()` | `RuleSet` | Empty rule set. |
| `cmpl_rule_int(s, id, sev, attr, op, a, b)` | `Int` | Append and enable an integer rule; returns its index. |
| `cmpl_rule_str(s, id, sev, attr, op, operand)` | `Int` | Append and enable a string rule; returns its index. |
| `cmpl_rule_count(s)` | `Int` | Rule count (shortest of the nine vectors). |
| `cmpl_rule_id(s, i)` / `cmpl_rule_severity(s, i)` / `cmpl_rule_subject(s, i)` | `Str` / `Int` / `Int` | Rule fields; sentinels `""` / `-1` / `-1` out of range. |
| `cmpl_rule_is_enabled(s, i)` | `Bool` | Enabled state; false out of range. |
| `cmpl_rule_set_enabled(s, i, on)` | `Bool` | Write `enabled[i]`; false (no-op) out of range. |
| `cmpl_evidence_new()` | `Evidence` | Empty evidence record. |
| `cmpl_evidence_put_int(e, name, value)` | `Int` | Append an integer attribute; returns its index. |
| `cmpl_evidence_put_str(e, name, value)` | `Int` | Append a string attribute; returns its index. |
| `cmpl_evidence_count(e)` | `Int` | Attribute count (shortest of the four vectors). |
| `cmpl_evidence_has(e, name)` | `Bool` | Byte-exact first-match presence. |
| `cmpl_evidence_kind(e, name)` | `Int` | `CMPL_INT`, `CMPL_STR`, or `-1` when absent. |
| `cmpl_evidence_int(e, name, fallback)` / `cmpl_evidence_str(e, name, fallback)` | `Int` / `Str` | Typed first-match value, or fallback when absent/wrong kind. |
| `cmpl_waivers_new()` | `WaiverSet` | Empty waiver set. |
| `cmpl_waive(w, rule_id, expiry_tick)` | `Int` | Append a waiver entry; returns its index. |
| `cmpl_waiver_count(w)` | `Int` | Waiver entry count. |
| `cmpl_waiver_active(w, rule_id, now)` | `Bool` | True when any entry for `rule_id` has `expiry_ticks[i] > now`. |
| `cmpl_eval(s, e, w, now)` | `Findings` | Evaluate all rules into one finding each, in rule order. |
| `cmpl_findings_len(f)` | `Int` | Finding count (shortest of the four vectors). |
| `cmpl_finding_rule(f, i)` / `cmpl_finding_severity(f, i)` / `cmpl_finding_outcome(f, i)` / `cmpl_finding_detail(f, i)` | `Str` / `Int` / `Int` / `Str` | Finding fields; sentinels out of range. |
| `cmpl_count(f, outcome)` | `Int` | Findings with that outcome. |
| `cmpl_severity_count(f, outcome, severity)` | `Int` | Findings with both outcome and severity. |
| `cmpl_is_compliant(f)` | `Bool` | True when `cmpl_count(f, CMPL_VIOLATION) == 0`. |
| `cmpl_severity_weight(sev)` | `Int` | `1, 2, 4, 8, 16` for info..critical; `0` otherwise. |
| `cmpl_risk_score(f)` | `Int` | Sum of weights over violations only. |
| `cmpl_waived_score(f)` | `Int` | Sum of weights over waived findings. |
| `cmpl_severity_name(sev)` / `cmpl_outcome_name(outcome)` | `Str` | Canonical lowercase names; `"unknown"` for other codes. |
| `cmpl_report(f)` | `Str` | Canonical LF-joined findings report. |

## Usage

```xi
use xiom.compliance;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  var rules = cmpl_rules_new();
  cmpl_rule_int(&mut rules, "G-AGE", CMPL_SEV_HIGH, "age", CMPL_OP_INT_RANGE, 18, 120);
  cmpl_rule_str(&mut rules, "G-REGION", CMPL_SEV_MEDIUM, "region", CMPL_OP_STR_EQ, "EU");

  var ev = cmpl_evidence_new();
  cmpl_evidence_put_int(&mut ev, "age", 30);
  cmpl_evidence_put_str(&mut ev, "region", "US");

  var waivers = cmpl_waivers_new();
  cmpl_waive(&mut waivers, "G-REGION", 1000);   // covered until tick 1000

  let f = cmpl_eval(&rules, &ev, &waivers, 42);
  io.println(cmpl_report(&f));
  // compliance-report v1
  // findings=2 pass=1 violation=0 waived=1 not-applicable=0
  // violations critical=0 high=0 medium=0 low=0 info=0 other=0
  // score=0 waived_score=4
  // 0|G-AGE|high|pass|age
  // 1|G-REGION|medium|waived|region
  io.println("risk " + convert.int_to_string(cmpl_risk_score(&f)));
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.compliance
```

Expected tail: 22 `[PASS]` lines, `xiom.compliance: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Not a legal or regulatory instrument.** This is a deterministic rule
  evaluator; it does not implement any specific regulation, does not interpret
  one, and passing it is not certification. Rule content and severities are
  entirely caller-defined.
- **Waivers are bookkeeping, not approvals.** A waiver entry silences a
  finding (`waived`) but carries no identity, evidence, reason or signature;
  it is not an authorization and nothing here authenticates who granted it.
- **No clock, no persistence, no concurrency.** `now` is a caller-supplied
  integer tick; the engine never reads a clock. Records live in memory only;
  the caller persists and synchronizes them.
- **First-match attribute lookup.** Duplicate attribute names are kept and the
  first entry wins; duplicate rules and waivers are never collapsed.
- **Severity codes outside 0..4 are tolerated, not validated**: they are
  rendered as `unknown`, counted in the report's `other` bucket, and weigh 0.
- **Report escaping is minimal**, same grammar as `xiom.audit` export: LF ->
  `\n`, `|` -> `\|`; backslashes are literal.
- **No floats.** All scoring is integer; weights are the fixed powers of two
  documented above.

See `SPEC.md` for the precise semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
