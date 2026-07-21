# xiom-dxc

DirectX Shader Compiler (DXC) &mdash; HLSL to DXIL/SPIR-V shader compilation.

## Quick Start

```xiom
use xiom.dxc;
```

## Building

```powershell
xiomc --release dxc.xi -o dxc.exe
```

## Dependencies

- DirectX Shader Compiler &mdash; system-installed

## Package Structure

```
├── dxc.xi               # Main module
├── dxc_bridge.c         # C bridge
├── dxc_bridge.h         # C bridge header
├── src/                 # Source files
├── examples/            # Usage examples
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
