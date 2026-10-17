# xiom.torch -- Specification (0.1.0)

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

## 1. Scope and design

The tensor-level surface of the XIOM ML stack:

* **Pure tier** (`types`, `nn`): a N-dimensional Float32 tensor struct with
  explicit strides, constructors, and neural-network building blocks with
  a REAL linear forward -- zero runtime dependency, deterministic math.
* **Runtime tier** (`runtime`): a multi-soname libtorch loader over the
  AOTInductor C ABI (declared subset) and the XIOM<->libtorch tensor
  bridge. No compile-time dependency; typed SKIP when no build is present.

The runtime tier shares its doctrine with `xiom.libtorch` (see that
package's SPEC/AUDIT): fail-closed surface resolution, `TORCH_ABI_VERSION`
floor 2.9, error-code protocol, owned out-param slots.

## 2. Modules

| Module | File | Role |
|---|---|---|
| `xiom.torch.types` | `src/types.xi` | Tensor/DType/Device/TensorOptions/ModuleDef; constructors, shape, reshape |
| `xiom.torch.nn` | `src/nn.xi` | Linear/Conv2D/BatchNorm2D/Sequential builders + real `linear_forward` |
| `xiom.torch.runtime` | `src/runtime.xi` | loader (13 C + 1 C++ anchor) + `torch_upload/download/release/cuda_available` |

Renamed at this landing: `xiom.torch.ffi` -> `xiom.torch.runtime` (a
module whose last segment is `ffi` cannot import the stdlib `xiom.ffi`;
B-07 in docs/BINDINGS-COMPILER-FINDINGS.md). The declared function set of
the tier changed accordingly (see section 4).

## 3. Pure tier -- contracts and coverage

| Function | Contract | Postcondition | Suite evidence |
|---|---|---|---|
| `tensor_new(shape, options)` | `shape.len() > 0`, dims > 0 | zero-filled Tensor, row-major strides, dtype/device from options | `types: tensor_new with options` |
| `tensor_zeros(shape)` | idem | all elements 0.0 | `types: tensor_zeros [2,3]` |
| `tensor_ones(shape)` | idem | all elements 1.0 | `types: tensor_ones [2,3]` |
| `tensor_shape(&t)` | -- | independent shape copy (mutation-safe) | `types: tensor_shape returns an independent copy` |
| `tensor_reshape(&t, shape)` | `shape.len() > 0`; element counts equal | `Result[Tensor, Str]`; data copied, strides recomputed; typed Err on mismatch | `types: tensor_reshape [2,2] -> [4] preserves data` + mismatch test |
| `linear_new(in, out)` | `in > 0`, `out > 0` | weight [out,in] + bias [out], zero-initialized | `nn: linear_new(3,2)` |
| `conv2d_new(in, out, k, s, p)` | dims > 0, k > 0 | weight [out,in,k,k] + bias [out] | `nn: conv2d_new(3,8,5,...)` |
| `batchnorm2d_new(ch, eps)` | `ch > 0` | gamma=1, beta=0, mean=0, var=1, eps stored | `nn: batchnorm2d_new(4, 1e-3)` |
| `sequential_new()` / `sequential_add(&mut, layer)` | -- | ordered `Vec[LayerType]` | `nn: sequential_new empty + sequential_add` |
| `linear_forward(&layer, &input)` | trailing dim == `in_features`; leading dims row-major | REAL `y = x @ W^T + b`, output [batch, out_features] (1-D input -> batch 1) | 3 live-math tests (1-D, batched, non-trivial weights) |

Shape semantics: strides are row-major (`strides[i] = prod(shape[i+1..])`);
the forward honors the trailing-axis stride for input indexing.

## 4. Runtime tier -- declared surface and coverage

Declared C surface (13 AOTI entry points, resolved fail-closed):

| # | Entry point | Field | Used by |
|---|---|---|---|
| 1 | `aoti_torch_abi_version` | `f_abi_version` | version probe at load; `torch_runtime_info` |
| 2 | `aoti_torch_dtype_float32` | `f_dtype_float32` | `torch_upload` |
| 3 | `aoti_torch_device_type_cpu` | `f_device_type_cpu` | `torch_upload` |
| 4 | `aoti_torch_layout_strided` | `f_layout_strided` | `torch_upload` (blob layout) |
| 5 | `aoti_torch_empty_strided` | `f_empty_strided` | `torch_upload` |
| 6 | `aoti_torch_delete_tensor_object` | `f_delete_tensor` | `torch_release`, internal blob cleanup |
| 7 | `aoti_torch_create_tensor_from_blob_v2` | `f_from_blob_v2` | `torch_upload` |
| 8 | `aoti_torch_tensor_copy_` | `f_tensor_copy` | `torch_upload` (copy-in) |
| 9 | `aoti_torch_get_data_ptr` | `f_get_data_ptr` | `torch_download` |
| 10 | `aoti_torch_get_numel` | `f_get_numel` | `torch_download` |
| 11 | `aoti_torch_get_dim` | `f_get_dim` | `torch_download` |
| 12 | `aoti_torch_get_size` | `f_get_size` | `torch_download` (shape) |
| 13 | `aoti_torch_is_contiguous` | `f_is_contiguous` | `torch_download` guard |
| A1 | `?is_available@cuda@torch@@YA_NXZ` | `p_cuda_available` | `torch_cuda_available` (live call) |

Public runtime surface:

| Function | Contract | Postcondition | Suite evidence |
|---|---|---|---|
| `torch_runtime_surface_names` / `torch_runtime_anchor_names` | -- | the declared lists | `runtime: declared C surface 13 entry points aligned`, `declared C++ anchor` |
| `torch_runtime_candidates` | -- | ordered candidate list | `runtime: candidate order` |
| `torch_runtime_open` | -- | first usable build or `TORCH_LOAD_ABSENT` | `live: SKIP ...` / version line |
| `torch_runtime_open_named` | `soname.len() > 0` | load/classify one build | `runtime: absent build classified TORCH_LOAD_ABSENT` |
| `torch_runtime_info` | handle != 0 | version + surface counts | `live: <soname> <ver> (tensor-tier surface 13/13)` |
| `torch_runtime_close` | handle != 0 | handle released | `live: runtime handle released` |
| `torch_cuda_available` | anchor resolved | live bool | `live: cuda anchor callable` |
| `torch_upload(&rt, &t)` | Float32 tensor; data length == shape product | new owning runtime handle; data COPIED (no aliasing) | `live: upload -> download ... exact; upload copies` |
| `torch_download(&rt, h, name)` | contiguous runtime tensor | owned `Tensor` (Float32/CPU, row-major strides) | idem |
| `torch_release(&rt, h)` | handle != 0 | owning handle released | idem |

Error taxonomy: `TORCH_LOAD_ABSENT` (no candidate -> SKIP),
`TORCH_LOAD_ABI` (surface/version failure or unsupported dtype -> FAIL),
`TORCH_CALL_FAILED` (aoti call nonzero / non-contiguous download).

## 5. Notes

* Float32 CPU only at 0.1.0 (upload rejects other dtypes with
  `TORCH_LOAD_ABI`; download rejects non-contiguous tensors).
* The `Tensor.data`-honoring forward reads the trailing axis through its
  declared stride; leading axes flatten row-major (the layout produced by
  this package's constructors).
* `Result` payloads are bound to locals before indexing in all package
  code and tests (compiler finding; see AUDIT.md).
