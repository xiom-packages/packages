# xiom-ffmpeg

FFmpeg &mdash; audio/video codec library (libavcodec, libavformat, libavutil). Decode/encode, transcode, stream.

## Quick Start

```xiom
use xiom.ffmpeg;
```

## Building

```powershell
xiom --release ffmpeg.xi -o ffmpeg.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- FFmpeg &mdash; system-installed (`winget install FFmpeg`, `apt install libavcodec-dev`)

## Package Structure

```
├── ffmpeg.xi            # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
