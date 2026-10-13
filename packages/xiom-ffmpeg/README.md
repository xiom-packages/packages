# xiom.ffmpeg

FFmpeg (libavcodec/libavformat/libavutil/libswresample) bindings for XIOM
via a **multi-soname generation loader**: `ffmpeg_load()` resolves one
release generation (8.x .. 4.x) of the four shared libraries at runtime and
every call goes through resolved function pointers. No link-time dependency,
no headers, no vendored code -- and the suite reports **SKIP** (green) when
no build is present (LGPL policy: dynamic linking only, nothing vendored).

The 0.3.0 **AV1-class decode surface** adds decoder discovery
(`libdav1d`/`libaom-av1` preferred, native `av1` last), codec-context open,
a packet/frame lifecycle and a send/receive/flush decode loop that exposes
frame width/height/pixel-format. Packets are built from XIOM-owned bytes by
`src/ffmpeg_bridge.c` (our code; FFmpeg is still resolved at runtime only).

> **Status:** `incubating` -- suite green on the pin (v0.64.4; 0.2.0 published
> in `eco-v0.1.122`; **0.3.0 in `eco-v0.1.176` (sha256 `24a5c522...`)**):
> **12/12 x2** with a software AV1 decoder present (`libaom-av1` on Blender
> 7.1.1; `libdav1d` 1.2.1 on Cascadeur 6.0 and CapCut 7.x -- 3 real AV1
> frames decoded per run: 64x48, `yuv420p`), **3/3 x2** SKIP on the default
> PATH, and **3/3** SKIP on partial generations (DLL sets missing
> `swresample`).
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

Decode AV1 (IVF elementary stream; keep the library loaded while decoding):

```xiom
let l = ffmpeg_load();
if l.is_ok {
  let lib: FfmpegLibrary = l.value;
  let d = ffmpeg_av1_decoder_open(&lib);
  if d.is_ok {
    let dec: FfDecoder = d.value;          // decoded via libdav1d/libaom-av1
    let po = ffmpeg_packet_from_bytes(&dec, &ivf_bytes, offset, size);
    if po.ok {
      let rc = ffmpeg_decoder_send(&dec, po.packet);
      let fr = ffmpeg_decoder_receive(&dec);
      if fr.kind == FFMPEG_DECODE_FRAME {
        io.println("decoded frame, pixel format " + fr.pix_fmt_name);
        // fr.width / fr.height hold the decoded dimensions
        let ig = ffmpeg_frame_unref(&dec, fr.frame);
        let ig2 = ffmpeg_frame_free(&dec, fr.frame);
      }
      let ig3 = ffmpeg_packet_unref(&dec, po.packet);
      let ig4 = ffmpeg_packet_free(&dec, po.packet);
    }
    let ic = ffmpeg_decoder_close(&dec);
  }
  let lc = ffmpeg_close(&lib);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `ffmpeg_load`, `ffmpeg_load_named(4 sonames)`, `ffmpeg_close`, `FfmpegLibrary` |
| Probe | `ffmpeg_probe(lib)`, `ffmpeg_probe_default`, `ffmpeg_probe_named(...)`, `FfmpegInfo` |
| Decode discovery | `ffmpeg_av1_decoder_open(lib)`, `ffmpeg_av1_decoder_open_named(lib, name)`, `FfDecoder` |
| Packet lifecycle | `ffmpeg_packet_alloc`, `ffmpeg_packet_from_bytes(dec, &Vec[UInt8], off, size)`, `ffmpeg_packet_unref`, `ffmpeg_packet_free` |
| Frame lifecycle | `ffmpeg_frame_alloc`, `ffmpeg_frame_unref`, `ffmpeg_frame_free` |
| Decode loop | `ffmpeg_decoder_send`, `ffmpeg_decoder_flush`, `ffmpeg_decoder_receive` -> `FfFrameOutcome`, `ffmpeg_decoder_close` |
| Helpers | `ffmpeg_version_str(packed)`, `ffmpeg_lgpl_build(info)` |
| Kinds | `FFMPEG_LOAD_ABSENT`, `FFMPEG_LOAD_ABI`, `FFMPEG_PROBE_FAILED`, `FFMPEG_DECODER_ABSENT`, `FFMPEG_DECODE_FRAME/AGAIN/EOF/ERROR`, `FFMPEG_ERR_EAGAIN/EOF/ENOSYS` |

Generations: 8.x (`avcodec-62`), 7.x (`avcodec-61`), 6.x (`avcodec-60`),
5.x (`avcodec-59`), 4.x (`avcodec-58`) -- a generation must resolve all four
libraries (avcodec/avformat/avutil/swresample); a partial set is skipped,
never mixed across ABI generations. The probe reports the version string,
the four packed versions and the build's license/configuration evidence.

AV1 discovery tries `libdav1d`, `libaom-av1`, then the native `av1`
(`FFMPEG_AV1_DECODERS` lists the name set). In the pinned 6.x-8.x lineage
the native `av1` decoder's software path is hardware-accelerator-only, so
without a hw device its first packet returns `FFMPEG_ERR_ENOSYS` (-40) and
the suite reports SKIP; the dav1d/aom wrappers are the software path
preferred by `ffmpeg_av1_decoder_open`.

## Bridge recipe

The decode surface links the small bridge `src/ffmpeg_bridge.c` (compiled
with `--c-source`; see `port.args.json`). Consumers building the package
from an installed artifact add the bridge the same way other bindings
packages do:

```
--c-source <installed>/src/ffmpeg_bridge.c
```

The bridge never links FFmpeg: the dynamic-loader model is unchanged.

## Tests

```
scripts/port.ps1 -Package xiom.ffmpeg
```

Expected (on this host): 3 `[PASS]` SKIP markers on the default PATH; with a
generation directory prepended to PATH that can software-decode AV1
(`libdav1d`/`libaom-av1` backing library present): 12 `[PASS]` including a
real 3-frame AV1 decode of `tests/fixtures/av1_64x48.ivf`. Container demux
(avformat) and hardware-accelerated AV1 are Phase 3 (`ROADMAP.md`).
