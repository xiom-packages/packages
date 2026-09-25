// XIOM -- xiom.pe conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API against a hand-built canonical PE32+ fixture
// (two sections, a 64-byte DOS stub, 16 data directories) and a canonical
// PE32 fixture (one section, no stub, 2 directories): the pinned header
// bytes, every accessor, the stub span copy, byte-for-byte pe_build and
// pe_build_headers round-trips, the whole error catalog (DOS header,
// signature, COFF, optional header/magic/directories, alignments, section
// names, raw spans, builder ranges and cross-checks).
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison); error messages and
// section names go through compare.str_compare with typed locals.

module pe_tests
use xiom.io; use xiom.test;
use xiom.pe;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Result and byte helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok { return r.value; }
  return Vec[UInt8].new();
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn ok_img(r: Result[PeImage, Str]) -> PeImage {
  if r.is_ok { return r.value; }
  return zero_img();
}

fn img_err_is(r: Result[PeImage, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if (a.len() != b.len()) { return false; }
  var i = 0;
  while (i < a.len()) {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if (x != y) { return false; }
    i = i + 1;
  }
  return true;
}

fn le_byte(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while (i < k) {
    q = q / 256;
    i = i + 1;
  }
  var b = q % 256;
  if (b < 0) { b = b + 256; }
  return b as UInt8;
}

fn push_le16(out: &mut Vec[UInt8], v: Int) {
  out.push(le_byte(v, 0));
  out.push(le_byte(v, 1));
}

fn push_le32(out: &mut Vec[UInt8], v: Int) {
  out.push(le_byte(v, 0));
  out.push(le_byte(v, 1));
  out.push(le_byte(v, 2));
  out.push(le_byte(v, 3));
}

fn push_zeros(out: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while (i < n) {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

fn push_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while (i < src.len()) {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn set_le16(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < data.len()) {
    if (i >= pos && i < pos + 2) {
      out.push(le_byte(v, i - pos));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_le32(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < data.len()) {
    if (i >= pos && i < pos + 4) {
      out.push(le_byte(v, i - pos));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_byte(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < data.len()) {
    if (i == pos) {
      out.push(v as UInt8);
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn truncate(data: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < n && i < data.len()) {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Struct fixtures
// --------------------------------------------------

fn zero_img() -> PeImage {
  return PeImage{
    file_size: 0; pe_offset: 0; stub_size: 0; machine: 0;
    number_of_sections: 0; time_date_stamp: 0; pointer_to_symbol_table: 0;
    number_of_symbols: 0; size_of_optional_header: 0; characteristics: 0;
    optional_magic: 0; address_of_entry_point: 0; image_base: 0;
    section_alignment: 0; file_alignment: 0; size_of_image: 0;
    size_of_headers: 0; subsystem: 0; number_of_rva_and_sizes: 0;
    dir_virtual_addresses: Vec[Int].new();
    dir_sizes: Vec[Int].new();
    section_names: Vec[Str].new();
    section_virtual_sizes: Vec[Int].new();
    section_virtual_addresses: Vec[Int].new();
    section_raw_sizes: Vec[Int].new();
    section_raw_pointers: Vec[Int].new();
    section_reloc_pointers: Vec[Int].new();
    section_line_pointers: Vec[Int].new();
    section_characteristics: Vec[Int].new();
  };
}

fn clone_img(img: &PeImage) -> PeImage {
  return PeImage{
    file_size: img.file_size;
    pe_offset: img.pe_offset;
    stub_size: img.stub_size;
    machine: img.machine;
    number_of_sections: img.number_of_sections;
    time_date_stamp: img.time_date_stamp;
    pointer_to_symbol_table: img.pointer_to_symbol_table;
    number_of_symbols: img.number_of_symbols;
    size_of_optional_header: img.size_of_optional_header;
    characteristics: img.characteristics;
    optional_magic: img.optional_magic;
    address_of_entry_point: img.address_of_entry_point;
    image_base: img.image_base;
    section_alignment: img.section_alignment;
    file_alignment: img.file_alignment;
    size_of_image: img.size_of_image;
    size_of_headers: img.size_of_headers;
    subsystem: img.subsystem;
    number_of_rva_and_sizes: img.number_of_rva_and_sizes;
    dir_virtual_addresses: img.dir_virtual_addresses;
    dir_sizes: img.dir_sizes;
    section_names: img.section_names;
    section_virtual_sizes: img.section_virtual_sizes;
    section_virtual_addresses: img.section_virtual_addresses;
    section_raw_sizes: img.section_raw_sizes;
    section_raw_pointers: img.section_raw_pointers;
    section_reloc_pointers: img.section_reloc_pointers;
    section_line_pointers: img.section_line_pointers;
    section_characteristics: img.section_characteristics;
  };
}

// Deterministic 64-byte DOS stub pattern (no NUL bytes).
fn fixture_stub() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < 64) {
    out.push(((i * 7 + 11) % 251) as UInt8);
    i = i + 1;
  }
  return out;
}

// Deterministic raw section bytes.
fn raw_bytes(seed: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    out.push(((i * 13 + seed) % 251) as UInt8);
    i = i + 1;
  }
  return out;
}

// An 8-byte NUL-padded section name field.
fn name_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < s.len()) {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  while (out.len() < 8) {
    out.push(0 as UInt8);
  }
  return out;
}

// Canonical minimal PE32+ fixture: 64-byte DOS header (e_lfanew 128), 64-byte
// stub, two sections (.text raw 0x600 @ 0x200, .rdata raw 0x200 @ 0x800),
// 16 data directories (entry 1 = import dir RVA 0x3000, size 0x28),
// fileAlignment 0x200; 2560 bytes total.
fn fixture_pe32plus() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(77 as UInt8);
  out.push(90 as UInt8);
  push_zeros(&mut out, 58);
  push_le32(&mut out, 128);
  let stub = fixture_stub();
  push_bytes(&mut out, &stub);
  out.push(80 as UInt8);
  out.push(69 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  push_le16(&mut out, 0x8664);
  push_le16(&mut out, 2);
  push_le32(&mut out, 1700000000);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le16(&mut out, 240);
  push_le16(&mut out, 0x22);
  push_le16(&mut out, 0x20B);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0x1000);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0x40000000);
  push_le32(&mut out, 1);
  push_le32(&mut out, 0x1000);
  push_le32(&mut out, 0x200);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0x4000);
  push_le32(&mut out, 0x200);
  push_le32(&mut out, 0);
  push_le16(&mut out, 3);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 16);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0x3000);
  push_le32(&mut out, 0x28);
  var d = 2;
  while (d < 16) {
    push_le32(&mut out, 0);
    push_le32(&mut out, 0);
    d = d + 1;
  }
  push_bytes(&mut out, &name_bytes(".text"));
  push_le32(&mut out, 0x1800);
  push_le32(&mut out, 0x1000);
  push_le32(&mut out, 0x600);
  push_le32(&mut out, 0x200);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0x60000020);
  push_bytes(&mut out, &name_bytes(".rdata"));
  push_le32(&mut out, 0x400);
  push_le32(&mut out, 0x3000);
  push_le32(&mut out, 0x200);
  push_le32(&mut out, 0x800);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0x40000040);
  push_zeros(&mut out, 40);
  push_bytes(&mut out, &raw_bytes(7, 0x600));
  push_bytes(&mut out, &raw_bytes(29, 0x200));
  return out;
}

// Canonical PE32 fixture: no stub (e_lfanew 64), one .text section
// (raw 0x200 @ 0x200), 2 data directories; 1024 bytes total.
fn fixture_pe32() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(77 as UInt8);
  out.push(90 as UInt8);
  push_zeros(&mut out, 58);
  push_le32(&mut out, 64);
  out.push(80 as UInt8);
  out.push(69 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  push_le16(&mut out, 0x14C);
  push_le16(&mut out, 1);
  push_le32(&mut out, 1600000000);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le16(&mut out, 112);
  push_le16(&mut out, 0x102);
  push_le16(&mut out, 0x10B);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0x1000);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0x400000);
  push_le32(&mut out, 0x1000);
  push_le32(&mut out, 0x200);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0x2000);
  push_le32(&mut out, 0x200);
  push_le32(&mut out, 0);
  push_le16(&mut out, 2);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le32(&mut out, 2);
  push_le32(&mut out, 0x1000);
  push_le32(&mut out, 0x100);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_bytes(&mut out, &name_bytes(".text"));
  push_le32(&mut out, 0x500);
  push_le32(&mut out, 0x1000);
  push_le32(&mut out, 0x200);
  push_le32(&mut out, 0x200);
  push_le32(&mut out, 0);
  push_le32(&mut out, 0);
  push_le16(&mut out, 0);
  push_le16(&mut out, 0);
  push_le32(&mut out, 0x60000020);
  push_zeros(&mut out, 272);
  push_bytes(&mut out, &raw_bytes(41, 0x200));
  return out;
}

// Concatenate the on-disk bytes of every section, in table order, using the
// public accessors.
fn collect_raw(img: &PeImage, data: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < pe_section_count(img)) {
    let rp = pe_section_raw_pointer(img, i);
    let rs = pe_section_raw_size(img, i);
    var j = 0;
    while (j < rs) {
      out.push(data[rp + j]);
      j = j + 1;
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

// 1. PE32+ fixture parses into every decoded COFF/optional-header field.
fn t1() -> TestResult {
  let fx = fixture_pe32plus();
  if (fx.len() != 2560) { return assert(false, "fixture is 2560 bytes"); }
  let img = ok_img(pe_parse(&fx));
  var ok = img.file_size == 2560;
  if img.pe_offset != 128 { ok = false; }
  if img.stub_size != 64 { ok = false; }
  if img.machine != 0x8664 { ok = false; }
  if img.number_of_sections != 2 { ok = false; }
  if img.time_date_stamp != 1700000000 { ok = false; }
  if img.pointer_to_symbol_table != 0 { ok = false; }
  if img.number_of_symbols != 0 { ok = false; }
  if img.size_of_optional_header != 240 { ok = false; }
  if img.characteristics != 0x22 { ok = false; }
  if img.optional_magic != 0x20B { ok = false; }
  if img.address_of_entry_point != 0x1000 { ok = false; }
  if img.image_base != 0x140000000 { ok = false; }
  if img.section_alignment != 0x1000 { ok = false; }
  if img.file_alignment != 0x200 { ok = false; }
  if img.size_of_image != 0x4000 { ok = false; }
  if img.size_of_headers != 0x200 { ok = false; }
  if img.subsystem != 3 { ok = false; }
  if img.number_of_rva_and_sizes != 16 { ok = false; }
  if !pe_is_valid(&fx) { ok = false; }
  if pe_pe_offset(&img) != 128 { ok = false; }
  if pe_stub_size(&img) != 64 { ok = false; }
  if pe_optional_offset(&img) != 152 { ok = false; }
  if pe_file_size(&img) != 2560 { ok = false; }
  if pe_optional_magic(&img) != 0x20B { ok = false; }
  return assert(ok, "PE32+ fixture decodes every documented header field");
}

// 2. DOS header pins and the stub span copy.
fn t2() -> TestResult {
  let fx = fixture_pe32plus();
  var ok = byte_is(&fx, 0, 77);
  if !byte_is(&fx, 1, 90) { ok = false; }
  if !byte_is(&fx, 60, 128) { ok = false; }
  if !byte_is(&fx, 61, 0) { ok = false; }
  if !byte_is(&fx, 62, 0) { ok = false; }
  if !byte_is(&fx, 63, 0) { ok = false; }
  let img = ok_img(pe_parse(&fx));
  if pe_pe_offset(&img) != 128 { ok = false; }
  if pe_stub_size(&img) != 64 { ok = false; }
  let sb = ok_bytes(pe_stub(&fx));
  let want = fixture_stub();
  if !bytes_equal(&sb, &want) { ok = false; }
  if sb.len() != 64 { ok = false; }
  let inner = truncate(&sb, 3);
  if !byte_is(&inner, 0, 11) { ok = false; }
  if !byte_is(&inner, 1, 18) { ok = false; }
  if !byte_is(&inner, 2, 25) { ok = false; }
  let short = truncate(&fx, 63);
  if !bytes_err_is(pe_stub(&short), "pe: truncated dos header") { ok = false; }
  return assert(ok, "DOS magic, e_lfanew and the stub span are exact");
}

// 3. Section accessors and pe_find_section.
fn t3() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  var ok = pe_section_count(&img) == 2;
  if !streq(pe_section_name(&img, 0), ".text") { ok = false; }
  if !streq(pe_section_name(&img, 1), ".rdata") { ok = false; }
  if pe_section_virtual_size(&img, 0) != 0x1800 { ok = false; }
  if pe_section_virtual_address(&img, 0) != 0x1000 { ok = false; }
  if pe_section_raw_size(&img, 0) != 0x600 { ok = false; }
  if pe_section_raw_pointer(&img, 0) != 0x200 { ok = false; }
  if pe_section_reloc_pointer(&img, 0) != 0 { ok = false; }
  if pe_section_line_pointer(&img, 0) != 0 { ok = false; }
  if pe_section_characteristics(&img, 0) != 0x60000020 { ok = false; }
  if pe_section_virtual_size(&img, 1) != 0x400 { ok = false; }
  if pe_section_virtual_address(&img, 1) != 0x3000 { ok = false; }
  if pe_section_raw_size(&img, 1) != 0x200 { ok = false; }
  if pe_section_raw_pointer(&img, 1) != 0x800 { ok = false; }
  if pe_section_characteristics(&img, 1) != 0x40000040 { ok = false; }
  if pe_find_section(&img, ".text") != 0 { ok = false; }
  if pe_find_section(&img, ".rdata") != 1 { ok = false; }
  if pe_find_section(&img, ".data") != -1 { ok = false; }
  if pe_find_section(&img, "") != -1 { ok = false; }
  return assert(ok, "section names, spans, flags and lookup are exact");
}

// 4. Optional-header accessors and raw data directories.
fn t4() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  var ok = pe_machine(&img) == 0x8664;
  if pe_entry_point(&img) != 0x1000 { ok = false; }
  if pe_image_base(&img) != 0x140000000 { ok = false; }
  if pe_subsystem(&img) != 3 { ok = false; }
  if pe_size_of_image(&img) != 0x4000 { ok = false; }
  if pe_size_of_headers(&img) != 0x200 { ok = false; }
  if pe_section_alignment(&img) != 0x1000 { ok = false; }
  if pe_file_alignment(&img) != 0x200 { ok = false; }
  if pe_characteristics(&img) != 0x22 { ok = false; }
  if pe_time_date_stamp(&img) != 1700000000 { ok = false; }
  if pe_directory_count(&img) != 16 { ok = false; }
  if pe_directory_virtual_address(&img, 0) != 0 { ok = false; }
  if pe_directory_size(&img, 0) != 0 { ok = false; }
  if pe_directory_virtual_address(&img, 1) != 0x3000 { ok = false; }
  if pe_directory_size(&img, 1) != 0x28 { ok = false; }
  if pe_directory_virtual_address(&img, 2) != 0 { ok = false; }
  if pe_directory_size(&img, 15) != 0 { ok = false; }
  if pe_directory_virtual_address(&img, 16) != -1 { ok = false; }
  if pe_directory_size(&img, -1) != -1 { ok = false; }
  if !streq(pe_machine_name(pe_machine(&img)), "amd64") { ok = false; }
  if !streq(pe_machine_name(PE_MACHINE_I386), "i386") { ok = false; }
  if !streq(pe_machine_name(PE_MACHINE_AMD64), "amd64") { ok = false; }
  if !streq(pe_machine_name(PE_MACHINE_ARM), "arm") { ok = false; }
  if !streq(pe_machine_name(PE_MACHINE_ARM64), "arm64") { ok = false; }
  if !streq(pe_machine_name(PE_MACHINE_IA64), "ia64") { ok = false; }
  if !streq(pe_machine_name(0x999), "unknown") { ok = false; }
  return assert(ok, "optional-header accessors and directories are exact");
}

// 5. pe_build_headers pins the canonical 472-byte header block byte for byte.
fn t5() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  let stub = fixture_stub();
  let hb = pe_build_headers(&img, &stub);
  if !hb.is_ok { return assert(false, "header build must succeed"); }
  let h: Vec[UInt8] = hb.value;
  var ok = h.len() == 472;
  if !byte_is(&h, 0, 77) { ok = false; }
  if !byte_is(&h, 1, 90) { ok = false; }
  if !byte_is(&h, 60, 128) { ok = false; }
  if !byte_is(&h, 61, 0) { ok = false; }
  let hp = truncate(&h, 128);
  let fp = truncate(&fx, 128);
  if !bytes_equal(&hp, &fp) { ok = false; }
  if !byte_is(&h, 128, 80) { ok = false; }
  if !byte_is(&h, 129, 69) { ok = false; }
  if !byte_is(&h, 130, 0) { ok = false; }
  if !byte_is(&h, 131, 0) { ok = false; }
  if !byte_is(&h, 132, 0x64) { ok = false; }
  if !byte_is(&h, 133, 0x86) { ok = false; }
  if !byte_is(&h, 134, 2) { ok = false; }
  if !byte_is(&h, 135, 0) { ok = false; }
  if !byte_is(&h, 148, 240) { ok = false; }
  if !byte_is(&h, 149, 0) { ok = false; }
  if !byte_is(&h, 152, 0x0B) { ok = false; }
  if !byte_is(&h, 153, 0x02) { ok = false; }
  if !byte_is(&h, 168, 0) { ok = false; }
  if !byte_is(&h, 169, 0x10) { ok = false; }
  if !byte_is(&h, 176, 0) { ok = false; }
  if !byte_is(&h, 180, 1) { ok = false; }
  if !byte_is(&h, 184, 0) { ok = false; }
  if !byte_is(&h, 185, 0x10) { ok = false; }
  if !byte_is(&h, 188, 0) { ok = false; }
  if !byte_is(&h, 189, 2) { ok = false; }
  if !byte_is(&h, 264, 0) { ok = false; }
  if !byte_is(&h, 272, 0) { ok = false; }
  if !byte_is(&h, 273, 0x30) { ok = false; }
  if !byte_is(&h, 276, 0x28) { ok = false; }
  if !byte_is(&h, 392, 46) { ok = false; }
  if !byte_is(&h, 393, 116) { ok = false; }
  if !byte_is(&h, 394, 101) { ok = false; }
  if !byte_is(&h, 395, 120) { ok = false; }
  if !byte_is(&h, 396, 116) { ok = false; }
  if !byte_is(&h, 397, 0) { ok = false; }
  if !byte_is(&h, 404, 0) { ok = false; }
  if !byte_is(&h, 405, 0x10) { ok = false; }
  if !byte_is(&h, 412, 0) { ok = false; }
  if !byte_is(&h, 413, 2) { ok = false; }
  if !byte_is(&h, 428, 0x20) { ok = false; }
  if !byte_is(&h, 431, 0x60) { ok = false; }
  if !byte_is(&h, 432, 46) { ok = false; }
  let fh = truncate(&fx, 472);
  if !bytes_equal(&h, &fh) { ok = false; }
  if !streq(pe_section_name(&img, 0), ".text") { ok = false; }
  if pe_entry_point(&img) != 0x1000 { ok = false; }
  return assert(ok, "pe_build_headers reproduces the fixture header block");
}

// 6. pe_build reproduces the whole PE32+ fixture byte for byte.
fn t6() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  let stub = fixture_stub();
  let raw = collect_raw(&img, &fx);
  var ok = raw.len() == 0x800;
  let br = pe_build(&img, &stub, &raw);
  if !br.is_ok { return assert(false, "full build must succeed"); }
  let out: Vec[UInt8] = br.value;
  if out.len() != 2560 { ok = false; }
  if !bytes_equal(&out, &fx) { ok = false; }
  let br2 = pe_build(&img, &stub, &raw);
  if !br2.is_ok { ok = false; }
  if br2.is_ok {
    let out2: Vec[UInt8] = br2.value;
    if !bytes_equal(&out2, &fx) { ok = false; }
  }
  let re = ok_img(pe_parse(&out));
  if pe_section_count(&re) != 2 { ok = false; }
  if pe_section_raw_pointer(&re, 1) != 0x800 { ok = false; }
  if pe_image_base(&re) != 0x140000000 { ok = false; }
  if !byte_is(&out, 512, 7) { ok = false; }
  if !byte_is(&out, 2048, 29) { ok = false; }
  return assert(ok, "pe_build round-trips the PE32+ fixture byte for byte");
}

// 7. The PE32 fixture (0x10B, no stub, one section) parses and rebuilds.
fn t7() -> TestResult {
  let fx = fixture_pe32();
  if (fx.len() != 1024) { return assert(false, "PE32 fixture is 1024 bytes"); }
  let img = ok_img(pe_parse(&fx));
  var ok = pe_optional_magic(&img) == 0x10B;
  if pe_image_base(&img) != 0x400000 { ok = false; }
  if pe_entry_point(&img) != 0x1000 { ok = false; }
  if pe_subsystem(&img) != 2 { ok = false; }
  if pe_stub_size(&img) != 0 { ok = false; }
  if pe_pe_offset(&img) != 64 { ok = false; }
  if pe_optional_offset(&img) != 88 { ok = false; }
  if pe_section_count(&img) != 1 { ok = false; }
  if !streq(pe_section_name(&img, 0), ".text") { ok = false; }
  if pe_directory_count(&img) != 2 { ok = false; }
  if pe_directory_virtual_address(&img, 0) != 0x1000 { ok = false; }
  if pe_directory_size(&img, 0) != 0x100 { ok = false; }
  if pe_section_virtual_address(&img, 0) != 0x1000 { ok = false; }
  let stub = Vec[UInt8].new();
  if pe_stub_size(&img) != stub.len() { ok = false; }
  let raw = collect_raw(&img, &fx);
  if raw.len() != 0x200 { ok = false; }
  let out = ok_bytes(pe_build(&img, &stub, &raw));
  if !bytes_equal(&out, &fx) { ok = false; }
  let sb = ok_bytes(pe_stub(&fx));
  if sb.len() != 0 { ok = false; }
  if !streq(pe_machine_name(pe_machine(&img)), "i386") { ok = false; }
  return assert(ok, "PE32 fixture parses and rebuilds byte for byte");
}

// 8. A header-only spec (all raw sizes zero) builds and parses at both
//    builder entry points.
fn t8() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  var hdr = clone_img(&img);
  var sizes = Vec[Int].new();
  sizes.push(0);
  sizes.push(0);
  hdr.section_raw_sizes = sizes;
  var ptrs = Vec[Int].new();
  ptrs.push(0);
  ptrs.push(0);
  hdr.section_raw_pointers = ptrs;
  let stub = fixture_stub();
  let empty_raw = Vec[UInt8].new();
  let hb = pe_build_headers(&hdr, &stub);
  if !hb.is_ok { return assert(false, "header build must succeed"); }
  let h: Vec[UInt8] = hb.value;
  let br = pe_build(&hdr, &stub, &empty_raw);
  if !br.is_ok { return assert(false, "header-only build must succeed"); }
  let out: Vec[UInt8] = br.value;
  var ok = bytes_equal(&out, &h);
  if out.len() != 472 { ok = false; }
  let re = ok_img(pe_parse(&out));
  if pe_section_count(&re) != 2 { ok = false; }
  if pe_section_raw_size(&re, 0) != 0 { ok = false; }
  if pe_section_raw_pointer(&re, 0) != 0 { ok = false; }
  if pe_entry_point(&re) != 0x1000 { ok = false; }
  let sb = ok_bytes(pe_stub(&out));
  let want = fixture_stub();
  if !bytes_equal(&sb, &want) { ok = false; }
  return assert(ok, "a zero-raw-size spec builds a 472-byte header-only file");
}

// 9. DOS header and signature error catalog.
fn t9() -> TestResult {
  let fx = fixture_pe32plus();
  var ok = img_err_is(pe_parse(&truncate(&fx, 63)), "pe: truncated dos header");
  let mz0 = set_byte(&fx, 0, 0x5A);
  if !img_err_is(pe_parse(&mz0), "pe: bad dos magic") { ok = false; }
  let mz1 = set_byte(&fx, 1, 0x41);
  if !img_err_is(pe_parse(&mz1), "pe: bad dos magic") { ok = false; }
  let lf1 = set_le32(&fx, 60, 63);
  if !img_err_is(pe_parse(&lf1), "pe: invalid e_lfanew") { ok = false; }
  let lf2 = set_le32(&fx, 60, 2558);
  if !img_err_is(pe_parse(&lf2), "pe: e_lfanew out of range") { ok = false; }
  let lf3 = set_le32(&fx, 60, 2540);
  let lf3b = set_le32(&lf3, 2540, 0x4550);
  if !img_err_is(pe_parse(&lf3b), "pe: truncated coff header") { ok = false; }
  let sig0 = set_byte(&fx, 128, 0x51);
  if !img_err_is(pe_parse(&sig0), "pe: bad pe signature") { ok = false; }
  let sig1 = set_byte(&fx, 129, 0x46);
  if !img_err_is(pe_parse(&sig1), "pe: bad pe signature") { ok = false; }
  let sig2 = set_byte(&fx, 130, 1);
  if !img_err_is(pe_parse(&sig2), "pe: bad pe signature") { ok = false; }
  let sig3 = set_byte(&fx, 131, 1);
  if !img_err_is(pe_parse(&sig3), "pe: bad pe signature") { ok = false; }
  if pe_is_valid(&mz0) { ok = false; }
  return assert(ok, "DOS header and signature errors are exact");
}

// 10. COFF and optional header structural errors.
fn t10() -> TestResult {
  let fx = fixture_pe32plus();
  var ok = img_err_is(pe_parse(&set_le16(&fx, 134, 0)), "pe: invalid section count");
  if !img_err_is(pe_parse(&set_le16(&fx, 134, 97)), "pe: invalid section count") { ok = false; }
  if !img_err_is(pe_parse(&set_le16(&fx, 148, 2500)), "pe: truncated optional header") { ok = false; }
  if !img_err_is(pe_parse(&set_le16(&fx, 148, 2)), "pe: optional header too small") { ok = false; }
  if !img_err_is(pe_parse(&set_le16(&fx, 148, 111)), "pe: optional header too small") { ok = false; }
  if !img_err_is(pe_parse(&set_le16(&fx, 152, 0x10A)), "pe: unsupported optional header magic") { ok = false; }
  if !img_err_is(pe_parse(&set_le16(&fx, 152, 0x20A)), "pe: unsupported optional header magic") { ok = false; }
  if !img_err_is(pe_parse(&truncate(&fx, 420)), "pe: truncated section table") { ok = false; }
  if !img_err_is(pe_parse(&set_le16(&fx, 148, 128)), "pe: data directories exceed optional header") { ok = false; }
  let nd17 = set_le32(&fx, 260, 17);
  if !img_err_is(pe_parse(&nd17), "pe: invalid numberOfRvaAndSizes") { ok = false; }
  let hi = set_byte(&fx, 183, 0x80);
  if !img_err_is(pe_parse(&hi), "pe: image base out of range") { ok = false; }
  return assert(ok, "COFF/optional header structural errors are exact");
}

// 11. Alignment validation.
fn t11() -> TestResult {
  let fx = fixture_pe32plus();
  var ok = img_err_is(pe_parse(&set_le32(&fx, 184, 3)), "pe: invalid section alignment");
  if !img_err_is(pe_parse(&set_le32(&fx, 184, 0)), "pe: invalid section alignment") { ok = false; }
  if !img_err_is(pe_parse(&set_le32(&fx, 188, 0x300)), "pe: invalid file alignment") { ok = false; }
  if !img_err_is(pe_parse(&set_le32(&fx, 188, 256)), "pe: invalid file alignment") { ok = false; }
  if !img_err_is(pe_parse(&set_le32(&fx, 188, 131072)), "pe: invalid file alignment") { ok = false; }
  if !img_err_is(pe_parse(&set_le32(&fx, 188, 0)), "pe: invalid file alignment") { ok = false; }
  var good = set_le32(&fx, 184, 512);
  good = set_le32(&good, 188, 512);
  if !pe_is_valid(&good) { ok = false; }
  return assert(ok, "alignment power-of-two and fileAlignment window rules hold");
}

// 12. Section name validation.
fn t12() -> TestResult {
  let fx = fixture_pe32plus();
  var ok = img_err_is(pe_parse(&set_byte(&fx, 392, 47)), "pe: slash-comment section name");
  if !img_err_is(pe_parse(&set_byte(&fx, 393, 1)), "pe: invalid section name") { ok = false; }
  if !img_err_is(pe_parse(&set_byte(&fx, 393, 127)), "pe: invalid section name") { ok = false; }
  if !img_err_is(pe_parse(&set_byte(&fx, 398, 65)), "pe: invalid section name") { ok = false; }
  var z = set_byte(&fx, 392, 0);
  z = set_byte(&z, 393, 0);
  z = set_byte(&z, 394, 0);
  z = set_byte(&z, 395, 0);
  z = set_byte(&z, 396, 0);
  z = set_byte(&z, 397, 0);
  z = set_byte(&z, 398, 0);
  z = set_byte(&z, 399, 0);
  if !img_err_is(pe_parse(&z), "pe: empty section name") { ok = false; }
  var full = set_byte(&fx, 397, 120);
  if !pe_is_valid(&full) { ok = false; }
  var slash2 = set_byte(&fx, 432, 47);
  if !img_err_is(pe_parse(&slash2), "pe: slash-comment section name") { ok = false; }
  return assert(ok, "section names must be 1..8 printable, NUL padded, no '/'");
}

// 13. Section raw span validation.
fn t13() -> TestResult {
  let fx = fixture_pe32plus();
  var ok = img_err_is(pe_parse(&set_le32(&fx, 408, 0x900)), "pe: section raw span out of bounds");
  if !img_err_is(pe_parse(&set_le32(&fx, 412, 100)), "pe: section raw span out of bounds") { ok = false; }
  var zero_size = set_le32(&fx, 408, 0);
  zero_size = set_le32(&zero_size, 412, 100);
  if !img_err_is(pe_parse(&zero_size), "pe: section raw span out of bounds") { ok = false; }
  if !img_err_is(pe_parse(&set_le32(&fx, 448, 0x900)), "pe: section raw span out of bounds") { ok = false; }
  var bss = set_le32(&fx, 408, 0);
  bss = set_le32(&bss, 412, 0);
  if !pe_is_valid(&bss) { ok = false; }
  return assert(ok, "raw spans must start after the header block and end in-buffer");
}

// 14. Builder range and consistency errors.
fn t14() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  let stub = fixture_stub();
  let short_stub = truncate(&stub, 32);
  var ok = bytes_err_is(pe_build_headers(&img, &short_stub), "pe: stub size mismatch");
  var spec = clone_img(&img);
  spec.number_of_sections = 3;
  if !bytes_err_is(pe_build_headers(&spec, &stub), "pe: section count mismatch") { ok = false; }
  var spec2 = clone_img(&img);
  var one = Vec[Int].new();
  one.push(0);
  spec2.section_virtual_sizes = one;
  if !bytes_err_is(pe_build_headers(&spec2, &stub), "pe: section table length mismatch") { ok = false; }
  var spec3 = clone_img(&img);
  spec3.machine = 65536;
  if !bytes_err_is(pe_build_headers(&spec3, &stub), "pe: machine out of range") { ok = false; }
  var spec4 = clone_img(&img);
  spec4.address_of_entry_point = -1;
  if !bytes_err_is(pe_build_headers(&spec4, &stub), "pe: entry point out of range") { ok = false; }
  var spec5 = clone_img(&img);
  spec5.image_base = -1;
  if !bytes_err_is(pe_build_headers(&spec5, &stub), "pe: image base out of range") { ok = false; }
  var spec6 = clone_img(&img);
  spec6.section_alignment = 3;
  if !bytes_err_is(pe_build_headers(&spec6, &stub), "pe: invalid section alignment") { ok = false; }
  var spec7 = clone_img(&img);
  spec7.file_alignment = 100;
  if !bytes_err_is(pe_build_headers(&spec7, &stub), "pe: invalid file alignment") { ok = false; }
  var spec8 = clone_img(&img);
  var bad_sizes = Vec[Int].new();
  bad_sizes.push(-1);
  bad_sizes.push(0x200);
  spec8.section_raw_sizes = bad_sizes;
  if !bytes_err_is(pe_build_headers(&spec8, &stub), "pe: section raw size out of range") { ok = false; }
  var spec9 = clone_img(&img);
  var bad_names = Vec[Str].new();
  bad_names.push("");
  bad_names.push(".rdata");
  spec9.section_names = bad_names;
  if !bytes_err_is(pe_build_headers(&spec9, &stub), "pe: invalid section name") { ok = false; }
  var spec10 = clone_img(&img);
  spec10.number_of_rva_and_sizes = 17;
  if !bytes_err_is(pe_build_headers(&spec10, &stub), "pe: invalid numberOfRvaAndSizes") { ok = false; }
  var spec11 = clone_img(&img);
  spec11.number_of_rva_and_sizes = 15;
  if !bytes_err_is(pe_build_headers(&spec11, &stub), "pe: directory count mismatch") { ok = false; }
  var spec12 = clone_img(&img);
  var bad_vas = Vec[Int].new();
  bad_vas.push(-1);
  spec12.dir_virtual_addresses = bad_vas;
  if !bytes_err_is(pe_build_headers(&spec12, &stub), "pe: directory count mismatch") { ok = false; }
  var spec13 = clone_img(&img);
  spec13.size_of_optional_header = 119;
  if !bytes_err_is(pe_build_headers(&spec13, &stub), "pe: data directories exceed optional header") { ok = false; }
  var spec14 = clone_img(&img);
  var raw_ptrs = Vec[Int].new();
  raw_ptrs.push(0x200);
  raw_ptrs.push(0x800);
  spec14.section_raw_pointers = raw_ptrs;
  spec14.section_raw_sizes = bad_sizes;
  if !bytes_err_is(pe_build_headers(&spec14, &stub), "pe: section raw size out of range") { ok = false; }
  return assert(ok, "pe_build_headers range and consistency errors are exact");
}

// 15. pe_build cross-checks and error forwarding.
fn t15() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  let stub = fixture_stub();
  let empty_raw = Vec[UInt8].new();
  var ok = bytes_err_is(pe_build(&img, &stub, &empty_raw), "pe: raw data size mismatch");
  let raw = collect_raw(&img, &fx);
  let short = truncate(&raw, 0x700);
  if !bytes_err_is(pe_build(&img, &stub, &short), "pe: raw data size mismatch") { ok = false; }
  var overlap = clone_img(&img);
  var ptrs = Vec[Int].new();
  ptrs.push(200);
  ptrs.push(0x800);
  overlap.section_raw_pointers = ptrs;
  if !bytes_err_is(pe_build(&overlap, &stub, &raw), "pe: section raw span out of bounds") { ok = false; }
  var bad_lfanew = clone_img(&img);
  bad_lfanew.pe_offset = 63;
  if !bytes_err_is(pe_build(&bad_lfanew, &stub, &raw), "pe: invalid e_lfanew") { ok = false; }
  let out = ok_bytes(pe_build(&img, &stub, &raw));
  if !bytes_equal(&out, &fx) { ok = false; }
  return assert(ok, "pe_build cross-checks raw data and forwards parse errors");
}

// 16. Out-of-range accessors and pe_find_section bounds.
fn t16() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  var ok = pe_section_count(&img) == 2;
  if !streq(pe_section_name(&img, -1), "") { ok = false; }
  if !streq(pe_section_name(&img, 2), "") { ok = false; }
  if !streq(pe_section_name(&img, 99), "") { ok = false; }
  if pe_section_virtual_size(&img, -1) != -1 { ok = false; }
  if pe_section_virtual_address(&img, 2) != -1 { ok = false; }
  if pe_section_raw_size(&img, -1) != -1 { ok = false; }
  if pe_section_raw_pointer(&img, 2) != -1 { ok = false; }
  if pe_section_reloc_pointer(&img, 9) != -1 { ok = false; }
  if pe_section_line_pointer(&img, 9) != -1 { ok = false; }
  if pe_section_characteristics(&img, -1) != -1 { ok = false; }
  if pe_find_section(&img, ".text2") != -1 { ok = false; }
  if pe_find_section(&img, ".TEXT") != -1 { ok = false; }
  return assert(ok, "accessors return the documented sentinels out of range");
}

// 17. Data directory builder errors.
fn t17() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  let stub = fixture_stub();
  var ok = true;
  var spec = clone_img(&img);
  var vas = Vec[Int].new();
  vas.push(-1);
  spec.dir_virtual_addresses = vas;
  if !bytes_err_is(pe_build_headers(&spec, &stub), "pe: directory count mismatch") { ok = false; }
  var spec2 = clone_img(&img);
  var sizes = Vec[Int].new();
  sizes.push(-1);
  spec2.dir_sizes = sizes;
  if !bytes_err_is(pe_build_headers(&spec2, &stub), "pe: directory table length mismatch") { ok = false; }
  return assert(ok, "directory Vec drift is rejected before emitting");
}

// 18. High-bit u32 fields survive, and the stub/accessor paths error cleanly.
fn t18() -> TestResult {
  let fx = fixture_pe32plus();
  let img = ok_img(pe_parse(&fx));
  let stub = fixture_stub();
  var hi = clone_img(&img);
  hi.time_date_stamp = 4294967295;
  hi.number_of_symbols = 4294967295;
  var chars = Vec[Int].new();
  chars.push(0x60000020);
  chars.push(2147483648);
  hi.section_characteristics = chars;
  let raw = collect_raw(&img, &fx);
  let br = pe_build(&hi, &stub, &raw);
  if !br.is_ok { return assert(false, "high-bit build must succeed"); }
  let out: Vec[UInt8] = br.value;
  let re = ok_img(pe_parse(&out));
  var ok = pe_time_date_stamp(&re) == 4294967295;
  if re.number_of_symbols != 4294967295 { ok = false; }
  if pe_section_characteristics(&re, 1) != 2147483648 { ok = false; }
  if pe_section_characteristics(&re, 0) != 0x60000020 { ok = false; }
  if !bytes_err_is(pe_stub(&truncate(&fx, 10)), "pe: truncated dos header") { ok = false; }
  let sb = ok_bytes(pe_stub(&fx));
  let want = fixture_stub();
  if !bytes_equal(&sb, &want) { ok = false; }
  return assert(ok, "u32 fields with the high bit set round-trip exactly");
}

fn main() -> Int {
  io.println("=== xiom.pe conformance tests ===");
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
    io.println("xiom.pe: all tests passed");
  } else {
    io.println("xiom.pe: tests failed");
  }
  return failed;
}
