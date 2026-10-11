# COVERAGE: xiom.spirv.headers 0.1.0

Recorded 2026-10-11, compiler **v0.64.3**, Windows x64.
Oracle: `C:\VulkanSDK\1.4.350.0\Include\spirv-headers\spirv.h` (sha256
`93F82C0B51984974E60485C126945C40F264B89FD4D395A580A1BC59D211E24E`),
byte-identical to the upstream clone at `vulkan-sdk-1.4.350.0`
(commit `ad9184e76a66b1001c29db9b0a3e87f646c64de0`).
No runtime library: constants-only; there is no resolver and no SKIP state.

## 1. Oracle vs emitted

| Measure | Oracle (parsed) | Emitted (`src/` + root) | Match |
|---------|-----------------|--------------------------|-------|
| Enum types (`typedef enum Spv*`) | 74 | 74 (spread over 10 family modules) | yes |
| Enumerators (`Spv* = value`) | 2378 | 2378 | yes |
| Macros (`SPV_VERSION`, `SPV_REVISION`) | 2 | 2 | yes |
| Header static consts (`SpvMagicNumber`, `SpvVersion`, `SpvRevision`, `SpvOpCodeMask`, `SpvWordCountShift`) | 5 | 5 | yes |
| **Total constants** | **2385** | **2385** | **yes** |

Audit: the generator asserts `structured parse == naive line-scan count`
(independent regex over the oracle) before writing anything, then asserts
`emitted == parsed` while rendering. The suite re-asserts the recorded
numbers at runtime via `SPV_CONST_COUNT == 2385`, `SPV_ENUM_COUNT == 2378`,
`SPV_ENUM_TYPE_COUNT == 74`, `SPV_CONST_COUNT == SPV_ENUM_COUNT + 7`
(the 7 non-enum constants), plus the oracle sha256 string.

## 2. Emitted modules (all generated; each < 600 lines)

| Module | Constants | Enums covered |
|--------|-----------|---------------|
| `xiom.spirv_headers` (root) | 7 | -- (macros, statics, counts, sha256) |
| `xiom.spirv_headers.core` | 212 | `SpvSourceLanguage`, `SpvExecutionModel`, `SpvAddressingModel`, `SpvMemoryModel`, `SpvExecutionMode`, `SpvStorageClass`, `SpvDim`, `SpvSamplerAddressingMode`, `SpvSamplerFilterMode` |
| `xiom.spirv_headers.image` | 133 | `SpvImageFormat`, `SpvImageChannelOrder`, `SpvImageChannelDataType`, `SpvImageOperandsShift/Mask` |
| `xiom.spirv_headers.fp` | 54 | `SpvFPFastMathMode*`, `SpvFPRoundingMode`, `SpvFPDenormMode`, `SpvFPOperationMode`, `SpvQuantizationModes`, `SpvOverflowModes`, `SpvPackedVectorFormat`, `SpvFPEncoding` |
| `xiom.spirv_headers.decorations` | 369 | `SpvDecoration`, `SpvBuiltIn`, `SpvFunctionParameterAttribute`, `SpvLinkageType`, `SpvAccessQualifier` |
| `xiom.spirv_headers.controls` | 347 | 44 enum types: selection/loop/function control, memory semantics/access, scope, group ops, kernel flags, ray flags/queries, cooperative matrix/tensor operands, cache controls, component types |
| `xiom.spirv_headers.capabilities` | 338 | `SpvCapability` |
| `xiom.spirv_headers.ops_core` | 344 | `SpvOp` 0..999 |
| `xiom.spirv_headers.ops_4000` | 77 | `SpvOp` 4000..4999 |
| `xiom.spirv_headers.ops_5000` | 432 | `SpvOp` 5000..5999 |
| `xiom.spirv_headers.ops_6000` | 72 | `SpvOp` 6000+ and `SpvOpMax` (0x7fffffff) |

## 3. Spot checks (verified from the oracle header)

Generator spot checks (61) plus suite assertions; the values below are the
required canaries and a sample across every module (all taken from the
header, not from memory):

| Constant | Value | Header text |
|----------|-------|-------------|
| `SpvOpTypeVoid` | 19 | `19` |
| `SpvExecutionModelVertex` | 0 | `0` |
| `SpvStorageClassUniform` | 2 | `2` |
| `SpvCapabilityShader` | 1 | `1` |
| `SpvOpTypeInt` | 21 | `21` |
| `SpvOpTypeFloat` | 22 | `22` |
| `SpvOpTypeVector` | 23 | `23` |
| `SpvOpConstant` | 43 | `43` |
| `SpvOpFunction` | 54 | `54` |
| `SpvOpReturn` | 253 | `253` |
| `SpvOpMax` | 2147483647 | `0x7fffffff` |
| `SpvOpTerminateInvocation` | 4416 | `4416` |
| `SpvOpGroupNonUniformPartitionNV` | 5296 | `5296` |
| `SpvOpRayQueryGetRayTMinKHR` | 6016 | `6016` |
| `SpvCapabilityRayTracingKHR` | 4479 | `4479` |
| `SpvCapabilityVulkanMemoryModel` | 5345 | `5345` |
| `SpvDecorationLocation` | 30 | `30` |
| `SpvDecorationBinding` | 33 | `33` |
| `SpvBuiltInPosition` | 0 | `0` |
| `SpvBuiltInVertexIndex` | 42 | `42` |
| `SpvMemorySemanticsAcquireReleaseMask` | 8 | `0x00000008` |
| `SpvMemoryAccessVolatileMask` | 1 | `0x00000001` |
| `SpvSourceLanguageGLSL` | 2 | `2` |
| `SpvMemoryModelGLSL450` | 1 | `1` |
| `SpvMagicNumber` | 0x07230203 | `0x07230203` |
| `SpvVersion` | 0x00010600 | `0x00010600` |
| `SPV_VERSION` | 0x10600 | `#define SPV_VERSION 0x10600` |

The full 61-entry checker table lives in
`tools/gen_spirv_headers.py` (`SPOT_CHECKS`); any mismatch aborts generation
with the constant name and both values.

## 4. Exact commands + observed output

Clone the upstream (owner policy; shared, disposable):

```powershell
git clone --depth 1 --branch vulkan-sdk-1.4.350.0 https://github.com/KhronosGroup/SPIRV-Headers.git E:\repos\SPIRV-Headers
git -C E:\repos\SPIRV-Headers log --oneline -1
# ad9184e Fix constant data operand types (#581)
```

Byte-identity check (oracle vs clone):

```powershell
(Get-FileHash -Algorithm SHA256 'C:\VulkanSDK\1.4.350.0\Include\spirv-headers\spirv.h').Hash
(Get-FileHash -Algorithm SHA256 'E:\repos\SPIRV-Headers\include\spirv\unified1\spirv.h').Hash
# both: 93F82C0B51984974E60485C126945C40F264B89FD4D395A580A1BC59D211E24E
```

Generate + verify (run from the package directory):

```powershell
python tools\gen_spirv_headers.py
# oracle:   C:\VulkanSDK\1.4.350.0\Include\spirv-headers\spirv.h
# sha256:   93F82C0B51984974E60485C126945C40F264B89FD4D395A580A1BC59D211E24E
# enums:    74 types / 2378 values
# emitted:  2385 constants (2378 enum + 2 macro + 5 static)
# spot:     61 checks, all match the oracle
# files:    10 modules

python tools\gen_spirv_headers.py --check
# ... same counts ...
# check:    tree matches a fresh generation (no drift)
```

Suite (constants-only; no DLL needed), recorded x2:

```powershell
. scripts\xiom.ps1; $t = Resolve-XiomToolchain
& $t.Xiom --run "E:\...\packages\xiom-spirv-headers\tests\test_conformance.xi"
# === xiom.spirv.headers conformance tests (constants-only) ===
#   [PASS] meta: emitted counts vs manifest (const=2385 enum=2378 types=74, SPV_VERSION=0x10600, sha256 ok)
#   [PASS] ops_core: 28 well-known core opcodes
#   [PASS] ops buckets: 4xxx/5xxx/6xxx + SpvOpMax sentinel
#   [PASS] core: execution models/modes + storage classes
#   [PASS] core: memory models + source languages + dims
#   [PASS] capabilities: core + extension values
#   [PASS] decorations + built-ins
#   [PASS] image: formats/channel orders/operand masks
#   [PASS] controls: memory/function/selection/loop/ray masks
#   [PASS] fp/misc: fast-math/rounding/scope/group/store modes
# xiom.spirv.headers: all tests passed
#   exit code: 0        <- two consecutive runs, identical output
```

Canonical gate (namespace-check + suite):

```powershell
.\scripts\port.ps1 -Package xiom.spirv.headers
# namespace-check: stdlib ... 1843 module namespaces
#   xiom.spirv.headers       OK (11 module(s))
# namespace-check: 1 package(s), 11 module(s), 0 conflict(s)
# port: PASS (passed=10 failed=0 program_exit=0 exit=0)
```

## 5. Compiler finding (workaround reference)

The module namespace is `xiom.spirv_headers.<family>` (not the canonical
`xiom.spirv.headers.<family>`) because of a checker defect on the pin:
several sibling imports of a **four-segment** module path under a
three-segment package name resolve only the last module's bare constants.
Minimal repro (deterministic, compiler v0.64.3, scratch package outside the
repo):

```
pkg/package.xi                 name: "xiom.foo.bar"
pkg/foo_bar.xi                 module xiom.foo.bar          pub const R: Int = 42;
pkg/src/alpha.xi               module xiom.foo.bar.alpha    pub const A: Int = 1;
pkg/src/beta.xi                module xiom.foo.bar.beta     pub const B: Int = 2;
pkg/tests/t.xi                 module t
                               use xiom.foo.bar.alpha;
                               use xiom.foo.bar.beta;
                               fn main() -> Int { ... A ... B ... }
# xiom --check tests/t.xi -> error[T001]: undefined variable 'A'  (B resolves)
```

Controls: one import alone passes; three-segment sibling paths
(`xiom.spirv_headers.alpha/beta`) pass; the in-repo `xiom.azure` package
(3-segment submodules) passes with eight submodule imports. Full text in
`AUDIT.md`; follow-up: file to the compiler lane, re-root in a re-carve.

## 6. Re-run checklist

1. `python tools\gen_spirv_headers.py` (regenerate + verify; fails closed).
2. `python tools\gen_spirv_headers.py --check` (no-drift gate).
3. Suite x2 via the toolchain command above (expect 10/10 + exit 0).
4. `.\scripts\port.ps1 -Package xiom.spirv.headers` (expect PASS).
5. `.\scripts\status.ps1 -Action update -Package xiom.spirv.headers
   -TestsStatus pass -Passed 10 -Failed 0 -RunBy <agent> -Commit <sha>`.
