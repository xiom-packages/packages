# xiom.torch -- Audit (landing 0.1.0)

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

Scope: the pure tier's math verification, the runtime tier's live-leg
verification, and the binding findings recorded during the landing.
Upstream pins live in PROVENANCE.md (shared with `xiom.libtorch`).

## 1. Verification chain

| Step | Evidence |
|---|---|
| Pure tier oracle | hand-computed exact vectors (dyadic Float32 values): identity-weights forward [11,22]; batch [[1,2],[3,4]] -> [[11,22],[13,24]]; W=[[2,3],[4,5]] b=[1,1] x=[1,1] -> [6,10]; constructor shapes/initializations checked field-by-field |
| Runtime header oracle | same pinned sparse surface as `xiom.libtorch` (shim.h/generated shims/shim_common.cpp; PROVENANCE.md there) |
| Runtime binary oracle | same official build `libtorch-win-shared-with-deps-2.9.0+cpu.zip` (SHA-256 `C826069D...`); the 13 declared C names + the CUDA anchor verified present in the export dump before transcription |
| Live suite | `scripts/port.ps1 -Package xiom.torch -TimeoutSec 300` x2 with the runtime env: 22/22 PASS, exit 0; x2 without: 19/19 PASS (pure + SKIP), exit 0 |
| Round-trip proof | upload -> download of a [2,3] tensor (1..6) exact; source mutation after upload invisible on re-download (copy semantics, no aliasing) |

## 2. Ownership / memory map (runtime tier)

| Kind | Producer | Owner | Release |
|---|---|---|---|
| Runtime handle | `torch_runtime_open` | caller | `torch_runtime_close` |
| Uploaded tensor handle | `torch_upload` | caller | `torch_release` |
| Borrowed blob wrapper | internal to `torch_upload` | internal | deleted in-call (no-op deleter; the XIOM tensor is untouched) |
| Downloaded `Tensor` | `torch_download` | caller (value) | XIOM value semantics |

All out-param slots are XIOM-owned `Vec[UInt8]`; no `ffi.alloc/free`
pairs; foreign size reads use per-dimension `get_size` calls (no foreign
array walks).

## 3. Findings recorded during this landing

1. **Module-name/import collision (pre-existing lane finding, B-07).**
   `xiom.torch.ffi` could not import `xiom.ffi`; the tier was renamed
   `xiom.torch.runtime` at this landing and the package.xi module list +
   SPEC updated. The renamed module imports `xiom.ffi`/`xiom.ffi.dl`
   successfully on the pin.
2. **Inline cast-call expressions miscompile**
   (`error[T001]`-class codegen IR type mismatch: `(fp as fn() -> Int)()`
   lowers a `ptr` where `i64` is expected). Two-step cast-then-call is
   used everywhere (same finding as xiom.libtorch's AUDIT section 3.2).
3. **Result-payload element reads miscompile** (`Result[Vec[Float32],
   _].value[i]` inline reads garbage on v0.64.5; bind the payload to a
   local first). Applied throughout the suite and runtime tier helpers;
   full repro in `xiom.libtorch/AUDIT.md` section 3.1.
4. **Struct-field Vec element access is fine** (opposite control):
   `tensor.data[i]` reads/writes on a plain `Tensor` struct verified
   green (types + nn suites), narrowing the payload bug to Result
   payloads specifically.
5. **Runtime-tier duplication is deliberate.** The loader/candidates/
   Float32-reconstruction helpers mirror `xiom.libtorch` because the
   conformance runner compiles a package's suite against ITS OWN modules
   only (cross-package imports are not resolvable in `port.ps1`); the
   duplicated surface is a 13-entry subset + `f32_from_bits`/`int_to_str`
   lane helpers. Keeping the two in sync is a SPEC-level contract (both
   reference the same pinned AOTI names).

## 4. Declared-surface completeness

* Pure tier: 5 types functions + 6 nn functions implemented; every one in
  the suite with semantic (not smoke) evidence; `linear_forward` proven
  by three exact-math vectors.
* Runtime tier: **13/13 C + 1/1 C++** resolved live (fail-closed);
  statics (surface list alignment, candidate order, classification kinds,
  bogus-soname SKIP) asserted every run; bridge operations live-proven.
* SKIP path: 19/19 with no runtime; CI without libtorch stays green.
