# PROVENANCE -- xiom.gles

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstreams (oracles):**
  - `KhronosGroup/OpenGL-Registry`, clone at `E:\repos\OpenGL-Registry`,
    pinned at commit **`6af574a14089ccfee87efe230ebcdd8742859813`**
    ("Merge pull request #685 ...", 2026-10-06) for the **GLES** surface:
    oracle file `xml/gl.xml`, SHA256
    `EC4FEE77D4BCCACE329C5B4530EFB1D34214BA5EC680B883ED63D88D16768382`
    (2,822,494 bytes).
  - `KhronosGroup/EGL-Registry`, clone at `E:\repos\EGL-Registry`, pinned
    at commit **`db3425b8246136faccb5e2782b5694960bd6edf1`**
    ("Transfer CoreAVI reservations to Lynx (#225)", 2026-09-21) for the
    **EGL** surface: oracle file `api/egl.xml`, SHA256
    `1664DAC6D8E10C4D276EA763CE45D7873BC1127A6DA1011600541A6D62D63A13`.
- **Runtime target:** ANGLE (`libEGL.dll` + `libGLESv2.dll`), resolved at
  runtime; **not vendored** and no ANGLE source is copied.  The consumers
  provide the pair on the DLL search path; absent -> SKIP.
- **Target surface:**
  - GLES: union of `<feature api="gles2">` requires up to
    `GL_ES_VERSION_3_2` (verbatim registry signatures).
  - EGL: `EGL_VERSION_1_0..1_5` + every declared extension command.
- **Generated surface** (branch `bindings`):
  - `src/gles_cmds_01..04.xi` -- 358 GLES command wrappers;
  - `src/gles_consts_1..5.xi` -- 1001 GLES enum values;
  - `src/gles_names.xi` -- `gles_cmd_names()` + `GLES_CMD_COUNT`;
  - `src/gles_api.xi` -- `GlesApi` + `gles_api_resolve`;
  - `src/egl_cmds_01..02.xi` -- 158 EGL command wrappers (incl. all
    extension commands);
  - `src/egl_consts_1..3.xi` -- 694 EGL enum values;
  - `src/egl_names.xi` -- `egl_cmd_names()` 158 / `egl_core_names()` 44;
  - `src/egl_api.xi` -- `EglApi` + `egl_api_resolve`.
  - Generators: `tools/gen_gles.py`, `tools/gen_egl.py` (Python stdlib
    only, deterministic; manifests `docs/gen_gles_manifest.json`,
    `docs/gen_egl_manifest.json`, oracle==emitted, 0 skips).
- **Loader path:** `src/gles_probe.c` (our code): runtime `LoadLibraryA`
  ("libEGL.dll" + "libGLESv2.dll", fallback "EGL.dll" + "GLESv2.dll") +
  `eglGetProcAddress`, then the libGLESv2/libEGL export tables;
  `xgs_session_open` keeps an ES context current on a 64x64 pbuffer.
  No link-time dependency; absent pair -> SKIP.
- **Derived vs independent:** declarations/constants are **derived**
  (mechanical extracts of the Khronos registries, Apache-2.0); the C
  bridge and all XIOM code are original to this package.
- **Coverage proof:** `tests/test_conformance.xi` -- live-session
  resolution check 358/358 GLES core commands + 44/44 EGL core commands
  (`unresolved=0`), oracle counts (358/158), wrapper-level
  `glGetString`/`eglQueryString`, buffer roundtrip (2026-10-13,
  v0.64.4, ANGLE 2.1 D3D11 on an RTX 3070 Ti); the manifests carry
  oracle-vs-emitted counts.
- **Clone ledger:** rows `OpenGL-Registry`, `EGL-Registry` in
  `E:\repos\CLEANUP.md` (bindings; review after 2026-12-01).
- **License:** registry-derived material Apache-2.0 (notice retained
  here); package code MIT OR Apache-2.0 (repo default).
