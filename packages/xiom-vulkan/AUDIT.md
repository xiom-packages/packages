# xiom-vulkan — Compiler Gap Audit & Production Readiness (v0.48.9)

**Compiler:** xiomc v0.48.9 — 783/783 tests, zero warnings
**Package:** packages/xiom-vulkan
**C bridge:** 0 errors, 0 warnings (clang -O2 -Wall -Wextra)
**Last sprint:** 8 (2026-07-20)

## Status: Production-ready for single-threaded use

### All critical audit findings resolved (6 sprints of C bridge fixes)
| Sprint | What | Status |
|--------|------|--------|
| S1 | 10 vkBind* + 6 vkMapMemory checks, offscreen leaks | ✅ |
| S2 | QueueSubmit, framebuffers NULL, fence, enumerate checks | ✅ |
| S3 | Thread-local error buffer, allocator destroy | ✅ |
| S5 | Render pass order, swapchain partial cleanup, image count, dynamic state | ✅ |
| S7 | Camera state per-app (XvkApp struct), DPI FontGlobalScale | ✅ |
| S8 | Descriptor set caching, validation ring buffer atomics, texture CB checks | ✅ |

### Compiler-dependent issues (not fixable in package)
| Gap | Status | Impact |
|-----|--------|--------|
| **CG-01b** Int32→Float32 cast | Fixed in v0.48.8 | Demo needs v0.48.8+ compiler |
| **G-27** E001 false-positives on loop counters | P2, non-fatal | 34 instances |
| **G-28** E001 extern out-param treated as move | P2, non-fatal | ~41 instances |
| **G-03** pub const module limit (~99) | P2 | vulkan.xi near limit |

### Workarounds applied for current compiler (v0.48.7)
- `xvk_camera_set_aspect_from_fb(Int32,Int32)` — aspect computed in C, avoids CG-01b
- `TRUE_I32`/`FALSE_I32` constants — avoids `1 as Int32` casts
- `Int32` params in wrapper signatures — avoids `as Int32` in caller code
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
| G4: Float Vec element reads | Garbage (sitofp, fptrunc missing) | **FIXED** — element type tracking + fptrunc coercion |
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

### ✓ Float32/Float64 Vec element operations (G4 FIXED)
Float Vec reads now use bitcast (not sitofp) for IEEE 754 reinterpretation.
Float64→Float32 push coercion added (fptrunc double→float).
```xiom
var v = Vec[Float32].new(); v.push(1.5);
let x: Float32 = v[0];  // x == 1.5 on v0.47.6+
```
