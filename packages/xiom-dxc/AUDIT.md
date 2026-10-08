# AUDIT: xiom.dxc

## Status (2026-10-08)

Capability-probe implementation at 0.2.0. The pre-pilot implementation
(`dxc_bridge.c/h` + `src/dxc_safe.xi` + demo, ~77 KB) included `dxcapi.h`
and linked DXC at build time; it is preserved in git history only as
reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Pin | soname `dxcompiler.dll` + `dxcapi.h` hashes + COM GUID/vtable ABI (`SPEC.md` §2) |
| Link model | none at build time; runtime `LoadLibraryA` + `DxcCreateInstance`; **no `dxcapi.h` included** (ABI declared locally, objects driven via raw vtable pointers) |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/dxc_probe.c` (no `--link`) |
| FFI confinement | all `unsafe`/`extern` in the root module `xiom.dxc` (G5); the bridge is plain C with no XIOM unsafe |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 3/3 x2** via `scripts/port.ps1`: `ps_6_0` compile -> 2,532-byte DXIL object; deterministic SKIP classification per run |

## Design notes

- The COM ABI (GUIDs + vtable slot offsets: compiler 3=Compile; result
  3=GetStatus, 7=GetOutput; blob 4=GetBufferSize) was extracted from the
  pinned `dxcapi.h` before writing the bridge -- a wrong slot would crash
  rather than fail softly, so the header was treated as the specification.
- `dxil.dll` is not shipped by the SDK `Bin` on this host; the probe emits
  unsigned DXIL, which is sufficient for capability reporting. The validator
  seam is a roadmap item.
- Probe failure policy: the shell-level shader is trivial, so
  `DXC_COMPILE_FAILED` is a FAIL (not a SKIP) -- it means a real ABI/SDK
  mismatch on a present compiler.

## Known limitations

- Fixed compile shape only (`ps_6_0`, entry `main`, no defines/includes);
  a generic compile API is Phase 2.
- Windows DLL name only (`dxcompiler.dll`).
- No validator/signature-info surface yet (`dxil.dll`, `IDxcValidator`).
- The compiler-absent SKIP path is code-reviewed; the bogus-soname
  classification runs in every suite run.
