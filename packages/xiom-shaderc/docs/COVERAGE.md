# COVERAGE: xiom.shaderc 0.1.0

Recorded 2026-10-11 (compiler v0.64.3; SDK 1.4.350.0; upstream pin
`google/shaderc` v2026.4, commit `b64fd42c`).

## Counts

| Metric | N |
|--------|----|
| Oracle: `SHADERC_EXPORT` functions in the pinned headers | **45** |
| Oracle: enum constants in the pinned headers | **191** |
| Bound: typed XIOM wrappers | **45** |
| Bound: `pub const` enum values | **191** |
| DLL exports (`llvm-readobj --coff-exports shaderc_shared.dll`, `shaderc_*`) | **45** |
| Runtime resolved (suite, per-name `dl.dl_sym` over the symbol table) | **45/45** |
| Header-declared but NOT exported by the shipped DLL | **0** |
| Exported but not header-declared | **0** |

The suite prints the resolution proof verbatim:

```
[PASS] resolve: resolved=45/45 oracle entry points
```

## How to reproduce

```powershell
# Oracle vs bound (regenerates the three modules; prints counts + header hashes):
python packages\xiom-shaderc\tools\gen_shaderc.py

# Export set (compare with the oracle list in src/shaderc_symbols.xi):
& "C:\Program Files\LLVM\bin\llvm-readobj.exe" --coff-exports `
  "C:\VulkanSDK\1.4.350.0\Bin\shaderc_shared.dll" | Select-String "shaderc_"

# Runtime resolution + functional probes, DLL present (x2 recorded PASS 17/17):
$env:PATH = "C:\VulkanSDK\1.4.350.0\Bin;" + $env:PATH
& scripts\port.ps1 -Package xiom.shaderc -TimeoutSec 700

# DLL absent -> SKIP-green (recorded PASS 5/5):
$env:PATH = (($env:PATH -split ';') | Where-Object { $_ -ne 'C:\VulkanSDK\1.4.350.0\Bin' }) -join ';'
& scripts\port.ps1 -Package xiom.shaderc -TimeoutSec 700
```

## Function families exercised by the suite

| Family | Wrappers | Probe |
|--------|----------|-------|
| compiler lifecycle | `shaderc_compiler_initialize`, `shaderc_compiler_release` | init -> non-null; release at the end |
| compile entry points | `shaderc_compile_into_spv`, `..._assembly`, `..._preprocessed_text`, `shaderc_assemble_into_spv` | GLSL vertex compile (status success, len 752, bytes [3,2,35,7]), garbage -> status 2 + message, asm round trip -> magic, preprocessed text non-empty |
| result inspection | `shaderc_result_release`, `_get_length`, `_get_num_errors`, `_get_num_warnings`, `_get_compilation_status`, `_get_bytes`, `_get_error_message` | status/length/error/warning assertions + byte-indexed magic read + text read |
| options (all setters) | 28 setter wrappers + `_initialize` / `_clone` / `_release` | full setter surface on a live object; macro definition proven by an `#ifndef`-`#error` source; clone compiles |
| version/profile | `shaderc_get_spv_version`, `shaderc_parse_version_profile` | version 67072 (1.6) rev 1; `450core` -> 450/core, `310es` -> 310/es, `banana` rejected |

Every one of the 45 bound functions is called at least once by the suite;
`shaderc_result_get_bytes` is exercised through the three decode helpers
(`_first_word`, `_copy_bytes`, `_get_text`).
