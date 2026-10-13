# SPEC: xiom.ffmpeg -- FFmpeg bindings (dynamic loader, system-library SKIP path)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.ffmpeg` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | FFmpeg -- https://ffmpeg.org/ (libavcodec/libavformat/libavutil/libswresample) |
| Upstream version | floating system builds (local samples: 6.0 LGPL, 7.0.2 GPL, 7.1.1 GPL, 8.x partial) |
| Upstream license | LGPL-2.1-or-later (FFmpeg); nothing vendored -- the LGPL policy requires dynamic linking only (`BINDINGS-LANE.md` §4/§11) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (multi-soname generation loader) |
| Compiler pin | v0.64.4 |
| Reference clone | `E:\repos\FFmpeg` @ `b5902e69c71bf556958f9fded99d1bcea2d7298c` (8.0.git) -- declaration oracle, `PROVENANCE.md` |

## 2. Decision: system-library SKIP path only (never vendored)

Native-lane decision 2026-10-09 (`BINDINGS-LANE.md` §11): the system-lib
**SKIP path is APPROVED**; vendoring FFmpeg binaries or sources is **NOT
approved** (explicit owner sign-off required to change). The loader resolves
one release generation of the four shared libraries at runtime and the suite
reports SKIP when none is present, so CI without FFmpeg stays green.
Present-path proof used local official prebuilt sets (Cascadeur/Blender/
CapCut/OBS release directories) placed on PATH at run time -- nothing
committed (the libpq/raylib local-binary pattern).

## 3. G2 pin: generation table + entry-point sets + samples

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

**Probe entry points (7):** `av_version_info`, `avutil_version`
(libavutil); `avcodec_version`, `avcodec_configuration`, `avcodec_license`
(libavcodec); `avformat_version` (libavformat); `swresample_version`
(libswresample). All are LGPL-safe core APIs (no GPL-only feature
dependency).

**Decode entry points (13, resolved separately in 0.3.0):** from libavcodec
-- `avcodec_find_decoder_by_name`, `avcodec_alloc_context3`, `avcodec_open2`,
`avcodec_send_packet`, `avcodec_receive_frame`, `avcodec_free_context`,
`av_packet_alloc`, `av_packet_free`, `av_packet_unref`; from libavutil --
`av_frame_alloc`, `av_frame_free`, `av_frame_unref`, `av_get_pix_fmt_name`.
A generation with a missing decode entry point is `FFMPEG_LOAD_ABI` (FAIL).

**Probe evidence:** version string + the four packed versions decoded as
`major.minor.micro` (`major<<16 | minor<<8 | micro`) + the build's
`avcodec_license()` string + `--enable-gpl` presence in
`avcodec_configuration()`.

**Local runtime samples used for positive-path proof (NOT the pin; nothing
committed):**

| Artifact | Value |
|----------|-------|
| Cascadeur `avcodec-60.dll` (6.0 LGPL; proof set) | 20,333,568 B, SHA256 `094CF53C26B58C7DFFF8B5FE07D8575F21F026F8C962229D6B044AFCB2CD7BE7` |
| Cascadeur `avformat-60.dll` | 3,280,896 B, SHA256 `978F36BF95E37FB26D48F010FD85B4C6DE985EEF82EEABD321D28F97F7694D5D` |
| Cascadeur `avutil-58.dll` | 1,123,840 B, SHA256 `2FFE865E05C46A3D66C9D6CE8EF14B5B9B0D1A51E8B1A6FB23EA1C382F6E6218` |
| Cascadeur `swresample-4.dll` | 194,560 B, SHA256 `43FF1854A154EBF929E99BA265E2B87A53F02F215CF3640009ACEFD64C6473BA` |
| Blender 5.1 `avcodec-61.dll` (7.1.1 GPL; second generation + GPL evidence) | 36,024,320 B, SHA256 `1377146F3C433D582EFE11A86D04F6F833463BEB25F4954E4A0912F3A1FA00CF` |
| OneDrive Codecs 8.1.2 `avcodec-62.dll` (8.x partial: no `swresample-6.dll` -> SKIP) | 13,386,576 B, SHA256 `6A194B539F41FD36F1CD42CA8DCCEC1DA91A2CE26E740D3158D9AFD7B1426ED0` |
| DaVinci Resolve `avcodec-60.dll` (6.x partial: no `swresample-4.dll` -> SKIP) | 12,918,784 B, SHA256 `83A94AD365620CA621ADF0E7949C12D53D73D0CF9EE58ED7891BFEA6C06B7B04` |

Recorded runtime reports: `FFmpeg 6.0`, avcodec 60.3.100 / avformat 60.3.100 /
avutil 58.2.100 / swresample 4.10.100, license `LGPL version 2.1 or later`
(Cascadeur); `FFmpeg 7.1.1`, 61.19.101 / 61.7.100 / 59.39.100 / 5.3.100,
license `GPL version 2 or later` (Blender); `FFmpeg n7.0.2`, 61.3.100 /
61.1.100 / 59.8.100 / 5.1.100, license `GPL version 3 or later` (OBS).

### Re-pin procedure

1. Re-verify the entry-point names/ABI before touching the module (all four
   libraries expose the probe calls across the FFmpeg 4.x-8.x generations;
   the decode set from libavcodec 4.x on).  Re-verify the AVFrame head
   offsets used by `src/ffmpeg_bridge.c` (`libavutil/frame.h`) and the
   discovery set (`libavcodec/av1dec.c`, `libdav1d.c`, `libaomdec.c`).
2. Update the generation table + sample table + `README.md`/`AUDIT.md` rows
   in one commit.
3. Re-run `scripts/port.ps1 -Package xiom.ffmpeg` (default PATH for the SKIP
   path; a full generation directory prepended for the present path) and
   record the matrix in §5.

## 4. Design and safe boundary (G5)

`ffmpeg.xi` is the only module with `unsafe`: an `FfmpegLibrary` loader
struct (four handles + resolved entry points) plus wrappers
(`ffmpeg_load(_named)`, `ffmpeg_close`, `ffmpeg_probe(_named/_default)`,
`ffmpeg_version_str`, `ffmpeg_lgpl_build`). Classification:
`FFMPEG_LOAD_ABSENT` -> SKIP; `FFMPEG_LOAD_ABI` -> FAIL;
`FFMPEG_PROBE_FAILED` -> FAIL. Bridge locals use the `f_` prefix (finding
B-10); no allocation in confined blocks (finding B-05). A GPL-configured
host build is reported as data (`gpl_enabled`, license string), not an
error: the package depends only on LGPL-safe APIs.

### 4.1 AV1-class decode surface (0.3.0, wave A3)

Surface (all on a loaded generation):

| Area | Functions / types |
|------|-------------------|
| Discovery | `ffmpeg_av1_decoder_open` (usable decoder, software-first preference), `ffmpeg_av1_decoder_open_named(lib, name)` (single-name primitive), `FfDecoder`, `FFMPEG_AV1_DECODERS`, `FFMPEG_AV1_SOFTWARE_ORDER` |
| Packet lifecycle | `ffmpeg_packet_alloc`, `ffmpeg_packet_from_bytes(dec, &Vec[UInt8], offset, size)`, `ffmpeg_packet_unref`, `ffmpeg_packet_free`, `FfPacketOutcome` |
| Frame lifecycle | `ffmpeg_frame_alloc`, `ffmpeg_frame_unref`, `ffmpeg_frame_free` |
| Decode loop | `ffmpeg_decoder_send`, `ffmpeg_decoder_flush` (send NULL), `ffmpeg_decoder_receive` -> `FfFrameOutcome` (`kind` + `rc` + `width`/`height`/`pix_fmt`/`pix_fmt_name`), `ffmpeg_decoder_close` |

**Discovery semantics.**  `ffmpeg_av1_decoder_open` tries, in preference
order, `libdav1d`, `libaom-av1`, then the native `av1`
(`FFMPEG_AV1_DECODERS` = `av1,libdav1d,libaom-av1` is the name set).
Rationale (pinned lineage): the native `av1` decoder's only software path
goes through a hardware accelerator -- `libavcodec/av1dec.c` logs "Your
platform doesn't support hardware accelerated AV1 decoding" and returns
`AVERROR(ENOSYS)` when no hwaccel is negotiated -- so the dav1d/aom
wrappers are preferred and the native entry stays the last fallback for a
later hardware-device surface.  A name that resolves but refuses to open
(wrapper without its backing library) is skipped; when no candidate opens
the result is `FFMPEG_DECODER_ABSENT` -> SKIP.  The first packet sent to a
hardware-only native decoder returns `FFMPEG_ERR_ENOSYS` (-40), which the
suite classifies as SKIP, never FAIL.

**Bridge (`src/ffmpeg_bridge.c`, compiled with `--c-source`).**  Ours, not
FFmpeg code; it never links FFmpeg.  Two jobs the v0.64.4 FFI discipline
cannot do from owned memory:

1. `ffmpeg_bridge_packet_from_bytes` -- copies XIOM-owned bytes into an
   `av_malloc`'ed buffer and wraps it with `av_packet_from_data`; the four
   functions are resolved at runtime via `GetProcAddress` on the module
   handles XIOM already loaded.
2. `ffmpeg_bridge_frame_info` -- copies the AVFrame head
   (width/height/format; `libavutil/frame.h` field order, stable 4.x-8.x)
   into an XIOM-owned 12-byte slot; XIOM reads the slot byte-indexed.

**FFI discipline (findings B-17/B-20/B-23/B-24/B-25/B-26).**  Handles cross
as `Int` params (never `Int as *UInt8`, B-25); nullable C args are `Int 0`
(B-23); one owned slot per out-param, written byte-indexed, no pointer
arithmetic (B-17); XIOM never reads through a foreign pointer (B-20/B-24);
flat outcome structs, no `Result[Option[T]]` (B-26); fn-pointer locals use
the `f_` prefix (B-10).  `ffmpeg_free_ptr` frees pointer-to-pointer APIs
(`avcodec_free_context`, `av_packet_free`, `av_frame_free`) through an
owned 8-byte slot.

**Container demux (avformat) is not part of 0.3.0** -- the suite parses the
IVF framing of its fixture in-suite (pure XIOM byte reads).  Demux stays
the next Phase 3 item (`ROADMAP.md`).

## 5. Test matrix (compiler v0.64.4, 2026-10-13)

| Configuration | Command | Result |
|---------------|---------|--------|
| Default PATH (no FFmpeg DLLs) | `scripts/port.ps1 -Package xiom.ffmpeg` | **PASS 3/3 x2** -- SKIP classification (bogus sonames) + probe SKIP + decode SKIP |
| Blender 5.1 7.1.1 GPL prepended | same | **PASS 12/12 x2** -- `libaom-av1`; 3 frames decoded, 64x48, `yuv420p`, flush/EOF clean |
| CapCut 9.3.0 7.x LGPL prepended | same | **PASS 12/12** -- `libdav1d`; same decode evidence |
| Cascadeur 6.0 LGPL prepended | same | **PASS 12/12** -- `libdav1d` (1.2.1); same decode evidence |
| OBS n7.0.2 GPL prepended | same | **PASS 12/12** -- `libaom-av1`; same decode evidence |
| OneDrive 8.1.2 (partial) prepended | same | **PASS 3/3** -- generation skipped (no `swresample-6.dll`), SKIP |
| DaVinci Resolve 6.x (partial) prepended | same | **PASS 3/3** -- generation skipped (no `swresample-4.dll`), SKIP |

The decode path is exercised with real software AV1 decoding on three
independent builds (`libdav1d` 1.2.1 under Cascadeur; `libaom-av1` under
Blender; `libdav1d` under CapCut).  The fixture (625 B IVF, 3 frames,
generated from `testsrc2`; `PROVENANCE.md`) is not vendored FFmpeg content.

## 6. Scope

0.3.0: library identification + license/configuration evidence (LGPL-safe
surface) + the AV1-class decode surface (discovery, codec-context open,
packet/frame lifecycle, width/height/pixel-format read-out) on a loaded
generation.  Audio decode, container demux (`avformat_open_input`/
`av_read_frame`), encode, transcode, filters, hardware-accelerated AV1
(device setup + `av_hwframe_transfer_data`) and WASM are later Phase 3
items (`ROADMAP.md`).  The pre-pilot module (27 static `extern "C"`
declarations, compile-time linked) is preserved in git history.
