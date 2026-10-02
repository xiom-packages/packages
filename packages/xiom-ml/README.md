# xiom.ml

> **Status:** `incubating` -- conformance-tested (18/18); published at `v0.1.0` on the XIOM registry.
> **Scope:** statistical and Bayesian machine-learning primitives on scaled
> integers only: no floats, no FFI, no I/O in the library, no external files.
> **Deps:** stdlib (`xiom.std`); the module itself imports nothing.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `regression` | One-feature least-squares and ridge regression with an intercept, closed-form normal equations, R^2 in basis points |
| `mcmc` | Metropolis-Hastings sampling over an unnormalised integer weight vector, driven by a pinned MINSTD (Park-Miller) LCG |
| `bayesian` | Beta-Binomial conjugate update, posterior mean/mode and a normal-approximation credible interval, all in basis points |
| `kalman` | One-dimensional predict/update filter over scaled state and covariance |

## Fixed-point contract

* `SCALE = 1000`: a real value `v` is stored as `round(v * 1000)`
  (`ml_scale()`).
* `BPS = 10000`: probabilities and ratios are in basis points
  (`ml_bps()`).
* All division rounds halves away from zero (`_div_round`); integer division
  elsewhere truncates toward zero.
* Input envelope: regression samples each in `[-10000, 10000]` (real +/-10)
  with `2..1000` samples; ridge `lambda` in `[0, 1e12]`; MCMC `1..10000`
  states, each weight in `1..1000000`, `1..100000` steps; Beta-Binomial
  posterior total `<= 100000`. Every violation returns a typed `Err`.
* Determinism: the MINSTD LCG is `state = (state * 48271) mod (2^31 - 1)`
  with `state_0 = |seed mod 2147483646| + 1`; the same seed and inputs
  produce the same result on every run and platform.

## Build / test

```
.\scripts\port.ps1 -Package xiom-ml -TimeoutSec 60
```

The suite `tests/test_conformance.xi` runs 18 test functions covering the
regression solver (exact, ridge, degenerate, errors), MCMC (invariants,
reproducibility, biased target, validation), Beta-Binomial inference (mean,
mode, credible interval, point estimate, validation) and Kalman
predict/update including the `den <= 0` guard.
