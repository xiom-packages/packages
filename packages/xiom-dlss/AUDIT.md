# AUDIT: xiom.dlss

## Status (2026-10-13, v0.64.4)

New package at 0.1.0: CLOSED-SDK declarative binding at full declared-surface
coverage; the runtime is dynamic-loaded and SKIP-safe.  No pre-pilot module
exists in git history for this package.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Upstream | DLSS SDK v310.9.1, commit `37495948` (reference-only; NVIDIA RTX SDKs License, CLOSED -- nothing vendored) |
| Link model | none; runtime `xiom.ffi.dl` loading of nvngx_dlss.dll / nvngx.dll / _nvngx.dll / nvngx_dlssg.dll / nvngx_dlssd.dll |
| FFI confinement | all `unsafe`/dynamic loading in `src/dlss.xi` (G5); `src/surface.xi` is generated data |
| Surface | 85 entries (15/15/17/20/16/2 by group) + 435 parameter keys + 74 effective-key codes + 19 result codes + ~70 enum/flag constants; 100% exposed |
| Suite | `tests/test_conformance.xi` |
| Runs | default: 21/21 x2 PASS (SKIP branches exercised); present path (local, `XIOM_DLSS_DIR` = pinned clone `rel/`): 22/22 PASS, 41/85 resolved against the real `nvngx_dlss.dll` |

## Design notes

- **The declared table is verified against two oracles at the pin**: every
  name is checked against the pinned `include/*.h` by the generator, and the
  observed `nvngx_dlss*.dll` export sets (`llvm-objdump -p`) confirm the
  resolvable subset.  Direct-module resolution counts (41/36/41 of 85) and
  the full table expectation (core proxy supplies the parameter API and the
  remaining core entries) are recorded in `SPEC.md` section 2.
- **Typed parameter C API** covers all 16 entries.  `Set*` are void per the
  header; `Get*` return `NVSDK_NGX_Result` and write an out-param: the
  wrappers allocate one XIOM-owned byte slot per call, read it
  byte-indexed, and read floats through `xiom.ffi.safe_ptr_from_raw`
  wrappers of the same owned buffer -- B-12 (no fp cast-call returns), B-20
  /B-24 (owned memory only), B-05/B-11 conscious (no alloc/free pair near
  confinement; per-call slots are fresh).
- **B-11 caveat (documented risk):** out-param slot reads through a driver
  component can be recycled on v0.64.4 (Vulkan-repro finding).  The typed
  getters are SKIP-untested on this host (no runtime); if a present-path
  host sees slots recycle through NGX calls, route those reads through
  bridge-owned scalars (the vma/zstd pattern) at the next touch --
  `ROADMAP.md` tracks it.
- **`DLSS_RC_UNRESOLVED` (-1)** is the typed unresolved sentinel; typed
  wrappers return it instead of calling nothing silently.  `dlss_failed`
  uses the B-27-safe boundary form (see below).
- **Loader classification**: no module -> `DLSS_LOAD_ABSENT` (suite SKIP);
  module opened but no D3D12 anchor -> `DLSS_LOAD_ABI` (suite would FAIL --
  a loaded module claiming an NGX name without NGX exports is an ABI
  problem, not a skip).  Probe/dedupe: bare names first (loader search),
  then cwd, then `%SystemRoot%\System32`.
- **Wide path helper**: `dlss_wide_path` emits UTF-16LE + NUL for `Init`'s
  `InApplicationDataPath`; ASCII-only, documented.
- **No NVIDIA code, doc text or binaries** anywhere in the package: the
  declarations are interface facts transcribed from the pinned headers
  (names, key strings, numeric codes; `PROVENANCE.md` sections 2/5).

## B-27 record (new compiler finding)

Found building this package: on v0.64.4, bitwise ops and integer division on
Int values >= 2^31 miscompile (`3132620800 >> 20` = 2987 not 2989;
`& 0xFFF00000` yields `0xBAC00000`; `/ 2^20` = 2987).  Repro:
`docs/repro/bindings-pilot/bigint-bitops/probe.xi` (standalone; exits 1
while broken); ledger row B-27 in `docs/BINDINGS-COMPILER-FINDINGS.md`.
This package ships `dlss_failed(rc) = (rc - 0xBAD00000) in [0, 18]` (exact
over the pinned 19-code failure space) and pins the result-code semantics
in-suite; restore a bitwise form after a fix re-probe.

## Coverage ledger (declared surface)

| Upstream item | Bound | Tested |
|---------------|-------|--------|
| Core entry table (85 names, 6 groups) | yes | count/dups/prefixes/anchors (6 checks) |
| Runtime spellings (Init_ProjectID aliases) | yes | alias count + resolver tries them (`dle_entry_resolved_as`) |
| Parameter keys 435 | yes | table completeness + uniqueness + value spot-checks |
| Effective-key byte codes 74 | yes | count + anchors + builder bytes (0/1/16) |
| Result codes + SUCCEED/FAILED | yes | full set + semantics pins (B-27-safe form) |
| Feature ids / flags / perf quality / presets / FG+RR enums | yes | pinned anchors |
| Loader + classification | yes | bogus-path ABSENT; default SKIP; present path 41/85 |
| Typed D3D12 SR create/evaluate/destroy/optimal settings | yes | compile-typed; runtime-absent -> SKIP (present host: 41/85 resolution proven, calls untested by design) |
| Reflex (PCL stats/markers) | not in headers | scan evidence; typed scope SKIP |
