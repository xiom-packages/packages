# AUDIT: xiom.assimp

## Status (2026-10-11)

Vendored-subset implementation at 0.8.0 (file import + mesh-data getters
for the engine P4 asset pipeline). The pre-pilot module (static
externs over the C API with handle stubs) is preserved in git history
only; the 0.2.0 pilot compiles a real generated subset and proves the
import pipeline (importer set grown 0.2.0 -> 0.7.0: glTF2, COLLADA, FBX,
BLEND, OFF, SMD; 0.8.0 adds path-based import with Triangulate + FlipUVs
and positions/uvs/indices copies).

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Upstream | assimp v6.0.5 (commit 392a658f); BSD-3-Clause |
| Subset | core (Common/CApi/Geometry/Material/PostProcessing) + OBJ/STL/PLY/glTF2/COLLADA/FBX/BLEND/OFF/SMD + zlib/minizip/earcut-hpp/utf8cpp/rapidjson/pugixml/poly2tri; 125 TUs |
| Generator | `tools/combine.py` (mirror + include rewrite + config synthesis + port.args emission) |
| Link model | `--c-source` list from `port.args.json` (which also raises the compiler watchdog: `--timeout 900` for the 125-TU build); no system library |
| FFI confinement | all `unsafe`/`extern` in the root module `assimp.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 16 checks (eight real imports + the 0.8.0 file-import group) |
| Runs | 16/16 x2 on the pin (previous 10 + quad_uv.obj: 4 verts / 2 tris / uvs; positions exact; UVs after FlipUVs; 6 indices covering 4 verts; release; missing file -> Err) |

## Design notes

- **Quoted-include rewriting** is the load-bearing trick: upstream mixes
  `<assimp/...>` and code-root-relative quoted includes with `-I` roots the
  xiom link line cannot pass; the generator resolves every include against
  a vendored-header map and rewrites it to an exact relative path, so each
  mirrored file compiles directly. Standard headers are never remapped
  (rapidjson ships `msinttypes/stdint.h`); contrib includes are keyed
  relative to the lib root and its `include/` dir, plus a `contrib/...`
  vendor-root key (which also resolved previously-stale poly2tri includes
  inside the disabled IFC loader -- inert, IFC is not compiled).
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
- **BLEND** (0.6.0): the Blender loader is DNA-driven binary; the probe
  imports the committed `tests/fixtures/BlenderDefault_248.blend` (upstream
  assimp test model, Blender 2.48 default scene: one cube). The fixture is
  embedded as `src/blend_default_248.inc` by
  `tools/embed_blend_fixture.py`; ngon tessellation is backed by the
  poly2tri contrib.
- **OFF/SMD** (0.7.0): both are ASCII formats exercised with minimal
  in-memory documents (OFF: 3 verts + 1 face; SMD: one node, one skeleton
  key, one bone-linked triangle).
- **File import** (0.8.0): 1-based registry handles (4 live imports),
  `ReadFile` with `aiProcess_Triangulate | aiProcess_FlipUVs`; positions /
  UVs / indices are copied by the bridge into an XIOM-owned slot and read
  with byte-indexed Vec access -- int-to-pointer casts are silently
  sanitized on v0.64.3 (foreign-pointer round-trips read zeros; B-20), so
  the C-copy out-param shape is the correct portable pattern.  UVs keep
  assimp's 12-byte stride (u/v read, w ignored).
- Scalar-return bridge (cached counts) -- no out-param slots for this
  heavy engine call (B-11 family avoidance); 0.8.0 out-params write into
  caller-owned slots only (same discipline).

## Known limitations

- Importer subset only (OBJ/STL/PLY/glTF2/COLLADA/FBX/BLEND/OFF/SMD;
  draco-compressed glTF is behind `ASSIMP_ENABLE_DRACO`, not defined);
  X3D, MD5 and the rest are Phase 3 additions (generator constant + config
  update).
- Export API disabled (`ASSIMP_BUILD_NO_EXPORT`).
- Version revision field reports GitVersion (0 for the tarball build); the
  patch pin (5) lives in the generated `revision.h`.
- BLEND coverage is the committed 2.48 fixture only (the loader supports
  more Blender versions; not exercised).
- Windows x64 primary; the vendored path is portable, no other platform run.
