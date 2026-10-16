# xiom.gles -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.5 | **Last updated**: 2026-10-16

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- bridge probes the candidate pairs (Windows ANGLE DLLs + Android system sonames) via `LoadLibraryA`/`dlopen` + `eglGetProcAddress` |
| G2 pin (sonames + symbol set + session attribs) | Done -- `SPEC.md` sec. 2 |
| Staged probe + classification | Done -- ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL |
| Pbuffer session (no window system dependency) | Done -- 64x64 RGBA8 pbuffer, ES3 context (ES2 fallback) |
| Full GLES 2.0->3.2 core surface (generated) | Done -- 358 commands + 1001 consts (`gles_cmds_01..04`, `gles_consts_1..5`); 358/358 resolved live |
| Android leg: system sonames + NDK r27b delta (generated) | Done -- loader candidates for both platforms; 494 extension commands + 1225 consts (`gles_android_*`); on-device probe PASS (SwiftShader) |
| EGL android family | Done -- measured complete over the NDK r27b EGL headers (delta 0; `EGL_ANDROID_*` entry points + constants carried by the EGL surface) |
| Full EGL 1.0->1.5 + extension surface (generated) | Done -- 158 commands (44 core + 114 ext) + 694 consts; 44/44 core resolved live |
| Per-call resolver + session API | Done -- `gles_get_proc`/`gles_egl_proc`, `gles_session_display` |
| ANGLE runtime pin for CI | Phase 2 (consumers provide the pair today) |
| Window-system surfaces (WGL/EGL native windows) | Phase 2 (consumer ask) |

## Phase 2 (remaining)

1. **ANGLE runtime pin for CI**: fetch a pinned ANGLE prebuilt pair into a
   lane-local test dir (never vendored into the package) so CI hosts
   without an Electron payload still get the live stage; document the
   hash in SPEC sec. 2 as the test-runtime sample.
2. **Window-system integration**: EGL native-window surfaces
   (`eglCreateWindowSurface`) + a small Win32/ANGLE window helper if a
   consumer (engine platform layer) asks; pbuffer covers headless use.
3. **Android arm64 device run**: the repro driver already cross-builds
   the aarch64 bundle; run the same probe on an arm64 device when one
   exists (G1/G4 in `docs/ANDROID-SDK100.md`).
4. **GLES 1.x**: out of scope unless a legacy consumer asks (documented
   delta exclusion; `libGLESv1_CM.so` is still probed as a candidate).
5. **Extension availability reporting**: `gles_has_extension(name)`-style
   helpers over `glGetStringi`/`eglQueryString(EGL_EXTENSIONS)` (the
   android delta makes this more useful).
6. **Delta re-pin glide**: when the Android wave moves to a newer NDK,
   re-run the generators (name set moves with the NDK; `gen_egl.py`
   gates EGL drift) and refresh the manifests.
