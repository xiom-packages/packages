# PROVENANCE -- xiom.opengl

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstream (oracle):** `KhronosGroup/OpenGL-Registry`, clone at
  `E:\repos\OpenGL-Registry`, pinned at commit **`6af574a14089ccfee87efe230ebcdd8742859813`**
  ("Merge pull request #685 ...", 2026-10-06).
- **Oracle file:** `xml/gl.xml`, SHA256
  `EC4FEE77D4BCCACE329C5B4530EFB1D34214BA5EC680B883ED63D88D16768382`
  (2,822,494 bytes).
- **WGL oracle file (0.5.0):** same clone, `xml/wgl.xml`, SHA256
  `6401072FBD5B2D992149BB619FA9731C0311256510EE5E688E995D4DD93C59C0`
  (106,344 bytes): WGL_VERSION_1_0 + all 57 WGL extensions -> 146 commands
  / 298 enums.
- **Target surface:** OpenGL **core profile 4.6** -- the union of
  `<feature api="gl">` requires up to `GL_VERSION_4_6` (profile core /
  no-profile), minus `<remove profile="core">`.  Extension commands are NOT
  generated (driver-conditional; the scan API reports the live list instead).
  The **WGL surface** (0.5.0) is the full `wgl.xml` oracle: WGL_VERSION_1_0
  plus every declared WGL extension command.
- **Generated surface** (branch `bindings`):
  - `src/cmds_01..07.xi` -- 656 core command wrappers (one module per ~100);
  - `src/consts_1..6.xi` -- 1358 core enum values (`pub const GL_*: Int`);
    the five G2-pin enums (GL_VENDOR/RENDERER/VERSION/EXTENSIONS/
    SHADING_LANGUAGE_VERSION) stay hand-bound in the package root;
  - `src/names.xi` -- the core command name table (`gl_cmd_names()`,
    `GL_CMD_COUNT`) used by the loadability check;
  - `src/gl_api.xi` -- `GlApi` + the per-call proc resolver.
  - `src/wgl_cmds_01..02.xi` / `wgl_consts_1..2.xi` / `wgl_names.xi`
    (0.5.0) -- the WGL surface: 146 wrappers (`wgl_<name>`), 298 consts,
    the full/core name tables (`WGL_CMD_COUNT` 146, `WGL_CORE_COUNT` 26,
    `WGL_CORE_RESOLVABLE_COUNT` 24 -- the two `wingdi.h` macro aliases
    `wglUseFontBitmaps`/`wglUseFontOutlines` have no exported symbol).
  - Generators: `tools/gen_gl.py` + `tools/gen_wgl.py` (Python stdlib only,
    deterministic; manifests `docs/gen_manifest.json` /
    `docs/gen_wgl_manifest.json`).
- **Loader path:** `src/gl_probe.c` (our code): runtime `LoadLibraryA`
  ("opengl32.dll") + `wglGetProcAddress`, then the `opengl32` export table
  and the `gdi32` fallback (the WGL 1.0 pixel-format set);
  `xgl_session_open` keeps a core-profile context current for the session;
  `xgl_session_dc`/`xgl_session_hglrc` expose the raw handles.
  No link-time dependency; absent runtime -> SKIP.
- **Derived vs independent:** declarations/constants are **derived**
  (mechanical extracts of the Khronos registries; gl.xml/wgl.xml are
  Apache-2.0 per Khronos licensing); the C bridge and all XIOM code are
  original to this package.  No upstream C source is copied.
- **Coverage proof:** `tests/test_conformance.xi` -- live-session resolution
  check 656/656 core commands (`unresolved=0`) + 24/24 resolvable WGL
  core-1.0 commands, oracle counts (146 commands / 298 consts), extensions
  string, swap-interval roundtrip, `wglChoosePixelFormatARB`, buffer
  roundtrip, shader compile, plus the 0.3.0 probe checks (x2 on the RTX
  3070 Ti host, GL 4.6.0 NVIDIA 616.92); the manifests carry
  oracle-vs-emitted counts.
- **Clone ledger:** `E:\repos\CLEANUP.md` row `OpenGL-Registry` (bindings;
  review after 2026-12-01).
- **License:** registry-derived material Apache-2.0 (notice retained here);
  package code MIT OR Apache-2.0 (repo default).
