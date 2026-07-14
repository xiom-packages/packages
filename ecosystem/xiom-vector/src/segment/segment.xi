module xiom.vector.segment.segment

use xiom.core.ids;
use xiom.vector.segment.segment_state;
use xiom.vector.storage.vector_store;
use xiom.vector.types.dense_vector;

// A Segment wraps a physical vector store plus its lifecycle state. New writes
// land in a single Mutable segment; once it reaches a size threshold it is
// sealed, indexed, and becomes Immutable. Search fans out across all
// non-dropped segments. SCAFFOLD: transitions are enforced but sealing/indexing
// side effects (building the immutable HNSW) arrive in Phase 5.

pub type Segment = {
  id: SegmentId;
  state: SegmentStateKind;
  store: VectorIndex;
}

pub fn segment_new(id: SegmentId, dim: UInt) -> Segment
  requires: dim > 0
{
  return Segment{
    id: id,
    state: SegmentStateKind.Mutable,
    store: index_new(dim),
  };
}

pub fn segment_insert(seg: &mut Segment, id: Int, vec: Vector) -> Bool
  requires: seg.store.dim == vec.dimension
{
  // TODO(Phase 5): reject the write unless segment_state_is_writable(&seg.state);
  // today the engine only ever holds a single mutable segment.
  return index_add(&mut seg.store, id, vec);
}

// Attempt a lifecycle transition; returns false (no-op) if it is illegal.
pub fn segment_transition(seg: &mut Segment, to: SegmentStateKind) -> Bool {
  if !segment_state_can_transition(&seg.state, &to) {
    return false;
  }
  seg.state = to;
  return true;
}

pub fn segment_size(seg: &Segment) -> Int {
  return index_size(&seg.store);
}

pub fn segment_is_writable(seg: &Segment) -> Bool {
  return segment_state_is_writable(&seg.state);
}
