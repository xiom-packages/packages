// XIOM -- xiom.xlsx conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic, self-contained tests over synthetic workbooks and ZIP
// archives built in this file (no external fixtures):
//   * fixed-point number parsing/formatting (scale 1_000_000, rounding);
//   * XML escape/unescape round-trips including control characters;
//   * the ZIP container (STORED + fixed-Huffman DEFLATE round-trips, CRC
//     verification, malformed archives, zip64 rejection);
//   * the sparse workbook model and the full model -> bytes -> read
//     round-trip for numbers, strings, bools and styles;
//   * crafted SpreadsheetML parts for reader-tolerance cases (sheet-part
//     fallback, inlineStr/str cells, shared-string index errors).
//
// Harness style mirrors xiom.parquet: one fn tN() -> Int per test, called
// directly from main; each test prints exactly one [PASS]/[FAIL] line and
// returns 0/1. Str values are compared with str_compare.

module xlsx_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.string.builder;
use xiom.xlsx;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  let n = s.len();
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

fn bytes_to_str(b: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  let n = b.len();
  while i < n {
    let v: UInt8 = b[i];
    builder.sb_push_byte(&mut out, v);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

fn find_sig(buf: &Vec[UInt8], sig: Int) -> Int {
  var i = 0;
  let n = buf.len();
  while i + 4 <= n {
    let b0: Int = (buf[i] as Int) & 0xFF;
    let b1: Int = (buf[i + 1] as Int) & 0xFF;
    let b2: Int = (buf[i + 2] as Int) & 0xFF;
    let b3: Int = (buf[i + 3] as Int) & 0xFF;
    let v = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
    if v == sig {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn patch_u16(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = (v % 256) as UInt8;
  buf[off + 1] = ((v / 256) % 256) as UInt8;
}

fn entry_text(z: &XlsxZip, name: Str) -> Str {
  let i = xlsx_zip_find(z, name);
  if i < 0 {
    return "";
  }
  let d = xlsx_zip_data(z, i);
  if !d.is_ok {
    return "";
  }
  let bytes: Vec[UInt8] = d.value;
  return bytes_to_str(&bytes);
}

fn zip1(name: Str, data: Vec[UInt8], method: Int) -> Result[Vec[UInt8], Str] {
  var names = Vec[Str].new();
  var methods = Vec[Int].new();
  var pool = Vec[UInt8].new();
  var offs = Vec[Int].new();
  var lens = Vec[Int].new();
  names.push(name);
  methods.push(method);
  offs.push(0);
  lens.push(data.len());
  var i = 0;
  while i < data.len() {
    let v: UInt8 = data[i];
    pool.push(v);
    i = i + 1;
  }
  return xlsx_zip_write(&names, &methods, &pool, &offs, &lens);
}

fn zip4(n1: Str, d1: Vec[UInt8], m1: Int, n2: Str, d2: Vec[UInt8], m2: Int, n3: Str, d3: Vec[UInt8], m3: Int, n4: Str, d4: Vec[UInt8], m4: Int) -> Result[Vec[UInt8], Str] {
  var names = Vec[Str].new();
  var methods = Vec[Int].new();
  var pool = Vec[UInt8].new();
  var offs = Vec[Int].new();
  var lens = Vec[Int].new();
  names.push(n1); methods.push(m1);
  names.push(n2); methods.push(m2);
  names.push(n3); methods.push(m3);
  names.push(n4); methods.push(m4);
  offs.push(0); lens.push(d1.len()); offs.push(d1.len()); lens.push(d2.len());
  offs.push(d1.len() + d2.len()); lens.push(d3.len());
  var o4 = d1.len() + d2.len() + d3.len();
  offs.push(o4); lens.push(d4.len());
  var i = 0;
  while i < d1.len() { let v: UInt8 = d1[i]; pool.push(v); i = i + 1; }
  i = 0;
  while i < d2.len() { let v2: UInt8 = d2[i]; pool.push(v2); i = i + 1; }
  i = 0;
  while i < d3.len() { let v3: UInt8 = d3[i]; pool.push(v3); i = i + 1; }
  i = 0;
  while i < d4.len() { let v4: UInt8 = d4[i]; pool.push(v4); i = i + 1; }
  return xlsx_zip_write(&names, &methods, &pool, &offs, &lens);
}

// --------------------------------------------------
//  Number parsing / formatting
// --------------------------------------------------

fn t01() -> Int {
  var ok = true;
  let a = xlsx_number_parse("0");
  let b = xlsx_number_parse("42");
  let c = xlsx_number_parse("1.5");
  let d = xlsx_number_parse("-2.25");
  let e = xlsx_number_parse("1e3");
  let f = xlsx_number_parse("+0.125");
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok || !e.is_ok || !f.is_ok {
    return report(false, "number parse basic");
  }
  if a.value != 0 { ok = false; }
  if b.value != 42000000 { ok = false; }
  if c.value != 1500000 { ok = false; }
  if d.value != -2250000 { ok = false; }
  if e.value != 1000000000 { ok = false; }
  if f.value != 125000 { ok = false; }
  return report(ok, "number parse basic");
}

fn t02() -> Int {
  var ok = true;
  if !str_eq(xlsx_number_to_str(3000000), "3") { ok = false; }
  if !str_eq(xlsx_number_to_str(3140000), "3.14") { ok = false; }
  if !str_eq(xlsx_number_to_str(-2250000), "-2.25") { ok = false; }
  if !str_eq(xlsx_number_to_str(1), "0.000001") { ok = false; }
  if !str_eq(xlsx_number_to_str(0), "0") { ok = false; }
  if !str_eq(xlsx_number_to_str(10500000), "10.5") { ok = false; }
  return report(ok, "number format basic");
}

fn t03() -> Int {
  let a = xlsx_number_parse("abc");
  let b = xlsx_number_parse("1.2.3");
  let c = xlsx_number_parse("1,000");
  let d = xlsx_number_parse("1e30");
  let e = xlsx_number_parse("");
  var ok = true;
  if a.is_ok || b.is_ok || c.is_ok || d.is_ok || e.is_ok { ok = false; }
  return report(ok, "number parse errors");
}

fn t04() -> Int {
  let a = xlsx_number_parse("0.0000005");
  let b = xlsx_number_parse("0.00000049");
  let c = xlsx_number_parse("-0.0000005");
  let d = xlsx_number_parse("0.0000015");
  var ok = true;
  if !a.is_ok || a.value != 1 { ok = false; }
  if !b.is_ok || b.value != 0 { ok = false; }
  if !c.is_ok || c.value != -1 { ok = false; }
  if !d.is_ok || d.value != 2 { ok = false; }
  return report(ok, "number rounding half away from zero");
}

// --------------------------------------------------
//  XML escape / unescape
// --------------------------------------------------

fn t05() -> Int {
  var ok = true;
  if !str_eq(xlsx_xml_escape("a<b>&\"'"), "a&lt;b&gt;&amp;&quot;&apos;") { ok = false; }
  if !str_eq(xlsx_xml_escape("\u{0001}"), "&#x01;") { ok = false; }
  if !str_eq(xlsx_xml_escape("a\rb"), "a&#xD;b") { ok = false; }
  if !str_eq(xlsx_xml_escape("tab\tok"), "tab\tok") { ok = false; }
  return report(ok, "xml escape");
}

fn t06() -> Int {
  let src = "a<&>\"'\u{0001}\u{0007}\u{007F}\r\t\nz";
  let e = xlsx_xml_escape(src);
  let u = xlsx_xml_unescape(e);
  if !u.is_ok {
    return report(false, "xml escape/unescape roundtrip");
  }
  return report(str_eq(u.value, src), "xml escape/unescape roundtrip");
}

fn t07() -> Int {
  let a = xlsx_xml_unescape("&#0;");
  let b = xlsx_xml_unescape("&bogus;");
  let c = xlsx_xml_unescape("&amp");
  let d = xlsx_xml_unescape("&#xD800;");
  let e = xlsx_xml_unescape("\u{0001}");
  let f = xlsx_xml_unescape("&#x1F;");
  let g = xlsx_xml_unescape("&amp;&lt;&#65;&#x42;");
  var ok = true;
  if a.is_ok || b.is_ok || c.is_ok || d.is_ok || e.is_ok { ok = false; }
  if !f.is_ok { ok = false; }
  if !g.is_ok || !str_eq(g.value, "&<AB") { ok = false; }
  return report(ok, "xml unescape validation");
}

// --------------------------------------------------
//  ZIP container
// --------------------------------------------------

fn t08() -> Int {
  let payload = bytes_of("hello zip stored");
  let zw = zip1("greeting.txt", payload, 0);
  if !zw.is_ok {
    return report(false, "zip stored scan");
  }
  let bytes: Vec[UInt8] = zw.value;
  let zr = xlsx_zip_scan(&bytes);
  if !zr.is_ok {
    return report(false, "zip stored scan");
  }
  let z: XlsxZip = zr.value;
  var ok = true;
  if xlsx_zip_count(&z) != 1 { ok = false; }
  let nm = xlsx_zip_name(&z, 0);
  if !nm.is_ok || !str_eq(nm.value, "greeting.txt") { ok = false; }
  let md = xlsx_zip_entry_method(&z, 0);
  if !md.is_ok || md.value != 0 { ok = false; }
  let dl = xlsx_zip_data(&z, 0);
  if !dl.is_ok { ok = false; } else {
    let data: Vec[UInt8] = dl.value;
    if !bytes_eq(&data, &payload) { ok = false; }
  }
  return report(ok, "zip stored scan");
}

fn t09() -> Int {
  var raw = Vec[UInt8].new();
  var i = 0;
  while i < 400 {
    raw.push(65u8);
    i = i + 1;
  }
  let zw = zip1("repeat.bin", raw, 8);
  if !zw.is_ok {
    return report(false, "zip deflate scan");
  }
  let bytes: Vec[UInt8] = zw.value;
  let zr = xlsx_zip_scan(&bytes);
  if !zr.is_ok {
    return report(false, "zip deflate scan");
  }
  let z: XlsxZip = zr.value;
  var ok = true;
  let md = xlsx_zip_entry_method(&z, 0);
  if !md.is_ok || md.value != 8 { ok = false; }
  let sz = xlsx_zip_entry_size(&z, 0);
  if !sz.is_ok || sz.value != 400 { ok = false; }
  let dl = xlsx_zip_data(&z, 0);
  if !dl.is_ok { ok = false; } else {
    let data: Vec[UInt8] = dl.value;
    if !bytes_eq(&data, &raw) { ok = false; }
  }
  return report(ok, "zip deflate scan");
}

fn t10() -> Int {
  var ok = true;
  let empty = Vec[UInt8].new();
  let r0 = xlsx_zip_scan(&empty);
  if r0.is_ok { ok = false; }
  var tiny = Vec[UInt8].new();
  var i = 0;
  while i < 22 {
    tiny.push(0u8);
    i = i + 1;
  }
  let r1 = xlsx_zip_scan(&tiny);
  if r1.is_ok { ok = false; }
  let zw = zip1("a.txt", bytes_of("abc"), 0);
  if !zw.is_ok {
    return report(false, "zip malformed archives");
  }
  var bytes: Vec[UInt8] = zw.value;
  let cd = find_sig(&bytes, 0x02014b50);
  if cd < 0 {
    return report(false, "zip malformed archives");
  }
  patch_u16(&mut bytes, cd + 10, 12);
  let r2 = xlsx_zip_scan(&bytes);
  if r2.is_ok { ok = false; }
  return report(ok, "zip malformed archives");
}

fn t11() -> Int {
  let payload = bytes_of("crc-test");
  let zw = zip1("c.txt", payload, 0);
  if !zw.is_ok {
    return report(false, "zip crc verification");
  }
  var bytes: Vec[UInt8] = zw.value;
  let cd = find_sig(&bytes, 0x02014b50);
  if cd < 0 {
    return report(false, "zip crc verification");
  }
  let c0: Int = (bytes[cd + 16] as Int) & 0xFF;
  let c1: Int = (bytes[cd + 17] as Int) & 0xFF;
  let cur = c0 + c1 * 256;
  patch_u16(&mut bytes, cd + 16, (cur + 1) % 65536);
  let r = xlsx_zip_scan(&bytes);
  return report(!r.is_ok, "zip crc verification");
}

fn t12() -> Int {
  var wb = xlsx_workbook_new();
  let s0 = xlsx_add_sheet(&mut wb, "Data");
  let s1 = xlsx_add_sheet(&mut wb, "Bools");
  if !s0.is_ok || s0.value != 0 || !s1.is_ok || s1.value != 1 {
    return report(false, "workbook roundtrip number/string/bool");
  }
  let n1 = xlsx_set_number(&mut wb, 0, 0, 0, 3140000);
  let n2 = xlsx_set_number(&mut wb, 0, 2, 1, -1500000);
  let st = xlsx_set_string(&mut wb, 0, 1, 0, "hi");
  let bt = xlsx_set_bool(&mut wb, 1, 0, 0, true);
  let bf = xlsx_set_bool(&mut wb, 1, 1, 0, false);
  if !n1.is_ok || !n2.is_ok || !st.is_ok || !bt.is_ok || !bf.is_ok {
    return report(false, "workbook roundtrip number/string/bool");
  }
  let zw = xlsx_write(&wb, 6);
  if !zw.is_ok {
    return report(false, "workbook roundtrip number/string/bool");
  }
  let bytes: Vec[UInt8] = zw.value;
  let wr = xlsx_read(&bytes);
  if !wr.is_ok {
    return report(false, "workbook roundtrip number/string/bool");
  }
  let w2: XlsxWorkbook = wr.value;
  var ok = true;
  if xlsx_sheet_count(&w2) != 2 { ok = false; }
  let sn = xlsx_sheet_name(&w2, 0);
  if !sn.is_ok || !str_eq(sn.value, "Data") { ok = false; }
  let a = xlsx_cell_number_scaled(&w2, 0, 0, 0);
  if !a.is_ok || a.value != 3140000 { ok = false; }
  let b = xlsx_cell_number_scaled(&w2, 0, 2, 1);
  if !b.is_ok || b.value != -1500000 { ok = false; }
  let c = xlsx_cell_string(&w2, 0, 1, 0);
  if !c.is_ok || !str_eq(c.value, "hi") { ok = false; }
  let d = xlsx_cell_bool(&w2, 1, 0, 0);
  if !d.is_ok || d.value != true { ok = false; }
  let e = xlsx_cell_bool(&w2, 1, 1, 0);
  if !e.is_ok || e.value != false { ok = false; }
  return report(ok, "workbook roundtrip number/string/bool");
}

fn t13() -> Int {
  var wb = xlsx_workbook_new();
  let s0 = xlsx_add_sheet(&mut wb, "S");
  if !s0.is_ok {
    return report(false, "workbook stored roundtrip");
  }
  let n1 = xlsx_set_number(&mut wb, 0, 0, 0, 7000000);
  if !n1.is_ok {
    return report(false, "workbook stored roundtrip");
  }
  let zw = xlsx_write(&wb, 0);
  if !zw.is_ok {
    return report(false, "workbook stored roundtrip");
  }
  let bytes: Vec[UInt8] = zw.value;
  let zr = xlsx_zip_scan(&bytes);
  if !zr.is_ok {
    return report(false, "workbook stored roundtrip");
  }
  let z: XlsxZip = zr.value;
  var ok = true;
  if xlsx_zip_count(&z) < 6 { ok = false; }
  var i = 0;
  while i < xlsx_zip_count(&z) {
    let m = xlsx_zip_entry_method(&z, i);
    if !m.is_ok || m.value != 0 { ok = false; }
    i = i + 1;
  }
  let wr = xlsx_read(&bytes);
  if !wr.is_ok { ok = false; } else {
    let w2: XlsxWorkbook = wr.value;
    let v = xlsx_cell_number_scaled(&w2, 0, 0, 0);
    if !v.is_ok || v.value != 7000000 { ok = false; }
  }
  return report(ok, "workbook stored roundtrip");
}

fn t14() -> Int {
  var wb = xlsx_workbook_new();
  let s0 = xlsx_add_sheet(&mut wb, "Sparse");
  if !s0.is_ok {
    return report(false, "sparse cells and sorted sheet XML");
  }
  let n1 = xlsx_set_number(&mut wb, 0, 0, 0, 1000000);
  let n2 = xlsx_set_number(&mut wb, 0, 6, 2, 2000000);
  if !n1.is_ok || !n2.is_ok {
    return report(false, "sparse cells and sorted sheet XML");
  }
  let zw = xlsx_write(&wb, 0);
  if !zw.is_ok {
    return report(false, "sparse cells and sorted sheet XML");
  }
  let bytes: Vec[UInt8] = zw.value;
  let zr = xlsx_zip_scan(&bytes);
  if !zr.is_ok {
    return report(false, "sparse cells and sorted sheet XML");
  }
  let z: XlsxZip = zr.value;
  let sheet = entry_text(&z, "xl/worksheets/sheet1.xml");
  var ok = true;
  if !string.str_contains(sheet, "A1") { ok = false; }
  if !string.str_contains(sheet, "C7") { ok = false; }
  if !string.str_contains(sheet, "<row r=\"1\">") { ok = false; }
  if !string.str_contains(sheet, "<row r=\"7\">") { ok = false; }
  let wr = xlsx_read(&bytes);
  if !wr.is_ok { ok = false; } else {
    let w2: XlsxWorkbook = wr.value;
    let miss = xlsx_cell_kind(&w2, 0, 1, 1);
    if miss.is_ok { ok = false; }
    let cc = xlsx_sheet_cell_count(&w2, 0);
    if !cc.is_ok || cc.value != 2 { ok = false; }
  }
  return report(ok, "sparse cells and sorted sheet XML");
}
fn t15() -> Int {
  var wb = xlsx_workbook_new();
  let s0 = xlsx_add_sheet(&mut wb, "S");
  if !s0.is_ok {
    return report(false, "string pool dedup");
  }
  let a = xlsx_set_string(&mut wb, 0, 0, 0, "same");
  let b = xlsx_set_string(&mut wb, 0, 1, 0, "same");
  let c = xlsx_set_string(&mut wb, 0, 2, 0, "other");
  if !a.is_ok || !b.is_ok || !c.is_ok {
    return report(false, "string pool dedup");
  }
  var ok = true;
  if xlsx_string_count(&wb) != 2 { ok = false; }
  let zw = xlsx_write(&wb, 0);
  if !zw.is_ok {
    return report(false, "string pool dedup");
  }
  let bytes: Vec[UInt8] = zw.value;
  let zr = xlsx_zip_scan(&bytes);
  if !zr.is_ok {
    return report(false, "string pool dedup");
  }
  let z: XlsxZip = zr.value;
  let sst = entry_text(&z, "xl/sharedStrings.xml");
  if !string.str_contains(sst, "uniqueCount=\"2\"") { ok = false; }
  let wr = xlsx_read(&bytes);
  if !wr.is_ok { ok = false; } else {
    let w2: XlsxWorkbook = wr.value;
    if xlsx_string_count(&w2) != 2 { ok = false; }
    let v0 = xlsx_cell_string(&w2, 0, 0, 0);
    let v2 = xlsx_cell_string(&w2, 0, 2, 0);
    if !v0.is_ok || !str_eq(v0.value, "same") { ok = false; }
    if !v2.is_ok || !str_eq(v2.value, "other") { ok = false; }
  }
  return report(ok, "string pool dedup");
}

fn t16() -> Int {
  var wb = xlsx_workbook_new();
  let s0 = xlsx_add_sheet(&mut wb, "Styled");
  let st = xlsx_add_style(&mut wb, true, true, 14, 0xFF112233, "0.000");
  if !s0.is_ok || st != 0 {
    return report(false, "style roundtrip");
  }
  let n1 = xlsx_set_number(&mut wb, 0, 0, 0, 1234567);
  let ss = xlsx_set_style(&mut wb, 0, 0, 0, st);
  if !n1.is_ok || !ss.is_ok {
    return report(false, "style roundtrip");
  }
  let zw = xlsx_write(&wb, 6);
  if !zw.is_ok {
    return report(false, "style roundtrip");
  }
  let bytes: Vec[UInt8] = zw.value;
  let wr = xlsx_read(&bytes);
  if !wr.is_ok {
    return report(false, "style roundtrip");
  }
  let w2: XlsxWorkbook = wr.value;
  var ok = true;
  if xlsx_style_count(&w2) != 1 { ok = false; }
  let bold = xlsx_style_bold(&w2, 0);
  let ital = xlsx_style_italic(&w2, 0);
  let size = xlsx_style_size(&w2, 0);
  let colr = xlsx_style_color(&w2, 0);
  let fmt = xlsx_style_numfmt(&w2, 0);
  if !bold.is_ok || bold.value != true { ok = false; }
  if !ital.is_ok || ital.value != true { ok = false; }
  if !size.is_ok || size.value != 14 { ok = false; }
  if !colr.is_ok || colr.value != 4279312947 { ok = false; }
  if !fmt.is_ok || !str_eq(fmt.value, "0.000") { ok = false; }
  let cs = xlsx_cell_style(&w2, 0, 0, 0);
  if !cs.is_ok || cs.value != 0 { ok = false; }
  return report(ok, "style roundtrip");
}

fn t17() -> Int {
  var wb = xlsx_workbook_new();
  let s0 = xlsx_add_sheet(&mut wb, "Fmt");
  let st = xlsx_add_style(&mut wb, false, false, 11, 0xFF000000, "0.00");
  if !s0.is_ok || st != 0 {
    return report(false, "builtin number format roundtrip");
  }
  let n1 = xlsx_set_number(&mut wb, 0, 0, 0, 2500000);
  let ss = xlsx_set_style(&mut wb, 0, 0, 0, 0);
  if !n1.is_ok || !ss.is_ok {
    return report(false, "builtin number format roundtrip");
  }
  let zw = xlsx_write(&wb, 0);
  if !zw.is_ok {
    return report(false, "builtin number format roundtrip");
  }
  let bytes: Vec[UInt8] = zw.value;
  let zr = xlsx_zip_scan(&bytes);
  if !zr.is_ok {
    return report(false, "builtin number format roundtrip");
  }
  let z: XlsxZip = zr.value;
  let styles = entry_text(&z, "xl/styles.xml");
  var ok = true;
  if !string.str_contains(styles, "numFmtId=\"2\"") { ok = false; }
  if string.str_contains(styles, "<numFmts") { ok = false; }
  let wr = xlsx_read(&bytes);
  if !wr.is_ok { ok = false; } else {
    let w2: XlsxWorkbook = wr.value;
    let fmt = xlsx_style_numfmt(&w2, 0);
    if !fmt.is_ok || !str_eq(fmt.value, "0.00") { ok = false; }
  }
  return report(ok, "builtin number format roundtrip");
}

fn t18() -> Int {
  var wb = xlsx_workbook_new();
  let bad1 = xlsx_add_sheet(&mut wb, "");
  let bad2 = xlsx_add_sheet(&mut wb, "abcdefghijklmnopqrstuvwxyz123456");
  let bad3 = xlsx_add_sheet(&mut wb, "a/b");
  let bad4 = xlsx_add_sheet(&mut wb, "a[b]");
  var ok = true;
  if bad1.is_ok || bad2.is_ok || bad3.is_ok || bad4.is_ok { ok = false; }
  let g1 = xlsx_add_sheet(&mut wb, "Data 1");
  if !g1.is_ok || g1.value != 0 { ok = false; }
  let dup = xlsx_add_sheet(&mut wb, "Data 1");
  if dup.is_ok { ok = false; }
  if xlsx_sheet_count(&wb) != 1 { ok = false; }
  if !xlsx_sheet_name_valid("ok") { ok = false; }
  return report(ok, "sheet name validation");
}

fn t19() -> Int {
  var wb = xlsx_workbook_new();
  let s0 = xlsx_add_sheet(&mut wb, "S");
  let n1 = xlsx_set_number(&mut wb, 0, 0, 0, 1000000);
  let b1 = xlsx_set_bool(&mut wb, 0, 1, 0, true);
  if !s0.is_ok || !n1.is_ok || !b1.is_ok {
    return report(false, "accessor error catalog");
  }
  var ok = true;
  let a = xlsx_sheet_name(&wb, 5);
  if a.is_ok { ok = false; }
  let b = xlsx_cell_string(&wb, 0, 0, 0);
  if b.is_ok { ok = false; }
  let c = xlsx_cell_number_scaled(&wb, 0, 1, 0);
  if c.is_ok { ok = false; }
  let d = xlsx_cell_kind(&wb, 0, 9, 9);
  if d.is_ok { ok = false; }
  let e = xlsx_style_bold(&wb, 0);
  if e.is_ok { ok = false; }
  let f = xlsx_set_style(&mut wb, 0, 9, 9, 0);
  if f.is_ok { ok = false; }
  let g = xlsx_set_number(&mut wb, 0, -1, 0, 0);
  if g.is_ok { ok = false; }
  return report(ok, "accessor error catalog");
}

fn t20() -> Int {
  var wb = xlsx_workbook_new();
  let s0 = xlsx_add_sheet(&mut wb, "Text");
  if !s0.is_ok {
    return report(false, "unicode and control text roundtrip");
  }
  let v0 = "h\u{00E9}llo";
  let v1 = "\u{0001}\u{0007}";
  let v2 = "a\tb\nc";
  let v3 = "<&>\"'";
  let a = xlsx_set_string(&mut wb, 0, 0, 0, v0);
  let b = xlsx_set_string(&mut wb, 0, 1, 0, v1);
  let c = xlsx_set_string(&mut wb, 0, 2, 0, v2);
  let d = xlsx_set_string(&mut wb, 0, 3, 0, v3);
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok {
    return report(false, "unicode and control text roundtrip");
  }
  let zw = xlsx_write(&wb, 6);
  if !zw.is_ok {
    return report(false, "unicode and control text roundtrip");
  }
  let bytes: Vec[UInt8] = zw.value;
  let wr = xlsx_read(&bytes);
  if !wr.is_ok {
    return report(false, "unicode and control text roundtrip");
  }
  let w2: XlsxWorkbook = wr.value;
  var ok = true;
  let r0 = xlsx_cell_string(&w2, 0, 0, 0);
  let r1 = xlsx_cell_string(&w2, 0, 1, 0);
  let r2 = xlsx_cell_string(&w2, 0, 2, 0);
  let r3 = xlsx_cell_string(&w2, 0, 3, 0);
  if !r0.is_ok || !str_eq(r0.value, v0) { ok = false; }
  if !r1.is_ok || !str_eq(r1.value, v1) { ok = false; }
  if !r2.is_ok || !str_eq(r2.value, v2) { ok = false; }
  if !r3.is_ok || !str_eq(r3.value, v3) { ok = false; }
  return report(ok, "unicode and control text roundtrip");
}

fn t21() -> Int {
  let wb = xlsx_workbook_new();
  let zw = xlsx_write(&wb, 6);
  if !zw.is_ok {
    return report(false, "empty workbook");
  }
  let bytes: Vec[UInt8] = zw.value;
  let zr = xlsx_zip_scan(&bytes);
  if !zr.is_ok {
    return report(false, "empty workbook");
  }
  let z: XlsxZip = zr.value;
  var ok = true;
  if xlsx_zip_count(&z) != 6 { ok = false; }
  if xlsx_zip_find(&z, "xl/workbook.xml") < 0 { ok = false; }
  let wr = xlsx_read(&bytes);
  if !wr.is_ok { ok = false; } else {
    let w2: XlsxWorkbook = wr.value;
    if xlsx_sheet_count(&w2) != 0 { ok = false; }
  }
  return report(ok, "empty workbook");
}

fn t22() -> Int {
  let zw = zip1("hello.txt", bytes_of("not a workbook"), 0);
  if !zw.is_ok {
    return report(false, "missing workbook part");
  }
  let bytes: Vec[UInt8] = zw.value;
  let wr = xlsx_read(&bytes);
  return report(!wr.is_ok, "missing workbook part");
}

fn t23() -> Int {
  let wbx = bytes_of("<workbook><sheets><sheet name=\"S\" sheetId=\"1\"/></sheets></workbook>");
  let sheet = bytes_of("<worksheet><sheetData><row r=\"1\"><c r=\"A1\"><v>7</v></c></row></sheetData></worksheet>");
  let styles = bytes_of("<styleSheet/>");
  let sst = bytes_of("<sst count=\"0\" uniqueCount=\"0\"></sst>");
  let zw = zip4("xl/workbook.xml", wbx, 0, "xl/worksheets/sheet1.xml", sheet, 0, "xl/styles.xml", styles, 0, "xl/sharedStrings.xml", sst, 0);
  if !zw.is_ok {
    return report(false, "sheet part fallback when r:id is absent");
  }
  let bytes: Vec[UInt8] = zw.value;
  let wr = xlsx_read(&bytes);
  if !wr.is_ok {
    return report(false, "sheet part fallback when r:id is absent");
  }
  let w2: XlsxWorkbook = wr.value;
  var ok = true;
  if xlsx_sheet_count(&w2) != 1 { ok = false; }
  let sn = xlsx_sheet_name(&w2, 0);
  if !sn.is_ok || !str_eq(sn.value, "S") { ok = false; }
  let v = xlsx_cell_number_scaled(&w2, 0, 0, 0);
  if !v.is_ok || v.value != 7000000 { ok = false; }
  return report(ok, "sheet part fallback when r:id is absent");
}

fn t24() -> Int {
  let wbx = bytes_of("<workbook><sheets><sheet name=\"S\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>");
  let rels = bytes_of("<Relationships><Relationship Id=\"rId1\" Type=\"x\" Target=\"worksheets/sheet1.xml\"/></Relationships>");
  let sst = bytes_of("<sst count=\"1\" uniqueCount=\"1\"><si><t>only</t></si></sst>");
  let sheet = bytes_of("<worksheet><sheetData><row r=\"1\"><c r=\"A1\" t=\"s\"><v>5</v></c></row></sheetData></worksheet>");
  let zw = zip4("xl/workbook.xml", wbx, 0, "xl/_rels/workbook.xml.rels", rels, 0, "xl/sharedStrings.xml", sst, 0, "xl/worksheets/sheet1.xml", sheet, 0);
  if !zw.is_ok {
    return report(false, "shared string index out of range");
  }
  let bytes: Vec[UInt8] = zw.value;
  let wr = xlsx_read(&bytes);
  return report(!wr.is_ok, "shared string index out of range");
}

fn t25() -> Int {
  let wbx = bytes_of("<workbook><sheets><sheet name=\"S\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>");
  let rels = bytes_of("<Relationships><Relationship Id=\"rId1\" Type=\"x\" Target=\"worksheets/sheet1.xml\"/></Relationships>");
  let sheet = bytes_of("<worksheet><sheetData><row r=\"1\"><c r=\"$B$2\"><v>1.5</v></c><c r=\"AA10\" t=\"b\"><v>1</v></c></row></sheetData></worksheet>");
  let styles = bytes_of("<styleSheet/>");
  let zw = zip4("xl/workbook.xml", wbx, 0, "xl/_rels/workbook.xml.rels", rels, 0, "xl/worksheets/sheet1.xml", sheet, 0, "xl/styles.xml", styles, 0);
  if !zw.is_ok {
    return report(false, "cell reference parsing");
  }
  let bytes: Vec[UInt8] = zw.value;
  let wr = xlsx_read(&bytes);
  if !wr.is_ok {
    return report(false, "cell reference parsing");
  }
  let w2: XlsxWorkbook = wr.value;
  var ok = true;
  let a = xlsx_cell_number_scaled(&w2, 0, 1, 1);
  if !a.is_ok || a.value != 1500000 { ok = false; }
  let b = xlsx_cell_bool(&w2, 0, 9, 26);
  if !b.is_ok || b.value != true { ok = false; }
  return report(ok, "cell reference parsing");
}

fn t26() -> Int {
  let wbx = bytes_of("<workbook><sheets><sheet name=\"S\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>");
  let rels = bytes_of("<Relationships><Relationship Id=\"rId1\" Type=\"x\" Target=\"worksheets/sheet1.xml\"/></Relationships>");
  let sheet = bytes_of("<worksheet><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>in&amp;line</t></is></c><c r=\"B1\" t=\"str\"><v>fx&lt;x</v></c></row></sheetData></worksheet>");
  let sst = bytes_of("<sst count=\"0\" uniqueCount=\"0\"></sst>");
  let zw = zip4("xl/workbook.xml", wbx, 0, "xl/_rels/workbook.xml.rels", rels, 0, "xl/worksheets/sheet1.xml", sheet, 0, "xl/sharedStrings.xml", sst, 0);
  if !zw.is_ok {
    return report(false, "inlineStr and str cell reading");
  }
  let bytes: Vec[UInt8] = zw.value;
  let wr = xlsx_read(&bytes);
  if !wr.is_ok {
    return report(false, "inlineStr and str cell reading");
  }
  let w2: XlsxWorkbook = wr.value;
  var ok = true;
  let a = xlsx_cell_string(&w2, 0, 0, 0);
  if !a.is_ok || !str_eq(a.value, "in&line") { ok = false; }
  let b = xlsx_cell_string(&w2, 0, 0, 1);
  if !b.is_ok || !str_eq(b.value, "fx<x") { ok = false; }
  return report(ok, "inlineStr and str cell reading");
}

fn t27() -> Int {
  let zw = zip1("a.txt", bytes_of("abc"), 0);
  if !zw.is_ok {
    return report(false, "zip64 rejection");
  }
  var bytes: Vec[UInt8] = zw.value;
  let eocd = find_sig(&bytes, 0x06054b50);
  if eocd < 0 {
    return report(false, "zip64 rejection");
  }
  patch_u16(&mut bytes, eocd + 10, 65535);
  let r = xlsx_zip_scan(&bytes);
  return report(!r.is_ok, "zip64 rejection");
}

fn t28() -> Int {
  var names = Vec[Str].new();
  var methods = Vec[Int].new();
  var pool = Vec[UInt8].new();
  var offs = Vec[Int].new();
  var lens = Vec[Int].new();
  let d1 = bytes_of("stored part");
  let d2 = bytes_of("deflated part");
  names.push("a.bin"); methods.push(0);
  names.push("b.bin"); methods.push(8);
  offs.push(0); lens.push(d1.len());
  offs.push(d1.len()); lens.push(d2.len());
  var i = 0;
  while i < d1.len() { let v: UInt8 = d1[i]; pool.push(v); i = i + 1; }
  i = 0;
  while i < d2.len() { let v2: UInt8 = d2[i]; pool.push(v2); i = i + 1; }
  let zw = xlsx_zip_write(&names, &methods, &pool, &offs, &lens);
  if !zw.is_ok {
    return report(false, "mixed stored/deflate archive");
  }
  let bytes: Vec[UInt8] = zw.value;
  let zr = xlsx_zip_scan(&bytes);
  if !zr.is_ok {
    return report(false, "mixed stored/deflate archive");
  }
  let z: XlsxZip = zr.value;
  var ok = true;
  if xlsx_zip_count(&z) != 2 { ok = false; }
  let m0 = xlsx_zip_entry_method(&z, 0);
  let m1 = xlsx_zip_entry_method(&z, 1);
  if !m0.is_ok || m0.value != 0 { ok = false; }
  if !m1.is_ok || m1.value != 8 { ok = false; }
  let p0 = xlsx_zip_data(&z, 0);
  let p1 = xlsx_zip_data(&z, 1);
  if !p0.is_ok || !p1.is_ok {
    ok = false;
  } else {
    let b0: Vec[UInt8] = p0.value;
    let b1: Vec[UInt8] = p1.value;
    if !bytes_eq(&b0, &d1) { ok = false; }
    if !bytes_eq(&b1, &d2) { ok = false; }
  }
  return report(ok, "mixed stored/deflate archive");
}

fn main() -> Int {
  io.println("=== xiom.xlsx conformance tests ===");
  var failed: Int = 0;
  failed = failed + t01();
  failed = failed + t02();
  failed = failed + t03();
  failed = failed + t04();
  failed = failed + t05();
  failed = failed + t06();
  failed = failed + t07();
  failed = failed + t08();
  failed = failed + t09();
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
  failed = failed + t28();
  if failed == 0 {
    io.println("xiom.xlsx: all tests passed");
  } else {
    io.println("xiom.xlsx: tests failed");
  }
  return failed;
}
