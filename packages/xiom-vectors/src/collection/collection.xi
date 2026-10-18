// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.collection.collection
// LEGACY local type wrappers (pre-`xiom.vectors` swap). DO NOT IMPORT from
// new code: this module re-declares same-named types (AnnParams,
// AnnIndexKind, CollectionId, SegmentId) that collide with the canonical
// ones (xiom.vector.index.ann_index / xiom.vector.core.shim /
// the xiom.vectors package) -- the XVC-C-14 short-name layout-shadow trap.
// Importing anything under the xiom.vector.collection prefix was observed
// to break engine.core type resolution on v0.64.4 (probe_snapshot build,
// 2026-10-13). Kept for reference until the porter flow retires it.
// Local type wrappers -- mirrors xiom.core.ids and xiom.vector.index.ann_index.
pub type CollectionId = { value: Int; }
pub type SegmentId = { value: Int; }

pub enum AnnIndexKind { Flat, Hnsw, Ivf }
pub type AnnParams = { m: Int; ef_construction: Int; ef_search: Int; } derive[Clone]

fn ann_params_default() -> AnnParams {
  return AnnParams{ m: 16, ef_construction: 200, ef_search: 64 };
}

pub type CollectionSchema = {
  name: Str;
  dimension: Int;
  metric: Str;
}

pub fn schema_dimension(s: &CollectionSchema) -> Int {
  return s.dimension;
}

pub type Collection = {
  id: CollectionId;
  schema: CollectionSchema;
  segments: Vec[SegmentId];
  index_kind: AnnIndexKind;
  index_params: AnnParams;
}

pub fn collection_new(id: CollectionId, schema: CollectionSchema, index_kind: AnnIndexKind) -> Collection {
  var segments = Vec[SegmentId].new();
  return Collection{
    id: id,
    schema: schema,
    segments: segments,
    index_kind: index_kind,
    index_params: ann_params_default(),
  };
}

pub fn collection_register_segment(c: &mut Collection, seg: SegmentId) {
  c.segments.push(seg);
}

pub fn collection_segment_count(c: &Collection) -> Int {
  return c.segments.len();
}

pub fn collection_dimension(c: &Collection) -> Int {
  return schema_dimension(&c.schema);
}