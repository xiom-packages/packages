// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.tests.test_conformance

use xiom.io;
use xiom.num.float;
use xiom.string.slice;
use xiom.test;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = "";
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

// ============================================================================
// Local type mirrors (consolidated engine types live in engine.xi;
// individual module types are inlined here for isolated testing)
// ============================================================================

pub type CoreError = {
  case: Int;
  msg: Str;
}

pub type VectorId = { value: Int; }
pub type CollectionId = { value: Int; }
pub type SegmentId = { value: Int; }
pub type PointId = { value: Int; }

pub type Vector = {
  data: Vec[Float32];
  dimension: Int;
}

pub enum DistanceMetric {
  Cosine,
  DotProduct,
  Euclidean,
}

pub type Neighbor = {
  id: Int;
  distance: Float32;
}

pub type VectorIndex = {
  vectors: Vec[Vector];
  ids: Vec[Int];
  dim: Int;
}

pub type SearchResult = {
  id: Int;
  distance: Float32;
}

// Ok-payload wrapper mirroring engine.xi (XVC-C-04: Result[Vec[non-scalar]]
// loses element fields on v0.64.0; wrapping the Vec in a struct preserves it).
pub type SearchHits = {
  items: Vec[SearchResult];
}

// Batch-search mirror (M-Q2): one result set per query, order preserved.
pub type BatchHits = {
  sets: Vec[SearchHits];
}

// Hydrated hit mirroring query/search_service.xi (SearchRequest.with_payload).
// XVC-C-08 (the trailing has_payload after the Vec-bearing payload field read
// as garbage in this unit) is FIXED in compiler v0.64.2; the suite asserts
// the flags again in test_request_hydration (the real-module probe stays the
// independent gate).
pub type SearchHit = {
  id: Int;
  distance: Float32;
  payload: Payload;
  has_payload: Bool;
}

pub type HydratedHits = {
  items: Vec[SearchHit];
}

pub enum WalOpKind {
  Insert,
  Update,
  Delete,
  SegmentSeal,
  ManifestUpdate,
  Checkpoint,
  SnapshotMarker,
}

pub type WalRecord = {
  lsn: Int;
  op: WalOpKind;
  key: Int;
  value: Int;
  payload: Vec[Int];
  timestamp: Int;
}

pub type WalWriter = {
  records: Vec[WalRecord];
  next_lsn: Int;
  synced_lsn: Int;
}

pub type Counter = {
  name: Str;
  value: Int;
}

pub type VectorEngine = {
  store: VectorIndex;
  metric: DistanceMetric;
  dimension: Int;
  created: Bool;
  wal: WalWriter;
  upserts: Counter;
  deletes: Counter;
  next_collection: Int;
  payloads: PayloadStore;
}

pub enum VectorError {
  DimensionMismatch(expected: Int, got: Int),
  UnsupportedMetric(name: Str),
  CollectionNotFound(id: Int),
  InvalidVector(msg: Str),
  SegmentSealed(id: Int),
  TopKExceeded(requested: Int, max: Int),
}

pub type IdMapEntry = {
  vector_id: Int;
  segment: Int;
  offset: Int;
}

pub type IdMap = {
  entries: Vec[IdMapEntry];
}

pub enum AnnIndexKind {
  Flat,
  Hnsw,
  Ivf,
}

pub type AnnParams = {
  m: Int;
  ef_construction: Int;
  ef_search: Int;
}

pub type TopKHeap = {
  capacity: Int;
  items: Vec[Neighbor];
}

pub type SearchRequest = {
  query: Vector;
  top_k: Int;
  metric: DistanceMetric;
  filter: Vec[FilterExpr];
  with_payload: Bool;
}

pub enum FieldValue {
  IntVal(v: Int),
  FloatVal(v: Float32),
  TextVal(v: Str),
  BoolVal(v: Bool),
}

pub type PayloadField = {
  key: Str;
  value: FieldValue;
}

pub type Payload = {
  fields: Vec[PayloadField];
}

pub type PayloadEntry = {
  id: Int;
  payload: Payload;
}

pub type PayloadStore = {
  entries: Vec[PayloadEntry];
}

pub type RecoveredState = {
  store: VectorIndex;
  payloads: PayloadStore;
}

pub enum FilterExpr {
  Eq(Str, FieldValue),
  Range(Str, Float32, Float32),
  Exists(Str),
  In(Str, Vec[FieldValue]),
  And(Vec[FilterExpr]),
  Or(Vec[FilterExpr]),
  Not(Vec[FilterExpr]),
}

pub enum SegmentStateKind {
  Mutable,
  Sealing,
  Sealed,
  Indexing,
  Immutable,
  Compacting,
  Dropped,
}

pub type Segment = {
  id: SegmentId;
  state: SegmentStateKind;
  store: VectorIndex;
}

pub type Manifest = {
  collection: CollectionId;
  active_segments: Vec[SegmentId];
  last_lsn: Int;
}

pub enum NormalizationMode {
  Raw,
  L2Normalized,
}

pub type PayloadFieldSpec = {
  name: Str;
  indexed: Bool;
}

pub type CollectionSchema = {
  dimension: Int;
  metric: DistanceMetric;
  normalization: NormalizationMode;
  payload_fields: Vec[PayloadFieldSpec];
}

pub type Collection = {
  id: CollectionId;
  schema: CollectionSchema;
  segments: Vec[SegmentId];
  index_kind: AnnIndexKind;
  index_params: AnnParams;
}

pub type Dimension = { value: Int; }

// ============================================================================
// Helper: Float32 comparison
// ============================================================================

fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}

fn f32_eq(a: Float32, b: Float32) -> Bool {
  return f32_approx(a, b, 0.0001);
}

// ============================================================================
// Helper: local vector math (standalone, mirrors engine.xi)
// ============================================================================

fn vector_new(dim: Int) -> Vector
  requires: dim > 0
{
  var data = Vec[Float32].new();
  var i: Int = 0;
  while i < dim {
    data.push(0.0);
    i = i + 1;
  }
  return Vector{ data: data, dimension: dim };
}

fn vector_set(v: &mut Vector, index: Int, value: Float32)
  requires: index >= 0 && index < v.dimension
{
  v.data[index] = value;
}

fn vector_get(v: &Vector, index: Int) -> Float32
  requires: index >= 0 && index < v.dimension
{
  return v.data[index];
}

fn vector_dot(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return sum;
}

fn sqrt_f32(x: Float32) -> Float32 {
  if x <= 0.0 { return 0.0; }
  var guess = x * 0.5;
  var i: Int = 0;
  while i < 20 {
    guess = (guess + x / guess) * 0.5;
    i = i + 1;
  }
  return guess;
}

fn vector_magnitude(v: &Vector) -> Float32 {
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  while i < v.dimension {
    sum_sq = sum_sq + v.data[i] * v.data[i];
    i = i + 1;
  }
  return sqrt_f32(sum_sq);
}

fn dot_product_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return -sum;
}

fn cosine_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
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
  var similarity = dot / (sqrt_f32(mag_a) * sqrt_f32(mag_b));
  return 1.0 - similarity;
}

fn euclidean_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    var diff = a.data[i] - b.data[i];
    sum_sq = sum_sq + diff * diff;
    i = i + 1;
  }
  return sqrt_f32(sum_sq);
}

fn vector_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32
  requires: a.dimension == b.dimension
{
  match metric {
    Cosine => cosine_distance(a, b),
    DotProduct => dot_product_distance(a, b),
    Euclidean => euclidean_distance(a, b),
  }
}

// ============================================================================
// Helper: engine operations (standalone, mirrors engine.xi)
// ============================================================================

fn collection_id(v: Int) -> CollectionId {
  return CollectionId{ value: v };
}

fn vector_id(v: Int) -> VectorId {
  return VectorId{ value: v };
}

fn vector_id_value(id: &VectorId) -> Int {
  return id.value;
}

fn segment_id(v: Int) -> SegmentId {
  return SegmentId{ value: v };
}

fn segment_id_eq(a: &SegmentId, b: &SegmentId) -> Bool {
  return a.value == b.value;
}

fn is_valid_dimension(dim: Int) -> Bool {
  return dim >= 1 && dim <= 65536;
}

fn is_valid_top_k(k: Int) -> Bool {
  return k >= 1 && k <= 10000;
}

fn index_new(dim: Int) -> VectorIndex
  requires: dim > 0
{
  return VectorIndex{
    vectors: Vec[Vector].new(),
    ids: Vec[Int].new(),
    dim: dim,
  };
}

fn index_add(idx: &mut VectorIndex, id: Int, vec: Vector) -> Bool
  requires: idx.dim == vec.dimension
{
  var i: Int = 0;
  while i < idx.ids.len() {
    if idx.ids[i] == id {
      return false;
    }
    i = i + 1;
  }
  idx.vectors.push(vec);
  idx.ids.push(id);
  return true;
}

fn index_remove(idx: &mut VectorIndex, id: Int) -> Bool {
  var pos: Int = -1;
  var i: Int = 0;
  while i < idx.ids.len() {
    if idx.ids[i] == id {
      pos = i;
    }
    i = i + 1;
  }
  if pos == -1 {
    return false;
  }
  var last: Int = idx.ids.len() - 1;
  idx.vectors[pos] = idx.vectors[last];
  idx.ids[pos] = idx.ids[last];
  idx.vectors.pop();
  idx.ids.pop();
  return true;
}

fn index_get(idx: &VectorIndex, id: Int) -> Option[Vector] {
  var i: Int = 0;
  while i < idx.ids.len() {
    if idx.ids[i] == id {
      return Some(idx.vectors[i]);
    }
    i = i + 1;
  }
  return None;
}

fn index_size(idx: &VectorIndex) -> Int {
  return idx.ids.len();
}

// ---- Durable vector codec (mirrors engine.xi) ----
fn vector_encode(v: &Vector) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(v.dimension);
  var i: Int = 0;
  while i < v.dimension {
    out.push(float.float_bits(v.data[i] as Float64));
    i = i + 1;
  }
  return out;
}

fn vector_decode(payload: &Vec[Int]) -> Option[Vector] {
  if payload.len() < 1 { return None; }
  var dim = payload[0];
  if !is_valid_dimension(dim) { return None; }
  if payload.len() != dim + 1 { return None; }
  var v = vector_new(dim);
  var i: Int = 0;
  while i < dim {
    v.data[i] = float.bits_to_float(payload[i + 1]) as Float32;
    i = i + 1;
  }
  return Some(v);
}

fn search_knn(idx: &VectorIndex, query: &Vector, k: Int, metric: DistanceMetric) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    var result = SearchResult{ id: idx.ids[i], distance: dist };
    results.push(result);
    var pos: Int = results.len() - 1;
    while pos > 0 && results[pos - 1].distance > results[pos].distance {
      var tmp = results[pos];
      results[pos] = results[pos - 1];
      results[pos - 1] = tmp;
      pos = pos - 1;
    }
    if results.len() > k {
      results.pop();
    }
    i = i + 1;
  }
  return results;
}

// Exact range scan mirror (M-Q1): every distance <= radius, sorted, bounded.
fn search_range_scan(idx: &VectorIndex, query: &Vector, radius: Float32, limit: Int, metric: DistanceMetric) -> Vec[SearchResult]
  requires: limit > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= limit
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    if dist <= radius {
      var result = SearchResult{ id: idx.ids[i], distance: dist };
      results.push(result);
      var pos: Int = results.len() - 1;
      while pos > 0 && results[pos - 1].distance > results[pos].distance {
        var tmp = results[pos];
        results[pos] = results[pos - 1];
        results[pos - 1] = tmp;
        pos = pos - 1;
      }
      while results.len() > limit {
        results.pop();
      }
    }
    i = i + 1;
  }
  return results;
}

fn wal_writer_new() -> WalWriter {
  var records = Vec[WalRecord].new();
  return WalWriter{ records: records, next_lsn: 1, synced_lsn: 0 };
}

fn wal_writer_append(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int) -> Int {
  var assigned = w.next_lsn;
  var payload = Vec[Int].new();
  var rec = WalRecord{
    lsn: assigned, op: op, key: key, value: value, payload: payload, timestamp: 0,
  };
  w.records.push(rec);
  w.next_lsn = w.next_lsn + 1;
  return assigned;
}

fn wal_writer_current_lsn(w: &WalWriter) -> Int {
  return w.next_lsn - 1;
}

fn wal_writer_flush(w: &mut WalWriter) -> Bool {
  w.synced_lsn = w.next_lsn - 1;
  return true;
}

fn wal_writer_append_payload(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int, payload: Vec[Int]) -> Int {
  var assigned = w.next_lsn;
  var rec = WalRecord{
    lsn: assigned, op: op, key: key, value: value, payload: payload, timestamp: 0,
  };
  w.records.push(rec);
  w.next_lsn = w.next_lsn + 1;
  return assigned;
}

fn wal_writer_resume(next_lsn: Int) -> WalWriter {
  var records = Vec[WalRecord].new();
  return WalWriter{ records: records, next_lsn: next_lsn, synced_lsn: next_lsn - 1 };
}

fn wal_writer_checkpoint_from(w: &WalWriter, idx: &VectorIndex, payloads: &PayloadStore) -> WalWriter {
  var out = wal_writer_resume(w.next_lsn);
  var i: Int = 0;
  while i < idx.ids.len() {
    wal_writer_append_payload(&mut out, WalOpKind.Insert, idx.ids[i], 1, vector_encode(&idx.vectors[i]));
    i = i + 1;
  }
  var j: Int = 0;
  while j < payloads.entries.len() {
    wal_writer_append_payload(&mut out, WalOpKind.Update, payloads.entries[j].id, 1, payload_encode(&payloads.entries[j].payload));
    j = j + 1;
  }
  return out;
}

fn counter_new(name: Str) -> Counter {
  return Counter{ name: name, value: 0 };
}

fn counter_inc(c: &mut Counter) {
  c.value = c.value + 1;
}

fn engine_new() -> VectorEngine {
  return VectorEngine{
    store: index_new(1),
    metric: DistanceMetric.Euclidean,
    dimension: 0,
    created: false,
    wal: wal_writer_new(),
    upserts: counter_new("vector.upserts"),
    deletes: counter_new("vector.deletes"),
    next_collection: 1,
    payloads: payload_store_new(),
  };
}

fn engine_create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Option[CollectionId]
  requires: dim >= 1
{
  if !is_valid_dimension(dim) {
    return None;
  }
  eng.store = index_new(dim);
  eng.dimension = dim;
  eng.metric = metric;
  eng.created = true;
  eng.payloads = payload_store_new();
  var id = collection_id(eng.next_collection);
  eng.next_collection = eng.next_collection + 1;
  return Some(id);
}

fn engine_upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Bool {
  if vec.dimension != eng.dimension {
    return false;
  }
  var payload = vector_encode(&vec);
  wal_writer_append_payload(&mut eng.wal, WalOpKind.Insert, point, 1, payload);
  var ok = index_add(&mut eng.store, point, vec);
  counter_inc(&mut eng.upserts);
  return ok;
}

fn engine_search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[SearchHits, CoreError] {
  if query.dimension != eng.dimension {
    return Err(CoreError{ case: 1, msg: "dimension mismatch" });
  }
  if !is_valid_top_k(k) {
    return Err(CoreError{ case: 1, msg: "top_k out of range" });
  }
  var hits = search_knn(&eng.store, query, k, eng.metric);
  return Ok(SearchHits{ items: hits });
}

fn engine_delete(eng: &mut VectorEngine, point: Int) -> Bool {
  wal_writer_append(&mut eng.wal, WalOpKind.Delete, point, 1);
  var ok = index_remove(&mut eng.store, point);
  payload_store_remove(&mut eng.payloads, point);
  counter_inc(&mut eng.deletes);
  return ok;
}

// ---- Batch ops (mirrors engine.core; M-Q2) ----
fn engine_upsert_many(eng: &mut VectorEngine, ids: &Vec[Int], vecs: &Vec[Vector]) -> Result[Int, CoreError] {
  if ids.len() == 0 { return Err(CoreError{ case: 1, msg: "empty batch" }); }
  if ids.len() != vecs.len() { return Err(CoreError{ case: 1, msg: "batch length mismatch" }); }
  var i: Int = 0;
  while i < vecs.len() {
    if vecs[i].dimension != eng.dimension { return Err(CoreError{ case: 1, msg: "dimension mismatch" }); }
    i = i + 1;
  }
  i = 0;
  while i < ids.len() {
    if !engine_upsert(eng, ids[i], vecs[i]) { return Err(CoreError{ case: 1, msg: "upsert failed" }); }
    i = i + 1;
  }
  return Ok(ids.len());
}

fn engine_delete_many(eng: &mut VectorEngine, ids: &Vec[Int]) -> Result[Int, CoreError] {
  if ids.len() == 0 { return Err(CoreError{ case: 1, msg: "empty batch" }); }
  var removed: Int = 0;
  var i: Int = 0;
  while i < ids.len() {
    if engine_delete(eng, ids[i]) { removed = removed + 1; }
    i = i + 1;
  }
  return Ok(removed);
}

fn engine_search_many(eng: &VectorEngine, queries: &Vec[Vector], k: Int) -> Result[BatchHits, CoreError] {
  if queries.len() == 0 { return Err(CoreError{ case: 1, msg: "empty batch" }); }
  if !is_valid_top_k(k) { return Err(CoreError{ case: 1, msg: "top_k out of range" }); }
  var i: Int = 0;
  while i < queries.len() {
    if queries[i].dimension != eng.dimension { return Err(CoreError{ case: 1, msg: "dimension mismatch" }); }
    i = i + 1;
  }
  var sets = Vec[SearchHits].new();
  i = 0;
  while i < queries.len() {
    match engine_search(eng, &queries[i], k) {
      Ok(h) => { sets.push(h); }
      Err(e) => { return Err(e); }
    }
    i = i + 1;
  }
  return Ok(BatchHits{ sets: sets });
}

// ---- Payload metadata + filtered search (mirrors engine.xi) ----
fn engine_set_payload(eng: &mut VectorEngine, point: Int, payload: Payload) -> Result[Bool, CoreError] {
  match index_get(&eng.store, point) {
    Some(_) => {
      var words = payload_encode(&payload);
      wal_writer_append_payload(&mut eng.wal, WalOpKind.Update, point, 1, words);
      payload_store_put(&mut eng.payloads, point, payload);
      return Ok(true);
    }
    None => { return Ok(false); }
  }
}

fn engine_get_payload(eng: &VectorEngine, point: Int) -> Option[Payload] {
  return payload_store_get(&eng.payloads, point);
}

fn engine_search_filtered(eng: &VectorEngine, query: &Vector, k: Int, filter: &FilterExpr) -> Result[SearchHits, CoreError] {
  if query.dimension != eng.dimension {
    return Err(CoreError{ case: 1, msg: "dimension mismatch" });
  }
  if !is_valid_top_k(k) {
    return Err(CoreError{ case: 1, msg: "top_k out of range" });
  }
  var hits = search_knn_filtered(&eng.store, &eng.payloads, query, k, eng.metric, filter);
  return Ok(SearchHits{ items: hits });
}

// Request-driven search mirroring engine/core.xi (top_k/filter/with_payload
// from the request; the collection metric governs).
fn engine_search_request(eng: &VectorEngine, req: &SearchRequest) -> Result[HydratedHits, CoreError] {
  if !eng.created {
    return Err(CoreError{ case: 2, msg: "not created" });
  }
  if req.query.dimension != eng.dimension {
    return Err(CoreError{ case: 1, msg: "dimension mismatch" });
  }
  if !is_valid_top_k(req.top_k) {
    return Err(CoreError{ case: 1, msg: "top_k out of range" });
  }
  if req.metric != eng.metric {
    return Err(CoreError{ case: 1, msg: "metric mismatch" });
  }
  if search_request_has_filter(req) {
    var hits = search_knn_filtered(&eng.store, &eng.payloads, &req.query, req.top_k, eng.metric, &req.filter[0]);
    return Ok(HydratedHits{ items: hydrate_hits(&hits, &eng.payloads, req.with_payload) });
  }
  var hits = search_knn(&eng.store, &req.query, req.top_k, eng.metric);
  return Ok(HydratedHits{ items: hydrate_hits(&hits, &eng.payloads, req.with_payload) });
}

fn engine_size(eng: &VectorEngine) -> Int {
  return index_size(&eng.store);
}

fn engine_durable_lsn(eng: &VectorEngine) -> Int {
  return wal_writer_current_lsn(&eng.wal);
}

// ---- Recovery replay: store + payloads (mirrors engine.xi) ----
fn recover_state(w: &WalWriter, dim: Int) -> RecoveredState
  requires: dim > 0
{
  var idx = index_new(dim);
  var pls = payload_store_new();
  var i: Int = 0;
  while i < w.records.len() {
    var op = w.records[i].op;
    var key = w.records[i].key;
    match op {
      Insert => {
        match vector_decode(&w.records[i].payload) {
          Some(v) => {
            if v.dimension == dim { index_add(&mut idx, key, v); }
          }
          None => {}
        }
      }
      Delete => {
        index_remove(&mut idx, key);
        payload_store_remove(&mut pls, key);
      }
      Update => {
        match payload_decode(&w.records[i].payload) {
          Some(p) => { payload_store_put(&mut pls, key, p); }
          None => {}
        }
      }
      _ => {}
    }
    i = i + 1;
  }
  return RecoveredState{ store: idx, payloads: pls };
}

fn recover_store(w: &WalWriter, dim: Int) -> VectorIndex
  requires: dim > 0
{
  var st = recover_state(w, dim);
  return st.store;
}

fn engine_recover(w: &WalWriter, dim: Int, metric: DistanceMetric) -> VectorEngine
  requires: dim > 0
{
  var eng = engine_new();
  var st = recover_state(w, dim);
  eng.store = st.store;
  eng.payloads = st.payloads;
  eng.dimension = dim;
  eng.metric = metric;
  eng.created = true;
  eng.wal = wal_writer_checkpoint_from(w, &eng.store, &eng.payloads);
  return eng;
}

// ============================================================================
// Helper: segment operations
// ============================================================================

fn segment_state_code(s: &SegmentStateKind) -> Int {
  match s {
    Mutable => 0,
    Sealing => 1,
    Sealed => 2,
    Indexing => 3,
    Immutable => 4,
    Compacting => 5,
    Dropped => 6,
  }
}

fn segment_state_can_transition(from: &SegmentStateKind, to: &SegmentStateKind) -> Bool {
  var f = segment_state_code(from);
  var t = segment_state_code(to);
  if f == 0 { return t == 1; }
  if f == 1 { return t == 2; }
  if f == 2 { return t == 3; }
  if f == 3 { return t == 4; }
  if f == 4 { return t == 5 || t == 6; }
  if f == 5 { return t == 4 || t == 6; }
  return false;
}

fn segment_state_is_writable(s: &SegmentStateKind) -> Bool {
  match s {
    Mutable => true,
    _ => false,
  }
}

fn segment_state_is_terminal(s: &SegmentStateKind) -> Bool {
  match s {
    Dropped => true,
    _ => false,
  }
}

fn segment_new(id: SegmentId, dim: Int) -> Segment
  requires: dim > 0
{
  return Segment{
    id: id,
    state: SegmentStateKind.Mutable,
    store: index_new(dim),
  };
}

fn segment_insert(seg: &mut Segment, id: Int, vec: Vector) -> Bool
  requires: seg.store.dim == vec.dimension
{
  return index_add(&mut seg.store, id, vec);
}

fn segment_transition(seg: &mut Segment, to: SegmentStateKind) -> Bool {
  if !segment_state_can_transition(&seg.state, &to) {
    return false;
  }
  seg.state = to;
  return true;
}

fn segment_size(seg: &Segment) -> Int {
  return index_size(&seg.store);
}

fn segment_is_writable(seg: &Segment) -> Bool {
  return segment_state_is_writable(&seg.state);
}

// ============================================================================
// Helper: manifest operations
// ============================================================================

fn manifest_new(collection: CollectionId) -> Manifest {
  var segs = Vec[SegmentId].new();
  return Manifest{ collection: collection, active_segments: segs, last_lsn: 0 };
}

fn manifest_add_segment(m: &mut Manifest, seg: SegmentId) {
  m.active_segments.push(seg);
}

fn manifest_remove_segment(m: &mut Manifest, seg: SegmentId) -> Bool {
  var i: Int = 0;
  while i < m.active_segments.len() {
    if segment_id_eq(&m.active_segments[i], &seg) {
      var last: Int = m.active_segments.len() - 1;
      m.active_segments[i] = m.active_segments[last];
      m.active_segments.pop();
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn manifest_set_lsn(m: &mut Manifest, lsn: Int) {
  m.last_lsn = lsn;
}

fn manifest_segment_count(m: &Manifest) -> Int {
  return m.active_segments.len();
}

// ============================================================================
// Helper: id_map operations
// ============================================================================

fn id_map_new() -> IdMap {
  var entries = Vec[IdMapEntry].new();
  return IdMap{ entries: entries };
}

fn id_map_put(m: &mut IdMap, vec_id: Int, segment: Int, offset: Int) {
  var i: Int = 0;
  while i < m.entries.len() {
    if m.entries[i].vector_id == vec_id {
      m.entries[i] = IdMapEntry{ vector_id: vec_id, segment: segment, offset: offset };
      return;
    }
    i = i + 1;
  }
  m.entries.push(IdMapEntry{ vector_id: vec_id, segment: segment, offset: offset });
}

fn id_map_lookup(m: &IdMap, vec_id: Int) -> Option[IdMapEntry] {
  var i: Int = 0;
  while i < m.entries.len() {
    if m.entries[i].vector_id == vec_id {
      return Some(m.entries[i]);
    }
    i = i + 1;
  }
  return None;
}

fn id_map_remove(m: &mut IdMap, vec_id: Int) -> Bool {
  var i: Int = 0;
  while i < m.entries.len() {
    if m.entries[i].vector_id == vec_id {
      var last: Int = m.entries.len() - 1;
      m.entries[i] = m.entries[last];
      m.entries.pop();
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn id_map_len(m: &IdMap) -> Int {
  return m.entries.len();
}

// ============================================================================
// Helper: payload operations
// ============================================================================

fn payload_new() -> Payload {
  var fields = Vec[PayloadField].new();
  return Payload{ fields: fields };
}

fn payload_set(p: &mut Payload, key: Str, value: FieldValue) {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key {
      p.fields[i].value = value;
      return;
    }
    i = i + 1;
  }
  p.fields.push(PayloadField{ key: key, value: value });
}

fn payload_has(p: &Payload, key: Str) -> Bool {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn payload_get(p: &Payload, key: Str) -> Option[FieldValue] {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key { return Some(p.fields[i].value); }
    i = i + 1;
  }
  return None;
}

fn payload_len(p: &Payload) -> Int {
  return p.fields.len();
}

fn field_value_kind(v: &FieldValue) -> Str {
  match v {
    IntVal(_) => "int",
    FloatVal(_) => "float",
    TextVal(_) => "text",
    BoolVal(_) => "bool",
  }
}

fn field_value_eq(a: &FieldValue, b: &FieldValue) -> Bool {
  match a {
    IntVal(av) => {
      match b { IntVal(bv) => { return av == bv; } _ => { return false; } }
    }
    FloatVal(av) => {
      match b { FloatVal(bv) => { return av == bv; } _ => { return false; } }
    }
    TextVal(av) => {
      match b { TextVal(bv) => { return av == bv; } _ => { return false; } }
    }
    BoolVal(av) => {
      match b { BoolVal(bv) => { return av == bv; } _ => { return false; } }
    }
  }
}

fn field_value_as_float(v: &FieldValue) -> Option[Float32] {
  match v {
    FloatVal(f) => {
      var out: Float32 = f;
      return Some(out);
    }
    IntVal(i) => {
      var out: Float32 = i as Float32;
      return Some(out);
    }
    _ => { return None; }
  }
}

// ---- Payload WAL codec (mirrors engine.xi; keep the two in sync) ----
fn push_str_words(out: &mut Vec[Int], s: Str) {
  var bytes = slice.str_bytes(s);
  out.push(bytes.len());
  var i: Int = 0;
  while i < bytes.len() {
    out.push(bytes[i] as Int);
    i = i + 1;
  }
}

fn payload_encode(p: &Payload) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(1);
  out.push(p.fields.len());
  var i: Int = 0;
  while i < p.fields.len() {
    push_str_words(&mut out, p.fields[i].key);
    var fv = p.fields[i].value;
    match fv {
      IntVal(v) => { out.push(1); out.push(v); }
      FloatVal(f) => { out.push(2); out.push(float.float_bits(f as Float64)); }
      TextVal(t) => { out.push(3); push_str_words(&mut out, t); }
      BoolVal(b) => {
        out.push(4);
        if b { out.push(1); } else { out.push(0); }
      }
    }
    i = i + 1;
  }
  return out;
}

fn payload_decode(words: &Vec[Int]) -> Option[Payload] {
  if words.len() < 2 { return None; }
  if words[0] != 1 { return None; }
  var count = words[1];
  if count < 0 { return None; }
  var out = payload_new();
  var pos: Int = 2;
  var i: Int = 0;
  while i < count {
    if pos >= words.len() { return None; }
    var klen = words[pos];
    pos = pos + 1;
    if klen < 0 || pos + klen > words.len() { return None; }
    var kb = Vec[UInt8].new();
    var j: Int = 0;
    while j < klen {
      kb.push(words[pos + j] as UInt8);
      j = j + 1;
    }
    pos = pos + klen;
    var key = Str::from_utf8(&kb);
    if pos >= words.len() { return None; }
    var kind = words[pos];
    pos = pos + 1;
    if kind == 1 {
      if pos >= words.len() { return None; }
      var iv = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.IntVal(iv));
    } elif kind == 2 {
      if pos >= words.len() { return None; }
      var bits = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.FloatVal(float.bits_to_float(bits) as Float32));
    } elif kind == 3 {
      if pos >= words.len() { return None; }
      var tlen = words[pos];
      pos = pos + 1;
      if tlen < 0 || pos + tlen > words.len() { return None; }
      var tb = Vec[UInt8].new();
      var k: Int = 0;
      while k < tlen {
        tb.push(words[pos + k] as UInt8);
        k = k + 1;
      }
      pos = pos + tlen;
      payload_set(&mut out, key, FieldValue.TextVal(Str::from_utf8(&tb)));
    } elif kind == 4 {
      if pos >= words.len() { return None; }
      var bv = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.BoolVal(bv != 0));
    } else {
      return None;
    }
    i = i + 1;
  }
  return Some(out);
}

// ============================================================================
// Helper: filter operations
// ============================================================================

fn filter_eq(field: Str, value: FieldValue) -> FilterExpr {
  return FilterExpr.Eq(field, value);
}

fn filter_range(field: Str, lo: Float32, hi: Float32) -> FilterExpr {
  return FilterExpr.Range(field, lo, hi);
}

fn filter_exists(field: Str) -> FilterExpr {
  return FilterExpr.Exists(field);
}

fn filter_in(field: Str, values: Vec[FieldValue]) -> FilterExpr {
  return FilterExpr.In(field, values);
}

fn filter_and(clauses: Vec[FilterExpr]) -> FilterExpr {
  return FilterExpr.And(clauses);
}

fn filter_or(clauses: Vec[FilterExpr]) -> FilterExpr {
  return FilterExpr.Or(clauses);
}

fn filter_not(clause: FilterExpr) -> FilterExpr {
  var clauses = Vec[FilterExpr].new();
  clauses.push(clause);
  return FilterExpr.Not(clauses);
}

fn filter_matches(expr: &FilterExpr, p: &Payload) -> Bool {
  match expr {
    Eq(field, value) => {
      // Capture the match bindings into locals BEFORE any nested call/match:
      // in this compilation unit the payload binds read back corrupted when
      // consumed after the nested match (XVC-C-05 class). Same semantics.
      var key: Str = field;
      var want: FieldValue = value;
      match payload_get(p, key) {
        Some(fv) => { return field_value_eq(&fv, &want); }
        None => { return false; }
      }
    }
    Range(field, lo, hi) => {
      var key: Str = field;
      var lo_v: Float32 = lo;
      var hi_v: Float32 = hi;
      match payload_get(p, key) {
        Some(fv) => {
          // Direct two-level match on the local Option payload: passing
          // `&fv` into a helper corrupted the Float32 payload in this unit
          // (XVC-C-05 class), so extract inline.
          match fv {
            FloatVal(f) => {
              var got: Float32 = f;
              if got < lo_v { return false; }
              if got > hi_v { return false; }
              return true;
            }
            IntVal(i) => {
              var got: Float32 = i as Float32;
              if got < lo_v { return false; }
              if got > hi_v { return false; }
              return true;
            }
            _ => { return false; }
          }
        }
        None => { return false; }
      }
    }
    Exists(field) => {
      return payload_has(p, field);
    }
    In(field, values) => {
      var key: Str = field;
      match payload_get(p, key) {
        Some(fv) => {
          var i: Int = 0;
          while i < values.len() {
            if field_value_eq(&fv, &values[i]) { return true; }
            i = i + 1;
          }
          return false;
        }
        None => { return false; }
      }
    }
    And(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if !filter_matches(&clauses[i], p) {
          return false;
        }
        i = i + 1;
      }
      return true;
    }
    Or(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if filter_matches(&clauses[i], p) {
          return true;
        }
        i = i + 1;
      }
      return false;
    }
    Not(clauses) => {
      if clauses.len() == 0 {
        return true;
      }
      return !filter_matches(&clauses[0], p);
    }
  }
}

fn filter_matches_empty(expr: &FilterExpr) -> Bool {
  match expr {
    And(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if !filter_matches_empty(&clauses[i]) { return false; }
        i = i + 1;
      }
      return true;
    }
    Or(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if filter_matches_empty(&clauses[i]) { return true; }
        i = i + 1;
      }
      return false;
    }
    Not(clauses) => {
      if clauses.len() == 0 { return true; }
      return !filter_matches_empty(&clauses[0]);
    }
    _ => { return false; }
  }
}

// ============================================================================
// Helper: payload store + filtered search (mirrors engine.xi)
// ============================================================================

fn payload_store_new() -> PayloadStore {
  var entries = Vec[PayloadEntry].new();
  return PayloadStore{ entries: entries };
}

fn payload_store_put(s: &mut PayloadStore, id: Int, payload: Payload) {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id {
      s.entries[i].payload = payload;
      return;
    }
    i = i + 1;
  }
  s.entries.push(PayloadEntry{ id: id, payload: payload });
}

fn payload_store_get(s: &PayloadStore, id: Int) -> Option[Payload] {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { return Some(s.entries[i].payload); }
    i = i + 1;
  }
  return None;
}

fn payload_store_remove(s: &mut PayloadStore, id: Int) -> Bool {
  var pos: Int = -1;
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { pos = i; }
    i = i + 1;
  }
  if pos == -1 { return false; }
  var last: Int = s.entries.len() - 1;
  s.entries[pos] = s.entries[last];
  s.entries.pop();
  return true;
}

fn payload_store_len(s: &PayloadStore) -> Int {
  return s.entries.len();
}

fn payload_store_matches(s: &PayloadStore, id: Int, expr: &FilterExpr) -> Bool {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id {
      return filter_matches(expr, &s.entries[i].payload);
    }
    i = i + 1;
  }
  return filter_matches_empty(expr);
}

fn results_push_bounded(results: &mut Vec[SearchResult], item: SearchResult, k: Int) {
  results.push(item);
  var pos: Int = results.len() - 1;
  while pos > 0 && results[pos - 1].distance > results[pos].distance {
    var tmp = results[pos];
    results[pos] = results[pos - 1];
    results[pos - 1] = tmp;
    pos = pos - 1;
  }
  if results.len() > k {
    results.pop();
  }
}

fn search_knn_filtered(idx: &VectorIndex, payloads: &PayloadStore, query: &Vector, k: Int, metric: DistanceMetric, filter: &FilterExpr) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    if payload_store_matches(payloads, idx.ids[i], filter) {
      var dist = vector_distance(&idx.vectors[i], query, metric);
      results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    }
    i = i + 1;
  }
  return results;
}

// Payload hydration mirroring query/search_service.xi.
fn hydrate_hits(items: &Vec[SearchResult], payloads: &PayloadStore, with_payload: Bool) -> Vec[SearchHit] {
  var out = Vec[SearchHit].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = payload_new();
    var have: Bool = false;
    if with_payload {
      match payload_store_get(payloads, items[i].id) {
        Some(found) => { pl = found; have = true; }
        None => {}
      }
    }
    out.push(SearchHit{ id: items[i].id, distance: items[i].distance, payload: pl, has_payload: have });
    i = i + 1;
  }
  return out;
}

// ============================================================================
// Helper: topk_heap operations
// ============================================================================

fn topk_new(capacity: Int) -> TopKHeap
  requires: capacity > 0
{
  var items = Vec[Neighbor].new();
  return TopKHeap{ capacity: capacity, items: items };
}

fn topk_push(h: &mut TopKHeap, n: Neighbor)
  requires: h.capacity > 0
{
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

fn topk_len(h: &TopKHeap) -> Int {
  return h.items.len();
}

fn topk_is_full(h: &TopKHeap) -> Bool {
  return h.items.len() >= h.capacity;
}

fn topk_worst(h: &TopKHeap) -> Option[Neighbor] {
  if h.items.len() == 0 {
    return None;
  }
  return Some(h.items[h.items.len() - 1]);
}

// ============================================================================
// Helper: collection/schema operations
// ============================================================================

fn schema_new(dimension: Int, metric: DistanceMetric) -> CollectionSchema
  requires: is_valid_dimension(dimension)
{
  var fields = Vec[PayloadFieldSpec].new();
  return CollectionSchema{
    dimension: dimension,
    metric: metric,
    normalization: NormalizationMode.Raw,
    payload_fields: fields,
  };
}

fn schema_set_normalization(s: &mut CollectionSchema, mode: NormalizationMode) {
  s.normalization = mode;
}

fn schema_add_field(s: &mut CollectionSchema, name: Str, indexed: Bool) {
  s.payload_fields.push(PayloadFieldSpec{ name: name, indexed: indexed });
}

fn schema_dimension(s: &CollectionSchema) -> Int {
  return s.dimension;
}

fn ann_params_default() -> AnnParams {
  return AnnParams{ m: 16, ef_construction: 200, ef_search: 64 };
}

fn ann_params_valid(p: &AnnParams) -> Bool {
  if p.m <= 0 { return false; }
  if p.m > 512 { return false; }
  if p.ef_construction <= 0 { return false; }
  if p.ef_search <= 0 { return false; }
  return true;
}

fn ann_index_kind_name(k: &AnnIndexKind) -> Str {
  match k {
    Flat => "flat",
    Hnsw => "hnsw",
    Ivf => "ivf",
  }
}

fn collection_new(id: CollectionId, schema: CollectionSchema, index_kind: AnnIndexKind) -> Collection {
  var segments = Vec[SegmentId].new();
  return Collection{
    id: id,
    schema: schema,
    segments: segments,
    index_kind: index_kind,
    index_params: ann_params_default(),
  };
}

fn collection_register_segment(c: &mut Collection, seg: SegmentId) {
  c.segments.push(seg);
}

fn collection_segment_count(c: &Collection) -> Int {
  return c.segments.len();
}

fn collection_dimension(c: &Collection) -> Int {
  return schema_dimension(&c.schema);
}

fn validate_dimension(schema: &CollectionSchema, dim: Int) -> Bool {
  return schema.dimension == dim;
}

fn validate_metric(schema: &CollectionSchema, metric: DistanceMetric) -> Bool {
  match metric {
    Cosine => true,
    DotProduct => true,
    Euclidean => true,
  }
}

// ============================================================================
// Helper: dimension operations
// ============================================================================

fn dimension(v: Int) -> Dimension
  requires: v >= 1
{
  return Dimension{ value: v };
}

fn dimension_value(d: &Dimension) -> Int {
  return d.value;
}

fn dimension_eq(a: &Dimension, b: &Dimension) -> Bool {
  return a.value == b.value;
}

fn dimension_is_valid(v: Int) -> Bool {
  return v >= 1 && v <= 65536;
}

fn dimension_within_limit(v: Int) -> Bool {
  return v >= 1 && v <= 65536;
}

// ============================================================================
// Helper: error operations
// ============================================================================

fn vector_error_to_str(e: &VectorError) -> Str {
  match e {
    DimensionMismatch(_, _) => "vector dimension mismatch",
    UnsupportedMetric(_) => "unsupported distance metric",
    CollectionNotFound(_) => "collection not found",
    InvalidVector(_) => "invalid vector",
    SegmentSealed(_) => "segment is sealed",
    TopKExceeded(_, _) => "top_k exceeds maximum",
  }
}

fn vector_error_code(e: &VectorError) -> Int {
  match e {
    DimensionMismatch(_, _) => 1001,
    UnsupportedMetric(_) => 1002,
    CollectionNotFound(_) => 1003,
    InvalidVector(_) => 1004,
    SegmentSealed(_) => 1005,
    TopKExceeded(_, _) => 1006,
  }
}

// ============================================================================
// SECTION 1: Types -- VectorId, CollectionId, SegmentId construction
// ============================================================================

fn run_types_vector_id_construct() -> Int {
  var vid = vector_id(42);
  if vector_id_value(&vid) == 42 { return 0; }
  return 1;
}
fn test_types_vector_id_construct() -> TestResult {
  if run_types_vector_id_construct() == 0 { return assert(true, "VectorId: construction stores value 42"); }
  return assert(false, "VectorId: construction failed");
}

fn run_types_collection_id_construct() -> Int {
  var cid = collection_id(7);
  if cid.value == 7 { return 0; }
  return 1;
}
fn test_types_collection_id_construct() -> TestResult {
  if run_types_collection_id_construct() == 0 { return assert(true, "CollectionId: construction stores value 7"); }
  return assert(false, "CollectionId: construction failed");
}

fn run_types_segment_id_construct() -> Int {
  var sid = segment_id(99);
  if sid.value == 99 { return 0; }
  return 1;
}
fn test_types_segment_id_construct() -> TestResult {
  if run_types_segment_id_construct() == 0 { return assert(true, "SegmentId: construction stores value 99"); }
  return assert(false, "SegmentId: construction failed");
}

fn run_types_segment_id_eq() -> Int {
  var a = segment_id(5);
  var b = segment_id(5);
  var c = segment_id(6);
  if segment_id_eq(&a, &b) && !segment_id_eq(&a, &c) { return 0; }
  return 1;
}
fn test_types_segment_id_eq() -> TestResult {
  if run_types_segment_id_eq() == 0 { return assert(true, "SegmentId: eq same(5==5) true, diff(5!=6) false"); }
  return assert(false, "SegmentId: eq failed");
}

fn run_types_dimension_construct() -> Int {
  var d = dimension(128);
  if dimension_value(&d) == 128 { return 0; }
  return 1;
}
fn test_types_dimension_construct() -> TestResult {
  if run_types_dimension_construct() == 0 { return assert(true, "Dimension: construction stores 128"); }
  return assert(false, "Dimension: construction failed");
}

fn run_types_dimension_eq() -> Int {
  var a = dimension(64);
  var b = dimension(64);
  var c = dimension(128);
  if dimension_eq(&a, &b) && !dimension_eq(&a, &c) { return 0; }
  return 1;
}
fn test_types_dimension_eq() -> TestResult {
  if run_types_dimension_eq() == 0 { return assert(true, "Dimension: eq same(64==64) true, diff(64!=128) false"); }
  return assert(false, "Dimension: eq failed");
}

fn run_types_dimension_is_valid() -> Int {
  var ok = dimension_is_valid(1) && dimension_is_valid(65536) && !dimension_is_valid(0) && !dimension_is_valid(99999);
  if ok { return 0; }
  return 1;
}
fn test_types_dimension_is_valid() -> TestResult {
  if run_types_dimension_is_valid() == 0 { return assert(true, "Dimension: is_valid(1,65536)=true, is_valid(0,99999)=false"); }
  return assert(false, "Dimension: is_valid failed");
}

// ============================================================================
// SECTION 2: Distance metrics -- L2, cosine, dot product correctness
// ============================================================================

fn run_distance_euclidean_same() -> Int {
  var v = vector_new(3);
  vector_set(&mut v, 0, 1.0);
  vector_set(&mut v, 1, 2.0);
  vector_set(&mut v, 2, 3.0);
  var d = euclidean_distance(&v, &v);
  if f32_eq(d, 0.0) { return 0; }
  return 1;
}
fn test_distance_euclidean_same() -> TestResult {
  if run_distance_euclidean_same() == 0 { return assert(true, "Euclidean: same vector = 0.0"); }
  return assert(false, "Euclidean: same vector != 0.0");
}

fn run_distance_euclidean_345() -> Int {
  var a = vector_new(2);
  vector_set(&mut a, 0, 0.0);
  vector_set(&mut a, 1, 0.0);
  var b = vector_new(2);
  vector_set(&mut b, 0, 3.0);
  vector_set(&mut b, 1, 4.0);
  var d = euclidean_distance(&a, &b);
  if f32_eq(d, 5.0) { return 0; }
  return 1;
}
fn test_distance_euclidean_345() -> TestResult {
  if run_distance_euclidean_345() == 0 { return assert(true, "Euclidean: (0,0) to (3,4) = 5.0"); }
  return assert(false, "Euclidean: 3-4-5 check failed");
}

fn run_distance_cosine_identical() -> Int {
  var v = vector_new(3);
  vector_set(&mut v, 0, 1.0);
  vector_set(&mut v, 1, 2.0);
  vector_set(&mut v, 2, 3.0);
  var d = cosine_distance(&v, &v);
  if f32_eq(d, 0.0) { return 0; }
  return 1;
}
fn test_distance_cosine_identical() -> TestResult {
  if run_distance_cosine_identical() == 0 { return assert(true, "Cosine: identical vector = 0.0"); }
  return assert(false, "Cosine: identical vector != 0.0");
}

fn run_distance_cosine_orthogonal() -> Int {
  var a = vector_new(2);
  vector_set(&mut a, 0, 1.0);
  vector_set(&mut a, 1, 0.0);
  var b = vector_new(2);
  vector_set(&mut b, 0, 0.0);
  vector_set(&mut b, 1, 1.0);
  var d = cosine_distance(&a, &b);
  if f32_eq(d, 1.0) { return 0; }
  return 1;
}
fn test_distance_cosine_orthogonal() -> TestResult {
  if run_distance_cosine_orthogonal() == 0 { return assert(true, "Cosine: orthogonal vectors = 1.0"); }
  return assert(false, "Cosine: orthogonal check failed");
}

fn run_distance_cosine_opposite() -> Int {
  var a = vector_new(2);
  vector_set(&mut a, 0, 1.0);
  vector_set(&mut a, 1, 0.0);
  var b = vector_new(2);
  vector_set(&mut b, 0, -1.0);
  vector_set(&mut b, 1, 0.0);
  var d = cosine_distance(&a, &b);
  if f32_eq(d, 2.0) { return 0; }
  return 1;
}
fn test_distance_cosine_opposite() -> TestResult {
  if run_distance_cosine_opposite() == 0 { return assert(true, "Cosine: opposite vectors = 2.0"); }
  return assert(false, "Cosine: opposite check failed");
}

fn run_distance_cosine_zero_vector() -> Int {
  var a = vector_new(3);
  var b = vector_new(3);
  vector_set(&mut b, 0, 1.0);
  vector_set(&mut b, 1, 2.0);
  vector_set(&mut b, 2, 3.0);
  var d = cosine_distance(&a, &b);
  if f32_eq(d, 1.0) { return 0; }
  return 1;
}
fn test_distance_cosine_zero_vector() -> TestResult {
  if run_distance_cosine_zero_vector() == 0 { return assert(true, "Cosine: zero vector = 1.0 guard"); }
  return assert(false, "Cosine: zero vector guard failed");
}

fn run_distance_dot_same() -> Int {
  var v = vector_new(3);
  vector_set(&mut v, 0, 2.0);
  vector_set(&mut v, 1, 3.0);
  vector_set(&mut v, 2, 4.0);
  var d = dot_product_distance(&v, &v);
  if f32_eq(d, -29.0) { return 0; }
  return 1;
}
fn test_distance_dot_same() -> TestResult {
  if run_distance_dot_same() == 0 { return assert(true, "DotProduct: (2,3,4) self = -29.0"); }
  return assert(false, "DotProduct: self check failed");
}

fn run_distance_dot_orthogonal() -> Int {
  var a = vector_new(2);
  vector_set(&mut a, 0, 1.0);
  vector_set(&mut a, 1, 0.0);
  var b = vector_new(2);
  vector_set(&mut b, 0, 0.0);
  vector_set(&mut b, 1, 1.0);
  var d = dot_product_distance(&a, &b);
  if f32_eq(d, 0.0) { return 0; }
  return 1;
}
fn test_distance_dot_orthogonal() -> TestResult {
  if run_distance_dot_orthogonal() == 0 { return assert(true, "DotProduct: orthogonal = 0.0"); }
  return assert(false, "DotProduct: orthogonal check failed");
}

fn run_distance_dispatch_euclidean() -> Int {
  var a = vector_new(2);
  vector_set(&mut a, 0, 1.0);
  var b = vector_new(2);
  vector_set(&mut b, 0, 4.0);
  var d = vector_distance(&a, &b, DistanceMetric.Euclidean);
  if f32_eq(d, 3.0) { return 0; }
  return 1;
}
fn test_distance_dispatch_euclidean() -> TestResult {
  if run_distance_dispatch_euclidean() == 0 { return assert(true, "vector_distance: Euclidean dispatch"); }
  return assert(false, "vector_distance: Euclidean dispatch failed");
}

fn run_distance_dispatch_cosine() -> Int {
  var v = vector_new(2);
  vector_set(&mut v, 0, 5.0);
  var d = vector_distance(&v, &v, DistanceMetric.Cosine);
  if f32_eq(d, 0.0) { return 0; }
  return 1;
}
fn test_distance_dispatch_cosine() -> TestResult {
  if run_distance_dispatch_cosine() == 0 { return assert(true, "vector_distance: Cosine dispatch"); }
  return assert(false, "vector_distance: Cosine dispatch failed");
}

fn run_distance_dispatch_dot() -> Int {
  var a = vector_new(2);
  vector_set(&mut a, 0, 2.0);
  vector_set(&mut a, 1, 3.0);
  var b = vector_new(2);
  vector_set(&mut b, 0, 4.0);
  vector_set(&mut b, 1, 1.0);
  var d = vector_distance(&a, &b, DistanceMetric.DotProduct);
  if f32_eq(d, -11.0) { return 0; }
  return 1;
}
fn test_distance_dispatch_dot() -> TestResult {
  if run_distance_dispatch_dot() == 0 { return assert(true, "vector_distance: DotProduct dispatch"); }
  return assert(false, "vector_distance: DotProduct dispatch failed");
}

fn run_distance_magnitude() -> Int {
  var v = vector_new(3);
  vector_set(&mut v, 0, 3.0);
  vector_set(&mut v, 1, 4.0);
  vector_set(&mut v, 2, 0.0);
  var mag = vector_magnitude(&v);
  if f32_eq(mag, 5.0) { return 0; }
  return 1;
}
fn test_distance_magnitude() -> TestResult {
  if run_distance_magnitude() == 0 { return assert(true, "Magnitude: (3,4,0) = 5.0"); }
  return assert(false, "Magnitude: 3-4-5 check failed");
}

fn run_distance_magnitude_zero() -> Int {
  var v = vector_new(5);
  var mag = vector_magnitude(&v);
  if f32_eq(mag, 0.0) { return 0; }
  return 1;
}
fn test_distance_magnitude_zero() -> TestResult {
  if run_distance_magnitude_zero() == 0 { return assert(true, "Magnitude: zero vector = 0.0"); }
  return assert(false, "Magnitude: zero vector check failed");
}

fn run_distance_dot_raw() -> Int {
  var a = vector_new(2);
  vector_set(&mut a, 0, 2.0);
  vector_set(&mut a, 1, 3.0);
  var b = vector_new(2);
  vector_set(&mut b, 0, 4.0);
  vector_set(&mut b, 1, 5.0);
  var dot = vector_dot(&a, &b);
  if f32_eq(dot, 23.0) { return 0; }
  return 1;
}
fn test_distance_dot_raw() -> TestResult {
  if run_distance_dot_raw() == 0 { return assert(true, "Dot: (2,3)*(4,5) = 23.0"); }
  return assert(false, "Dot: raw dot check failed");
}

// ============================================================================
// SECTION 3: Vector store -- insert, search, delete operations
// ============================================================================

fn run_store_index_new() -> Int {
  var idx = index_new(4);
  if idx.dim == 4 && index_size(&idx) == 0 { return 0; }
  return 1;
}
fn test_store_index_new() -> TestResult {
  if run_store_index_new() == 0 { return assert(true, "VectorIndex: new creates dim=4 empty store"); }
  return assert(false, "VectorIndex: new failed");
}

fn run_store_index_add() -> Int {
  var idx = index_new(2);
  var v = vector_new(2);
  vector_set(&mut v, 0, 1.0);
  vector_set(&mut v, 1, 2.0);
  var ok = index_add(&mut idx, 100, v);
  if ok && index_size(&idx) == 1 { return 0; }
  return 1;
}
fn test_store_index_add() -> TestResult {
  if run_store_index_add() == 0 { return assert(true, "VectorIndex: add returns true, size=1"); }
  return assert(false, "VectorIndex: add failed");
}

fn run_store_index_add_duplicate() -> Int {
  var idx = index_new(2);
  var v1 = vector_new(2);
  vector_set(&mut v1, 0, 1.0);
  var v2 = vector_new(2);
  vector_set(&mut v2, 0, 2.0);
  index_add(&mut idx, 10, v1);
  var ok = index_add(&mut idx, 10, v2);
  if !ok && index_size(&idx) == 1 { return 0; }
  return 1;
}
fn test_store_index_add_duplicate() -> TestResult {
  if run_store_index_add_duplicate() == 0 { return assert(true, "VectorIndex: duplicate id returns false"); }
  return assert(false, "VectorIndex: duplicate id check failed");
}

fn run_store_index_get() -> Int {
  var idx = index_new(3);
  var v = vector_new(3);
  vector_set(&mut v, 0, 7.0);
  vector_set(&mut v, 1, 8.0);
  vector_set(&mut v, 2, 9.0);
  index_add(&mut idx, 42, v);
  var got = index_get(&idx, 42);
  match got {
    Some(vec) => {
      if f32_eq(vector_get(&vec, 0), 7.0) { return 0; }
    }
    None => { return 1; }
  }
  return 1;
}
fn test_store_index_get() -> TestResult {
  if run_store_index_get() == 0 { return assert(true, "VectorIndex: get returns stored vector"); }
  return assert(false, "VectorIndex: get failed");
}

fn run_store_index_get_miss() -> Int {
  var idx = index_new(2);
  var got = index_get(&idx, 999);
  match got {
    Some(_) => { return 1; }
    None => { return 0; }
  }
}
fn test_store_index_get_miss() -> TestResult {
  if run_store_index_get_miss() == 0 { return assert(true, "VectorIndex: get missing id returns None"); }
  return assert(false, "VectorIndex: get miss failed");
}

fn run_store_index_remove() -> Int {
  var idx = index_new(2);
  var v = vector_new(2);
  vector_set(&mut v, 0, 5.0);
  index_add(&mut idx, 1, v);
  var ok = index_remove(&mut idx, 1);
  if ok && index_size(&idx) == 0 { return 0; }
  return 1;
}
fn test_store_index_remove() -> TestResult {
  if run_store_index_remove() == 0 { return assert(true, "VectorIndex: remove returns true, size=0"); }
  return assert(false, "VectorIndex: remove failed");
}

fn run_store_index_remove_miss() -> Int {
  var idx = index_new(2);
  var ok = index_remove(&mut idx, 999);
  if !ok { return 0; }
  return 1;
}
fn test_store_index_remove_miss() -> TestResult {
  if run_store_index_remove_miss() == 0 { return assert(true, "VectorIndex: remove missing id returns false"); }
  return assert(false, "VectorIndex: remove miss failed");
}

fn run_store_index_add_multiple() -> Int {
  var idx = index_new(1);
  var i: Int = 0;
  while i < 5 {
    var v = vector_new(1);
    vector_set(&mut v, 0, i as Float32 + 1.0);
    index_add(&mut idx, i, v);
    i = i + 1;
  }
  if index_size(&idx) == 5 { return 0; }
  return 1;
}
fn test_store_index_add_multiple() -> TestResult {
  if run_store_index_add_multiple() == 0 { return assert(true, "VectorIndex: add 5 vectors, size=5"); }
  return assert(false, "VectorIndex: add multiple failed");
}

// ============================================================================
// SECTION 4: HNSW index -- construction stubs
//   (HNSW has pre-existing T001 errors per AUDIT.md; test parameter types)
// ============================================================================

fn run_hnsw_params_valid() -> Int {
  var p = ann_params_default();
  if ann_params_valid(&p) { return 0; }
  return 1;
}
fn test_hnsw_params_valid() -> TestResult {
  if run_hnsw_params_valid() == 0 { return assert(true, "HNSW: default AnnParams pass validation"); }
  return assert(false, "HNSW: AnnParams validation failed");
}

fn run_hnsw_params_invalid_m() -> Int {
  var p = AnnParams{ m: 0, ef_construction: 200, ef_search: 64 };
  if !ann_params_valid(&p) { return 0; }
  return 1;
}
fn test_hnsw_params_invalid_m() -> TestResult {
  if run_hnsw_params_invalid_m() == 0 { return assert(true, "HNSW: m=0 fails validation"); }
  return assert(false, "HNSW: m=0 should be invalid");
}

fn run_hnsw_params_m_too_high() -> Int {
  var p = AnnParams{ m: 1000, ef_construction: 200, ef_search: 64 };
  if !ann_params_valid(&p) { return 0; }
  return 1;
}
fn test_hnsw_params_m_too_high() -> TestResult {
  if run_hnsw_params_m_too_high() == 0 { return assert(true, "HNSW: m=1000 > 512 fails validation"); }
  return assert(false, "HNSW: m=1000 should be invalid");
}

fn run_hnsw_params_invalid_efc() -> Int {
  var p = AnnParams{ m: 16, ef_construction: -1, ef_search: 64 };
  if !ann_params_valid(&p) { return 0; }
  return 1;
}
fn test_hnsw_params_invalid_efc() -> TestResult {
  if run_hnsw_params_invalid_efc() == 0 { return assert(true, "HNSW: ef_construction=-1 fails validation"); }
  return assert(false, "HNSW: ef_construction=-1 should be invalid");
}

fn run_hnsw_params_invalid_efs() -> Int {
  var p = AnnParams{ m: 16, ef_construction: 200, ef_search: 0 };
  if !ann_params_valid(&p) { return 0; }
  return 1;
}
fn test_hnsw_params_invalid_efs() -> TestResult {
  if run_hnsw_params_invalid_efs() == 0 { return assert(true, "HNSW: ef_search=0 fails validation"); }
  return assert(false, "HNSW: ef_search=0 should be invalid");
}

fn run_hnsw_params_default_values() -> Int {
  var p = ann_params_default();
  if p.m == 16 && p.ef_construction == 200 && p.ef_search == 64 { return 0; }
  return 1;
}
fn test_hnsw_params_default_values() -> TestResult {
  if run_hnsw_params_default_values() == 0 { return assert(true, "HNSW: defaults m=16 efC=200 efS=64"); }
  return assert(false, "HNSW: defaults incorrect");
}

// ============================================================================
// SECTION 5: Flat index -- brute-force search correctness
// ============================================================================

fn run_flat_search_exact_top1() -> Int {
  var idx = index_new(2);
  var v1 = vector_new(2);
  vector_set(&mut v1, 0, 1.0);
  vector_set(&mut v1, 1, 0.0);
  var v2 = vector_new(2);
  vector_set(&mut v2, 0, 100.0);
  vector_set(&mut v2, 1, 100.0);
  index_add(&mut idx, 10, v1);
  index_add(&mut idx, 20, v2);
  var query = vector_new(2);
  vector_set(&mut query, 0, 1.0);
  vector_set(&mut query, 1, 0.0);
  var results = search_knn(&idx, &query, 1, DistanceMetric.Euclidean);
  if results.len() == 1 && results[0].id == 10 { return 0; }
  return 1;
}
fn test_range_search_basic() -> TestResult {
  var idx = index_new(3);
  index_add(&mut idx, 1, mk_vec3(1.0, 0.0, 0.0));
  index_add(&mut idx, 2, mk_vec3(0.9, 0.1, 0.0));
  index_add(&mut idx, 3, mk_vec3(0.0, 0.0, 1.0));
  var q = mk_vec3(1.0, 0.0, 0.0);
  // Cosine distances from q: id1 = 0, id2 ~ 0.006, id3 = 1.
  var all = search_range_scan(&idx, &q, 1.0, 10, DistanceMetric.Cosine);
  if all.len() != 3 { return assert(false, "range: radius 1.0 inclusive keeps all 3"); }
  if all[0].id != 1 { return assert(false, "range: closest first"); }
  if all[2].id != 3 { return assert(false, "range: farthest last"); }
  var near = search_range_scan(&idx, &q, 0.01, 10, DistanceMetric.Cosine);
  if near.len() != 2 { return assert(false, "range: radius 0.01 keeps id1+id2"); }
  var bounded = search_range_scan(&idx, &q, 1.0, 1, DistanceMetric.Cosine);
  if bounded.len() != 1 { return assert(false, "range: limit 1 bounds the result"); }
  if bounded[0].id != 1 { return assert(false, "range: limit keeps the closest"); }
  var exact = search_range_scan(&idx, &q, 0.0, 10, DistanceMetric.Cosine);
  if exact.len() != 1 { return assert(false, "range: radius 0 keeps only exact matches"); }
  if exact[0].id != 1 { return assert(false, "range: radius 0 exact id"); }
  return assert(true, "range scan: inclusive radius, sorted, bounded");
}

fn test_batch_ops_basic() -> TestResult {
  var eng = engine_new();
  let _cid = engine_create_collection(&mut eng, 3, DistanceMetric.Cosine);
  var ids = Vec[Int].new();
  ids.push(1); ids.push(2); ids.push(3);
  var vecs = Vec[Vector].new();
  vecs.push(mk_vec3(1.0, 0.0, 0.0));
  vecs.push(mk_vec3(0.0, 1.0, 0.0));
  vecs.push(mk_vec3(0.0, 0.0, 1.0));
  match engine_upsert_many(&mut eng, &ids, &vecs) {
    Ok(n) => { if n != 3 { return assert(false, "batch upsert: returns 3"); } }
    Err(_) => { return assert(false, "batch upsert: Ok expected"); }
  }
  if engine_size(&eng) != 3 { return assert(false, "batch upsert: size 3"); }
  // All-or-nothing: one bad dimension -> nothing applied.
  var badids = Vec[Int].new();
  badids.push(10); badids.push(11);
  var badvecs = Vec[Vector].new();
  badvecs.push(mk_vec3(1.0, 0.0, 0.0));
  badvecs.push(vector_new(2));
  match engine_upsert_many(&mut eng, &badids, &badvecs) {
    Ok(_) => { return assert(false, "batch upsert: bad dim rejected"); }
    Err(_) => {}
  }
  if engine_size(&eng) != 3 { return assert(false, "batch upsert: all-or-nothing"); }
  // Batch search: order preserved, k bounded.
  var qs = Vec[Vector].new();
  qs.push(mk_vec3(1.0, 0.0, 0.0));
  qs.push(mk_vec3(0.0, 1.0, 0.0));
  match engine_search_many(&eng, &qs, 1) {
    Ok(b) => {
      if b.sets.len() != 2 { return assert(false, "batch search: 2 sets"); }
      if b.sets[0].items.len() != 1 || b.sets[0].items[0].id != 1 { return assert(false, "batch search: set 0 -> id 1"); }
      if b.sets[1].items.len() != 1 || b.sets[1].items[0].id != 2 { return assert(false, "batch search: set 1 -> id 2"); }
    }
    Err(_) => { return assert(false, "batch search: Ok expected"); }
  }
  // Batch delete: missing ids skipped, count = actual removals.
  var del = Vec[Int].new();
  del.push(1); del.push(99); del.push(2);
  match engine_delete_many(&mut eng, &del) {
    Ok(n) => { if n != 2 { return assert(false, "batch delete: 2 removed"); } }
    Err(_) => { return assert(false, "batch delete: Ok expected"); }
  }
  if engine_size(&eng) != 1 { return assert(false, "batch delete: size 1"); }
  // Empty batches rejected.
  var eids = Vec[Int].new();
  var evecs = Vec[Vector].new();
  match engine_upsert_many(&mut eng, &eids, &evecs) {
    Ok(_) => { return assert(false, "batch upsert: empty rejected"); }
    Err(_) => {}
  }
  return assert(true, "batch ops: upsert/search/delete + all-or-nothing");
}

fn test_flat_search_exact_top1() -> TestResult {
  if run_flat_search_exact_top1() == 0 { return assert(true, "Flat: KNN top-1 returns nearest (id=10)"); }
  return assert(false, "Flat: KNN top-1 failed");
}

fn run_flat_search_results_bounded() -> Int {
  var idx = index_new(1);
  var i: Int = 0;
  while i < 3 {
    var v = vector_new(1);
    vector_set(&mut v, 0, i as Float32);
    index_add(&mut idx, i, v);
    i = i + 1;
  }
  var query = vector_new(1);
  vector_set(&mut query, 0, 0.0);
  var results = search_knn(&idx, &query, 2, DistanceMetric.Euclidean);
  if results.len() == 2 { return 0; }
  return 1;
}
fn test_flat_search_results_bounded() -> TestResult {
  if run_flat_search_results_bounded() == 0 { return assert(true, "Flat: KNN k=2 with 3 vectors returns len=2"); }
  return assert(false, "Flat: KNN result count bounded");
}

fn run_flat_search_ordered() -> Int {
  var idx = index_new(1);
  var v0 = vector_new(1); vector_set(&mut v0, 0, 0.0); index_add(&mut idx, 0, v0);
  var v1 = vector_new(1); vector_set(&mut v1, 0, 10.0); index_add(&mut idx, 1, v1);
  var v2 = vector_new(1); vector_set(&mut v2, 0, 5.0); index_add(&mut idx, 2, v2);
  var query = vector_new(1);
  vector_set(&mut query, 0, 0.0);
  var results = search_knn(&idx, &query, 3, DistanceMetric.Euclidean);
  if results.len() == 3 && results[0].id == 0 && results[2].id == 1 { return 0; }
  return 1;
}
fn test_flat_search_ordered() -> TestResult {
  if run_flat_search_ordered() == 0 { return assert(true, "Flat: KNN results ordered by distance asc"); }
  return assert(false, "Flat: KNN ordering failed");
}

fn run_flat_search_all_metrics() -> Int {
  var idx = index_new(2);
  var v1 = vector_new(2); vector_set(&mut v1, 0, 1.0); vector_set(&mut v1, 1, 0.0); index_add(&mut idx, 1, v1);
  var v2 = vector_new(2); vector_set(&mut v2, 0, 0.0); vector_set(&mut v2, 1, 2.0); index_add(&mut idx, 2, v2);
  var query = vector_new(2);
  vector_set(&mut query, 0, 1.0);
  vector_set(&mut query, 1, 0.0);
  var r1 = search_knn(&idx, &query, 2, DistanceMetric.Euclidean);
  var r2 = search_knn(&idx, &query, 2, DistanceMetric.Cosine);
  var r3 = search_knn(&idx, &query, 2, DistanceMetric.DotProduct);
  if r1.len() == 2 && r2.len() == 2 && r3.len() == 2 { return 0; }
  return 1;
}
fn test_flat_search_all_metrics() -> TestResult {
  if run_flat_search_all_metrics() == 0 { return assert(true, "Flat: KNN works with all 3 distance metrics"); }
  return assert(false, "Flat: KNN across metrics failed");
}

// ============================================================================
// SECTION 6: Segment management -- manifest, state transitions
// ============================================================================

fn run_segment_new() -> Int {
  var sid = segment_id(1);
  var seg = segment_new(sid, 3);
  if segment_size(&seg) == 0 && segment_is_writable(&seg) { return 0; }
  return 1;
}
fn test_segment_new() -> TestResult {
  if run_segment_new() == 0 { return assert(true, "Segment: new is empty and writable"); }
  return assert(false, "Segment: new failed");
}

fn run_segment_insert() -> Int {
  var seg = segment_new(segment_id(1), 2);
  var v = vector_new(2);
  vector_set(&mut v, 0, 1.0);
  var ok = segment_insert(&mut seg, 100, v);
  if ok && segment_size(&seg) == 1 { return 0; }
  return 1;
}
fn test_segment_insert() -> TestResult {
  if run_segment_insert() == 0 { return assert(true, "Segment: insert works"); }
  return assert(false, "Segment: insert failed");
}

fn run_segment_transition_mutable_sealing() -> Int {
  var seg = segment_new(segment_id(1), 2);
  var ok = segment_transition(&mut seg, SegmentStateKind.Sealing);
  if ok && !segment_is_writable(&seg) { return 0; }
  return 1;
}
fn test_segment_transition_mutable_sealing() -> TestResult {
  if run_segment_transition_mutable_sealing() == 0 { return assert(true, "Segment: Mutable->Sealing allowed, writable=false"); }
  return assert(false, "Segment: Mutable->Sealing failed");
}

fn run_segment_transition_full_lifecycle() -> Int {
  var seg = segment_new(segment_id(1), 2);
  var ok = true;
  ok = ok && segment_transition(&mut seg, SegmentStateKind.Sealing);
  ok = ok && segment_transition(&mut seg, SegmentStateKind.Sealed);
  ok = ok && segment_transition(&mut seg, SegmentStateKind.Indexing);
  ok = ok && segment_transition(&mut seg, SegmentStateKind.Immutable);
  ok = ok && segment_transition(&mut seg, SegmentStateKind.Compacting);
  ok = ok && segment_transition(&mut seg, SegmentStateKind.Immutable);
  ok = ok && segment_transition(&mut seg, SegmentStateKind.Dropped);
  if ok { return 0; }
  return 1;
}
fn test_segment_transition_full_lifecycle() -> TestResult {
  if run_segment_transition_full_lifecycle() == 0 { return assert(true, "Segment: full lifecycle M->Sealing->Sealed->Indexing->Immutable->Compacting->Immutable->Dropped"); }
  return assert(false, "Segment: full lifecycle failed");
}

fn run_segment_transition_illegal() -> Int {
  var seg = segment_new(segment_id(1), 2);
  var ok = segment_transition(&mut seg, SegmentStateKind.Dropped);
  if !ok { return 0; }
  return 1;
}
fn test_segment_transition_illegal() -> TestResult {
  if run_segment_transition_illegal() == 0 { return assert(true, "Segment: Mutable->Dropped illegal, returns false"); }
  return assert(false, "Segment: illegal transition should fail");
}

fn run_segment_transition_sealed_indexing_ok() -> Int {
  var seg = segment_new(segment_id(1), 2);
  segment_transition(&mut seg, SegmentStateKind.Sealing);
  segment_transition(&mut seg, SegmentStateKind.Sealed);
  var ok = segment_transition(&mut seg, SegmentStateKind.Indexing);
  if ok { return 0; }
  return 1;
}
fn test_segment_transition_sealed_indexing_ok() -> TestResult {
  if run_segment_transition_sealed_indexing_ok() == 0 { return assert(true, "Segment: Sealed->Indexing allowed"); }
  return assert(false, "Segment: Sealed->Indexing fail");
}

fn run_segment_transition_dropped_terminal() -> Int {
  var seg = segment_new(segment_id(1), 2);
  segment_transition(&mut seg, SegmentStateKind.Sealing);
  segment_transition(&mut seg, SegmentStateKind.Sealed);
  segment_transition(&mut seg, SegmentStateKind.Indexing);
  segment_transition(&mut seg, SegmentStateKind.Immutable);
  segment_transition(&mut seg, SegmentStateKind.Dropped);
  var ok = segment_transition(&mut seg, SegmentStateKind.Mutable);
  if !ok { return 0; }
  return 1;
}
fn test_segment_transition_dropped_terminal() -> TestResult {
  if run_segment_transition_dropped_terminal() == 0 { return assert(true, "Segment: Dropped is terminal, no further transitions"); }
  return assert(false, "Segment: Dropped should be terminal");
}

// ============================================================================
// Manifest tests
// ============================================================================

fn run_manifest_new() -> Int {
  var cid = collection_id(1);
  var m = manifest_new(cid);
  if manifest_segment_count(&m) == 0 && m.last_lsn == 0 { return 0; }
  return 1;
}
fn test_manifest_new() -> TestResult {
  if run_manifest_new() == 0 { return assert(true, "Manifest: new empty, LSN=0"); }
  return assert(false, "Manifest: new failed");
}

fn run_manifest_add_remove() -> Int {
  var cid = collection_id(1);
  var m = manifest_new(cid);
  var s1 = segment_id(10);
  var s2 = segment_id(20);
  manifest_add_segment(&mut m, s1);
  manifest_add_segment(&mut m, s2);
  if manifest_segment_count(&m) == 2 {
    var rm = manifest_remove_segment(&mut m, s1);
    if rm && manifest_segment_count(&m) == 1 { return 0; }
  }
  return 1;
}
fn test_manifest_add_remove() -> TestResult {
  if run_manifest_add_remove() == 0 { return assert(true, "Manifest: add 2, remove 1, count=1"); }
  return assert(false, "Manifest: add/remove failed");
}

fn run_manifest_remove_miss() -> Int {
  var cid = collection_id(1);
  var m = manifest_new(cid);
  manifest_add_segment(&mut m, segment_id(5));
  var ok = manifest_remove_segment(&mut m, segment_id(99));
  if !ok && manifest_segment_count(&m) == 1 { return 0; }
  return 1;
}
fn test_manifest_remove_miss() -> TestResult {
  if run_manifest_remove_miss() == 0 { return assert(true, "Manifest: remove non-existent returns false"); }
  return assert(false, "Manifest: remove miss failed");
}

fn run_manifest_lsn() -> Int {
  var cid = collection_id(1);
  var m = manifest_new(cid);
  manifest_set_lsn(&mut m, 42);
  if m.last_lsn == 42 { return 0; }
  return 1;
}
fn test_manifest_lsn() -> TestResult {
  if run_manifest_lsn() == 0 { return assert(true, "Manifest: set_lsn stores value"); }
  return assert(false, "Manifest: LSN failed");
}

// ============================================================================
// Segment state machine tests
// ============================================================================

fn run_state_is_writable() -> Int {
  if segment_state_is_writable(&SegmentStateKind.Mutable)
     && !segment_state_is_writable(&SegmentStateKind.Sealed)
     && !segment_state_is_writable(&SegmentStateKind.Dropped) { return 0; }
  return 1;
}
fn test_state_is_writable() -> TestResult {
  if run_state_is_writable() == 0 { return assert(true, "SegmentState: only Mutable is writable"); }
  return assert(false, "SegmentState: writable check failed");
}

fn run_state_is_terminal() -> Int {
  if !segment_state_is_terminal(&SegmentStateKind.Mutable)
     && !segment_state_is_terminal(&SegmentStateKind.Sealed)
     && segment_state_is_terminal(&SegmentStateKind.Dropped) { return 0; }
  return 1;
}
fn test_state_is_terminal() -> TestResult {
  if run_state_is_terminal() == 0 { return assert(true, "SegmentState: only Dropped is terminal"); }
  return assert(false, "SegmentState: terminal check failed");
}

fn run_state_code_all() -> Int {
  var codes = segment_state_code(&SegmentStateKind.Mutable);
  codes = codes + segment_state_code(&SegmentStateKind.Sealing);
  codes = codes + segment_state_code(&SegmentStateKind.Sealed);
  codes = codes + segment_state_code(&SegmentStateKind.Indexing);
  codes = codes + segment_state_code(&SegmentStateKind.Immutable);
  codes = codes + segment_state_code(&SegmentStateKind.Compacting);
  codes = codes + segment_state_code(&SegmentStateKind.Dropped);
  if codes == 21 { return 0; }
  return 1;
}
fn test_state_code_all() -> TestResult {
  if run_state_code_all() == 0 { return assert(true, "SegmentState: codes sum 0+1+2+3+4+5+6=21"); }
  return assert(false, "SegmentState: code sum failed");
}

// ============================================================================
// SECTION 7: Collection -- schema validation, CRUD
// ============================================================================

fn run_collection_schema_new() -> Int {
  var schema = schema_new(128, DistanceMetric.Cosine);
  if schema_dimension(&schema) == 128 && schema.metric == DistanceMetric.Cosine { return 0; }
  return 1;
}
fn test_collection_schema_new() -> TestResult {
  if run_collection_schema_new() == 0 { return assert(true, "CollectionSchema: new(128, Cosine) stores both"); }
  return assert(false, "CollectionSchema: new failed");
}

fn run_collection_schema_normalization() -> Int {
  var schema = schema_new(64, DistanceMetric.Euclidean);
  schema_set_normalization(&mut schema, NormalizationMode.L2Normalized);
  if schema.normalization == NormalizationMode.L2Normalized { return 0; }
  return 1;
}
fn test_collection_schema_normalization() -> TestResult {
  if run_collection_schema_normalization() == 0 { return assert(true, "CollectionSchema: set normalization to L2Normalized"); }
  return assert(false, "CollectionSchema: normalization failed");
}

fn run_collection_schema_add_field() -> Int {
  var schema = schema_new(64, DistanceMetric.Euclidean);
  schema_add_field(&mut schema, "color", true);
  schema_add_field(&mut schema, "price", false);
  if schema.payload_fields.len() == 2 { return 0; }
  return 1;
}
fn test_collection_schema_add_field() -> TestResult {
  if run_collection_schema_add_field() == 0 { return assert(true, "CollectionSchema: add 2 fields"); }
  return assert(false, "CollectionSchema: add_field failed");
}

fn run_collection_schema_dimension() -> Int {
  var schema = schema_new(768, DistanceMetric.Cosine);
  if schema_dimension(&schema) == 768 { return 0; }
  return 1;
}
fn test_collection_schema_dimension() -> TestResult {
  if run_collection_schema_dimension() == 0 { return assert(true, "CollectionSchema: dimension read 768"); }
  return assert(false, "CollectionSchema: dimension read failed");
}

fn run_collection_new() -> Int {
  var cid = collection_id(1);
  var schema = schema_new(256, DistanceMetric.Euclidean);
  var col = collection_new(cid, schema, AnnIndexKind.Flat);
  if collection_segment_count(&col) == 0 && collection_dimension(&col) == 256 { return 0; }
  return 1;
}
fn test_collection_new() -> TestResult {
  if run_collection_new() == 0 { return assert(true, "Collection: new empty, dim=256"); }
  return assert(false, "Collection: new failed");
}

fn run_collection_register_segment() -> Int {
  var cid = collection_id(1);
  var schema = schema_new(128, DistanceMetric.Cosine);
  var col = collection_new(cid, schema, AnnIndexKind.Hnsw);
  collection_register_segment(&mut col, segment_id(1));
  collection_register_segment(&mut col, segment_id(2));
  collection_register_segment(&mut col, segment_id(3));
  if collection_segment_count(&col) == 3 { return 0; }
  return 1;
}
fn test_collection_register_segment() -> TestResult {
  if run_collection_register_segment() == 0 { return assert(true, "Collection: register 3 segments"); }
  return assert(false, "Collection: register_segment failed");
}

fn run_validate_dimension_ok() -> Int {
  var schema = schema_new(64, DistanceMetric.Euclidean);
  if validate_dimension(&schema, 64) { return 0; }
  return 1;
}
fn test_validate_dimension_ok() -> TestResult {
  if run_validate_dimension_ok() == 0 { return assert(true, "Validator: dimension 64 matches schema dim=64"); }
  return assert(false, "Validator: dimension match failed");
}

fn run_validate_dimension_mismatch() -> Int {
  var schema = schema_new(64, DistanceMetric.Euclidean);
  if !validate_dimension(&schema, 128) { return 0; }
  return 1;
}
fn test_validate_dimension_mismatch() -> TestResult {
  if run_validate_dimension_mismatch() == 0 { return assert(true, "Validator: dimension 128 rejects schema dim=64"); }
  return assert(false, "Validator: dimension mismatch should fail");
}

fn run_validate_metric_all() -> Int {
  var schema = schema_new(16, DistanceMetric.Euclidean);
  if validate_metric(&schema, DistanceMetric.Cosine)
     && validate_metric(&schema, DistanceMetric.DotProduct)
     && validate_metric(&schema, DistanceMetric.Euclidean) { return 0; }
  return 1;
}
fn test_validate_metric_all() -> TestResult {
  if run_validate_metric_all() == 0 { return assert(true, "Validator: all 3 metrics accepted"); }
  return assert(false, "Validator: metric check failed");
}

// ============================================================================
// SECTION 8: Payload -- filter AST, evaluation
// ============================================================================

fn run_payload_new() -> Int {
  var p = payload_new();
  if payload_len(&p) == 0 { return 0; }
  return 1;
}
fn test_payload_new() -> TestResult {
  if run_payload_new() == 0 { return assert(true, "Payload: new empty, len=0"); }
  return assert(false, "Payload: new failed");
}

fn run_payload_set_has() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  payload_set(&mut p, "price", FieldValue.IntVal(100));
  if payload_has(&p, "color") && payload_has(&p, "price") && !payload_has(&p, "missing") { return 0; }
  return 1;
}
fn test_payload_set_has() -> TestResult {
  if run_payload_set_has() == 0 { return assert(true, "Payload: set/has works for existing/missing keys"); }
  return assert(false, "Payload: set/has failed");
}

fn run_payload_len() -> Int {
  var p = payload_new();
  payload_set(&mut p, "a", FieldValue.IntVal(1));
  payload_set(&mut p, "b", FieldValue.FloatVal(2.0));
  payload_set(&mut p, "c", FieldValue.BoolVal(true));
  if payload_len(&p) == 3 { return 0; }
  return 1;
}
fn test_payload_len() -> TestResult {
  if run_payload_len() == 0 { return assert(true, "Payload: len=3 after 3 sets"); }
  return assert(false, "Payload: len failed");
}

fn run_field_value_kind() -> Int {
  if field_value_kind(&FieldValue.IntVal(1)) == "int"
     && field_value_kind(&FieldValue.FloatVal(1.0)) == "float"
     && field_value_kind(&FieldValue.TextVal("hi")) == "text"
     && field_value_kind(&FieldValue.BoolVal(true)) == "bool" { return 0; }
  return 1;
}
fn test_field_value_kind() -> TestResult {
  if run_field_value_kind() == 0 { return assert(true, "FieldValue: kind returns correct type names"); }
  return assert(false, "FieldValue: kind failed");
}

fn run_filter_exists_true() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var expr = filter_exists("color");
  if filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_exists_true() -> TestResult {
  if run_filter_exists_true() == 0 { return assert(true, "Filter: Exists('color') true when color present"); }
  return assert(false, "Filter: Exists true failed");
}

fn run_filter_exists_false() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var expr = filter_exists("price");
  if !filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_exists_false() -> TestResult {
  if run_filter_exists_false() == 0 { return assert(true, "Filter: Exists('price') false when absent"); }
  return assert(false, "Filter: Exists false failed");
}

fn run_filter_eq() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var expr = filter_eq("color", FieldValue.TextVal("red"));
  if filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_eq() -> TestResult {
  if run_filter_eq() == 0 { return assert(true, "Filter: Eq('color','red') on present field"); }
  return assert(false, "Filter: Eq failed");
}

fn run_filter_and_both_true() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  payload_set(&mut p, "size", FieldValue.TextVal("large"));
  var clauses = Vec[FilterExpr].new();
  clauses.push(filter_exists("color"));
  clauses.push(filter_exists("size"));
  var expr = filter_and(clauses);
  if filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_and_both_true() -> TestResult {
  if run_filter_and_both_true() == 0 { return assert(true, "Filter: And(color, size) both present = true"); }
  return assert(false, "Filter: And both true failed");
}

fn run_filter_and_one_false() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var clauses = Vec[FilterExpr].new();
  clauses.push(filter_exists("color"));
  clauses.push(filter_exists("price"));
  var expr = filter_and(clauses);
  if !filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_and_one_false() -> TestResult {
  if run_filter_and_one_false() == 0 { return assert(true, "Filter: And(color, price) one absent = false"); }
  return assert(false, "Filter: And one false failed");
}

fn run_filter_or_one_true() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var clauses = Vec[FilterExpr].new();
  clauses.push(filter_exists("color"));
  clauses.push(filter_exists("price"));
  var expr = filter_or(clauses);
  if filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_or_one_true() -> TestResult {
  if run_filter_or_one_true() == 0 { return assert(true, "Filter: Or(color, price) one present = true"); }
  return assert(false, "Filter: Or one true failed");
}

fn run_filter_or_both_false() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var clauses = Vec[FilterExpr].new();
  clauses.push(filter_exists("price"));
  clauses.push(filter_exists("size"));
  var expr = filter_or(clauses);
  if !filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_or_both_false() -> TestResult {
  if run_filter_or_both_false() == 0 { return assert(true, "Filter: Or(price, size) both absent = false"); }
  return assert(false, "Filter: Or both false failed");
}

fn run_filter_not_true() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var expr = filter_not(filter_exists("price"));
  if filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_not_true() -> TestResult {
  if run_filter_not_true() == 0 { return assert(true, "Filter: Not(Exists(price)) true when price absent"); }
  return assert(false, "Filter: Not true failed");
}

fn run_filter_not_false() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var expr = filter_not(filter_exists("color"));
  if !filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_not_false() -> TestResult {
  if run_filter_not_false() == 0 { return assert(true, "Filter: Not(Exists(color)) false when color present"); }
  return assert(false, "Filter: Not false failed");
}

fn run_filter_empty_not() -> Int {
  var p = payload_new();
  var clauses = Vec[FilterExpr].new();
  var expr = FilterExpr.Not(clauses);
  if filter_matches(&expr, &p) { return 0; }
  return 1;
}
fn test_filter_empty_not() -> TestResult {
  if run_filter_empty_not() == 0 { return assert(true, "Filter: Not([]) = true (vacuous)"); }
  return assert(false, "Filter: empty Not failed");
}

// ============================================================================
// SECTION 9: Search -- top-K heap, search orchestration
// ============================================================================

fn run_topk_new() -> Int {
  var h = topk_new(10);
  if topk_len(&h) == 0 { return 0; }
  return 1;
}
fn test_topk_new() -> TestResult {
  if run_topk_new() == 0 { return assert(true, "TopKHeap: new empty"); }
  return assert(false, "TopKHeap: new failed");
}

fn run_topk_push_bounded() -> Int {
  var h = topk_new(3);
  topk_push(&mut h, Neighbor{ id: 1, distance: 5.0 });
  topk_push(&mut h, Neighbor{ id: 2, distance: 3.0 });
  topk_push(&mut h, Neighbor{ id: 3, distance: 7.0 });
  topk_push(&mut h, Neighbor{ id: 4, distance: 1.0 });
  if topk_len(&h) == 3 { return 0; }
  return 1;
}
fn test_topk_push_bounded() -> TestResult {
  if run_topk_push_bounded() == 0 { return assert(true, "TopKHeap: push 4 into capacity 3, len stays 3"); }
  return assert(false, "TopKHeap: bound failed");
}

fn run_topk_push_sorted() -> Int {
  var h = topk_new(3);
  topk_push(&mut h, Neighbor{ id: 3, distance: 5.0 });
  topk_push(&mut h, Neighbor{ id: 1, distance: 1.0 });
  topk_push(&mut h, Neighbor{ id: 2, distance: 3.0 });
  if h.items[0].id == 1 && h.items[1].id == 2 && h.items[2].id == 3 { return 0; }
  return 1;
}
fn test_topk_push_sorted() -> TestResult {
  if run_topk_push_sorted() == 0 { return assert(true, "TopKHeap: items sorted asc by distance"); }
  return assert(false, "TopKHeap: sort failed");
}

fn run_topk_is_full() -> Int {
  var h = topk_new(2);
  topk_push(&mut h, Neighbor{ id: 1, distance: 1.0 });
  if !topk_is_full(&h) { return 0; }
  topk_push(&mut h, Neighbor{ id: 2, distance: 2.0 });
  if topk_is_full(&h) { return 0; }
  return 1;
}
fn test_topk_is_full() -> TestResult {
  if run_topk_is_full() == 0 { return assert(true, "TopKHeap: is_full false at 1/2, true at 2/2"); }
  return assert(false, "TopKHeap: is_full failed");
}

fn run_topk_worst() -> Int {
  var h = topk_new(3);
  topk_push(&mut h, Neighbor{ id: 1, distance: 1.0 });
  topk_push(&mut h, Neighbor{ id: 2, distance: 5.0 });
  topk_push(&mut h, Neighbor{ id: 3, distance: 3.0 });
  var w = topk_worst(&h);
  match w {
    Some(n) => { if n.distance == 5.0 { return 0; } }
    None => { return 1; }
  }
  return 1;
}
fn test_topk_worst() -> TestResult {
  if run_topk_worst() == 0 { return assert(true, "TopKHeap: worst has max distance=5.0"); }
  return assert(false, "TopKHeap: worst failed");
}

fn run_topk_worst_empty() -> Int {
  var h = topk_new(3);
  var w = topk_worst(&h);
  match w {
    Some(_) => { return 1; }
    None => { return 0; }
  }
}
fn test_topk_worst_empty() -> TestResult {
  if run_topk_worst_empty() == 0 { return assert(true, "TopKHeap: worst on empty returns None"); }
  return assert(false, "TopKHeap: worst empty failed");
}

// ============================================================================
// Engine orchestration tests
// ============================================================================

fn run_engine_new() -> Int {
  var eng = engine_new();
  if engine_size(&eng) == 0 && eng.next_collection == 1 { return 0; }
  return 1;
}
fn test_engine_new() -> TestResult {
  if run_engine_new() == 0 { return assert(true, "Engine: new has size=0, next_collection=1"); }
  return assert(false, "Engine: new failed");
}

fn run_engine_create_collection() -> Int {
  var eng = engine_new();
  var cid = engine_create_collection(&mut eng, 4, DistanceMetric.Cosine);
  match cid {
    Some(id) => {
      if eng.created && eng.dimension == 4 { return 0; }
    }
    None => { return 1; }
  }
  return 1;
}
fn test_engine_create_collection() -> TestResult {
  if run_engine_create_collection() == 0 { return assert(true, "Engine: create_collection(4, Cosine) sets dim=4"); }
  return assert(false, "Engine: create_collection failed");
}

fn run_engine_create_collection_invalid() -> Int {
  // `engine_create_collection` is contracted (`requires: dim >= 1`), so an
  // out-of-range dim is rejected by the CONTRACT, not the body -- and on
  // v0.64.0 a runtime requires-violation aborts the process with exit 0
  // (XVC-C-02), which would silently kill the whole suite. Verify the
  // predicate rejects invalid dims and the boundary dim=1 is accepted.
  if is_valid_dimension(0) { return 1; }
  if is_valid_dimension(65537) { return 1; }
  var eng = engine_new();
  var cid = engine_create_collection(&mut eng, 1, DistanceMetric.Euclidean);
  match cid {
    Some(_) => { return 0; }
    None => { return 1; }
  }
}
fn test_engine_create_collection_invalid() -> TestResult {
  if run_engine_create_collection_invalid() == 0 { return assert(true, "Engine: invalid dim rejected by predicate; dim=1 accepted"); }
  return assert(false, "Engine: invalid dim boundary failed");
}

fn run_engine_upsert() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Euclidean);
  var v = vector_new(3);
  vector_set(&mut v, 0, 1.0);
  vector_set(&mut v, 1, 2.0);
  vector_set(&mut v, 2, 3.0);
  var ok = engine_upsert(&mut eng, 100, v);
  if ok && engine_size(&eng) == 1 { return 0; }
  return 1;
}
fn test_engine_upsert() -> TestResult {
  if run_engine_upsert() == 0 { return assert(true, "Engine: upsert point 100, size=1"); }
  return assert(false, "Engine: upsert failed");
}

fn run_engine_upsert_dim_mismatch() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Euclidean);
  var v = vector_new(2);
  vector_set(&mut v, 0, 1.0);
  vector_set(&mut v, 1, 2.0);
  var ok = engine_upsert(&mut eng, 200, v);
  if !ok { return 0; }
  return 1;
}
fn test_engine_upsert_dim_mismatch() -> TestResult {
  if run_engine_upsert_dim_mismatch() == 0 { return assert(true, "Engine: upsert dimension mismatch rejected"); }
  return assert(false, "Engine: dim mismatch should fail");
}

fn run_engine_search() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var v1 = vector_new(2); vector_set(&mut v1, 0, 1.0); engine_upsert(&mut eng, 10, v1);
  var v2 = vector_new(2); vector_set(&mut v2, 0, 100.0); engine_upsert(&mut eng, 20, v2);
  var query = vector_new(2);
  vector_set(&mut query, 0, 1.0);
  var r = engine_search(&eng, &query, 1);
  match r {
    Ok(h) => { if h.items.len() == 1 && h.items[0].id == 10 { return 0; } }
    Err(_) => {}
  }
  return 1;
}
fn test_engine_search() -> TestResult {
  if run_engine_search() == 0 { return assert(true, "Engine: search returns nearest (id=10)"); }
  return assert(false, "Engine: search failed");
}

fn run_search_hits_shape() -> Int {
  // Regression guard for XVC-C-04: the Ok payload of a Result[Vec[struct]]
  // used to arrive with zeroed element fields. The SearchHits wrapper must
  // carry BOTH ids and non-zero distances through the Result.
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var v1 = vector_new(2); vector_set(&mut v1, 0, 1.0);
  var v2 = vector_new(2); vector_set(&mut v2, 0, 100.0);
  engine_upsert(&mut eng, 10, v1);
  engine_upsert(&mut eng, 20, v2);
  var query = vector_new(2); vector_set(&mut query, 0, 1.0);
  var r = engine_search(&eng, &query, 2);
  match r {
    Ok(h) => {
      if h.items.len() != 2 { return 1; }
      if h.items[0].id != 10 { return 2; }
      if h.items[1].id != 20 { return 3; }
      if !f32_approx(h.items[0].distance, 0.0, 0.0001) { return 4; }
      if !f32_approx(h.items[1].distance, 99.0, 0.0001) { return 5; }
      return 0;
    }
    Err(_) => { return 6; }
  }
}
fn test_search_hits_shape() -> TestResult {
  if run_search_hits_shape() == 0 { return assert(true, "SearchHits: Ok payload carries ids + distances"); }
  return assert(false, "SearchHits: payload fields lost (XVC-C-04)");
}

fn run_engine_delete() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 1, DistanceMetric.Euclidean);
  var v = vector_new(1);
  vector_set(&mut v, 0, 1.0);
  engine_upsert(&mut eng, 50, v);
  var ok = engine_delete(&mut eng, 50);
  if ok && engine_size(&eng) == 0 { return 0; }
  return 1;
}
fn test_engine_delete() -> TestResult {
  if run_engine_delete() == 0 { return assert(true, "Engine: delete removes point, size=0"); }
  return assert(false, "Engine: delete failed");
}

fn run_engine_delete_miss() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 1, DistanceMetric.Euclidean);
  var ok = engine_delete(&mut eng, 999);
  if !ok { return 0; }
  return 1;
}
fn test_engine_delete_miss() -> TestResult {
  if run_engine_delete_miss() == 0 { return assert(true, "Engine: delete missing point returns false"); }
  return assert(false, "Engine: delete miss failed");
}

fn run_engine_full_lifecycle() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Cosine);
  var v1 = vector_new(3); vector_set(&mut v1, 0, 1.0); vector_set(&mut v1, 1, 0.0); vector_set(&mut v1, 2, 0.0);
  var v2 = vector_new(3); vector_set(&mut v2, 0, 0.0); vector_set(&mut v2, 1, 1.0); vector_set(&mut v2, 2, 0.0);
  var v3 = vector_new(3); vector_set(&mut v3, 0, 0.0); vector_set(&mut v3, 1, 0.0); vector_set(&mut v3, 2, 1.0);
  engine_upsert(&mut eng, 1, v1);
  engine_upsert(&mut eng, 2, v2);
  engine_upsert(&mut eng, 3, v3);
  var query = vector_new(3);
  vector_set(&mut query, 0, 1.0);
  vector_set(&mut query, 1, 0.0);
  vector_set(&mut query, 2, 0.0);
  var r = engine_search(&eng, &query, 3);
  match r {
    Ok(h) => { if h.items.len() == 3 && h.items[0].id == 1 { return 0; } }
    Err(_) => {}
  }
  return 1;
}
fn test_engine_full_lifecycle() -> TestResult {
  if run_engine_full_lifecycle() == 0 { return assert(true, "Engine: full create/upsert/search lifecycle"); }
  return assert(false, "Engine: lifecycle failed");
}

// ============================================================================
// SECTION 10: ANN index -- type dispatch (AnnIndexKind)
// ============================================================================

fn run_ann_kind_names() -> Int {
  if ann_index_kind_name(&AnnIndexKind.Flat) == "flat"
     && ann_index_kind_name(&AnnIndexKind.Hnsw) == "hnsw"
     && ann_index_kind_name(&AnnIndexKind.Ivf) == "ivf" { return 0; }
  return 1;
}
fn test_ann_kind_names() -> TestResult {
  if run_ann_kind_names() == 0 { return assert(true, "AnnIndexKind: names flat/hnsw/ivf"); }
  return assert(false, "AnnIndexKind: name check failed");
}

fn run_ann_kind_enum_variants() -> Int {
  var k1 = AnnIndexKind.Flat;
  var k2 = AnnIndexKind.Hnsw;
  var k3 = AnnIndexKind.Ivf;
  var ok: Bool = true;
  match k1 { Flat => { } Hnsw => { ok = false; } Ivf => { ok = false; } }
  match k2 { Flat => { ok = false; } Hnsw => { } Ivf => { ok = false; } }
  match k3 { Flat => { ok = false; } Hnsw => { ok = false; } Ivf => { } }
  if ok { return 0; }
  return 1;
}
fn test_ann_kind_enum_variants() -> TestResult {
  if run_ann_kind_enum_variants() == 0 { return assert(true, "AnnIndexKind: 3 variants discriminate correctly"); }
  return assert(false, "AnnIndexKind: variant discrimination failed");
}

fn run_ann_params_collection_attached() -> Int {
  var cid = collection_id(1);
  var schema = schema_new(128, DistanceMetric.DotProduct);
  var col = collection_new(cid, schema, AnnIndexKind.Hnsw);
  if col.index_kind == AnnIndexKind.Hnsw
     && col.index_params.m == 16
     && col.index_params.ef_construction == 200
     && col.index_params.ef_search == 64 { return 0; }
  return 1;
}
fn test_ann_params_collection_attached() -> TestResult {
  if run_ann_params_collection_attached() == 0 { return assert(true, "ANN: Collection stores AnnIndexKind + default AnnParams"); }
  return assert(false, "ANN: collection index params failed");
}

// ============================================================================
// SECTION 11: Error types and error handling
// ============================================================================

fn run_error_dimension_mismatch() -> Int {
  var e = VectorError.DimensionMismatch(128, 64);
  if vector_error_code(&e) == 1001 { return 0; }
  return 1;
}
fn test_error_dimension_mismatch() -> TestResult {
  if run_error_dimension_mismatch() == 0 { return assert(true, "VectorError: DimensionMismatch code=1001"); }
  return assert(false, "VectorError: DimensionMismatch code failed");
}

fn run_error_unsupported_metric() -> Int {
  var e = VectorError.UnsupportedMetric("manhattan");
  if vector_error_code(&e) == 1002 { return 0; }
  return 1;
}
fn test_error_unsupported_metric() -> TestResult {
  if run_error_unsupported_metric() == 0 { return assert(true, "VectorError: UnsupportedMetric code=1002"); }
  return assert(false, "VectorError: UnsupportedMetric code failed");
}

fn run_error_collection_not_found() -> Int {
  var e = VectorError.CollectionNotFound(42);
  if vector_error_code(&e) == 1003 { return 0; }
  return 1;
}
fn test_error_collection_not_found() -> TestResult {
  if run_error_collection_not_found() == 0 { return assert(true, "VectorError: CollectionNotFound code=1003"); }
  return assert(false, "VectorError: CollectionNotFound code failed");
}

fn run_error_invalid_vector() -> Int {
  var e = VectorError.InvalidVector("zero-length vector");
  if vector_error_code(&e) == 1004 { return 0; }
  return 1;
}
fn test_error_invalid_vector() -> TestResult {
  if run_error_invalid_vector() == 0 { return assert(true, "VectorError: InvalidVector code=1004"); }
  return assert(false, "VectorError: InvalidVector code failed");
}

fn run_error_segment_sealed() -> Int {
  var e = VectorError.SegmentSealed(7);
  if vector_error_code(&e) == 1005 { return 0; }
  return 1;
}
fn test_error_segment_sealed() -> TestResult {
  if run_error_segment_sealed() == 0 { return assert(true, "VectorError: SegmentSealed code=1005"); }
  return assert(false, "VectorError: SegmentSealed code failed");
}

fn run_error_topk_exceeded() -> Int {
  var e = VectorError.TopKExceeded(20000, 10000);
  if vector_error_code(&e) == 1006 { return 0; }
  return 1;
}
fn test_error_topk_exceeded() -> TestResult {
  if run_error_topk_exceeded() == 0 { return assert(true, "VectorError: TopKExceeded code=1006"); }
  return assert(false, "VectorError: TopKExceeded code failed");
}

fn run_error_to_str_all() -> Int {
  var e1 = VectorError.DimensionMismatch(0, 0);
  var e2 = VectorError.UnsupportedMetric("");
  var e3 = VectorError.CollectionNotFound(0);
  var e4 = VectorError.InvalidVector("");
  var e5 = VectorError.SegmentSealed(0);
  var e6 = VectorError.TopKExceeded(0, 0);
  var s1 = vector_error_to_str(&e1);
  var s2 = vector_error_to_str(&e2);
  var s3 = vector_error_to_str(&e3);
  var s4 = vector_error_to_str(&e4);
  var s5 = vector_error_to_str(&e5);
  var s6 = vector_error_to_str(&e6);
  if s1.len() > 0 && s2.len() > 0 && s3.len() > 0 && s4.len() > 0 && s5.len() > 0 && s6.len() > 0 { return 0; }
  return 1;
}
fn test_error_to_str_all() -> TestResult {
  if run_error_to_str_all() == 0 { return assert(true, "VectorError: all 6 variants have to_str"); }
  return assert(false, "VectorError: to_str failed");
}

fn run_error_codes_unique() -> Int {
  var codes = Vec[Int].new();
  codes.push(vector_error_code(&VectorError.DimensionMismatch(0, 0)));
  codes.push(vector_error_code(&VectorError.UnsupportedMetric("")));
  codes.push(vector_error_code(&VectorError.CollectionNotFound(0)));
  codes.push(vector_error_code(&VectorError.InvalidVector("")));
  codes.push(vector_error_code(&VectorError.SegmentSealed(0)));
  codes.push(vector_error_code(&VectorError.TopKExceeded(0, 0)));
  var i: Int = 0;
  while i < codes.len() {
    var j = i + 1;
    while j < codes.len() {
      if codes[i] == codes[j] { return 1; }
      j = j + 1;
    }
    i = i + 1;
  }
  return 0;
}
fn test_error_codes_unique() -> TestResult {
  if run_error_codes_unique() == 0 { return assert(true, "VectorError: all 6 codes are unique"); }
  return assert(false, "VectorError: codes not unique");
}

// ============================================================================
// SECTION 12: Durability/engine stubs -- WAL, Counter, IdMap
// ============================================================================

fn run_wal_new() -> Int {
  var w = wal_writer_new();
  if w.next_lsn == 1 && w.synced_lsn == 0 { return 0; }
  return 1;
}
fn test_wal_new() -> TestResult {
  if run_wal_new() == 0 { return assert(true, "WAL: new next_lsn=1, synced=0"); }
  return assert(false, "WAL: new failed");
}

fn run_wal_append() -> Int {
  var w = wal_writer_new();
  var lsn = wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  if lsn == 1 && w.next_lsn == 2 { return 0; }
  return 1;
}
fn test_wal_append() -> TestResult {
  if run_wal_append() == 0 { return assert(true, "WAL: append returns LSN=1, next=2"); }
  return assert(false, "WAL: append failed");
}

fn run_wal_append_multiple() -> Int {
  var w = wal_writer_new();
  var l1 = wal_writer_append(&mut w, WalOpKind.Insert, 1, 10);
  var l2 = wal_writer_append(&mut w, WalOpKind.Update, 2, 20);
  var l3 = wal_writer_append(&mut w, WalOpKind.Delete, 3, 0);
  if l1 == 1 && l2 == 2 && l3 == 3 && w.records.len() == 3 { return 0; }
  return 1;
}
fn test_wal_append_multiple() -> TestResult {
  if run_wal_append_multiple() == 0 { return assert(true, "WAL: 3 appends LSN=1,2,3 records=3"); }
  return assert(false, "WAL: append multiple failed");
}

fn run_wal_current_lsn() -> Int {
  var w = wal_writer_new();
  wal_writer_append(&mut w, WalOpKind.Insert, 1, 10);
  wal_writer_append(&mut w, WalOpKind.Insert, 2, 20);
  if wal_writer_current_lsn(&w) == 2 { return 0; }
  return 1;
}
fn test_wal_current_lsn() -> TestResult {
  if run_wal_current_lsn() == 0 { return assert(true, "WAL: current_lsn=2 after 2 appends"); }
  return assert(false, "WAL: current_lsn failed");
}

fn run_wal_flush() -> Int {
  var w = wal_writer_new();
  wal_writer_append(&mut w, WalOpKind.Insert, 1, 10);
  wal_writer_append(&mut w, WalOpKind.Insert, 2, 20);
  var ok = wal_writer_flush(&mut w);
  if ok && w.synced_lsn == 2 { return 0; }
  return 1;
}
fn test_wal_flush() -> TestResult {
  if run_wal_flush() == 0 { return assert(true, "WAL: flush syncs to current LSN=2"); }
  return assert(false, "WAL: flush failed");
}

fn run_wal_before_ack_contract() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var before = engine_durable_lsn(&eng);
  var v = vector_new(2);
  vector_set(&mut v, 0, 1.0);
  engine_upsert(&mut eng, 10, v);
  var after = engine_durable_lsn(&eng);
  if after > before { return 0; }
  return 1;
}
fn test_wal_before_ack_contract() -> TestResult {
  if run_wal_before_ack_contract() == 0 { return assert(true, "WAL: upsert advances durable LSN"); }
  return assert(false, "WAL: before-ack contract failed");
}

fn run_counter_new() -> Int {
  var c = counter_new("test");
  if c.name == "test" && c.value == 0 { return 0; }
  return 1;
}
fn test_counter_new() -> TestResult {
  if run_counter_new() == 0 { return assert(true, "Counter: new name=test value=0"); }
  return assert(false, "Counter: new failed");
}

fn run_counter_inc() -> Int {
  var c = counter_new("x");
  counter_inc(&mut c);
  counter_inc(&mut c);
  counter_inc(&mut c);
  if c.value == 3 { return 0; }
  return 1;
}
fn test_counter_inc() -> TestResult {
  if run_counter_inc() == 0 { return assert(true, "Counter: incx3 -> value=3"); }
  return assert(false, "Counter: inc failed");
}

fn run_engine_counters() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 1, DistanceMetric.Euclidean);
  var v = vector_new(1);
  vector_set(&mut v, 0, 1.0);
  engine_upsert(&mut eng, 1, v);
  engine_upsert(&mut eng, 2, v);
  engine_delete(&mut eng, 2);
  if eng.upserts.value == 2 && eng.deletes.value == 1 { return 0; }
  return 1;
}
fn test_engine_counters() -> TestResult {
  if run_engine_counters() == 0 { return assert(true, "Engine: upserts=2, deletes=1 after 2 upserts + 1 delete"); }
  return assert(false, "Engine: counters failed");
}

fn run_id_map_new() -> Int {
  var m = id_map_new();
  if id_map_len(&m) == 0 { return 0; }
  return 1;
}
fn test_id_map_new() -> TestResult {
  if run_id_map_new() == 0 { return assert(true, "IdMap: new empty"); }
  return assert(false, "IdMap: new failed");
}

fn run_id_map_put_lookup() -> Int {
  var m = id_map_new();
  id_map_put(&mut m, 100, 1, 0);
  id_map_put(&mut m, 200, 1, 1);
  var e1 = id_map_lookup(&m, 100);
  var e2 = id_map_lookup(&m, 200);
  match e1 {
    Some(entry) => {
      if entry.segment == 1 && entry.offset == 0 {
        match e2 {
          Some(entry2) => {
            if entry2.segment == 1 && entry2.offset == 1 { return 0; }
          }
          None => { return 1; }
        }
      }
    }
    None => { return 1; }
  }
  return 1;
}
fn test_id_map_put_lookup() -> TestResult {
  if run_id_map_put_lookup() == 0 { return assert(true, "IdMap: put 2 entries, look up both"); }
  return assert(false, "IdMap: put/lookup failed");
}

fn run_id_map_put_update() -> Int {
  var m = id_map_new();
  id_map_put(&mut m, 100, 1, 0);
  id_map_put(&mut m, 100, 2, 5);
  var e = id_map_lookup(&m, 100);
  match e {
    Some(entry) => {
      if entry.segment == 2 && entry.offset == 5 && id_map_len(&m) == 1 { return 0; }
    }
    None => { return 1; }
  }
  return 1;
}
fn test_id_map_put_update() -> TestResult {
  if run_id_map_put_update() == 0 { return assert(true, "IdMap: re-put updates entry, len stays 1"); }
  return assert(false, "IdMap: put update failed");
}

fn run_id_map_remove() -> Int {
  var m = id_map_new();
  id_map_put(&mut m, 100, 1, 0);
  id_map_put(&mut m, 200, 1, 1);
  var ok = id_map_remove(&mut m, 100);
  if ok && id_map_len(&m) == 1 { return 0; }
  return 1;
}
fn test_id_map_remove() -> TestResult {
  if run_id_map_remove() == 0 { return assert(true, "IdMap: remove reduces len to 1"); }
  return assert(false, "IdMap: remove failed");
}

fn run_id_map_remove_miss() -> Int {
  var m = id_map_new();
  id_map_put(&mut m, 100, 1, 0);
  var ok = id_map_remove(&mut m, 999);
  if !ok && id_map_len(&m) == 1 { return 0; }
  return 1;
}
fn test_id_map_remove_miss() -> TestResult {
  if run_id_map_remove_miss() == 0 { return assert(true, "IdMap: remove missing returns false, len unchanged"); }
  return assert(false, "IdMap: remove miss failed");
}

fn run_id_map_lookup_miss() -> Int {
  var m = id_map_new();
  var e = id_map_lookup(&m, 999);
  match e {
    Some(_) => { return 1; }
    None => { return 0; }
  }
}
fn test_id_map_lookup_miss() -> TestResult {
  if run_id_map_lookup_miss() == 0 { return assert(true, "IdMap: lookup missing returns None"); }
  return assert(false, "IdMap: lookup miss failed");
}

// ============================================================================
// Additional boundary/validation tests
// ============================================================================

fn run_is_valid_dimension() -> Int {
  if is_valid_dimension(1) && is_valid_dimension(65536)
     && !is_valid_dimension(0) && !is_valid_dimension(65537) { return 0; }
  return 1;
}
fn test_is_valid_dimension() -> TestResult {
  if run_is_valid_dimension() == 0 { return assert(true, "is_valid_dimension: 1/65536=true, 0/65537=false"); }
  return assert(false, "is_valid_dimension failed");
}

fn run_is_valid_top_k() -> Int {
  if is_valid_top_k(1) && is_valid_top_k(10000)
     && !is_valid_top_k(0) && !is_valid_top_k(10001) { return 0; }
  return 1;
}
fn test_is_valid_top_k() -> TestResult {
  if run_is_valid_top_k() == 0 { return assert(true, "is_valid_top_k: 1/10000=true, 0/10001=false"); }
  return assert(false, "is_valid_top_k failed");
}

fn run_engine_search_empty() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var query = vector_new(2);
  vector_set(&mut query, 0, 1.0);
  var r = engine_search(&eng, &query, 5);
  match r {
    Ok(h) => { if h.items.len() == 0 { return 0; } }
    Err(_) => {}
  }
  return 1;
}
fn test_engine_search_empty() -> TestResult {
  if run_engine_search_empty() == 0 { return assert(true, "Engine: search empty store returns 0 results"); }
  return assert(false, "Engine: empty search failed");
}

fn run_engine_durable_lsn_tracks() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 1, DistanceMetric.Euclidean);
  var v = vector_new(1); vector_set(&mut v, 0, 1.0);
  engine_upsert(&mut eng, 1, v);
  engine_upsert(&mut eng, 2, v);
  var lsn = engine_durable_lsn(&eng);
  if lsn == 2 { return 0; }
  return 1;
}
fn test_engine_durable_lsn_tracks() -> TestResult {
  if run_engine_durable_lsn_tracks() == 0 { return assert(true, "Engine: durable_lsn increments with each upsert"); }
  return assert(false, "Engine: durable_lsn failed");
}

fn run_neighbor_struct() -> Int {
  var n = Neighbor{ id: 42, distance: 0.5 };
  if n.id == 42 && f32_eq(n.distance, 0.5) { return 0; }
  return 1;
}
fn test_neighbor_struct() -> TestResult {
  if run_neighbor_struct() == 0 { return assert(true, "Neighbor: struct field access"); }
  return assert(false, "Neighbor: struct failed");
}

fn run_search_result_struct() -> Int {
  var sr = SearchResult{ id: 99, distance: 1.5 };
  if sr.id == 99 && f32_eq(sr.distance, 1.5) { return 0; }
  return 1;
}
fn test_search_result_struct() -> TestResult {
  if run_search_result_struct() == 0 { return assert(true, "SearchResult: struct field access"); }
  return assert(false, "SearchResult: struct failed");
}

fn run_dimension_within_limit() -> Int {
  if dimension_within_limit(1) && dimension_within_limit(65536)
     && !dimension_within_limit(0) && !dimension_within_limit(65537) { return 0; }
  return 1;
}
fn test_dimension_within_limit() -> TestResult {
  if run_dimension_within_limit() == 0 { return assert(true, "Dimension: within_limit mirrors is_valid"); }
  return assert(false, "Dimension: within_limit failed");
}

// ============================================================================
// Float comparison edge case
// ============================================================================

fn run_f32_approx_epsilon() -> Int {
  if f32_approx(1.0, 1.00001, 0.001) && !f32_approx(1.0, 1.1, 0.001) { return 0; }
  return 1;
}
fn test_f32_approx_epsilon() -> TestResult {
  if run_f32_approx_epsilon() == 0 { return assert(true, "Float32: approx within epsilon"); }
  return assert(false, "Float32: approx failed");
}

// ============================================================================
// Search request building + request-driven search (from query/search_request.xi
// and engine/core.xi)
// ============================================================================

fn run_search_request_fields() -> Int {
  var query = vector_new(2);
  vector_set(&mut query, 0, 1.0);
  var req = SearchRequest{ query: query, top_k: 10, metric: DistanceMetric.Cosine, filter: Vec[FilterExpr].new(), with_payload: false };
  if req.top_k == 10 && req.metric == DistanceMetric.Cosine && !req.with_payload && req.filter.len() == 0 { return 0; }
  return 1;
}
fn test_search_request_fields() -> TestResult {
  if run_search_request_fields() == 0 { return assert(true, "SearchRequest: field init top_k=10 Cosine no payload/filter"); }
  return assert(false, "SearchRequest: field init failed");
}

fn search_request_new(query: Vector, top_k: Int, metric: DistanceMetric) -> SearchRequest {
  var filter = Vec[FilterExpr].new();
  return SearchRequest{ query: query, top_k: top_k, metric: metric, filter: filter, with_payload: false };
}

fn search_request_set_filter(req: &mut SearchRequest, expr: FilterExpr) {
  var filter = Vec[FilterExpr].new();
  filter.push(expr);
  req.filter = filter;
}

fn search_request_has_filter(req: &SearchRequest) -> Bool {
  return req.filter.len() > 0;
}

fn search_request_set_with_payload(req: &mut SearchRequest, on: Bool) {
  req.with_payload = on;
}

// Restored 2026-10-09 after compiler v0.64.2 fixed XVC-C-08: hydration flags
// and payload content are asserted in this large unit again (mirrors the
// real-module gate tests/probes/probe_search_request.xi).
fn run_request_hydration() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Cosine);
  engine_upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  engine_upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  engine_upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  payload_set(&mut p1, "stock", FieldValue.IntVal(7));
  engine_set_payload(&mut eng, 1, p1);
  var p2 = payload_new();
  payload_set(&mut p2, "color", FieldValue.TextVal("blue"));
  engine_set_payload(&mut eng, 2, p2);

  var req = search_request_new(mk_vec3(1.0, 0.0, 0.0), 10, DistanceMetric.Cosine);
  search_request_set_with_payload(&mut req, true);
  match engine_search_request(&eng, &req) {
    Ok(h) => {
      if h.items.len() != 3 { return 1; }
      if h.items[0].id != 1 { return 2; }
      if !h.items[0].has_payload { return 3; }
      var stock_ok: Bool = false;
      var hp = payload_new();
      if h.items[0].has_payload { hp = h.items[0].payload; }
      match payload_get(&hp, "stock") { Some(v) => { var w = FieldValue.IntVal(7); stock_ok = field_value_eq(&v, &w); } None => {} }
      if !stock_ok { return 4; }
      if h.items[1].id != 2 { return 5; }
      if !h.items[1].has_payload { return 6; }
      if h.items[2].id != 3 { return 7; }
      if h.items[2].has_payload { return 8; }
    }
    Err(_) => { return 9; }
  }

  var req2 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 10, DistanceMetric.Cosine);
  match engine_search_request(&eng, &req2) {
    Ok(h2) => {
      if h2.items.len() != 3 { return 10; }
      if h2.items[0].has_payload { return 11; }
      if h2.items[2].has_payload { return 12; }
    }
    Err(_) => { return 13; }
  }
  return 0;
}
fn test_request_hydration() -> TestResult {
  if run_request_hydration() == 0 { return assert(true, "SearchRequest: hydration flags + payload content"); }
  return assert(false, "SearchRequest: hydration mirror failed");
}

fn run_request_filtered() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Cosine);
  engine_upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  engine_upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  engine_upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  engine_set_payload(&mut eng, 1, p1);
  var p3 = payload_new();
  payload_set(&mut p3, "color", FieldValue.TextVal("red"));
  engine_set_payload(&mut eng, 3, p3);
  var req = search_request_new(mk_vec3(1.0, 0.0, 0.0), 5, DistanceMetric.Cosine);
  search_request_set_filter(&mut req, filter_eq("color", FieldValue.TextVal("red")));
  match engine_search_request(&eng, &req) {
    Ok(h) => {
      if h.items.len() != 2 { return 1; }
      if h.items[0].id != 1 { return 2; }
      if h.items[1].id != 3 { return 3; }
      // Hydration is OFF for this request: flags must be detached (C-08 gate).
      if h.items[0].has_payload { return 4; }
      if h.items[1].has_payload { return 4; }
      return 0;
    }
    Err(_) => { return 5; }
  }
}
fn test_request_filtered() -> TestResult {
  if run_request_filtered() == 0 { return assert(true, "SearchRequest: Eq filter -> {1,3}, flags detached"); }
  return assert(false, "SearchRequest: filtered request failed");
}

fn run_request_metric_mismatch() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Cosine);
  var req = search_request_new(vector_new(2), 5, DistanceMetric.Euclidean);
  match engine_search_request(&eng, &req) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}
fn test_request_metric_mismatch() -> TestResult {
  if run_request_metric_mismatch() == 0 { return assert(true, "SearchRequest: metric mismatch -> Err"); }
  return assert(false, "SearchRequest: metric mismatch accepted");
}

// ============================================================================
// SECTION 13: Durable codec + WAL recovery replay (Phase 2 slice)
// ============================================================================

fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = vector_new(3);
  vector_set(&mut v, 0, a);
  vector_set(&mut v, 1, b);
  vector_set(&mut v, 2, c);
  return v;
}

fn run_codec_roundtrip() -> Int {
  var v = mk_vec3(1.5, -2.25, 0.0);
  var payload = vector_encode(&v);
  if payload.len() != 4 { return 1; }
  if payload[0] != 3 { return 2; }
  match vector_decode(&payload) {
    Some(w) => {
      if w.dimension != 3 { return 3; }
      if !f32_eq(w.data[0], 1.5) { return 4; }
      if !f32_eq(w.data[1], -2.25) { return 5; }
      if !f32_eq(w.data[2], 0.0) { return 6; }
      return 0;
    }
    None => { return 7; }
  }
}
fn test_codec_roundtrip() -> TestResult {
  if run_codec_roundtrip() == 0 { return assert(true, "Codec: Float32 value roundtrip"); }
  return assert(false, "Codec: value roundtrip failed");
}

fn run_codec_bit_exactness() -> Int {
  var v = vector_new(2);
  vector_set(&mut v, 0, -0.0);
  vector_set(&mut v, 1, 1.1754944e-38);   // smallest positive normal Float32
  let b0 = float.float_bits(v.data[0] as Float64);
  let b1 = float.float_bits(v.data[1] as Float64);
  var payload = vector_encode(&v);
  match vector_decode(&payload) {
    Some(w) => {
      if float.float_bits(w.data[0] as Float64) != b0 { return 1; }
      if float.float_bits(w.data[1] as Float64) != b1 { return 2; }
      return 0;
    }
    None => { return 3; }
  }
}
fn test_codec_bit_exactness() -> TestResult {
  if run_codec_bit_exactness() == 0 { return assert(true, "Codec: negative zero + subnormal bit-exact"); }
  return assert(false, "Codec: bit exactness failed");
}

fn run_codec_malformed_rejected() -> Int {
  var empty = Vec[Int].new();
  match vector_decode(&empty) { Some(_) => { return 1; } None => {} }
  var dim0 = Vec[Int].new(); dim0.push(0);
  match vector_decode(&dim0) { Some(_) => { return 2; } None => {} }
  var short = Vec[Int].new(); short.push(3); short.push(1);
  match vector_decode(&short) { Some(_) => { return 3; } None => {} }
  var huge = Vec[Int].new(); huge.push(65537);
  match vector_decode(&huge) { Some(_) => { return 4; } None => {} }
  return 0;
}
fn test_codec_malformed_rejected() -> TestResult {
  if run_codec_malformed_rejected() == 0 { return assert(true, "Codec: malformed payloads -> None"); }
  return assert(false, "Codec: malformed payload accepted");
}

fn run_recover_replays_inserts() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Euclidean);
  var ok1 = engine_upsert(&mut eng, 10, mk_vec3(1.0, 0.0, 0.0));
  var ok2 = engine_upsert(&mut eng, 20, mk_vec3(0.0, 1.0, 0.0));
  if !ok1 || !ok2 { return 1; }
  var recovered = recover_store(&eng.wal, 3);
  if index_size(&recovered) != 2 { return 2; }
  match index_get(&recovered, 10) {
    Some(v) => { if !f32_eq(v.data[0], 1.0) { return 3; } }
    None => { return 4; }
  }
  match index_get(&recovered, 20) {
    Some(v) => { if !f32_eq(v.data[1], 1.0) { return 5; } }
    None => { return 6; }
  }
  match index_get(&recovered, 99) {
    Some(_) => { return 7; }
    None => {}
  }
  return 0;
}
fn test_recover_replays_inserts() -> TestResult {
  if run_recover_replays_inserts() == 0 { return assert(true, "Recovery: inserts replayed from WAL payloads"); }
  return assert(false, "Recovery: insert replay failed");
}

fn run_recover_replays_delete() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Euclidean);
  engine_upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  engine_upsert(&mut eng, 2, mk_vec3(0.0, 1.0, 0.0));
  var okdel = engine_delete(&mut eng, 1);
  if !okdel { return 1; }
  var recovered = recover_store(&eng.wal, 3);
  if index_size(&recovered) != 1 { return 2; }
  match index_get(&recovered, 1) { Some(_) => { return 3; } None => {} }
  match index_get(&recovered, 2) { Some(_) => {} None => { return 4; } }
  return 0;
}
fn test_recover_replays_delete() -> TestResult {
  if run_recover_replays_delete() == 0 { return assert(true, "Recovery: delete replayed, point stays gone"); }
  return assert(false, "Recovery: delete replay failed");
}

fn run_recover_search_identical() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Cosine);
  engine_upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  engine_upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  engine_upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  var query = mk_vec3(1.0, 0.0, 0.0);
  var r_before = engine_search(&eng, &query, 2);
  var recovered = engine_recover(&eng.wal, 3, DistanceMetric.Cosine);
  var r_after = engine_search(&recovered, &query, 2);
  var b = Vec[SearchResult].new();
  var a = Vec[SearchResult].new();
  match r_before { Ok(h) => { b = h.items; } Err(_) => {} }
  match r_after { Ok(h) => { a = h.items; } Err(_) => {} }
  if b.len() != a.len() { return 1; }
  if b.len() != 2 { return 2; }
  var i: Int = 0;
  while i < b.len() {
    if b[i].id != a[i].id { return 3; }
    if !f32_approx(b[i].distance, a[i].distance, 0.0001) { return 4; }
    i = i + 1;
  }
  return 0;
}
fn test_recover_search_identical() -> TestResult {
  if run_recover_search_identical() == 0 { return assert(true, "Recovery: post-reopen search identical"); }
  return assert(false, "Recovery: search diverged after reopen");
}

fn run_recover_lsn_continuity() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Euclidean);
  engine_upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  engine_upsert(&mut eng, 2, mk_vec3(0.0, 1.0, 0.0));
  let lsn_before = engine_durable_lsn(&eng);
  if lsn_before != 2 { return 1; }
  var recovered = engine_recover(&eng.wal, 3, DistanceMetric.Euclidean);
  let lsn_recovered = engine_durable_lsn(&recovered);
  if lsn_recovered < lsn_before { return 2; }   // LSNs stay monotonic
  engine_upsert(&mut recovered, 3, mk_vec3(0.0, 0.0, 1.0));
  if engine_durable_lsn(&recovered) != lsn_recovered + 1 { return 3; }
  return 0;
}
fn test_recover_lsn_continuity() -> TestResult {
  if run_recover_lsn_continuity() == 0 { return assert(true, "Recovery: LSN monotonic, +1 per write after reopen"); }
  return assert(false, "Recovery: LSN continuity broken");
}

fn run_recover_twice() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Euclidean);
  engine_upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  engine_upsert(&mut eng, 2, mk_vec3(0.0, 1.0, 0.0));
  var r1 = engine_recover(&eng.wal, 3, DistanceMetric.Euclidean);
  if engine_size(&r1) != 2 { return 1; }
  engine_delete(&mut r1, 1);
  var r2 = engine_recover(&r1.wal, 3, DistanceMetric.Euclidean);
  if engine_size(&r2) != 1 { return 2; }
  match index_get(&r2.store, 1) { Some(_) => { return 3; } None => {} }
  match index_get(&r2.store, 2) { Some(_) => {} None => { return 4; } }
  return 0;
}
fn test_recover_twice() -> TestResult {
  if run_recover_twice() == 0 { return assert(true, "Recovery: chained reopen (recovered engine is recoverable)"); }
  return assert(false, "Recovery: chained reopen failed");
}

fn run_recover_torn_tail_tolerated() -> Int {
  var w = wal_writer_new();
  var v1 = mk_vec3(1.0, 2.0, 3.0);
  wal_writer_append_payload(&mut w, WalOpKind.Insert, 7, 1, vector_encode(&v1));
  var torn = Vec[Int].new();
  torn.push(3);   // dim says 3, only one float follows -> malformed
  torn.push(1);
  wal_writer_append_payload(&mut w, WalOpKind.Insert, 8, 1, torn);
  var v2 = mk_vec3(4.0, 5.0, 6.0);
  wal_writer_append_payload(&mut w, WalOpKind.Insert, 9, 1, vector_encode(&v2));
  var recovered = recover_store(&w, 3);
  if index_size(&recovered) != 2 { return 1; }
  match index_get(&recovered, 7) { Some(_) => {} None => { return 2; } }
  match index_get(&recovered, 8) { Some(_) => { return 3; } None => {} }
  match index_get(&recovered, 9) { Some(_) => {} None => { return 4; } }
  return 0;
}
fn test_recover_torn_tail_tolerated() -> TestResult {
  if run_recover_torn_tail_tolerated() == 0 { return assert(true, "Recovery: torn payload skipped, later records replayed"); }
  return assert(false, "Recovery: torn tail handling failed");
}

// ============================================================================
// SECTION 14: Payload filtering (Phase 3)
// ============================================================================

fn run_payload_get() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  match payload_get(&p, "color") {
    Some(v) => {
      if field_value_kind(&v) == "text" { return 0; }
      return 1;
    }
    None => { return 2; }
  }
}
fn test_payload_get() -> TestResult {
  if run_payload_get() == 0 { return assert(true, "Payload: get returns the stored value"); }
  return assert(false, "Payload: get failed");
}

fn run_payload_set_overwrite() -> Int {
  var p = payload_new();
  payload_set(&mut p, "n", FieldValue.IntVal(1));
  payload_set(&mut p, "n", FieldValue.IntVal(2));
  if payload_len(&p) != 1 { return 1; }
  var want = FieldValue.IntVal(2);
  match payload_get(&p, "n") {
    Some(v) => {
      if field_value_eq(&v, &want) { return 0; }
      return 2;
    }
    None => { return 3; }
  }
}
fn test_payload_set_overwrite() -> TestResult {
  if run_payload_set_overwrite() == 0 { return assert(true, "Payload: set overwrites, len stays 1"); }
  return assert(false, "Payload: overwrite failed");
}

fn run_field_value_eq_matrix() -> Int {
  var i1 = FieldValue.IntVal(1);
  var i1b = FieldValue.IntVal(1);
  var f1 = FieldValue.FloatVal(1.0);
  var t_a = FieldValue.TextVal("a");
  var t_ab = FieldValue.TextVal("a");
  var t_b = FieldValue.TextVal("b");
  var b_t = FieldValue.BoolVal(true);
  var b_tb = FieldValue.BoolVal(true);
  var b_f = FieldValue.BoolVal(false);
  if !field_value_eq(&i1, &i1b) { return 1; }
  if field_value_eq(&i1, &f1) { return 2; }      // cross-type false
  if !field_value_eq(&t_a, &t_ab) { return 3; }
  if field_value_eq(&t_a, &t_b) { return 4; }
  if !field_value_eq(&b_t, &b_tb) { return 5; }
  if field_value_eq(&b_t, &b_f) { return 6; }
  return 0;
}
fn test_field_value_eq_matrix() -> TestResult {
  if run_field_value_eq_matrix() == 0 { return assert(true, "FieldValue: eq within type, false across types"); }
  return assert(false, "FieldValue: eq matrix failed");
}

fn run_filter_eq_value_mismatch() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var same = filter_eq("color", FieldValue.TextVal("red"));
  var diff = filter_eq("color", FieldValue.TextVal("blue"));
  if filter_matches(&diff, &p) { return 1; }
  if !filter_matches(&same, &p) { return 2; }
  return 0;
}
fn test_filter_eq_value_mismatch() -> TestResult {
  if run_filter_eq_value_mismatch() == 0 { return assert(true, "Filter: Eq value mismatch false, match true"); }
  return assert(false, "Filter: Eq value compare failed");
}

fn run_filter_range_inclusive() -> Int {
  // FloatVal restored after the v0.64.1 fix of XVC-C-06 (v0.64.0 zeroed f32
  // enum payloads in this unit; the FloatVal roundtrip pin probe guards it).
  var p = payload_new();
  payload_set(&mut p, "price", FieldValue.FloatVal(10.0));
  var at_lo = filter_range("price", 10.0, 20.0);
  var at_hi = filter_range("price", 0.0, 10.0);
  var above = filter_range("price", 10.01, 20.0);
  var below = filter_range("price", 0.0, 9.99);
  if !filter_matches(&at_lo, &p) { return 1; }
  if !filter_matches(&at_hi, &p) { return 2; }
  if filter_matches(&above, &p) { return 3; }
  if filter_matches(&below, &p) { return 4; }
  return 0;
}
fn test_filter_range_inclusive() -> TestResult {
  if run_filter_range_inclusive() == 0 { return assert(true, "Filter: Range bounds inclusive"); }
  return assert(false, "Filter: Range inclusivity failed");
}

fn run_filter_range_int_promotion() -> Int {
  var p = payload_new();
  payload_set(&mut p, "n", FieldValue.IntVal(5));
  var inside = filter_range("n", 1.0, 10.0);
  var outside = filter_range("n", 6.0, 10.0);
  if !filter_matches(&inside, &p) { return 1; }
  if filter_matches(&outside, &p) { return 2; }
  return 0;
}
fn test_filter_range_int_promotion() -> TestResult {
  if run_filter_range_int_promotion() == 0 { return assert(true, "Filter: Range promotes Int fields to Float32"); }
  return assert(false, "Filter: Int promotion failed");
}

fn run_filter_range_non_numeric() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var expr = filter_range("color", 0.0, 100.0);
  if filter_matches(&expr, &p) { return 1; }
  return 0;
}
fn test_filter_range_non_numeric() -> TestResult {
  if run_filter_range_non_numeric() == 0 { return assert(true, "Filter: Range on Text field is false"); }
  return assert(false, "Filter: non-numeric Range failed");
}

fn run_filter_range_missing() -> Int {
  var p = payload_new();
  var expr = filter_range("x", 0.0, 100.0);
  if filter_matches(&expr, &p) { return 1; }
  return 0;
}
fn test_filter_range_missing() -> TestResult {
  if run_filter_range_missing() == 0 { return assert(true, "Filter: Range on missing field is false"); }
  return assert(false, "Filter: missing Range failed");
}

fn run_filter_in_membership() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var vals = Vec[FieldValue].new();
  vals.push(FieldValue.TextVal("blue"));
  vals.push(FieldValue.TextVal("red"));
  var hit = filter_in("color", vals);
  if !filter_matches(&hit, &p) { return 1; }
  var vals2 = Vec[FieldValue].new();
  vals2.push(FieldValue.TextVal("green"));
  var miss = filter_in("color", vals2);
  if filter_matches(&miss, &p) { return 2; }
  return 0;
}
fn test_filter_in_membership() -> TestResult {
  if run_filter_in_membership() == 0 { return assert(true, "Filter: In membership hit/miss"); }
  return assert(false, "Filter: In membership failed");
}

fn run_filter_in_empty() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var vals = Vec[FieldValue].new();
  var expr = filter_in("color", vals);
  if filter_matches(&expr, &p) { return 1; }
  return 0;
}
fn test_filter_in_empty() -> TestResult {
  if run_filter_in_empty() == 0 { return assert(true, "Filter: In([]) is false"); }
  return assert(false, "Filter: empty In failed");
}

fn run_filter_missing_payload_semantics() -> Int {
  var store = payload_store_new();
  var ex = filter_exists("k");
  if payload_store_matches(&store, 1, &ex) { return 1; }
  var ne = filter_not(filter_exists("k"));
  if !payload_store_matches(&store, 1, &ne) { return 2; }
  var both = Vec[FilterExpr].new();
  both.push(filter_exists("k"));
  both.push(filter_exists("j"));
  var andx = filter_and(both);
  if payload_store_matches(&store, 1, &andx) { return 3; }
  var orx = filter_or(both);
  if payload_store_matches(&store, 1, &orx) { return 4; }
  return 0;
}
fn test_filter_missing_payload_semantics() -> TestResult {
  if run_filter_missing_payload_semantics() == 0 { return assert(true, "Filter: no-payload semantics (value false, Not true)"); }
  return assert(false, "Filter: no-payload semantics failed");
}

// ---- filtered search over an engine ----

fn setup_filtered_engine() -> VectorEngine {
  var eng = engine_new();
  engine_create_collection(&mut eng, 3, DistanceMetric.Cosine);
  engine_upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  engine_upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  engine_upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  payload_set(&mut p1, "price", FieldValue.FloatVal(5.0));
  engine_set_payload(&mut eng, 1, p1);
  var p2 = payload_new();
  payload_set(&mut p2, "color", FieldValue.TextVal("blue"));
  payload_set(&mut p2, "price", FieldValue.FloatVal(50.0));
  engine_set_payload(&mut eng, 2, p2);
  var p3 = payload_new();
  payload_set(&mut p3, "color", FieldValue.TextVal("red"));
  payload_set(&mut p3, "price", FieldValue.FloatVal(500.0));
  engine_set_payload(&mut eng, 3, p3);
  return eng;
}

fn run_filtered_search_only_matching() -> Int {
  var eng = setup_filtered_engine();
  var q = mk_vec3(1.0, 0.0, 0.0);
  var f = filter_eq("color", FieldValue.TextVal("red"));
  match engine_search_filtered(&eng, &q, 3, &f) {
    Ok(h) => {
      if h.items.len() != 2 { return 1; }
      if h.items[0].id != 1 { return 2; }
      if h.items[1].id != 3 { return 3; }
      return 0;
    }
    Err(_) => { return 4; }
  }
}
fn test_filtered_search_only_matching() -> TestResult {
  if run_filtered_search_only_matching() == 0 { return assert(true, "Filtered search: only matching points, ordered"); }
  return assert(false, "Filtered search: matching set wrong");
}

fn run_filtered_search_and_price() -> Int {
  var eng = setup_filtered_engine();
  var q = mk_vec3(1.0, 0.0, 0.0);
  var clauses = Vec[FilterExpr].new();
  clauses.push(filter_eq("color", FieldValue.TextVal("red")));
  clauses.push(filter_range("price", 0.0, 100.0));
  var f = filter_and(clauses);
  match engine_search_filtered(&eng, &q, 5, &f) {
    Ok(h) => {
      if h.items.len() == 1 && h.items[0].id == 1 { return 0; }
      return 1;
    }
    Err(_) => { return 2; }
  }
}
fn test_filtered_search_and_price() -> TestResult {
  if run_filtered_search_and_price() == 0 { return assert(true, "Filtered search: And(color, price range)"); }
  return assert(false, "Filtered search: And filter failed");
}

fn run_filtered_search_not() -> Int {
  var eng = setup_filtered_engine();
  var q = mk_vec3(1.0, 0.0, 0.0);
  var inner = filter_eq("color", FieldValue.TextVal("blue"));
  var f = filter_not(inner);
  match engine_search_filtered(&eng, &q, 5, &f) {
    Ok(h) => {
      if h.items.len() != 2 { return 1; }
      if h.items[0].id != 1 { return 2; }
      if h.items[1].id != 3 { return 3; }
      return 0;
    }
    Err(_) => { return 4; }
  }
}
fn test_filtered_search_not() -> TestResult {
  if run_filtered_search_not() == 0 { return assert(true, "Filtered search: Not(color=blue) excludes point 2"); }
  return assert(false, "Filtered search: Not filter failed");
}

fn run_filtered_search_bounded_k() -> Int {
  var eng = setup_filtered_engine();
  var q = mk_vec3(1.0, 0.0, 0.0);
  var f = filter_exists("color");
  match engine_search_filtered(&eng, &q, 1, &f) {
    Ok(h) => {
      if h.items.len() == 1 { return 0; }
      return 1;
    }
    Err(_) => { return 2; }
  }
}
fn test_filtered_search_bounded_k() -> TestResult {
  if run_filtered_search_bounded_k() == 0 { return assert(true, "Filtered search: k bound honoured (len <= k)"); }
  return assert(false, "Filtered search: k bound failed");
}

fn run_filtered_search_missing_payload_point() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var v1 = vector_new(2); vector_set(&mut v1, 0, 1.0);
  var v2 = vector_new(2); vector_set(&mut v2, 0, 2.0);
  engine_upsert(&mut eng, 1, v1);
  engine_upsert(&mut eng, 2, v2);
  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  engine_set_payload(&mut eng, 1, p1);
  var q = vector_new(2); vector_set(&mut q, 0, 1.0);
  var f = filter_exists("color");
  match engine_search_filtered(&eng, &q, 5, &f) {
    Ok(h) => {
      if h.items.len() == 1 && h.items[0].id == 1 { return 0; }
      return 1;
    }
    Err(_) => { return 2; }
  }
}
fn test_filtered_search_missing_payload_point() -> TestResult {
  if run_filtered_search_missing_payload_point() == 0 { return assert(true, "Filtered search: point without payload excluded"); }
  return assert(false, "Filtered search: missing payload handling failed");
}

fn run_filtered_search_dim_mismatch() -> Int {
  var eng = setup_filtered_engine();
  var q = vector_new(2); vector_set(&mut q, 0, 1.0);
  var f = filter_exists("color");
  match engine_search_filtered(&eng, &q, 1, &f) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}
fn test_filtered_search_dim_mismatch() -> TestResult {
  if run_filtered_search_dim_mismatch() == 0 { return assert(true, "Filtered search: dim mismatch -> Err"); }
  return assert(false, "Filtered search: dim mismatch not rejected");
}

fn run_set_payload_missing_point() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 1, DistanceMetric.Euclidean);
  var p = payload_new();
  payload_set(&mut p, "k", FieldValue.IntVal(1));
  match engine_set_payload(&mut eng, 99, p) {
    Ok(ok) => {
      if !ok { return 0; }
      return 1;
    }
    Err(_) => { return 2; }
  }
}
fn test_set_payload_missing_point() -> TestResult {
  if run_set_payload_missing_point() == 0 { return assert(true, "Payload: set on missing point -> Ok(false)"); }
  return assert(false, "Payload: missing-point set failed");
}

fn run_delete_removes_payload() -> Int {
  var eng = setup_filtered_engine();
  match engine_get_payload(&eng, 1) {
    Some(_) => {}
    None => { return 1; }
  }
  engine_delete(&mut eng, 1);
  match engine_get_payload(&eng, 1) {
    Some(_) => { return 2; }
    None => {}
  }
  var q = mk_vec3(1.0, 0.0, 0.0);
  var f = filter_eq("color", FieldValue.TextVal("red"));
  match engine_search_filtered(&eng, &q, 5, &f) {
    Ok(h) => {
      if h.items.len() == 1 && h.items[0].id == 3 { return 0; }
      return 3;
    }
    Err(_) => { return 4; }
  }
}
fn test_delete_removes_payload() -> TestResult {
  if run_delete_removes_payload() == 0 { return assert(true, "Payload: delete removes metadata, search reflects it"); }
  return assert(false, "Payload: delete cleanup failed");
}

fn run_payload_store_put_replace() -> Int {
  var s = payload_store_new();
  var p = payload_new();
  payload_set(&mut p, "k", FieldValue.IntVal(1));
  payload_store_put(&mut s, 7, p);
  var p2 = payload_new();
  payload_set(&mut p2, "k", FieldValue.IntVal(2));
  payload_store_put(&mut s, 7, p2);
  if payload_store_len(&s) != 1 { return 1; }
  match payload_store_get(&s, 7) {
    Some(v) => {
      if payload_len(&v) == 1 { return 0; }
      return 2;
    }
    None => { return 3; }
  }
}
fn test_payload_store_put_replace() -> TestResult {
  if run_payload_store_put_replace() == 0 { return assert(true, "PayloadStore: put replaces by id, len stable"); }
  return assert(false, "PayloadStore: replace failed");
}

// ============================================================================
// SECTION 15: Durable payloads (WAL codec + recovery)
// ============================================================================

fn run_payload_encode_empty() -> Int {
  var p = payload_new();
  var words = payload_encode(&p);
  if words.len() != 2 { return 1; }
  match payload_decode(&words) {
    Some(q) => {
      if payload_len(&q) == 0 { return 0; }
      return 2;
    }
    None => { return 3; }
  }
}
fn test_payload_encode_empty() -> TestResult {
  if run_payload_encode_empty() == 0 { return assert(true, "Payload codec: empty payload roundtrip"); }
  return assert(false, "Payload codec: empty roundtrip failed");
}

fn run_payload_encode_roundtrip() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("crimson red"));
  payload_set(&mut p, "stock", FieldValue.IntVal(-3));
  payload_set(&mut p, "active", FieldValue.BoolVal(false));
  var words = payload_encode(&p);
  match payload_decode(&words) {
    Some(q) => {
      if payload_len(&q) != 3 { return 1; }
      var wc = FieldValue.TextVal("crimson red");
      var ws = FieldValue.IntVal(-3);
      var wa = FieldValue.BoolVal(false);
      match payload_get(&q, "color") { Some(v) => { if !field_value_eq(&v, &wc) { return 2; } } None => { return 3; } }
      match payload_get(&q, "stock") { Some(v) => { if !field_value_eq(&v, &ws) { return 4; } } None => { return 5; } }
      match payload_get(&q, "active") { Some(v) => { if !field_value_eq(&v, &wa) { return 6; } } None => { return 7; } }
      return 0;
    }
    None => { return 8; }
  }
}
fn test_payload_encode_roundtrip() -> TestResult {
  if run_payload_encode_roundtrip() == 0 { return assert(true, "Payload codec: text/int(-3)/bool roundtrip"); }
  return assert(false, "Payload codec: roundtrip failed");
}

fn run_payload_encode_floatval() -> Int {
  // XVC-C-06 guard: FloatVal must survive the WAL codec bit-exactly.
  var p = payload_new();
  payload_set(&mut p, "price", FieldValue.FloatVal(-2.5));
  var words = payload_encode(&p);
  match payload_decode(&words) {
    Some(q) => {
      match payload_get(&q, "price") {
        Some(v) => {
          let expected = float.float_bits(-2.5);
          match v {
            FloatVal(f) => {
              if float.float_bits(f as Float64) == expected { return 0; }
              return 1;
            }
            _ => { return 2; }
          }
        }
        None => { return 3; }
      }
    }
    None => { return 4; }
  }
}
fn test_payload_encode_floatval() -> TestResult {
  if run_payload_encode_floatval() == 0 { return assert(true, "Payload codec: FloatVal bit-exact roundtrip"); }
  return assert(false, "Payload codec: FloatVal roundtrip failed");
}

fn run_payload_decode_malformed() -> Int {
  var empty = Vec[Int].new();
  match payload_decode(&empty) { Some(_) => { return 1; } None => {} }
  var badver = Vec[Int].new(); badver.push(0); badver.push(1);
  match payload_decode(&badver) { Some(_) => { return 2; } None => {} }
  var badkind = Vec[Int].new();
  badkind.push(1); badkind.push(1); badkind.push(1); badkind.push(65); badkind.push(9);
  match payload_decode(&badkind) { Some(_) => { return 3; } None => {} }
  var trunk = Vec[Int].new();
  trunk.push(1); trunk.push(1); trunk.push(5); trunk.push(65);
  match payload_decode(&trunk) { Some(_) => { return 4; } None => {} }
  var truncval = Vec[Int].new();
  truncval.push(1); truncval.push(1); truncval.push(1); truncval.push(65); truncval.push(1);
  match payload_decode(&truncval) { Some(_) => { return 5; } None => {} }
  return 0;
}
fn test_payload_decode_malformed() -> TestResult {
  if run_payload_decode_malformed() == 0 { return assert(true, "Payload codec: malformed -> None (5 shapes)"); }
  return assert(false, "Payload codec: malformed accepted");
}

fn run_payload_wal_before_ack() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var v = vector_new(2); vector_set(&mut v, 0, 1.0);
  engine_upsert(&mut eng, 1, v);
  if engine_durable_lsn(&eng) != 1 { return 1; }
  var p = payload_new();
  payload_set(&mut p, "k", FieldValue.IntVal(1));
  engine_set_payload(&mut eng, 1, p);
  if engine_durable_lsn(&eng) != 2 { return 2; }
  return 0;
}
fn test_payload_wal_before_ack() -> TestResult {
  if run_payload_wal_before_ack() == 0 { return assert(true, "Payload: set_payload appends a WAL record (LSN+1)"); }
  return assert(false, "Payload: WAL-before-ack failed");
}

fn run_recover_payloads() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var v = vector_new(2); vector_set(&mut v, 0, 1.0);
  engine_upsert(&mut eng, 1, v);
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  engine_set_payload(&mut eng, 1, p);
  var r = engine_recover(&eng.wal, 2, DistanceMetric.Euclidean);
  var ok: Bool = false;
  match engine_get_payload(&r, 1) {
    Some(q) => {
      var w = FieldValue.TextVal("red");
      match payload_get(&q, "color") { Some(vv) => { ok = field_value_eq(&vv, &w); } None => {} }
    }
    None => {}
  }
  if ok { return 0; }
  return 1;
}
fn test_recover_payloads() -> TestResult {
  if run_recover_payloads() == 0 { return assert(true, "Recovery: payload restored from WAL"); }
  return assert(false, "Recovery: payload restore failed");
}

fn run_recover_state_both() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var v1 = vector_new(2); vector_set(&mut v1, 0, 1.0);
  var v2 = vector_new(2); vector_set(&mut v2, 0, 2.0);
  engine_upsert(&mut eng, 1, v1);
  engine_upsert(&mut eng, 2, v2);
  var p1 = payload_new();
  payload_set(&mut p1, "k", FieldValue.IntVal(1));
  engine_set_payload(&mut eng, 1, p1);
  var p2 = payload_new();
  payload_set(&mut p2, "k", FieldValue.IntVal(2));
  engine_set_payload(&mut eng, 2, p2);
  var st = recover_state(&eng.wal, 2);
  if index_size(&st.store) != 2 { return 1; }
  if payload_store_len(&st.payloads) != 2 { return 2; }
  return 0;
}
fn test_recover_state_both() -> TestResult {
  if run_recover_state_both() == 0 { return assert(true, "Recovery: recover_state returns store + payloads"); }
  return assert(false, "Recovery: recover_state failed");
}

fn run_recover_payloads_chained() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var v = vector_new(2); vector_set(&mut v, 0, 1.0);
  engine_upsert(&mut eng, 1, v);
  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  engine_set_payload(&mut eng, 1, p1);
  var r1 = engine_recover(&eng.wal, 2, DistanceMetric.Euclidean);
  var p2 = payload_new();
  payload_set(&mut p2, "color", FieldValue.TextVal("green"));
  engine_set_payload(&mut r1, 1, p2);
  var r2 = engine_recover(&r1.wal, 2, DistanceMetric.Euclidean);
  var ok: Bool = false;
  match engine_get_payload(&r2, 1) {
    Some(q) => {
      var w = FieldValue.TextVal("green");
      match payload_get(&q, "color") { Some(vv) => { ok = field_value_eq(&vv, &w); } None => {} }
    }
    None => {}
  }
  if ok { return 0; }
  return 1;
}
fn test_recover_payloads_chained() -> TestResult {
  if run_recover_payloads_chained() == 0 { return assert(true, "Recovery: chained reopen keeps latest payload"); }
  return assert(false, "Recovery: chained payload failed");
}

fn run_recover_delete_clears_payload() -> Int {
  var eng = engine_new();
  engine_create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var v = vector_new(2); vector_set(&mut v, 0, 1.0);
  engine_upsert(&mut eng, 1, v);
  var p = payload_new();
  payload_set(&mut p, "k", FieldValue.IntVal(1));
  engine_set_payload(&mut eng, 1, p);
  var r1 = engine_recover(&eng.wal, 2, DistanceMetric.Euclidean);
  engine_delete(&mut r1, 1);
  var r2 = engine_recover(&r1.wal, 2, DistanceMetric.Euclidean);
  var gone: Bool = true;
  match engine_get_payload(&r2, 1) { Some(_) => { gone = false; } None => {} }
  if gone && engine_size(&r2) == 0 { return 0; }
  return 1;
}
fn test_recover_delete_clears_payload() -> TestResult {
  if run_recover_delete_clears_payload() == 0 { return assert(true, "Recovery: delete clears payload through reopen"); }
  return assert(false, "Recovery: delete payload cleanup failed");
}

fn run_recover_torn_payload_record() -> Int {
  var w = wal_writer_new();
  var v = vector_new(2); vector_set(&mut v, 0, 1.0);
  wal_writer_append_payload(&mut w, WalOpKind.Insert, 1, 1, vector_encode(&v));
  var torn = Vec[Int].new();
  torn.push(0); torn.push(1);   // bad version -> decode None
  wal_writer_append_payload(&mut w, WalOpKind.Update, 1, 1, torn);
  var good = payload_new();
  payload_set(&mut good, "k", FieldValue.IntVal(5));
  wal_writer_append_payload(&mut w, WalOpKind.Update, 1, 1, payload_encode(&good));
  var st = recover_state(&w, 2);
  if index_size(&st.store) != 1 { return 1; }
  if payload_store_len(&st.payloads) != 1 { return 2; }
  return 0;
}
fn test_recover_torn_payload_record() -> TestResult {
  if run_recover_torn_payload_record() == 0 { return assert(true, "Recovery: torn payload record skipped, later one applied"); }
  return assert(false, "Recovery: torn payload handling failed");
}

// ============================================================================
// SECTION 16: SQ8 quantization (reference study 02, Q-a) -- mirror of
// src/index/quantize.xi: trained per-dim ranges, truncation codec, the
// per-component bound, clamping, constant dimensions, rejection, and the
// two-tier candidates-then-exact-rescore equality on a tiny corpus.
// ============================================================================

pub type SQ8 = {
  dim: Int;
  vmin: Vec[Float32];
  vstep: Vec[Float32];
}

fn sq8_max_error(sq: &SQ8) -> Float32 {
  var m: Float32 = 0.0;
  var d: Int = 0;
  while d < sq.dim {
    if sq.vstep[d] > m { m = sq.vstep[d]; }
    d = d + 1;
  }
  return m;
}

fn sq8_train(vs: &Vec[Vector], out: &mut SQ8) -> Bool {
  if vs.len() == 0 { return false; }
  var dim: Int = vs[0].dimension;
  if dim < 1 { return false; }
  var vi: Int = 0;
  while vi < vs.len() {
    if vs[vi].dimension != dim { return false; }
    vi = vi + 1;
  }
  var vmin = Vec[Float32].new();
  var vmax = Vec[Float32].new();
  var d: Int = 0;
  while d < dim {
    vmin.push(vs[0].data[d]);
    vmax.push(vs[0].data[d]);
    d = d + 1;
  }
  vi = 0;
  while vi < vs.len() {
    d = 0;
    while d < dim {
      var x = vs[vi].data[d];
      if x < vmin[d] { vmin[d] = x; }
      if x > vmax[d] { vmax[d] = x; }
      d = d + 1;
    }
    vi = vi + 1;
  }
  out.dim = dim;
  out.vmin = Vec[Float32].new();
  out.vstep = Vec[Float32].new();
  d = 0;
  while d < dim {
    var span = vmax[d] - vmin[d];
    out.vmin.push(vmin[d]);
    if span > 0.0 { out.vstep.push(span / 255.0); } else { out.vstep.push(0.0); }
    d = d + 1;
  }
  return true;
}

fn sq8_encode_one(sq: &SQ8, v: &Vector) -> Vec[Int] {
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

fn sq8_decode_one(sq: &SQ8, codes: &Vec[Int], out: &mut Vector) -> Bool {
  if codes.len() != sq.dim { return false; }
  var d: Int = 0;
  while d < sq.dim {
    var c = codes[d];
    if c < 0 || c > 255 { return false; }
    out.data[d] = sq.vmin[d] + (c as Float32) * sq.vstep[d];
    d = d + 1;
  }
  return true;
}

fn run_sq8_train_ranges() -> Int {
  var vs = Vec[Vector].new();
  var a = vector_new(2);
  vector_set(&mut a, 0, 1.0);
  vector_set(&mut a, 1, 5.0);
  vs.push(a);
  var b = vector_new(2);
  vector_set(&mut b, 0, 9.0);
  vector_set(&mut b, 1, 5.0);
  vs.push(b);
  var c = vector_new(2);
  vector_set(&mut c, 0, 5.0);
  vector_set(&mut c, 1, 5.0);
  vs.push(c);
  var sq = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  if !sq8_train(&vs, &mut sq) { return 1; }
  if !f32_eq(sq.vmin[0], 1.0) { return 2; }
  if !f32_eq(sq.vmin[1], 5.0) { return 3; }
  if !f32_eq(sq.vstep[0], 8.0 / 255.0) { return 4; }
  if sq.vstep[1] != 0.0 { return 5; }
  return 0;
}
fn test_sq8_train_ranges() -> TestResult {
  if run_sq8_train_ranges() == 0 { return assert(true, "SQ8: per-dim min/step training (constant dim -> step 0)"); }
  return assert(false, "SQ8: training ranges failed");
}

fn run_sq8_roundtrip_bound() -> Int {
  var vs = Vec[Vector].new();
  var i: Int = 0;
  while i < 6 {
    var v = vector_new(3);
    vector_set(&mut v, 0, (i as Float32) * 1.5 - 4.0);
    vector_set(&mut v, 1, (i as Float32) * 0.25 + 1.0);
    vector_set(&mut v, 2, 7.0 - (i as Float32));
    vs.push(v);
    i = i + 1;
  }
  var sq = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  if !sq8_train(&vs, &mut sq) { return 1; }
  i = 0;
  while i < vs.len() {
    var codes = sq8_encode_one(&sq, &vs[i]);
    var dec = vector_new(3);
    if !sq8_decode_one(&sq, &codes, &mut dec) { return 2; }
    var d: Int = 0;
    while d < 3 {
      var err = vs[i].data[d] - dec.data[d];
      if err < 0.0 { err = 0.0 - err; }
      if err > sq.vstep[d] + 0.00001 { return 3; }
      d = d + 1;
    }
    i = i + 1;
  }
  return 0;
}
fn test_sq8_roundtrip_bound() -> TestResult {
  if run_sq8_roundtrip_bound() == 0 { return assert(true, "SQ8: roundtrip error <= step per component"); }
  return assert(false, "SQ8: roundtrip bound violated");
}

fn run_sq8_clamp_constant() -> Int {
  var vs = Vec[Vector].new();
  var a = vector_new(2);
  vector_set(&mut a, 0, 0.0);
  vector_set(&mut a, 1, 7.0);
  vs.push(a);
  var b = vector_new(2);
  vector_set(&mut b, 0, 10.0);
  vector_set(&mut b, 1, 7.0);
  vs.push(b);
  var sq = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  if !sq8_train(&vs, &mut sq) { return 1; }
  var lo = vector_new(2);
  vector_set(&mut lo, 0, 0.0 - 5.0);
  vector_set(&mut lo, 1, 7.0);
  var hic = vector_new(2);
  vector_set(&mut hic, 0, 10.0 + 500.0 * sq.vstep[0]);
  vector_set(&mut hic, 1, 7.0);
  var cl = sq8_encode_one(&sq, &lo);
  var ch = sq8_encode_one(&sq, &hic);
  if cl[0] != 0 { return 2; }
  if ch[0] != 255 { return 3; }
  // constant dim: code 0 and an exact decode
  var cc = sq8_encode_one(&sq, &a);
  if cc[1] != 0 { return 4; }
  var dec = vector_new(2);
  if !sq8_decode_one(&sq, &cc, &mut dec) { return 5; }
  if !f32_eq(dec.data[1], 7.0) { return 6; }
  return 0;
}
fn test_sq8_clamp_constant() -> TestResult {
  if run_sq8_clamp_constant() == 0 { return assert(true, "SQ8: clamp 0/255 + constant dim exact"); }
  return assert(false, "SQ8: clamp/constant-dim failed");
}

fn run_sq8_decode_rejects() -> Int {
  var sq = SQ8{ dim: 2, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  sq.vmin.push(0.0);
  sq.vmin.push(0.0);
  sq.vstep.push(1.0);
  sq.vstep.push(1.0);
  var out = vector_new(2);
  var short = Vec[Int].new();
  short.push(1);
  if sq8_decode_one(&sq, &short, &mut out) { return 1; }
  var over = Vec[Int].new();
  over.push(1);
  over.push(256);
  if sq8_decode_one(&sq, &over, &mut out) { return 2; }
  var neg = Vec[Int].new();
  neg.push(0 - 1);
  neg.push(1);
  if sq8_decode_one(&sq, &neg, &mut out) { return 3; }
  return 0;
}
fn test_sq8_decode_rejects() -> TestResult {
  if run_sq8_decode_rejects() == 0 { return assert(true, "SQ8: decode rejects short / 256 / negative codes"); }
  return assert(false, "SQ8: decode rejection failed");
}

fn run_sq8_train_rejects() -> Int {
  var empty = Vec[Vector].new();
  var sq = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  if sq8_train(&empty, &mut sq) { return 1; }
  var vs = Vec[Vector].new();
  var a = vector_new(2);
  vector_set(&mut a, 0, 0.5);
  vs.push(a);
  var b = vector_new(3);
  vector_set(&mut b, 0, 0.5);
  vs.push(b);
  if sq8_train(&vs, &mut sq) { return 2; }
  return 0;
}
fn test_sq8_train_rejects() -> TestResult {
  if run_sq8_train_rejects() == 0 { return assert(true, "SQ8: train rejects empty + dimension mismatch"); }
  return assert(false, "SQ8: train rejection failed");
}

fn run_sq8_rescore_equality() -> Int {
  // tiny corpus: 5 vectors, dim 2; query between the points
  var vs = Vec[Vector].new();
  var i: Int = 0;
  while i < 5 {
    var v = vector_new(2);
    vector_set(&mut v, 0, (i as Float32) * 1.25 - 2.0);
    vector_set(&mut v, 1, ((i % 2) as Float32) * 1.5);
    vs.push(v);
    i = i + 1;
  }
  var sq = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  if !sq8_train(&vs, &mut sq) { return 1; }
  var codes = Vec[Int].new();
  i = 0;
  while i < vs.len() {
    var cw = sq8_encode_one(&sq, &vs[i]);
    var j: Int = 0;
    while j < cw.len() { codes.push(cw[j]); j = j + 1; }
    i = i + 1;
  }
  var q = vector_new(2);
  vector_set(&mut q, 0, 2.5);
  vector_set(&mut q, 1, 0.25);
  var k: Int = 3;
  // phase 1: top k*8 (clamped to n) by quantized (decoded) distance
  var cap: Int = k * 8;
  if cap > vs.len() { cap = vs.len(); }
  var cand = topk_new(cap);
  var pos: Int = 0;
  while pos < vs.len() {
    var dec = vector_new(2);
    var cw = Vec[Int].new();
    var d: Int = 0;
    while d < 2 { cw.push(codes[pos * 2 + d]); d = d + 1; }
    if !sq8_decode_one(&sq, &cw, &mut dec) { return 2; }
    topk_push(&mut cand, Neighbor{ id: pos, distance: euclidean_distance(&dec, &q) });
    pos = pos + 1;
  }
  // phase 2: exact rescore of the candidates by ascending position
  var poslist = Vec[Int].new();
  i = 0;
  while i < cand_items_len(&cand) { poslist.push(cand.items[i].id); i = i + 1; }
  var p1: Int = 0;
  while p1 < poslist.len() {
    var p2: Int = p1 + 1;
    while p2 < poslist.len() {
      if poslist[p2] < poslist[p1] {
        var t = poslist[p1];
        poslist[p1] = poslist[p2];
        poslist[p2] = t;
      }
      p2 = p2 + 1;
    }
    p1 = p1 + 1;
  }
  var tier2 = topk_new(k);
  i = 0;
  while i < poslist.len() {
    var pp = poslist[i];
    topk_push(&mut tier2, Neighbor{ id: pp, distance: euclidean_distance(&vs[pp], &q) });
    i = i + 1;
  }
  // brute force
  var brute = topk_new(k);
  i = 0;
  while i < vs.len() {
    topk_push(&mut brute, Neighbor{ id: i, distance: euclidean_distance(&vs[i], &q) });
    i = i + 1;
  }
  if cand_items_len(&tier2) != cand_items_len(&brute) { return 3; }
  i = 0;
  while i < cand_items_len(&brute) {
    if tier2.items[i].id != brute.items[i].id { return 4; }
    if !f32_eq(tier2.items[i].distance, brute.items[i].distance) { return 5; }
    i = i + 1;
  }
  return 0;
}

fn cand_items_len(h: &TopKHeap) -> Int {
  return h.items.len();
}

fn test_sq8_rescore_equality() -> TestResult {
  if run_sq8_rescore_equality() == 0 { return assert(true, "SQ8: two-tier rescore equals the exact top-k"); }
  return assert(false, "SQ8: two-tier rescore diverged");
}

// ============================================================================
// Main -- manual dispatch
// ============================================================================

// NOTE: dispatch by evaluated result, not `&fn()` pointers. On compiler
// v0.64.0 a `&fn() -> T` parameter called as `f()` emits invalid LLVM IR
// (`inttoptr ptr to ptr`, clang exit 1) and `(*f)()` compiles but crashes
// (exit 0xC0000005). Finding XVC-C-01; repro docs/repro/xv-fnptr-call-inttoptr/.
fn run_one_test(r: TestResult) -> Int {
  return report(r.passed, r.name);
}

fn main() -> Int {
  io.println("=== XIOM-Vector Conformance Tests ===");
  var failed: Int = 0; var total: Int = 0;

  // SECTION 1: Types
  failed = failed + run_one_test(test_types_vector_id_construct()); total = total + 1;
  failed = failed + run_one_test(test_types_collection_id_construct()); total = total + 1;
  failed = failed + run_one_test(test_types_segment_id_construct()); total = total + 1;
  failed = failed + run_one_test(test_types_segment_id_eq()); total = total + 1;
  failed = failed + run_one_test(test_types_dimension_construct()); total = total + 1;
  failed = failed + run_one_test(test_types_dimension_eq()); total = total + 1;
  failed = failed + run_one_test(test_types_dimension_is_valid()); total = total + 1;

  // SECTION 2: Distance metrics
  failed = failed + run_one_test(test_distance_euclidean_same()); total = total + 1;
  failed = failed + run_one_test(test_distance_euclidean_345()); total = total + 1;
  failed = failed + run_one_test(test_distance_cosine_identical()); total = total + 1;
  failed = failed + run_one_test(test_distance_cosine_orthogonal()); total = total + 1;
  failed = failed + run_one_test(test_distance_cosine_opposite()); total = total + 1;
  failed = failed + run_one_test(test_distance_cosine_zero_vector()); total = total + 1;
  failed = failed + run_one_test(test_distance_dot_same()); total = total + 1;
  failed = failed + run_one_test(test_distance_dot_orthogonal()); total = total + 1;
  failed = failed + run_one_test(test_distance_dispatch_euclidean()); total = total + 1;
  failed = failed + run_one_test(test_distance_dispatch_cosine()); total = total + 1;
  failed = failed + run_one_test(test_distance_dispatch_dot()); total = total + 1;
  failed = failed + run_one_test(test_distance_magnitude()); total = total + 1;
  failed = failed + run_one_test(test_distance_magnitude_zero()); total = total + 1;
  failed = failed + run_one_test(test_distance_dot_raw()); total = total + 1;

  // SECTION 3: Vector store
  failed = failed + run_one_test(test_store_index_new()); total = total + 1;
  failed = failed + run_one_test(test_store_index_add()); total = total + 1;
  failed = failed + run_one_test(test_store_index_add_duplicate()); total = total + 1;
  failed = failed + run_one_test(test_store_index_get()); total = total + 1;
  failed = failed + run_one_test(test_store_index_get_miss()); total = total + 1;
  failed = failed + run_one_test(test_store_index_remove()); total = total + 1;
  failed = failed + run_one_test(test_store_index_remove_miss()); total = total + 1;
  failed = failed + run_one_test(test_store_index_add_multiple()); total = total + 1;

  // SECTION 4: HNSW index (params only, HNSW has T001 errors per AUDIT.md)
  failed = failed + run_one_test(test_hnsw_params_valid()); total = total + 1;
  failed = failed + run_one_test(test_hnsw_params_invalid_m()); total = total + 1;
  failed = failed + run_one_test(test_hnsw_params_m_too_high()); total = total + 1;
  failed = failed + run_one_test(test_hnsw_params_invalid_efc()); total = total + 1;
  failed = failed + run_one_test(test_hnsw_params_invalid_efs()); total = total + 1;
  failed = failed + run_one_test(test_hnsw_params_default_values()); total = total + 1;

  // SECTION 5: Flat index
  failed = failed + run_one_test(test_flat_search_exact_top1()); total = total + 1;
  failed = failed + run_one_test(test_flat_search_results_bounded()); total = total + 1;
  failed = failed + run_one_test(test_flat_search_ordered()); total = total + 1;
  failed = failed + run_one_test(test_flat_search_all_metrics()); total = total + 1;
  failed = failed + run_one_test(test_range_search_basic()); total = total + 1;
  failed = failed + run_one_test(test_batch_ops_basic()); total = total + 1;

  // SECTION 6: Segment management
  failed = failed + run_one_test(test_segment_new()); total = total + 1;
  failed = failed + run_one_test(test_segment_insert()); total = total + 1;
  failed = failed + run_one_test(test_segment_transition_mutable_sealing()); total = total + 1;
  failed = failed + run_one_test(test_segment_transition_full_lifecycle()); total = total + 1;
  failed = failed + run_one_test(test_segment_transition_illegal()); total = total + 1;
  failed = failed + run_one_test(test_segment_transition_sealed_indexing_ok()); total = total + 1;
  failed = failed + run_one_test(test_segment_transition_dropped_terminal()); total = total + 1;
  failed = failed + run_one_test(test_manifest_new()); total = total + 1;
  failed = failed + run_one_test(test_manifest_add_remove()); total = total + 1;
  failed = failed + run_one_test(test_manifest_remove_miss()); total = total + 1;
  failed = failed + run_one_test(test_manifest_lsn()); total = total + 1;
  failed = failed + run_one_test(test_state_is_writable()); total = total + 1;
  failed = failed + run_one_test(test_state_is_terminal()); total = total + 1;
  failed = failed + run_one_test(test_state_code_all()); total = total + 1;

  // SECTION 7: Collection
  failed = failed + run_one_test(test_collection_schema_new()); total = total + 1;
  failed = failed + run_one_test(test_collection_schema_normalization()); total = total + 1;
  failed = failed + run_one_test(test_collection_schema_add_field()); total = total + 1;
  failed = failed + run_one_test(test_collection_schema_dimension()); total = total + 1;
  failed = failed + run_one_test(test_collection_new()); total = total + 1;
  failed = failed + run_one_test(test_collection_register_segment()); total = total + 1;
  failed = failed + run_one_test(test_validate_dimension_ok()); total = total + 1;
  failed = failed + run_one_test(test_validate_dimension_mismatch()); total = total + 1;
  failed = failed + run_one_test(test_validate_metric_all()); total = total + 1;

  // SECTION 8: Payload
  failed = failed + run_one_test(test_payload_new()); total = total + 1;
  failed = failed + run_one_test(test_payload_set_has()); total = total + 1;
  failed = failed + run_one_test(test_payload_len()); total = total + 1;
  failed = failed + run_one_test(test_field_value_kind()); total = total + 1;
  failed = failed + run_one_test(test_filter_exists_true()); total = total + 1;
  failed = failed + run_one_test(test_filter_exists_false()); total = total + 1;
  failed = failed + run_one_test(test_filter_eq()); total = total + 1;
  failed = failed + run_one_test(test_filter_and_both_true()); total = total + 1;
  failed = failed + run_one_test(test_filter_and_one_false()); total = total + 1;
  failed = failed + run_one_test(test_filter_or_one_true()); total = total + 1;
  failed = failed + run_one_test(test_filter_or_both_false()); total = total + 1;
  failed = failed + run_one_test(test_filter_not_true()); total = total + 1;
  failed = failed + run_one_test(test_filter_not_false()); total = total + 1;
  failed = failed + run_one_test(test_filter_empty_not()); total = total + 1;

  // SECTION 9: Search
  failed = failed + run_one_test(test_topk_new()); total = total + 1;
  failed = failed + run_one_test(test_topk_push_bounded()); total = total + 1;
  failed = failed + run_one_test(test_topk_push_sorted()); total = total + 1;
  failed = failed + run_one_test(test_topk_is_full()); total = total + 1;
  failed = failed + run_one_test(test_topk_worst()); total = total + 1;
  failed = failed + run_one_test(test_topk_worst_empty()); total = total + 1;
  failed = failed + run_one_test(test_engine_new()); total = total + 1;
  failed = failed + run_one_test(test_engine_create_collection()); total = total + 1;
  failed = failed + run_one_test(test_engine_create_collection_invalid()); total = total + 1;
  failed = failed + run_one_test(test_engine_upsert()); total = total + 1;
  failed = failed + run_one_test(test_engine_upsert_dim_mismatch()); total = total + 1;
  failed = failed + run_one_test(test_engine_search()); total = total + 1;
  failed = failed + run_one_test(test_search_hits_shape()); total = total + 1;
  failed = failed + run_one_test(test_engine_delete()); total = total + 1;
  failed = failed + run_one_test(test_engine_delete_miss()); total = total + 1;
  failed = failed + run_one_test(test_engine_full_lifecycle()); total = total + 1;

  // SECTION 10: ANN index
  failed = failed + run_one_test(test_ann_kind_names()); total = total + 1;
  failed = failed + run_one_test(test_ann_kind_enum_variants()); total = total + 1;
  failed = failed + run_one_test(test_ann_params_collection_attached()); total = total + 1;

  // SECTION 11: Error types
  failed = failed + run_one_test(test_error_dimension_mismatch()); total = total + 1;
  failed = failed + run_one_test(test_error_unsupported_metric()); total = total + 1;
  failed = failed + run_one_test(test_error_collection_not_found()); total = total + 1;
  failed = failed + run_one_test(test_error_invalid_vector()); total = total + 1;
  failed = failed + run_one_test(test_error_segment_sealed()); total = total + 1;
  failed = failed + run_one_test(test_error_topk_exceeded()); total = total + 1;
  failed = failed + run_one_test(test_error_to_str_all()); total = total + 1;
  failed = failed + run_one_test(test_error_codes_unique()); total = total + 1;

  // SECTION 12: Durability/engine
  failed = failed + run_one_test(test_wal_new()); total = total + 1;
  failed = failed + run_one_test(test_wal_append()); total = total + 1;
  failed = failed + run_one_test(test_wal_append_multiple()); total = total + 1;
  failed = failed + run_one_test(test_wal_current_lsn()); total = total + 1;
  failed = failed + run_one_test(test_wal_flush()); total = total + 1;
  failed = failed + run_one_test(test_wal_before_ack_contract()); total = total + 1;
  failed = failed + run_one_test(test_counter_new()); total = total + 1;
  failed = failed + run_one_test(test_counter_inc()); total = total + 1;
  failed = failed + run_one_test(test_engine_counters()); total = total + 1;
  failed = failed + run_one_test(test_id_map_new()); total = total + 1;
  failed = failed + run_one_test(test_id_map_put_lookup()); total = total + 1;
  failed = failed + run_one_test(test_id_map_put_update()); total = total + 1;
  failed = failed + run_one_test(test_id_map_remove()); total = total + 1;
  failed = failed + run_one_test(test_id_map_remove_miss()); total = total + 1;
  failed = failed + run_one_test(test_id_map_lookup_miss()); total = total + 1;

  // SECTION 13: Durable codec + recovery replay (Phase 2)
  failed = failed + run_one_test(test_codec_roundtrip()); total = total + 1;
  failed = failed + run_one_test(test_codec_bit_exactness()); total = total + 1;
  failed = failed + run_one_test(test_codec_malformed_rejected()); total = total + 1;
  failed = failed + run_one_test(test_recover_replays_inserts()); total = total + 1;
  failed = failed + run_one_test(test_recover_replays_delete()); total = total + 1;
  failed = failed + run_one_test(test_recover_search_identical()); total = total + 1;
  failed = failed + run_one_test(test_recover_lsn_continuity()); total = total + 1;
  failed = failed + run_one_test(test_recover_twice()); total = total + 1;

  // SECTION 14: Payload filtering (Phase 3)
  failed = failed + run_one_test(test_payload_get()); total = total + 1;
  failed = failed + run_one_test(test_payload_set_overwrite()); total = total + 1;
  failed = failed + run_one_test(test_field_value_eq_matrix()); total = total + 1;
  failed = failed + run_one_test(test_filter_eq_value_mismatch()); total = total + 1;
  failed = failed + run_one_test(test_filter_range_inclusive()); total = total + 1;
  failed = failed + run_one_test(test_filter_range_int_promotion()); total = total + 1;
  failed = failed + run_one_test(test_filter_range_non_numeric()); total = total + 1;
  failed = failed + run_one_test(test_filter_range_missing()); total = total + 1;
  failed = failed + run_one_test(test_filter_in_membership()); total = total + 1;
  failed = failed + run_one_test(test_filter_in_empty()); total = total + 1;
  failed = failed + run_one_test(test_filter_missing_payload_semantics()); total = total + 1;
  failed = failed + run_one_test(test_filtered_search_only_matching()); total = total + 1;
  failed = failed + run_one_test(test_filtered_search_and_price()); total = total + 1;
  failed = failed + run_one_test(test_filtered_search_not()); total = total + 1;
  failed = failed + run_one_test(test_filtered_search_bounded_k()); total = total + 1;
  failed = failed + run_one_test(test_filtered_search_missing_payload_point()); total = total + 1;
  failed = failed + run_one_test(test_filtered_search_dim_mismatch()); total = total + 1;
  failed = failed + run_one_test(test_set_payload_missing_point()); total = total + 1;
  failed = failed + run_one_test(test_delete_removes_payload()); total = total + 1;
  failed = failed + run_one_test(test_payload_store_put_replace()); total = total + 1;

  // SECTION 15: Durable payloads (WAL codec + recovery)
  failed = failed + run_one_test(test_payload_encode_empty()); total = total + 1;
  failed = failed + run_one_test(test_payload_encode_roundtrip()); total = total + 1;
  failed = failed + run_one_test(test_payload_encode_floatval()); total = total + 1;
  failed = failed + run_one_test(test_payload_decode_malformed()); total = total + 1;
  failed = failed + run_one_test(test_payload_wal_before_ack()); total = total + 1;
  failed = failed + run_one_test(test_recover_payloads()); total = total + 1;
  failed = failed + run_one_test(test_recover_state_both()); total = total + 1;
  failed = failed + run_one_test(test_recover_payloads_chained()); total = total + 1;
  failed = failed + run_one_test(test_recover_delete_clears_payload()); total = total + 1;
  failed = failed + run_one_test(test_recover_torn_payload_record()); total = total + 1;
  failed = failed + run_one_test(test_recover_torn_tail_tolerated()); total = total + 1;

  // SECTION 16: SQ8 quantization (reference study 02, Q-a)
  failed = failed + run_one_test(test_sq8_train_ranges()); total = total + 1;
  failed = failed + run_one_test(test_sq8_roundtrip_bound()); total = total + 1;
  failed = failed + run_one_test(test_sq8_clamp_constant()); total = total + 1;
  failed = failed + run_one_test(test_sq8_decode_rejects()); total = total + 1;
  failed = failed + run_one_test(test_sq8_train_rejects()); total = total + 1;
  failed = failed + run_one_test(test_sq8_rescore_equality()); total = total + 1;

  // Boundary/validation
  failed = failed + run_one_test(test_is_valid_dimension()); total = total + 1;
  failed = failed + run_one_test(test_is_valid_top_k()); total = total + 1;
  failed = failed + run_one_test(test_engine_search_empty()); total = total + 1;
  failed = failed + run_one_test(test_engine_durable_lsn_tracks()); total = total + 1;
  failed = failed + run_one_test(test_neighbor_struct()); total = total + 1;
  failed = failed + run_one_test(test_search_result_struct()); total = total + 1;
  failed = failed + run_one_test(test_dimension_within_limit()); total = total + 1;
  failed = failed + run_one_test(test_f32_approx_epsilon()); total = total + 1;
  failed = failed + run_one_test(test_search_request_fields()); total = total + 1;
  failed = failed + run_one_test(test_request_filtered()); total = total + 1;
  failed = failed + run_one_test(test_request_hydration()); total = total + 1;
  failed = failed + run_one_test(test_request_metric_mismatch()); total = total + 1;

  let passed = total - failed;
  io.println("");
  io.println("XIOM-Vector Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
