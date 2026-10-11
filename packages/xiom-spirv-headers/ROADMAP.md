# xiom.spirv.headers -- Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.64.3 | **Last updated**: 2026-10-11

## Current state

| Criterion | Status |
|-----------|--------|
| 100% `spirv.h` constants (74 enum types / 2378 values / 2 macros / 5 statics = 2385) | Done -- source-generated, oracle-verified |
| Family-split modules, every file < 600 lines | Done -- 10 modules |
| Generated emitted-count constants + manifest | Done -- `SPV_CONST_COUNT` etc. vs `tools/spirv_manifest.json` |
| Oracle parity + drift gate | Done -- `gen_spirv_headers.py` + `--check` |
| Conformance suite (constants-only, no runtime) | Done -- 10/10 x2 |
| PROVENANCE (upstream-first doctrine) | Done -- pinned clone `vulkan-sdk-1.4.350.0` |
| Compiler finding (4-segment module imports) | Worked around via `xiom.spirv_headers.*`; filed to report, awaiting compiler lane |

## Next (0.2.x candidates)

1. **Extended instruction-set constants** (not `Spv*`, deliberately out of
   0.1.0): `GLSL.std.450.h` (~76), `OpenCL.std.h` (~324),
   `DebugInfo.h` (~83), `OpenCLDebugInfo100.h` (~94),
   `NonSemanticShaderDebugInfo(100).h` (~210),
   `NonSemanticClspvReflection.h` (~48), `NonSemanticDebugPrintf.h` (4),
   `NonSemanticDebugBreak.h` (4), `NonSemanticVkspReflection.h` (~11),
   `TOSA.001000.1.h` (~71), the AMD headers -- same generator, per-prefix
   family modules, counts recorded in the manifest. Feeds spirv-tools /
   spirv-cross consumers that disassemble ext instructions by number.
2. **Module re-root** to `xiom.spirv.headers.<family>` once the checker
   fixes multi-import of 4-segment module paths (same values, import-path
   only change; keep the old names as aliases for one minor if feasible).
3. **Grammar-derived tables** (optional): operand-kind/word-count helpers
   from `spirv.core.grammar.json` (still constants-only).
4. **Re-carve cadence**: on each Vulkan SDK bump (re-pin procedure in
   `SPEC.md` §2); the generator fails closed on spot-check drift.
5. **Consumer smoke**: a disassembler-style round trip in a consumer
   package (spirv-tools) once the other SDK100 slices land.
