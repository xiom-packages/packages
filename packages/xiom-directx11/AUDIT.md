# AUDIT: xiom.directx11

## Status (2026-10-08)

Capability-probe implementation at 0.2.0. The pre-pilot module
(`directx11.xi`, 22 KB of static `extern "C"` D3D declarations) required SDK
import libraries at link time and could not satisfy the SKIP-when-absent
gate; it is preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Pin | sonames + SDK header hashes + IIDs/vtable slots/struct offsets (`SPEC.md` §2) |
| Link model | none at build time; runtime `LoadLibraryA` + `GetProcAddress`; **no SDK headers included** |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/d3d11_probe.c` (no `--link`) |
| FFI confinement | all `unsafe`/`extern` in the root module `xiom.directx11` (G5); the bridge is plain C with no XIOM unsafe |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 5/5 x2** via `scripts/port.ps1`: hardware device at 11_0, 3 adapters, `NVIDIA GeForce RTX 3070 Ti`; deterministic SKIP classification per run |

## Design notes

- The DXGI COM vtables were pinned from `dxgi.h` before writing the bridge
  (`IDXGIFactory1` slot 12 = `EnumAdapters1`; `IDXGIAdapter` slot 8 =
  `GetDesc`; `DXGI_ADAPTER_DESC` offsets 0/256/260) -- a wrong slot would
  crash rather than fail softly.
- `D3D11CreateDevice` with NULL feature-level array returns the default 11_0
  on this driver; explicit 11_1 requires the caller to request it -- the
  probe reports what the API returns.
- Adapter count is 3 on this host (hardware + fallback enumerations); the
  first adapter description is reported.
- `vendor_id 4318` = 0x10DE (NVIDIA), `device_id 9346` = 0x2482 (RTX 3070 Ti).

## Known limitations

- Device flags, debug layer, WARP/software fallback and feature-level
  requests are not exposed yet (Phase 2).
- Swapchain/render/resource surfaces and HLSL hand-off (`xiom.dxc`) are
  Phase 2.
- Windows only; the SKIP path for machines without D3D11 is code-reviewed
  (the bogus-soname classification runs every suite run).
