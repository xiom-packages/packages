# PROVENANCE: xiom.dxc

Upstream-first record (owner policy 2026-10-11, `docs/UPSTREAM-FIRST.md`).

## Upstream

| Field | Value |
|-------|-------|
| Project | DirectXShaderCompiler (DXC) |
| Repository | https://github.com/microsoft/DirectXShaderCompiler |
| Pinned commit | `fe2615732899960b4077d02511810a80ccc4ffc9` (2026-04-30, "[SPIRV] Update spirv-tools to v2026.2.rc2 (#8415)") |
| Release window | ancestor of tag `v1.9.2609`; matches the shipped DLL `ProductVersion 1.9.0.5347 (fe2615732)` |
| License | LLVM Release License / University of Illinois/NCSA Open Source License (`LICENSE.TXT` at the pinned commit) |
| Clone | `E:\repos\DirectXShaderCompiler` — blobless clone of tag `v1.9.2609`, sparse checkout (`include/dxc/`) at the pinned commit; HEAD detached at `fe26157` |
| CLEANUP.md row | `| DirectXShaderCompiler | https://github.com/microsoft/DirectXShaderCompiler (LLVM Release License / NCSA) | 2026-10-11 | bindings (xiom.dxc) | 2026-12-01 | active |` (owner adds; this package does not edit the shared ledger) |

License note: NCSA/LLVM is a permissive BSD-3-clause-style attribution license
(not GPL/AGPL/SSPL/Elastic; no MPL/LGPL in the studied parts). It is not
literally one of the enumerated names in the owner whitelist
(MIT/Apache-2.0/BSD/ISC/zlib/PD/X11/Unicode/RFC) — flagged to the coordinator
for an explicit OK; nothing from upstream is copied into this repo either way
(see "Derived vs independent").

## Oracle source

The oracle is the DXC COM API header:

| Artifact | Bytes | SHA256 |
|----------|-------|--------|
| Pin (what the bridge is generated against): SDK copy `C:\VulkanSDK\1.4.350.0\Include\dxc\dxcapi.h` | 54,624 | `FF3CA20C5FF948D7B1050C4B96D1EE42A9ECC054724DC4DAFBEF50CC04FD1CDE` |
| Upstream cross-reference (verified in the clone): `include/dxc/dxcapi.h` @ `fe2615732` | 53,314 | `A8D409642DED485EA4FD4C055F1199A13538F0393755C2D958ADE281AFED4CA0` |

The SDK copy differs from upstream only in line endings/packaging (same
content, different hash — both recorded in `SPEC.md` §2). `tools/gen_dxc.py`
parses the pin; `--check` fails on any drift. Counts: 27 interfaces /
128 methods / 12 named CLSIDs / 27 IIDs / 2 free functions.

## Files studied

- `include/dxc/dxcapi.h` — the entire oracle: interface declarations, GUIDs
  (`CROSS_PLATFORM_UUIDOF`), CLSID literals, struct layouts (`DxcBuffer`,
  `DxcDefine`, `DxcArgPair`, `DxcShaderHash`), `DXC_OUT_KIND`.
- Census-only (not bound; see `docs/COVERAGE.md` §2): `dxcisense.h`,
  `dxctools.h`, `dxcpix.h`, `dxcdxrfallbackcompiler.h`, `dxcerrors.h`,
  `dxcapi.internal.h`.

No upstream implementation source (compiler, reflection, validator) was read or
re-implemented; this package binds the DLL's public COM surface at runtime.

## Derived vs independent

**Nothing is copied from upstream.** The package is an independent FFI
layer generated from interface *declarations*:

- The ABI facts it reproduces (GUID values, vtable slot order, struct layout,
  method names/signatures) are the interface identity; reproducing them is
  required for interoperability, not derivation. They come from the pinned
  header by mechanical parse (`tools/gen_dxc.py`), not from memory.
- `src/dxc_bridge.cpp` (loader, UTF-8/UTF-16 conversion, owned-slot
  marshalling, COM string frees, bound-method table) and the XIOM wrapper
  modules are original XIOM code.
- No upstream code, algorithms, or test vectors are vendored. The upstream
  license text is therefore not shipped; attribution stays in this file.

## Test vectors / golden data

None imported: bindings parity is behavioral. The suite compiles HLSL through
the actual DLL and checks DXC's own outputs (DXIL `DXBC` container produced by
the compiler, reflection/disassembly of that container, error blobs), so the
oracle is the DLL itself under the pinned header contract. `--check` pins the
generated surface to the header hash.

## Re-carve procedure

1. Clone the new upstream release into `E:\repos\DirectXShaderCompiler`
   (refresh), record the new commit/tag + `dxcapi.h` hashes.
2. `python tools/gen_dxc.py --header <new header> --package-dir .` and review
   the diff (counts, vtables, GUIDs); re-pin `SPEC.md` §2.
3. Re-run `scripts/port.ps1 -Package xiom.dxc` x2; update `STATUS.json`.
