# xiom-imgui — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| cimgui | Dear ImGui v1.89+ (C wrapper) | Core ImGui library |
| GLFW | >= 3.3 | Window backend (via xiom-glfw) |
| xiom-glfw | 0.1.0 | GLFW XIOM bindings |
| xiomc | >= v0.45.3 | XIOM compiler |

## Platform-Specific Installation

### Windows
1. **cimgui**: Build from https://github.com/cimgui/cimgui
   - Compile `cimgui.dll`, `cimgui_glfw.dll`, `cimgui_vulkan.dll`
   - Place DLLs in the project directory or a PATH-accessible location
2. **GLFW**: See `xiom-glfw/AUDIT.md`
3. Link flags: `-l cimgui -l cimgui_glfw -l cimgui_vulkan -l glfw3 -l opengl32`

### Linux
```bash
# cimgui: build from source (CMake)
git clone https://github.com/cimgui/cimgui
cd cimgui && mkdir build && cd build
cmake .. && make
sudo make install
```
Link flags: `-l cimgui -l cimgui_glfw -l cimgui_vulkan -l glfw -l GL`

### macOS
```bash
brew install glfw
# Build cimgui from source
```
Link flags: `-l cimgui -l cimgui_glfw -l cimgui_vulkan -l glfw -framework OpenGL`

## Build Command

```powershell
# Windows (multi-file compile)
xiomc imgui.xi src/bindings.xi tests/test_imgui.xi `
  -l cimgui -l cimgui_glfw -l glfw3 -l opengl32 -o test_imgui.exe
```

## Compile Status
- `imgui.xi` — PASSED (standalone)
- `src/bindings.xi` — PASSED (multi-file with imgui.xi)
- `tests/test_imgui.xi` — PASSED (multi-file with imgui.xi + bindings.xi)

## Fixes Applied
- `src/bindings.xi:182`: Changed `ig_combo` parameter from `items: &Vec[Str]` to `items: Vec[Str]` (by value). Removed `items.clone()` call on borrowed value (Vec[Str] has no clone method in XIOM).

## Known Limitations
- Test only validates `create_context()` — no widget interaction testing.
- The `.xiom-bind` file uses `#` comments and is a binding definition, not compiled directly.
- `ig_combo` now takes ownership of the items Vec — callers must move, not borrow.
