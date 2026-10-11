# COVERAGE: xiom.glslang -- glslang C API coverage report

Recorded 2026-10-11, compiler v0.64.3, glslang 16.3.0 (Vulkan SDK 1.4.350.0).
Oracle and counts are produced by `tools/gen_glslang.ps1` (see the bottom for
the exact commands); runtime numbers come from `tests/test_conformance.xi`.

**Coverage equation: oracle N == bound N == runtime resolved N == 61**
(100% of the component's public C API).  The runtime SKIP state when the
DLLs are absent is a classified platform state, not a coverage gap.

## 1. Counts

| Metric | Count | Where |
|--------|-------|-------|
| Oracle: C entry points declared in the public headers | **61** | `docs/oracle-functions.txt` (parsed mechanically) |
| Bound: typed XIOM wrappers + loader symbols | **61** (57 core + 4 limits) | `glslang.xi` (`dl.dl_sym` calls == oracle; checked by `-Action verify`) |
| Resolved at runtime (glslang.dll) | **57/57** | suite line `loader: resolved=57/57` |
| Resolved at runtime (glslang-default-resource-limits.dll) | **4/4** | suite line `loader: resolved=4/4` |
| Resolved total | **61/61** | suite line `coverage: resolved=61/61` |
| Constants (enums + macros) oracle | **290** | `docs/oracle-constants.txt` |
| Constants bound as `pub const` | **290** | generated block in `glslang.xi` (checked by `-Action verify`) |

Oracle split by header:

| Header | C entry points | Constants |
|--------|---------------:|----------:|
| `Public/ShaderLang.h` (legacy extern "C") | 16 (`ShInitialize`..`ShGetUniformLocation`, `StageName`) | 138 (ESh*/TResourceType/TBlockStorageClass/TLayoutPacking) |
| `Include/glslang_c_interface.h` + `glslang_c_shader_types.h` | 41 (`glslang_*`) | 137 (GLSLANG_* enums) |
| `Public/resource_limits_c.h` | 4 (`glslang_resource`, `glslang_default_resource`, `glslang_default_resource_string`, `glslang_decode_resource_limits`) | 0 |
| `build_info.h` | 0 | 3 (GLSLANG_VERSION_MAJOR/MINOR/PATCH) |
| `MachineIndependent/Versions.h` | 0 | 12 (EProfile 6 + TExtensionBehavior 6) |

## 2. The C/C++ split (why this is 100% of the FFI surface)

- glslang's **C++** API (`glslang::TShader`, `glslang::TProgram`,
  `TIoMapResolver`, ...) is exported as mangled symbols
  (`?parse@TShader@glslang@@QEAA...`, 172 of the DLL's 229 exports).  It is
  **not an FFI surface** for the dynamic-loader lane: C++ object lifetimes,
  std::string/std::vector members and virtual dispatch cannot cross a
  `dl_sym` fn-pointer cast.  Documented exclusion.
- Upstream ships a **complete C interface** over the compile path
  (`Include/glslang_c_interface.h` + `SPIRV/CInterface/spirv_c_interface.cpp`
  inside the DLL) -- shader create/preprocess/parse, program link, SPIR-V
  generation, and `glslang_program_SPIRV_get` which **memcpys into a
  caller-owned buffer** (the C-copy-out shape this lane requires).  This
  package binds that surface, so **no C++ bridge is needed**: all 61 C entry
  points are reached through `dl_sym`, with no SDK headers or import
  libraries at build time and no `port.args.json`.
- The four resource-limit helpers are declared in `Public/resource_limits_c.h`
  but live in the **companion** `glslang-default-resource-limits.dll`; the
  core `glslang.dll` does not export them (verified: `docs/exports-glslang.txt`
  has no `glslang_*resource*` symbol; `docs/exports-glslang-default-resource-limits.txt`
  has all four).  Both DLLs ship in the Vulkan SDK `Bin\`.  There is **no
  header-declared C entry point that the shipped DLLs fail to export**:
  oracle 61 = 57 (core exports) + 4 (limits exports); the per-loader split is
  machine-checked against the committed dumpbin transcripts by
  `gen_glslang.ps1 -Action verify` (a header-declared function that is not
  exported would be reported as drift there and listed in this section).

C++-only headers excluded (non-FFI, like `vulkan.hpp` for the Vulkan slice):
`Include/Types.h` (internal type system), `SPIRV/GlslangToSpv.h`,
`SPIRV/SpvTools.h`, `SPIRV/Logger.h`, `SPIRV/spirv.hpp11`,
`Include/ResourceLimits.h` (C++ resource struct -- the C counterpart
`glslang_resource_t` in `glslang_c_interface.h` is bound instead; the two are
static_assert-size-equal upstream), `Public/ResourceLimits.h` (C++ helpers).

## 3. Functional probes (real calls, v0.64.3, glslang 16.3.0)

- `glslang_get_version` -> 16.3.0, equal to the pinned header macros.
- `glslang_initialize_process` / `glslang_finalize_process` (and the legacy
  `ShInitialize`/`ShFinalize`, the same upstream refcounted process state).
- Resource limits: `glslang_default_resource` / `glslang_resource` /
  `glslang_default_resource_string` (non-null), and
  `glslang_decode_resource_limits` decoding `MaxLights 42 MaxClipPlanes 7`
  into an owned 420-byte slot, read back byte-indexed (42/7, then 8 on a
  second decode).
- **GLSL -> SPIR-V compile proof through the pure C interface**:
  `glslang_compile_glsl_to_spirv` (a #version 450 vertex shader) -> 289
  words, magic word `119734787` (= 0x07230203), version word 65536
  (SPIR-V 1.0); an invalid shader returns `Err` carrying the real info log
  ("ERROR: 0:2: ...").
- Manual pipeline: shader create/preprocess/parse with preprocessed-source
  readback (172 bytes), `glslang_program_link`, glsl mapper + resolver
  create, `glslang_program_map_io_with_resolver_and_mapper` = true,
  `glslang_program_SPIRV_generate_with_options`, owned-buffer
  `glslang_program_SPIRV_get` copy (1156 bytes), program/shader delete
  ordering.
- Legacy surface: `StageName(VERTEX)` = "vertex"; `ShConstructUniformMap` +
  `ShGetUniformLocation(absent)` (0 on this build; upstream declares -1 for
  error -- callers treat <= 0 as "no such uniform"); `ShConstructCompiler` +
  empty info log + `ShGetExecutable` = 0 before a build.

## 4. Commands (reproduce)

```powershell
# oracle + constants + artifact drift check (needs the pinned SDK headers)
& packages\xiom-glslang\tools\gen_glslang.ps1 -Action verify

# suite with the runtime DLLs on PATH (present path: 29/29)
$env:PATH = "C:\VulkanSDK\1.4.350.0\Bin;" + $env:PATH
& .\scripts\port.ps1 -Package xiom.glslang -TimeoutSec 300

# CI shape: SDK dir filtered out of PATH (SKIP-green: 7/7, exit 0)
$env:PATH = (($env:PATH -split ';') | Where-Object { $_ -notmatch 'VulkanSDK' }) -join ';'
& .\scripts\port.ps1 -Package xiom.glslang -TimeoutSec 300

# export transcripts committed as evidence (dumpbin from VS2022 MSVC 14.36)
dumpbin /exports C:\VulkanSDK\1.4.350.0\Bin\glslang.dll
dumpbin /exports C:\VulkanSDK\1.4.350.0\Bin\glslang-default-resource-limits.dll
```

## 5. Known limitations / notes

- `glslang_default_resource_string()` returns a `malloc`'d string with no
  matching free in the C surface; the probe calls it once and accepts the
  process-lifetime leak (documented on the wrapper).
- `glsl_include_callbacks_t` (the C include trampoline) is part of the bound
  `glslang_input_t` layout (offset 64, zeroed by the builder = "no
  callbacks") but the suite does not drive C callbacks back into XIOM
  (lane finding B-13); tracked in `ROADMAP.md`.
- Foreign-pointer reads (`GLSLANG_SPIRV_get_ptr`) are exposed as raw Int
  addresses only; all data retrieval flows through owned-buffer copies.
