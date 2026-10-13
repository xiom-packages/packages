// XIOM -- meshoptimizer Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe wrappers for meshoptimizer v1.2.
// Uses the pub wrappers exported by `xiom.meshopt` (extern "C" names are
// module-private on the pin, so FFI stays confined to meshopt.xi -- G5);
// this module carries no `unsafe` blocks.
// Provides typed pipeline wrappers for common optimization workflows.
//
// Module name note: a dotted child (`xiom.meshopt.safe`) cannot import its
// parent on the pin (B-04: child -> parent imports do not resolve), so the
// module uses the flat sibling namespace `xiom.meshopt_safe`.
//
// COVERAGE: 5 pipeline types:
//   RemapPipeline, OptimizePipeline, SimplifyPipeline,
//   EncodePipeline, StripPipeline

module xiom.meshopt_safe

use xiom.meshopt;

// =========================================================================
// MeshoptError
// =========================================================================

pub type MeshoptError = {
  code: Int32;
  message: Str;
} derive[Clone]

// =========================================================================
// RemapPipeline -- deduplicate vertices and rebuild buffers
// =========================================================================

pub type RemapPipeline = {
  remap: Vec[UInt8];
  unique_count: Int;
  vertex_ptr: Int;
  vertex_count: Int;
  vertex_size: Int;
} derive[Clone]

/// Build the dedup remap for a vertex buffer (indices = identity over the
/// vertex range).  The remap table is XIOM-owned and kept alive in the
/// pipeline; `remap_indices` rewrites an index buffer through it.
/// Complexity: O(vertices).
pub fn RemapPipeline.build(vertices_ptr: Int, vertex_count: Int, vertex_size: Int) -> Result[RemapPipeline, MeshoptError]
  requires: vertices_ptr != 0
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  var remap: Vec[UInt8] = meshopt.byte_slot(vertex_count * 4);
  let unique: Int = meshopt.generate_vertex_remap_into(remap.as_mut_ptr() as Int, vertices_ptr, vertex_count, vertex_size);
  if unique == 0 { return Err(MeshoptError{ code: 1 as Int32, message: "no unique vertices" }); }
  return Ok(RemapPipeline{ remap: remap, unique_count: unique, vertex_ptr: vertices_ptr, vertex_count: vertex_count, vertex_size: vertex_size });
}

pub fn RemapPipeline.remap_vertices(dest_vertices: Int)
  requires: remap.len() > 0
  requires: dest_vertices != 0
  requires: vertex_ptr != 0
{
  meshopt.remap_vertex_buffer(dest_vertices, vertex_ptr, vertex_count, vertex_size, remap.as_ptr() as Int);
}

pub fn RemapPipeline.remap_indices(dest_indices: Int, src_indices: Int, index_count: Int)
  requires: remap.len() > 0
  requires: dest_indices != 0
  requires: src_indices != 0
  requires: index_count > 0
{
  meshopt.remap_index_buffer(dest_indices, src_indices, index_count, remap.as_ptr() as Int);
}

// =========================================================================
// OptimizePipeline -- vertex cache, overdraw, and fetch optimization
// =========================================================================

pub type OptimizePipeline = {
  vertex_count: Int;
  index_count: Int;
} derive[Clone]

pub fn OptimizePipeline.init(vertex_count: Int, index_count: Int) -> OptimizePipeline
  requires: vertex_count > 0
  requires: index_count > 0
{
  return OptimizePipeline{ vertex_count: vertex_count, index_count: index_count };
}

pub fn OptimizePipeline.vertex_cache(dest_indices: Int, src_indices: Int)
  requires: dest_indices != 0
  requires: src_indices != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  meshopt.optimize_vertex_cache(dest_indices, src_indices, index_count, vertex_count);
}

pub fn OptimizePipeline.vertex_cache_fifo(dest_indices: Int, src_indices: Int, cache_size: Int32)
  requires: dest_indices != 0
  requires: src_indices != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  meshopt.optimize_vertex_cache_fifo(dest_indices, src_indices, index_count, vertex_count, cache_size);
}

pub fn OptimizePipeline.overdraw(dest_indices: Int, cache_optimized_indices: Int, pos_ptr: Int, pos_stride: Int, threshold: Float32)
  requires: dest_indices != 0
  requires: cache_optimized_indices != 0
  requires: pos_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  meshopt.optimize_overdraw(dest_indices, cache_optimized_indices, index_count, pos_ptr, vertex_count, pos_stride, threshold);
}

pub fn OptimizePipeline.vertex_fetch(dest_vertices: Int, indices_inout: Int, src_vertices: Int, vertex_size: Int) -> Result[Int, MeshoptError]
  requires: dest_vertices != 0
  requires: indices_inout != 0
  requires: src_vertices != 0
  requires: vertex_size > 0
{
  let result: Int = meshopt.optimize_vertex_fetch(dest_vertices, indices_inout, index_count, src_vertices, vertex_count, vertex_size);
  if result == 0 { return Err(MeshoptError{ code: 2 as Int32, message: "vertex fetch optimization failed" }); }
  return Ok(result);
}

pub fn OptimizePipeline.vertex_fetch_remap(dest_remap: Int, indices_ptr: Int) -> Result[Int, MeshoptError]
  requires: dest_remap != 0
  requires: indices_ptr != 0
{
  let result: Int = meshopt.optimize_vertex_fetch_remap(dest_remap, indices_ptr, index_count, vertex_count);
  if result == 0 { return Err(MeshoptError{ code: 2 as Int32, message: "vertex fetch remap failed" }); }
  return Ok(result);
}

pub fn OptimizePipeline.analyze_vertex_cache(indices_ptr: Int, cache_size: Int32, warp_size: Int32, primgroup_size: Int32) -> MeshoptVertexCacheStatistics
  requires: indices_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  return meshopt.analyze_vertex_cache(indices_ptr, index_count, vertex_count, cache_size, warp_size, primgroup_size);
}

pub fn OptimizePipeline.analyze_vertex_fetch(indices_ptr: Int, vertex_size: Int) -> MeshoptVertexFetchStatistics
  requires: indices_ptr != 0
  requires: vertex_size > 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  return meshopt.analyze_vertex_fetch(indices_ptr, index_count, vertex_count, vertex_size);
}

// =========================================================================
// SimplifyPipeline -- mesh simplification with error measurement
// =========================================================================

pub type SimplifyPipeline = {
  index_count: Int;
  vertex_count: Int;
  pos_ptr: Int;
  pos_stride: Int;
} derive[Clone]

pub fn SimplifyPipeline.init(indices_ptr: Int, index_count: Int, pos_ptr: Int, vertex_count: Int, pos_stride: Int) -> SimplifyPipeline
  requires: indices_ptr != 0
  requires: index_count > 0
  requires: pos_ptr != 0
  requires: vertex_count > 0
{
  return SimplifyPipeline{ index_count: index_count, vertex_count: vertex_count, pos_ptr: pos_ptr, pos_stride: pos_stride };
}

pub fn SimplifyPipeline.scale() -> Float32
  requires: pos_ptr != 0
  requires: vertex_count > 0
  requires: pos_stride > 0
{
  return meshopt.simplify_scale(pos_ptr, vertex_count, pos_stride);
}

pub fn SimplifyPipeline.run(dest_ptr: Int, indices_ptr: Int, target_index_count: Int, target_error: Float32, options: Int32) -> Result[Int, MeshoptError]
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: target_index_count > 0
  requires: target_index_count <= index_count
  requires: pos_ptr != 0
{
  let new_count: Int = meshopt.simplify_with_options(dest_ptr, indices_ptr, index_count, pos_ptr, vertex_count, pos_stride, target_index_count, target_error, options);
  if new_count == 0 { return Err(MeshoptError{ code: 3 as Int32, message: "simplification produced no indices" }); }
  return Ok(new_count);
}

// =========================================================================
// EncodePipeline -- index/vertex buffer compression
// =========================================================================

pub type EncodePipeline = { } derive[Clone]

pub fn EncodePipeline.index_bound(index_count: Int, vertex_count: Int) -> Int
  requires: index_count > 0
{
  return meshopt.encode_index_bound(index_count, vertex_count);
}

pub fn EncodePipeline.encode_indices(buffer_ptr: Int, buffer_size: Int, indices_ptr: Int, index_count: Int) -> Result[Int, MeshoptError]
  requires: buffer_ptr != 0
  requires: indices_ptr != 0
  requires: index_count > 0
{
  let result: Int = meshopt.encode_indices_raw(buffer_ptr, buffer_size, indices_ptr, index_count);
  if result == 0 { return Err(MeshoptError{ code: 4 as Int32, message: "index buffer encoding failed (buffer too small)" }); }
  return Ok(result);
}

pub fn EncodePipeline.vertex_bound(vertex_count: Int, vertex_size: Int) -> Int
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  return meshopt.encode_vertices_bound(vertex_count, vertex_size);
}

pub fn EncodePipeline.encode_vertices(buffer_ptr: Int, buffer_size: Int, vertices_ptr: Int, vertex_count: Int, vertex_size: Int) -> Result[Int, MeshoptError]
  requires: buffer_ptr != 0
  requires: vertices_ptr != 0
  requires: vertex_count > 0
{
  let result: Int = meshopt.encode_vertices_raw(buffer_ptr, buffer_size, vertices_ptr, vertex_count, vertex_size);
  if result == 0 { return Err(MeshoptError{ code: 4 as Int32, message: "vertex buffer encoding failed (buffer too small)" }); }
  return Ok(result);
}

pub fn EncodePipeline.decode_vertices(dest_ptr: Int, vertex_count: Int, vertex_size: Int, buffer_ptr: Int, buffer_size: Int) -> Result[Int, MeshoptError]
  requires: dest_ptr != 0
  requires: buffer_ptr != 0
  requires: vertex_count > 0
{
  let res: Int32 = meshopt.decode_vertex_buffer(dest_ptr, vertex_count, vertex_size, buffer_ptr, buffer_size);
  if res != 0 { return Err(MeshoptError{ code: res, message: "vertex decode failed" }); }
  return Ok(0);
}

pub fn EncodePipeline.decode_indices(dest_ptr: Int, index_count: Int, index_size: Int, buffer_ptr: Int, buffer_size: Int) -> Result[Int, MeshoptError]
  requires: dest_ptr != 0
  requires: buffer_ptr != 0
  requires: index_count > 0
{
  let res: Int32 = meshopt.decode_index_buffer(dest_ptr, index_count, index_size, buffer_ptr, buffer_size);
  if res != 0 { return Err(MeshoptError{ code: res, message: "index decode failed" }); }
  return Ok(0);
}

// =========================================================================
// StripPipeline -- triangle strip conversion
// =========================================================================

pub type StripPipeline = {
  index_count: Int;
  vertex_count: Int;
} derive[Clone]

pub fn StripPipeline.init(index_count: Int, vertex_count: Int) -> StripPipeline
  requires: index_count > 0
  requires: vertex_count > 0
{
  return StripPipeline{ index_count: index_count, vertex_count: vertex_count };
}

pub fn StripPipeline.bound() -> Int
  requires: index_count > 0
{
  return meshopt.stripify_bound(index_count);
}

pub fn StripPipeline.stripify(dest_ptr: Int, indices_ptr: Int, restart_index: Int32) -> Result[Int, MeshoptError]
  requires: dest_ptr != 0
  requires: indices_ptr != 0
{
  let result: Int = meshopt.stripify(dest_ptr, indices_ptr, index_count, vertex_count, restart_index);
  if result == 0 { return Err(MeshoptError{ code: 5 as Int32, message: "stripification produced no output" }); }
  return Ok(result);
}
