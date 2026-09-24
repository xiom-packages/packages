# xiom.alerting

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** threshold alert rules with consecutive-breach streaks, a firing
> state machine, and lifetime transition counters.
> **Deps:** none (the library imports nothing; tests use `xiom.std` modules).

## What it is

`xiom.alerting` is a small, deterministic alert state machine. An `AlertRule`
is a threshold plus a direction (`above`) plus the number of consecutive
breaching samples needed to fire. An `AlertState` is the caller-owned state:
the current breach streak, whether the alert is firing, and how many times it
fired and resolved. The caller supplies every sample; there is no clock, no
I/O, no buffering, no FFI, and no global state.

The state machine is exactly two transitions:

- **fire** -- the streak reaches `consecutive` while not firing: `firing` goes
  true, `fired_count` grows by one, and `alert_observe` returns `true` (the
  fired edge) for that one sample;
- **resolve** -- the first non-breaching sample while firing: `fired_count`
  does not move, `resolved_count` grows by one, `firing` goes false, and the
  streak resets to 0.

## API

| Function | Returns | Description |
|---|---|---|
| `alert_rule_new(threshold, above, consecutive)` | `AlertRule` | New rule; `above=true` breaches on `value >= threshold`, `above=false` on `value <= threshold`; `consecutive` clamped to `>= 1`. |
| `alert_state_new()` | `AlertState` | Fresh state: no streak, not firing, zero counters. |
| `alert_observe(r, &mut s, value)` | `Bool` | Feed one sample; returns `true` exactly on the sample that fires the alert. |
| `alert_evaluate(r, values)` | `AlertState` | Fold `alert_observe` over a `Vec[Int]` series into a fresh state. |
| `alert_is_firing(s)` | `Bool` | Whether the alert is currently firing. |
| `alert_fired_count(s)` | `Int` | Fired edges so far. |
| `alert_resolved_count(s)` | `Int` | Resolve edges so far. |
| `alert_breaches(s)` | `Int` | Current consecutive breach streak (0 while not firing). |
| `alert_transition_count(r, values)` | `Int` | Number of fired edges across a series. |

Equality is always a breach: `value == threshold` counts for both directions.
Breaching samples that arrive while the alert is already firing only grow the
streak; they never produce a second fired edge. A non-breaching sample while
not firing simply clears the streak.

## Usage

```xi
use xiom.alerting;
use xiom.io;

var rule = alert_rule_new(90, true, 3);   // fires after 3 samples >= 90
var state = alert_state_new();

alert_observe(&rule, &mut state, 91);     // false, streak 1
alert_observe(&rule, &mut state, 95);     // false, streak 2
alert_observe(&rule, &mut state, 99);     // true  -- fired edge
alert_observe(&rule, &mut state, 97);     // false, still firing
alert_observe(&rule, &mut state, 12);     // false -- resolved

io.println(alert_fired_count(&state));    // 1
io.println(alert_resolved_count(&state)); // 1

var series = Vec[Int].new();
series.push(5); series.push(95); series.push(96); series.push(97);
var folded = alert_evaluate(&rule, &series);
io.println(alert_transition_count(&rule, &series)); // 1
io.println(alert_is_firing(&folded));               // true
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.alerting
```

Expected: the namespaced module passes the section-4 namespace rule, 21
`[PASS]` lines, and a final `port: PASS (passed=21 failed=0 program_exit=0
exit=0)`.

## Limitations

- **Single threshold per rule.** A rule is one level and one direction; there
  are no bands, hysteresis margins, or composite conditions. Two thresholds
  (for example, a warning and a critical level) are two rules and two states.
- **No windows or aggregations.** The state machine sees one sample at a time;
  it has no time window, no rate, no average/max/percentile, and no
  `for`/`unless` qualifiers. Any smoothing or aggregation is the caller's
  job before calling `alert_observe`.
- **The caller supplies every sample.** There is no scheduler, clock,
  collection loop, or data source; the caller decides the cadence and calls
  `alert_observe` (or passes a whole `Vec[Int]` to `alert_evaluate` /
  `alert_transition_count`). `Int` samples and thresholds only -- no floats.
- **No persistence, dedupe, or notification.** Counters live in the caller's
  `AlertState`; there is no serialization, grouping, silencing, routing, or
  acknowledgement.
- Not thread-safe; the types are plain values with no internal locking.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
