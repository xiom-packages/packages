# xiom.neural

> **Status:** `incubating` -- conformance-tested (21/21); not yet published on the XIOM registry.
> **Scope:** deterministic fixed-point MLP inference over scaled integers:
> dense layers with guarded dot products, relu / leaky / sigmoid / tanh /
> linear activations, requantization between layers, softmax, argmax
> prediction, parameter counting and a canonical text dump with parse
> round-trip. No training.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.string`
> and `xiom.convert`; tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.neural` runs a fully-connected network **without floating point**.
Every weight, bias, activation and probability is an `Int` in fixed-point
units of `1e-4` (`neural_scale() == 10000`), every division rounds half away
from zero, and every multiply-before-divide step is explicitly guarded and
documented. The module covers:

- **construction** (`neural_network`): a flat network record -- widths, one
  activation code per layer, concatenated row-major weights and concatenated
  biases -- validated shape by shape;
- **forward pass** (`neural_forward`): dense layers, per-term product
  guards, running dot-product guards, requantization after every dot product
  and the layer bias, then the activation;
- **activations** (`neural_activation`): relu, leaky relu (slope exactly
  `1/10`), a fast rational sigmoid, tanh derived from it, and linear; all
  local integer approximations specified in `SPEC.md`;
- **softmax** (`neural_softmax`): max-shifted logits, a piecewise-linear exp
  approximation with breakpoints at multiples of `ln 2`, exact integer
  normalization;
- **prediction** (`neural_predict`, `neural_predict_probs`, `neural_argmax`):
  class id by argmax (ties to the lowest index) and the output-layer softmax;
- **parameter counting** (`neural_parameter_count` and the per-layer
  helpers): total and per-layer weight / bias counts;
- **canonical dump** (`neural_dump`, `neural_parse`): a deterministic text
  grammar that parses back to an identical network,
  `neural_dump(parse(dump)) == dump`.

No `Float64`, no FFI, no threads, no I/O, no global state, no allocation
beyond the returned vectors. Every parse and forward loop advances or exits,
so hostile input cannot spin. See `SPEC.md` for the exact scale, activation
and dump rules.

## API

| Function | Returns | Description |
|---|---|---|
| `neural_scale()` | `Int` | Fixed-point scale (10000; one unit is 1e-4). |
| `neural_act_relu()` / `_leaky()` / `_sigmoid()` / `_tanh()` / `_linear()` | `Int` | Activation codes 0..4. |
| `neural_network(&widths, &activations, &weights, &biases)` | `Result[Network, Str]` | Validate and copy the flat parts into a network. |
| `neural_n_layers(&net)` / `neural_n_inputs(&net)` / `neural_n_outputs(&net)` | `Int` | Shape accessors. |
| `neural_layer_width(&net, k)` | `Int` | Widths[k], or 0 out of range. |
| `neural_forward(&net, &input)` | `Result[Vec[Int], Str]` | Dense forward pass at 1e-4 scale. |
| `neural_activation(kind, x)` | `Result[Int, Str]` | Apply one activation code. |
| `neural_softmax(&logits)` | `Result[Vec[Int], Str]` | Probabilities in [0, 10000]. |
| `neural_argmax(&values)` | `Result[Int, Str]` | First maximum index. |
| `neural_predict(&net, &input)` | `Result[Int, Str]` | Argmax of the forward output. |
| `neural_predict_probs(&net, &input)` | `Result[Vec[Int], Str]` | Softmax of the forward output. |
| `neural_parameter_count(&net)` | `Int` | Weights + biases. |
| `neural_weight_count(&net)` / `neural_bias_count(&net)` | `Int` | Totals. |
| `neural_layer_weight_count(&net, k)` / `neural_layer_bias_count(&net, k)` | `Int` | Per-layer counts, 0 out of range. |
| `neural_dump(&net)` | `Result[Str, Str]` | Canonical text dump. |
| `neural_parse(text)` | `Result[Network, Str]` | Parse the canonical dump. |

The complete error catalog and the dump grammar are in `SPEC.md`.

## Usage

```xi
use xiom.neural;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // 2-2-1: hidden relu, output linear; input (1.0, 2.0) in 1e-4 units.
  let widths = v3(2, 2, 1);
  let acts = v2(0, 4);
  let weights = v6(5000, 10000, -10000, 2500, 2000, 3000);
  let biases = v3(5000, -1000, 1000);
  let built = neural_network(&widths, &acts, &weights, &biases);
  match built {
    Ok(net) => {
      let input = v2(10000, 20000);
      let out = neural_forward(&net, &input);
      match out {
        Ok(v) => { io.println(convert.int_to_string(v[0])); }, // 7000 = 0.7
        Err(e) => { io.println(e); },
      }
      let text = neural_dump(&net);
      match text {
        Ok(s) => { io.println(s); }, // xiom.neural v1 ... end
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
.\scripts\port.ps1 -Package xiom.neural
```

Expected tail: 21 `[PASS]` lines, `xiom.neural: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`. Verified with the
pinned compiler 0.62.2 and the repo stdlib.

## Limitations

- **Inference only.** Training, backpropagation and weight initialization
  are out of scope for v0.1.0; weights are caller-supplied fixed-point
  integers.
- **Fixed-point only.** Inputs, weights, biases and outputs are all in
  `1e-4` units; the module never sees a float.
- **Fully connected only.** Convolution, pooling, recurrence, dropout and
  batch normalization are not implemented.
- **One network per dump.** The grammar carries a single flat MLP; there is
  no graph container, and layers are strictly sequential.
- **Approximate activations.** Sigmoid and tanh are documented integer
  approximations (`SPEC.md` section 6), not correctly rounded math-library
  values; the conformance suite pins the exact hand-computed outputs.
- **Softmax sums to 10000 only up to per-entry rounding** (each entry is
  rounded independently); see `SPEC.md` section 7.
- **Dump is not a training format.** It records structure and parameters
  only; no optimizer state, names or metadata.
