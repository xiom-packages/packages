// XIOM -- xiom.zstd: Zstandard bindings (vendored single-file amalgamation).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C path (same pattern as xiom.sqlite). The official
// single-file amalgamation `vendor/zstd.c` (generated with the upstream
// combine.py from release v1.5.7, BSD-3-Clause) is compiled into the test
// binary via `--c-source` (port.args.json); `vendor/zstd.h` and the upstream
// LICENSE are vendored alongside. No system library, no runtime DLL.
//
// G5 confinement: this is the ONE module in the package with `extern "C"`;
// every foreign call is wrapped here. Other modules are pure XIOM.
//
// G2 pin (SPEC.md): upstream release v1.5.7 (tar.gz SHA256 verified against
// the published .sha256) + generated `vendor/zstd.c` SHA256 + `vendor/zstd.h`
// SHA256 + BSD-3-Clause license.
//
// API subset (pilot): version, compressBound, one-shot compress/decompress,
// frame content size, error detection/naming. Streaming CCtx/DCtx and
// dictionaries are Phase 2 (ROADMAP.md).
//
// 0.3.0 adds the ZSTC container framing surface (SPEC.md section 5): a
// general-purpose container over N independently compressed zstd frames with
// a per-frame offset/size index for random access. Writer (one-shot and
// append+finalize builder), reader (open/frame_count/frame_at), seek-by-index
// and typed container errors. All container logic is pure XIOM over owned
// Vec[UInt8] buffers; only the frame content-size query and decompression
// cross the FFI boundary, through the wrappers above.

module xiom.zstd

extern "C" {
  fn ZSTD_versionNumber() -> UInt32;
  fn ZSTD_compressBound(srcSize: Int) -> Int;
  fn ZSTD_compress(dst: *UInt8, dstCapacity: Int, src: *UInt8, srcSize: Int, compressionLevel: Int) -> Int;
  fn ZSTD_decompress(dst: *UInt8, dstCapacity: Int, src: *UInt8, compressedSize: Int) -> Int;
  fn ZSTD_getFrameContentSize(src: *UInt8, srcSize: Int) -> UInt64;
  fn ZSTD_isError(code: Int) -> UInt32;
  fn ZSTD_getErrorName(code: Int) -> *UInt8;
}

// ZSTD_getFrameContentSize sentinels (zstd.h).
pub const ZSTD_CONTENTSIZE_UNKNOWN: Int = -1;
pub const ZSTD_CONTENTSIZE_ERROR: Int = -2;

/// Runtime zstd version as an integer (e.g. 10507 for 1.5.7).
/// Complexity: O(1).
pub fn zstd_version_number() -> Int
  requires: true
{
  unsafe { return ZSTD_versionNumber() as Int; }
}

/// Human version string derived from the version number.
/// Complexity: O(1).
pub fn zstd_version() -> Str
  requires: true
{
  let v = zstd_version_number();
  return int_to_str(v / 10000) + "." + int_to_str((v / 100) % 100) + "." + int_to_str(v % 100);
}

/// Worst-case compressed size for an input of `src_size` bytes.
/// Complexity: O(1).
pub fn zstd_compress_bound(src_size: Int) -> Int
  requires: src_size >= 0
{
  unsafe { return ZSTD_compressBound(src_size); }
}

/// True when a returned size_t is an error code.
/// Complexity: O(1).
pub fn zstd_is_error(code: Int) -> Bool
  requires: true
{
  unsafe { return (ZSTD_isError(code) as Int) != 0; }
}

/// Error name for an error code ("" when the code is not an error).
/// Complexity: O(len).
pub fn zstd_error_name(code: Int) -> Str
  requires: true
{
  unsafe {
    let p = ZSTD_getErrorName(code);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Content size declared by a zstd frame, or ZSTD_CONTENTSIZE_UNKNOWN (-1) /
/// ZSTD_CONTENTSIZE_ERROR (-2).
/// Complexity: O(1).
pub fn zstd_frame_content_size(src: &mut Vec[UInt8]) -> Int
  requires: src.len() > 0
{
  unsafe {
    let v = ZSTD_getFrameContentSize(src.as_mut_ptr(), src.len());
    if v == 18446744073709551615 { return ZSTD_CONTENTSIZE_UNKNOWN; }
    if v == 18446744073709551614 { return ZSTD_CONTENTSIZE_ERROR; }
    return v as Int;
  }
}

/// One-shot compression of `src` at `level` (1..22; 3 is the default).
/// Returns the compressed frame as a new buffer.
/// Complexity: O(len(src)) plus compression work.
pub fn zstd_compress(src: &mut Vec[UInt8], level: Int) -> Result[Vec[UInt8], Str]
  requires: src.len() >= 0
  requires: level >= 1
  requires: level <= 22
{
  let bound = zstd_compress_bound(src.len());
  var dst: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < bound {
    dst.push(0 as UInt8);
    i = i + 1;
  }
  let rc = unsafe { ZSTD_compress(dst.as_mut_ptr(), bound, src.as_mut_ptr(), src.len(), level) };
  if zstd_is_error(rc) {
    return Err(zstd_error_name(rc));
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var k: Int = 0;
  while k < rc {
    out.push(dst[k]);
    k = k + 1;
  }
  return Ok(out);
}

/// One-shot decompression into a buffer of `out_capacity` bytes.
/// Returns the decompressed bytes as a new buffer.
/// Complexity: O(compressed) plus decompression work.
pub fn zstd_decompress(src: &mut Vec[UInt8], out_capacity: Int) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
  requires: out_capacity > 0
{
  var dst: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < out_capacity {
    dst.push(0 as UInt8);
    i = i + 1;
  }
  let rc = unsafe { ZSTD_decompress(dst.as_mut_ptr(), out_capacity, src.as_mut_ptr(), src.len()) };
  if zstd_is_error(rc) {
    return Err(zstd_error_name(rc));
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var k: Int = 0;
  while k < rc {
    out.push(dst[k]);
    k = k + 1;
  }
  return Ok(out);
}

/// Decompress using the frame content size recorded in the zstd frame
/// (single-shot frames record it).  Err when the size is unknown.
/// Complexity: O(compressed) plus decompression work.
pub fn zstd_decompress_auto(src: &mut Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
{
  let size = zstd_frame_content_size(src);
  if size == ZSTD_CONTENTSIZE_UNKNOWN {
    return Err("zstd: frame content size unknown");
  }
  if size == ZSTD_CONTENTSIZE_ERROR {
    return Err("zstd: not a valid zstd frame");
  }
  if size <= 0 {
    return Err("zstd: frame content size is not positive");
  }
  return zstd_decompress(src, size);
}

// --------------------------------------------------
//  ZSTC container framing (0.3.0)
// --------------------------------------------------

// Container byte layout (all integers little-endian; SPEC.md section 5):
//
//   header (16 bytes): magic "ZSTC" | u16 version | u16 flags |
//                      u32 frame_count | u32 index_offset
//   frame region:      frame_count raw zstd frames, back to back, no padding
//   index (at index_offset): frame_count entries of 12 bytes each:
//                      u32 frame_offset | u32 compressed_size |
//                      u32 decompressed_size
//
// The writer records the zstd frame content size as decompressed_size, so
// every container it emits describes its own decompressed sizes. A frame
// whose content size is not recorded in the frame header (streaming-style
// frames) is rejected with a typed error; the reader validates the index
// structure in full (exact-size check, contiguous frames, nonzero sizes) and
// validates each frame payload only at frame_at time, so a structurally
// valid container with a corrupt payload fails with a typed error instead of
// crashing. The empty container is valid: 16 bytes, zero frames.

/// ZSTC magic length in bytes ("ZSTC").
pub const ZSTC_MAGIC_LEN: Int = 4;

/// ZSTC fixed header length in bytes.
pub const ZSTC_HEADER_LEN: Int = 16;

/// ZSTC index entry length in bytes.
pub const ZSTC_INDEX_ENTRY_LEN: Int = 12;

/// ZSTC format version written by this package; readers reject any other.
pub const ZSTC_FORMAT_VERSION: Int = 1;

/// Parsed ZSTC container index. The container bytes stay in the caller's
/// buffer (the one passed to zstd_container_open); frame_at slices the
/// compressed region out of that buffer. Fields are implementation details;
/// callers use the free functions below.
pub type ZstdContainer = {
  frame_offsets: Vec[Int];
  frame_sizes: Vec[Int];
  frame_out_sizes: Vec[Int];
  index_offset: Int;
  total_size: Int;
}

/// Streaming-ish container builder: append validated frames one at a time,
/// then finalize into one ZSTC container buffer. Invalid frames are rejected
/// at append time and leave the builder unchanged.
pub type ZstdContainerBuilder = {
  frames: Vec[Vec[UInt8]];
  out_sizes: Vec[Int];
}

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _zc_byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 255;
}

// Little-endian UInt32 at `off` (callers guarantee four bytes).
fn _zc_u32(data: &Vec[UInt8], off: Int) -> Int {
  let b0: Int = _zc_byte(data, off);
  let b1: Int = _zc_byte(data, off + 1);
  let b2: Int = _zc_byte(data, off + 2);
  let b3: Int = _zc_byte(data, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Append `v` (0..4294967295) as four little-endian bytes.
fn _zc_put_u32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push((v / 256 % 256) as UInt8);
  out.push((v / 65536 % 256) as UInt8);
  out.push((v / 16777216 % 256) as UInt8);
}

// Append `v` (0..65535) as two little-endian bytes.
fn _zc_put_u16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push((v / 256 % 256) as UInt8);
}

// Append the bytes of `v`.
fn _zc_push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

/// Build one ZSTC container from N compressed zstd frames (frame order is
/// preserved; each frame is stored uncompressed-in-container, i.e. exactly
/// the bytes passed in). The container is: 16-byte header + frame region +
/// 12-byte-per-frame index, so its length is
/// `ZSTC_HEADER_LEN + sum(frame sizes) + N * ZSTC_INDEX_ENTRY_LEN`.
///
/// Every frame must be a zstd frame whose content size is recorded in the
/// frame header (frames produced by `zstd_compress` qualify).
///
/// Error catalog (first failing frame wins, nothing is emitted):
/// Err("zstd.container: empty frame") for a zero-length frame;
/// Err("zstd.container: container too large") when a frame or the frame
/// count exceeds the u32 index fields;
/// Err("zstd.container: not a zstd frame") when the frame content size
/// reads as ZSTD_CONTENTSIZE_ERROR;
/// Err("zstd.container: frame content size unknown") for a valid frame
/// without a recorded content size.
/// An empty frame list yields exactly the 16-byte empty container.
/// Complexity: O(total frame bytes).
pub fn zstd_container_write(frames: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
  ensures: frames.len() == 0 => result is Ok;
{
  var b = zstd_container_builder_new();
  let n: Int = frames.len();
  var i = 0;
  while i < n {
    let f: Vec[UInt8] = frames[i];
    let r = zstd_container_builder_append(&mut b, &f);
    if !r.is_ok {
      return Err(r.error);
    }
    i = i + 1;
  }
  return zstd_container_builder_finalize(&mut b);
}

/// New empty container builder. Complexity: O(1).
pub fn zstd_container_builder_new() -> ZstdContainerBuilder {
  return ZstdContainerBuilder{ frames: Vec[Vec[UInt8]].new(); out_sizes: Vec[Int].new() };
}

/// Number of frames appended to the builder so far. Complexity: O(1).
pub fn zstd_container_builder_count(b: &ZstdContainerBuilder) -> Int
  ensures: result == b.frames.len();
{
  return b.frames.len();
}

/// Validate and append one compressed zstd frame to the builder.
///
/// The frame must be non-empty and carry a recorded content size (the
/// decompressed size is stored in the index at finalize). The error catalog
/// is that of zstd_container_write; on Err the builder is unchanged.
/// Complexity: O(frame.len()).
pub fn zstd_container_builder_append(b: &mut ZstdContainerBuilder, frame: &Vec[UInt8]) -> Result[Unit, Str]
  ensures: frame.len() == 0 => result is Err;
{
  let fl: Int = frame.len();
  if fl == 0 {
    return Err("zstd.container: empty frame");
  }
  if fl > 4294967295 {
    return Err("zstd.container: container too large");
  }
  if b.frames.len() >= 4294967295 {
    return Err("zstd.container: container too large");
  }
  var f: Vec[UInt8] = Vec[UInt8].new();
  _zc_push_bytes(&mut f, frame);
  let out_size: Int = zstd_frame_content_size(&mut f);
  if out_size == ZSTD_CONTENTSIZE_ERROR {
    return Err("zstd.container: not a zstd frame");
  }
  if out_size == ZSTD_CONTENTSIZE_UNKNOWN {
    return Err("zstd.container: frame content size unknown");
  }
  b.frames.push(f);
  b.out_sizes.push(out_size);
  return Ok(());
}

/// Assemble the final ZSTC container from every frame appended so far.
/// The builder is not consumed: it can keep receiving frames and be
/// finalized again (each finalize re-emits the same bytes).
/// Err("zstd.container: container too large") when the running frame bytes
/// exceed the u32 index fields. Complexity: O(total frame bytes).
pub fn zstd_container_builder_finalize(b: &mut ZstdContainerBuilder) -> Result[Vec[UInt8], Str] {
  let n: Int = b.frames.len();
  var body: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let f: Vec[UInt8] = b.frames[i];
    _zc_push_bytes(&mut body, &f);
    i = i + 1;
  }
  let index_offset: Int = ZSTC_HEADER_LEN + body.len();
  if index_offset > 4294967295 {
    return Err("zstd.container: container too large");
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  out.push(90 as UInt8);
  out.push(83 as UInt8);
  out.push(84 as UInt8);
  out.push(67 as UInt8);
  _zc_put_u16(&mut out, ZSTC_FORMAT_VERSION);
  _zc_put_u16(&mut out, 0);
  _zc_put_u32(&mut out, n);
  _zc_put_u32(&mut out, index_offset);
  _zc_push_bytes(&mut out, &body);
  var off: Int = ZSTC_HEADER_LEN;
  i = 0;
  while i < n {
    let f2: Vec[UInt8] = b.frames[i];
    let os: Int = b.out_sizes[i];
    _zc_put_u32(&mut out, off);
    _zc_put_u32(&mut out, f2.len());
    _zc_put_u32(&mut out, os);
    off = off + f2.len();
    i = i + 1;
  }
  return Ok(out);
}

/// Open/parse a ZSTC container buffer. The buffer stays owned by the caller
/// (every operation below takes it by reference; nothing is copied).
///
/// Validation order (first failure wins):
/// len < 16 -> Err("zstd.container: truncated header");
/// magic != "ZSTC" -> Err("zstd.container: bad magic");
/// version != 1 -> Err("zstd.container: unsupported version");
/// flags != 0 -> Err("zstd.container: unsupported flags");
/// index_offset outside [16, len] or
/// index_offset + frame_count * 12 != len ->
/// Err("zstd.container: truncated index");
/// a frame entry whose offset is not exactly the running end of the previous
/// frame (first frame at 16), a zero compressed size, or a frame region
/// crossing index_offset -> Err("zstd.container: bad frame index");
/// zero frames with an index_offset above 16 -> Err("zstd.container: bad
/// frame index").
///
/// Frame payloads are NOT parsed here; a structurally valid container with a
/// corrupt frame fails at zstd_container_frame_at with a typed error.
/// Complexity: O(frame_count).
pub fn zstd_container_open(data: &Vec[UInt8]) -> Result[ZstdContainer, Str]
  ensures: data.len() < ZSTC_HEADER_LEN => result is Err;
{
  let n0: Int = data.len();
  if n0 < ZSTC_HEADER_LEN {
    return Err("zstd.container: truncated header");
  }
  if _zc_byte(data, 0) != 90 || _zc_byte(data, 1) != 83 || _zc_byte(data, 2) != 84 || _zc_byte(data, 3) != 67 {
    return Err("zstd.container: bad magic");
  }
  let version: Int = _zc_byte(data, 4) + _zc_byte(data, 5) * 256;
  if version != ZSTC_FORMAT_VERSION {
    return Err("zstd.container: unsupported version");
  }
  let flags: Int = _zc_byte(data, 6) + _zc_byte(data, 7) * 256;
  if flags != 0 {
    return Err("zstd.container: unsupported flags");
  }
  let count: Int = _zc_u32(data, 8);
  let index_offset: Int = _zc_u32(data, 12);
  if index_offset < ZSTC_HEADER_LEN || index_offset > n0 {
    return Err("zstd.container: truncated index");
  }
  if index_offset + count * ZSTC_INDEX_ENTRY_LEN != n0 {
    return Err("zstd.container: truncated index");
  }
  var frame_offsets: Vec[Int] = Vec[Int].new();
  var frame_sizes: Vec[Int] = Vec[Int].new();
  var frame_out_sizes: Vec[Int] = Vec[Int].new();
  var expected: Int = ZSTC_HEADER_LEN;
  var pos: Int = index_offset;
  var i = 0;
  while i < count {
    let off: Int = _zc_u32(data, pos);
    let csize: Int = _zc_u32(data, pos + 4);
    let osize: Int = _zc_u32(data, pos + 8);
    if off != expected || csize <= 0 {
      return Err("zstd.container: bad frame index");
    }
    if off + csize > index_offset {
      return Err("zstd.container: bad frame index");
    }
    frame_offsets.push(off);
    frame_sizes.push(csize);
    frame_out_sizes.push(osize);
    expected = expected + csize;
    pos = pos + ZSTC_INDEX_ENTRY_LEN;
    i = i + 1;
  }
  if expected != index_offset {
    return Err("zstd.container: bad frame index");
  }
  return Ok(ZstdContainer{
    frame_offsets: frame_offsets;
    frame_sizes: frame_sizes;
    frame_out_sizes: frame_out_sizes;
    index_offset: index_offset;
    total_size: n0;
  });
}

/// Number of frames in the container index. Complexity: O(1).
pub fn zstd_container_frame_count(c: &ZstdContainer) -> Int
  ensures: result == c.frame_offsets.len();
{
  return c.frame_offsets.len();
}

/// Total container size in bytes (validated at open). Complexity: O(1).
pub fn zstd_container_total_size(c: &ZstdContainer) -> Int
  ensures: result >= ZSTC_HEADER_LEN;
{
  return c.total_size;
}

/// Absolute offset of the index table in the container. Complexity: O(1).
pub fn zstd_container_index_offset(c: &ZstdContainer) -> Int
  ensures: result >= ZSTC_HEADER_LEN;
{
  return c.index_offset;
}

/// Absolute offset of frame `i`'s first byte in the container; -1 when `i`
/// is out of range. Complexity: O(1).
pub fn zstd_container_frame_offset(c: &ZstdContainer, i: Int) -> Int
  ensures: i < 0 => result == -1;
  ensures: i >= c.frame_offsets.len() => result == -1;
{
  if i < 0 || i >= c.frame_offsets.len() {
    return -1;
  }
  let v: Int = c.frame_offsets[i];
  return v;
}

/// Compressed (stored) size of frame `i` in bytes; -1 out of range.
/// Complexity: O(1).
pub fn zstd_container_frame_size(c: &ZstdContainer, i: Int) -> Int
  ensures: i < 0 => result == -1;
  ensures: i >= c.frame_sizes.len() => result == -1;
{
  if i < 0 || i >= c.frame_sizes.len() {
    return -1;
  }
  let v: Int = c.frame_sizes[i];
  return v;
}

/// Decompressed size of frame `i` recorded in the index at write time;
/// -1 out of range. Complexity: O(1).
pub fn zstd_container_frame_out_size(c: &ZstdContainer, i: Int) -> Int
  ensures: i < 0 => result == -1;
  ensures: i >= c.frame_out_sizes.len() => result == -1;
{
  if i < 0 || i >= c.frame_out_sizes.len() {
    return -1;
  }
  let v: Int = c.frame_out_sizes[i];
  return v;
}

/// Seek-by-index: absolute byte offset of frame `i` in the container, ready
/// to slice the stored frame out of the container buffer.
/// Err("zstd.container: frame out of range") for `i` < 0 or >= frame_count.
/// Complexity: O(1).
pub fn zstd_container_seek(c: &ZstdContainer, i: Int) -> Result[Int, Str]
  ensures: i < 0 => result is Err;
  ensures: i >= c.frame_offsets.len() => result is Err;
{
  if i < 0 || i >= c.frame_offsets.len() {
    return Err("zstd.container: frame out of range");
  }
  let off: Int = c.frame_offsets[i];
  return Ok(off);
}

/// Random access: decompress frame `i` out of the container buffer `data`
/// (the buffer passed to zstd_container_open) into a NEW owned buffer.
/// Frames can be read in any order, repeatedly, independently.
///
/// Err("zstd.container: frame out of range") for `i` out of range;
/// Err("zstd.container: bad frame index") for a hand-built index with a
/// non-positive size or an offset inside the header;
/// Err("zstd.container: truncated frame") when `data` is shorter than the
/// recorded frame range;
/// Err("zstd.container: decompress failed (...zstd error...)") when the
/// stored payload is not a valid zstd frame;
/// Err("zstd.container: frame size mismatch") when the payload decompresses
/// to a different size than the index records.
/// A frame recorded with decompressed size 0 yields an empty Ok buffer.
/// Complexity: O(frame size) plus decompression work.
pub fn zstd_container_frame_at(data: &Vec[UInt8], c: &ZstdContainer, i: Int) -> Result[Vec[UInt8], Str]
  ensures: i < 0 => result is Err;
  ensures: i >= c.frame_offsets.len() => result is Err;
{
  if i < 0 || i >= c.frame_offsets.len() {
    return Err("zstd.container: frame out of range");
  }
  let off: Int = c.frame_offsets[i];
  let csize: Int = c.frame_sizes[i];
  let osize: Int = c.frame_out_sizes[i];
  if off < ZSTC_HEADER_LEN || csize <= 0 || osize < 0 {
    return Err("zstd.container: bad frame index");
  }
  if off + csize > data.len() {
    return Err("zstd.container: truncated frame");
  }
  var comp: Vec[UInt8] = Vec[UInt8].new();
  var k = 0;
  while k < csize {
    comp.push(data[off + k]);
    k = k + 1;
  }
  var cap: Int = osize;
  if cap < 1 {
    cap = 1;
  }
  let r = zstd_decompress(&mut comp, cap);
  if !r.is_ok {
    return Err("zstd.container: decompress failed (" + r.error + ")");
  }
  var out: Vec[UInt8] = r.value;
  if out.len() != osize {
    return Err("zstd.container: frame size mismatch");
  }
  return Ok(out);
}

// Local integer-to-string (avoids cross-module const/convert pitfalls in the
// confined module; see docs/BINDINGS-COMPILER-FINDINGS.md).
fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}
