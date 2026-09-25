// XIOM -- xiom.nbt conformance tests (26 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: exact big-endian byte encodings for all twelve
// tag types, nested compounds and lists, empty payloads, builder/navigation
// accessors, typed readers, byte-exact re-encode, and the full error catalog
// (truncated buffer, unknown tag type, string length overrun, negative
// length, depth exceeded, trailing bytes, list element type mismatch, root
// tag / node index errors).
//
// Str payloads and names are compared with str_compare (BUG 17 discipline:
// `==` on Str values read from a Vec lowers to a pointer comparison), and
// Vec[Int] element reads are bound to typed locals (BUG 17 family).

module nbt_tests
use xiom.io; use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;
use xiom.nbt;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn clone_bytes(v: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  return v;
}

fn ints2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn ints3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn ints_equal(a: Vec[Int], b: Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_tree_is(r: Result[NbtTree, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn child_tag(t: &NbtTree, parent: Int, name: Str) -> Int {
  return nbt_tag_type(t, nbt_find_child(t, parent, name));
}

fn child_tag_is(t: &NbtTree, parent: Int, name: Str, want: Int) -> Bool {
  return child_tag(t, parent, name) == want;
}

fn child_byte_eq(t: &NbtTree, parent: Int, name: Str, want: Int) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_byte(t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn child_short_eq(t: &NbtTree, parent: Int, name: Str, want: Int) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_short(t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn child_int_eq(t: &NbtTree, parent: Int, name: Str, want: Int) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_int(t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn child_long_eq(t: &NbtTree, parent: Int, name: Str, want: Int) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_long(t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn child_float_bits_eq(t: &NbtTree, parent: Int, name: Str, want: Int) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_float_bits(t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn child_double_bits_eq(t: &NbtTree, parent: Int, name: Str, want: Int) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_double_bits(t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn child_str_eq(t: &NbtTree, parent: Int, name: Str, want: Str) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_str(t, ch);
  if !r.is_ok {
    return false;
  }
  return str_eq(r.value, want);
}

fn child_byte_array_eq(t: &NbtTree, parent: Int, name: Str, want: Vec[UInt8]) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_byte_array(t, ch);
  if !r.is_ok {
    return false;
  }
  return bytes_equal(r.value, want);
}

fn child_int_array_eq(t: &NbtTree, parent: Int, name: Str, want: Vec[Int]) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_int_array(t, ch);
  if !r.is_ok {
    return false;
  }
  return ints_equal(r.value, want);
}

fn child_long_array_eq(t: &NbtTree, parent: Int, name: Str, want: Vec[Int]) -> Bool {
  let ch = nbt_find_child(t, parent, name);
  if ch < 0 {
    return false;
  }
  let r = nbt_get_long_array(t, ch);
  if !r.is_ok {
    return false;
  }
  return ints_equal(r.value, want);
}

fn list_int_eq(t: &NbtTree, list_node: Int, index: Int, want: Int) -> Bool {
  let ir = nbt_list_item(t, list_node, index);
  if !ir.is_ok {
    return false;
  }
  let vr = nbt_get_int(t, ir.value);
  if !vr.is_ok {
    return false;
  }
  return vr.value == want;
}

// One-scalar round trip: build, encode, decode, read back.
fn rt_scalar(tag: Int, v: Int) -> Bool {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "r");
  if tag == 1 { nbt_add_byte(&mut tree, root, "v", v); }
  if tag == 2 { nbt_add_short(&mut tree, root, "v", v); }
  if tag == 3 { nbt_add_int(&mut tree, root, "v", v); }
  if tag == 4 { nbt_add_long(&mut tree, root, "v", v); }
  let e = nbt_encode(&mut tree);
  if !e.is_ok {
    return false;
  }
  let d = nbt_decode(e.value);
  if !d.is_ok {
    return false;
  }
  let t = d.value;
  let ch = nbt_find_child(&t, nbt_root(&t), "v");
  if ch < 0 {
    return false;
  }
  if tag == 1 {
    let r = nbt_get_byte(&t, ch);
    if !r.is_ok { return false; }
    return r.value == v;
  }
  if tag == 2 {
    let r = nbt_get_short(&t, ch);
    if !r.is_ok { return false; }
    return r.value == v;
  }
  if tag == 3 {
    let r = nbt_get_int(&t, ch);
    if !r.is_ok { return false; }
    return r.value == v;
  }
  let r = nbt_get_long(&t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == v;
}

// The TAG_Compound bytes reused by the nesting tests: root -> a -> b -> c
// (int 7) plus a root-level list l of two strings ("x", "y").
fn nested_bytes() -> Vec[UInt8] {
  var want = hb("0a0000");
  want = cat(want, hb("0a000161"));
  want = cat(want, hb("0a000162"));
  want = cat(want, hb("0300016300000007"));
  want = cat(want, hb("00"));
  want = cat(want, hb("00"));
  want = cat(want, hb("0900016c08"));
  want = cat(want, hb("00000002"));
  want = cat(want, hb("000178"));
  want = cat(want, hb("000179"));
  want = cat(want, hb("00"));
  return want;
}

// A builder tree exercising all twelve tag types (used by t9 and t13).
fn all_types_bytes() -> Vec[UInt8] {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "r");
  nbt_add_byte(&mut tree, root, "b", 5);
  nbt_add_short(&mut tree, root, "s", -300);
  nbt_add_int(&mut tree, root, "i", 70000);
  nbt_add_long(&mut tree, root, "l", 5000000000);
  nbt_add_float_bits(&mut tree, root, "f", 1069547520);
  nbt_add_double_bits(&mut tree, root, "d", 4613937818241073152);
  var barray = Vec[UInt8].new();
  barray.push(9); barray.push(8); barray.push(7);
  nbt_add_byte_array(&mut tree, root, "ba", barray);
  nbt_add_str(&mut tree, root, "st", "nbt");
  let lst = nbt_add_list(&mut tree, root, "li", 3);
  nbt_add_int(&mut tree, lst, "", 10);
  nbt_add_int(&mut tree, lst, "", 20);
  let comp = nbt_add_compound(&mut tree, root, "co");
  nbt_add_str(&mut tree, comp, "k", "v");
  nbt_add_int_array(&mut tree, root, "ia", ints2(100, -100));
  nbt_add_long_array(&mut tree, root, "la", ints2(10000000000, -10000000000));
  let e = nbt_encode(&mut tree);
  if !e.is_ok {
    return Vec[UInt8].new();
  }
  return e.value;
}

// A chain of `k` nested TAG_Compound nodes with empty names (root included).
fn deep_bytes(k: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(10 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  var i = 1;
  while i < k {
    v.push(10 as UInt8);
    v.push(0 as UInt8);
    v.push(0 as UInt8);
    i = i + 1;
  }
  i = 0;
  while i < k {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// The same chain as a builder tree.
fn deep_tree(k: Int) -> NbtTree {
  var tree = nbt_tree_new();
  var cur = nbt_add_compound(&mut tree, -1, "");
  var i = 1;
  while i < k {
    cur = nbt_add_compound(&mut tree, cur, "");
    i = i + 1;
  }
  return tree;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  let e = nbt_encode(&mut tree);
  var ok = e.is_ok;
  if ok {
    if !bytes_equal(e.value, hb("0a000000")) { ok = false; }
  }
  if nbt_node_count(&tree) != 1 { ok = false; }
  if root != 0 { ok = false; }
  let d = nbt_decode(hb("0a000000"));
  if !d.is_ok {
    ok = false;
  } else {
    let t = d.value;
    if nbt_node_count(&t) != 1 { ok = false; }
    if nbt_root(&t) != 0 { ok = false; }
    if nbt_tag_type(&t, 0) != 10 { ok = false; }
    if !str_eq(nbt_name(&t, 0), "") { ok = false; }
    if nbt_child_count(&t, 0) != 0 { ok = false; }
    if nbt_parent(&t, 0) != -1 { ok = false; }
  }
  return assert(ok, "empty root compound encodes as 0a000000 and decodes");
}

fn t2() -> TestResult {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  nbt_add_byte(&mut tree, root, "b", 127);
  nbt_add_short(&mut tree, root, "s", 4660);
  nbt_add_int(&mut tree, root, "i", 305419896);
  nbt_add_long(&mut tree, root, "l", 72623859790382856);
  let e = nbt_encode(&mut tree);
  var want = hb("0a0000");
  want = cat(want, hb("010001627f"));
  want = cat(want, hb("020001731234"));
  want = cat(want, hb("0300016912345678"));
  want = cat(want, hb("0400016c0102030405060708"));
  want = cat(want, hb("00"));
  var ok = e.is_ok;
  if ok {
    if !bytes_equal(e.value, want) { ok = false; }
  }
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    ok = false;
  } else {
    let t = d.value;
    let r = nbt_root(&t);
    if !child_byte_eq(&t, r, "b", 127) { ok = false; }
    if !child_short_eq(&t, r, "s", 4660) { ok = false; }
    if !child_int_eq(&t, r, "i", 305419896) { ok = false; }
    if !child_long_eq(&t, r, "l", 72623859790382856) { ok = false; }
  }
  return assert(ok, "byte/short/int/long payloads: exact big-endian bytes");
}

fn t3() -> TestResult {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  nbt_add_byte(&mut tree, root, "b", -128);
  nbt_add_short(&mut tree, root, "s", -2);
  nbt_add_int(&mut tree, root, "i", -1);
  nbt_add_long(&mut tree, root, "l", 0 - 9223372036854775807 - 1);
  let e = nbt_encode(&mut tree);
  var want = hb("0a0000");
  want = cat(want, hb("0100016280"));
  want = cat(want, hb("02000173fffe"));
  want = cat(want, hb("03000169ffffffff"));
  want = cat(want, hb("0400016c8000000000000000"));
  want = cat(want, hb("00"));
  var ok = e.is_ok;
  if ok {
    if !bytes_equal(e.value, want) { ok = false; }
  }
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    ok = false;
  } else {
    let t = d.value;
    let r = nbt_root(&t);
    if !child_byte_eq(&t, r, "b", -128) { ok = false; }
    if !child_short_eq(&t, r, "s", -2) { ok = false; }
    if !child_int_eq(&t, r, "i", -1) { ok = false; }
    if !child_long_eq(&t, r, "l", 0 - 9223372036854775807 - 1) { ok = false; }
  }
  return assert(ok, "negative scalars: two's-complement big-endian bytes");
}

fn t4() -> TestResult {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  nbt_add_float_bits(&mut tree, root, "f", 1065353216);
  nbt_add_double_bits(&mut tree, root, "d", 4607182418800017408);
  nbt_add_double_bits(&mut tree, root, "n", 0 - 9223372036854775807 - 1);
  let e = nbt_encode(&mut tree);
  var want = hb("0a0000");
  want = cat(want, hb("050001663f800000"));
  want = cat(want, hb("060001643ff0000000000000"));
  want = cat(want, hb("0600016e8000000000000000"));
  want = cat(want, hb("00"));
  var ok = e.is_ok;
  if ok {
    if !bytes_equal(e.value, want) { ok = false; }
  }
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    ok = false;
  } else {
    let t = d.value;
    let r = nbt_root(&t);
    if !child_float_bits_eq(&t, r, "f", 1065353216) { ok = false; }
    if !child_double_bits_eq(&t, r, "d", 4607182418800017408) { ok = false; }
    if !child_double_bits_eq(&t, r, "n", 0 - 9223372036854775807 - 1) { ok = false; }
  }
  return assert(ok, "float/double tags: raw IEEE-754 bit patterns");
}

fn t5() -> TestResult {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  nbt_add_str(&mut tree, root, "a", "");
  nbt_add_str(&mut tree, root, "b", "abc");
  nbt_add_str(&mut tree, root, "c", "héllo");
  nbt_add_str(&mut tree, root, "é", "v");
  let e = nbt_encode(&mut tree);
  var want = hb("0a0000");
  want = cat(want, hb("080001610000"));
  want = cat(want, hb("080001620003616263"));
  want = cat(want, hb("08000163000668c3a96c6c6f"));
  want = cat(want, hb("080002c3a9000176"));
  want = cat(want, hb("00"));
  var ok = e.is_ok;
  if ok {
    if !bytes_equal(e.value, want) { ok = false; }
  }
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    ok = false;
  } else {
    let t = d.value;
    let r = nbt_root(&t);
    if !child_str_eq(&t, r, "a", "") { ok = false; }
    if !child_str_eq(&t, r, "b", "abc") { ok = false; }
    if !child_str_eq(&t, r, "c", "héllo") { ok = false; }
    let ch = nbt_find_child(&t, r, "é");
    if ch < 0 { ok = false; }
    if !str_eq(nbt_name(&t, ch), "é") { ok = false; }
    if !child_str_eq(&t, r, "é", "v") { ok = false; }
  }
  return assert(ok, "strings: u16 length prefix, UTF-8 bytes, UTF-8 names");
}

fn t6() -> TestResult {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  var b1 = Vec[UInt8].new();
  b1.push(1); b1.push(128); b1.push(255);
  nbt_add_byte_array(&mut tree, root, "B", b1);
  nbt_add_int_array(&mut tree, root, "I", ints3(1, -1, 2147483647));
  nbt_add_long_array(&mut tree, root, "L", ints2(1, -1));
  let e = nbt_encode(&mut tree);
  var want = hb("0a0000");
  want = cat(want, hb("07000142000000030180ff"));
  want = cat(want, hb("0b0001490000000300000001ffffffff7fffffff"));
  want = cat(want, hb("0c00014c000000020000000000000001ffffffffffffffff"));
  want = cat(want, hb("00"));
  var ok = e.is_ok;
  if ok {
    if !bytes_equal(e.value, want) { ok = false; }
  }
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    ok = false;
  } else {
    let t = d.value;
    let r = nbt_root(&t);
    if !child_byte_array_eq(&t, r, "B", hb("0180ff")) { ok = false; }
    if !child_int_array_eq(&t, r, "I", ints3(1, -1, 2147483647)) { ok = false; }
    if !child_long_array_eq(&t, r, "L", ints2(1, -1)) { ok = false; }
  }
  return assert(ok, "byte/int/long arrays: length prefix and exact payloads");
}

fn t7() -> TestResult {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  let lst = nbt_add_list(&mut tree, root, "l", 3);
  nbt_add_int(&mut tree, lst, "", 1);
  nbt_add_int(&mut tree, lst, "", 2);
  nbt_add_int(&mut tree, lst, "", 3);
  nbt_add_list(&mut tree, root, "e", 0);
  let e = nbt_encode(&mut tree);
  var want = hb("0a0000");
  want = cat(want, hb("0900016c0300000003000000010000000200000003"));
  want = cat(want, hb("090001650000000000"));
  want = cat(want, hb("00"));
  var ok = e.is_ok;
  if ok {
    if !bytes_equal(e.value, want) { ok = false; }
  }
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    ok = false;
  } else {
    let t = d.value;
    let r = nbt_root(&t);
    if !child_tag_is(&t, r, "l", 9) { ok = false; }
    let l = nbt_find_child(&t, r, "l");
    let ll = nbt_list_len(&t, l);
    if !ll.is_ok { ok = false; }
    elif ll.value != 3 { ok = false; }
    let lt = nbt_list_element_type(&t, l);
    if !lt.is_ok { ok = false; }
    elif lt.value != 3 { ok = false; }
    if !list_int_eq(&t, l, 0, 1) { ok = false; }
    if !list_int_eq(&t, l, 2, 3) { ok = false; }
    if !err_int_is(nbt_list_item(&t, l, 3), "nbt: list index out of range") { ok = false; }
    let el = nbt_find_child(&t, r, "e");
    let e0 = nbt_list_len(&t, el);
    if !e0.is_ok { ok = false; }
    elif e0.value != 0 { ok = false; }
    let et = nbt_list_element_type(&t, el);
    if !et.is_ok { ok = false; }
    elif et.value != 0 { ok = false; }
  }
  return assert(ok, "lists: element type byte, count, empty list with type 0");
}

fn t8() -> TestResult {
  let want = nested_bytes();
  var ok = true;
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    return assert(false, "nested compounds and lists: bytes and navigation");
  }
  let t = d.value;
  var tr2 = nbt_decode(clone_bytes(want));
  if !tr2.is_ok {
    ok = false;
  } else {
    var tr3 = tr2.value;
    let e2 = nbt_encode(&mut tr3);
    if !e2.is_ok { ok = false; }
    elif !bytes_equal(e2.value, want) { ok = false; }
  }
  let root = nbt_root(&t);
  if nbt_child_count(&t, root) != 2 { ok = false; }
  let a = nbt_find_child(&t, root, "a");
  if a != 1 { ok = false; }
  let b = nbt_find_child(&t, a, "b");
  if b != 2 { ok = false; }
  let c = nbt_find_child(&t, b, "c");
  if c != 3 { ok = false; }
  if !child_int_eq(&t, b, "c", 7) { ok = false; }
  let l = nbt_find_child(&t, root, "l");
  if !child_tag_is(&t, root, "l", 9) { ok = false; }
  let ll = nbt_list_len(&t, l);
  if !ll.is_ok { ok = false; }
  elif ll.value != 2 { ok = false; }
  let it0 = nbt_list_item(&t, l, 0);
  if !it0.is_ok {
    ok = false;
  } else {
    let sr = nbt_get_str(&t, it0.value);
    if !sr.is_ok { ok = false; }
    elif !str_eq(sr.value, "x") { ok = false; }
  }
  let it1 = nbt_list_item(&t, l, 1);
  if !it1.is_ok {
    ok = false;
  } else {
    let sr = nbt_get_str(&t, it1.value);
    if !sr.is_ok { ok = false; }
    elif !str_eq(sr.value, "y") { ok = false; }
  }
  return assert(ok, "nested compounds and lists: bytes, navigation, re-encode");
}

fn t9() -> TestResult {
  let raw = all_types_bytes();
  let d = nbt_decode(clone_bytes(raw));
  if !d.is_ok {
    return assert(false, "all twelve tag types round-trip through builder");
  }
  let t = d.value;
  let r = nbt_root(&t);
  var ok = child_byte_eq(&t, r, "b", 5);
  if !child_short_eq(&t, r, "s", -300) { ok = false; }
  if !child_int_eq(&t, r, "i", 70000) { ok = false; }
  if !child_long_eq(&t, r, "l", 5000000000) { ok = false; }
  if !child_float_bits_eq(&t, r, "f", 1069547520) { ok = false; }
  if !child_double_bits_eq(&t, r, "d", 4613937818241073152) { ok = false; }
  if !child_byte_array_eq(&t, r, "ba", hb("090807")) { ok = false; }
  if !child_str_eq(&t, r, "st", "nbt") { ok = false; }
  if !child_tag_is(&t, r, "li", 9) { ok = false; }
  let li = nbt_find_child(&t, r, "li");
  if !list_int_eq(&t, li, 0, 10) { ok = false; }
  if !list_int_eq(&t, li, 1, 20) { ok = false; }
  if !child_tag_is(&t, r, "co", 10) { ok = false; }
  let co = nbt_find_child(&t, r, "co");
  if !child_str_eq(&t, co, "k", "v") { ok = false; }
  if !child_int_array_eq(&t, r, "ia", ints2(100, -100)) { ok = false; }
  if !child_long_array_eq(&t, r, "la", ints2(10000000000, -10000000000)) { ok = false; }
  return assert(ok, "all twelve tag types round-trip through builder");
}

fn t10() -> TestResult {
  let raw = all_types_bytes();
  let d = nbt_decode(clone_bytes(raw));
  if !d.is_ok {
    return assert(false, "decode then re-encode is byte-exact");
  }
  var tr = d.value;
  let e2 = nbt_encode(&mut tr);
  var ok = e2.is_ok;
  if ok {
    if !bytes_equal(e2.value, raw) { ok = false; }
  }
  return assert(ok, "decode then re-encode is byte-exact");
}

fn t11() -> TestResult {
  var ok = rt_scalar(1, 127);
  if !rt_scalar(1, -128) { ok = false; }
  if !rt_scalar(2, 32767) { ok = false; }
  if !rt_scalar(2, -32768) { ok = false; }
  if !rt_scalar(3, 2147483647) { ok = false; }
  if !rt_scalar(3, -2147483648) { ok = false; }
  if !rt_scalar(4, 9223372036854775807) { ok = false; }
  if !rt_scalar(4, 0 - 9223372036854775807 - 1) { ok = false; }
  return assert(ok, "scalar round-trips at every type boundary");
}

fn t12() -> TestResult {
  let d = nbt_decode(nested_bytes());
  if !d.is_ok {
    return assert(false, "navigation accessors over the flat node store");
  }
  let t = d.value;
  var ok = nbt_node_count(&t) == 7;
  if nbt_root(&t) != 0 { ok = false; }
  if nbt_tag_type(&t, 0) != 10 { ok = false; }
  if nbt_tag_type(&t, -1) != -1 { ok = false; }
  if nbt_tag_type(&t, 99) != -1 { ok = false; }
  if nbt_child_count(&t, 0) != 2 { ok = false; }
  if nbt_child_count(&t, -1) != 0 { ok = false; }
  if nbt_child_at(&t, 0, 0) != 1 { ok = false; }
  if nbt_child_at(&t, 0, 1) != 4 { ok = false; }
  if nbt_child_at(&t, 0, 2) != -1 { ok = false; }
  if nbt_child_at(&t, 0, -1) != -1 { ok = false; }
  if nbt_find_child(&t, 0, "zzz") != -1 { ok = false; }
  if !str_eq(nbt_name(&t, 3), "c") { ok = false; }
  if !str_eq(nbt_name(&t, -1), "") { ok = false; }
  if nbt_parent(&t, 0) != -1 { ok = false; }
  if nbt_parent(&t, 1) != 0 { ok = false; }
  if nbt_parent(&t, -5) != -1 { ok = false; }
  return assert(ok, "navigation accessors over the flat node store");
}

fn t13() -> TestResult {
  let d = nbt_decode(all_types_bytes());
  if !d.is_ok {
    return assert(false, "typed readers reject the wrong tag with 0xNN text");
  }
  let t = d.value;
  let r = nbt_root(&t);
  let bn = nbt_find_child(&t, r, "b");
  let sn = nbt_find_child(&t, r, "s");
  let ino = nbt_find_child(&t, r, "i");
  let dn = nbt_find_child(&t, r, "d");
  let ian = nbt_find_child(&t, r, "ia");
  var ok = err_int_is(nbt_get_int(&t, bn), "nbt: unexpected tag type 1");
  if !err_str_is(nbt_get_str(&t, bn), "nbt: unexpected tag type 1") { ok = false; }
  if !err_int_is(nbt_get_byte(&t, ino), "nbt: unexpected tag type 3") { ok = false; }
  if !err_int_is(nbt_get_int(&t, sn), "nbt: unexpected tag type 2") { ok = false; }
  if !err_int_is(nbt_list_len(&t, ino), "nbt: unexpected tag type 3") { ok = false; }
  if !err_int_is(nbt_list_element_type(&t, ino), "nbt: unexpected tag type 3") { ok = false; }
  if !err_int_is(nbt_list_item(&t, ino, 0), "nbt: unexpected tag type 3") { ok = false; }
  if !err_int_is(nbt_get_float_bits(&t, dn), "nbt: unexpected tag type 6") { ok = false; }
  if !err_bytes_is(nbt_get_byte_array(&t, ian), "nbt: unexpected tag type 11") { ok = false; }
  if !err_int_is(nbt_get_int(&t, -1), "nbt: node index out of range") { ok = false; }
  if !err_str_is(nbt_get_str(&t, 999), "nbt: node index out of range") { ok = false; }
  return assert(ok, "typed readers reject the wrong tag with 0xNN text");
}

fn t14() -> TestResult {
  var ok = err_tree_is(nbt_decode(Vec[UInt8].new()), "nbt: truncated buffer");
  if !err_tree_is(nbt_decode(hb("0a")), "nbt: truncated buffer") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a00")), "nbt: truncated buffer") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a000001000162")), "nbt: truncated buffer") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a000003000169123456")), "nbt: truncated buffer") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a00000400016c01020304050607")), "nbt: truncated buffer") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a00000b0001490000000200000001")), "nbt: truncated buffer") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a00000c00014c0000000100000001")), "nbt: truncated buffer") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a00000900016c030000000200000001")), "nbt: truncated buffer") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a0000010001627f")), "nbt: truncated buffer") { ok = false; }
  return assert(ok, "truncated payloads and missing terminators are Err");
}

fn t15() -> TestResult {
  var ok = err_tree_is(nbt_decode(hb("0a00000800016100056162")), "nbt: string length overrun");
  if !err_tree_is(nbt_decode(hb("0a0005")), "nbt: string length overrun") { ok = false; }
  let nul_bytes = hb("0a000008000161000361006200");
  let d = nbt_decode(clone_bytes(nul_bytes));
  if !d.is_ok {
    ok = false;
  } else {
    var tr = d.value;
    let ch = nbt_find_child(&tr, nbt_root(&tr), "a");
    if ch < 0 { ok = false; }
    let sr = nbt_get_str(&tr, ch);
    if !sr.is_ok { ok = false; }
    elif !str_eq(sr.value, "a") { ok = false; }
    let e2 = nbt_encode(&mut tr);
    if !e2.is_ok { ok = false; }
    elif !bytes_equal(e2.value, nul_bytes) { ok = false; }
  }
  return assert(ok, "string length overrun; raw NUL payloads re-encode byte-exact");
}

fn t16() -> TestResult {
  var ok = err_tree_is(nbt_decode(hb("0a000007000142ffffffff")), "nbt: negative length");
  if !err_tree_is(nbt_decode(hb("0a00000b000149ffffffff")), "nbt: negative length") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a00000c00014cfffffffe")), "nbt: negative length") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a00000900016c03ffffffff")), "nbt: negative length") { ok = false; }
  return assert(ok, "negative array and list lengths are Err");
}

fn t17() -> TestResult {
  var ok = err_tree_is(nbt_decode(hb("0d000000")), "nbt: unknown tag type 13");
  if !err_tree_is(nbt_decode(hb("0a00000d00016200")), "nbt: unknown tag type 13") { ok = false; }
  if !err_tree_is(nbt_decode(hb("0a00000900016c0d00000000")), "nbt: unknown tag type 13") { ok = false; }
  return assert(ok, "unknown tag type 13 at root, in a compound and in a list");
}

fn t18() -> TestResult {
  let d64 = nbt_decode(deep_bytes(64));
  var ok = d64.is_ok;
  if ok {
    let dt = d64.value;
    if nbt_node_count(&dt) != 64 { ok = false; }
  }
  if !err_tree_is(nbt_decode(deep_bytes(65)), "nbt: depth exceeded") { ok = false; }
  var t64 = deep_tree(64);
  let e64 = nbt_encode(&mut t64);
  if !e64.is_ok { ok = false; }
  var t65 = deep_tree(65);
  if !err_bytes_is(nbt_encode(&mut t65), "nbt: depth exceeded") { ok = false; }
  return assert(ok, "nesting is capped at NBT_MAX_DEPTH (64) containers");
}

fn t19() -> TestResult {
  let ok_bytes = hb("0a00000900016c03000000010000017f00");
  let pd = nbt_decode(clone_bytes(ok_bytes));
  var ok = pd.is_ok;
  if ok {
    let pt = pd.value;
    let pl = nbt_find_child(&pt, nbt_root(&pt), "l");
    if !list_int_eq(&pt, pl, 0, 383) { ok = false; }
  }
  if !err_tree_is(nbt_decode(hb("0a00000900016c0000000001")), "nbt: list element type mismatch") { ok = false; }
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "r");
  let lst = nbt_add_list(&mut tree, root, "l", 3);
  nbt_add_byte(&mut tree, lst, "", 1);
  if !err_bytes_is(nbt_encode(&mut tree), "nbt: list element type mismatch") { ok = false; }
  return assert(ok, "list elements are payload-only; TAG_End list with items mismatches");
}

fn t20() -> TestResult {
  var ok = err_tree_is(nbt_decode(hb("03000000000001")), "nbt: root tag is not a compound");
  if !err_tree_is(nbt_decode(hb("00000000")), "nbt: unknown tag type 0") { ok = false; }
  var tree = nbt_tree_new();
  nbt_add_int(&mut tree, -1, "", 1);
  if !err_bytes_is(nbt_encode(&mut tree), "nbt: root tag is not a compound") { ok = false; }
  if !err_bytes_is(nbt_encode(&mut nbt_tree_new()), "nbt: empty tree") { ok = false; }
  return assert(ok, "root tag must be a compound; an empty tree cannot encode");
}

fn t21() -> TestResult {
  var want = hb("0a0000");
  want = cat(want, hb("080001730000"));
  want = cat(want, hb("0700016200000000"));
  want = cat(want, hb("0b00016900000000"));
  want = cat(want, hb("0c00016c00000000"));
  want = cat(want, hb("090001650300000000"));
  want = cat(want, hb("0a00016300"));
  want = cat(want, hb("00"));
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    return assert(false, "empty strings, arrays, lists and compounds");
  }
  var tr = d.value;
  let r = nbt_root(&tr);
  var ok = child_str_eq(&tr, r, "s", "");
  if !child_byte_array_eq(&tr, r, "b", Vec[UInt8].new()) { ok = false; }
  if !child_int_array_eq(&tr, r, "i", Vec[Int].new()) { ok = false; }
  if !child_long_array_eq(&tr, r, "l", Vec[Int].new()) { ok = false; }
  let e = nbt_find_child(&tr, r, "e");
  let el = nbt_list_len(&tr, e);
  if !el.is_ok { ok = false; }
  elif el.value != 0 { ok = false; }
  if nbt_child_count(&tr, nbt_find_child(&tr, r, "c")) != 0 { ok = false; }
  let e2 = nbt_encode(&mut tr);
  if !e2.is_ok { ok = false; }
  elif !bytes_equal(e2.value, want) { ok = false; }
  return assert(ok, "empty strings, arrays, lists and compounds");
}

fn t22() -> TestResult {
  var want = hb("0a0000");
  want = cat(want, hb("0a000161"));
  want = cat(want, hb("090001620a00000002"));
  want = cat(want, hb("030001760000000100"));
  want = cat(want, hb("030001760000000200"));
  want = cat(want, hb("00"));
  want = cat(want, hb("00"));
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    return assert(false, "list of compounds: element payloads carry no names");
  }
  var tr = d.value;
  let r = nbt_root(&tr);
  let a = nbt_find_child(&tr, r, "a");
  let b = nbt_find_child(&tr, a, "b");
  let bl = nbt_list_len(&tr, b);
  var ok = bl.is_ok && bl.value == 2;
  let bt = nbt_list_element_type(&tr, b);
  if !bt.is_ok { ok = false; }
  elif bt.value != 10 { ok = false; }
  let it0 = nbt_list_item(&tr, b, 0);
  if !it0.is_ok {
    ok = false;
  } else {
    if nbt_tag_type(&tr, it0.value) != 10 { ok = false; }
    if !child_int_eq(&tr, it0.value, "v", 1) { ok = false; }
  }
  let it1 = nbt_list_item(&tr, b, 1);
  if !it1.is_ok {
    ok = false;
  } else {
    if !child_int_eq(&tr, it1.value, "v", 2) { ok = false; }
  }
  let e2 = nbt_encode(&mut tr);
  if !e2.is_ok { ok = false; }
  elif !bytes_equal(e2.value, want) { ok = false; }
  return assert(ok, "list of compounds: element payloads carry no names");
}

fn t23() -> TestResult {
  var want = hb("0a0000");
  want = cat(want, hb("0100046279746501"));
  want = cat(want, hb("0800046e616d65000942616e616e72616d61"));
  want = cat(want, hb("00"));
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    return assert(false, "classic hello NBT document (byte + string)");
  }
  var tr = d.value;
  let r = nbt_root(&tr);
  var ok = child_byte_eq(&tr, r, "byte", 1);
  if !child_str_eq(&tr, r, "name", "Bananrama") { ok = false; }
  let e2 = nbt_encode(&mut tr);
  if !e2.is_ok { ok = false; }
  elif !bytes_equal(e2.value, want) { ok = false; }
  return assert(ok, "classic hello NBT document (byte + string)");
}

fn t24() -> TestResult {
  let s65535 = string.str_repeat("x", 65535);
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  nbt_add_str(&mut tree, root, "s", s65535);
  let e = nbt_encode(&mut tree);
  var ok = e.is_ok;
  var raw = Vec[UInt8].new();
  if ok {
    raw = clone_bytes(e.value);
    if raw.len() != 65545 { ok = false; }
  }
  let d = nbt_decode(clone_bytes(raw));
  if !d.is_ok {
    ok = false;
  } else {
    var tr = d.value;
    let ch = nbt_find_child(&tr, nbt_root(&tr), "s");
    if ch < 0 {
      ok = false;
    } else {
      let sr = nbt_get_str(&tr, ch);
      if !sr.is_ok {
        ok = false;
      } else {
        if string.str_len(sr.value) != 65535 { ok = false; }
        if ((string.byte_at(sr.value, 0) as Int) & 0xFF) != 120 { ok = false; }
        if ((string.byte_at(sr.value, 65534) as Int) & 0xFF) != 120 { ok = false; }
      }
    }
  }
  let too_long = string.str_repeat("y", 65536);
  var tree2 = nbt_tree_new();
  let root2 = nbt_add_compound(&mut tree2, -1, "");
  nbt_add_str(&mut tree2, root2, "s", too_long);
  if !err_bytes_is(nbt_encode(&mut tree2), "nbt: string length overrun") { ok = false; }
  return assert(ok, "string byte length 65535 round-trips; 65536 is rejected");
}

fn t25() -> TestResult {
  var want = hb("0a0000");
  want = cat(want, hb("070001420000000280ff"));
  want = cat(want, hb("0b00014900000002800000007fffffff"));
  want = cat(want, hb("0c00014c0000000280000000000000007fffffffffffffff"));
  want = cat(want, hb("00"));
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    return assert(false, "high-bit array payloads decode signed without sign bleed");
  }
  let t = d.value;
  let r = nbt_root(&t);
  var ok = child_byte_array_eq(&t, r, "B", hb("80ff"));
  if !child_int_array_eq(&t, r, "I", ints2(-2147483648, 2147483647)) { ok = false; }
  if !child_long_array_eq(&t, r, "L", ints2(0 - 9223372036854775807 - 1, 9223372036854775807)) { ok = false; }
  return assert(ok, "high-bit array payloads decode signed without sign bleed");
}

fn t26() -> TestResult {
  var tree = nbt_tree_new();
  let root = nbt_add_compound(&mut tree, -1, "");
  nbt_add_float_bits(&mut tree, root, "f", 4294967295);
  nbt_add_double_bits(&mut tree, root, "d", -1);
  nbt_add_float_bits(&mut tree, root, "g", 0);
  nbt_add_double_bits(&mut tree, root, "h", 4607182418800017408);
  let e = nbt_encode(&mut tree);
  var want = hb("0a0000");
  want = cat(want, hb("05000166ffffffff"));
  want = cat(want, hb("06000164ffffffffffffffff"));
  want = cat(want, hb("0500016700000000"));
  want = cat(want, hb("060001683ff0000000000000"));
  want = cat(want, hb("00"));
  var ok = e.is_ok;
  if ok {
    if !bytes_equal(e.value, want) { ok = false; }
  }
  let d = nbt_decode(clone_bytes(want));
  if !d.is_ok {
    ok = false;
  } else {
    let t = d.value;
    let r = nbt_root(&t);
    if !child_float_bits_eq(&t, r, "f", 4294967295) { ok = false; }
    if !child_double_bits_eq(&t, r, "d", -1) { ok = false; }
    if !child_float_bits_eq(&t, r, "g", 0) { ok = false; }
    if !child_double_bits_eq(&t, r, "h", 4607182418800017408) { ok = false; }
  }
  return assert(ok, "float/double bit patterns with bit 31/63 set re-encode exactly");
}

fn main() -> Int {
  io.println("=== xiom.nbt conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.nbt: all tests passed");
  } else {
    io.println("xiom.nbt: tests failed");
  }
  return failed;
}
