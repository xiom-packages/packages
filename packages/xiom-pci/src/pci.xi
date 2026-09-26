// XIOM -- xiom.pci: PCI configuration-space codec (256-byte function space)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Port task: greenfield pure-XIOM port (no FFI) of a PCI config-space codec.
//
// Scope: decode the 256-byte PCI configuration space of one function:
// identification (vendor/device/class/revision), command/status words with
// bit predicates (IO/MEM/bus-master), the header type (bit 7 multi-function
// plus the documented header kinds 0x00/0x01/0x02), the type-0 BAR array
// with IO/memory decoding and address masking, the type-0 CardBus CIS /
// subsystem / expansion-ROM fields, the type-1 PCI-to-PCI bridge bus numbers
// and IO/memory/prefetchable windows with documented granularity, and the
// capability list walk (pointer chain with range/alignment checks, loop and
// duplicate detection, raw preservation of unknown capabilities). The
// builder emits a canonical type-0 header with no capability list.
//
// Non-goals (see SPEC.md): no OS/device IO, no MSI-X table parsing, no PCIe
// extended configuration space (bytes 256..4095), no class-code registry
// beyond the pci_class_name table, no CardBus (kind 0x02) register decoding,
// no 64-bit bridge window upper-register combination.
//
// Storage is flat: a parsed function keeps its 256 raw bytes plus three
// parallel capability columns (ids, offsets, spans) in walk order. Every
// scalar accessor decodes from the raw bytes on demand, so the only parallel
// columns are the capability columns, which are pushed together in one walk
// and whose lengths pci_cap_count defensively minimizes.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the leaf helpers below.
//   * every byte read is widened with `(v[pos] as Int) & 0xFF`; UInt8 values
//     are never compared against Int constants without widening.
//   * bit extraction is arithmetic (division and modulo), never shifts or
//     large masks: `&` on operands with bit 31 set miscompiles in this
//     compiler, so flag bits are stripped with `v - v % 16` / `v - v % 4`
//     and tested with `(v / p) % 2`.
//   * String values are only literals (class/capability/header-kind names);
//     the module performs no string equality.
//   * Vec parameters are bound to typed locals before use (never a `&f.raw`
//     field borrow), matching the gpt/aiff precedent.

module xiom.pci

const _PCI_SPACE: Int = 256;
const _PCI_BAR_COUNT: Int = 6;
const _PCI_CAP_ALIGN: Int = 4;
const _PCI_CAP_MIN: Int = 64;
const _PCI_CAP_MAX: Int = 255;
const _PCI_U8_MAX: Int = 255;
const _PCI_U16_MAX: Int = 65535;
const _PCI_U32_MAX: Int = 4294967295;
const _PCI_2P32: Int = 4294967296;
const _PCI_POW2_CAP: Int = 4611686018427387904;
const _PCI_IO_GRAN: Int = 4096;
const _PCI_MEM_GRAN: Int = 1048576;
const _PCI_ROM_GRAN: Int = 2048;

/// Parsed PCI function. `raw` holds the 256 configuration-space bytes exactly
/// as parsed; cap_ids/cap_offsets/cap_spans are the flat parallel capability
/// columns in walk order (one element per capability). Fields are
/// implementation details; callers should go through the free functions
/// below. A parsed function always has `raw.len() == 256`; all three
/// capability columns have the same length.
pub type PciFunction = {
  raw: Vec[UInt8];
  cap_ids: Vec[Int];
  cap_offsets: Vec[Int];
  cap_spans: Vec[Int];
}

/// Canonical type-0 builder input. Every field is the raw register value to
/// write (no masking is applied by the builder); `bars` must hold exactly six
/// 32-bit values for BAR0..BAR5, and `multifunction` drives header-type bit 7.
pub type PciType0Config = {
  vendor_id: Int;
  device_id: Int;
  command: Int;
  status: Int;
  revision_id: Int;
  prog_if: Int;
  subclass: Int;
  class_code: Int;
  cache_line_size: Int;
  latency_timer: Int;
  bist: Int;
  multifunction: Bool;
  bars: Vec[Int];
  cardbus_cis: Int;
  subsystem_vendor_id: Int;
  subsystem_device_id: Int;
  expansion_rom: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[PciFunction, Str].
fn _ok_fn(v: PciFunction) -> Result[PciFunction, Str] {
  return Ok(v);
}

// Err(m) for Result[PciFunction, Str].
fn _err_fn(m: Str) -> Result[PciFunction, Str] {
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

// --------------------------------------------------
//  Internal byte/bit helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _u8(v: &Vec[UInt8], pos: Int) -> Int {
  return (v[pos] as Int) & 0xFF;
}

// Little-endian UInt16 at `off` as an Int; callers guarantee the bounds.
fn _u16(v: &Vec[UInt8], off: Int) -> Int {
  return _u8(v, off) + _u8(v, off + 1) * 256;
}

// Little-endian UInt32 at `off` as an Int (0..2^32-1); callers guarantee the
// bounds.
fn _u32(v: &Vec[UInt8], off: Int) -> Int {
  return _u16(v, off) + _u16(v, off + 2) * 65536;
}

// Byte number `k` of `v` (0 = least significant) as a UInt8. Arithmetic only:
// exact for negative two's-complement values too (bson/tlv precedent).
fn _byte_at(v: Int, k: Int) -> UInt8 {
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
  return b as UInt8;
}

// Append the low `size` bytes of `v` in little-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_at(v, i));
    i = i + 1;
  }
}

// Append `count` zero bytes.
fn _push_zero(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// 2^k for k >= 0, by repeated multiplication (no shift operator).
fn _pow2(k: Int) -> Int {
  var p: Int = 1;
  var i = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// Bit `k` (0 = least significant) of a non-negative 16-bit word.
fn _bit16(v: Int, k: Int) -> Bool {
  let p: Int = _pow2(k);
  let q: Int = v / p;
  return q % 2 == 1;
}

// Header kind: the low seven bits of the header-type byte (bit 7 is the
// multi-function flag, see pci_multifunction).
fn _header_kind(header_type: Int) -> Int {
  if header_type >= 128 {
    return header_type - 128;
  }
  return header_type;
}

// Smallest power of two that divides `v`, for v != 0. Arithmetic only (no
// shifts): the loop doubles a trial divisor and tests `v % d == 0`, which is
// exact for negative two's-complement values as well. Capped at 2^62 so the
// test divisor never overflows a signed 64-bit Int; 0 maps to 0.
fn _lowest_bit(v: Int) -> Int {
  if v == 0 { return 0; }
  var a: Int = 1;
  while a < _PCI_POW2_CAP {
    let d: Int = a * 2;
    if v % d != 0 { return a; }
    a = d;
  }
  return a;
}

// True when `v` fits in an unsigned 8/16/32-bit field.
fn _byte_ok(v: Int) -> Bool {
  return v >= 0 && v <= _PCI_U8_MAX;
}

fn _word_ok(v: Int) -> Bool {
  return v >= 0 && v <= _PCI_U16_MAX;
}

fn _dword_ok(v: Int) -> Bool {
  return v >= 0 && v <= _PCI_U32_MAX;
}

// --------------------------------------------------
//  Internal BAR helpers
// --------------------------------------------------

// Raw 32-bit BAR slot `i` (no index guard; callers checked).
fn _bar_val(raw: &Vec[UInt8], i: Int) -> Int {
  return _u32(raw, 16 + i * 4);
}

// BAR flag bit 0: 0 = memory space, 1 = I/O space.
fn _bar_is_io_val(v: Int) -> Bool {
  return v % 2 == 1;
}

// Memory BAR type bits 1..2: 2 = 64-bit decode, 0 = 32-bit, 1/3 reserved.
fn _bar_is_64_val(v: Int) -> Bool {
  if _bar_is_io_val(v) { return false; }
  return (v / 2) % 4 == 2;
}

// True when slot `i` is the upper half of the 64-bit BAR in slot `i - 1`.
fn _bar_is_upper_of(raw: &Vec[UInt8], i: Int) -> Bool {
  if i < 1 { return false; }
  let prev: Int = _bar_val(raw, i - 1);
  return _bar_is_64_val(prev);
}

// Base address of slot `i` with the flag bits masked off. I/O BARs drop the
// low two bits (`v - v % 4`); memory BARs drop the low four bits
// (`v - v % 16`, covering the type and prefetchable bits). A 64-bit memory
// BAR adds the upper half from slot `i + 1` when that slot exists.
fn _bar_address_of(raw: &Vec[UInt8], i: Int) -> Int {
  let v: Int = _bar_val(raw, i);
  if _bar_is_io_val(v) {
    return v - v % 4;
  }
  if _bar_is_64_val(v) && i + 1 < _PCI_BAR_COUNT {
    let hi: Int = _bar_val(raw, i + 1);
    return (v - v % 16) + hi * _PCI_2P32;
  }
  return v - v % 16;
}

// True when `i` is a valid BAR slot for `f`'s header kind and `f` holds a
// full 256-byte space. Kind 0x00 owns slots 0..5, kind 0x01 slots 0..1
// (BAR0/BAR1; 0x18..0x27 are bridge registers), kind 0x02 slot 0 (the
// CardBus socket/ExCA base); any other kind has no decoded BARs.
fn _bar_ready(f: &PciFunction, i: Int) -> Bool {
  if i < 0 { return false; }
  if i >= _PCI_BAR_COUNT { return false; }
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return false; }
  let kind: Int = _header_kind(_u8(&raw, 14));
  if kind == 0 { return true; }
  if kind == 1 { return i < 2; }
  if kind == 2 { return i < 1; }
  return false;
}

// --------------------------------------------------
//  Internal capability helpers
// --------------------------------------------------

// First/next capability pointer rule: 0x40..0xFF and a multiple of 4.
fn _cap_ptr_ok(p: Int) -> Bool {
  if p < _PCI_CAP_MIN { return false; }
  if p > _PCI_CAP_MAX { return false; }
  return p % _PCI_CAP_ALIGN == 0;
}

// True when capability `i` exists and its recorded span covers `need` bytes
// starting at rel 0, wholly inside the 256-byte space, on a full raw buffer.
fn _cap_ready(f: &PciFunction, i: Int, need: Int) -> Bool {
  if i < 0 { return false; }
  if need < 1 { return false; }
  let offsets: Vec[Int] = f.cap_offsets;
  let spans: Vec[Int] = f.cap_spans;
  if i >= offsets.len() { return false; }
  if i >= spans.len() { return false; }
  let off: Int = offsets[i];
  let span: Int = spans[i];
  if off < 0 { return false; }
  if span < need { return false; }
  if off + need > _PCI_SPACE { return false; }
  let raw: Vec[UInt8] = f.raw;
  return raw.len() >= _PCI_SPACE;
}

// Little-endian field at `rel` bytes from capability `i`'s header, or -1 when
// the capability does not exist or its span does not cover the field.
fn _cap_u8(f: &PciFunction, i: Int, rel: Int) -> Int {
  if rel < 0 { return -1; }
  if !_cap_ready(f, i, rel + 1) { return -1; }
  let offsets: Vec[Int] = f.cap_offsets;
  let raw: Vec[UInt8] = f.raw;
  let off: Int = offsets[i];
  return _u8(&raw, off + rel);
}

fn _cap_u16(f: &PciFunction, i: Int, rel: Int) -> Int {
  if rel < 0 { return -1; }
  if !_cap_ready(f, i, rel + 2) { return -1; }
  let offsets: Vec[Int] = f.cap_offsets;
  let raw: Vec[UInt8] = f.raw;
  let off: Int = offsets[i];
  return _u16(&raw, off + rel);
}

fn _cap_u32(f: &PciFunction, i: Int, rel: Int) -> Int {
  if rel < 0 { return -1; }
  if !_cap_ready(f, i, rel + 4) { return -1; }
  let offsets: Vec[Int] = f.cap_offsets;
  let raw: Vec[UInt8] = f.raw;
  let off: Int = offsets[i];
  return _u32(&raw, off + rel);
}

// --------------------------------------------------
//  Public API -- parsing, raw access, population
// --------------------------------------------------

/// Parse one function's 256-byte configuration space.
///
/// `data` must hold at least 256 bytes; the first 256 are the function's
/// space and any extra bytes are ignored. The header type's bit 7 is the
/// multi-function flag and the low seven bits select the header kind; only
/// kinds 0x00 (type-0 device) and 0x01 (PCI-to-PCI bridge) are decoded, and
/// only they get a capability walk. When the status word's bit 4
/// (capability-list present) is clear, or the kind is neither 0x00 nor 0x01,
/// the three capability columns are empty even if 0x34 is nonzero.
///
/// Capability walk rules: the first pointer and every next pointer must lie
/// in 0x40..0xFF and be a multiple of 4 -> Err("pci: bad capability
/// pointer"); next pointers must be strictly increasing, so a self-loop, a
/// backward pointer or any pointer that would revisit an earlier capability
/// is Err("pci: capability loop"). Each capability's span is the distance to
/// the next capability, or to the end of the 256-byte space for the last one.
/// Unknown capability IDs are preserved in the columns raw.
///
/// Vendor ID 0xFFFF is not an error: it is the documented "no device" rule,
/// reported by pci_is_populated.
///
/// Error case: Err("pci: truncated config space") when data.len() < 256;
/// Err("pci: bad capability pointer") / Err("pci: capability loop") from the
/// walk. An empty vendor ID (0x0000) parses and is "populated".
/// Complexity: O(256).
pub fn pci_parse(data: &Vec[UInt8]) -> Result[PciFunction, Str] {
  if data.len() < _PCI_SPACE {
    return _err_fn("pci: truncated config space");
  }
  var raw = Vec[UInt8].new();
  var i = 0;
  while i < _PCI_SPACE {
    raw.push(data[i]);
    i = i + 1;
  }
  var cap_ids = Vec[Int].new();
  var cap_offsets = Vec[Int].new();
  var cap_spans = Vec[Int].new();
  let header_type: Int = _u8(data, 14);
  let kind: Int = _header_kind(header_type);
  let status: Int = _u16(data, 6);
  let walk: Bool = _bit16(status, 4) && (kind == 0 || kind == 1);
  if walk {
    var offset: Int = _u8(data, 52);
    if !_cap_ptr_ok(offset) {
      return _err_fn("pci: bad capability pointer");
    }
    while offset != 0 {
      let id: Int = _u8(data, offset);
      let next: Int = _u8(data, offset + 1);
      cap_ids.push(id);
      cap_offsets.push(offset);
      if next == 0 {
        cap_spans.push(_PCI_SPACE - offset);
        offset = 0;
      } else {
        if !_cap_ptr_ok(next) {
          return _err_fn("pci: bad capability pointer");
        }
        if next <= offset {
          return _err_fn("pci: capability loop");
        }
        cap_spans.push(next - offset);
        offset = next;
      }
    }
  }
  let f = PciFunction{
    raw: raw;
    cap_ids: cap_ids;
    cap_offsets: cap_offsets;
    cap_spans: cap_spans;
  };
  return _ok_fn(f);
}

/// Copy of the function's stored raw bytes exactly as parsed (256 bytes for a
/// parsed function). Round-trips: pci_serialize(pci_parse(x).value) equals x
/// for every accepted 256-byte prefix. Complexity: O(raw length).
pub fn pci_serialize(f: &PciFunction) -> Vec[UInt8] {
  let raw: Vec[UInt8] = f.raw;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < raw.len() {
    out.push(raw[i]);
    i = i + 1;
  }
  return out;
}

/// Byte at configuration-space offset `off` (0..255) widened to an Int; -1
/// when the stored raw buffer is shorter than 256 bytes or `off` is outside
/// 0..255. Complexity: O(1).
pub fn pci_raw_byte(f: &PciFunction, off: Int) -> Int {
  if off < 0 { return -1; }
  if off >= _PCI_SPACE { return -1; }
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, off);
}

/// True when the function is populated: its vendor ID differs from 0xFFFF
/// (the standard "no device" encoding). A vendor ID of 0x0000 counts as
/// populated. False when the stored raw buffer is shorter than 256 bytes.
/// Complexity: O(1).
pub fn pci_is_populated(f: &PciFunction) -> Bool {
  let vendor: Int = pci_vendor_id(f);
  if vendor < 0 { return false; }
  return vendor != 65535;
}

// --------------------------------------------------
//  Public API -- identification and header type
// --------------------------------------------------

/// Vendor ID (LE16 at 0x00); -1 when the raw buffer is shorter than 256.
/// Complexity: O(1).
pub fn pci_vendor_id(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u16(&raw, 0);
}

/// Device ID (LE16 at 0x02); -1 when the raw buffer is shorter than 256.
/// Complexity: O(1).
pub fn pci_device_id(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u16(&raw, 2);
}

/// Command word (LE16 at 0x04), raw. See the pci_command_* predicates.
/// Complexity: O(1).
pub fn pci_command(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u16(&raw, 4);
}

/// Status word (LE16 at 0x06), raw. See the pci_status_* predicates.
/// Complexity: O(1).
pub fn pci_status(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u16(&raw, 6);
}

/// Revision ID (byte at 0x08); -1 when the raw buffer is shorter than 256.
/// Complexity: O(1).
pub fn pci_revision_id(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, 8);
}

/// Programming interface byte (0x09); -1 when raw is shorter than 256.
/// Complexity: O(1).
pub fn pci_prog_if(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, 9);
}

/// Sub-class code (0x0A); -1 when raw is shorter than 256. Complexity: O(1).
pub fn pci_subclass(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, 10);
}

/// Base class code (0x0B); -1 when raw is shorter than 256. Use
/// pci_class_name for the documented partial name table. Complexity: O(1).
pub fn pci_class_code(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, 11);
}

/// Cache line size register (0x0C); -1 when raw is shorter than 256.
/// Complexity: O(1).
pub fn pci_cache_line_size(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, 12);
}

/// Latency timer register (0x0D); -1 when raw is shorter than 256.
/// Complexity: O(1).
pub fn pci_latency_timer(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, 13);
}

/// Header type byte (0x0E), raw 0..255: bit 7 is the multi-function flag,
/// bits 0..6 the header kind. Complexity: O(1).
pub fn pci_header_type(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, 14);
}

/// BIST register (0x0F), raw. Complexity: O(1).
pub fn pci_bist(f: &PciFunction) -> Int {
  let raw: Vec[UInt8] = f.raw;
  if raw.len() < _PCI_SPACE { return -1; }
  return _u8(&raw, 15);
}

/// Header kind: the low seven bits of pci_header_type (bit 7 is stripped).
/// 0x00 = type-0 device, 0x01 = PCI-to-PCI bridge, 0x02 = CardBus bridge;
/// any other value is an undocumented kind kept raw. -1 when raw is shorter
/// than 256. Complexity: O(1).
pub fn pci_header_kind(f: &PciFunction) -> Int {
  let ht: Int = pci_header_type(f);
  if ht < 0 { return -1; }
  return _header_kind(ht);
}

/// True when header-type bit 7 is set (multi-function device). False when raw
/// is shorter than 256. Complexity: O(1).
pub fn pci_multifunction(f: &PciFunction) -> Bool {
  let ht: Int = pci_header_type(f);
  if ht < 0 { return false; }
  return ht >= 128;
}

// --------------------------------------------------
//  Public API -- command and status predicates
// --------------------------------------------------

/// Command bit 0: I/O space access enabled. False when raw is short.
/// Complexity: O(1).
pub fn pci_command_io_enabled(f: &PciFunction) -> Bool {
  let v: Int = pci_command(f);
  if v < 0 { return false; }
  return _bit16(v, 0);
}

/// Command bit 1: memory space access enabled. False when raw is short.
/// Complexity: O(1).
pub fn pci_command_memory_enabled(f: &PciFunction) -> Bool {
  let v: Int = pci_command(f);
  if v < 0 { return false; }
  return _bit16(v, 1);
}

/// Command bit 2: bus-master access enabled. False when raw is short.
/// Complexity: O(1).
pub fn pci_command_bus_master_enabled(f: &PciFunction) -> Bool {
  let v: Int = pci_command(f);
  if v < 0 { return false; }
  return _bit16(v, 2);
}

/// Command bit 8: SERR# driver enabled. False when raw is short.
/// Complexity: O(1).
pub fn pci_command_serr_enabled(f: &PciFunction) -> Bool {
  let v: Int = pci_command(f);
  if v < 0 { return false; }
  return _bit16(v, 8);
}

/// Command bit 10: interrupt disable set. False when raw is short.
/// Complexity: O(1).
pub fn pci_command_interrupt_disabled(f: &PciFunction) -> Bool {
  let v: Int = pci_command(f);
  if v < 0 { return false; }
  return _bit16(v, 10);
}

/// Status bit 4: the function declares a capability list (the walk uses it).
/// This reports the raw status bit only; kinds other than 0x00/0x01 have
/// their walk skipped (see pci_parse). False when raw is short.
/// Complexity: O(1).
pub fn pci_has_capability_list(f: &PciFunction) -> Bool {
  let v: Int = pci_status(f);
  if v < 0 { return false; }
  return _bit16(v, 4);
}

/// Status bit 5: 66 MHz capable. False when raw is short. Complexity: O(1).
pub fn pci_status_66mhz_capable(f: &PciFunction) -> Bool {
  let v: Int = pci_status(f);
  if v < 0 { return false; }
  return _bit16(v, 5);
}

/// Status bit 7: fast back-to-back capable. False when raw is short.
/// Complexity: O(1).
pub fn pci_status_fast_back_to_back(f: &PciFunction) -> Bool {
  let v: Int = pci_status(f);
  if v < 0 { return false; }
  return _bit16(v, 7);
}

/// Status bit 3: interrupt status (pending). False when raw is short.
/// Complexity: O(1).
pub fn pci_status_interrupt_pending(f: &PciFunction) -> Bool {
  let v: Int = pci_status(f);
  if v < 0 { return false; }
  return _bit16(v, 3);
}

/// Status bit 8: master data parity error. False when raw is short.
/// Complexity: O(1).
pub fn pci_status_master_data_parity_error(f: &PciFunction) -> Bool {
  let v: Int = pci_status(f);
  if v < 0 { return false; }
  return _bit16(v, 8);
}

// --------------------------------------------------
//  Public API -- documented name tables
// --------------------------------------------------

/// Documented partial base-class name table: 0x00..0x13, 0x40 and 0xFF are
/// named; every other code (including negatives) returns "". This is a
/// convenience table, not a registry.
/// Complexity: O(1).
pub fn pci_class_name(code: Int) -> Str {
  if code == 0x00 { return "Unclassified"; }
  if code == 0x01 { return "Mass storage controller"; }
  if code == 0x02 { return "Network controller"; }
  if code == 0x03 { return "Display controller"; }
  if code == 0x04 { return "Multimedia controller"; }
  if code == 0x05 { return "Memory controller"; }
  if code == 0x06 { return "Bridge"; }
  if code == 0x07 { return "Communication controller"; }
  if code == 0x08 { return "Generic system peripheral"; }
  if code == 0x09 { return "Input device controller"; }
  if code == 0x0A { return "Docking station"; }
  if code == 0x0B { return "Processor"; }
  if code == 0x0C { return "Serial bus controller"; }
  if code == 0x0D { return "Wireless controller"; }
  if code == 0x0E { return "Intelligent controller"; }
  if code == 0x0F { return "Satellite communications controller"; }
  if code == 0x10 { return "Encryption controller"; }
  if code == 0x11 { return "Signal processing controller"; }
  if code == 0x12 { return "Processing accelerators"; }
  if code == 0x13 { return "Non-Essential Instrumentation"; }
  if code == 0x40 { return "Coprocessor"; }
  if code == 0xFF { return "Unassigned class"; }
  return "";
}

/// Documented header-kind names: 0 = "device", 1 = "bridge", 2 = "cardbus";
/// any other value returns "". Complexity: O(1).
pub fn pci_header_kind_name(kind: Int) -> Str {
  if kind == 0 { return "device"; }
  if kind == 1 { return "bridge"; }
  if kind == 2 { return "cardbus"; }
  return "";
}

/// Documented partial capability-ID name table: 0x01 = "Power Management",
/// 0x05 = "MSI", 0x10 = "PCI Express"; every other ID returns "". Unknown
/// capabilities stay in the capability columns with their raw bytes intact.
/// Complexity: O(1).
pub fn pci_cap_name(id: Int) -> Str {
  if id == 0x01 { return "Power Management"; }
  if id == 0x05 { return "MSI"; }
  if id == 0x10 { return "PCI Express"; }
  return "";
}

// --------------------------------------------------
//  Public API -- BAR decoding (type-0 layout)
// --------------------------------------------------

/// Raw 32-bit BAR register of slot `i` (at 0x10 + 4*i) when the slot is a
/// real BAR for the header kind: slots 0..5 on kind 0x00, slots 0..1 on kind
/// 0x01 (a bridge's 0x18..0x27 bytes are bus/window registers), slot 0 on
/// kind 0x02; no slots on any other kind. -1 when the slot is not a BAR for
/// the kind or raw is shorter than 256. Complexity: O(1).
pub fn pci_bar_raw(f: &PciFunction, i: Int) -> Int {
  if !_bar_ready(f, i) { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _bar_val(&raw, i);
}

/// BAR kind from flag bit 0: 0 = memory space, 1 = I/O space; -1 for an
/// invalid slot or short raw. Complexity: O(1).
pub fn pci_bar_kind(f: &PciFunction, i: Int) -> Int {
  if !_bar_ready(f, i) { return -1; }
  let raw: Vec[UInt8] = f.raw;
  let v: Int = _bar_val(&raw, i);
  if _bar_is_io_val(v) { return 1; }
  return 0;
}

/// Memory BAR type bits 1..2: 0 = 32-bit, 2 = 64-bit, 1 and 3 reserved; -1
/// for an I/O BAR, an invalid slot or short raw. Complexity: O(1).
pub fn pci_bar_memory_type(f: &PciFunction, i: Int) -> Int {
  if !_bar_ready(f, i) { return -1; }
  let raw: Vec[UInt8] = f.raw;
  let v: Int = _bar_val(&raw, i);
  if _bar_is_io_val(v) { return -1; }
  return (v / 2) % 4;
}

/// True when slot `i` is a memory BAR with type bits 2 (64-bit decode).
/// False for I/O BARs, other types, invalid slots and short raw.
/// Complexity: O(1).
pub fn pci_bar_is_64(f: &PciFunction, i: Int) -> Bool {
  if !_bar_ready(f, i) { return false; }
  let raw: Vec[UInt8] = f.raw;
  return _bar_is_64_val(_bar_val(&raw, i));
}

/// True when slot `i` is the upper half of the 64-bit BAR in slot `i - 1`;
/// the upper half is not an independent BAR (pci_bar_address and
/// pci_bar_size return -1 for it). False for slot 0, invalid slots and short
/// raw. Complexity: O(1).
pub fn pci_bar_is_upper(f: &PciFunction, i: Int) -> Bool {
  if !_bar_ready(f, i) { return false; }
  let raw: Vec[UInt8] = f.raw;
  return _bar_is_upper_of(&raw, i);
}

/// BAR base address with the flag bits masked off: I/O drops bits 1..0,
/// memory drops bits 3..0 (type and prefetchable), and a 64-bit memory BAR
/// adds the upper 32 bits from the next slot. -1 for the upper half of a
/// 64-bit BAR, an invalid slot or short raw. A 64-bit address with bit 63
/// set comes out negative (signed Int two's complement, documented).
/// Complexity: O(1).
pub fn pci_bar_address(f: &PciFunction, i: Int) -> Int {
  if !_bar_ready(f, i) { return -1; }
  let raw: Vec[UInt8] = f.raw;
  if _bar_is_upper_of(&raw, i) { return -1; }
  return _bar_address_of(&raw, i);
}

/// BAR size proxy: the lowest set bit of the masked base address (its
/// power-of-two alignment), 0 when the address is zero (unassigned). On a
/// sizing value (all low bits zero above the address bits) this is exactly
/// the probed size; on a live base address it is the alignment. The result is
/// always 0 or a power of two, capped at 2^62 for the signed 64-bit edge.
/// -1 for the upper half of a 64-bit BAR, an invalid slot or short raw.
/// Complexity: O(1) (at most 63 modulo steps).
pub fn pci_bar_size(f: &PciFunction, i: Int) -> Int {
  if !_bar_ready(f, i) { return -1; }
  let raw: Vec[UInt8] = f.raw;
  if _bar_is_upper_of(&raw, i) { return -1; }
  let a: Int = _bar_address_of(&raw, i);
  if a == 0 { return 0; }
  return _lowest_bit(a);
}

// --------------------------------------------------
//  Public API -- type-0 extras (kind 0x00)
// --------------------------------------------------

/// CardBus CIS pointer (LE32 at 0x28) for header kind 0x00; -1 for any other
/// kind or short raw. Complexity: O(1).
pub fn pci_cardbus_cis(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 0 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _u32(&raw, 40);
}

/// Subsystem vendor ID (LE16 at 0x2C) for header kind 0x00; -1 otherwise.
/// Complexity: O(1).
pub fn pci_subsystem_vendor_id(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 0 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _u16(&raw, 44);
}

/// Subsystem ID (LE16 at 0x2E) for header kind 0x00; -1 otherwise.
/// Complexity: O(1).
pub fn pci_subsystem_device_id(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 0 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _u16(&raw, 46);
}

/// Expansion ROM BAR (LE32) at 0x30 for header kind 0x00 and at 0x38 for
/// header kind 0x01; -1 for any other kind or short raw. Raw value: bit 0 is
/// the enable flag, bits 10..1 are reserved, bits 31..11 the address.
/// Complexity: O(1).
pub fn pci_expansion_rom_raw(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 0 && kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  if kind == 0 { return _u32(&raw, 48); }
  return _u32(&raw, 56);
}

/// Expansion ROM enable flag (bit 0 of pci_expansion_rom_raw); false when
/// the kind has no expansion-ROM register or raw is short. Complexity: O(1).
pub fn pci_expansion_rom_enabled(f: &PciFunction) -> Bool {
  let v: Int = pci_expansion_rom_raw(f);
  if v < 0 { return false; }
  return v % 2 == 1;
}

/// Expansion ROM base address with bit 0 and the reserved bits 10..1 masked
/// off (`v - v % 2048`, 2 KiB granularity); -1 when the kind has no
/// expansion-ROM register or raw is short. Complexity: O(1).
pub fn pci_expansion_rom_address(f: &PciFunction) -> Int {
  let v: Int = pci_expansion_rom_raw(f);
  if v < 0 { return -1; }
  return v - v % _PCI_ROM_GRAN;
}

// --------------------------------------------------
//  Public API -- type-1 bridge fields (kind 0x01)
// --------------------------------------------------

/// Primary bus number (byte at 0x18) for header kind 0x01; -1 otherwise.
/// Complexity: O(1).
pub fn pci_bridge_primary_bus(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _u8(&raw, 24);
}

/// Secondary bus number (byte at 0x19) for header kind 0x01; -1 otherwise.
/// Complexity: O(1).
pub fn pci_bridge_secondary_bus(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _u8(&raw, 25);
}

/// Subordinate bus number (byte at 0x1A) for header kind 0x01; -1 otherwise.
/// Complexity: O(1).
pub fn pci_bridge_subordinate_bus(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _u8(&raw, 26);
}

/// Secondary status word (LE16 at 0x1E), raw, for header kind 0x01; -1
/// otherwise. Complexity: O(1).
pub fn pci_bridge_secondary_status(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _u16(&raw, 30);
}

/// True when I/O base bit 0 marks a 32-bit I/O window (kind 0x01 only).
/// False for other kinds or short raw. Complexity: O(1).
pub fn pci_bridge_io_is_32bit(f: &PciFunction) -> Bool {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return false; }
  let raw: Vec[UInt8] = f.raw;
  return _u8(&raw, 28) % 2 == 1;
}

/// I/O window base: the 8-bit register at 0x1C with its low flag nibble
/// dropped and scaled by 4 KiB (`(raw / 16) * 4096`, granularity 4 KiB);
/// -1 outside header kind 0x01. Complexity: O(1).
pub fn pci_bridge_io_base(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return (_u8(&raw, 28) / 16) * _PCI_IO_GRAN;
}

/// I/O window limit: the 8-bit register at 0x1D decoded like
/// pci_bridge_io_base; -1 outside header kind 0x01. Complexity: O(1).
pub fn pci_bridge_io_limit(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return (_u8(&raw, 29) / 16) * _PCI_IO_GRAN;
}

/// Memory window base: the 16-bit register at 0x20 with its low flag nibble
/// dropped and scaled by 1 MiB (`(raw / 16) * 1048576`, granularity 1 MiB);
/// -1 outside header kind 0x01. Complexity: O(1).
pub fn pci_bridge_memory_base(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return (_u16(&raw, 32) / 16) * _PCI_MEM_GRAN;
}

/// Memory window limit: the 16-bit register at 0x22 decoded like
/// pci_bridge_memory_base; -1 outside header kind 0x01. Complexity: O(1).
pub fn pci_bridge_memory_limit(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return (_u16(&raw, 34) / 16) * _PCI_MEM_GRAN;
}

/// Prefetchable memory window base: the 16-bit register at 0x24 decoded with
/// 1 MiB granularity; -1 outside header kind 0x01. The 64-bit upper register
/// at 0x28 is not combined (documented non-goal). Complexity: O(1).
pub fn pci_bridge_prefetchable_base(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return (_u16(&raw, 36) / 16) * _PCI_MEM_GRAN;
}

/// Prefetchable memory window limit: the 16-bit register at 0x26 decoded with
/// 1 MiB granularity; -1 outside header kind 0x01. The 64-bit upper register
/// at 0x2C is not combined (documented non-goal). Complexity: O(1).
pub fn pci_bridge_prefetchable_limit(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return (_u16(&raw, 38) / 16) * _PCI_MEM_GRAN;
}

/// Bridge control word (LE16 at 0x3E), raw, for header kind 0x01; -1
/// otherwise. For other header kinds 0x3E..0x3F are not bridge control
/// (Min_Gnt/Max_Lat on type-0) and are not exposed as such. Complexity: O(1).
pub fn pci_bridge_control(f: &PciFunction) -> Int {
  let kind: Int = pci_header_kind(f);
  if kind != 1 { return -1; }
  let raw: Vec[UInt8] = f.raw;
  return _u16(&raw, 62);
}

// --------------------------------------------------
//  Public API -- capability index
// --------------------------------------------------

/// Number of capabilities recorded by the walk, defensively the minimum of
/// the three capability-column lengths (a parsed function has them equal).
/// O(1).
pub fn pci_cap_count(f: &PciFunction) -> Int {
  let ids: Vec[Int] = f.cap_ids;
  let offsets: Vec[Int] = f.cap_offsets;
  let spans: Vec[Int] = f.cap_spans;
  var n: Int = ids.len();
  if offsets.len() < n { n = offsets.len(); }
  if spans.len() < n { n = spans.len(); }
  return n;
}

/// Capability ID of list entry `i` in walk order; -1 when out of range.
/// Complexity: O(1).
pub fn pci_cap_id(f: &PciFunction, i: Int) -> Int {
  if i < 0 { return -1; }
  let ids: Vec[Int] = f.cap_ids;
  if i >= ids.len() { return -1; }
  let v: Int = ids[i];
  return v;
}

/// Configuration-space offset of capability `i` in walk order; -1 out of
/// range. Complexity: O(1).
pub fn pci_cap_offset(f: &PciFunction, i: Int) -> Int {
  if i < 0 { return -1; }
  let offsets: Vec[Int] = f.cap_offsets;
  if i >= offsets.len() { return -1; }
  let v: Int = offsets[i];
  return v;
}

/// Span of capability `i` in bytes: the distance to the next capability, or
/// to the end of the 256-byte space for the last capability. A bounded
/// region, not a guaranteed register-block size. -1 out of range.
/// Complexity: O(1).
pub fn pci_cap_span(f: &PciFunction, i: Int) -> Int {
  if i < 0 { return -1; }
  let spans: Vec[Int] = f.cap_spans;
  if i >= spans.len() { return -1; }
  let v: Int = spans[i];
  return v;
}

/// First list entry in walk order whose ID equals `id`, or -1 when absent.
/// This is the capability list order accessor: iterate 0..pci_cap_count-1 for
/// the full order. Complexity: O(capabilities).
pub fn pci_cap_find(f: &PciFunction, id: Int) -> Int {
  let ids: Vec[Int] = f.cap_ids;
  var i = 0;
  while i < ids.len() {
    let v: Int = ids[i];
    if v == id { return i; }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Public API -- capability raw reads
// --------------------------------------------------

/// Byte at `rel` bytes from capability `i`'s header (rel 0 is the ID byte,
/// rel 1 the next pointer); -1 when the capability does not exist or its span
/// does not cover rel + 1. Works for unknown capability IDs too (raw
/// preservation). Complexity: O(1).
pub fn pci_cap_read_u8(f: &PciFunction, i: Int, rel: Int) -> Int {
  return _cap_u8(f, i, rel);
}

/// LE16 at `rel` bytes from capability `i`'s header, or -1 when out of span.
/// Complexity: O(1).
pub fn pci_cap_read_u16(f: &PciFunction, i: Int, rel: Int) -> Int {
  return _cap_u16(f, i, rel);
}

/// LE32 at `rel` bytes from capability `i`'s header, or -1 when out of span.
/// Complexity: O(1).
pub fn pci_cap_read_u32(f: &PciFunction, i: Int, rel: Int) -> Int {
  return _cap_u32(f, i, rel);
}

// --------------------------------------------------
//  Public API -- documented capability subsets
// --------------------------------------------------

/// PM capability (ID 0x01) version: bits 2..0 of the 16-bit PMC register at
/// rel 2; -1 when `i` is not a PM capability or the span is too short
/// (needs 4 bytes). Complexity: O(1).
pub fn pci_cap_pm_version(f: &PciFunction, i: Int) -> Int {
  if pci_cap_id(f, i) != 0x01 { return -1; }
  let v: Int = _cap_u16(f, i, 2);
  if v < 0 { return -1; }
  return v % 8;
}

/// PM capability (ID 0x01) PMCSR register (LE16 at rel 4); -1 when `i` is not
/// a PM capability or the span is too short (needs 6 bytes). Complexity: O(1).
pub fn pci_cap_pm_control(f: &PciFunction, i: Int) -> Int {
  if pci_cap_id(f, i) != 0x01 { return -1; }
  return _cap_u16(f, i, 4);
}

/// MSI capability (ID 0x05) message control word (LE16 at rel 2); -1 when
/// `i` is not an MSI capability or the span is too short (needs 4 bytes).
/// Complexity: O(1).
pub fn pci_cap_msi_control(f: &PciFunction, i: Int) -> Int {
  if pci_cap_id(f, i) != 0x05 { return -1; }
  return _cap_u16(f, i, 2);
}

/// True when MSI capability `i` bit 7 of the message control word selects
/// 64-bit message addresses. False for a non-MSI entry or too-short span.
/// Complexity: O(1).
pub fn pci_cap_msi_64bit(f: &PciFunction, i: Int) -> Bool {
  let ctl: Int = pci_cap_msi_control(f, i);
  if ctl < 0 { return false; }
  return (ctl / 128) % 2 == 1;
}

/// MSI capability (ID 0x05) message address: LE32 at rel 4, plus the upper
/// LE32 at rel 8 when the 64-bit bit is set (needs 8 or 12 span bytes); -1
/// when `i` is not an MSI capability or the span is too short. A 64-bit
/// address with bit 63 set comes out negative (documented). Complexity: O(1).
pub fn pci_cap_msi_address(f: &PciFunction, i: Int) -> Int {
  if pci_cap_id(f, i) != 0x05 { return -1; }
  let lo: Int = _cap_u32(f, i, 4);
  if lo < 0 { return -1; }
  if pci_cap_msi_64bit(f, i) {
    let hi: Int = _cap_u32(f, i, 8);
    if hi < 0 { return -1; }
    return lo + hi * _PCI_2P32;
  }
  return lo;
}

/// MSI capability (ID 0x05) message data: LE16 at rel 8 for 32-bit addresses
/// or rel 12 for 64-bit ones (needs 10 or 14 span bytes); -1 when `i` is not
/// an MSI capability or the span is too short. Complexity: O(1).
pub fn pci_cap_msi_data(f: &PciFunction, i: Int) -> Int {
  if pci_cap_id(f, i) != 0x05 { return -1; }
  if pci_cap_msi_64bit(f, i) {
    return _cap_u16(f, i, 12);
  }
  return _cap_u16(f, i, 8);
}

/// PCIe capability (ID 0x10) version: bits 3..0 of the 16-bit PCI Express
/// capability register at rel 2; -1 when `i` is not a PCIe capability or the
/// span is too short (needs 4 bytes). Complexity: O(1).
pub fn pci_cap_pcie_version(f: &PciFunction, i: Int) -> Int {
  if pci_cap_id(f, i) != 0x10 { return -1; }
  let v: Int = _cap_u16(f, i, 2);
  if v < 0 { return -1; }
  return v % 16;
}

/// PCIe capability (ID 0x10) device capabilities register (LE32 at rel 4);
/// -1 when `i` is not a PCIe capability or the span is too short (needs 8
/// bytes). Complexity: O(1).
pub fn pci_cap_pcie_device_caps(f: &PciFunction, i: Int) -> Int {
  if pci_cap_id(f, i) != 0x10 { return -1; }
  return _cap_u32(f, i, 4);
}

// --------------------------------------------------
//  Public API -- canonical type-0 builder
// --------------------------------------------------

/// Build a canonical 256-byte type-0 configuration space from `cfg`.
///
/// Canonical output: the seven header words at 0x00..0x0F (header type 0x00,
/// or 0x80 when `multifunction` is true), the six BAR values at
/// 0x10..0x27, the CardBus CIS pointer at 0x28, the subsystem vendor/device
/// IDs at 0x2C/0x2E, and the expansion ROM BAR at 0x30. Everything from 0x34
/// to 0xFF is zero: the capability pointer is 0 and no capability list is
/// emitted, so the status word's capability-list bit 4 must be clear.
///
/// Validation order: `bars.len() == 6` -> Err("pci: bar count"); the six
/// 16-bit words (vendor, device, command, status, subsystem vendor, subsystem
/// device) -> Err("pci: bad word field"); the seven 8-bit fields (revision,
/// prog_if, subclass, class_code, cache line size, latency timer, BIST) ->
/// Err("pci: bad byte field"); the nine 32-bit fields (BAR0..BAR5 in order,
/// CardBus CIS, expansion ROM) -> Err("pci: bad dword field"); status bit 4
/// set -> Err("pci: capability list bit set").
///
/// Returns Ok(bytes) of length 256. Complexity: O(256).
pub fn pci_build_type0(cfg: &PciType0Config) -> Result[Vec[UInt8], Str] {
  let bars: Vec[Int] = cfg.bars;
  if bars.len() != _PCI_BAR_COUNT {
    return _err_bytes("pci: bar count");
  }
  if !_word_ok(cfg.vendor_id) { return _err_bytes("pci: bad word field"); }
  if !_word_ok(cfg.device_id) { return _err_bytes("pci: bad word field"); }
  if !_word_ok(cfg.command) { return _err_bytes("pci: bad word field"); }
  if !_word_ok(cfg.status) { return _err_bytes("pci: bad word field"); }
  if !_word_ok(cfg.subsystem_vendor_id) { return _err_bytes("pci: bad word field"); }
  if !_word_ok(cfg.subsystem_device_id) { return _err_bytes("pci: bad word field"); }
  if !_byte_ok(cfg.revision_id) { return _err_bytes("pci: bad byte field"); }
  if !_byte_ok(cfg.prog_if) { return _err_bytes("pci: bad byte field"); }
  if !_byte_ok(cfg.subclass) { return _err_bytes("pci: bad byte field"); }
  if !_byte_ok(cfg.class_code) { return _err_bytes("pci: bad byte field"); }
  if !_byte_ok(cfg.cache_line_size) { return _err_bytes("pci: bad byte field"); }
  if !_byte_ok(cfg.latency_timer) { return _err_bytes("pci: bad byte field"); }
  if !_byte_ok(cfg.bist) { return _err_bytes("pci: bad byte field"); }
  var i = 0;
  while i < _PCI_BAR_COUNT {
    let b: Int = bars[i];
    if !_dword_ok(b) { return _err_bytes("pci: bad dword field"); }
    i = i + 1;
  }
  if !_dword_ok(cfg.cardbus_cis) { return _err_bytes("pci: bad dword field"); }
  if !_dword_ok(cfg.expansion_rom) { return _err_bytes("pci: bad dword field"); }
  if _bit16(cfg.status, 4) { return _err_bytes("pci: capability list bit set"); }
  var out = Vec[UInt8].new();
  _push_le(&mut out, cfg.vendor_id, 2);
  _push_le(&mut out, cfg.device_id, 2);
  _push_le(&mut out, cfg.command, 2);
  _push_le(&mut out, cfg.status, 2);
  out.push(cfg.revision_id as UInt8);
  out.push(cfg.prog_if as UInt8);
  out.push(cfg.subclass as UInt8);
  out.push(cfg.class_code as UInt8);
  out.push(cfg.cache_line_size as UInt8);
  out.push(cfg.latency_timer as UInt8);
  if cfg.multifunction {
    out.push(128 as UInt8);
  } else {
    out.push(0 as UInt8);
  }
  out.push(cfg.bist as UInt8);
  var b = 0;
  while b < _PCI_BAR_COUNT {
    let v: Int = bars[b];
    _push_le(&mut out, v, 4);
    b = b + 1;
  }
  _push_le(&mut out, cfg.cardbus_cis, 4);
  _push_le(&mut out, cfg.subsystem_vendor_id, 2);
  _push_le(&mut out, cfg.subsystem_device_id, 2);
  _push_le(&mut out, cfg.expansion_rom, 4);
  _push_zero(&mut out, _PCI_SPACE - out.len());
  return _ok_bytes(out);
}
