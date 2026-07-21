# xiom-miniaudio

MiniAudio &mdash; single-header C audio playback and capture library. Cross-platform.

## Quick Start

```xiom
use xiom.miniaudio;
```

## Building

```powershell
xiomc --release miniaudio.xi -o miniaudio.exe
```

## Dependencies

- MiniAudio &mdash; single-header, bundled or system-installed

## Package Structure

```
├── miniaudio.xi         # Main module
├── miniaudio_safe.xi     # Safe wrapper layer
├── demo_miniaudio.xi     # Interactive demo
├── bridge/              # Platform bridge
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
