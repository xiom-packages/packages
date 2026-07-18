# xiom-vulkan — Compiler Gap Audit & Production Readiness (v0.47.6)

**Compiler:** xiomc v0.47.6 "Production" — 495/495 tests, zero warnings
**Package:** ecosystem/xiom-vulkan v0.2.0

## Executive Summary

xiom-vulkan is **production-grade on v0.47.6.** All 11 examples + tests compile AND link with **native pointer types** using `xiomc` directly from PATH — zero workarounds, zero scratch layers. Two bridge fixes (hex-constant macro, Windows platform libs) eliminated all C compilation and linking issues.

## Build Commands (v0.47.6)

```powershell
# Single-command build + run any demo:
.\run.ps1 demo2d              # 2D triangle
.\run.ps1 demo3d              # Spinning cube
.\run.ps1 particles           # Particle fountain
.\run.ps1 shapes              # Animated quads + triangle
.\run.ps1 cubes               # 3x3 spinning cubes
.\run.ps1 vertex_buffer       # Vertex/index buffer workflow
.\run.ps1 compute             # Offscreen golden-image test
.\run.ps1 models              # Model field
.\run.ps1 sprites             # Sprite field
.\run.ps1 ui                  # Immediate-mode UI
.\run.ps1 viewport            # Multi-viewport
.\run.ps1 test -NoRun         # Headless CI test (build only)

# Or the legacy full pipeline script:
.\build.ps1 -Target demo2d -Run
.\build.ps1 -Target test -Run

# Direct xiomc (minimal):
xiomc -o demo_2d.exe examples/demo_2d.xi vulkan.xi src/wrapper.xi `
  --c-source bridge/xvk_bridge.obj `
  --link vulkan-1 --link glfw3 --link gdi32 --link user32 --link kernel32 --link shell32 --link ole32 `
  --link-path $env:VULKAN_SDK\Lib --link-path $env:GLFW_DIR\lib-vc2022
```

## Compile Status (v0.47.6)

| Target | xiomc compile | xiomc link | Notes |
|--------|--------------|------------|-------|
| 11 demos | ALL PASS | ALL PASS | Zero type errors, zero link errors |
| test_vulkan | PASS | PASS | Headless offscreen CI |
| vulkan.xi (standalone) | PASS | N/A | |

## v0.47.3 → v0.47.6 Fixes

| Issue | v0.47.3 | v0.47.6 |
|-------|---------|---------|
| `store %struct.Vec %tmp10` IR error | FIXED (checker) | Still fixed |
| `XVK_HANDLE_IMPL` hex-constant macro | BROKEN (clang 19) | **FIXED** — renamed macro param from `magic` to `magic_val` |
| Windows platform libs missing | Undefined symbols | **FIXED** — `--link gdi32 user32 kernel32 shell32 ole32` added |
| `--link-path` quoting in build.ps1 | BROKEN | **FIXED** |
| `cargo run` in build.ps1 | Doesn't work standalone | **FIXED** — uses `xiomc` from PATH |
| Missing demo targets in build.ps1 | 6 targets | **12 targets** (all 11 demos + test) |

## Compiler Gaps Resolved (v0.46 → v0.47.6)

| Gap | v0.46 | v0.47.6 |
|-----|-------|---------|
| G1: `Vec as *T` cast | Rejected | **FIXED** |
| G2: `&local` → `*T` param | Passes value, not address | **FIXED** |
| G3: `(if..) as Int32` | Rejected | **FIXED** |
| G4: Float Vec element reads | Garbage (sitofp) | **STILL BROKEN** — scalar floats fine |
| G5: Vec literal + .data → invalid IR | Rejected by clang | **FIXED** |
| G6: .data local rebind | E001 + crash | **FIXED** |
| G7: @null contract | clang reject | **FIXED** |

## Production FFI Patterns (v0.47.6)

### ✓ Native Vec→Ptr casting (all integer types verified)
```xiom
var v = Vec[Int32].new(); v.push(111); v.push(222);
unsafe { xvk_foo(v as *Int32, v.len()); }
```

### ✓ &local→Ptr out-parameter passing
```xiom
var w: Int32 = 0;
unsafe { xvk_get_size(&w); }
```

### ✓ Float32 scalar FFI (drawing APIs)
```xiom
unsafe { xvk_draw_triangle_2d(app, 1.0, 0.5, 0.0); }
```

### ✗ Float32/Float64 Vec element operations (G4 remaining)
Do not pass `Vec[Float32]` or `Vec[Float64]` to C if element values matter. Scalar floats work fine.
