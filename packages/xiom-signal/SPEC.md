# xiom.signal SPEC

## Package Overview

`xiom.signal` is a pure-XIOM, FFI-free toolkit for one-dimensional integer
signals: fixed-point window functions, same-length convolution, trailing
moving extrema and zero-crossing counts. One module: `xiom.signal`
(`src/signal.xi`). A "signal" is a flat `Vec[Int]` in sample order; the
module never allocates nested vectors and never stores sample-rate or
timestamp metadata.

## Scope

- Rectangular / Hann / Hamming windows on a fixed 1000-permille scale.
- Elementwise permille weighting of two series (`signal_apply_permille`).
- Same-length causal convolution with a flipped kernel and zero padding
  (`signal_convolve`).
- Trailing moving maximum and minimum with partial windows
  (`signal_moving_max`, `signal_moving_min`).
- Count of sign changes in the non-zero subsequence
  (`signal_zero_crossings`).

## Non-Goals

- No floating-point storage: `Vec[Float64]` is never used (v0.61.3 trap);
  `Float64` appears only as scalars inside the window generators.
- No FFT/DFT, filter design (FIR/IIR coefficients), resampling, modulation,
  noise or spectral estimation.
- No parameterised window families beyond Hann/Hamming (no Kaiser,
  Blackman, Bartlett, Tukey, arbitrary `alpha`).
- No 2-D/multi-channel convolution, strides, dilation or padding modes
  other than zero.
- No streaming/incremental state; every call is a pure transform of a
  caller-owned slice.
- No mutation: all `Vec` parameters are `&Vec[Int]` and every result is a
  fresh value (or a scalar).

## Data Model

The only data type crossing the API is `Vec[Int]` (and `Int` scalars).
There are no structs, no `Vec[Vec[Int]]`, no `Vec[StructType]`, and
therefore no `Vec[fn]` dispatch and no match statements in this module.

## API Signatures

```
pub fn signal_rect_permille(n: Int) -> Vec[Int]
pub fn signal_hann_permille(n: Int) -> Vec[Int]
pub fn signal_hamming_permille(n: Int) -> Vec[Int]
pub fn signal_apply_permille(values: &Vec[Int], weights: &Vec[Int]) -> Vec[Int]
pub fn signal_convolve(values: &Vec[Int], kernel: &Vec[Int]) -> Vec[Int]
pub fn signal_moving_max(values: &Vec[Int], window: Int) -> Vec[Int]
pub fn signal_moving_min(values: &Vec[Int], window: Int) -> Vec[Int]
pub fn signal_zero_crossings(values: &Vec[Int]) -> Int
```

One private helper, `_raised_cosine_permille(n, a, b)`, implements the
shared Hann/Hamming loop; it is not part of the public API.

## Semantics

Let `v` be the input signal, `n = v.len()`, `K = kernel.len()`.

- **`signal_rect_permille(n)`** -- returns `[1000; n]`; `n < 1` returns an
  empty vector.
- **`signal_hann_permille(n)`** -- `n < 1` returns an empty vector;
  `n == 1` returns `[1000]` (degenerate single point). For `n >= 2`,
  `out[i] = round(1000 * (0.5 - 0.5*cos(2*pi*i/(n-1))))` for every `i` in
  `[0, n)`. Endpoints are `0`; for odd `n` the centre is `1000`; the
  sequence is point-symmetric.
- **`signal_hamming_permille(n)`** -- same shape with
  `out[i] = round(1000 * (0.54 - 0.46*cos(2*pi*i/(n-1))))`. Endpoints are
  `80` (`0.54 - 0.46 = 0.08`); for odd `n` the centre is `1000`.
- **`signal_apply_permille(v, w)`** -- `m = min(v.len(), w.len())`; empty
  when either input is empty; otherwise `out[i] = trunc(v[i] * w[i] / 1000)`
  for `i` in `[0, m)`, where `trunc` rounds toward zero.
- **`signal_convolve(v, k)`** -- output length is `n` (same length as the
  input, the "same"-mode convention). `K == 0` returns `[0; n]`. Otherwise,
  for every `i` in `[0, n)`:
  `out[i] = sum_{j=0}^{K-1} k[j] * v[i-j]`, with `v[t]` taken as `0` for
  `t < 0`. The kernel is applied flipped: equivalently
  `out[i] = sum_j v[j] * k[i-j]` truncated to the input length. The first
  `K-1` positions read one or more zero-padded samples.
- **`signal_moving_max(v, window)` / `signal_moving_min(v, window)`** --
  `window < 1` returns an empty vector. Otherwise the result has length `n`
  and, for every `i` in `[0, n)`:
  `start = max(0, i - window + 1)`;
  `out[i] = max/min(v[start..i])`. A window wider than the signal yields
  partial windows; `window == 1` is the identity; ties pick the same value
  (extremum identity, not position).
- **`signal_zero_crossings(v)`** -- `0` for empty or all-zero signals.
  Scanning left to right, zeros are skipped entirely; each consecutive pair
  of non-zero values with opposite signs counts one crossing. A single
  non-zero value (or several of the same sign) counts `0`.

## Rounding Rules

- **Window coefficients round to nearest, halves away from zero.** The
  generators evaluate the closed form in scalar `Float64` and convert with
  `xiom.math.round`, which implements `x >= 0 -> trunc(x + 0.5)` and
  `x < 0 -> trunc(x - 0.5)`. Examples: `round(146.446...) = 146`,
  `round(853.553...) = 854`, `round(80.000...) = 80`.
- **`signal_apply_permille` truncates toward zero**, not to nearest and not
  toward negative infinity: `-1 * 1 / 1000 == 0` (floor would give `-1`),
  `-1500 * 1 / 1000 == -1` (floor would give `-2`).
- **Convolution and extrema involve no rounding** -- pure `Int` arithmetic.
- **Phase computation.** `phase = 2*pi*i/(n-1)`; `n == 1` is special-cased
  (the formula would divide by zero), and the result is pinned to `[1000]`.
  The index is converted with `xiom.convert.int_to_float` (no implicit
  `Int -> Float64` coercion in v0.61.3).

## Edge Cases

| Input | Result |
|---|---|
| `n == 0` or `n < 0` (rect/hann/hamming) | empty vector. |
| `n == 1` (hann/hamming) | `[1000]` (degenerate centre). |
| `n == 2` (hann) | `[0, 0]` (both endpoints are the formula's zeros). |
| `n == 2` (hamming) | `[80, 80]`. |
| Empty series into apply/convolve/extrema | empty vector. |
| Equal-length opposite vector into apply | multiply through, length min. |
| Empty kernel into convolve | `[0; n]` (zero-filled output). |
| Empty signal into convolve with any kernel | empty vector. |
| `window < 1` into moving max/min | empty vector. |
| `window >= n` into moving max/min | partial windows; last position is the extremum of the whole signal. |
| All-zero or constant-sign signal into zero crossings | `0`. |
| Zeros between opposite signs | ignored; the surrounding non-zero values count one crossing. |

## Error Paths

The API is total: no `Result` returns, no contracts, no panics. Every
function is defined for every `Vec[Int]` and every `Int` argument,
including empty signals, `n < 1`, `window < 1` and empty kernels.

## Complexity

| Function | Time | Extra memory |
|---|---|---|
| `signal_rect_permille` | O(n) | O(n) output |
| `signal_hann_permille` / `signal_hamming_permille` | O(n) | O(n) output |
| `signal_apply_permille` | O(min(n, m)) | O(min(n, m)) output |
| `signal_convolve` | O(n * K) | O(n) output |
| `signal_moving_max` / `signal_moving_min` | O(n * window) | O(n) output |
| `signal_zero_crossings` | O(n) | O(1) |

## Test Plan

`tests/test_conformance.xi` (27 deterministic named tests, no I/O beyond
the pass/fail lines; expected series are built with `ivN` helpers and
compared through an elementwise `ints_eq`; every `Vec[Int]` read uses a
typed `let` binding per the v0.61.3 trap).

| Test | Checks |
|---|---|
| rect length/values | `n=1 -> [1000]`; `n=4 -> [1000,1000,1000,1000]`. |
| rect `n < 1` | `n=0` and `n=-3` -> empty. |
| hann values n=5 | `[0,500,1000,500,0]` (endpoints 0, centre 1000). |
| hann symmetry n=9 | `[0,146,500,854,1000,854,500,146,0]` (rounding documented). |
| hann n=1 / n=2 | `[1000]` / `[0,0]`. |
| hann property n=17 | point symmetry `h[i] == h[n-1-i]`, endpoints 0, centre 1000. |
| hamming values n=5 | `[80,540,1000,540,80]` (endpoints 80, centre 1000). |
| hamming rounding n=9 | `[80,215,540,865,1000,865,540,215,80]`. |
| hamming n=1 | `[1000]`. |
| cosine windows `n < 1` | hann and hamming, `n=0` and `n=-4` -> empty. |
| apply basic | `[1000,2000,-3000]` x `[500,250,1000]` -> `[500,500,-3000]`. |
| apply truncation | `[1,-1,-1500,1500,999,-999]` x ones -> `[1,-1,-1,1,0,0]` (toward zero). |
| apply shorter length | stops at `min` length, both orientations. |
| apply empty | empty when either side is empty. |
| convolve identity | kernel `[1]` reproduces the signal. |
| convolve impulse | signal `[0,0,0,5,0,0]`, kernel `[1,2,3]` -> `[0,0,0,5,10,15]`. |
| convolve ramp | kernel `[1,1,1]` on `[0,1,2,3,4]` -> `[0,1,3,6,9]`. |
| convolve asymmetric | kernel `[1,2]` on `[1,0,0,0]` -> `[1,2,0,0]`; `[1,2,3]` on `[1,2,3]` -> `[1,4,10]`. |
| convolve empty inputs | empty kernel -> zeros; empty signal -> empty; both -> empty. |
| moving max identity/w2 | window 1 identity; window 2 on `[3,1,4,1,5]` -> `[3,3,4,4,5]`. |
| moving max negatives/ties | `[-5,-1,-9,-3]` -> `[-5,-1,-1,-3]`; ties `[2,5,5,1]` w=3 -> `[2,5,5,5]`. |
| moving min known | `[3,1,4,1,5]` -> `[3,1,1,1,1]`; negatives; ties. |
| moving extrema partial window | `[3,1,4]` with window 5 and 3 -> max `[3,3,4]`, min `[3,1,1]`. |
| moving extrema edges | window `0`/`-2` and empty input -> empty. |
| zero crossings basic | `[1,-1,2,-3]` -> 3; `[-1,2,-3,4,-5]` -> 4. |
| zero crossings zeros | `[1,0,-1,0,2,0,0,-2]` -> 3; single-sign runs and leading/trailing zeros -> 0. |
| zero crossings constant/empty | all-equal, all-zero, single and empty -> 0. |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.signal
```

Expected: `port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Known Limitations

- **Fixed 1000-scale windows.** Only rect/Hann/Hamming exist; coefficients
  that are not multiples of 0.001 are unrepresentable, and no other window
  family or shape parameter is offered.
- **One-dimensional convolution only.** No 2-D kernels, multi-channel
  signals, strides, dilation or padding modes other than zero; an empty
  kernel silently zero-fills (by design) rather than erroring.
- **No overflow protection.** Convolution products/sums and
  `values[i] * weights[i]` can overflow `Int` (i64) for extreme
  magnitudes; results are then two's-complement arithmetic.
- **Complexity of extrema.** `signal_moving_max/min` is O(n * window), not
  the O(n) monotonic-deque algorithm; fine for small windows, not for
  windows in the millions.
- **No spectral features.** FFT, filter design, resampling, modulation and
  noise are out of scope for this incubating module.
