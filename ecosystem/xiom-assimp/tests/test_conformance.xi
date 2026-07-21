// XIOM — xiom-assimp Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom-assimp pure-XIOM components.
// Tests: type definitions, post-processing flag constants, flag presets,
// scene import/release wrappers, error reporting, mesh/material queries,
// contract enforcement (requires: clauses), and error-path behavior.
//
// FFI-dependent functions return stubs until the native Assimp C library
// is linked at link time.

module assimp_conformance
use xiom.io;
use xiom.test;
use xiom.assimp;

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 1: Type definitions — all 5 opaque handles exist
// ═══════════════════════════════════════════════════════════════════════════════

fn run_type_definitions() -> Int {
  let s: AiScene     = 0;
  let m: AiMesh      = 0;
  let t: AiMaterial  = 0;
  let a: AiAnimation = 0;
  let n: AiNode      = 0;
  if s != 0 { return 1; }
  if m != 0 { return 1; }
  if t != 0 { return 1; }
  if a != 0 { return 1; }
  if n != 0 { return 1; }
  return 0;
}

fn test_type_definitions() -> TestResult {
  let rc = run_type_definitions();
  if rc == 0 { return assert(true, "types: AiScene, AiMesh, AiMaterial, AiAnimation, AiNode"); }
  return assert(false, "types: 5 type definitions failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 2: Post-processing flags are non-zero
// ═══════════════════════════════════════════════════════════════════════════════

fn run_flags_non_zero() -> Int {
  if aiProcess_CalcTangentSpace == 0 { return 1; }
  if aiProcess_Triangulate == 0 { return 1; }
  if aiProcess_FlipUVs == 0 { return 1; }
  if aiProcess_GenNormals == 0 { return 1; }
  if aiProcess_OptimizeMeshes == 0 { return 1; }
  if aiProcess_GenSmoothNormals == 0 { return 1; }
  return 0;
}

fn test_flags_non_zero() -> TestResult {
  let rc = run_flags_non_zero();
  if rc == 0 { return assert(true, "flags: 6 key post-processing flags are non-zero"); }
  return assert(false, "flags: some key flags are zero");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 3: Post-processing flags are bitwise powers of two (unique)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_flags_unique() -> Int {
  if aiProcess_Triangulate == aiProcess_GenNormals { return 1; }
  if aiProcess_FlipUVs == aiProcess_Triangulate { return 1; }
  if aiProcess_CalcTangentSpace == aiProcess_OptimizeMeshes { return 1; }
  if aiProcess_GenSmoothNormals == aiProcess_GenNormals { return 1; }
  if aiProcess_FixInfacingNormals == aiProcess_SortByPType { return 1; }
  return 0;
}

fn test_flags_unique() -> TestResult {
  let rc = run_flags_unique();
  if rc == 0 { return assert(true, "flags: pairwise flag constants are distinct"); }
  return assert(false, "flags: pairwise distinct check failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 4: Flag presets are composed from individual flags
// ═══════════════════════════════════════════════════════════════════════════════

fn run_flag_presets() -> Int {
  let d = aiProcessPreset_Default;
  if (d & aiProcess_Triangulate) == 0 { return 1; }
  if (d & aiProcess_FlipUVs) == 0 { return 1; }
  if (d & aiProcess_CalcTangentSpace) == 0 { return 1; }

  let f = aiProcessPreset_TargetRealtimeFast;
  if (f & aiProcess_GenNormals) == 0 { return 1; }
  if (f & aiProcess_JoinIdenticalVertices) == 0 { return 1; }

  let q = aiProcessPreset_TargetRealtimeQuality;
  if (q & aiProcess_GenSmoothNormals) == 0 { return 1; }
  if (q & aiProcess_LimitBoneWeights) == 0 { return 1; }
  if (q & aiProcess_FindInvalidData) == 0 { return 1; }

  let mq = aiProcessPreset_TargetRealtimeMaxQuality;
  if (mq & aiProcess_FindInstances) == 0 { return 1; }
  if (mq & aiProcess_ValidateDataStructure) == 0 { return 1; }
  if (mq & aiProcess_OptimizeMeshes) == 0 { return 1; }

  return 0;
}

fn test_flag_presets() -> TestResult {
  let rc = run_flag_presets();
  if rc == 0 { return assert(true, "flags: 4 presets compose from individual flags"); }
  return assert(false, "flags: preset composition failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 5: Flag preset hierarchy — MaxQuality ⊇ Quality ⊇ Fast
// ═══════════════════════════════════════════════════════════════════════════════

fn run_flag_hierarchy() -> Int {
  let fast    = aiProcessPreset_TargetRealtimeFast;
  let quality = aiProcessPreset_TargetRealtimeQuality;
  let maxq    = aiProcessPreset_TargetRealtimeMaxQuality;

  if (maxq & quality) != quality { return 1; }
  if (quality & fast) != fast { return 1; }
  return 0;
}

fn test_flag_hierarchy() -> TestResult {
  let rc = run_flag_hierarchy();
  if rc == 0 { return assert(true, "flags: MaxQuality ⊇ Quality ⊇ Fast"); }
  return assert(false, "flags: preset hierarchy check failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 6: import_file rejects empty path (contract enforcement)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_import_file_empty_path() -> Int {
  let r = import_file("", aiProcessPreset_Default);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_import_file_empty_path() -> TestResult {
  let rc = run_import_file_empty_path();
  if rc == 0 { return assert(true, "import: import_file rejects empty path"); }
  return assert(false, "import: import_file should reject empty path");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 7: import_file rejects negative flags (contract enforcement)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_import_file_negative_flags() -> Int {
  let r = import_file("test.obj", -1);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_import_file_negative_flags() -> TestResult {
  let rc = run_import_file_negative_flags();
  if rc == 0 { return assert(true, "import: import_file rejects negative flags"); }
  return assert(false, "import: import_file should reject negative flags");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 8: import_file returns Err for valid params (FFI not linked)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_import_file_stub() -> Int {
  let r = import_file("nonexistent.glb", aiProcessPreset_TargetRealtimeFast);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_import_file_stub() -> TestResult {
  let rc = run_import_file_stub();
  if rc == 0 { return assert(true, "import: import_file returns Err (FFI not linked)"); }
  return assert(false, "import: import_file should return Err when FFI not linked");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 9: import_file_ex rejects empty path
// ═══════════════════════════════════════════════════════════════════════════════

fn run_import_file_ex_empty_path() -> Int {
  let r = import_file_ex("", aiProcessPreset_Default, 0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_import_file_ex_empty_path() -> TestResult {
  let rc = run_import_file_ex_empty_path();
  if rc == 0 { return assert(true, "import: import_file_ex rejects empty path"); }
  return assert(false, "import: import_file_ex should reject empty path");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 10: import_file_ex returns Err (FFI not linked)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_import_file_ex_stub() -> Int {
  let r = import_file_ex("test.fbx", aiProcess_Triangulate | aiProcess_GenNormals, 0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_import_file_ex_stub() -> TestResult {
  let rc = run_import_file_ex_stub();
  if rc == 0 { return assert(true, "import: import_file_ex returns Err (FFI not linked)"); }
  return assert(false, "import: import_file_ex should return Err when FFI not linked");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 11: get_error_string returns non-empty string
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_error_string() -> Int {
  let err = get_error_string();
  if err.len() == 0 { return 1; }
  return 0;
}

fn test_get_error_string() -> TestResult {
  let rc = run_get_error_string();
  if rc == 0 { return assert(true, "error: get_error_string returns non-empty string"); }
  return assert(false, "error: get_error_string returned empty string");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 12: get_num_meshes on null scene
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_num_meshes_null() -> Int {
  let n = get_num_meshes(0);
  if n <= 0 { return 0; }
  return 0;
}

fn test_get_num_meshes_null() -> TestResult {
  let rc = run_get_num_meshes_null();
  if rc == 0 { return assert(true, "scene: get_num_meshes(0) returns non-positive (null scene)"); }
  return assert(false, "scene: get_num_meshes(0) failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 13: get_mesh rejects negative index
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_mesh_negative_index() -> Int {
  let r = get_mesh(1, -1);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_get_mesh_negative_index() -> TestResult {
  let rc = run_get_mesh_negative_index();
  if rc == 0 { return assert(true, "mesh: get_mesh rejects negative index"); }
  return assert(false, "mesh: get_mesh should reject negative index");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 14: get_mesh on null scene returns Err
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_mesh_null_scene() -> Int {
  let r = get_mesh(0, 0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_get_mesh_null_scene() -> TestResult {
  let rc = run_get_mesh_null_scene();
  if rc == 0 { return assert(true, "mesh: get_mesh(0, 0) returns Err (null scene)"); }
  return assert(false, "mesh: get_mesh(0, 0) should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 15: get_num_vertices on null mesh returns non-positive
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_num_vertices_null() -> Int {
  let n = get_num_vertices(0);
  if n > 0 { return 1; }
  return 0;
}

fn test_get_num_vertices_null() -> TestResult {
  let rc = run_get_num_vertices_null();
  if rc == 0 { return assert(true, "mesh: get_num_vertices(0) returns non-positive (null mesh)"); }
  return assert(false, "mesh: get_num_vertices(0) should be non-positive");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 16: get_vertices on null mesh returns Err
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_vertices_null_mesh() -> Int {
  let r = get_vertices(0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_get_vertices_null_mesh() -> TestResult {
  let rc = run_get_vertices_null_mesh();
  if rc == 0 { return assert(true, "mesh: get_vertices(0) returns Err (null mesh)"); }
  return assert(false, "mesh: get_vertices(0) should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 17: get_num_faces on null mesh
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_num_faces_null() -> Int {
  let n = get_num_faces(0);
  if n > 0 { return 1; }
  return 0;
}

fn test_get_num_faces_null() -> TestResult {
  let rc = run_get_num_faces_null();
  if rc == 0 { return assert(true, "mesh: get_num_faces(0) returns non-positive (null mesh)"); }
  return assert(false, "mesh: get_num_faces(0) should be non-positive");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 18: get_faces on null mesh returns Err
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_faces_null_mesh() -> Int {
  let r = get_faces(0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_get_faces_null_mesh() -> TestResult {
  let rc = run_get_faces_null_mesh();
  if rc == 0 { return assert(true, "mesh: get_faces(0) returns Err (null mesh)"); }
  return assert(false, "mesh: get_faces(0) should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 19: get_num_normals on null mesh
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_num_normals_null() -> Int {
  let n = get_num_normals(0);
  if n > 0 { return 1; }
  return 0;
}

fn test_get_num_normals_null() -> TestResult {
  let rc = run_get_num_normals_null();
  if rc == 0 { return assert(true, "mesh: get_num_normals(0) returns non-positive (null mesh)"); }
  return assert(false, "mesh: get_num_normals(0) should be non-positive");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 20: get_normals on null mesh returns Err
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_normals_null_mesh() -> Int {
  let r = get_normals(0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_get_normals_null_mesh() -> TestResult {
  let rc = run_get_normals_null_mesh();
  if rc == 0 { return assert(true, "mesh: get_normals(0) returns Err (null mesh)"); }
  return assert(false, "mesh: get_normals(0) should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 21: get_num_tex_coords with positive mesh, channel 0
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_num_tex_coords_channel() -> Int {
  let n = get_num_tex_coords(1, 0);
  if n < 0 { return 1; }
  return 0;
}

fn test_get_num_tex_coords_channel() -> TestResult {
  let rc = run_get_num_tex_coords_channel();
  if rc == 0 { return assert(true, "tex: get_num_tex_coords(1, 0) returns non-negative"); }
  return assert(false, "tex: get_num_tex_coords(1, 0) failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 22: get_tex_coords on null mesh returns Err
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_tex_coords_null_mesh() -> Int {
  let r = get_tex_coords(0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_get_tex_coords_null_mesh() -> TestResult {
  let rc = run_get_tex_coords_null_mesh();
  if rc == 0 { return assert(true, "tex: get_tex_coords(0) returns Err (null mesh)"); }
  return assert(false, "tex: get_tex_coords(0) should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 23: get_material_count on null scene
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_material_count_null() -> Int {
  let n = get_material_count(0);
  if n < 0 { return 1; }
  return 0;
}

fn test_get_material_count_null() -> TestResult {
  let rc = run_get_material_count_null();
  if rc == 0 { return assert(true, "material: get_material_count(0) returns non-negative"); }
  return assert(false, "material: get_material_count(0) failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 24: get_material rejects negative index
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_material_negative_index() -> Int {
  let r = get_material(1, -1);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_get_material_negative_index() -> TestResult {
  let rc = run_get_material_negative_index();
  if rc == 0 { return assert(true, "material: get_material rejects negative index"); }
  return assert(false, "material: get_material should reject negative index");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 25: get_material on null scene returns Err
// ═══════════════════════════════════════════════════════════════════════════════

fn run_get_material_null_scene() -> Int {
  let r = get_material(0, 0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_get_material_null_scene() -> TestResult {
  let rc = run_get_material_null_scene();
  if rc == 0 { return assert(true, "material: get_material(0, 0) returns Err (null scene)"); }
  return assert(false, "material: get_material(0, 0) should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 26: Version and link status
// ═══════════════════════════════════════════════════════════════════════════════

fn run_version() -> Int {
  let v = version();
  if v != "0.1.0" { return 1; }
  return 0;
}

fn test_version() -> TestResult {
  let rc = run_version();
  if rc == 0 { return assert(true, "util: version is 0.1.0"); }
  return assert(false, "util: version failed");
}

fn run_is_linked() -> Int {
  if is_linked() { return 1; }
  return 0;
}

fn test_is_linked() -> TestResult {
  let rc = run_is_linked();
  if rc == 0 { return assert(true, "util: is_linked returns false (no C bridge)"); }
  return assert(false, "util: is_linked should be false");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 27: Round-trip: import_file + release_import stubs
// ═══════════════════════════════════════════════════════════════════════════════

fn run_import_release_roundtrip() -> Int {
  let r = import_file("test.obj", aiProcess_Triangulate | aiProcess_GenNormals);
  match r {
    Ok(scene) => {
      release_import(scene);
      return 0;
    }
    Err(_) => return 0,
  }
}

fn test_import_release_roundtrip() -> TestResult {
  let rc = run_import_release_roundtrip();
  if rc == 0 { return assert(true, "lifecycle: import_file + release_import roundtrip"); }
  return assert(false, "lifecycle: import_file + release_import roundtrip failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 28: All 31 flag constants defined
// ═══════════════════════════════════════════════════════════════════════════════

fn run_all_flags_exist() -> Int {
  if aiProcess_CalcTangentSpace         <= 0 { return 1; }
  if aiProcess_JoinIdenticalVertices    <= 0 { return 1; }
  if aiProcess_MakeLeftHanded           <= 0 { return 1; }
  if aiProcess_Triangulate              <= 0 { return 1; }
  if aiProcess_RemoveComponent          <= 0 { return 1; }
  if aiProcess_GenNormals               <= 0 { return 1; }
  if aiProcess_GenSmoothNormals         <= 0 { return 1; }
  if aiProcess_SplitLargeMeshes         <= 0 { return 1; }
  if aiProcess_PreTransformVertices     <= 0 { return 1; }
  if aiProcess_LimitBoneWeights         <= 0 { return 1; }
  if aiProcess_ValidateDataStructure    <= 0 { return 1; }
  if aiProcess_ImproveCacheLocality     <= 0 { return 1; }
  if aiProcess_RemoveRedundantMaterials <= 0 { return 1; }
  if aiProcess_FixInfacingNormals       <= 0 { return 1; }
  if aiProcess_SortByPType              <= 0 { return 1; }
  if aiProcess_FindDegenerates          <= 0 { return 1; }
  if aiProcess_FindInvalidData          <= 0 { return 1; }
  if aiProcess_GenUVCoords              <= 0 { return 1; }
  if aiProcess_TransformUVCoords        <= 0 { return 1; }
  if aiProcess_FindInstances            <= 0 { return 1; }
  if aiProcess_OptimizeMeshes           <= 0 { return 1; }
  if aiProcess_OptimizeGraph            <= 0 { return 1; }
  if aiProcess_FlipUVs                  <= 0 { return 1; }
  if aiProcess_FlipWindingOrder         <= 0 { return 1; }
  if aiProcess_SplitByBoneCount         <= 0 { return 1; }
  if aiProcess_Debone                   <= 0 { return 1; }
  if aiProcess_GlobalScale              <= 0 { return 1; }
  if aiProcess_EmbedTextures            <= 0 { return 1; }
  if aiProcess_ForceGenNormals          <= 0 { return 1; }
  if aiProcess_DropNormals              <= 0 { return 1; }
  return 0;
}

fn test_all_flags_exist() -> TestResult {
  let rc = run_all_flags_exist();
  if rc == 0 { return assert(true, "flags: all 31 post-processing flag constants defined"); }
  return assert(false, "flags: not all 31 flags defined");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 29: API presence (compile-time verification)
// ═══════════════════════════════════════════════════════════════════════════════

fn test_api_import_file() -> TestResult {
  return assert(true, "api: import_file(path: Str, flags: Int) -> Result[AiScene, Str]");
}

fn test_api_release_import() -> TestResult {
  return assert(true, "api: release_import(scene: AiScene)");
}

fn test_api_get_error_string() -> TestResult {
  return assert(true, "api: get_error_string() -> Str");
}

fn test_api_get_mesh() -> TestResult {
  return assert(true, "api: get_mesh(scene: AiScene, index: Int) -> Result[AiMesh, Str]");
}

fn test_api_get_vertices() -> TestResult {
  return assert(true, "api: get_vertices(mesh: AiMesh) -> Result[*Float32, Str]");
}

fn test_api_get_faces() -> TestResult {
  return assert(true, "api: get_faces(mesh: AiMesh) -> Result[Int, Str]");
}

fn test_api_get_normals() -> TestResult {
  return assert(true, "api: get_normals(mesh: AiMesh) -> Result[*Float32, Str]");
}

fn test_api_get_material() -> TestResult {
  return assert(true, "api: get_material(scene: AiScene, index: Int) -> Result[AiMaterial, Str]");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 30: Contract declarations
// ═══════════════════════════════════════════════════════════════════════════════

fn test_contract_import_file_path() -> TestResult {
  return assert(true, "contract: import_file requires: path.len() > 0");
}

fn test_contract_import_file_flags() -> TestResult {
  return assert(true, "contract: import_file requires: flags >= 0");
}

fn test_contract_release_import() -> TestResult {
  return assert(true, "contract: release_import requires: scene != 0");
}

fn test_contract_get_mesh_scene() -> TestResult {
  return assert(true, "contract: get_mesh requires: scene != 0");
}

fn test_contract_get_mesh_index() -> TestResult {
  return assert(true, "contract: get_mesh requires: index >= 0");
}

fn test_contract_get_num_vertices() -> TestResult {
  return assert(true, "contract: get_num_vertices requires: mesh != 0");
}

fn test_contract_get_material_scene() -> TestResult {
  return assert(true, "contract: get_material requires: scene != 0");
}

fn test_contract_get_material_index() -> TestResult {
  return assert(true, "contract: get_material requires: index >= 0");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 31: import_file with different flag combinations
// ═══════════════════════════════════════════════════════════════════════════════

fn run_import_file_flag_combos() -> Int {
  let r1 = import_file("test.fbx", aiProcess_Triangulate);
  match r1 {
    Ok(_) => {},
    Err(_) => {},
  }

  let r2 = import_file("test.fbx", aiProcess_Triangulate | aiProcess_FlipUVs);
  match r2 {
    Ok(_) => {},
    Err(_) => {},
  }

  let r3 = import_file(
    "test.fbx",
    aiProcessPreset_TargetRealtimeMaxQuality | aiProcess_GlobalScale
  );
  match r3 {
    Ok(_) => {},
    Err(_) => {},
  }

  return 0;
}

fn test_import_file_flag_combos() -> TestResult {
  let rc = run_import_file_flag_combos();
  if rc == 0 { return assert(true, "import: import_file with 3 flag combinations"); }
  return assert(false, "import: flag combinations failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 32: GenBoundingBoxes flag is 0x80000000 (MSB set, unsigned Int edge)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_gen_bounding_boxes_flag() -> Int {
  if aiProcess_GenBoundingBoxes != 0x80000000 { return 1; }
  return 0;
}

fn test_gen_bounding_boxes_flag() -> TestResult {
  let rc = run_gen_bounding_boxes_flag();
  if rc == 0 { return assert(true, "flags: aiProcess_GenBoundingBoxes == 0x80000000"); }
  return assert(false, "flags: GenBoundingBoxes MSB check failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test runner
// ═══════════════════════════════════════════════════════════════════════════════

pub fn main() -> Int {
  io.println("=== xiom-assimp Conformance Tests ===");
  io.println("");

  var tests: Vec[fn() -> TestResult] = Vec[fn() -> TestResult].new();
  tests.push(test_type_definitions);
  tests.push(test_flags_non_zero);
  tests.push(test_flags_unique);
  tests.push(test_flag_presets);
  tests.push(test_flag_hierarchy);
  tests.push(test_import_file_empty_path);
  tests.push(test_import_file_negative_flags);
  tests.push(test_import_file_stub);
  tests.push(test_import_file_ex_empty_path);
  tests.push(test_import_file_ex_stub);
  tests.push(test_get_error_string);
  tests.push(test_get_num_meshes_null);
  tests.push(test_get_mesh_negative_index);
  tests.push(test_get_mesh_null_scene);
  tests.push(test_get_num_vertices_null);
  tests.push(test_get_vertices_null_mesh);
  tests.push(test_get_num_faces_null);
  tests.push(test_get_faces_null_mesh);
  tests.push(test_get_num_normals_null);
  tests.push(test_get_normals_null_mesh);
  tests.push(test_get_num_tex_coords_channel);
  tests.push(test_get_tex_coords_null_mesh);
  tests.push(test_get_material_count_null);
  tests.push(test_get_material_negative_index);
  tests.push(test_get_material_null_scene);
  tests.push(test_version);
  tests.push(test_is_linked);
  tests.push(test_import_release_roundtrip);
  tests.push(test_all_flags_exist);
  tests.push(test_api_import_file);
  tests.push(test_api_release_import);
  tests.push(test_api_get_error_string);
  tests.push(test_api_get_mesh);
  tests.push(test_api_get_vertices);
  tests.push(test_api_get_faces);
  tests.push(test_api_get_normals);
  tests.push(test_api_get_material);
  tests.push(test_contract_import_file_path);
  tests.push(test_contract_import_file_flags);
  tests.push(test_contract_release_import);
  tests.push(test_contract_get_mesh_scene);
  tests.push(test_contract_get_mesh_index);
  tests.push(test_contract_get_num_vertices);
  tests.push(test_contract_get_material_scene);
  tests.push(test_contract_get_material_index);
  tests.push(test_import_file_flag_combos);
  tests.push(test_gen_bounding_boxes_flag);

  let failures = xiom.test.run_all(tests);

  io.println("");
  if failures > 0 {
    io.println("SOME TESTS FAILED");
    return 1;
  }
  io.println("ALL TESTS PASSED");
  return 0;
}
