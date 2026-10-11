# AUDIT: xiom.spirv-reflect

## Status (2026-10-11)

New vendored-route binding at 0.1.0. `C:\VulkanSDK\1.4.350.0\Bin\SPIRV.dll`
exports no `spvReflect*` symbol (stub: exactly one export), so the package
vendors the SDK-exported sources and links them into the test binary rather
than loading a library.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Upstream | SPIRV-Reflect tag `vulkan-sdk-1.4.350.0` (commit `c90b7b78`), byte-identical to the Vulkan SDK 1.4.350.0 export, vendored unmodified (Apache-2.0); see `PROVENANCE.md` |
| Link model | `--c-source` (`src/spvref_bridge.c` + `vendor/spirv_reflect.c`) via `port.args.json`, `--timeout 700`; no system library |
| FFI confinement | all `extern "C"` in the root module `spirvreflect.xi` (G5) |
| Oracle | `tools/oracle_spvreflect.py` -- 45 functions, 186 enum/macro values from the vendored header |
| Coverage check | `oracle_spvreflect.py check`: 45/45 bound + called, 186/186 consts, OK |
| Suite | `tests/test_conformance.xi`, 40 checks; `resolved=45/45` |
| Runs | **PASS 40/40 x2** on the pin (`scripts/port.ps1 -Package xiom.spirv-reflect -TimeoutSec 700`) |

## Design notes

- **Route decision (evidence)**: PE export table of `Bin\SPIRV.dll` parsed
  2026-10-11: `funcs=1 names=1`, the only export is
  `?stub_library_function@@YAHXZ`. No reflect entry; vendoring is the only
  honest route (documented in SPEC.md section 2 and COVERAGE.md).
- **Scalar/owned-slot ABI**: every probe writes scalars into XIOM-owned
  4-byte slots (little-endian) and copies strings into owned byte slots;
  reflection structs, pointer arrays, and the `SpvReflectShaderModule`
  (which embeds `descriptor_sets[64]` and an internal pointer) stay inside
  the C bridge. XIOM never reads through a foreign pointer (B-20); no
  `ffi.ptr_write_*` at offsets and no pointer arithmetic (B-16/B-17).
- **Fixtures embedded, not read at runtime**: the two SPIR-V modules are
  committed as `.spvasm` (provenance) and assembled bytes embedded in the
  bridge; the suite performs no file I/O. Both validate clean under
  `spirv-val --target-env spv1.0`.
- **Upstream caveats pinned by probes**: for image bindings
  `SpvReflectBlockVariable::type_description` stays NULL (type-name probes
  use the UBO fixture); `CreateShaderModule`/`DestroyShaderModule` do not
  NULL-check the module pointer, so NULL-module is UB and is not part of the
  error matrix; failed creates leave `_internal == NULL` (destroy-safe).
- **Deprecated aliases are first-class surface**: the 45-function oracle
  includes them; the bridge calls each one and silences the header's
  deprecation attribute locally (documented in the bridge header).

## Known limitations

- The report wrappers reflect the two committed fixtures (plus the fixed
  error/change probes). Arbitrary caller-owned SPIR-V blobs are Phase 2
  (`ROADMAP.md` item 1).
- Windows x64 tested; the vendored C path is portable (the bridge uses no
  platform APIs).
- `SPIRV-Reflect`'s C++ wrapper class (header-only sugar) is excluded per
  the program's documented C++-sugar exclusion; it is not a separate C API.
