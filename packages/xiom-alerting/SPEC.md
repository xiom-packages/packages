# xiom.alerting -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.alerting` (`src/alerting.xi`). Pure XIOM, no FFI.

## 1. Scope

A deterministic threshold-alert state machine over caller-supplied integer
samples:

- a rule (`AlertRule`) fixes a threshold, a direction, and the number of
  consecutive breaching samples needed to fire,
- a state (`AlertState`) tracks the breach streak, the firing signal, and the
  lifetime fired/resolved edge counts,
- `alert_observe` advances the state by one sample and reports the fired edge,
- `alert_evaluate` folds a whole series into a fresh state,
- `alert_transition_count` counts fired edges across a series,
- accessors read the state (`alert_is_firing`, `alert_fired_count`,
  `alert_resolved_count`, `alert_breaches`).

## 2. Non-goals

- Time windows, rate/bucket aggregation, pending periods, or `for`/`unless`
  qualifiers.
- Multiple thresholds per rule, hysteresis bands, or composite expressions.
- Floats, labels, dimensions, grouping, deduplication, silencing.
- Persistence, serialization, notification, or acknowledgement.
- Clock access, schedulers, background collection, FFI, or global state.

## 3. Definitions

- **Breach.** A sample `value` breaches rule `r` when
  `r.above && value >= r.threshold`, or `!r.above && value <= r.threshold`.
  Equality is a breach in both directions.
- **Streak.** `breaches` is the number of consecutive breaching samples since
  the last non-breaching sample; it resets to 0 whenever a non-breaching
  sample arrives.
- **Fired edge.** The single `alert_observe` call on which `firing` changes
  from false to true; that call returns `true`.
- **Resolve edge.** The single `alert_observe` call on which `firing` changes
  from true to false, caused by a non-breaching sample; that call returns
  `false`.
- **Consecutive.** `r.consecutive` is clamped by `alert_rule_new` to be at
  least 1; a value of 0 or negative behaves exactly as 1.

## 4. State machine

States are `(firing, streak)`; a fresh state is `(false, 0)`. Columns are the
sample class; cells give the next state, counter changes, and return value of
`alert_observe`.

| Current | Breaching sample | Non-breaching sample |
|---|---|---|
| `(false, k)`, `k + 1 < consecutive` | `(false, k + 1)`; no counter change; returns `false` | `(false, 0)`; no counter change; returns `false` |
| `(false, consecutive - 1)` | `(true, consecutive)`; `fired_count += 1`; returns `true` (fired edge) | `(false, 0)`; no counter change; returns `false` |
| `(true, k)`, any `k >= consecutive` | `(true, k + 1)`; no counter change; returns `false` | `(false, 0)`; `resolved_count += 1`; returns `false` (resolve edge) |

Explicit edge semantics:

1. **Equality is a breach.** `value == threshold` breaches for `above=true`
   (`>=`) and for `above=false` (`<=`).
2. **Fire latches once per crossing.** While firing, further breaching samples
   only grow the streak; no additional fired edges are produced until a
   non-breaching sample resolves the alert.
3. **Resolve counts once.** Only the transition out of firing increments
   `resolved_count`; subsequent non-breaching samples change nothing.
4. **Resolve clears the streak.** A resolved alert must accumulate the full
   `consecutive` run again before re-firing.
5. **No-breach while clear is a no-op.** A non-breaching sample while not
   firing sets the streak to 0 (already 0 or a partial run is discarded).
6. **Pure.** `alert_observe` reads the rule only; it never mutates it. All
   functions are deterministic: the same rule and series always yield the same
   state and edge count.

## 5. API signatures

```xi
pub type AlertRule = { threshold: Int; above: Bool; consecutive: Int; }
pub type AlertState = { breaches: Int; firing: Bool; fired_count: Int; resolved_count: Int; }

pub fn alert_rule_new(threshold: Int, above: Bool, consecutive: Int) -> AlertRule
pub fn alert_state_new() -> AlertState
pub fn alert_observe(r: &AlertRule, s: &mut AlertState, value: Int) -> Bool
pub fn alert_evaluate(r: &AlertRule, values: &Vec[Int]) -> AlertState
pub fn alert_is_firing(s: &AlertState) -> Bool
pub fn alert_fired_count(s: &AlertState) -> Int
pub fn alert_resolved_count(s: &AlertState) -> Int
pub fn alert_breaches(s: &AlertState) -> Int
pub fn alert_transition_count(r: &AlertRule, values: &Vec[Int]) -> Int
```

`alert_observe` is O(1); `alert_evaluate` and `alert_transition_count` are
O(n) in the series length; everything else is O(1). `AlertRule` holds no
`Vec`, so a rule can be created and dropped at will; `AlertState` is a plain
value the caller copies or stores as needed.

## 6. Test plan

`tests/test_conformance.xi` (module `alerting_tests`) runs 21 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | rule_new fields | threshold/direction/streak stored verbatim |
| t2 | rule_new clamps | consecutive 0 and -7 become 1 |
| t3 | state_new | clear, zero streak, zero counters |
| t4 | consecutive=1 | first breach fires; edge returned exactly once |
| t5 | consecutive=3 | fires on the third consecutive breach, not before |
| t6 | streak reset | a non-breach in a partial run prevents firing |
| t7 | resolve | first clear sample resolves once and clears the streak |
| t8 | re-fire | a new run after a resolve is a new fired edge |
| t9 | still firing | breaching samples while firing grow the streak only |
| t10 | above=false | breaches on values at or below the threshold |
| t11 | equality (above) | `value == threshold` fires with `above=true` |
| t12 | equality (below) | `value == threshold` fires with `above=false` |
| t13 | clamp 0 | consecutive=0 behaves as 1 |
| t14 | clamp negative | consecutive=-3 behaves as 1 |
| t15 | evaluate mixed | `[5,11,12,3,20,21,1]`, consecutive=2 => fired 2, resolved 2, breaches 0; 2 transitions |
| t16 | empty series | fresh state, no edges |
| t17 | all-breaching | 5 samples => fired 1, resolved 0, breaches 5, still firing; 1 transition |
| t18 | all-clear | 5 samples => all counters 0; 0 transitions |
| t19 | extremes | threshold 1e9 and -1e9 compare exactly |
| t20 | accessors | firing/fired/resolved/breaches report the final state |
| t21 | transition count | `[10,0,10,4,10]`, consecutive=1 => 3 edges |

Test helpers wrap the `&`-based read accessors in `&mut`-taking helpers so a
`&local` read call is never followed by a `&mut local` call in the same test
body (advisory E001); no `Str` comparison, `match`, or `Vec[StructType]` is
needed anywhere in the suite.

## 7. Compiler / stdlib notes

No compiler workarounds were required beyond the documented v0.61.x
constraints: free functions only, no methods on the structs, and typed
`let v: Int = values[i];` element reads for the `Vec[Int]` folds. The module
imports nothing; the suite uses `xiom.test` and `xiom.io` only. Verified with
`.\scripts\port.ps1 -Package xiom.alerting` (v0.61.3).
