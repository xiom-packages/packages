# xiom.assimp -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot static-extern surface over the assimp C API (preserved in git history)

## Phase 2 (Done) -- 0.2.0-0.7.0 vendored generated subset
- [x] Generator (`tools/combine.py`): mirror + include rewriting + config/revision synthesis + port.args emission
- [x] Subset build: core + OBJ/STL/PLY + zlib/minizip/earcut/utf8 (89 TUs)
- [x] Scalar-return bridge; real in-memory OBJ + PLY imports
- [x] 0.3.0: glTF2 importer (+ rapidjson) with an embedded-buffer import probe (92 TUs, 5/5)
- [x] 0.4.0: COLLADA importer (+ pugixml) with a minimal-document import probe (96 TUs, 6/6)
- [x] 0.5.0: FBX importer (ASCII + binary tokenizers) with a minimal-document import probe (111 TUs, 7/7)
- [x] 0.6.0: BLEND importer (+ poly2tri) with a committed-fixture import probe (123 TUs, 8/8)
- [x] 0.7.0: OFF + SMD importers with minimal-document import probes (125 TUs, 10/10)
- [x] Conformance suite (10 checks incl. determinism)

## Phase 3 (Planned)
- [ ] Expand the importer set (X3D, MD5, ...)
- [ ] Post-processing option wrappers (`aiProcess_*` flags, `ApplyPostProcessing`)
- [ ] IO abstraction (custom `IOSystem` bridge)
- [ ] File-based import helpers + examples
- [ ] Export API (re-enable `NO_EXPORT`, exporter TUs)
- [ ] Re-pin to the latest tag when the drift guard flags it
