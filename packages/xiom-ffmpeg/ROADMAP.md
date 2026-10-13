# xiom.ffmpeg -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot module: static `extern "C"` FFmpeg declarations + 26-test suite (preserved in git history)

## Phase 2 (Done) -- 0.2.0 dynamic loader
- [x] Multi-soname generation loader (avcodec/avformat/avutil/swresample); SKIP when absent, never FAIL
- [x] LGPL-safe capability probe: `av_version_info` + four library versions + license/configuration evidence
- [x] Conformance suite: deterministic SKIP classification + present-path checks

## Phase 3 (In progress)
- [x] 0.3.0: AV1-class decode surface -- decoder discovery, codec-context open, packet/frame lifecycle, frame width/height/pixel-format read-out
- [x] 0.4.0: container demux -- `avformat_open_input`/`avformat_close_input` from a file path, stream enumeration (count, index, codec id/type, time base, geometry), `av_find_best_stream`, packet read loop (`av_read_frame` -> bytes/PTS/DTS/flags) feeding the decode loop, generic-index seek
- [ ] Decode/encode send/receive wrappers on a loaded generation (encode side)
- [ ] Transcode pipeline example (`examples/transcode.xi`) with a real input fixture
- [ ] Audio stream support (demux side is media-type generic; audio decode pending)
- [ ] Filter graph / hardware acceleration (evaluate `libavfilter` as a separate generation entry)
- [ ] WASM cross-compilation target
