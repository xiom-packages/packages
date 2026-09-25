// XIOM -- xiom.dtb: flattened device tree (DTB) parsing, validation and canonical emission
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI) codec for Flattened Device Tree blobs as defined by
// the Devicetree Specification: a 40-byte big-endian header (magic
// 0xd00dfeed, totalsize, off_dt_struct, off_dt_strings, off_mem_rsvmap,
// version, last_comp_version, boot_cpuid_phys, size_dt_strings,
// size_dt_struct), a memory reservation block of big-endian u64 pairs
// terminated by 0/0, a structure block token stream (FDT_BEGIN_NODE with a
// NUL-terminated name padded to 4 bytes, FDT_END_NODE, FDT_PROP with a u32
// length, a u32 name offset and 4-byte-padded value bytes, FDT_NOP, and the
// final FDT_END) and a NUL-terminated property-name strings block.
//
// dtb_parse validates the whole blob and returns a flat Dtb store built
// from parallel vectors: node name spans, depths and parent indices, plus
// property owner/name-offset/value-span entries pointing into the source
// buffer. dtb_emit walks that store and writes the canonical version-17
// blob. Version 17 is the documented target; version 16 is accepted on
// input (the size_dt_struct header field predates v17, so for v16 the
// structure-block size is derived as off_dt_strings - off_dt_struct).
//
// Documented non-goals: no phandle resolution, no overlays, no /chosen
// semantics, no DTS text parsing.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing struct payloads such as Result[Dtb, Str] directly in
//     other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(b as Int) & 0xFF`, and all big-endian extraction/packing is
//     arithmetic (modulo/division), which is exact for negative
//     two's-complement values, so a u64 field with bit 63 set round-trips
//     as the same signed Int bit pattern.
//   * Str values that come out of a Vec are never compared with `==` and
//     never measured with str_len (BUG 17): property names, node names and
//     path components are compared byte by byte.
//   * every Vec[Int] element read is bound to a typed local.
//   * every push on one parallel vector is mirrored on all its siblings;
//     dtb_emit refuses trees whose parallel vectors have drifted apart
//     ("dtb: invalid tree").
//   * names are materialized with xiom.string.builder.sb_to_str, never over
//     a byte range that can contain 0x00 (the builder's length contract
//     aborts on NUL), so _materialize stops at a NUL byte.

module xiom.dtb

use xiom.string;
use xiom.string.builder;

/// FDT structure token: begin a node.
pub const DTB_TOKEN_BEGIN_NODE: Int = 1;
/// FDT structure token: end a node.
pub const DTB_TOKEN_END_NODE: Int = 2;
/// FDT structure token: one property (u32 value length, u32 name offset,
/// value bytes padded to 4).
pub const DTB_TOKEN_PROP: Int = 3;
/// FDT structure token: no-op; the parser skips it and the emitter drops it.
pub const DTB_TOKEN_NOP: Int = 4;
/// FDT structure token: end of the structure block.
pub const DTB_TOKEN_END: Int = 9;
/// DTB header magic (0xd00dfeed as an unsigned 32-bit value).
pub const DTB_MAGIC: Int = 3490578157;

/// Flat DTB store. Nodes and properties are held in parallel vectors (no
/// Vec[StructType]), each in document order:
///   * nodes: `node_name_off`/`node_name_len` locate the NUL-free name
///     bytes inside the source buffer, `node_depth` is 0 for the root and
///     `node_parent` is the parent node index (-1 for the root);
///   * properties: `prop_node` is the owning node index, `prop_name_off`
///     is the strings-block-relative offset of the NUL-terminated name,
///     and `prop_value_off`/`prop_value_len` are the absolute span of the
///     value bytes inside the source buffer;
///   * memory reservations: `rsv_address`/`rsv_size` hold the u64 pair
///     values (without the terminating 0/0 pair) as Int bit patterns.
/// The header fields are copied verbatim from the parsed blob. Fields are
/// implementation details; callers must go through the free functions
/// below.
pub type Dtb = {
  totalsize: Int;
  version: Int;
  last_comp_version: Int;
  boot_cpuid_phys: Int;
  off_dt_struct: Int;
  size_dt_struct: Int;
  off_dt_strings: Int;
  size_dt_strings: Int;
  off_mem_rsvmap: Int;
  rsv_address: Vec[Int];
  rsv_size: Vec[Int];
  node_name_off: Vec[Int];
  node_name_len: Vec[Int];
  node_depth: Vec[Int];
  node_parent: Vec[Int];
  prop_node: Vec[Int];
  prop_name_off: Vec[Int];
  prop_value_off: Vec[Int];
  prop_value_len: Vec[Int];
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Dtb, Str].
fn _ok_dtb(v: Dtb) -> Result[Dtb, Str] {
  return Ok(v);
}

// Err(m) for Result[Dtb, Str].
fn _err_dtb(m: Str) -> Result[Dtb, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte).
// Arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3, and this form is exact for negative two's-complement values.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Unsigned big-endian Int of the `size` bytes at `pos` (1..8 bytes; 8-byte
// values above 2^63-1 wrap to the same two's-complement bit pattern). The
// caller guarantees pos + size <= data.len().
fn _read_be(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < size {
    let b: UInt8 = data[pos + i];
    v = v * 256 + ((b as Int) & 0xFF);
    i = i + 1;
  }
  return v;
}

// Length of the NUL-free run starting at `from` and bounded by `limit` and
// the buffer end. The parser has already proven a NUL exists.
fn _nul_len(data: &Vec[UInt8], from: Int, limit: Int) -> Int {
  var i = 0;
  while from + i < limit && from + i < data.len() {
    let b: UInt8 = data[from + i];
    if ((b as Int) & 0xFF) == 0 {
      return i;
    }
    i = i + 1;
  }
  return i;
}

// Copy data[off, off + len) into a fresh Str, stopping at the first 0x00
// byte (sb_to_str aborts on NUL; parsed names never contain one).
fn _materialize(data: &Vec[UInt8], off: Int, len: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < len && !done {
    var b: UInt8 = 0 as UInt8;
    let at = off + i;
    if at >= 0 && at < data.len() {
      b = data[at];
    }
    if ((b as Int) & 0xFF) == 0 {
      done = true;
    } else {
      sb.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Store construction
// --------------------------------------------------

// An empty Dtb store (zero counts, no root).
fn _dtb_new() -> Dtb {
  return Dtb{
    totalsize: 0;
    version: 0;
    last_comp_version: 0;
    boot_cpuid_phys: 0;
    off_dt_struct: 0;
    size_dt_struct: 0;
    off_dt_strings: 0;
    size_dt_strings: 0;
    off_mem_rsvmap: 0;
    rsv_address: Vec[Int].new();
    rsv_size: Vec[Int].new();
    node_name_off: Vec[Int].new();
    node_name_len: Vec[Int].new();
    node_depth: Vec[Int].new();
    node_parent: Vec[Int].new();
    prop_node: Vec[Int].new();
    prop_name_off: Vec[Int].new();
    prop_value_off: Vec[Int].new();
    prop_value_len: Vec[Int].new();
  };
}

// Append one node and return its index. Every parallel node vector receives
// exactly one push here.
fn _add_node(d: &mut Dtb, name_off: Int, name_len: Int, depth: Int, parent: Int) -> Int {
  let idx = d.node_name_off.len();
  d.node_name_off.push(name_off);
  d.node_name_len.push(name_len);
  d.node_depth.push(depth);
  d.node_parent.push(parent);
  return idx;
}

// Append one property. Every parallel property vector receives exactly one
// push here.
fn _add_prop(d: &mut Dtb, node: Int, name_off: Int, value_off: Int, value_len: Int) {
  d.prop_node.push(node);
  d.prop_name_off.push(name_off);
  d.prop_value_off.push(value_off);
  d.prop_value_len.push(value_len);
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse and fully validate a Flattened Device Tree blob.
///
/// On success the returned Dtb stores offsets into `data` (node names,
/// property values) plus strings-block-relative property name offsets; the
/// source buffer must stay alive for the accessors and dtb_emit. Validation
/// covers the magic, totalsize, version (16 or 17), last_comp_version,
/// every block offset/size against the buffer, the 0/0-terminated memory
/// reservation block, token nesting balance, NUL-terminated node names,
/// property name offsets inside the strings block and NUL-terminated
/// property names. Padding bytes are not inspected (any value is
/// tolerated; the emitter always writes zeros) and bytes after FDT_END or
/// after `totalsize` are ignored.
///
/// Errors (all `"dtb: ..."`): `header truncated`, `bad magic`,
/// `totalsize out of range`, `unsupported version`, `bad last_comp_version`,
/// `struct block out of range`, `strings block out of range`,
/// `memory reservation block out of range`,
/// `unterminated memory reservation block`, `unterminated node name`,
/// `multiple root nodes`, `missing root node`, `unbalanced end node`,
/// `unbalanced node nesting`, `property outside node`,
/// `property value out of range`, `property name offset out of range`,
/// `unterminated property name`, `unknown token`,
/// `truncated structure block`.
/// Complexity: O(data.len()).
pub fn dtb_parse(data: &Vec[UInt8]) -> Result[Dtb, Str] {
  if data.len() < 40 {
    return _err_dtb("dtb: header truncated");
  }
  let magic: Int = _read_be(data, 0, 4);
  if magic != DTB_MAGIC {
    return _err_dtb("dtb: bad magic");
  }
  let totalsize: Int = _read_be(data, 4, 4);
  if totalsize < 40 || totalsize > data.len() {
    return _err_dtb("dtb: totalsize out of range");
  }
  let off_struct: Int = _read_be(data, 8, 4);
  let off_strings: Int = _read_be(data, 12, 4);
  let off_rsv: Int = _read_be(data, 16, 4);
  let version: Int = _read_be(data, 20, 4);
  let last_comp: Int = _read_be(data, 24, 4);
  let boot_cpuid: Int = _read_be(data, 28, 4);
  let size_strings: Int = _read_be(data, 32, 4);
  let size_struct_field: Int = _read_be(data, 36, 4);
  if version != 16 && version != 17 {
    return _err_dtb("dtb: unsupported version");
  }
  if last_comp > version {
    return _err_dtb("dtb: bad last_comp_version");
  }
  // v16 predates size_dt_struct: the structure block runs up to the
  // strings block. v17 uses the header field.
  var struct_size: Int = size_struct_field;
  if version < 17 {
    if off_strings < off_struct {
      return _err_dtb("dtb: struct block out of range");
    }
    struct_size = off_strings - off_struct;
  }
  if off_struct < 40 || struct_size < 4 || off_struct + struct_size > totalsize {
    return _err_dtb("dtb: struct block out of range");
  }
  if off_strings < 40 || off_strings + size_strings > totalsize {
    return _err_dtb("dtb: strings block out of range");
  }
  if off_rsv < 40 || off_rsv + 16 > totalsize {
    return _err_dtb("dtb: memory reservation block out of range");
  }
  var d = _dtb_new();
  d.totalsize = totalsize;
  d.version = version;
  d.last_comp_version = last_comp;
  d.boot_cpuid_phys = boot_cpuid;
  d.off_dt_struct = off_struct;
  d.size_dt_struct = struct_size;
  d.off_dt_strings = off_strings;
  d.size_dt_strings = size_strings;
  d.off_mem_rsvmap = off_rsv;
  // Memory reservation block: u64 address/size pairs until 0/0.
  var rpos = off_rsv;
  var rdone = false;
  while !rdone {
    if rpos + 16 > totalsize {
      return _err_dtb("dtb: unterminated memory reservation block");
    }
    let ra: Int = _read_be(data, rpos, 8);
    let rs: Int = _read_be(data, rpos + 8, 8);
    if ra == 0 && rs == 0 {
      rdone = true;
    } else {
      d.rsv_address.push(ra);
      d.rsv_size.push(rs);
      rpos = rpos + 16;
    }
  }
  // Structure block: flat token stream with an explicit open-node stack.
  let send = off_struct + struct_size;
  var pos = off_struct;
  var depth = -1;
  var root_seen = false;
  var ended = false;
  var stack = Vec[Int].new();
  while !ended {
    if pos + 4 > send {
      return _err_dtb("dtb: truncated structure block");
    }
    let tok: Int = _read_be(data, pos, 4);
    pos = pos + 4;
    if tok == DTB_TOKEN_BEGIN_NODE {
      if depth < 0 && root_seen {
        return _err_dtb("dtb: multiple root nodes");
      }
      var k = 0;
      var nul_found = false;
      while pos + k < send && !nul_found {
        let b: UInt8 = data[pos + k];
        if ((b as Int) & 0xFF) == 0 {
          nul_found = true;
        } else {
          k = k + 1;
        }
      }
      if !nul_found {
        return _err_dtb("dtb: unterminated node name");
      }
      let name_off = pos;
      let name_len = k;
      var used = (pos + k + 1) - off_struct;
      while used % 4 != 0 {
        used = used + 1;
      }
      pos = off_struct + used;
      if pos > send {
        return _err_dtb("dtb: truncated structure block");
      }
      var parent = -1;
      if depth >= 0 {
        let pnode: Int = stack[depth];
        parent = pnode;
      }
      let idx = _add_node(&mut d, name_off, name_len, depth + 1, parent);
      stack.push(idx);
      depth = depth + 1;
      if parent < 0 {
        root_seen = true;
      }
    } elif tok == DTB_TOKEN_END_NODE {
      if depth < 0 {
        return _err_dtb("dtb: unbalanced end node");
      }
      depth = depth - 1;
      stack.pop();
    } elif tok == DTB_TOKEN_PROP {
      if depth < 0 {
        return _err_dtb("dtb: property outside node");
      }
      if pos + 8 > send {
        return _err_dtb("dtb: truncated structure block");
      }
      let plen: Int = _read_be(data, pos, 4);
      let nameoff: Int = _read_be(data, pos + 4, 4);
      pos = pos + 8;
      if pos + plen > send {
        return _err_dtb("dtb: property value out of range");
      }
      if nameoff >= size_strings {
        return _err_dtb("dtb: property name offset out of range");
      }
      let pbase = off_strings + nameoff;
      let plimit = off_strings + size_strings;
      var m = pbase;
      var pnul = false;
      while m < plimit && m < data.len() && !pnul {
        let pb: UInt8 = data[m];
        if ((pb as Int) & 0xFF) == 0 {
          pnul = true;
        } else {
          m = m + 1;
        }
      }
      if !pnul {
        return _err_dtb("dtb: unterminated property name");
      }
      let owner: Int = stack[depth];
      _add_prop(&mut d, owner, nameoff, pos, plen);
      pos = pos + plen;
      var pused = pos - off_struct;
      while pused % 4 != 0 {
        pused = pused + 1;
      }
      pos = off_struct + pused;
      if pos > send {
        return _err_dtb("dtb: truncated structure block");
      }
    } elif tok == DTB_TOKEN_NOP {
      // No-op token: skipped, never recorded.
    } elif tok == DTB_TOKEN_END {
      if depth != -1 {
        return _err_dtb("dtb: unbalanced node nesting");
      }
      ended = true;
    } else {
      return _err_dtb("dtb: unknown token");
    }
  }
  if !root_seen {
    return _err_dtb("dtb: missing root node");
  }
  return _ok_dtb(d);
}

// --------------------------------------------------
//  Header and reservation accessors
// --------------------------------------------------

/// Total blob size stored in the header (`totalsize`).
pub fn dtb_total_size(d: &Dtb) -> Int {
  return d.totalsize;
}

/// Blob format version stored in the header (16 or 17 after a parse).
pub fn dtb_version(d: &Dtb) -> Int {
  return d.version;
}

/// Oldest compatible version stored in the header.
pub fn dtb_last_comp_version(d: &Dtb) -> Int {
  return d.last_comp_version;
}

/// Boot CPU physical id stored in the header.
pub fn dtb_boot_cpuid_phys(d: &Dtb) -> Int {
  return d.boot_cpuid_phys;
}

/// Size of the strings block (`size_dt_strings`) in bytes.
pub fn dtb_strings_size(d: &Dtb) -> Int {
  return d.size_dt_strings;
}

/// Number of memory reservation entries (the 0/0 terminator is not one).
pub fn dtb_mem_rsv_count(d: &Dtb) -> Int {
  return d.rsv_address.len();
}

/// Address of reservation entry `i` as a 64-bit Int bit pattern, or -1 for
/// an out-of-range index.
pub fn dtb_mem_rsv_address(d: &Dtb, i: Int) -> Int {
  if i < 0 || i >= d.rsv_address.len() {
    return -1;
  }
  let v: Int = d.rsv_address[i];
  return v;
}

/// Size of reservation entry `i` as a 64-bit Int bit pattern, or -1 for an
/// out-of-range index.
pub fn dtb_mem_rsv_size(d: &Dtb, i: Int) -> Int {
  if i < 0 || i >= d.rsv_size.len() {
    return -1;
  }
  let v: Int = d.rsv_size[i];
  return v;
}

// --------------------------------------------------
//  Node and property accessors
// --------------------------------------------------

/// Number of nodes in the store (1 for any valid blob: the root).
pub fn dtb_node_count(d: &Dtb) -> Int {
  return d.node_name_off.len();
}

/// Depth of node `i` (the root is 0), or -1 for an out-of-range index.
pub fn dtb_node_depth(d: &Dtb, i: Int) -> Int {
  if i < 0 || i >= d.node_depth.len() {
    return -1;
  }
  let v: Int = d.node_depth[i];
  return v;
}

/// Parent index of node `i` (-1 for the root), or -1 for an out-of-range
/// index.
pub fn dtb_node_parent(d: &Dtb, i: Int) -> Int {
  if i < 0 || i >= d.node_parent.len() {
    return -1;
  }
  let v: Int = d.node_parent[i];
  return v;
}

/// Name of the root node; "" when the store has no nodes. `data` must be
/// the buffer the store was parsed from.
pub fn dtb_root_name(data: &Vec[UInt8], d: &Dtb) -> Str {
  if d.node_name_off.len() == 0 {
    return "";
  }
  let off: Int = d.node_name_off[0];
  let len: Int = d.node_name_len[0];
  return _materialize(data, off, len);
}

/// Name of node `i`. Err("dtb: node index out of range") for a bad index.
pub fn dtb_node_name(data: &Vec[UInt8], d: &Dtb, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= d.node_name_off.len() {
    return _err_str("dtb: node index out of range");
  }
  let off: Int = d.node_name_off[i];
  let len: Int = d.node_name_len[i];
  return _ok_str(_materialize(data, off, len));
}

/// Number of properties in the store.
pub fn dtb_prop_count(d: &Dtb) -> Int {
  return d.prop_node.len();
}

/// Owning node index of property `i`, or -1 for an out-of-range index.
pub fn dtb_prop_node(d: &Dtb, i: Int) -> Int {
  if i < 0 || i >= d.prop_node.len() {
    return -1;
  }
  let v: Int = d.prop_node[i];
  return v;
}

/// Value length in bytes of property `i`, or -1 for a bad index.
pub fn dtb_prop_value_len(d: &Dtb, i: Int) -> Int {
  if i < 0 || i >= d.prop_value_len.len() {
    return -1;
  }
  let v: Int = d.prop_value_len[i];
  return v;
}

/// Name of property `i` (resolved through the strings block).
/// Err("dtb: property index out of range") for a bad index.
pub fn dtb_prop_name(data: &Vec[UInt8], d: &Dtb, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= d.prop_node.len() {
    return _err_str("dtb: property index out of range");
  }
  let noff: Int = d.prop_name_off[i];
  let base = d.off_dt_strings + noff;
  let limit = d.off_dt_strings + d.size_dt_strings;
  let n = _nul_len(data, base, limit);
  return _ok_str(_materialize(data, base, n));
}

/// Copy the value bytes of property `i` out of `data`.
/// Err("dtb: property index out of range") for a bad index and
/// Err("dtb: property value out of bounds") when the recorded span does not
/// fit `data`.
pub fn dtb_prop_value(data: &Vec[UInt8], d: &Dtb, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= d.prop_node.len() {
    return _err_bytes("dtb: property index out of range");
  }
  let off: Int = d.prop_value_off[i];
  let len: Int = d.prop_value_len[i];
  if off < 0 || len < 0 || off + len > data.len() {
    return _err_bytes("dtb: property value out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Lookup
// --------------------------------------------------

// Path byte, or -1 out of range.
fn _pbyte(s: Str, pos: Int) -> Int {
  if pos < 0 || pos >= string.str_len(s) {
    return -1;
  }
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Does the stored name of `node` equal path[start, end) byte for byte?
fn _name_equals(data: &Vec[UInt8], d: &Dtb, node: Int, s: Str, start: Int, end: Int) -> Bool {
  let len: Int = d.node_name_len[node];
  if len != end - start {
    return false;
  }
  let off: Int = d.node_name_off[node];
  var i = 0;
  while i < len {
    let at = off + i;
    var b: UInt8 = 0 as UInt8;
    if at >= 0 && at < data.len() {
      b = data[at];
    }
    let got = (b as Int) & 0xFF;
    let want = _pbyte(s, start + i);
    if got != want {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// First child of `parent` named path[start, end), or -1.
fn _find_child(data: &Vec[UInt8], d: &Dtb, parent: Int, s: Str, start: Int, end: Int) -> Int {
  let nn = d.node_name_off.len();
  var i = 0;
  while i < nn {
    let par: Int = d.node_parent[i];
    if par == parent {
      if _name_equals(data, d, i, s, start, end) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Resolve an absolute node path such as `"/soc@0/uart@1000"`.
///
/// "" and "/" select the root. Otherwise the path must start with '/';
/// components are separated by '/' and matched byte-for-byte against the
/// full node names (unit addresses included). A single trailing '/' is
/// accepted; empty components ("//") are not. No relative paths. Returns
/// the node index, or -1 when the path does not resolve.
pub fn dtb_find_node(data: &Vec[UInt8], d: &Dtb, path: Str) -> Int {
  let nn = d.node_name_off.len();
  if nn == 0 {
    return -1;
  }
  let plen = string.str_len(path);
  if plen == 0 {
    return 0;
  }
  if _pbyte(path, 0) != 47 {
    return -1;
  }
  if plen == 1 {
    return 0;
  }
  var cur = 0;
  var i = 1;
  while i < plen {
    var j = i;
    while j < plen && _pbyte(path, j) != 47 {
      j = j + 1;
    }
    if j == i {
      return -1;
    }
    cur = _find_child(data, d, cur, path, i, j);
    if cur < 0 {
      return -1;
    }
    i = j + 1;
  }
  return cur;
}

// Does the strings-block name of property `i` equal `name` byte for byte?
// The comparison follows the NUL terminator.
fn _prop_name_equals(data: &Vec[UInt8], d: &Dtb, i: Int, name: Str) -> Bool {
  let noff: Int = d.prop_name_off[i];
  let base = d.off_dt_strings + noff;
  let limit = d.off_dt_strings + d.size_dt_strings;
  let nlen = string.str_len(name);
  var k = 0;
  var done = false;
  var same = false;
  while !done {
    let at = base + k;
    if at < 0 || at >= limit || at >= data.len() {
      done = true;
    } else {
      let b: UInt8 = data[at];
      let bc = (b as Int) & 0xFF;
      if bc == 0 {
        if k == nlen {
          same = true;
        }
        done = true;
      } elif k >= nlen {
        done = true;
      } elif bc != _pbyte(name, k) {
        done = true;
      } else {
        k = k + 1;
      }
    }
  }
  return same;
}

/// Index of the first property of `node` whose name equals `name`
/// byte-for-byte, or -1 when absent (also for a bad node index).
pub fn dtb_find_property(data: &Vec[UInt8], d: &Dtb, node: Int, name: Str) -> Int {
  if node < 0 || node >= d.node_name_off.len() {
    return -1;
  }
  let pn = d.prop_node.len();
  var i = 0;
  while i < pn {
    let owner: Int = d.prop_node[i];
    if owner == node {
      if _prop_name_equals(data, d, i, name) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

// All parallel vectors share one length, the node forest is a preorder
// sequence rooted at node 0, spans fit the source buffer, every property
// name is NUL-terminated inside the strings block, property owners are
// non-decreasing and node names contain no NUL byte. A drifted store can
// otherwise cause access violations or a non-canonical blob.
fn _tree_well_formed(data: &Vec<UInt8>, d: &Dtb) -> Bool {
  let nn = d.node_name_off.len();
  if d.node_name_len.len() != nn { return false; }
  if d.node_depth.len() != nn { return false; }
  if d.node_parent.len() != nn { return false; }
  let pn = d.prop_node.len();
  if d.prop_name_off.len() != pn { return false; }
  if d.prop_value_off.len() != pn { return false; }
  if d.prop_value_len.len() != pn { return false; }
  if d.rsv_address.len() != d.rsv_size.len() { return false; }
  if nn < 1 { return false; }
  if d.off_dt_strings < 0 || d.size_dt_strings < 0 { return false; }
  if d.off_dt_strings + d.size_dt_strings > data.len() { return false; }
  let rd: Int = d.node_depth[0];
  let rp: Int = d.node_parent[0];
  if rd != 0 || rp != -1 { return false; }
  var i = 1;
  while i < nn {
    let par: Int = d.node_parent[i];
    let dep: Int = d.node_depth[i];
    if par < 0 || par >= i { return false; }
    let pdep: Int = d.node_depth[par];
    if dep != pdep + 1 { return false; }
    i = i + 1;
  }
  i = 0;
  while i < nn {
    let no: Int = d.node_name_off[i];
    let nl: Int = d.node_name_len[i];
    if no < 0 || nl < 0 || no + nl > data.len() { return false; }
    var k = 0;
    while k < nl {
      let b: UInt8 = data[no + k];
      if ((b as Int) & 0xFF) == 0 { return false; }
      k = k + 1;
    }
    i = i + 1;
  }
  var prev = -1;
  i = 0;
  while i < pn {
    let owner: Int = d.prop_node[i];
    if owner < 0 || owner >= nn { return false; }
    if owner < prev { return false; }
    prev = owner;
    let vo: Int = d.prop_value_off[i];
    let vl: Int = d.prop_value_len[i];
    if vo < 0 || vl < 0 || vo + vl > data.len() { return false; }
    let po: Int = d.prop_name_off[i];
    if po < 0 || po >= d.size_dt_strings { return false; }
    let base = d.off_dt_strings + po;
    let limit = d.off_dt_strings + d.size_dt_strings;
    if base < 0 || base >= data.len() { return false; }
    var m = base;
    var found = false;
    while m < limit && m < data.len() && !found {
      let b2: UInt8 = data[m];
      if ((b2 as Int) & 0xFF) == 0 { found = true; }
      m = m + 1;
    }
    if !found { return false; }
    i = i + 1;
  }
  return true;
}

// Index of the strings-block entry equal to data[base, base + len), or -1.
// The entry bytes are NUL-free and `base + len` is inside the buffer.
fn _sb_find(sb: &Vec[UInt8], offs: &Vec[Int], lens: &Vec[Int], data: &Vec[UInt8], base: Int, len: Int) -> Int {
  var j = 0;
  while j < offs.len() {
    let o: Int = offs[j];
    let l: Int = lens[j];
    if l == len {
      var k = 0;
      var same = true;
      while k < len && same {
        let a: UInt8 = data[base + k];
        let b: UInt8 = sb[o + k];
        if ((a as Int) & 0xFF) != ((b as Int) & 0xFF) {
          same = false;
        }
        k = k + 1;
      }
      if same {
        return j;
      }
    }
    j = j + 1;
  }
  return -1;
}

// Emit one FDT_PROP token: token, u32 value length, u32 new name offset,
// the value bytes and zero padding to 4 bytes.
fn _emit_prop(data: &Vec<UInt8>, d: &Dtb, pi: Int, new_nameoff: Int, out: &mut Vec<UInt8>) {
  let vl: Int = d.prop_value_len[pi];
  let vo: Int = d.prop_value_off[pi];
  _push_be(out, DTB_TOKEN_PROP, 4);
  _push_be(out, vl, 4);
  _push_be(out, new_nameoff, 4);
  var k = 0;
  while k < vl {
    out.push(data[vo + k]);
    k = k + 1;
  }
  var used = vl;
  while used % 4 != 0 {
    out.push(0 as UInt8);
    used = used + 1;
  }
}

// Emit the whole structure block from the preorder node forest: close open
// nodes before each BEGIN_NODE, emit each node's properties in order, then
// close the remaining nodes and write FDT_END. No FDT_NOP is ever written.
fn _emit_struct(data: &Vec[UInt8], d: &Dtb, prop_off: &Vec[Int], out: &mut Vec<UInt8>) {
  let nn = d.node_name_off.len();
  let pn = d.prop_node.len();
  var open_depth = -1;
  var pp = 0;
  var i = 0;
  while i < nn {
    let nd: Int = d.node_depth[i];
    while open_depth >= nd {
      _push_be(out, DTB_TOKEN_END_NODE, 4);
      open_depth = open_depth - 1;
    }
    _push_be(out, DTB_TOKEN_BEGIN_NODE, 4);
    let no: Int = d.node_name_off[i];
    let nl: Int = d.node_name_len[i];
    var k = 0;
    while k < nl {
      out.push(data[no + k]);
      k = k + 1;
    }
    out.push(0 as UInt8);
    var used = 4 + nl + 1;
    while used % 4 != 0 {
      out.push(0 as UInt8);
      used = used + 1;
    }
    open_depth = nd;
    var more = true;
    while pp < pn && more {
      let owner: Int = d.prop_node[pp];
      if owner == i {
        let new_off: Int = prop_off[pp];
        _emit_prop(data, d, pp, new_off, out);
        pp = pp + 1;
      } else {
        more = false;
      }
    }
    i = i + 1;
  }
  while open_depth >= 0 {
    _push_be(out, DTB_TOKEN_END_NODE, 4);
    open_depth = open_depth - 1;
  }
  _push_be(out, DTB_TOKEN_END, 4);
}

/// Emit the canonical version-17 blob for a parsed store.
///
/// Blocks are laid out in canonical order (header, memory reservation
/// block, structure block, strings block), the strings block is rebuilt by
/// first use of each property name in document order, FDT_NOPs are dropped,
/// node-name and property-value padding is zero, FDT_END closes the
/// structure block and `boot_cpuid_phys` plus the reservation entries are
/// preserved. Parsing a canonical blob and emitting it again is
/// byte-identical. `data` must be the buffer the store was parsed from.
/// Err("dtb: invalid tree") when the parallel vectors have drifted apart,
/// the node forest is not a preorder tree rooted at node 0, or a span/name
/// does not fit `data` and the strings block.
/// Complexity: O(blob size).
pub fn dtb_emit(data: &Vec[UInt8], d: &Dtb) -> Result[Vec[UInt8], Str] {
  if !_tree_well_formed(data, d) {
    return _err_bytes("dtb: invalid tree");
  }
  // Rebuild the strings block by first use; record each property's new
  // strings-block-relative name offset.
  var sb = Vec[UInt8].new();
  var sb_off = Vec[Int].new();
  var sb_len = Vec[Int].new();
  var prop_off = Vec[Int].new();
  var i = 0;
  while i < d.prop_node.len() {
    let noff: Int = d.prop_name_off[i];
    let base = d.off_dt_strings + noff;
    let limit = d.off_dt_strings + d.size_dt_strings;
    let nl = _nul_len(data, base, limit);
    let hit = _sb_find(&sb, &sb_off, &sb_len, data, base, nl);
    if hit >= 0 {
      let at: Int = sb_off[hit];
      prop_off.push(at);
    } else {
      let at = sb.len();
      var k = 0;
      while k < nl {
        sb.push(data[base + k]);
        k = k + 1;
      }
      sb.push(0 as UInt8);
      sb_off.push(at);
      sb_len.push(nl);
      prop_off.push(at);
    }
    i = i + 1;
  }
  var enc = Vec[UInt8].new();
  _emit_struct(data, d, &prop_off, &mut enc);
  // Memory reservation block: the stored pairs then the 0/0 terminator.
  var rb = Vec[UInt8].new();
  var ri = 0;
  while ri < d.rsv_address.len() {
    let ra: Int = d.rsv_address[ri];
    let rs: Int = d.rsv_size[ri];
    _push_be(&mut rb, ra, 8);
    _push_be(&mut rb, rs, 8);
    ri = ri + 1;
  }
  var zeros = 0;
  while zeros < 16 {
    rb.push(0 as UInt8);
    zeros = zeros + 1;
  }
  // Header: canonical v17 layout with the reservation block at offset 40.
  var out = Vec[UInt8].new();
  let off_struct: Int = 40 + rb.len();
  let off_strings: Int = off_struct + enc.len();
  let total: Int = off_strings + sb.len();
  let boot: Int = d.boot_cpuid_phys;
  _push_be(&mut out, DTB_MAGIC, 4);
  _push_be(&mut out, total, 4);
  _push_be(&mut out, off_struct, 4);
  _push_be(&mut out, off_strings, 4);
  _push_be(&mut out, 40, 4);
  _push_be(&mut out, 17, 4);
  _push_be(&mut out, 16, 4);
  _push_be(&mut out, boot, 4);
  _push_be(&mut out, sb.len(), 4);
  _push_be(&mut out, enc.len(), 4);
  _push_bytes(&mut out, &rb);
  _push_bytes(&mut out, &enc);
  _push_bytes(&mut out, &sb);
  return _ok_bytes(out);
}
