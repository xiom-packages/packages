# SPEC: xiom.dxc -- DirectX Shader Compiler 100% COM binding

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.dxc` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | DirectXShaderCompiler -- https://github.com/microsoft/DirectXShaderCompiler |
| Upstream version pinned | dxcompiler.dll 1.9.0.5347 (commit `fe2615732`, as shipped with Vulkan SDK 1.4.350.0) |
| Upstream license | MIT (LLVM-style); nothing vendored -- the generator/bridge are our code |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `dxcompiler.dll`) |
| Compiler pin | v0.64.3 |

## 2. G2 pin: soname + header hash + COM ABI

**Soname (runtime contract):** `dxcompiler.dll`. Resolved at runtime via
`LoadLibraryA` + `GetProcAddress("DxcCreateInstance")`; no import library, no
`dxcapi.h` at build time, nothing vendored.

**Header pin** (the oracle; parsed by `tools/gen_dxc.py`, not included at build):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| SDK copy: `C:\VulkanSDK\1.4.350.0\Include\dxc\dxcapi.h` | 54,624 | `FF3CA20C5FF948D7B1050C4B96D1EE42A9ECC054724DC4DAFBEF50CC04FD1CDE` |
| Upstream cross-reference: `include/dxc/dxcapi.h` at commit `fe2615732` | 53,314 | `A8D409642DED485EA4FD4C055F1199A13538F0393755C2D958ADE281AFED4CA0` |

**Upstream clone** (verified 2026-10-12, upstream-first policy): pinned commit
`fe2615732899960b4077d02511810a80ccc4ffc9` (2026-04-30, "[SPIRV] Update
spirv-tools to v2026.2.rc2 (#8415)"), ancestor of tag `v1.9.2609`, in the
shared clone `E:\repos\DirectXShaderCompiler` (blobless, sparse
`include/dxc/`); license LLVM/NCSA. Provenance: `PROVENANCE.md`.

The SDK copy is the pin (it is what ships with the DLL on this host); the
upstream hash is a cross-reference. `--check` re-parses the pinned header and
fails on any drift in the committed generated files (counts, vtables, GUIDs).

**COM ABI pinned** (parsed from the header above; the bridge declares it
locally in generated `src/dxc_abi.h`):

| Item | Value |
|------|-------|
| `CLSID_DxcCompiler` | `{73e22d93-e6ce-47f3-b5bf-f0664f39c1b0}` |
| `CLSID_DxcUtils` (alias of `CLSID_DxcLibrary`) | `{6245d6af-66e0-48fd-80b4-4d271796748c}` |
| `IID_IDxcCompiler3` / `IID_IDxcResult` / `IID_IDxcBlob` | `{228b4687-...}` / `{58346cda-...}` / `{8ba5fb08-...}` |
| Interfaces / methods / CLSIDs / free functions | 27 / 128 / 12 / 2 (see `COVERAGE.md`, `docs/DXC-INVENTORY.md`) |
| Vtable order | flattened: IUnknown (3) + base chain + declared methods (slot index in the inventory) |
| `DxcBuffer`/`DxcText` | `{ const void* Ptr; size_t Size; uint32_t Encoding; }` (24 B on x64; 0 = ANSI/unknown) |

**Reference runtime sample used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| DLL | `C:\VulkanSDK\1.4.350.0\Bin\dxcompiler.dll`, 21,565,880 bytes, FileVersion 1.9.0.5347 (`fe2615732`), SHA256 `6E990D20E53390CDE413CE9A8016A8F43582E325A04CF72ECC706B4BEA504F0C` |
| Signing companion | `dxil.dll` NOT present in the SDK `Bin`; unsigned DXIL is emitted (validator path documented as bound-only) |
| Runtime report | `vs_6_0` vertex shader -> 2,684-byte DXIL container (`DXBC` magic); probe pixel shader -> 2,532 bytes; 9/9 CLSIDs create |

### Re-pin procedure

1. Update the SDK/package; record the new `dxcompiler.dll` FileVersion +
   SHA256 and the matching `dxcapi.h` hash (SDK copy + upstream commit).
2. Run `python tools/gen_dxc.py --header <new header> --package-dir .` and
   review the diff (counts, vtables, GUIDs); the generator fails loudly on any
   construct it does not understand.
3. Re-run `scripts/port.ps1 -Package xiom.dxc -TimeoutSec 900` (x2) and record.

## 3. Design

- **Generator** `tools/gen_dxc.py` (committed; the only source of truth for
  the surface) parses `dxcapi.h` and emits: `src/dxc_abi.h` (GUID + vtable
  structs + struct layouts), `src/dxc_bridge.cpp` (loader + one `extern "C"`
  stub per declared method + bound-method table + CLSID/IID tables),
  family-split XIOM wrapper modules (`src/dxc_gen_*.xi`), and
  `docs/DXC-INVENTORY.md`. `--check` verifies committed == regenerated.
- **Bridge** (`src/dxc_bridge.cpp`, no DXC/SDK headers at build): resolves
  `dxcompiler.dll` at runtime; objects cross the XIOM boundary as opaque `Int`
  handles; every out-param is copied into an XIOM-owned byte slot (LE scalars;
  owned byte/UTF-8 copies) -- the B-11..B-20-safe shape. UTF-8/UTF-16
  conversion is bridge-side; COM-allocated strings are freed via
  runtime-resolved `CoTaskMemFree`/`SysFreeString` (no import libraries).
- **XIOM modules**: root `xiom.dxc` keeps the hand-written probe API
  (`dxc_probe`/`dxc_probe_named`); generated modules `xiom.dxc.gen_support`,
  `xiom.dxc.gen_runtime`, and one per interface family carry the typed
  wrappers. All `unsafe`/`extern` live in the generated modules + root (G5).
- **Classification**: compiler missing -> `DXC_LOAD_ABSENT` (SKIP); missing
  `DxcCreateInstance` -> `DXC_LOAD_ABI` (FAIL); present-but-compile-failure ->
  FAIL (the probe shader cannot legitimately fail on a healthy SDK). The
  surface checks (`bound=N/N`) are DLL-independent and run on every host.
- The pre-0.3.0 header-based bridge (`dxc_bridge.c/h`, `src/dxc_safe.xi`) and
  the 0.2.0 probe remain in git history; `src/dxc_probe.c` is retained as the
  deterministic SKIP-classification probe.

## 4. Test matrix (recorded 2026-10-12, compiler v0.64.3)

| Configuration | Command | Result |
|---------------|---------|--------|
| DXC present (SDK 1.4.350.0, `dxcompiler.dll` 1.9.0.5347 on PATH) | `scripts/port.ps1 -Package xiom.dxc -TimeoutSec 900` | **PASS 20/20 x2** -- `bound=128/128`, compile/error/reflection/disasm/factory/lifecycle probes green |
| Compiler absent (CI shape) | not reproducible on this host (SDK `Bin` is on PATH); absent path is exercised every run via the bogus-soname classification | SKIP path exercised + code-reviewed |
| Generator drift | `python tools/gen_dxc.py --check` | OK -- committed output matches the pinned header parse |

## 5. Scope

100% of the `dxcapi.h` COM surface: 27 interfaces / 128 methods across 13
generated wrapper modules, plus the 2 free functions, 12 named CLSIDs and 27
IIDs. Functional probes cover the compile pipeline (Utils/Compiler3/Result/
Blob/BlobEncoding/VersionInfo/IncludeHandler/ContainerReflection); class
creation is verified for 9/9 convenience CLSIDs. Bound-but-not-functionally-
exercised methods (PDB tooling, validator signing without `dxil.dll`,
IMalloc-taking methods, linker/assembler/optimizer execution) are listed with
reasons in `docs/COVERAGE.md`. SKIP-green when the DLL is absent.

**Non-goals (explicit)**: the upstream `include/dxc/` siblings are NOT part of
the pinned oracle. `docs/COVERAGE.md` §2 records a runtime census of what the
shipped DLL actually implements: `dxcisense.h` (15 interfaces) and
`dxctools.h` (`IDxcRewriter`/`IDxcRewriter2`) classes ARE creatable via
`DxcCreateInstance` and are follow-up-slice candidates; `dxcpix.h` and
`dxcdxrfallbackcompiler.h` classes are not registered in this DLL;
`dxcerrors.h` is macros only; `dxcapi.internal.h` is internal.
