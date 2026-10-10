// xiom.assimp conformance suite -- vendored assimp v6.0.5 (OBJ/STL/PLY subset).
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

  // 2. In-memory OBJ + PLY + glTF2 imports.
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
  } else {
    failed = failed + report(false, "imports: " + p.error);
  }

  // 3. Determinism: a repeated probe yields identical counts.
  let p2 = assimp_probe();
  let same = p.is_ok && p2.is_ok
    && p2.value.obj_vertices == p.value.obj_vertices
    && p2.value.ply_vertices == p.value.ply_vertices
    && p2.value.gltf_vertices == p.value.gltf_vertices
    && p2.value.collada_vertices == p.value.collada_vertices;
  failed = failed + report(same, "determinism: repeated imports identical");

  if failed == 0 {
    io.println("xiom.assimp: all tests passed");
  } else {
    io.println("xiom.assimp: tests failed");
  }
  return failed;
}
