// XIOM -- xiom.apple conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API against hand-built synthetic buffers:
//   * the four thin magics and the fat/fat64 magics (format detection,
//     bits and endianness);
//   * a 64-bit little-endian fixture with eleven load commands
//     (LC_SEGMENT_64 + one section, LC_LOAD_DYLIB, LC_UUID, LC_MAIN,
//     LC_CODE_SIGNATURE, LC_BUILD_VERSION, LC_SOURCE_VERSION, an unknown
//     command, LC_VERSION_MIN_MACOSX, LC_SYMTAB, LC_ENCRYPTION_INFO_64)
//     exercising every accessor and field selector;
//   * a 32-bit little-endian fixture (LC_SEGMENT with two sections and
//     LC_UUID) and a 32-bit big-endian fixture (endianness handling);
//   * a fat/universal fixture with an x86_64 4 KB slice and an arm64 16 KB
//     slice, plus the little-endian FAT_CIGAM form;
//   * the whole error catalog: header truncation/bad magic/fat-in-thin,
//     sizeofcmds bounds, cmdsize (too small, misaligned, over sizeofcmds,
//     not filling it), truncated commands, segment/section spans and
//     alignment, dylib name offsets/NUL/printable-ASCII, fixed-size
//     commands, fat arch count/table/slice bounds/alignment/overlap,
//     fat64 rejection, index and selector errors.
//
// Fixture bytes are assembled here byte by byte (independent of
// src/apple.xi). Str equality goes through str_compare (BUG 17
// discipline: `==` on a Str read from a Vec lowers to a pointer
// comparison).

module apple_tests
use xiom.io; use xiom.test;
use xiom.apple;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Generic helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `r` is Ok and its value equals `want`.
fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

// True when `r` is Ok and its Str value equals `want`.
fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return str_eq(v, want);
}

// True when `r` is Err with exactly `want`.
fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn macho_err_is(r: Result[MachOFile, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn fat_err_is(r: Result[FatFile, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Byte helpers (independent of src/apple.xi)
// --------------------------------------------------

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// Byte `k` (0 = least significant) of `val`'s two's-complement pattern.
fn low_byte(val: Int, k: Int) -> Int {
  var q = val;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b;
}

fn put_u8(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = (val % 256) as UInt8;
}

// Patch `size` (1..8) bytes at `off` with `val`; `be` selects byte order.
fn put_uint(v: &mut Vec[UInt8], off: Int, val: Int, size: Int, be: Bool) {
  if be {
    var i = size - 1;
    while i >= 0 {
      v[off + i] = low_byte(val, size - 1 - i) as UInt8;
      i = i - 1;
    }
  } else {
    var i = 0;
    while i < size {
      v[off + i] = low_byte(val, i) as UInt8;
      i = i + 1;
    }
  }
}

fn put_bytes(dst: &mut Vec[UInt8], off: Int, src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst[off + i] = src[i];
    i = i + 1;
  }
}

fn append_uint(out: &mut Vec[UInt8], val: Int, size: Int, be: Bool) {
  if be {
    var i = size - 1;
    while i >= 0 {
      out.push(low_byte(val, i) as UInt8);
      i = i - 1;
    }
  } else {
    var i = 0;
    while i < size {
      out.push(low_byte(val, i) as UInt8);
      i = i + 1;
    }
  }
}

fn append_zeros(out: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

fn append_ascii(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// A 16-byte NUL-padded segname/sectname field.
fn append_name16(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < 16 {
    var b = 0;
    if i < s.len() {
      b = (string.byte_at(s, i) as Int) & 0xFF;
    }
    out.push(b as UInt8);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// The 32-byte mach_header_64 prefix with the given ncmds/sizeofcmds.
fn head64(ncmds: Int, sizeofcmds: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_uint(&mut out, 0xFEEDFACF, 4, false);
  append_uint(&mut out, 0x01000007, 4, false);
  append_uint(&mut out, 3, 4, false);
  append_uint(&mut out, 2, 4, false);
  append_uint(&mut out, ncmds, 4, false);
  append_uint(&mut out, sizeofcmds, 4, false);
  append_uint(&mut out, 0x200085, 4, false);
  append_uint(&mut out, 0, 4, false);
  return out;
}

// Minimal 64-bit little-endian Mach-O (32-byte header, no commands).
fn fx64le_min() -> Vec[UInt8] {
  return head64(0, 0);
}

// Minimal 32-bit little-endian Mach-O (28-byte header, no commands).
fn fx32le_min() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_uint(&mut out, 0xFEEDFACE, 4, false);
  append_uint(&mut out, 7, 4, false);
  append_uint(&mut out, 3, 4, false);
  append_uint(&mut out, 1, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  return out;
}

// 416-byte 64-bit little-endian executable fixture with 11 load commands:
//   32   LC_SEGMENT_64 (__TEXT, 1 section __text) size 152
//   184  LC_LOAD_DYLIB ("/usr/lib/libSystem.B.dylib") size 56
//   240  LC_UUID size 24
//   264  LC_MAIN size 24
//   288  LC_CODE_SIGNATURE size 16
//   304  LC_BUILD_VERSION (macos 13.1.0, sdk 14.0.0) size 24
//   328  LC_SOURCE_VERSION size 16
//   344  unknown command 0x77 size 8
//   352  LC_VERSION_MIN_MACOSX (10.15.0, sdk 11.0.0) size 16
//   368  LC_SYMTAB size 24
//   392  LC_ENCRYPTION_INFO_64 size 24
fn fx64le() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_uint(&mut out, 0xFEEDFACF, 4, false);
  append_uint(&mut out, 0x01000007, 4, false);
  append_uint(&mut out, 3, 4, false);
  append_uint(&mut out, 2, 4, false);
  append_uint(&mut out, 11, 4, false);
  append_uint(&mut out, 384, 4, false);
  append_uint(&mut out, 0x200085, 4, false);
  append_uint(&mut out, 0, 4, false);
  // cmd 0: LC_SEGMENT_64 @32
  append_uint(&mut out, 0x19, 4, false);
  append_uint(&mut out, 152, 4, false);
  append_name16(&mut out, "__TEXT");
  append_uint(&mut out, 0x100000000, 8, false);
  append_uint(&mut out, 0x4000, 8, false);
  append_uint(&mut out, 0, 8, false);
  append_uint(&mut out, 416, 8, false);
  append_uint(&mut out, 5, 4, false);
  append_uint(&mut out, 5, 4, false);
  append_uint(&mut out, 1, 4, false);
  append_uint(&mut out, 0, 4, false);
  // section @104 (80 bytes)
  append_name16(&mut out, "__text");
  append_name16(&mut out, "__TEXT");
  append_uint(&mut out, 0x100001000, 8, false);
  append_uint(&mut out, 0x20, 8, false);
  append_uint(&mut out, 32, 4, false);
  append_uint(&mut out, 4, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0x80000400, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  // cmd 1: LC_LOAD_DYLIB @184 (size 56, name 26 chars + NUL + 5 pad)
  append_uint(&mut out, 0xC, 4, false);
  append_uint(&mut out, 56, 4, false);
  append_uint(&mut out, 24, 4, false);
  append_uint(&mut out, 2, 4, false);
  append_uint(&mut out, 0x00050000, 4, false);
  append_uint(&mut out, 0x00010000, 4, false);
  append_ascii(&mut out, "/usr/lib/libSystem.B.dylib");
  out.push(0 as UInt8);
  append_zeros(&mut out, 5);
  // cmd 2: LC_UUID @240 (16 uuid bytes 1..16)
  append_uint(&mut out, 0x1B, 4, false);
  append_uint(&mut out, 24, 4, false);
  var k = 1;
  while k <= 16 {
    out.push(k as UInt8);
    k = k + 1;
  }
  // cmd 3: LC_MAIN @264
  append_uint(&mut out, 0x80000028, 4, false);
  append_uint(&mut out, 24, 4, false);
  append_uint(&mut out, 0x1000, 8, false);
  append_uint(&mut out, 0x800000, 8, false);
  // cmd 4: LC_CODE_SIGNATURE @288
  append_uint(&mut out, 0x1D, 4, false);
  append_uint(&mut out, 16, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  // cmd 5: LC_BUILD_VERSION @304
  append_uint(&mut out, 0x32, 4, false);
  append_uint(&mut out, 24, 4, false);
  append_uint(&mut out, 1, 4, false);
  append_uint(&mut out, 0x000D0100, 4, false);
  append_uint(&mut out, 0x000E0000, 4, false);
  append_uint(&mut out, 0, 4, false);
  // cmd 6: LC_SOURCE_VERSION @328
  append_uint(&mut out, 0x2A, 4, false);
  append_uint(&mut out, 16, 4, false);
  append_uint(&mut out, 0x0001000200030004, 8, false);
  // cmd 7: unknown 0x77 @344
  append_uint(&mut out, 0x77, 4, false);
  append_uint(&mut out, 8, 4, false);
  // cmd 8: LC_VERSION_MIN_MACOSX @352
  append_uint(&mut out, 0x24, 4, false);
  append_uint(&mut out, 16, 4, false);
  append_uint(&mut out, 0x000A0F00, 4, false);
  append_uint(&mut out, 0x000B0000, 4, false);
  // cmd 9: LC_SYMTAB @368
  append_uint(&mut out, 0x2, 4, false);
  append_uint(&mut out, 24, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  // cmd 10: LC_ENCRYPTION_INFO_64 @392
  append_uint(&mut out, 0x2C, 4, false);
  append_uint(&mut out, 24, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  return out;
}

// 244-byte 32-bit little-endian fixture with 2 load commands:
//   28   LC_SEGMENT (__TEXT, 2 sections __text/__data) size 192
//   220  LC_UUID size 24
fn fx32le() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_uint(&mut out, 0xFEEDFACE, 4, false);
  append_uint(&mut out, 7, 4, false);
  append_uint(&mut out, 3, 4, false);
  append_uint(&mut out, 1, 4, false);
  append_uint(&mut out, 2, 4, false);
  append_uint(&mut out, 216, 4, false);
  append_uint(&mut out, 0x2000, 4, false);
  // cmd 0: LC_SEGMENT @28
  append_uint(&mut out, 0x1, 4, false);
  append_uint(&mut out, 192, 4, false);
  append_name16(&mut out, "__TEXT");
  append_uint(&mut out, 0x1000, 4, false);
  append_uint(&mut out, 0x1000, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 244, 4, false);
  append_uint(&mut out, 7, 4, false);
  append_uint(&mut out, 3, 4, false);
  append_uint(&mut out, 2, 4, false);
  append_uint(&mut out, 0, 4, false);
  // section 0 @84 (68 bytes)
  append_name16(&mut out, "__text");
  append_name16(&mut out, "__TEXT");
  append_uint(&mut out, 0x2000, 4, false);
  append_uint(&mut out, 0x10, 4, false);
  append_uint(&mut out, 16, 4, false);
  append_uint(&mut out, 2, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0x80000400, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  // section 1 @152 (68 bytes)
  append_name16(&mut out, "__data");
  append_name16(&mut out, "__DATA");
  append_uint(&mut out, 0x3000, 4, false);
  append_uint(&mut out, 0x10, 4, false);
  append_uint(&mut out, 32, 4, false);
  append_uint(&mut out, 2, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  append_uint(&mut out, 0, 4, false);
  // cmd 1: LC_UUID @220
  append_uint(&mut out, 0x1B, 4, false);
  append_uint(&mut out, 24, 4, false);
  var k = 1;
  while k <= 16 {
    out.push(k as UInt8);
    k = k + 1;
  }
  return out;
}

// 84-byte 32-bit big-endian fixture (PowerPC): one empty LC_SEGMENT.
fn fx32be() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_uint(&mut out, 0xFEEDFACE, 4, true);
  append_uint(&mut out, 18, 4, true);
  append_uint(&mut out, 0, 4, true);
  append_uint(&mut out, 2, 4, true);
  append_uint(&mut out, 1, 4, true);
  append_uint(&mut out, 56, 4, true);
  append_uint(&mut out, 0x85, 4, true);
  append_uint(&mut out, 0x1, 4, true);
  append_uint(&mut out, 56, 4, true);
  append_name16(&mut out, "__TEXT");
  append_uint(&mut out, 0x1000, 4, true);
  append_uint(&mut out, 0x1000, 4, true);
  append_uint(&mut out, 0, 4, true);
  append_uint(&mut out, 84, 4, true);
  append_uint(&mut out, 5, 4, true);
  append_uint(&mut out, 5, 4, true);
  append_uint(&mut out, 0, 4, true);
  append_uint(&mut out, 0, 4, true);
  return out;
}

// 16412-byte big-endian fat fixture: x86_64 slice @4096 (align 12, 4 KB)
// holding fx64le_min and arm64 slice @16384 (align 14, 16 KB) holding
// fx32le_min.
fn fx_fat_be() -> Vec[UInt8] {
  var v = zeros(16412);
  put_uint(&mut v, 0, 0xCAFEBABE, 4, true);
  put_uint(&mut v, 4, 2, 4, true);
  put_uint(&mut v, 8, 0x01000007, 4, true);
  put_uint(&mut v, 12, 3, 4, true);
  put_uint(&mut v, 16, 4096, 4, true);
  put_uint(&mut v, 20, 32, 4, true);
  put_uint(&mut v, 24, 12, 4, true);
  put_uint(&mut v, 28, 0x0100000C, 4, true);
  put_uint(&mut v, 32, 0, 4, true);
  put_uint(&mut v, 36, 16384, 4, true);
  put_uint(&mut v, 40, 28, 4, true);
  put_uint(&mut v, 44, 14, 4, true);
  let s0 = fx64le_min();
  put_bytes(&mut v, 4096, &s0);
  let s1 = fx32le_min();
  put_bytes(&mut v, 16384, &s1);
  return v;
}

// 4128-byte little-endian (FAT_CIGAM) fat fixture with one x86_64 slice.
fn fx_fat_le() -> Vec[UInt8] {
  var v = zeros(4128);
  put_uint(&mut v, 0, 0xCAFEBABE, 4, false);
  put_uint(&mut v, 4, 1, 4, false);
  put_uint(&mut v, 8, 0x01000007, 4, false);
  put_uint(&mut v, 12, 3, 4, false);
  put_uint(&mut v, 16, 4096, 4, false);
  put_uint(&mut v, 20, 32, 4, false);
  put_uint(&mut v, 24, 12, 4, false);
  let s0 = fx64le_min();
  put_bytes(&mut v, 4096, &s0);
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let v64 = fx64le();
  let v32 = fx32le();
  let vbe = fx32be();
  let vfat = fx_fat_be();
  let vfatle = fx_fat_le();
  var ok = apple_format(&v64) == APPLE_FORMAT_MACHO64_LE;
  if apple_format(&v32) != APPLE_FORMAT_MACHO32_LE { ok = false; }
  if apple_format(&vbe) != APPLE_FORMAT_MACHO32_BE { ok = false; }
  if apple_format(&vfat) != APPLE_FORMAT_FAT_BE { ok = false; }
  if apple_format(&vfatle) != APPLE_FORMAT_FAT_LE { ok = false; }
  var short = Vec[UInt8].new();
  short.push(0xCE as UInt8);
  short.push(0xFA as UInt8);
  if apple_format(&short) != APPLE_FORMAT_UNKNOWN { ok = false; }
  var junk = zeros(8);
  put_uint(&mut junk, 0, 0x11223344, 4, true);
  if apple_format(&junk) != APPLE_FORMAT_UNKNOWN { ok = false; }
  var f64 = zeros(4);
  put_uint(&mut f64, 0, 0xCAFEBABF, 4, true);
  if apple_format(&f64) != APPLE_FORMAT_FAT64_BE { ok = false; }
  var f64le = zeros(4);
  put_uint(&mut f64le, 0, 0xCAFEBABF, 4, false);
  if apple_format(&f64le) != APPLE_FORMAT_FAT64_LE { ok = false; }
  if apple_format_bits(APPLE_FORMAT_MACHO64_LE) != 64 { ok = false; }
  if apple_format_bits(APPLE_FORMAT_MACHO32_BE) != 32 { ok = false; }
  if apple_format_bits(APPLE_FORMAT_FAT_BE) != 0 { ok = false; }
  if apple_format_endianness(APPLE_FORMAT_MACHO64_LE) != APPLE_ENDIAN_LE { ok = false; }
  if apple_format_endianness(APPLE_FORMAT_MACHO32_BE) != APPLE_ENDIAN_BE { ok = false; }
  if apple_format_endianness(APPLE_FORMAT_UNKNOWN) != 0 { ok = false; }
  if !str_eq(apple_format_name(APPLE_FORMAT_MACHO64_LE), "macho64-le") { ok = false; }
  if !str_eq(apple_format_name(APPLE_FORMAT_FAT_BE), "fat-be") { ok = false; }
  if !str_eq(apple_format_name(APPLE_FORMAT_UNKNOWN), "unknown") { ok = false; }
  if !apple_is_fat_format(APPLE_FORMAT_FAT_LE) { ok = false; }
  if apple_is_fat_format(APPLE_FORMAT_MACHO32_LE) { ok = false; }
  if !apple_is_thin_format(APPLE_FORMAT_MACHO32_BE) { ok = false; }
  if apple_is_thin_format(APPLE_FORMAT_FAT_BE) { ok = false; }
  return assert(ok, "every magic is detected with class and byte order");
}

fn t2() -> TestResult {
  let v = fx64le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "64-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = macho_magic(&f) == APPLE_MH_CIGAM_64;
  if macho_bits(&f) != 64 { ok = false; }
  if macho_endianness(&f) != APPLE_ENDIAN_LE { ok = false; }
  if macho_cputype(&f) != APPLE_CPU_TYPE_X86_64 { ok = false; }
  if macho_cpusubtype(&f) != 3 { ok = false; }
  if macho_filetype(&f) != APPLE_MH_EXECUTE { ok = false; }
  if macho_ncmds(&f) != 11 { ok = false; }
  if macho_sizeofcmds(&f) != 384 { ok = false; }
  if macho_flags(&f) != 0x200085 { ok = false; }
  if macho_reserved(&f) != 0 { ok = false; }
  if macho_header_size(&f) != 32 { ok = false; }
  if !str_eq(macho_file_type_name(macho_filetype(&f)), "executable") { ok = false; }
  if !str_eq(macho_cpu_name(macho_cputype(&f)), "x86_64") { ok = false; }
  return assert(ok, "mach_header_64 scalars and names are pinned");
}

fn t3() -> TestResult {
  let v = fx64le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "64-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = macho_has_flag(&f, APPLE_MH_NOUNDEFS);
  if !macho_has_flag(&f, APPLE_MH_DYLDLINK) { ok = false; }
  if !macho_has_flag(&f, APPLE_MH_TWOLEVEL) { ok = false; }
  if !macho_has_flag(&f, APPLE_MH_PIE) { ok = false; }
  if macho_has_flag(&f, APPLE_MH_FORCE_FLAT) { ok = false; }
  if macho_has_flag(&f, APPLE_MH_WEAK_DEFINES) { ok = false; }
  if macho_has_flag(&f, APPLE_MH_DYLIB_IN_CACHE) { ok = false; }
  let v32 = fx32le();
  let r32 = macho_parse(&v32);
  if !r32.is_ok { ok = false; } else {
    let f32: MachOFile = r32.value;
    if !macho_has_flag(&f32, APPLE_MH_SUBSECTIONS_VIA_SYMBOLS) { ok = false; }
    if macho_has_flag(&f32, APPLE_MH_PIE) { ok = false; }
  }
  return assert(ok, "header flags decode bit by bit (NOUNDEFS/DYLDLINK/TWOLEVEL/PIE)");
}

fn t4() -> TestResult {
  let v = fx64le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "64-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = macho_command_count(&f) == 11;
  if !int_is(macho_command_field(&f, 0, APPLE_LC_FIELD_CMD), 0x19) { ok = false; }
  if !int_is(macho_command_field(&f, 0, APPLE_LC_FIELD_SIZE), 152) { ok = false; }
  if !int_is(macho_command_field(&f, 0, APPLE_LC_FIELD_OFFSET), 32) { ok = false; }
  if !int_is(macho_command_field(&f, 0, APPLE_LC_FIELD_KIND), APPLE_LCK_SEGMENT_64) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_CMD), APPLE_LC_LOAD_DYLIB) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_SIZE), 56) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_OFFSET), 184) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_KIND), APPLE_LCK_DYLIB) { ok = false; }
  if !int_is(macho_command_field(&f, 2, APPLE_LC_FIELD_CMD), 0x1B) { ok = false; }
  if !int_is(macho_command_field(&f, 2, APPLE_LC_FIELD_KIND), APPLE_LCK_UUID) { ok = false; }
  if !int_is(macho_command_field(&f, 3, APPLE_LC_FIELD_CMD), APPLE_LC_MAIN) { ok = false; }
  if !int_is(macho_command_field(&f, 3, APPLE_LC_FIELD_KIND), APPLE_LCK_MAIN) { ok = false; }
  if !int_is(macho_command_field(&f, 4, APPLE_LC_FIELD_CMD), APPLE_LC_CODE_SIGNATURE) { ok = false; }
  if !int_is(macho_command_field(&f, 4, APPLE_LC_FIELD_KIND), APPLE_LCK_LINKEDIT_DATA) { ok = false; }
  if !int_is(macho_command_field(&f, 5, APPLE_LC_FIELD_CMD), APPLE_LC_BUILD_VERSION) { ok = false; }
  if !int_is(macho_command_field(&f, 5, APPLE_LC_FIELD_KIND), APPLE_LCK_BUILD_VERSION) { ok = false; }
  if !int_is(macho_command_field(&f, 6, APPLE_LC_FIELD_CMD), APPLE_LC_SOURCE_VERSION) { ok = false; }
  if !int_is(macho_command_field(&f, 6, APPLE_LC_FIELD_KIND), APPLE_LCK_SOURCE_VERSION) { ok = false; }
  if !int_is(macho_command_field(&f, 7, APPLE_LC_FIELD_CMD), 0x77) { ok = false; }
  if !int_is(macho_command_field(&f, 7, APPLE_LC_FIELD_KIND), APPLE_LCK_UNKNOWN) { ok = false; }
  if !int_is(macho_command_field(&f, 8, APPLE_LC_FIELD_CMD), APPLE_LC_VERSION_MIN_MACOSX) { ok = false; }
  if !int_is(macho_command_field(&f, 8, APPLE_LC_FIELD_KIND), APPLE_LCK_VERSION_MIN) { ok = false; }
  if !int_is(macho_command_field(&f, 9, APPLE_LC_FIELD_CMD), APPLE_LC_SYMTAB) { ok = false; }
  if !int_is(macho_command_field(&f, 9, APPLE_LC_FIELD_KIND), APPLE_LCK_SYMTAB) { ok = false; }
  if !int_is(macho_command_field(&f, 10, APPLE_LC_FIELD_CMD), APPLE_LC_ENCRYPTION_INFO_64) { ok = false; }
  if !int_is(macho_command_field(&f, 10, APPLE_LC_FIELD_KIND), APPLE_LCK_ENCRYPTION_INFO) { ok = false; }
  return assert(ok, "load-command walk pins cmd/cmdsize/offset/kind for all 11 commands");
}

fn t5() -> TestResult {
  let v = fx64le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "64-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = macho_segment_count(&f) == 1;
  if macho_section_count(&f) != 1 { ok = false; }
  if !str_is(macho_segment_name(&f, 0), "__TEXT") { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_CMD_INDEX), 0) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_VMADDR), 0x100000000) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_VMSIZE), 0x4000) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_FILEOFF), 0) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_FILESIZE), 416) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_MAXPROT), 5) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_INITPROT), 5) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_NSECTS), 1) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_FLAGS), 0) { ok = false; }
  if !str_is(macho_section_name(&f, 0), "__text") { ok = false; }
  if !str_is(macho_section_segment_name(&f, 0), "__TEXT") { ok = false; }
  if !int_is(macho_section_field(&f, 0, APPLE_SEC_FIELD_SEG_INDEX), 0) { ok = false; }
  if !int_is(macho_section_field(&f, 0, APPLE_SEC_FIELD_ADDR), 0x100001000) { ok = false; }
  if !int_is(macho_section_field(&f, 0, APPLE_SEC_FIELD_SIZE), 0x20) { ok = false; }
  if !int_is(macho_section_field(&f, 0, APPLE_SEC_FIELD_OFFSET), 32) { ok = false; }
  if !int_is(macho_section_field(&f, 0, APPLE_SEC_FIELD_ALIGN), 4) { ok = false; }
  if !int_is(macho_section_field(&f, 0, APPLE_SEC_FIELD_FLAGS), 0x80000400) { ok = false; }
  if !str_eq(macho_prot_text(5), "r-x") { ok = false; }
  if !str_eq(macho_prot_text(7), "rwx") { ok = false; }
  if !str_eq(macho_prot_text(0), "---") { ok = false; }
  if !str_eq(macho_prot_text(4), "--x") { ok = false; }
  if macho_prot_bits(5) != 5 { ok = false; }
  return assert(ok, "LC_SEGMENT_64 and its section record decode field by field");
}

fn t6() -> TestResult {
  let v = fx64le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "64-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = str_is(macho_command_name(&f, 1), "/usr/lib/libSystem.B.dylib");
  if !str_is(macho_command_name(&f, 0), "") { ok = false; }
  if !str_is(macho_command_name(&f, 2), "") { ok = false; }
  if !str_is(macho_command_name(&f, 3), "") { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_NAME_OFFSET), 24) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_VAL1), 24) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_VAL2), 2) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_VAL3), 0x00050000) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_VAL4), 0x00010000) { ok = false; }
  if !str_eq(macho_version_text(0x00050000), "5.0.0") { ok = false; }
  // The same payload decoded as LC_LOAD_WEAK_DYLIB and LC_REEXPORT_DYLIB.
  var vw = fx64le();
  put_uint(&mut vw, 184, 0x80000018, 4, false);
  let rw = macho_parse(&vw);
  if !rw.is_ok { ok = false; } else {
    let fw: MachOFile = rw.value;
    if !int_is(macho_command_field(&fw, 1, APPLE_LC_FIELD_KIND), APPLE_LCK_DYLIB) { ok = false; }
    if !str_is(macho_command_name(&fw, 1), "/usr/lib/libSystem.B.dylib") { ok = false; }
  }
  var vr = fx64le();
  put_uint(&mut vr, 184, 0x8000001F, 4, false);
  let rr = macho_parse(&vr);
  if !rr.is_ok { ok = false; } else {
    let fr: MachOFile = rr.value;
    if !int_is(macho_command_field(&fr, 1, APPLE_LC_FIELD_KIND), APPLE_LCK_DYLIB) { ok = false; }
    if !str_is(macho_command_name(&fr, 1), "/usr/lib/libSystem.B.dylib") { ok = false; }
  }
  return assert(ok, "dylib-family commands decode the lc_str name and versions");
}

fn t7() -> TestResult {
  let v = fx64le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "64-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = true;
  var k = 0;
  while k < 16 {
    if !int_is(macho_uuid_byte(&f, 2, k), k + 1) {
      ok = false;
    }
    k = k + 1;
  }
  if !str_is(macho_uuid_text(&f, 2), "01020304-0506-0708-090a-0b0c0d0e0f10") { ok = false; }
  if !int_is(macho_command_field(&f, 2, APPLE_LC_FIELD_UUID_LEN), 16) { ok = false; }
  if !int_is(macho_command_field(&f, 0, APPLE_LC_FIELD_UUID_START), -1) { ok = false; }
  if !int_err_is(macho_uuid_byte(&f, 0, 0), "apple: no uuid on this command") { ok = false; }
  if !str_err_is(macho_uuid_text(&f, 0), "apple: no uuid on this command") { ok = false; }
  if !int_err_is(macho_uuid_byte(&f, 2, 16), "apple: index out of range") { ok = false; }
  return assert(ok, "LC_UUID exposes its 16 raw bytes and canonical text");
}

fn t8() -> TestResult {
  let v = fx64le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "64-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = int_is(macho_command_field(&f, 3, APPLE_LC_FIELD_VAL1), 0x1000);
  if !int_is(macho_command_field(&f, 3, APPLE_LC_FIELD_VAL2), 0x800000) { ok = false; }
  if !int_is(macho_command_field(&f, 4, APPLE_LC_FIELD_VAL1), 0) { ok = false; }
  if !int_is(macho_command_field(&f, 4, APPLE_LC_FIELD_VAL2), 0) { ok = false; }
  if !int_is(macho_command_field(&f, 5, APPLE_LC_FIELD_VAL1), APPLE_PLATFORM_MACOS) { ok = false; }
  if !int_is(macho_command_field(&f, 5, APPLE_LC_FIELD_VAL2), 0x000D0100) { ok = false; }
  if !int_is(macho_command_field(&f, 5, APPLE_LC_FIELD_VAL3), 0x000E0000) { ok = false; }
  if !int_is(macho_command_field(&f, 5, APPLE_LC_FIELD_VAL4), 0) { ok = false; }
  if !str_eq(macho_platform_name(APPLE_PLATFORM_MACOS), "macos") { ok = false; }
  if !str_eq(macho_platform_name(APPLE_PLATFORM_VISIONOS_SIMULATOR), "visionos-simulator") { ok = false; }
  if !str_eq(macho_platform_name(99), "unknown") { ok = false; }
  if !str_eq(macho_version_text(0x000D0100), "13.1.0") { ok = false; }
  if !str_eq(macho_version_text(0x000E0000), "14.0.0") { ok = false; }
  if !int_is(macho_command_field(&f, 6, APPLE_LC_FIELD_VAL1), 0x0001000200030004) { ok = false; }
  if !int_is(macho_command_field(&f, 8, APPLE_LC_FIELD_VAL1), 0x000A0F00) { ok = false; }
  if !int_is(macho_command_field(&f, 8, APPLE_LC_FIELD_VAL2), 0x000B0000) { ok = false; }
  if !str_eq(macho_version_text(0x000A0F00), "10.15.0") { ok = false; }
  if !str_eq(macho_version_text(0x000B0000), "11.0.0") { ok = false; }
  if !int_is(macho_command_field(&f, 9, APPLE_LC_FIELD_VAL1), 0) { ok = false; }
  if !int_is(macho_command_field(&f, 9, APPLE_LC_FIELD_VAL4), 0) { ok = false; }
  if !int_is(macho_command_field(&f, 10, APPLE_LC_FIELD_VAL1), 0) { ok = false; }
  if !int_is(macho_command_field(&f, 10, APPLE_LC_FIELD_VAL3), 0) { ok = false; }
  return assert(ok, "MAIN/code-signature/build-version/source/version_min/symtab/encryption values");
}

fn t9() -> TestResult {
  let v = fx32le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "32-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = macho_magic(&f) == APPLE_MH_CIGAM;
  if macho_bits(&f) != 32 { ok = false; }
  if macho_endianness(&f) != APPLE_ENDIAN_LE { ok = false; }
  if macho_cputype(&f) != APPLE_CPU_TYPE_X86 { ok = false; }
  if macho_filetype(&f) != APPLE_MH_OBJECT { ok = false; }
  if !str_eq(macho_file_type_name(macho_filetype(&f)), "object") { ok = false; }
  if macho_ncmds(&f) != 2 { ok = false; }
  if macho_sizeofcmds(&f) != 216 { ok = false; }
  if macho_header_size(&f) != 28 { ok = false; }
  if macho_command_count(&f) != 2 { ok = false; }
  if macho_segment_count(&f) != 1 { ok = false; }
  if macho_section_count(&f) != 2 { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_VMADDR), 0x1000) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_VMSIZE), 0x1000) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_FILESIZE), 244) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_MAXPROT), 7) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_INITPROT), 3) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_NSECTS), 2) { ok = false; }
  if !str_is(macho_section_name(&f, 0), "__text") { ok = false; }
  if !str_is(macho_section_name(&f, 1), "__data") { ok = false; }
  if !str_is(macho_section_segment_name(&f, 1), "__DATA") { ok = false; }
  if !int_is(macho_section_field(&f, 0, APPLE_SEC_FIELD_ADDR), 0x2000) { ok = false; }
  if !int_is(macho_section_field(&f, 0, APPLE_SEC_FIELD_OFFSET), 16) { ok = false; }
  if !int_is(macho_section_field(&f, 1, APPLE_SEC_FIELD_SIZE), 0x10) { ok = false; }
  if !int_is(macho_section_field(&f, 1, APPLE_SEC_FIELD_OFFSET), 32) { ok = false; }
  if !int_is(macho_command_field(&f, 1, APPLE_LC_FIELD_KIND), APPLE_LCK_UUID) { ok = false; }
  if !int_is(macho_uuid_byte(&f, 1, 0), 1) { ok = false; }
  if !int_is(macho_uuid_byte(&f, 1, 15), 16) { ok = false; }
  if !str_eq(macho_prot_text(7), "rwx") { ok = false; }
  if !str_eq(macho_prot_text(3), "rw-") { ok = false; }
  return assert(ok, "32-bit LE LC_SEGMENT sections and LC_UUID decode");
}

fn t10() -> TestResult {
  let v = fx32be();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "32-bit BE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = macho_magic(&f) == APPLE_MH_MAGIC;
  if macho_bits(&f) != 32 { ok = false; }
  if macho_endianness(&f) != APPLE_ENDIAN_BE { ok = false; }
  if macho_cputype(&f) != APPLE_CPU_TYPE_PPC { ok = false; }
  if !str_eq(macho_cpu_name(macho_cputype(&f)), "ppc") { ok = false; }
  if macho_segment_count(&f) != 1 { ok = false; }
  if !str_is(macho_segment_name(&f, 0), "__TEXT") { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_VMADDR), 0x1000) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_FILESIZE), 84) { ok = false; }
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_NSECTS), 0) { ok = false; }
  if macho_section_count(&f) != 0 { ok = false; }
  if macho_cpu_class(APPLE_CPU_TYPE_X86) != APPLE_CPU_CLASS_X86 { ok = false; }
  if macho_cpu_class(APPLE_CPU_TYPE_X86_64) != APPLE_CPU_CLASS_X86_64 { ok = false; }
  if macho_cpu_class(APPLE_CPU_TYPE_ARM) != APPLE_CPU_CLASS_ARM { ok = false; }
  if macho_cpu_class(APPLE_CPU_TYPE_ARM64) != APPLE_CPU_CLASS_ARM64 { ok = false; }
  if macho_cpu_class(APPLE_CPU_TYPE_ARM64_32) != APPLE_CPU_CLASS_ARM64_32 { ok = false; }
  if macho_cpu_class(APPLE_CPU_TYPE_PPC) != APPLE_CPU_CLASS_PPC { ok = false; }
  if macho_cpu_class(APPLE_CPU_TYPE_PPC64) != APPLE_CPU_CLASS_PPC64 { ok = false; }
  if macho_cpu_class(99) != APPLE_CPU_CLASS_UNKNOWN { ok = false; }
  if !str_eq(macho_cpu_name(APPLE_CPU_TYPE_ARM64_32), "arm64_32") { ok = false; }
  if !str_eq(macho_cpu_name(99), "unknown") { ok = false; }
  return assert(ok, "big-endian decoding and every cputype classification");
}

fn t11() -> TestResult {
  var tiny = Vec[UInt8].new();
  tiny.push(0xCF as UInt8);
  tiny.push(0xFA as UInt8);
  let r1 = macho_parse(&tiny);
  var ok = macho_err_is(r1, "apple: truncated magic at 0");
  var junk = zeros(16);
  put_uint(&mut junk, 0, 0xDEADBEEF, 4, true);
  if !macho_err_is(macho_parse(&junk), "apple: bad magic at 0") { ok = false; }
  var short64 = zeros(16);
  put_uint(&mut short64, 0, 0xFEEDFACF, 4, false);
  if !macho_err_is(macho_parse(&short64), "apple: truncated header at 0") { ok = false; }
  var v1 = fx64le();
  put_uint(&mut v1, 20, 1000, 4, false);
  if !macho_err_is(macho_parse(&v1), "apple: sizeofcmds out of bounds at 20") { ok = false; }
  var v2 = fx32le();
  put_uint(&mut v2, 20, 1000, 4, false);
  if !macho_err_is(macho_parse(&v2), "apple: sizeofcmds out of bounds at 20") { ok = false; }
  let fat = fx_fat_be();
  if !macho_err_is(macho_parse(&fat), "apple: fat header where a thin Mach-O was expected at 0") { ok = false; }
  var f64 = zeros(8);
  put_uint(&mut f64, 0, 0xCAFEBABF, 4, true);
  if !macho_err_is(macho_parse(&f64), "apple: fat header where a thin Mach-O was expected at 0") { ok = false; }
  return assert(ok, "header truncation, bad magic, sizeofcmds bound and fat-in-thin");
}

fn t12() -> TestResult {
  var v1 = head64(1, 8);
  append_uint(&mut v1, 0x77, 4, false);
  append_uint(&mut v1, 4, 4, false);
  var ok = macho_err_is(macho_parse(&v1), "apple: bad cmdsize at 36");
  var v2 = head64(1, 8);
  append_uint(&mut v2, 0x77, 4, false);
  append_uint(&mut v2, 12, 4, false);
  if !macho_err_is(macho_parse(&v2), "apple: misaligned cmdsize at 36") { ok = false; }
  var v3 = head64(1, 8);
  append_uint(&mut v3, 0x77, 4, false);
  append_uint(&mut v3, 16, 4, false);
  append_zeros(&mut v3, 8);
  if !macho_err_is(macho_parse(&v3), "apple: command exceeds sizeofcmds at 36") { ok = false; }
  var v4 = head64(1, 16);
  append_uint(&mut v4, 0x77, 4, false);
  append_uint(&mut v4, 8, 4, false);
  append_zeros(&mut v4, 8);
  if !macho_err_is(macho_parse(&v4), "apple: load commands do not fill sizeofcmds at 40") { ok = false; }
  var v5 = head64(2, 16);
  append_uint(&mut v5, 0x77, 4, false);
  append_uint(&mut v5, 8, 4, false);
  append_uint(&mut v5, 0x78, 4, false);
  append_uint(&mut v5, 8, 4, false);
  let r5 = macho_parse(&v5);
  if !r5.is_ok { ok = false; } else {
    let f5: MachOFile = r5.value;
    if macho_command_count(&f5) != 2 { ok = false; }
    if !int_is(macho_command_field(&f5, 1, APPLE_LC_FIELD_CMD), 0x78) { ok = false; }
  }
  return assert(ok, "cmdsize must be >= 8, aligned, inside sizeofcmds and fill it exactly");
}

fn t13() -> TestResult {
  var v = head64(2, 12);
  append_uint(&mut v, 0x77, 4, false);
  append_uint(&mut v, 8, 4, false);
  append_uint(&mut v, 0x78, 4, false);
  var ok = macho_err_is(macho_parse(&v), "apple: truncated load command at 40");
  var v2 = fx64le_min();
  let r2 = macho_parse(&v2);
  if !r2.is_ok { ok = false; } else {
    let f2: MachOFile = r2.value;
    if macho_command_count(&f2) != 0 { ok = false; }
    if macho_sizeofcmds(&f2) != 0 { ok = false; }
  }
  return assert(ok, "a command that crosses sizeofcmds is a truncation; empty tables parse");
}

fn t14() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 96, 100, 4, false);
  var ok = macho_err_is(macho_parse(&v1), "apple: segment sections exceed cmdsize at 96");
  var v2 = fx64le();
  put_uint(&mut v2, 80, 100000, 8, false);
  if !macho_err_is(macho_parse(&v2), "apple: segment data out of bounds at 32") { ok = false; }
  var v3 = fx64le();
  put_uint(&mut v3, 72, -1, 8, false);
  if !macho_err_is(macho_parse(&v3), "apple: segment data out of bounds at 32") { ok = false; }
  var v4 = fx64le();
  put_uint(&mut v4, 144, 100000, 8, false);
  if !macho_err_is(macho_parse(&v4), "apple: section data out of bounds at 104") { ok = false; }
  var v5 = fx64le();
  put_uint(&mut v5, 156, 40, 4, false);
  if !macho_err_is(macho_parse(&v5), "apple: bad section alignment at 156") { ok = false; }
  var v6 = fx64le();
  put_u8(&mut v6, 40, 1);
  if !macho_err_is(macho_parse(&v6), "apple: name not printable ASCII at 40") { ok = false; }
  var v7 = fx64le();
  put_u8(&mut v7, 104, 200);
  if !macho_err_is(macho_parse(&v7), "apple: name not printable ASCII at 104") { ok = false; }
  var v8 = fx64le();
  put_uint(&mut v8, 168, 1, 4, false);
  put_uint(&mut v8, 144, 100000, 8, false);
  put_uint(&mut v8, 152, 100000, 4, false);
  let r8 = macho_parse(&v8);
  if !r8.is_ok { ok = false; } else {
    let f8: MachOFile = r8.value;
    if !int_is(macho_section_field(&f8, 0, APPLE_SEC_FIELD_SIZE), 100000) { ok = false; }
    if !int_is(macho_section_field(&f8, 0, APPLE_SEC_FIELD_FLAGS), 1) { ok = false; }
  }
  return assert(ok, "segment/section spans and names validate; S_ZEROFILL sections are exempt");
}

fn t15() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 192, 10, 4, false);
  var ok = macho_err_is(macho_parse(&v1), "apple: bad name offset at 192");
  var v2 = fx64le();
  put_uint(&mut v2, 192, 56, 4, false);
  if !macho_err_is(macho_parse(&v2), "apple: bad name offset at 192") { ok = false; }
  var v3 = fx64le();
  var k = 234;
  while k <= 239 {
    put_u8(&mut v3, k, 122);
    k = k + 1;
  }
  if !macho_err_is(macho_parse(&v3), "apple: name not NUL-terminated at 208") { ok = false; }
  var v4 = fx64le();
  put_u8(&mut v4, 210, 7);
  if !macho_err_is(macho_parse(&v4), "apple: name not printable ASCII at 210") { ok = false; }
  return assert(ok, "dylib name offset bounds, NUL termination and printable ASCII");
}

fn t16() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 244, 16, 4, false);
  var ok = macho_err_is(macho_parse(&v1), "apple: bad LC_UUID size at 240");
  var v2 = fx64le();
  put_uint(&mut v2, 268, 16, 4, false);
  if !macho_err_is(macho_parse(&v2), "apple: bad LC_MAIN size at 264") { ok = false; }
  var v3 = fx64le();
  put_uint(&mut v3, 292, 8, 4, false);
  if !macho_err_is(macho_parse(&v3), "apple: bad linkedit command size at 288") { ok = false; }
  var v4 = fx64le();
  put_uint(&mut v4, 296, 300, 4, false);
  put_uint(&mut v4, 300, 200, 4, false);
  if !macho_err_is(macho_parse(&v4), "apple: linkedit data out of bounds at 296") { ok = false; }
  var v5 = fx64le();
  put_uint(&mut v5, 324, 5, 4, false);
  if !macho_err_is(macho_parse(&v5), "apple: build version tools exceed cmdsize at 324") { ok = false; }
  var v6 = fx64le();
  put_uint(&mut v6, 356, 8, 4, false);
  if !macho_err_is(macho_parse(&v6), "apple: bad LC_VERSION_MIN size at 352") { ok = false; }
  var v7 = fx64le();
  put_uint(&mut v7, 372, 16, 4, false);
  if !macho_err_is(macho_parse(&v7), "apple: bad LC_SYMTAB size at 368") { ok = false; }
  var v8 = fx64le();
  put_uint(&mut v8, 332, 8, 4, false);
  if !macho_err_is(macho_parse(&v8), "apple: bad LC_SOURCE_VERSION size at 328") { ok = false; }
  var v9 = fx64le();
  put_uint(&mut v9, 396, 16, 4, false);
  if !macho_err_is(macho_parse(&v9), "apple: bad LC_ENCRYPTION_INFO size at 392") { ok = false; }
  return assert(ok, "fixed-size commands reject wrong cmdsize and out-of-bounds payloads");
}

fn t17() -> TestResult {
  var v = fx64le();
  put_uint(&mut v, 336, -1, 8, false);
  put_uint(&mut v, 56, -2, 8, false);
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "high-bit fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = int_is(macho_command_field(&f, 6, APPLE_LC_FIELD_VAL1), -1);
  if !int_is(macho_segment_field(&f, 0, APPLE_SEG_FIELD_VMADDR), -2) { ok = false; }
  if !str_eq(macho_version_text(-1), "?") { ok = false; }
  if !str_eq(macho_version_text(0), "0.0.0") { ok = false; }
  return assert(ok, "64-bit fields decode as raw two's-complement (bit 63 set is negative)");
}

fn t18() -> TestResult {
  let v = fx_fat_be();
  let r = fat_parse(&v);
  if !r.is_ok {
    return assert(false, "big-endian fat fixture must parse");
  }
  let f: FatFile = r.value;
  var ok = fat_magic(&f) == APPLE_FAT_MAGIC;
  if fat_endianness(&f) != APPLE_ENDIAN_BE { ok = false; }
  if fat_arch_count(&f) != 2 { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_CPUTYPE), APPLE_CPU_TYPE_X86_64) { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_CPUSUBTYPE), 3) { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_OFFSET), 4096) { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_SIZE), 32) { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_ALIGN), 12) { ok = false; }
  if !int_is(fat_arch_field(&f, 1, APPLE_FAT_FIELD_CPUTYPE), APPLE_CPU_TYPE_ARM64) { ok = false; }
  if !int_is(fat_arch_field(&f, 1, APPLE_FAT_FIELD_OFFSET), 16384) { ok = false; }
  if !int_is(fat_arch_field(&f, 1, APPLE_FAT_FIELD_SIZE), 28) { ok = false; }
  if !int_is(fat_arch_field(&f, 1, APPLE_FAT_FIELD_ALIGN), 14) { ok = false; }
  if fat_select(&f, APPLE_CPU_TYPE_X86_64) != 0 { ok = false; }
  if fat_select(&f, APPLE_CPU_TYPE_ARM64) != 1 { ok = false; }
  if fat_select(&f, APPLE_CPU_TYPE_X86) != -1 { ok = false; }
  if fat_select_subtype(&f, APPLE_CPU_TYPE_X86_64, 3) != 0 { ok = false; }
  if fat_select_subtype(&f, APPLE_CPU_TYPE_X86_64, 0) != -1 { ok = false; }
  let r0 = fat_slice_macho(&v, &f, 0);
  if !r0.is_ok { ok = false; } else {
    let m0: MachOFile = r0.value;
    if macho_bits(&m0) != 64 { ok = false; }
    if macho_cputype(&m0) != APPLE_CPU_TYPE_X86_64 { ok = false; }
  }
  let r1 = fat_slice_macho(&v, &f, 1);
  if !r1.is_ok { ok = false; } else {
    let m1: MachOFile = r1.value;
    if macho_bits(&m1) != 32 { ok = false; }
    if macho_cputype(&m1) != APPLE_CPU_TYPE_X86 { ok = false; }
  }
  let rb = fat_slice_bytes(&v, &f, 0);
  if !rb.is_ok { ok = false; } else {
    let b0: Vec[UInt8] = rb.value;
    if b0.len() != 32 { ok = false; }
  }
  return assert(ok, "big-endian fat archive slices decode, select and parse");
}

fn t19() -> TestResult {
  let v = fx_fat_le();
  let r = fat_parse(&v);
  if !r.is_ok {
    return assert(false, "little-endian fat fixture must parse");
  }
  let f: FatFile = r.value;
  var ok = fat_magic(&f) == APPLE_FAT_CIGAM;
  if fat_endianness(&f) != APPLE_ENDIAN_LE { ok = false; }
  if fat_arch_count(&f) != 1 { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_CPUTYPE), APPLE_CPU_TYPE_X86_64) { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_OFFSET), 4096) { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_SIZE), 32) { ok = false; }
  if !int_is(fat_arch_field(&f, 0, APPLE_FAT_FIELD_ALIGN), 12) { ok = false; }
  if fat_select(&f, APPLE_CPU_TYPE_X86_64) != 0 { ok = false; }
  let r0 = fat_slice_macho(&v, &f, 0);
  if !r0.is_ok { ok = false; } else {
    let m0: MachOFile = r0.value;
    if macho_bits(&m0) != 64 { ok = false; }
  }
  return assert(ok, "little-endian FAT_CIGAM archives decode");
}

fn t20() -> TestResult {
  var v1 = zeros(8);
  put_uint(&mut v1, 0, 0xCAFEBABE, 4, true);
  var ok = fat_err_is(fat_parse(&v1), "apple: bad fat arch count at 4");
  var v2 = zeros(8);
  put_uint(&mut v2, 0, 0xCAFEBABE, 4, true);
  put_uint(&mut v2, 4, 3, 4, true);
  if !fat_err_is(fat_parse(&v2), "apple: fat arch table out of bounds at 4") { ok = false; }
  var v3 = fx_fat_be();
  put_uint(&mut v3, 20, 20000, 4, true);
  if !fat_err_is(fat_parse(&v3), "apple: fat slice out of bounds at 16") { ok = false; }
  var v4 = fx_fat_be();
  put_uint(&mut v4, 16, 4097, 4, true);
  if !fat_err_is(fat_parse(&v4), "apple: misaligned fat slice at 24") { ok = false; }
  var v5 = fx_fat_be();
  put_uint(&mut v5, 16, 40, 4, true);
  put_uint(&mut v5, 24, 0, 4, true);
  if !fat_err_is(fat_parse(&v5), "apple: fat slice overlaps the arch table at 16") { ok = false; }
  var v6 = fx_fat_be();
  put_uint(&mut v6, 36, 4100, 4, true);
  put_uint(&mut v6, 44, 0, 4, true);
  if !fat_err_is(fat_parse(&v6), "apple: fat slices overlap at 36") { ok = false; }
  var v7 = zeros(8);
  put_uint(&mut v7, 0, 0xCAFEBABF, 4, true);
  if !fat_err_is(fat_parse(&v7), "apple: fat64 header unsupported at 0") { ok = false; }
  let thin = fx64le();
  if !fat_err_is(fat_parse(&thin), "apple: not a fat archive at 0") { ok = false; }
  let vfat = fx_fat_le();
  let rf = fat_parse(&vfat);
  if !rf.is_ok { ok = false; } else {
    let ff: FatFile = rf.value;
    let r8 = fat_slice_bytes(&vfat, &ff, 1);
    if !bytes_err_is(r8, "apple: index out of range") { ok = false; }
  }
  var v8 = zeros(4);
  put_uint(&mut v8, 0, 0xCAFEBABE, 4, true);
  if !fat_err_is(fat_parse(&v8), "apple: truncated fat header at 0") { ok = false; }
  return assert(ok, "fat count/table/slice bounds, alignment, overlap and fat64 rejection");
}

// A tiny valid 1-arch fat file, used where a slice index out of range needs
// a parsed FatFile (see t21).
fn fat_ok() -> FatFile {
  let v = fx_fat_le();
  let r = fat_parse(&v);
  if r.is_ok {
    return r.value;
  }
  return FatFile{
    magic: 0;
    endianness: 0;
    nfat_arch: 0;
    cputypes: Vec[Int].new();
    cpusubtypes: Vec[Int].new();
    offsets: Vec[Int].new();
    sizes: Vec[Int].new();
    aligns: Vec[Int].new();
  };
}

fn t21() -> TestResult {
  let v = fx64le();
  let r = macho_parse(&v);
  if !r.is_ok {
    return assert(false, "64-bit LE fixture must parse");
  }
  let f: MachOFile = r.value;
  var ok = int_err_is(macho_command_field(&f, 11, APPLE_LC_FIELD_CMD), "apple: index out of range");
  if !int_err_is(macho_command_field(&f, -1, APPLE_LC_FIELD_CMD), "apple: index out of range") { ok = false; }
  if !int_err_is(macho_command_field(&f, 0, 99), "apple: bad field selector") { ok = false; }
  if !str_err_is(macho_command_name(&f, 11), "apple: index out of range") { ok = false; }
  if !int_err_is(macho_segment_field(&f, 1, APPLE_SEG_FIELD_VMADDR), "apple: index out of range") { ok = false; }
  if !int_err_is(macho_segment_field(&f, 0, 99), "apple: bad field selector") { ok = false; }
  if !str_err_is(macho_segment_name(&f, 1), "apple: index out of range") { ok = false; }
  if !int_err_is(macho_section_field(&f, 1, APPLE_SEC_FIELD_ADDR), "apple: index out of range") { ok = false; }
  if !int_err_is(macho_section_field(&f, 0, 99), "apple: bad field selector") { ok = false; }
  if !str_err_is(macho_section_name(&f, 1), "apple: index out of range") { ok = false; }
  if !str_err_is(macho_section_segment_name(&f, 1), "apple: index out of range") { ok = false; }
  let fat = fat_ok();
  if !int_err_is(fat_arch_field(&fat, 1, APPLE_FAT_FIELD_CPUTYPE), "apple: index out of range") { ok = false; }
  if !int_err_is(fat_arch_field(&fat, 0, 99), "apple: bad field selector") { ok = false; }
  if !str_eq(apple_format_name(99), "unknown") { ok = false; }
  if !str_eq(apple_version(), "0.1.0") { ok = false; }
  return assert(ok, "index and field-selector errors are exact");
}

fn main() -> Int {
  io.println("=== xiom.apple conformance tests ===");
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
    io.println("xiom.apple: all tests passed");
  } else {
    io.println("xiom.apple: tests failed");
  }
  return failed;
}
