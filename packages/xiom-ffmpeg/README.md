# xiom.ffmpeg

FFmpeg (libavcodec/libavformat/libavutil/libswresample) bindings for XIOM
via a **multi-soname generation loader**: `ffmpeg_load()` resolves one
release generation (8.x .. 4.x) of the four shared libraries at runtime and
every call goes through resolved function pointers. No link-time dependency,
no headers, no vendored code -- and the suite reports **SKIP** (green) when
no build is present (LGPL policy: dynamic linking only, nothing vendored).

> **Status:** `incubating` -- suite green on the pin (v0.64.4; 0.2.0 published
> in `eco-v0.1.122`; **0.3.0 in `eco-v0.1.176` (sha256 `24a5c522...`)**):
> **23/23 x2** with local generations on PATH (GIMP 6.1.1, `libdav1d` 1.4.1;
> Blender 7.1.1 GPL, `libaom-av1` -- the 0.4.0 gate failed 22/23 there and
> 0.4.1 fixes it by resolving the AV1 codec id by name),
> **12/12** on 0.3.0-era sets (Cascadeur 6.0 / CapCut / OBS),
> and **3/3 x2** SKIP on the default PATH.
> **Lane:** bindings (`keywords: ["binding"]`).
> **Published**: `0.4.1` in `eco-v0.1.179` (sha256 `50f6d46b...`).

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

  let l = ffmpeg_load();
  if l.is_ok {
    let lib: FfmpegLibrary = l.value;
    let d = ffmpeg_demux_open(&lib, "clip.ivf");
    if d.is_ok {
      let demux: FfDemuxer = d.value;
      let best = ffmpeg_demux_best_stream(&demux, FFMPEG_MEDIA_TYPE_VIDEO);
      // resolve the generation's numeric AV1 id by name: AVCodecID values
      // shift across FFmpeg majors (226 on lavc 60.x, 225 on lavc 61.x)
      let av1_id = ffmpeg_codec_id_by_name(&lib, "av1");
      io.println("best video stream: " + ffmpeg_codec_name(&lib, av1_id)
        + " index " + best.index);
      // read loop: feed each packet to ffmpeg_decoder_send or copy the
      // payload out with ffmpeg_demux_packet_bytes, then unref + free.
      var more = true;
      while more {
        let pr = ffmpeg_demux_read_packet(&demux);
        if !pr.ok { more = false; }
        else {
          var ig1 = ffmpeg_demux_packet_unref(&demux, pr.packet);
          var ig2 = ffmpeg_demux_packet_free(&demux, pr.packet);
        }
      }
      var igc = ffmpeg_demux_close(&demux);
    }
    var igl = ffmpeg_close(&lib);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `ffmpeg_load`, `ffmpeg_load_named(4 sonames)`, `ffmpeg_close`, `FfmpegLibrary` |
| Probe | `ffmpeg_probe(lib)`, `ffmpeg_probe_default`, `ffmpeg_probe_named(...)`, `FfmpegInfo` |
| Helpers | `ffmpeg_version_str(packed)`, `ffmpeg_lgpl_build(info)`, `ffmpeg_codec_name(lib, id)`, `ffmpeg_codec_id_by_name(lib, name)` |
| Decode (0.3.0) | `ffmpeg_av1_decoder_open(_named)`, `ffmpeg_decoder_send/flush/receive/close`, `ffmpeg_packet_alloc/from_bytes/unref/free`, `ffmpeg_frame_alloc/unref/free`, `FfDecoder`, `FfPacketOutcome`, `FfFrameOutcome` |
| Demux (0.4.0) | `ffmpeg_demux_open/close`, `ffmpeg_demux_stream_count/stream_info`, `ffmpeg_demux_best_stream`, `ffmpeg_demux_read_packet`, `ffmpeg_demux_packet_bytes/unref/free`, `ffmpeg_demux_seek`, `FfDemuxer`, `FfStreamInfo`, `FfBestStream`, `FfPacketRead`, `FfSeekOutcome` |
| Kinds | `FFMPEG_LOAD_ABSENT`, `FFMPEG_LOAD_ABI`, `FFMPEG_PROBE_FAILED`, `FFMPEG_DECODER_ABSENT`, `FFMPEG_DEMUX_FAILED` |
| Constants | `FFMPEG_MEDIA_TYPE_VIDEO/AUDIO`, `FFMPEG_SEEK_BACKWARD` |

Generations: 8.x (`avcodec-62`), 7.x (`avcodec-61`), 6.x (`avcodec-60`),
5.x (`avcodec-59`), 4.x (`avcodec-58`) -- a generation must resolve all four
libraries (avcodec/avformat/avutil/swresample); a partial set is skipped,
never mixed across ABI generations. The probe reports the version string,
the four packed versions and the build's license/configuration evidence.

Demux notes: the packet read loop returns an owned AVPacket (feed it to
`ffmpeg_decoder_send` directly or copy the payload out with
`ffmpeg_demux_packet_bytes`); `ffmpeg_demux_stream_info` reports the codec
id/type, geometry and stream time base; `ffmpeg_demux_seek(..., 0,
FFMPEG_SEEK_BACKWARD)` repositions for a re-read. All demux calls are
LGPL-safe core libavformat/libavcodec APIs.

## Tests

```
scripts/port.ps1 -Package xiom.ffmpeg
```

Expected (on this host): 3 `[PASS]` SKIP markers on the default PATH; with a
complete generation directory prepended to PATH: 23 `[PASS]` (12 decode +
11 demux checks) on both the 6.1.1 and 7.1.1 generations (the demux codec-id
gate resolves the AV1 id by name). Encode/transcode wrappers are Phase 3
(`ROADMAP.md`).
