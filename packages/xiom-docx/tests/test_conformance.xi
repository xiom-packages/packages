// XIOM -- xiom.docx conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic in-memory tests (no external files): document model
// round trips at ZIP level 0 and 6, ZIP container structure and error
// paths (bad signatures, truncation, CRC, unsupported method), the
// document.xml subset (paragraph/run/text/bold/italic/size, escaping,
// UTF-8, entities) and the stored + fixed-Huffman inflater.
//
// Harness style mirrors xiom.parquet: one fn tN() -> Int per test, called
// directly from main; each test prints exactly one [PASS]/[FAIL] line and
// returns 0/1. Str values are compared with str_compare.

module docx_tests
use xiom.io;
use xiom.string;
use xiom.string.compare;
use xiom.convert;
use xiom.compress.deflate;
use xiom.docx;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  };
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  };
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    };
    i = i + 1;
  };
  return true;
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    out.push(b);
    i = i + 1;
  };
  return out;
}

fn bytes_contain(hay: &Vec[UInt8], needle: Str) -> Bool {
  let nlen = string.str_len(needle);
  if nlen == 0 {
    return true;
  };
  var i = 0;
  while i + nlen <= hay.len() {
    var ok = true;
    var k = 0;
    while k < nlen {
      let a: UInt8 = hay[i + k];
      let b: UInt8 = string.byte_at(needle, k);
      if a != b {
        ok = false;
        k = nlen;
      } else {
        k = k + 1;
      };
    };
    if ok {
      return true;
    };
    i = i + 1;
  };
  return false;
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  };
  return str_eq(r.error, want);
}

fn docx_err_is(r: Result[DocxDoc, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  };
  return str_eq(r.error, want);
}

fn zip_err_is(r: Result[DocxZip, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  };
  return str_eq(r.error, want);
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  };
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Fixtures and byte builders
// --------------------------------------------------

fn build_sample() -> DocxDoc {
  var d = docx_new();
  docx_add_paragraph(&mut d);
  docx_add_run(&mut d, "Hello ", false, false, 0);
  docx_add_run(&mut d, "world", true, false, 0);
  docx_add_paragraph(&mut d);
  docx_add_run(&mut d, "Second", false, false, 0);
  return d;
}

fn build_styled() -> DocxDoc {
  var d = docx_new();
  docx_add_paragraph(&mut d);
  docx_add_run(&mut d, "a", false, false, 0);
  docx_add_run(&mut d, "b", true, false, 0);
  docx_add_run(&mut d, "c", false, true, 0);
  docx_add_run(&mut d, "d", true, true, 48);
  return d;
}

fn push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var q = v;
  var i = 0;
  while i < size {
    out.push((q % 256) as UInt8);
    q = q / 256;
    i = i + 1;
  };
}

fn put_str(out: &mut Vec[UInt8], s: Str) {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  };
}

// A hand-built one-entry ZIP whose method (12) is unsupported.
fn craft_bad_method_zip() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_le(&mut out, 0x04034B50, 4);
  push_le(&mut out, 20, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 12, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 0x21, 2);
  push_le(&mut out, 0, 4);
  push_le(&mut out, 0, 4);
  push_le(&mut out, 0, 4);
  push_le(&mut out, 5, 2);
  push_le(&mut out, 0, 2);
  put_str(&mut out, "a.txt");
  let cd_off = out.len();
  push_le(&mut out, 0x02014B50, 4);
  push_le(&mut out, 20, 2);
  push_le(&mut out, 20, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 12, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 0x21, 2);
  push_le(&mut out, 0, 4);
  push_le(&mut out, 0, 4);
  push_le(&mut out, 0, 4);
  push_le(&mut out, 5, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 0, 4);
  push_le(&mut out, 0, 4);
  put_str(&mut out, "a.txt");
  let cd_size = out.len() - cd_off;
  push_le(&mut out, 0x06054B50, 4);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 0, 2);
  push_le(&mut out, 1, 2);
  push_le(&mut out, 1, 2);
  push_le(&mut out, cd_size, 4);
  push_le(&mut out, cd_off, 4);
  push_le(&mut out, 0, 2);
  return out;
}

// A .docx-shaped ZIP whose word/document.xml is `xml_text`.
fn pack_doc_xml(xml_text: Str) -> Vec[UInt8] {
  var ct = bytes_of("<Types/>");
  var rels = bytes_of("<Relationships/>");
  var xml = bytes_of(xml_text);
  var w = docx_zip_writer_new();
  docx_zip_writer_add(&mut w, "[Content_Types].xml", &ct, 6);
  docx_zip_writer_add(&mut w, "_rels/.rels", &rels, 6);
  docx_zip_writer_add(&mut w, "word/document.xml", &xml, 6);
  return docx_zip_writer_finish(&mut w);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> Int {
  return report(str_eq(docx_version(), "0.1.0"), "version is 0.1.0");
}

fn t2() -> Int {
  var d = docx_new();
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "empty document round trip");
  };
  let buf: Vec[UInt8] = br.value;
  let dr = docx_from_bytes(&buf);
  if !dr.is_ok {
    return report(false, "empty document round trip");
  };
  let d2: DocxDoc = dr.value;
  let ok = docx_paragraph_count(&d2) == 0 && docx_run_count(&d2) == 0;
  return report(ok, "empty document round trip");
}

fn t3() -> Int {
  var d = build_sample();
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "two paragraphs and three runs round trip");
  };
  let buf: Vec[UInt8] = br.value;
  let dr = docx_from_bytes(&buf);
  if !dr.is_ok {
    return report(false, "two paragraphs and three runs round trip");
  };
  let d2: DocxDoc = dr.value;
  var ok = docx_paragraph_count(&d2) == 2;
  if ok {
    let p0 = docx_paragraph_text(&d2, 0);
    let p1 = docx_paragraph_text(&d2, 1);
    if !p0.is_ok || !p1.is_ok {
      ok = false;
    } else {
      ok = str_eq(p0.value, "Hello world") && str_eq(p1.value, "Second");
    };
  };
  return report(ok, "two paragraphs and three runs round trip");
}

fn t4() -> Int {
  var d = build_styled();
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "bold/italic/size round trip");
  };
  let buf: Vec[UInt8] = br.value;
  let dr = docx_from_bytes(&buf);
  if !dr.is_ok {
    return report(false, "bold/italic/size round trip");
  };
  let d2: DocxDoc = dr.value;
  var ok = docx_run_count(&d2) == 4;
  if ok {
    let b1 = docx_run_bold(&d2, 1);
    let i2 = docx_run_italic(&d2, 2);
    let b3 = docx_run_bold(&d2, 3);
    let i3 = docx_run_italic(&d2, 3);
    let s3 = docx_run_size(&d2, 3);
    let t3r = docx_run_text(&d2, 3);
    if !b1.is_ok || !i2.is_ok || !b3.is_ok || !i3.is_ok || !s3.is_ok || !t3r.is_ok {
      ok = false;
    } else {
      ok = b1.value && i2.value && b3.value && i3.value && s3.value == 48 && str_eq(t3r.value, "d");
    };
  };
  return report(ok, "bold/italic/size round trip");
}

fn t5() -> Int {
  var d = build_sample();
  let br = docx_to_bytes_level(&d, 0);
  if !br.is_ok {
    return report(false, "stored (level 0) document round trip");
  };
  let buf: Vec[UInt8] = br.value;
  let dr = docx_from_bytes(&buf);
  if !dr.is_ok {
    return report(false, "stored (level 0) document round trip");
  };
  let d2: DocxDoc = dr.value;
  let zr = docx_zip_open(&buf);
  var ok = docx_paragraph_count(&d2) == 2 && zr.is_ok;
  if ok {
    let z: DocxZip = zr.value;
    let di = docx_zip_find(&z, "word/document.xml");
    if di < 0 {
      ok = false;
    } else {
      let m = docx_zip_entry_method(&z, di);
      ok = m.is_ok && m.value == 0;
    };
  };
  return report(ok, "stored (level 0) document round trip");
}

fn t6() -> Int {
  var d = build_sample();
  let b1 = docx_to_bytes(&d);
  let b2 = docx_to_bytes(&d);
  if !b1.is_ok || !b2.is_ok {
    return report(false, "serialization is deterministic");
  };
  let v1: Vec[UInt8] = b1.value;
  let v2: Vec[UInt8] = b2.value;
  let ok = v1.len() > 0 && bytes_eq(&v1, &v2);
  return report(ok, "serialization is deterministic");
}

fn t7() -> Int {
  var d = build_sample();
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "zip has three expected entries");
  };
  let buf: Vec[UInt8] = br.value;
  let zr = docx_zip_open(&buf);
  if !zr.is_ok {
    return report(false, "zip has three expected entries");
  };
  let z: DocxZip = zr.value;
  let ci = docx_zip_find(&z, "[Content_Types].xml");
  let ri = docx_zip_find(&z, "_rels/.rels");
  let di = docx_zip_find(&z, "word/document.xml");
  let ok = docx_zip_count(&z) == 3 && ci >= 0 && ri >= 0 && di >= 0;
  return report(ok, "zip has three expected entries");
}

fn t8() -> Int {
  var d = build_sample();
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "entry name and data accessors");
  };
  let buf: Vec[UInt8] = br.value;
  let zr = docx_zip_open(&buf);
  if !zr.is_ok {
    return report(false, "entry name and data accessors");
  };
  let z: DocxZip = zr.value;
  let ci = docx_zip_find(&z, "[Content_Types].xml");
  if ci < 0 {
    return report(false, "entry name and data accessors");
  };
  let nr = docx_zip_entry_name(&z, ci);
  let da = docx_zip_entry_data(&z, ci);
  var ok = nr.is_ok && str_eq(nr.value, "[Content_Types].xml") && da.is_ok;
  if ok {
    let data: Vec[UInt8] = da.value;
    ok = bytes_contain(&data, "<Types");
  };
  return report(ok, "entry name and data accessors");
}

fn t9() -> Int {
  var w = docx_zip_writer_new();
  let a = bytes_of("stored payload");
  let b = bytes_of("deflated payload deflated payload");
  docx_zip_writer_add(&mut w, "a.txt", &a, 0);
  docx_zip_writer_add(&mut w, "b.txt", &b, 6);
  let buf = docx_zip_writer_finish(&mut w);
  let zr = docx_zip_open(&buf);
  if !zr.is_ok {
    return report(false, "mixed stored+deflate zip round trip");
  };
  let z: DocxZip = zr.value;
  let ia = docx_zip_find(&z, "a.txt");
  let ib = docx_zip_find(&z, "b.txt");
  if ia < 0 || ib < 0 {
    return report(false, "mixed stored+deflate zip round trip");
  };
  let da = docx_zip_entry_data(&z, ia);
  let db = docx_zip_entry_data(&z, ib);
  let ma = docx_zip_entry_method(&z, ia);
  let mb = docx_zip_entry_method(&z, ib);
  var ok = da.is_ok && db.is_ok && ma.is_ok && mb.is_ok;
  if ok {
    let va: Vec[UInt8] = da.value;
    let vb: Vec[UInt8] = db.value;
    ok = bytes_eq(&va, &a) && bytes_eq(&vb, &b) && ma.value == 0 && mb.value == 8;
  };
  return report(ok, "mixed stored+deflate zip round trip");
}

fn t10() -> Int {
  var d = build_sample();
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "zip_find returns -1 for a missing entry");
  };
  let buf: Vec[UInt8] = br.value;
  let zr = docx_zip_open(&buf);
  if !zr.is_ok {
    return report(false, "zip_find returns -1 for a missing entry");
  };
  let z: DocxZip = zr.value;
  return report(docx_zip_find(&z, "nope.txt") == -1, "zip_find returns -1 for a missing entry");
}

fn t11() -> Int {
  let b = bytes_of("PK");
  return report(zip_err_is(docx_zip_open(&b), "docx: zip too small"), "two-byte input is rejected");
}

fn t12() -> Int {
  let b = bytes_of("not a zip at all............");
  return report(zip_err_is(docx_zip_open(&b), "docx: end of central directory not found"), "missing EOCD is rejected");
}

fn t13() -> Int {
  var w = docx_zip_writer_new();
  let a = bytes_of("hi");
  docx_zip_writer_add(&mut w, "a.txt", &a, 0);
  var buf = docx_zip_writer_finish(&mut w);
  buf[0] = 0x51u8;
  return report(zip_err_is(docx_zip_open(&buf), "docx: bad local file header signature"), "corrupt local signature is rejected");
}

fn t14() -> Int {
  var w = docx_zip_writer_new();
  let a = bytes_of("hello");
  docx_zip_writer_add(&mut w, "x.txt", &a, 0);
  var buf = docx_zip_writer_finish(&mut w);
  buf[36] = 0x5Au8;
  return report(zip_err_is(docx_zip_open(&buf), "docx: crc mismatch"), "tampered stored payload fails CRC");
}

fn t15() -> Int {
  let b = craft_bad_method_zip();
  return report(zip_err_is(docx_zip_open(&b), "docx: unsupported compression method 12"), "unsupported compression method is rejected");
}

fn t16() -> Int {
  var w = docx_zip_writer_new();
  let xml = bytes_of("<w:document><w:body/></w:document>");
  docx_zip_writer_add(&mut w, "word/document.xml", &xml, 0);
  let buf = docx_zip_writer_finish(&mut w);
  return report(docx_err_is(docx_from_bytes(&buf), "docx: missing [Content_Types].xml"), "missing content types part is rejected");
}

fn t17() -> Int {
  var d = docx_new();
  docx_add_run(&mut d, "\u{0001}", false, false, 0);
  let br = docx_to_bytes(&d);
  return report(bytes_err_is(br, "docx: control character in text"), "control character in text is rejected");
}

fn t18() -> Int {
  var d = docx_new();
  docx_add_run(&mut d, "A&B <tag> \"q\" 'a'", false, false, 0);
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "xml escaping round trip");
  };
  let buf: Vec[UInt8> = br.value;
  let dr = docx_from_bytes(&buf);
  if !dr.is_ok {
    return report(false, "xml escaping round trip");
  };
  let d2: DocxDoc = dr.value;
  let p = docx_paragraph_text(&d2, 0);
  var ok = p.is_ok;
  if ok {
    ok = str_eq(p.value, "A&B <tag> \"q\" 'a'");
  };
  return report(ok, "xml escaping round trip");
}

fn t19() -> Int {
  let uni = "Gr\u{00FC}\u{00DF}e \u{03A9}";
  var d = docx_new();
  docx_add_run(&mut d, uni, false, false, 0);
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "utf-8 text round trip");
  };
  let buf: Vec[UInt8] = br.value;
  let dr = docx_from_bytes(&buf);
  if !dr.is_ok {
    return report(false, "utf-8 text round trip");
  };
  let d2: DocxDoc = dr.value;
  let p = docx_paragraph_text(&d2, 0);
  var ok = p.is_ok;
  if ok {
    ok = str_eq(p.value, uni);
  };
  return report(ok, "utf-8 text round trip");
}

fn t20() -> Int {
  let data = bytes_of("the quick brown fox jumps over the lazy dog 1234567890");
  let comp = deflate.deflate_compress(&data);
  let rf = docx_inflate_fixed(&comp, 1000);
  let comp0 = deflate.deflate_compress_level(&data, 0);
  let rs = docx_inflate_fixed(&comp0, 1000);
  var ok = rf.is_ok && rs.is_ok;
  if ok {
    let vf: Vec[UInt8] = rf.value;
    let vs: Vec[UInt8] = rs.value;
    ok = bytes_eq(&vf, &data) && bytes_eq(&vs, &data);
  };
  return report(ok, "own inflater reads fixed and stored deflate blocks");
}

fn t21() -> Int {
  var b = Vec[UInt8].new();
  b.push(4u8);
  return report(bytes_err_is(docx_inflate_fixed(&b, 10), "docx: deflate dynamic huffman unsupported"), "dynamic huffman is a documented limitation");
}

fn t22() -> Int {
  var d = docx_new();
  docx_add_run(&mut d, "x", false, false, 0);
  let r1 = str_err_is(docx_run_text(&d, 5), "docx: run index out of range");
  let r2 = str_err_is(docx_paragraph_text(&d, 5), "docx: paragraph index out of range");
  let r3 = zip_err_is(docx_zip_open(&bytes_of("PK")), "docx: zip too small");
  return report(r1 && r2 && r3, "accessors range-check their indices");
}

fn t23() -> Int {
  var chunk = "";
  var i = 0;
  while i < 100 {
    chunk = chunk + "0123456789";
    i = i + 1;
  };
  var big = "";
  i = 0;
  while i < 70 {
    big = big + chunk;
    i = i + 1;
  };
  var d = docx_new();
  docx_add_run(&mut d, big, false, false, 0);
  let br = docx_to_bytes_level(&d, 0);
  if !br.is_ok {
    return report(false, "70000-byte stored round trip");
  };
  let buf: Vec[UInt8] = br.value;
  let dr = docx_from_bytes(&buf);
  if !dr.is_ok {
    return report(false, "70000-byte stored round trip");
  };
  let d2: DocxDoc = dr.value;
  let p = docx_paragraph_text(&d2, 0);
  var ok = p.is_ok;
  if ok {
    ok = str_eq(p.value, big);
  };
  return report(ok, "70000-byte stored round trip");
}

fn t24() -> Int {
  var d = build_styled();
  let br = docx_to_bytes(&d);
  if !br.is_ok {
    return report(false, "serialized document.xml carries bold markup");
  };
  let buf: Vec[UInt8> = br.value;
  let zr = docx_zip_open(&buf);
  if !zr.is_ok {
    return report(false, "serialized document.xml carries bold markup");
  };
  let z: DocxZip = zr.value;
  let di = docx_zip_find(&z, "word/document.xml");
  if di < 0 {
    return report(false, "serialized document.xml carries bold markup");
  };
  let da = docx_zip_entry_data(&z, di);
  var ok = da.is_ok;
  if ok {
    let data: Vec[UInt8> = da.value;
    ok = bytes_contain(&data, "<w:b/>") && bytes_contain(&data, "<w:i/>") && bytes_contain(&data, "<w:sz w:val=\"48\"/>") && bytes_contain(&data, "xml:space=\"preserve\"");
  };
  return report(ok, "serialized document.xml carries bold markup");
}

fn t25() -> Int {
  let buf = pack_doc_xml("not xml");
  return report(docx_err_is(docx_from_bytes(&buf), "docx: missing w:body"), "document without w:body is rejected");
}

fn t26() -> Int {
  let buf = pack_doc_xml("<w:document><w:body><w:p><w:r><w:t>&bogus;</w:t></w:r></w:p></w:body></w:document>");
  return report(docx_err_is(docx_from_bytes(&buf), "docx: unknown entity"), "unknown entity is rejected");
}

fn t27() -> Int {
  var d = build_sample();
  var ok = docx_points_to_half(12) == 24 && docx_half_to_points(24) == 12;
  let prc = docx_para_run_count(&d, 0);
  if ok {
    ok = prc.is_ok && prc.value == 2;
  };
  var w = docx_zip_writer_new();
  let nine = bytes_of("123456789");
  docx_zip_writer_add(&mut w, "nine.txt", &nine, 6);
  if ok {
    ok = docx_zip_writer_count(&w) == 1;
  };
  let buf = docx_zip_writer_finish(&mut w);
  let zr = docx_zip_open(&buf);
  if ok {
    ok = zr.is_ok;
  };
  if ok {
    let z: DocxZip = zr.value;
    let sz = docx_zip_entry_size(&z, 0);
    let cr = docx_zip_entry_crc(&z, 0);
    ok = sz.is_ok && cr.is_ok && sz.value == 9 && cr.value == 3421780262;
  };
  return report(ok, "style converters, counts and CRC known answer");
}

fn main() -> Int {
  io.println("=== xiom.docx conformance tests ===");
  var failed: Int = 0;
  failed = failed + t1();
  failed = failed + t2();
  failed = failed + t3();
  failed = failed + t4();
  failed = failed + t5();
  failed = failed + t6();
  failed = failed + t7();
  failed = failed + t8();
  failed = failed + t9();
  failed = failed + t10();
  failed = failed + t11();
  failed = failed + t12();
  failed = failed + t13();
  failed = failed + t14();
  failed = failed + t15();
  failed = failed + t16();
  failed = failed + t17();
  failed = failed + t18();
  failed = failed + t19();
  failed = failed + t20();
  failed = failed + t21();
  failed = failed + t22();
  failed = failed + t23();
  failed = failed + t24();
  failed = failed + t25();
  failed = failed + t26();
  failed = failed + t27();
  if failed == 0 {
    io.println("xiom.docx: all tests passed");
  } else {
    io.println("xiom.docx: tests failed");
  };
  return failed;
}
