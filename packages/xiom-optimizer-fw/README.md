# xiom.optimizer-fw

> **Status:** `incubating` -- conformance-tested (25/25); not yet published on the XIOM registry.
> **Scope:** a deterministic optimization framework over integer objective
> records: sample tables and explicit value lists, exhaustive grid search,
> first/best-improvement hill climbing, LCG simulated annealing with a
> fixed-point cooling schedule, deterministic random restarts, shared
> stopping rules and convergence traces.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports nothing; tests use
> `xiom.test`, `xiom.io` and `xiom.string.compare`).

## What it is

`xiom.optimizer-fw` is the framework-shaped sibling of `xiom.optimizer`: it
searches integer points for the maximum of an objective, but the objective is
**plain data, not a callback**. There are no function pointers, no closures
and no `Vec[StructType]`; a search is always a free function over an
`OptObjective` record plus an `OptStop` record.

An objective is one of two things, both built through a single push site so
the parallel vectors cannot drift:

- a **sample table** -- `optfw_table_new(values, lo, step)` places
  `values[i]` at the point `lo + i * step`;
- an **explicit value list** -- `optfw_list_new(xs, vs)` pairs caller
  positions with caller values.

Evaluation is **nearest-sample and piecewise constant**: `optfw_eval(o, x)`
returns the value of the sample closest to `x`, ties keeping the earliest
sample. On a stride-1 table this is an ordinary array lookup; on any record
it is the documented total extension to every integer point, so proposals
between samples stay meaningful. An empty objective has no value and returns
the reserved sentinel `OPT_NONE`.

Four searches share the objective and stopping records:

- **`optfw_grid_search`** -- exhaustive stepped scan of `[lo, hi]`;
- **`optfw_hill_first`** / **`optfw_hill_best`** -- hill climbing with first
  or best improvement and integer step halving on a stall;
- **`optfw_anneal`** -- simulated annealing with the framework's
  deterministic LCG and a fixed-point geometric cooling schedule;
- **`optfw_restart_search`** -- deterministic random restarts of
  best-improvement hill climbing.

## Example

```xi
use xiom.optimizer_fw;
use xiom.io;

fn main() -> Int {
  // Objective table: peak value 1000 at x = 3.
  var vals: Vec[Int] = Vec[Int].new();
  vals.push(991);
  vals.push(996);
  vals.push(999);
  vals.push(1000);
  vals.push(999);
  vals.push(996);
  vals.push(991);
  let obj = optfw_table_new(&vals, 0, 1);

  let stop = optfw_stop_new(100, 0, OPT_NONE);          // cap 100, no window/floor
  let g = optfw_grid_search(&obj, 0, 6, 1, &stop);      // x=3 value=1000
  let h = optfw_hill_first(&obj, 0, 0, 6, 3, &stop);    // x=3 value=1000

  let cfg = optfw_anneal_cfg_new(1, 42, 64, 1, 2);      // step 1, seed 42, 64 -> 1
  let a = optfw_anneal(&obj, 0, 0, 6, &cfg, &stop);     // same seed, same walk

  io.println(optfw_reason_name(g.reason));              // "exhausted"
  return h.x + a.x;                                     // 6, deterministic
}
```

## API

Records (all fields are read directly; accessor functions exist for every
field):

| Record | Fields | Meaning |
|---|---|---|
| `OptObjective` | `xs`, `vs` | Parallel sample positions and values. |
| `OptStop` | `max_iters`, `no_improve`, `floor` | Shared stopping rules. |
| `OptAnnealCfg` | `step`, `seed`, `temp_start`, `cool_num`, `cool_den` | Annealing knobs. |
| `OptResult` | `x`, `value`, `iters`, `reason`, `improved` | Search outcome. |
| `OptTrace` | `iters`, `bests`, `currents` | Convergence rows. |

Construction and evaluation:

| Function | Returns | Description |
|---|---|---|
| `optfw_table_new(values, lo, step)` | `OptObjective` | `values[i]` at `lo + i * step`; `step` clamped to `>= 1`. |
| `optfw_list_new(xs, vs)` | `OptObjective` | Explicit list; the shorter vector bounds the record. |
| `optfw_obj_len/is_consistent/x/v/first/last` | `Int`/`Bool` | Range-safe introspection (`x` -> 0, `v` -> `OPT_NONE`). |
| `optfw_eval(o, x)` | `Int` | Nearest sample, ties keep the earliest; `OPT_NONE` when empty. |

Searches (`o` is `&OptObjective`, `s` is `&OptStop`; each has a `_trace`
twin that appends rows to a caller-owned `&mut OptTrace`):

| Function | Returns | Description |
|---|---|---|
| `optfw_grid_search(o, lo, hi, step, s)` | `OptResult` | Exhaustive stepped scan; ties keep the smallest `x`. |
| `optfw_hill_first(o, start, lo, hi, step, s)` | `OptResult` | Move to `x - step` on strict improvement, else `x + step`; halve on stall. |
| `optfw_hill_best(o, start, lo, hi, step, s)` | `OptResult` | Best of both neighbours on strict improvement (ties keep `x - step`). |
| `optfw_anneal(o, start, lo, hi, cfg, s)` | `OptResult` | Integer Metropolis acceptance; returns the best seen. |
| `optfw_restart_search(o, lo, hi, restarts, step, seed, s)` | `OptResult` | Deterministic multi-start best-improvement climbing. |

Stopping rules (`OptStop`, shared by every search, checked in this order:
floor, no-improve, budget):

| Field | Rule | Disabled by |
|---|---|---|
| `max_iters` | Hard iteration cap (grid samples, hill iterations, anneal steps, restart count). | never: `optfw_stop_new` clamps to `>= 1`, so every search terminates. |
| `no_improve` | Stop after this many consecutive iterations without a new best value. | `<= 0`. |
| `floor` | Stop as soon as `best_value >= floor`. | `OPT_NONE`. |

Support: `optfw_stop_new/max_iters/no_improve/floor`,
`optfw_trace_new/len/is_consistent/iter/best/current`,
`optfw_result_x/value/iters/reason/improved`,
`optfw_anneal_cfg_new/step/seed/temp_start/cool_num/cool_den`,
`optfw_temp_next`, `optfw_temp_at`, `optfw_lcg_next`, `optfw_seed_at`,
`optfw_reason_name`. Constants: `OPT_NONE`, `OPT_REASON_NONE`,
`OPT_REASON_MAX_ITERS`, `OPT_REASON_NO_IMPROVE`, `OPT_REASON_FLOOR`,
`OPT_REASON_EXHAUSTED`, `OPT_REASON_STEP_ZERO`, `OPT_REASON_EMPTY`,
`OPT_RESTART_CLIMB_ITERS` (64), `OPT_LCG_MUL`, `OPT_LCG_INC`,
`OPT_LCG_MASK`, `OPT_SEED_SPREAD`.

## Annealing recipe

- **Randomness.** `optfw_lcg_next(state) = (state * 1103515245 + 12345) mod
  2^31`, seeded from `cfg.seed`. Deterministic, not cryptographic; same
  seed, same walk.
- **Proposal.** `delta = draw % (2 * step + 1) - step` (in `[-step, step]`),
  candidate `clamp(x + delta, lo, hi)`.
- **Acceptance.** An improving candidate is always accepted; otherwise the
  move is accepted when `draw % (temp + 1) > |value(candidate) - value(x)|`
  -- the integer approximation of `exp(-cost / temp)`. The second draw
  happens only when the candidate does not improve.
- **Temperature.** Fixed-point geometric cooling: `temp' =
  max(1, temp * cool_num / cool_den)`, so step `k` (1-based) runs at
  `optfw_temp_at(temp_start, cool_num, cool_den, k - 1)`. The schedule is
  non-increasing and clamped at 1; `temp_start` is clamped to `>= 1`.

## Tests

From the repository root:

```
.\scripts\port.ps1 -Package xiom.optimizer-fw
```

Expected tail: 25 `[PASS]` lines, `xiom.optimizer-fw: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Install / usage

The package is **not yet published** on the XIOM registry; when it is, the
consumer workflow is:

```
xiom pkg install xiom.optimizer-fw@0.1.0
```

Until then, use it from this repository (the module is pure XIOM, no FFI):

```
use xiom.optimizer_fw;
```

## Limitations

- **One-dimensional integers only.** No vector/multi-parameter mode, no
  `Float`, no gradients, no constraints beyond the documented clamps.
- **Objective records only.** There are no function-pointer or closure
  objectives; every objective is a table/list record (this is deliberate:
  it keeps the framework value-only and reproducible).
- **Nearest-sample evaluation.** Points between samples observe the closer
  sample's value (ties to the earlier sample), so a coarse table is a
  piecewise-constant approximation of the underlying function.
- **Deterministic, not cryptographic randomness.** The LCG is a
  reproducibility device; `seed` is the only entropy.
- **Wraparound arithmetic.** All values are 64-bit signed `Int` and wrap at
  the extremes; keep coordinates, values and strides far from the Int
  extremes (the `OPT_NONE` sentinel itself is Int min + 1 and must not be
  used as a real value).
- **Restarts bound only the sampled starts.** The per-restart climbs are
  bounded by `OPT_RESTART_CLIMB_ITERS` and the `[lo, hi]` clamps, but the
  restart stop rules apply to the global best, not per climb.
- **Value semantics only.** No threads, no shared state, no I/O in the
  library.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
