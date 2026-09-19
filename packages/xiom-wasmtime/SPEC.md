# xiom.wasmtime -- SPEC

**Phase**: 5 (Nice-to-Have) | **Priority**: Low
**Status**: SPEC with XIOM bindings -- all FFI stubs return Err (Phase 2 = C bridge)
**Depends on**: xiom.ffi (stdlib)

## What it wraps
Wasmtime -- standalone WebAssembly runtime (Bytecode Alliance).
Engine, Store, Module compilation, Instance instantiation, function calling.

## Dependencies

| What | How | Size |
|------|-----|------|
| Wasmtime C API | System-installed. `winget install wasmtime`, `apt install libwasmtime-dev` | ~5MB |

## Bundling strategy
**System-installed only.** Wasmtime C API available on all major platforms.

## Files

| File | Lines | Description |
|------|-------|-------------|
| `wasmtime.xi` | ~150 | Main module: 4 types, 4 constants, 11 extern C + 11 safe wrappers with 13 contracts |
| `tests/test_conformance.xi` | ~470 | 46 conformance tests (12 sections) |
| `ROADMAP.md` | -- | Phased implementation plan v0.1.0 ? v1.0.0 |
| `SPEC.md` | -- | This file |

## API surface (implemented)

```xiom
module xiom.wasmtime

pub type WasmEngine = Int;
pub type WasmStore = Int;
pub type WasmModule = Int;
pub type WasmInstance = Int;

pub const WASM_VALTYPE_I32: Int = 0;
pub const WASM_VALTYPE_I64: Int = 1;
pub const WASM_VALTYPE_F32: Int = 2;
pub const WASM_VALTYPE_F64: Int = 3;

// Engine -- 2 functions
pub fn engine_new() -> Result[WasmEngine, Str]                        // ensures
pub fn engine_delete(engine: WasmEngine)                              // requires: engine > 0

// Store -- 2 functions
pub fn store_new(engine: WasmEngine) -> Result[WasmStore, Str]        // requires: engine > 0
pub fn store_delete(store: WasmStore)                                 // requires: store > 0

// Module -- 2 functions
pub fn module_new(store: WasmStore, wasm_bytes: &Vec[UInt8]) -> Result[WasmModule, Str]
  // requires: store > 0, wasm_bytes.len() > 0
pub fn module_delete(module: WasmModule)                              // requires: module > 0

// Instance -- 2 functions
pub fn instance_new(store: WasmStore, module: WasmModule, imports: Int) -> Result[WasmInstance, Str]
  // requires: store > 0, module > 0, imports >= 0
pub fn instance_delete(instance: WasmInstance)                        // requires: instance > 0

// Function calling -- 1 function
pub fn func_call(func: Int, args: Int, results: Int) -> Result[Int, Str]
  // requires: func > 0, args >= 0, results >= 0

// Function types -- 2 functions
pub fn functype_new(param_types: Int, result_types: Int) -> Result[Int, Str]
  // requires: param_types >= 0, result_types >= 0
pub fn valtype_new(kind: Int) -> Result[Int, Str]
  // requires: kind >= 0, kind <= 3
```

### extern "C" declarations

```xiom
extern "C" {
  fn wasm_engine_new() -> Int;
  fn wasm_engine_delete(engine: Int);
  fn wasm_store_new(engine: Int) -> Int;
  fn wasm_store_delete(store: Int);
  fn wasm_module_new(store: Int, wasm_bytes: Int, size: Int) -> Int;
  fn wasm_module_delete(module: Int);
  fn wasm_instance_new(store: Int, module: Int, imports: Int, trap_out: Int) -> Int;
  fn wasm_instance_delete(instance: Int);
  fn wasm_func_call(func: Int, args: Int, results: Int) -> Int;
  fn wasm_functype_new(param_types: Int, result_types: Int) -> Int;
  fn wasm_valtype_new(kind: Int) -> Int;
}
```

## Contract coverage
- **11 public functions** total
- **10 functions** guarded by `requires:` contracts (91%)
- **1 function** guarded by `ensures:` contract
- **11 extern "C"** FFI declarations
- All contracts validate: non-zero handles, non-empty byte buffers, valid type ranges

## Test Coverage (46 tests, 12 sections)
1. Types -- 4 tests: WasmEngine, WasmStore, WasmModule, WasmInstance Int aliases
2. Constants -- 4 tests: WASM_VALTYPE_I32=0, I64=1, F32=2, F64=3
3. Engine -- 3 tests: engine_new stub, engine_delete callable, engine lifecycle
4. Store -- 3 tests: store_new stub, store_delete callable, store lifecycle
5. Module -- 2 tests: module_new stub, module_delete callable
6. Instance -- 2 tests: instance_new stub, instance_delete callable
7. Function Calling -- 1 test: func_call stub
8. Function Types -- 2 tests: functype_new stub, valtype_new stub
9. Contract Declarations -- 11 tests: all requires/ensures clauses
10. Error Handling -- 2 tests: non-empty message, contains "stub"
11. API Presence -- 11 tests: all public function signatures
12. Full Lifecycle -- 1 test: engine ? store ? module ? instance create/destroy

## Known Limitations
- All safe wrappers return Err until C bridge is linked (same pattern as xiom.libuv, xiom.zstd)
- Module compilation requires real .wasm byte vectors
- Import/exports as raw Int -- extern vector marshaling needs structured types
- Memory access (wasm_memory_data) not yet declared

## Effort: Day (implemented)

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Engine, Store, Module, Instance (SPEC + stubs + 46 tests) | Done |
| 2 | C bridge (`wasmtime_bridge.c`), engine + store wiring | Weekend |
| 3 | Module compilation from .wasm, instance instantiation | Weekend |
| 4 | Function export lookup, typed calling, memory access | Weekend |
| 5 | WASI support, multi-value, tables, globals | Weekend |
