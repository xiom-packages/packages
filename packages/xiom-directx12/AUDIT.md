# AUDIT: xiom.directx12

## Status (2026-10-08)

Capability-probe implementation at 0.2.0. The pre-pilot module
(`directx12.xi`, ~17 KB of static `extern "C"` D3D12 declarations) required
SDK import libraries at link time and could not satisfy the SKIP-when-absent
gate; it is preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Pin | sonames + SDK header hashes + IID/vtable slots/struct offsets + feature levels (`SPEC.md` §2) |
| Link model | none at build time; runtime `LoadLibraryA` + `GetProcAddress`; **no SDK headers included** |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/d3d12_probe.c` (no `--link`) |
| FFI confinement | all `unsafe`/`extern` in the root module `xiom.directx12` (G5); the bridge is plain C with no XIOM unsafe |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 5/5 x2** via `scripts/port.ps1`: highest accepted feature level **12_2**, 3 adapters, `NVIDIA GeForce RTX 3070 Ti`; deterministic SKIP classification per run |

## Design notes

- The max-level probe tries `D3D12CreateDevice` from 12_2 down to 11_0 and
  reports the first accepted level -- a real capability statement rather than
  the requested minimum.
- DXGI adapter enumeration reuses the exact vtables/offsets verified for
  `xiom.directx11` (factory slot 12 = EnumAdapters1, adapter slot 8 =
  GetDesc, desc offsets 0/256/260); `IID_ID3D12Device` =
  `{189819f1-1db6-4b57-be54-1821339b85f7}`.
- `D3D12CreateDevice(NULL, ...)` uses the default adapter, so the reported
  adapter description and the device capability come from the same GPU.

## Known limitations

- No command queue/device object beyond creation + release; no debug layer,
  no `ID3D12InfoQueue`.
- Swapchain, descriptors/heaps, root signatures, pipelines and barriers are
  Phase 2 (`ROADMAP.md`).
- Windows only; the no-DX12 SKIP path is code-reviewed (the bogus-soname
  classification runs every suite run).
