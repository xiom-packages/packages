// XIOM -- xiom.snbt conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: compounds with bare and quoted keys, nested
// compounds, heterogeneous lists, typed arrays, quoted/bare strings and
// escapes, every number form, canonical emission and round-trip stability,
// the depth cap, accessor behaviour and the full error catalog (unbalanced
// braces/brackets, missing colon, bad key, bad escape, unterminated string,
// invalid number, bad number suffix, integer out of range, mixed typed
// array, trailing tokens, empty input, depth exceeded).
//
// Str payloads and keys are compared with str_compare only (BUG 17
// discipline: `==` on Str values read from a Vec lowers to a pointer
// comparison, and str_len on such values is not trusted); Vec[Int] element
// reads are bound to typed locals.

module snbt_tests
use xiom.io; use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.snbt;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_tree_is(r: Result[SnbtTree, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
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

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn parse_ok(input: Str) -> Bool {
  let pr = snbt_parse(input);
  return pr.is_ok;
}

// Canonical text of `input`, or a sentinel on any parse/emit failure.
fn emit_of(input: Str) -> Str {
  let pr = snbt_parse(input);
  if !pr.is_ok {
    return "<parse-error>";
  }
  let t = pr.value;
  let er = snbt_emit(&t);
  if !er.is_ok {
    return "<emit-error>";
  }
  return er.value;
}

fn root_of(input: Str) -> Int {
  let pr = snbt_parse(input);
  if !pr.is_ok {
    return -2;
  }
  let t = pr.value;
  return snbt_root(&t);
}

fn root_kind(input: Str) -> Int {
  let pr = snbt_parse(input);
  if !pr.is_ok {
    return -2;
  }
  let t = pr.value;
  return snbt_kind(&t, snbt_root(&t));
}

fn root_kind_is(input: Str, want: Int) -> Bool {
  return root_kind(input) == want;
}

fn root_kind_name_is(input: Str, want: Str) -> Bool {
  return str_eq(snbt_kind_name(root_kind(input)), want);
}

fn find(t: &SnbtTree, key: Str) -> Int {
  return snbt_find_child(t, snbt_root(t), key);
}

fn key_kind(t: &SnbtTree, key: Str) -> Int {
  return snbt_kind(t, find(t, key));
}

fn key_kind_is(t: &SnbtTree, key: Str, want: Int) -> Bool {
  return key_kind(t, key) == want;
}

fn key_text_is(t: &SnbtTree, key: Str, want: Str) -> Bool {
  let ch = find(t, key);
  if ch < 0 {
    return false;
  }
  return str_eq(snbt_text(t, ch), want);
}

fn key_int_is(t: &SnbtTree, key: Str, want: Int) -> Bool {
  let ch = find(t, key);
  if ch < 0 {
    return false;
  }
  let r = snbt_get_integer(t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn key_bool_is(t: &SnbtTree, key: Str, want: Bool) -> Bool {
  let ch = find(t, key);
  if ch < 0 {
    return false;
  }
  let r = snbt_get_bool(t, ch);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

// Element `index` of the list under `key` as an integer.
fn list_int_is(t: &SnbtTree, key: Str, index: Int, want: Int) -> Bool {
  let l = find(t, key);
  if l < 0 {
    return false;
  }
  let ir = snbt_list_item(t, l, index);
  if !ir.is_ok {
    return false;
  }
  let v = snbt_get_integer(t, ir.value);
  if !v.is_ok {
    return false;
  }
  return v.value == want;
}

// Element `index` of the typed array under `key` as an integer.
fn array_int_is(t: &SnbtTree, key: Str, index: Int, want: Int) -> Bool {
  let a = find(t, key);
  if a < 0 {
    return false;
  }
  let ch = snbt_child_at(t, a, index);
  if ch < 0 {
    return false;
  }
  let v = snbt_get_integer(t, ch);
  if !v.is_ok {
    return false;
  }
  return v.value == want;
}

fn list_len_is(t: &SnbtTree, key: Str, want: Int) -> Bool {
  let l = find(t, key);
  if l < 0 {
    return false;
  }
  let r = snbt_list_count(t, l);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn array_len_is(t: &SnbtTree, key: Str, want: Int) -> Bool {
  let a = find(t, key);
  if a < 0 {
    return false;
  }
  let r = snbt_array_count(t, a);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn nest_lists(n: Int) -> Str {
  var s = "";
  var i = 0;
  while i < n {
    s = s + "[";
    i = i + 1;
  }
  i = 0;
  while i < n {
    s = s + "]";
    i = i + 1;
  }
  return s;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let src = "{name:\"Bananrama\",byte:1b,short:2s,int:3,long:4L,ok:true,no:false,flt:1.5f,dbl:2.5d}";
  let pr = snbt_parse(src);
  if !pr.is_ok {
    return assert(false, "flat compound: kinds, values and readers");
  }
  let t = pr.value;
  let r = snbt_root(&t);
  var ok = snbt_kind(&t, r) == SNBT_KIND_COMPOUND;
  if snbt_node_count(&t) != 10 { ok = false; }
  if !key_kind_is(&t, "name", SNBT_KIND_STRING) { ok = false; }
  if !key_text_is(&t, "name", "Bananrama") { ok = false; }
  if !key_kind_is(&t, "byte", SNBT_KIND_BYTE) { ok = false; }
  if !key_int_is(&t, "byte", 1) { ok = false; }
  if !key_kind_is(&t, "short", SNBT_KIND_SHORT) { ok = false; }
  if !key_int_is(&t, "short", 2) { ok = false; }
  if !key_kind_is(&t, "int", SNBT_KIND_INT) { ok = false; }
  if !key_int_is(&t, "int", 3) { ok = false; }
  if !key_kind_is(&t, "long", SNBT_KIND_LONG) { ok = false; }
  if !key_int_is(&t, "long", 4) { ok = false; }
  if !key_bool_is(&t, "ok", true) { ok = false; }
  if !key_bool_is(&t, "no", false) { ok = false; }
  if !key_kind_is(&t, "flt", SNBT_KIND_FLOAT) { ok = false; }
  if !key_text_is(&t, "flt", "1.5") { ok = false; }
  if !key_kind_is(&t, "dbl", SNBT_KIND_DOUBLE) { ok = false; }
  if !key_text_is(&t, "dbl", "2.5") { ok = false; }
  if snbt_parent(&t, find(&t, "name")) != r { ok = false; }
  if !str_eq(snbt_key(&t, find(&t, "byte")), "byte") { ok = false; }
  return assert(ok, "flat compound: kinds, values and readers");
}

fn t2() -> TestResult {
  let pr = snbt_parse("{a:{b:[1,2,3]},c:[{x:1},{y:2}]}");
  if !pr.is_ok {
    return assert(false, "nested compound/list navigation");
  }
  let t = pr.value;
  let r = snbt_root(&t);
  var ok = snbt_node_count(&t) == 11;
  let a = find(&t, "a");
  if snbt_kind(&t, a) != SNBT_KIND_COMPOUND { ok = false; }
  let b = snbt_find_child(&t, a, "b");
  if snbt_kind(&t, b) != SNBT_KIND_LIST { ok = false; }
  if !list_len_is(&t, "c", 2) { ok = false; }
  let c = find(&t, "c");
  let i0 = snbt_list_item(&t, c, 0);
  if !i0.is_ok { ok = false; } else {
    let obj = i0.value;
    if snbt_kind(&t, obj) != SNBT_KIND_COMPOUND { ok = false; }
    let x = snbt_find_child(&t, obj, "x");
    let xv = snbt_get_int(&t, x);
    if !xv.is_ok { ok = false; } else {
      if xv.value != 1 { ok = false; }
    }
  }
  if !str_eq(snbt_kind_name(snbt_kind(&t, r)), "compound") { ok = false; }
  return assert(ok, "nested compound/list navigation");
}

fn t3() -> TestResult {
  var ok = root_kind_is("{}", SNBT_KIND_COMPOUND);
  if !str_eq(emit_of("{}"), "{}") { ok = false; }
  if !root_kind_is("[]", SNBT_KIND_LIST) { ok = false; }
  if !str_eq(emit_of("[]"), "[]") { ok = false; }
  if !root_kind_is("[B;]", SNBT_KIND_BYTE_ARRAY) { ok = false; }
  if !str_eq(emit_of("[B;]"), "[B;]") { ok = false; }
  if !root_kind_is("[I;]", SNBT_KIND_INT_ARRAY) { ok = false; }
  if !str_eq(emit_of("[I;]"), "[I;]") { ok = false; }
  if !root_kind_is("[L;]", SNBT_KIND_LONG_ARRAY) { ok = false; }
  if !str_eq(emit_of("[L;]"), "[L;]") { ok = false; }
  let pr = snbt_parse("[B;]");
  if !pr.is_ok { return assert(false, "empty containers and empty typed arrays"); }
  let t = pr.value;
  let r = snbt_root(&t);
  let ac = snbt_array_count(&t, r);
  if !ac.is_ok { ok = false; } else {
    if ac.value != 0 { ok = false; }
  }
  let ak = snbt_array_element_kind(&t, r);
  if !ak.is_ok { ok = false; } else {
    if ak.value != SNBT_KIND_BYTE { ok = false; }
  }
  return assert(ok, "empty containers and empty typed arrays");
}

fn t4() -> TestResult {
  let pr = snbt_parse("{ \"a b\" : 1 , 'c' : 2 }");
  if !pr.is_ok {
    return assert(false, "quoted keys and canonical key emission");
  }
  let t = pr.value;
  var ok = key_int_is(&t, "a b", 1);
  if !key_int_is(&t, "c", 2) { ok = false; }
  if !str_eq(emit_of("{ \"a b\" : 1 , 'c' : 2 }"), "{\"a b\":1,c:2}") { ok = false; }
  if !str_eq(emit_of("{\"a\\\"b\":1}"), "{\"a\\\"b\":1}") { ok = false; }
  return assert(ok, "quoted keys and canonical key emission");
}

fn t5() -> TestResult {
  let src = "{s:\"a\\nb\\t\\\"c\\\\d\\'e\"}";
  let pr = snbt_parse(src);
  if !pr.is_ok {
    return assert(false, "string escapes decode and re-emit canonically");
  }
  let t = pr.value;
  var ok = key_text_is(&t, "s", "a\nb\t\"c\\d'e");
  if !str_eq(emit_of(src), "{s:\"a\\nb\\t\\\"c\\\\d'e\"}") { ok = false; }
  return assert(ok, "string escapes decode and re-emit canonically");
}

fn t6() -> TestResult {
  let pr = snbt_parse("{a:'x',b:'he said \"hi\"',c:\"single ' quote\",d:'it\\'s'}");
  if !pr.is_ok {
    return assert(false, "single-quoted strings");
  }
  let t = pr.value;
  var ok = key_text_is(&t, "a", "x");
  if !key_text_is(&t, "b", "he said \"hi\"") { ok = false; }
  if !key_text_is(&t, "c", "single ' quote") { ok = false; }
  if !key_text_is(&t, "d", "it's") { ok = false; }
  if !str_eq(emit_of("{a:'x',b:'he said \"hi\"',c:\"single ' quote\",d:'it\\'s'}"), "{a:\"x\",b:\"he said \\\"hi\\\"\",c:\"single ' quote\",d:\"it's\"}") { ok = false; }
  return assert(ok, "single-quoted strings");
}

fn t7() -> TestResult {
  let src = "[B;1b,-2b,127b,-128b]";
  let pr = snbt_parse(src);
  if !pr.is_ok {
    return assert(false, "typed arrays validate and round-trip");
  }
  let t = pr.value;
  let r = snbt_root(&t);
  var ok = snbt_kind(&t, r) == SNBT_KIND_BYTE_ARRAY;
  let bc = snbt_array_count(&t, r);
  if !bc.is_ok { ok = false; } else {
    if bc.value != 4 { ok = false; }
  }
  let bk = snbt_array_element_kind(&t, r);
  if !bk.is_ok { ok = false; } else {
    if bk.value != SNBT_KIND_BYTE { ok = false; }
  }
  let b0 = snbt_get_byte(&t, snbt_child_at(&t, r, 0));
  if !b0.is_ok { ok = false; } else {
    if b0.value != 1 { ok = false; }
  }
  let b1 = snbt_get_byte(&t, snbt_child_at(&t, r, 1));
  if !b1.is_ok { ok = false; } else {
    if b1.value != -2 { ok = false; }
  }
  let b3 = snbt_get_byte(&t, snbt_child_at(&t, r, 3));
  if !b3.is_ok { ok = false; } else {
    if b3.value != -128 { ok = false; }
  }
  let second = snbt_parse("[I;1,-2,2147483647,-2147483648]");
  if !second.is_ok { ok = false; } else {
    let t2 = second.value;
    let r2 = snbt_root(&t2);
    if snbt_kind(&t2, r2) != SNBT_KIND_INT_ARRAY { ok = false; }
    let c2 = snbt_array_count(&t2, r2);
    if !c2.is_ok { ok = false; } else {
      if c2.value != 4 { ok = false; }
    }
    let i2 = snbt_get_int(&t2, snbt_child_at(&t2, r2, 3));
    if !i2.is_ok { ok = false; } else {
      if i2.value != -2147483648 { ok = false; }
    }
  }
  if !str_eq(emit_of(src), src) { ok = false; }
  if !str_eq(emit_of("[I;1,-2,2147483647,-2147483648]"), "[I;1,-2,2147483647,-2147483648]") { ok = false; }
  if !str_eq(emit_of("[ B; 1b , 2b ]"), "[B;1b,2b]") { ok = false; }
  if !str_eq(emit_of("[L;1L,-9223372036854775807L]"), "[L;1L,-9223372036854775807L]") { ok = false; }
  return assert(ok, "typed arrays validate and round-trip");
}

fn t8() -> TestResult {
  var ok = err_tree_is(snbt_parse("[B;1,2]"), "snbt: mixed typed array");
  if !err_tree_is(snbt_parse("[I;1b]"), "snbt: mixed typed array") { ok = false; }
  if !err_tree_is(snbt_parse("[L;1]"), "snbt: mixed typed array") { ok = false; }
  if !err_tree_is(snbt_parse("[B;1b,true]"), "snbt: mixed typed array") { ok = false; }
  if !err_tree_is(snbt_parse("[I;1.5]"), "snbt: mixed typed array") { ok = false; }
  if !err_tree_is(snbt_parse("[B;{a:1}]"), "snbt: mixed typed array") { ok = false; }
  return assert(ok, "mixed typed arrays are rejected");
}

fn t9() -> TestResult {
  var ok = parse_ok("{a:1,}");
  if !str_eq(emit_of("{a:1,}"), "{a:1}") { ok = false; }
  if !str_eq(emit_of("[1,2,]"), "[1,2]") { ok = false; }
  if !str_eq(emit_of("[B;1b,]"), "[B;1b]") { ok = false; }
  if !str_eq(emit_of("{a:[1,],}"), "{a:[1]}") { ok = false; }
  return assert(ok, "a single trailing comma is accepted and canonicalized away");
}

fn t10() -> TestResult {
  var ok = err_tree_is(snbt_parse("{a:1"), "snbt: unbalanced braces");
  if !err_tree_is(snbt_parse("{a:[1,2}"), "snbt: unbalanced brackets") { ok = false; }
  if !err_tree_is(snbt_parse("[1,2"), "snbt: unbalanced brackets") { ok = false; }
  if !err_tree_is(snbt_parse("[1,2}"), "snbt: unbalanced brackets") { ok = false; }
  if !err_tree_is(snbt_parse("{} x"), "snbt: trailing tokens") { ok = false; }
  if !err_tree_is(snbt_parse("1 2"), "snbt: trailing tokens") { ok = false; }
  if !err_tree_is(snbt_parse(""), "snbt: empty input") { ok = false; }
  if !err_tree_is(snbt_parse("   "), "snbt: empty input") { ok = false; }
  if !err_tree_is(snbt_parse("}"), "snbt: unexpected character") { ok = false; }
  return assert(ok, "structural error catalog");
}

fn t11() -> TestResult {
  var ok = err_tree_is(snbt_parse("{a 1}"), "snbt: missing colon");
  if !err_tree_is(snbt_parse("{:1}"), "snbt: bad key") { ok = false; }
  if !err_tree_is(snbt_parse("{a$b:1}"), "snbt: bad key") { ok = false; }
  if !err_tree_is(snbt_parse("{a:\"x\\q\"}"), "snbt: bad escape") { ok = false; }
  if !err_tree_is(snbt_parse("{a:\"x"), "snbt: unterminated string") { ok = false; }
  if !err_tree_is(snbt_parse("{a:'x}"), "snbt: unterminated string") { ok = false; }
  return assert(ok, "key and string error catalog");
}

fn t12() -> TestResult {
  var ok = err_tree_is(snbt_parse("{a:1z}"), "snbt: bad number suffix");
  if !err_tree_is(snbt_parse("{a:1bc}"), "snbt: bad number suffix") { ok = false; }
  if !err_tree_is(snbt_parse("{a:1.5b}"), "snbt: bad number suffix") { ok = false; }
  if !err_tree_is(snbt_parse("{a:1.}"), "snbt: invalid number") { ok = false; }
  if !err_tree_is(snbt_parse("{a:1e}"), "snbt: invalid number") { ok = false; }
  if !err_tree_is(snbt_parse("{a:1e+}"), "snbt: invalid number") { ok = false; }
  if !err_tree_is(snbt_parse("{a:-}"), "snbt: invalid number") { ok = false; }
  if !err_tree_is(snbt_parse("1.2.3"), "snbt: invalid number") { ok = false; }
  if !err_tree_is(snbt_parse("{a:128b}"), "snbt: integer out of range") { ok = false; }
  if !err_tree_is(snbt_parse("{a:32768s}"), "snbt: integer out of range") { ok = false; }
  if !err_tree_is(snbt_parse("{a:2147483648}"), "snbt: integer out of range") { ok = false; }
  if !err_tree_is(snbt_parse("{a:9223372036854775808L}"), "snbt: integer out of range") { ok = false; }
  return assert(ok, "number error catalog");
}

fn t13() -> TestResult {
  let src = "{a:1,b:-42,c:0,d:007,e:1b,f:1s,g:1L,h:1f,i:1.5,j:1e3,k:1.5F,l:2.0D,m:-0,n:1.25e-2}";
  let pr = snbt_parse(src);
  if !pr.is_ok {
    return assert(false, "number forms, canonical suffixes and normalization");
  }
  let t = pr.value;
  var ok = key_kind_is(&t, "a", SNBT_KIND_INT);
  if !key_int_is(&t, "a", 1) { ok = false; }
  if !key_int_is(&t, "b", -42) { ok = false; }
  if !key_int_is(&t, "c", 0) { ok = false; }
  if !key_int_is(&t, "d", 7) { ok = false; }
  if !key_kind_is(&t, "e", SNBT_KIND_BYTE) { ok = false; }
  if !key_int_is(&t, "e", 1) { ok = false; }
  if !key_kind_is(&t, "f", SNBT_KIND_SHORT) { ok = false; }
  if !key_kind_is(&t, "g", SNBT_KIND_LONG) { ok = false; }
  if !key_kind_is(&t, "h", SNBT_KIND_FLOAT) { ok = false; }
  if !key_text_is(&t, "h", "1") { ok = false; }
  if !key_kind_is(&t, "i", SNBT_KIND_DOUBLE) { ok = false; }
  if !key_text_is(&t, "i", "1.5") { ok = false; }
  if !key_text_is(&t, "j", "1e3") { ok = false; }
  if !key_text_is(&t, "k", "1.5") { ok = false; }
  if !key_kind_is(&t, "l", SNBT_KIND_DOUBLE) { ok = false; }
  if !key_int_is(&t, "m", 0) { ok = false; }
  if !key_text_is(&t, "n", "1.25e-2") { ok = false; }
  let want = "{a:1,b:-42,c:0,d:7,e:1b,f:1s,g:1L,h:1f,i:1.5d,j:1e3d,k:1.5f,l:2.0d,m:0,n:1.25e-2d}";
  if !str_eq(emit_of(src), want) { ok = false; }
  return assert(ok, "number forms, canonical suffixes and normalization");
}

fn t14() -> TestResult {
  let src = "{a:{b:[1,2,3],\"k y\":true},c:[B;1b,2b],d:'str\\n',e:[1.5f,{f:2L}]}";
  let pr = snbt_parse(src);
  if !pr.is_ok {
    return assert(false, "canonical emit is stable under re-parse");
  }
  let t1 = pr.value;
  let e1r = snbt_emit(&t1);
  if !e1r.is_ok {
    return assert(false, "canonical emit is stable under re-parse");
  }
  let e1 = e1r.value;
  let pr2 = snbt_parse(e1);
  var ok = pr2.is_ok;
  if ok {
    let t2 = pr2.value;
    if snbt_node_count(&t2) != snbt_node_count(&t1) { ok = false; }
    let e2r = snbt_emit(&t2);
    if !e2r.is_ok { ok = false; } else {
      if !str_eq(e1, e2r.value) { ok = false; }
    }
    if !key_text_is(&t2, "d", "str\n") { ok = false; }
    if !array_int_is(&t2, "c", 0, 1) { ok = false; }
  }
  return assert(ok, "canonical emit is stable under re-parse");
}

fn t15() -> TestResult {
  var ok = root_kind_is("1", SNBT_KIND_INT);
  if !root_kind_is("true", SNBT_KIND_BOOLEAN) { ok = false; }
  if !root_kind_is("\"s\"", SNBT_KIND_STRING) { ok = false; }
  if !root_kind_is("1b", SNBT_KIND_BYTE) { ok = false; }
  if !root_kind_is("1s", SNBT_KIND_SHORT) { ok = false; }
  if !root_kind_is("1L", SNBT_KIND_LONG) { ok = false; }
  if !root_kind_is("1.5", SNBT_KIND_DOUBLE) { ok = false; }
  if !root_kind_is("1f", SNBT_KIND_FLOAT) { ok = false; }
  if !root_kind_is("{a:1}", SNBT_KIND_COMPOUND) { ok = false; }
  if !root_kind_is("[1]", SNBT_KIND_LIST) { ok = false; }
  if !root_kind_is("[B;1b]", SNBT_KIND_BYTE_ARRAY) { ok = false; }
  if !root_kind_is("[I;1]", SNBT_KIND_INT_ARRAY) { ok = false; }
  if !root_kind_is("[L;1L]", SNBT_KIND_LONG_ARRAY) { ok = false; }
  if !root_kind_name_is("\"s\"", "string") { ok = false; }
  if !root_kind_name_is("1", "int") { ok = false; }
  if !root_kind_name_is("[L;1L]", "long_array") { ok = false; }
  var ok2 = root_kind_name_is("true", "boolean");
  if !root_kind_name_is("1b", "byte") { ok2 = false; }
  if !root_kind_name_is("1s", "short") { ok2 = false; }
  if !root_kind_name_is("1L", "long") { ok2 = false; }
  if !root_kind_name_is("1.5", "double") { ok2 = false; }
  if !root_kind_name_is("1f", "float") { ok2 = false; }
  if !root_kind_name_is("[1]", "list") { ok2 = false; }
  if !root_kind_name_is("[B;1b]", "byte_array") { ok2 = false; }
  if !root_kind_name_is("[I;1]", "int_array") { ok2 = false; }
  if !root_kind_name_is("{a:1}", "compound") { ok2 = false; }
  if !str_eq(snbt_kind_name(99), "") { ok2 = false; }
  return assert(ok && ok2, "every node kind is reachable at the root");
}

fn t16() -> TestResult {
  var ok = parse_ok(nest_lists(64));
  if !err_tree_is(snbt_parse(nest_lists(65)), "snbt: depth exceeded") { ok = false; }
  if !err_tree_is(snbt_parse("[B;" + nest_lists(64)), "snbt: depth exceeded") { ok = false; }
  return assert(ok, "container depth cap is exactly 64");
}

fn t17() -> TestResult {
  let pr = snbt_parse("{a:1,b:1b,l:[1,2],s:\"x\"}");
  if !pr.is_ok {
    return assert(false, "accessor and reader error behaviour");
  }
  let t = pr.value;
  let r = snbt_root(&t);
  var ok = snbt_find_child(&t, r, "missing") == -1;
  if snbt_child_at(&t, r, 99) != -1 { ok = false; }
  if snbt_kind(&t, -5) != -1 { ok = false; }
  if !str_eq(snbt_text(&t, 999), "") { ok = false; }
  if snbt_parent(&t, r) != -1 { ok = false; }
  let l = find(&t, "l");
  if !err_int_is(snbt_list_item(&t, l, 5), "snbt: list index out of range") { ok = false; }
  if !err_int_is(snbt_list_count(&t, r), "snbt: unexpected kind 9") { ok = false; }
  if !err_int_is(snbt_array_count(&t, l), "snbt: unexpected kind 10") { ok = false; }
  if !err_int_is(snbt_get_int(&t, find(&t, "b")), "snbt: unexpected kind 3") { ok = false; }
  if !err_int_is(snbt_get_byte(&t, find(&t, "a")), "snbt: unexpected kind 5") { ok = false; }
  if !err_int_is(snbt_get_integer(&t, find(&t, "s")), "snbt: unexpected kind 1") { ok = false; }
  if !err_int_is(snbt_get_long(&t, -1), "snbt: node index out of range") { ok = false; }
  if !err_bool_is(snbt_get_bool(&t, find(&t, "a")), "snbt: unexpected kind 5") { ok = false; }
  if !err_str_is(snbt_get_string(&t, find(&t, "a")), "snbt: unexpected kind 5") { ok = false; }
  return assert(ok, "accessor and reader error behaviour");
}

fn t18() -> TestResult {
  let pr = snbt_parse("{a:foo,b:a.b_c+d-e,c:true,d:false,e:truex,f:\"true\",g:.5}");
  if !pr.is_ok {
    return assert(false, "bare strings, booleans and the bare charset");
  }
  let t = pr.value;
  var ok = key_kind_is(&t, "a", SNBT_KIND_STRING);
  if !key_text_is(&t, "a", "foo") { ok = false; }
  if !key_text_is(&t, "b", "a.b_c+d-e") { ok = false; }
  if !key_bool_is(&t, "c", true) { ok = false; }
  if !key_bool_is(&t, "d", false) { ok = false; }
  if !key_kind_is(&t, "e", SNBT_KIND_STRING) { ok = false; }
  if !key_text_is(&t, "e", "truex") { ok = false; }
  if !key_text_is(&t, "f", "true") { ok = false; }
  if !key_text_is(&t, "g", ".5") { ok = false; }
  let want = "{a:\"foo\",b:\"a.b_c+d-e\",c:true,d:false,e:\"truex\",f:\"true\",g:\".5\"}";
  if !str_eq(emit_of("{a:foo,b:a.b_c+d-e,c:true,d:false,e:truex,f:\"true\",g:.5}"), want) { ok = false; }
  return assert(ok, "bare strings, booleans and the bare charset");
}

fn t19() -> TestResult {
  let src = "[1,\"two\",3b,true,{k:1},[1,2],[B;1b]]";
  let pr = snbt_parse(src);
  if !pr.is_ok {
    return assert(false, "heterogeneous lists are supported");
  }
  let t = pr.value;
  let r = snbt_root(&t);
  var ok = snbt_kind(&t, r) == SNBT_KIND_LIST;
  let lc = snbt_list_count(&t, r);
  if !lc.is_ok { ok = false; } else {
    if lc.value != 7 { ok = false; }
  }
  let e5 = snbt_list_item(&t, r, 5);
  if !e5.is_ok { ok = false; } else {
    if snbt_kind(&t, e5.value) != SNBT_KIND_LIST { ok = false; }
  }
  let e2 = snbt_list_item(&t, r, 2);
  if !e2.is_ok { ok = false; } else {
    let v = snbt_get_integer(&t, e2.value);
    if !v.is_ok { ok = false; } else {
      if v.value != 3 { ok = false; }
    }
  }
  if !str_eq(emit_of(src), src) { ok = false; }
  return assert(ok, "heterogeneous lists are supported");
}

fn t20() -> TestResult {
  let pr = snbt_parse("{\"\":1,a:2}");
  if !pr.is_ok {
    return assert(false, "empty quoted key and key lookup edges");
  }
  let t = pr.value;
  var ok = key_int_is(&t, "", 1);
  if !key_int_is(&t, "a", 2) { ok = false; }
  if !str_eq(emit_of("{\"\":1,a:2}"), "{\"\":1,a:2}") { ok = false; }
  if key_int_is(&t, "a.", -1) { ok = false; }
  return assert(ok, "empty quoted key and key lookup edges");
}

fn t21() -> TestResult {
  let src = "{a:127b,b:-128b,c:32767s,d:-32768s,e:2147483647,f:-2147483648,g:9223372036854775807L,h:-9223372036854775807L}";
  let pr = snbt_parse(src);
  if !pr.is_ok {
    return assert(false, "integer boundary values round-trip exactly");
  }
  let t = pr.value;
  var ok = key_int_is(&t, "a", 127);
  if !key_int_is(&t, "b", -128) { ok = false; }
  if !key_int_is(&t, "c", 32767) { ok = false; }
  if !key_int_is(&t, "d", -32768) { ok = false; }
  if !key_int_is(&t, "e", 2147483647) { ok = false; }
  if !key_int_is(&t, "f", -2147483648) { ok = false; }
  if !key_int_is(&t, "g", 9223372036854775807) { ok = false; }
  if !key_int_is(&t, "h", -9223372036854775807) { ok = false; }
  if !str_eq(emit_of(src), src) { ok = false; }
  return assert(ok, "integer boundary values round-trip exactly");
}

fn t22() -> TestResult {
  let src = "{\r\n  a : 1,\n\tb:[ 1 , 2 ]\r\n}";
  let pr = snbt_parse(src);
  if !pr.is_ok {
    return assert(false, "whitespace between tokens is tolerated");
  }
  let t = pr.value;
  var ok = key_int_is(&t, "a", 1);
  if !list_int_is(&t, "b", 1, 2) { ok = false; }
  if !str_eq(emit_of(src), "{a:1,b:[1,2]}") { ok = false; }
  return assert(ok, "whitespace between tokens is tolerated");
}

fn main() -> Int {
  io.println("=== xiom.snbt conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.snbt: all tests passed");
  } else {
    io.println("xiom.snbt: tests failed");
  }
  return failed;
}
