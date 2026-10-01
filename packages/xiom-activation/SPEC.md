# xiom.activation -- specification

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

This document pins the formulas, integer steps, rounding rules, accuracy
bounds and envelopes implemented in `src/activation.xi`. Every fixture in
`tests/test_conformance.xi` is generated from the rules below.

## 1. Number format and conventions

- Fixed point: one unit is `1e-4`, so `10000` units represent `1.0`.
  `activation_scale() == 10000`.
- All divisions are `Int` divisions that **truncate toward zero**
  (compiler v0.62.x semantics). A "round-half-up" step is written as
  `(a + b / 2) / b` for `a >= 0`.
- Activation outputs saturate at `+-10000`; `activation_saturation() == 10000`.
- Scalar inputs live in `|x| <= activation_x_limit() == 10^9`. Values outside
  the envelope are clamped before any multiply (documented per function).
- Slope and alpha parameters are basis points clamped to `[0, 10000]` by
  `_act_clamp_bps` (10000 == 1.0).
- No floating point, no FFI, no recursion; every loop runs a fixed or bounded
  number of iterations.

## 2. Constants

| Name | Value | Meaning |
|---|---|---|
| `_ACT_SCALE` | 10000 | fixed-point scale (`1e-4`) |
| `_ACT_SAT` | 10000 | output saturation bound (`1.0`) |
| `_ACT_X_LIMIT` | 1000000000 | scalar input envelope (`100.0`) |
| `_ACT_EXP_SCALE` | 1000000 | exponential base scale (`10^6`) |
| `_ACT_EXP_T_DIV` | 10240000 | `1024 * 10^4` (squaring count times scale) |
| `_ACT_EXP_T_HALF` | 5120000 | `_ACT_EXP_T_DIV / 2` |
| `_ACT_EXP_SQ_HALF` | 500000 | `_ACT_EXP_SCALE / 2` |
| `_ACT_EXP_PROD` | 10000000000 | `_ACT_EXP_SCALE * _ACT_SCALE` (`10^10`) |
| `_ACT_EXP_FLOOR` | -150000 | `exp` input floor (`-15.0`) |
| `_ACT_EXP_STEPS` | 10 | fixed-point squarings (`2^10 = 1024`) |
| `_ACT_SAT_SQ` | 100000000 | `_ACT_SAT * _ACT_SAT` (`10^8`) |
| `_ACT_SOFTMAX_X_LIMIT` | 1000000 | softmax logit envelope (`100.0`) |
| `_ACT_SOFTMAX_N_LIMIT` | 1000000 | softmax length limit |

## 3. The integer exponential

`activation_exp(x)`:

1. `x >= 0` returns `10000` (the public domain is `x <= 0`; the positive
   branch is clamped and documented).
2. `x <= -150000` returns `0` (`e^-15 = 3.06e-7`, i.e. `0.003` units).

`_act_exp_nonpos(x)` for `-150000 < x < 0`:

```
ax = -x
t  = (ax * 10^6 + 5 120 000) / 10 240 000      // round(ax / 10.24)
v  = 10^6 + t
repeat 10 times:
  v = (v * v + 500 000) / 10^6                // rounded squaring
return 10^10 / v                              // truncating reciprocal
```

Derivation: `v0 / 10^6 = 1 + round(ax / (1024 * 10^4))` approximates
`1 - x / (1024 * 10^4)`, and ten squarings raise it to the `1024`-th power:
`(1 - x / (1024 * 10^4))^1024 ~= e^x`. The final reciprocal converts the
`10^6`-scaled result back to `1e-4` units.

Rounding and accuracy (measured on the implementation, see
`activation_exp` fixtures):

- The half-up `t` step contributes at most `0.5 / 10^24` relative error in
  the base, amplified by `1024` to at most `0.051 %` of the result; the
  squaring roundings and final truncation add under `1` unit.
- Worst measured absolute error over the whole domain: **5.82 units**
  (`x = -128`), i.e. below `0.0006` of full scale. Documented bound: **8
  units**.
- Relative error stays below `0.8 %` for `x >= -40000` and below `3.3 %` for
  `x >= -80000`; it only affects values whose absolute size is a few units.
- Monotone non-decreasing in `x` (rounding, squaring and reciprocal are each
  monotone).

Overflow safety: `ax * 10^6 <= 1.5e11`; the largest squared term (the tenth
squaring at `x = -150000`) is below `2.95e18 < Int::MAX (9.22e18)`; `v` is
always at least `10^6`, so the final division is safe.

Fixtures: `exp(0) = 10000`, `exp(-5000) = 6068`, `exp(-10000) = 3678`,
`exp(-20000) = 1356`, `exp(-30000) = 499`, `exp(-60000) = 25`,
`exp(-100000) = 0`, `exp(-150000) = 0`.

## 4. ReLU, leaky ReLU, ELU

```
relu(x)        = 0                     if x <= 0
               = x                     if 0 < x < 10000
               = 10000                 if x >= 10000

leaky_relu(x, s) = 10000               if x >= 10000
                 = x                   if 0 < x < 10000
                 = (s * clamp(x)) / 10000, clamped to >= -10000   otherwise
                   with s in [0, 10000] and clamp(x) >= -10^9

elu(x, a)      = 10000                 if x >= 10000
               = x                     if 0 <= x < 10000
               = (a * (exp(x) - 10000)) / 10000                  otherwise
                   with a in [0, 10000]
```

- `relu` is exact. `leaky_relu`'s negative branch truncates toward zero; its
  magnitude is at most `10000` because `s <= 10000` and the input is clamped.
- `elu`'s negative branch is bounded below by `-a >= -10000` (since
  `exp(x) >= 0`), so no separate clamp is needed; the exponential's error
  makes it accurate to well under one unit (the factor `e^x - 1` is smallest
  exactly where the absolute exponential error is smallest).
- Subgradients at `x == 0` are pinned to `0` for relu and leaky relu
  (consistent), `10000` for elu (right branch).

## 5. Sigmoid and tanh

Both use the exponential of section 3 through exact identities:

```
sigmoid(x) = 10^8 / (10000 + exp(-x))        if x >= 0
           = (exp(x) * 10000) / (10000 + exp(x))   if x < 0
tanh(x)    = ((10000 - e) * 10000) / (10000 + e)  with e = exp(-2x),  x > 0
           = -(the same at -x)                     x < 0
           = 0                                     x == 0
```

`|x| >= 10^9` saturates immediately (`sigmoid` to `10000`/`0`, `tanh` to
`+-10000`); values below `-75000` already return the exact saturation because
`exp` hits the `-150000` floor at doubled arguments.

Accuracy (measured against `Float64` references; documented bounds):

| Function | Measured worst case | Documented bound |
|---|---|---|
| `sigmoid` | 3 units | 5 units (`5e-4`) |
| `tanh` | 6 units | 8 units (`8e-4`) |
| `sigmoid_derivative` | 2 bps | 5 bps |
| `tanh_derivative` | 9 bps | 12 bps |

`sigmoid` is monotone non-decreasing and maps `0 -> 5000`; `tanh` is odd
(`f(-x) == -f(x)`), monotone non-decreasing, and maps `0 -> 0`. Both stay in
`[0, 10000]` / `[-10000, 10000]`.

Fixtures: `sigmoid(10000) = 7311`, `sigmoid(20000) = 8805`,
`sigmoid(30000) = 9524`, `sigmoid(60000) = 9975`, `sigmoid(-10000) = 2688`,
`sigmoid(-20000) = 1194`, `sigmoid(-30000) = 475`, `tanh(10000) = 7611`,
`tanh(20000) = 9638`, `tanh(30000) = 9950`, `tanh(40000) = 9994`,
`tanh(-10000) = -7611`.

## 6. Softmax

`activation_softmax(&logits)`:

1. Reject an empty vector, more than `10^6` elements, or any
   `|logit| > 10^6` with `Err("activation: ...")`.
2. `m = max(logits)`.
3. `e_i = exp(logit_i - m)` for every `i` (arguments are in `[-2e6, 0]`; the
   maximum element gets exactly `10000`).
4. `out_i = (e_i * 10000) / sum(e)` (truncating division).
5. `total = sum(out)`, `r = 10000 - total`; the **first** index attaining
   the maximum `e_i` receives `out_i + r`.

Properties:

- `sum(out) == 10000` exactly: each floor loses less than one unit, so
  `total <= 10000`; `r >= 0`, and since `total - out_top = sum of the other
  floors >= 0`, the top entry plus `r` equals `10000 - sum(others) <= 10000`.
  No overflow: `e_i * 10000 <= 10^8` and `total <= n * 10^4 <= 10^10`.
- Every entry lies in `[0, 10000]`.
- Order preservation: `out` is non-decreasing along the (stable) logit order;
  ties can differ by one unit because only the first maximum gets the residue.
- Paired with the section-3 bound, each pre-normalization value is within
  8 units of `10000 * e^(logit_i - m)`; per-element probabilities are
  therefore within `8` units of the ideal floored normalization plus the
  residue rule.

Fixtures (exact): `[0, 0] -> [5000, 5000]`,
`[0, -10000] -> [7312, 2688]`, `[0, -20000] -> [8806, 1194]`,
`[0, -30000] -> [9525, 475]`, `[5000, 4000] -> [5251, 4749]`,
`[4000, 2000, 1000] -> [3907, 3199, 2894]`,
`[2000, 2000, 2000] -> [3334, 3333, 3333]`,
`[1000, 2000, 3000, 4000, 5000] -> [1620, 1791, 1980, 2187, 2422]`.

Error case messages:

| Condition | Message |
|---|---|
| empty vector | `activation: softmax requires a non-empty vector` |
| length > 10^6 | `activation: softmax input exceeds the length limit` |
| `logit > 10^6` or `logit < -10^6` | `activation: softmax logit is out of range` |

(The exact literal is `activation: softmax logit out of range`.)

## 7. Derivatives

All derivatives are slopes in the same `1e-4` units (10000 == 1.0).

```
relu_derivative(x)            = 10000 if x > 0 else 0
leaky_relu_derivative(x, s)   = 10000 if x > 0; s if x < 0; 0 if x == 0
elu_derivative(x, a)          = 10000 if x >= 0; (a * exp(x)) / 10000 if x < 0
sigmoid_derivative(x)         = (s * (10000 - s)) / 10000,  s = sigmoid(x)
tanh_derivative(x)            = 10000 - (t * t) / 10000,  t = tanh(x)
softmax_diag_derivative(s)    = (s * (10000 - s)) / 10000, clamped s in [0, 10000]
softmax_cross_derivative(a,b) = -((a * b) / 10000),       clamped a, b in [0, 10000]
```

The sigmoid/tanh derivatives are evaluated from the returned activation
values, so they are exactly consistent with the forward pass (including its
approximation error). Ranges: sigmoid derivative `[0, 2500]` (peak 2500 at
`x == 0`), tanh derivative `[0, 10000]` (peak 10000 at `x == 0`), softmax
Jacobian entries in `[-2500, 0]` (diagonal) and `[-10000, 0]` (extreme
cross term).

Fixtures: `sigmoid_derivative(0) = 2500`, `sigmoid_derivative(10000) = 1965`,
`sigmoid_derivative(20000) = 1052`, `sigmoid_derivative(60000) = 24`,
`tanh_derivative(0) = 10000`, `tanh_derivative(10000) = 4208`,
`tanh_derivative(20000) = 711`, `elu_derivative(-10000, 10000) = 3678`,
`softmax_diag_derivative(5000) = 2500`,
`softmax_cross_derivative(5000, 5000) = -2500`.

## 8. Envelope and overflow analysis

| Operation | Worst-case intermediate | Bound |
|---|---|---|
| `slope * x` (leaky/elu derivative) | `10^4 * 10^9 = 10^13` | safe |
| `(v * v)` in exp squaring | `< 2.95 * 10^18` | `< 9.22 * 10^18` |
| `e * 10000` (softmax) | `10^8` | safe |
| `10000 * e` (sigmoid negative) | `10^8` | safe |
| `(10000 - e) * 10000` (tanh) | `10^8` | safe |
| softmax exponential sum | `<= n * 10^4 <= 10^10` | safe |
| softmax `x - max` | `>= -2 * 10^6` | safe |

No step can silently overflow inside the documented envelope; scalar inputs
outside the `10^9` envelope are clamped first, and softmax rejects logits
outside its envelope.

## 9. Complexity

Every function is `O(1)` with the exponential's fixed cost (10 squarings and
one division); `activation_softmax` is `O(n)` with that cost per element.
All loops are bounded counters that strictly make progress (no `while true`).
