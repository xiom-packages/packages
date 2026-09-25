// XIOM -- xiom.pe: PE/COFF header codec (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Parses and builds the header layer of a Windows
// Portable Executable image:
//   * the DOS header ("MZ" magic, e_lfanew at offset 0x3C) plus the DOS
//     stub span between the 64-byte header and e_lfanew;
//   * the "PE\0\0" signature and the 20-byte COFF file header;
//   * the optional header in its PE32 (0x10B) and PE32+ (0x20B) forms,
//     decoded through a documented field subset;
//   * the data directories, carried as raw (virtualAddress, size) records;
//   * the section table: 8-byte names, virtual/raw spans and characteristics.
//
// Storage is flat. PeImage is a single struct of Int/Bool scalars, Str and
// Int vectors: the sections and the data directories are held as parallel
// Vecs (no Vec[StructType], no mirror structs). A hand-built PeImage is the
// builder's spec: the two builders below take it, plus the DOS stub bytes
// (pe_build_headers) or the stub bytes and the concatenated raw section data
// (pe_build).
//
// Documented subset and strictness (full detail in SPEC.md):
//   * section names must be 1..8 printable ASCII bytes (0x20..0x7E), NUL
//     padded; the linker "/nnn" slash-comment long-name form is rejected;
//   * 1..96 sections (the historical IMAGE_NT loader cap);
//   * at most 16 data directories; every directory record is carried raw,
//     never interpreted;
//   * sectionAlignment must be a nonzero power of two; fileAlignment must be
//     a power of two in 512..65536;
//   * imageBase must fit a signed 64-bit Int (bit 63 clear) for PE32+;
//   * a section with sizeOfRawData > 0 must start at or after the end of the
//     header block and end inside the buffer; a zero-size section must have
//     pointerToRawData 0.
//
// Non-goals: no imports/exports/relocations, no resource parsing, no .NET
// metadata, no Authenticode, no payload decoding of any kind.
//
// v0.61.3 notes that shaped this module: every byte read is widened with
// `(data[pos] as Int) & 0xFF`; Ok/Err for struct payloads are only built in
// the leaf helpers below; Str values derived from file bytes come from the
// printable-ASCII table (never sb_to_str, so no NUL can enter a Str); `==`
// is never used on a Str read from a Vec[Str] (pe_find_section goes through
// xiom.string.compare.str_compare and typed locals); every section push is
// mirrored on all eight parallel Vecs; alignments are tested by halving,
// never by bitwise AND; no Vec[StructType], no Vec[fn], no self methods.

module xiom.pe

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed PE header layer, flat storage. All multi-byte fields are decoded
/// little-endian. `pe_offset` is e_lfanew; `stub_size` is
/// `pe_offset - 64` (the DOS stub spans bytes 64..pe_offset). The sections
/// are eight parallel Vecs, index i describing section i; the data
/// directories are two parallel Vecs (`dir_virtual_addresses`,
/// `dir_sizes`). `image_base` carries the PE32 u32 or the PE32+ u64 as a
/// signed Int (bit 63 must be clear). `file_size` is the parsed buffer
/// length.
pub type PeImage = {
  file_size: Int;
  pe_offset: Int;
  stub_size: Int;
  machine: Int;
  number_of_sections: Int;
  time_date_stamp: Int;
  pointer_to_symbol_table: Int;
  number_of_symbols: Int;
  size_of_optional_header: Int;
  characteristics: Int;
  optional_magic: Int;
  address_of_entry_point: Int;
  image_base: Int;
  section_alignment: Int;
  file_alignment: Int;
  size_of_image: Int;
  size_of_headers: Int;
  subsystem: Int;
  number_of_rva_and_sizes: Int;
  dir_virtual_addresses: Vec[Int];
  dir_sizes: Vec[Int];
  section_names: Vec[Str];
  section_virtual_sizes: Vec[Int];
  section_virtual_addresses: Vec[Int];
  section_raw_sizes: Vec[Int];
  section_raw_pointers: Vec[Int];
  section_reloc_pointers: Vec[Int];
  section_line_pointers: Vec[Int];
  section_characteristics: Vec[Int];
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Structural constants.
pub const PE_DOS_MAGIC: Int = 0x5A4D;
pub const PE_DOS_HEADER_SIZE: Int = 64;
pub const PE_LFANEW_OFFSET: Int = 60;
pub const PE_SIGNATURE: Int = 0x00004550;
pub const PE_COFF_HEADER_SIZE: Int = 20;
pub const PE_SECTION_ENTRY_SIZE: Int = 40;
pub const PE_DIRECTORY_ENTRY_SIZE: Int = 8;
pub const PE32_MAGIC: Int = 0x10B;
pub const PE32_PLUS_MAGIC: Int = 0x20B;
pub const PE32_OPTIONAL_SIZE: Int = 96;
pub const PE32_PLUS_OPTIONAL_SIZE: Int = 112;

// Documented caps: 96 sections is the historical IMAGE_NT loader limit and
// 16 is the size of the spec's data directory array.
pub const PE_MAX_SECTIONS: Int = 96;
pub const PE_MAX_RVA_AND_SIZES: Int = 16;

// Documented fileAlignment window.
pub const PE_MIN_FILE_ALIGNMENT: Int = 512;
pub const PE_MAX_FILE_ALIGNMENT: Int = 65536;

// IMAGE_FILE_MACHINE values recognized by pe_machine_name.
pub const PE_MACHINE_I386: Int = 0x14C;
pub const PE_MACHINE_ARM: Int = 0x1C0;
pub const PE_MACHINE_IA64: Int = 0x200;
pub const PE_MACHINE_AMD64: Int = 0x8664;
pub const PE_MACHINE_ARM64: Int = 0xAA64;

// COFF characteristics bits documented by the codec (the field itself is
// carried through untouched, up to its 16-bit width).
pub const PE_FILE_RELOCS_STRIPPED: Int = 0x0001;
pub const PE_FILE_EXECUTABLE_IMAGE: Int = 0x0002;
pub const PE_FILE_LARGE_ADDRESS_AWARE: Int = 0x0020;
pub const PE_FILE_32BIT_MACHINE: Int = 0x0100;
pub const PE_FILE_SYSTEM: Int = 0x1000;
pub const PE_FILE_DLL: Int = 0x2000;

// Section characteristics bits documented by the codec.
pub const PE_SCN_CNT_CODE: Int = 0x00000020;
pub const PE_SCN_CNT_INITIALIZED_DATA: Int = 0x00000040;
pub const PE_SCN_CNT_UNINITIALIZED_DATA: Int = 0x00000080;
pub const PE_SCN_MEM_DISCARDABLE: Int = 0x02000000;
pub const PE_SCN_MEM_EXECUTE: Int = 0x20000000;
pub const PE_SCN_MEM_READ: Int = 0x40000000;
pub const PE_SCN_MEM_WRITE: Int = 0x80000000;

// Subsystem values used by the fixtures.
pub const PE_SUBSYSTEM_WINDOWS_GUI: Int = 2;
pub const PE_SUBSYSTEM_WINDOWS_CUI: Int = 3;

// Offsets inside the COFF file header (relative to pe_offset + 4).
const _COFF_MACHINE: Int = 0;
const _COFF_SECTIONS: Int = 2;
const _COFF_STAMP: Int = 4;
const _COFF_SYM_TABLE: Int = 8;
const _COFF_NUM_SYMBOLS: Int = 12;
const _COFF_OPT_SIZE: Int = 16;
const _COFF_CHARS: Int = 18;

// Offsets inside the optional header (relative to optional_offset). Fields
// shared by both magics are listed once; baseOfData exists only in PE32 and
// is emitted as zero.
const _OPT_ENTRY: Int = 16;
const _OPT_IMAGE_BASE32: Int = 28;
const _OPT_IMAGE_BASE64: Int = 24;
const _OPT_SECTION_ALIGN: Int = 32;
const _OPT_FILE_ALIGN: Int = 36;
const _OPT_SIZE_OF_IMAGE: Int = 56;
const _OPT_SIZE_OF_HEADERS: Int = 60;
const _OPT_SUBSYSTEM: Int = 68;

// Offsets inside a 40-byte section table entry.
const _SEC_NAME: Int = 0;
const _SEC_VSIZE: Int = 8;
const _SEC_VA: Int = 12;
const _SEC_RSIZE: Int = 16;
const _SEC_RPTR: Int = 20;
const _SEC_RELOC: Int = 24;
const _SEC_LINES: Int = 28;
const _SEC_CHARS: Int = 36;

// --------------------------------------------------
//  Byte readers and writers (little-endian)
// --------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Unsigned 16-bit little-endian value at `off`.
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  return b0 + b1 * 256;
}

// Unsigned 32-bit little-endian value at `off`.
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  let b2 = _b(data, off + 2);
  let b3 = _b(data, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Append the low 16 bits of v, little-endian. Callers range-check first.
fn _p16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

// Append the low 32 bits of v, little-endian. Callers range-check first.
fn _p32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// Append n zero bytes (n >= 0; n == 0 appends nothing).
fn _push_zeros(out: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while (i < n) {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Append the bytes of `src` verbatim.
fn _push_bytes(out: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while (i < src.len()) {
    out.push(src[i]);
    i = i + 1;
  }
}

// True when v fits an unsigned 16-bit field.
fn _u16_ok(v: Int) -> Bool {
  if (v < 0) { return false; }
  if (v > 65535) { return false; }
  return true;
}

// True when v fits an unsigned 32-bit field.
fn _u32_ok(v: Int) -> Bool {
  if (v < 0) { return false; }
  if (v > 4294967295) { return false; }
  return true;
}

// True for 1, 2, 4, 8, ... (0 and negatives are not powers of two). Halving
// avoids bitwise AND, which misbehaves on bit-31 operands in v0.61.3.
fn _is_power_of_two(v: Int) -> Bool {
  if (v <= 0) { return false; }
  var x = v;
  while (x > 1) {
    if (x % 2 != 0) { return false; }
    x = x / 2;
  }
  return true;
}

// --------------------------------------------------
//  Name helpers
// --------------------------------------------------

// Printable ASCII 0x20..0x7E, indexed as (byte - 32). This is the only
// source of Str values derived from file bytes, so no NUL byte can ever end
// up inside a Str.
fn _printable_table() -> Str {
  return " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
}

// One printable byte (32..126) as a 1-character Str.
fn _name_char(b: Int) -> Str {
  return string.str_slice(_printable_table(), b - 32, b - 31);
}

// Ok(v) for Result[Str, Str].
fn _ok_name(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_name(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Decode one 8-byte section name field at `base`. A leading '/' is the
// linker slash-comment long-name form and is rejected. Otherwise the name
// runs to the first NUL (or to all 8 bytes); only printable ASCII
// 0x20..0x7E is accepted, bytes after the first NUL must be NUL, and an
// all-NUL field is an empty name. The name is built from the printable
// table, so it can never contain a NUL.
fn _section_name(data: &Vec[UInt8], base: Int) -> Result[Str, Str] {
  if (_b(data, base) == 47) {
    return _err_name("pe: slash-comment section name");
  }
  var name = "";
  var i = 0;
  var ended = false;
  while (i < 8) {
    let c = _b(data, base + i);
    if (c == 0) {
      ended = true;
      i = 8;
    } else {
      if (c < 32 || c > 126) {
        return _err_name("pe: invalid section name");
      }
      name = name + _name_char(c);
      i = i + 1;
    }
  }
  if (ended) {
    var j = name.len();
    while (j < 8) {
      if (_b(data, base + j) != 0) {
        return _err_name("pe: invalid section name");
      }
      j = j + 1;
    }
  }
  if (name.len() == 0) {
    return _err_name("pe: empty section name");
  }
  return _ok_name(name);
}

// True when a builder-supplied name is a valid section name: 1..8 printable
// ASCII bytes, no leading '/' and no NUL. Called with a typed local only.
fn _name_ok(name: Str) -> Bool {
  let n: Int = name.len();
  if (n < 1 || n > 8) { return false; }
  if (((string.byte_at(name, 0) as Int) & 0xFF) == 47) { return false; }
  var i = 0;
  while (i < n) {
    let c: Int = (string.byte_at(name, i) as Int) & 0xFF;
    if (c < 32 || c > 126) { return false; }
    i = i + 1;
  }
  return true;
}

// Append an 8-byte section name field: the name bytes, then NUL padding.
// The caller has checked _name_ok first.
fn _push_name(out: &mut Vec[UInt8], name: Str) {
  let n: Int = name.len();
  var i = 0;
  while (i < 8) {
    if (i < n) {
      let b: UInt8 = string.byte_at(name, i);
      out.push(b);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
}

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

fn _err_image(m: Str) -> Result[PeImage, Str] { return Err(m); }
fn _ok_image(v: PeImage) -> Result[PeImage, Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse and validate the header layer of a PE image buffer. The checks, in
/// order, are documented in SPEC.md: DOS header length and "MZ" magic;
/// e_lfanew at 0x3C with room for the signature (and at least 64, so the
/// stub span is non-negative); the "PE\0\0" signature; the 20-byte COFF
/// header; 1..96 sections; the optional header (PE32 0x10B or PE32+ 0x20B,
/// at least its 96/112-byte base form, with room for the declared data
/// directories); up to 16 raw data directory records; nonzero power-of-two
/// alignments with fileAlignment in 512..65536; the section table inside
/// the buffer; every section name valid; every nonzero raw span starting at
/// or after the header block and ending inside the buffer (a zero-size
/// section must have pointerToRawData 0).
///
/// Err messages are deterministic; see SPEC.md for the catalog.
/// Complexity: O(data.len()).
pub fn pe_parse(data: &Vec[UInt8]) -> Result[PeImage, Str] {
  let total = data.len();
  if (total < PE_DOS_HEADER_SIZE) {
    return _err_image("pe: truncated dos header");
  }
  if (_b(data, 0) != 77) { return _err_image("pe: bad dos magic"); }
  if (_b(data, 1) != 90) { return _err_image("pe: bad dos magic"); }
  let pe_offset = _le32(data, PE_LFANEW_OFFSET);
  if (pe_offset < PE_DOS_HEADER_SIZE) {
    return _err_image("pe: invalid e_lfanew");
  }
  if (pe_offset > total - 4) {
    return _err_image("pe: e_lfanew out of range");
  }
  if (_b(data, pe_offset) != 80) { return _err_image("pe: bad pe signature"); }
  if (_b(data, pe_offset + 1) != 69) { return _err_image("pe: bad pe signature"); }
  if (_b(data, pe_offset + 2) != 0) { return _err_image("pe: bad pe signature"); }
  if (_b(data, pe_offset + 3) != 0) { return _err_image("pe: bad pe signature"); }
  if (pe_offset + 4 + PE_COFF_HEADER_SIZE > total) {
    return _err_image("pe: truncated coff header");
  }
  let machine = _le16(data, pe_offset + 4 + _COFF_MACHINE);
  let nsections = _le16(data, pe_offset + 4 + _COFF_SECTIONS);
  if (nsections < 1 || nsections > PE_MAX_SECTIONS) {
    return _err_image("pe: invalid section count");
  }
  let stamp = _le32(data, pe_offset + 4 + _COFF_STAMP);
  let symtab = _le32(data, pe_offset + 4 + _COFF_SYM_TABLE);
  let nsyms = _le32(data, pe_offset + 4 + _COFF_NUM_SYMBOLS);
  let soh = _le16(data, pe_offset + 4 + _COFF_OPT_SIZE);
  let chars = _le16(data, pe_offset + 4 + _COFF_CHARS);
  let optional_offset = pe_offset + 4 + PE_COFF_HEADER_SIZE;
  if (optional_offset + soh > total) {
    return _err_image("pe: truncated optional header");
  }
  if (soh < 2) {
    return _err_image("pe: optional header too small");
  }
  let magic = _le16(data, optional_offset);
  if (magic != PE32_MAGIC && magic != PE32_PLUS_MAGIC) {
    return _err_image("pe: unsupported optional header magic");
  }
  var base = PE32_OPTIONAL_SIZE;
  if (magic == PE32_PLUS_MAGIC) {
    base = PE32_PLUS_OPTIONAL_SIZE;
  }
  if (soh < base) {
    return _err_image("pe: optional header too small");
  }
  let entry = _le32(data, optional_offset + _OPT_ENTRY);
  var image_base = 0;
  if (magic == PE32_PLUS_MAGIC) {
    let lo = _le32(data, optional_offset + _OPT_IMAGE_BASE64);
    let hi = _le32(data, optional_offset + _OPT_IMAGE_BASE64 + 4);
    if (hi > 2147483647) {
      return _err_image("pe: image base out of range");
    }
    image_base = lo + hi * 4294967296;
  } else {
    image_base = _le32(data, optional_offset + _OPT_IMAGE_BASE32);
  }
  let salign = _le32(data, optional_offset + _OPT_SECTION_ALIGN);
  let falign = _le32(data, optional_offset + _OPT_FILE_ALIGN);
  if (!_is_power_of_two(salign)) {
    return _err_image("pe: invalid section alignment");
  }
  if (!_is_power_of_two(falign)) {
    return _err_image("pe: invalid file alignment");
  }
  if (falign < PE_MIN_FILE_ALIGNMENT || falign > PE_MAX_FILE_ALIGNMENT) {
    return _err_image("pe: invalid file alignment");
  }
  let simage = _le32(data, optional_offset + _OPT_SIZE_OF_IMAGE);
  let sheaders = _le32(data, optional_offset + _OPT_SIZE_OF_HEADERS);
  let subsystem = _le16(data, optional_offset + _OPT_SUBSYSTEM);
  let ndirs = _le32(data, optional_offset + base - 4);
  if (ndirs > PE_MAX_RVA_AND_SIZES) {
    return _err_image("pe: invalid numberOfRvaAndSizes");
  }
  if (base + ndirs * PE_DIRECTORY_ENTRY_SIZE > soh) {
    return _err_image("pe: data directories exceed optional header");
  }
  let dir_offset = optional_offset + base;
  var dir_vas = Vec[Int].new();
  var dir_sizes = Vec[Int].new();
  var i = 0;
  while (i < ndirs) {
    dir_vas.push(_le32(data, dir_offset + i * PE_DIRECTORY_ENTRY_SIZE));
    dir_sizes.push(_le32(data, dir_offset + i * PE_DIRECTORY_ENTRY_SIZE + 4));
    i = i + 1;
  }
  let sections_offset = optional_offset + soh;
  let header_end = sections_offset + nsections * PE_SECTION_ENTRY_SIZE;
  if (header_end > total) {
    return _err_image("pe: truncated section table");
  }
  var names = Vec[Str].new();
  var vsizes = Vec[Int].new();
  var vas = Vec[Int].new();
  var rsizes = Vec[Int].new();
  var rptrs = Vec[Int].new();
  var relocs = Vec[Int].new();
  var lines = Vec[Int].new();
  var schars = Vec[Int].new();
  var k = 0;
  while (k < nsections) {
    let sec = sections_offset + k * PE_SECTION_ENTRY_SIZE;
    let nres = _section_name(data, sec + _SEC_NAME);
    if (!nres.is_ok) { return _err_image(nres.error); }
    let sname: Str = nres.value;
    let vsize = _le32(data, sec + _SEC_VSIZE);
    let va = _le32(data, sec + _SEC_VA);
    let rsize = _le32(data, sec + _SEC_RSIZE);
    let rptr = _le32(data, sec + _SEC_RPTR);
    let reloc = _le32(data, sec + _SEC_RELOC);
    let line = _le32(data, sec + _SEC_LINES);
    let schar = _le32(data, sec + _SEC_CHARS);
    if (rsize == 0) {
      if (rptr != 0) {
        return _err_image("pe: section raw span out of bounds");
      }
    } else {
      if (rptr < header_end) {
        return _err_image("pe: section raw span out of bounds");
      }
      if (rptr + rsize > total) {
        return _err_image("pe: section raw span out of bounds");
      }
    }
    names.push(sname);
    vsizes.push(vsize);
    vas.push(va);
    rsizes.push(rsize);
    rptrs.push(rptr);
    relocs.push(reloc);
    lines.push(line);
    schars.push(schar);
    k = k + 1;
  }
  let img = PeImage{
    file_size: total;
    pe_offset: pe_offset;
    stub_size: pe_offset - PE_DOS_HEADER_SIZE;
    machine: machine;
    number_of_sections: nsections;
    time_date_stamp: stamp;
    pointer_to_symbol_table: symtab;
    number_of_symbols: nsyms;
    size_of_optional_header: soh;
    characteristics: chars;
    optional_magic: magic;
    address_of_entry_point: entry;
    image_base: image_base;
    section_alignment: salign;
    file_alignment: falign;
    size_of_image: simage;
    size_of_headers: sheaders;
    subsystem: subsystem;
    number_of_rva_and_sizes: ndirs;
    dir_virtual_addresses: dir_vas;
    dir_sizes: dir_sizes;
    section_names: names;
    section_virtual_sizes: vsizes;
    section_virtual_addresses: vas;
    section_raw_sizes: rsizes;
    section_raw_pointers: rptrs;
    section_reloc_pointers: relocs;
    section_line_pointers: lines;
    section_characteristics: schars;
  };
  return _ok_image(img);
}

/// True when pe_parse succeeds. Complexity: O(data.len()).
pub fn pe_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = pe_parse(data);
  return r.is_ok;
}

/// Copy the DOS stub span (bytes 64..e_lfanew) out of `data`, which must be
/// the buffer the image was parsed from. Err when pe_parse fails on `data`;
/// a stubless image (e_lfanew == 64) yields an empty Ok.
/// Complexity: O(stub size).
pub fn pe_stub(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let pr = pe_parse(data);
  if (!pr.is_ok) { return _err_bytes(pr.error); }
  let img: PeImage = pr.value;
  let off = PE_DOS_HEADER_SIZE;
  let n = img.stub_size;
  let out = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// COFF IMAGE_FILE_MACHINE value.
pub fn pe_machine(img: &PeImage) -> Int {
  return img.machine;
}

/// Human-readable name for the documented machines: "i386", "arm", "ia64",
/// "amd64", "arm64"; "unknown" otherwise. Complexity: O(1).
pub fn pe_machine_name(machine: Int) -> Str {
  if (machine == PE_MACHINE_I386) { return "i386"; }
  if (machine == PE_MACHINE_ARM) { return "arm"; }
  if (machine == PE_MACHINE_IA64) { return "ia64"; }
  if (machine == PE_MACHINE_AMD64) { return "amd64"; }
  if (machine == PE_MACHINE_ARM64) { return "arm64"; }
  return "unknown";
}

/// Number of sections (the length of the parallel section Vecs).
pub fn pe_section_count(img: &PeImage) -> Int {
  return img.section_names.len();
}

/// Name of section `i` (1..8 printable ASCII characters), or "" when i is
/// negative or out of range. The result is read from a Vec[Str] field:
/// compare it with xiom.string.compare.str_compare rather than `==`.
pub fn pe_section_name(img: &PeImage, i: Int) -> Str {
  if (i < 0 || i >= img.section_names.len()) {
    return "";
  }
  let s: Str = img.section_names[i];
  return s;
}

/// virtualSize of section `i`; -1 out of range.
pub fn pe_section_virtual_size(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.section_virtual_sizes.len()) {
    return -1;
  }
  let v: Int = img.section_virtual_sizes[i];
  return v;
}

/// virtualAddress (RVA) of section `i`; -1 out of range.
pub fn pe_section_virtual_address(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.section_virtual_addresses.len()) {
    return -1;
  }
  let v: Int = img.section_virtual_addresses[i];
  return v;
}

/// sizeOfRawData of section `i`; -1 out of range.
pub fn pe_section_raw_size(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.section_raw_sizes.len()) {
    return -1;
  }
  let v: Int = img.section_raw_sizes[i];
  return v;
}

/// pointerToRawData (absolute file offset) of section `i`; -1 out of range.
pub fn pe_section_raw_pointer(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.section_raw_pointers.len()) {
    return -1;
  }
  let v: Int = img.section_raw_pointers[i];
  return v;
}

/// pointerToRelocations of section `i`; -1 out of range.
pub fn pe_section_reloc_pointer(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.section_reloc_pointers.len()) {
    return -1;
  }
  let v: Int = img.section_reloc_pointers[i];
  return v;
}

/// pointerToLineNumbers of section `i`; -1 out of range.
pub fn pe_section_line_pointer(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.section_line_pointers.len()) {
    return -1;
  }
  let v: Int = img.section_line_pointers[i];
  return v;
}

/// characteristics of section `i` (a u32 carried through untouched); -1 out
/// of range.
pub fn pe_section_characteristics(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.section_characteristics.len()) {
    return -1;
  }
  let v: Int = img.section_characteristics[i];
  return v;
}

/// Index of the first section whose name equals `name` (str_compare, exact
/// case), or -1 when absent. Complexity: O(sections).
pub fn pe_find_section(img: &PeImage, name: Str) -> Int {
  var i = 0;
  while (i < img.section_names.len()) {
    let s: Str = img.section_names[i];
    if (compare.str_compare(s, name) == 0) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// AddressOfEntryPoint RVA.
pub fn pe_entry_point(img: &PeImage) -> Int {
  return img.address_of_entry_point;
}

/// ImageBase: the PE32 u32 or the PE32+ u64 (bit 63 clear) as a signed Int.
pub fn pe_image_base(img: &PeImage) -> Int {
  return img.image_base;
}

/// Subsystem value.
pub fn pe_subsystem(img: &PeImage) -> Int {
  return img.subsystem;
}

/// NumberOfRvaAndSizes: the declared data directory count (0..16).
pub fn pe_directory_count(img: &PeImage) -> Int {
  return img.number_of_rva_and_sizes;
}

/// virtualAddress of data directory `i`; -1 out of range.
pub fn pe_directory_virtual_address(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.number_of_rva_and_sizes) { return -1; }
  if (i >= img.dir_virtual_addresses.len()) { return -1; }
  let v: Int = img.dir_virtual_addresses[i];
  return v;
}

/// size of data directory `i`; -1 out of range.
pub fn pe_directory_size(img: &PeImage, i: Int) -> Int {
  if (i < 0 || i >= img.number_of_rva_and_sizes) { return -1; }
  if (i >= img.dir_sizes.len()) { return -1; }
  let v: Int = img.dir_sizes[i];
  return v;
}

/// e_lfanew: the absolute offset of the "PE\0\0" signature.
pub fn pe_pe_offset(img: &PeImage) -> Int {
  return img.pe_offset;
}

/// Length of the DOS stub span (e_lfanew - 64; 0 when there is no stub).
pub fn pe_stub_size(img: &PeImage) -> Int {
  return img.stub_size;
}

/// Absolute offset of the optional header (e_lfanew + 24).
pub fn pe_optional_offset(img: &PeImage) -> Int {
  return img.pe_offset + 4 + PE_COFF_HEADER_SIZE;
}

/// Optional header magic: 0x10B (PE32) or 0x20B (PE32+).
pub fn pe_optional_magic(img: &PeImage) -> Int {
  return img.optional_magic;
}

/// Parsed buffer length.
pub fn pe_file_size(img: &PeImage) -> Int {
  return img.file_size;
}

/// SizeOfImage.
pub fn pe_size_of_image(img: &PeImage) -> Int {
  return img.size_of_image;
}

/// SizeOfHeaders.
pub fn pe_size_of_headers(img: &PeImage) -> Int {
  return img.size_of_headers;
}

/// SectionAlignment (nonzero power of two).
pub fn pe_section_alignment(img: &PeImage) -> Int {
  return img.section_alignment;
}

/// FileAlignment (power of two in 512..65536).
pub fn pe_file_alignment(img: &PeImage) -> Int {
  return img.file_alignment;
}

/// COFF characteristics bits.
pub fn pe_characteristics(img: &PeImage) -> Int {
  return img.characteristics;
}

/// COFF timeDateStamp.
pub fn pe_time_date_stamp(img: &PeImage) -> Int {
  return img.time_date_stamp;
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Build the whole header block of `img`: DOS header and stub, "PE\0\0",
/// the 20-byte COFF header, the optional header, the data directories and
/// the section table. `stub` must hold exactly `img.stub_size` bytes
/// (bytes 64..e_lfanew of the output). Fields that the parser does not
/// decode -- linker/OS/image version fields, sizeOfCode, checksum, DLL
/// characteristics, stack/heap sizes, numberOfRelocations and
/// numberOfLineNumbers -- are emitted as zero. `img.number_of_sections` must
/// equal the length of every parallel section Vec and
/// `img.number_of_rva_and_sizes` the length of both directory Vecs. Every
/// field is range-checked to its on-disk width; the emitted length is
/// `e_lfanew + 24 + sizeOfOptionalHeader + 40 * number_of_sections`.
/// Error messages are deterministic; see SPEC.md. Complexity: O(header).
pub fn pe_build_headers(img: &PeImage, stub: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if (!_u32_ok(img.pe_offset)) { return _err_bytes("pe: invalid e_lfanew"); }
  if (img.pe_offset < PE_DOS_HEADER_SIZE) { return _err_bytes("pe: invalid e_lfanew"); }
  if (img.stub_size != img.pe_offset - PE_DOS_HEADER_SIZE) {
    return _err_bytes("pe: stub size mismatch");
  }
  if (stub.len() != img.stub_size) { return _err_bytes("pe: stub size mismatch"); }
  if (!_u16_ok(img.machine)) { return _err_bytes("pe: machine out of range"); }
  if (!_u16_ok(img.number_of_sections)) {
    return _err_bytes("pe: section count out of range");
  }
  if (img.number_of_sections < 1 || img.number_of_sections > PE_MAX_SECTIONS) {
    return _err_bytes("pe: invalid section count");
  }
  if (img.number_of_sections != img.section_names.len()) {
    return _err_bytes("pe: section count mismatch");
  }
  let n = img.section_names.len();
  if (img.section_virtual_sizes.len() != n) {
    return _err_bytes("pe: section table length mismatch");
  }
  if (img.section_virtual_addresses.len() != n) {
    return _err_bytes("pe: section table length mismatch");
  }
  if (img.section_raw_sizes.len() != n) {
    return _err_bytes("pe: section table length mismatch");
  }
  if (img.section_raw_pointers.len() != n) {
    return _err_bytes("pe: section table length mismatch");
  }
  if (img.section_reloc_pointers.len() != n) {
    return _err_bytes("pe: section table length mismatch");
  }
  if (img.section_line_pointers.len() != n) {
    return _err_bytes("pe: section table length mismatch");
  }
  if (img.section_characteristics.len() != n) {
    return _err_bytes("pe: section table length mismatch");
  }
  if (!_u32_ok(img.time_date_stamp)) {
    return _err_bytes("pe: time date stamp out of range");
  }
  if (!_u32_ok(img.pointer_to_symbol_table)) {
    return _err_bytes("pe: symbol table pointer out of range");
  }
  if (!_u32_ok(img.number_of_symbols)) {
    return _err_bytes("pe: symbol count out of range");
  }
  if (!_u16_ok(img.size_of_optional_header)) {
    return _err_bytes("pe: optional header size out of range");
  }
  if (!_u16_ok(img.characteristics)) {
    return _err_bytes("pe: characteristics out of range");
  }
  if (img.optional_magic != PE32_MAGIC && img.optional_magic != PE32_PLUS_MAGIC) {
    return _err_bytes("pe: unsupported optional header magic");
  }
  var base = PE32_OPTIONAL_SIZE;
  if (img.optional_magic == PE32_PLUS_MAGIC) {
    base = PE32_PLUS_OPTIONAL_SIZE;
  }
  if (img.size_of_optional_header < base) {
    return _err_bytes("pe: optional header too small");
  }
  if (!_u32_ok(img.address_of_entry_point)) {
    return _err_bytes("pe: entry point out of range");
  }
  if (img.optional_magic == PE32_PLUS_MAGIC) {
    if (img.image_base < 0) { return _err_bytes("pe: image base out of range"); }
  } else {
    if (!_u32_ok(img.image_base)) {
      return _err_bytes("pe: image base out of range");
    }
  }
  if (!_is_power_of_two(img.section_alignment)) {
    return _err_bytes("pe: invalid section alignment");
  }
  if (!_is_power_of_two(img.file_alignment)) {
    return _err_bytes("pe: invalid file alignment");
  }
  if (img.file_alignment < PE_MIN_FILE_ALIGNMENT || img.file_alignment > PE_MAX_FILE_ALIGNMENT) {
    return _err_bytes("pe: invalid file alignment");
  }
  if (!_u32_ok(img.size_of_image)) {
    return _err_bytes("pe: size of image out of range");
  }
  if (!_u32_ok(img.size_of_headers)) {
    return _err_bytes("pe: size of headers out of range");
  }
  if (!_u16_ok(img.subsystem)) { return _err_bytes("pe: subsystem out of range"); }
  if (img.number_of_rva_and_sizes < 0 || img.number_of_rva_and_sizes > PE_MAX_RVA_AND_SIZES) {
    return _err_bytes("pe: invalid numberOfRvaAndSizes");
  }
  if (img.number_of_rva_and_sizes != img.dir_virtual_addresses.len()) {
    return _err_bytes("pe: directory count mismatch");
  }
  if (img.dir_sizes.len() != img.dir_virtual_addresses.len()) {
    return _err_bytes("pe: directory table length mismatch");
  }
  if (base + img.number_of_rva_and_sizes * PE_DIRECTORY_ENTRY_SIZE > img.size_of_optional_header) {
    return _err_bytes("pe: data directories exceed optional header");
  }
  var i = 0;
  while (i < img.number_of_rva_and_sizes) {
    let dva: Int = img.dir_virtual_addresses[i];
    let dsz: Int = img.dir_sizes[i];
    if (!_u32_ok(dva)) {
      return _err_bytes("pe: directory virtual address out of range");
    }
    if (!_u32_ok(dsz)) {
      return _err_bytes("pe: directory size out of range");
    }
    i = i + 1;
  }
  var k = 0;
  while (k < n) {
    let sname: Str = img.section_names[k];
    if (!_name_ok(sname)) { return _err_bytes("pe: invalid section name"); }
    let vsize: Int = img.section_virtual_sizes[k];
    let va: Int = img.section_virtual_addresses[k];
    let rsize: Int = img.section_raw_sizes[k];
    let rptr: Int = img.section_raw_pointers[k];
    let reloc: Int = img.section_reloc_pointers[k];
    let line: Int = img.section_line_pointers[k];
    let schar: Int = img.section_characteristics[k];
    if (!_u32_ok(vsize)) { return _err_bytes("pe: section virtual size out of range"); }
    if (!_u32_ok(va)) { return _err_bytes("pe: section virtual address out of range"); }
    if (!_u32_ok(rsize)) { return _err_bytes("pe: section raw size out of range"); }
    if (!_u32_ok(rptr)) { return _err_bytes("pe: section raw pointer out of range"); }
    if (!_u32_ok(reloc)) { return _err_bytes("pe: relocation pointer out of range"); }
    if (!_u32_ok(line)) { return _err_bytes("pe: line number pointer out of range"); }
    if (!_u32_ok(schar)) {
      return _err_bytes("pe: section characteristics out of range");
    }
    if (rsize == 0 && rptr != 0) {
      return _err_bytes("pe: section raw span out of bounds");
    }
    k = k + 1;
  }
  var out = Vec[UInt8].new();
  out.push(77 as UInt8);
  out.push(90 as UInt8);
  _push_zeros(&mut out, 58);
  _p32(&mut out, img.pe_offset);
  _push_bytes(&mut out, stub);
  out.push(80 as UInt8);
  out.push(69 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  _p16(&mut out, img.machine);
  _p16(&mut out, img.number_of_sections);
  _p32(&mut out, img.time_date_stamp);
  _p32(&mut out, img.pointer_to_symbol_table);
  _p32(&mut out, img.number_of_symbols);
  _p16(&mut out, img.size_of_optional_header);
  _p16(&mut out, img.characteristics);
  _p16(&mut out, img.optional_magic);
  _p16(&mut out, 0);
  _p32(&mut out, 0);
  _p32(&mut out, 0);
  _p32(&mut out, 0);
  _p32(&mut out, img.address_of_entry_point);
  _p32(&mut out, 0);
  if (img.optional_magic == PE32_PLUS_MAGIC) {
    _p32(&mut out, img.image_base % 4294967296);
    _p32(&mut out, img.image_base / 4294967296);
  } else {
    _p32(&mut out, 0);
    _p32(&mut out, img.image_base);
  }
  _p32(&mut out, img.section_alignment);
  _p32(&mut out, img.file_alignment);
  _p16(&mut out, 0);
  _p16(&mut out, 0);
  _p16(&mut out, 0);
  _p16(&mut out, 0);
  _p16(&mut out, 0);
  _p16(&mut out, 0);
  _p32(&mut out, 0);
  _p32(&mut out, img.size_of_image);
  _p32(&mut out, img.size_of_headers);
  _p32(&mut out, 0);
  _p16(&mut out, img.subsystem);
  _p16(&mut out, 0);
  if (img.optional_magic == PE32_PLUS_MAGIC) {
    _p32(&mut out, 0);
    _p32(&mut out, 0);
    _p32(&mut out, 0);
    _p32(&mut out, 0);
    _p32(&mut out, 0);
    _p32(&mut out, 0);
    _p32(&mut out, 0);
    _p32(&mut out, 0);
  } else {
    _p32(&mut out, 0);
    _p32(&mut out, 0);
    _p32(&mut out, 0);
    _p32(&mut out, 0);
  }
  _p32(&mut out, 0);
  _p32(&mut out, img.number_of_rva_and_sizes);
  var d = 0;
  while (d < img.number_of_rva_and_sizes) {
    let dva2: Int = img.dir_virtual_addresses[d];
    let dsz2: Int = img.dir_sizes[d];
    _p32(&mut out, dva2);
    _p32(&mut out, dsz2);
    d = d + 1;
  }
  let pad = img.size_of_optional_header - (base + img.number_of_rva_and_sizes * PE_DIRECTORY_ENTRY_SIZE);
  _push_zeros(&mut out, pad);
  var s = 0;
  while (s < n) {
    let sname2: Str = img.section_names[s];
    let vsize2: Int = img.section_virtual_sizes[s];
    let va2: Int = img.section_virtual_addresses[s];
    let rsize2: Int = img.section_raw_sizes[s];
    let rptr2: Int = img.section_raw_pointers[s];
    let reloc2: Int = img.section_reloc_pointers[s];
    let line2: Int = img.section_line_pointers[s];
    let schar2: Int = img.section_characteristics[s];
    _push_name(&mut out, sname2);
    _p32(&mut out, vsize2);
    _p32(&mut out, va2);
    _p32(&mut out, rsize2);
    _p32(&mut out, rptr2);
    _p32(&mut out, reloc2);
    _p32(&mut out, line2);
    _p16(&mut out, 0);
    _p16(&mut out, 0);
    _p32(&mut out, schar2);
    s = s + 1;
  }
  return _ok_bytes(out);
}

/// Build a whole PE file: the header block from pe_build_headers, then
/// every section's raw bytes at its recorded absolute pointerToRawData,
/// with zero fill everywhere else. `raw` holds the sections' on-disk bytes
/// in table order, concatenated (`raw.len()` must equal the sum of the
/// nonzero sizeOfRawData values). A section with sizeOfRawData > 0 must
/// start at or after the end of the header block; overlapping raw spans are
/// written in table order (the last section wins). The assembled buffer is
/// re-parsed with pe_parse and its error is forwarded unchanged, so a
/// successful build always parses back. Complexity: O(file size).
pub fn pe_build(img: &PeImage, stub: &Vec[UInt8], raw: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let hr = pe_build_headers(img, stub);
  if (!hr.is_ok) { return _err_bytes(hr.error); }
  let headers: Vec[UInt8] = hr.value;
  let hlen = headers.len();
  let n = img.section_names.len();
  var total_raw = 0;
  var i = 0;
  while (i < n) {
    let rs: Int = img.section_raw_sizes[i];
    let rp: Int = img.section_raw_pointers[i];
    if (rs > 0) {
      if (rp < hlen) {
        return _err_bytes("pe: section raw span out of bounds");
      }
      total_raw = total_raw + rs;
    }
    i = i + 1;
  }
  if (raw.len() != total_raw) {
    return _err_bytes("pe: raw data size mismatch");
  }
  var total = hlen;
  var k = 0;
  while (k < n) {
    let rs2: Int = img.section_raw_sizes[k];
    let rp2: Int = img.section_raw_pointers[k];
    if (rs2 > 0) {
      let end = rp2 + rs2;
      if (end > total) { total = end; }
    }
    k = k + 1;
  }
  var out = Vec[UInt8].new();
  var z = 0;
  while (z < total) {
    out.push(0 as UInt8);
    z = z + 1;
  }
  var h = 0;
  while (h < hlen) {
    let hb: UInt8 = headers[h];
    out[h] = hb;
    h = h + 1;
  }
  var cursor = 0;
  var s = 0;
  while (s < n) {
    let rs3: Int = img.section_raw_sizes[s];
    let rp3: Int = img.section_raw_pointers[s];
    if (rs3 > 0) {
      var j = 0;
      while (j < rs3) {
        let rb: UInt8 = raw[cursor + j];
        out[rp3 + j] = rb;
        j = j + 1;
      }
      cursor = cursor + rs3;
    }
    s = s + 1;
  }
  let check = pe_parse(&out);
  if (!check.is_ok) { return _err_bytes(check.error); }
  return _ok_bytes(out);
}
