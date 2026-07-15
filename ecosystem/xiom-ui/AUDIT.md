# xiom-ui — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| xiomc | >= v0.45.3 | XIOM compiler |
| GLFW | >= 3.3 | Window backend (for `xiom.ui.backend` OpenGL rendering) |
| OpenGL | System | Rendering backend (for `xiom.ui.backend`) |
| ffi_bridge.c | Project runtime | C bridge for `xiom_alloc`, `xiom_free_ptr`, etc. |

## Platform-Specific Installation

### Windows
1. **GLFW**: See `xiom-glfw/AUDIT.md`
2. **OpenGL**: Ships with Windows GPU drivers (opengl32.dll)
3. Link flags: `-l opengl32 -l glfw3`

### Linux
```bash
# Ubuntu/Debian
sudo apt install libglfw3-dev mesa-common-dev
```
Link flags: `-l GL -l glfw`

### macOS
```bash
brew install glfw
```
Link flags: `-framework OpenGL -l glfw`

## Build Command

```powershell
# Type-check only (pure XIOM modules)
xiomc --check src/types.xi src/layout.xi src/widgets.xi src/render.xi `
  src/theme.xi src/application.xi src/demo.xi

# Full build with OpenGL backend
xiomc src/types.xi src/layout.xi src/widgets.xi src/render.xi `
  src/theme.xi src/application.xi src/demo.xi src/backend.xi `
  ../runtime/ffi_bridge.c -l glfw3 -l opengl32 -o app.exe
```

## Compile Status
- All 8 source files — **PASSED** (multi-file compile)
- Individual files require multi-file compilation (cross-module `use` deps)

## Fixes Applied

### 1. Cross-module `use` declarations added (5 files)
The following files were missing `use` statements for their types from other xiom.ui modules:

| File | Added imports |
|------|---------------|
| `src/demo.xi` | `use xiom.ui.types;` `use xiom.ui.layout;` `use xiom.ui.widgets;` `use xiom.ui.render;` `use xiom.ui.theme;` `use xiom.ui.application;` |
| `src/application.xi` | `use xiom.ui.types;` `use xiom.ui.theme;` `use xiom.ui.render;` |
| `src/theme.xi` | `use xiom.ui.types;` |
| `src/layout.xi` | `use xiom.ui.types;` |
| `src/render.xi` | `use xiom.ui.types;` |

### 2. Method call resolution (`src/layout.xi:73-84`)
- Inlined the `advance(size)` method call body into `LayoutContext.allocate()`.
- The compiler cannot resolve same-type method calls via implicit `self` — this is a known compiler limitation (caller-side method dispatch requires explicit receiver).

### 3. Unit type workaround (`src/demo.xi`)
- `Result[Unit, Str]` → `Result[Int, Str]` — the compiler does not recognize `Unit` as a type name.
- `Ok(Unit{})` → `Ok(0)` — `Unit{}` is not a valid literal.
- `()` is supported as a value but NOT as a type parameter.
- Workaround uses `Int` as a placeholder return type for demo functions.

## Known Compiler Gaps Affecting This Package
- **`()` type**: Supported as a value literal (GAP-12 closed) but not as a type in generics like `Result[(), Str]`.
- **Same-type method resolution**: Calling `advance(size)` from within a `LayoutContext` method requires explicit inlining or a forwarding free function.
- **`extern "C"`**: Working (GAP-2 closed) — `src/backend.xi` uses it.
- **`pub const`**: Working (GAP-3 closed) — `src/backend.xi` uses it.
