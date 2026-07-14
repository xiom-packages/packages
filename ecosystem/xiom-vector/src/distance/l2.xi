module xiom.vector.distance.l2

use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;

// L2 (Euclidean) distance kernel. The canonical implementation lives in
// types.metric; this module is the seam where a SIMD/FMA kernel will be dropped
// in during Phase 10 without touching call sites. `l2_squared` avoids the sqrt
// and is preferred anywhere only the ordering (not the magnitude) matters.

pub fn l2_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  return euclidean_distance(a, b);
}

pub fn l2_squared(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum_sq: Float32 = 0.0;
  var i: UInt = 0;
  while i < a.dimension {
    var diff = a.data[i] - b.data[i];
    sum_sq = sum_sq + diff * diff;
    i = i + 1;
  }
  return sum_sq;
}
