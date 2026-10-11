# PROVENANCE: xiom.spirv-tools

Upstream-first record (policy: `docs/UPSTREAM-FIRST.md` in
xiom-packages/packages, owner 2026-10-11).

## 1. Upstream + pin

| Item | Value |
|------|-------|
| Upstream | **github.com/KhronosGroup/SPIRV-Tools** (Khronos Group) |
| License | **Apache-2.0** (verified: `LICENSE` in the clone; permissive -- allowed) |
| Pin | tag **`v2026.2`** == tag `vulkan-sdk-1.4.350.0` == commit **`0539c81f69a3daeb706fd3477dca61435b475156`** |
| Local clone | `E:\repos\SPIRV-Tools` (shallow, `--depth 1 --branch v2026.2`, cloned 2026-10-11) |
| Runtime | `C:\VulkanSDK\1.4.350.0\Bin\SPIRV-Tools-shared.dll` (reports `spvSoftwareVersionString()` = `v2026.2`) |

The SDK-shipped header `Include\spirv-tools\libspirv.h` was compared against
the clone's `include\spirv-tools\libspirv.h`: **identical modulo line
endings** (full-content equality after CRLF normalization; SHA256 of the
SDK copy `F4B0A230…ACAC` reflects its CRLF encoding).  The oracle is
therefore the authoritative upstream header at the pinned commit.

## 2. What was studied (from the clone, before writing code)

- `include/spirv-tools/libspirv.h` -- the C API (declarations, enums,
  structs, the `SPIRV_TOOLS_EXPORT`/`SPIRV_TOOLS_SHAREDLIB` macro
  semantics).  Oracle for the generator (67 `spv*` functions, 11 enums).
- `source/CMakeLists.txt` (lines 161/168/342-350) + `source/opt/CMakeLists.txt`
  (line 268): the base `SPIRV-Tools`/`SPIRV-Tools-shared` library is built
  from the parent source set **without** `source/opt/**`; the optimizer is a
  separate `SPIRV-Tools-opt` library target.
- `source/opt/optimizer.cpp` (lines 1225-1290): all ten `spvOptimizer*` C
  functions are defined there **with** `SPIRV_TOOLS_EXPORT` -- but that
  translation unit is not part of the shared DLL.
- `source/operand.cpp` (lines 280, 357) and the header (lines 348/351):
  `spvOperandIsConcrete` / `spvOperandIsConcreteMask` are declared and
  defined **without** `SPIRV_TOOLS_EXPORT` (not part of the shared-library
  export surface by design).
- `LICENSE` (Apache-2.0), `CHANGES` (v2026.2 release notes).

Cross-checked against the shipped binaries: the PE export table of
`SPIRV-Tools-shared.dll` contains 55 `spv*` names (dump committed at
`tools/dll_exports_SPIRV-Tools-shared.txt`); the debug `SPIRV-Tools-sharedd.dll`
exports the same 55.  The 12-name gap is therefore explained by the upstream
library split (10 optimizer functions live in the static `SPIRV-Tools-opt`
library / `spirv-opt.exe`) and by the two unexported operand helpers --
a packaging boundary of the component, not a binding gap.  All 67 declared
functions are still bound; the 55 exported resolve at runtime.

## 3. Derived vs independent

| Part | Classification |
|------|----------------|
| Function inventory, signatures, enum constants (222 values) | **Derived interface data** -- parsed mechanically from the upstream header by `tools/gen_spirv_tools.py`; no upstream code copied |
| Typed wrappers, loader, resolver, readout helpers | **Independently implemented** XIOM (dynamic-loader idiom of this lane; the fn-pointer cast / owned-slot shapes came from the lane's compiler findings, not from upstream) |
| `src/st_probe_bridge.c` | **Independent** original C (two copy helpers; no upstream header or code) |
| Test vectors | **Authored in-package**: the minimal SPIR-V module in `tests/test_conformance.xi` is written for this suite; no upstream vector files imported yet (candidate, see ROADMAP) |
| Vendored upstream files | **None** (dynamic-loader tier; nothing committed from upstream) |

No upstream license text needs to travel with the package since no upstream
code is retained; the package remains MIT OR Apache-2.0 and attribution is
this file.

## 4. Re-carve procedure

1. Re-pin: identify the new SDK tag/commit (tags `vulkan-sdk-*` and
   `vYYYY.N` point at the same commits); shallow-clone into
   `E:\repos\SPIRV-Tools` (replace the previous clone or fetch the tag).
2. Re-dump the DLL export table into
   `tools/dll_exports_SPIRV-Tools-shared.txt` (PE export parser; 55 names
   expected while the optimizer stays out of the shared target).
3. `python tools/gen_spirv_tools.py` then `--check` (must be clean);
   `--print-inventory > tools/oracle_inventory.txt`.
4. Update `SPEC.md` hashes + counts and `docs/COVERAGE.md`; re-run the suite
   x2 in both PATH configurations; record via `scripts/status.ps1`.

CLEANUP ledger row (for the shared `E:\repos\CLEANUP.md`, maintained by the
owner of that file -- requested, not edited):

`| SPIRV-Tools | github.com/KhronosGroup/SPIRV-Tools (Apache-2.0) | 2026-10-11 | bindings (xiom.spirv-tools) | 2026-12-01 | active |`
