# xiom.autoscale -- specification

Deterministic autoscaling policy model in pure XIOM (no FFI, no threads, no
clock). This document describes the windows, rules, cooldowns and decision
catalog that `src/autoscale.xi` actually enforces.

- package: `xiom.autoscale` 0.1.0
- module: `xiom.autoscale`
- entry points: `autoscale_controller_new`, `autoscale_controller_tick`,
  `autoscale_controller_tick_avg`, `autoscale_policy_check`, the
  `autoscale_series_*` functions and the accessor/text catalogs

## 1. Scope

In scope:

- A fixed-capacity **metric ring buffer** of `Int` samples with rolling
  window aggregates (`sum`, `min`, `max`, `avg`) over the most recent N
  stored samples.
- A **policy** with scale-up/scale-down thresholds, a hysteresis band and a
  minimum hysteresis margin, per-direction cooldowns in ticks, min/max
  replica bounds, a consecutive-breach requirement and a fixed or
  proportional step, plus an **invariant checker** over all of it.
- A **controller** state machine driven by explicit integer ticks: breach
  streak tracking, cooldown gating, bound clamping, and one **decision
  record per attempted tick** with an action and a reason code.

Out of scope (non-goals):

- Wall-clock time, sleeping, timers, threads and concurrency. The caller
  reads the clock, calls tick and performs any action.
- Metric collection itself (the controller receives samples).
- Floating point: every value, threshold and aggregate is an `Int`.
- Acting on the environment (no scaling side effects, no process access).

## 2. Data model

`AutoscaleSeries`:

| field | meaning |
|---|---|
| `capacity` | ring size, clamped to `[1, 1000000]` at construction |
| `count` | total pushes ever recorded (may exceed capacity) |
| `head` | next write slot once the ring is full |
| `values` | stored samples, chronological (index 0 = oldest stored) |

`AutoscalePolicy`:

| field | meaning |
|---|---|
| `metric` | metric name (non-empty for a valid policy) |
| `min_replicas` / `max_replicas` | replica bounds |
| `up_threshold` / `down_threshold` | inclusive breach bounds |
| `min_hysteresis` | smallest required `up_threshold - down_threshold` gap |
| `up_cooldown` / `down_cooldown` | minimum ticks between same-direction actions |
| `breach_threshold` | consecutive breaching samples required to act |
| `step_mode` | 0 fixed, 1 proportional (bps) |
| `step_fixed` | fixed step in replicas (mode 0) |
| `step_bps` | proportional step in basis points (mode 1) |
| `series_capacity` | controller ring capacity |

`AutoscaleController`:

| field | meaning |
|---|---|
| `policy` | embedded policy copy |
| `series` | embedded metric series |
| `replicas` | current target |
| `ticks` | accepted tick count |
| `last_up_tick` / `last_down_tick` | tick of the last same-direction action |
| `up_streak` / `down_streak` | consecutive-breach counters |
| `record_tick/action/from/to/reason/detail` | mirrored decision records |

## 3. Metric series

- `autoscale_series_new(capacity)` clamps `capacity` to `[1, 1000000]`.
- `autoscale_series_push` appends while the ring has room; once full it
  overwrites the oldest sample, so the stored window is always the newest
  `min(count, capacity)` samples.
- `autoscale_series_at(s, i)` indexes chronologically: 0 is the oldest
  stored sample, `len-1` the newest. Out-of-range indexes return 0.
- `autoscale_series_len` is `min(count, capacity)`.

Window aggregates:

- The effective window is `0` when `window <= 0` or the series is empty,
  otherwise `min(window, len)`.
- An empty effective window makes `sum`, `min`, `max` and `avg` all return
  0.
- `sum` uses saturating `Int` addition (clamped at the `Int` limits);
  `min`/`max` are exact.
- `avg` is `trunc(sum / n)` toward zero: `sum(-10, -15) = -25` over two
  samples gives `-12`, not `-13`.

## 4. Policy invariants

`autoscale_policy_new` stores its inputs verbatim (so malformed fixtures can
be constructed and checked); the builders derive modified copies.
`autoscale_policy_check` returns the first violated code:

| code | invariant |
|---|---|
| 0 | well formed |
| 1 | `metric` is non-empty |
| 2 | `min_replicas >= 0` |
| 3 | `max_replicas >= min_replicas` |
| 4 | `max_replicas <= 1000000000` |
| 5 | `up_threshold > down_threshold` |
| 6 | `min_hysteresis >= 0` and `up_threshold - down_threshold >= min_hysteresis` |
| 7 | both cooldowns are `>= 0` |
| 8 | `breach_threshold >= 1` |
| 9 | `step_mode` is 0 (fixed) or 1 (bps) |
| 10 | in fixed mode, `step_fixed >= 1` |
| 11 | in bps mode, `step_bps` is in `[1, 10000]` |
| 12 | `series_capacity` is in `[1, 1000000]` |

`autoscale_policy_check_ok` is `check == 0` and
`autoscale_policy_error_text` returns the human text of a code.

Constructor defaults: cooldowns 0, `breach_threshold` 1, fixed step of 1
replica, `series_capacity` 16.

## 5. Step computation

`autoscale_step(p, replicas)` always returns at least 1:

- mode 0: `step_fixed` (a value below 1 is clamped to 1);
- mode 1: `trunc(replicas * step_bps / 10000)`, clamped up to 1. The product
  is never formed: the helper splits `replicas` into quotient and remainder
  of 10000, so the partial products stay bounded; `bps` is clamped to
  `[0, 10000]` inside the helper. Examples: `replicas=10, bps=2500 -> 2`;
  `replicas=3, bps=1000 -> 1` (0.3 rounds down to 0, then clamps to 1);
  `replicas=9, bps=9999 -> 8` (8.9991 truncates).

## 6. Tick algorithm and decision catalog

`autoscale_controller_new(p, initial)` clamps `initial` into
`[min_replicas, max_replicas]` (if the bounds are inverted, `min_replicas`
wins after clamping) and starts with `ticks = 0`,
`last_up_tick = -up_cooldown`, `last_down_tick = -down_cooldown`, so
cooldowns are already satisfied at tick 0.

`autoscale_controller_tick(&mut c, value)` and
`autoscale_controller_tick_avg(&mut c, value, window)` are refused with -1
(no state advance, one record appended) when:

- the tick counter is already at `9223372036854775806` (overflow guard):
  record reason 11, detail = `value`;
- `autoscale_policy_check` is nonzero: record reason 10, detail = the check
  code.

Otherwise the tick is accepted: `ticks += 1` and the sample is pushed. The
decision is then evaluated on `value` (plain tick) or on the window average
including the new sample (avg tick):

```
observed >= up_threshold   -> up breach
observed <= down_threshold -> down breach
otherwise                  -> inside the hysteresis band (both streaks reset)
```

Check order for an up breach (the down path is symmetric):

| condition | action | reason |
|---|---|---|
| `up_streak < breach_threshold` | 0 | 4 hold: up breach streak below required |
| `replicas >= max_replicas` | 0 | 8 hold: already at max replicas |
| `tick - last_up_tick < up_cooldown` | 0 | 6 hold: up cooldown active |
| otherwise | 1 | 1 scale-up: up threshold breached |

and for a down breach: `down_streak < breach_threshold` -> reason 5,
`replicas <= min_replicas` -> reason 9,
`tick - last_down_tick < down_cooldown` -> reason 7, otherwise action 2 /
reason 2. A sample inside the band resets both streaks and records reason 3.

On an action the target is clamped: `to = min(from + step, max_replicas)`
up, `to = max(from - step, min_replicas)` down. Actions do **not** reset the
breach streak: the cooldown (plus the bounds) is the rate limiter, so a
direction that keeps breaching acts again as soon as its cooldown elapses.
The two directions are independent: an up action is allowed during a down
cooldown and vice versa.

Reason catalog (`autoscale_reason_text`):

| code | action | text |
|---|---|---|
| 1 | scale-up | `scale-up: up threshold breached` |
| 2 | scale-down | `scale-down: down threshold breached` |
| 3 | none | `hold: metric inside hysteresis band` |
| 4 | none | `hold: up breach streak below required` |
| 5 | none | `hold: down breach streak below required` |
| 6 | none | `hold: up cooldown active` |
| 7 | none | `hold: down cooldown active` |
| 8 | none | `hold: already at max replicas` |
| 9 | none | `hold: already at min replicas` |
| 10 | none | `refused: invalid policy` |
| 11 | none | `refused: tick counter overflow` |
| other | none | `unknown reason` |

Action codes (`autoscale_action_text`): 0 `none`, 1 `scale-up`,
2 `scale-down`; any other value reads as `none`.

## 7. Decision records

Every attempted tick appends exactly one record as six mirrored parallel
`Int` vectors:

| accessor | meaning |
|---|---|
| `autoscale_controller_record_tick(c, i)` | tick number (or the unchanged counter for a refusal) |
| `autoscale_controller_record_action(c, i)` | 0/1/2 |
| `autoscale_controller_record_from(c, i)` | replicas before |
| `autoscale_controller_record_to(c, i)` | replicas after |
| `autoscale_controller_record_reason(c, i)` | reason code |
| `autoscale_controller_record_detail(c, i)` | observed value (raw sample or window average) or the policy check code on refusal |

Out-of-range indexes return -1. `autoscale_controller_last_reason` returns
the newest reason code, or -1 when there are no records.

## 8. Determinism, complexity, overflow guards

- No clock, thread, sleep, environment or allocation beyond the series and
  record vectors; identical policies and tick sequences always produce
  identical replicas, streak counters, records and series (pinned by the
  determinism conformance test).
- All loops are bounded by the window length or the record count and have a
  strictly increasing counter, so every loop terminates.
- Aggregates use saturating addition; cooldown arithmetic uses saturating
  subtraction; the proportional step never forms the raw product; the
  policy bound `max_replicas <= 1000000000` keeps target arithmetic small;
  tick growth is explicitly refused at the overflow guard.
- Complexity: series push/at O(1); window aggregates O(window); tick O(1)
  plus the record append; `tick_avg` O(window); policy check and step O(1).

## 9. API index

Series: `autoscale_series_new`, `autoscale_series_push`,
`autoscale_series_capacity`, `autoscale_series_count`,
`autoscale_series_len`, `autoscale_series_at`, `autoscale_series_sum`,
`autoscale_series_min`, `autoscale_series_max`, `autoscale_series_avg`.

Policy: `autoscale_policy_new`, `autoscale_policy_with_cooldowns`,
`autoscale_policy_with_breach`, `autoscale_policy_with_step_fixed`,
`autoscale_policy_with_step_bps`, `autoscale_policy_with_series_capacity`,
`autoscale_policy_check`, `autoscale_policy_check_ok`,
`autoscale_policy_error_text`, `autoscale_step`.

Controller: `autoscale_controller_new`, `autoscale_controller_tick`,
`autoscale_controller_tick_avg`, `autoscale_controller_policy`,
`autoscale_controller_replicas`, `autoscale_controller_ticks`,
`autoscale_controller_up_streak`, `autoscale_controller_down_streak`,
`autoscale_controller_last_up_tick`, `autoscale_controller_last_down_tick`,
`autoscale_controller_series_len`, `autoscale_controller_series_at`,
`autoscale_controller_series_avg`, `autoscale_controller_record_count`,
`autoscale_controller_record_tick/action/from/to/reason/detail`,
`autoscale_controller_last_reason`.

Catalog: `autoscale_action_text`, `autoscale_reason_text`.
