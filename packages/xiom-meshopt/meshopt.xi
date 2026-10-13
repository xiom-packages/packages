// XIOM -- meshoptimizer Bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for meshoptimizer v1.2 (meshoptimizer.h).
// meshoptimizer is a mesh optimization library for rendering engines.
//
// Types: size_t -> Int, unsigned int / uint32_t -> Int32, float -> Float32,
// int -> Int32, unsigned char -> Int32, void* -> Int, unsigned short -> Int32.
// float* (out-parameter) -> Int (pass 0 for NULL).
// Naming follows the C API verbatim.
//
// COVERAGE: 85 functions (100% of C API) across 24 subsystems:
//   Remapping, Filtering, Shadow Buffers, Index Generation,
//   Cache Optimization, Overdraw, Fetch Optimization,
//   Index/Sequence/Meshlet/Vertex Encoding, Filter Encode/Decode,
//   Simplification, Stripification, Analysis, Meshlet Building,
//   Meshlet Optimization, Bounds, Partitioning, Spatial,
//   Opacity Maps, Tangents, Quantization, Allocator.
//
// 0.2.0 (pool drive): upstream sources are vendored in vendor/src
// (v1.2, commit f843aae0) and compiled with the suite via port.args.json.
// The `xmo_*` block at the bottom exposes real runtime probes over the
// vendored build (SPEC.md); the raw declarations remain the 100%-coverage
// surface.  ABI-sensitive shapes (fp returns through casts, struct-by-value
// returns) go through the bridge; probes never read through foreign
// pointers (B-20 -- C copies into XIOM-owned slots read byte-indexed).
//
// 0.5.0: `extern "C"` names are module-private on the pin, so the sibling
// modules (xiom.meshopt_safe, xiom.meshopt_cooked -- flat sibling names,
// because a dotted child cannot import its parent on the pin, B-04) reach
// the C surface through the thin pub wrappers at the bottom; FFI stays
// confined to this module (G5).  The cooked-mesh container "XMC1"
// (SPEC.md section 4) wraps the EncodePipeline streams behind an
// owned-bytes writer/reader.

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
// FFI: extern "C" declarations -- full meshoptimizer.h v1.2 API surface
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
// Safe wrapper functions -- for direct procedural use
// =========================================================================

pub fn generate_vertex_remap(vertices_ptr: Int, vertex_count: Int, vertex_size: Int) -> Result[Int, Str]
  requires: vertices_ptr != 0
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  // Upstream memsets the destination unconditionally, so the old
  // destination=0 call was an access violation; the mapping is written into
  // an owned scratch slot and only the unique count is returned.
  var scratch: Vec[UInt8] = byte_slot(vertex_count * 4);
  let unique_count: Int = unsafe { meshopt_generateVertexRemap(scratch.as_mut_ptr() as Int, 0, vertex_count, vertices_ptr, vertex_count, vertex_size) };
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

// =========================================================================
// 0.2.0: vendored runtime probes (src/meshopt_bridge.cpp)
// =========================================================================
//
// The vendored tree (vendor/src) is compiled with the suite via
// port.args.json.  These wrappers run real meshes through the library:
// out-params are 4-byte XIOM-owned slots read little-endian (B-11/B-16/B-17),
// meshes are either built inside the bridge or copied by C into an
// XIOM-owned byte slot (B-20 -- never read through a foreign pointer).

extern "C" {
  fn xmo_version() -> Int32;
  fn xmo_remap_probe(unique: *UInt8, valid: *UInt8) -> Int32;
  fn xmo_cache_probe(acmr_before_milli: *UInt8, acmr_after_milli: *UInt8, transformed_before: *UInt8, transformed_after: *UInt8) -> Int32;
  fn xmo_fetch_probe(bytes_fetched: *UInt8, overfetch_milli: *UInt8) -> Int32;
  fn xmo_simplify_probe(out_count: *UInt8, err_milli: *UInt8) -> Int32;
  fn xmo_encode_index_probe(enc_size: *UInt8, dec_rc: *UInt8, equal: *UInt8) -> Int32;
  fn xmo_vertex_codec_probe(enc_size: *UInt8, dec_rc: *UInt8, equal: *UInt8) -> Int32;
  fn xmo_strip_probe(strip_count: *UInt8, unstrip_triangles: *UInt8, set_equal: *UInt8) -> Int32;
  fn xmo_quant_probe(half_one: *UInt8, half_neg_two: *UInt8, back_one_milli: *UInt8) -> Int32;
  fn xmo_bounds_probe(radius_milli: *UInt8, center_x_milli: *UInt8, center_y_milli: *UInt8) -> Int32;
  fn xmo_meshlet_probe(meshlet_count: *UInt8, triangle_sum: *UInt8, input_triangles: *UInt8) -> Int32;
  fn xmo_filter_probe(max_err_milli: *UInt8) -> Int32;
  fn xmo_build_indices(dst: *UInt8, capacity: Int32) -> Int32;
  fn xmo_optimize_inplace(buf: *UInt8, index_count: Int32, vertex_count: Int32) -> Int32;
  fn xmo_checksum(buf: *UInt8, byte_count: Int32) -> Int32;
  fn xmo_fill_grid(positions: *UInt8, positions_capacity: Int32, indices: *UInt8, indices_capacity: Int32, w: Int32, h: Int32, zscale_milli: Int32) -> Int32;
  fn xmo_remap_bytes(vertices: *UInt8, vertex_count: Int32, vertex_size: Int32, indices: *UInt8, index_count: Int32, out_vertices: *UInt8, out_capacity: Int32, out_unique: *UInt8) -> Int32;
  fn xmo_optimize_bytes(indices: *UInt8, index_count: Int32, vertex_count: Int32) -> Int32;
  fn xmo_simplify_bytes(vertices: *UInt8, vertex_count: Int32, vertex_stride: Int32, indices: *UInt8, index_count: Int32, target_index_count: Int32, target_error_milli: Int32, out_indices: *UInt8, out_capacity: Int32, out_count: *UInt8, out_err_milli: *UInt8) -> Int32;
  fn xmo_index_sequence_probe(out_size: *UInt8, out_rc: *UInt8, out_equal: *UInt8) -> Int32;
  fn xmo_filter_quat_probe(out_max_err_micro: *UInt8) -> Int32;
  fn xmo_filter_exp_probe(out_max_err_micro: *UInt8) -> Int32;
  fn xmo_filter_color_probe(out_max_err_micro: *UInt8) -> Int32;
  fn xmo_meshlet_codec_probe(out_vertex_count: *UInt8, out_triangle_count: *UInt8, out_size: *UInt8, out_rc: *UInt8, out_equal: *UInt8) -> Int32;
}

/// n zero bytes in an XIOM-owned slot (owned out-param / staging buffers).
/// Complexity: O(n).
pub fn byte_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn xmo_slot4() -> Vec[UInt8]
  requires: true
{
  return byte_slot(4);
}

fn xmo_read_u32(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn xmo_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}

pub type MeshoptRemapProbe = {
  unique: Int;
  valid: Bool;
}

pub type MeshoptCacheProbe = {
  acmr_before_milli: Int;
  acmr_after_milli: Int;
  transformed_before: Int;
  transformed_after: Int;
}

pub type MeshoptFetchProbe = {
  bytes_fetched: Int;
  overfetch_milli: Int;
}

pub type MeshoptSimplifyProbe = {
  out_count: Int;
  err_milli: Int;
}

pub type MeshoptCodecProbe = {
  enc_size: Int;
  dec_rc: Int;
  equal: Bool;
}

pub type MeshoptStripProbe = {
  strip_count: Int;
  unstrip_triangles: Int;
  set_equal: Bool;
}

pub type MeshoptQuantProbe = {
  half_one: Int;
  half_neg_two: Int;
  back_one_milli: Int;
}

pub type MeshoptSphereProbe = {
  radius_milli: Int;
  center_x_milli: Int;
  center_y_milli: Int;
}

pub type MeshoptMeshletProbe = {
  meshlet_count: Int;
  triangle_sum: Int;
  input_triangles: Int;
}

/// Probe grid: 8x8 vertices, 98 triangles, 294 indices, 1176 bytes.
pub const MESHOPT_PROBE_INDEX_COUNT: Int = 294;
pub const MESHOPT_PROBE_VERTEX_COUNT: Int = 64;
pub const MESHOPT_PROBE_INDEX_BYTES: Int = 1176;

/// Packed MESHOPTIMIZER_VERSION (major*1000 + minor*10 + patch).
/// v1.2 -> 1020.  Complexity: O(1).
pub fn meshopt_version() -> Int
  requires: true
{
  return unsafe { xmo_version() as Int };
}

/// Remap the duplicated-corner quad: 6 vertices -> 4 unique, mapped
/// indices valid.  Complexity: O(vertices).
pub fn meshopt_remap_probe() -> MeshoptRemapProbe
  requires: true
{
  unsafe {
    var su = xmo_slot4();
    var sv = xmo_slot4();
    xmo_remap_probe(su.as_mut_ptr(), sv.as_mut_ptr());
    return MeshoptRemapProbe{
      unique: xmo_read_u32(&su),
      valid: xmo_read_u32(&sv) != 0
    };
  }
}

/// ACMR (x1000) and transformed-vertex counts before/after
/// optimizeVertexCache on the deliberately scrambled probe grid.
/// Complexity: O(triangles).
pub fn meshopt_cache_probe() -> MeshoptCacheProbe
  requires: true
{
  unsafe {
    var sa = xmo_slot4();
    var sb = xmo_slot4();
    var sc = xmo_slot4();
    var sd = xmo_slot4();
    xmo_cache_probe(sa.as_mut_ptr(), sb.as_mut_ptr(), sc.as_mut_ptr(), sd.as_mut_ptr());
    return MeshoptCacheProbe{
      acmr_before_milli: xmo_read_u32(&sa),
      acmr_after_milli: xmo_read_u32(&sb),
      transformed_before: xmo_read_u32(&sc),
      transformed_after: xmo_read_u32(&sd)
    };
  }
}

/// analyzeVertexFetch on the cache-optimized probe grid (12-byte vertices).
/// Complexity: O(triangles).
pub fn meshopt_fetch_probe() -> MeshoptFetchProbe
  requires: true
{
  unsafe {
    var sb = xmo_slot4();
    var so = xmo_slot4();
    xmo_fetch_probe(sb.as_mut_ptr(), so.as_mut_ptr());
    return MeshoptFetchProbe{
      bytes_fetched: xmo_read_u32(&sb),
      overfetch_milli: xmo_read_u32(&so)
    };
  }
}

/// Simplify the 11x11 bumpy grid (600 indices) toward 100 indices at a 5%
/// relative error budget.  Complexity: O(n log n).
pub fn meshopt_simplify_probe() -> MeshoptSimplifyProbe
  requires: true
{
  unsafe {
    var sc = xmo_slot4();
    var se = xmo_slot4();
    xmo_simplify_probe(sc.as_mut_ptr(), se.as_mut_ptr());
    return MeshoptSimplifyProbe{
      out_count: xmo_read_u32(&sc),
      err_milli: xmo_read_u32(&se)
    };
  }
}

/// Index codec round trip on the probe grid (encode -> decode -> rotation-
/// invariant triangle-set compare; upstream rotates corners by design).
/// Complexity: O(triangles).
pub fn meshopt_index_codec_probe() -> MeshoptCodecProbe
  requires: true
{
  unsafe {
    var ss = xmo_slot4();
    var sr = xmo_slot4();
    var se = xmo_slot4();
    xmo_encode_index_probe(ss.as_mut_ptr(), sr.as_mut_ptr(), se.as_mut_ptr());
    return MeshoptCodecProbe{
      enc_size: xmo_read_u32(&ss),
      dec_rc: xmo_read_u32(&sr),
      equal: xmo_read_u32(&se) != 0
    };
  }
}

/// Vertex codec round trip on the 64-vertex float3 grid.  Complexity: O(n).
pub fn meshopt_vertex_codec_probe() -> MeshoptCodecProbe
  requires: true
{
  unsafe {
    var ss = xmo_slot4();
    var sr = xmo_slot4();
    var se = xmo_slot4();
    xmo_vertex_codec_probe(ss.as_mut_ptr(), sr.as_mut_ptr(), se.as_mut_ptr());
    return MeshoptCodecProbe{
      enc_size: xmo_read_u32(&ss),
      dec_rc: xmo_read_u32(&sr),
      equal: xmo_read_u32(&se) != 0
    };
  }
}

/// stripify -> unstripify over the cache-optimized grid with an order-
/// insensitive triangle-set check.  Complexity: O(triangles).
pub fn meshopt_strip_probe() -> MeshoptStripProbe
  requires: true
{
  unsafe {
    var ss = xmo_slot4();
    var su = xmo_slot4();
    var se = xmo_slot4();
    xmo_strip_probe(ss.as_mut_ptr(), su.as_mut_ptr(), se.as_mut_ptr());
    return MeshoptStripProbe{
      strip_count: xmo_read_u32(&ss),
      unstrip_triangles: xmo_read_u32(&su),
      set_equal: xmo_read_u32(&se) != 0
    };
  }
}

/// fp16 quantize/dequantize spot checks (1.0 -> 0x3C00, -2.0 -> 0xC000).
/// Complexity: O(1).
pub fn meshopt_quant_probe() -> MeshoptQuantProbe
  requires: true
{
  unsafe {
    var sh = xmo_slot4();
    var sn = xmo_slot4();
    var sb = xmo_slot4();
    xmo_quant_probe(sh.as_mut_ptr(), sn.as_mut_ptr(), sb.as_mut_ptr());
    return MeshoptQuantProbe{
      half_one: xmo_read_u32(&sh),
      half_neg_two: xmo_read_u32(&sn),
      back_one_milli: xmo_read_u32(&sb)
    };
  }
}

/// Sphere bounds of the (0,0,0)-(2,0,0)-(0,2,0)-(0,0,2) tetra; radius and
/// center in milli-units.  Complexity: O(points).
pub fn meshopt_sphere_bounds_probe() -> MeshoptSphereProbe
  requires: true
{
  unsafe {
    var sr = xmo_slot4();
    var sx = xmo_slot4();
    var sy = xmo_slot4();
    xmo_bounds_probe(sr.as_mut_ptr(), sx.as_mut_ptr(), sy.as_mut_ptr());
    return MeshoptSphereProbe{
      radius_milli: xmo_read_u32(&sr),
      center_x_milli: xmo_read_u32(&sx),
      center_y_milli: xmo_read_u32(&sy)
    };
  }
}

/// buildMeshlets over the probe grid (max 64 vertices / 64 triangles per
/// meshlet); triangle_sum must conserve the 98 input triangles.
/// Complexity: O(triangles).
pub fn meshopt_meshlet_probe() -> MeshoptMeshletProbe
  requires: true
{
  unsafe {
    var sm = xmo_slot4();
    var st = xmo_slot4();
    var si = xmo_slot4();
    xmo_meshlet_probe(sm.as_mut_ptr(), st.as_mut_ptr(), si.as_mut_ptr());
    return MeshoptMeshletProbe{
      meshlet_count: xmo_read_u32(&sm),
      triangle_sum: xmo_read_u32(&st),
      input_triangles: xmo_read_u32(&si)
    };
  }
}

/// Max reconstruction error (x1000) of an 8-bit octahedral normal round
/// trip.  Complexity: O(1).
pub fn meshopt_oct_filter_probe() -> Int
  requires: true
{
  unsafe {
    var se = xmo_slot4();
    xmo_filter_probe(se.as_mut_ptr());
    return xmo_read_u32(&se);
  }
}

/// C writes the 294-index scrambled probe grid into an XIOM-owned byte slot
/// (C -> owned copy; the B-20-safe direction).  Returns the index count.
/// Complexity: O(indices).
pub fn meshopt_probe_build_indices(buf: &mut Vec[UInt8]) -> Int
  requires: buf.len() >= MESHOPT_PROBE_INDEX_BYTES
{
  return unsafe { xmo_build_indices(buf.as_mut_ptr(), MESHOPT_PROBE_INDEX_BYTES as Int32) as Int };
}

/// Optimize the XIOM-owned index buffer in place; the bridge verifies the
/// triangle multiset is preserved before copying the result back.
/// Complexity: O(triangles).
pub fn meshopt_probe_optimize_inplace(buf: &mut Vec[UInt8]) -> Bool
  requires: buf.len() >= MESHOPT_PROBE_INDEX_BYTES
{
  return unsafe { (xmo_optimize_inplace(buf.as_mut_ptr(), MESHOPT_PROBE_INDEX_COUNT as Int32, MESHOPT_PROBE_VERTEX_COUNT as Int32) as Int) != 0 };
}

/// FNV-1a checksum over an XIOM-owned buffer (order-change evidence for the
/// in-place optimization).  Complexity: O(bytes).
pub fn meshopt_probe_checksum(buf: &mut Vec[UInt8]) -> Int
  requires: buf.len() > 0
{
  return unsafe { xmo_checksum(buf.as_mut_ptr(), buf.len() as Int32) as Int };
}

// =========================================================================
// 0.3.0: owned-buffer wrappers (ROADMAP Phase 3 item 1)
// =========================================================================
//
// Consumer-facing shapes over the probe trio: the caller owns byte buffers
// (f32 positions stride 12, u32 indices), C reads the inputs and writes
// results back into XIOM-owned outputs (the B-20-safe direction); the XIOM
// side reads results back byte-indexed.

pub type MeshoptSimplifyResult = {
  index_count: Int;
  error_milli: Int;
}

/// Fill an owned byte mesh fixture: f32 positions (stride 12, z bump scaled
/// by zscale_milli) plus u32 indices in reversed triangle order (cache-
/// hostile).  Returns the index count (0 on bad args/capacity).
/// Complexity: O(w*h).
pub fn meshopt_fill_grid(w: Int, h: Int, zscale_milli: Int, positions: &mut Vec[UInt8], indices: &mut Vec[UInt8]) -> Int
  requires: w >= 2
  requires: h >= 2
  requires: positions.len() >= w * h * 12
  requires: indices.len() >= (w - 1) * (h - 1) * 24
{
  return unsafe {
    xmo_fill_grid(positions.as_mut_ptr(), positions.len() as Int32, indices.as_mut_ptr(), indices.len() as Int32, w as Int32, h as Int32, zscale_milli as Int32) as Int
  };
}

/// Merge byte-identical vertices (within vertex_size bytes): indices are
/// rewritten in place (u32) and the remapped vertices are copied into
/// `out_vertices` when it is large enough.  Ok(unique_vertex_count).
/// Complexity: O(vertices + indices).
pub fn meshopt_remap_mesh(vertices: &mut Vec[UInt8], vertex_count: Int, vertex_size: Int, indices: &mut Vec[UInt8], index_count: Int, out_vertices: &mut Vec[UInt8]) -> Result[Int, Str]
  requires: vertex_count > 0
  requires: vertex_size > 0
  requires: index_count > 0
  requires: vertices.len() >= vertex_count * vertex_size
  requires: indices.len() >= index_count * 4
{
  unsafe {
    var fu = xmo_slot4();
    let rc = xmo_remap_bytes(vertices.as_mut_ptr(), vertex_count as Int32, vertex_size as Int32, indices.as_mut_ptr(), index_count as Int32, out_vertices.as_mut_ptr(), out_vertices.len() as Int32, fu.as_mut_ptr()) as Int;
    if rc != 0 { return Err("meshopt: remap rc=" + xmo_i2s(rc)); }
    return Ok(xmo_read_u32(&fu));
  }
}

/// Cache-optimize a u32 index buffer in place; the bridge verifies the
/// triangle multiset is preserved before writing the result back.
/// Complexity: O(triangles).
pub fn meshopt_optimize_mesh(indices: &mut Vec[UInt8], index_count: Int, vertex_count: Int) -> Bool
  requires: index_count > 0
  requires: vertex_count > 0
  requires: indices.len() >= index_count * 4
{
  return unsafe { (xmo_optimize_bytes(indices.as_mut_ptr(), index_count as Int32, vertex_count as Int32) as Int) != 0 };
}

/// Simplify an indexed byte mesh (f32 positions, u32 indices) toward
/// target_index_count at a relative target error (milli); the result index
/// list is written into `out_indices` when it fits.  Ok carries the new
/// index count and the relative error (milli).
/// Complexity: O(n log n).
pub fn meshopt_simplify_mesh(vertices: &mut Vec[UInt8], vertex_count: Int, vertex_stride: Int, indices: &mut Vec[UInt8], index_count: Int, target_index_count: Int, target_error_milli: Int, out_indices: &mut Vec[UInt8]) -> Result[MeshoptSimplifyResult, Str]
  requires: vertex_count > 0
  requires: vertex_stride > 0
  requires: index_count > 0
  requires: target_index_count > 0
  requires: vertices.len() >= vertex_count * vertex_stride
  requires: indices.len() >= index_count * 4
{
  unsafe {
    var fc = xmo_slot4();
    var fe = xmo_slot4();
    let rc = xmo_simplify_bytes(vertices.as_mut_ptr(), vertex_count as Int32, vertex_stride as Int32, indices.as_mut_ptr(), index_count as Int32, target_index_count as Int32, target_error_milli as Int32, out_indices.as_mut_ptr(), out_indices.len() as Int32, fc.as_mut_ptr(), fe.as_mut_ptr()) as Int;
    if rc != 0 { return Err("meshopt: simplify rc=" + xmo_i2s(rc)); }
    return Ok(MeshoptSimplifyResult{
      index_count: xmo_read_u32(&fc),
      error_milli: xmo_read_u32(&fe)
    });
  }
}

// =========================================================================
// 0.4.0: codec-family probes (ROADMAP Phase 3 item 2)
// =========================================================================

pub type MeshoptMeshletCodec = {
  vertex_count: Int;
  triangle_count: Int;
  enc_size: Int;
  dec_rc: Int;
  equal: Bool;
}

/// Index SEQUENCE codec round trip over the reversed 294-index grid:
/// arbitrary topology, order preserved byte-exactly (unlike the triangle-
/// list codec, which rotates corners).  Complexity: O(indices).
pub fn meshopt_index_sequence_probe() -> Result[MeshoptCodecProbe, Str]
  requires: true
{
  unsafe {
    var ss = xmo_slot4();
    var sr = xmo_slot4();
    var se = xmo_slot4();
    let rc = xmo_index_sequence_probe(ss.as_mut_ptr(), sr.as_mut_ptr(), se.as_mut_ptr()) as Int;
    if rc != 0 { return Err("meshopt: index sequence probe rc=" + xmo_i2s(rc)); }
    return Ok(MeshoptCodecProbe{
      enc_size: xmo_read_u32(&ss),
      dec_rc: xmo_read_u32(&sr),
      equal: xmo_read_u32(&se) != 0
    });
  }
}

/// Quat filter round trip (90-degree rotation about Z, 16-bit); returns the
/// max component error in micro units (1e-6).  Complexity: O(1).
pub fn meshopt_filter_quat_probe() -> Int
  requires: true
{
  unsafe {
    var se = xmo_slot4();
    xmo_filter_quat_probe(se.as_mut_ptr());
    return xmo_read_u32(&se);
  }
}

/// Exp filter round trip ((1.5, 3.0, 8.0), 16-bit mantissa, separate
/// exponents); returns the max RELATIVE error in micro units.
/// Complexity: O(1).
pub fn meshopt_filter_exp_probe() -> Int
  requires: true
{
  unsafe {
    var se = xmo_slot4();
    xmo_filter_exp_probe(se.as_mut_ptr());
    return xmo_read_u32(&se);
  }
}

/// Color filter round trip ((1.0, 0.5, 0.25, 1.0), 8-bit YCoCg); returns the
/// max component error in micro units.  Complexity: O(1).
pub fn meshopt_filter_color_probe() -> Int
  requires: true
{
  unsafe {
    var se = xmo_slot4();
    xmo_filter_color_probe(se.as_mut_ptr());
    return xmo_read_u32(&se);
  }
}

/// Meshlet codec round trip: encode meshlet 0 of the probe grid (u32 vertex
/// refs + u8 local triangle indices) and decode it typed (4-byte vertices,
/// 3-byte triangles).  Vertex refs are byte-exact; triangles are compared
/// rotation-invariant (the meshlet triangle coder rotates corners to line up
/// next-bits, like the index codec).  Complexity: O(meshlet).
pub fn meshopt_meshlet_codec_probe() -> Result[MeshoptMeshletCodec, Str]
  requires: true
{
  unsafe {
    var fv = xmo_slot4();
    var ft = xmo_slot4();
    var fs = xmo_slot4();
    var fr = xmo_slot4();
    var fe = xmo_slot4();
    let rc = xmo_meshlet_codec_probe(fv.as_mut_ptr(), ft.as_mut_ptr(), fs.as_mut_ptr(), fr.as_mut_ptr(), fe.as_mut_ptr()) as Int;
    if rc != 0 { return Err("meshopt: meshlet codec probe rc=" + xmo_i2s(rc)); }
    return Ok(MeshoptMeshletCodec{
      vertex_count: xmo_read_u32(&fv),
      triangle_count: xmo_read_u32(&ft),
      enc_size: xmo_read_u32(&fs),
      dec_rc: xmo_read_u32(&fr),
      equal: xmo_read_u32(&fe) != 0
    });
  }
}

// =========================================================================
// 0.5.0: raw-surface wrappers for the safe/cooked sibling modules
// =========================================================================
//
// Extern "C" names are module-private on the pin (v0.64.4), so the sibling
// modules (xiom.meshopt_safe, xiom.meshopt_cooked) reach the C surface
// through these thin pub wrappers; FFI stays confined to this module (G5).
// Signatures mirror meshoptimizer.h with the declaration convention above
// (pointer params are Int; Int params cross the boundary faithfully).

pub fn generate_vertex_remap_into(remap_ptr: Int, vertices_ptr: Int, vertex_count: Int, vertex_size: Int) -> Int
  requires: remap_ptr != 0
  requires: vertices_ptr != 0
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  // indices = NULL with index_count = vertex_count: the identity index list,
  // which is the valid NULL-indices form (upstream asserts the equality).
  return unsafe { meshopt_generateVertexRemap(remap_ptr, 0, vertex_count, vertices_ptr, vertex_count, vertex_size) };
}

pub fn remap_vertex_buffer(dest_ptr: Int, vertices_ptr: Int, vertex_count: Int, vertex_size: Int, remap_ptr: Int)
  requires: dest_ptr != 0
  requires: vertices_ptr != 0
  requires: remap_ptr != 0
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  unsafe { meshopt_remapVertexBuffer(dest_ptr, vertices_ptr, vertex_count, vertex_size, remap_ptr); }
}

pub fn remap_index_buffer(dest_ptr: Int, indices_ptr: Int, index_count: Int, remap_ptr: Int)
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: remap_ptr != 0
  requires: index_count > 0
{
  unsafe { meshopt_remapIndexBuffer(dest_ptr, indices_ptr, index_count, remap_ptr); }
}

pub fn optimize_vertex_cache_fifo(dest_ptr: Int, indices_ptr: Int, index_count: Int, vertex_count: Int, cache_size: Int32)
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  unsafe { meshopt_optimizeVertexCacheFifo(dest_ptr, indices_ptr, index_count, vertex_count, cache_size); }
}

pub fn optimize_overdraw(dest_ptr: Int, indices_ptr: Int, index_count: Int, positions_ptr: Int, vertex_count: Int, pos_stride: Int, threshold: Float32)
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: positions_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  unsafe { meshopt_optimizeOverdraw(dest_ptr, indices_ptr, index_count, positions_ptr, vertex_count, pos_stride, threshold); }
}

pub fn optimize_vertex_fetch(dest_ptr: Int, indices_ptr: Int, index_count: Int, vertices_ptr: Int, vertex_count: Int, vertex_size: Int) -> Int
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: vertices_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  return unsafe { meshopt_optimizeVertexFetch(dest_ptr, indices_ptr, index_count, vertices_ptr, vertex_count, vertex_size) };
}

pub fn optimize_vertex_fetch_remap(dest_ptr: Int, indices_ptr: Int, index_count: Int, vertex_count: Int) -> Int
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  return unsafe { meshopt_optimizeVertexFetchRemap(dest_ptr, indices_ptr, index_count, vertex_count) };
}

pub fn analyze_vertex_fetch(indices_ptr: Int, index_count: Int, vertex_count: Int, vertex_size: Int) -> MeshoptVertexFetchStatistics
  requires: indices_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
{
  return unsafe { meshopt_analyzeVertexFetch(indices_ptr, index_count, vertex_count, vertex_size) };
}

pub fn simplify_with_options(dest_ptr: Int, indices_ptr: Int, index_count: Int, pos_ptr: Int, vertex_count: Int, pos_stride: Int, target_count: Int, target_error: Float32, options: Int32) -> Int
  requires: dest_ptr != 0
  requires: indices_ptr != 0
  requires: pos_ptr != 0
  requires: index_count > 0
  requires: vertex_count > 0
  requires: target_count > 0
{
  return unsafe { meshopt_simplify(dest_ptr, indices_ptr, index_count, pos_ptr, vertex_count, pos_stride, target_count, target_error, options, 0) };
}

pub fn encode_index_bound(index_count: Int, vertex_count: Int) -> Int
  requires: index_count > 0
{
  return unsafe { meshopt_encodeIndexBufferBound(index_count, vertex_count) };
}

pub fn encode_indices_raw(buffer_ptr: Int, buffer_size: Int, indices_ptr: Int, index_count: Int) -> Int
  requires: buffer_ptr != 0
  requires: indices_ptr != 0
  requires: index_count > 0
{
  return unsafe { meshopt_encodeIndexBuffer(buffer_ptr, buffer_size, indices_ptr, index_count) };
}

pub fn encode_vertices_bound(vertex_count: Int, vertex_size: Int) -> Int
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  return unsafe { meshopt_encodeVertexBufferBound(vertex_count, vertex_size) };
}

pub fn encode_vertices_raw(buffer_ptr: Int, buffer_size: Int, vertices_ptr: Int, vertex_count: Int, vertex_size: Int) -> Int
  requires: buffer_ptr != 0
  requires: vertices_ptr != 0
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  return unsafe { meshopt_encodeVertexBuffer(buffer_ptr, buffer_size, vertices_ptr, vertex_count, vertex_size) };
}

pub fn decode_vertex_buffer(dest_ptr: Int, vertex_count: Int, vertex_size: Int, buffer_ptr: Int, buffer_size: Int) -> Int32
  requires: dest_ptr != 0
  requires: buffer_ptr != 0
  requires: vertex_count > 0
  requires: vertex_size > 0
{
  return unsafe { meshopt_decodeVertexBuffer(dest_ptr, vertex_count, vertex_size, buffer_ptr, buffer_size) };
}

pub fn decode_index_buffer(dest_ptr: Int, index_count: Int, index_size: Int, buffer_ptr: Int, buffer_size: Int) -> Int32
  requires: dest_ptr != 0
  requires: buffer_ptr != 0
  requires: index_count > 0
{
  return unsafe { meshopt_decodeIndexBuffer(dest_ptr, index_count, index_size, buffer_ptr, buffer_size) };
}

pub fn stripify_bound(index_count: Int) -> Int
  requires: index_count > 0
{
  return unsafe { meshopt_stripifyBound(index_count) };
}
