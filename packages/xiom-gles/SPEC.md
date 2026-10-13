# SPEC: xiom.gles -- OpenGL ES 2.0/3.2 + EGL 1.5 bindings via ANGLE

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.gles` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Khronos OpenGL ES + EGL API registries; runtime target ANGLE |
| Upstream license | registries Apache-2.0 (derived declarations/consts; notice in PROVENANCE.md) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (runtime-loaded ANGLE pair; POSIX sonames are a follow-on) |
| Compiler pin | v0.64.4 |

## 2. G2 pin: sonames + symbol set + session attribs

**Sonames:** `libEGL.dll` + `libGLESv2.dll` (ANGLE build), with the
`EGL.dll` + `GLESv2.dll` pair as a fallback.  Both are resolved at
**runtime** via `LoadLibraryA`/`GetProcAddress` + `eglGetProcAddress`
inside the vendored bridge -- there is no link-time dependency.  Absent
pair -> SKIP.

**Resolved symbol set (the ABI registry this package actually depends on):**

| Library (runtime-loaded) | Symbols |
|--------------------------|---------|
| `libEGL.dll` (required) | `eglGetDisplay`, `eglInitialize`, `eglQueryString`, `eglGetProcAddress` |
| `libEGL.dll` (session path) | `eglTerminate`, `eglGetError`, `eglBindAPI`, `eglChooseConfig`, `eglCreatePbufferSurface`, `eglCreateContext`, `eglMakeCurrent`, `eglDestroySurface`, `eglDestroyContext` |
| `libGLESv2.dll` (or via `eglGetProcAddress`) | `glGetString` (+ every generated wrapper entry point) |

**Session attribs pinned** (used by `xgs_query`/`xgs_session_open`):
default display; `eglBindAPI(EGL_OPENGL_ES_API=0x30A0)`; config
`SURFACE_TYPE=EGL_PBUFFER_BIT(0x1)`,
`RENDERABLE_TYPE=OPENGL_ES2_BIT(0x4)|OPENGL_ES3_BIT(0x40)`, RGBA8
(`R/G/B/A_SIZE=8`), `DEPTH_SIZE=0`, `STENCIL_SIZE=0`; pbuffer 64x64
(`EGL_WIDTH=0x3057`, `EGL_HEIGHT=0x3056`); context
`EGL_CONTEXT_CLIENT_VERSION=0x3098` = requested (3, falling back to 2).

**Local runtime sample (reference, NOT the pin -- build-dependent):**

| Artifact | Value |
|----------|-------|
| `libEGL.dll` (VS Code payload `2a59476c9b`) | 488,808 bytes, ANGLE 2.1, SHA256 `488C51EA9D29765ED22551051B86120D39B1E9C71428987A8DEC2BE9BCA141A7` |
| `libGLESv2.dll` (same payload) | 8,078,648 bytes, ANGLE 2.1, SHA256 `882A6A411E4C098B96823144EEC7BC3D6A1E06EAE3FC5CD417BF726496610A7F` |
| EGL_VERSION | `1.5 (ANGLE 2.1 git hash: unknown hash)` |
| GL_VERSION | `OpenGL ES 3.0 (ANGLE 2.1 ...)` |
| GL_RENDERER | `ANGLE (NVIDIA, NVIDIA GeForce RTX 3070 Ti (0x00002482) Direct3D11 vs_5_0 ps_5_0, D3D11-32.0.16.1692)` |
| GLSL | `OpenGL ES GLSL ES 3.00 (...)` |

ANGLE is **not vendored**: the consumer puts a directory containing the
pair on the DLL search path (an Electron payload such as VS Code's app dir
works as a test runtime).

**Oracle pins:**

| Surface | Oracle | SHA256 |
|---------|--------|--------|
| GLES 2.0 -> 3.2 core | `OpenGL-Registry` @ `6af574a1`, `xml/gl.xml` | `EC4FEE77D4BCCACE329C5B4530EFB1D34214BA5EC680B883ED63D88D16768382` |
| EGL 1.0 -> 1.5 + extensions | `EGL-Registry` @ `db3425b8`, `api/egl.xml` | `1664DAC6D8E10C4D276EA763CE45D7873BC1127A6DA1011600541A6D62D63A13` |

### Re-pin procedure

1. On a target host, re-run `scripts/port.ps1 -Package xiom.gles` with the
   ANGLE pair on `PATH` and compare the EGL/GL strings + resolved counts
   with this SPEC (ANGLE builds vary; strings are informational).
2. If a symbol in the table changes, update the bridge and this table in
   the same commit; the bridge fails closed (`GLES_LOAD_ABI`).
3. Record the new libEGL/libGLESv2 hashes as the reference sample.

## 3. Design: vendored C bridge + staged probe + generated surfaces

- `src/gles_probe.c` (our code, MIT/Apache) resolves ANGLE at runtime and
  performs the staged probe on a **pbuffer** surface (no window system
  dependency).  It links nothing but kernel32.
- The XIOM module (`gles.xi`, module `xiom.gles`) is a thin safe wrapper:
  all hand-written `unsafe`/`extern` are confined to it.  Public API:
  `gles_probe`, `gles_probe_named`, `gles_session_open`,
  `gles_session_is_active`, `gles_session_display`, `gles_get_proc`,
  `gles_egl_proc`, `gles_session_close`, `gles_unload`, `GlesInfo`,
  `GlesSession`, `GlesProbeError`, kinds.
- **Generated surfaces** (same pattern as `xiom.opengl`):
  - GLES: `src/gles_cmds_01..04.xi` (358 wrappers, modules
    `xiom.gles.gles_cmds_<grp>`), `src/gles_consts_1..5.xi` (1001 consts),
    `src/gles_names.xi` (`gles_cmd_names()`, `GLES_CMD_COUNT`);
    `src/gles_api.xi` (`GlesApi` + `gles_api_resolve`).  Generator
    `tools/gen_gles.py` (oracle `gl.xml`, `api="gles2"`, <= 3.2).
  - EGL: `src/egl_cmds_01..02.xi` (158 wrappers incl. all extension
    commands), `src/egl_consts_1..3.xi` (694 consts), `src/egl_names.xi`
    (`egl_cmd_names()` 158 / `egl_core_names()` 44); `src/egl_api.xi`
    (`EglApi` + `egl_api_resolve` calling `gles_egl_proc`).  Generator
    `tools/gen_egl.py` (oracle `EGL-Registry/api/egl.xml`).
- **Resolution semantics:** success at resolve time means the entry point
  exists in the runtime; version-gated ES commands must only be *called*
  when the reported context version supports them (ANGLE resolves the full
  set even for an ES 3.0 context).
- **Classification** (the suite maps it to markers):
  - `GLES_LOAD_ABSENT` -> SKIP (ANGLE pair missing; CI stays green)
  - `GLES_LOAD_NO_CONTEXT` -> SKIP (no display/config/context)
  - `GLES_LOAD_ABI` -> FAIL (present but exports missing; never silent)

## 4. Test matrix (recorded 2026-10-13, compiler v0.64.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| Full (VS Code ANGLE 2.1 on RTX 3070 Ti, D3D11) | `$env:PATH="<vscode-app-dir>;"+$env:PATH; scripts/port.ps1 -Package xiom.gles` | **PASS 18/18** -- constants (kinds + GL/EGL enums), SKIP classification (bogus pair), EGL_VERSION = 1.5 (ANGLE 2.1), GL_VERSION = `OpenGL ES 3.0`, ANGLE D3D11 renderer, GLSL ES 3.00, session (display live), **358/358 ES core commands resolved**, **44/44 EGL core commands resolved**, oracle counts (358 GLES + 158 EGL), bogus command -> 0, `glGetString` + `eglQueryString` wrappers live, `glGetIntegerv(GL_MAJOR_VERSION)` = 3, buffer roundtrip (size=64 err=0), session close, unload |
| SKIP classification | deterministic on every host via `gles_probe_named("xiom-absent-egl-xyz.dll", "xiom-absent-gles-xyz.dll")` | **PASS** |
| No-context SKIP path | code-reviewed; shares the kind mapping with the tested ABSENT branch | not exercised locally |
| Without ANGLE on PATH | the live path collapses to the ABSENT/SKIP classification | documented |

## 5. Scope

0.1.0 ships the **full generated GLES 2.0->3.2 core surface** (358 command
wrappers + 1001 enums) and the **full EGL surface** (158 command wrappers
incl. every declared extension command + 694 enums), driven by the live
session (`gles_session_open` keeps an ES context current on a 64x64
pbuffer; each wrapper resolves its entry point per call through
`eglGetProcAddress`, then the libGLESv2/libEGL export tables).

Not in scope: GLES 1.x (obsolete), WGL-style window-system integration
(ANGLE needs none for pbuffers; window surfaces come with a consumer ask),
a pinned ANGLE binary (consumers provide it), POSIX sonames.
