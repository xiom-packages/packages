# xiom.ffmpeg

> **Status:** `incubating` -- not yet conformance-tested; not yet published to the XIOM registry.
> **Scope:** FFI bindings to FFmpeg for media demuxing, decoding, encoding, and scaling.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `avcodec` | libavcodec bindings for encoding and decoding |
| `avformat` | libavformat bindings for containers |
| `swscale` | libswscale pixel format conversion |
| `ffi` | C ABI declarations and buffer lifetime management |
