// XIOM — Wasmtime (WebAssembly Runtime) Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure SPEC package — all FFI calls return Err until the C bridge is linked.
// Phase 1: Engine, Store, Module, Instance with design-by-contract wrappers.
//
// Dependencies: Wasmtime C API (system-installed via winget/apt/brew)
// Compile (when bridge ready): xiom --link wasmtime wasmtime.xi

module xiom.wasmtime

// ═══════════════════════════════════════════════════════════════════════════
// Types
// ═══════════════════════════════════════════════════════════════════════════

pub type WasmEngine = Int;
pub type WasmStore = Int;
pub type WasmModule = Int;
pub type WasmInstance = Int;

// ═══════════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════════

pub const WASM_VALTYPE_I32: Int = 0;
pub const WASM_VALTYPE_I64: Int = 1;
pub const WASM_VALTYPE_F32: Int = 2;
pub const WASM_VALTYPE_F64: Int = 3;

// ═══════════════════════════════════════════════════════════════════════════
// Wasmtime C API — extern "C" declarations
// ═══════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════
// Safe Wrappers: Engine
// ═══════════════════════════════════════════════════════════════════════════

pub fn engine_new() -> Result[WasmEngine, Str]
  ensures: result.is_ok() || result.is_err();
{
  return Err("stub: Wasmtime C bridge not linked");
}

pub fn engine_delete(engine: WasmEngine)
  requires: engine > 0;
{
  // stub: no-op until C bridge is linked
}

// ═══════════════════════════════════════════════════════════════════════════
// Safe Wrappers: Store
// ═══════════════════════════════════════════════════════════════════════════

pub fn store_new(engine: WasmEngine) -> Result[WasmStore, Str]
  requires: engine > 0;
{
  return Err("stub: Wasmtime C bridge not linked");
}

pub fn store_delete(store: WasmStore)
  requires: store > 0;
{
  // stub: no-op until C bridge is linked
}

// ═══════════════════════════════════════════════════════════════════════════
// Safe Wrappers: Module
// ═══════════════════════════════════════════════════════════════════════════

pub fn module_new(store: WasmStore, wasm_bytes: &Vec[UInt8]) -> Result[WasmModule, Str]
  requires: store > 0;
  requires: wasm_bytes.len() > 0;
{
  return Err("stub: Wasmtime C bridge not linked");
}

pub fn module_delete(module: WasmModule)
  requires: module > 0;
{
  // stub: no-op until C bridge is linked
}

// ═══════════════════════════════════════════════════════════════════════════
// Safe Wrappers: Instance
// ═══════════════════════════════════════════════════════════════════════════

pub fn instance_new(store: WasmStore, module: WasmModule, imports: Int) -> Result[WasmInstance, Str]
  requires: store > 0;
  requires: module > 0;
  requires: imports >= 0;
{
  return Err("stub: Wasmtime C bridge not linked");
}

pub fn instance_delete(instance: WasmInstance)
  requires: instance > 0;
{
  // stub: no-op until C bridge is linked
}

// ═══════════════════════════════════════════════════════════════════════════
// Safe Wrappers: Function Calling
// ═══════════════════════════════════════════════════════════════════════════

pub fn func_call(func: Int, args: Int, results: Int) -> Result[Int, Str]
  requires: func > 0;
  requires: args >= 0;
  requires: results >= 0;
{
  return Err("stub: Wasmtime C bridge not linked");
}

// ═══════════════════════════════════════════════════════════════════════════
// Safe Wrappers: Function Types
// ═══════════════════════════════════════════════════════════════════════════

pub fn functype_new(param_types: Int, result_types: Int) -> Result[Int, Str]
  requires: param_types >= 0;
  requires: result_types >= 0;
{
  return Err("stub: Wasmtime C bridge not linked");
}

pub fn valtype_new(kind: Int) -> Result[Int, Str]
  requires: kind >= 0;
  requires: kind <= 3;
{
  return Err("stub: Wasmtime C bridge not linked");
}
