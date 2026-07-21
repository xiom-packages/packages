# xiom-assimp — ROADMAP

**Phase 1** (v0.1.0) — **DONE**
- [x] Opaque handle types: AiScene, AiMesh, AiMaterial, AiAnimation, AiNode
- [x] extern "C" stubs for 16 Assimp C API functions
- [x] 28 post-processing flag constants (bitmask)
- [x] 4 composable flag presets (Default, Fast, Quality, MaxQuality)
- [x] Safe wrappers with requires/ensures contracts: import_file, import_file_ex, release_import, get_error_string, get_num_meshes, get_mesh, get_num_vertices, get_vertices, get_num_faces, get_faces, get_num_normals, get_normals, get_num_tex_coords, get_tex_coords, get_material_count, get_material
- [x] Conformance test suite (48 tests)

**Phase 2** (planned)
- [ ] aiNode tree traversal: get_root_node, get_num_children, get_child, get_node_name
- [ ] aiAnimation extraction: get_num_animations, get_animation, get_num_channels
- [ ] aiMaterial property reading: get_material_name, get_material_color, get_material_texture_path
- [ ] Bone/skeleton extraction: get_num_bones, get_bone
- [ ] Camera and light extraction
- [ ] Memory safety: arena-based AiString lifetime wrappers

**Phase 3** (future)
- [ ] Scene graph builder (high-level tree over aiNode)
- [ ] Material system bridge (xiom.assimp → engine material pipeline)
- [ ] Streaming/lazy-loading support
- [ ] Custom file I/O (aiFileIO bridge)
- [ ] Export support (Assimp exporter API)
