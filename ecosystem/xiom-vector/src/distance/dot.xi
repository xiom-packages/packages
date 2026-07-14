module xiom.vector.distance.dot

use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;

// Dot-product distance kernel. `dot_distance` is the negated inner product
// (closer = smaller, as the search layer expects); `dot_raw` is the raw
// similarity score for callers that want it directly.

pub fn dot_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  return dot_product_distance(a, b);
}

pub fn dot_raw(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  return vector_dot(a, b);
}
