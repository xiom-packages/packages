module xiom.vector.collection.validator

use xiom.vector.collection.schema;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.error;
use xiom.core.contracts;

// Guards every write and query against a collection. The central rule: a
// vector's dimension must equal the schema dimension exactly (the "dimension is
// constant after creation" invariant). Metric compatibility is checked here
// too. These are the checks migrated from the old index_add / search_knn
// `requires:` clauses, now centralised and returning typed errors.

pub fn validate_dimension(schema: &CollectionSchema, dim: Int) -> Bool {
  return schema.dimension == dim;
}

pub fn validate_vector(schema: &CollectionSchema, v: &Vector) -> Result[Bool, VectorError] {
  if !is_valid_dimension(schema.dimension) {
    return Err(VectorError.InvalidVector("schema dimension out of range"));
  }
  if (v.dimension as Int) != schema.dimension {
    return Err(VectorError.DimensionMismatch(schema.dimension, v.dimension as Int));
  }
  return Ok(true);
}

pub fn validate_metric(schema: &CollectionSchema, metric: DistanceMetric) -> Result[Bool, VectorError] {
  // All three built-in metrics are currently supported for every schema.
  match metric {
    Cosine => Ok(true),
    DotProduct => Ok(true),
    Euclidean => Ok(true),
  }
}
