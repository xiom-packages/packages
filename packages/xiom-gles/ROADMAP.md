# xiom.gles -- Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-13

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- bridge resolves libEGL/libGLESv2 (EGL/GLESv2 fallback) + eglGetProcAddress |
| G2 pin (sonames + symbol set + session attribs) | Done -- `SPEC.md` sec. 2 |
| Staged probe + classification | Done -- ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL |
| Pbuffer session (no window system dependency) | Done -- 64x64 RGBA8 pbuffer, ES3 context (ES2 fallback) |
| Full GLES 2.0->3.2 core surface (generated) | Done -- 358 commands + 1001 consts (`gles_cmds_01..04`, `gles_consts_1..5`); 358/358 resolved live |
| Full EGL 1.0->1.5 + extension surface (generated) | Done -- 158 commands (44 core + 114 ext) + 694 consts; 44/44 core resolved live |
| Per-call resolver + session API | Done -- `gles_get_proc`/`gles_egl_proc`, `gles_session_display` |
| ANGLE runtime pin for CI | Phase 2 (consumers provide the pair today) |
| POSIX sonames (`libEGL.so`/`libGLESv2.so`) | Phase 2 |
| Window-system surfaces (WGL/EGL native windows) | Phase 2 (consumer ask) |

## Phase 2 (remaining)

1. **ANGLE runtime pin for CI**: fetch a pinned ANGLE prebuilt pair into a
   lane-local test dir (never vendored into the package) so CI hosts
   without an Electron payload still get the live stage; document the
   hash in SPEC sec. 2 as the test-runtime sample.
2. **POSIX path**: `libEGL.so.1`/`libGLESv2.so.2` behind the same
   classification API when a Linux CI target exists.
3. **Window-system integration**: EGL native-window surfaces
   (`eglCreateWindowSurface`) + a small Win32/ANGLE window helper if a
   consumer (engine platform layer) asks; pbuffer covers headless use.
4. **GLES 1.x**: out of scope unless a legacy consumer asks (ES1 is
   obsolete; ANGLE still ships `libGLESv1_CM.dll`).
5. **Extension availability reporting**: `gles_has_extension(name)`-style
   helpers over `glGetStringi`/`eglQueryString(EGL_EXTENSIONS)`.
