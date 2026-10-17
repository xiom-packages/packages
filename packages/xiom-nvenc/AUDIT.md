# AUDIT: xiom.nvenc

## Status (2026-10-17, v0.64.6)

Loader-only implementation at 0.1.0: NVENC essentials + NVDEC essentials,
typed errors, deterministic SKIP paths. The package contains no NVIDIA code,
no import library and no generated headers; `src/nvenc_bridge.c` is original
XIOM-side code with compile-time layout assertions.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.6 |
| Decision | **system-library path only** (driver DLLs; nothing vendored) |
| Pin | nv-codec-headers `eddcea9e` (SDK 13.1.15.1, MIT); oracle hashes + local DLL samples in `PROVENANCE.md` |
| Link model | none at build time; `LoadLibraryA` + `GetProcAddress` at run time |
| FFI confinement | all `unsafe`/`extern` in `src/nvenc.xi` (G5); the C bridge is support code that never links NVIDIA code |
| Suite | `tests/test_conformance.xi` |
| Runs (0.1.0) | RTX 3070 Ti / driver 616.92: **67/67 x2** (H.264 + HEVC full pipeline) |
| Handles | integer slots owned by C; no foreign pointers cross the FFI |

## Design notes

- **Version negotiation is two-stage.** `NvEncodeAPIGetMaxSupportedVersion`
  returns `(major << 4) | minor` (209 = 13.1 on this host). The bridge
  refuses a driver below 13.1 (the header pin) with `NVE_UNSUPPORTED`, then
  calls `NvEncodeAPICreateInstance` with the function-list version
  `0x7102000D`. The session is opened with `apiVersion = 0x0100000D`.
- **Codec support is data-driven.** `nvenc_probe` enumerates the driver GUID
  list and reports H.264/HEVC presence; `nvenc_open` re-checks the requested
  GUID, so unsupported codecs are `NVE_UNSUPPORTED` (SKIP) rather than a
  mid-pipeline failure.
- **Preset configuration is driver-computed.** The bridge asks
  `NvEncGetEncodePresetConfigEx` (P1..P7, low-latency tuning) into a 64 KiB
  zeroed buffer and passes `buf+8` as `NV_ENC_INITIALIZE_PARAMS.encodeConfig`.
  The embedded config version (`0xF109000D`) is set before the query. No
  hand-built codec-config struct is copied from upstream.
- **The input resource is package-owned.** A pitched CUDA allocation
  (`cuMemAllocPitch`, 16-byte element size) is registered as a CUDA device
  pointer. `nvenc_fill_frame` uploads a deterministic Y pattern and neutral
  UV, so the live leg needs no media fixture. The same allocation is mapped
  with `NvEncMapInputResource` on first encode and unmapped at destroy.
- **The bitstream lock is explicit.** `nvenc_lock_bitstream` blocks in the
  driver and caches the pointer/size; `nvenc_copy_bitstream` performs the
  copy into an XIOM-owned `Vec[UInt8]` (short buffer ->
  `NVE_BUFFER_TOO_SMALL`); `nvenc_unlock_bitstream` releases the driver lock.
- **NVDEC uses the cuvid parser.** `nvdec_parse` creates
  `cuvidCreateVideoParser` lazily with sequence/decode/display callbacks.
  The sequence callback records coded geometry and rejects a codec mismatch;
  the decode callback calls `cuvidDecodePicture`; the display callback
  records the picture index. The packet is fed with
  `CUVID_PKT_ENDOFSTREAM`, which flushes a single IDR access unit.
- **Frame copy-out is compact NV12.** `cuvidMapVideoFrame64` returns a
  pitched device pointer; the bridge `cuMemcpyDtoH`s the surface into a C
  temporary, then packs `width*height*3/2` bytes (Y then UV) into the
  XIOM-owned buffer. For HEVC the coded height (256) is larger than the
  display height (240); the decoder's mapped surface is copied with the
  display height, matching the observed UV plane offset.
- **Error classification** follows the lane doctrine: loader/device/codec
  absence is SKIP; a present driver that rejects a declared call is FAIL
  with the raw NVENCSTATUS/CUresult in `code`.
- **v0.64.6 discipline compliance:** all foreign memory is touched only in
  C (B-20); integer handles (B-23/B-25); one XIOM-owned output buffer per
  copy (B-17/B-24); flat records, no `Result[Option[T]]` (B-26); bridge
  locals prefixed `n_` (B-10); no allocation in confined blocks (B-05).

## Known limitations

- One access unit per decoder instance in practice (the parser is one-shot
  with `ENDOFSTREAM`); multi-frame streaming is Phase 2.
- Only package-owned CUDA device-pointer input; no caller surfaces yet.
- AV1, 10-bit, 4:4:4, B-frames, lookahead, SVC, ME-only, async events and
  D3D/GL interop are not declared.
- Windows loader names only; Linux sonames are Phase 2.
- The HEVC coded height can exceed the display height (CTU alignment); the
  declarative frame copy uses the display geometry (320x240 here) and the
  test asserts the coded height is >= the display height.
- The live leg is one H.264 + one HEVC frame per run; throughput/queueing
  behavior is not measured.
