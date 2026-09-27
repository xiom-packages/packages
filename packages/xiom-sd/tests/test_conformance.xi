// XIOM -- xiom.sd conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented SD/MMC register layouts and framing against:
//   * real published register images (SanDisk Ultra II 1GB CID, SanDisk
//     32GB and Kingston 2GB CSDs, the non-conforming SanDisk Ultra II
//     CSD whose reserved bits [30:29] are set);
//   * synthetic 16-byte CID/CSD images built in-test bit by bit with a
//     pinned expected capacity for every variant;
//   * a test-local CRC7 implementation written as a serial 7-bit LFSR
//     (the module uses an 8-bit byte accumulator), so a shared bug in the
//     module CRC cannot pass unnoticed.
//
// No Str value is compared with `==` (BUG 17 discipline): string equality
// goes through compare.str_compare. Every Vec[UInt8] element read is bound
// to a typed local and widened with `& 0xFF`.

module sd_tests
use xiom.io; use xiom.test;
use xiom.sd;
use xiom.string.compare;
use xiom.convert;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/sd.xi)
// --------------------------------------------------

// Bytes for a hex string; "" on malformed input (the test then fails on
// the byte comparison). Lowercase or uppercase digits both parse.
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

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn copy_first(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn clone_reg(v: &Vec[UInt8]) -> Vec[UInt8] {
  return copy_first(v, v.len());
}

fn with_tail(v: &Vec[UInt8], extra: Int, n: Int) -> Vec[UInt8] {
  var out = clone_reg(v);
  var i = 0;
  while i < n {
    out.push(extra as UInt8);
    i = i + 1;
  }
  return out;
}

fn set_byte(v: &mut Vec[UInt8], pos: Int, val: Int) {
  v[pos] = val as UInt8;
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn bool_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  if want {
    return v;
  }
  return !v;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
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

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
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

fn err_mdt_is(r: Result[SdMdt, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_cid_is(r: Result[SdCid, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_csd_is(r: Result[SdCsd, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_ocr_is(r: Result[SdOcr, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

// --------------------------------------------------
//  Synthetic register construction and an independent CRC7
// --------------------------------------------------

// 2^k by repeated multiplication (no shift).
fn rp2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Independent CRC7: serial 7-bit LFSR over the MSB-first message bits,
// feedback = register MSB XOR message bit, polynomial x^3 + x^0 applied
// on feedback. This formulation shares no code with the module's 8-bit
// byte accumulator.
fn ref_crc7(data: &Vec[UInt8], n: Int) -> Int {
  var r = 0;
  var i = 0;
  while i < n {
    let b: Int = (data[i] as Int) & 0xFF;
    var j = 7;
    while j >= 0 {
      let m = (b / rp2(j)) % 2;
      let top = (r / 64) % 2;
      var fb = 0;
      if top != m {
        fb = 1;
      }
      r = (r * 2) % 128;
      if fb == 1 {
        r = r ^ 9;
      }
      j = j - 1;
    }
    i = i + 1;
  }
  return r;
}

// Set register field [hi:lo] (register bit 127 = MSB of byte 0) of a
// 16-byte image to `val` by adjusting single bits.
fn set_field(v: &mut Vec[UInt8], hi: Int, lo: Int, val: Int) {
  let n = hi - lo + 1;
  var i = 0;
  while i < n {
    let bitpos = hi - i;
    let byte = (127 - bitpos) / 8;
    let mask = rp2(bitpos % 8);
    let cur: Int = (v[byte] as Int) & 0xFF;
    let has = (cur / mask) % 2;
    let nb = (val / rp2(n - 1 - i)) % 2;
    if nb == 1 {
      if has == 0 {
        let nv = cur + mask;
        v[byte] = nv as UInt8;
      }
    } else {
      if has == 1 {
        let nv = cur - mask;
        v[byte] = nv as UInt8;
      }
    }
    i = i + 1;
  }
}

// A zeroed 16-byte register image.
fn new_reg() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// Copy of `v` with field [hi:lo] replaced by `val` (CRC deliberately left
// stale so error paths can be exercised).
fn mutated(v: &Vec[UInt8], hi: Int, lo: Int, val: Int) -> Vec[UInt8] {
  var c = clone_reg(v);
  set_field(&mut c, hi, lo, val);
  return c;
}

// Seal a 15-byte register body: copy the first 15 bytes into a fresh
// vector and append the CRC/end-bit byte. Returning a fresh vector (never
// the borrowed body) keeps v0.61.3 from lowering the return to a stale
// borrow of the input.
fn seal_reg(v: &Vec[UInt8], crc: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 15 {
    out.push(v[i]);
    i = i + 1;
  }
  out.push((crc * 2 + 1) as UInt8);
  return out;
}

// Synthetic CID: MID 27, OID "SD", PNM "KX256", PRV 0x25 (2.5),
// PSN 0x12345678, manufacturing date 2026-09. Pinned image:
// 1b53444b58323536251234567801a985 (CRC7 0x42).
fn synth_cid() -> Vec[UInt8] {
  var v = new_reg();
  set_field(&mut v, 127, 120, 27);
  set_field(&mut v, 119, 112, 83);
  set_field(&mut v, 111, 104, 68);
  set_field(&mut v, 103, 96, 75);
  set_field(&mut v, 95, 88, 88);
  set_field(&mut v, 87, 80, 50);
  set_field(&mut v, 79, 72, 53);
  set_field(&mut v, 71, 64, 54);
  set_field(&mut v, 63, 56, 37);
  set_field(&mut v, 55, 24, 305419896);
  set_field(&mut v, 19, 12, 26);
  set_field(&mut v, 11, 8, 9);
  let crc = ref_crc7(&v, 15);
  return seal_reg(&v, crc);
}

// Synthetic CSD v1.0: TAAC 0x2D (2.0 x 100us = 200000 ns), TRAN_SPEED
// 0x32 (25 Mbit/s), C_SIZE 511, C_SIZE_MULT 3, READ_BL_LEN 9,
// ERASE_BLK_EN 1. Capacity (511+1) * 2^5 * 2^9 = 8388608 bytes. Pinned
// image: 002d00325b59807fc001ff8012400077 (CRC7 0x3B).
fn synth_csd_v1() -> Vec[UInt8] {
  var v = new_reg();
  set_field(&mut v, 127, 126, 0);
  set_field(&mut v, 119, 112, 45);
  set_field(&mut v, 111, 104, 0);
  set_field(&mut v, 103, 96, 50);
  set_field(&mut v, 95, 84, 1461);
  set_field(&mut v, 83, 80, 9);
  set_field(&mut v, 79, 79, 1);
  set_field(&mut v, 78, 78, 0);
  set_field(&mut v, 77, 77, 0);
  set_field(&mut v, 76, 76, 0);
  set_field(&mut v, 73, 62, 511);
  set_field(&mut v, 49, 47, 3);
  set_field(&mut v, 46, 46, 1);
  set_field(&mut v, 45, 39, 127);
  set_field(&mut v, 38, 32, 0);
  set_field(&mut v, 31, 31, 0);
  set_field(&mut v, 28, 26, 4);
  set_field(&mut v, 25, 22, 9);
  set_field(&mut v, 21, 21, 0);
  let crc = ref_crc7(&v, 15);
  return seal_reg(&v, crc);
}

// Synthetic CSD v2.0: TAAC 0x0E (1 ms), TRAN_SPEED 0x32, C_SIZE 15159.
// Capacity (15159+1) * 512 KiB = 7948206080 bytes. Pinned image:
// 400e00325b5900003b377f8012400009 (CRC7 0x04).
fn synth_csd_v2() -> Vec[UInt8] {
  var v = new_reg();
  set_field(&mut v, 127, 126, 1);
  set_field(&mut v, 119, 112, 14);
  set_field(&mut v, 111, 104, 0);
  set_field(&mut v, 103, 96, 50);
  set_field(&mut v, 95, 84, 1461);
  set_field(&mut v, 83, 80, 9);
  set_field(&mut v, 76, 76, 0);
  set_field(&mut v, 69, 48, 15159);
  set_field(&mut v, 46, 46, 1);
  set_field(&mut v, 45, 39, 127);
  set_field(&mut v, 38, 32, 0);
  set_field(&mut v, 31, 31, 0);
  set_field(&mut v, 28, 26, 4);
  set_field(&mut v, 25, 22, 9);
  set_field(&mut v, 21, 21, 0);
  let crc = ref_crc7(&v, 15);
  return seal_reg(&v, crc);
}

// --------------------------------------------------
//  CID tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let b = hb("035344535530314780401c751300637d");
  let r = sd_cid_parse(&b);
  if !r.is_ok {
    return assert(false, "real CID must parse");
  }
  let c: SdCid = r.value;
  if c.manufacturer_id != 3 { ok = false; }
  if !str_eq(c.oem_id, "SD") { ok = false; }
  if !str_eq(c.product_name, "SU01G") { ok = false; }
  if c.revision_major != 8 { ok = false; }
  if c.revision_minor != 0 { ok = false; }
  if c.serial != 1075606803 { ok = false; }
  if c.mdt_year != 2006 { ok = false; }
  if c.mdt_month != 3 { ok = false; }
  if c.crc7 != 62 { ok = false; }
  if !int_is(sd_cid_crc(&b), 62) { ok = false; }
  if !int_is(sd_cid_crc_stored(&b), 62) { ok = false; }
  if !int_is(sd_cid_revision(&b), 128) { ok = false; }
  return assert(ok, "cid real register: SanDisk Ultra II 1GB fields, crc 0x3E");
}

fn t2() -> TestResult {
  var ok = true;
  let b = synth_cid();
  if !bytes_equal(b, hb("1b53444b58323536251234567801a985")) { ok = false; }
  let r = sd_cid_parse(&b);
  if !r.is_ok {
    return assert(false, "synthetic CID must parse");
  }
  let c: SdCid = r.value;
  if c.manufacturer_id != 27 { ok = false; }
  if !str_eq(c.oem_id, "SD") { ok = false; }
  if !str_eq(c.product_name, "KX256") { ok = false; }
  if c.revision_major != 2 { ok = false; }
  if c.revision_minor != 5 { ok = false; }
  if c.serial != 305419896 { ok = false; }
  if c.mdt_year != 2026 { ok = false; }
  if c.mdt_month != 9 { ok = false; }
  if c.crc7 != 66 { ok = false; }
  return assert(ok, "cid synthetic: bit-built image, pinned bytes and fields");
}

fn t3() -> TestResult {
  var ok = true;
  let b = synth_cid();
  if !int_is(sd_cid_manufacturer_id(&b), 27) { ok = false; }
  if !int_is(sd_cid_revision(&b), 37) { ok = false; }
  if !int_is(sd_cid_serial(&b), 305419896) { ok = false; }
  let oidr = sd_cid_oem_id(&b);
  if !oidr.is_ok { ok = false; } else {
    let oid: Str = oidr.value;
    if !str_eq(oid, "SD") { ok = false; }
  }
  let pnmr = sd_cid_product_name(&b);
  if !pnmr.is_ok { ok = false; } else {
    let pnm: Str = pnmr.value;
    if !str_eq(pnm, "KX256") { ok = false; }
  }
  let mdr = sd_cid_manufacturing_date(&b);
  if !mdr.is_ok { ok = false; } else {
    let m: SdMdt = mdr.value;
    if m.year != 2026 { ok = false; }
    if m.month != 9 { ok = false; }
  }
  return assert(ok, "cid accessors: every field agrees with the parsed struct");
}

fn t4() -> TestResult {
  var ok = true;
  let b = synth_cid();
  let r1 = mutated(&b, 23, 20, 1);
  if !err_cid_is(sd_cid_parse(&r1), "sd.cid: reserved bits [23:20] must be zero") { ok = false; }
  let r2 = mutated(&b, 0, 0, 0);
  if !err_cid_is(sd_cid_parse(&r2), "sd.cid: end bit 0 must be 1") { ok = false; }
  let r3 = mutated(&b, 11, 8, 13);
  if !err_cid_is(sd_cid_parse(&r3), "sd.cid: manufacturing month 13 out of range 1..12") { ok = false; }
  let r4 = mutated(&b, 11, 8, 0);
  if !err_cid_is(sd_cid_parse(&r4), "sd.cid: manufacturing month 0 out of range 1..12") { ok = false; }
  if !err_mdt_is(sd_cid_manufacturing_date(&r3), "sd.cid: manufacturing month 13 out of range 1..12") { ok = false; }
  return assert(ok, "cid reserved bits, end bit and manufacturing month errors");
}

fn t5() -> TestResult {
  var ok = true;
  let b = synth_cid();
  let r1 = mutated(&b, 119, 112, 31);
  if !err_cid_is(sd_cid_parse(&r1), "sd.cid: oem id byte at offset 1 is not printable (value 31)") { ok = false; }
  if !err_str_is(sd_cid_oem_id(&r1), "sd.cid: oem id byte at offset 1 is not printable (value 31)") { ok = false; }
  let r2 = mutated(&b, 87, 80, 127);
  if !err_cid_is(sd_cid_parse(&r2), "sd.cid: product name byte at offset 5 is not printable (value 127)") { ok = false; }
  if !err_str_is(sd_cid_product_name(&r2), "sd.cid: product name byte at offset 5 is not printable (value 127)") { ok = false; }
  let short = copy_first(&b, 15);
  let long = with_tail(&b, 0, 1);
  if !err_cid_is(sd_cid_parse(&short), "sd.cid: register needs 16 bytes, have 15") { ok = false; }
  if !err_cid_is(sd_cid_parse(&long), "sd.cid: register needs 16 bytes, have 17") { ok = false; }
  if !err_int_is(sd_cid_crc(&short), "sd.cid: register needs 16 bytes, have 15") { ok = false; }
  if !err_int_is(sd_cid_serial(&long), "sd.cid: register needs 16 bytes, have 17") { ok = false; }
  return assert(ok, "cid printable validation with offsets and length errors");
}

fn t6() -> TestResult {
  var ok = true;
  let b = synth_cid();
  let bad = mutated(&b, 24, 24, 1);
  let head = copy_first(&bad, 15);
  let comp = ref_crc7(&head, 15);
  let stored = 66;
  let want = "sd.cid: crc7 mismatch: stored " + convert.int_to_string(stored) + ", computed " + convert.int_to_string(comp);
  if !err_cid_is(sd_cid_parse(&bad), want) { ok = false; }
  let bad2 = mutated(&b, 7, 1, 0);
  let head2 = copy_first(&bad2, 15);
  let comp2 = ref_crc7(&head2, 15);
  let want2 = "sd.cid: crc7 mismatch: stored " + convert.int_to_string(0) + ", computed " + convert.int_to_string(comp2);
  if !err_cid_is(sd_cid_parse(&bad2), want2) { ok = false; }
  return assert(ok, "cid crc7 mismatch: stored and computed values reported");
}

// --------------------------------------------------
//  CSD tests
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = true;
  let b = hb("400e00325b590000edc87f800a4040c3");
  let r = sd_csd_parse(&b);
  if !r.is_ok {
    return assert(false, "real SDHC CSD must parse");
  }
  let c: SdCsd = r.value;
  if c.structure != 1 { ok = false; }
  if c.c_size != 60872 { ok = false; }
  if c.c_size_mult != 0 { ok = false; }
  if c.capacity_bytes != 31914983424 { ok = false; }
  if c.read_bl_len != 9 { ok = false; }
  if c.read_bl_len_bytes != 512 { ok = false; }
  if c.taac != 14 { ok = false; }
  if c.taac_ns != 1000000 { ok = false; }
  if c.nsac != 0 { ok = false; }
  if c.tran_speed != 50 { ok = false; }
  if c.tran_speed_bps != 25000000 { ok = false; }
  if !c.erase_blk_en { ok = false; }
  if c.erase_unit_bytes != 512 { ok = false; }
  if c.dsr_imp { ok = false; }
  if c.crc7 != 97 { ok = false; }
  if !int_is(sd_csd_capacity_bytes(&b), 31914983424) { ok = false; }
  if !int_is(sd_csd_c_size(&b), 60872) { ok = false; }
  if !int_is(sd_csd_crc(&b), 97) { ok = false; }
  if !int_is(sd_csd_crc_stored(&b), 97) { ok = false; }
  if !int_is(sd_csd_c_size_mult(&b), 0) { ok = false; }
  if !int_is(sd_csd_read_bl_len(&b), 9) { ok = false; }
  if !int_is(sd_csd_write_bl_len(&b), 9) { ok = false; }
  if !bool_is(sd_csd_dsr_imp(&b), false) { ok = false; }
  return assert(ok, "csd v2 real SanDisk 32GB: 31914983424-byte capacity, crc 0x61");
}

fn t8() -> TestResult {
  var ok = true;
  let b = hb("002d00325b5a83d5fefbff80168000cf");
  let r = sd_csd_parse(&b);
  if !r.is_ok {
    return assert(false, "real SDSC CSD must parse");
  }
  let c: SdCsd = r.value;
  if c.structure != 0 { ok = false; }
  if c.c_size != 3927 { ok = false; }
  if c.c_size_mult != 7 { ok = false; }
  if c.capacity_bytes != 2059403264 { ok = false; }
  if c.read_bl_len != 10 { ok = false; }
  if c.write_bl_len != 10 { ok = false; }
  if c.taac != 45 { ok = false; }
  if c.taac_ns != 200000 { ok = false; }
  if c.nsac_ns != 0 { ok = false; }
  if c.tran_speed_bps != 25000000 { ok = false; }
  if c.ccc != 1461 { ok = false; }
  if !c.erase_blk_en { ok = false; }
  if c.erase_unit_bytes != 512 { ok = false; }
  if c.crc7 != 103 { ok = false; }
  if !int_is(sd_csd_capacity_bytes(&b), 2059403264) { ok = false; }
  if !int_is(sd_csd_taac(&b), 45) { ok = false; }
  if !int_is(sd_csd_nsac(&b), 0) { ok = false; }
  if !int_is(sd_csd_tran_speed(&b), 50) { ok = false; }
  if !int_is(sd_csd_read_bl_len(&b), 10) { ok = false; }
  if !int_is(sd_csd_write_bl_len(&b), 10) { ok = false; }
  if !int_is(sd_csd_c_size_mult(&b), 7) { ok = false; }
  if !int_is(sd_csd_crc_stored(&b), 103) { ok = false; }
  if !bool_is(sd_csd_dsr_imp(&b), false) { ok = false; }
  return assert(ok, "csd v1 real Kingston 2GB: (C_SIZE+1)*2^9*2^10 formula, crc 0x67");
}

fn t9() -> TestResult {
  var ok = true;
  let b = synth_csd_v1();
  if !bytes_equal(b, hb("002d00325b59807fc001ff8012400077")) { ok = false; }
  let r = sd_csd_parse(&b);
  if !r.is_ok {
    return assert(false, "synthetic CSD v1 must parse");
  }
  let c: SdCsd = r.value;
  if c.structure != 0 { ok = false; }
  if c.capacity_bytes != 8388608 { ok = false; }
  if c.c_size != 511 { ok = false; }
  if c.c_size_mult != 3 { ok = false; }
  if c.read_bl_len != 9 { ok = false; }
  if !c.read_bl_partial { ok = false; }
  if !c.erase_blk_en { ok = false; }
  if c.erase_unit_bytes != 512 { ok = false; }
  if c.taac_ns != 200000 { ok = false; }
  if c.nsac_ns != 0 { ok = false; }
  if c.tran_speed_bps != 25000000 { ok = false; }
  if c.crc7 != 59 { ok = false; }
  let m1 = mutated(&b, 46, 46, 0);
  let m2 = mutated(&m1, 45, 39, 31);
  let m3 = mutated(&m2, 25, 22, 10);
  if !int_is(sd_csd_erase_unit_bytes(&m3), 32768) { ok = false; }
  if !bool_is(sd_csd_erase_blk_en(&m3), false) { ok = false; }
  return assert(ok, "csd v1 synthetic: pinned image, capacity 8388608, sector erase unit");
}

fn t10() -> TestResult {
  var ok = true;
  let b = synth_csd_v2();
  if !bytes_equal(b, hb("400e00325b5900003b377f8012400009")) { ok = false; }
  let r = sd_csd_parse(&b);
  if !r.is_ok {
    return assert(false, "synthetic CSD v2 must parse");
  }
  let c: SdCsd = r.value;
  if c.structure != 1 { ok = false; }
  if c.capacity_bytes != 7948206080 { ok = false; }
  if c.c_size != 15159 { ok = false; }
  if c.c_size_mult != 0 { ok = false; }
  if c.crc7 != 4 { ok = false; }
  let minv = mutated(&b, 69, 48, 0);
  if !int_is(sd_csd_capacity_bytes(&minv), 524288) { ok = false; }
  let maxv = mutated(&b, 69, 48, 4194303);
  if !int_is(sd_csd_capacity_bytes(&maxv), 2199023255552) { ok = false; }
  let noen = mutated(&b, 46, 46, 0);
  if !int_is(sd_csd_erase_unit_bytes(&noen), 512) { ok = false; }
  let v1min = mutated(&synth_csd_v1(), 73, 62, 0);
  let v1min2 = mutated(&v1min, 49, 47, 0);
  if !int_is(sd_csd_capacity_bytes(&v1min2), 2048) { ok = false; }
  let v1max = mutated(&synth_csd_v1(), 73, 62, 4095);
  let v1max2 = mutated(&v1max, 49, 47, 7);
  let v1max3 = mutated(&v1max2, 83, 80, 11);
  if !int_is(sd_csd_capacity_bytes(&v1max3), 4294967296) { ok = false; }
  return assert(ok, "csd v2 synthetic and capacity edges for both structures");
}

fn t11() -> TestResult {
  var ok = true;
  let r1 = hb("400e00325b590000edc87f800a4040c3");
  let r2 = hb("002d00325b5a83d5fefbff80168000cf");
  if !int_is(sd_csd_structure(&r1), 1) { ok = false; }
  if !int_is(sd_csd_structure(&r2), 0) { ok = false; }
  if !str_eq(sd_csd_structure_label(0), "1.0") { ok = false; }
  if !str_eq(sd_csd_structure_label(1), "2.0") { ok = false; }
  if !str_eq(sd_csd_structure_label(2), "3.0") { ok = false; }
  if !str_eq(sd_csd_structure_label(3), "reserved") { ok = false; }
  let b = synth_csd_v2();
  let v3 = mutated(&b, 127, 126, 2);
  if !err_csd_is(sd_csd_parse(&v3), "sd.csd: CSD structure value 2 (v3.0) is not supported") { ok = false; }
  if !err_int_is(sd_csd_capacity_bytes(&v3), "sd.csd: CSD structure value 2 (v3.0) is not supported") { ok = false; }
  if !int_is(sd_csd_structure(&v3), 2) { ok = false; }
  let v4 = mutated(&b, 127, 126, 3);
  if !err_csd_is(sd_csd_parse(&v4), "sd.csd: reserved CSD structure value 3") { ok = false; }
  if !err_int_is(sd_csd_capacity_bytes(&v4), "sd.csd: reserved CSD structure value 3") { ok = false; }
  if !err_int_is(sd_csd_c_size(&v4), "sd.csd: reserved CSD structure value 3") { ok = false; }
  if !err_int_is(sd_csd_c_size(&v3), "sd.csd: CSD structure value 2 (v3.0) is not supported") { ok = false; }
  return assert(ok, "csd structure detection: labels, v3.0 unsupported, value 3 reserved");
}

fn t12() -> TestResult {
  var ok = true;
  let v1 = synth_csd_v1();
  let v2 = synth_csd_v2();
  if !err_csd_is(sd_csd_parse(&mutated(&v1, 125, 120, 1)), "sd.csd: reserved bits [125:120] must be zero") { ok = false; }
  if !err_csd_is(sd_csd_parse(&mutated(&v1, 75, 74, 3)), "sd.csd: reserved bits [75:74] must be zero") { ok = false; }
  if !err_csd_is(sd_csd_parse(&mutated(&v2, 75, 70, 1)), "sd.csd: reserved bits [75:70] must be zero") { ok = false; }
  if !err_csd_is(sd_csd_parse(&mutated(&v2, 47, 47, 1)), "sd.csd: reserved bits [47] must be zero") { ok = false; }
  if !err_csd_is(sd_csd_parse(&mutated(&v2, 30, 29, 2)), "sd.csd: reserved bits [30:29] must be zero") { ok = false; }
  if !err_csd_is(sd_csd_parse(&mutated(&v1, 20, 16, 1)), "sd.csd: reserved bits [20:16] must be zero") { ok = false; }
  if !err_csd_is(sd_csd_parse(&mutated(&v1, 9, 8, 1)), "sd.csd: reserved bits [9:8] must be zero") { ok = false; }
  // Real SanDisk Ultra II 1GB CSD sets reserved bits [30:29] (bit 30): the
  // spec enforcement must flag this non-conforming register.
  let ultra = hb("002600325f5983c8addbcfffd24040a5");
  if !err_csd_is(sd_csd_parse(&ultra), "sd.csd: reserved bits [30:29] must be zero") { ok = false; }
  return assert(ok, "csd reserved bit enforcement, including a real non-conforming card");
}

fn t13() -> TestResult {
  var ok = true;
  let v1 = synth_csd_v1();
  if !err_csd_is(sd_csd_parse(&mutated(&v1, 0, 0, 0)), "sd.csd: end bit 0 must be 1") { ok = false; }
  if !err_csd_is(sd_csd_parse(&mutated(&v1, 83, 80, 8)), "sd.csd: READ_BL_LEN 8 is reserved (valid 9..11)") { ok = false; }
  if !err_int_is(sd_csd_capacity_bytes(&mutated(&v1, 83, 80, 8)), "sd.csd: READ_BL_LEN 8 is reserved (valid 9..11)") { ok = false; }
  if !err_csd_is(sd_csd_parse(&mutated(&v1, 25, 22, 12)), "sd.csd: WRITE_BL_LEN 12 is reserved (valid 9..11)") { ok = false; }
  let bad = mutated(&v1, 95, 84, 1);
  let head = copy_first(&bad, 15);
  let comp = ref_crc7(&head, 15);
  let want = "sd.csd: crc7 mismatch: stored " + convert.int_to_string(59) + ", computed " + convert.int_to_string(comp);
  if !err_csd_is(sd_csd_parse(&bad), want) { ok = false; }
  let short = copy_first(&v1, 15);
  if !err_csd_is(sd_csd_parse(&short), "sd.csd: register needs 16 bytes, have 15") { ok = false; }
  return assert(ok, "csd end bit, block length and crc7 mismatch errors");
}

// --------------------------------------------------
//  TAAC / NSAC / TRAN_SPEED decoders
// --------------------------------------------------

fn t14() -> TestResult {
  var ok = true;
  if !int_is(sd_taac_ns(14), 1000000) { ok = false; }
  if !int_is(sd_taac_ns(45), 200000) { ok = false; }
  if !int_is(sd_taac_ns(42), 200) { ok = false; }
  if !int_is(sd_taac_ns(26), 130) { ok = false; }
  if !int_is(sd_taac_ns(119), 70000000) { ok = false; }
  if !int_is(sd_taac_ns(127), 80000000) { ok = false; }
  if !err_int_is(sd_taac_ns(0), "sd.taac: time value 0 is reserved") { ok = false; }
  if !err_int_is(sd_taac_ns(7), "sd.taac: time value 0 is reserved") { ok = false; }
  if !err_int_is(sd_taac_ns(128), "sd.taac: value 128 has reserved bit 7 set") { ok = false; }
  if !err_int_is(sd_taac_ns(256), "sd.taac: value 256 out of range 0..255") { ok = false; }
  if !err_int_is(sd_taac_ns(-1), "sd.taac: value -1 out of range 0..255") { ok = false; }
  return assert(ok, "taac decode: time value table, time unit table, reserved codes");
}

fn t15() -> TestResult {
  var ok = true;
  if !int_is(sd_nsac_ns(0), 0) { ok = false; }
  if !int_is(sd_nsac_ns(1), 100) { ok = false; }
  if !int_is(sd_nsac_ns(255), 25500) { ok = false; }
  if !err_int_is(sd_nsac_ns(256), "sd.nsac: value 256 out of range 0..255") { ok = false; }
  if !err_int_is(sd_nsac_ns(-1), "sd.nsac: value -1 out of range 0..255") { ok = false; }
  if !int_is(sd_tran_speed_bps(50), 25000000) { ok = false; }
  if !int_is(sd_tran_speed_bps(90), 50000000) { ok = false; }
  if !int_is(sd_tran_speed_bps(11), 100000000) { ok = false; }
  if !int_is(sd_tran_speed_bps(42), 20000000) { ok = false; }
  if !int_is(sd_tran_speed_bps(96), 550000) { ok = false; }
  if !err_int_is(sd_tran_speed_bps(0), "sd.transpeed: time value 0 is reserved") { ok = false; }
  if !err_int_is(sd_tran_speed_bps(36), "sd.transpeed: transfer rate unit 4 is reserved") { ok = false; }
  if !err_int_is(sd_tran_speed_bps(128), "sd.transpeed: value 128 has reserved bit 7 set") { ok = false; }
  if !err_int_is(sd_tran_speed_bps(256), "sd.transpeed: value 256 out of range 0..255") { ok = false; }
  return assert(ok, "nsac and tran_speed decode: units, reserved codes, ranges");
}

// --------------------------------------------------
//  OCR tests
// --------------------------------------------------

fn t16() -> TestResult {
  var ok = true;
  let b = hb("C0FF8000");
  let r = sd_ocr_parse(&b);
  if !r.is_ok {
    return assert(false, "OCR C0FF8000 must parse");
  }
  let o: SdOcr = r.value;
  if o.raw != 3237969920 { ok = false; }
  if !o.ready { ok = false; }
  if !o.ccs { ok = false; }
  if o.uhs2 { ok = false; }
  if o.xpc { ok = false; }
  if o.voltage_mask != 511 { ok = false; }
  if !int_is(sd_ocr_value(&b), 3237969920) { ok = false; }
  if !bool_is(sd_ocr_ready(&b), true) { ok = false; }
  if !bool_is(sd_ocr_ccs(&b), true) { ok = false; }
  if !int_is(sd_ocr_voltage_mask(&b), 511) { ok = false; }
  let busy = hb("40FF8000");
  if !bool_is(sd_ocr_ready(&busy), false) { ok = false; }
  if !bool_is(sd_ocr_ccs(&busy), true) { ok = false; }
  let bare = hb("80000000");
  if !bool_is(sd_ocr_ready(&bare), true) { ok = false; }
  if !bool_is(sd_ocr_ccs(&bare), false) { ok = false; }
  if !int_is(sd_ocr_voltage_mask(&bare), 0) { ok = false; }
  let partial = hb("00018000");
  if !bool_is(sd_ocr_supports_voltage(&partial, 2700), true) { ok = false; }
  if !bool_is(sd_ocr_supports_voltage(&partial, 2800), true) { ok = false; }
  if !bool_is(sd_ocr_supports_voltage(&partial, 2900), false) { ok = false; }
  if !bool_is(sd_ocr_supports_voltage(&b, 2700), true) { ok = false; }
  if !bool_is(sd_ocr_supports_voltage(&b, 3500), true) { ok = false; }
  if !int_is(sd_ocr_voltage_bit(2700), 15) { ok = false; }
  if !int_is(sd_ocr_voltage_bit(2800), 16) { ok = false; }
  if !int_is(sd_ocr_voltage_bit(3500), 23) { ok = false; }
  return assert(ok, "ocr: busy/ready, ccs, voltage windows and voltage queries");
}

fn t17() -> TestResult {
  var ok = true;
  if !err_ocr_is(sd_ocr_parse(&hb("C2FF8000")), "sd.ocr: reserved bits [26:25] must be zero") { ok = false; }
  if !err_ocr_is(sd_ocr_parse(&hb("C0FFC000")), "sd.ocr: reserved bits [14:0] must be zero") { ok = false; }
  if !err_ocr_is(sd_ocr_parse(&hb("C0FF8001")), "sd.ocr: reserved bits [14:0] must be zero") { ok = false; }
  if !err_ocr_is(sd_ocr_parse(&hb("C0FF80")), "sd.ocr: register needs 4 bytes, have 3") { ok = false; }
  if !err_ocr_is(sd_ocr_parse(&hb("C0FF800000")), "sd.ocr: register needs 4 bytes, have 5") { ok = false; }
  if !err_int_is(sd_ocr_value(&hb("C0FF80")), "sd.ocr: register needs 4 bytes, have 3") { ok = false; }
  if !err_int_is(sd_ocr_voltage_bit(2699), "sd.ocr: voltage 2699 out of range 2700..3500") { ok = false; }
  if !err_int_is(sd_ocr_voltage_bit(3600), "sd.ocr: voltage 3600 out of range 2700..3500") { ok = false; }
  if !err_int_is(sd_ocr_voltage_bit(2750), "sd.ocr: voltage 2750 is not a multiple of 100") { ok = false; }
  return assert(ok, "ocr reserved bits with offsets, length and voltage-range errors");
}

// --------------------------------------------------
//  SPI framing and CRC7
// --------------------------------------------------

fn t18() -> TestResult {
  var ok = true;
  let f0 = sd_spi_cmd0_frame();
  if !f0.is_ok {
    return assert(false, "CMD0 frame must build");
  }
  let b0: Vec[UInt8] = f0.value;
  if !bytes_equal(b0, hb("400000000095")) { ok = false; }
  let fc = sd_spi_command_frame(0, 0);
  if !fc.is_ok { ok = false; } else {
    let bc: Vec[UInt8] = fc.value;
    if !bytes_equal(bc, hb("400000000095")) { ok = false; }
  }
  let f8 = sd_spi_cmd8_frame(1, 170);
  if !f8.is_ok { ok = false; } else {
    let b8: Vec[UInt8] = f8.value;
    if !bytes_equal(b8, hb("48000001AA87")) { ok = false; }
  }
  let fm = sd_spi_command_frame_marker(13, 0, 149);
  if !fm.is_ok { ok = false; } else {
    let bm: Vec[UInt8] = fm.value;
    if !bytes_equal(bm, hb("4D0000000095")) { ok = false; }
  }
  let fmax = sd_spi_command_frame(63, 4294967295);
  if !fmax.is_ok { ok = false; } else {
    let bmax: Vec[UInt8] = fmax.value;
    if !int_is(sd_spi_frame_index(&bmax), 63) { ok = false; }
    if !int_is(sd_spi_frame_argument(&bmax), 4294967295) { ok = false; }
  }
  if !err_bytes_is(sd_spi_command_frame(64, 0), "sd.spi: command index 64 out of range 0..63") { ok = false; }
  if !err_bytes_is(sd_spi_command_frame(-1, 0), "sd.spi: command index -1 out of range 0..63") { ok = false; }
  if !err_bytes_is(sd_spi_command_frame(0, 4294967296), "sd.spi: argument 4294967296 does not fit in 32 bits") { ok = false; }
  if !err_bytes_is(sd_spi_command_frame_marker(0, 0, 148), "sd.spi: trailer marker 148 must have end bit 1") { ok = false; }
  if !err_bytes_is(sd_spi_command_frame_marker(0, 0, 256), "sd.spi: trailer marker 256 out of range 0..255") { ok = false; }
  if !err_bytes_is(sd_spi_cmd8_frame(16, 170), "sd.spi: cmd8 voltage 16 out of range 0..15") { ok = false; }
  if !err_bytes_is(sd_spi_cmd8_frame(1, 256), "sd.spi: cmd8 check pattern 256 out of range 0..255") { ok = false; }
  return assert(ok, "spi frames: pinned CMD0 0x95 and CMD8 0xAA/0x87, marker and range errors");
}

fn t19() -> TestResult {
  var ok = true;
  let f8 = sd_spi_cmd8_frame(1, 170);
  if !f8.is_ok {
    return assert(false, "CMD8 frame must build");
  }
  let b8: Vec[UInt8] = f8.value;
  if !int_is(sd_spi_frame_index(&b8), 8) { ok = false; }
  if !int_is(sd_spi_frame_argument(&b8), 426) { ok = false; }
  if !int_is(sd_spi_frame_trailer(&b8), 135) { ok = false; }
  if !int_is(sd_spi_frame_crc(&b8), 67) { ok = false; }
  if !bool_is(sd_spi_frame_crc_ok(&b8), true) { ok = false; }
  if !sd_spi_frame_check(&b8).is_ok { ok = false; }
  var cor = clone_reg(&b8);
  set_byte(&mut cor, 4, 171);
  let head = copy_first(&cor, 5);
  let comp = ref_crc7(&head, 5);
  let want = "sd.spi: crc7 mismatch: stored " + convert.int_to_string(67) + ", computed " + convert.int_to_string(comp);
  if !err_bool_is(sd_spi_frame_crc_ok(&cor), want) { ok = false; }
  if !err_unit_is(sd_spi_frame_check(&cor), want) { ok = false; }
  var badp = clone_reg(&b8);
  set_byte(&mut badp, 0, 0);
  if !err_int_is(sd_spi_frame_index(&badp), "sd.spi: prefix byte 0 does not have bits 7:6 = 01") { ok = false; }
  if !err_unit_is(sd_spi_frame_check(&badp), "sd.spi: prefix byte 0 does not have bits 7:6 = 01") { ok = false; }
  var bade = clone_reg(&b8);
  set_byte(&mut bade, 5, 134);
  if !err_bool_is(sd_spi_frame_crc_ok(&bade), "sd.spi: trailer byte 134 does not have end bit 1") { ok = false; }
  if !err_unit_is(sd_spi_frame_check(&bade), "sd.spi: trailer byte 134 does not have end bit 1") { ok = false; }
  let short = copy_first(&b8, 5);
  if !err_int_is(sd_spi_frame_index(&short), "sd.spi: frame needs 6 bytes, have 5") { ok = false; }
  if !err_unit_is(sd_spi_frame_check(&short), "sd.spi: frame needs 6 bytes, have 5") { ok = false; }
  return assert(ok, "spi frame inspection: fields, crc check, prefix/end-bit/length errors");
}

fn t20() -> TestResult {
  var ok = true;
  // Pinned command checksums.
  let h0 = hb("4000000000");
  let h8 = hb("48000001AA");
  if sd_crc7(&h0) != 74 { ok = false; }
  if sd_crc7(&h8) != 67 { ok = false; }
  // Independent cross-check on every fixture.
  if ref_crc7(&h0, 5) != sd_crc7(&h0) { ok = false; }
  if ref_crc7(&h8, 5) != sd_crc7(&h8) { ok = false; }
  let cid = synth_cid();
  let cid_head = copy_first(&cid, 15);
  if ref_crc7(&cid_head, 15) != sd_crc7(&cid_head) { ok = false; }
  if !int_is(sd_cid_crc(&cid), ref_crc7(&cid_head, 15)) { ok = false; }
  let csd1 = synth_csd_v1();
  let csd1_head = copy_first(&csd1, 15);
  if ref_crc7(&csd1_head, 15) != sd_crc7(&csd1_head) { ok = false; }
  if !int_is(sd_csd_crc(&csd1), ref_crc7(&csd1_head, 15)) { ok = false; }
  let csd2 = synth_csd_v2();
  let csd2_head = copy_first(&csd2, 15);
  if ref_crc7(&csd2_head, 15) != sd_crc7(&csd2_head) { ok = false; }
  let maxv = hb("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF");
  if ref_crc7(&maxv, 16) != sd_crc7(&maxv) { ok = false; }
  let empty = Vec[UInt8].new();
  if sd_crc7(&empty) != 0 { ok = false; }
  return assert(ok, "crc7: pinned CMD0/CMD8 checksums and independent LFSR cross-check");
}

fn t21() -> TestResult {
  var ok = true;
  let b = synth_cid();
  let r1 = sd_cid_parse(&b);
  let r2 = sd_cid_parse(&b);
  if !r1.is_ok || !r2.is_ok {
    return assert(false, "repeated cid parse must succeed");
  }
  let c1: SdCid = r1.value;
  let c2: SdCid = r2.value;
  if c1.manufacturer_id != c2.manufacturer_id { ok = false; }
  if !str_eq(c1.product_name, c2.product_name) { ok = false; }
  if c1.serial != c2.serial { ok = false; }
  if c1.crc7 != c2.crc7 { ok = false; }
  let s1 = synth_csd_v2();
  let s2 = synth_csd_v2();
  if !bytes_equal(s1, s2) { ok = false; }
  let ca = sd_csd_capacity_bytes(&s1);
  let cb = sd_csd_capacity_bytes(&s2);
  if !int_is(ca, 7948206080) { ok = false; }
  if !int_is(cb, 7948206080) { ok = false; }
  let f1 = sd_spi_cmd8_frame(1, 170);
  let f2 = sd_spi_cmd8_frame(1, 170);
  if !f1.is_ok || !f2.is_ok { ok = false; } else {
    let b1: Vec[UInt8] = f1.value;
    let b2: Vec[UInt8] = f2.value;
    if !bytes_equal(b1, b2) { ok = false; }
  }
  return assert(ok, "determinism: repeated parses, builds and capacity calls agree");
}

fn main() -> Int {
  io.println("=== xiom.sd conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.sd: all tests passed");
  } else {
    io.println("xiom.sd: tests failed");
  }
  return failed;
}
