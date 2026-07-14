module xiom.vector.types.dense_vector

use xiom.math;

// Dense float32 vector — the fundamental value type of the engine. `dimension`
// is fixed at construction and must equal the owning collection's dimension for
// the lifetime of the point (see docs/contracts-and-invariants.md).

pub type Vector = {
  data: Vec[Float32];
  dimension: UInt;
} derive[Clone]

pub fn Vector.new(dimension: UInt) -> Vector
  requires: dimension > 0
  ensures: result.data.len() == dimension
{
  var data_vec = Vec[Float32].new();
  var i: UInt = 0;
  while i < dimension {
    data_vec.push(0.0);
    i = i + 1;
  }
  return Vector{ data: data_vec, dimension: dimension };
}

pub fn Vector.set(index: UInt, value: Float32)
  requires: index < dimension
{
  data[index] = value;
}

pub fn Vector.get(index: UInt) -> Float32
  requires: index < dimension
{
  return data[index];
}

pub fn vector_dot(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum: Float32 = 0.0;
  var i: UInt = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return sum;
}

pub fn vector_magnitude(v: &Vector) -> Float32 {
  var sum_sq: Float32 = 0.0;
  var i: UInt = 0;
  while i < v.dimension {
    sum_sq = sum_sq + v.data[i] * v.data[i];
    i = i + 1;
  }
  return (xiom.math.sqrt(sum_sq as Float64) as Float32);
}

pub fn vector_normalize(v: &Vector) -> Vector
  requires: vector_magnitude(&v) > 0.0 {
  var mag = vector_magnitude(v);
  var result = Vector.new(v.dimension);
  var i: UInt = 0;
  if mag == 0.0 {
    return result;
  }
  while i < v.dimension {
    result.data[i] = v.data[i] / mag;
    i = i + 1;
  }
  return result;
}

pub fn vector_add(a: &Vector, b: &Vector) -> Vector
  requires: a.dimension == b.dimension
{
  var result = Vector.new(a.dimension);
  var i: UInt = 0;
  while i < a.dimension {
    result.data[i] = a.data[i] + b.data[i];
    i = i + 1;
  }
  return result;
}

pub fn vector_sub(a: &Vector, b: &Vector) -> Vector
  requires: a.dimension == b.dimension
{
  var result = Vector.new(a.dimension);
  var i: UInt = 0;
  while i < a.dimension {
    result.data[i] = a.data[i] - b.data[i];
    i = i + 1;
  }
  return result;
}

pub fn vector_scale(v: &Vector, scalar: Float32) -> Vector {
  var result = Vector.new(v.dimension);
  var i: UInt = 0;
  while i < v.dimension {
    result.data[i] = v.data[i] * scalar;
    i = i + 1;
  }
  return result;
}

pub fn vector_dimension(v: &Vector) -> UInt {
  return v.dimension;
}
