# xiom.libtorch -- Audit (landing 0.1.0)

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

Scope: the loader surface, the public API, the live-leg verification on
the pinned official build, and the binding-discipline findings recorded
during the landing. Upstream pins live in PROVENANCE.md.

## 1. Verification chain

| Step | Evidence |
|---|---|
| Upstream license | pytorch/pytorch `LICENSE` (BSD-3-Clause, "Redistribution and use in source and binary forms...") checked before any code was written; pinned at `v2.9.0` = `0fabc3ba44823f257e70ce397d989c8de5e362c1` |
| Header oracle (exact signatures) | sparse clone surface: `torch/csrc/inductor/aoti_torch/c/shim.h`, `macros.h` (AOTITorchError, AtenTensorHandle), `generated/c_shim_aten.h`, `generated/c_shim_cpu.h`, `aoti_runtime/interface.h`, `torch/version.h.in` (TORCH_ABI_VERSION layout), `shim_common.cpp` (semantics: copy_ argument order, dispatcher to_ivalue/from_ivalue) |
| Binary oracle (exact exports) | official CPU build `libtorch-win-shared-with-deps-2.9.0+cpu.zip` (SHA-256 `C826069DA829550BD3F1205159F8A95EE906A447DD141D08F42C568D4EE9E05E`); export tables dumped with `llvm-readobj --coff-exports` into `torch_cpu_exports.txt` (60,248 symbols), `torch_exports.txt`, `c10_exports.txt` (E:\repos\libtorch-bin) |
| C-surface selection | `torch_cpu.dll` exports 317 plain-C symbols; 315 are the AOTI shim (`aoti_torch_*` + `aoti_torch_cpu_*`), the rest ancillary. 38 of them are the declared surface; each was verified present by name in the dump before transcription |
| Anchor verification | `?is_available@cuda@torch@@YA_NXZ`, `?device_count@cuda@torch@@YACXZ`, and the 3-arg `?load@jit@torch@@...@5@_N@Z` verified byte-exact in the dump (the jit anchor's `std::optional` spelling pins the 2.9 ABI line) |
| ABI probe | `aoti_torch_abi_version()` returns `0x0209_0000_0000_0000` on the pinned build (MAJOR 2 / MINOR 9 / PATCH 0); the loader decodes and enforces the floor |
| Live suite | `scripts/port.ps1 -Package xiom.libtorch -TimeoutSec 300` x2 with `XIOM_LIBTORCH_RUNTIME` + `PATH` set: 33/33 PASS, exit 0; x2 without: 8/8 PASS (SKIP path), exit 0 |

## 2. Ownership / memory map

| Kind | Producer | Owner | Release |
|---|---|---|---|
| Library handle | `lt_load`/`try_load` | caller | `torch_close` |
| Tensor handle (owning) | `torch_tensor_new/zeros/ones/from_data/scalar/clone/add/mul/scale/matmul/reshape/narrow/relu/softmax/sgd_step` | caller | `torch_tensor_free` |
| Borrowed blob wrapper | created inside `torch_tensor_from_data`/`torch_upload` only | internal | deleted inside the same call (no-op deleter; caller memory untouched) |
| Dispatcher input clone | `torch_tensor_relu/_softmax` | the C dispatcher | consumed inside the call (RAIIAtenTensorHandle) |
| Data pointer | `torch_tensor_data_ptr` | borrowed; valid while the tensor is | -- |

No `ffi.alloc`/`free` pairs are used; every out-param slot is an
XIOM-owned `Vec[UInt8]` (B-05/B-16/B-17 discipline: one slot per
out-param, Int-typed address math for the foreign size/stride arrays).

## 3. Binding-discipline findings (recorded during this landing)

1. **Result-payload element reads miscompile.** Indexing a
   `Result[Vec[Float32], E]` payload INLINE (`r.value[i]`) reads garbage on
   the pinned v0.64.5 toolchain; binding the payload to a local first
   (`let v = r.value; v[i]`) is correct. Minimal repro: create a tensor,
   `to_vec`, compare `r.value[0] == 1.0` (false) vs `let v = r.value;
   v[0] == 1.0` (true); bits of the inline read were `0x4E802000` vs the
   true `0x3F800000`. Vec[Int] payloads were unaffected in the same
   suite. Discipline applied package-wide; flagged for the compiler lane.
2. **Inline cast-call expressions miscompile.** `(fp as fn() -> Int)()`
   (cast + call in one expression) generates IR with a `ptr`-typed operand
   where `i64` is expected ("defined with type 'ptr' but expected 'i64'").
   Two-step form (`let f = fp as fn() -> Int; f()`) is used everywhere.
3. **AOTI dispatcher consumes input handles.** `to_ivalue` wraps each
   Tensor argument in an owning `RAIIAtenTensorHandle`; the handle is
   deleted at scope exit (before `callBoxed`). Verified in
   `shim_common.cpp` and by live double-free heap corruption
   (0xC0000374) when the original code freed the input after dispatch.
   The wrappers clone first; the relu suite test proves the caller handle
   survives.
4. **Plain `LoadLibraryA` search semantics.** `xiom_dl_open` maps to
   `LoadLibraryA`; libtorch's own DLLs (c10/uv/libiomp5md) resolve through
   the process search path, so the live leg puts the build's `lib` dir on
   `PATH` (documented in README/AUDIT; no code workaround needed).
5. **Libtorch stderr logging on typed dispatch failures.** The deliberate
   softmax-dim-5 failure prints libtorch's own `[E1017 ...]` exception
   trace on stderr (the shim catches the C++ exception and returns the
   error code). The suite's PASS/FAIL counting is stdout-marker based
   (port.ps1), so this is cosmetic; kept as evidence of the typed path.

## 4. Declared-surface completeness

* Loader surface: **38/38 C + 3/3 C++** resolved live (fail-closed);
  suite-asserted counts; every entry mapped to call sites in SPEC.md
  section 3 (1:1 table).
* Public surface: **40/40** functions implemented and covered by the
  suite; SPEC.md section 4 carries the 1:1 table with the live evidence
  per function.
* SKIP path: deterministic (bogus-soname classification + no-candidate
  run types `LT_LOAD_ABSENT`); CI without libtorch stays green (8/8).
