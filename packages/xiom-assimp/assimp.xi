// XIOM -- xiom.assimp: assimp v6.0.5 bindings (vendored core + OBJ/STL/PLY/
// glTF2/COLLADA/FBX/BLEND/OFF/SMD importers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C++ subset (the ozz/sqlite pattern, generated).  The
// upstream `include/assimp/**` + `code/**` trees plus the needed contribs
// (zlib, earcut-hpp, utf8cpp, rapidjson, pugixml, poly2tri) are mirrored into
// `vendor/`
// and every include that resolves to a vendored header is rewritten to an
// exact relative path by `tools/combine.py` (the xiom link line has no -I
// passthrough).  `vendor/include/assimp/config.h` is generated from the
// upstream `config.h.in` templates with the subset's importer switches.  The
// selected TUs (core + Material + PostProcessing + the enabled importer
// dirs + contribs; 125 TUs) compile into the test binary with --c-source
// (port.args.json); no system library, no SDK.
//
// The module calls a scalar-return C++ bridge (src/assimp_bridge.cpp) that
// imports in-memory assets (OBJ, PLY, glTF2, COLLADA, FBX, BLEND, OFF,
// SMD).  All
// `unsafe`/`extern "C"` live in this single module (G5).
//
// G2 pin (SPEC.md): upstream tag v6.0.5 (commit 392a658f) + generator +
// generated-tree sha256; nothing on the network at build time.
//
// API subset (pilot): version + eight in-memory imports proving the importer
// pipeline (OBJ, PLY, glTF2, COLLADA, FBX, BLEND, OFF, SMD).  0.8.0 adds
// file-based import + mesh-data getters (engine P4 asset pipeline).  STL is
// included in the compiled set; full format breadth, post-processing
// wrappers, and the export API are later Phase 3 items (ROADMAP.md).

module xiom.assimp

extern "C" {
  fn assimprobe_version() -> Int32;
  fn assimprobe_obj() -> Int32;
  fn assimprobe_meshes() -> Int32;
  fn assimprobe_vertices() -> Int32;
  fn assimprobe_faces() -> Int32;
  fn assimprobe_ply() -> Int32;
  fn assimprobe_ply_vertices() -> Int32;
  fn assimprobe_gltf() -> Int32;
  fn assimprobe_gltf_vertices() -> Int32;
  fn assimprobe_collada() -> Int32;
  fn assimprobe_collada_vertices() -> Int32;
  fn assimprobe_fbx() -> Int32;
  fn assimprobe_fbx_vertices() -> Int32;
  fn assimprobe_blend() -> Int32;
  fn assimprobe_blend_meshes() -> Int32;
  fn assimprobe_blend_vertices() -> Int32;
  fn assimprobe_blend_faces() -> Int32;
  fn assimprobe_off() -> Int32;
  fn assimprobe_off_meshes() -> Int32;
  fn assimprobe_off_vertices() -> Int32;
  fn assimprobe_off_faces() -> Int32;
  fn assimprobe_smd() -> Int32;
  fn assimprobe_smd_meshes() -> Int32;
  fn assimprobe_smd_vertices() -> Int32;
  fn assimprobe_smd_faces() -> Int32;
  fn assimprobe_error() -> *UInt8;
  fn assimbridge_import_file(path: *UInt8) -> Int32;
  fn assimbridge_release(handle: Int);
  fn assimbridge_mesh_count(handle: Int) -> Int32;
  fn assimbridge_mesh_vertex_count(handle: Int, mesh: Int) -> Int32;
  fn assimbridge_mesh_triangle_count(handle: Int, mesh: Int) -> Int32;
  fn assimbridge_mesh_has_uvs(handle: Int, mesh: Int) -> Int32;
  fn assimbridge_copy_positions(handle: Int, mesh: Int, out: *UInt8, max_bytes: Int) -> Int32;
  fn assimbridge_copy_uvs(handle: Int, mesh: Int, out: *UInt8, max_bytes: Int) -> Int32;
  fn assimbridge_copy_indices(handle: Int, mesh: Int, out: *UInt8, max_bytes: Int) -> Int32;
  fn assimbridge_error() -> *UInt8;
}

pub type AssimpInfo = {
  version: Int;
  obj_meshes: Int;
  obj_vertices: Int;
  obj_faces: Int;
  ply_vertices: Int;
  gltf_vertices: Int;
  collada_vertices: Int;
  fbx_vertices: Int;
  blend_meshes: Int;
  blend_vertices: Int;
  blend_faces: Int;
  off_meshes: Int;
  off_vertices: Int;
  off_faces: Int;
  smd_meshes: Int;
  smd_vertices: Int;
  smd_faces: Int;
}

/// Packed upstream version: major * 10000 + minor * 100 + revision, where
/// the revision field is assimp's GitVersion value (0 for this pinned
/// tarball build -- the real patch level 5 is pinned in
/// `vendor/include/assimp/revision.h`).  Complexity: O(1).
pub fn assimp_version() -> Int
  requires: true
{
  unsafe { return assimprobe_version() as Int; }
}

/// Decode a packed version into "major.minor.revision" (see
/// `assimp_version` for the revision-field note).  Complexity: O(1).
pub fn assimp_version_str(v: Int) -> Str
  requires: v >= 0
{
  let major = v / 10000;
  let minor = (v / 100) % 100;
  let revision = v % 100;
  return assimp_i2s(major) + "." + assimp_i2s(minor) + "." + assimp_i2s(revision);
}

/// Import the built-in in-memory OBJ, PLY, glTF2, COLLADA, FBX, BLEND, OFF,
/// and SMD probes and report the scene counts.  Complexity: O(import).
pub fn assimp_probe() -> Result[AssimpInfo, Str]
  requires: true
{
  let obj_rc = unsafe { assimprobe_obj() as Int };
  if obj_rc != 0 {
    return Err(assimp_error("obj", obj_rc));
  }
  let ply_rc = unsafe { assimprobe_ply() as Int };
  if ply_rc != 0 {
    return Err(assimp_error("ply", ply_rc));
  }
  let gltf_rc = unsafe { assimprobe_gltf() as Int };
  if gltf_rc != 0 {
    return Err(assimp_error("gltf", gltf_rc));
  }
  let collada_rc = unsafe { assimprobe_collada() as Int };
  if collada_rc != 0 {
    return Err(assimp_error("collada", collada_rc));
  }
  let fbx_rc = unsafe { assimprobe_fbx() as Int };
  if fbx_rc != 0 {
    return Err(assimp_error("fbx", fbx_rc));
  }
  let blend_rc = unsafe { assimprobe_blend() as Int };
  if blend_rc != 0 {
    return Err(assimp_error("blend", blend_rc));
  }
  let off_rc = unsafe { assimprobe_off() as Int };
  if off_rc != 0 {
    return Err(assimp_error("off", off_rc));
  }
  let smd_rc = unsafe { assimprobe_smd() as Int };
  if smd_rc != 0 {
    return Err(assimp_error("smd", smd_rc));
  }
  return Ok(AssimpInfo{
    version: unsafe { assimprobe_version() as Int };
    obj_meshes: unsafe { assimprobe_meshes() as Int };
    obj_vertices: unsafe { assimprobe_vertices() as Int };
    obj_faces: unsafe { assimprobe_faces() as Int };
    ply_vertices: unsafe { assimprobe_ply_vertices() as Int };
    gltf_vertices: unsafe { assimprobe_gltf_vertices() as Int };
    collada_vertices: unsafe { assimprobe_collada_vertices() as Int };
    fbx_vertices: unsafe { assimprobe_fbx_vertices() as Int };
    blend_meshes: unsafe { assimprobe_blend_meshes() as Int };
    blend_vertices: unsafe { assimprobe_blend_vertices() as Int };
    blend_faces: unsafe { assimprobe_blend_faces() as Int };
    off_meshes: unsafe { assimprobe_off_meshes() as Int };
    off_vertices: unsafe { assimprobe_off_vertices() as Int };
    off_faces: unsafe { assimprobe_off_faces() as Int };
    smd_meshes: unsafe { assimprobe_smd_meshes() as Int };
    smd_vertices: unsafe { assimprobe_smd_vertices() as Int };
    smd_faces: unsafe { assimprobe_smd_faces() as Int };
  });
}

// =========================================================================
// 0.8.0: file-based import + mesh-data getters (engine P4 asset pipeline)
//
// Path-based import so assimp does its own I/O (keeps the read_file_bytes
// miscompile class out of the loop); imports run with Triangulate + FlipUVs.
// Getters hand back XIOM-owned Vecs: positions Vec[Float64] (xyz triples),
// uvs Vec[Float64] (uv pairs; empty when the mesh has no UV channel),
// indices Vec[UInt32] (3 per triangle, post-triangulate).  Bridge memory is
// read with Int-typed address math (B-17: no pointer arithmetic) and f32
// bits are decoded arithmetically (B-12: no fp cast-call returns).
// =========================================================================

/// Import a file from disk with Triangulate + FlipUVs -> handle (> 0).
/// Release with `assimp_release`; the registry holds 4 live imports.
/// Complexity: O(import).
pub fn assimp_import_file(path: Str) -> Result[Int, Str]
  requires: path.len() > 0
{
  unsafe {
    let h = assimbridge_import_file(path.c_str()) as Int;
    if h <= 0 {
      return Err(assimp_bridge_error("import"));
    }
    return Ok(h);
  }
}

/// Release an import handle (frees the scene; idempotent for stale handles).
/// Complexity: O(free).
pub fn assimp_release(handle: Int)
  requires: handle > 0
{
  unsafe {
    assimbridge_release(handle);
  }
}

/// Mesh count of an import (0 for an invalid/released handle).
/// Complexity: O(1).
pub fn assimp_mesh_count(handle: Int) -> Int
  requires: handle > 0
{
  unsafe { return assimbridge_mesh_count(handle) as Int; }
}

/// Vertex count of a mesh (0 for invalid handle/mesh).
/// Complexity: O(1).
pub fn assimp_mesh_vertex_count(handle: Int, mesh: Int) -> Int
  requires: handle > 0
  requires: mesh >= 0
{
  unsafe { return assimbridge_mesh_vertex_count(handle, mesh) as Int; }
}

/// Triangle count of a mesh (post-triangulate; 0 for invalid handle/mesh).
/// Complexity: O(triangles).
pub fn assimp_mesh_triangle_count(handle: Int, mesh: Int) -> Int
  requires: handle > 0
  requires: mesh >= 0
{
  unsafe { return assimbridge_mesh_triangle_count(handle, mesh) as Int; }
}

/// True when the mesh carries UV channel 0.
/// Complexity: O(1).
pub fn assimp_mesh_has_uvs(handle: Int, mesh: Int) -> Bool
  requires: handle > 0
  requires: mesh >= 0
{
  unsafe { return (assimbridge_mesh_has_uvs(handle, mesh) as Int) != 0; }
}

/// Object-space positions: 3 floats per vertex (x,y,z triples), empty for
/// an invalid handle/mesh.  The bridge copies into an owned slot and the
/// bytes are read byte-indexed (the B-16/B-17-safe path).
/// Complexity: O(vertices).
pub fn assimp_mesh_positions(handle: Int, mesh: Int) -> Vec[Float64]
  requires: handle > 0
  requires: mesh >= 0
{
  var out: Vec[Float64] = Vec[Float64].new();
  let n = assimp_mesh_vertex_count(handle, mesh);
  if n == 0 { return out; }
  var raw = assimp_slot(n * 12);
  unsafe {
    let copied = assimbridge_copy_positions(handle, mesh, raw.as_mut_ptr(), n * 12) as Int;
    if copied != n * 12 { return out; }
  }
  var i = 0;
  while i < n * 3 {
    out.push(assimp_f32_from_bits(assimp_read_u32_vec(&raw, i * 4)));
    i = i + 1;
  }
  return out;
}

/// Per-vertex UV pairs (2 floats per vertex), empty when the mesh has no
/// UV channel 0 or the handle/mesh is invalid.  Complexity: O(vertices).
pub fn assimp_mesh_uvs(handle: Int, mesh: Int) -> Vec[Float64]
  requires: handle > 0
  requires: mesh >= 0
{
  var out: Vec[Float64] = Vec[Float64].new();
  let n = assimp_mesh_vertex_count(handle, mesh);
  if n == 0 { return out; }
  var raw = assimp_slot(n * 12);
  unsafe {
    let copied = assimbridge_copy_uvs(handle, mesh, raw.as_mut_ptr(), n * 12) as Int;
    if copied != n * 12 { return out; }
  }
  var i = 0;
  while i < n {
    out.push(assimp_f32_from_bits(assimp_read_u32_vec(&raw, i * 12)));
    out.push(assimp_f32_from_bits(assimp_read_u32_vec(&raw, i * 12 + 4)));
    i = i + 1;
  }
  return out;
}

/// Post-triangulate indices (3 per triangle), empty for an invalid
/// handle/mesh.  Complexity: O(triangles).
pub fn assimp_mesh_indices(handle: Int, mesh: Int) -> Vec[UInt32]
  requires: handle > 0
  requires: mesh >= 0
{
  var out: Vec[UInt32] = Vec[UInt32].new();
  let tris = assimp_mesh_triangle_count(handle, mesh);
  if tris == 0 { return out; }
  var raw = assimp_slot(tris * 12);
  unsafe {
    let copied = assimbridge_copy_indices(handle, mesh, raw.as_mut_ptr(), tris * 12) as Int;
    if copied != tris * 12 { return out; }
  }
  var i = 0;
  while i < tris * 3 {
    out.push(assimp_read_u32_vec(&raw, i * 4) as UInt32);
    i = i + 1;
  }
  return out;
}

// ---- internals -----------------------------------------------------------

fn assimp_error(step: Str, rc: Int) -> Str
  requires: rc != 0
{
  unsafe {
    let p = assimprobe_error();
    if (p as Int) != 0 {
      let msg = Str::from_c_str(p);
      if msg.len() > 0 {
        return "assimp: " + step + " import failed: " + msg;
      }
    }
    return "assimp: " + step + " import rc=" + assimp_i2s(0 - rc);
  }
}

fn assimp_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}

fn assimp_bridge_error(step: Str) -> Str
  requires: true
{
  unsafe {
    let p = assimbridge_error();
    if (p as Int) != 0 {
      let msg = Str::from_c_str(p);
      if msg.len() > 0 {
        return "assimp: " + step + " failed: " + msg;
      }
    }
    return "assimp: " + step + " failed";
  }
}

/// Zero-filled owned byte slot of `n` bytes (for foreign out-params).
fn assimp_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Little-endian u32 read from an owned byte slot (byte-indexed; the
/// B-16/B-17-safe read path for foreign-written data).
fn assimp_read_u32_vec(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// IEEE-754 binary32 bits -> Float64 (pure arithmetic).  Complexity: O(1).
fn assimp_f32_from_bits(bits: Int) -> Float64
  requires: bits >= 0
  requires: bits <= 0xFFFFFFFF
{
  let sign = if ((bits >> 31) & 1) == 1 { -1.0 } else { 1.0 };
  let exp = (bits >> 23) & 0xFF;
  let frac = bits & 0x7FFFFF;
  if exp == 0 {
    if frac == 0 { return sign * 0.0; }
    return sign * (frac as Float64) * assimp_pow2i(-149);
  }
  if exp == 255 { return 0.0; }
  return sign * (1.0 + (frac as Float64) / 8388608.0) * assimp_pow2i(exp - 127);
}

fn assimp_pow2i(e: Int) -> Float64
  requires: e >= -1074
  requires: e <= 1024
{
  var r = 1.0;
  var i = e;
  while i > 0 {
    r = r * 2.0;
    i = i - 1;
  }
  while i < 0 {
    r = r / 2.0;
    i = i + 1;
  }
  return r;
}
