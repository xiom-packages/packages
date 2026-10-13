# AUDIT: xiom.gles

## Status (2026-10-13)

**0.1.0**: full generated GLES 2.0->3.2 core surface (358 commands + 1001
enums from the pinned Khronos `gl.xml`, `api="gles2"`) plus the full EGL
1.0->1.5 + extension surface (158 commands + 694 enums from the pinned
`EGL-Registry` `egl.xml`), driven by the live session
(`gles_session_open` + `src/gles_api.xi` / `src/egl_api.xi`); suite
**18/18** on v0.64.4 with ANGLE 2.1 (VS Code payload, D3D11 backend on an
NVIDIA RTX 3070 Ti): 358/358 GLES core commands resolved, 44/44 EGL core
commands resolved, buffer roundtrip, wrapper-level
`glGetString`/`eglQueryString`.

| Item | State |
|------|-------|
| Compiler | v0.64.4 |
| Pin | sonames + symbol set + session attribs (`SPEC.md` sec. 2); oracles: OpenGL-Registry `6af574a1` (`gl.xml`), EGL-Registry `db3425b8` (`egl.xml`) |
| Link model | none; the bridge (`src/gles_probe.c`) links only kernel32 and resolves everything via `LoadLibraryA`/`GetProcAddress` + `eglGetProcAddress` |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/gles_probe.c` (no `--link`) |
| FFI confinement | hand-written `unsafe`/`extern` in the root module `xiom.gles` (G5); the generated wrapper modules (`src/gles_cmds_*.xi`, `src/egl_cmds_*.xi`) carry only the mechanical resolve + cast call; the bridge is plain C |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 18/18** via `scripts/port.ps1` with the ANGLE pair on `PATH` (EGL 1.5, ES 3.0, 358/358+44/44 resolved, buffer roundtrip), plus deterministic SKIP-classification |

## Design notes

- The probe uses a 64x64 **pbuffer** surface: no window system dependency,
  so the classification + live stages work on headless CI hosts that have
  ANGLE on the search path.
- `gles_probe_named` gives the suite a deterministic SKIP-branch test
  (bogus pair -> `GLES_LOAD_ABSENT`) independent of the host runtime.
- Resolution success means the entry point exists; version-gated ES
  commands must only be called when the reported context version supports
  them (ANGLE resolves the full ES3.2 name set in an ES3.0 context).
- EGL extension commands are emitted for the full oracle (they resolve
  only when the implementation advertises them; 0 otherwise -- never
  silent).
- The upstream registries are the declaration oracle; ANGLE is only the
  runtime target (no ANGLE source is vendored or copied).

## Known limitations

- Windows x64 first (`libEGL.dll`/`libGLESv2.dll`); POSIX sonames are
  Phase 2.
- ANGLE is not vendored: the live path requires a consumer-provided pair
  on the DLL search path; absent -> SKIP (documented in SPEC sec. 2).
- GLES 1.x is not wrapped (obsolete).
- Window-system (non-pbuffer) surfaces and extension-availability helpers
  are follow-ons (`ROADMAP.md`).
- The no-context SKIP path is code-reviewed and shares the kind mapping
  with the tested ABSENT branch, but was not force-tested locally.
