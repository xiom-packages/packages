# AUDIT: xiom.opengl

## Status (2026-10-13)

**0.5.0**: full generated core-profile 4.6 surface (656 commands + 1358
enums) **plus the full WGL surface** (146 commands + 298 enums from the
pinned `xml/wgl.xml`; `PROVENANCE.md` / `docs/COVERAGE.md`) driven by the
live-session resolver (`opengl_session_open` + `src/gl_api.xi`); suite
**28/28 x2** (656/656 core commands resolved, 24/24 resolvable WGL
core-1.0 commands, extensions string, swap-interval roundtrip,
`wglChoosePixelFormatARB`, buffer + shader roundtrips). Loader/probe
implementation at 0.2.0. The pre-pilot static-extern wrapper set
(`glCreateShader` etc. as `extern "C"`) could not link -- those functions are
not exported by `opengl32.dll`; it was replaced by the runtime probe and is
preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | v0.64.4 |
| Pin | soname `opengl32.dll` + symbol set + PFD layout + core-context attribs (`SPEC.md` sec. 2); WGL: `xml/wgl.xml` @ the same registry pin (SHA256 `6401072F...`) |
| Link model | none for OpenGL; the bridge (`src/gl_probe.c`) links only kernel32 and resolves everything via `LoadLibraryA`/`GetProcAddress` (plus `wglGetProcAddress` for context-scoped entry points) |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/gl_probe.c` (no `--link`) |
| FFI confinement | hand-written `unsafe`/`extern` in the root module `xiom.opengl` (G5); the generated wrapper modules (`src/cmds_*.xi`, `src/wgl_cmds_*.xi`) carry only the mechanical resolve + cast call; the bridge is plain C with no XIOM unsafe |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 28/28 x2** via `scripts/port.ps1` on an NVIDIA RTX 3070 Ti (classic 4.6, 3.3 core, 404 extensions, 656/656 core commands, 24/24 WGL core, WGL surface checks, buffer + shader roundtrips), plus deterministic SKIP-classification per run |

## Design notes

- 0.3.0 adds the core-profile probe (`opengl_probe_core`): a temporary
  classic context obtains `wglCreateContextAttribsARB`, the requested core
  context is created, and the negotiated version + extension count/head are
  reported; `opengl_has_extension` scans with `glGetStringi`.
- 0.4.0 adds the session path: `opengl_session_open` keeps a core context
  current; the generated `gl_*` wrappers resolve per call.
- 0.5.0 adds the WGL surface: `tools/gen_wgl.py` emits every `wgl.xml`
  command as a `wgl_*` wrapper resolved through the same session; the
  resolver gained the `gdi32` fallback (WGL 1.0 pixel-format exports);
  `opengl_session_dc`/`opengl_session_hglrc` expose the raw handles.
- The pure-XIOM Win32/WGL context path was abandoned after it poisoned the
  binary on v0.64.0 (crash before first output; deterministic). Bounded repro
  + control: `docs/repro/bindings-pilot/win32-gl-unsafe/`; finding B-09 in
  `docs/BINDINGS-COMPILER-FINDINGS.md` (FIXED at v0.64.1 -- the bridge stays
  as the shipped workaround; re-evaluate at the next major touch).
- `opengl_probe_named` gives the suite a deterministic SKIP-branch test (bogus
  soname -> `OPENGL_LOAD_ABSENT`) independent of the host GPU.
- Driver strings are informational (reference sample in SPEC sec. 2); the pin
  is the soname + symbol set + PFD/attribs layout.

## Known limitations

- Windows only (sonames `opengl32.dll` + `libEGL.dll`/`libGLESv2.dll` are
  Phase 2; the bridge is Win32-based).
- GL extension commands are not wrapped (driver-conditional); the extension
  scan reports the live list.  WGL extension wrappers exist for the full
  oracle, but each resolves only when the driver advertises the extension
  (0 at call time otherwise -- never silent).
- Probes remain atomic (load -> context -> query -> unload); the 0.4.0
  session path keeps a context current for the generated wrappers.
- Classic contexts request RGBA 32-bit color, 24-bit depth, 8-bit stencil,
  double-buffered; no attribute negotiation beyond the core version.
- The no-context SKIP path is code-reviewed and shares the classification
  mapping with the tested ABSENT branch, but was not force-tested locally.
