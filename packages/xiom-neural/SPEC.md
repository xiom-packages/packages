# xiom.neural -- Specification

Status: `incubating` (implemented, harness-green on compiler 0.62.2, not
published).
Module: `xiom.neural` (`src/neural.xi`). Manifest: `package.xi` (name
`xiom.neural`, version `0.1.0`). Depends on `xiom.std` for the manifest; the
library imports `xiom.string` (byte scanning, comparison) and `xiom.convert`
(decimal rendering) and uses no other module. Tests:
`tests/test_conformance.xi` (21 checks).

## 1. Scope

Integer-only MLP inference:

- a flat network record (widths, activation codes, concatenated row-major
  weights, concatenated biases) with full shape validation;
- a dense forward pass with guarded dot products, requantization after every
  dot product and the layer bias, then the activation;
- five activations: relu, leaky relu (slope 1/10), sigmoid, tanh and linear,
  all implemented locally as documented integer approximations;
- softmax over the output layer with a piecewise-linear exp approximation;
- argmax prediction (ties to the lowest index) and softmax prediction;
- total and per-layer parameter counting;
- a canonical text dump with a parser that round-trips it exactly.

Pure and deterministic: no floats, no FFI, no I/O, no clock access, no
global state, no allocation beyond the returned vectors. Every loop in the
module advances its index or exits, so parsing arbitrary text and forwarding
arbitrary shapes terminate.

## 2. Non-goals (v0.1.0)

- training, backpropagation, gradients, optimizers, weight initialization;
- convolution, pooling, recurrence, attention, dropout, batch norm;
- graph containers, branching networks, multi-input / multi-output models;
- floating-point inference of any kind;
- persistence formats other than the canonical dump (no optimizer state,
  names or metadata);
- overflow detection outside the documented guards (see section 12);
- secure or arbitrary-precision arithmetic: the envelope is signed 64-bit
  `Int`.

## 3. Data model

`Network` is a flat struct with parallel vectors (no `Vec[StructType]`):

| Field | Type | Meaning |
|---|---|---|
| `n_layers` | `Int` | number of dense layers (>= 1) |
| `n_inputs` | `Int` | `widths[0]` |
| `n_outputs` | `Int` | `widths[n_layers]` |
| `widths` | `Vec[Int]` | `n_layers + 1` positive layer widths |
| `activations` | `Vec[Int]` | one code in [0, 4] per layer |
| `weights` | `Vec[Int]` | concatenated row-major matrices |
| `biases` | `Vec[Int]` | concatenated bias vectors |

Layer `k` owns `widths[k] * widths[k+1]` weights and `widths[k+1]` biases.
Within layer `k`, output `j` and input `i` are at the layer's running weight
offset plus `j * widths[k] + i`.

All values are `Int` in fixed-point units of `1e-4` (section 4).

Fields are implementation detail; build with `neural_network` (or
`neural_parse`) and query with the `neural_*` accessors. Because the fields
are public, every public entry point re-validates the structure
(`_nn_validate`) before indexing.

## 4. Fixed point and rounding

- Scale: `neural_scale() == 10000`; one unit is `1e-4`.
- Product of two scaled values has scale `1e8` (i.e. `1e-4 * 1e-4`).
  Requantization divides the `1e8`-scale dot product by 10000 back to `1e-4`
  scale.
- Every division is `round_half_away_from_zero(a / b)` for `b > 0`
  (`_nn_div_round`): truncating quotient `q = a / b` and remainder
  `r = a % b`; with `mag = |r|`, if `mag > Int_max / 2` or `mag * 2 >= b`
  the result moves one unit away from zero (`q + 1` for `a >= 0`, `q - 1`
  for `a < 0`), else `q`. The doubled remainder is guarded, so no
  denominator can overflow it.

## 5. Layer math (forward pass)

`neural_forward(net, input)`:

1. Validate the network structure (section 11) and
   `input.len() == widths[0]`; reject otherwise before any arithmetic.
2. `cur = input` (copied).
3. For each layer `k` with `ni = widths[k]`, `no = widths[k+1]`, activation
   `act = activations[k]`, for each output `j`:

   `s_j = sum_i w[j,i] * cur[i]`

   with, for every term: a product-overflow check on `w * cur[i]`
   ("weight input product overflows"), then a running-sum check ("dot
   product overflows"). The biased result and next activation are:

   `pre_j = _nn_div_round(s_j, 10000) + b_j`
   `next[j] = activation(act, pre_j)`

   where `+ b_j` is guarded ("bias addition overflows").

4. `cur = next`; after the last layer the result is returned as
   `Ok(cur)` at `1e-4` scale.

The dot product is requantized **before** the bias is added, so weights and
biases are both `1e-4` scale and the accumulator never leaves the requantized
scale. The input and output of every layer are therefore always `1e-4`
scale.

Worked fixture (tests): widths `[2, 2, 1]`, weights row-major
`[5000, 10000, -10000, 2500, 2000, 3000]`, biases `[5000, -1000, 1000]`,
activations `[relu, linear]`, input `[10000, 20000]` (= 1.0, 2.0):

| Layer | Dot (`s`) | `pre` | Bias | Activation | Output |
|---|---|---|---|---|---|
| 0, j=0 | 250000000 | 25000 | 5000 | relu(30000) | 30000 |
| 0, j=1 | -50000000 | -5000 | -1000 | relu(-6000) | 0 |
| 1, j=0 | 60000000 | 6000 | 1000 | linear(7000) | 7000 |

Result `[7000]` (= 0.7).

## 6. Activation approximations

`neural_activation(kind, x)` applies one of the codes below; every formula
uses `_nn_div_round` (section 4) and the `1e-4` scale. Unknown codes are an
error (`neural: unknown activation code`).

| Code | Name | Definition (implemented) | Hand values |
|---|---|---|---|
| 0 | relu | `max(0, x)` | `-6000 -> 0`, `30000 -> 30000` |
| 1 | leaky relu | `x` for `x >= 0`, else `round(x / 10)` (slope 1/10) | `-6000 -> -600`, `-5 -> -1`, `-15 -> -2`, `5 -> 5` |
| 2 | sigmoid | `t = round(x * 10000 / (10000 + |x|))`, `s = round((10000 + t) / 2)` | `0 -> 5000`, `10000 -> 7500`, `-10000 -> 2500`, `30000 -> 8750` |
| 3 | tanh | `2 * sigmoid(2x) - 10000` | `10000 -> 6668`, `-10000 -> -6666`, `0 -> 0` |
| 4 | linear | `x` | `-6000 -> -6000` |

Saturation: sigmoid returns `10000` for `x > Int_max / 10000` and `0` for
`x < -Int_max / 10000` (the `x * 10000` product would overflow otherwise);
tanh returns `±10000` for `|x| > Int_max / 2`. The sigmoid approximation is
within ~0.026 of the true logistic at `x = 1` and is exactly `5000` at 0 and
symmetric-in-value (`s(-x) = 10000 - s(x)` holds only up to rounding; tanh is
not exactly odd because of per-step rounding, e.g. `-10000 -> -6666`).
These are approximations by design; the test suite pins the hand-computed
values above.

## 7. Softmax

`neural_softmax(logits)`:

1. Reject an empty input (`neural: logits must not be empty`).
2. `m = max_i logits[i]`; for each `i`, `shifted_i = logits[i] - m <= 0`
   (a shift underflow is rejected: `neural: logit shift underflows` when
   `m > 0` and `logits[i] < Int_min + m`).
3. `e_i = _nn_exp(shifted_i)` (below); sum with an overflow guard.
4. `p_i = _nn_div_round(e_i * 10000, sum)` with a product guard; each `p_i`
   is in `[0, 10000]`.

`_nn_exp(x)` for `x <= 0` is the piecewise-linear interpolation of `e^x`
between the breakpoints `(0, 10000)`, `(-6931, 5000)`, `(-13863, 2500)`,
`(-20794, 1250)`, `(-27726, 625)`; below `-27726` the result is `0`
(truncation). Each segment is
`y0 - _nn_div_round(dx * drop, 6931)` with `dx` the distance past the
segment start, so the values are hand-computable and monotone.

Hand-computed rows (tests):

| Logits | Shifted | `e` | Probabilities |
|---|---|---|---|
| `[0, 0]` | `[0, 0]` | `[10000, 10000]` | `[5000, 5000]` |
| `[0, 6931]` | `[-6931, 0]` | `[5000, 10000]` | `[3333, 6667]` |
| `[0, 10000]` | `[-10000, 0]` | `[3893, 10000]` | `[2802, 7198]` |
| `[0, 0, 0]` | zeros | `10000` each | `[3333, 3333, 3333]` |

The probabilities sum to `10000` only up to per-entry rounding (the
three-way row sums to 9999). The row is a distribution by construction:
every entry is non-negative and rounds independently.

## 8. Argmax and prediction

- `neural_argmax(values)`: `Ok(index)` of the first occurrence of the
  maximum; empty input is an error (`neural: values must not be empty`).
  Ties therefore go to the lowest index.
- `neural_predict(net, input)`: `neural_forward` then `neural_argmax`; the
  forward-pass errors are passed through unchanged.
- `neural_predict_probs(net, input)`: `neural_forward` then
  `neural_softmax`.

## 9. Parameter counting

- `neural_parameter_count(net) = weights.len() + biases.len()`.
- `neural_weight_count(net)` / `neural_bias_count(net)` return the vector
  lengths.
- `neural_layer_weight_count(net, k)` returns `widths[k] * widths[k+1]` and
  `neural_layer_bias_count(net, k)` returns `widths[k+1]` for
  `k in [0, n_layers)`, else `0`.

For the fixture network: weights 6, biases 3, total 9 parameters.

## 10. Canonical dump grammar

`neural_dump(net)` emits exactly (one `\n`-terminated record per line,
single spaces between tokens; the output always ends with a newline):

```
xiom.neural v1
layers <n>
widths <w0> <w1> ... <wn>
acts <a0> ... <a_{n-1}>
weights <w_0> ... <w_{W-1}>
biases <b_0> ... <b_{B-1}>
end
```

where `W = sum_k widths[k]*widths[k+1]` and `B = sum_k widths[k+1]`. Numbers
are plain decimal (`convert.int_to_string`), negative values carry a leading
`-`; the accepted range is `[-Int_max, Int_max]` (the literal `Int_min` is
not produced). The weights are layer 0's matrix row-major, then layer 1's,
and so on; the same for biases.

Example (the 2-2-1 fixture):

```
xiom.neural v1
layers 2
widths 2 2 1
acts 0 4
weights 5000 10000 -10000 2500 2000 3000
biases 5000 -1000 1000
end
```

`neural_parse` accepts this grammar with any ASCII whitespace (space, LF,
CR, tab) between tokens, including arbitrary leading whitespace. The dump is
canonical: `neural_dump(parse(text))` reproduces `text` when `text` is a
dump; `neural_parse(neural_dump(net))` yields a network with the same shape,
parameters and forward outputs.

## 11. Validation order and error catalog

Validation order (first failure wins):

| Entry point | Order |
|---|---|
| `neural_network` | widths count (>= 2), activation count, per-width positivity, activation range, dimensions / totals overflow, weights length, biases length |
| `neural_forward` | network structure (as `_nn_validate`: layer count, widths count, activation count, widths positivity, activation range, dimensions, weights length, biases length), input length, then per-term product, dot sum, bias add |
| `neural_activation` | kind range |
| `neural_softmax` | emptiness, max scan, per-entry shift underflow, exp sum overflow, sum positivity, product overflow |
| `neural_argmax` | emptiness |
| `neural_dump` | network structure |
| `neural_parse` | magic, version, `layers` keyword, integer layer count, count in `[1, 1024]`, `widths` keyword, integer list, per-width positivity, dimensions / totals overflow, `acts` keyword, integer list, activation range, `weights` keyword, integer list, `biases` keyword, integer list, `end` keyword, end of input |

| Message | Trigger |
|---|---|
| `neural: need at least one layer` | `widths.len() < 2`; malformed `n_layers <= 0` |
| `neural: activation count does not match layer count` | `activations.len() != n_layers` |
| `neural: widths must be positive` | a width `<= 0` |
| `neural: unknown activation code` | code outside `[0, 4]` |
| `neural: dimensions overflow` | width product or parameter total overflows `Int` |
| `neural: weights length does not match the shape` | `weights.len() != W` |
| `neural: biases length does not match the shape` | `biases.len() != B` |
| `neural: input length does not match the input width` | forward input length mismatch |
| `neural: weight input product overflows` | `w * x` leaves the `Int` range |
| `neural: dot product overflows` | the running dot sum leaves the `Int` range |
| `neural: bias addition overflows` | `pre + b` leaves the `Int` range |
| `neural: logits must not be empty` | softmax / argmax on an empty vector (argmax uses `values`) |
| `neural: logit shift underflows` | `logits[i] - max` would underflow |
| `neural: softmax sum overflows` | exp sum leaves the `Int` range |
| `neural: softmax sum must be positive` | defensive invariant (unreachable: at least one exp is > 0) |
| `neural: softmax product overflows` | `e * 10000` leaves the `Int` range (unreachable at this scale) |
| `neural: values must not be empty` | argmax on an empty vector |
| `neural: prediction failed` | defensive invariant (unreachable) |
| `neural: network widths are inconsistent` | `widths.len() != n_layers + 1` |
| `neural: network activations are inconsistent` | `activations.len() != n_layers` |
| `neural: network weights are inconsistent` | `weights.len() != W` |
| `neural: network biases are inconsistent` | `biases.len() != B` |
| `neural: dump must start with xiom.neural` | parse magic mismatch |
| `neural: dump version must be v1` | parse version mismatch |
| `neural: expected layers` / `expected widths` / `expected acts` / `expected weights` / `expected biases` / `expected end` | parse keyword mismatch |
| `neural: layer count must be an integer` | `layers` not followed by an integer |
| `neural: layer count must be positive` | parsed layer count `<= 0` |
| `neural: layer count exceeds the limit` | parsed layer count `> 1024` |
| `neural: widths list is truncated or malformed` | widths list missing a token or containing a non-integer |
| `neural: activation list is truncated or malformed` | acts list malformed |
| `neural: weights list is truncated or malformed` | weights list malformed |
| `neural: biases list is truncated or malformed` | biases list malformed |
| `neural: unexpected trailing tokens` | tokens after `end` |

## 12. Overflow guards

| Path | Guarded? | Contract |
|---|---|---|
| every `w * x` product | yes (`weight input product overflows`) | any inputs |
| dot-product running sum | yes (`dot product overflows`) | any inputs |
| `pre + b` | yes (`bias addition overflows`) | any inputs |
| shape products / parameter totals | yes (`dimensions overflow`) | any widths |
| exp sum | yes (`softmax sum overflows`) | any logits |
| `e * 10000` | yes (`softmax product overflows`) | defensive, `e <= 10000` |
| `x * 10000` in sigmoid | yes, by saturation | any `x` |
| `2 * x` in tanh | yes, by saturation | any `x` |
| parse integer accumulation | yes (`<= Int_max` magnitude) | any token |
| `_nn_div_round` doubling | yes (`mag > Int_max / 2` short-circuit) | any denominator |

## 13. Compatibility notes (compiler 0.62.2)

- Every `Vec[Int]` element read binds the element to a typed local first.
- No `Vec[Str].push` anywhere: the dump is assembled by `Str` concatenation
  with `convert.int_to_string`, and the lexer classifies tokens byte by byte
  without ever building a `Vec[Str]`.
- `Str` values are compared only via `string.str_compare` (BUG 17); the dump
  lexer's keyword match compares bytes and does not use `==` on `Str`.
- `Ok` / `Err` construction is confined to the leaf helpers at the bottom of
  the module (`_ok_net` / `_err_net` / `_ok_str` / `_err_str` / `_ok_ints` /
  `_err_ints` / `_ok_int` / `_err_int`).
- No `&mut Int` parameters: the parser threads its position through returned
  `_NnTok` values (pos / kind / value) and helper return values. The only
  `&mut` parameter is `_nn_read_ints(out: &mut Vec[Int])`, which appends in
  place.
- Free functions only: no methods, generics, callbacks, `self` or indexed
  function-table dispatch; the network holds parallel Vecs.
- Every loop advances an index or exits, so `neural_parse` terminates on any
  input and host memory does not grow beyond the parsed (bounded) shapes.

## 14. Test plan

`tests/test_conformance.xi` (21 checks, all passing):

| # | Check |
|---|---|
| 1 | scale and activation codes are pinned (10000; 0..4) |
| 2 | builder reports the 2-2-1 shape and 9 parameters |
| 3 | builder validates every shape and guards dimensions |
| 4 | relu clamps negatives and rejects unknown codes |
| 5 | leaky relu divides negatives by 10 with half-away rounding |
| 6 | fast sigmoid matches the documented rational values |
| 7 | tanh follows `2*sigmoid(2x)-1` with saturation |
| 8 | linear activation is the identity |
| 9 | hand-computed 2-2-1 forward pass returns 7000 |
| 10 | requantization keeps the 1e-4 scale between layers |
| 11 | forward validates the input and guards product / bias overflow |
| 12 | softmax of equal logits is uniform |
| 13 | softmax matches hand-computed asymmetric rows (3333/6667, 2802/7198) |
| 14 | softmax rejects empty input and guards the max shift |
| 15 | argmax picks the first maximum |
| 16 | predict returns the argmax and predict_probs the softmax |
| 17 | dump emits the canonical text byte for byte |
| 18 | parse + emit round-trips the network and its forward pass |
| 19 | parse rejects a bad magic, version, count and widths |
| 20 | parse rejects bad activations, missing lists and trailing tokens |
| 21 | per-layer accessors are range-safe |
