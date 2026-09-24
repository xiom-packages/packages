# xiom.optimizer

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** deterministic single-variable integer optimizers: grid search,
> hill climbing with step halving, random-restart hill climbing, and
> simulated annealing, all driven by named `fn(&Int) -> Int` objective
> callbacks.
> **Deps:** `xiom.std` only (the library imports nothing; the tests use
> `xiom.test` and `xiom.io`).

## What it is

`xiom.optimizer` searches a **1-D integer domain** for the point that
maximizes a caller-supplied score function. There are no structs, no
references, no `Result`, and no I/O: every function takes plain `Int`s, a
`seed` where randomness is involved, and a **NAMED** top-level objective
`fn(&Int) -> Int` (strictly larger is better). Inline lambdas are rejected
by the compiler's function-pointer codegen, so the objective must be
declared at module scope:

```xi
fn profit(x: &Int) -> Int {
  let d = *x - 137;
  return 1000 - d * d;
}
```

Four algorithms share that interface:

- **`opt_grid_best_int`** -- exhaustive scan of a stepped grid (ties keep
  the smallest point);
- **`opt_hill_climb_int`** -- steepest-of-three neighbourhood with adaptive
  step halving;
- **`opt_random_restart_int`** -- deterministic multi-start hill climbing;
- **`opt_anneal_int`** -- deterministic integer simulated annealing with an
  internal xorshift PRNG.

`opt_linspace_int` and `opt_bounds_ok` are small domain utilities
(endpoints-inclusive integer spacing and inclusive bounds checks).

## API

| Function | Returns | Description |
|---|---|---|
| `opt_linspace_int(lo, hi, n)` | `Vec[Int]` | `n` evenly spaced integers from `lo` to `hi` (endpoints inclusive, integer truncation); `n == 1` gives `[lo]`; `n < 1` or `hi < lo` give an empty vector. |
| `opt_grid_best_int(lo, hi, step, f)` | `Int` | Best grid point `lo, lo+step, ... <= hi`; ties keep the smallest `x`; `step < 1` or `hi < lo` return `lo`. |
| `opt_hill_climb_int(start, step, max_steps, f)` | `Int` | Climbs to the best of `x-step, x, x+step` on strict improvement; on a stall the step halves (integer); stops at step 0 or `max_steps`. |
| `opt_random_restart_int(lo, hi, restarts, step, seed, f)` | `Int` | Deterministic restarts: draws a start in `[lo, hi]` from a seed-derived xorshift stream, runs the hill-climb algorithm (64-step budget), keeps the best. `restarts < 1` or `hi < lo` return `lo`. |
| `opt_anneal_int(start, lo, hi, steps, seed, temp_start, f)` | `Int` | Deterministic simulated annealing; returns the best point seen. `start` is clamped into `[lo, hi]`; `steps < 1` returns the clamped start; `hi < lo` returns `start`. |
| `opt_bounds_ok(x, lo, hi)` | `Bool` | `lo <= x <= hi`; an empty range (`hi < lo`) is always false. |

## Acceptance rule and temperature schedule

A candidate `x + delta` (with `delta = rng() % 17 - 8`, i.e. in `[-8, 8]`,
clamped into `[lo, hi]`) is handled by `opt_anneal_int` as follows:

1. if `f(candidate) > f(x)`, the move is **always accepted**;
2. otherwise the move is accepted exactly when
   `rng() % (temp + 1) > |f(candidate) - f(x)|`.

That inequality is the documented integer approximation of the Metropolis
rule `exp(-cost / temp)`: a zero-cost move is almost always accepted
(`rng() % (temp + 1) > 0`), and the acceptance ceiling shrinks as `temp`
decays. The second draw happens only when the candidate fails to improve,
so the number of PRNG calls per step is 1 (improvement) or 2 (otherwise).

The temperature at 0-based step `i` of `steps` is

```
temp_i = temp_start - ((temp_start - 1) * i) / (steps - 1)   // steps > 1
```

with integer division truncation, `temp_start` clamped to `>= 1` and every
`temp_i` clamped to `>= 1`. It therefore decays linearly from `temp_start`
to exactly 1 across the run; with `steps == 1` the single step runs at
`temp_start`. At `temp == 1` the acceptance test reduces to
`rng() % 2 > cost`, which is never true for `cost >= 1`, so the tail of a
run is greedy.

## Usage

```xi
use xiom.optimizer;

// Objective must be a named top-level fn(&Int) -> Int.
fn profit(x: &Int) -> Int {
  let d = *x - 137;
  return 1000 - d * d;
}

let grid = opt_linspace_int(0, 300, 7);              // 0, 50, 100, ... 300
let a = opt_grid_best_int(0, 300, 5, profit);        // coarse exhaustive scan
let b = opt_hill_climb_int(0, 16, 64, profit);       // adaptive local search
let c = opt_random_restart_int(0, 300, 8, 16, 42, profit);
let d = opt_anneal_int(0, 0, 300, 400, 12345, 200, profit);

// Same seed and inputs always reproduce the same walk on a platform.
let again = opt_anneal_int(0, 0, 300, 400, 12345, 200, profit);
let same = d == again;                               // true
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.optimizer
```

Expected: the module passes the section-4 namespace rule, 24 `[PASS]` lines,
and a final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **One-dimensional integers only.** There is no vector/multi-parameter
  mode, no `Float` objective, and no gradient support; anything richer is
  the caller's job to encode.
- **The PRNG is deterministic, not cryptographic.** Same seed, same walk;
  it is a reproducibility device, not a source of security or statistical
  quality randomness.
- Bounds are only enforced by the algorithms that document them
  (`opt_anneal_int`), and `opt_random_restart_int` bounds only the sampled
  starts -- its hill climbs follow `opt_hill_climb_int` and may leave
  `[lo, hi]`.
- All arithmetic is the platform's 64-bit signed `Int` and wraps on
  overflow rather than trapping (hostile bounds/values are not clamped
  beyond what the API documents).
- Value semantics only: no threads, no shared state, no I/O in the library.
- Callers must declare objectives as named top-level functions; inline
  lambdas are rejected by compiler v0.61.3.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
