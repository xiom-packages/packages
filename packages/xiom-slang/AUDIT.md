# AUDIT: xiom.slang

## Status (2026-10-11)

Generated dynamic-loader binding at **0.1.0** covering **100% of the Slang C
API** exported by the pinned Vulkan SDK build (`slang.dll`, runtime tag
2026.8): 277/277 exported C functions, 382 constants.

| Item | State |
|------|-------|
| Compiler | v0.64.3 (installed pin) |
| Upstream pin | Vulkan SDK 1.4.350.0: `slang.h` + `slang-deprecated.h`, `slang.dll` (proxy forwarding to `slang-compiler.dll`); hashes in SPEC.md §2 |
| Link model | none at build time; runtime `LoadLibraryA`/`GetProcAddress` via `xiom.ffi.dl` |
| Generator | `tools/gen_slang.py` (committed; deterministic: two runs byte-identical across 29 generated files); header + PE export oracles cross-checked; X-macro enums (`SlangImageFormat` via `slang-image-format-defs.h`, 43 entries) expanded preprocessor-faithfully |
| Provenance | `PROVENANCE.md`: upstream `shader-slang/slang` tag **v2026.8**, commit `d88cc8fff35baf96cf30d242b2572564cf8043b6`; SDK headers byte-identical (LF-normalized); Apache-2.0 WITH LLVM-exception; clone `E:\repos\slang` |
| Coverage | 277/277 exported bound and resolved; 9 header-declared-not-exported documented (COVERAGE.md §3); 61 C++ helper enum entries + 49 conditional config macros + 61 non-integer macros excluded with reasons |
| FFI confinement | `unsafe` only inside generated wrappers (fn-pointer casts); pointers cross as `Int`; out-params are owned `Vec[UInt8]` slots, byte-indexed readback |
| Suite | `tests/test_conformance.xi`, 20 checks present-path (3 absent-path) |
| Runs | present (2026.8 DLL): PASS 20/20 x2; absent (PATH-filtered): PASS 3/3; both via `scripts/port.ps1` (v0.64.3, 2026-10-11) |
| Namespace | `namespace-check.ps1`: 28 package modules OK vs 1843 stdlib namespaces |

## Notable runtime findings (pinned DLL)

- **`bool` returns carry garbage in the upper 64-bit register.** The pinned
  `slang.dll`/`slang-compiler.dll` build does not zero-extend `bool` returns
  (`slang_isRecordLayerEnabled` returned a pointer-sized value whose low byte
  held the real flag). The generated wrappers read the full register and mask
  `& 255`, which is correct both for this DLL and for a zero-extending one.
- **Pure-forwarder proxy.** All 435 `slang.dll` exports are forwarder entries
  to `slang-compiler.dll`; the SDK `Bin` directory must be on PATH at run
  time. The suite's SKIP path triggers on `LoadLibraryA` error code 126.
- **Legacy chain is fully functional from a string**: session -> compile
  request -> SPIR-V target -> HLSL translation unit -> entry point ->
  `spCompile` -> `spGetEntryPointCode` produced 296 bytes of SPIR-V for a
  trivial vertex shader; garbage input produced rc `0x80004005` (E_FAIL) with
  645 bytes of diagnostics.

## Design choices (vs. templates)

- Followed the `xiom-sdl3` dynamic-loader pattern (symbol struct of `Int`
  addresses + `xiom.ffi.dl` + typed wrappers + SKIP-on-absent), scaled with
  family-split generated modules (12 families) because the surface is 277
  functions.
- Multi-module layout per B-04 guidance: the parent (`xiom.slang`) imports
  the family modules; wrappers live in their family module and take
  `&<Family>Syms` (no child->parent imports).
- Constants are single literals (no cross-module aliases; B-03 discipline);
  no `unsafe` block references exported consts (B-02 discipline).
