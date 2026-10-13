# xiom.gles

OpenGL ES **2.0 -> 3.2** + **EGL 1.5** bindings for XIOM, targeting
[ANGLE](https://chromium.googlesource.com/angle/angle/) at runtime. The
package resolves the `libEGL.dll` + `libGLESv2.dll` pair (fallback
`EGL.dll` + `GLESv2.dll`) through a tiny vendored C bridge and reports a
staged capability probe on a **pbuffer** surface (no window needed):

1. **symbols** -- libEGL exports + `glGetString` resolved
2. **context** -- default display -> initialize -> bind ES API -> choose
   config (pbuffer, RGBA8) -> ES3 context (ES2 fallback) -> strings

Missing pair -> **SKIP**; no display/context -> **SKIP**; present but
broken exports -> **FAIL**. CI stays green without ANGLE.

> **Status:** `incubating` -- **0.1.0 full GLES + EGL surface**: 18/18 on
> the pin (v0.64.4) with ANGLE 2.1 (VS Code payload) on an NVIDIA RTX
> 3070 Ti (D3D11 backend): 358/358 ES core commands resolved, 44/44 EGL
> core commands resolved (158 EGL wrappers incl. extensions), buffer
> roundtrip, wrapper-level `glGetString`/`eglQueryString`, deterministic
> SKIP-path test. **0.1.0 published in `eco-v0.1.171` (sha256
> `017b7664...`).**  **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.gles;

fn main() {
  let p = gles_probe();
  if !p.is_ok {
    // GLES_LOAD_ABSENT / GLES_LOAD_NO_CONTEXT -> skip cleanly
    io.println("ANGLE unavailable: " + p.error.message);
    gles_unload();
    return;
  }
  let info: GlesInfo = p.value;
  io.println(info.egl_version + " | " + info.gles_version + " | " + info.gles_renderer);
  gles_unload();
}
```

Runtime note: ANGLE is **not** vendored -- put a directory containing
`libEGL.dll` + `libGLESv2.dll` on the DLL search path for the live path
(an Electron app payload such as VS Code's versioned app dir works):

```powershell
$env:PATH = "<dir with libEGL.dll>;" + $env:PATH
scripts/port.ps1 -Package xiom.gles
```

## Full surface (0.1.0)

```xiom
use xiom.gles;
use xiom.gles.gles_api;
use xiom.gles.egl_api;
use xiom.gles.gles_cmds_01;   // ... gles_cmds_04; gles_consts_1..5 carry the enums
use xiom.gles.egl_cmds_01;    // ... egl_cmds_02; egl_consts_1..3 carry the enums

fn main() {
  let so = gles_session_open(3);      // ES3 context (falls back to ES2)
  if !so.is_ok { return; }
  let api = gles_api_new();
  let eapi = egl_api_new();
  // gl_buffer_data(&api, GL_ARRAY_BUFFER as UInt32, ...);
  // egl_query_string(&eapi, gles_session_display(), EGL_VERSION as Int32);
  gles_session_close();
}
```

The generated wrappers resolve each entry point per call through
`eglGetProcAddress` (then the libGLESv2/libEGL exports) against the
session context. Oracle counts: GLES 358 commands + 1001 enums
(`xiom.gles.gles_cmds_01..04`, `xiom.gles.gles_consts_1..5`); EGL 158
commands (44 core + 114 extension) + 694 enums
(`xiom.gles.egl_cmds_01..02`, `xiom.gles.egl_consts_1..3`). Name tables:
`xiom.gles.gles_names`, `xiom.gles.egl_names`. See `docs/COVERAGE.md`,
`SPEC.md`, `PROVENANCE.md`.

## API

| Area | Functions |
|------|-----------|
| Probe | `gles_probe`, `gles_probe_named(egl_soname, gles_soname)`, `gles_unload` |
| Session | `gles_session_open(client_version)`, `gles_session_is_active`, `gles_session_display`, `gles_get_proc(name)`, `gles_egl_proc(name)`, `gles_session_close` |
| GLES surface | generated `gl_*` wrappers in `xiom.gles.gles_cmds_01..04` (358 ES2->3.2 commands); enums in `xiom.gles.gles_consts_1..5`; name table `xiom.gles.gles_names` |
| EGL surface | generated `egl_*` wrappers in `xiom.gles.egl_cmds_01..02` (158 commands); enums in `xiom.gles.egl_consts_1..3`; name tables `xiom.gles.egl_names` |
| Types | `GlesInfo` (EGL/GL strings), `GlesSession` (client_version), `GlesProbeError` (kind/message) |
| Kinds | `GLES_LOAD_ABSENT`, `GLES_LOAD_NO_CONTEXT`, `GLES_LOAD_ABI` |
| Constants | `GLES_EGL_SONAME`, `GLES_SONAME`, `GLES_SESSION_CLIENT_VERSION` |

`gles_probe_named` accepts any soname pair -- a bogus pair exercises the
SKIP classification deterministically, which is how the suite proves the
no-ANGLE path on a host that has ANGLE.

## Build note

The bridge is compiled by the runner hook (`port.args.json`:
`--c-source ${PACKAGE_DIR}/src/gles_probe.c`). Direct runs:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\gles_probe.c
```

## Tests

```
scripts/port.ps1 -Package xiom.gles
```

Expected: 18 `[PASS]`, exit 0, with ANGLE on the DLL search path
(EGL 1.5 + ES context, 358/358 GLES + 44/44 EGL core commands resolved;
buffer roundtrip); without ANGLE the live stage collapses to SKIP.
See `SPEC.md` sec. 4 for the recorded matrix and sec. 2 for the pin.
