module xiom.vector.collection.collection
// Local type wrappers — mirrors xiom.core.ids and xiom.vector.index.ann_index.
pub type CollectionId = { value: Int; }
pub type SegmentId = { value: Int; }

pub enum AnnIndexKind { Flat, Hnsw, Ivf }
pub type AnnParams = { m: Int; ef_construction: Int; ef_search: Int; } derive[Clone]

fn ann_params_default() -> AnnParams {
  return AnnParams{ m: 16, ef_construction: 200, ef_search: 64 };
}

pub type CollectionSchema = {
  name: Str;
  dimension: Int;
  metric: Str;
}

pub fn schema_dimension(s: &CollectionSchema) -> Int {
  return s.dimension;
}

pub type Collection = {
  id: CollectionId;
  schema: CollectionSchema;
  segments: Vec[SegmentId];
  index_kind: AnnIndexKind;
  index_params: AnnParams;
}

pub fn collection_new(id: CollectionId, schema: CollectionSchema, index_kind: AnnIndexKind) -> Collection {
  var segments = Vec[SegmentId].new();
  return Collection{
    id: id,
    schema: schema,
    segments: segments,
    index_kind: index_kind,
    index_params: ann_params_default(),
  };
}

pub fn collection_register_segment(c: &mut Collection, seg: SegmentId) {
  c.segments.push(seg);
}

pub fn collection_segment_count(c: &Collection) -> Int {
  return c.segments.len();
}

pub fn collection_dimension(c: &Collection) -> Int {
  return schema_dimension(&c.schema);
}