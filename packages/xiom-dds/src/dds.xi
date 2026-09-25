// XIOM -- xiom.dds: DirectDraw Surface (DDS) header codec (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Parses and builds the canonical DirectDraw Surface
// container: the "DDS " magic, the 124-byte DDS_HEADER (with its embedded
// 32-byte DDS_PIXELFORMAT), the optional 20-byte DDS_HEADER_DXT10 block that
// follows a DX10 fourCC, and the payload offset/length. Nothing below the
// header is interpreted: no block is decompressed, no mip level is sliced and
// no format is converted.
//
// Accepted pixel formats (the documented subset):
//   * uncompressed RGB(A): DDPF_RGB with a 16-, 24- or 32-bit count and
//     nonzero, pairwise disjoint R/G/B (and optional A) masks that fit the
//     bit count;
//   * the compressed fourCCs DXT1..DXT5 (recognized);
//   * the DX10 fourCC, which requires the DDS_HEADER_DXT10 block;
//   * any other nonzero fourCC is accepted and passed through: the
//     dds_fourcc_recognized predicate reports whether the codec knows the
//     code, and dds_pixel_format_supported reports whether the pixel-format
//     flag shape is inside the subset.
// Other data flags (DDPF_ALPHA, DDPF_YUV, DDPF_LUMINANCE, palettes) are
// outside the subset and rejected with "dds: unsupported pixel format".
//
// Strictness (see SPEC.md): reserved1 must be zero; DDSD_CAPS, DDSD_HEIGHT,
// DDSD_WIDTH and DDSD_PIXELFORMAT are required; DDSD_PITCH and
// DDSD_LINEARSIZE are mutually exclusive; depth and mipMapCount are
// cross-checked against their flags; a DDSCAPS2_VOLUME texture needs a
// nonzero depth. reserved2 is not validated, is preserved by the parser and
// re-emitted by the builder.
//
// v0.61.3 notes that shaped this module: Ok/Err for struct payloads are only
// constructed in the small leaf helpers below; every byte read is widened
// with `(data[pos] as Int) & 0xFF`; Str values derived from file bytes are
// only produced as fourCC text through the printable-ASCII table; no
// Vec[StructType] is declared and no parallel index vectors are kept.

module xiom.dds

use xiom.string;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// The 32-byte DDS_PIXELFORMAT (size in the file must be 32). `four_cc` is
/// the code read as a little-endian u32, so DXT1 is 0x31545844 and its text
/// form is "DXT1"; 0 means no fourCC. For a fourCC format `rgb_bit_count` and
/// the masks are carried through untouched (some writers set them for YUV
/// codes); for DDPF_RGB they carry the channel masks.
pub type DdsPixelFormat = {
  size: Int;
  flags: Int;
  four_cc: Int;
  rgb_bit_count: Int;
  r_mask: Int;
  g_mask: Int;
  b_mask: Int;
  a_mask: Int;
}

/// The 124-byte DDS_HEADER, fully decoded except reserved1 (validated as all
/// zero and not retained) and reserved2 (retained verbatim). `depth` is 0
/// for 2D and cube textures; `mip_map_count` is 0 when DDSD_MIPMAPCOUNT is
/// absent, which means "one level".
pub type DdsHeader = {
  size: Int;
  flags: Int;
  height: Int;
  width: Int;
  pitch_or_linear_size: Int;
  depth: Int;
  mip_map_count: Int;
  pixel_format: DdsPixelFormat;
  caps: Int;
  caps2: Int;
  caps3: Int;
  caps4: Int;
  reserved2: Int;
}

/// The 20-byte DDS_HEADER_DXT10 block, present when the pixel format uses
/// the DX10 fourCC. The fields are carried through verbatim; the parser only
/// requires `resource_dimension` in 2..4 and `array_size` >= 1.
pub type DdsDxt10 = {
  dxgi_format: Int;
  resource_dimension: Int;
  misc_flag: Int;
  array_size: Int;
  misc_flags2: Int;
}

/// A parsed DDS buffer: the decoded header, the decoded DXT10 block (all
/// zero when absent), `has_dx10` and the payload span. `data_offset` is 128
/// without a DXT10 block and 148 with one; `data_bytes` is the rest of the
/// buffer (the payload is opaque).
pub type DdsImage = {
  header: DdsHeader;
  dx10: DdsDxt10;
  has_dx10: Bool;
  data_offset: Int;
  data_bytes: Int;
}

// --------------------------------------------------
//  Format constants
// --------------------------------------------------

// Magic "DDS " read as a little-endian u32.
pub const DDS_MAGIC: Int = 0x20534444;

// Fixed structural sizes.
pub const DDS_HEADER_SIZE: Int = 124;
pub const DDS_PIXEL_FORMAT_SIZE: Int = 32;
pub const DDS_DATA_OFFSET: Int = 128;
pub const DDS_DX10_OFFSET: Int = 148;

// DDS_HEADER flags.
pub const DDSD_CAPS: Int = 0x1;
pub const DDSD_HEIGHT: Int = 0x2;
pub const DDSD_WIDTH: Int = 0x4;
pub const DDSD_PITCH: Int = 0x8;
pub const DDSD_PIXELFORMAT: Int = 0x1000;
pub const DDSD_MIPMAPCOUNT: Int = 0x20000;
pub const DDSD_LINEARSIZE: Int = 0x80000;
pub const DDSD_DEPTH: Int = 0x800000;

// DDS_PIXELFORMAT flags.
pub const DDPF_ALPHAPIXELS: Int = 0x1;
pub const DDPF_ALPHA: Int = 0x2;
pub const DDPF_FOURCC: Int = 0x4;
pub const DDPF_RGB: Int = 0x40;
pub const DDPF_YUV: Int = 0x200;
pub const DDPF_LUMINANCE: Int = 0x20000;

// DDSCAPS / DDSCAPS2 bits used by the documented subset.
pub const DDSCAPS_COMPLEX: Int = 0x8;
pub const DDSCAPS_TEXTURE: Int = 0x1000;
pub const DDSCAPS_MIPMAP: Int = 0x400000;
pub const DDSCAPS2_CUBEMAP: Int = 0x200;
pub const DDSCAPS2_CUBEMAP_ALLFACES: Int = 0xFC00;
pub const DDSCAPS2_VOLUME: Int = 0x200000;

// Recognized fourCCs (little-endian, file byte order).
pub const DDS_FOURCC_DXT1: Int = 0x31545844;
pub const DDS_FOURCC_DXT2: Int = 0x32545844;
pub const DDS_FOURCC_DXT3: Int = 0x33545844;
pub const DDS_FOURCC_DXT4: Int = 0x34545844;
pub const DDS_FOURCC_DXT5: Int = 0x35545844;
pub const DDS_FOURCC_DX10: Int = 0x30315844;

// Absolute byte offsets inside a DDS buffer (magic included).
const _OFF_MAGIC: Int = 0;
const _OFF_SIZE: Int = 4;
const _OFF_FLAGS: Int = 8;
const _OFF_HEIGHT: Int = 12;
const _OFF_WIDTH: Int = 16;
const _OFF_PITCH: Int = 20;
const _OFF_DEPTH: Int = 24;
const _OFF_MIPMAPS: Int = 28;
const _OFF_RESERVED1: Int = 32;
const _OFF_PF_SIZE: Int = 76;
const _OFF_PF_FLAGS: Int = 80;
const _OFF_PF_FOURCC: Int = 84;
const _OFF_PF_BITS: Int = 88;
const _OFF_PF_R: Int = 92;
const _OFF_PF_G: Int = 96;
const _OFF_PF_B: Int = 100;
const _OFF_PF_A: Int = 104;
const _OFF_CAPS: Int = 108;
const _OFF_CAPS2: Int = 112;
const _OFF_CAPS3: Int = 116;
const _OFF_CAPS4: Int = 120;
const _OFF_RESERVED2: Int = 124;
const _OFF_DX10_DXGI: Int = 128;
const _OFF_DX10_DIM: Int = 132;
const _OFF_DX10_MISC: Int = 136;
const _OFF_DX10_ARRAY: Int = 140;
const _OFF_DX10_MISC2: Int = 144;

// --------------------------------------------------
//  Byte readers and writers (little-endian)
// --------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Unsigned 32-bit little-endian value at `off`.
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  let b2 = _b(data, off + 2);
  let b3 = _b(data, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Append the low 32 bits of v, little-endian. Callers range-check first.
fn _p32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// True when v fits an unsigned 32-bit field.
fn _u32_ok(v: Int) -> Bool {
  if (v < 0) { return false; }
  if (v > 4294967295) { return false; }
  return true;
}

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

fn _err_header(m: Str) -> Result[DdsHeader, Str] { return Err(m); }
fn _ok_header(h: DdsHeader) -> Result[DdsHeader, Str] { return Ok(h); }
fn _err_pf(m: Str) -> Result[DdsPixelFormat, Str] { return Err(m); }
fn _ok_pf(p: DdsPixelFormat) -> Result[DdsPixelFormat, Str] { return Ok(p); }
fn _err_dx10(m: Str) -> Result[DdsDxt10, Str] { return Err(m); }
fn _ok_dx10(d: DdsDxt10) -> Result[DdsDxt10, Str] { return Ok(d); }
fn _err_image(m: Str) -> Result[DdsImage, Str] { return Err(m); }
fn _ok_image(v: DdsImage) -> Result[DdsImage, Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// --------------------------------------------------
//  Predicates and small helpers
// --------------------------------------------------

// True when the pixel-format flags select the DX10 fourCC extension.
fn _is_dx10(pf_flags: Int, four_cc: Int) -> Bool {
  if ((pf_flags & DDPF_FOURCC) == 0) { return false; }
  return four_cc == DDS_FOURCC_DX10;
}

// The all-zero DXT10 block used when no DX10 header is present.
fn _zero_dx10() -> DdsDxt10 {
  return DdsDxt10{
    dxgi_format: 0;
    resource_dimension: 0;
    misc_flag: 0;
    array_size: 0;
    misc_flags2: 0;
  };
}

// Largest value representable in `bits` bits (2^bits - 1). Only called with
// 16, 24 or 32.
fn _mask_limit(bits: Int) -> Int {
  var m = 1;
  var i = 0;
  while (i < bits) {
    m = m * 2;
    i = i + 1;
  }
  return m - 1;
}

// Printable ASCII 0x20..0x7E, indexed as (byte - 32). This is the only
// source of Str values derived from file bytes, so no NUL byte can ever end
// up inside a Str.
fn _printable_table() -> Str {
  return " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
}

// One fourCC byte as text: the printable character, or "." outside
// 0x20..0x7E.
fn _fourcc_char(b: Int) -> Str {
  if (b < 32) { return "."; }
  if (b > 126) { return "."; }
  return string.str_slice(_printable_table(), b - 32, b - 31);
}

/// True when the codec knows the fourCC: DXT1, DXT2, DXT3, DXT4, DXT5 or
/// DX10. Unknown codes are still accepted by the parser (pass-through); this
/// predicate is the documented way to tell the two apart.
pub fn dds_fourcc_recognized(code: Int) -> Bool {
  if (code == DDS_FOURCC_DXT1) { return true; }
  if (code == DDS_FOURCC_DXT2) { return true; }
  if (code == DDS_FOURCC_DXT3) { return true; }
  if (code == DDS_FOURCC_DXT4) { return true; }
  if (code == DDS_FOURCC_DXT5) { return true; }
  if (code == DDS_FOURCC_DX10) { return true; }
  return false;
}

/// True when the pixel-format flag shape is inside the documented subset:
/// exactly one of DDPF_FOURCC (with a nonzero code) and DDPF_RGB (with no
/// fourCC), never both, never neither. The parser additionally validates the
/// RGB bit count and masks; fourCC codes are accepted whatever their value.
pub fn dds_pixel_format_supported(flags: Int, four_cc: Int) -> Bool {
  let has_fourcc = (flags & DDPF_FOURCC) != 0;
  let has_rgb = (flags & DDPF_RGB) != 0;
  if (has_fourcc && has_rgb) { return false; }
  if (has_fourcc) { return four_cc != 0; }
  if (has_rgb) { return four_cc == 0; }
  return false;
}

/// The fourCC code as four characters in file byte order: DXT1 for
/// 0x31545844, DX10 for 0x30315844, and e.g. "UYVY" for 0x59565955.
/// Non-printable bytes render as ".". Code 0 (no fourCC) and values outside
/// the unsigned 32-bit range return "".
pub fn dds_fourcc_text(code: Int) -> Str {
  if (code <= 0) { return ""; }
  if (code > 4294967295) { return ""; }
  let b0 = code % 256;
  let b1 = (code / 256) % 256;
  let b2 = (code / 65536) % 256;
  let b3 = (code / 16777216) % 256;
  return _fourcc_char(b0) + _fourcc_char(b1) + _fourcc_char(b2) + _fourcc_char(b3);
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// Decode and validate the DDS_PIXELFORMAT at bytes 76..108. Flag shape and
// RGB mask rules are documented in SPEC.md; the rules match
// dds_pixel_format_supported plus the extra uncompressed-mask checks.
fn _parse_pixel_format(data: &Vec[UInt8]) -> Result[DdsPixelFormat, Str] {
  let size = _le32(data, _OFF_PF_SIZE);
  if (size != 32) { return _err_pf("dds: invalid pixel format size"); }
  let flags = _le32(data, _OFF_PF_FLAGS);
  let four_cc = _le32(data, _OFF_PF_FOURCC);
  let bits = _le32(data, _OFF_PF_BITS);
  let r = _le32(data, _OFF_PF_R);
  let g = _le32(data, _OFF_PF_G);
  let b = _le32(data, _OFF_PF_B);
  let a = _le32(data, _OFF_PF_A);
  let has_fourcc = (flags & DDPF_FOURCC) != 0;
  let has_rgb = (flags & DDPF_RGB) != 0;
  if (has_fourcc && has_rgb) {
    return _err_pf("dds: conflicting pixel format flags");
  }
  if (has_fourcc) {
    if (four_cc == 0) { return _err_pf("dds: missing fourCC"); }
  } else {
    if (has_rgb) {
      if (four_cc != 0) { return _err_pf("dds: unexpected fourCC"); }
      if (bits != 16 && bits != 24 && bits != 32) {
        return _err_pf("dds: unsupported RGB bit count");
      }
      if (r == 0 || g == 0 || b == 0) {
        return _err_pf("dds: invalid RGB masks");
      }
      if ((r & g) != 0 || (r & b) != 0 || (g & b) != 0) {
        return _err_pf("dds: overlapping color masks");
      }
      if (a != 0 && ((a & r) != 0 || (a & g) != 0 || (a & b) != 0)) {
        return _err_pf("dds: overlapping color masks");
      }
      let limit = _mask_limit(bits);
      if (r > limit || g > limit || b > limit || a > limit) {
        return _err_pf("dds: color mask out of range");
      }
    } else {
      return _err_pf("dds: unsupported pixel format");
    }
  }
  let pf = DdsPixelFormat{
    size: size;
    flags: flags;
    four_cc: four_cc;
    rgb_bit_count: bits;
    r_mask: r;
    g_mask: g;
    b_mask: b;
    a_mask: a;
  };
  return _ok_pf(pf);
}

/// Parse and validate the 128-byte prefix (magic + DDS_HEADER). Structural
/// and cross-field rules are documented in SPEC.md. The DXT10 block and the
/// payload are not required here; use dds_parse for a whole buffer.
pub fn dds_parse_header(data: &Vec[UInt8]) -> Result[DdsHeader, Str] {
  if (data.len() < DDS_DATA_OFFSET) { return _err_header("dds: truncated header"); }
  if (_b(data, _OFF_MAGIC) != 68) { return _err_header("dds: bad magic"); }
  if (_b(data, _OFF_MAGIC + 1) != 68) { return _err_header("dds: bad magic"); }
  if (_b(data, _OFF_MAGIC + 2) != 83) { return _err_header("dds: bad magic"); }
  if (_b(data, _OFF_MAGIC + 3) != 32) { return _err_header("dds: bad magic"); }
  let size = _le32(data, _OFF_SIZE);
  if (size != DDS_HEADER_SIZE) { return _err_header("dds: invalid header size"); }
  var i = 0;
  while (i < 11) {
    if (_le32(data, _OFF_RESERVED1 + i * 4) != 0) {
      return _err_header("dds: nonzero reserved1");
    }
    i = i + 1;
  }
  let flags = _le32(data, _OFF_FLAGS);
  let required = DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT;
  if ((flags & required) != required) {
    return _err_header("dds: missing required flags");
  }
  if (((flags & DDSD_PITCH) != 0) && ((flags & DDSD_LINEARSIZE) != 0)) {
    return _err_header("dds: conflicting pitch flags");
  }
  let height = _le32(data, _OFF_HEIGHT);
  if (height == 0 || height > 1000000) {
    return _err_header("dds: invalid height");
  }
  let width = _le32(data, _OFF_WIDTH);
  if (width == 0 || width > 1000000) {
    return _err_header("dds: invalid width");
  }
  let pitch = _le32(data, _OFF_PITCH);
  let depth = _le32(data, _OFF_DEPTH);
  if (depth > 0 && (flags & DDSD_DEPTH) == 0) {
    return _err_header("dds: depth without DDSD_DEPTH");
  }
  if (depth == 0 && (flags & DDSD_DEPTH) != 0) {
    return _err_header("dds: invalid depth");
  }
  let mips = _le32(data, _OFF_MIPMAPS);
  if (mips > 0 && (flags & DDSD_MIPMAPCOUNT) == 0) {
    return _err_header("dds: mipmaps without DDSD_MIPMAPCOUNT");
  }
  if (mips == 0 && (flags & DDSD_MIPMAPCOUNT) != 0) {
    return _err_header("dds: invalid mipmap count");
  }
  let pfp = _parse_pixel_format(data);
  if (!pfp.is_ok) { return _err_header(pfp.error); }
  let pf: DdsPixelFormat = pfp.value;
  let caps = _le32(data, _OFF_CAPS);
  let caps2 = _le32(data, _OFF_CAPS2);
  if ((caps2 & DDSCAPS2_VOLUME) != 0 && depth == 0) {
    return _err_header("dds: volume without depth");
  }
  let caps3 = _le32(data, _OFF_CAPS3);
  let caps4 = _le32(data, _OFF_CAPS4);
  let reserved2 = _le32(data, _OFF_RESERVED2);
  let h = DdsHeader{
    size: size;
    flags: flags;
    height: height;
    width: width;
    pitch_or_linear_size: pitch;
    depth: depth;
    mip_map_count: mips;
    pixel_format: pf;
    caps: caps;
    caps2: caps2;
    caps3: caps3;
    caps4: caps4;
    reserved2: reserved2;
  };
  return _ok_header(h);
}

// Decode and validate the 20-byte DDS_HEADER_DXT10 block at bytes 128..148.
fn _parse_dx10(data: &Vec[UInt8]) -> Result[DdsDxt10, Str] {
  if (data.len() < DDS_DX10_OFFSET) {
    return _err_dx10("dds: truncated dx10 header");
  }
  let dxgi = _le32(data, _OFF_DX10_DXGI);
  let dim = _le32(data, _OFF_DX10_DIM);
  if (dim < 2 || dim > 4) {
    return _err_dx10("dds: invalid resource dimension");
  }
  let misc = _le32(data, _OFF_DX10_MISC);
  let array = _le32(data, _OFF_DX10_ARRAY);
  if (array == 0) { return _err_dx10("dds: invalid array size"); }
  let misc2 = _le32(data, _OFF_DX10_MISC2);
  let d = DdsDxt10{
    dxgi_format: dxgi;
    resource_dimension: dim;
    misc_flag: misc;
    array_size: array;
    misc_flags2: misc2;
  };
  return _ok_dx10(d);
}

/// Parse and validate a whole DDS buffer: the header, the DXT10 block when
/// the pixel format uses the DX10 fourCC, and the payload span. The payload
/// itself is opaque and may be empty. Err messages are deterministic, see
/// SPEC.md for the catalog and the validation order.
pub fn dds_parse(data: &Vec[UInt8]) -> Result[DdsImage, Str] {
  let n = data.len();
  let hp = dds_parse_header(data);
  if (!hp.is_ok) { return _err_image(hp.error); }
  let h: DdsHeader = hp.value;
  let pf: DdsPixelFormat = h.pixel_format;
  let has = _is_dx10(pf.flags, pf.four_cc);
  var d = _zero_dx10();
  if (has) {
    let dp = _parse_dx10(data);
    if (!dp.is_ok) { return _err_image(dp.error); }
    d = dp.value;
  }
  let off = DDS_DATA_OFFSET;
  if (has) { off = DDS_DX10_OFFSET; }
  let img = DdsImage{
    header: h;
    dx10: d;
    has_dx10: has;
    data_offset: off;
    data_bytes: n - off;
  };
  return _ok_image(img);
}

/// True when dds_parse succeeds. Complexity: O(data.len()).
pub fn dds_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = dds_parse(data);
  return r.is_ok;
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Texture width in pixels.
pub fn dds_width(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  return h.width;
}

/// Texture height in pixels.
pub fn dds_height(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  return h.height;
}

/// Volume depth: 0 for 2D and cube textures, >= 1 for volume textures.
pub fn dds_depth(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  return h.depth;
}

/// Stored mipMapCount: 0 when DDSD_MIPMAPCOUNT is absent, which means one
/// level; otherwise the declared number of levels (>= 1).
pub fn dds_mipmaps(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  return h.mip_map_count;
}

/// The pixel format's fourCC code (0 when none).
pub fn dds_fourcc(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  let pf: DdsPixelFormat = h.pixel_format;
  return pf.four_cc;
}

/// True when the file carries the 20-byte DDS_HEADER_DXT10 block.
pub fn dds_has_dx10(img: &DdsImage) -> Bool {
  return img.has_dx10;
}

/// DXGI format id from the DXT10 block (0 when absent; never validated).
pub fn dds_dxgi_format(img: &DdsImage) -> Int {
  let d: DdsDxt10 = img.dx10;
  return d.dxgi_format;
}

/// D3D10_RESOURCE_DIMENSION from the DXT10 block: 2, 3 or 4 when present.
pub fn dds_resource_dimension(img: &DdsImage) -> Int {
  let d: DdsDxt10 = img.dx10;
  return d.resource_dimension;
}

/// Array size from the DXT10 block (>= 1 when present; 0 when absent).
pub fn dds_array_size(img: &DdsImage) -> Int {
  let d: DdsDxt10 = img.dx10;
  return d.array_size;
}

/// miscFlag from the DXT10 block (0 when absent).
pub fn dds_misc_flag(img: &DdsImage) -> Int {
  let d: DdsDxt10 = img.dx10;
  return d.misc_flag;
}

/// miscFlags2 from the DXT10 block (0 when absent).
pub fn dds_misc_flags2(img: &DdsImage) -> Int {
  let d: DdsDxt10 = img.dx10;
  return d.misc_flags2;
}

/// RGBBitCount of the pixel format (0 for fourCC formats).
pub fn dds_rgb_bit_count(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  let pf: DdsPixelFormat = h.pixel_format;
  return pf.rgb_bit_count;
}

/// Red channel mask of an uncompressed format (0 for fourCC formats).
pub fn dds_red_mask(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  let pf: DdsPixelFormat = h.pixel_format;
  return pf.r_mask;
}

/// Green channel mask of an uncompressed format (0 for fourCC formats).
pub fn dds_green_mask(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  let pf: DdsPixelFormat = h.pixel_format;
  return pf.g_mask;
}

/// Blue channel mask of an uncompressed format (0 for fourCC formats).
pub fn dds_blue_mask(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  let pf: DdsPixelFormat = h.pixel_format;
  return pf.b_mask;
}

/// Alpha channel mask (0 when the format has no alpha channel).
pub fn dds_alpha_mask(img: &DdsImage) -> Int {
  let h: DdsHeader = img.header;
  let pf: DdsPixelFormat = h.pixel_format;
  return pf.a_mask;
}

/// Absolute offset of the first payload byte: 128 without a DXT10 block,
/// 148 with one.
pub fn dds_payload_offset(img: &DdsImage) -> Int {
  return img.data_offset;
}

/// Payload length: everything after the header prefix (and the DXT10 block
/// when present). The payload is opaque, mips and faces are not sliced.
pub fn dds_payload_size(img: &DdsImage) -> Int {
  return img.data_bytes;
}

/// Copy the payload span (empty for a header-only buffer). Err when the
/// buffer does not parse.
pub fn dds_payload(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let pr = dds_parse(data);
  if (!pr.is_ok) { return _err_bytes(pr.error); }
  let img: DdsImage = pr.value;
  let off = img.data_offset;
  let n = img.data_bytes;
  let out = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Build the canonical 128-byte prefix: "DDS " magic plus the 124-byte
/// DDS_HEADER, with reserved1 written as zero. `h.size` must be 124 and
/// `h.pixel_format.size` must be 32; every field must fit its unsigned
/// 32-bit slot, and the assembled bytes are re-validated through
/// dds_parse_header, whose messages are forwarded unchanged. The DXT10
/// block is not emitted here -- use dds_build_dx10, or dds_build for a whole
/// file.
pub fn dds_build_header(h: &DdsHeader) -> Result[Vec[UInt8], Str] {
  if (h.size != DDS_HEADER_SIZE) { return _err_bytes("dds: invalid header size"); }
  let pf: DdsPixelFormat = h.pixel_format;
  if (pf.size != DDS_PIXEL_FORMAT_SIZE) {
    return _err_bytes("dds: invalid pixel format size");
  }
  if (!_u32_ok(h.flags)) { return _err_bytes("dds: flags out of range"); }
  if (!_u32_ok(h.height)) { return _err_bytes("dds: height out of range"); }
  if (!_u32_ok(h.width)) { return _err_bytes("dds: width out of range"); }
  if (!_u32_ok(h.pitch_or_linear_size)) {
    return _err_bytes("dds: pitch out of range");
  }
  if (!_u32_ok(h.depth)) { return _err_bytes("dds: depth out of range"); }
  if (!_u32_ok(h.mip_map_count)) {
    return _err_bytes("dds: mipmap count out of range");
  }
  if (!_u32_ok(pf.flags)) { return _err_bytes("dds: pixel format flags out of range"); }
  if (!_u32_ok(pf.four_cc)) { return _err_bytes("dds: fourCC out of range"); }
  if (!_u32_ok(pf.rgb_bit_count)) { return _err_bytes("dds: RGB bit count out of range"); }
  if (!_u32_ok(pf.r_mask)) { return _err_bytes("dds: red mask out of range"); }
  if (!_u32_ok(pf.g_mask)) { return _err_bytes("dds: green mask out of range"); }
  if (!_u32_ok(pf.b_mask)) { return _err_bytes("dds: blue mask out of range"); }
  if (!_u32_ok(pf.a_mask)) { return _err_bytes("dds: alpha mask out of range"); }
  if (!_u32_ok(h.caps)) { return _err_bytes("dds: caps out of range"); }
  if (!_u32_ok(h.caps2)) { return _err_bytes("dds: caps2 out of range"); }
  if (!_u32_ok(h.caps3)) { return _err_bytes("dds: caps3 out of range"); }
  if (!_u32_ok(h.caps4)) { return _err_bytes("dds: caps4 out of range"); }
  if (!_u32_ok(h.reserved2)) { return _err_bytes("dds: reserved2 out of range"); }
  let out = Vec[UInt8].new();
  out.push(68 as UInt8);
  out.push(68 as UInt8);
  out.push(83 as UInt8);
  out.push(32 as UInt8);
  _p32(&mut out, DDS_HEADER_SIZE);
  _p32(&mut out, h.flags);
  _p32(&mut out, h.height);
  _p32(&mut out, h.width);
  _p32(&mut out, h.pitch_or_linear_size);
  _p32(&mut out, h.depth);
  _p32(&mut out, h.mip_map_count);
  var i = 0;
  while (i < 11) {
    _p32(&mut out, 0);
    i = i + 1;
  }
  _p32(&mut out, DDS_PIXEL_FORMAT_SIZE);
  _p32(&mut out, pf.flags);
  _p32(&mut out, pf.four_cc);
  _p32(&mut out, pf.rgb_bit_count);
  _p32(&mut out, pf.r_mask);
  _p32(&mut out, pf.g_mask);
  _p32(&mut out, pf.b_mask);
  _p32(&mut out, pf.a_mask);
  _p32(&mut out, h.caps);
  _p32(&mut out, h.caps2);
  _p32(&mut out, h.caps3);
  _p32(&mut out, h.caps4);
  _p32(&mut out, h.reserved2);
  let check = dds_parse_header(out);
  if (!check.is_ok) { return _err_bytes(check.error); }
  return _ok_bytes(out);
}

/// Build the 20-byte DDS_HEADER_DXT10 block. `resource_dimension` must be
/// 2, 3 or 4 and `array_size` must be >= 1; all five fields must fit their
/// unsigned 32-bit slots. The emitted block is checked with the same rules
/// as the parser.
pub fn dds_build_dx10(d: &DdsDxt10) -> Result[Vec[UInt8], Str] {
  if (!_u32_ok(d.dxgi_format)) {
    return _err_bytes("dds: dxgi format out of range");
  }
  if (!_u32_ok(d.resource_dimension)) {
    return _err_bytes("dds: resource dimension out of range");
  }
  if (!_u32_ok(d.misc_flag)) {
    return _err_bytes("dds: misc flag out of range");
  }
  if (!_u32_ok(d.array_size)) {
    return _err_bytes("dds: array size out of range");
  }
  if (!_u32_ok(d.misc_flags2)) {
    return _err_bytes("dds: misc flags2 out of range");
  }
  if (d.resource_dimension < 2 || d.resource_dimension > 4) {
    return _err_bytes("dds: invalid resource dimension");
  }
  if (d.array_size == 0) { return _err_bytes("dds: invalid array size"); }
  let out = Vec[UInt8].new();
  _p32(&mut out, d.dxgi_format);
  _p32(&mut out, d.resource_dimension);
  _p32(&mut out, d.misc_flag);
  _p32(&mut out, d.array_size);
  _p32(&mut out, d.misc_flags2);
  return _ok_bytes(out);
}

/// Build a whole DDS file: the 128-byte header prefix, the DXT10 block when
/// `img.has_dx10` and the pixel format uses the DX10 fourCC, then `payload`
/// verbatim. `img.has_dx10` must agree with the DX10 fourCC and
/// `payload.len()` must equal `img.data_bytes`; the assembled bytes are
/// re-parsed with dds_parse, whose messages are forwarded unchanged, so the
/// result always parses back to the same fields. Complexity: O(payload.len()).
pub fn dds_build(img: &DdsImage, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let h: DdsHeader = img.header;
  let pf: DdsPixelFormat = h.pixel_format;
  let has = _is_dx10(pf.flags, pf.four_cc);
  if (has != img.has_dx10) { return _err_bytes("dds: dx10 flag mismatch"); }
  if (payload.len() != img.data_bytes) {
    return _err_bytes("dds: payload size mismatch");
  }
  let hb = dds_build_header(&h);
  if (!hb.is_ok) { return _err_bytes(hb.error); }
  let hbytes: Vec[UInt8] = hb.value;
  let out = Vec[UInt8].new();
  var i = 0;
  while (i < hbytes.len()) {
    out.push(hbytes[i]);
    i = i + 1;
  }
  if (has) {
    let d: DdsDxt10 = img.dx10;
    let db = dds_build_dx10(&d);
    if (!db.is_ok) { return _err_bytes(db.error); }
    let dbytes: Vec[UInt8] = db.value;
    var k = 0;
    while (k < dbytes.len()) {
      out.push(dbytes[k]);
      k = k + 1;
    }
  }
  var j = 0;
  while (j < payload.len()) {
    out.push(payload[j]);
    j = j + 1;
  }
  let check = dds_parse(&out);
  if (!check.is_ok) { return _err_bytes(check.error); }
  return _ok_bytes(out);
}
