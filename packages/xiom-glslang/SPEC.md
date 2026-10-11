# SPEC: xiom.glslang -- glslang bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.glslang` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | glslang -- https://github.com/KhronosGroup/glslang |
| Upstream version pinned | **16.3.0** (as shipped in Vulkan SDK **1.4.350.0**; `build_info.h`) |
| Upstream license | BSD-family (Khronos/3Dlabs/Google; bindings only, no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (loader path is OS-agnostic in design; sonames here are `glslang.dll` + `glslang-default-resource-limits.dll`) |
| Compiler pin | v0.64.3 |

## 2. G2 pin: sonames + header hash set + runtime DLL hashes

**Sonames (runtime contract):** `glslang.dll` (core C surface, 57 exported C
entry points) and `glslang-default-resource-limits.dll` (4 C resource-limit
helpers).  The loaders pass these exact names to `LoadLibraryA` through
`xiom.ffi.dl`; there is no link-time dependency, no import library, and
nothing vendored.  Both DLLs ship together in the Vulkan SDK `Bin\` dir.

**Upstream source clone (doctrine `docs/UPSTREAM-FIRST.md`):**
`E:\repos\glslang` at tag `vulkan-sdk-1.4.350.0` commit
`275822a6261ee689aadb1da5f09a0ec2f058685c` (`16.3.0`) -- 5 of the 6 pinned
headers below are byte-identical to the SDK copies (`build_info.h` is
generated at build time); see `PROVENANCE.md` for the verification record.

**Header set pinned** (`C:\VulkanSDK\1.4.350.0\Include\glslang\`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `Public/ShaderLang.h` | 44,447 | `559F1C724211DFAC2EBB344811B7AED8A8C7D87549F6F83766DF0758FA29D695` |
| `Include/glslang_c_interface.h` | 12,889 | `C9CC37D924C314920856847F01C96A79BC98ECF08C8F44F3A184BE9BF1B4AF02` |
| `Include/glslang_c_shader_types.h` | 9,409 | `5A1CF6CA4B0A2AE63B11E3CA00FECF922F328A2967A853CC51BFE034A26933AB` |
| `Public/resource_limits_c.h` | 2,394 | `4E01EE67E30BE094659E9579DB280005FC92A97AC3F57644A7827FF8FCC8FBA8` |
| `MachineIndependent/Versions.h` | 28,453 | `9B8F0D0B3666FF08CF735B757D84E64E2ECF5349596CC17789FD0D9F65A5090B` |
| `build_info.h` | 2,957 | `C4EE2D2A33EBAE13C8A5B501A25438B3181BF40413ABF0FF33553A4D595FC2F7` |
| **manifest (name+hash lines, LF)** | 715 | **`D889C4295F36FAE5A2509333D87725608CF210AAF6BBCDAF57B5DB8CEF85E4BF`** |

The manifest hash is the compact pin: SHA256 over the six
`"<name> <sha256>"` lines joined with LF.

**Runtime sample pinned for local positive-path proof:**

| Artifact | Bytes | SHA256 |
|----------|-------|--------|
| `Bin\glslang.dll` | 12,003,768 | `C12995F8EE1A9D7D0C04C274E44D8D88DB5B62571953160E317960E25A162E39` |
| `Bin\glslang-default-resource-limits.dll` | 295,352 | `934E45D8F1168E4B0DFA15DC9BBF13ED9C1EABCAA039593ED3D3B8F7E34D928F` |
| Runtime report | `glslang_get_version()` = 16.3.0; suite `resolved=61/61` |

### Re-pin procedure

1. Pick the new SDK/glslang version; re-hash the six headers above and the
   two DLLs; update this table, `docs/COVERAGE.md` and `README.md` in one
   commit.
2. Re-run `tools/gen_glslang.ps1 -Action emit` against the new
   `-IncludeDir`, splice the regenerated constants block into `glslang.xi`
   (BEGIN/END markers), refresh `docs/oracle-*.txt` and the two
   `docs/exports-*.txt` dumpbin transcripts, then `-Action verify`.
3. Re-run the suite with the matching runtime DLLs on PATH
   (`scripts/port.ps1 -Package xiom.glslang`); the suite asserts the runtime
   version equals the pinned `GLSLANG_VERSION_*` macros, so a mismatch is
   visible as a FAIL (not a SKIP).
4. If entry points were added/removed upstream, extend/trim the loader field
   set and wrappers in the same commit; `-Action verify` fails until the
   `dl.dl_sym` inventory matches the oracle exactly.

## 3. Design: two loaders + the C/C++ split

- **No link-time dependency.** `glslang_load()` resolves 57 C entry points
  from `glslang.dll`; `glslang_load_resource_limits()` resolves 4 from
  `glslang-default-resource-limits.dll`.  Every call is an fn-pointer cast
  executed inside `glslang.xi` (`module xiom.glslang`) -- the ONLY module in
  the package with `unsafe`.
- **SKIP semantics.** Absent library -> `Err(kind = GLSLANG_LOAD_ABSENT)`;
  the suite prints explicit `SKIP` labels under `[PASS]` markers and exits
  0.  Present-but-missing-symbol -> `Err(kind = GLSLANG_LOAD_ABI)` ->
  `[FAIL]` (a real install/SDK mismatch must not silently skip).
- **C vs C++.**  glslang's historical API is C++ (TShader/TProgram; mangled
  `?parse@TShader@glslang@@...` exports).  Upstream ships a complete **C
  interface** that wraps the compile path (create/preprocess/parse ->
  program link -> SPIR-V generate -> owned-buffer copy-out via
  `glslang_program_SPIRV_get`, which `memcpy`s into a caller buffer).  This
  package binds that C surface plus the legacy extern-"C" `Sh*` surface; no
  C++ bridge is needed and none is shipped.  See `docs/COVERAGE.md` for the
  oracle/bound/resolved counts and the documented C++ exclusions.
- **Owned-slot discipline (B-11..B-20).**  Every out-param is an
  XIOM-owned `Vec[UInt8]` slot, read back byte-indexed
  (`glslang_read_u32`); one slot per out-pointer (no `base + N` pointer
  math); C reads our strings (`Str.c_str()`) and our config buffers; the
  few foreign strings read back (info logs, preprocessed source, stage
  names) are copied with `Str::from_c_str` -- the proven read direction.
- **Lifetime rules** (documented on the wrappers):
  - the input slot (glslang_input_t) and the Str whose pointer lives at
    offset 24 must outlive `glslang_shader_create` .. `glslang_shader_parse`;
  - programs are deleted BEFORE the shaders linked into them;
  - `glslang_default_resource()` points into the companion DLL's data
    segment: keep the companion handle loaded while compiling
    (the suite reproduces the failure mode as a note in the test matrix).

Pinned layouts (x64): `glslang_input_t` = 96 bytes (offsets 0/4/8/12/16/20/
24/32/36/40/44/48/56/88 exported as `GLSLANG_INPUT_OFF_*`),
`glslang_version_t` = 24, `glslang_resource_t` = 420 (102 ints + 9 bools,
static_assert-equal to `TBuiltInResource`), `glslang_spv_options_t` = 10.

## 4. Test matrix (recorded 2026-10-11, compiler v0.64.3)

| Configuration | Command | Result |
|---------------|---------|--------|
| SDK DLLs present | `port.ps1 -Package xiom.glslang` with `C:\VulkanSDK\1.4.350.0\Bin` on PATH | **PASS, 29/29 x2** -- `resolved=57/57` + `resolved=4/4` (`resolved=61/61` total), version 16.3.0 vs header macros, init/finalize, limits decode round-trip, GLSL->SPIR-V (289 words, magic word 119734787, version word 65536), invalid GLSL -> Err with the info log, preprocess/parse readbacks, mapper/resolver `map_io` = true, owned-buffer SPIR-V copy |
| SDK DLLs absent (CI shape) | same command with the Vulkan SDK dir filtered out of PATH | **PASS, 7/7** -- `loader: SKIP ... code 126` + SKIP labels; constants checks still run |

No `port.args.json` is needed: the suite compiles no C source and needs no
extra compiler flags.

## 5. Compiler notes

- Only one module in the package; all exported functions carry the
  `glslang_` prefix (no generic-name resolver pitfalls); confined-block
  locals follow the lane naming rules; no exported-const references inside
  `unsafe` blocks (helper functions hoist constants into plain calls).
- `Str` parameters share the caller's buffer (probe 2026-10-11: pointer
  identity holds through pass-through helpers), so the input-builder stores
  a valid code pointer taken in-place.

## 6. Scope

0.1.0 covers the complete **C surface** of the shipped glslang: the 41-entry
C interface, the 16 legacy `Sh*` entry points, the 4 C resource-limits
helpers, the source-generated constant tables (290 values) and the
GLSL->SPIR-V compile path with owned-buffer copy-out.  Documented
exclusions (non-FFI): the C++ `TShader`/`TProgram` API and the C++-only
headers (`Types.h`, `SPIRV/*.h`, `Public/ResourceLimits.h`); the
`glsl_include_callbacks_t` C-callback trampoline is bound as a struct layout
but not driven by the suite (B-13 marshalling constraints) -- see
`docs/COVERAGE.md` and `ROADMAP.md`.
