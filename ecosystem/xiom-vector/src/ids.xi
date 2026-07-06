module xiom.vector.ids

use xiom.core.ids;

// Identity for the vector engine. CollectionId, VectorId, and SegmentId are
// reused verbatim from xiom.core.ids (a `use` brings them into scope) so the
// whole ecosystem shares one id vocabulary. PointId is added here: it is the
// user-facing external id of a stored point, kept distinct from the internal
// VectorId (a dense storage slot) so the two can never be confused at compile
// time.

pub type PointId = { value: Int; } derive[Clone, Eq]

pub fn point_id(v: Int) -> PointId {
  return PointId{ value: v };
}

pub fn point_id_value(id: &PointId) -> Int {
  return id.value;
}

pub fn point_id_eq(a: &PointId, b: &PointId) -> Bool {
  return a.value == b.value;
}

// Bridge a user-facing PointId to the internal VectorId storage handle.
pub fn point_to_vector_id(id: &PointId) -> VectorId {
  return vector_id(id.value);
}

pub fn vector_to_point_id(id: &VectorId) -> PointId {
  return PointId{ value: vector_id_value(id) };
}
