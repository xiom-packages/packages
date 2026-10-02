# xiom.inference

> **Status:** `incubating` -- conformance-tested (28/28); not yet published on the XIOM registry.
> **Scope:** deterministic fixed-point inference over a parallel-vector model
> descriptor (dense and elementwise-activation layers, precomputed weight
> offsets, guarded forward pass, softmax and argmax predict, batched and
> streaming inference, per-tensor shift quantization with a documented error
> bound, and lossless text/binary dump codecs). No training, no floats.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.string`
> and `xiom.convert`; tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.inference` executes a sequential model **without floating point**.
Every weight, bias, activation, logit and probability is an `Int` in
fixed-point units of `1e-4` (`inference_scale() == 10000`); every division
rounds half away from zero; every multiply-before-divide step is explicitly
guarded and documented. The descriptor is parallel vectors only, with the
per-layer weight and bias offsets precomputed at build time and re-validated
by every entry point.

## Libs inventory

| Lib | Entry points | Description |
|-----|--------------|-------------|
| `inference` | `inference_model`, `inference_forward`, `inference_activation`, `inference_validate`-backed accessors | Optimized forward execution path over the model descriptor: `DENSE` (weights + bias + activation) and `ACT` (elementwise) layers, precomputed offsets, guarded dot products. |
| `predict` | `inference_predict`, `inference_predict_probs`, `inference_argmax`, `inference_softmax` | High-level prediction API: max-shifted softmax and first-maximum argmax over a forward pass. |
| `batch` | `inference_batch`, `inference_stream`, `inference_stream_count` | Batched inference over a flat row-major tensor and streaming sliding-window inference over a signal (stride >= 1). |
| `export` | `inference_export_text`, `inference_import_text`, `inference_export_bin`, `inference_import_bin` | Model export to a canonical text dump and a little-endian binary dump, both strictly validated and lossless (round-trip). |
| `quantize` | `inference_quantize`, `inference_dequantize`, `inference_quantize_shift`, `inference_quantize_error_bound`, `inference_quantize_model`, `inference_model_weight_absmax` | Integer quantization: per-tensor shift `2^s`, half-away rounding, automatic shift selection, model weight quantization, documented bound `|x - x'| <= 2^(s-1)`. |

No `Float64`, no FFI, no threads, no I/O, no global state. Every parse,
forward, batch and stream loop advances or exits; text and binary imports are
additionally capped (1024 layers, 16777216 tensor entries), so hostile input
cannot spin or over-allocate. See `SPEC.md` for the exact scale, layer,
activation, quantization and codec rules.

## API

| Function | Returns | Description |
|---|---|---|
| `inference_scale()` | `Int` | Fixed-point scale (10000; one unit is 1e-4). |
| `inference_kind_dense()` / `inference_kind_activation()` | `Int` | Layer kind codes 0 / 1. |
| `inference_act_relu()` / `_leaky()` / `_sigmoid()` / `_tanh()` / `_linear()` | `Int` | Activation codes 0..4. |
| `inference_model(&widths, &kinds, &activations, &weights, &biases)` | `Result[Model, Str]` | Validate, copy and precompute offsets. |
| `inference_n_layers(&m)` / `inference_n_inputs(&m)` / `inference_n_outputs(&m)` | `Int` | Shape accessors. |
| `inference_layer_width(&m, k)` / `inference_layer_kind(&m, k)` | `Int` | Per-layer width (0 out of range) / kind (-1 out of range). |
| `inference_parameter_count(&m)` / `inference_weight_count(&m)` / `inference_bias_count(&m)` | `Int` | Totals. |
| `inference_layer_weight_count(&m, k)` / `inference_layer_bias_count(&m, k)` | `Int` | Per-layer dense counts, 0 for `ACT` / out of range. |
| `inference_forward(&m, &input)` | `Result[Vec[Int], Str]` | Sequential forward pass at 1e-4 scale. |
| `inference_activation(kind, x)` | `Result[Int, Str]` | Apply one activation code. |
| `inference_softmax(&logits)` | `Result[Vec[Int], Str]` | Probabilities in [0, 10000]. |
| `inference_argmax(&values)` | `Result[Int, Str]` | First maximum index. |
| `inference_predict(&m, &input)` | `Result[Int, Str]` | Argmax of the forward output. |
| `inference_predict_probs(&m, &input)` | `Result[Vec[Int], Str]` | Softmax of the forward output. |
| `inference_batch(&m, &inputs)` | `Result[Vec[Int], Str]` | Flat row-major batch forward. |
| `inference_stream(&m, &data, window, stride)` | `Result[Vec[Int], Str]` | Sliding-window forward; window must equal the input width. |
| `inference_stream_count(data_len, window, stride)` | `Int` | Closed-form window count. |
| `inference_quantize(&values, shift)` / `inference_dequantize(&values, shift)` | `Result[Vec[Int], Str]` | Per-tensor step `2^shift` with half-away rounding. |
| `inference_quantize_shift(&values, max_abs_q)` | `Result[Int, Str]` | Finest shift whose peak fits `max_abs_q`. |
| `inference_quantize_error_bound(shift)` | `Result[Int, Str]` | `2^(shift-1)` (0 for shift 0). |
| `inference_quantize_model(&m, shift)` / `inference_model_weight_absmax(&m)` | `Result[Model, Str]` / `Result[Int, Str]` | Weight-tensor quantization and its peak helper. |
| `inference_export_text(&m)` / `inference_import_text(text)` | `Result[Str, Str]` / `Result[Model, Str]` | Canonical text dump round-trip. |
| `inference_export_bin(&m)` / `inference_import_bin(&bytes)` | `Result[Vec[UInt8], Str]` / `Result[Model, Str]` | Little-endian binary dump round-trip. |

The complete error catalog and both dump grammars are in `SPEC.md`.

## Usage

```xi
use xiom.inference;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // 2-2-1 dense model: hidden relu, output linear; input (1.0, 2.0).
  let built = inference_model(&v3(2, 2, 1), &v2(0, 0), &v2(0, 4),
                              &v6(5000, 10000, -10000, 2500, 2000, 3000),
                              &v3(5000, -1000, 1000));
  match built {
    Ok(m) => {
      let out = inference_forward(&m, &v2(10000, 20000));
      match out {
        Ok(v) => { io.println(convert.int_to_string(v[0])); }, // 7000 = 0.7
        Err(e) => { io.println(e); },
      }
      let text = inference_export_text(&m);
      match text {
        Ok(s) => { io.println(s); }, // xiom.inference v1 ... end
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { return 1; },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom-inference
```

Expected tail: 28 `[PASS]` lines, `xiom.inference: all tests passed`, then
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`. Verified twice with
the pinned compiler 0.62.2 and the repo stdlib.

## Limitations

- **Inference only.** Training, backpropagation and weight initialization are
  out of scope for v0.1.0; weights are caller-supplied fixed-point integers.
- **Fixed-point only.** Inputs, weights, biases, activations and probabilities
  are all in `1e-4` units; the module never sees a float.
- **Sequential and dense only.** Dense and elementwise-activation layers; no
  convolution, pooling, recurrence, residual joins, dropout or batch norm.
- **Quantization is per-tensor shift.** One `2^shift` step per tensor (the
  whole weight tensor for `inference_quantize_model`); no per-channel scales
  and no learned ranges. The bound is `2^(shift-1)`, documented in `SPEC.md`.
- **Approximate activations.** Sigmoid and tanh are documented integer
  approximations (`SPEC.md` section 4), not correctly rounded math-library
  values; the conformance suite pins the exact hand-computed outputs.
- **Softmax sums to 10000 only up to per-entry rounding** (each entry is
  rounded independently); see `SPEC.md` section 5.
- **Binary counts are capped** at 16777216 tensor entries and 1024 layers;
  larger tensors fail closed with a typed error.
