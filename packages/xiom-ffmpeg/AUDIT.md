# AUDIT: xiom.ffmpeg

## Status (2026-10-13, v0.64.4)

System-library dynamic-loader implementation at 0.3.0. The pre-pilot module
(27 static `extern "C"` declarations, compile-time linked) required FFmpeg
import libraries at build time and is preserved in git history only.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Decision | **system-library SKIP path only** (native lane 2026-10-09; `SPEC.md` §2, `BINDINGS-LANE.md` §11) |
| Pin | generation table + entry points + local samples (`SPEC.md` §3); reference clone `E:\repos\FFmpeg` @ `b5902e6` (`PROVENANCE.md`) |
| Link model | none at build time; runtime `xiom.ffi.dl` (generation scan) |
| FFI confinement | all `unsafe`/`extern` in the root module `ffmpeg.xi` (G5); `src/ffmpeg_bridge.c` is XIOM-side support code (no FFmpeg link) |
| Suite | `tests/test_conformance.xi` |
| Runs | default PATH: SKIP 3/3 x2; Blender 7.1.1 GPL: 12/12 x2 (`libaom-av1`); CapCut 7.x LGPL: 12/12 (`libdav1d`); Cascadeur 6.0 LGPL: 12/12 (`libdav1d`); OBS n7.0.2 GPL: 12/12 (`libaom-av1`); partial generations: SKIP 3/3 |

## Design notes

- A **generation** = the four shared libraries of one FFmpeg release; all
  four must resolve, so a partial set (e.g., DaVinci Resolve's 6.x without
  `swresample-4.dll`) is skipped instead of mixing ABI generations.
- The probe calls only version/configuration/license entry points -- the
  LGPL-safe surface approved by the native lane. A GPL-configured host build
  is reported as data (`license`, `gpl_enabled`) and is not an error: the
  package never depends on a GPL-only feature.
- License strings verified by byte scan of the DLLs' `avcodec_license()`
  constants: `LGPL version 2.1 or later` in Cascadeur/DaVinci/OneDrive
  builds, `GPL version 2 or later` in Blender's.
- Bridge locals use the `f_` prefix (finding B-10); no allocation in
  confined blocks (finding B-05).

## 0.3.0 decode surface notes

- **Native `av1` is hardware-only in the pinned lineage.**
  `libavcodec/av1dec.c` returns `AVERROR(ENOSYS)` ("Your platform doesn't
  support hardware accelerated AV1 decoding") when no hwaccel is
  negotiated; a standalone C probe against Cascadeur's 6.0 build reproduced
  send rc=-40 with the same log line. Hence `ffmpeg_av1_decoder_open`
  prefers the software wrappers (`libdav1d`, `libaom-av1`) and keeps the
  native name as the last candidate; a first-packet ENOSYS is classified
  SKIP (not FAIL) by the suite.
- **Software decoder evidence (present path, real decode):** Cascadeur 6.0
  LGPL ships a working `libdav1d` 1.2.1 (no `dav1d.dll` on PATH needed);
  CapCut 7.x resolves `dav1d.dll` from its own directory; Blender 5.1 and
  OBS n7.0.2 decode via `libaom-av1`. All four report the same decoded
  fixture: 3 frames, 64x48, `yuv420p`, flush to EOF clean.
- **Bridge (`src/ffmpeg_bridge.c`) is ours** and never links FFmpeg; it
  resolves `av_packet_alloc`/`av_packet_from_data`/`av_malloc`/`av_free`
  via `GetProcAddress` on the loaded modules. It encodes one ABI fact (the
  public AVFrame head field order) -- verified end to end every run by the
  fixture's known 64x48 header; re-carve procedure in `PROVENANCE.md`.
- **v0.64.4 discipline compliance:** handles cross as `Int` params (B-25);
  nullable args are `Int 0` (B-23); one owned slot per out-param with
  byte-indexed reads (B-17/B-24); no foreign-pointer reads (B-20); flat
  outcome structs, no `Result[Option[T]]` (B-26); no fp returns (B-12);
  bridge locals prefixed `f_` (B-10).
- The suite's IVF framing parse is pure XIOM byte reads (no avformat; that
  is the next Phase 3 item).

## Known limitations

- Decode is video (AV1-class) only; audio decode, demux/container
  introspection, encode/transcode and filters are Phase 3.
- Frame pixel planes are not copied out yet (the frame head +
  lifecycle are surfaced; pixel copy-out is a later item).
- The AV1 surface is exercised against software decoders; the native
  hardware path needs a device-context surface that is not part of 0.3.0.
- Only the five built-in generations are scanned; an unusual soname needs
  `ffmpeg_probe_named`.
- Windows x64 only: FFmpeg shared builds on other platforms use different
  sonames (the generation table is platform-specific).
