// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: xiom.vectors 0.1.0 package gate (adoption 2026-10-10; see
// docs/XIOM-VECTORS-EVAL.md). The package is a byte-exact carve of this
// lane's primitives (extraction pins in its SPEC all match the current
// tree), so this gate pins the package's behavior on exactly-representable
// corpora -- the same arithmetic the lane probes assert through the local
// modules:
//   - dot / magnitude / euclidean / cosine / dot-product distance exact;
//   - normalize (zero stays zero, unit stays unit);
//   - metric codes 1/2/3 round-trip + unknown fallback;
//   - dimension validity 1..65536;
//   - bounded top-K ordering + eviction;
//   - WAL value codec shape, element-exact round-trip, torn-skip replay.
// Exit = failed checks.

module probe_package_vectors

use xiom.vectors;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn mk2(a: Float32, b: Float32) -> Vector {
  var v = Vector.new(2);
  v.set(0, a);
  v.set(1, b);
  return v;
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.vectors package adoption ===");
  var fails: Int = 0;

  var a = mk2(1.0, 0.0);
  var b = mk2(0.0, 1.0);
  var c = mk2(3.0, 4.0);
  var z = mk2(0.0, 0.0);

  fails = check(vector_dot(&a, &b) == 0.0 && vector_dot(&c, &c) == 25.0
    && vector_dot(&a, &c) == 3.0,
    "dot: exact on integer corpora (0 / 25 / 3)", fails);
  fails = check(vector_magnitude(&c) == 5.0 && vector_magnitude(&b) == 1.0,
    "magnitude: 3-4-5 exact and unit axis", fails);
  fails = check(euclidean_distance(&c, &z) == 5.0 && euclidean_distance(&a, &a) == 0.0,
    "euclidean: 3-4-5 and identity exact", fails);
  fails = check(cosine_distance(&a, &b) == 1.0 && cosine_distance(&a, &a) == 0.0
    && cosine_distance(&z, &a) == 1.0,
    "cosine: orthogonal 1.0, self 0.0, zero-vector 1.0", fails);
  fails = check(dot_product_distance(&a, &c) == -3.0,
    "dot-product distance: negative dot (-3)", fails);
  var nz = vector_normalize(&z);
  var nb = vector_normalize(&b);
  fails = check(vector_magnitude(&nz) == 0.0 && vector_magnitude(&nb) == 1.0,
    "normalize: zero stays zero, unit stays unit", fails);

  fails = check(metric_code(DistanceMetric.Cosine) == 1
    && metric_code(DistanceMetric.DotProduct) == 2
    && metric_code(DistanceMetric.Euclidean) == 3
    && metric_from_code(1) == DistanceMetric.Cosine
    && metric_from_code(3) == DistanceMetric.Euclidean
    && metric_from_code(9) == DistanceMetric.Euclidean,
    "metric: codes 1/2/3 round-trip; unknown falls back to Euclidean", fails);

  fails = check(dimension_is_valid(1) && !dimension_is_valid(0)
    && dimension_within_limit(65536) && !dimension_within_limit(65537)
    && dimension_eq(dimension(4), dimension(4)),
    "dimension: validity 1..65536 + equality", fails);

  var heap = topk_new(2);
  topk_push(&mut heap, neighbor_new(10, 2.0));
  topk_push(&mut heap, neighbor_new(11, 1.0));
  topk_push(&mut heap, neighbor_new(12, 3.0));
  var w1: Int = -1;
  match topk_worst(&heap) {
    Some(w) => { w1 = w.id; }
    None => {}
  }
  fails = check(topk_len(&heap) == 2 && topk_is_full(&heap) && w1 == 10,
    "topk: capacity 2 keeps [1.0, 2.0]; 3.0 evicted; worst id 10", fails);
  topk_push(&mut heap, neighbor_new(13, 0.5));
  var w2: Int = -1;
  match topk_worst(&heap) {
    Some(w) => { w2 = w.id; }
    None => {}
  }
  fails = check(w2 == 11, "topk: 0.5 arrives, worst becomes id 11", fails);

  var payload = vector_encode(&c);
  fails = check(payload.len() == 3 && payload[0] == 2,
    "codec: encode(dim 2) -> [2, bits, bits]", fails);
  var rt_ok: Bool = false;
  match vector_decode(&payload) {
    Some(w) => { rt_ok = w.get(0) == c.get(0) && w.get(1) == c.get(1); }
    None => {}
  }
  fails = check(rt_ok, "codec: decode(encode(c)) element-exact", fails);
  var payloads = Vec[Vec[Int]].new();
  payloads.push(vector_encode(&c));
  var torn = Vec[Int].new();
  torn.push(2);
  torn.push(1);
  payloads.push(torn);
  payloads.push(vector_encode(&a));
  var replay = vectors_replay_into(&payloads);
  var r0_ok: Bool = false;
  if replay.len() == 2 {
    let r0: Vector = replay[0];
    let r1: Vector = replay[1];
    r0_ok = r0.get(0) == 3.0 && r1.get(0) == 1.0;
  }
  fails = check(replay.len() == 2 && r0_ok,
    "replay: torn payload skipped, order preserved", fails);

  io.println("");
  io.println("probe_package_vectors: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
