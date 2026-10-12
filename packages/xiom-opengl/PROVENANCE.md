# PROVENANCE -- xiom.opengl

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstream (oracle):** `KhronosGroup/OpenGL-Registry`, clone at
  `E:\repos\OpenGL-Registry`, pinned at commit **`6af574a14089ccfee87efe230ebcdd8742859813`**
  ("Merge pull request #685 ...", 2026-10-06).
- **Oracle file:** `xml/gl.xml`, SHA256
  `EC4FEE77D4BCCACE329C5B4530EFB1D34214BA5EC680B883ED63D88D16768382`
  (2,822,494 bytes).
- **Target surface:** OpenGL **core profile 4.6** -- the union of
  `<feature api="gl">` requires up to `GL_VERSION_4_6` (profile core /
  no-profile), minus `<remove profile="core">`.  Extension commands are NOT
  generated (driver-conditional; the scan API reports the live list instead).
- **Generated surface** (branch `bindings`):
  - `src/cmds_01..07.xi` -- 656 core command wrappers (one module per ~100);
  - `src/consts_1..6.xi` -- 1358 core enum values (`pub const GL_*: Int`);
    the five G2-pin enums (GL_VENDOR/RENDERER/VERSION/EXTENSIONS/
    SHADING_LANGUAGE_VERSION) stay hand-bound in the package root;
  - `src/names.xi` -- the core command name table (`gl_cmd_names()`,
    `GL_CMD_COUNT`) used by the loadability check;
  - `src/gl_api.xi` -- `GlApi` + the per-call proc resolver.
  - Generator: `tools/gen_gl.py` (Python stdlib only, deterministic).
- **Loader path:** `src/gl_probe.c` (our code): runtime `LoadLibraryA`
  ("opengl32.dll") + `wglGetProcAddress`, then the `opengl32` export table;
  `xgl_session_open` keeps a core-profile context current for the session.
  No link-time dependency; absent runtime -> SKIP.
- **Derived vs independent:** declarations/constants are **derived**
  (mechanical extracts of the Khronos registry; gl.xml is Apache-2.0 per
  Khronos licensing); the C bridge and all XIOM code are original to this
  package.  No upstream C source is copied.
- **Coverage proof:** `tests/test_conformance.xi` -- live-session resolution
  check 656/656 core commands (`unresolved=0`, x2 on the RTX 3070 Ti host,
  GL 4.6.0 NVIDIA 616.92), buffer roundtrip, shader compile, plus the 0.3.0
  probe checks; `docs/gen_manifest.json` carries oracle-vs-emitted counts.
- **Clone ledger:** `E:\repos\CLEANUP.md` row `OpenGL-Registry` (bindings;
  review after 2026-12-01).
- **License:** registry-derived material Apache-2.0 (notice retained here);
  package code MIT OR Apache-2.0 (repo default).
