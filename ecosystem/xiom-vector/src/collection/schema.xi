module xiom.vector.collection.schema

use xiom.vector.types.metric;
use xiom.core.contracts;

// The immutable description of a collection: its vector dimension, distance
// metric, normalization policy, and the payload fields eligible for filtering.
// Dimension and metric are fixed at creation — this is the root of the
// "dimension is constant" invariant enforced by the validator.

pub enum NormalizationMode {
  Raw,
  L2Normalized,
}

pub type PayloadFieldSpec = {
  name: Str;
  indexed: Bool;
} derive[Clone]

pub type CollectionSchema = {
  dimension: Int;
  metric: DistanceMetric;
  normalization: NormalizationMode;
  payload_fields: Vec[PayloadFieldSpec];
}

pub fn schema_new(dimension: Int, metric: DistanceMetric) -> CollectionSchema
  requires: is_valid_dimension(dimension)
  ensures: result.dimension == dimension
{
  var fields = Vec[PayloadFieldSpec].new();
  return CollectionSchema{
    dimension: dimension,
    metric: metric,
    normalization: NormalizationMode.Raw,
    payload_fields: fields,
  };
}

pub fn schema_set_normalization(s: &mut CollectionSchema, mode: NormalizationMode) {
  s.normalization = mode;
}

pub fn schema_add_field(s: &mut CollectionSchema, name: Str, indexed: Bool) {
  s.payload_fields.push(PayloadFieldSpec{ name: name, indexed: indexed });
}

pub fn schema_dimension(s: &CollectionSchema) -> Int {
  return s.dimension;
}
