module xiom.vector.distance.cosine

use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;

// Cosine distance kernel. Delegates to the canonical implementation in
// types.metric. `cosine_similarity` returns the raw cos(theta) in [-1, 1] for
// callers that want the similarity rather than the distance.

pub fn cosine_kernel(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  return cosine_distance(a, b);
}

pub fn cosine_similarity(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  return 1.0 - cosine_distance(a, b);
}
