// XIOM -- xiom.tcx: Garmin TCX subset codec (parse and canonical build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Supported subset (SPEC.md has the grammar, semantics and error catalog):
// an optional <?xml ...?> declaration, a <TrainingCenterDatabase> root with
// one <Activities>, <Activity Sport="..."> entries, each with one <Id> and
// one or more <Lap StartTime="..."> records holding TotalTimeSeconds,
// DistanceMeters, MaximumSpeed, Calories and AverageHeartRateBpm/Value, plus
// an optional <Track> of <Trackpoint> entries with Time, optional
// Position/LatitudeDegrees/LongitudeDegrees, AltitudeMeters, DistanceMeters,
// HeartRateBpm/Value, Cadence and SensorState. Attribute values must be
// quoted and are entity-decoded (the five predefined entities plus validated
// numeric &#NN; / &#xHH; references).
//
// Numeric values are kept as validated text tokens (never Float64 and never
// Vec[Float64]): TotalTimeSeconds, DistanceMeters, MaximumSpeed,
// AltitudeMeters and latitude/longitude are validated decimal literals;
// Calories, Cadence and the heart-rate Value are unsigned decimal integers;
// SensorState is "Present" or "Absent". No unit conversion and no GPS math.
//
// Non-goals: courses, workouts, extensions, Biking/other activity payload
// elements, creator/author blocks, schemas, namespaces semantics, comments,
// CDATA, DTD and file I/O.
//
// v0.61.3 notes that shaped this module (same idioms as xiom.gpx):
//   * The document is flat: parallel Vec fields and per-record ranges, no
//     Vec[StructType].
//   * Ok/Err for Result[TcxDoc, Str] are constructed only in the leaf
//     helpers _ok_doc/_err_doc.
//   * Str equality always goes through xiom.string.compare.str_compare
//     (BUG 17: `==` on Str values read from Vec[Str] elements lowers to a
//     pointer comparison) and Vec element reads bind typed locals first.
//   * No FFI: text output is collected with Vec[UInt8].push and materialized
//     with xiom.string.builder.sb_to_str exactly once per document.

module xiom.tcx

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Element kinds
// --------------------------------------------------

// Structural kinds: 0 TrainingCenterDatabase, 1 Activities, 2 Activity,
// 4 Lap, 9 AverageHeartRateBpm, 11 Track, 12 Trackpoint, 14 Position,
// 18 HeartRateBpm.
// Leaf kinds: 3 Id, 5 TotalTimeSeconds, 6 DistanceMeters, 7 MaximumSpeed,
// 8 Calories, 10 Value, 13 Time, 15 LatitudeDegrees, 16 LongitudeDegrees,
// 17 AltitudeMeters, 19 Cadence, 20 SensorState.
// DistanceMeters (6) and Value (10) are shared by two parents; the parser
// disambiguates them with the parent kind.

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _T_LT: UInt8 = 60u8;
const _T_GT: UInt8 = 62u8;
const _T_SLASH: UInt8 = 47u8;
const _T_EQ: UInt8 = 61u8;
const _T_BANG: UInt8 = 33u8;
const _T_QUEST: UInt8 = 63u8;
const _T_DQUOTE: UInt8 = 34u8;
const _T_SQUOTE: UInt8 = 39u8;
const _T_HASH: UInt8 = 35u8;
const _T_AMP: UInt8 = 38u8;
const _T_SEMI: UInt8 = 59u8;
const _T_SPACE: UInt8 = 32u8;
const _T_TAB: UInt8 = 9u8;
const _T_CR: UInt8 = 13u8;
const _T_LF: UInt8 = 10u8;
const _T_DOT: UInt8 = 46u8;
const _T_PLUS: UInt8 = 43u8;
const _T_MINUS: UInt8 = 45u8;
const _T_LOWER_X: UInt8 = 120u8;
const _T_UPPER_X: UInt8 = 88u8;

// --------------------------------------------------
//  Leaf storage targets
// --------------------------------------------------

// Which record vector a leaf element writes to. The target is computed when
// the leaf opens (parent kind + leaf kind) and carried on the open stack, so
// DistanceMeters and Value can be disambiguated without rescanning.
const _T_ID: Int = 0;
const _T_LAP_TOTAL: Int = 1;
const _T_LAP_DIST: Int = 2;
const _T_TP_DIST: Int = 3;
const _T_LAP_MAXSPEED: Int = 4;
const _T_LAP_CAL: Int = 5;
const _T_LAP_HR: Int = 6;
const _T_TP_HR: Int = 7;
const _T_TP_TIME: Int = 8;
const _T_TP_LAT: Int = 9;
const _T_TP_LON: Int = 10;
const _T_TP_ALT: Int = 11;
const _T_TP_CAD: Int = 12;
const _T_TP_SENSOR: Int = 13;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// Parsed or hand-built TCX document: a flat model of parallel vectors with
/// per-record ranges. Activities are indexed 0..act_sport.len(); activity a
/// owns the laps in [act_lap_start[a], _lap_end); every lap record carries
/// its own [lap_tp_start[l], _tp_end) trackpoint range. All text fields are
/// entity-decoded, whitespace-trimmed tokens: sport and id are free text;
/// lap_total_time/lap_distance/lap_max_speed/lap_calories/lap_avg_hr are the
/// validated scalar tokens; tp_time is free text; tp_lat/tp_lon/tp_alt/
/// tp_distance/tp_hr/tp_cadence/tp_sensor are optional ("" when the element
/// was absent). Read everything through the accessors below so that
/// out-of-range indices stay safe. Vec[StructType] is not usable in this
/// compiler, hence the flat layout.
pub type TcxDoc = {
  act_sport: Vec[Str];
  act_id: Vec[Str];
  act_lap_start: Vec[Int];
  lap_start_time: Vec[Str];
  lap_total_time: Vec[Str];
  lap_distance: Vec[Str];
  lap_max_speed: Vec[Str];
  lap_calories: Vec[Str];
  lap_avg_hr: Vec[Str];
  lap_tp_start: Vec[Int];
  tp_time: Vec[Str];
  tp_lat: Vec[Str];
  tp_lon: Vec[Str];
  tp_alt: Vec[Str];
  tp_distance: Vec[Str];
  tp_hr: Vec[Str];
  tp_cadence: Vec[Str];
  tp_sensor: Vec[Str];
}

/// An empty document (no activities). tcx_build emits the canonical skeleton
/// with a self-closed <Activities/>; parsing it back is not part of the
/// round-trip contract (the subset requires at least one Activity).
pub fn tcx_new() -> TcxDoc {
  return TcxDoc{
    act_sport: Vec[Str].new(); act_id: Vec[Str].new();
    act_lap_start: Vec[Int].new();
    lap_start_time: Vec[Str].new(); lap_total_time: Vec[Str].new();
    lap_distance: Vec[Str].new(); lap_max_speed: Vec[Str].new();
    lap_calories: Vec[Str].new(); lap_avg_hr: Vec[Str].new();
    lap_tp_start: Vec[Int].new();
    tp_time: Vec[Str].new(); tp_lat: Vec[Str].new(); tp_lon: Vec[Str].new();
    tp_alt: Vec[Str].new(); tp_distance: Vec[Str].new(); tp_hr: Vec[Str].new();
    tp_cadence: Vec[Str].new(); tp_sensor: Vec[Str].new();
  };
}

// Mutable parse state. text/pos are the input cursor; the act/lap/tp vectors
// accumulate the flat document; open_names/open_kinds/open_recs/open_targets
// are the parallel open-element stacks (open_recs carries the owning record
// index, open_targets the leaf storage target or -1 for structural elements);
// leaf_start/leaf_end delimit the raw span of the current leaf's single text
// run (-1 when none was seen). activities_activity_start and track_tp_start
// remember the record counts when <Activities> / <Track> opened so their
// "at least one child" rules can be checked at close time.
type _TcxParser = {
  text: Str;
  pos: Int;
  act_sport: Vec[Str];
  act_id: Vec[Str];
  act_lap_start: Vec[Int];
  lap_start_time: Vec[Str];
  lap_total_time: Vec[Str];
  lap_distance: Vec[Str];
  lap_max_speed: Vec[Str];
  lap_calories: Vec[Str];
  lap_avg_hr: Vec[Str];
  lap_tp_start: Vec[Int];
  tp_time: Vec[Str];
  tp_lat: Vec[Str];
  tp_lon: Vec[Str];
  tp_alt: Vec[Str];
  tp_distance: Vec[Str];
  tp_hr: Vec[Str];
  tp_cadence: Vec[Str];
  tp_sensor: Vec[Str];
  open_names: Vec[Str];
  open_kinds: Vec[Int];
  open_recs: Vec[Int];
  open_targets: Vec[Int];
  have_root: Bool;
  have_activities: Bool;
  activities_activity_start: Int;
  track_tp_start: Int;
  cur_kind: Int;
  cur_sport: Str;
  have_sport: Bool;
  cur_start: Str;
  have_start: Bool;
  self_close: Bool;
  leaf_start: Int;
  leaf_end: Int;
  failed: Bool;
  error: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[TcxDoc, Str].
fn _ok_doc(d: TcxDoc) -> Result[TcxDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[TcxDoc, Str].
fn _err_doc(m: Str) -> Result[TcxDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and string predicates
// --------------------------------------------------

fn _is_ws(b: UInt8) -> Bool {
  if b == _T_SPACE { return true; }
  if b == _T_TAB { return true; }
  if b == _T_CR { return true; }
  if b == _T_LF { return true; }
  return false;
}

// Byte that terminates a tag or attribute name: whitespace, '<', '>', '/' or
// '='.
fn _is_name_end(b: UInt8) -> Bool {
  if _is_ws(b) { return true; }
  if b == _T_LT { return true; }
  if b == _T_GT { return true; }
  if b == _T_SLASH { return true; }
  if b == _T_EQ { return true; }
  return false;
}

// True when every byte of s[start, end) is XML whitespace.
fn _raw_all_ws(s: Str, start: Int, end: Int) -> Bool {
  var i = start;
  while i < end {
    let b: UInt8 = string.byte_at(s, i);
    if !_is_ws(b) { return false; }
    i = i + 1;
  }
  return true;
}

// True when the Str equals "" (str_compare, never `==`, because the value
// may come from a Vec[Str] element).
fn _str_empty(s: Str) -> Bool {
  return compare.str_compare(s, "") == 0;
}

// Decimal token: optional '+'/'-', at least one digit, optional '.'-fraction
// with at least one digit; no exponent, no embedded whitespace.
fn _is_dec(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  var i = 0;
  let b0: UInt8 = string.byte_at(s, 0);
  if b0 == _T_MINUS || b0 == _T_PLUS { i = 1; }
  let ds = i;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if b < 48 || b > 57 { break; }
    i = i + 1;
  }
  if i == ds { return false; }
  if i < n {
    if string.byte_at(s, i) != _T_DOT { return false; }
    i = i + 1;
    let fs = i;
    while i < n {
      let b2: UInt8 = string.byte_at(s, i);
      if b2 < 48 || b2 > 57 { break; }
      i = i + 1;
    }
    if i == fs { return false; }
  }
  return i == n;
}

// Unsigned decimal integer token: one or more ASCII digits.
fn _is_uint(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if b < 48 || b > 57 { return false; }
    i = i + 1;
  }
  return true;
}

// SensorState token: exactly "Present" or "Absent".
fn _is_sensor(s: Str) -> Bool {
  if compare.str_compare(s, "Present") == 0 { return true; }
  if compare.str_compare(s, "Absent") == 0 { return true; }
  return false;
}

// Strip leading and trailing XML whitespace from a freshly decoded Str.
fn _trim(s: Str) -> Str {
  let n = s.len();
  var a = 0;
  while a < n {
    let b: UInt8 = string.byte_at(s, a);
    if !_is_ws(b) { break; }
    a = a + 1;
  }
  var e = n;
  while e > a {
    let b2: UInt8 = string.byte_at(s, e - 1);
    if !_is_ws(b2) { break; }
    e = e - 1;
  }
  if a == 0 && e == n { return s; }
  return string.str_slice(s, a, e);
}

// --------------------------------------------------
//  Names and placement
// --------------------------------------------------

// Element name of a kind ("" for an unknown kind).
fn _kind_name(k: Int) -> Str {
  if k == 0 { return "TrainingCenterDatabase"; }
  if k == 1 { return "Activities"; }
  if k == 2 { return "Activity"; }
  if k == 3 { return "Id"; }
  if k == 4 { return "Lap"; }
  if k == 5 { return "TotalTimeSeconds"; }
  if k == 6 { return "DistanceMeters"; }
  if k == 7 { return "MaximumSpeed"; }
  if k == 8 { return "Calories"; }
  if k == 9 { return "AverageHeartRateBpm"; }
  if k == 10 { return "Value"; }
  if k == 11 { return "Track"; }
  if k == 12 { return "Trackpoint"; }
  if k == 13 { return "Time"; }
  if k == 14 { return "Position"; }
  if k == 15 { return "LatitudeDegrees"; }
  if k == 16 { return "LongitudeDegrees"; }
  if k == 17 { return "AltitudeMeters"; }
  if k == 18 { return "HeartRateBpm"; }
  if k == 19 { return "Cadence"; }
  if k == 20 { return "SensorState"; }
  return "";
}

// Kind of an element name (case-sensitive), -1 when outside the subset.
fn _element_kind(name: Str) -> Int {
  if compare.str_compare(name, "TrainingCenterDatabase") == 0 { return 0; }
  if compare.str_compare(name, "Activities") == 0 { return 1; }
  if compare.str_compare(name, "Activity") == 0 { return 2; }
  if compare.str_compare(name, "Id") == 0 { return 3; }
  if compare.str_compare(name, "Lap") == 0 { return 4; }
  if compare.str_compare(name, "TotalTimeSeconds") == 0 { return 5; }
  if compare.str_compare(name, "DistanceMeters") == 0 { return 6; }
  if compare.str_compare(name, "MaximumSpeed") == 0 { return 7; }
  if compare.str_compare(name, "Calories") == 0 { return 8; }
  if compare.str_compare(name, "AverageHeartRateBpm") == 0 { return 9; }
  if compare.str_compare(name, "Value") == 0 { return 10; }
  if compare.str_compare(name, "Track") == 0 { return 11; }
  if compare.str_compare(name, "Trackpoint") == 0 { return 12; }
  if compare.str_compare(name, "Time") == 0 { return 13; }
  if compare.str_compare(name, "Position") == 0 { return 14; }
  if compare.str_compare(name, "LatitudeDegrees") == 0 { return 15; }
  if compare.str_compare(name, "LongitudeDegrees") == 0 { return 16; }
  if compare.str_compare(name, "AltitudeMeters") == 0 { return 17; }
  if compare.str_compare(name, "HeartRateBpm") == 0 { return 18; }
  if compare.str_compare(name, "Cadence") == 0 { return 19; }
  if compare.str_compare(name, "SensorState") == 0 { return 20; }
  return -1;
}

// Leaf kinds hold text only and can never contain elements.
fn _is_leaf_kind(k: Int) -> Bool {
  if k == 3 { return true; }
  if k == 5 { return true; }
  if k == 6 { return true; }
  if k == 7 { return true; }
  if k == 8 { return true; }
  if k == 10 { return true; }
  if k == 13 { return true; }
  if k == 15 { return true; }
  if k == 16 { return true; }
  if k == 17 { return true; }
  if k == 19 { return true; }
  if k == 20 { return true; }
  return false;
}

// Structural placement rule: which child kinds are allowed inside which open
// element kind.
fn _placement_ok(parent_kind: Int, child_kind: Int) -> Bool {
  if parent_kind == 0 { return child_kind == 1; }
  if parent_kind == 1 { return child_kind == 2; }
  if parent_kind == 2 {
    if child_kind == 3 { return true; }
    return child_kind == 4;
  }
  if parent_kind == 4 {
    if child_kind == 5 { return true; }
    if child_kind == 6 { return true; }
    if child_kind == 7 { return true; }
    if child_kind == 8 { return true; }
    if child_kind == 9 { return true; }
    return child_kind == 11;
  }
  if parent_kind == 9 { return child_kind == 10; }
  if parent_kind == 11 { return child_kind == 12; }
  if parent_kind == 12 {
    if child_kind == 13 { return true; }
    if child_kind == 14 { return true; }
    if child_kind == 6 { return true; }
    if child_kind == 17 { return true; }
    if child_kind == 18 { return true; }
    if child_kind == 19 { return true; }
    return child_kind == 20;
  }
  if parent_kind == 14 {
    if child_kind == 15 { return true; }
    return child_kind == 16;
  }
  if parent_kind == 18 { return child_kind == 10; }
  return false;
}

// Storage target of a leaf kind under its parent, or -1 when the pair is not
// in the subset (defensive: _placement_ok already rejects such pairs).
fn _leaf_target(parent_kind: Int, leaf_kind: Int) -> Int {
  if leaf_kind == 3 { return _T_ID; }
  if leaf_kind == 13 { return _T_TP_TIME; }
  if leaf_kind == 5 { return _T_LAP_TOTAL; }
  if leaf_kind == 7 { return _T_LAP_MAXSPEED; }
  if leaf_kind == 8 { return _T_LAP_CAL; }
  if leaf_kind == 6 {
    if parent_kind == 4 { return _T_LAP_DIST; }
    if parent_kind == 12 { return _T_TP_DIST; }
    return -1;
  }
  if leaf_kind == 10 {
    if parent_kind == 9 { return _T_LAP_HR; }
    if parent_kind == 18 { return _T_TP_HR; }
    return -1;
  }
  if leaf_kind == 15 { return _T_TP_LAT; }
  if leaf_kind == 16 { return _T_TP_LON; }
  if leaf_kind == 17 { return _T_TP_ALT; }
  if leaf_kind == 19 { return _T_TP_CAD; }
  if leaf_kind == 20 { return _T_TP_SENSOR; }
  return -1;
}

// --------------------------------------------------
//  Entity decoding
// --------------------------------------------------

// Append the UTF-8 encoding of codepoint `code` (1..0x10FFFF) to out.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code <= 127 {
    out.push(code as UInt8);
    return;
  }
  if code <= 2047 {
    out.push((192 + code / 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  if code <= 65535 {
    out.push((224 + code / 4096) as UInt8);
    out.push((128 + (code / 64) % 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  out.push((240 + code / 262144) as UInt8);
  out.push((128 + (code / 4096) % 64) as UInt8);
  out.push((128 + (code / 64) % 64) as UInt8);
  out.push((128 + code % 64) as UInt8);
}

// Codepoint of a "#NN" or "#xHH" numeric reference body, or -1 when the body
// is malformed, zero, a surrogate or beyond U+10FFFF.
fn _entity_code(body: Str) -> Int {
  let n = body.len();
  if n < 2 { return -1; }
  if string.byte_at(body, 0) != _T_HASH { return -1; }
  var i = 1;
  var base = 10;
  let mark: UInt8 = string.byte_at(body, i);
  if mark == _T_LOWER_X || mark == _T_UPPER_X {
    base = 16;
    i = i + 1;
  }
  if i >= n { return -1; }
  var v = 0;
  while i < n {
    let b: Int = (string.byte_at(body, i) as Int) & 0xFF;
    var d = -1;
    if b >= 48 && b <= 57 {
      d = b - 48;
    } elif base == 16 && b >= 97 && b <= 102 {
      d = b - 87;
    } elif base == 16 && b >= 65 && b <= 70 {
      d = b - 55;
    } else {
      return -1;
    }
    if d >= base { return -1; }
    v = v * base + d;
    if v > 1114111 { return -1; }
    i = i + 1;
  }
  if v == 0 { return -1; }
  if v >= 55296 && v <= 57343 { return -1; }
  return v;
}

// Decode the entity starting at s[at] (which is '&') into out. Returns the
// number of consumed input bytes, or -1 when the reference is malformed,
// unknown or unterminated.
fn _entity_decode(s: Str, at: Int, end: Int, out: &mut Vec[UInt8]) -> Int {
  var semi = -1;
  var j = at + 1;
  while j < end {
    let b: UInt8 = string.byte_at(s, j);
    if b == _T_SEMI {
      semi = j;
      break;
    }
    if b == _T_AMP { break; }
    j = j + 1;
  }
  if semi < 0 { return -1; }
  let body = string.str_slice(s, at + 1, semi);
  if compare.str_compare(body, "amp") == 0 {
    out.push(_T_AMP);
    return semi - at + 1;
  }
  if compare.str_compare(body, "lt") == 0 {
    out.push(_T_LT);
    return semi - at + 1;
  }
  if compare.str_compare(body, "gt") == 0 {
    out.push(_T_GT);
    return semi - at + 1;
  }
  if compare.str_compare(body, "quot") == 0 {
    out.push(_T_DQUOTE);
    return semi - at + 1;
  }
  if compare.str_compare(body, "apos") == 0 {
    out.push(_T_SQUOTE);
    return semi - at + 1;
  }
  let code = _entity_code(body);
  if code < 0 { return -1; }
  _push_utf8(out, code);
  return semi - at + 1;
}

// Deterministic error for the entity at s[at] (the same scan as
// _entity_decode, used only on failure).
fn _entity_error(s: Str, at: Int, end: Int) -> Str {
  var semi = -1;
  var j = at + 1;
  while j < end {
    let b: UInt8 = string.byte_at(s, j);
    if b == _T_SEMI {
      semi = j;
      break;
    }
    if b == _T_AMP { break; }
    j = j + 1;
  }
  if semi < 0 { return "tcx: unterminated entity"; }
  let body = string.str_slice(s, at + 1, semi);
  return "tcx: bad entity: &" + body + ";";
}

// Entity-decode s[start, end) into a fresh Str. Err("tcx: ...") on the first
// malformed or unterminated reference.
fn _decode_range(s: Str, start: Int, end: Int) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    let b: UInt8 = string.byte_at(s, i);
    if b == _T_AMP {
      let adv = _entity_decode(s, i, end, &mut out);
      if adv < 0 { return Err(_entity_error(s, i, end)); }
      i = i + adv;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return Ok(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Parser helpers
// --------------------------------------------------

fn _fail(p: &mut _TcxParser, m: Str) -> Bool {
  p.failed = true;
  p.error = m;
  return false;
}

fn _byte(p: &mut _TcxParser, i: Int) -> UInt8 {
  return string.byte_at(p.text, i);
}

fn _skip_ws(p: &mut _TcxParser) {
  let n = p.text.len();
  while p.pos < n {
    if !_is_ws(_byte(p, p.pos)) { break; }
    p.pos = p.pos + 1;
  }
}

// Number of trackpoints currently owned by lap l (live parser state).
fn _lap_tp_count(p: &_TcxParser, l: Int) -> Int {
  if l < 0 || l >= p.lap_tp_start.len() { return 0; }
  let s: Int = p.lap_tp_start[l];
  var e = p.tp_time.len();
  if l + 1 < p.lap_tp_start.len() {
    let n2: Int = p.lap_tp_start[l + 1];
    if n2 < e { e = n2; }
  }
  if e <= s { return 0; }
  return e - s;
}

// True when the parent record already owns a child of this kind. The parent
// record index plus the parent kind uniquely identify the parent node; a
// single-instance child stores a non-empty marker (or, for Track, at least
// one trackpoint) once it has been completed successfully.
fn _child_seen(p: &_TcxParser, parent_kind: Int, rec: Int, kind: Int) -> Bool {
  if kind == 1 { return p.have_activities; }
  if kind == 3 {
    if rec < 0 || rec >= p.act_id.len() { return false; }
    let v: Str = p.act_id[rec];
    return !_str_empty(v);
  }
  if kind == 5 {
    if rec < 0 || rec >= p.lap_total_time.len() { return false; }
    let v2: Str = p.lap_total_time[rec];
    return !_str_empty(v2);
  }
  if kind == 6 {
    if parent_kind == 4 {
      if rec < 0 || rec >= p.lap_distance.len() { return false; }
      let v3: Str = p.lap_distance[rec];
      return !_str_empty(v3);
    }
    if rec < 0 || rec >= p.tp_distance.len() { return false; }
    let v4: Str = p.tp_distance[rec];
    return !_str_empty(v4);
  }
  if kind == 7 {
    if rec < 0 || rec >= p.lap_max_speed.len() { return false; }
    let v5: Str = p.lap_max_speed[rec];
    return !_str_empty(v5);
  }
  if kind == 8 {
    if rec < 0 || rec >= p.lap_calories.len() { return false; }
    let v6: Str = p.lap_calories[rec];
    return !_str_empty(v6);
  }
  if kind == 9 {
    if rec < 0 || rec >= p.lap_avg_hr.len() { return false; }
    let v7: Str = p.lap_avg_hr[rec];
    return !_str_empty(v7);
  }
  if kind == 10 {
    if parent_kind == 9 {
      if rec < 0 || rec >= p.lap_avg_hr.len() { return false; }
      let v8: Str = p.lap_avg_hr[rec];
      return !_str_empty(v8);
    }
    if rec < 0 || rec >= p.tp_hr.len() { return false; }
    let v9: Str = p.tp_hr[rec];
    return !_str_empty(v9);
  }
  if kind == 11 { return _lap_tp_count(p, rec) > 0; }
  if kind == 13 {
    if rec < 0 || rec >= p.tp_time.len() { return false; }
    let v10: Str = p.tp_time[rec];
    return !_str_empty(v10);
  }
  if kind == 14 {
    if rec < 0 || rec >= p.tp_lat.len() { return false; }
    let v11: Str = p.tp_lat[rec];
    return !_str_empty(v11);
  }
  if kind == 15 {
    if rec < 0 || rec >= p.tp_lat.len() { return false; }
    let v12: Str = p.tp_lat[rec];
    return !_str_empty(v12);
  }
  if kind == 16 {
    if rec < 0 || rec >= p.tp_lon.len() { return false; }
    let v13: Str = p.tp_lon[rec];
    return !_str_empty(v13);
  }
  if kind == 17 {
    if rec < 0 || rec >= p.tp_alt.len() { return false; }
    let v14: Str = p.tp_alt[rec];
    return !_str_empty(v14);
  }
  if kind == 18 {
    if rec < 0 || rec >= p.tp_hr.len() { return false; }
    let v15: Str = p.tp_hr[rec];
    return !_str_empty(v15);
  }
  if kind == 19 {
    if rec < 0 || rec >= p.tp_cadence.len() { return false; }
    let v16: Str = p.tp_cadence[rec];
    return !_str_empty(v16);
  }
  if kind == 20 {
    if rec < 0 || rec >= p.tp_sensor.len() { return false; }
    let v17: Str = p.tp_sensor[rec];
    return !_str_empty(v17);
  }
  return false;
}

// Required-children check for a structural element that just ended (closing
// tag or self-close). Messages name the missing child.
fn _check_children(p: &mut _TcxParser, kind: Int, rec: Int) -> Bool {
  if kind == 0 {
    if !p.have_activities { return _fail(p, "tcx: missing required element: Activities"); }
    return true;
  }
  if kind == 1 {
    if p.act_sport.len() <= p.activities_activity_start {
      return _fail(p, "tcx: missing required element: Activity");
    }
    return true;
  }
  if kind == 2 {
    if rec < 0 || rec >= p.act_id.len() {
      return _fail(p, "tcx: missing required element: Id");
    }
    let idv: Str = p.act_id[rec];
    if _str_empty(idv) { return _fail(p, "tcx: missing required element: Id"); }
    if rec >= p.act_lap_start.len() {
      return _fail(p, "tcx: missing required element: Lap");
    }
    let ls: Int = p.act_lap_start[rec];
    if p.lap_start_time.len() <= ls {
      return _fail(p, "tcx: missing required element: Lap");
    }
    return true;
  }
  if kind == 4 {
    if rec < 0 || rec >= p.lap_total_time.len() {
      return _fail(p, "tcx: missing required element: TotalTimeSeconds");
    }
    let tt: Str = p.lap_total_time[rec];
    if _str_empty(tt) { return _fail(p, "tcx: missing required element: TotalTimeSeconds"); }
    let dd: Str = p.lap_distance[rec];
    if _str_empty(dd) { return _fail(p, "tcx: missing required element: DistanceMeters"); }
    let cc: Str = p.lap_calories[rec];
    if _str_empty(cc) { return _fail(p, "tcx: missing required element: Calories"); }
    return true;
  }
  if kind == 9 {
    if rec < 0 || rec >= p.lap_avg_hr.len() {
      return _fail(p, "tcx: missing required element: Value");
    }
    let hv: Str = p.lap_avg_hr[rec];
    if _str_empty(hv) { return _fail(p, "tcx: missing required element: Value"); }
    return true;
  }
  if kind == 11 {
    if _lap_tp_count(p, rec) == 0 {
      return _fail(p, "tcx: missing required element: Trackpoint");
    }
    return true;
  }
  if kind == 12 {
    if rec < 0 || rec >= p.tp_time.len() {
      return _fail(p, "tcx: missing required element: Time");
    }
    let tv: Str = p.tp_time[rec];
    if _str_empty(tv) { return _fail(p, "tcx: missing required element: Time"); }
    return true;
  }
  if kind == 14 {
    if rec < 0 || rec >= p.tp_lat.len() {
      return _fail(p, "tcx: missing required element: LatitudeDegrees");
    }
    let la: Str = p.tp_lat[rec];
    if _str_empty(la) { return _fail(p, "tcx: missing required element: LatitudeDegrees"); }
    let lo: Str = p.tp_lon[rec];
    if _str_empty(lo) { return _fail(p, "tcx: missing required element: LongitudeDegrees"); }
    return true;
  }
  if kind == 18 {
    if rec < 0 || rec >= p.tp_hr.len() {
      return _fail(p, "tcx: missing required element: Value");
    }
    let thv: Str = p.tp_hr[rec];
    if _str_empty(thv) { return _fail(p, "tcx: missing required element: Value"); }
    return true;
  }
  return true;
}

// Skip a leading <?xml ...?> declaration when present; nothing else may
// precede the root element.
fn _skip_declaration(p: &mut _TcxParser) -> Bool {
  _skip_ws(p);
  let n = p.text.len();
  if p.pos + 1 >= n { return true; }
  if _byte(p, p.pos) != _T_LT { return true; }
  if _byte(p, p.pos + 1) != _T_QUEST { return true; }
  if p.pos + 5 > n { return _fail(p, "tcx: malformed declaration"); }
  if _byte(p, p.pos + 2) != _T_LOWER_X { return _fail(p, "tcx: malformed declaration"); }
  if _byte(p, p.pos + 3) != 109u8 { return _fail(p, "tcx: malformed declaration"); }
  if _byte(p, p.pos + 4) != 108u8 { return _fail(p, "tcx: malformed declaration"); }
  if p.pos + 5 < n {
    let after: UInt8 = _byte(p, p.pos + 5);
    if !_is_ws(after) && after != _T_QUEST {
      return _fail(p, "tcx: malformed declaration");
    }
  }
  var i = p.pos + 5;
  while i + 1 < n {
    if _byte(p, i) == _T_QUEST {
      if _byte(p, i + 1) == _T_GT {
        p.pos = i + 2;
        return true;
      }
    }
    i = i + 1;
  }
  return _fail(p, "tcx: malformed declaration");
}

// Parse attributes after an element name. Values must be quoted and are
// entity-decoded and trimmed; Sport (Activity) and StartTime (Lap) are
// stored, duplicates of those two are rejected, and every other attribute
// (namespace declarations included) is accepted and ignored.
fn _parse_attrs(p: &mut _TcxParser) -> Bool {
  let n = p.text.len();
  loop {
    _skip_ws(p);
    if p.pos >= n { return _fail(p, "tcx: premature end of input"); }
    let b: UInt8 = _byte(p, p.pos);
    if b == _T_GT {
      p.pos = p.pos + 1;
      return true;
    }
    if b == _T_SLASH {
      p.pos = p.pos + 1;
      _skip_ws(p);
      if p.pos >= n { return _fail(p, "tcx: premature end of input"); }
      if _byte(p, p.pos) != _T_GT { return _fail(p, "tcx: malformed tag"); }
      p.pos = p.pos + 1;
      p.self_close = true;
      return true;
    }
    let an_start = p.pos;
    while p.pos < n {
      if _is_name_end(_byte(p, p.pos)) { break; }
      p.pos = p.pos + 1;
    }
    if p.pos == an_start { return _fail(p, "tcx: malformed attribute"); }
    let aname = string.str_slice(p.text, an_start, p.pos);
    _skip_ws(p);
    if p.pos >= n { return _fail(p, "tcx: premature end of input"); }
    if _byte(p, p.pos) != _T_EQ { return _fail(p, "tcx: malformed attribute"); }
    p.pos = p.pos + 1;
    _skip_ws(p);
    if p.pos >= n { return _fail(p, "tcx: premature end of input"); }
    let q: UInt8 = _byte(p, p.pos);
    if q != _T_DQUOTE && q != _T_SQUOTE {
      return _fail(p, "tcx: unquoted attribute value: " + aname);
    }
    p.pos = p.pos + 1;
    let v_start = p.pos;
    var bad_lt = false;
    while p.pos < n {
      let vb: UInt8 = _byte(p, p.pos);
      if vb == q { break; }
      if vb == _T_LT {
        bad_lt = true;
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos >= n { return _fail(p, "tcx: premature end of input"); }
    if bad_lt { return _fail(p, "tcx: malformed attribute"); }
    let raw = string.str_slice(p.text, v_start, p.pos);
    p.pos = p.pos + 1;
    let dr = _decode_range(raw, 0, raw.len());
    var value = "";
    match dr {
      Ok(v) => { value = v; },
      Err(e) => { return _fail(p, e); },
    }
    let trimmed = _trim(value);
    if p.cur_kind == 2 {
      if compare.str_compare(aname, "Sport") == 0 {
        if p.have_sport { return _fail(p, "tcx: duplicate attribute: Sport"); }
        p.have_sport = true;
        p.cur_sport = trimmed;
      }
    } elif p.cur_kind == 4 {
      if compare.str_compare(aname, "StartTime") == 0 {
        if p.have_start { return _fail(p, "tcx: duplicate attribute: StartTime"); }
        p.have_start = true;
        p.cur_start = trimmed;
      }
    }
  }
  return true;
}

// Consume a start tag (p.pos at the first name byte), validate placement,
// create the record (or compute the leaf storage target) and push the open
// stack unless the tag is self-closing.
fn _start_tag(p: &mut _TcxParser) -> Bool {
  let n = p.text.len();
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_byte(p, p.pos)) { break; }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start { return _fail(p, "tcx: malformed tag"); }
  let name = string.str_slice(p.text, name_start, p.pos);
  let kind = _element_kind(name);
  if kind < 0 { return _fail(p, "tcx: unknown element: <" + name + ">"); }
  var parent_kind = -1;
  var parent_rec = -1;
  if p.open_kinds.len() == 0 {
    if p.have_root { return _fail(p, "tcx: multiple root elements"); }
    if kind != 0 { return _fail(p, "tcx: wrong root element: <" + name + ">"); }
  } else {
    parent_kind = p.open_kinds[p.open_kinds.len() - 1];
    parent_rec = p.open_recs[p.open_recs.len() - 1];
    if !_placement_ok(parent_kind, kind) {
      return _fail(p, "tcx: element not allowed here: <" + name + ">");
    }
    if _child_seen(p, parent_kind, parent_rec, kind) {
      return _fail(p, "tcx: duplicate element: <" + name + ">");
    }
  }
  p.cur_kind = kind;
  p.cur_sport = "";
  p.have_sport = false;
  p.cur_start = "";
  p.have_start = false;
  p.self_close = false;
  if !_parse_attrs(p) { return false; }
  if kind == 2 {
    if !p.have_sport { return _fail(p, "tcx: missing required attribute: Sport"); }
    if _str_empty(p.cur_sport) { return _fail(p, "tcx: empty attribute: Sport"); }
  }
  if kind == 4 {
    if !p.have_start { return _fail(p, "tcx: missing required attribute: StartTime"); }
    if _str_empty(p.cur_start) { return _fail(p, "tcx: empty attribute: StartTime"); }
  }
  var rec = parent_rec;
  if kind == 1 {
    p.activities_activity_start = p.act_sport.len();
    rec = -1;
  } elif kind == 2 {
    rec = p.act_sport.len();
    p.act_sport.push(p.cur_sport);
    p.act_id.push("");
    p.act_lap_start.push(p.lap_start_time.len());
  } elif kind == 4 {
    rec = p.lap_start_time.len();
    p.lap_start_time.push(p.cur_start);
    p.lap_total_time.push("");
    p.lap_distance.push("");
    p.lap_max_speed.push("");
    p.lap_calories.push("");
    p.lap_avg_hr.push("");
    p.lap_tp_start.push(p.tp_time.len());
  } elif kind == 11 {
    p.track_tp_start = p.tp_time.len();
    rec = parent_rec;
  } elif kind == 12 {
    rec = p.tp_time.len();
    p.tp_time.push("");
    p.tp_lat.push("");
    p.tp_lon.push("");
    p.tp_alt.push("");
    p.tp_distance.push("");
    p.tp_hr.push("");
    p.tp_cadence.push("");
    p.tp_sensor.push("");
  }
  if kind == 0 { p.have_root = true; }
  if kind == 1 { p.have_activities = true; }
  var target = -1;
  if _is_leaf_kind(kind) {
    target = _leaf_target(parent_kind, kind);
    if target < 0 { return _fail(p, "tcx: element not allowed here: <" + name + ">"); }
    rec = parent_rec;
  }
  if p.self_close {
    if _is_leaf_kind(kind) { return _fail(p, "tcx: empty element: " + name); }
    return _check_children(p, kind, rec);
  }
  p.open_names.push(name);
  p.open_kinds.push(kind);
  p.open_recs.push(rec);
  p.open_targets.push(target);
  if _is_leaf_kind(kind) {
    p.leaf_start = -1;
    p.leaf_end = -1;
  }
  return true;
}

// Store a validated leaf token into its record vector.
fn _store_leaf(p: &mut _TcxParser, target: Int, rec: Int, text: Str) {
  if target == _T_ID {
    p.act_id[rec] = text;
    return;
  }
  if target == _T_LAP_TOTAL {
    p.lap_total_time[rec] = text;
    return;
  }
  if target == _T_LAP_DIST {
    p.lap_distance[rec] = text;
    return;
  }
  if target == _T_TP_DIST {
    p.tp_distance[rec] = text;
    return;
  }
  if target == _T_LAP_MAXSPEED {
    p.lap_max_speed[rec] = text;
    return;
  }
  if target == _T_LAP_CAL {
    p.lap_calories[rec] = text;
    return;
  }
  if target == _T_LAP_HR {
    p.lap_avg_hr[rec] = text;
    return;
  }
  if target == _T_TP_HR {
    p.tp_hr[rec] = text;
    return;
  }
  if target == _T_TP_TIME {
    p.tp_time[rec] = text;
    return;
  }
  if target == _T_TP_LAT {
    p.tp_lat[rec] = text;
    return;
  }
  if target == _T_TP_LON {
    p.tp_lon[rec] = text;
    return;
  }
  if target == _T_TP_ALT {
    p.tp_alt[rec] = text;
    return;
  }
  if target == _T_TP_CAD {
    p.tp_cadence[rec] = text;
    return;
  }
  if target == _T_TP_SENSOR {
    p.tp_sensor[rec] = text;
    return;
  }
}

// Consume a closing tag (p.pos at the first name byte after "</"), pop the
// open element, finalize a leaf's decoded text or check a structural
// element's required children.
fn _close_tag(p: &mut _TcxParser) -> Bool {
  let n = p.text.len();
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_byte(p, p.pos)) { break; }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start { return _fail(p, "tcx: malformed tag"); }
  let name = string.str_slice(p.text, name_start, p.pos);
  _skip_ws(p);
  if p.pos >= n { return _fail(p, "tcx: premature end of input"); }
  if _byte(p, p.pos) != _T_GT { return _fail(p, "tcx: malformed tag"); }
  p.pos = p.pos + 1;
  if p.open_names.len() == 0 {
    return _fail(p, "tcx: unexpected closing tag: </" + name + ">");
  }
  let top_name: Str = p.open_names[p.open_names.len() - 1];
  if compare.str_compare(top_name, name) != 0 {
    return _fail(p, "tcx: mismatched closing tag: expected </" + top_name + ">, found </" + name + ">");
  }
  let top_kind: Int = p.open_kinds[p.open_kinds.len() - 1];
  let top_rec: Int = p.open_recs[p.open_recs.len() - 1];
  let top_target: Int = p.open_targets[p.open_targets.len() - 1];
  p.open_names.pop();
  p.open_kinds.pop();
  p.open_recs.pop();
  p.open_targets.pop();
  if _is_leaf_kind(top_kind) {
    if p.leaf_start < 0 { return _fail(p, "tcx: empty element: " + top_name); }
    var raw = "";
    let dr = _decode_range(p.text, p.leaf_start, p.leaf_end);
    match dr {
      Ok(v) => { raw = v; },
      Err(e) => { return _fail(p, e); },
    }
    let text = _trim(raw);
    if _str_empty(text) { return _fail(p, "tcx: empty element: " + top_name); }
    var bad = false;
    if top_target == _T_TP_SENSOR {
      if !_is_sensor(text) { bad = true; }
    } elif top_target == _T_LAP_CAL || top_target == _T_LAP_HR || top_target == _T_TP_HR || top_target == _T_TP_CAD {
      if !_is_uint(text) { bad = true; }
    } elif top_target != _T_ID && top_target != _T_TP_TIME {
      if !_is_dec(text) { bad = true; }
    }
    if bad { return _fail(p, "tcx: malformed " + top_name + ": " + text); }
    _store_leaf(p, top_target, top_rec, text);
    return true;
  }
  return _check_children(p, top_kind, top_rec);
}

// Consume markup after '<'.
fn _consume_markup(p: &mut _TcxParser) -> Bool {
  let n = p.text.len();
  if p.pos >= n { return _fail(p, "tcx: premature end of input"); }
  let b: UInt8 = _byte(p, p.pos);
  if b == _T_SLASH {
    p.pos = p.pos + 1;
    return _close_tag(p);
  }
  if b == _T_QUEST || b == _T_BANG {
    return _fail(p, "tcx: unsupported markup");
  }
  return _start_tag(p);
}

// Consume character data up to the next '<' or EOF. Document-level text must
// be whitespace; container text must be whitespace; a leaf's single text run
// is remembered as a raw span and decoded when the leaf closes.
fn _consume_text(p: &mut _TcxParser) -> Bool {
  let n = p.text.len();
  let start = p.pos;
  var i = p.pos;
  while i < n {
    if _byte(p, i) == _T_LT { break; }
    i = i + 1;
  }
  p.pos = i;
  if p.open_kinds.len() == 0 {
    if _raw_all_ws(p.text, start, i) { return true; }
    return _fail(p, "tcx: text outside elements");
  }
  let top: Int = p.open_kinds[p.open_kinds.len() - 1];
  if _is_leaf_kind(top) {
    p.leaf_start = start;
    p.leaf_end = i;
    return true;
  }
  if _raw_all_ws(p.text, start, i) { return true; }
  return _fail(p, "tcx: unexpected text in <" + _kind_name(top) + ">");
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// Parse a TCX document in the supported subset.
/// Params: text - the whole document as one Str.
/// Returns: Ok(doc) with the flat activity/lap/trackpoint model.
/// Error case: Err("tcx: ...") on the first malformed construct; see SPEC.md
/// for the catalog (declaration, unknown/misplaced elements, missing required
/// elements or attributes, attribute quoting/duplication, malformed numeric
/// tokens, entities, mismatched closing tags, unexpected text, premature end
/// of input).
/// Complexity: O(input length).
pub fn tcx_parse(text: Str) -> Result[TcxDoc, Str] {
  var p = _TcxParser{
    text: text; pos: 0;
    act_sport: Vec[Str].new(); act_id: Vec[Str].new();
    act_lap_start: Vec[Int].new();
    lap_start_time: Vec[Str].new(); lap_total_time: Vec[Str].new();
    lap_distance: Vec[Str].new(); lap_max_speed: Vec[Str].new();
    lap_calories: Vec[Str].new(); lap_avg_hr: Vec[Str].new();
    lap_tp_start: Vec[Int].new();
    tp_time: Vec[Str].new(); tp_lat: Vec[Str].new(); tp_lon: Vec[Str].new();
    tp_alt: Vec[Str].new(); tp_distance: Vec[Str].new(); tp_hr: Vec[Str].new();
    tp_cadence: Vec[Str].new(); tp_sensor: Vec[Str].new();
    open_names: Vec[Str].new(); open_kinds: Vec[Int].new();
    open_recs: Vec[Int].new(); open_targets: Vec[Int].new();
    have_root: false; have_activities: false;
    activities_activity_start: 0; track_tp_start: 0;
    cur_kind: -1; cur_sport: ""; have_sport: false;
    cur_start: ""; have_start: false;
    self_close: false; leaf_start: -1; leaf_end: -1;
    failed: false; error: "";
  };
  if !_skip_declaration(&mut p) { return _err_doc(p.error); }
  let n = text.len();
  while p.pos < n {
    let b: UInt8 = _byte(&mut p, p.pos);
    if b == _T_LT {
      p.pos = p.pos + 1;
      if !_consume_markup(&mut p) { return _err_doc(p.error); }
    } else {
      if !_consume_text(&mut p) { return _err_doc(p.error); }
    }
  }
  if p.open_kinds.len() > 0 { return _err_doc("tcx: premature end of input"); }
  if !p.have_root { return _err_doc("tcx: premature end of input"); }
  return _ok_doc(TcxDoc{
    act_sport: p.act_sport; act_id: p.act_id;
    act_lap_start: p.act_lap_start;
    lap_start_time: p.lap_start_time; lap_total_time: p.lap_total_time;
    lap_distance: p.lap_distance; lap_max_speed: p.lap_max_speed;
    lap_calories: p.lap_calories; lap_avg_hr: p.lap_avg_hr;
    lap_tp_start: p.lap_tp_start;
    tp_time: p.tp_time; tp_lat: p.tp_lat; tp_lon: p.tp_lon;
    tp_alt: p.tp_alt; tp_distance: p.tp_distance; tp_hr: p.tp_hr;
    tp_cadence: p.tp_cadence; tp_sensor: p.tp_sensor;
  });
}

// --------------------------------------------------
//  Range helpers
// --------------------------------------------------

// First lap index of activity a, clamped to the lap vector (0 when a is out
// of range or the stored start is unusable).
fn _lap_start(d: &TcxDoc, a: Int) -> Int {
  if a < 0 || a >= d.act_lap_start.len() { return 0; }
  let s: Int = d.act_lap_start[a];
  let n = d.lap_start_time.len();
  if s < 0 { return 0; }
  if s > n { return n; }
  return s;
}

// Exclusive end lap index of activity a (one past its last lap).
fn _lap_end(d: &TcxDoc, a: Int) -> Int {
  let n = d.lap_start_time.len();
  if a < 0 { return 0; }
  if a + 1 < d.act_lap_start.len() {
    let e: Int = d.act_lap_start[a + 1];
    if e < 0 { return 0; }
    if e < n { return e; }
  }
  return n;
}

// First trackpoint index of lap l.
fn _tp_start(d: &TcxDoc, l: Int) -> Int {
  if l < 0 || l >= d.lap_tp_start.len() { return 0; }
  let s: Int = d.lap_tp_start[l];
  let n = d.tp_time.len();
  if s < 0 { return 0; }
  if s > n { return n; }
  return s;
}

// Exclusive end trackpoint index of lap l (one past its last trackpoint).
fn _tp_end(d: &TcxDoc, l: Int) -> Int {
  let n = d.tp_time.len();
  if l < 0 { return 0; }
  if l + 1 < d.lap_tp_start.len() {
    let e: Int = d.lap_tp_start[l + 1];
    if e < 0 { return 0; }
    if e < n { return e; }
  }
  return n;
}

// --------------------------------------------------
//  Document accessors
// --------------------------------------------------

/// Number of activities.
/// Params: d - the document.
/// Returns: d.act_sport.len() (0 for tcx_new).
/// Complexity: O(1).
pub fn tcx_activity_count(d: &TcxDoc) -> Int {
  return d.act_sport.len();
}

/// Total number of laps over every activity.
/// Params: d - the document.
/// Returns: d.lap_start_time.len().
/// Complexity: O(1).
pub fn tcx_lap_count(d: &TcxDoc) -> Int {
  return d.lap_start_time.len();
}

/// Total number of trackpoints over every lap.
/// Params: d - the document.
/// Returns: d.tp_time.len().
/// Complexity: O(1).
pub fn tcx_trackpoint_count(d: &TcxDoc) -> Int {
  return d.tp_time.len();
}

/// Sport attribute of an activity ("" when a is out of range).
/// Params: d - the document; a - the activity index.
/// Complexity: O(1).
pub fn tcx_activity_sport(d: &TcxDoc, a: Int) -> Str {
  if a < 0 || a >= d.act_sport.len() { return ""; }
  let v: Str = d.act_sport[a];
  return v;
}

/// Id text of an activity ("" when a is out of range).
/// Params: d - the document; a - the activity index.
/// Complexity: O(1).
pub fn tcx_activity_id(d: &TcxDoc, a: Int) -> Str {
  if a < 0 || a >= d.act_id.len() { return ""; }
  let v: Str = d.act_id[a];
  return v;
}

/// Number of laps owned by activity a (0 when a is out of range).
/// Params: d - the document; a - the activity index.
/// Complexity: O(1).
pub fn tcx_activity_lap_count(d: &TcxDoc, a: Int) -> Int {
  if a < 0 || a >= d.act_sport.len() { return 0; }
  let s = _lap_start(d, a);
  let e = _lap_end(d, a);
  if e <= s { return 0; }
  return e - s;
}

/// Owning activity of lap l (-1 when l is out of range).
/// Params: d - the document; l - the lap index.
/// Complexity: O(activities).
pub fn tcx_lap_activity(d: &TcxDoc, l: Int) -> Int {
  if l < 0 || l >= d.lap_start_time.len() { return -1; }
  var a = 0;
  while a < d.act_sport.len() {
    let s = _lap_start(d, a);
    let e = _lap_end(d, a);
    if l >= s && l < e { return a; }
    a = a + 1;
  }
  return -1;
}

/// Lap StartTime attribute ("" when l is out of range).
/// Params: d - the document; l - the lap index.
/// Complexity: O(1).
pub fn tcx_lap_start_time(d: &TcxDoc, l: Int) -> Str {
  if l < 0 || l >= d.lap_start_time.len() { return ""; }
  let v: Str = d.lap_start_time[l];
  return v;
}

/// Lap TotalTimeSeconds token ("" when l is out of range).
/// Params: d - the document; l - the lap index.
/// Complexity: O(1).
pub fn tcx_lap_total_time(d: &TcxDoc, l: Int) -> Str {
  if l < 0 || l >= d.lap_total_time.len() { return ""; }
  let v: Str = d.lap_total_time[l];
  return v;
}

/// Lap DistanceMeters token ("" when l is out of range).
/// Params: d - the document; l - the lap index.
/// Complexity: O(1).
pub fn tcx_lap_distance(d: &TcxDoc, l: Int) -> Str {
  if l < 0 || l >= d.lap_distance.len() { return ""; }
  let v: Str = d.lap_distance[l];
  return v;
}

/// Lap MaximumSpeed token ("" when absent or l is out of range).
/// Params: d - the document; l - the lap index.
/// Complexity: O(1).
pub fn tcx_lap_max_speed(d: &TcxDoc, l: Int) -> Str {
  if l < 0 || l >= d.lap_max_speed.len() { return ""; }
  let v: Str = d.lap_max_speed[l];
  return v;
}

/// Lap Calories token ("" when l is out of range).
/// Params: d - the document; l - the lap index.
/// Complexity: O(1).
pub fn tcx_lap_calories(d: &TcxDoc, l: Int) -> Str {
  if l < 0 || l >= d.lap_calories.len() { return ""; }
  let v: Str = d.lap_calories[l];
  return v;
}

/// Lap AverageHeartRateBpm/Value token ("" when absent or out of range).
/// Params: d - the document; l - the lap index.
/// Complexity: O(1).
pub fn tcx_lap_avg_hr(d: &TcxDoc, l: Int) -> Str {
  if l < 0 || l >= d.lap_avg_hr.len() { return ""; }
  let v: Str = d.lap_avg_hr[l];
  return v;
}

/// Number of trackpoints owned by lap l (0 when l is out of range).
/// Params: d - the document; l - the lap index.
/// Complexity: O(1).
pub fn tcx_lap_trackpoint_count(d: &TcxDoc, l: Int) -> Int {
  if l < 0 || l >= d.lap_start_time.len() { return 0; }
  let s = _tp_start(d, l);
  let e = _tp_end(d, l);
  if e <= s { return 0; }
  return e - s;
}

/// True when lap l has a Track (at least one trackpoint).
/// Params: d - the document; l - the lap index.
/// Complexity: O(1).
pub fn tcx_lap_has_track(d: &TcxDoc, l: Int) -> Bool {
  return tcx_lap_trackpoint_count(d, l) > 0;
}

/// Owning lap of trackpoint t (-1 when t is out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(laps).
pub fn tcx_trackpoint_lap(d: &TcxDoc, t: Int) -> Int {
  if t < 0 || t >= d.tp_time.len() { return -1; }
  var l = 0;
  while l < d.lap_start_time.len() {
    let s = _tp_start(d, l);
    let e = _tp_end(d, l);
    if t >= s && t < e { return l; }
    l = l + 1;
  }
  return -1;
}

/// Trackpoint Time text ("" when t is out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_time(d: &TcxDoc, t: Int) -> Str {
  if t < 0 || t >= d.tp_time.len() { return ""; }
  let v: Str = d.tp_time[t];
  return v;
}

/// Trackpoint LatitudeDegrees token ("" when no Position or out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_lat(d: &TcxDoc, t: Int) -> Str {
  if t < 0 || t >= d.tp_lat.len() { return ""; }
  let v: Str = d.tp_lat[t];
  return v;
}

/// Trackpoint LongitudeDegrees token ("" when no Position or out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_lon(d: &TcxDoc, t: Int) -> Str {
  if t < 0 || t >= d.tp_lon.len() { return ""; }
  let v: Str = d.tp_lon[t];
  return v;
}

/// Trackpoint true when it carries a Position (both coordinates).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_has_position(d: &TcxDoc, t: Int) -> Bool {
  if t < 0 || t >= d.tp_lat.len() { return false; }
  let v: Str = d.tp_lat[t];
  return !_str_empty(v);
}

/// Trackpoint AltitudeMeters token ("" when absent or out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_alt(d: &TcxDoc, t: Int) -> Str {
  if t < 0 || t >= d.tp_alt.len() { return ""; }
  let v: Str = d.tp_alt[t];
  return v;
}

/// Trackpoint DistanceMeters token ("" when absent or out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_distance(d: &TcxDoc, t: Int) -> Str {
  if t < 0 || t >= d.tp_distance.len() { return ""; }
  let v: Str = d.tp_distance[t];
  return v;
}

/// Trackpoint HeartRateBpm/Value token ("" when absent or out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_hr(d: &TcxDoc, t: Int) -> Str {
  if t < 0 || t >= d.tp_hr.len() { return ""; }
  let v: Str = d.tp_hr[t];
  return v;
}

/// Trackpoint Cadence token ("" when absent or out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_cadence(d: &TcxDoc, t: Int) -> Str {
  if t < 0 || t >= d.tp_cadence.len() { return ""; }
  let v: Str = d.tp_cadence[t];
  return v;
}

/// Trackpoint SensorState token ("" when absent or out of range).
/// Params: d - the document; t - the trackpoint index.
/// Complexity: O(1).
pub fn tcx_trackpoint_sensor(d: &TcxDoc, t: Int) -> Str {
  if t < 0 || t >= d.tp_sensor.len() { return ""; }
  let v: Str = d.tp_sensor[t];
  return v;
}

// --------------------------------------------------
//  Canonical serialization
// --------------------------------------------------

// Escape &, < and > in element text.
fn _escape_text(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: UInt8 = string.byte_at(s, i);
    if b == _T_AMP {
      builder.sb_push_str(&mut out, "&amp;");
    } elif b == _T_LT {
      builder.sb_push_str(&mut out, "&lt;");
    } elif b == _T_GT {
      builder.sb_push_str(&mut out, "&gt;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Escape &, <, > and " in double-quoted attribute values.
fn _escape_attr(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: UInt8 = string.byte_at(s, i);
    if b == _T_AMP {
      builder.sb_push_str(&mut out, "&amp;");
    } elif b == _T_LT {
      builder.sb_push_str(&mut out, "&lt;");
    } elif b == _T_GT {
      builder.sb_push_str(&mut out, "&gt;");
    } elif b == _T_DQUOTE {
      builder.sb_push_str(&mut out, "&quot;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Append 2*level spaces.
fn _push_indent(out: &mut Vec[UInt8], level: Int) {
  var i = 0;
  while i < level * 2 {
    out.push(_T_SPACE);
    i = i + 1;
  }
}

// Emit one indented text element: <name>escaped</name>\n.
fn _ptext(out: &mut Vec[UInt8], level: Int, name: Str, text: Str) {
  _push_indent(out, level);
  builder.sb_push_str(out, "<");
  builder.sb_push_str(out, name);
  builder.sb_push_str(out, ">");
  builder.sb_push_str(out, _escape_text(text));
  builder.sb_push_str(out, "</");
  builder.sb_push_str(out, name);
  builder.sb_push_str(out, ">\n");
}

// Emit one <Trackpoint> at level 5 and its optional children at level 6.
fn _emit_trackpoint(d: &TcxDoc, t: Int, out: &mut Vec[UInt8]) {
  _push_indent(out, 5);
  builder.sb_push_str(out, "<Trackpoint>\n");
  let timev: Str = d.tp_time[t];
  _ptext(out, 6, "Time", timev);
  let lat: Str = d.tp_lat[t];
  let lon: Str = d.tp_lon[t];
  if !_str_empty(lat) && !_str_empty(lon) {
    _push_indent(out, 6);
    builder.sb_push_str(out, "<Position>\n");
    _ptext(out, 7, "LatitudeDegrees", lat);
    _ptext(out, 7, "LongitudeDegrees", lon);
    _push_indent(out, 6);
    builder.sb_push_str(out, "</Position>\n");
  }
  let alt: Str = d.tp_alt[t];
  if !_str_empty(alt) { _ptext(out, 6, "AltitudeMeters", alt); }
  let dist: Str = d.tp_distance[t];
  if !_str_empty(dist) { _ptext(out, 6, "DistanceMeters", dist); }
  let hr: Str = d.tp_hr[t];
  if !_str_empty(hr) {
    _push_indent(out, 6);
    builder.sb_push_str(out, "<HeartRateBpm>\n");
    _ptext(out, 7, "Value", hr);
    _push_indent(out, 6);
    builder.sb_push_str(out, "</HeartRateBpm>\n");
  }
  let cad: Str = d.tp_cadence[t];
  if !_str_empty(cad) { _ptext(out, 6, "Cadence", cad); }
  let sens: Str = d.tp_sensor[t];
  if !_str_empty(sens) { _ptext(out, 6, "SensorState", sens); }
  _push_indent(out, 5);
  builder.sb_push_str(out, "</Trackpoint>\n");
}

// Emit one <Lap> at level 3: required tokens always, optional tokens and the
// Track only when present, in canonical order.
fn _emit_lap(d: &TcxDoc, l: Int, out: &mut Vec<UInt8>) {
  let start: Str = d.lap_start_time[l];
  _push_indent(out, 3);
  builder.sb_push_str(out, "<Lap StartTime=\"");
  builder.sb_push_str(out, _escape_attr(start));
  builder.sb_push_str(out, "\">\n");
  let tt: Str = d.lap_total_time[l];
  _ptext(out, 4, "TotalTimeSeconds", tt);
  let dist: Str = d.lap_distance[l];
  _ptext(out, 4, "DistanceMeters", dist);
  let ms: Str = d.lap_max_speed[l];
  if !_str_empty(ms) { _ptext(out, 4, "MaximumSpeed", ms); }
  let cal: Str = d.lap_calories[l];
  _ptext(out, 4, "Calories", cal);
  let hr: Str = d.lap_avg_hr[l];
  if !_str_empty(hr) {
    _push_indent(out, 4);
    builder.sb_push_str(out, "<AverageHeartRateBpm>\n");
    _ptext(out, 5, "Value", hr);
    _push_indent(out, 4);
    builder.sb_push_str(out, "</AverageHeartRateBpm>\n");
  }
  let s = _tp_start(d, l);
  let e = _tp_end(d, l);
  if e > s {
    _push_indent(out, 4);
    builder.sb_push_str(out, "<Track>\n");
    var t = s;
    while t < e {
      _emit_trackpoint(d, t, out);
      t = t + 1;
    }
    _push_indent(out, 4);
    builder.sb_push_str(out, "</Track>\n");
  }
  _push_indent(out, 3);
  builder.sb_push_str(out, "</Lap>\n");
}

// Emit one <Activity> at level 2: Id first, then its laps in order.
fn _emit_activity(d: &TcxDoc, a: Int, out: &mut Vec<UInt8>) {
  let sport: Str = d.act_sport[a];
  let id: Str = d.act_id[a];
  _push_indent(out, 2);
  builder.sb_push_str(out, "<Activity Sport=\"");
  builder.sb_push_str(out, _escape_attr(sport));
  builder.sb_push_str(out, "\">\n");
  _ptext(out, 3, "Id", id);
  let s = _lap_start(d, a);
  let e = _lap_end(d, a);
  var l = s;
  while l < e {
    _emit_lap(d, l, out);
    l = l + 1;
  }
  _push_indent(out, 2);
  builder.sb_push_str(out, "</Activity>\n");
}

/// Serialize a document as canonical TCX text.
/// Params: d - a document from tcx_parse or tcx_new.
/// Returns: the canonical text: an <?xml?> declaration line, then
/// TrainingCenterDatabase > Activities > Activity > Lap > Track >
/// Trackpoint, indented with two spaces per level, double-quoted attributes
/// (Sport, then StartTime), escaped text, a trailing newline, canonical
/// child order, and optional elements omitted when empty. A document with no
/// activities yields a self-closed <Activities/>. For a parsed document,
/// re-parsing this output reproduces the same model.
/// Complexity: O(records + output bytes).
pub fn tcx_build(d: &TcxDoc) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
  builder.sb_push_str(&mut out, "<TrainingCenterDatabase>\n");
  let ac = d.act_sport.len();
  if ac == 0 {
    _push_indent(&mut out, 1);
    builder.sb_push_str(&mut out, "<Activities/>\n");
  } else {
    _push_indent(&mut out, 1);
    builder.sb_push_str(&mut out, "<Activities>\n");
    var a = 0;
    while a < ac {
      _emit_activity(d, a, &mut out);
      a = a + 1;
    }
    _push_indent(&mut out, 1);
    builder.sb_push_str(&mut out, "</Activities>\n");
  }
  builder.sb_push_str(&mut out, "</TrainingCenterDatabase>\n");
  return builder.sb_to_str(&out);
}
