// XIOM -- xiom.weather: METAR observation decoding (wind, visibility,
// temperature, altimeter, cloud ceiling, flight category)
// Port task: replace the xiom.weather placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one raw METAR observation string ("EGLL 121150Z 24012KT 9999 SCT020
// 18/12 Q1013") is split on runs of ASCII space/tab and scanned token by
// token. Every token that matches a known shape fills one part of Metar;
// every other token is ignored, so real reports decode even with remarks,
// trend groups, RVR, wind-variability and other extension tokens present
// (see SPEC.md section 3). Missing numeric values are -1; see SPEC.md
// section 6 for the one collision this sentinel causes (a genuine -1 degC
// temperature is indistinguishable from "not reported").
//
// Language notes (XIOM v0.61.3):
//   * free functions only: no self methods, no lambdas, no Vec[StructType];
//   * Ok/Err are constructed only in the tiny leaf helpers below
//     (constructing a Result inline in a function that also returns a struct
//     miscompiles);
//   * Str comparisons route through xiom.string.compare.str_compare, never
//     `==` (BUG 17: `==` on a Str read from a Vec[Str] element lowers to a
//     pointer comparison);
//   * Vec[Str] element reads are bound with a typed `let` before use;
//   * xiom.string.byte_at results are widened to Int before arithmetic.

module xiom.weather

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _MET_TAB: UInt8 = 9u8;
const _MET_SPACE: UInt8 = 32u8;
const _MET_SLASH: UInt8 = 47u8;
const _MET_ZERO: UInt8 = 48u8;
const _MET_NINE: UInt8 = 57u8;
const _MET_A: UInt8 = 65u8;
const _MET_B: UInt8 = 66u8;
const _MET_C: UInt8 = 67u8;
const _MET_E: UInt8 = 69u8;
const _MET_F: UInt8 = 70u8;
const _MET_G: UInt8 = 71u8;
const _MET_K: UInt8 = 75u8;
const _MET_M: UInt8 = 77u8;
const _MET_N: UInt8 = 78u8;
const _MET_O: UInt8 = 79u8;
const _MET_Q: UInt8 = 81u8;
const _MET_R: UInt8 = 82u8;
const _MET_S: UInt8 = 83u8;
const _MET_T: UInt8 = 84u8;
const _MET_V: UInt8 = 86u8;
const _MET_W: UInt8 = 87u8;
const _MET_Z: UInt8 = 90u8;
const _MET_LOWER_A: UInt8 = 97u8;
const _MET_LOWER_Z: UInt8 = 122u8;
const _MET_CAVOK_VIS: Int = 10000;
const _MET_M_PER_SM: Int = 1609;

/// A decoded METAR observation. Every numeric field is -1 when the report
/// did not carry the value in a recognized token. Units are fixed:
/// wind_dir_deg degrees true (0-360, -1 for variable/missing), wind_speed_kt
/// and wind_gust_kt knots, visibility_m meters, temp_c and dewpoint_c degrees
/// Celsius, altimeter_hpa hectopascals, ceiling_ft feet AGL.
pub type Metar = {
  station: Str;
  day: Int;
  hour: Int;
  minute: Int;
  wind_dir_deg: Int;
  wind_speed_kt: Int;
  wind_gust_kt: Int;
  visibility_m: Int;
  temp_c: Int;
  dewpoint_c: Int;
  altimeter_hpa: Int;
  ceiling_ft: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (compiler workaround; see the module header)
// ---------------------------------------------------------------------------

fn _ok_metar(m: Metar) -> Result[Metar, Str] {
  return Ok(m);
}

fn _err_metar(msg: Str) -> Result[Metar, Str] {
  return Err(msg);
}

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

fn _is_ws_byte(b: UInt8) -> Bool {
  return b == _MET_SPACE || b == _MET_TAB;
}

fn _is_digit(b: UInt8) -> Bool {
  return b >= _MET_ZERO && b <= _MET_NINE;
}

// Byte-equal test; BUG 17 discipline (never `==` on Str).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Split on runs of ASCII space/tab; leading/trailing whitespace is dropped.
fn _split_fields(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = text.len();
  var i = 0;
  while i < n {
    while i < n && _is_ws_byte(string.byte_at(text, i)) { i = i + 1; }
    if i >= n { break; }
    var j = i;
    while j < n && !_is_ws_byte(string.byte_at(text, j)) { j = j + 1; }
    out.push(string.str_slice(text, i, j));
    i = j;
  }
  return out;
}

// True for exactly four ASCII letters, either case (real reports are upper
// case; the caller's text is preserved verbatim).
fn _is_station(s: Str) -> Bool {
  if s.len() != 4 { return false; }
  var i = 0;
  while i < 4 {
    let b = string.byte_at(s, i);
    let upper = b >= _MET_A && b <= _MET_Z;
    let lower = b >= _MET_LOWER_A && b <= _MET_LOWER_Z;
    if !upper && !lower { return false; }
    i = i + 1;
  }
  return true;
}

// Decimal value of s[start, end); -1 when the run is empty or has a non-digit
// byte. Callers that need "missing" vs "invalid" separate the two cases first.
fn _digits_value(s: Str, start: Int, end: Int) -> Int {
  if start >= end { return -1; }
  var acc = 0;
  var i = start;
  while i < end {
    let b = string.byte_at(s, i);
    if !_is_digit(b) { return -1; }
    acc = acc * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  return acc;
}

fn _find_byte(s: Str, target: UInt8) -> Int {
  var i = 0;
  while i < s.len() {
    if string.byte_at(s, i) == target { return i; }
    i = i + 1;
  }
  return -1;
}

// 3-digit zero-padded non-negative integer (wind direction).
fn _pad3(v: Int) -> Str {
  if v < 10 { return "00" + convert.int_to_string(v); }
  if v < 100 { return "0" + convert.int_to_string(v); }
  return convert.int_to_string(v);
}

// ---------------------------------------------------------------------------
// Token recognizers. Each returns None when the token is not exactly this
// shape; a recognized shape always yields a complete value group.
// ---------------------------------------------------------------------------

// DDHHMMZ, with day 1-31, hour 0-23 and minute 0-59.
fn _parse_time(tok: Str) -> Option[(Int, Int, Int)] {
  if tok.len() != 7 { return None; }
  if string.byte_at(tok, 6) != _MET_Z { return None; }
  let day = _digits_value(tok, 0, 2);
  let hour = _digits_value(tok, 2, 4);
  let minute = _digits_value(tok, 4, 6);
  if day < 1 || day > 31 { return None; }
  if hour < 0 || hour > 23 { return None; }
  if minute < 0 || minute > 59 { return None; }
  return Some((day, hour, minute));
}

// True when the first three bytes of a 7-byte token are "VRB".
fn _is_vrb(tok: Str) -> Bool {
  let b0 = string.byte_at(tok, 0);
  if b0 != _MET_V { return false; }
  return string.byte_at(tok, 1) == _MET_R && string.byte_at(tok, 2) == _MET_B;
}

// dddssKT (dir 0-360, speed 2 digits), dddssGggKT (adds a gust) or VRBssKT.
// Direction is -1 for VRB; gust is -1 when not reported. Anything else,
// including out-of-range directions, is not a wind token.
fn _parse_wind(tok: Str) -> Option[(Int, Int, Int)] {
  let n = tok.len();
  if n == 7 {
    if string.byte_at(tok, 5) != _MET_K { return None; }
    if string.byte_at(tok, 6) != _MET_T { return None; }
    if _is_vrb(tok) {
      let speed = _digits_value(tok, 3, 5);
      if speed < 0 { return None; }
      return Some((-1, speed, -1));
    }
    let dir = _digits_value(tok, 0, 3);
    if dir < 0 || dir > 360 { return None; }
    let speed = _digits_value(tok, 3, 5);
    if speed < 0 { return None; }
    return Some((dir, speed, -1));
  }
  if n == 10 {
    if string.byte_at(tok, 5) != _MET_G { return None; }
    if string.byte_at(tok, 8) != _MET_K { return None; }
    if string.byte_at(tok, 9) != _MET_T { return None; }
    let dir = _digits_value(tok, 0, 3);
    if dir < 0 || dir > 360 { return None; }
    let speed = _digits_value(tok, 3, 5);
    let gust = _digits_value(tok, 6, 8);
    if speed < 0 || gust < 0 { return None; }
    return Some((dir, speed, gust));
  }
  return None;
}

// Exactly four digits (0-9999 meters), or 1-4 digits followed by SM
// (statute miles, n * 1609 meters). CAVOK is handled by the caller because it
// also clears the ceiling.
fn _parse_visibility(tok: Str) -> Option[Int] {
  let n = tok.len();
  if n >= 3 && n <= 7 {
    if string.byte_at(tok, n - 2) == _MET_S && string.byte_at(tok, n - 1) == _MET_M {
      let miles = _digits_value(tok, 0, n - 2);
      if miles < 0 { return None; }
      return Some(miles * _MET_M_PER_SM);
    }
  }
  if n == 4 {
    let meters = _digits_value(tok, 0, 4);
    if meters < 0 { return None; }
    return Some(meters);
  }
  return None;
}

// One side of a temperature token: empty means missing (-1); otherwise an
// optional 'M' prefix and one or two digits.
fn _temp_part_ok(s: Str, start: Int, end: Int) -> Bool {
  if start == end { return true; }
  var i = start;
  if string.byte_at(s, i) == _MET_M { i = i + 1; }
  let digits = end - i;
  if digits < 1 || digits > 2 { return false; }
  return _digits_value(s, i, end) >= 0;
}

fn _temp_part_value(s: Str, start: Int, end: Int) -> Int {
  if start == end { return -1; }
  var i = start;
  var neg = false;
  if string.byte_at(s, i) == _MET_M {
    neg = true;
    i = i + 1;
  }
  let v = _digits_value(s, i, end);
  if neg { return 0 - v; }
  return v;
}

// TT/TT or MTT/MTT with exactly one '/'; either side may be empty, which
// decodes to -1 for that value.
fn _parse_temperature(tok: Str) -> Option[(Int, Int)] {
  let slash = _find_byte(tok, _MET_SLASH);
  if slash < 0 { return None; }
  var i = slash + 1;
  while i < tok.len() {
    if string.byte_at(tok, i) == _MET_SLASH { return None; }
    i = i + 1;
  }
  if !_temp_part_ok(tok, 0, slash) { return None; }
  if !_temp_part_ok(tok, slash + 1, tok.len()) { return None; }
  let temp = _temp_part_value(tok, 0, slash);
  let dew = _temp_part_value(tok, slash + 1, tok.len());
  return Some((temp, dew));
}

// True for the FEW/SCT/BKN/OVC prefixes of a 6-byte cloud token.
fn _is_cloud_prefix(tok: Str) -> Bool {
  let b0 = string.byte_at(tok, 0);
  if b0 == _MET_F {
    return string.byte_at(tok, 1) == _MET_E && string.byte_at(tok, 2) == _MET_W;
  }
  if b0 == _MET_S {
    return string.byte_at(tok, 1) == _MET_C && string.byte_at(tok, 2) == _MET_T;
  }
  if b0 == _MET_B {
    return string.byte_at(tok, 1) == _MET_K && string.byte_at(tok, 2) == _MET_N;
  }
  if b0 == _MET_O {
    return string.byte_at(tok, 1) == _MET_V && string.byte_at(tok, 2) == _MET_C;
  }
  return false;
}

// Layer height in feet for a BKN/OVC token (the only layers that form a
// ceiling); None for FEW/SCT and for every other token. Heights > 999 are
// impossible in the 3-digit form.
fn _parse_ceiling(tok: Str) -> Option[Int] {
  if tok.len() != 6 { return None; }
  if !_is_cloud_prefix(tok) { return None; }
  let b0 = string.byte_at(tok, 0);
  if b0 != _MET_B && b0 != _MET_O { return None; }
  let hundreds = _digits_value(tok, 3, 6);
  if hundreds < 0 { return None; }
  return Some(hundreds * 100);
}

// Q0998 (already hPa) or A2992 (hundredths of inHg -> hPa, truncated:
// hPa = value * 3386 / 10000, so A2992 -> 1013).
fn _parse_altimeter(tok: Str) -> Option[Int] {
  if tok.len() != 5 { return None; }
  let b0 = string.byte_at(tok, 0);
  let v = _digits_value(tok, 1, 5);
  if v < 0 { return None; }
  if b0 == _MET_Q { return Some(v); }
  if b0 == _MET_A { return Some(v * 3386 / 10000); }
  return None;
}

// ---------------------------------------------------------------------------
// Struct construction (never through Ok/Err; see the module header)
// ---------------------------------------------------------------------------

fn _make_metar(station: Str, day: Int, hour: Int, minute: Int, wind_dir_deg: Int, wind_speed_kt: Int, wind_gust_kt: Int, visibility_m: Int, temp_c: Int, dewpoint_c: Int, altimeter_hpa: Int, ceiling_ft: Int) -> Metar {
  return Metar{
    station: station;
    day: day;
    hour: hour;
    minute: minute;
    wind_dir_deg: wind_dir_deg;
    wind_speed_kt: wind_speed_kt;
    wind_gust_kt: wind_gust_kt;
    visibility_m: visibility_m;
    temp_c: temp_c;
    dewpoint_c: dewpoint_c;
    altimeter_hpa: altimeter_hpa;
    ceiling_ft: ceiling_ft;
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse one METAR observation.
/// Params: raw - the observation text; tokens are separated by runs of ASCII
/// space or tab.
/// Grammar: the first token must be a four-letter station (either case;
/// stored verbatim). The remaining tokens are scanned independently:
/// DDHHMMZ time; dddssKT / dddssGggKT / VRBssKT wind (dir 0-360); 4-digit
/// meters, CAVOK (10000 m and ceiling -1) or 1-4 digits + SM visibility;
/// FEW/SCT/BKN/OVC + 3-digit hundreds of feet clouds (ceiling = the lowest
/// BKN/OVC layer); TT/TT or MTT/MTT temperature/dewpoint with either side
/// allowed to be empty; Qdddd hPa or Adddd hundredths of inHg altimeter.
/// Unknown tokens (remarks, trends, RVR, ...) are ignored. Later recognized
/// tokens of a kind overwrite earlier ones.
/// Returns: Ok(Metar); every value the report did not carry stays -1.
/// Error case: Err("metar: empty observation") when there is no token at all;
/// Err("metar: invalid station: <token>") when the first token is not four
/// ASCII letters.
/// Complexity: O(len(raw)) plus O(1) per token.
pub fn metar_parse(raw: Str) -> Result[Metar, Str] {
  let fields = _split_fields(raw);
  if fields.len() == 0 {
    return _err_metar("metar: empty observation");
  }
  let station: Str = fields[0];
  if !_is_station(station) {
    return _err_metar("metar: invalid station: " + station);
  }
  var day = -1;
  var hour = -1;
  var minute = -1;
  var wind_dir_deg = -1;
  var wind_speed_kt = -1;
  var wind_gust_kt = -1;
  var visibility_m = -1;
  var temp_c = -1;
  var dewpoint_c = -1;
  var altimeter_hpa = -1;
  var ceiling_ft = -1;
  var i = 1;
  while i < fields.len() {
    let tok: Str = fields[i];
    let t = _parse_time(tok);
    match t {
      Some((d, h, mi)) => { day = d; hour = h; minute = mi; },
      None => {},
    }
    let w = _parse_wind(tok);
    match w {
      Some((dir, speed, gust)) => { wind_dir_deg = dir; wind_speed_kt = speed; wind_gust_kt = gust; },
      None => {},
    }
    if _streq(tok, "CAVOK") {
      visibility_m = _MET_CAVOK_VIS;
      ceiling_ft = -1;
    } else {
      let v = _parse_visibility(tok);
      match v {
        Some(meters) => { visibility_m = meters; },
        None => {},
      }
    }
    let tp = _parse_temperature(tok);
    match tp {
      Some((t_c, d_c)) => { temp_c = t_c; dewpoint_c = d_c; },
      None => {},
    }
    let al = _parse_altimeter(tok);
    match al {
      Some(hpa) => { altimeter_hpa = hpa; },
      None => {},
    }
    let cl = _parse_ceiling(tok);
    match cl {
      Some(ft) => {
        if ceiling_ft < 0 || ft < ceiling_ft { ceiling_ft = ft; }
      },
      None => {},
    }
    i = i + 1;
  }
  return _ok_metar(_make_metar(station, day, hour, minute, wind_dir_deg, wind_speed_kt, wind_gust_kt, visibility_m, temp_c, dewpoint_c, altimeter_hpa, ceiling_ft));
}

// Category rank from a visibility in meters; missing (negative) imposes no
// restriction.
fn _visibility_rank(vis_m: Int) -> Int {
  if vis_m < 0 { return 3; }
  if vis_m < 1600 { return 0; }
  if vis_m < 4800 { return 1; }
  if vis_m < 8000 { return 2; }
  return 3;
}

// Category rank from a ceiling in feet AGL; missing (negative) imposes no
// restriction.
fn _ceiling_rank(ceiling_ft: Int) -> Int {
  if ceiling_ft < 0 { return 3; }
  if ceiling_ft < 500 { return 0; }
  if ceiling_ft < 1000 { return 1; }
  if ceiling_ft < 3000 { return 2; }
  return 3;
}

/// FAA-style flight category of a decoded observation.
/// Params: m - the decoded observation.
/// Returns: "LIFR" (visibility < 1600 m or ceiling < 500 ft), "IFR"
/// (< 4800 m or < 1000 ft), "MVFR" (< 8000 m or < 3000 ft), else "VFR".
/// The most restrictive of the two rules wins; a missing visibility or
/// ceiling imposes no restriction, so an observation without either is VFR.
/// Complexity: O(1).
pub fn metar_flight_category(m: &Metar) -> Str {
  let vis_rank = _visibility_rank(m.visibility_m);
  let ceil_rank = _ceiling_rank(m.ceiling_ft);
  var rank = vis_rank;
  if ceil_rank < rank { rank = ceil_rank; }
  if rank <= 0 { return "LIFR"; }
  if rank == 1 { return "IFR"; }
  if rank == 2 { return "MVFR"; }
  return "VFR";
}

/// Reported wind speed, in knots.
/// Params: m - the decoded observation.
/// Returns: the sustained wind speed (wind_speed_kt); a reported gust is
/// exposed separately as Metar.wind_gust_kt. -1 when no wind token was seen.
/// Complexity: O(1).
pub fn metar_wind_kt(m: &Metar) -> Int {
  return m.wind_speed_kt;
}

/// Reported air temperature, in degrees Celsius.
/// Params: m - the decoded observation.
/// Returns: temp_c; -1 when not reported (which is also how a genuine -1 degC
/// reading is stored; see SPEC.md section 6).
/// Complexity: O(1).
pub fn metar_temperature_c(m: &Metar) -> Int {
  return m.temp_c;
}

// Wind field of the summary: "ddd/sskt", "VRB/sskt", or "///" elements for a
// missing direction/speed.
fn _wind_text(m: &Metar) -> Str {
  var dir = "///";
  if m.wind_dir_deg >= 0 {
    dir = _pad3(m.wind_dir_deg);
  } elif m.wind_speed_kt >= 0 {
    dir = "VRB";
  }
  var speed = "///";
  if m.wind_speed_kt >= 0 {
    speed = convert.int_to_string(m.wind_speed_kt);
  }
  return dir + "/" + speed + "kt";
}

// Visibility field of the summary: "1234m" or "///".
fn _visibility_text(vis_m: Int) -> Str {
  if vis_m < 0 { return "///"; }
  return convert.int_to_string(vis_m) + "m";
}

// Temperature/dewpoint element: the signed value, or "///" for missing.
// Because -1 marks "missing", a genuine -1 degC reading also renders as
// "///" (SPEC.md section 6).
fn _temperature_text(c: Int) -> Str {
  if c == -1 { return "///"; }
  return convert.int_to_string(c);
}

// Altimeter field of the summary: "Q1013" or "Q///".
fn _altimeter_text(hpa: Int) -> Str {
  if hpa < 0 { return "Q///"; }
  return "Q" + convert.int_to_string(hpa);
}

/// One-line human-readable rendering of a decoded observation.
/// Params: m - the decoded observation.
/// Returns: "<station> <dir>/<kt>kt vis=<vis>m <temp>/<dew> Q<hpa> <category>"
/// where a missing direction/speed renders as "///" (VRB when only the
/// direction is variable), a missing visibility renders as "///" (including
/// the "m" suffix), temp/dew render as signed integers with -1 as "///", a
/// missing altimeter renders as "Q///", and the category always appears.
/// Example: "EGLL 240/12kt vis=9999m 18/12 Q1013 VFR"; with only a station
/// and wind: "EGLL 240/12kt vis=/// ////// Q/// VFR".
/// Complexity: O(1).
pub fn metar_summary(m: &Metar) -> Str {
  return m.station + " " + _wind_text(m) + " vis=" + _visibility_text(m.visibility_m) + " " + _temperature_text(m.temp_c) + "/" + _temperature_text(m.dewpoint_c) + " " + _altimeter_text(m.altimeter_hpa) + " " + metar_flight_category(m);
}
