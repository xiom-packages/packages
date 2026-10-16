# xiom.libtorch -- Specification (0.1.0)

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

## 1. Scope

A runtime-loaded binding of the PyTorch C++ distribution (libtorch). The
declared surface is two-tier:

* **C tier (38 entry points)** -- the AOTInductor runtime C shim
  (`aoti_torch_*`), the stable C ABI libtorch ships for compiled model
  runtimes (`torch/csrc/inductor/aoti_torch/c/shim.h`).
* **C++ tier (3 anchors)** -- pinned mangled names verified byte-exact
  against the official release build (PROVENANCE.md):
  `torch::cuda::is_available` (`?is_available@cuda@torch@@YA_NXZ`),
  `torch::cuda::device_count` (`?device_count@cuda@torch@@YACXZ`),
  `torch::jit::load` (3-arg std::optional overload).

No link-time dependency: everything is resolved at runtime via
`xiom.ffi.dl` (`LoadLibraryA`/`GetProcAddress` on Windows,
`dlopen`/`dlsym` elsewhere).

## 2. Modules

| Module | File | Role |
|---|---|---|
| `xiom.libtorch.loader` | `src/loader.xi` | candidates, try_load, surface resolution, ABI probe, classification, typed errors, `f32_from_bits`, `int_to_str` |
| `xiom.libtorch` | `libtorch.xi` | the declared tensor-level surface (40 functions) |

## 3. Declared loader surface (38 C + 3 C++) -- coverage table

Resolution is fail-closed: every row below must resolve or the candidate
is rejected with `LT_LOAD_ABI` (never a silent fallback). On any accepted
build `resolved == 38` and `anchors_resolved == 3` (suite-asserted live).

| # | Entry point | Field | Exercised by |
|---|---|---|---|
| 1 | `aoti_torch_abi_version` | `f_abi_version` | version probe at load; `torch_abi_version`, `torch_probe` |
| 2 | `aoti_torch_dtype_float32` | `f_dtype_float32` | `torch_dtype_float32`; creation paths |
| 3 | `aoti_torch_dtype_element_size` | `f_dtype_element_size` | `torch_dtype_size` |
| 4 | `aoti_torch_device_type_cpu` | `f_device_type_cpu` | `torch_device_type_cpu`; creation paths |
| 5 | `aoti_torch_device_type_cuda` | `f_device_type_cuda` | `torch_device_type_cuda` |
| 6 | `aoti_torch_layout_strided` | `f_layout_strided` | `torch_tensor_from_data` (blob layout) |
| 7 | `aoti_torch_empty_strided` | `f_empty_strided` | `torch_tensor_new` |
| 8 | `aoti_torch_delete_tensor_object` | `f_delete_tensor` | `torch_tensor_free` |
| 9 | `aoti_torch_create_tensor_from_blob_v2` | `f_from_blob_v2` | `torch_tensor_from_data` |
| 10 | `aoti_torch_tensor_copy_` | `f_tensor_copy` | `torch_tensor_from_data`, `torch_tensor_copy_into` |
| 11 | `aoti_torch_clone` | `f_clone` | `torch_tensor_clone`, dispatcher input-clone |
| 12 | `aoti_torch_new_tensor_handle` | `f_new_handle` | resolved (alias-construction slot; unused at 0.1.0) |
| 13 | `aoti_torch_get_data_ptr` | `f_get_data_ptr` | `torch_tensor_data_ptr`, `torch_tensor_to_vec` |
| 14 | `aoti_torch_get_numel` | `f_get_numel` | `torch_tensor_numel` |
| 15 | `aoti_torch_get_dim` | `f_get_dim` | `torch_tensor_dim`, shape/strides |
| 16 | `aoti_torch_get_sizes` | `f_get_sizes` | `torch_tensor_shape` |
| 17 | `aoti_torch_get_strides` | `f_get_strides` | `torch_tensor_strides` |
| 18 | `aoti_torch_get_size` | `f_get_size` | `torch_tensor_size` |
| 19 | `aoti_torch_get_stride` | `f_get_stride` | `torch_tensor_stride` |
| 20 | `aoti_torch_get_dtype` | `f_get_dtype` | `torch_tensor_dtype` |
| 21 | `aoti_torch_get_device_type` | `f_get_device_type` | `torch_tensor_device_type` |
| 22 | `aoti_torch_get_device_index` | `f_get_device_index` | `torch_tensor_device_index` |
| 23 | `aoti_torch_get_storage_offset` | `f_get_storage_offset` | `torch_tensor_storage_offset` |
| 24 | `aoti_torch_is_contiguous` | `f_is_contiguous` | `torch_tensor_is_contiguous`; `to_vec` guard |
| 25 | `aoti_torch_is_defined` | `f_is_defined` | `torch_tensor_is_defined` |
| 26 | `aoti_torch_item_float32` | `f_item_f32` | `torch_tensor_item_float32` |
| 27 | `aoti_torch_scalar_to_tensor_float32` | `f_scalar_to_tensor_f32` | `torch_tensor_scalar` |
| 28 | `aoti_torch_cpu_add_Tensor` | `f_cpu_add` | `torch_tensor_add`, `torch_sgd_step` |
| 29 | `aoti_torch_cpu_mul_Tensor` | `f_cpu_mul` | `torch_tensor_mul` |
| 30 | `aoti_torch_cpu_mul_Scalar` | `f_cpu_mul_scalar` | `torch_tensor_scale`, `torch_sgd_step` |
| 31 | `aoti_torch_cpu_mm_out` | `f_cpu_mm_out` | `torch_tensor_matmul` |
| 32 | `aoti_torch_cpu_reshape` | `f_cpu_reshape` | `torch_tensor_reshape` |
| 33 | `aoti_torch_cpu_narrow` | `f_cpu_narrow` | `torch_tensor_narrow` |
| 34 | `aoti_torch_aten_fill__Scalar` | `f_fill_scalar` | `torch_tensor_fill`, `torch_tensor_ones` |
| 35 | `aoti_torch_zero_` | `f_zero` | `torch_tensor_zero`, `torch_tensor_zeros` |
| 36 | `aoti_torch_call_dispatcher` | `f_dispatcher` | `torch_tensor_relu`, `torch_tensor_softmax` |
| 37 | `aoti_torch_grad_mode_is_enabled` | `f_grad_enabled` | `torch_grad_mode_enabled` |
| 38 | `aoti_torch_grad_mode_set_enabled` | `f_grad_set` | `torch_set_grad_mode` |
| A1 | `?is_available@cuda@torch@@YA_NXZ` | `p_cuda_available` | `torch_cuda_is_available` (live call) |
| A2 | `?device_count@cuda@torch@@YACXZ` | `p_cuda_device_count` | `torch_cuda_device_count` (live call) |
| A3 | `?load@jit@torch@@YA?AUModule@12@AEBV?$basic_string@...@5@_N@Z` | `p_jit_load` | `torch_jit_anchor_present` (resolve-verified; call deferred, ROADMAP P2) |

## 4. Public surface -- contracts and coverage

Float32 is the declared element type at 0.1.0; all creation paths produce
row-major strided Float32 CPU tensors. Handles are opaque owning
references unless marked borrowed. "Owning" results must be released with
`torch_tensor_free`.

| Function | Contract (requires) | Postcondition | Suite evidence (live) |
|---|---|---|---|
| `torch_load` | -- | first usable candidate or `LT_LOAD_ABSENT` | `live: SKIP ...` / version line |
| `torch_load_named` | `soname.len() > 0` | load/classify one named build | `skip-path: absent runtime classified LT_LOAD_ABSENT` |
| `torch_load_candidates` | -- | the ordered candidate list | `loader: candidate order (...)` |
| `torch_probe` | handle != 0 | `LtInfo` version+counts | `live: <soname> <ver> (surface 38/38 + anchors 3/3)` |
| `torch_close` | handle != 0 | handle released | `live: runtime handle released` |
| `torch_abi_version` | handle != 0 | raw TORCH_ABI_VERSION | version line (decode equality) |
| `torch_tensor_new` | `shape.len() > 0`, last dim > 0 | zeroed `[shape]` owning handle | metadata check |
| `torch_tensor_zeros` | idem | zero-filled (via `zero_`) | `zeros [2,3] reads back all 0.0` |
| `torch_tensor_ones` | idem | one-filled (via fill) | `ones [2,3] reads back all 1.0` |
| `torch_tensor_from_data` | `data.len() == prod(shape)` | owning handle; data **copied**, never aliases XIOM memory | `from_data copies (1,2,3,4) and never aliases` |
| `torch_tensor_free` | handle != 0 | owning reference released | all free paths + `runtime handle released` |
| `torch_tensor_to_vec` | contiguous tensor | `Vec[Float32]` exact round trip | zeros/ones/from_data/op readbacks |
| `torch_tensor_data_ptr` | handle != 0 | borrowed data address (Int) | `to_vec` path |
| `torch_tensor_numel/dim/size/stride` | handle != 0 (`d >= 0`) | scalar metadata | metadata check |
| `torch_tensor_shape/strides` | handle != 0 | independent `Vec[Int]` copies | metadata check |
| `torch_tensor_is_contiguous/is_defined` | handle != 0 | Bool | metadata; non-contiguous narrow |
| `torch_tensor_dtype/device_type/device_index/storage_offset` | handle != 0 | runtime codes; CPU index sign-extended (-1) | metadata check |
| `torch_tensor_item_float32` | single-element tensor | scalar value | `scalar_to_tensor(2.5) -> item 2.5` |
| `torch_tensor_scalar` | handle != 0 | 1-element owning tensor | idem |
| `torch_dtype_size` | handle != 0 | element bytes (4 for Float32) | runtime constants |
| `torch_dtype_float32` / `torch_device_type_cpu/cuda` | handle != 0 | runtime codes; cpu != cuda | runtime constants |
| `torch_tensor_clone` | handle != 0 | independent owning copy | `clone is independent` |
| `torch_tensor_copy_into` | both handles != 0 | `dst.copy_(src)` | `copy_into fills a zeros tensor` |
| `torch_tensor_reshape` | count match (`numel` preserved) | owning view handle; typed Err on mismatch | `reshape [2,2] -> [4,1]` + mismatch test |
| `torch_tensor_narrow` | `dim,start >= 0`, `len > 0` | owning view handle (may be non-contiguous) | `narrow [4]@[1,3)` + storage offset 1 |
| `torch_tensor_add` | two handles | elementwise a+b (alpha=1) | `add (1,2)+(3,4) = (4,6)` |
| `torch_tensor_mul` | two handles | elementwise a*b | `mul (1,2)*(3,4) = (3,8)` |
| `torch_tensor_scale` | handle != 0 | scalar multiply | `scale (1,2)*2.5 = (2.5,5.0)` |
| `torch_tensor_matmul` | both 2-D, inner dims equal | `[M,N]` owning result; typed Err otherwise | `matmul ... = [[19,22],[43,50]]` + rank mismatch |
| `torch_tensor_relu` | handle != 0 | dispatcher `aten::relu`; input handle preserved (internal clone consumed by dispatcher) | `relu (-1,2) -> (0,2); input handle preserved` |
| `torch_tensor_softmax` | `dim >= 0` | dispatcher `aten::softmax.int` (dtype None sentinel 0) | `softmax ([0,0], dim 0) -> (0.5,0.5)`; failure typed |
| `torch_tensor_fill` | handle != 0 | in-place scalar fill | `ones` path |
| `torch_tensor_zero` | handle != 0 | in-place zero | `zeros` path |
| `torch_sgd_step` | `lr > 0`, two handles | functional `param + (-lr)grad`; source handles untouched | `sgd_step ... = [0.875,1.75]; source untouched` |
| `torch_grad_mode_enabled` | handle != 0 | autograd recording state | `grad mode ... round trip` |
| `torch_set_grad_mode` | handle != 0 | set state | idem |
| `torch_cuda_is_available` | anchor resolved | live bool (false on the pinned CPU build) | `cuda anchors callable` |
| `torch_cuda_device_count` | anchor resolved | live int8 (0 on CPU builds) | idem |
| `torch_jit_anchor_present` | handle != 0 | anchor resolved | `torch::jit::load anchor resolved` |

## 5. Classification and error semantics

| Kind | Meaning | Suite behavior |
|---|---|---|
| `LT_LOAD_ABSENT` | no candidate loaded (or bogus name) | reported as SKIP, green |
| `LT_LOAD_ABI` | candidate loaded; a declared entry/version failed | FAIL |
| `LT_CALL_FAILED` | aoti call returned nonzero (e.g. softmax dim error) | typed Err returned to callers |
| `LT_UNAVAILABLE` | declared capability absent (non-contiguous `to_vec`, rank limits) | typed Err returned to callers |

Version floor: `TORCH_ABI_VERSION` (MAJOR<<56|MINOR<<48|PATCH<<40|TAG)
decoded at load; `>= 2.9` required (the pinned transcription line). The
module pointer is never null-checked after resolution (fail-closed at
load).

## 6. Semantic notes (verified against the pinned shim source)

1. **Dispatcher input consumption.** `aoti_torch_call_dispatcher` converts
   each Tensor argument through `to_ivalue`, which wraps the incoming
   handle in an `RAIIAtenTensorHandle` and deletes it at scope exit -- the
   dispatcher *consumes* its inputs. `torch_tensor_relu`/`_softmax` clone
   first and dispatch on the clone, so caller handles stay valid
   (live-proven by the relu test).
2. **Borrowed-blob lifetime.** `create_tensor_from_blob_v2` wraps caller
   memory (no-op deleter); this package only uses it internally for
   same-call copies and deletes the wrapper immediately after.
3. **CPU device index is -1** (c10::Device); the wrapper sign-extends.
4. **`to_vec` requires contiguity** (views from dim-1 `narrow` are
   rejected with `LT_UNAVAILABLE`).
5. **Float32-only at 0.1.0.** Every creation path pins
   `aoti_torch_dtype_float32()`; other dtypes are out of the declared set.
