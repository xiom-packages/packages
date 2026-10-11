// xiom.assimp conformance suite -- vendored assimp v6.0.5
// (multiformat subset: OBJ/PLY/glTF2/COLLADA/FBX/BLEND/OFF/SMD probes).
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.assimp

module assimp_conformance

use xiom.io;
use xiom.test;
use xiom.assimp;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
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
  if neg { return "-" + buf; }
  return buf;
}

fn main() -> Int {
  io.println("=== xiom.assimp conformance tests (vendored v6.0.5 subset) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Version pin (v6.0.x).
  let v = assimp_version();
  let major = v / 10000;
  failed = failed + report(major == 6, "version: " + assimp_version_str(v));

  // 2. In-memory OBJ + PLY + glTF2 + COLLADA + FBX imports.
  let p = assimp_probe();
  if p.is_ok {
    failed = failed + report(p.value.obj_meshes == 1 && p.value.obj_vertices == 3
      && p.value.obj_faces == 1,
      "obj: meshes=" + i2s(p.value.obj_meshes) + " vertices=" + i2s(p.value.obj_vertices)
        + " faces=" + i2s(p.value.obj_faces));
    failed = failed + report(p.value.ply_vertices == 3,
      "ply: vertices=" + i2s(p.value.ply_vertices));
    failed = failed + report(p.value.gltf_vertices == 3,
      "gltf2: vertices=" + i2s(p.value.gltf_vertices));
    failed = failed + report(p.value.collada_vertices == 3,
      "collada: vertices=" + i2s(p.value.collada_vertices));
    failed = failed + report(p.value.fbx_vertices == 3,
      "fbx: vertices=" + i2s(p.value.fbx_vertices));
    failed = failed + report(p.value.blend_meshes == 1 && p.value.blend_vertices == 24
      && p.value.blend_faces == 6,
      "blend: meshes=" + i2s(p.value.blend_meshes) + " vertices=" + i2s(p.value.blend_vertices)
        + " faces=" + i2s(p.value.blend_faces));
    failed = failed + report(p.value.off_meshes == 1 && p.value.off_vertices == 3
      && p.value.off_faces == 1,
      "off: meshes=" + i2s(p.value.off_meshes) + " vertices=" + i2s(p.value.off_vertices)
        + " faces=" + i2s(p.value.off_faces));
    failed = failed + report(p.value.smd_meshes == 1 && p.value.smd_vertices == 3
      && p.value.smd_faces == 1,
      "smd: meshes=" + i2s(p.value.smd_meshes) + " vertices=" + i2s(p.value.smd_vertices)
        + " faces=" + i2s(p.value.smd_faces));
  } else {
    failed = failed + report(false, "imports: " + p.error);
  }

  // 3. Determinism: a repeated probe yields identical counts.
  let p2 = assimp_probe();
  let same = p.is_ok && p2.is_ok
    && p2.value.obj_vertices == p.value.obj_vertices
    && p2.value.ply_vertices == p.value.ply_vertices
    && p2.value.gltf_vertices == p.value.gltf_vertices
    && p2.value.collada_vertices == p.value.collada_vertices
    && p2.value.fbx_vertices == p.value.fbx_vertices
    && p2.value.blend_vertices == p.value.blend_vertices
    && p2.value.off_vertices == p.value.off_vertices
    && p2.value.smd_vertices == p.value.smd_vertices;
  failed = failed + report(same, "determinism: repeated imports identical");

  // 4. 0.8.0: file-based import + mesh-data getters (engine P4 shape).
  let imp = assimp_import_file("tests/fixtures/quad_uv.obj");
  if imp.is_ok {
    let h = imp.value;
    let mc = assimp_mesh_count(h);
    let vc = assimp_mesh_vertex_count(h, 0);
    let tc = assimp_mesh_triangle_count(h, 0);
    let hu = assimp_mesh_has_uvs(h, 0);
    failed = failed + report(mc == 1 && vc == 4 && tc == 2 && hu,
      "file-import: quad_uv.obj handle=" + i2s(h) + " meshes=" + i2s(mc)
        + " verts=" + i2s(vc) + " tris=" + i2s(tc) + " uvs=" + b2s(hu));

    let pos = assimp_mesh_positions(h, 0);
    let pos_ok = pos.len() == 12
      && pos[0] == 0.0 && pos[1] == 0.0 && pos[2] == 0.0
      && pos[6] == 1.0 && pos[7] == 1.0 && pos[8] == 0.0;
    failed = failed + report(pos_ok,
      "file-import: positions " + i2s(pos.len()) + " [p0=" + i2s(pos[0] as Int)
        + " p1=" + i2s(pos[1] as Int) + " p2=" + i2s(pos[2] as Int)
        + " p3=" + i2s(pos[3] as Int) + " p6=" + i2s(pos[6] as Int)
        + " p7=" + i2s(pos[7] as Int) + " p8=" + i2s(pos[8] as Int)
        + " p9=" + i2s(pos[9] as Int) + "]");

    let uvs = assimp_mesh_uvs(h, 0);
    // aiProcess_FlipUVs flips V: vt(0,0)->(0,1), (1,0)->(1,1), (1,1)->(1,0),
    // (0,1)->(0,0).
    let uvs_ok = uvs.len() == 8 && uvs[0] == 0.0 && uvs[1] == 1.0
      && uvs[2] == 1.0 && uvs[3] == 1.0 && uvs[6] == 0.0 && uvs[7] == 0.0;
    failed = failed + report(uvs_ok,
      "file-import: uvs " + i2s(uvs.len()) + " [u0=" + i2s(uvs[0] as Int)
        + " v0=" + i2s(uvs[1] as Int) + " u1=" + i2s(uvs[2] as Int)
        + " v1=" + i2s(uvs[3] as Int) + " u3=" + i2s(uvs[6] as Int)
        + " v3=" + i2s(uvs[7] as Int) + "]");

    let idx = assimp_mesh_indices(h, 0);
    var idx_ok = idx.len() == 6;
    var has0 = false;
    var has1 = false;
    var has2 = false;
    var has3 = false;
    var k = 0;
    while k < idx.len() {
      let e = idx[k] as Int;
      if e < 0 || e > 3 { idx_ok = false; }
      if e == 0 { has0 = true; }
      if e == 1 { has1 = true; }
      if e == 2 { has2 = true; }
      if e == 3 { has3 = true; }
      k = k + 1;
    }
    idx_ok = idx_ok && has0 && has1 && has2 && has3;
    if idx_ok {
      if idx[0] == idx[1] || idx[1] == idx[2] || idx[0] == idx[2] { idx_ok = false; }
      if idx[3] == idx[4] || idx[4] == idx[5] || idx[3] == idx[5] { idx_ok = false; }
    }
    failed = failed + report(idx_ok,
      "file-import: indices " + i2s(idx.len()) + " entries covering 4 verts, non-degenerate");

    assimp_release(h);
    let after = assimp_mesh_count(h);
    failed = failed + report(after == 0,
      "file-import: release invalidates handle (mesh_count=" + i2s(after) + ")");
  } else {
    failed = failed + report(false, "file-import: " + imp.error);
  }

  // 5. Failure shape: a missing file must yield Err with a message.
  let missing = assimp_import_file("tests/fixtures/definitely_missing.obj");
  var merr = "unexpected ok";
  if !missing.is_ok { merr = missing.error; }
  failed = failed + report(!missing.is_ok && merr.len() > 0,
    "file-import: missing file -> Err (" + merr + ")");

  if failed == 0 {
    io.println("xiom.assimp: all tests passed");
  } else {
    io.println("xiom.assimp: tests failed");
  }
  return failed;
}
