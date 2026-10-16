# COVERAGE -- xiom.gles (GLES 2.0->3.2 + android delta + EGL 1.0->1.5)

Oracles: `KhronosGroup/OpenGL-Registry` @ `6af574a1` for the GLES surface
(`xml/gl.xml`, SHA256 `EC4FEE77...`), `KhronosGroup/EGL-Registry` @
`db3425b8` for the EGL surface (`api/egl.xml`, SHA256 `1664DAC6...`), and
the **NDK r27b** sysroot headers (`27.1.12297006`) for the android delta
name set.  Generators: `tools/gen_gles.py` + `tools/gen_egl.py`
(deterministic, Python stdlib; they re-measure the delta on every run).
Runtime targets: ANGLE (Windows) / the Android system libraries.

| Set | Oracle | Emitted | Resolved (live) | Notes |
|-----|--------|---------|-----------------|-------|
| GLES core commands (2.0 -> 3.2) | 358 | 358 wrappers (`gles_cmds_01..04`) | **358/358** (`unresolved=0`) | loadability check in `tests/test_conformance.xi` |
| GLES core enums | 1001 | 1001 consts (`gles_consts_1..5`) | n/a | ES2+ES3 shares names with GL (separate modules) |
| **GLES android delta** (NDK r27b `GLES2/GLES3/KHR` beyond core) | 494 commands | 494 wrappers (`gles_android_cmds_01..05`) | **221/494** on ANGLE 2.1 (extension-conditional; reported, never gated) | name set from the NDK headers, signatures verbatim from the pinned `gl.xml`; ES1 headers excluded (documented in SPEC sec. 2) |
| GLES android delta enums | 1225 | 1225 consts (`gles_android_consts_1..5`) | n/a | 279 guard/token macros + `GL_APIENTRYP` typedef excluded (manifest reasons) |
| EGL commands (1.0->1.5 + all extensions) | 158 | 158 wrappers (`egl_cmds_01..02`) | core: **44/44** (`unresolved=0`); extension commands implementation-conditional | full oracle emitted; every `EGL_ANDROID_*` entry point carried |
| EGL enums | 694 | 694 consts (`egl_consts_1..3`) | n/a | `EGL_CAST` handle constants included; 29 `EGL_*_ANDROID` values covered |
| **EGL android delta** (NDK r27b `EGL/`) | 0 | (already carried by the sets above) | n/a | **measured complete**: 0 missing entry points, 0 missing real constants; 147 guards + `EGL_EGLEXT_VERSION` excluded; `gen_egl.py` fails loudly on drift |
| Runtime-load candidates | 3 + 5 | `egl_load_candidates()` / `gles_load_candidates()` | on-device: `libEGL.so+libGLESv2.so` loaded | Windows ANGLE DLLs retained; Android system sonames added |

Resolved = `xgs_get_proc` / `xgs_egl_proc` (`eglGetProcAddress` first,
then the runtime export tables) under a live ES session.

Live witness (2026-10-16, ANGLE 2.1.18912 D3D11 on an RTX 3070 Ti):

```
[PASS] egl: EGL_VERSION = 1.5 (ANGLE 2.1.18912 git hash: 872d7947bb76)
[PASS] gles: GL_VERSION = OpenGL ES 3.0.0 (ANGLE 2.1.18912 ...)
[PASS] surface: 358 ES core commands resolved (unresolved=0)
[PASS] egl: 44 core commands resolved (unresolved=0)
[PASS] android delta: 221/494 extension commands resolved on the live runtime (extension-conditional)
[PASS] surface: buffer roundtrip (size=64 err=0)
```

On-device witness (x86_64-linux-android26, API-36 emulator, SwiftShader;
`docs/repro/recorded-gles-android.txt`): `libEGL.so+libGLESv2.so`,
EGL display live, `GL_RENDERER = Android Emulator OpenGL ES Translator
(Google SwiftShader)`, 16 `eglQueryString(EGL_EXTENSIONS)` names (7
`EGL_ANDROID_*`), ES2 context + `glClear` -> `glGetError == 0`.

Skip ledger: `docs/gen_gles_manifest.json` (core 0/0 skips; delta 0
command skips, 1 const skip `GL_APIENTRYP` typedef; 279 guard/token
macros excluded) and
`docs/gen_egl_manifest.json` (0/0 skips; delta 0/0, 147 guards + 1
version macro excluded, `EGL_CAST(...)` values parsed to their
underlying 0/-1).

Out of scope for this wave: GLES 1.x (documented exclusion; see SPEC
sec. 2), window-system surfaces, a pinned ANGLE binary for CI
(`ROADMAP.md`).
