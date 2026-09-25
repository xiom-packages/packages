// XIOM -- xiom.dtb conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented flat DTB format against a fully hand-computed
// canonical v17 blob (299 bytes, literal hex in blob1_hex()), then covers:
// header and reservation accessors; node name/depth/parent layout;
// property owner/name/value accessors; property lookup by name and node
// lookup by absolute path; out-of-range accessors and short source
// buffers; byte-identical canonical emission; NOP skipping plus
// strings-block first-use canonicalization; memory reservations including
// a u64 with bit 63 set; v16 acceptance and v17 canonicalization; lenient
// nonzero padding; totalsize handling and trailing bytes; and the full
// error catalog (header, magic, version, block bounds, token nesting,
// unterminated names, property errors, invalid trees).
//
// Str values read from Vec elements are never compared with `==` (BUG 17:
// pointer comparison); error texts go through compare.str_compare, and
// every Vec[Int] element read is bound to a typed local.

module dtb_tests
use xiom.io; use xiom.test;
use xiom.dtb;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte and string helpers
// --------------------------------------------------

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < string.str_len(s) {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
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

fn copy_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn append_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

fn prefix(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Little byte / result helpers
// --------------------------------------------------

fn be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

fn be8(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(be_byte(v, i));
    i = i - 1;
  }
}

fn be32(out: &mut Vec[UInt8], v: Int) {
  be8(out, v, 4);
}

fn set8(v: &mut Vec[UInt8], pos: Int, val: Int) {
  v[pos] = be_byte(val, 0);
}

fn set32(v: &mut Vec[UInt8], pos: Int, val: Int) {
  var i = 0;
  while i < 4 {
    v[pos + i] = be_byte(val, 3 - i);
    i = i + 1;
  }
}

fn err_tree_is(r: Result[Dtb, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

// --------------------------------------------------
//  Blob builders (mirror the byte-level layout; the canonical v17 blob in
//  blob1_hex() is the independent hand-computed anchor)
// --------------------------------------------------

fn tok(out: &mut Vec[UInt8], t: Int) {
  be8(out, t, 4);
}

fn begin_node(out: &mut Vec[UInt8], name: Vec[UInt8]) {
  let start = out.len();
  tok(out, 1);
  var i = 0;
  while i < name.len() {
    out.push(name[i]);
    i = i + 1;
  }
  out.push(0 as UInt8);
  var used = out.len() - start;
  while used % 4 != 0 {
    out.push(0 as UInt8);
    used = used + 1;
  }
}

fn prop(out: &mut Vec[UInt8], nameoff: Int, value: Vec[UInt8]) {
  let start = out.len();
  tok(out, 3);
  tok(out, value.len());
  tok(out, nameoff);
  var i = 0;
  while i < value.len() {
    out.push(value[i]);
    i = i + 1;
  }
  var used = out.len() - start;
  while used % 4 != 0 {
    out.push(0 as UInt8);
    used = used + 1;
  }
}

fn end_node(out: &mut Vec[UInt8]) {
  tok(out, 2);
}

fn nop(out: &mut Vec[UInt8]) {
  tok(out, 4);
}

fn fdt_end(out: &mut Vec[UInt8]) {
  tok(out, 9);
}

fn append_text_nul(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < string.str_len(s) {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  out.push(0 as UInt8);
}

fn nul_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  append_text_nul(&mut v, s);
  return v;
}

fn empty_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn strings1() -> Vec[UInt8] {
  return nul_bytes("compatible");
}

// Assemble a canonical v17 blob from a structure block, a strings block,
// a boot CPU id and memory reservation pairs (the terminator is added).
fn assemble(struct_bytes: Vec[UInt8], strings: Vec<UInt8>, boot: Int, rsv_addr: Vec[Int], rsv_size: Vec<Int>) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let rn = rsv_addr.len();
  let rsv_bytes = 16 * (rn + 1);
  let off_struct = 40 + rsv_bytes;
  let off_strings = off_struct + struct_bytes.len();
  let total = off_strings + strings.len();
  be32(&mut out, 3490578157);   // magic 0xd00dfeed
  be32(&mut out, total);
  be32(&mut out, off_struct);
  be32(&mut out, off_strings);
  be32(&mut out, 40);
  be32(&mut out, 17);
  be32(&mut out, 16);
  be32(&mut out, boot);
  be32(&mut out, strings.len());
  be32(&mut out, struct_bytes.len());
  var i = 0;
  while i < rn {
    let a: Int = rsv_addr[i];
    let s: Int = rsv_size[i];
    be8(&mut out, a, 8);
    be8(&mut out, s, 8);
    i = i + 1;
  }
  var z = 0;
  while z < 16 {
    out.push(0 as UInt8);
    z = z + 1;
  }
  append_bytes(&mut out, &struct_bytes);
  append_bytes(&mut out, &strings);
  return out;
}

// Canonical v17 blob, 299 bytes, hand-computed from the specification:
// root "" with "compatible" = "acme,board\0" and "model" = "Acme Board";
// child "soc@0" with "compatible" = "simple-bus", "ranges" = empty and
// "#address-cells" = 00000001; grandchild "uart@1000" with "compatible" =
// "ns16550a" and "reg" = 00000000 00001000 00000000 00000100. Strings
// block in first-use order (compatible, model, ranges, #address-cells,
// reg). Header: totalsize 299, off_dt_struct 56, off_dt_strings 256,
// off_mem_rsvmap 40, version 17, last_comp_version 16, boot_cpuid 0,
// size_dt_strings 43, size_dt_struct 200; 16-byte 0/0 reservation
// terminator.
fn blob1_hex() -> Str {
  var s: Str = "d00dfeed0000012b0000003800000100000000280000001100000010000000000000002b000000c8000000000000000000000000000000000000000100000000000000030000000b";
  s = s + "0000000061636d652c626f6172640000000000030000000a0000000b41636d6520426f617264000000000001736f634030000000000000030000000a0000000073696d706c652d62";
  s = s + "7573000000000003000000000000001100000003000000040000001800000001000000017561727440313030300000000000000300000008000000006e7331363535306100000003";
  s = s + "00000010000000270000000000001000000000000000010000000002000000020000000200000009636f6d70617469626c65006d6f64656c0072616e676573002361646472657373";
  s = s + "2d63656c6c730072656700";
  return s;
}

// Blob with two reservations (0x10000000/0x2000 and the bit-63 u64
// 0x8000000000000000/1), boot_cpuid 42 and root "board" with
// "compatible" = "acme\0". Built by the test helpers, emitted bytes must
// match it exactly.
fn blob2_bytes() -> Vec[UInt8] {
  var s = Vec[UInt8].new();
  begin_node(&mut s, bytes_of("board"));
  prop(&mut s, 0, nul_bytes("acme"));
  end_node(&mut s);
  fdt_end(&mut s);
  var a = Vec[Int].new();
  var z = Vec[Int].new();
  let big: Int = 268435456;                 // 0x10000000
  let huge: Int = -9223372036854775807 - 1; // 0x8000000000000000
  a.push(big);
  a.push(huge);
  z.push(8192);
  z.push(1);
  return assemble(s, nul_bytes("compatible"), 42, a, z);
}

// Non-canonical version of the blob1 tree: FDT_NOPs inserted and the
// strings block in reverse first-use order (reg, #address-cells, ranges,
// model, compatible) with matching name offsets. Parsing then emitting
// must reproduce the canonical blob1 bytes exactly.
fn blob3_bytes() -> Vec<UInt8> {
  var s = Vec[UInt8].new();
  begin_node(&mut s, Vec[UInt8].new());
  nop(&mut s);
  prop(&mut s, 32, nul_bytes("acme,board"));
  prop(&mut s, 26, bytes_of("Acme Board"));
  nop(&mut s);
  begin_node(&mut s, bytes_of("soc@0"));
  prop(&mut s, 32, bytes_of("simple-bus"));
  prop(&mut s, 19, Vec[UInt8].new());
  prop(&mut s, 4, hb("00000001"));
  nop(&mut s);
  begin_node(&mut s, bytes_of("uart@1000"));
  prop(&mut s, 32, bytes_of("ns16550a"));
  prop(&mut s, 0, hb("00000000000010000000000000000100"));
  end_node(&mut s);
  end_node(&mut s);
  end_node(&mut s);
  fdt_end(&mut s);
  var strings = nul_bytes("reg");
  append_text_nul(&mut strings, "#address-cells");
  append_text_nul(&mut strings, "ranges");
  append_text_nul(&mut strings, "model");
  append_text_nul(&mut strings, "compatible");
  return assemble(s, strings, 0, empty_ints(), empty_ints());
}

// --------------------------------------------------
//  Parsed-store probe helpers
// --------------------------------------------------

fn name_is(data: &Vec[UInt8], d: &Dtb, i: Int, want: Str) -> Bool {
  let r = dtb_node_name(data, d, i);
  if !r.is_ok {
    return false;
  }
  let s: Str = r.value;
  return str_eq(s, want);
}

fn root_name_is(data: &Vec[UInt8], d: &Dtb, want: Str) -> Bool {
  return str_eq(dtb_root_name(data, d), want);
}

fn pname_is(data: &Vec[UInt8], d: &Dtb, i: Int, want: Str) -> Bool {
  let r = dtb_prop_name(data, d, i);
  if !r.is_ok {
    return false;
  }
  let s: Str = r.value;
  return str_eq(s, want);
}

fn pvalue_is(data: &Vec[UInt8], d: &Dtb, i: Int, want: Vec[UInt8]) -> Bool {
  let r = dtb_prop_value(data, d, i);
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

fn emit_of(data: &Vec[UInt8], d: &Dtb) -> Vec[UInt8] {
  let r = dtb_emit(data, d);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

fn empty_dtb() -> Dtb {
  return Dtb{
    totalsize: 0;
    version: 0;
    last_comp_version: 0;
    boot_cpuid_phys: 0;
    off_dt_struct: 0;
    size_dt_struct: 0;
    off_dt_strings: 0;
    size_dt_strings: 0;
    off_mem_rsvmap: 0;
    rsv_address: Vec[Int].new();
    rsv_size: Vec[Int].new();
    node_name_off: Vec[Int].new();
    node_name_len: Vec[Int].new();
    node_depth: Vec[Int].new();
    node_parent: Vec[Int].new();
    prop_node: Vec[Int].new();
    prop_name_off: Vec[Int].new();
    prop_value_off: Vec[Int].new();
    prop_value_len: Vec[Int].new();
  };
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = hb(blob1_hex());
  let pr = dtb_parse(&data);
  if !pr.is_ok {
    return assert(false, "canonical v17 blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_version(&d) == 17;
  if dtb_last_comp_version(&d) != 16 { ok = false; }
  if dtb_boot_cpuid_phys(&d) != 0 { ok = false; }
  if dtb_total_size(&d) != 299 { ok = false; }
  if dtb_strings_size(&d) != 43 { ok = false; }
  if dtb_mem_rsv_count(&d) != 0 { ok = false; }
  if d.off_dt_struct != 56 { ok = false; }
  if d.off_dt_strings != 256 { ok = false; }
  if d.off_mem_rsvmap != 40 { ok = false; }
  if d.size_dt_struct != 200 { ok = false; }
  if data.len() != 299 { ok = false; }
  return assert(ok, "canonical header fields parse exactly");
}

fn t2() -> TestResult {
  let data = hb(blob1_hex());
  let pr = dtb_parse(&data);
  if !pr.is_ok {
    return assert(false, "canonical v17 blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_node_count(&d) == 3;
  if !root_name_is(&data, &d, "") { ok = false; }
  if !name_is(&data, &d, 0, "") { ok = false; }
  if !name_is(&data, &d, 1, "soc@0") { ok = false; }
  if !name_is(&data, &d, 2, "uart@1000") { ok = false; }
  if dtb_node_depth(&d, 0) != 0 { ok = false; }
  if dtb_node_depth(&d, 1) != 1 { ok = false; }
  if dtb_node_depth(&d, 2) != 2 { ok = false; }
  if dtb_node_parent(&d, 0) != -1 { ok = false; }
  if dtb_node_parent(&d, 1) != 0 { ok = false; }
  if dtb_node_parent(&d, 2) != 1 { ok = false; }
  return assert(ok, "canonical node names, depths and parents parse exactly");
}

fn t3() -> TestResult {
  let data = hb(blob1_hex());
  let pr = dtb_parse(&data);
  if !pr.is_ok {
    return assert(false, "canonical v17 blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_prop_count(&d) == 7;
  if dtb_prop_node(&d, 0) != 0 { ok = false; }
  if dtb_prop_node(&d, 1) != 0 { ok = false; }
  if dtb_prop_node(&d, 2) != 1 { ok = false; }
  if dtb_prop_node(&d, 3) != 1 { ok = false; }
  if dtb_prop_node(&d, 4) != 1 { ok = false; }
  if dtb_prop_node(&d, 5) != 2 { ok = false; }
  if dtb_prop_node(&d, 6) != 2 { ok = false; }
  if !pname_is(&data, &d, 0, "compatible") { ok = false; }
  if !pname_is(&data, &d, 1, "model") { ok = false; }
  if !pname_is(&data, &d, 3, "ranges") { ok = false; }
  if !pname_is(&data, &d, 4, "#address-cells") { ok = false; }
  if !pname_is(&data, &d, 6, "reg") { ok = false; }
  if !pvalue_is(&data, &d, 0, hb("61636d652c626f61726400")) { ok = false; }
  if !pvalue_is(&data, &d, 1, bytes_of("Acme Board")) { ok = false; }
  if !pvalue_is(&data, &d, 3, Vec[UInt8].new()) { ok = false; }
  if !pvalue_is(&data, &d, 4, hb("00000001")) { ok = false; }
  if dtb_prop_value_len(&d, 6) != 16 { ok = false; }
  if !pvalue_is(&data, &d, 6, hb("00000000000010000000000000000100")) { ok = false; }
  return assert(ok, "canonical property owners, names and values parse exactly");
}

fn t4() -> TestResult {
  let data = hb(blob1_hex());
  let pr = dtb_parse(&data);
  if !pr.is_ok {
    return assert(false, "canonical v17 blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_find_property(&data, &d, 0, "compatible") == 0;
  if dtb_find_property(&data, &d, 0, "model") != 1 { ok = false; }
  if dtb_find_property(&data, &d, 1, "compatible") != 2 { ok = false; }
  if dtb_find_property(&data, &d, 1, "ranges") != 3 { ok = false; }
  if dtb_find_property(&data, &d, 2, "reg") != 6 { ok = false; }
  if dtb_find_property(&data, &d, 2, "model") != -1 { ok = false; }
  if dtb_find_property(&data, &d, 7, "reg") != -1 { ok = false; }
  if dtb_find_property(&data, &d, -1, "reg") != -1 { ok = false; }
  if dtb_find_property(&data, &d, 2, "compat") != -1 { ok = false; }
  if dtb_find_property(&data, &d, 2, "compatible-x") != -1 { ok = false; }
  if dtb_find_property(&data, &d, 0, "") != -1 { ok = false; }
  return assert(ok, "property lookup by name is exact and scoped to a node");
}

fn t5() -> TestResult {
  let data = hb(blob1_hex());
  let pr = dtb_parse(&data);
  if !pr.is_ok {
    return assert(false, "canonical v17 blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_find_node(&data, &d, "") == 0;
  if dtb_find_node(&data, &d, "/") != 0 { ok = false; }
  if dtb_find_node(&data, &d, "/soc@0") != 1 { ok = false; }
  if dtb_find_node(&data, &d, "/soc@0/uart@1000") != 2 { ok = false; }
  if dtb_find_node(&data, &d, "/soc@0/") != 1 { ok = false; }
  if dtb_find_node(&data, &d, "soc@0") != -1 { ok = false; }
  if dtb_find_node(&data, &d, "//soc@0") != -1 { ok = false; }
  if dtb_find_node(&data, &d, "/uart@1000") != -1 { ok = false; }
  if dtb_find_node(&data, &d, "/soc@0/uart@1000/x") != -1 { ok = false; }
  if dtb_find_node(&data, &d, "/SOC@0") != -1 { ok = false; }
  return assert(ok, "absolute path lookup resolves, rejects and is case-sensitive");
}

fn t6() -> TestResult {
  let data = hb(blob1_hex());
  let pr = dtb_parse(&data);
  if !pr.is_ok {
    return assert(false, "canonical v17 blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_node_depth(&d, 3) == -1;
  if dtb_node_depth(&d, -1) != -1 { ok = false; }
  if dtb_node_parent(&d, 99) != -1 { ok = false; }
  if !err_str_is(dtb_node_name(&data, &d, 3), "dtb: node index out of range") { ok = false; }
  if !err_str_is(dtb_node_name(&data, &d, -1), "dtb: node index out of range") { ok = false; }
  if !err_str_is(dtb_prop_name(&data, &d, 7), "dtb: property index out of range") { ok = false; }
  if !err_bytes_is(dtb_prop_value(&data, &d, 7), "dtb: property index out of range") { ok = false; }
  if dtb_prop_node(&d, 7) != -1 { ok = false; }
  if dtb_prop_value_len(&d, 7) != -1 { ok = false; }
  if dtb_prop_value_len(&d, -1) != -1 { ok = false; }
  let cut = prefix(&data, 80);
  if !err_bytes_is(dtb_prop_value(&cut, &d, 6), "dtb: property value out of bounds") { ok = false; }
  return assert(ok, "out-of-range accessors and short buffers report -1 or Err");
}

fn t7() -> TestResult {
  let data = hb(blob1_hex());
  let pr = dtb_parse(&data);
  if !pr.is_ok {
    return assert(false, "canonical v17 blob must parse");
  }
  let d: Dtb = pr.value;
  let er = dtb_emit(&data, &d);
  if !er.is_ok {
    return assert(false, "canonical emit must succeed");
  }
  let out: Vec[UInt8] = er.value;
  var ok = bytes_equal(out, data);
  if out.len() != 299 { ok = false; }
  return assert(ok, "parse -> emit reproduces the canonical v17 blob byte for byte");
}

fn t8() -> TestResult {
  let canonical = hb(blob1_hex());
  let src = blob3_bytes();
  let pr = dtb_parse(&src);
  if !pr.is_ok {
    return assert(false, "non-canonical blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_node_count(&d) == 3;
  if dtb_prop_count(&d) != 7 { ok = false; }
  if !name_is(&src, &d, 2, "uart@1000") { ok = false; }
  if !pname_is(&src, &d, 3, "ranges") { ok = false; }
  let er = dtb_emit(&src, &d);
  if !er.is_ok {
    return assert(false, "non-canonical emit must succeed");
  }
  let out: Vec[UInt8] = er.value;
  if !bytes_equal(out, canonical) { ok = false; }
  return assert(ok, "FDT_NOPs are skipped and strings are re-emitted in first-use order");
}

fn t9() -> TestResult {
  let src = blob2_bytes();
  let pr = dtb_parse(&src);
  if !pr.is_ok {
    return assert(false, "reservation blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_mem_rsv_count(&d) == 2;
  if dtb_mem_rsv_address(&d, 0) != 268435456 { ok = false; }
  if dtb_mem_rsv_size(&d, 0) != 8192 { ok = false; }
  if dtb_mem_rsv_address(&d, 1) != (-9223372036854775807 - 1) { ok = false; }
  if dtb_mem_rsv_size(&d, 1) != 1 { ok = false; }
  if dtb_mem_rsv_address(&d, 2) != -1 { ok = false; }
  if dtb_mem_rsv_size(&d, 2) != -1 { ok = false; }
  if dtb_boot_cpuid_phys(&d) != 42 { ok = false; }
  if dtb_node_count(&d) != 1 { ok = false; }
  if !root_name_is(&src, &d, "board") { ok = false; }
  if !name_is(&src, &d, 0, "board") { ok = false; }
  if dtb_find_property(&src, &d, 0, "compatible") != 0 { ok = false; }
  if !pvalue_is(&src, &d, 0, hb("61636d6500")) { ok = false; }
  let er = dtb_emit(&src, &d);
  if !er.is_ok {
    return assert(false, "reservation emit must succeed");
  }
  let out: Vec[UInt8] = er.value;
  if !bytes_equal(out, src) { ok = false; }
  return assert(ok, "reservations (incl. a bit-63 u64) and boot_cpuid round-trip");
}

fn t10() -> TestResult {
  let canonical = hb(blob1_hex());
  var v16 = copy_bytes(&canonical);
  set32(&mut v16, 20, 16);
  set32(&mut v16, 36, 999999);
  let pr = dtb_parse(&v16);
  if !pr.is_ok {
    return assert(false, "v16 blob must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_version(&d) == 16;
  if dtb_node_count(&d) != 3 { ok = false; }
  if d.size_dt_struct != 200 { ok = false; }
  let er = dtb_emit(&v16, &d);
  if !er.is_ok {
    return assert(false, "v16 emit must succeed");
  }
  let out: Vec[UInt8] = er.value;
  if !bytes_equal(out, canonical) { ok = false; }
  var bad = copy_bytes(&v16);
  set32(&mut bad, 24, 17);
  if !err_tree_is(dtb_parse(&bad), "dtb: bad last_comp_version") { ok = false; }
  return assert(ok, "v16 is accepted (size derived) and emits canonical v17 bytes");
}

fn t11() -> TestResult {
  let canonical = hb(blob1_hex());
  var padded = copy_bytes(&canonical);
  set8(&mut padded, 61, 171);   // root name pad
  set8(&mut padded, 62, 171);
  set8(&mut padded, 63, 171);
  set8(&mut padded, 87, 205);   // first property value pad
  let pr = dtb_parse(&padded);
  if !pr.is_ok {
    return assert(false, "nonzero padding must parse");
  }
  let d: Dtb = pr.value;
  var ok = dtb_node_count(&d) == 3;
  if !name_is(&padded, &d, 0, "") { ok = false; }
  if !pvalue_is(&padded, &d, 0, hb("61636d652c626f61726400")) { ok = false; }
  let out = emit_of(&padded, &d);
  if !bytes_equal(out, canonical) { ok = false; }
  return assert(ok, "nonzero padding parses (lenient) and emit writes zeros");
}

fn t12() -> TestResult {
  let canonical = hb(blob1_hex());
  var longer = copy_bytes(&canonical);
  var j = 0;
  while j < 8 {
    longer.push(238 as UInt8);
    j = j + 1;
  }
  let pr = dtb_parse(&longer);
  if !pr.is_ok {
    return assert(false, "bytes past totalsize must be ignored");
  }
  let d: Dtb = pr.value;
  var ok = dtb_node_count(&d) == 3;
  let out = emit_of(&longer, &d);
  if !bytes_equal(out, canonical) { ok = false; }
  var big = copy_bytes(&canonical);
  set32(&mut big, 4, 5000);
  if !err_tree_is(dtb_parse(&big), "dtb: totalsize out of range") { ok = false; }
  var small = copy_bytes(&canonical);
  set32(&mut small, 4, 39);
  if !err_tree_is(dtb_parse(&small), "dtb: totalsize out of range") { ok = false; }
  return assert(ok, "trailing bytes are ignored; bogus totalsize is rejected");
}

fn t13() -> TestResult {
  let canonical = hb(blob1_hex());
  let short = prefix(&canonical, 39);
  var ok = err_tree_is(dtb_parse(&short), "dtb: header truncated");
  var magic = copy_bytes(&canonical);
  set32(&mut magic, 0, 305419896);
  if !err_tree_is(dtb_parse(&magic), "dtb: bad magic") { ok = false; }
  var v18 = copy_bytes(&canonical);
  set32(&mut v18, 20, 18);
  if !err_tree_is(dtb_parse(&v18), "dtb: unsupported version") { ok = false; }
  var v15 = copy_bytes(&canonical);
  set32(&mut v15, 20, 15);
  if !err_tree_is(dtb_parse(&v15), "dtb: unsupported version") { ok = false; }
  return assert(ok, "header truncation, bad magic and bad versions are rejected");
}

fn t14() -> TestResult {
  let canonical = hb(blob1_hex());
  var a = copy_bytes(&canonical);
  set32(&mut a, 8, 5000);
  var ok = err_tree_is(dtb_parse(&a), "dtb: struct block out of range");
  var b = copy_bytes(&canonical);
  set32(&mut b, 36, 1000);
  if !err_tree_is(dtb_parse(&b), "dtb: struct block out of range") { ok = false; }
  var c = copy_bytes(&canonical);
  set32(&mut c, 36, 0);
  if !err_tree_is(dtb_parse(&c), "dtb: struct block out of range") { ok = false; }
  var e = copy_bytes(&canonical);
  set32(&mut e, 12, 400);
  if !err_tree_is(dtb_parse(&e), "dtb: strings block out of range") { ok = false; }
  var f = copy_bytes(&canonical);
  set32(&mut f, 32, 1000);
  if !err_tree_is(dtb_parse(&f), "dtb: strings block out of range") { ok = false; }
  var g = copy_bytes(&canonical);
  set32(&mut g, 16, 290);
  if !err_tree_is(dtb_parse(&g), "dtb: memory reservation block out of range") { ok = false; }
  return assert(ok, "out-of-buffer block offsets and sizes are rejected");
}

fn t15() -> TestResult {
  var s1 = Vec[UInt8].new();
  end_node(&mut s1);
  var ok = err_tree_is(dtb_parse(&assemble(s1, strings1(), 0, empty_ints(), empty_ints())), "dtb: unbalanced end node");
  var s2 = Vec[UInt8].new();
  begin_node(&mut s2, Vec[UInt8].new());
  fdt_end(&mut s2);
  if !err_tree_is(dtb_parse(&assemble(s2, strings1(), 0, empty_ints(), empty_ints())), "dtb: unbalanced node nesting") { ok = false; }
  var s3 = Vec[UInt8].new();
  begin_node(&mut s3, Vec[UInt8].new());
  tok(&mut s3, 5);
  fdt_end(&mut s3);
  if !err_tree_is(dtb_parse(&assemble(s3, strings1(), 0, empty_ints(), empty_ints())), "dtb: unknown token") { ok = false; }
  var s4 = Vec[UInt8].new();
  begin_node(&mut s4, Vec[UInt8].new());
  if !err_tree_is(dtb_parse(&assemble(s4, strings1(), 0, empty_ints(), empty_ints())), "dtb: truncated structure block") { ok = false; }
  var s5 = Vec[UInt8].new();
  begin_node(&mut s5, Vec[UInt8].new());
  end_node(&mut s5);
  begin_node(&mut s5, Vec[UInt8].new());
  if !err_tree_is(dtb_parse(&assemble(s5, strings1(), 0, empty_ints(), empty_ints())), "dtb: multiple root nodes") { ok = false; }
  var s6 = Vec[UInt8].new();
  fdt_end(&mut s6);
  if !err_tree_is(dtb_parse(&assemble(s6, strings1(), 0, empty_ints(), empty_ints())), "dtb: missing root node") { ok = false; }
  return assert(ok, "token nesting, unknown tokens and missing root/end are rejected");
}

fn t16() -> TestResult {
  var s = Vec[UInt8].new();
  tok(&mut s, 1);
  s.push(97 as UInt8);
  s.push(98 as UInt8);
  s.push(99 as UInt8);
  let blob = assemble(s, strings1(), 0, empty_ints(), empty_ints());
  return assert(err_tree_is(dtb_parse(&blob), "dtb: unterminated node name"), "a node name without a NUL before the block end is rejected");
}

fn t17() -> TestResult {
  var s1 = Vec[UInt8].new();
  begin_node(&mut s1, Vec[UInt8].new());
  tok(&mut s1, 3);
  tok(&mut s1, 8);
  tok(&mut s1, 0);
  s1.push(120 as UInt8);
  s1.push(121 as UInt8);
  var ok = err_tree_is(dtb_parse(&assemble(s1, strings1(), 0, empty_ints(), empty_ints())), "dtb: property value out of range");
  var s2 = Vec[UInt8].new();
  begin_node(&mut s2, Vec[UInt8].new());
  prop(&mut s2, 99, bytes_of("x"));
  end_node(&mut s2);
  fdt_end(&mut s2);
  if !err_tree_is(dtb_parse(&assemble(s2, strings1(), 0, empty_ints(), empty_ints())), "dtb: property name offset out of range") { ok = false; }
  var s3 = Vec[UInt8].new();
  begin_node(&mut s3, Vec[UInt8].new());
  prop(&mut s3, 0, bytes_of("x"));
  end_node(&mut s3);
  fdt_end(&mut s3);
  if !err_tree_is(dtb_parse(&assemble(s3, bytes_of("abc"), 0, empty_ints(), empty_ints())), "dtb: unterminated property name") { ok = false; }
  var s4 = Vec[UInt8].new();
  begin_node(&mut s4, Vec[UInt8].new());
  prop(&mut s4, 0, bytes_of("x"));
  end_node(&mut s4);
  fdt_end(&mut s4);
  if !err_tree_is(dtb_parse(&assemble(s4, Vec[UInt8].new(), 0, empty_ints(), empty_ints())), "dtb: property name offset out of range") { ok = false; }
  var s5 = Vec[UInt8].new();
  prop(&mut s5, 0, bytes_of("x"));
  fdt_end(&mut s5);
  if !err_tree_is(dtb_parse(&assemble(s5, strings1(), 0, empty_ints(), empty_ints())), "dtb: property outside node") { ok = false; }
  return assert(ok, "property value, name-offset and placement errors are rejected");
}

fn t18() -> TestResult {
  let data = hb(blob1_hex());
  var empty = empty_dtb();
  var ok = err_bytes_is(dtb_emit(&data, &empty), "dtb: invalid tree");
  var drift = empty_dtb();
  drift.node_name_off.push(60);
  if !err_bytes_is(dtb_emit(&data, &drift), "dtb: invalid tree") { ok = false; }
  let pr = dtb_parse(&data);
  if pr.is_ok {
    let d: Dtb = pr.value;
    let er = dtb_emit(&data, &d);
    if !er.is_ok { ok = false; }
  }
  return assert(ok, "the emitter refuses empty and drifted stores");
}

fn main() -> Int {
  io.println("=== xiom.dtb conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.dtb: all tests passed");
  } else {
    io.println("xiom.dtb: tests failed");
  }
  return failed;
}
