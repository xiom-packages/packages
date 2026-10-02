# xiom.autoscale

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.0` on the XIOM registry.
> **Scope:** a pure deterministic autoscaling policy model -- metric ring
> buffer, rolling-window aggregates, hysteresis thresholds, per-direction
> cooldowns, replica bounds, fixed/proportional steps and decision records --
> driven entirely by explicit integer tick steps. No threads, no clock, no
> environment access.
> **Deps:** none (the library imports nothing; tests use `xiom.std` modules).

## What it is

`xiom.autoscale` is the policy core an autoscaler is built around, kept
pure so it can be tested deterministically. The caller reads its metric,
calls `autoscale_controller_tick` (or `autoscale_controller_tick_avg` to
drive decisions from a rolling-window average), and acts on the returned
action while the caller still owns all I/O, timing and thread concerns.

The model has three values:

- `AutoscaleSeries` -- a fixed-capacity ring buffer of `Int` samples with
  rolling-window aggregates (`sum`, `min`, `max`, `avg` over the last N
  stored samples; the average is an integer, truncated toward zero).
- `AutoscalePolicy` -- the configuration: metric name, min/max replicas,
  scale-up/scale-down thresholds whose open interval is the hysteresis
  band, a minimum hysteresis margin, per-direction cooldowns in ticks, a
  consecutive-breach requirement, and a step that is either fixed or
  proportional in basis points of the current replica count.
  `autoscale_policy_check` validates all 12 invariants.
- `AutoscaleController` -- the state machine: replicas, tick counter,
  breach streaks, last-action ticks, an embedded metric series, and one
  decision record per attempted tick (tick, action, from/to, reason code,
  observed value) stored as mirrored parallel `Int` vectors.

## API

Series:

| Function | Returns | Description |
|---|---|---|
| `autoscale_series_new(capacity)` | `AutoscaleSeries` | Empty ring; capacity clamped to `[1, 1000000]`. |
| `autoscale_series_push(&mut s, v)` | -- | Push a sample; overwrites the oldest when full. |
| `autoscale_series_at(&s, i)` | `Int` | Sample `i` chronologically (0 = oldest stored). |
| `autoscale_series_sum/min/max/avg(&s, window)` | `Int` | Aggregate over the last `window` samples (empty window = 0). |

Policy:

| Function | Returns | Description |
|---|---|---|
| `autoscale_policy_new(metric, min, max, up, down, hysteresis)` | `AutoscalePolicy` | Defaults: no cooldowns, breach 1, fixed step 1, 16-slot series. |
| `autoscale_policy_with_cooldowns(p, up, down)` | `AutoscalePolicy` | Copy with per-direction cooldowns in ticks. |
| `autoscale_policy_with_breach(p, n)` | `AutoscalePolicy` | Copy with the consecutive-breach requirement. |
| `autoscale_policy_with_step_fixed(p, n)` | `AutoscalePolicy` | Copy with a fixed step of `n` replicas. |
| `autoscale_policy_with_step_bps(p, bps)` | `AutoscalePolicy` | Copy with a proportional step (2500 = 25%). |
| `autoscale_policy_with_series_capacity(p, cap)` | `AutoscalePolicy` | Copy with the controller ring capacity. |
| `autoscale_policy_check(&p)` | `Int` | First violated invariant code, 0 = well formed. |
| `autoscale_policy_check_ok(&p)` | `Bool` | `check == 0`. |
| `autoscale_step(&p, replicas)` | `Int` | Step in replicas, always at least 1. |

Controller:

| Function | Returns | Description |
|---|---|---|
| `autoscale_controller_new(p, initial)` | `AutoscaleController` | Initial replicas clamped to `[min, max]`. |
| `autoscale_controller_tick(&mut c, v)` | `Int` | Feed a raw sample; returns action (`0/1/2`) or `-1` on refusal. |
| `autoscale_controller_tick_avg(&mut c, v, window)` | `Int` | Feed a sample, decide on the window average (including it). |
| `autoscale_controller_replicas/ticks/...` | `Int` | State accessors. |
| `autoscale_controller_record_*` | `Int` | Decision-record accessors (out of range `-1`). |
| `autoscale_controller_last_reason(&c)` | `Int` | Newest record's reason code. |
| `autoscale_action_text(a)` / `autoscale_reason_text(r)` | `Str` | Decision catalog text. |

## Usage

```xiom
use xiom.autoscale;

// Scale between 2 and 20 replicas when the 30s CPU average leaves the
// 30%-70% band; act at most once every 10 ticks per direction and by 25%.
let p =
  autoscale_policy_with_step_bps(
    autoscale_policy_with_cooldowns(
      autoscale_policy_new("cpu_util_bps", 2, 20, 7000, 3000, 1000),
      10, 10),
    2500);

var c = autoscale_controller_new(p, 4);

// On every explicit tick step (the caller owns the clock and the actions):
let action = autoscale_controller_tick_avg(&mut c, observed_bps, 30);
if action == 1 {
  // scale up to autoscale_controller_replicas(&c)
} elif action == 2 {
  // scale down to autoscale_controller_replicas(&c)
}
```

Every attempt is recorded, holds included:

```xiom
let n = autoscale_controller_record_count(&c);
if n > 0 {
  let i = n - 1;
  // action = autoscale_controller_record_action(&c, i)
  // reason = autoscale_controller_record_reason(&c, i)
  // text   = autoscale_reason_text(reason)
}
```

## Testing

From the repository root:

```powershell
.\scripts\port.ps1 -Package xiom.autoscale -TimeoutSec 60
```

Expected tail: `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Files

| file | purpose |
|------|---------|
| `package.xi` | package manifest (`xiom.autoscale` 0.1.0) |
| `src/autoscale.xi` | series, policy, checker, steps, controller, catalogs |
| `tests/test_conformance.xi` | 21 self-contained conformance tests |
| `SPEC.md` | windows, rules, cooldowns, decision catalog (as implemented) |
| `README.md` | this file |

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
