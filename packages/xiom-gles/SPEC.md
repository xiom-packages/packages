# SPEC: xiom.gles -- OpenGL ES 2.0/3.2 + EGL 1.5 bindings (Windows ANGLE / Android system libraries)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.gles` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Khronos OpenGL ES + EGL API registries; NDK r27b header oracle (android delta); runtime targets ANGLE (Windows) and the Android platform libraries |
| Upstream license | registries Apache-2.0; NDK/Khronos headers MIT-style (Khronos) -- derived declarations/consts only (notice in PROVENANCE.md) |
| Package license | MIT OR Apache-2.0 |
| Platforms | `windows-x64` (runtime-loaded ANGLE pair), `android-arm64`, `android-x86_64` (system libraries; runtime-load, SKIP when absent) |
| Compiler pin | v0.64.5 |

## 2. G2 pin: runtime-load candidates + symbol set + session attribs

**Runtime-load candidates (generated; single source of truth).**  The
bridge probes candidate **pairs** in order and keeps the first that loads
and exports the required symbols:

| Order | EGL side | GLES side | Leg |
|-------|----------|-----------|-----|
| 1 | `libEGL.dll` | `libGLESv2.dll` | Windows ANGLE (primary) |
| 2 | `EGL.dll` | `GLESv2.dll` | Windows ANGLE (fallback) |
| 3 | `libEGL.so` | `libGLESv2.so` | Android system GLES 2.0/3.x |
| 4 | `libEGL.so` | `libGLESv3.so` | Android alias (devices that publish it) |
| 5 | `libEGL.so` | `libGLESv1_CM.so` | Android legacy CM (last resort; classification only -- an ES2 context cannot be created from an ES1 library, which classifies as NO_CONTEXT/SKIP) |

The two name lists are emitted by the generators
(`egl_names.egl_load_candidates()`, `gles_names.gles_load_candidates()`)
and mirrored by the `xgs_pairs` table in `src/gles_probe.c`.  All are
resolved at **runtime** (`LoadLibraryA`/`GetProcAddress` on Windows,
`dlopen`/`dlsym` elsewhere, plus `eglGetProcAddress`); there is no
link-time dependency.  No candidate pair present -> SKIP.

**Resolved symbol set (the ABI registry this package actually depends on):**

| Library (runtime-loaded) | Symbols |
|--------------------------|---------|
| EGL side (required) | `eglGetDisplay`, `eglInitialize`, `eglQueryString`, `eglGetProcAddress` |
| EGL side (session path) | `eglTerminate`, `eglGetError`, `eglBindAPI`, `eglChooseConfig`, `eglCreatePbufferSurface`, `eglCreateContext`, `eglMakeCurrent`, `eglDestroySurface`, `eglDestroyContext` |
| GLES side (or via `eglGetProcAddress`) | `glGetString` (+ every generated wrapper entry point) |

**Session attribs pinned** (used by `xgs_query`/`xgs_session_open`):
default display; `eglBindAPI(EGL_OPENGL_ES_API=0x30A0)`; config
`SURFACE_TYPE=EGL_PBUFFER_BIT(0x1)`,
`RENDERABLE_TYPE=OPENGL_ES2_BIT(0x4)|OPENGL_ES3_BIT(0x40)`, RGBA8
(`R/G/B/A_SIZE=8`), `DEPTH_SIZE=0`, `STENCIL_SIZE=0`; pbuffer 64x64
(`EGL_WIDTH=0x3057`, `EGL_HEIGHT=0x3056`); context
`EGL_CONTEXT_CLIENT_VERSION=0x3098` = requested (3, falling back to 2).

**Local runtime sample (Windows reference, NOT the pin -- build-dependent):**

| Artifact | Value |
|----------|-------|
| `libEGL.dll` (VS Code payload `2a59476c9b`) | 488,808 bytes, ANGLE 2.1, SHA256 `488C51EA9D29765ED22551051B86120D39B1E9C71428987A8DEC2BE9BCA141A7` |
| `libGLESv2.dll` (same payload) | 8,078,648 bytes, ANGLE 2.1, SHA256 `882A6A411E4C098B96823144EEC7BC3D6A1E06EAE3FC5CD417BF726496610A7F` |
| EGL_VERSION (0.2.0 runs) | `1.5 (ANGLE 2.1.18912 git hash: 872d7947bb76)` |
| GL_VERSION | `OpenGL ES 3.0.0 (...)` |
| GL_RENDERER | `ANGLE (NVIDIA, NVIDIA GeForce RTX 3070 Ti Direct3D11 vs_5_0 ps_5_0, D3D11-32.0.16.1692)` |

**Device sample (android leg, API-36 emulator, x86_64):**

| Field | Value |
|-------|-------|
| Loaded pair | `libEGL.so` + `libGLESv2.so` (candidate 3) |
| EGL_VERSION | `1.4 Android META-EGL` (EGL_VENDOR `Android`) |
| GL_RENDERER | `Android Emulator OpenGL ES Translator (Google SwiftShader)` |
| GL_VERSION | `OpenGL ES 3.0 (OpenGL ES 3.0 SwiftShader 4.0.0.1)` |
| eglQueryString(EGL_EXTENSIONS) | 16 extensions (7 `EGL_ANDROID_*`; see `docs/repro/recorded-gles-android.txt`) |

**Oracle pins:**

| Surface | Oracle | SHA256 |
|---------|--------|--------|
| GLES 2.0 -> 3.2 core | `OpenGL-Registry` @ `6af574a1`, `xml/gl.xml` | `EC4FEE77D4BCCACE329C5B4530EFB1D34214BA5EC680B883ED63D88D16768382` |
| EGL 1.0 -> 1.5 + extensions | `EGL-Registry` @ `db3425b8`, `api/egl.xml` | `1664DAC6D8E10C4D276EA763CE45D7873BC1127A6DA1011600541A6D62D63A13` |
| android delta (name set) | NDK r27b `27.1.12297006` sysroot `usr/include` (`GLES2/`, `GLES3/`, `KHR/`, `EGL/`) | headers pinned by the NDK release; per-header ledger in `docs/gen_gles_manifest.json` / `docs/gen_egl_manifest.json` |
| android delta (values/signatures) | the pinned `gl.xml` / `egl.xml` above | same |

### Android delta -- definition and exclusions (0.2.0)

The android delta is the surface the NDK r27b headers declare **beyond
the generated Khronos-registry surface**, with these documented rules:

- **Declared (GLES)**: every constant and entry point in `GLES2/gl2.h`,
  `GLES2/gl2ext.h`, `GLES3/gl3.h`, `GLES3/gl31.h`, `GLES3/gl32.h`,
  `GLES3/gl3ext.h`, `KHR/khrplatform.h` that the core emission does not
  already carry -> **494 wrappers + 1225 constants** (emitted;
  `gles_android_cmds_*`, `gles_android_consts_*`).
- **Excluded (documented)**: the ES1 fixed-function surface
  (`GLES/gl.h`) and the ES1 extension pack (`GLES/glext.h`) -- the
  package binds ES 2.0+; `libGLESv1_CM.so` stays a loader candidate for
  the classification chain only.  Preprocessor guards/extension tokens
  (`#define GL_KHR_debug 1`, `GL_ES_VERSION_3_0`, `GL_GLES_PROTOTYPES`,
  ...) are not ABI constants (279 names).  `GL_APIENTRYP` (a typedef
  macro) is skipped with a manifest reason.
- **Declared (EGL)**: the NDK r27b `EGL/egl.h` + `EGL/eglext.h` surface
  was **measured** against the generated EGL surface: entry-point delta
  **0** (all 144 declared `egl*` prototypes are covered by the 158
  emitted wrappers, including every `EGL_ANDROID_*` entry point) and
  real-constant delta **0** (147 guards + `EGL_EGLEXT_VERSION`, a
  preprocessor version macro, excluded).  `tools/gen_egl.py` re-measures
  on every run and **fails loudly** if a future pin declares EGL surface
  that is not declared here.

## 3. Design: vendored C bridge + staged probe + generated surfaces

- `src/gles_probe.c` (our code, MIT/Apache) resolves the runtime at
  runtime (Windows: `LoadLibraryA`; Android/POSIX: `dlopen`) and performs
  the staged probe on a **pbuffer** surface (no window system
  dependency).  On Windows it links nothing but kernel32; on Android it
  needs only `libdl`.
- The XIOM module (`gles.xi`, module `xiom.gles`) is a thin safe wrapper:
  all hand-written `unsafe`/`extern` are confined to it.  Public API:
  `gles_probe`, `gles_probe_named`, `gles_session_open`,
  `gles_session_is_active`, `gles_session_display`, `gles_get_proc`,
  `gles_egl_proc`, `gles_session_close`, `gles_unload`, `GlesInfo`,
  `GlesSession`, `GlesProbeError`, kinds.
- **Generated surfaces** (same pattern as `xiom.opengl`):
  - GLES core: `src/gles_cmds_01..04.xi` (358 wrappers, modules
    `xiom.gles.gles_cmds_<grp>`), `src/gles_consts_1..5.xi` (1001 consts),
    `src/gles_names.xi` (`gles_cmd_names()`, `GLES_CMD_COUNT`,
    `gles_load_candidates()`).  Generator `tools/gen_gles.py` (oracle
    `gl.xml`, `api="gles2"`, <= 3.2).
  - GLES android delta: `src/gles_android_cmds_01..05.xi` (494 wrappers,
    modules `xiom.gles.gles_android_cmds_<grp>`),
    `src/gles_android_consts_1..5.xi` (1225 consts),
    `gles_android_cmd_names()`/`GLES_ANDROID_*` counts in
    `src/gles_names.xi`.  Same generator: name set from the NDK r27b
    headers, values/signatures verbatim from the pinned `gl.xml`.
  - EGL: `src/egl_cmds_01..02.xi` (158 wrappers incl. all extension
    commands), `src/egl_consts_1..3.xi` (694 consts), `src/egl_names.xi`
    (`egl_cmd_names()` 158 / `egl_core_names()` 44 /
    `egl_load_candidates()`); `src/egl_api.xi` (`EglApi` +
    `egl_api_resolve` calling `gles_egl_proc`).  Generator
    `tools/gen_egl.py` (oracle `EGL-Registry/api/egl.xml` + the NDK
    measurement above).
- **Resolution semantics:** success at resolve time means the entry point
  exists in the runtime; version-gated ES commands (and every android
  delta command) must only be *called* when the runtime reports support.
- **Classification** (the suite maps it to markers):
  - `GLES_LOAD_ABSENT` -> SKIP (no candidate pair found; CI stays green)
  - `GLES_LOAD_NO_CONTEXT` -> SKIP (no display/config/context)
  - `GLES_LOAD_ABI` -> FAIL (a pair loaded but exports are missing; never silent)

## 4. Test matrix (0.2.0, compiler v0.64.5)

| Configuration | Command | Result |
|---------------|---------|--------|
| Full (VS Code ANGLE 2.1 on RTX 3070 Ti, D3D11) | `scripts/port.ps1 -Package xiom.gles -TimeoutSec 300` | **PASS 20/20 x2** -- constants, android delta (candidates + 494 cmds + 1225 consts + EGL android family), SKIP classification (bogus pair), EGL_VERSION = 1.5 (ANGLE 2.1.18912), GL_VERSION = `OpenGL ES 3.0.0`, D3D11 renderer, GLSL ES 3.00, session (display live), **358/358 ES core commands resolved**, **44/44 EGL core commands resolved**, **221/494 android-delta extension commands resolved on ANGLE** (extension-conditional, informational), oracle counts (358 GLES + 158 EGL), bogus command -> 0, `glGetString` + `eglQueryString` wrappers live, `glGetIntegerv(GL_MAJOR_VERSION)` = 3, buffer roundtrip (size=64 err=0), session close, unload |
| SKIP classification | deterministic on every host via `gles_probe_named("xiom-absent-egl-xyz.dll", "xiom-absent-gles-xyz.dll")` | **PASS** |
| Android on-device | `packages/xiom-gles/docs/repro/build-and-run-android.ps1` (NDK r27b, x86_64-linux-android26) | **PASS** -- recorded transcript `docs/repro/recorded-gles-android.txt` (details sec. 2 device sample) |
| aarch64 cross-build | same script (build-only bundle check; no arm64 device) | **PASS** -- ELF64/AArch64 DYN |
| No-context SKIP path | code-reviewed; shares the kind mapping with the tested ABSENT branch | not exercised locally |
| Without a runtime on PATH | the live path collapses to the ABSENT/SKIP classification | documented |

## 5. Scope

0.2.0 ships the **full generated GLES 2.0->3.2 core surface** (358
command wrappers + 1001 enums), the **NDK r27b android delta** (494
extension command wrappers + 1225 enums) and the **full EGL surface**
(158 command wrappers incl. every declared extension command + 694
enums, `EGL_ANDROID_*` included), driven by the live session
(`gles_session_open` keeps an ES context current on a 64x64 pbuffer;
each wrapper resolves its entry point per call through
`eglGetProcAddress`, then the runtime export tables).

Not in scope: GLES 1.x (obsolete; its surface is a documented delta
exclusion), WGL-style window-system integration (ANGLE needs none for
pbuffers; window surfaces come with a consumer ask), a pinned ANGLE
binary (consumers provide it), GLES 3.2/Mesa-only extensions not
declared by the NDK r27b (the delta clamps to the NDK oracle).
