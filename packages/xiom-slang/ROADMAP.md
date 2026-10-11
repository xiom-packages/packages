# ROADMAP: xiom.slang

Status: **0.1.0** -- generated 100% C API surface of the pinned Slang build
(Vulkan SDK 1.4.350.0, runtime 2026.8). Oracle, coverage and runtime
evidence: `docs/COVERAGE.md`.

## Done (0.1.0)

- [x] Committed deterministic generator `tools/gen_slang.py`: header oracle
      (both headers in `slang.h`'s include chain) + PE export-table oracle
      (pure Python), cross-checked; 277/277 exported C functions bound.
- [x] Family-split emitted modules (12 resolver + 12 wrapper + syms + types +
      constants + loader entry); every file < 600 lines.
- [x] 339 constants (`SLANG_*` enum entries + integer macros) as literals.
- [x] Conformance suite: `resolved=277/277` print, session/compile
      functional probe (HLSL -> SPIR-V, code size > 0), error path
      (success=false + non-empty diagnostics), free chain; SKIP-green when
      the DLL is absent.
- [x] `docs/COVERAGE.md` with the export-table vs header split (9
      header-declared functions not exported, listed with proof).

## Next (candidate; owner/coordinator ordered)

1. **SPIR-V blob extraction helper**: wrap `spGetEntryPointCodeBlob` +
   `spGetTargetCodeBlob` with a C-side copy into an XIOM-owned `Vec[UInt8]`
   (the blob pointer is a COM interface; a bridge or the `slang_getEmbeddedCoreModule`
   replacement API would be needed to read it without vtable calls).
2. **Session-level API convenience**: thin helpers around
   `slang_createGlobalSession` + `spFindProfile`/`spSetTargetProfile`
   presets per target (SPIR-V / DXIL / HLSL profile strings).
3. **Re-pin wave**: when the Vulkan SDK moves, re-hash and regenerate
   (procedure in SPEC.md §2); the suite reports the runtime build tag so a
   mismatch is visible.
4. **DXIL end-to-end probe**: compile a compute entry point to `SLANG_DXIL`
   and assert non-zero code (extends the SPIR-V probe matrix).
5. **Constants split**: if the const file grows past 600 lines after a
   re-pin, lower the generator's chunk cap (automatic).

## Out of scope (documented exclusions)

- C++ COM interfaces (`slang::IGlobalSession` family) -- C++-only surface
  per the SDK-100 program plan; only the C API is bound.
- The 9 header-declared functions the pinned DLL does not export (listed in
  `docs/COVERAGE.md` §3).
- `slangc` CLI and the replay/record layer's file formats -- no C API beyond
  the bound `slang_*` entries.
