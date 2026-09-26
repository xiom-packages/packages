// XIOM -- xiom.hid: USB HID report-descriptor codec (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Port task: greenfield pure-XIOM implementation (no FFI) of the xiom.hid
// placeholder.
//
// A pure-XIOM (no FFI) codec for USB HID report descriptors (HID 1.11,
// section 6.2.2): parse and validate a descriptor stream into a flat,
// self-contained item store (parallel vectors, no Vec[StructType]), read it
// back through free accessors, and re-emit it canonically. See SPEC.md for
// the documented subset, the byte layout, the error catalog, the
// depth/push/pop/usage-page conventions and the documented limits.
//
// Documented subset:
//   * short items: one prefix byte -- bSize in bits 1..0 (0/1/2 -> 0/1/2
//     data bytes; the 4-byte form, bSize = 3, is outside the subset and is
//     rejected), bType in bits 3..2 (0 main, 1 global, 2 local) and bTag in
//     bits 7..4; data bytes are little-endian and at most 2 bytes wide;
//   * long items: the 0xFE prefix, bDataSize, bLongItemTag and the payload,
//     preserved verbatim as type 3 (LONG) with no interpretation;
//   * main items Input(0x8), Output(0x9), Collection(0xA), Feature(0xB) and
//     End Collection(0xC);
//   * global items Usage Page(0x0), Logical Minimum(0x1), Logical
//     Maximum(0x2), Physical Minimum(0x3), Physical Maximum(0x4), Unit(0x5),
//     Unit Exponent(0x6), Report Size(0x7), Report ID(0x8), Report
//     Count(0x9), Push(0xA) and Pop(0xB);
//   * local items Usage(0x0), Usage Minimum(0x1), Usage Maximum(0x2),
//     Designator Index(0x3), Designator Minimum(0x4), Designator Maximum(0x5),
//     String Index(0x7), String Minimum(0x8), String Maximum(0x9) and
//     Delimiter(0xA).
// Anything else is rejected: the reserved short type (bType = 3 outside the
// 0xFE long prefix), the 4-byte short size, and any tag not listed above.
//
// Non-goals: no report-field assembly (no report bit offsets, no field
// extraction), no usage tables or usage-name resolution, no Report ID
// semantics beyond recording the item, no Push/Pop global-state replay
// beyond balance and Usage Page tracking, no HID device IO.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing struct payloads such as Result[HidDescriptor, Str]
//     directly in other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * every Vec[Int] element read is bound to a typed local.
//   * the item prefix is decoded and encoded with division/modulo only; no
//     bitwise operator is used anywhere in this module.
//   * every push on one parallel vector is mirrored on all its siblings
//     through _add_item, and hid_emit refuses stores whose parallel vectors
//     have drifted apart (`hid: invalid store`).

module xiom.hid

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Item type code: main item (bType 0).
pub const HID_TYPE_MAIN: Int = 0;
/// Item type code: global item (bType 1).
pub const HID_TYPE_GLOBAL: Int = 1;
/// Item type code: local item (bType 2).
pub const HID_TYPE_LOCAL: Int = 2;
/// Item type code: long item (the 0xFE prefix form).
pub const HID_TYPE_LONG: Int = 3;

/// The long-item prefix byte (0xFE).
pub const HID_LONG_ITEM_PREFIX: Int = 254;

/// Main item tag: Input.
pub const HID_MAIN_INPUT: Int = 8;
/// Main item tag: Output.
pub const HID_MAIN_OUTPUT: Int = 9;
/// Main item tag: Collection.
pub const HID_MAIN_COLLECTION: Int = 10;
/// Main item tag: Feature.
pub const HID_MAIN_FEATURE: Int = 11;
/// Main item tag: End Collection.
pub const HID_MAIN_END_COLLECTION: Int = 12;

/// Global item tag: Usage Page.
pub const HID_GLOBAL_USAGE_PAGE: Int = 0;
/// Global item tag: Logical Minimum.
pub const HID_GLOBAL_LOGICAL_MIN: Int = 1;
/// Global item tag: Logical Maximum.
pub const HID_GLOBAL_LOGICAL_MAX: Int = 2;
/// Global item tag: Physical Minimum.
pub const HID_GLOBAL_PHYSICAL_MIN: Int = 3;
/// Global item tag: Physical Maximum.
pub const HID_GLOBAL_PHYSICAL_MAX: Int = 4;
/// Global item tag: Unit.
pub const HID_GLOBAL_UNIT: Int = 5;
/// Global item tag: Unit Exponent.
pub const HID_GLOBAL_UNIT_EXPONENT: Int = 6;
/// Global item tag: Report Size.
pub const HID_GLOBAL_REPORT_SIZE: Int = 7;
/// Global item tag: Report ID.
pub const HID_GLOBAL_REPORT_ID: Int = 8;
/// Global item tag: Report Count.
pub const HID_GLOBAL_REPORT_COUNT: Int = 9;
/// Global item tag: Push.
pub const HID_GLOBAL_PUSH: Int = 10;
/// Global item tag: Pop.
pub const HID_GLOBAL_POP: Int = 11;

/// Local item tag: Usage.
pub const HID_LOCAL_USAGE: Int = 0;
/// Local item tag: Usage Minimum.
pub const HID_LOCAL_USAGE_MIN: Int = 1;
/// Local item tag: Usage Maximum.
pub const HID_LOCAL_USAGE_MAX: Int = 2;
/// Local item tag: Designator Index.
pub const HID_LOCAL_DESIGNATOR_INDEX: Int = 3;
/// Local item tag: Designator Minimum.
pub const HID_LOCAL_DESIGNATOR_MIN: Int = 4;
/// Local item tag: Designator Maximum.
pub const HID_LOCAL_DESIGNATOR_MAX: Int = 5;
/// Local item tag: String Index.
pub const HID_LOCAL_STRING_INDEX: Int = 7;
/// Local item tag: String Minimum.
pub const HID_LOCAL_STRING_MIN: Int = 8;
/// Local item tag: String Maximum.
pub const HID_LOCAL_STRING_MAX: Int = 9;
/// Local item tag: Delimiter.
pub const HID_LOCAL_DELIMITER: Int = 10;

/// Documented maximum collection nesting depth.
///
/// A top-level Collection item opens a collection at depth 0, so the deepest
/// accepted collection is opened at depth 31; opening one at depth 32 (or
/// deeper) is rejected with
/// `Err("hid: collection nesting exceeds limit of 32")`.
pub fn hid_max_collection_depth() -> Int {
  return 32;
}

// --------------------------------------------------
//  Item store
// --------------------------------------------------

/// Flat HID report-descriptor item store.
///
/// Every parsed item occupies one index in all eight parallel vectors, in
/// stream order (short items and long items alike). Fields are
/// implementation details; callers should use the free accessors below.
///
///   * `item_type[i]`: `HID_TYPE_MAIN`, `HID_TYPE_GLOBAL`, `HID_TYPE_LOCAL`
///     or `HID_TYPE_LONG`;
///   * `item_tag[i]`: the bTag of a short item, or the bLongItemTag of a
///     long item;
///   * `item_size[i]`: the number of data bytes: 0, 1 or 2 for short items
///     (the 4-byte form is rejected by `hid_parse`), the bDataSize value
///     (0..255) for long items;
///   * `item_data[i]`: the unsigned little-endian value of the short item's
///     data bytes (0 for size 0); always 0 for long items, whose bytes stay
///     in `item_raw[i]`;
///   * `item_raw[i]`: the verbatim long-item payload (empty for short
///     items);
///   * `item_depth[i]`: the number of enclosing open collections. For a
///     Collection item it is the depth of the collection it opens, and for
///     the matching End Collection item it is the depth of the collection it
///     closes (the same value); items directly inside a top-level collection
///     have depth 1;
///   * `item_stack[i]`: the number of Push items not yet matched by a Pop
///     *after* processing item `i` (a Push reports the incremented balance,
///     a Pop the decremented one);
///   * `item_usage_page[i]`: the Usage Page global in effect for item `i`
///     (see `hid_item_usage_page`).
///
/// The store is self-contained: it holds no spans into the parse buffer, so
/// the accessors and `hid_emit` never need the source bytes again.
pub type HidDescriptor = {
  item_type: Vec[Int];
  item_tag: Vec[Int];
  item_size: Vec[Int];
  item_data: Vec[Int];
  item_raw: Vec[Vec[UInt8]];
  item_depth: Vec[Int];
  item_stack: Vec[Int];
  item_usage_page: Vec[Int];
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[HidDescriptor, Str].
fn _ok_desc(v: HidDescriptor) -> Result[HidDescriptor, Str] {
  return Ok(v);
}

// Err(m) for Result[HidDescriptor, Str].
fn _err_desc(m: Str) -> Result[HidDescriptor, Str] {
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
//  Internal byte and prefix helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned little-endian Int of the `size` bytes at `pos`. The caller
// guarantees pos + size <= data.len(); size 0 yields 0.
fn _read_le(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var i = size - 1;
  while i >= 0 {
    v = v * 256 + _byte(data, pos + i);
    i = i - 1;
  }
  return v;
}

// Byte `shift` of a non-negative `v`, counting from the least significant
// byte. Division/modulo only (no bitwise operators).
fn _le_byte(v: Int, shift: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift {
    q = q / 256;
    k = k + 1;
  }
  return (q % 256) as UInt8;
}

// Append the low `size` bytes of a non-negative `v` in little-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_le_byte(v, i));
    i = i + 1;
  }
}

// Append every byte of `v` to `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// bSize field of a short-item prefix byte (prefix >= 0, prefix < 256).
fn _size_of(prefix: Int) -> Int {
  return prefix % 4;
}

// bType field of a short-item prefix byte.
fn _type_of(prefix: Int) -> Int {
  return (prefix % 16) / 4;
}

// bTag field of a short-item prefix byte.
fn _tag_of(prefix: Int) -> Int {
  return prefix / 16;
}

// True when `tag` is one of the documented tags of short item type `t`.
fn _tag_known(t: Int, tag: Int) -> Bool {
  if t == HID_TYPE_MAIN {
    if tag == HID_MAIN_INPUT { return true; }
    if tag == HID_MAIN_OUTPUT { return true; }
    if tag == HID_MAIN_COLLECTION { return true; }
    if tag == HID_MAIN_FEATURE { return true; }
    if tag == HID_MAIN_END_COLLECTION { return true; }
    return false;
  }
  if t == HID_TYPE_GLOBAL {
    if tag == HID_GLOBAL_USAGE_PAGE { return true; }
    if tag == HID_GLOBAL_LOGICAL_MIN { return true; }
    if tag == HID_GLOBAL_LOGICAL_MAX { return true; }
    if tag == HID_GLOBAL_PHYSICAL_MIN { return true; }
    if tag == HID_GLOBAL_PHYSICAL_MAX { return true; }
    if tag == HID_GLOBAL_UNIT { return true; }
    if tag == HID_GLOBAL_UNIT_EXPONENT { return true; }
    if tag == HID_GLOBAL_REPORT_SIZE { return true; }
    if tag == HID_GLOBAL_REPORT_ID { return true; }
    if tag == HID_GLOBAL_REPORT_COUNT { return true; }
    if tag == HID_GLOBAL_PUSH { return true; }
    if tag == HID_GLOBAL_POP { return true; }
    return false;
  }
  if t == HID_TYPE_LOCAL {
    if tag == HID_LOCAL_USAGE { return true; }
    if tag == HID_LOCAL_USAGE_MIN { return true; }
    if tag == HID_LOCAL_USAGE_MAX { return true; }
    if tag == HID_LOCAL_DESIGNATOR_INDEX { return true; }
    if tag == HID_LOCAL_DESIGNATOR_MIN { return true; }
    if tag == HID_LOCAL_DESIGNATOR_MAX { return true; }
    if tag == HID_LOCAL_STRING_INDEX { return true; }
    if tag == HID_LOCAL_STRING_MIN { return true; }
    if tag == HID_LOCAL_STRING_MAX { return true; }
    if tag == HID_LOCAL_DELIMITER { return true; }
    return false;
  }
  return false;
}

// --------------------------------------------------
//  Store construction
// --------------------------------------------------

// An empty store (no items).
fn _hid_new() -> HidDescriptor {
  return HidDescriptor{
    item_type: Vec[Int].new();
    item_tag: Vec[Int].new();
    item_size: Vec[Int].new();
    item_data: Vec[Int].new();
    item_raw: Vec[Vec[UInt8]].new();
    item_depth: Vec[Int].new();
    item_stack: Vec[Int].new();
    item_usage_page: Vec[Int].new();
  };
}

// Append one item; every parallel vector receives exactly one push here, so
// the store can never drift during parsing.
fn _add_item(h: &mut HidDescriptor, t: Int, tag: Int, sz: Int, data: Int, raw: Vec[UInt8], depth: Int, stack: Int, page: Int) {
  h.item_type.push(t);
  h.item_tag.push(tag);
  h.item_size.push(sz);
  h.item_data.push(data);
  h.item_raw.push(raw);
  h.item_depth.push(depth);
  h.item_stack.push(stack);
  h.item_usage_page.push(page);
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse and validate a HID report-descriptor byte stream.
///
/// The walk is sequential over the whole buffer; the result is a
/// self-contained flat `HidDescriptor` store (see the type comment for the
/// per-item conventions). An empty buffer yields Ok with zero items.
///
/// Per-item validation order (the first failing check wins):
///  1. a 0xFE prefix enters the long-item path: fewer than two bytes after
///     the prefix (bDataSize and bLongItemTag) or a payload running past the
///     buffer end is `hid: truncated long item`;
///  2. a short item with bSize = 3 (the 4-byte form) is
///     `hid: reserved item size`;
///  3. a short item with bType = 3 (reserved outside the long prefix) is
///     `hid: reserved item type`;
///  4. a short tag outside the documented set for its type is
///     `hid: reserved item tag`;
///  5. a short item whose data bytes run past the buffer end is
///     `hid: truncated item`;
///  6. structural checks: opening a Collection at depth >=
///     `hid_max_collection_depth()` is
///     `hid: collection nesting exceeds limit of 32`; an End Collection with
///     no open collection is `hid: end collection without collection`; a Pop
///     with an empty Push stack is `hid: pop without push`.
///
/// After the walk, an open collection is `hid: unterminated collection` and
/// an unmatched Push is `hid: unbalanced push` (the collection check runs
/// first). Reserved tags are never silently accepted, and long items are
/// preserved verbatim without interpreting their tag.
/// Complexity: O(data.len()).
pub fn hid_parse(data: &Vec[UInt8]) -> Result[HidDescriptor, Str] {
  var h = _hid_new();
  let total = data.len();
  var pos = 0;
  var cur_depth = 0;
  var stack_depth = 0;
  var cur_page = 0;
  var pages = Vec[Int].new();
  while pos < total {
    let prefix = _byte(data, pos);
    if prefix == HID_LONG_ITEM_PREFIX {
      if pos + 3 > total {
        return _err_desc("hid: truncated long item");
      }
      let dsize = _byte(data, pos + 1);
      let dtag = _byte(data, pos + 2);
      if pos + 3 + dsize > total {
        return _err_desc("hid: truncated long item");
      }
      var raw = Vec[UInt8].new();
      var k = pos + 3;
      while k < pos + 3 + dsize {
        raw.push(data[k]);
        k = k + 1;
      }
      _add_item(&mut h, HID_TYPE_LONG, dtag, dsize, 0, raw, cur_depth, stack_depth, cur_page);
      pos = pos + 3 + dsize;
    } else {
      let size_code = _size_of(prefix);
      let type_code = _type_of(prefix);
      let tag = _tag_of(prefix);
      if size_code == 3 {
        return _err_desc("hid: reserved item size");
      }
      if type_code == 3 {
        return _err_desc("hid: reserved item type");
      }
      if !_tag_known(type_code, tag) {
        return _err_desc("hid: reserved item tag");
      }
      if pos + 1 + size_code > total {
        return _err_desc("hid: truncated item");
      }
      let value = _read_le(data, pos + 1, size_code);
      var depth_val = cur_depth;
      if type_code == HID_TYPE_MAIN {
        if tag == HID_MAIN_COLLECTION {
          if cur_depth >= hid_max_collection_depth() {
            return _err_desc("hid: collection nesting exceeds limit of 32");
          }
          depth_val = cur_depth;
          cur_depth = cur_depth + 1;
        } elif tag == HID_MAIN_END_COLLECTION {
          if cur_depth == 0 {
            return _err_desc("hid: end collection without collection");
          }
          depth_val = cur_depth - 1;
          cur_depth = cur_depth - 1;
        }
      }
      var stack_val = stack_depth;
      if type_code == HID_TYPE_GLOBAL {
        if tag == HID_GLOBAL_USAGE_PAGE {
          cur_page = value;
        } elif tag == HID_GLOBAL_PUSH {
          pages.push(cur_page);
          stack_depth = stack_depth + 1;
          stack_val = stack_depth;
        } elif tag == HID_GLOBAL_POP {
          if stack_depth == 0 {
            return _err_desc("hid: pop without push");
          }
          let top: Int = pages[stack_depth - 1];
          cur_page = top;
          pages.pop();
          stack_depth = stack_depth - 1;
          stack_val = stack_depth;
        }
      }
      _add_item(&mut h, type_code, tag, size_code, value, Vec[UInt8].new(), depth_val, stack_val, cur_page);
      pos = pos + 1 + size_code;
    }
  }
  if cur_depth != 0 {
    return _err_desc("hid: unterminated collection");
  }
  if stack_depth != 0 {
    return _err_desc("hid: unbalanced push");
  }
  return _ok_desc(h);
}

// --------------------------------------------------
//  Item accessors
// --------------------------------------------------

/// Number of items in the stream (short and long).
/// Complexity: O(1).
pub fn hid_item_count(d: &HidDescriptor) -> Int {
  return d.item_type.len();
}

/// Item type of item `i` (`HID_TYPE_MAIN`, `HID_TYPE_GLOBAL`,
/// `HID_TYPE_LOCAL` or `HID_TYPE_LONG`), or -1 for an out-of-range index.
/// Complexity: O(1).
pub fn hid_item_type(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_type.len() {
    return -1;
  }
  let v: Int = d.item_type[i];
  return v;
}

/// bTag of item `i` (the bLongItemTag for long items, 0..255), or -1 for an
/// out-of-range index.
/// Complexity: O(1).
pub fn hid_item_tag(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_tag.len() {
    return -1;
  }
  let v: Int = d.item_tag[i];
  return v;
}

/// Number of data bytes of item `i`: 0, 1 or 2 for short items, the
/// bDataSize value (0..255) for long items, or -1 for an out-of-range index.
/// Complexity: O(1).
pub fn hid_item_size(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_size.len() {
    return -1;
  }
  let v: Int = d.item_size[i];
  return v;
}

/// Unsigned little-endian value of item `i`'s data bytes (0 for a size-0
/// short item, 0 for a long item), or 0 for an out-of-range index (0 is also
/// a legal data value; check the index first when that matters).
/// Complexity: O(1).
pub fn hid_item_data(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_data.len() {
    return 0;
  }
  let v: Int = d.item_data[i];
  return v;
}

/// Signed interpretation of item `i`'s data, sign-extended from its byte
/// width: -128..127 for size 1, -32768..32767 for size 2, 0 for size 0. This
/// is the interpretation used for Logical/Physical Minimum and Maximum,
/// Report Size/Count and the other signed integer items. Long items and
/// out-of-range indexes yield 0.
/// Complexity: O(1).
pub fn hid_item_data_signed(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_type.len() {
    return 0;
  }
  let t: Int = d.item_type[i];
  if t == HID_TYPE_LONG {
    return 0;
  }
  let sz: Int = d.item_size[i];
  let data: Int = d.item_data[i];
  if sz == 1 {
    if data >= 128 { return data - 256; }
    return data;
  }
  if sz == 2 {
    if data >= 32768 { return data - 65536; }
    return data;
  }
  return 0;
}

/// Nibble-signed interpretation of the low four bits of item `i`'s data
/// (`data % 16`, sign-extended from 4 bits): -8..7. This is the
/// interpretation used for the global Unit Exponent item; it is defined for
/// every item (and yields 0 for size 0, long items and out-of-range
/// indexes).
/// Complexity: O(1).
pub fn hid_item_data_nibble_signed(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_data.len() {
    return 0;
  }
  let data: Int = d.item_data[i];
  if data < 0 {
    return 0;
  }
  let n = data % 16;
  if n >= 8 {
    return n - 16;
  }
  return n;
}

/// Copy of item `i`'s data bytes: the recorded little-endian bytes for a
/// short item, the verbatim payload for a long item.
/// Err("hid: item index out of range") when `i` is negative or >=
/// `hid_item_count(d)`.
/// Complexity: O(data size).
pub fn hid_item_data_bytes(d: &HidDescriptor, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= d.item_type.len() {
    return _err_bytes("hid: item index out of range");
  }
  var out = Vec[UInt8].new();
  let t: Int = d.item_type[i];
  if t == HID_TYPE_LONG {
    let raw: Vec[UInt8] = d.item_raw[i];
    _push_bytes(&mut out, &raw);
  } else {
    let sz: Int = d.item_size[i];
    let data: Int = d.item_data[i];
    _push_le(&mut out, data, sz);
  }
  return _ok_bytes(out);
}

/// Copy of item `i`'s complete encoded bytes: the prefix byte (0xFE,
/// bDataSize, bLongItemTag for a long item) and its data bytes. For any item
/// produced by `hid_parse`, concatenating every `hid_item_bytes` result
/// reproduces the original stream exactly.
/// Err("hid: item index out of range") when `i` is negative or >=
/// `hid_item_count(d)`.
/// Complexity: O(item size).
pub fn hid_item_bytes(d: &HidDescriptor, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= d.item_type.len() {
    return _err_bytes("hid: item index out of range");
  }
  var out = Vec[UInt8].new();
  let t: Int = d.item_type[i];
  let tag: Int = d.item_tag[i];
  let sz: Int = d.item_size[i];
  if t == HID_TYPE_LONG {
    out.push(HID_LONG_ITEM_PREFIX as UInt8);
    out.push(sz as UInt8);
    out.push(tag as UInt8);
    let raw: Vec[UInt8] = d.item_raw[i];
    _push_bytes(&mut out, &raw);
  } else {
    out.push((sz + t * 4 + tag * 16) as UInt8);
    let data: Int = d.item_data[i];
    _push_le(&mut out, data, sz);
  }
  return _ok_bytes(out);
}

/// Number of enclosing open collections of item `i`. For a Collection item
/// this is the depth of the collection it opens, and for its End Collection
/// the depth of the collection it closes; -1 for an out-of-range index.
/// Complexity: O(1).
pub fn hid_item_depth(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_depth.len() {
    return -1;
  }
  let v: Int = d.item_depth[i];
  return v;
}

/// Push/Pop balance after item `i`: the number of Push items not yet matched
/// by a Pop (a Push item reports the incremented balance, a Pop the
/// decremented one), or -1 for an out-of-range index.
/// Complexity: O(1).
pub fn hid_item_stack(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_stack.len() {
    return -1;
  }
  let v: Int = d.item_stack[i];
  return v;
}

/// Collection kind (the Collection item's data value: 0 Physical,
/// 1 Application, 2 Logical, 3 Report, 4 Named Array, 5 Usage Switch,
/// 6 Usage Modifier) of item `i`, or -1 when item `i` is not a Collection or
/// the index is out of range.
/// Complexity: O(1).
pub fn hid_item_collection_kind(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_type.len() {
    return -1;
  }
  let t: Int = d.item_type[i];
  if t != HID_TYPE_MAIN {
    return -1;
  }
  let tag: Int = d.item_tag[i];
  if tag != HID_MAIN_COLLECTION {
    return -1;
  }
  let data: Int = d.item_data[i];
  return data;
}

/// Usage ID carried by item `i` when it is a local Usage, Usage Minimum or
/// Usage Maximum item; -1 when item `i` carries no usage or the index is out
/// of range (a legal usage ID is never negative, so -1 is unambiguous here).
/// Note that with the 4-byte form out of the subset there are no 32-bit
/// extended usages: the usage ID is always the recorded data value and the
/// page comes from `hid_item_usage_page`.
/// Complexity: O(1).
pub fn hid_item_usage(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_type.len() {
    return -1;
  }
  let t: Int = d.item_type[i];
  if t != HID_TYPE_LOCAL {
    return -1;
  }
  let tag: Int = d.item_tag[i];
  if tag == HID_LOCAL_USAGE {
    let v: Int = d.item_data[i];
    return v;
  }
  if tag == HID_LOCAL_USAGE_MIN {
    let v2: Int = d.item_data[i];
    return v2;
  }
  if tag == HID_LOCAL_USAGE_MAX {
    let v3: Int = d.item_data[i];
    return v3;
  }
  return -1;
}

/// Usage Page global in effect for item `i` (0 before the first Usage Page
/// item and for an out-of-range index).
///
/// The page takes effect with the Usage Page item itself (which reports its
/// own new page). Push saves the current page and Pop restores it, so a Pop
/// item reports the restored page; the page therefore reflects the global
/// state at every item, not just the most recent Usage Page item in stream
/// order.
/// Complexity: O(1).
pub fn hid_item_usage_page(d: &HidDescriptor, i: Int) -> Int {
  if i < 0 || i >= d.item_usage_page.len() {
    return 0;
  }
  let v: Int = d.item_usage_page[i];
  return v;
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

// Structural well-formedness of a store: parallel vectors aligned, every
// short item's type/tag/size/data in range, every long item's payload length
// consistent, and the depth / push-pop balance / usage page vectors exactly
// what a fresh walk of the item stream would record. A drifted store can
// otherwise produce a non-canonical stream or an out-of-bounds read.
fn _well_formed(d: &HidDescriptor) -> Bool {
  let n = d.item_type.len();
  if d.item_tag.len() != n { return false; }
  if d.item_size.len() != n { return false; }
  if d.item_data.len() != n { return false; }
  if d.item_raw.len() != n { return false; }
  if d.item_depth.len() != n { return false; }
  if d.item_stack.len() != n { return false; }
  if d.item_usage_page.len() != n { return false; }
  var cur_depth = 0;
  var stack_depth = 0;
  var cur_page = 0;
  var pages = Vec[Int].new();
  var i = 0;
  while i < n {
    let t: Int = d.item_type[i];
    let tag: Int = d.item_tag[i];
    let sz: Int = d.item_size[i];
    let data: Int = d.item_data[i];
    let want_depth: Int = d.item_depth[i];
    let want_stack: Int = d.item_stack[i];
    let want_page: Int = d.item_usage_page[i];
    if t == HID_TYPE_LONG {
      if sz < 0 || sz > 255 { return false; }
      if tag < 0 || tag > 255 { return false; }
      if data != 0 { return false; }
      let raw: Vec[UInt8] = d.item_raw[i];
      if raw.len() != sz { return false; }
      if want_depth != cur_depth { return false; }
      if want_stack != stack_depth { return false; }
      if want_page != cur_page { return false; }
    } else {
      if t < 0 || t > 2 { return false; }
      if tag < 0 || tag > 15 { return false; }
      if sz < 0 || sz > 2 { return false; }
      if !_tag_known(t, tag) { return false; }
      if sz == 0 {
        if data != 0 { return false; }
      } elif sz == 1 {
        if data < 0 || data > 255 { return false; }
      } else {
        if data < 0 || data > 65535 { return false; }
      }
      var depth_after = cur_depth;
      if t == HID_TYPE_MAIN {
        if tag == HID_MAIN_COLLECTION {
          if cur_depth >= hid_max_collection_depth() { return false; }
          depth_after = cur_depth;
          cur_depth = cur_depth + 1;
        } elif tag == HID_MAIN_END_COLLECTION {
          if cur_depth == 0 { return false; }
          depth_after = cur_depth - 1;
          cur_depth = cur_depth - 1;
        }
      }
      var stack_after = stack_depth;
      if t == HID_TYPE_GLOBAL {
        if tag == HID_GLOBAL_USAGE_PAGE {
          cur_page = data;
        } elif tag == HID_GLOBAL_PUSH {
          pages.push(cur_page);
          stack_depth = stack_depth + 1;
          stack_after = stack_depth;
        } elif tag == HID_GLOBAL_POP {
          if stack_depth == 0 { return false; }
          let top: Int = pages[stack_depth - 1];
          cur_page = top;
          pages.pop();
          stack_depth = stack_depth - 1;
          stack_after = stack_depth;
        }
      }
      if want_depth != depth_after { return false; }
      if want_stack != stack_after { return false; }
      if want_page != cur_page { return false; }
    }
    i = i + 1;
  }
  if cur_depth != 0 { return false; }
  if stack_depth != 0 { return false; }
  return true;
}

// Append item `i` in its canonical encoding (the only encoding the parser
// accepts for it).
fn _emit_item(d: &HidDescriptor, i: Int, out: &mut Vec[UInt8]) {
  let t: Int = d.item_type[i];
  let tag: Int = d.item_tag[i];
  let sz: Int = d.item_size[i];
  if t == HID_TYPE_LONG {
    out.push(HID_LONG_ITEM_PREFIX as UInt8);
    out.push(sz as UInt8);
    out.push(tag as UInt8);
    let raw: Vec[UInt8] = d.item_raw[i];
    _push_bytes(out, &raw);
  } else {
    out.push((sz + t * 4 + tag * 16) as UInt8);
    let data: Int = d.item_data[i];
    _push_le(out, data, sz);
  }
}

/// Emit the canonical encoding of a parsed store.
///
/// Because every accepted item has exactly one byte encoding, the output is
/// byte-identical to the input of the `hid_parse` that produced `d` (long
/// payloads are copied from the store, not from the source buffer, so this
/// is a real reconstruction). An empty store emits zero bytes.
///
/// Err("hid: invalid store") when the parallel vectors have drifted apart,
/// when a short item's type/tag/size/data is outside the documented domain,
/// when a long item's payload length disagrees with its size, or when the
/// recorded depth/push-pop/page values do not match a fresh walk of the
/// stored items.
/// Complexity: O(emitted size).
pub fn hid_emit(d: &HidDescriptor) -> Result[Vec[UInt8], Str] {
  if !_well_formed(d) {
    return _err_bytes("hid: invalid store");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < d.item_type.len() {
    _emit_item(d, i, &mut out);
    i = i + 1;
  }
  return _ok_bytes(out);
}
