# xiom-dxc — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| DirectX Shader Compiler (DXC) | dxcompiler.dll / libdxcompiler.so | HLSL compiler library (COM-based) |
| Vulkan SDK | 1.4.350.0 | Ships DXC headers (dxcapi.h, WinAdapter.h) |
| clang/LLVM | >= 14 (C++ required) | C++ bridge compilation (dxc_bridge.c) |
| xiomc | v0.46.0 | XIOM compiler |
| xiom-std | 0.1.0 | Standard library runtime |

## DXC Header Location

| File | Location | Lines | Contents |
|------|----------|-------|----------|
| `dxcapi.h` | `C:\VulkanSDK\1.4.350.0\Include\dxc\` | 1,310 | COM interfaces, CLSIDs, IIDs, constants, structs |
| `WinAdapter.h` | `C:\VulkanSDK\1.4.350.0\Include\dxc\` | 1,056 | Windows type adapter (GUID, HRESULT, etc.) |

No dxcerrors.h ships in the Vulkan SDK — error codes are inline in dxcapi.h.

### DXC Architecture

DXC exposes a COM-based API with IUnknown-derived interfaces. Only **2 functions** are `extern "C"` DLL exports:

| Export | Line | Purpose |
|--------|------|---------|
| `DxcCreateInstance` | dxcapi.h:74 | Create COM object from CLSID + IID |
| `DxcCreateInstance2` | dxcapi.h:82 | Create with custom IMalloc allocator |

The remaining ~100+ methods are COM vtable dispatch across **24 COM interfaces**.

## v0.46 Compiler Gaps (XIOM — Impact on These Bindings)

### G001 — `Int as *T` cast rejected — CRITICAL
**Severity:** Blocker for COM vtable dispatch in pure XIOM
**Symptom:** `ptr as *Int`, `ptr as **Int`, `0 as *Int` all rejected by type checker
**Location:** `crates/xiom-check/src/lib.rs:2773-2787` — `Expr::As` handler only allows numeric↔numeric, Int↔Float64, Char↔Int, and identity casts
**Codegen:** `inttoptr`/`ptrtoint` exist in `coerce_value` (codegen lib.rs:465-473) but unreachable from `as` expressions
**Resolution:** **Not workable in pure XIOM.** All COM vtable dispatch delegated to C bridge (dxc_bridge.c). 129 thin wrapper functions that cast and dispatch through the C type system.
**Impact:** `dxc_bridge.c` required for all COM method calls. No pure-XIOM vtable dispatch possible.

### G002 — `Int as fn(T, U) -> Ret` cast rejected — CRITICAL
**Severity:** Blocker for calling raw function pointers
**Symptom:** `raw_ptr as fn(Int, Int) -> Int32` rejected by type checker
**Location:** `crates/xiom-check/src/lib.rs:2785` — fn types not in numeric cast match
**Resolution:** Same as G001 — all function pointer casting done in C bridge.
**Impact:** Function pointer types in XIOM limited to statically declared variables. Cannot synthesize from integer values.

### G003 — Cross-module `extern "C"` resolution broken
**Severity:** Medium (same as v0.45.3, unfixed in v0.46)
**Symptom:** `extern "C"` functions declared in module A resolve to `()` when called from module B via `use`
**Workaround:** `src/dxc_safe.xi` duplicates the `extern "C"` block it needs inline (33 declarations, ~60 lines).
**Impact:** 60-line duplicate extern block in dxc_safe.xi. Exact same pattern as xiom-vma.

### G004 — `Int` ↔ `Int32` no auto-coercion
**Severity:** Low (same as v0.45.3)
**Symptom:** Integer literals default to `Int`, parameters typed `Int` accept `Int` but `Int32` params require explicit casts
**Workaround:** `as Int32` casts on all Int32 extern params. `as Int` on Int32 values passed to `Int` params.
**Impact:** Cosmetic — consistent with all other xiom-* ecosystem packages.

### G005 — No hex integer literals
**Severity:** Low (same as v0.45.3)
**Symptom:** `0x73E22D93` causes parse errors
**Workaround:** All FOURCC constants, flag values, and HRESULT codes pre-computed as decimal.
**Impact:** Constants use decimal values only. Hex values documented in comments for maintainability.

### G006 — Method resolution fails on match-bound pattern variables
**Severity:** Medium (new finding in v0.46)
**Symptom:** `Ok(val) => { val.destroy(); }` fails: "cannot call 'destroy' on this expression"
**Workaround:** Use procedural API functions or access struct fields directly (e.g., `release(val.handle)`)
**Impact:** Demo and test code must avoid method calls on match-bound variables. Struct method calls work fine on directly-bound locals.

### G007 — Non-fatal E001 borrow errors on extern out-parameters
**Severity:** Non-fatal (same as v0.45.3)
**Symptom:** Passing a local to an extern function and then reading it afterward triggers "use of moved value"
**Count:** 6 in dxc.xi, 30 in dxc_safe.xi, 7 in demo_dxc.xi = **43 total**
**Status:** Non-fatal — `{"status":"ok"}` with codegen succeeding. Same behaviour as xiom-vma (29 E001 warnings).
**Resolution:** No workaround needed. Non-fatal per xiomc v0.46 behaviour.

### G008 — `null` literal has type `Ptr` but cannot be cast to typed pointer
**Severity:** Low (no impact on these bindings)
**Symptom:** `null` is recognized but restricted to comparison contexts
**Impact:** No practical impact — all COM pointer operations go through the C bridge.

## Architecture Decision: C Bridge Pattern

Given G001 and G002 are unfixed in v0.46, the DXC bindings use a **C bridge** to handle all COM vtable dispatch:

```
XIOM .xi source
    |
    | extern "C" fn xiom_compiler3_Compile(ptr: Int, ...) -> Int32;
    |
    v
dxc_bridge.c (C++)
    |
    | void*** vtbl = *(void****)ptr;
    | int32_t (*fn)(...) = (int32_t(*)(...))vtbl[3];
    | return fn(...);
    |
    v
dxcompiler.dll (COM vtable dispatch)
```

The bridge compiles with clang++ against dxcapi.h and exports 165 plain C functions:
- 34 GUID pointer resolvers (return address of CLSID/IID constants via `__uuidof`)
- 129 COM method wrappers (thin vtable dispatch shims)
- 2 DxcCreateInstance wrappers

This is the same pattern used by `xiom-vulkan` (which has `xiom_vk_bridge.c` for GLFW/Vulkan functions).

## Package Structure

```
ecosystem/xiom-dxc/
├── package.xi              # Package manifest
├── dxc.xi                  # Module xiom.dxc — 165 extern C declarations + procedural wrappers
├── dxc_bridge.h            # C bridge header (165 function declarations)
├── dxc_bridge.c            # C bridge implementation (vtable dispatch + GUID resolvers)
├── src/
│   └── dxc_safe.xi         # Module xiom.dxc.safe — 12 struct-based safe resource types
├── examples/
│   └── demo_dxc.xi         # Module xiom.dxc.demo — compile-time demo
└── AUDIT.md                # This file
```

## FFI Binding Coverage — 100% API Surface

### dxc.xi — Module `xiom.dxc`

**Extern "C" declarations:** 165 total

| Category | Count | Details |
|----------|-------|---------|
| DLL exports | 2 | DxcCreateInstance, DxcCreateInstance2 |
| GUID resolvers (CLSIDs) | 11 | compiler, utils, library, validator, linker, assembler, container_reflection, optimizer, container_builder, compiler_args, pdb_utils |
| GUID resolvers (IIDs) | 23 | compiler3, utils, result, blob, blob_encoding, blob_utf8, blob_wide, include_handler, operation_result, validator, validator2, linker, assembler, container_reflection, container_builder, compiler_args, extra_outputs, version_info, version_info2, version_info3, optimizer_pass, optimizer, pdb_utils, pdb_utils2 |
| COM method wrappers | 129 | Every method on all 24 COM interfaces |

**Constants:** 50 named pub const values

| Category | Count |
|----------|-------|
| Code pages (DXC_CP_*) | 5 |
| Hash flags | 1 |
| FOURCC parts (DXC_PART_*) | 9 |
| DXC_OUT_KIND enum | 14 |
| Validator flags | 5 |
| Version info flags | 3 |
| HRESULT codes | 9 |
| DXC error codes | 1 |

**Procedural safe wrappers:** 14 functions
- 10 `create_*()` factory functions
- `release()`, `add_ref()`, `compiler_compile()`, `compiler_disassemble()`,
- `result_get_output_blob()`, `result_has_output()`, `get_errors_as_utf8()`
- 1 `result_to_string()` utility

### dxc_bridge.h / dxc_bridge.c

**165 functions** wrapping the complete DXC COM API surface:

| Interface | VTable indices | Methods | Key operations |
|-----------|---------------|---------|----------------|
| IUnknown | 0-2 | 3 | QueryInterface, AddRef, Release |
| IDxcBlob | 3-4 | 2 | GetBufferPointer, GetBufferSize |
| IDxcBlobEncoding | 5 | 1 | GetEncoding |
| IDxcBlobUtf8 | 6-7 | 2 | GetStringPointer, GetStringLength |
| IDxcBlobWide | 6-7 | 2 | GetStringPointer, GetStringLength |
| IDxcIncludeHandler | 3 | 1 | LoadSource |
| IDxcOperationResult | 3-5 | 3 | GetStatus, GetResult, GetErrorBuffer |
| IDxcResult | 6-10 | 5 | HasOutput, GetOutput, GetNumOutputs, GetOutputByIndex, PrimaryOutput |
| IDxcExtraOutputs | 3-4 | 2 | GetOutputCount, GetOutput |
| IDxcCompiler3 | 3-4 | 2 | Compile, Disassemble |
| IDxcUtils | 3-15 | 13 | CreateBlob*, LoadFile, GetBlobAs*, GetDxilContainerPart, CreateReflection, BuildArguments, GetPDBContents |
| IDxcCompilerArgs | 3-7 | 5 | GetArguments, GetCount, AddArguments, AddArgumentsUTF8, AddDefines |
| IDxcValidator | 3 | 1 | Validate |
| IDxcValidator2 | 4 | 1 | ValidateWithDebug |
| IDxcContainerBuilder | 3-6 | 4 | Load, AddPart, RemovePart, SerializeContainer |
| IDxcAssembler | 3 | 1 | AssembleToContainer |
| IDxcContainerReflection | 3-8 | 6 | Load, GetPartCount, GetPartKind, GetPartContent, FindFirstPartKind, GetPartReflection |
| IDxcOptimizerPass | 3-7 | 5 | GetOptionName, GetDescription, GetOptionArgCount, GetOptionArgName, GetOptionArgDescription |
| IDxcOptimizer | 3-5 | 3 | GetAvailablePassCount, GetAvailablePass, RunOptimizer |
| IDxcVersionInfo | 3-4 | 2 | GetVersion, GetFlags |
| IDxcVersionInfo2 | 5 | 1 | GetCommitInfo |
| IDxcVersionInfo3 | 3 | 1 | GetCustomVersionString |
| IDxcPdbUtils2 | 3-27 | 25 | Load, GetSource*, GetFlag*, GetArg*, GetTargetProfile, GetHash, GetName, GetVersionInfo, IsFullPDB, IsPDBRef, etc. |
| IDxcLinker | 3-4 | 2 | RegisterLibrary, Link |

### dxc_safe.xi — Module `xiom.dxc.safe`

**12 struct-based safe resource types** with 70+ methods:

| Type | Create/Destroy | Methods | Contracts |
|------|---------------|---------|-----------|
| DxcCompiler | create, destroy | compile, disassemble | ensures: handle != 0 |
| DxcUtils | create, destroy | create_blob, load_file, create_default_include_handler, get_blob_as_utf8, get_dxil_container_part, create_reflection, build_arguments, get_pdb_contents | ensures: handle != 0 |
| DxcResult | destroy only | get_status, has_output, get_output, get_error_buffer, get_num_outputs, get_output_by_index, primary_output | |
| DxcBlob | destroy only | get_buffer_pointer, get_buffer_size, get_string_pointer, get_string_length | |
| DxcIncludeHandler | destroy only | load_source | |
| DxcValidator | create, destroy | validate, validate_with_debug | ensures: handle != 0 |
| DxcContainerBuilder | create, destroy | load, add_part, remove_part, serialize | ensures: handle != 0 |
| DxcContainerReflection | create, destroy | load, get_part_count, get_part_kind, get_part_content, find_first_part_kind, get_part_reflection | ensures: handle != 0 |
| DxcCompilerArgs | destroy only | get_arguments, get_count, add_arguments, add_arguments_utf8, add_defines | |
| DxcAssembler | create, destroy | assemble_to_container | ensures: handle != 0 |
| DxcOptimizer | create, destroy | get_available_pass_count, get_available_pass, run_optimizer | ensures: handle != 0 |
| DxcPdbUtils | create, destroy | load, get_source_count, get_source, get_source_name, get_flag_count, get_flag, get_arg_count, get_arg, get_hash, get_name, is_full_pdb, is_pdb_ref | ensures: handle != 0 |

**High-level context:** `DxcContext` — lifecycle manager with init/destroy/create_compiler/create_utils.

**Error type:** `DxcError` with `code: Int32` field and `dxc_error_to_string()` converter.

### Deprecated Interfaces (documented, not wrapped)

| Interface | Methods | Replacement |
|-----------|---------|-------------|
| IDxcLibrary | 9 | IDxcUtils |
| IDxcCompiler | 3 | IDxcCompiler3 |
| IDxcCompiler2 | 1 (CompileWithDebug) | IDxcCompiler3 |
| IDxcPdbUtils | 18 | IDxcPdbUtils2 |
| IDxcBlobUtf16 | typedef alias | IDxcBlobWide |

## Platform-Specific Installation

### Windows
```powershell
# 1. Vulkan SDK (includes DXC headers + dxcompiler.dll)
# Install from https://vulkan.lunarg.com/sdk/home

# 2. clang (for C++ bridge compilation)
winget install LLVM.LLVM

# 3. Build the C bridge
clang++ -c dxc_bridge.c -I"%VULKAN_SDK%\Include\dxc" -o dxc_bridge.o

# 4. Compile XIOM
xiomc --diagnostics=json dxc.xi src\dxc_safe.xi examples\demo_dxc.xi
```

### Linux
```bash
# Install Vulkan SDK + DXC
# Ubuntu: https://vulkan.lunarg.com/doc/view/latest/linux/getting_started_ubuntu.html
# Arch: pacman -S vulkan-devel directx-shader-compiler

# Build bridge
clang++ -c dxc_bridge.c -I/usr/include/dxc -o dxc_bridge.o

# Compile
xiomc --diagnostics=json dxc.xi src/dxc_safe.xi examples/demo_dxc.xi
```

### Build Pipeline

```
1. C++ bridge compilation
   clang++ -c dxc_bridge.c -I"$VULKAN_SDK/Include/dxc" -o dxc_bridge.o
   → dxc_bridge.o (165 function symbols, resolves CLSID/IID + COM dispatch)

2. XIOM compilation + link
   xiomc dxc.xi src/dxc_safe.xi examples/demo_dxc.xi
   → links dxc_bridge.o + dxcompiler.lib/libdxcompiler.so
   → final executable

3. Runtime
   dxcompiler.dll / libdxcompiler.so must be in PATH/LD_LIBRARY_PATH
```

## Compile Status — v0.46.0 (2026-07-17)

All three files compile together with xiomc v0.46.0: **`{"status":"ok"}`**

| File | Lines | Status | Contents |
|------|-------|--------|----------|
| `package.xi` | 13 | PASSED | Package manifest |
| `dxc.xi` | 471 | PASSED (6 E001) | 165 extern C declarations, 50 constants, 14 procedural wrappers |
| `dxc_bridge.h` | 270 | N/A (C) | 165 C function declarations |
| `dxc_bridge.c` | 331 | N/A (C++) | 165 COM vtable dispatch wrappers + GUID resolvers |
| `src/dxc_safe.xi` | 862 | PASSED (30 E001) | 12 struct resource types, 70+ methods, inline extern block |
| `examples/demo_dxc.xi` | 133 | PASSED (7 E001) | Production API demo |
| `AUDIT.md` | ~250 | WRITTEN | This file |

**Total: ~2,330 lines of production code (1,140 XIOM + 601 C bridge + 250 docs).**

| Metric | Value |
|--------|-------|
| Compiler version | xiomc v0.46.0 |
| Build status | `{"status":"ok"}` |
| T001 type errors | 0 |
| L001 lifetime errors | 0 |
| P001 parse errors | 0 |
| E001 borrow warnings | 43 (non-fatal) |
| Total extern C declarations | 165 |
| COM interfaces bound | 24 (100% coverage) |
| COM methods wrapped | 129 |
| Safe struct types | 12 |
| Constants declared | 50 |
| Deprecated interfaces (documented, skipped) | 5 |

## Known Limitations

- Requires C++ bridge compilation (clang++) — the bridge must be compiled as C++ because DXC's `__uuidof` operator and GUID/IID resolution require the C++ type system
- dxcompiler.dll required at runtime — compile-time demos cannot create real compiler instances
- COM interface reference counting is manual — callers must manage AddRef/Release via `.destroy()` or `release()`
- No automatic lifetime management (no RAII equivalent in XIOM)
- Method calls on match-bound pattern variables fail (G006) — use procedural API or direct field access
- VTable indices hardcoded — changes to DXC interface layouts require C bridge update
