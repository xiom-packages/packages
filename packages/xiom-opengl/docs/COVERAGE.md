# COVERAGE -- xiom.opengl (core profile 4.6 + WGL)

Oracle: `KhronosGroup/OpenGL-Registry` @ commit `6af574a1`
(`xml/gl.xml` SHA256 `EC4FEE77...`; `xml/wgl.xml` SHA256 `6401072F...`).
Generators: `tools/gen_gl.py` + `tools/gen_wgl.py` (deterministic, Python
stdlib).  Target: the registry's **core profile** set up to GL 4.6 --
`<feature api="gl">` requires minus `<remove profile="core">` -- plus the
full **WGL** surface from `wgl.xml`.

| Set | Oracle | Emitted | Resolved (live) | Notes |
|-----|--------|---------|-----------------|-------|
| Core commands (<= 4.6) | 656 | 656 wrappers (`cmds_01..07`) | **656/656** (`unresolved=0`) | loadability check in `tests/test_conformance.xi` |
| Core enums | 1363 | 1358 consts (`consts_1..6`) | n/a | 5 names hand-bound in the root (G2 pin) |
| GL extensions | driver list | name scan only (`opengl_has_extension`) | 404 advertised on the RTX 3070 Ti | extension commands out of scope for GL |
| WGL commands (1.0 + all extensions) | 146 | 146 wrappers (`wgl_cmds_01..02`) | core-1.0: **24/24 resolvable** (`unresolved=0`); extension commands driver-conditional | 2 `wingdi.h` macro aliases excluded from the resolvable set (no exported symbol; A/W variants ship) |
| WGL enums | 298 | 298 consts (`wgl_consts_1..2`) | n/a | -- |

Resolved = `xgl_get_proc` (`wglGetProcAddress` first, then the `opengl32`
exports, then `gdi32` for the WGL 1.0 pixel-format set) under a live
4.6-core session.  Witness (2026-10-13, x2):

```
[PASS] surface: 656 core commands resolved (unresolved=0)
[PASS] wgl: session handles live (dc+context)
[PASS] wgl: 24 core-1.0 commands resolved (unresolved=0)
[PASS] wgl: oracle surface 146 commands (core 26)
[PASS] wgl: extensions string (809 chars)
[PASS] wgl: swap interval roundtrip (1 -> 1, 0 -> 0)
[PASS] wgl: ChoosePixelFormatARB -> 1 format(s) pf=9
```

Skip ledger: `docs/gen_manifest.json` (GL: 0 command / 0 const skips; 5
root-owned enums excluded by design) and `docs/gen_wgl_manifest.json`
(WGL: 0 skips; the macro-alias ledger + core/resolvable split recorded).

Out of scope for this wave (next candidates): GL EXTENSION command
wrappers (resolve-on-demand surface), GLES/EGL (ANGLE `libEGL`/`libGLESv2`
+ `eglGetProcAddress`), `opengl32sw.dll` fallback, POSIX sonames.
