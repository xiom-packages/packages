// XIOM -- xiom.crc: parameterized CRC-8/16/32 with named presets and
// known-answer vectors
// Port task: implement a pure-XIOM (no FFI), bitwise, table-free CRC engine
// over the classic Rocksoft / CRC-RevEng parameter model plus the standard
// named presets, then prove it green with scripts/port.ps1.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Parameter model (full rules in SPEC.md):
//   width   register width in bits: exactly 8, 16 or 32; any other value
//           makes crc_compute return 0
//   poly    generator polynomial in NORMAL (MSB-first) form, masked to
//           `width` bits. When refin is true the reflected form is derived
//           internally (_crc_reflect), so callers always pass the normal
//           form -- exactly as the named presets below do
//   init    initial register contents in normal form, masked to `width` bits.
//           When refin is true the register starts reflected (this is what
//           makes e.g. CRC-16/RIELLO work)
//   refin   true: each input byte is processed LSB-first with the reflected
//           polynomial; false: MSB-first with poly
//   refout  output reflection: when refout differs from refin, the final
//           register is reflected before xorout
//   xorout  final XOR value, masked to `width` bits
//
// The register stays a non-negative Int below 2^width, maintained with
// arithmetic truncation (`% 2^width`) rather than `&` on a large mask:
// v0.61.3 miscompiles bitwise AND on operands with bit 31 set (BUG 25 #7,
// documented in xiom.bits.bitwise and xiom.collect.bitmap). The
// implementation is bitwise and table-free on purpose: module-level [256]
// tables mis-materialize in v0.61.3 (see the xiom.compress.gzip notes), and
// all state here is local anyway.
//
// v0.61.3 notes that shaped this module:
//   * free functions only (no methods, no lambdas, no Vec[fn] dispatch);
//   * no Result/Option is constructed and no struct type is needed;
//   * the loops use only `^`, `>>`, `<<`, `*`, `+`, `%`, comparisons and
//     small-mask `&` (`& 1`, `& 255`); the top-bit test is a comparison;
//   * poly/init/xorout and the final value are truncated arithmetically, so
//     a 32-bit mask is never the right operand of `&`.

module xiom.crc

// Low `width` bits of the non-negative value `v`, arithmetically. `%` is the
// proven truncation in this compiler (xiom.packet packs u32 fields with it);
// `v & 0xFFFFFFFF` is not usable because of the large-Int AND bug. The caller
// guarantees that `width` is 8, 16 or 32.
fn _crc_trunc(v: Int, width: Int) -> Int {
  if width == 8 {
    return v % 256;
  }
  if width == 16 {
    return v % 65536;
  }
  return v % 4294967296;
}

// Value of the single highest bit of `width` (0x80, 0x8000, 0x80000000).
fn _crc_top_bit(width: Int) -> Int {
  if width == 8 {
    return 128;
  }
  if width == 16 {
    return 32768;
  }
  return 2147483648;
}

// Reverse the low `width` bits of `value`: bit k <-> bit width-1-k.
// Multiplication/addition is used instead of `|` to stay within the
// operators already proven throughout the stdlib bit handlers.
fn _crc_reflect(value: Int, width: Int) -> Int {
  var out = 0;
  var v = value;
  var i = 0;
  while i < width {
    out = out * 2 + (v & 1);
    v = v >> 1;
    i = i + 1;
  }
  return out;
}

/// Compute a CRC with the full parameter set of the classic Rocksoft /
/// CRC-RevEng model. Returns the checksum as a non-negative Int in
/// [0, 2^width - 1], or 0 when `width` is not one of 8, 16 or 32.
///
/// `poly`, `init` and `xorout` are given in normal form, must be
/// non-negative and are masked to `width` bits. `refin` processes each byte
/// LSB-first with the reflected polynomial and a reflected register;
/// `refout`, when it differs from refin, reflects the final register before
/// `xorout` is applied. Complexity: O(data.len()) time, O(1) space
/// (8 bit-steps per byte).
pub fn crc_compute(data: &Vec[UInt8], width: Int, poly: Int, init: Int, refin: Bool, refout: Bool, xorout: Int) -> Int {
  if width != 8 && width != 16 && width != 32 {
    return 0;
  }
  let p = _crc_trunc(poly, width);
  var reg = _crc_trunc(init, width);
  if refin {
    reg = _crc_reflect(reg, width);
    let rpoly = _crc_reflect(p, width);
    var i = 0;
    while i < data.len() {
      let b = (data[i] as Int) & 255;
      reg = reg ^ b;
      var j = 0;
      while j < 8 {
        if (reg & 1) == 1 {
          reg = (reg >> 1) ^ rpoly;
        } else {
          reg = reg >> 1;
        }
        j = j + 1;
      }
      i = i + 1;
    }
  } else {
    let top = _crc_top_bit(width);
    var i = 0;
    while i < data.len() {
      let b = (data[i] as Int) & 255;
      reg = reg ^ (b << (width - 8));
      var j = 0;
      while j < 8 {
        if reg >= top {
          reg = (reg << 1) ^ p;
        } else {
          reg = reg << 1;
        }
        reg = _crc_trunc(reg, width);
        j = j + 1;
      }
      i = i + 1;
    }
  }
  if refout != refin {
    reg = _crc_reflect(reg, width);
  }
  return reg ^ _crc_trunc(xorout, width);
}

/// True when crc_compute(data, width, poly, init, refin, refout, xorout)
/// equals `expected`. Convenience wrapper for verification paths; the
/// parameters follow crc_compute exactly.
pub fn crc_matches(data: &Vec[UInt8], width: Int, poly: Int, init: Int, refin: Bool, refout: Bool, xorout: Int, expected: Int) -> Bool {
  return crc_compute(data, width, poly, init, refin, refout, xorout) == expected;
}

/// CRC-32/IEEE (CRC-32, zlib, PKZIP, Ethernet): normal polynomial
/// 0x04C11DB7 (reflected 0xEDB88320), init 0xFFFFFFFF, refin/refout true,
/// xorout 0xFFFFFFFF. Check ("123456789") = 0xCBF43926 (3421780262);
/// empty input = 0. Complexity: O(data.len()).
pub fn crc32_ieee(data: &Vec[UInt8]) -> Int {
  return crc_compute(data, 32, 79764919, 4294967295, true, true, 4294967295);
}

/// CRC-32C / Castagnoli (iSCSI, SSE4.2): normal polynomial 0x1EDC6F41
/// (reflected 0x82F63B78), init 0xFFFFFFFF, refin/refout true, xorout
/// 0xFFFFFFFF. Check ("123456789") = 0xE3069283 (3808858755).
/// Complexity: O(data.len()).
pub fn crc32c(data: &Vec[UInt8]) -> Int {
  return crc_compute(data, 32, 517762881, 4294967295, true, true, 4294967295);
}

/// CRC-16/CCITT-FALSE (CRC-16/IBM-3740): normal polynomial 0x1021, init
/// 0xFFFF, refin/refout false, xorout 0. Check ("123456789") = 0x29B1
/// (10673); empty input = 0xFFFF (65535, the init survives). Complexity:
/// O(data.len()).
pub fn crc16_ccitt_false(data: &Vec[UInt8]) -> Int {
  return crc_compute(data, 16, 4129, 65535, false, false, 0);
}

/// CRC-16/ARC (CRC-16/IBM, CRC-16/LHA): normal polynomial 0x8005 (reflected
/// 0xA001), init 0, refin/refout true, xorout 0. Check ("123456789") =
/// 0xBB3D (47933); empty input = 0. Complexity: O(data.len()).
pub fn crc16_arc(data: &Vec[UInt8]) -> Int {
  return crc_compute(data, 16, 32773, 0, true, true, 0);
}

/// CRC-8 (CRC-8/SMBUS): normal polynomial 0x07, init 0, refin/refout false,
/// xorout 0. Check ("123456789") = 0xF4 (244); empty input = 0.
/// Complexity: O(data.len()).
pub fn crc8(data: &Vec[UInt8]) -> Int {
  return crc_compute(data, 8, 7, 0, false, false, 0);
}
