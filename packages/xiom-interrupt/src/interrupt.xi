// XIOM -- xiom.interrupt: interrupt controller structure codecs
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.interrupt
// placeholder. Scope: *structure* codecs for interrupt controller tables
// and registers. Every function reads a caller-supplied byte buffer;
// nothing performs MMIO, registration, dispatch or device access.
//
//   * x86 IDT gate descriptors, 32-bit (8-byte) and 64-bit (16-byte)
//     forms: offset split fields (low/mid/high), selector, IST, the
//     type/attribute byte (gate type 0xE interrupt / 0xF trap, DPL 0-3,
//     P present, S storage segment), offset assembly/extraction helpers,
//     present-bit validation and the IDTR base/limit in both modes.
//   * Well-known x86 vectors: names for 0-21, RESERVED for 15 and 22-31,
//     USER for 32-255; error-code classification; class strings.
//   * ARM GICv2 distributor registers (little-endian, byte offsets from
//     the distributor base): GICD_CTLR, GICD_TYPER, the
//     IGROUPR / ISENABLER / ICENABLER / ISPENDR / ICPENDR bitmaps, the
//     per-IRQ GICD_IPRIORITYR byte, the per-IRQ GICD_ITARGETSR byte and
//     IRQ ID classification (SGI 0-15, PPI 16-31, SPI 32+ and the
//     highest valid ID from TYPER).
//   * GICv3 / GICv3.1 note-level extras, documented as limited:
//     GICD_TYPER bit 17 (LSPI), bit 8 (ESPI) with bits [31:27]
//     (ESPI range) and the GICD_TYPER2 raw field at offset 0x00C.
//
// Documented policies:
//   * little-endian extraction/packing is arithmetic (division/modulo
//     with negative-remainder correction) because `&` masks on operands
//     with bit 31 set miscompile in v0.61.3; every bitfield probe goes
//     through byte extraction first;
//   * u32 values with bit 31 set are held as the same signed
//     two's-complement Int bit pattern (the xiom.acpi convention), and
//     64-bit addresses above 2^63-1 likewise;
//   * every error message names the byte offset (or register offset) it
//     was detected at;
//   * strict decoders reject short register blocks, impossible bitmap
//     sizes and the reserved bits of the documented layouts; the raw
//     register word can always be read with `gicd_word` when a
//     forward-compatible lenient read is wanted;
//   * GICD_ITARGETSR is reported as read-only for SGI 0-15 and PPI
//     16-31, matching the GICv2 spec.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with `(b as Int) & 0xFF`
//     before entering Int arithmetic.
//   * Str values are never compared with `==`; the library has no Str
//     equality checks at all, and tests compare with str_compare.

module xiom.interrupt

use xiom.string;
use xiom.convert.int;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Size of a 32-bit IDT gate descriptor in bytes.
pub const X86_IDT_GATE32_LEN: Int = 8;
/// Size of a 64-bit IDT gate descriptor in bytes.
pub const X86_IDT_GATE64_LEN: Int = 16;
/// Size of the IDTR in 32-bit mode (16-bit limit + 32-bit base).
pub const X86_IDTR32_LEN: Int = 6;
/// Size of the IDTR in 64-bit mode (16-bit limit + 64-bit base).
pub const X86_IDTR64_LEN: Int = 10;
/// Number of architectural IDT vectors (0..255).
pub const X86_IDT_VECTOR_COUNT: Int = 256;
/// Legacy 32-bit task gate type (attribute low nibble 0x5).
pub const X86_IDT_TYPE_TASK32: Int = 5;
/// Legacy 16-bit interrupt gate type (attribute low nibble 0x6).
pub const X86_IDT_TYPE_INT16: Int = 6;
/// Legacy 16-bit trap gate type (attribute low nibble 0x7).
pub const X86_IDT_TYPE_TRAP16: Int = 7;
/// Interrupt gate type (attribute low nibble 0xE).
pub const X86_IDT_TYPE_INTERRUPT: Int = 14;
/// Trap gate type (attribute low nibble 0xF).
pub const X86_IDT_TYPE_TRAP: Int = 15;
/// Highest DPL value (DPL is 0..3).
pub const X86_IDT_DPL_MAX: Int = 3;
/// Highest IST index (IST is 0..7; 0 means "no stack switch").
pub const X86_IDT_IST_MAX: Int = 7;

/// GICD_CTLR: distributor control register (offset from distributor base).
pub const GICD_CTLR: Int = 0;
/// GICD_TYPER: distributor type register.
pub const GICD_TYPER: Int = 4;
/// GICD_TYPER2: GICv3.1 distributor type register 2 (note-level extra).
pub const GICD_TYPER2: Int = 12;
/// GICD_IGROUPR: group bitmap base, ID 0 upward (SGI/PPI in word 0).
pub const GICD_IGROUPR: Int = 128;
/// GICD_ISENABLER: set-enable bitmap base, SPI 32 upward.
pub const GICD_ISENABLER: Int = 256;
/// GICD_ICENABLER: clear-enable bitmap base, SPI 32 upward.
pub const GICD_ICENABLER: Int = 384;
/// GICD_ISPENDR: set-pending bitmap base, SPI 32 upward.
pub const GICD_ISPENDR: Int = 512;
/// GICD_ICPENDR: clear-pending bitmap base, SPI 32 upward.
pub const GICD_ICPENDR: Int = 640;
/// GICD_IPRIORITYR: per-IRQ priority byte base.
pub const GICD_IPRIORITYR: Int = 1024;
/// GICD_ITARGETSR: per-IRQ CPU target byte base.
pub const GICD_ITARGETSR: Int = 2048;
/// Distributor register aperture size (64 KiB, GICv3 GIC_V3_DIST_SIZE).
pub const GICD_SIZE: Int = 65536;

/// Number of SGIs (interrupt IDs 0-15).
pub const GIC_SGI_COUNT: Int = 16;
/// Number of PPIs (interrupt IDs 16-31).
pub const GIC_PPI_COUNT: Int = 16;
/// First SPI interrupt ID.
pub const GIC_FIRST_SPI: Int = 32;
/// Highest valid GICv2 interrupt ID (1020-1023 are special).
pub const GIC_MAX_INTID: Int = 1019;
/// The GICv2 spurious interrupt ID.
pub const GIC_SPURIOUS_INTID: Int = 1022;
/// First extended SPI (ESPI) interrupt ID (GICv3.1, note-level).
pub const ESPI_BASE_INTID: Int = 4096;
/// Number of ESPI IDs in the maximum extended range (4096-5119).
pub const GIC_ESPI_COUNT: Int = 1024;
/// Largest bitmap block: 32 words cover interrupt IDs 0-1023.
pub const GIC_MAX_BITMAP_WORDS: Int = 32;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// One decoded x86 IDT gate descriptor. `target_offset` is the assembled
/// handler offset (32-bit for the 8-byte form; the 64-bit bit pattern,
/// possibly negative above 2^63-1, for the 16-byte form). `ist_index` is
/// always 0 for the 32-bit form. `gate_type` is the attribute low nibble
/// (0x5/0x6/0x7 legacy, 0xE interrupt, 0xF trap). Fields are public;
/// accessors exist for the common ones.
pub type X86IdtGate = {
  target_offset: Int;
  code_selector: Int;
  ist_index: Int;
  gate_type: Int;
  dpl: Int;
  present: Bool;
  storage_segment: Bool;
  long_mode: Bool;
}

/// One decoded IDTR value. `base` is a 32-bit address for the 6-byte form
/// and a 64-bit bit pattern for the 10-byte form; `limit` is the raw
/// 16-bit byte limit.
pub type X86Idtr = {
  limit: Int;
  base: Int;
  long_mode: Bool;
}

/// Decoded GICD_CTLR. `enable_grp0`/`enable_grp1` are the GICv2 group
/// enables, `enable_grp1s`/`enable_grp1ns` the security-extension split,
/// `are_s`/`are_ns` the GICv3 affinity-routing enables (bit 4 is ARE_S in
/// the secure view and ARE_NS in the non-secure view; this decoder names
/// the secure view), `disable_security` is DS (bit 6) and `nassgi_req` is
/// the GICv4.1 nASSGIreq bit (bit 8). `rwp` is bit 31.
pub type GicdCtlr = {
  enable_grp0: Bool;
  enable_grp1: Bool;
  enable_grp1s: Bool;
  enable_grp1ns: Bool;
  are_s: Bool;
  are_ns: Bool;
  disable_security: Bool;
  nassgi_req: Bool;
  rwp: Bool;
  raw: Int;
}

/// Decoded GICD_TYPER. `it_lines_number` is bits [4:0]; `cpu_count` is
/// CPUNumber+1 (1..8); `security_extn` is bit 10; `lspi` is bit 17
/// (GICv3 note-level); `mbis` is bit 16; `espi` is bit 8 and `espi_range`
/// the number of extended SPI IDs advertised by bits [31:27]
/// (GICv3.1 note-level, 0 when bit 8 is clear); `max_interrupts` is the
/// GICv2 total from ITLinesNumber, capped at 1020.
pub type GicdTyper = {
  it_lines_number: Int;
  cpu_count: Int;
  espi: Bool;
  espi_range: Int;
  security_extn: Bool;
  mbis: Bool;
  lspi: Bool;
  max_interrupts: Int;
  raw: Int;
}

/// Decoded GICD_TYPER2 (GICv3.1, note-level and documented as limited):
/// `vid` is bits [4:0], `vil` is bit 7 and `nassgi_cap` is bit 8.
pub type GicdTyper2 = {
  vid: Int;
  vil: Bool;
  nassgi_cap: Bool;
  raw: Int;
}

/// One decoded GICD_ITARGETSR byte. `targets` is the raw 8-bit CPU target
/// mask; `writable` is false for SGI 0-15 and PPI 16-31, whose targets
/// are read-only in GICv2.
pub type GicdTarget = {
  irq: Int;
  targets: Int;
  writable: Bool;
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[X86IdtGate, Str].
fn _ok_gate(v: X86IdtGate) -> Result[X86IdtGate, Str] {
  return Ok(v);
}

// Err(m) for Result[X86IdtGate, Str].
fn _err_gate(m: Str) -> Result[X86IdtGate, Str] {
  return Err(m);
}

// Ok(v) for Result[X86Idtr, Str].
fn _ok_idtr(v: X86Idtr) -> Result[X86Idtr, Str] {
  return Ok(v);
}

// Err(m) for Result[X86Idtr, Str].
fn _err_idtr(m: Str) -> Result[X86Idtr, Str] {
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

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[GicdCtlr, Str].
fn _ok_ctl(v: GicdCtlr) -> Result[GicdCtlr, Str] {
  return Ok(v);
}

// Err(m) for Result[GicdCtlr, Str].
fn _err_ctl(m: Str) -> Result[GicdCtlr, Str] {
  return Err(m);
}

// Ok(v) for Result[GicdTyper, Str].
fn _ok_typ(v: GicdTyper) -> Result[GicdTyper, Str] {
  return Ok(v);
}

// Err(m) for Result[GicdTyper, Str].
fn _err_typ(m: Str) -> Result[GicdTyper, Str] {
  return Err(m);
}

// Ok(v) for Result[GicdTyper2, Str].
fn _ok_typ2(v: GicdTyper2) -> Result[GicdTyper2, Str] {
  return Ok(v);
}

// Err(m) for Result[GicdTyper2, Str].
fn _err_typ2(m: Str) -> Result[GicdTyper2, Str] {
  return Err(m);
}

// Ok(v) for Result[GicdTarget, Str].
fn _ok_tgt(v: GicdTarget) -> Result[GicdTarget, Str] {
  return Ok(v);
}

// Err(m) for Result[GicdTarget, Str].
fn _err_tgt(m: Str) -> Result[GicdTarget, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte and bit helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  let b: UInt8 = data[pos];
  return (b as Int) & 0xFF;
}

// Unsigned little-endian Int of the `size` bytes at `pos` (1..8 bytes;
// 8-byte values above 2^63-1 wrap to the same two's-complement bit
// pattern). The caller guarantees pos + size <= data.len().
fn _read_le(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var shift: Int = 1;
  var i = 0;
  while i < size {
    v = v + _byte(data, pos + i) * shift;
    shift = shift * 256;
    i = i + 1;
  }
  return v;
}

// Byte `shift_bytes` above the least significant byte of `v` (0 = LSB),
// widened to 0..255. Arithmetic only, exact for negative two's-complement
// values: `& 0xFF` on values with bit 31 set miscompiles in v0.61.3.
fn _byte_of(v: Int, shift_bytes: Int) -> Int {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b;
}

// Append the low `size` bytes of `v` in little-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_of(v, i) as UInt8);
    i = i + 1;
  }
}

// True when bit `k` (0..7) of byte `b` (0..255) is set.
fn _byte_bit(b: Int, k: Int) -> Bool {
  var div: Int = 1;
  var i = 0;
  while i < k {
    div = div * 2;
    i = i + 1;
  }
  let q: Int = b / div;
  return q % 2 == 1;
}

// True when bit `k` (0..31) of the 32-bit value `v` is set, including
// values with bit 31 set (byte extraction first, then bit test).
fn _word_bit(v: Int, k: Int) -> Bool {
  let b: Int = _byte_of(v, k / 8);
  return _byte_bit(b, k % 8);
}

// True when any bit in [lo, hi] of `v` is set.
fn _bit_set_between(v: Int, lo: Int, hi: Int) -> Bool {
  var k = lo;
  while k <= hi {
    if _word_bit(v, k) {
      return true;
    }
    k = k + 1;
  }
  return false;
}

// "interrupt: <what> out of range at offset N (need X bytes, have Y)".
fn _range_err(what: Str, offset: Int, need: Int, have: Int) -> Str {
  if need == 1 {
    return "interrupt: " + what + " out of range at offset " + int_to_string(offset) + " (need 1 byte, have " + int_to_string(have) + ")";
  }
  return "interrupt: " + what + " out of range at offset " + int_to_string(offset) + " (need " + int_to_string(need) + " bytes, have " + int_to_string(have) + ")";
}

// "interrupt: <what> <detail> invalid at offset N".
fn _field_err(what: Str, offset: Int, detail: Str) -> Str {
  return "interrupt: " + what + " " + detail + " invalid at offset " + int_to_string(offset);
}

// "interrupt: irq N <detail>".
fn _irq_err(irq: Int, detail: Str) -> Str {
  return "interrupt: irq " + int_to_string(irq) + " " + detail;
}

// True when `base` is one of the five distributor bitmap register bases.
fn _bitmap_base_ok(base: Int) -> Bool {
  if base == GICD_IGROUPR { return true; }
  if base == GICD_ISENABLER { return true; }
  if base == GICD_ICENABLER { return true; }
  if base == GICD_ISPENDR { return true; }
  if base == GICD_ICPENDR { return true; }
  return false;
}

// Word index of `irq` inside bitmap family `base`. The group bitmap
// starts at ID 0; the enable/pending bitmaps start at SPI 32.
fn _bitmap_word_index(base: Int, irq: Int) -> Int {
  if base == GICD_IGROUPR {
    return irq / 32;
  }
  return (irq - GIC_FIRST_SPI) / 32;
}

// --------------------------------------------------
//  x86 IDT gate descriptors
// --------------------------------------------------

/// Assemble a 32-bit gate target offset from its two split fields. The
/// documented domain is 0..65535 for each field; the result is exact for
/// non-negative inputs.
/// Complexity: O(1).
pub fn x86_idt_gate32_join(offset_low: Int, offset_mid: Int) -> Int {
  return offset_low + offset_mid * 65536;
}

/// Assemble a 64-bit gate target offset from its three split fields. The
/// documented domain is 0..65535 for the low/mid fields and 0..4294967295
/// for the high field; a high field above 2^31-1 yields the same
/// negative two's-complement Int bit pattern as the hardware value.
/// Complexity: O(1).
pub fn x86_idt_gate64_join(offset_low: Int, offset_mid: Int, offset_high: Int) -> Int {
  return offset_low + offset_mid * 65536 + offset_high * 4294967296;
}

/// Split a 32-bit target offset into [low16, mid16]. Extraction is exact
/// two's complement, so negative bit patterns also round-trip.
/// Complexity: O(1).
pub fn x86_idt_gate32_offset_parts(target_offset: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(_byte_of(target_offset, 0) + _byte_of(target_offset, 1) * 256);
  v.push(_byte_of(target_offset, 2) + _byte_of(target_offset, 3) * 256);
  return v;
}

/// Split a target offset into [low16, mid16, high32]. Extraction is exact
/// two's complement, so 64-bit addresses above 2^63-1 also round-trip.
/// Complexity: O(1).
pub fn x86_idt_gate64_offset_parts(target_offset: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(_byte_of(target_offset, 0) + _byte_of(target_offset, 1) * 256);
  v.push(_byte_of(target_offset, 2) + _byte_of(target_offset, 3) * 256);
  v.push(
    _byte_of(target_offset, 4)
    + _byte_of(target_offset, 5) * 256
    + _byte_of(target_offset, 6) * 65536
    + _byte_of(target_offset, 7) * 16777216
  );
  return v;
}

/// Decode one 8-byte 32-bit IDT gate descriptor at `offset`.
///
/// Layout: [0:2] offset 15:0, [2:4] selector, [4] reserved (must be 0),
/// [5] type/attribute byte, [6:8] offset 31:16. The attribute byte is
/// split by divisor/modulo: gate type = attr % 16, S storage = (attr/16)
/// % 2, DPL = (attr/32) % 4, P present = (attr/128) % 2.
///
/// Errors: `interrupt: idt gate32 block out of range at offset N (...)`
/// for a short block, `interrupt: idt gate32 reserved byte invalid at
/// offset N` when byte 4 is nonzero.
/// Complexity: O(1).
pub fn x86_idt_gate32_decode(data: &Vec[UInt8], offset: Int) -> Result[X86IdtGate, Str] {
  if offset < 0 || offset > data.len() - X86_IDT_GATE32_LEN {
    return _err_gate(_range_err("idt gate32 block", offset, X86_IDT_GATE32_LEN, data.len()));
  }
  let reserved: Int = _byte(data, offset + 4);
  if reserved != 0 {
    return _err_gate(_field_err("idt gate32", offset + 4, "reserved byte"));
  }
  let off_low: Int = _read_le(data, offset, 2);
  let selector: Int = _read_le(data, offset + 2, 2);
  let attr: Int = _byte(data, offset + 5);
  let off_mid: Int = _read_le(data, offset + 6, 2);
  return _ok_gate(X86IdtGate{
    target_offset: x86_idt_gate32_join(off_low, off_mid);
    code_selector: selector;
    ist_index: 0;
    gate_type: attr % 16;
    dpl: (attr / 32) % 4;
    present: (attr / 128) % 2 == 1;
    storage_segment: (attr / 16) % 2 == 1;
    long_mode: false;
  });
}

/// Decode one 16-byte 64-bit IDT gate descriptor at `offset`.
///
/// Layout: [0:2] offset 15:0, [2:4] selector, [4] IST (bits 2:0) with
/// bits 7:3 reserved, [5] type/attribute byte, [6:8] offset 31:16,
/// [8:12] offset 63:32, [12:16] reserved (must be 0).
///
/// Errors: `interrupt: idt gate64 block out of range at offset N (...)`
/// for a short block, `interrupt: idt gate64 ist/reserved byte invalid at
/// offset N` when bits 7:3 of byte 4 are set, `interrupt: idt gate64
/// reserved tail invalid at offset N` when bytes 12..16 are nonzero.
/// Complexity: O(1).
pub fn x86_idt_gate64_decode(data: &Vec[UInt8], offset: Int) -> Result[X86IdtGate, Str] {
  if offset < 0 || offset > data.len() - X86_IDT_GATE64_LEN {
    return _err_gate(_range_err("idt gate64 block", offset, X86_IDT_GATE64_LEN, data.len()));
  }
  let ist_raw: Int = _byte(data, offset + 4);
  if _bit_set_between(ist_raw, 3, 7) {
    return _err_gate(_field_err("idt gate64", offset + 4, "ist/reserved byte"));
  }
  let tail: Int = _read_le(data, offset + 12, 4);
  if tail != 0 {
    return _err_gate(_field_err("idt gate64", offset + 12, "reserved tail"));
  }
  let off_low: Int = _read_le(data, offset, 2);
  let selector: Int = _read_le(data, offset + 2, 2);
  let attr: Int = _byte(data, offset + 5);
  let off_mid: Int = _read_le(data, offset + 6, 2);
  let off_high: Int = _read_le(data, offset + 8, 4);
  return _ok_gate(X86IdtGate{
    target_offset: x86_idt_gate64_join(off_low, off_mid, off_high);
    code_selector: selector;
    ist_index: ist_raw % 8;
    gate_type: attr % 16;
    dpl: (attr / 32) % 4;
    present: (attr / 128) % 2 == 1;
    storage_segment: (attr / 16) % 2 == 1;
    long_mode: true;
  });
}

/// Build one canonical 8-byte 32-bit IDT gate descriptor.
///
/// Errors: `interrupt: idt gate32 target offset out of range` (outside
/// 0..4294967295), `interrupt: idt gate32 selector out of range` (outside
/// 0..65535), `interrupt: idt gate32 gate type out of range` (outside
/// 0..15), `interrupt: idt gate32 dpl out of range` (outside 0..3).
/// Complexity: O(1).
pub fn x86_idt_gate32_build(target_offset: Int, code_selector: Int, gate_type: Int, dpl: Int, present: Bool, storage_segment: Bool) -> Result[Vec[UInt8], Str] {
  if target_offset < 0 || target_offset > 4294967295 {
    return _err_bytes("interrupt: idt gate32 target offset out of range");
  }
  if code_selector < 0 || code_selector > 65535 {
    return _err_bytes("interrupt: idt gate32 selector out of range");
  }
  if gate_type < 0 || gate_type > 15 {
    return _err_bytes("interrupt: idt gate32 gate type out of range");
  }
  if dpl < 0 || dpl > X86_IDT_DPL_MAX {
    return _err_bytes("interrupt: idt gate32 dpl out of range");
  }
  var attr: Int = gate_type + dpl * 32;
  if storage_segment { attr = attr + 16; }
  if present { attr = attr + 128; }
  var out = Vec[UInt8].new();
  _push_le(&mut out, target_offset % 65536, 2);
  _push_le(&mut out, code_selector, 2);
  out.push(0 as UInt8);
  out.push(attr as UInt8);
  _push_le(&mut out, (target_offset / 65536) % 65536, 2);
  return _ok_bytes(out);
}

/// Build one canonical 16-byte 64-bit IDT gate descriptor. `ist_index`
/// must be 0..7 (0 = no IST stack switch). `target_offset` must be a
/// canonical non-negative address (bit 63 clear); a negative bit pattern
/// is rejected because x86-64 canonical addresses do not have bit 63 set.
///
/// Errors: `interrupt: idt gate64 target offset out of range`,
/// `interrupt: idt gate64 selector out of range`,
/// `interrupt: idt gate64 ist index out of range`,
/// `interrupt: idt gate64 gate type out of range`,
/// `interrupt: idt gate64 dpl out of range`.
/// Complexity: O(1).
pub fn x86_idt_gate64_build(target_offset: Int, code_selector: Int, ist_index: Int, gate_type: Int, dpl: Int, present: Bool, storage_segment: Bool) -> Result[Vec[UInt8], Str] {
  if target_offset < 0 {
    return _err_bytes("interrupt: idt gate64 target offset out of range");
  }
  if code_selector < 0 || code_selector > 65535 {
    return _err_bytes("interrupt: idt gate64 selector out of range");
  }
  if ist_index < 0 || ist_index > X86_IDT_IST_MAX {
    return _err_bytes("interrupt: idt gate64 ist index out of range");
  }
  if gate_type < 0 || gate_type > 15 {
    return _err_bytes("interrupt: idt gate64 gate type out of range");
  }
  if dpl < 0 || dpl > X86_IDT_DPL_MAX {
    return _err_bytes("interrupt: idt gate64 dpl out of range");
  }
  var attr: Int = gate_type + dpl * 32;
  if storage_segment { attr = attr + 16; }
  if present { attr = attr + 128; }
  var out = Vec[UInt8].new();
  _push_le(&mut out, target_offset % 65536, 2);
  _push_le(&mut out, code_selector, 2);
  out.push(ist_index as UInt8);
  out.push(attr as UInt8);
  _push_le(&mut out, (target_offset / 65536) % 65536, 2);
  _push_le(&mut out, (target_offset / 4294967296) % 4294967296, 4);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  x86 gate accessors and validation
// --------------------------------------------------

/// Assembled target offset of a decoded gate.
/// Complexity: O(1).
pub fn x86_idt_gate_target_offset(g: &X86IdtGate) -> Int {
  return g.target_offset;
}

/// Code segment selector of a decoded gate.
/// Complexity: O(1).
pub fn x86_idt_gate_selector(g: &X86IdtGate) -> Int {
  return g.code_selector;
}

/// IST index of a decoded gate (always 0 for the 32-bit form).
/// Complexity: O(1).
pub fn x86_idt_gate_ist(g: &X86IdtGate) -> Int {
  return g.ist_index;
}

/// Attribute low nibble: 0xE interrupt gate, 0xF trap gate (0x5/0x6/0x7
/// legacy forms are decoded as-is).
/// Complexity: O(1).
pub fn x86_idt_gate_type(g: &X86IdtGate) -> Int {
  return g.gate_type;
}

/// Descriptor privilege level (0..3).
/// Complexity: O(1).
pub fn x86_idt_gate_dpl(g: &X86IdtGate) -> Int {
  return g.dpl;
}

/// Present bit of a decoded gate.
/// Complexity: O(1).
pub fn x86_idt_gate_present(g: &X86IdtGate) -> Bool {
  return g.present;
}

/// S storage-segment bit of a decoded gate (always 0 for real IDT gates).
/// Complexity: O(1).
pub fn x86_idt_gate_storage(g: &X86IdtGate) -> Bool {
  return g.storage_segment;
}

/// True when the gate was decoded from the 16-byte 64-bit form.
/// Complexity: O(1).
pub fn x86_idt_gate_long_mode(g: &X86IdtGate) -> Bool {
  return g.long_mode;
}

/// True when the gate is a hardware interrupt gate (type 0xE).
/// Complexity: O(1).
pub fn x86_idt_gate_is_interrupt(g: &X86IdtGate) -> Bool {
  let t: Int = g.gate_type;
  return t == X86_IDT_TYPE_INTERRUPT;
}

/// True when the gate is a trap gate (type 0xF).
/// Complexity: O(1).
pub fn x86_idt_gate_is_trap(g: &X86IdtGate) -> Bool {
  let t: Int = g.gate_type;
  return t == X86_IDT_TYPE_TRAP;
}

/// True when the gate is usable by the CPU as an interrupt/trap gate:
/// present, not a storage segment, a nonzero code selector and type 0xE
/// or 0xF. Legacy/16-bit gate types and task gates report false.
/// Complexity: O(1).
pub fn x86_idt_gate_valid(g: &X86IdtGate) -> Bool {
  if !g.present { return false; }
  if g.storage_segment { return false; }
  let selector: Int = g.code_selector;
  if selector == 0 { return false; }
  if x86_idt_gate_is_interrupt(g) { return true; }
  if x86_idt_gate_is_trap(g) { return true; }
  return false;
}

// --------------------------------------------------
//  IDTR
// --------------------------------------------------

/// Decode the 6-byte 32-bit IDTR at `offset`: [0:2] limit, [2:6] base.
/// Errors: `interrupt: idtr32 block out of range at offset N (...)`.
/// Complexity: O(1).
pub fn x86_idtr32_decode(data: &Vec[UInt8], offset: Int) -> Result[X86Idtr, Str] {
  if offset < 0 || offset > data.len() - X86_IDTR32_LEN {
    return _err_idtr(_range_err("idtr32 block", offset, X86_IDTR32_LEN, data.len()));
  }
  return _ok_idtr(X86Idtr{
    limit: _read_le(data, offset, 2);
    base: _read_le(data, offset + 2, 4);
    long_mode: false;
  });
}

/// Decode the 10-byte 64-bit IDTR at `offset`: [0:2] limit, [2:10] base.
/// A base above 2^63-1 is held as the same negative two's-complement bit
/// pattern.
/// Errors: `interrupt: idtr64 block out of range at offset N (...)`.
/// Complexity: O(1).
pub fn x86_idtr64_decode(data: &Vec[UInt8], offset: Int) -> Result[X86Idtr, Str] {
  if offset < 0 || offset > data.len() - X86_IDTR64_LEN {
    return _err_idtr(_range_err("idtr64 block", offset, X86_IDTR64_LEN, data.len()));
  }
  return _ok_idtr(X86Idtr{
    limit: _read_le(data, offset, 2);
    base: _read_le(data, offset + 2, 8);
    long_mode: true;
  });
}

/// Build a canonical 6-byte 32-bit IDTR.
/// Errors: `interrupt: idtr32 limit out of range` (outside 0..65535),
/// `interrupt: idtr32 base out of range` (outside 0..4294967295).
/// Complexity: O(1).
pub fn x86_idtr32_build(limit: Int, base: Int) -> Result[Vec[UInt8], Str] {
  if limit < 0 || limit > 65535 {
    return _err_bytes("interrupt: idtr32 limit out of range");
  }
  if base < 0 || base > 4294967295 {
    return _err_bytes("interrupt: idtr32 base out of range");
  }
  var out = Vec[UInt8].new();
  _push_le(&mut out, limit, 2);
  _push_le(&mut out, base, 4);
  return _ok_bytes(out);
}

/// Build a canonical 10-byte 64-bit IDTR. The base must be a canonical
/// non-negative address (bit 63 clear).
/// Errors: `interrupt: idtr64 limit out of range` (outside 0..65535),
/// `interrupt: idtr64 base out of range` (negative).
/// Complexity: O(1).
pub fn x86_idtr64_build(limit: Int, base: Int) -> Result[Vec[UInt8], Str] {
  if limit < 0 || limit > 65535 {
    return _err_bytes("interrupt: idtr64 limit out of range");
  }
  if base < 0 {
    return _err_bytes("interrupt: idtr64 base out of range");
  }
  var out = Vec[UInt8].new();
  _push_le(&mut out, limit, 2);
  _push_le(&mut out, base, 8);
  return _ok_bytes(out);
}

/// Raw 16-bit byte limit of a decoded IDTR.
/// Complexity: O(1).
pub fn x86_idtr_limit(r: &X86Idtr) -> Int {
  return r.limit;
}

/// Base address of a decoded IDTR (32-bit value or 64-bit bit pattern).
/// Complexity: O(1).
pub fn x86_idtr_base(r: &X86Idtr) -> Int {
  return r.base;
}

/// True when the IDTR was decoded from the 10-byte 64-bit form.
/// Complexity: O(1).
pub fn x86_idtr_long_mode(r: &X86Idtr) -> Bool {
  return r.long_mode;
}

/// Byte span described by the IDTR (`limit + 1`).
/// Complexity: O(1).
pub fn x86_idtr_span(r: &X86Idtr) -> Int {
  return r.limit + 1;
}

/// Number of gate descriptors the IDTR can hold: `(limit + 1) / 16` in
/// long mode, `(limit + 1) / 8` otherwise. Returns -1 when the span is
/// not a whole multiple of the descriptor size (a malformed IDTR).
/// Complexity: O(1).
pub fn x86_idtr_entry_count(r: &X86Idtr) -> Int {
  var entry: Int = 8;
  if r.long_mode { entry = 16; }
  let total: Int = r.limit + 1;
  let rem: Int = total % entry;
  if rem != 0 {
    return -1;
  }
  return total / entry;
}

// --------------------------------------------------
//  x86 well-known vectors
// --------------------------------------------------

/// Architectural mnemonic of vector `v` (0..255): DE, DB, NMI, BP, OF,
/// BR, UD, NM, DF, CSO (obsolete coprocessor segment overrun), TS, NP,
/// SS, GP, PF, MF, AC, MC, XM, VE, CP. Vectors 15 and 22-31 are
/// "RESERVED"; 32-255 are "USER". Out-of-range values return "".
/// Complexity: O(1).
pub fn x86_vector_name(v: Int) -> Str {
  if v < 0 { return ""; }
  if v > 255 { return ""; }
  if v == 0 { return "DE"; }
  if v == 1 { return "DB"; }
  if v == 2 { return "NMI"; }
  if v == 3 { return "BP"; }
  if v == 4 { return "OF"; }
  if v == 5 { return "BR"; }
  if v == 6 { return "UD"; }
  if v == 7 { return "NM"; }
  if v == 8 { return "DF"; }
  if v == 9 { return "CSO"; }
  if v == 10 { return "TS"; }
  if v == 11 { return "NP"; }
  if v == 12 { return "SS"; }
  if v == 13 { return "GP"; }
  if v == 14 { return "PF"; }
  if v == 16 { return "MF"; }
  if v == 17 { return "AC"; }
  if v == 18 { return "MC"; }
  if v == 19 { return "XM"; }
  if v == 20 { return "VE"; }
  if v == 21 { return "CP"; }
  if v <= 31 { return "RESERVED"; }
  return "USER";
}

/// Vector class: "exception" for 0-21, "reserved" for 15 and 22-31,
/// "user" for 32-255, "invalid" outside 0..255.
/// Complexity: O(1).
pub fn x86_vector_class(v: Int) -> Str {
  if v < 0 { return "invalid"; }
  if v <= 21 { return "exception"; }
  if v <= 31 { return "reserved"; }
  if v <= 255 { return "user"; }
  return "invalid";
}

/// True when vector `v` pushes an architectural error code: #DF (8),
/// #TS-#PF (10-14), #AC (17) and #CP (21). All other vectors, including
/// the obsolete 9 and the reserved range, report false.
/// Complexity: O(1).
pub fn x86_vector_has_error_code(v: Int) -> Bool {
  if v == 8 { return true; }
  if v >= 10 && v <= 14 { return true; }
  if v == 17 { return true; }
  if v == 21 { return true; }
  return false;
}

// --------------------------------------------------
//  GIC distributor register words
// --------------------------------------------------

/// Read one little-endian 32-bit distributor register word at byte
/// `offset`. A u32 with bit 31 set is returned as the same negative
/// two's-complement Int bit pattern.
/// Errors: `interrupt: distributor register out of range at offset N
/// (need 4 bytes, have Y)`.
/// Complexity: O(1).
pub fn gicd_word(data: &Vec[UInt8], offset: Int) -> Result[Int, Str] {
  if offset < 0 || offset > data.len() - 4 {
    return _err_int(_range_err("distributor register", offset, 4, data.len()));
  }
  return _ok_int(_read_le(data, offset, 4));
}

/// Decode GICD_CTLR at `offset` in strict mode.
///
/// Bits: 0 EnableGrp0, 1 EnableGrp1, 2 EnableGrp1S, 3 EnableGrp1NS,
/// 4 ARE_S, 5 ARE_NS, 6 DS (GICv3.x), 8 nASSGIreq (GICv4.1), 31 RWP.
/// The reserved bits of that layout are bit 7 and bits 9..30; a word
/// with any of them set is rejected (use `gicd_ctlr_reserved_bits` to
/// inspect and `gicd_word` for a lenient read).
///
/// Errors: the `gicd_word` block error, plus `interrupt: distributor
/// ctlr reserved bits set invalid at offset N`.
/// Complexity: O(1).
pub fn gicd_ctlr_decode(data: &Vec[UInt8], offset: Int) -> Result[GicdCtlr, Str] {
  let wr = gicd_word(data, offset);
  if !wr.is_ok {
    return _err_ctl(wr.error);
  }
  let raw: Int = wr.value;
  if gicd_ctlr_reserved_bits(raw) != 0 {
    return _err_ctl(_field_err("distributor ctlr", offset, "reserved bits set"));
  }
  let b0: Int = _byte_of(raw, 0);
  let b1: Int = _byte_of(raw, 1);
  return _ok_ctl(GicdCtlr{
    enable_grp0: _byte_bit(b0, 0);
    enable_grp1: _byte_bit(b0, 1);
    enable_grp1s: _byte_bit(b0, 2);
    enable_grp1ns: _byte_bit(b0, 3);
    are_s: _byte_bit(b0, 4);
    are_ns: _byte_bit(b0, 5);
    disable_security: _byte_bit(b0, 6);
    nassgi_req: _byte_bit(b1, 0);
    rwp: _word_bit(raw, 31);
    raw: raw;
  });
}

/// Mask of the GICD_CTLR reserved bits that are set in `raw`: bit 7
/// (value 128) plus any of bits 9..30. Returns 0 when the word uses only
/// the documented fields.
/// Complexity: O(1).
pub fn gicd_ctlr_reserved_bits(raw: Int) -> Int {
  var m: Int = 0;
  if _word_bit(raw, 7) {
    m = m + 128;
  }
  var k = 9;
  var bit_val: Int = 512;
  while k <= 30 {
    if _word_bit(raw, k) {
      m = m + bit_val;
    }
    bit_val = bit_val * 2;
    k = k + 1;
  }
  return m;
}

/// Packed group-enable mask of a decoded GICD_CTLR: bit 0 EnableGrp0,
/// bit 1 EnableGrp1, bit 2 EnableGrp1S, bit 3 EnableGrp1NS (0..15).
/// Complexity: O(1).
pub fn gicd_ctlr_enable_mask(c: &GicdCtlr) -> Int {
  var m: Int = 0;
  if c.enable_grp0 { m = m + 1; }
  if c.enable_grp1 { m = m + 2; }
  if c.enable_grp1s { m = m + 4; }
  if c.enable_grp1ns { m = m + 8; }
  return m;
}

/// Decode GICD_TYPER at `offset` in strict mode.
///
/// GICv2 bits: [4:0] ITLinesNumber, [7:5] CPUNumber, [10] SecurityExtn.
/// Note-level extras: [8] ESPI and [31:27] ESPI range (GICv3.1), [16]
/// MBIS and [17] LSPI (GICv3). Bit 9 is reserved in every revision of
/// the layout implemented here and is rejected.
///
/// Errors: the `gicd_word` block error, plus `interrupt: distributor
/// typer reserved bit 9 set invalid at offset N`.
/// Complexity: O(1).
pub fn gicd_typer_decode(data: &Vec[UInt8], offset: Int) -> Result[GicdTyper, Str] {
  let wr = gicd_word(data, offset);
  if !wr.is_ok {
    return _err_typ(wr.error);
  }
  let raw: Int = wr.value;
  if gicd_typer_reserved_bits(raw) != 0 {
    return _err_typ(_field_err("distributor typer", offset, "reserved bit 9 set"));
  }
  let lines: Int = gic_max_interrupts(raw);
  return _ok_typ(GicdTyper{
    it_lines_number: _byte_of(raw, 0) % 32;
    cpu_count: gic_cpu_count(raw);
    espi: gic_has_espis(raw);
    espi_range: gic_espi_range(raw);
    security_extn: gic_has_security_extensions(raw);
    mbis: gic_has_mbis(raw);
    lspi: gic_has_lpis(raw);
    max_interrupts: lines;
    raw: raw;
  });
}

/// Mask of the GICD_TYPER reserved bits that are set in `typer`: bit 9
/// (value 512) or 0. Every other undefined bit is revision-dependent
/// (GICv3/GICv3.1 reuse them) and is left to the caller.
/// Complexity: O(1).
pub fn gicd_typer_reserved_bits(typer: Int) -> Int {
  if _word_bit(typer, 9) {
    return 512;
  }
  return 0;
}

/// Total number of interrupt IDs from ITLinesNumber: 32*(N+1), or the
/// documented 1020 cap when ITLinesNumber is 31.
/// Complexity: O(1).
pub fn gic_max_interrupts(typer: Int) -> Int {
  let lines: Int = _byte_of(typer, 0) % 32;
  if lines == 31 {
    return 1020;
  }
  return (lines + 1) * 32;
}

/// Number of SPI IDs (32 and above) from ITLinesNumber:
/// `gic_max_interrupts(typer) - 32`.
/// Complexity: O(1).
pub fn gic_max_spi_count(typer: Int) -> Int {
  return gic_max_interrupts(typer) - GIC_FIRST_SPI;
}

/// Highest valid interrupt ID from ITLinesNumber:
/// `gic_max_interrupts(typer) - 1` (31, 127, ..., 1019).
/// Complexity: O(1).
pub fn gic_highest_valid_id(typer: Int) -> Int {
  return gic_max_interrupts(typer) - 1;
}

/// Number of CPU interfaces: CPUNumber (bits [7:5]) + 1, so 1..8.
/// Complexity: O(1).
pub fn gic_cpu_count(typer: Int) -> Int {
  let b0: Int = _byte_of(typer, 0);
  return ((b0 / 32) % 8) + 1;
}

/// True when GICD_TYPER bit 10 reports implemented security extensions.
/// Complexity: O(1).
pub fn gic_has_security_extensions(typer: Int) -> Bool {
  let b1: Int = _byte_of(typer, 1);
  return _byte_bit(b1, 2);
}

/// True when GICD_TYPER bit 16 reports message-based interrupts (MBIS).
/// Complexity: O(1).
pub fn gic_has_mbis(typer: Int) -> Bool {
  let b2: Int = _byte_of(typer, 2);
  return _byte_bit(b2, 0);
}

/// True when GICD_TYPER bit 17 reports LPI support (GICv3, note-level).
/// Complexity: O(1).
pub fn gic_has_lpis(typer: Int) -> Bool {
  let b2: Int = _byte_of(typer, 2);
  return _byte_bit(b2, 1);
}

/// True when GICD_TYPER bit 8 reports extended SPI support (GICv3.1,
/// note-level; documented as limited).
/// Complexity: O(1).
pub fn gic_has_espis(typer: Int) -> Bool {
  let b1: Int = _byte_of(typer, 1);
  return _byte_bit(b1, 0);
}

/// Number of extended SPI IDs advertised by bits [31:27] (GICv3.1,
/// note-level): `(field + 1) * 32`, or 0 when bit 8 is clear. The field
/// is a count of 32-ID blocks, so the result is a multiple of 32 up to
/// 1024.
/// Complexity: O(1).
pub fn gic_espi_range(typer: Int) -> Int {
  if !gic_has_espis(typer) {
    return 0;
  }
  let b3: Int = _byte_of(typer, 3);
  return (((b3 / 8) % 32) + 1) * 32;
}

/// Highest ESPI ID implied by `typer` (`4096 + range - 1`), or -1 when
/// the ESPI bit is clear. Note-level and documented as limited.
/// Complexity: O(1).
pub fn gic_espi_max_id(typer: Int) -> Int {
  let r: Int = gic_espi_range(typer);
  if r == 0 {
    return -1;
  }
  return ESPI_BASE_INTID + r - 1;
}

/// True when `irq` is within the SGI/PPI/SPI range implied by `typer`
/// (0..`gic_highest_valid_id(typer)`). ESPI IDs are outside this check;
/// use `gic_is_espi` and `gic_espi_range` for those.
/// Complexity: O(1).
pub fn gic_irq_in_range(typer: Int, irq: Int) -> Bool {
  if irq < 0 {
    return false;
  }
  return irq <= gic_highest_valid_id(typer);
}

// --------------------------------------------------
//  GIC IRQ ID classification
// --------------------------------------------------

/// Class of interrupt ID `irq`: "SGI" 0-15, "PPI" 16-31, "SPI" 32-1019,
/// "reserved" 1020-1023, "ESPI" 4096-5119 (GICv3.1, note-level) and
/// "invalid" everywhere else.
/// Complexity: O(1).
pub fn gic_irq_class(irq: Int) -> Str {
  if irq < 0 { return "invalid"; }
  if irq < GIC_SGI_COUNT { return "SGI"; }
  if irq < GIC_FIRST_SPI { return "PPI"; }
  if irq <= GIC_MAX_INTID { return "SPI"; }
  if irq <= 1023 { return "reserved"; }
  if gic_is_espi(irq) { return "ESPI"; }
  return "invalid";
}

/// Class of a GICv3.1 extended SPI ID: "ESPI" for 4096-5119, else
/// "invalid". Note-level and documented as limited.
/// Complexity: O(1).
pub fn gic_espi_class(irq: Int) -> Str {
  if gic_is_espi(irq) {
    return "ESPI";
  }
  return "invalid";
}

/// True when `irq` is an SGI (0-15).
/// Complexity: O(1).
pub fn gic_is_sgi(irq: Int) -> Bool {
  if irq < 0 { return false; }
  return irq < GIC_SGI_COUNT;
}

/// True when `irq` is a PPI (16-31).
/// Complexity: O(1).
pub fn gic_is_ppi(irq: Int) -> Bool {
  if irq < GIC_SGI_COUNT { return false; }
  return irq < GIC_FIRST_SPI;
}

/// True when `irq` is a GICv2 SPI (32-1019).
/// Complexity: O(1).
pub fn gic_is_spi(irq: Int) -> Bool {
  if irq < GIC_FIRST_SPI { return false; }
  return irq <= GIC_MAX_INTID;
}

/// True when `irq` is in the GICv3.1 extended SPI window (4096-5119).
/// Note-level and documented as limited: whether the window is actually
/// implemented must be confirmed from GICD_TYPER bit 8 / bits [31:27].
/// Complexity: O(1).
pub fn gic_is_espi(irq: Int) -> Bool {
  if irq < ESPI_BASE_INTID { return false; }
  return irq < ESPI_BASE_INTID + GIC_ESPI_COUNT;
}

// --------------------------------------------------
//  GIC distributor bitmaps
// --------------------------------------------------

/// Byte offset of the 4-byte register word that holds the bit for `irq`
/// inside bitmap family `base` (GICD_IGROUPR starts at ID 0, the
/// enable/pending bitmaps at SPI 32).
///
/// Errors: `interrupt: unknown distributor bitmap base N`,
/// `interrupt: irq N outside the GICv2 range 0..1019`,
/// `interrupt: irq N is an SGI/PPI; bitmap base B covers SPIs only`.
/// Complexity: O(1).
pub fn gicd_bitmap_offset(base: Int, irq: Int) -> Result[Int, Str] {
  if !_bitmap_base_ok(base) {
    return _err_int("interrupt: unknown distributor bitmap base " + int_to_string(base));
  }
  if irq < 0 || irq > GIC_MAX_INTID {
    return _err_int(_irq_err(irq, "outside the GICv2 range 0..1019"));
  }
  if base != GICD_IGROUPR && irq < GIC_FIRST_SPI {
    return _err_int(_irq_err(irq, "is an SGI/PPI; bitmap base " + int_to_string(base) + " covers SPIs only"));
  }
  return _ok_int(base + 4 * _bitmap_word_index(base, irq));
}

/// Extract the bitmap bit for `irq` from the 4-byte word at
/// `gicd_bitmap_offset(base, irq)` inside the caller's register block.
/// Bit order is little-endian: bit `irq % 32` of the word, so byte
/// `(irq % 32) / 8` and bit `(irq % 32) % 8` within that byte.
///
/// Errors: the `gicd_bitmap_offset` errors, plus `interrupt:
/// distributor bitmap word out of range at offset N (need 4 bytes,
/// have Y)` when the block is too short.
/// Complexity: O(1).
pub fn gicd_bitmap_bit(data: &Vec[UInt8], base: Int, irq: Int) -> Result[Bool, Str] {
  let wr = gicd_bitmap_offset(base, irq);
  if !wr.is_ok {
    return _err_bool(wr.error);
  }
  let word: Int = wr.value;
  if word > data.len() - 4 {
    return _err_bool(_range_err("distributor bitmap word", word, 4, data.len()));
  }
  let bit_index: Int = irq % 32;
  let pos: Int = word + bit_index / 8;
  let b: Int = _byte(data, pos);
  return _ok_bool(_byte_bit(b, bit_index % 8));
}

/// Convenience wrapper: the GICD_IGROUPR (group) bit for `irq`, which is
/// the only bitmap covering SGI/PPI IDs as well as SPIs.
/// Errors: as `gicd_bitmap_bit` with base `GICD_IGROUPR`.
/// Complexity: O(1).
pub fn gicd_group_bit(data: &Vec[UInt8], irq: Int) -> Result[Bool, Str] {
  return gicd_bitmap_bit(data, GICD_IGROUPR, irq);
}

/// Number of 4-byte words needed to cover `highest_irq` in bitmap family
/// `base`: 1..32. This is the size check companion of `gicd_bitmap_span`.
/// Errors: the `gicd_bitmap_offset` base/irq errors.
/// Complexity: O(1).
pub fn gicd_bitmap_word_count(base: Int, highest_irq: Int) -> Result[Int, Str] {
  if !_bitmap_base_ok(base) {
    return _err_int("interrupt: unknown distributor bitmap base " + int_to_string(base));
  }
  if highest_irq < 0 || highest_irq > GIC_MAX_INTID {
    return _err_int(_irq_err(highest_irq, "outside the GICv2 range 0..1019"));
  }
  if base != GICD_IGROUPR && highest_irq < GIC_FIRST_SPI {
    return _err_int(_irq_err(highest_irq, "is an SGI/PPI; bitmap base " + int_to_string(base) + " covers SPIs only"));
  }
  return _ok_int(_bitmap_word_index(base, highest_irq) + 1);
}

/// Validate that `word_count` 4-byte bitmap words starting at `base` fit
/// inside the register block, and return the byte span. A GICv2 bitmap
/// can never need more than 32 words (32*32 = 1024 IDs), so larger sizes
/// are rejected as impossible.
///
/// Errors: `interrupt: unknown distributor bitmap base N`,
/// `interrupt: impossible bitmap size N words at base B`,
/// `interrupt: distributor bitmap block out of range at offset N (...)`.
/// Complexity: O(1).
pub fn gicd_bitmap_span(data: &Vec[UInt8], base: Int, word_count: Int) -> Result[Int, Str] {
  if !_bitmap_base_ok(base) {
    return _err_int("interrupt: unknown distributor bitmap base " + int_to_string(base));
  }
  if word_count < 1 || word_count > GIC_MAX_BITMAP_WORDS {
    return _err_int("interrupt: impossible bitmap size " + int_to_string(word_count) + " words at base " + int_to_string(base));
  }
  let need: Int = 4 * word_count;
  if base > data.len() - need {
    return _err_int(_range_err("distributor bitmap block", base, need, data.len()));
  }
  return _ok_int(need);
}

// --------------------------------------------------
//  GIC per-IRQ priority and targets
// --------------------------------------------------

/// Byte offset of the GICD_IPRIORITYR byte for `irq` (one byte per
/// interrupt ID). The top bits actually implemented are
/// implementation-defined; the raw 8-bit byte is returned.
/// Errors: `interrupt: irq N outside the GICv2 range 0..1019`.
/// Complexity: O(1).
pub fn gicd_priority_offset(irq: Int) -> Result[Int, Str] {
  if irq < 0 || irq > GIC_MAX_INTID {
    return _err_int(_irq_err(irq, "outside the GICv2 range 0..1019"));
  }
  return _ok_int(GICD_IPRIORITYR + irq);
}

/// Read the raw 8-bit GICD_IPRIORITYR priority of `irq` from the
/// register block.
/// Errors: the `gicd_priority_offset` error, plus `interrupt:
/// distributor priority byte out of range at offset N (need 1 byte,
/// have Y)`.
/// Complexity: O(1).
pub fn gicd_priority(data: &Vec[UInt8], irq: Int) -> Result[Int, Str] {
  let or_result = gicd_priority_offset(irq);
  if !or_result.is_ok {
    return _err_int(or_result.error);
  }
  let pos: Int = or_result.value;
  if pos > data.len() - 1 {
    return _err_int(_range_err("distributor priority byte", pos, 1, data.len()));
  }
  return _ok_int(_byte(data, pos));
}

/// Byte offset of the GICD_ITARGETSR byte for `irq` (one byte per
/// interrupt ID; bits [7:0] are the CPU target mask for that IRQ).
/// Errors: `interrupt: irq N outside the GICv2 range 0..1019`.
/// Complexity: O(1).
pub fn gicd_target_offset(irq: Int) -> Result[Int, Str] {
  if irq < 0 || irq > GIC_MAX_INTID {
    return _err_int(_irq_err(irq, "outside the GICv2 range 0..1019"));
  }
  return _ok_int(GICD_ITARGETSR + irq);
}

/// Read the GICD_ITARGETSR byte of `irq`. The result reports
/// `writable: false` for SGI 0-15 and PPI 16-31 (read-only in GICv2)
/// and `writable: true` for SPIs.
/// Errors: the `gicd_target_offset` error, plus `interrupt:
/// distributor target byte out of range at offset N (need 1 byte,
/// have Y)`.
/// Complexity: O(1).
pub fn gicd_target(data: &Vec[UInt8], irq: Int) -> Result[GicdTarget, Str] {
  let or_result = gicd_target_offset(irq);
  if !or_result.is_ok {
    return _err_tgt(or_result.error);
  }
  let pos: Int = or_result.value;
  if pos > data.len() - 1 {
    return _err_tgt(_range_err("distributor target byte", pos, 1, data.len()));
  }
  return _ok_tgt(GicdTarget{
    irq: irq;
    targets: _byte(data, pos);
    writable: irq >= GIC_FIRST_SPI;
  });
}

/// True when the GICD_ITARGETSR byte of `irq` is writable: false for
/// SGI 0-15 and PPI 16-31, true for SPI 32 and above.
/// Complexity: O(1).
pub fn gicd_target_writable(irq: Int) -> Bool {
  return irq >= GIC_FIRST_SPI;
}

// --------------------------------------------------
//  GICD_TYPER2 (note-level)
// --------------------------------------------------

/// Decode the GICv3.1 GICD_TYPER2 register (offset 0x00C) as a
/// note-level extra: `vid` is bits [4:0], `vil` is bit 7 and
/// `nassgi_cap` is bit 8. Documented as limited: this decoder does not
/// claim the full GICv4.1 semantics of the register, only the three
/// documented fields; no reserved-bit rejection is performed.
/// Errors: the `gicd_word` block error.
/// Complexity: O(1).
pub fn gicd_typer2_decode(data: &Vec[UInt8], offset: Int) -> Result[GicdTyper2, Str] {
  let wr = gicd_word(data, offset);
  if !wr.is_ok {
    return _err_typ2(wr.error);
  }
  let raw: Int = wr.value;
  let b0: Int = _byte_of(raw, 0);
  return _ok_typ2(GicdTyper2{
    vid: b0 % 32;
    vil: _byte_bit(b0, 7);
    nassgi_cap: _byte_bit(_byte_of(raw, 1), 0);
    raw: raw;
  });
}
