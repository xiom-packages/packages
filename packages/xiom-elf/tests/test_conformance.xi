// XIOM -- xiom.elf conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the pinned 64-byte minimal 64-bit LE builder
// and a parse-back of its output; a hand-built 64-bit LE fixture (one
// PT_LOAD program header, three section headers: NULL, .text and .shstrtab,
// with pinned fields) exercising every program/section field selector and
// the section-name string table (empty name, ".text", ".shstrtab",
// section_index lookup); a 32-bit LE fixture (32-bit program and section
// header layouts) and a 64-bit BE fixture (big-endian field decoding);
// magic/class/data/ident-version errors; header truncation; e_version,
// e_ehsize, e_phentsize and e_shentsize errors; program/section table span
// errors (including negative raw 64-bit offsets); segment file-byte bounds
// with the zero-filesz exception; section span bounds with the SHT_NOBITS
// exception; shstrndx out-of-range, SHN_XINDEX, non-STRTAB and SHN_UNDEF
// handling; name index bounds, NUL termination and printable-ASCII errors;
// and raw two's-complement decoding of high-bit 64-bit fields.
//
// Fixture bytes are assembled here byte by byte (independent of src/elf.xi)
// so the parser is exercised against bytes the test controls. Str equality
// goes through str_compare (BUG 17 discipline: `==` on a Str read from a
// Vec lowers to a pointer comparison).

module elf_tests
use xiom.io; use xiom.test;
use xiom.elf;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Generic test helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; the caller then
// fails on the length/byte checks).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
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

fn err_file_is(r: Result[ElfFile, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
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

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
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

// --------------------------------------------------
//  Byte helpers (independent of src/elf.xi)
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

// Prefix of a byte vector, used to build short source buffers.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
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

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// 64-bit little-endian fixture, 333 bytes:
//   0..63    ELF header (class 2, data 1, ET_EXEC, EM_X86_64, entry
//            0x401000, phoff 64, shoff 141, 1 phdr, 3 shdrs, shstrndx 2)
//   64..119  program header (PT_LOAD, flags 5, offset 0, vaddr/paddr
//            0x400000, filesz 64, memsz 128, align 4096)
//   120..123 .text payload ("CODE")
//   124..140 shstrtab "\0.text\0.shstrtab\0" (name 1 = ".text", 7 =
//            ".shstrtab")
//   141..204 NULL section header (all zero)
//   205..268 .text header (type 1, flags 6, addr 0x401000, offset 120,
//            size 4, link 2, info 7, addralign 16, entsize 0)
//   269..332 .shstrtab header (type 3, offset 124, size 17, addralign 1)
fn fx64le() -> Vec[UInt8] {
  var v = zeros(333);
  put_u8(&mut v, 0, 127);
  put_u8(&mut v, 1, 69);
  put_u8(&mut v, 2, 76);
  put_u8(&mut v, 3, 70);
  put_u8(&mut v, 4, 2);
  put_u8(&mut v, 5, 1);
  put_u8(&mut v, 6, 1);
  put_u8(&mut v, 7, 3);
  put_u8(&mut v, 8, 0);
  put_uint(&mut v, 16, 2, 2, false);
  put_uint(&mut v, 18, 62, 2, false);
  put_uint(&mut v, 20, 1, 4, false);
  put_uint(&mut v, 24, 0x401000, 8, false);
  put_uint(&mut v, 32, 64, 8, false);
  put_uint(&mut v, 40, 141, 8, false);
  put_uint(&mut v, 48, 0, 4, false);
  put_uint(&mut v, 52, 64, 2, false);
  put_uint(&mut v, 54, 56, 2, false);
  put_uint(&mut v, 56, 1, 2, false);
  put_uint(&mut v, 58, 64, 2, false);
  put_uint(&mut v, 60, 3, 2, false);
  put_uint(&mut v, 62, 2, 2, false);
  put_uint(&mut v, 64, 1, 4, false);
  put_uint(&mut v, 68, 5, 4, false);
  put_uint(&mut v, 72, 0, 8, false);
  put_uint(&mut v, 80, 0x400000, 8, false);
  put_uint(&mut v, 88, 0x400000, 8, false);
  put_uint(&mut v, 96, 64, 8, false);
  put_uint(&mut v, 104, 128, 8, false);
  put_uint(&mut v, 112, 4096, 8, false);
  put_u8(&mut v, 120, 67);
  put_u8(&mut v, 121, 79);
  put_u8(&mut v, 122, 68);
  put_u8(&mut v, 123, 69);
  put_u8(&mut v, 125, 46);
  put_u8(&mut v, 126, 116);
  put_u8(&mut v, 127, 101);
  put_u8(&mut v, 128, 120);
  put_u8(&mut v, 129, 116);
  put_u8(&mut v, 131, 46);
  put_u8(&mut v, 132, 115);
  put_u8(&mut v, 133, 104);
  put_u8(&mut v, 134, 115);
  put_u8(&mut v, 135, 116);
  put_u8(&mut v, 136, 114);
  put_u8(&mut v, 137, 116);
  put_u8(&mut v, 138, 97);
  put_u8(&mut v, 139, 98);
  put_uint(&mut v, 205, 1, 4, false);
  put_uint(&mut v, 209, 1, 4, false);
  put_uint(&mut v, 213, 6, 8, false);
  put_uint(&mut v, 221, 0x401000, 8, false);
  put_uint(&mut v, 229, 120, 8, false);
  put_uint(&mut v, 237, 4, 8, false);
  put_uint(&mut v, 245, 2, 4, false);
  put_uint(&mut v, 249, 7, 4, false);
  put_uint(&mut v, 253, 16, 8, false);
  put_uint(&mut v, 261, 0, 8, false);
  put_uint(&mut v, 269, 7, 4, false);
  put_uint(&mut v, 273, 3, 4, false);
  put_uint(&mut v, 277, 0, 8, false);
  put_uint(&mut v, 285, 0, 8, false);
  put_uint(&mut v, 293, 124, 8, false);
  put_uint(&mut v, 301, 17, 8, false);
  put_uint(&mut v, 309, 0, 4, false);
  put_uint(&mut v, 313, 0, 4, false);
  put_uint(&mut v, 317, 1, 8, false);
  put_uint(&mut v, 325, 0, 8, false);
  return v;
}

// 32-bit little-endian fixture, 124 bytes:
//   0..51   ELF header (class 1, data 1, ET_EXEC, EM_386, entry 0x8048000)
//   52..83  program header (32-bit layout; PT_LOAD, filesz 52, memsz 100)
//   84..123 one NULL section header; shstrndx 0 (all names empty)
fn fx32le() -> Vec[UInt8] {
  var v = zeros(124);
  put_u8(&mut v, 0, 127);
  put_u8(&mut v, 1, 69);
  put_u8(&mut v, 2, 76);
  put_u8(&mut v, 3, 70);
  put_u8(&mut v, 4, 1);
  put_u8(&mut v, 5, 1);
  put_u8(&mut v, 6, 1);
  put_u8(&mut v, 7, 0);
  put_u8(&mut v, 8, 0);
  put_uint(&mut v, 16, 2, 2, false);
  put_uint(&mut v, 18, 3, 2, false);
  put_uint(&mut v, 20, 1, 4, false);
  put_uint(&mut v, 24, 0x8048000, 4, false);
  put_uint(&mut v, 28, 52, 4, false);
  put_uint(&mut v, 32, 84, 4, false);
  put_uint(&mut v, 36, 0, 4, false);
  put_uint(&mut v, 40, 52, 2, false);
  put_uint(&mut v, 42, 32, 2, false);
  put_uint(&mut v, 44, 1, 2, false);
  put_uint(&mut v, 46, 40, 2, false);
  put_uint(&mut v, 48, 1, 2, false);
  put_uint(&mut v, 50, 0, 2, false);
  put_uint(&mut v, 52, 1, 4, false);
  put_uint(&mut v, 56, 0, 4, false);
  put_uint(&mut v, 60, 0x8048000, 4, false);
  put_uint(&mut v, 64, 0x8048000, 4, false);
  put_uint(&mut v, 68, 52, 4, false);
  put_uint(&mut v, 72, 100, 4, false);
  put_uint(&mut v, 76, 4, 4, false);
  put_uint(&mut v, 80, 4096, 4, false);
  return v;
}

// 64-bit big-endian fixture, 120 bytes: ELF header (class 2, data 2,
// ET_DYN, EM_PPC64) plus one program header with byte-order-revealing
// values; no section table (shnum 0, shstrndx 0).
fn fx64be() -> Vec[UInt8] {
  var v = zeros(120);
  put_u8(&mut v, 0, 127);
  put_u8(&mut v, 1, 69);
  put_u8(&mut v, 2, 76);
  put_u8(&mut v, 3, 70);
  put_u8(&mut v, 4, 2);
  put_u8(&mut v, 5, 2);
  put_u8(&mut v, 6, 1);
  put_u8(&mut v, 7, 0);
  put_u8(&mut v, 8, 0);
  put_uint(&mut v, 16, 3, 2, true);
  put_uint(&mut v, 18, 21, 2, true);
  put_uint(&mut v, 20, 1, 4, true);
  put_uint(&mut v, 24, 0x0102030405060708, 8, true);
  put_uint(&mut v, 32, 64, 8, true);
  put_uint(&mut v, 40, 0, 8, true);
  put_uint(&mut v, 48, 0x11223344, 4, true);
  put_uint(&mut v, 52, 64, 2, true);
  put_uint(&mut v, 54, 56, 2, true);
  put_uint(&mut v, 56, 1, 2, true);
  put_uint(&mut v, 58, 64, 2, true);
  put_uint(&mut v, 60, 0, 2, true);
  put_uint(&mut v, 62, 0, 2, true);
  put_uint(&mut v, 64, 1, 4, true);
  put_uint(&mut v, 68, 6, 4, true);
  put_uint(&mut v, 72, 0, 8, true);
  put_uint(&mut v, 80, 0x1122334455667788, 8, true);
  put_uint(&mut v, 88, 0x0102030405060708, 8, true);
  put_uint(&mut v, 96, 64, 8, true);
  put_uint(&mut v, 104, 8192, 8, true);
  put_uint(&mut v, 112, 4096, 8, true);
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let r = elf_build_minimal_64le(0x401000);
  if !r.is_ok { return assert(false, "minimal build must succeed"); }
  let b: Vec[UInt8] = r.value;
  var ok = b.len() == 64;
  if !bytes_equal(b, hb("7f454c4602010100000000000000000002003e000100000000104000000000000000000000000000000000000000000000000000400038000000400000000000")) {
    ok = false;
  }
  let pr = elf_parse(&b);
  if !pr.is_ok { return assert(false, "built header must parse"); }
  let f: ElfFile = pr.value;
  if elf_class(&f) != 2 { ok = false; }
  if elf_endianness(&f) != 1 { ok = false; }
  if elf_file_type(&f) != 2 { ok = false; }
  if elf_machine(&f) != 62 { ok = false; }
  if elf_entry(&f) != 0x401000 { ok = false; }
  if elf_program_count(&f) != 0 { ok = false; }
  if elf_section_count(&f) != 0 { ok = false; }
  if elf_shstrndx(&f) != 0 { ok = false; }
  if !err_bytes_is(elf_build_minimal_64le(-1), "elf: negative entry") { ok = false; }
  return assert(ok, "minimal 64-bit LE builder: exact 64 bytes and parse-back");
}

fn t2() -> TestResult {
  let d = fx64le();
  let r = elf_parse(&d);
  if !r.is_ok { return assert(false, "64-bit LE fixture must parse"); }
  let f: ElfFile = r.value;
  var ok = elf_class(&f) == 2;
  if elf_endianness(&f) != 1 { ok = false; }
  if elf_osabi(&f) != 3 { ok = false; }
  if elf_file_type(&f) != 2 { ok = false; }
  if elf_machine(&f) != 62 { ok = false; }
  if elf_entry(&f) != 0x401000 { ok = false; }
  if elf_phoff(&f) != 64 { ok = false; }
  if elf_shoff(&f) != 141 { ok = false; }
  if elf_program_count(&f) != 1 { ok = false; }
  if elf_section_count(&f) != 3 { ok = false; }
  if elf_shstrndx(&f) != 2 { ok = false; }
  return assert(ok, "64-bit LE fixture: header fields and table counts");
}

fn t3() -> TestResult {
  let d = fx64le();
  let r = elf_parse(&d);
  if !r.is_ok { return assert(false, "64-bit LE fixture must parse"); }
  let f: ElfFile = r.value;
  var ok = int_is(elf_program_field(&f, 0, ELF_PH_FIELD_TYPE), 1);
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_FLAGS), 5) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_OFFSET), 0) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_VADDR), 0x400000) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_PADDR), 0x400000) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_FILESZ), 64) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_MEMSZ), 128) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_ALIGN), 4096) { ok = false; }
  if !err_int_is(elf_program_field(&f, 1, ELF_PH_FIELD_TYPE), "elf: index out of range") { ok = false; }
  if !err_int_is(elf_program_field(&f, -1, ELF_PH_FIELD_TYPE), "elf: index out of range") { ok = false; }
  if !err_int_is(elf_program_field(&f, 0, ELF_PH_FIELD_COUNT), "elf: bad field selector") { ok = false; }
  if !err_int_is(elf_program_field(&f, 0, -1), "elf: bad field selector") { ok = false; }
  return assert(ok, "program header: all eight fields, index bounds, field selectors");
}

fn t4() -> TestResult {
  let d = fx64le();
  let r = elf_parse(&d);
  if !r.is_ok { return assert(false, "64-bit LE fixture must parse"); }
  let f: ElfFile = r.value;
  var ok = int_is(elf_section_field(&f, 1, ELF_SH_FIELD_NAME), 1);
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_TYPE), 1) { ok = false; }
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_FLAGS), 6) { ok = false; }
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_ADDR), 0x401000) { ok = false; }
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_OFFSET), 120) { ok = false; }
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_SIZE), 4) { ok = false; }
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_LINK), 2) { ok = false; }
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_INFO), 7) { ok = false; }
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_ADDRAALIGN), 16) { ok = false; }
  if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_ENTSIZE), 0) { ok = false; }
  if !int_is(elf_section_field(&f, 2, ELF_SH_FIELD_TYPE), 3) { ok = false; }
  if !int_is(elf_section_field(&f, 2, ELF_SH_FIELD_OFFSET), 124) { ok = false; }
  if !int_is(elf_section_field(&f, 2, ELF_SH_FIELD_SIZE), 17) { ok = false; }
  if !err_int_is(elf_section_field(&f, 3, ELF_SH_FIELD_TYPE), "elf: index out of range") { ok = false; }
  if !err_int_is(elf_section_field(&f, -1, ELF_SH_FIELD_TYPE), "elf: index out of range") { ok = false; }
  if !err_int_is(elf_section_field(&f, 0, ELF_SH_FIELD_COUNT), "elf: bad field selector") { ok = false; }
  return assert(ok, "section header: all ten fields, index bounds, field selectors");
}

fn t5() -> TestResult {
  let d = fx64le();
  let r = elf_parse(&d);
  if !r.is_ok { return assert(false, "64-bit LE fixture must parse"); }
  let f: ElfFile = r.value;
  var ok = str_is(elf_section_name(&f, 0), "");
  if !str_is(elf_section_name(&f, 1), ".text") { ok = false; }
  if !str_is(elf_section_name(&f, 2), ".shstrtab") { ok = false; }
  if !err_str_is(elf_section_name(&f, 3), "elf: index out of range") { ok = false; }
  if !err_str_is(elf_section_name(&f, -1), "elf: index out of range") { ok = false; }
  return assert(ok, "section names resolve through the shstrtab (empty, .text, .shstrtab)");
}

fn t6() -> TestResult {
  let d = fx64le();
  let r = elf_parse(&d);
  if !r.is_ok { return assert(false, "64-bit LE fixture must parse"); }
  let f: ElfFile = r.value;
  var ok = elf_section_index(&f, "") == 0;
  if elf_section_index(&f, ".text") != 1 { ok = false; }
  if elf_section_index(&f, ".shstrtab") != 2 { ok = false; }
  if elf_section_index(&f, ".rodata") != -1 { ok = false; }
  if elf_section_index(&f, ".Text") != -1 { ok = false; }
  return assert(ok, "section index by name is exact, case-sensitive and -1 when absent");
}

fn t7() -> TestResult {
  let d = fx32le();
  let r = elf_parse(&d);
  if !r.is_ok { return assert(false, "32-bit LE fixture must parse"); }
  let f: ElfFile = r.value;
  var ok = elf_class(&f) == 1;
  if elf_endianness(&f) != 1 { ok = false; }
  if elf_file_type(&f) != 2 { ok = false; }
  if elf_machine(&f) != 3 { ok = false; }
  if elf_entry(&f) != 0x8048000 { ok = false; }
  if elf_program_count(&f) != 1 { ok = false; }
  if elf_section_count(&f) != 1 { ok = false; }
  if elf_shstrndx(&f) != 0 { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_TYPE), 1) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_FLAGS), 4) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_VADDR), 0x8048000) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_PADDR), 0x8048000) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_FILESZ), 52) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_MEMSZ), 100) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_ALIGN), 4096) { ok = false; }
  if !int_is(elf_section_field(&f, 0, ELF_SH_FIELD_NAME), 0) { ok = false; }
  if !str_is(elf_section_name(&f, 0), "") { ok = false; }
  return assert(ok, "32-bit LE fixture: 32-bit program/section layouts parse");
}

fn t8() -> TestResult {
  let d = fx64be();
  let r = elf_parse(&d);
  if !r.is_ok { return assert(false, "64-bit BE fixture must parse"); }
  let f: ElfFile = r.value;
  var ok = elf_class(&f) == 2;
  if elf_endianness(&f) != 2 { ok = false; }
  if elf_file_type(&f) != 3 { ok = false; }
  if elf_machine(&f) != 21 { ok = false; }
  if elf_entry(&f) != 0x0102030405060708 { ok = false; }
  if elf_flags(&f) != 0x11223344 { ok = false; }
  if elf_phoff(&f) != 64 { ok = false; }
  if elf_program_count(&f) != 1 { ok = false; }
  if elf_section_count(&f) != 0 { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_TYPE), 1) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_FLAGS), 6) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_VADDR), 0x1122334455667788) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_PADDR), 0x0102030405060708) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_FILESZ), 64) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_MEMSZ), 8192) { ok = false; }
  if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_ALIGN), 4096) { ok = false; }
  return assert(ok, "64-bit BE fixture: big-endian header and program fields");
}

fn t9() -> TestResult {
  var v1 = fx64le();
  put_u8(&mut v1, 0, 0);
  var ok = err_file_is(elf_parse(&v1), "elf: bad magic");
  var v2 = fx64le();
  put_u8(&mut v2, 1, 70);
  if !err_file_is(elf_parse(&v2), "elf: bad magic") { ok = false; }
  var v3 = fx64le();
  put_u8(&mut v3, 2, 70);
  if !err_file_is(elf_parse(&v3), "elf: bad magic") { ok = false; }
  var v4 = fx64le();
  put_u8(&mut v4, 3, 75);
  if !err_file_is(elf_parse(&v4), "elf: bad magic") { ok = false; }
  return assert(ok, "any wrong e_ident magic byte is Err(elf: bad magic)");
}

fn t10() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_file_is(elf_parse(&empty), "elf: truncated ident");
  let d = fx64le();
  let p10 = prefix(d, 10);
  if !err_file_is(elf_parse(&p10), "elf: truncated ident") { ok = false; }
  let p16 = prefix(d, 16);
  if !err_file_is(elf_parse(&p16), "elf: truncated header") { ok = false; }
  let p63 = prefix(d, 63);
  if !err_file_is(elf_parse(&p63), "elf: truncated header") { ok = false; }
  let p64 = prefix(d, 64);
  if !err_file_is(elf_parse(&p64), "elf: program headers out of bounds") { ok = false; }
  return assert(ok, "short buffers: truncated ident below 16 bytes, truncated header below 64");
}

fn t11() -> TestResult {
  var v1 = fx64le();
  put_u8(&mut v1, 4, 0);
  var ok = err_file_is(elf_parse(&v1), "elf: bad class");
  var v2 = fx64le();
  put_u8(&mut v2, 4, 3);
  if !err_file_is(elf_parse(&v2), "elf: bad class") { ok = false; }
  var v3 = fx64le();
  put_u8(&mut v3, 5, 0);
  if !err_file_is(elf_parse(&v3), "elf: bad data encoding") { ok = false; }
  var v4 = fx64le();
  put_u8(&mut v4, 5, 3);
  if !err_file_is(elf_parse(&v4), "elf: bad data encoding") { ok = false; }
  var v5 = fx64le();
  put_u8(&mut v5, 6, 2);
  if !err_file_is(elf_parse(&v5), "elf: bad ident version") { ok = false; }
  return assert(ok, "class 0/3, data 0/3 and ident version 2 are the documented errors");
}

fn t12() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 20, 2, 4, false);
  var ok = err_file_is(elf_parse(&v1), "elf: bad e_version");
  var v2 = fx64le();
  put_uint(&mut v2, 52, 63, 2, false);
  if !err_file_is(elf_parse(&v2), "elf: bad e_ehsize") { ok = false; }
  var v3 = fx64le();
  put_uint(&mut v3, 54, 32, 2, false);
  if !err_file_is(elf_parse(&v3), "elf: bad e_phentsize") { ok = false; }
  var v4 = fx64le();
  put_uint(&mut v4, 58, 40, 2, false);
  if !err_file_is(elf_parse(&v4), "elf: bad e_shentsize") { ok = false; }
  return assert(ok, "bad e_version, e_ehsize, e_phentsize and e_shentsize are Err");
}

fn t13() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 32, 300, 8, false);
  var ok = err_file_is(elf_parse(&v1), "elf: program headers out of bounds");
  var v2 = fx64le();
  put_uint(&mut v2, 32, -1, 8, false);
  if !err_file_is(elf_parse(&v2), "elf: program headers out of bounds") { ok = false; }
  var v3 = fx64le();
  put_uint(&mut v3, 40, 142, 8, false);
  if !err_file_is(elf_parse(&v3), "elf: section headers out of bounds") { ok = false; }
  var v4 = fx64le();
  put_uint(&mut v4, 40, -1, 8, false);
  if !err_file_is(elf_parse(&v4), "elf: section headers out of bounds") { ok = false; }
  return assert(ok, "table spans outside the buffer (including raw negative offsets) are Err");
}

fn t14() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 72, 128, 8, false);
  put_uint(&mut v1, 96, 300, 8, false);
  var ok = err_file_is(elf_parse(&v1), "elf: segment data out of bounds");
  var v2 = fx64le();
  put_uint(&mut v2, 96, -1, 8, false);
  if !err_file_is(elf_parse(&v2), "elf: segment data out of bounds") { ok = false; }
  var v3 = fx64le();
  put_uint(&mut v3, 72, 4000, 8, false);
  put_uint(&mut v3, 96, 0, 8, false);
  let r3 = elf_parse(&v3);
  if !r3.is_ok { ok = false; } else {
    let f: ElfFile = r3.value;
    if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_OFFSET), 4000) { ok = false; }
    if !int_is(elf_program_field(&f, 0, ELF_PH_FIELD_FILESZ), 0) { ok = false; }
  }
  return assert(ok, "segment file bytes must fit; a zero-filesz segment skips the offset check");
}

fn t15() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 237, 1000, 8, false);
  var ok = err_file_is(elf_parse(&v1), "elf: section data out of bounds");
  var v2 = fx64le();
  put_uint(&mut v2, 229, -1, 8, false);
  if !err_file_is(elf_parse(&v2), "elf: section data out of bounds") { ok = false; }
  var v3 = fx64le();
  put_uint(&mut v3, 209, 8, 4, false);
  put_uint(&mut v3, 237, 1000, 8, false);
  let r3 = elf_parse(&v3);
  if !r3.is_ok { ok = false; } else {
    let f: ElfFile = r3.value;
    if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_TYPE), 8) { ok = false; }
    if !int_is(elf_section_field(&f, 1, ELF_SH_FIELD_SIZE), 1000) { ok = false; }
  }
  var v4 = fx64le();
  put_uint(&mut v4, 209, 8, 4, false);
  put_uint(&mut v4, 229, -1, 8, false);
  if !err_file_is(elf_parse(&v4), "elf: section data out of bounds") { ok = false; }
  return assert(ok, "section spans must fit; SHT_NOBITS keeps size but still needs sh_offset >= 0");
}

fn t16() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 62, 3, 2, false);
  var ok = err_file_is(elf_parse(&v1), "elf: shstrndx out of range");
  var v2 = fx64le();
  put_uint(&mut v2, 62, 0xFFFF, 2, false);
  if !err_file_is(elf_parse(&v2), "elf: extended section index unsupported (SHN_XINDEX)") { ok = false; }
  var v3 = fx64le();
  put_uint(&mut v3, 62, 1, 2, false);
  if !err_file_is(elf_parse(&v3), "elf: shstrndx is not a string table") { ok = false; }
  var v4 = fx64le();
  put_uint(&mut v4, 62, 0, 2, false);
  if !err_file_is(elf_parse(&v4), "elf: no section name string table") { ok = false; }
  var v5 = fx64le();
  put_uint(&mut v5, 62, 0, 2, false);
  put_uint(&mut v5, 205, 0, 4, false);
  put_uint(&mut v5, 269, 0, 4, false);
  let r5 = elf_parse(&v5);
  if !r5.is_ok { ok = false; } else {
    let f: ElfFile = r5.value;
    if !str_is(elf_section_name(&f, 1), "") { ok = false; }
    if !str_is(elf_section_name(&f, 2), "") { ok = false; }
  }
  return assert(ok, "shstrndx bounds, SHN_XINDEX, non-STRTAB and SHN_UNDEF are documented");
}

fn t17() -> TestResult {
  var v1 = fx64le();
  put_uint(&mut v1, 205, 17, 4, false);
  var ok = err_file_is(elf_parse(&v1), "elf: section name index out of bounds");
  var v2 = fx64le();
  put_uint(&mut v2, 301, 8, 8, false);
  put_uint(&mut v2, 269, 7, 4, false);
  if !err_file_is(elf_parse(&v2), "elf: section name not NUL-terminated") { ok = false; }
  var v3 = fx64le();
  put_u8(&mut v3, 125, 1);
  if !err_file_is(elf_parse(&v3), "elf: section name not printable ASCII") { ok = false; }
  var v4 = fx64le();
  put_u8(&mut v4, 125, 127);
  if !err_file_is(elf_parse(&v4), "elf: section name not printable ASCII") { ok = false; }
  return assert(ok, "section name index bounds, NUL termination and printable-ASCII rules");
}

fn t18() -> TestResult {
  var v1 = fx64be();
  put_uint(&mut v1, 24, -1, 8, true);
  let r1 = elf_parse(&v1);
  var ok = false;
  if !r1.is_ok { return assert(false, "high-bit entry fixture must parse"); }
  let f1: ElfFile = r1.value;
  ok = elf_entry(&f1) == -1;
  var v2 = fx64be();
  put_uint(&mut v2, 24, 0x7FFFFFFFFFFFFFFF, 8, true);
  let r2 = elf_parse(&v2);
  if !r2.is_ok { ok = false; } else {
    let f2: ElfFile = r2.value;
    if elf_entry(&f2) != 0x7FFFFFFFFFFFFFFF { ok = false; }
  }
  var v3 = fx64be();
  put_uint(&mut v3, 32, -1, 8, true);
  if !err_file_is(elf_parse(&v3), "elf: program headers out of bounds") { ok = false; }
  var v4 = fx64le();
  put_uint(&mut v4, 80, -1, 8, false);
  let r4 = elf_parse(&v4);
  if !r4.is_ok { ok = false; } else {
    let f4: ElfFile = r4.value;
    if !int_is(elf_program_field(&f4, 0, ELF_PH_FIELD_VADDR), -1) { ok = false; }
  }
  return assert(ok, "64-bit fields decode as raw two's-complement (bit 63 set is negative)");
}

fn main() -> Int {
  io.println("=== xiom.elf conformance tests ===");
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
    io.println("xiom.elf: all tests passed");
  } else {
    io.println("xiom.elf: tests failed");
  }
  return failed;
}
