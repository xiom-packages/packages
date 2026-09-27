// XIOM -- xiom.expat conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Synthetic XML documents are built in-test; every string equality goes
// through str_compare (BUG 17) and raw bytes a source literal cannot spell are
// built with Vec[UInt8].

module expat_tests
use xiom.io; use xiom.test; use xiom.expat;
use xiom.string;
use xiom.string.compare;
use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes1(a: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return Str::from_utf8(v);
}

fn bytes2(a: Int, b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

fn pos_of(s: Str, lit: Str) -> Int {
  let n = s.len();
  let m = lit.len();
  if m == 0 {
    return 0;
  }
  var i = 0;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if string.byte_at(s, i + j) != string.byte_at(lit, j) {
        hit = false;
        break;
      }
      j = j + 1;
    }
    if hit {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn err_is(text: Str, want: Str) -> Bool {
  let r = expat_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  };
  return false;
}

fn ev_count_of(text: Str) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_count(&st); },
    Err(_) => { return -1; },
  };
  return -1;
}

fn kind_name_at(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_kind_name(expat_event_kind(&st, i)); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn name_at(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_name(&st, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn data_at(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_data(&st, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn off_at(text: Str, i: Int) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_offset(&st, i); },
    Err(_) => { return -99; },
  };
  return -99;
}

fn line_at(text: Str, i: Int) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_line(&st, i); },
    Err(_) => { return -99; },
  };
  return -99;
}

fn col_at(text: Str, i: Int) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_column(&st, i); },
    Err(_) => { return -99; },
  };
  return -99;
}

fn consumed_at(text: Str, i: Int) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_consumed(&st, i); },
    Err(_) => { return -99; },
  };
  return -99;
}

fn attr_count_at(text: Str, i: Int) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_attr_count(&st, i); },
    Err(_) => { return -99; },
  };
  return -99;
}

fn attr_name_at(text: Str, i: Int, k: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_attr_name(&st, i, k); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn attr_val_at(text: Str, i: Int, k: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_attr_value(&st, i, k); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn attr_quote_at(text: Str, i: Int, k: Int) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_attr_quote(&st, i, k); },
    Err(_) => { return -99; },
  };
  return -99;
}

fn elem_count_of(text: Str) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_element_count(&st); },
    Err(_) => { return -1; },
  };
  return -1;
}

fn elem_name_of(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_element_name(&st, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn elem_depth_of(text: Str, i: Int) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_element_depth(&st, i); },
    Err(_) => { return -99; },
  };
  return -99;
}

fn elem_attr_of(text: Str, i: Int, name: Str) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_extract_attribute(&st, i, name); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn text_content_of(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_text_content(&st, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn enc_of(text: Str) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_encoding(&st); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn ver_of(text: Str) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_version(&st); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn standalone_of(text: Str) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_standalone(&st); },
    Err(_) => { return -99; },
  };
  return -99;
}

fn has_doctype_of(text: Str) -> Bool {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_has_doctype(&st); },
    Err(_) => { return false; },
  };
  return false;
}

fn sid_of(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_system_id(&st, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn pid_of(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_event_public_id(&st, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn entity_count_of(text: Str) -> Int {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_entity_count(&st); },
    Err(_) => { return -1; },
  };
  return -1;
}

fn entity_name_of(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_entity_name(&st, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

fn entity_value_of(text: Str, i: Int) -> Str {
  let r = expat_parse(text);
  match r {
    Ok(st) => { return expat_entity_value(&st, i); },
    Err(_) => { return "<err>"; },
  };
  return "<err>";
}

// ---------------------------------------------------------------------------
//  Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let doc = "<a b=\"1\" c='2'>hi</a>";
  var ok = ev_count_of(doc) == 3;
  if !streq(kind_name_at(doc, 0), "start") { ok = false; }
  if !streq(kind_name_at(doc, 1), "text") { ok = false; }
  if !streq(kind_name_at(doc, 2), "end") { ok = false; }
  if !streq(name_at(doc, 0), "a") { ok = false; }
  if !streq(name_at(doc, 2), "a") { ok = false; }
  if !streq(data_at(doc, 1), "hi") { ok = false; }
  if off_at(doc, 0) != 0 { ok = false; }
  if off_at(doc, 1) != 15 { ok = false; }
  if off_at(doc, 2) != 17 { ok = false; }
  if col_at(doc, 0) != 1 { ok = false; }
  if col_at(doc, 1) != 16 { ok = false; }
  if col_at(doc, 2) != 18 { ok = false; }
  if line_at(doc, 2) != 1 { ok = false; }
  if consumed_at(doc, 0) != 15 { ok = false; }
  if consumed_at(doc, 1) != 2 { ok = false; }
  if consumed_at(doc, 2) != 4 { ok = false; }
  if attr_count_at(doc, 0) != 2 { ok = false; }
  if !streq(attr_name_at(doc, 0, 0), "b") { ok = false; }
  if !streq(attr_name_at(doc, 0, 1), "c") { ok = false; }
  if !streq(attr_val_at(doc, 0, 0), "1") { ok = false; }
  if !streq(attr_val_at(doc, 0, 1), "2") { ok = false; }
  if attr_quote_at(doc, 0, 0) != 0 { ok = false; }
  if attr_quote_at(doc, 0, 1) != 1 { ok = false; }
  return assert(ok, "start/text/end events: names, attributes, offsets, lines and consumed counts");
}

fn t2() -> TestResult {
  let doc = "<r><a/> <b>x</b></r>";
  var ok = ev_count_of(doc) == 8;
  if !streq(kind_name_at(doc, 0), "start") { ok = false; }
  if !streq(kind_name_at(doc, 2), "end") { ok = false; }
  if !streq(name_at(doc, 2), "a") { ok = false; }
  if off_at(doc, 1) != 3 { ok = false; }
  if off_at(doc, 2) != 3 { ok = false; }
  if consumed_at(doc, 1) != 4 { ok = false; }
  if consumed_at(doc, 2) != 0 { ok = false; }
  if elem_count_of(doc) != 3 { ok = false; }
  if !streq(elem_name_of(doc, 0), "r") { ok = false; }
  if !streq(elem_name_of(doc, 1), "a") { ok = false; }
  if !streq(elem_name_of(doc, 2), "b") { ok = false; }
  if elem_depth_of(doc, 0) != 0 { ok = false; }
  if elem_depth_of(doc, 1) != 1 { ok = false; }
  if elem_depth_of(doc, 2) != 1 { ok = false; }
  if !streq(text_content_of(doc, 0), " x") { ok = false; }
  if !streq(text_content_of(doc, 1), "") { ok = false; }
  if !streq(text_content_of(doc, 2), "x") { ok = false; }
  return assert(ok, "empty elements produce start+end; depths and text_content aggregation");
}

fn t3() -> TestResult {
  let doc = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a/>";
  var ok = ev_count_of(doc) == 3;
  if !streq(kind_name_at(doc, 0), "decl") { ok = false; }
  if !streq(name_at(doc, 0), "1.0") { ok = false; }
  if !streq(data_at(doc, 0), "UTF-8") { ok = false; }
  if !streq(ver_of(doc), "1.0") { ok = false; }
  if !streq(enc_of(doc), "UTF-8") { ok = false; }
  if standalone_of(doc) != 1 { ok = false; }
  if off_at(doc, 1) != 55 { ok = false; }
  if consumed_at(doc, 0) != 55 { ok = false; }
  return assert(ok, "XML declaration: version, encoding and standalone are recorded");
}

fn t4() -> TestResult {
  let e_acute = bytes2(195, 169);
  let doc = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><a>" + bytes1(233) + "</a>";
  var ok = streq(enc_of(doc), "ISO-8859-1");
  if !streq(data_at(doc, 2), e_acute) { ok = false; }
  if !streq(text_content_of(doc, 0), e_acute) { ok = false; }
  if elem_count_of(doc) != 1 { ok = false; }
  return assert(ok, "declared Latin-1 fallback: 0xE9 decodes to U+00E9 (UTF-8 0xC3 0xA9)");
}

fn t5() -> TestResult {
  let doc = bytes2(239, 187) + bytes1(191) + "<a/>";
  var ok = ev_count_of(doc) == 2;
  if !streq(enc_of(doc), "UTF-8") { ok = false; }
  if off_at(doc, 0) != 0 { ok = false; }
  if !streq(name_at(doc, 0), "a") { ok = false; }
  return assert(ok, "UTF-8 BOM is detected and stripped (offsets are BOM-stripped offsets)");
}

fn t6() -> TestResult {
  let le = bytes2(255, 254) + "<a/>";
  let be = bytes2(254, 255) + "<a/>";
  var ok = err_is(le, "expat: UTF-16LE input unsupported at 0");
  if !err_is(be, "expat: UTF-16BE input unsupported at 0") { ok = false; }
  return assert(ok, "UTF-16LE/BE BOMs are detected and rejected (XIOM Str cannot carry NUL bytes)");
}

fn t7() -> TestResult {
  let doc = "<!--c--><a/><!--d-->";
  var ok = ev_count_of(doc) == 4;
  if !streq(kind_name_at(doc, 0), "comment") { ok = false; }
  if !streq(data_at(doc, 0), "c") { ok = false; }
  if !streq(data_at(doc, 3), "d") { ok = false; }
  if !streq(data_at("<!----><a/>", 0), "") { ok = false; }
  if !err_is("<!--a--b-->", "expat: double dash in comment at 5") { ok = false; }
  if !err_is("<!--a--->", "expat: double dash in comment at 5") { ok = false; }
  if !err_is("<!--a", "expat: unterminated comment at 0") { ok = false; }
  return assert(ok, "comments: body kept verbatim, '--' inside is rejected, empty comment allowed");
}

fn t8() -> TestResult {
  var ok = streq(kind_name_at("<?php echo; ?><a/>", 0), "pi");
  if !streq(name_at("<?php echo; ?><a/>", 0), "php") { ok = false; }
  if !streq(data_at("<?php echo; ?><a/>", 0), "echo; ") { ok = false; }
  if !streq(data_at("<?p a?b?><a/>", 0), "a?b") { ok = false; }
  if !err_is("<?XML x?><a/>", "expat: reserved PI target at 0") { ok = false; }
  if !err_is("<a><?xml x?></a>", "expat: reserved PI target at 3") { ok = false; }
  if !err_is("<?p x", "expat: unterminated PI at 0") { ok = false; }
  return assert(ok, "processing instructions: target and raw data; the reserved xml target is rejected");
}

fn t9() -> TestResult {
  let doc = "<a><![CDATA[x<y&z]]></a>";
  var ok = streq(kind_name_at(doc, 1), "cdata");
  if !streq(data_at(doc, 1), "x<y&z") { ok = false; }
  if off_at(doc, 1) != 3 { ok = false; }
  if consumed_at(doc, 1) != 17 { ok = false; }
  if !streq(text_content_of(doc, 0), "x<y&z") { ok = false; }
  if !streq(text_content_of("<a>t<![CDATA[c]]></a>", 0), "tc") { ok = false; }
  if !err_is("<![CDATA[x]]>", "expat: CDATA outside root element at 0") { ok = false; }
  if !err_is("<a><![CDATA[x</a>", "expat: unterminated CDATA at 3") { ok = false; }
  return assert(ok, "CDATA: verbatim body, no reference expansion, text_content includes it");
}

fn t10() -> TestResult {
  let d1 = "<!DOCTYPE doc SYSTEM \"doc.dtd\"><doc/>";
  var ok = streq(kind_name_at(d1, 0), "doctype");
  if !streq(name_at(d1, 0), "doc") { ok = false; }
  if !streq(sid_of(d1, 0), "doc.dtd") { ok = false; }
  if !streq(pid_of(d1, 0), "") { ok = false; }
  let d2 = "<!DOCTYPE doc PUBLIC \"-//X//EN\" \"doc.dtd\"><doc/>";
  if !streq(pid_of(d2, 0), "-//X//EN") { ok = false; }
  if !streq(sid_of(d2, 0), "doc.dtd") { ok = false; }
  let d3 = "<!DOCTYPE d [<!ELEMENT d (#PCDATA)>]><d/>";
  if !streq(data_at(d3, 0), "<!ELEMENT d (#PCDATA)>") { ok = false; }
  if !has_doctype_of(d3) { ok = false; }
  if !err_is("<!DOCTYPE d", "expat: unterminated DOCTYPE at 0") { ok = false; }
  if !err_is("<!DOCTYPE 1><d/>", "expat: invalid DOCTYPE name at 10") { ok = false; }
  if !err_is("<!DOCTYPE d SYSTEM x><d/>", "expat: unterminated DOCTYPE literal at 19") { ok = false; }
  if !err_is("<!DOCTYPE d><!DOCTYPE d><d/>", "expat: duplicate DOCTYPE at 12") { ok = false; }
  if !err_is("<d/><!DOCTYPE d>", "expat: DOCTYPE after root element at 4") { ok = false; }
  return assert(ok, "DOCTYPE: name, SYSTEM/PUBLIC ids, raw internal subset, duplicate and ordering errors");
}

fn t11() -> TestResult {
  let d1 = "<!DOCTYPE d [<!ENTITY e \"v\">]><d>&e;</d>";
  var ok = entity_count_of(d1) == 1;
  if !streq(entity_name_of(d1, 0), "e") { ok = false; }
  if !streq(entity_value_of(d1, 0), "v") { ok = false; }
  if !streq(data_at(d1, 2), "v") { ok = false; }
  let d2 = "<!DOCTYPE d [<!ENTITY a \"A\"><!ENTITY b \"&a;B\">]><d>&b;</d>";
  if !streq(data_at(d2, 2), "AB") { ok = false; }
  if !err_is("<d>&nope;</d>", "expat: unknown entity at 3") { ok = false; }
  if !err_is("<d>&e</d>", "expat: malformed entity reference at 3") { ok = false; }
  if !err_is("<!DOCTYPE d [<!ENTITY e \"&e;\">]><d>&e;</d>", "expat: entity nesting too deep at 35") { ok = false; }
  let reserved = "<!DOCTYPE d [<!ENTITY lt \"x\">]><d/>";
  let rp = pos_of(reserved, "lt \"x\"");
  if !err_is(reserved, "expat: reserved entity redeclared at " + convert.int_to_string(rp)) { ok = false; }
  let param = "<!DOCTYPE d [<!ENTITY % p \"x\">]><d/>";
  let pp = pos_of(param, "% p");
  if !err_is(param, "expat: parameter entity not supported at " + convert.int_to_string(pp)) { ok = false; }
  let dup = "<!DOCTYPE d [<!ENTITY e \"1\"><!ENTITY e \"2\">]><d/>";
  let dp = pos_of(dup, "e \"2\"");
  if !err_is(dup, "expat: duplicate entity at " + convert.int_to_string(dp)) { ok = false; }
  return assert(ok, "internal entities: literal values, recursion, unknown/malformed/reserved/parameter cases");
}

fn t12() -> TestResult {
  let e_acute = bytes2(195, 169);
  var ok = streq(data_at("<a>&lt;&gt;&amp;&apos;&quot;</a>", 1), "<>&'\"");
  if !streq(data_at("<a>&#65;&#x42;&#233;</a>", 1), "AB" + e_acute) { ok = false; }
  if !streq(elem_attr_of("<a b=\"&lt;x&gt;\" c='&#x41;'/>", 0, "b"), "<x>") { ok = false; }
  if !streq(elem_attr_of("<a b=\"&lt;x&gt;\" c='&#x41;'/>", 0, "c"), "A") { ok = false; }
  if !err_is("<a>&#0;</a>", "expat: bad character reference at 3") { ok = false; }
  if !err_is("<a>&#xD800;</a>", "expat: bad character reference at 3") { ok = false; }
  if !err_is("<a>&#x110000;</a>", "expat: bad character reference at 3") { ok = false; }
  if !err_is("<a>&#12</a>", "expat: bad character reference at 3") { ok = false; }
  if !err_is("<a>&;</a>", "expat: malformed entity reference at 3") { ok = false; }
  return assert(ok, "predefined and numeric references decode in text and attributes; bad refs are rejected");
}

fn t13() -> TestResult {
  let doc = "<a b=\"x\ty\" c='p\nq'/>";
  var ok = streq(elem_attr_of(doc, 0, "b"), "x y");
  if !streq(elem_attr_of(doc, 0, "c"), "p q") { ok = false; }
  if attr_quote_at(doc, 0, 0) != 0 { ok = false; }
  if attr_quote_at(doc, 0, 1) != 1 { ok = false; }
  if !streq(elem_attr_of("<a b=\"\"/>", 0, "b"), "") { ok = false; }
  if !err_is("<a b=\"1\" b=\"2\"/>", "expat: duplicate attribute at 9") { ok = false; }
  if !err_is("<a b=\"1\"c=\"2\"/>", "expat: missing whitespace between attributes at 8") { ok = false; }
  if !err_is("<a b/>", "expat: missing '=' in attribute at 4") { ok = false; }
  if !err_is("<a b=x/>", "expat: unterminated attribute value at 5") { ok = false; }
  if !err_is("<a b=\"x<y\"/>", "expat: '<' in attribute value at 7") { ok = false; }
  if !err_is("<a b=\"1>", "expat: unterminated attribute value at 5") { ok = false; }
  return assert(ok, "attributes: quoting, whitespace normalization, duplicates and malformed values");
}

fn t14() -> TestResult {
  var ok = err_is("<a><b></a></b>", "expat: mismatched end tag at 6");
  if !err_is("<a><b></b>", "expat: unclosed element at 0") { ok = false; }
  if !err_is("</a>", "expat: unexpected end tag at 0") { ok = false; }
  if !err_is("<a/><b/>", "expat: multiple root elements at 4") { ok = false; }
  if !err_is("", "expat: no root element at 0") { ok = false; }
  if !err_is("   ", "expat: no root element at 3") { ok = false; }
  if !err_is("<!--c-->", "expat: no root element at 8") { ok = false; }
  if !err_is("x<a/>", "expat: text before root element at 0") { ok = false; }
  if !err_is("<a/>x", "expat: junk after root element at 4") { ok = false; }
  if ev_count_of("<a/>  ") != 3 { ok = false; }
  return assert(ok, "well-formedness: matching end tags, single root, no text before/after the root");
}

fn t15() -> TestResult {
  var ok = err_is("<a>x < y</a>", "expat: invalid markup at 5");
  if !err_is("<a>]]></a>", "expat: ']]>' in text at 5") { ok = false; }
  if !err_is("<a><1/></a>", "expat: invalid markup at 3") { ok = false; }
  if !err_is("<", "expat: invalid markup at 0") { ok = false; }
  if !err_is("</>", "expat: invalid end tag name at 2") { ok = false; }
  return assert(ok, "raw '<' starts markup only when valid; ']]>' and invalid starts are rejected");
}

fn t16() -> TestResult {
  var ok = err_is("<a>" + bytes1(255) + "</a>", "expat: invalid UTF-8 byte at 3");
  if !err_is("<a>" + bytes2(192, 175) + "</a>", "expat: invalid UTF-8 byte at 3") { ok = false; }
  if !err_is("<a>" + bytes1(226) + "</a>", "expat: invalid UTF-8 byte at 3") { ok = false; }
  if !err_is("<a>" + bytes2(226, 65) + "</a>", "expat: invalid UTF-8 byte at 3") { ok = false; }
  if !err_is("<a>" + bytes1(1) + "</a>", "expat: control character at 3") { ok = false; }
  if !err_is("<!--" + bytes1(1) + "--><a/>", "expat: control character at 4") { ok = false; }
  return assert(ok, "malformed UTF-8 (overlong/truncated/bad continuation) and raw controls are rejected");
}

fn t17() -> TestResult {
  let e_acute = bytes2(195, 169);
  var ok = streq(data_at("<a>" + e_acute + "</a>", 1), e_acute);
  if !streq(text_content_of("<a>" + e_acute + "</a>", 0), e_acute) { ok = false; }
  let uni_name = "<" + e_acute + "/>";
  if !streq(elem_name_of(uni_name, 0), e_acute) { ok = false; }
  let ns = "<ns:tag xmlns:ns=\"u\"/>";
  if !streq(elem_name_of(ns, 0), "ns:tag") { ok = false; }
  if !streq(elem_attr_of(ns, 0, "xmlns:ns"), "u") { ok = false; }
  if !streq(expat_prefix_of("ns:tag"), "ns") { ok = false; }
  if !streq(expat_local_of("ns:tag"), "tag") { ok = false; }
  if !streq(expat_prefix_of("tag"), "") { ok = false; }
  if !streq(expat_local_of("tag"), "tag") { ok = false; }
  if !err_is("<1a/>", "expat: invalid markup at 0") { ok = false; }
  if !err_is("<a 1b=\"x\"/>", "expat: invalid attribute name at 3") { ok = false; }
  if !err_is("<a b:c=\"1\" b:c=\"2\"/>", "expat: duplicate attribute at 11") { ok = false; }
  return assert(ok, "non-ASCII bytes pass through names/text; prefixes are recorded, never resolved");
}

fn t18() -> TestResult {
  var ok = err_is("<?xml?><a/>", "expat: bad XML declaration at 5");
  if !err_is("<?xml version=\"2.0\"?><a/>", "expat: bad XML declaration at 14") { ok = false; }
  if !err_is("<?xml version=\"1.0\" encoding=\"Shift_JIS\"?><a/>", "expat: unsupported encoding at 20") { ok = false; }
  if !err_is("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"maybe\"?><a/>", "expat: bad XML declaration at 48") { ok = false; }
  if !err_is("<?xml version=\"1.0\" encoding=\"UTF-8\" version=\"1.0\"?><a/>", "expat: bad XML declaration at 45") { ok = false; }
  if !err_is(" <?xml version=\"1.0\"?><a/>", "expat: reserved PI target at 1") { ok = false; }
  if standalone_of("<?xml version=\"1.0\"?><a/>") != -1 { ok = false; }
  if !streq(enc_of("<a/>"), "UTF-8") { ok = false; }
  return assert(ok, "XML declaration: pseudo-attribute order, value shapes and start-of-document rule");
}

fn t19() -> TestResult {
  let doc = "<r a=\"1\"><x n=\"2\">t1</x><y>t2</y></r>";
  var ok = elem_count_of(doc) == 3;
  if !streq(elem_name_of(doc, 0), "r") { ok = false; }
  if !streq(elem_name_of(doc, 1), "x") { ok = false; }
  if !streq(elem_name_of(doc, 2), "y") { ok = false; }
  if elem_depth_of(doc, 0) != 0 { ok = false; }
  if elem_depth_of(doc, 1) != 1 { ok = false; }
  if elem_depth_of(doc, 2) != 1 { ok = false; }
  if !streq(elem_attr_of(doc, 0, "a"), "1") { ok = false; }
  if !streq(elem_attr_of(doc, 1, "n"), "2") { ok = false; }
  if !streq(elem_attr_of(doc, 0, "zz"), "") { ok = false; }
  if !streq(text_content_of(doc, 0), "t1t2") { ok = false; }
  if !streq(text_content_of(doc, 1), "t1") { ok = false; }
  if !streq(text_content_of(doc, 2), "t2") { ok = false; }
  if !streq(elem_name_of(doc, 9), "") { ok = false; }
  if !streq(text_content_of(doc, -1), "") { ok = false; }
  if !streq(name_at(doc, 99), "") { ok = false; }
  if !streq(kind_name_at(doc, 99), "") { ok = false; }
  if off_at(doc, 99) != -1 { ok = false; }
  if attr_count_at(doc, 2) != 0 { ok = false; }
  if !streq(attr_name_at(doc, 0, 5), "") { ok = false; }
  if !streq(attr_val_at(doc, 0, -1), "") { ok = false; }
  return assert(ok, "one-shot helpers: element count/name/depth, attribute extraction, text content, bounds");
}

fn t20() -> TestResult {
  let r = expat_open("<a b=\"1\">hi</a>");
  match r {
    Ok(st) => {
      var s = st;
      var kinds = Vec[Int].new();
      var err = "";
      loop {
        let nr = expat_next_event(&mut s);
        match nr {
          Ok(k) => { if k < 0 { break; } kinds.push(k); },
          Err(e) => { err = e; break; },
        };
      }
      var ok = streq(err, "");
      if kinds.len() != 3 { ok = false; }
      if kinds.len() == 3 {
        let k0: Int = kinds[0];
        let k1: Int = kinds[1];
        let k2: Int = kinds[2];
        if k0 != 5 { ok = false; }
        if k1 != 7 { ok = false; }
        if k2 != 6 { ok = false; }
      }
      let again = expat_next_event(&mut s);
      match again {
        Ok(k) => { if k >= 0 { ok = false; } },
        Err(_) => { ok = false; },
      };
      if expat_depth(&s) != 0 { ok = false; }
      if expat_event_count(&s) != 3 { ok = false; }
      return assert(ok, "expat_open + expat_next_event stream events one at a time and end with Ok(-1)");
    },
    Err(_) => { return assert(false, "expat_open failed"); },
  };
  return assert(false, "unreachable");
}

fn t21() -> TestResult {
  var ok = streq(text_content_of("<r>a<b>b</b><![CDATA[c]]>d</r>", 0), "abcd");
  if !streq(text_content_of("<r>a<b>b</b><![CDATA[c]]>d</r>", 1), "b") { ok = false; }
  if !streq(text_content_of("<r>x<!--c-->y</r>", 0), "xy") { ok = false; }
  if !streq(text_content_of("<r>a<?p d?>b</r>", 0), "ab") { ok = false; }
  if !streq(text_content_of("<r><a/><b/></r>", 0), "") { ok = false; }
  return assert(ok, "text_content: descendant text and CDATA concatenated, comments/PIs excluded");
}

fn t22() -> TestResult {
  let doc = "<!DOCTYPE d [<!ENTITY e \"E\"><!ATTLIST d a CDATA #IMPLIED>]><d a=\"&e;\"/>";
  var ok = streq(data_at(doc, 0), "<!ENTITY e \"E\"><!ATTLIST d a CDATA #IMPLIED>");
  if entity_count_of(doc) != 1 { ok = false; }
  if !streq(entity_value_of(doc, 0), "E") { ok = false; }
  if !streq(elem_attr_of(doc, 0, "a"), "E") { ok = false; }
  return assert(ok, "internal subset: non-ENTITY declarations are skipped, entities expand in attributes");
}

fn t23() -> TestResult {
  let doc = "<a>\n  <b/>\n</a>";
  var ok = ev_count_of(doc) == 6;
  if line_at(doc, 0) != 1 { ok = false; }
  if col_at(doc, 0) != 1 { ok = false; }
  if line_at(doc, 1) != 1 { ok = false; }
  if col_at(doc, 1) != 4 { ok = false; }
  if !streq(data_at(doc, 1), "\n  ") { ok = false; }
  if line_at(doc, 2) != 2 { ok = false; }
  if col_at(doc, 2) != 3 { ok = false; }
  if !streq(kind_name_at(doc, 3), "end") { ok = false; }
  if line_at(doc, 5) != 3 { ok = false; }
  if col_at(doc, 5) != 1 { ok = false; }
  if !streq(text_content_of(doc, 0), "\n  \n") { ok = false; }
  return assert(ok, "whitespace-only text runs are preserved; line/column track CR/LF boundaries");
}

fn t24() -> TestResult {
  let doc = "<!DOCTYPE d [<!ENTITY e \"X\">]><d><?p &e;?><!--&e;--><![CDATA[&e;]]>&e;</d>";
  var ok = streq(data_at(doc, 2), "&e;");
  if !streq(data_at(doc, 3), "&e;") { ok = false; }
  if !streq(data_at(doc, 4), "&e;") { ok = false; }
  if !streq(data_at(doc, 5), "X") { ok = false; }
  if !streq(text_content_of(doc, 0), "&e;X") { ok = false; }
  return assert(ok, "references expand only in text and attribute values, never in PI/comment/CDATA");
}

fn t25() -> TestResult {
  let big = string.str_repeat("a", 70000);
  let dt = "<!DOCTYPE d [<!ENTITY big \"" + big + "\">]>";
  let doc = dt + "<d>&big;</d>";
  let want = "expat: entity expansion too large at " + convert.int_to_string(dt.len() + 3);
  var ok = err_is(doc, want);
  return assert(ok, "entity expansion is capped (70000-byte payload rejected at the reference)");
}
fn main() -> Int {
  io.println("=== xiom.expat conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.expat: all tests passed");
  } else {
    io.println("xiom.expat: tests failed");
  }
  return failed;
}
