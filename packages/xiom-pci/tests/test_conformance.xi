// XIOM -- xiom.pci conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Port task: prove the pure-XIOM xiom.pci codec against its documented
// 256-byte configuration-space layout, error catalog and builder rules.
//
// Fixtures are assembled byte by byte (zero-filled 256-byte spaces with
// controlled fields), so pci_parse is exercised against bytes the test owns,
// not only against pci_build_type0.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison); names and error messages
// go through compare.str_compare.

module pci_tests
use xiom.io; use xiom.test;
use xiom.pci;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_fn_is(r: Result[PciFunction, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return str_eq(got, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return str_eq(got, want);
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn clone_bytes(v: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Prefix of a byte vector, used to build a short source buffer.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn zero_space() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// Byte at `off` widened to an Int, or -1 when out of range.
fn b8(v: Vec[UInt8], off: Int) -> Int {
  if off < 0 || off >= v.len() {
    return -1;
  }
  return (v[off] as Int) & 0xFF;
}

fn set_u8(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = val as UInt8;
}

fn set_u16(v: &mut Vec[UInt8], off: Int, val: Int) {
  set_u8(v, off, val % 256);
  set_u8(v, off + 1, val / 256);
}

fn set_u32(v: &mut Vec[UInt8], off: Int, val: Int) {
  set_u16(v, off, val % 65536);
  set_u16(v, off + 2, val / 65536);
}

fn empty_fn() -> PciFunction {
  let raw = Vec[UInt8].new();
  let ids = Vec[Int].new();
  let offsets = Vec[Int].new();
  let spans = Vec[Int].new();
  return PciFunction{ raw: raw; cap_ids: ids; cap_offsets: offsets; cap_spans: spans; };
}

// Parsed function, or the empty hand-built function on error (tests then
// fail their assertions instead of crashing).
fn parse_ok(v: &Vec[UInt8]) -> PciFunction {
  let r = pci_parse(v);
  if r.is_ok {
    let f: PciFunction = r.value;
    return f;
  }
  return empty_fn();
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// Type-0 device: vendor 0x1234, device 0x5678, class 0x03 (Display),
// command 0x0407 (IO|MEM|bus-master|interrupt disable), status 0x00B0
// (capability list + 66 MHz + fast back-to-back), BAR0 = 32-bit prefetchable
// memory at 0xFE000000, BAR1 = I/O at 0xE000, expansion ROM 0xC0000005
// (enabled), capability list at 0x40: PM (0x01) -> MSI (0x05, 64-bit).
fn fixture_type0() -> Vec[UInt8] {
  var v = zero_space();
  set_u16(&mut v, 0, 0x1234);
  set_u16(&mut v, 2, 0x5678);
  set_u16(&mut v, 4, 0x0407);
  set_u16(&mut v, 6, 0x00B0);
  set_u8(&mut v, 8, 0x02);
  set_u8(&mut v, 11, 0x03);
  set_u8(&mut v, 12, 0x10);
  set_u8(&mut v, 13, 0x20);
  set_u32(&mut v, 16, 0xFE000008);
  set_u32(&mut v, 20, 0x0000E001);
  set_u16(&mut v, 44, 0x103C);
  set_u16(&mut v, 46, 0x1234);
  set_u32(&mut v, 48, 0xC0000005);
  set_u8(&mut v, 52, 0x40);
  set_u8(&mut v, 64, 0x01);
  set_u8(&mut v, 65, 0x50);
  set_u16(&mut v, 66, 0x0003);
  set_u16(&mut v, 68, 0x0008);
  set_u8(&mut v, 80, 0x05);
  set_u8(&mut v, 81, 0x00);
  set_u16(&mut v, 82, 0x0081);
  set_u32(&mut v, 84, 0xFEE00000);
  set_u32(&mut v, 88, 0x00000000);
  set_u16(&mut v, 92, 0x0041);
  return v;
}

// Type-1 PCI-to-PCI bridge: primary 0, secondary 1, subordinate 2,
// I/O window 0x10/0x20 (4 KiB granularity), memory window 0x1010/0x1020,
// prefetchable window 0x2020/0x2030, expansion ROM 0xC0000805, bridge
// control 0x0040, BAR0 = I/O at 0xE000, no capability list.
fn fixture_bridge() -> Vec[UInt8] {
  var v = zero_space();
  set_u16(&mut v, 0, 0x8086);
  set_u16(&mut v, 2, 0x1237);
  set_u16(&mut v, 4, 0x0007);
  set_u8(&mut v, 8, 0x02);
  set_u8(&mut v, 11, 0x06);
  set_u8(&mut v, 14, 0x01);
  set_u32(&mut v, 16, 0x0000E001);
  set_u8(&mut v, 24, 0x00);
  set_u8(&mut v, 25, 0x01);
  set_u8(&mut v, 26, 0x02);
  set_u8(&mut v, 28, 0x10);
  set_u8(&mut v, 29, 0x20);
  set_u16(&mut v, 30, 0x00A0);
  set_u16(&mut v, 32, 0x1010);
  set_u16(&mut v, 34, 0x1020);
  set_u16(&mut v, 36, 0x2020);
  set_u16(&mut v, 38, 0x2030);
  set_u32(&mut v, 56, 0xC0000805);
  set_u16(&mut v, 62, 0x0040);
  return v;
}

// A space whose status word declares a capability list at `ptr` (the caps
// themselves are written by the caller).
fn cap_space(ptr: Int) -> Vec[UInt8] {
  var v = zero_space();
  set_u16(&mut v, 6, 0x0010);
  set_u8(&mut v, 14, 0x00);
  set_u8(&mut v, 52, ptr);
  return v;
}

fn mk_config() -> PciType0Config {
  var bars = Vec[Int].new();
  bars.push(0xFE000000);
  bars.push(0x0000E001);
  bars.push(0);
  bars.push(0);
  bars.push(0);
  bars.push(0);
  return PciType0Config{
    vendor_id: 0x1234;
    device_id: 0x5678;
    command: 0x0007;
    status: 0x0000;
    revision_id: 0x02;
    prog_if: 0x00;
    subclass: 0x00;
    class_code: 0x03;
    cache_line_size: 0x10;
    latency_timer: 0x20;
    bist: 0x00;
    multifunction: false;
    bars: bars;
    cardbus_cis: 0;
    subsystem_vendor_id: 0x103C;
    subsystem_device_id: 0x1234;
    expansion_rom: 0xC0000000;
  };
}

// Same canonical config with a caller-supplied BAR vector (used by the
// bar-count error check).
fn mk_config_bars(bars: Vec[Int]) -> PciType0Config {
  return PciType0Config{
    vendor_id: 0x1234;
    device_id: 0x5678;
    command: 0x0007;
    status: 0x0000;
    revision_id: 0x02;
    prog_if: 0x00;
    subclass: 0x00;
    class_code: 0x03;
    cache_line_size: 0x10;
    latency_timer: 0x20;
    bist: 0x00;
    multifunction: false;
    bars: bars;
    cardbus_cis: 0;
    subsystem_vendor_id: 0x103C;
    subsystem_device_id: 0x1234;
    expansion_rom: 0xC0000000;
  };
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture_type0();
  let r = pci_parse(&data);
  if !r.is_ok { return assert(false, "type-0 fixture must parse"); }
  let f: PciFunction = r.value;
  var ok = pci_vendor_id(&f) == 0x1234;
  if pci_device_id(&f) != 0x5678 { ok = false; }
  if pci_revision_id(&f) != 0x02 { ok = false; }
  if pci_prog_if(&f) != 0x00 { ok = false; }
  if pci_subclass(&f) != 0x00 { ok = false; }
  if pci_class_code(&f) != 0x03 { ok = false; }
  if pci_cache_line_size(&f) != 0x10 { ok = false; }
  if pci_latency_timer(&f) != 0x20 { ok = false; }
  if pci_bist(&f) != 0x00 { ok = false; }
  if pci_header_type(&f) != 0x00 { ok = false; }
  if pci_header_kind(&f) != 0 { ok = false; }
  if pci_multifunction(&f) { ok = false; }
  if pci_command(&f) != 0x0407 { ok = false; }
  if pci_status(&f) != 0x00B0 { ok = false; }
  if !pci_is_populated(&f) { ok = false; }
  return assert(ok, "type-0 identification and header type are exact");
}

fn t2() -> TestResult {
  let data = fixture_type0();
  let f: PciFunction = parse_ok(&data);
  var ok = pci_command_io_enabled(&f);
  if !pci_command_memory_enabled(&f) { ok = false; }
  if !pci_command_bus_master_enabled(&f) { ok = false; }
  if pci_command_serr_enabled(&f) { ok = false; }
  if !pci_command_interrupt_disabled(&f) { ok = false; }
  if !pci_has_capability_list(&f) { ok = false; }
  if !pci_status_66mhz_capable(&f) { ok = false; }
  if !pci_status_fast_back_to_back(&f) { ok = false; }
  if pci_status_interrupt_pending(&f) { ok = false; }
  if pci_status_master_data_parity_error(&f) { ok = false; }
  return assert(ok, "command/status bit predicates decode flag bits");
}

fn t3() -> TestResult {
  var ok = str_eq(pci_class_name(0x00), "Unclassified");
  if !str_eq(pci_class_name(0x01), "Mass storage controller") { ok = false; }
  if !str_eq(pci_class_name(0x03), "Display controller") { ok = false; }
  if !str_eq(pci_class_name(0x06), "Bridge") { ok = false; }
  if !str_eq(pci_class_name(0x10), "Encryption controller") { ok = false; }
  if !str_eq(pci_class_name(0x13), "Non-Essential Instrumentation") { ok = false; }
  if !str_eq(pci_class_name(0x40), "Coprocessor") { ok = false; }
  if !str_eq(pci_class_name(0xFF), "Unassigned class") { ok = false; }
  if !str_eq(pci_class_name(0x14), "") { ok = false; }
  if !str_eq(pci_class_name(-1), "") { ok = false; }
  if !str_eq(pci_class_name(256), "") { ok = false; }
  if !str_eq(pci_header_kind_name(0), "device") { ok = false; }
  if !str_eq(pci_header_kind_name(1), "bridge") { ok = false; }
  if !str_eq(pci_header_kind_name(2), "cardbus") { ok = false; }
  if !str_eq(pci_header_kind_name(3), "") { ok = false; }
  if !str_eq(pci_cap_name(0x01), "Power Management") { ok = false; }
  if !str_eq(pci_cap_name(0x05), "MSI") { ok = false; }
  if !str_eq(pci_cap_name(0x10), "PCI Express") { ok = false; }
  if !str_eq(pci_cap_name(0x09), "") { ok = false; }
  if !str_eq(pci_cap_name(0), "") { ok = false; }
  return assert(ok, "documented class/header-kind/capability name tables");
}

fn t4() -> TestResult {
  let data = fixture_type0();
  let f: PciFunction = parse_ok(&data);
  var ok = pci_bar_raw(&f, 0) == 0xFE000008;
  if pci_bar_kind(&f, 0) != 0 { ok = false; }
  if pci_bar_memory_type(&f, 0) != 0 { ok = false; }
  if pci_bar_is_64(&f, 0) { ok = false; }
  if pci_bar_is_upper(&f, 0) { ok = false; }
  if pci_bar_address(&f, 0) != 0xFE000000 { ok = false; }
  if pci_bar_size(&f, 0) != 33554432 { ok = false; }
  if pci_bar_raw(&f, 1) != 0x0000E001 { ok = false; }
  if pci_bar_kind(&f, 1) != 1 { ok = false; }
  if pci_bar_memory_type(&f, 1) != -1 { ok = false; }
  if pci_bar_is_64(&f, 1) { ok = false; }
  if pci_bar_is_upper(&f, 1) { ok = false; }
  if pci_bar_address(&f, 1) != 0xE000 { ok = false; }
  if pci_bar_size(&f, 1) != 8192 { ok = false; }
  if pci_bar_raw(&f, 2) != 0 { ok = false; }
  if pci_bar_address(&f, 2) != 0 { ok = false; }
  if pci_bar_size(&f, 2) != 0 { ok = false; }
  if pci_bar_raw(&f, -1) != -1 { ok = false; }
  if pci_bar_kind(&f, 6) != -1 { ok = false; }
  if pci_bar_address(&f, 6) != -1 { ok = false; }
  if pci_bar_size(&f, 6) != -1 { ok = false; }
  return assert(ok, "type-0 BAR kind, masked address and lowest-bit size");
}

fn t5() -> TestResult {
  var v = zero_space();
  set_u32(&mut v, 24, 0x00000004);
  set_u32(&mut v, 28, 0x00000001);
  let f: PciFunction = parse_ok(&v);
  var ok = pci_bar_kind(&f, 2) == 0;
  if pci_bar_memory_type(&f, 2) != 2 { ok = false; }
  if !pci_bar_is_64(&f, 2) { ok = false; }
  if pci_bar_is_upper(&f, 2) { ok = false; }
  if pci_bar_address(&f, 2) != 4294967296 { ok = false; }
  if pci_bar_size(&f, 2) != 4294967296 { ok = false; }
  if !pci_bar_is_upper(&f, 3) { ok = false; }
  if pci_bar_address(&f, 3) != -1 { ok = false; }
  if pci_bar_size(&f, 3) != -1 { ok = false; }
  if pci_bar_raw(&f, 3) != 1 { ok = false; }
  if pci_bar_is_upper(&f, 4) { ok = false; }
  return assert(ok, "64-bit memory BAR combines the upper slot without shifts");
}

fn t6() -> TestResult {
  var v = zero_space();
  set_u32(&mut v, 16, 0x0000E003);
  set_u32(&mut v, 20, 0x0000000E);
  let f: PciFunction = parse_ok(&v);
  var ok = pci_bar_kind(&f, 0) == 1;
  if pci_bar_address(&f, 0) != 0xE000 { ok = false; }
  if pci_bar_size(&f, 0) != 8192 { ok = false; }
  if pci_bar_memory_type(&f, 0) != -1 { ok = false; }
  if pci_bar_kind(&f, 1) != 0 { ok = false; }
  if pci_bar_memory_type(&f, 1) != 3 { ok = false; }
  if pci_bar_is_64(&f, 1) { ok = false; }
  if pci_bar_address(&f, 1) != 0 { ok = false; }
  if pci_bar_size(&f, 1) != 0 { ok = false; }
  return assert(ok, "I/O flags and reserved memory types are masked raw");
}

fn t7() -> TestResult {
  let d0 = fixture_type0();
  let f0: PciFunction = parse_ok(&d0);
  var ok = pci_cardbus_cis(&f0) == 0;
  if pci_subsystem_vendor_id(&f0) != 0x103C { ok = false; }
  if pci_subsystem_device_id(&f0) != 0x1234 { ok = false; }
  if pci_expansion_rom_raw(&f0) != 0xC0000005 { ok = false; }
  if !pci_expansion_rom_enabled(&f0) { ok = false; }
  if pci_expansion_rom_address(&f0) != 0xC0000000 { ok = false; }
  let d1 = fixture_bridge();
  let f1: PciFunction = parse_ok(&d1);
  if pci_cardbus_cis(&f1) != -1 { ok = false; }
  if pci_subsystem_vendor_id(&f1) != -1 { ok = false; }
  if pci_subsystem_device_id(&f1) != -1 { ok = false; }
  if pci_expansion_rom_raw(&f1) != 0xC0000805 { ok = false; }
  if !pci_expansion_rom_enabled(&f1) { ok = false; }
  if pci_expansion_rom_address(&f1) != 0xC0000800 { ok = false; }
  return assert(ok, "type-0 CIS/subsystem/expansion-ROM accessors and kind guard");
}

fn t8() -> TestResult {
  let data = fixture_type0();
  let f: PciFunction = parse_ok(&data);
  var ok = pci_cap_count(&f) == 2;
  if pci_cap_id(&f, 0) != 0x01 { ok = false; }
  if pci_cap_id(&f, 1) != 0x05 { ok = false; }
  if pci_cap_offset(&f, 0) != 0x40 { ok = false; }
  if pci_cap_offset(&f, 1) != 0x50 { ok = false; }
  if pci_cap_span(&f, 0) != 16 { ok = false; }
  if pci_cap_span(&f, 1) != 176 { ok = false; }
  if pci_cap_find(&f, 0x01) != 0 { ok = false; }
  if pci_cap_find(&f, 0x05) != 1 { ok = false; }
  if pci_cap_find(&f, 0x10) != -1 { ok = false; }
  if pci_cap_id(&f, -1) != -1 { ok = false; }
  if pci_cap_id(&f, 2) != -1 { ok = false; }
  if pci_cap_offset(&f, 2) != -1 { ok = false; }
  if pci_cap_span(&f, 2) != -1 { ok = false; }
  let d1 = fixture_bridge();
  let f1: PciFunction = parse_ok(&d1);
  if pci_cap_count(&f1) != 0 { ok = false; }
  if pci_cap_find(&f1, 0x01) != -1 { ok = false; }
  return assert(ok, "capability walk order, spans, find and range guards");
}

fn t9() -> TestResult {
  let data = fixture_type0();
  let f: PciFunction = parse_ok(&data);
  var ok = pci_cap_pm_version(&f, 0) == 3;
  if pci_cap_pm_control(&f, 0) != 8 { ok = false; }
  if pci_cap_read_u8(&f, 0, 0) != 0x01 { ok = false; }
  if pci_cap_read_u8(&f, 0, 1) != 0x50 { ok = false; }
  if pci_cap_read_u16(&f, 0, 2) != 0x0003 { ok = false; }
  if pci_cap_read_u32(&f, 0, 4) != 0x00000008 { ok = false; }
  if pci_cap_pm_version(&f, 1) != -1 { ok = false; }
  if pci_cap_msi_control(&f, 0) != -1 { ok = false; }
  if pci_cap_read_u8(&f, 0, 16) != -1 { ok = false; }
  if pci_cap_read_u16(&f, 0, 15) != -1 { ok = false; }
  if pci_cap_read_u8(&f, 0, -1) != -1 { ok = false; }
  if pci_cap_read_u32(&f, 0, 13) != -1 { ok = false; }
  if pci_cap_read_u8(&f, 2, 0) != -1 { ok = false; }
  return assert(ok, "PM subset and span-bounded raw capability reads");
}

fn t10() -> TestResult {
  let data = fixture_type0();
  let f: PciFunction = parse_ok(&data);
  var ok = pci_cap_msi_control(&f, 1) == 0x0081;
  if !pci_cap_msi_64bit(&f, 1) { ok = false; }
  if pci_cap_msi_address(&f, 1) != 0xFEE00000 { ok = false; }
  if pci_cap_msi_data(&f, 1) != 0x0041 { ok = false; }
  var v2: Vec[UInt8] = clone_bytes(data);
  set_u16(&mut v2, 82, 0x0001);
  set_u32(&mut v2, 84, 0xFEE01000);
  set_u32(&mut v2, 88, 0x00000042);
  let f2: PciFunction = parse_ok(&v2);
  if pci_cap_msi_64bit(&f2, 1) { ok = false; }
  if pci_cap_msi_address(&f2, 1) != 0xFEE01000 { ok = false; }
  if pci_cap_msi_data(&f2, 1) != 0x0042 { ok = false; }
  if pci_cap_pm_version(&f2, 1) != -1 { ok = false; }
  return assert(ok, "MSI 64-bit and 32-bit message subset accessors");
}

fn t11() -> TestResult {
  var v = cap_space(0x40);
  set_u8(&mut v, 64, 0x10);
  set_u8(&mut v, 65, 0x00);
  set_u16(&mut v, 66, 0x0002);
  set_u32(&mut v, 68, 0x0000001F);
  let f: PciFunction = parse_ok(&v);
  var ok = pci_cap_count(&f) == 1;
  if pci_cap_id(&f, 0) != 0x10 { ok = false; }
  if pci_cap_offset(&f, 0) != 0x40 { ok = false; }
  if pci_cap_span(&f, 0) != 192 { ok = false; }
  if pci_cap_pcie_version(&f, 0) != 2 { ok = false; }
  if pci_cap_pcie_device_caps(&f, 0) != 31 { ok = false; }
  if pci_cap_read_u16(&f, 0, 2) != 2 { ok = false; }
  if pci_cap_pcie_version(&f, 0) != pci_cap_read_u16(&f, 0, 2) % 16 { ok = false; }
  let d0 = fixture_type0();
  let f0: PciFunction = parse_ok(&d0);
  if pci_cap_pcie_version(&f0, 0) != -1 { ok = false; }
  if pci_cap_pcie_device_caps(&f0, 1) != -1 { ok = false; }
  return assert(ok, "PCIe documented subset (version, device capabilities)");
}

fn t12() -> TestResult {
  let short = prefix(fixture_type0(), 255);
  var ok = err_fn_is(pci_parse(&short), "pci: truncated config space");
  let none = Vec[UInt8].new();
  if !err_fn_is(pci_parse(&none), "pci: truncated config space") { ok = false; }
  let p0 = cap_space(0x00);
  if !err_fn_is(pci_parse(&p0), "pci: bad capability pointer") { ok = false; }
  let p3c = cap_space(0x3C);
  if !err_fn_is(pci_parse(&p3c), "pci: bad capability pointer") { ok = false; }
  let p41 = cap_space(0x41);
  if !err_fn_is(pci_parse(&p41), "pci: bad capability pointer") { ok = false; }
  var unaligned = cap_space(0x40);
  set_u8(&mut unaligned, 64, 0x01);
  set_u8(&mut unaligned, 65, 0x51);
  if !err_fn_is(pci_parse(&unaligned), "pci: bad capability pointer") { ok = false; }
  var far = cap_space(0x40);
  set_u8(&mut far, 64, 0x01);
  set_u8(&mut far, 65, 0xFF);
  if !err_fn_is(pci_parse(&far), "pci: bad capability pointer") { ok = false; }
  var self_loop = cap_space(0x40);
  set_u8(&mut self_loop, 64, 0x01);
  set_u8(&mut self_loop, 65, 0x40);
  if !err_fn_is(pci_parse(&self_loop), "pci: capability loop") { ok = false; }
  var back = cap_space(0x40);
  set_u8(&mut back, 64, 0x01);
  set_u8(&mut back, 65, 0x60);
  set_u8(&mut back, 96, 0x05);
  set_u8(&mut back, 97, 0x40);
  if !err_fn_is(pci_parse(&back), "pci: capability loop") { ok = false; }
  var late_start = cap_space(0x80);
  set_u8(&mut late_start, 128, 0x01);
  set_u8(&mut late_start, 129, 0x40);
  if !err_fn_is(pci_parse(&late_start), "pci: capability loop") { ok = false; }
  let good = fixture_type0();
  if !pci_parse(&good).is_ok { ok = false; }
  return assert(ok, "truncation, pointer range/alignment and loop errors");
}

fn t13() -> TestResult {
  var kind2 = cap_space(0xFF);
  set_u8(&mut kind2, 14, 0x02);
  let r2 = pci_parse(&kind2);
  if !r2.is_ok { return assert(false, "kind 0x02 must parse"); }
  let f2: PciFunction = r2.value;
  var ok = pci_header_kind(&f2) == 2;
  if pci_multifunction(&f2) { ok = false; }
  if pci_cap_count(&f2) != 0 { ok = false; }
  if !pci_has_capability_list(&f2) { ok = false; }
  if pci_bar_raw(&f2, 0) != 0 { ok = false; }
  if pci_bar_kind(&f2, 0) != 0 { ok = false; }
  if pci_bar_raw(&f2, 1) != -1 { ok = false; }
  var kind3 = cap_space(0x41);
  set_u8(&mut kind3, 14, 0x83);
  let r3 = pci_parse(&kind3);
  if !r3.is_ok { return assert(false, "unknown kind must parse raw"); }
  let f3: PciFunction = r3.value;
  if pci_header_kind(&f3) != 3 { ok = false; }
  if !pci_multifunction(&f3) { ok = false; }
  if pci_cap_count(&f3) != 0 { ok = false; }
  if pci_bar_raw(&f3, 0) != -1 { ok = false; }
  var multi = fixture_type0();
  set_u8(&mut multi, 14, 0x80);
  let r4 = pci_parse(&multi);
  if !r4.is_ok { return assert(false, "kind 0x80 must parse"); }
  let f4: PciFunction = r4.value;
  if pci_header_kind(&f4) != 0 { ok = false; }
  if !pci_multifunction(&f4) { ok = false; }
  if pci_cap_count(&f4) != 2 { ok = false; }
  var status_clear = zero_space();
  set_u8(&mut status_clear, 52, 0xFF);
  let fsc: PciFunction = parse_ok(&status_clear);
  if pci_cap_count(&fsc) != 0 { ok = false; }
  if pci_has_capability_list(&fsc) { ok = false; }
  return assert(ok, "kind and status-bit gating of the capability walk");
}

fn t14() -> TestResult {
  var vendor_absent = zero_space();
  set_u16(&mut vendor_absent, 0, 0xFFFF);
  let r0 = pci_parse(&vendor_absent);
  if !r0.is_ok { return assert(false, "0xFFFF vendor space must parse"); }
  let f0: PciFunction = r0.value;
  var ok = !pci_is_populated(&f0);
  if pci_vendor_id(&f0) != 0xFFFF { ok = false; }
  let zero_vendor = zero_space();
  let fz: PciFunction = parse_ok(&zero_vendor);
  if pci_vendor_id(&fz) != 0 { ok = false; }
  if !pci_is_populated(&fz) { ok = false; }
  let e: PciFunction = empty_fn();
  if pci_vendor_id(&e) != -1 { ok = false; }
  if pci_is_populated(&e) { ok = false; }
  if pci_header_kind(&e) != -1 { ok = false; }
  if pci_raw_byte(&e, 0) != -1 { ok = false; }
  if pci_bar_raw(&e, 0) != -1 { ok = false; }
  if pci_cap_count(&e) != 0 { ok = false; }
  if pci_cap_find(&e, 1) != -1 { ok = false; }
  return assert(ok, "vendor 0xFFFF is unpopulated; short raw is defensive");
}

fn t15() -> TestResult {
  let cfg = mk_config();
  let r = pci_build_type0(&cfg);
  if !r.is_ok { return assert(false, "type-0 build must succeed"); }
  let built: Vec[UInt8] = r.value;
  var ok = built.len() == 256;
  if b8(built, 0) != 0x34 { ok = false; }
  if b8(built, 1) != 0x12 { ok = false; }
  if b8(built, 2) != 0x78 { ok = false; }
  if b8(built, 3) != 0x56 { ok = false; }
  if b8(built, 4) != 0x07 { ok = false; }
  if b8(built, 6) != 0x00 { ok = false; }
  if b8(built, 14) != 0x00 { ok = false; }
  if b8(built, 15) != 0x00 { ok = false; }
  if b8(built, 16) != 0x00 { ok = false; }
  if b8(built, 19) != 0xFE { ok = false; }
  if b8(built, 20) != 0x01 { ok = false; }
  if b8(built, 21) != 0xE0 { ok = false; }
  if b8(built, 23) != 0x00 { ok = false; }
  if b8(built, 44) != 0x3C { ok = false; }
  if b8(built, 45) != 0x10 { ok = false; }
  if b8(built, 46) != 0x34 { ok = false; }
  if b8(built, 47) != 0x12 { ok = false; }
  if b8(built, 48) != 0x00 { ok = false; }
  if b8(built, 51) != 0xC0 { ok = false; }
  if b8(built, 52) != 0x00 { ok = false; }
  if b8(built, 64) != 0x00 { ok = false; }
  if b8(built, 255) != 0x00 { ok = false; }
  let pr = pci_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let f: PciFunction = pr.value;
    if pci_vendor_id(&f) != 0x1234 { ok = false; }
    if pci_device_id(&f) != 0x5678 { ok = false; }
    if pci_class_code(&f) != 0x03 { ok = false; }
    if pci_header_kind(&f) != 0 { ok = false; }
    if pci_bar_kind(&f, 0) != 0 { ok = false; }
    if pci_bar_address(&f, 0) != 0xFE000000 { ok = false; }
    if pci_bar_size(&f, 0) != 33554432 { ok = false; }
    if pci_bar_kind(&f, 1) != 1 { ok = false; }
    if pci_bar_address(&f, 1) != 0xE000 { ok = false; }
    if pci_subsystem_vendor_id(&f) != 0x103C { ok = false; }
    if pci_subsystem_device_id(&f) != 0x1234 { ok = false; }
    if pci_expansion_rom_raw(&f) != 0xC0000000 { ok = false; }
    if pci_has_capability_list(&f) { ok = false; }
    if pci_cap_count(&f) != 0 { ok = false; }
    let back: Vec[UInt8] = pci_serialize(&f);
    if !bytes_equal(back, built) { ok = false; }
  }
  var mcfg = mk_config();
  mcfg.multifunction = true;
  let mr = pci_build_type0(&mcfg);
  if !mr.is_ok { ok = false; } else {
    let mbuilt: Vec[UInt8] = mr.value;
    if b8(mbuilt, 14) != 0x80 { ok = false; }
    let mf: PciFunction = parse_ok(&mbuilt);
    if pci_header_kind(&mf) != 0 { ok = false; }
    if !pci_multifunction(&mf) { ok = false; }
  }
  return assert(ok, "canonical type-0 builder bytes and build/parse round-trip");
}

fn t16() -> TestResult {
  var ok = true;
  var five = Vec[Int].new();
  five.push(1);
  five.push(2);
  five.push(3);
  five.push(4);
  five.push(5);
  var c0 = mk_config_bars(five);
  if !err_bytes_is(pci_build_type0(&c0), "pci: bar count") { ok = false; }
  var c1 = mk_config();
  c1.vendor_id = 65536;
  if !err_bytes_is(pci_build_type0(&c1), "pci: bad word field") { ok = false; }
  var c2 = mk_config();
  c2.status = -1;
  if !err_bytes_is(pci_build_type0(&c2), "pci: bad word field") { ok = false; }
  var c3 = mk_config();
  c3.revision_id = 256;
  if !err_bytes_is(pci_build_type0(&c3), "pci: bad byte field") { ok = false; }
  var c4 = mk_config();
  c4.bist = -1;
  if !err_bytes_is(pci_build_type0(&c4), "pci: bad byte field") { ok = false; }
  var c5 = mk_config();
  c5.expansion_rom = 4294967296;
  if !err_bytes_is(pci_build_type0(&c5), "pci: bad dword field") { ok = false; }
  var c6 = mk_config();
  c6.cardbus_cis = -1;
  if !err_bytes_is(pci_build_type0(&c6), "pci: bad dword field") { ok = false; }
  var c7 = mk_config();
  c7.status = 0x0010;
  if !err_bytes_is(pci_build_type0(&c7), "pci: capability list bit set") { ok = false; }
  return assert(ok, "builder validation order and error strings");
}

fn t17() -> TestResult {
  let d0 = fixture_type0();
  let f0: PciFunction = parse_ok(&d0);
  var ok = bytes_equal(pci_serialize(&f0), d0);
  if pci_raw_byte(&f0, 0) != 0x34 { ok = false; }
  if pci_raw_byte(&f0, 255) != 0x00 { ok = false; }
  if pci_raw_byte(&f0, -1) != -1 { ok = false; }
  if pci_raw_byte(&f0, 256) != -1 { ok = false; }
  let d1 = fixture_bridge();
  let f1: PciFunction = parse_ok(&d1);
  if !bytes_equal(pci_serialize(&f1), d1) { ok = false; }
  var pv = cap_space(0x40);
  set_u8(&mut pv, 64, 0x10);
  set_u8(&mut pv, 65, 0x60);
  set_u8(&mut pv, 96, 0x42);
  set_u8(&mut pv, 97, 0x00);
  let fp: PciFunction = parse_ok(&pv);
  if !bytes_equal(pci_serialize(&fp), pv) { ok = false; }
  if pci_cap_count(&fp) != 2 { ok = false; }
  if pci_cap_id(&fp, 1) != 0x42 { ok = false; }
  if pci_cap_span(&fp, 1) != 160 { ok = false; }
  return assert(ok, "parse then serialize reproduces every fixture byte-for-byte");
}

fn t18() -> TestResult {
  let data = fixture_bridge();
  let f: PciFunction = parse_ok(&data);
  var ok = pci_header_kind(&f) == 1;
  if pci_multifunction(&f) { ok = false; }
  if pci_bridge_primary_bus(&f) != 0 { ok = false; }
  if pci_bridge_secondary_bus(&f) != 1 { ok = false; }
  if pci_bridge_subordinate_bus(&f) != 2 { ok = false; }
  if pci_bridge_secondary_status(&f) != 0x00A0 { ok = false; }
  if pci_bridge_io_base(&f) != 4096 { ok = false; }
  if pci_bridge_io_limit(&f) != 8192 { ok = false; }
  if pci_bridge_memory_base(&f) != 269484032 { ok = false; }
  if pci_bridge_memory_limit(&f) != 270532608 { ok = false; }
  if pci_bridge_prefetchable_base(&f) != 538968064 { ok = false; }
  if pci_bridge_prefetchable_limit(&f) != 540016640 { ok = false; }
  if pci_bridge_control(&f) != 0x0040 { ok = false; }
  if pci_bridge_io_is_32bit(&f) { ok = false; }
  if pci_bar_kind(&f, 0) != 1 { ok = false; }
  if pci_bar_address(&f, 0) != 0xE000 { ok = false; }
  if pci_bar_size(&f, 0) != 8192 { ok = false; }
  if pci_bar_raw(&f, 1) != 0 { ok = false; }
  if pci_bar_raw(&f, 2) != -1 { ok = false; }
  if pci_bar_address(&f, 4) != -1 { ok = false; }
  var v2: Vec[UInt8] = clone_bytes(data);
  set_u8(&mut v2, 28, 0x11);
  let f2: PciFunction = parse_ok(&v2);
  if !pci_bridge_io_is_32bit(&f2) { ok = false; }
  if pci_bridge_io_base(&f2) != 4096 { ok = false; }
  let d0 = fixture_type0();
  let f0: PciFunction = parse_ok(&d0);
  if pci_bridge_primary_bus(&f0) != -1 { ok = false; }
  if pci_bridge_control(&f0) != -1 { ok = false; }
  if pci_bridge_io_base(&f0) != -1 { ok = false; }
  if pci_bridge_io_is_32bit(&f0) { ok = false; }
  return assert(ok, "type-1 bridge windows, granularity and kind guards");
}

fn main() -> Int {
  io.println("=== xiom.pci conformance tests ===");
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
    io.println("xiom.pci: all tests passed");
  } else {
    io.println("xiom.pci: tests failed");
  }
  return failed;
}
