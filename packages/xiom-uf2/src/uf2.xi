// XIOM -- xiom.uf2: USB Flashing Format (UF2) codec and host-side flashing
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no vendored runtime) implementation of the UF2 format used by
// Microsoft MakeCode and by MCU bootloaders (RP2040/RP2350 BOOTSEL, SAMD21,
// SAMD51):
//
//   * uf2_block_parse / uf2_block_parse_at -- validate and decode one
//     512-byte block (three magic words, flags, target address, payload
//     size, block number/count, family ID field and the trailing magic);
//   * uf2_block_build -- emit one canonical 512-byte block, zero-padding
//     the 476-byte payload area;
//   * uf2_image_build / uf2_image_build_ex -- split a byte image into
//     blocks at a caller-chosen payload size and write a complete UF2 file;
//   * uf2_image_parse -- validate a whole file (size multiple, per-block
//     checks, block numbering complete and unique, consistent family ID),
//     order blocks by block number and concatenate their payloads;
//   * uf2_flash_to_mount -- copy a UF2 image to a mounted BOOTSEL volume
//     after detecting it through INFO_UF2.TXT, with a typed SKIP outcome
//     when no volume is mounted;
//   * uf2_flash_wait -- completion detection: poll until the volume
//     disappears (the bootloader consumed the file and rebooted) or the
//     timeout expires.
//
// The format is the one documented by microsoft/uf2 (README.md, commit
// 90e9741f217f5a40c98ba74d663e408041037578, MIT); see SPEC.md and
// PROVENANCE.md for the pinned layout, the family-ID table and the exact
// validation order. Nothing from upstream is vendored: only the public
// format specification is implemented.
//
// v0.64.7 notes that shaped this module:
//   * free functions only; Ok/Err values are constructed only in the leaf
//     helpers below (one helper per result payload type).
//   * every byte read out of Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before entering arithmetic.
//   * there are no bit shifts: flag tests use division/modulo by the
//     power-of-two flag value, and LE32 writes use division/modulo by
//     256/65536/16777216.
//   * no `==` on Str values anywhere in this module.
//   * callers should bind a Result payload to a local before reading its
//     fields (the tests follow this).

module xiom.uf2

use xiom.io.fs;
use xiom.time;

// --------------------------------------------------
//  Format constants
// --------------------------------------------------

/// First magic word of every UF2 block ("UF2\n" as little-endian bytes
/// 55 46 32 0A).
pub const UF2_MAGIC_START0: Int = 0x0A324655;

/// Second magic word of every UF2 block (randomly selected upstream).
pub const UF2_MAGIC_START1: Int = 0x9E5D5157;

/// Trailing magic word of every UF2 block (bytes 30 6F B1 0A).
pub const UF2_MAGIC_END: Int = 0x0AB16F30;

/// Size of one UF2 block in bytes.
pub const UF2_BLOCK_SIZE: Int = 512;

/// Size of the fixed block header in bytes.
pub const UF2_HEADER_SIZE: Int = 32;

/// Maximum number of payload bytes in one block (512 - 32 - 4).
pub const UF2_PAYLOAD_MAX: Int = 476;

/// Default payload size used by uf2_image_build (always a multiple of 4).
pub const UF2_DEFAULT_PAYLOAD_SIZE: Int = 256;

/// Flag 0x00000001: the block is a comment and must not be written to the
/// main flash.
pub const UF2_FLAG_NOT_MAIN_FLASH: Int = 0x00000001;

/// Flag 0x00001000: the block belongs to a file container.
pub const UF2_FLAG_FILE_CONTAINER: Int = 0x00001000;

/// Flag 0x00002000: the fileSize/familyID field holds a board family ID.
pub const UF2_FLAG_FAMILY_ID: Int = 0x00002000;

/// Flag 0x00004000: the last 24 payload bytes hold an MD5 checksum record.
pub const UF2_FLAG_MD5: Int = 0x00004000;

/// Flag 0x00008000: extension tags follow the payload.
pub const UF2_FLAG_EXTENSION_TAGS: Int = 0x00008000;

/// Union of the five flags defined by the upstream format.
pub const UF2_FLAG_ALL: Int = 0x0000F001;

// Family IDs from microsoft/uf2 utils/uf2families.json at the pinned commit.
pub const UF2_FAMILY_RP2040: Int = 0xE48BFF56;
pub const UF2_FAMILY_RP2350_ARM_S: Int = 0xE48BFF59;
pub const UF2_FAMILY_RP2350_RISCV: Int = 0xE48BFF5A;
pub const UF2_FAMILY_RP2350_ARM_NS: Int = 0xE48BFF5B;
pub const UF2_FAMILY_SAMD21: Int = 0x68ED2B88;
pub const UF2_FAMILY_SAMD51: Int = 0x55114460;

/// Number of family IDs in the documented subset.
pub const UF2_FAMILY_COUNT: Int = 6;

/// Flash outcome: the image was copied and the volume had already
/// disappeared (the bootloader consumed it and rebooted).
pub const UF2_FLASH_DONE: Int = 0;

/// Flash outcome: the image was copied but the volume is still mounted.
pub const UF2_FLASH_COPIED: Int = 1;

/// Flash outcome: no UF2 volume was mounted, so nothing was written.
pub const UF2_FLASH_SKIPPED: Int = 2;

/// Largest u32 value carried by an Int field.
pub const UF2_U32_MAX: Int = 4294967295;

// Typed error codes (stable; the message carries the human-readable detail).
pub const UF2_ERR_BLOCK_SIZE: Int = 1;
pub const UF2_ERR_MAGIC_START0: Int = 2;
pub const UF2_ERR_MAGIC_START1: Int = 3;
pub const UF2_ERR_MAGIC_END: Int = 4;
pub const UF2_ERR_PAYLOAD_SIZE: Int = 5;
pub const UF2_ERR_BLOCK_NUMBER: Int = 6;
pub const UF2_ERR_BLOCK_COUNT: Int = 7;
pub const UF2_ERR_FAMILY_ID: Int = 8;
pub const UF2_ERR_IMAGE_EMPTY: Int = 9;
pub const UF2_ERR_MISSING_BLOCK: Int = 10;
pub const UF2_ERR_DUPLICATE_BLOCK: Int = 11;
pub const UF2_ERR_ADDRESS: Int = 12;
pub const UF2_ERR_FLAGS: Int = 13;
pub const UF2_ERR_MOUNT: Int = 20;
pub const UF2_ERR_FILENAME: Int = 21;
pub const UF2_ERR_ARGUMENT: Int = 22;
pub const UF2_ERR_IO: Int = 23;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A typed UF2 error.
///
/// `code` is one of the UF2_ERR_* constants, `offset` is the byte position
/// of the offending field in the parsed buffer (-1 for scalar-argument and
/// host-I/O errors) and `message` is a stable lowercase "uf2: ..." detail.
pub type Uf2Error = {
  code: Int;
  offset: Int;
  message: Str;
}

/// One decoded UF2 block.
///
/// `family_id` is the raw value of the eighth header word. It is the board
/// family ID only when `family_id_present` is true (the UF2_FLAG_FAMILY_ID
/// bit is set); otherwise the same word is a file size in the upstream
/// format and is exposed unchanged. `payload` holds exactly `payload_size`
/// bytes (never the 476-byte zero padding).
pub type Uf2Block = {
  flags: Int;
  target_address: Int;
  payload_size: Int;
  block_no: Int;
  num_blocks: Int;
  family_id: Int;
  family_id_present: Bool;
  payload: Vec[UInt8];
}

/// A decoded UF2 image.
///
/// `blocks` is ordered by `block_no` (0..block_count-1) regardless of the
/// order the blocks appeared in the file. `data` is the concatenation of
/// every payload in that same order; it includes any zero padding the
/// producer wrote into the last block. `base_address` is the target address
/// of block 0 and `payload_bytes` is the sum of all payload sizes.
pub type Uf2Image = {
  blocks: Vec[Uf2Block];
  data: Vec[UInt8];
  block_count: Int;
  family_id: Int;
  family_id_present: Bool;
  base_address: Int;
  payload_bytes: Int;
}

/// A validated plan for copying an image to a mounted volume.
///
/// `volume_present` is the INFO_UF2.TXT detection result at plan time;
/// `bytes` is the UF2 file size (block_count * 512).
pub type Uf2FlashPlan = {
  mount: Str;
  filename: Str;
  target_path: Str;
  volume_present: Bool;
  block_count: Int;
  bytes: Int;
  family_id: Int;
  family_id_present: Bool;
}

/// The outcome of uf2_flash_to_mount.
///
/// `status` is UF2_FLASH_DONE, UF2_FLASH_COPIED or UF2_FLASH_SKIPPED.
/// `bytes_written` is 0 on SKIP. `volume_present` is the detection result
/// after the write (always false on DONE, true on COPIED).
pub type Uf2FlashOutcome = {
  status: Int;
  mount: Str;
  target_path: Str;
  bytes_written: Int;
  block_count: Int;
  volume_present: Bool;
}

/// The outcome of uf2_flash_wait.
///
/// `completed` is true when the volume disappeared while polling (the
/// bootloader rebooted). `waited_ms` is the elapsed monotonic time and
/// `polls` the number of volume probes performed; `volume_present` is the
/// final probe result.
pub type Uf2FlashWait = {
  completed: Bool;
  waited_ms: Int;
  polls: Int;
  volume_present: Bool;
}

// --------------------------------------------------
//  Result constructors (one leaf per payload type)
// --------------------------------------------------

fn _ok_block(v: Uf2Block) -> Result[Uf2Block, Uf2Error] {
  return Ok(v);
}

fn _err_block(code: Int, offset: Int, message: Str) -> Result[Uf2Block, Uf2Error] {
  return Err(Uf2Error{ code: code; offset: offset; message: message; });
}

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Uf2Error] {
  return Ok(v);
}

fn _err_bytes(code: Int, offset: Int, message: Str) -> Result[Vec[UInt8], Uf2Error] {
  return Err(Uf2Error{ code: code; offset: offset; message: message; });
}

fn _ok_image(v: Uf2Image) -> Result[Uf2Image, Uf2Error] {
  return Ok(v);
}

fn _err_image(code: Int, offset: Int, message: Str) -> Result[Uf2Image, Uf2Error] {
  return Err(Uf2Error{ code: code; offset: offset; message: message; });
}

fn _ok_plan(v: Uf2FlashPlan) -> Result[Uf2FlashPlan, Uf2Error] {
  return Ok(v);
}

fn _err_plan(code: Int, offset: Int, message: Str) -> Result[Uf2FlashPlan, Uf2Error] {
  return Err(Uf2Error{ code: code; offset: offset; message: message; });
}

fn _ok_outcome(v: Uf2FlashOutcome) -> Result[Uf2FlashOutcome, Uf2Error] {
  return Ok(v);
}

fn _err_outcome(code: Int, offset: Int, message: Str) -> Result[Uf2FlashOutcome, Uf2Error] {
  return Err(Uf2Error{ code: code; offset: offset; message: message; });
}

fn _ok_wait(v: Uf2FlashWait) -> Result[Uf2FlashWait, Uf2Error] {
  return Ok(v);
}

fn _err_wait(code: Int, offset: Int, message: Str) -> Result[Uf2FlashWait, Uf2Error] {
  return Err(Uf2Error{ code: code; offset: offset; message: message; });
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Little-endian UInt32 at `off` as an Int (0..2^32-1); callers guarantee
// that off + 3 is inside the buffer.
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256 + _byte(data, off + 2) * 65536 + _byte(data, off + 3) * 16777216;
}

// Append `v` (0..2^32-1) as four little-endian bytes.
fn _push_le32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// Append `count` zero bytes.
fn _push_zero(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Append every byte of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// True when the power-of-two `flag` is set in `flags` (0..2^32-1).
// Division instead of a shift keeps sign-bit-set values harmless.
fn _flag_set(flags: Int, flag: Int) -> Bool {
  if flag <= 0 {
    return false;
  }
  return ((flags / flag) % 2) == 1;
}

// True when the byte at `i` of `s` is a slash or a backslash.
fn _is_separator(s: Str, i: Int) -> Bool {
  let b = s.byte_at(i);
  if b == 47 {
    return true;
  }
  if b == 92 {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Public API -- block parsing
// --------------------------------------------------

/// Parse exactly one 512-byte UF2 block.
///
/// The buffer must be exactly UF2_BLOCK_SIZE bytes; use uf2_block_parse_at
/// for a block inside a larger image. Validation order: block size, first
/// magic, second magic, trailing magic, payload size <= 476, non-zero
/// block count, block number < block count.
///
/// Params: data - the 512 block bytes, read only.
/// Returns: Ok(Uf2Block) with the payload copied out and padding dropped.
/// Error case: the typed UF2_ERR_* catalog in SPEC.md.
/// Complexity: O(512).
pub fn uf2_block_parse(data: &Vec[UInt8]) -> Result[Uf2Block, Uf2Error]
  ensures: data.len() != 512 => result is Err;
  ensures: result is Ok => data.len() == 512;
{
  if data.len() != UF2_BLOCK_SIZE {
    return _err_block(UF2_ERR_BLOCK_SIZE, data.len(), "uf2: block size");
  }
  return uf2_block_parse_at(data, 0);
}

/// Parse one 512-byte UF2 block starting at `offset`.
///
/// `offset` must be non-negative and `offset + 512` must not exceed the
/// buffer length; bytes outside the block are ignored. Field offsets in
/// errors are absolute positions in `data`.
///
/// Params: data - the image bytes, read only; offset - the block start.
/// Returns: Ok(Uf2Block) for a structurally valid block.
/// Error case: UF2_ERR_ARGUMENT for a negative offset, then the same
/// catalog as uf2_block_parse.
/// Complexity: O(512).
pub fn uf2_block_parse_at(data: &Vec[UInt8], offset: Int) -> Result[Uf2Block, Uf2Error]
  ensures: offset < 0 => result is Err;
  ensures: offset >= 0 && offset + 512 > data.len() => result is Err;
  ensures: result is Ok => offset >= 0 && offset + 512 <= data.len();
{
  if offset < 0 {
    return _err_block(UF2_ERR_ARGUMENT, 0, "uf2: negative offset");
  }
  if offset + UF2_BLOCK_SIZE > data.len() {
    return _err_block(UF2_ERR_BLOCK_SIZE, data.len(), "uf2: block size");
  }
  if _le32(data, offset) != UF2_MAGIC_START0 {
    return _err_block(UF2_ERR_MAGIC_START0, offset, "uf2: bad start magic 0");
  }
  if _le32(data, offset + 4) != UF2_MAGIC_START1 {
    return _err_block(UF2_ERR_MAGIC_START1, offset + 4, "uf2: bad start magic 1");
  }
  if _le32(data, offset + 508) != UF2_MAGIC_END {
    return _err_block(UF2_ERR_MAGIC_END, offset + 508, "uf2: bad end magic");
  }
  let flags: Int = _le32(data, offset + 8);
  let address: Int = _le32(data, offset + 12);
  let payload_size: Int = _le32(data, offset + 16);
  let block_no: Int = _le32(data, offset + 20);
  let num_blocks: Int = _le32(data, offset + 24);
  let field7: Int = _le32(data, offset + 28);
  if payload_size > UF2_PAYLOAD_MAX {
    return _err_block(UF2_ERR_PAYLOAD_SIZE, offset + 16, "uf2: payload size out of range");
  }
  if num_blocks == 0 {
    return _err_block(UF2_ERR_BLOCK_COUNT, offset + 24, "uf2: block count is zero");
  }
  if block_no >= num_blocks {
    return _err_block(UF2_ERR_BLOCK_NUMBER, offset + 20, "uf2: block number out of range");
  }
  var payload = Vec[UInt8].new();
  var i = 0;
  while i < payload_size {
    payload.push(data[offset + UF2_HEADER_SIZE + i]);
    i = i + 1;
  }
  let block = Uf2Block{
    flags: flags;
    target_address: address;
    payload_size: payload_size;
    block_no: block_no;
    num_blocks: num_blocks;
    family_id: field7;
    family_id_present: _flag_set(flags, UF2_FLAG_FAMILY_ID);
    payload: payload;
  };
  return _ok_block(block);
}

/// Build one canonical 512-byte UF2 block.
///
/// The payload is copied at offset 32 and the remaining bytes up to offset
/// 508 are zero, as required by the upstream layout. `family_id` is written
/// to the eighth header word; set UF2_FLAG_FAMILY_ID in `flags` (or use
/// uf2_block_build_family) when that word is a board family ID rather than
/// a file size. The builder accepts any flag bits in 0..2^32-1 and does not
/// interpret them.
///
/// Params: address - target address, 0..2^32-1; payload - at most 476
/// bytes; block_no - 0..num_blocks-1; num_blocks - 1..2^32-1; family_id -
/// the eighth header word, 0..2^32-1; flags - the flag word, 0..2^32-1.
/// Returns: Ok(512 bytes).
/// Error case: UF2_ERR_ADDRESS, UF2_ERR_PAYLOAD_SIZE, UF2_ERR_BLOCK_COUNT,
/// UF2_ERR_BLOCK_NUMBER, UF2_ERR_FAMILY_ID or UF2_ERR_FLAGS.
/// Complexity: O(512).
pub fn uf2_block_build(address: Int, payload: &Vec[UInt8], block_no: Int, num_blocks: Int, family_id: Int, flags: Int) -> Result[Vec[UInt8], Uf2Error]
  ensures: payload.len() > 476 => result is Err;
  ensures: result is Ok => result.value.len() == 512;
{
  if flags < 0 || flags > UF2_U32_MAX {
    return _err_bytes(UF2_ERR_FLAGS, 8, "uf2: flags out of range");
  }
  if address < 0 || address > UF2_U32_MAX {
    return _err_bytes(UF2_ERR_ADDRESS, 12, "uf2: address out of range");
  }
  if payload.len() > UF2_PAYLOAD_MAX {
    return _err_bytes(UF2_ERR_PAYLOAD_SIZE, 16, "uf2: payload size out of range");
  }
  if num_blocks < 1 || num_blocks > UF2_U32_MAX {
    return _err_bytes(UF2_ERR_BLOCK_COUNT, 24, "uf2: block count out of range");
  }
  if block_no < 0 || block_no >= num_blocks {
    return _err_bytes(UF2_ERR_BLOCK_NUMBER, 20, "uf2: block number out of range");
  }
  if family_id < 0 || family_id > UF2_U32_MAX {
    return _err_bytes(UF2_ERR_FAMILY_ID, 28, "uf2: family id out of range");
  }
  var out = Vec[UInt8].new();
  _push_le32(&mut out, UF2_MAGIC_START0);
  _push_le32(&mut out, UF2_MAGIC_START1);
  _push_le32(&mut out, flags);
  _push_le32(&mut out, address);
  _push_le32(&mut out, payload.len());
  _push_le32(&mut out, block_no);
  _push_le32(&mut out, num_blocks);
  _push_le32(&mut out, family_id);
  _push_bytes(&mut out, payload);
  _push_zero(&mut out, UF2_PAYLOAD_MAX - payload.len());
  _push_le32(&mut out, UF2_MAGIC_END);
  return _ok_bytes(out);
}

/// Build one block with the UF2_FLAG_FAMILY_ID bit set.
///
/// Convenience wrapper over uf2_block_build: flags = UF2_FLAG_FAMILY_ID.
/// Params and errors match uf2_block_build.
pub fn uf2_block_build_family(address: Int, payload: &Vec[UInt8], block_no: Int, num_blocks: Int, family_id: Int) -> Result[Vec[UInt8], Uf2Error] {
  return uf2_block_build(address, payload, block_no, num_blocks, family_id, UF2_FLAG_FAMILY_ID);
}

/// True when the power-of-two `flag` bit is set in `flags`.
/// Complexity: O(1).
pub fn uf2_flags_have(flags: Int, flag: Int) -> Bool {
  return _flag_set(flags, flag);
}

/// True when `block` carries the power-of-two `flag` bit.
/// Complexity: O(1).
pub fn uf2_block_has_flag(block: &Uf2Block, flag: Int) -> Bool {
  return _flag_set(block.flags, flag);
}

// --------------------------------------------------
//  Public API -- image build and parse
// --------------------------------------------------

/// Build a complete UF2 image from `data` using 256-byte payloads.
///
/// Each block carries 256 payload bytes except possibly the last, which is
/// zero-padded to 256 so every block has the same payload size (matching
/// the upstream uf2conv padding policy). The UF2_FLAG_FAMILY_ID bit is set
/// when `family_id` is non-zero.
///
/// Params: base_address - target address of block 0, 0..2^32-1; data - the
/// image bytes, at least one byte; family_id - a UF2_FAMILY_* value or 0.
/// Returns: Ok(block_count * 512 bytes).
/// Error case: UF2_ERR_IMAGE_EMPTY, UF2_ERR_ADDRESS (including address
/// overflow) or UF2_ERR_FAMILY_ID; builder errors are propagated.
/// Complexity: O(data.len()).
pub fn uf2_image_build(base_address: Int, data: &Vec[UInt8], family_id: Int) -> Result[Vec[UInt8], Uf2Error] {
  return uf2_image_build_ex(base_address, data, UF2_DEFAULT_PAYLOAD_SIZE, family_id);
}

/// Build a complete UF2 image with a caller-chosen payload size.
///
/// `payload_size` must be in 1..476 and a multiple of 4 (the upstream
/// alignment rule for payload size and target address). Block count is
/// ceil(data.len() / payload_size); block i starts at
/// base_address + i * payload_size. The final block is zero-padded to
/// `payload_size`. The UF2_FLAG_FAMILY_ID bit is set when `family_id` is
/// non-zero.
///
/// Params: base_address - target address of block 0; data - at least one
/// byte; payload_size - 4..476, multiple of 4; family_id - family ID or 0.
/// Returns: Ok(block_count * 512 bytes).
/// Error case: UF2_ERR_IMAGE_EMPTY, UF2_ERR_PAYLOAD_SIZE, UF2_ERR_ADDRESS
/// (including address overflow) or UF2_ERR_FAMILY_ID.
/// Complexity: O(data.len()).
pub fn uf2_image_build_ex(base_address: Int, data: &Vec[UInt8], payload_size: Int, family_id: Int) -> Result[Vec[UInt8], Uf2Error]
  ensures: data.len() == 0 => result is Err;
  ensures: payload_size <= 0 || payload_size > 476 => result is Err;
  ensures: result is Ok => result.value.len() % 512 == 0;
{
  if data.len() == 0 {
    return _err_bytes(UF2_ERR_IMAGE_EMPTY, 0, "uf2: empty image");
  }
  if payload_size <= 0 || payload_size > UF2_PAYLOAD_MAX {
    return _err_bytes(UF2_ERR_PAYLOAD_SIZE, 16, "uf2: payload size out of range");
  }
  if payload_size % 4 != 0 {
    return _err_bytes(UF2_ERR_PAYLOAD_SIZE, 16, "uf2: payload size not aligned");
  }
  if base_address < 0 || base_address > UF2_U32_MAX {
    return _err_bytes(UF2_ERR_ADDRESS, 12, "uf2: address out of range");
  }
  if family_id < 0 || family_id > UF2_U32_MAX {
    return _err_bytes(UF2_ERR_FAMILY_ID, 28, "uf2: family id out of range");
  }
  let n: Int = (data.len() + payload_size - 1) / payload_size;
  let last_address: Int = base_address + (n - 1) * payload_size;
  if last_address > UF2_U32_MAX {
    return _err_bytes(UF2_ERR_ADDRESS, 12, "uf2: address overflow");
  }
  var flags: Int = 0;
  if family_id != 0 {
    flags = UF2_FLAG_FAMILY_ID;
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    var chunk = Vec[UInt8].new();
    var j = 0;
    while j < payload_size {
      let src: Int = i * payload_size + j;
      if src < data.len() {
        chunk.push(data[src]);
      } else {
        chunk.push(0 as UInt8);
      }
      j = j + 1;
    }
    let address: Int = base_address + i * payload_size;
    let br = uf2_block_build(address, &chunk, i, n, family_id, flags);
    if !br.is_ok {
      let e: Uf2Error = br.error;
      let c: Int = e.code;
      let o: Int = e.offset;
      let m: Str = e.message;
      return _err_bytes(c, o, m);
    }
    let bb: Vec[UInt8] = br.value;
    _push_bytes(&mut out, &bb);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Parse and validate a complete UF2 image.
///
/// Requirements: a non-empty length that is a multiple of 512; every block
/// passes uf2_block_parse_at; every block reports the same num_blocks,
/// equal to the actual block count; block numbers 0..n-1 each appear
/// exactly once (file order is irrelevant); the UF2_FLAG_FAMILY_ID bit and
/// the family ID value agree across all blocks.
///
/// Params: data - the UF2 file bytes, read only.
/// Returns: Ok(Uf2Image) with blocks ordered by block number.
/// Error case: UF2_ERR_IMAGE_EMPTY, UF2_ERR_BLOCK_SIZE, the per-block
/// catalog, UF2_ERR_BLOCK_COUNT for a count mismatch, UF2_ERR_FAMILY_ID,
/// UF2_ERR_DUPLICATE_BLOCK or UF2_ERR_MISSING_BLOCK.
/// Complexity: O(n) for n = data.len() / 512.
pub fn uf2_image_parse(data: &Vec[UInt8]) -> Result[Uf2Image, Uf2Error]
  ensures: data.len() == 0 => result is Err;
  ensures: data.len() % 512 != 0 => result is Err;
{
  if data.len() == 0 {
    return _err_image(UF2_ERR_IMAGE_EMPTY, 0, "uf2: empty image");
  }
  if data.len() % UF2_BLOCK_SIZE != 0 {
    return _err_image(UF2_ERR_BLOCK_SIZE, data.len(), "uf2: image size");
  }
  let n: Int = data.len() / UF2_BLOCK_SIZE;
  var blocks = Vec[Uf2Block].new();
  var expected_family: Int = 0;
  var expected_present: Bool = false;
  var i = 0;
  while i < n {
    let off: Int = i * UF2_BLOCK_SIZE;
    let br = uf2_block_parse_at(data, off);
    if !br.is_ok {
      let e: Uf2Error = br.error;
      let c: Int = e.code;
      let o: Int = e.offset;
      let m: Str = e.message;
      return _err_image(c, o, m);
    }
    let b: Uf2Block = br.value;
    if b.num_blocks != n {
      return _err_image(UF2_ERR_BLOCK_COUNT, off + 24, "uf2: block count mismatch");
    }
    if i == 0 {
      expected_family = b.family_id;
      expected_present = b.family_id_present;
    } else {
      if b.family_id_present != expected_present {
        return _err_image(UF2_ERR_FAMILY_ID, off + 28, "uf2: inconsistent family id");
      }
      if expected_present {
        if b.family_id != expected_family {
          return _err_image(UF2_ERR_FAMILY_ID, off + 28, "uf2: inconsistent family id");
        }
      }
    }
    blocks.push(b);
    i = i + 1;
  }
  var order = Vec[Int].new();
  i = 0;
  while i < n {
    order.push(-1);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let bno: Int = blocks[i].block_no;
    let seen_at: Int = order[bno];
    if seen_at >= 0 {
      return _err_image(UF2_ERR_DUPLICATE_BLOCK, i * UF2_BLOCK_SIZE + 20, "uf2: duplicate block");
    }
    order[bno] = i;
    i = i + 1;
  }
  var pos = 0;
  while pos < n {
    if order[pos] < 0 {
      return _err_image(UF2_ERR_MISSING_BLOCK, pos * UF2_BLOCK_SIZE + 20, "uf2: missing block");
    }
    pos = pos + 1;
  }
  var ordered = Vec[Uf2Block].new();
  var all_data = Vec[UInt8].new();
  var payload_bytes: Int = 0;
  pos = 0;
  while pos < n {
    let idx: Int = order[pos];
    let b2: Uf2Block = blocks[idx];
    payload_bytes = payload_bytes + b2.payload_size;
    let p: Vec[UInt8] = b2.payload;
    var j = 0;
    while j < p.len() {
      all_data.push(p[j]);
      j = j + 1;
    }
    ordered.push(b2);
    pos = pos + 1;
  }
  let first: Uf2Block = ordered[0];
  let image = Uf2Image{
    blocks: ordered;
    data: all_data;
    block_count: n;
    family_id: first.family_id;
    family_id_present: first.family_id_present;
    base_address: first.target_address;
    payload_bytes: payload_bytes;
  };
  return _ok_image(image);
}

// --------------------------------------------------
//  Public API -- family IDs
// --------------------------------------------------

/// The documented family-ID subset, in table order:
/// RP2040, RP2350_ARM_S, RP2350_RISCV, RP2350_ARM_NS, SAMD21, SAMD51.
/// Complexity: O(1).
pub fn uf2_family_table() -> Vec[Int] {
  var t = Vec[Int].new();
  t.push(UF2_FAMILY_RP2040);
  t.push(UF2_FAMILY_RP2350_ARM_S);
  t.push(UF2_FAMILY_RP2350_RISCV);
  t.push(UF2_FAMILY_RP2350_ARM_NS);
  t.push(UF2_FAMILY_SAMD21);
  t.push(UF2_FAMILY_SAMD51);
  return t;
}

/// Number of family IDs in the documented subset (6).
/// Complexity: O(1).
pub fn uf2_family_count() -> Int {
  return UF2_FAMILY_COUNT;
}

/// Family ID at table index 0..5, or -1 when out of range.
/// Complexity: O(1).
pub fn uf2_family_id_at(index: Int) -> Int {
  let t = uf2_family_table();
  if index < 0 || index >= t.len() {
    return -1;
  }
  return t[index];
}

/// Stable family short name at table index 0..5, or "unknown" when out of
/// range. Complexity: O(1).
pub fn uf2_family_name_at(index: Int) -> Str {
  if index == 0 {
    return "RP2040";
  }
  if index == 1 {
    return "RP2350_ARM_S";
  }
  if index == 2 {
    return "RP2350_RISCV";
  }
  if index == 3 {
    return "RP2350_ARM_NS";
  }
  if index == 4 {
    return "SAMD21";
  }
  if index == 5 {
    return "SAMD51";
  }
  return "unknown";
}

/// Stable name for a family ID, or "unknown" when it is not in the
/// documented subset. Complexity: O(1).
pub fn uf2_family_name(id: Int) -> Str {
  if id == UF2_FAMILY_RP2040 {
    return "RP2040";
  }
  if id == UF2_FAMILY_RP2350_ARM_S {
    return "RP2350_ARM_S";
  }
  if id == UF2_FAMILY_RP2350_RISCV {
    return "RP2350_RISCV";
  }
  if id == UF2_FAMILY_RP2350_ARM_NS {
    return "RP2350_ARM_NS";
  }
  if id == UF2_FAMILY_SAMD21 {
    return "SAMD21";
  }
  if id == UF2_FAMILY_SAMD51 {
    return "SAMD51";
  }
  return "unknown";
}

/// True when `id` is in the documented family subset.
/// Complexity: O(1).
pub fn uf2_family_known(id: Int) -> Bool {
  let t = uf2_family_table();
  var i = 0;
  while i < t.len() {
    if t[i] == id {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Public API -- host flashing (BOOTSEL mount)
// --------------------------------------------------

/// Stable name for a flash outcome status: "done", "copied", "skipped" or
/// "unknown". Complexity: O(1).
pub fn uf2_flash_status_name(status: Int) -> Str {
  if status == UF2_FLASH_DONE {
    return "done";
  }
  if status == UF2_FLASH_COPIED {
    return "copied";
  }
  if status == UF2_FLASH_SKIPPED {
    return "skipped";
  }
  return "unknown";
}

/// Join a mount directory and a file name with '/', inserting one
/// separator unless `mount` already ends with '/' or '\\'. Returns
/// `filename` unchanged when `mount` is empty.
/// Complexity: O(mount.len() + filename.len()).
pub fn uf2_mount_join(mount: Str, filename: Str) -> Str {
  if mount.len() == 0 {
    return filename;
  }
  if _is_separator(mount, mount.len() - 1) {
    return mount + filename;
  }
  return mount + "/" + filename;
}

/// True when `filename` is a safe plain file name: 1..255 bytes, no '/'
/// or '\\' separator, and not "." or "..".
/// Complexity: O(filename.len()).
pub fn uf2_filename_valid(filename: Str) -> Bool {
  if filename.len() == 0 || filename.len() > 255 {
    return false;
  }
  if filename.len() == 1 {
    if filename.byte_at(0) == 46 {
      return false;
    }
  }
  if filename.len() == 2 {
    if filename.byte_at(0) == 46 && filename.byte_at(1) == 46 {
      return false;
    }
  }
  var i = 0;
  while i < filename.len() {
    if _is_separator(filename, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// True when `mount` is an existing directory containing INFO_UF2.TXT
/// (upper- or lower-case), the upstream detection rule for a UF2 MSC
/// volume. This performs host filesystem probes only.
/// Complexity: O(1) filesystem calls.
pub fn uf2_volume_present(mount: Str) -> Bool {
  if mount.len() == 0 {
    return false;
  }
  if !fs.fs_is_dir(mount) {
    return false;
  }
  if fs.fs_exists(uf2_mount_join(mount, "INFO_UF2.TXT")) {
    return true;
  }
  if fs.fs_exists(uf2_mount_join(mount, "info_uf2.txt")) {
    return true;
  }
  return false;
}

/// Validate an image and compute the copy plan for a mount.
///
/// The volume is probed but a missing volume is not an error: the plan
/// reports volume_present = false so the caller can classify the operation
/// as SKIP. The image itself must be valid, and `filename` must pass
/// uf2_filename_valid.
///
/// Params: mount - the mounted directory; image - UF2 file bytes;
/// filename - destination file name inside the volume.
/// Returns: Ok(Uf2FlashPlan).
/// Error case: UF2_ERR_MOUNT, UF2_ERR_FILENAME, then the uf2_image_parse
/// catalog.
/// Complexity: O(image.len()).
pub fn uf2_flash_plan(mount: Str, image: &Vec[UInt8], filename: Str) -> Result[Uf2FlashPlan, Uf2Error] {
  if mount.len() == 0 {
    return _err_plan(UF2_ERR_MOUNT, -1, "uf2: empty mount path");
  }
  if !uf2_filename_valid(filename) {
    return _err_plan(UF2_ERR_FILENAME, -1, "uf2: invalid filename");
  }
  let ir = uf2_image_parse(image);
  if !ir.is_ok {
    let e: Uf2Error = ir.error;
    let c: Int = e.code;
    let o: Int = e.offset;
    let m: Str = e.message;
    return _err_plan(c, o, m);
  }
  let img: Uf2Image = ir.value;
  let plan = Uf2FlashPlan{
    mount: mount;
    filename: filename;
    target_path: uf2_mount_join(mount, filename);
    volume_present: uf2_volume_present(mount);
    block_count: img.block_count;
    bytes: image.len();
    family_id: img.family_id;
    family_id_present: img.family_id_present;
  };
  return _ok_plan(plan);
}

/// Copy a UF2 image to a mounted UF2 volume.
///
/// The image is validated and the volume detected before any write. When
/// no volume is present the call returns Ok with status UF2_FLASH_SKIPPED
/// and writes nothing (the CI/host SKIP path). Otherwise the file is
/// written with fs_write, its size is verified against the image size, and
/// the volume is probed again: if it disappeared during the write the
/// bootloader has consumed the image and rebooted (UF2_FLASH_DONE), else
/// the result is UF2_FLASH_COPIED and the caller may poll with
/// uf2_flash_wait.
///
/// Params: mount - the mounted directory; image - UF2 file bytes;
/// filename - destination file name inside the volume.
/// Returns: Ok(Uf2FlashOutcome) including the SKIP outcome.
/// Error case: UF2_ERR_MOUNT, UF2_ERR_FILENAME, the image catalog and
/// UF2_ERR_IO (with the host message appended).
/// Complexity: O(image.len()).
pub fn uf2_flash_to_mount(mount: Str, image: &Vec[UInt8], filename: Str) -> Result[Uf2FlashOutcome, Uf2Error] {
  let pr = uf2_flash_plan(mount, image, filename);
  if !pr.is_ok {
    let e: Uf2Error = pr.error;
    let c: Int = e.code;
    let o: Int = e.offset;
    let m: Str = e.message;
    return _err_outcome(c, o, m);
  }
  let plan: Uf2FlashPlan = pr.value;
  if !plan.volume_present {
    let skipped = Uf2FlashOutcome{
      status: UF2_FLASH_SKIPPED;
      mount: plan.mount;
      target_path: plan.target_path;
      bytes_written: 0;
      block_count: plan.block_count;
      volume_present: false;
    };
    return _ok_outcome(skipped);
  }
  let wr = fs.fs_write(plan.target_path, image);
  if !wr.is_ok {
    let msg: Str = wr.error;
    return _err_outcome(UF2_ERR_IO, -1, "uf2: write failed: " + msg);
  }
  let szr = fs.fs_size(plan.target_path);
  if !szr.is_ok {
    let msg2: Str = szr.error;
    return _err_outcome(UF2_ERR_IO, -1, "uf2: stat failed: " + msg2);
  }
  let written: Int = szr.value;
  if written != image.len() {
    return _err_outcome(UF2_ERR_IO, -1, "uf2: short write");
  }
  let after: Bool = uf2_volume_present(plan.mount);
  var status: Int = UF2_FLASH_COPIED;
  if !after {
    status = UF2_FLASH_DONE;
  }
  let outcome = Uf2FlashOutcome{
    status: status;
    mount: plan.mount;
    target_path: plan.target_path;
    bytes_written: image.len();
    block_count: plan.block_count;
    volume_present: after;
  };
  return _ok_outcome(outcome);
}

/// Wait for flash completion by polling until the mounted volume
/// disappears, with a bounded timeout.
///
/// Call this after a UF2_FLASH_COPIED outcome. The volume disappearing is
/// the completion signal used by BOOTSEL bootloaders: the file has been
/// consumed and the board rebooted into the new firmware. A volume that is
/// already absent at entry counts as completed immediately.
///
/// Params: mount - the mounted directory; timeout_ms - total wait budget
/// (>= 0); poll_ms - delay between probes (> 0).
/// Returns: Ok(Uf2FlashWait) with completed, waited_ms, polls and the final
/// probe result. A timeout is not an error.
/// Error case: UF2_ERR_MOUNT for an empty mount, UF2_ERR_ARGUMENT for a
/// negative timeout or non-positive poll interval.
/// Complexity: O(timeout_ms / poll_ms) probes.
pub fn uf2_flash_wait(mount: Str, timeout_ms: Int, poll_ms: Int) -> Result[Uf2FlashWait, Uf2Error] {
  if mount.len() == 0 {
    return _err_wait(UF2_ERR_MOUNT, -1, "uf2: empty mount path");
  }
  if timeout_ms < 0 {
    return _err_wait(UF2_ERR_ARGUMENT, -1, "uf2: negative timeout");
  }
  if poll_ms <= 0 {
    return _err_wait(UF2_ERR_ARGUMENT, -1, "uf2: invalid poll interval");
  }
  let start: Int = time.monotonic_ms();
  var polls = 0;
  let max_polls: Int = timeout_ms / poll_ms + 2;
  while polls < max_polls {
    polls = polls + 1;
    if !uf2_volume_present(mount) {
      let now: Int = time.monotonic_ms();
      let done = Uf2FlashWait{
        completed: true;
        waited_ms: now - start;
        polls: polls;
        volume_present: false;
      };
      return _ok_wait(done);
    }
    let elapsed: Int = time.monotonic_ms() - start;
    if elapsed >= timeout_ms {
      break;
    }
    var nap: Int = poll_ms;
    let remaining: Int = timeout_ms - elapsed;
    if nap > remaining {
      nap = remaining;
    }
    if nap > 0 {
      time.sleep_ms(nap);
    }
  }
  let now: Int = time.monotonic_ms();
  let timed_out = Uf2FlashWait{
    completed: false;
    waited_ms: now - start;
    polls: polls;
    volume_present: true;
  };
  return _ok_wait(timed_out);
}
