# AUDIT: xiom.opengl

## Status (2026-10-08)

Loader/probe implementation at 0.2.0. The pre-pilot static-extern wrapper set
(`glCreateShader` etc. as `extern "C"`) could not link -- those functions are
not exported by `opengl32.dll`; it was replaced by the runtime probe and is
preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.0 |
| Pin | soname `opengl32.dll` + symbol set + PFD layout (`SPEC.md` §2) |
| Link model | none for OpenGL; the bridge (`src/gl_probe.c`) links only kernel32 and resolves everything via `LoadLibraryA`/`GetProcAddress` |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/gl_probe.c` (no `--link`) |
| FFI confinement | all `unsafe`/`extern` in the root module `xiom.opengl` (G5); the bridge is plain C with no XIOM unsafe |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 8/8 x2** via `scripts/port.ps1` on an NVIDIA RTX 3070 Ti (GL 4.6.0), plus deterministic SKIP-classification per run |

## Design notes

- The pure-XIOM Win32/WGL context path was abandoned after it poisoned the
  binary on v0.64.0 (crash before first output; deterministic). Bounded repro
  + control: `docs/repro/bindings-pilot/win32-gl-unsafe/`; finding B-09 in
  `docs/BINDINGS-COMPILER-FINDINGS.md`.
- `opengl_probe_named` gives the suite a deterministic SKIP-branch test (bogus
  soname -> `OPENGL_LOAD_ABSENT`) independent of the host GPU.
- Driver strings are informational (reference sample in SPEC §2); the pin is
  the soname + symbol set + PFD layout.

## Known limitations

- Windows only (soname `opengl32.dll` hard-coded; POSIX/EGL is Phase 2).
- Detail settings are implicit (RGBA 32-bit color, 24-bit depth, 8-bit
  stencil, double-buffered); no attributes/version negotiation yet.
- Extension loading (`wglGetProcAddress`) and the modern GL function table
  are Phase 2 -- this package currently proves the loader path and reports
  capabilities only.
- The no-context SKIP path is code-reviewed and shares the classification
  mapping with the tested ABSENT branch, but was not force-tested locally.
