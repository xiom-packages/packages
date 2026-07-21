# xiom-phonon

Steam Audio (Phonon) &mdash; 3D spatial audio library. Binaural rendering, occlusion, physics-based sound.

## Quick Start

```xiom
use xiom.phonon;
```

## Building

```powershell
xiomc --release phonon.xi -o phonon.exe
```

## Dependencies

- Steam Audio SDK &mdash; system-installed

## Package Structure

```
├── phonon.xi            # Main module
├── phonon_safe.xi        # Safe wrapper layer
├── demo_phonon.xi        # Interactive demo
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
