# COVERAGE -- xiom.opengl (core profile 4.6)

Oracle: `KhronosGroup/OpenGL-Registry` `xml/gl.xml` @ commit `6af574a1`
(SHA256 `EC4FEE77...`).  Generator: `tools/gen_gl.py` (deterministic, Python
stdlib).  Target: the registry's **core profile** set up to GL 4.6 --
`<feature api="gl">` requires minus `<remove profile="core">`.

| Set | Oracle | Emitted | Resolved (live) | Notes |
|-----|--------|---------|-----------------|-------|
| Core commands (<= 4.6) | 656 | 656 wrappers (`cmds_01..07`) | **656/656** (`unresolved=0`) | loadability check in `tests/test_conformance.xi` |
| Core enums | 1363 | 1358 consts (`consts_1..6`) | n/a | 5 names hand-bound in the root (G2 pin) |
| Extensions | driver list | name scan only (`opengl_has_extension`) | 404 advertised on the RTX 3070 Ti | extension commands out of scope for 0.4.0 |

Resolved = `xgl_get_proc` (`wglGetProcAddress` first, then the `opengl32`
export table) under a live 4.6-core session.  Witness (2026-10-12, x2):

```
[PASS] surface: 656 core commands resolved (unresolved=0)
[PASS] surface: buffer roundtrip (size=64 err=0)
[PASS] surface: shader compile status=1
```

Skip ledger (recorded in `docs/gen_manifest.json`): 0 command skips,
0 const skips; the 5 root-owned enums are excluded by design.

Out of scope for this wave (next candidates): extension command wrappers
(resolve-on-demand surface), WGL extension bindings, GLES/EGL (ANGLE),
POSIX sonames.
