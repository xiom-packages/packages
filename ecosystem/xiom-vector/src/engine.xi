module xiom.vector.engine

use xiom.math;

// ============================================================================
// XIOM-Vector: Consolidated Engine — Vector + Distances + Index + WAL + API
// ============================================================================

// ---- Inline CoreError (from xiom.core.error) ----
pub enum CoreError {
  NotFound,
  InvalidInput(msg: Str),
  OutOfBounds,
  Corruption(msg: Str),
  IOFailure(msg: Str),
  Unsupported(msg: Str),
  CapacityExceeded,
  InvalidState(msg: Str),
  ChecksumMismatch,
  VersionMismatch,
}

// ---- Inline WalOpKind, WalRecord, WalWriter (from xiom.core.wal) ----
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

pub fn wal_writer_new() -> WalWriter {
  var records = Vec[WalRecord].new();
  return WalWriter{ records: records, next_lsn: 1, synced_lsn: 0 };
}

pub fn wal_writer_append(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int) -> Int {
  var assigned = w.next_lsn;
  var payload = Vec[Int].new();
  var rec = WalRecord{
    lsn: assigned, op: op, key: key, value: value, payload: payload, timestamp: 0,
  };
  w.records.push(rec);
  w.next_lsn = w.next_lsn + 1;
  return assigned;
}

pub fn wal_writer_current_lsn(w: &WalWriter) -> Int {
  return w.next_lsn - 1;
}

pub fn wal_writer_flush(w: &mut WalWriter) -> Bool {
  w.synced_lsn = w.next_lsn - 1;
  return true;
}

// ---- Inline Counter (from xiom.core.metrics) ----
pub type Counter = {
  name: Str;
  value: Int;
}

pub fn counter_new(name: Str) -> Counter {
  return Counter{ name: name, value: 0 };
}

pub fn counter_inc(c: &mut Counter) {
  c.value = c.value + 1;
}

// ---- Inline CollectionId, VectorId, SegmentId (from xiom.core.ids) ----
pub type CollectionId = { value: Int; } derive[Clone, Eq]
pub type VectorId = { value: Int; } derive[Clone, Eq]
pub type SegmentId = { value: Int; } derive[Clone, Eq]

pub fn collection_id(v: Int) -> CollectionId {
  return CollectionId{ value: v };
}

pub fn vector_id(v: Int) -> VectorId {
  return VectorId{ value: v };
}

pub fn vector_id_value(id: &VectorId) -> Int {
  return id.value;
}

pub fn segment_id(v: Int) -> SegmentId {
  return SegmentId{ value: v };
}

pub fn segment_id_eq(a: &SegmentId, b: &SegmentId) -> Bool {
  return a.value == b.value;
}

// ---- Validity predicates ----
pub fn is_valid_dimension(dim: Int) -> Bool {
  return dim >= 1 && dim <= 65536;
}

pub fn is_valid_top_k(k: Int) -> Bool {
  return k >= 1 && k <= 10000;
}

// ---- Vector (from dense_vector.xi) ----
pub type Vector = {
  data: Vec[Float32];
  dimension: Int;
} derive[Clone]

pub fn Vector.new(dimension: Int) -> Vector
  requires: dimension > 0
  ensures: result.data.len() == dimension
{
  var data_vec = Vec[Float32].new();
  var i: Int = 0;
  while i < dimension {
    data_vec.push(0.0);
    i = i + 1;
  }
  return Vector{ data: data_vec, dimension: dimension };
}

pub fn Vector.set(index: Int, value: Float32)
  requires: index < dimension
{
  data[index] = value;
}

pub fn Vector.get(index: Int) -> Float32
  requires: index < dimension
{
  return data[index];
}

pub fn vector_dot(a: &Vector, b: &Vector) -> Float32
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

pub fn vector_magnitude(v: &Vector) -> Float32 {
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  while i < v.dimension {
    sum_sq = sum_sq + v.data[i] * v.data[i];
    i = i + 1;
  }
  return (xiom.math.sqrt(sum_sq as Float64) as Float32);
}

// ---- DistanceMetric + distance functions (from metric.xi) ----
pub enum DistanceMetric {
  Cosine,
  DotProduct,
  Euclidean,
}

pub fn dot_product_distance(a: &Vector, b: &Vector) -> Float32
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

pub fn cosine_distance(a: &Vector, b: &Vector) -> Float32
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
  var similarity = dot / ((xiom.math.sqrt(mag_a as Float64) as Float32) * (xiom.math.sqrt(mag_b as Float64) as Float32));
  return 1.0 - similarity;
}

pub fn euclidean_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    var diff = a.data[i] - b.data[i];
    sum_sq = sum_sq + diff * diff;
    i = i + 1;
  }
  return (xiom.math.sqrt(sum_sq as Float64) as Float32);
}

pub fn vector_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32
  requires: a.dimension == b.dimension
{
  match metric {
    Cosine => cosine_distance(a, b),
    DotProduct => dot_product_distance(a, b),
    Euclidean => euclidean_distance(a, b),
  }
}

// ---- Neighbor (from neighbor.xi) ----
pub type Neighbor = {
  id: UInt64;
  distance: Float32;
} derive[Clone]

pub fn neighbor_new(id: UInt64, distance: Float32) -> Neighbor {
  return Neighbor{ id: id, distance: distance };
}

// ---- VectorIndex (from vector_store.xi) ----
pub type VectorIndex = {
  vectors: Vec[Vector];
  ids: Vec[Int];
  dim: Int;
}

pub fn index_new(dim: Int) -> VectorIndex
  requires: dim > 0
{
  return VectorIndex{
    vectors: Vec[Vector].new(),
    ids: Vec[Int].new(),
    dim: dim,
  };
}

pub fn index_add(idx: &mut VectorIndex, id: Int, vec: Vector) -> Bool
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

pub fn index_remove(idx: &mut VectorIndex, id: Int) -> Bool {
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

pub fn index_get(idx: &VectorIndex, id: Int) -> Option[Vector] {
  var i: Int = 0;
  while i < idx.ids.len() {
    if idx.ids[i] == id {
      return Some(idx.vectors[i]);
    }
    i = i + 1;
  }
  return None;
}

pub fn index_size(idx: &VectorIndex) -> Int {
  return idx.ids.len();
}

// ---- SearchResult + search (from search_service.xi) ----
pub type SearchResult = {
  id: Int;
  distance: Float32;
} derive[Clone]

pub fn search_knn(idx: &VectorIndex, query: &Vector, k: Int, metric: DistanceMetric) -> Vec[SearchResult]
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

// ---- Write-ahead events (inline, from write_ahead_events.xi) ----
pub fn log_upsert(w: &mut WalWriter, collection: Int, point: Int) -> Int {
  return wal_writer_append(w, WalOpKind.Insert, collection, point);
}

pub fn log_delete(w: &mut WalWriter, collection: Int, point: Int) -> Int {
  return wal_writer_append(w, WalOpKind.Delete, collection, point);
}

// ---- VectorEngine (from engine.xi) ----
pub type VectorEngine = {
  store: VectorIndex;
  metric: DistanceMetric;
  dimension: Int;
  created: Bool;
  wal: WalWriter;
  upserts: Counter;
  deletes: Counter;
  next_collection: Int;
}

pub fn engine_new() -> VectorEngine {
  return VectorEngine{
    store: index_new(1),
    metric: DistanceMetric.Euclidean,
    dimension: 0,
    created: false,
    wal: wal_writer_new(),
    upserts: counter_new("vector.upserts"),
    deletes: counter_new("vector.deletes"),
    next_collection: 1,
  };
}

pub fn engine_create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError]
  requires: dim >= 1
{
  if !is_valid_dimension(dim) {
    return Err(CoreError.InvalidInput("dimension out of range"));
  }
  eng.store = index_new(dim);
  eng.dimension = dim;
  eng.metric = metric;
  eng.created = true;
  var id = collection_id(eng.next_collection);
  eng.next_collection = eng.next_collection + 1;
  return Ok(id);
}

pub fn engine_upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError]
  requires: eng.created
{
  if vec.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  log_upsert(&mut eng.wal, 1, point);
  var ok = index_add(&mut eng.store, point, vec);
  counter_inc(&mut eng.upserts);
  return Ok(ok);
}

pub fn engine_search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[Vec[SearchResult], CoreError]
  requires: eng.created
  requires: k > 0
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  var hits = search_knn(&eng.store, query, k, eng.metric);
  return Ok(hits);
}

pub fn engine_delete(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError]
  requires: eng.created
{
  log_delete(&mut eng.wal, 1, point);
  var ok = index_remove(&mut eng.store, point);
  counter_inc(&mut eng.deletes);
  return Ok(ok);
}

pub fn engine_size(eng: &VectorEngine) -> Int {
  return index_size(&eng.store);
}

pub fn engine_durable_lsn(eng: &VectorEngine) -> Int {
  return wal_writer_current_lsn(&eng.wal);
}

// ---- Vector API (from api/vector_api.xi) ----
pub fn create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError] {
  return engine_create_collection(eng, dim, metric);
}

pub fn upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError] {
  return engine_upsert(eng, point, vec);
}

pub fn search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[Vec[SearchResult], CoreError] {
  return engine_search(eng, query, k);
}

pub fn delete_point(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError] {
  return engine_delete(eng, point);
}

pub fn get_point(eng: &VectorEngine, point: Int) -> Option[Vector] {
  return index_get(&eng.store, point);
}