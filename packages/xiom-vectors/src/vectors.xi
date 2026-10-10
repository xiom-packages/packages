// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vectors

// Dense-vector primitives extracted from XVECTOR
// (E:\xiom-projects\xiom-xvector @ 8a8b0ff; see SPEC.md section 2 for the
// per-file SHA256 pins). Public surface: Vector + dot/magnitude/normalize,
// cosine/dot/L2 distance with stable on-disk metric codes, Neighbor,
// Dimension, bounded top-K heap, and the WAL value codec + decode-replay
// loop. No engine, no indexes (xiom.ann / xiom.db territory). No contracts
// and no unsafe by policy.

use xiom.math;
use xiom.num.float;

// ==== Dense vector primitive (xvector src/types/dense_vector.xi) ====

pub type Vector = {
  data: Vec[Float32];
  dimension: Int;
} derive[Clone]

pub fn Vector.new(dimension: Int) -> Vector {
  var data_vec = Vec[Float32].new();
  var i: Int = 0;
  while i < dimension {
    data_vec.push(0.0);
    i = i + 1;
  }
  return Vector{ data: data_vec, dimension: dimension };
}

pub fn Vector.set(index: Int, value: Float32) {
  data[index] = value;
}

pub fn Vector.get(index: Int) -> Float32 {
  return data[index];
}

pub fn vector_dot(a: &Vector, b: &Vector) -> Float32 {
  var sum: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return sum;
}

pub fn vector_magnitude(v: &Vector) -> Float32 {
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  while i < v.dimension {
    sum_sq = sum_sq + v.data[i] * v.data[i];
    i = i + 1;
  }
  return (math.sqrt(sum_sq as Float64) as Float32);
}

// Addition over the reference (which normalizes inline in cosine_distance):
// a unit-length copy of `v` built on vector_magnitude; the zero vector
// stays zero (unit length is undefined there).
pub fn vector_normalize(v: &Vector) -> Vector {
  var out = Vector.new(v.dimension);
  var mag = vector_magnitude(v);
  if mag == 0.0 {
    return out;
  }
  var i: Int = 0;
  while i < v.dimension {
    out.data[i] = v.data[i] / mag;
    i = i + 1;
  }
  return out;
}

// ==== Distance metrics (xvector src/types/metric.xi) ====

pub enum DistanceMetric {
  Cosine,
  DotProduct,
  Euclidean,
}

pub fn dot_product_distance(a: &Vector, b: &Vector) -> Float32 {
  var sum: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return -sum;
}

pub fn cosine_distance(a: &Vector, b: &Vector) -> Float32 {
  var dot: Float32 = 0.0;
  var mag_a: Float32 = 0.0;
  var mag_b: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    var ai = a.data[i];
    var bi = b.data[i];
    dot = dot + ai * bi;
    mag_a = mag_a + ai * ai;
    mag_b = mag_b + bi * bi;
    i = i + 1;
  }
  if mag_a == 0.0 || mag_b == 0.0 { return 1.0; }
  var similarity = dot / ((math.sqrt(mag_a as Float64) as Float32) * (math.sqrt(mag_b as Float64) as Float32));
  return 1.0 - similarity;
}

pub fn euclidean_distance(a: &Vector, b: &Vector) -> Float32 {
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    var diff = a.data[i] - b.data[i];
    sum_sq = sum_sq + diff * diff;
    i = i + 1;
  }
  return (math.sqrt(sum_sq as Float64) as Float32);
}

pub fn vector_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32 {
  match metric {
    DistanceMetric.Cosine => cosine_distance(a, b),
    DistanceMetric.DotProduct => dot_product_distance(a, b),
    DistanceMetric.Euclidean => euclidean_distance(a, b),
  }
}

// Stable wire/on-disk codes for the metric: 1 = Cosine, 2 = DotProduct,
// 3 = Euclidean. Shared by the WAL collection-manifest record and the
// durable manifest file (D2); the codes are part of the on-disk format and
// are kept from the reference unchanged.
pub fn metric_code(m: DistanceMetric) -> Int {
  if m == DistanceMetric.Cosine { return 1; }
  if m == DistanceMetric.DotProduct { return 2; }
  return 3;
}

pub fn metric_from_code(c: Int) -> DistanceMetric {
  if c == 1 { return DistanceMetric.Cosine; }
  if c == 2 { return DistanceMetric.DotProduct; }
  return DistanceMetric.Euclidean;
}

// ==== Neighbor edge (xvector src/types/neighbor.xi) ====

pub type Neighbor = {
  id: UInt64;
  distance: Float32;
} derive[Clone]

pub fn neighbor_new(id: UInt64, distance: Float32) -> Neighbor {
  return Neighbor{ id: id, distance: distance };
}

// ==== Dimension value object (xvector src/types/dimension.xi) ====

fn is_valid_dimension(v: Int) -> Bool {
  return v >= 1 && v <= 65536;
}

fn max_dimensions() -> Int {
  return 65536;
}

pub type Dimension = { value: Int; } derive[Clone, Eq]

pub fn dimension(v: Int) -> Dimension {
  return Dimension{ value: v };
}

pub fn dimension_value(d: &Dimension) -> Int {
  return d.value;
}

pub fn dimension_eq(a: &Dimension, b: &Dimension) -> Bool {
  return a.value == b.value;
}

pub fn dimension_is_valid(v: Int) -> Bool {
  return is_valid_dimension(v);
}

pub fn dimension_within_limit(v: Int) -> Bool {
  return v >= 1 && v <= max_dimensions();
}

// ==== Bounded top-K collector (xvector src/query/topk_heap.xi) ====

// Maintains at most `capacity` neighbours in ascending distance order using
// the same insertion-sort-then-truncate strategy as the reference
// brute-force scan; items.len() <= capacity after every push.

pub type TopKHeap = {
  capacity: Int;
  items: Vec[Neighbor];
}

pub fn topk_new(capacity: Int) -> TopKHeap {
  var items = Vec[Neighbor].new();
  return TopKHeap{ capacity: capacity, items: items };
}

pub fn topk_push(h: &mut TopKHeap, n: Neighbor) {
  h.items.push(n);
  var pos: Int = h.items.len() - 1;
  while pos > 0 && h.items[pos - 1].distance > h.items[pos].distance {
    var tmp = h.items[pos];
    h.items[pos] = h.items[pos - 1];
    h.items[pos - 1] = tmp;
    pos = pos - 1;
  }
  if h.items.len() > h.capacity {
    h.items.pop();
  }
}

pub fn topk_len(h: &TopKHeap) -> Int {
  return h.items.len();
}

pub fn topk_is_full(h: &TopKHeap) -> Bool {
  return h.items.len() >= h.capacity;
}

// The current worst (largest-distance) member, i.e. the eviction candidate.
pub fn topk_worst(h: &TopKHeap) -> Option[Neighbor] {
  if h.items.len() == 0 {
    return None;
  }
  return Some(h.items[h.items.len() - 1]);
}

// ==== Durable vector codec (xvector src/storage/vector_store.xi L156/L169) ====

// WAL value payload = [dim, bits0, bits1, ...]. Float32 -> Float64 ->
// IEEE-754 bits is exact (every Float32 is exactly representable in
// Float64) and float_bits lowers to a true LLVM bitcast since v0.64.0.

pub fn vector_encode(v: &Vector) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(v.dimension);
  var i: Int = 0;
  while i < v.dimension {
    out.push(float.float_bits(v.data[i] as Float64));
    i = i + 1;
  }
  return out;
}

// Rebuild a vector from a WAL payload; None on any malformed shape (empty
// buffer, invalid dim, length mismatch) so replay can skip torn records.
pub fn vector_decode(payload: &Vec[Int]) -> Option[Vector] {
  if payload.len() < 1 { return None; }
  var dim = payload[0];
  if !dimension_is_valid(dim) { return None; }
  if payload.len() != dim + 1 { return None; }
  var v = Vector.new(dim);
  var i: Int = 0;
  while i < dim {
    v.data[i] = float.bits_to_float(payload[i + 1]) as Float32;
    i = i + 1;
  }
  return Some(v);
}

// Decode-replay loop over WAL payloads (the recover_store shape from
// xvector durability/recovery.xi, value level only): torn/malformed
// payloads decode to None and are skipped, everything decodable is kept in
// order. The WAL file layer itself is xiom.wal's home.
pub fn vectors_replay_into(payloads: &Vec[Vec[Int]]) -> Vec[Vector] {
  var out = Vec[Vector].new();
  var i: Int = 0;
  while i < payloads.len() {
    match vector_decode(&payloads[i]) {
      Some(v) => { out.push(v); }
      None => {}
    }
    i = i + 1;
  }
  return out;
}
