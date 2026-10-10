# AUDIT: xiom.assimp

## Status (2026-10-10)

Vendored-subset implementation at 0.5.0. The pre-pilot module (static
externs over the C API with handle stubs) is preserved in git history
only; the 0.2.0 pilot compiles a real generated subset and proves the
import pipeline (importer set grown 0.2.0 -> 0.5.0: glTF2, COLLADA, FBX).

| Item | State |
|------|-------|
| Compiler | xiom v0.64.2 |
| Upstream | assimp v6.0.5 (commit 392a658f); BSD-3-Clause |
| Subset | core (Common/CApi/Geometry/Material/PostProcessing) + OBJ/STL/PLY/glTF2/COLLADA/FBX + zlib/minizip/earcut-hpp/utf8cpp/rapidjson/pugixml; 111 TUs |
| Generator | `tools/combine.py` (mirror + include rewrite + config synthesis + port.args emission) |
| Link model | `--c-source` list from `port.args.json`; no system library |
| FFI confinement | all `unsafe`/`extern` in the root module `assimp.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 7 checks (five real in-memory imports) |
| Runs | 7/7 x2 on the pin (OBJ 1 mesh/3 verts/1 face; PLY 3 verts; glTF2 3 verts; COLLADA 3 verts; FBX 3 verts) |

## Design notes

- **Quoted-include rewriting** is the load-bearing trick: upstream mixes
  `<assimp/...>` and code-root-relative quoted includes with `-I` roots the
  xiom link line cannot pass; the generator resolves every include against
  a vendored-header map and rewrites it to an exact relative path, so each
  mirrored file compiles directly. Standard headers are never remapped
  (rapidjson ships `msinttypes/stdint.h`); contrib includes are keyed
  relative to the lib root and its `include/` dir.
- **config synthesis from config.h.in** keeps all `AI_CONFIG_*` defaults;
  the subset switches are appended (every disabled importer name + C4D +
  NO_EXPORT).
- **zlib**: compiled from `contrib/zlib` (top-level core + minizip
  unzip/ioapi); `zconf.h` comes from `zconf.h.included` (zlib's configured
  file). Export files are excluded and the C export API is not compiled.
- **FBX** (0.5.0): the FBX importer ships ASCII + binary tokenizers; the
  probe exercises the ASCII path with a minimal FBX 7400 document
  (FBXHeaderExtension + Objects + OO connections). Binary FBX compiles in
  (zlib-backed arrays) but is not covered by the probe.
- Scalar-return bridge (cached counts) -- no out-param slots for this
  heavy engine call (B-11 family avoidance).

## Known limitations

- Importer subset only (OBJ/STL/PLY/glTF2/COLLADA/FBX; draco-compressed
  glTF is behind `ASSIMP_ENABLE_DRACO`, not defined); BLEND and the rest
  are Phase 3 additions (generator constant + config update).
- Export API disabled (`ASSIMP_BUILD_NO_EXPORT`).
- Version revision field reports GitVersion (0 for the tarball build); the
  patch pin (5) lives in the generated `revision.h`.
- Windows x64 primary; the vendored path is portable, no other platform run.
