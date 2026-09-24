# xiom.signal

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** integer-friendly window functions (rect / Hann / Hamming),
> same-length convolution, moving extrema and zero-crossing counts over
> flat `Vec[Int]` signals.
> **Deps:** `xiom.std` only (`deps` declares the platform dependency; the
> library module imports `xiom.convert` and `xiom.math` from it for scalar
> `Float64` trig -- no FFI).

## What it is

`xiom.signal` is a pure-XIOM toolkit for one-dimensional integer signals.
A signal is a flat `Vec[Int]` in sample order; there are no timestamps, no
sample-rate metadata and no floating-point storage. Window coefficients are
fixed-point permille integers on a 1000 scale, generated with scalar
`Float64` math and stdlib `cos` where the closed form needs them. Every
function is total: empty signals, non-positive window lengths and
zero-filled edges all have documented results, and none of them panic.

The module exposes seven free functions: three window generators
(`signal_rect_permille`, `signal_hann_permille`, `signal_hamming_permille`),
one elementwise weighting (`signal_apply_permille`), one convolution
(`signal_convolve`), two trailing extrema (`signal_moving_max`,
`signal_moving_min`) and one event counter (`signal_zero_crossings`).

## API

| Function | Returns | Description |
|---|---|---|
| `signal_rect_permille(n)` | `Vec[Int]` | `n` copies of `1000`; `n < 1` yields an empty vector. |
| `signal_hann_permille(n)` | `Vec[Int]` | `round(1000 * (0.5 - 0.5*cos(2*pi*i/(n-1))))`; endpoints `0`, odd centre `1000`; `n == 1` yields `[1000]`; `n < 1` empty. |
| `signal_hamming_permille(n)` | `Vec[Int]` | `round(1000 * (0.54 - 0.46*cos(2*pi*i/(n-1))))`; endpoints `80`, odd centre `1000`; `n == 1` yields `[1000]`; `n < 1` empty. |
| `signal_apply_permille(values, weights)` | `Vec[Int]` | `out[i] = trunc(values[i] * weights[i] / 1000)`; stops at the shorter length; empty when either input is empty. |
| `signal_convolve(values, kernel)` | `Vec[Int]` | Same length as `values`; `out[i] = sum_j kernel[j] * values[i-j]` with `values[t] = 0` for `t < 0` (flipped kernel, zero-padded edge). Empty kernel zero-fills; empty input empty. |
| `signal_moving_max(values, window)` | `Vec[Int]` | Trailing maximum of the `min(i+1, window)` samples ending at `i`; `window == 1` identity; `window < 1` empty; empty input empty. |
| `signal_moving_min(values, window)` | `Vec[Int]` | Trailing minimum, same edges as above. |
| `signal_zero_crossings(values)` | `Int` | Sign flips between consecutive non-zero values; zeros are skipped; `0` for empty / constant-sign / all-zero signals. |

## Usage

```xi
use xiom.signal;

let v = ...;                                  // any Vec[Int] signal

let hann = signal_hann_permille(9);           // [0,146,500,854,1000,854,500,146,0]
let windowed = signal_apply_permille(&v, &hann);
let smoothed = signal_convolve(&v, &signal_rect_permille(3)); // 3-point box sum
let peaks = signal_moving_max(&v, 5);         // trailing 5-sample maximum
let flips = signal_zero_crossings(&v);        // sign changes, zeros ignored
```

## Units and rounding

- **Permille = 1000.** A coefficient of `1000` means `1.0`; `500` means
  `0.5`. This is the only scale in the module -- there is no fractional
  fixed-point type.
- **Windows round half away from zero.** Hann/Hamming values are computed in
  scalar `Float64` (`round(1000 * (a - b*cos(phase)))` via `xiom.math.round`):
  `0.5 -> 1`, `-0.5 -> -1`. Hamming endpoints are `0.54 - 0.46 = 0.08`, i.e.
  `80`; the Hann/Hamming centre of an odd-length window is `1000`.
- **Weights truncate toward zero.** `signal_apply_permille` uses native
  integer division, so `1 * -1 / 1000 == 0` and `-1500 * 1 / 1000 == -1`
  (truncation, not floor).
- **Convolution and extrema are exact.** No rounding is involved: products
  and sums are ordinary `Int` arithmetic.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.signal
```

Expected: the namespaced module passes the section-4 namespace rule, 27
`[PASS]` lines, and a final
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Fixed 1000-scale windows only.** `signal_rect_permille`,
  `signal_hann_permille` and `signal_hamming_permille` are the only window
  generators; there is no parameterised Kaiser/Blackman/Bartlett family, no
  arbitrary `alpha`, and no fractional (e.g. Q15/Q31) scale. Coefficients
  that are not multiples of 0.001 cannot be represented.
- **One-dimensional only.** Signals are flat `Vec[Int]`; convolution and
  extrema do not support 2-D kernels, multi-channel axes, strides or
  padding modes other than zero.
- **No overflow guards.** `signal_convolve` sums `values[i-j] * kernel[j]`
  and `signal_apply_permille` computes `values[i] * weights[i]`; extreme
  magnitudes can overflow `Int` (i64). Inputs are used as given.
- **Eager materialization.** Every transform allocates a fresh output
  vector of (up to) the input length; there is no streaming/incremental API
  and no in-place variant.
- **Single-threaded.** No locks, atomics or async variants; callers
  serialize access.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
