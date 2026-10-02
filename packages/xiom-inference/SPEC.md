# xiom.inference -- specification (v0.1.0)

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

This document pins the observable behavior of the `xiom.inference` module
(`src/inference.xi`, module `xiom.inference`). Everything here is pure
fixed-point integer arithmetic: no floats, no FFI, no I/O, no global state.
The conformance suite (`tests/test_conformance.xi`, 28 checks) pins every
hand-computable value below.

## 1. Fixed-point scale

- `inference_scale()` returns `10000`; one unit is `1e-4`.
- Every weight, bias, activation, logit and probability in this module is an
  `Int` in those units.
- Division is truncating (toward zero), then adjusted to **round half away
  from zero**: `round_half_away(a/b)` with `b > 0` is `q = a / b`, `r = a % b`;
  if `2*|r| >= b` the result is `q - 1` for `a < 0`, else `q + 1`; otherwise
  `q`. All divisions in the module (requantization, activation curves,
  softmax, quantization) use this one rule.
- The signed 64-bit envelope is `Int`. `Int` minimum is built as
  `0 - Int_max - 1` (the literal does not parse).

## 2. Model descriptor

`inference_model(widths, kinds, activations, weights, biases)` validates and
copies five flat vectors into a `Model`; `Vec[StructType]` is never used.

- `widths`: `n_layers + 1` positive widths; `widths[0]` is the input width,
  `widths[k+1]` the output width of layer `k`.
- `kinds`: `n_layers` kind codes, `0` = `DENSE`, `1` = `ACT`.
- `activations`: `n_layers` codes in `[0, 4]`. For `DENSE` the code is applied
  after requantization and the bias; for `ACT` it is the layer operation.
- `weights`: concatenated row-major dense matrices; the `DENSE` layer `k`
  entry for output `j`, input `i` is at `w_offsets[k] + j*widths[k] + i`.
  The exact total is `sum over dense k of widths[k]*widths[k+1]`.
- `biases`: concatenated dense bias vectors; exact total is
  `sum over dense k of widths[k+1]`.
- `w_offsets` / `b_offsets`: prefix sums of the per-layer counts (`n_layers+1`
  entries each, starting at 0), precomputed by the builder and **re-validated
  by every public entry point** together with all parallel-vector lengths.
  A hand-built `Model` whose offsets drift is rejected with
  `inference: network offsets are inconsistent`.

Builder validation order and messages:

1. `inference: need at least one layer` -- `widths.len() < 2`.
2. `inference: kind count does not match layer count`.
3. `inference: activation count does not match layer count`.
4. `inference: widths must be positive` -- any `widths[k] <= 0`.
5. `inference: unknown layer kind` -- any kind outside `[0, 1]`.
6. `inference: activation layer changes width` -- `ACT` with
   `widths[k] != widths[k+1]`.
7. `inference: unknown activation code` -- any activation outside `[0, 4]`.
8. `inference: dimensions overflow` -- `widths[k] > Int_max / widths[k+1]`
   or a running total would exceed `Int_max`.
9. `inference: weights length does not match the shape`.
10. `inference: biases length does not match the shape`.

Runtime validation (every entry point) re-checks lengths, positivity, kinds,
activation codes, `n_inputs == widths[0]`, `n_outputs == widths[n_layers]`,
the precomputed offsets, and reports `inference: network weights/biases/
widths/kinds/activations/offsets are inconsistent` for the first violation.

## 3. Layer kinds

| Code | Kind | Math |
|---|---|---|
| 0 | `DENSE` | `pre[j] = round_half_away(sum_i w[j,i]*x[i] / 10000) + b[j]`; `out[j] = activation(pre[j])` |
| 1 | `ACT` | `out[j] = activation(x[j])`, `widths[k] == widths[k+1]`, no weights or biases |

## 4. Activations

Applied by `inference_activation(kind, x)`; codes returned by
`inference_act_*()`.

- `0` relu: `x < 0 -> 0`, else `x`.
- `1` leaky relu: `x >= 0 -> x`; otherwise `round_half_away(x / 10)`.
- `2` sigmoid: `x == 0 -> 5000`. For `x > 0`:
  `t = round_half_away(x * 10000 / (10000 + x))`,
  `s = round_half_away((10000 + t) / 2)`. For `x < 0` the same with `|x|`.
  The result is in `[0, 10000]`, `s(-x) = 10000 - s(x)`, and `|x|` beyond
  `Int_max / 10000` saturates to `10000` / `0`.
- `3` tanh: `tanh(x) = 2 * sigmoid(2*x) - 10000`, saturated to `+/-10000`
  for `|x| > Int_max / 2`.
- `4` linear: `x`.

Hand-pinned values: `sigmoid(0) = 5000`, `sigmoid(10000) = 7500`,
`sigmoid(-10000) = 2500`, `sigmoid(30000) = 8750`; `tanh(10000) = 6668`,
`tanh(-10000) = -6666`.

## 5. Softmax and predict

`inference_softmax(logits)`:

1. `maxv = max(logits)`; empty input is `inference: logits must not be empty`.
2. `shifted = x - maxv` (guarded: `inference: logit shift underflows`).
3. `e = exp_approx(shifted)` where `exp_approx` is the piecewise-linear map
   through `(0, 10000)`, `(-6931, 5000)`, `(-13863, 2500)`,
   `(-20794, 1250)`, `(-27726, 625)`, with each segment interpolated by
   `round_half_away(drop * dx / 6931)` and `0` below `-27726`.
4. `probs[i] = round_half_away(e[i] * 10000 / sum(e))`.
   Sum and product overflows are typed errors; entries land in `[0, 10000]`
   and sum to `10000` only up to per-entry rounding.

`inference_argmax(values)`: index of the first maximum; empty input is
`inference: values must not be empty`. `inference_predict` is the argmax of
`inference_forward`; `inference_predict_probs` is the softmax of it.

## 6. Batched and streaming inference

- `inference_batch(model, inputs)`: `inputs` must have a positive length that
  is a multiple of `model.n_inputs` (otherwise
  `inference: batch input length must be a positive multiple of the input
  width`). Row `r` occupies `[r*n_inputs, (r+1)*n_inputs)` and is forwarded
  independently; output rows are concatenated in order.
- `inference_stream(model, data, window, stride)`: repeated window inference
  at starts `p = 0, stride, 2*stride, ...` while `p + window <= data.len()`.
  `window` must equal `model.n_inputs` (`inference: stream window must equal
  the input width`); `stride >= 1` (`inference: stream stride must be
  positive`). Output rows are concatenated in window order.
- `inference_stream_count(data_len, window, stride)`:
  `0` if `data_len < 0`, `window <= 0`, `stride <= 0` or
  `data_len < window`; otherwise `1 + (data_len - window) / stride`.

## 7. Integer quantization (per-tensor shift)

One arithmetic step `2^s` per tensor, `s` in `[0, 62]`:

- `inference_quantize(values, s)`: `q[i] = round_half_away(x[i] / 2^s)`.
- `inference_dequantize(values, s)`: `x'[i] = q[i] * 2^s` (per-element
  overflow guard: `inference: dequantized value overflows`).
- `inference_quantize_error_bound(s)`: `0` for `s = 0`, else `2^(s-1)`.
- `inference_quantize_shift(values, max_abs_q)`: the smallest `s` in
  `[0, 62]` with `max|x[i]| <= max_abs_q * 2^s`; `max_abs_q <= 0` is
  `inference: quantization max magnitude must be positive`, and no fitting
  shift is `inference: no quantization shift in range fits the tensor`.
- `inference_quantize_model(model, s)`: replaces every dense weight `w` by
  `round_half_away(w / 2^s)`; widths, kinds, activations, biases and offsets
  are preserved. `inference_model_weight_absmax` returns the weight peak
  (saturated at `Int_max` for the `Int`-min element) for shift selection.

**Error bound.** For any `x` and any `s` in `[0, 62]`, with
`q = round_half_away(x / 2^s)` and `x' = q * 2^s`:
`|x - x'| <= 2^(s-1)` for `s >= 1`, and `|x - x'| = 0` for `s = 0`.
Proof sketch: `|x - q*2^s| = 2^s * |x/2^s - q|` and half-away rounding gives
`|x/2^s - q| <= 1/2`. Values already multiples of `2^s` round-trip exactly.
For `inference_quantize_model`, dequantizing the new weight tensor with the
same shift therefore bounds each weight error by `2^(s-1)`. The conformance
suite checks the bound elementwise for `s = 2` and the model weight tensor
for `s = 3` (weights `2500 -> 313 -> 2504`, error `4 = 2^2`).

## 8. Canonical text dump

`inference_export_text(model)` emits exactly (ASCII, `\n`-terminated lines,
single spaces, decimal integers):

```
xiom.inference v1
layers <n>
widths <w0> ... <wn>
kinds <k0> ... <k_{n-1}>
acts <a0> ... <a_{n-1}>
weights <...>
biases <...>
end
```

`inference_import_text(text)` accepts ASCII whitespace between tokens and
validates exactly like `inference_model`. The dump is stable:
`export_text(import_text(dump)) == dump` (byte for byte, checked for both
suite fixtures).

Parser errors: `inference: dump must start with xiom.inference`,
`inference: dump version must be v1`, `inference: expected layers`,
`inference: layer count must be an integer`, `inference: layer count must be
positive`, `inference: layer count exceeds the limit` (over 1024),
`inference: expected widths/kinds/acts/weights/biases/end`,
`inference: widths/kind/activation/weights/biases list is truncated or
malformed`, `inference: unexpected trailing tokens`, plus every builder and
structural error above.

## 9. Binary dump

`inference_export_bin(model)` emits:

| Offset | Bytes | Field |
|---|---|---|
| 0 | 4 | magic `XINF` (`88 73 78 70`) |
| 4 | 1 | format version `1` |
| 5 | 8 | `n_layers`, Int64 little-endian two's complement |
| 13 | 8 + 8*(n+1) | widths count + values |
| ... | 8 + 8*n | kinds count + values |
| ... | 8 + 8*n | acts count + values |
| ... | 8 + 8*w_total | weights count + values |
| ... | 8 + 8*b_total | biases count + values |

`inference_import_bin(bytes)` rejects: `inference: binary dump must start
with XINF`, `inference: binary dump version must be v1`,
`inference: binary dump is truncated` (wrong length/count),
`inference: binary dump has trailing bytes`, `inference: tensor size exceeds
the limit` (count above 16777216), `inference: widths/kind/activation/
weights/biases list is truncated or malformed`, and every structural error.
Round-trip is lossless in both directions (bytes and text dumps compared in
the suite, including the zero-weight `ACT` fixture).

## 10. Complexity and termination

- `inference_forward`: `O(sum of dense weight counts)`.
- softmax / argmax / activations: linear / `O(1)`.
- batch: `O(rows * forward)`; stream: `O(windows * forward)`.
- quantize / dequantize / binary codec: `O(tensor)`.
- text parse: `O(tokens)`; every scan step advances or exits, and list reads
  fail on the first non-integer token, so no input can make a read spin.
- binary parse: same, with the explicit `16777216`-entry and `1024`-layer
  caps checked before allocation.

## 11. Out of scope (v0.1.0)

Training, backpropagation, weight initialization, convolution, pooling,
recurrence, dropout, batch normalization, per-channel quantization, float
paths and foreign exchange formats are not implemented. The text and binary
dumps are the only persistence formats.
