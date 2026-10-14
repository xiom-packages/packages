# SPEC: xiom.ffmpeg -- FFmpeg bindings (dynamic loader, system-library SKIP path)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.ffmpeg` |
| Version | 0.4.1 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | FFmpeg -- https://ffmpeg.org/ (libavcodec/libavformat/libavutil/libswresample) |
| Upstream version | floating system builds (local samples: 6.1.1 GIMP GPL set, 6.0 LGPL, 7.1.1 GPL, 8.x partial) |
| Upstream license | LGPL-2.1-or-later (FFmpeg); nothing vendored -- the LGPL policy requires dynamic linking only (`BINDINGS-LANE.md` §4/§11) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (multi-soname generation loader) |
| Compiler pin | v0.64.4 |

## 2. Decision: system-library SKIP path only (never vendored)

Native-lane decision 2026-10-09 (`BINDINGS-LANE.md` §11): the system-lib
**SKIP path is APPROVED**; vendoring FFmpeg binaries or sources is **NOT
approved** (explicit owner sign-off required to change). The loader resolves
one release generation of the four shared libraries at runtime and the suite
reports SKIP when none is present, so CI without FFmpeg stays green.
Present-path proof uses local official/prebuilt sets placed on PATH at run
time -- nothing committed (the libpq/raylib local-binary pattern).

## 3. G2 pin: generation table + entry-point set + samples

**Generation table (in load order):** each generation must resolve all four
sonames; a partially present generation is skipped (never mixed across ABI
generations).

| FFmpeg | avcodec | avformat | avutil | swresample |
|--------|---------|----------|--------|------------|
| 8.x | `avcodec-62.dll` | `avformat-62.dll` | `avutil-60.dll` | `swresample-6.dll` |
| 7.x | `avcodec-61.dll` | `avformat-61.dll` | `avutil-59.dll` | `swresample-5.dll` |
| 6.x | `avcodec-60.dll` | `avformat-60.dll` | `avutil-58.dll` | `swresample-4.dll` |
| 5.x | `avcodec-59.dll` | `avformat-59.dll` | `avutil-57.dll` | `swresample-4.dll` |
| 4.x | `avcodec-58.dll` | `avformat-58.dll` | `avutil-56.dll` | `swresample-3.dll` |

**Resolved entry points (pilot, 7):** `av_version_info`, `avutil_version`
(libavutil); `avcodec_version`, `avcodec_configuration`, `avcodec_license`
(libavcodec); `avformat_version` (libavformat); `swresample_version`
(libswresample). All are LGPL-safe core APIs (no GPL-only feature
dependency).

**0.3.0 decode entry points (15, on demand):** `avcodec_find_decoder_by_name`,
`avcodec_alloc_context3`, `avcodec_open2`, `avcodec_send_packet`,
`avcodec_receive_frame`, `avcodec_free_context`, `av_packet_alloc`,
`av_packet_free`, `av_packet_unref` (libavcodec); `av_frame_alloc`,
`av_frame_free`, `av_frame_unref`, `av_get_pix_fmt_name` (libavutil). The
bridge additionally resolves `av_packet_from_data`, `av_malloc`, `av_free`
via `GetProcAddress` (never linked).

**0.4.0 demux entry points (10, on demand):** `avformat_open_input`,
`avformat_close_input`, `avformat_find_stream_info`, `av_find_best_stream`,
`av_read_frame`, `av_seek_frame` (libavformat); `av_packet_alloc`,
`av_packet_unref`, `av_packet_free` (libavcodec); `av_strerror` (libavutil).
`ffmpeg_codec_name` and `ffmpeg_codec_id_by_name` (0.4.1) resolve
`avcodec_get_name` (libavcodec). All LGPL-safe.

**0.4.1 generation-skew fix:** the numeric `AVCodecID` is NOT stable across
FFmpeg major generations -- `AV_CODEC_ID_AV1` is 226 on lavc 60.x (FFmpeg
6.1), 225 on lavc 61.x (FFmpeg 7.0+, after the deprecated packed-YUV ids
were removed from the video enum) and 222 in the pinned 8.0.git list. The
0.4.0 suite asserted a hardcoded 226 and failed on the 7.1.1 generation
while the bridge read the field correctly. `ffmpeg_codec_id_by_name(lib,
name)` resolves the loaded generation's id from the stable codec name; the
suite gates on name + resolved id. No bridge/ABI change was needed.

**Probe evidence:** version string + the four packed versions decoded as
`major.minor.micro` (`major<<16 | minor<<8 | micro`) + the build's
`avcodec_license()` string + `--enable-gpl` presence in
`avcodec_configuration()`.

**ABI facts encoded by the bridge (declaration oracle: `PROVENANCE.md`):**

| Struct (x64) | Layout used | Generation variance |
|--------------|-------------|---------------------|
| `AVFormatContext` | `nb_streams` at 44 (u32), `streams` at 48 | none across lavf 58-62 |
| `AVStream` | index/id/codecpar/priv_data/time_base relative to `stream_base` | `av_class` added at lavf 60 -> `stream_base` 8 on FFmpeg >= 6.0, else 0 |
| `AVCodecParameters` | codec_type 0, codec_id 4; width/height at `wh_off` | `wh_off` 56 on lavc <= 60.x, 72 from lavc 61 (7.0) where `coded_side_data` was inserted before `format` (on 6.x it is appended at the struct end) |
| `AVPacket` | pts 8, dts 16, data 24, size 32, stream_index 36, flags 40, duration 64, pos 72 | none across lavc 58-62 |
| `AVFrame` (0.3.0) | width 104, height 108, format 116 | none across lavc 58-62 |

The two generation-dependent prefix values are selected from the loaded
generation's packed versions at `ffmpeg_demux_open` time; the suite verifies
them every present-path run against the fixture's known header (64x48,
time_base 1/4, the AV1 codec NAME plus the generation's own id resolved by
`ffmpeg_codec_id_by_name`), so drift fails loudly. No AVCodecID constant is
asserted: the enum shifts across FFmpeg majors (see 0.4.1 note in §3).

**Local runtime samples used for positive-path proof (NOT the pin; nothing
committed):**

| Artifact | Value |
|----------|-------|
| GIMP 2.x `avcodec-60.dll` (FFmpeg 6.1.1; 0.4.0 present-path set) | 16,135,236 B, `libdav1d-7.dll` 1,814,487 B alongside |
| Cascadeur `avcodec-60.dll` (6.0 LGPL; proof set) | 20,333,568 B, SHA256 `094CF53C26B58C7DFFF8B5FE07D8575F21F026F8C962229D6B044AFCB2CD7BE7` |
| Cascadeur `avformat-60.dll` | 3,280,896 B, SHA256 `978F36BF95E37FB26D48F010FD85B4C6DE985EEF82EEABD321D28F97F7694D5D` |
| Cascadeur `avutil-58.dll` | 1,123,840 B, SHA256 `2FFE865E05C46A3D66C9D6CE8EF14B5B9B0D1A51E8B1A6FB23EA1C382F6E6218` |
| Cascadeur `swresample-4.dll` | 194,560 B, SHA256 `43FF1854A154EBF929E99BA265E2B87A53F02F215CF3640009ACEFD64C6473BA` |
| Blender 5.1 `avcodec-61.dll` (7.1.1 GPL; second generation + GPL evidence) | 36,024,320 B, SHA256 `1377146F3C433D582EFE11A86D04F6F833463BEB25F4954E4A0912F3A1FA00CF` |
| OneDrive Codecs 8.1.2 `avcodec-62.dll` (8.x partial: no `swresample-6.dll` -> SKIP) | 13,386,576 B, SHA256 `6A194B539F41FD36F1CD42CA8DCCEC1DA91A2CE26E740D3158D9AFD7B1426ED0` |
| DaVinci Resolve `avcodec-60.dll` (6.x partial: no `swresample-4.dll` -> SKIP) | 12,918,784 B, SHA256 `83A94AD365620CA621ADF0E7949C12D53D73D0CF9EE58ED7891BFEA6C06B7B04` |

Recorded runtime reports: `FFmpeg 6.1.1`, avcodec 60.31.102 / avformat
60.16.100 / avutil 58.29.100 / swresample 4.12.100, license `GPL version 3
or later`, decode via `libdav1d` 1.4.1 (GIMP 0.4.0 present path);
`FFmpeg 6.0`, 60.3.100 / 60.3.100 / 58.2.100 / 4.10.100, license `LGPL
version 2.1 or later` (Cascadeur); `FFmpeg 7.1.1`, 61.19.101 / 61.7.100 /
59.39.100 / 5.3.100, license `GPL version 2 or later` (Blender).

### Re-pin procedure

1. Re-verify the entry-point names/ABI before touching the module (all four
   libraries expose the pilot/decoder/demux calls across the FFmpeg 4.x-8.x
   generations).
2. Update the generation table + sample table + `README.md`/`AUDIT.md` rows
   in one commit.
3. Re-run `scripts/port.ps1 -Package xiom.ffmpeg` (default PATH for the SKIP
   path; a full generation directory prepended for the present path) and
   record the matrix in §5.

## 4. Design and safe boundary (G5)

`ffmpeg.xi` is the only module with `unsafe`: the `FfmpegLibrary` loader
struct (four handles + resolved entry points) plus wrappers
(`ffmpeg_load(_named)`, `ffmpeg_close`, `ffmpeg_probe(_named/_default)`,
`ffmpeg_version_str`, `ffmpeg_lgpl_build`, the 0.3.0 AV1 decode surface and
the 0.4.0 demux surface). Classification: `FFMPEG_LOAD_ABSENT` -> SKIP;
`FFMPEG_LOAD_ABI` -> FAIL; `FFMPEG_PROBE_FAILED` -> FAIL;
`FFMPEG_DECODER_ABSENT` -> SKIP; `FFMPEG_DEMUX_FAILED` -> FAIL (typed rc +
av_strerror text). Bridge locals use the `f_` prefix (finding B-10); no
allocation in confined blocks (finding B-05). A GPL-configured host build is
reported as data (`gpl_enabled`, license string), not an error: the package
depends only on LGPL-safe APIs.

Demux copy-out discipline (v0.64.4 findings): handles cross as `Int` params
in the fn-pointer casts (B-25: never `Int as *UInt8`); nullable C args are
`Int 0` (B-23); out-params use one owned slot each and are read byte-indexed
(B-17/B-24); `AVFormatContext`/`AVStream`/`AVCodecParameters`/`AVPacket`
reads happen only in `src/ffmpeg_bridge.c` (B-20); no XIOM pointer
arithmetic; flat outcome structs, no `Result[Option[T]]` (B-26); Str
equality via `string.str_compare`.

## 5. Test matrix (0.4.1 recorded 2026-10-14, compiler v0.64.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| Default PATH (no FFmpeg DLLs) | `scripts/port.ps1 -Package xiom.ffmpeg` | **PASS 3/3 x2** -- SKIP classification (bogus sonames) + probe SKIP + decode+demux SKIP |
| GIMP 6.1.1 prepended (present path) | same | **PASS 23/23 x2** -- 12 decode + 11 demux checks (`libdav1d` 1.4.1; runtime av1 id 226) |
| Blender 7.1.1 GPL prepended (present path) | same | **PASS 23/23 x2** (0.4.1) -- 12 decode + 11 demux checks (`libaom-av1`; runtime av1 id 225; the 0.4.0 gate failed 22/23 here) |
| Cascadeur 6.0 LGPL prepended | same | **PASS 12/12 x2** (0.3.0 recorded) -- `FFmpeg 6.0`, four versions, `LGPL version 2.1 or later` |
| OneDrive 8.1.2 (partial) prepended | same | **PASS 3/3** (0.3.0 recorded) -- generation skipped (no `swresample-6.dll`), SKIP |
| DaVinci Resolve 6.x (partial) prepended | same | **PASS 3/3** (0.3.0 recorded) -- generation skipped (no `swresample-4.dll`), SKIP |

Demux checks counted by the present-path suite: absent-path typed error;
open + stream count; stream codec id/type/time base; stream geometry;
best-stream selection; packet loop count/sizes/EOF; packet byte equality;
packet metadata (stream_index/pts); demux->decode feed; seek + re-read;
close.

## 6. Scope

0.4.1: generation-skew fix for the demux codec-id gate (runtime id
resolution by codec name; no API/ABI change to the demux surface). 0.4.0:
library identification + license evidence (0.2.0), AV1-class decode
surface (0.3.0), container demux surface (0.4.0: avformat open/close from a
file path, stream enumeration, best-stream selection, packet read loop,
seek). Encode/transcode wrappers, audio decode, filters and a transcode
example are Phase 3 (`ROADMAP.md`).
