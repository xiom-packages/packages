# xiom.libtorch -- Roadmap

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

## P1 -- Landed (0.1.0, this repo state)

Delivered and live-proven against the official libtorch 2.9.0 CPU build
(33/33 suite checks; 8/8 on the no-runtime SKIP path):

* Multi-soname runtime loader over the AOTInductor C ABI (38 declared C
  entry points) + 3 pinned C++ mangled anchors, fail-closed resolution,
  `TORCH_ABI_VERSION` probe with the 2.9 floor (src/loader.xi).
* Full tensor tier: creation (`new`/`zeros`/`ones`/`from_data`/`scalar`),
  lifecycle (`free`/`clone`/`copy_into`), metadata (numel/dim/size/stride/
  shape/strides/contiguity/defined/dtype/device/offset), extraction
  (`to_vec`/`item_float32`, data pointer).
* Ops: `add`/`mul`/`scale` (C shim, double-typed scalars), 2-D `matmul`
  (`mm_out` with computed out), `relu`/`softmax` through the boxed
  dispatcher (with the input-handle-consumption discipline),
  `fill`/`zero`.
* Training primitives: functional `sgd_step` (`p - lr*g`), grad-mode
  read/write.
* GPU/JIT probes: `torch::cuda::is_available` / `device_count` called
  live; `torch::jit::load` anchor resolved.
* Typed error taxonomy + deterministic SKIP-path classification; landing
  docs (SPEC/AUDIT/PROVENANCE) with 1:1 coverage tables.

## P2 -- TorchScript + richer ops (next)

1. **`torch::jit::load` call path.** Needs the MSVC `std::string` (SSO +
   heap) and `std::optional<c10::Device>` (nullopt) ABI shapes plus a
   `.pt` fixture; the anchor is already resolved. Mint fixtures with a
   pinned torch Python wheel in the test environment (opt-in, like the
   Android device probes).
2. **`Module::forward`** via the same C++ path (`std::vector<IValue>` box
   marshaling) or by promoting the artifact to the AOTI route.
3. **More dispatcher ops** behind typed helpers: `sub`, `neg`, `select`/
   `cat`, `pow`, `mean`/`amax` reductions (all schema-legal without
   Scalar-typed args), + `aoti_torch_aten_pad`/`narrow` compositions.
4. **Dtype surface**: `float64`/`int64` constructors + `item_*` readers
   from the same C shim (`aoti_torch_dtype_float64/_int64`), with the
   declared set extended in SPEC.md.
5. **Broadcasting-explicit `add`/`mul`** tests (currently ATen-inherited).

## P3 -- Autograd + optimizers + artifacts (exploratory)

1. **Optimizer state objects** over the functional `sgd_step` (momentum +
   weight-decay as pure-XIOM state; Adam via the dispatcher ops).
2. **AOTI artifact loading**: compiled model packages (`.so`/`.dll`) built
   against the same C shim expose `aoti_*` model entry points; load them
   with the same loader discipline (path-validated artifact probe, typed
   ABI mismatch).
3. **CUDA-build lane**: run the suite against an official CUDA libtorch on
   a GPU host (the anchors and device queries are already in the declared
   set; device-guard/stream entry points would be added then).

## Non-goals

* Vendoring libtorch (the system-library stance is deliberate, PROVENANCE).
* Direct C++ (mangled) op calls beyond the three declared anchors -- the
  AOTI C shim plus the dispatcher carry the op surface.
* Python interop (`libtorch_python`) -- not part of the libtorch C++
  distribution this package declares.
