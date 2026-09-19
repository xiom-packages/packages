# xiom.ffmpeg -- ROADMAP

## Phase 1 (Done)
- [x] `ffmpeg.xi` -- module `xiom.ffmpeg` with 20 extern "C" raw bindings
- [x] Opaque types: `FfmpegContext`, `FfmpegPacket`, `FfmpegFrame`
- [x] Safe wrappers: `open_input`, `close_input`, `find_stream_info`, `get_video_stream`, `read_frame`, `decode_frame`, `encode_frame`, `write_frame`, `open_output`
- [x] Resource helpers: `alloc_packet`, `free_packet`, `alloc_frame`, `free_frame`
- [x] Constants: `AVMEDIA_TYPE_VIDEO`, `AVMEDIA_TYPE_AUDIO`, `AV_ERROR_EOF`, `AV_ERROR_EAGAIN`, `AV_SUCCESS`
- [x] `tests/test_conformance.xi` -- 26 tests covering types, constants, resource lifecycle, all 9 safe wrappers, error chains, `int_to_str`, contract stubs
- [x] `requires:` contract on `open_input` and `open_output` (path.len() > 0)

## Phase 2 (Planned)
- [ ] FFmpeg DLL auto-detection (PATH vs bundled)
- [ ] Safe stream-level wrapper (`FfmpegStream` type)
- [ ] Codec parameter introspection (`get_codec_name`, `get_resolution`)
- [ ] Audio stream support (decode/encode)
- [ ] Transcode pipeline example (`examples/transcode.xi`)
- [ ] Integration tests with real input files

## Phase 3 (Future)
- [ ] Frame data access (pixel buffer read/write)
- [ ] Filter graph support (`libavfilter`)
- [ ] Hardware acceleration support (CUDA, DXVA2, VAAPI)
- [ ] Streaming protocols (RTMP, HLS, SRT)
- [ ] WASM cross-compilation target
