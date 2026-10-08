# SPEC: xiom.opengl -- OpenGL loader/probe bindings

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.opengl` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | OpenGL (Khronos API); Windows implementation `opengl32.dll` |
| Upstream license | none vendored -- the API is a specification; the bridge is our code |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (system component `opengl32.dll`; soname hard-coded for now) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: soname + symbol set + PFD layout

**Soname:** `opengl32.dll` (Windows system component; always present). The
probe resolves it at **runtime** via `LoadLibraryA`/`GetProcAddress` inside the
vendored bridge -- there is no link-time dependency on OpenGL.

**Resolved symbol set** (the ABI registry this package actually depends on):

| Library (runtime-loaded) | Symbols |
|--------------------------|---------|
| `opengl32.dll` | `glGetString`, `wglGetProcAddress`, `wglCreateContext`, `wglMakeCurrent`, `wglDeleteContext` |
| `user32.dll` | `CreateWindowExA`, `DestroyWindow`, `GetDC`, `ReleaseDC` |
| `gdi32.dll` | `ChoosePixelFormat`, `SetPixelFormat` |
| via `wglGetProcAddress` (context-scoped) | `wglCreateContextAttribsARB`, `glGetIntegerv`, `glGetStringi` |

**Core-context attribs pinned** (used by `xgl_query_core`):
`WGL_CONTEXT_MAJOR_VERSION_ARB=0x2091`, `MINOR=0x2092`, `FLAGS=0x2094`,
`PROFILE_MASK=0x9126`, `CORE_PROFILE_BIT_ARB=0x1`; GL queries
`GL_MAJOR_VERSION=0x821B`, `GL_MINOR_VERSION=0x821C`,
`GL_NUM_EXTENSIONS=0x821D`, `GL_EXTENSIONS=0x1F03`.

**PIXELFORMATDESCRIPTOR layout:** 40 bytes; `nVersion=1`;
`dwFlags = PFD_DRAW_TO_WINDOW(0x4) | PFD_SUPPORT_OPENGL(0x20) |
PFD_DOUBLEBUFFER(0x1)` = 0x25; `iPixelType = PFD_TYPE_RGBA(0)`;
`cColorBits=32`, `cDepthBits=24`, `cStencilBits=8`;
`iLayerType = PFD_MAIN_PLANE(0)`.

**GL enums pinned:** `GL_VENDOR=0x1F00`, `GL_RENDERER=0x1F01`,
`GL_VERSION=0x1F02`, `GL_EXTENSIONS=0x1F03`,
`GL_SHADING_LANGUAGE_VERSION=0x8B8C`.

**Local runtime sample (reference, NOT the pin -- driver-dependent):**

| Artifact | Value |
|----------|-------|
| `C:\Windows\System32\opengl32.dll` | 983,040 bytes, FileVersion 10.0.26100.9278, SHA256 `659BE03CF2B88B5063A35B2637D9EF38122D7F6F30DAFFF118FA41B273AA5ECE` |
| GL_VENDOR | `NVIDIA Corporation` |
| GL_RENDERER | `NVIDIA GeForce RTX 3070 Ti/PCIe/SSE2` |
| GL_VERSION | `4.6.0 NVIDIA 616.92` |
| GLSL | `4.60 NVIDIA` |
| Contextless probe | `glGetString(VERSION)` = NULL before `wglMakeCurrent` (expected) |

### Re-pin procedure

1. On a target Windows host, re-run `scripts/port.ps1 -Package xiom.opengl`
   and compare the reported strings + the bridge's symbol set with this SPEC.
2. If a symbol changed (new function used), update the table and the bridge in
   the same commit; the bridge fails closed (`OPENGL_LOAD_ABI`) when an
   expected export is missing.
3. Record the new `opengl32.dll` hash/FileVersion as the reference sample.
   The pin itself is the soname + symbol set + PFD layout (driver strings are
   informational).

## 3. Design: vendored C bridge + staged probe

- `src/gl_probe.c` (our code, MIT/Apache) resolves all libraries at runtime,
  performs the staged probes, and exposes the flat `extern "C"` contract.
  It links nothing but kernel32 (`LoadLibraryA`/`GetProcAddress`).
- The XIOM module (`opengl.xi`, module `xiom.opengl`) is a thin safe wrapper:
  all `unsafe`/`extern` in this package are confined to this single module
  (G5). Public API: `opengl_probe`, `opengl_probe_named`,
  `opengl_probe_core`, `opengl_probe_core_named`, `opengl_has_extension`,
  `opengl_has_extension_named`, `opengl_unload`, `GlInfo`, `GlCoreInfo`,
  `GlProbeError`, constants.
- **Why a C bridge** (not pure-XIOM Win32): a pure-XIOM version of the
  context path poisoned the binary on v0.64.0 (crash before first output,
  deterministic) -- see finding B-09 in
  `docs/BINDINGS-COMPILER-FINDINGS.md` and the runnable repro in
  `docs/repro/bindings-pilot/win32-gl-unsafe/`. The isolated sub-parts were
  green, so the bridge keeps the XIOM side to one-line wrappers.
- **Build:** `port.args.json` compiles the bridge: `--c-source
  ${PACKAGE_DIR}/src/gl_probe.c` (no `--link` flags needed). The packages
  runner hook resolves `${PACKAGE_DIR}` and the 240 s watchdog covers the
  tiny C compile.
- **Classification** (the suite maps it to markers):
  - `OPENGL_LOAD_ABSENT` -> SKIP (library missing; CI stays green)
  - `OPENGL_LOAD_NO_CONTEXT` -> SKIP (no display/pixel format/context)
  - `OPENGL_LOAD_ABI` -> FAIL (present but exports missing; never silent)
- **Phase 2 (0.3.0): core-profile probe + extension loading.**
  `opengl_probe_core(major, minor)` obtains `wglCreateContextAttribsARB`
  through a temporary classic context and creates the requested core-profile
  context, then reports the negotiated version, the extension count and the
  first extension names; `opengl_has_extension(name)` scans the extension
  list with `glGetStringi` (exact match). Both are atomic
  (load -> context -> query -> unload) like the classic probe.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Full (NVIDIA RTX 3070 Ti) | `scripts/port.ps1 -Package xiom.opengl` | **PASS 13/13 x2** -- constants, SKIP classification (bogus soname -> ABSENT), classic context strings, contextless NULL, 3.3 core negotiation, extension count (404) + head, bogus extension absent, well-known extension (driver-dependent), unload |
| SKIP classification | deterministic on every host via `opengl_probe_named("xiom-absent-gl-probe-xyz.dll")` | **PASS** in both recorded runs |
| No-context SKIP path | code-reviewed; force-testing requires breaking window creation (covered by the same kind mapping as the ABSENT branch) | not exercised locally |

The bridge exposes a deterministic SKIP-branch test on any host (bogus
soname), so CI without a GPU still exercises the classification logic.

## 5. Scope

0.3.0 covers capability probing: symbol resolution, contextless safety, one
classic context with VENDOR/RENDERER/VERSION/GLSL, and a core-profile probe
(version negotiation + extension count/scan). A **session-based function
table** (keeping a context alive so consumers can call modern GL entry
points through resolved addresses) is the next step, along with the
`opengl32sw.dll` fallback and the POSIX/EGL path (`ROADMAP.md`). The old
static-extern wrapper set (pre-0.2.0 `opengl.xi`) could not link
(`glCreateShader` etc. are not exported by `opengl32.dll`) and is preserved
in git history only as reference.
