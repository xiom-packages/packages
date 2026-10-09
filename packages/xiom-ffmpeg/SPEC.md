# SPEC: xiom.ffmpeg -- FFmpeg bindings (dynamic loader, system-library SKIP path)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.ffmpeg` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | FFmpeg -- https://ffmpeg.org/ (libavcodec/libavformat/libavutil/libswresample) |
| Upstream version | floating system builds (local samples: 6.0 LGPL, 7.1.1 GPL, 8.x partial) |
| Upstream license | LGPL-2.1-or-later (FFmpeg); nothing vendored -- the LGPL policy requires dynamic linking only (`BINDINGS-LANE.md` §4/§11) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (multi-soname generation loader) |
| Compiler pin | v0.64.1 |

## 2. Decision: system-library SKIP path only (never vendored)

Native-lane decision 2026-10-09 (`BINDINGS-LANE.md` §11): the system-lib
**SKIP path is APPROVED**; vendoring FFmpeg binaries or sources is **NOT
approved** (explicit owner sign-off required to change). The loader resolves
one release generation of the four shared libraries at runtime and the suite
reports SKIP when none is present, so CI without FFmpeg stays green.
Present-path proof used a local official prebuilt LGPL set (Cascadeur) placed
on PATH at run time -- nothing committed (the libpq/raylib local-binary
pattern).

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

**Resolved entry points (7):** `av_version_info`, `avutil_version`
(libavutil); `avcodec_version`, `avcodec_configuration`, `avcodec_license`
(libavcodec); `avformat_version` (libavformat); `swresample_version`
(libswresample). All are LGPL-safe core APIs (no GPL-only feature
dependency).

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
license `GPL version 2 or later` (Blender).

### Re-pin procedure

1. Re-verify the entry-point names/ABI before touching the module (all four
   libraries expose the version calls across the FFmpeg 4.x-8.x generations).
2. Update the generation table + sample table + `README.md`/`AUDIT.md` rows
   in one commit.
3. Re-run `scripts/port.ps1 -Package xiom.ffmpeg` (default PATH for the SKIP
   path; a full LGPL generation directory prepended for the present path) and
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

## 5. Test matrix (recorded 2026-10-09, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Default PATH (no FFmpeg DLLs) | `scripts/port.ps1 -Package xiom.ffmpeg` | **PASS 2/2 x2** -- SKIP classification (bogus sonames) + probe SKIP |
| Cascadeur 6.0 LGPL prepended | same | **PASS 4/4 x2** -- `FFmpeg 6.0`, four versions, `LGPL version 2.1 or later` |
| Blender 7.1.1 GPL prepended | same | **PASS 4/4** -- `FFmpeg 7.1.1`, license `GPL version 2 or later`, consistency check |
| OneDrive 8.1.2 (partial) prepended | same | **PASS 2/2** -- generation skipped (no `swresample-6.dll`), SKIP |
| DaVinci Resolve 6.x (partial) prepended | same | **PASS 2/2** -- generation skipped (no `swresample-4.dll`), SKIP |

## 6. Scope

Pilot: library identification + license/configuration evidence (LGPL-safe
surface). Demux/decode/encode wrappers, packet/frame lifecycles, and a
transcode example are Phase 2 (`ROADMAP.md`). The pre-pilot module (27 static
`extern "C"` declarations, compile-time linked) is preserved in git history.
