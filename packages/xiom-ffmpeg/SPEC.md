# xiom.ffmpeg -- SPEC

**Phase**: 2 (Scientific) | **Priority**: HIGH
**Status**: Implemented | **Depends on**: xiom.ffi

## What it wraps
FFmpeg -- audio/video codec library (libavcodec, libavformat, libavutil).
Decode/encode, transcode, stream.

## Dependencies
| What | How | Size |
|------|-----|------|
| FFmpeg | System-installed. `winget install FFmpeg`, `apt install libavcodec-dev` | ~50MB DLLs |

## Bundling strategy: System-installed only.

## Implementation

### Files
| File | Lines | Purpose |
|------|-------|---------|
| `ffmpeg.xi` | 212 | Module `xiom.ffmpeg` -- types, raw FFI, safe wrappers |
| `tests/test_conformance.xi` | 277 | 26 conformance tests |
| `ROADMAP.md` | 26 | Future phases |

### Types
```
pub type FfmpegContext = Int
pub type FfmpegPacket  = Int
pub type FfmpegFrame   = Int
```

### Extern "C" Block (20 functions)
`avformat_alloc_context`, `avformat_open_input`, `avformat_close_input`,
`avformat_find_stream_info`, `av_find_best_stream`, `av_read_frame`,
`av_packet_alloc`, `av_packet_unref`, `av_packet_free`,
`av_frame_alloc`, `av_frame_unref`, `av_frame_free`,
`avcodec_find_decoder`, `avcodec_alloc_context3`, `avcodec_open2`,
`avcodec_close`, `avcodec_free_context`,
`avcodec_send_packet`, `avcodec_receive_frame`,
`avcodec_send_frame`, `avcodec_receive_packet`,
`avformat_alloc_output_context2`, `avformat_new_stream`,
`avformat_write_header`, `av_interleaved_write_frame`,
`av_write_trailer`, `avformat_free_context`, `av_strerror`

### Safe Wrappers (9 + 4 helpers)
| Function | Returns | Contract |
|----------|---------|----------|
| `open_input(path)` | `Result[FfmpegContext, Str]` | `requires path.len() > 0` |
| `close_input(ctx)` | void | -- |
| `find_stream_info(ctx)` | `Result[Int, Str]` | -- |
| `get_video_stream(ctx)` | `Result[Int, Str]` | -- |
| `read_frame(ctx, pkt)` | `Result[Int, Str]` | -- |
| `decode_frame(ctx, pkt, frame)` | `Result[Int, Str]` | -- |
| `encode_frame(ctx, frame, pkt)` | `Result[Int, Str]` | -- |
| `write_frame(ctx, pkt)` | `Result[Int, Str]` | -- |
| `open_output(path, ctx)` | `Result[FfmpegContext, Str]` | `requires path.len() > 0` |
| `alloc_packet()` | `Result[FfmpegPacket, Str]` | -- |
| `free_packet(pkt)` | void | -- |
| `alloc_frame()` | `Result[FfmpegFrame, Str]` | -- |
| `free_frame(frame)` | void | -- |

### Constants
- `AVMEDIA_TYPE_VIDEO = 0`
- `AVMEDIA_TYPE_AUDIO = 1`
- `AV_ERROR_EOF = -541478725`
- `AV_ERROR_EAGAIN = -11`
- `AV_SUCCESS = 0`

### Tests: 26 (test_conformance.xi)
1. Type declarations exist (compile-time)
2. Constants defined
3. alloc_packet returns Ok
4. free_packet no crash
5. alloc_frame returns Ok
6. free_frame no crash
7. Packet + frame distinct handles
8. Multiple packets distinct
9. Multiple frames distinct
10. open_input valid path stub
11. open_input nonempty no trap
12. close_input null no crash
13. find_stream_info null returns Err
14. get_video_stream null returns Err
15. read_frame null returns Err
16. decode_frame null returns Err
17. encode_frame null returns Err
18. write_frame null returns Err
19. open_output valid path stub
20. Result chain null propagation
21. int_to_str positive
22. int_to_str zero
23. int_to_str negative
24. Error message format
25. EOF constant negative
26. EAGAIN constant negative

## API (original reference)
```xiom
pub fn av_register_all()
pub fn avformat_open_input(path) -> Result[FormatCtx, Str]
pub fn avcodec_find_decoder(id) -> Result[Codec, Str]
pub fn avcodec_decode_video2(ctx, frame, got) -> Result[Int, Str]
pub fn av_read_frame(ctx, pkt) -> Result[Int, Str]
```

## Effort: Week
