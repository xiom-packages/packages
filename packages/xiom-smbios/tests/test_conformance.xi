// XIOM -- xiom.smbios conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.smbios codec against its documented
// SMBIOS/DMI subset: both entry-point variants, the preference rule, the
// structure table stream, the documented structure types, canonical
// builders, the error catalog and the round-trips.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is either a literal hex byte string or built through the
// public builder; canonical encodings are pinned as exact bytes. Str
// values read from vectors are never compared with `==` (BUG 17:
// pointer comparison); comparisons go through compare.str_compare, and
// every Vec element read is bound to a typed local.

module smbios_tests
use xiom.io; use xiom.test;
use xiom.smbios;
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

fn append_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

fn copy_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_bytes(&mut out, v);
  return out;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_bytes(&mut out, &a);
  append_bytes(&mut out, &b);
  return out;
}

fn cat3(a: Vec[UInt8], b: Vec[UInt8], c: Vec[UInt8]) -> Vec[UInt8] {
  return cat(cat(a, b), c);
}

fn slice_bytes(v: Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

fn u8(v: &Vec[UInt8], i: Int) -> Int {
  let b: UInt8 = v[i];
  return (b as Int) & 0xFF;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_entry_is(r: Result[SmbiosEntry, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_table_is(r: Result[SmbiosTable, Str], want: Str) -> Bool {
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

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Store of a successful parse, or an empty store.
fn table_of(r: Result[SmbiosTable, Str]) -> SmbiosTable {
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return SmbiosTable{ types: Vec[Int].new(); lengths: Vec[Int].new();
    handles: Vec[Int].new(); starts: Vec[Int].new(); str_first: Vec[Int].new();
    str_count: Vec[Int].new(); str_struct: Vec[Int].new();
    str_off: Vec[Int].new(); str_len: Vec[Int].new(); };
}

// Copy the formatted area of structure i (empty on any error; callers
// only use it on a store they already validated).
fn formatted_at(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Vec[UInt8] {
  let r = smbios_formatted(data, t, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// Decoded string (empty on any error).
fn string_at(data: &Vec[UInt8], t: &SmbiosTable, i: Int, s: Int) -> Str {
  let r = smbios_string(data, t, i, s);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return "";
}

// Build one structure through the public builder (empty on error).
fn build_struct(stype: Int, handle: Int, formatted: Vec[UInt8], strings: Vec[Str]) -> Vec[UInt8] {
  let r = smbios_struct_build(stype, handle, &formatted, &strings);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn build_image32(table: Vec[UInt8], major: Int, minor: Int, bcd_rev: Int) -> Vec[UInt8] {
  let r = smbios_image_build32(&table, major, minor, bcd_rev);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// Reseal the 32-bit entry-point checksum byte after a fixture edit, so
// the checksum check passes and the intended downstream error surfaces.
// (Inlined at the call sites: a helper returning a Vec built from a &Vec
// parameter trips advisory E001.)

// --------------------------------------------------
//  Fixture fragments
// --------------------------------------------------

fn bios_formatted() -> Vec[UInt8] {
  return hb("010200e8037f0000000000000000");
}

fn bios_strings() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("Vendor Inc");
  v.push("1.2.3");
  v.push("01/01/2026");
  return v;
}

fn sys_formatted() -> Vec[UInt8] {
  return hb("01020304112233445566778899aabbccddeeff00060000");
}

fn sys_strings() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("ACME Corp");
  v.push("SuperBoard");
  v.push("Rev C");
  v.push("SN123456");
  return v;
}

fn baseboard_formatted() -> Vec[UInt8] {
  return hb("01020304050003000a00");
}

fn baseboard_strings() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("BaseMfg");
  v.push("BaseProduct");
  v.push("BaseVer");
  v.push("BaseSerial");
  v.push("BaseAsset");
  return v;
}

fn chassis_formatted() -> Vec[UInt8] {
  return hb("018502030403030303000000000001000000");
}

fn chassis_strings() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("ChasMfg");
  v.push("ChasVer");
  v.push("ChasSerial");
  v.push("ChasAsset");
  return v;
}

fn processor_formatted() -> Vec[UInt8] {
  return hb("0103b302000000000000000003006400a00fb80b4102");
}

fn processor_strings() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("CPU1");
  v.push("ProcMfg");
  v.push("ProcVer");
  return v;
}

fn mem_array_formatted() -> Vec[UInt8] {
  return hb("03030500008000feff020000000000000000");
}

fn mem_device_formatted() -> Vec[UInt8] {
  return hb("1000feff400040000020090001021a8000800c030400050200000000800c000000000000");
}

fn mem_device_strings() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("DIMM_A1");
  v.push("BANK 0");
  v.push("MemMfg");
  v.push("MemSerial");
  v.push("PartNo123");
  return v;
}

fn no_strings() -> Vec[Str] {
  return Vec[Str].new();
}

fn no_bytes() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

// BIOS + System + End of Table, canonical (117 bytes).
fn fixture_table() -> Vec[UInt8] {
  let s0 = build_struct(0, 0, bios_formatted(), bios_strings());
  let s1 = build_struct(1, 1, sys_formatted(), sys_strings());
  let s2 = build_struct(127, 2, no_bytes(), no_strings());
  return cat3(s0, s1, s2);
}

// The full documented field-accessor table:
// 0 BIOS, 1 System, 2 Baseboard, 3 Chassis, 4 Processor, 16 Memory
// Array, 17 Memory Device, 127 End of Table (handles 0..7).
fn field_table() -> Vec[UInt8] {
  let s0 = build_struct(0, 0, bios_formatted(), bios_strings());
  let s1 = build_struct(1, 1, sys_formatted(), sys_strings());
  let s2 = build_struct(2, 2, baseboard_formatted(), baseboard_strings());
  let s3 = build_struct(3, 3, chassis_formatted(), chassis_strings());
  let s4 = build_struct(4, 4, processor_formatted(), processor_strings());
  let s5 = build_struct(16, 5, mem_array_formatted(), no_strings());
  let s6 = build_struct(17, 6, mem_device_formatted(), mem_device_strings());
  let s7 = build_struct(127, 7, no_bytes(), no_strings());
  return cat(cat(cat(cat(s0, s1), cat(s2, s3)), cat(s4, s5)), cat(s6, s7));
}

fn fixture_image() -> Vec[UInt8] {
  return build_image32(fixture_table(), 2, 8, 40);
}

fn field_image() -> Vec[UInt8] {
  return build_image32(field_table(), 2, 8, 40);
}

// Rebuild a parsed store with smbios_struct_build, structure by
// structure, in order.
fn rebuild_table(data: &Vec[UInt8], t: &SmbiosTable) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < smbios_count(t) {
    let stype: Int = smbios_type(t, i);
    let handle: Int = smbios_handle(t, i);
    let fmt: Vec[UInt8] = formatted_at(data, t, i);
    var strs = Vec[Str].new();
    let sc: Int = smbios_string_count(t, i);
    var s = 1;
    while s <= sc {
      strs.push(string_at(data, t, i, s));
      s = s + 1;
    }
    let br = smbios_struct_build(stype, handle, &fmt, &strs);
    if br.is_ok {
      let b: Vec[UInt8] = br.value;
      append_bytes(&mut out, &b);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  // Canonical _SM_ entry point: major 2, minor 8, max size 0, table at
  // 32 (length 0), count 0, BCD 0x28.
  let br = smbios_entry32_build(2, 8, 0, 32, 0, 0, 40);
  if !br.is_ok { return assert(false, "entry32_build must succeed"); }
  let ep: Vec[UInt8] = br.value;
  let want = hb("5f534d5f791f020800000000000000005f444d495f20000020000000000028");
  var ok = bytes_equal(ep, want);
  if ep.len() != 31 { ok = false; }
  if u8(&ep, 5) != 31 { ok = false; }
  if smbios_checksum8(&ep, 0, 31) != 0 { ok = false; }
  if !smbios_entry32_checksum_ok(&ep) { ok = false; }
  if !smbios_entry32_intermediate_checksum_ok(&ep) { ok = false; }
  if !smbios_entry_checksum_ok(&ep) { ok = false; }
  if smbios_entry_points(&ep) != 1 { ok = false; }
  let r = smbios_entry32_parse(&ep);
  if !r.is_ok { return assert(false, "entry32 must parse"); }
  let e: SmbiosEntry = r.value;
  if smbios_entry_kind(&e) != 0 { ok = false; }
  if smbios_entry_major(&e) != 2 { ok = false; }
  if smbios_entry_minor(&e) != 8 { ok = false; }
  if smbios_entry_docrev(&e) != 0 { ok = false; }
  if smbios_entry_revision(&e) != 0 { ok = false; }
  if smbios_entry_max_size(&e) != 0 { ok = false; }
  if smbios_entry_table_len(&e) != 0 { ok = false; }
  if smbios_entry_table_addr(&e) != 32 { ok = false; }
  if smbios_entry_count(&e) != 0 { ok = false; }
  if smbios_entry_bcd(&e) != 40 { ok = false; }
  let pr = smbios_entry_parse(&ep);
  if !pr.is_ok { ok = false; } else {
    let pe: SmbiosEntry = pr.value;
    if smbios_entry_kind(&pe) != 0 { ok = false; }
  }
  if !err_entry_is(smbios_entry64_parse(&ep), "smbios: bad 64-bit signature") { ok = false; }
  return assert(ok, "canonical _SM_ entry point: pinned bytes, checksums, accessors");
}

fn t2() -> TestResult {
  let b0 = smbios_entry32_build(2, 8, 0, 32, 0, 0, 40);
  if !b0.is_ok { return assert(false, "build must succeed"); }
  let ep: Vec[UInt8] = b0.value;
  let short = slice_bytes(ep, 0, 30);
  var ok = err_entry_is(smbios_entry32_parse(&short), "smbios: 32-bit entry point too short");
  var bad = copy_bytes(&ep);
  bad[0] = 94 as UInt8;
  if !err_entry_is(smbios_entry32_parse(&bad), "smbios: bad 32-bit signature") { ok = false; }
  bad = copy_bytes(&ep);
  bad[5] = 30 as UInt8;
  if !err_entry_is(smbios_entry32_parse(&bad), "smbios: bad 32-bit entry length") { ok = false; }
  bad = copy_bytes(&ep);
  bad[4] = 0 as UInt8;
  if !err_entry_is(smbios_entry32_parse(&bad), "smbios: bad 32-bit checksum") { ok = false; }
  bad = copy_bytes(&ep);
  bad[16] = 0 as UInt8;
  bad[4] = 0 as UInt8;
  let sa: Int = smbios_checksum8(&bad, 0, 31);
  var cba = 0;
  if sa > 0 { cba = 256 - sa; }
  bad[4] = cba as UInt8;
  if !err_entry_is(smbios_entry32_parse(&bad), "smbios: bad intermediate anchor") { ok = false; }
  bad = copy_bytes(&ep);
  bad[21] = 0 as UInt8;
  bad[4] = 0 as UInt8;
  let sb: Int = smbios_checksum8(&bad, 0, 31);
  var cbb = 0;
  if sb > 0 { cbb = 256 - sb; }
  bad[4] = cbb as UInt8;
  if !err_entry_is(smbios_entry32_parse(&bad), "smbios: bad intermediate checksum") { ok = false; }
  if smbios_entry32_checksum_ok(&short) { ok = false; }
  if smbios_entry32_intermediate_checksum_ok(&short) { ok = false; }
  return assert(ok, "_SM_ error catalog: signature, length, checksum, intermediate block");
}

fn t3() -> TestResult {
  let b0 = smbios_entry64_build(3, 0, 0, 0, 0, 0);
  if !b0.is_ok { return assert(false, "entry64_build must succeed"); }
  let ep: Vec[UInt8] = b0.value;
  var ok = bytes_equal(ep, hb("5f534d335f54180300000000000000000000000000000000"));
  if ep.len() != 24 { ok = false; }
  if u8(&ep, 6) != 24 { ok = false; }
  if !smbios_entry64_checksum_ok(&ep) { ok = false; }
  if !smbios_entry_checksum_ok(&ep) { ok = false; }
  let r = smbios_entry64_parse(&ep);
  if !r.is_ok { return assert(false, "entry64 must parse"); }
  let e: SmbiosEntry = r.value;
  if smbios_entry_kind(&e) != 1 { ok = false; }
  if smbios_entry_major(&e) != 3 { ok = false; }
  if smbios_entry_minor(&e) != 0 { ok = false; }
  if smbios_entry_docrev(&e) != 0 { ok = false; }
  if smbios_entry_revision(&e) != 0 { ok = false; }
  if smbios_entry_max_size(&e) != 0 { ok = false; }
  if smbios_entry_table_len(&e) != 0 { ok = false; }
  if smbios_entry_count(&e) != 0 { ok = false; }
  if smbios_entry_bcd(&e) != 0 { ok = false; }
  if smbios_entry_table_addr(&e) != 0 { ok = false; }
  // Distinct fields: docrev 2, revision 1, max size 65536, address 128.
  let b1 = smbios_entry64_build(3, 5, 2, 1, 65536, 128);
  if !b1.is_ok { return assert(false, "second entry64_build must succeed"); }
  let ep1: Vec[UInt8] = b1.value;
  if !bytes_equal(ep1, hb("5f534d335fcb180305020100000001008000000000000000")) { ok = false; }
  let r1 = smbios_entry64_parse(&ep1);
  if !r1.is_ok { ok = false; } else {
    let e1: SmbiosEntry = r1.value;
    if smbios_entry_minor(&e1) != 5 { ok = false; }
    if smbios_entry_docrev(&e1) != 2 { ok = false; }
    if smbios_entry_revision(&e1) != 1 { ok = false; }
    if smbios_entry_max_size(&e1) != 65536 { ok = false; }
    if smbios_entry_table_addr(&e1) != 128 { ok = false; }
  }
  if !err_entry_is(smbios_entry32_parse(&ep), "smbios: 32-bit entry point too short") { ok = false; }
  return assert(ok, "canonical _SM3_ entry point: pinned bytes, checksum, u64 address");
}

fn t4() -> TestResult {
  let b0 = smbios_entry64_build(3, 1, 0, 0, 0, 0);
  if !b0.is_ok { return assert(false, "build must succeed"); }
  let ep: Vec[UInt8] = b0.value;
  let short = slice_bytes(ep, 0, 23);
  var ok = err_entry_is(smbios_entry64_parse(&short), "smbios: 64-bit entry point too short");
  var bad = copy_bytes(&ep);
  bad[3] = 50 as UInt8;
  if !err_entry_is(smbios_entry64_parse(&bad), "smbios: bad 64-bit signature") { ok = false; }
  bad = copy_bytes(&ep);
  bad[6] = 23 as UInt8;
  if !err_entry_is(smbios_entry64_parse(&bad), "smbios: bad 64-bit entry length") { ok = false; }
  bad = copy_bytes(&ep);
  bad[5] = 0 as UInt8;
  if !err_entry_is(smbios_entry64_parse(&bad), "smbios: bad 64-bit checksum") { ok = false; }
  if smbios_entry64_checksum_ok(&bad) { ok = false; }
  return assert(ok, "_SM3_ error catalog: short, signature, length, checksum");
}

fn t5() -> TestResult {
  let b32 = smbios_entry32_build(2, 8, 0, 32, 0, 0, 40);
  let b64 = smbios_entry64_build(3, 4, 0, 0, 0, 64);
  if !b32.is_ok || !b64.is_ok { return assert(false, "builds must succeed"); }
  let ep32: Vec[UInt8] = b32.value;
  let ep64: Vec[UInt8] = b64.value;
  // Both present: the 64-bit entry point wins (it sits at aligned 32).
  let both = cat(ep32, cat(zeros(1), ep64));
  if both.len() != 56 { return assert(false, "combined fixture length"); }
  var ok = smbios_entry_points(&both) == 2;
  let r = smbios_entry_parse(&both);
  if !r.is_ok { return assert(false, "combined image must parse"); }
  let e: SmbiosEntry = r.value;
  if smbios_entry_kind(&e) != 1 { ok = false; }
  if smbios_entry_minor(&e) != 4 { ok = false; }
  if smbios_entry_table_addr(&e) != 64 { ok = false; }
  let r32 = smbios_entry32_parse(&both);
  if !r32.is_ok { ok = false; } else {
    let e32: SmbiosEntry = r32.value;
    if smbios_entry_kind(&e32) != 0 { ok = false; }
    if smbios_entry_table_addr(&e32) != 32 { ok = false; }
  }
  // A lone _SM_ entry point at aligned offset 16 is found by the scan.
  let shifted = cat(zeros(16), ep32);
  if smbios_entry_points(&shifted) != 1 { ok = false; }
  let rs = smbios_entry_parse(&shifted);
  if !rs.is_ok { ok = false; } else {
    let es: SmbiosEntry = rs.value;
    if smbios_entry_kind(&es) != 0 { ok = false; }
  }
  if !err_entry_is(smbios_entry32_parse(&shifted), "smbios: bad 32-bit signature") { ok = false; }
  // Misaligned anchors are not entry points; no anchor at all is Err.
  let mis = cat(zeros(8), ep32);
  if smbios_entry_points(&mis) != 0 { ok = false; }
  if !err_entry_is(smbios_entry_parse(&mis), "smbios: no entry point") { ok = false; }
  let empty = zeros(64);
  if smbios_entry_points(&empty) != 0 { ok = false; }
  if !err_entry_is(smbios_entry_parse(&empty), "smbios: no entry point") { ok = false; }
  return assert(ok, "preference rule: first aligned _SM3_ wins; _SM_ only without it");
}

fn t6() -> TestResult {
  let table = fixture_table();
  var ok = table.len() == 117;
  let r = smbios_table_parse(&table);
  if !r.is_ok { return assert(false, "fixture table must parse"); }
  let t: SmbiosTable = r.value;
  if smbios_count(&t) != 3 { ok = false; }
  if smbios_type(&t, 0) != 0 { ok = false; }
  if smbios_type(&t, 1) != 1 { ok = false; }
  if smbios_type(&t, 2) != 127 { ok = false; }
  if smbios_length(&t, 0) != 18 { ok = false; }
  if smbios_length(&t, 1) != 27 { ok = false; }
  if smbios_length(&t, 2) != 4 { ok = false; }
  if smbios_handle(&t, 0) != 0 { ok = false; }
  if smbios_handle(&t, 1) != 1 { ok = false; }
  if smbios_handle(&t, 2) != 2 { ok = false; }
  if smbios_struct_start(&t, 0) != 0 { ok = false; }
  if smbios_struct_start(&t, 1) != 47 { ok = false; }
  if smbios_struct_start(&t, 2) != 111 { ok = false; }
  if smbios_formatted_len(&t, 0) != 14 { ok = false; }
  if smbios_formatted_len(&t, 1) != 23 { ok = false; }
  if smbios_formatted_len(&t, 2) != 0 { ok = false; }
  if smbios_string_count(&t, 0) != 3 { ok = false; }
  if smbios_string_count(&t, 1) != 4 { ok = false; }
  if smbios_string_count(&t, 2) != 0 { ok = false; }
  if smbios_find_type(&t, 1) != 1 { ok = false; }
  if smbios_find_type(&t, 127) != 2 { ok = false; }
  if smbios_find_type(&t, 17) != -1 { ok = false; }
  if !bytes_equal(formatted_at(&table, &t, 0), bios_formatted()) { ok = false; }
  if !bytes_equal(formatted_at(&table, &t, 1), sys_formatted()) { ok = false; }
  if formatted_at(&table, &t, 2).len() != 0 { ok = false; }
  if smbios_type(&t, -1) != -1 { ok = false; }
  if smbios_type(&t, 3) != -1 { ok = false; }
  if smbios_handle(&t, 3) != -1 { ok = false; }
  if smbios_struct_start(&t, 9) != -1 { ok = false; }
  if smbios_formatted_len(&t, 3) != -1 { ok = false; }
  if smbios_string_count(&t, 3) != -1 { ok = false; }
  return assert(ok, "structure table: pinned counts, types, lengths, handles and starts");
}

fn t7() -> TestResult {
  let table = fixture_table();
  let r = smbios_table_parse(&table);
  if !r.is_ok { return assert(false, "fixture table must parse"); }
  let t: SmbiosTable = r.value;
  // Strings are 1-indexed; index 0 is the documented "no string".
  var ok = str_eq(string_at(&table, &t, 0, 1), "Vendor Inc");
  if !str_eq(string_at(&table, &t, 0, 2), "1.2.3") { ok = false; }
  if !str_eq(string_at(&table, &t, 0, 3), "01/01/2026") { ok = false; }
  if !str_eq(string_at(&table, &t, 1, 1), "ACME Corp") { ok = false; }
  if !str_eq(string_at(&table, &t, 1, 2), "SuperBoard") { ok = false; }
  if !str_eq(string_at(&table, &t, 1, 3), "Rev C") { ok = false; }
  if !str_eq(string_at(&table, &t, 1, 4), "SN123456") { ok = false; }
  let z = smbios_string(&table, &t, 0, 0);
  if !z.is_ok { ok = false; } else {
    let zs: Str = z.value;
    if !str_eq(zs, "") { ok = false; }
  }
  if !err_str_is(smbios_string(&table, &t, 0, 4), "smbios: string index out of range") { ok = false; }
  if !err_str_is(smbios_string(&table, &t, 2, 1), "smbios: string index out of range") { ok = false; }
  if !err_str_is(smbios_string(&table, &t, 3, 1), "smbios: structure index out of range") { ok = false; }
  if !err_bytes_is(smbios_string_bytes(&table, &t, 1, 5), "smbios: string index out of range") { ok = false; }
  // Raw bytes stay raw; a Str is not required for them.
  let rb = smbios_string_bytes(&table, &t, 1, 4);
  if !rb.is_ok { ok = false; } else {
    let rbb: Vec[UInt8] = rb.value;
    if !bytes_equal(rbb, bytes_of("SN123456")) { ok = false; }
  }
  let rb0 = smbios_string_bytes(&table, &t, 0, 0);
  if !rb0.is_ok { ok = false; } else {
    let rb0v: Vec[UInt8] = rb0.value;
    if rb0v.len() != 0 { ok = false; }
  }
  // A shorter buffer makes the recorded spans unreachable.
  let short = slice_bytes(table, 0, 4);
  if !err_str_is(smbios_string(&short, &t, 0, 1), "smbios: string out of bounds") { ok = false; }
  if !err_bytes_is(smbios_string_bytes(&short, &t, 0, 1), "smbios: string out of bounds") { ok = false; }
  if !err_bytes_is(smbios_formatted(&short, &t, 0), "smbios: structure out of bounds") { ok = false; }
  return assert(ok, "string-set accessors: 1-indexing, index 0, ranges and raw bytes");
}

fn t8() -> TestResult {
  let table = field_image();
  let r = smbios_parse(&table);
  if !r.is_ok { return assert(false, "field image must parse"); }
  let t: SmbiosTable = r.value;
  var ok = smbios_count(&t) == 8;
  let i0 = smbios_find_type(&t, 0);
  let i1 = smbios_find_type(&t, 1);
  let i2 = smbios_find_type(&t, 2);
  let i3 = smbios_find_type(&t, 3);
  let i4 = smbios_find_type(&t, 4);
  let i16 = smbios_find_type(&t, 16);
  let i17 = smbios_find_type(&t, 17);
  let i127 = smbios_find_type(&t, 127);
  if i0 != 0 || i1 != 1 || i2 != 2 || i3 != 3 { ok = false; }
  if i4 != 4 || i16 != 5 || i17 != 6 || i127 != 7 { ok = false; }
  // Type 0 BIOS Information.
  if smbios_bios_vendor(&table, &t, i0) != 1 { ok = false; }
  if smbios_bios_version(&table, &t, i0) != 2 { ok = false; }
  if smbios_bios_release_date(&table, &t, i0) != 3 { ok = false; }
  if smbios_bios_rom_size(&table, &t, i0) != 127 { ok = false; }
  if !str_eq(string_at(&table, &t, i0, 1), "Vendor Inc") { ok = false; }
  // Type 1 System Information, including the raw 16-byte UUID.
  if smbios_system_manufacturer(&table, &t, i1) != 1 { ok = false; }
  if smbios_system_product(&table, &t, i1) != 2 { ok = false; }
  if smbios_system_version(&table, &t, i1) != 3 { ok = false; }
  if smbios_system_serial(&table, &t, i1) != 4 { ok = false; }
  let ur = smbios_uuid(&table, &t, i1);
  if !ur.is_ok { ok = false; } else {
    let u: Vec[UInt8] = ur.value;
    if !bytes_equal(u, hb("112233445566778899aabbccddeeff00")) { ok = false; }
  }
  if !err_bytes_is(smbios_uuid(&table, &t, i0), "smbios: uuid out of range") { ok = false; }
  if !err_bytes_is(smbios_uuid(&table, &t, 99), "smbios: structure index out of range") { ok = false; }
  // Type 2 Baseboard.
  if smbios_baseboard_manufacturer(&table, &t, i2) != 1 { ok = false; }
  if smbios_baseboard_product(&table, &t, i2) != 2 { ok = false; }
  if smbios_baseboard_version(&table, &t, i2) != 3 { ok = false; }
  if smbios_baseboard_serial(&table, &t, i2) != 4 { ok = false; }
  if smbios_baseboard_asset_tag(&table, &t, i2) != 5 { ok = false; }
  if !str_eq(string_at(&table, &t, i2, 5), "BaseAsset") { ok = false; }
  // Type 3 Chassis, raw byte with the lock bit and the name table.
  if smbios_chassis_manufacturer(&table, &t, i3) != 1 { ok = false; }
  if smbios_chassis_type(&table, &t, i3) != 133 { ok = false; }
  if smbios_chassis_version(&table, &t, i3) != 2 { ok = false; }
  if smbios_chassis_serial(&table, &t, i3) != 3 { ok = false; }
  if smbios_chassis_asset_tag(&table, &t, i3) != 4 { ok = false; }
  let cname = smbios_chassis_type_name(133);
  if !str_eq(cname, "Pizza Box") { ok = false; }
  // Type 4 Processor.
  if smbios_processor_socket(&table, &t, i4) != 1 { ok = false; }
  if smbios_processor_family(&table, &t, i4) != 179 { ok = false; }
  if smbios_processor_version(&table, &t, i4) != 3 { ok = false; }
  if !str_eq(string_at(&table, &t, i4, 3), "ProcVer") { ok = false; }
  // Type 16 Physical Memory Array.
  if smbios_memory_array_capacity(&table, &t, i16) != 8388608 { ok = false; }
  // Type 17 Memory Device.
  if smbios_memory_device_size(&table, &t, i17) != 8192 { ok = false; }
  if smbios_memory_device_type(&table, &t, i17) != 26 { ok = false; }
  if smbios_memory_device_speed(&table, &t, i17) != 3200 { ok = false; }
  if smbios_memory_device_manufacturer(&table, &t, i17) != 3 { ok = false; }
  if !str_eq(string_at(&table, &t, i17, 3), "MemMfg") { ok = false; }
  // Wrong-type and absent-field reads report -1 instead of faulting.
  if smbios_bios_vendor(&table, &t, i1) != -1 { ok = false; }
  if smbios_processor_socket(&table, &t, i17) != -1 { ok = false; }
  if smbios_memory_device_size(&table, &t, i16) != -1 { ok = false; }
  if smbios_bios_vendor(&table, &t, 99) != -1 { ok = false; }
  // A short (length 5) BIOS structure has the vendor index but no ROM
  // size field.
  var tiny_fmt = Vec[UInt8].new();
  tiny_fmt.push(1 as UInt8);
  let tiny = build_struct(0, 9, tiny_fmt, no_strings());
  let tr = smbios_table_parse(&tiny);
  if !tr.is_ok { ok = false; } else {
    let tt: SmbiosTable = tr.value;
    if smbios_bios_vendor(&tiny, &tt, 0) != 1 { ok = false; }
    if smbios_bios_version(&tiny, &tt, 0) != -1 { ok = false; }
    if smbios_bios_rom_size(&tiny, &tt, 0) != -1 { ok = false; }
  }
  return assert(ok, "documented field accessors for types 0,1,2,3,4,16,17");
}

fn t9() -> TestResult {
  var ok = str_eq(smbios_chassis_type_name(1), "Other");
  if !str_eq(smbios_chassis_type_name(2), "Unknown") { ok = false; }
  if !str_eq(smbios_chassis_type_name(3), "Desktop") { ok = false; }
  if !str_eq(smbios_chassis_type_name(9), "Laptop") { ok = false; }
  if !str_eq(smbios_chassis_type_name(10), "Notebook") { ok = false; }
  if !str_eq(smbios_chassis_type_name(17), "Main Server Chassis") { ok = false; }
  if !str_eq(smbios_chassis_type_name(24), "Sealed-case PC") { ok = false; }
  if !str_eq(smbios_chassis_type_name(30), "Tablet") { ok = false; }
  if !str_eq(smbios_chassis_type_name(36), "Stick PC") { ok = false; }
  if !str_eq(smbios_chassis_type_name(133), "Pizza Box") { ok = false; }
  if !str_eq(smbios_chassis_type_name(0), "Unknown") { ok = false; }
  if !str_eq(smbios_chassis_type_name(37), "Unknown") { ok = false; }
  if !str_eq(smbios_chassis_type_name(255), "Unknown") { ok = false; }
  if !str_eq(smbios_chassis_type_name(-1), "Unknown") { ok = false; }
  return assert(ok, "chassis type name table including the bit-7 lock strip");
}

fn t10() -> TestResult {
  // Unknown type 200 with two raw formatted bytes and one string.
  var fmt = Vec[UInt8].new();
  fmt.push(222 as UInt8);
  fmt.push(173 as UInt8);
  var strs = Vec[Str].new();
  strs.push("junk");
  let raw = build_struct(200, 4660, fmt, strs);
  var ok = raw.len() == 12;
  let r = smbios_table_parse(&raw);
  if !r.is_ok { return assert(false, "unknown-type table must parse"); }
  let t: SmbiosTable = r.value;
  if smbios_count(&t) != 1 { ok = false; }
  if smbios_type(&t, 0) != 200 { ok = false; }
  if smbios_length(&t, 0) != 6 { ok = false; }
  if smbios_handle(&t, 0) != 4660 { ok = false; }
  if smbios_formatted_len(&t, 0) != 2 { ok = false; }
  if !bytes_equal(formatted_at(&raw, &t, 0), fmt) { ok = false; }
  if !str_eq(string_at(&raw, &t, 0, 1), "junk") { ok = false; }
  if smbios_find_type(&t, 200) != 0 { ok = false; }
  if smbios_find_type(&t, 201) != -1 { ok = false; }
  // Hand-built unknown type 201 with a non-UTF-8 string byte 0xFF: the raw
  // bytes survive, the text decode is a documented Err.
  let weird = hb("c9040100ff0000");
  let wr = smbios_table_parse(&weird);
  if !wr.is_ok { ok = false; } else {
    let wt: SmbiosTable = wr.value;
    if smbios_type(&wt, 0) != 201 { ok = false; }
    if smbios_string_count(&wt, 0) != 1 { ok = false; }
    let wb = smbios_string_bytes(&weird, &wt, 0, 1);
    if !wb.is_ok { ok = false; } else {
      let wbv: Vec[UInt8] = wb.value;
      if !bytes_equal(wbv, hb("ff")) { ok = false; }
    }
    if !err_str_is(smbios_string(&weird, &wt, 0, 1), "smbios: invalid string bytes") { ok = false; }
  }
  return assert(ok, "unknown types keep their raw formatted and string spans");
}

fn t11() -> TestResult {
  // Structure length below 4.
  var ok = err_table_is(smbios_table_parse(&hb("000300000000")), "smbios: invalid structure length");
  // Fewer than 4 bytes left at a structure boundary.
  if !err_table_is(smbios_table_parse(&hb("0100")), "smbios: truncated structure") { ok = false; }
  // Declared length runs past the table end.
  if !err_table_is(smbios_table_parse(&hb("001000000000000000")), "smbios: truncated structure") { ok = false; }
  // Formatted area reaches the table end: no room for the string set.
  if !err_table_is(smbios_table_parse(&hb("0008000001020304")), "smbios: unterminated string set") { ok = false; }
  if !err_table_is(smbios_table_parse(&hb("0004000000")), "smbios: unterminated string set") { ok = false; }
  // Duplicate handles (two zero-string structures both with handle 0).
  if !err_table_is(smbios_table_parse(&hb("000400000000010400000000")), "smbios: duplicate handle") { ok = false; }
  // Unique handles parse; the two-NUL pair alone is a valid empty set.
  let good = hb("000400000000010401000000");
  let gr = smbios_table_parse(&good);
  if !gr.is_ok { ok = false; } else {
    let gt: SmbiosTable = gr.value;
    if smbios_count(&gt) != 2 { ok = false; }
    if smbios_string_count(&gt, 0) != 0 { ok = false; }
    if smbios_handle(&gt, 1) != 1 { ok = false; }
  }
  return assert(ok, "table validation: length, truncation, termination, handles");
}

fn t12() -> TestResult {
  // Canonical no-string structure: the pair 00 00 after the formatted area.
  let eot = build_struct(127, 0, no_bytes(), no_strings());
  var ok = bytes_equal(eot, hb("7f0400000000"));
  var one_fmt = Vec[UInt8].new();
  one_fmt.push(170 as UInt8);
  var one_strs = Vec[Str].new();
  one_strs.push("A");
  let one = build_struct(0, 258, one_fmt, one_strs);
  if !bytes_equal(one, hb("00050201aa410000")) { ok = false; }
  // Type 127 ends the walk: bytes after it are ignored.
  let eot_only = cat(eot, hb("00120000"));
  let r = smbios_table_parse(&eot_only);
  if !r.is_ok { ok = false; } else {
    let t: SmbiosTable = r.value;
    if smbios_count(&t) != 1 { ok = false; }
    if smbios_type(&t, 0) != 127 { ok = false; }
    if smbios_string_count(&t, 0) != 0 { ok = false; }
  }
  // An empty table parses to zero structures.
  let er = smbios_table_parse(&no_bytes());
  if !er.is_ok { ok = false; } else {
    let et: SmbiosTable = er.value;
    if smbios_count(&et) != 0 { ok = false; }
    if smbios_find_type(&et, 0) != -1 { ok = false; }
  }
  return assert(ok, "canonical no-string pair, single string, EoT stop and empty table");
}

fn t13() -> TestResult {
  let table = fixture_table();
  let image = fixture_image();
  var ok = image.len() == 149;
  if u8(&image, 0) != 95 { ok = false; }
  if u8(&image, 4) != 121 { ok = false; }
  if u8(&image, 30) != 40 { ok = false; }
  if !bytes_equal(slice_bytes(image, 32, 149), table) { ok = false; }
  let er = smbios_entry_parse(&image);
  if !er.is_ok { return assert(false, "entry must parse"); }
  let e: SmbiosEntry = er.value;
  if smbios_entry_kind(&e) != 0 { ok = false; }
  if smbios_entry_table_addr(&e) != 32 { ok = false; }
  if smbios_entry_table_len(&e) != 117 { ok = false; }
  if smbios_entry_count(&e) != 3 { ok = false; }
  let pr = smbios_parse(&image);
  if !pr.is_ok { return assert(false, "image must parse"); }
  let t: SmbiosTable = pr.value;
  if smbios_count(&t) != 3 { ok = false; }
  if smbios_struct_start(&t, 0) != 32 { ok = false; }
  if smbios_struct_start(&t, 1) != 79 { ok = false; }
  if !str_eq(string_at(&image, &t, 0, 1), "Vendor Inc") { ok = false; }
  if !str_eq(string_at(&image, &t, 1, 4), "SN123456") { ok = false; }
  if smbios_system_serial(&image, &t, 1) != 4 { ok = false; }
  if !bytes_equal(formatted_at(&image, &t, 1), sys_formatted()) { ok = false; }
  // Parse -> rebuild reproduces the table byte for byte.
  let rebuilt = rebuild_table(&image, &t);
  if !bytes_equal(rebuilt, table) { ok = false; }
  let image2 = build_image32(rebuilt, 2, 8, 40);
  if !bytes_equal(image2, image) { ok = false; }
  return assert(ok, "32-bit fixture round-trip: parse, accessors, rebuild byte-identical");
}

fn t14() -> TestResult {
  let table = fixture_table();
  // A declared count that disagrees with the table is an error.
  let b1 = smbios_entry32_build(2, 8, 0, 32, 117, 4, 40);
  if !b1.is_ok { return assert(false, "entry build must succeed"); }
  let ep1: Vec[UInt8] = b1.value;
  let img1 = cat(ep1, cat(zeros(1), table));
  var ok = err_table_is(smbios_parse(&img1), "smbios: structure count mismatch");
  // A declared count of 0 means "unknown" and skips the check.
  let b2 = smbios_entry32_build(2, 8, 0, 32, 117, 0, 40);
  if !b2.is_ok { return assert(false, "entry build must succeed"); }
  let ep2: Vec[UInt8] = b2.value;
  let img2 = cat(ep2, cat(zeros(1), table));
  let t2: SmbiosTable = table_of(smbios_parse(&img2));
  if smbios_count(&t2) != 3 { ok = false; }
  // A table address outside the buffer is rejected.
  let b3 = smbios_entry32_build(2, 8, 0, 200, 117, 3, 40);
  if !b3.is_ok { return assert(false, "entry build must succeed"); }
  let ep3: Vec[UInt8] = b3.value;
  let img3 = cat(ep3, cat(zeros(1), table));
  if !err_table_is(smbios_parse(&img3), "smbios: table out of buffer") { ok = false; }
  // A declared table length past the buffer end is rejected.
  let b4 = smbios_entry32_build(2, 8, 0, 32, 200, 3, 40);
  if !b4.is_ok { return assert(false, "entry build must succeed"); }
  let ep4: Vec[UInt8] = b4.value;
  let img4 = cat(ep4, cat(zeros(1), table));
  if !err_table_is(smbios_parse(&img4), "smbios: table out of buffer") { ok = false; }
  // A short declared table length cuts the walk mid-structure.
  let b5 = smbios_entry32_build(2, 8, 0, 32, 100, 3, 40);
  if !b5.is_ok { return assert(false, "entry build must succeed"); }
  let ep5: Vec[UInt8] = b5.value;
  let img5 = cat(ep5, cat(zeros(1), table));
  if !err_table_is(smbios_parse(&img5), "smbios: unterminated string set") { ok = false; }
  // An empty declared table (address at the buffer end) is zero structures.
  let b6 = smbios_entry32_build(2, 8, 0, 149, 0, 0, 40);
  if !b6.is_ok { return assert(false, "entry build must succeed"); }
  let ep6: Vec[UInt8] = b6.value;
  let img6 = cat(ep6, cat(zeros(1), table));
  let t6: SmbiosTable = table_of(smbios_parse(&img6));
  if smbios_count(&t6) != 0 { ok = false; }
  return assert(ok, "smbios_parse 32-bit policies: count, address and length bounds");
}

fn t15() -> TestResult {
  let table = fixture_table();
  // max_size equal to the table length.
  let b1 = smbios_entry64_build(3, 4, 0, 0, 117, 32);
  if !b1.is_ok { return assert(false, "entry build must succeed"); }
  let ep1: Vec[UInt8] = b1.value;
  let img1 = cat(ep1, cat(zeros(8), table));
  var ok = img1.len() == 149;
  let pr = smbios_parse(&img1);
  if !pr.is_ok { return assert(false, "64-bit image must parse"); }
  let t1: SmbiosTable = pr.value;
  if smbios_count(&t1) != 3 { ok = false; }
  if smbios_struct_start(&t1, 1) != 79 { ok = false; }
  if !str_eq(string_at(&img1, &t1, 1, 2), "SuperBoard") { ok = false; }
  if smbios_memory_device_speed(&img1, &t1, 3) != -1 { ok = false; }
  let er = smbios_entry_parse(&img1);
  if !er.is_ok { ok = false; } else {
    let e: SmbiosEntry = er.value;
    if smbios_entry_kind(&e) != 1 { ok = false; }
    if smbios_entry_docrev(&e) != 0 { ok = false; }
    if smbios_entry_table_addr(&e) != 32 { ok = false; }
    if smbios_entry_max_size(&e) != 117 { ok = false; }
  }
  // max_size 0: the table runs to the buffer end.
  let b2 = smbios_entry64_build(3, 4, 0, 0, 0, 32);
  if !b2.is_ok { return assert(false, "entry build must succeed"); }
  let ep2: Vec[UInt8] = b2.value;
  let img2 = cat(ep2, cat(zeros(8), table));
  let t2: SmbiosTable = table_of(smbios_parse(&img2));
  if smbios_count(&t2) != 3 { ok = false; }
  // max_size 115 cuts inside the End-of-Table structure.
  let b3 = smbios_entry64_build(3, 4, 0, 0, 115, 32);
  if !b3.is_ok { return assert(false, "entry build must succeed"); }
  let ep3: Vec[UInt8] = b3.value;
  let img3 = cat(ep3, cat(zeros(8), table));
  if !err_table_is(smbios_parse(&img3), "smbios: unterminated string set") { ok = false; }
  // A table address outside the buffer is rejected.
  let b4 = smbios_entry64_build(3, 4, 0, 0, 0, 200);
  if !b4.is_ok { return assert(false, "entry build must succeed"); }
  let ep4: Vec[UInt8] = b4.value;
  let img4 = cat(ep4, cat(zeros(8), table));
  if !err_table_is(smbios_parse(&img4), "smbios: table out of buffer") { ok = false; }
  let b5 = smbios_entry64_build(3, 4, 0, 0, 0, 149);
  if !b5.is_ok { return assert(false, "entry build must succeed"); }
  let ep5: Vec[UInt8] = b5.value;
  let img5 = cat(ep5, cat(zeros(8), table));
  if !err_table_is(smbios_parse(&img5), "smbios: table out of buffer") { ok = false; }
  return assert(ok, "64-bit image: u64 table address, max-size bound, address checks");
}

fn t16() -> TestResult {
  let nb = no_bytes();
  let ns = no_strings();
  var ok = err_bytes_is(smbios_entry32_build(256, 8, 0, 0, 0, 0, 0), "smbios: major version out of range");
  if !err_bytes_is(smbios_entry32_build(2, -1, 0, 0, 0, 0, 0), "smbios: minor version out of range") { ok = false; }
  if !err_bytes_is(smbios_entry32_build(2, 8, 65536, 0, 0, 0, 0), "smbios: max structure size out of range") { ok = false; }
  if !err_bytes_is(smbios_entry32_build(2, 8, 0, 4294967296, 0, 0, 0), "smbios: table address out of range") { ok = false; }
  if !err_bytes_is(smbios_entry32_build(2, 8, 0, -1, 0, 0, 0), "smbios: table address out of range") { ok = false; }
  if !err_bytes_is(smbios_entry32_build(2, 8, 0, 0, 65536, 0, 0), "smbios: table length out of range") { ok = false; }
  if !err_bytes_is(smbios_entry32_build(2, 8, 0, 0, 0, 70000, 0), "smbios: structure count out of range") { ok = false; }
  if !err_bytes_is(smbios_entry32_build(2, 8, 0, 0, 0, 0, 256), "smbios: bcd revision out of range") { ok = false; }
  if !err_bytes_is(smbios_entry64_build(3, 0, 300, 0, 0, 0), "smbios: docrev out of range") { ok = false; }
  if !err_bytes_is(smbios_entry64_build(3, 0, 0, -1, 0, 0), "smbios: entry revision out of range") { ok = false; }
  if !err_bytes_is(smbios_entry64_build(3, 0, 0, 0, 4294967296, 0), "smbios: max structure size out of range") { ok = false; }
  if !err_bytes_is(smbios_entry64_build(3, 0, 0, 0, 0, -1), "smbios: table address out of range") { ok = false; }
  let fb = zeros(252);
  if !err_bytes_is(smbios_struct_build(0, 0, &fb, &ns), "smbios: formatted area too long") { ok = false; }
  if !err_bytes_is(smbios_struct_build(256, 0, &nb, &ns), "smbios: structure type out of range") { ok = false; }
  if !err_bytes_is(smbios_struct_build(-1, 0, &nb, &ns), "smbios: structure type out of range") { ok = false; }
  if !err_bytes_is(smbios_struct_build(0, 65536, &nb, &ns), "smbios: handle out of range") { ok = false; }
  if !err_bytes_is(smbios_struct_build(0, -1, &nb, &ns), "smbios: handle out of range") { ok = false; }
  var empties = Vec[Str].new();
  empties.push("");
  if !err_bytes_is(smbios_struct_build(0, 0, &no_bytes(), &empties), "smbios: empty string") { ok = false; }
  let badt = hb("000300000000");
  if !err_bytes_is(smbios_image_build32(&badt, 2, 8, 40), "smbios: invalid structure length") { ok = false; }
  return assert(ok, "builder error catalog: entry fields, structure fields, image input");
}

fn t17() -> TestResult {
  let two = hb("0102");
  let ff = hb("ff");
  let ff00 = hb("ff00");
  let one = hb("01");
  var ok = smbios_checksum8(&two, 0, 2) == 3;
  if smbios_checksum8(&ff, 0, 1) != 255 { ok = false; }
  if smbios_checksum8(&ff00, 0, 2) != 255 { ok = false; }
  if smbios_checksum8(&two, 0, 0) != 0 { ok = false; }
  if smbios_checksum8(&one, 1, 0) != 0 { ok = false; }
  if smbios_checksum8(&one, 2, 1) != -1 { ok = false; }
  if smbios_checksum8(&one, -1, 1) != -1 { ok = false; }
  if smbios_checksum8(&one, 0, -1) != -1 { ok = false; }
  // The four checksum predicates.
  let b32 = smbios_entry32_build(2, 8, 0, 32, 0, 0, 40);
  let b64 = smbios_entry64_build(3, 0, 0, 0, 0, 0);
  if !b32.is_ok || !b64.is_ok { return assert(false, "builds must succeed"); }
  let ep32: Vec[UInt8] = b32.value;
  let ep64: Vec[UInt8] = b64.value;
  if !smbios_entry32_checksum_ok(&ep32) { ok = false; }
  if !smbios_entry32_intermediate_checksum_ok(&ep32) { ok = false; }
  if !smbios_entry64_checksum_ok(&ep64) { ok = false; }
  if !smbios_entry_checksum_ok(&ep32) { ok = false; }
  if !smbios_entry_checksum_ok(&ep64) { ok = false; }
  if smbios_entry32_checksum_ok(&ep64) { ok = false; }
  if smbios_entry32_intermediate_checksum_ok(&ep64) { ok = false; }
  let empty = zeros(24);
  let nz = copy_bytes(&empty);
  nz[23] = 1 as UInt8;
  if smbios_entry64_checksum_ok(&nz) { ok = false; }
  if !smbios_entry64_checksum_ok(&empty) { ok = false; }
  if smbios_entry_checksum_ok(&nz) { ok = false; }
  return assert(ok, "checksum helper: modulo-256 sums, invalid spans, four predicates");
}

fn t18() -> TestResult {
  let table = fixture_table();
  let image = fixture_image();
  var ok = image.len() == 149;
  // Pinned entry-point field bytes inside the image.
  if u8(&image, 0) != 95 { ok = false; }
  if u8(&image, 1) != 83 { ok = false; }
  if u8(&image, 2) != 77 { ok = false; }
  if u8(&image, 3) != 95 { ok = false; }
  if u8(&image, 5) != 31 { ok = false; }
  if u8(&image, 6) != 2 { ok = false; }
  if u8(&image, 7) != 8 { ok = false; }
  if u8(&image, 8) != 0 || u8(&image, 9) != 0 { ok = false; }
  if u8(&image, 10) != 0 { ok = false; }
  if u8(&image, 22) != 117 || u8(&image, 23) != 0 { ok = false; }
  if u8(&image, 24) != 32 { ok = false; }
  if u8(&image, 25) != 0 { ok = false; }
  if u8(&image, 28) != 3 || u8(&image, 29) != 0 { ok = false; }
  if u8(&image, 30) != 40 { ok = false; }
  // Pinned structure bytes: BIOS header/strings, System UUID, EoT pair.
  if u8(&image, 32) != 0 || u8(&image, 33) != 18 { ok = false; }
  if u8(&image, 34) != 0 || u8(&image, 35) != 0 { ok = false; }
  if u8(&image, 32 + 4) != 1 || u8(&image, 32 + 5) != 2 { ok = false; }
  if u8(&image, 32 + 8) != 3 || u8(&image, 32 + 9) != 127 { ok = false; }
  if u8(&image, 32 + 18) != 86 { ok = false; }
  if u8(&image, 79) != 1 || u8(&image, 80) != 27 { ok = false; }
  if u8(&image, 83) != 1 || u8(&image, 84) != 2 { ok = false; }
  if u8(&image, 86) != 4 { ok = false; }
  if u8(&image, 87) != 17 { ok = false; }
  if u8(&image, 102) != 0 { ok = false; }
  if u8(&image, 143) != 127 || u8(&image, 144) != 4 { ok = false; }
  if u8(&image, 148) != 0 { ok = false; }
  if !bytes_equal(slice_bytes(image, 32, 149), table) { ok = false; }
  return assert(ok, "32-bit image layout: pinned entry and structure bytes");
}

fn main() -> Int {
  io.println("=== xiom.smbios conformance tests ===");
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
    io.println("xiom.smbios: all tests passed");
  } else {
    io.println("xiom.smbios: tests failed");
  }
  return failed;
}
