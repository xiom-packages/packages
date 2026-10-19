// XIOM -- xiom.uf2 conformance tests (format + flashing, host side).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Host-independent checks (always run, always green):
//   * constants: magics, 512/32/476 sizes, flags, family IDs;
//   * block build golden (every header field + padding + end magic);
//   * build -> parse -> field roundtrip, with and without family;
//   * every structural rejection: short/bad magic/bad end, payload > 476,
//     block numbering, reserved flags, family+MD5 conflict, address
//     overflow, non-multiple image size, duplicate/missing/out-of-range
//     block numbers, mixed families;
//   * image build (256 and 476 chunking) -> parse -> exact payload
//     roundtrip, out-of-order file order, comment (NOFLASH) exclusion,
//     file-container addresses, contiguity reporting;
//   * catalogs (families, flags, error kinds, flash statuses).
//
// Host-touching checks use fs_temp_dir() only:
//   * basename parsing for both separators;
//   * mount presence / BOOTSEL INFO_UF2.TXT probe;
//   * flash SKIP on an absent mount, typed I/O/size/magic failures, a real
//     binary copy to a temp "mount" with read-back verification, and the
//     completion wait for an absent destination (COMPLETE) vs a still
//     present one (COPIED).  A real BOOTSEL volume is never required.
//
// Build+run:
//   scripts/port.ps1 -Package xiom.uf2 -TimeoutSec 300

module uf2_conformance

use xiom.io;
use xiom.io.fs;
use xiom.string.compare;
use xiom.uf2;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn why(msg: Str) {
  io.println("    detail: " + msg);
  io.flush_stdout();
}

fn finish(failed: Int) -> Int {
  if failed == 0 {
    io.println("xiom.uf2: all tests passed");
  } else {
    io.println("xiom.uf2: tests failed");
  }
  return failed;
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn itoa(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}

fn rd_u32(v: &Vec[UInt8], off: Int) -> Int {
  let b0 = v[off] as Int;
  let b1 = v[off + 1] as Int;
  let b2 = v[off + 2] as Int;
  let b3 = v[off + 3] as Int;
  return (b0 & 255) | ((b1 & 255) << 8) | ((b2 & 255) << 16) | ((b3 & 255) << 24);
}

fn put_u32(v: &mut Vec[UInt8], off: Int, value: Int) {
  v[off] = (value & 255) as UInt8;
  v[off + 1] = ((value >> 8) & 255) as UInt8;
  v[off + 2] = ((value >> 16) & 255) as UInt8;
  v[off + 3] = ((value >> 24) & 255) as UInt8;
}

fn clone_vec(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn append_vec(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn fill(n: Int, seed: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(((i * 7 + seed) % 256) as UInt8);
    i = i + 1;
  }
  return out;
}

fn valid_block() -> Vec[UInt8] {
  let p = fill(4, 1);
  let r = uf2_block_build(&p, 268435456, 0, 1, UF2_FAMILY_RP2040);
  if !r.is_ok { return Vec[UInt8].new(); }
  return r.value;
}

fn build_image(payload: &Vec[UInt8], addr: Int, family: Int) -> Vec[UInt8] {
  let r = uf2_image_build(payload, addr, family);
  if !r.is_ok { return Vec[UInt8].new(); }
  return r.value;
}

fn image_err_kind(data: &Vec[UInt8]) -> Int {
  let r = uf2_image_parse(data);
  if r.is_ok { return -1; }
  return r.error.kind;
}

fn block_err_kind(data: &Vec[UInt8]) -> Int {
  let r = uf2_block_parse(data);
  if r.is_ok { return -1; }
  return r.error.kind;
}

fn read_all(path: Str) -> Vec[UInt8] {
  let sz = fs.fs_size(path);
  if !sz.is_ok { return Vec[UInt8].new(); }
  let r = fs.fs_read_range(path, 0, sz.value);
  if !r.is_ok { return Vec[UInt8].new(); }
  return r.value;
}

fn remove_quiet(path: Str) {
  let r = io.remove_file(path);
}

// =========================================================================
// Constants and catalogs
// =========================================================================

fn test_constants() -> Int {
  var ok = UF2_BLOCK_SIZE == 512;
  ok = ok && UF2_HEADER_SIZE == 32;
  ok = ok && UF2_MAX_PAYLOAD == 476;
  ok = ok && UF2_MAGIC_START0 == 171066965;
  ok = ok && UF2_MAGIC_START1 == 2656915799;
  ok = ok && UF2_MAGIC_END == 179400496;
  ok = ok && UF2_FLAG_NOFLASH == 1;
  ok = ok && UF2_FLAG_FILECONTAINER == 4096;
  ok = ok && UF2_FLAG_FAMILY_ID == 8192;
  ok = ok && UF2_FLAG_MD5_CHKSUM == 16384;
  ok = ok && UF2_FLAG_EXTENSION_TAGS == 32768;
  ok = ok && UF2_FLAG_KNOWN_MASK == 61441;
  ok = ok && UF2_FAMILY_RP2040 == 3834380118;
  ok = ok && UF2_FAMILY_RP2350_ARM_S == 3834380121;
  ok = ok && UF2_FAMILY_RP2350_RISCV == 3834380122;
  ok = ok && UF2_FAMILY_SAMD21 == 1760373640;
  ok = ok && UF2_FAMILY_SAMD51 == 1427194976;
  if !ok { why("a pinned UF2 constant drifted"); }
  return report(ok, "constants: magics, 512/32/476 sizes, flags and family IDs exact");
}

fn test_catalogs() -> Int {
  var failed = 0;
  var ok = streq(uf2_family_name(UF2_FAMILY_RP2040), "RP2040");
  ok = ok && streq(uf2_family_name(UF2_FAMILY_RP2350_ARM_S), "RP2350_ARM_S");
  ok = ok && streq(uf2_family_name(UF2_FAMILY_RP2350_RISCV), "RP2350_RISCV");
  ok = ok && streq(uf2_family_name(UF2_FAMILY_SAMD21), "SAMD21");
  ok = ok && streq(uf2_family_name(UF2_FAMILY_SAMD51), "SAMD51");
  ok = ok && streq(uf2_family_name(12345), "unknown");
  failed = failed + report(ok, "names: family catalog resolves RP2040/RP2350/SAMD21/SAMD51 + unknown");

  ok = streq(uf2_flags_name(0), "NONE");
  ok = ok && streq(uf2_flags_name(UF2_FLAG_NOFLASH), "NOFLASH");
  ok = ok && streq(uf2_flags_name(UF2_FLAG_FAMILY_ID | UF2_FLAG_FILECONTAINER), "FILECONTAINER|FAMILY_ID");
  ok = ok && streq(uf2_flags_name(2), "RESERVED");
  failed = failed + report(ok, "names: flag catalog (NONE / single / combined / reserved)");

  ok = streq(uf2_error_kind_name(UF2_ERR_MAGIC), "MAGIC");
  ok = ok && streq(uf2_error_kind_name(UF2_ERR_VERIFY), "VERIFY");
  ok = ok && streq(uf2_error_kind_name(999), "unknown");
  ok = ok && streq(uf2_flash_status_name(UF2_FLASH_SKIP), "SKIP");
  ok = ok && streq(uf2_flash_status_name(UF2_FLASH_COMPLETE), "COMPLETE");
  ok = ok && streq(uf2_flash_status_name(UF2_FLASH_COPIED), "COPIED");
  ok = ok && streq(uf2_flash_status_name(77), "unknown");
  failed = failed + report(ok, "names: error-kind and flash-status catalogs");
  return failed;
}

// =========================================================================
// Block build / parse
// =========================================================================

fn test_block_golden() -> Int {
  let p = fill(4, 9);
  let r = uf2_block_build(&p, 268435456, 0, 1, UF2_FAMILY_RP2040);
  var ok = r.is_ok;
  if ok {
    let b = r.value;
    ok = b.len() == 512;
    if ok { ok = rd_u32(&b, 0) == UF2_MAGIC_START0; }
    if ok { ok = rd_u32(&b, 4) == UF2_MAGIC_START1; }
    if ok { ok = rd_u32(&b, 8) == UF2_FLAG_FAMILY_ID; }
    if ok { ok = rd_u32(&b, 12) == 268435456; }
    if ok { ok = rd_u32(&b, 16) == 4; }
    if ok { ok = rd_u32(&b, 20) == 0; }
    if ok { ok = rd_u32(&b, 24) == 1; }
    if ok { ok = rd_u32(&b, 28) == UF2_FAMILY_RP2040; }
    if ok { ok = (b[32] as Int) == (p[0] as Int); }
    if ok { ok = (b[35] as Int) == (p[3] as Int); }
    if ok {
      var i = 36;
      while i < 508 {
        if b[i] != 0 { ok = false; }
        i = i + 1;
      }
    }
    if ok { ok = rd_u32(&b, 508) == UF2_MAGIC_END; }
  } else {
    why(r.error.message);
  }
  return report(ok, "block-golden: 512 bytes, all header fields, zero padding, end magic");
}

fn test_block_roundtrip() -> Int {
  let p = fill(300, 3);
  let r = uf2_block_build(&p, 537919488, 2, 5, UF2_FAMILY_SAMD51);
  var ok = r.is_ok;
  if ok {
    let pr = uf2_block_parse(&r.value);
    ok = pr.is_ok;
    if ok {
      ok = pr.value.flags == UF2_FLAG_FAMILY_ID;
      ok = ok && pr.value.target_addr == 537919488;
      ok = ok && pr.value.payload_size == 300;
      ok = ok && pr.value.block_no == 2;
      ok = ok && pr.value.num_blocks == 5;
      ok = ok && pr.value.family_id == UF2_FAMILY_SAMD51;
      ok = ok && pr.value.has_family;
      ok = ok && !pr.value.no_flash;
      ok = ok && !pr.value.has_md5;
      ok = ok && bytes_equal(&pr.value.payload, &p);
    } else {
      why(pr.error.message);
    }
  } else {
    why(r.error.message);
  }
  return report(ok, "block-roundtrip: 300-byte payload + every field parses back exactly");
}

fn test_block_no_family() -> Int {
  let p = fill(8, 4);
  let r = uf2_block_build(&p, 4096, 0, 1, 0);
  var ok = r.is_ok;
  if ok {
    let b = r.value;
    ok = rd_u32(&b, 8) == 0 && rd_u32(&b, 28) == 0;
    let pr = uf2_block_parse(&b);
    ok = ok && pr.is_ok;
    if ok {
      ok = !pr.value.has_family && pr.value.family_id == 0;
    }
  }
  return report(ok, "block: family_id 0 -> no FAMILY_ID flag, parse reports has_family false");
}

fn test_block_parse_rejections() -> Int {
  var failed = 0;
  var ok = false;

  let short = fill(511, 1);
  ok = block_err_kind(&short) == UF2_ERR_SIZE;
  failed = failed + report(ok, "block-reject: 511 bytes -> SIZE");

  var b = valid_block();
  put_u32(&mut b, 0, 0);
  ok = block_err_kind(&b) == UF2_ERR_MAGIC;
  failed = failed + report(ok, "block-reject: start magic 0 -> MAGIC");

  b = valid_block();
  put_u32(&mut b, 4, 0);
  ok = block_err_kind(&b) == UF2_ERR_MAGIC;
  failed = failed + report(ok, "block-reject: start magic 1 -> MAGIC");

  b = valid_block();
  put_u32(&mut b, 508, 0);
  ok = block_err_kind(&b) == UF2_ERR_MAGIC;
  failed = failed + report(ok, "block-reject: end magic -> MAGIC");

  b = valid_block();
  put_u32(&mut b, 16, 477);
  ok = block_err_kind(&b) == UF2_ERR_PAYLOAD;
  failed = failed + report(ok, "block-reject: payload_size 477 -> PAYLOAD");

  b = valid_block();
  put_u32(&mut b, 20, 1);
  ok = block_err_kind(&b) == UF2_ERR_INDEX;
  failed = failed + report(ok, "block-reject: block_no == num_blocks -> INDEX");

  b = valid_block();
  put_u32(&mut b, 24, 0);
  ok = block_err_kind(&b) == UF2_ERR_INDEX;
  failed = failed + report(ok, "block-reject: num_blocks 0 -> INDEX");

  b = valid_block();
  put_u32(&mut b, 8, 2);
  ok = block_err_kind(&b) == UF2_ERR_FLAGS;
  failed = failed + report(ok, "block-reject: reserved flag bit -> FLAGS");

  b = valid_block();
  put_u32(&mut b, 8, UF2_FLAG_FAMILY_ID | UF2_FLAG_MD5_CHKSUM);
  ok = block_err_kind(&b) == UF2_ERR_FLAGS;
  failed = failed + report(ok, "block-reject: FAMILY_ID + MD5_CHKSUM together -> FLAGS");

  b = valid_block();
  put_u32(&mut b, 12, UF2_U32_MAX);
  ok = block_err_kind(&b) == UF2_ERR_ARG;
  failed = failed + report(ok, "block-reject: target_addr + payload overflows u32 -> ARG");

  return failed;
}

fn test_block_build_rejections() -> Int {
  var failed = 0;
  var ok = false;

  let p4 = fill(4, 1);
  let big = fill(477, 1);
  let rb = uf2_block_build(&big, 0, 0, 1, 0);
  ok = !rb.is_ok && rb.error.kind == UF2_ERR_PAYLOAD;
  failed = failed + report(ok, "block-build-reject: payload 477 -> PAYLOAD");

  let ri = uf2_block_build(&p4, 0, 1, 1, 0);
  ok = !ri.is_ok && ri.error.kind == UF2_ERR_INDEX;
  failed = failed + report(ok, "block-build-reject: block_no out of range -> INDEX");

  let rn = uf2_block_build(&p4, 0, 0, 0, 0);
  ok = !rn.is_ok && rn.error.kind == UF2_ERR_INDEX;
  failed = failed + report(ok, "block-build-reject: num_blocks 0 -> INDEX");

  let ra = uf2_block_build(&p4, UF2_U32_MAX, 0, 1, 0);
  ok = !ra.is_ok && ra.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "block-build-reject: address overflow -> ARG");

  let rneg = uf2_block_build(&p4, -1, 0, 1, 0);
  ok = !rneg.is_ok && rneg.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "block-build-reject: negative address -> ARG");

  let rf = uf2_block_build(&p4, 0, 0, 1, UF2_U32_MAX + 1);
  ok = !rf.is_ok && rf.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "block-build-reject: family_id over u32 -> ARG");

  let rflag = uf2_block_build_with_flags(2, &p4, 0, 0, 1, 0);
  ok = !rflag.is_ok && rflag.error.kind == UF2_ERR_FLAGS;
  failed = failed + report(ok, "block-build-reject: reserved flag -> FLAGS");

  let rboth = uf2_block_build_with_flags(UF2_FLAG_FAMILY_ID | UF2_FLAG_MD5_CHKSUM, &p4, 0, 0, 1, 0);
  ok = !rboth.is_ok && rboth.error.kind == UF2_ERR_FLAGS;
  failed = failed + report(ok, "block-build-reject: FAMILY_ID + MD5_CHKSUM -> FLAGS");

  return failed;
}

// =========================================================================
// Image build / parse
// =========================================================================

fn test_image_roundtrip() -> Int {
  let p = fill(700, 5);
  let img = build_image(&p, 268435456, UF2_FAMILY_RP2350_ARM_S);
  var ok = img.len() == 1536;
  if ok {
    let pr = uf2_image_parse(&img);
    ok = pr.is_ok;
    if ok {
      ok = pr.value.num_blocks == 3;
      ok = ok && pr.value.has_family;
      ok = ok && pr.value.family_id == UF2_FAMILY_RP2350_ARM_S;
      ok = ok && pr.value.data_bytes == 700;
      ok = ok && pr.value.target_addr == 268435456;
      ok = ok && pr.value.contiguous;
      ok = ok && !pr.value.file_container;
      ok = ok && bytes_equal(&pr.value.payload, &p);
      if ok {
        let b1 = uf2_block_parse_at(&img, 512);
        let b2 = uf2_block_parse_at(&img, 1024);
        ok = b1.is_ok && b2.is_ok;
        if ok {
          ok = b1.value.block_no == 1 && b1.value.target_addr == 268435712;
          ok = ok && b2.value.block_no == 2 && b2.value.target_addr == 268435968;
          ok = ok && b2.value.payload_size == 188;
        }
      }
    } else {
      why(pr.error.message);
    }
  }
  return report(ok, "image-roundtrip: 700 bytes -> 3 blocks -> exact payload + addresses");
}

fn test_image_chunked() -> Int {
  let p = fill(700, 6);
  let r = uf2_image_build_chunked(&p, 4096, UF2_FAMILY_RP2040, 476);
  var ok = r.is_ok;
  if ok {
    let img = r.value;
    ok = img.len() == 1024;
    let pr = uf2_image_parse(&img);
    ok = ok && pr.is_ok;
    if ok {
      ok = pr.value.num_blocks == 2;
      ok = ok && bytes_equal(&pr.value.payload, &p);
      let b0 = uf2_block_parse_at(&img, 0);
      let b1 = uf2_block_parse_at(&img, 512);
      ok = ok && b0.is_ok && b1.is_ok;
      if ok {
        ok = b0.value.payload_size == 476;
        ok = ok && b1.value.payload_size == 224;
        ok = ok && b1.value.target_addr == 4096 + 476;
      }
    } else {
      why(pr.error.message);
    }
  } else {
    why(r.error.message);
  }
  return report(ok, "image-chunked: 476-byte chunk -> 476 + 224, contiguous addresses, exact roundtrip");
}

fn test_image_build_rejections() -> Int {
  var failed = 0;
  var ok = false;
  let empty: Vec[UInt8] = Vec[UInt8].new();
  let r1 = uf2_image_build(&empty, 0, 0);
  ok = !r1.is_ok && r1.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "image-build-reject: empty payload -> ARG");

  let p = fill(10, 1);
  let r2 = uf2_image_build_chunked(&p, 0, 0, 0);
  ok = !r2.is_ok && r2.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "image-build-reject: chunk 0 -> ARG");

  let r3 = uf2_image_build_chunked(&p, 0, 0, 477);
  ok = !r3.is_ok && r3.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "image-build-reject: chunk 477 -> ARG");

  let r4 = uf2_image_build(&p, UF2_U32_MAX - 4, 0);
  ok = !r4.is_ok && r4.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "image-build-reject: target range overflow -> ARG");

  return failed;
}

fn test_image_parse_structure() -> Int {
  var failed = 0;
  var ok = false;

  let empty: Vec[UInt8] = Vec[UInt8].new();
  ok = image_err_kind(&empty) == UF2_ERR_SIZE;
  failed = failed + report(ok, "image-reject: empty file -> SIZE");

  let odd = fill(1000, 2);
  ok = image_err_kind(&odd) == UF2_ERR_SIZE;
  failed = failed + report(ok, "image-reject: size 1000 (not a multiple of 512) -> SIZE");

  let p = fill(700, 7);
  let img = build_image(&p, 0, UF2_FAMILY_RP2040);

  var bad = clone_vec(&img);
  put_u32(&mut bad, 512 + 24, 9);
  ok = image_err_kind(&bad) == UF2_ERR_INDEX;
  failed = failed + report(ok, "image-reject: inconsistent num_blocks -> INDEX");

  var dup = clone_vec(&img);
  put_u32(&mut dup, 512 + 20, 0);
  ok = image_err_kind(&dup) == UF2_ERR_INDEX;
  failed = failed + report(ok, "image-reject: duplicate block number -> INDEX");

  var missing: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 1024 {
    missing.push(img[i]);
    i = i + 1;
  }
  put_u32(&mut missing, 512 + 20, 2);
  ok = image_err_kind(&missing) == UF2_ERR_INDEX;
  failed = failed + report(ok, "image-reject: missing block number -> INDEX");

  let q = fill(64, 8);
  let b0 = uf2_block_build(&q, 0, 0, 2, UF2_FAMILY_RP2040);
  let b1 = uf2_block_build(&q, 64, 1, 2, UF2_FAMILY_SAMD21);
  var mixed: Vec[UInt8] = Vec[UInt8].new();
  if b0.is_ok { append_vec(&mut mixed, &b0.value); }
  if b1.is_ok { append_vec(&mut mixed, &b1.value); }
  ok = image_err_kind(&mixed) == UF2_ERR_FAMILY;
  failed = failed + report(ok, "image-reject: mixed family IDs -> FAMILY");

  return failed;
}

fn test_image_out_of_order() -> Int {
  let p = fill(300, 10);
  let img = build_image(&p, 8192, UF2_FAMILY_RP2040);
  var swapped: Vec[UInt8] = Vec[UInt8].new();
  var i = 512;
  while i < 1024 {
    swapped.push(img[i]);
    i = i + 1;
  }
  i = 0;
  while i < 512 {
    swapped.push(img[i]);
    i = i + 1;
  }
  let pr = uf2_image_parse(&swapped);
  var ok = pr.is_ok;
  if ok {
    ok = pr.value.num_blocks == 2 && bytes_equal(&pr.value.payload, &p);
    ok = ok && pr.value.contiguous;
  } else {
    why(pr.error.message);
  }
  return report(ok, "image-order: out-of-order file blocks accepted, payload rebuilt in block order");
}

fn test_image_noflash() -> Int {
  let q = fill(64, 11);
  let p1 = fill(64, 12);
  let p2 = fill(36, 13);
  let c = uf2_block_build_with_flags(UF2_FLAG_NOFLASH | UF2_FLAG_FAMILY_ID, &q, 536870912, 0, 3, UF2_FAMILY_RP2350_RISCV);
  let b1 = uf2_block_build(&p1, 268435456, 1, 3, UF2_FAMILY_RP2350_RISCV);
  let b2 = uf2_block_build(&p2, 268435520, 2, 3, UF2_FAMILY_RP2350_RISCV);
  var img: Vec[UInt8] = Vec[UInt8].new();
  var ok = c.is_ok && b1.is_ok && b2.is_ok;
  if ok {
    append_vec(&mut img, &c.value);
    append_vec(&mut img, &b1.value);
    append_vec(&mut img, &b2.value);
    let pr = uf2_image_parse(&img);
    ok = pr.is_ok;
    if ok {
      ok = pr.value.num_blocks == 3;
      ok = ok && pr.value.data_bytes == 100;
      ok = ok && pr.value.target_addr == 268435456;
      ok = ok && pr.value.family_id == UF2_FAMILY_RP2350_RISCV;
      var want: Vec[UInt8] = Vec[UInt8].new();
      append_vec(&mut want, &p1);
      append_vec(&mut want, &p2);
      ok = ok && bytes_equal(&pr.value.payload, &want);
    } else {
      why(pr.error.message);
    }
  }
  return report(ok, "image-noflash: comment block counted but excluded from payload; family from data blocks");
}

fn test_image_file_container() -> Int {
  let p = fill(4, 14);
  let b0 = uf2_block_build_with_flags(UF2_FLAG_FILECONTAINER | UF2_FLAG_FAMILY_ID, &p, 4096, 0, 2, UF2_FAMILY_RP2040);
  let b1 = uf2_block_build_with_flags(UF2_FLAG_FILECONTAINER | UF2_FLAG_FAMILY_ID, &p, 12288, 1, 2, UF2_FAMILY_RP2040);
  var img: Vec[UInt8] = Vec[UInt8].new();
  var ok = b0.is_ok && b1.is_ok;
  if ok {
    append_vec(&mut img, &b0.value);
    append_vec(&mut img, &b1.value);
    let pr = uf2_image_parse(&img);
    ok = pr.is_ok;
    if ok {
      ok = pr.value.file_container;
      ok = ok && !pr.value.contiguous;
      ok = ok && pr.value.data_bytes == 8;
    } else {
      why(pr.error.message);
    }
  }
  return report(ok, "image-container: FILECONTAINER addresses accepted, contiguity reported false");
}

fn test_validate_payload() -> Int {
  var failed = 0;
  var ok = false;
  let p = fill(500, 15);
  let img = build_image(&p, 0, UF2_FAMILY_SAMD21);
  let vr = uf2_image_validate(&img);
  ok = vr.is_ok;
  failed = failed + report(ok, "validate: a built image validates clean");

  let pr = uf2_image_payload(&img);
  ok = pr.is_ok && bytes_equal(&pr.value, &p);
  failed = failed + report(ok, "payload: uf2_image_payload returns the exact source bytes");

  var bad = clone_vec(&img);
  put_u32(&mut bad, 4, 0);
  let vr2 = uf2_image_validate(&bad);
  ok = !vr2.is_ok && vr2.error.kind == UF2_ERR_MAGIC;
  failed = failed + report(ok, "validate: bad magic -> typed MAGIC");

  ok = uf2_block_is_uf2(&img) && !uf2_block_is_uf2(&bad);
  failed = failed + report(ok, "is_uf2: true for valid start magics, false after corruption");

  let vb = valid_block();
  let vbr = uf2_block_validate(&vb);
  var cb = clone_vec(&vb);
  put_u32(&mut cb, 0, 0);
  let cbr = uf2_block_validate(&cb);
  ok = vbr.is_ok && !cbr.is_ok && cbr.error.kind == UF2_ERR_MAGIC;
  failed = failed + report(ok, "block-validate: valid block Ok, corrupted start magic -> MAGIC");
  return failed;
}

// =========================================================================
// Flashing (temp files only; no real BOOTSEL volume required)
// =========================================================================

fn test_basename() -> Int {
  var ok = streq(uf2_basename("C:\\firmware\\app.uf2"), "app.uf2");
  ok = ok && streq(uf2_basename("/tmp/app.uf2"), "app.uf2");
  ok = ok && streq(uf2_basename("app.uf2"), "app.uf2");
  ok = ok && streq(uf2_basename("C:\\firmware\\"), "");
  return report(ok, "basename: backslash/slash/plain paths and trailing separator");
}

fn test_mount_probe() -> Int {
  var failed = 0;
  var ok = false;
  let missing = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-no-such-mount-" + itoa(io.time_now()));
  ok = !uf2_mount_present(missing) && !uf2_mount_is_bootsel(missing);
  failed = failed + report(ok, "mount: absent path -> not present, not BOOTSEL (SKIP seam)");

  let mdir = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-mount-" + itoa(io.time_now()));
  let cr = io.create_dir(mdir);
  ok = cr.is_ok;
  if ok {
    ok = uf2_mount_present(mdir) && !uf2_mount_is_bootsel(mdir);
    let info = io.join_paths(mdir, UF2_INFO_FILE);
    let info_bytes = fill(3, 1);
    let wr = fs.fs_write(info, &info_bytes);
    ok = ok && wr.is_ok && uf2_mount_is_bootsel(mdir);
    remove_quiet(info);
    let rd = io.remove_dir(mdir);
    ok = ok && rd.is_ok;
  } else {
    why("cannot create a temp mount directory");
  }
  failed = failed + report(ok, "mount: directory present; INFO_UF2.TXT toggles the BOOTSEL probe");
  return failed;
}

fn test_flash_args_and_skip() -> Int {
  var failed = 0;
  var ok = false;
  let mdir = fs.fs_temp_dir();
  let r1 = uf2_flash_to_mount("", mdir, 0, 1);
  ok = !r1.is_ok && r1.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "flash-args: empty source -> ARG");

  let r2 = uf2_flash_to_mount("x.uf2", "", 0, 1);
  ok = !r2.is_ok && r2.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "flash-args: empty mount -> ARG");

  let r3 = uf2_flash_to_mount("x.uf2", mdir, -1, 1);
  ok = !r3.is_ok && r3.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "flash-args: negative timeout -> ARG");

  let r4 = uf2_flash_to_mount("x.uf2", mdir, 10, 0);
  ok = !r4.is_ok && r4.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "flash-args: timeout with poll 0 -> ARG");

  let missing = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-absent-" + itoa(io.time_now()));
  let r5 = uf2_flash_to_mount(io.join_paths(fs.fs_temp_dir(), "also-missing.uf2"), missing, 0, 1);
  ok = r5.is_ok;
  if ok {
    ok = r5.value.status == UF2_FLASH_SKIP && !r5.value.verified;
    ok = ok && streq(r5.value.detail, "no mount/volume present");
  }
  failed = failed + report(ok, "flash-skip: absent mount -> Ok status SKIP, not an error");

  let w1 = uf2_flash_wait_complete("", mdir, 0, 1);
  ok = !w1.is_ok && w1.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "flash-wait-args: empty destination -> ARG");

  let w2 = uf2_flash_wait_complete("x.uf2", mdir, -1, 1);
  ok = !w2.is_ok && w2.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "flash-wait-args: negative timeout -> ARG");

  let w3 = uf2_flash_wait_complete("x.uf2", mdir, 10, 0);
  ok = !w3.is_ok && w3.error.kind == UF2_ERR_ARG;
  failed = failed + report(ok, "flash-wait-args: poll 0 with a timeout -> ARG");
  return failed;
}

fn test_flash_source_errors() -> Int {
  var failed = 0;
  var ok = false;
  let stamp = itoa(io.time_now());
  let mdir = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-flash-" + stamp);
  let cr = io.create_dir(mdir);
  ok = cr.is_ok;
  if !ok {
    why("cannot create a temp mount directory");
    return report(false, "flash-source: temp mount unavailable");
  }

  let missing = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-missing-" + stamp + ".uf2");
  let r1 = uf2_flash_to_mount(missing, mdir, 0, 1);
  ok = !r1.is_ok && r1.error.kind == UF2_ERR_IO;
  failed = failed + report(ok, "flash-source: missing source -> IO");

  let badsize = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-badsize-" + stamp + ".uf2");
  let size_bytes = fill(100, 1);
  let w1 = fs.fs_write(badsize, &size_bytes);
  let r2 = uf2_flash_to_mount(badsize, mdir, 0, 1);
  ok = w1.is_ok && !r2.is_ok && r2.error.kind == UF2_ERR_SIZE;
  failed = failed + report(ok, "flash-source: 100-byte file -> SIZE");

  let badmagic = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-badmagic-" + stamp + ".uf2");
  let magic_bytes = fill(512, 1);
  let w2 = fs.fs_write(badmagic, &magic_bytes);
  let r3 = uf2_flash_to_mount(badmagic, mdir, 0, 1);
  ok = w2.is_ok && !r3.is_ok && r3.error.kind == UF2_ERR_MAGIC;
  failed = failed + report(ok, "flash-source: 512 bytes of zeros -> MAGIC");

  remove_quiet(badsize);
  remove_quiet(badmagic);
  let rd = io.remove_dir(mdir);
  ok = rd.is_ok;
  return failed;
}

fn test_flash_copy_and_completion() -> Int {
  var failed = 0;
  var ok = false;
  let stamp = itoa(io.time_now());
  let mdir = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-copy-mount-" + stamp);
  let src = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-copy-src-" + stamp + ".uf2");
  let cr = io.create_dir(mdir);
  let p = fill(700, 16);
  let img = build_image(&p, 268435456, UF2_FAMILY_RP2040);
  let wr = fs.fs_write(src, &img);
  ok = cr.is_ok && wr.is_ok && img.len() == 1536;
  if ok {
    let r = uf2_flash_to_mount(src, mdir, 0, 1);
    ok = r.is_ok;
    if ok {
      ok = r.value.status == UF2_FLASH_COPIED;
      ok = ok && r.value.verified;
      ok = ok && r.value.source_bytes == 1536;
      ok = ok && r.value.copied_bytes == 1536;
      ok = ok && r.value.blocks == 3;
      let dest = io.join_paths(mdir, uf2_basename(src));
      ok = ok && streq(r.value.dest_path, dest);
      ok = ok && fs.fs_exists(dest);
      if ok {
        let back = read_all(dest);
        ok = bytes_equal(&back, &img);
        remove_quiet(dest);
      }
    } else {
      why(r.error.message);
    }
  } else {
    why("cannot prepare the temp source/mount");
  }
  remove_quiet(src);
  let rd = io.remove_dir(mdir);
  ok = ok && rd.is_ok;
  failed = failed + report(ok, "flash-copy: binary copy + read-back verification -> COPIED (volume still up)");

  let absent = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-never-written-" + stamp + ".uf2");
  let w1 = uf2_flash_wait_complete(absent, fs.fs_temp_dir(), 0, 1);
  ok = w1.is_ok && w1.value == UF2_FLASH_COMPLETE;
  failed = failed + report(ok, "flash-complete: absent destination -> COMPLETE immediately");

  let present = io.join_paths(fs.fs_temp_dir(), "xiom-uf2-present-" + stamp + ".uf2");
  let present_bytes = fill(4, 1);
  let wp = fs.fs_write(present, &present_bytes);
  let w2 = uf2_flash_wait_complete(present, fs.fs_temp_dir(), 0, 1);
  ok = wp.is_ok && w2.is_ok && w2.value == UF2_FLASH_COPIED;
  failed = failed + report(ok, "flash-complete: present destination with timeout 0 -> COPIED");

  remove_quiet(present);
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.uf2 conformance tests ===");
  var failed: Int = 0;

  failed = failed + test_constants();
  failed = failed + test_catalogs();
  failed = failed + test_block_golden();
  failed = failed + test_block_roundtrip();
  failed = failed + test_block_no_family();
  failed = failed + test_block_parse_rejections();
  failed = failed + test_block_build_rejections();
  failed = failed + test_image_roundtrip();
  failed = failed + test_image_chunked();
  failed = failed + test_image_build_rejections();
  failed = failed + test_image_parse_structure();
  failed = failed + test_image_out_of_order();
  failed = failed + test_image_noflash();
  failed = failed + test_image_file_container();
  failed = failed + test_validate_payload();
  failed = failed + test_basename();
  failed = failed + test_mount_probe();
  failed = failed + test_flash_args_and_skip();
  failed = failed + test_flash_source_errors();
  failed = failed + test_flash_copy_and_completion();

  return finish(failed);
}
