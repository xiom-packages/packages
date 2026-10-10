# SPEC: xiom.assimp -- Open Asset Import Library bindings (vendored subset, v6.0.5)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.assimp` |
| Version | 0.7.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Open Asset Import Library -- https://github.com/assimp/assimp |
| Upstream version | **v6.0.5** (tag; commit `392a658f9c271be965271f45e7521a1b80ea4392`) |
| Upstream license | BSD-3-Clause (`vendor/LICENSE`; mirrored contribs keep their own licenses) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored path is portable |
| Compiler pin | v0.64.2 |

## 2. Vendored subset (G2 pin)

The pilot compiles **core + material + post-processing + the
OBJ/STL/PLY/glTF2/COLLADA/FBX/BLEND/OFF/SMD importers +
zlib/minizip/earcut-hpp/utf8cpp/rapidjson/pugixml/poly2tri**, mirrored from
the tagged tree by `tools/combine.py`:

- Mirror: `include/assimp/**`, `code/**`, and the needed `contrib/`
  trees into `vendor/` (verbatim bytes), then **rewrite every include that
  resolves to a vendored header into an exact relative path** (the xiom
  link line has no `-I` passthrough). System headers are untouched.
- Rewriter guarantees: standard headers (`stdint.h`, `<vector>`, ...) are
  never remapped even when a vendored file shares the basename (rapidjson
  ships `msinttypes/stdint.h`); contrib includes are keyed relative to the
  lib root and its `include/` dir (plus a `contrib/...` vendor-root key), so
  `<rapidjson/document.h>` and `contrib/poly2tri/...` resolve.
- `vendor/include/assimp/config.h` is generated: CMake-substituted from the
  upstream `config.h.in` (keeping every `AI_CONFIG_*` default), with
  `ASSIMP_BUILD_NO_EXPORT` plus `ASSIMP_BUILD_NO_<X>_IMPORTER`/
  `_EXPORTER` for every importer outside
  OBJ/STL/PLY/GLTF/COLLADA/FBX/BLEND/OFF/SMD and
  `ASSIMP_BUILD_NO_C4D_IMPORTER`.
- `vendor/include/assimp/revision.h` is generated from `revision.h.in`
  (VER 6/0/5; GitVersion 0 for the tarball build).
- `vendor/contrib/zlib/zconf.h` is `zconf.h.included` (zlib's own
  configured file, as upstream's CMake produces).
- Compiled TUs (125, listed in `port.args.json`): 119 C++ files (core dirs
  Common/CApi/Geometry/Material/PostProcessing +
  AssetLib/{OBJ,PLY,STL,glTF,glTF2,glTFCommon,Collada,FBX,Blender,OFF,SMD} +
  pugixml + poly2tri) plus zlib core + minizip (unzip/ioapi) + our bridge.
  Export files are excluded (`Export` in name) and exporter registration is
  disabled.
- **BLEND fixture**: `.blend` is DNA-driven binary and cannot be synthesized
  in-memory like the text/base64 probes. The BLEND probe imports
  `tests/fixtures/BlenderDefault_248.blend` (upstream assimp v6.0.5
  `test/models/BLEND/`, BSD-3-Clause set), embedded as
  `src/blend_default_248.inc` by `tools/embed_blend_fixture.py` (regenerate
  after fixture changes; the .inc is committed).

### Pinned source

| Artifact | Value |
|----------|-------|
| Source of record | tag `v6.0.5`; sparse clone `git clone --depth 1 --branch v6.0.5 --filter=blob:none --sparse https://github.com/assimp/assimp.git` + `sparse-checkout set code include contrib` |
| Commit | `392a658f9c271be965271f45e7521a1b80ea4392` |
| Generated tree sha256 | printed by `tools/combine.py` on every run (excludes the generated `config.h`/`revision.h`) |

### Re-pin procedure

1. Clone/extract the new tag; update the commit row.
2. Run `python tools/combine.py <upstream-root> packages/xiom-assimp`; it
   re-mirrors, regenerates `config.h`/`revision.h`/`zconf.h`, rewrites
   includes, and rewrites `port.args.json`.
3. Record the printed tree sha256; update version rows here and in
   `README.md`/`AUDIT.md`.
4. Re-run `scripts/port.ps1 -Package xiom.assimp` x2 and record
   `STATUS.json`. Watchdog >=600 s (125 TUs compile in ~250-340 s under
   load; `port.args.json` raises the compiler's own watchdog to 900 s via
   `--timeout 900`, since the default 300 s sits too close).

## 3. Design and safe boundary (G5)

`assimp.xi` is the only module with `unsafe`/`extern "C"`; it calls a
scalar-return C++ bridge (`src/assimp_bridge.cpp`) that runs imports
(`Assimp::Importer::ReadFileFromMemory`, hints "obj", "ply", "gltf2",
"dae", "fbx", "blend", "off", "smd") and caches the counts. No out-param
slots (finding B-11 family avoidance); no malloc/free from XIOM. There is
no SKIP path -- the vendored sources always compile in, so the suite runs
real imports on every platform.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- 10 checks: version pin (major 6),
in-memory OBJ import (1 mesh / 3 vertices / 1 face), in-memory PLY import
(3 vertices), in-memory glTF2 import (embedded base64 buffer, 3 vertices),
in-memory COLLADA import (minimal 1.4.1 document, 3 vertices), in-memory
ASCII FBX import (minimal FBX 7400 document, 3 vertices), BLEND import from
the committed fixture (default-scene cube: 1 mesh / 6 quad faces / 24
unshared loop-vertices), in-memory OFF import (minimal ASCII OFF, 1 mesh /
3 vertices / 1 face), in-memory SMD import (minimal ASCII SMD with one
node, skeleton key and bone-linked triangle, 1 mesh / 3 vertices / 1 face),
and repeated-import determinism.

Command (cwd = this package directory; the runner hook adds the C sources):

```
scripts/port.ps1 -Package xiom.assimp
```

## 5. Scope

Pilot: version + eight real imports proving the parser pipeline (OBJ, PLY,
glTF2, COLLADA, ASCII FBX, OFF, SMD in-memory; BLEND from the committed
2.48 fixture). The remaining importer set (X3D, MD5, ...), post-processing
option wrappers, IO abstraction, and the export API are Phase 3
(`ROADMAP.md`). The pre-pilot 0.1.0 static-extern surface is preserved in
git history.
