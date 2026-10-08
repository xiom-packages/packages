# xiom.glfw -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.0 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `glfw_load`/`glfw_close` over `xiom.ffi.dl` |
| SKIP-when-absent / no-platform | Done -- `GLFW_LOAD_ABSENT` / `GLFW_LOAD_NO_PLATFORM` |
| ABI-mismatch detection | Done -- `GLFW_LOAD_ABI` + handle cleanup |
| Smoke suite (init/version/timer/error) | Done -- 9 checks present, 3 checks absent |
| G2 pin (soname + header + symbols) | Done -- `SPEC.md` §2 |
| Window / input / monitor resources | Phase 2 |
| POSIX loader (`libglfw.so.3`) | Phase 2 |

## Phase 2 (next touches)

1. Window layer over the loader: `glfw_window_create/destroy/should_close/
   set_title/get_size/get_framebuffer_size`, `glfw_poll_events`; GUI paths
   capability-gated (headless CI skips cleanly through the same
   classification).
2. Input layer: `glfw_get_key`, `glfw_get_mouse_button`, `glfw_get_cursor_pos`
   with XIOM-owned out-params; event polling only when a window exists.
3. Monitor layer: primary monitor + video mode query behind the same
   SKIP/FAIL kinds.
4. Context creation interop with `xiom.opengl` Phase 2 (shared context
   helpers; keep the packages independent -- no cross-package imports).
5. POSIX loader fallback (`libglfw.so.3`) when a Linux CI target exists.
6. Restore the window/input examples (one per feature) as the Phase 2
   resources land; the current demo covers the loader smoke only.
