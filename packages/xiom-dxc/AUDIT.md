# AUDIT: xiom.dxc

## Status (2026-10-12)

100% `dxcapi.h` COM binding at 0.3.0: a committed generator
(`tools/gen_dxc.py`) parses the pinned header and emits the local ABI
(`src/dxc_abi.h`), the scalar-ABI bridge (`src/dxc_bridge.cpp`), 13
family-split XIOM wrapper modules, and the oracle inventory. The 0.2.0
capability probe (`src/dxc_probe.c` + root `xiom.dxc`) is retained as the
deterministic SKIP-classification seam; the pre-pilot header-based bridge is
preserved in git history only.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Pin | soname `dxcompiler.dll` + `dxcapi.h` hashes + 27/128/12/2 ABI counts (`SPEC.md` Â§2) |
| Link model | none at build time; runtime `LoadLibraryA` + `DxcCreateInstance(2)`; **no `dxcapi.h` included** (ABI generated locally) |
| Build | `port.args.json`: `--c-source .../dxc_probe.c --c-source .../dxc_bridge.cpp` (no `--link`) |
| FFI confinement | all `unsafe`/`extern` in the root probe module + generated modules; the bridge is plain C++ with no XIOM unsafe; objects cross as opaque `Int` handles |
| Out-params | one XIOM-owned byte slot per out-param, little-endian copies (B-11..B-20); no foreign pointer is ever read from XIOM |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 20/20 x2** via `scripts/port.ps1` (`bound=128/128`; compile/errors/reflection/disasm/version/factory/lifecycle green); generator `--check` OK |

## Design notes

- The vtable structs are emitted with the **flattened slot order** (IUnknown +
  base chain + declared methods). A derived interface missing the IUnknown
  prefix shifts every slot by three: this produced a real bug during
  development (`GetEncoding` resolved to `Release`) that the runtime probe
  caught -- the probe set is the guard for this class of ABI drift.
- `bound=N/N` counts a **compiled function table** in the bridge, populated by
  the generator from the same parse that produces the vtables, so a dropped or
  renamed stub cannot pass unnoticed (count + per-interface buckets + link).
- `dxil.dll` is absent from the SDK `Bin` on this host; validator objects
  create (factory 9/9) but `Validate` is bound-only until a signing companion
  is available. See `docs/COVERAGE.md` Â§2 for the full bound-vs-functional map.
- COM-allocated out strings (`LPWSTR*`, `BSTR*`, `char**`) are copied into XIOM
  slots and freed through runtime-resolved `CoTaskMemFree`/`SysFreeString`
  (no import libraries); if the allocator DLL cannot be loaded the copy still
  succeeds and the free is skipped (documented leak-avoidance).

## Known limitations

- Windows x64 DLL name only (`dxcompiler.dll`).
- Bound-but-not-functionally-exercised methods are enumerated with reasons in
  `docs/COVERAGE.md` Â§2 (PDB pipeline, validator signing, IMalloc-taking
  methods, linker/assembler/optimizer execution).
- `CLSID_DxcDiaDataSource` is bound in the CLSID table but has no IID in
  `dxcapi.h` (DIA SDK header); reachable via the generic `dxc_create_instance`.
- The compiler-absent SKIP path is code-reviewed + classified every run via a
  bogus soname; it is not reproducible on this host (SDK `Bin` on PATH).
