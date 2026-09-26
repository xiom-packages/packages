// XIOM -- xiom.acpi conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented ACPI table-layer behavior against two hand-computed
// buffers: fixture A (RSDP revision 0 + RSDT + FACP-like table, 104 bytes)
// and fixture B (RSDP revision 2 + XSDT + DSDT-like + FACP-like tables, 172
// bytes). Covers the RSDP revision/address/OEM accessors and both checksum
// helpers, the walker's zero-entry policy, table spans/signatures/OEM IDs,
// first-match lookup with tolerated duplicate signatures, the full error
// catalog, and the canonical builders (table, RSDT, XSDT, RSDP rev0/rev2)
// against the pinned fixtures.
//
// Str values are never compared with `==` (BUG 17 discipline); error texts
// go through compare.str_compare, and every Vec element read is bound to a
// typed local.

module acpi_tests
use xiom.io; use xiom.test;
use xiom.acpi;
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
  while i < s.len() {
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn concat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
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

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn slice_bytes(v: Vec[UInt8], from: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len && from + i < v.len() {
    out.push(v[from + i]);
    i = i + 1;
  }
  return out;
}

fn patched(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(val as UInt8);
    } else {
      let b: UInt8 = v[i];
      out.push(b);
    }
    i = i + 1;
  }
  return out;
}

fn sum8_local(v: Vec[UInt8], off: Int, len: Int) -> Int {
  var s: Int = 0;
  var i = 0;
  while i < len {
    let b: UInt8 = v[off + i];
    s = s + ((b as Int) & 0xFF);
    i = i + 1;
  }
  return s % 256;
}

// Independent checksum fixer: copy `v` with the byte at `ckpos` set so that
// the bytes in [off, off + len) sum to 0 modulo 256.
fn fix_checksum(v: Vec[UInt8], ckpos: Int, off: Int, len: Int) -> Vec[UInt8] {
  var s: Int = 0;
  var k = 0;
  while k < len {
    let b: UInt8 = v[off + k];
    if off + k != ckpos {
      s = s + ((b as Int) & 0xFF);
    }
    k = k + 1;
  }
  let ck: Int = (256 - (s % 256)) % 256;
  var out = Vec[UInt8].new();
  var j = 0;
  while j < v.len() {
    if j == ckpos {
      out.push(ck as UInt8);
    } else {
      let b2: UInt8 = v[j];
      out.push(b2);
    }
    j = j + 1;
  }
  return out;
}

// --------------------------------------------------
//  Result and field helpers
// --------------------------------------------------

fn err_rsdp_is(r: Result[AcpiRsdp, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_set_is(r: Result[AcpiTableSet, Str], want: Str) -> Bool {
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

fn sig_bytes(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Vec[UInt8] {
  let r = acpi_table_signature_bytes(data, t, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn oem_bytes(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Vec[UInt8] {
  let r = acpi_table_oem_id(data, t, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn oem_tid_bytes(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Vec[UInt8] {
  let r = acpi_table_oem_table_id(data, t, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn creator_bytes(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Vec[UInt8] {
  let r = acpi_table_creator_id(data, t, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn body_bytes(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Vec[UInt8] {
  let r = acpi_table_body(data, t, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// --------------------------------------------------
//  Pinned fixtures
// --------------------------------------------------

// RSDP rev0 (20) + RSDT with one u32 entry -> 60 (40) + FACP-like (44).
fn fixture_a() -> Vec[UInt8] {
  return hb("52534420505452205058494f4d202000140000005253445428000000016358494f4d202058494f4d504b47200100000058494f4d000001003c000000464143502c000000059e58494f4d202058494f4d504b47200100000058494f4d000001000001020304050607");
}

// RSDP rev2 (36) + XSDT with two u64 entries -> 88/128 (52) + DSDT-like
// (40) + FACP-like (44).
fn fixture_b() -> Vec[UInt8] {
  return hb("52534420505452206258494f4d20200200000000240000002400000000000000b8000000585344543400000001b558494f4d202058494f4d504b47200100000058494f4d00000100580000000000000080000000000000004453445428000000027458494f4d202058494f4d504b47200100000058494f4d00000100deadbeef464143502c000000069d58494f4d202058494f4d504b47200100000058494f4d000001000001020304050607");
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture_a();
  let r = acpi_rsdp_parse(&data);
  if !r.is_ok { return assert(false, "rev0 RSDP must parse"); }
  let p: AcpiRsdp = r.value;
  var ok = acpi_rsdp_revision(&p) == 0;
  if acpi_rsdp_length(&p) != 20 { ok = false; }
  if acpi_rsdp_rsdt_address(&p) != 20 { ok = false; }
  if acpi_rsdp_xsdt_address(&p) != 0 { ok = false; }
  if !bytes_equal(acpi_rsdp_oem_id(&p), bytes_of("XIOM  ")) { ok = false; }
  if !acpi_checksum_valid(&data, 0, 20) { ok = false; }
  return assert(ok, "rev0 RSDP: revision, length, RSDT address, OEMID, base checksum");
}

fn t2() -> TestResult {
  let data = fixture_a();
  var ok = err_rsdp_is(acpi_rsdp_parse(&prefix(data, 19)), "acpi: buffer too short");
  let bad_sig = patched(data, 0, 0x58);
  if !err_rsdp_is(acpi_rsdp_parse(&bad_sig), "acpi: bad rsdp signature") { ok = false; }
  let bad_ck = patched(data, 12, 0x5A);
  if !err_rsdp_is(acpi_rsdp_parse(&bad_ck), "acpi: bad rsdp checksum") { ok = false; }
  var rev1 = patched(data, 15, 1);
  rev1 = fix_checksum(rev1, 8, 0, 20);
  if !err_rsdp_is(acpi_rsdp_parse(&rev1), "acpi: unsupported rsdp revision") { ok = false; }
  var rev255 = patched(data, 15, 255);
  rev255 = fix_checksum(rev255, 8, 0, 20);
  if !err_rsdp_is(acpi_rsdp_parse(&rev255), "acpi: unsupported rsdp revision") { ok = false; }
  return assert(ok, "RSDP errors: short buffer, bad signature, bad checksum, bad revision");
}

fn t3() -> TestResult {
  let data = fixture_b();
  let r = acpi_rsdp_parse(&data);
  if !r.is_ok { return assert(false, "rev2 RSDP must parse"); }
  let p: AcpiRsdp = r.value;
  var ok = acpi_rsdp_revision(&p) == 2;
  if acpi_rsdp_length(&p) != 36 { ok = false; }
  if acpi_rsdp_rsdt_address(&p) != 0 { ok = false; }
  if acpi_rsdp_xsdt_address(&p) != 36 { ok = false; }
  if !bytes_equal(acpi_rsdp_oem_id(&p), bytes_of("XIOM  ")) { ok = false; }
  if !acpi_checksum_valid(&data, 0, 20) { ok = false; }
  if !acpi_checksum_valid(&data, 20, 16) { ok = false; }
  return assert(ok, "rev2 RSDP: length, RSDT/XSDT addresses and both checksums");
}

fn t4() -> TestResult {
  let data = fixture_b();
  var ok = err_rsdp_is(acpi_rsdp_parse(&patched(data, 20, 35)), "acpi: bad rsdp length");
  if !err_rsdp_is(acpi_rsdp_parse(&patched(data, 20, 200)), "acpi: bad rsdp length") { ok = false; }
  if !err_rsdp_is(acpi_rsdp_parse(&prefix(data, 30)), "acpi: bad rsdp length") { ok = false; }
  if !err_rsdp_is(acpi_rsdp_parse(&patched(data, 33, 0xFF)), "acpi: bad rsdp extended checksum") { ok = false; }
  var bad_oem = patched(data, 10, 0x01);
  bad_oem = fix_checksum(bad_oem, 8, 0, 20);
  if !err_rsdp_is(acpi_rsdp_parse(&bad_oem), "acpi: rsdp oem id not printable") { ok = false; }
  return assert(ok, "rev2 RSDP errors: bad length, extended checksum, non-printable OEMID");
}

fn t5() -> TestResult {
  let data = fixture_a();
  let r = acpi_walk_rsdt(&data, 20);
  if !r.is_ok { return assert(false, "RSDT chain must walk"); }
  let t: AcpiTableSet = r.value;
  var ok = acpi_table_count(&t) == 1;
  if acpi_table_offset(&t, 0) != 60 { ok = false; }
  if acpi_table_length(&t, 0) != 44 { ok = false; }
  if acpi_table_revision(&t, 0) != 5 { ok = false; }
  if acpi_table_signature(&t, 0) != acpi_signature_value("FACP") { ok = false; }
  if acpi_find_table(&t, "FACP") != 0 { ok = false; }
  if acpi_find_table(&t, "DSDT") != -1 { ok = false; }
  if acpi_find_table(&t, "FAC") != -1 { ok = false; }
  return assert(ok, "RSDT walk resolves the FACP entry with pinned span and signature");
}

fn t6() -> TestResult {
  let data = fixture_a();
  let r = acpi_walk_rsdt(&data, 20);
  if !r.is_ok { return assert(false, "RSDT chain must walk"); }
  let t: AcpiTableSet = r.value;
  var ok = bytes_equal(sig_bytes(&data, &t, 0), bytes_of("FACP"));
  if !bytes_equal(oem_bytes(&data, &t, 0), bytes_of("XIOM  ")) { ok = false; }
  if !bytes_equal(oem_tid_bytes(&data, &t, 0), bytes_of("XIOMPKG ")) { ok = false; }
  if !bytes_equal(creator_bytes(&data, &t, 0), bytes_of("XIOM")) { ok = false; }
  if acpi_table_oem_revision(&data, &t, 0) != 1 { ok = false; }
  if acpi_table_creator_revision(&data, &t, 0) != 65536 { ok = false; }
  if acpi_table_body_offset(&data, &t, 0) != 96 { ok = false; }
  if acpi_table_body_length(&t, 0) != 8 { ok = false; }
  if !acpi_table_span_ok(&data, &t, 0) { ok = false; }
  if !bytes_equal(body_bytes(&data, &t, 0), hb("0001020304050607")) { ok = false; }
  if acpi_table_offset(&t, -1) != -1 { ok = false; }
  if acpi_table_signature(&t, 1) != -1 { ok = false; }
  if !err_bytes_is(acpi_table_oem_id(&data, &t, 1), "acpi: index out of range") { ok = false; }
  if !err_bytes_is(acpi_table_body(&data, &t, 5), "acpi: index out of range") { ok = false; }
  let cut = prefix(data, 100);
  if acpi_table_span_ok(&cut, &t, 0) { ok = false; }
  if !err_bytes_is(acpi_table_body(&cut, &t, 0), "acpi: table span out of bounds") { ok = false; }
  if !bytes_equal(sig_bytes(&cut, &t, 0), bytes_of("FACP")) { ok = false; }
  return assert(ok, "table accessors: IDs, revisions, body span, bounds errors");
}

fn t7() -> TestResult {
  let data = fixture_a();
  var ok = err_set_is(acpi_walk_rsdt(&data, 22), "acpi: table address not aligned");
  if !err_set_is(acpi_walk_rsdt(&data, 100), "acpi: table header out of range") { ok = false; }
  var bad_sig = patched(data, 20, 0x58);
  bad_sig = fix_checksum(bad_sig, 29, 20, 40);
  if !err_set_is(acpi_walk_rsdt(&bad_sig, 20), "acpi: bad root signature") { ok = false; }
  var bad_print = patched(data, 20, 0x01);
  bad_print = fix_checksum(bad_print, 29, 20, 40);
  if !err_set_is(acpi_walk_rsdt(&bad_print, 20), "acpi: table signature not printable") { ok = false; }
  if !err_set_is(acpi_walk_rsdt(&patched(data, 29, 0xAA), 20), "acpi: bad table checksum") { ok = false; }
  if !err_set_is(acpi_walk_rsdt(&patched(data, 24, 35), 20), "acpi: table length out of range") { ok = false; }
  if !err_set_is(acpi_walk_rsdt(&patched(data, 24, 200), 20), "acpi: table length out of range") { ok = false; }
  var mis = patched(data, 24, 41);
  mis = fix_checksum(mis, 29, 20, 41);
  if !err_set_is(acpi_walk_rsdt(&mis, 20), "acpi: rsdt length misaligned") { ok = false; }
  return assert(ok, "RSDT root errors: alignment, bounds, signature, checksum, length");
}

fn t8() -> TestResult {
  let facp = slice_bytes(fixture_a(), 60, 44);
  var e1 = Vec[Int].new();
  e1.push(0);
  e1.push(60);
  let b1 = acpi_build_rsdt(&e1, "XIOM", "XIOMPKG", "XIOM", 65536);
  if !b1.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt1: Vec[UInt8] = b1.value;
  let buf1 = concat2(concat2(rsdt1, zeros(16)), facp);
  let w1 = acpi_walk_rsdt(&buf1, 0);
  if !w1.is_ok { return assert(false, "zero-skip walk must succeed"); }
  let t1: AcpiTableSet = w1.value;
  var ok = acpi_table_count(&t1) == 1;
  if acpi_table_offset(&t1, 0) != 60 { ok = false; }
  var e2 = Vec[Int].new();
  e2.push(60);
  e2.push(0);
  let b2 = acpi_build_rsdt(&e2, "XIOM", "XIOMPKG", "XIOM", 65536);
  if !b2.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt2: Vec[UInt8] = b2.value;
  let buf2 = concat2(concat2(rsdt2, zeros(16)), facp);
  let w2 = acpi_walk_rsdt(&buf2, 0);
  if !w2.is_ok { ok = false; } else {
    let t2: AcpiTableSet = w2.value;
    if acpi_table_count(&t2) != 1 { ok = false; }
    if acpi_table_offset(&t2, 0) != 60 { ok = false; }
  }
  var e3 = Vec[Int].new();
  e3.push(0);
  e3.push(0);
  let b3 = acpi_build_rsdt(&e3, "XIOM", "XIOMPKG", "XIOM", 65536);
  if !b3.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt3: Vec[UInt8] = b3.value;
  let w3 = acpi_walk_rsdt(&rsdt3, 0);
  if !w3.is_ok { ok = false; } else {
    let t3: AcpiTableSet = w3.value;
    if acpi_table_count(&t3) != 0 { ok = false; }
    if acpi_find_table(&t3, "FACP") != -1 { ok = false; }
  }
  return assert(ok, "zero entries are skipped and do not terminate the walk");
}

fn t9() -> TestResult {
  var e1 = Vec[Int].new();
  e1.push(62);
  let b1 = acpi_build_rsdt(&e1, "XIOM", "XIOMPKG", "XIOM", 1);
  if !b1.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt1: Vec[UInt8] = b1.value;
  var ok = err_set_is(acpi_walk_rsdt(&rsdt1, 0), "acpi: table address not aligned");
  var e2 = Vec[Int].new();
  e2.push(1000);
  let b2 = acpi_build_rsdt(&e2, "XIOM", "XIOMPKG", "XIOM", 1);
  if !b2.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt2: Vec[UInt8] = b2.value;
  if !err_set_is(acpi_walk_rsdt(&rsdt2, 0), "acpi: table header out of range") { ok = false; }
  var e3 = Vec[Int].new();
  e3.push(40);
  let b3 = acpi_build_rsdt(&e3, "XIOM", "XIOMPKG", "XIOM", 1);
  if !b3.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt3: Vec[UInt8] = b3.value;
  let facp = slice_bytes(fixture_a(), 60, 44);
  let buf3 = concat2(rsdt3, facp);
  let w3 = acpi_walk_rsdt(&buf3, 0);
  if !w3.is_ok { return assert(false, "valid chain must walk"); }
  let tw3: AcpiTableSet = w3.value;
  if acpi_table_count(&tw3) != 1 { ok = false; }
  if acpi_table_offset(&tw3, 0) != 40 { ok = false; }
  if !err_set_is(acpi_walk_rsdt(&patched(buf3, 49, 0x00), 0), "acpi: bad table checksum") { ok = false; }
  if !err_set_is(acpi_walk_rsdt(&patched(buf3, 44, 200), 0), "acpi: table length out of range") { ok = false; }
  if !err_set_is(acpi_walk_rsdt(&patched(buf3, 40, 0x01), 0), "acpi: table signature not printable") { ok = false; }
  return assert(ok, "entry errors: alignment, bounds, checksum, length, signature");
}

fn t10() -> TestResult {
  let data = fixture_b();
  let pr = acpi_rsdp_parse(&data);
  if !pr.is_ok { return assert(false, "rev2 RSDP must parse"); }
  let p: AcpiRsdp = pr.value;
  let wr = acpi_tables_from_rsdp(&data, &p);
  if !wr.is_ok { return assert(false, "XSDT chain must walk"); }
  let t: AcpiTableSet = wr.value;
  var ok = acpi_table_count(&t) == 2;
  if acpi_table_signature(&t, 0) != acpi_signature_value("DSDT") { ok = false; }
  if acpi_table_signature(&t, 1) != acpi_signature_value("FACP") { ok = false; }
  if acpi_table_offset(&t, 0) != 88 { ok = false; }
  if acpi_table_offset(&t, 1) != 128 { ok = false; }
  if acpi_table_length(&t, 0) != 40 { ok = false; }
  if acpi_table_length(&t, 1) != 44 { ok = false; }
  if acpi_table_revision(&t, 0) != 2 { ok = false; }
  if acpi_table_revision(&t, 1) != 6 { ok = false; }
  if acpi_find_table(&t, "DSDT") != 0 { ok = false; }
  if acpi_find_table(&t, "FACP") != 1 { ok = false; }
  if acpi_find_table(&t, "XSDT") != -1 { ok = false; }
  if !bytes_equal(body_bytes(&data, &t, 0), hb("deadbeef")) { ok = false; }
  return assert(ok, "XSDT walk: two tables, pinned spans, revisions and lookup");
}

fn t11() -> TestResult {
  let data_a = fixture_a();
  var ok = err_set_is(acpi_walk_xsdt(&data_a, 20), "acpi: bad root signature");
  let data = fixture_b();
  if !err_set_is(acpi_walk_xsdt(&patched(data, 45, 0xAA), 36), "acpi: bad table checksum") { ok = false; }
  var mis = patched(data, 40, 48);
  mis = fix_checksum(mis, 45, 36, 48);
  if !err_set_is(acpi_walk_xsdt(&mis, 36), "acpi: xsdt length misaligned") { ok = false; }
  var neg = patched(data, 87, 0x80);
  neg = fix_checksum(neg, 45, 36, 52);
  if !err_set_is(acpi_walk_xsdt(&neg, 36), "acpi: table address out of range") { ok = false; }
  if !err_set_is(acpi_walk_xsdt(&data, 168), "acpi: table header out of range") { ok = false; }
  return assert(ok, "XSDT errors: root signature, checksum, misalignment, negative u64");
}

fn t12() -> TestResult {
  let data_a = fixture_a();
  let pr_a = acpi_rsdp_parse(&data_a);
  if !pr_a.is_ok { return assert(false, "fixture A RSDP must parse"); }
  let p_a: AcpiRsdp = pr_a.value;
  let wa = acpi_tables_from_rsdp(&data_a, &p_a);
  var ok = wa.is_ok;
  if wa.is_ok {
    let ta: AcpiTableSet = wa.value;
    if acpi_table_count(&ta) != 1 { ok = false; }
    if acpi_find_table(&ta, "FACP") != 0 { ok = false; }
  }
  let data_b = fixture_b();
  let pr_b = acpi_rsdp_parse(&data_b);
  if !pr_b.is_ok { return assert(false, "fixture B RSDP must parse"); }
  let p_b: AcpiRsdp = pr_b.value;
  let wb = acpi_tables_from_rsdp(&data_b, &p_b);
  if !wb.is_ok { ok = false; } else {
    let tb: AcpiTableSet = wb.value;
    if acpi_table_count(&tb) != 2 { ok = false; }
  }
  var body = hb("deadbeef");
  let fr = acpi_build_table("FACP", 6, "XIOM", "XIOMPKG", 1, "XIOM", 1, &body);
  if !fr.is_ok { return assert(false, "table build must succeed"); }
  let facp: Vec[UInt8] = fr.value;
  var e = Vec[Int].new();
  e.push(76);
  let rr = acpi_build_rsdt(&e, "XIOM", "XIOMPKG", "XIOM", 1);
  if !rr.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt: Vec[UInt8] = rr.value;
  let sr = acpi_build_rsdp(2, 36, 0, "XIOM");
  if !sr.is_ok { return assert(false, "rsdp build must succeed"); }
  let rsdp: Vec[UInt8] = sr.value;
  let buf = concat2(concat2(rsdp, rsdt), facp);
  let pf = acpi_rsdp_parse(&buf);
  if !pf.is_ok { ok = false; } else {
    let p_f: AcpiRsdp = pf.value;
    if acpi_rsdp_xsdt_address(&p_f) != 0 { ok = false; }
    let wf = acpi_tables_from_rsdp(&buf, &p_f);
    if !wf.is_ok { ok = false; } else {
      let tf: AcpiTableSet = wf.value;
      if acpi_table_count(&tf) != 1 { ok = false; }
      if acpi_table_offset(&tf, 0) != 76 { ok = false; }
      if acpi_find_table(&tf, "FACP") != 0 { ok = false; }
    }
  }
  let nr0 = acpi_build_rsdp(0, 0, 0, "XIOM");
  if !nr0.is_ok { return assert(false, "rsdp build must succeed"); }
  let rsdp0: Vec[UInt8] = nr0.value;
  let p0r = acpi_rsdp_parse(&rsdp0);
  if !p0r.is_ok { ok = false; } else {
    let p0: AcpiRsdp = p0r.value;
    if !err_set_is(acpi_tables_from_rsdp(&rsdp0, &p0), "acpi: no table root") { ok = false; }
  }
  let nr2 = acpi_build_rsdp(2, 0, 0, "XIOM");
  if !nr2.is_ok { return assert(false, "rsdp build must succeed"); }
  let rsdp2: Vec[UInt8] = nr2.value;
  let p2r = acpi_rsdp_parse(&rsdp2);
  if !p2r.is_ok { ok = false; } else {
    let p2: AcpiRsdp = p2r.value;
    if !err_set_is(acpi_tables_from_rsdp(&rsdp2, &p2), "acpi: no table root") { ok = false; }
  }
  return assert(ok, "from_rsdp selects XSDT/RSDT, falls back and errors when rootless");
}

fn t13() -> TestResult {
  var body = hb("0001020304050607");
  let r = acpi_build_table("FACP", 5, "XIOM", "XIOMPKG", 1, "XIOM", 65536, &body);
  if !r.is_ok { return assert(false, "table build must succeed"); }
  let built: Vec[UInt8] = r.value;
  let fx = slice_bytes(fixture_a(), 60, 44);
  var ok = bytes_equal(built, fx);
  if built.len() != 44 { ok = false; }
  if !acpi_checksum_valid(&built, 0, 44) { ok = false; }
  if acpi_sum8(&built, 0, 44) != 0 { ok = false; }
  return assert(ok, "acpi_build_table reproduces the pinned FACP fixture and checksum");
}

fn t14() -> TestResult {
  var body = Vec[UInt8].new();
  var ok = err_bytes_is(acpi_build_table("FAC", 5, "XIOM", "XIOMPKG", 1, "XIOM", 1, &body), "acpi: bad signature text");
  if !err_bytes_is(acpi_build_table("FACPX", 5, "XIOM", "XIOMPKG", 1, "XIOM", 1, &body), "acpi: bad signature text") { ok = false; }
  if !err_bytes_is(acpi_build_table("FACP", 5, "XIOMXYZ", "XIOMPKG", 1, "XIOM", 1, &body), "acpi: bad oem id text") { ok = false; }
  if !err_bytes_is(acpi_build_table("FACP", 5, "XIOM", "XIOMPKGXX", 1, "XIOM", 1, &body), "acpi: bad oem table id text") { ok = false; }
  if !err_bytes_is(acpi_build_table("FACP", 5, "XIOM", "XIOMPKG", 1, "XIOMX", 1, &body), "acpi: bad creator id text") { ok = false; }
  if !err_bytes_is(acpi_build_table("FACP", -1, "XIOM", "XIOMPKG", 1, "XIOM", 1, &body), "acpi: bad revision") { ok = false; }
  if !err_bytes_is(acpi_build_table("FACP", 256, "XIOM", "XIOMPKG", 1, "XIOM", 1, &body), "acpi: bad revision") { ok = false; }
  if !err_bytes_is(acpi_build_table("FACP", 5, "XIOM", "XIOMPKG", -1, "XIOM", 1, &body), "acpi: bad oem revision") { ok = false; }
  if !err_bytes_is(acpi_build_table("FACP", 5, "XIOM", "XIOMPKG", 1, "XIOM", -1, &body), "acpi: bad creator revision") { ok = false; }
  var ne = Vec[Int].new();
  ne.push(-1);
  if !err_bytes_is(acpi_build_rsdt(&ne, "XIOM", "XIOMPKG", "XIOM", 1), "acpi: entry address out of range") { ok = false; }
  var be = Vec[Int].new();
  be.push(4294967296);
  if !err_bytes_is(acpi_build_rsdt(&be, "XIOM", "XIOMPKG", "XIOM", 1), "acpi: entry address out of range") { ok = false; }
  if !err_bytes_is(acpi_build_rsdp(1, 0, 0, "XIOM"), "acpi: rsdp revision must be 0 or 2") { ok = false; }
  if !err_bytes_is(acpi_build_rsdp(0, -1, 0, "XIOM"), "acpi: rsdp address out of range") { ok = false; }
  if !err_bytes_is(acpi_build_rsdp(0, 0, 1, "XIOM"), "acpi: rsdp revision 0 has no xsdt") { ok = false; }
  return assert(ok, "builder error catalog for tables, index tables and RSDPs");
}

fn t15() -> TestResult {
  let fx = fixture_a();
  var body = hb("0001020304050607");
  let tr = acpi_build_table("FACP", 5, "XIOM", "XIOMPKG", 1, "XIOM", 65536, &body);
  if !tr.is_ok { return assert(false, "table build must succeed"); }
  let facp: Vec[UInt8] = tr.value;
  var e = Vec[Int].new();
  e.push(60);
  let rr = acpi_build_rsdt(&e, "XIOM", "XIOMPKG", "XIOM", 65536);
  if !rr.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt: Vec[UInt8] = rr.value;
  let sr = acpi_build_rsdp(0, 20, 0, "XIOM");
  if !sr.is_ok { return assert(false, "rsdp build must succeed"); }
  let rsdp: Vec[UInt8] = sr.value;
  var ok = bytes_equal(rsdp, slice_bytes(fx, 0, 20));
  if !bytes_equal(rsdt, slice_bytes(fx, 20, 40)) { ok = false; }
  if !bytes_equal(facp, slice_bytes(fx, 60, 44)) { ok = false; }
  let buf = concat2(concat2(rsdp, rsdt), facp);
  if !bytes_equal(buf, fx) { ok = false; }
  let pr = acpi_rsdp_parse(&buf);
  if !pr.is_ok { ok = false; } else {
    let p: AcpiRsdp = pr.value;
    if acpi_rsdp_revision(&p) != 0 { ok = false; }
    let wr = acpi_tables_from_rsdp(&buf, &p);
    if !wr.is_ok { ok = false; } else {
      let t: AcpiTableSet = wr.value;
      if acpi_table_count(&t) != 1 { ok = false; }
      if acpi_find_table(&t, "FACP") != 0 { ok = false; }
      if acpi_table_revision(&t, 0) != 5 { ok = false; }
      if acpi_table_body_length(&t, 0) != 8 { ok = false; }
      if !bytes_equal(body_bytes(&buf, &t, 0), body) { ok = false; }
    }
  }
  return assert(ok, "rev0 builder round-trip equals the pinned RSDP + RSDT + FACP buffer");
}

fn t16() -> TestResult {
  let fx = fixture_b();
  var body_d = hb("deadbeef");
  let dr = acpi_build_table("DSDT", 2, "XIOM", "XIOMPKG", 1, "XIOM", 65536, &body_d);
  if !dr.is_ok { return assert(false, "dsdt build must succeed"); }
  let dsdt: Vec[UInt8] = dr.value;
  var body_f = hb("0001020304050607");
  let fr = acpi_build_table("FACP", 6, "XIOM", "XIOMPKG", 1, "XIOM", 65536, &body_f);
  if !fr.is_ok { return assert(false, "facp build must succeed"); }
  let facp: Vec[UInt8] = fr.value;
  var e = Vec[Int].new();
  e.push(88);
  e.push(128);
  let xr = acpi_build_xsdt(&e, "XIOM", "XIOMPKG", "XIOM", 65536);
  if !xr.is_ok { return assert(false, "xsdt build must succeed"); }
  let xsdt: Vec[UInt8] = xr.value;
  let sr = acpi_build_rsdp(2, 0, 36, "XIOM");
  if !sr.is_ok { return assert(false, "rsdp build must succeed"); }
  let rsdp: Vec[UInt8] = sr.value;
  var ok = bytes_equal(rsdp, slice_bytes(fx, 0, 36));
  if !bytes_equal(xsdt, slice_bytes(fx, 36, 52)) { ok = false; }
  if !bytes_equal(dsdt, slice_bytes(fx, 88, 40)) { ok = false; }
  if !bytes_equal(facp, slice_bytes(fx, 128, 44)) { ok = false; }
  let buf = concat2(concat2(concat2(rsdp, xsdt), dsdt), facp);
  if !bytes_equal(buf, fx) { ok = false; }
  let pr = acpi_rsdp_parse(&buf);
  if !pr.is_ok { ok = false; } else {
    let p: AcpiRsdp = pr.value;
    if acpi_rsdp_length(&p) != 36 { ok = false; }
    if acpi_rsdp_xsdt_address(&p) != 36 { ok = false; }
    let wr = acpi_tables_from_rsdp(&buf, &p);
    if !wr.is_ok { ok = false; } else {
      let t: AcpiTableSet = wr.value;
      if acpi_table_count(&t) != 2 { ok = false; }
      if acpi_find_table(&t, "DSDT") != 0 { ok = false; }
      if acpi_find_table(&t, "FACP") != 1 { ok = false; }
      if acpi_table_offset(&t, 1) != 128 { ok = false; }
      if !bytes_equal(body_bytes(&buf, &t, 0), body_d) { ok = false; }
    }
  }
  return assert(ok, "rev2 builder round-trip equals the pinned RSDP + XSDT + DSDT + FACP buffer");
}

fn t17() -> TestResult {
  var body1 = hb("0001020304050607");
  let f1 = acpi_build_table("FACP", 5, "XIOM", "XIOMPKG", 1, "XIOM", 1, &body1);
  if !f1.is_ok { return assert(false, "facp build must succeed"); }
  let facp1: Vec[UInt8] = f1.value;
  var body2 = hb("deadbeefdeadbeef");
  let f2 = acpi_build_table("FACP", 6, "XIOM", "XIOMPKG", 1, "XIOM", 1, &body2);
  if !f2.is_ok { return assert(false, "facp build must succeed"); }
  let facp2: Vec[UInt8] = f2.value;
  var e = Vec[Int].new();
  e.push(88);
  e.push(132);
  let xr = acpi_build_xsdt(&e, "XIOM", "XIOMPKG", "XIOM", 1);
  if !xr.is_ok { return assert(false, "xsdt build must succeed"); }
  let xsdt: Vec[UInt8] = xr.value;
  let sr = acpi_build_rsdp(2, 0, 36, "XIOM");
  if !sr.is_ok { return assert(false, "rsdp build must succeed"); }
  let rsdp: Vec[UInt8] = sr.value;
  let buf = concat2(concat2(concat2(rsdp, xsdt), facp1), facp2);
  let pr = acpi_rsdp_parse(&buf);
  if !pr.is_ok { return assert(false, "rev2 RSDP must parse"); }
  let p: AcpiRsdp = pr.value;
  let wr = acpi_tables_from_rsdp(&buf, &p);
  if !wr.is_ok { return assert(false, "duplicate-signature chain must walk"); }
  let t: AcpiTableSet = wr.value;
  var ok = acpi_table_count(&t) == 2;
  if acpi_find_table(&t, "FACP") != 0 { ok = false; }
  if acpi_table_signature(&t, 1) != acpi_signature_value("FACP") { ok = false; }
  if acpi_table_offset(&t, 0) != 88 { ok = false; }
  if acpi_table_offset(&t, 1) != 132 { ok = false; }
  if acpi_table_revision(&t, 0) != 5 { ok = false; }
  if acpi_table_revision(&t, 1) != 6 { ok = false; }
  if !bytes_equal(body_bytes(&buf, &t, 1), body2) { ok = false; }
  var e2 = Vec[Int].new();
  e2.push(60);
  e2.push(60);
  let rr2 = acpi_build_rsdt(&e2, "XIOM", "XIOMPKG", "XIOM", 1);
  if !rr2.is_ok { return assert(false, "rsdt build must succeed"); }
  let rsdt2: Vec[UInt8] = rr2.value;
  let buf2 = concat2(concat2(rsdt2, zeros(16)), facp1);
  let w2 = acpi_walk_rsdt(&buf2, 0);
  if !w2.is_ok { ok = false; } else {
    let t2: AcpiTableSet = w2.value;
    if acpi_table_count(&t2) != 2 { ok = false; }
    if acpi_table_offset(&t2, 0) != 60 { ok = false; }
    if acpi_table_offset(&t2, 1) != 60 { ok = false; }
    if acpi_find_table(&t2, "FACP") != 0 { ok = false; }
  }
  return assert(ok, "duplicate signatures and duplicate addresses are tolerated");
}

fn t18() -> TestResult {
  var ok = acpi_signature_value("FACP") == 1178682192;
  if acpi_signature_value("RSDT") != 1381188692 { ok = false; }
  if acpi_signature_value("XSDT") != 1481851988 { ok = false; }
  if acpi_signature_value("DSDT") != 1146307668 { ok = false; }
  if acpi_signature_value("FAC") != -1 { ok = false; }
  if acpi_signature_value("FACPP") != -1 { ok = false; }
  if acpi_signature_value("") != -1 { ok = false; }
  let data = fixture_a();
  if !acpi_range_printable(&data, 60, 4) { ok = false; }
  if acpi_range_printable(&data, 60, 40) { ok = false; }
  if acpi_range_printable(&data, -1, 4) { ok = false; }
  if acpi_range_printable(&data, 101, 4) { ok = false; }
  if acpi_sum8(&data, 0, 20) != 0 { ok = false; }
  if acpi_sum8(&data, 0, 200) != -1 { ok = false; }
  if !acpi_checksum_valid(&data, 20, 40) { ok = false; }
  if acpi_checksum_valid(&data, 21, 40) { ok = false; }
  if acpi_checksum_valid(&data, 0, 200) { ok = false; }
  if acpi_checksum_valid(&data, -1, 20) { ok = false; }
  if sum8_local(data, 0, 20) != acpi_sum8(&data, 0, 20) { ok = false; }
  return assert(ok, "signature packing, printability and checksum helper semantics");
}

fn main() -> Int {
  io.println("=== xiom.acpi conformance tests ===");
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
    io.println("xiom.acpi: all tests passed");
  } else {
    io.println("xiom.acpi: tests failed");
  }
  return failed;
}
