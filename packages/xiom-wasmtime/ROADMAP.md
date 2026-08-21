# xiom.wasmtime -- Production Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.46.0+ | **Last updated**: 2026-07-21

## Current Rating: 7/10 [SETTINGS] SPEC-READY (FFI stub)

| Criterion | Status |
|-----------|--------|
| [OK] Extern "C" declarations | 11 FFI functions declared: Engine, Store, Module, Instance, Func, Functype, Valtype |
| [OK] Safe wrappers | 11 pub fn: engine_new/delete, store_new/delete, module_new/delete, instance_new/delete, func_call, functype_new, valtype_new |
| [OK] Design-by-contract | 13 contracts across 11 functions (+1 ensures) |
| [OK] Tests | test_conformance.xi -- 46 tests, 12 sections |
| [OK] SPEC.md | Full API surface documented |
| [OK] ROADMAP.md | This file |
| [WARN] C bridge linking | Requires system-installed Wasmtime C API at link time |

## Dependencies

- **System**: Wasmtime C API (`winget install wasmtime`, `apt install libwasmtime-dev`, `brew install wasmtime`)
- **XIOM**: xiom.ffi (for Vec[UInt8] <-> raw pointer bridge, future)

## Implementation History

| Phase | Status | Description |
|-------|--------|-------------|
| **P1: Core FFI** | [OK] Done | extern "C" declarations for wasmtime engine, store, module, instance, func |
| **P1: Safe Wrappers** | [OK] Done | 11 safe wrappers with design-by-contract (requires/ensures) |
| **P1: Tests** | [OK] Done | 46 conformance tests (types, constants, stubs, contracts, error handling, lifecycle, API presence) |

## API Surface

| Function | Signature | Contracts | Status |
|----------|-----------|-----------|--------|
| `engine_new` | `() -> Result[WasmEngine, Str]` | ensures result.is_ok() \|\| result.is_err() | [OK] |
| `engine_delete` | `(engine: WasmEngine)` | requires engine > 0 | [OK] |
| `store_new` | `(engine: WasmEngine) -> Result[WasmStore, Str]` | requires engine > 0 | [OK] |
| `store_delete` | `(store: WasmStore)` | requires store > 0 | [OK] |
| `module_new` | `(store: WasmStore, wasm_bytes: &Vec[UInt8]) -> Result[WasmModule, Str]` | requires store > 0, wasm_bytes.len() > 0 | [OK] |
| `module_delete` | `(module: WasmModule)` | requires module > 0 | [OK] |
| `instance_new` | `(store: WasmStore, module: WasmModule, imports: Int) -> Result[WasmInstance, Str]` | requires store > 0, module > 0, imports >= 0 | [OK] |
| `instance_delete` | `(instance: WasmInstance)` | requires instance > 0 | [OK] |
| `func_call` | `(func: Int, args: Int, results: Int) -> Result[Int, Str]` | requires func > 0, args >= 0, results >= 0 | [OK] |
| `functype_new` | `(param_types: Int, result_types: Int) -> Result[Int, Str]` | requires param_types >= 0, result_types >= 0 | [OK] |
| `valtype_new` | `(kind: Int) -> Result[Int, Str]` | requires kind >= 0, kind <= 3 | [OK] |

## Extern "C" Surface

| C Function | XIOM Signature |
|------------|---------------|
| `wasm_engine_new` | `() -> Int` |
| `wasm_engine_delete` | `(engine: Int)` |
| `wasm_store_new` | `(engine: Int) -> Int` |
| `wasm_store_delete` | `(store: Int)` |
| `wasm_module_new` | `(store: Int, wasm_bytes: Int, size: Int) -> Int` |
| `wasm_module_delete` | `(module: Int)` |
| `wasm_instance_new` | `(store: Int, module: Int, imports: Int, trap_out: Int) -> Int` |
| `wasm_instance_delete` | `(instance: Int)` |
| `wasm_func_call` | `(func: Int, args: Int, results: Int) -> Int` |
| `wasm_functype_new` | `(param_types: Int, result_types: Int) -> Int` |
| `wasm_valtype_new` | `(kind: Int) -> Int` |

## Future (Phase 2+)

| Feature | Priority | Effort | Blocker |
|---------|----------|--------|---------|
| C bridge (`wasmtime_bridge.c`) for engine + store | P0 | Weekend | System wasmtime installation |
| Module compilation from .wasm bytes | P1 | Day | C bridge, Vec[UInt8] marshaling |
| Instance instantiation with imports | P1 | Day | Module compilation |
| Function export lookup and typed calling | P1 | Day | Instance instantiation |
| Memory export access (read/write linear memory) | P2 | Day | Instance, function calling |
| WASI support (wasi_config_new, wasi_ctx) | P2 | Weekend | Instance, module |
| Multi-value return support | P3 | Day | Function calling, valtype vectors |
| Table and Global access | P3 | Weekend | Instance exports |
| Streaming compilation | P4 | Weekend | C bridge, async I/O |

## Known Limitations

- **All safe wrappers return Err** -- Wasmtime C bridge not yet linked. The FFI declarations, contract signatures, and error paths are fully specified.
- **No .wasm compilation** -- requires C bridge with `wasm_module_new` receiving real byte buffers.
- **Import/exports as raw Int** -- Wasmtime extern vectors (imports/exports) require structured type marshaling not yet available.
- **No memory access** -- linear memory reads/writes require `wasm_memory_data` + pointer arithmetic.
