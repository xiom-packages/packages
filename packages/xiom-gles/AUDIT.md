# AUDIT: xiom.gles

## Status (2026-10-16)

**0.2.0** (A9 graphics-gl android leg): the runtime loader walks the
generated candidate pairs -- Windows ANGLE DLLs retained, Android system
sonames added (`libEGL.so` + `libGLESv2.so`/`libGLESv3.so`/
`libGLESv1_CM.so`); the bridge is cross-platform (`LoadLibraryA` on
Windows, `dlopen` elsewhere).  Generated surface additions: the **NDK
r27b android delta** (494 extension command wrappers + 1225 enum values
from `GLES2/GLES3/KHR`; ES1 + guards excluded, documented) and the
**measured-complete** EGL android family (delta 0 over `EGL/egl.h` +
`EGL/eglext.h`; `gen_egl.py` fails loudly on drift).  Suite **20/20 x2**
on v0.64.5 with ANGLE 2.1 (FULL leg: 358/358 GLES core + 44/44 EGL core
resolved; 221/494 android-delta commands resolve on ANGLE,
extension-conditional) plus the deterministic SKIP classification.  On-device (x86_64-linux-android26, API-36 emulator, SwiftShader): bridge
loads `libEGL.so+libGLESv2.so`, display + strings live, 16
`eglQueryString` extensions (7 `EGL_ANDROID_*`), ES2 context + real
`glClear` -- recorded in `docs/repro/recorded-gles-android.txt`.

**0.1.0** (2026-10-13): full generated GLES 2.0->3.2 core surface (358
commands + 1001 enums from the pinned Khronos `gl.xml`, `api="gles2"`)
plus the full EGL 1.0->1.5 + extension surface (158 commands + 694 enums
from the pinned `EGL-Registry` `egl.xml`), driven by the live session;
suite **18/18** on v0.64.4 with ANGLE 2.1.

| Item | State |
|------|-------|
| Compiler | v0.64.5 |
| Pin | sonames + symbol set + session attribs (`SPEC.md` sec. 2); oracles: OpenGL-Registry `6af574a1` (`gl.xml`), EGL-Registry `db3425b8` (`egl.xml`), NDK r27b `27.1.12297006` (android delta) |
| Link model | none; the bridge (`src/gles_probe.c`) resolves everything via `LoadLibraryA`/`dlopen` + `GetProcAddress`/`dlsym` + `eglGetProcAddress` |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/gles_probe.c` (no `--link`) |
| FFI confinement | hand-written `unsafe`/`extern` in the root module `xiom.gles` (G5); the generated wrapper modules (`src/*_cmds_*.xi`, `src/*_consts_*.xi`) carry only the mechanical resolve + cast call; the bridge is plain C |
| Suite | `tests/test_conformance.xi` (20 checks) |
| Runs | **PASS 20/20 x2** via `scripts/port.ps1` with ANGLE on `PATH`, plus deterministic SKIP-classification; on-device PASS via `docs/repro/build-and-run-android.ps1` |

## Design notes

- The probe uses a 64x64 **pbuffer** surface: no window system
  dependency, so the classification + live stages work on headless CI
  hosts.
- `gles_probe_named` gives the suite a deterministic SKIP-branch test
  (bogus pair -> `GLES_LOAD_ABSENT`) independent of the host runtime.
- Resolution success means the entry point exists; version-gated ES
  commands and android-delta extension commands must only be *called*
  when the runtime reports support (the suite reports -- never gates --
  the live delta resolution count).
- EGL extension commands are emitted for the full oracle (they resolve
  only when the implementation advertises them; 0 otherwise -- never
  silent).
- The upstream registries + the NDK headers are the declaration oracle;
  ANGLE and the Android platform libraries are only runtime targets (no
  upstream source is vendored or copied).

## Known limitations

- ANGLE is not vendored: the Windows live path requires a
  consumer-provided pair on the DLL search path; absent -> SKIP
  (documented in SPEC sec. 2).
- GLES 1.x is a documented android-delta exclusion (the package binds
  ES 2.0+); `libGLESv1_CM.so` is probed as a classification-chain
  candidate only.
- The android delta clamps to the NDK r27b declared set (newer
  registry-only extensions are not part of the measured delta).
- Window-system (non-pbuffer) surfaces and extension-availability
  helpers are follow-ons (`ROADMAP.md`).
- The no-context SKIP path is code-reviewed and shares the kind mapping
  with the tested ABSENT branch, but was not force-tested locally.
