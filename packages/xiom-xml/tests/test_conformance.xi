// XIOM -- xiom.xml conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.xml module against its documented subset.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: parsing (elements, attributes, text, self-closing
// tags, comments, the declaration, entities, whitespace), the error catalog,
// malformed input, escaping round-trips and the query accessors.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through the streq/attr_is/text_of_is helpers.

module xml_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.xml;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Expected error text; false when the parse unexpectedly succeeded.
fn err_text(r_is_ok: Bool, err: Str, want: Str) -> Bool {
  if r_is_ok { return false; }
  return streq(err, want);
}

fn attr_is(d: &XmlDoc, node: Int, name: Str, want: Str) -> Bool {
  let v = xml_attr(d, node, name);
  match v {
    Some(s) => { return streq(s, want); },
    None => {},
  }
  return false;
}

fn attr_none(d: &XmlDoc, node: Int, name: Str) -> Bool {
  let v = xml_attr(d, node, name);
  match v {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn child_is(d: &XmlDoc, node: Int, index: Int, want: Int) -> Bool {
  let c = xml_child(d, node, index);
  match c {
    Some(i) => { return i == want; },
    None => {},
  }
  return false;
}

fn child_none(d: &XmlDoc, node: Int, index: Int) -> Bool {
  let c = xml_child(d, node, index);
  match c {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn first_is(d: &XmlDoc, tag: Str, want: Int) -> Bool {
  let f = xml_find_first(d, tag);
  match f {
    Some(i) => { return i == want; },
    None => {},
  }
  return false;
}

fn first_none(d: &XmlDoc, tag: Str) -> Bool {
  let f = xml_find_first(d, tag);
  match f {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn text_of_is(d: &XmlDoc, tag: Str, want: Str) -> Bool {
  let t = xml_text_of(d, tag);
  match t {
    Some(s) => { return streq(s, want); },
    None => {},
  }
  return false;
}

fn text_of_none(d: &XmlDoc, tag: Str) -> Bool {
  let t = xml_text_of(d, tag);
  match t {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let res = xml_parse("<greeting>Hello</greeting>");
  if !res.is_ok { return assert(false, "single element parses"); }
  let d = res.value;
  var ok = xml_node_count(&d) == 3;
  if xml_root(&d) != 1 { ok = false; }
  if xml_kind(&d, 0) != 0 { ok = false; }
  if xml_kind(&d, 1) != 0 { ok = false; }
  if !streq(xml_name(&d, 1), "greeting") { ok = false; }
  if !streq(xml_text(&d, 1), "Hello") { ok = false; }
  return assert(ok, "single element parses with root, kind, name and text");
}

fn t2() -> TestResult {
  let res = xml_parse("<a x=\"1\" y='2'/>");
  if !res.is_ok { return assert(false, "attributes with both quote styles parse"); }
  let d = res.value;
  let root = xml_root(&d);
  var ok = root == 1;
  if !attr_is(&d, root, "x", "1") { ok = false; }
  if !attr_is(&d, root, "y", "2") { ok = false; }
  if !attr_none(&d, root, "z") { ok = false; }
  if xml_child_count(&d, root) != 0 { ok = false; }
  return assert(ok, "attributes parse with double and single quotes");
}

fn t3() -> TestResult {
  let res = xml_parse("<a><b/><c><d/></c></a>");
  if !res.is_ok { return assert(false, "nested elements parse"); }
  let d = res.value;
  var ok = xml_node_count(&d) == 5;
  if xml_root(&d) != 1 { ok = false; }
  if !child_is(&d, 1, 0, 2) { ok = false; }
  if !child_is(&d, 1, 1, 3) { ok = false; }
  if !child_is(&d, 3, 0, 4) { ok = false; }
  if !child_none(&d, 1, 2) { ok = false; }
  if !child_none(&d, 2, 0) { ok = false; }
  if xml_child_count(&d, 1) != 2 { ok = false; }
  if xml_child_count(&d, 3) != 1 { ok = false; }
  if xml_kind(&d, 4) != 0 { ok = false; }
  if !streq(xml_name(&d, 3), "c") { ok = false; }
  if !streq(xml_name(&d, 4), "d") { ok = false; }
  return assert(ok, "nested elements expose child indices and parents");
}

fn t4() -> TestResult {
  let res = xml_parse("<p>Hello <b>world</b>!</p>");
  if !res.is_ok { return assert(false, "text nodes parse"); }
  let d = res.value;
  var ok = xml_node_count(&d) == 6;
  if xml_child_count(&d, 1) != 3 { ok = false; }
  if !child_is(&d, 1, 0, 2) { ok = false; }
  if !child_is(&d, 1, 1, 3) { ok = false; }
  if !child_is(&d, 1, 2, 5) { ok = false; }
  if xml_kind(&d, 2) != 1 { ok = false; }
  if xml_kind(&d, 5) != 1 { ok = false; }
  if !streq(d.texts[2], "Hello ") { ok = false; }
  if !streq(d.texts[4], "world") { ok = false; }
  if !streq(d.texts[5], "!") { ok = false; }
  if !streq(xml_text(&d, 1), "Hello !") { ok = false; }
  if !streq(xml_text(&d, 3), "world") { ok = false; }
  return assert(ok, "text nodes are children and xml_text concatenates direct text");
}

fn t5() -> TestResult {
  let res = xml_parse("<a><b x=\"1\"/><b y='2'/></a>");
  if !res.is_ok { return assert(false, "self-closing tags parse"); }
  let d = res.value;
  var ok = xml_node_count(&d) == 4;
  if xml_child_count(&d, 1) != 2 { ok = false; }
  if !child_is(&d, 1, 0, 2) { ok = false; }
  if !child_is(&d, 1, 1, 3) { ok = false; }
  if xml_child_count(&d, 2) != 0 { ok = false; }
  if xml_child_count(&d, 3) != 0 { ok = false; }
  if !attr_is(&d, 2, "x", "1") { ok = false; }
  if !attr_is(&d, 3, "y", "2") { ok = false; }
  if !streq(xml_text(&d, 1), "") { ok = false; }
  return assert(ok, "self-closing tags create childless elements");
}

fn t6() -> TestResult {
  let res = xml_parse("<?xml version=\"1.0\" encoding=\"UTF-8\"?><!-- top --><r><!-- <fake> <x/> --><x/></r>");
  if !res.is_ok { return assert(false, "declaration and comments are skipped"); }
  let d = res.value;
  var ok = xml_node_count(&d) == 3;
  if xml_root(&d) != 1 { ok = false; }
  if !streq(xml_name(&d, 1), "r") { ok = false; }
  if xml_child_count(&d, 1) != 1 { ok = false; }
  if !child_is(&d, 1, 0, 2) { ok = false; }
  if !streq(xml_name(&d, 2), "x") { ok = false; }
  if xml_find(&d, "fake").len() != 0 { ok = false; }
  if xml_find(&d, "x").len() != 1 { ok = false; }
  return assert(ok, "declaration and comments are skipped");
}

fn t7() -> TestResult {
  let res = xml_parse("<a>&amp;&lt;&gt;&quot;&apos;&#65;&#x42;&#X43;</a>");
  if !res.is_ok { return assert(false, "entities decode in text"); }
  let d = res.value;
  var ok = streq(xml_text(&d, 1), "&<>\"'ABC");
  let loose = xml_parse("<a>a &amp b &nope;</a>");
  if !loose.is_ok { ok = false; }
  if loose.is_ok {
    let ld = loose.value;
    if !streq(xml_text(&ld, 1), "a &amp b &nope;") { ok = false; }
  }
  return assert(ok, "entities: named, decimal and hex decode; unknown stays literal");
}

fn t8() -> TestResult {
  let s = "a<b&c>d\"e'f";
  var ok = streq(xml_escape(s), "a&lt;b&amp;c&gt;d&quot;e&apos;f");
  if !streq(xml_unescape(xml_escape(s)), s) { ok = false; }
  if !streq(xml_escape(""), "") { ok = false; }
  if !streq(xml_unescape("plain"), "plain") { ok = false; }
  return assert(ok, "xml_escape / xml_unescape round-trip");
}

fn t9() -> TestResult {
  let res = xml_parse("<r><x i=\"1\"/><y/><x i=\"2\"/></r>");
  if !res.is_ok { return assert(false, "xml_find multiple and none"); }
  let d = res.value;
  let xs = xml_find(&d, "x");
  var ok = xs.len() == 2;
  if ok {
    if !attr_is(&d, xs[0], "i", "1") { ok = false; }
    if !attr_is(&d, xs[1], "i", "2") { ok = false; }
    if xs[0] >= xs[1] { ok = false; }
  }
  if xml_find(&d, "y").len() != 1 { ok = false; }
  if xml_find(&d, "z").len() != 0 { ok = false; }
  if xml_find(&d, "r").len() != 1 { ok = false; }
  return assert(ok, "xml_find returns all matches in document order and none");
}

fn t10() -> TestResult {
  let res = xml_parse("<r><x i=\"1\"/><y/><x i=\"2\"/></r>");
  if !res.is_ok { return assert(false, "xml_find_first"); }
  let d = res.value;
  let xs = xml_find(&d, "x");
  let ys = xml_find(&d, "y");
  var ok = xs.len() == 2;
  if ys.len() != 1 { ok = false; }
  if ok {
    if !first_is(&d, "x", xs[0]) { ok = false; }
    if !first_is(&d, "y", ys[0]) { ok = false; }
  }
  if !first_none(&d, "z") { ok = false; }
  return assert(ok, "xml_find_first returns first match or None");
}

fn t11() -> TestResult {
  let res = xml_parse("<r><n>one</n><n>two</n></r>");
  if !res.is_ok { return assert(false, "xml_text_of"); }
  let d = res.value;
  var ok = text_of_is(&d, "n", "one");
  if !text_of_is(&d, "r", "") { ok = false; }
  if !text_of_none(&d, "z") { ok = false; }
  let twice = xml_parse("<r><n>a<!--c-->b</n></r>");
  if !twice.is_ok { ok = false; }
  if twice.is_ok {
    let td = twice.value;
    if !text_of_is(&td, "n", "ab") { ok = false; }
  }
  return assert(ok, "xml_text_of returns first match text or None");
}

fn t12() -> TestResult {
  let a = xml_parse("<a></b>");
  var ok = err_text(a.is_ok, a.error, "xml: mismatched closing tag");
  let b = xml_parse("<a><b></a></b>");
  if !err_text(b.is_ok, b.error, "xml: mismatched closing tag") { ok = false; }
  return assert(ok, "mismatched closing tag is Err");
}

fn t13() -> TestResult {
  let a = xml_parse("<a><b></b>");
  var ok = err_text(a.is_ok, a.error, "xml: unclosed tag");
  let b = xml_parse("<a");
  if !err_text(b.is_ok, b.error, "xml: unclosed tag") { ok = false; }
  let c = xml_parse("<a><b");
  if !err_text(c.is_ok, c.error, "xml: unclosed tag") { ok = false; }
  return assert(ok, "unclosed tag is Err");
}

fn t14() -> TestResult {
  let a = xml_parse("<a>1 < 2</a>");
  var ok = err_text(a.is_ok, a.error, "xml: stray '<'");
  let b = xml_parse("<a><</a>");
  if !err_text(b.is_ok, b.error, "xml: stray '<'") { ok = false; }
  let c = xml_parse("<a><></a>");
  if !err_text(c.is_ok, c.error, "xml: stray '<'") { ok = false; }
  return assert(ok, "stray '<' is Err");
}

fn t15() -> TestResult {
  let res = xml_parse("");
  if !res.is_ok { return assert(false, "empty input parses"); }
  let d = res.value;
  var ok = xml_node_count(&d) == 1;
  if xml_kind(&d, 0) != 0 { ok = false; }
  if xml_child_count(&d, 0) != 0 { ok = false; }
  if xml_find(&d, "").len() != 0 { ok = false; }
  if xml_text(&d, 0).len() != 0 { ok = false; }
  return assert(ok, "empty input yields an empty document");
}

fn t16() -> TestResult {
  let empty = xml_parse("");
  if !empty.is_ok { return assert(false, "empty document root is -1"); }
  let d = empty.value;
  var ok = xml_root(&d) == -1;
  let blank = xml_parse("  \n\t ");
  if !blank.is_ok { ok = false; }
  if blank.is_ok {
    let b = blank.value;
    if xml_root(&b) != -1 { ok = false; }
    if xml_node_count(&b) != 1 { ok = false; }
  }
  let comment = xml_parse("<!-- only a comment -->");
  if !comment.is_ok { ok = false; }
  if comment.is_ok {
    let c = comment.value;
    if xml_root(&c) != -1 { ok = false; }
  }
  return assert(ok, "root of an empty document is -1");
}

fn t17() -> TestResult {
  let res = xml_parse("<a x=\"1\">t</a>");
  if !res.is_ok { return assert(false, "attribute missing yields None"); }
  let d = res.value;
  var ok = attr_is(&d, 1, "x", "1");
  if !attr_none(&d, 1, "y") { ok = false; }
  if !attr_none(&d, 1, "") { ok = false; }
  if !attr_none(&d, 2, "x") { ok = false; }
  if !attr_none(&d, 99, "x") { ok = false; }
  if !attr_none(&d, -1, "x") { ok = false; }
  let dup = xml_parse("<a x=\"1\" x=\"2\"/>");
  if !dup.is_ok { ok = false; }
  if dup.is_ok {
    let dd = dup.value;
    if !attr_is(&dd, 1, "x", "1") { ok = false; }
  }
  return assert(ok, "xml_attr returns None for missing attributes (first of duplicates)");
}

fn t18() -> TestResult {
  let res = xml_parse("<a>x</a>");
  if !res.is_ok { return assert(false, "accessors are safe out of range"); }
  let d = res.value;
  var ok = xml_kind(&d, -1) == -1;
  if xml_kind(&d, 99) != -1 { ok = false; }
  if !streq(xml_name(&d, -1), "") { ok = false; }
  if !streq(xml_name(&d, 99), "") { ok = false; }
  if !streq(xml_text(&d, -1), "") { ok = false; }
  if xml_child_count(&d, -5) != 0 { ok = false; }
  if !child_none(&d, 1, -1) { ok = false; }
  if !child_none(&d, 0, 1) { ok = false; }
  if xml_node_count(&d) != 3 { ok = false; }
  return assert(ok, "accessors are safe for out-of-range nodes");
}

fn t19() -> TestResult {
  let a = xml_parse("hello<a/>");
  var ok = err_text(a.is_ok, a.error, "xml: text outside root element");
  let b = xml_parse("<a/>tail");
  if !err_text(b.is_ok, b.error, "xml: text outside root element") { ok = false; }
  let amp = xml_parse(" &amp;<a/>");
  if !err_text(amp.is_ok, amp.error, "xml: text outside root element") { ok = false; }
  let ws = xml_parse("  <a/>\n ");
  if !ws.is_ok { ok = false; }
  if ws.is_ok {
    let wd = ws.value;
    if xml_root(&wd) != 1 { ok = false; }
    if xml_node_count(&wd) != 2 { ok = false; }
  }
  return assert(ok, "text outside the root element is Err");
}

fn t20() -> TestResult {
  let a = xml_parse("<a/><b/>");
  var ok = err_text(a.is_ok, a.error, "xml: multiple root elements");
  let b = xml_parse("<a></a><b></b>");
  if !err_text(b.is_ok, b.error, "xml: multiple root elements") { ok = false; }
  return assert(ok, "multiple root elements are Err");
}

fn t21() -> TestResult {
  let a = xml_parse("<a><!-- no end");
  var ok = err_text(a.is_ok, a.error, "xml: unclosed comment");
  let b = xml_parse("<!DOCTYPE a><a/>");
  if !err_text(b.is_ok, b.error, "xml: unsupported markup") { ok = false; }
  let c = xml_parse("<a><![CDATA[x]]></a>");
  if !err_text(c.is_ok, c.error, "xml: unsupported markup") { ok = false; }
  let e = xml_parse("<?xml version=\"1.0\"");
  if !err_text(e.is_ok, e.error, "xml: unclosed processing instruction") { ok = false; }
  let f = xml_parse("<?pi data?><a/>");
  if !f.is_ok { ok = false; }
  if f.is_ok {
    let fd = f.value;
    if xml_root(&fd) != 1 { ok = false; }
  }
  return assert(ok, "unclosed comment / unsupported markup / unclosed PI are Err");
}

fn t22() -> TestResult {
  let res = xml_parse("<a>  hi  </a>");
  if !res.is_ok { return assert(false, "whitespace is preserved"); }
  let d = res.value;
  var ok = streq(xml_text(&d, 1), "  hi  ");
  if xml_child_count(&d, 1) != 1 { ok = false; }
  let multi = xml_parse("<a>l1\nl2</a>");
  if !multi.is_ok { ok = false; }
  if multi.is_ok {
    let md = multi.value;
    if !streq(xml_text(&md, 1), "l1\nl2") { ok = false; }
  }
  let mixed = xml_parse("<a><b/>  <c/></a>");
  if !mixed.is_ok { ok = false; }
  if mixed.is_ok {
    let xd = mixed.value;
    if xml_child_count(&xd, 1) != 3 { ok = false; }
    if !streq(xml_text(&xd, 1), "  ") { ok = false; }
  }
  return assert(ok, "whitespace inside elements is preserved as text nodes");
}

fn t23() -> TestResult {
  let res = xml_parse("<a b=\"&amp;\" c='&#65;'/>");
  if !res.is_ok { return assert(false, "attribute values decode entities"); }
  let d = res.value;
  var ok = attr_is(&d, 1, "b", "&");
  if !attr_is(&d, 1, "c", "A") { ok = false; }
  let single = xml_parse("<a b='x&lt;y'/>");
  if !single.is_ok { ok = false; }
  if single.is_ok {
    let sd = single.value;
    if !attr_is(&sd, 1, "b", "x<y") { ok = false; }
  }
  return assert(ok, "attribute values decode predefined and numeric entities");
}

fn t24() -> TestResult {
  let a = xml_parse("<a b=\"x></a>");
  var ok = err_text(a.is_ok, a.error, "xml: unclosed attribute value");
  let b = xml_parse("<a b=x/>");
  if !err_text(b.is_ok, b.error, "xml: malformed attribute") { ok = false; }
  let c = xml_parse("<a b/>");
  if !err_text(c.is_ok, c.error, "xml: malformed attribute") { ok = false; }
  let e = xml_parse("<a b=\"1\"c='2'/>");
  if !e.is_ok { ok = false; }
  if e.is_ok {
    let ed = e.value;
    if !attr_is(&ed, 1, "c", "2") { ok = false; }
  }
  return assert(ok, "unclosed attribute value and malformed attributes are Err");
}

fn main() -> Int {
  io.println("=== xiom.xml conformance tests ===");
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
    io.println("xiom.xml: all tests passed");
  } else {
    io.println("xiom.xml: tests failed");
  }
  return failed;
}
