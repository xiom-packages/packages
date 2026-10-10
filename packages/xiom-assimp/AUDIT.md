# AUDIT: xiom.assimp

## Status (2026-10-10)

Vendored-subset implementation at 0.2.0. The pre-pilot module (static
externs over the C API with handle stubs) is preserved in git history
only; the 0.2.0 pilot compiles a real generated subset and proves the
import pipeline.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.2 |
| Upstream | assimp v6.0.5 (commit 392a658f); BSD-3-Clause |
| Subset | core (Common/CApi/Geometry/Material/PostProcessing) + OBJ/STL/PLY + zlib/minizip/earcut-hpp/utf8cpp; 89 TUs |
| Generator | `tools/combine.py` (mirror + include rewrite + config synthesis + port.args emission) |
| Link model | `--c-source` list from `port.args.json`; no system library |
| FFI confinement | all `unsafe`/`extern` in the root module `assimp.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 4 checks (two real in-memory imports) |
| Runs | 4/4 x2 on the pin (OBJ 1 mesh/3 verts/1 face; PLY 3 verts) |

## Design notes

- **Quoted-include rewriting** is the load-bearing trick: upstream mixes
  `<assimp/...>` and code-root-relative quoted includes with `-I` roots the
  xiom link line cannot pass; the generator resolves every include against
  a vendored-header map and rewrites it to an exact relative path, so each
  mirrored file compiles directly.
- **config synthesis from config.h.in** keeps all `AI_CONFIG_*` defaults;
  the subset switches are appended (47 importer names + C4D + NO_EXPORT).
- **zlib**: compiled from `contrib/zlib` (top-level core + minizip
  unzip/ioapi); `zconf.h` comes from `zconf.h.included` (zlib's configured
  file). Export files are excluded and the C export API is not compiled.
- Scalar-return bridge (cached counts) -- no out-param slots for this
  heavy engine call (B-11 family avoidance).

## Known limitations

- Importer subset only (OBJ/STL/PLY); FBX/glTF/COLLADA/BLEND and the rest
  are Phase 2 additions (generator constant + config update).
- Export API disabled (`ASSIMP_BUILD_NO_EXPORT`).
- Version revision field reports GitVersion (0 for the tarball build); the
  patch pin (5) lives in the generated `revision.h`.
- Windows x64 primary; the vendored path is portable, no other platform run.
