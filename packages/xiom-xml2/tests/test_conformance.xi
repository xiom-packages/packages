// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.xml2 conformance tests (24 checks, all fixtures inline).
//
// Covers: parse + DOM links, attributes, comments/PIs/CDATA/DOCTYPE,
// entity decoding and its strict errors, well-formedness error offsets,
// bounded depth, serializer escaping/canonical attribute order/round trips,
// namespaces (default, prefixed, scoped, unbound) and the XPath-LITE subset
// (paths, @attr, text(), [n] and [@a='v'] predicates).
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// string check below is routed through streq/text_is/name_is helpers.

module xml2_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.xml2;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Exact error text; false when the parse unexpectedly succeeded.
fn err_text(r_is_ok: Bool, err: Str, want: Str) -> Bool {
  if r_is_ok { return false; }
  return streq(err, want);
}

// Error message prefix (the parser appends " at offset N").
fn err_starts(r_is_ok: Bool, err: Str, want: Str) -> Bool {
  if r_is_ok { return false; }
  if err.len() < want.len() { return false; }
  let head = string.str_slice(err, 0, want.len());
  return streq(head, want);
}

fn root_is(d: &XmlDoc, want: Int) -> Bool {
  return xml2_root(d) == want;
}

fn name_is(d: &XmlDoc, node: Int, want: Str) -> Bool {
  return streq(xml2_name(d, node), want);
}

fn text_is(d: &XmlDoc, node: Int, want: Str) -> Bool {
  return streq(xml2_text(d, node), want);
}

fn deep_text_is(d: &XmlDoc, node: Int, want: Str) -> Bool {
  return streq(xml2_text_deep(d, node), want);
}

fn node_str_is(d: &XmlDoc, node: Int, want: Str) -> Bool {
  return streq(xml2_node_string(d, node), want);
}

fn attr_is(d: &XmlDoc, node: Int, name: Str, want: Str) -> Bool {
  let r = xml2_attr(d, node, name);
  if !r.is_ok { return false; }
  let v: Str = r.value;
  return streq(v, want);
}

fn attr_none(d: &XmlDoc, node: Int, name: Str) -> Bool {
  let r = xml2_attr(d, node, name);
  return !r.is_ok;
}

// Namespace URI of an element equals want.
fn elem_uri_is(d: &XmlDoc, node: Int, want: Str) -> Bool {
  let r = xml2_ns_element_uri(d, node);
  if !r.is_ok { return false; }
  let v: Str = r.value;
  return streq(v, want);
}

// Resolved prefix equals want.
fn ns_is(d: &XmlDoc, node: Int, prefix: Str, want: Str) -> Bool {
  let r = xml2_ns_resolve(d, node, prefix);
  if !r.is_ok { return false; }
  let v: Str = r.value;
  return streq(v, want);
}

// Evaluate and return the error message ("" when Ok).
fn xerr(d: &XmlDoc, ctx: Int, expr: Str) -> Str {
  let r = xml2_xpath_eval(d, ctx, expr);
  if r.is_ok { return ""; }
  return r.error;
}

fn count_is(d: &XmlDoc, ctx: Int, expr: Str, want: Int) -> Bool {
  return xml2_xpath_count(d, ctx, expr) == want;
}

fn first_is(d: &XmlDoc, ctx: Int, expr: Str, want: Int) -> Bool {
  return xml2_xpath_first(d, ctx, expr) == want;
}

fn xstr_is(d: &XmlDoc, ctx: Int, expr: Str, want: Str) -> Bool {
  return streq(xml2_xpath_string(d, ctx, expr), want);
}

// Match a node list [want0, want1, ...] from xml2_xpath_nodes.
fn nodes_are(d: &XmlDoc, ctx: Int, expr: Str, w0: Int, w1: Int, w2: Int) -> Bool {
  let v = xml2_xpath_nodes(d, ctx, expr);
  if v.len() != 3 { return false; }
  let a0: Int = v[0];
  let a1: Int = v[1];
  let a2: Int = v[2];
  return a0 == w0 && a1 == w1 && a2 == w2;
}

// Structural equality of two parsed documents (kinds, names, scalar strings,
// attributes) plus the root index.
fn same_doc(a: &XmlDoc, b: &XmlDoc) -> Bool {
  if xml2_node_count(a) != xml2_node_count(b) { return false; }
  var i = 0;
  while i < xml2_node_count(a) {
    if xml2_kind(a, i) != xml2_kind(b, i) { return false; }
    if !streq(xml2_name(a, i), xml2_name(b, i)) { return false; }
    if !streq(xml2_node_string(a, i), xml2_node_string(b, i)) { return false; }
    if xml2_attr_count(a, i) != xml2_attr_count(b, i) { return false; }
    var k = 0;
    while k < xml2_attr_count(a, i) {
      if !streq(xml2_attr_name_at(a, i, k), xml2_attr_name_at(b, i, k)) { return false; }
      if !streq(xml2_attr_value_at(a, i, k), xml2_attr_value_at(b, i, k)) { return false; }
      k = k + 1;
    }
    i = i + 1;
  }
  return xml2_root(a) == xml2_root(b);
}

fn nested_xml(n: Int) -> Str {
  var s = "";
  var i = 0;
  while i < n { s = s + "<d>"; i = i + 1; }
  var j = 0;
  while j < n { s = s + "</d>"; j = j + 1; }
  return s;
}

// Parse, serialize, reparse and compare canonical stability.
fn round_trips(d: &XmlDoc) -> Bool {
  let s1 = xml2_serialize(d);
  let r2 = xml2_parse(s1);
  if !r2.is_ok { return false; }
  let d2 = r2.value;
  let s2 = xml2_serialize(&d2);
  if !streq(s1, s2) { return false; }
  let r3 = xml2_parse(s2);
  if !r3.is_ok { return false; }
  let d3 = r3.value;
  return same_doc(&d2, &d3);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let res = xml2_parse("<a>hi</a>");
  if !res.is_ok { return assert(false, "single element parses"); }
  let d = res.value;
  var ok = xml2_node_count(&d) == 3;
  if !root_is(&d, 1) { ok = false; }
  if xml2_kind(&d, 0) != 0 { ok = false; }
  if xml2_kind(&d, 2) != 1 { ok = false; }
  if !name_is(&d, 1, "a") { ok = false; }
  if !text_is(&d, 1, "hi") { ok = false; }
  if xml2_parent(&d, 2) != 1 { ok = false; }
  if xml2_first_child(&d, 1) != 2 { ok = false; }
  if xml2_last_child(&d, 1) != 2 { ok = false; }
  if xml2_next_sibling(&d, 2) != -1 { ok = false; }
  if xml2_child_count(&d, 1) != 1 { ok = false; }
  if xml2_depth(&d, 1) != 1 { ok = false; }
  if xml2_depth(&d, 2) != 2 { ok = false; }
  if !node_str_is(&d, 1, "hi") { ok = false; }
  return assert(ok, "single element: root, kinds, links, text, depth");
}

fn t2() -> TestResult {
  let res = xml2_parse("<a x=\"1\" y='2' z=\"a&amp;b\"/>");
  if !res.is_ok { return assert(false, "attributes parse"); }
  let d = res.value;
  var ok = xml2_attr_count(&d, 1) == 3;
  if !attr_is(&d, 1, "x", "1") { ok = false; }
  if !attr_is(&d, 1, "y", "2") { ok = false; }
  if !attr_is(&d, 1, "z", "a&b") { ok = false; }
  if !xml2_has_attr(&d, 1, "z") { ok = false; }
  if xml2_has_attr(&d, 1, "q") { ok = false; }
  if !attr_none(&d, 1, "q") { ok = false; }
  if !streq(xml2_attr_or(&d, 1, "q", "D"), "D") { ok = false; }
  if !streq(xml2_attr_name_at(&d, 1, 0), "x") { ok = false; }
  if !streq(xml2_attr_name_at(&d, 1, 2), "z") { ok = false; }
  if !streq(xml2_attr_value_at(&d, 1, 1), "2") { ok = false; }
  if xml2_attr_count(&d, 1) != 3 { ok = false; }
  return assert(ok, "attributes: quotes, entities, accessors, defaults");
}

fn t3() -> TestResult {
  let res = xml2_parse("<r><a/><b><c/><d/></b><e/></r>");
  if !res.is_ok { return assert(false, "nested elements parse"); }
  let d = res.value;
  var ok = xml2_node_count(&d) == 7;
  if !root_is(&d, 1) { ok = false; }
  if xml2_first_child(&d, 1) != 2 { ok = false; }
  if xml2_next_sibling(&d, 2) != 3 { ok = false; }
  if xml2_next_sibling(&d, 3) != 6 { ok = false; }
  if xml2_next_sibling(&d, 6) != -1 { ok = false; }
  if xml2_last_child(&d, 1) != 6 { ok = false; }
  if xml2_first_child(&d, 3) != 4 { ok = false; }
  if xml2_next_sibling(&d, 4) != 5 { ok = false; }
  if xml2_last_child(&d, 3) != 5 { ok = false; }
  if xml2_child_count(&d, 1) != 3 { ok = false; }
  if xml2_child_count(&d, 3) != 2 { ok = false; }
  if xml2_child_at(&d, 1, 1) != 3 { ok = false; }
  if xml2_child_at(&d, 3, 1) != 5 { ok = false; }
  if xml2_child_at(&d, 1, 3) != -1 { ok = false; }
  if xml2_parent(&d, 4) != 3 { ok = false; }
  if xml2_child_by_name(&d, 3, "d") != 5 { ok = false; }
  if xml2_child_by_name(&d, 3, "z") != -1 { ok = false; }
  if xml2_depth(&d, 4) != 3 { ok = false; }
  return assert(ok, "DOM links: first/last child, next sibling, child_at, depth");
}

fn t4() -> TestResult {
  let res = xml2_parse("<p>Hello <b>world</b>!</p>");
  if !res.is_ok { return assert(false, "mixed content parses"); }
  let d = res.value;
  var ok = xml2_node_count(&d) == 6;
  if xml2_child_count(&d, 1) != 3 { ok = false; }
  if xml2_child_at(&d, 1, 0) != 2 { ok = false; }
  if xml2_child_at(&d, 1, 2) != 5 { ok = false; }
  if !text_is(&d, 1, "Hello !") { ok = false; }
  if !deep_text_is(&d, 1, "Hello world!") { ok = false; }
  if !node_str_is(&d, 3, "world") { ok = false; }
  if !text_is(&d, 3, "world") { ok = false; }
  if xml2_first_child(&d, 3) != 4 { ok = false; }
  if xml2_depth(&d, 4) != 3 { ok = false; }
  return assert(ok, "mixed content: direct vs deep text, element text");
}

fn t5() -> TestResult {
  let src = "<?xml version=\"1.0\"?><!-- top --><a><b/><!-- in --><?go now?></a><!-- end -->";
  let res = xml2_parse(src);
  if !res.is_ok { return assert(false, "PI/comment document parses"); }
  let d = res.value;
  var ok = xml2_node_count(&d) == 8;
  if !root_is(&d, 3) { ok = false; }
  if xml2_kind(&d, 1) != 4 { ok = false; }
  if xml2_kind(&d, 2) != 3 { ok = false; }
  if xml2_kind(&d, 7) != 3 { ok = false; }
  if !name_is(&d, 1, "xml") { ok = false; }
  if !node_str_is(&d, 1, "version=\"1.0\"") { ok = false; }
  if !node_str_is(&d, 2, " top ") { ok = false; }
  if !node_str_is(&d, 5, " in ") { ok = false; }
  if !name_is(&d, 6, "go") { ok = false; }
  if !node_str_is(&d, 6, "now") { ok = false; }
  if xml2_child_count(&d, 3) != 3 { ok = false; }
  if xml2_first_child(&d, 0) != 1 { ok = false; }
  if xml2_next_sibling(&d, 1) != 2 { ok = false; }
  if xml2_next_sibling(&d, 2) != 3 { ok = false; }
  if xml2_next_sibling(&d, 3) != 7 { ok = false; }
  if !streq(xml2_serialize(&d), src) { ok = false; }
  return assert(ok, "comments and PIs are nodes and round-trip verbatim");
}

fn t6() -> TestResult {
  let src = "<a><![CDATA[x<y & z]]></a>";
  let res = xml2_parse(src);
  if !res.is_ok { return assert(false, "CDATA parses"); }
  let d = res.value;
  var ok = xml2_kind(&d, 2) == 2;
  if !node_str_is(&d, 2, "x<y & z") { ok = false; }
  if !text_is(&d, 1, "x<y & z") { ok = false; }
  if !streq(xml2_serialize(&d), src) { ok = false; }
  let src2 = "<a><![CDATA[a]]]]><![CDATA[>b]]></a>";
  let res2 = xml2_parse(src2);
  if !res2.is_ok { ok = false; }
  if res2.is_ok {
    let d2 = res2.value;
    if !node_str_is(&d2, 2, "a]]") { ok = false; }
    if !node_str_is(&d2, 3, ">b") { ok = false; }
    if !text_is(&d2, 1, "a]]>b") { ok = false; }
    if !streq(xml2_serialize(&d2), src2) { ok = false; }
  }
  return assert(ok, "CDATA is raw, joins text(), and ]]&gt; splits on write");
}

fn t7() -> TestResult {
  let src = "<!DOCTYPE r SYSTEM \"r.dtd\"><r/>";
  let res = xml2_parse(src);
  if !res.is_ok { return assert(false, "SYSTEM DOCTYPE parses"); }
  let d = res.value;
  var ok = xml2_kind(&d, 1) == 5;
  if !name_is(&d, 1, "r") { ok = false; }
  if !node_str_is(&d, 1, "SYSTEM \"r.dtd\"") { ok = false; }
  if !root_is(&d, 2) { ok = false; }
  if !streq(xml2_serialize(&d), src) { ok = false; }
  let pub_src = "<!DOCTYPE r PUBLIC \"-//x//DTD y//EN\" \"y.dtd\"><r/>";
  let rp = xml2_parse(pub_src);
  if !rp.is_ok { ok = false; }
  if rp.is_ok {
    let dp = rp.value;
    if !node_str_is(&dp, 1, "PUBLIC \"-//x//DTD y//EN\" \"y.dtd\"") { ok = false; }
    if !streq(xml2_serialize(&dp), pub_src) { ok = false; }
  }
  let bare = xml2_parse("<!DOCTYPE r><r/>");
  if !bare.is_ok { ok = false; }
  if bare.is_ok {
    let db = bare.value;
    if !node_str_is(&db, 1, "") { ok = false; }
  }
  let sub = xml2_parse("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r/>");
  if !err_text(sub.is_ok, sub.error, "xml2: unsupported internal DTD subset at offset 12") { ok = false; }
  let after = xml2_parse("<r/><!DOCTYPE r>");
  if !err_text(after.is_ok, after.error, "xml2: DOCTYPE after root element at offset 16") { ok = false; }
  return assert(ok, "DOCTYPE subset: bare/SYSTEM/PUBLIC plus error cases");
}

fn t8() -> TestResult {
  let res = xml2_parse("<a t=\"&amp;&lt;&gt;&quot;&apos; &#65;&#x42;\">&#233;x</a>");
  if !res.is_ok { return assert(false, "entities decode"); }
  let d = res.value;
  var ok = attr_is(&d, 1, "t", "&<>\"' AB");
  let t = xml2_text(&d, 1);
  if t.len() != 3 { ok = false; }
  if ((string.byte_at(t, 0) as Int) & 0xFF) != 195 { ok = false; }
  if ((string.byte_at(t, 1) as Int) & 0xFF) != 169 { ok = false; }
  if ((string.byte_at(t, 2) as Int) & 0xFF) != 120 { ok = false; }
  let emoji = xml2_parse("<b>&#x1F600;</b>");
  if !emoji.is_ok { ok = false; }
  if emoji.is_ok {
    let de = emoji.value;
    let e = xml2_text(&de, 1);
    if e.len() != 4 { ok = false; }
  }
  return assert(ok, "predefined + numeric entities decode to UTF-8");
}

fn t9() -> TestResult {
  let a = xml2_parse("<a>&nope;</a>");
  var ok = err_text(a.is_ok, a.error, "xml2: unknown entity at offset 3");
  let b = xml2_parse("<a>&#xZZ;</a>");
  if !err_text(b.is_ok, b.error, "xml2: invalid character reference at offset 3") { ok = false; }
  let c = xml2_parse("<a>&amp</a>");
  if !err_text(c.is_ok, c.error, "xml2: unterminated entity at offset 3") { ok = false; }
  let e = xml2_parse("<a>&#0;</a>");
  if !err_text(e.is_ok, e.error, "xml2: invalid character reference at offset 3") { ok = false; }
  return assert(ok, "entity errors are strict with exact offsets");
}

fn t10() -> TestResult {
  let a = xml2_parse("<a><b></a>");
  var ok = err_text(a.is_ok, a.error, "xml2: mismatched closing tag at offset 10");
  let b = xml2_parse("</a>");
  if !err_text(b.is_ok, b.error, "xml2: unexpected closing tag at offset 4") { ok = false; }
  let c = xml2_parse("<a>");
  if !err_text(c.is_ok, c.error, "xml2: unclosed element at offset 3") { ok = false; }
  let e = xml2_parse("<a/><b/>");
  if !err_text(e.is_ok, e.error, "xml2: multiple root elements at offset 6") { ok = false; }
  let f = xml2_parse("x<a/>");
  if !err_text(f.is_ok, f.error, "xml2: text outside root element at offset 0") { ok = false; }
  let g = xml2_parse("<a><");
  if !err_text(g.is_ok, g.error, "xml2: unclosed tag at offset 4") { ok = false; }
  return assert(ok, "structural errors carry exact offsets");
}

fn t11() -> TestResult {
  let a = xml2_parse("<a b=\"x></a>");
  var ok = err_text(a.is_ok, a.error, "xml2: unclosed attribute value at offset 12");
  let b = xml2_parse("<a b=x/>");
  if !err_text(b.is_ok, b.error, "xml2: malformed attribute at offset 5") { ok = false; }
  let c = xml2_parse("<a b c=\"1\"/>");
  if !err_text(c.is_ok, c.error, "xml2: malformed attribute at offset 5") { ok = false; }
  let e = xml2_parse("<a b=\"1\" b=\"2\"/>");
  if !err_text(e.is_ok, e.error, "xml2: duplicate attribute at offset 10") { ok = false; }
  let f = xml2_parse("<a b=\"1\"c='2'/>");
  if !f.is_ok { ok = false; }
  if f.is_ok {
    let df = f.value;
    if !attr_is(&df, 1, "c", "2") { ok = false; }
  }
  return assert(ok, "attribute errors: unclosed value, malformed, duplicate");
}

fn t12() -> TestResult {
  let ok64 = xml2_parse(nested_xml(64));
  var ok = ok64.is_ok;
  if ok64.is_ok {
    let d = ok64.value;
    if xml2_node_count(&d) != 65 { ok = false; }
    if xml2_depth(&d, 64) != 64 { ok = false; }
    if !name_is(&d, 64, "d") { ok = false; }
  }
  let deep = xml2_parse(nested_xml(65));
  if !err_starts(deep.is_ok, deep.error, "xml2: nesting too deep at offset ") { ok = false; }
  return assert(ok, "depth 64 is accepted, 65 is rejected");
}

fn t13() -> TestResult {
  let res = xml2_parse("<r><a id=\"x1\"/><a id=\"x2\"><b>t1</b></a><a id=\"x3\"/></r>");
  if !res.is_ok { return assert(false, "xpath fixture parses"); }
  let d = res.value;
  var ok = count_is(&d, 0, "/r/a", 3);
  if !first_is(&d, 0, "/r/a", 2) { ok = false; }
  if !nodes_are(&d, 0, "/r/a", 2, 3, 6) { ok = false; }
  if !first_is(&d, 0, "/r/a[2]", 3) { ok = false; }
  if !count_is(&d, 1, "a", 3) { ok = false; }
  if !first_is(&d, 1, "a", 2) { ok = false; }
  if !xstr_is(&d, 0, "/r/a[2]/b", "t1") { ok = false; }
  if !first_is(&d, 0, "/r/a/b/text()", 5) { ok = false; }
  if !xstr_is(&d, 0, "/r/a/b/text()", "t1") { ok = false; }
  return assert(ok, "XPath-LITE: absolute/relative paths, index, text()");
}

fn t14() -> TestResult {
  let res = xml2_parse("<r><a id=\"x1\"/><a id=\"x2\"/><a id=\"x3\"/></r>");
  if !res.is_ok { return assert(false, "attr fixture parses"); }
  let d = res.value;
  let r = xml2_xpath_eval(&d, 0, "/r/a/@id");
  var ok = r.is_ok;
  if r.is_ok {
    let xr = r.value;
    if xr.kind != XML2_XPATH_KIND_ATTRS { ok = false; }
    if xr.count != 3 { ok = false; }
    let vals: Vec[Str] = xr.values;
    let owners: Vec[Int] = xr.nodes;
    if !streq(vals[0], "x1") { ok = false; }
    if !streq(vals[2], "x3") { ok = false; }
    if owners[1] != 3 { ok = false; }
  }
  if !xstr_is(&d, 0, "/r/a[2]/@id", "x2") { ok = false; }
  if xml2_xpath_nodes(&d, 0, "/r/a/@id").len() != 0 { ok = false; }
  return assert(ok, "@attr steps return values with owner nodes in lockstep");
}

// Two-element node-list check (helper for t15).
fn nodes_are_2(d: &XmlDoc, ctx: Int, expr: Str, w0: Int, w1: Int) -> Bool {
  let v = xml2_xpath_nodes(d, ctx, expr);
  if v.len() != 2 { return false; }
  let a0: Int = v[0];
  let a1: Int = v[1];
  return a0 == w0 && a1 == w1;
}

fn t15() -> TestResult {
  let res = xml2_parse("<r><g><i n=\"1\"/><i n=\"2\"/></g><g><i n=\"3\"/></g></r>");
  if !res.is_ok { return assert(false, "predicate fixture parses"); }
  let d = res.value;
  var ok = count_is(&d, 0, "/r/g/i[1]", 2);
  if !nodes_are_2(&d, 0, "/r/g/i[1]", 3, 6) { ok = false; }
  if !first_is(&d, 0, "/r/g/i[2]", 4) { ok = false; }
  if !first_is(&d, 0, "/r/g/i[@n='2']", 4) { ok = false; }
  if !first_is(&d, 0, "/r/g/i[@n=\"3\"]", 6) { ok = false; }
  if !first_is(&d, 0, "/r/g[2]/i", 6) { ok = false; }
  if !count_is(&d, 0, "/r/g/i[0]", 0) { ok = false; }
  if !count_is(&d, 0, "/r/g/i[@n='9']", 0) { ok = false; }
  return assert(ok, "predicates: [n] is per-context, [@a='v'] filters");
}

fn t16() -> TestResult {
  let res = xml2_parse("<r><g><i n=\"1\"/></g></r>");
  if !res.is_ok { return assert(false, "xpath error fixture parses"); }
  let d = res.value;
  var ok = streq(xerr(&d, 0, ""), "xml2: xpath: empty expression");
  if !streq(xerr(&d, 0, "//a"), "xml2: xpath: descendant axis '//' is not supported") { ok = false; }
  if !streq(xerr(&d, 0, "/r/"), "xml2: xpath: trailing '/'") { ok = false; }
  if !streq(xerr(&d, 0, "/r/g["), "xml2: xpath: unterminated predicate") { ok = false; }
  if !streq(xerr(&d, 0, "/r/g/i[@n=x]"), "xml2: xpath: malformed predicate") { ok = false; }
  if !streq(xerr(&d, 0, "/r/g/i[n]"), "xml2: xpath: malformed predicate") { ok = false; }
  if !streq(xerr(&d, 0, "/r/g/i/@n/x"), "xml2: xpath: attribute step must be last") { ok = false; }
  if !streq(xerr(&d, 0, "/r/g/i/@n[1]"), "xml2: xpath: predicates on attribute steps are not supported") { ok = false; }
  if !streq(xerr(&d, 0, "/r/g/nope()"), "xml2: xpath: unsupported function") { ok = false; }
  if !streq(xerr(&d, 0, "a//b"), "xml2: xpath: empty step") { ok = false; }
  let tx = xml2_parse("<r>x</r>");
  if !tx.is_ok { ok = false; }
  if tx.is_ok {
    let dt = tx.value;
    if !streq(xerr(&dt, 2, "a"), "xml2: xpath: context node is not an element") { ok = false; }
  }
  if !streq(xerr(&d, 99, "a"), "xml2: xpath: context node out of range") { ok = false; }
  return assert(ok, "XPath-LITE error catalog");
}

fn t17() -> TestResult {
  let res = xml2_parse("<r xmlns=\"urn:d\" xmlns:p=\"urn:p\"><p:a/><a/><p:b p:x=\"1\" x=\"2\"/></r>");
  if !res.is_ok { return assert(false, "namespace fixture parses"); }
  let d = res.value;
  var ok = xml2_ns_decl_count(&d, 1) == 2;
  if !streq(xml2_ns_decl_prefix_at(&d, 1, 0), "") { ok = false; }
  if !streq(xml2_ns_decl_uri_at(&d, 1, 0), "urn:d") { ok = false; }
  if !streq(xml2_ns_decl_prefix_at(&d, 1, 1), "p") { ok = false; }
  if !streq(xml2_ns_decl_uri_at(&d, 1, 1), "urn:p") { ok = false; }
  if !elem_uri_is(&d, 1, "urn:d") { ok = false; }
  if !elem_uri_is(&d, 2, "urn:p") { ok = false; }
  if !elem_uri_is(&d, 3, "urn:d") { ok = false; }
  let au = xml2_ns_attr_uri(&d, 4, "p:x");
  if !au.is_ok { ok = false; }
  if au.is_ok {
    let av: Str = au.value;
    if !streq(av, "urn:p") { ok = false; }
  }
  let au2 = xml2_ns_attr_uri(&d, 4, "x");
  if !au2.is_ok { ok = false; }
  if au2.is_ok {
    let av2: Str = au2.value;
    if !streq(av2, "") { ok = false; }
  }
  let au3 = xml2_ns_attr_uri(&d, 4, "nope");
  if au3.is_ok { ok = false; }
  if !ns_is(&d, 1, "xml", XML2_NS_XML) { ok = false; }
  let xr = xml2_ns_resolve(&d, 1, "xmlns");
  if xr.is_ok { ok = false; }
  if !streq(xr.error, "xml2: reserved namespace prefix") { ok = false; }
  return assert(ok, "namespaces: declarations, default and prefixed resolution");
}

fn t18() -> TestResult {
  let res = xml2_parse("<r xmlns:p=\"urn:1\"><c xmlns:p=\"urn:2\"><p:d/></c><p:e/></r>");
  if !res.is_ok { return assert(false, "scoped namespace fixture parses"); }
  let d = res.value;
  var ok = elem_uri_is(&d, 3, "urn:2");
  if !elem_uri_is(&d, 4, "urn:1") { ok = false; }
  if !ns_is(&d, 2, "p", "urn:2") { ok = false; }
  if !ns_is(&d, 4, "p", "urn:1") { ok = false; }
  let un = xml2_parse("<a><p:b/></a>");
  if !un.is_ok { ok = false; }
  if un.is_ok {
    let du = un.value;
    let eu = xml2_ns_element_uri(&du, 2);
    if eu.is_ok { ok = false; }
    let ru = xml2_ns_resolve(&du, 2, "p");
    if ru.is_ok { ok = false; }
    if !streq(ru.error, "xml2: unbound namespace prefix") { ok = false; }
    if !ns_is(&du, 2, "", "") { ok = false; }
  }
  let nsdoc = xml2_parse("<r xmlns:p=\"urn:p\"><p:a/><a/></r>");
  if !nsdoc.is_ok { ok = false; }
  if nsdoc.is_ok {
    let dn = nsdoc.value;
    if !count_is(&dn, 0, "/r/p:a", 1) { ok = false; }
    if !first_is(&dn, 0, "/r/p:a", 2) { ok = false; }
    if !count_is(&dn, 0, "/r/a", 2) { ok = false; }
    if !count_is(&dn, 0, "/r/x:q", 0) { ok = false; }
  }
  return assert(ok, "namespaces: scoped override, unbound errors, XPath-aware");
}

fn t19() -> TestResult {
  let res = xml2_parse("<a z=\"1\" m=\"2\" xmlns:b=\"u2\" xmlns=\"u1\" b:q=\"3\"/>");
  if !res.is_ok { return assert(false, "serializer fixture parses"); }
  let d = res.value;
  var ok = streq(xml2_serialize(&d), "<a b:q=\"3\" m=\"2\" xmlns=\"u1\" xmlns:b=\"u2\" z=\"1\"/>");
  if !streq(xml2_escape_text("<&>\"'"), "&lt;&amp;&gt;\"'") { ok = false; }
  if !streq(xml2_escape_attr("a\"b<c&d"), "a&quot;b&lt;c&amp;d") { ok = false; }
  if !streq(xml2_escape_attr("x>y"), "x>y") { ok = false; }
  return assert(ok, "serializer: canonical attribute order, quoting, escaping");
}

fn t20() -> TestResult {
  let res = xml2_parse("<a b=\"x&lt;y\">t &amp; u</a>");
  if !res.is_ok { return assert(false, "round-trip fixture parses"); }
  let d = res.value;
  var ok = streq(xml2_serialize(&d), "<a b=\"x&lt;y\">t &amp; u</a>");
  if !round_trips(&d) { ok = false; }
  let empty = xml2_parse("<e/>");
  if !empty.is_ok { ok = false; }
  if empty.is_ok {
    let de = empty.value;
    if !streq(xml2_serialize(&de), "<e/>") { ok = false; }
    if !round_trips(&de) { ok = false; }
  }
  return assert(ok, "serializer round-trips and never double-escapes");
}

fn t21() -> TestResult {
  let src = "<?xml version=\"1.0\"?><!DOCTYPE r SYSTEM \"r.dtd\"><r xmlns:p=\"urn:p\" z=\"2\" a=\"1\"><!-- c --><p:x><![CDATA[a<b & c]]></p:x>text &amp; more<?pi data?></r>";
  let res = xml2_parse(src);
  if !res.is_ok { return assert(false, "full document parses"); }
  let d = res.value;
  var ok = xml2_node_count(&d) == 9;
  if !root_is(&d, 3) { ok = false; }
  if !round_trips(&d) { ok = false; }
  return assert(ok, "full-document round trip is stable (PI, DOCTYPE, CDATA)");
}

fn t22() -> TestResult {
  let res = xml2_parse("<r> <a/> </r>");
  if !res.is_ok { return assert(false, "whitespace fixture parses"); }
  let d = res.value;
  var ok = xml2_child_count(&d, 1) == 3;
  if !text_is(&d, 1, "  ") { ok = false; }
  if xml2_kind(&d, 2) != 1 { ok = false; }
  let lead = xml2_parse("\n<a/>\n");
  if !lead.is_ok { ok = false; }
  if lead.is_ok {
    let dl = lead.value;
    if xml2_node_count(&dl) != 2 { ok = false; }
    if !streq(xml2_serialize(&dl), "<a/>") { ok = false; }
  }
  let inner = xml2_parse("<r>  hi  </r>");
  if !inner.is_ok { ok = false; }
  if inner.is_ok {
    let di = inner.value;
    if !text_is(&di, 1, "  hi  ") { ok = false; }
  }
  return assert(ok, "element whitespace is preserved, document-level is dropped");
}

fn t23() -> TestResult {
  let src = "<r><a/><b><a x=\"1\"/></b></r>";
  let res = xml2_parse(src);
  if !res.is_ok { return assert(false, "find fixture parses"); }
  let d = res.value;
  let va = xml2_find(&d, "a");
  var ok = va.len() == 2;
  if va.len() == 2 {
    let a0: Int = va[0];
    let a1: Int = va[1];
    if a0 != 2 { ok = false; }
    if a1 != 4 { ok = false; }
  }
  if xml2_find(&d, "z").len() != 0 { ok = false; }
  if xml2_find_first(&d, "a") != 2 { ok = false; }
  if xml2_find_first(&d, "z") != -1 { ok = false; }
  if xml2_find_local(&d, "a").len() != 2 { ok = false; }
  if xml2_child_by_name(&d, 3, "a") != 4 { ok = false; }
  if xml2_node_open(&d, 1) != 0 { ok = false; }
  if xml2_node_close(&d, 1) != src.len() { ok = false; }
  let rb = xml2_node_raw_bytes(&d, 2);
  if rb.len() != 4 { ok = false; }
  if rb.len() == 4 {
    if (((rb[0] as Int) & 0xFF) != 60) { ok = false; }
    if (((rb[1] as Int) & 0xFF) != 97) { ok = false; }
    if (((rb[2] as Int) & 0xFF) != 47) { ok = false; }
    if (((rb[3] as Int) & 0xFF) != 62) { ok = false; }
  }
  if xml2_node_raw_bytes(&d, 99).len() != 0 { ok = false; }
  return assert(ok, "find/find_local, spans, raw bytes");
}

fn t24() -> TestResult {
  let res = xml2_parse("<?p d?><r><![CDATA[c]]><!-- m --></r>");
  if !res.is_ok { return assert(false, "node fixture parses"); }
  let d = res.value;
  var ok = streq(xml2_version(), "0.1.0");
  if xml2_kind(&d, 1) != 4 { ok = false; }
  if xml2_kind(&d, 3) != 2 { ok = false; }
  if xml2_kind(&d, 4) != 3 { ok = false; }
  if !node_str_is(&d, 1, "d") { ok = false; }
  if !node_str_is(&d, 3, "c") { ok = false; }
  if !node_str_is(&d, 4, " m ") { ok = false; }
  if xml2_child_count(&d, 2) != 2 { ok = false; }
  if xml2_last_child(&d, 2) != 4 { ok = false; }
  if xml2_child_at(&d, 2, 0) != 3 { ok = false; }
  if !streq(xml2_attr_name_at(&d, 2, 0), "") { ok = false; }
  if !streq(xml2_qname_local("p:a"), "a") { ok = false; }
  if !streq(xml2_qname_prefix("p:a"), "p") { ok = false; }
  if !streq(xml2_qname_prefix("a"), "") { ok = false; }
  return assert(ok, "node kinds, scalar strings, version, qname helpers");
}

fn main() -> Int {
  io.println("=== xiom.xml2 conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.xml2: all tests passed");
  } else {
    io.println("xiom.xml2: tests failed");
  }
  return failed;
}
