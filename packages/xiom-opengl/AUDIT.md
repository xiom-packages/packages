# AUDIT: xiom.opengl

## Status (2026-10-08)

Loader/probe implementation at 0.2.0. The pre-pilot static-extern wrapper set
(`glCreateShader` etc. as `extern "C"`) could not link -- those functions are
not exported by `opengl32.dll`; it was replaced by the runtime probe and is
preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | v0.64.1 |
| Pin | soname `opengl32.dll` + symbol set + PFD layout + core-context attribs (`SPEC.md` §2) |
| Link model | none for OpenGL; the bridge (`src/gl_probe.c`) links only kernel32 and resolves everything via `LoadLibraryA`/`GetProcAddress` (plus `wglGetProcAddress` for context-scoped entry points) |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/gl_probe.c` (no `--link`) |
| FFI confinement | all `unsafe`/`extern` in the root module `xiom.opengl` (G5); the bridge is plain C with no XIOM unsafe |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 13/13 x2** via `scripts/port.ps1` on an NVIDIA RTX 3070 Ti (classic 4.6, 3.3 core, 404 extensions), plus deterministic SKIP-classification per run |

## Design notes

- 0.3.0 adds the core-profile probe (`opengl_probe_core`): a temporary
  classic context obtains `wglCreateContextAttribsARB`, the requested core
  context is created, and the negotiated version + extension count/head are
  reported; `opengl_has_extension` scans with `glGetStringi`.
- The pure-XIOM Win32/WGL context path was abandoned after it poisoned the
  binary on v0.64.0 (crash before first output; deterministic). Bounded repro
  + control: `docs/repro/bindings-pilot/win32-gl-unsafe/`; finding B-09 in
  `docs/BINDINGS-COMPILER-FINDINGS.md` (FIXED at v0.64.1 -- the bridge stays
  as the shipped workaround; re-evaluate at the next major touch).
- `opengl_probe_named` gives the suite a deterministic SKIP-branch test (bogus
  soname -> `OPENGL_LOAD_ABSENT`) independent of the host GPU.
- Driver strings are informational (reference sample in SPEC §2); the pin is
  the soname + symbol set + PFD/attribs layout.

## Known limitations

- Windows only (soname `opengl32.dll` hard-coded; POSIX/EGL is Phase 2).
- Probes are atomic (load -> context -> query -> unload); a session-based
  API that keeps a context alive so consumers can call modern GL entry
  points through resolved addresses is the next step (`ROADMAP.md`).
- Classic contexts request RGBA 32-bit color, 24-bit depth, 8-bit stencil,
  double-buffered; no attribute negotiation beyond the core version.
- The no-context SKIP path is code-reviewed and shares the classification
  mapping with the tested ABSENT branch, but was not force-tested locally.
