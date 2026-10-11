# AUDIT: xiom.glslang

Recorded 2026-10-11 (compiler v0.64.3; glslang 16.3.0 / Vulkan SDK 1.4.350.0).

## Method

- Oracle parsed mechanically from the pinned headers by
  `tools/gen_glslang.ps1` (extern-"C" regions for functions; enum bodies by
  brace matching for constants).  No hand-maintained function list.
- Per-DLL export split checked against committed `dumpbin /exports`
  transcripts (`docs/exports-*.txt`); `-Action verify` fails on any
  difference between oracle, module `dl.dl_sym` inventory, and exports.
- Runtime resolution is all-or-nothing per loader: any missing symbol ->
  `GLSLANG_LOAD_ABI` -> `[FAIL]`; absent DLL -> `GLSLANG_LOAD_ABSENT` ->
  SKIP label under `[PASS]`.
- Functional proofs are real calls (no mocking): version, init/finalize,
  limits decode into an owned slot, GLSL->SPIR-V compile (289 words, magic
  word and version word asserted), invalid-source Err carrying the info
  log, preprocess/parse readbacks, map_io, owned-buffer SPIR-V copy.
- Discipline: every out-param is a separate XIOM-owned `Vec[UInt8]` slot
  read byte-indexed; no `ffi.ptr_write_*` at offsets; no raw pointer
  arithmetic (addresses only stored into slots for C to dereference); the
  only `unsafe` is confined to `glslang.xi`.

## Evidence

| Item | Where |
|------|-------|
| Suite present-path x2 | `[PASS]` block 29/29, `resolved=57/57` + `4/4` + `61/61` (`port.ps1 -Package xiom.glslang`) |
| Suite absent-path | 7/7 SKIP-green (same command, SDK dir filtered from PATH) |
| Oracle counts | `docs/oracle-functions.txt`, `docs/oracle-constants.txt` |
| Export split | `docs/exports-glslang.txt`, `docs/exports-glslang-default-resource-limits.txt` |
| Generator drift check | `tools/gen_glslang.ps1 -Action verify` -> OK (61 functions, 290 constants) |

## Risks / findings

1. **Resource-pointer lifetime** (found by the suite, 2026-10-11):
   `glslang_default_resource()` points into the companion DLL's data
   segment.  Closing the companion handle before the compile silently
   breaks `glslang_shader_preprocess` (returns 0, empty log).  Documented in
   SPEC/README and asserted by suite ordering.
2. **Foreign-string reads**: info logs / preprocessed source / `StageName`
   are read with `Str::from_c_str` (the proven read direction; B-20 affects
   pointer round-trips, not C-string copies).  Reproduced with a content
   assertion (invalid source -> info log contains "ERROR").
3. **`ShGetUniformLocation` semantics**: upstream header says -1 on error;
   the shipped 16.3.0 build returns 0 for a name absent from an empty map
   (probe).  Wrapper docs and the suite treat `<= 0` as not-found.
4. **`glslang_default_resource_string()` leak**: upstream returns a
   `malloc`'d string with no free in the C surface; the probe calls it once
   (process-lifetime leak).  Wrapper documents this.
5. **ABI is x64-pinned** for struct sizes/offsets (96/24/420/10).  The
   header constants and `static_assert`s upstream pin these; the suite
   asserts the sizes so a non-x64 port fails loudly rather than corrupting.
6. **No C++ bridge** was written (decision, not a gap): the upstream C
   interface covers the compile path with an owned-buffer copy-out.  The
   C++ TShader/TProgram surface is documented as non-FFI in `COVERAGE.md`.
