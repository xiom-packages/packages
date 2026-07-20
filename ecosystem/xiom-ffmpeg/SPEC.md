# xiom-ffmpeg — SPEC

**Phase**: 2 (Scientific) | **Priority**: HIGH
**Status**: SPEC only | **Depends on**: xiom.ffi

## What it wraps
FFmpeg — audio/video codec library (libavcodec, libavformat, libavutil).
Decode/encode, transcode, stream.

## Dependencies
| What | How | Size |
|------|-----|------|
| FFmpeg | System-installed. `winget install FFmpeg`, `apt install libavcodec-dev` | ~50MB DLLs |

## Bundling strategy: System-installed only.

## API (minimal)
```xiom
pub fn av_register_all()
pub fn avformat_open_input(path) -> Result[FormatCtx, Str]
pub fn avcodec_find_decoder(id) -> Result[Codec, Str]
pub fn avcodec_decode_video2(ctx, frame, got) -> Result[Int, Str]
pub fn av_read_frame(ctx, pkt) -> Result[Int, Str]
```

## Effort: Week
