module xiom.vector.segment.segment

use xiom.vector.segment.segment_state;

// Local types — mirrors types absorbed into engine.
pub type SegmentId = { value: Int; }
pub type Vector = {
  data: Vec[Float32];
  dimension: Int;
}

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

pub fn index_size(idx: &VectorIndex) -> Int {
  return idx.ids.len();
}

pub type Segment = {
  id: SegmentId;
  state: SegmentStateKind;
  store: VectorIndex;
}

pub fn segment_new(id: SegmentId, dim: Int) -> Segment
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
  return index_add(&mut seg.store, id, vec);
}

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