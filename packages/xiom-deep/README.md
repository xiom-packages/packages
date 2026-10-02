# xiom.deep

> **Status:** `incubating` -- pure-XIOM implementation, 24/24 conformance checks
> passing on toolchain 0.62.2 (`scripts/port.ps1 -Package xiom-deep`).
> **Scope:** deep network assembly helpers, residual/skip-connection blocks
> (resnet), convolutional building blocks (convnet), attention/transformer
> blocks, RNN/LSTM/GRU cells, and architecture-specific initialization -- all
> over scaled `Int` vectors (fixed point, scale 1e-4), with deterministic
> in-package LCG initialization and tiny forward passes with parameter-count
> verification.
> **Deps:** stdlib (`xiom.std`); the library imports `xiom.convert` only. No
> FFI, no floats, no `Vec[Float64]`, no I/O.

## What it is

A dependency-light toolbox for assembling small deep architectures in XIOM
without a tensor runtime. Every weight, bias, activation and probability is an
integer in units of `1e-4`; products are requantized with half-away-from-zero
rounding. Models are represented as parallel `Int` vectors (row-major weight
matrices, bias vectors, hidden/cell states) so there is no `Vec[StructType]`
and no global mutable state. Random initialization threads an LCG state
through return values, making every stream reproducible from a seed.

## Libs inventory

| Lib | Status | Description |
|-----|--------|-------------|
| `deep` | implemented | Assembly helpers (`deep_linear`, `deep_mlp2`, `deep_add`), fixed-point primitives (`deep_div_round`, `deep_int_sqrt`, `deep_relu`, `deep_sigmoid`, `deep_tanh`, `deep_softmax`), parameter counters, layer norm and FFN. |
| `resnet` | implemented | `deep_res_identity` (identity skip) and `deep_res_projection` (1x1 projection skip). |
| `convnet` | implemented | `deep_conv1d_valid`, `deep_conv1d_relu_valid`, `deep_max_pool1d`, `deep_conv1d_params`. |
| `transformer` | implemented | `deep_attention_scores` (scaled dot-product), `deep_attention_head`, `deep_ffn`, `deep_layer_norm`. |
| `recurrent` | implemented | `deep_rnn_cell`, `deep_lstm_cell`, `deep_gru_cell` with `LstmState` accessors and RNN/LSTM/GRU parameter counts. |
| `init` | implemented | `deep_init_uniform`, `deep_init_dense` (Xavier), `deep_init_zeros`, `deep_init_ones` over a deterministic in-package LCG. |

## API sketch

```xi
use xiom.deep;
let x = deep_init_ones(2);              // [10000, 10000]
let w = deep_init_dense(2, 2, 1);       // Xavier weights + stream state
let ws = deep_init_values(&w);
let y = deep_linear(&x, &ws, &deep_init_zeros(2), 2);
```

## Tests

```
xiom --run tests/test_conformance.xi
# or, from the repo root:
.\scripts\port.ps1 -Package xiom-deep
```

Expected: 24 `[PASS]` lines then `xiom.deep: all tests passed`, exit 0.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
