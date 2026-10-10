// XIOM -- xiom.vectors conformance tests (37 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Adapted from XVECTOR's tests/test_conformance.xi (vector/distance/topk/
// codec sections) plus the codec acceptance probe; only cases that cover
// the extracted xiom.vectors surface are carried. The normalization checks
// are for the small addition over the reference (SPEC.md section 3).

module vectors_tests

use xiom.io; use xiom.test; use xiom.vectors; use xiom.num.float;

fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}

fn f32_eq(a: Float32, b: Float32) -> Bool {
  return f32_approx(a, b, 0.0001);
}

fn mk_vec2(a: Float32, b: Float32) -> Vector {
  var v = Vector.new(2);
  v.set(0, a); v.set(1, b);
  return v;
}

fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}

// ==== Section 1: types ====

fn t_dimension_construct() -> TestResult {
  var d = dimension(128);
  return assert(dimension_value(&d) == 128, "Dimension: construction stores 128");
}

fn t_dimension_eq() -> TestResult {
  var a = dimension(64);
  var b = dimension(64);
  var c = dimension(128);
  var ok = dimension_eq(&a, &b) && !dimension_eq(&a, &c);
  return assert(ok, "Dimension: eq same(64==64) true, diff(64!=128) false");
}

fn t_dimension_is_valid() -> TestResult {
  var ok = dimension_is_valid(1) && dimension_is_valid(65536)
    && !dimension_is_valid(0) && !dimension_is_valid(99999);
  return assert(ok, "Dimension: is_valid(1,65536)=true, is_valid(0,99999)=false");
}

fn t_dimension_within_limit() -> TestResult {
  var ok = dimension_within_limit(1) && dimension_within_limit(65536)
    && !dimension_within_limit(0) && !dimension_within_limit(65537);
  return assert(ok, "Dimension: within_limit mirrors is_valid");
}

fn t_neighbor_struct() -> TestResult {
  var n = neighbor_new(42, 0.5);
  var m = Neighbor{ id: 7, distance: 1.25 };
  var ok = (n.id as Int) == 42 && f32_eq(n.distance, 0.5);
  if (m.id as Int) != 7 { ok = false; }
  if !f32_eq(m.distance, 1.25) { ok = false; }
  return assert(ok, "Neighbor: struct field access + neighbor_new");
}

fn t_metric_codes_roundtrip() -> TestResult {
  var ok = metric_code(DistanceMetric.Cosine) == 1;
  if metric_code(DistanceMetric.DotProduct) != 2 { ok = false; }
  if metric_code(DistanceMetric.Euclidean) != 3 { ok = false; }
  if metric_from_code(1) != DistanceMetric.Cosine { ok = false; }
  if metric_from_code(2) != DistanceMetric.DotProduct { ok = false; }
  if metric_from_code(3) != DistanceMetric.Euclidean { ok = false; }
  if metric_from_code(99) != DistanceMetric.Euclidean { ok = false; }
  if DistanceMetric.Cosine == DistanceMetric.DotProduct { ok = false; }
  return assert(ok, "Metric: on-disk codes 1/2/3 round-trip; unknown code falls back to Euclidean");
}

fn t_vector_new_set_get() -> TestResult {
  var v = Vector.new(3);
  var ok = v.dimension == 3 && v.data.len() == 3 && v.data[0] == 0.0;
  v.set(0, 1.5); v.set(1, -2.5); v.set(2, 0.25);
  if !f32_eq(v.get(0), 1.5) { ok = false; }
  if !f32_eq(v.get(1), -2.5) { ok = false; }
  if !f32_eq(v.get(2), 0.25) { ok = false; }
  return assert(ok, "Vector: new zero-fills dimension slots, set/get round-trip");
}

// ==== Section 2: distance metrics ====

fn t_distance_euclidean_same() -> TestResult {
  var v = mk_vec3(1.0, 2.0, 3.0);
  return assert(f32_eq(euclidean_distance(&v, &v), 0.0), "Euclidean: same vector = 0.0");
}

fn t_distance_euclidean_345() -> TestResult {
  var a = mk_vec2(0.0, 0.0);
  var b = mk_vec2(3.0, 4.0);
  return assert(f32_eq(euclidean_distance(&a, &b), 5.0), "Euclidean: (0,0) to (3,4) = 5.0");
}

fn t_distance_cosine_identical() -> TestResult {
  var v = mk_vec3(1.0, 2.0, 3.0);
  return assert(f32_eq(cosine_distance(&v, &v), 0.0), "Cosine: identical vector = 0.0");
}

fn t_distance_cosine_orthogonal() -> TestResult {
  var a = mk_vec2(1.0, 0.0);
  var b = mk_vec2(0.0, 1.0);
  return assert(f32_eq(cosine_distance(&a, &b), 1.0), "Cosine: orthogonal vectors = 1.0");
}

fn t_distance_cosine_opposite() -> TestResult {
  var a = mk_vec2(1.0, 0.0);
  var b = mk_vec2(-1.0, 0.0);
  return assert(f32_eq(cosine_distance(&a, &b), 2.0), "Cosine: opposite vectors = 2.0");
}

fn t_distance_cosine_zero_vector() -> TestResult {
  var a = mk_vec3(0.0, 0.0, 0.0);
  var b = mk_vec3(1.0, 2.0, 3.0);
  return assert(f32_eq(cosine_distance(&a, &b), 1.0), "Cosine: zero vector = 1.0 guard");
}

fn t_distance_cosine_close_pair() -> TestResult {
  var a = mk_vec3(0.9, 0.1, 0.0);
  var b = mk_vec3(1.0, 0.0, 0.0);
  return assert(f32_approx(cosine_distance(&a, &b), 0.00614, 0.001),
    "Cosine: (0.9,0.1,0) vs (1,0,0) ~ 0.00614 (probe_vector_store)");
}

fn t_distance_dot_same() -> TestResult {
  var v = mk_vec3(2.0, 3.0, 4.0);
  return assert(f32_eq(dot_product_distance(&v, &v), -29.0), "DotProduct: (2,3,4) self = -29.0");
}

fn t_distance_dot_orthogonal() -> TestResult {
  var a = mk_vec2(1.0, 0.0);
  var b = mk_vec2(0.0, 1.0);
  return assert(f32_eq(dot_product_distance(&a, &b), 0.0), "DotProduct: orthogonal = 0.0");
}

fn t_distance_dispatch_euclidean() -> TestResult {
  var a = mk_vec2(1.0, 0.0);
  var b = mk_vec2(4.0, 0.0);
  return assert(f32_eq(vector_distance(&a, &b, DistanceMetric.Euclidean), 3.0),
    "vector_distance: Euclidean dispatch");
}

fn t_distance_dispatch_cosine() -> TestResult {
  var v = mk_vec2(5.0, 0.0);
  return assert(f32_eq(vector_distance(&v, &v, DistanceMetric.Cosine), 0.0),
    "vector_distance: Cosine dispatch");
}

fn t_distance_dispatch_dot() -> TestResult {
  var a = mk_vec2(2.0, 3.0);
  var b = mk_vec2(4.0, 1.0);
  return assert(f32_eq(vector_distance(&a, &b, DistanceMetric.DotProduct), -11.0),
    "vector_distance: DotProduct dispatch");
}

fn t_distance_magnitude() -> TestResult {
  var v = mk_vec3(3.0, 4.0, 0.0);
  return assert(f32_eq(vector_magnitude(&v), 5.0), "Magnitude: (3,4,0) = 5.0");
}

fn t_distance_magnitude_zero() -> TestResult {
  var v = Vector.new(5);
  return assert(f32_eq(vector_magnitude(&v), 0.0), "Magnitude: zero vector = 0.0");
}

fn t_distance_dot_raw() -> TestResult {
  var a = mk_vec2(2.0, 3.0);
  var b = mk_vec2(4.0, 5.0);
  return assert(f32_eq(vector_dot(&a, &b), 23.0), "Dot: (2,3)*(4,5) = 23.0");
}

// ==== Section 3: normalization (addition over the reference) ====

fn t_normalize_345() -> TestResult {
  var v = mk_vec3(3.0, 4.0, 0.0);
  let n = vector_normalize(&v);
  var ok = n.dimension == 3;
  if !f32_eq(n.data[0], 0.6) { ok = false; }
  if !f32_eq(n.data[1], 0.8) { ok = false; }
  if !f32_eq(n.data[2], 0.0) { ok = false; }
  if !f32_eq(vector_magnitude(&n), 1.0) { ok = false; }
  if !f32_eq(v.data[0], 3.0) { ok = false; }
  return assert(ok, "Normalize: (3,4,0) -> (0.6,0.8,0) unit length; input untouched");
}

fn t_normalize_zero_vector() -> TestResult {
  var z = mk_vec3(0.0, 0.0, 0.0);
  let n = vector_normalize(&z);
  var ok = n.dimension == 3 && n.data[0] == 0.0 && n.data[1] == 0.0 && n.data[2] == 0.0;
  return assert(ok, "Normalize: zero vector stays zero");
}

fn t_normalize_cosine_invariant() -> TestResult {
  var a = mk_vec3(1.0, 2.0, 3.0);
  var b = mk_vec3(4.0, -1.0, 0.5);
  let na = vector_normalize(&a);
  let nb = vector_normalize(&b);
  let d0 = cosine_distance(&a, &b);
  let d1 = cosine_distance(&na, &nb);
  return assert(f32_approx(d0, d1, 0.001), "Normalize: cosine distance is scale-invariant");
}

// ==== Section 4: bounded top-K heap ====

fn t_topk_new() -> TestResult {
  var h = topk_new(10);
  return assert(topk_len(&h) == 0, "TopKHeap: new empty");
}

fn t_topk_push_bounded() -> TestResult {
  var h = topk_new(3);
  topk_push(&mut h, neighbor_new(1, 5.0));
  topk_push(&mut h, neighbor_new(2, 3.0));
  topk_push(&mut h, neighbor_new(3, 7.0));
  topk_push(&mut h, neighbor_new(4, 1.0));
  return assert(topk_len(&h) == 3, "TopKHeap: push 4 into capacity 3, len stays 3");
}

fn t_topk_push_sorted() -> TestResult {
  var h = topk_new(3);
  topk_push(&mut h, neighbor_new(3, 5.0));
  topk_push(&mut h, neighbor_new(1, 1.0));
  topk_push(&mut h, neighbor_new(2, 3.0));
  var ok = (h.items[0].id as Int) == 1 && (h.items[1].id as Int) == 2 && (h.items[2].id as Int) == 3;
  return assert(ok, "TopKHeap: items sorted asc by distance");
}

fn t_topk_is_full() -> TestResult {
  var h = topk_new(2);
  topk_push(&mut h, neighbor_new(1, 1.0));
  var ok = !topk_is_full(&h);
  topk_push(&mut h, neighbor_new(2, 2.0));
  if !topk_is_full(&h) { ok = false; }
  return assert(ok, "TopKHeap: is_full false at 1/2, true at 2/2");
}

fn t_topk_worst() -> TestResult {
  var h = topk_new(3);
  topk_push(&mut h, neighbor_new(1, 1.0));
  topk_push(&mut h, neighbor_new(2, 5.0));
  topk_push(&mut h, neighbor_new(3, 3.0));
  var w = topk_worst(&h);
  match w {
    Some(n) => { return assert(f32_eq(n.distance, 5.0), "TopKHeap: worst has max distance=5.0"); }
    None => { return assert(false, "TopKHeap: worst returned None"); }
  }
}

fn t_topk_worst_empty() -> TestResult {
  var h = topk_new(3);
  var w = topk_worst(&h);
  match w {
    Some(_) => { return assert(false, "TopKHeap: worst on empty returned Some"); }
    None => { return assert(true, "TopKHeap: worst on empty returns None"); }
  }
}

fn t_topk_determinism() -> TestResult {
  var q = mk_vec3(1.0, 1.0, 0.0);
  var h1 = topk_new(3);
  var h2 = topk_new(3);
  var i: Int = 0;
  while i < 5 {
    var v = mk_vec3(i as Float32, (5 - i) as Float32, 0.5);
    let d1 = vector_distance(&q, &v, DistanceMetric.Cosine);
    let d2 = vector_distance(&q, &v, DistanceMetric.Cosine);
    if float.float_bits(d1 as Float64) != float.float_bits(d2 as Float64) { break; }
    topk_push(&mut h1, neighbor_new(i as UInt64, d1));
    topk_push(&mut h2, neighbor_new(i as UInt64, d2));
    i = i + 1;
  }
  var ok = topk_len(&h1) == 3 && topk_len(&h2) == 3;
  var j: Int = 0;
  while j < topk_len(&h1) {
    if (h1.items[j].id as Int) != (h2.items[j].id as Int) { ok = false; }
    if float.float_bits(h1.items[j].distance as Float64) != float.float_bits(h2.items[j].distance as Float64) { ok = false; }
    j = j + 1;
  }
  return assert(ok, "Determinism: distance + topK results bit-identical across two runs");
}

// ==== Section 5: WAL value codec + replay ====

fn t_codec_roundtrip() -> TestResult {
  var v = mk_vec3(1.5, -2.25, 0.0);
  var payload = vector_encode(&v);
  var ok = payload.len() == 4 && payload[0] == 3;
  match vector_decode(&payload) {
    Some(w) => {
      if w.dimension != 3 { ok = false; }
      if !f32_eq(w.data[0], 1.5) { ok = false; }
      if !f32_eq(w.data[1], -2.25) { ok = false; }
      if !f32_eq(w.data[2], 0.0) { ok = false; }
    }
    None => { ok = false; }
  }
  return assert(ok, "Codec: Float32 value roundtrip, payload = [dim, bits...]");
}

fn t_codec_bit_exactness() -> TestResult {
  var v = mk_vec2(-0.0, 1.1754944e-38);
  let b0 = float.float_bits(v.data[0] as Float64);
  let b1 = float.float_bits(v.data[1] as Float64);
  var payload = vector_encode(&v);
  match vector_decode(&payload) {
    Some(w) => {
      var ok = float.float_bits(w.data[0] as Float64) == b0;
      if float.float_bits(w.data[1] as Float64) != b1 { ok = false; }
      return assert(ok, "Codec: negative zero + smallest normal bit-exact");
    }
    None => { return assert(false, "Codec: bit-exact decode returned None"); }
  }
}

fn t_codec_malformed_rejected() -> TestResult {
  var empty = Vec[Int].new();
  var ok = true;
  match vector_decode(&empty) { Some(_) => { ok = false; } None => {} }
  var dim0 = Vec[Int].new(); dim0.push(0);
  match vector_decode(&dim0) { Some(_) => { ok = false; } None => {} }
  var short = Vec[Int].new(); short.push(3); short.push(1);
  match vector_decode(&short) { Some(_) => { ok = false; } None => {} }
  var huge = Vec[Int].new(); huge.push(65537);
  match vector_decode(&huge) { Some(_) => { ok = false; } None => {} }
  return assert(ok, "Codec: malformed payloads -> None");
}

fn t_codec_replay_torn_skipped() -> TestResult {
  var v1 = mk_vec3(1.0, 2.0, 3.0);
  var v2 = mk_vec3(4.0, 5.0, 6.0);
  var payloads = Vec[Vec[Int]].new();
  payloads.push(vector_encode(&v1));
  var torn = Vec[Int].new();
  torn.push(3); torn.push(1);
  payloads.push(torn);
  payloads.push(vector_encode(&v2));
  let got = vectors_replay_into(&payloads);
  var ok = got.len() == 2;
  if ok {
    if got[0].dimension != 3 { ok = false; }
    if !f32_eq(got[0].data[0], 1.0) { ok = false; }
    if !f32_eq(got[1].data[2], 6.0) { ok = false; }
  }
  return assert(ok, "Codec: replay skips torn payload, keeps later records in order");
}

fn t_codec_determinism() -> TestResult {
  var v = mk_vec3(-0.0, 3.5, 10000000000.0);
  var p1 = vector_encode(&v);
  var p2 = vector_encode(&v);
  var ok = p1.len() == p2.len();
  var i: Int = 0;
  while i < p1.len() {
    if p1[i] != p2[i] { ok = false; }
    i = i + 1;
  }
  match vector_decode(&p1) {
    Some(a) => {
      match vector_decode(&p2) {
        Some(b) => {
          if a.dimension != b.dimension { ok = false; }
          var j: Int = 0;
          while j < a.dimension {
            if float.float_bits(a.data[j] as Float64) != float.float_bits(b.data[j] as Float64) { ok = false; }
            j = j + 1;
          }
        }
        None => { ok = false; }
      }
    }
    None => { ok = false; }
  }
  return assert(ok, "Codec: encode/decode deterministic bit-for-bit");
}

fn run_one(r: TestResult) -> Int {
  if r.passed { io.println("  [PASS] " + r.name); return 0; }
  io.println("  [FAIL] " + r.name); return 1;
}

fn main() -> Int {
  io.println("=== xiom.vectors conformance tests ===");
  var failed: Int = 0;
  let r1 = t_dimension_construct();
  failed = failed + run_one(r1);
  let r2 = t_dimension_eq();
  failed = failed + run_one(r2);
  let r3 = t_dimension_is_valid();
  failed = failed + run_one(r3);
  let r4 = t_dimension_within_limit();
  failed = failed + run_one(r4);
  let r5 = t_neighbor_struct();
  failed = failed + run_one(r5);
  let r6 = t_metric_codes_roundtrip();
  failed = failed + run_one(r6);
  let r7 = t_vector_new_set_get();
  failed = failed + run_one(r7);
  let r8 = t_distance_euclidean_same();
  failed = failed + run_one(r8);
  let r9 = t_distance_euclidean_345();
  failed = failed + run_one(r9);
  let r10 = t_distance_cosine_identical();
  failed = failed + run_one(r10);
  let r11 = t_distance_cosine_orthogonal();
  failed = failed + run_one(r11);
  let r12 = t_distance_cosine_opposite();
  failed = failed + run_one(r12);
  let r13 = t_distance_cosine_zero_vector();
  failed = failed + run_one(r13);
  let r14 = t_distance_cosine_close_pair();
  failed = failed + run_one(r14);
  let r15 = t_distance_dot_same();
  failed = failed + run_one(r15);
  let r16 = t_distance_dot_orthogonal();
  failed = failed + run_one(r16);
  let r17 = t_distance_dispatch_euclidean();
  failed = failed + run_one(r17);
  let r18 = t_distance_dispatch_cosine();
  failed = failed + run_one(r18);
  let r19 = t_distance_dispatch_dot();
  failed = failed + run_one(r19);
  let r20 = t_distance_magnitude();
  failed = failed + run_one(r20);
  let r21 = t_distance_magnitude_zero();
  failed = failed + run_one(r21);
  let r22 = t_distance_dot_raw();
  failed = failed + run_one(r22);
  let r23 = t_normalize_345();
  failed = failed + run_one(r23);
  let r24 = t_normalize_zero_vector();
  failed = failed + run_one(r24);
  let r25 = t_normalize_cosine_invariant();
  failed = failed + run_one(r25);
  let r26 = t_topk_new();
  failed = failed + run_one(r26);
  let r27 = t_topk_push_bounded();
  failed = failed + run_one(r27);
  let r28 = t_topk_push_sorted();
  failed = failed + run_one(r28);
  let r29 = t_topk_is_full();
  failed = failed + run_one(r29);
  let r30 = t_topk_worst();
  failed = failed + run_one(r30);
  let r31 = t_topk_worst_empty();
  failed = failed + run_one(r31);
  let r32 = t_topk_determinism();
  failed = failed + run_one(r32);
  let r33 = t_codec_roundtrip();
  failed = failed + run_one(r33);
  let r34 = t_codec_bit_exactness();
  failed = failed + run_one(r34);
  let r35 = t_codec_malformed_rejected();
  failed = failed + run_one(r35);
  let r36 = t_codec_replay_torn_skipped();
  failed = failed + run_one(r36);
  let r37 = t_codec_determinism();
  failed = failed + run_one(r37);
  if failed == 0 {
    io.println("xiom.vectors: all 37 checks passed");
  } else {
    io.println("xiom.vectors: checks failed");
  }
  return failed;
}
