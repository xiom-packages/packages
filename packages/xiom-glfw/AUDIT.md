# xiom-glfw -- Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| GLFW | >= 3.3 (3.4 recommended) | Window creation, input, OpenGL/Vulkan surface |
| xiom | >= v0.45.3 | XIOM compiler (tested with `E:\Projects\AXIOM\target\release\xiom.exe`) |

## Platform-Specific Installation

### Windows
1. **GLFW**: Download from https://www.glfw.org/download.html (64-bit Windows binaries)
   - Set `GLFW_DIR` environment variable to the GLFW root (contains `include/` and `lib-vc2022/` or similar)
   - Or install via vcpkg: `vcpkg install glfw3:x64-windows`
2. Link flags: `-l glfw3 -l opengl32 -l gdi32`

### Linux
```bash
# Ubuntu/Debian
sudo apt install libglfw3-dev
# Fedora
sudo dnf install glfw-devel
# Arch
sudo pacman -S glfw
```
Link flags: `-l glfw -l GL`

### macOS
```bash
brew install glfw
```
Link flags: `-l glfw -framework OpenGL -framework Cocoa -framework IOKit`

## Build Command

```powershell
# Windows
xiom glfw.xi tests/test_glfw.xi --link glfw3 --link opengl32 --link gdi32 -o test_glfw.exe

# Linux
xiom glfw.xi tests/test_glfw.xi --link glfw --link GL -o test_glfw
```

## Compile Status
- `glfw.xi` -- PASSED (multi-file with test_glfw.xi)
- `tests/test_glfw.xi` -- PASSED (multi-file with glfw.xi)

## Known Limitations
- Test `test_init_terminate` gracefully skips in headless environments (no display).
- The `.xiom-bind` file maps to GLFW 3.4 ABI and is not compiled by xiom directly.
