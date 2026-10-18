// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.collection.validator
// LEGACY module: the canonical DistanceMetric lives in the `xiom.vectors`
// package (src/vectors.xi). DO NOT IMPORT from new code -- importing this
// module (or any xiom.vector.collection.* sibling) loads the collection
// family into the catalog and trips the XVC-C-14 same-name trap against
// ann_index/shim types (observed on v0.64.4, probe_snapshot build
// 2026-10-13). Kept for reference until the porter flow retires it.
// Local types -- mirrors core types absorbed into engine.

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