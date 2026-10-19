// XIOM -- xiom.uf2: UF2 firmware-image format + BOOTSEL flashing (host side).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// UF2 ("USB Flashing Format") is the drag-and-drop firmware container used
// by the RP2040/RP2350 BOOTSEL mass-storage bootloaders, the SAMD21/SAMD51
// Arduino bootloaders, and many other MCUs.  A file is a sequence of
// 512-byte blocks; every block carries a 32-byte little-endian header, up
// to 476 payload bytes, zero padding to offset 508, and the end magic.
//
// This module is a PURE-XIOM implementation: the format is rebuilt from
// the published specification and the upstream header/table
// (microsoft/uf2 @ 90e9741f, MIT; reference-only -- no code is vendored).
// It has two legs:
//
//   * format: build/parse/validate blocks and images, family IDs, flags,
//     byte-exact roundtrip, structural integrity (counts, ordering,
//     address overflow, mixed families) -- all deterministic and
//     hardware-free;
//   * flashing: copy a validated image to a mounted BOOTSEL volume with
//     binary I/O (never text-mode), read it back for verification, then
//     detect completion by the volume/file disappearing (the board
//     reboots when the last block lands).  A missing mount is a typed
//     SKIP result, not an error, so fleet hosts stay green.
//
// Classification:
//   UF2_FLASH_SKIP     -> no mount/volume present (or the mount vanished
//                         before the copy started) -> SKIP
//   UF2_FLASH_COPIED   -> image copied + read-back verified, but the
//                         volume was still mounted when the wait expired
//   UF2_FLASH_COMPLETE -> the destination file or the mount disappeared
//                         -> the bootloader rebooted (flash complete)
//   Err(Uf2Error)      -> validation/I/O/verification failure
//
// All multi-byte fields are little-endian; all addresses are 32-bit
// unsigned values carried in XIOM Int (the format cannot represent more).

module xiom.uf2

use xiom.io;
use xiom.io.fs;
use xiom.serialize.endian;
use xiom.string;
use xiom.string.compare;

// =========================================================================
// Format constants (oracle: uf2.h @ 90e9741f; MIT)
// =========================================================================

/// Every UF2 block is exactly 512 bytes.
pub const UF2_BLOCK_SIZE: Int = 512;

/// Fixed header before the payload (8 little-endian u32 fields).
pub const UF2_HEADER_SIZE: Int = 32;

/// Maximum payload bytes per block (512 - 32 header - 4 end magic).
pub const UF2_MAX_PAYLOAD: Int = 476;

/// First start magic, little-endian u32 0x0A324655 ("UF2\n").
pub const UF2_MAGIC_START0: Int = 171066965;

/// Second start magic, little-endian u32 0x9E5D5157.
pub const UF2_MAGIC_START1: Int = 2656915799;

/// End magic at offset 508, little-endian u32 0x0AB16F30.
pub const UF2_MAGIC_END: Int = 179400496;

/// Largest value representable in a UF2 32-bit field.
pub const UF2_U32_MAX: Int = 4294967295;

// =========================================================================
// Flags (uf2.h UF2_FLAG_*)
// =========================================================================

/// Block is a comment/container entry and must not be flashed.
pub const UF2_FLAG_NOFLASH: Int = 1;

/// Block belongs to a file container (arbitrary target addresses).
pub const UF2_FLAG_FILECONTAINER: Int = 4096;

/// The familyID field is present and holds a device-family identifier.
pub const UF2_FLAG_FAMILY_ID: Int = 8192;

/// The familyID field holds an MD5 checksum instead of a family identifier.
pub const UF2_FLAG_MD5_CHKSUM: Int = 16384;

/// Extension tags are present in the payload.
pub const UF2_FLAG_EXTENSION_TAGS: Int = 32768;

/// Every flag bit defined by the pinned specification (0xF001).  Reserved
/// bits are rejected by this implementation (strict validation).
pub const UF2_FLAG_KNOWN_MASK: Int = 61441;

// =========================================================================
// Family identifiers (upstream utils/uf2families.json @ 90e9741f)
// =========================================================================

/// Raspberry Pi RP2040.
pub const UF2_FAMILY_RP2040: Int = 3834380118;

/// Raspberry Pi RP2xxx absolute (unpartitioned) download.
pub const UF2_FAMILY_RP2XXX_ABSOLUTE: Int = 3834380119;

/// Raspberry Pi RP2xxx data-partition download.
pub const UF2_FAMILY_RP2XXX_DATA: Int = 3834380120;

/// Raspberry Pi RP2350 secure Arm image.
pub const UF2_FAMILY_RP2350_ARM_S: Int = 3834380121;

/// Raspberry Pi RP2350 RISC-V image.
pub const UF2_FAMILY_RP2350_RISCV: Int = 3834380122;

/// Raspberry Pi RP2350 non-secure Arm image.
pub const UF2_FAMILY_RP2350_ARM_NS: Int = 3834380123;

/// Microchip (Atmel) SAMD21.
pub const UF2_FAMILY_SAMD21: Int = 1760373640;

/// Microchip (Atmel) SAMD51.
pub const UF2_FAMILY_SAMD51: Int = 1427194976;

// =========================================================================
// Error kinds (typed; never a panic on caller input)
// =========================================================================

/// Invalid argument (empty path, negative timeout, bad chunk size).
pub const UF2_ERR_ARG: Int = 1;

/// Wrong byte length (block not 512, image not a multiple of 512).
pub const UF2_ERR_SIZE: Int = 2;

/// A start or end magic did not match.
pub const UF2_ERR_MAGIC: Int = 3;

/// Payload size outside 0..476.
pub const UF2_ERR_PAYLOAD: Int = 4;

/// Block numbering invalid (blockNo >= numBlocks, duplicate/missing).
pub const UF2_ERR_INDEX: Int = 5;

/// Unknown/reserved flag bits, or mutually exclusive flags together.
pub const UF2_ERR_FLAGS: Int = 6;

/// Inconsistent or mixed family identifiers inside one image.
pub const UF2_ERR_FAMILY: Int = 7;

/// Source read or destination write failure.
pub const UF2_ERR_IO: Int = 8;

/// The mount path is not a directory (internal; the public flash reports
/// an absent mount as SKIP).
pub const UF2_ERR_MOUNT: Int = 9;

/// The read-back copy does not match the source bytes.
pub const UF2_ERR_VERIFY: Int = 10;

// =========================================================================
// Flash result statuses
// =========================================================================

/// No mount/volume present -> SKIP (deterministic, not an error).
pub const UF2_FLASH_SKIP: Int = 0;

/// Copy verified and the volume/file then disappeared -> flash complete.
pub const UF2_FLASH_COMPLETE: Int = 1;

/// Copy verified but the volume was still mounted when the wait expired.
pub const UF2_FLASH_COPIED: Int = 2;

/// BOOTSEL info file exposed by the upstream bootloaders.
pub const UF2_INFO_FILE: Str = "INFO_UF2.TXT";

// =========================================================================
// Public types
// =========================================================================

/// Typed UF2 failure.
pub type Uf2Error = {
  kind: Int;
  message: Str;
}

/// One parsed 512-byte UF2 block.
///
/// `family_id` is the raw 8th header field; it is a family identifier only
/// when `has_family` is true, and an MD5 checksum when `has_md5` is true.
pub type Uf2Block = {
  flags: Int;
  target_addr: Int;
  payload_size: Int;
  block_no: Int;
  num_blocks: Int;
  family_id: Int;
  has_family: Bool;
  no_flash: Bool;
  file_container: Bool;
  has_md5: Bool;
  has_extension_tags: Bool;
  payload: Vec[UInt8];
}

/// A validated UF2 image.
///
/// `blocks` keeps file order; `payload` concatenates the non-comment blocks
/// in block-number order; `contiguous` reports whether consecutive flashing
/// blocks meet exactly (target[n+1] == target[n] + payload_size[n]).
pub type Uf2Image = {
  blocks: Vec[Uf2Block];
  num_blocks: Int;
  family_id: Int;
  has_family: Bool;
  payload: Vec[UInt8];
  data_bytes: Int;
  target_addr: Int;
  contiguous: Bool;
  file_container: Bool;
}

/// Outcome of a flash-to-mount attempt (statuses above).
pub type Uf2FlashResult = {
  status: Int;
  source_path: Str;
  dest_path: Str;
  source_bytes: Int;
  copied_bytes: Int;
  blocks: Int;
  verified: Bool;
  elapsed_ms: Int;
  detail: Str;
}

// =========================================================================
// Local helpers
// =========================================================================

/// Local Int-to-Str (avoids cross-module convert resolution inside the
/// module; the lane pattern used by xiom.serial).
fn _itoa(n: Int) -> Str {
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

fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn _err(kind: Int, message: Str) -> Uf2Error {
  return Uf2Error{ kind: kind; message: message; };
}

fn _u32(data: &Vec[UInt8], off: Int) -> Int {
  return endian.read_u32_le(data, off) as Int;
}

fn _put_u32(out: &mut Vec[UInt8], value: Int) {
  endian.write_u32_le(out, value as UInt32);
}

fn _append_vec(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn _bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn _flags_known(flags: Int) -> Bool {
  if flags < 0 { return false; }
  return (flags | UF2_FLAG_KNOWN_MASK) == UF2_FLAG_KNOWN_MASK;
}

fn _family_ok(family_id: Int) -> Bool {
  return family_id >= 0 && family_id <= UF2_U32_MAX;
}

fn _addr_ok(addr: Int, payload_size: Int) -> Bool {
  if addr < 0 || addr > UF2_U32_MAX { return false; }
  if payload_size < 0 || payload_size > UF2_MAX_PAYLOAD { return false; }
  return addr <= UF2_U32_MAX - payload_size;
}

fn _basename(path: Str) -> Str {
  if path.len() == 0 { return ""; }
  var i = path.len() - 1;
  while i >= 0 {
    let c = string.byte_at(path, i);
    if c == 92 || c == 47 {
      if i == path.len() - 1 { return ""; }
      return string.str_slice(path, i + 1, path.len());
    }
    i = i - 1;
  }
  return path;
}

fn _flash_complete_unverified(source_path: Str, dest: Str, bytes: Int, blocks: Int, elapsed: Int) -> Uf2FlashResult {
  return Uf2FlashResult{
    status: UF2_FLASH_COMPLETE;
    source_path: source_path;
    dest_path: dest;
    source_bytes: bytes;
    copied_bytes: bytes;
    blocks: blocks;
    verified: false;
    elapsed_ms: elapsed;
    detail: "volume/file disappeared before read-back (board rebooted)";
  };
}

fn _file_bytes(path: Str) -> Result[Vec[UInt8], Str] {
  let sz = fs.fs_size(path);
  if !sz.is_ok { return Err(sz.error); }
  if sz.value <= 0 { return Err("empty file"); }
  let r = fs.fs_read_range(path, 0, sz.value);
  if !r.is_ok { return Err(r.error); }
  if r.value.len() != sz.value { return Err("short read"); }
  return Ok(r.value);
}

// =========================================================================
// Block build
// =========================================================================

/// Build one 512-byte UF2 block with automatic flags: FAMILY_ID is set when
/// `family_id` is non-zero.  The payload is zero-padded to offset 508 and
/// the end magic is written last.
///
/// Complexity: O(payload).
pub fn uf2_block_build(payload: &Vec[UInt8], target_addr: Int, block_no: Int, num_blocks: Int, family_id: Int) -> Result[Vec[UInt8], Uf2Error] {
  var flags = 0;
  if family_id != 0 { flags = UF2_FLAG_FAMILY_ID; }
  return uf2_block_build_with_flags(flags, payload, target_addr, block_no, num_blocks, family_id);
}

/// Build one 512-byte UF2 block with explicit flags.  `family_field` is the
/// raw 8th header field (family ID when FAMILY_ID is set, MD5 when
/// MD5_CHKSUM is set).
///
/// Complexity: O(payload).
pub fn uf2_block_build_with_flags(flags: Int, payload: &Vec[UInt8], target_addr: Int, block_no: Int, num_blocks: Int, family_field: Int) -> Result[Vec[UInt8], Uf2Error] {
  if !_flags_known(flags) {
    return Err(_err(UF2_ERR_FLAGS, "block_build: unknown flag bits " + _itoa(flags)));
  }
  if (flags & UF2_FLAG_FAMILY_ID) != 0 && (flags & UF2_FLAG_MD5_CHKSUM) != 0 {
    return Err(_err(UF2_ERR_FLAGS, "block_build: FAMILY_ID and MD5_CHKSUM are mutually exclusive"));
  }
  if payload.len() > UF2_MAX_PAYLOAD {
    return Err(_err(UF2_ERR_PAYLOAD, "block_build: payload " + _itoa(payload.len()) + " exceeds " + _itoa(UF2_MAX_PAYLOAD)));
  }
  if num_blocks < 1 {
    return Err(_err(UF2_ERR_INDEX, "block_build: num_blocks must be >= 1"));
  }
  if block_no < 0 || block_no >= num_blocks {
    return Err(_err(UF2_ERR_INDEX, "block_build: block_no " + _itoa(block_no) + " outside 0.." + _itoa(num_blocks - 1)));
  }
  if !_addr_ok(target_addr, payload.len()) {
    return Err(_err(UF2_ERR_ARG, "block_build: target_addr/payload overflow the 32-bit address space"));
  }
  if !_family_ok(family_field) {
    return Err(_err(UF2_ERR_ARG, "block_build: family_field outside u32"));
  }

  var out: Vec[UInt8] = Vec[UInt8].new();
  _put_u32(&mut out, UF2_MAGIC_START0);
  _put_u32(&mut out, UF2_MAGIC_START1);
  _put_u32(&mut out, flags);
  _put_u32(&mut out, target_addr);
  _put_u32(&mut out, payload.len());
  _put_u32(&mut out, block_no);
  _put_u32(&mut out, num_blocks);
  _put_u32(&mut out, family_field);
  _append_vec(&mut out, payload);
  while out.len() < UF2_BLOCK_SIZE - 4 {
    out.push(0);
  }
  _put_u32(&mut out, UF2_MAGIC_END);
  return Ok(out);
}

// =========================================================================
// Block parse / validate
// =========================================================================

fn _block_at(data: &Vec[UInt8], off: Int) -> Result[Uf2Block, Uf2Error] {
  if off < 0 || off > data.len() {
    return Err(_err(UF2_ERR_SIZE, "block_parse: offset outside buffer"));
  }
  if data.len() - off < UF2_BLOCK_SIZE {
    return Err(_err(UF2_ERR_SIZE, "block_parse: need 512 bytes, have " + _itoa(data.len() - off)));
  }
  let m0 = _u32(data, off);
  if m0 != UF2_MAGIC_START0 {
    return Err(_err(UF2_ERR_MAGIC, "block_parse: start magic 0 mismatch"));
  }
  let m1 = _u32(data, off + 4);
  if m1 != UF2_MAGIC_START1 {
    return Err(_err(UF2_ERR_MAGIC, "block_parse: start magic 1 mismatch"));
  }
  let flags = _u32(data, off + 8);
  if !_flags_known(flags) {
    return Err(_err(UF2_ERR_FLAGS, "block_parse: unknown flag bits " + _itoa(flags)));
  }
  let target_addr = _u32(data, off + 12);
  let payload_size = _u32(data, off + 16);
  let block_no = _u32(data, off + 20);
  let num_blocks = _u32(data, off + 24);
  let family_field = _u32(data, off + 28);
  if payload_size > UF2_MAX_PAYLOAD {
    return Err(_err(UF2_ERR_PAYLOAD, "block_parse: payload_size " + _itoa(payload_size) + " exceeds " + _itoa(UF2_MAX_PAYLOAD)));
  }
  if num_blocks < 1 {
    return Err(_err(UF2_ERR_INDEX, "block_parse: num_blocks is zero"));
  }
  if block_no >= num_blocks {
    return Err(_err(UF2_ERR_INDEX, "block_parse: block_no " + _itoa(block_no) + " >= num_blocks " + _itoa(num_blocks)));
  }
  if !_addr_ok(target_addr, payload_size) {
    return Err(_err(UF2_ERR_ARG, "block_parse: target_addr/payload overflow the 32-bit address space"));
  }
  let end_magic = _u32(data, off + UF2_BLOCK_SIZE - 4);
  if end_magic != UF2_MAGIC_END {
    return Err(_err(UF2_ERR_MAGIC, "block_parse: end magic mismatch"));
  }
  if (flags & UF2_FLAG_FAMILY_ID) != 0 && (flags & UF2_FLAG_MD5_CHKSUM) != 0 {
    return Err(_err(UF2_ERR_FLAGS, "block_parse: FAMILY_ID and MD5_CHKSUM are mutually exclusive"));
  }

  var payload: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < payload_size {
    payload.push(data[off + UF2_HEADER_SIZE + i]);
    i = i + 1;
  }
  return Ok(Uf2Block{
    flags: flags;
    target_addr: target_addr;
    payload_size: payload_size;
    block_no: block_no;
    num_blocks: num_blocks;
    family_id: family_field;
    has_family: (flags & UF2_FLAG_FAMILY_ID) != 0;
    no_flash: (flags & UF2_FLAG_NOFLASH) != 0;
    file_container: (flags & UF2_FLAG_FILECONTAINER) != 0;
    has_md5: (flags & UF2_FLAG_MD5_CHKSUM) != 0;
    has_extension_tags: (flags & UF2_FLAG_EXTENSION_TAGS) != 0;
    payload: payload;
  });
}

/// Parse one 512-byte UF2 block.  Any trailing bytes after the first 512 are
/// ignored; use `uf2_image_parse` for whole files.
///
/// Complexity: O(1).
pub fn uf2_block_parse(bytes: &Vec[UInt8]) -> Result[Uf2Block, Uf2Error] {
  if bytes.len() < UF2_BLOCK_SIZE {
    return Err(_err(UF2_ERR_SIZE, "block_parse: need 512 bytes, have " + _itoa(bytes.len())));
  }
  return _block_at(bytes, 0);
}

/// Parse the block starting at `offset` (512 bytes required).
///
/// Complexity: O(1).
pub fn uf2_block_parse_at(data: &Vec[UInt8], offset: Int) -> Result[Uf2Block, Uf2Error] {
  return _block_at(data, offset);
}

/// Validate one block without exposing the parsed value.
///
/// Complexity: O(1).
pub fn uf2_block_validate(bytes: &Vec[UInt8]) -> Result[Unit, Uf2Error] {
  let r = uf2_block_parse(bytes);
  if !r.is_ok { return Err(r.error); }
  return Ok(());
}

/// True when the first eight bytes carry both start magics (the upstream
/// `is_uf2` rule; a truncated/foreign file is false).
///
/// Complexity: O(1).
pub fn uf2_block_is_uf2(bytes: &Vec[UInt8]) -> Bool {
  if bytes.len() < 8 { return false; }
  return _u32(bytes, 0) == UF2_MAGIC_START0 && _u32(bytes, 4) == UF2_MAGIC_START1;
}

// =========================================================================
// Image build
// =========================================================================

/// Split `payload` into 256-byte UF2 blocks (the upstream converter default)
/// starting at `target_addr`.  A non-zero family_id sets the FAMILY_ID flag.
///
/// Complexity: O(payload).
pub fn uf2_image_build(payload: &Vec[UInt8], target_addr: Int, family_id: Int) -> Result[Vec[UInt8], Uf2Error] {
  return uf2_image_build_chunked(payload, target_addr, family_id, 256);
}

/// Split `payload` into blocks of at most `chunk_size` bytes (1..476).
/// Every block but the last carries exactly `chunk_size` bytes; the last
/// carries the remainder, so build/parse round-trips the payload exactly.
///
/// Complexity: O(payload).
pub fn uf2_image_build_chunked(payload: &Vec[UInt8], target_addr: Int, family_id: Int, chunk_size: Int) -> Result[Vec[UInt8], Uf2Error] {
  if payload.len() == 0 {
    return Err(_err(UF2_ERR_ARG, "image_build: empty payload"));
  }
  if chunk_size < 1 || chunk_size > UF2_MAX_PAYLOAD {
    return Err(_err(UF2_ERR_ARG, "image_build: chunk_size must be 1.." + _itoa(UF2_MAX_PAYLOAD)));
  }
  if !_family_ok(family_id) {
    return Err(_err(UF2_ERR_ARG, "image_build: family_id outside u32"));
  }
  if target_addr < 0 || target_addr > UF2_U32_MAX {
    return Err(_err(UF2_ERR_ARG, "image_build: target_addr outside u32"));
  }
  if payload.len() > UF2_U32_MAX - target_addr {
    return Err(_err(UF2_ERR_ARG, "image_build: payload overflows the 32-bit address space"));
  }
  var num_blocks = payload.len() / chunk_size;
  if payload.len() % chunk_size != 0 { num_blocks = num_blocks + 1; }

  var out: Vec[UInt8] = Vec[UInt8].new();
  var block_no = 0;
  var pos = 0;
  while block_no < num_blocks {
    var count = chunk_size;
    if payload.len() - pos < count { count = payload.len() - pos; }
    var chunk: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < count {
      chunk.push(payload[pos + i]);
      i = i + 1;
    }
    let br = uf2_block_build(&chunk, target_addr + pos, block_no, num_blocks, family_id);
    if !br.is_ok { return Err(br.error); }
    _append_vec(&mut out, &br.value);
    pos = pos + count;
    block_no = block_no + 1;
  }
  return Ok(out);
}

// =========================================================================
// Image parse / validate
// =========================================================================

/// Parse and validate a complete UF2 image.
///
/// Structural checks: length is a positive multiple of 512; every block is
/// valid; every block declares the file's block count; block numbers form a
/// complete 0..n-1 permutation (file order may differ); non-comment blocks
/// agree on family presence/value.  Payload is reconstructed in block-number
/// order and comment (NOFLASH) blocks are excluded.
///
/// Complexity: O(size).
pub fn uf2_image_parse(data: &Vec[UInt8]) -> Result[Uf2Image, Uf2Error] {
  if data.len() == 0 {
    return Err(_err(UF2_ERR_SIZE, "image_parse: empty file"));
  }
  if data.len() % UF2_BLOCK_SIZE != 0 {
    return Err(_err(UF2_ERR_SIZE, "image_parse: size " + _itoa(data.len()) + " is not a multiple of 512"));
  }
  let count = data.len() / UF2_BLOCK_SIZE;
  var blocks: Vec[Uf2Block] = Vec[Uf2Block].new();
  var seen: Vec[Int] = Vec[Int].with_len(count);
  var order: Vec[Int] = Vec[Int].with_len(count);
  var family_seen = false;
  var have_family = false;
  var family_id = 0;

  var i = 0;
  while i < count {
    let br = _block_at(data, i * UF2_BLOCK_SIZE);
    if !br.is_ok {
      return Err(_err(br.error.kind, "block " + _itoa(i) + ": " + br.error.message));
    }
    let bn = br.value.block_no;
    let nb = br.value.num_blocks;
    if nb != count {
      return Err(_err(UF2_ERR_INDEX, "block " + _itoa(i) + ": declares num_blocks " + _itoa(nb) + ", file has " + _itoa(count)));
    }
    if seen[bn] != 0 {
      return Err(_err(UF2_ERR_INDEX, "image_parse: duplicate block number " + _itoa(bn)));
    }
    seen[bn] = 1;
    order[bn] = i;
    if !br.value.no_flash {
      if !family_seen {
        family_seen = true;
        have_family = br.value.has_family;
        family_id = br.value.family_id;
      } else {
        if have_family != br.value.has_family {
          return Err(_err(UF2_ERR_FAMILY, "image_parse: inconsistent family presence"));
        }
        if have_family && family_id != br.value.family_id {
          return Err(_err(UF2_ERR_FAMILY, "image_parse: mixed family IDs " + _itoa(family_id) + " and " + _itoa(br.value.family_id)));
        }
      }
    }
    blocks.push(br.value);
    i = i + 1;
  }

  var k = 0;
  while k < count {
    if seen[k] == 0 {
      return Err(_err(UF2_ERR_INDEX, "image_parse: missing block number " + _itoa(k)));
    }
    k = k + 1;
  }

  var payload: Vec[UInt8] = Vec[UInt8].new();
  var data_bytes = 0;
  var target_addr = 0;
  var have_flash = false;
  var contiguous = true;
  var prev_end = 0;
  var file_container = false;

  k = 0;
  while k < count {
    let idx = order[k];
    if !blocks[idx].no_flash {
      if !have_flash {
        have_flash = true;
        target_addr = blocks[idx].target_addr;
      } else {
        if contiguous && blocks[idx].target_addr != prev_end { contiguous = false; }
      }
      if blocks[idx].file_container { file_container = true; }
      _append_vec(&mut payload, &blocks[idx].payload);
      data_bytes = data_bytes + blocks[idx].payload_size;
      prev_end = blocks[idx].target_addr + blocks[idx].payload_size;
    }
    k = k + 1;
  }

  return Ok(Uf2Image{
    blocks: blocks;
    num_blocks: count;
    family_id: family_id;
    has_family: have_family;
    payload: payload;
    data_bytes: data_bytes;
    target_addr: target_addr;
    contiguous: contiguous;
    file_container: file_container;
  });
}

/// Validate a complete UF2 image without returning it.
///
/// Complexity: O(size).
pub fn uf2_image_validate(data: &Vec[UInt8]) -> Result[Unit, Uf2Error] {
  let r = uf2_image_parse(data);
  if !r.is_ok { return Err(r.error); }
  return Ok(());
}

/// Reconstruct the flashable payload of a valid image (comment blocks are
/// excluded; block order is normalized).
///
/// Complexity: O(size).
pub fn uf2_image_payload(data: &Vec[UInt8]) -> Result[Vec[UInt8], Uf2Error] {
  let r = uf2_image_parse(data);
  if !r.is_ok { return Err(r.error); }
  return Ok(r.value.payload);
}

// =========================================================================
// Catalogs
// =========================================================================

/// Upstream short name for a family ID, or "unknown".
///
/// Complexity: O(1).
pub fn uf2_family_name(family_id: Int) -> Str {
  if family_id == UF2_FAMILY_RP2040 { return "RP2040"; }
  if family_id == UF2_FAMILY_RP2XXX_ABSOLUTE { return "RP2XXX_ABSOLUTE"; }
  if family_id == UF2_FAMILY_RP2XXX_DATA { return "RP2XXX_DATA"; }
  if family_id == UF2_FAMILY_RP2350_ARM_S { return "RP2350_ARM_S"; }
  if family_id == UF2_FAMILY_RP2350_RISCV { return "RP2350_RISCV"; }
  if family_id == UF2_FAMILY_RP2350_ARM_NS { return "RP2350_ARM_NS"; }
  if family_id == UF2_FAMILY_SAMD21 { return "SAMD21"; }
  if family_id == UF2_FAMILY_SAMD51 { return "SAMD51"; }
  return "unknown";
}

/// Human-readable flag list ("NONE" for zero).
///
/// Complexity: O(1).
pub fn uf2_flags_name(flags: Int) -> Str {
  if flags == 0 { return "NONE"; }
  var out = "";
  if (flags & UF2_FLAG_NOFLASH) != 0 { out = out + "NOFLASH"; }
  if (flags & UF2_FLAG_FILECONTAINER) != 0 {
    if out.len() > 0 { out = out + "|"; }
    out = out + "FILECONTAINER";
  }
  if (flags & UF2_FLAG_FAMILY_ID) != 0 {
    if out.len() > 0 { out = out + "|"; }
    out = out + "FAMILY_ID";
  }
  if (flags & UF2_FLAG_MD5_CHKSUM) != 0 {
    if out.len() > 0 { out = out + "|"; }
    out = out + "MD5_CHKSUM";
  }
  if (flags & UF2_FLAG_EXTENSION_TAGS) != 0 {
    if out.len() > 0 { out = out + "|"; }
    out = out + "EXTENSION_TAGS";
  }
  if out.len() == 0 { return "RESERVED"; }
  return out;
}

/// Name of an error kind ("unknown" for out-of-range values).
///
/// Complexity: O(1).
pub fn uf2_error_kind_name(kind: Int) -> Str {
  if kind == UF2_ERR_ARG { return "ARG"; }
  if kind == UF2_ERR_SIZE { return "SIZE"; }
  if kind == UF2_ERR_MAGIC { return "MAGIC"; }
  if kind == UF2_ERR_PAYLOAD { return "PAYLOAD"; }
  if kind == UF2_ERR_INDEX { return "INDEX"; }
  if kind == UF2_ERR_FLAGS { return "FLAGS"; }
  if kind == UF2_ERR_FAMILY { return "FAMILY"; }
  if kind == UF2_ERR_IO { return "IO"; }
  if kind == UF2_ERR_MOUNT { return "MOUNT"; }
  if kind == UF2_ERR_VERIFY { return "VERIFY"; }
  return "unknown";
}

/// Name of a flash status ("unknown" for out-of-range values).
///
/// Complexity: O(1).
pub fn uf2_flash_status_name(status: Int) -> Str {
  if status == UF2_FLASH_SKIP { return "SKIP"; }
  if status == UF2_FLASH_COMPLETE { return "COMPLETE"; }
  if status == UF2_FLASH_COPIED { return "COPIED"; }
  return "unknown";
}

// =========================================================================
// Flash-to-mount
// =========================================================================

/// True when `mount_dir` is a directory carrying the BOOTSEL info file.
///
/// Complexity: O(1).
pub fn uf2_mount_is_bootsel(mount_dir: Str) -> Bool {
  if mount_dir.len() == 0 { return false; }
  if !fs.fs_is_dir(mount_dir) { return false; }
  return fs.fs_exists(io.join_paths(mount_dir, UF2_INFO_FILE));
}

/// True when `mount_dir` exists and is a directory (volume present).
///
/// Complexity: O(1).
pub fn uf2_mount_present(mount_dir: Str) -> Bool {
  if mount_dir.len() == 0 { return false; }
  return fs.fs_is_dir(mount_dir);
}

/// Base name of a path, accepting both `\` and `/` separators.
///
/// Complexity: O(path).
pub fn uf2_basename(path: Str) -> Str {
  return _basename(path);
}

/// Wait for the board to reboot after a copy: COMPLETE as soon as the
/// destination file or the mount directory disappears, COPIED if the
/// volume is still mounted when `timeout_ms` expires (timeout 0 returns
/// COPIED immediately).  Polls every `poll_ms` milliseconds.
///
/// Complexity: O(timeout / poll).
pub fn uf2_flash_wait_complete(dest_path: Str, mount_dir: Str, timeout_ms: Int, poll_ms: Int) -> Result[Int, Uf2Error] {
  if dest_path.len() == 0 {
    return Err(_err(UF2_ERR_ARG, "flash_wait: empty destination path"));
  }
  if timeout_ms < 0 {
    return Err(_err(UF2_ERR_ARG, "flash_wait: timeout_ms must be >= 0"));
  }
  if timeout_ms > 0 && poll_ms < 1 {
    return Err(_err(UF2_ERR_ARG, "flash_wait: poll_ms must be >= 1"));
  }
  if !fs.fs_exists(dest_path) { return Ok(UF2_FLASH_COMPLETE); }
  if mount_dir.len() > 0 && !fs.fs_is_dir(mount_dir) { return Ok(UF2_FLASH_COMPLETE); }
  if timeout_ms == 0 { return Ok(UF2_FLASH_COPIED); }

  let start = io.time_now();
  var now = start;
  while now - start < timeout_ms {
    if !fs.fs_exists(dest_path) { return Ok(UF2_FLASH_COMPLETE); }
    if mount_dir.len() > 0 && !fs.fs_is_dir(mount_dir) { return Ok(UF2_FLASH_COMPLETE); }
    io.sleep(poll_ms);
    now = io.time_now();
  }
  return Ok(UF2_FLASH_COPIED);
}

/// Flash a UF2 image to a mounted BOOTSEL volume.
///
/// The source is read as binary, validated as a complete UF2 image, written
/// to `<mount_dir>/<basename(source)>` with binary I/O, read back and
/// compared byte-for-byte, then completion is awaited (see
/// `uf2_flash_wait_complete`).  A missing mount directory is the SKIP path:
/// Ok with status UF2_FLASH_SKIP.  `fs_copy` is deliberately NOT used (it is
/// text-mode and would corrupt binary data).
///
/// Complexity: O(size + timeout / poll).
pub fn uf2_flash_to_mount(source_path: Str, mount_dir: Str, timeout_ms: Int, poll_ms: Int) -> Result[Uf2FlashResult, Uf2Error] {
  if source_path.len() == 0 {
    return Err(_err(UF2_ERR_ARG, "flash: empty source path"));
  }
  if mount_dir.len() == 0 {
    return Err(_err(UF2_ERR_ARG, "flash: empty mount path"));
  }
  if timeout_ms < 0 {
    return Err(_err(UF2_ERR_ARG, "flash: timeout_ms must be >= 0"));
  }
  if timeout_ms > 0 && poll_ms < 1 {
    return Err(_err(UF2_ERR_ARG, "flash: poll_ms must be >= 1"));
  }
  if !fs.fs_is_dir(mount_dir) {
    return Ok(Uf2FlashResult{
      status: UF2_FLASH_SKIP;
      source_path: source_path;
      dest_path: "";
      source_bytes: 0;
      copied_bytes: 0;
      blocks: 0;
      verified: false;
      elapsed_ms: 0;
      detail: "no mount/volume present";
    });
  }

  let read = _file_bytes(source_path);
  if !read.is_ok {
    return Err(_err(UF2_ERR_IO, "flash: cannot read source: " + read.error));
  }
  let data: Vec[UInt8] = read.value;
  if data.len() % UF2_BLOCK_SIZE != 0 {
    return Err(_err(UF2_ERR_SIZE, "flash: source size " + _itoa(data.len()) + " is not a multiple of 512"));
  }
  let parsed = uf2_image_parse(&data);
  if !parsed.is_ok {
    return Err(_err(parsed.error.kind, "flash: source invalid: " + parsed.error.message));
  }

  let name = _basename(source_path);
  if name.len() == 0 {
    return Err(_err(UF2_ERR_ARG, "flash: source path has no file name"));
  }
  let dest = io.join_paths(mount_dir, name);
  let started = io.time_now();

  let wr = fs.fs_write(dest, &data);
  if !wr.is_ok {
    return Err(_err(UF2_ERR_IO, "flash: cannot write " + dest + ": " + wr.error));
  }

  // The bootloader may reset as soon as the file is closed.  A volume that
  // disappears here is completion, not a write failure.
  if !fs.fs_exists(dest) || !fs.fs_is_dir(mount_dir) {
    return Ok(_flash_complete_unverified(source_path, dest, data.len(), parsed.value.num_blocks, io.time_now() - started));
  }

  let back_sz = fs.fs_size(dest);
  if !back_sz.is_ok {
    if !fs.fs_exists(dest) || !fs.fs_is_dir(mount_dir) {
      return Ok(_flash_complete_unverified(source_path, dest, data.len(), parsed.value.num_blocks, io.time_now() - started));
    }
    return Err(_err(UF2_ERR_VERIFY, "flash: cannot stat the written file: " + back_sz.error));
  }
  if back_sz.value != data.len() {
    if !fs.fs_exists(dest) || !fs.fs_is_dir(mount_dir) {
      return Ok(_flash_complete_unverified(source_path, dest, data.len(), parsed.value.num_blocks, io.time_now() - started));
    }
    return Err(_err(UF2_ERR_VERIFY, "flash: written size " + _itoa(back_sz.value) + " != " + _itoa(data.len())));
  }
  let back = fs.fs_read_range(dest, 0, data.len());
  if !back.is_ok {
    if !fs.fs_exists(dest) || !fs.fs_is_dir(mount_dir) {
      return Ok(_flash_complete_unverified(source_path, dest, data.len(), parsed.value.num_blocks, io.time_now() - started));
    }
    return Err(_err(UF2_ERR_VERIFY, "flash: cannot read back the written file: " + back.error));
  }
  if !_bytes_equal(&back.value, &data) {
    if !fs.fs_exists(dest) || !fs.fs_is_dir(mount_dir) {
      return Ok(_flash_complete_unverified(source_path, dest, data.len(), parsed.value.num_blocks, io.time_now() - started));
    }
    return Err(_err(UF2_ERR_VERIFY, "flash: read-back differs from the source"));
  }

  let wait = uf2_flash_wait_complete(dest, mount_dir, timeout_ms, poll_ms);
  if !wait.is_ok {
    return Err(wait.error);
  }
  let status = wait.value;
  let elapsed = io.time_now() - started;
  var detail = "volume still mounted after the wait";
  if status == UF2_FLASH_COMPLETE { detail = "volume/file disappeared (board rebooted)"; }
  return Ok(Uf2FlashResult{
    status: status;
    source_path: source_path;
    dest_path: dest;
    source_bytes: data.len();
    copied_bytes: data.len();
    blocks: parsed.value.num_blocks;
    verified: true;
    elapsed_ms: elapsed;
    detail: detail;
  });
}
