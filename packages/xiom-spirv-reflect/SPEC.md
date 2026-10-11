# SPEC: xiom.spirv-reflect -- SPIRV-Reflect bindings (vendored C)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.spirv-reflect` |
| Module | `xiom.spirvreflect` (identifier-safe module segment; package name keeps the program's `spirv-reflect` spelling) |
| Version | 0.1.0 |
| Kind | binding (`categories: ["graphics"]`, `keywords` includes `"binding"`) |
| Upstream project | SPIRV-Reflect -- https://github.com/KhronosGroup/SPIRV-Reflect |
| Upstream version pinned | upstream tag **`vulkan-sdk-1.4.350.0`**, commit `c90b7b781cdcff63cf1b409ffc7ca0a714e0425e` -- the files shipped in **Vulkan SDK 1.4.350.0** (`C:\VulkanSDK\1.4.350.0\Source\SPIRV-Reflect`); verified byte-identical to the tag in `E:\repos\SPIRV-Reflect` (see `PROVENANCE.md`). |
| Upstream license | Apache-2.0 (notice embedded in `spirv_reflect.h`; `vendor/LICENSE` is the upstream Apache-2.0 text) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored C path is portable |
| Compiler pin | v0.64.3 |

## 2. Vendored path (G2 pin)

`C:\VulkanSDK\1.4.350.0` ships no SPIRV-Reflect shared library: `Bin\SPIRV.dll`
is a stub whose entire PE export table is `?stub_library_function@@YAHXZ`
(1 export, verified 2026-10-11 by parsing the PE export directory). There is
no `spvReflectCreateShaderModule` export, so the **vendored + bridge route**
is mandatory (program plan section 3, slice 5).

The upstream files are vendored **verbatim** (raw bytes; no EOL conversion)
into `vendor/` and compiled in C with the suite via `port.args.json`
(`--c-source`); `src/spvref_bridge.c` (the reviewable probe bridge) is
compiled first. No include rewriting is needed: `spirv_reflect.c` includes
`"spirv_reflect.h"` (same directory) and the header includes
`"./include/spirv/unified1/spirv.h"` (relative to the header).

`.gitattributes` pins `vendor/** -text`.

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/spirv_reflect.h` | 96,745 | `0FEE694B129486163E8F1245EE293AEEBA068B406EF451D608F3AA3304B4C01D` |
| `vendor/spirv_reflect.c` | 222,468 | `4A615B739F89E48E44406BBF7E61F73DD60B3C1BE4A600754BF3F6F8ABB029CB` |
| `vendor/include/spirv/unified1/spirv.h` | 342,611 | `5F618BF5B328EBFC38DBD4568435CE216C0D40370400B26AA143CAA2A31CC921` |
| `vendor/LICENSE` | 11,357 | `C71D239DF91726FC519C6EB72D318EC65820627232B2F796219E87DCF35D0AB4` |

### Provenance

| Artifact | Value |
|----------|-------|
| Source of record | `C:\VulkanSDK\1.4.350.0\Source\SPIRV-Reflect\` (`spirv_reflect.h`, `spirv_reflect.c`, `include\spirv\unified1\spirv.h`); byte-identical to upstream tag `vulkan-sdk-1.4.350.0` (commit `c90b7b78`), verified by blob-hash comparison in `E:\repos\SPIRV-Reflect` |
| Extraction | `Copy-Item` raw bytes (no text conversion); hashes computed over the written files |
| LICENSE | the SDK export does **not** ship a LICENSE file; upstream is Apache-2.0. `vendor/LICENSE` is byte-identical to the upstream repo's `LICENSE` at the pinned tag (git blob `261eeb9e...`; first obtained via the upstream mirror `E:\repos\godot\thirdparty\spirv-reflect\LICENSE`, then hash-verified against `vulkan-sdk-1.4.350.0:LICENSE`). |

Re-pin procedure: identify the upstream tag matching the new SDK export
(e.g. `vulkan-sdk-X.Y.Z` in KhronosGroup/SPIRV-Reflect), verify the four
vendored files byte-identical against that tag in the clone, re-copy them as
raw bytes, recompute the SHA256 table above, regenerate the constant block
(`python tools/oracle_spvreflect.py emit-consts`), diff it against
`spirvreflect.xi`, run `python tools/oracle_spvreflect.py check
spirvreflect.xi src/spvref_bridge.c` (must print 45/45 + 186/186), then
`scripts/port.ps1 -Package xiom.spirv-reflect -TimeoutSec 700` x2, and update
the version rows (SPEC, PROVENANCE, module header comment).

## 3. Design and safe boundary (G5)

`spirvreflect.xi` is the only module in the package with `extern "C"`: the raw
45-function surface (100% of the C API, declared but not the recommended call
path) plus the `xspv_*` probe surface compiled from `src/spvref_bridge.c`.

- **Route**: vendored C compiled into the test binary (meshopt pattern).
  There is no library-absence SKIP path -- the sources are always present.
- **Resolution** (`resolved=45/45`): the bridge pins one function pointer per
  public API function in `kApi[]`; the runtime probe reports table size and
  NULL count. The suite prints `resolved=N/N` and asserts N == the oracle
  count (45).
- **ABI discipline (B-11..B-20)**: every probe out-param is an XIOM-owned
  `Vec[UInt8]` slot; C writes scalars little-endian (`wr_u32`) and copies
  strings INTO owned slots (`copy_str`); XIOM reads results back byte-indexed
  (`spv_read_u32`, `spv_slot_str`). Reflection structs and pointer arrays
  stay inside the bridge; no foreign pointer is ever read from XIOM (B-20);
  no raw pointer arithmetic (no `ptr + N`); one owned slot per out-param.
- **Fixtures**: `tests/fixtures/minimal_frag.spvasm` (fragment shader: input
  `uv` @location 0 vec2, output `outColor` vec4, combined image sampler at set
  0/binding 0, spec constant `sc` SpecId 0) and `tests/fixtures/ubo_frag.spvasm`
  (uniform block `UBOBlock` at set 0/binding 0). Assembled once with
  `C:\VulkanSDK\1.4.350.0\Bin\spirv-as.exe --target-env spv1.0`; the byte
  words are embedded verbatim in the bridge (no runtime file I/O) and the
  same bytes validate under `spirv-val --target-env spv1.0`.
- **Error mapping**: garbage words -> `INVALID_MAGIC_NUMBER` (10); word
  arrays below the 20-byte minimum and non-multiple-of-4 sizes -->
  `INVALID_CODE_SIZE` (9); failed creates leave `_internal == NULL`
  (destroy-safe); absent getters -> `ELEMENT_NOT_FOUND` (8) + NULL pointer.
- **Upstream caveat documented**: `spvReflectCreateShaderModule*` and
  `spvReflectDestroyShaderModule` do not NULL-check their out-param, so a
  NULL module pointer is a crash, not `ERROR_NULL_POINTER`; the probes never
  pass NULL there.

## 4. Test matrix (recorded 2026-10-11, compiler v0.64.3)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored tree (always compiled in) | `scripts/port.ps1 -Package xiom.spirv-reflect -TimeoutSec 700` | **PASS 40/40 x2** -- 13 constant checks, resolved=45/45 (+3 resolution checks), create/create2 header (4), descriptor bindings/sets (2), interface variables (3), entry-point family (3), get family (2), spec constants (2), string copies (2), change family (2), deprecated aliases (1), error paths (2), free chain (1) |

## 5. Scope

0.1.0 delivers the full vendored surface: 45/45 functions resolved and
exercised, 186/186 enum/macro constants, functional reflection probes over
two committed SPIR-V fixtures, error paths, and the free chain. The C++
`spv_reflect::ShaderModule` wrapper in the header is out of scope by the
program's documented C++-sugar exclusion (it mirrors the same C surface; see
`docs/COVERAGE.md`).
