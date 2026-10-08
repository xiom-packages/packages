# SPEC: xiom.directx12 -- Direct3D 12 / DXGI capability probe

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.directx12` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Direct3D 12 / DXGI (Windows system components; Microsoft) |
| Upstream license | proprietary system API; nothing vendored -- the bridge is our code |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (system `d3d12.dll` + `dxgi.dll`) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: sonames + SDK header hashes + ABI

**Sonames (runtime contract):** `d3d12.dll` + `dxgi.dll`. Resolved at runtime
via `LoadLibraryA` + `GetProcAddress`; no import libraries, no SDK headers at
build time, nothing vendored.

**Header pin** (ABI source; not vendored; Windows SDK 10.0.22621.0):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `um\d3d12.h` | 1,111,752 | `82EB33195558E43CEE6A254FB48C076D65FB55209BE2EB6878573585AA7AE5C8` |
| `shared\dxgi.h` | 104,147 | `4B983AC75717296191A5FAEF4A87FF0B02B0E8D6202CD5AF85BF75ACCEA2CBBE` |
| `um\d3dcommon.h` | 49,619 | `62F7BF1A5F17A02834B2CE0CA892EA204EDD037AEA970B4961B04C74E426B4BC` |

**ABI pinned** (verified against those headers; declared locally):

| Item | Value |
|------|-------|
| `D3D12CreateDevice` | `(IUnknown* pAdapter, D3D_FEATURE_LEVEL min, REFIID riid, void** device) -> HRESULT` |
| `IID_ID3D12Device` | `{189819f1-1db6-4b57-be54-1821339b85f7}` |
| Feature levels | `11_0=0xb000`, `11_1=0xb100`, `12_0=0xc000`, `12_1=0xc100`, `12_2=0xc200` |
| `IID_IDXGIFactory1` | `{770aae78-f26f-4dba-a829-253c83d1b387}` (shared with directx11) |
| `IDXGIFactory1` vtable | 12 = `EnumAdapters1` |
| `IDXGIAdapter` vtable | 8 = `GetDesc` |
| `DXGI_ADAPTER_DESC` | `Description` at 0 (256 B), `VendorId` at 256, `DeviceId` at 260 |
| Max-level method | descending `D3D12CreateDevice` attempts 12_2 -> 11_0; first accepted level is reported |

**Reference runtime sample used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| `System32\d3d12.dll` / `dxgi.dll` | Windows 10.0.26100.9549-era system components (same `dxgi.dll` sample as directx11: SHA256 `023542BB...`) |
| Runtime report | highest accepted feature level **12_2** (0xc200); 3 adapters; first = `NVIDIA GeForce RTX 3070 Ti` (vendor_id 4318 = 0x10DE, device_id 9346 = 0x2482) |

### Re-pin procedure

1. Re-verify the IID/vtable/offsets against the headers before touching the
   bridge (they are the ABI; a wrong slot crashes).
2. Update the header hashes and the version rows in `README.md`/`AUDIT.md` in
   one commit; record the new runtime sample.
3. Re-run `scripts/port.ps1 -Package xiom.directx12` and record the matrix.

## 3. Design

- `src/d3d12_probe.c` (our code, MIT/Apache) includes **no SDK headers**: the
  ABI is declared locally and objects are driven through raw vtable pointers.
  It links only kernel32; `port.args.json` compiles it via `--c-source` with
  no `--link` flags.
- The XIOM module (`directx12.xi`, module `xiom.directx12`) is a thin safe
  wrapper; all `unsafe`/`extern` are confined to this single module (G5).
  Public API: `d3d12_probe`, `d3d12_probe_named`,
  `d3d12_feature_level_name`, `D3d12Info`, `D3d12LoadError`, constants.
- **Classification**: `d3d12.dll`/`dxgi.dll` missing -> `D3D12_LOAD_ABSENT`
  (SKIP); every `D3D12CreateDevice` attempt refused (no DX12 driver) ->
  `D3D12_LOAD_NO_DEVICE` (SKIP); entry points missing -> `D3D12_LOAD_ABI`
  (FAIL). A bogus soname exercises the SKIP path deterministically.
- The pre-pilot module (`directx12.xi` with static `extern "C"` D3D
  declarations) required the SDK import libraries at link time and is
  preserved in git history.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| D3D12 present (System32, NVIDIA RTX 3070 Ti) | `scripts/port.ps1 -Package xiom.directx12` | **PASS 5/5 x2** -- feature-level names, SKIP classification (bogus sonames), highest accepted level 12_2, 3 adapters, first adapter `NVIDIA GeForce RTX 3070 Ti` |
| No DX12 device / libraries absent | not reproducible on this host; SKIP kinds code-reviewed; bogus-soname classification runs every suite invocation | SKIP path exercised + code-reviewed |

## 5. Scope

Capability probe only. Command queues, descriptors/heaps, root signatures,
pipelines (with `xiom.dxc` blobs), swapchains and resource barriers are later
phases (`ROADMAP.md`).
