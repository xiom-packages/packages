# xiom-vma

Vulkan Memory Allocator (VMA) &mdash; GPU memory allocation library for Vulkan. Reduces boilerplate and improves performance.

## Quick Start

```xiom
use xiom.vma;
```

## Building

```powershell
xiomc --release vma.xi -o vma.exe
```

## Dependencies

- Vulkan Memory Allocator &mdash; header-only, bundled
- `xiom-vulkan` (Vulkan API)

## Package Structure

```
├── vma.xi               # Main module
├── src/                 # Source files
├── examples/            # Usage examples
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
