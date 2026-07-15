module xiom.vector.collection.validator
// Local types — mirrors core types absorbed into engine.

pub enum VectorError {
  DimensionMismatch(expected: Int, got: Int),
  UnsupportedMetric(name: Str),
  CollectionNotFound(id: Int),
  InvalidVector(msg: Str),
  SegmentSealed(id: Int),
  TopKExceeded(requested: Int, max: Int),
}

fn is_valid_dimension(dim: Int) -> Bool {
  return dim >= 1 && dim <= 65536;
}

pub type CollectionSchema = {
  name: Str;
  dimension: Int;
  metric: Str;
}

pub type Vector = {
  data: Vec[Float32];
  dimension: Int;
}

pub enum DistanceMetric { Cosine, DotProduct, Euclidean }

pub fn validate_dimension(schema: &CollectionSchema, dim: Int) -> Bool {
  return schema.dimension == dim;
}

pub fn validate_vector(schema: &CollectionSchema, v: &Vector) -> Result[Bool, VectorError] {
  if !is_valid_dimension(schema.dimension) {
    return Err(VectorError.InvalidVector("schema dimension out of range"));
  }
  if v.dimension != schema.dimension {
    return Err(VectorError.DimensionMismatch(schema.dimension, v.dimension));
  }
  return Ok(true);
}

pub fn validate_metric(schema: &CollectionSchema, metric: DistanceMetric) -> Result[Bool, VectorError] {
  match metric {
    Cosine => Ok(true),
    DotProduct => Ok(true),
    Euclidean => Ok(true),
  }
}