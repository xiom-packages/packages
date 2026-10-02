// XIOM -- xiom.pptx conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic, fixture-free coverage of the documented API:
//   * the presentation/slide/shape model and its error cases;
//   * integer EMU geometry;
//   * ZIP writer validation, stored/deflate entries, EOCD and
//     central-directory parsing, CRC and structural rejections;
//   * the local STORED+fixed-Huffman inflater (round trip, stored blocks,
//     dynamic-Huffman rejection);
//   * full model -> bytes -> package -> model round trips for both stored
//     and deflate entry methods, including XML escaping and UTF-8 text.
//
// Harness style mirrors xiom.parquet/xiom.pdf: one fn tN() -> Int per test,
// called directly from main; each test prints one [PASS]/[FAIL] line and
// returns 0/1. Str values are compared with str_compare.

module pptx_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare; use xiom.string.builder;
use xiom.convert;
use xiom.compress.deflate;
use xiom.pptx;

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

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  };
  return r.value == want;
}

fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  };
  return str_eq(r.value, want);
}

fn bytes_is(r: Result[Vec[UInt8], Str], want: &Vec[UInt8]) -> Bool {
  if !r.is_ok {
    return false;
  };
  let got: Vec[UInt8] = r.value;
  return bytes_eq(&got, want);
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
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

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  };
  return str_eq(r.error, want);
}

fn pres_err_is(r: Result[PptxPresentation, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  };
  return str_eq(r.error, want);
}

fn zip_err_is(r: Result[ZipArchive, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  };
  return str_eq(r.error, want);
}

fn pres_ok_is(r: Result[PptxPresentation, Str], name: Str) -> Bool {
  if !r.is_ok {
    io.println("    (unexpected: " + r.error + ")");
    return false;
  };
  return true;
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

fn push_u8(out: &mut Vec[UInt8], v: Int) {
  var q = v % 256;
  if q < 0 {
    q = q + 256;
  };
  out.push((q as UInt8));
}

fn push_bytes(out: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    out.push(b);
    i = i + 1;
  };
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

fn str_of(b: &Vec[UInt8]) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < b.len() {
    let x: UInt8 = b[i];
    sb.push(x);
    i = i + 1;
  };
  return builder.sb_to_str(&sb);
}

fn vb1(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u8(&mut v, a);
  return v;
}

fn slice(buf: &Vec[UInt8], off: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b: UInt8 = buf[off + i];
    out.push(b);
    i = i + 1;
  };
  return out;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((0 as UInt8));
    i = i + 1;
  };
  return v;
}

fn find_from(hay: Str, needle: Str, from: Int) -> Int {
  let hn = string.str_len(hay);
  let nn = string.str_len(needle);
  var i = from;
  if i < 0 {
    i = 0;
  };
  while i + nn <= hn {
    var j = 0;
    var ok = true;
    while j < nn {
      let a: UInt8 = string.byte_at(hay, i + j);
      let b: UInt8 = string.byte_at(needle, j);
      if a != b {
        ok = false;
        j = nn;
      } else {
        j = j + 1;
      };
    };
    if ok {
      return i;
    };
    i = i + 1;
  };
  return -1;
}

fn rd_u16(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: UInt8 = data[pos];
  let b1: UInt8 = data[pos + 1];
  let x0: Int = (b0 as Int) & 0xFF;
  let x1: Int = (b1 as Int) & 0xFF;
  return x0 + x1 * 256;
}

fn rd_u32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: UInt8 = data[pos];
  let b1: UInt8 = data[pos + 1];
  let b2: UInt8 = data[pos + 2];
  let b3: UInt8 = data[pos + 3];
  let x0: Int = (b0 as Int) & 0xFF;
  let x1: Int = (b1 as Int) & 0xFF;
  let x2: Int = (b2 as Int) & 0xFF;
  let x3: Int = (b3 as Int) & 0xFF;
  return x0 + x1 * 256 + x2 * 65536 + x3 * 16777216;
}

// --------------------------------------------------
//  Fixtures and mini-package builders
// --------------------------------------------------

fn sample_pres() -> PptxPresentation {
  var p = pptx_presentation_new(9144000, 5143500);
  let s0 = pptx_add_slide(&mut p);
  let s1 = pptx_add_slide(&mut p);
  let a = pptx_add_text_box(&mut p, 0, 914400, 457200, 3657600, 914400, "Hello & <PPTX>");
  let b = pptx_add_text_box(&mut p, 0, 0, 0, 1000, 2000, "second");
  let c = pptx_add_text_box(&mut p, 1, 0 - 100, 200, 300, 400, "");
  return p;
}

fn add_part(w: &mut ZipWriter, name: Str, s: Str, method: Int) -> Result[Int, Str] {
  let b = bytes_of(s);
  return zip_writer_add(w, name, &b, method);
}

fn mini_presentation(slide_rid: Str) -> Str {
  return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:presentation xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:sldIdLst><p:sldId id=\"256\" r:id=\"" + slide_rid + "\"/></p:sldIdLst><p:sldSz cx=\"9144000\" cy=\"5143500\"/></p:presentation>";
}

fn mini_rels(rid: Str) -> Str {
  return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"" + rid + "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide1.xml\"/></Relationships>";
}

fn mini_slide(off_attrs: Str, ext_attrs: Str, text: Str) -> Str {
  return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"TextBox 1\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off " + off_attrs + "/><a:ext " + ext_attrs + "/></a:xfrm></p:spPr><p:txBody><a:p><a:r><a:t>" + text + "</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>";
}

fn mini_zip(pres_xml: Str, rels_xml: Str, slide_xml: Str, method: Int) -> Result[Vec[UInt8], Str] {
  var w = zip_writer_new();
  let r0 = add_part(&mut w, "[Content_Types].xml", "<Types/>", method);
  let r1 = add_part(&mut w, "_rels/.rels", "<Relationships/>", method);
  let r2 = add_part(&mut w, "ppt/presentation.xml", pres_xml, method);
  let r3 = add_part(&mut w, "ppt/_rels/presentation.xml.rels", rels_xml, method);
  let r4 = add_part(&mut w, "ppt/slides/slide1.xml", slide_xml, method);
  return zip_writer_finish(&w);
}

// --------------------------------------------------
//  Model and geometry tests
// --------------------------------------------------

fn t1() -> Int {
  let p = pptx_presentation_new_default();
  if pptx_slide_count(&p) != 0 {
    return report(false, "default presentation has no slides");
  };
  if pptx_shape_count(&p) != 0 {
    return report(false, "default presentation has no shapes");
  };
  if pptx_presentation_width(&p) != 12192000 {
    return report(false, "default width is 12192000 EMU");
  };
  if pptx_presentation_height(&p) != 6858000 {
    return report(false, "default height is 6858000 EMU");
  };
  if !str_eq(pptx_shape_kind_name(0), "text_box") {
    return report(false, "kind 0 names text_box");
  };
  if !str_eq(pptx_shape_kind_name(9), "unknown") {
    return report(false, "kind 9 names unknown");
  };
  return report(true, "default model");
}

fn t2() -> Int {
  if pptx_mm_to_emu(100) != 3600000 {
    return report(false, "100 mm -> EMU");
  };
  if pptx_emu_to_mm(3600000) != 100 {
    return report(false, "EMU -> mm");
  };
  if pptx_inches_to_emu(10) != 9144000 {
    return report(false, "10 in -> EMU");
  };
  if pptx_emu_to_inches(9144001) != 10 {
    return report(false, "EMU -> in truncates");
  };
  if pptx_points_to_emu(72) != 914400 {
    return report(false, "72 pt -> EMU");
  };
  if pptx_emu_to_points(914400) != 72 {
    return report(false, "EMU -> pt");
  };
  if pptx_emu_to_mm(0 - 36000) != 0 - 1 {
    return report(false, "negative EMU -> mm truncates toward zero");
  };
  return report(true, "integer EMU geometry");
}

fn t3() -> Int {
  let p = sample_pres();
  if pptx_slide_count(&p) != 2 {
    return report(false, "two slides");
  };
  if pptx_shape_count(&p) != 3 {
    return report(false, "three shapes");
  };
  if pptx_slide_shape_count(&p, 0) != 2 {
    return report(false, "slide 0 has two shapes");
  };
  if pptx_slide_shape_count(&p, 1) != 1 {
    return report(false, "slide 1 has one shape");
  };
  if pptx_slide_shape_count(&p, 2) != 0 {
    return report(false, "slide 2 does not exist -> 0");
  };
  if !int_is(pptx_slide_shape(&p, 0, 1), 1) {
    return report(false, "slide 0 second shape is global 1");
  };
  if !int_is(pptx_shape_slide(&p, 2), 1) {
    return report(false, "shape 2 belongs to slide 1");
  };
  if !int_is(pptx_shape_x(&p, 0), 914400) {
    return report(false, "shape 0 x");
  };
  if !int_is(pptx_shape_width(&p, 1), 1000) {
    return report(false, "shape 1 width");
  };
  if !int_is(pptx_shape_height(&p, 2), 400) {
    return report(false, "shape 2 height");
  };
  if !int_is(pptx_shape_kind(&p, 0), 0) {
    return report(false, "shape 0 kind");
  };
  if !str_is(pptx_shape_text(&p, 0), "Hello & <PPTX>") {
    return report(false, "shape 0 text");
  };
  if !str_is(pptx_shape_text(&p, 1), "second") {
    return report(false, "shape 1 text");
  };
  if !str_is(pptx_shape_text(&p, 2), "") {
    return report(false, "shape 2 text is empty");
  };
  return report(true, "model accessors");
}

fn t4() -> Int {
  var p = pptx_presentation_new_default();
  let s0 = pptx_add_slide(&mut p);
  if !int_err_is(pptx_add_text_box(&mut p, 5, 0, 0, 10, 10, "x"), "pptx: slide index out of range") {
    return report(false, "bad slide index rejected");
  };
  if !int_err_is(pptx_add_text_box(&mut p, 0, 0, 0, 0, 10, "x"), "pptx: shape size must be positive") {
    return report(false, "zero width rejected");
  };
  if !int_err_is(pptx_add_text_box(&mut p, 0, 0, 0, 10, 10, "\u{0001}"), "pptx: text contains control character") {
    return report(false, "control character rejected");
  };
  if !int_err_is(pptx_shape_x(&p, 9), "pptx: shape index out of range") {
    return report(false, "shape accessor bounds");
  };
  if !str_err_is(pptx_shape_text(&p, 0 - 1), "pptx: shape index out of range") {
    return report(false, "shape text bounds");
  };
  return report(true, "model error cases");
}

// --------------------------------------------------
//  Round-trip tests
// --------------------------------------------------

fn t5() -> Int {
  let p = sample_pres();
  let r = pptx_presentation_to_bytes(&p);
  if !pres_ok_is(r, "serialize") {
    return report(false, "deflate serialize");
  };
  let data: Vec[UInt8] = r.value;
  let q = pptx_presentation_from_bytes(&data);
  if !pres_ok_is(q, "parse") {
    return report(false, "deflate parse");
  };
  let m: PptxPresentation = q.value;
  if pptx_slide_count(&m) != 2 || pptx_shape_count(&m) != 3 {
    return report(false, "deflate round trip counts");
  };
  if !int_is(pptx_shape_x(&m, 2), 0 - 100) {
    return report(false, "deflate round trip negative x");
  };
  if !str_is(pptx_shape_text(&m, 0), "Hello & <PPTX>") {
    return report(false, "deflate round trip escaped text");
  };
  if !str_is(pptx_shape_text(&m, 2), "") {
    return report(false, "deflate round trip empty text");
  };
  return report(true, "deflate model round trip");
}

fn t6() -> Int {
  let p = sample_pres();
  let r = pptx_presentation_to_bytes_stored(&p);
  if !pres_ok_is(r, "stored serialize") {
    return report(false, "stored serialize");
  };
  let data: Vec[UInt8] = r.value;
  let q = pptx_presentation_from_bytes(&data);
  if !pres_ok_is(q, "stored parse") {
    return report(false, "stored parse");
  };
  let m: PptxPresentation = q.value;
  if pptx_slide_count(&m) != 2 || pptx_shape_count(&m) != 3 {
    return report(false, "stored round trip counts");
  };
  if !int_is(pptx_shape_width(&m, 1), 1000) {
    return report(false, "stored round trip width");
  };
  if !str_is(pptx_shape_text(&m, 1), "second") {
    return report(false, "stored round trip text");
  };
  return report(true, "stored model round trip");
}

fn t7() -> Int {
  let p = sample_pres();
  let r = pptx_presentation_to_bytes(&p);
  if !pres_ok_is(r, "zip serialize") {
    return report(false, "zip serialize");
  };
  let data: Vec[UInt8] = r.value;
  let ar = zip_read(&data);
  if !ar.is_ok {
    return report(false, "zip read");
  };
  let a: ZipArchive = ar.value;
  if zip_entry_count(&a) != 6 {
    return report(false, "four fixed parts plus two slides");
  };
  if zip_entry_find(&a, "[Content_Types].xml") != 0 {
    return report(false, "content types entry");
  };
  if zip_entry_find(&a, "ppt/presentation.xml") != 2 {
    return report(false, "presentation entry");
  };
  if zip_entry_find(&a, "ppt/slides/slide2.xml") != 5 {
    return report(false, "slide 2 entry");
  };
  if zip_entry_find(&a, "nope") != -1 {
    return report(false, "absent entry -> -1");
  };
  let i = zip_entry_find(&a, "ppt/slides/slide1.xml");
  if !int_is(zip_entry_method(&a, i), 8) {
    return report(false, "deflate method");
  };
  let lo = zip_entry_local_offset(&a, i);
  if !lo.is_ok {
    return report(false, "slide 1 local offset");
  };
  let lov: Int = lo.value;
  if lov <= 0 || lov >= data.len() {
    return report(false, "slide 1 local offset in bounds");
  };
  let d = zip_entry_data(&a, i);
  if !d.is_ok {
    return report(false, "slide 1 data");
  };
  let dv: Vec[UInt8] = d.value;
  if zip_crc32(&dv) != zip_entry_crc(&a, i).value {
    return report(false, "entry crc matches payload crc");
  };
  return report(true, "zip structure");
}

fn t8() -> Int {
  let p = sample_pres();
  let r = pptx_presentation_to_bytes_stored(&p);
  if !pres_ok_is(r, "stored zip serialize") {
    return report(false, "stored zip serialize");
  };
  let data: Vec[UInt8] = r.value;
  let ar = zip_read(&data);
  if !ar.is_ok {
    return report(false, "stored zip read");
  };
  let a: ZipArchive = ar.value;
  let pi = zip_entry_find(&a, "ppt/presentation.xml");
  if !int_is(zip_entry_method(&a, pi), 0) {
    return report(false, "stored method");
  };
  let pd = zip_entry_data(&a, pi);
  if !pd.is_ok {
    return report(false, "stored presentation data");
  };
  let pv: Vec[UInt8] = pd.value;
  let px = str_of(&pv);
  if find_from(px, "<p:presentation", 0) < 0 {
    return report(false, "presentation part content");
  };
  let si = zip_entry_find(&a, "ppt/slides/slide1.xml");
  let sd = zip_entry_data(&a, si);
  if !sd.is_ok {
    return report(false, "stored slide data");
  };
  let sv: Vec[UInt8] = sd.value;
  let sx = str_of(&sv);
  if find_from(sx, "Hello &amp; &lt;PPTX&gt;", 0) < 0 {
    return report(false, "escaped text in slide part");
  };
  return report(true, "stored parts readable");
}

fn t9() -> Int {
  if !zip_err_is(zip_read(&vb1(1)), "pptx: not a zip archive (no end of central directory)") {
    return report(false, "tiny buffer rejected");
  };
  let p = sample_pres();
  let r = pptx_presentation_to_bytes_stored(&p);
  if !pres_ok_is(r, "zip reject serialize") {
    return report(false, "zip reject serialize");
  };
  let data: Vec[UInt8] = r.value;
  let cut = slice(&data, 0, data.len() - 5);
  if !zip_err_is(zip_read(&cut), "pptx: not a zip archive (no end of central directory)") {
    return report(false, "truncated archive rejected");
  };
  var bad = data;
  let n = bad.len();
  bad[n - 22] = 0;
  if !zip_err_is(zip_read(&bad), "pptx: not a zip archive (no end of central directory)") {
    return report(false, "bad EOCD signature rejected");
  };
  return report(true, "zip structural rejections");
}

fn t10() -> Int {
  var w = zip_writer_new();
  if !int_err_is(zip_writer_add(&mut w, "x", &vb1(1), 12), "pptx: unsupported compression method") {
    return report(false, "bad method rejected");
  };
  if !int_err_is(zip_writer_add(&mut w, "", &vb1(1), 0), "pptx: zip entry name is empty") {
    return report(false, "empty name rejected");
  };
  if !int_err_is(zip_writer_add(&mut w, "../x", &vb1(1), 0), "pptx: zip entry name must not contain ..") {
    return report(false, "dotdot name rejected");
  };
  if !int_err_is(zip_writer_add(&mut w, "a\u{005C}b", &vb1(1), 0), "pptx: zip entry name must be printable ascii") {
    return report(false, "backslash name rejected");
  };
  let ok = zip_writer_add(&mut w, "a.txt", &vb1(65), 0);
  if !int_is(ok, 0) {
    return report(false, "valid entry index");
  };
  if zip_writer_entry_count(&w) != 1 {
    return report(false, "writer entry count");
  };
  let f = zip_writer_finish(&w);
  if !f.is_ok {
    return report(false, "writer finish");
  };
  let fv: Vec[UInt8] = f.value;
  let ar = zip_read(&fv);
  if !ar.is_ok {
    return report(false, "written archive reads");
  };
  let a: ZipArchive = ar.value;
  if !str_is(zip_entry_name(&a, 0), "a.txt") {
    return report(false, "written entry name");
  };
  return report(true, "zip writer validation");
}

fn t11() -> Int {
  let w = zip_writer_new();
  let f = zip_writer_finish(&w);
  if !f.is_ok {
    return report(false, "empty archive finish");
  };
  let fv: Vec[UInt8] = f.value;
  if fv.len() != 22 {
    return report(false, "empty archive is 22 bytes");
  };
  let ar = zip_read(&fv);
  if !ar.is_ok {
    return report(false, "empty archive reads");
  };
  let a: ZipArchive = ar.value;
  if zip_entry_count(&a) != 0 {
    return report(false, "empty archive has no entries");
  };
  return report(true, "empty zip");
}

// --------------------------------------------------
//  Local inflater tests
// --------------------------------------------------

fn pattern_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((65 + (i % 7)) as UInt8));
    i = i + 1;
  };
  return v;
}

fn t12() -> Int {
  let src = pattern_bytes(1024);
  let comp = deflate.deflate_compress(&src);
  let r = zip_inflate_fixed(&comp, 100000);
  if !r.is_ok {
    return report(false, "fixed inflate decodes");
  };
  let got: Vec[UInt8] = r.value;
  if !bytes_eq(&got, &src) {
    return report(false, "fixed inflate round trip");
  };
  let r2 = deflate.deflate_decompress_capped(&comp, 100000);
  if !r2.is_ok {
    return report(false, "stdlib inflate decodes");
  };
  let got2: Vec[UInt8] = r2.value;
  if !bytes_eq(&got2, &src) {
    return report(false, "stdlib and local agree");
  };
  return report(true, "local fixed inflater");
}

fn t13() -> Int {
  let src = pattern_bytes(70000);
  let comp = deflate.deflate_compress_level(&src, 0);
  let r = zip_inflate_fixed(&comp, 200000);
  if !r.is_ok {
    return report(false, "stored blocks decode");
  };
  let got: Vec[UInt8] = r.value;
  if !bytes_eq(&got, &src) {
    return report(false, "stored blocks round trip across 64 KiB");
  };
  return report(true, "local stored-block inflater");
}

fn t14() -> Int {
  if !bytes_err_is(zip_inflate_fixed(&vb1(5), 100), "pptx: deflate: dynamic-huffman blocks unsupported") {
    return report(false, "dynamic-huffman rejected");
  };
  let empty = Vec[UInt8].new();
  if !bytes_err_is(zip_inflate_fixed(&empty, 100), "pptx: deflate: truncated block header") {
    return report(false, "truncated header rejected");
  };
  return report(true, "inflater error cases");
}

// --------------------------------------------------
//  Package parsing error cases
// --------------------------------------------------

fn t15() -> Int {
  var w = zip_writer_new();
  let r0 = add_part(&mut w, "[Content_Types].xml", "<Types/>", 0);
  let f = zip_writer_finish(&w);
  if !f.is_ok {
    return report(false, "missing-presentation fixture");
  };
  let fv: Vec[UInt8] = f.value;
  if !pres_err_is(pptx_presentation_from_bytes(&fv), "pptx: missing part ppt/presentation.xml") {
    return report(false, "missing presentation part rejected");
  };
  return report(true, "missing presentation part");
}

fn t16() -> Int {
  let f = mini_zip(mini_presentation("rId9"), mini_rels("rId1"), mini_slide("x=\"0\" y=\"0\"", "cx=\"10\" cy=\"10\"", "hi"), 0);
  if !f.is_ok {
    return report(false, "unknown-rel fixture");
  };
  let fv: Vec[UInt8] = f.value;
  if !pres_err_is(pptx_presentation_from_bytes(&fv), "pptx: sldId references unknown relationship") {
    return report(false, "unknown relationship rejected");
  };
  return report(true, "unknown relationship");
}

fn t17() -> Int {
  var w = zip_writer_new();
  let r0 = add_part(&mut w, "[Content_Types].xml", "<Types/>", 0);
  let r1 = add_part(&mut w, "ppt/presentation.xml", mini_presentation("rId1"), 0);
  let r2 = add_part(&mut w, "ppt/_rels/presentation.xml.rels", mini_rels("rId1"), 0);
  let f = zip_writer_finish(&w);
  if !f.is_ok {
    return report(false, "missing-slide fixture");
  };
  let fv: Vec[UInt8] = f.value;
  if !pres_err_is(pptx_presentation_from_bytes(&fv), "pptx: missing slide part ppt/slides/slide1.xml") {
    return report(false, "missing slide part rejected");
  };
  return report(true, "missing slide part");
}

fn t18() -> Int {
  let f = mini_zip(mini_presentation("rId1"), mini_rels("rId1"), mini_slide("x=\"abc\" y=\"0\"", "cx=\"10\" cy=\"10\"", "hi"), 0);
  if !f.is_ok {
    return report(false, "bad-int fixture");
  };
  let fv: Vec[UInt8] = f.value;
  if !pres_err_is(pptx_presentation_from_bytes(&fv), "pptx: malformed integer attribute") {
    return report(false, "malformed integer attribute rejected");
  };
  return report(true, "malformed geometry attribute");
}

fn t19() -> Int {
  let no_text = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree><p:sp><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"10\" cy=\"10\"/></a:xfrm></p:spPr></p:sp></p:spTree></p:cSld></p:sld>";
  let f = mini_zip(mini_presentation("rId1"), mini_rels("rId1"), no_text, 0);
  if !f.is_ok {
    return report(false, "no-text fixture");
  };
  let fv: Vec[UInt8] = f.value;
  if !pres_err_is(pptx_presentation_from_bytes(&fv), "pptx: shape missing a:t text") {
    return report(false, "shape without a:t rejected");
  };
  return report(true, "shape text requirement");
}

fn t20() -> Int {
  let ctrl_slide = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sld><p:cSld><p:spTree>\u{0001}</p:spTree></p:cSld></p:sld>";
  let f = mini_zip(mini_presentation("rId1"), mini_rels("rId1"), ctrl_slide, 0);
  if !f.is_ok {
    return report(false, "control fixture");
  };
  let fv: Vec[UInt8] = f.value;
  if !pres_err_is(pptx_presentation_from_bytes(&fv), "pptx: part contains control byte") {
    return report(false, "control byte in part rejected");
  };
  return report(true, "control byte rejection");
}

fn t21() -> Int {
  var p = pptx_presentation_new_default();
  let s0 = pptx_add_slide(&mut p);
  let a = pptx_add_text_box(&mut p, 0, 1, 2, 3, 4, "a & b < c > d \" e ' f");
  let b = pptx_add_text_box(&mut p, 0, 5, 6, 7, 8, "line1\nline2");
  let c = pptx_add_text_box(&mut p, 0, 9, 10, 11, 12, "tab\tend");
  let r = pptx_presentation_to_bytes(&p);
  if !pres_ok_is(r, "escape round trip serialize") {
    return report(false, "escape round trip serialize");
  };
  let data: Vec[UInt8] = r.value;
  let q = pptx_presentation_from_bytes(&data);
  if !pres_ok_is(q, "escape round trip parse") {
    return report(false, "escape round trip parse");
  };
  let m: PptxPresentation = q.value;
  if !str_is(pptx_shape_text(&m, 0), "a & b < c > d \" e ' f") {
    return report(false, "entity-heavy text");
  };
  if !str_is(pptx_shape_text(&m, 1), "line1\nline2") {
    return report(false, "newline text");
  };
  if !str_is(pptx_shape_text(&m, 2), "tab\tend") {
    return report(false, "tab text");
  };
  return report(true, "xml escaping round trip");
}

fn t22() -> Int {
  var p = pptx_presentation_new_default();
  let s0 = pptx_add_slide(&mut p);
  let a = pptx_add_text_box(&mut p, 0, 0, 0, 100, 100, "caf\u{00E9} \u{20AC}uro");
  let r = pptx_presentation_to_bytes(&p);
  if !pres_ok_is(r, "utf8 serialize") {
    return report(false, "utf8 serialize");
  };
  let data: Vec[UInt8] = r.value;
  let q = pptx_presentation_from_bytes(&data);
  if !pres_ok_is(q, "utf8 parse") {
    return report(false, "utf8 parse");
  };
  let m: PptxPresentation = q.value;
  if !str_is(pptx_shape_text(&m, 0), "caf\u{00E9} \u{20AC}uro") {
    return report(false, "utf8 text round trip");
  };
  let got = pptx_shape_text(&m, 0);
  if !got.is_ok {
    return report(false, "utf8 text accessor");
  };
  let gstr: Str = got.value;
  let gb = bytes_of(gstr);
  let want = bytes_of("caf\u{00E9} \u{20AC}uro");
  if !bytes_eq(&gb, &want) {
    return report(false, "utf8 byte-exact round trip");
  };
  return report(true, "utf8 text round trip");
}

fn t23() -> Int {
  var p = pptx_presentation_new(9144000, 5143500);
  let s0 = pptx_add_slide(&mut p);
  let a = pptx_add_text_box(&mut p, 0, 100, 200, 300, 400, "");
  let r = pptx_presentation_to_bytes(&p);
  if !pres_ok_is(r, "custom size serialize") {
    return report(false, "custom size serialize");
  };
  let data: Vec[UInt8] = r.value;
  let ar = zip_read(&data);
  if !ar.is_ok {
    return report(false, "custom size zip");
  };
  let arch: ZipArchive = ar.value;
  let pi = zip_entry_find(&arch, "ppt/presentation.xml");
  let pd = zip_entry_data(&arch, pi);
  if !pd.is_ok {
    return report(false, "custom size presentation part");
  };
  let pv: Vec[UInt8] = pd.value;
  let px = str_of(&pv);
  if find_from(px, "<p:sldSz cx=\"9144000\" cy=\"5143500\"", 0) < 0 {
    return report(false, "sldSz attributes written");
  };
  let q = pptx_presentation_from_bytes(&data);
  if !pres_ok_is(q, "custom size parse") {
    return report(false, "custom size parse");
  };
  let m: PptxPresentation = q.value;
  if pptx_presentation_width(&m) != 9144000 || pptx_presentation_height(&m) != 5143500 {
    return report(false, "custom size round trip");
  };
  if pptx_shape_count(&m) != 1 || !str_is(pptx_shape_text(&m, 0), "") {
    return report(false, "empty text shape round trip");
  };
  return report(true, "custom slide size and empty text");
}

// --------------------------------------------------
//  Tamper tests
// --------------------------------------------------

fn t24() -> Int {
  let p = sample_pres();
  let r = pptx_presentation_to_bytes_stored(&p);
  if !pres_ok_is(r, "crc fixture") {
    return report(false, "crc fixture");
  };
  let data: Vec[UInt8] = r.value;
  let ar = zip_read(&data);
  if !ar.is_ok {
    return report(false, "crc fixture reads");
  };
  let a: ZipArchive = ar.value;
  let i = zip_entry_find(&a, "ppt/presentation.xml");
  let lo = zip_entry_local_offset(&a, i);
  let nm = zip_entry_name(&a, i);
  if !lo.is_ok || !nm.is_ok {
    return report(false, "crc fixture entry metadata");
  };
  let name: Str = nm.value;
  let off = lo.value + 30 + string.str_len(name);
  var tampered = data;
  let ob: UInt8 = tampered[off];
  let nb: UInt8 = ((((ob as Int) & 0xFF) ^ 1) as UInt8);
  tampered[off] = nb;
  let ar2 = zip_read(&tampered);
  if !ar2.is_ok {
    return report(false, "tampered archive still reads");
  };
  let a2: ZipArchive = ar2.value;
  if !bytes_err_is(zip_entry_data(&a2, i), "pptx: zip entry crc mismatch") {
    return report(false, "tampered payload crc mismatch");
  };
  return report(true, "crc tamper detection");
}

fn t25() -> Int {
  let p = sample_pres();
  let r = pptx_presentation_to_bytes_stored(&p);
  if !pres_ok_is(r, "method fixture") {
    return report(false, "method fixture");
  };
  var data: Vec[UInt8] = r.value;
  let n = data.len();
  let eocd = n - 22;
  if rd_u32(&data, eocd) != 0x06054b50 {
    return report(false, "eocd present");
  };
  let cd = rd_u32(&data, eocd + 16);
  data[cd + 10] = 12;
  if !zip_err_is(zip_read(&data), "pptx: unsupported zip compression method") {
    return report(false, "patched central method rejected");
  };
  return report(true, "unsupported method detection");
}

fn t26() -> Int {
  var p = pptx_presentation_new_default();
  let s0 = pptx_add_slide(&mut p);
  let a = pptx_add_text_box(&mut p, 0, 0, 0, 10, 10, "inline <b>bold</b> &amp; text");
  let r = pptx_presentation_to_bytes(&p);
  if !pres_ok_is(r, "double-escape serialize") {
    return report(false, "double-escape serialize");
  };
  let data: Vec[UInt8] = r.value;
  let q = pptx_presentation_from_bytes(&data);
  if !pres_ok_is(q, "double-escape parse") {
    return report(false, "double-escape parse");
  };
  let m: PptxPresentation = q.value;
  if !str_is(pptx_shape_text(&m, 0), "inline <b>bold</b> &amp; text") {
    return report(false, "literal entity text preserved");
  };
  return report(true, "literal entity text");
}

fn main() -> Int {
  io.println("=== xiom.pptx conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.pptx: all tests passed");
  } else {
    io.println("xiom.pptx: tests failed");
  };
  return failed;
}
