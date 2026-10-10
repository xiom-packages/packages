// XIOM -- xiom.assimp: assimp v6.0.5 bindings (vendored core + OBJ/STL/PLY/
// glTF2/COLLADA/FBX importers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C++ subset (the ozz/sqlite pattern, generated).  The
// upstream `include/assimp/**` + `code/**` trees plus the needed contribs
// (zlib, earcut-hpp, utf8cpp, rapidjson, pugixml) are mirrored into `vendor/`
// and every include that resolves to a vendored header is rewritten to an
// exact relative path by `tools/combine.py` (the xiom link line has no -I
// passthrough).  `vendor/include/assimp/config.h` is generated from the
// upstream `config.h.in` templates with the subset's importer switches.  The
// selected TUs (core + Material + PostProcessing + the enabled importer
// dirs + contribs; 111 TUs) compile into the test binary with --c-source
// (port.args.json); no system library, no SDK.
//
// The module calls a scalar-return C++ bridge (src/assimp_bridge.cpp) that
// imports in-memory assets (OBJ, PLY, glTF2, COLLADA, FBX).  All
// `unsafe`/`extern "C"` live in this single module (G5).
//
// G2 pin (SPEC.md): upstream tag v6.0.5 (commit 392a658f) + generator +
// generated-tree sha256; nothing on the network at build time.
//
// API subset (pilot): version + five in-memory imports proving the importer
// pipeline (OBJ, PLY, glTF2, COLLADA, FBX).  STL is included in the compiled
// set; full format breadth, post-processing wrappers, and the export API are
// Phase 2 (ROADMAP.md).

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
  fn assimprobe_error() -> *UInt8;
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

/// Import the built-in in-memory OBJ, PLY, glTF2, COLLADA, and FBX probes
/// and report the scene counts.  Complexity: O(import).
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
  return Ok(AssimpInfo{
    version: unsafe { assimprobe_version() as Int };
    obj_meshes: unsafe { assimprobe_meshes() as Int };
    obj_vertices: unsafe { assimprobe_vertices() as Int };
    obj_faces: unsafe { assimprobe_faces() as Int };
    ply_vertices: unsafe { assimprobe_ply_vertices() as Int };
    gltf_vertices: unsafe { assimprobe_gltf_vertices() as Int };
    collada_vertices: unsafe { assimprobe_collada_vertices() as Int };
    fbx_vertices: unsafe { assimprobe_fbx_vertices() as Int };
  });
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
