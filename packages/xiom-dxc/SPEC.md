# SPEC: xiom.dxc -- DirectX Shader Compiler capability probe

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.dxc` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | DirectXShaderCompiler -- https://github.com/microsoft/DirectXShaderCompiler |
| Upstream version pinned | dxcompiler.dll 1.9.0.5347 (commit `fe2615732`, as shipped with Vulkan SDK 1.4.350.0) |
| Upstream license | MIT (LLVM-style); nothing vendored -- the bridge is our code |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `dxcompiler.dll`) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: soname + header hash + COM ABI

**Soname (runtime contract):** `dxcompiler.dll`. Resolved at runtime via
`LoadLibraryA` + `GetProcAddress("DxcCreateInstance")`; no import library, no
`dxcapi.h` at build time, nothing vendored.

**Header pin** (documentation/ABI source; not vendored):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| SDK copy: `C:\VulkanSDK\1.4.350.0\Include\dxc\dxcapi.h` | 54,624 | `FF3CA20C5FF948D7B1050C4B96D1EE42A9ECC054724DC4DAFBEF50CC04FD1CDE` |
| Upstream cross-reference: `include/dxc/dxcapi.h` at commit `fe2615732` | 53,314 | `A8D409642DED485EA4FD4C055F1199A13538F0393755C2D958ADE281AFED4CA0` |

**COM ABI pinned** (verified against the header above; the bridge declares it
locally):

| Item | Value |
|------|-------|
| `CLSID_DxcCompiler` | `{73e22d93-e6ce-47f3-b5bf-f0664f39c1b0}` |
| `IID_IDxcCompiler3` | `{228b4687-5a6a-4730-900c-9702b2203f54}` |
| `IID_IDxcResult` | `{58346cda-dde7-4497-9461-6f87af5e0659}` |
| `IID_IDxcBlob` | `{8ba5fb08-5195-40e2-ac58-0d989c3a0102}` |
| `IDxcCompiler3` vtable | `IUnknown` + 3 `Compile`, 4 `Disassemble` |
| `IDxcResult` vtable | `IDxcOperationResult`: 3 `GetStatus`, 4 `GetResult`, 5 `GetErrorBuffer`; then 6 `HasOutput`, 7 `GetOutput` |
| `IDxcBlob` vtable | 3 `GetBufferPointer`, 4 `GetBufferSize` |
| `DxcBuffer`/`DxcText` | `{ const void* Ptr; size_t Size; uint32_t Encoding; }` (24 B on x64; 0 = ANSI/unknown) |
| `DXC_OUT_OBJECT` | 1 |

**Reference runtime sample used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| DLL | `C:\VulkanSDK\1.4.350.0\Bin\dxcompiler.dll` (on the SDK `Bin`, present on PATH here), 21,565,880 bytes, FileVersion 1.9.0.5347 (`fe2615732`), SHA256 `6E990D20E53390CDE413CE9A8016A8F43582E325A04CF72ECC706B4BEA504F0C` |
| Signing companion | `dxil.dll` NOT present in the SDK `Bin`; the probe emits unsigned DXIL, which is fine for capability reporting |
| Runtime report | `ps_6_0` pixel shader `main` compiled to a 2,532-byte DXIL object |

### Re-pin procedure

1. Update the SDK/package; record the new `dxcompiler.dll` FileVersion +
   SHA256 and the matching `dxcapi.h` hash (SDK copy + upstream commit).
2. Re-verify the GUIDs and vtable slots against the header before touching
   the bridge; they are the ABI.
3. Re-run `scripts/port.ps1 -Package xiom.dxc` and record the run.

## 3. Design

- `src/dxc_probe.c` (our code, MIT/Apache) includes **no `dxcapi.h`**: GUIDs,
  vtable-slot offsets, and `DxcBuffer` are declared locally (checked against
  the pinned header) and objects are driven through raw vtable pointers. It
  links only kernel32; `port.args.json` compiles it via `--c-source` with no
  `--link` flags.
- The XIOM module (`dxc.xi`, module `xiom.dxc`) is a thin safe wrapper; all
  `unsafe`/`extern` are confined to this single module (G5). Public API:
  `dxc_probe`, `dxc_probe_named`, `DxcInfo`, `DxcLoadError`.
- **Classification**: compiler missing -> `DXC_LOAD_ABSENT` (SKIP); missing
  `DxcCreateInstance` or refused `IDxcCompiler3` instance -> `DXC_LOAD_ABI`
  (FAIL); trivial-shader compile failure on a present compiler ->
  `DXC_COMPILE_FAILED` (FAIL -- the probe shader cannot legitimately fail on
  a healthy SDK).
- Probes are atomic (load -> instance -> compile -> unload); a bogus soname
  exercises the SKIP path deterministically on any host.
- The pre-pilot bridge (`dxc_bridge.c/h`, `src/dxc_safe.xi`, demo) required
  `dxcapi.h` + import libraries at build time and is preserved in git
  history.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| DXC present (SDK 1.4.350.0, `dxcompiler.dll` 1.9.0.5347 on PATH) | `scripts/port.ps1 -Package xiom.dxc` | **PASS 3/3 x2** -- SKIP classification (bogus soname), `ps_6_0` compile -> 2,532-byte DXIL blob, 4-byte-aligned container |
| Compiler absent (CI shape) | not reproducible on this host (SDK `Bin` is on PATH); the bogus-soname classification runs every suite invocation | SKIP path exercised + code-reviewed |

## 5. Scope

Capability probe only: load, COM instance, one fixed `ps_6_0` compile.
Generic compile API (source/target/entry/defines from XIOM), include handlers,
the validator (`dxil.dll`) and signature info are later phases
(`ROADMAP.md`).
