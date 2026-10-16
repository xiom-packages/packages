# PROVENANCE -- xiom.gles

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstreams (oracles):**
  - `KhronosGroup/OpenGL-Registry`, clone at `E:\repos\OpenGL-Registry`,
    pinned at commit **`6af574a14089ccfee87efe230ebcdd8742859813`**
    ("Merge pull request #685 ...", 2026-10-06) for the **GLES** surface
    (core and android-delta values/signatures): oracle file `xml/gl.xml`,
    SHA256
    `EC4FEE77D4BCCACE329C5B4530EFB1D34214BA5EC680B883ED63D88D16768382`
    (2,822,494 bytes).
  - `KhronosGroup/EGL-Registry`, clone at `E:\repos\EGL-Registry`, pinned
    at commit **`db3425b8246136faccb5e2782b5694960bd6edf1`**
    ("Transfer CoreAVI reservations to Lynx (#225)", 2026-09-21) for the
    **EGL** surface: oracle file `api/egl.xml`, SHA256
    `1664DAC6D8E10C4D276EA763CE45D7873BC1127A6DA1011600541A6D62D63A13`.
  - **NDK r27b** (`27.1.12297006` on the shared Android SDK at
    `C:\Android\sdk\ndk\`; `XIOM_ANDROID_NDK` overrides the root) sysroot
    `usr/include` for the **android-delta name set** and the EGL delta
    measurement -- per-touch header groups:
    - `GLES2/gl2.h`, `GLES2/gl2ext.h` -- Khronos MIT-style license
      ("Copyright (c) The Khronos Group Inc.", notice in-file);
    - `GLES3/gl3.h`, `GLES3/gl31.h`, `GLES3/gl32.h`, `GLES3/gl3ext.h` --
      Khronos MIT-style license;
    - `KHR/khrplatform.h` -- Khronos MIT-style license;
    - `EGL/egl.h`, `EGL/eglext.h` (measurement only) -- Khronos
      MIT-style license.
    Excluded per SPEC sec. 2: `GLES/gl.h`, `GLES/glext.h` (ES1).  No NDK
    or Khronos source code is vendored; only derived constant values and
    mechanically typed declarations (Apache-2.0 registry rows above;
    Khronos header notices retained here).
- **Runtime targets:** Windows ANGLE (`libEGL.dll` + `libGLESv2.dll`,
  fallback `EGL.dll` + `GLESv2.dll`) and the Android platform libraries
  (`libEGL.so` + `libGLESv2.so`/`libGLESv3.so`/`libGLESv1_CM.so`),
  resolved at runtime; **not vendored** and no ANGLE/NDK source is
  copied.  The consumers provide the Windows pair on the DLL search path;
  Android uses the system libraries.  Absent -> SKIP.
- **Target surface:**
  - GLES core: union of `<feature api="gles2">` requires up to
    `GL_ES_VERSION_3_2` (verbatim registry signatures).
  - GLES android delta: names declared by the NDK r27b `GLES2/GLES3/KHR`
    headers beyond the core surface, clamped to the pinned registry for
    values/signatures.
  - EGL: `EGL_VERSION_1_0..1_5` + every declared extension command
    (includes the full `EGL_ANDROID_*` family; measured complete over
    the NDK r27b EGL headers).
- **Generated surface** (0.2.0):
  - `src/gles_cmds_01..04.xi` -- 358 GLES core command wrappers;
  - `src/gles_consts_1..5.xi` -- 1001 GLES core enum values;
  - `src/gles_android_cmds_01..05.xi` -- 494 android-delta wrappers;
  - `src/gles_android_consts_1..5.xi` -- 1225 android-delta enum values;
  - `src/gles_names.xi` -- `gles_cmd_names()` + `GLES_CMD_COUNT`,
    `gles_android_cmd_names()` + `GLES_ANDROID_*`, `gles_load_candidates()`;
  - `src/gles_api.xi` -- `GlesApi` + `gles_api_resolve`;
  - `src/egl_cmds_01..02.xi` -- 158 EGL command wrappers (incl. all
    extension commands);
  - `src/egl_consts_1..3.xi` -- 694 EGL enum values;
  - `src/egl_names.xi` -- `egl_cmd_names()` 158 / `egl_core_names()` 44 /
    `egl_load_candidates()`;
  - `src/egl_api.xi` -- `EglApi` + `egl_api_resolve`.
  - Generators: `tools/gen_gles.py`, `tools/gen_egl.py` (Python stdlib
    only, deterministic, stale-file-safe; manifests
    `docs/gen_gles_manifest.json`, `docs/gen_egl_manifest.json` with the
    oracle==emitted ledger, skip reasons, runtime-load candidates and
    the android-delta measurement; `gen_egl.py` fails loudly if a future
    pin declares undeclared EGL delta).
- **Loader path:** `src/gles_probe.c` (our code): runtime
  `LoadLibraryA`/`dlopen` over the candidate pairs (Windows ANGLE DLLs
  retained + Android system sonames; `xgs_pairs` mirrors the generated
  `*_load_candidates()` lists) + `eglGetProcAddress`, then the runtime
  export tables; `xgs_session_open` keeps an ES context current on a
  64x64 pbuffer.  No link-time dependency; absent pairs -> SKIP.
- **Derived vs independent:** declarations/constants are **derived**
  (mechanical extracts of the Khronos registries + the NDK header name
  sets); the C bridge, the probe driver and all XIOM code are original
  to this package.
- **Coverage proof:** `tests/test_conformance.xi` -- live-session
  resolution check 358/358 GLES core commands + 44/44 EGL core commands
  (`unresolved=0`), android-delta counts + candidates + spot values,
  221/494 delta commands resolved on ANGLE 2.1 (extension-conditional;
  2026-10-16, v0.64.5), oracle counts, wrapper-level
  `glGetString`/`eglQueryString`, buffer roundtrip; on-device repro
  `docs/repro/` (NDK r27b cross-build + API-36 emulator run,
  `recorded-gles-android.txt`).
- **Clone ledger:** rows `OpenGL-Registry`, `EGL-Registry` in
  `E:\repos\CLEANUP.md` (bindings; review after 2026-12-01); the NDK
  oracle is the shared read-only SDK at `C:\Android\sdk\ndk\27.1.12297006`
  (no clone row; pinned by directory version).
- **License:** registry-derived material Apache-2.0 (notice retained
  here); NDK/Khronos header-derived names/values under the Khronos
  MIT-style header licenses (notices retained here); package code MIT OR
  Apache-2.0 (repo default).
