module xiom.vector.types

use xiom.math;

pub type Neighbor = {
  id: UInt64;
  distance: Float32;
} derive[Clone]

pub type Vector = {
  data: Vec[Float32];
  dimension: UInt;
} derive[Clone]

pub type HNSWNode = {
  id: UInt64;
  neighbors: Vec[Neighbor];
} derive[Clone]

pub enum DistanceMetric {
  Cosine,
  DotProduct,
  Euclidean,
}

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

pub fn HNSWNode.new(id: UInt64) -> HNSWNode {
  return HNSWNode{ id: id, neighbors: Vec[Neighbor].new() };
}

pub fn dot_product_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum: Float32 = 0.0;
  var i: UInt = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return -sum;
}

pub fn cosine_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var dot: Float32 = 0.0;
  var mag_a: Float32 = 0.0;
  var mag_b: Float32 = 0.0;
  var i: UInt = 0;
  while i < a.dimension {
    var ai = a.data[i];
    var bi = b.data[i];
    dot = dot + ai * bi;
    mag_a = mag_a + ai * ai;
    mag_b = mag_b + bi * bi;
    i = i + 1;
  }
  if mag_a == 0.0 || mag_b == 0.0 { return 1.0; }
  var similarity = dot / ((xiom.math.sqrt(mag_a as Float64) as Float32) * (xiom.math.sqrt(mag_b as Float64) as Float32));
  return 1.0 - similarity;
}

pub fn euclidean_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum_sq: Float32 = 0.0;
  var i: UInt = 0;
  while i < a.dimension {
    var diff = a.data[i] - b.data[i];
    sum_sq = sum_sq + diff * diff;
    i = i + 1;
  }
  return (xiom.math.sqrt(sum_sq as Float64) as Float32);
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

pub fn vector_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32
  requires: a.dimension == b.dimension
{
  match metric {
    Cosine { return cosine_distance(a, b); };
    DotProduct { return dot_product_distance(a, b); };
    Euclidean { return euclidean_distance(a, b); };
  }
}

pub fn vector_dimension(v: &Vector) -> UInt {
  return v.dimension;
}
