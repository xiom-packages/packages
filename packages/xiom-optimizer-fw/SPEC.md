# xiom.optimizer-fw -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.optimizer_fw` (`src/optimizer_fw.xi`). Manifest: `package.xi`
(name `xiom.optimizer-fw`, version `0.1.0`, categories `science`/`tooling`).
Pure XIOM, no FFI, no IO in the library, no `Vec[Float64]`, no
`Vec[StructType]`, no closures, no fn-pointer values, no `Result` values.

## 1. Scope

A deterministic, IO-free optimization framework for **one integer variable**,
where the objective is a caller-provided **record** rather than a callback:

- two objective constructors -- a sample table (`optfw_table_new`) and an
  explicit value list (`optfw_list_new`);
- nearest-sample (piecewise-constant) evaluation (`optfw_eval`);
- four searches: exhaustive stepped grid search (`optfw_grid_search`),
  first/best-improvement hill climbing with step halving
  (`optfw_hill_first`, `optfw_hill_best`), simulated annealing with a
  deterministic LCG and a fixed-point geometric cooling schedule
  (`optfw_anneal`), and deterministic random restarts
  (`optfw_restart_search`);
- shared stopping rules (`OptStop`: max iterations, no-improvement window,
  value floor);
- best-so-far tracking with optional convergence traces (`OptTrace`, three
  parallel `Vec[Int]` fields).

There are no references to external state, no clock, no environment access,
no global mutable state and no threads. Randomness comes from an explicit
`seed` and a pure LCG step, so every run is reproducible on a platform.

## 2. Non-goals

- Function-pointer or closure objectives; multi-dimensional or vector
  objectives; floats, gradients, or constraint handling beyond the
  documented clamps.
- OS-entropy restarts: the LCG is deterministic by design.
- Cryptographic or statistically certified randomness.
- Concurrency, cancellation, or progress callbacks; a trace is inspected
  after the search returns.
- Statistical guarantees on annealing output (best-seen is a heuristic
  outcome, not an optimality certificate).

## 3. Constants

| Constant | Value | Meaning |
|---|---|---|
| `OPT_NONE` | `-9223372036854775807` (Int min + 1) | Reserved "no value" sentinel (empty objective, out-of-range accessor) and the disabled `OptStop.floor`. |
| `OPT_REASON_NONE` | 0 | No stop reason (name lookup only). |
| `OPT_REASON_MAX_ITERS` | 1 | The `max_iters` cap fired. |
| `OPT_REASON_NO_IMPROVE` | 2 | The no-improvement window fired. |
| `OPT_REASON_FLOOR` | 3 | The best value reached the floor. |
| `OPT_REASON_EXHAUSTED` | 4 | The space or restart budget was consumed normally. |
| `OPT_REASON_STEP_ZERO` | 5 | Hill climbing halved its step to 0. |
| `OPT_REASON_EMPTY` | 6 | Degenerate input (empty objective or `hi < lo`); no iteration ran. |
| `OPT_RESTART_CLIMB_ITERS` | 64 | Internal iteration budget of each restart climb. |
| `OPT_LCG_MUL` | 1103515245 | LCG multiplier. |
| `OPT_LCG_INC` | 12345 | LCG increment. |
| `OPT_LCG_MASK` | `0x7FFFFFFF` | LCG modulus mask (mod 2^31). |
| `OPT_SEED_SPREAD` | 2654435761 | Per-restart seed spread multiplier. |

`OPT_NONE` is the lowest value distinguishable from Int min and must not be
used as a real objective value.

## 4. Records and invariants

```
OptObjective = { xs: Vec[Int]; vs: Vec[Int] }
OptStop      = { max_iters: Int; no_improve: Int; floor: Int }
OptAnnealCfg = { step: Int; seed: Int; temp_start: Int; cool_num: Int; cool_den: Int }
OptResult    = { x: Int; value: Int; iters: Int; reason: Int; improved: Bool }
OptTrace     = { iters: Vec[Int]; bests: Vec[Int]; currents: Vec[Int] }
```

- `OptObjective`: identical-length parallel vectors. `optfw_table_new`
  writes both through `_obj_push` in one loop; `optfw_list_new` copies
  `min(xs.len, vs.len)` pairs through the same site, so
  `optfw_obj_is_consistent` is always true for records built through the
  public API.
- `OptTrace`: identical-length parallel vectors, written through
  `_trace_push`; `optfw_trace_is_consistent` is its check.
- `OptResult.value` is `OPT_NONE` only when the objective is empty
  (`OPT_REASON_EMPTY`).
- `OptResult.improved` is `true` exactly when the returned best point
  differs from the search's starting point (`lo` for grid/restarts, the
  clamped `start` for hill/anneal).
- `OptAnnealCfg` fields are clamped *at use*: `step >= 0`, `temp_start >= 1`
  in the schedule, `cool_den >= 1`, `cool_num` into `[0, cool_den]`. The
  accessors (`optfw_cfg_step` clamps `step`; the others return raw fields)
  and `optfw_anneal_cfg_new` (raw store) never mutate the record.

## 5. Objective evaluation (`optfw_eval`)

For a non-empty record, `optfw_eval(o, x)` is `vs[i*]` where `i*` is the
smallest index minimizing `|xs[i] - x|` (ties keep the earliest sample). On
a stride-1 table this is `vs[x - lo]`; on any other record it is the
documented piecewise-constant extension to every integer point. An empty
record (or one whose value vector is empty) returns `OPT_NONE`.

Complexity: O(samples). Positions and differences are 64-bit signed `Int`
and wrap at the extremes; callers keep coordinates far from Int min/max.

## 6. Stopping rules (shared `OptStop`, as implemented)

`optfw_stop_new(max_iters, no_improve, floor)` clamps `max_iters` to `>= 1`
(so every search performs at least one iteration and every loop is
bounded); it stores `no_improve` and `floor` unchanged. At use:
`window = no_improve` is active iff `window >= 1`; `floor` is active iff
`floor != OPT_NONE`; the hard cap is `max(1, max_iters)` regardless of how
the record was constructed.

Every search checks the rules at the top of its loop, in this order:

1. **budget** (`max_iters`) -- grid samples / hill iterations / anneal
   steps / restart count; `OPT_REASON_MAX_ITERS`;
2. for grid/hill/anneal: **floor** then **window**; for restarts: **floor**
   then **window**, then the `restarts` count (`OPT_REASON_EXHAUSTED`),
   then the `max_iters` cap (`OPT_REASON_MAX_ITERS`).

Consequences:

- A search whose `restarts` budget runs out before its `max_iters` cap
  reports `OPT_REASON_EXHAUSTED`; the cap reports `OPT_REASON_MAX_ITERS`.
- The first sample of a grid scan and the first iteration of a hill/anneal
  run always count as an improvement for the window counter (a new best is
  recorded at the starting value).
- In hill climbing a step halving is progress but not an improvement: it
  increments the no-improvement counter.
- In annealing an accepted sideways/downhill move increments the counter
  too; only a strict best-value improvement resets it.
- The floor comparison is `best_value >= floor` against the best-so-far
  value, so it can fire even when the current point is worse.

## 7. Search algorithms (as implemented)

All searches first handle degenerate input: `hi < lo` or an empty objective
returns `x = lo` (grid/restarts) or `x = start` (hill/anneal) with
`value = optfw_eval(o, x)`, `iters = 0`, `reason = OPT_REASON_EMPTY`,
`improved = false` -- except that an empty objective yields
`value = OPT_NONE`.

### 7.1 `optfw_grid_search(o, lo, hi, step, stop)`

`step` is clamped to `>= 1`; the scan visits `x = lo, lo + step, ...` while
the stride fits: after processing `x`, the scan continues only when
`step <= hi - x` (a non-negative remainder check, so no stride can overflow
the loop). A strictly larger value replaces the incumbent, so ties keep the
SMALLEST `x`. The scan ends normally with `OPT_REASON_EXHAUSTED`. The
no-improve counter counts samples that did not set a new best (the first
sample sets one).

### 7.2 `optfw_hill_first` / `optfw_hill_best`

`x` starts at `start` clamped into `[lo, hi]`; `step` is clamped to `>= 1`;
`cur`, `best_x`, `best_v` are initialised from `x`.

Each iteration, with `left = clamp(x - s, lo, hi)` and
`right = clamp(x + s, lo, hi)`:

- **first improvement** (`optfw_hill_first`): move to `left` if
  `value(left) > cur`, otherwise to `right` if `value(right) > cur`;
- **best improvement** (`optfw_hill_best`): move to the strictly higher of
  `left`/`right` when that value exceeds `cur` (a tie between `left` and
  `right` keeps `left`).

On a move, `x`/`cur` update, the best-so-far updates on strict improvement
(ties keep the earliest), and the window counter resets. On a stall the
counter increments and `s = s / 2` (integer division; `1 / 2 == 0`). When
`s` reaches 0 the next check stops with `OPT_REASON_STEP_ZERO`. A move is
always a strict score improvement, so the current score never decreases
(the best-so-far never decreases by construction). The default reason
(when no rule fires) is `OPT_REASON_STEP_ZERO`.

### 7.3 `optfw_anneal(o, start, lo, hi, cfg, stop)`

`x = clamp(start, lo, hi)`; the walk's value, best-so-far and the LCG state
(`optfw_lcg_next(cfg.seed)`) are initialised once.

Per step (1-based `k`):

1. the temperature is `optfw_temp_at(temp_start, cool_num, cool_den, k - 1)`;
2. advance the LCG and set `delta = draw % (2 * step + 1) - step`, i.e.
   `delta` in `[-step, step]` (`step` clamped to `>= 0`);
3. candidate `nx = clamp(x + delta, lo, hi)`;
4. accept when `value(nx) > cur`; otherwise advance the LCG again and
   accept when `draw % (temp + 1) > |value(nx) - cur|`;
5. on acceptance set `x = nx`, `cur = value(nx)`, and update the
   best-so-far only on a strict improvement (ties keep the earliest);
6. append one trace row (iteration, best-so-far, current), then cool.

The result is the best point SEEN, which may differ from the final `x`; the
default reason is `OPT_REASON_MAX_ITERS`. Same inputs reproduce the exact
same walk (no other entropy exists).

### 7.4 `optfw_restart_search(o, lo, hi, restarts, step, seed, stop)`

The global best is seeded with `(lo, value(lo))`. Restart `i` (0-based):

1. draw `x0 = lo + (optfw_seed_at(seed, i) % (hi - lo + 1))`, so `x0` is in
   `[lo, hi]`;
2. run the best-improvement hill climb from `x0` with `step` and an
   internal stop record `optfw_stop_new(OPT_RESTART_CLIMB_ITERS, 0,
   OPT_NONE)` (floor/window used by the outer loop only);
3. replace the global best when the climb's value is strictly larger.

The outer loop checks floor, window, the `restarts` count and the
`max_iters` cap in that order, so `restarts < 1` returns `(lo, value(lo))`
with `OPT_REASON_EXHAUSTED`, and the run ends `OPT_REASON_EXHAUSTED` when
the restart list is exhausted. Ties keep the earliest global best.

## 8. Randomness and temperature schedule

### 8.1 Deterministic LCG

```
optfw_lcg_next(state) = ((state & 0x7FFFFFFF) * 1103515245 + 12345) & 0x7FFFFFFF
```

The state/draw is in `[0, 2^31 - 1]`; the stream is non-cryptographic and
platform-stable. Per-restart seeds are spread as

```
optfw_seed_at(base, index) = optfw_lcg_next(base + (index + 1) * 2654435761)
```

so nearby restart indices differ widely before mixing.

### 8.2 Fixed-point cooling

```
optfw_temp_next(temp, num, den) = max(1, max(1, temp) * clamp(num, 0, max(1, den)) / max(1, den))
optfw_temp_at(t0, num, den, steps) = apply temp_next `steps` times to max(1, t0)
```

with integer division truncating toward zero (all operands here are
non-negative). The schedule is non-increasing, never below 1 and never
above the starting temperature; `num == den` freezes the temperature and
`num < den` reaches 1 in finite steps. Step `k` of a run (1-based) runs at
`temp_at(temp_start, cool_num, cool_den, k - 1)`.

### 8.3 Acceptance inequality

For a non-improving candidate with `cost = |value(nx) - cur| >= 0`, the move
is accepted iff `draw % (temp + 1) > cost`. With `draw` (near-)uniform in
`[0, temp]`, a zero-cost move is almost always accepted and a positive-cost
move is never accepted at `temp == 1`; this is the documented integer
approximation of `exp(-cost / temp)` with no floating-point arithmetic. The
second draw happens only when the candidate does not improve, so a step
consumes 1 draw (improvement) or 2 draws (otherwise).

## 9. Complexity

| Operation | Complexity |
|---|---|
| `optfw_table_new` | O(values.len) |
| `optfw_list_new` | O(min(xs.len, vs.len)) |
| `optfw_eval` | O(samples) |
| `optfw_grid_search(+trace)` | O(iters * samples), iters = samples scanned |
| `optfw_hill_first/best(+trace)` | O(iters * samples), <= 2 objective calls per iteration |
| `optfw_anneal(+trace)` | O(iters * samples), <= 2 objective calls per step |
| `optfw_restart_search(+trace)` | O(restarts * (OPT_RESTART_CLIMB_ITERS small constant + 1) * samples) |
| accessors / names | O(1) |

Every loop is bounded by a clamped cap and by construction: grid strides
advance by a remainder check, hill steps halve to 0, annealing draws always
advance the LCG state, restarts count down.

## 10. API signatures

```xi
pub const OPT_NONE: Int = 0 - 0x7FFFFFFFFFFFFFFF;   // .. reason constants 0..6
pub const OPT_RESTART_CLIMB_ITERS: Int = 64;
pub const OPT_LCG_MUL: Int = 1103515245;
pub const OPT_LCG_INC: Int = 12345;
pub const OPT_LCG_MASK: Int = 0x7FFFFFFF;
pub const OPT_SEED_SPREAD: Int = 2654435761;

pub type OptObjective = { xs: Vec[Int]; vs: Vec[Int]; }
pub type OptStop      = { max_iters: Int; no_improve: Int; floor: Int; }
pub type OptAnnealCfg = { step: Int; seed: Int; temp_start: Int; cool_num: Int; cool_den: Int; }
pub type OptResult    = { x: Int; value: Int; iters: Int; reason: Int; improved: Bool; }
pub type OptTrace     = { iters: Vec[Int]; bests: Vec[Int]; currents: Vec[Int]; }

pub fn optfw_table_new(values: &Vec[Int], lo: Int, step: Int) -> OptObjective
pub fn optfw_list_new(xs: &Vec[Int], vs: &Vec[Int]) -> OptObjective
pub fn optfw_obj_len(o: &OptObjective) -> Int
pub fn optfw_obj_is_consistent(o: &OptObjective) -> Bool
pub fn optfw_obj_x(o: &OptObjective, i: Int) -> Int
pub fn optfw_obj_v(o: &OptObjective, i: Int) -> Int
pub fn optfw_obj_first(o: &OptObjective) -> Int
pub fn optfw_obj_last(o: &OptObjective) -> Int
pub fn optfw_eval(o: &OptObjective, x: Int) -> Int

pub fn optfw_stop_new(max_iters: Int, no_improve: Int, floor: Int) -> OptStop
pub fn optfw_stop_max_iters(s: &OptStop) -> Int
pub fn optfw_stop_no_improve(s: &OptStop) -> Int
pub fn optfw_stop_floor(s: &OptStop) -> Int

pub fn optfw_trace_new() -> OptTrace
pub fn optfw_trace_len(t: &OptTrace) -> Int
pub fn optfw_trace_is_consistent(t: &OptTrace) -> Bool
pub fn optfw_trace_iter(t: &OptTrace, i: Int) -> Int
pub fn optfw_trace_best(t: &OptTrace, i: Int) -> Int
pub fn optfw_trace_current(t: &OptTrace, i: Int) -> Int

pub fn optfw_result_x(r: &OptResult) -> Int
pub fn optfw_result_value(r: &OptResult) -> Int
pub fn optfw_result_iters(r: &OptResult) -> Int
pub fn optfw_result_reason(r: &OptResult) -> Int
pub fn optfw_result_improved(r: &OptResult) -> Bool

pub fn optfw_anneal_cfg_new(step: Int, seed: Int, temp_start: Int, cool_num: Int, cool_den: Int) -> OptAnnealCfg
pub fn optfw_cfg_step(c: &OptAnnealCfg) -> Int
pub fn optfw_cfg_seed(c: &OptAnnealCfg) -> Int
pub fn optfw_cfg_temp_start(c: &OptAnnealCfg) -> Int
pub fn optfw_cfg_cool_num(c: &OptAnnealCfg) -> Int
pub fn optfw_cfg_cool_den(c: &OptAnnealCfg) -> Int

pub fn optfw_lcg_next(state: Int) -> Int
pub fn optfw_seed_at(base: Int, index: Int) -> Int
pub fn optfw_temp_next(temp: Int, cool_num: Int, cool_den: Int) -> Int
pub fn optfw_temp_at(temp_start: Int, cool_num: Int, cool_den: Int, steps: Int) -> Int

pub fn optfw_grid_search(o: &OptObjective, lo: Int, hi: Int, step: Int, stop: &OptStop) -> OptResult
pub fn optfw_grid_search_trace(o: &OptObjective, lo: Int, hi: Int, step: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult
pub fn optfw_hill_first(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop) -> OptResult
pub fn optfw_hill_first_trace(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult
pub fn optfw_hill_best(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop) -> OptResult
pub fn optfw_hill_best_trace(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult
pub fn optfw_anneal(o: &OptObjective, start: Int, lo: Int, hi: Int, cfg: &OptAnnealCfg, stop: &OptStop) -> OptResult
pub fn optfw_anneal_trace(o: &OptObjective, start: Int, lo: Int, hi: Int, cfg: &OptAnnealCfg, stop: &OptStop, tr: &mut OptTrace) -> OptResult
pub fn optfw_restart_search(o: &OptObjective, lo: Int, hi: Int, restarts: Int, step: Int, seed: Int, stop: &OptStop) -> OptResult
pub fn optfw_restart_search_trace(o: &OptObjective, lo: Int, hi: Int, restarts: Int, step: Int, seed: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult

pub fn optfw_reason_name(reason: Int) -> Str
```

Private helpers (not exported): `_optfw_abs`, `_optfw_clamp`,
`_optfw_result`, `_optfw_degenerate`, `_obj_push`, `_trace_push`,
`_optfw_cap`, `_grid_core`, `_hill_core`, `_anneal_core`, `_restart_core`.

## 11. Test plan

`tests/test_conformance.xi` (module `optimizer_fw_tests`, 25 named checks
via `assert(cond, "name")`, one `fn` per check, direct calls only; `main`
returns the failure count, 0 = green). All string equality goes through
`str_compare`. Fixtures: `unimodal` (peak 1000 at x=3), `twin` (equal
maxima 100 at x=2 and x=4), `trap` (`[5,20,4,4,10,4,4,50,4,4]`), `linear`
(`10*i` on 0..10), `well` (plateau 100 on `[-1,1]`, valley at `|x|=12`,
wall, global 500 for `|x| >= 33`) and `spiky` (local peaks at 7 and 34,
global 500 at x=23).

| # | Check | Pinned values |
|---|---|---|
| t1 | table geometry, consistency, on-grid eval | len 7; first 0, last 6; eval(3)=1000 |
| t2 | stride geometry, nearest-sample eval | `[10,20,30]` at 100..110 step 5; eval(103)=20, eval(90)=10 |
| t3 | value list, tie to earliest, short side bounds | `[0,10,25]`/`[5,9,3]`; eval(5)=5; len(min)=1 |
| t4 | empty objective | len 0; eval=OPT_NONE; accessors bounded |
| t5 | grid peak | x=3, value 1000, 7 iters, EXHAUSTED |
| t6 | grid ties | x=2 of {2,4}, value 100, 9 iters |
| t7 | grid stride, step clamp, oversized stride | step 3 -> x=9/90/4 iters; step 1 -> 11 iters; step 0 -> 11 iters; step 20 -> 1 iter |
| t8 | grid floor | x=3, 4 iters, FLOOR |
| t9 | grid max_iters 2 | x=1, value 996, 2 iters, MAX_ITERS |
| t10 | grid no-improve window 2 | 6 iters, 6 trace rows, best 1000 |
| t11 | hill first path | x=1, value 20, 3 iters, STEP_ZERO, trace `[20,20,20]` |
| t12 | hill best path | x=7, value 50, 3 iters; better than first (20) |
| t13 | hill cap vs full climb | cap 2 -> x=6/60/MAX_ITERS; full -> x=10/100/6 iters/STEP_ZERO |
| t14 | hill floor 50 | x=7, 1 iter, FLOOR |
| t15 | hill no-improve windows 2 and 1 | 2 iters and 1 iter, NO_IMPROVE |
| t16 | hill start clamp, empty range | start 100 -> x=9/value 4; `hi < lo` -> EMPTY, 0 iters |
| t17 | annealing determinism | cfg(1,42,64,1,2): x=3, value 1000, identical traces |
| t18 | annealing cold/hot on `well` | cold: value 100, x in `[-1,1]`, not improved; hot: value 500 |
| t19 | annealing floor and start clamp | floor 1000 -> x=3/FLOOR; start 500 -> x in `[0,6]` |
| t20 | temperature schedule | 1000*(1/2) -> 1 at step 9; ratio clamps; monotone on 100*(999/1000) |
| t21 | grid trace + bounded accessors | rows == iters; bests non-decreasing; out-of-range defaults |
| t22 | anneal trace | rows == iters; bests non-decreasing; value 1000 |
| t23 | restarts determinism and optimum | 12 climbs, step 4, seed 2026 -> x=23, value 500, 12 iters, EXHAUSTED |
| t24 | restarts floor/degenerate | floor 500 -> FLOOR, <= 12 iters; 0 restarts -> `(0, 477, 0)`; `hi < lo` -> EMPTY |
| t25 | stop clamps, reason names, empty searches | max_iters 0 -> 1; names; empty -> EMPTY/OPT_NONE/0 iters |

## 12. Verification

Last verified: compiler **0.62.2** (installed), stdlib `E:\xiom-lang\stdlib`,
namespace-check 0 conflicts, conformance 25/25:

```
port: PASS (passed=25 failed=0 program_exit=0 exit=0)
```

## 13. Known limitations

- One-dimensional integers only; no floats, gradients or constraints.
- Objective records only: no function-pointer/closure objectives by design.
- Nearest-sample evaluation makes a coarse table a piecewise-constant
  approximation; sample positions should be sorted for intuitive results
  (`optfw_eval` itself only requires them to be present, not sorted).
- `optfw_table_new` positions, `optfw_seed_at` roots and all score
  arithmetic wrap at the Int extremes; hostile extremes are the caller's
  responsibility (documented, as in `xiom.optimizer`).
- The LCG is deterministic and non-cryptographic; `seed` is the only
  entropy. Best-so-far updates use strict `>`: ties keep the earliest best.
- Restarts constrain only the sampled starts; the climbs are bounded by
  `OPT_RESTART_CLIMB_ITERS` and the `[lo, hi]` clamps.

## 14. Compiler / stdlib notes (pinned v0.62.2)

- Free functions only; no `self`, closures, lambdas or indexed `Vec[fn]`
  dispatch; no `Vec[StructType]`; no `Result`/`Ok`/`Err` values; no
  `Vec[Str]` reads.
- Every `Int` read from a `Vec` goes through a typed local; the three
  parallel trace vectors and the two parallel objective vectors each have a
  single push site (`_trace_push`, `_obj_push`) so they cannot drift.
- `OPT_NONE` is written as `0 - 0x7FFFFFFFFFFFFFFF` (Int min + 1), so the
  sentinel needs no Int-min literal and never traps.
- `struct`-typed records with `Vec[Int]` fields, `&mut` record parameters
  and a `Bool` result field were validated with a compile-and-run probe on
  the pinned compiler before the module was written.
- The library imports nothing from `xiom.std` (pure integer logic); tests
  use `xiom.test`, `xiom.io` and `xiom.string.compare` (`str_compare` for
  every string equality, per the v0.62.x string-comparison trap).
- Hand-rolled (no stdlib dependency): the LCG stream
  (`optfw_lcg_next`/`optfw_seed_at`), the fixed-point cooling schedule
  (`optfw_temp_next`/`optfw_temp_at`), nearest-sample lookup (`optfw_eval`)
  and the small integer helpers `_optfw_abs`/`_optfw_clamp`.
