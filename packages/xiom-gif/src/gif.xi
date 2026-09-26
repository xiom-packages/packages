// XIOM -- xiom.gif: GIF87a/GIF89a structure parser (no pixel decoding)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the container structure of the Graphics Interchange Format over a
// flat Vec[UInt8] buffer. The parser walks the exact byte stream:
//
//   header            := "GIF" ("87a" | "89a")
//   screen descriptor := LE16(width) LE16(height) packed bg_index aspect
//   global table      := 3 * 2^(N+1) bytes, present when packed bit 7 is set
//   blocks            := block* trailer
//   block             := image | extension
//   image             := 0x2C LE16(left) LE16(top) LE16(w) LE16(h) packed
//                        [local table] lzw_min sub-block* 0x00
//   extension         := 0x21 label body
//   trailer           := 0x3B
//
// LZW image data is OPAQUE: sub-block framing is validated and the raw
// concatenated payload bytes are copied out, but no code is decoded and no
// pixel is ever produced. Color tables are copied verbatim and exposed as
// RGB lookups. Extensions are recorded as a flat list; the graphic control
// extension additionally attaches delay/disposal/transparency to the NEXT
// image descriptor only, exactly as the specification scopes it.
//
// Every failure is Err(Str) with a deterministic "gif: " message that
// carries the absolute byte offset at which parsing failed, e.g.
// "gif: truncated image descriptor at offset 23" or
// "gif: unknown block id at offset 13". See SPEC.md for the catalog.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[i] as Int) & 0xFF`.
//   * no Vec[StructType]: per-frame state lives in parallel Vec[Int] fields
//     plus one flat payload vector, and every vector is written through a
//     single push helper so they cannot drift.
//   * dynamic messages use convert.int_to_string (no sb_to_str).
// See SPEC.md for the byte layout, validation order, error catalog and the
// test matrix.

module xiom.gif

use xiom.convert;

// ---------------------------------------------------------------------------
//  Constants
// ---------------------------------------------------------------------------

/// Version code of the GIF87a signature (bytes 3..5 = "87a").
pub const GIF_VERSION_87A: Int = 87;

/// Version code of the GIF89a signature (bytes 3..5 = "89a").
pub const GIF_VERSION_89A: Int = 89;

/// Block introducer of an image descriptor, 0x2C.
pub const GIF_BLOCK_IMAGE: Int = 44;

/// Block introducer of an extension, 0x21.
pub const GIF_BLOCK_EXTENSION: Int = 33;

/// Block introducer of the trailer, 0x3B.
pub const GIF_BLOCK_TRAILER: Int = 59;

/// Extension label of a graphic control extension, 0xF9.
pub const GIF_LABEL_GRAPHIC_CONTROL: Int = 249;

/// Extension label of a comment extension, 0xFE.
pub const GIF_LABEL_COMMENT: Int = 254;

/// Extension label of a plain text extension, 0x01.
pub const GIF_LABEL_PLAIN_TEXT: Int = 1;

/// Extension label of an application extension, 0xFF.
pub const GIF_LABEL_APPLICATION: Int = 255;

/// Extension record kind of a graphic control extension.
pub const GIF_EXT_KIND_CONTROL: Int = 0;

/// Extension record kind of a comment extension.
pub const GIF_EXT_KIND_COMMENT: Int = 1;

/// Extension record kind of a plain text extension.
pub const GIF_EXT_KIND_PLAIN_TEXT: Int = 2;

/// Extension record kind of an application extension.
pub const GIF_EXT_KIND_APPLICATION: Int = 3;

/// Disposal method 0: no disposal method specified.
pub const GIF_DISPOSAL_UNSPECIFIED: Int = 0;

/// Disposal method 1: leave the frame in place.
pub const GIF_DISPOSAL_KEEP: Int = 1;

/// Disposal method 2: restore to the background color.
pub const GIF_DISPOSAL_BACKGROUND: Int = 2;

/// Disposal method 3: restore to the previous frame.
pub const GIF_DISPOSAL_PREVIOUS: Int = 3;

// ---------------------------------------------------------------------------
//  Public types
// ---------------------------------------------------------------------------

/// Parsed GIF container. Canvas fields come from the header and logical
/// screen descriptor; frame state lives in parallel Vec[Int] fields (entry i
/// belongs to frame i) plus one flat `payload` vector of opaque LZW bytes;
/// extensions live in parallel fields plus one flat `ext_bytes` vector.
/// `ext_bytes` holds, per extension, the fixed header (0 bytes for comments,
/// 4 for graphic control, 12 for plain text, 11 for application) followed by
/// the concatenated sub-block data.
pub type Gif = {
  version: Int;            // 87 or 89
  width: Int;              // logical screen width, 0..65535
  height: Int;             // logical screen height, 0..65535
  packed: Int;             // raw logical-screen-descriptor packed byte
  has_gct: Int;            // 0/1, packed bit 7
  color_resolution: Int;   // 0..7, packed bits 6..4
  sort_flag: Int;          // 0/1, packed bit 3
  gct_size: Int;           // global table entries (2^(N+1)), 0 when absent
  bg_index: Int;           // background color index
  aspect: Int;             // pixel aspect ratio byte (0 = unspecified)
  gct_bytes: Vec[UInt8];   // flat RGB triples, 3 * gct_size bytes
  frame_left: Vec[Int];
  frame_top: Vec[Int];
  frame_width: Vec[Int];
  frame_height: Vec[Int];
  frame_interlace: Vec[Int];      // 0/1
  frame_has_lct: Vec[Int];        // 0/1
  frame_lct_size: Vec[Int];       // entries, 0 when absent
  frame_lct_off: Vec[Int];        // offset into lct_bytes
  frame_lct_len: Vec[Int];        // 3 * lct_size, 0 when absent
  frame_lzw_min: Vec[Int];        // 2..8
  frame_lzw_min_off: Vec[Int];    // source offset of the code-size byte
  frame_data_off: Vec[Int];       // source offset of the first sub-block
  frame_data_len: Vec[Int];       // raw payload bytes, framing dropped
  frame_block_end: Vec[Int];      // source offset after the 0x00 terminator
  frame_pay_off: Vec[Int];        // offset into payload
  frame_delay: Vec[Int];          // GCE delay in 1/100 s, 0 by default
  frame_disposal: Vec[Int];       // GCE disposal method 0..7, 0 by default
  frame_user_input: Vec[Int];     // GCE user-input flag 0/1
  frame_transparent: Vec[Int];    // GCE transparency flag 0/1
  frame_trans_index: Vec[Int];    // GCE transparent color index
  frame_from_gce: Vec[Int];       // 0/1, whether a GCE applied to the frame
  payload: Vec[UInt8];            // concatenated opaque LZW bytes
  lct_bytes: Vec[UInt8];          // concatenated local color tables
  ext_kind: Vec[Int];             // GIF_EXT_KIND_*
  ext_offset: Vec[Int];           // source offset of the 0x21 introducer
  ext_hdr_off: Vec[Int];          // offset of the fixed header in ext_bytes
  ext_hdr_len: Vec[Int];          // 4, 12, 11 or 0 (comment)
  ext_data_off: Vec[Int];         // offset of the data in ext_bytes
  ext_data_len: Vec[Int];         // sub-block data byte count
  ext_bytes: Vec[UInt8];          // fixed headers + concatenated data
}

/// Decoded frame metadata. `data_offset` is the absolute source offset of
/// the first LZW sub-block length byte and `data_bytes` is the number of raw
/// payload bytes in the concatenated chain (framing dropped); `block_end` is
/// the offset just past the terminating 0x00. `gif_lzw_data` returns the
/// opaque bytes themselves. Frames without a preceding graphic control
/// extension report delay 0, disposal 0, transparency 0 and from_gce 0.
pub type GifFrame = {
  index: Int;
  left: Int;
  top: Int;
  width: Int;
  height: Int;
  interlace: Int;        // 0/1
  has_lct: Int;          // 0/1
  lct_size: Int;         // entries, 0 when absent
  lzw_min: Int;          // 2..8
  lzw_min_offset: Int;   // absolute offset of the code-size byte
  data_offset: Int;      // absolute offset of the first sub-block
  data_bytes: Int;       // raw payload bytes
  block_end: Int;        // absolute offset past the 0x00 terminator
  delay: Int;            // hundredths of a second
  disposal: Int;         // 0..7
  user_input: Int;       // 0/1
  transparent: Int;      // 0/1
  trans_index: Int;      // transparent color index
  from_gce: Int;         // 0/1, whether a GCE applied
}

/// One recorded extension. `offset` is the absolute source offset of its
/// 0x21 introducer; `hdr_offset`/`hdr_size` locate the fixed header inside
/// `ext_bytes` (0 bytes for comments, 4 for graphic control, 12 for plain
/// text, 11 for application); `data_offset`/`data_size` locate the
/// concatenated sub-block data in `ext_bytes` (empty for graphic control).
pub type GifExtension = {
  index: Int;
  kind: Int;         // GIF_EXT_KIND_*
  offset: Int;       // absolute offset of the 0x21 byte
  hdr_offset: Int;   // offset into ext_bytes
  hdr_size: Int;     // 0, 4, 11 or 12
  data_offset: Int;  // offset into ext_bytes
  data_size: Int;    // data byte count
}

// ---------------------------------------------------------------------------
//  Result leaf helpers (v0.61.3: Ok/Err are confined to these)
// ---------------------------------------------------------------------------

fn _ok_gif(v: Gif) -> Result[Gif, Str] { return Ok(v); }
fn _err_gif(m: Str) -> Result[Gif, Str] { return Err(m); }
fn _ok_frame(v: GifFrame) -> Result[GifFrame, Str] { return Ok(v); }
fn _err_frame(m: Str) -> Result[GifFrame, Str] { return Err(m); }
fn _ok_ext(v: GifExtension) -> Result[GifExtension, Str] { return Ok(v); }
fn _err_ext(m: Str) -> Result[GifExtension, Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
//  Byte helpers
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Unsigned 16-bit little-endian value at `off`.
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  return b0 + b1 * 256;
}

// Append `len` bytes of `data` starting at `from` to `out`.
fn _copy(out: &mut Vec[UInt8], data: &Vec[UInt8], from: Int, len: Int) {
  var i = 0;
  while (i < len) {
    let b: UInt8 = data[from + i];
    out.push(b);
    i = i + 1;
  }
}

// Message with a byte offset appended: prefix + decimal offset.
fn _at(prefix: Str, off: Int) -> Str {
  return prefix + convert.int_to_string(off);
}

// Number of color table entries for a packed size field N: 2^(N+1).
fn _table_size(exp: Int) -> Int {
  var size = 1;
  var k = 0;
  while (k <= exp) {
    size = size * 2;
    k = k + 1;
  }
  return size;
}

// Header signature: bytes 0..2 are "GIF" (71 73 70).
fn _sig_is(data: &Vec[UInt8]) -> Bool {
  if (_b(data, 0) != 71) { return false; }
  if (_b(data, 1) != 73) { return false; }
  if (_b(data, 2) != 70) { return false; }
  return true;
}

// Version bytes 3..5 are "87a" (56 55 97).
fn _ver_87(data: &Vec[UInt8]) -> Bool {
  if (_b(data, 3) != 56) { return false; }
  if (_b(data, 4) != 55) { return false; }
  if (_b(data, 5) != 97) { return false; }
  return true;
}

// Version bytes 3..5 are "89a" (56 57 97).
fn _ver_89(data: &Vec[UInt8]) -> Bool {
  if (_b(data, 3) != 56) { return false; }
  if (_b(data, 4) != 57) { return false; }
  if (_b(data, 5) != 97) { return false; }
  return true;
}

// ---------------------------------------------------------------------------
//  Internal state
// ---------------------------------------------------------------------------

// Mutable cursor and the pending graphic-control state that applies to the
// next image descriptor.
type _State = {
  pos: Int;
  pend_delay: Int;
  pend_disposal: Int;
  pend_user: Int;
  pend_trans: Int;
  pend_trans_index: Int;
  pend_from_gce: Int;
}

// One image's parallel field values, pushed atomically.
type _FrameData = {
  left: Int;
  top: Int;
  width: Int;
  height: Int;
  interlace: Int;
  has_lct: Int;
  lct_size: Int;
  lct_off: Int;
  lct_len: Int;
  lzw_min: Int;
  lzw_min_off: Int;
  data_off: Int;
  data_len: Int;
  block_end: Int;
  pay_off: Int;
  delay: Int;
  disposal: Int;
  user: Int;
  trans: Int;
  trans_index: Int;
  from_gce: Int;
}

// One extension's parallel field values, pushed atomically.
type _ExtData = {
  kind: Int;
  offset: Int;
  hdr_off: Int;
  hdr_len: Int;
  data_off: Int;
  data_len: Int;
}

// Append one frame: every frame vector receives exactly one entry, so
// parallel drift is structurally impossible.
fn _push_frame(g: &mut Gif, f: &_FrameData) {
  g.frame_left.push(f.left);
  g.frame_top.push(f.top);
  g.frame_width.push(f.width);
  g.frame_height.push(f.height);
  g.frame_interlace.push(f.interlace);
  g.frame_has_lct.push(f.has_lct);
  g.frame_lct_size.push(f.lct_size);
  g.frame_lct_off.push(f.lct_off);
  g.frame_lct_len.push(f.lct_len);
  g.frame_lzw_min.push(f.lzw_min);
  g.frame_lzw_min_off.push(f.lzw_min_off);
  g.frame_data_off.push(f.data_off);
  g.frame_data_len.push(f.data_len);
  g.frame_block_end.push(f.block_end);
  g.frame_pay_off.push(f.pay_off);
  g.frame_delay.push(f.delay);
  g.frame_disposal.push(f.disposal);
  g.frame_user_input.push(f.user);
  g.frame_transparent.push(f.trans);
  g.frame_trans_index.push(f.trans_index);
  g.frame_from_gce.push(f.from_gce);
}

// Append one extension record (the caller has already copied its bytes into
// ext_bytes, so the six vectors stay parallel by construction).
fn _push_ext(g: &mut Gif, e: &_ExtData) {
  g.ext_kind.push(e.kind);
  g.ext_offset.push(e.offset);
  g.ext_hdr_off.push(e.hdr_off);
  g.ext_hdr_len.push(e.hdr_len);
  g.ext_data_off.push(e.data_off);
  g.ext_data_len.push(e.data_len);
}

// ---------------------------------------------------------------------------
//  Sub-block stream
// ---------------------------------------------------------------------------

// Read a GIF sub-block chain starting at `start` (the first length byte),
// append the concatenated payload bytes to `out`, and return the offset just
// past the 0x00 terminator. A length byte whose payload does not fit, or a
// missing terminator, is Err(prefix + failing offset).
fn _collect_subblocks(out: &mut Vec[UInt8], data: &Vec[UInt8], n: Int, start: Int, prefix: Str) -> Result[Int, Str] {
  var pos = start;
  var done = 0;
  while (done == 0) {
    if (pos >= n) { return _err_int(_at(prefix, pos)); }
    let len = _b(data, pos);
    if (len == 0) {
      pos = pos + 1;
      done = 1;
    } else {
      if (pos + 1 + len > n) { return _err_int(_at(prefix, pos)); }
      _copy(out, data, pos + 1, len);
      pos = pos + 1 + len;
    }
  }
  return _ok_int(pos);
}

// ---------------------------------------------------------------------------
//  Image descriptor
// ---------------------------------------------------------------------------

// Parse one image descriptor plus its optional local color table, LZW code
// size and opaque sub-block payload. The pending graphic-control fields are
// attached to the frame and then reset. Returns "" on success.
fn _scan_image(g: &mut Gif, st: &mut _State, data: &Vec[UInt8], n: Int) -> Str {
  let start = st.pos;
  if (start + 10 > n) {
    return _at("gif: truncated image descriptor at offset ", start);
  }
  let left = _le16(data, start + 1);
  let top = _le16(data, start + 3);
  let width = _le16(data, start + 5);
  let height = _le16(data, start + 7);
  let packed = _b(data, start + 9);
  let has_lct = packed / 128;
  let interlace = (packed / 64) % 2;
  let lct_exp = packed % 8;
  var pos = start + 10;
  var lct_size = 0;
  var lct_off = 0;
  var lct_len = 0;
  if (has_lct == 1) {
    lct_size = _table_size(lct_exp);
    let lct_bytes = lct_size * 3;
    if (pos + lct_bytes > n) {
      return _at("gif: truncated local color table at offset ", pos);
    }
    lct_off = g.lct_bytes.len();
    _copy(&mut g.lct_bytes, data, pos, lct_bytes);
    lct_len = lct_bytes;
    pos = pos + lct_bytes;
  }
  if (pos >= n) {
    return _at("gif: truncated lzw code size at offset ", pos);
  }
  let lzw_min = _b(data, pos);
  let lzw_min_off = pos;
  if (lzw_min < 2 || lzw_min > 8) {
    return _at("gif: invalid lzw code size at offset ", pos);
  }
  pos = pos + 1;
  let data_off = pos;
  let pay_off = g.payload.len();
  var done = 0;
  while (done == 0) {
    if (pos >= n) {
      return _at("gif: truncated lzw sub-block at offset ", pos);
    }
    let len = _b(data, pos);
    if (len == 0) {
      pos = pos + 1;
      done = 1;
    } else {
      if (pos + 1 + len > n) {
        return _at("gif: truncated lzw sub-block at offset ", pos);
      }
      _copy(&mut g.payload, data, pos + 1, len);
      pos = pos + 1 + len;
    }
  }
  let data_len = g.payload.len() - pay_off;
  let f = _FrameData{
    left: left;
    top: top;
    width: width;
    height: height;
    interlace: interlace;
    has_lct: has_lct;
    lct_size: lct_size;
    lct_off: lct_off;
    lct_len: lct_len;
    lzw_min: lzw_min;
    lzw_min_off: lzw_min_off;
    data_off: data_off;
    data_len: data_len;
    block_end: pos;
    pay_off: pay_off;
    delay: st.pend_delay;
    disposal: st.pend_disposal;
    user: st.pend_user;
    trans: st.pend_trans;
    trans_index: st.pend_trans_index;
    from_gce: st.pend_from_gce;
  };
  _push_frame(g, &f);
  st.pend_delay = 0;
  st.pend_disposal = 0;
  st.pend_user = 0;
  st.pend_trans = 0;
  st.pend_trans_index = 0;
  st.pend_from_gce = 0;
  st.pos = pos;
  return "";
}

// ---------------------------------------------------------------------------
//  Extensions
// ---------------------------------------------------------------------------

// Parse one extension introduced at st.pos (the 0x21 byte). Graphic control
// bodies are 4 bytes plus a 0x00 terminator; plain text bodies are 12 bytes;
// application bodies are 11 bytes; comment bodies are empty. Comment, plain
// text and application extensions then carry a sub-block data chain.
fn _scan_extension(g: &mut Gif, st: &mut _State, data: &Vec[UInt8], n: Int) -> Str {
  let start = st.pos;
  if (start + 2 > n) {
    return _at("gif: truncated extension at offset ", start);
  }
  let label = _b(data, start + 1);
  if (label == 249) {
    if (start + 8 > n) {
      return _at("gif: malformed graphic control extension at offset ", start);
    }
    let size = _b(data, start + 2);
    if (size != 4) {
      return _at("gif: malformed graphic control extension at offset ", start);
    }
    if (_b(data, start + 7) != 0) {
      return _at("gif: malformed graphic control extension at offset ", start);
    }
    let hdr_off = g.ext_bytes.len();
    _copy(&mut g.ext_bytes, data, start + 3, 4);
    let e = _ExtData{
      kind: 0;
      offset: start;
      hdr_off: hdr_off;
      hdr_len: 4;
      data_off: g.ext_bytes.len();
      data_len: 0;
    };
    _push_ext(g, &e);
    let packed = _b(data, start + 3);
    st.pend_delay = _le16(data, start + 4);
    st.pend_disposal = (packed / 4) % 8;
    st.pend_user = (packed / 2) % 2;
    st.pend_trans = packed % 2;
    st.pend_trans_index = _b(data, start + 6);
    st.pend_from_gce = 1;
    st.pos = start + 8;
    return "";
  }
  if (label == 254) {
    let data_off = g.ext_bytes.len();
    let r = _collect_subblocks(&mut g.ext_bytes, data, n, start + 2, "gif: truncated extension sub-block at offset ");
    if (!r.is_ok) { return r.error; }
    let after: Int = r.value;
    let e = _ExtData{
      kind: 1;
      offset: start;
      hdr_off: data_off;
      hdr_len: 0;
      data_off: data_off;
      data_len: g.ext_bytes.len() - data_off;
    };
    _push_ext(g, &e);
    st.pos = after;
    return "";
  }
  if (label == 1) {
    if (start + 15 > n) {
      return _at("gif: malformed plain text extension at offset ", start);
    }
    if (_b(data, start + 2) != 12) {
      return _at("gif: malformed plain text extension at offset ", start);
    }
    let hdr_off = g.ext_bytes.len();
    _copy(&mut g.ext_bytes, data, start + 3, 12);
    let data_off = g.ext_bytes.len();
    let r = _collect_subblocks(&mut g.ext_bytes, data, n, start + 15, "gif: truncated extension sub-block at offset ");
    if (!r.is_ok) { return r.error; }
    let after: Int = r.value;
    let e = _ExtData{
      kind: 2;
      offset: start;
      hdr_off: hdr_off;
      hdr_len: 12;
      data_off: data_off;
      data_len: g.ext_bytes.len() - data_off;
    };
    _push_ext(g, &e);
    st.pos = after;
    return "";
  }
  if (label == 255) {
    if (start + 14 > n) {
      return _at("gif: malformed application extension at offset ", start);
    }
    if (_b(data, start + 2) != 11) {
      return _at("gif: malformed application extension at offset ", start);
    }
    let hdr_off = g.ext_bytes.len();
    _copy(&mut g.ext_bytes, data, start + 3, 11);
    let data_off = g.ext_bytes.len();
    let r = _collect_subblocks(&mut g.ext_bytes, data, n, start + 14, "gif: truncated extension sub-block at offset ");
    if (!r.is_ok) { return r.error; }
    let after: Int = r.value;
    let e = _ExtData{
      kind: 3;
      offset: start;
      hdr_off: hdr_off;
      hdr_len: 11;
      data_off: data_off;
      data_len: g.ext_bytes.len() - data_off;
    };
    _push_ext(g, &e);
    st.pos = after;
    return "";
  }
  return _at("gif: unknown extension label at offset ", start + 1);
}

// ---------------------------------------------------------------------------
//  Block stream
// ---------------------------------------------------------------------------

// Walk image, extension and trailer blocks until the trailer. Returns "" on
// success; the caller guarantees that st.pos is inside the buffer or equal
// to n (end of data).
fn _scan_stream(g: &mut Gif, st: &mut _State, data: &Vec[UInt8], n: Int) -> Str {
  var done = 0;
  while (done == 0) {
    if (st.pos >= n) {
      return _at("gif: missing trailer at offset ", n);
    }
    let b0 = _b(data, st.pos);
    if (b0 == 44) {
      let e = _scan_image(g, st, data, n);
      if (e.len() > 0) { return e; }
    } elif (b0 == 33) {
      let e = _scan_extension(g, st, data, n);
      if (e.len() > 0) { return e; }
    } elif (b0 == 59) {
      if (st.pos + 1 != n) {
        return _at("gif: trailing data at offset ", st.pos + 1);
      }
      done = 1;
    } else {
      return _at("gif: unknown block id at offset ", st.pos);
    }
  }
  return "";
}

// ---------------------------------------------------------------------------
//  Parser
// ---------------------------------------------------------------------------

/// Parse one complete GIF87a/GIF89a buffer.
///
/// Validation order (see SPEC.md for the exact catalog):
///   1. fewer than 6 bytes -> "gif: truncated header at offset <n>";
///   2. bytes 0..2 not "GIF" -> "gif: bad signature at offset 0";
///   3. bytes 3..5 not "87a"/"89a" -> "gif: bad version at offset 3";
///   4. fewer than 13 bytes -> "gif: truncated screen descriptor at offset 6";
///   5. a flagged global color table that does not fit ->
///      "gif: truncated global color table at offset 13";
///   6. block stream: image descriptors (descriptor, optional local color
///      table, code size 2..8, sub-block LZW chain), extensions (graphic
///      control, comment, plain text, application) and finally the 0x3B
///      trailer with no trailing byte;
///   7. an unknown block id or extension label, a truncated descriptor or
///      sub-block chain, and a missing trailer are reported with offsets.
///
/// LZW payloads stay opaque. Complexity: O(input bytes).
pub fn gif_parse(data: &Vec[UInt8]) -> Result[Gif, Str] {
  let n = data.len();
  if (n < 6) {
    return _err_gif(_at("gif: truncated header at offset ", n));
  }
  if (!_sig_is(data)) {
    return _err_gif("gif: bad signature at offset 0");
  }
  var version = 0;
  if (_ver_87(data)) {
    version = 87;
  } elif (_ver_89(data)) {
    version = 89;
  } else {
    return _err_gif("gif: bad version at offset 3");
  }
  if (n < 13) {
    return _err_gif("gif: truncated screen descriptor at offset 6");
  }
  let width = _le16(data, 6);
  let height = _le16(data, 8);
  let packed = _b(data, 10);
  let has_gct = packed / 128;
  let color_resolution = (packed / 16) % 8;
  let sort_flag = (packed / 8) % 2;
  let gct_exp = packed % 8;
  let bg_index = _b(data, 11);
  let aspect = _b(data, 12);
  var gct_size = 0;
  var pos = 13;
  if (has_gct == 1) {
    gct_size = _table_size(gct_exp);
    let gct_bytes = gct_size * 3;
    if (13 + gct_bytes > n) {
      return _err_gif(_at("gif: truncated global color table at offset ", 13));
    }
    pos = 13 + gct_bytes;
  }
  var g = Gif{
    version: version;
    width: width;
    height: height;
    packed: packed;
    has_gct: has_gct;
    color_resolution: color_resolution;
    sort_flag: sort_flag;
    gct_size: gct_size;
    bg_index: bg_index;
    aspect: aspect;
    gct_bytes: Vec[UInt8].new();
    frame_left: Vec[Int].new();
    frame_top: Vec[Int].new();
    frame_width: Vec[Int].new();
    frame_height: Vec[Int].new();
    frame_interlace: Vec[Int].new();
    frame_has_lct: Vec[Int].new();
    frame_lct_size: Vec[Int].new();
    frame_lct_off: Vec[Int].new();
    frame_lct_len: Vec[Int].new();
    frame_lzw_min: Vec[Int].new();
    frame_lzw_min_off: Vec[Int].new();
    frame_data_off: Vec[Int].new();
    frame_data_len: Vec[Int].new();
    frame_block_end: Vec[Int].new();
    frame_pay_off: Vec[Int].new();
    frame_delay: Vec[Int].new();
    frame_disposal: Vec[Int].new();
    frame_user_input: Vec[Int].new();
    frame_transparent: Vec[Int].new();
    frame_trans_index: Vec[Int].new();
    frame_from_gce: Vec[Int].new();
    payload: Vec[UInt8].new();
    lct_bytes: Vec[UInt8].new();
    ext_kind: Vec[Int].new();
    ext_offset: Vec[Int].new();
    ext_hdr_off: Vec[Int].new();
    ext_hdr_len: Vec[Int].new();
    ext_data_off: Vec[Int].new();
    ext_data_len: Vec[Int].new();
    ext_bytes: Vec[UInt8].new();
  };
  if (has_gct == 1) {
    _copy(&mut g.gct_bytes, data, 13, gct_size * 3);
  }
  var st = _State{
    pos: pos;
    pend_delay: 0;
    pend_disposal: 0;
    pend_user: 0;
    pend_trans: 0;
    pend_trans_index: 0;
    pend_from_gce: 0;
  };
  let scan = _scan_stream(&mut g, &mut st, data, n);
  if (scan.len() > 0) {
    return _err_gif(scan);
  }
  return _ok_gif(g);
}

// ---------------------------------------------------------------------------
//  Canvas accessors
// ---------------------------------------------------------------------------

/// Version code: GIF_VERSION_87A (87) or GIF_VERSION_89A (89).
/// Complexity: O(1).
pub fn gif_version(g: &Gif) -> Int {
  return g.version;
}

/// Logical screen width in pixels (0..65535, not range-checked).
/// Complexity: O(1).
pub fn gif_width(g: &Gif) -> Int {
  return g.width;
}

/// Logical screen height in pixels (0..65535, not range-checked).
/// Complexity: O(1).
pub fn gif_height(g: &Gif) -> Int {
  return g.height;
}

/// True when the logical screen descriptor flags a global color table.
/// Complexity: O(1).
pub fn gif_has_gct(g: &Gif) -> Bool {
  return g.has_gct == 1;
}

/// Global color table entry count (2..256), or 0 when absent.
/// Complexity: O(1).
pub fn gif_gct_size(g: &Gif) -> Int {
  return g.gct_size;
}

/// Color resolution field from the packed screen byte (0..7).
/// Complexity: O(1).
pub fn gif_color_resolution(g: &Gif) -> Int {
  return g.color_resolution;
}

/// Sort flag from the packed screen byte (0 or 1).
/// Complexity: O(1).
pub fn gif_sort_flag(g: &Gif) -> Int {
  return g.sort_flag;
}

/// Background color index byte.
/// Complexity: O(1).
pub fn gif_bg_index(g: &Gif) -> Int {
  return g.bg_index;
}

/// Pixel aspect ratio byte (0 = unspecified, otherwise (n + 15) / 64).
/// Complexity: O(1).
pub fn gif_aspect(g: &Gif) -> Int {
  return g.aspect;
}

/// Number of image descriptors in the file (0 for a trailer-only stream).
/// Complexity: O(1).
pub fn gif_frame_count(g: &Gif) -> Int {
  return g.frame_left.len();
}

/// Number of extension records in file order (graphic control, comment,
/// plain text and application extensions all count).
/// Complexity: O(1).
pub fn gif_extension_count(g: &Gif) -> Int {
  return g.ext_kind.len();
}

/// True when the file holds more than one image descriptor.
/// Complexity: O(1).
pub fn gif_is_animated(g: &Gif) -> Bool {
  return g.frame_left.len() > 1;
}

// ---------------------------------------------------------------------------
//  Color table accessors
// ---------------------------------------------------------------------------

/// Global color table entry `i` as a packed 0xRRGGBB value, or -1 when
/// `i` is outside 0..gct_size.
/// Complexity: O(1).
pub fn gif_global_color(g: &Gif, i: Int) -> Int {
  if (i < 0 || i >= g.gct_size) { return -1; }
  let off = i * 3;
  let r = (g.gct_bytes[off] as Int) & 0xFF;
  let gg = (g.gct_bytes[off + 1] as Int) & 0xFF;
  let b = (g.gct_bytes[off + 2] as Int) & 0xFF;
  return r * 65536 + gg * 256 + b;
}

/// Local color table entry `ci` of frame `i` as a packed 0xRRGGBB value, or
/// -1 when the frame or entry index is out of range (including frames
/// without a local table).
/// Complexity: O(1).
pub fn gif_local_color(g: &Gif, i: Int, ci: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let size: Int = g.frame_lct_size[i];
  if (ci < 0 || ci >= size) { return -1; }
  let off: Int = g.frame_lct_off[i] + ci * 3;
  let r = (g.lct_bytes[off] as Int) & 0xFF;
  let gg = (g.lct_bytes[off + 1] as Int) & 0xFF;
  let b = (g.lct_bytes[off + 2] as Int) & 0xFF;
  return r * 65536 + gg * 256 + b;
}

/// Local color table entry count of frame `i` (2..256), 0 when the frame has
/// no local table, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_local_color_count(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let size: Int = g.frame_lct_size[i];
  return size;
}

// ---------------------------------------------------------------------------
//  Frame accessors
// ---------------------------------------------------------------------------

/// Decoded frame `i`: geometry, interlace/local-table flags, LZW code size
/// and source offsets, and the graphic-control metadata that applied to it.
/// Err("gif: frame index out of range") when `i` is negative or beyond
/// gif_frame_count(g) - 1.
/// Complexity: O(1).
pub fn gif_frame(g: &Gif, i: Int) -> Result[GifFrame, Str] {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) {
    return _err_frame("gif: frame index out of range");
  }
  let left: Int = g.frame_left[i];
  let top: Int = g.frame_top[i];
  let width: Int = g.frame_width[i];
  let height: Int = g.frame_height[i];
  let interlace: Int = g.frame_interlace[i];
  let has_lct: Int = g.frame_has_lct[i];
  let lct_size: Int = g.frame_lct_size[i];
  let lzw_min: Int = g.frame_lzw_min[i];
  let lzw_min_off: Int = g.frame_lzw_min_off[i];
  let data_off: Int = g.frame_data_off[i];
  let data_len: Int = g.frame_data_len[i];
  let block_end: Int = g.frame_block_end[i];
  let delay: Int = g.frame_delay[i];
  let disposal: Int = g.frame_disposal[i];
  let user: Int = g.frame_user_input[i];
  let trans: Int = g.frame_transparent[i];
  let trans_index: Int = g.frame_trans_index[i];
  let from_gce: Int = g.frame_from_gce[i];
  let f = GifFrame{
    index: i;
    left: left;
    top: top;
    width: width;
    height: height;
    interlace: interlace;
    has_lct: has_lct;
    lct_size: lct_size;
    lzw_min: lzw_min;
    lzw_min_offset: lzw_min_off;
    data_offset: data_off;
    data_bytes: data_len;
    block_end: block_end;
    delay: delay;
    disposal: disposal;
    user_input: user;
    transparent: trans;
    trans_index: trans_index;
    from_gce: from_gce;
  };
  return _ok_frame(f);
}

/// Frame left position, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_left(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_left[i];
  return v;
}

/// Frame top position, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_top(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_top[i];
  return v;
}

/// Frame width, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_width(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_width[i];
  return v;
}

/// Frame height, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_height(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_height[i];
  return v;
}

/// Graphic-control delay of frame `i` in hundredths of a second, or -1 when
/// `i` is out of range. Frames without a graphic control extension report 0.
/// Complexity: O(1).
pub fn gif_frame_delay(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_delay[i];
  return v;
}

/// Graphic-control disposal method of frame `i` (0..7), or -1 when `i` is
/// out of range. Frames without a graphic control extension report 0.
/// Complexity: O(1).
pub fn gif_frame_disposal(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_disposal[i];
  return v;
}

/// Transparency flag of frame `i` (0 or 1), or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_transparent(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_transparent[i];
  return v;
}

/// Transparent color index of frame `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_trans_index(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_trans_index[i];
  return v;
}

/// LZW minimum code size of frame `i` (2..8), or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_lzw_min(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_lzw_min[i];
  return v;
}

/// Absolute byte offset of frame `i`'s LZW minimum code size byte, or -1
/// when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_lzw_offset(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_lzw_min_off[i];
  return v;
}

/// Number of raw payload bytes (sub-block framing dropped) of frame `i`, or
/// -1 when `i` is out of range.
/// Complexity: O(1).
pub fn gif_frame_lzw_size(g: &Gif, i: Int) -> Int {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) { return -1; }
  let v: Int = g.frame_data_len[i];
  return v;
}

/// Copy the opaque LZW payload of frame `i`: the concatenation of its
/// sub-block bytes with all length bytes and the terminator dropped. The
/// bytes are never decoded. Err("gif: frame index out of range") when `i`
/// is out of range.
/// Complexity: O(payload bytes).
pub fn gif_lzw_data(g: &Gif, i: Int) -> Result[Vec[UInt8], Str] {
  let count = g.frame_left.len();
  if (i < 0 || i >= count) {
    return _err_bytes("gif: frame index out of range");
  }
  let off: Int = g.frame_pay_off[i];
  let len: Int = g.frame_data_len[i];
  let out = Vec[UInt8].new();
  var k = 0;
  while (k < len) {
    let b: UInt8 = g.payload[off + k];
    out.push(b);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// ---------------------------------------------------------------------------
//  Extension accessors
// ---------------------------------------------------------------------------

/// Decoded extension `i` (kind, introducer offset and the ext_bytes ranges of
/// its fixed header and data). Err("gif: extension index out of range") when
/// `i` is negative or beyond gif_extension_count(g) - 1.
/// Complexity: O(1).
pub fn gif_extension(g: &Gif, i: Int) -> Result[GifExtension, Str] {
  let count = g.ext_kind.len();
  if (i < 0 || i >= count) {
    return _err_ext("gif: extension index out of range");
  }
  let kind: Int = g.ext_kind[i];
  let off: Int = g.ext_offset[i];
  let hdr_off: Int = g.ext_hdr_off[i];
  let hdr_len: Int = g.ext_hdr_len[i];
  let data_off: Int = g.ext_data_off[i];
  let data_len: Int = g.ext_data_len[i];
  let e = GifExtension{
    index: i;
    kind: kind;
    offset: off;
    hdr_offset: hdr_off;
    hdr_size: hdr_len;
    data_offset: data_off;
    data_size: data_len;
  };
  return _ok_ext(e);
}

/// Fixed-header byte `k` of extension `i` (GCE: 4 bytes, plain text: 12,
/// application: 11, comment: none), or -1 when the extension or `k` is out
/// of range.
/// Complexity: O(1).
pub fn gif_extension_header_byte(g: &Gif, i: Int, k: Int) -> Int {
  let count = g.ext_kind.len();
  if (i < 0 || i >= count) { return -1; }
  let off: Int = g.ext_hdr_off[i];
  let len: Int = g.ext_hdr_len[i];
  if (k < 0 || k >= len) { return -1; }
  return (g.ext_bytes[off + k] as Int) & 0xFF;
}

/// Data byte `k` of extension `i` (the concatenated sub-block payload), or
/// -1 when the extension or `k` is out of range.
/// Complexity: O(1).
pub fn gif_extension_data_byte(g: &Gif, i: Int, k: Int) -> Int {
  let count = g.ext_kind.len();
  if (i < 0 || i >= count) { return -1; }
  let off: Int = g.ext_data_off[i];
  let len: Int = g.ext_data_len[i];
  if (k < 0 || k >= len) { return -1; }
  return (g.ext_bytes[off + k] as Int) & 0xFF;
}

/// Copy the concatenated sub-block data of extension `i` (comment text,
/// plain text bytes, application data; empty for graphic control). The fixed
/// header is not included; use gif_extension_header_byte for it.
/// Err("gif: extension index out of range") when `i` is out of range.
/// Complexity: O(data bytes).
pub fn gif_extension_data_copy(g: &Gif, i: Int) -> Result[Vec[UInt8], Str] {
  let count = g.ext_kind.len();
  if (i < 0 || i >= count) {
    return _err_bytes("gif: extension index out of range");
  }
  let off: Int = g.ext_data_off[i];
  let len: Int = g.ext_data_len[i];
  let out = Vec[UInt8].new();
  var k = 0;
  while (k < len) {
    let b: UInt8 = g.ext_bytes[off + k];
    out.push(b);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// True when extension i carries the NETSCAPE2.0 application identifier
// (78 69 84 83 67 65 80 69 50 46 48).
fn _is_netscape(g: &Gif, i: Int) -> Bool {
  if (gif_extension_header_byte(g, i, 0) != 78) { return false; }
  if (gif_extension_header_byte(g, i, 1) != 69) { return false; }
  if (gif_extension_header_byte(g, i, 2) != 84) { return false; }
  if (gif_extension_header_byte(g, i, 3) != 83) { return false; }
  if (gif_extension_header_byte(g, i, 4) != 67) { return false; }
  if (gif_extension_header_byte(g, i, 5) != 65) { return false; }
  if (gif_extension_header_byte(g, i, 6) != 80) { return false; }
  if (gif_extension_header_byte(g, i, 7) != 69) { return false; }
  if (gif_extension_header_byte(g, i, 8) != 50) { return false; }
  if (gif_extension_header_byte(g, i, 9) != 46) { return false; }
  if (gif_extension_header_byte(g, i, 10) != 48) { return false; }
  return true;
}

// True when extension i carries the ANIMEXTS1.0 application identifier
// (65 78 73 77 69 88 84 83 49 46 48).
fn _is_animexts(g: &Gif, i: Int) -> Bool {
  if (gif_extension_header_byte(g, i, 0) != 65) { return false; }
  if (gif_extension_header_byte(g, i, 1) != 78) { return false; }
  if (gif_extension_header_byte(g, i, 2) != 73) { return false; }
  if (gif_extension_header_byte(g, i, 3) != 77) { return false; }
  if (gif_extension_header_byte(g, i, 4) != 69) { return false; }
  if (gif_extension_header_byte(g, i, 5) != 88) { return false; }
  if (gif_extension_header_byte(g, i, 6) != 84) { return false; }
  if (gif_extension_header_byte(g, i, 7) != 83) { return false; }
  if (gif_extension_header_byte(g, i, 8) != 49) { return false; }
  if (gif_extension_header_byte(g, i, 9) != 46) { return false; }
  if (gif_extension_header_byte(g, i, 10) != 48) { return false; }
  return true;
}

/// Loop count from a NETSCAPE2.0 or ANIMEXTS1.0 application extension `i`,
/// or -1 when the extension is not such a loop extension or its data is not
/// exactly the 3 bytes `01 <count LE16>`. A returned 0 means "loop forever";
/// the value is reported verbatim.
/// Complexity: O(1).
pub fn gif_application_loop_count(g: &Gif, i: Int) -> Int {
  let count = g.ext_kind.len();
  if (i < 0 || i >= count) { return -1; }
  let kind: Int = g.ext_kind[i];
  if (kind != 3) { return -1; }
  if (!_is_netscape(g, i) && !_is_animexts(g, i)) { return -1; }
  let len: Int = g.ext_data_len[i];
  if (len != 3) { return -1; }
  let first = gif_extension_data_byte(g, i, 0);
  if (first != 1) { return -1; }
  let lo = gif_extension_data_byte(g, i, 1);
  let hi = gif_extension_data_byte(g, i, 2);
  if (lo < 0 || hi < 0) { return -1; }
  return lo + hi * 256;
}
