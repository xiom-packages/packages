// XIOM -- xiom.uf2 conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented xiom.uf2 API against SPEC.md: the three magic
// constants and the five format flags, the pinned 512-byte synthetic block
// fixture (family 0xE48BFF56, address 0x10000000, 256 payload bytes), the
// per-block validation catalog with absolute error offsets, block
// build/parse roundtrips against the pinned bytes, full-image build/parse
// order independence (out-of-order blocks), payload-size variants (128/476),
// semantic image errors (count mismatch, duplicate block, inconsistent
// family ID), the documented family-ID table (RP2040, three RP2350 images,
// SAMD21, SAMD51), flash planning/join/filename rules, the SKIP-safe
// no-volume path, a synthetic BOOTSEL volume created under the host temp
// directory (detection through INFO_UF2.TXT, copy, byte readback and
// timeout-based completion polling), and flash status/argument errors.
//
// All block fixtures are synthetic and built in-test from pinned hex
// (xiom.encoding.hex) or byte pushes. Str values are compared through
// xiom.string.compare.str_compare; the library never compares Str values.

module uf2_tests
use xiom.io; use xiom.test;
use xiom.uf2;
use xiom.string.compare;
use xiom.encoding.hex;
use xiom.io.fs;
use xiom.convert.int;
use xiom.time;

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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn clone_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Byte pattern used by image roundtrip tests.
fn payload_seq(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((i % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn put_le32(v: &mut Vec[UInt8], off: Int, value: Int) {
  v[off] = (value % 256) as UInt8;
  v[off + 1] = ((value / 256) % 256) as UInt8;
  v[off + 2] = ((value / 65536) % 256) as UInt8;
  v[off + 3] = ((value / 16777216) % 256) as UInt8;
}

// Copy the image with its 512-byte blocks in reverse file order.
fn blocks_reversed(data: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if data.len() % 512 != 0 {
    return out;
  }
  let n = data.len() / 512;
  var b = n - 1;
  while b >= 0 {
    var i = 0;
    while i < 512 {
      out.push(data[b * 512 + i]);
      i = i + 1;
    }
    b = b - 1;
  }
  return out;
}

fn repeat_a(n: Int) -> Str {
  var s = "";
  var i = 0;
  while i < n {
    s = s + "a";
    i = i + 1;
  }
  return s;
}

fn unique_absent_path(tag: Str) -> Str {
  return fs.fs_temp_dir() + "/xiom-uf2-" + tag + "-" + int.int_to_string(time.monotonic_ms());
}

// --------------------------------------------------
//  Typed error checkers
// --------------------------------------------------

fn e_block(r: Result[Uf2Block, Uf2Error], code: Int, off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Uf2Error = r.error;
  if e.code != code {
    return false;
  }
  if e.offset != off {
    return false;
  }
  return str_eq(e.message, msg);
}

fn e_bytes(r: Result[Vec[UInt8], Uf2Error], code: Int, off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Uf2Error = r.error;
  if e.code != code {
    return false;
  }
  if e.offset != off {
    return false;
  }
  return str_eq(e.message, msg);
}

fn e_image(r: Result[Uf2Image, Uf2Error], code: Int, off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Uf2Error = r.error;
  if e.code != code {
    return false;
  }
  if e.offset != off {
    return false;
  }
  return str_eq(e.message, msg);
}

fn e_plan(r: Result[Uf2FlashPlan, Uf2Error], code: Int, off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Uf2Error = r.error;
  if e.code != code {
    return false;
  }
  if e.offset != off {
    return false;
  }
  return str_eq(e.message, msg);
}

fn e_outcome(r: Result[Uf2FlashOutcome, Uf2Error], code: Int, off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Uf2Error = r.error;
  if e.code != code {
    return false;
  }
  if e.offset != off {
    return false;
  }
  return str_eq(e.message, msg);
}

fn e_wait(r: Result[Uf2FlashWait, Uf2Error], code: Int, off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Uf2Error = r.error;
  if e.code != code {
    return false;
  }
  if e.offset != off {
    return false;
  }
  return str_eq(e.message, msg);
}

// --------------------------------------------------
//  Pinned synthetic block fixture
// --------------------------------------------------
//
// Flags 0x00002000 (family ID present), target address 0x10000000,
// payload size 256, block 0 of 2, family 0xE48BFF56 (RP2040), payload bytes
// 00..FF, 220 zero padding bytes, then the end magic. Exactly 512 bytes.
fn fixture_hex() -> Str {
  return "5546320A57515D9E002000000000001000010000000000000200000056FF8BE4000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f" + "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f" + "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f" + "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf" + "e0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff0000000000000000000000000000000000000000000000000000000000000000" + "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" + "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" + "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000306FB10A";
}

fn fixture() -> Vec[UInt8] {
  return hb(fixture_hex());
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = UF2_MAGIC_START0 == 0x0A324655;
  if UF2_MAGIC_START1 != 0x9E5D5157 { ok = false; }
  if UF2_MAGIC_END != 0x0AB16F30 { ok = false; }
  if UF2_BLOCK_SIZE != 512 { ok = false; }
  if UF2_HEADER_SIZE != 32 { ok = false; }
  if UF2_PAYLOAD_MAX != 476 { ok = false; }
  if UF2_DEFAULT_PAYLOAD_SIZE != 256 { ok = false; }
  if UF2_FLAG_NOT_MAIN_FLASH != 0x00000001 { ok = false; }
  if UF2_FLAG_FILE_CONTAINER != 0x00001000 { ok = false; }
  if UF2_FLAG_FAMILY_ID != 0x00002000 { ok = false; }
  if UF2_FLAG_MD5 != 0x00004000 { ok = false; }
  if UF2_FLAG_EXTENSION_TAGS != 0x00008000 { ok = false; }
  if UF2_FLAG_ALL != 0x0000F001 { ok = false; }
  if UF2_FAMILY_RP2040 != 0xE48BFF56 { ok = false; }
  if UF2_FAMILY_RP2350_ARM_S != 0xE48BFF59 { ok = false; }
  if UF2_FAMILY_RP2350_RISCV != 0xE48BFF5A { ok = false; }
  if UF2_FAMILY_RP2350_ARM_NS != 0xE48BFF5B { ok = false; }
  if UF2_FAMILY_SAMD21 != 0x68ED2B88 { ok = false; }
  if UF2_FAMILY_SAMD51 != 0x55114460 { ok = false; }
  return assert(ok, "magic words, block geometry, five flags and family IDs are pinned");
}

fn t2() -> TestResult {
  let f = fixture();
  var ok = f.len() == 512;
  let r = uf2_block_parse(&f);
  if !r.is_ok {
    return assert(false, "pinned synthetic block parses into every documented field");
  }
  let b: Uf2Block = r.value;
  let flags: Int = b.flags;
  let addr: Int = b.target_address;
  let psize: Int = b.payload_size;
  let bno: Int = b.block_no;
  let nblocks: Int = b.num_blocks;
  let fam: Int = b.family_id;
  let present: Bool = b.family_id_present;
  if flags != 0x00002000 { ok = false; }
  if addr != 0x10000000 { ok = false; }
  if psize != 256 { ok = false; }
  if bno != 0 { ok = false; }
  if nblocks != 2 { ok = false; }
  if fam != 0xE48BFF56 { ok = false; }
  if !present { ok = false; }
  let p: Vec[UInt8] = b.payload;
  if p.len() != 256 { ok = false; }
  if p[0] != 0 { ok = false; }
  if p[42] != 42 { ok = false; }
  if p[255] != 255 { ok = false; }
  return assert(ok, "pinned synthetic block parses into every documented field");
}

fn t3() -> TestResult {
  var ok = true;
  let short = zeros(511);
  if !e_block(uf2_block_parse(&short), UF2_ERR_BLOCK_SIZE, 511, "uf2: block size") { ok = false; }
  let long = zeros(513);
  if !e_block(uf2_block_parse(&long), UF2_ERR_BLOCK_SIZE, 513, "uf2: block size") { ok = false; }
  var v = fixture();
  v[0] = 0 as UInt8;
  if !e_block(uf2_block_parse(&v), UF2_ERR_MAGIC_START0, 0, "uf2: bad start magic 0") { ok = false; }
  v = fixture();
  v[4] = 0 as UInt8;
  if !e_block(uf2_block_parse(&v), UF2_ERR_MAGIC_START1, 4, "uf2: bad start magic 1") { ok = false; }
  v = fixture();
  v[508] = 0 as UInt8;
  if !e_block(uf2_block_parse(&v), UF2_ERR_MAGIC_END, 508, "uf2: bad end magic") { ok = false; }
  let f = fixture();
  if !uf2_block_parse_at(&f, 0).is_ok { ok = false; }
  if !e_block(uf2_block_parse_at(&f, -1), UF2_ERR_ARGUMENT, 0, "uf2: negative offset") { ok = false; }
  if !e_block(uf2_block_parse_at(&f, 1), UF2_ERR_BLOCK_SIZE, 512, "uf2: block size") { ok = false; }
  let two = cat(fixture(), fixture());
  if !uf2_block_parse_at(&two, 512).is_ok { ok = false; }
  return assert(ok, "block size, three magic words and offsets are validated");
}

fn t4() -> TestResult {
  var ok = true;
  var v = fixture();
  put_le32(&mut v, 16, 477);
  if !e_block(uf2_block_parse(&v), UF2_ERR_PAYLOAD_SIZE, 16, "uf2: payload size out of range") { ok = false; }
  v = fixture();
  put_le32(&mut v, 24, 0);
  if !e_block(uf2_block_parse(&v), UF2_ERR_BLOCK_COUNT, 24, "uf2: block count is zero") { ok = false; }
  v = fixture();
  put_le32(&mut v, 20, 2);
  if !e_block(uf2_block_parse(&v), UF2_ERR_BLOCK_NUMBER, 20, "uf2: block number out of range") { ok = false; }
  v = fixture();
  put_le32(&mut v, 16, 476);
  let r = uf2_block_parse(&v);
  if !r.is_ok { ok = false; } else {
    let b: Uf2Block = r.value;
    if b.payload_size != 476 { ok = false; }
    let p: Vec[UInt8] = b.payload;
    if p.len() != 476 { ok = false; }
  }
  return assert(ok, "payload size and block numbering boundaries are enforced");
}

fn t5() -> TestResult {
  var p = Vec[UInt8].new();
  var i = 0;
  while i < 17 {
    p.push(((i * 7) % 256) as UInt8);
    i = i + 1;
  }
  let br = uf2_block_build(0x10000000, &p, 3, 7, 0xE48BFF56, 0x00002000);
  var ok = br.is_ok;
  if ok {
    let out: Vec[UInt8] = br.value;
    if out.len() != 512 { ok = false; }
    if out[0] != 0x55 || out[1] != 0x46 || out[2] != 0x32 || out[3] != 0x0A { ok = false; }
    if out[4] != 0x57 || out[5] != 0x51 || out[6] != 0x5D || out[7] != 0x9E { ok = false; }
    if out[508] != 0x30 || out[509] != 0x6F || out[510] != 0xB1 || out[511] != 0x0A { ok = false; }
    var z = 32 + 17;
    while z < 508 {
      if out[z] != 0 { ok = false; }
      z = z + 1;
    }
    let pr = uf2_block_parse(&out);
    if !pr.is_ok { ok = false; } else {
      let b: Uf2Block = pr.value;
      if b.target_address != 0x10000000 { ok = false; }
      if b.block_no != 3 { ok = false; }
      if b.num_blocks != 7 { ok = false; }
      if b.family_id != 0xE48BFF56 { ok = false; }
      if !b.family_id_present { ok = false; }
      if !bytes_equal(b.payload, p) { ok = false; }
    }
  }
  let fr = uf2_block_build_family(0x10000000, &p, 0, 1, 0xE48BFF56);
  if !fr.is_ok { ok = false; } else {
    let fbytes: Vec[UInt8] = fr.value;
    let fp = uf2_block_parse(&fbytes);
    if !fp.is_ok { ok = false; } else {
      let fb: Uf2Block = fp.value;
      if !fb.family_id_present { ok = false; }
      if fb.flags != 0x00002000 { ok = false; }
    }
  }
  return assert(ok, "block build emits canonical 512 bytes and parses back");
}

fn t6() -> TestResult {
  let p = zeros(10);
  let big = zeros(477);
  var ok = uf2_block_build(-1, &p, 0, 1, 0, 0).is_ok == false;
  if !e_bytes(uf2_block_build(-1, &p, 0, 1, 0, 0), UF2_ERR_ADDRESS, 12, "uf2: address out of range") { ok = false; }
  if !e_bytes(uf2_block_build(4294967296, &p, 0, 1, 0, 0), UF2_ERR_ADDRESS, 12, "uf2: address out of range") { ok = false; }
  if !e_bytes(uf2_block_build(0, &big, 0, 1, 0, 0), UF2_ERR_PAYLOAD_SIZE, 16, "uf2: payload size out of range") { ok = false; }
  if !e_bytes(uf2_block_build(0, &p, 0, 0, 0, 0), UF2_ERR_BLOCK_COUNT, 24, "uf2: block count out of range") { ok = false; }
  if !e_bytes(uf2_block_build(0, &p, 5, 5, 0, 0), UF2_ERR_BLOCK_NUMBER, 20, "uf2: block number out of range") { ok = false; }
  if !e_bytes(uf2_block_build(0, &p, -1, 5, 0, 0), UF2_ERR_BLOCK_NUMBER, 20, "uf2: block number out of range") { ok = false; }
  if !e_bytes(uf2_block_build(0, &p, 0, 1, -1, 0), UF2_ERR_FAMILY_ID, 28, "uf2: family id out of range") { ok = false; }
  if !e_bytes(uf2_block_build(0, &p, 0, 1, 4294967296, 0), UF2_ERR_FAMILY_ID, 28, "uf2: family id out of range") { ok = false; }
  if !e_bytes(uf2_block_build(0, &p, 0, 1, 0, -1), UF2_ERR_FLAGS, 8, "uf2: flags out of range") { ok = false; }
  if !e_bytes(uf2_block_build(0, &p, 0, 1, 0, 4294967296), UF2_ERR_FLAGS, 8, "uf2: flags out of range") { ok = false; }
  return assert(ok, "builder rejects every out-of-range field with typed errors");
}

fn t7() -> TestResult {
  let data = payload_seq(700);
  let br = uf2_image_build(0x10000000, &data, 0xE48BFF56);
  if !br.is_ok {
    return assert(false, "700-byte image builds three blocks and roundtrips");
  }
  let bytes: Vec[UInt8] = br.value;
  var ok = bytes.len() == 1536;
  let pr = uf2_image_parse(&bytes);
  if !pr.is_ok {
    return assert(false, "700-byte image builds three blocks and roundtrips");
  }
  let img: Uf2Image = pr.value;
  if img.block_count != 3 { ok = false; }
  if img.blocks.len() != 3 { ok = false; }
  if img.base_address != 0x10000000 { ok = false; }
  if img.family_id != 0xE48BFF56 { ok = false; }
  if !img.family_id_present { ok = false; }
  if img.payload_bytes != 768 { ok = false; }
  if img.data.len() != 768 { ok = false; }
  var i = 0;
  while i < 3 {
    let b: Uf2Block = img.blocks[i];
    if b.block_no != i { ok = false; }
    if b.payload_size != 256 { ok = false; }
    if b.target_address != 0x10000000 + i * 256 { ok = false; }
    i = i + 1;
  }
  i = 0;
  while i < data.len() {
    if img.data[i] != data[i] { ok = false; }
    i = i + 1;
  }
  while i < img.data.len() {
    if img.data[i] != 0 { ok = false; }
    i = i + 1;
  }
  let rev = blocks_reversed(&bytes);
  let rr = uf2_image_parse(&rev);
  if !rr.is_ok { ok = false; } else {
    let rimg: Uf2Image = rr.value;
    if !bytes_equal(rimg.data, img.data) { ok = false; }
    if rimg.blocks[0].block_no != 0 { ok = false; }
    if rimg.blocks[2].block_no != 2 { ok = false; }
  }
  let rb = uf2_image_build(img.base_address, &img.data, img.family_id);
  if !rb.is_ok { ok = false; } else {
    let rbytes: Vec[UInt8] = rb.value;
    if !bytes_equal(rbytes, bytes) { ok = false; }
  }
  return assert(ok, "700-byte image builds three blocks and roundtrips");
}

fn t8() -> TestResult {
  let data = payload_seq(700);
  var ok = true;
  let br = uf2_image_build_ex(0x10000000, &data, 128, 0);
  if !br.is_ok { ok = false; } else {
    let bytes: Vec[UInt8] = br.value;
    if bytes.len() != 6 * 512 { ok = false; }
    let pr = uf2_image_parse(&bytes);
    if !pr.is_ok { ok = false; } else {
      let img: Uf2Image = pr.value;
      if img.block_count != 6 { ok = false; }
      if img.data.len() != 768 { ok = false; }
      if img.base_address != 0x10000000 { ok = false; }
      if img.family_id_present { ok = false; }
      if img.family_id != 0 { ok = false; }
      var i = 0;
      while i < 6 {
        let b: Uf2Block = img.blocks[i];
        if b.payload_size != 128 { ok = false; }
        if b.target_address != 0x10000000 + i * 128 { ok = false; }
        i = i + 1;
      }
    }
  }
  let br2 = uf2_image_build_ex(0x10000000, &data, 476, 0xE48BFF56);
  if !br2.is_ok { ok = false; } else {
    let bytes2: Vec[UInt8] = br2.value;
    if bytes2.len() != 2 * 512 { ok = false; }
    let pr2 = uf2_image_parse(&bytes2);
    if !pr2.is_ok { ok = false; } else {
      let img2: Uf2Image = pr2.value;
      if img2.block_count != 2 { ok = false; }
      if img2.blocks[1].target_address != 0x10000000 + 476 { ok = false; }
      if img2.data.len() != 952 { ok = false; }
    }
  }
  if !e_bytes(uf2_image_build_ex(0x10000000, &data, 130, 0), UF2_ERR_PAYLOAD_SIZE, 16, "uf2: payload size not aligned") { ok = false; }
  if !e_bytes(uf2_image_build_ex(0x10000000, &data, 480, 0), UF2_ERR_PAYLOAD_SIZE, 16, "uf2: payload size out of range") { ok = false; }
  if !e_bytes(uf2_image_build_ex(0x10000000, &data, 0, 0), UF2_ERR_PAYLOAD_SIZE, 16, "uf2: payload size out of range") { ok = false; }
  return assert(ok, "payload sizes 128 and 476 build; unaligned/oversized are rejected");
}

fn t9() -> TestResult {
  let empty = Vec[UInt8].new();
  let data = payload_seq(700);
  var ok = e_bytes(uf2_image_build(0, &empty, 0), UF2_ERR_IMAGE_EMPTY, 0, "uf2: empty image");
  if !e_bytes(uf2_image_build(-1, &data, 0), UF2_ERR_ADDRESS, 12, "uf2: address out of range") { ok = false; }
  if !e_bytes(uf2_image_build(4294967040, &data, 0), UF2_ERR_ADDRESS, 12, "uf2: address overflow") { ok = false; }
  if !e_bytes(uf2_image_build(0, &data, 4294967296), UF2_ERR_FAMILY_ID, 28, "uf2: family id out of range") { ok = false; }
  return assert(ok, "image builder rejects empty input, bad base and family IDs");
}

fn t10() -> TestResult {
  var ok = e_image(uf2_image_parse(&Vec[UInt8].new()), UF2_ERR_IMAGE_EMPTY, 0, "uf2: empty image");
  let a = zeros(511);
  if !e_image(uf2_image_parse(&a), UF2_ERR_BLOCK_SIZE, 511, "uf2: image size") { ok = false; }
  let b = zeros(513);
  if !e_image(uf2_image_parse(&b), UF2_ERR_BLOCK_SIZE, 513, "uf2: image size") { ok = false; }
  let c = zeros(1000);
  if !e_image(uf2_image_parse(&c), UF2_ERR_BLOCK_SIZE, 1000, "uf2: image size") { ok = false; }
  let z = zeros(512);
  if !e_image(uf2_image_parse(&z), UF2_ERR_MAGIC_START0, 0, "uf2: bad start magic 0") { ok = false; }
  return assert(ok, "image size must be non-zero and a multiple of 512");
}

fn t11() -> TestResult {
  let data = payload_seq(300);
  let br = uf2_image_build(0x10000000, &data, 0xE48BFF56);
  var ok = br.is_ok;
  let base: Vec[UInt8] = br.value;
  var count = clone_bytes(&base);
  put_le32(&mut count, 512 + 24, 3);
  if !e_image(uf2_image_parse(&count), UF2_ERR_BLOCK_COUNT, 512 + 24, "uf2: block count mismatch") { ok = false; }
  var dup = clone_bytes(&base);
  put_le32(&mut dup, 512 + 20, 0);
  if !e_image(uf2_image_parse(&dup), UF2_ERR_DUPLICATE_BLOCK, 512 + 20, "uf2: duplicate block") { ok = false; }
  var fam = clone_bytes(&base);
  put_le32(&mut fam, 512 + 28, 0x68ED2B88);
  if !e_image(uf2_image_parse(&fam), UF2_ERR_FAMILY_ID, 512 + 28, "uf2: inconsistent family id") { ok = false; }
  var noflag = clone_bytes(&base);
  put_le32(&mut noflag, 512 + 8, 0);
  if !e_image(uf2_image_parse(&noflag), UF2_ERR_FAMILY_ID, 512 + 28, "uf2: inconsistent family id") { ok = false; }
  return assert(ok, "count mismatch, duplicate block and mixed family IDs are rejected");
}

fn t12() -> TestResult {
  let t = uf2_family_table();
  var ok = t.len() == 6;
  if uf2_family_count() != 6 { ok = false; }
  if uf2_family_id_at(0) != 0xE48BFF56 { ok = false; }
  if uf2_family_id_at(1) != 0xE48BFF59 { ok = false; }
  if uf2_family_id_at(2) != 0xE48BFF5A { ok = false; }
  if uf2_family_id_at(3) != 0xE48BFF5B { ok = false; }
  if uf2_family_id_at(4) != 0x68ED2B88 { ok = false; }
  if uf2_family_id_at(5) != 0x55114460 { ok = false; }
  if uf2_family_id_at(6) != -1 { ok = false; }
  if uf2_family_id_at(-1) != -1 { ok = false; }
  if !str_eq(uf2_family_name_at(0), "RP2040") { ok = false; }
  if !str_eq(uf2_family_name_at(1), "RP2350_ARM_S") { ok = false; }
  if !str_eq(uf2_family_name_at(2), "RP2350_RISCV") { ok = false; }
  if !str_eq(uf2_family_name_at(3), "RP2350_ARM_NS") { ok = false; }
  if !str_eq(uf2_family_name_at(4), "SAMD21") { ok = false; }
  if !str_eq(uf2_family_name_at(5), "SAMD51") { ok = false; }
  if !str_eq(uf2_family_name_at(6), "unknown") { ok = false; }
  if !str_eq(uf2_family_name(0xE48BFF56), "RP2040") { ok = false; }
  if !str_eq(uf2_family_name(0x55114460), "SAMD51") { ok = false; }
  if !str_eq(uf2_family_name(0x12345678), "unknown") { ok = false; }
  if !uf2_family_known(0x68ED2B88) { ok = false; }
  if uf2_family_known(0x12345678) { ok = false; }
  return assert(ok, "documented family table decodes RP2040/RP2350/SAMD21/SAMD51");
}

fn t13() -> TestResult {
  var ok = uf2_flags_have(0x00002001, UF2_FLAG_FAMILY_ID);
  if !uf2_flags_have(0x00002001, UF2_FLAG_NOT_MAIN_FLASH) { ok = false; }
  if uf2_flags_have(0x00002000, UF2_FLAG_MD5) { ok = false; }
  if uf2_flags_have(0, UF2_FLAG_FAMILY_ID) { ok = false; }
  if !uf2_flags_have(UF2_FLAG_ALL, UF2_FLAG_FILE_CONTAINER) { ok = false; }
  if !uf2_flags_have(UF2_FLAG_ALL, UF2_FLAG_EXTENSION_TAGS) { ok = false; }
  if !uf2_flags_have(4294967295, 0x80000000) { ok = false; }
  let f = fixture();
  let r = uf2_block_parse(&f);
  if !r.is_ok { ok = false; } else {
    let b: Uf2Block = r.value;
    if !uf2_block_has_flag(&b, UF2_FLAG_FAMILY_ID) { ok = false; }
    if uf2_block_has_flag(&b, UF2_FLAG_MD5) { ok = false; }
  }
  return assert(ok, "flag-bit tests cover defined, absent and high bits");
}

fn t14() -> TestResult {
  let absent = unique_absent_path("absent-mount");
  let data = payload_seq(300);
  let br = uf2_image_build(0x10000000, &data, 0xE48BFF56);
  if !br.is_ok {
    return assert(false, "no-volume flash is a typed SKIP and writes nothing");
  }
  let img: Vec[UInt8] = br.value;
  var ok = !uf2_volume_present(absent);
  let pr = uf2_flash_plan(absent, &img, "firmware.uf2");
  if !pr.is_ok { ok = false; } else {
    let plan: Uf2FlashPlan = pr.value;
    if plan.volume_present { ok = false; }
    if plan.block_count != 2 { ok = false; }
    if plan.bytes != 1024 { ok = false; }
    if !str_eq(plan.target_path, absent + "/firmware.uf2") { ok = false; }
  }
  let outr = uf2_flash_to_mount(absent, &img, "firmware.uf2");
  if !outr.is_ok { ok = false; } else {
    let out: Uf2FlashOutcome = outr.value;
    if out.status != UF2_FLASH_SKIPPED { ok = false; }
    if out.bytes_written != 0 { ok = false; }
    if out.volume_present { ok = false; }
    if out.block_count != 2 { ok = false; }
  }
  if uf2_volume_present(absent) { ok = false; }
  return assert(ok, "no-volume flash is a typed SKIP and writes nothing");
}

fn t15() -> TestResult {
  let data = payload_seq(300);
  let br = uf2_image_build(0x10000000, &data, 0xE48BFF56);
  var ok = br.is_ok;
  let img: Vec[UInt8] = br.value;
  if !e_plan(uf2_flash_plan("", &img, "firmware.uf2"), UF2_ERR_MOUNT, -1, "uf2: empty mount path") { ok = false; }
  if !e_plan(uf2_flash_plan("mnt", &img, ""), UF2_ERR_FILENAME, -1, "uf2: invalid filename") { ok = false; }
  if !e_plan(uf2_flash_plan("mnt", &img, "."), UF2_ERR_FILENAME, -1, "uf2: invalid filename") { ok = false; }
  if !e_plan(uf2_flash_plan("mnt", &img, ".."), UF2_ERR_FILENAME, -1, "uf2: invalid filename") { ok = false; }
  if !e_plan(uf2_flash_plan("mnt", &img, "a/b"), UF2_ERR_FILENAME, -1, "uf2: invalid filename") { ok = false; }
  if !e_plan(uf2_flash_plan("mnt", &img, "a\\b"), UF2_ERR_FILENAME, -1, "uf2: invalid filename") { ok = false; }
  if !e_plan(uf2_flash_plan("mnt", &img, repeat_a(256)), UF2_ERR_FILENAME, -1, "uf2: invalid filename") { ok = false; }
  if !uf2_filename_valid("firmware.uf2") { ok = false; }
  if !uf2_filename_valid("a.bin") { ok = false; }
  if !uf2_filename_valid(repeat_a(255)) { ok = false; }
  if uf2_filename_valid("") { ok = false; }
  let bad = zeros(512);
  if !e_plan(uf2_flash_plan("mnt", &bad, "firmware.uf2"), UF2_ERR_MAGIC_START0, 0, "uf2: bad start magic 0") { ok = false; }
  return assert(ok, "plan validates mount, file name and image before any write");
}

fn t16() -> TestResult {
  var ok = str_eq(uf2_mount_join("E:", "f.uf2"), "E:/f.uf2");
  if !str_eq(uf2_mount_join("E:/", "f.uf2"), "E:/f.uf2") { ok = false; }
  if !str_eq(uf2_mount_join("/media/x", "f.uf2"), "/media/x/f.uf2") { ok = false; }
  if !str_eq(uf2_mount_join("/media/x/", "f.uf2"), "/media/x/f.uf2") { ok = false; }
  if !str_eq(uf2_mount_join("C:\\mnt", "f.uf2"), "C:\\mnt/f.uf2") { ok = false; }
  if !str_eq(uf2_mount_join("C:\\mnt\\", "f.uf2"), "C:\\mnt\\f.uf2") { ok = false; }
  if !str_eq(uf2_mount_join("", "f.uf2"), "f.uf2") { ok = false; }
  return assert(ok, "mount join inserts exactly one separator, including drive roots");
}

fn t17() -> TestResult {
  let mount = fs.fs_temp_dir() + "/xiom-uf2-synthetic-mount";
  if io.is_dir(mount) {
    let _ = io.remove_file(uf2_mount_join(mount, "INFO_UF2.TXT"));
    let _ = io.remove_file(uf2_mount_join(mount, "firmware.uf2"));
    let _ = io.remove_dir(mount);
  }
  let cr = io.create_dir(mount);
  if !cr.is_ok {
    return assert(false, "synthetic BOOTSEL volume: detect, copy, readback and timeout wait");
  }
  var ok = true;
  if uf2_volume_present(mount) { ok = false; }
  let info = hb("55463220426f6f746c6f6164");
  let iw = fs.fs_write(uf2_mount_join(mount, "INFO_UF2.TXT"), &info);
  if !iw.is_ok { ok = false; }
  if !uf2_volume_present(mount) { ok = false; }
  let data = payload_seq(300);
  let br = uf2_image_build(0x10000000, &data, 0xE48BFF56);
  if !br.is_ok { ok = false; }
  let img: Vec[UInt8] = br.value;
  let pr = uf2_flash_plan(mount, &img, "firmware.uf2");
  if !pr.is_ok { ok = false; } else {
    let plan: Uf2FlashPlan = pr.value;
    if !plan.volume_present { ok = false; }
    if plan.bytes != 1024 { ok = false; }
  }
  let outr = uf2_flash_to_mount(mount, &img, "firmware.uf2");
  if !outr.is_ok { ok = false; } else {
    let out: Uf2FlashOutcome = outr.value;
    if out.status != UF2_FLASH_COPIED { ok = false; }
    if out.bytes_written != img.len() { ok = false; }
    if !out.volume_present { ok = false; }
    if !str_eq(out.target_path, mount + "/firmware.uf2") { ok = false; }
  }
  let target = uf2_mount_join(mount, "firmware.uf2");
  let szr = fs.fs_size(target);
  if !szr.is_ok { ok = false; } else {
    let sz: Int = szr.value;
    if sz != img.len() { ok = false; }
    let rr = fs.fs_read_range(target, 0, sz);
    if !rr.is_ok { ok = false; } else {
      let back: Vec[UInt8] = rr.value;
      if !bytes_equal(back, img) { ok = false; }
    }
  }
  let wr = uf2_flash_wait(mount, 0, 10);
  if !wr.is_ok { ok = false; } else {
    let w: Uf2FlashWait = wr.value;
    if w.completed { ok = false; }
    if !w.volume_present { ok = false; }
    if w.polls < 1 { ok = false; }
  }
  let _ = fs.fs_remove(target);
  let _ = fs.fs_remove(uf2_mount_join(mount, "INFO_UF2.TXT"));
  let _ = io.remove_dir(mount);
  if uf2_volume_present(mount) { ok = false; }
  return assert(ok, "synthetic BOOTSEL volume: detect, copy, readback and timeout wait");
}

fn t18() -> TestResult {
  let absent = unique_absent_path("wait-absent");
  var ok = true;
  let r1 = uf2_flash_wait(absent, 0, 10);
  if !r1.is_ok { ok = false; } else {
    let w1: Uf2FlashWait = r1.value;
    if !w1.completed { ok = false; }
    if w1.volume_present { ok = false; }
    if w1.polls != 1 { ok = false; }
  }
  if !e_wait(uf2_flash_wait("", 0, 10), UF2_ERR_MOUNT, -1, "uf2: empty mount path") { ok = false; }
  if !e_wait(uf2_flash_wait(absent, -1, 10), UF2_ERR_ARGUMENT, -1, "uf2: negative timeout") { ok = false; }
  if !e_wait(uf2_flash_wait(absent, 10, 0), UF2_ERR_ARGUMENT, -1, "uf2: invalid poll interval") { ok = false; }
  if !e_wait(uf2_flash_wait(absent, 10, -5), UF2_ERR_ARGUMENT, -1, "uf2: invalid poll interval") { ok = false; }
  if !str_eq(uf2_flash_status_name(UF2_FLASH_DONE), "done") { ok = false; }
  if !str_eq(uf2_flash_status_name(UF2_FLASH_COPIED), "copied") { ok = false; }
  if !str_eq(uf2_flash_status_name(UF2_FLASH_SKIPPED), "skipped") { ok = false; }
  if !str_eq(uf2_flash_status_name(99), "unknown") { ok = false; }
  return assert(ok, "wait completes on an absent volume and rejects bad arguments");
}

fn t19() -> TestResult {
  let f = fixture();
  let pr = uf2_block_parse(&f);
  var ok = pr.is_ok;
  if !pr.is_ok {
    return assert(false, "parse->build of the pinned block is byte-identical");
  }
  let b: Uf2Block = pr.value;
  let flags: Int = b.flags;
  let addr: Int = b.target_address;
  let bno: Int = b.block_no;
  let nb: Int = b.num_blocks;
  let fam: Int = b.family_id;
  let p: Vec[UInt8] = b.payload;
  let br = uf2_block_build(addr, &p, bno, nb, fam, flags);
  if !br.is_ok { ok = false; } else {
    let out: Vec[UInt8] = br.value;
    if !bytes_equal(out, f) { ok = false; }
  }
  return assert(ok, "parse->build of the pinned block is byte-identical");
}

fn t20() -> TestResult {
  var ok = true;
  var sizes = Vec[Int].new();
  sizes.push(4);
  sizes.push(64);
  sizes.push(256);
  sizes.push(472);
  sizes.push(476);
  var k = 0;
  while k < sizes.len() {
    let ps: Int = sizes[k];
    let data = payload_seq(ps * 2 + 3);
    let br = uf2_image_build_ex(0x20000000, &data, ps, 0x55114460);
    if !br.is_ok { ok = false; } else {
      let bytes: Vec[UInt8] = br.value;
      if bytes.len() != 3 * 512 { ok = false; }
      let pr = uf2_image_parse(&bytes);
      if !pr.is_ok { ok = false; } else {
        let img: Uf2Image = pr.value;
        if img.block_count != 3 { ok = false; }
        if img.data.len() != ps * 3 { ok = false; }
        if img.family_id != 0x55114460 { ok = false; }
        if !img.family_id_present { ok = false; }
        var i = 0;
        while i < data.len() {
          if img.data[i] != data[i] { ok = false; }
          i = i + 1;
        }
      }
    }
    k = k + 1;
  }
  return assert(ok, "aligned payload sizes 4..476 roundtrip exact image data");
}

fn main() -> Int {
  io.println("=== xiom.uf2 conformance tests ===");
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
    io.println("xiom.uf2: all tests passed");
  } else {
    io.println("xiom.uf2: tests failed");
  }
  return failed;
}
