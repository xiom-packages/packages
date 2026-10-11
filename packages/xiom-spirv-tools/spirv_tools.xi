// XIOM -- xiom.spirv-tools: SPIRV-Tools C API bindings (dynamic loader entry).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (sdl3 template). The package does NOT link
// against SPIRV-Tools at build time. `spirv_tools_load` resolves
// `SPIRV-Tools-shared.dll` through `xiom.ffi.dl` at runtime and every call
// goes through fn-pointer casts in the generated family modules. When the
// DLL is absent the suite reports SKIP, so CI without the Vulkan SDK stays
// green.
//
// ORACLE: every `spv*` function declared in the header's `extern "C"` block
// (67 names at the SDK 1.4.350.0 pin; see src/st_resolve.xi and
// docs/COVERAGE.md). The typed resolver records which names the shipped DLL
// actually exports (55 at this pin); the remaining 12 are documented
// shipping gaps and resolve to 0. Wrappers carry `requires: syms.p_x != 0`,
// so calling a non-exported function is a contract violation, never a
// silent crash.
//
// C++ API (libspirv.hpp: spvtools::Context / Optimizer / ...) is a separate
// mangled surface and is deliberately excluded -- see docs/COVERAGE.md.

module xiom.spirv_tools

use xiom.ffi.dl;

use xiom.spirv_tools.symbols;
use xiom.spirv_tools.resolve;

/// Runtime library name resolved by the loader (Windows soname at the
/// SDK 1.4.350.0 pin).
pub const SPIRV_TOOLS_SONAME: Str = "SPIRV-Tools-shared.dll";

/// Failure modes of `spirv_tools_load`, distinguishing "library absent"
/// (callers report SKIP) from "library present but ABI symbols missing"
/// (callers report FAIL -- a real install/SDK mismatch).
pub const SPIRV_TOOLS_LOAD_ABSENT: Int = 0;
pub const SPIRV_TOOLS_LOAD_ABI: Int = 1;

pub type SpirvToolsLoadError = {
  kind: Int;
  message: Str;
}

/// A loaded SPIRV-Tools library.  `handle` is the dl handle; `syms` holds
/// one resolved address per declared C function (0 = not exported by this
/// DLL build); `missing` lists the declared names that did not resolve.
/// Owned by the caller; release with `spirv_tools_close`.
pub type SpirvToolsLibrary = {
  handle: Int;
  syms: StSymbols;
  missing: Vec[Str];
}

/// Load SPIRV-Tools-shared.dll and resolve the full declared C surface.
/// Err(kind=SPIRV_TOOLS_LOAD_ABSENT) when the library cannot be loaded;
/// Err(kind=SPIRV_TOOLS_LOAD_ABI) when it loads but even the baseline
/// version symbol is missing (nothing is leaked: the handle is closed).
/// A DLL that exports a subset of the declared surface loads Ok -- the
/// subset is authoritative (documented shipping gaps live in `missing`).
/// Complexity: O(symbols).
pub fn spirv_tools_load() -> Result[SpirvToolsLibrary, SpirvToolsLoadError] {
  let h = dl.dl_open(SPIRV_TOOLS_SONAME);
  if !h.is_ok {
    return Err(SpirvToolsLoadError{ kind: SPIRV_TOOLS_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;
  let out = st_resolve_symbols(handle);
  if out.syms.p_spv_software_version_string == 0 {
    var ig = dl.dl_close(handle);
    return Err(SpirvToolsLoadError{
      kind: SPIRV_TOOLS_LOAD_ABI;
      message: "SPIRV-Tools-shared.dll loaded but spvSoftwareVersionString did not resolve"
    });
  }
  return Ok(SpirvToolsLibrary{ handle: handle; syms: out.syms; missing: out.missing });
}

/// Unload the library.
/// Complexity: O(1).
pub fn spirv_tools_close(lib: &SpirvToolsLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

/// Declared C functions that did not resolve against this DLL build.
/// Complexity: O(1).
pub fn spirv_tools_missing_count(lib: &SpirvToolsLibrary) -> Int {
  return lib.missing.len();
}

/// Name of the i-th unresolved declared symbol (0 <= i < missing_count).
/// Complexity: O(1).
pub fn spirv_tools_missing_at(lib: &SpirvToolsLibrary, i: Int) -> Str
  requires: i >= 0
  requires: i < lib.missing.len()
{
  return lib.missing[i];
}

/// True when the given declared C function resolved in this DLL build.
/// False for names that are not declared and for declared names in the
/// runtime `missing` list.  Complexity: O(oracle).
pub fn spirv_tools_resolved(lib: &SpirvToolsLibrary, c_name: Str) -> Bool {
  var i = 0;
  while i < lib.missing.len() {
    if lib.missing[i] == c_name { return false; }
    i = i + 1;
  }
  let names = st_oracle_names();
  var j = 0;
  while j < names.len() {
    if names[j] == c_name { return true; }
    j = j + 1;
  }
  return false;
}
