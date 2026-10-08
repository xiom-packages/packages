# xiom.opengl

OpenGL **loader/probe** bindings for XIOM. The package resolves
`opengl32.dll` (plus `user32`/`gdi32`) at runtime through a tiny vendored C
bridge and reports a staged capability probe:

1. **symbols** -- expected exports resolved (`glGetString`, `wglCreateContext`, ...)
2. **contextless** -- `glGetString(GL_VERSION)` with no current context is
   safe and returns NULL (expected)
3. **context** -- a 1x1 window + WGL context yields VENDOR / RENDERER /
   VERSION / GLSL, then full cleanup

Missing runtime -> **SKIP**; no display/context -> **SKIP**; present but
broken exports -> **FAIL**. CI stays green without a GPU.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.0):
> 8/8 on an NVIDIA RTX 3070 Ti (GL 4.6), plus a deterministic SKIP-path test.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.opengl;

fn main() {
  let p = opengl_probe();
  if !p.is_ok {
    // OPENGL_LOAD_ABSENT / OPENGL_LOAD_NO_CONTEXT -> skip cleanly
    io.println("OpenGL unavailable: " + p.error.message);
    opengl_unload();
    return;
  }
  let info: GlInfo = p.value;
  io.println(info.vendor + " | " + info.renderer + " | " + info.version);
  opengl_unload();
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `opengl_probe`, `opengl_probe_named(soname)`, `opengl_unload` |
| Types | `GlInfo` (vendor/renderer/version/glsl/contextless_len), `GlProbeError` (kind/message) |
| Kinds | `OPENGL_LOAD_ABSENT`, `OPENGL_LOAD_NO_CONTEXT`, `OPENGL_LOAD_ABI` |
| Constants | `GL_VENDOR/RENDERER/VERSION/EXTENSIONS/SHADING_LANGUAGE_VERSION`, `PFD_*`, `OPENGL_GL_SONAME` |

`opengl_probe_named` accepts any library name -- a bogus name exercises the
SKIP classification deterministically, which is how the suite proves the
no-GPU path on a GPU host.

## Build note

The probe bridge is compiled by the runner hook
(`port.args.json`: `--c-source ${PACKAGE_DIR}/src/gl_probe.c`). Direct runs:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\gl_probe.c
```

## Tests

```
scripts/port.ps1 -Package xiom.opengl
```

Expected: 8 `[PASS]`, exit 0, on a desktop session. See `SPEC.md` §4 for the
recorded matrix and `SPEC.md` §2 for the G2 pin.
