# PROVENANCE: xiom.ffmpeg

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | FFmpeg -- https://ffmpeg.org/ (libavcodec / libavformat / libavutil / libswresample) |
| Upstream license | LGPL-2.1-or-later (FFmpeg core); GPL/GPL-3 builds exist upstream |
| Policy | **Reference-only. NEVER vendored** (LGPL) -- dynamic linking only, `docs/BINDINGS-LANE.md` sec. 4/11; ledger note `E:\repos\CLEANUP.md` ("FFmpeg is LGPL/GPL: reference-only; the shipped xiom.ffmpeg uses system libs (SKIP-only) -- never copy FFmpeg code"). |
| Reference clone | `E:\repos\FFmpeg` -- pinned commit `b5902e69c71bf556958f9fded99d1bcea2d7298c` (`git describe` -> `8.0.git`; master 2026-10-07; ledger row verified 2026-10-13, review-after 2026-12-01) |
| Package license | MIT OR Apache-2.0 (no upstream code copied into this package) |

The shipped decode surface is **independent XIOM code** written against the
public C API declarations in the pinned clone (the "declaration oracle"
below) and verified against real shared builds at runtime.  Nothing from
FFmpeg is copied, linked, or committed: the loader resolves one release
generation at run time and the suite SKIPs green when none is present.

## Declaration oracle (files read at the pinned commit)

| File | SHA256 |
|------|--------|
| `libavcodec/avcodec.h` | `B7599BF5043E4F440376EC441337932B6588FB4577ABCD085A41D734BE9D3DB7` |
| `libavcodec/codec.h` | `8E190FE4A7F7738C91DF84035E2DEF3B86501EAD545553AE36C9F9CDFA3846F7` |
| `libavcodec/codec_id.h` | `CFE37B23A819AFD81BD3357D7A10D9613D79A0EBE1FB075298E5BAF5347433B4` |
| `libavcodec/codec_par.h` | `B2B7C11B8CA7A3304F0F4144935263710C0B4351F955D6BF6B5F64BAFF59B134` |
| `libavcodec/packet.h` | `A7AE6EB98A1DFEB6D438726F2771FDD0FBFE43B9A2D5D272860006DDBA8B1AC0` |
| `libavcodec/av1dec.c` | `E67F208E1D2F5030F8342A662275B7A17F3973EBDF155D4061F747549203EE80` |
| `libavcodec/libdav1d.c` | `9870564455E6B37D711386C66956AD28DBA066A8A070CABFEB5BA6D7BD432A43` |
| `libavcodec/libaomdec.c` | `A9D7221277664BCCBBB21641309AC6C7EAC7B6D2DE516A6C241F41A5B8A4A663` |
| `libavformat/avformat.h` | `F143BE8DABCC245FD84B69DB3B92E54D6B1674FF4A019A6A5254D06629F3C27A` |
| `libavformat/ivfdec.c` | `521D233B5E52ED789A5C5399F01B2464B16DCAAD6D438869A82EFA61EE8B6A68` |
| `libavformat/seek.c` | `8C19E2A8658AAB641A84AEB065B0144F2F35A06709BA4C9D8A1282C45553F6AF` |
| `libavutil/frame.h` | `E784F784B50CD5F33FB4D24BB19E38BF784038AEDE8D96896767F15B9D3536D9` |
| `libavutil/error.h` | `ADC7D58271E93EF905F13374482CF646E38B981E5CF9A971AEE5497B980D24AF` |
| `libavutil/pixfmt.h` | `242660CC1B7053C98F2883A9B326AF7F902F798AD13AD23F22CC1BBFF20B8CD8` |

Bound entry-point signatures come from `codec.h`/`avcodec.h`/`packet.h`/
`frame.h`/`pixfmt.h` (decode) and `avformat.h` (demux:
`avformat_open_input`, `avformat_close_input`, `avformat_find_stream_info`,
`av_find_best_stream`, `av_read_frame`, `av_seek_frame`); the error
constants (`AVERROR(EAGAIN)`, `AVERROR_EOF`, `AVERROR(ENOSYS)`) from
`error.h`; the AVFrame head field order in `src/ffmpeg_bridge.c` from
`frame.h`; the AVFormatContext / AVStream / AVCodecParameters / AVPacket
head field orders from `avformat.h` / `codec_par.h` / `packet.h`; the
discovery names and the hardware-only classification of the native `av1`
decoder from `av1dec.c` (`ff_av1_decoder`, `get_pixel_format` ->
`AVERROR(ENOSYS)` when no hwaccel is negotiated); the wrapper names from
`libdav1d.c` / `libaomdec.c`; the generic-index seek behavior from
`seek.c`; the IVF demuxer's time-base and generic-index setup
(`AVFMT_GENERIC_INDEX`, `avpriv_set_pts_info`) from `ivfdec.c`.

**Generation-skew verification for the demux prefixes (2026-10-13).** The
struct prefixes were cross-checked at the release tags that bracket the
local runtimes (read from the canonical FFmpeg repository at `n6.0` (lavf
60 / FFmpeg 6.0: `AVStream.av_class` present), `n6.1` (lavc 60.31:
`AVCodecParameters.width` still at 56; `coded_side_data` appended at the
struct end) and `n7.0` (lavc 61: `coded_side_data` inserted before
`format`, width at 72)). The selection rule in `ffmpeg_demux_open`
(`stream_base` from the lavf major, `wh_off` from the lavc major) encodes
exactly this; the runtime probe on the GIMP 6.1.1 DLL caught the
first-attempt 72-offset read (field_order/color_space = 0/1 instead of
64x48) before any record was made.

## Derived vs independent

- `ffmpeg.xi` (root module, all `unsafe`/`extern`): **independent** XIOM
  code -- dynamic loader + LGPL-safe probe (0.2.0) + AV1-class decode
  surface (0.3.0) + container demux surface (0.4.0).  No FFmpeg code,
  tables, or generated files.
- `src/ffmpeg_bridge.c`: **original XIOM-side helper** (ours, MIT OR
  Apache-2.0).  It never links FFmpeg and resolves the four functions it
  needs (`av_packet_alloc`, `av_packet_from_data`, `av_malloc`, `av_free`)
  via `GetProcAddress` on the module handles XIOM already loaded.  It knows
  no FFmpeg implementation: the only ABI facts it encodes are the public
  AVFrame head field order (data/linesize/extended_data/width/height/
  nb_samples/format), the AVFormatContext / AVStream / AVCodecParameters /
  AVPacket head field orders and `AV_INPUT_BUFFER_PADDING_SIZE = 64`, all
  from the headers at the pinned commit -- interface facts, not copied
  code.  Its copy-out slots are the sanctioned B-20/B-24 boundary: foreign
  memory is read in C only.
- Test fixture `tests/fixtures/av1_64x48.ivf` (625 bytes, SHA256
  `39D105E4BDB10F2745D0F53728D954DAB8339C39BFE80766C0364AF04CA2A555`):
  generated locally, **not imported from upstream**.  Source is the
  synthetic `testsrc2` pattern; encoder = the local
  `C:\ffmpeg\bin\ffmpeg.exe` ("8.0-git-25b0a8e295-full_build", gyan.dev
  static build, `--enable-gpl --enable-libaom`), with:

  ```
  ffmpeg -f lavfi -i "testsrc2=size=64x48:rate=4" -frames:v 3 \
         -c:v libaom-av1 -cpu-used 8 -crf 50 -lag-in-frames 0 -auto-alt-ref 0 \
         -f ivf tests/fixtures/av1_64x48.ivf
  ```

  Contents: IVF header (DKIF/AV01, 64x48, 3 frames) + 3 AV1 temporal units
  (sequence header + keyframe + 2 inter frames).  No third-party content,
  no upstream test vectors.  The 0.4.0 demux suite reads the same fixture
  through libavformat's IVF demuxer (the container's own per-frame headers
  are the expected packet sizes/timestamps).
- Local runtime samples used for present-path proof (NOT the pin, nothing
  committed): GIMP 6.1.1 (`libdav1d-7.dll` 1.4.1; 0.4.0 present path),
  Cascadeur 6.0 LGPL (`libdav1d` 1.2.1), Blender 5.1 7.1.1 GPL
  (`libaom-av1` + `aom.dll`), CapCut 9.3.0 7.x LGPL (`libdav1d` +
  `dav1d.dll`), OBS n7.0.2 GPL (`libaom-av1`).  Paths + evidence in
  `SPEC.md` sec. 5.

## Test vectors

- None imported from upstream.  The conformance fixture is our own
  (generated as above); the IVF header's 64x48 is the ground truth the
  decoded frame must match (this also verifies the AVFrame head offsets
  used by the bridge end to end).

## Re-carve procedure (upstream moves)

1. Re-clone/refresh `E:\repos\FFmpeg` at the new tag; update the pinned
   commit here and the `E:\repos\CLEANUP.md` review date.
2. Re-verify the entry-point signatures (`codec.h`/`avcodec.h`/`packet.h`/
   `frame.h`/`pixfmt.h`, decode; `avformat.h`, demux) and the AVFrame /
   AVFormatContext / AVStream / AVCodecParameters / AVPacket head offsets;
   re-hash the oracle files into this table.
3. Re-check the discovery set (native `av1` hw-only classification; the
   `libdav1d`/`libaom-av1` wrapper names) against the new `av1dec.c`/
   `libdav1d.c`/`libaomdec.c`, and the generation rules for `stream_base`
   (lavf major) / `wh_off` (lavc major) against the tag headers.
4. `scripts/port.ps1 -Package xiom.ffmpeg` (default SKIP x2 + a present-path
   generation directory on PATH x2); `scripts/status.ps1 -Action update`;
   conventional commit; sync `SPEC.md`/`AUDIT.md` counts in the same commit.
