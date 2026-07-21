# xiom-portaudio — ROADMAP

**Module**: `xiom.portaudio`
**Phase**: 5 (Nice-to-Have)
**Status**: Implemented (Phase 1)

## Completed

- [x] `portaudio.xi` — full FFI `extern "C"` block (25 PortAudio C functions declared)
- [x] `pub type PaStream = Int` — opaque stream handle
- [x] 9 sample format constants (`FORMAT_FLOAT32`..`FORMAT_NONINTERLEAVED`)
- [x] 30 error code constants (`NO_ERROR`..`BAD_BUFFER_PTR`, matching PortAudio defines)
- [x] 5 stream flag constants (`NO_FLAG`, `CLIP_OFF`, `DITHER_OFF`, `NEVER_DROP_INPUT`, `PRIME_OUTPUT_BUFFERS_USING_STREAM_CALLBACK`)
- [x] 21 safe wrapper functions with `requires` contracts
- [x] `tests/test_conformance.xi` — 38 conformance tests across 10 sections
- [x] Lifecycle coverage: init/terminate, device query, stream open/start/stop/close/abort
- [x] I/O coverage: write stream, read stream
- [x] Diagnostics: stream info, stream time, CPU load, error text, version
- [x] Utility: sleep

## Planned (Phase 2)

- [ ] C bridge (`xiom_portaudio_bridge`) — native `.c`/`.dll` linking the PortAudio shared library
- [ ] `Vec[Float32]` buffer marshaling for `write_stream` / `read_stream`
- [ ] `package.xi` manifest
- [ ] `StreamParams` config struct (device, channel count, sample format, suggested latency, host API)
- [ ] `DeviceInfo` struct wrapper (name, max channels, default sample rate, host API)
- [ ] Stream callback support (XIOM closure → C function pointer)
- [ ] Blocking I/O integration tests with actual audio hardware

## Dependencies

- `xiom.ffi` — extern "C" linkage
- `xiom.test` — test framework
- `xiom.io` — I/O for test output
