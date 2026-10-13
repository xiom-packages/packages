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

> **Status:** `incubating` -- **0.5.0 full core + WGL surface**: 28/28 x2 on
> the pin (v0.64.4) on an NVIDIA RTX 3070 Ti: 656/656 generated core-4.6
> commands resolved under a live session (unresolved=0), the full WGL surface
> (146 commands / 298 enums; 24/24 resolvable core-1.0 commands resolved,
> extensions string, swap-interval roundtrip, `wglChoosePixelFormatARB`),
> buffer + shader roundtrips, plus the classic/core probes (4.6 classic +
> 3.3 core, 404 extensions) and the deterministic SKIP-path test.
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

## Full surface (0.4.0)

```xiom
use xiom.opengl;
use xiom.opengl.glapi;
use xiom.opengl.cmds_01;   // ... cmds_07; consts_1..6 carry the enums

fn main() {
  let so = opengl_session_open(4, 6);
  if !so.is_ok { /* ABSENT/NO_CONTEXT -> skip cleanly */ return; }
  let api = gl_api_new();
  // let err = gl_get_error(&api);
  // vao/buffer/shader calls: gl_gen_vertex_arrays, gl_buffer_data, ...
  opengl_session_close();
}
```

The generated wrappers resolve every command per call through
`wglGetProcAddress` (then the `opengl32` exports) against the session
context. Enums live in `xiom.opengl.consts_1..6` (`pub const GL_*: Int`);
the command name table is `xiom.opengl.names` (`gl_cmd_names()`,
`GL_CMD_COUNT`). Target + counts: `docs/COVERAGE.md`, `PROVENANCE.md`.

## WGL surface (0.5.0)

```xiom
use xiom.opengl;
use xiom.opengl.glapi;
use xiom.opengl.wgl_cmds_01;   // ... wgl_cmds_02
use xiom.opengl.wgl_consts_1;  // ... wgl_consts_2

fn main() {
  let so = opengl_session_open(4, 6);
  if !so.is_ok { return; }
  let api = gl_api_new();
  let dc = opengl_session_dc();
  // wgl_create_context_attribs_arb(&api, dc, 0, attribs.as_mut_ptr());
  // let _ = wgl_swap_interval_ext(&api, 1);
  opengl_session_close();
}
```

Every command in the pinned `wgl.xml` (WGL_VERSION_1_0 + all 57 WGL
extensions -> 146 wrappers `wgl_<name>`) resolves through the session
(`wglGetProcAddress` -> `opengl32` -> `gdi32` exports); enums live in
`xiom.opengl.wgl_consts_1..2`, name tables in `xiom.opengl.wgl_names`.
WGL functions are context-scoped: call them while a session is open, with
`opengl_session_dc()`/`opengl_session_hglrc()` supplying the handles
(`Int`).

## API

| Area | Functions |
|------|-----------|
| Probe | `opengl_probe`, `opengl_probe_named(soname)`, `opengl_unload` |
| Session (0.4.0) | `opengl_session_open(major, minor)`, `opengl_session_is_active`, `opengl_session_dc`, `opengl_session_hglrc`, `opengl_get_proc(name)`, `opengl_session_close` |
| Surface (0.4.0) | generated `gl_*` wrappers in `xiom.opengl.cmds_01..07` (656 core-4.6 commands); enums in `xiom.opengl.consts_1..6`; name table `xiom.opengl.names` |
| WGL (0.5.0) | generated `wgl_*` wrappers in `xiom.opengl.wgl_cmds_01..02` (146 commands from wgl.xml); enums in `xiom.opengl.wgl_consts_1..2` (298); names in `xiom.opengl.wgl_names` |
| Core probe | `opengl_probe_core(major, minor)`, `opengl_probe_core_named(soname, major, minor)` |
| Extensions | `opengl_has_extension(name)`, `opengl_has_extension_named(soname, name)` |
| Types | `GlInfo` (vendor/renderer/version/glsl/contextless_len), `GlCoreInfo` (strings + major/minor/extension_count/extension_head), `GlProbeError` (kind/message) |
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

Expected: 28 `[PASS]`, exit 0, on a desktop session (classic 4.6 + 3.3 core
probe with 404 extensions; 656/656 core commands resolved; 24/24 resolvable
core-1.0 WGL commands + the WGL surface checks; buffer + shader
roundtrips). See `SPEC.md` §4 for the
recorded matrix and `SPEC.md` §2 for the G2 pin.
