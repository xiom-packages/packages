// XIOM -- xiom.adc conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.adc codecs against the documented
// integer scaling formulas, the channel/mux and gain helpers, the reference
// and input-mode selection, the averaging/oversampling helpers, the sample
// rate and PGA tables and the ADS1x15-style 16-bit config register codec
// (MUX/PGA/MODE/DR/COMP fields, big-endian byte order, validation catalog).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every pinned integer below was derived by hand from the formulas in
// SPEC.md and independently recomputed; the ADS1x15 config words 0x8583
// (power-on default) and 0xC3E3 / 0x301D are cross-checked field by field
// through decode. All synthetic buffers are built in-test from hex strings;
// no file or device is touched (the library is a codec).
//
// BUG 17 discipline: no Str value is compared with `==`; names and error
// messages go through xiom.string.compare.str_compare. All Vec element
// reads are bound to typed locals.

module adc_tests
use xiom.io; use xiom.test;
use xiom.adc;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/adc.xi)
// --------------------------------------------------

// Bytes for a hex string; "" on malformed input (the test then fails on the
// byte comparison). Lowercase or uppercase digits both parse.
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_cfg_is(r: Result[Ads1x15Config, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_stats_is(r: Result[AdcStats, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn cfg_eq(a: &Ads1x15Config, b: &Ads1x15Config) -> Bool {
  if a.os != b.os {
    return false;
  }
  if a.mux != b.mux {
    return false;
  }
  if a.pga != b.pga {
    return false;
  }
  if a.mode != b.mode {
    return false;
  }
  if a.dr != b.dr {
    return false;
  }
  if a.comp_mode != b.comp_mode {
    return false;
  }
  if a.comp_pol != b.comp_pol {
    return false;
  }
  if a.comp_lat != b.comp_lat {
    return false;
  }
  if a.comp_que != b.comp_que {
    return false;
  }
  return true;
}

// A default config with exactly one field replaced; used to pin one
// validation message per field without repeating the literal nine times.
fn cfg_os(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: v; mux: 0; pga: 2; mode: 1; dr: 4; comp_mode: 0; comp_pol: 0; comp_lat: 0; comp_que: 3; };
}

fn cfg_mux(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: 1; mux: v; pga: 2; mode: 1; dr: 4; comp_mode: 0; comp_pol: 0; comp_lat: 0; comp_que: 3; };
}

fn cfg_pga(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: 1; mux: 0; pga: v; mode: 1; dr: 4; comp_mode: 0; comp_pol: 0; comp_lat: 0; comp_que: 3; };
}

fn cfg_mode(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: 1; mux: 0; pga: 2; mode: v; dr: 4; comp_mode: 0; comp_pol: 0; comp_lat: 0; comp_que: 3; };
}

fn cfg_dr(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: 1; mux: 0; pga: 2; mode: 1; dr: v; comp_mode: 0; comp_pol: 0; comp_lat: 0; comp_que: 3; };
}

fn cfg_cm(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: 1; mux: 0; pga: 2; mode: 1; dr: 4; comp_mode: v; comp_pol: 0; comp_lat: 0; comp_que: 3; };
}

fn cfg_cp(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: 1; mux: 0; pga: 2; mode: 1; dr: 4; comp_mode: 0; comp_pol: v; comp_lat: 0; comp_que: 3; };
}

fn cfg_cl(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: 1; mux: 0; pga: 2; mode: 1; dr: 4; comp_mode: 0; comp_pol: 0; comp_lat: v; comp_que: 3; };
}

fn cfg_cq(v: Int) -> Ads1x15Config {
  return Ads1x15Config{ os: 1; mux: 0; pga: 2; mode: 1; dr: 4; comp_mode: 0; comp_pol: 0; comp_lat: 0; comp_que: v; };
}

// --------------------------------------------------
//  Resolution, gain, reference, mode
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = adc_validate_resolution(8).is_ok;
  if !adc_validate_resolution(24).is_ok { ok = false; }
  if !err_unit_is(adc_validate_resolution(7), "adc: resolution 7 out of range 8..24") { ok = false; }
  if !err_unit_is(adc_validate_resolution(25), "adc: resolution 25 out of range 8..24") { ok = false; }
  if ADC_RES_MIN != 8 { ok = false; }
  if ADC_RES_MAX != 24 { ok = false; }
  if adc_full_scale(8) != 255 { ok = false; }
  if adc_full_scale(12) != 4095 { ok = false; }
  if adc_full_scale(16) != 65535 { ok = false; }
  if adc_full_scale(24) != 16777215 { ok = false; }
  if adc_full_scale(7) != -1 { ok = false; }
  if adc_full_scale(25) != -1 { ok = false; }
  if adc_diff_full_scale(8) != 128 { ok = false; }
  if adc_diff_full_scale(16) != 32768 { ok = false; }
  if adc_diff_full_scale(24) != 8388608 { ok = false; }
  if adc_diff_full_scale(31) != -1 { ok = false; }
  return assert(ok, "resolution 8..24: validation, full scale 2^bits-1, differential 2^(bits-1)");
}

fn t2() -> TestResult {
  var ok = adc_validate_gain(1).is_ok;
  if !adc_validate_gain(128).is_ok { ok = false; }
  if !adc_validate_gain(3).is_ok { ok = false; }
  if !err_unit_is(adc_validate_gain(0), "adc: gain 0 must be at least 1") { ok = false; }
  if !err_unit_is(adc_validate_gain(-4), "adc: gain -4 must be at least 1") { ok = false; }
  return assert(ok, "gain: any positive integer accepted, 0 and negatives rejected");
}

fn t3() -> TestResult {
  var ok = ADC_INTERNAL_REF_UV == 2048000;
  if !int_is(adc_reference_uv(ADC_REF_INTERNAL, 0), 2048000) { ok = false; }
  if !int_is(adc_reference_uv(ADC_REF_INTERNAL, 9999999), 2048000) { ok = false; }
  if !int_is(adc_reference_uv(ADC_REF_EXTERNAL, 3300000), 3300000) { ok = false; }
  if !err_int_is(adc_reference_uv(ADC_REF_EXTERNAL, 0), "adc: external reference 0 uV must be positive") { ok = false; }
  if !err_int_is(adc_reference_uv(ADC_REF_EXTERNAL, -1), "adc: external reference -1 uV must be positive") { ok = false; }
  if !err_int_is(adc_reference_uv(2, 1000), "adc: reference selector 2 is not 0 or 1") { ok = false; }
  if !str_eq(adc_reference_name(ADC_REF_INTERNAL), "internal") { ok = false; }
  if !str_eq(adc_reference_name(ADC_REF_EXTERNAL), "external") { ok = false; }
  if !str_eq(adc_reference_name(9), "unknown") { ok = false; }
  return assert(ok, "reference selection: internal 2.048 V, external uV, selector names");
}

fn t4() -> TestResult {
  var ok = adc_validate_mode(ADC_SINGLE_ENDED).is_ok;
  if !adc_validate_mode(ADC_DIFFERENTIAL).is_ok { ok = false; }
  if !err_unit_is(adc_validate_mode(2), "adc: mode 2 is not 0 (single-ended) or 1 (differential)") { ok = false; }
  if !err_unit_is(adc_validate_mode(-1), "adc: mode -1 is not 0 (single-ended) or 1 (differential)") { ok = false; }
  if ADC_SINGLE_ENDED != 0 { ok = false; }
  if ADC_DIFFERENTIAL != 1 { ok = false; }
  if !str_eq(adc_mode_name(0), "single-ended") { ok = false; }
  if !str_eq(adc_mode_name(1), "differential") { ok = false; }
  if !str_eq(adc_mode_name(2), "unknown") { ok = false; }
  return assert(ok, "input mode: single-ended vs differential constants and names");
}

// --------------------------------------------------
//  Integer scaling
// --------------------------------------------------

fn t5() -> TestResult {
  var ok = int_is(adc_raw_to_uv(0, 12, 4096000, 1), 0);
  if !int_is(adc_raw_to_uv(4095, 12, 4096000, 1), 4096000) { ok = false; }
  if !int_is(adc_raw_to_uv(2048, 12, 4096000, 1), 2048500) { ok = false; }
  if !int_is(adc_raw_to_uv(255, 8, 5000000, 2), 2500000) { ok = false; }
  if !int_is(adc_raw_to_uv(16777215, 24, 2500000, 1), 2500000) { ok = false; }
  if !int_is(adc_raw_to_uv(32767, 16, 2048000, 1), 1023984) { ok = false; }
  if !err_int_is(adc_raw_to_uv(-1, 12, 4096000, 1), "adc: raw -1 out of range 0..4095") { ok = false; }
  if !err_int_is(adc_raw_to_uv(4096, 12, 4096000, 1), "adc: raw 4096 out of range 0..4095") { ok = false; }
  if !err_int_is(adc_raw_to_uv(0, 12, 0, 1), "adc: vref 0 uV must be positive") { ok = false; }
  if !err_int_is(adc_raw_to_uv(0, 12, 4096000, 0), "adc: gain 0 must be at least 1") { ok = false; }
  if !err_int_is(adc_raw_to_uv(0, 7, 4096000, 1), "adc: resolution 7 out of range 8..24") { ok = false; }
  return assert(ok, "unipolar raw-to-uV: vref*raw/full-scale/gain, pinned integer values");
}

fn t6() -> TestResult {
  var ok = int_is(adc_raw_to_millivolts(4095, 12, 4096000, 1), 4096);
  if !int_is(adc_raw_to_millivolts(2048, 12, 4096000, 1), 2048) { ok = false; }
  if !int_is(adc_raw_to_millivolts(32767, 16, 2048000, 1), 1023) { ok = false; }
  if !int_is(adc_raw_to_millivolts(255, 8, 5000000, 2), 2500) { ok = false; }
  if !err_int_is(adc_raw_to_millivolts(4096, 12, 4096000, 1), "adc: raw 4096 out of range 0..4095") { ok = false; }
  if !int_is(adc_lsb_nanovolts(16, 2048000, 1), 31250) { ok = false; }
  if !int_is(adc_lsb_nanovolts(12, 4096000, 1), 1000244) { ok = false; }
  if !int_is(adc_lsb_nanovolts(8, 5000000, 2), 9803921) { ok = false; }
  if !err_int_is(adc_lsb_nanovolts(16, 2048000, 0), "adc: gain 0 must be at least 1") { ok = false; }
  if !err_int_is(adc_lsb_nanovolts(25, 2048000, 1), "adc: resolution 25 out of range 8..24") { ok = false; }
  return assert(ok, "millivolts and LSB nanovolts: truncating integer chain");
}

fn t7() -> TestResult {
  var ok = int_is(adc_twos_complement(0, 16), 0);
  if !int_is(adc_twos_complement(32767, 16), 32767) { ok = false; }
  if !int_is(adc_twos_complement(32768, 16), -32768) { ok = false; }
  if !int_is(adc_twos_complement(65535, 16), -1) { ok = false; }
  if !int_is(adc_twos_complement(2047, 12), 2047) { ok = false; }
  if !int_is(adc_twos_complement(2048, 12), -2048) { ok = false; }
  if !int_is(adc_twos_complement(4095, 12), -1) { ok = false; }
  if !int_is(adc_twos_complement(127, 8), 127) { ok = false; }
  if !int_is(adc_twos_complement(128, 8), -128) { ok = false; }
  if !int_is(adc_twos_complement(255, 8), -1) { ok = false; }
  if !err_int_is(adc_twos_complement(65536, 16), "adc: raw 65536 out of range 0..65535") { ok = false; }
  if !err_int_is(adc_twos_complement(-1, 16), "adc: raw -1 out of range 0..65535") { ok = false; }
  if !err_int_is(adc_twos_complement(0, 25), "adc: resolution 25 out of range 8..24") { ok = false; }
  return assert(ok, "two's complement: top-bit codes become negative, range validated");
}

fn t8() -> TestResult {
  var ok = int_is(adc_raw_to_uv_signed(0, 16, 2048000, 1), 0);
  if !int_is(adc_raw_to_uv_signed(32767, 16, 2048000, 1), 2047937) { ok = false; }
  if !int_is(adc_raw_to_uv_signed(-32768, 16, 2048000, 1), -2048000) { ok = false; }
  if !int_is(adc_raw_to_uv_signed(-1, 16, 2048000, 1), -62) { ok = false; }
  if !int_is(adc_raw_to_uv_signed(1, 16, 2048000, 1), 62) { ok = false; }
  if !int_is(adc_raw_to_uv_signed(32767, 16, 2048000, 2), 1023968) { ok = false; }
  if !int_is(adc_raw_to_millivolts_signed(32767, 16, 2048000, 1), 2047) { ok = false; }
  if !int_is(adc_raw_to_millivolts_signed(-32768, 16, 2048000, 1), -2048) { ok = false; }
  if !err_int_is(adc_raw_to_uv_signed(32768, 16, 2048000, 1), "adc: signed raw 32768 out of range -32768..32767") { ok = false; }
  if !err_int_is(adc_raw_to_uv_signed(-32769, 16, 2048000, 1), "adc: signed raw -32769 out of range -32768..32767") { ok = false; }
  if !err_int_is(adc_raw_to_uv_signed(0, 16, 0, 1), "adc: vref 0 uV must be positive") { ok = false; }
  return assert(ok, "differential scaling: 2^(bits-1) scale, signed microvolts and millivolts");
}

fn t9() -> TestResult {
  var ok = int_is(adc_uv_to_raw(0, 16, 2048000, 1), 0);
  if !int_is(adc_uv_to_raw(1024000, 16, 2048000, 1), 32767) { ok = false; }
  if !int_is(adc_uv_to_raw(2048000, 16, 2048000, 1), 65535) { ok = false; }
  if !int_is(adc_uv_to_raw(1024000, 16, 2048000, 2), 65535) { ok = false; }
  if !int_is(adc_uv_to_raw(2500000, 24, 2500000, 1), 16777215) { ok = false; }
  if !err_int_is(adc_uv_to_raw(2048001, 16, 2048000, 1), "adc: value 2048001 uV out of range 0..2048000") { ok = false; }
  if !err_int_is(adc_uv_to_raw(-1, 16, 2048000, 1), "adc: value -1 uV out of range 0..2048000") { ok = false; }
  if !err_int_is(adc_uv_to_raw(1024001, 16, 2048000, 2), "adc: value 1024001 uV out of range 0..1024000") { ok = false; }
  var raws = Vec[Int].new();
  raws.push(0);
  raws.push(1);
  raws.push(100);
  raws.push(2048);
  raws.push(4095);
  var i = 0;
  while i < raws.len() {
    let raw: Int = raws[i];
    let uv = adc_raw_to_uv(raw, 12, 4096000, 1);
    if !uv.is_ok {
      ok = false;
    } else {
      let u: Int = uv.value;
      let back = adc_uv_to_raw(u, 12, 4096000, 1);
      if !back.is_ok {
        ok = false;
      } else {
        let b: Int = back.value;
        var diff = b - raw;
        if diff < 0 {
          diff = 0 - diff;
        }
        if diff > 1 {
          ok = false;
        }
      }
    }
    i = i + 1;
  }
  return assert(ok, "uV-to-raw inverse: truncating division, full-scale bound, round-trip within 1 LSB");
}

// --------------------------------------------------
//  Channel / mux helpers
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = ADS_MUX_DIFF_0_1 == 0;
  if ADS_MUX_DIFF_0_3 != 1 { ok = false; }
  if ADS_MUX_DIFF_1_3 != 2 { ok = false; }
  if ADS_MUX_DIFF_2_3 != 3 { ok = false; }
  if ADS_MUX_SINGLE_0 != 4 { ok = false; }
  if ADS_MUX_SINGLE_1 != 5 { ok = false; }
  if ADS_MUX_SINGLE_2 != 6 { ok = false; }
  if ADS_MUX_SINGLE_3 != 7 { ok = false; }
  if !int_is(ads_mux_single(0), 4) { ok = false; }
  if !int_is(ads_mux_single(3), 7) { ok = false; }
  if !int_is(ads_mux_differential(0, 1), 0) { ok = false; }
  if !int_is(ads_mux_differential(0, 3), 1) { ok = false; }
  if !int_is(ads_mux_differential(1, 3), 2) { ok = false; }
  if !int_is(ads_mux_differential(2, 3), 3) { ok = false; }
  if !str_eq(ads_mux_label(0), "AIN0-AIN1") { ok = false; }
  if !str_eq(ads_mux_label(1), "AIN0-AIN3") { ok = false; }
  if !str_eq(ads_mux_label(2), "AIN1-AIN3") { ok = false; }
  if !str_eq(ads_mux_label(3), "AIN2-AIN3") { ok = false; }
  if !str_eq(ads_mux_label(4), "AIN0") { ok = false; }
  if !str_eq(ads_mux_label(5), "AIN1") { ok = false; }
  if !str_eq(ads_mux_label(6), "AIN2") { ok = false; }
  if !str_eq(ads_mux_label(7), "AIN3") { ok = false; }
  if !str_eq(ads_mux_label(8), "unknown") { ok = false; }
  if !str_eq(ads_mux_label(-1), "unknown") { ok = false; }
  if !ads_mux_is_single_ended(4) { ok = false; }
  if !ads_mux_is_single_ended(5) { ok = false; }
  if !ads_mux_is_single_ended(6) { ok = false; }
  if !ads_mux_is_single_ended(7) { ok = false; }
  if ads_mux_is_single_ended(0) { ok = false; }
  if ads_mux_is_single_ended(3) { ok = false; }
  if ads_mux_is_single_ended(8) { ok = false; }
  if !str_eq(ads_channel_label(0), "AIN0") { ok = false; }
  if !str_eq(ads_channel_label(1), "AIN1") { ok = false; }
  if !str_eq(ads_channel_label(2), "AIN2") { ok = false; }
  if !str_eq(ads_channel_label(3), "AIN3") { ok = false; }
  if !str_eq(ads_channel_label(4), "unknown") { ok = false; }
  return assert(ok, "ADS1x15 mux: channel mapping, four differential pairs, labels");
}

fn t11() -> TestResult {
  var ok = err_int_is(ads_mux_single(4), "adc.ads1x15: single-ended channel 4 out of range 0..3");
  if !err_int_is(ads_mux_single(-1), "adc.ads1x15: single-ended channel -1 out of range 0..3") { ok = false; }
  if !err_int_is(ads_mux_differential(0, 2), "adc.ads1x15: differential pair AIN0-AIN2 is not supported") { ok = false; }
  if !err_int_is(ads_mux_differential(2, 0), "adc.ads1x15: differential pair AIN2-AIN0 is not supported") { ok = false; }
  if !err_int_is(ads_mux_differential(3, 1), "adc.ads1x15: differential pair AIN3-AIN1 is not supported") { ok = false; }
  if !err_int_is(ads_mux_differential(4, 1), "adc.ads1x15: channel 4 out of range 0..3") { ok = false; }
  if !err_int_is(ads_mux_differential(0, 5), "adc.ads1x15: channel 5 out of range 0..3") { ok = false; }
  if !err_int_is(ads_mux_differential(1, -1), "adc.ads1x15: channel -1 out of range 0..3") { ok = false; }
  return assert(ok, "ADS1x15 mux validation: channel range and unsupported pair errors");
}

// --------------------------------------------------
//  PGA and data-rate tables
// --------------------------------------------------

fn t12() -> TestResult {
  var ok = ads_pga_fsr_uv(0, true) == 6144000;
  if ads_pga_fsr_uv(1, true) != 4096000 { ok = false; }
  if ads_pga_fsr_uv(2, true) != 2048000 { ok = false; }
  if ads_pga_fsr_uv(3, true) != 1024000 { ok = false; }
  if ads_pga_fsr_uv(4, true) != 512000 { ok = false; }
  if ads_pga_fsr_uv(5, true) != 256000 { ok = false; }
  if ads_pga_fsr_uv(6, true) != 256000 { ok = false; }
  if ads_pga_fsr_uv(7, true) != 256000 { ok = false; }
  if ads_pga_fsr_uv(0, false) != 6144000 { ok = false; }
  if ads_pga_fsr_uv(1, false) != 4096000 { ok = false; }
  if ads_pga_fsr_uv(2, false) != 2048000 { ok = false; }
  if ads_pga_fsr_uv(3, false) != 1024000 { ok = false; }
  if ads_pga_fsr_uv(4, false) != 512000 { ok = false; }
  if ads_pga_fsr_uv(5, false) != 512000 { ok = false; }
  if ads_pga_fsr_uv(6, false) != 512000 { ok = false; }
  if ads_pga_fsr_uv(7, false) != 512000 { ok = false; }
  if ads_pga_fsr_uv(-1, true) != -1 { ok = false; }
  if ads_pga_fsr_uv(8, false) != -1 { ok = false; }
  if ads_pga_index(2048000, true) != 2 { ok = false; }
  if ads_pga_index(256000, true) != 5 { ok = false; }
  if ads_pga_index(512000, true) != 4 { ok = false; }
  if ads_pga_index(512000, false) != 4 { ok = false; }
  if ads_pga_index(123, true) != -1 { ok = false; }
  return assert(ok, "ADS1x15 PGA: full-scale tables for ADS1115/ADS1015 and reverse index");
}

fn t13() -> TestResult {
  var ok = ads_data_rate_sps(0, true) == 8;
  if ads_data_rate_sps(1, true) != 16 { ok = false; }
  if ads_data_rate_sps(2, true) != 32 { ok = false; }
  if ads_data_rate_sps(3, true) != 64 { ok = false; }
  if ads_data_rate_sps(4, true) != 128 { ok = false; }
  if ads_data_rate_sps(5, true) != 250 { ok = false; }
  if ads_data_rate_sps(6, true) != 475 { ok = false; }
  if ads_data_rate_sps(7, true) != 860 { ok = false; }
  if ads_data_rate_sps(0, false) != 128 { ok = false; }
  if ads_data_rate_sps(1, false) != 250 { ok = false; }
  if ads_data_rate_sps(2, false) != 490 { ok = false; }
  if ads_data_rate_sps(3, false) != 920 { ok = false; }
  if ads_data_rate_sps(4, false) != 1600 { ok = false; }
  if ads_data_rate_sps(5, false) != 2400 { ok = false; }
  if ads_data_rate_sps(6, false) != 3300 { ok = false; }
  if ads_data_rate_sps(7, false) != 3300 { ok = false; }
  if ads_data_rate_sps(-1, true) != -1 { ok = false; }
  if ads_data_rate_sps(8, false) != -1 { ok = false; }
  if ads_data_rate_index(8, true) != 0 { ok = false; }
  if ads_data_rate_index(128, true) != 4 { ok = false; }
  if ads_data_rate_index(860, true) != 7 { ok = false; }
  if ads_data_rate_index(1600, false) != 4 { ok = false; }
  if ads_data_rate_index(3300, false) != 6 { ok = false; }
  if ads_data_rate_index(3300, true) != -1 { ok = false; }
  if ads_data_rate_index(100, true) != -1 { ok = false; }
  return assert(ok, "ADS1x15 data rates: ADS1115/ADS1015 tables and reverse lookup");
}

// --------------------------------------------------
//  Config register codec
// --------------------------------------------------

fn t14() -> TestResult {
  let def: Ads1x15Config = ads1x15_default_config();
  var ok = def.os == 1;
  if def.mux != 0 { ok = false; }
  if def.pga != 2 { ok = false; }
  if def.mode != 1 { ok = false; }
  if def.dr != 4 { ok = false; }
  if def.comp_mode != 0 { ok = false; }
  if def.comp_pol != 0 { ok = false; }
  if def.comp_lat != 0 { ok = false; }
  if def.comp_que != 3 { ok = false; }
  if !int_is(ads1x15_config_encode_word(&def), 34179) { ok = false; }
  let er = ads1x15_config_encode(&def);
  if !er.is_ok {
    return assert(false, "default config must encode");
  }
  let eb: Vec[UInt8] = er.value;
  if !bytes_equal(eb, hb("8583")) { ok = false; }
  let d1 = ads1x15_config_decode_word(34179);
  if !d1.is_ok {
    ok = false;
  } else {
    let c1: Ads1x15Config = d1.value;
    if !cfg_eq(&c1, &def) { ok = false; }
  }
  let rb = hb("8583");
  let d2 = ads1x15_config_decode(&rb);
  if !d2.is_ok {
    ok = false;
  } else {
    let c2: Ads1x15Config = d2.value;
    if !cfg_eq(&c2, &def) { ok = false; }
  }
  let rx = hb("8583FF");
  let d3 = ads1x15_config_decode(&rx);
  if !d3.is_ok {
    ok = false;
  } else {
    let c3: Ads1x15Config = d3.value;
    if !cfg_eq(&c3, &def) { ok = false; }
  }
  return assert(ok, "ADS1x15 default config 0x8583: fields, word, big-endian bytes, decode");
}

fn t15() -> TestResult {
  let g = Ads1x15Config{ os: 1; mux: 4; pga: 1; mode: 1; dr: 7; comp_mode: 0; comp_pol: 0; comp_lat: 0; comp_que: 3; };
  var ok = int_is(ads1x15_config_encode_word(&g), 50147);
  let eg = ads1x15_config_encode(&g);
  if !eg.is_ok {
    return assert(false, "golden config must encode");
  }
  let gb: Vec[UInt8] = eg.value;
  if !bytes_equal(gb, hb("C3E3")) { ok = false; }
  let c = Ads1x15Config{ os: 0; mux: 3; pga: 0; mode: 0; dr: 0; comp_mode: 1; comp_pol: 1; comp_lat: 1; comp_que: 1; };
  if !int_is(ads1x15_config_encode_word(&c), 12317) { ok = false; }
  let ec = ads1x15_config_encode(&c);
  if !ec.is_ok {
    ok = false;
  } else {
    let cb: Vec[UInt8] = ec.value;
    if !bytes_equal(cb, hb("301D")) { ok = false; }
  }
  let dg = ads1x15_config_decode_word(50147);
  if !dg.is_ok {
    ok = false;
  } else {
    let dc: Ads1x15Config = dg.value;
    if !cfg_eq(&dc, &g) { ok = false; }
  }
  let dc2 = ads1x15_config_decode_word(12317);
  if !dc2.is_ok {
    ok = false;
  } else {
    let dcc: Ads1x15Config = dc2.value;
    if !cfg_eq(&dcc, &c) { ok = false; }
  }
  return assert(ok, "ADS1x15 golden configs: single-shot AIN0 4.096 V 860 SPS and window comparator");
}

fn t16() -> TestResult {
  var ok = err_int_is(ads1x15_config_encode_word(&cfg_os(2)), "adc.ads1x15: os 2 out of range 0..1");
  if !err_int_is(ads1x15_config_encode_word(&cfg_mux(8)), "adc.ads1x15: mux 8 out of range 0..7") { ok = false; }
  if !err_int_is(ads1x15_config_encode_word(&cfg_pga(-1)), "adc.ads1x15: pga -1 out of range 0..7") { ok = false; }
  if !err_int_is(ads1x15_config_encode_word(&cfg_mode(2)), "adc.ads1x15: mode 2 out of range 0..1") { ok = false; }
  if !err_int_is(ads1x15_config_encode_word(&cfg_dr(9)), "adc.ads1x15: dr 9 out of range 0..7") { ok = false; }
  if !err_int_is(ads1x15_config_encode_word(&cfg_cm(2)), "adc.ads1x15: comp_mode 2 out of range 0..1") { ok = false; }
  if !err_int_is(ads1x15_config_encode_word(&cfg_cp(2)), "adc.ads1x15: comp_pol 2 out of range 0..1") { ok = false; }
  if !err_int_is(ads1x15_config_encode_word(&cfg_cl(2)), "adc.ads1x15: comp_lat 2 out of range 0..1") { ok = false; }
  if !err_int_is(ads1x15_config_encode_word(&cfg_cq(4)), "adc.ads1x15: comp_que 4 out of range 0..3") { ok = false; }
  let bad = cfg_os(2);
  if !err_bytes_is(ads1x15_config_encode(&bad), "adc.ads1x15: os 2 out of range 0..1") { ok = false; }
  if !err_cfg_is(ads1x15_config_decode_word(-1), "adc.ads1x15: config word -1 out of range 0..65535") { ok = false; }
  if !err_cfg_is(ads1x15_config_decode_word(65536), "adc.ads1x15: config word 65536 out of range 0..65535") { ok = false; }
  let s1 = hb("85");
  if !err_cfg_is(ads1x15_config_decode(&s1), "adc.ads1x15: config needs 2 bytes, have 1") { ok = false; }
  var s0 = Vec[UInt8].new();
  if !err_cfg_is(ads1x15_config_decode(&s0), "adc.ads1x15: config needs 2 bytes, have 0") { ok = false; }
  return assert(ok, "ADS1x15 config validation: field ranges, word bounds, short buffer");
}

// --------------------------------------------------
//  Averaging, oversampling, determinism
// --------------------------------------------------

fn t17() -> TestResult {
  var v = Vec[Int].new();
  v.push(10);
  v.push(20);
  v.push(30);
  v.push(40);
  var ok = adc_sum(&v) == 100;
  if !int_is(adc_mean(&v), 25) { ok = false; }
  if !int_is(adc_mean_rounded(&v), 25) { ok = false; }
  let st = adc_stats(&v);
  if !st.is_ok {
    return assert(false, "stats must build");
  }
  let s: AdcStats = st.value;
  if s.count != 4 { ok = false; }
  if s.min != 10 { ok = false; }
  if s.max != 40 { ok = false; }
  if s.sum != 100 { ok = false; }
  var w = Vec[Int].new();
  w.push(100);
  w.push(101);
  if !int_is(adc_mean(&w), 100) { ok = false; }
  if !int_is(adc_mean_rounded(&w), 101) { ok = false; }
  var n = Vec[Int].new();
  n.push(-7);
  n.push(-8);
  if adc_sum(&n) != -15 { ok = false; }
  if !int_is(adc_mean(&n), -7) { ok = false; }
  if !int_is(adc_mean_rounded(&n), -8) { ok = false; }
  let stn = adc_stats(&n);
  if !stn.is_ok {
    ok = false;
  } else {
    let sn: AdcStats = stn.value;
    if sn.min != -8 { ok = false; }
    if sn.max != -7 { ok = false; }
    if sn.sum != -15 { ok = false; }
  }
  var one = Vec[Int].new();
  one.push(5);
  if !int_is(adc_mean(&one), 5) { ok = false; }
  var empty = Vec[Int].new();
  if adc_sum(&empty) != 0 { ok = false; }
  if !err_int_is(adc_mean(&empty), "adc: no samples") { ok = false; }
  if !err_int_is(adc_mean_rounded(&empty), "adc: no samples") { ok = false; }
  if !err_stats_is(adc_stats(&empty), "adc: no samples") { ok = false; }
  return assert(ok, "averaging: sum, truncated mean, half-away-from-zero rounding, stats");
}

fn t18() -> TestResult {
  var ok = adc_oversample_shift(1) == 0;
  if adc_oversample_shift(2) != 1 { ok = false; }
  if adc_oversample_shift(4) != 2 { ok = false; }
  if adc_oversample_shift(256) != 8 { ok = false; }
  if adc_oversample_shift(3) != -1 { ok = false; }
  if adc_oversample_shift(0) != -1 { ok = false; }
  if adc_oversample_shift(-4) != -1 { ok = false; }
  if !int_is(adc_oversample_bits(16, 4), 18) { ok = false; }
  if !int_is(adc_oversample_bits(8, 1), 8) { ok = false; }
  if !int_is(adc_oversample_bits(16, 256), 24) { ok = false; }
  if !err_int_is(adc_oversample_bits(24, 2), "adc: oversampled resolution 25 out of range 8..24") { ok = false; }
  if !err_int_is(adc_oversample_bits(16, 1024), "adc: oversampled resolution 26 out of range 8..24") { ok = false; }
  if !err_int_is(adc_oversample_bits(16, 3), "adc: oversampling factor 3 is not a power of two") { ok = false; }
  if !err_int_is(adc_oversample_bits(7, 2), "adc: resolution 7 out of range 8..24") { ok = false; }
  let def: Ads1x15Config = ads1x15_default_config();
  let a = ads1x15_config_encode(&def);
  let b = ads1x15_config_encode(&def);
  if !a.is_ok || !b.is_ok {
    ok = false;
  } else {
    let ab: Vec[UInt8] = a.value;
    let bb: Vec[UInt8] = b.value;
    if !bytes_equal(ab, bb) { ok = false; }
  }
  let d1 = ads1x15_config_decode_word(34179);
  let d2 = ads1x15_config_decode_word(34179);
  if !d1.is_ok || !d2.is_ok {
    ok = false;
  } else {
    let x1: Ads1x15Config = d1.value;
    let x2: Ads1x15Config = d2.value;
    if !cfg_eq(&x1, &x2) { ok = false; }
  }
  return assert(ok, "oversampling shift/effective bits and codec determinism");
}

fn main() -> Int {
  io.println("=== xiom.adc conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.adc: all tests passed");
  } else {
    io.println("xiom.adc: tests failed");
  }
  return failed;
}
