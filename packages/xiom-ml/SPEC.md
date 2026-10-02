# xiom.ml -- specification

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Pure-XIOM, deterministic, fixed-point statistical and Bayesian ML primitives.
Module `xiom.ml`; no floats, no FFI, no I/O in the library, no external files
in the tests.

## Scales and rounding

* `SCALE = 1000` (`ml_scale()`) for state-like quantities.
* `BPS = 10000` (`ml_bps()`) for probabilities/ratios.
* `_div_round(a, b)` truncates `a / b` then rounds half away from zero
  (`b > 0`); all documented scalar outputs use it.
* `Int` division elsewhere is LLVM `sdiv` (toward zero).

## 1. Regression

Closed-form normal equations for one feature and an intercept.

Inputs `x`, `y`: equal length `n`, `2 <= n <= 1000`, each component in
`[-10000, 10000]`. Let `Sx=sum x`, `Sy=sum y`, `Sxx=sum x*x`,
`Sxy=sum x*y`.

```
num = n*Sxy - Sx*Sy
den = n*Sxx - Sx*Sx + lambda        (lambda = 0 for OLS)
slope_scaled      = round(SCALE * num / den)
mean_y            = round(Sy / n)
mean_x            = round(Sx / n)
intercept_scaled  = mean_y - round(slope_scaled * mean_x / SCALE)
pred(x)           = intercept_scaled + round(slope_scaled * x / SCALE)
sse               = sum (y - pred(x))^2
sst               = sum (y - mean_y)^2
r2_bps            = 0                         if sst == 0
                  = round((sst - sse) * BPS / sst) otherwise
```

`den <= 0` (all `x` equal and no ridge) is the error
`"ml: regression is degenerate"`. `|num| > floor(INT_MAX / SCALE)` is
`"ml: regression scale overflows"`. The envelope above keeps every product
below `INT_MAX`.

## 2. MCMC

Metropolis-Hastings over states `0..n-1` with positive unnormalised weights.

* LCG: MINSTD `state = (state * 48271) mod (2^31 - 1)`, seeded as
  `|seed mod 2147483646| + 1`.
* Chain starts at state 0. Each step: draw `u`; propose `cur+1` when
  `u mod 2 == 0`, else `cur-1`, reflecting at the ends (`cand = n-2` at the
  top, `1` at the bottom; single-state stays at 0). Draw `u2`; accept when
  `w_prop >= w_cur`, else when `u2 * w_cur < w_prop * (2^31 - 1)`.
* `counts` sums to `steps`; `accepted` counts accepted proposals;
  `mean_bps = round(BPS * sum k*counts[k] / steps)`; `map_state` is the
  arg-max of `counts` (ties to the lowest index).

Envelope: `1 <= n <= 10000`, each weight in `[1, 1000000]`,
`1 <= steps <= 100000`. Violations return `Err("ml: ...")`.

## 3. Bayesian Beta-Binomial

Prior `(alpha, beta)` with `alpha,beta > 0`; `successes, failures >= 0`;
`z_bps >= 0`.

```
a = alpha + successes, b = beta + failures, tot = a + b
mean_bps = round(BPS * a / tot)
mode_bps = round(BPS * (a-1) / (a+b-2))   when a > 1 and b > 1
         = mean_bps                        otherwise
var_bps  = round(BPS * BPS * a * b / (tot^2 * (tot+1)))
std_bps  = isqrt(var_bps)
half     = round(z_bps * std_bps / 100)
lower    = max(0,    mean_bps - half)
upper    = min(BPS,  mean_bps + half)
```

`z_bps = 196` gives the 95% normal-approximation interval. `z_bps = 0`
yields a point estimate. Envelope: `tot <= 100000` keeps
`BPS*BPS*a*b <= ~2.5e17`. `isqrt` is integer Newton iteration bounded at
100 rounds.

## 4. Kalman (1-D)

State `x` and covariance `p` scaled by `SCALE`.

```
predict(q):  x' = x ;  p' = p + q
update(z, r):
  den = p + r                       ; Err when den <= 0
  k   = clamp(round(SCALE * p / den), 0, SCALE)
  x'  = x + round(k * (z - x) / SCALE)
  p'  = round((SCALE - k) * p / SCALE)
```

## Compiler notes (v0.62.2)

* Every `Vec[Int]` element read binds a typed local; no `Str` values are
  compared in the library, so BUG-17 is not reachable.
* Struct payloads cross function boundaries only through leaf
  `_ok_*` / `_err_*` constructors.
* Free functions only; no methods, generics, callbacks, recursive user
  functions or indexed function dispatch.
* All loops are bounded: regression `n <= 1000`, MCMC `steps <= 100000`,
  `isqrt` Newton `<= 100` rounds apart from the LCG stream.

## Test coverage

`tests/test_conformance.xi` (`module ml_tests`) runs 18 test functions:
scale/LCG surface, exact line fit, ridge shrinkage, regression validation,
degenerate rescue, MCMC invariants/reproducibility/bias/validation,
Beta-Binomial mean+mode, interval, point estimate, validation, Kalman
predict/update/guard, constant-target R^2, extrapolation.
