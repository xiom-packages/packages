// XIOM -- xiom.apple: Apple executable/container structure parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the structural layer of Apple Mach-O containers.
//   * thin Mach-O: the four magics (0xFEEDFACE / 0xFEEDFACF and their
//     byte-swapped forms), mach_header / mach_header_64 fields (cputype,
//     cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved) and the
//     load-command walk: LC_SEGMENT / LC_SEGMENT_64 (segment name, vmaddr,
//     vmsize, fileoff, filesize, maxprot/initprot, nsects, flags and the
//     section records with sectname/segname/addr/size/offset/align/flags),
//     the dylib family (LC_LOAD_DYLIB, LC_ID_DYLIB, LC_LOAD_WEAK_DYLIB,
//     LC_REEXPORT_DYLIB, LC_LOAD_UPWARD_DYLIB, LC_LAZY_LOAD_DYLIB: name
//     offset, timestamp, current/compatibility version), LC_UUID (16 raw
//     bytes), LC_MAIN (entryoff, stacksize), LC_CODE_SIGNATURE and the
//     linkedit-data family (dataoff, datasize), LC_BUILD_VERSION (platform,
//     minos, sdk, ntools), LC_VERSION_MIN_* (version, sdk), LC_SYMTAB
//     (table locations only), LC_SOURCE_VERSION, LC_ENCRYPTION_INFO(_64),
//     the lc_str commands (LC_LOAD_DYLINKER, LC_ID_DYLINKER,
//     LC_DYLD_ENVIRONMENT, LC_RPATH, LC_SUB_*), and unknown/undecoded
//     commands preserved with their raw cmd/cmdsize/offset span.
//   * fat/universal archives: fat_header + fat_arch records for the 32-bit
//     big-endian FAT_MAGIC and little-endian FAT_CIGAM variants (nfat_arch,
//     cputype, cpusubtype, offset, size, align), with slice bounds,
//     power-of-two alignment and overlap validation, a slice-selection
//     helper for a cputype and a slice copy helper.
//
// Non-goals: instruction/symbol decoding (the LC_SYMTAB location is
// recorded but nlist entries are never decoded), relocations, dyld
// bind/export/lazy semantics, Objective-C metadata, code-signature
// verification, and 64-bit fat (FAT_MAGIC_64) arch records.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType];
//     tables are parallel Vec fields (one slot per command/segment/section).
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * Vec[Int] and Vec[Str] element reads are bound to typed locals.
//   * 64-bit fields use the overflow-safe two's-complement shape: the low
//     seven bytes accumulate with a `place` factor and the top byte is
//     applied separately, so the raw 64-bit pattern is exact (bit 63 set
//     decodes as a negative Int; see SPEC.md).
//   * Str values read from Vec[Str] fields are compared by callers through
//     xiom.string.compare.str_compare, never `==` (BUG 17 discipline).
//   * @struct.field is never passed where a &Vec parameter is expected; all
//     helper calls bind a local first.
//   * error messages embed the exact byte offset through xiom.convert.itos.
// See SPEC.md for the byte layouts, validation order and error catalog.

module xiom.apple

use xiom.convert.itos;

// --------------------------------------------------
//  Public constants -- magics and format codes
// --------------------------------------------------

// On-disk magic constants, read as a big-endian u32 of the first four
// bytes: MH_MAGIC / MH_MAGIC_64 are the big-endian (legacy PowerPC) forms,
// MH_CIGAM / MH_CIGAM_64 the byte-swapped little-endian forms.
pub const APPLE_MH_MAGIC: Int = 0xFEEDFACE;
pub const APPLE_MH_MAGIC_64: Int = 0xFEEDFACF;
pub const APPLE_MH_CIGAM: Int = 0xCEFAEDFE;
pub const APPLE_MH_CIGAM_64: Int = 0xCFFAEDFE;
pub const APPLE_FAT_MAGIC: Int = 0xCAFEBABE;
pub const APPLE_FAT_CIGAM: Int = 0xBEBAFECA;
pub const APPLE_FAT_MAGIC_64: Int = 0xCAFEBABF;
pub const APPLE_FAT_CIGAM_64: Int = 0xBFBAFECA;

// apple_format codes.
pub const APPLE_FORMAT_UNKNOWN: Int = 0;
pub const APPLE_FORMAT_MACHO32_BE: Int = 1;
pub const APPLE_FORMAT_MACHO32_LE: Int = 2;
pub const APPLE_FORMAT_MACHO64_BE: Int = 3;
pub const APPLE_FORMAT_MACHO64_LE: Int = 4;
pub const APPLE_FORMAT_FAT_BE: Int = 5;
pub const APPLE_FORMAT_FAT_LE: Int = 6;
pub const APPLE_FORMAT_FAT64_BE: Int = 7;
pub const APPLE_FORMAT_FAT64_LE: Int = 8;

// Endianness codes.
pub const APPLE_ENDIAN_LE: Int = 1;
pub const APPLE_ENDIAN_BE: Int = 2;

// cputype constants (CPU_ARCH_ABI64 adds the 64-bit ABI bit).
pub const APPLE_CPU_ARCH_ABI64: Int = 0x01000000;
pub const APPLE_CPU_ARCH_ABI64_32: Int = 0x02000000;
pub const APPLE_CPU_TYPE_X86: Int = 7;
pub const APPLE_CPU_TYPE_X86_64: Int = 0x01000007;
pub const APPLE_CPU_TYPE_ARM: Int = 12;
pub const APPLE_CPU_TYPE_ARM64: Int = 0x0100000C;
pub const APPLE_CPU_TYPE_ARM64_32: Int = 0x0200000C;
pub const APPLE_CPU_TYPE_PPC: Int = 18;
pub const APPLE_CPU_TYPE_PPC64: Int = 0x01000012;

// macho_cpu_class results.
pub const APPLE_CPU_CLASS_UNKNOWN: Int = 0;
pub const APPLE_CPU_CLASS_X86: Int = 1;
pub const APPLE_CPU_CLASS_X86_64: Int = 2;
pub const APPLE_CPU_CLASS_ARM: Int = 3;
pub const APPLE_CPU_CLASS_ARM64: Int = 4;
pub const APPLE_CPU_CLASS_ARM64_32: Int = 5;
pub const APPLE_CPU_CLASS_PPC: Int = 6;
pub const APPLE_CPU_CLASS_PPC64: Int = 7;

// filetype values.
pub const APPLE_MH_OBJECT: Int = 1;
pub const APPLE_MH_EXECUTE: Int = 2;
pub const APPLE_MH_FVMLIB: Int = 3;
pub const APPLE_MH_CORE: Int = 4;
pub const APPLE_MH_PRELOAD: Int = 5;
pub const APPLE_MH_DYLIB: Int = 6;
pub const APPLE_MH_DYLINKER: Int = 7;
pub const APPLE_MH_BUNDLE: Int = 8;
pub const APPLE_MH_DYLIB_STUB: Int = 9;
pub const APPLE_MH_DSYM: Int = 10;
pub const APPLE_MH_KEXT_BUNDLE: Int = 11;
pub const APPLE_MH_FILESET: Int = 12;

// mach_header flags (all single-bit masks; see macho_has_flag).
pub const APPLE_MH_NOUNDEFS: Int = 0x1;
pub const APPLE_MH_INCRLINK: Int = 0x2;
pub const APPLE_MH_DYLDLINK: Int = 0x4;
pub const APPLE_MH_BINDATLOAD: Int = 0x8;
pub const APPLE_MH_PREBOUND: Int = 0x10;
pub const APPLE_MH_SPLIT_SEGS: Int = 0x20;
pub const APPLE_MH_LAZY_INIT: Int = 0x40;
pub const APPLE_MH_TWOLEVEL: Int = 0x80;
pub const APPLE_MH_FORCE_FLAT: Int = 0x100;
pub const APPLE_MH_NOMULTIDEFS: Int = 0x200;
pub const APPLE_MH_NOFIXPREBINDING: Int = 0x400;
pub const APPLE_MH_PREBINDABLE: Int = 0x800;
pub const APPLE_MH_ALLMODSBOUND: Int = 0x1000;
pub const APPLE_MH_SUBSECTIONS_VIA_SYMBOLS: Int = 0x2000;
pub const APPLE_MH_CANONICAL: Int = 0x4000;
pub const APPLE_MH_WEAK_DEFINES: Int = 0x8000;
pub const APPLE_MH_BINDS_TO_WEAK: Int = 0x10000;
pub const APPLE_MH_ALLOW_STACK_EXECUTION: Int = 0x20000;
pub const APPLE_MH_ROOT_SAFE: Int = 0x40000;
pub const APPLE_MH_SETUID_SAFE: Int = 0x80000;
pub const APPLE_MH_NO_REEXPORTED_DYLIBS: Int = 0x100000;
pub const APPLE_MH_PIE: Int = 0x200000;
pub const APPLE_MH_DEAD_STRIPPABLE_DYLIB: Int = 0x400000;
pub const APPLE_MH_HAS_TLV_DESCRIPTORS: Int = 0x800000;
pub const APPLE_MH_NO_HEAP_EXECUTION: Int = 0x1000000;
pub const APPLE_MH_APP_EXTENSION_SAFE: Int = 0x2000000;
pub const APPLE_MH_NLIST_OUTOFSYNC_WITH_DYLDINFO: Int = 0x4000000;
pub const APPLE_MH_SIM_SUPPORT: Int = 0x8000000;
pub const APPLE_MH_DYLIB_IN_CACHE: Int = 0x80000000;

// Load command values (LC_REQ_DYLD = 0x80000000 is already OR'd in).
pub const APPLE_LC_SEGMENT: Int = 0x1;
pub const APPLE_LC_SYMTAB: Int = 0x2;
pub const APPLE_LC_SYMSEG: Int = 0x3;
pub const APPLE_LC_THREAD: Int = 0x4;
pub const APPLE_LC_UNIXTHREAD: Int = 0x5;
pub const APPLE_LC_LOADFVMLIB: Int = 0x6;
pub const APPLE_LC_IDFVMLIB: Int = 0x7;
pub const APPLE_LC_IDENT: Int = 0x8;
pub const APPLE_LC_FVMFILE: Int = 0x9;
pub const APPLE_LC_PREPAGE: Int = 0xA;
pub const APPLE_LC_DYSYMTAB: Int = 0xB;
pub const APPLE_LC_LOAD_DYLIB: Int = 0xC;
pub const APPLE_LC_ID_DYLIB: Int = 0xD;
pub const APPLE_LC_LOAD_DYLINKER: Int = 0xE;
pub const APPLE_LC_ID_DYLINKER: Int = 0xF;
pub const APPLE_LC_PREBOUND_DYLIB: Int = 0x10;
pub const APPLE_LC_ROUTINES: Int = 0x11;
pub const APPLE_LC_SUB_FRAMEWORK: Int = 0x12;
pub const APPLE_LC_SUB_UMBRELLA: Int = 0x13;
pub const APPLE_LC_SUB_CLIENT: Int = 0x14;
pub const APPLE_LC_SUB_LIBRARY: Int = 0x15;
pub const APPLE_LC_TWOLEVEL_HINTS: Int = 0x16;
pub const APPLE_LC_PREBIND_CKSUM: Int = 0x17;
pub const APPLE_LC_SEGMENT_64: Int = 0x19;
pub const APPLE_LC_ROUTINES_64: Int = 0x1A;
pub const APPLE_LC_UUID: Int = 0x1B;
pub const APPLE_LC_CODE_SIGNATURE: Int = 0x1D;
pub const APPLE_LC_SEGMENT_SPLIT_INFO: Int = 0x1E;
pub const APPLE_LC_LAZY_LOAD_DYLIB: Int = 0x20;
pub const APPLE_LC_ENCRYPTION_INFO: Int = 0x21;
pub const APPLE_LC_DYLD_INFO: Int = 0x22;
pub const APPLE_LC_VERSION_MIN_MACOSX: Int = 0x24;
pub const APPLE_LC_VERSION_MIN_IPHONEOS: Int = 0x25;
pub const APPLE_LC_FUNCTION_STARTS: Int = 0x26;
pub const APPLE_LC_DYLD_ENVIRONMENT: Int = 0x27;
pub const APPLE_LC_DATA_IN_CODE: Int = 0x29;
pub const APPLE_LC_SOURCE_VERSION: Int = 0x2A;
pub const APPLE_LC_DYLIB_CODE_SIGN_DRS: Int = 0x2B;
pub const APPLE_LC_ENCRYPTION_INFO_64: Int = 0x2C;
pub const APPLE_LC_LINKER_OPTION: Int = 0x2D;
pub const APPLE_LC_LINKER_OPTIMIZATION_HINT: Int = 0x2E;
pub const APPLE_LC_VERSION_MIN_TVOS: Int = 0x2F;
pub const APPLE_LC_VERSION_MIN_WATCHOS: Int = 0x30;
pub const APPLE_LC_NOTE: Int = 0x31;
pub const APPLE_LC_BUILD_VERSION: Int = 0x32;
pub const APPLE_LC_LOAD_WEAK_DYLIB: Int = 0x80000018;
pub const APPLE_LC_RPATH: Int = 0x8000001C;
pub const APPLE_LC_REEXPORT_DYLIB: Int = 0x8000001F;
pub const APPLE_LC_DYLD_INFO_ONLY: Int = 0x80000022;
pub const APPLE_LC_LOAD_UPWARD_DYLIB: Int = 0x80000023;
pub const APPLE_LC_MAIN: Int = 0x80000028;
pub const APPLE_LC_DYLD_EXPORTS_TRIE: Int = 0x80000033;
pub const APPLE_LC_DYLD_CHAINED_FIXUPS: Int = 0x80000034;
pub const APPLE_LC_FILESET_ENTRY: Int = 0x80000035;

// Decoded load-command kinds (macho_command_field APPLE_LC_FIELD_KIND).
pub const APPLE_LCK_UNKNOWN: Int = 0;
pub const APPLE_LCK_SEGMENT: Int = 1;
pub const APPLE_LCK_SEGMENT_64: Int = 2;
pub const APPLE_LCK_DYLIB: Int = 3;
pub const APPLE_LCK_UUID: Int = 4;
pub const APPLE_LCK_MAIN: Int = 5;
pub const APPLE_LCK_LINKEDIT_DATA: Int = 6;
pub const APPLE_LCK_BUILD_VERSION: Int = 7;
pub const APPLE_LCK_VERSION_MIN: Int = 8;
pub const APPLE_LCK_SYMTAB: Int = 9;
pub const APPLE_LCK_DYSYMTAB: Int = 10;
pub const APPLE_LCK_DYLD_INFO: Int = 11;
pub const APPLE_LCK_SOURCE_VERSION: Int = 12;
pub const APPLE_LCK_ENCRYPTION_INFO: Int = 13;
pub const APPLE_LCK_DYLINKER: Int = 14;
pub const APPLE_LCK_RPATH: Int = 15;
pub const APPLE_LCK_SUB: Int = 16;
pub const APPLE_LCK_THREAD: Int = 17;
pub const APPLE_LCK_OTHER: Int = 18;

// Load-command field selectors (macho_command_field).
pub const APPLE_LC_FIELD_CMD: Int = 0;
pub const APPLE_LC_FIELD_SIZE: Int = 1;
pub const APPLE_LC_FIELD_OFFSET: Int = 2;
pub const APPLE_LC_FIELD_KIND: Int = 3;
pub const APPLE_LC_FIELD_VAL1: Int = 4;
pub const APPLE_LC_FIELD_VAL2: Int = 5;
pub const APPLE_LC_FIELD_VAL3: Int = 6;
pub const APPLE_LC_FIELD_VAL4: Int = 7;
pub const APPLE_LC_FIELD_NAME_OFFSET: Int = 8;
pub const APPLE_LC_FIELD_UUID_START: Int = 9;
pub const APPLE_LC_FIELD_UUID_LEN: Int = 10;
pub const APPLE_LC_FIELD_COUNT: Int = 11;

// Segment field selectors (macho_segment_field).
pub const APPLE_SEG_FIELD_CMD_INDEX: Int = 0;
pub const APPLE_SEG_FIELD_VMADDR: Int = 1;
pub const APPLE_SEG_FIELD_VMSIZE: Int = 2;
pub const APPLE_SEG_FIELD_FILEOFF: Int = 3;
pub const APPLE_SEG_FIELD_FILESIZE: Int = 4;
pub const APPLE_SEG_FIELD_MAXPROT: Int = 5;
pub const APPLE_SEG_FIELD_INITPROT: Int = 6;
pub const APPLE_SEG_FIELD_NSECTS: Int = 7;
pub const APPLE_SEG_FIELD_FLAGS: Int = 8;
pub const APPLE_SEG_FIELD_COUNT: Int = 9;

// Section field selectors (macho_section_field).
pub const APPLE_SEC_FIELD_SEG_INDEX: Int = 0;
pub const APPLE_SEC_FIELD_ADDR: Int = 1;
pub const APPLE_SEC_FIELD_SIZE: Int = 2;
pub const APPLE_SEC_FIELD_OFFSET: Int = 3;
pub const APPLE_SEC_FIELD_ALIGN: Int = 4;
pub const APPLE_SEC_FIELD_FLAGS: Int = 5;
pub const APPLE_SEC_FIELD_COUNT: Int = 6;

// Fat arch field selectors (fat_arch_field).
pub const APPLE_FAT_FIELD_CPUTYPE: Int = 0;
pub const APPLE_FAT_FIELD_CPUSUBTYPE: Int = 1;
pub const APPLE_FAT_FIELD_OFFSET: Int = 2;
pub const APPLE_FAT_FIELD_SIZE: Int = 3;
pub const APPLE_FAT_FIELD_ALIGN: Int = 4;
pub const APPLE_FAT_FIELD_COUNT: Int = 5;

// Platform values (LC_BUILD_VERSION).
pub const APPLE_PLATFORM_MACOS: Int = 1;
pub const APPLE_PLATFORM_IOS: Int = 2;
pub const APPLE_PLATFORM_TVOS: Int = 3;
pub const APPLE_PLATFORM_WATCHOS: Int = 4;
pub const APPLE_PLATFORM_BRIDGEOS: Int = 5;
pub const APPLE_PLATFORM_MACCATALYST: Int = 6;
pub const APPLE_PLATFORM_IOS_SIMULATOR: Int = 7;
pub const APPLE_PLATFORM_TVOS_SIMULATOR: Int = 8;
pub const APPLE_PLATFORM_WATCHOS_SIMULATOR: Int = 9;
pub const APPLE_PLATFORM_DRIVERKIT: Int = 10;
pub const APPLE_PLATFORM_VISIONOS: Int = 11;
pub const APPLE_PLATFORM_VISIONOS_SIMULATOR: Int = 12;

// --------------------------------------------------
//  Parsed thin Mach-O header and tables
// --------------------------------------------------

/// Parsed Mach-O header plus flat load-command/segment/section tables.
///
/// Scalar fields mirror the mach_header / mach_header_64; `magic` is the
/// on-disk magic read as a big-endian u32 (one of APPLE_MH_MAGIC,
/// APPLE_MH_MAGIC_64, APPLE_MH_CIGAM, APPLE_MH_CIGAM_64), `bits` is 32 or
/// 64 and `endianness` APPLE_ENDIAN_LE / APPLE_ENDIAN_BE. For load command
/// i the `lc_*` vectors hold cmd, cmdsize, file offset, decoded kind and
/// up to four decoded values in file order; `lc_names[i]` is the decoded
/// dylib/lc_str name ("" when the command has none), and `lc_uuid_starts[i]`
/// / `lc_uuid_lens[i]` locate the command's 16 raw UUID bytes inside the
/// flat `uuid_bytes` vector (-1 / 0 when absent). For segment j the `seg_*`
/// vectors hold the command index, name, vmaddr, vmsize, fileoff, filesize,
/// maxprot, initprot, flags and nsects. For section k the `sec_*` vectors
/// hold the owning segment index, sectname, segname, addr, size, offset,
/// align and flags. All parallel vectors hold one slot per entry and never
/// drift. Bytes stay in the parse buffer; fields are implementation details
/// and callers use the accessor functions below.
pub type MachOFile = {
  magic: Int;
  bits: Int;
  endianness: Int;
  cputype: Int;
  cpusubtype: Int;
  filetype: Int;
  ncmds: Int;
  sizeofcmds: Int;
  flags: Int;
  reserved: Int;
  header_size: Int;
  lc_cmds: Vec[Int];
  lc_sizes: Vec[Int];
  lc_offsets: Vec[Int];
  lc_kinds: Vec[Int];
  lc_val1: Vec[Int];
  lc_val2: Vec[Int];
  lc_val3: Vec[Int];
  lc_val4: Vec[Int];
  lc_name_offsets: Vec[Int];
  lc_names: Vec[Str];
  lc_uuid_starts: Vec[Int];
  lc_uuid_lens: Vec[Int];
  uuid_bytes: Vec[UInt8];
  seg_cmd_indices: Vec[Int];
  seg_names: Vec[Str];
  seg_vmaddrs: Vec[Int];
  seg_vmsizes: Vec[Int];
  seg_fileoffs: Vec[Int];
  seg_filesizes: Vec[Int];
  seg_maxprots: Vec[Int];
  seg_initprots: Vec[Int];
  seg_flags: Vec[Int];
  seg_nsects: Vec[Int];
  sec_seg_indices: Vec[Int];
  sec_names: Vec[Str];
  sec_segnames: Vec[Str];
  sec_addrs: Vec[Int];
  sec_sizes: Vec[Int];
  sec_offsets: Vec[Int];
  sec_aligns: Vec[Int];
  sec_flags: Vec[Int];
}

// --------------------------------------------------
//  Parsed fat/universal header
// --------------------------------------------------

/// Parsed fat_header plus its flat fat_arch table.
///
/// `magic` is the on-disk magic (APPLE_FAT_MAGIC for the big-endian form,
/// APPLE_FAT_CIGAM for the little-endian form), `endianness` the byte order
/// of the record fields, and the parallel vectors hold one slot per
/// architecture in file order. Slice payloads are not parsed or copied by
/// fat_parse; use fat_slice_bytes / fat_slice_macho.
pub type FatFile = {
  magic: Int;
  endianness: Int;
  nfat_arch: Int;
  cputypes: Vec[Int];
  cpusubtypes: Vec[Int];
  offsets: Vec[Int];
  sizes: Vec[Int];
  aligns: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (leaf helpers only, see the module header)
// --------------------------------------------------

// Ok(v) for Result[MachOFile, Str].
fn _ok_macho(v: MachOFile) -> Result[MachOFile, Str] {
  return Ok(v);
}

// Err(m) for Result[MachOFile, Str].
fn _err_macho(m: Str) -> Result[MachOFile, Str] {
  return Err(m);
}

// Ok(v) for Result[FatFile, Str].
fn _ok_fat(v: FatFile) -> Result[FatFile, Str] {
  return Ok(v);
}

// Err(m) for Result[FatFile, Str].
fn _err_fat(m: Str) -> Result[FatFile, Str] {
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
//  Internal byte, name and arithmetic helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Raw `size` (1..8) byte field at `off`: little-endian when `be` is false,
// big-endian when true. For size 8 the raw two's-complement bit pattern is
// returned (bit 63 set decodes as a negative Int): the low seven bytes
// accumulate with a `place` factor and the top byte is applied separately,
// so no intermediate overflows. Callers guarantee off + size <= data.len().
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

// `<base> at <off>` -- every error message carries its byte offset.
fn _err_at(base: Str, off: Int) -> Str {
  return base + " at " + itos.itos(off);
}

// 2 to the k (0 <= k <= 62; callers bound k).
fn _pow2(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// True when single-bit `mask` is set in non-negative `v`.
fn _bit_set(v: Int, mask: Int) -> Bool {
  let q = (v / mask) % 2;
  return q == 1;
}

// One lowercase hex digit for 0..15 ("?" outside; callers pass byte
// nibbles).
fn _hex_char(n: Int) -> Str {
  if n == 0 { return "0"; }
  if n == 1 { return "1"; }
  if n == 2 { return "2"; }
  if n == 3 { return "3"; }
  if n == 4 { return "4"; }
  if n == 5 { return "5"; }
  if n == 6 { return "6"; }
  if n == 7 { return "7"; }
  if n == 8 { return "8"; }
  if n == 9 { return "9"; }
  if n == 10 { return "a"; }
  if n == 11 { return "b"; }
  if n == 12 { return "c"; }
  if n == 13 { return "d"; }
  if n == 14 { return "e"; }
  if n == 15 { return "f"; }
  return "?";
}

// Two hex digits for a byte value 0..255.
fn _hex_byte(b: Int) -> Str {
  let hi = b / 16;
  let lo = b % 16;
  return _hex_char(hi) + _hex_char(lo);
}

// A fixed-width (16-byte) segname/sectname field at `off`: the bytes before
// the first NUL, or all `width` bytes when there is no NUL. Every byte
// before the end must be printable ASCII (0x20..0x7E). Bytes after the NUL
// are unchecked padding.
fn _scan_name(data: &Vec[UInt8], off: Int, width: Int) -> Result[Str, Str] {
  var end = off + width;
  var i = off;
  var found = false;
  while i < end {
    if _byte(data, i) == 0 {
      found = true;
      break;
    }
    i = i + 1;
  }
  if found { end = i; }
  var bytes = Vec[UInt8].new();
  var k = off;
  while k < end {
    let b = _byte(data, k);
    if b < 32 || b > 126 {
      return _err_str(_err_at("apple: name not printable ASCII", k));
    }
    bytes.push(b as UInt8);
    k = k + 1;
  }
  return _ok_str(Str::from_utf8(bytes));
}

// A NUL-terminated name inside [off, limit): the NUL must exist inside the
// command, and every byte before it must be printable ASCII (0x20..0x7E).
fn _scan_cstr(data: &Vec[UInt8], off: Int, limit: Int) -> Result[Str, Str] {
  var i = off;
  var found = false;
  while i < limit {
    if _byte(data, i) == 0 {
      found = true;
      break;
    }
    i = i + 1;
  }
  if !found {
    return _err_str(_err_at("apple: name not NUL-terminated", off));
  }
  var bytes = Vec[UInt8].new();
  var k = off;
  while k < i {
    let b = _byte(data, k);
    if b < 32 || b > 126 {
      return _err_str(_err_at("apple: name not printable ASCII", k));
    }
    bytes.push(b as UInt8);
    k = k + 1;
  }
  return _ok_str(Str::from_utf8(bytes));
}

// The on-disk magic of the first four bytes, read as a big-endian u32, so
// the raw byte order of the file is visible in the returned value.
fn _magic_be(data: &Vec[UInt8]) -> Int {
  return _rdu(data, 0, 4, true);
}

// Format code of `data` (APPLE_FORMAT_*); APPLE_FORMAT_UNKNOWN when the
// buffer is shorter than four bytes or the magic is not a Mach-O/fat magic.
fn _detect(data: &Vec[UInt8]) -> Int {
  if data.len() < 4 {
    return APPLE_FORMAT_UNKNOWN;
  }
  let m = _magic_be(data);
  if m == APPLE_MH_MAGIC { return APPLE_FORMAT_MACHO32_BE; }
  if m == APPLE_MH_MAGIC_64 { return APPLE_FORMAT_MACHO64_BE; }
  if m == APPLE_MH_CIGAM { return APPLE_FORMAT_MACHO32_LE; }
  if m == APPLE_MH_CIGAM_64 { return APPLE_FORMAT_MACHO64_LE; }
  if m == APPLE_FAT_MAGIC { return APPLE_FORMAT_FAT_BE; }
  if m == APPLE_FAT_CIGAM { return APPLE_FORMAT_FAT_LE; }
  if m == APPLE_FAT_MAGIC_64 { return APPLE_FORMAT_FAT64_BE; }
  if m == APPLE_FAT_CIGAM_64 { return APPLE_FORMAT_FAT64_LE; }
  return APPLE_FORMAT_UNKNOWN;
}

// --------------------------------------------------
//  Byte appenders (one push per parallel vector per entry)
// --------------------------------------------------

// Append one load-command record to the twelve parallel lc_* vectors.
fn _append_command(f: &mut MachOFile, cmd: Int, size: Int, off: Int, kind: Int, v1: Int, v2: Int, v3: Int, v4: Int, name_off: Int, name: Str, uuid_start: Int, uuid_len: Int) {
  f.lc_cmds.push(cmd);
  f.lc_sizes.push(size);
  f.lc_offsets.push(off);
  f.lc_kinds.push(kind);
  f.lc_val1.push(v1);
  f.lc_val2.push(v2);
  f.lc_val3.push(v3);
  f.lc_val4.push(v4);
  f.lc_name_offsets.push(name_off);
  f.lc_names.push(name);
  f.lc_uuid_starts.push(uuid_start);
  f.lc_uuid_lens.push(uuid_len);
}

// Append one segment record to the ten parallel seg_* vectors.
fn _append_segment(f: &mut MachOFile, cmd_index: Int, name: Str, vmaddr: Int, vmsize: Int, fileoff: Int, filesize: Int, maxprot: Int, initprot: Int, flags: Int, nsects: Int) {
  f.seg_cmd_indices.push(cmd_index);
  f.seg_names.push(name);
  f.seg_vmaddrs.push(vmaddr);
  f.seg_vmsizes.push(vmsize);
  f.seg_fileoffs.push(fileoff);
  f.seg_filesizes.push(filesize);
  f.seg_maxprots.push(maxprot);
  f.seg_initprots.push(initprot);
  f.seg_flags.push(flags);
  f.seg_nsects.push(nsects);
}

// Append one section record to the eight parallel sec_* vectors.
fn _append_section(f: &mut MachOFile, seg_index: Int, name: Str, segname: Str, addr: Int, size: Int, offset: Int, align: Int, flags: Int) {
  f.sec_seg_indices.push(seg_index);
  f.sec_names.push(name);
  f.sec_segnames.push(segname);
  f.sec_addrs.push(addr);
  f.sec_sizes.push(size);
  f.sec_offsets.push(offset);
  f.sec_aligns.push(align);
  f.sec_flags.push(flags);
}

// Append one fat_arch record to the five parallel vectors.
fn _append_fat_arch(f: &mut FatFile, cputype: Int, cpusubtype: Int, offset: Int, size: Int, align: Int) {
  f.cputypes.push(cputype);
  f.cpusubtypes.push(cpusubtype);
  f.offsets.push(offset);
  f.sizes.push(size);
  f.aligns.push(align);
}

// --------------------------------------------------
//  Thin Mach-O: header
// --------------------------------------------------

// The magic, class and byte order of a thin Mach-O, then the fixed header
// fields and the sizeofcmds bound against the buffer. Fat and fat64 magics
// are rejected here with a dedicated message; unknown magics are rejected
// as bad magic. The load-command region [header_size, header_size +
// sizeofcmds) is fully inside the buffer on success.
fn _read_header(data: &Vec[UInt8], f: &mut MachOFile) -> Result[Unit, Str] {
  let total = data.len();
  if total < 4 {
    return _err_unit(_err_at("apple: truncated magic", 0));
  }
  let fmt = _detect(data);
  if fmt == APPLE_FORMAT_UNKNOWN {
    return _err_unit(_err_at("apple: bad magic", 0));
  }
  if fmt == APPLE_FORMAT_FAT_BE || fmt == APPLE_FORMAT_FAT_LE || fmt == APPLE_FORMAT_FAT64_BE || fmt == APPLE_FORMAT_FAT64_LE {
    return _err_unit(_err_at("apple: fat header where a thin Mach-O was expected", 0));
  }
  f.magic = _magic_be(data);
  if fmt == APPLE_FORMAT_MACHO32_BE || fmt == APPLE_FORMAT_MACHO32_LE {
    f.bits = 32;
  } else {
    f.bits = 64;
  }
  if fmt == APPLE_FORMAT_MACHO32_LE || fmt == APPLE_FORMAT_MACHO64_LE {
    f.endianness = APPLE_ENDIAN_LE;
  } else {
    f.endianness = APPLE_ENDIAN_BE;
  }
  var hs = 28;
  if f.bits == 64 { hs = 32; }
  f.header_size = hs;
  if total < hs {
    return _err_unit(_err_at("apple: truncated header", 0));
  }
  let be: Bool = f.endianness == APPLE_ENDIAN_BE;
  f.cputype = _rdu(data, 4, 4, be);
  f.cpusubtype = _rdu(data, 8, 4, be);
  f.filetype = _rdu(data, 12, 4, be);
  f.ncmds = _rdu(data, 16, 4, be);
  f.sizeofcmds = _rdu(data, 20, 4, be);
  f.flags = _rdu(data, 24, 4, be);
  if f.bits == 64 {
    f.reserved = _rdu(data, 28, 4, be);
  }
  if f.sizeofcmds > total - hs {
    return _err_unit(_err_at("apple: sizeofcmds out of bounds", 20));
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Thin Mach-O: load-command payload decoders
// --------------------------------------------------

// LC_SEGMENT (is64 false, 56-byte command) / LC_SEGMENT_64 (is64 true,
// 72-byte command) and its section records (68- or 80-byte records). The
// segment name and every section name must be printable ASCII before their
// NUL; nsects must fit the command; a segment with filesize > 0 must have
// its file bytes inside the buffer, and a section with size > 0 whose type
// is not S_ZEROFILL / S_GB_ZEROFILL / S_THREAD_LOCAL_ZEROFILL must have its
// file bytes inside the buffer. Section align must be in 0..31.
fn _decode_segment(data: &Vec[UInt8], f: &mut MachOFile, pos: Int, size: Int, is64: Bool, be: Bool, cmd_index: Int) -> Result[Unit, Str] {
  let total = data.len();
  var base = 56;
  var secsize = 68;
  var nsects_off = 48;
  var align_off_in_section = 44;
  if is64 {
    base = 72;
    secsize = 80;
    nsects_off = 64;
    align_off_in_section = 52;
  }
  if size < base {
    return _err_unit(_err_at("apple: bad segment command", pos));
  }
  var vmaddr = 0;
  var vmsize = 0;
  var fileoff = 0;
  var filesize = 0;
  var maxprot = 0;
  var initprot = 0;
  var flags = 0;
  if is64 {
    vmaddr = _rdu(data, pos + 24, 8, be);
    vmsize = _rdu(data, pos + 32, 8, be);
    fileoff = _rdu(data, pos + 40, 8, be);
    filesize = _rdu(data, pos + 48, 8, be);
    maxprot = _rdu(data, pos + 56, 4, be);
    initprot = _rdu(data, pos + 60, 4, be);
    flags = _rdu(data, pos + 68, 4, be);
  } else {
    vmaddr = _rdu(data, pos + 24, 4, be);
    vmsize = _rdu(data, pos + 28, 4, be);
    fileoff = _rdu(data, pos + 32, 4, be);
    filesize = _rdu(data, pos + 36, 4, be);
    maxprot = _rdu(data, pos + 40, 4, be);
    initprot = _rdu(data, pos + 44, 4, be);
    flags = _rdu(data, pos + 52, 4, be);
  }
  let nsects = _rdu(data, pos + nsects_off, 4, be);
  let need = nsects * secsize;
  if need > size - base {
    return _err_unit(_err_at("apple: segment sections exceed cmdsize", pos + nsects_off));
  }
  if fileoff < 0 || filesize < 0 {
    return _err_unit(_err_at("apple: segment data out of bounds", pos));
  }
  if filesize > 0 {
    if fileoff > total || filesize > total - fileoff {
      return _err_unit(_err_at("apple: segment data out of bounds", pos));
    }
  }
  let rn = _scan_name(data, pos + 8, 16);
  if !rn.is_ok {
    return _err_unit(rn.error);
  }
  let segname: Str = rn.value;
  _append_segment(f, cmd_index, segname, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, flags, nsects);
  let seg_index = f.seg_cmd_indices.len() - 1;
  var s = 0;
  while s < nsects {
    let sp = pos + base + s * secsize;
    let r1 = _scan_name(data, sp, 16);
    if !r1.is_ok {
      return _err_unit(r1.error);
    }
    let r2 = _scan_name(data, sp + 16, 16);
    if !r2.is_ok {
      return _err_unit(r2.error);
    }
    let sectname: Str = r1.value;
    let ssegname: Str = r2.value;
    var saddr = 0;
    var ssize = 0;
    var soff = 0;
    var salign = 0;
    var sflags = 0;
    if is64 {
      saddr = _rdu(data, sp + 32, 8, be);
      ssize = _rdu(data, sp + 40, 8, be);
      soff = _rdu(data, sp + 48, 4, be);
      salign = _rdu(data, sp + 52, 4, be);
      sflags = _rdu(data, sp + 64, 4, be);
    } else {
      saddr = _rdu(data, sp + 32, 4, be);
      ssize = _rdu(data, sp + 36, 4, be);
      soff = _rdu(data, sp + 40, 4, be);
      salign = _rdu(data, sp + 44, 4, be);
      sflags = _rdu(data, sp + 56, 4, be);
    }
    if salign < 0 || salign > 31 {
      return _err_unit(_err_at("apple: bad section alignment", sp + align_off_in_section));
    }
    var zerofill = false;
    let stype = sflags % 256;
    if stype == 1 || stype == 12 || stype == 18 {
      zerofill = true;
    }
    if ssize < 0 || soff < 0 {
      return _err_unit(_err_at("apple: section data out of bounds", sp));
    }
    if ssize > 0 && !zerofill {
      if soff > total || ssize > total - soff {
        return _err_unit(_err_at("apple: section data out of bounds", sp));
      }
    }
    _append_section(f, seg_index, sectname, ssegname, saddr, ssize, soff, salign, sflags);
    s = s + 1;
  }
  var cmd_value = APPLE_LC_SEGMENT;
  var kind = APPLE_LCK_SEGMENT;
  if is64 {
    cmd_value = APPLE_LC_SEGMENT_64;
    kind = APPLE_LCK_SEGMENT_64;
  }
  _append_command(f, cmd_value, size, pos, kind, vmaddr, vmsize, fileoff, filesize, -1, "", -1, 0);
  return _ok_unit();
}

// Dylib-family command (LC_LOAD_DYLIB, LC_ID_DYLIB, LC_LOAD_WEAK_DYLIB,
// LC_REEXPORT_DYLIB, LC_LOAD_UPWARD_DYLIB, LC_LAZY_LOAD_DYLIB): the
// dylib_command is 24 bytes, the name offset must be >= 24 and < cmdsize,
// and the name must be NUL-terminated and printable inside the command.
// val1..val4 = name offset, timestamp, current version, compatibility
// version.
fn _decode_dylib(data: &Vec[UInt8], f: &mut MachOFile, pos: Int, size: Int, cmd: Int, be: Bool) -> Result[Unit, Str] {
  if size < 24 {
    return _err_unit(_err_at("apple: bad dylib command", pos));
  }
  let name_off = _rdu(data, pos + 8, 4, be);
  if name_off < 24 || name_off >= size {
    return _err_unit(_err_at("apple: bad name offset", pos + 8));
  }
  let rs = _scan_cstr(data, pos + name_off, pos + size);
  if !rs.is_ok {
    return _err_unit(rs.error);
  }
  let name: Str = rs.value;
  let timestamp = _rdu(data, pos + 12, 4, be);
  let current = _rdu(data, pos + 16, 4, be);
  let compat = _rdu(data, pos + 20, 4, be);
  _append_command(f, cmd, size, pos, APPLE_LCK_DYLIB, name_off, timestamp, current, compat, name_off, name, -1, 0);
  return _ok_unit();
}

// Plain lc_str command (LC_LOAD_DYLINKER, LC_ID_DYLINKER,
// LC_DYLD_ENVIRONMENT, LC_RPATH, LC_SUB_*): 12-byte payload header, name
// offset >= 12 and < cmdsize, NUL-terminated and printable inside the
// command. val1 = name offset.
fn _decode_lcstr(data: &Vec[UInt8], f: &mut MachOFile, pos: Int, size: Int, cmd: Int, kind: Int, be: Bool) -> Result[Unit, Str] {
  if size < 12 {
    return _err_unit(_err_at("apple: bad lc_str command", pos));
  }
  let name_off = _rdu(data, pos + 8, 4, be);
  if name_off < 12 || name_off >= size {
    return _err_unit(_err_at("apple: bad name offset", pos + 8));
  }
  let rs = _scan_cstr(data, pos + name_off, pos + size);
  if !rs.is_ok {
    return _err_unit(rs.error);
  }
  let name: Str = rs.value;
  _append_command(f, cmd, size, pos, kind, name_off, 0, 0, 0, name_off, name, -1, 0);
  return _ok_unit();
}

// LC_UUID: exactly 24 bytes; the 16 UUID bytes are appended raw to the flat
// uuid_bytes vector and located by lc_uuid_starts/lc_uuid_lens.
fn _decode_uuid(data: &Vec[UInt8], f: &mut MachOFile, cmd: Int, pos: Int, size: Int) -> Result[Unit, Str] {
  if size != 24 {
    return _err_unit(_err_at("apple: bad LC_UUID size", pos));
  }
  let start = f.uuid_bytes.len();
  var k = 0;
  while k < 16 {
    f.uuid_bytes.push(data[pos + 8 + k]);
    k = k + 1;
  }
  _append_command(f, cmd, size, pos, APPLE_LCK_UUID, 0, 0, 0, 0, -1, "", start, 16);
  return _ok_unit();
}

// LC_MAIN: exactly 24 bytes; val1 = entryoff, val2 = stacksize (both raw
// 64-bit two's complement: bit 63 set decodes as a negative Int).
fn _decode_main(data: &Vec[UInt8], f: &mut MachOFile, cmd: Int, pos: Int, size: Int, be: Bool) -> Result[Unit, Str] {
  if size != 24 {
    return _err_unit(_err_at("apple: bad LC_MAIN size", pos));
  }
  let entryoff = _rdu(data, pos + 8, 8, be);
  let stacksize = _rdu(data, pos + 16, 8, be);
  _append_command(f, cmd, size, pos, APPLE_LCK_MAIN, entryoff, stacksize, 0, 0, -1, "", -1, 0);
  return _ok_unit();
}

// linkedit_data_command family (LC_CODE_SIGNATURE, LC_FUNCTION_STARTS,
// LC_DATA_IN_CODE, LC_DYLIB_CODE_SIGN_DRS, LC_SEGMENT_SPLIT_INFO,
// LC_DYLD_EXPORTS_TRIE, LC_DYLD_CHAINED_FIXUPS,
// LC_LINKER_OPTIMIZATION_HINT): exactly 16 bytes, dataoff/datasize, and a
// non-empty blob must lie inside the buffer.
fn _decode_linkedit_data(data: &Vec[UInt8], f: &mut MachOFile, cmd: Int, pos: Int, size: Int, be: Bool) -> Result[Unit, Str] {
  if size != 16 {
    return _err_unit(_err_at("apple: bad linkedit command size", pos));
  }
  let total = data.len();
  let dataoff = _rdu(data, pos + 8, 4, be);
  let datasize = _rdu(data, pos + 12, 4, be);
  if dataoff < 0 || datasize < 0 {
    return _err_unit(_err_at("apple: linkedit data out of bounds", pos + 8));
  }
  if datasize > 0 {
    if dataoff > total || datasize > total - dataoff {
      return _err_unit(_err_at("apple: linkedit data out of bounds", pos + 8));
    }
  }
  _append_command(f, cmd, size, pos, APPLE_LCK_LINKEDIT_DATA, dataoff, datasize, 0, 0, -1, "", -1, 0);
  return _ok_unit();
}

// LC_BUILD_VERSION: 24-byte payload header plus ntools 8-byte tool records,
// all inside cmdsize. val1 = platform, val2 = minos, val3 = sdk,
// val4 = ntools.
fn _decode_build_version(data: &Vec[UInt8], f: &mut MachOFile, cmd: Int, pos: Int, size: Int, be: Bool) -> Result[Unit, Str] {
  if size < 24 {
    return _err_unit(_err_at("apple: bad LC_BUILD_VERSION size", pos));
  }
  let platform = _rdu(data, pos + 8, 4, be);
  let minos = _rdu(data, pos + 12, 4, be);
  let sdk = _rdu(data, pos + 16, 4, be);
  let ntools = _rdu(data, pos + 20, 4, be);
  if ntools * 8 > size - 24 {
    return _err_unit(_err_at("apple: build version tools exceed cmdsize", pos + 20));
  }
  _append_command(f, cmd, size, pos, APPLE_LCK_BUILD_VERSION, platform, minos, sdk, ntools, -1, "", -1, 0);
  return _ok_unit();
}

// LC_VERSION_MIN_MACOSX / _IPHONEOS / _TVOS / _WATCHOS: exactly 16 bytes;
// val1 = version, val2 = sdk (both packed x.y.z).
fn _decode_version_min(data: &Vec[UInt8], f: &mut MachOFile, cmd: Int, pos: Int, size: Int, be: Bool) -> Result[Unit, Str] {
  if size != 16 {
    return _err_unit(_err_at("apple: bad LC_VERSION_MIN size", pos));
  }
  let version = _rdu(data, pos + 8, 4, be);
  let sdk = _rdu(data, pos + 12, 4, be);
  _append_command(f, cmd, size, pos, APPLE_LCK_VERSION_MIN, version, sdk, 0, 0, -1, "", -1, 0);
  return _ok_unit();
}

// LC_SYMTAB: exactly 24 bytes. Only the four table locations are recorded
// (symoff, nsyms, stroff, strsize); nlist entries are never decoded.
fn _decode_symtab(data: &Vec[UInt8], f: &mut MachOFile, cmd: Int, pos: Int, size: Int, be: Bool) -> Result[Unit, Str] {
  if size != 24 {
    return _err_unit(_err_at("apple: bad LC_SYMTAB size", pos));
  }
  let symoff = _rdu(data, pos + 8, 4, be);
  let nsyms = _rdu(data, pos + 12, 4, be);
  let stroff = _rdu(data, pos + 16, 4, be);
  let strsize = _rdu(data, pos + 20, 4, be);
  _append_command(f, cmd, size, pos, APPLE_LCK_SYMTAB, symoff, nsyms, stroff, strsize, -1, "", -1, 0);
  return _ok_unit();
}

// LC_SOURCE_VERSION: exactly 16 bytes; val1 = the raw 64-bit version
// (bit 63 set decodes as a negative Int).
fn _decode_source_version(data: &Vec[UInt8], f: &mut MachOFile, cmd: Int, pos: Int, size: Int, be: Bool) -> Result[Unit, Str] {
  if size != 16 {
    return _err_unit(_err_at("apple: bad LC_SOURCE_VERSION size", pos));
  }
  let v = _rdu(data, pos + 8, 8, be);
  _append_command(f, cmd, size, pos, APPLE_LCK_SOURCE_VERSION, v, 0, 0, 0, -1, "", -1, 0);
  return _ok_unit();
}

// LC_ENCRYPTION_INFO (20 bytes) / LC_ENCRYPTION_INFO_64 (24 bytes);
// val1 = cryptoff, val2 = cryptsize, val3 = cryptid.
fn _decode_encryption(data: &Vec[UInt8], f: &mut MachOFile, cmd: Int, pos: Int, size: Int, be: Bool, is64: Bool) -> Result[Unit, Str] {
  var want = 20;
  if is64 { want = 24; }
  if size != want {
    return _err_unit(_err_at("apple: bad LC_ENCRYPTION_INFO size", pos));
  }
  let cryptoff = _rdu(data, pos + 8, 4, be);
  let cryptsize = _rdu(data, pos + 12, 4, be);
  let cryptid = _rdu(data, pos + 16, 4, be);
  _append_command(f, cmd, size, pos, APPLE_LCK_ENCRYPTION_INFO, cryptoff, cryptsize, cryptid, 0, -1, "", -1, 0);
  return _ok_unit();
}

// Map a raw cmd value to its decoded kind.
fn _classify(cmd: Int) -> Int {
  if cmd == APPLE_LC_SEGMENT { return APPLE_LCK_SEGMENT; }
  if cmd == APPLE_LC_SEGMENT_64 { return APPLE_LCK_SEGMENT_64; }
  if cmd == APPLE_LC_LOAD_DYLIB { return APPLE_LCK_DYLIB; }
  if cmd == APPLE_LC_ID_DYLIB { return APPLE_LCK_DYLIB; }
  if cmd == APPLE_LC_LOAD_WEAK_DYLIB { return APPLE_LCK_DYLIB; }
  if cmd == APPLE_LC_REEXPORT_DYLIB { return APPLE_LCK_DYLIB; }
  if cmd == APPLE_LC_LOAD_UPWARD_DYLIB { return APPLE_LCK_DYLIB; }
  if cmd == APPLE_LC_LAZY_LOAD_DYLIB { return APPLE_LCK_DYLIB; }
  if cmd == APPLE_LC_UUID { return APPLE_LCK_UUID; }
  if cmd == APPLE_LC_MAIN { return APPLE_LCK_MAIN; }
  if cmd == APPLE_LC_CODE_SIGNATURE { return APPLE_LCK_LINKEDIT_DATA; }
  if cmd == APPLE_LC_FUNCTION_STARTS { return APPLE_LCK_LINKEDIT_DATA; }
  if cmd == APPLE_LC_DATA_IN_CODE { return APPLE_LCK_LINKEDIT_DATA; }
  if cmd == APPLE_LC_DYLIB_CODE_SIGN_DRS { return APPLE_LCK_LINKEDIT_DATA; }
  if cmd == APPLE_LC_SEGMENT_SPLIT_INFO { return APPLE_LCK_LINKEDIT_DATA; }
  if cmd == APPLE_LC_DYLD_EXPORTS_TRIE { return APPLE_LCK_LINKEDIT_DATA; }
  if cmd == APPLE_LC_DYLD_CHAINED_FIXUPS { return APPLE_LCK_LINKEDIT_DATA; }
  if cmd == APPLE_LC_LINKER_OPTIMIZATION_HINT { return APPLE_LCK_LINKEDIT_DATA; }
  if cmd == APPLE_LC_BUILD_VERSION { return APPLE_LCK_BUILD_VERSION; }
  if cmd == APPLE_LC_VERSION_MIN_MACOSX { return APPLE_LCK_VERSION_MIN; }
  if cmd == APPLE_LC_VERSION_MIN_IPHONEOS { return APPLE_LCK_VERSION_MIN; }
  if cmd == APPLE_LC_VERSION_MIN_TVOS { return APPLE_LCK_VERSION_MIN; }
  if cmd == APPLE_LC_VERSION_MIN_WATCHOS { return APPLE_LCK_VERSION_MIN; }
  if cmd == APPLE_LC_SYMTAB { return APPLE_LCK_SYMTAB; }
  if cmd == APPLE_LC_DYSYMTAB { return APPLE_LCK_DYSYMTAB; }
  if cmd == APPLE_LC_DYLD_INFO { return APPLE_LCK_DYLD_INFO; }
  if cmd == APPLE_LC_DYLD_INFO_ONLY { return APPLE_LCK_DYLD_INFO; }
  if cmd == APPLE_LC_SOURCE_VERSION { return APPLE_LCK_SOURCE_VERSION; }
  if cmd == APPLE_LC_ENCRYPTION_INFO { return APPLE_LCK_ENCRYPTION_INFO; }
  if cmd == APPLE_LC_ENCRYPTION_INFO_64 { return APPLE_LCK_ENCRYPTION_INFO; }
  if cmd == APPLE_LC_LOAD_DYLINKER { return APPLE_LCK_DYLINKER; }
  if cmd == APPLE_LC_ID_DYLINKER { return APPLE_LCK_DYLINKER; }
  if cmd == APPLE_LC_DYLD_ENVIRONMENT { return APPLE_LCK_DYLINKER; }
  if cmd == APPLE_LC_RPATH { return APPLE_LCK_RPATH; }
  if cmd == APPLE_LC_SUB_FRAMEWORK { return APPLE_LCK_SUB; }
  if cmd == APPLE_LC_SUB_UMBRELLA { return APPLE_LCK_SUB; }
  if cmd == APPLE_LC_SUB_CLIENT { return APPLE_LCK_SUB; }
  if cmd == APPLE_LC_SUB_LIBRARY { return APPLE_LCK_SUB; }
  if cmd == APPLE_LC_THREAD { return APPLE_LCK_THREAD; }
  if cmd == APPLE_LC_UNIXTHREAD { return APPLE_LCK_THREAD; }
  if cmd == APPLE_LC_SYMSEG { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_LOADFVMLIB { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_IDFVMLIB { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_IDENT { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_FVMFILE { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_PREPAGE { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_PREBOUND_DYLIB { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_ROUTINES { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_ROUTINES_64 { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_TWOLEVEL_HINTS { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_PREBIND_CKSUM { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_LINKER_OPTION { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_NOTE { return APPLE_LCK_OTHER; }
  if cmd == APPLE_LC_FILESET_ENTRY { return APPLE_LCK_OTHER; }
  return APPLE_LCK_UNKNOWN;
}

// Walk the ncmds load commands in [header_size, header_size + sizeofcmds).
// Each cmdsize must be >= 8, a multiple of 4 in a 32-bit image and of 8 in
// a 64-bit image, and must keep the command inside sizeofcmds; the walked
// sizes must fill sizeofcmds exactly. Decoded commands append one record
// per command/segment/section to the parallel vectors; recognized but
// undecoded and unknown commands are preserved with their raw cmd, cmdsize
// and offset.
fn _walk_commands(data: &Vec[UInt8], f: &mut MachOFile) -> Result[Unit, Str] {
  let be: Bool = f.endianness == APPLE_ENDIAN_BE;
  let start: Int = f.header_size;
  let limit: Int = start + f.sizeofcmds;
  var lc_align = 4;
  if f.bits == 64 { lc_align = 8; }
  var pos = start;
  var i = 0;
  let n: Int = f.ncmds;
  while i < n {
    if pos + 8 > limit {
      return _err_unit(_err_at("apple: truncated load command", pos));
    }
    let cmd = _rdu(data, pos, 4, be);
    let size = _rdu(data, pos + 4, 4, be);
    if size < 8 {
      return _err_unit(_err_at("apple: bad cmdsize", pos + 4));
    }
    if size % lc_align != 0 {
      return _err_unit(_err_at("apple: misaligned cmdsize", pos + 4));
    }
    if size > limit - pos {
      return _err_unit(_err_at("apple: command exceeds sizeofcmds", pos + 4));
    }
    let kind = _classify(cmd);
    if kind == APPLE_LCK_SEGMENT {
      let r = _decode_segment(data, f, pos, size, false, be, i);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_SEGMENT_64 {
      let r = _decode_segment(data, f, pos, size, true, be, i);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_DYLIB {
      let r = _decode_dylib(data, f, pos, size, cmd, be);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_UUID {
      let r = _decode_uuid(data, f, cmd, pos, size);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_MAIN {
      let r = _decode_main(data, f, cmd, pos, size, be);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_LINKEDIT_DATA {
      let r = _decode_linkedit_data(data, f, cmd, pos, size, be);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_BUILD_VERSION {
      let r = _decode_build_version(data, f, cmd, pos, size, be);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_VERSION_MIN {
      let r = _decode_version_min(data, f, cmd, pos, size, be);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_SYMTAB {
      let r = _decode_symtab(data, f, cmd, pos, size, be);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_SOURCE_VERSION {
      let r = _decode_source_version(data, f, cmd, pos, size, be);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_ENCRYPTION_INFO {
      var enc64 = false;
      if cmd == APPLE_LC_ENCRYPTION_INFO_64 { enc64 = true; }
      let r = _decode_encryption(data, f, cmd, pos, size, be, enc64);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_DYLINKER || kind == APPLE_LCK_RPATH || kind == APPLE_LCK_SUB {
      let r = _decode_lcstr(data, f, pos, size, cmd, kind, be);
      if !r.is_ok {
        return _err_unit(r.error);
      }
    }
    if kind == APPLE_LCK_DYSYMTAB || kind == APPLE_LCK_DYLD_INFO || kind == APPLE_LCK_THREAD || kind == APPLE_LCK_OTHER || kind == APPLE_LCK_UNKNOWN {
      _append_command(f, cmd, size, pos, kind, 0, 0, 0, 0, -1, "", -1, 0);
    }
    pos = pos + size;
    i = i + 1;
  }
  if pos != limit {
    return _err_unit(_err_at("apple: load commands do not fill sizeofcmds", pos));
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Public thin Mach-O API
// --------------------------------------------------

/// Format code of `data`: APPLE_FORMAT_MACHO32_BE, APPLE_FORMAT_MACHO32_LE,
/// APPLE_FORMAT_MACHO64_BE, APPLE_FORMAT_MACHO64_LE, APPLE_FORMAT_FAT_BE,
/// APPLE_FORMAT_FAT_LE, APPLE_FORMAT_FAT64_BE, APPLE_FORMAT_FAT64_LE or
/// APPLE_FORMAT_UNKNOWN (buffer shorter than four bytes or no known magic).
/// The thin codes read the on-disk magic: the _BE codes are the legacy
/// big-endian byte order (apps written little-endian by Apple's tools are
/// the _LE codes). Complexity: O(1).
pub fn apple_format(data: &Vec[UInt8]) -> Int {
  return _detect(data);
}

/// Number of bits encoded by a thin format code: 32 or 64 for the
/// APPLE_FORMAT_MACHO* codes, 0 for fat, fat64 and unknown codes.
/// Complexity: O(1).
pub fn apple_format_bits(fmt: Int) -> Int {
  if fmt == APPLE_FORMAT_MACHO32_BE || fmt == APPLE_FORMAT_MACHO32_LE { return 32; }
  if fmt == APPLE_FORMAT_MACHO64_BE || fmt == APPLE_FORMAT_MACHO64_LE { return 64; }
  return 0;
}

/// Byte order encoded by a format code: APPLE_ENDIAN_LE / APPLE_ENDIAN_BE
/// for every recognized code, 0 for APPLE_FORMAT_UNKNOWN. Complexity: O(1).
pub fn apple_format_endianness(fmt: Int) -> Int {
  if fmt == APPLE_FORMAT_MACHO32_LE || fmt == APPLE_FORMAT_MACHO64_LE { return APPLE_ENDIAN_LE; }
  if fmt == APPLE_FORMAT_MACHO32_BE || fmt == APPLE_FORMAT_MACHO64_BE { return APPLE_ENDIAN_BE; }
  if fmt == APPLE_FORMAT_FAT_LE { return APPLE_ENDIAN_LE; }
  if fmt == APPLE_FORMAT_FAT_BE { return APPLE_ENDIAN_BE; }
  if fmt == APPLE_FORMAT_FAT64_LE { return APPLE_ENDIAN_LE; }
  if fmt == APPLE_FORMAT_FAT64_BE { return APPLE_ENDIAN_BE; }
  return 0;
}

/// True for the two supported fat (32-bit arch record) format codes.
/// Complexity: O(1).
pub fn apple_is_fat_format(fmt: Int) -> Bool {
  if fmt == APPLE_FORMAT_FAT_BE || fmt == APPLE_FORMAT_FAT_LE { return true; }
  return false;
}

/// True for the four thin Mach-O format codes. Complexity: O(1).
pub fn apple_is_thin_format(fmt: Int) -> Bool {
  if fmt == APPLE_FORMAT_MACHO32_BE || fmt == APPLE_FORMAT_MACHO32_LE { return true; }
  if fmt == APPLE_FORMAT_MACHO64_BE || fmt == APPLE_FORMAT_MACHO64_LE { return true; }
  return false;
}

/// Short name of a format code: "macho32-be", "macho32-le", "macho64-be",
/// "macho64-le", "fat-be", "fat-le", "fat64-be", "fat64-le", "unknown".
/// Complexity: O(1).
pub fn apple_format_name(fmt: Int) -> Str {
  if fmt == APPLE_FORMAT_MACHO32_BE { return "macho32-be"; }
  if fmt == APPLE_FORMAT_MACHO32_LE { return "macho32-le"; }
  if fmt == APPLE_FORMAT_MACHO64_BE { return "macho64-be"; }
  if fmt == APPLE_FORMAT_MACHO64_LE { return "macho64-le"; }
  if fmt == APPLE_FORMAT_FAT_BE { return "fat-be"; }
  if fmt == APPLE_FORMAT_FAT_LE { return "fat-le"; }
  if fmt == APPLE_FORMAT_FAT64_BE { return "fat64-be"; }
  if fmt == APPLE_FORMAT_FAT64_LE { return "fat64-le"; }
  return "unknown";
}

/// Parse a thin Mach-O header and its load commands.
///
/// Validates, in order: the buffer length and magic, that the image is
/// thin (fat/fat64 magics are rejected), the fixed header size, the
/// sizeofcmds span, then every load command (cmdsize >= 8, alignment,
/// sizeofcmds boundary, exact fill) and each decoded payload (segments and
/// their sections, dylib/lc_str names, fixed-size commands). All errors are
/// `"apple: ..."` strings carrying the offending byte offset. On success
/// `bits`, `endianness`, every header scalar and the flat command/segment/
/// section tables are filled; bytes stay in `data`. Complexity:
/// O(data.len() + commands).
pub fn macho_parse(data: &Vec[UInt8]) -> Result[MachOFile, Str] {
  var f = MachOFile{
    magic: 0;
    bits: 0;
    endianness: 0;
    cputype: 0;
    cpusubtype: 0;
    filetype: 0;
    ncmds: 0;
    sizeofcmds: 0;
    flags: 0;
    reserved: 0;
    header_size: 0;
    lc_cmds: Vec[Int].new();
    lc_sizes: Vec[Int].new();
    lc_offsets: Vec[Int].new();
    lc_kinds: Vec[Int].new();
    lc_val1: Vec[Int].new();
    lc_val2: Vec[Int].new();
    lc_val3: Vec[Int].new();
    lc_val4: Vec[Int].new();
    lc_name_offsets: Vec[Int].new();
    lc_names: Vec[Str].new();
    lc_uuid_starts: Vec[Int].new();
    lc_uuid_lens: Vec[Int].new();
    uuid_bytes: Vec[UInt8].new();
    seg_cmd_indices: Vec[Int].new();
    seg_names: Vec[Str].new();
    seg_vmaddrs: Vec[Int].new();
    seg_vmsizes: Vec[Int].new();
    seg_fileoffs: Vec[Int].new();
    seg_filesizes: Vec[Int].new();
    seg_maxprots: Vec[Int].new();
    seg_initprots: Vec[Int].new();
    seg_flags: Vec[Int].new();
    seg_nsects: Vec[Int].new();
    sec_seg_indices: Vec[Int].new();
    sec_names: Vec[Str].new();
    sec_segnames: Vec[Str].new();
    sec_addrs: Vec[Int].new();
    sec_sizes: Vec[Int].new();
    sec_offsets: Vec[Int].new();
    sec_aligns: Vec[Int].new();
    sec_flags: Vec[Int].new();
  };
  let r1 = _read_header(data, &mut f);
  if !r1.is_ok {
    return _err_macho(r1.error);
  }
  let r2 = _walk_commands(data, &mut f);
  if !r2.is_ok {
    return _err_macho(r2.error);
  }
  return _ok_macho(f);
}

/// On-disk magic of the parsed image: APPLE_MH_MAGIC, APPLE_MH_MAGIC_64,
/// APPLE_MH_CIGAM or APPLE_MH_CIGAM_64. Complexity: O(1).
pub fn macho_magic(f: &MachOFile) -> Int {
  return f.magic;
}

/// 32 or 64. Complexity: O(1).
pub fn macho_bits(f: &MachOFile) -> Int {
  return f.bits;
}

/// APPLE_ENDIAN_LE or APPLE_ENDIAN_BE. Complexity: O(1).
pub fn macho_endianness(f: &MachOFile) -> Int {
  return f.endianness;
}

/// Raw cputype (pass-through). Complexity: O(1).
pub fn macho_cputype(f: &MachOFile) -> Int {
  return f.cputype;
}

/// Raw cpusubtype (pass-through). Complexity: O(1).
pub fn macho_cpusubtype(f: &MachOFile) -> Int {
  return f.cpusubtype;
}

/// Raw filetype (pass-through; compare against the APPLE_MH_* constants).
/// Complexity: O(1).
pub fn macho_filetype(f: &MachOFile) -> Int {
  return f.filetype;
}

/// Raw header flags (pass-through; use macho_has_flag). Complexity: O(1).
pub fn macho_flags(f: &MachOFile) -> Int {
  return f.flags;
}

/// ncmds as stored in the header. Complexity: O(1).
pub fn macho_ncmds(f: &MachOFile) -> Int {
  return f.ncmds;
}

/// sizeofcmds as stored in the header. Complexity: O(1).
pub fn macho_sizeofcmds(f: &MachOFile) -> Int {
  return f.sizeofcmds;
}

/// Reserved header field (0 for 32-bit images). Complexity: O(1).
pub fn macho_reserved(f: &MachOFile) -> Int {
  return f.reserved;
}

/// Fixed header size: 28 (32-bit) or 32 (64-bit). Complexity: O(1).
pub fn macho_header_size(f: &MachOFile) -> Int {
  return f.header_size;
}

/// Number of parsed load commands. Complexity: O(1).
pub fn macho_command_count(f: &MachOFile) -> Int {
  return f.lc_cmds.len();
}

/// Number of parsed segments. Complexity: O(1).
pub fn macho_segment_count(f: &MachOFile) -> Int {
  return f.seg_names.len();
}

/// Number of parsed sections. Complexity: O(1).
pub fn macho_section_count(f: &MachOFile) -> Int {
  return f.sec_names.len();
}

/// Classify a cputype: APPLE_CPU_CLASS_UNKNOWN, _X86, _X86_64, _ARM,
/// _ARM64, _ARM64_32, _PPC or _PPC64. Exact matches only (the ABI bits are
/// part of the cputype). Complexity: O(1).
pub fn macho_cpu_class(cputype: Int) -> Int {
  if cputype == APPLE_CPU_TYPE_X86 { return APPLE_CPU_CLASS_X86; }
  if cputype == APPLE_CPU_TYPE_X86_64 { return APPLE_CPU_CLASS_X86_64; }
  if cputype == APPLE_CPU_TYPE_ARM { return APPLE_CPU_CLASS_ARM; }
  if cputype == APPLE_CPU_TYPE_ARM64 { return APPLE_CPU_CLASS_ARM64; }
  if cputype == APPLE_CPU_TYPE_ARM64_32 { return APPLE_CPU_CLASS_ARM64_32; }
  if cputype == APPLE_CPU_TYPE_PPC { return APPLE_CPU_CLASS_PPC; }
  if cputype == APPLE_CPU_TYPE_PPC64 { return APPLE_CPU_CLASS_PPC64; }
  return APPLE_CPU_CLASS_UNKNOWN;
}

/// Name of a cputype: "x86", "x86_64", "arm", "arm64", "arm64_32", "ppc",
/// "ppc64" or "unknown". Complexity: O(1).
pub fn macho_cpu_name(cputype: Int) -> Str {
  if cputype == APPLE_CPU_TYPE_X86 { return "x86"; }
  if cputype == APPLE_CPU_TYPE_X86_64 { return "x86_64"; }
  if cputype == APPLE_CPU_TYPE_ARM { return "arm"; }
  if cputype == APPLE_CPU_TYPE_ARM64 { return "arm64"; }
  if cputype == APPLE_CPU_TYPE_ARM64_32 { return "arm64_32"; }
  if cputype == APPLE_CPU_TYPE_PPC { return "ppc"; }
  if cputype == APPLE_CPU_TYPE_PPC64 { return "ppc64"; }
  return "unknown";
}

/// Name of a filetype: "object", "executable", "dylib", "bundle", "dsym",
/// "core", "preload", "dylinker", "dylib-stub", "kext-bundle", "fileset",
/// "fvmlib" or "unknown". Complexity: O(1).
pub fn macho_file_type_name(filetype: Int) -> Str {
  if filetype == APPLE_MH_OBJECT { return "object"; }
  if filetype == APPLE_MH_EXECUTE { return "executable"; }
  if filetype == APPLE_MH_DYLIB { return "dylib"; }
  if filetype == APPLE_MH_BUNDLE { return "bundle"; }
  if filetype == APPLE_MH_DSYM { return "dsym"; }
  if filetype == APPLE_MH_CORE { return "core"; }
  if filetype == APPLE_MH_PRELOAD { return "preload"; }
  if filetype == APPLE_MH_DYLINKER { return "dylinker"; }
  if filetype == APPLE_MH_DYLIB_STUB { return "dylib-stub"; }
  if filetype == APPLE_MH_KEXT_BUNDLE { return "kext-bundle"; }
  if filetype == APPLE_MH_FILESET { return "fileset"; }
  if filetype == APPLE_MH_FVMLIB { return "fvmlib"; }
  return "unknown";
}

/// True when every bit of single-bit `flagmask` (the APPLE_MH_* constants)
/// is set in the parsed header flags. Complexity: O(1).
pub fn macho_has_flag(f: &MachOFile, flagmask: Int) -> Bool {
  let flags: Int = f.flags;
  return _bit_set(flags, flagmask);
}

/// Low three protection bits of a raw maxprot/initprot value (0..7):
/// VM_PROT_READ = 1, VM_PROT_WRITE = 2, VM_PROT_EXECUTE = 4. Works for the
/// full 32-bit raw range (bit 31 set included). Complexity: O(1).
pub fn macho_prot_bits(prot: Int) -> Int {
  var p = prot % 8;
  if p < 0 { p = p + 8; }
  return p;
}

/// Three-character protection text for a raw maxprot/initprot value: bit 0
/// is "r", bit 1 "w", bit 2 "x", absent bits are "-" (e.g. 5 -> "r-x").
/// Complexity: O(1).
pub fn macho_prot_text(prot: Int) -> Str {
  let bits = macho_prot_bits(prot);
  var out = "";
  var i = 0;
  var p = bits;
  while i < 3 {
    let b = p % 2;
    var ch = "-";
    if b == 1 {
      if i == 0 { ch = "r"; }
      if i == 1 { ch = "w"; }
      if i == 2 { ch = "x"; }
    }
    out = out + ch;
    p = (p - b) / 2;
    i = i + 1;
  }
  return out;
}

/// Packed x.y.z version text for a 32-bit LC_BUILD_VERSION / LC_VERSION_MIN
/// version or sdk field (major << 16 | minor << 8 | patch). Negative (bit 31
/// set) values return "?". Complexity: O(1).
pub fn macho_version_text(v: Int) -> Str {
  if v < 0 { return "?"; }
  let major = v / 65536;
  let minor = (v / 256) % 256;
  let patch = v % 256;
  return itos.itos(major) + "." + itos.itos(minor) + "." + itos.itos(patch);
}

/// Name of an LC_BUILD_VERSION platform value: "macos", "ios", "tvos",
/// "watchos", "bridgeos", "maccatalyst", "ios-simulator",
/// "tvos-simulator", "watchos-simulator", "driverkit", "visionos",
/// "visionos-simulator" or "unknown". Complexity: O(1).
pub fn macho_platform_name(platform: Int) -> Str {
  if platform == APPLE_PLATFORM_MACOS { return "macos"; }
  if platform == APPLE_PLATFORM_IOS { return "ios"; }
  if platform == APPLE_PLATFORM_TVOS { return "tvos"; }
  if platform == APPLE_PLATFORM_WATCHOS { return "watchos"; }
  if platform == APPLE_PLATFORM_BRIDGEOS { return "bridgeos"; }
  if platform == APPLE_PLATFORM_MACCATALYST { return "maccatalyst"; }
  if platform == APPLE_PLATFORM_IOS_SIMULATOR { return "ios-simulator"; }
  if platform == APPLE_PLATFORM_TVOS_SIMULATOR { return "tvos-simulator"; }
  if platform == APPLE_PLATFORM_WATCHOS_SIMULATOR { return "watchos-simulator"; }
  if platform == APPLE_PLATFORM_DRIVERKIT { return "driverkit"; }
  if platform == APPLE_PLATFORM_VISIONOS { return "visionos"; }
  if platform == APPLE_PLATFORM_VISIONOS_SIMULATOR { return "visionos-simulator"; }
  return "unknown";
}

/// Field `field` (an APPLE_LC_FIELD_* selector) of load command `i`.
///
/// Err("apple: index out of range") when i is negative or >=
/// macho_command_count(f); Err("apple: bad field selector") when field is
/// not a known selector. The raw parsed value is returned. The meaning of
/// val1..val4 depends on the kind: LCK_DYLIB (name offset, timestamp,
/// current, compatibility), LCK_UUID (all 0; see macho_uuid_*), LCK_MAIN
/// (entryoff, stacksize), LCK_LINKEDIT_DATA (dataoff, datasize),
/// LCK_BUILD_VERSION (platform, minos, sdk, ntools), LCK_VERSION_MIN
/// (version, sdk), LCK_SYMTAB (symoff, nsyms, stroff, strsize),
/// LCK_SOURCE_VERSION (version), LCK_ENCRYPTION_INFO (cryptoff, cryptsize,
/// cryptid), LCK_DYLINKER/RPATH/SUB (name offset), others 0.
/// Complexity: O(1).
pub fn macho_command_field(f: &MachOFile, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.lc_cmds.len() {
    return _err_int("apple: index out of range");
  }
  if field == APPLE_LC_FIELD_CMD {
    let v: Int = f.lc_cmds[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_SIZE {
    let v: Int = f.lc_sizes[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_OFFSET {
    let v: Int = f.lc_offsets[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_KIND {
    let v: Int = f.lc_kinds[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_VAL1 {
    let v: Int = f.lc_val1[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_VAL2 {
    let v: Int = f.lc_val2[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_VAL3 {
    let v: Int = f.lc_val3[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_VAL4 {
    let v: Int = f.lc_val4[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_NAME_OFFSET {
    let v: Int = f.lc_name_offsets[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_UUID_START {
    let v: Int = f.lc_uuid_starts[i];
    return _ok_int(v);
  }
  if field == APPLE_LC_FIELD_UUID_LEN {
    let v: Int = f.lc_uuid_lens[i];
    return _ok_int(v);
  }
  return _err_int("apple: bad field selector");
}

/// Decoded name of load command `i` (dylib family and lc_str commands;
/// "" for every other kind). Err("apple: index out of range") when i is
/// negative or >= macho_command_count(f). The returned Str is read from a
/// Vec[Str] field: compare it with xiom.string.compare.str_compare rather
/// than `==`. Complexity: O(1).
pub fn macho_command_name(f: &MachOFile, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.lc_names.len() {
    return _err_str("apple: index out of range");
  }
  let nm: Str = f.lc_names[i];
  return _ok_str(nm);
}

/// Raw UUID byte k (0..15) of load command `i` (LC_UUID only).
///
/// Err("apple: index out of range") for an invalid command index or for k
/// outside 0..15; Err("apple: no uuid on this command") when command i is
/// not an LC_UUID. Complexity: O(1).
pub fn macho_uuid_byte(f: &MachOFile, i: Int, k: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.lc_uuid_starts.len() {
    return _err_int("apple: index out of range");
  }
  if k < 0 || k > 15 {
    return _err_int("apple: index out of range");
  }
  let start: Int = f.lc_uuid_starts[i];
  let ln: Int = f.lc_uuid_lens[i];
  if start < 0 || ln != 16 {
    return _err_int("apple: no uuid on this command");
  }
  let b: Int = (f.uuid_bytes[start + k] as Int) & 0xFF;
  return _ok_int(b);
}

/// Canonical lowercase UUID text of load command `i` (LC_UUID only),
/// 8-4-4-4-12 with dashes. Err("apple: index out of range") for an invalid
/// command index; Err("apple: no uuid on this command") when command i is
/// not an LC_UUID. Complexity: O(1).
pub fn macho_uuid_text(f: &MachOFile, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.lc_uuid_starts.len() {
    return _err_str("apple: index out of range");
  }
  let start: Int = f.lc_uuid_starts[i];
  let ln: Int = f.lc_uuid_lens[i];
  if start < 0 || ln != 16 {
    return _err_str("apple: no uuid on this command");
  }
  var out = "";
  var k = 0;
  while k < 16 {
    if k == 4 || k == 6 || k == 8 || k == 10 {
      out = out + "-";
    }
    let b: Int = (f.uuid_bytes[start + k] as Int) & 0xFF;
    out = out + _hex_byte(b);
    k = k + 1;
  }
  return _ok_str(out);
}

/// Field `field` (an APPLE_SEG_FIELD_* selector) of segment `j`.
///
/// Err("apple: index out of range") when j is negative or >=
/// macho_segment_count(f); Err("apple: bad field selector") otherwise on a
/// non-selector field. The raw parsed value is returned. Complexity: O(1).
pub fn macho_segment_field(f: &MachOFile, j: Int, field: Int) -> Result[Int, Str] {
  if j < 0 || j >= f.seg_names.len() {
    return _err_int("apple: index out of range");
  }
  if field == APPLE_SEG_FIELD_CMD_INDEX {
    let v: Int = f.seg_cmd_indices[j];
    return _ok_int(v);
  }
  if field == APPLE_SEG_FIELD_VMADDR {
    let v: Int = f.seg_vmaddrs[j];
    return _ok_int(v);
  }
  if field == APPLE_SEG_FIELD_VMSIZE {
    let v: Int = f.seg_vmsizes[j];
    return _ok_int(v);
  }
  if field == APPLE_SEG_FIELD_FILEOFF {
    let v: Int = f.seg_fileoffs[j];
    return _ok_int(v);
  }
  if field == APPLE_SEG_FIELD_FILESIZE {
    let v: Int = f.seg_filesizes[j];
    return _ok_int(v);
  }
  if field == APPLE_SEG_FIELD_MAXPROT {
    let v: Int = f.seg_maxprots[j];
    return _ok_int(v);
  }
  if field == APPLE_SEG_FIELD_INITPROT {
    let v: Int = f.seg_initprots[j];
    return _ok_int(v);
  }
  if field == APPLE_SEG_FIELD_NSECTS {
    let v: Int = f.seg_nsects[j];
    return _ok_int(v);
  }
  if field == APPLE_SEG_FIELD_FLAGS {
    let v: Int = f.seg_flags[j];
    return _ok_int(v);
  }
  return _err_int("apple: bad field selector");
}

/// Decoded name of segment `j` (`__TEXT`, `__DATA`, ...). Err("apple:
/// index out of range") when j is negative or >= macho_segment_count(f).
/// Compare with xiom.string.compare.str_compare, not `==`. Complexity:
/// O(1).
pub fn macho_segment_name(f: &MachOFile, j: Int) -> Result[Str, Str] {
  if j < 0 || j >= f.seg_names.len() {
    return _err_str("apple: index out of range");
  }
  let nm: Str = f.seg_names[j];
  return _ok_str(nm);
}

/// Field `field` (an APPLE_SEC_FIELD_* selector) of section `k`.
///
/// Err("apple: index out of range") when k is negative or >=
/// macho_section_count(f); Err("apple: bad field selector") otherwise on a
/// non-selector field. APPLE_SEC_FIELD_SEG_INDEX is the index of the owning
/// segment among macho_segment_count(f). The raw parsed value is returned.
/// Complexity: O(1).
pub fn macho_section_field(f: &MachOFile, k: Int, field: Int) -> Result[Int, Str] {
  if k < 0 || k >= f.sec_names.len() {
    return _err_int("apple: index out of range");
  }
  if field == APPLE_SEC_FIELD_SEG_INDEX {
    let v: Int = f.sec_seg_indices[k];
    return _ok_int(v);
  }
  if field == APPLE_SEC_FIELD_ADDR {
    let v: Int = f.sec_addrs[k];
    return _ok_int(v);
  }
  if field == APPLE_SEC_FIELD_SIZE {
    let v: Int = f.sec_sizes[k];
    return _ok_int(v);
  }
  if field == APPLE_SEC_FIELD_OFFSET {
    let v: Int = f.sec_offsets[k];
    return _ok_int(v);
  }
  if field == APPLE_SEC_FIELD_ALIGN {
    let v: Int = f.sec_aligns[k];
    return _ok_int(v);
  }
  if field == APPLE_SEC_FIELD_FLAGS {
    let v: Int = f.sec_flags[k];
    return _ok_int(v);
  }
  return _err_int("apple: bad field selector");
}

/// Decoded sectname of section `k` (`__text`, ...). Err("apple: index out
/// of range") when k is negative or >= macho_section_count(f). Compare with
/// str_compare, not `==`. Complexity: O(1).
pub fn macho_section_name(f: &MachOFile, k: Int) -> Result[Str, Str] {
  if k < 0 || k >= f.sec_names.len() {
    return _err_str("apple: index out of range");
  }
  let nm: Str = f.sec_names[k];
  return _ok_str(nm);
}

/// Decoded segname of section `k` (the 16-byte name repeated in the section
/// record). Err("apple: index out of range") when k is negative or >=
/// macho_section_count(f). Compare with str_compare, not `==`. Complexity:
/// O(1).
pub fn macho_section_segment_name(f: &MachOFile, k: Int) -> Result[Str, Str] {
  if k < 0 || k >= f.sec_segnames.len() {
    return _err_str("apple: index out of range");
  }
  let nm: Str = f.sec_segnames[k];
  return _ok_str(nm);
}

// --------------------------------------------------
//  Fat/universal archives
// --------------------------------------------------

// fat_header plus fat_arch table validation: magic/byte order, nfat_arch
// in 1..INT and the 20-byte record table inside the buffer, then every arch
// record (slice inside the buffer and clear of the arch table, align in
// 0..32, offset divisible by 2^align when align > 0), then every arch pair
// for overlap.
fn _parse_fat(data: &Vec[UInt8], f: &mut FatFile) -> Result[Unit, Str] {
  let total = data.len();
  if total < 8 {
    return _err_unit(_err_at("apple: truncated fat header", 0));
  }
  let fmt = _detect(data);
  if fmt == APPLE_FORMAT_FAT64_BE || fmt == APPLE_FORMAT_FAT64_LE {
    return _err_unit(_err_at("apple: fat64 header unsupported", 0));
  }
  if fmt != APPLE_FORMAT_FAT_BE && fmt != APPLE_FORMAT_FAT_LE {
    return _err_unit(_err_at("apple: not a fat archive", 0));
  }
  f.magic = _magic_be(data);
  if fmt == APPLE_FORMAT_FAT_LE {
    f.endianness = APPLE_ENDIAN_LE;
  } else {
    f.endianness = APPLE_ENDIAN_BE;
  }
  let be: Bool = f.endianness == APPLE_ENDIAN_BE;
  let count = _rdu(data, 4, 4, be);
  if count <= 0 {
    return _err_unit(_err_at("apple: bad fat arch count", 4));
  }
  let table = count * 20;
  if table > total - 8 {
    return _err_unit(_err_at("apple: fat arch table out of bounds", 4));
  }
  f.nfat_arch = count;
  let table_end = 8 + table;
  var i = 0;
  while i < count {
    let ap = 8 + i * 20;
    let cputype = _rdu(data, ap, 4, be);
    let cpusubtype = _rdu(data, ap + 4, 4, be);
    let offset = _rdu(data, ap + 8, 4, be);
    let size = _rdu(data, ap + 12, 4, be);
    let align = _rdu(data, ap + 16, 4, be);
    if align < 0 || align > 32 {
      return _err_unit(_err_at("apple: bad fat arch alignment", ap + 16));
    }
    if offset < 0 || size < 0 {
      return _err_unit(_err_at("apple: fat slice out of bounds", ap + 8));
    }
    if size > 0 {
      if offset > total || size > total - offset {
        return _err_unit(_err_at("apple: fat slice out of bounds", ap + 8));
      }
      if offset < table_end {
        return _err_unit(_err_at("apple: fat slice overlaps the arch table", ap + 8));
      }
    }
    if align > 0 {
      let unit = _pow2(align);
      if offset % unit != 0 {
        return _err_unit(_err_at("apple: misaligned fat slice", ap + 16));
      }
    }
    _append_fat_arch(f, cputype, cpusubtype, offset, size, align);
    i = i + 1;
  }
  var a = 0;
  while a < count {
    var b = a + 1;
    while b < count {
      let ao: Int = f.offsets[a];
      let as_: Int = f.sizes[a];
      let bo: Int = f.offsets[b];
      let bs: Int = f.sizes[b];
      if as_ > 0 && bs > 0 {
        if ao < bo + bs && bo < ao + as_ {
          return _err_unit(_err_at("apple: fat slices overlap", 8 + b * 20 + 8));
        }
      }
      b = b + 1;
    }
    a = a + 1;
  }
  return _ok_unit();
}

/// Parse a fat/universal header and its fat_arch table.
///
/// Validates the magic (big-endian FAT_MAGIC and little-endian FAT_CIGAM;
/// fat64 is rejected explicitly), the 8-byte header, nfat_arch >= 1, the
/// 20-byte-per-arch table span, every slice (inside the buffer, clear of
/// the arch table, offset aligned to 2^align for the recorded 0..32 align
/// exponent -- 12 = 4 KB and 14 = 16 KB are the conventional page sizes)
/// and every slice pair for overlap. On success the flat arch table is
/// filled; slice payloads stay in `data` and are read through
/// fat_slice_bytes / fat_slice_macho. Complexity: O(nfat_arch^2).
pub fn fat_parse(data: &Vec[UInt8]) -> Result[FatFile, Str] {
  var f = FatFile{
    magic: 0;
    endianness: 0;
    nfat_arch: 0;
    cputypes: Vec[Int].new();
    cpusubtypes: Vec[Int].new();
    offsets: Vec[Int].new();
    sizes: Vec[Int].new();
    aligns: Vec[Int].new();
  };
  let r1 = _parse_fat(data, &mut f);
  if !r1.is_ok {
    return _err_fat(r1.error);
  }
  return _ok_fat(f);
}

/// On-disk fat magic: APPLE_FAT_MAGIC or APPLE_FAT_CIGAM. Complexity: O(1).
pub fn fat_magic(f: &FatFile) -> Int {
  return f.magic;
}

/// APPLE_ENDIAN_BE for FAT_MAGIC, APPLE_ENDIAN_LE for FAT_CIGAM.
/// Complexity: O(1).
pub fn fat_endianness(f: &FatFile) -> Int {
  return f.endianness;
}

/// nfat_arch as stored in the header. Complexity: O(1).
pub fn fat_arch_count(f: &FatFile) -> Int {
  return f.nfat_arch;
}

/// Field `field` (an APPLE_FAT_FIELD_* selector) of arch record `i`.
///
/// Err("apple: index out of range") when i is negative or >=
/// fat_arch_count(f); Err("apple: bad field selector") otherwise on a
/// non-selector field. `align` is the stored power-of-two exponent.
/// Complexity: O(1).
pub fn fat_arch_field(f: &FatFile, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.nfat_arch {
    return _err_int("apple: index out of range");
  }
  if field == APPLE_FAT_FIELD_CPUTYPE {
    let v: Int = f.cputypes[i];
    return _ok_int(v);
  }
  if field == APPLE_FAT_FIELD_CPUSUBTYPE {
    let v: Int = f.cpusubtypes[i];
    return _ok_int(v);
  }
  if field == APPLE_FAT_FIELD_OFFSET {
    let v: Int = f.offsets[i];
    return _ok_int(v);
  }
  if field == APPLE_FAT_FIELD_SIZE {
    let v: Int = f.sizes[i];
    return _ok_int(v);
  }
  if field == APPLE_FAT_FIELD_ALIGN {
    let v: Int = f.aligns[i];
    return _ok_int(v);
  }
  return _err_int("apple: bad field selector");
}

/// Index of the first arch record whose cputype equals `cputype`, or -1
/// when absent. Exact match; duplicate cputypes resolve to the first.
/// Complexity: O(nfat_arch).
pub fn fat_select(f: &FatFile, cputype: Int) -> Int {
  let n: Int = f.cputypes.len();
  var i = 0;
  while i < n {
    let cur: Int = f.cputypes[i];
    if cur == cputype {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Index of the first arch record whose cputype and cpusubtype both match
/// exactly, or -1 when absent. Complexity: O(nfat_arch).
pub fn fat_select_subtype(f: &FatFile, cputype: Int, cpusubtype: Int) -> Int {
  let n: Int = f.cputypes.len();
  var i = 0;
  while i < n {
    let cur: Int = f.cputypes[i];
    let sub: Int = f.cpusubtypes[i];
    if cur == cputype && sub == cpusubtype {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Copy the raw bytes of slice `i` out of `data`.
///
/// Err("apple: index out of range") when i is negative or >=
/// fat_arch_count(f). The returned Vec[UInt8] is a fresh copy, so the slice
/// can be parsed independently (see fat_slice_macho). Complexity:
/// O(slice size).
pub fn fat_slice_bytes(data: &Vec[UInt8], f: &FatFile, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= f.nfat_arch {
    return _err_bytes("apple: index out of range");
  }
  let off: Int = f.offsets[i];
  let size: Int = f.sizes[i];
  var out = Vec[UInt8].new();
  var k = 0;
  while k < size {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Copy slice `i` and parse it as a thin Mach-O (macho_parse on the copy).
///
/// Err("apple: index out of range") when i is out of range; otherwise the
/// first error from macho_parse on the slice. Complexity: O(slice size).
pub fn fat_slice_macho(data: &Vec[UInt8], f: &FatFile, i: Int) -> Result[MachOFile, Str] {
  let r1 = fat_slice_bytes(data, f, i);
  if !r1.is_ok {
    return _err_macho(r1.error);
  }
  let slice: Vec[UInt8] = r1.value;
  let r2 = macho_parse(&slice);
  if !r2.is_ok {
    return _err_macho(r2.error);
  }
  return _ok_macho(r2.value);
}

/// Version marker of this package's module: "0.1.0". Complexity: O(1).
pub fn apple_version() -> Str {
  return "0.1.0";
}
