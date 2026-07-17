// XIOM — meshoptimizer Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for meshoptimizer v1.2 (meshoptimizer.h).
// meshoptimizer is a mesh optimization library for rendering engines.
//
// Types: size_t → Int, unsigned int / uint32_t → Int32, float → Float32,
// int → Int32, unsigned char → Int32, void* → Int, unsigned short → Int32.
// float* (out-parameter) → Int (pass 0 for NULL).
// Naming follows the C API verbatim.
//
// COVERAGE: 85 functions (100% of C API) across 24 subsystems:
//   Remapping, Filtering, Shadow Buffers, Index Generation,
//   Cache Optimization, Overdraw, Fetch Optimization,
//   Index/Sequence/Meshlet/Vertex Encoding, Filter Encode/Decode,
//   Simplification, Stripification, Analysis, Meshlet Building,
//   Meshlet Optimization, Bounds, Partitioning, Spatial,
//   Opacity Maps, Tangents, Quantization, Allocator.

module xiom.meshopt

// =========================================================================
// Streaming vertex attribute descriptor
// =========================================================================

pub type MeshoptStream = {
  data: Int;
  size: Int;
  stride: Int;
} derive[Clone]

// =========================================================================
// Simplification option flags
// =========================================================================

pub const MESHOPT_SIMPLIFY_LOCK_BORDER: Int32 = 1 as Int32;
pub const MESHOPT_SIMPLIFY_SPARSE: Int32 = 2 as Int32;
pub const MESHOPT_SIMPLIFY_ERROR_ABSOLUTE: Int32 = 4 as Int32;
pub const MESHOPT_SIMPLIFY_PRUNE: Int32 = 8 as Int32;
pub const MESHOPT_SIMPLIFY_REGULARIZE: Int32 = 16 as Int32;
pub const MESHOPT_SIMPLIFY_PERMISSIVE: Int32 = 32 as Int32;
pub const MESHOPT_SIMPLIFY_REGULARIZE_LIGHT: Int32 = 64 as Int32;

// =========================================================================
// Simplification vertex lock flags
// =========================================================================

pub const MESHOPT_SIMPLIFY_VERTEX_LOCK: Int32 = 1 as Int32;
pub const MESHOPT_SIMPLIFY_VERTEX_PROTECT: Int32 = 2 as Int32;
pub const MESHOPT_SIMPLIFY_VERTEX_PRIORITY: Int32 = 4 as Int32;

// =========================================================================
// EncodeExpMode enum values
// =========================================================================

pub const MESHOPT_ENCODE_EXP_SEPARATE: Int32 = 0 as Int32;
pub const MESHOPT_ENCODE_EXP_SHARED_VECTOR: Int32 = 1 as Int32;
pub const MESHOPT_ENCODE_EXP_SHARED_COMPONENT: Int32 = 2 as Int32;
pub const MESHOPT_ENCODE_EXP_CLAMPED: Int32 = 3 as Int32;

// =========================================================================
// Tangent generation option flags
// =========================================================================

pub const MESHOPT_TANGENT_COMPATIBLE: Int32 = 1 as Int32;
pub const MESHOPT_TANGENT_ZERO_FALLBACK: Int32 = 2 as Int32;

// =========================================================================
// Analysis result structs (returned by value from C)
// =========================================================================

pub type MeshoptVertexCacheStatistics = {
  vertices_transformed: Int32;
  warps_executed: Int32;
  acmr: Float32;
  atvr: Float32;
} derive[Clone]

pub type MeshoptVertexFetchStatistics = {
  bytes_fetched: Int32;
  overfetch: Float32;
} derive[Clone]

pub type MeshoptOverdrawStatistics = {
  pixels_covered: Int32;
  pixels_shaded: Int32;
  overdraw: Float32;
} derive[Clone]

pub type MeshoptCoverageStatistics = {
  coverage0: Float32;
  coverage1: Float32;
  coverage2: Float32;
  extent: Float32;
} derive[Clone]

pub type MeshoptBounds = {
  center0: Float32; center1: Float32; center2: Float32;
  radius: Float32;
  cone_apex0: Float32; cone_apex1: Float32; cone_apex2: Float32;
  cone_axis0: Float32; cone_axis1: Float32; cone_axis2: Float32;
  cone_cutoff: Float32;
  cone_axis_s8_0: Int32;
  cone_axis_s8_1: Int32;
  cone_axis_s8_2: Int32;
  cone_cutoff_s8: Int32;
} derive[Clone]

pub type MeshoptMeshlet = {
  vertex_offset: Int32;
  triangle_offset: Int32;
  vertex_count: Int32;
  triangle_count: Int32;
} derive[Clone]

// =========================================================================
// FFI: extern "C" declarations — full meshoptimizer.h v1.2 API surface
// =========================================================================

extern "C" {
  // Remapping
  fn meshopt_generateVertexRemap(destination: Int, indices: Int, index_count: Int, vertices: Int, vertex_count: Int, vertex_size: Int) -> Int;
  fn meshopt_generateVertexRemapMulti(destination: Int, indices: Int, index_count: Int, vertex_count: Int, streams: Int, stream_count: Int) -> Int;
  fn meshopt_generateVertexRemapCustom(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, callback: Int, context: Int) -> Int;
  fn meshopt_remapVertexBuffer(destination: Int, vertices: Int, vertex_count: Int, vertex_size: Int, remap: Int);
  fn meshopt_remapIndexBuffer(destination: Int, indices: Int, index_count: Int, remap: Int);

  // Filtering (filterIndexBuffer is EXPERIMENTAL)
  fn meshopt_filterIndexBuffer(destination: Int, indices: Int, index_count: Int, vertices: Int, vertex_count: Int, vertex_size: Int, vertex_stride: Int) -> Int;
  fn meshopt_filterIndexBufferMulti(destination: Int, indices: Int, index_count: Int, vertex_count: Int, streams: Int, stream_count: Int) -> Int;

  // Shadow index buffers
  fn meshopt_generateShadowIndexBuffer(destination: Int, indices: Int, index_count: Int, vertices: Int, vertex_count: Int, vertex_size: Int, vertex_stride: Int);
  fn meshopt_generateShadowIndexBufferMulti(destination: Int, indices: Int, index_count: Int, vertex_count: Int, streams: Int, stream_count: Int);
  fn meshopt_generatePositionRemap(destination: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int);

  // Index buffer topology
  fn meshopt_generateAdjacencyIndexBuffer(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int);
  fn meshopt_generateTessellationIndexBuffer(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int);
  fn meshopt_generateProvokingIndexBuffer(destination: Int, reorder: Int, indices: Int, index_count: Int, vertex_count: Int) -> Int;

  // Vertex cache optimization
  fn meshopt_optimizeVertexCache(destination: Int, indices: Int, index_count: Int, vertex_count: Int);
  fn meshopt_optimizeVertexCacheStrip(destination: Int, indices: Int, index_count: Int, vertex_count: Int);
  fn meshopt_optimizeVertexCacheFifo(destination: Int, indices: Int, index_count: Int, vertex_count: Int, cache_size: Int32);

  // Overdraw optimization
  fn meshopt_optimizeOverdraw(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, threshold: Float32);

  // Vertex fetch optimization
  fn meshopt_optimizeVertexFetch(destination: Int, indices: Int, index_count: Int, vertices: Int, vertex_count: Int, vertex_size: Int) -> Int;
  fn meshopt_optimizeVertexFetchRemap(destination: Int, indices: Int, index_count: Int, vertex_count: Int) -> Int;

  // Index encoding
  fn meshopt_encodeIndexBuffer(buffer: Int, buffer_size: Int, indices: Int, index_count: Int) -> Int;
  fn meshopt_encodeIndexBufferBound(index_count: Int, vertex_count: Int) -> Int;
  fn meshopt_encodeIndexVersion(version: Int32);
  fn meshopt_decodeIndexBuffer(destination: Int, index_count: Int, index_size: Int, buffer: Int, buffer_size: Int) -> Int32;
  fn meshopt_decodeIndexVersion(buffer: Int, buffer_size: Int) -> Int32;

  // Index sequence encoding
  fn meshopt_encodeIndexSequence(buffer: Int, buffer_size: Int, indices: Int, index_count: Int) -> Int;
  fn meshopt_encodeIndexSequenceBound(index_count: Int, vertex_count: Int) -> Int;
  fn meshopt_decodeIndexSequence(destination: Int, index_count: Int, index_size: Int, buffer: Int, buffer_size: Int) -> Int32;

  // Meshlet encoding
  fn meshopt_encodeMeshlet(buffer: Int, buffer_size: Int, vertices: Int, vertex_count: Int, triangles: Int, triangle_count: Int) -> Int;
  fn meshopt_encodeMeshletBound(max_vertices: Int, max_triangles: Int) -> Int;
  fn meshopt_decodeMeshlet(vertices: Int, vertex_count: Int, vertex_size: Int, triangles: Int, triangle_count: Int, triangle_size: Int, buffer: Int, buffer_size: Int) -> Int32;
  fn meshopt_decodeMeshletRaw(vertices: Int, vertex_count: Int, triangles: Int, triangle_count: Int, buffer: Int, buffer_size: Int) -> Int32;

  // Vertex encoding
  fn meshopt_encodeVertexBuffer(buffer: Int, buffer_size: Int, vertices: Int, vertex_count: Int, vertex_size: Int) -> Int;
  fn meshopt_encodeVertexBufferBound(vertex_count: Int, vertex_size: Int) -> Int;
  fn meshopt_encodeVertexBufferLevel(buffer: Int, buffer_size: Int, vertices: Int, vertex_count: Int, vertex_size: Int, level: Int32, version: Int32) -> Int;
  fn meshopt_encodeVertexVersion(version: Int32);
  fn meshopt_decodeVertexBuffer(destination: Int, vertex_count: Int, vertex_size: Int, buffer: Int, buffer_size: Int) -> Int32;
  fn meshopt_decodeVertexVersion(buffer: Int, buffer_size: Int) -> Int32;

  // Vertex filter decoders
  fn meshopt_decodeFilterOct(buffer: Int, count: Int, stride: Int);
  fn meshopt_decodeFilterQuat(buffer: Int, count: Int, stride: Int);
  fn meshopt_decodeFilterExp(buffer: Int, count: Int, stride: Int);
  fn meshopt_decodeFilterColor(buffer: Int, count: Int, stride: Int);

  // Vertex filter encoders
  fn meshopt_encodeFilterOct(destination: Int, count: Int, stride: Int, bits: Int32, data: Int);
  fn meshopt_encodeFilterQuat(destination: Int, count: Int, stride: Int, bits: Int32, data: Int);
  fn meshopt_encodeFilterExp(destination: Int, count: Int, stride: Int, bits: Int32, data: Int, mode: Int32);
  fn meshopt_encodeFilterColor(destination: Int, count: Int, stride: Int, bits: Int32, data: Int);

  // Simplification
  fn meshopt_simplify(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, target_index_count: Int, target_error: Float32, options: Int32, result_error: Int) -> Int;
  fn meshopt_simplifyWithAttributes(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, vertex_attributes: Int, vertex_attributes_stride: Int, attribute_weights: Int, attribute_count: Int, vertex_lock: Int, target_index_count: Int, target_error: Float32, options: Int32, result_error: Int) -> Int;
  fn meshopt_simplifyWithUpdate(indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, vertex_attributes: Int, vertex_attributes_stride: Int, attribute_weights: Int, attribute_count: Int, vertex_lock: Int, target_index_count: Int, target_error: Float32, options: Int32, result_error: Int) -> Int;
  fn meshopt_simplifySloppy(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, vertex_lock: Int, target_index_count: Int, target_error: Float32, result_error: Int) -> Int;
  fn meshopt_simplifyPrune(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, target_error: Float32) -> Int;
  fn meshopt_simplifyPoints(destination: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, vertex_colors: Int, vertex_colors_stride: Int, color_weight: Float32, target_vertex_count: Int) -> Int;
  fn meshopt_simplifyScale(vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int) -> Float32;

  // Stripification
  fn meshopt_stripify(destination: Int, indices: Int, index_count: Int, vertex_count: Int, restart_index: Int32) -> Int;
  fn meshopt_stripifyBound(index_count: Int) -> Int;
  fn meshopt_unstripify(destination: Int, indices: Int, index_count: Int, restart_index: Int32) -> Int;
  fn meshopt_unstripifyBound(index_count: Int) -> Int;

  // Analysis
  fn meshopt_analyzeVertexCache(indices: Int, index_count: Int, vertex_count: Int, cache_size: Int32, warp_size: Int32, primgroup_size: Int32) -> MeshoptVertexCacheStatistics;
  fn meshopt_analyzeVertexFetch(indices: Int, index_count: Int, vertex_count: Int, vertex_size: Int) -> MeshoptVertexFetchStatistics;
  fn meshopt_analyzeOverdraw(indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int) -> MeshoptOverdrawStatistics;
  fn meshopt_analyzeCoverage(indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int) -> MeshoptCoverageStatistics;

  // Meshlet building
  fn meshopt_buildMeshlets(meshlets: Int, meshlet_vertices: Int, meshlet_triangles: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, max_vertices: Int, max_triangles: Int, cone_weight: Float32) -> Int;
  fn meshopt_buildMeshletsScan(meshlets: Int, meshlet_vertices: Int, meshlet_triangles: Int, indices: Int, index_count: Int, vertex_count: Int, max_vertices: Int, max_triangles: Int) -> Int;
  fn meshopt_buildMeshletsBound(index_count: Int, max_vertices: Int, max_triangles: Int) -> Int;
  fn meshopt_buildMeshletsFlex(meshlets: Int, meshlet_vertices: Int, meshlet_triangles: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, max_vertices: Int, min_triangles: Int, max_triangles: Int, cone_weight: Float32, split_factor: Float32) -> Int;
  fn meshopt_buildMeshletsSpatial(meshlets: Int, meshlet_vertices: Int, meshlet_triangles: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, max_vertices: Int, min_triangles: Int, max_triangles: Int, fill_weight: Float32) -> Int;

  // Meshlet optimization
  fn meshopt_optimizeMeshlet(meshlet_vertices: Int, meshlet_triangles: Int, triangle_count: Int, vertex_count: Int);
  fn meshopt_optimizeMeshletLevel(meshlet_vertices: Int, vertex_count: Int, meshlet_triangles: Int, triangle_count: Int, level: Int32);

  // Bounds computation
  fn meshopt_computeClusterBounds(indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int) -> MeshoptBounds;
  fn meshopt_computeMeshletBounds(meshlet_vertices: Int, meshlet_triangles: Int, triangle_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int) -> MeshoptBounds;
  fn meshopt_computeSphereBounds(positions: Int, count: Int, positions_stride: Int, radii: Int, radii_stride: Int) -> MeshoptBounds;
  fn meshopt_extractMeshletIndices(vertices: Int, triangles: Int, indices: Int, index_count: Int) -> Int;

  // Partitioning
  fn meshopt_partitionClusters(destination: Int, cluster_indices: Int, total_index_count: Int, cluster_index_counts: Int, cluster_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, target_partition_size: Int) -> Int;

  // Spatial sorting
  fn meshopt_spatialSortRemap(destination: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int);
  fn meshopt_spatialSortTriangles(destination: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int);
  fn meshopt_spatialClusterPoints(destination: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, cluster_size: Int);

  // Opacity micromaps (EXPERIMENTAL)
  fn meshopt_opacityMapMeasure(levels: Int, sources: Int, omm_indices: Int, indices: Int, index_count: Int, vertex_uvs: Int, vertex_count: Int, vertex_uvs_stride: Int, texture_width: Int32, texture_height: Int32, max_level: Int32, target_edge: Float32) -> Int;
  fn meshopt_opacityMapRasterize(result: Int, level: Int32, states: Int32, uv0: Int, uv1: Int, uv2: Int, texture_data: Int, texture_stride: Int, texture_pitch: Int, texture_width: Int32, texture_height: Int32);
  fn meshopt_opacityMapEntrySize(level: Int32, states: Int32) -> Int;
  fn meshopt_opacityMapCompact(data: Int, data_size: Int, levels: Int, offsets: Int, omm_count: Int, omm_indices: Int, triangle_count: Int, states: Int32) -> Int;

  // Tangents (EXPERIMENTAL)
  fn meshopt_generateTangents(result: Int, indices: Int, index_count: Int, vertex_positions: Int, vertex_count: Int, vertex_positions_stride: Int, vertex_normals: Int, vertex_normals_stride: Int, vertex_uvs: Int, vertex_uvs_stride: Int, options: Int32);

  // Quantization
  fn meshopt_quantizeHalf(v: Float32) -> Int32;
  fn meshopt_quantizeFloat(v: Float32, N: Int32) -> Float32;
  fn meshopt_dequantizeHalf(h: Int32) -> Float32;
  fn meshopt_computePositionExponent(minv: Int, maxv: Int, min_exp: Int32, max_bits: Int32) -> Int32;

  // Allocator
  fn meshopt_setAllocator(allocate: Int, deallocate: Int);
}

// =========================================================================
// Safe wrapper functions — for direct procedural use
// =========================================================================

pub fn generate_vertex_remap(vertices_ptr: Int, vertex_count: Int, vertex_size: Int) -> Result[Int, Str]
  requires: vertices_ptr != 0
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  let remap_ptr: Int = 0;
  let unique_count: Int = unsafe { meshopt_generateVertexRemap(remap_ptr, 0, 0, vertices_ptr, vertex_count, vertex_size) };
  if unique_count == 0 { return Err("meshopt_generateVertexRemap returned 0 vertices"); }
  return Ok(unique_count);
}

pub fn optimize_vertex_cache(dest_ptr: Int, indices_ptr: Int, index_count: Int, vertex_count: Int)
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  unsafe { meshopt_optimizeVertexCache(dest_ptr, indices_ptr, index_count, vertex_count); }
}

pub fn simplify(dest_ptr: Int, indices_ptr: Int, index_count: Int, pos_ptr: Int, vertex_count: Int, pos_stride: Int, target_count: Int, target_error: Float32) -> Result[Int, Str]
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: pos_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
  requires: target_count > 0
{
  let new_count: Int = unsafe { meshopt_simplify(dest_ptr, indices_ptr, index_count, pos_ptr, vertex_count, pos_stride, target_count, target_error, 0 as Int32, 0) };
  return Ok(new_count);
}

pub fn simplify_scale(pos_ptr: Int, vertex_count: Int, pos_stride: Int) -> Float32
  requires: pos_ptr != 0
  requires: vertex_count > 0
  requires: pos_stride > 0
{
  return unsafe { meshopt_simplifyScale(pos_ptr, vertex_count, pos_stride) };
}

pub fn stripify(dest_ptr: Int, indices_ptr: Int, index_count: Int, vertex_count: Int, restart_index: Int32) -> Int
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: index_count > 0
{
  return unsafe { meshopt_stripify(dest_ptr, indices_ptr, index_count, vertex_count, restart_index) };
}

pub fn analyze_vertex_cache(indices_ptr: Int, index_count: Int, vertex_count: Int, cache_size: Int32, warp_size: Int32, primgroup_size: Int32) -> MeshoptVertexCacheStatistics
  requires: indices_ptr != 0
  requires: index_count > 0
{
  return unsafe { meshopt_analyzeVertexCache(indices_ptr, index_count, vertex_count, cache_size, warp_size, primgroup_size) };
}
