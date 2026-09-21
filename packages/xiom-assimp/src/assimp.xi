// XIOM -- Assimp (Open Asset Import Library) Bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Production-grade Assimp bindings for 3D model import in the XIOM ecosystem.
// Wraps the Assimp C API (aiImportFile, aiReleaseImport, scene/mesh queries)
// with safe wrappers, design-by-contract, and comprehensive post-processing flags.
//
// Phase 1 (v0.1.0): Raw extern "C" stubs + safe wrappers + contracts
// Phase 2 (future):  Material properties, animation/bone extraction, scene graph traversal
//
// Links against system-installed libassimp at link time.

module xiom.assimp

// ===============================================================================
// Types -- Opaque handles for Assimp data structures
// ===============================================================================

pub type AiScene     = Int;
pub type AiMesh      = Int;
pub type AiMaterial  = Int;
pub type AiAnimation = Int;
pub type AiNode      = Int;

// ===============================================================================
// Post-processing flag constants
//
// Bitmask flags passed to aiImportFile / aiImportFileEx to control
// mesh processing. Combine with bitwise OR: Triangulate | FlipUVs.
// ===========================================================================
// aiProcess_CalcTangentSpace         = 0x1     (1)
// aiProcess_JoinIdenticalVertices    = 0x2     (2)
// aiProcess_MakeLeftHanded           = 0x4     (4)
// aiProcess_Triangulate              = 0x8     (8)
// aiProcess_RemoveComponent          = 0x10   (16)
// aiProcess_GenNormals               = 0x20   (32)
// aiProcess_GenSmoothNormals         = 0x40   (64)
// aiProcess_SplitLargeMeshes         = 0x80  (128)
// aiProcess_PreTransformVertices     = 0x100 (256)
// aiProcess_LimitBoneWeights         = 0x200 (512)
// aiProcess_ValidateDataStructure    = 0x400 (1024)
// aiProcess_ImproveCacheLocality     = 0x800 (2048)
// aiProcess_RemoveRedundantMaterials = 0x1000 (4096)
// aiProcess_FixInfacingNormals       = 0x2000 (8192)
// aiProcess_PopulateArmatureData     = 0x4000 (16384)
// aiProcess_SortByPType              = 0x8000 (32768)
// aiProcess_FindDegenerates          = 0x10000 (65536)
// aiProcess_FindInvalidData          = 0x20000 (131072)
// aiProcess_GenUVCoords              = 0x40000 (262144)
// aiProcess_TransformUVCoords        = 0x80000 (524288)
// aiProcess_FindInstances            = 0x100000 (1048576)
// aiProcess_OptimizeMeshes           = 0x200000 (2097152)
// aiProcess_OptimizeGraph            = 0x400000 (4194304)
// aiProcess_FlipUVs                  = 0x800000 (8388608)
// aiProcess_FlipWindingOrder         = 0x1000000 (16777216)
// aiProcess_SplitByBoneCount         = 0x2000000 (33554432)
// aiProcess_Debone                   = 0x4000000 (67108864)
// aiProcess_GlobalScale              = 0x8000000 (134217728)
// aiProcess_EmbedTextures            = 0x10000000 (268435456)
// aiProcess_ForceGenNormals          = 0x20000000 (536870912)
// aiProcess_DropNormals              = 0x40000000 (1073741824)
// aiProcess_GenBoundingBoxes         = 0x80000000 (2147483648)
// ===============================================================================

pub const aiProcess_CalcTangentSpace:         Int = 0x1;
pub const aiProcess_JoinIdenticalVertices:    Int = 0x2;
pub const aiProcess_MakeLeftHanded:           Int = 0x4;
pub const aiProcess_Triangulate:              Int = 0x8;
pub const aiProcess_RemoveComponent:          Int = 0x10;
pub const aiProcess_GenNormals:               Int = 0x20;
pub const aiProcess_GenSmoothNormals:         Int = 0x40;
pub const aiProcess_SplitLargeMeshes:         Int = 0x80;
pub const aiProcess_PreTransformVertices:     Int = 0x100;
pub const aiProcess_LimitBoneWeights:         Int = 0x200;
pub const aiProcess_ValidateDataStructure:    Int = 0x400;
pub const aiProcess_ImproveCacheLocality:     Int = 0x800;
pub const aiProcess_RemoveRedundantMaterials: Int = 0x1000;
pub const aiProcess_FixInfacingNormals:       Int = 0x2000;
pub const aiProcess_SortByPType:              Int = 0x8000;
pub const aiProcess_FindDegenerates:          Int = 0x10000;
pub const aiProcess_FindInvalidData:          Int = 0x20000;
pub const aiProcess_GenUVCoords:              Int = 0x40000;
pub const aiProcess_TransformUVCoords:        Int = 0x80000;
pub const aiProcess_FindInstances:            Int = 0x100000;
pub const aiProcess_OptimizeMeshes:           Int = 0x200000;
pub const aiProcess_OptimizeGraph:            Int = 0x400000;
pub const aiProcess_FlipUVs:                  Int = 0x800000;
pub const aiProcess_FlipWindingOrder:         Int = 0x1000000;
pub const aiProcess_SplitByBoneCount:         Int = 0x2000000;
pub const aiProcess_Debone:                   Int = 0x4000000;
pub const aiProcess_GlobalScale:              Int = 0x8000000;
pub const aiProcess_EmbedTextures:            Int = 0x10000000;
pub const aiProcess_ForceGenNormals:          Int = 0x20000000;
pub const aiProcess_DropNormals:              Int = 0x40000000;
pub const aiProcess_GenBoundingBoxes:         Int = 0x80000000;

// ===============================================================================
// Commonly used flag presets
// ===============================================================================

// Default: Triangulate | FlipUVs | CalcTangentSpace
pub const aiProcessPreset_Default: Int = 0x800009;

// Fast: CalcTangentSpace | GenNormals | JoinIdenticalVertices | Triangulate | GenUVCoords | SortByPType
pub const aiProcessPreset_TargetRealtimeFast: Int = 0x4802B;

// Quality: CalcTangentSpace | GenSmoothNormals | JoinIdenticalVertices | ImproveCacheLocality |
//          LimitBoneWeights | RemoveRedundantMaterials | SplitLargeMeshes | Triangulate |
//          GenUVCoords | SortByPType | FindInvalidData | FindDegenerates
pub const aiProcessPreset_TargetRealtimeQuality: Int = 0x78ECB;

// MaxQuality: Quality | FindInstances | ValidateDataStructure | OptimizeMeshes
pub const aiProcessPreset_TargetRealtimeMaxQuality: Int = 0x378ECB;

// ===============================================================================
// Raw C API -- extern "C" stubs
// ===============================================================================

extern "C" {
  fn aiImportFile(file: Str, flags: Int) -> Int;
  fn aiImportFileEx(file: Str, flags: Int, fs: Int) -> Int;
  fn aiReleaseImport(scene: Int);
  fn aiGetErrorString() -> Str;
  fn aiGetNumMeshes(scene: Int) -> Int;
  fn aiGetMesh(scene: Int, index: Int) -> Int;
  fn aiGetNumVertices(mesh: Int) -> Int;
  fn aiGetVertices(mesh: Int) -> *Float32;
  fn aiGetNumFaces(mesh: Int) -> Int;
  fn aiGetFaces(mesh: Int) -> Int;
  fn aiGetNumNormals(mesh: Int) -> Int;
  fn aiGetNormals(mesh: Int) -> *Float32;
  fn aiGetNumTexCoords(mesh: Int, channel: Int) -> Int;
  fn aiGetTexCoords(mesh: Int) -> *Float32;
  fn aiGetMaterialCount(scene: Int) -> Int;
  fn aiGetMaterial(scene: Int, index: Int) -> Int;
}

// ===============================================================================
// Safe wrappers -- Scene import / release
// ===============================================================================

pub fn import_file(path: Str, flags: Int) -> Result[AiScene, Str]
  requires: path.len() > 0
  requires: flags >= 0
{
  if path.len() == 0 { return Err("import_file: path must not be empty"); }
  if flags < 0 { return Err("import_file: flags must be non-negative"); }
  unsafe {
    let scene: Int = aiImportFile(path, flags);
    if scene == 0 {
      return Err("import_file: failed to import -- library not linked or invalid file");
    }
    Ok(scene)
  }
}

pub fn import_file_ex(path: Str, flags: Int, fs: Int) -> Result[AiScene, Str]
  requires: path.len() > 0
  requires: flags >= 0
{
  if path.len() == 0 { return Err("import_file_ex: path must not be empty"); }
  if flags < 0 { return Err("import_file_ex: flags must be non-negative"); }
  unsafe {
    let scene: Int = aiImportFileEx(path, flags, fs);
    if scene == 0 {
      return Err("import_file_ex: failed to import")
    }
    Ok(scene)
  }
}

pub fn release_import(scene: AiScene)
  requires: scene != 0
{
  unsafe { aiReleaseImport(scene); }
}

// ===============================================================================
// Safe wrappers -- Error reporting
// ===============================================================================

pub fn get_error_string() -> Str
{
  unsafe {
    let err = aiGetErrorString();
    if err == "" {
      return "unknown error";
    }
    return err;
  }
}

// ===============================================================================
// Safe wrappers -- Scene queries
// ===============================================================================

pub fn get_num_meshes(scene: AiScene) -> Int
  requires: scene != 0
{
  unsafe { return aiGetNumMeshes(scene); }
}

pub fn get_mesh(scene: AiScene, index: Int) -> Result[AiMesh, Str]
  requires: scene != 0
  requires: index >= 0
{
  if index < 0 { return Err("get_mesh: index must be non-negative"); }
  let num = get_num_meshes(scene);
  if index >= num {
    return Err("get_mesh: mesh index out of bounds");
  }
  unsafe {
    let mesh: Int = aiGetMesh(scene, index);
    if mesh == 0 {
      return Err("get_mesh: null mesh pointer");
    }
    Ok(mesh)
  }
}

pub fn get_material_count(scene: AiScene) -> Int
  requires: scene != 0
{
  unsafe { return aiGetMaterialCount(scene); }
}

pub fn get_material(scene: AiScene, index: Int) -> Result[AiMaterial, Str]
  requires: scene != 0
  requires: index >= 0
{
  if index < 0 { return Err("get_material: index must be non-negative"); }
  let count = get_material_count(scene);
  if index >= count {
    return Err("get_material: material index out of bounds");
  }
  unsafe {
    let mat: Int = aiGetMaterial(scene, index);
    if mat == 0 {
      return Err("get_material: null material pointer");
    }
    Ok(mat)
  }
}

// ===============================================================================
// Safe wrappers -- Mesh queries
// ===============================================================================

pub fn get_num_vertices(mesh: AiMesh) -> Int
  requires: mesh != 0
{
  unsafe { return aiGetNumVertices(mesh); }
}

pub fn get_vertices(mesh: AiMesh) -> Result<*Float32, Str>
  requires: mesh != 0
{
  let num = get_num_vertices(mesh);
  if num == 0 { return Err("get_vertices: mesh has no vertices"); }
  unsafe {
    let ptr: *Float32 = aiGetVertices(mesh);
    if ptr == 0 {
      return Err("get_vertices: null vertex buffer pointer");
    }
    Ok(ptr)
  }
}

pub fn get_num_faces(mesh: AiMesh) -> Int
  requires: mesh != 0
{
  unsafe { return aiGetNumFaces(mesh); }
}

pub fn get_faces(mesh: AiMesh) -> Result<Int, Str>
  requires: mesh != 0
{
  let num = get_num_faces(mesh);
  if num == 0 { return Err("get_faces: mesh has no faces"); }
  unsafe {
    let ptr: Int = aiGetFaces(mesh);
    if ptr == 0 {
      return Err("get_faces: null face buffer pointer");
    }
    Ok(ptr)
  }
}

pub fn get_num_normals(mesh: AiMesh) -> Int
  requires: mesh != 0
{
  unsafe { return aiGetNumNormals(mesh); }
}

pub fn get_normals(mesh: AiMesh) -> Result<*Float32, Str>
  requires: mesh != 0
{
  let num = get_num_normals(mesh);
  if num == 0 { return Err("get_normals: mesh has no normals"); }
  unsafe {
    let ptr: *Float32 = aiGetNormals(mesh);
    if ptr == 0 {
      return Err("get_normals: null normal buffer pointer");
    }
    Ok(ptr)
  }
}

pub fn get_num_tex_coords(mesh: AiMesh, channel: Int) -> Int
  requires: mesh != 0
  requires: channel >= 0
{
  if channel < 0 { return 0; }
  unsafe { return aiGetNumTexCoords(mesh, channel); }
}

pub fn get_tex_coords(mesh: AiMesh) -> Result<*Float32, Str>
  requires: mesh != 0
{
  unsafe {
    let ptr: *Float32 = aiGetTexCoords(mesh);
    if ptr == 0 {
      return Err("get_tex_coords: null texcoord buffer pointer");
    }
    Ok(ptr)
  }
}

// ===============================================================================
// Utility
// ===============================================================================

pub fn version() -> Str {
  "0.1.0"
}

pub fn is_linked() -> Bool {
  false
}
