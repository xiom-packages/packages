# xiom.ffmpeg

FFmpeg (libavcodec/libavformat/libavutil/libswresample) bindings for XIOM
via a **multi-soname generation loader**: `ffmpeg_load()` resolves one
release generation (8.x .. 4.x) of the four shared libraries at runtime and
every call goes through resolved function pointers. No link-time dependency,
no headers, no vendored code -- and the suite reports **SKIP** (green) when
no build is present (LGPL policy: dynamic linking only, nothing vendored).

> **Status:** `incubating` -- suite green on the pin (v0.64.1):
> **4/4 x2** with a local LGPL set on PATH (`FFmpeg 6.0`, license
> `LGPL version 2.1 or later`), **4/4** on a GPL 7.1.1 set (reported as
> data), **2/2 x2** SKIP on the default PATH, and **2/2** SKIP on partial
> generations (DLL sets missing `swresample`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.ffmpeg;

fn main() {
  let p = ffmpeg_probe_default();
  if !p.is_ok {
    io.println("FFmpeg unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: FfmpegInfo = p.value;
  io.println("FFmpeg " + info.version_info);
  io.println(info.license);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `ffmpeg_load`, `ffmpeg_load_named(4 sonames)`, `ffmpeg_close`, `FfmpegLibrary` |
| Probe | `ffmpeg_probe(lib)`, `ffmpeg_probe_default`, `ffmpeg_probe_named(...)`, `FfmpegInfo` |
| Helpers | `ffmpeg_version_str(packed)`, `ffmpeg_lgpl_build(info)` |
| Kinds | `FFMPEG_LOAD_ABSENT`, `FFMPEG_LOAD_ABI`, `FFMPEG_PROBE_FAILED` |

Generations: 8.x (`avcodec-62`), 7.x (`avcodec-61`), 6.x (`avcodec-60`),
5.x (`avcodec-59`), 4.x (`avcodec-58`) -- a generation must resolve all four
libraries (avcodec/avformat/avutil/swresample); a partial set is skipped,
never mixed across ABI generations. The probe reports the version string,
the four packed versions and the build's license/configuration evidence.

## Tests

```
scripts/port.ps1 -Package xiom.ffmpeg
```

Expected (on this host): 2 `[PASS]` SKIP markers on the default PATH; with a
complete LGPL generation directory prepended to PATH: 4 `[PASS]`.
Demux/decode/transcode wrappers are Phase 2 (`ROADMAP.md`).
