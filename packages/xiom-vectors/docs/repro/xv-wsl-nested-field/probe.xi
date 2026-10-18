// XVC-C-09 repro (revision-pinned to commit bca8b7f; see README.md): on WSL
// the engine_set_index call segfaults there, while the inlined steps in this
// probe are green. At the fix commit and later everything is green.
module probe_wsl_nested_field

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.index.hnsw;
use xiom.vectors;
use xiom.io;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = ""; var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  if neg { out = "-" + out; }
  return out;
}

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn rand_coords(state: Int, dim: Int, coords: &mut Vec[Float32]) -> Int {
  var s = state;
  var i: Int = 0;
  while i < dim {
    s = lcg_next(s);
    var c = (s % 4001) as Float32;
    coords.push(c / 1000.0 - 2.0);
    i = i + 1;
  }
  return s;
}

fn vec_from_coords(coords: &Vec[Float32]) -> Vector {
  var v = Vector.new(coords.len());
  var i: Int = 0;
  while i < coords.len() {
    v.set(i, coords[i]);
    i = i + 1;
  }
  return v;
}

fn main() -> Int {
  var ann = engine_new();
  create_collection(&mut ann, 8, DistanceMetric.Euclidean);
  var st: Int = 777333111;
  var i: Int = 0;
  while i < 150 {
    var c = Vec[Float32].new();
    st = rand_coords(st, 8, &mut c);
    var v = vec_from_coords(&c);
    upsert(&mut ann, i + 1, v);
    i = i + 1;
  }
  io.println("upserts done: " + int_to_str(engine_size(&ann)));
  var params = ann_params_default();
  io.println("params: m=" + int_to_str(params.m));
  io.println("step 1: assign fresh graph");
  ann.graph = hnsw_new(params.m, 4.0);
  io.println("step 1 done: size=" + int_to_str(hnsw_size(&ann.graph)));
  hnsw_set_ef_construction(&mut ann.graph, params.ef_construction);
  io.println("step 2 done: ef=" + int_to_str(ann.graph.ef_construction));
  var i2: Int = 0;
  while i2 < ann.store.ids.len() {
    var pid = ann.store.ids[i2];
    var pv = ann.store.vectors[i2];
    hnsw_insert_ref(&mut ann.graph, pid, &pv, ann.metric);
    if i2 % 25 == 0 { io.println("step 3 inserted: " + int_to_str(i2 + 1)); }
    i2 = i2 + 1;
  }
  io.println("step 3 done: graph=" + int_to_str(hnsw_size(&ann.graph)));
  var okv = ann_params_valid(&params);
  io.println("step 4: ann_params_valid=" + int_to_str(if okv { 1 } else { 0 }));
  ann.index_kind = AnnIndexKind.Hnsw;
  ann.ann = params;
  io.println("step 5: field writes done");
  match engine_set_index(&mut ann, AnnIndexKind.Hnsw, ann_params_default()) {
    Ok(_) => { io.println("step 6: engine_set_index ok"); }
    Err(_) => { io.println("step 6: engine_set_index err"); }
  }
  io.println("end");
  return 0;
}
