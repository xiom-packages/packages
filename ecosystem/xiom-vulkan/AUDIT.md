# xiom-vulkan — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| Vulkan SDK | >= 1.3 | GPU API (headers + loader) |
| GLFW | >= 3.4 | Window creation + Vulkan surface |
| clang/LLVM | >= 14 | C bridge compilation |
| glslc | >= 1.3 (Vulkan SDK) | GLSL → SPIR-V shader compilation |
| Rust/Cargo | Latest stable | Compiler build (xiomc) |
| xiomc | >= v0.45.3 | XIOM compiler |

## Platform-Specific Installation

### Windows
1. **Vulkan SDK**: Install from https://vulkan.lunarg.com/sdk/home
   - Sets `VULKAN_SDK` environment variable automatically
   - Provides `glslc.exe` in `$VULKAN_SDK\Bin`
2. **GLFW**: See `xiom-glfw/AUDIT.md` or set `GLFW_DIR`
3. **clang**: Install via LLVM from https://releases.llvm.org/ or `winget install LLVM.LLVM`

### Linux
```bash
# Vulkan SDK
# Ubuntu: https://vulkan.lunarg.com/doc/view/latest/linux/getting_started_ubuntu.html
# Arch: sudo pacman -S vulkan-devel glslang

# GLFW
sudo apt install libglfw3-dev

# clang
sudo apt install clang
```

### macOS
```bash
# Vulkan SDK
# Download from https://vulkan.lunarg.com/sdk/home

# GLFW
brew install glfw

# clang
# Ships with Xcode Command Line Tools
```

## Build Pipeline (4 steps)

The `build.ps1` script implements a 4-step pipeline:

```
1. GLSL Shaders → SPIR-V (glslc)
   shaders/triangle.vert/.frag → spv/triangle_vert.spv/.frag.spv
   shaders/cube.vert/.frag    → spv/cube_vert.spv/.frag.spv
   shaders/quad.vert/.frag    → spv/quad_vert.spv/.frag.spv
   shaders/particle.vert/.frag → spv/particle_vert.spv/.frag.spv

2. SPIR-V → Generated Header (PowerShell)
   Reads .spv files → xvk_shaders_generated.h (C arrays)

3. C Bridge (clang)
   bridge/xiom_vk_bridge.c → bridge/xiom_vk_bridge.obj

4. XIOM Compilation + Link (xiomc + clang)
   vulkan.xi + src/wrapper.xi + examples/*.xi + bridge/*.obj
   → final executable linked with vulkan-1 + glfw3
```

### Windows (PowerShell)
```powershell
.\build.ps1 -Target demo2d -Run
.\build.ps1 -Target demo3d -Run
.\build.ps1 -Target particles -Run
.\build.ps1 -Target shapes -Run
.\build.ps1 -Target cubes -Run
.\build.ps1 -Target test -Run
```

### Linux/macOS (Bash)
```bash
./build.sh demo2d
./build.sh test
```

## Compile Status
- `vulkan.xi` — PASSED (multi-file)
- `src/wrapper.xi` — PASSED (multi-file)
- `examples/demo_2d.xi` — PASSED (multi-file)
- `examples/demo_3d.xi` — PASSED (multi-file)
- `examples/demo_cubes.xi` — PASSED (multi-file)
- `examples/demo_particles.xi` — PASSED (multi-file)
- `examples/demo_shapes.xi` — PASSED (multi-file)
- `tests/test_vulkan.xi` — PASSED (multi-file)

## Fixes Applied
No fixes needed — all files compiled clean on first pass.
`extern "C"` blocks, `pub const`, tail expressions, and unit literal `()` all work.

## Known Limitations
- No text/sprite rendering in the bridge
- Offscreen rendering is 2D only
- No window-minimize handling
- Static error buffer (not thread-safe)
- Generated `xvk_shaders_generated.h` not in repo — must run build script first
- `bridge/xiom_vk_bridge.obj` is pre-compiled for Windows; rebuild needed for other platforms
