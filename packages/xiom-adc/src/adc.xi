// XIOM -- xiom.adc: ADC conversion and configuration codecs
// Port task: greenfield pure-XIOM port (no FFI) of the deterministic subset
// of ADC device handling: resolution and full-scale math, channel/mux and
// gain selection, reference selection, integer raw-to-voltage scaling,
// averaging/oversampling helpers, sample-rate tables and an ADS1x15-style
// 16-bit configuration register codec (MUX/PGA/MODE/DR/COMP fields).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Everything is integer math in microvolts (uV) and nanovolts (nV): there is
// no float type anywhere. The generic scaling path follows the documented
// formula vref_uv * raw / full-scale / gain with one truncation per division;
// the differential path divides by 2^(bits-1), the magnitude of the most
// negative two's complement code, so codes map to -vref/gain..+vref/gain.
//
// The concrete device is the ADS1x15 family (ADS1015 12-bit, ADS1115
// 16-bit). Its 16-bit configuration register packs, from bit 15 down:
// OS[15] MUX[14:12] PGA[11:9] MODE[8] DR[7:5] COMP_MODE[4] COMP_POL[3]
// COMP_LAT[2] COMP_QUE[1:0]; the register is transmitted big-endian and its
// documented power-on default 0x8583 is pinned in the tests.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no self methods, no lambdas, no Vec[fn] dispatch;
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results directly inside other functions
//     miscompiles);
//   * no Str value is compared with `==` (BUG 17: `==` on a Str from a
//     Vec[Str] lowers to a pointer compare); this module only returns Str
//     labels and never matches them, so the bug is unreachable here;
//   * every byte read from a Vec[UInt8] is widened with
//     `(x as Int) & 0xFF` before entering Int arithmetic;
//   * `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that
//     yields an empty vector): fields are bound to typed locals first;
//   * no Vec[Float64] and no Vec[StructType]: an AdcStats row is returned by
//     value from one leaf constructor;
//   * bit composition and extraction use multiplication and division by
//     powers of two, never a shift on a value that could carry the sign bit;
//   * ceil division is q + (r > 0 ? 1 : 0), never (a + b - 1) / b; plain
//     division truncates toward zero (verified: -7 / 2 = -3).

module xiom.adc

use xiom.convert;

// --------------------------------------------------
//  Constants: resolution, modes, references
// --------------------------------------------------

/// Lowest supported resolution in bits.
pub const ADC_RES_MIN: Int = 8;
/// Highest supported resolution in bits.
pub const ADC_RES_MAX: Int = 24;
/// Single-ended input mode: raw codes are unsigned 0..2^bits-1.
pub const ADC_SINGLE_ENDED: Int = 0;
/// Differential input mode: raw codes are two's complement.
pub const ADC_DIFFERENTIAL: Int = 1;
/// Internal reference selector (the ADS1x15 internal 2.048 V reference).
pub const ADC_REF_INTERNAL: Int = 0;
/// External reference selector: the caller supplies the reference in uV.
pub const ADC_REF_EXTERNAL: Int = 1;
/// The ADS1x15 internal reference in microvolts (2.048 V).
pub const ADC_INTERNAL_REF_UV: Int = 2048000;

// --------------------------------------------------
//  Constants: ADS1x15 MUX, mode, status, comparator
// --------------------------------------------------

/// ADS1x15 MUX setting 000: differential AIN0 - AIN1.
pub const ADS_MUX_DIFF_0_1: Int = 0;
/// ADS1x15 MUX setting 001: differential AIN0 - AIN3.
pub const ADS_MUX_DIFF_0_3: Int = 1;
/// ADS1x15 MUX setting 010: differential AIN1 - AIN3.
pub const ADS_MUX_DIFF_1_3: Int = 2;
/// ADS1x15 MUX setting 011: differential AIN2 - AIN3.
pub const ADS_MUX_DIFF_2_3: Int = 3;
/// ADS1x15 MUX setting 100: single-ended AIN0.
pub const ADS_MUX_SINGLE_0: Int = 4;
/// ADS1x15 MUX setting 101: single-ended AIN1.
pub const ADS_MUX_SINGLE_1: Int = 5;
/// ADS1x15 MUX setting 110: single-ended AIN2.
pub const ADS_MUX_SINGLE_2: Int = 6;
/// ADS1x15 MUX setting 111: single-ended AIN3.
pub const ADS_MUX_SINGLE_3: Int = 7;
/// ADS1x15 MODE field: continuous conversion.
pub const ADS_MODE_CONTINUOUS: Int = 0;
/// ADS1x15 MODE field: single-shot (power-down between conversions).
pub const ADS_MODE_SINGLE_SHOT: Int = 1;
/// OS field: no effect / device not converting.
pub const ADS_OS_IDLE: Int = 0;
/// OS field: start a single conversion (reads back 1 while busy in
/// single-shot mode).
pub const ADS_OS_START: Int = 1;
/// Comparator mode: traditional hysteresis.
pub const ADS_COMP_TRADITIONAL: Int = 0;
/// Comparator mode: window.
pub const ADS_COMP_WINDOW: Int = 1;
/// Comparator polarity: active low.
pub const ADS_COMP_ACTIVE_LOW: Int = 0;
/// Comparator polarity: active high.
pub const ADS_COMP_ACTIVE_HIGH: Int = 1;
/// Comparator latching: non-latching.
pub const ADS_COMP_NONLATCHING: Int = 0;
/// Comparator latching: latching.
pub const ADS_COMP_LATCHING: Int = 1;
/// Comparator queue: assert after one conversion.
pub const ADS_COMP_QUE_ONE: Int = 0;
/// Comparator queue: assert after two conversions.
pub const ADS_COMP_QUE_TWO: Int = 1;
/// Comparator queue: assert after four conversions.
pub const ADS_COMP_QUE_FOUR: Int = 2;
/// Comparator queue: comparator disabled (power-on default).
pub const ADS_COMP_QUE_DISABLE: Int = 3;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// ADS1x15-style configuration register, field by field: each member holds
/// the raw bitfield value, not a decoded voltage. OS is 1 bit, MUX 3 bits,
/// PGA 3 bits, MODE 1 bit, DR 3 bits, COMP_MODE/COMP_POL/COMP_LAT 1 bit each
/// and COMP_QUE 2 bits.
pub type Ads1x15Config = {
  os: Int;
  mux: Int;
  pga: Int;
  mode: Int;
  dr: Int;
  comp_mode: Int;
  comp_pol: Int;
  comp_lat: Int;
  comp_que: Int;
}

/// Summary of a sample block: the sample count, the minimum and maximum
/// sample and the raw sum (callers divide; `sum` can be large, so blocks are
/// bounded in practice by the caller).
pub type AdcStats = {
  count: Int;
  min: Int;
  max: Int;
  sum: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Ads1x15Config, Str].
fn _ok_cfg(v: Ads1x15Config) -> Result[Ads1x15Config, Str] {
  return Ok(v);
}

// Err(m) for Result[Ads1x15Config, Str].
fn _err_cfg(m: Str) -> Result[Ads1x15Config, Str] {
  return Err(m);
}

// Ok(v) for Result[AdcStats, Str].
fn _ok_stats(v: AdcStats) -> Result[AdcStats, Str] {
  return Ok(v);
}

// Err(m) for Result[AdcStats, Str].
fn _err_stats(m: Str) -> Result[AdcStats, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// 2^k for 0 <= k <= 30, computed by repeated multiplication (no shift).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Base-2 logarithm of an exact power of two v >= 1; 0 for v <= 1.
fn _log2i(v: Int) -> Int {
  var x = v;
  var k = 0;
  while x > 1 {
    x = x / 2;
    k = k + 1;
  }
  return k;
}

// True when v is a power of two (1, 2, 4, ...); false otherwise.
fn _is_pow2(v: Int) -> Bool {
  if v < 1 {
    return false;
  }
  return _pow2(_log2i(v)) == v;
}

// Shared scaling core: vref_uv * raw / scale / gain, one truncation per
// division. Callers validate bits, vref_uv, gain and the raw range first.
fn _scale_uv(raw: Int, vref_uv: Int, scale: Int, gain: Int) -> Int {
  return vref_uv * raw / scale / gain;
}

// --------------------------------------------------
//  Resolution, full scale, gain
// --------------------------------------------------

/// Validate a resolution in bits; the supported range is 8..24.
///
/// Err("adc: resolution N out of range 8..24") otherwise.
/// Complexity: O(1).
pub fn adc_validate_resolution(bits: Int) -> Result[Unit, Str] {
  if bits < ADC_RES_MIN || bits > ADC_RES_MAX {
    return _err_unit("adc: resolution " + convert.int_to_string(bits) + " out of range 8..24");
  }
  return _ok_unit();
}

/// Unipolar full-scale code of a resolution: 2^bits - 1, or -1 when the
/// resolution is outside 8..24. Complexity: O(1).
pub fn adc_full_scale(bits: Int) -> Int {
  if bits < ADC_RES_MIN || bits > ADC_RES_MAX {
    return -1;
  }
  return _pow2(bits) - 1;
}

/// Differential full-scale magnitude of a resolution: 2^(bits-1), the
/// magnitude of the most negative two's complement code, or -1 when the
/// resolution is outside 8..24. Complexity: O(1).
pub fn adc_diff_full_scale(bits: Int) -> Int {
  if bits < ADC_RES_MIN || bits > ADC_RES_MAX {
    return -1;
  }
  return _pow2(bits - 1);
}

/// Validate a gain factor: any integer >= 1 is accepted (PGA-style gains are
/// usually powers of two, but the scaling math does not require it).
///
/// Err("adc: gain N must be at least 1") otherwise.
/// Complexity: O(1).
pub fn adc_validate_gain(gain: Int) -> Result[Unit, Str] {
  if gain < 1 {
    return _err_unit("adc: gain " + convert.int_to_string(gain) + " must be at least 1");
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Reference and input-mode selection
// --------------------------------------------------

/// Reference voltage in microvolts for a reference selector: selector 0 is
/// the internal 2.048 V reference (ADC_INTERNAL_REF_UV, the passed external
/// value is ignored); selector 1 is an external reference whose positive
/// value the caller passes as `external_uv`.
///
/// Err("adc: reference selector N is not 0 or 1") for any other selector;
/// Err("adc: external reference N uV must be positive") when selector 1
/// receives an external_uv <= 0.
/// Complexity: O(1).
pub fn adc_reference_uv(sel: Int, external_uv: Int) -> Result[Int, Str] {
  if sel == ADC_REF_INTERNAL {
    return _ok_int(ADC_INTERNAL_REF_UV);
  }
  if sel == ADC_REF_EXTERNAL {
    if external_uv <= 0 {
      return _err_int("adc: external reference " + convert.int_to_string(external_uv) + " uV must be positive");
    }
    return _ok_int(external_uv);
  }
  return _err_int("adc: reference selector " + convert.int_to_string(sel) + " is not 0 or 1");
}

/// Human-readable reference selector name: "internal", "external" or
/// "unknown". Complexity: O(1).
pub fn adc_reference_name(sel: Int) -> Str {
  if sel == ADC_REF_INTERNAL {
    return "internal";
  }
  if sel == ADC_REF_EXTERNAL {
    return "external";
  }
  return "unknown";
}

/// Validate an input mode: 0 single-ended (ADC_SINGLE_ENDED) or
/// 1 differential (ADC_DIFFERENTIAL).
///
/// Err("adc: mode N is not 0 (single-ended) or 1 (differential)") otherwise.
/// Complexity: O(1).
pub fn adc_validate_mode(mode: Int) -> Result[Unit, Str] {
  if mode != ADC_SINGLE_ENDED && mode != ADC_DIFFERENTIAL {
    return _err_unit("adc: mode " + convert.int_to_string(mode) + " is not 0 (single-ended) or 1 (differential)");
  }
  return _ok_unit();
}

/// Human-readable mode name: "single-ended", "differential" or "unknown".
/// Complexity: O(1).
pub fn adc_mode_name(mode: Int) -> Str {
  if mode == ADC_SINGLE_ENDED {
    return "single-ended";
  }
  if mode == ADC_DIFFERENTIAL {
    return "differential";
  }
  return "unknown";
}

// --------------------------------------------------
//  Raw-to-voltage scaling (integer microvolts)
// --------------------------------------------------

/// Convert an unsigned raw code to microvolts:
/// vref_uv * raw / (2^bits - 1) / gain, one truncation per division
/// (truncation toward zero).
///
/// Validation order and errors:
///   1. bits outside 8..24 -> "adc: resolution N out of range 8..24";
///   2. vref_uv <= 0 -> "adc: vref N uV must be positive";
///   3. gain < 1 -> "adc: gain N must be at least 1";
///   4. raw outside 0..2^bits-1 -> "adc: raw N out of range 0..M".
/// Complexity: O(1).
pub fn adc_raw_to_uv(raw: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str] {
  if bits < ADC_RES_MIN || bits > ADC_RES_MAX {
    return _err_int("adc: resolution " + convert.int_to_string(bits) + " out of range 8..24");
  }
  if vref_uv <= 0 {
    return _err_int("adc: vref " + convert.int_to_string(vref_uv) + " uV must be positive");
  }
  if gain < 1 {
    return _err_int("adc: gain " + convert.int_to_string(gain) + " must be at least 1");
  }
  let fs = _pow2(bits) - 1;
  if raw < 0 || raw > fs {
    return _err_int("adc: raw " + convert.int_to_string(raw) + " out of range 0.." + convert.int_to_string(fs));
  }
  return _ok_int(_scale_uv(raw, vref_uv, fs, gain));
}

/// Convert an unsigned raw code to millivolts: the microvolt result of
/// adc_raw_to_uv, then a truncating division by 1000. Same validation order
/// and errors as adc_raw_to_uv. Complexity: O(1).
pub fn adc_raw_to_millivolts(raw: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str] {
  let r = adc_raw_to_uv(raw, bits, vref_uv, gain);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let uv: Int = r.value;
  return _ok_int(uv / 1000);
}

/// Size of one LSB in nanovolts for a unipolar scale:
/// vref_uv * 1000 / (2^bits - 1) / gain (truncating). Nanovolts keep the
/// result integer; a 16-bit 2.048 V range is 31250 nV = 31.25 uV per LSB.
///
/// Validation order and errors are those of adc_raw_to_uv steps 1..3.
/// Complexity: O(1).
pub fn adc_lsb_nanovolts(bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str] {
  if bits < ADC_RES_MIN || bits > ADC_RES_MAX {
    return _err_int("adc: resolution " + convert.int_to_string(bits) + " out of range 8..24");
  }
  if vref_uv <= 0 {
    return _err_int("adc: vref " + convert.int_to_string(vref_uv) + " uV must be positive");
  }
  if gain < 1 {
    return _err_int("adc: gain " + convert.int_to_string(gain) + " must be at least 1");
  }
  let fs = _pow2(bits) - 1;
  return _ok_int(vref_uv * 1000 / fs / gain);
}

/// Interpret `raw` as a `bits`-wide two's complement code: codes with the
/// top bit set become negative (raw - 2^bits). The input must be a valid bit
/// pattern 0..2^bits-1; out-of-range input is rejected rather than wrapped.
///
/// Err("adc: resolution N out of range 8..24") for an invalid resolution;
/// Err("adc: raw N out of range 0..M") for a code outside 0..2^bits-1.
/// Complexity: O(1).
pub fn adc_twos_complement(raw: Int, bits: Int) -> Result[Int, Str] {
  if bits < ADC_RES_MIN || bits > ADC_RES_MAX {
    return _err_int("adc: resolution " + convert.int_to_string(bits) + " out of range 8..24");
  }
  let fs = _pow2(bits) - 1;
  if raw < 0 || raw > fs {
    return _err_int("adc: raw " + convert.int_to_string(raw) + " out of range 0.." + convert.int_to_string(fs));
  }
  let half = _pow2(bits - 1);
  if raw >= half {
    return _ok_int(raw - _pow2(bits));
  }
  return _ok_int(raw);
}

/// Convert a two's complement raw code to signed microvolts:
/// vref_uv * signed / 2^(bits-1) / gain, one truncation per division. The
/// differential scale is the magnitude of the most negative code, so valid
/// codes map to -vref/gain..+vref/gain.
///
/// Validation order and errors:
///   1. bits outside 8..24 -> the resolution error;
///   2. vref_uv <= 0 -> the vref error;
///   3. gain < 1 -> the gain error;
///   4. raw outside -2^(bits-1)..2^(bits-1)-1 -> "adc: signed raw N out of
///      range -M..P".
/// Complexity: O(1).
pub fn adc_raw_to_uv_signed(raw: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str] {
  if bits < ADC_RES_MIN || bits > ADC_RES_MAX {
    return _err_int("adc: resolution " + convert.int_to_string(bits) + " out of range 8..24");
  }
  if vref_uv <= 0 {
    return _err_int("adc: vref " + convert.int_to_string(vref_uv) + " uV must be positive");
  }
  if gain < 1 {
    return _err_int("adc: gain " + convert.int_to_string(gain) + " must be at least 1");
  }
  let half = _pow2(bits - 1);
  let lo = 0 - half;
  let hi = half - 1;
  if raw < lo || raw > hi {
    return _err_int("adc: signed raw " + convert.int_to_string(raw) + " out of range " + convert.int_to_string(lo) + ".." + convert.int_to_string(hi));
  }
  return _ok_int(_scale_uv(raw, vref_uv, half, gain));
}

/// Convert a two's complement raw code to millivolts: the microvolt result
/// of adc_raw_to_uv_signed, then a truncating division by 1000 (negative
/// results round toward zero). Same validation order and errors as
/// adc_raw_to_uv_signed. Complexity: O(1).
pub fn adc_raw_to_millivolts_signed(raw: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str] {
  let r = adc_raw_to_uv_signed(raw, bits, vref_uv, gain);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let uv: Int = r.value;
  return _ok_int(uv / 1000);
}

/// Convert a unipolar voltage in microvolts back to the raw code:
/// uv * gain * (2^bits - 1) / vref_uv, truncating toward zero.
///
/// Validation order and errors:
///   1. bits outside 8..24 -> the resolution error;
///   2. vref_uv <= 0 -> the vref error;
///   3. gain < 1 -> the gain error;
///   4. uv outside 0..vref_uv/gain (the full-scale voltage) ->
///      "adc: value N uV out of range 0..M".
/// Complexity: O(1).
pub fn adc_uv_to_raw(uv: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str] {
  if bits < ADC_RES_MIN || bits > ADC_RES_MAX {
    return _err_int("adc: resolution " + convert.int_to_string(bits) + " out of range 8..24");
  }
  if vref_uv <= 0 {
    return _err_int("adc: vref " + convert.int_to_string(vref_uv) + " uV must be positive");
  }
  if gain < 1 {
    return _err_int("adc: gain " + convert.int_to_string(gain) + " must be at least 1");
  }
  let fs = _pow2(bits) - 1;
  let max_uv = vref_uv / gain;
  if uv < 0 || uv > max_uv {
    return _err_int("adc: value " + convert.int_to_string(uv) + " uV out of range 0.." + convert.int_to_string(max_uv));
  }
  return _ok_int(uv * gain * fs / vref_uv);
}

// --------------------------------------------------
//  Averaging / oversampling helpers
// --------------------------------------------------

/// Sum of a sample block; 0 for an empty block. Complexity: O(n).
pub fn adc_sum(samples: &Vec[Int]) -> Int {
  var total = 0;
  var i = 0;
  while i < samples.len() {
    let s: Int = samples[i];
    total = total + s;
    i = i + 1;
  }
  return total;
}

/// Truncated mean of a sample block: sum / count, division truncating
/// toward zero. Complexity: O(n).
///
/// Err("adc: no samples") for an empty block.
pub fn adc_mean(samples: &Vec[Int]) -> Result[Int, Str] {
  let n = samples.len();
  if n < 1 {
    return _err_int("adc: no samples");
  }
  return _ok_int(adc_sum(samples) / n);
}

/// Mean rounded half away from zero: q = sum / count, r = sum % count, and
/// |r| * 2 >= count bumps q by one in the sign direction (the remainder
/// carries the sign of the sum, so positive blocks round up and negative
/// blocks round down). Complexity: O(n).
///
/// Err("adc: no samples") for an empty block.
pub fn adc_mean_rounded(samples: &Vec[Int]) -> Result[Int, Str] {
  let n = samples.len();
  if n < 1 {
    return _err_int("adc: no samples");
  }
  let total = adc_sum(samples);
  let q = total / n;
  let r = total % n;
  var ar = r;
  if ar < 0 {
    ar = 0 - ar;
  }
  if ar * 2 >= n {
    if r > 0 {
      return _ok_int(q + 1);
    }
    if r < 0 {
      return _ok_int(q - 1);
    }
  }
  return _ok_int(q);
}

/// Count, minimum, maximum and sum of a sample block in one pass.
/// Complexity: O(n).
///
/// Err("adc: no samples") for an empty block.
pub fn adc_stats(samples: &Vec[Int]) -> Result[AdcStats, Str] {
  let n = samples.len();
  if n < 1 {
    return _err_stats("adc: no samples");
  }
  let first: Int = samples[0];
  var mn = first;
  var mx = first;
  var total = 0;
  var i = 0;
  while i < n {
    let s: Int = samples[i];
    if s < mn {
      mn = s;
    }
    if s > mx {
      mx = s;
    }
    total = total + s;
    i = i + 1;
  }
  return _ok_stats(AdcStats{ count: n; min: mn; max: mx; sum: total; });
}

/// Extra bits provided by an oversampling factor: log2(factor) when factor
/// is a power of two, else -1 (also -1 for factor < 1). Averaging 4^n
/// samples yields n extra bits under ideal conditions.
/// Complexity: O(log factor).
pub fn adc_oversample_shift(factor: Int) -> Int {
  if factor < 1 {
    return -1;
  }
  if !_is_pow2(factor) {
    return -1;
  }
  return _log2i(factor);
}

/// Resolution after oversampling by a power-of-two factor:
/// resolution + log2(factor).
///
/// Err("adc: resolution N out of range 8..24") for an invalid resolution;
/// Err("adc: oversampling factor N is not a power of two") when factor is
/// not a power of two >= 1; Err("adc: oversampled resolution N out of range
/// 8..24") when the sum leaves the supported range.
/// Complexity: O(log factor).
pub fn adc_oversample_bits(resolution: Int, factor: Int) -> Result[Int, Str] {
  if resolution < ADC_RES_MIN || resolution > ADC_RES_MAX {
    return _err_int("adc: resolution " + convert.int_to_string(resolution) + " out of range 8..24");
  }
  let shift = adc_oversample_shift(factor);
  if shift < 0 {
    return _err_int("adc: oversampling factor " + convert.int_to_string(factor) + " is not a power of two");
  }
  let effective = resolution + shift;
  if effective > ADC_RES_MAX {
    return _err_int("adc: oversampled resolution " + convert.int_to_string(effective) + " out of range 8..24");
  }
  return _ok_int(effective);
}

// --------------------------------------------------
//  ADS1x15: MUX and channel helpers
// --------------------------------------------------

/// ADS1x15 MUX setting for a single-ended channel 0..3: 4 + channel.
///
/// Err("adc.ads1x15: single-ended channel N out of range 0..3") otherwise.
/// Complexity: O(1).
pub fn ads_mux_single(channel: Int) -> Result[Int, Str] {
  if channel < 0 || channel > 3 {
    return _err_int("adc.ads1x15: single-ended channel " + convert.int_to_string(channel) + " out of range 0..3");
  }
  return _ok_int(ADS_MUX_SINGLE_0 + channel);
}

/// ADS1x15 MUX setting for a differential pair. Only the four hardware
/// pairs exist: AIN0-AIN1, AIN0-AIN3, AIN1-AIN3 and AIN2-AIN3; the order
/// matters (positive input first).
///
/// Err("adc.ads1x15: channel N out of range 0..3") when either input is
/// outside 0..3; Err("adc.ads1x15: differential pair AINp-AINn is not
/// supported") for any other pair.
/// Complexity: O(1).
pub fn ads_mux_differential(pos: Int, neg: Int) -> Result[Int, Str] {
  if pos < 0 || pos > 3 {
    return _err_int("adc.ads1x15: channel " + convert.int_to_string(pos) + " out of range 0..3");
  }
  if neg < 0 || neg > 3 {
    return _err_int("adc.ads1x15: channel " + convert.int_to_string(neg) + " out of range 0..3");
  }
  if pos == 0 && neg == 1 {
    return _ok_int(ADS_MUX_DIFF_0_1);
  }
  if pos == 0 && neg == 3 {
    return _ok_int(ADS_MUX_DIFF_0_3);
  }
  if pos == 1 && neg == 3 {
    return _ok_int(ADS_MUX_DIFF_1_3);
  }
  if pos == 2 && neg == 3 {
    return _ok_int(ADS_MUX_DIFF_2_3);
  }
  return _err_int("adc.ads1x15: differential pair AIN" + convert.int_to_string(pos) + "-AIN" + convert.int_to_string(neg) + " is not supported");
}

/// Human-readable label of an ADS1x15 MUX setting: "AIN0-AIN1",
/// "AIN0-AIN3", "AIN1-AIN3", "AIN2-AIN3", "AIN0", "AIN1", "AIN2", "AIN3"
/// or "unknown". Complexity: O(1).
pub fn ads_mux_label(mux: Int) -> Str {
  if mux == ADS_MUX_DIFF_0_1 {
    return "AIN0-AIN1";
  }
  if mux == ADS_MUX_DIFF_0_3 {
    return "AIN0-AIN3";
  }
  if mux == ADS_MUX_DIFF_1_3 {
    return "AIN1-AIN3";
  }
  if mux == ADS_MUX_DIFF_2_3 {
    return "AIN2-AIN3";
  }
  if mux == ADS_MUX_SINGLE_0 {
    return "AIN0";
  }
  if mux == ADS_MUX_SINGLE_1 {
    return "AIN1";
  }
  if mux == ADS_MUX_SINGLE_2 {
    return "AIN2";
  }
  if mux == ADS_MUX_SINGLE_3 {
    return "AIN3";
  }
  return "unknown";
}

/// True for MUX settings 4..7 (single-ended inputs); false for 0..3 and for
/// any other value. Complexity: O(1).
pub fn ads_mux_is_single_ended(mux: Int) -> Bool {
  return mux >= ADS_MUX_SINGLE_0 && mux <= ADS_MUX_SINGLE_3;
}

/// Human-readable single-ended input name for channels 0..3: "AIN0".."AIN3"
/// or "unknown". Complexity: O(1).
pub fn ads_channel_label(channel: Int) -> Str {
  if channel == 0 {
    return "AIN0";
  }
  if channel == 1 {
    return "AIN1";
  }
  if channel == 2 {
    return "AIN2";
  }
  if channel == 3 {
    return "AIN3";
  }
  return "unknown";
}

// --------------------------------------------------
//  ADS1x15: PGA and data-rate tables
// --------------------------------------------------

/// Full-scale range in microvolts of an ADS1x15 PGA index 0..7, or -1 when
/// the index is outside 0..7. ADS1115 ranges: 0 +/-6.144 V, 1 +/-4.096 V,
/// 2 +/-2.048 V, 3 +/-1.024 V, 4 +/-0.512 V, 5..7 +/-0.256 V. ADS1015
/// ranges: 0..4 identical, 5..7 +/-0.512 V.
/// Complexity: O(1).
pub fn ads_pga_fsr_uv(index: Int, is_ads1115: Bool) -> Int {
  if index < 0 || index > 7 {
    return -1;
  }
  if index == 0 {
    return 6144000;
  }
  if index == 1 {
    return 4096000;
  }
  if index == 2 {
    return 2048000;
  }
  if index == 3 {
    return 1024000;
  }
  if index == 4 {
    return 512000;
  }
  if is_ads1115 {
    return 256000;
  }
  return 512000;
}

/// First PGA index whose full-scale range equals `fsr_uv`, or -1 when no
/// index matches. Duplicate ranges resolve to the lowest index (the ADS1015
/// 0.512 V range is index 4, not 5..7).
/// Complexity: O(1).
pub fn ads_pga_index(fsr_uv: Int, is_ads1115: Bool) -> Int {
  var i = 0;
  while i < 8 {
    if ads_pga_fsr_uv(i, is_ads1115) == fsr_uv {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Sample rate in samples per second of an ADS1x15 data-rate index 0..7, or
/// -1 when the index is outside 0..7. ADS1115: 8, 16, 32, 64, 128, 250,
/// 475, 860. ADS1015: 128, 250, 490, 920, 1600, 2400, 3300, 3300.
/// Complexity: O(1).
pub fn ads_data_rate_sps(index: Int, is_ads1115: Bool) -> Int {
  if index < 0 || index > 7 {
    return -1;
  }
  if is_ads1115 {
    if index == 0 {
      return 8;
    }
    if index == 1 {
      return 16;
    }
    if index == 2 {
      return 32;
    }
    if index == 3 {
      return 64;
    }
    if index == 4 {
      return 128;
    }
    if index == 5 {
      return 250;
    }
    if index == 6 {
      return 475;
    }
    return 860;
  }
  if index == 0 {
    return 128;
  }
  if index == 1 {
    return 250;
  }
  if index == 2 {
    return 490;
  }
  if index == 3 {
    return 920;
  }
  if index == 4 {
    return 1600;
  }
  if index == 5 {
    return 2400;
  }
  return 3300;
}

/// First data-rate index whose rate equals `sps`, or -1 when no index
/// matches. On the ADS1015 the 3300 SPS rate is available at index 6 and 7;
/// the reverse lookup returns 6.
/// Complexity: O(1).
pub fn ads_data_rate_index(sps: Int, is_ads1115: Bool) -> Int {
  var i = 0;
  while i < 8 {
    if ads_data_rate_sps(i, is_ads1115) == sps {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  ADS1x15: configuration register codec
// --------------------------------------------------

/// Default ADS1x15 configuration fields: OS start (1), differential
/// AIN0-AIN1 (MUX 0), +/-2.048 V (PGA 2), single-shot (MODE 1), 128 SPS
/// (DR 4) and the traditional non-latching active-low comparator disabled
/// (COMP_MODE 0, COMP_POL 0, COMP_LAT 0, COMP_QUE 3). The encoded word is
/// 0x8583, the documented power-on default.
/// Complexity: O(1).
pub fn ads1x15_default_config() -> Ads1x15Config {
  return Ads1x15Config{ os: ADS_OS_START; mux: ADS_MUX_DIFF_0_1; pga: 2; mode: ADS_MODE_SINGLE_SHOT; dr: 4; comp_mode: ADS_COMP_TRADITIONAL; comp_pol: ADS_COMP_ACTIVE_LOW; comp_lat: ADS_COMP_NONLATCHING; comp_que: ADS_COMP_QUE_DISABLE; };
}

// Validate all nine config fields in register order; returns "" when every
// field fits, otherwise the first out-of-range error message. The fields
// are passed by value so no struct reference travels further than its own
// function (v0.61.3 reference rules).
fn _ads1x15_config_error(os: Int, mux: Int, pga: Int, mode: Int, dr: Int, comp_mode: Int, comp_pol: Int, comp_lat: Int, comp_que: Int) -> Str {
  if os < 0 || os > 1 {
    return "adc.ads1x15: os " + convert.int_to_string(os) + " out of range 0..1";
  }
  if mux < 0 || mux > 7 {
    return "adc.ads1x15: mux " + convert.int_to_string(mux) + " out of range 0..7";
  }
  if pga < 0 || pga > 7 {
    return "adc.ads1x15: pga " + convert.int_to_string(pga) + " out of range 0..7";
  }
  if mode < 0 || mode > 1 {
    return "adc.ads1x15: mode " + convert.int_to_string(mode) + " out of range 0..1";
  }
  if dr < 0 || dr > 7 {
    return "adc.ads1x15: dr " + convert.int_to_string(dr) + " out of range 0..7";
  }
  if comp_mode < 0 || comp_mode > 1 {
    return "adc.ads1x15: comp_mode " + convert.int_to_string(comp_mode) + " out of range 0..1";
  }
  if comp_pol < 0 || comp_pol > 1 {
    return "adc.ads1x15: comp_pol " + convert.int_to_string(comp_pol) + " out of range 0..1";
  }
  if comp_lat < 0 || comp_lat > 1 {
    return "adc.ads1x15: comp_lat " + convert.int_to_string(comp_lat) + " out of range 0..1";
  }
  if comp_que < 0 || comp_que > 3 {
    return "adc.ads1x15: comp_que " + convert.int_to_string(comp_que) + " out of range 0..3";
  }
  return "";
}

/// Encode the config register to its 16-bit word:
/// os*32768 + mux*4096 + pga*512 + mode*256 + dr*32 + comp_mode*16 +
/// comp_pol*8 + comp_lat*4 + comp_que.
///
/// Err("adc.ads1x15: <field> N out of range ...") for the first out-of-range
/// field, in register order OS, MUX, PGA, MODE, DR, COMP_MODE, COMP_POL,
/// COMP_LAT, COMP_QUE.
/// Complexity: O(1).
pub fn ads1x15_config_encode_word(cfg: &Ads1x15Config) -> Result[Int, Str] {
  let os: Int = cfg.os;
  let mux: Int = cfg.mux;
  let pga: Int = cfg.pga;
  let mode: Int = cfg.mode;
  let dr: Int = cfg.dr;
  let comp_mode: Int = cfg.comp_mode;
  let comp_pol: Int = cfg.comp_pol;
  let comp_lat: Int = cfg.comp_lat;
  let comp_que: Int = cfg.comp_que;
  let msg = _ads1x15_config_error(os, mux, pga, mode, dr, comp_mode, comp_pol, comp_lat, comp_que);
  if msg.len() > 0 {
    return _err_int(msg);
  }
  return _ok_int(os * 32768 + mux * 4096 + pga * 512 + mode * 256 + dr * 32 + comp_mode * 16 + comp_pol * 8 + comp_lat * 4 + comp_que);
}

/// Encode the config register to its two wire bytes, most significant byte
/// first (big-endian, as the ADS1x15 transmits it).
///
/// Same validation order and errors as ads1x15_config_encode_word; nothing
/// is written on Err.
/// Complexity: O(1).
pub fn ads1x15_config_encode(cfg: &Ads1x15Config) -> Result[Vec[UInt8], Str] {
  let wordr = ads1x15_config_encode_word(cfg);
  if !wordr.is_ok {
    return _err_bytes(wordr.error);
  }
  let word: Int = wordr.value;
  var out = Vec[UInt8].new();
  out.push(((word / 256) % 256) as UInt8);
  out.push((word % 256) as UInt8);
  return _ok_bytes(out);
}

/// Decode a 16-bit config word into its fields; every 0..65535 word decodes
/// (all non-negative bitfield values are valid).
///
/// Err("adc.ads1x15: config word N out of range 0..65535") otherwise.
/// Complexity: O(1).
pub fn ads1x15_config_decode_word(word: Int) -> Result[Ads1x15Config, Str] {
  if word < 0 || word > 65535 {
    return _err_cfg("adc.ads1x15: config word " + convert.int_to_string(word) + " out of range 0..65535");
  }
  let os = (word / 32768) % 2;
  let mux = (word / 4096) % 8;
  let pga = (word / 512) % 8;
  let mode = (word / 256) % 2;
  let dr = (word / 32) % 8;
  let comp_mode = (word / 16) % 2;
  let comp_pol = (word / 8) % 2;
  let comp_lat = (word / 4) % 2;
  let comp_que = word % 4;
  return _ok_cfg(Ads1x15Config{ os: os; mux: mux; pga: pga; mode: mode; dr: dr; comp_mode: comp_mode; comp_pol: comp_pol; comp_lat: comp_lat; comp_que: comp_que; });
}

/// Decode the config register from its wire bytes: byte 0 is the most
/// significant byte (big-endian); bytes beyond the first two are ignored.
///
/// Err("adc.ads1x15: config needs 2 bytes, have N") when `data` is shorter
/// than 2 bytes; otherwise the word errors of ads1x15_config_decode_word.
/// Complexity: O(1).
pub fn ads1x15_config_decode(data: &Vec[UInt8]) -> Result[Ads1x15Config, Str] {
  if data.len() < 2 {
    return _err_cfg("adc.ads1x15: config needs 2 bytes, have " + convert.int_to_string(data.len()));
  }
  let hi: Int = _byte(data, 0);
  let lo: Int = _byte(data, 1);
  return ads1x15_config_decode_word(hi * 256 + lo);
}
