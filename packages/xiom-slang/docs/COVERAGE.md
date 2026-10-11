# COVERAGE: xiom.slang -- 100% of the Slang C API (Vulkan SDK 1.4.350.0)

Program: `docs/checklists/vulkan-sdk-100.md` (owner directive 2026-10-11),
slice A6. This file is the airtight coverage evidence: oracle N vs bound N
vs runtime-resolved N, plus the export-table vs header split.

## 1. Oracle (committed generator: `tools/gen_slang.py`)

Two oracles are parsed and cross-checked; **no manual lists** anywhere.

| Oracle | Source | Parsed with |
|--------|--------|-------------|
| Header C API | `C:\VulkanSDK\1.4.350.0\Include\slang\slang.h` + `slang-deprecated.h` (the `#include` chain) | `SLANG_API` declaration scan (returns/params/typedefs) + enum/macro scan |
| Export table | `C:\VulkanSDK\1.4.350.0\Bin\slang.dll` | pure-Python PE export-directory reader (no dumpbin) |

Measured counts (generator run 2026-10-11, committed manifest
`tools/oracle_manifest.json`):

| Metric | N |
|--------|---|
| C API functions declared in the header chain | **286** |
| C-ABI functions exported by `slang.dll` (`slang_*` + legacy `sp*`) | **277** |
| header-declared but NOT exported by the DLL | **9** (listed in §3) |
| exported but not declared in the headers | **0** |
| bound as typed XIOM wrappers | **277 / 277** |
| runtime-resolved by the suite (`resolved=N/N`) | **277 / 277** |
| constants bound (`pub const`) | **382** (375 enum entries + 7 macros) |

**The DLL is a pure-forwarder proxy.** All 435 exports of `slang.dll` are
forwarder entries to `slang-compiler.dll` (Windows resolves them through the
DLL search path; the suite prepends `C:\VulkanSDK\1.4.350.0\Bin`). Of the 435
exports, 277 are C-ABI and 158 are C++ mangled `SlangRecord` internals
(`??0...@SlangRecord@@...`) -- not part of the C API surface.

## 2. Emitted surface (family-split, every file < 600 lines)

| Module group | Files | Content |
|--------------|-------|---------|
| `xiom.slang` (`slang.xi`) | 1 | loader entry: `slang_load` (fail-fast resolve of all 277), `slang_close`, `slang_resolved_count`, `SlangLibrary` |
| `xiom.slang.syms` | 1 | symbol-name blob (`SLANG_SYMBOLS`), `SLANG_SYMBOL_COUNT=277`, header-only list, forward-target const |
| `xiom.slang.types` | 1 | C typedef aliases (`SlangResult`, `SlangInt`, `SlangSizeT`, ...) |
| `xiom.slang.res_*` | 12 | per-family resolved-address struct + fail-fast resolver + per-name count probe |
| `xiom.slang.wrap_*` | 12 | one typed wrapper per exported function (277 total) |
| `xiom.slang.const_1` | 1 | 382 `pub const` enum/macro literals |

Largest generated file: 394 lines (`src/wrap_refl_decl.xi`); largest const
file: 392 lines (`src/gen_const_1.xi`); largest wrapper
file: 394 lines (`src/wrap_refl_decl.xi`). The generator enforces
`MAX_FAMILY = 30` functions per family chunk and splits automatically.

## 3. Export-table vs header split (proof)

`slang.dll` exports 277 C names; the header chain declares 286. The 9
declared-but-not-exported functions are **not bound as resolvable symbols**
(they would make the fail-fast loader fail on a correct DLL). They are
recorded in `xiom.slang.syms` (`SLANG_HEADER_ONLY`, count 9) and listed here:

| Header-only function | Header |
|----------------------|--------|
| `slang_getEmbeddedCoreModule` | slang.h |
| `spReflectionTypeLayout_getSubObjectRangeDescriptorRangeBindingCount` | slang-deprecated.h |
| `spReflectionTypeLayout_getSubObjectRangeDescriptorRangeBindingType` | slang-deprecated.h |
| `spReflectionTypeLayout_getSubObjectRangeDescriptorRangeCount` | slang-deprecated.h |
| `spReflectionTypeLayout_getSubObjectRangeDescriptorRangeIndexOffset` | slang-deprecated.h |
| `spReflectionTypeLayout_getSubObjectRangeDescriptorRangeSpaceOffset` | slang-deprecated.h |
| `spReflectionTypeLayout_getSubObjectRangeObjectCount` | slang-deprecated.h |
| `spReflectionTypeLayout_getSubObjectRangeTypeLayout` | slang-deprecated.h |
| `spReflection_GetSession` | slang-deprecated.h |

Proof (re-runnable):

```powershell
python packages\xiom-slang\tools\gen_slang.py
# prints: functions=277 header_only=9 export_only=0 forwarders->['slang-compiler']
```

The generator fails hard if the DLL exports a C name the headers do not
declare (`export_only` must be empty -- it is), so the header set and the
DLL agree on everything that is exported.

### Constants exclusions

| Item | Count | Why excluded |
|------|-------|--------------|
| C++ helper enum entries (`ScalarType::None`, `ScalarType::Void`, `ParameterCategory::DescriptorTableSlot`, `Modifier::ID`, `CompileCoreModuleFlag`) | 61 | C++-only conveniences inside `struct` definitions, not C API constants (documented C++-exclusion policy of the program plan) |
| Platform/config macros (`SLANG_VC`, `SLANG_WIN64`, `SLANG_LITTLE_ENDIAN`, `SLANG_API`, ...) | 49 | defined multiple times under `#if` branches; the value depends on the build configuration, not on the API |
| Non-integer macros (`SLANG_UUID_ICompileRequest` etc.) | 61 | GUID-list / function-like / platform string expressions, not integer constants |
| Duplicate enum entries across enums | 0 | first definition wins (none present after the C++ filter) |

X-macro enums are **not** gaps: `enum SlangImageFormat` is built by including
`slang-image-format-defs.h` under `#define SLANG_FORMAT(NAME, DESC)
SLANG_IMAGE_FORMAT_##NAME,`. The generator expands that include exactly like
the preprocessor (upstream file has **43** `SLANG_FORMAT(...)` invocations;
all **43** are bound as `SLANG_IMAGE_FORMAT_*` literals, verified by the
generator's arity check and by the suite's spot checks).

## 4. Runtime evidence (pinned compiler v0.64.3, 2026-10-11)

| Configuration | Command | Result |
|---------------|---------|--------|
| slang.dll present (2026.8, Vulkan SDK) | `port.ps1 -Package xiom.slang -TimeoutSec 900` with `C:\VulkanSDK\1.4.350.0\Bin` on PATH | **PASS 20/20 x2** -- prints `resolved=277/277`; session + HLSL->SPIRV compile (code size 296), error path (rc=0x80004005, diagnostics 645 bytes), free chain, reflection probe |
| slang.dll absent (CI shape) | same with the SDK dir filtered out of PATH | **PASS 3/3 x1** -- `loader: SKIP ... code 126`, `smoke: SKIP`; constants + oracle-count checks still run (DLL-free) |

Representative suite output (present path):

```
  resolved=277/277
  [PASS] resolve: every exported oracle name resolves (resolved=277/277)
  [PASS] session: build tag = "2026.8"
  [PASS] compile: trivial HLSL vertex -> SPIRV rc=0
  [PASS] compile: output code ptr!=0 and size=296 (bytes)
  [PASS] error-path: spCompile success=false rc=2147500037
  [PASS] error-path: diagnostics non-empty (645 bytes)
  [PASS] free: request2/request/session destroyed
```

## 5. Pinned artifacts

| Artifact | Bytes | SHA256 |
|----------|-------|--------|
| `Include\slang\slang.h` | 200,920 | `80CA5B8DBFC6061AAF9D28D376FD4625FEFE3B36272597BA97FF1384EC84C94D` |
| `Include\slang\slang-deprecated.h` | 73,113 | `A764D633FEA9FF3DBCC30DA1E9551E671B2D684BBB1CAFFC3903853B78580C60` |
| `Bin\slang.dll` | 71,608 | `3B36EDE98C2C58BAB5EFDA3914CAAE0698C2E0F815C3E1A896CA1DBA8439DA00` |
| `Bin\slang-compiler.dll` (forwarder target) | 31,122,360 | `CFDC9C0067942608757CBB343B53302BD7DA1C6B945E9DD343C9474941F9830B` |

Runtime build tag (via `spGetBuildTagString`): **2026.8**.

Upstream source pin (upstream-first policy, `PROVENANCE.md`): clone
`E:\repos\slang` at tag **v2026.8**, commit
`d88cc8fff35baf96cf30d242b2572564cf8043b6` (Apache-2.0 WITH LLVM-exception).
The SDK headers are byte-identical to that tag's `include/slang.h`
(blob `955c510a...`) and `include/slang-deprecated.h` (blob `765e3283...`)
after newline normalization (local clone is CRLF via git `autocrlf`; the
canonical LF blob content equals the SDK bytes).

## 6. Commands (reproduce everything)

```powershell
# regenerate the bindings (deterministic; two runs are byte-identical)
python packages\xiom-slang\tools\gen_slang.py

# present-path conformance (needs the SDK on PATH)
$env:PATH = "C:\VulkanSDK\1.4.350.0\Bin;" + $env:PATH
& scripts\port.ps1 -Package xiom.slang -TimeoutSec 900

# absent-path conformance (SKIP-green)
$env:PATH = (($env:PATH -split ';') | Where-Object { $_ -ne 'C:\VulkanSDK\1.4.350.0\Bin' }) -join ';'
& scripts\port.ps1 -Package xiom.slang -TimeoutSec 900
```
