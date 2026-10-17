# xiom.gles

OpenGL ES **2.0 -> 3.2** + **EGL 1.5** bindings for XIOM against a
**runtime-loaded implementation**: on Windows the [ANGLE](https://chromium.googlesource.com/angle/angle/)
pair (`libEGL.dll` + `libGLESv2.dll`, fallback `EGL.dll` + `GLESv2.dll`),
on Android the **system libraries** (`libEGL.so` with `libGLESv2.so`, then
`libGLESv3.so`, then `libGLESv1_CM.so`).  The candidate sonames are
**generated** (`egl_names.egl_load_candidates()`,
`gles_names.gles_load_candidates()`) and probed in order by the vendored C
bridge; a staged capability probe runs on a **pbuffer** surface (no window
needed):

1. **symbols** -- EGL exports + `glGetString` resolved
2. **context** -- default display -> initialize -> bind ES API -> choose
   config (pbuffer, RGBA8) -> ES3 context (ES2 fallback) -> strings

Missing libraries -> **SKIP**; no display/context -> **SKIP**; present but
broken exports -> **FAIL**.  CI stays green without a runtime.

> **Status:** `incubating` -- **0.2.0 android leg (A9 graphics-gl)**: the
> loader walks the Windows ANGLE + Android system soname candidates (one
> bridge, both platforms), and the generated surface gains the **NDK r27b
> android delta** -- every GLES2/GLES3/KHR extension the NDK declares
> beyond the ES 2.0->3.2 core: **494 extension commands + 1225 constant
> values** (`gles_android_cmds_01..05`, `gles_android_consts_1..5`).  The
> **EGL android family** (`EGL_ANDROID_*` entry points + constants,
> incl. `eglGetFrameTimestampsANDROID`/`eglDupNativeFenceFDANDROID`/
> `eglPresentationTimeANDROID`...) was **measured complete** over the NDK
> r27b EGL headers (delta 0; documented exclusions in `SPEC.md`/`docs/
> COVERAGE.md`).  Suite **20/20 x2** on v0.64.5 with ANGLE 2.1 (D3D11,
> RTX 3070 Ti; **221/494** delta commands resolved on the live runtime,
> extension-conditional) + deterministic SKIP path.  On-device
> (x86_64-linux-android26, API-36 emulator, SwiftShader): bridge
> `libEGL.so+libGLESv2.so` load, EGL display + `GL_VERSION`/
> `GL_RENDERER` strings, `eglQueryString(EGL_EXTENSIONS)` = 16 extensions
> (7 `EGL_ANDROID_*`), live **ES2 context** + real `glClear` -- recorded
> run in `docs/repro/recorded-gles-android.txt`.  **0.1.0** (ANGLE-only
> surface) was published in `eco-v0.1.171` (sha256 `017b7664...`); **0.2.0 in
> `eco-v0.1.190` (sha256 `40328c2a...`)**.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.gles;

fn main() {
  let p = gles_probe();
  if !p.is_ok {
    // GLES_LOAD_ABSENT / GLES_LOAD_NO_CONTEXT -> skip cleanly
    io.println("no EGL/GLES runtime: " + p.error.message);
    gles_unload();
    return;
  }
  let info: GlesInfo = p.value;
  io.println(info.egl_version + " | " + info.gles_version + " | " + info.gles_renderer);
  gles_unload();
}
```

Runtime note: the implementation is **not** vendored.  On Windows put a
directory containing `libEGL.dll` + `libGLESv2.dll` on the DLL search
path (an Electron app payload such as VS Code's versioned app dir works);
on Android the platform libraries are used directly:

```powershell
$env:PATH = "<dir with libEGL.dll>;" + $env:PATH
scripts/port.ps1 -Package xiom.gles
```

## Full surface (0.2.0)

```xiom
use xiom.gles;
use xiom.gles.gles_api;
use xiom.gles.egl_api;
use xiom.gles.gles_cmds_01;        // ... gles_cmds_04; gles_consts_1..5 carry the core enums
use xiom.gles.gles_android_cmds_01; // ... gles_android_cmds_05 (NDK r27b delta wrappers)
use xiom.gles.gles_android_consts_1; // ... gles_android_consts_5 (delta enums)
use xiom.gles.egl_cmds_01;         // ... egl_cmds_02; egl_consts_1..3 carry the enums

fn main() {
  let so = gles_session_open(3);      // ES3 context (falls back to ES2)
  if !so.is_ok { return; }
  let api = gles_api_new();
  let eapi = egl_api_new();
  // gl_buffer_data(&api, GL_ARRAY_BUFFER as UInt32, ...);
  // gl_debug_message_callback_khr(&api, callback, user_param);  // android delta
  // egl_query_string(&eapi, gles_session_display(), EGL_VERSION as Int32);
  gles_session_close();
}
```

The generated wrappers resolve each entry point per call through
`eglGetProcAddress` (then the runtime export tables) against the session
context.  Oracle counts: GLES **358 core** commands + **1001** enums
(`xiom.gles.gles_cmds_01..04`, `gles_consts_1..5`); android delta **494**
commands + **1225** enums (`gles_android_cmds_01..05`,
`gles_android_consts_1..5`); EGL **158** commands (44 core + 114
extension, incl. every `EGL_ANDROID_*` entry point) + **694** enums
(`egl_cmds_01..02`, `egl_consts_1..3`).  Name tables + runtime-load
candidates: `xiom.gles.gles_names`, `xiom.gles.egl_names`.  See
`docs/COVERAGE.md`, `SPEC.md`, `PROVENANCE.md`.

## API

| Area | Functions |
|------|-----------|
| Probe | `gles_probe` (walks the candidate pairs), `gles_probe_named(egl_soname, gles_soname)`, `gles_unload` |
| Session | `gles_session_open(client_version)`, `gles_session_is_active`, `gles_session_display`, `gles_get_proc(name)`, `gles_egl_proc(name)`, `gles_session_close` |
| GLES surface | generated `gl_*` wrappers in `gles_cmds_01..04` (358 ES2->3.2 commands); enums in `gles_consts_1..5`; name table `gles_names` |
| GLES android delta | generated `gl_*` wrappers in `gles_android_cmds_01..05` (494 NDK r27b extension commands); enums in `gles_android_consts_1..5`; `gles_android_cmd_names()` |
| EGL surface | generated `egl_*` wrappers in `egl_cmds_01..02` (158 commands, incl. `EGL_ANDROID_*`); enums in `egl_consts_1..3`; name tables `egl_names` |
| Loader candidates | `gles_load_candidates()`, `egl_load_candidates()` (generated; Windows ANGLE DLLs + Android system sonames) |
| Types | `GlesInfo` (EGL/GL strings), `GlesSession` (client_version), `GlesProbeError` (kind/message) |
| Kinds | `GLES_LOAD_ABSENT`, `GLES_LOAD_NO_CONTEXT`, `GLES_LOAD_ABI` |
| Constants | `GLES_SESSION_CLIENT_VERSION` |

`gles_probe_named` accepts any soname pair -- a bogus pair exercises the
SKIP classification deterministically, which is how the suite proves the
no-runtime path on a host that has one.

## Build note

The bridge is compiled by the runner hook (`port.args.json`:
`--c-source ${PACKAGE_DIR}/src/gles_probe.c`).  Direct runs:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\gles_probe.c
```

## Tests

```
scripts/port.ps1 -Package xiom.gles
```

Expected: 20 `[PASS]`, exit 0, with a runtime on the search path (EGL +
ES context, 358/358 GLES + 44/44 EGL core commands resolved, android
delta count + spot values, buffer roundtrip; 221/494 delta commands
resolve on ANGLE 2.1 -- extension-conditional); without a runtime the
live stage collapses to SKIP.  See `SPEC.md` sec. 4 for the recorded
matrix and sec. 2 for the pin.

## On-device evidence (android leg)

`docs/repro/` carries the cross-build + emulator driver
(`build-and-run-android.ps1`: NDK r27b clang, aarch64 build-only bundle
check + x86_64 run on the `Medium_Phone_API_36.0` emulator) and the
recorded transcript `recorded-gles-android.txt` (loader pair
`libEGL.so+libGLESv2.so`; SwiftShader `GL_RENDERER`; 16
`eglQueryString` extensions incl. 7 `EGL_ANDROID_*`; live ES2 context;
`glClear` -> `glGetError == 0`).
