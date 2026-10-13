// XIOM -- meshoptimizer cooked-mesh container
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 0.5.0: a small self-describing container that wraps the EncodePipeline
// streams (vertex + index codecs) plus the decoder integration surface.
//
// Format "XMC1" (all integers little-endian u32):
//
//   offset  size  field
//   0       4     magic "XMC1" (bytes 0x58 0x4D 0x43 0x31)
//   4       4     format version (1)
//   8       4     vertex_count
//   12      4     vertex_size (bytes per vertex, 1..256)
//   16      4     index_count (u32 indices, multiple of 3)
//   20      4     vertex_stream_size (encoded bytes)
//   24      4     index_stream_size (encoded bytes)
//   28      4     total_size (32 + vertex_stream_size + index_stream_size)
//   32      ...   vertex stream, then index stream
//
// Decoding stays on the owned-memory path: the streams are copied into owned
// staging slots, C decodes into owned destination slots, and the decoded
// bytes are read back byte-indexed (B-16/B-17/B-20/B-24/B-25 discipline; no
// foreign-pointer reads, no pointer arithmetic).
//
// Module name note: a dotted child (`xiom.meshopt.cooked`) cannot import its
// parent on the pin (B-04: child -> parent imports do not resolve), so the
// module uses the flat sibling namespace `xiom.meshopt_cooked`.

module xiom.meshopt_cooked

use xiom.meshopt;
use xiom.meshopt_safe;

// =========================================================================
// Format constants and typed error codes
// =========================================================================

pub const MESHOPT_COOKED_MAGIC: Int = 826494296;
pub const MESHOPT_COOKED_VERSION: Int = 1;
pub const MESHOPT_COOKED_HEADER_SIZE: Int = 32;

pub const MESHOPT_COOKED_ERR_HEADER: Int32 = 10;
pub const MESHOPT_COOKED_ERR_MAGIC: Int32 = 11;
pub const MESHOPT_COOKED_ERR_VERSION: Int32 = 12;
pub const MESHOPT_COOKED_ERR_SIZE: Int32 = 13;
pub const MESHOPT_COOKED_ERR_DECODE: Int32 = 14;
pub const MESHOPT_COOKED_ERR_RANGE: Int32 = 15;

// =========================================================================
// Decoded mesh payload
// =========================================================================

pub type MeshoptCookedMesh = {
  vertex_count: Int;
  vertex_size: Int;
  index_count: Int;
  vertices: Vec[UInt8];
  indices: Vec[UInt8];
} derive[Clone]

// =========================================================================
// Byte helpers (owned buffers, byte-indexed only)
// =========================================================================

/// Little-endian u32 read from an XIOM-owned byte slot (byte-indexed).
/// Complexity: O(1).
fn cooked_rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Little-endian u32 append to an XIOM-owned byte slot (byte-indexed).
/// Complexity: O(1).
fn cooked_push_u32(buf: &mut Vec[UInt8], v: Int)
  requires: v >= 0
{
  buf.push((v & 255) as UInt8);
  buf.push(((v >> 8) & 255) as UInt8);
  buf.push(((v >> 16) & 255) as UInt8);
  buf.push(((v >> 24) & 255) as UInt8);
}

/// Append n bytes from an owned source slot (byte-indexed).
/// Complexity: O(n).
fn cooked_append(out: &mut Vec[UInt8], src: &Vec[UInt8], start: Int, n: Int)
  requires: start >= 0
  requires: n >= 0
  requires: src.len() >= start + n
{
  var i: Int = 0;
  while i < n {
    out.push(src[start + i]);
    i = i + 1;
  }
}

/// Copy n bytes out of an owned source slot into a fresh owned slot
/// (byte-indexed). Complexity: O(n).
fn cooked_slice_copy(src: &Vec[UInt8], start: Int, n: Int) -> Vec[UInt8]
  requires: start >= 0
  requires: n > 0
  requires: src.len() >= start + n
{
  var out: Vec[UInt8] = Vec[UInt8].new();
  cooked_append(&mut out, src, start, n);
  return out;
}

// =========================================================================
// Writer -- owned vertex/index buffers -> "XMC1" container bytes
// =========================================================================

/// Cook a vertex buffer (u32-indexed mesh, stride `vertex_size`) and its u32
/// index list into an "XMC1" container: both streams go through the existing
/// EncodePipeline codecs and are framed by the header above.  All buffers are
/// XIOM-owned; C only reads them.  Ok carries the container bytes.
/// Complexity: O(vertices + indices).
pub fn meshopt_cooked_encode(vertices: &Vec[UInt8], vertex_count: Int, vertex_size: Int, indices: &Vec[UInt8], index_count: Int) -> Result[Vec[UInt8], MeshoptError]
  requires: vertex_count > 0
  requires: vertex_size > 0
  requires: vertex_size <= 256
  requires: index_count > 0
  requires: vertices.len() >= vertex_count * vertex_size
  requires: indices.len() >= index_count * 4
{
  if index_count % 3 != 0 {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_HEADER, message: "meshopt cooked: index_count must be a multiple of 3" });
  }
  let v_bound: Int = EncodePipeline.vertex_bound(vertex_count, vertex_size);
  var v_buf: Vec[UInt8] = meshopt.byte_slot(v_bound);
  let enc_v = EncodePipeline.encode_vertices(v_buf.as_mut_ptr() as Int, v_bound, vertices.as_ptr() as Int, vertex_count, vertex_size);
  if enc_v.is_err {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_DECODE, message: "meshopt cooked: vertex stream encode failed" });
  }
  let i_bound: Int = EncodePipeline.index_bound(index_count, vertex_count);
  var i_buf: Vec[UInt8] = meshopt.byte_slot(i_bound);
  let enc_i = EncodePipeline.encode_indices(i_buf.as_mut_ptr() as Int, i_bound, indices.as_ptr() as Int, index_count);
  if enc_i.is_err {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_DECODE, message: "meshopt cooked: index stream encode failed" });
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  cooked_push_u32(&mut out, MESHOPT_COOKED_MAGIC);
  cooked_push_u32(&mut out, MESHOPT_COOKED_VERSION);
  cooked_push_u32(&mut out, vertex_count);
  cooked_push_u32(&mut out, vertex_size);
  cooked_push_u32(&mut out, index_count);
  cooked_push_u32(&mut out, enc_v.value);
  cooked_push_u32(&mut out, enc_i.value);
  cooked_push_u32(&mut out, MESHOPT_COOKED_HEADER_SIZE + enc_v.value + enc_i.value);
  cooked_append(&mut out, &v_buf, 0, enc_v.value);
  cooked_append(&mut out, &i_buf, 0, enc_i.value);
  return Ok(out);
}

// =========================================================================
// Reader / integration helper -- "XMC1" bytes -> decoded mesh data
// =========================================================================

/// Open a cooked container from owned bytes, validate the header, decode both
/// codec streams into XIOM-owned buffers and return the reconstructed mesh
/// (counts + decoded vertex/index bytes) in one call -- no pointer juggling
/// on the consumer side.  Corrupt/truncated containers surface as typed
/// `MeshoptError` codes (10..15).  Complexity: O(bytes).
pub fn meshopt_cooked_decode(cooked: &Vec[UInt8]) -> Result[MeshoptCookedMesh, MeshoptError]
  requires: true
{
  if cooked.len() < MESHOPT_COOKED_HEADER_SIZE {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_HEADER, message: "meshopt cooked: truncated header" });
  }
  if cooked_rd_u32(cooked, 0) != MESHOPT_COOKED_MAGIC {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_MAGIC, message: "meshopt cooked: bad magic (want XMC1)" });
  }
  if cooked_rd_u32(cooked, 4) != MESHOPT_COOKED_VERSION {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_VERSION, message: "meshopt cooked: unsupported version" });
  }
  let vertex_count: Int = cooked_rd_u32(cooked, 8);
  let vertex_size: Int = cooked_rd_u32(cooked, 12);
  let index_count: Int = cooked_rd_u32(cooked, 16);
  let vertex_stream_size: Int = cooked_rd_u32(cooked, 20);
  let index_stream_size: Int = cooked_rd_u32(cooked, 24);
  let total_size: Int = cooked_rd_u32(cooked, 28);
  if vertex_count <= 0 || vertex_size <= 0 || vertex_size > 256 || index_count <= 0 || index_count % 3 != 0 {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_HEADER, message: "meshopt cooked: invalid counts" });
  }
  if vertex_stream_size <= 0 || index_stream_size <= 0 {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_SIZE, message: "meshopt cooked: empty stream" });
  }
  if total_size != cooked.len() || total_size != MESHOPT_COOKED_HEADER_SIZE + vertex_stream_size + index_stream_size {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_SIZE, message: "meshopt cooked: size mismatch (truncated or corrupt)" });
  }
  var v_stream: Vec[UInt8] = cooked_slice_copy(cooked, MESHOPT_COOKED_HEADER_SIZE, vertex_stream_size);
  var v_dest: Vec[UInt8] = meshopt.byte_slot(vertex_count * vertex_size);
  let dec_v = EncodePipeline.decode_vertices(v_dest.as_mut_ptr() as Int, vertex_count, vertex_size, v_stream.as_mut_ptr() as Int, vertex_stream_size);
  if dec_v.is_err {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_DECODE, message: "meshopt cooked: vertex stream decode failed" });
  }
  var i_stream: Vec[UInt8] = cooked_slice_copy(cooked, MESHOPT_COOKED_HEADER_SIZE + vertex_stream_size, index_stream_size);
  var i_dest: Vec[UInt8] = meshopt.byte_slot(index_count * 4);
  let dec_i = EncodePipeline.decode_indices(i_dest.as_mut_ptr() as Int, index_count, 4, i_stream.as_mut_ptr() as Int, index_stream_size);
  if dec_i.is_err {
    return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_DECODE, message: "meshopt cooked: index stream decode failed" });
  }
  var i: Int = 0;
  while i < index_count {
    if cooked_rd_u32(&i_dest, i * 4) >= vertex_count {
      return Err(MeshoptError{ code: MESHOPT_COOKED_ERR_RANGE, message: "meshopt cooked: decoded index out of range" });
    }
    i = i + 1;
  }
  return Ok(MeshoptCookedMesh{
    vertex_count: vertex_count,
    vertex_size: vertex_size,
    index_count: index_count,
    vertices: v_dest,
    indices: i_dest
  });
}
