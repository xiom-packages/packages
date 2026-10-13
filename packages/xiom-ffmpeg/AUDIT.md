# AUDIT: xiom.ffmpeg

## Status (2026-10-13, v0.64.4)

System-library dynamic-loader implementation at 0.4.0 (probe + AV1-class
decode + container demux). The pre-pilot module (27 static `extern "C"`
declarations, compile-time linked) required FFmpeg import libraries at build
time and is preserved in git history only.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Decision | **system-library SKIP path only** (native lane 2026-10-09; `SPEC.md` §2, `BINDINGS-LANE.md` §11) |
| Pin | generation table + entry points + local samples (`SPEC.md` §3); reference clone `E:\repos\FFmpeg` @ `b5902e6` (`PROVENANCE.md`) |
| Link model | none at build time; runtime `xiom.ffi.dl` (generation scan) |
| FFI confinement | all `unsafe`/`extern` in the root module `ffmpeg.xi` (G5); `src/ffmpeg_bridge.c` is XIOM-side support code (no FFmpeg link) |
| Suite | `tests/test_conformance.xi` |
| Runs (0.4.0) | default PATH: SKIP 3/3 x2; GIMP 6.1.1: 23/23 x2 (12 decode + 11 demux, `libdav1d` 1.4.1) |
| Runs (0.3.0, kept green) | Cascadeur 6.0 LGPL: 12/12 x2 (`libdav1d` 1.2.1); Blender 7.1.1 GPL: 12/12 (`libaom-av1`); CapCut 7.x LGPL: 12/12 (`libdav1d`); OBS n7.0.2 GPL: 12/12 (`libaom-av1`); partial generations (OneDrive 8.1.2, DaVinci 6.x): SKIP 3/3 |

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

## 0.4.0 demux surface notes

- **AVStream prefix is generation-dependent:** `AVStream.av_class` was added
  at lavf 60 (FFmpeg 6.0), so the bridge walks `stream_base` (8 on lavf >=
  60, else 0) before index/id/codecpar/priv_data/time_base. Confirmed
  against the pinned master header and the n6.0 tag.
- **AVCodecParameters width/height shifted at lavc 61:** `coded_side_data`
  was added at lavc 60.30 but appended at the struct end (n6.1 header), so
  6.x keeps width at 56; FFmpeg 7.0 (n7.0 header) inserted it before
  `format`, moving width/height to 72. `ffmpeg_demux_open` selects
  `wh_off` from the loaded avcodec version; the first present-path attempt
  with the 72 offset against the 6.1 runtime read field_order/color_space
  (0/1) instead of 64/48 -- the geometry check caught the skew immediately
  (loud-failure design working as intended).
- **AV_CODEC_ID_AV1 = 226** (video enum order after XPM/BITPACKED in the
  pinned headers) verified at runtime on the 6.1 DLL:
  `avcodec_get_name(226) == "av1"`; the suite asserts both the constant and
  the name.
- **The packet read loop is checked against the container's own framing**:
  count (3), per-packet size (450/44/63), payload byte equality against the
  IVF frame bytes, stream_index/pts (0/1/2) against the per-frame headers,
  and clean EOF; the demuxed packets are then fed to a fresh AV1 decoder
  (demux -> decode integration) with the same 64x48/yuv420p result as the
  byte-fed path.
- **Seek:** the IVF demuxer has no `read_seek` (only `AVFMT_GENERIC_INDEX`),
  so `av_seek_frame(0, 0, AVSEEK_FLAG_BACKWARD)` exercises the generic
  index path built from the read pass; the suite re-reads all 3 packets
  after the seek.
- **Typed errors:** an absent path opens as `FFMPEG_DEMUX_FAILED` with the
  AVERROR rc and `av_strerror` text (`rc=-2: No such file or directory` on
  the GIMP set); missing entry points are `FFMPEG_LOAD_ABI`.
- The bridge copy-outs (`format_info`, `stream_info`, `packet_info`,
  `packet_bytes`) read all foreign memory in C into XIOM-owned slots or
  buffers; XIOM performs no reads through foreign pointers.

## Known limitations

- Decode is video (AV1-class) only; audio decode, encode/transcode and
  filters are Phase 3.
- Frame pixel planes are not copied out yet (the frame head +
  lifecycle are surfaced; pixel copy-out is a later item).
- The demux surface is validated on the IVF fixture (single video stream)
  and the 6.1 GIMP runtime; the 4.x/5.x and 8.x prefix values are pinned
  from the declaration oracle, not exercised on this host.
- The AV1 surface is exercised against software decoders; the native
  hardware path needs a device-context surface that is not part of 0.3.0.
- Only the five built-in generations are scanned; an unusual soname needs
  `ffmpeg_probe_named`.
- Windows x64 only: FFmpeg shared builds on other platforms use different
  sonames (the generation table is platform-specific).
