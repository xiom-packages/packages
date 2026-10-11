# PROVENANCE -- xiom.spirv-cross

Upstream-first record (policy: `docs/UPSTREAM-FIRST.md` in xiom-packages/packages).

## Upstream

| Item | Value |
|---|---|
| Project | SPIRV-Cross (Khronos Group) |
| Repository | https://github.com/KhronosGroup/SPIRV-Cross |
| License | Apache-2.0 (repo `LICENSE`; per-file headers Apache-2.0) |
| Pinned commit | `1a6169566c73d3da552748fc372fe2bbb856e46e` |
| Pin description | `vulkan-sdk-1.4.341.0-67-g1a616956` (2026-04-30) |
| Pin evidence | the shipped DLL itself reports it: `spvc_get_commit_revision_and_timestamp()` -> `Git commit: vulkan-sdk-1.4.341.0-67-g1a616956 Timestamp: 2026-05-11T10:55:23` |
| Studied clone | `E:\repos\SPIRV-Cross` (detached at the pinned commit) |
| Governing header set | `spirv_cross_c.h` + `spirv.h` (Vulkan SDK 1.4.350.0 pins, SPEC.md) |

## Equivalence proof (SDK vendor == upstream pin)

Verified on 2026-10-11 against the clone at the pinned commit:

- `spirv_cross_c.h`: SDK file and clone file are identical modulo CRLF
  (both 55,185 bytes LF-normalized, 0 byte differences; SHA256 of the SDK
  file = `8939834EFB802521AD36F97F2AFD83FA03A0DAECBEFC2124C4E56BE77D126D4F`).
- `spirv.h`: identical modulo CRLF (both 320,719 bytes LF-normalized,
  0 byte differences; SDK SHA256 = `62E24E3F287D612B47163350A04AA0B49822C1437BE407FBE10E488B9E4ADF3A`).
- Oracle re-parse of the UPSTREAM header
  (`python tools/gen_spirv_cross.py --check --header E:\repos\SPIRV-Cross\spirv_cross_c.h`)
  yields exactly the shipped inventory: 169 functions in the same 10 family
  split, 23 enums / 242 members / 19 macros / 17 structs.

## Derived vs independent

- **Derived (interface facts only):** symbol names, parameter/return
  declarations, enum member values and macro values, struct member layout
  -- all mechanically parsed from `spirv_cross_c.h` by the committed
  generator. These are the API's public interface, not implementation.
- **Independent:** the XIOM loader, resolver, slot discipline, wrappers,
  fixtures and suite are written in this package; no upstream C/C++ source
  is copied or vendored, and no upstream code is compiled or linked. The
  runtime uses the SDK-shipped binary `spirv-cross-c-shared.dll` via
  `xiom.ffi.dl` only.
- Family split (context/compiler/glsl/hlsl/msl/resources/type/constant/
  buffer/reflect) and the out-slot conventions are this package's design
  (see SPEC.md).

## Test vectors / golden data

- `tools/shaders/min.frag.spvasm` + `min.frag.spv` (141 words, 564 bytes) is
  authored here as hand-written SPIR-V 1.0 assembly, assembled with the
  SDK's `spirv-as` (`--target-env vulkan1.0`) and validated with `spirv-val`.
  It is derived from the SPIR-V specification, not from upstream test data.
- Expected behavior asserted by the suite: GLSL cross-compile output
  contains `void main`; reflection reports 3 resources (UBO + stage input +
  stage output); entry-point model is Fragment; `spvc_get_version` ==
  0.68.0. No upstream golden files are imported.

## Re-carve (refresh procedure)

1. Take the new SDK DLL's revision: `spvc_get_commit_revision_and_timestamp()`.
2. `git -C E:\repos\SPIRV-Cross fetch --filter=blob:none --shallow-exclude=<prev tag> origin main`
   (or a shallow tag clone) and check out the new pin; re-verify the header
   hashes against the new SDK (modulo CRLF).
3. `python tools/gen_spirv_cross.py` + `tools/embed_spv_xiom.py`; re-run
   `tools/check_exports.py`; x2 `scripts/port.ps1`; update SPEC.md hashes
   and this file; record with `scripts/status.ps1`.

## Clone hygiene (E:\repos)

Suggested ledger row for `E:\repos\CLEANUP.md` (owner-maintained; not edited
by this lane):

```
| SPIRV-Cross | github.com/KhronosGroup/SPIRV-Cross (Apache-2.0) | 2026-10-11 | bindings (xiom.spirv-cross) | 2026-12-01 | active |
```
