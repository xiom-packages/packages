# xiom.video

> **Status:** `incubating` -- implemented; conformance-tested (24/24) on
> compiler v0.62.2; not yet published.
> **Scope:** core video container abstractions -- format-agnostic container
> interface, elementary-stream demux/mux, frame buffers/timestamps/duration.
> **Deps:** `xiom.std` only (`xiom.string.builder`); pure XIOM, no FFI, no
> codecs (payloads stay opaque).

`xiom.video` is the format-agnostic container layer: a flat `VideoStream`
store, magic sniffing, a minimal RIFF/AVI muxer/demuxer as the proof
container, a raw elementary-stream (`XRAW`) mux/demux round-trip and
integer-only timebase math. Video and audio payloads are copied verbatim and
never interpreted.

## Modules

| Module | Source | Description |
|---|---|---|
| `xiom.video` | `src/video.xi` | Types (`VideoStream`, `VideoFrame`, `VideoTimebase`), sniffing, FourCC helpers, timebase/frame math |
| `xiom.video.store` | `src/store.xi` | Store builder API and guarded accessors (parallel vectors + one payload blob) |
| `xiom.video.avi` | `src/avi.xi` | Minimal RIFF/AVI mux and demux (LIST/chunks, avih/strh/strf, idx1) |
| `xiom.video.raw` | `src/raw.xi` | Raw `XRAW` elementary-stream mux/demux (exact round-trip) |
| `xiom.video.container` | `src/container.xi` | `video_demux` / `video_mux` dispatch over the readers/writers |

## What it does

- **Sniff** `avi`, `mkv` (EBML), `mp4` (`ftyp`), `ogg` and `raw` from the
  leading bytes.
- **Demux** AVI (stream headers, chunk ids, keyframe flags from `idx1`) and
  raw XRAW into one flat store; Matroska/WebM, MP4 and Ogg are recognised
  but deliberately unsupported (no demuxer in this package).
- **Mux** a store into a minimal, deterministic RIFF/AVI file (one `strl`
  per track, word-aligned `movi` chunks, `idx1` with `AVIF_HASINDEX`) or
  into the exact XRAW round-trip stream.
- **Frame model** with `VideoFrame` (track/pts/dts/duration/key) and integer
  timebase rescaling (`video_rescale`, round half away from zero, correct
  for negative timestamps).

## Non-goals

- Codecs: payloads (frame bytes, codec-private data) are opaque; nothing is
  decoded or re-encoded.
- Matroska/WebM, MP4 and Ogg demuxing or muxing (magic sniffing only).
- Streaming/incremental parsing: the whole buffer is parsed in one call.
- `Float64` timestamps: every quantity is integer milliseconds or a
  documented integer timebase.

## Usage

```xiom
use xiom.io;
use xiom.convert;
use xiom.video;
use xiom.video.store;
use xiom.video.container;

fn describe(bytes: &Vec[UInt8]) -> Int {
  io.println("format: " + video_format_name(video_sniff(bytes)));
  let r = video_demux(bytes);
  if !r.is_ok {
    io.println("video: " + r.error);
    return 1;
  }
  let s: VideoStream = r.value;
  io.println("tracks: " + convert.int_to_string(video_track_count(&s)));
  io.println("frames: " + convert.int_to_string(video_frame_count(&s)));
  var i = 0;
  while i < video_frame_count(&s) {
    io.println("  #" + convert.int_to_string(i)
      + " track " + convert.int_to_string(video_frame_track(&s, i))
      + " pts " + convert.int_to_string(video_frame_pts(&s, i))
      + "ms key " + convert.int_to_string(video_frame_is_key(&s, i)));
    i = i + 1;
  }
  return 0;
}
```

Building a container by hand (mux) uses the builder API in
`xiom.video.store`:

```xiom
use xiom.video;
use xiom.video.store;
use xiom.video.container;

fn build() -> Vec[UInt8] {
  var s = video_stream_new();
  video_add_track(&mut s, VIDEO_KIND_VIDEO, 0x64697678, 1, 25, 3, 640, 480, 0, 0);
  let payload = Vec[UInt8].new();       // opaque codec bytes
  video_add_frame(&mut s, 0, 0, 0, 40, 1, 0x30306463, &payload);
  let r = video_mux_avi(&s);
  if r.is_ok { let b: Vec[UInt8] = r.value; return b; }
  return Vec[UInt8].new();
}
```

## API summary

- Sniff/format: `video_sniff`, `video_format_name`, `video_fourcc_to_str`.
- Store: `video_stream_new`, `video_add_track`, `video_add_frame`,
  `video_add_frame_span`, `video_set_*`.
- Accessors: `video_format`, `video_stream_width/height/duration_ms`,
  `video_index_entries/ok`, `video_flags`, `video_track_*`
  (count/kind/codec/scale/rate/length/width/height/channels/sample_rate/
  duration_ms/frame_count), `video_frame_*`
  (count/track/pts/dts/duration/is_key/codec/size/chunk_offset/data/at).
- Math: `video_timebase_new`, `video_timebase_valid`,
  `video_timebase_rescale`, `video_rescale`, `video_units_to_ms`,
  `video_ms_to_units`, `video_tick_ms`, `video_frame_duration_ms`,
  `video_frame_new/valid/end`, `video_format_time`.
- Containers: `avi_mux`, `avi_demux`, `raw_mux`, `raw_demux`,
  `video_demux`, `video_mux`, `video_mux_avi`, `video_mux_raw`.

## Tests

```powershell
.\scripts\port.ps1 -Package xiom-video -TimeoutSec 60
```

Expected: 24 `[PASS]` lines, then `xiom.video: all tests passed` and
`port: PASS (program_exit=0)`. Every fixture is synthetic and inline; no
external files are read.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
