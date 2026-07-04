module xiom.vector.types

pub type VectorId = UInt64;

pub type Neighbor = {
  id: VectorId;
  distance: Float32;
} derive[Clone]

pub type Vector = {
  data: Vec[Float32];
  dimension: UInt;
  invariant: data.len() == dimension;
} derive[Clone]

pub type HNSWNode = {
  id: VectorId;
  neighbors: Vec[Neighbor];
  invariant: neighbors.len() <= 16;
} derive[Clone]

pub enum DistanceMetric {
  Cosine,
  DotProduct,
  Euclidean,
}

pub fn Vector.new(dimension: UInt) -> Vector
  requires: dimension > 0
  ensures: data.len() == dimension
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

pub fn HNSWNode.new(id: VectorId) -> HNSWNode {
  return HNSWNode{ id: id, neighbors: Vec[Neighbor].new() };
}

fn sqrt_f32(x: Float32) -> Float32 {
  if x <= 0.0 { return 0.0; }
  var guess: Float32 = x / 2.0;
  var i: UInt = 0;
  while i < 20 {
    guess = (guess + x / guess) / 2.0;
    i = i + 1;
  }
  return guess;
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
  var similarity = dot / (sqrt_f32(mag_a) * sqrt_f32(mag_b));
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
  return sqrt_f32(sum_sq);
}
