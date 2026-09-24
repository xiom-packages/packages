# xiom.optimizer -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.optimizer` (`src/optimizer.xi`). Manifest: `package.xi` (name
`xiom.optimizer`, version `0.1.0`). Depends on `xiom.std` (no library
imports; tests use `xiom.test` and `xiom.io`).

## Scope

Deterministic single-variable integer optimizers over a caller-supplied
objective `f: fn(&Int) -> Int` (strictly larger is better):

- `opt_linspace_int` -- endpoints-inclusive integer spacing;
- `opt_grid_best_int` -- exhaustive stepped-grid scan;
- `opt_hill_climb_int` -- best-of-three hill climbing with step halving;
- `opt_random_restart_int` -- deterministic multi-start hill climbing;
- `opt_anneal_int` -- deterministic integer simulated annealing with a
  linearly decaying temperature;
- `opt_bounds_ok` -- inclusive bounds check.

Everything is caller-owned values: no I/O, no clock, no environment access,
no global state, no threads. Randomness comes from a local xorshift-style
PRNG carried in a plain `var rng: Int` and seeded from an explicit `seed`
argument, so every run is reproducible on a platform.

## Non-goals

- Multi-dimensional or vector objectives; floats or gradients.
- Stochastic restarts from OS entropy: the PRNG is deterministic by design.
- Constraint handling beyond the documented clamps: only `opt_anneal_int`
  enforces `[lo, hi]` on every visited point.
- Concurrency, cancellation, or progress callbacks.
- Cryptographic or statistically certified randomness.

## API signatures

All functions are free functions in module `xiom.optimizer`:

```xi
pub fn opt_linspace_int(lo: Int, hi: Int, n: Int) -> Vec[Int]
pub fn opt_grid_best_int(lo: Int, hi: Int, step: Int, f: fn(&Int) -> Int) -> Int
pub fn opt_hill_climb_int(start: Int, step: Int, max_steps: Int, f: fn(&Int) -> Int) -> Int
pub fn opt_random_restart_int(lo: Int, hi: Int, restarts: Int, step: Int, seed: Int, f: fn(&Int) -> Int) -> Int
pub fn opt_anneal_int(start: Int, lo: Int, hi: Int, steps: Int, seed: Int, temp_start: Int, f: fn(&Int) -> Int) -> Int
pub fn opt_bounds_ok(x: Int, lo: Int, hi: Int) -> Bool
```

Private helpers: `_OPT_RESTART_MAX_STEPS` (const 64), `_opt_abs`,
`_opt_clamp`, `_opt_rng_next`, `_opt_seed_at`.

## Semantics

### opt_linspace_int

For `n >= 2` and `hi >= lo`:

```
out[i] = lo + ((hi - lo) * i) / (n - 1),  i in [0, n - 1]
```

with integer division truncating toward zero. Because `hi >= lo` the
product is non-negative and the result is non-decreasing; `out[0] == lo`
and `out[n-1] == hi`. `n == 1` yields `[lo]` (the single point is the
lower endpoint). `n < 1` or `hi < lo` yield an empty vector. A constant
range (`hi == lo`) repeats `lo` `n` times.

### opt_grid_best_int

Scans `x = lo, lo + step, lo + 2*step, ...` while `x <= hi`, keeping the
incumbent and replacing it only on a strictly larger score. Ties therefore
keep the SMALLEST grid point. `step < 1` or `hi < lo` return `lo` without
a scan (in the `step < 1` case `f` is still evaluated once at `lo`).

### opt_hill_climb_int

Each iteration (while `i < max_steps` and `s >= 1`):

1. evaluate `cur = f(x)`, `lv = f(x - s)`, `rv = f(x + s)`;
2. move to the strictly highest-scoring of the three (`x - s` is preferred
   over `x` over `x + s` only when strictly better; ties keep `x`);
3. if no move happened (stall), `s = s / 2` (integer division; `1 / 2`
   is `0`, which terminates the loop).

`step < 1` or `max_steps < 1` return `start`. Every accepted move is a
strict improvement, so the score never decreases. The loop is bounded by
`min(max_steps, number of halvings until 0)` iterations, with at most 3
objective calls per iteration.

### opt_random_restart_int

The running best is seeded with `(lo, f(lo))`. For restart index `i` in
`[0, restarts)`:

1. draw `x0 = lo + (_opt_seed_at(seed, i) % (hi - lo + 1))`, so
   `x0` is in `[lo, hi]`;
2. run the `opt_hill_climb_int` algorithm from `x0` with `step` and an
   internal budget of `_OPT_RESTART_MAX_STEPS = 64` iterations;
3. replace the running best when the climb result scores strictly higher.

`restarts < 1` or `hi < lo` return `lo`. Because the best is seeded with
`f(lo)`, the empty-restart case returns `lo`. The climbs themselves are
unbounded (`opt_hill_climb_int` semantics): only the sampled starts are
constrained to `[lo, hi]`.

### opt_anneal_int

Entry: `hi < lo` returns `start` unchanged. Otherwise
`x = clamp(start, lo, hi)`; `steps < 1` returns that clamped `x`.

Per step (0-based `i`):

1. temperature (see below), clamped to `>= 1`;
2. advance the PRNG and set `delta = (rng % 17) - 8`, i.e. `delta` in
   `[-8, 8]`;
3. candidate `nx = clamp(x + delta, lo, hi)`;
4. accept when `f(nx) > f(x)`; otherwise advance the PRNG again and accept
   when `rng % (temp + 1) > |f(nx) - f(x)|`;
5. on acceptance set `x = nx`, and update the best-seen record only when
   the new score is strictly larger than the recorded best (ties keep the
   earliest best point).

Returns the best point seen, which may differ from the final `x`.

### Temperature schedule

```
temp_i = temp_start - ((temp_start - 1) * i) / (steps - 1)   // steps > 1
temp_i = temp_start                                          // steps == 1
```

with integer truncation, `temp_start` clamped to `>= 1`, and every
`temp_i` additionally clamped to `>= 1`. At `i = 0` the temperature is
`temp_start`; at `i = steps - 1` it is exactly 1; intermediate values
decay linearly (up to truncation).

### Acceptance probability

The worse-move test is the documented integer approximation of the
Metropolis rule `exp(-cost / temp)`:

```
accept  iff  rng() % (temp + 1) > cost,   cost = |f(nx) - f(x)| >= 0
```

Properties: `rng()` is uniform in `[1, 2^31 - 1]`, so `rng() % (temp + 1)`
is (near-)uniform in `[0, temp]`. A zero-cost move is rejected only when
the draw is exactly 0, i.e. with approximate probability `1/(temp + 1)`.
A positive-cost move is accepted with approximate probability
`(temp - cost) / (temp + 1)` for `cost <= temp`, and never for
`cost >= temp + 1`; at `temp == 1` no positive-cost move is ever accepted
(`rng() % 2` is 0 or 1). This mirrors `exp(-cost/temp)` qualitatively
(high temperature accepts most moves, low temperature only improvements)
without any floating-point arithmetic.

### opt_bounds_ok

Exactly `x >= lo && x <= hi`. An empty range (`hi < lo`) is always false;
degenerate single points (`lo == hi`) are inclusive.

## PRNG recipe (pinned)

Deterministic 31-bit xorshift-style step; input is the current state, the
returned state IS the draw:

```
h = state
h = h ^ (h >> 13)
h = h & 0x00FFFFFFFFFFFFFF      // make non-negative before the left shift
h = h ^ (h << 7)
h = h ^ (h >> 17)
h = h & 0x7FFFFFFF
if h == 0 { h = 0x1F123BB5 }    // repair the zero fixed point
return h                        // in [1, 2^31 - 1]
```

`opt_anneal_int` initialises with `rng = _opt_rng_next(seed)` and uses the
post-advance state as the draw on every subsequent call.
`opt_random_restart_int` derives per-restart states as

```
_opt_seed_at(base, index) = _opt_rng_next(base + (index + 1) * 2654435761)
```

so nearby restarts are spread far apart before mixing. The PRNG is
deterministic and platform-stable for these operations; it is NOT
cryptographic.

## Complexity

| Operation | Complexity |
|---|---|
| `opt_linspace_int` | O(n) |
| `opt_grid_best_int` | O(1 + (hi - lo) / step) objective calls |
| `opt_hill_climb_int` | O(min(max_steps, log2 step)) iterations, <= 3 f-calls each |
| `opt_random_restart_int` | O(restarts * 64) iterations, <= 3 f-calls each |
| `opt_anneal_int` | O(steps) iterations, <= 2 f-calls each |
| `opt_bounds_ok` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module optimizer_tests`, 24 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Each check is its own small function; `main`
only sequences them. Named objectives in the suite: `neg_abs`,
`quadratic` (peak at 3), `peak_7`, `peak_10`, `twin_peaks` (equal maxima at
2 and 6), `linear`, `well_two` (plateau 100 on `[-1, 1]`, valley at 8,
global plateau 500 at `|x| >= 32`) and `neg_quad_137`.

1. `linspace 0..10 n=3` is exactly `[0, 5, 10]`;
2. `n == 1` pins `lo`; `n == 0` and `n == -3` are empty;
3. `hi < lo` (twice) is empty;
4. a constant range repeats `lo` `n` times;
5. `-5..5 n=5` is `[-5, -3, 0, 2, 5]` and `-7..9 n=6` is non-decreasing;
6. grid finds the unimodal quadratic peak at 3;
7. grid honours `step` and a non-multiple `hi`;
8. grid ties keep the smallest `x` (2 of {2, 6});
9. grid returns `lo` for `step < 1` and for `hi < lo`;
10. hill climb converges to the peak at 7 on `peak_7`;
11. step halving escapes a stall: start 6, step 4 -> 7 (`f(6) == 999`);
12. `max_steps` bound: 8 after 2 iterations, 10 after 4, on `peak_10`;
13. hill climb returns `start` for `step == 0` or `max_steps <= 0`;
14. hill climb never lowers the score across six starts;
15. random restarts are deterministic (same seed twice) and reach 137;
16. random restarts improve on the start point (two pinned configurations);
17. no restarts / empty range return `lo`;
18. annealing is deterministic and reaches 137 (`temp_start = 200`);
19. at `temp_start == 1` annealing accepts only improvements and climbs
    `linear` to `hi == 100`;
20. temperature decay on the pinned `well_two` case: `temp_start == 1`
    stays on the 100 plateau, `temp_start == 100000` escapes to 500, and
    the two results differ;
21. `temp_start` below 1 clamps to the greedy `temp == 1` behaviour
    (results identical to test 20's low run);
22. `start` clamps into `[lo, hi]` (`steps == 0`), and `hi < lo` returns
    `start`;
23. annealing respects bounds from an out-of-range start;
24. `opt_bounds_ok` is inclusive and rejects empty ranges.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.optimizer
```

Last verified: compiler 0.61.3, `port: PASS (passed=24 failed=0
program_exit=0 exit=0)`.

## Known limitations

- One-dimensional integers only; no floats, gradients, or constraints
  beyond `opt_anneal_int`'s clamps.
- The PRNG is deterministic by design and not cryptographic; `seed` is the
  only entropy.
- `opt_random_restart_int` bounds only the sampled starts; the climbs are
  unbounded. `opt_anneal_int` is the only bounded-walk optimizer.
- `opt_grid_best_int` evaluates `f` once even when returning `lo` for
  `step < 1` (documented above).
- All arithmetic wraps on the platform's signed 64-bit `Int`; extreme
  bounds or scores are the caller's responsibility.
- The best-seen record uses strict `>`: ties keep the earliest best point,
  never a later equal one.

## Compiler / stdlib notes for v0.61.3

- **No `&mut` parameters in this module.** A probe on 0.61.3 showed that a
  simple `state = state + 1` write-through on a `&mut Int` parameter
  miscompiles (the callee returned pointer-sized garbage). The PRNG was
  therefore designed around a value-returning `_opt_rng_next(state: Int)`
  -- the returned state is both the advance and the draw -- so the module
  contains no references at all.
- Function pointers must be NAMED top-level functions; inline lambdas are
  rejected (or miscompiled) by the function-pointer codegen. All callbacks
  here and in the tests follow the `fn(&Int) -> Int` convention of
  `xiom.property` / `xiom.option`.
- A single very large function that hosts many distinct function-pointer
  call sites (9+ optimizer calls with 5 different callbacks in one `main`)
  miscompiled with an access violation during development on 0.61.3. The
  conformance suite keeps every check in its own small function and `main`
  only sequences them, which compiles and runs clean.
- No `Str`, no `Vec[StructType]`, no `Vec[fn]` dispatch, no `Result`: the
  module cannot hit the BUG 17 string-comparison path or the
  `Ok`/`Err`-in-struct-returning-function miscompile because it uses none
  of those constructs.
- The namespace rule passes: `xiom.optimizer` shares only the root `xiom`
  segment with every stdlib module, and no stdlib module lives under
  `xiom.optimizer` (`namespace-check` reports 0 conflicts).
