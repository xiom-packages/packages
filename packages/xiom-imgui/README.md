# xiom-imgui

Dear ImGui v1.92.9 &mdash; immediate-mode GUI library. Widgets, windows, tabs, popups, menus, plots, styling.

## Quick Start

```xiom
use xiom.imgui;
```

## Building

```powershell
xiomc --release imgui.xi -o imgui.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom-vulkan`
- `xiom-glfw`
- Dear ImGui &mdash; bundled or system-installed

## Package Structure

```
├── imgui.xi             # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
