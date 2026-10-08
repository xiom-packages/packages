# SPEC: xiom.directx11 -- Direct3D 11 / DXGI capability probe

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.directx11` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Direct3D 11 / DXGI (Windows system components; Microsoft) |
| Upstream license | proprietary system API; nothing vendored -- the bridge is our code |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (system `d3d11.dll` + `dxgi.dll`) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: sonames + SDK header hashes + ABI

**Sonames (runtime contract):** `d3d11.dll` + `dxgi.dll`. Resolved at runtime
via `LoadLibraryA` + `GetProcAddress`; no import libraries, no SDK headers at
build time, nothing vendored.

**Header pin** (ABI source; not vendored; Windows SDK 10.0.22621.0):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `um\d3d11.h` | 578,617 | `B2C0CAA561CC1F422F31C44CA38C861C43A8FA135CCEF476EE2F3E47DCA99E2D` |
| `shared\dxgi.h` | 104,147 | `4B983AC75717296191A5FAEF4A87FF0B02B0E8D6202CD5AF85BF75ACCEA2CBBE` |
| `um\d3dcommon.h` | 49,619 | `62F7BF1A5F17A02834B2CE0CA892EA204EDD037AEA970B4961B04C74E426B4BC` |

**ABI pinned** (verified against those headers; declared locally in the
bridge):

| Item | Value |
|------|-------|
| `D3D11CreateDevice` | `(IDXGIAdapter*, D3D_DRIVER_TYPE, HMODULE, UINT flags, const D3D_FEATURE_LEVEL*, UINT, UINT sdk, ID3D11Device**, D3D_FEATURE_LEVEL*, ID3D11DeviceContext**) -> HRESULT` |
| Driver type / SDK version | `D3D_DRIVER_TYPE_HARDWARE = 1`, `D3D11_SDK_VERSION = 7` |
| Feature levels | `9_3=0x9300`, `10_0=0xa000`, `10_1=0xa100`, `11_0=0xb000`, `11_1=0xb100` |
| `IID_IDXGIFactory1` | `{770aae78-f26f-4dba-a829-253c83d1b387}` |
| `IDXGIFactory1` vtable | `IUnknown` 0-2, `IDXGIObject` 3-6, `IDXGIFactory` 7-11; **12 = `EnumAdapters1`**, 13 = `IsCurrent` |
| `IDXGIAdapter` vtable | `IUnknown` 0-2, `IDXGIObject` 3-6; 7 = `EnumOutputs`, **8 = `GetDesc`**, 9 = `CheckInterfaceSupport` |
| `DXGI_ADAPTER_DESC` | `WCHAR Description[128]` at 0 (256 B), `UINT VendorId` at 256, `UINT DeviceId` at 260 (received into an oversized buffer) |
| `CreateDXGIFactory1` | exported by `dxgi.dll` |

**Reference runtime sample used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| `System32\d3d11.dll` | 2,537,488 bytes, FileVersion 10.0.26100.9549, SHA256 `3E6C8932026FFB0DBA16207A4BB6793E56B9483FA2E19F36E68EF308ED027E25` |
| `System32\dxgi.dll` | 1,316,224 bytes, FileVersion 10.0.26100.9549, SHA256 `023542BB41AFCF0BA5EE02CB63CCBAEAB4765A5DD859A1B0A6E05FA9B739E89F` |
| Runtime report | hardware device at feature level 11_0 (45056); 3 adapters; first = `NVIDIA GeForce RTX 3070 Ti` (vendor_id 4318 = 0x10DE, device_id 9346 = 0x2482) |

### Re-pin procedure

1. On a new SDK/host, re-verify the vtables/offsets against the headers
   before touching the bridge (they are the ABI; a wrong slot crashes).
2. Update the header hashes above and the version rows in `README.md`/
   `AUDIT.md` in one commit; record the new DLL sample.
3. Re-run `scripts/port.ps1 -Package xiom.directx11` and record the matrix.

## 3. Design

- `src/d3d11_probe.c` (our code, MIT/Apache) includes **no SDK headers**: the
  ABI is declared locally and objects are driven through raw vtable pointers.
  It links only kernel32 (`WideCharToMultiByte`); `port.args.json` compiles
  it via `--c-source` with no `--link` flags.
- The XIOM module (`directx11.xi`, module `xiom.directx11`) is a thin safe
  wrapper; all `unsafe`/`extern` are confined to this single module (G5).
  Public API: `d3d11_probe`, `d3d11_probe_named`,
  `d3d11_feature_level_name`, `D3d11Info`, `D3d11LoadError`, constants.
- **Classification**: `d3d11.dll`/`dxgi.dll` missing -> `D3D11_LOAD_ABSENT`
  (SKIP); `D3D11CreateDevice(HARDWARE)` failed (no GPU/driver) ->
  `D3D11_LOAD_NO_DEVICE` (SKIP); entry points missing -> `D3D11_LOAD_ABI`
  (FAIL). A bogus soname exercises the SKIP path deterministically on any
  host.
- The pre-pilot module (`directx11.xi` with static `extern "C"` D3D
  declarations) required the SDK import libraries at link time and is
  preserved in git history.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| D3D11 present (System32, NVIDIA RTX 3070 Ti) | `scripts/port.ps1 -Package xiom.directx11` | **PASS 5/5 x2** -- feature-level names, SKIP classification (bogus sonames), hardware device at 11_0, 3 adapters, first adapter `NVIDIA GeForce RTX 3070 Ti` |
| No GPU / libraries absent | not reproducible on this host; SKIP kinds code-reviewed; bogus-soname classification runs every suite invocation | SKIP path exercised + code-reviewed |

## 5. Scope

Capability probe only. Device/context creation with flags, IDXGISwapChain,
render targets, shaders (hand off to `xiom.dxc` for HLSL), and resource
bindings are later phases (`ROADMAP.md`).
