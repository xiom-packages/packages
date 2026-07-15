module xiom.vector.ids

pub type VectorId = { value: Int; } derive[Clone, Eq]
pub type PointId = { value: Int; } derive[Clone, Eq]

fn vector_id(v: Int) -> VectorId {
  return VectorId{ value: v };
}

fn vector_id_value(id: &VectorId) -> Int {
  return id.value;
}

pub fn point_id(v: Int) -> PointId {
  return PointId{ value: v };
}

pub fn point_id_value(id: &PointId) -> Int {
  return id.value;
}

pub fn point_id_eq(a: &PointId, b: &PointId) -> Bool {
  return a.value == b.value;
}

pub fn point_to_vector_id(id: &PointId) -> VectorId {
  return vector_id(id.value);
}

pub fn vector_to_point_id(id: &VectorId) -> PointId {
  return PointId{ value: vector_id_value(id) };
}