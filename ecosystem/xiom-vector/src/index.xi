module xiom.vector.index

pub type VectorIndex = {
  vectors: Vec[Vector];
  ids: Vec[Int];
  dim: UInt;
}

pub fn index_new(dim: UInt) -> VectorIndex
  requires: dim > 0
{
  return VectorIndex{
    vectors: Vec[Vector].new();
    ids: Vec[Int].new();
    dim: dim;
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
