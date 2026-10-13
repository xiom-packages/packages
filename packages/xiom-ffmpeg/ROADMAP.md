# xiom.ffmpeg -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot module: static `extern "C"` FFmpeg declarations + 26-test suite (preserved in git history)

## Phase 2 (Done) -- 0.2.0 dynamic loader
- [x] Multi-soname generation loader (avcodec/avformat/avutil/swresample); SKIP when absent, never FAIL
- [x] LGPL-safe capability probe: `av_version_info` + four library versions + license/configuration evidence
- [x] Conformance suite: deterministic SKIP classification + present-path checks

## Phase 3 (In progress)
- [x] 0.3.0 AV1-class decode surface: decoder discovery by name
      (`libdav1d`/`libaom-av1` software wrappers preferred, native `av1`
      last), codec-context open, packet/frame lifecycle
      (`av_packet_alloc`/`av_packet_from_data`/`av_packet_unref`/
      `av_packet_free`, `av_frame_alloc`/`av_frame_unref`/
      `av_frame_free`), send/receive/flush decode loop with
      width/height/AVPixelFormat read-out; IVF fixture + x2 present-path
      proof (real 3-frame AV1 decode on three vendor builds)
- [ ] Container demux: `avformat_open_input` / `av_find_best_stream` /
      `av_read_frame` over resolved pointers (needs a codecpar-to-context
      bridge helper for the `AVCodecParameters` hand-off) -- next
- [ ] Frame pixel copy-out (`av_frame_copy` / plane copy into owned slots)
      for engine pixel consumption
- [ ] Audio decode (same send/receive model on an audio codec context)
- [ ] Hardware-accelerated AV1: `av_hwdevice_ctx_create` +
      `av_hwframe_transfer_data` (the native `av1` decoder's software path
      is hwaccel-only in this lineage; no hw device today -> ENOSYS/SKIP)
- [ ] Encode path + transcode pipeline example (`examples/transcode.xi`)
      with a real input fixture
- [ ] Filter graph (`libavfilter` as a separate generation entry)
- [ ] WASM cross-compilation target
