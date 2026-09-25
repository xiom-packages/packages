// XIOM -- xiom.elf: ELF header and table-layer codec (parse and build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the ELF header (16-byte e_ident, e_type, e_machine, e_version,
// e_entry, e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize/e_phnum,
// e_shentsize/e_shnum, e_shstrndx), the program-header table and the
// section-header table, for 32-bit (class 1) and 64-bit (class 2) files in
// both little-endian (data 1) and big-endian (data 2) byte order.
//
// elf_parse validates the magic, class and data codes, the ident and header
// versions, the fixed header/entry sizes, every table span against the
// buffer, every segment's file bytes, every non-SHT_NOBITS section span,
// the section-name string table (e_shstrndx) and every section name (index
// bounds, NUL termination, printable ASCII). Tables are stored flat in
// parallel Vec fields (no Vec[StructType]); bytes stay in the source buffer
// and are located by offset/size pairs. elf_build_minimal_64le writes a
// canonical 64-bit little-endian ET_EXEC/EM_X86_64 header with no program
// or section tables.
//
// Non-goals: symbol tables, relocations, dynamic-linking semantics,
// disassembly, and writing complete executables.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * Vec[Int] and Vec[Str] element reads are bound to typed locals.
//   * 64-bit fields use the xiom.pack overflow-safe shape: the low seven
//     bytes accumulate with a `place` factor and the top byte is applied
//     separately, so the raw 64-bit pattern is exact (bit 63 set decodes as
//     a negative Int; see SPEC.md).
//   * Str values read from Vec[Str] fields are only compared through
//     xiom.string.compare.str_compare (BUG 17 discipline).
//   * @struct.field is never passed where a &Vec parameter is expected; all
//     helper calls bind a local first.
// See SPEC.md for the byte layout tables, validation order, error catalog
// and test plan.

module xiom.elf

use xiom.string;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// e_ident magic bytes: 0x7F 'E' 'L' 'F'.
pub const ELF_MAGIC0: Int = 127;
pub const ELF_MAGIC1: Int = 69;
pub const ELF_MAGIC2: Int = 76;
pub const ELF_MAGIC3: Int = 70;

// EI_CLASS values.
pub const ELF_CLASS_32: Int = 1;
pub const ELF_CLASS_64: Int = 2;

// EI_DATA values.
pub const ELF_DATA_2LSB: Int = 1;
pub const ELF_DATA_2MSB: Int = 2;

// EI_VERSION and e_version value (EV_CURRENT).
pub const ELF_EV_CURRENT: Int = 1;

// e_type values (subset documented here).
pub const ELF_ET_REL: Int = 1;
pub const ELF_ET_EXEC: Int = 2;
pub const ELF_ET_DYN: Int = 3;
pub const ELF_ET_CORE: Int = 4;

// e_machine values (subset documented here).
pub const ELF_EM_386: Int = 3;
pub const ELF_EM_PPC64: Int = 21;
pub const ELF_EM_X86_64: Int = 62;
pub const ELF_EM_AARCH64: Int = 183;

// Fixed table/header entry sizes per class.
pub const ELF_EHDR32_SIZE: Int = 52;
pub const ELF_EHDR64_SIZE: Int = 64;
pub const ELF_PHDR32_SIZE: Int = 32;
pub const ELF_PHDR64_SIZE: Int = 56;
pub const ELF_SHDR32_SIZE: Int = 40;
pub const ELF_SHDR64_SIZE: Int = 64;

// e_shstrndx special values.
pub const ELF_SHN_UNDEF: Int = 0;
pub const ELF_SHN_XINDEX: Int = 65535;

// p_type values (subset documented here).
pub const ELF_PT_NULL: Int = 0;
pub const ELF_PT_LOAD: Int = 1;
pub const ELF_PT_DYNAMIC: Int = 2;
pub const ELF_PT_INTERP: Int = 3;
pub const ELF_PT_NOTE: Int = 4;
pub const ELF_PT_PHDR: Int = 6;

// p_flags bits: the low three are documented; higher bits are preserved.
pub const ELF_PF_X: Int = 1;
pub const ELF_PF_W: Int = 2;
pub const ELF_PF_R: Int = 4;

// sh_type values (subset documented here).
pub const ELF_SHT_NULL: Int = 0;
pub const ELF_SHT_PROGBITS: Int = 1;
pub const ELF_SHT_STRTAB: Int = 3;
pub const ELF_SHT_NOBITS: Int = 8;

// sh_flags bits (subset documented here).
pub const ELF_SHF_WRITE: Int = 1;
pub const ELF_SHF_ALLOC: Int = 2;
pub const ELF_SHF_EXECINSTR: Int = 4;

// elf_program_field selectors.
pub const ELF_PH_FIELD_TYPE: Int = 0;
pub const ELF_PH_FIELD_FLAGS: Int = 1;
pub const ELF_PH_FIELD_OFFSET: Int = 2;
pub const ELF_PH_FIELD_VADDR: Int = 3;
pub const ELF_PH_FIELD_PADDR: Int = 4;
pub const ELF_PH_FIELD_FILESZ: Int = 5;
pub const ELF_PH_FIELD_MEMSZ: Int = 6;
pub const ELF_PH_FIELD_ALIGN: Int = 7;
pub const ELF_PH_FIELD_COUNT: Int = 8;

// elf_section_field selectors.
pub const ELF_SH_FIELD_NAME: Int = 0;
pub const ELF_SH_FIELD_TYPE: Int = 1;
pub const ELF_SH_FIELD_FLAGS: Int = 2;
pub const ELF_SH_FIELD_ADDR: Int = 3;
pub const ELF_SH_FIELD_OFFSET: Int = 4;
pub const ELF_SH_FIELD_SIZE: Int = 5;
pub const ELF_SH_FIELD_LINK: Int = 6;
pub const ELF_SH_FIELD_INFO: Int = 7;
pub const ELF_SH_FIELD_ADDRAALIGN: Int = 8;
pub const ELF_SH_FIELD_ENTSIZE: Int = 9;
pub const ELF_SH_FIELD_COUNT: Int = 10;

// --------------------------------------------------
//  Parsed file index
// --------------------------------------------------

/// Parsed ELF header plus flat program/section tables.
///
/// Scalar fields mirror the ELF header. For program header i, the eight
/// `seg_*` vectors hold p_type, p_flags, p_offset, p_vaddr, p_paddr,
/// p_filesz, p_memsz and p_align in file order. For section header i, the
/// `sec_*` vectors hold sh_name, sh_type, sh_flags, sh_addr, sh_offset,
/// sh_size, sh_link, sh_info, sh_addralign and sh_entsize, `sec_names[i]`
/// is the decoded section name resolved through the shstrtab selected by
/// e_shstrndx ("" when e_shstrndx is SHN_UNDEF), and `sec_name_indices[i]`
/// is the raw sh_name byte offset. All vectors have one slot per table
/// entry and therefore never drift. Bytes stay in the parse buffer.
/// Fields are implementation details; callers use the free functions below.
pub type ElfFile = {
  class: Int;
  endianness: Int;
  ident_version: Int;
  osabi: Int;
  abiversion: Int;
  e_type: Int;
  e_machine: Int;
  e_version: Int;
  e_entry: Int;
  e_phoff: Int;
  e_shoff: Int;
  e_flags: Int;
  e_ehsize: Int;
  e_phentsize: Int;
  e_phnum: Int;
  e_shentsize: Int;
  e_shnum: Int;
  e_shstrndx: Int;
  seg_types: Vec[Int];
  seg_flags: Vec[Int];
  seg_offsets: Vec[Int];
  seg_vaddrs: Vec[Int];
  seg_paddrs: Vec[Int];
  seg_filesz: Vec[Int];
  seg_memsz: Vec[Int];
  seg_aligns: Vec[Int];
  sec_name_indices: Vec[Int];
  sec_names: Vec[Str];
  sec_types: Vec[Int];
  sec_flags: Vec[Int];
  sec_addrs: Vec[Int];
  sec_offsets: Vec[Int];
  sec_sizes: Vec[Int];
  sec_links: Vec[Int];
  sec_infos: Vec[Int];
  sec_addraligns: Vec[Int];
  sec_entsizes: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[ElfFile, Str].
fn _ok_file(v: ElfFile) -> Result[ElfFile, Str] {
  return Ok(v);
}

// Err(m) for Result[ElfFile, Str].
fn _err_file(m: Str) -> Result[ElfFile, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte and field helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Raw `size` (1..8) byte field at `off`: little-endian when `be` is false,
// big-endian when true. For size 8 the raw two's-complement bit pattern is
// returned (bit 63 set decodes as a negative Int, exactly like xiom.pack's
// u64): the low seven bytes accumulate with a `place` factor and the top
// byte is applied separately, so no intermediate overflows. Callers
// guarantee off + size <= data.len().
fn _rdu(data: &Vec[UInt8], off: Int, size: Int, be: Bool) -> Int {
  var nlow = size;
  if size == 8 { nlow = 7; }
  var low: Int = 0;
  var place: Int = 1;
  var i = 0;
  while i < nlow {
    var src = off + i;
    if be { src = off + size - 1 - i; }
    let b = _byte(data, src);
    low = low + b * place;
    place = place * 256;
    i = i + 1;
  }
  if size == 8 {
    var top_src = off + 7;
    if be { top_src = off; }
    let top = _byte(data, top_src);
    if top < 128 {
      return low + top * place;
    }
    let t = top - 128;
    let hi = low + t * place;
    return hi + (0 - 9223372036854775807 - 1);
  }
  return low;
}

// Byte `k` (0 = least significant) of the raw two's-complement bit pattern
// of `v`, as a value in 0..255. Arithmetic only: `& 0xFF` on values with
// bit 31 set miscompiles in v0.61.3 (see xiom.pack / xiom.convert.base58).
fn _low_byte(v: Int, k: Int) -> Int {
  var q = v;
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

// Append the low `size` bytes of `v`, least significant byte first.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_low_byte(v, i) as UInt8);
    i = i + 1;
  }
}

// Append the low `size` bytes of `v`, most significant byte first.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_low_byte(v, i) as UInt8);
    i = i - 1;
  }
}

// --------------------------------------------------
//  Parse stages
// --------------------------------------------------

// e_ident: magic, class, data encoding, ident version, OSABI and ABI
// version. The seven remaining ident bytes are padding and are not
// validated. Fills class/endianness/ident_version/osabi/abiversion.
fn _read_ident(data: &Vec[UInt8], f: &mut ElfFile) -> Result[Unit, Str] {
  if data.len() < 16 {
    return _err_unit("elf: truncated ident");
  }
  if _byte(data, 0) != ELF_MAGIC0 {
    return _err_unit("elf: bad magic");
  }
  if _byte(data, 1) != ELF_MAGIC1 {
    return _err_unit("elf: bad magic");
  }
  if _byte(data, 2) != ELF_MAGIC2 {
    return _err_unit("elf: bad magic");
  }
  if _byte(data, 3) != ELF_MAGIC3 {
    return _err_unit("elf: bad magic");
  }
  let cls = _byte(data, 4);
  if cls != ELF_CLASS_32 && cls != ELF_CLASS_64 {
    return _err_unit("elf: bad class");
  }
  let enc = _byte(data, 5);
  if enc != ELF_DATA_2LSB && enc != ELF_DATA_2MSB {
    return _err_unit("elf: bad data encoding");
  }
  let iv = _byte(data, 6);
  if iv != ELF_EV_CURRENT {
    return _err_unit("elf: bad ident version");
  }
  f.class = cls;
  f.endianness = enc;
  f.ident_version = iv;
  f.osabi = _byte(data, 7);
  f.abiversion = _byte(data, 8);
  return _ok_unit();
}

// The fixed header fields after e_ident. Validates the buffer length, the
// header version and e_ehsize against the class.
fn _read_header(data: &Vec[UInt8], f: &mut ElfFile) -> Result[Unit, Str] {
  let total = data.len();
  let cls: Int = f.class;
  let be: Bool = f.endianness == ELF_DATA_2MSB;
  var hsize = ELF_EHDR32_SIZE;
  if cls == ELF_CLASS_64 { hsize = ELF_EHDR64_SIZE; }
  if total < hsize {
    return _err_unit("elf: truncated header");
  }
  f.e_type = _rdu(data, 16, 2, be);
  f.e_machine = _rdu(data, 18, 2, be);
  f.e_version = _rdu(data, 20, 4, be);
  if cls == ELF_CLASS_64 {
    f.e_entry = _rdu(data, 24, 8, be);
    f.e_phoff = _rdu(data, 32, 8, be);
    f.e_shoff = _rdu(data, 40, 8, be);
    f.e_flags = _rdu(data, 48, 4, be);
    f.e_ehsize = _rdu(data, 52, 2, be);
    f.e_phentsize = _rdu(data, 54, 2, be);
    f.e_phnum = _rdu(data, 56, 2, be);
    f.e_shentsize = _rdu(data, 58, 2, be);
    f.e_shnum = _rdu(data, 60, 2, be);
    f.e_shstrndx = _rdu(data, 62, 2, be);
  } else {
    f.e_entry = _rdu(data, 24, 4, be);
    f.e_phoff = _rdu(data, 28, 4, be);
    f.e_shoff = _rdu(data, 32, 4, be);
    f.e_flags = _rdu(data, 36, 4, be);
    f.e_ehsize = _rdu(data, 40, 2, be);
    f.e_phentsize = _rdu(data, 42, 2, be);
    f.e_phnum = _rdu(data, 44, 2, be);
    f.e_shentsize = _rdu(data, 46, 2, be);
    f.e_shnum = _rdu(data, 48, 2, be);
    f.e_shstrndx = _rdu(data, 50, 2, be);
  }
  if f.e_version != ELF_EV_CURRENT {
    return _err_unit("elf: bad e_version");
  }
  if f.e_ehsize != hsize {
    return _err_unit("elf: bad e_ehsize");
  }
  return _ok_unit();
}

// The program-header table. When e_phnum is 0 there is no table and
// e_phoff/e_phentsize are not validated. Otherwise e_phentsize must equal
// the class entry size, the whole table must fit the buffer, and every
// segment with p_filesz > 0 must have its file bytes inside the buffer (a
// zero-filesz segment carries no file bytes, so p_offset is not validated).
fn _read_programs(data: &Vec[UInt8], f: &mut ElfFile) -> Result[Unit, Str] {
  let total = data.len();
  let cls: Int = f.class;
  let be: Bool = f.endianness == ELF_DATA_2MSB;
  let count: Int = f.e_phnum;
  if count == 0 {
    return _ok_unit();
  }
  var want = ELF_PHDR32_SIZE;
  if cls == ELF_CLASS_64 { want = ELF_PHDR64_SIZE; }
  let esz: Int = f.e_phentsize;
  if esz != want {
    return _err_unit("elf: bad e_phentsize");
  }
  let off0: Int = f.e_phoff;
  let need = count * esz;
  if off0 < 0 || need > total || off0 > total - need {
    return _err_unit("elf: program headers out of bounds");
  }
  var i = 0;
  while i < count {
    let pos = off0 + i * esz;
    var ptype = 0;
    var pflags = 0;
    var poff = 0;
    var pvaddr = 0;
    var ppaddr = 0;
    var pfilesz = 0;
    var pmemsz = 0;
    var palign = 0;
    if cls == ELF_CLASS_64 {
      ptype = _rdu(data, pos, 4, be);
      pflags = _rdu(data, pos + 4, 4, be);
      poff = _rdu(data, pos + 8, 8, be);
      pvaddr = _rdu(data, pos + 16, 8, be);
      ppaddr = _rdu(data, pos + 24, 8, be);
      pfilesz = _rdu(data, pos + 32, 8, be);
      pmemsz = _rdu(data, pos + 40, 8, be);
      palign = _rdu(data, pos + 48, 8, be);
    } else {
      ptype = _rdu(data, pos, 4, be);
      poff = _rdu(data, pos + 4, 4, be);
      pvaddr = _rdu(data, pos + 8, 4, be);
      ppaddr = _rdu(data, pos + 12, 4, be);
      pfilesz = _rdu(data, pos + 16, 4, be);
      pmemsz = _rdu(data, pos + 20, 4, be);
      pflags = _rdu(data, pos + 24, 4, be);
      palign = _rdu(data, pos + 28, 4, be);
    }
    if pfilesz < 0 {
      return _err_unit("elf: segment data out of bounds");
    }
    if pfilesz > 0 {
      if poff < 0 || poff > total || pfilesz > total - poff {
        return _err_unit("elf: segment data out of bounds");
      }
    }
    f.seg_types.push(ptype);
    f.seg_flags.push(pflags);
    f.seg_offsets.push(poff);
    f.seg_vaddrs.push(pvaddr);
    f.seg_paddrs.push(ppaddr);
    f.seg_filesz.push(pfilesz);
    f.seg_memsz.push(pmemsz);
    f.seg_aligns.push(palign);
    i = i + 1;
  }
  return _ok_unit();
}

// The section-header table. When e_shnum is 0 there is no table and
// e_shoff/e_shentsize are not validated. Otherwise e_shentsize must equal
// the class entry size and the whole table must fit the buffer. Section
// spans are checked for every section except SHT_NOBITS, whose sh_offset
// addresses no file bytes (sh_size is the in-memory size); SHT_NOBITS
// sh_offset/sh_size must still be non-negative.
fn _read_sections(data: &Vec[UInt8], f: &mut ElfFile) -> Result[Unit, Str] {
  let total = data.len();
  let cls: Int = f.class;
  let be: Bool = f.endianness == ELF_DATA_2MSB;
  let count: Int = f.e_shnum;
  if count == 0 {
    return _ok_unit();
  }
  var want = ELF_SHDR32_SIZE;
  if cls == ELF_CLASS_64 { want = ELF_SHDR64_SIZE; }
  let esz: Int = f.e_shentsize;
  if esz != want {
    return _err_unit("elf: bad e_shentsize");
  }
  let off0: Int = f.e_shoff;
  let need = count * esz;
  if off0 < 0 || need > total || off0 > total - need {
    return _err_unit("elf: section headers out of bounds");
  }
  var i = 0;
  while i < count {
    let pos = off0 + i * esz;
    var sname = 0;
    var stype = 0;
    var sflags = 0;
    var saddr = 0;
    var soff = 0;
    var ssize = 0;
    var slink = 0;
    var sinfo = 0;
    var salign = 0;
    var sent = 0;
    if cls == ELF_CLASS_64 {
      sname = _rdu(data, pos, 4, be);
      stype = _rdu(data, pos + 4, 4, be);
      sflags = _rdu(data, pos + 8, 8, be);
      saddr = _rdu(data, pos + 16, 8, be);
      soff = _rdu(data, pos + 24, 8, be);
      ssize = _rdu(data, pos + 32, 8, be);
      slink = _rdu(data, pos + 40, 4, be);
      sinfo = _rdu(data, pos + 44, 4, be);
      salign = _rdu(data, pos + 48, 8, be);
      sent = _rdu(data, pos + 56, 8, be);
    } else {
      sname = _rdu(data, pos, 4, be);
      stype = _rdu(data, pos + 4, 4, be);
      sflags = _rdu(data, pos + 8, 4, be);
      saddr = _rdu(data, pos + 12, 4, be);
      soff = _rdu(data, pos + 16, 4, be);
      ssize = _rdu(data, pos + 20, 4, be);
      slink = _rdu(data, pos + 24, 4, be);
      sinfo = _rdu(data, pos + 28, 4, be);
      salign = _rdu(data, pos + 32, 4, be);
      sent = _rdu(data, pos + 36, 4, be);
    }
    if soff < 0 || ssize < 0 {
      return _err_unit("elf: section data out of bounds");
    }
    if stype != ELF_SHT_NOBITS {
      if soff > total || ssize > total - soff {
        return _err_unit("elf: section data out of bounds");
      }
    }
    f.sec_name_indices.push(sname);
    f.sec_types.push(stype);
    f.sec_flags.push(sflags);
    f.sec_addrs.push(saddr);
    f.sec_offsets.push(soff);
    f.sec_sizes.push(ssize);
    f.sec_links.push(slink);
    f.sec_infos.push(sinfo);
    f.sec_addraligns.push(salign);
    f.sec_entsizes.push(sent);
    i = i + 1;
  }
  return _ok_unit();
}

// Resolve every section name through the shstrtab selected by e_shstrndx.
//
// e_shstrndx == SHN_UNDEF (0) means there is no name table: every sh_name
// must then be 0 (the empty name) and every resolved name is "". Otherwise
// e_shstrndx must be a valid section index and that section must be
// SHT_STRTAB; every sh_name must be a byte offset strictly inside its
// sh_size, the name must hit a NUL before the end of the table, and every
// byte before that NUL must be printable ASCII (0x20..0x7E).
fn _read_names(data: &Vec[UInt8], f: &mut ElfFile) -> Result[Unit, Str] {
  let count: Int = f.e_shnum;
  let ndx: Int = f.e_shstrndx;
  if ndx == ELF_SHN_XINDEX {
    return _err_unit("elf: extended section index unsupported (SHN_XINDEX)");
  }
  if count == 0 {
    if ndx != ELF_SHN_UNDEF {
      return _err_unit("elf: shstrndx out of range");
    }
    return _ok_unit();
  }
  if ndx >= count {
    return _err_unit("elf: shstrndx out of range");
  }
  var have_tab = false;
  var tab_off = 0;
  var tab_size = 0;
  if ndx != ELF_SHN_UNDEF {
    let stype: Int = f.sec_types[ndx];
    if stype != ELF_SHT_STRTAB {
      return _err_unit("elf: shstrndx is not a string table");
    }
    have_tab = true;
    tab_off = f.sec_offsets[ndx];
    tab_size = f.sec_sizes[ndx];
  }
  let n: Int = f.sec_name_indices.len();
  let empty: Str = "";
  var i = 0;
  while i < n {
    let name_off: Int = f.sec_name_indices[i];
    if !have_tab {
      if name_off != 0 {
        return _err_unit("elf: no section name string table");
      }
      f.sec_names.push(empty);
    } else {
      if name_off < 0 || name_off >= tab_size {
        return _err_unit("elf: section name index out of bounds");
      }
      var k = name_off;
      var terminated = false;
      while k < tab_size {
        if _byte(data, tab_off + k) == 0 {
          terminated = true;
          break;
        }
        k = k + 1;
      }
      if !terminated {
        return _err_unit("elf: section name not NUL-terminated");
      }
      var bytes = Vec[UInt8].new();
      var j = name_off;
      while j < k {
        let b = _byte(data, tab_off + j);
        if b < 32 || b > 126 {
          return _err_unit("elf: section name not printable ASCII");
        }
        bytes.push(b as UInt8);
        j = j + 1;
      }
      f.sec_names.push(Str::from_utf8(bytes));
    }
    i = i + 1;
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Parse
// --------------------------------------------------

/// Parse an ELF header and its program/section tables.
///
/// Validates, in order: the ident (length, magic, class, data encoding,
/// ident version), the header (length, e_version, e_ehsize), the program
/// table (entry size, span, per-segment file bytes), the section table
/// (entry size, span, per-section file span except SHT_NOBITS) and the
/// section names (shstrndx, name index bounds, NUL termination, printable
/// ASCII). On success the returned ElfFile holds every header field and the
/// flat table vectors in file order; bytes stay in `data`.
/// A file with no tables (e_phnum == 0, e_shnum == 0) is valid, as is an
/// empty section-name string table (e_shstrndx == SHN_UNDEF with all-zero
/// sh_name). Err(m) with an "elf: " message on malformed input; no partial
/// file is returned. Complexity: O(data.len() + table entries).
pub fn elf_parse(data: &Vec[UInt8]) -> Result[ElfFile, Str] {
  var f = ElfFile{
    class: 0;
    endianness: 0;
    ident_version: 0;
    osabi: 0;
    abiversion: 0;
    e_type: 0;
    e_machine: 0;
    e_version: 0;
    e_entry: 0;
    e_phoff: 0;
    e_shoff: 0;
    e_flags: 0;
    e_ehsize: 0;
    e_phentsize: 0;
    e_phnum: 0;
    e_shentsize: 0;
    e_shnum: 0;
    e_shstrndx: 0;
    seg_types: Vec[Int].new();
    seg_flags: Vec[Int].new();
    seg_offsets: Vec[Int].new();
    seg_vaddrs: Vec[Int].new();
    seg_paddrs: Vec[Int].new();
    seg_filesz: Vec[Int].new();
    seg_memsz: Vec[Int].new();
    seg_aligns: Vec[Int].new();
    sec_name_indices: Vec[Int].new();
    sec_names: Vec[Str].new();
    sec_types: Vec[Int].new();
    sec_flags: Vec[Int].new();
    sec_addrs: Vec[Int].new();
    sec_offsets: Vec[Int].new();
    sec_sizes: Vec[Int].new();
    sec_links: Vec[Int].new();
    sec_infos: Vec[Int].new();
    sec_addraligns: Vec[Int].new();
    sec_entsizes: Vec[Int].new();
  };
  let r1 = _read_ident(data, &mut f);
  if !r1.is_ok { return _err_file(r1.error); }
  let r2 = _read_header(data, &mut f);
  if !r2.is_ok { return _err_file(r2.error); }
  let r3 = _read_programs(data, &mut f);
  if !r3.is_ok { return _err_file(r3.error); }
  let r4 = _read_sections(data, &mut f);
  if !r4.is_ok { return _err_file(r4.error); }
  let r5 = _read_names(data, &mut f);
  if !r5.is_ok { return _err_file(r5.error); }
  return _ok_file(f);
}

// --------------------------------------------------
//  Header accessors
// --------------------------------------------------

/// EI_CLASS of the file: 1 (32-bit) or 2 (64-bit). Complexity: O(1).
pub fn elf_class(f: &ElfFile) -> Int {
  return f.class;
}

/// EI_DATA of the file: 1 (little-endian) or 2 (big-endian).
/// Complexity: O(1).
pub fn elf_endianness(f: &ElfFile) -> Int {
  return f.endianness;
}

/// EI_OSABI as stored (pass-through; not validated). Complexity: O(1).
pub fn elf_osabi(f: &ElfFile) -> Int {
  return f.osabi;
}

/// e_type (ET_*). Complexity: O(1).
pub fn elf_file_type(f: &ElfFile) -> Int {
  return f.e_type;
}

/// e_machine (EM_*). Complexity: O(1).
pub fn elf_machine(f: &ElfFile) -> Int {
  return f.e_machine;
}

/// e_entry: the raw entry-point field (for 64-bit files a value with bit 63
/// set decodes as a negative Int). Complexity: O(1).
pub fn elf_entry(f: &ElfFile) -> Int {
  return f.e_entry;
}

/// e_flags as stored (machine-specific pass-through). Complexity: O(1).
pub fn elf_flags(f: &ElfFile) -> Int {
  return f.e_flags;
}

/// e_phoff: program-header table file offset. Complexity: O(1).
pub fn elf_phoff(f: &ElfFile) -> Int {
  return f.e_phoff;
}

/// e_shoff: section-header table file offset. Complexity: O(1).
pub fn elf_shoff(f: &ElfFile) -> Int {
  return f.e_shoff;
}

/// e_shstrndx: section-name string table index (SHN_UNDEF when absent).
/// Complexity: O(1).
pub fn elf_shstrndx(f: &ElfFile) -> Int {
  return f.e_shstrndx;
}

/// Number of parsed program headers. Complexity: O(1).
pub fn elf_program_count(f: &ElfFile) -> Int {
  return f.seg_types.len();
}

/// Number of parsed section headers. Complexity: O(1).
pub fn elf_section_count(f: &ElfFile) -> Int {
  return f.sec_types.len();
}

// --------------------------------------------------
//  Table accessors
// --------------------------------------------------

/// Field `field` (an ELF_PH_FIELD_* selector) of program header `i`.
///
/// Err("elf: index out of range") when i is negative or >=
/// elf_program_count(f); Err("elf: bad field selector") when field is not a
/// known ELF_PH_FIELD_* value. The raw parsed value is returned (no range
/// or alignment validation). Complexity: O(1).
pub fn elf_program_field(f: &ElfFile, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.seg_types.len() {
    return _err_int("elf: index out of range");
  }
  if field == ELF_PH_FIELD_TYPE {
    let v: Int = f.seg_types[i];
    return _ok_int(v);
  }
  if field == ELF_PH_FIELD_FLAGS {
    let v: Int = f.seg_flags[i];
    return _ok_int(v);
  }
  if field == ELF_PH_FIELD_OFFSET {
    let v: Int = f.seg_offsets[i];
    return _ok_int(v);
  }
  if field == ELF_PH_FIELD_VADDR {
    let v: Int = f.seg_vaddrs[i];
    return _ok_int(v);
  }
  if field == ELF_PH_FIELD_PADDR {
    let v: Int = f.seg_paddrs[i];
    return _ok_int(v);
  }
  if field == ELF_PH_FIELD_FILESZ {
    let v: Int = f.seg_filesz[i];
    return _ok_int(v);
  }
  if field == ELF_PH_FIELD_MEMSZ {
    let v: Int = f.seg_memsz[i];
    return _ok_int(v);
  }
  if field == ELF_PH_FIELD_ALIGN {
    let v: Int = f.seg_aligns[i];
    return _ok_int(v);
  }
  return _err_int("elf: bad field selector");
}

/// Field `field` (an ELF_SH_FIELD_* selector) of section header `i`.
///
/// Err("elf: index out of range") when i is negative or >=
/// elf_section_count(f); Err("elf: bad field selector") when field is not a
/// known ELF_SH_FIELD_* value. ELF_SH_FIELD_NAME is the raw sh_name byte
/// offset, not the resolved name (use elf_section_name for that).
/// Complexity: O(1).
pub fn elf_section_field(f: &ElfFile, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.sec_types.len() {
    return _err_int("elf: index out of range");
  }
  if field == ELF_SH_FIELD_NAME {
    let v: Int = f.sec_name_indices[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_TYPE {
    let v: Int = f.sec_types[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_FLAGS {
    let v: Int = f.sec_flags[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_ADDR {
    let v: Int = f.sec_addrs[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_OFFSET {
    let v: Int = f.sec_offsets[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_SIZE {
    let v: Int = f.sec_sizes[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_LINK {
    let v: Int = f.sec_links[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_INFO {
    let v: Int = f.sec_infos[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_ADDRAALIGN {
    let v: Int = f.sec_addraligns[i];
    return _ok_int(v);
  }
  if field == ELF_SH_FIELD_ENTSIZE {
    let v: Int = f.sec_entsizes[i];
    return _ok_int(v);
  }
  return _err_int("elf: bad field selector");
}

/// Decoded name of section header `i` (resolved through the shstrtab).
///
/// Err("elf: index out of range") when i is negative or >=
/// elf_section_count(f). The returned Str is read from a Vec[Str] field:
/// callers must compare it with xiom.string.compare.str_compare rather than
/// `==`. Complexity: O(1).
pub fn elf_section_name(f: &ElfFile, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.sec_names.len() {
    return _err_str("elf: index out of range");
  }
  let nm: Str = f.sec_names[i];
  return _ok_str(nm);
}

/// Index of the first section whose decoded name equals `name`, or -1 when
/// absent (including on an empty section table). Comparison is exact
/// (case-sensitive) via xiom.string.compare.str_compare, and duplicate
/// names resolve to the first match. Complexity: O(sections * name length).
pub fn elf_section_index(f: &ElfFile, name: Str) -> Int {
  let n: Int = f.sec_names.len();
  var i = 0;
  while i < n {
    let cur: Str = f.sec_names[i];
    if string.str_compare(cur, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

/// Build a canonical minimal 64-bit little-endian ELF header (64 bytes):
/// e_ident class 2 / data 1 / version 1 with zero OSABI, ABI version and
/// padding, e_type ET_EXEC (2), e_machine EM_X86_64 (62), e_version
/// EV_CURRENT (1), the given `entry`, zero e_phoff/e_shoff/e_flags, and
/// e_ehsize 64 / e_phentsize 56 / e_phnum 0 / e_shentsize 64 / e_shnum 0 /
/// e_shstrndx 0 -- so the result declares no program and no section tables.
///
/// Err("elf: negative entry") when entry < 0. Complexity: O(1).
pub fn elf_build_minimal_64le(entry: Int) -> Result[Vec[UInt8], Str] {
  if entry < 0 {
    return _err_bytes("elf: negative entry");
  }
  var out = Vec[UInt8].new();
  out.push(ELF_MAGIC0 as UInt8);
  out.push(ELF_MAGIC1 as UInt8);
  out.push(ELF_MAGIC2 as UInt8);
  out.push(ELF_MAGIC3 as UInt8);
  out.push(ELF_CLASS_64 as UInt8);
  out.push(ELF_DATA_2LSB as UInt8);
  out.push(ELF_EV_CURRENT as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  var pad = 0;
  while pad < 7 {
    out.push(0 as UInt8);
    pad = pad + 1;
  }
  _push_le(&mut out, ELF_ET_EXEC, 2);
  _push_le(&mut out, ELF_EM_X86_64, 2);
  _push_le(&mut out, ELF_EV_CURRENT, 4);
  _push_le(&mut out, entry, 8);
  _push_le(&mut out, 0, 8);
  _push_le(&mut out, 0, 8);
  _push_le(&mut out, 0, 4);
  _push_le(&mut out, ELF_EHDR64_SIZE, 2);
  _push_le(&mut out, ELF_PHDR64_SIZE, 2);
  _push_le(&mut out, 0, 2);
  _push_le(&mut out, ELF_SHDR64_SIZE, 2);
  _push_le(&mut out, 0, 2);
  _push_le(&mut out, 0, 2);
  return _ok_bytes(out);
}
