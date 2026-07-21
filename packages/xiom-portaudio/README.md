# xiom-portaudio

PortAudio &mdash; cross-platform audio I/O. System-installed.

## Quick Start

```xiom
use xiom.portaudio;
```

## Building

```powershell
xiom --release portaudio.xi -o portaudio.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- PortAudio &mdash; system-installed (`apt install portaudio19-dev`)

## Package Structure

```
├── portaudio.xi         # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
