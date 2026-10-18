// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.index.quantize

// SQ8 scalar quantization + the two-tier quantized scan (reference study
// 02, proposal Q-a; sources studied: FAISS `QT_8bit` trained per-dimension
// ranges + the ADC distance-table pattern, sqlite-vec's `int8`/rescore
// shadow-table split). Re-implemented here, no vendoring.
//
// Mechanics: training records per-dimension [vmin, vstep] where
// `vstep = (vmax - vmin) / 255`; a component encodes as
// `clamp(trunc((x - vmin) / vstep), 0, 255)` (FAISS truncation, so the
// round-trip error is < vstep per component for in-range inputs) and
// decodes as `vmin + code * vstep`. A query builds FAISS-style distance
// tables (256 entries per dimension: squared L2 contributions, inner-
// product contributions, decoded squared-norms); scanning a candidate is
// `dim` table lookups, no per-candidate float decode.
//
// The scan is TWO-TIER (the honesty device from the study): phase 1 ranks
// codes for `k * oversample` candidates (capped at 4096, sqlite-vec's
// rescore cap), phase 2 recomputes EXACT distances with
// `vector_distance` on the full-precision vectors from the store and
// sorts them exactly like `search_knn` (stable insertion, strict `>`), so
// `sq8_scan_rescore` results are bit-identical to the exact scan whenever
// the coarse tier keeps the true top-k in its candidate set. The
// coarse-only tier is never a final result; its deviation from exact is
// bounded and pinned by `probe_quantization` (study 02 error story).

use xiom.math;
use xiom.vector.primitives;
use xiom.vector.storage.vector_store;

pub type SQ8 = {
  dim: Int;
  vmin: Vec[Float32];
  vstep: Vec[Float32];
}

// A phase-1 candidate: store POSITION + its quantized distance. Positions
// are internal to this module (the public scan maps them to user ids).
pub type QuantCand = {
  pos: Int;
  distance: Float32;
}

// A quantized-scan hit: user id + distance (exact after rescore).
pub type QuantHit = {
  id: Int;
  distance: Float32;
}

// ---- Training + encode/decode ----

// Per-dimension min/max training over the given vectors. None when the
// list is empty or dimensions are inconsistent. Constant dimensions get
// vstep 0 (every value encodes to code 0 and decodes exactly).
pub fn sq8_train(vectors: &Vec[Vector]) -> Option[SQ8] {
  if vectors.len() == 0 { return None; }
  var dim: Int = vectors[0].dimension;
  if dim < 1 { return None; }
  var vi: Int = 0;
  while vi < vectors.len() {
    if vectors[vi].dimension != dim { return None; }
    vi = vi + 1;
  }
  var vmin = Vec[Float32].new();
  var vmax = Vec[Float32].new();
  var d: Int = 0;
  while d < dim {
    vmin.push(vectors[0].data[d]);
    vmax.push(vectors[0].data[d]);
    d = d + 1;
  }
  vi = 0;
  while vi < vectors.len() {
    d = 0;
    while d < dim {
      var x = vectors[vi].data[d];
      if x < vmin[d] { vmin[d] = x; }
      if x > vmax[d] { vmax[d] = x; }
      d = d + 1;
    }
    vi = vi + 1;
  }
  var vstep = Vec[Float32].new();
  d = 0;
  while d < dim {
    var span = vmax[d] - vmin[d];
    if span > 0.0 { vstep.push(span / 255.0); } else { vstep.push(0.0); }
    d = d + 1;
  }
  var sq = SQ8{ dim: dim, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  d = 0;
  while d < dim {
    sq.vmin.push(vmin[d]);
    sq.vstep.push(vstep[d]);
    d = d + 1;
  }
  return Some(sq);
}

// The codec round-trip bound: the largest per-component error the trained
// ranges can produce for in-range inputs (truncation -> strictly below one
// step). 0.0 for an all-constant quantizer.
pub fn sq8_max_error(sq: &SQ8) -> Float32 {
  var m: Float32 = 0.0;
  var d: Int = 0;
  while d < sq.dim {
    if sq.vstep[d] > m { m = sq.vstep[d]; }
    d = d + 1;
  }
  return m;
}

pub fn sq8_encode_one(sq: &SQ8, v: &Vector) -> Vec[Int]
  requires: sq.dim == v.dimension
{
  var out = Vec[Int].new();
  var d: Int = 0;
  while d < sq.dim {
    var c: Int = 0;
    if sq.vstep[d] > 0.0 {
      var f = (v.data[d] - sq.vmin[d]) / sq.vstep[d];
      c = f as Int;
      if c < 0 { c = 0; }
      if c > 255 { c = 255; }
    }
    out.push(c);
    d = d + 1;
  }
  return out;
}

pub fn sq8_decode_one(sq: &SQ8, codes: &Vec[Int]) -> Option[Vector] {
  if codes.len() != sq.dim { return None; }
  var out = Vector.new(sq.dim);
  var d: Int = 0;
  while d < sq.dim {
    var c = codes[d];
    if c < 0 || c > 255 { return None; }
    out.data[d] = sq.vmin[d] + (c as Float32) * sq.vstep[d];
    d = d + 1;
  }
  return Some(out);
}

// Encode every store position (flattened: position p owns
// `codes[p * dim .. p * dim + dim]`). Empty on a dimension mismatch.
pub fn sq8_encode_store(store: &VectorIndex, sq: &SQ8) -> Vec[Int] {
  var out = Vec[Int].new();
  if store.dim != sq.dim { return out; }
  var p: Int = 0;
  while p < store.ids.len() {
    var cw = sq8_encode_one(sq, &store.vectors[p]);
    var j: Int = 0;
    while j < cw.len() {
      out.push(cw[j]);
      j = j + 1;
    }
    p = p + 1;
  }
  return out;
}

// ---- Query tables (FAISS SQ distance-computer pattern) ----
// Each table is `dim * 256` floats. Euclidean needs the squared-L2 table;
// DotProduct the inner-product table; Cosine inner-product + decoded
// squared-norm tables.

pub fn sq8_table_l2(sq: &SQ8, query: &Vector) -> Vec[Float32]
  requires: sq.dim == query.dimension
{
  var t = Vec[Float32].new();
  var d: Int = 0;
  while d < sq.dim {
    var qd = query.data[d];
    var c: Int = 0;
    while c < 256 {
      var dec = sq.vmin[d] + (c as Float32) * sq.vstep[d];
      var diff = qd - dec;
      t.push(diff * diff);
      c = c + 1;
    }
    d = d + 1;
  }
  return t;
}

pub fn sq8_table_ip(sq: &SQ8, query: &Vector) -> Vec[Float32]
  requires: sq.dim == query.dimension
{
  var t = Vec[Float32].new();
  var d: Int = 0;
  while d < sq.dim {
    var qd = query.data[d];
    var c: Int = 0;
    while c < 256 {
      var dec = sq.vmin[d] + (c as Float32) * sq.vstep[d];
      t.push(qd * dec);
      c = c + 1;
    }
    d = d + 1;
  }
  return t;
}

pub fn sq8_table_norm2(sq: &SQ8) -> Vec[Float32] {
  var t = Vec[Float32].new();
  var d: Int = 0;
  while d < sq.dim {
    var c: Int = 0;
    while c < 256 {
      var dec = sq.vmin[d] + (c as Float32) * sq.vstep[d];
      t.push(dec * dec);
      c = c + 1;
    }
    d = d + 1;
  }
  return t;
}

// ---- Table-lookup distances (one `&Vec` each: no multi-ref helper) ----

pub fn sq8_l2_distance(t: &Vec[Float32], codes: &Vec[Int], base: Int) -> Float32 {
  var sum: Float32 = 0.0;
  var d: Int = 0;
  while d < t.len() / 256 {
    sum = sum + t[d * 256 + codes[base + d]];
    d = d + 1;
  }
  return (math.sqrt(sum as Float64) as Float32);
}

pub fn sq8_ip_distance(t: &Vec[Float32], codes: &Vec[Int], base: Int) -> Float32 {
  var sum: Float32 = 0.0;
  var d: Int = 0;
  while d < t.len() / 256 {
    sum = sum + t[d * 256 + codes[base + d]];
    d = d + 1;
  }
  return -sum;
}

pub fn sq8_cos_distance(tip: &Vec[Float32], tnrm: &Vec[Float32], qmag: Float32, codes: &Vec[Int], base: Int) -> Float32 {
  var dot: Float32 = 0.0;
  var n2: Float32 = 0.0;
  var d: Int = 0;
  while d < tip.len() / 256 {
    var c = codes[base + d];
    dot = dot + tip[d * 256 + c];
    n2 = n2 + tnrm[d * 256 + c];
    d = d + 1;
  }
  if qmag == 0.0 || n2 <= 0.0 { return 1.0; }
  var sim = dot / (qmag * (math.sqrt(n2 as Float64) as Float32));
  return 1.0 - sim;
}

// ---- Two-tier scan ----

// Phase 1: the `cap` best positions by quantized distance (deterministic:
// sorted by distance, ties by store position). Private; both public scans
// go through it so the coarse tier is identical wherever it is used.
fn sq8_coarse_top(store: &VectorIndex, sq: &SQ8, codes: &Vec[Int], query: &Vector, cap: Int, metric: DistanceMetric) -> Vec[QuantCand] {
  var sel = Vec[QuantCand].new();
  var n: Int = store.ids.len();
  if n == 0 || codes.len() != n * sq.dim { return sel; }
  var c: Int = cap;
  if c > n { c = n; }
  if c <= 0 { return sel; }
  var heap = topk_new(c);
  var p: Int = 0;
  match metric {
    Euclidean => {
      var t = sq8_table_l2(sq, query);
      while p < n {
        topk_push(&mut heap, Neighbor{ id: p as UInt64, distance: sq8_l2_distance(&t, codes, p * sq.dim) });
        p = p + 1;
      }
    }
    DotProduct => {
      var t = sq8_table_ip(sq, query);
      while p < n {
        topk_push(&mut heap, Neighbor{ id: p as UInt64, distance: sq8_ip_distance(&t, codes, p * sq.dim) });
        p = p + 1;
      }
    }
    Cosine => {
      var t = sq8_table_ip(sq, query);
      var tn = sq8_table_norm2(sq);
      var qmag = vector_magnitude(query);
      while p < n {
        topk_push(&mut heap, Neighbor{ id: p as UInt64, distance: sq8_cos_distance(&t, &tn, qmag, codes, p * sq.dim) });
        p = p + 1;
      }
    }
  }
  var i: Int = 0;
  while i < heap.items.len() {
    sel.push(QuantCand{ pos: heap.items[i].id as Int, distance: heap.items[i].distance });
    i = i + 1;
  }
  return sel;
}

// Coarse-tier scan (positions -> user ids; NOT a final result path: it is
// the study's gated deviation tier, never claimed exact).
pub fn sq8_scan_coarse(store: &VectorIndex, sq: &SQ8, codes: &Vec[Int], query: &Vector, k: Int, metric: DistanceMetric) -> Vec[QuantHit]
  requires: k > 0
  requires: store.dim == query.dimension
{
  var cands = sq8_coarse_top(store, sq, codes, query, k, metric);
  var out = Vec[QuantHit].new();
  var i: Int = 0;
  while i < cands.len() {
    out.push(QuantHit{ id: store.ids[cands[i].pos], distance: cands[i].distance });
    i = i + 1;
  }
  return out;
}

// Quantized scan + exact rescore: phase 1 keeps `k * oversample`
// candidates (capped at 4096), phase 2 ranks them with the exact
// `vector_distance` in store-position order using the same stable
// bounded-insertion as `search_knn`, so the result equals the exact scan
// bit-for-bit whenever the candidate set contains the true top-k.
pub fn sq8_scan_rescore(store: &VectorIndex, sq: &SQ8, codes: &Vec[Int], query: &Vector, k: Int, metric: DistanceMetric, oversample: Int) -> Vec[QuantHit]
  requires: k > 0
  requires: oversample >= 1
  requires: store.dim == query.dimension
{
  var cap: Int = k * oversample;
  if cap > 4096 { cap = 4096; }
  var cands = sq8_coarse_top(store, sq, codes, query, cap, metric);
  // Phase 2 in store-position order (stable insertion parity with
  // search_knn's scan order).
  var poslist = Vec[Int].new();
  var i: Int = 0;
  while i < cands.len() {
    poslist.push(cands[i].pos);
    var j: Int = poslist.len() - 1;
    while j > 0 && poslist[j - 1] > poslist[j] {
      var tmp = poslist[j];
      poslist[j] = poslist[j - 1];
      poslist[j - 1] = tmp;
      j = j - 1;
    }
    i = i + 1;
  }
  var heap = topk_new(k);
  i = 0;
  while i < poslist.len() {
    var p = poslist[i];
    topk_push(&mut heap, Neighbor{ id: store.ids[p] as UInt64, distance: vector_distance(&store.vectors[p], query, metric) });
    i = i + 1;
  }
  var out = Vec[QuantHit].new();
  i = 0;
  while i < heap.items.len() {
    out.push(QuantHit{ id: heap.items[i].id as Int, distance: heap.items[i].distance });
    i = i + 1;
  }
  return out;
}
