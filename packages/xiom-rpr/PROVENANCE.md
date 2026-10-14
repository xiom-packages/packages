# PROVENANCE -- xiom.rpr

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% of the declared
surface) and docs/BINDINGS-LANE.md (gates G0-G7).

## Upstream (oracle)

- `github.com/GPUOpen-LibrariesAndSDKs/RadeonProRenderSDK`, tag **v3.1.7.1**
  = commit **`2edd23c5fdb8eabf40bdf1ba4f6509e203e28c51`** (latest release,
  published 2026-09-10; `git describe` -> `v3.1.7.1`).
- Clone: `E:\repos\RadeonProRenderSDK` (shallow at the tag).
- License verified in the clone: **Apache-2.0** (`license.txt`, "Copyright(C)
  2019-2023 Advanced Micro Devices, Inc.", full Apache-2.0 text). Class:
  permissive -- vendoring is allowed; redistribution must keep the license
  text (done: `vendor/rpr/license.txt`).
- The release carries prebuilt `binWin64` libraries (also tracked in the git
  repo).  Decision and rationale in SPEC.md sec. 2: **headers vendored,
  binaries NOT vendored** (runtime loader; the `binWin64` set is a local
  sample only).

## Vendored files (byte pins)

Vendored with `git show v3.1.7.1:<path>` so the stored bytes are the git blob
bytes (LF), not a CRLF checkout.  Hashes are over the stored bytes; the blob
SHA1s are the upstream git object ids (both verify byte-identity).

| Vendored | Origin | Bytes | Blob SHA1 | SHA256 |
|----------|--------|-------|-----------|--------|
| `vendor/rpr/RadeonProRender.h` | v3.1.7.1 `RadeonProRender/inc/` | 158,463 | `445fb9e53718898e218428c2f53315e9ef62dc86` | `57FF864D1B8DFBD3C754A81413DEC5536AA3D509209A10A8A35D1870FCD5FD20` |
| `vendor/rpr/license.txt` | v3.1.7.1 root | 1,842 | `0bfb67e8ef355c720f12024fe824011d1374e970` | `5AF0AD505B68B05EC5C5381595582769B9BCAAFFED618CDE3A1A46AC691D932C` |

The header is the declaration oracle for the declared surface: every bridged
symbol, constant value and typedef in `docs/COVERAGE.md` is verified against
it by `tools/surface_rpr.py` (fail-closed; it also re-checks both hashes).

## Local runtime samples (NOT the pin; nothing committed)

The present-path proof uses the SDK's own `binWin64` directory (clone
`E:\repos\RadeonProRenderSDK\RadeonProRender\binWin64`) placed on PATH or
named through `XIOM_RPR_SDK_DIR` at run time -- the libpq/raylib/ffmpeg
local-binary pattern.  Recorded on 2026-10-14 (host: AMD Ryzen 9 3950X +
NVIDIA GeForce RTX 3070 Ti, Windows x64):

| Binary | Bytes | SHA256 | Recorded behavior on this host |
|--------|-------|--------|--------------------------------|
| `RadeonProRender64.dll` | 4,728,320 | `03A81EAC65A4947CE6D41117166E84D746119D4B734F7C49CAE93AC96B78A576` | host API loads; no missing entry point |
| `Northstar64.dll` (CPU) | 42,341,888 | `D9960A9771DCD93728B8078481CB83394F2BF1448B6A08CFDE1B13A68434904E` | registers (plugin id 0); context on "AMD Ryzen 9 3950X 16-Core Processor"; **renders** the 16x16 scene (read-back non-uniform, finite) |
| `Tahoe64.dll` (GPU) | 20,999,888 | `5C486AA60BD91DCD94BC2008531880A02EE8968B4C3E79BD683CCD415F1EA39B` | registers; context enumerates "NVIDIA GeForce RTX 3070 Ti"; render calls succeed but the framebuffer is blank -> typed `SKIP(no render output on host)` |
| `HybridPro.dll` (GPU) | 20,807,376 | `651BAD0BA10C0B1763F5E06C8AB91C19F7ACAE2F0F506953970646ABE6C537AC` | same as Tahoe64 (hardware-RT shaders compile, blank frame) -> typed SKIP |
| `Hybrid.dll` (legacy GPU) | 13,352,144 | `D8FDECD881242649D8DDADAE0BBEFF7F71CC18D42BC5B46A2FF57BFAE18B4A24` | **access violation (0xC0000005) on this host** (needs its AMD/OpenCL environment); audited non-goal -- excluded from the default probe list, still reachable via `probe_backend` for users who know their host supports it |

## Derived vs independent

- **Derived (verbatim vendored):** `RadeonProRender.h`, `license.txt` only.
- **Original to this package (MIT OR Apache-2.0):** `src/rpr_bridge.c`
  (runtime loader + flat ABI + object registry), `src/rpr.xi`,
  `src/rpr_ffi.xi`, `tests/test_conformance.xi`, `tools/surface_rpr.py`,
  the docs.
- **Coverage proof:** `docs/COVERAGE.md` + `docs/surface_rpr.json` -- 34
  bridged functions + 31 modeled constants + 23 modeled core typedefs = 88
  declared items, 0 gaps, regenerated fail-closed from the pinned header.
- **Portability workarounds recorded in SPEC.md sec. 4** (v0.64.4): handles
  cross as integer ids (B-25), no foreign-pointer reads (B-20, the bridge
  copies into XIOM-owned buffers), no `null` from XIOM (B-23), scalar/packed
  returns for driver-heavy calls (B-11), and two delegation wrappers that hit
  a C001 unresolved-symbol codegen shape inside the full module now call the
  FFI layer directly.

## Test vectors

Upstream ships no ABI test vectors.  The conformance suite pins: the API
version constant (`RPR_CONTEXT_API_VERSION` == `RPR_API_VERSION` ==
0x00300107 read back from a live context), the framebuffer descriptor
(16x16 packed, read back through `rprFrameBufferGetInfo`), the read-back
sizes (1024 floats / 4096 bytes) and the render contract (non-uniform and
finite) on the CPU backend.  The bridge's byte-size handshake
(`out_count * 4 == GetInfo(DATA) size`) is exercised by a capacity-mismatch
error case.

## Clone ledger

Row in `E:\repos\CLEANUP.md` (bindings lane, review after 2026-12-01):
`RadeonProRenderSDK` (added 2026-10-14, xiom.rpr oracle + local present-path
sample; keep for re-carve).  Re-carve procedure: SPEC.md sec. 7.
