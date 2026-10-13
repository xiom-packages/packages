# COVERAGE -- xiom.gles (GLES 2.0->3.2 + EGL 1.0->1.5)

Oracles: `KhronosGroup/OpenGL-Registry` @ `6af574a1` for the GLES surface
(`xml/gl.xml`, SHA256 `EC4FEE77...`) and `KhronosGroup/EGL-Registry` @
`db3425b8` for the EGL surface (`api/egl.xml`, SHA256 `1664DAC6...`).
Generators: `tools/gen_gles.py` + `tools/gen_egl.py` (deterministic,
Python stdlib).  Runtime target: ANGLE (consumer-provided pair, not
vendored).

| Set | Oracle | Emitted | Resolved (live) | Notes |
|-----|--------|---------|-----------------|-------|
| GLES core commands (2.0 -> 3.2) | 358 | 358 wrappers (`gles_cmds_01..04`) | **358/358** (`unresolved=0`) | loadability check in `tests/test_conformance.xi` |
| GLES core enums | 1001 | 1001 consts (`gles_consts_1..5`) | n/a | ES2+ES3 shares names with GL (separate modules) |
| GLES extensions | `gl2ext.h` surface | not generated (GL precedent) | n/a | availability via `glGetStringi` (Phase 2 helper) |
| EGL commands (1.0->1.5 + all extensions) | 158 | 158 wrappers (`egl_cmds_01..02`) | core: **44/44** (`unresolved=0`); extension commands implementation-conditional | full oracle emitted; ES3.2 vs ES3.0 context gate documented in SPEC sec. 3 |
| EGL enums | 694 | 694 consts (`egl_consts_1..3`) | n/a | `EGL_CAST` handle constants included |

Resolved = `xgs_get_proc` / `xgs_egl_proc` (`eglGetProcAddress` first,
then the libGLESv2/libEGL export tables) under a live ES session.
Witness (2026-10-13, ANGLE 2.1 D3D11 backend on an RTX 3070 Ti; run with
the VS Code payload dir on `PATH`):

```
[PASS] egl: EGL_VERSION = 1.5 (ANGLE 2.1 git hash: unknown hash)
[PASS] gles: GL_VERSION = OpenGL ES 3.0 (ANGLE 2.1 ...)
[PASS] surface: 358 ES core commands resolved (unresolved=0)
[PASS] egl: 44 core commands resolved (unresolved=0)
[PASS] surface: buffer roundtrip (size=64 err=0)
```

Skip ledger: `docs/gen_gles_manifest.json` (0 command / 0 const skips) and
`docs/gen_egl_manifest.json` (0 command / 0 const skips; `EGL_CAST(...)`
values parsed to their underlying 0/-1).

Out of scope for this wave: GLES 1.x, extension COMMAND wrappers for GLES
(GL precedent), window-system surfaces, POSIX sonames, a pinned ANGLE
binary for CI (`ROADMAP.md`).
