# xiom.assimp -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot static-extern surface over the assimp C API (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored generated subset
- [x] Generator (`tools/combine.py`): mirror + include rewriting + config/revision synthesis + port.args emission
- [x] Subset build: core + OBJ/STL/PLY + zlib/minizip/earcut/utf8 (89 TUs)
- [x] Scalar-return bridge; real in-memory OBJ + PLY imports
- [x] Conformance suite (4 checks incl. determinism)

## Phase 3 (Planned)
- [ ] Expand the importer set (glTF2 + rapidjson, FBX, COLLADA + pugixml, BLEND, ...)
- [ ] Post-processing option wrappers (`aiProcess_*` flags, `ApplyPostProcessing`)
- [ ] IO abstraction (custom `IOSystem` bridge)
- [ ] File-based import helpers + examples
- [ ] Export API (re-enable `NO_EXPORT`, exporter TUs)
- [ ] Re-pin to the latest tag when the drift guard flags it
