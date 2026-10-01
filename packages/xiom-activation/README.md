# xiom.activation

> **Status:** `incubating` -- conformance-tested (24/24); not yet published on the XIOM registry.
> **Scope:** fixed-point activation functions and their derivatives for
> integer neural-network code (`relu`, leaky relu, elu, `sigmoid`, `tanh`,
> softmax) at scale `1e-4`, with documented integer approximations,
> saturation at `+-10000` and overflow guards.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports nothing; tests
> use `xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.activation` evaluates the common activation functions **without floating
point**. Every argument, activation value and derivative is an `Int` in units
of `1e-4` (`activation_scale() == 10000`), every division truncates toward
zero, and every activation output saturates at `+-10000` (`+-1.0`) so it can
feed straight into fixed-point matrix code without overflow surprises.

- **`relu`, leaky relu, elu** are exact piecewise integer formulas: slopes
  and the elu coefficient are basis-point parameters clamped to `[0, 10000]`.
- **`sigmoid` and `tanh`** are built from an integer exponential through the
  exact identities `sigmoid(x) = 1 / (1 + e^-x)` and
  `tanh(x) = (1 - e^-2x) / (1 + e^-2x)`; both are monotone and saturate.
- **`exp`** uses repeated squaring of `(1 - x / (1024 * 10^4))` (ten rounded
  fixed-point squarings plus a reciprocal), never Taylor series; it is
  monotone, returns `0` at or below `-15.0`, and its measured worst-case
  absolute error is below 6 units (documented bound 8).
- **`softmax`** subtracts the maximum logit, exponentiates with the same
  approximation, floors each share and gives the residue to the first
  maximum element, so the returned vector sums to **exactly** `10000`.
- **Derivatives** come with each activation: exact bps slopes for relu,
  leaky relu and elu, value-based formulas for sigmoid (`s(10000-s)/10000`)
  and tanh (`10000 - t*t/10000`), and the diagonal/off-diagonal Jacobian
  entries for softmax as separate helpers.

No `Float64`, no FFI, no threads, no I/O, no global state, no allocation
beyond the returned vectors. Every loop is a bounded counter. See `SPEC.md`
for the exact integer steps, rounding rules, accuracy bounds and envelope.

## API

| Function | Returns | Description |
|---|---|---|
| `activation_scale()` / `activation_saturation()` | `Int` | Fixed-point scale and output bound (10000). |
| `activation_x_limit()` | `Int` | Scalar input envelope (1000000000). |
| `activation_exp_floor()` / `activation_exp_steps()` | `Int` | Exp floor (-150000) and squaring count (10). |
| `activation_softmax_x_limit()` | `Int` | Softmax logit envelope (1000000). |
| `activation_exp(x)` | `Int` | `10000 * e^x` for `x <= 0`; clamps `x >= 0` to 10000. |
| `activation_relu(x)` / `activation_relu_derivative(x)` | `Int` | ReLU and its subgradient (0 at x == 0). |
| `activation_leaky_relu(x, slope_bps)` | `Int` | Leaky ReLU with slope in basis points. |
| `activation_leaky_relu_derivative(x, slope_bps)` | `Int` | Leaky ReLU slope (10000 / slope_bps / 0). |
| `activation_elu(x, alpha_bps)` | `Int` | ELU with basis-point alpha. |
| `activation_elu_derivative(x, alpha_bps)` | `Int` | `10000` for `x >= 0`, `alpha * e^x` below. |
| `activation_sigmoid(x)` / `activation_sigmoid_derivative(x)` | `Int` | Logistic sigmoid and `s(10000-s)/10000`. |
| `activation_tanh(x)` / `activation_tanh_derivative(x)` | `Int` | Hyperbolic tangent and `10000 - t*t/10000`. |
| `activation_softmax(&logits)` | `Result[Vec[Int], Str]` | Probabilities that sum to exactly 10000. |
| `activation_softmax_diag_derivative(s)` | `Int` | Jacobian diagonal `s(10000-s)/10000`. |
| `activation_softmax_cross_derivative(s_i, s_j)` | `Int` | Jacobian off-diagonal `-s_i*s_j/10000`. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.activation;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // Fixed point: 1.0 == 10000.
  io.println(convert.int_to_string(activation_relu(5000)));            // 5000
  io.println(convert.int_to_string(activation_leaky_relu(-10000, 1000))); // -1000
  io.println(convert.int_to_string(activation_sigmoid(0)));            // 5000
  io.println(convert.int_to_string(activation_tanh(10000)));           // 7611
  var logits = Vec[Int].new();
  logits.push(0);
  logits.push(-10000);
  let probs = activation_softmax(&logits);
  if probs.is_ok {
    let p = probs.value;
    io.println(convert.int_to_string(p[0]) + " " + convert.int_to_string(p[1])); // 7312 2688
  }
  return 0;
}
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: twenty-four `[PASS]` lines, then
`xiom.activation: all tests passed`, exit 0.

## Install / publish

```
xiom pkg install xiom.activation@0.1.0   # consumer, from the XIOM registry
xiom pkg publish                         # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Until `v0.1.0` is published, build from this repository:

```
.\scripts\port.ps1 -Package xiom.activation
```

Expected tail: 24 `[PASS]` lines, `xiom.activation: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integer fixed-point only.** Inputs and outputs are `Int` in units of
  `1e-4`; callers must quantize real data first and document the rounding
  (every division truncates toward zero).
- **Documented approximations.** The exponential's absolute error is bounded
  by 8 units; sigmoid by 5, tanh by 8, the tanh derivative by 12 basis
  points (all measured well below the bounds, see `SPEC.md`).
- **Saturation.** All activation outputs are clamped to `[-10000, 10000]`;
  a network that needs wider linear ranges must rescale around this module.
- **Scalar envelope.** `|x| <= 10^9` for scalar activations, `|logit| <= 10^6`
  and at most `10^6` logits per softmax call. Values outside the envelope are
  clamped (scalars) or rejected (softmax).
- **Softmax is not bit-exact softmax.** It is the floored fixed-point
  normalization with an exact 10000 sum; per-element error is bounded by the
  exponential's bound plus at most one unit of truncation, with the rounding
  residue assigned to the first maximum element (ties can differ by one unit).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
