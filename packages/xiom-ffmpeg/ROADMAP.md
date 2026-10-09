# xiom.ffmpeg -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot module: static `extern "C"` FFmpeg declarations + 26-test suite (preserved in git history)

## Phase 2 (Done) -- 0.2.0 dynamic loader
- [x] Multi-soname generation loader (avcodec/avformat/avutil/swresample); SKIP when absent, never FAIL
- [x] LGPL-safe capability probe: `av_version_info` + four library versions + license/configuration evidence
- [x] Conformance suite: deterministic SKIP classification + present-path checks

## Phase 3 (Planned)
- [ ] Stream/container introspection (`avformat_open_input`, `av_find_best_stream` over resolved pointers)
- [ ] Packet/frame lifecycle wrappers (`av_packet_*`, `av_frame_*`)
- [ ] Decode/encode send/receive wrappers on a loaded generation
- [ ] Transcode pipeline example (`examples/transcode.xi`) with a real input fixture
- [ ] Audio stream support
- [ ] Filter graph / hardware acceleration (evaluate `libavfilter` as a separate generation entry)
- [ ] WASM cross-compilation target
