# SPEC: xiom.shaderc -- shaderc C API bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.shaderc` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | shaderc -- https://github.com/google/shaderc |
| Upstream version pinned | **v2026.4** (tag `v2026.4`, commit `b64fd42c4a2a9d501c47aca5d3571f7673a5e9cc`) |
| Upstream license | Apache-2.0 (bindings only; no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (loader path is OS-agnostic in design; soname here is `shaderc_shared.dll`) |
| Compiler pin | v0.64.3 |
| Generator | `tools/gen_shaderc.py` (committed; emits `shaderc.xi`, `src/shaderc_symbols.xi`, `src/shaderc_constants.xi`) |

## 2. G2 pin: soname + header-set hash + export matrix

**Soname (runtime contract):** `shaderc_shared.dll` (Windows). The loader
passes this exact name to `LoadLibraryA` through `xiom.ffi.dl`; there is no
link-time dependency, no import library, and nothing vendored.

**Header set pinned** (the Vulkan SDK 1.4.350.0 copies under
`C:\VulkanSDK\1.4.350.0\Include\shaderc\`; byte-identical to upstream
`google/shaderc` v2026.4 `libshaderc/include/shaderc/` -- verified by git
blob-hash equality against the `E:\repos\shaderc` clone at
`b64fd42c4a2a9d501c47aca5d3571f7673a5e9cc`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `shaderc.h` | 29,624 | `78A8195DB6FA67B94E95014FE08F63063C36D2B581D182BAE0F7CD4E86D59588` |
| `env.h` | 2,775 | `645D5D8C0BBC874E42BE727D8BB3CB887408B39A7335E99F33BF1F923142DAC8` |
| `status.h` | 1,377 | `C379F95263F2A319DE6805A68749B5BDF78EC885075BC504D6D2C1173C032941` |
| `visibility.h` | 1,163 | `9BB1C9DB00AB812CED4B22BB813A8950ECB7C9CDF7A92135DB0C71F0804B3D62` |

(The checksums are over the LF copies shipped in the SDK; the upstream clone
worktree shows CRLF variants of the same blobs.)

**Export matrix (the oracle):**

| Row | Count | Proof |
|-----|-------|-------|
| Oracle: `SHADERC_EXPORT` function declarations in the pinned headers | **45** | `tools/gen_shaderc.py` parse; `SHADERC_SYMBOL_COUNT` in `src/shaderc_symbols.xi` |
| `shaderc_*` exports of the shipped `shaderc_shared.dll` (llvm-readobj --coff-exports) | **45** | identical name set; zero header-declared-but-not-exported, zero exported-but-unbound |
| Bound: typed XIOM wrappers in `shaderc.xi` | **45** | one `pub fn shaderc_*` per declaration |
| Enum constants bound in `src/shaderc_constants.xi` | **191** | all enumerators of the 11 enums (`SHADERC_CONSTANT_COUNT`) |
| Runtime resolved | **45/45** | suite line `resolve: resolved=45/45 oracle entry points` |

**Local runtime sample used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| DLL | `C:\VulkanSDK\1.4.350.0\Bin\shaderc_shared.dll` (shipped with the Vulkan SDK) |
| Bytes | 5,045,688 |
| SHA256 | `FF7EB3639F2C72E99B0D904AF13401FF994C6471446B1E8792FE4C9250BB3D17` |
| Runtime report | `shaderc_get_spv_version` = 67072 (SPIR-V 1.6) revision 1; trivial GLSL vertex compile status success, 752-byte module, magic 0x07230203; garbage source status compilation_error with 3 errors |

### Re-pin procedure

1. Pick the new upstream tag; fetch the four headers from
   `raw.githubusercontent.com/google/shaderc/<tag>/libshaderc/include/shaderc/`.
2. Recompute the SHA256s (or compare git blob hashes against a fresh clone);
   update the table and version rows here, `README.md`/`AUDIT.md`, in one commit.
3. Re-run `python tools/gen_shaderc.py` (it re-parses the pinned headers and
   rewrites the three modules) and re-build.
4. Re-run `scripts/port.ps1 -Package xiom.shaderc` in both configurations
   (DLL absent -> SKIP; DLL on PATH -> probes) and record the matrix in §5.

## 3. Design: generated dynamic loader (G5 boundary)

- **No link-time dependency.** `shaderc_load()` resolves all 45 entry points
  from `shaderc_shared.dll` at runtime through `xiom.ffi.dl`; every call is a
  fn-pointer cast inside the generated module `xiom.shaderc` -- the only
  module in the package with `unsafe`.
- **SKIP semantics.** DLL absent -> `Err(kind = SHADERC_LOAD_ABSENT)`; the
  suite prints explicit SKIP labels under `[PASS]` markers and exits 0.
  DLL present but a symbol missing -> `Err(kind = SHADERC_LOAD_ABI)` naming
  the symbol; the suite FAILs (a present-but-wrong library must not skip).
- **Oracle-driven generation.** `tools/gen_shaderc.py` parses the header C
  declarations (functions) and enums (constants, with C enum semantics:
  implicit sequencing after explicit values, aliases, `(1u << 22) | ...`
  expressions) and emits:
  - `src/shaderc_symbols.xi` -- the ordered symbol-name oracle
    (`SHADERC_SYMBOL_COUNT`, `shaderc_symbol_name(i)`),
  - `src/shaderc_constants.xi` -- every enum value as `pub const`,
  - `shaderc.xi` -- load error type, `ShadercLibrary` (45 symbol fields),
    `shaderc_load`/`shaderc_close`, one typed wrapper per function, and the
    owned-slot decode helpers.
- **Out-params / pointer returns (B-11..B-20 discipline).** Raw wrappers take
  `Int` addresses (`shaderc_get_spv_version`, `shaderc_parse_version_profile`)
  or return addresses (`shaderc_result_get_bytes`).  Decode helpers
  (`*_values`, `shaderc_result_first_word`, `shaderc_result_copy_bytes`,
  `shaderc_result_get_text`) create a FRESH owned slot per call -- one slot
  per out-param, never reused across calls -- let C write through the slot
  pointers, then read byte-indexed.  Binary output is copied into an owned
  `Vec[UInt8]` with `ffi.memcpy` before any byte-level read; no foreign
  pointer is ever read directly; no pointer arithmetic (Int address math
  only).  Slots are built with push loops, never `Vec.with_len` (see §6).
- **`#[unsafe_direct]` (trusted escape hatch) + `port.args.json`.** The
  generated wrappers annotate their blocks `#[unsafe_direct]`;
  `port.args.json` passes `--enable-unsafe-direct`.  Rationale (AUDIT.md,
  "confined-call boundary"): `shaderc_shared.dll` is a large C++ library that
  raises and handles exceptions/SEH internally; the confined-block
  trampoline/guard machinery on v0.64.3 corrupts state around those calls.
  With direct blocks the suite is deterministic (10/10 same-binary runs,
  x2 port runs).  The flag prints a compiler warning on every run; that is
  expected and documented.

## 4. Test matrix (recorded 2026-10-11, compiler v0.64.3)

| Configuration | Command | Result |
|---------------|---------|--------|
| shaderc 2026.4 present | `scripts/port.ps1 -Package xiom.shaderc -TimeoutSec 700` (SDK Bin on PATH) | **PASS 17/17 x2** -- constants, loader, `resolved=45/45`, compile+magic, counts, error path, assembly round trip, preprocessed text, 31-setter options surface, macro proof, clone, forced version/profile, SPIR-V version, profile parsing, releases. Same binary re-run 10/10 green. |
| DLL absent (CI shape) | same command with `C:\VulkanSDK\1.4.350.0\Bin` filtered out of PATH | **PASS 4/4** -- constants + `loader/resolve/functional: SKIP` lines; exit 0 |

## 5. Scope

100% of the public C API of `shaderc.h` (45/45 entry points, 191 enum
constants).  Opaque handles cross as `Int`; C strings as `Str`; callbacks
(`shaderc_include_resolve_fn` / `shaderc_include_result_release_fn`) as `Int`
addresses (the caller supplies extern callbacks; the suite exercises the
setter with null callbacks).  The `shaderc.hpp` C++ wrapper and the CLI tools
(glslc) are out of scope per the binding lane policy (C-API surface only).
