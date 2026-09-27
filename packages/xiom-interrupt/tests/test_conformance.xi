// XIOM -- xiom.interrupt conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented structure-codec behavior against synthetic buffers
// built in-test: hand-assembled x86 IDT gate32/gate64 descriptors and
// IDTRs (including malformed reserve/reserved-field cases), the GICv2
// distributor register matrix (CTLR, TYPER, bitmaps, priority byte,
// target byte, group bit), the IRQ classification boundaries 15/16/31/32
// and the note-level GICv3 extras.
//
// Independent fixtures: every expected value is written into the test
// file, not computed by the module under test. Str values are compared
// with compare.str_compare / str_eq, never `==`, and every Vec element
// read is bound to a typed local.

module interrupt_tests
use xiom.io; use xiom.test;
use xiom.interrupt;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte-vector helpers
// --------------------------------------------------

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
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

fn set_bytes(v: Vec[UInt8], pos: Int, bs: Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    var hit: Int = -1;
    var j = 0;
    while j < bs.len() {
      if i == pos + j {
        hit = j;
      }
      j = j + 1;
    }
    if hit >= 0 {
      let x: Int = bs[hit];
      out.push(x as UInt8);
    } else {
      let b: UInt8 = v[i];
      out.push(b);
    }
    i = i + 1;
  }
  return out;
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

// Word of four little-endian bytes `b0..b3` written into `v` at `pos`.
fn put_word(v: Vec[UInt8], pos: Int, b0: Int, b1: Int, b2: Int, b3: Int) -> Vec[UInt8] {
  var bs = Vec[Int].new();
  bs.push(b0);
  bs.push(b1);
  bs.push(b2);
  bs.push(b3);
  return set_bytes(v, pos, bs);
}

// Hand-assembled 8-byte 32-bit IDT gate: split offset `lo`/`mid`, 16-bit
// `sel`, reserved byte `res`, attribute byte `attr`.
fn gate32_fixture(lo: Int, sel: Int, res: Int, attr: Int, mid: Int) -> Vec[UInt8] {
  var bs = Vec[Int].new();
  bs.push(lo % 256);
  bs.push((lo / 256) % 256);
  bs.push(sel % 256);
  bs.push((sel / 256) % 256);
  bs.push(res);
  bs.push(attr);
  bs.push(mid % 256);
  bs.push((mid / 256) % 256);
  return set_bytes(zeros(8), 0, bs);
}

// Hand-assembled 16-byte 64-bit IDT gate.
fn gate64_fixture(lo: Int, sel: Int, ist: Int, attr: Int, mid: Int, high: Int) -> Vec[UInt8] {
  var bs = Vec[Int].new();
  bs.push(lo % 256);
  bs.push((lo / 256) % 256);
  bs.push(sel % 256);
  bs.push((sel / 256) % 256);
  bs.push(ist);
  bs.push(attr);
  bs.push(mid % 256);
  bs.push((mid / 256) % 256);
  bs.push(high % 256);
  bs.push((high / 256) % 256);
  bs.push((high / 65536) % 256);
  bs.push((high / 16777216) % 256);
  bs.push(0);
  bs.push(0);
  bs.push(0);
  bs.push(0);
  return set_bytes(zeros(16), 0, bs);
}

// --------------------------------------------------
//  Result helpers
// --------------------------------------------------

fn gate_of(r: Result[X86IdtGate, Str]) -> X86IdtGate {
  if r.is_ok {
    let v: X86IdtGate = r.value;
    return v;
  }
  return X86IdtGate{
    target_offset: -1; code_selector: -1; ist_index: -1; gate_type: -1;
    dpl: -1; present: false; storage_segment: false; long_mode: false;
  };
}

fn idtr_of(r: Result[X86Idtr, Str]) -> X86Idtr {
  if r.is_ok {
    let v: X86Idtr = r.value;
    return v;
  }
  return X86Idtr{ limit: -1; base: -1; long_mode: false; };
}

fn ctl_of(r: Result[GicdCtlr, Str]) -> GicdCtlr {
  if r.is_ok {
    let v: GicdCtlr = r.value;
    return v;
  }
  return GicdCtlr{
    enable_grp0: false; enable_grp1: false; enable_grp1s: false;
    enable_grp1ns: false; are_s: false; are_ns: false;
    disable_security: false; nassgi_req: false; rwp: false; raw: -1;
  };
}

fn typ_of(r: Result[GicdTyper, Str]) -> GicdTyper {
  if r.is_ok {
    let v: GicdTyper = r.value;
    return v;
  }
  return GicdTyper{
    it_lines_number: -1; cpu_count: -1; espi: false; espi_range: -1;
    security_extn: false; mbis: false; lspi: false; max_interrupts: -1;
    raw: -1;
  };
}

fn typ2_of(r: Result[GicdTyper2, Str]) -> GicdTyper2 {
  if r.is_ok {
    let v: GicdTyper2 = r.value;
    return v;
  }
  return GicdTyper2{ vid: -1; vil: false; nassgi_cap: false; raw: -1 };
}

fn tgt_of(r: Result[GicdTarget, Str]) -> GicdTarget {
  if r.is_ok {
    let v: GicdTarget = r.value;
    return v;
  }
  return GicdTarget{ irq: -1; targets: -1; writable: false };
}

fn int_of(r: Result[Int, Str]) -> Int {
  if r.is_ok {
    let v: Int = r.value;
    return v;
  }
  return -1;
}

fn bool_of(r: Result[Bool, Str]) -> Bool {
  if r.is_ok {
    let v: Bool = r.value;
    return v;
  }
  return false;
}

fn bytes_of(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok {
    let v: Vec[UInt8] = r.value;
    return v;
  }
  return Vec[UInt8].new();
}

fn err_gate_is(r: Result[X86IdtGate, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_idtr_is(r: Result[X86Idtr, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_ctl_is(r: Result[GicdCtlr, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_typ_is(r: Result[GicdTyper, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_typ2_is(r: Result[GicdTyper2, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_tgt_is(r: Result[GicdTarget, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Tests: x86 IDT
// --------------------------------------------------

fn t1() -> TestResult {
  let d = gate32_fixture(0x1234, 0x0008, 0x00, 0x8E, 0x9ABC);
  let r = x86_idt_gate32_decode(&d, 0);
  var ok = r.is_ok;
  if ok {
    let g: X86IdtGate = r.value;
    if x86_idt_gate_target_offset(&g) != 2596016692 { ok = false; }
    if x86_idt_gate_selector(&g) != 8 { ok = false; }
    if x86_idt_gate_ist(&g) != 0 { ok = false; }
    if x86_idt_gate_type(&g) != 14 { ok = false; }
    if x86_idt_gate_dpl(&g) != 0 { ok = false; }
    if !x86_idt_gate_present(&g) { ok = false; }
    if x86_idt_gate_storage(&g) { ok = false; }
    if x86_idt_gate_long_mode(&g) { ok = false; }
    if !x86_idt_gate_is_interrupt(&g) { ok = false; }
    if x86_idt_gate_is_trap(&g) { ok = false; }
    if !x86_idt_gate_valid(&g) { ok = false; }
  }
  return assert(ok, "gate32 decode: 0x9ABC1234 / selector 8 / interrupt gate / present");
}

fn t2() -> TestResult {
  var ok = true;
  let not_present = gate32_fixture(0x0010, 0x0008, 0x00, 0x0E, 0x0000);
  let g1 = gate_of(x86_idt_gate32_decode(&not_present, 0));
  if x86_idt_gate_present(&g1) { ok = false; }
  if x86_idt_gate_valid(&g1) { ok = false; }
  if x86_idt_gate_type(&g1) != 14 { ok = false; }
  let trap3 = gate32_fixture(0x0020, 0x0008, 0x00, 0xEF, 0x0000);
  let g2 = gate_of(x86_idt_gate32_decode(&trap3, 0));
  if !x86_idt_gate_is_trap(&g2) { ok = false; }
  if x86_idt_gate_dpl(&g2) != 3 { ok = false; }
  if !x86_idt_gate_present(&g2) { ok = false; }
  if !x86_idt_gate_valid(&g2) { ok = false; }
  let storage = gate32_fixture(0x0030, 0x0008, 0x00, 0x1E, 0x0000);
  let g3 = gate_of(x86_idt_gate32_decode(&storage, 0));
  if !x86_idt_gate_storage(&g3) { ok = false; }
  if x86_idt_gate_valid(&g3) { ok = false; }
  let legacy = gate32_fixture(0x0040, 0x0008, 0x00, 0x86, 0x0000);
  let g4 = gate_of(x86_idt_gate32_decode(&legacy, 0));
  if x86_idt_gate_type(&g4) != 6 { ok = false; }
  if x86_idt_gate_valid(&g4) { ok = false; }
  return assert(ok, "gate32 attribute matrix: P/S/DPL/type and valid-bit rules");
}

fn t3() -> TestResult {
  let short = zeros(7);
  var ok = err_gate_is(x86_idt_gate32_decode(&short, 0), "interrupt: idt gate32 block out of range at offset 0 (need 8 bytes, have 7)");
  let full = gate32_fixture(0x1234, 0x0008, 0x00, 0x8E, 0x9ABC);
  if !err_gate_is(x86_idt_gate32_decode(&full, 1), "interrupt: idt gate32 block out of range at offset 1 (need 8 bytes, have 8)") { ok = false; }
  if !err_gate_is(x86_idt_gate32_decode(&full, -1), "interrupt: idt gate32 block out of range at offset -1 (need 8 bytes, have 8)") { ok = false; }
  let bad_res = gate32_fixture(0x1234, 0x0008, 0x01, 0x8E, 0x9ABC);
  if !err_gate_is(x86_idt_gate32_decode(&bad_res, 0), "interrupt: idt gate32 reserved byte invalid at offset 4") { ok = false; }
  return assert(ok, "gate32 errors: short block, out-of-range offset, nonzero reserved byte");
}

fn t4() -> TestResult {
  let d = gate64_fixture(0x5678, 0x0010, 3, 0x8F, 0x1234, 1);
  let r = x86_idt_gate64_decode(&d, 0);
  var ok = r.is_ok;
  if ok {
    let g: X86IdtGate = r.value;
    if x86_idt_gate_target_offset(&g) != 4600387192 { ok = false; }
    if x86_idt_gate_selector(&g) != 16 { ok = false; }
    if x86_idt_gate_ist(&g) != 3 { ok = false; }
    if x86_idt_gate_type(&g) != 15 { ok = false; }
    if x86_idt_gate_dpl(&g) != 0 { ok = false; }
    if !x86_idt_gate_present(&g) { ok = false; }
    if x86_idt_gate_storage(&g) { ok = false; }
    if !x86_idt_gate_long_mode(&g) { ok = false; }
    if !x86_idt_gate_is_trap(&g) { ok = false; }
    if !x86_idt_gate_valid(&g) { ok = false; }
  }
  return assert(ok, "gate64 decode: 0x112345678 / IST 3 / trap gate / present");
}

fn t5() -> TestResult {
  let short = zeros(15);
  var ok = err_gate_is(x86_idt_gate64_decode(&short, 0), "interrupt: idt gate64 block out of range at offset 0 (need 16 bytes, have 15)");
  let bad_ist = gate64_fixture(0x5678, 0x0010, 8, 0x8F, 0x1234, 1);
  if !err_gate_is(x86_idt_gate64_decode(&bad_ist, 0), "interrupt: idt gate64 ist/reserved byte invalid at offset 4") { ok = false; }
  let bad_tail = patched(gate64_fixture(0x5678, 0x0010, 7, 0x8F, 0x1234, 1), 12, 0x01);
  if !err_gate_is(x86_idt_gate64_decode(&bad_tail, 0), "interrupt: idt gate64 reserved tail invalid at offset 12") { ok = false; }
  let g = gate_of(x86_idt_gate64_decode(&gate64_fixture(0x5678, 0x0010, 7, 0x8F, 0x1234, 1), 0));
  if x86_idt_gate_ist(&g) != 7 { ok = false; }
  return assert(ok, "gate64 errors: short block, IST/reserved byte, reserved tail; IST 7 decodes");
}

fn t6() -> TestResult {
  let br = x86_idt_gate32_build(2596016692, 8, 14, 1, true, false);
  var ok = br.is_ok;
  if ok {
    let b: Vec[UInt8] = br.value;
    if !bytes_equal(b, hb("3412080000aebc9a")) { ok = false; }
    if b.len() != 8 { ok = false; }
    let g = gate_of(x86_idt_gate32_decode(&b, 0));
    if x86_idt_gate_target_offset(&g) != 2596016692 { ok = false; }
    if x86_idt_gate_dpl(&g) != 1 { ok = false; }
    if x86_idt_gate_type(&g) != 14 { ok = false; }
    if !x86_idt_gate_valid(&g) { ok = false; }
  }
  if !err_bytes_is(x86_idt_gate32_build(-1, 8, 14, 0, true, false), "interrupt: idt gate32 target offset out of range") { ok = false; }
  if !err_bytes_is(x86_idt_gate32_build(4294967296, 8, 14, 0, true, false), "interrupt: idt gate32 target offset out of range") { ok = false; }
  if !err_bytes_is(x86_idt_gate32_build(0, 65536, 14, 0, true, false), "interrupt: idt gate32 selector out of range") { ok = false; }
  if !err_bytes_is(x86_idt_gate32_build(0, 8, 16, 0, true, false), "interrupt: idt gate32 gate type out of range") { ok = false; }
  if !err_bytes_is(x86_idt_gate32_build(0, 8, 14, 4, true, false), "interrupt: idt gate32 dpl out of range") { ok = false; }
  return assert(ok, "gate32 builder: canonical bytes, round-trip and error catalog");
}

fn t7() -> TestResult {
  let br = x86_idt_gate64_build(4600387192, 16, 3, 15, 2, true, false);
  var ok = br.is_ok;
  if ok {
    let b: Vec[UInt8] = br.value;
    if !bytes_equal(b, hb("7856100003cf34120100000000000000")) { ok = false; }
    if b.len() != 16 { ok = false; }
    let g = gate_of(x86_idt_gate64_decode(&b, 0));
    if x86_idt_gate_target_offset(&g) != 4600387192 { ok = false; }
    if x86_idt_gate_ist(&g) != 3 { ok = false; }
    if x86_idt_gate_dpl(&g) != 2 { ok = false; }
    if !x86_idt_gate_is_trap(&g) { ok = false; }
    if !x86_idt_gate_long_mode(&g) { ok = false; }
    if !x86_idt_gate_valid(&g) { ok = false; }
  }
  if !err_bytes_is(x86_idt_gate64_build(-1, 16, 0, 15, 0, true, false), "interrupt: idt gate64 target offset out of range") { ok = false; }
  if !err_bytes_is(x86_idt_gate64_build(0, 65536, 0, 15, 0, true, false), "interrupt: idt gate64 selector out of range") { ok = false; }
  if !err_bytes_is(x86_idt_gate64_build(0, 16, 8, 15, 0, true, false), "interrupt: idt gate64 ist index out of range") { ok = false; }
  if !err_bytes_is(x86_idt_gate64_build(0, 16, 0, 16, 0, true, false), "interrupt: idt gate64 gate type out of range") { ok = false; }
  if !err_bytes_is(x86_idt_gate64_build(0, 16, 0, 15, 4, true, false), "interrupt: idt gate64 dpl out of range") { ok = false; }
  return assert(ok, "gate64 builder: canonical bytes, round-trip and error catalog");
}

fn t8() -> TestResult {
  var ok = x86_idt_gate32_join(0x1234, 0x9ABC) == 2596016692;
  if x86_idt_gate64_join(0x5678, 0x1234, 1) != 4600387192 { ok = false; }
  let p32 = x86_idt_gate32_offset_parts(2596016692);
  if p32.len() != 2 { ok = false; } else {
    let lo: Int = p32[0];
    let mid: Int = p32[1];
    if lo != 4660 { ok = false; }
    if mid != 39612 { ok = false; }
  }
  let p64 = x86_idt_gate64_offset_parts(4600387192);
  if p64.len() != 3 { ok = false; } else {
    let lo2: Int = p64[0];
    let mid2: Int = p64[1];
    let hi2: Int = p64[2];
    if lo2 != 22136 { ok = false; }
    if mid2 != 4660 { ok = false; }
    if hi2 != 1 { ok = false; }
  }
  let neg = x86_idt_gate64_offset_parts(0 - 1);
  if neg.len() != 3 { ok = false; } else {
    let n0: Int = neg[0];
    let n1: Int = neg[1];
    let n2: Int = neg[2];
    if n0 != 65535 { ok = false; }
    if n1 != 65535 { ok = false; }
    if n2 != 4294967295 { ok = false; }
  }
  return assert(ok, "offset join/parts: 0x9ABC1234, 64-bit high word, two's-complement -1");
}

fn t9() -> TestResult {
  let br = x86_idtr32_build(2047, 4194304);
  var ok = br.is_ok;
  if ok {
    let b: Vec[UInt8] = br.value;
    if !bytes_equal(b, hb("ff0700004000")) { ok = false; }
    if b.len() != 6 { ok = false; }
    let r = idtr_of(x86_idtr32_decode(&b, 0));
    if x86_idtr_limit(&r) != 2047 { ok = false; }
    if x86_idtr_base(&r) != 4194304 { ok = false; }
    if x86_idtr_long_mode(&r) { ok = false; }
    if x86_idtr_span(&r) != 2048 { ok = false; }
    if x86_idtr_entry_count(&r) != 256 { ok = false; }
  }
  let odd = set_bytes(zeros(6), 0, [0xF8, 0x07, 0x00, 0x00, 0x00, 0x00]);
  let r2 = idtr_of(x86_idtr32_decode(&odd, 0));
  if x86_idtr_entry_count(&r2) != -1 { ok = false; }
  if !err_idtr_is(x86_idtr32_decode(&zeros(5), 0), "interrupt: idtr32 block out of range at offset 0 (need 6 bytes, have 5)") { ok = false; }
  if !err_bytes_is(x86_idtr32_build(65536, 0), "interrupt: idtr32 limit out of range") { ok = false; }
  if !err_bytes_is(x86_idtr32_build(0, 4294967296), "interrupt: idtr32 base out of range") { ok = false; }
  return assert(ok, "IDTR32: canonical bytes, accessors, odd limit and error catalog");
}

fn t10() -> TestResult {
  let br = x86_idtr64_build(4095, 305419896);
  var ok = br.is_ok;
  if ok {
    let b: Vec[UInt8] = br.value;
    if b.len() != 10 { ok = false; }
    let r = idtr_of(x86_idtr64_decode(&b, 0));
    if x86_idtr_limit(&r) != 4095 { ok = false; }
    if x86_idtr_base(&r) != 305419896 { ok = false; }
    if !x86_idtr_long_mode(&r) { ok = false; }
    if x86_idtr_span(&r) != 4096 { ok = false; }
    if x86_idtr_entry_count(&r) != 256 { ok = false; }
  }
  let high = set_bytes(zeros(10), 0, [0xFF, 0x0F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
  let r2 = idtr_of(x86_idtr64_decode(&high, 0));
  if x86_idtr_base(&r2) != -1 { ok = false; }
  if x86_idtr_entry_count(&r2) != 256 { ok = false; }
  if !err_idtr_is(x86_idtr64_decode(&zeros(9), 0), "interrupt: idtr64 block out of range at offset 0 (need 10 bytes, have 9)") { ok = false; }
  if !err_bytes_is(x86_idtr64_build(65536, 0), "interrupt: idtr64 limit out of range") { ok = false; }
  if !err_bytes_is(x86_idtr64_build(0, -1), "interrupt: idtr64 base out of range") { ok = false; }
  return assert(ok, "IDTR64: round-trip, 64-bit high base bit pattern, odd limit and errors");
}

// --------------------------------------------------
//  Tests: GIC distributor
// --------------------------------------------------

fn t11() -> TestResult {
  let block = put_word(zeros(8), 0, 0x03, 0x00, 0x00, 0x00);
  let r = gicd_ctlr_decode(&block, 0);
  var ok = r.is_ok;
  if ok {
    let c: GicdCtlr = r.value;
    if !c.enable_grp0 { ok = false; }
    if !c.enable_grp1 { ok = false; }
    if c.enable_grp1s { ok = false; }
    if c.enable_grp1ns { ok = false; }
    if c.are_s { ok = false; }
    if c.are_ns { ok = false; }
    if c.disable_security { ok = false; }
    if c.nassgi_req { ok = false; }
    if c.rwp { ok = false; }
    if c.raw != 3 { ok = false; }
    if gicd_ctlr_enable_mask(&c) != 3 { ok = false; }
  }
  let full = put_word(zeros(8), 0, 0x7F, 0x01, 0x00, 0x80);
  let c2 = ctl_of(gicd_ctlr_decode(&full, 0));
  if !c2.enable_grp0 { ok = false; }
  if !c2.enable_grp1 { ok = false; }
  if !c2.enable_grp1s { ok = false; }
  if !c2.enable_grp1ns { ok = false; }
  if !c2.are_s { ok = false; }
  if !c2.are_ns { ok = false; }
  if !c2.disable_security { ok = false; }
  if !c2.nassgi_req { ok = false; }
  if !c2.rwp { ok = false; }
  if gicd_ctlr_reserved_bits(c2.raw) != 0 { ok = false; }
  if gicd_ctlr_enable_mask(&c2) != 15 { ok = false; }
  if gicd_ctlr_reserved_bits(0) != 0 { ok = false; }
  if gicd_ctlr_reserved_bits(128) != 128 { ok = false; }
  if gicd_ctlr_reserved_bits(512) != 512 { ok = false; }
  return assert(ok, "GICD_CTLR: enable/security/RWP fields and reserved-bit mask");
}

fn t12() -> TestResult {
  // bits 7:5 = 2 (3 CPUs), bit 10 SecurityExtn, bit 8 ESPI.
  let block = put_word(zeros(8), 0, 0x43, 0x05, 0x00, 0x00);
  let r = gicd_typer_decode(&block, 0);
  var ok = r.is_ok;
  if ok {
    let t: GicdTyper = r.value;
    if t.it_lines_number != 3 { ok = false; }
    if t.cpu_count != 3 { ok = false; }
    if !t.espi { ok = false; }
    if t.espi_range != 32 { ok = false; }
    if !t.security_extn { ok = false; }
    if t.mbis { ok = false; }
    if t.lspi { ok = false; }
    if t.max_interrupts != 128 { ok = false; }
    if gic_max_interrupts(t.raw) != 128 { ok = false; }
    if gic_max_spi_count(t.raw) != 96 { ok = false; }
    if gic_highest_valid_id(t.raw) != 127 { ok = false; }
    if gic_cpu_count(t.raw) != 3 { ok = false; }
    if !gic_has_security_extensions(t.raw) { ok = false; }
    if gic_has_lpis(t.raw) { ok = false; }
    if !gic_has_espis(t.raw) { ok = false; }
    if gic_espi_range(t.raw) != 32 { ok = false; }
    if gic_espi_max_id(t.raw) != 4127 { ok = false; }
    if !gic_irq_in_range(t.raw, 127) { ok = false; }
    if gic_irq_in_range(t.raw, 128) { ok = false; }
  }
  let lpi_block = put_word(zeros(8), 0, 0x43, 0x00, 0x03, 0x00);
  let t2 = typ_of(gicd_typer_decode(&lpi_block, 0));
  if !t2.mbis { ok = false; }
  if !t2.lspi { ok = false; }
  if t2.security_extn { ok = false; }
  if gic_has_mbis(t2.raw) != true { ok = false; }
  if gic_has_lpis(t2.raw) != true { ok = false; }
  if gic_max_interrupts(31) != 1020 { ok = false; }
  if gic_highest_valid_id(31) != 1019 { ok = false; }
  if gic_max_spi_count(31) != 988 { ok = false; }
  if gic_max_interrupts(0) != 32 { ok = false; }
  if gic_max_spi_count(0) != 0 { ok = false; }
  if gic_highest_valid_id(0) != 31 { ok = false; }
  // GICv3.1 ESPI range: b1 bit 8, b3 field 3 -> 4 blocks of 32.
  let espi = 31 + 256 + 24 * 16777216;
  if gic_has_espis(espi) != true { ok = false; }
  if gic_espi_range(espi) != 128 { ok = false; }
  if gic_espi_max_id(espi) != 4223 { ok = false; }
  if gic_espi_range(31) != 0 { ok = false; }
  if gic_espi_max_id(31) != -1 { ok = false; }
  let bad9 = put_word(zeros(8), 4, 0x43, 0x02, 0x00, 0x00);
  if !err_typ_is(gicd_typer_decode(&bad9, 4), "interrupt: distributor typer reserved bit 9 set invalid at offset 4") { ok = false; }
  if gicd_typer_reserved_bits(512) != 512 { ok = false; }
  if gicd_typer_reserved_bits(31) != 0 { ok = false; }
  return assert(ok, "GICD_TYPER: field decode, SPI/CPU math, 1020 cap, LSPI/MBIS/ESPI and bit-9 reject");
}

fn t13() -> TestResult {
  var block = zeros(0x900);
  block = patched(block, 0x100, 0x01);
  block = patched(block, 0x103, 0x80);
  block = patched(block, 0x104, 0x01);
  var ok = int_of(gicd_bitmap_offset(GICD_ISENABLER, 32)) == 256;
  if int_of(gicd_bitmap_offset(GICD_ISENABLER, 63)) != 256 { ok = false; }
  if int_of(gicd_bitmap_offset(GICD_ISENABLER, 64)) != 260 { ok = false; }
  if int_of(gicd_bitmap_offset(GICD_ICENABLER, 32)) != 384 { ok = false; }
  if int_of(gicd_bitmap_offset(GICD_IGROUPR, 0)) != 128 { ok = false; }
  if int_of(gicd_bitmap_offset(GICD_IGROUPR, 31)) != 128 { ok = false; }
  if int_of(gicd_bitmap_offset(GICD_IGROUPR, 32)) != 132 { ok = false; }
  if int_of(gicd_bitmap_offset(GICD_ISENABLER, 1019)) != 376 { ok = false; }
  if bool_of(gicd_bitmap_bit(&block, GICD_ISENABLER, 32)) != true { ok = false; }
  if bool_of(gicd_bitmap_bit(&block, GICD_ISENABLER, 33)) != false { ok = false; }
  if bool_of(gicd_bitmap_bit(&block, GICD_ISENABLER, 63)) != true { ok = false; }
  if bool_of(gicd_bitmap_bit(&block, GICD_ISENABLER, 64)) != true { ok = false; }
  if bool_of(gicd_bitmap_bit(&block, GICD_ICPENDR, 32)) != false { ok = false; }
  if !err_int_is(gicd_bitmap_offset(GICD_ISENABLER, 31), "interrupt: irq 31 is an SGI/PPI; bitmap base 256 covers SPIs only") { ok = false; }
  if !err_int_is(gicd_bitmap_offset(GICD_ISENABLER, 1020), "interrupt: irq 1020 outside the GICv2 range 0..1019") { ok = false; }
  if !err_int_is(gicd_bitmap_offset(132, 32), "interrupt: unknown distributor bitmap base 132") { ok = false; }
  if !err_bool_is(gicd_bitmap_bit(&zeros(0x102), GICD_ISENABLER, 32), "interrupt: distributor bitmap word out of range at offset 256 (need 4 bytes, have 258)") { ok = false; }
  if !err_bool_is(gicd_bitmap_bit(&zeros(0x100), GICD_ISENABLER, 32), "interrupt: distributor bitmap word out of range at offset 256 (need 4 bytes, have 256)") { ok = false; }
  return assert(ok, "bitmaps: word offsets (IGROUPR at 0, others at SPI 32), bit extraction and errors");
}

fn t14() -> TestResult {
  var block = zeros(0x900);
  block = patched(block, 0x80, 0x01);
  block = patched(block, 0x82, 0x01);
  block = patched(block, 0x84, 0x01);
  var ok = bool_of(gicd_group_bit(&block, 0)) == true;
  if bool_of(gicd_group_bit(&block, 16)) != true { ok = false; }
  if bool_of(gicd_group_bit(&block, 32)) != true { ok = false; }
  if bool_of(gicd_group_bit(&block, 1)) != false { ok = false; }
  if int_of(gicd_bitmap_word_count(GICD_IGROUPR, 31)) != 1 { ok = false; }
  if int_of(gicd_bitmap_word_count(GICD_IGROUPR, 32)) != 2 { ok = false; }
  if int_of(gicd_bitmap_word_count(GICD_ISENABLER, 63)) != 1 { ok = false; }
  if int_of(gicd_bitmap_word_count(GICD_ISENABLER, 64)) != 2 { ok = false; }
  if int_of(gicd_bitmap_word_count(GICD_ISENABLER, 1019)) != 31 { ok = false; }
  if int_of(gicd_bitmap_span(&block, GICD_ISENABLER, 31)) != 124 { ok = false; }
  if int_of(gicd_bitmap_span(&block, GICD_ISENABLER, 32)) != 128 { ok = false; }
  if int_of(gicd_bitmap_span(&block, GICD_IGROUPR, 32)) != 128 { ok = false; }
  if !err_int_is(gicd_bitmap_span(&block, GICD_ISENABLER, 33), "interrupt: impossible bitmap size 33 words at base 256") { ok = false; }
  if !err_int_is(gicd_bitmap_span(&block, GICD_ISENABLER, 0), "interrupt: impossible bitmap size 0 words at base 256") { ok = false; }
  if !err_int_is(gicd_bitmap_span(&block, 999, 1), "interrupt: unknown distributor bitmap base 999") { ok = false; }
  if !err_int_is(gicd_bitmap_span(&zeros(0x100), GICD_ISENABLER, 1), "interrupt: distributor bitmap block out of range at offset 256 (need 4 bytes, have 256)") { ok = false; }
  if !err_int_is(gicd_bitmap_word_count(GICD_ISENABLER, 31), "interrupt: irq 31 is an SGI/PPI; bitmap base 256 covers SPIs only") { ok = false; }
  return assert(ok, "group bit and bitmap sizing: word counts, spans, impossible sizes");
}

fn t15() -> TestResult {
  var block = zeros(0x900);
  block = patched(block, 1024, 0xFF);
  block = patched(block, 1057, 0xA0);
  var ok = int_of(gicd_priority_offset(0)) == 1024;
  if int_of(gicd_priority_offset(33)) != 1057 { ok = false; }
  if int_of(gicd_priority(&block, 0)) != 255 { ok = false; }
  if int_of(gicd_priority(&block, 33)) != 160 { ok = false; }
  if int_of(gicd_priority(&block, 1)) != 0 { ok = false; }
  if !err_int_is(gicd_priority_offset(1020), "interrupt: irq 1020 outside the GICv2 range 0..1019") { ok = false; }
  if !err_int_is(gicd_priority_offset(-1), "interrupt: irq -1 outside the GICv2 range 0..1019") { ok = false; }
  if !err_int_is(gicd_priority(&zeros(1024), 0), "interrupt: distributor priority byte out of range at offset 1024 (need 1 byte, have 1024)") { ok = false; }
  return assert(ok, "GICD_IPRIORITYR: offsets, 8-bit reads (>=128 widened) and errors");
}

fn t16() -> TestResult {
  var block = zeros(0x900);
  block = patched(block, 2080, 0x05);
  block = patched(block, 0x800, 0x01);
  var ok = int_of(gicd_target_offset(32)) == 2080;
  if int_of(gicd_target_offset(1019)) != 3067 { ok = false; }
  if gicd_target_writable(31) { ok = false; }
  if !gicd_target_writable(32) { ok = false; }
  let t = tgt_of(gicd_target(&block, 32));
  if t.irq != 32 { ok = false; }
  if t.targets != 5 { ok = false; }
  if !t.writable { ok = false; }
  let t0 = tgt_of(gicd_target(&block, 0));
  if t0.targets != 1 { ok = false; }
  if t0.writable { ok = false; }
  let t15 = tgt_of(gicd_target(&block, 15));
  if t15.writable { ok = false; }
  let t16 = tgt_of(gicd_target(&block, 16));
  if t16.writable { ok = false; }
  if !err_int_is(gicd_target_offset(1020), "interrupt: irq 1020 outside the GICv2 range 0..1019") { ok = false; }
  if !err_tgt_is(gicd_target(&zeros(2048), 0), "interrupt: distributor target byte out of range at offset 2048 (need 1 byte, have 2048)") { ok = false; }
  return assert(ok, "GICD_ITARGETSR: offsets, target bytes, SGI/PPI read-only rule");
}

// --------------------------------------------------
//  Tests: IRQ classification and GICv3 notes
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = str_eq(gic_irq_class(0), "SGI");
  if !str_eq(gic_irq_class(15), "SGI") { ok = false; }
  if !str_eq(gic_irq_class(16), "PPI") { ok = false; }
  if !str_eq(gic_irq_class(31), "PPI") { ok = false; }
  if !str_eq(gic_irq_class(32), "SPI") { ok = false; }
  if !str_eq(gic_irq_class(1019), "SPI") { ok = false; }
  if !str_eq(gic_irq_class(1020), "reserved") { ok = false; }
  if !str_eq(gic_irq_class(1023), "reserved") { ok = false; }
  if !str_eq(gic_irq_class(1024), "invalid") { ok = false; }
  if !str_eq(gic_irq_class(4095), "invalid") { ok = false; }
  if !str_eq(gic_irq_class(4096), "ESPI") { ok = false; }
  if !str_eq(gic_irq_class(5119), "ESPI") { ok = false; }
  if !str_eq(gic_irq_class(5120), "invalid") { ok = false; }
  if !str_eq(gic_irq_class(-1), "invalid") { ok = false; }
  if gic_is_sgi(15) != true { ok = false; }
  if gic_is_sgi(16) != false { ok = false; }
  if gic_is_ppi(15) != false { ok = false; }
  if gic_is_ppi(16) != true { ok = false; }
  if gic_is_ppi(31) != true { ok = false; }
  if gic_is_ppi(32) != false { ok = false; }
  if gic_is_spi(31) != false { ok = false; }
  if gic_is_spi(32) != true { ok = false; }
  if gic_is_spi(1019) != true { ok = false; }
  if gic_is_spi(1020) != false { ok = false; }
  if gic_is_espi(4095) != false { ok = false; }
  if gic_is_espi(4096) != true { ok = false; }
  if gic_is_espi(5119) != true { ok = false; }
  if gic_is_espi(5120) != false { ok = false; }
  if !str_eq(gic_espi_class(4096), "ESPI") { ok = false; }
  if !str_eq(gic_espi_class(4095), "invalid") { ok = false; }
  if !str_eq(gic_espi_class(5120), "invalid") { ok = false; }
  return assert(ok, "IRQ classification: boundaries 15/16/31/32/1019/1020/1023/4096/5119");
}

fn t18() -> TestResult {
  let block = put_word(zeros(16), 12, 0x85, 0x01, 0x00, 0x00);
  let r = gicd_typer2_decode(&block, 12);
  var ok = r.is_ok;
  if ok {
    let t: GicdTyper2 = r.value;
    if t.vid != 5 { ok = false; }
    if !t.vil { ok = false; }
    if !t.nassgi_cap { ok = false; }
    if t.raw != 389 { ok = false; }
  }
  let r2 = typ2_of(gicd_typer2_decode(&put_word(zeros(16), 12, 0x03, 0x00, 0x00, 0x00), 12));
  if r2.vid != 3 { ok = false; }
  if r2.vil { ok = false; }
  if r2.nassgi_cap { ok = false; }
  if !err_typ2_is(gicd_typer2_decode(&zeros(14), 12), "interrupt: distributor register out of range at offset 12 (need 4 bytes, have 14)") { ok = false; }
  if GICD_TYPER2 != 12 { ok = false; }
  if GICD_TYPER != 4 { ok = false; }
  if GICD_CTLR != 0 { ok = false; }
  return assert(ok, "GICD_TYPER2 note-level decode: VID/VIL/nASSGIcap and block errors");
}

fn t19() -> TestResult {
  var ok = str_eq(x86_vector_name(0), "DE");
  if !str_eq(x86_vector_name(1), "DB") { ok = false; }
  if !str_eq(x86_vector_name(2), "NMI") { ok = false; }
  if !str_eq(x86_vector_name(3), "BP") { ok = false; }
  if !str_eq(x86_vector_name(4), "OF") { ok = false; }
  if !str_eq(x86_vector_name(5), "BR") { ok = false; }
  if !str_eq(x86_vector_name(6), "UD") { ok = false; }
  if !str_eq(x86_vector_name(7), "NM") { ok = false; }
  if !str_eq(x86_vector_name(8), "DF") { ok = false; }
  if !str_eq(x86_vector_name(9), "CSO") { ok = false; }
  if !str_eq(x86_vector_name(10), "TS") { ok = false; }
  if !str_eq(x86_vector_name(11), "NP") { ok = false; }
  if !str_eq(x86_vector_name(12), "SS") { ok = false; }
  if !str_eq(x86_vector_name(13), "GP") { ok = false; }
  if !str_eq(x86_vector_name(14), "PF") { ok = false; }
  if !str_eq(x86_vector_name(15), "RESERVED") { ok = false; }
  if !str_eq(x86_vector_name(16), "MF") { ok = false; }
  if !str_eq(x86_vector_name(17), "AC") { ok = false; }
  if !str_eq(x86_vector_name(18), "MC") { ok = false; }
  if !str_eq(x86_vector_name(19), "XM") { ok = false; }
  if !str_eq(x86_vector_name(20), "VE") { ok = false; }
  if !str_eq(x86_vector_name(21), "CP") { ok = false; }
  if !str_eq(x86_vector_name(22), "RESERVED") { ok = false; }
  if !str_eq(x86_vector_name(31), "RESERVED") { ok = false; }
  if !str_eq(x86_vector_name(32), "USER") { ok = false; }
  if !str_eq(x86_vector_name(255), "USER") { ok = false; }
  if !str_eq(x86_vector_name(-1), "") { ok = false; }
  if !str_eq(x86_vector_name(256), "") { ok = false; }
  if !str_eq(x86_vector_class(0), "exception") { ok = false; }
  if !str_eq(x86_vector_class(21), "exception") { ok = false; }
  if !str_eq(x86_vector_class(22), "reserved") { ok = false; }
  if !str_eq(x86_vector_class(32), "user") { ok = false; }
  if !str_eq(x86_vector_class(256), "invalid") { ok = false; }
  if !x86_vector_has_error_code(8) { ok = false; }
  if !x86_vector_has_error_code(10) { ok = false; }
  if !x86_vector_has_error_code(14) { ok = false; }
  if !x86_vector_has_error_code(17) { ok = false; }
  if !x86_vector_has_error_code(21) { ok = false; }
  if x86_vector_has_error_code(0) { ok = false; }
  if x86_vector_has_error_code(7) { ok = false; }
  if x86_vector_has_error_code(9) { ok = false; }
  if x86_vector_has_error_code(15) { ok = false; }
  if x86_vector_has_error_code(16) { ok = false; }
  return assert(ok, "x86 vector table: names, classes and error-code classification");
}

fn t20() -> TestResult {
  var ok = X86_IDT_GATE32_LEN == 8;
  if X86_IDT_GATE64_LEN != 16 { ok = false; }
  if X86_IDTR32_LEN != 6 { ok = false; }
  if X86_IDTR64_LEN != 10 { ok = false; }
  if X86_IDT_VECTOR_COUNT != 256 { ok = false; }
  if X86_IDT_TYPE_INTERRUPT != 14 { ok = false; }
  if X86_IDT_TYPE_TRAP != 15 { ok = false; }
  if GIC_FIRST_SPI != 32 { ok = false; }
  if GIC_MAX_INTID != 1019 { ok = false; }
  if GIC_SPURIOUS_INTID != 1022 { ok = false; }
  if ESPI_BASE_INTID != 4096 { ok = false; }
  if GIC_ESPI_COUNT != 1024 { ok = false; }
  if GIC_MAX_BITMAP_WORDS != 32 { ok = false; }
  if GICD_SIZE != 65536 { ok = false; }
  if GICD_ISENABLER != 256 { ok = false; }
  if GICD_ICENABLER != 384 { ok = false; }
  if GICD_ISPENDR != 512 { ok = false; }
  if GICD_ICPENDR != 640 { ok = false; }
  if GICD_IPRIORITYR != 1024 { ok = false; }
  if GICD_ITARGETSR != 2048 { ok = false; }
  // A present gate with a NULL selector is not usable.
  let null_sel = gate32_fixture(0x1234, 0x0000, 0x00, 0xAE, 0x9ABC);
  let g = gate_of(x86_idt_gate32_decode(&null_sel, 0));
  if x86_idt_gate_valid(&g) { ok = false; }
  if !x86_idt_gate_present(&g) { ok = false; }
  return assert(ok, "public constants and NULL-selector gate validation");
}

fn main() -> Int {
  io.println("=== xiom.interrupt conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.interrupt: all tests passed");
  } else {
    io.println("xiom.interrupt: tests failed");
  }
  return failed;
}
