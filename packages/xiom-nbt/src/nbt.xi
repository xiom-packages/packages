// XIOM -- xiom.nbt: pure-XIOM Minecraft NBT (Named Binary Tag) codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A no-FFI NBT codec for tag types 1-12 (Byte, Short, Int, Long, Float,
// Double, Byte_Array, String, List, Compound, Int_Array, Long_Array),
// big-endian throughout, with a flat node store instead of a recursive
// Vec[StructType] tree: nbt_decode validates a complete document (root
// TAG_Compound, exact buffer size, bounded nesting) into an NbtTree whose
// nodes live in parallel Vecs; navigation accessors (find child by name,
// list length, typed readers) walk that store. nbt_encode writes the tree
// back byte-exactly. See SPEC.md for the byte-level format table, error
// catalog and documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Result values directly in other functions miscompiles).
//   * all big-endian byte extraction is arithmetic (modulo/division);
//     `& 0xFF` on Int operands with bit 31 set miscompiles.
//   * there is no Int <-> Float64 bitcast intrinsic (xiom.num.float is a
//     documented zero-returning stub), so TAG_Float / TAG_Double payloads
//     are exposed as their raw IEEE-754 bit patterns (Int). No Float64
//     appears in the public API; see SPEC.md.
//   * Str values read from Vec[Str] elements are never compared with `==`
//     and never measured with str_len (BUG 17): name byte lengths are kept
//     in a parallel Vec[Int] and comparisons go through str_compare.

module xiom.nbt

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

/// TAG_Byte (1): signed 8-bit integer payload.
pub const NBT_TAG_BYTE: Int = 1;
/// TAG_Short (2): signed 16-bit big-endian integer payload.
pub const NBT_TAG_SHORT: Int = 2;
/// TAG_Int (3): signed 32-bit big-endian integer payload.
pub const NBT_TAG_INT: Int = 3;
/// TAG_Long (4): signed 64-bit big-endian integer payload.
pub const NBT_TAG_LONG: Int = 4;
/// TAG_Float (5): 4-byte IEEE-754 payload, exposed as raw bits.
pub const NBT_TAG_FLOAT: Int = 5;
/// TAG_Double (6): 8-byte IEEE-754 payload, exposed as raw bits.
pub const NBT_TAG_DOUBLE: Int = 6;
/// TAG_Byte_Array (7): int32 count then count bytes.
pub const NBT_TAG_BYTE_ARRAY: Int = 7;
/// TAG_String (8): u16 byte length then UTF-8 bytes.
pub const NBT_TAG_STRING: Int = 8;
/// TAG_List (9): element type byte, int32 count, then the elements.
pub const NBT_TAG_LIST: Int = 9;
/// TAG_Compound (10): named tags then a 0x00 terminator.
pub const NBT_TAG_COMPOUND: Int = 10;
/// TAG_Int_Array (11): int32 count then count 4-byte ints.
pub const NBT_TAG_INT_ARRAY: Int = 11;
/// TAG_Long_Array (12): int32 count then count 8-byte longs.
pub const NBT_TAG_LONG_ARRAY: Int = 12;
/// TAG_End (0): compound terminator; never a standalone tag.
pub const NBT_TAG_END: Int = 0;
/// Maximum container (Compound/List) nesting accepted by decode and encode.
pub const NBT_MAX_DEPTH: Int = 64;

/// Flat NBT node store. Every node is one index into the parallel vectors:
/// `types` is the tag type (1-12), `names` the element name ("" for list
/// elements), `name_off`/`name_len` the exact UTF-8 name bytes inside
/// `data`, `parent` the owning node (-1 for the root), and
/// `child_start`/`child_count`/`order` a contiguous child range inside
/// `order`. `values` holds the scalar payload or the element count (arrays)
/// / the element type (lists); `data_off`/`data_len` locate the payload
/// bytes (strings, arrays) inside the shared `data` buffer. `root` is the
/// root node index, or -1 for an empty tree. Fields are implementation
/// details; callers must go through the free functions below.
pub type NbtTree = {
  types: Vec[Int];
  names: Vec[Str];
  name_off: Vec[Int];
  name_len: Vec[Int];
  parent: Vec[Int];
  child_start: Vec[Int];
  child_count: Vec[Int];
  order: Vec[Int];
  values: Vec[Int];
  data_off: Vec[Int];
  data_len: Vec[Int];
  data: Vec[UInt8];
  root: Int;
}

/// Internal big-endian cursor over the input buffer.
type NbtCursor = {
  data: Vec[UInt8];
  pos: Int;
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
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

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[NbtTree, Str].
fn _ok_tree(v: NbtTree) -> Result[NbtTree, Str] {
  return Ok(v);
}

// Err(m) for Result[NbtTree, Str].
fn _err_tree(m: Str) -> Result[NbtTree, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// "nbt: unknown tag type N" for a raw type byte.
fn _unknown(t: Int) -> Str {
  return "nbt: unknown tag type " + convert.int_to_string(t);
}

// "nbt: unexpected tag type N" for a typed reader on the wrong node.
fn _unexpected(t: Int) -> Str {
  return "nbt: unexpected tag type " + convert.int_to_string(t);
}

// 2^k for small k (sign extension of 1/2/4-byte payloads).
fn _pow2(k: Int) -> Int {
  var v: Int = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

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

// Raw byte at the cursor without advancing; Err when exhausted.
fn _peek_u8(rd: &mut NbtCursor) -> Result[Int, Str] {
  if rd.pos >= rd.data.len() {
    return _err_int("nbt: truncated buffer");
  }
  return _ok_int((rd.data[rd.pos] as Int) & 0xFF);
}

// Read one unsigned byte and advance.
fn _read_u8(rd: &mut NbtCursor) -> Result[Int, Str] {
  if rd.pos >= rd.data.len() {
    return _err_int("nbt: truncated buffer");
  }
  let b = (rd.data[rd.pos] as Int) & 0xFF;
  rd.pos = rd.pos + 1;
  return _ok_int(b);
}

// Read two big-endian bytes as an unsigned 16-bit Int and advance.
fn _read_u16(rd: &mut NbtCursor) -> Result[Int, Str] {
  if rd.data.len() - rd.pos < 2 {
    return _err_int("nbt: truncated buffer");
  }
  let hi = (rd.data[rd.pos] as Int) & 0xFF;
  let lo = (rd.data[rd.pos + 1] as Int) & 0xFF;
  rd.pos = rd.pos + 2;
  return _ok_int(hi * 256 + lo);
}

// Read `size` bytes at the cursor as an UNSIGNED big-endian Int and advance.
// Size-8 values above 2^63-1 wrap to the same two's-complement bit pattern
// (Int is signed 64-bit; documented in SPEC.md).
fn _read_uint(rd: &mut NbtCursor, size: Int) -> Result[Int, Str] {
  if rd.data.len() - rd.pos < size {
    return _err_int("nbt: truncated buffer");
  }
  var acc: Int = 0;
  var i = 0;
  while i < size {
    let b = (rd.data[rd.pos + i] as Int) & 0xFF;
    acc = acc * 256 + b;
    i = i + 1;
  }
  rd.pos = rd.pos + size;
  return _ok_int(acc);
}

// Read `size` bytes at the cursor as a SIGNED big-endian Int and advance.
fn _read_sint(rd: &mut NbtCursor, size: Int) -> Result[Int, Str] {
  if rd.data.len() - rd.pos < size {
    return _err_int("nbt: truncated buffer");
  }
  let first = (rd.data[rd.pos] as Int) & 0xFF;
  let negative = first >= 128;
  var acc: Int = 0;
  if negative && size == 8 {
    acc = -1;
  }
  var i = 0;
  while i < size {
    let b = (rd.data[rd.pos + i] as Int) & 0xFF;
    acc = acc * 256 + b;
    i = i + 1;
  }
  if negative && size < 8 {
    acc = acc - _pow2(size * 8);
  }
  rd.pos = rd.pos + size;
  return _ok_int(acc);
}

// Copy `n` payload bytes at the cursor into tree.data (bytes verbatim) and
// advance. The caller has already checked that `n` bytes are available.
fn _copy_bytes(rd: &mut NbtCursor, tree: &mut NbtTree, n: Int) -> Int {
  let off = tree.data.len();
  var i = 0;
  while i < n {
    tree.data.push(rd.data[rd.pos + i]);
    i = i + 1;
  }
  rd.pos = rd.pos + n;
  return off;
}

// Materialize a Str view of tree.data[off, off + len). A raw 0x00 byte in
// the payload stays in tree.data (byte-exact re-encode) but terminates the
// Str view: Str is NUL-terminated, so bytes after the first NUL cannot be
// represented (see SPEC.md). Truncating BEFORE sb_to_str keeps its
// `result.len() == sb.len()` contract intact.
fn _materialize(tree: &NbtTree, off: Int, len: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < len && !done {
    var b: UInt8 = 0 as UInt8;
    let at = off + i;
    if at >= 0 && at < tree.data.len() {
      b = tree.data[at];
    }
    if b == 0 as UInt8 {
      done = true;
    } else {
      sb.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

// Append a node to the store and return its index. `parent` < 0 marks the
// root (the first root wins); `noff`/`nlen` locate the name bytes in data.
fn _add_core(tree: &mut NbtTree, tag: Int, parent: Int, name: Str, noff: Int, nlen: Int) -> Int {
  let idx = tree.types.len();
  tree.types.push(tag);
  tree.names.push(name);
  tree.name_off.push(noff);
  tree.name_len.push(nlen);
  tree.parent.push(parent);
  tree.values.push(0);
  tree.data_off.push(0);
  tree.data_len.push(0);
  tree.child_start.push(-1);
  tree.child_count.push(0);
  if parent < 0 && tree.root < 0 {
    tree.root = idx;
  }
  return idx;
}

// Append the bytes of `name` to tree.data and return their offset.
fn _push_name(tree: &mut NbtTree, name: Str) -> Int {
  let off = tree.data.len();
  let n = string.str_len(name);
  var i = 0;
  while i < n {
    tree.data.push(string.byte_at(name, i));
    i = i + 1;
  }
  return off;
}

// Rebuild `child_start` / `child_count` / `order` from `parent`. O(nodes).
// Called by nbt_decode and by nbt_encode (which finalizes a builder tree
// before writing it); builders only maintain `parent`, so navigation
// accessors require nbt_finalize on hand-built trees.
fn _finalize(tree: &mut NbtTree) {
  let n = tree.types.len();
  var counts = Vec[Int].new();
  var i = 0;
  while i < n {
    counts.push(0);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let p: Int = tree.parent[i];
    if p >= 0 && p < n {
      let c: Int = counts[p];
      counts[p] = c + 1;
    }
    i = i + 1;
  }
  var starts = Vec[Int].new();
  var acc = 0;
  i = 0;
  while i < n {
    starts.push(acc);
    let c: Int = counts[i];
    acc = acc + c;
    i = i + 1;
  }
  var order = Vec[Int].new();
  i = 0;
  while i < n {
    order.push(-1);
    i = i + 1;
  }
  var cursors = Vec[Int].new();
  i = 0;
  while i < n {
    let s: Int = starts[i];
    cursors.push(s);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let p: Int = tree.parent[i];
    if p >= 0 && p < n {
      let cur: Int = cursors[p];
      if cur >= 0 && cur < n {
        order[cur] = i;
        cursors[p] = cur + 1;
      }
    }
    i = i + 1;
  }
  tree.child_start = starts;
  tree.child_count = counts;
  tree.order = order;
}

// --------------------------------------------------
//  Decoder
// --------------------------------------------------

// Read the u16-length-prefixed name payload at the cursor into tree.data;
// Ok = offset of the copied bytes. A declared length past the end of the
// buffer is "nbt: string length overrun".
fn _read_name_raw(rd: &mut NbtCursor, tree: &mut NbtTree) -> Result[Int, Str] {
  let lr = _read_u16(rd);
  if !lr.is_ok {
    return _err_int(lr.error);
  }
  let n = lr.value;
  if rd.data.len() - rd.pos < n {
    return _err_int("nbt: string length overrun");
  }
  return _ok_int(_copy_bytes(rd, tree, n));
}

// Read the payload of a scalar tag (1-6) at the cursor into values[idx].
// Byte/Short/Int/Long are sign-extended; Float/Double keep their raw
// IEEE-754 bits (4/8 bytes, size-8 wraps to the two's-complement pattern).
fn _decode_scalar(rd: &mut NbtCursor, tree: &mut NbtTree, idx: Int, tag: Int) -> Result[Int, Str] {
  var size = 0;
  var signed = true;
  if tag == NBT_TAG_BYTE { size = 1; }
  if tag == NBT_TAG_SHORT { size = 2; }
  if tag == NBT_TAG_INT { size = 4; }
  if tag == NBT_TAG_LONG { size = 8; }
  if tag == NBT_TAG_FLOAT { size = 4; signed = false; }
  if tag == NBT_TAG_DOUBLE { size = 8; signed = false; }
  var vr = _ok_int(0);
  if signed {
    vr = _read_sint(rd, size);
  } else {
    vr = _read_uint(rd, size);
  }
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  tree.values[idx] = vr.value;
  return _ok_int(idx);
}

// Decode the payload of the node at `idx` (its tag is already known) and
// return the node index. `depth` is the container depth of this node
// (root = 1); Compound and non-empty List nodes deeper than NBT_MAX_DEPTH
// are rejected. List elements recurse here payload-only: NBT declares the
// element tag once in the list header, so elements carry no tag byte and
// no name of their own.
fn _decode_payload(rd: &mut NbtCursor, tree: &mut NbtTree, idx: Int, tag: Int, depth: Int) -> Result[Int, Str] {
  if tag >= NBT_TAG_BYTE && tag <= NBT_TAG_DOUBLE {
    return _decode_scalar(rd, tree, idx, tag);
  }
  if tag == NBT_TAG_BYTE_ARRAY {
    let lr = _read_sint(rd, 4);
    if !lr.is_ok { return _err_int(lr.error); }
    let n = lr.value;
    if n < 0 { return _err_int("nbt: negative length"); }
    if rd.data.len() - rd.pos < n { return _err_int("nbt: truncated buffer"); }
    let off = _copy_bytes(rd, tree, n);
    tree.values[idx] = n;
    tree.data_off[idx] = off;
    tree.data_len[idx] = n;
    return _ok_int(idx);
  }
  if tag == NBT_TAG_STRING {
    let lr = _read_u16(rd);
    if !lr.is_ok { return _err_int(lr.error); }
    let n = lr.value;
    if rd.data.len() - rd.pos < n { return _err_int("nbt: string length overrun"); }
    let off = _copy_bytes(rd, tree, n);
    tree.values[idx] = n;
    tree.data_off[idx] = off;
    tree.data_len[idx] = n;
    return _ok_int(idx);
  }
  if tag == NBT_TAG_LIST {
    let er = _read_u8(rd);
    if !er.is_ok { return _err_int(er.error); }
    let elem = er.value;
    let lr = _read_sint(rd, 4);
    if !lr.is_ok { return _err_int(lr.error); }
    let count = lr.value;
    if count < 0 { return _err_int("nbt: negative length"); }
    if elem > NBT_TAG_LONG_ARRAY { return _err_int(_unknown(elem)); }
    if count > 0 && elem == NBT_TAG_END { return _err_int("nbt: list element type mismatch"); }
    if count > 0 && depth + 1 > NBT_MAX_DEPTH { return _err_int("nbt: depth exceeded"); }
    tree.values[idx] = elem;
    var k = 0;
    while k < count {
      let eidx = _add_core(tree, elem, idx, "", 0, 0);
      let cr = _decode_payload(rd, tree, eidx, elem, depth + 1);
      if !cr.is_ok { return _err_int(cr.error); }
      k = k + 1;
    }
    return _ok_int(idx);
  }
  if tag == NBT_TAG_COMPOUND {
    if depth > NBT_MAX_DEPTH { return _err_int("nbt: depth exceeded"); }
    var done = false;
    while !done {
      let pr = _peek_u8(rd);
      if !pr.is_ok { return _err_int(pr.error); }
      if pr.value == NBT_TAG_END {
        rd.pos = rd.pos + 1;
        done = true;
      } else {
        let cr = _decode_tag(rd, tree, idx, depth + 1);
        if !cr.is_ok { return _err_int(cr.error); }
      }
    }
    return _ok_int(idx);
  }
  if tag == NBT_TAG_INT_ARRAY {
    let lr = _read_sint(rd, 4);
    if !lr.is_ok { return _err_int(lr.error); }
    let n = lr.value;
    if n < 0 { return _err_int("nbt: negative length"); }
    let need = n * 4;
    if rd.data.len() - rd.pos < need { return _err_int("nbt: truncated buffer"); }
    let off = _copy_bytes(rd, tree, need);
    tree.values[idx] = n;
    tree.data_off[idx] = off;
    tree.data_len[idx] = need;
    return _ok_int(idx);
  }
  if tag == NBT_TAG_LONG_ARRAY {
    let lr = _read_sint(rd, 4);
    if !lr.is_ok { return _err_int(lr.error); }
    let n = lr.value;
    if n < 0 { return _err_int("nbt: negative length"); }
    let need = n * 8;
    if rd.data.len() - rd.pos < need { return _err_int("nbt: truncated buffer"); }
    let off = _copy_bytes(rd, tree, need);
    tree.values[idx] = n;
    tree.data_off[idx] = off;
    tree.data_len[idx] = need;
    return _ok_int(idx);
  }
  return _err_int(_unknown(tag));
}

// Decode one named tag (tag byte + name + payload) at the cursor into the
// store and return its node index. The root and every compound child go
// through here.
fn _decode_tag(rd: &mut NbtCursor, tree: &mut NbtTree, parent: Int, depth: Int) -> Result[Int, Str] {
  let tr = _read_u8(rd);
  if !tr.is_ok {
    return _err_int(tr.error);
  }
  let tag = tr.value;
  if tag < NBT_TAG_BYTE || tag > NBT_TAG_LONG_ARRAY {
    return _err_int(_unknown(tag));
  }
  let nr = _read_name_raw(rd, tree);
  if !nr.is_ok {
    return _err_int(nr.error);
  }
  let name_off = nr.value;
  let name_len = tree.data.len() - name_off;
  let name_text = _materialize(tree, name_off, name_len);
  let idx = _add_core(tree, tag, parent, name_text, name_off, name_len);
  return _decode_payload(rd, tree, idx, tag, depth);
}

/// Decode a complete NBT document into a flat node store. The buffer must
/// hold exactly one document: the root tag must be TAG_Compound, nesting is
/// capped at NBT_MAX_DEPTH container levels and trailing bytes are an error
/// ("nbt: trailing bytes"). The returned tree is finalized, so all
/// navigation accessors work immediately.
pub fn nbt_decode(data: Vec[UInt8]) -> Result[NbtTree, Str] {
  var rd = NbtCursor{ data: data; pos: 0; };
  var tree = nbt_tree_new();
  let pr = _peek_u8(&mut rd);
  if !pr.is_ok {
    return _err_tree(pr.error);
  }
  let root_tag = pr.value;
  if root_tag < NBT_TAG_BYTE || root_tag > NBT_TAG_LONG_ARRAY {
    return _err_tree(_unknown(root_tag));
  }
  if root_tag != NBT_TAG_COMPOUND {
    return _err_tree("nbt: root tag is not a compound");
  }
  let dr = _decode_tag(&mut rd, &mut tree, -1, 1);
  if !dr.is_ok {
    return _err_tree(dr.error);
  }
  if rd.pos != rd.data.len() {
    return _err_tree("nbt: trailing bytes");
  }
  _finalize(&mut tree);
  return _ok_tree(tree);
}

// --------------------------------------------------
//  Encoder
// --------------------------------------------------

// Write the u16 name prefix and the exact name bytes of `node`.
fn _encode_name(tree: &NbtTree, node: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  let nl: Int = tree.name_len[node];
  if nl > 65535 {
    return _err_int("nbt: string length overrun");
  }
  _push_be(out, nl, 2);
  let off: Int = tree.name_off[node];
  var i = 0;
  while i < nl {
    out.push(tree.data[off + i]);
    i = i + 1;
  }
  return _ok_int(0);
}

// Write the payload of `node` (no tag byte, no name). All bounds and type
// invariants of the store are validated here; `depth` mirrors _decode_payload.
fn _encode_payload(tree: &NbtTree, node: Int, out: &mut Vec[UInt8], depth: Int) -> Result[Int, Str] {
  if node < 0 || node >= tree.types.len() {
    return _err_int("nbt: node index out of range");
  }
  let t: Int = tree.types[node];
  if t < NBT_TAG_BYTE || t > NBT_TAG_LONG_ARRAY {
    return _err_int(_unknown(t));
  }
  if t >= NBT_TAG_BYTE && t <= NBT_TAG_DOUBLE {
    var size = 1;
    if t == NBT_TAG_SHORT { size = 2; }
    if t == NBT_TAG_INT { size = 4; }
    if t == NBT_TAG_LONG { size = 8; }
    if t == NBT_TAG_FLOAT { size = 4; }
    if t == NBT_TAG_DOUBLE { size = 8; }
    _push_be(out, tree.values[node], size);
    return _ok_int(0);
  }
  if t == NBT_TAG_BYTE_ARRAY {
    let count: Int = tree.values[node];
    let dlen: Int = tree.data_len[node];
    if count < 0 { return _err_int("nbt: negative length"); }
    if dlen != count { return _err_int("nbt: invalid node structure"); }
    _push_be(out, count, 4);
    let off: Int = tree.data_off[node];
    var i = 0;
    while i < count {
      out.push(tree.data[off + i]);
      i = i + 1;
    }
    return _ok_int(0);
  }
  if t == NBT_TAG_STRING {
    let len: Int = tree.values[node];
    let dlen: Int = tree.data_len[node];
    if len < 0 || len > 65535 { return _err_int("nbt: string length overrun"); }
    if dlen != len { return _err_int("nbt: invalid node structure"); }
    _push_be(out, len, 2);
    let off: Int = tree.data_off[node];
    var i = 0;
    while i < len {
      out.push(tree.data[off + i]);
      i = i + 1;
    }
    return _ok_int(0);
  }
  if t == NBT_TAG_LIST {
    let elem: Int = tree.values[node];
    if elem < 0 || elem > NBT_TAG_LONG_ARRAY { return _err_int(_unknown(elem)); }
    let count: Int = tree.child_count[node];
    if count > 0 && elem == NBT_TAG_END { return _err_int("nbt: list element type mismatch"); }
    if count > 0 && depth > NBT_MAX_DEPTH { return _err_int("nbt: depth exceeded"); }
    out.push(elem as UInt8);
    _push_be(out, count, 4);
    var i = 0;
    while i < count {
      let ch = nbt_child_at(tree, node, i);
      if ch < 0 { return _err_int("nbt: invalid node structure"); }
      let ct: Int = tree.types[ch];
      if ct != elem { return _err_int("nbt: list element type mismatch"); }
      let cr = _encode_payload(tree, ch, out, depth + 1);
      if !cr.is_ok { return _err_int(cr.error); }
      i = i + 1;
    }
    return _ok_int(0);
  }
  if t == NBT_TAG_COMPOUND {
    if depth > NBT_MAX_DEPTH { return _err_int("nbt: depth exceeded"); }
    let count: Int = tree.child_count[node];
    var i = 0;
    while i < count {
      let ch = nbt_child_at(tree, node, i);
      if ch < 0 { return _err_int("nbt: invalid node structure"); }
      let cr = _encode_node(tree, ch, out, depth + 1);
      if !cr.is_ok { return _err_int(cr.error); }
      i = i + 1;
    }
    out.push(NBT_TAG_END as UInt8);
    return _ok_int(0);
  }
  if t == NBT_TAG_INT_ARRAY {
    let count: Int = tree.values[node];
    let dlen: Int = tree.data_len[node];
    if count < 0 { return _err_int("nbt: negative length"); }
    if dlen != count * 4 { return _err_int("nbt: invalid node structure"); }
    _push_be(out, count, 4);
    let off: Int = tree.data_off[node];
    var i = 0;
    while i < dlen {
      out.push(tree.data[off + i]);
      i = i + 1;
    }
    return _ok_int(0);
  }
  if t == NBT_TAG_LONG_ARRAY {
    let count: Int = tree.values[node];
    let dlen: Int = tree.data_len[node];
    if count < 0 { return _err_int("nbt: negative length"); }
    if dlen != count * 8 { return _err_int("nbt: invalid node structure"); }
    _push_be(out, count, 4);
    let off: Int = tree.data_off[node];
    var i = 0;
    while i < dlen {
      out.push(tree.data[off + i]);
      i = i + 1;
    }
    return _ok_int(0);
  }
  return _err_int(_unknown(t));
}

// Write tag byte + name + payload of `node`.
fn _encode_node(tree: &NbtTree, node: Int, out: &mut Vec<UInt8>, depth: Int) -> Result[Int, Str] {
  if node < 0 || node >= tree.types.len() {
    return _err_int("nbt: node index out of range");
  }
  let t: Int = tree.types[node];
  if t < NBT_TAG_BYTE || t > NBT_TAG_LONG_ARRAY {
    return _err_int(_unknown(t));
  }
  out.push(t as UInt8);
  let nr = _encode_name(tree, node, out);
  if !nr.is_ok {
    return _err_int(nr.error);
  }
  return _encode_payload(tree, node, out, depth);
}

/// Encode a finalized (or builder-built) NbtTree as a complete NBT
/// document. Child ranges are rebuilt first, so a tree assembled with the
/// nbt_add_* functions encodes without a separate nbt_finalize call. The
/// root must be a TAG_Compound; nesting deeper than NBT_MAX_DEPTH, an
/// invalid List element type and any store inconsistency are reported as
/// Err with the catalog messages in SPEC.md.
pub fn nbt_encode(tree: &mut NbtTree) -> Result[Vec[UInt8], Str] {
  _finalize(tree);
  let root = tree.root;
  if root < 0 {
    return _err_bytes("nbt: empty tree");
  }
  if root >= tree.types.len() {
    return _err_bytes("nbt: invalid node structure");
  }
  let rt: Int = tree.types[root];
  if rt != NBT_TAG_COMPOUND {
    return _err_bytes("nbt: root tag is not a compound");
  }
  var out = Vec[UInt8].new();
  let er = _encode_node(tree, root, &mut out, 1);
  if !er.is_ok {
    return _err_bytes(er.error);
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

/// Create an empty node store (no root). Add the root with parent -1.
pub fn nbt_tree_new() -> NbtTree {
  return NbtTree{
    types: Vec[Int].new();
    names: Vec[Str].new();
    name_off: Vec[Int].new();
    name_len: Vec[Int].new();
    parent: Vec[Int].new();
    child_start: Vec[Int].new();
    child_count: Vec[Int].new();
    order: Vec[Int].new();
    values: Vec[Int].new();
    data_off: Vec[Int].new();
    data_len: Vec[Int].new();
    data: Vec[UInt8].new();
    root: -1;
  };
}

/// Rebuild the child ranges from the parent links. Builder-built trees need
/// this before navigation accessors; nbt_decode and nbt_encode call it
/// internally. O(nodes).
pub fn nbt_finalize(tree: &mut NbtTree) {
  _finalize(tree);
}

/// Add a TAG_Compound node and return its index. Pass parent -1 for the
/// root; the first root wins. Child names inside a Compound are the
/// caller's responsibility (duplicates are legal NBT).
pub fn nbt_add_compound(tree: &mut NbtTree, parent: Int, name: Str) -> Int {
  let nl = string.str_len(name);
  let noff = _push_name(tree, name);
  return _add_core(tree, NBT_TAG_COMPOUND, parent, name, noff, nl);
}

/// Add a TAG_List node and return its index. `elem_type` is the declared
/// element tag type (0 for an empty list, as vanilla NBT writes); every
/// element added under the list must match it. When `parent` is a List the
/// `name` is ignored (List elements are unnamed) and the caller may pass "".
pub fn nbt_add_list(tree: &mut NbtTree, parent: Int, name: Str, elem_type: Int) -> Int {
  let nl = string.str_len(name);
  let noff = _push_name(tree, name);
  let idx = _add_core(tree, NBT_TAG_LIST, parent, name, noff, nl);
  tree.values[idx] = elem_type;
  return idx;
}

// Shared body of every scalar add: store `v` under the node's tag.
fn _add_scalar(tree: &mut NbtTree, parent: Int, name: Str, tag: Int, v: Int) -> Int {
  let nl = string.str_len(name);
  let noff = _push_name(tree, name);
  let idx = _add_core(tree, tag, parent, name, noff, nl);
  tree.values[idx] = v;
  return idx;
}

/// Add a TAG_Byte node (signed 8-bit value; the low byte is encoded).
pub fn nbt_add_byte(tree: &mut NbtTree, parent: Int, name: Str, v: Int) -> Int {
  return _add_scalar(tree, parent, name, NBT_TAG_BYTE, v);
}

/// Add a TAG_Short node (signed 16-bit value; the low 2 bytes are encoded).
pub fn nbt_add_short(tree: &mut NbtTree, parent: Int, name: Str, v: Int) -> Int {
  return _add_scalar(tree, parent, name, NBT_TAG_SHORT, v);
}

/// Add a TAG_Int node (signed 32-bit value; the low 4 bytes are encoded).
pub fn nbt_add_int(tree: &mut NbtTree, parent: Int, name: Str, v: Int) -> Int {
  return _add_scalar(tree, parent, name, NBT_TAG_INT, v);
}

/// Add a TAG_Long node (signed 64-bit value).
pub fn nbt_add_long(tree: &mut NbtTree, parent: Int, name: Str, v: Int) -> Int {
  return _add_scalar(tree, parent, name, NBT_TAG_LONG, v);
}

/// Add a TAG_Float node from the raw 32-bit IEEE-754 bit pattern (there is
/// no Float64 bitcast in XIOM v0.61.3; see SPEC.md).
pub fn nbt_add_float_bits(tree: &mut NbtTree, parent: Int, name: Str, bits: Int) -> Int {
  return _add_scalar(tree, parent, name, NBT_TAG_FLOAT, bits);
}

/// Add a TAG_Double node from the raw 64-bit IEEE-754 bit pattern (there is
/// no Float64 bitcast in XIOM v0.61.3; see SPEC.md).
pub fn nbt_add_double_bits(tree: &mut NbtTree, parent: Int, name: Str, bits: Int) -> Int {
  return _add_scalar(tree, parent, name, NBT_TAG_DOUBLE, bits);
}

/// Add a TAG_String node. The UTF-8 bytes of `v` are stored verbatim; a
/// byte length above 65535 is rejected by nbt_encode ("nbt: string length
/// overrun") because NBT prefixes strings with an unsigned 16-bit length.
pub fn nbt_add_str(tree: &mut NbtTree, parent: Int, name: Str, v: Str) -> Int {
  let vl = string.str_len(v);
  let voff = tree.data.len();
  var i = 0;
  while i < vl {
    tree.data.push(string.byte_at(v, i));
    i = i + 1;
  }
  let nl = string.str_len(name);
  let noff = _push_name(tree, name);
  let idx = _add_core(tree, NBT_TAG_STRING, parent, name, noff, nl);
  tree.values[idx] = vl;
  tree.data_off[idx] = voff;
  tree.data_len[idx] = vl;
  return idx;
}

/// Add a TAG_Byte_Array node with the given bytes (copied verbatim).
pub fn nbt_add_byte_array(tree: &mut NbtTree, parent: Int, name: Str, bytes: Vec[UInt8]) -> Int {
  let nl = string.str_len(name);
  let noff = _push_name(tree, name);
  let voff = tree.data.len();
  let n = bytes.len();
  var i = 0;
  while i < n {
    tree.data.push(bytes[i]);
    i = i + 1;
  }
  let idx = _add_core(tree, NBT_TAG_BYTE_ARRAY, parent, name, noff, nl);
  tree.values[idx] = n;
  tree.data_off[idx] = voff;
  tree.data_len[idx] = n;
  return idx;
}

/// Add a TAG_Int_Array node: each Int is encoded as 4 big-endian bytes.
pub fn nbt_add_int_array(tree: &mut NbtTree, parent: Int, name: Str, values: Vec[Int]) -> Int {
  let nl = string.str_len(name);
  let noff = _push_name(tree, name);
  let voff = tree.data.len();
  let n = values.len();
  var i = 0;
  while i < n {
    let v: Int = values[i];
    _push_be(&mut tree.data, v, 4);
    i = i + 1;
  }
  let idx = _add_core(tree, NBT_TAG_INT_ARRAY, parent, name, noff, nl);
  tree.values[idx] = n;
  tree.data_off[idx] = voff;
  tree.data_len[idx] = n * 4;
  return idx;
}

/// Add a TAG_Long_Array node: each Int is encoded as 8 big-endian bytes.
pub fn nbt_add_long_array(tree: &mut NbtTree, parent: Int, name: Str, values: Vec[Int]) -> Int {
  let nl = string.str_len(name);
  let noff = _push_name(tree, name);
  let voff = tree.data.len();
  let n = values.len();
  var i = 0;
  while i < n {
    let v: Int = values[i];
    _push_be(&mut tree.data, v, 8);
    i = i + 1;
  }
  let idx = _add_core(tree, NBT_TAG_LONG_ARRAY, parent, name, noff, nl);
  tree.values[idx] = n;
  tree.data_off[idx] = voff;
  tree.data_len[idx] = n * 8;
  return idx;
}

// --------------------------------------------------
//  Navigation accessors
// --------------------------------------------------

/// Number of nodes in the store (0 for an empty tree).
pub fn nbt_node_count(tree: &NbtTree) -> Int {
  return tree.types.len();
}

/// Root node index, or -1 when the tree has no root.
pub fn nbt_root(tree: &NbtTree) -> Int {
  return tree.root;
}

/// Tag type (1-12) of `node`, or -1 for an out-of-range index.
pub fn nbt_tag_type(tree: &NbtTree, node: Int) -> Int {
  if node < 0 || node >= tree.types.len() {
    return -1;
  }
  let t: Int = tree.types[node];
  return t;
}

/// Name of `node` ("" for list elements and unnamed nodes; "" for an
/// out-of-range index). Names containing a raw 0x00 byte are truncated by
/// the Str view; use the stored bytes via re-encode for full fidelity.
pub fn nbt_name(tree: &NbtTree, node: Int) -> Str {
  if node < 0 || node >= tree.names.len() {
    return "";
  }
  let s: Str = tree.names[node];
  return s;
}

/// Parent node index, or -1 for the root and for out-of-range nodes.
pub fn nbt_parent(tree: &NbtTree, node: Int) -> Int {
  if node < 0 || node >= tree.parent.len() {
    return -1;
  }
  let p: Int = tree.parent[node];
  return p;
}

/// Number of children of `node` (0 for leaves and out-of-range nodes).
pub fn nbt_child_count(tree: &NbtTree, node: Int) -> Int {
  if node < 0 || node >= tree.child_count.len() {
    return 0;
  }
  let c: Int = tree.child_count[node];
  return c;
}

/// Child node index at position `index` (0-based), or -1 when out of range.
pub fn nbt_child_at(tree: &NbtTree, node: Int, index: Int) -> Int {
  if node < 0 || node >= tree.child_start.len() {
    return -1;
  }
  if index < 0 {
    return -1;
  }
  let c: Int = tree.child_count[node];
  if index >= c {
    return -1;
  }
  let s: Int = tree.child_start[node];
  let at = s + index;
  if at < 0 || at >= tree.order.len() {
    return -1;
  }
  let ch: Int = tree.order[at];
  return ch;
}

/// First child of `node` whose name compares equal to `name`, or -1 when
/// absent. Str equality goes through str_compare (BUG 17: `==` on Str
/// values read from a Vec lowers to a pointer compare).
pub fn nbt_find_child(tree: &NbtTree, node: Int, name: Str) -> Int {
  let c: Int = nbt_child_count(tree, node);
  var i = 0;
  while i < c {
    let ch: Int = nbt_child_at(tree, node, i);
    if ch >= 0 && ch < tree.names.len() {
      let nm: Str = tree.names[ch];
      if compare.str_compare(nm, name) == 0 {
        return ch;
      }
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Typed readers
// --------------------------------------------------

// Ok(tag) when `node` holds a tag of type `want`; Err otherwise.
fn _require_type(tree: &NbtTree, node: Int, want: Int) -> Result[Int, Str] {
  if node < 0 || node >= tree.types.len() {
    return _err_int("nbt: node index out of range");
  }
  let t: Int = tree.types[node];
  if t != want {
    return _err_int(_unexpected(t));
  }
  return _ok_int(t);
}

/// Signed TAG_Byte value. Err("nbt: unexpected tag type N") on another tag.
pub fn nbt_get_byte(tree: &NbtTree, node: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_BYTE);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let v: Int = tree.values[node];
  return _ok_int(v);
}

/// Signed TAG_Short value. Err("nbt: unexpected tag type N") on another tag.
pub fn nbt_get_short(tree: &NbtTree, node: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_SHORT);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let v: Int = tree.values[node];
  return _ok_int(v);
}

/// Signed TAG_Int value. Err("nbt: unexpected tag type N") on another tag.
pub fn nbt_get_int(tree: &NbtTree, node: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_INT);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let v: Int = tree.values[node];
  return _ok_int(v);
}

/// Signed TAG_Long value. Err("nbt: unexpected tag type N") on another tag.
pub fn nbt_get_long(tree: &NbtTree, node: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_LONG);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let v: Int = tree.values[node];
  return _ok_int(v);
}

/// Raw 32-bit IEEE-754 bits of a TAG_Float. Tagged as a tag-type error on
/// another tag; use nbt_add_float_bits to build one.
pub fn nbt_get_float_bits(tree: &NbtTree, node: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_FLOAT);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let v: Int = tree.values[node];
  return _ok_int(v);
}

/// Raw 64-bit IEEE-754 bits of a TAG_Double (may read negative for bit 63
/// set; the two's-complement pattern is the documented bit pattern).
pub fn nbt_get_double_bits(tree: &NbtTree, node: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_DOUBLE);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let v: Int = tree.values[node];
  return _ok_int(v);
}

/// UTF-8 TAG_String payload as a Str (bytes materialized verbatim; a raw
/// 0x00 byte terminates the Str view, see SPEC.md). Err on another tag.
pub fn nbt_get_str(tree: &NbtTree, node: Int) -> Result[Str, Str] {
  let cr = _require_type(tree, node, NBT_TAG_STRING);
  if !cr.is_ok {
    return _err_str(cr.error);
  }
  let len: Int = tree.data_len[node];
  let off: Int = tree.data_off[node];
  return _ok_str(_materialize(tree, off, len));
}

/// TAG_Byte_Array payload as a fresh Vec[UInt8] (bytes copied). Err on
/// another tag.
pub fn nbt_get_byte_array(tree: &NbtTree, node: Int) -> Result[Vec[UInt8], Str] {
  let cr = _require_type(tree, node, NBT_TAG_BYTE_ARRAY);
  if !cr.is_ok {
    return _err_bytes(cr.error);
  }
  let len: Int = tree.data_len[node];
  let off: Int = tree.data_off[node];
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(tree.data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// TAG_Int_Array payload as a fresh Vec[Int] (values decoded as signed
/// 32-bit big-endian ints). Err on another tag.
pub fn nbt_get_int_array(tree: &NbtTree, node: Int) -> Result[Vec[Int], Str] {
  let cr = _require_type(tree, node, NBT_TAG_INT_ARRAY);
  if !cr.is_ok {
    return _err_ints(cr.error);
  }
  let count: Int = tree.values[node];
  let off: Int = tree.data_off[node];
  var out = Vec[Int].new();
  var i = 0;
  while i < count {
    var v: Int = 0;
    var k = 0;
    while k < 4 {
      let b = (tree.data[off + i * 4 + k] as Int) & 0xFF;
      v = v * 256 + b;
      k = k + 1;
    }
    if (tree.data[off + i * 4] as Int) >= 128 {
      v = v - 4294967296;
    }
    out.push(v);
    i = i + 1;
  }
  return _ok_ints(out);
}

/// TAG_Long_Array payload as a fresh Vec[Int] (values decoded as signed
/// 64-bit big-endian ints; patterns above 2^63-1 wrap to the same
/// two's-complement Int). Err on another tag.
pub fn nbt_get_long_array(tree: &NbtTree, node: Int) -> Result[Vec[Int], Str] {
  let cr = _require_type(tree, node, NBT_TAG_LONG_ARRAY);
  if !cr.is_ok {
    return _err_ints(cr.error);
  }
  let count: Int = tree.values[node];
  let off: Int = tree.data_off[node];
  var out = Vec[Int].new();
  var i = 0;
  while i < count {
    var v: Int = 0;
    let base = off + i * 8;
    if (tree.data[base] as Int) >= 128 {
      v = -1;
    }
    var k = 0;
    while k < 8 {
      let b = (tree.data[base + k] as Int) & 0xFF;
      v = v * 256 + b;
      k = k + 1;
    }
    out.push(v);
    i = i + 1;
  }
  return _ok_ints(out);
}

/// Number of elements of a TAG_List node. Err on another tag.
pub fn nbt_list_len(tree: &NbtTree, node: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_LIST);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let c: Int = tree.child_count[node];
  return _ok_int(c);
}

/// Declared element tag type of a TAG_List node (0 means empty). Err on
/// another tag.
pub fn nbt_list_element_type(tree: &NbtTree, node: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_LIST);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let e: Int = tree.values[node];
  return _ok_int(e);
}

/// Node index of list element `index` (0-based). Err on a non-list node or
/// an out-of-range index ("nbt: list index out of range").
pub fn nbt_list_item(tree: &NbtTree, node: Int, index: Int) -> Result[Int, Str] {
  let cr = _require_type(tree, node, NBT_TAG_LIST);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let ch = nbt_child_at(tree, node, index);
  if ch < 0 {
    return _err_int("nbt: list index out of range");
  }
  return _ok_int(ch);
}
