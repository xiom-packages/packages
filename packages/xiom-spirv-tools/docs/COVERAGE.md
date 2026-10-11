# COVERAGE: xiom.spirv-tools (Vulkan SDK 100% program, slice A1)

Measured 2026-10-11 (UTC) on the pinned toolchain (compiler v0.64.3, stdlib
`>=0.60.0 <1.0.0`).  Oracle: `C:\VulkanSDK\1.4.350.0\Include\spirv-tools\libspirv.h`
(sha256 `F4B0A2300806ACF1EFC9CFB79708B892891352F4D719DE1F76848CC89B95ACAC`).
Runtime: `C:\VulkanSDK\1.4.350.0\Bin\SPIRV-Tools-shared.dll`
(sha256 `06C7CAE210D28D1DE2A6EB0F9357B4337429DD8F7F49B32F60194B51983241DB`,
reports `spvSoftwareVersionString()` = `v2026.2`).

## 1. Counts -- oracle vs bound vs runtime-resolved

| Metric | Count | Evidence |
|---|---|---|
| **Oracle**: `extern "C"` `spv*` functions declared in the header | **67** | `tools/gen_spirv_tools.py --print-inventory` -> `tools/oracle_inventory.txt` |
| **Bound**: typed XIOM wrappers (one per oracle function) + `p_*` handle | **67** | generated `src/st_symbols.xi` (`st_declared_count() == 67`), family modules |
| **Exported by the shipped DLL** (resolve target) | **55** | committed PE export dump `tools/dll_exports_SPIRV-Tools-shared.txt` |
| **Resolved at runtime** (name-driven `dl_sym` over the oracle list) | **55/67** | suite prints `resolved=55/67` |
| Exported names that resolve (zero missing) | **55/55** | suite: `resolve: every exported name resolves`, `exported_missing.len() == 0` |
| **Shipping gap**: declared but NOT exported by the DLL | **12** | suite: `gap_resolved.len() == 0` + the gap-name list below |
| Typed-resolver agreement (`StSymbols` non-zero handles) | **55** | suite: `st_resolved_count(&lib.syms) == 55` |
| Constants generated (enum members + file constants) | **222** | `src/st_constants.xi`, `st_constant_count() == 222` (11 enums) |

Suites (check counts): present-path suite = **39 checks**; absent-path suite
= **3 checks** (SKIP-green).

## 2. The 12-name shipping gap (declared, not exported)

Listed in `tools/oracle_inventory.txt` as `NOT-EXPORTED`; the suite proves at
runtime that none of them resolves (`gap_resolved.len() == 0`) and prints
the list:

```
spvOperandIsConcrete
spvOperandIsConcreteMask
spvOptimizerCreate
spvOptimizerDestroy
spvOptimizerSetMessageConsumer
spvOptimizerRegisterLegalizationPasses
spvOptimizerRegisterPerformancePasses
spvOptimizerRegisterSizePasses
spvOptimizerRegisterPassFromFlag
spvOptimizerRegisterPassesFromFlags
spvOptimizerRegisterPassesFromFlagsWhilePreservingTheInterface
spvOptimizerRun
```

Interpretation (source-verified against the upstream clone at the pinned
commit `0539c81f`, tag `v2026.2` == `vulkan-sdk-1.4.350.0`; see
`PROVENANCE.md`):

- The ten `spvOptimizer*` functions are defined in
  `source/opt/optimizer.cpp` with `SPIRV_TOOLS_EXPORT`, but that translation
  unit is compiled into the separate `SPIRV-Tools-opt` library target
  (`source/opt/CMakeLists.txt` line 268), not into the base
  `SPIRV-Tools-shared` DLL (`source/CMakeLists.txt` lines 168/342; the base
  source set has no `opt/` entries).  The shipped release DLL and the debug
  `SPIRV-Tools-sharedd.dll` both export the same 55 `spv*` names (PE dumps).
  The optimizer's runtime home is the static library / `spirv-opt.exe`.
- The two `spvOperandIsConcrete*` helpers are declared in the header
  (lines 348/351) and defined in `source/operand.cpp` (lines 280/357)
  without `SPIRV_TOOLS_EXPORT`: upstream deliberately keeps them out of the
  shared-library export surface.

Both classes are documented here rather than silently dropped: the wrappers
exist (`requires: syms.p_x != 0`), and the suite's gated optimizer-run probe
activates automatically if a future SDK ships a shared library that
includes the optimizer target.

Note: the task brief also named `spvOptimizerToBinary`; no such symbol
exists in `libspirv.h` at this pin (the optimizer returns through
`spvOptimizerRun(..., spv_binary* optimized_binary, ...)`).

## 3. C / C++ split (documented exclusion)

`Include\spirv-tools\` ships `libspirv.h` (C API, bound here), plus
`libspirv.hpp`, `linker.hpp`, `optimizer.hpp`, which expose the C++ API
(`spvtools::Context`, `spvtools::Optimizer`, ...).  The DLL exports those as
~62 mangled symbols (see the raw export dump).  The C++ surface is **not
bound**: it is not an FFI surface (same policy as the program plan's
glslang note; no C++ bridge in this slice).  Everything bound here is the
`extern "C"` `spv*` surface only.

## 4. Exact commands + observed results

Present path (SDK `Bin` on PATH -- required for the DLL to resolve):

```powershell
& scripts\port.ps1 -Package xiom.spirv-tools -TimeoutSec 700
```

Observed x2 (2026-10-11 UTC):

```
port: PASS (passed=39 failed=0 program_exit=0 exit=0)
port: PASS (passed=39 failed=0 program_exit=0 exit=0)
```

Key suite lines (both runs identical):

```
oracle: declared=67 exported-expected=55 gap-expected=12
resolved=55/67
gap names: spvOperandIsConcrete, spvOperandIsConcreteMask, spvOptimizerCreate, ...
  [PASS] resolve: every exported name resolves (55/55 exported; 55/67 declared)
  [PASS] assemble: spvTextToBinary(minimal module) == SPV_SUCCESS (rc=0)
  [PASS] validate: spvValidate == SPV_SUCCESS (rc=0)
  [PASS] disassemble: text contains OpEntryPoint (len=276)
  [PASS] disassemble: disassembly re-assembles (round trip)
  [PASS] diagnostics: invalid assembly -> rc=4294967287, error text copied out ("Invalid Opcode name 'OpBogus'")
xiom.spirv-tools: all checks passed
```

Absent path (SDK `Bin` filtered out of PATH -- SKIP-green proof):

```powershell
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ -notmatch 'VulkanSDK' }) -join ';'
& scripts\port.ps1 -Package xiom.spirv-tools -TimeoutSec 700
```

Observed x2 (2026-10-11 UTC):

```
port: PASS (passed=3 failed=0 program_exit=0 exit=0)
port: PASS (passed=3 failed=0 program_exit=0 exit=0)
  [PASS] loader: SKIP -- SPIRV-Tools-shared.dll not present (dynamic library error (code 126))
  [PASS] smoke: SKIP -- assemble/validate/disassemble/options (no SPIRV-Tools runtime)
```

Generator + drift guard:

```powershell
python packages\xiom-spirv-tools\tools\gen_spirv_tools.py           # regenerate src/*.xi
python packages\xiom-spirv-tools\tools\gen_spirv_tools.py --check   # exit 0 = no drift
python packages\xiom-spirv-tools\tools\gen_spirv_tools.py --print-inventory
```

Observed (2026-10-11 UTC): `oracle=67 exported=55 missing=12 constants=222 enums=11`,
`--check` exit 0.

## 5. Functional probe inventory (what "resolved" is not just counted for)

| Family | Probes |
|---|---|
| core | `spvSoftwareVersionString` (v2026.2), `spvSoftwareVersionDetailsString`, `spvTargetEnvDescription`, `spvParseTargetEnv`, `spvParseVulkanEnv`, `spvContextCreate`/`Destroy` |
| codec | `spvTextToBinary` (+`WithOptions`), `spvBinaryToText` (contains `OpEntryPoint`, round-trip re-assemble), `spvValidate`, `spvValidateWithOptions`, `spvValidateBinary`, `spvBinaryParse`, `spvDiagnosticCreate`/`Print`/`Destroy`, `spvOpcodeString` |
| validator | `spvValidatorOptionsCreate` + 13 setters (incl. `SetUniversalLimit`) + destroy; options used in `spvValidateWithOptions` |
| optimizer | `spvOptimizerOptionsCreate` + 5 setters + destroy; `spvOptimizer*` gated SKIP (shipping gap) |
| reducer/fuzzer | `spvReducerOptions*` (create + 3 setters + destroy), `spvFuzzerOptions*` (create + 6 setters + destroy) |
| operand | `spvOperandIsConcrete*` gated SKIP (shipping gap) |

All out-params ride in owned zeroed `Vec[UInt8]` slots; C-owned structs are
copied out through `src/st_probe_bridge.c` (B-20 discipline -- see
`AUDIT.md`).
