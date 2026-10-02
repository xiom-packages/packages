# xiom.deep -- Specification (v0.1.0)

Pure-XIOM deep-learning building blocks: residual/skip connections, 1D
convolutional blocks, scaled dot-product attention, RNN/LSTM/GRU cells,
architecture-specific initialization, tiny forward passes and parameter-count
verification. No floats, no FFI, no I/O, no training.

## 1. Fixed-point data model

Every weight, bias, activation and probability is an `Int` in units of
`_DP_SCALE = 10000` (one unit is `1e-4`).

- A dot product `sum_i w[i]*x[i]` accumulates the raw `Int` product and is
  requantized once by `deep_div_round(raw, 10000)`.
- `deep_div_round(a, b)` (for `b > 0`) is truncating division with halves
  rounded **away from zero**: the quotient and non-negative remainder are
  computed, and one is added/subtracted when `2*|remainder| >= b`. Int
  division itself truncates toward zero (LLVM `sdiv`), so `-5/2 => -2` but
  `deep_div_round(-5, 2) => -3`.
- `deep_div_round(a, b) => 0` when `b <= 0`; callers validate divisors.
- Products and running sums are guarded with `_dp_mul_overflows` /
  `_dp_add_overflows`; every guarded failure returns an `Err` instead of
  wrapping.
- `deep_int_sqrt(n)` is the floor of the integer square root (binary search,
  bounded by `floor(sqrt(Int_max)) = 3037000500`); `0` for `n <= 0`.

### Vector conventions

Parallel `Vec[Int]` fields only (never `Vec[StructType]`). Weight matrices are
row-major: element `(row, col)` of a `rows x cols` matrix is at
`row*cols + col`. Layers receive read-only `&Vec[Int]`; owned results are
returned. There is no global mutable state.

## 2. Public types

```xi
type InitStep  = { value: Int; state: Int; }
type InitVec   = { values: Vec[Int]; state: Int; }
type LstmState = { h: Vec[Int]; c: Vec[Int]; }
```

`InitStep`/`InitVec` carry the LCG state after a draw so a stream is threaded
through return values (never a `&mut Int`).

## 3. API

### Fixed-point utilities

| Function | Returns | Notes |
|---|---|---|
| `deep_scale()` | `Int` | `10000`. |
| `deep_div_round(a, b)` | `Int` | Half-away-from-zero rounding division. |
| `deep_int_sqrt(n)` | `Int` | Floor integer square root. |
| `deep_relu(x)` | `Vec[Int]` | Elementwise `max(0, x)`. |
| `deep_sigmoid(x)` | `Int` | `1/2 + (x/(1+\|x\|))/2` in 1e-4 units, `[0,10000]`. |
| `deep_tanh(x)` | `Int` | `2*sigmoid(2x) - 1`, saturates at `+-10000`. |
| `deep_softmax(logits)` | `Result[Vec[Int],Str]` | Max-shifted, piecewise-linear exp, sums to 10000 up to rounding. |

### Deterministic initialization (LCG)

`state' = (state * 1103515245 + 12345) mod 2^31` (same seed -> same stream).

| Function | Returns | Notes |
|---|---|---|
| `deep_lcg_next(state)` | `Int` | One LCG step. |
| `deep_init_next(state, bound)` | `InitStep` | Draw in `[0, bound)`. |
| `deep_init_uniform(n, lo, hi, state)` | `InitVec` | `n` values in `[lo, hi]`. |
| `deep_init_dense(fan_in, fan_out, state)` | `InitVec` | Xavier: `fan_in*fan_out` weights in `[-L, L]`, `L = floor(sqrt(6*scale^2/(fan_in+fan_out)))`. |
| `deep_init_zeros(n)` / `deep_init_ones(n)` | `Vec[Int]` | Exact 0 / 10000 fills. |
| `deep_init_values(iv)` / `deep_init_state(iv)` | `Vec[Int]` / `Int` | Extract from an `InitVec`. |

### Assembly

| Function | Shape / semantics |
|---|---|
| `deep_linear(x, w, b, n_out)` | `out[j] = round(sum_i w[j,i]*x[i]/scale) + b[j]`; `w` is `n_out x x.len()`, `b` is `n_out`. |
| `deep_mlp2(x, w1, b1, h, w2, b2, n_out)` | `linear(relu(linear(x)))`. |
| `deep_add(a, b)` | Elementwise sum, equal lengths. |
| `deep_dense_params(n_in, n_out)` | `n_in*n_out + n_out`. |
| `deep_conv1d_params(in_ch, out_ch, k)` | `out_ch*in_ch*k + out_ch`. |
| `deep_rnn_params(input, hidden)` | `hidden*(input+hidden) + hidden`. |
| `deep_lstm_params(input, hidden)` | `4*hidden*(input+hidden) + 4*hidden`. |
| `deep_gru_params(input, hidden)` | `3*hidden*(input+hidden) + 3*hidden`. |

### Residual blocks

| Function | Semantics |
|---|---|
| `deep_res_identity(x, w1, b1, h, w2, b2)` | `relu(F(x) + x)`, `F` a two-layer relu MLP; `x.len() == h`. |
| `deep_res_projection(x, w1, b1, h, w2, b2, n_out, ws, bs)` | `relu(F(x) + Ws*x + bs)`; `ws` is `n_out x n_in`. |

### Convolutional blocks

| Function | Semantics |
|---|---|
| `deep_conv1d_valid(input, kernel, bias)` | Valid 1D conv, `out.len() = n-k+1`, `bias` a scalar; products/sums guarded. |
| `deep_conv1d_relu_valid(input, kernel, bias)` | The same followed by relu. |
| `deep_max_pool1d(x, k, stride)` | Strided max pooling; windows while `start+k <= n`. |

### Recurrent cells

| Function | Semantics |
|---|---|
| `deep_rnn_cell(x, h, wx, wh, b)` | `h' = tanh(Wx x + Wh h + b)`; `wx` `hh x xx`, `wh` `hh x hh`. |
| `deep_lstm_cell(x, h, c, w, b, hidden)` | Gate order `i,f,g,o`; `w` is `4*hidden x (xx+hidden)` row-major, `b` is `4*hidden`; `c' = round(f*c/S) + round(i*g/S)`, `h' = round(o*tanh(c')/S)`. |
| `deep_lstm_h(s)` / `deep_lstm_c(s)` | Hidden / cell vectors of an `LstmState`. |
| `deep_gru_cell(x, h, wz, wr, wh, bz, br, bh, hidden)` | `z,r = sigmoid`; `cand = tanh(Wh [x, r*h] + bh)`; `h' = round(((S-z)*h + z*cand)/S)`. |

### Attention / transformer

| Function | Semantics |
|---|---|
| `deep_attention_scores(q, keys, key_dim)` | `score_j = round(round(q.keys_j/S)/floor(sqrt(d)))`. |
| `deep_attention_head(q, keys, values, key_dim, val_dim)` | `softmax(scores)` weighted sum of `values` (`n x val_dim`). |
| `deep_ffn(x, w1, b1, h, w2, b2, n_out)` | Alias of `deep_mlp2`. |
| `deep_layer_norm(x)` | `out_i = round((x_i - mean)*S/floor(sqrt(var)))`; constant input -> zeros. |

## 4. Error cases

Every fallible entry point returns `Err("deep: ...")`; messages are stable and
asserted in the tests. Categories:

- **Emptiness**: empty linear input, empty softmax logits, empty rnn/gru
  input, empty layer-norm input, empty conv kernel.
- **Shape**: weight/bias/state length mismatches; ragged attention key matrix;
  query dimension mismatch; `val_dim <= 0`; residual identity width mismatch;
  conv/pool input shorter than the window.
- **Range**: non-positive output widths and pool/stride sizes; `deep_div_round`
  with a non-positive divisor (returns 0 without error); `deep_int_sqrt` of a
  non-positive value (returns 0 without error).
- **Overflow**: any guarded dot product, product, sum or bias addition; huge
  shape products (`_dp_mul_overflows`).

`Ok`/`Err` are constructed only in the leaf helpers at the bottom of
`src/deep.xi` (`_ok_int`, `_err_int`, `_ok_ints`, `_err_ints`, `_ok_lstm`,
`_err_lstm`, `_ok_gates`, `_err_gates`).

## 5. Determinism and termination

- Initialization is a pure function of the seed: `deep_init_uniform` and
  `deep_init_dense` called twice with equal arguments produce equal vectors and
  equal successor states.
- Every loop in the module either advances its index/offset or exits on a
  bounded guard, so no input can cause a non-terminating scan.

## 6. Tests

`tests/test_conformance.xi` (module `deep_tests`) runs 24 deterministic checks
with hand-computed fixtures; no external files, no I/O beyond the test runner.
Expected: 24 `[PASS]` lines then `xiom.deep: all tests passed`, exit 0.

## 7. Out of scope (v0.1.0)

Training/backpropagation, floating point, multi-channel 2D convolution,
batched tensors, persistence formats, drop-out and batch normalization.
