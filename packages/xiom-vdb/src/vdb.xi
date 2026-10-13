// XIOM -- xiom.vdb: minimal OpenVDB ".vdb" file reader (pure XIOM)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// An independent, surface-first reader for the OpenVDB sparse-volume
// container. It is NOT a port of OpenVDB: no upstream code was copied or
// vendored (see PROVENANCE.md); the file layout below was implemented from
// the documented format and cross-read against the pinned upstream oracle
// (v13.1.0, Apache-2.0) as a semantic reference only.
//
// What this module reads from a ".vdb" image (little-endian, file format
// versions 222..225):
//
//   file    : 8-byte magic 0x56444220 ("VDB " family), u32 file version,
//             u32 library major/minor, u8 has-grid-offsets flag,
//             36-byte UUID, file-level MetaMap, i32 grid count, then one
//             GridDescriptor per grid (unique name, tree type name,
//             instance-parent name, three i64 stream positions) followed
//             by that grid's body;
//   grid    : u32 compression flags, MetaMap, math::Transform
//             (space-terminated type name + fixed-size map payload),
//             tree topology (background value, root tiles and children,
//             node masks, mask-compressed node values) and the leaf
//             buffers section (per leaf: 64-byte value mask + mask
//             metadata + compressed active values);
//   values  : float / float-as-half / double / half / vec3f /
//             vec3f-as-half / vec3d leaves, raw or zlib-compressed, with
//             OpenVDB's active-mask compression (inactive values are
//             reconstructed from the background, two saved inactive
//             values and/or a selection mask).
//
// The zlib framing (i64 chunk size prefix: positive = zlib stream,
// non-positive = uncompressed fallback of -n bytes), the RFC 1950/1951
// inflate path and the Adler-32 checksum are implemented here in pure
// XIOM. Blosc-framed chunks are skipped for structure walks but fail with
// a typed error on value decode (documented limitation).
//
// Non-goals (documented, enforced by typed errors where reachable):
// point-data / bool / mask / integer trees, grids without offsets whose
// bodies cannot be skipped, instance trees (the parent name is exposed),
// multi-buffer (multi-pass) trees, file versions < 222 or > 225, blosc
// value decode, writers of any kind.
//
// v0.64.4 notes that shaped this module (see docs/BINDINGS-COMPILER-FINDINGS.md):
//   * free functions only; no Vec[StructType] fields (parallel vectors);
//   * every Ok/Err is built in a tiny leaf constructor;
//   * every UInt8 is widened with `(b as Int) & 0xFF` once;
//   * Vec/Vec-element reads are bound to typed locals first;
//   * Str equality goes through xiom.string.compare.str_compare;
//   * no `&mut` of call-result temporaries (locals are bound first);
//   * flat outcome structs; no Result[Option[T]] shapes.
//
// v0.64.4 finding (found while building this package): the `?` operator
// corrupts the propagated error when the enclosing function's Result
// payload type differs from the callee's (verified minimally: a
// Result[Int, E] error crossed into a Result[Vec[UInt8], E] function and
// reading `.error.code` crashed with an access violation; the same error
// hand-unpacked and rebuilt through a leaf constructor is sound). This
// module therefore uses NO `?` anywhere and re-wraps every propagated
// error explicitly through the `_err_*` leaf constructors.

module xiom.vdb

use xiom.string;
use xiom.string.compare;
use xiom.math;
use xiom.num.float;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// 32-bit OpenVDB magic (0x56444220), stored zero-extended in the first
/// 8 bytes of every file.
pub const VDB_MAGIC: Int = 1447313952;

/// Header size in bytes for supported file versions (222..225):
/// 8 magic + 4 file version + 4 library major + 4 library minor +
/// 1 has-grid-offsets flag + 36 UUID bytes.
pub const VDB_HEADER_BYTES: Int = 57;

/// Lowest supported file format version (mock-compression metadata byte).
pub const VDB_FILE_VERSION_MIN: Int = 222;

/// Highest supported file format version (this reader was built against the
/// v13.1.0 oracle, whose writer emits 225).
pub const VDB_FILE_VERSION_MAX: Int = 225;

/// Compression flag: no value compression (raw payloads).
pub const VDB_COMPRESS_NONE: Int = 0;

/// Compression flag: zlib deflate value chunks.
pub const VDB_COMPRESS_ZIP: Int = 1;

/// Compression flag: active-mask compression (inactive values are implicit).
pub const VDB_COMPRESS_ACTIVE_MASK: Int = 2;

/// Compression flag: blosc value chunks (structure readable, values not).
pub const VDB_COMPRESS_BLOSC: Int = 4;

/// Element kind: 32-bit float (also the storage type of half-float grids).
pub const VDB_ELEM_F32: Int = 1;

/// Element kind: 64-bit float.
pub const VDB_ELEM_F64: Int = 2;

/// Element kind: native IEEE-754 binary16 half grid.
pub const VDB_ELEM_F16: Int = 3;

/// Element kind: 3 x 32-bit float (Tree_vec3s).
pub const VDB_ELEM_VEC3F: Int = 4;

/// Element kind: 3 x 64-bit float (Tree_vec3d).
pub const VDB_ELEM_VEC3D: Int = 5;

/// Leaf node edge length in voxels.
pub const VDB_LEAF_DIM: Int = 8;

/// Voxels per leaf node (8^3).
pub const VDB_LEAF_VOXELS: Int = 512;

/// Bytes of one 512-bit node mask.
pub const VDB_LEAF_MASK_BYTES: Int = 64;

/// Transform map kind: 5 Vec3d, scale-only (UniformScaleMap, ScaleMap).
pub const VDB_MAP_KIND_SCALE: Int = 1;

/// Transform map kind: 6 Vec3d, translation + scale
/// (UniformScaleTranslateMap, ScaleTranslateMap).
pub const VDB_MAP_KIND_SCALE_TRANSLATE: Int = 2;

/// Transform map kind: 3 doubles, translation only (TranslationMap).
pub const VDB_MAP_KIND_TRANSLATION: Int = 3;

/// Transform map kind: 16 doubles, row-major 4x4 (AffineMap, UnitaryMap).
pub const VDB_MAP_KIND_AFFINE: Int = 4;

/// Error code: buffer too short for the 57-byte header.
pub const VDB_ERR_TRUNCATED_HEADER: Int = 1;

/// Error code: the 8-byte magic is not 0x56444220.
pub const VDB_ERR_BAD_MAGIC: Int = 2;

/// Error code: file version outside VDB_FILE_VERSION_MIN..MAX.
pub const VDB_ERR_UNSUPPORTED_VERSION: Int = 3;

/// Error code: a declared section extends past the end of the buffer.
pub const VDB_ERR_TRUNCATED: Int = 4;

/// Error code: a name/type/UUID string has non-printable or oversized bytes.
pub const VDB_ERR_BAD_NAME: Int = 5;

/// Error code: a count or length exceeds a documented sanity cap.
pub const VDB_ERR_LIMIT_EXCEEDED: Int = 6;

/// Error code: stream positions disagree with the walked structure.
pub const VDB_ERR_BAD_LAYOUT: Int = 7;

/// Error code: grid type is not one of the supported tree types.
pub const VDB_ERR_UNSUPPORTED_GRID_TYPE: Int = 8;

/// Error code: transform map type is not supported.
pub const VDB_ERR_UNSUPPORTED_TRANSFORM: Int = 9;

/// Error code: unknown compression flags or blosc value decode.
pub const VDB_ERR_UNSUPPORTED_COMPRESSION: Int = 10;

/// Error code: malformed zlib/deflate stream.
pub const VDB_ERR_ZIP_INVALID: Int = 11;

/// Error code: Adler-32 mismatch after inflate.
pub const VDB_ERR_ZIP_ADLER: Int = 12;

/// Error code: node metadata byte out of range or inconsistent masks.
pub const VDB_ERR_BAD_NODE_DATA: Int = 13;

/// Error code: an index argument is out of range.
pub const VDB_ERR_INDEX_OUT_OF_RANGE: Int = 14;

/// Error code: a typed metadata accessor was used on the wrong type.
pub const VDB_ERR_META_TYPE_MISMATCH: Int = 15;

/// Error code: the grid is an instance; read the parent grid instead.
pub const VDB_ERR_INSTANCE_GRID: Int = 16;

/// Error code: a typed metadata payload has the wrong byte count.
pub const VDB_ERR_META_BAD_SIZE: Int = 17;

// Per-node metadata byte values (OpenVDB io/Compression.h).
const _NM_NO_MASK_OR_INACTIVE_VALS: Int = 0;
const _NM_NO_MASK_AND_MINUS_BG: Int = 1;
const _NM_NO_MASK_AND_ONE_INACTIVE: Int = 2;
const _NM_MASK_AND_NO_INACTIVE: Int = 3;
const _NM_MASK_AND_ONE_INACTIVE: Int = 4;
const _NM_MASK_AND_TWO_INACTIVE: Int = 5;
const _NM_NO_MASK_AND_ALL_VALS: Int = 6;

// Sanity caps (typed VDB_ERR_LIMIT_EXCEEDED when exceeded).
const _CAP_STRING_BYTES: Int = 4096;
const _CAP_META_ITEMS: Int = 65536;
const _CAP_META_VALUE_BYTES: Int = 16777216;
const _CAP_GRIDS: Int = 65536;
const _CAP_LEAVES: Int = 1048576;
const _CAP_INFLATE_BYTES: Int = 16777216;

// ---------------------------------------------------------------------------
// Parsed structures
// ---------------------------------------------------------------------------

/// A typed error: stable numeric `code` (one of the VDB_ERR_* constants)
/// plus a human-readable `message`.
pub type VdbError = {
  code: Int;
  message: Str;
}

/// The 57-byte file header of a supported ".vdb" image.
pub type VdbHeader = {
  file_version: Int;      // 222..225
  library_major: Int;     // OpenVDB library major version
  library_minor: Int;     // OpenVDB library minor version
  has_grid_offsets: Bool; // true when per-grid stream positions are valid
  uuid: Str;              // 36 printable bytes, or "" when not printable
}

/// Flat index of one MetaMap (file-level or grid-level). Slot `i` has the
/// decoded printable-ASCII `names[i]`, its type `types[i]` ("string",
/// "int32", "float", ...) and an opaque value payload at absolute
/// `value_offsets[i]` that is `value_bytes[i]` long.
pub type VdbMetaMap = {
  count: Int;
  names: Vec[Str];
  types: Vec[Str];
  value_offsets: Vec[Int];
  value_bytes: Vec[Int];
  end: Int;               // absolute offset just past the map
}

/// The container-level view of a ".vdb" image: header, file metadata and
/// the grid descriptor table (parallel vectors; slot `i` is grid `i`).
/// Grid bodies are located by `body_offsets[i]` and parsed on demand by
/// `vdb_grid_meta`, `vdb_grid_transform` and `vdb_grid_tree`.
pub type VdbFile = {
  header: VdbHeader;
  meta: VdbMetaMap;
  grid_count: Int;
  unique_names: Vec[Str];   // raw stored names (with the 0x1E suffix)
  names: Vec[Str];          // names with the 0x1E suffix stripped
  types: Vec[Str];          // raw tree type names (may carry _HalfFloat)
  instance_parents: Vec[Str]; // "" for non-instances
  grid_pos: Vec[Int];       // i64 stream positions (0 when not seekable)
  block_pos: Vec[Int];
  end_pos: Vec[Int];
  body_offsets: Vec[Int];   // absolute offset of each grid body
}

/// A decoded grid transform. `voxel_size` is always 3 values (1,1,1 for
/// translation-only maps); `translation` is 3 values (0,0,0 when absent).
/// `map_kind` is one of the VDB_MAP_KIND_* constants.
pub type VdbTransform = {
  map_type: Str;
  map_kind: Int;
  voxel_size: Vec[Float64];
  translation: Vec[Float64];
  map_offset: Int;          // offset of the map payload (past the type name)
  map_end: Int;             // absolute offset just past the map payload
}

/// Decoded tree topology. Leaves are indexed in file (depth-first) order:
/// leaf `k` has origin (origins[3k], origins[3k+1], origins[3k+2]) and its
/// buffer starts at `buffer_offsets[k]`. `background` is the root
/// background value (per-component for vectors). Structural tile values
/// are walked and validated but not exposed.
pub type VdbTree = {
  grid_index: Int;
  element_kind: Int;        // VDB_ELEM_*
  from_half: Bool;          // stored as binary16 halves (float/vec3f grids)
  components: Int;          // 1 or 3
  compression: Int;         // raw u32 compression flags of the grid
  leaf_count: Int;
  origins: Vec[Int];        // 3 per leaf
  buffer_offsets: Vec[Int]; // 1 per leaf
  background: Vec[Float64]; // components long
  background_bits: Vec[Int];// components long; raw storage-width patterns
  root_tile_count: Int;
  root_child_count: Int;
  topology_offset: Int;
  topology_end: Int;
  buffers_offset: Int;
  buffers_end: Int;
}

/// One decoded dense leaf block: the 64-byte value mask (`active`), the raw
/// (decompressed) payload bytes of the stored values, and the full
/// 8x8x8 value block with inactive values reconstructed. `values` has
/// VDB_LEAF_VOXELS * components entries, component-interleaved; index
/// `offset * components + c` corresponds to local voxel offset
/// `x*64 + y*8 + z` (x fastest), which maps to global voxels
/// (origin_x + x, origin_y + y, origin_z + z).
pub type VdbLeaf = {
  leaf_index: Int;
  origin: Vec[Int];         // 3 values
  active: Vec[UInt8];       // 64 bytes of the value mask
  metadata: Int;            // mask-compression metadata byte (0..6)
  value_count: Int;         // always 512
  components: Int;          // 1 or 3
  element_kind: Int;
  from_half: Bool;
  logical_width: Int;       // bytes per value in the logical type
  payload_width: Int;       // bytes per stored value (2 when from_half)
  payload: Vec[UInt8];      // decompressed stored payload (active subset)
  values: Vec[Float64];     // 512 * components reconstructed values
}

/// Flat voxel outcome (no Result[Option] shapes): `found` is false when no
/// leaf contains the coordinate, in which case `values` is empty and the
/// voxel is background/unknown.
pub type VdbVoxel = {
  found: Bool;
  active: Bool;
  components: Int;
  values: Vec[Float64];     // components long when found
}

// A length-prefixed decoded string plus its end offset (internal).
type _StrSpan = {
  value: Str;
  next: Int;
}

// Topology walk result (internal).
type _TreeCore = {
  leaf_count: Int;
  origins: Vec[Int];
  background: Vec[Float64];
  background_bits: Vec[Int];
  root_tile_count: Int;
  root_child_count: Int;
  end: Int;
}

// ---------------------------------------------------------------------------
// Result leaf constructors (v0.64.4: Ok/Err are built only in functions that
// return a Result directly, so every fallible function returns through one
// of these tiny constructors).
// ---------------------------------------------------------------------------

fn _err_hdr(code: Int, message: Str) -> Result[VdbHeader, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_hdr(h: VdbHeader) -> Result[VdbHeader, VdbError] { return Ok(h); }

fn _err_file(code: Int, message: Str) -> Result[VdbFile, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_file(f: VdbFile) -> Result[VdbFile, VdbError] { return Ok(f); }

fn _err_meta(code: Int, message: Str) -> Result[VdbMetaMap, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_meta(m: VdbMetaMap) -> Result[VdbMetaMap, VdbError] { return Ok(m); }

fn _err_xform(code: Int, message: Str) -> Result[VdbTransform, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_xform(t: VdbTransform) -> Result[VdbTransform, VdbError] { return Ok(t); }

fn _err_tree(code: Int, message: Str) -> Result[VdbTree, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_tree(t: VdbTree) -> Result[VdbTree, VdbError] { return Ok(t); }

fn _err_leaf(code: Int, message: Str) -> Result[VdbLeaf, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_leaf(l: VdbLeaf) -> Result[VdbLeaf, VdbError] { return Ok(l); }

fn _err_voxel(code: Int, message: Str) -> Result[VdbVoxel, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_voxel(v: VdbVoxel) -> Result[VdbVoxel, VdbError] { return Ok(v); }

fn _err_bytes(code: Int, message: Str) -> Result[Vec[UInt8], VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], VdbError] { return Ok(v); }

fn _err_str(code: Int, message: Str) -> Result[Str, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_str(s: Str) -> Result[Str, VdbError] { return Ok(s); }

fn _err_int(code: Int, message: Str) -> Result[Int, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_int(n: Int) -> Result[Int, VdbError] { return Ok(n); }

fn _err_bool(code: Int, message: Str) -> Result[Bool, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_bool(b: Bool) -> Result[Bool, VdbError] { return Ok(b); }

fn _err_f64(code: Int, message: Str) -> Result[Float64, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_f64(x: Float64) -> Result[Float64, VdbError] { return Ok(x); }

fn _err_span(code: Int, message: Str) -> Result[_StrSpan, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_span(s: _StrSpan) -> Result[_StrSpan, VdbError] { return Ok(s); }

fn _err_core(code: Int, message: Str) -> Result[_TreeCore, VdbError] {
  return Err(VdbError{ code: code; message: message; });
}
fn _ok_core(c: _TreeCore) -> Result[_TreeCore, VdbError] { return Ok(c); }

// ---------------------------------------------------------------------------
// Byte readers (callers establish bounds; every reader masks to its width)
// ---------------------------------------------------------------------------

// Unsigned byte at `i`, widened and masked to 0..255.
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Unsigned little-endian u16 at `off`.
fn _u16le(data: &Vec[UInt8], off: Int) -> Int {
  let b0: Int = _b(data, off);
  let b1: Int = _b(data, off + 1);
  return b0 + b1 * 256;
}

// Unsigned little-endian u32 at `off`.
fn _u32le(data: &Vec[UInt8], off: Int) -> Int {
  let b0: Int = _b(data, off);
  let b1: Int = _b(data, off + 1);
  let b2: Int = _b(data, off + 2);
  let b3: Int = _b(data, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Signed little-endian i32 at `off` (used for node origins).
fn _i32le(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = _u32le(data, off);
  if v >= 2147483648 {
    v = v - 4294967296;
  }
  return v;
}

// Unsigned little-endian u64 at `off` (positions; values < 2^56 in practice
// keep this exact in a signed Int).
fn _u64le(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = 0;
  var shift: Int = 1;
  var i = 0;
  while i < 8 {
    let b: Int = _b(data, off + i);
    v = v + b * shift;
    shift = shift * 256;
    i = i + 1;
  }
  return v;
}

// Signed little-endian i64 at `off` (zip/blosc chunk-size prefixes).
fn _i64le(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = 0;
  var shift: Int = 1;
  var i = 0;
  while i < 7 {
    let b: Int = _b(data, off + i);
    v = v + b * shift;
    shift = shift * 256;
    i = i + 1;
  }
  let top: Int = _b(data, off + 7);
  v = v + (top - 256) * shift;
  return v;
}

// Raw u32 bit pattern of a 32-bit float at `off`.
fn _f32_bits_at(data: &Vec[UInt8], off: Int) -> Int {
  return _u32le(data, off);
}

// Raw u16 bit pattern of a binary16 half at `off`.
fn _f16_bits_at(data: &Vec[UInt8], off: Int) -> Int {
  return _u16le(data, off);
}

// Raw u64 bit pattern of a 64-bit double at `off` (as a signed Int; the
// bit pattern is preserved bit-for-bit through two's-complement wrapping).
fn _f64_bits_at(data: &Vec[UInt8], off: Int) -> Int {
  return _u64le(data, off);
}

// ---------------------------------------------------------------------------
// IEEE-754 decoding
// ---------------------------------------------------------------------------

// Exact float32 -> Float64 conversion from the raw 32-bit pattern. Normal
// and special values are expanded to a 64-bit pattern and bitcast; the few
// float32 subnormals are computed arithmetically (man * 2^-149, exact in
// binary64). Negative zero is reconstructed exactly.
fn _f32_to_f64(bits32: Int) -> Float64 {
  let sign: Int = (bits32 / 2147483648) % 2;
  let exp32: Int = (bits32 / 8388608) % 256;
  let man: Int = bits32 % 8388608;
  if exp32 == 0 {
    if man == 0 {
      if sign == 1 {
        return bits_to_float(0 - 9223372036854775807 - 1);
      }
      return 0.0;
    }
    let m: Float64 = man as Float64;
    let v: Float64 = m * 1.401298464324817e-45;
    if sign == 1 {
      return 0.0 - v;
    }
    return v;
  }
  var bits64: Int = (exp32 + 896) * 4503599627370496 + man * 536870912;
  if sign == 1 {
    bits64 = bits64 + (0 - 9223372036854775807 - 1);
  }
  return bits_to_float(bits64);
}

// Exact binary16 -> Float64 conversion from the raw 16-bit pattern.
// Subnormals are man * 2^-24 (exact); inf/NaN keep their sign/payload in
// the widened pattern.
fn _f16_to_f64(bits16: Int) -> Float64 {
  let sign: Int = (bits16 / 32768) % 2;
  let exp5: Int = (bits16 / 1024) % 32;
  let man: Int = bits16 % 1024;
  if exp5 == 0 {
    if man == 0 {
      if sign == 1 {
        return bits_to_float(0 - 9223372036854775807 - 1);
      }
      return 0.0;
    }
    let m: Float64 = man as Float64;
    let v: Float64 = m * 5.960464477539063e-8;
    if sign == 1 {
      return 0.0 - v;
    }
    return v;
  }
  if exp5 == 31 {
    var bits64: Int = 2047 * 4503599627370496 + man * 4398046511104;
    if sign == 1 {
      bits64 = bits64 + (0 - 9223372036854775807 - 1);
    }
    return bits_to_float(bits64);
  }
  var bits64: Int = (exp5 + 1008) * 4503599627370496 + man * 4398046511104;
  if sign == 1 {
    bits64 = bits64 + (0 - 9223372036854775807 - 1);
  }
  return bits_to_float(bits64);
}

// ---------------------------------------------------------------------------
// Grid type dispatch and element geometry
// ---------------------------------------------------------------------------

fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Element kind of a supported tree type name, or 0 when unsupported.
fn _grid_kind(t: Str) -> Int {
  if _str_eq(t, "Tree_float_5_4_3") { return VDB_ELEM_F32; }
  if _str_eq(t, "Tree_float_5_4_3_HalfFloat") { return VDB_ELEM_F32; }
  if _str_eq(t, "Tree_double_5_4_3") { return VDB_ELEM_F64; }
  if _str_eq(t, "Tree_half_5_4_3") { return VDB_ELEM_F16; }
  if _str_eq(t, "Tree_vec3s_5_4_3") { return VDB_ELEM_VEC3F; }
  if _str_eq(t, "Tree_vec3s_5_4_3_HalfFloat") { return VDB_ELEM_VEC3F; }
  if _str_eq(t, "Tree_vec3d_5_4_3") { return VDB_ELEM_VEC3D; }
  return 0;
}

// True when the stored values are binary16 halves (`_HalfFloat` suffix).
fn _grid_from_half(t: Str) -> Bool {
  if _str_eq(t, "Tree_float_5_4_3_HalfFloat") { return true; }
  if _str_eq(t, "Tree_vec3s_5_4_3_HalfFloat") { return true; }
  return false;
}

// Bytes per value in the logical (in-file reduced) type.
fn _logical_width(kind: Int) -> Int {
  if kind == VDB_ELEM_F32 { return 4; }
  if kind == VDB_ELEM_F64 { return 8; }
  if kind == VDB_ELEM_F16 { return 2; }
  if kind == VDB_ELEM_VEC3F { return 12; }
  if kind == VDB_ELEM_VEC3D { return 24; }
  return 0;
}

// Bytes per stored value in the payload (2/6 for half-storage floats).
fn _payload_width(kind: Int, from_half: Bool) -> Int {
  if from_half {
    if kind == VDB_ELEM_F32 { return 2; }
    if kind == VDB_ELEM_VEC3F { return 6; }
  }
  return _logical_width(kind);
}

// Components per voxel (3 for vector grids).
fn _components_of(kind: Int) -> Int {
  if kind == VDB_ELEM_VEC3F { return 3; }
  if kind == VDB_ELEM_VEC3D { return 3; }
  return 1;
}

// ---------------------------------------------------------------------------
// Strings and names
// ---------------------------------------------------------------------------

// Printable ASCII (0x20..0x7E) only: names and types in this reader.
fn _printable(b: Int) -> Bool {
  return b >= 32 && b <= 126;
}

// Length-prefixed name/type/UUID-safe string: u32 byte count + bytes. Every
// byte must be printable ASCII; the decoded Str starts at `off + 4`.
fn _str_span(data: &Vec[UInt8], off: Int) -> Result[_StrSpan, VdbError] {
  if off < 0 || off + 4 > data.len() {
    return _err_span(VDB_ERR_TRUNCATED, "vdb: truncated string header");
  }
  let n: Int = _u32le(data, off);
  if n > _CAP_STRING_BYTES {
    return _err_span(VDB_ERR_LIMIT_EXCEEDED, "vdb: string longer than the 4096-byte cap");
  }
  let start: Int = off + 4;
  if start + n > data.len() {
    return _err_span(VDB_ERR_TRUNCATED, "vdb: truncated string body");
  }
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b: Int = _b(data, start + i);
    if !_printable(b) {
      return _err_span(VDB_ERR_BAD_NAME, "vdb: non-printable name/type byte");
    }
    bytes.push(b as UInt8);
    i = i + 1;
  }
  return _ok_span(_StrSpan{ value: Str::from_utf8(bytes); next: start + n; });
}

// Decode `n` bytes at `off` as printable ASCII into a fresh Str.
fn _ascii_str(data: &Vec[UInt8], off: Int, n: Int) -> Result[Str, VdbError] {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b: Int = _b(data, off + i);
    if !_printable(b) {
      return _err_str(VDB_ERR_BAD_NAME, "vdb: non-printable metadata string byte");
    }
    bytes.push(b as UInt8);
    i = i + 1;
  }
  return _ok_str(Str::from_utf8(bytes));
}

// Strip the OpenVDB 0x1E ("record separator") duplicate-name suffix.
fn _strip_suffix(s: Str) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  let n = s.len();
  var done = false;
  while i < n && !done {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 30 {
      done = true;
    } else {
      bytes.push(b as UInt8);
      i = i + 1;
    }
  }
  return Str::from_utf8(bytes);
}

// ---------------------------------------------------------------------------
// MetaMap parsing
// ---------------------------------------------------------------------------

/// Number of metadata items in a map.
pub fn vdb_meta_count(m: &VdbMetaMap) -> Int {
  return m.count;
}

/// Name of metadata item `i` ("" when out of range).
pub fn vdb_meta_name(m: &VdbMetaMap, i: Int) -> Str {
  if i < 0 || i >= m.names.len() {
    return "";
  }
  let s: Str = m.names[i];
  return s;
}

/// Type name of metadata item `i` ("" when out of range).
pub fn vdb_meta_type(m: &VdbMetaMap, i: Int) -> Str {
  if i < 0 || i >= m.types.len() {
    return "";
  }
  let s: Str = m.types[i];
  return s;
}

/// Absolute offset of metadata item `i`'s value payload (-1 out of range).
pub fn vdb_meta_value_offset(m: &VdbMetaMap, i: Int) -> Int {
  if i < 0 || i >= m.value_offsets.len() {
    return -1;
  }
  let v: Int = m.value_offsets[i];
  return v;
}

/// Byte count of metadata item `i`'s value payload (-1 out of range).
pub fn vdb_meta_value_bytes(m: &VdbMetaMap, i: Int) -> Int {
  if i < 0 || i >= m.value_bytes.len() {
    return -1;
  }
  let v: Int = m.value_bytes[i];
  return v;
}

/// Index of the first metadata item named `name`, or -1.
pub fn vdb_meta_find(m: &VdbMetaMap, name: Str) -> Int {
  var i = 0;
  while i < m.names.len() {
    let s: Str = m.names[i];
    if _str_eq(s, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Parse a MetaMap: u32 count, then per item a length-prefixed name, a
// length-prefixed type, and a u32-sized opaque value payload.
fn _parse_metamap(data: &Vec[UInt8], off: Int) -> Result[VdbMetaMap, VdbError] {
  if off < 0 || off + 4 > data.len() {
    return _err_meta(VDB_ERR_TRUNCATED, "vdb: truncated metadata count");
  }
  let count: Int = _u32le(data, off);
  if count > _CAP_META_ITEMS {
    return _err_meta(VDB_ERR_LIMIT_EXCEEDED, "vdb: metadata item count over the 65536 cap");
  }
  var names = Vec[Str].new();
  var types = Vec[Str].new();
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  var pos: Int = off + 4;
  var i = 0;
  while i < count {
    let snr = _str_span(data, pos);
    if snr.is_err { return _err_meta(snr.error.code, snr.error.message); }
    let sn = snr.value;
    pos = sn.next;
    names.push(sn.value);
    let str_ = _str_span(data, pos);
    if str_.is_err { return _err_meta(str_.error.code, str_.error.message); }
    let st = str_.value;
    pos = st.next;
    types.push(st.value);
    if pos + 4 > data.len() {
      return _err_meta(VDB_ERR_TRUNCATED, "vdb: truncated metadata value size");
    }
    let nbytes: Int = _u32le(data, pos);
    pos = pos + 4;
    if nbytes > _CAP_META_VALUE_BYTES {
      return _err_meta(VDB_ERR_LIMIT_EXCEEDED, "vdb: metadata value over the 16 MiB cap");
    }
    if pos + nbytes > data.len() {
      return _err_meta(VDB_ERR_TRUNCATED, "vdb: truncated metadata value");
    }
    offsets.push(pos);
    lengths.push(nbytes);
    pos = pos + nbytes;
    i = i + 1;
  }
  return _ok_meta(VdbMetaMap{
    count: count;
    names: names;
    types: types;
    value_offsets: offsets;
    value_bytes: lengths;
    end: pos;
  });
}

/// Copy metadata item `i`'s opaque value payload out of the buffer.
pub fn vdb_meta_value(data: &Vec[UInt8], m: &VdbMetaMap, i: Int) -> Result[Vec[UInt8], VdbError] {
  if i < 0 || i >= m.count {
    return _err_bytes(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: metadata index out of range");
  }
  let foff: Int = m.value_offsets[i];
  let flen: Int = m.value_bytes[i];
  if foff < 0 || foff + flen > data.len() {
    return _err_bytes(VDB_ERR_TRUNCATED, "vdb: metadata value outside the buffer");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < flen {
    out.push(data[foff + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// Require metadata item `i` to have the given type name and payload size.
fn _meta_require(data: &Vec[UInt8], m: &VdbMetaMap, i: Int, want_type: Str, want_bytes: Int) -> Result[Int, VdbError] {
  if i < 0 || i >= m.count {
    return _err_int(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: metadata index out of range");
  }
  let t: Str = m.types[i];
  if !_str_eq(t, want_type) {
    return _err_int(VDB_ERR_META_TYPE_MISMATCH, "vdb: metadata type mismatch");
  }
  let flen: Int = m.value_bytes[i];
  if flen != want_bytes {
    return _err_int(VDB_ERR_META_BAD_SIZE, "vdb: metadata payload size mismatch");
  }
  let foff: Int = m.value_offsets[i];
  if foff < 0 || foff + flen > data.len() {
    return _err_int(VDB_ERR_TRUNCATED, "vdb: metadata value outside the buffer");
  }
  return _ok_int(foff);
}

/// Decode a "string" metadata item (used for the grid class and creator).
pub fn vdb_meta_string(data: &Vec[UInt8], m: &VdbMetaMap, i: Int) -> Result[Str, VdbError] {
  if i < 0 || i >= m.count {
    return _err_str(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: metadata index out of range");
  }
  let t: Str = m.types[i];
  if !_str_eq(t, "string") {
    return _err_str(VDB_ERR_META_TYPE_MISMATCH, "vdb: metadata is not a string");
  }
  let foff: Int = m.value_offsets[i];
  let flen: Int = m.value_bytes[i];
  if foff < 0 || foff + flen > data.len() {
    return _err_str(VDB_ERR_TRUNCATED, "vdb: metadata value outside the buffer");
  }
  return _ascii_str(data, foff, flen);
}

/// Decode an integer-valued metadata item ("int32", "int64" or "bool").
pub fn vdb_meta_int(data: &Vec[UInt8], m: &VdbMetaMap, i: Int) -> Result[Int, VdbError] {
  if i < 0 || i >= m.count {
    return _err_int(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: metadata index out of range");
  }
  let t: Str = m.types[i];
  if _str_eq(t, "int32") {
    let mrr = _meta_require(data, m, i, "int32", 4);
    if mrr.is_err { return _err_int(mrr.error.code, mrr.error.message); }
    let foff: Int = mrr.value;
    var v: Int = _u32le(data, foff);
    if v >= 2147483648 {
      v = v - 4294967296;
    }
    return _ok_int(v);
  }
  if _str_eq(t, "int64") {
    let mrr = _meta_require(data, m, i, "int64", 8);
    if mrr.is_err { return _err_int(mrr.error.code, mrr.error.message); }
    let foff: Int = mrr.value;
    return _ok_int(_u64le(data, foff));
  }
  if _str_eq(t, "bool") {
    let mrr = _meta_require(data, m, i, "bool", 1);
    if mrr.is_err { return _err_int(mrr.error.code, mrr.error.message); }
    let foff: Int = mrr.value;
    let v: Int = _b(data, foff);
    if v == 0 { return _ok_int(0); }
    return _ok_int(1);
  }
  return _err_int(VDB_ERR_META_TYPE_MISMATCH, "vdb: metadata is not an integer type");
}

/// Decode a boolean metadata item ("bool").
pub fn vdb_meta_bool(data: &Vec[UInt8], m: &VdbMetaMap, i: Int) -> Result[Bool, VdbError] {
  let ir = vdb_meta_int(data, m, i);
  if ir.is_err { return _err_bool(ir.error.code, ir.error.message); }
  return _ok_bool(ir.value != 0);
}

/// Decode a floating-point metadata item ("float" or "double").
pub fn vdb_meta_float(data: &Vec[UInt8], m: &VdbMetaMap, i: Int) -> Result[Float64, VdbError] {
  if i < 0 || i >= m.count {
    return _err_f64(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: metadata index out of range");
  }
  let t: Str = m.types[i];
  if _str_eq(t, "float") {
    let mrr = _meta_require(data, m, i, "float", 4);
    if mrr.is_err { return _err_f64(mrr.error.code, mrr.error.message); }
    let foff: Int = mrr.value;
    return _ok_f64(_f32_to_f64(_f32_bits_at(data, foff)));
  }
  if _str_eq(t, "double") {
    let mrr = _meta_require(data, m, i, "double", 8);
    if mrr.is_err { return _err_f64(mrr.error.code, mrr.error.message); }
    let foff: Int = mrr.value;
    return _ok_f64(bits_to_float(_f64_bits_at(data, foff)));
  }
  return _err_f64(VDB_ERR_META_TYPE_MISMATCH, "vdb: metadata is not a floating-point type");
}

// ---------------------------------------------------------------------------
// Transform parsing
// ---------------------------------------------------------------------------

// Push the little-endian double at `off` onto `out`.
fn _push_f64(data: &Vec[UInt8], off: Int, out: &mut Vec[Float64]) {
  out.push(bits_to_float(_f64_bits_at(data, off)));
}

// Map kind of a transform type name (0 = unsupported).
fn _map_kind(t: Str) -> Int {
  if _str_eq(t, "UniformScaleMap") { return VDB_MAP_KIND_SCALE; }
  if _str_eq(t, "ScaleMap") { return VDB_MAP_KIND_SCALE; }
  if _str_eq(t, "UniformScaleTranslateMap") { return VDB_MAP_KIND_SCALE_TRANSLATE; }
  if _str_eq(t, "ScaleTranslateMap") { return VDB_MAP_KIND_SCALE_TRANSLATE; }
  if _str_eq(t, "TranslationMap") { return VDB_MAP_KIND_TRANSLATION; }
  if _str_eq(t, "AffineMap") { return VDB_MAP_KIND_AFFINE; }
  if _str_eq(t, "UnitaryMap") { return VDB_MAP_KIND_AFFINE; }
  return 0;
}

// Payload size in bytes of a map kind.
fn _map_bytes(kind: Int) -> Int {
  if kind == VDB_MAP_KIND_SCALE { return 120; }
  if kind == VDB_MAP_KIND_SCALE_TRANSLATE { return 144; }
  if kind == VDB_MAP_KIND_TRANSLATION { return 24; }
  if kind == VDB_MAP_KIND_AFFINE { return 128; }
  return 0;
}

// Parse the grid transform: length-prefixed map type name + fixed-size map
// payload. Voxel size is taken from the stored mVoxelSize vector for scale
// maps, (1,1,1) for TranslationMap, and the norms of the three matrix
// columns for AffineMap/UnitaryMap.
fn _parse_transform(data: &Vec[UInt8], off: Int) -> Result[VdbTransform, VdbError] {
  let snr = _str_span(data, off);
  if snr.is_err { return _err_xform(snr.error.code, snr.error.message); }
  let sn = snr.value;
  let map_type: Str = sn.value;
  let mk: Int = _map_kind(map_type);
  if mk == 0 {
    return _err_xform(VDB_ERR_UNSUPPORTED_TRANSFORM, "vdb: unsupported transform map: " + map_type);
  }
  let pos: Int = sn.next;
  let need: Int = _map_bytes(mk);
  if pos + need > data.len() {
    return _err_xform(VDB_ERR_TRUNCATED, "vdb: truncated transform payload");
  }
  var vox = Vec[Float64].new();
  var tr = Vec[Float64].new();
  if mk == VDB_MAP_KIND_SCALE {
    _push_f64(data, pos + 24, &mut vox);
    _push_f64(data, pos + 32, &mut vox);
    _push_f64(data, pos + 40, &mut vox);
    tr.push(0.0); tr.push(0.0); tr.push(0.0);
  } elif mk == VDB_MAP_KIND_SCALE_TRANSLATE {
    _push_f64(data, pos + 0, &mut tr);
    _push_f64(data, pos + 8, &mut tr);
    _push_f64(data, pos + 16, &mut tr);
    _push_f64(data, pos + 48, &mut vox);
    _push_f64(data, pos + 56, &mut vox);
    _push_f64(data, pos + 64, &mut vox);
  } elif mk == VDB_MAP_KIND_TRANSLATION {
    _push_f64(data, pos + 0, &mut tr);
    _push_f64(data, pos + 8, &mut tr);
    _push_f64(data, pos + 16, &mut tr);
    vox.push(1.0); vox.push(1.0); vox.push(1.0);
  } else {
    _push_f64(data, pos + 24, &mut tr);
    _push_f64(data, pos + 56, &mut tr);
    _push_f64(data, pos + 88, &mut tr);
    let c0 = _col_norm(data, pos, 0);
    let c1 = _col_norm(data, pos, 1);
    let c2 = _col_norm(data, pos, 2);
    vox.push(c0); vox.push(c1); vox.push(c2);
  }
  return _ok_xform(VdbTransform{
    map_type: map_type;
    map_kind: mk;
    voxel_size: vox;
    translation: tr;
    map_offset: pos;
    map_end: pos + need;
  });
}

// Norm of column `col` of the row-major Mat4d at `base` (doubles).
fn _col_norm(data: &Vec[UInt8], base: Int, col: Int) -> Float64 {
  let a: Float64 = bits_to_float(_f64_bits_at(data, base + col * 8));
  let b: Float64 = bits_to_float(_f64_bits_at(data, base + 32 + col * 8));
  let c: Float64 = bits_to_float(_f64_bits_at(data, base + 64 + col * 8));
  return math.sqrt(a * a + b * b + c * c);
}

// ---------------------------------------------------------------------------
// Node masks and value skipping
// ---------------------------------------------------------------------------

// 2^k for k >= 0 (small exponents only; used for node dimensions).
fn _pow2(k: Int) -> Int {
  var d: Int = 1;
  var i = 0;
  while i < k {
    d = d * 2;
    i = i + 1;
  }
  return d;
}

// Raw byte size of a node mask with the given log2 dimension.
fn _mask_bytes(log2dim: Int) -> Int {
  return _pow2(3 * log2dim - 3);
}

// Bit `bit` of the mask whose first byte is at `mask_off`
// (little-endian 64-bit words; bit n lives in byte n>>3, bit n&7).
fn _mask_on(data: &Vec[UInt8], mask_off: Int, bit: Int) -> Bool {
  let byte_i: Int = mask_off + (bit >> 3);
  if byte_i < 0 || byte_i >= data.len() {
    return false;
  }
  let b: Int = _b(data, byte_i);
  return ((b >> (bit & 7)) & 1) == 1;
}

// Number of on bits in a `bits`-bit mask starting at `mask_off`.
fn _mask_count_on(data: &Vec[UInt8], mask_off: Int, bits: Int) -> Int {
  let nbytes: Int = (bits + 7) / 8;
  var count = 0;
  var i = 0;
  while i < nbytes {
    let b: Int = _b(data, mask_off + i);
    var k = 0;
    while k < 8 {
      count = count + ((b >> k) & 1);
      k = k + 1;
    }
    i = i + 1;
  }
  return count;
}

// Skip one node's compressed value payload (topology walk; values are not
// decoded). Consumes the metadata byte, any saved inactive values, any
// selection mask and the payload chunk itself, then returns the offset
// just past the payload.
fn _skip_values(data: &Vec[UInt8], pos: Int, num_values: Int, mask_compressed: Bool,
    mask_off: Int, mask_bits: Int, logical_w: Int, payload_w: Int, comp: Int) -> Result[Int, VdbError] {
  var p: Int = pos;
  if p + 1 > data.len() {
    return _err_int(VDB_ERR_TRUNCATED, "vdb: truncated node value header");
  }
  let metadata: Int = _b(data, p);
  p = p + 1;
  if metadata > _NM_NO_MASK_AND_ALL_VALS {
    return _err_int(VDB_ERR_BAD_NODE_DATA, "vdb: node metadata byte out of range");
  }
  if metadata == _NM_NO_MASK_AND_ONE_INACTIVE || metadata == _NM_MASK_AND_ONE_INACTIVE {
    p = p + logical_w;
  }
  if metadata == _NM_MASK_AND_TWO_INACTIVE {
    p = p + 2 * logical_w;
  }
  if metadata == _NM_MASK_AND_NO_INACTIVE || metadata == _NM_MASK_AND_ONE_INACTIVE || metadata == _NM_MASK_AND_TWO_INACTIVE {
    p = p + (mask_bits + 7) / 8;
  }
  if p > data.len() {
    return _err_int(VDB_ERR_TRUNCATED, "vdb: truncated node value metadata");
  }
  if (comp & (VDB_COMPRESS_ZIP + VDB_COMPRESS_BLOSC)) != 0 {
    if p + 8 > data.len() {
      return _err_int(VDB_ERR_TRUNCATED, "vdb: truncated compression chunk size");
    }
    let n: Int = _i64le(data, p);
    p = p + 8;
    if n <= 0 {
      let raw: Int = 0 - n;
      if p + raw > data.len() {
        return _err_int(VDB_ERR_TRUNCATED, "vdb: raw chunk beyond the buffer");
      }
      p = p + raw;
    } else {
      if p + n > data.len() {
        return _err_int(VDB_ERR_TRUNCATED, "vdb: compressed chunk beyond the buffer");
      }
      p = p + n;
    }
  } else {
    var count: Int = num_values;
    if mask_compressed && metadata != _NM_NO_MASK_AND_ALL_VALS {
      count = _mask_count_on(data, mask_off, mask_bits);
    }
    let span: Int = count * payload_w;
    if p + span > data.len() {
      return _err_int(VDB_ERR_TRUNCATED, "vdb: raw values beyond the buffer");
    }
    p = p + span;
  }
  return _ok_int(p);
}

// Push the logical-type element at `off` (per-component bits and decoded
// values). `from_half` selects the binary16 storage of float/vec3f payloads;
// backgrounds and inactive values are always logical-width (from_half false).
fn _push_element(data: &Vec[UInt8], off: Int, kind: Int, from_half: Bool,
    values: &mut Vec[Float64], bits: &mut Vec[Int]) {
  if kind == VDB_ELEM_F32 {
    if from_half {
      let h: Int = _f16_bits_at(data, off);
      bits.push(h);
      values.push(_f16_to_f64(h));
    } else {
      let w: Int = _f32_bits_at(data, off);
      bits.push(w);
      values.push(_f32_to_f64(w));
    }
  } elif kind == VDB_ELEM_F64 {
    let w: Int = _f64_bits_at(data, off);
    bits.push(w);
    values.push(bits_to_float(w));
  } elif kind == VDB_ELEM_F16 {
    let h: Int = _f16_bits_at(data, off);
    bits.push(h);
    values.push(_f16_to_f64(h));
  } elif kind == VDB_ELEM_VEC3F {
    var step = 4;
    if from_half {
      step = 2;
    }
    var c = 0;
    while c < 3 {
      _push_element(data, off + c * step, VDB_ELEM_F32, from_half, values, bits);
      c = c + 1;
    }
  } else {
    var c = 0;
    while c < 3 {
      _push_element(data, off + c * 8, VDB_ELEM_F64, from_half, values, bits);
      c = c + 1;
    }
  }
}

// Child-node log2 dimension for the fixed 5/4/3 node chain: an L5 node's
// children span 2^7 voxels per axis, an L4 node's children span 2^3.
fn _child_total(log2dim: Int) -> Int {
  if log2dim == 5 {
    return 7;
  }
  return 3;
}

// Walk one node (internal cluster or leaf) in file order, appending leaf
// origins to `origins` (3 per leaf). Returns the offset just past the node.
fn _walk_node(data: &Vec[UInt8], off: Int, log2dim: Int, ox: Int, oy: Int, oz: Int,
    kind: Int, from_half: Bool, comp: Int, origins: &mut Vec[Int]) -> Result[Int, VdbError] {
  if log2dim == 3 {
    if off + VDB_LEAF_MASK_BYTES > data.len() {
      return _err_int(VDB_ERR_TRUNCATED, "vdb: truncated leaf value mask");
    }
    if origins.len() / 3 >= _CAP_LEAVES {
      return _err_int(VDB_ERR_LIMIT_EXCEEDED, "vdb: leaf count over the 1048576 cap");
    }
    origins.push(ox);
    origins.push(oy);
    origins.push(oz);
    return _ok_int(off + VDB_LEAF_MASK_BYTES);
  }
  let mn: Int = _mask_bytes(log2dim);
  if off + 2 * mn > data.len() {
    return _err_int(VDB_ERR_TRUNCATED, "vdb: truncated node masks");
  }
  let value_mask_off: Int = off + mn;
  let nv: Int = _pow2(3 * log2dim);
  let logical_w: Int = _logical_width(kind);
  let payload_w: Int = _payload_width(kind, from_half);
  let mask_compressed: Bool = (comp & VDB_COMPRESS_ACTIVE_MASK) != 0;
  let sr = _skip_values(data, off + 2 * mn, nv, mask_compressed,
      value_mask_off, nv, logical_w, payload_w, comp);
  if sr.is_err { return _err_int(sr.error.code, sr.error.message); }
  var pos: Int = sr.value;
  let dim: Int = _pow2(log2dim);
  let span: Int = _pow2(_child_total(log2dim));
  var n = 0;
  while n < nv {
    if _mask_on(data, off, n) {
      let lx: Int = n / (dim * dim);
      let rem: Int = n % (dim * dim);
      let ly: Int = rem / dim;
      let lz: Int = rem % dim;
      let cr = _walk_node(data, pos, log2dim - 1, ox + lx * span, oy + ly * span, oz + lz * span,
          kind, from_half, comp, origins);
      if cr.is_err { return _err_int(cr.error.code, cr.error.message); }
      pos = cr.value;
    }
    n = n + 1;
  }
  return _ok_int(pos);
}

// Parse a tree topology section: i32 buffer count (must be 1), root
// background, root tile/child counts, root tiles, then children depth-first.
fn _parse_topology(data: &Vec[UInt8], off: Int, kind: Int, from_half: Bool, comp: Int) -> Result[_TreeCore, VdbError] {
  if off < 0 || off + 4 > data.len() {
    return _err_core(VDB_ERR_TRUNCATED, "vdb: truncated topology header");
  }
  let buffers: Int = _u32le(data, off);
  if buffers != 1 {
    return _err_core(VDB_ERR_BAD_LAYOUT, "vdb: multi-buffer trees are not supported");
  }
  var pos: Int = off + 4;
  let logical_w: Int = _logical_width(kind);
  if pos + logical_w > data.len() {
    return _err_core(VDB_ERR_TRUNCATED, "vdb: truncated root background value");
  }
  var bg = Vec[Float64].new();
  var bgbits = Vec[Int].new();
  _push_element(data, pos, kind, false, &mut bg, &mut bgbits);
  pos = pos + logical_w;
  if pos + 8 > data.len() {
    return _err_core(VDB_ERR_TRUNCATED, "vdb: truncated root counts");
  }
  let ntiles: Int = _u32le(data, pos);
  let nchildren: Int = _u32le(data, pos + 4);
  pos = pos + 8;
  var ti = 0;
  while ti < ntiles {
    if pos + 12 + logical_w + 1 > data.len() {
      return _err_core(VDB_ERR_TRUNCATED, "vdb: truncated root tile record");
    }
    pos = pos + 12 + logical_w + 1;
    ti = ti + 1;
  }
  var origins = Vec[Int].new();
  var ci = 0;
  while ci < nchildren {
    if pos + 12 > data.len() {
      return _err_core(VDB_ERR_TRUNCATED, "vdb: truncated root child origin");
    }
    let ox: Int = _i32le(data, pos);
    let oy: Int = _i32le(data, pos + 4);
    let oz: Int = _i32le(data, pos + 8);
    pos = pos + 12;
    let cr = _walk_node(data, pos, 5, ox, oy, oz, kind, from_half, comp, &mut origins);
    if cr.is_err { return _err_core(cr.error.code, cr.error.message); }
    pos = cr.value;
    ci = ci + 1;
  }
  return _ok_core(_TreeCore{
    leaf_count: origins.len() / 3;
    origins: origins;
    background: bg;
    background_bits: bgbits;
    root_tile_count: ntiles;
    root_child_count: nchildren;
    end: pos;
  });
}

// ---------------------------------------------------------------------------
// Whole-grid scan (grid body -> tree index)
// ---------------------------------------------------------------------------

// Parse one grid body (compression flags, metadata, transform, topology,
// leaf buffers walk) into a VdbTree.
fn _scan_grid(data: &Vec<UInt8>, body_off: Int, kind: Int, from_half: Bool, grid_index: Int) -> Result[VdbTree, VdbError] {
  if body_off < 0 || body_off + 4 > data.len() {
    return _err_tree(VDB_ERR_TRUNCATED, "vdb: truncated grid body");
  }
  let comp: Int = _u32le(data, body_off);
  if (comp & (0 - 8)) != 0 {
    return _err_tree(VDB_ERR_UNSUPPORTED_COMPRESSION, "vdb: unknown compression flag bits");
  }
  var pos: Int = body_off + 4;
  let mr = _parse_metamap(data, pos);
  if mr.is_err { return _err_tree(mr.error.code, mr.error.message); }
  let meta = mr.value;
  pos = meta.end;
  let xr = _parse_transform(data, pos);
  if xr.is_err { return _err_tree(xr.error.code, xr.error.message); }
  let xf = xr.value;
  pos = xf.map_end;
  let topology_offset: Int = pos;
  let cr = _parse_topology(data, pos, kind, from_half, comp);
  if cr.is_err { return _err_tree(cr.error.code, cr.error.message); }
  let core = cr.value;
  pos = core.end;
  let buffers_offset: Int = pos;
  let payload_w: Int = _payload_width(kind, from_half);
  let logical_w: Int = _logical_width(kind);
  let mask_compressed: Bool = (comp & VDB_COMPRESS_ACTIVE_MASK) != 0;
  var boffs = Vec[Int].new();
  var k = 0;
  while k < core.leaf_count {
    boffs.push(pos);
    if pos + VDB_LEAF_MASK_BYTES > data.len() {
      return _err_tree(VDB_ERR_TRUNCATED, "vdb: truncated leaf buffer mask");
    }
    let nxtr = _skip_values(data, pos + VDB_LEAF_MASK_BYTES, VDB_LEAF_VOXELS, mask_compressed,
        pos, VDB_LEAF_VOXELS, logical_w, payload_w, comp);
    if nxtr.is_err { return _err_tree(nxtr.error.code, nxtr.error.message); }
    pos = nxtr.value;
    k = k + 1;
  }
  return _ok_tree(VdbTree{
    grid_index: grid_index;
    element_kind: kind;
    from_half: from_half;
    components: _components_of(kind);
    compression: comp;
    leaf_count: core.leaf_count;
    origins: core.origins;
    buffer_offsets: boffs;
    background: core.background;
    background_bits: core.background_bits;
    root_tile_count: core.root_tile_count;
    root_child_count: core.root_child_count;
    topology_offset: topology_offset;
    topology_end: core.end;
    buffers_offset: buffers_offset;
    buffers_end: pos;
  });
}

/// Parse the grid's MetaMap (also used for instance grids).
pub fn vdb_grid_meta(data: &Vec[UInt8], f: &VdbFile, grid_index: Int) -> Result[VdbMetaMap, VdbError] {
  if grid_index < 0 || grid_index >= f.grid_count {
    return _err_meta(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: grid index out of range");
  }
  let body: Int = f.body_offsets[grid_index];
  if body < 0 || body + 4 > data.len() {
    return _err_meta(VDB_ERR_TRUNCATED, "vdb: truncated grid body");
  }
  let mr = _parse_metamap(data, body + 4);
  if mr.is_err { return _err_meta(mr.error.code, mr.error.message); }
  return _ok_meta(mr.value);
}

/// Parse the grid's transform (also used for instance grids).
pub fn vdb_grid_transform(data: &Vec<UInt8>, f: &VdbFile, grid_index: Int) -> Result[VdbTransform, VdbError] {
  if grid_index < 0 || grid_index >= f.grid_count {
    return _err_xform(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: grid index out of range");
  }
  let mr = vdb_grid_meta(data, f, grid_index);
  if mr.is_err { return _err_xform(mr.error.code, mr.error.message); }
  let m = mr.value;
  let xr = _parse_transform(data, m.end);
  if xr.is_err { return _err_xform(xr.error.code, xr.error.message); }
  return _ok_xform(xr.value);
}

/// Parse the grid's topology and leaf-buffer index. Instance grids have no
/// tree (typed error: resolve the parent by name instead); unsupported tree
/// types are typed errors; declared stream positions are cross-checked
/// against the walked structure when present.
pub fn vdb_grid_tree(data: &Vec<UInt8>, f: &VdbFile, grid_index: Int) -> Result[VdbTree, VdbError] {
  if grid_index < 0 || grid_index >= f.grid_count {
    return _err_tree(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: grid index out of range");
  }
  let parent: Str = f.instance_parents[grid_index];
  if parent.len() > 0 {
    return _err_tree(VDB_ERR_INSTANCE_GRID, "vdb: grid is an instance; read its parent");
  }
  let t: Str = f.types[grid_index];
  let kind: Int = _grid_kind(t);
  if kind == 0 {
    return _err_tree(VDB_ERR_UNSUPPORTED_GRID_TYPE, "vdb: unsupported grid type: " + t);
  }
  let from_half: Bool = _grid_from_half(t);
  let body: Int = f.body_offsets[grid_index];
  let tr = _scan_grid(data, body, kind, from_half, grid_index);
  if tr.is_err { return _err_tree(tr.error.code, tr.error.message); }
  let tree = tr.value;
  let declared_block: Int = f.block_pos[grid_index];
  if declared_block > 0 && declared_block != tree.buffers_offset {
    return _err_tree(VDB_ERR_BAD_LAYOUT, "vdb: block position disagrees with the tree walk");
  }
  let declared_end: Int = f.end_pos[grid_index];
  if declared_end > 0 && declared_end != tree.buffers_end {
    return _err_tree(VDB_ERR_BAD_LAYOUT, "vdb: end position disagrees with the tree walk");
  }
  return _ok_tree(tree);
}

// ---------------------------------------------------------------------------
// Adler-32 and RFC 1950/1951 inflate (pure XIOM)
// ---------------------------------------------------------------------------

fn _zeros(n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(0);
    i = i + 1;
  }
  return v;
}

/// Adler-32 checksum of a whole buffer (mod 65521; s1 initialized to 1).
pub fn vdb_adler32(data: &Vec[UInt8]) -> Int {
  var s1 = 1;
  var s2 = 0;
  var i = 0;
  let n = data.len();
  while i < n {
    var chunk = 5552;
    if i + chunk > n {
      chunk = n - i;
    }
    var k = 0;
    while k < chunk {
      let b: Int = _b(data, i + k);
      s1 = s1 + b;
      s2 = s2 + s1;
      k = k + 1;
    }
    s1 = s1 % 65521;
    s2 = s2 % 65521;
    i = i + chunk;
  }
  return s2 * 65536 + s1;
}

// Bit `bit` of `data` (LSB-first within each byte); -1 when beyond `limit`.
fn _bit_at(data: &Vec[UInt8], bit: Int, limit: Int) -> Int {
  let byte_i: Int = bit >> 3;
  if bit < 0 || byte_i >= limit {
    return -1;
  }
  let b: Int = _b(data, byte_i);
  return (b >> (bit & 7)) & 1;
}

// `n` bits (n <= 16) starting at `bit`, packed LSB-first; -1 when the range
// crosses `limit` (never a valid value, so it doubles as an error).
fn _bits_lo(data: &Vec[UInt8], bit: Int, n: Int, limit: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < n {
    let b: Int = _bit_at(data, bit + i, limit);
    if b < 0 {
      return -1;
    }
    v = v + b * _pow2(i);
    i = i + 1;
  }
  return v;
}

// Code-length-code order for dynamic Huffman blocks (RFC 1951 3.2.7).
fn _cl_order() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(16); v.push(17); v.push(18); v.push(0); v.push(8); v.push(7);
  v.push(9); v.push(6); v.push(10); v.push(5); v.push(11); v.push(4);
  v.push(12); v.push(3); v.push(13); v.push(2); v.push(14); v.push(1);
  v.push(15);
  return v;
}

// Canonical Huffman table build: `counts[len]` = number of symbols with
// that length; `syms` = symbols ordered by (length, symbol index).
fn _huff_build(lens: &Vec[Int], counts: &mut Vec[Int], syms: &mut Vec[Int]) {
  var i = 0;
  while i < 16 {
    counts[i] = 0;
    i = i + 1;
  }
  i = 0;
  while i < lens.len() {
    let l: Int = lens[i];
    if l > 0 && l < 16 {
      counts[l] = counts[l] + 1;
    }
    i = i + 1;
  }
  var l = 1;
  while l < 16 {
    var s = 0;
    while s < lens.len() {
      let li: Int = lens[s];
      if li == l {
        syms.push(s);
      }
      s = s + 1;
    }
    l = l + 1;
  }
}

// Decode one Huffman symbol at `bit`; returns sym*64 + bits_used, -1 on a
// malformed code, -2 when the stream is exhausted.
fn _huff_decode(data: &Vec[UInt8], bit: Int, limit: Int, counts: &Vec[Int], syms: &Vec[Int]) -> Int {
  var code = 0;
  var first = 0;
  var index = 0;
  var l = 1;
  while l <= 15 {
    let b: Int = _bit_at(data, bit + l - 1, limit);
    if b < 0 {
      return -2;
    }
    code = code + b;
    let count: Int = counts[l];
    if code - first < count {
      let sym: Int = syms[index + (code - first)];
      return sym * 64 + l;
    }
    index = index + count;
    first = first + count;
    first = first * 2;
    code = code * 2;
    l = l + 1;
  }
  return -1;
}

// Fixed-Huffman literal/length code lengths (RFC 1951 3.2.6).
fn _fixed_lit_lens(out: &mut Vec[Int]) {
  var i = 0;
  while i < 144 { out.push(8); i = i + 1; }
  while i < 256 { out.push(9); i = i + 1; }
  while i < 280 { out.push(7); i = i + 1; }
  while i < 288 { out.push(8); i = i + 1; }
}

// Base length of length code 257..285.
fn _length_base(code: Int) -> Int {
  if code == 257 { return 3; }
  if code == 258 { return 4; }
  if code == 259 { return 5; }
  if code == 260 { return 6; }
  if code == 261 { return 7; }
  if code == 262 { return 8; }
  if code == 263 { return 9; }
  if code == 264 { return 10; }
  if code == 265 { return 11; }
  if code == 266 { return 13; }
  if code == 267 { return 15; }
  if code == 268 { return 17; }
  if code == 269 { return 19; }
  if code == 270 { return 23; }
  if code == 271 { return 27; }
  if code == 272 { return 31; }
  if code == 273 { return 35; }
  if code == 274 { return 43; }
  if code == 275 { return 51; }
  if code == 276 { return 59; }
  if code == 277 { return 67; }
  if code == 278 { return 83; }
  if code == 279 { return 99; }
  if code == 280 { return 115; }
  if code == 281 { return 131; }
  if code == 282 { return 163; }
  if code == 283 { return 195; }
  if code == 284 { return 227; }
  return 258;
}

// Extra bits of length code 257..285.
fn _length_extra(code: Int) -> Int {
  if code >= 265 && code <= 268 { return 1; }
  if code >= 269 && code <= 272 { return 2; }
  if code >= 273 && code <= 276 { return 3; }
  if code >= 277 && code <= 280 { return 4; }
  if code >= 281 && code <= 284 { return 5; }
  return 0;
}

// Base distance of distance code 0..29.
fn _dist_base(code: Int) -> Int {
  if code == 0 { return 1; }
  if code == 1 { return 2; }
  if code == 2 { return 3; }
  if code == 3 { return 4; }
  if code == 4 { return 5; }
  if code == 5 { return 7; }
  if code == 6 { return 9; }
  if code == 7 { return 13; }
  if code == 8 { return 17; }
  if code == 9 { return 25; }
  if code == 10 { return 33; }
  if code == 11 { return 49; }
  if code == 12 { return 65; }
  if code == 13 { return 97; }
  if code == 14 { return 129; }
  if code == 15 { return 193; }
  if code == 16 { return 257; }
  if code == 17 { return 385; }
  if code == 18 { return 513; }
  if code == 19 { return 769; }
  if code == 20 { return 1025; }
  if code == 21 { return 1537; }
  if code == 22 { return 2049; }
  if code == 23 { return 3073; }
  if code == 24 { return 4097; }
  if code == 25 { return 6145; }
  if code == 26 { return 8193; }
  if code == 27 { return 12289; }
  if code == 28 { return 16385; }
  return 24577;
}

// Extra bits of distance code 0..29.
fn _dist_extra(code: Int) -> Int {
  if code == 4 || code == 5 { return 1; }
  if code == 6 || code == 7 { return 2; }
  if code == 8 || code == 9 { return 3; }
  if code == 10 || code == 11 { return 4; }
  if code == 12 || code == 13 { return 5; }
  if code == 14 || code == 15 { return 6; }
  if code == 16 || code == 17 { return 7; }
  if code == 18 || code == 19 { return 8; }
  if code == 20 || code == 21 { return 9; }
  if code == 22 || code == 23 { return 10; }
  if code == 24 || code == 25 { return 11; }
  if code == 26 || code == 27 { return 12; }
  if code == 28 || code == 29 { return 13; }
  return 0;
}

// Inflate one zlib stream occupying [from, limit) into `out`, which must be
// empty; the decompressed size must equal `expected` and the trailing
// Adler-32 must match. Returns the offset just past the Adler-32.
fn _inflate_into(z: &Vec[UInt8], from: Int, limit: Int, expected: Int, out: &mut Vec[UInt8]) -> Result[Int, VdbError] {
  if expected < 0 || expected > _CAP_INFLATE_BYTES {
    return _err_int(VDB_ERR_LIMIT_EXCEEDED, "vdb: inflate output over the 16 MiB cap");
  }
  if from < 0 || limit > z.len() || from + 2 > limit {
    return _err_int(VDB_ERR_ZIP_INVALID, "vdb: zlib stream too short");
  }
  let cmf: Int = _b(z, from);
  let flg: Int = _b(z, from + 1);
  if (cmf & 15) != 8 {
    return _err_int(VDB_ERR_ZIP_INVALID, "vdb: zlib stream is not deflate");
  }
  if (cmf / 16) > 7 {
    return _err_int(VDB_ERR_ZIP_INVALID, "vdb: zlib window size not supported");
  }
  if ((cmf * 256 + flg) % 31) != 0 {
    return _err_int(VDB_ERR_ZIP_INVALID, "vdb: zlib header check failed");
  }
  if (flg & 32) != 0 {
    return _err_int(VDB_ERR_ZIP_INVALID, "vdb: zlib preset dictionary not supported");
  }
  var bit: Int = (from + 2) * 8;
  var last = 0;
  while last == 0 {
    let fb: Int = _bit_at(z, bit, limit);
    if fb < 0 {
      return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated deflate stream");
    }
    last = fb;
    bit = bit + 1;
    let btype: Int = _bits_lo(z, bit, 2, limit);
    if btype < 0 {
      return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated deflate block header");
    }
    bit = bit + 2;
    if btype == 0 {
      let byte_pos: Int = (bit + 7) / 8;
      if byte_pos + 4 > limit {
        return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated stored block header");
      }
      let blen: Int = _u16le(z, byte_pos);
      let nlen: Int = _u16le(z, byte_pos + 2);
      if (blen ^ 65535) != nlen {
        return _err_int(VDB_ERR_ZIP_INVALID, "vdb: stored block length check failed");
      }
      if byte_pos + 4 + blen > limit {
        return _err_int(VDB_ERR_ZIP_INVALID, "vdb: stored block beyond the stream");
      }
      var k = 0;
      while k < blen {
        let raw: UInt8 = z[byte_pos + 4 + k];
        out.push(raw);
        k = k + 1;
      }
      if out.len() > expected {
        return _err_int(VDB_ERR_ZIP_INVALID, "vdb: inflate output larger than expected");
      }
      bit = (byte_pos + 4 + blen) * 8;
    } elif btype == 1 || btype == 2 {
      var lit_counts = _zeros(16);
      var lit_syms = Vec[Int].new();
      var dist_counts = _zeros(16);
      var dist_syms = Vec[Int].new();
      if btype == 1 {
        var lit_lens = Vec[Int].new();
        _fixed_lit_lens(&mut lit_lens);
        _huff_build(&lit_lens, &mut lit_counts, &mut lit_syms);
        var dist_lens = Vec[Int].new();
        var i = 0;
        while i < 32 {
          dist_lens.push(5);
          i = i + 1;
        }
        _huff_build(&dist_lens, &mut dist_counts, &mut dist_syms);
      } else {
        let v_hlit: Int = _bits_lo(z, bit, 5, limit);
        let v_hdist: Int = _bits_lo(z, bit + 5, 5, limit);
        let v_hclen: Int = _bits_lo(z, bit + 10, 4, limit);
        if v_hlit < 0 || v_hdist < 0 || v_hclen < 0 {
          return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated dynamic block header");
        }
        bit = bit + 14;
        let nlit: Int = v_hlit + 257;
        let ndist: Int = v_hdist + 1;
        let ncl: Int = v_hclen + 4;
        if nlit > 286 || ndist > 30 {
          return _err_int(VDB_ERR_ZIP_INVALID, "vdb: dynamic code counts out of range");
        }
        let order = _cl_order();
        var cl_lens = _zeros(19);
        var i = 0;
        while i < ncl {
          let v: Int = _bits_lo(z, bit, 3, limit);
          if v < 0 {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated code-length table");
          }
          let slot: Int = order[i];
          cl_lens[slot] = v;
          bit = bit + 3;
          i = i + 1;
        }
        var cl_counts = _zeros(16);
        var cl_syms = Vec[Int].new();
        _huff_build(&cl_lens, &mut cl_counts, &mut cl_syms);
        var lens = Vec[Int].new();
        var prev = 0;
        while lens.len() < nlit + ndist {
          let p: Int = _huff_decode(z, bit, limit, &cl_counts, &cl_syms);
          if p == -2 {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated code-length stream");
          }
          if p < 0 {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: invalid code-length code");
          }
          let sym: Int = p / 64;
          let used: Int = p % 64;
          bit = bit + used;
          if sym < 16 {
            lens.push(sym);
            if sym != 0 {
              prev = sym;
            }
          } elif sym == 16 {
            if lens.len() == 0 {
              return _err_int(VDB_ERR_ZIP_INVALID, "vdb: repeat with no previous length");
            }
            let r: Int = _bits_lo(z, bit, 2, limit);
            if r < 0 {
              return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated code-length repeat");
            }
            bit = bit + 2;
            var k = 0;
            while k < 3 + r {
              lens.push(prev);
              k = k + 1;
            }
          } elif sym == 17 {
            let r: Int = _bits_lo(z, bit, 3, limit);
            if r < 0 {
              return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated zero run");
            }
            bit = bit + 3;
            var k = 0;
            while k < 3 + r {
              lens.push(0);
              k = k + 1;
            }
          } elif sym == 18 {
            let r: Int = _bits_lo(z, bit, 7, limit);
            if r < 0 {
              return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated zero run");
            }
            bit = bit + 7;
            var k = 0;
            while k < 11 + r {
              lens.push(0);
              k = k + 1;
            }
          } else {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: invalid code-length symbol");
          }
        }
        var lit_lens = Vec[Int].new();
        var di = 0;
        while di < nlit {
          let lv: Int = lens[di];
          lit_lens.push(lv);
          di = di + 1;
        }
        var dist_lens = Vec[Int].new();
        while di < nlit + ndist {
          let dv: Int = lens[di];
          dist_lens.push(dv);
          di = di + 1;
        }
        _huff_build(&lit_lens, &mut lit_counts, &mut lit_syms);
        _huff_build(&dist_lens, &mut dist_counts, &mut dist_syms);
      }
      let dist_empty: Bool = dist_syms.len() == 0;
      var block_done = false;
      while !block_done {
        let p: Int = _huff_decode(z, bit, limit, &lit_counts, &lit_syms);
        if p == -2 {
          return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated compressed block");
        }
        if p < 0 {
          return _err_int(VDB_ERR_ZIP_INVALID, "vdb: invalid literal/length code");
        }
        let sym: Int = p / 64;
        let used: Int = p % 64;
        bit = bit + used;
        if sym < 256 {
          out.push(sym as UInt8);
        } elif sym == 256 {
          block_done = true;
        } else {
          if sym > 285 {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: invalid length code");
          }
          var length: Int = _length_base(sym);
          let lex: Int = _length_extra(sym);
          if lex > 0 {
            let r: Int = _bits_lo(z, bit, lex, limit);
            if r < 0 {
              return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated length extra bits");
            }
            bit = bit + lex;
            length = length + r;
          }
          if dist_empty {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: length code with an empty distance tree");
          }
          let dp: Int = _huff_decode(z, bit, limit, &dist_counts, &dist_syms);
          if dp == -2 {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated distance code");
          }
          if dp < 0 {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: invalid distance code");
          }
          let dcode: Int = dp / 64;
          let dused: Int = dp % 64;
          bit = bit + dused;
          if dcode > 29 {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: distance code out of range");
          }
          var dist: Int = _dist_base(dcode);
          let dex: Int = _dist_extra(dcode);
          if dex > 0 {
            let r: Int = _bits_lo(z, bit, dex, limit);
            if r < 0 {
              return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated distance extra bits");
            }
            bit = bit + dex;
            dist = dist + r;
          }
          if dist > out.len() {
            return _err_int(VDB_ERR_ZIP_INVALID, "vdb: distance reaches before the output start");
          }
          var k = 0;
          while k < length {
            let src_i: Int = out.len() - dist;
            let b: UInt8 = out[src_i];
            out.push(b);
            k = k + 1;
          }
        }
        if out.len() > expected {
          return _err_int(VDB_ERR_ZIP_INVALID, "vdb: inflate output larger than expected");
        }
      }
    } else {
      return _err_int(VDB_ERR_ZIP_INVALID, "vdb: invalid deflate block type");
    }
  }
  if out.len() != expected {
    return _err_int(VDB_ERR_ZIP_INVALID, "vdb: inflate size mismatch");
  }
  let adler_pos: Int = (bit + 7) / 8;
  if adler_pos + 4 > limit {
    return _err_int(VDB_ERR_ZIP_INVALID, "vdb: truncated Adler-32");
  }
  let a0: Int = _b(z, adler_pos);
  let a1: Int = _b(z, adler_pos + 1);
  let a2: Int = _b(z, adler_pos + 2);
  let a3: Int = _b(z, adler_pos + 3);
  let want: Int = a0 * 16777216 + a1 * 65536 + a2 * 256 + a3;
  var s1 = 1;
  var s2 = 0;
  var i = 0;
  while i < out.len() {
    let b: Int = _b(out, i);
    s1 = s1 + b;
    s2 = s2 + s1;
    if i % 5552 == 5551 {
      s1 = s1 % 65521;
      s2 = s2 % 65521;
    }
    i = i + 1;
  }
  s1 = s1 % 65521;
  s2 = s2 % 65521;
  let got: Int = s2 * 65536 + s1;
  if got != want {
    return _err_int(VDB_ERR_ZIP_ADLER, "vdb: Adler-32 mismatch");
  }
  return _ok_int(adler_pos + 4);
}

/// Inflate a complete zlib stream (RFC 1950: deflate payload + Adler-32)
/// whose decompressed size must be exactly `expected`.
pub fn vdb_zip_inflate(zdata: &Vec[UInt8], expected: Int) -> Result[Vec[UInt8], VdbError] {
  var out = Vec[UInt8].new();
  let ir = _inflate_into(zdata, 0, zdata.len(), expected, &mut out);
  if ir.is_err { return _err_bytes(ir.error.code, ir.error.message); }
  return _ok_bytes(out);
}

// ---------------------------------------------------------------------------
// Leaf buffers: payload read and full leaf decode
// ---------------------------------------------------------------------------

// Push the stored payload element at `off` (half-storage honoured).
fn _push_payload_element(p: &Vec[UInt8], off: Int, kind: Int, from_half: Bool, values: &mut Vec[Float64]) {
  if kind == VDB_ELEM_F32 {
    if from_half {
      values.push(_f16_to_f64(_u16le(p, off)));
    } else {
      values.push(_f32_to_f64(_u32le(p, off)));
    }
  } elif kind == VDB_ELEM_F64 {
    values.push(bits_to_float(_u64le(p, off)));
  } elif kind == VDB_ELEM_F16 {
    values.push(_f16_to_f64(_u16le(p, off)));
  } elif kind == VDB_ELEM_VEC3F {
    var step = 4;
    if from_half {
      step = 2;
    }
    var c = 0;
    while c < 3 {
      if from_half {
        values.push(_f16_to_f64(_u16le(p, off + c * step)));
      } else {
        values.push(_f32_to_f64(_u32le(p, off + c * step)));
      }
      c = c + 1;
    }
  } else {
    var c = 0;
    while c < 3 {
      values.push(bits_to_float(_u64le(p, off + c * 8)));
      c = c + 1;
    }
  }
}

// Read one value chunk (zlib-compressed, blosc, raw fallback or plain raw)
// for `count` stored elements of `payload_w` bytes into `out`. Returns the
// offset just past the chunk.
fn _read_payload(data: &Vec<UInt8>, p: Int, count: Int, payload_w: Int, comp: Int,
    out: &mut Vec[UInt8]) -> Result[Int, VdbError] {
  let want: Int = count * payload_w;
  if (comp & (VDB_COMPRESS_ZIP + VDB_COMPRESS_BLOSC)) != 0 {
    if p + 8 > data.len() {
      return _err_int(VDB_ERR_TRUNCATED, "vdb: truncated compression chunk size");
    }
    let n: Int = _i64le(data, p);
    let q: Int = p + 8;
    if n <= 0 {
      let raw: Int = 0 - n;
      if raw != want {
        return _err_int(VDB_ERR_BAD_NODE_DATA, "vdb: raw chunk size does not match the active count");
      }
      if q + raw > data.len() {
        return _err_int(VDB_ERR_TRUNCATED, "vdb: raw chunk beyond the buffer");
      }
      var k = 0;
      while k < raw {
        out.push(data[q + k]);
        k = k + 1;
      }
      return _ok_int(q + raw);
    }
    if (comp & VDB_COMPRESS_BLOSC) != 0 {
      return _err_int(VDB_ERR_UNSUPPORTED_COMPRESSION, "vdb: blosc-compressed values are not decodable");
    }
    if q + n > data.len() {
      return _err_int(VDB_ERR_TRUNCATED, "vdb: compressed chunk beyond the buffer");
    }
    let nxtr = _inflate_into(data, q, q + n, want, out);
    if nxtr.is_err { return _err_int(nxtr.error.code, nxtr.error.message); }
    if nxtr.value > data.len() {
      return _err_int(VDB_ERR_ZIP_INVALID, "vdb: inflate consumed bytes beyond the buffer");
    }
    return _ok_int(q + n);
  }
  if p + want > data.len() {
    return _err_int(VDB_ERR_TRUNCATED, "vdb: raw values beyond the buffer");
  }
  var k = 0;
  while k < want {
    out.push(data[p + k]);
    k = k + 1;
  }
  return _ok_int(p + want);
}

// Decode leaf `leaf_index` of `tree` from the buffer: mask, mask metadata,
// inactive values, selection mask, payload, full reconstruction.
fn _decode_leaf(data: &Vec<UInt8>, tree: &VdbTree, leaf_index: Int) -> Result[VdbLeaf, VdbError] {
  let off: Int = tree.buffer_offsets[leaf_index];
  let ox: Int = tree.origins[leaf_index * 3];
  let oy: Int = tree.origins[leaf_index * 3 + 1];
  let oz: Int = tree.origins[leaf_index * 3 + 2];
  let kind: Int = tree.element_kind;
  let from_half: Bool = tree.from_half;
  let comp: Int = tree.compression;
  let components: Int = tree.components;
  let logical_w: Int = _logical_width(kind);
  let payload_w: Int = _payload_width(kind, from_half);
  let mask_compressed: Bool = (comp & VDB_COMPRESS_ACTIVE_MASK) != 0;
  if off < 0 || off + VDB_LEAF_MASK_BYTES > data.len() {
    return _err_leaf(VDB_ERR_TRUNCATED, "vdb: truncated leaf buffer mask");
  }
  var active = Vec[UInt8].new();
  var i = 0;
  while i < VDB_LEAF_MASK_BYTES {
    active.push(data[off + i]);
    i = i + 1;
  }
  var p: Int = off + VDB_LEAF_MASK_BYTES;
  if p + 1 > data.len() {
    return _err_leaf(VDB_ERR_TRUNCATED, "vdb: truncated leaf value header");
  }
  let metadata: Int = _b(data, p);
  p = p + 1;
  if metadata > _NM_NO_MASK_AND_ALL_VALS {
    return _err_leaf(VDB_ERR_BAD_NODE_DATA, "vdb: leaf metadata byte out of range");
  }
  var in0 = Vec[Float64].new();
  var in1 = Vec[Float64].new();
  var in0bits = Vec[Int].new();
  var in1bits = Vec[Int].new();
  if metadata == _NM_NO_MASK_AND_ONE_INACTIVE || metadata == _NM_MASK_AND_ONE_INACTIVE {
    if p + logical_w > data.len() {
      return _err_leaf(VDB_ERR_TRUNCATED, "vdb: truncated inactive value");
    }
    _push_element(data, p, kind, false, &mut in0, &mut in0bits);
    p = p + logical_w;
  }
  if metadata == _NM_MASK_AND_TWO_INACTIVE {
    if p + 2 * logical_w > data.len() {
      return _err_leaf(VDB_ERR_TRUNCATED, "vdb: truncated inactive values");
    }
    _push_element(data, p, kind, false, &mut in0, &mut in0bits);
    _push_element(data, p + logical_w, kind, false, &mut in1, &mut in1bits);
    p = p + 2 * logical_w;
  }
  var sel_off: Int = -1;
  if metadata == _NM_MASK_AND_NO_INACTIVE || metadata == _NM_MASK_AND_ONE_INACTIVE || metadata == _NM_MASK_AND_TWO_INACTIVE {
    sel_off = p;
    p = p + VDB_LEAF_MASK_BYTES;
  }
  if p > data.len() {
    return _err_leaf(VDB_ERR_TRUNCATED, "vdb: truncated leaf value metadata");
  }
  var count: Int = VDB_LEAF_VOXELS;
  if mask_compressed && metadata != _NM_NO_MASK_AND_ALL_VALS {
    count = _mask_count_on(data, off, VDB_LEAF_VOXELS);
  }
  var payload = Vec[UInt8].new();
  let ar = _read_payload(data, p, count, payload_w, comp, &mut payload);
  if ar.is_err { return _err_leaf(ar.error.code, ar.error.message); }
  if ar.value > data.len() {
    return _err_leaf(VDB_ERR_TRUNCATED, "vdb: leaf payload beyond the buffer");
  }
  var values = Vec[Float64].new();
  if mask_compressed && metadata != _NM_NO_MASK_AND_ALL_VALS {
    var use0 = Vec[Float64].new();
    var use1 = Vec[Float64].new();
    var c = 0;
    while c < components {
      let bg: Float64 = tree.background[c];
      use0.push(bg);
      use1.push(bg);
      c = c + 1;
    }
    if metadata == _NM_NO_MASK_AND_MINUS_BG || metadata == _NM_MASK_AND_NO_INACTIVE {
      c = 0;
      while c < components {
        let v: Float64 = use0[c];
        use0[c] = 0.0 - v;
        c = c + 1;
      }
    }
    if metadata == _NM_NO_MASK_AND_ONE_INACTIVE || metadata == _NM_MASK_AND_ONE_INACTIVE {
      c = 0;
      while c < components {
        let v: Float64 = in0[c];
        use0[c] = v;
        c = c + 1;
      }
    }
    if metadata == _NM_MASK_AND_TWO_INACTIVE {
      c = 0;
      while c < components {
        let v0: Float64 = in0[c];
        let v1: Float64 = in1[c];
        use0[c] = v0;
        use1[c] = v1;
        c = c + 1;
      }
    }
    var t = 0;
    var offi = 0;
    while offi < VDB_LEAF_VOXELS {
      if _mask_on(data, off, offi) {
        _push_payload_element(&payload, t * payload_w, kind, from_half, &mut values);
        t = t + 1;
      } else {
        var sel = false;
        if sel_off >= 0 {
          sel = _mask_on(data, sel_off, offi);
        }
        c = 0;
        while c < components {
          if sel {
            let v1: Float64 = use1[c];
            values.push(v1);
          } else {
            let v0: Float64 = use0[c];
            values.push(v0);
          }
          c = c + 1;
        }
      }
      offi = offi + 1;
    }
  } else {
    var t = 0;
    while t < count {
      _push_payload_element(&payload, t * payload_w, kind, from_half, &mut values);
      t = t + 1;
    }
  }
  var origin = Vec[Int].new();
  origin.push(ox);
  origin.push(oy);
  origin.push(oz);
  return _ok_leaf(VdbLeaf{
    leaf_index: leaf_index;
    origin: origin;
    active: active;
    metadata: metadata;
    value_count: VDB_LEAF_VOXELS;
    components: components;
    element_kind: kind;
    from_half: from_half;
    logical_width: logical_w;
    payload_width: payload_w;
    payload: payload;
    values: values;
  });
}

/// Decode leaf block `leaf_index` of a parsed tree. The result carries the
/// 64-byte value mask, the decompressed stored payload and the full
/// reconstructed 512-voxel value block.
pub fn vdb_read_leaf(data: &Vec[UInt8], tree: &VdbTree, leaf_index: Int) -> Result[VdbLeaf, VdbError] {
  if leaf_index < 0 || leaf_index >= tree.leaf_count {
    return _err_leaf(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: leaf index out of range");
  }
  return _decode_leaf(data, tree, leaf_index);
}

/// Index of the leaf containing voxel (x, y, z), or -1. Linear over the
/// tree's leaf list (documented minimal-reader behaviour).
pub fn vdb_find_leaf(tree: &VdbTree, x: Int, y: Int, z: Int) -> Int {
  var k = 0;
  while k < tree.leaf_count {
    let ox: Int = tree.origins[k * 3];
    let oy: Int = tree.origins[k * 3 + 1];
    let oz: Int = tree.origins[k * 3 + 2];
    if x >= ox && x < ox + VDB_LEAF_DIM && y >= oy && y < oy + VDB_LEAF_DIM && z >= oz && z < oz + VDB_LEAF_DIM {
      return k;
    }
    k = k + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Leaf accessors
// ---------------------------------------------------------------------------

/// True when voxel (x, y, z) lies inside this leaf's 8^3 block.
pub fn vdb_leaf_contains(leaf: &VdbLeaf, x: Int, y: Int, z: Int) -> Bool {
  let ox: Int = leaf.origin[0];
  let oy: Int = leaf.origin[1];
  let oz: Int = leaf.origin[2];
  return x >= ox && x < ox + VDB_LEAF_DIM && y >= oy && y < oy + VDB_LEAF_DIM && z >= oz && z < oz + VDB_LEAF_DIM;
}

/// Local voxel offset (x*64 + y*8 + z) of (x, y, z) inside the leaf, or -1
/// when the coordinate is outside the block.
pub fn vdb_leaf_voxel_offset(leaf: &VdbLeaf, x: Int, y: Int, z: Int) -> Int {
  if !vdb_leaf_contains(leaf, x, y, z) {
    return -1;
  }
  let ox: Int = leaf.origin[0];
  let oy: Int = leaf.origin[1];
  let oz: Int = leaf.origin[2];
  return (x - ox) * 64 + (y - oy) * 8 + (z - oz);
}

/// Active state of voxel (x, y, z); false when the coordinate is outside
/// the block (check vdb_leaf_contains first when that matters).
pub fn vdb_leaf_is_active(leaf: &VdbLeaf, x: Int, y: Int, z: Int) -> Bool {
  let off: Int = vdb_leaf_voxel_offset(leaf, x, y, z);
  if off < 0 {
    return false;
  }
  let byte_i: Int = off / 8;
  let b: UInt8 = leaf.active[byte_i];
  return (((b as Int) & 0xFF) >> (off % 8)) % 2 == 1;
}

/// Number of active voxels in the leaf's value mask.
pub fn vdb_leaf_active_count(leaf: &VdbLeaf) -> Int {
  var n = 0;
  var i = 0;
  while i < VDB_LEAF_VOXELS {
    let byte_i: Int = i / 8;
    let b: UInt8 = leaf.active[byte_i];
    n = n + ((((b as Int) & 0xFF) >> (i % 8)) % 2);
    i = i + 1;
  }
  return n;
}

/// Reconstructed value of component `c` at voxel (x, y, z).
pub fn vdb_leaf_component(leaf: &VdbLeaf, x: Int, y: Int, z: Int, c: Int) -> Result[Float64, VdbError] {
  let off: Int = vdb_leaf_voxel_offset(leaf, x, y, z);
  if off < 0 {
    return _err_f64(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: voxel outside the leaf block");
  }
  if c < 0 || c >= leaf.components {
    return _err_f64(VDB_ERR_INDEX_OUT_OF_RANGE, "vdb: component index out of range");
  }
  let v: Float64 = leaf.values[off * leaf.components + c];
  return _ok_f64(v);
}

/// Read one voxel: find its leaf, decode it and return the value vector.
/// A coordinate outside every leaf is not an error: `found` is false and
/// `values` is empty (background/unknown).
pub fn vdb_read_voxel(data: &Vec<UInt8>, tree: &VdbTree, x: Int, y: Int, z: Int) -> Result[VdbVoxel, VdbError] {
  let k: Int = vdb_find_leaf(tree, x, y, z);
  if k < 0 {
    var empty = Vec[Float64].new();
    return _ok_voxel(VdbVoxel{ found: false; active: false; components: tree.components; values: empty; });
  }
  let lr = _decode_leaf(data, tree, k);
  if lr.is_err { return _err_voxel(lr.error.code, lr.error.message); }
  let leaf = lr.value;
  let off: Int = vdb_leaf_voxel_offset(&leaf, x, y, z);
  if off < 0 {
    return _err_voxel(VDB_ERR_BAD_LAYOUT, "vdb: leaf lookup and offset disagree");
  }
  var vals = Vec[Float64].new();
  var c = 0;
  while c < leaf.components {
    let v: Float64 = leaf.values[off * leaf.components + c];
    vals.push(v);
    c = c + 1;
  }
  let active: Bool = vdb_leaf_is_active(&leaf, x, y, z);
  return _ok_voxel(VdbVoxel{ found: true; active: active; components: leaf.components; values: vals; });
}

// ---------------------------------------------------------------------------
// File header and container open
// ---------------------------------------------------------------------------

/// True when the first 8 bytes carry the zero-extended OpenVDB magic.
pub fn vdb_magic_ok(data: &Vec[UInt8]) -> Bool {
  if data.len() < 8 {
    return false;
  }
  let lo: Int = _u32le(data, 0);
  let hi: Int = _u32le(data, 4);
  return lo == VDB_MAGIC && hi == 0;
}

/// Parse the 57-byte file header. Rejects missing magic and file versions
/// outside VDB_FILE_VERSION_MIN..MAX with typed errors. The UUID is exposed
/// as "" when any of its 36 bytes is not printable ASCII.
pub fn vdb_parse_header(data: &Vec<UInt8>) -> Result[VdbHeader, VdbError] {
  if data.len() < VDB_HEADER_BYTES {
    return _err_hdr(VDB_ERR_TRUNCATED_HEADER, "vdb: truncated header");
  }
  if !vdb_magic_ok(data) {
    return _err_hdr(VDB_ERR_BAD_MAGIC, "vdb: not a VDB file");
  }
  let version: Int = _u32le(data, 8);
  if version < VDB_FILE_VERSION_MIN || version > VDB_FILE_VERSION_MAX {
    return _err_hdr(VDB_ERR_UNSUPPORTED_VERSION, "vdb: unsupported file version");
  }
  let major: Int = _u32le(data, 12);
  let minor: Int = _u32le(data, 16);
  let has_offsets: Bool = _b(data, 20) != 0;
  var uuid = "";
  var printable = true;
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < 36 {
    let b: Int = _b(data, 21 + i);
    if !_printable(b) {
      printable = false;
    }
    bytes.push(b as UInt8);
    i = i + 1;
  }
  if printable {
    uuid = Str::from_utf8(bytes);
  }
  return _ok_hdr(VdbHeader{
    file_version: version;
    library_major: major;
    library_minor: minor;
    has_grid_offsets: has_offsets;
    uuid: uuid;
  });
}

/// Parse the whole container: header, file-level metadata and the grid
/// descriptor table. Grid bodies are located by `body_offsets` and decoded
/// on demand with vdb_grid_meta / vdb_grid_transform / vdb_grid_tree.
///
/// Seekable images (has_grid_offsets true) jump between descriptors using
/// the stored stream positions, which are cross-checked. Non-seekable
/// images stream every grid body (instance grids stop after the transform,
/// value grids are fully walked) to reach the next descriptor, so their
/// grid types must be supported.
pub fn vdb_open(data: &Vec<UInt8>) -> Result[VdbFile, VdbError] {
  let hrr = vdb_parse_header(data);
  if hrr.is_err { return _err_file(hrr.error.code, hrr.error.message); }
  let hr = hrr.value;
  let mr = _parse_metamap(data, VDB_HEADER_BYTES);
  if mr.is_err { return _err_file(mr.error.code, mr.error.message); }
  let meta = mr.value;
  var pos: Int = meta.end;
  if pos + 4 > data.len() {
    return _err_file(VDB_ERR_TRUNCATED, "vdb: truncated grid count");
  }
  let n: Int = _u32le(data, pos);
  pos = pos + 4;
  if n > _CAP_GRIDS {
    return _err_file(VDB_ERR_LIMIT_EXCEEDED, "vdb: grid count over the 65536 cap");
  }
  var unique = Vec[Str].new();
  var names = Vec[Str].new();
  var types = Vec[Str].new();
  var parents = Vec[Str].new();
  var gpos = Vec[Int].new();
  var bpos = Vec[Int].new();
  var epos = Vec[Int].new();
  var bodies = Vec[Int].new();
  var i = 0;
  while i < n {
    let snr = _str_span(data, pos);
    if snr.is_err { return _err_file(snr.error.code, snr.error.message); }
    let sn = snr.value;
    pos = sn.next;
    unique.push(sn.value);
    names.push(_strip_suffix(sn.value));
    let str_ = _str_span(data, pos);
    if str_.is_err { return _err_file(str_.error.code, str_.error.message); }
    let st = str_.value;
    pos = st.next;
    types.push(st.value);
    let spr = _str_span(data, pos);
    if spr.is_err { return _err_file(spr.error.code, spr.error.message); }
    let sp = spr.value;
    pos = sp.next;
    parents.push(sp.value);
    if pos + 24 > data.len() {
      return _err_file(VDB_ERR_TRUNCATED, "vdb: truncated grid descriptor positions");
    }
    let gp: Int = _u64le(data, pos);
    let bp: Int = _u64le(data, pos + 8);
    let ep: Int = _u64le(data, pos + 16);
    pos = pos + 24;
    gpos.push(gp);
    bpos.push(bp);
    epos.push(ep);
    bodies.push(pos);
    if hr.has_grid_offsets {
      if gp != pos {
        return _err_file(VDB_ERR_BAD_LAYOUT, "vdb: grid position disagrees with the descriptor table");
      }
      if ep <= pos {
        return _err_file(VDB_ERR_BAD_LAYOUT, "vdb: end position before the grid body");
      }
      if ep > data.len() {
        return _err_file(VDB_ERR_TRUNCATED, "vdb: end position beyond the buffer");
      }
      pos = ep;
    } else {
      let parent: Str = parents[i];
      if parent.len() > 0 {
        if pos + 4 > data.len() {
          return _err_file(VDB_ERR_TRUNCATED, "vdb: truncated instance grid body");
        }
        let imr = _parse_metamap(data, pos + 4);
        if imr.is_err { return _err_file(imr.error.code, imr.error.message); }
        let im = imr.value;
        let ixr = _parse_transform(data, im.end);
        if ixr.is_err { return _err_file(ixr.error.code, ixr.error.message); }
        pos = ixr.value.map_end;
      } else {
        let t: Str = types[i];
        let kind: Int = _grid_kind(t);
        if kind == 0 {
          return _err_file(VDB_ERR_UNSUPPORTED_GRID_TYPE,
              "vdb: cannot skip unsupported grid type in a non-seekable file: " + t);
        }
        let tr = _scan_grid(data, bodies[i], kind, _grid_from_half(t), i);
        if tr.is_err { return _err_file(tr.error.code, tr.error.message); }
        pos = tr.value.buffers_end;
      }
    }
    i = i + 1;
  }
  return _ok_file(VdbFile{
    header: hr;
    meta: meta;
    grid_count: n;
    unique_names: unique;
    names: names;
    types: types;
    instance_parents: parents;
    grid_pos: gpos;
    block_pos: bpos;
    end_pos: epos;
    body_offsets: bodies;
  });
}

// ---------------------------------------------------------------------------
// Container accessors
// ---------------------------------------------------------------------------

/// Number of grids in the descriptor table.
pub fn vdb_grid_count(f: &VdbFile) -> Int {
  return f.grid_count;
}

/// User-facing grid name (0x1E duplicate suffix stripped); "" out of range.
pub fn vdb_grid_name(f: &VdbFile, i: Int) -> Str {
  if i < 0 || i >= f.grid_count {
    return "";
  }
  let s: Str = f.names[i];
  return s;
}

/// Raw stored unique name (with the 0x1E suffix when present); "" out of range.
pub fn vdb_grid_unique_name(f: &VdbFile, i: Int) -> Str {
  if i < 0 || i >= f.grid_count {
    return "";
  }
  let s: Str = f.unique_names[i];
  return s;
}

/// Raw tree type name (may carry the `_HalfFloat` storage suffix).
pub fn vdb_grid_type(f: &VdbFile, i: Int) -> Str {
  if i < 0 || i >= f.grid_count {
    return "";
  }
  let s: Str = f.types[i];
  return s;
}

/// Instance-parent unique name; "" for non-instance grids.
pub fn vdb_grid_instance_parent(f: &VdbFile, i: Int) -> Str {
  if i < 0 || i >= f.grid_count {
    return "";
  }
  let s: Str = f.instance_parents[i];
  return s;
}

/// Stored grid start position (0 when the file has no offsets); -1 out of range.
pub fn vdb_grid_pos(f: &VdbFile, i: Int) -> Int {
  if i < 0 || i >= f.grid_count {
    return -1;
  }
  let v: Int = f.grid_pos[i];
  return v;
}

/// Stored block (buffers) position (0 when the file has no offsets); -1 out of range.
pub fn vdb_grid_block_pos(f: &VdbFile, i: Int) -> Int {
  if i < 0 || i >= f.grid_count {
    return -1;
  }
  let v: Int = f.block_pos[i];
  return v;
}

/// Stored end position (0 when the file has no offsets); -1 out of range.
pub fn vdb_grid_end_pos(f: &VdbFile, i: Int) -> Int {
  if i < 0 || i >= f.grid_count {
    return -1;
  }
  let v: Int = f.end_pos[i];
  return v;
}

/// Absolute offset of the grid body (compression flags) in the buffer;
/// -1 out of range.
pub fn vdb_grid_body_offset(f: &VdbFile, i: Int) -> Int {
  if i < 0 || i >= f.grid_count {
    return -1;
  }
  let v: Int = f.body_offsets[i];
  return v;
}

/// Index of the first grid whose unique or stripped name equals `name`,
/// or -1.
pub fn vdb_find_grid(f: &VdbFile, name: Str) -> Int {
  var i = 0;
  while i < f.grid_count {
    let u: Str = f.unique_names[i];
    if _str_eq(u, name) {
      return i;
    }
    let s: Str = f.names[i];
    if _str_eq(s, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}
