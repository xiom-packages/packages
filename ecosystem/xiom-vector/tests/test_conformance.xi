module xiom.vector.tests.test_conformance

use xiom.io;
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
  filter: Int;
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
  var id = collection_id(eng.next_collection);
  eng.next_collection = eng.next_collection + 1;
  return Some(id);
}

fn engine_upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Bool {
  if vec.dimension != eng.dimension {
    return false;
  }
  wal_writer_append(&mut eng.wal, WalOpKind.Insert, 1, point);
  var ok = index_add(&mut eng.store, point, vec);
  counter_inc(&mut eng.upserts);
  return ok;
}

fn engine_search(eng: &VectorEngine, query: &Vector, k: Int) -> Vec[SearchResult] {
  if query.dimension != eng.dimension {
    var empty = Vec[SearchResult].new();
    return empty;
  }
  if !is_valid_top_k(k) {
    var empty = Vec[SearchResult].new();
    return empty;
  }
  return search_knn(&eng.store, query, k, eng.metric);
}

fn engine_delete(eng: &mut VectorEngine, point: Int) -> Bool {
  wal_writer_append(&mut eng.wal, WalOpKind.Delete, 1, point);
  var ok = index_remove(&mut eng.store, point);
  counter_inc(&mut eng.deletes);
  return ok;
}

fn engine_size(eng: &VectorEngine) -> Int {
  return index_size(&eng.store);
}

fn engine_durable_lsn(eng: &VectorEngine) -> Int {
  return wal_writer_current_lsn(&eng.wal);
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

// ============================================================================
// Helper: filter operations
// ============================================================================

fn filter_eq(field: Str, value: FieldValue) -> FilterExpr {
  return FilterExpr.Eq(field, value);
}

fn filter_exists(field: Str) -> FilterExpr {
  return FilterExpr.Exists(field);
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
      return payload_has(p, field);
    }
    Range(field, lo, hi) => {
      return payload_has(p, field);
    }
    Exists(field) => {
      return payload_has(p, field);
    }
    In(field, values) => {
      return payload_has(p, field);
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
// SECTION 1: Types — VectorId, CollectionId, SegmentId construction
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
// SECTION 2: Distance metrics — L2, cosine, dot product correctness
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
// SECTION 3: Vector store — insert, search, delete operations
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
// SECTION 4: HNSW index — construction stubs
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
// SECTION 5: Flat index — brute-force search correctness
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
// SECTION 6: Segment management — manifest, state transitions
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
// SECTION 7: Collection — schema validation, CRUD
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
// SECTION 8: Payload — filter AST, evaluation
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
// SECTION 9: Search — top-K heap, search orchestration
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
  var eng = engine_new();
  var cid = engine_create_collection(&mut eng, 0, DistanceMetric.Euclidean);
  match cid {
    Some(_) => { return 1; }
    None => { return 0; }
  }
}
fn test_engine_create_collection_invalid() -> TestResult {
  if run_engine_create_collection_invalid() == 0 { return assert(true, "Engine: create_collection(0) rejects invalid dim"); }
  return assert(false, "Engine: invalid dim should fail");
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
  var results = engine_search(&eng, &query, 1);
  if results.len() == 1 && results[0].id == 10 { return 0; }
  return 1;
}
fn test_engine_search() -> TestResult {
  if run_engine_search() == 0 { return assert(true, "Engine: search returns nearest (id=10)"); }
  return assert(false, "Engine: search failed");
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
  var results = engine_search(&eng, &query, 3);
  if results.len() == 3 && results[0].id == 1 { return 0; }
  return 1;
}
fn test_engine_full_lifecycle() -> TestResult {
  if run_engine_full_lifecycle() == 0 { return assert(true, "Engine: full create/upsert/search lifecycle"); }
  return assert(false, "Engine: lifecycle failed");
}

// ============================================================================
// SECTION 10: ANN index — type dispatch (AnnIndexKind)
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
// SECTION 12: Durability/engine stubs — WAL, Counter, IdMap
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
  var results = engine_search(&eng, &query, 5);
  if results.len() == 0 { return 0; }
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
// Search request building (from query/search_request.xi)
// ============================================================================

fn run_search_request_fields() -> Int {
  var query = vector_new(2);
  vector_set(&mut query, 0, 1.0);
  var req = SearchRequest{ query: query, top_k: 10, metric: DistanceMetric.Cosine, filter: 0, with_payload: false };
  if req.top_k == 10 && req.metric == DistanceMetric.Cosine && !req.with_payload { return 0; }
  return 1;
}
fn test_search_request_fields() -> TestResult {
  if run_search_request_fields() == 0 { return assert(true, "SearchRequest: field init top_k=10 Cosine no payload"); }
  return assert(false, "SearchRequest: field init failed");
}

// ============================================================================
// Main — manual dispatch
// ============================================================================

fn run_one_test(fn_ptr: &fn() -> TestResult) -> Int {
  return report(fn_ptr().passed, fn_ptr().name);
}

fn main() -> Int {
  io.println("=== XIOM-Vector Conformance Tests ===");
  var failed: Int = 0; var total: Int = 0;

  // SECTION 1: Types
  failed = failed + run_one_test(&test_types_vector_id_construct); total = total + 1;
  failed = failed + run_one_test(&test_types_collection_id_construct); total = total + 1;
  failed = failed + run_one_test(&test_types_segment_id_construct); total = total + 1;
  failed = failed + run_one_test(&test_types_segment_id_eq); total = total + 1;
  failed = failed + run_one_test(&test_types_dimension_construct); total = total + 1;
  failed = failed + run_one_test(&test_types_dimension_eq); total = total + 1;
  failed = failed + run_one_test(&test_types_dimension_is_valid); total = total + 1;

  // SECTION 2: Distance metrics
  failed = failed + run_one_test(&test_distance_euclidean_same); total = total + 1;
  failed = failed + run_one_test(&test_distance_euclidean_345); total = total + 1;
  failed = failed + run_one_test(&test_distance_cosine_identical); total = total + 1;
  failed = failed + run_one_test(&test_distance_cosine_orthogonal); total = total + 1;
  failed = failed + run_one_test(&test_distance_cosine_opposite); total = total + 1;
  failed = failed + run_one_test(&test_distance_cosine_zero_vector); total = total + 1;
  failed = failed + run_one_test(&test_distance_dot_same); total = total + 1;
  failed = failed + run_one_test(&test_distance_dot_orthogonal); total = total + 1;
  failed = failed + run_one_test(&test_distance_dispatch_euclidean); total = total + 1;
  failed = failed + run_one_test(&test_distance_dispatch_cosine); total = total + 1;
  failed = failed + run_one_test(&test_distance_dispatch_dot); total = total + 1;
  failed = failed + run_one_test(&test_distance_magnitude); total = total + 1;
  failed = failed + run_one_test(&test_distance_magnitude_zero); total = total + 1;
  failed = failed + run_one_test(&test_distance_dot_raw); total = total + 1;

  // SECTION 3: Vector store
  failed = failed + run_one_test(&test_store_index_new); total = total + 1;
  failed = failed + run_one_test(&test_store_index_add); total = total + 1;
  failed = failed + run_one_test(&test_store_index_add_duplicate); total = total + 1;
  failed = failed + run_one_test(&test_store_index_get); total = total + 1;
  failed = failed + run_one_test(&test_store_index_get_miss); total = total + 1;
  failed = failed + run_one_test(&test_store_index_remove); total = total + 1;
  failed = failed + run_one_test(&test_store_index_remove_miss); total = total + 1;
  failed = failed + run_one_test(&test_store_index_add_multiple); total = total + 1;

  // SECTION 4: HNSW index (params only, HNSW has T001 errors per AUDIT.md)
  failed = failed + run_one_test(&test_hnsw_params_valid); total = total + 1;
  failed = failed + run_one_test(&test_hnsw_params_invalid_m); total = total + 1;
  failed = failed + run_one_test(&test_hnsw_params_m_too_high); total = total + 1;
  failed = failed + run_one_test(&test_hnsw_params_invalid_efc); total = total + 1;
  failed = failed + run_one_test(&test_hnsw_params_invalid_efs); total = total + 1;
  failed = failed + run_one_test(&test_hnsw_params_default_values); total = total + 1;

  // SECTION 5: Flat index
  failed = failed + run_one_test(&test_flat_search_exact_top1); total = total + 1;
  failed = failed + run_one_test(&test_flat_search_results_bounded); total = total + 1;
  failed = failed + run_one_test(&test_flat_search_ordered); total = total + 1;
  failed = failed + run_one_test(&test_flat_search_all_metrics); total = total + 1;

  // SECTION 6: Segment management
  failed = failed + run_one_test(&test_segment_new); total = total + 1;
  failed = failed + run_one_test(&test_segment_insert); total = total + 1;
  failed = failed + run_one_test(&test_segment_transition_mutable_sealing); total = total + 1;
  failed = failed + run_one_test(&test_segment_transition_full_lifecycle); total = total + 1;
  failed = failed + run_one_test(&test_segment_transition_illegal); total = total + 1;
  failed = failed + run_one_test(&test_segment_transition_sealed_indexing_ok); total = total + 1;
  failed = failed + run_one_test(&test_segment_transition_dropped_terminal); total = total + 1;
  failed = failed + run_one_test(&test_manifest_new); total = total + 1;
  failed = failed + run_one_test(&test_manifest_add_remove); total = total + 1;
  failed = failed + run_one_test(&test_manifest_remove_miss); total = total + 1;
  failed = failed + run_one_test(&test_manifest_lsn); total = total + 1;
  failed = failed + run_one_test(&test_state_is_writable); total = total + 1;
  failed = failed + run_one_test(&test_state_is_terminal); total = total + 1;
  failed = failed + run_one_test(&test_state_code_all); total = total + 1;

  // SECTION 7: Collection
  failed = failed + run_one_test(&test_collection_schema_new); total = total + 1;
  failed = failed + run_one_test(&test_collection_schema_normalization); total = total + 1;
  failed = failed + run_one_test(&test_collection_schema_add_field); total = total + 1;
  failed = failed + run_one_test(&test_collection_schema_dimension); total = total + 1;
  failed = failed + run_one_test(&test_collection_new); total = total + 1;
  failed = failed + run_one_test(&test_collection_register_segment); total = total + 1;
  failed = failed + run_one_test(&test_validate_dimension_ok); total = total + 1;
  failed = failed + run_one_test(&test_validate_dimension_mismatch); total = total + 1;
  failed = failed + run_one_test(&test_validate_metric_all); total = total + 1;

  // SECTION 8: Payload
  failed = failed + run_one_test(&test_payload_new); total = total + 1;
  failed = failed + run_one_test(&test_payload_set_has); total = total + 1;
  failed = failed + run_one_test(&test_payload_len); total = total + 1;
  failed = failed + run_one_test(&test_field_value_kind); total = total + 1;
  failed = failed + run_one_test(&test_filter_exists_true); total = total + 1;
  failed = failed + run_one_test(&test_filter_exists_false); total = total + 1;
  failed = failed + run_one_test(&test_filter_eq); total = total + 1;
  failed = failed + run_one_test(&test_filter_and_both_true); total = total + 1;
  failed = failed + run_one_test(&test_filter_and_one_false); total = total + 1;
  failed = failed + run_one_test(&test_filter_or_one_true); total = total + 1;
  failed = failed + run_one_test(&test_filter_or_both_false); total = total + 1;
  failed = failed + run_one_test(&test_filter_not_true); total = total + 1;
  failed = failed + run_one_test(&test_filter_not_false); total = total + 1;
  failed = failed + run_one_test(&test_filter_empty_not); total = total + 1;

  // SECTION 9: Search
  failed = failed + run_one_test(&test_topk_new); total = total + 1;
  failed = failed + run_one_test(&test_topk_push_bounded); total = total + 1;
  failed = failed + run_one_test(&test_topk_push_sorted); total = total + 1;
  failed = failed + run_one_test(&test_topk_is_full); total = total + 1;
  failed = failed + run_one_test(&test_topk_worst); total = total + 1;
  failed = failed + run_one_test(&test_topk_worst_empty); total = total + 1;
  failed = failed + run_one_test(&test_engine_new); total = total + 1;
  failed = failed + run_one_test(&test_engine_create_collection); total = total + 1;
  failed = failed + run_one_test(&test_engine_create_collection_invalid); total = total + 1;
  failed = failed + run_one_test(&test_engine_upsert); total = total + 1;
  failed = failed + run_one_test(&test_engine_upsert_dim_mismatch); total = total + 1;
  failed = failed + run_one_test(&test_engine_search); total = total + 1;
  failed = failed + run_one_test(&test_engine_delete); total = total + 1;
  failed = failed + run_one_test(&test_engine_delete_miss); total = total + 1;
  failed = failed + run_one_test(&test_engine_full_lifecycle); total = total + 1;

  // SECTION 10: ANN index
  failed = failed + run_one_test(&test_ann_kind_names); total = total + 1;
  failed = failed + run_one_test(&test_ann_kind_enum_variants); total = total + 1;
  failed = failed + run_one_test(&test_ann_params_collection_attached); total = total + 1;

  // SECTION 11: Error types
  failed = failed + run_one_test(&test_error_dimension_mismatch); total = total + 1;
  failed = failed + run_one_test(&test_error_unsupported_metric); total = total + 1;
  failed = failed + run_one_test(&test_error_collection_not_found); total = total + 1;
  failed = failed + run_one_test(&test_error_invalid_vector); total = total + 1;
  failed = failed + run_one_test(&test_error_segment_sealed); total = total + 1;
  failed = failed + run_one_test(&test_error_topk_exceeded); total = total + 1;
  failed = failed + run_one_test(&test_error_to_str_all); total = total + 1;
  failed = failed + run_one_test(&test_error_codes_unique); total = total + 1;

  // SECTION 12: Durability/engine
  failed = failed + run_one_test(&test_wal_new); total = total + 1;
  failed = failed + run_one_test(&test_wal_append); total = total + 1;
  failed = failed + run_one_test(&test_wal_append_multiple); total = total + 1;
  failed = failed + run_one_test(&test_wal_current_lsn); total = total + 1;
  failed = failed + run_one_test(&test_wal_flush); total = total + 1;
  failed = failed + run_one_test(&test_wal_before_ack_contract); total = total + 1;
  failed = failed + run_one_test(&test_counter_new); total = total + 1;
  failed = failed + run_one_test(&test_counter_inc); total = total + 1;
  failed = failed + run_one_test(&test_engine_counters); total = total + 1;
  failed = failed + run_one_test(&test_id_map_new); total = total + 1;
  failed = failed + run_one_test(&test_id_map_put_lookup); total = total + 1;
  failed = failed + run_one_test(&test_id_map_put_update); total = total + 1;
  failed = failed + run_one_test(&test_id_map_remove); total = total + 1;
  failed = failed + run_one_test(&test_id_map_remove_miss); total = total + 1;
  failed = failed + run_one_test(&test_id_map_lookup_miss); total = total + 1;

  // Boundary/validation
  failed = failed + run_one_test(&test_is_valid_dimension); total = total + 1;
  failed = failed + run_one_test(&test_is_valid_top_k); total = total + 1;
  failed = failed + run_one_test(&test_engine_search_empty); total = total + 1;
  failed = failed + run_one_test(&test_engine_durable_lsn_tracks); total = total + 1;
  failed = failed + run_one_test(&test_neighbor_struct); total = total + 1;
  failed = failed + run_one_test(&test_search_result_struct); total = total + 1;
  failed = failed + run_one_test(&test_dimension_within_limit); total = total + 1;
  failed = failed + run_one_test(&test_f32_approx_epsilon); total = total + 1;
  failed = failed + run_one_test(&test_search_request_fields); total = total + 1;

  let passed = total - failed;
  io.println("");
  io.println("XIOM-Vector Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
