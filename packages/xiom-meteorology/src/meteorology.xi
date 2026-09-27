// XIOM -- xiom.meteorology: aviation weather report codecs (METAR + TAF)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: decode-only codecs for two aviation weather report formats.
//   * metar_decode -- one METAR/SPECI observation into a structured report:
//     report type and AUTO/COR flags, ICAO station, DDHHMMZ observation time,
//     wind (dddffKT / dddffGggKT / VRB, calm, KT or MPS, plus the dddVddd
//     variability group), visibility (4-digit meters, statute miles including
//     fractions and mixed numbers, CAVOK, M/P prefixes, NDV), RVR groups,
//     present-weather groups, sky-cover layers, temperature/dewpoint, the
//     altimeter (Axxxx inHg / Qxxxx hPa), NOSIG, and an opaque RMK tail.
//   * taf_decode -- one TAF into its station, issue time and validity plus its
//     TEMPO/BECMG/FM change groups, decoding wind/visibility/weather/sky
//     inside each change group when present.
// Both decoders are stateless and byte-oriented: one Str in, one structured
// value out, or a deterministic Err("metar: ..."/"taf: ...") message carrying
// the byte offset of the offending token. Tokens that do not belong to any
// recognized group are preserved in the per-report extra-token lists instead
// of being dropped; malformed tokens in recognized positions are rejected.
// See SPEC.md for the grammar, token tables and error catalog.
//
// Language notes (XIOM v0.61.3), same discipline as xiom.nmea / xiom.weather:
//   * free functions only: no self methods, no lambdas, no Vec[StructType];
//     variable-length data is carried by parallel Vec fields with mirrored
//     pushes;
//   * Str equality always goes through xiom.string.compare.str_compare
//     (BUG 17: `==` on a Str read from a Vec[Str] element lowers to a
//     pointer comparison); Vec[Str]/Vec[Int] element reads bind a typed
//     `let` first;
//   * Ok/Err for the report types are constructed only in the leaf helpers
//     _ok_metar/_err_metar/_ok_taf/_err_taf (constructing a Result inside a
//     larger function returning a struct miscompiles);
//   * all arithmetic is 64-bit signed integer math in fixed units (meters,
//     tenths of a degree, hundredths of inHg); no Vec[Float64], no floats;
//   * byte_at results are widened with `as Int` before arithmetic and are
//     never compared against a UInt8 constant >= 128.

module xiom.meteorology

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Byte constants
// ---------------------------------------------------------------------------

const _MT_TAB: UInt8 = 9u8;
const _MT_SPACE: UInt8 = 32u8;
const _MT_PLUS: UInt8 = 43u8;
const _MT_MINUS: UInt8 = 45u8;
const _MT_SLASH: UInt8 = 47u8;
const _MT_ZERO: UInt8 = 48u8;
const _MT_NINE: UInt8 = 57u8;
const _MT_A: UInt8 = 65u8;
const _MT_C: UInt8 = 67u8;
const _MT_D: UInt8 = 68u8;
const _MT_G: UInt8 = 71u8;
const _MT_L: UInt8 = 76u8;
const _MT_M: UInt8 = 77u8;
const _MT_N: UInt8 = 78u8;
const _MT_P: UInt8 = 80u8;
const _MT_Q: UInt8 = 81u8;
const _MT_R: UInt8 = 82u8;
const _MT_U: UInt8 = 85u8;
const _MT_V: UInt8 = 86u8;
const _MT_Z: UInt8 = 90u8;
const _MT_LOWER_A: UInt8 = 97u8;
const _MT_LOWER_Z: UInt8 = 122u8;

// Statute mile in milli-miles per meter: millimiles * 1609344 / 1000000 is
// the truncated meter value of the milli-mile count (1 SM = 1609.344 m).
const _MT_MM_PER_SM_NUM: Int = 1609344;
const _MT_MM_PER_SM_DEN: Int = 1000000;

// ---------------------------------------------------------------------------
// Structured output types
// ---------------------------------------------------------------------------

/// A decoded METAR/SPECI observation. Numeric units are fixed: wind_dir in
/// whole degrees (0-360, -1 for VRB), wind_speed/wind_gust in knots or m/s
/// per wind_unit (gust -1 when absent), var_from/var_to the dddVddd group
/// (-1 when absent), vis_m meters (-1 when absent), temperature/dewpoint in
/// tenths of a degree Celsius, altimeter in hundredths of inHg or whole hPa
/// (-1 when the respective form was not reported). All list fields are
/// parallel vectors: index i of each list describes the same group.
/// See SPEC.md section 4 for the field table and sentinels.
pub type MetarReport = {
  station: Str;
  report_type: Int;
  auto_flag: Bool;
  cor_flag: Bool;
  day: Int;
  hour: Int;
  minute: Int;
  wind_dir: Int;
  wind_speed: Int;
  wind_gust: Int;
  wind_unit: Int;
  wind_calm: Bool;
  wind_vrb: Bool;
  var_from: Int;
  var_to: Int;
  vis_m: Int;
  vis_cavok: Bool;
  vis_sm: Bool;
  vis_ge_10km: Bool;
  vis_prefix: Int;
  vis_ndv: Bool;
  rvr_raw: Vec[Str];
  rvr_runway: Vec[Str];
  rvr_min_m: Vec[Int];
  rvr_max_m: Vec[Int];
  rvr_prefix: Vec[Int];
  rvr_prefix2: Vec[Int];
  rvr_variable: Vec[Int];
  rvr_unit: Vec[Int];
  rvr_trend: Vec[Int];
  wx_raw: Vec[Str];
  wx_intensity: Vec[Int];
  wx_descriptor: Vec[Str];
  wx_phenomena: Vec[Str];
  wx_nsw: Vec[Int];
  sky_raw: Vec[Str];
  sky_cover: Vec[Int];
  sky_height: Vec[Int];
  sky_type: Vec[Str];
  temp_tenths: Int;
  dew_tenths: Int;
  have_temp: Bool;
  alt_inhg100: Int;
  alt_hpa: Int;
  nosig: Bool;
  extra: Vec[Str];
}

/// A decoded TAF forecast. day/hour/minute is the issue time, vfrom_*/
/// vto_* the DDHH/DDHH validity. Change groups are parallel vectors indexed
/// 0..forecast_count: kind 0 = BECMG, 1 = TEMPO, 2 = FM; hours and days are
/// the group validity (for FM, to_day/to_hour are -1, open-ended). Weather
/// and sky entries carry the owning group index in wx_group/sky_group.
/// fc_extra holds unclassifiable tokens seen inside change group g.
/// See SPEC.md section 5 for the field table.
pub type TafReport = {
  station: Str;
  amd_flag: Bool;
  cor_flag: Bool;
  day: Int;
  hour: Int;
  minute: Int;
  vfrom_day: Int;
  vfrom_hour: Int;
  vto_day: Int;
  vto_hour: Int;
  fc_kind: Vec[Int];
  fc_fday: Vec[Int];
  fc_fhour: Vec[Int];
  fc_tday: Vec[Int];
  fc_thour: Vec[Int];
  fc_has_wind: Vec[Int];
  fc_wdir: Vec[Int];
  fc_wspd: Vec[Int];
  fc_wgust: Vec[Int];
  fc_wunit: Vec[Int];
  fc_has_vis: Vec[Int];
  fc_vis_m: Vec[Int];
  fc_cavok: Vec[Int];
  fc_vis_sm: Vec[Int];
  wx_raw: Vec[Str];
  wx_group: Vec[Int];
  sky_raw: Vec[Str];
  sky_group: Vec[Int];
  sky_cover: Vec[Int];
  sky_height: Vec[Int];
  fc_extra: Vec[Str];
  fc_extra_group: Vec[Int];
  extra: Vec[Str];
}

// Parse-result carriers of the private recognizers. Each one has ok = false
// plus safe defaults when the token was not (or not validly) that shape.

type WindParse = {
  ok: Bool;
  dir: Int;
  speed: Int;
  gust: Int;
  unit: Int;
  calm: Bool;
  vrb: Bool;
}

type VisParse = {
  ok: Bool;
  cavok: Bool;
  sm: Bool;
  value_m: Int;
  ge_10km: Bool;
  prefix: Int;
  ndv: Bool;
}

type RvrParse = {
  ok: Bool;
  runway: Str;
  min_m: Int;
  max_m: Int;
  variable: Bool;
  prefix: Int;
  prefix2: Int;
  unit: Int;
  trend: Int;
}

type WxParse = {
  ok: Bool;
  intensity: Int;
  descriptor: Str;
  phenomena: Str;
  nsw: Bool;
}

type SkyParse = {
  ok: Bool;
  cover: Int;
  height: Int;
  ctype: Str;
}

type TempParse = {
  ok: Bool;
  temp_tenths: Int;
  dew_tenths: Int;
}

type AltParse = {
  ok: Bool;
  kind: Int;
  value: Int;
}

type TimeParse = {
  ok: Bool;
  day: Int;
  hour: Int;
  minute: Int;
}

type ValidParse = {
  ok: Bool;
  from_day: Int;
  from_hour: Int;
  to_day: Int;
  to_hour: Int;
}

type SignedParse = {
  ok: Bool;
  value: Int;
}

// Accumulator for a TAF decode: parallel group vectors plus the flat weather/
// sky/extra lists and the index of the group currently being filled (-1
// before the first change group).
type _TafState = {
  fc_kind: Vec[Int];
  fc_fday: Vec[Int];
  fc_fhour: Vec[Int];
  fc_tday: Vec[Int];
  fc_thour: Vec[Int];
  fc_has_wind: Vec[Int];
  fc_wdir: Vec[Int];
  fc_wspd: Vec[Int];
  fc_wgust: Vec[Int];
  fc_wunit: Vec[Int];
  fc_has_vis: Vec[Int];
  fc_vis_m: Vec[Int];
  fc_cavok: Vec[Int];
  fc_vis_sm: Vec[Int];
  wx_raw: Vec[Str];
  wx_group: Vec[Int];
  sky_raw: Vec[Str];
  sky_group: Vec[Int];
  sky_cover: Vec[Int];
  sky_height: Vec[Int];
  fc_extra: Vec[Str];
  fc_extra_group: Vec[Int];
  extra: Vec[Str];
  cur: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (compiler workaround; see the module header)
// ---------------------------------------------------------------------------

fn _ok_metar(m: MetarReport) -> Result[MetarReport, Str] {
  return Ok(m);
}

fn _err_metar(msg: Str) -> Result[MetarReport, Str] {
  return Err(msg);
}

fn _ok_taf(t: TafReport) -> Result[TafReport, Str] {
  return Ok(t);
}

fn _err_taf(msg: Str) -> Result[TafReport, Str] {
  return Err(msg);
}

// ---------------------------------------------------------------------------
// Recognizer defaults
// ---------------------------------------------------------------------------

fn _no_wind() -> WindParse {
  return WindParse{ ok: false; dir: -1; speed: 0; gust: -1; unit: 0; calm: false; vrb: false; };
}

fn _no_vis() -> VisParse {
  return VisParse{ ok: false; cavok: false; sm: false; value_m: -1; ge_10km: false; prefix: 0; ndv: false; };
}

fn _no_rvr() -> RvrParse {
  return RvrParse{ ok: false; runway: ""; min_m: -1; max_m: -1; variable: false; prefix: 0; prefix2: 0; unit: 0; trend: 0; };
}

fn _no_wx() -> WxParse {
  return WxParse{ ok: false; intensity: 0; descriptor: ""; phenomena: ""; nsw: false; };
}

fn _no_sky() -> SkyParse {
  return SkyParse{ ok: false; cover: -1; height: -1; ctype: ""; };
}

fn _no_temp() -> TempParse {
  return TempParse{ ok: false; temp_tenths: 0; dew_tenths: 0; };
}

fn _no_alt() -> AltParse {
  return AltParse{ ok: false; kind: 0; value: 0; };
}

fn _no_time() -> TimeParse {
  return TimeParse{ ok: false; day: 0; hour: 0; minute: 0; };
}

fn _no_valid() -> ValidParse {
  return ValidParse{ ok: false; from_day: 0; from_hour: 0; to_day: 0; to_hour: 0; };
}

fn _no_signed() -> SignedParse {
  return SignedParse{ ok: false; value: 0 };
}

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn _is_digit(b: UInt8) -> Bool {
  return b >= _MT_ZERO && b <= _MT_NINE;
}

fn _is_letter(b: UInt8) -> Bool {
  if b >= _MT_A && b <= _MT_Z { return true; }
  return b >= _MT_LOWER_A && b <= _MT_LOWER_Z;
}

// Decimal value of s[start, end); -1 when the run is empty or has a
// non-digit byte.
fn _digits_value(s: Str, start: Int, end: Int) -> Int {
  if start >= end { return -1; }
  var acc = 0;
  var i = start;
  while i < end {
    let b: UInt8 = string.byte_at(s, i);
    if !_is_digit(b) { return -1; }
    acc = acc * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  return acc;
}

// True when every byte of s[start, end) is an ASCII digit and the run is
// non-empty.
fn _all_digits(s: Str, start: Int, end: Int) -> Bool {
  if start >= end { return false; }
  return _digits_value(s, start, end) >= 0;
}

// Index of the first occurrence of target at or after `from`, or -1.
fn _find_byte_from(s: Str, from: Int, target: UInt8) -> Int {
  var i = from;
  while i < s.len() {
    if string.byte_at(s, i) == target { return i; }
    i = i + 1;
  }
  return -1;
}

fn _has_slash(s: Str) -> Bool {
  return _find_byte_from(s, 0, _MT_SLASH) >= 0;
}

// Byte equality of s[a, b) against a literal with the same length.
fn _slice_eq(s: Str, a: Int, b: Int, lit: Str) -> Bool {
  if b - a != lit.len() { return false; }
  var i = 0;
  while i < lit.len() {
    if string.byte_at(s, a + i) != string.byte_at(lit, i) { return false; }
    i = i + 1;
  }
  return true;
}

fn _ends_with(s: Str, suffix: Str) -> Bool {
  let n = s.len();
  let m = suffix.len();
  if m > n { return false; }
  var i = 0;
  while i < m {
    if string.byte_at(s, n - m + i) != string.byte_at(suffix, i) { return false; }
    i = i + 1;
  }
  return true;
}

// Exactly four ASCII letters, either case (ICAO station designator).
fn _is_icao(s: Str) -> Bool {
  if s.len() != 4 { return false; }
  var i = 0;
  while i < 4 {
    if !_is_letter(string.byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Space/tab-separated token scan. tokens receives the token text and starts
// the byte offset of each token in s; both vectors grow in lockstep.
fn _scan_tokens(s: Str, tokens: &mut Vec[Str], starts: &mut Vec[Int]) {
  let n = s.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if b == _MT_SPACE || b == _MT_TAB {
      i = i + 1;
    } else {
      let a = i;
      while i < n {
        let c: UInt8 = string.byte_at(s, i);
        if c == _MT_SPACE || c == _MT_TAB { break; }
        i = i + 1;
      }
      tokens.push(string.str_slice(s, a, i));
      starts.push(a);
    }
  }
}

// ---------------------------------------------------------------------------
// Time recognizers
// ---------------------------------------------------------------------------

// DDHHMMZ with day 1-31, hour 0-23, minute 0-59.
fn _parse_ddhhmmz(t: Str) -> TimeParse {
  var r = _no_time();
  if t.len() != 7 { return r; }
  if string.byte_at(t, 6) != _MT_Z { return r; }
  let d = _digits_value(t, 0, 2);
  let h = _digits_value(t, 2, 4);
  let m = _digits_value(t, 4, 6);
  if d < 1 || d > 31 { return r; }
  if h < 0 || h > 23 { return r; }
  if m < 0 || m > 59 { return r; }
  r.ok = true;
  r.day = d;
  r.hour = h;
  r.minute = m;
  return r;
}

// TAF issue time: DDHHMMZ, or the shorter DDHHZ (minute 0).
fn _parse_issue_time(t: Str) -> TimeParse {
  if t.len() == 5 {
    var r = _no_time();
    if string.byte_at(t, 4) != _MT_Z { return r; }
    let d = _digits_value(t, 0, 2);
    let h = _digits_value(t, 2, 4);
    if d < 1 || d > 31 { return r; }
    if h < 0 || h > 23 { return r; }
    r.ok = true;
    r.day = d;
    r.hour = h;
    r.minute = 0;
    return r;
  }
  return _parse_ddhhmmz(t);
}

// DDHH/DDHH TAF validity period.
fn _parse_validity(t: Str) -> ValidParse {
  var r = _no_valid();
  if t.len() != 9 { return r; }
  if string.byte_at(t, 4) != _MT_SLASH { return r; }
  let fd = _digits_value(t, 0, 2);
  let fh = _digits_value(t, 2, 4);
  let td = _digits_value(t, 5, 7);
  let th = _digits_value(t, 7, 9);
  if fd < 1 || fd > 31 { return r; }
  if fh < 0 || fh > 23 { return r; }
  if td < 1 || td > 31 { return r; }
  if th < 0 || th > 23 { return r; }
  r.ok = true;
  r.from_day = fd;
  r.from_hour = fh;
  r.to_day = td;
  r.to_hour = th;
  return r;
}

// ---------------------------------------------------------------------------
// Wind recognizer
// ---------------------------------------------------------------------------

/// Token shape check used by TAF change groups: a token whose suffix
/// announces a wind group. The actual validity is decided by _parse_wind.
fn _looks_like_wind(t: Str) -> Bool {
  if _ends_with(t, "KT") { return true; }
  return _ends_with(t, "MPS");
}

// dddffKT / dddffGggKT / VRBffKT / VRBffGggKT, ff and gg 2 or 3 digits,
// unit KT or MPS. dir -1 for VRB; gust -1 when absent; calm only for
// non-VRB 000 with speed 0 and no gust.
fn _parse_wind(t: Str) -> WindParse {
  var w = _no_wind();
  let n = t.len();
  if n < 7 { return w; }
  var unit = -1;
  var core_end = n;
  if _ends_with(t, "KT") {
    unit = 0;
    core_end = n - 2;
  } elif _ends_with(t, "MPS") {
    unit = 1;
    core_end = n - 3;
  }
  if unit < 0 { return w; }
  if core_end < 5 { return w; }
  var i = 0;
  var dir = 0;
  var vrb = false;
  if string.byte_at(t, 0) == _MT_V {
    if !_slice_eq(t, 0, 3, "VRB") { return w; }
    vrb = true;
    dir = -1;
    i = 3;
  } else {
    let d = _digits_value(t, 0, 3);
    if d < 0 || d > 360 { return w; }
    dir = d;
    i = 3;
  }
  var gust = -1;
  var speed_end = core_end;
  var gpos = -1;
  var k = i;
  while k < core_end {
    if string.byte_at(t, k) == _MT_G {
      gpos = k;
      break;
    }
    k = k + 1;
  }
  if gpos >= 0 {
    let gl = core_end - gpos - 1;
    if gl < 2 || gl > 3 { return w; }
    let g = _digits_value(t, gpos + 1, core_end);
    if g < 0 { return w; }
    gust = g;
    speed_end = gpos;
  }
  let sl = speed_end - i;
  if sl < 2 || sl > 3 { return w; }
  let sp = _digits_value(t, i, speed_end);
  if sp < 0 { return w; }
  var calm = false;
  if !vrb && dir == 0 && sp == 0 && gust < 0 { calm = true; }
  w.ok = true;
  w.dir = dir;
  w.speed = sp;
  w.gust = gust;
  w.unit = unit;
  w.calm = calm;
  w.vrb = vrb;
  return w;
}

// dddVddd variability group: 3 digits, 'V', 3 digits.
fn _var_wind_shape(t: Str) -> Bool {
  if t.len() != 7 { return false; }
  if string.byte_at(t, 3) != _MT_V { return false; }
  if _digits_value(t, 0, 3) < 0 { return false; }
  return _digits_value(t, 4, 7) >= 0;
}

// ---------------------------------------------------------------------------
// Visibility recognizers
// ---------------------------------------------------------------------------

// Exactly four digits (0000-9999 meters), optionally with an NDV suffix
// ("no directional variation").
fn _vis_meter_token(t: Str) -> Bool {
  let n = t.len();
  if n == 4 { return _all_digits(t, 0, 4); }
  if n == 7 && _ends_with(t, "NDV") { return _all_digits(t, 0, 4); }
  return false;
}

// 4-digit meter visibility (with optional NDV); 9999 marks "10 km or more".
fn _parse_vis_meters(t: Str) -> VisParse {
  var v = _no_vis();
  let n = t.len();
  var core_end = 0;
  if n == 4 {
    core_end = 4;
  } elif n == 7 && _ends_with(t, "NDV") {
    v.ndv = true;
    core_end = 4;
  } else {
    return v;
  }
  let val = _digits_value(t, 0, core_end);
  if val < 0 { return v; }
  v.ok = true;
  v.value_m = val;
  if val == 9999 { v.ge_10km = true; }
  return v;
}

// Millimiles of a plain "p/qSM" fraction token, or -1 when the token is not
// that shape (no M/P prefix, single '/', p and q digits, 0 < p <= q).
fn _sm_fraction_milli(t: Str) -> Int {
  let n = t.len();
  if n < 4 { return -1; }
  if !_ends_with(t, "SM") { return -1; }
  let stop = n - 2;
  let b0 = string.byte_at(t, 0);
  if b0 == _MT_M || b0 == _MT_P { return -1; }
  var slash = -1;
  var k = 0;
  while k < stop {
    if string.byte_at(t, k) == _MT_SLASH {
      slash = k;
      break;
    }
    k = k + 1;
  }
  if slash <= 0 { return -1; }
  if _find_byte_from(t, slash + 1, _MT_SLASH) >= 0 { return -1; }
  let p = _digits_value(t, 0, slash);
  let q = _digits_value(t, slash + 1, stop);
  if p < 0 || q < 1 || p > q { return -1; }
  return (p * 1000) / q;
}

// Whole-number part of a mixed statute-mile group ("1" in "1 1/2SM").
fn _whole_sm_part(t: Str) -> Bool {
  let n = t.len();
  if n < 1 || n > 2 { return false; }
  return _all_digits(t, 0, n);
}

// Visibility in statute miles: dSM, p/qSM, with an optional M (less than) or
// P (greater than) prefix. value_m is the truncated meter equivalent.
fn _parse_vis_sm(t: Str) -> VisParse {
  var v = _no_vis();
  let n = t.len();
  if n < 3 { return v; }
  if !_ends_with(t, "SM") { return v; }
  let stop = n - 2;
  var i = 0;
  var prefix = 0;
  let b0 = string.byte_at(t, 0);
  if b0 == _MT_M {
    prefix = 1;
    i = 1;
  } elif b0 == _MT_P {
    prefix = 2;
    i = 1;
  }
  if stop <= i { return v; }
  var milli = -1;
  let slash = _find_byte_from(t, i, _MT_SLASH);
  if slash < 0 {
    let d = _digits_value(t, i, stop);
    if d >= 0 && d <= 999 { milli = d * 1000; }
  } else {
    if _find_byte_from(t, slash + 1, _MT_SLASH) >= 0 { return v; }
    let p = _digits_value(t, i, slash);
    let q = _digits_value(t, slash + 1, stop);
    if p >= 0 && q >= 1 && p <= q { milli = (p * 1000) / q; }
  }
  if milli < 0 { return v; }
  v.ok = true;
  v.sm = true;
  v.prefix = prefix;
  v.value_m = milli * _MT_MM_PER_SM_NUM / _MT_MM_PER_SM_DEN;
  return v;
}

// Mixed statute-mile visibility: whole + p/qSM ("1 1/2SM" -> 1500 millimiles).
fn _parse_vis_sm_mixed(whole: Str, frac: Str) -> VisParse {
  var v = _no_vis();
  let w = _digits_value(whole, 0, whole.len());
  if w < 0 || w > 99 { return v; }
  let fm = _sm_fraction_milli(frac);
  if fm < 0 { return v; }
  let milli = w * 1000 + fm;
  v.ok = true;
  v.sm = true;
  v.value_m = milli * _MT_MM_PER_SM_NUM / _MT_MM_PER_SM_DEN;
  return v;
}

// ---------------------------------------------------------------------------
// RVR recognizer
// ---------------------------------------------------------------------------

// Runway designator: 1-2 digits 1-36 with an optional L/C/R suffix.
fn _valid_runway(rw: Str) -> Bool {
  let n = rw.len();
  if n < 2 || n > 3 { return false; }
  var digits_len = n;
  let last = string.byte_at(rw, n - 1);
  if last == _MT_L || last == _MT_C || last == _MT_R { digits_len = n - 1; }
  if digits_len < 1 || digits_len > 2 { return false; }
  let d = _digits_value(rw, 0, digits_len);
  if d < 1 || d > 36 { return false; }
  return true;
}

/// Token shape check for RVR: 'R' followed by a digit.
fn _rvr_shape(t: Str) -> Bool {
  if t.len() < 2 { return false; }
  if string.byte_at(t, 0) != _MT_R { return false; }
  return _is_digit(string.byte_at(t, 1));
}

// R<runway>/[M|P]vvvv[V[M|P]vvvv][FT][/][U|D|N]; vvvv is 4 digits, in meters
// unless FT is present, in which case the stored min_m/max_m are the
// truncated meter equivalents (ft * 3048 / 10000).
fn _parse_rvr(t: Str) -> RvrParse {
  var r = _no_rvr();
  let n = t.len();
  if n < 4 { return r; }
  if string.byte_at(t, 0) != _MT_R { return r; }
  let k = _find_byte_from(t, 1, _MT_SLASH);
  if k < 0 { return r; }
  let runway = string.str_slice(t, 1, k);
  if !_valid_runway(runway) { return r; }
  var i = k + 1;
  var prefix = 0;
  if i < n {
    let b0 = string.byte_at(t, i);
    if b0 == _MT_M {
      prefix = 1;
      i = i + 1;
    } elif b0 == _MT_P {
      prefix = 2;
      i = i + 1;
    }
  }
  if i + 4 > n { return r; }
  let minv = _digits_value(t, i, i + 4);
  if minv < 0 { return r; }
  i = i + 4;
  var variable = false;
  var prefix2 = 0;
  var maxv = minv;
  if i < n && string.byte_at(t, i) == _MT_V {
    variable = true;
    i = i + 1;
    if i < n {
      let b1 = string.byte_at(t, i);
      if b1 == _MT_M {
        prefix2 = 1;
        i = i + 1;
      } elif b1 == _MT_P {
        prefix2 = 2;
        i = i + 1;
      }
    }
    if i + 4 > n { return r; }
    maxv = _digits_value(t, i, i + 4);
    if maxv < 0 { return r; }
    i = i + 4;
  }
  var unit = 0;
  if i + 2 <= n && _slice_eq(t, i, i + 2, "FT") {
    unit = 1;
    i = i + 2;
  }
  var trend = 0;
  if i < n && string.byte_at(t, i) == _MT_SLASH { i = i + 1; }
  if i < n {
    let bt = string.byte_at(t, i);
    if bt == _MT_U {
      trend = 1;
    } elif bt == _MT_D {
      trend = 2;
    } elif bt == _MT_N {
      trend = 3;
    } else {
      return r;
    }
    i = i + 1;
  }
  if i != n { return r; }
  r.ok = true;
  r.runway = runway;
  r.variable = variable;
  r.prefix = prefix;
  r.prefix2 = prefix2;
  r.unit = unit;
  r.trend = trend;
  if unit == 1 {
    r.min_m = minv * 3048 / 10000;
    r.max_m = maxv * 3048 / 10000;
  } else {
    r.min_m = minv;
    r.max_m = maxv;
  }
  return r;
}

// ---------------------------------------------------------------------------
// Present-weather recognizer
// ---------------------------------------------------------------------------

// Two-letter weather code classes. Descriptors: MI BC PR DR BL SH TS FZ.
fn _is_descriptor_code(c: Str) -> Bool {
  if _str_eq(c, "MI") { return true; }
  if _str_eq(c, "BC") { return true; }
  if _str_eq(c, "PR") { return true; }
  if _str_eq(c, "DR") { return true; }
  if _str_eq(c, "BL") { return true; }
  if _str_eq(c, "SH") { return true; }
  if _str_eq(c, "TS") { return true; }
  if _str_eq(c, "FZ") { return true; }
  return false;
}

// Precipitation DZ RA SN SG IC PL GR GS UP; obscuration BR FG FU VA DU SA HZ
// PY; other PO SQ FC SS DS.
fn _is_phenomenon_code(c: Str) -> Bool {
  if _str_eq(c, "DZ") { return true; }
  if _str_eq(c, "RA") { return true; }
  if _str_eq(c, "SN") { return true; }
  if _str_eq(c, "SG") { return true; }
  if _str_eq(c, "IC") { return true; }
  if _str_eq(c, "PL") { return true; }
  if _str_eq(c, "GR") { return true; }
  if _str_eq(c, "GS") { return true; }
  if _str_eq(c, "UP") { return true; }
  if _str_eq(c, "BR") { return true; }
  if _str_eq(c, "FG") { return true; }
  if _str_eq(c, "FU") { return true; }
  if _str_eq(c, "VA") { return true; }
  if _str_eq(c, "DU") { return true; }
  if _str_eq(c, "SA") { return true; }
  if _str_eq(c, "HZ") { return true; }
  if _str_eq(c, "PY") { return true; }
  if _str_eq(c, "PO") { return true; }
  if _str_eq(c, "SQ") { return true; }
  if _str_eq(c, "FC") { return true; }
  if _str_eq(c, "SS") { return true; }
  if _str_eq(c, "DS") { return true; }
  return false;
}

// Present weather: [+|-] [descriptor] phenomenon... or VC [descriptor]
// phenomenon..., or the single token NSW. Intensity: 0 moderate, 1 light,
// 2 heavy, 3 vicinity. A descriptor may stand alone only when it is TS or
// when the token carries the VC prefix (VCTS, VCSH, ...). Anything else --
// including unknown combinations such as RERA or TSXX -- is not a weather
// group and is left for the caller to store as an extra token.
fn _parse_wx(t: Str) -> WxParse {
  var r = _no_wx();
  let n = t.len();
  if n < 2 { return r; }
  if _str_eq(t, "NSW") {
    r.ok = true;
    r.nsw = true;
    return r;
  }
  var i = 0;
  var intensity = 0;
  let b0 = string.byte_at(t, 0);
  if b0 == _MT_PLUS {
    intensity = 2;
    i = 1;
  } elif b0 == _MT_MINUS {
    intensity = 1;
    i = 1;
  } elif n >= 4 && b0 == _MT_V && string.byte_at(t, 1) == _MT_C {
    intensity = 3;
    i = 2;
  }
  var desc = "";
  if i + 2 <= n {
    let code = string.str_slice(t, i, i + 2);
    if _is_descriptor_code(code) {
      desc = code;
      i = i + 2;
    }
  }
  var phen = "";
  while i < n {
    if i + 2 > n { return _no_wx(); }
    let code = string.str_slice(t, i, i + 2);
    if !_is_phenomenon_code(code) { return _no_wx(); }
    phen = phen + code;
    i = i + 2;
  }
  if phen.len() == 0 && desc.len() == 0 { return _no_wx(); }
  if phen.len() == 0 {
    if !_str_eq(desc, "TS") && intensity != 3 { return _no_wx(); }
  }
  r.ok = true;
  r.intensity = intensity;
  r.descriptor = desc;
  r.phenomena = phen;
  return r;
}

// ---------------------------------------------------------------------------
// Sky-cover recognizer
// ---------------------------------------------------------------------------

// 0 FEW, 1 SCT, 2 BKN, 3 OVC, 4 VV; -1 when the token is not a layer.
fn _parse_sky(t: Str) -> SkyParse {
  var s = _no_sky();
  let n = t.len();
  if n == 5 && _slice_eq(t, 0, 2, "VV") {
    if _slice_eq(t, 2, 5, "///") {
      s.ok = true;
      s.cover = 4;
      s.height = -1;
      return s;
    }
    let h = _digits_value(t, 2, 5);
    if h >= 0 {
      s.ok = true;
      s.cover = 4;
      s.height = h * 100;
    }
    return s;
  }
  if n == 6 {
    var c = -1;
    if _slice_eq(t, 0, 3, "FEW") { c = 0; }
    elif _slice_eq(t, 0, 3, "SCT") { c = 1; }
    elif _slice_eq(t, 0, 3, "BKN") { c = 2; }
    elif _slice_eq(t, 0, 3, "OVC") { c = 3; }
    if c < 0 { return s; }
    let h = _digits_value(t, 3, 6);
    if h < 0 { return s; }
    s.ok = true;
    s.cover = c;
    s.height = h * 100;
    return s;
  }
  if n == 8 && _slice_eq(t, 6, 8, "CB") {
    var c = -1;
    if _slice_eq(t, 0, 3, "FEW") { c = 0; }
    elif _slice_eq(t, 0, 3, "SCT") { c = 1; }
    elif _slice_eq(t, 0, 3, "BKN") { c = 2; }
    elif _slice_eq(t, 0, 3, "OVC") { c = 3; }
    if c < 0 { return s; }
    let h = _digits_value(t, 3, 6);
    if h < 0 { return s; }
    s.ok = true;
    s.cover = c;
    s.height = h * 100;
    s.ctype = "CB";
    return s;
  }
  if n == 9 && _slice_eq(t, 6, 9, "TCU") {
    var c = -1;
    if _slice_eq(t, 0, 3, "FEW") { c = 0; }
    elif _slice_eq(t, 0, 3, "SCT") { c = 1; }
    elif _slice_eq(t, 0, 3, "BKN") { c = 2; }
    elif _slice_eq(t, 0, 3, "OVC") { c = 3; }
    if c < 0 { return s; }
    let h = _digits_value(t, 3, 6);
    if h < 0 { return s; }
    s.ok = true;
    s.cover = c;
    s.height = h * 100;
    s.ctype = "TCU";
    return s;
  }
  return s;
}

// ---------------------------------------------------------------------------
// Temperature / dewpoint and altimeter recognizers
// ---------------------------------------------------------------------------

// One side of TT/TT: optional M, one or two digits. Tenths of a degree.
fn _parse_signed_2(p: Str) -> SignedParse {
  var r = _no_signed();
  let n = p.len();
  if n < 1 || n > 3 { return r; }
  var i = 0;
  var neg = false;
  if string.byte_at(p, 0) == _MT_M {
    neg = true;
    i = 1;
  }
  let dlen = n - i;
  if dlen < 1 || dlen > 2 { return r; }
  let d = _digits_value(p, i, n);
  if d < 0 { return r; }
  var v = d * 10;
  if neg && v != 0 { v = 0 - v; }
  r.ok = true;
  r.value = v;
  return r;
}

// (M)TT/(M)TT with exactly one '/' and both sides present.
fn _parse_temp(t: Str) -> TempParse {
  var r = _no_temp();
  let slash = _find_byte_from(t, 0, _MT_SLASH);
  if slash < 0 { return r; }
  if _find_byte_from(t, slash + 1, _MT_SLASH) >= 0 { return r; }
  let a = _parse_signed_2(string.str_slice(t, 0, slash));
  if !a.ok { return r; }
  let b = _parse_signed_2(string.str_slice(t, slash + 1, t.len()));
  if !b.ok { return r; }
  r.ok = true;
  r.temp_tenths = a.value;
  r.dew_tenths = b.value;
  return r;
}

// Axxxx (hundredths of inHg, kind 0) or Qxxxx (whole hPa, kind 1).
fn _parse_alt(t: Str) -> AltParse {
  var r = _no_alt();
  let n = t.len();
  if n != 5 { return r; }
  let b0 = string.byte_at(t, 0);
  var kind = -1;
  if b0 == _MT_A {
    kind = 0;
  } elif b0 == _MT_Q {
    kind = 1;
  }
  if kind < 0 { return r; }
  let v = _digits_value(t, 1, 5);
  if v < 0 { return r; }
  r.ok = true;
  r.kind = kind;
  r.value = v;
  return r;
}

// ---------------------------------------------------------------------------
// METAR decoder
// ---------------------------------------------------------------------------

/// Decode one METAR or SPECI observation.
/// Params: s - the whole report text; tokens are separated by runs of ASCII
/// space or tab, leading/trailing separators are ignored.
/// Grammar: an optional METAR/SPECI keyword, any number of AUTO/COR flag
/// tokens (before the station or immediately after the observation time,
/// which is where AUTO normally appears), then the required station
/// (4 letters), observation time
/// (DDHHMMZ), and wind group (dddffKT / dddffGggKT / VRB... / calm, KT or
/// MPS, dir 0-360). The remaining tokens are classified independently and
/// order-tolerantly: variable wind dddVddd, visibility (4-digit meters with
/// optional NDV, CAVOK, dSM / p/qSM / d p/qSM with optional M/P prefix), RVR
/// groups, present-weather groups, sky layers (FEW/SCT/BKN/OVC + 3-digit
/// hundreds of feet, optional CB/TCU suffix, VV///, VVhhh), temperature
/// (M)TT/(M)TT, altimeter Axxxx/Qxxxx, and NOSIG. RMK starts an opaque tail:
/// every token from RMK on is kept in the extra list and not interpreted.
/// A token in a recognized position that fails its grammar (station, time,
/// wind, visibility, RVR, temperature, altimeter) and a repeated
/// single-instance group (visibility, temperature, altimeter, variable wind,
/// wind) produce a deterministic Err with the token's byte offset. Unrecognized
/// tokens (trend keywords, NSC/NCD, station remarks, ...) are preserved in
/// MetarReport.extra.
/// Returns: Ok(MetarReport).
/// Error case: Err("metar: ...") as described above; the message ends with
/// " at offset N" and, when a token is involved, ": <token>".
/// Complexity: O(len(s)) plus O(1) per token (the mixed SM case reads one
/// token of lookahead).
pub fn metar_decode(s: Str) -> Result[MetarReport, Str] {
  var texts = Vec[Str].new();
  var starts = Vec[Int].new();
  _scan_tokens(s, &mut texts, &mut starts);
  let count = texts.len();
  var i = 0;
  var report_type = 0;
  var auto_flag = false;
  var cor_flag = false;
  if i < count {
    let t0: Str = texts[i];
    if _str_eq(t0, "METAR") {
      report_type = 1;
      i = i + 1;
    } elif _str_eq(t0, "SPECI") {
      report_type = 2;
      i = i + 1;
    }
  }
  while i < count {
    let tf: Str = texts[i];
    if _str_eq(tf, "AUTO") {
      auto_flag = true;
      i = i + 1;
    } elif _str_eq(tf, "COR") {
      cor_flag = true;
      i = i + 1;
    } else {
      break;
    }
  }
  if i >= count {
    return _err_metar("metar: missing station at offset " + convert.int_to_string(s.len()));
  }
  let station: Str = texts[i];
  let st_off: Int = starts[i];
  if !_is_icao(station) {
    return _err_metar("metar: invalid station at offset " + convert.int_to_string(st_off) + ": " + station);
  }
  i = i + 1;
  if i >= count {
    return _err_metar("metar: missing time at offset " + convert.int_to_string(s.len()));
  }
  let time_tok: Str = texts[i];
  let time_off: Int = starts[i];
  let tp = _parse_ddhhmmz(time_tok);
  if !tp.ok {
    return _err_metar("metar: invalid time at offset " + convert.int_to_string(time_off) + ": " + time_tok);
  }
  i = i + 1;
  // AUTO/COR may also follow the observation time (the usual position for
  // AUTO in real reports), immediately before the required wind group.
  while i < count {
    let tf2: Str = texts[i];
    if _str_eq(tf2, "AUTO") {
      auto_flag = true;
      i = i + 1;
    } elif _str_eq(tf2, "COR") {
      cor_flag = true;
      i = i + 1;
    } else {
      break;
    }
  }
  if i >= count {
    return _err_metar("metar: missing wind at offset " + convert.int_to_string(s.len()));
  }
  let wind_tok: Str = texts[i];
  let wind_off: Int = starts[i];
  let wp = _parse_wind(wind_tok);
  if !wp.ok {
    return _err_metar("metar: invalid wind at offset " + convert.int_to_string(wind_off) + ": " + wind_tok);
  }
  i = i + 1;

  var var_from = -1;
  var var_to = -1;
  var have_var = false;
  var vis_m = -1;
  var vis_cavok = false;
  var vis_sm = false;
  var vis_ge10 = false;
  var vis_prefix = 0;
  var vis_ndv = false;
  var have_vis = false;
  var temp_tenths = 0;
  var dew_tenths = 0;
  var have_temp = false;
  var alt_inhg = -1;
  var alt_hpa = -1;
  var have_alt = false;
  var nosig = false;
  var rraw = Vec[Str].new();
  var rrun = Vec[Str].new();
  var rmin = Vec[Int].new();
  var rmax = Vec[Int].new();
  var rpfx = Vec[Int].new();
  var rpfx2 = Vec[Int].new();
  var rvar = Vec[Int].new();
  var runit = Vec[Int].new();
  var rtrend = Vec[Int].new();
  var wraw = Vec[Str].new();
  var wint = Vec[Int].new();
  var wdesc = Vec[Str].new();
  var wphen = Vec[Str].new();
  var wnsw = Vec[Int].new();
  var sraw = Vec[Str].new();
  var scov = Vec[Int].new();
  var shel = Vec[Int].new();
  var styp = Vec[Str].new();
  var extra = Vec[Str].new();
  var stop = false;
  while i < count && !stop {
    let tok: Str = texts[i];
    let off: Int = starts[i];
    var mixed_sm = false;
    if i + 1 < count {
      let nxt: Str = texts[i + 1];
      if _whole_sm_part(tok) && _sm_fraction_milli(nxt) >= 0 { mixed_sm = true; }
    }
    if _str_eq(tok, "RMK") {
      extra.push(tok);
      i = i + 1;
      while i < count {
        let tail: Str = texts[i];
        extra.push(tail);
        i = i + 1;
      }
      stop = true;
    } elif _str_eq(tok, "NOSIG") {
      nosig = true;
      i = i + 1;
    } elif _str_eq(tok, "CAVOK") {
      if have_vis {
        return _err_metar("metar: duplicate visibility at offset " + convert.int_to_string(off) + ": " + tok);
      }
      have_vis = true;
      vis_cavok = true;
      vis_ge10 = true;
      vis_m = 10000;
      i = i + 1;
    } elif _rvr_shape(tok) {
      let rp = _parse_rvr(tok);
      if !rp.ok {
        return _err_metar("metar: invalid RVR at offset " + convert.int_to_string(off) + ": " + tok);
      }
      rraw.push(tok);
      rrun.push(rp.runway);
      rmin.push(rp.min_m);
      rmax.push(rp.max_m);
      rpfx.push(rp.prefix);
      rpfx2.push(rp.prefix2);
      var rv = 0;
      if rp.variable { rv = 1; }
      rvar.push(rv);
      runit.push(rp.unit);
      rtrend.push(rp.trend);
      i = i + 1;
    } elif _vis_meter_token(tok) {
      if have_vis {
        return _err_metar("metar: duplicate visibility at offset " + convert.int_to_string(off) + ": " + tok);
      }
      let vp = _parse_vis_meters(tok);
      have_vis = true;
      vis_m = vp.value_m;
      vis_ge10 = vp.ge_10km;
      vis_ndv = vp.ndv;
      i = i + 1;
    } elif _ends_with(tok, "SM") {
      if have_vis {
        return _err_metar("metar: duplicate visibility at offset " + convert.int_to_string(off) + ": " + tok);
      }
      let vp = _parse_vis_sm(tok);
      if !vp.ok {
        return _err_metar("metar: invalid visibility at offset " + convert.int_to_string(off) + ": " + tok);
      }
      have_vis = true;
      vis_sm = true;
      vis_m = vp.value_m;
      vis_prefix = vp.prefix;
      i = i + 1;
    } elif mixed_sm {
      if have_vis {
        return _err_metar("metar: duplicate visibility at offset " + convert.int_to_string(off) + ": " + tok);
      }
      let nxt2: Str = texts[i + 1];
      let vp = _parse_vis_sm_mixed(tok, nxt2);
      have_vis = true;
      vis_sm = true;
      vis_m = vp.value_m;
      i = i + 2;
    } elif _var_wind_shape(tok) {
      let vfrom = _digits_value(tok, 0, 3);
      let vto = _digits_value(tok, 4, 7);
      if vfrom > 360 || vto > 360 {
        return _err_metar("metar: invalid variable wind at offset " + convert.int_to_string(off) + ": " + tok);
      }
      if have_var {
        return _err_metar("metar: duplicate variable wind at offset " + convert.int_to_string(off) + ": " + tok);
      }
      have_var = true;
      var_from = vfrom;
      var_to = vto;
      i = i + 1;
    } elif _looks_like_wind(tok) {
      let w2 = _parse_wind(tok);
      if !w2.ok {
        return _err_metar("metar: invalid wind at offset " + convert.int_to_string(off) + ": " + tok);
      }
      return _err_metar("metar: duplicate wind at offset " + convert.int_to_string(off) + ": " + tok);
    } else {
      var claimed = false;
      let sp = _parse_sky(tok);
      if sp.ok {
        sraw.push(tok);
        scov.push(sp.cover);
        shel.push(sp.height);
        styp.push(sp.ctype);
        claimed = true;
      }
      if !claimed {
        let wxp = _parse_wx(tok);
        if wxp.ok {
          wraw.push(tok);
          wint.push(wxp.intensity);
          wdesc.push(wxp.descriptor);
          wphen.push(wxp.phenomena);
          var ns = 0;
          if wxp.nsw { ns = 1; }
          wnsw.push(ns);
          claimed = true;
        }
      }
      if !claimed && _has_slash(tok) {
        if have_temp {
          return _err_metar("metar: duplicate temperature at offset " + convert.int_to_string(off) + ": " + tok);
        }
        let tpp = _parse_temp(tok);
        if !tpp.ok {
          return _err_metar("metar: invalid temperature at offset " + convert.int_to_string(off) + ": " + tok);
        }
        have_temp = true;
        temp_tenths = tpp.temp_tenths;
        dew_tenths = tpp.dew_tenths;
        claimed = true;
      }
      if !claimed && tok.len() == 5 {
        let b0 = string.byte_at(tok, 0);
        if b0 == _MT_A || b0 == _MT_Q {
          if have_alt {
            return _err_metar("metar: duplicate altimeter at offset " + convert.int_to_string(off) + ": " + tok);
          }
          let ap = _parse_alt(tok);
          if !ap.ok {
            return _err_metar("metar: invalid altimeter at offset " + convert.int_to_string(off) + ": " + tok);
          }
          have_alt = true;
          if ap.kind == 0 {
            alt_inhg = ap.value;
          } else {
            alt_hpa = ap.value;
          }
          claimed = true;
        }
      }
      if !claimed { extra.push(tok); }
      i = i + 1;
    }
  }
  return _ok_metar(MetarReport{
    station: station;
    report_type: report_type;
    auto_flag: auto_flag;
    cor_flag: cor_flag;
    day: tp.day;
    hour: tp.hour;
    minute: tp.minute;
    wind_dir: wp.dir;
    wind_speed: wp.speed;
    wind_gust: wp.gust;
    wind_unit: wp.unit;
    wind_calm: wp.calm;
    wind_vrb: wp.vrb;
    var_from: var_from;
    var_to: var_to;
    vis_m: vis_m;
    vis_cavok: vis_cavok;
    vis_sm: vis_sm;
    vis_ge_10km: vis_ge10;
    vis_prefix: vis_prefix;
    vis_ndv: vis_ndv;
    rvr_raw: rraw;
    rvr_runway: rrun;
    rvr_min_m: rmin;
    rvr_max_m: rmax;
    rvr_prefix: rpfx;
    rvr_prefix2: rpfx2;
    rvr_variable: rvar;
    rvr_unit: runit;
    rvr_trend: rtrend;
    wx_raw: wraw;
    wx_intensity: wint;
    wx_descriptor: wdesc;
    wx_phenomena: wphen;
    wx_nsw: wnsw;
    sky_raw: sraw;
    sky_cover: scov;
    sky_height: shel;
    sky_type: styp;
    temp_tenths: temp_tenths;
    dew_tenths: dew_tenths;
    have_temp: have_temp;
    alt_inhg100: alt_inhg;
    alt_hpa: alt_hpa;
    nosig: nosig;
    extra: extra;
  });
}

// ---------------------------------------------------------------------------
// METAR accessors
// ---------------------------------------------------------------------------

/// Station designator as written (4 letters, either case; "" only when the
/// report value is used out of range).
/// Complexity: O(1).
pub fn metar_station(r: &MetarReport) -> Str {
  let v: Str = r.station;
  return v;
}

/// Report type: 0 plain, 1 METAR, 2 SPECI.
/// Complexity: O(1).
pub fn metar_report_type(r: &MetarReport) -> Int {
  return r.report_type;
}

/// True when an AUTO token was present.
/// Complexity: O(1).
pub fn metar_is_auto(r: &MetarReport) -> Bool {
  return r.auto_flag;
}

/// True when a COR token was present.
/// Complexity: O(1).
pub fn metar_is_cor(r: &MetarReport) -> Bool {
  return r.cor_flag;
}

/// Observation day-of-month (1-31).
/// Complexity: O(1).
pub fn metar_day(r: &MetarReport) -> Int {
  return r.day;
}

/// Observation hour (0-23).
/// Complexity: O(1).
pub fn metar_hour(r: &MetarReport) -> Int {
  return r.hour;
}

/// Observation minute (0-59).
/// Complexity: O(1).
pub fn metar_minute(r: &MetarReport) -> Int {
  return r.minute;
}

/// Wind direction in whole degrees (0-360), or -1 for VRB.
/// Complexity: O(1).
pub fn metar_wind_dir(r: &MetarReport) -> Int {
  return r.wind_dir;
}

/// Sustained wind speed in the report's unit (Knots or MPS; see
/// metar_wind_unit).
/// Complexity: O(1).
pub fn metar_wind_speed(r: &MetarReport) -> Int {
  return r.wind_speed;
}

/// Wind gust in the report's unit, or -1 when no gust was reported.
/// Complexity: O(1).
pub fn metar_wind_gust(r: &MetarReport) -> Int {
  return r.wind_gust;
}

/// Wind unit: 0 knots (KT), 1 meters per second (MPS).
/// Complexity: O(1).
pub fn metar_wind_unit(r: &MetarReport) -> Int {
  return r.wind_unit;
}

/// True for the calm-wind group 00000 (direction 000, speed 0, no gust).
/// Complexity: O(1).
pub fn metar_wind_is_calm(r: &MetarReport) -> Bool {
  return r.wind_calm;
}

/// True when the direction was VRB (wind_dir is -1).
/// Complexity: O(1).
pub fn metar_wind_is_variable(r: &MetarReport) -> Bool {
  return r.wind_vrb;
}

/// First direction of the dddVddd variability group, or -1 when absent.
/// Complexity: O(1).
pub fn metar_var_from(r: &MetarReport) -> Int {
  return r.var_from;
}

/// Second direction of the dddVddd variability group, or -1 when absent.
/// Complexity: O(1).
pub fn metar_var_to(r: &MetarReport) -> Int {
  return r.var_to;
}

/// Visibility in meters, or -1 when no visibility group was decoded. CAVOK
/// and 9999 both yield at least 10000 (see metar_vis_at_least_10km).
/// Complexity: O(1).
pub fn metar_vis_m(r: &MetarReport) -> Int {
  return r.vis_m;
}

/// True when the visibility group was CAVOK.
/// Complexity: O(1).
pub fn metar_is_cavok(r: &MetarReport) -> Bool {
  return r.vis_cavok;
}

/// True when the visibility was given in statute miles (the stored vis_m is
/// the truncated meter equivalent).
/// Complexity: O(1).
pub fn metar_vis_is_sm(r: &MetarReport) -> Bool {
  return r.vis_sm;
}

/// True when the visibility means "10 km or more" (CAVOK or 9999 meters).
/// Complexity: O(1).
pub fn metar_vis_at_least_10km(r: &MetarReport) -> Bool {
  return r.vis_ge_10km;
}

/// Statute-mile prefix: 0 none, 1 M (less than), 2 P (greater than).
/// Complexity: O(1).
pub fn metar_vis_prefix(r: &MetarReport) -> Int {
  return r.vis_prefix;
}

/// True when the meter visibility carried an NDV suffix.
/// Complexity: O(1).
pub fn metar_vis_is_ndv(r: &MetarReport) -> Bool {
  return r.vis_ndv;
}

/// Number of RVR groups.
/// Complexity: O(1).
pub fn metar_rvr_count(r: &MetarReport) -> Int {
  return r.rvr_raw.len();
}

/// Raw text of RVR group i ("" when out of range).
/// Complexity: O(1).
pub fn metar_rvr_raw(r: &MetarReport, i: Int) -> Str {
  if i < 0 || i >= r.rvr_raw.len() { return ""; }
  let v: Str = r.rvr_raw[i];
  return v;
}

/// Runway designator of RVR group i.
/// Complexity: O(1).
pub fn metar_rvr_runway(r: &MetarReport, i: Int) -> Str {
  if i < 0 || i >= r.rvr_runway.len() { return ""; }
  let v: Str = r.rvr_runway[i];
  return v;
}

/// Lower bound of RVR group i in meters.
/// Complexity: O(1).
pub fn metar_rvr_min_m(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.rvr_min_m.len() { return -1; }
  let v: Int = r.rvr_min_m[i];
  return v;
}

/// Upper bound of RVR group i in meters (equals the lower bound when the
/// group was not variable).
/// Complexity: O(1).
pub fn metar_rvr_max_m(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.rvr_max_m.len() { return -1; }
  let v: Int = r.rvr_max_m[i];
  return v;
}

/// True when RVR group i was a V (variable) range.
/// Complexity: O(1).
pub fn metar_rvr_is_variable(r: &MetarReport, i: Int) -> Bool {
  if i < 0 || i >= r.rvr_variable.len() { return false; }
  let v: Int = r.rvr_variable[i];
  return v == 1;
}

/// Prefix of the first RVR value: 0 none, 1 M, 2 P.
/// Complexity: O(1).
pub fn metar_rvr_prefix(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.rvr_prefix.len() { return 0; }
  let v: Int = r.rvr_prefix[i];
  return v;
}

/// Prefix of the second RVR value: 0 none, 1 M, 2 P.
/// Complexity: O(1).
pub fn metar_rvr_prefix2(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.rvr_prefix2.len() { return 0; }
  let v: Int = r.rvr_prefix2[i];
  return v;
}

/// RVR unit as reported: 0 meters, 1 feet (min/max are always meters).
/// Complexity: O(1).
pub fn metar_rvr_unit(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.rvr_unit.len() { return 0; }
  let v: Int = r.rvr_unit[i];
  return v;
}

/// RVR trend: 0 none, 1 U (up), 2 D (down), 3 N (no change).
/// Complexity: O(1).
pub fn metar_rvr_trend(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.rvr_trend.len() { return 0; }
  let v: Int = r.rvr_trend[i];
  return v;
}

/// Number of present-weather groups.
/// Complexity: O(1).
pub fn metar_weather_count(r: &MetarReport) -> Int {
  return r.wx_raw.len();
}

/// Raw text of weather group i ("" when out of range).
/// Complexity: O(1).
pub fn metar_weather_raw(r: &MetarReport, i: Int) -> Str {
  if i < 0 || i >= r.wx_raw.len() { return ""; }
  let v: Str = r.wx_raw[i];
  return v;
}

/// Intensity of weather group i: 0 moderate, 1 light (-), 2 heavy (+),
/// 3 vicinity (VC).
/// Complexity: O(1).
pub fn metar_weather_intensity(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.wx_intensity.len() { return 0; }
  let v: Int = r.wx_intensity[i];
  return v;
}

/// Descriptor of weather group i ("" when none).
/// Complexity: O(1).
pub fn metar_weather_descriptor(r: &MetarReport, i: Int) -> Str {
  if i < 0 || i >= r.wx_descriptor.len() { return ""; }
  let v: Str = r.wx_descriptor[i];
  return v;
}

/// Concatenated phenomena of weather group i (e.g. "RASN"); "NSW" for the
/// no-significant-weather token.
/// Complexity: O(1).
pub fn metar_weather_phenomena(r: &MetarReport, i: Int) -> Str {
  if i < 0 || i >= r.wx_phenomena.len() { return ""; }
  let v: Str = r.wx_phenomena[i];
  return v;
}

/// True when weather group i is the NSW token.
/// Complexity: O(1).
pub fn metar_weather_is_nsw(r: &MetarReport, i: Int) -> Bool {
  if i < 0 || i >= r.wx_nsw.len() { return false; }
  let v: Int = r.wx_nsw[i];
  return v == 1;
}

/// Number of sky layers.
/// Complexity: O(1).
pub fn metar_sky_count(r: &MetarReport) -> Int {
  return r.sky_raw.len();
}

/// Raw text of sky layer i ("" when out of range).
/// Complexity: O(1).
pub fn metar_sky_raw(r: &MetarReport, i: Int) -> Str {
  if i < 0 || i >= r.sky_raw.len() { return ""; }
  let v: Str = r.sky_raw[i];
  return v;
}

/// Cover of sky layer i: 0 FEW, 1 SCT, 2 BKN, 3 OVC, 4 VV.
/// Complexity: O(1).
pub fn metar_sky_cover(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.sky_cover.len() { return -1; }
  let v: Int = r.sky_cover[i];
  return v;
}

/// Height of sky layer i in feet; -1 for VV/// (unknown vertical visibility).
/// Complexity: O(1).
pub fn metar_sky_height_ft(r: &MetarReport, i: Int) -> Int {
  if i < 0 || i >= r.sky_height.len() { return -1; }
  let v: Int = r.sky_height[i];
  return v;
}

/// Convective type suffix of sky layer i: "" or "CB"/"TCU".
/// Complexity: O(1).
pub fn metar_sky_type(r: &MetarReport, i: Int) -> Str {
  if i < 0 || i >= r.sky_type.len() { return ""; }
  let v: Str = r.sky_type[i];
  return v;
}

/// True when a temperature/dewpoint group was decoded.
/// Complexity: O(1).
pub fn metar_has_temperature(r: &MetarReport) -> Bool {
  return r.have_temp;
}

/// Temperature in tenths of a degree Celsius (only meaningful when
/// metar_has_temperature).
/// Complexity: O(1).
pub fn metar_temperature_tenths(r: &MetarReport) -> Int {
  return r.temp_tenths;
}

/// Dewpoint in tenths of a degree Celsius (only meaningful when
/// metar_has_temperature).
/// Complexity: O(1).
pub fn metar_dewpoint_tenths(r: &MetarReport) -> Int {
  return r.dew_tenths;
}

/// Altimeter in hundredths of inHg (Axxxx form), or -1 when not reported.
/// Complexity: O(1).
pub fn metar_altimeter_inhg100(r: &MetarReport) -> Int {
  return r.alt_inhg100;
}

/// Altimeter in whole hPa (Qxxxx form), or -1 when not reported.
/// Complexity: O(1).
pub fn metar_altimeter_hpa(r: &MetarReport) -> Int {
  return r.alt_hpa;
}

/// True when a NOSIG token was decoded.
/// Complexity: O(1).
pub fn metar_is_nosig(r: &MetarReport) -> Bool {
  return r.nosig;
}

/// Number of extra (unclassified) tokens, including the whole RMK tail.
/// Complexity: O(1).
pub fn metar_extra_count(r: &MetarReport) -> Int {
  return r.extra.len();
}

/// Extra token i ("" when out of range).
/// Complexity: O(1).
pub fn metar_extra(r: &MetarReport, i: Int) -> Str {
  if i < 0 || i >= r.extra.len() { return ""; }
  let v: Str = r.extra[i];
  return v;
}

// ---------------------------------------------------------------------------
// TAF decoder
// ---------------------------------------------------------------------------

fn _new_taf_state() -> _TafState {
  return _TafState{
    fc_kind: Vec[Int].new();
    fc_fday: Vec[Int].new();
    fc_fhour: Vec[Int].new();
    fc_tday: Vec[Int].new();
    fc_thour: Vec[Int].new();
    fc_has_wind: Vec[Int].new();
    fc_wdir: Vec[Int].new();
    fc_wspd: Vec[Int].new();
    fc_wgust: Vec[Int].new();
    fc_wunit: Vec[Int].new();
    fc_has_vis: Vec[Int].new();
    fc_vis_m: Vec[Int].new();
    fc_cavok: Vec[Int].new();
    fc_vis_sm: Vec[Int].new();
    wx_raw: Vec[Str].new();
    wx_group: Vec[Int].new();
    sky_raw: Vec[Str].new();
    sky_group: Vec[Int].new();
    sky_cover: Vec[Int].new();
    sky_height: Vec[Int].new();
    fc_extra: Vec[Str].new();
    fc_extra_group: Vec[Int].new();
    extra: Vec[Str].new();
    cur: -1;
  };
}

// Append one change group, mirroring every parallel vector, and return its
// index. FM groups pass to_day/to_hour -1 (open-ended).
fn _taf_push_group(st: &mut _TafState, kind: Int, fd: Int, fh: Int, td: Int, th: Int) -> Int {
  let g = st.fc_kind.len();
  st.fc_kind.push(kind);
  st.fc_fday.push(fd);
  st.fc_fhour.push(fh);
  st.fc_tday.push(td);
  st.fc_thour.push(th);
  st.fc_has_wind.push(0);
  st.fc_wdir.push(-1);
  st.fc_wspd.push(0);
  st.fc_wgust.push(-1);
  st.fc_wunit.push(0);
  st.fc_has_vis.push(0);
  st.fc_vis_m.push(-1);
  st.fc_cavok.push(0);
  st.fc_vis_sm.push(0);
  return g;
}

// FMDDHH or FMDDHHMM shape (digits only after FM).
fn _fm_shape(t: Str) -> Bool {
  let n = t.len();
  if n != 6 && n != 8 { return false; }
  if !_slice_eq(t, 0, 2, "FM") { return false; }
  return _digits_value(t, 2, n) >= 0;
}

// FMDDHH[MM] time; minute is 0 when only the short form is present.
fn _fm_time(t: Str) -> TimeParse {
  var r = _no_time();
  let n = t.len();
  if n != 6 && n != 8 { return r; }
  if !_slice_eq(t, 0, 2, "FM") { return r; }
  let d = _digits_value(t, 2, 4);
  let h = _digits_value(t, 4, 6);
  if d < 1 || d > 31 { return r; }
  if h < 0 || h > 23 { return r; }
  var m = 0;
  if n == 8 {
    m = _digits_value(t, 6, 8);
    if m < 0 || m > 59 { return r; }
  }
  r.ok = true;
  r.day = d;
  r.hour = h;
  r.minute = m;
  return r;
}

fn _taf_add_fc_extra(st: &mut _TafState, g: Int, tok: Str) {
  st.fc_extra.push(tok);
  st.fc_extra_group.push(g);
}

// Classify one token inside a change group. Wind, visibility (meters, CAVOK,
// SM, mixed SM), sky and weather are decoded when recognized; a duplicate
// wind or visibility and every unrecognized token become group extras. The
// base forecast period (before the first change group) is not decoded.
fn _taf_group_token(st: &mut _TafState, tok: Str) {
  let g = st.cur;
  let w = _parse_wind(tok);
  if w.ok {
    let hw: Int = st.fc_has_wind[g];
    if hw == 0 {
      st.fc_has_wind[g] = 1;
      st.fc_wdir[g] = w.dir;
      st.fc_wspd[g] = w.speed;
      st.fc_wgust[g] = w.gust;
      st.fc_wunit[g] = w.unit;
    } else {
      _taf_add_fc_extra(st, g, tok);
    }
    return;
  }
  if _str_eq(tok, "CAVOK") {
    let hv: Int = st.fc_has_vis[g];
    if hv == 0 {
      st.fc_has_vis[g] = 1;
      st.fc_vis_m[g] = 10000;
      st.fc_cavok[g] = 1;
    } else {
      _taf_add_fc_extra(st, g, tok);
    }
    return;
  }
  if _vis_meter_token(tok) {
    let hv2: Int = st.fc_has_vis[g];
    if hv2 == 0 {
      let v = _parse_vis_meters(tok);
      st.fc_has_vis[g] = 1;
      st.fc_vis_m[g] = v.value_m;
    } else {
      _taf_add_fc_extra(st, g, tok);
    }
    return;
  }
  if _ends_with(tok, "SM") {
    let v2 = _parse_vis_sm(tok);
    if v2.ok {
      let hv3: Int = st.fc_has_vis[g];
      if hv3 == 0 {
        st.fc_has_vis[g] = 1;
        st.fc_vis_m[g] = v2.value_m;
        st.fc_vis_sm[g] = 1;
      } else {
        _taf_add_fc_extra(st, g, tok);
      }
    } else {
      _taf_add_fc_extra(st, g, tok);
    }
    return;
  }
  let sp = _parse_sky(tok);
  if sp.ok {
    st.sky_raw.push(tok);
    st.sky_group.push(g);
    st.sky_cover.push(sp.cover);
    st.sky_height.push(sp.height);
    return;
  }
  let wxp = _parse_wx(tok);
  if wxp.ok {
    st.wx_raw.push(tok);
    st.wx_group.push(g);
    return;
  }
  _taf_add_fc_extra(st, g, tok);
}

/// Decode one TAF.
/// Params: s - the whole forecast text; tokens are separated by runs of
/// ASCII space or tab.
/// Grammar: an optional TAF keyword, optional AMD and/or COR flags, the
/// required station (4 letters), the required issue time (DDHHMMZ or DDHHZ),
/// and the required validity period DDHH/DDHH. The rest of the report is a
/// sequence of change groups:
///   * TEMPO DDHH/DDHH -- temporary fluctuations,
///   * BECMG DDHH/DDHH -- gradual change,
///   * FMDDHH[MM] -- instantaneous change to the following conditions.
/// Inside a change group, wind (metar wind grammar), visibility (4-digit
/// meters, CAVOK, dSM / p/qSM / d p/qSM), sky layers and present-weather
/// groups are decoded when present; everything else is preserved in the
/// group's extra list. Tokens before the first change group are preserved in
/// the report-level extra list (the base forecast period is not decoded).
/// Returns: Ok(TafReport).
/// Error case: Err("taf: ...") for a missing/malformed station, issue time or
/// validity, a missing/malformed validity after TEMPO/BECMG, and a malformed
/// FM time; messages carry the byte offset and offending token.
/// Complexity: O(len(s)) plus O(1) per token.
pub fn taf_decode(s: Str) -> Result[TafReport, Str] {
  var texts = Vec[Str].new();
  var starts = Vec[Int].new();
  _scan_tokens(s, &mut texts, &mut starts);
  let count = texts.len();
  var i = 0;
  var amd_flag = false;
  var cor_flag = false;
  if i < count {
    let t0: Str = texts[i];
    if _str_eq(t0, "TAF") { i = i + 1; }
  }
  while i < count {
    let tf: Str = texts[i];
    if _str_eq(tf, "AMD") {
      amd_flag = true;
      i = i + 1;
    } elif _str_eq(tf, "COR") {
      cor_flag = true;
      i = i + 1;
    } else {
      break;
    }
  }
  if i >= count {
    return _err_taf("taf: missing station at offset " + convert.int_to_string(s.len()));
  }
  let station: Str = texts[i];
  let st_off: Int = starts[i];
  if !_is_icao(station) {
    return _err_taf("taf: invalid station at offset " + convert.int_to_string(st_off) + ": " + station);
  }
  i = i + 1;
  if i >= count {
    return _err_taf("taf: missing time at offset " + convert.int_to_string(s.len()));
  }
  let time_tok: Str = texts[i];
  let time_off: Int = starts[i];
  let tp = _parse_issue_time(time_tok);
  if !tp.ok {
    return _err_taf("taf: invalid time at offset " + convert.int_to_string(time_off) + ": " + time_tok);
  }
  i = i + 1;
  if i >= count {
    return _err_taf("taf: missing validity at offset " + convert.int_to_string(s.len()));
  }
  let val_tok: Str = texts[i];
  let val_off: Int = starts[i];
  let vp = _parse_validity(val_tok);
  if !vp.ok {
    return _err_taf("taf: invalid validity at offset " + convert.int_to_string(val_off) + ": " + val_tok);
  }
  i = i + 1;
  var st = _new_taf_state();
  while i < count {
    let tok: Str = texts[i];
    let off: Int = starts[i];
    var mixed_sm = false;
    if i + 1 < count {
      let nxt: Str = texts[i + 1];
      if _whole_sm_part(tok) && _sm_fraction_milli(nxt) >= 0 { mixed_sm = true; }
    }
    if _str_eq(tok, "TEMPO") || _str_eq(tok, "BECMG") {
      var kind = 1;
      if _str_eq(tok, "BECMG") { kind = 0; }
      i = i + 1;
      if i >= count {
        return _err_taf("taf: missing validity after " + tok + " at offset " + convert.int_to_string(s.len()));
      }
      let vt: Str = texts[i];
      let voff: Int = starts[i];
      let v2 = _parse_validity(vt);
      if !v2.ok {
        return _err_taf("taf: invalid validity at offset " + convert.int_to_string(voff) + ": " + vt);
      }
      let g = _taf_push_group(&mut st, kind, v2.from_day, v2.from_hour, v2.to_day, v2.to_hour);
      st.cur = g;
      i = i + 1;
    } elif _fm_shape(tok) {
      let f = _fm_time(tok);
      if !f.ok {
        return _err_taf("taf: invalid FM time at offset " + convert.int_to_string(off) + ": " + tok);
      }
      let g2 = _taf_push_group(&mut st, 2, f.day, f.hour, -1, -1);
      st.cur = g2;
      i = i + 1;
    } elif mixed_sm {
      if st.cur < 0 {
        st.extra.push(tok);
        i = i + 1;
      } else {
        let g3 = st.cur;
        let hv: Int = st.fc_has_vis[g3];
        if hv == 0 {
          let nxt2: Str = texts[i + 1];
          let v3 = _parse_vis_sm_mixed(tok, nxt2);
          st.fc_has_vis[g3] = 1;
          st.fc_vis_m[g3] = v3.value_m;
          st.fc_vis_sm[g3] = 1;
          i = i + 2;
        } else {
          _taf_add_fc_extra(&mut st, g3, tok);
          i = i + 1;
        }
      }
    } else {
      if st.cur < 0 {
        st.extra.push(tok);
      } else {
        _taf_group_token(&mut st, tok);
      }
      i = i + 1;
    }
  }
  return _ok_taf(TafReport{
    station: station;
    amd_flag: amd_flag;
    cor_flag: cor_flag;
    day: tp.day;
    hour: tp.hour;
    minute: tp.minute;
    vfrom_day: vp.from_day;
    vfrom_hour: vp.from_hour;
    vto_day: vp.to_day;
    vto_hour: vp.to_hour;
    fc_kind: st.fc_kind;
    fc_fday: st.fc_fday;
    fc_fhour: st.fc_fhour;
    fc_tday: st.fc_tday;
    fc_thour: st.fc_thour;
    fc_has_wind: st.fc_has_wind;
    fc_wdir: st.fc_wdir;
    fc_wspd: st.fc_wspd;
    fc_wgust: st.fc_wgust;
    fc_wunit: st.fc_wunit;
    fc_has_vis: st.fc_has_vis;
    fc_vis_m: st.fc_vis_m;
    fc_cavok: st.fc_cavok;
    fc_vis_sm: st.fc_vis_sm;
    wx_raw: st.wx_raw;
    wx_group: st.wx_group;
    sky_raw: st.sky_raw;
    sky_group: st.sky_group;
    sky_cover: st.sky_cover;
    sky_height: st.sky_height;
    fc_extra: st.fc_extra;
    fc_extra_group: st.fc_extra_group;
    extra: st.extra;
  });
}

// ---------------------------------------------------------------------------
// TAF accessors
// ---------------------------------------------------------------------------

/// Station designator as written.
/// Complexity: O(1).
pub fn taf_station(t: &TafReport) -> Str {
  let v: Str = t.station;
  return v;
}

/// True when an AMD token was present.
/// Complexity: O(1).
pub fn taf_is_amd(t: &TafReport) -> Bool {
  return t.amd_flag;
}

/// True when a COR token was present.
/// Complexity: O(1).
pub fn taf_is_cor(t: &TafReport) -> Bool {
  return t.cor_flag;
}

/// Issue day-of-month (1-31).
/// Complexity: O(1).
pub fn taf_day(t: &TafReport) -> Int {
  return t.day;
}

/// Issue hour (0-23).
/// Complexity: O(1).
pub fn taf_hour(t: &TafReport) -> Int {
  return t.hour;
}

/// Issue minute (0-59); 0 for the short DDHHZ form.
/// Complexity: O(1).
pub fn taf_minute(t: &TafReport) -> Int {
  return t.minute;
}

/// Validity start day (1-31).
/// Complexity: O(1).
pub fn taf_valid_from_day(t: &TafReport) -> Int {
  return t.vfrom_day;
}

/// Validity start hour (0-23).
/// Complexity: O(1).
pub fn taf_valid_from_hour(t: &TafReport) -> Int {
  return t.vfrom_hour;
}

/// Validity end day (1-31).
/// Complexity: O(1).
pub fn taf_valid_to_day(t: &TafReport) -> Int {
  return t.vto_day;
}

/// Validity end hour (0-23).
/// Complexity: O(1).
pub fn taf_valid_to_hour(t: &TafReport) -> Int {
  return t.vto_hour;
}

/// Number of forecast change groups.
/// Complexity: O(1).
pub fn taf_forecast_count(t: &TafReport) -> Int {
  return t.fc_kind.len();
}

/// Kind of change group g: 0 BECMG, 1 TEMPO, 2 FM (-1 when out of range).
/// Complexity: O(1).
pub fn taf_fc_kind(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_kind.len() { return -1; }
  let v: Int = t.fc_kind[g];
  return v;
}

/// Change-group start day.
/// Complexity: O(1).
pub fn taf_fc_from_day(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_fday.len() { return -1; }
  let v: Int = t.fc_fday[g];
  return v;
}

/// Change-group start hour.
/// Complexity: O(1).
pub fn taf_fc_from_hour(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_fhour.len() { return -1; }
  let v: Int = t.fc_fhour[g];
  return v;
}

/// Change-group end day; -1 for FM groups (open-ended).
/// Complexity: O(1).
pub fn taf_fc_to_day(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_tday.len() { return -1; }
  let v: Int = t.fc_tday[g];
  return v;
}

/// Change-group end hour; -1 for FM groups (open-ended).
/// Complexity: O(1).
pub fn taf_fc_to_hour(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_thour.len() { return -1; }
  let v: Int = t.fc_thour[g];
  return v;
}

/// True when change group g carried a wind group.
/// Complexity: O(1).
pub fn taf_fc_has_wind(t: &TafReport, g: Int) -> Bool {
  if g < 0 || g >= t.fc_has_wind.len() { return false; }
  let v: Int = t.fc_has_wind[g];
  return v == 1;
}

/// Wind direction of change group g (0-360, -1 for VRB/absent).
/// Complexity: O(1).
pub fn taf_fc_wind_dir(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_wdir.len() { return -1; }
  let v: Int = t.fc_wdir[g];
  return v;
}

/// Wind speed of change group g.
/// Complexity: O(1).
pub fn taf_fc_wind_speed(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_wspd.len() { return -1; }
  let v: Int = t.fc_wspd[g];
  return v;
}

/// Wind gust of change group g, or -1 when absent.
/// Complexity: O(1).
pub fn taf_fc_wind_gust(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_wgust.len() { return -1; }
  let v: Int = t.fc_wgust[g];
  return v;
}

/// Wind unit of change group g: 0 KT, 1 MPS.
/// Complexity: O(1).
pub fn taf_fc_wind_unit(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_wunit.len() { return 0; }
  let v: Int = t.fc_wunit[g];
  return v;
}

/// True when change group g carried a visibility group.
/// Complexity: O(1).
pub fn taf_fc_has_vis(t: &TafReport, g: Int) -> Bool {
  if g < 0 || g >= t.fc_has_vis.len() { return false; }
  let v: Int = t.fc_has_vis[g];
  return v == 1;
}

/// Visibility of change group g in meters, or -1 when absent.
/// Complexity: O(1).
pub fn taf_fc_vis_m(t: &TafReport, g: Int) -> Int {
  if g < 0 || g >= t.fc_vis_m.len() { return -1; }
  let v: Int = t.fc_vis_m[g];
  return v;
}

/// True when change group g's visibility was CAVOK.
/// Complexity: O(1).
pub fn taf_fc_is_cavok(t: &TafReport, g: Int) -> Bool {
  if g < 0 || g >= t.fc_cavok.len() { return false; }
  let v: Int = t.fc_cavok[g];
  return v == 1;
}

/// True when change group g's visibility was given in statute miles.
/// Complexity: O(1).
pub fn taf_fc_vis_is_sm(t: &TafReport, g: Int) -> Bool {
  if g < 0 || g >= t.fc_vis_sm.len() { return false; }
  let v: Int = t.fc_vis_sm[g];
  return v == 1;
}

/// Number of weather tokens decoded inside change groups.
/// Complexity: O(1).
pub fn taf_weather_count(t: &TafReport) -> Int {
  return t.wx_raw.len();
}

/// Raw text of weather entry k ("" when out of range).
/// Complexity: O(1).
pub fn taf_weather_raw(t: &TafReport, k: Int) -> Str {
  if k < 0 || k >= t.wx_raw.len() { return ""; }
  let v: Str = t.wx_raw[k];
  return v;
}

/// Owning change group of weather entry k (-1 when out of range).
/// Complexity: O(1).
pub fn taf_weather_group(t: &TafReport, k: Int) -> Int {
  if k < 0 || k >= t.wx_group.len() { return -1; }
  let v: Int = t.wx_group[k];
  return v;
}

/// Number of sky layers decoded inside change groups.
/// Complexity: O(1).
pub fn taf_sky_count(t: &TafReport) -> Int {
  return t.sky_raw.len();
}

/// Raw text of sky entry k ("" when out of range).
/// Complexity: O(1).
pub fn taf_sky_raw(t: &TafReport, k: Int) -> Str {
  if k < 0 || k >= t.sky_raw.len() { return ""; }
  let v: Str = t.sky_raw[k];
  return v;
}

/// Owning change group of sky entry k (-1 when out of range).
/// Complexity: O(1).
pub fn taf_sky_group(t: &TafReport, k: Int) -> Int {
  if k < 0 || k >= t.sky_group.len() { return -1; }
  let v: Int = t.sky_group[k];
  return v;
}

/// Cover of sky entry k: 0 FEW, 1 SCT, 2 BKN, 3 OVC, 4 VV.
/// Complexity: O(1).
pub fn taf_sky_cover(t: &TafReport, k: Int) -> Int {
  if k < 0 || k >= t.sky_cover.len() { return -1; }
  let v: Int = t.sky_cover[k];
  return v;
}

/// Height of sky entry k in feet (-1 for VV///).
/// Complexity: O(1).
pub fn taf_sky_height_ft(t: &TafReport, k: Int) -> Int {
  if k < 0 || k >= t.sky_height.len() { return -1; }
  let v: Int = t.sky_height[k];
  return v;
}

/// Number of unclassified tokens inside change group g.
/// Complexity: O(entries).
pub fn taf_fc_extra_count(t: &TafReport, g: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < t.fc_extra_group.len() {
    let gi: Int = t.fc_extra_group[i];
    if gi == g { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// k-th unclassified token of change group g ("" when out of range).
/// Complexity: O(entries).
pub fn taf_fc_extra(t: &TafReport, g: Int, k: Int) -> Str {
  if k < 0 { return ""; }
  var seen = 0;
  var i = 0;
  while i < t.fc_extra_group.len() {
    let gi: Int = t.fc_extra_group[i];
    if gi == g {
      if seen == k {
        let v: Str = t.fc_extra[i];
        return v;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

/// Number of report-level extra tokens (the undecoded base forecast period
/// and any other pre-change tokens).
/// Complexity: O(1).
pub fn taf_extra_count(t: &TafReport) -> Int {
  return t.extra.len();
}

/// Report-level extra token k ("" when out of range).
/// Complexity: O(1).
pub fn taf_extra(t: &TafReport, k: Int) -> Str {
  if k < 0 || k >= t.extra.len() { return ""; }
  let v: Str = t.extra[k];
  return v;
}
