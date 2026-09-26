// XIOM -- xiom.cab: Microsoft Cabinet (CAB) header and directory codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.cab placeholder.
//
// Scope: the CFHEADER, CFFOLDER and CFFILE structures of a cabinet file.
// cab_parse validates the header (signature, reserved fields, version,
// folder/file counts, flags, optional setID/iCabinet and optional reserve
// descriptor + header reserve span) plus the directory (CFFOLDER entries with
// their per-folder reserve spans, CFFILE entries with their NUL-terminated
// names) and returns a flat CabArchive index built from parallel vectors.
// cab_build emits a canonical version-1.3 header plus a directory for
// uncompressed files (one folder, typeCompress 0 = none, cCFData 0 and no
// CFDATA blocks).
//
// Non-goals: CFDATA records and every compression algorithm (MSZIP, Quantum,
// LZX) are out of scope; parse keeps the raw typeCompress word and never
// touches compressed data. No decompression, no file extraction, no
// multi-cabinet (prev/next) set traversal: the prev/next flags and their
// NUL-terminated strings are validated and skipped but their names are not
// stored. The builder cannot emit CFDATA, reserve areas or prev/next links.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic; multi-byte
//     fields are assembled with multiplication only (no shifts on values
//     that can carry a sign bit).
//   * scalar and Vec element reads are always bound to typed locals before
//     comparison, and Str values read from Vec[Str] fields are compared with
//     xiom.string.compare.str_compare (BUG 17: `==` on such values lowers to
//     a pointer comparison).
//   * CabArchive (mixed scalar + parallel Vec fields) is constructed inside
//     cab_parse and crosses function boundaries only by reference or through
//     _ok_archive.
//   * bit tests are written as `(x & MASK) != 0` with an explicit mask
//     constant on values already masked to u8/u16 range; dates and times are
//     decoded arithmetically (`/`, `%`) like the xiom.mbr precedent.
// See SPEC.md for the byte layout tables, validation order, error catalog
// and test plan.

module xiom.cab

use xiom.string;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Signature length: the four bytes "MSCF" at offset 0.
pub const CAB_SIGNATURE_LEN: Int = 4;

/// Length of the fixed CFHEADER prefix through `flags`: 32 bytes.
pub const CAB_HEADER_MIN: Int = 32;

/// Length of a version-1.3 CFHEADER through `iCabinet`: 36 bytes.
pub const CAB_HEADER_LEN: Int = 36;

/// Length of one CFFOLDER entry before the per-folder reserve bytes: 8 bytes.
pub const CAB_FOLDER_LEN: Int = 8;

/// Length of the fixed CFFILE fields before `szName`: 16 bytes.
pub const CAB_FILE_LEN: Int = 16;

/// Largest accepted name, in bytes.
pub const CAB_MAX_NAME: Int = 255;

/// Largest file count (the `cFiles` field is a u16).
pub const CAB_MAX_FILES: Int = 65535;

/// Flag bit: a reserve descriptor plus header reserve area follows.
pub const CAB_FLAG_RESERVE_PRESENT: Int = 1;

/// Flag bit: the cabinet is locked (exposed raw; not interpreted).
pub const CAB_FLAG_LOCK: Int = 2;

/// Flag bit: the previous-cabinet name strings are present.
pub const CAB_FLAG_PREV_CABINET: Int = 4;

/// Flag bit: the next-cabinet name strings are present.
pub const CAB_FLAG_NEXT_CABINET: Int = 8;

/// typeCompress code: the folder data is stored (not compressed).
pub const CAB_COMPRESSION_NONE: Int = 0;

/// typeCompress code: MSZIP (deflate with a 32 KiB history).
pub const CAB_COMPRESSION_MSZIP: Int = 1;

/// typeCompress code: Quantum (Q | level bits).
pub const CAB_COMPRESSION_QUANTUM: Int = 2;

/// typeCompress code: LZX (window bits in the high nibble).
pub const CAB_COMPRESSION_LZX: Int = 3;

/// DOS attribute bit: read-only.
pub const CAB_ATTRIB_READONLY: Int = 1;

/// DOS attribute bit: hidden.
pub const CAB_ATTRIB_HIDDEN: Int = 2;

/// DOS attribute bit: system.
pub const CAB_ATTRIB_SYSTEM: Int = 4;

/// DOS attribute bit: volume label.
pub const CAB_ATTRIB_VOLUME: Int = 8;

/// DOS attribute bit: directory.
pub const CAB_ATTRIB_DIRECTORY: Int = 16;

/// DOS attribute bit: archive (the canonical builder's value).
pub const CAB_ATTRIB_ARCHIVE: Int = 32;

/// DOS attribute bit: device.
pub const CAB_ATTRIB_DEVICE: Int = 64;

/// Attribute bit 0x80: the CFFILE name is UTF-8 encoded (cabinet 1.3+).
pub const CAB_ATTRIB_UTF_NAME: Int = 128;

// --------------------------------------------------
//  Parsed cabinet index
// --------------------------------------------------

/// Parsed cabinet header and directory index.
///
/// The scalar fields mirror the CFHEADER: `cabinet_size` is `cbCabinet`,
/// `version_major`/`version_minor` the version bytes, `flags` the raw u16,
/// and `set_id`/`i_cabinet` are the optional u16 fields or -1 when the
/// version is below 1.3 and they are absent. `reserve_header_len`,
/// `reserve_folder_len` and `reserve_data_len` are `cbCFHeader`,
/// `cbCFFolder` and `cbCFData` (0 when no reserve area is present);
/// `reserved_header_offset` is the absolute offset of the header reserve
/// area (meaningful only when `reserve_header_len` > 0).
///
/// The Vec fields are the flat parallel columns, one element per entry, in
/// directory order. Files: `names` (`szName`), `file_sizes` (`cbFile`),
/// `file_offsets` (`uoffFolderStart`), `file_folders` (`iFolder`),
/// `file_dates`/`file_times` (raw packed DOS u16), `file_attribs` (raw u16).
/// Folders: `folder_starts` (`coffCabStart`), `folder_data_counts`
/// (`cCFData`), `folder_compress` (raw `typeCompress`), `folder_offsets`
/// (absolute offset of the 8-byte CFFOLDER entry). Fields are
/// implementation details; callers use the free functions below.
pub type CabArchive = {
  cabinet_size: Int;
  version_major: Int;
  version_minor: Int;
  flags: Int;
  set_id: Int;
  i_cabinet: Int;
  reserve_header_len: Int;
  reserve_folder_len: Int;
  reserve_data_len: Int;
  reserved_header_offset: Int;
  names: Vec[Str];
  file_sizes: Vec[Int];
  file_offsets: Vec[Int];
  file_folders: Vec[Int];
  file_dates: Vec[Int];
  file_times: Vec[Int];
  file_attribs: Vec[Int];
  folder_starts: Vec[Int];
  folder_data_counts: Vec[Int];
  folder_compress: Vec[Int];
  folder_offsets: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[CabArchive, Str].
fn _ok_archive(v: CabArchive) -> Result[CabArchive, Str] {
  return Ok(v);
}

// Err(m) for Result[CabArchive, Str].
fn _err_archive(m: Str) -> Result[CabArchive, Str] {
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

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte and field helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Little-endian u16 at `off` as an Int (0..65535); callers guarantee bounds.
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256;
}

// Little-endian u32 at `off` as an Int (0..2^32-1); callers guarantee bounds.
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256 + _byte(data, off + 2) * 65536 + _byte(data, off + 3) * 16777216;
}

// True when the four bytes at offset 0 are the cabinet signature "MSCF";
// callers guarantee at least CAB_SIGNATURE_LEN bytes.
fn _sig_ok(data: &Vec[UInt8]) -> Bool {
  if _byte(data, 0) != 77 { return false; }
  if _byte(data, 1) != 83 { return false; }
  if _byte(data, 2) != 67 { return false; }
  if _byte(data, 3) != 70 { return false; }
  return true;
}

// True when the version carries the optional setID/iCabinet fields: the
// documented "1.3 or greater" rule, i.e. major > 1, or major == 1 with
// minor >= 3.
fn _version_has_setid(major: Int, minor: Int) -> Bool {
  if major > 1 { return true; }
  if major == 1 && minor >= 3 { return true; }
  return false;
}

// True when raw name byte `b` is acceptable under `utf`: printable ASCII
// (0x20..0x7E) always; bytes 0x80..0xFF only when `utf` is set. Full UTF-8
// decoding is out of scope (documented policy: the bytes are kept verbatim).
fn _name_byte_ok(b: Int, utf: Bool) -> Bool {
  if b >= 32 && b <= 126 { return true; }
  if b >= 128 && utf { return true; }
  return false;
}

// Index just past the NUL-terminated string starting at `off`; the caller
// guarantees off <= limit. Err("cab: truncated string") when no NUL appears
// before `limit`.
fn _skip_cstr(data: &Vec[UInt8], off: Int, limit: Int) -> Result[Int, Str] {
  var i = off;
  while i < limit {
    if _byte(data, i) == 0 {
      return _ok_int(i + 1);
    }
    i = i + 1;
  }
  return _err_int("cab: truncated string");
}

// Name bytes of the CFFILE name starting at `off` and ending at the first
// NUL before `limit`. Err("cab: truncated name") when no NUL is found,
// Err("cab: bad name") for an empty name or a byte rejected by
// _name_byte_ok. The caller computes the next entry offset as
// off + name.len() + 1. The UTF policy is honored only for cabinets of
// version 1.3 or greater (the `utf` argument is the caller's decision).
fn _read_name(data: &Vec[UInt8], off: Int, limit: Int, utf: Bool) -> Result[Vec[UInt8], Str] {
  var bytes = Vec[UInt8].new();
  var i = off;
  var done = false;
  while i < limit && !done {
    let b: Int = _byte(data, i);
    if b == 0 {
      done = true;
    } else {
      if !_name_byte_ok(b, utf) {
        return _err_bytes("cab: bad name");
      }
      bytes.push(b as UInt8);
      i = i + 1;
    }
  }
  if !done {
    return _err_bytes("cab: truncated name");
  }
  if bytes.len() == 0 {
    return _err_bytes("cab: bad name");
  }
  return _ok_bytes(bytes);
}

// --------------------------------------------------
//  Writer helpers
// --------------------------------------------------

// Append the bytes of `s`.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append `v` (0..65535) as two little-endian bytes.
fn _push_le16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

// Append `v` (0..2^32-1) as four little-endian bytes.
fn _push_le32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse a Microsoft Cabinet header and directory.
///
/// The buffer must start with the four signature bytes "MSCF" and contain at
/// least the 32-byte fixed CFHEADER prefix. Validation order (first failure
/// wins): signature -> Err("cab: bad signature"); fixed header present ->
/// Err("cab: truncated header"); reserved1/reserved2/reserved3 all zero ->
/// Err("cab: reserved field set"); cbCabinet not beyond the buffer ->
/// Err("cab: truncated cabinet") and at least CAB_HEADER_MIN ->
/// Err("cab: bad cabinet size"); the version-1.3 optional fields (setID,
/// iCabinet) and the reserve descriptor + reserve bytes fit cbCabinet ->
/// Err("cab: truncated header"); prev/next cabinet strings are
/// NUL-terminated -> Err("cab: truncated string"); the CFFOLDER array fits
/// cbCabinet -> Err("cab: folder directory overflow"); when cFiles > 0,
/// coffFiles lies between the folder array end and cbCabinet ->
/// Err("cab: coffFiles out of range") and the minimal file directory fits ->
/// Err("cab: file directory overflow").
///
/// Per folder: coffCabStart <= cbCabinet, and when cCFData > 0 the minimal
/// CFDATA extent cCFData * (8 + cbCFData) fits at coffCabStart ->
/// Err("cab: folder data out of range"). The compression word is stored raw:
/// an unknown algorithm code is accepted (documented pass-through).
///
/// Per file (walked from coffFiles in order): the 16 fixed bytes fit ->
/// Err("cab: truncated file directory"); iFolder < cFolders ->
/// Err("cab: bad folder index"); uoffFolderStart + cbFile is representable
/// in 32 bits -> Err("cab: file span out of range"); the name is
/// NUL-terminated before cbCabinet -> Err("cab: truncated name") and passes
/// the printable policy -> Err("cab: bad name"). The printable policy
/// accepts bytes 0x20..0x7E always and bytes 0x80..0xFF only when the UTF
/// attribute bit (0x80) is set and the cabinet version is 1.3 or greater;
/// UTF-8 sequences are not decoded. Bytes past cbCabinet are ignored.
/// Complexity: O(data.len()).
pub fn cab_parse(data: &Vec[UInt8]) -> Result[CabArchive, Str] {
  if data.len() < CAB_SIGNATURE_LEN {
    return _err_archive("cab: bad signature");
  }
  if !_sig_ok(data) {
    return _err_archive("cab: bad signature");
  }
  if data.len() < CAB_HEADER_MIN {
    return _err_archive("cab: truncated header");
  }
  let r1: Int = _le32(data, 4);
  let size: Int = _le32(data, 8);
  let r2: Int = _le32(data, 12);
  let coff: Int = _le32(data, 16);
  let r3: Int = _le32(data, 20);
  let vmin: Int = _byte(data, 24);
  let vmaj: Int = _byte(data, 25);
  let nfolders: Int = _le16(data, 26);
  let nfiles: Int = _le16(data, 28);
  let flags: Int = _le16(data, 30);
  if r1 != 0 { return _err_archive("cab: reserved field set"); }
  if r2 != 0 { return _err_archive("cab: reserved field set"); }
  if r3 != 0 { return _err_archive("cab: reserved field set"); }
  if size > data.len() { return _err_archive("cab: truncated cabinet"); }
  if size < CAB_HEADER_MIN { return _err_archive("cab: bad cabinet size"); }
  let has_setid: Bool = _version_has_setid(vmaj, vmin);
  var pos: Int = CAB_HEADER_MIN;
  var set_id: Int = -1;
  var icabinet: Int = -1;
  if has_setid {
    if pos + 4 > size { return _err_archive("cab: truncated header"); }
    set_id = _le16(data, pos);
    icabinet = _le16(data, pos + 2);
    pos = pos + 4;
  }
  var rh_len: Int = 0;
  var rf_len: Int = 0;
  var rd_len: Int = 0;
  var rh_off: Int = pos;
  if (flags & CAB_FLAG_RESERVE_PRESENT) != 0 {
    if pos + 4 > size { return _err_archive("cab: truncated header"); }
    rh_len = _le16(data, pos);
    rf_len = _byte(data, pos + 2);
    rd_len = _byte(data, pos + 3);
    pos = pos + 4;
    if pos + rh_len > size { return _err_archive("cab: truncated header"); }
    rh_off = pos;
    pos = pos + rh_len;
  }
  if (flags & CAB_FLAG_PREV_CABINET) != 0 {
    let s1 = _skip_cstr(data, pos, size);
    if !s1.is_ok { return _err_archive("cab: truncated string"); }
    pos = s1.value;
    let s2 = _skip_cstr(data, pos, size);
    if !s2.is_ok { return _err_archive("cab: truncated string"); }
    pos = s2.value;
  }
  if (flags & CAB_FLAG_NEXT_CABINET) != 0 {
    let s3 = _skip_cstr(data, pos, size);
    if !s3.is_ok { return _err_archive("cab: truncated string"); }
    pos = s3.value;
    let s4 = _skip_cstr(data, pos, size);
    if !s4.is_ok { return _err_archive("cab: truncated string"); }
    pos = s4.value;
  }
  let folder_start: Int = pos;
  let folder_entry: Int = CAB_FOLDER_LEN + rf_len;
  if nfolders * folder_entry > size - folder_start {
    return _err_archive("cab: folder directory overflow");
  }
  let folder_end: Int = folder_start + nfolders * folder_entry;
  var file_start: Int = 0;
  if nfiles > 0 {
    if coff < folder_end { return _err_archive("cab: coffFiles out of range"); }
    if coff > size { return _err_archive("cab: coffFiles out of range"); }
    if nfiles * (CAB_FILE_LEN + 1) > size - coff {
      return _err_archive("cab: file directory overflow");
    }
    file_start = coff;
  }
  var names = Vec[Str].new();
  var file_sizes = Vec[Int].new();
  var file_offsets = Vec[Int].new();
  var file_folders = Vec[Int].new();
  var file_dates = Vec[Int].new();
  var file_times = Vec[Int].new();
  var file_attribs = Vec[Int].new();
  var folder_starts = Vec[Int].new();
  var folder_counts = Vec[Int].new();
  var folder_compress = Vec[Int].new();
  var folder_offsets = Vec[Int].new();
  var f = 0;
  while f < nfolders {
    let foff: Int = folder_start + f * folder_entry;
    let fstart: Int = _le32(data, foff);
    let fcount: Int = _le16(data, foff + 4);
    let fcomp: Int = _le16(data, foff + 6);
    if fstart > size { return _err_archive("cab: folder data out of range"); }
    if fcount * (CAB_FOLDER_LEN + rd_len) > size - fstart {
      return _err_archive("cab: folder data out of range");
    }
    folder_starts.push(fstart);
    folder_counts.push(fcount);
    folder_compress.push(fcomp);
    folder_offsets.push(foff);
    f = f + 1;
  }
  var i = 0;
  var fpos: Int = file_start;
  while i < nfiles {
    if fpos + CAB_FILE_LEN > size { return _err_archive("cab: truncated file directory"); }
    let fsize: Int = _le32(data, fpos);
    let fuoff: Int = _le32(data, fpos + 4);
    let ifolder: Int = _le16(data, fpos + 8);
    let fdate: Int = _le16(data, fpos + 10);
    let ftime: Int = _le16(data, fpos + 12);
    let fattrs: Int = _le16(data, fpos + 14);
    if ifolder >= nfolders { return _err_archive("cab: bad folder index"); }
    if fuoff + fsize > 4294967295 { return _err_archive("cab: file span out of range"); }
    let utf: Bool = has_setid && ((fattrs & CAB_ATTRIB_UTF_NAME) != 0);
    let name_at: Int = fpos + CAB_FILE_LEN;
    let nr = _read_name(data, name_at, size, utf);
    if !nr.is_ok { return _err_archive(nr.error); }
    let nb: Vec[UInt8] = nr.value;
    let nmlen: Int = nb.len();
    let nm: Str = Str::from_utf8(nb);
    names.push(nm);
    file_sizes.push(fsize);
    file_offsets.push(fuoff);
    file_folders.push(ifolder);
    file_dates.push(fdate);
    file_times.push(ftime);
    file_attribs.push(fattrs);
    fpos = name_at + nmlen + 1;
    i = i + 1;
  }
  let archive = CabArchive{
    cabinet_size: size;
    version_major: vmaj;
    version_minor: vmin;
    flags: flags;
    set_id: set_id;
    i_cabinet: icabinet;
    reserve_header_len: rh_len;
    reserve_folder_len: rf_len;
    reserve_data_len: rd_len;
    reserved_header_offset: rh_off;
    names: names;
    file_sizes: file_sizes;
    file_offsets: file_offsets;
    file_folders: file_folders;
    file_dates: file_dates;
    file_times: file_times;
    file_attribs: file_attribs;
    folder_starts: folder_starts;
    folder_data_counts: folder_counts;
    folder_compress: folder_compress;
    folder_offsets: folder_offsets;
  };
  return _ok_archive(archive);
}

/// Total cabinet size from the header (`cbCabinet`), in bytes.
/// Complexity: O(1).
pub fn cab_cabinet_size(a: &CabArchive) -> Int {
  return a.cabinet_size;
}

/// CFHEADER version major byte.
/// Complexity: O(1).
pub fn cab_version_major(a: &CabArchive) -> Int {
  return a.version_major;
}

/// CFHEADER version minor byte.
/// Complexity: O(1).
pub fn cab_version_minor(a: &CabArchive) -> Int {
  return a.version_minor;
}

/// Raw CFHEADER flags word. The documented bits are CAB_FLAG_RESERVE_PRESENT
/// (1), CAB_FLAG_LOCK (2, exposed but not interpreted),
/// CAB_FLAG_PREV_CABINET (4) and CAB_FLAG_NEXT_CABINET (8).
/// Complexity: O(1).
pub fn cab_flags(a: &CabArchive) -> Int {
  return a.flags;
}

/// Cabinet set identifier (`setID`), or -1 when the version is below 1.3 and
/// the field is absent.
/// Complexity: O(1).
pub fn cab_set_id(a: &CabArchive) -> Int {
  return a.set_id;
}

/// Cabinet index in its set (`iCabinet`), or -1 when the version is below
/// 1.3 and the field is absent.
/// Complexity: O(1).
pub fn cab_i_cabinet(a: &CabArchive) -> Int {
  return a.i_cabinet;
}

/// Number of CFFOLDER entries.
/// Complexity: O(1).
pub fn cab_folder_count(a: &CabArchive) -> Int {
  return a.folder_starts.len();
}

/// Number of CFFILE entries.
/// Complexity: O(1).
pub fn cab_file_count(a: &CabArchive) -> Int {
  return a.names.len();
}

/// `cbCFHeader`: byte length of the header reserve area (0 when the reserve
/// flag is clear).
/// Complexity: O(1).
pub fn cab_reserved_header_len(a: &CabArchive) -> Int {
  return a.reserve_header_len;
}

/// `cbCFFolder`: byte length of the per-folder reserve area appended to every
/// CFFOLDER entry (0 when the reserve flag is clear).
/// Complexity: O(1).
pub fn cab_reserved_folder_len(a: &CabArchive) -> Int {
  return a.reserve_folder_len;
}

/// `cbCFData`: byte length of the per-CFDATA reserve area (0 when the
/// reserve flag is clear); CFDATA records themselves are not parsed.
/// Complexity: O(1).
pub fn cab_reserved_data_len(a: &CabArchive) -> Int {
  return a.reserve_data_len;
}

/// Absolute offset of the header reserve area (`abReserve`). When
/// cab_reserved_header_len is 0 this is the offset just past the optional
/// header fields and the span is empty.
/// Complexity: O(1).
pub fn cab_reserved_header_offset(a: &CabArchive) -> Int {
  return a.reserved_header_offset;
}

/// `coffCabStart` of folder `i`: absolute offset of the folder's first
/// CFDATA record; -1 out of range.
/// Complexity: O(1).
pub fn cab_folder_start(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.folder_starts.len() {
    return -1;
  }
  let v: Int = a.folder_starts[i];
  return v;
}

/// `cCFData` of folder `i`: number of CFDATA records; -1 out of range.
/// Complexity: O(1).
pub fn cab_folder_data_count(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.folder_data_counts.len() {
    return -1;
  }
  let v: Int = a.folder_data_counts[i];
  return v;
}

/// Raw `typeCompress` word of folder `i` (unknown codes pass through);
/// -1 out of range. See cab_compression_code / cab_compression_known.
/// Complexity: O(1).
pub fn cab_folder_compression(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.folder_compress.len() {
    return -1;
  }
  let v: Int = a.folder_compress[i];
  return v;
}

/// Absolute offset where folder `i`'s per-folder reserve bytes start (the
/// CFFOLDER entry offset + 8); -1 out of range. The span length is
/// cab_reserved_folder_len(a), 0 when no reserve area is present.
/// Complexity: O(1).
pub fn cab_folder_reserve_offset(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.folder_offsets.len() {
    return -1;
  }
  let v: Int = a.folder_offsets[i];
  return v + CAB_FOLDER_LEN;
}

/// `szName` of file `i` (without the terminating NUL), or "" out of range.
/// The result is a Str read from a Vec[Str] field: callers must compare it
/// with xiom.string.compare.str_compare rather than `==`.
/// Complexity: O(1).
pub fn cab_file_name(a: &CabArchive, i: Int) -> Str {
  if i < 0 || i >= a.names.len() {
    return "";
  }
  let nm: Str = a.names[i];
  return nm;
}

/// `cbFile` of file `i`: uncompressed size in bytes; -1 out of range.
/// Complexity: O(1).
pub fn cab_file_size(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.file_sizes.len() {
    return -1;
  }
  let v: Int = a.file_sizes[i];
  return v;
}

/// `uoffFolderStart` of file `i`: uncompressed offset inside folder
/// `cab_file_folder(a, i)`; -1 out of range.
/// Complexity: O(1).
pub fn cab_file_offset(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.file_offsets.len() {
    return -1;
  }
  let v: Int = a.file_offsets[i];
  return v;
}

/// `iFolder` of file `i`: index of the owning folder; -1 out of range.
/// Complexity: O(1).
pub fn cab_file_folder(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.file_folders.len() {
    return -1;
  }
  let v: Int = a.file_folders[i];
  return v;
}

/// Raw packed MS-DOS date of file `i` (see cab_dos_date_year / _month /
/// _day); -1 out of range.
/// Complexity: O(1).
pub fn cab_file_date(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.file_dates.len() {
    return -1;
  }
  let v: Int = a.file_dates[i];
  return v;
}

/// Raw packed MS-DOS time of file `i`, in two-second units (see
/// cab_dos_time_hour / _minute / _second); -1 out of range.
/// Complexity: O(1).
pub fn cab_file_time(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.file_times.len() {
    return -1;
  }
  let v: Int = a.file_times[i];
  return v;
}

/// Raw `attribs` word of file `i` (see the CAB_ATTRIB_* constants);
/// -1 out of range.
/// Complexity: O(1).
pub fn cab_file_attribs(a: &CabArchive, i: Int) -> Int {
  if i < 0 || i >= a.file_attribs.len() {
    return -1;
  }
  let v: Int = a.file_attribs[i];
  return v;
}

/// True when the 0x80 name-is-UTF-8 attribute bit is set in file `i`'s raw
/// attribs word; false out of range. Name validation honors the bit only for
/// cabinets of version 1.3 or greater (see cab_parse).
/// Complexity: O(1).
pub fn cab_file_utf(a: &CabArchive, i: Int) -> Bool {
  if i < 0 || i >= a.file_attribs.len() {
    return false;
  }
  let v: Int = a.file_attribs[i];
  return (v & CAB_ATTRIB_UTF_NAME) != 0;
}

/// Compression algorithm code: the low nibble of a raw `typeCompress` word
/// (0 none, 1 MSZIP, 2 Quantum, 3 LZX); -1 when `type_compress` is negative.
/// Complexity: O(1).
pub fn cab_compression_code(type_compress: Int) -> Int {
  if type_compress < 0 {
    return -1;
  }
  return type_compress % 16;
}

/// True when the typeCompress algorithm code is one of the four documented
/// codes (0..3). Unknown codes return false but still parse (documented
/// pass-through of the raw word).
/// Complexity: O(1).
pub fn cab_compression_known(type_compress: Int) -> Bool {
  let code: Int = cab_compression_code(type_compress);
  if code < 0 {
    return false;
  }
  if code > CAB_COMPRESSION_LZX {
    return false;
  }
  return true;
}

/// True when a cabinet with this (major, minor) version carries the optional
/// setID/iCabinet fields: the documented "1.3 or greater" rule.
/// Complexity: O(1).
pub fn cab_version_has_setid(major: Int, minor: Int) -> Bool {
  return _version_has_setid(major, minor);
}

/// Year of a raw packed MS-DOS date (1980..2107 for a u16 input).
/// Complexity: O(1).
pub fn cab_dos_date_year(d: Int) -> Int {
  return 1980 + d / 512;
}

/// Month of a raw packed MS-DOS date (0..15 as stored; 0 means unset).
/// Complexity: O(1).
pub fn cab_dos_date_month(d: Int) -> Int {
  return (d / 32) % 16;
}

/// Day of a raw packed MS-DOS date (0..31 as stored; 0 means unset).
/// Complexity: O(1).
pub fn cab_dos_date_day(d: Int) -> Int {
  return d % 32;
}

/// Hour of a raw packed MS-DOS time (0..31 as stored; 0 means unset).
/// Complexity: O(1).
pub fn cab_dos_time_hour(t: Int) -> Int {
  return t / 2048;
}

/// Minute of a raw packed MS-DOS time (0..63 as stored; 0 means unset).
/// Complexity: O(1).
pub fn cab_dos_time_minute(t: Int) -> Int {
  return (t / 32) % 64;
}

/// Second of a raw packed MS-DOS time, in two-second units (0..62).
/// Complexity: O(1).
pub fn cab_dos_time_second(t: Int) -> Int {
  return (t % 32) * 2;
}

/// Build a canonical cabinet header plus directory for uncompressed files.
///
/// `sizes[i]` is the declared uncompressed size (`cbFile`) of `names[i]`.
/// The output is a structurally valid, dataless cabinet: a version-1.3
/// CFHEADER (setID 0, iCabinet 0), one CFFOLDER (typeCompress
/// CAB_COMPRESSION_NONE, cCFData 0, coffCabStart = the end of the directory,
/// where CFDATA records would begin), then one CFFILE per name in order, with
/// iFolder 0, date/time 0, attribs CAB_ATTRIB_ARCHIVE (0x20) and
/// uoffFolderStart set to the running sum of the declared sizes. cbCabinet is
/// the exact emitted length. No CFDATA blocks are written and no reserve or
/// prev/next areas are emitted, so the result parses with cab_parse but is
/// not extractable.
///
/// Validation runs before the first byte is written. Err("cab: entry count
/// mismatch") when names.len() != sizes.len(); Err("cab: too many files")
/// above CAB_MAX_FILES entries; Err("cab: size overflow") when a size is
/// negative or above 2^32-1; Err("cab: bad name") for an empty name or a
/// byte outside the printable ASCII policy (0x20..0x7E);
/// Err("cab: name too long") above CAB_MAX_NAME bytes.
/// Complexity: O(total name bytes).
pub fn cab_build(names: &Vec[Str], sizes: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let count: Int = names.len();
  if sizes.len() != count {
    return _err_bytes("cab: entry count mismatch");
  }
  if count > CAB_MAX_FILES {
    return _err_bytes("cab: too many files");
  }
  var i = 0;
  var dir_len: Int = 0;
  while i < count {
    let nm: Str = names[i];
    let sz: Int = sizes[i];
    if sz < 0 || sz > 4294967295 {
      return _err_bytes("cab: size overflow");
    }
    let nl: Int = nm.len();
    if nl == 0 {
      return _err_bytes("cab: bad name");
    }
    if nl > CAB_MAX_NAME {
      return _err_bytes("cab: name too long");
    }
    var k = 0;
    while k < nl {
      let b: Int = (string.byte_at(nm, k) as Int) & 0xFF;
      if !_name_byte_ok(b, false) {
        return _err_bytes("cab: bad name");
      }
      k = k + 1;
    }
    dir_len = dir_len + CAB_FILE_LEN + nl + 1;
    i = i + 1;
  }
  let coff_files: Int = CAB_HEADER_LEN + CAB_FOLDER_LEN;
  let total: Int = coff_files + dir_len;
  var out = Vec[UInt8].new();
  _push_str(&mut out, "MSCF");
  _push_le32(&mut out, 0);
  _push_le32(&mut out, total);
  _push_le32(&mut out, 0);
  _push_le32(&mut out, coff_files);
  _push_le32(&mut out, 0);
  out.push(3 as UInt8);
  out.push(1 as UInt8);
  _push_le16(&mut out, 1);
  _push_le16(&mut out, count);
  _push_le16(&mut out, 0);
  _push_le16(&mut out, 0);
  _push_le16(&mut out, 0);
  _push_le32(&mut out, total);
  _push_le16(&mut out, 0);
  _push_le16(&mut out, 0);
  var off: Int = 0;
  i = 0;
  while i < count {
    let nm: Str = names[i];
    let sz: Int = sizes[i];
    _push_le32(&mut out, sz);
    _push_le32(&mut out, off);
    _push_le16(&mut out, 0);
    _push_le16(&mut out, 0);
    _push_le16(&mut out, 0);
    _push_le16(&mut out, CAB_ATTRIB_ARCHIVE);
    _push_str(&mut out, nm);
    out.push(0 as UInt8);
    off = off + sz;
    i = i + 1;
  }
  return _ok_bytes(out);
}
