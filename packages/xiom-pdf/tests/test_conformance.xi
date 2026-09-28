// XIOM -- xiom.pdf conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Synthetic PDFs are built byte-by-byte in-test (no fixtures on disk); every
// Str comparison goes through str_compare and every Vec[Str] element read is
// bound to a typed local.

module pdf_tests
use xiom.io; use xiom.test; use xiom.pdf;
use xiom.string;
use xiom.string.compare;
use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn itos(v: Int) -> Str {
  return convert.int_to_string(v);
}

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  io.flush_stdout();
  return 1;
}

fn app(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn appv(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

fn vb(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  app(&mut v, s);
  return v;
}

fn pad10(v: Int) -> Str {
  var s = itos(v);
  while s.len() < 10 {
    s = "0" + s;
  }
  return s;
}

fn pad5(v: Int) -> Str {
  var s = itos(v);
  while s.len() < 5 {
    s = "0" + s;
  }
  return s;
}

fn pos_of(s: &Vec[UInt8], lit: Str) -> Int {
  let n = s.len();
  let m = lit.len();
  if m == 0 { return 0; }
  var i = 0;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if ((s[i + j] as Int) & 0xFF) != ((string.byte_at(lit, j) as Int) & 0xFF) {
        hit = false;
        break;
      }
      j = j + 1;
    }
    if hit { return i; }
    i = i + 1;
  }
  return -1;
}

fn replace_at(v: &mut Vec[UInt8], pos: Int, s: Str) {
  var i = 0;
  while i < s.len() {
    v[pos + i] = string.byte_at(s, i);
    i = i + 1;
  }
}

fn err_has(text: &Vec[UInt8], sub: Str) -> Bool {
  let r = pdf_open(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_contains(e, sub); },
  };
  return false;
}

fn adler32(v: &Vec[UInt8]) -> Int {
  var a = 1;
  var b = 0;
  var i = 0;
  while i < v.len() {
    let x = (v[i] as Int) & 0xFF;
    a = (a + x) % 65521;
    b = (b + a) % 65521;
    i = i + 1;
  }
  return b * 65536 + a;
}

// zlib stream with one stored DEFLATE block and an Adler-32 trailer.
fn zlib_store(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(120 as UInt8);
  out.push(1 as UInt8);
  out.push(1 as UInt8);
  let len = v.len();
  out.push((len % 256) as UInt8);
  out.push((len / 256) as UInt8);
  let nlen = 65535 - len;
  out.push((nlen % 256) as UInt8);
  out.push((nlen / 256) as UInt8);
  var i = 0;
  while i < len {
    out.push(v[i]);
    i = i + 1;
  }
  let ad = adler32(v);
  out.push(((ad / 16777216) % 256) as UInt8);
  out.push(((ad / 65536) % 256) as UInt8);
  out.push(((ad / 256) % 256) as UInt8);
  out.push((ad % 256) as UInt8);
  return out;
}

// Classic-xref file from per-object body strings, numbered 1..n.
fn classic_from_objects(objs: &Vec[Str], root_num: Int, extra: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  app(&mut body, "%PDF-1.4\n");
  var offs = Vec[Int].new();
  var i = 0;
  while i < objs.len() {
    let o: Str = objs[i];
    offs.push(body.len());
    app(&mut body, o);
    i = i + 1;
  }
  let total = objs.len() + 1;
  let xo = body.len();
  app(&mut body, "xref\n0 " + itos(total) + "\n0000000000 65535 f \n");
  i = 0;
  while i < objs.len() {
    let oo: Int = offs[i];
    app(&mut body, pad10(oo) + " 00000 n \n");
    i = i + 1;
  }
  app(&mut body, "trailer\n<< /Size " + itos(total) + " /Root " + itos(root_num) + " 0 R" + extra + " >>\nstartxref\n" + itos(xo) + "\n%%EOF\n");
  return body;
}

fn min_content() -> Str {
  return "BT /F1 24 Tf 100 700 Td (Hello) Tj ET\n";
}

// The canonical one-page document (5 objects, classic xref, direct Length).
fn min_doc() -> Vec[UInt8] {
  let content = min_content();
  var objs = Vec[Str].new();
  objs.push("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  objs.push("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  objs.push("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n");
  objs.push("4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n");
  objs.push("5 0 obj\n<< /Length " + itos(content.len()) + " >>\nstream\n" + content + "endstream\nendobj\n");
  return classic_from_objects(&objs, 1, "");
}

// ---------------------------------------------------------------------------
//  Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let d = min_doc();
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if !streq(pdf_version(&doc), "1.4") { ok = false; }
      let rn = pdf_root_node(&doc);
      if rn < 0 { ok = false; }
      let tv = pdf_dict_get(&doc, rn, "Type");
      if !streq(pdf_node_text(&doc, tv), "Catalog") { ok = false; }
      if pdf_declared_page_count(&doc) != 1 { ok = false; }
      if pdf_page_count(&doc) != 1 { ok = false; }
      if pdf_page_object_num(&doc, 0) != 3 { ok = false; }
      let mb = pdf_page_mediabox_node(&doc, 0);
      if pdf_array_len(&doc, mb) != 4 { ok = false; }
      if pdf_node_int(&doc, pdf_array_item(&doc, mb, 2)) != 612 { ok = false; }
      if pdf_node_int(&doc, pdf_array_item(&doc, mb, 3)) != 792 { ok = false; }
      if !pdf_page_resources_present(&doc, 0) { ok = false; }
      if pdf_page_contents_count(&doc, 0) != 1 { ok = false; }
      let cv = pdf_page_contents_node(&doc, 0, 0);
      if pdf_node_kind(&doc, cv) != 8 { ok = false; }
      let cobj = pdf_deref(&doc, cv);
      if cobj < 0 { ok = false; }
      if pdf_object_offset(&doc, pdf_find_object(&doc, 5)) <= 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "one-page document: header, xref, catalog, page tree, MediaBox, contents");
}

fn t2() -> TestResult {
  var ok = true;
  let src = vb("[ /Name 42 3.5 (s) <4142> <4> true false null ] 7 0 R");
  let r = pdf_lex(&src);
  match r {
    Ok(t) => {
      if pdf_token_count(&t) != 14 { ok = false; }
      if !streq(pdf_token_kind_name(pdf_token_kind(&t, 0)), "array_open") { ok = false; }
      if !streq(pdf_token_kind_name(pdf_token_kind(&t, 1)), "name") { ok = false; }
      if !streq(pdf_token_text(&t, 1), "Name") { ok = false; }
      if pdf_token_int(&t, 2) != 42 { ok = false; }
      if pdf_token_kind(&t, 3) != 1 { ok = false; }
      if !streq(pdf_token_text(&t, 3), "3.5") { ok = false; }
      if !streq(pdf_token_text(&t, 4), "s") { ok = false; }
      if !streq(pdf_token_text(&t, 5), "AB") { ok = false; }
      if !streq(pdf_token_text(&t, 6), "@") { ok = false; }
      if pdf_token_keyword(&t, 7) != 1 { ok = false; }
      if pdf_token_keyword(&t, 8) != 2 { ok = false; }
      if pdf_token_keyword(&t, 9) != 3 { ok = false; }
      if !streq(pdf_token_kind_name(pdf_token_kind(&t, 10)), "array_close") { ok = false; }
      if pdf_token_int(&t, 11) != 7 { ok = false; }
      if pdf_token_int(&t, 12) != 0 { ok = false; }
      if pdf_token_keyword(&t, 13) != 11 { ok = false; }
      if !streq(pdf_keyword_name(11), "R") { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "lexer: names, ints, reals, strings, hex strings, keywords, brackets, R");
}

fn t3() -> TestResult {
  var ok = true;
  var src = Vec[UInt8].new();
  app(&mut src, "(a");
  src.push(92 as UInt8);
  src.push(110 as UInt8);
  app(&mut src, "b");
  src.push(92 as UInt8);
  src.push(116 as UInt8);
  app(&mut src, "c");
  src.push(92 as UInt8);
  app(&mut src, "050d");
  src.push(92 as UInt8);
  src.push(92 as UInt8);
  app(&mut src, "e");
  src.push(92 as UInt8);
  src.push(40 as UInt8);
  app(&mut src, "f");
  src.push(92 as UInt8);
  src.push(41 as UInt8);
  app(&mut src, "g)");
  let r = pdf_lex(&src);
  match r {
    Ok(t) => {
      if pdf_token_count(&t) != 1 { ok = false; }
      if !streq(pdf_token_text(&t, 0), "a\nb\tc(d\\e(f)g") { ok = false; }
      let b = pdf_token_bytes(&t, 0);
      if b.len() != 13 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "literal strings: \\n \\t \\ooo \\\\ \\( \\) escapes decode to the right bytes");
}

fn t4() -> TestResult {
  var ok = true;
  let r1 = pdf_lex(&vb("(a(b)c)"));
  match r1 {
    Ok(t) => { if !streq(pdf_token_text(&t, 0), "a(b)c") { ok = false; } },
    Err(_) => { ok = false; },
  };
  let r2 = pdf_lex(&vb("<48656C6C6F>"));
  match r2 {
    Ok(t) => { if !streq(pdf_token_text(&t, 0), "Hello") { ok = false; } },
    Err(_) => { ok = false; },
  };
  let r3 = pdf_lex(&vb("<48 65 6c 6c 6f>"));
  match r3 {
    Ok(t) => { if !streq(pdf_token_text(&t, 0), "Hello") { ok = false; } },
    Err(_) => { ok = false; },
  };
  var lc = Vec[UInt8].new();
  app(&mut lc, "(a");
  lc.push(92 as UInt8);
  lc.push(13 as UInt8);
  lc.push(10 as UInt8);
  app(&mut lc, "b)");
  let r4 = pdf_lex(&lc);
  match r4 {
    Ok(t) => { if !streq(pdf_token_text(&t, 0), "ab") { ok = false; } },
    Err(_) => { ok = false; },
  };
  return assert(ok, "strings: nested parentheses, hex pairs and spaces, CRLF line continuation");
}

fn t5() -> TestResult {
  var ok = true;
  let r1 = pdf_lex(&vb("/A#42"));
  match r1 {
    Ok(t) => { if !streq(pdf_token_text(&t, 0), "AB") { ok = false; } },
    Err(_) => { ok = false; },
  };
  let r2 = pdf_lex(&vb("/Pa#74h"));
  match r2 {
    Ok(t) => { if !streq(pdf_token_text(&t, 0), "Path") { ok = false; } },
    Err(_) => { ok = false; },
  };
  if !err_has_lex("/A#00", "NUL in name") { ok = false; }
  if !err_has_lex("/A#ZZ", "bad name escape") { ok = false; }
  return assert(ok, "names: #xx escapes decode; NUL and bad escapes are rejected");
}

fn err_has_lex(src: Str, sub: Str) -> Bool {
  let r = pdf_lex(&vb(src));
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_contains(e, sub); },
  };
  return false;
}

fn t6() -> TestResult {
  var ok = true;
  let r = pdf_lex(&vb("+17 -3 34.5 -.002 4. .5"));
  match r {
    Ok(t) => {
      if pdf_token_count(&t) != 6 { ok = false; }
      if pdf_token_int(&t, 0) != 17 { ok = false; }
      if pdf_token_int(&t, 1) != -3 { ok = false; }
      if !streq(pdf_token_text(&t, 2), "34.5") { ok = false; }
      if !streq(pdf_token_text(&t, 3), "-.002") { ok = false; }
      if !streq(pdf_token_text(&t, 4), "4.") { ok = false; }
      if !streq(pdf_token_text(&t, 5), ".5") { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  if !err_has_lex("12abc", "bad number") { ok = false; }
  return assert(ok, "numbers: signs, leading/trailing dots, fractions; digits glued to words rejected");
}

fn t7() -> TestResult {
  var ok = true;
  let r = pdf_lex(&vb("% c\n<<%x\n/Type/Page%y\n>>"));
  match r {
    Ok(t) => {
      if pdf_token_count(&t) != 4 { ok = false; }
      if pdf_token_kind(&t, 0) != 7 { ok = false; }
      if !streq(pdf_token_text(&t, 1), "Type") { ok = false; }
      if !streq(pdf_token_text(&t, 2), "Page") { ok = false; }
      if pdf_token_kind(&t, 3) != 8 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "% comments and whitespace are skipped between tokens");
}

fn t8() -> TestResult {
  var ok = true;
  let content = min_content();
  let d = min_doc();
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if pdf_stream_count(&doc) != 1 { ok = false; }
      if pdf_stream_object(&doc, 0) != 5 { ok = false; }
      if pdf_stream_declared_length(&doc, 0) != content.len() { ok = false; }
      if pdf_stream_data_len(&doc, 0) != content.len() { ok = false; }
      if pdf_stream_length_source(&doc, 0) != 1 { ok = false; }
      if pdf_stream_bounds_scanned(&doc, 0) { ok = false; }
      if pdf_stream_length_indirect(&doc, 0) { ok = false; }
      let sd = pdf_stream_data(&doc, 0);
      if sd.len() != content.len() { ok = false; }
      if ((sd[0] as Int) & 0xFF) != 66 { ok = false; }
      if pdf_page_object_num(&doc, 0) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "streams: direct /Length verified against endstream, raw bytes exposed");
}

fn t9() -> TestResult {
  var ok = true;
  let content = "abc";
  var objs = Vec[Str].new();
  objs.push("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  objs.push("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  objs.push("3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>\nendobj\n");
  objs.push("4 0 obj\n" + itos(content.len()) + "\nendobj\n");
  objs.push("5 0 obj\n<< /Length 4 0 R >>\nstream\n" + content + "endstream\nendobj\n");
  let d = classic_from_objects(&objs, 1, "");
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if pdf_stream_length_source(&doc, 0) != 2 { ok = false; }
      if !pdf_stream_length_indirect(&doc, 0) { ok = false; }
      if pdf_stream_bounds_scanned(&doc, 0) { ok = false; }
      if pdf_stream_data_len(&doc, 0) != 3 { ok = false; }
      let sd = pdf_stream_data(&doc, 0);
      if ((sd[0] as Int) & 0xFF) != 97 { ok = false; }
      if pdf_find_object(&doc, 4) < 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "streams: indirect /Length resolved through the object map");
}

fn t10() -> TestResult {
  var ok = true;
  var objs = Vec[Str].new();
  objs.push("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  objs.push("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  objs.push("3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n");
  objs.push("4 0 obj\n<< /Length 99 0 R >>\nstream\nabc\nendstream\nendobj\n");
  let d = classic_from_objects(&objs, 1, "");
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if pdf_stream_length_source(&doc, 0) != 4 { ok = false; }
      if !pdf_stream_length_indirect(&doc, 0) { ok = false; }
      if !pdf_stream_bounds_scanned(&doc, 0) { ok = false; }
      if pdf_stream_data_len(&doc, 0) != 3 { ok = false; }
      let sd = pdf_stream_data(&doc, 0);
      if ((sd[2] as Int) & 0xFF) != 99 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "streams: unresolvable indirect /Length falls back to the endstream scan and is flagged");
}

fn t11() -> TestResult {
  var ok = true;
  let base = min_doc();
  let r0 = pdf_open(&base);
  var xo1 = -1;
  match r0 {
    Ok(doc) => { xo1 = pdf_xref_section_offset(&doc, 0); },
    Err(_) => { xo1 = -1; },
  };
  if xo1 < 0 {
    return assert(false, "incremental update: base document failed to open");
  }
  var up = Vec[UInt8].new();
  appv(&mut up, &base);
  let obj3 = up.len();
  app(&mut up, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 200] /Contents 5 0 R >>\nendobj\n");
  let xo2 = up.len();
  app(&mut up, "xref\n3 1\n" + pad10(obj3) + " 00000 n \n");
  app(&mut up, "trailer\n<< /Size 6 /Root 1 0 R /Prev " + itos(xo1) + " >>\nstartxref\n" + itos(xo2) + "\n%%EOF\n");
  let r = pdf_open(&up);
  match r {
    Ok(doc) => {
      if pdf_xref_section_count(&doc) != 2 { ok = false; }
      if pdf_trailer_prev(&doc) != xo1 { ok = false; }
      if pdf_xref_section_offset(&doc, 1) != xo1 { ok = false; }
      let mb = pdf_page_mediabox_node(&doc, 0);
      if pdf_array_len(&doc, mb) != 4 { ok = false; }
      if pdf_node_int(&doc, pdf_array_item(&doc, mb, 2)) != 100 { ok = false; }
      if pdf_node_int(&doc, pdf_array_item(&doc, mb, 3)) != 200 { ok = false; }
      if pdf_page_count(&doc) != 1 { ok = false; }
      if pdf_find_object(&doc, 5) < 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "incremental update: /Prev chain walked, newest object wins");
}

// Xref-stream document (objects 1..3 + xref stream object 4). The entry
// table is 5 entries of [type, offset-hi, offset-lo, gen].
fn build_xref_stream_doc(compressed: Int) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  app(&mut body, "%PDF-1.5\n");
  var offs = Vec[Int].new();
  offs.push(body.len());
  app(&mut body, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  offs.push(body.len());
  app(&mut body, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  offs.push(body.len());
  app(&mut body, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>\nendobj\n");
  let xo = body.len();
  var ed = Vec[UInt8].new();
  ed.push(0 as UInt8);
  ed.push(0 as UInt8);
  ed.push(0 as UInt8);
  ed.push(255 as UInt8);
  var i = 0;
  while i < 3 {
    let o: Int = offs[i];
    ed.push(1 as UInt8);
    ed.push(((o / 256) % 256) as UInt8);
    ed.push((o % 256) as UInt8);
    ed.push(0 as UInt8);
    i = i + 1;
  }
  ed.push(1 as UInt8);
  ed.push(((xo / 256) % 256) as UInt8);
  ed.push((xo % 256) as UInt8);
  ed.push(0 as UInt8);
  var store = Vec[UInt8].new();
  var filt = "";
  if compressed == 1 {
    store = zlib_store(&ed);
    filt = " /Filter /FlateDecode";
  } else {
    appv(&mut store, &ed);
  }
  app(&mut body, "4 0 obj\n<< /Type /XRef /Size 5 /W [1 2 1] /Index [0 5] /Root 1 0 R" + filt + " /Length " + itos(store.len()) + " >>\nstream\n");
  appv(&mut body, &store);
  app(&mut body, "\nendstream\nendobj\n");
  app(&mut body, "startxref\n" + itos(xo) + "\n%%EOF\n");
  return body;
}

fn t12() -> TestResult {
  var ok = true;
  let d = build_xref_stream_doc(0);
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if pdf_xref_type(&doc) != 2 { ok = false; }
      if !streq(pdf_xref_type_name(pdf_xref_type(&doc)), "stream") { ok = false; }
      if pdf_find_object(&doc, 1) < 0 { ok = false; }
      if pdf_find_object(&doc, 3) < 0 { ok = false; }
      if pdf_page_count(&doc) != 1 { ok = false; }
      let mb = pdf_page_mediabox_node(&doc, 0);
      if pdf_node_int(&doc, pdf_array_item(&doc, mb, 2)) != 200 { ok = false; }
      if pdf_stream_count(&doc) < 1 { ok = false; }
      if pdf_stream_object(&doc, 0) != 4 { ok = false; }
      let sd = pdf_stream_data(&doc, 0);
      if sd.len() != 20 { ok = false; }
      if pdf_xref_count(&doc) != 5 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "xref streams: /W + /Index entries decoded from raw data; raw stream exposed");
}

fn t13() -> TestResult {
  var ok = true;
  let d = build_xref_stream_doc(1);
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if pdf_xref_type(&doc) != 2 { ok = false; }
      if pdf_find_object(&doc, 3) < 0 { ok = false; }
      if pdf_page_count(&doc) != 1 { ok = false; }
      let mb = pdf_page_mediabox_node(&doc, 0);
      if pdf_node_int(&doc, pdf_array_item(&doc, mb, 3)) != 300 { ok = false; }
      if !streq(pdf_xref_decode_error(&doc), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "xref streams: FlateDecode entries inflate cleanly (local DEFLATE decoder)");
}

// Hybrid file: classic table for objects 0..3 plus /XRefStm adding object 5
// (the Info dictionary) and the stream object 4 itself.
fn build_hybrid_doc() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  app(&mut body, "%PDF-1.5\n");
  var offs = Vec[Int].new();
  offs.push(body.len());
  app(&mut body, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  offs.push(body.len());
  app(&mut body, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  offs.push(body.len());
  app(&mut body, "3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n");
  offs.push(body.len());
  app(&mut body, "5 0 obj\n<< /Title (FromStream) >>\nendobj\n");
  let xo = body.len();
  var ed = Vec[UInt8].new();
  ed.push(0 as UInt8);
  ed.push(0 as UInt8);
  ed.push(0 as UInt8);
  ed.push(255 as UInt8);
  var i = 0;
  while i < 3 {
    let o: Int = offs[i];
    ed.push(1 as UInt8);
    ed.push(((o / 256) % 256) as UInt8);
    ed.push((o % 256) as UInt8);
    ed.push(0 as UInt8);
    i = i + 1;
  }
  ed.push(1 as UInt8);
  ed.push(((xo / 256) % 256) as UInt8);
  ed.push((xo % 256) as UInt8);
  ed.push(0 as UInt8);
  let o5: Int = offs[3];
  ed.push(1 as UInt8);
  ed.push(((o5 / 256) % 256) as UInt8);
  ed.push((o5 % 256) as UInt8);
  ed.push(0 as UInt8);
  app(&mut body, "4 0 obj\n<< /Type /XRef /Size 6 /W [1 2 1] /Index [0 6] /Root 1 0 R /Info 5 0 R /Length " + itos(ed.len()) + " >>\nstream\n");
  appv(&mut body, &ed);
  app(&mut body, "\nendstream\nendobj\n");
  let txo = body.len();
  app(&mut body, "xref\n0 4\n0000000000 65535 f \n");
  i = 0;
  while i < 3 {
    let oo: Int = offs[i];
    app(&mut body, pad10(oo) + " 00000 n \n");
    i = i + 1;
  }
  app(&mut body, "trailer\n<< /Size 6 /Root 1 0 R /XRefStm " + itos(xo) + " >>\nstartxref\n" + itos(txo) + "\n%%EOF\n");
  return body;
}

fn t14() -> TestResult {
  var ok = true;
  let d = build_hybrid_doc();
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if pdf_xref_type(&doc) != 3 { ok = false; }
      if !streq(pdf_xref_type_name(pdf_xref_type(&doc)), "hybrid") { ok = false; }
      if pdf_find_object(&doc, 5) < 0 { ok = false; }
      if pdf_trailer_info_num(&doc) != 5 { ok = false; }
      if !streq(pdf_info_title(&doc), "FromStream") { ok = false; }
      if pdf_page_count(&doc) != 1 { ok = false; }
      if pdf_find_object(&doc, 4) < 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "hybrid files: /XRefStm entries merged over the classic table");
}

fn t15() -> TestResult {
  var ok = true;
  var objs = Vec[Str].new();
  objs.push("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  objs.push("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  objs.push("3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n");
  objs.push("4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n");
  objs.push("5 0 obj\n<< /Type /Font >>\nendobj\n");
  objs.push("6 0 obj\n<< /Filter /Standard /V 1 /R 2 /O (x) /U (y) >>\nendobj\n");
  let d = classic_from_objects(&objs, 1, " /Encrypt 6 0 R");
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if !pdf_is_encrypted(&doc) { ok = false; }
      if pdf_encrypt_num(&doc) != 6 { ok = false; }
      if pdf_page_count(&doc) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "encrypted documents are flagged (/Encrypt present), never decrypted");
}

fn t16() -> TestResult {
  var ok = true;
  var objs = Vec[Str].new();
  objs.push("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  objs.push("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  objs.push("3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n");
  objs.push("4 0 obj\n<< /Type /Font >>\nendobj\n");
  objs.push("5 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n");
  objs.push("6 0 obj\n<< /Title (T) /Author (A) /Subject (S) /CreationDate (D:20260101) /Producer (P) >>\nendobj\n");
  let d = classic_from_objects(&objs, 1, " /Info 6 0 R");
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if !streq(pdf_info_title(&doc), "T") { ok = false; }
      if !streq(pdf_info_author(&doc), "A") { ok = false; }
      if !streq(pdf_info_subject(&doc), "S") { ok = false; }
      if !streq(pdf_info_creation_date(&doc), "D:20260101") { ok = false; }
      if !streq(pdf_info_field(&doc, "Producer"), "P") { ok = false; }
      let sp = pdf_info_span(&doc, 0);
      if sp.len() != 2 { ok = false; }
      if pdf_info_node(&doc) < 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "Info dictionary: Title/Author/Subject/CreationDate text and pool spans");
}

fn t17() -> TestResult {
  var ok = true;
  let d = classic_from_objects(&min_objs(), 1, " /ID [<414243> <444546>]");
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if !pdf_has_id(&doc) { ok = false; }
      if !streq(pdf_id(&doc, 0), "ABC") { ok = false; }
      if !streq(pdf_id(&doc, 1), "DEF") { ok = false; }
      let sp = pdf_id_span(&doc, 0);
      if sp.len() != 2 { ok = false; }
      if pdf_id(&doc, 2) != "" { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "trailer /ID: both hex strings decoded, spans exposed");
}

fn min_objs() -> Vec[Str] {
  let content = min_content();
  var objs = Vec[Str].new();
  objs.push("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  objs.push("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  objs.push("3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n");
  objs.push("4 0 obj\n<< /Type /Font >>\nendobj\n");
  objs.push("5 0 obj\n<< /Length " + itos(content.len()) + " >>\nstream\n" + content + "endstream\nendobj\n");
  return objs;
}

fn t18() -> TestResult {
  var ok = true;
  let nox = vb("%PDF-1.4\n1 0 obj\n<< >>\nendobj\n");
  if !err_has(&nox, "missing startxref") { ok = false; }
  let noh = vb("1 0 obj\n<< >>\nendobj\nstartxref\n0\n%%EOF\n");
  if !err_has(&noh, "missing PDF header") { ok = false; }
  var bad = min_doc();
  let p = pos_of(&bad, " 00000 n \n");
  if p < 0 { ok = false; }
  replace_at(&mut bad, p + 7, "x");
  if !err_has(&bad, "malformed xref entry") { ok = false; }
  return assert(ok, "malformed documents: missing startxref, missing header, malformed xref entry");
}

fn t19() -> TestResult {
  var ok = true;
  var bad = min_doc();
  let p1 = pos_of(&bad, "1 0 obj");
  if p1 < 0 { ok = false; }
  replace_at(&mut bad, p1, "x");
  if !err_has(&bad, "bad object header") { ok = false; }
  var mm = min_doc();
  let p2 = pos_of(&mm, "1 0 obj");
  replace_at(&mut mm, p2, "7 0 obj");
  if !err_has(&mm, "object header mismatch") { ok = false; }
  return assert(ok, "xref entries pointing at bad or mismatched object headers are rejected");
}

fn t20() -> TestResult {
  var ok = true;
  var o1 = Vec[Str].new();
  o1.push("1 0 obj\n(abc\nendobj\n");
  let d1 = classic_from_objects(&o1, 1, "");
  if !err_has(&d1, "unterminated string") { ok = false; }
  var o2 = Vec[Str].new();
  o2.push("1 0 obj\n<41\n");
  let d2 = classic_from_objects(&o2, 1, "");
  if !err_has(&d2, "bad hex digit") { ok = false; }
  var o3 = Vec[Str].new();
  o3.push("1 0 obj\n<< /A#Z 1 >>\nendobj\n");
  let d3 = classic_from_objects(&o3, 1, "");
  if !err_has(&d3, "bad name escape") { ok = false; }
  return assert(ok, "lexical errors inside objects: unterminated string, bad hex digit, bad name escape");
}

fn t21() -> TestResult {
  var ok = true;
  var o1 = Vec[Str].new();
  o1.push("1 0 obj\n<< /A 1 >>\n");
  let d1 = classic_from_objects(&o1, 1, "");
  if !err_has(&d1, "missing endobj") { ok = false; }
  var o2 = Vec[Str].new();
  o2.push("1 0 obj\n<< >>\nstream\nabc\nendstream\nendobj\n");
  let d2 = classic_from_objects(&o2, 1, "");
  if !err_has(&d2, "missing /Length") { ok = false; }
  var o3 = Vec[Str].new();
  o3.push("1 0 obj\n<< /Length (x) >>\nstream\nabc\nendstream\nendobj\n");
  let d3 = classic_from_objects(&o3, 1, "");
  if !err_has(&d3, "bad /Length value") { ok = false; }
  return assert(ok, "object structure errors: missing endobj, missing /Length, non-numeric /Length");
}

fn t22() -> TestResult {
  var ok = true;
  var o1 = Vec[Str].new();
  o1.push("1 0 obj\n<< /Length 3 >>\nstream abc\nendstream\nendobj\n");
  let d1 = classic_from_objects(&o1, 1, "");
  if !err_has(&d1, "stream keyword not followed by LF or CRLF") { ok = false; }
  return assert(ok, "stream keyword must be followed by LF or CRLF (lone space rejected)");
}

// Object-stream document: objects 1..3 in the classic sense, the ObjStm as
// object 6, objects 10/11 inside it, and an xref stream as object 7.
fn build_objstm_doc() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  app(&mut body, "%PDF-1.5\n");
  var offs = Vec[Int].new();
  offs.push(body.len());
  app(&mut body, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  offs.push(body.len());
  app(&mut body, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
  offs.push(body.len());
  app(&mut body, "3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n");
  let pairs = "10 0 11 11 ";
  let payload = pairs + "<< /A 1 >>" + " " + "<< /B 2 >>";
  offs.push(body.len());
  app(&mut body, "6 0 obj\n<< /Type /ObjStm /N 2 /First " + itos(pairs.len()) + " /Length " + itos(payload.len()) + " >>\nstream\n" + payload + "\nendstream\nendobj\n");
  let xo = body.len();
  var ed = Vec[UInt8].new();
  ed.push(0 as UInt8);
  ed.push(0 as UInt8);
  ed.push(0 as UInt8);
  ed.push(255 as UInt8);
  var i = 0;
  while i < 3 {
    let o: Int = offs[i];
    ed.push(1 as UInt8);
    ed.push(((o / 256) % 256) as UInt8);
    ed.push((o % 256) as UInt8);
    ed.push(0 as UInt8);
    i = i + 1;
  }
  var k = 0;
  while k < 2 {
    ed.push(0 as UInt8);
    ed.push(0 as UInt8);
    ed.push(0 as UInt8);
    ed.push(0 as UInt8);
    k = k + 1;
  }
  let o6: Int = offs[3];
  ed.push(1 as UInt8);
  ed.push(((o6 / 256) % 256) as UInt8);
  ed.push((o6 % 256) as UInt8);
  ed.push(0 as UInt8);
  ed.push(1 as UInt8);
  ed.push(((xo / 256) % 256) as UInt8);
  ed.push((xo % 256) as UInt8);
  ed.push(0 as UInt8);
  ed.push(2 as UInt8);
  ed.push(0 as UInt8);
  ed.push(6 as UInt8);
  ed.push(0 as UInt8);
  ed.push(2 as UInt8);
  ed.push(0 as UInt8);
  ed.push(6 as UInt8);
  ed.push(1 as UInt8);
  app(&mut body, "7 0 obj\n<< /Type /XRef /Size 12 /W [1 2 1] /Index [0 8 10 2] /Root 1 0 R /Length " + itos(ed.len()) + " >>\nstream\n");
  appv(&mut body, &ed);
  app(&mut body, "\nendstream\nendobj\n");
  app(&mut body, "startxref\n" + itos(xo) + "\n%%EOF\n");
  return body;
}

fn t23() -> TestResult {
  var ok = true;
  let d = build_objstm_doc();
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if !pdf_objstm_used(&doc) { ok = false; }
      let f10 = pdf_find_object(&doc, 10);
      if f10 < 0 { ok = false; }
      if !pdf_object_from_objstm(&doc, f10) { ok = false; }
      let n10 = pdf_object_node(&doc, f10);
      let av = pdf_dict_get(&doc, n10, "A");
      if pdf_node_int(&doc, av) != 1 { ok = false; }
      let f11 = pdf_find_object(&doc, 11);
      let n11 = pdf_object_node(&doc, f11);
      let bv = pdf_dict_get(&doc, n11, "B");
      if pdf_node_int(&doc, bv) != 2 { ok = false; }
      if pdf_page_count(&doc) != 1 { ok = false; }
      if pdf_xref_kind(&doc, pdf_xref_find(&doc, 10)) != 2 { ok = false; }
      if pdf_xref_kind(&doc, pdf_xref_find(&doc, 11)) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "object streams: type-2 xref entries decoded, /N pairs parsed, objects merged");
}

fn bytes_text(v: &Vec[UInt8]) -> Str {
  var i = 0;
  while i < v.len() {
    if ((v[i] as Int) & 0xFF) == 0 { return ""; }
    i = i + 1;
  }
  var c = Vec[UInt8].new();
  i = 0;
  while i < v.len() {
    c.push(v[i]);
    i = i + 1;
  }
  return Str::from_utf8(c);
}

fn t24() -> TestResult {
  var ok = true;
  var def = Vec[UInt8].new();
  def.push(109 as UInt8);
  def.push(82 as UInt8);
  def.push(201 as UInt8);
  def.push(1 as UInt8);
  def.push(195 as UInt8);
  def.push(48 as UInt8);
  def.push(8 as UInt8);
  def.push(155 as UInt8);
  def.push(21 as UInt8);
  def.push(9 as UInt8);
  def.push(246 as UInt8);
  def.push(95 as UInt8);
  def.push(161 as UInt8);
  def.push(49 as UInt8);
  def.push(183 as UInt8);
  def.push(147 as UInt8);
  def.push(58 as UInt8);
  def.push(143 as UInt8);
  def.push(96 as UInt8);
  def.push(14 as UInt8);
  def.push(33 as UInt8);
  def.push(132 as UInt8);
  def.push(133 as UInt8);
  def.push(114 as UInt8);
  def.push(142 as UInt8);
  def.push(81 as UInt8);
  def.push(234 as UInt8);
  def.push(131 as UInt8);
  def.push(196 as UInt8);
  def.push(65 as UInt8);
  def.push(24 as UInt8);
  def.push(79 as UInt8);
  def.push(220 as UInt8);
  def.push(206 as UInt8);
  def.push(95 as UInt8);
  def.push(143 as UInt8);
  def.push(69 as UInt8);
  def.push(208 as UInt8);
  def.push(243 as UInt8);
  def.push(59 as UInt8);
  def.push(196 as UInt8);
  def.push(180 as UInt8);
  def.push(3 as UInt8);
  def.push(165 as UInt8);
  def.push(126 as UInt8);
  def.push(110 as UInt8);
  def.push(153 as UInt8);
  def.push(220 as UInt8);
  def.push(64 as UInt8);
  def.push(21 as UInt8);
  def.push(245 as UInt8);
  def.push(43 as UInt8);
  def.push(226 as UInt8);
  def.push(242 as UInt8);
  def.push(160 as UInt8);
  def.push(193 as UInt8);
  def.push(28 as UInt8);
  def.push(55 as UInt8);
  def.push(195 as UInt8);
  def.push(224 as UInt8);
  def.push(74 as UInt8);
  def.push(207 as UInt8);
  def.push(86 as UInt8);
  def.push(136 as UInt8);
  def.push(78 as UInt8);
  def.push(140 as UInt8);
  def.push(132 as UInt8);
  def.push(196 as UInt8);
  def.push(100 as UInt8);
  def.push(101 as UInt8);
  def.push(57 as UInt8);
  def.push(251 as UInt8);
  def.push(244 as UInt8);
  def.push(181 as UInt8);
  def.push(3 as UInt8);
  def.push(205 as UInt8);
  def.push(170 as UInt8);
  def.push(107 as UInt8);
  def.push(170 as UInt8);
  def.push(112 as UInt8);
  def.push(134 as UInt8);
  def.push(114 as UInt8);
  def.push(83 as UInt8);
  def.push(145 as UInt8);
  def.push(78 as UInt8);
  def.push(86 as UInt8);
  def.push(255 as UInt8);
  def.push(69 as UInt8);
  def.push(182 as UInt8);
  def.push(165 as UInt8);
  def.push(104 as UInt8);
  def.push(167 as UInt8);
  def.push(3 as UInt8);
  def.push(163 as UInt8);
  def.push(93 as UInt8);
  def.push(69 as UInt8);
  def.push(141 as UInt8);
  def.push(196 as UInt8);
  def.push(82 as UInt8);
  def.push(110 as UInt8);
  def.push(201 as UInt8);
  def.push(16 as UInt8);
  def.push(202 as UInt8);
  def.push(133 as UInt8);
  def.push(195 as UInt8);
  def.push(182 as UInt8);
  def.push(82 as UInt8);
  def.push(38 as UInt8);
  def.push(144 as UInt8);
  def.push(247 as UInt8);
  def.push(105 as UInt8);
  def.push(125 as UInt8);
  def.push(208 as UInt8);
  def.push(105 as UInt8);
  def.push(176 as UInt8);
  def.push(102 as UInt8);
  def.push(156 as UInt8);
  def.push(146 as UInt8);
  def.push(77 as UInt8);
  def.push(217 as UInt8);
  def.push(105 as UInt8);
  def.push(10 as UInt8);
  def.push(202 as UInt8);
  def.push(158 as UInt8);
  def.push(122 as UInt8);
  def.push(221 as UInt8);
  def.push(0 as UInt8);
  def.push(157 as UInt8);
  def.push(17 as UInt8);
  def.push(94 as UInt8);
  def.push(189 as UInt8);
  def.push(224 as UInt8);
  def.push(164 as UInt8);
  def.push(158 as UInt8);
  def.push(141 as UInt8);
  def.push(106 as UInt8);
  def.push(77 as UInt8);
  def.push(204 as UInt8);
  def.push(152 as UInt8);
  def.push(201 as UInt8);
  def.push(46 as UInt8);
  def.push(242 as UInt8);
  def.push(216 as UInt8);
  def.push(132 as UInt8);
  def.push(139 as UInt8);
  def.push(225 as UInt8);
  def.push(12 as UInt8);
  def.push(31 as UInt8);
  def.push(178 as UInt8);
  def.push(241 as UInt8);
  def.push(128 as UInt8);
  def.push(204 as UInt8);
  def.push(29 as UInt8);
  def.push(254 as UInt8);
  def.push(241 as UInt8);
  def.push(86 as UInt8);
  def.push(224 as UInt8);
  def.push(162 as UInt8);
  def.push(152 as UInt8);
  def.push(171 as UInt8);
  def.push(214 as UInt8);
  def.push(92 as UInt8);
  def.push(40 as UInt8);
  def.push(195 as UInt8);
  def.push(185 as UInt8);
  def.push(10 as UInt8);
  def.push(48 as UInt8);
  def.push(79 as UInt8);
  def.push(160 as UInt8);
  def.push(246 as UInt8);
  def.push(209 as UInt8);
  def.push(210 as UInt8);
  def.push(125 as UInt8);
  def.push(68 as UInt8);
  def.push(75 as UInt8);
  def.push(77 as UInt8);
  def.push(52 as UInt8);
  def.push(218 as UInt8);
  def.push(15 as UInt8);
  def.push(57 as UInt8);
  def.push(205 as UInt8);
  def.push(153 as UInt8);
  def.push(14 as UInt8);
  def.push(130 as UInt8);
  def.push(222 as UInt8);
  def.push(5 as UInt8);
  def.push(246 as UInt8);
  def.push(158 as UInt8);
  def.push(202 as UInt8);
  def.push(25 as UInt8);
  def.push(233 as UInt8);
  def.push(122 as UInt8);
  def.push(38 as UInt8);
  def.push(84 as UInt8);
  def.push(78 as UInt8);
  def.push(74 as UInt8);
  def.push(72 as UInt8);
  def.push(179 as UInt8);
  def.push(222 as UInt8);
  def.push(219 as UInt8);
  def.push(230 as UInt8);
  def.push(160 as UInt8);
  def.push(3 as UInt8);
  def.push(32 as UInt8);
  def.push(250 as UInt8);
  def.push(103 as UInt8);
  def.push(165 as UInt8);
  def.push(187 as UInt8);
  def.push(40 as UInt8);
  def.push(214 as UInt8);
  def.push(133 as UInt8);
  def.push(122 as UInt8);
  def.push(234 as UInt8);
  def.push(21 as UInt8);
  def.push(128 as UInt8);
  def.push(252 as UInt8);
  def.push(0 as UInt8);
  let r1 = pdf_flate_decode(&def);
  match r1 {
    Ok(v) => {
      if v.len() != 900 { ok = false; }
      if ((v[0] as Int) & 0xFF) != 97 { ok = false; }
      if ((v[899] as Int) & 0xFF) != 97 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  let plain = vb("zlib round trip");
  let z = zlib_store(&plain);
  let r2 = pdf_zlib_decode(&z);
  match r2 {
    Ok(v) => { if !streq(bytes_text(&v), "zlib round trip") { ok = false; } },
    Err(_) => { ok = false; },
  };
  let bad = vb("not a zlib stream at all");
  let r3 = pdf_flate_decode(&bad);
  match r3 {
    Ok(_) => { ok = false; },
    Err(_) => {},
  };
  return assert(ok, "flate: dynamic-Huffman DEFLATE decodes to 900 bytes; zlib stored block round-trips; junk rejected");
}

fn t25() -> TestResult {
  var ok = true;
  var objs = Vec[Str].new();
  objs.push("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  objs.push("2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>\nendobj\n");
  objs.push("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 20] >>\nendobj\n");
  objs.push("4 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 30 40] >>\nendobj\n");
  let d = classic_from_objects(&objs, 1, "");
  let r = pdf_open(&d);
  match r {
    Ok(doc) => {
      if pdf_declared_page_count(&doc) != 2 { ok = false; }
      if pdf_page_count(&doc) != 2 { ok = false; }
      if pdf_page_object_num(&doc, 0) != 3 { ok = false; }
      if pdf_page_object_num(&doc, 1) != 4 { ok = false; }
      let mb1 = pdf_page_mediabox_node(&doc, 1);
      if pdf_node_int(&doc, pdf_array_item(&doc, mb1, 2)) != 30 { ok = false; }
      let fi = pdf_xref_find(&doc, 0);
      if fi < 0 { ok = false; }
      if pdf_xref_kind(&doc, fi) != 0 { ok = false; }
      if pdf_find_object(&doc, 0) >= 0 { ok = false; }
      if !streq(pdf_xref_kind_name(0), "free") { ok = false; }
      if pdf_page_node(&doc, 5) != -1 { ok = false; }
      if pdf_page_count(&doc) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  };
  return assert(ok, "two-page tree: Kids order, Count, MediaBox; free entries stay free");
}



fn main() -> Int {
  io.println("=== xiom.pdf conformance tests ===");
  io.flush_stdout();
  var failed = 0;
  failed = failed + report(t1());
  failed = failed + report(t2());
  failed = failed + report(t3());
  failed = failed + report(t4());
  failed = failed + report(t5());
  failed = failed + report(t6());
  failed = failed + report(t7());
  failed = failed + report(t8());
  failed = failed + report(t9());
  failed = failed + report(t10());
  failed = failed + report(t11());
  failed = failed + report(t12());
  failed = failed + report(t13());
  failed = failed + report(t14());
  failed = failed + report(t15());
  failed = failed + report(t16());
  failed = failed + report(t17());
  failed = failed + report(t18());
  failed = failed + report(t19());
  failed = failed + report(t20());
  failed = failed + report(t21());
  failed = failed + report(t22());
  failed = failed + report(t23());
  failed = failed + report(t24());
  failed = failed + report(t25());
  if failed == 0 {
    io.println("xiom.pdf: all tests passed");
  } else {
    io.println("xiom.pdf: tests failed");
  }
  return failed;
}
