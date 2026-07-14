module xiom.vector.collection.collection

use xiom.core.ids;
use xiom.vector.collection.schema;
use xiom.vector.index.ann_index;

// A Collection binds a schema to its physical realization: the set of live
// segments and the ANN index configuration used to search them. SCAFFOLD: the
// engine currently manages one collection with a single segment; the segment
// registry here is the shape Phase 5 grows into.

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
  // TODO(Phase 5): update the durable manifest before exposing the segment.
  c.segments.push(seg);
}

pub fn collection_segment_count(c: &Collection) -> Int {
  return c.segments.len();
}

pub fn collection_dimension(c: &Collection) -> Int {
  return schema_dimension(&c.schema);
}
