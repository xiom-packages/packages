// XIOM -- xiom.l10n.time: locale-style time-of-day and timezone-offset logic.
// Port task: real, tested, pure-XIOM implementation replacing the placeholder
// (time-of-day validation, 12h/24h conversion, pattern formatting and parsing,
// day-period classification, timezone offsets). Caller-supplied AM/PM labels
// and period boundaries: there is no locale database and no clock.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a wall-clock time is `TimeOfDay` (hour 0..23, minute 0..59,
// second 0..59); a UTC offset is `TimeOffset` (sign -1/+1, hours 0..14,
// minutes 0..59, magnitude within -12:00..+14:00). Nothing here uses floating
// point, a clock, FFI, locale databases or allocators; the module depends only
// on xiom.string, xiom.string.compare and xiom.convert from xiom.std.
//
// v0.62.0 notes that shaped this module: free functions only; every
// xiom.string.byte_at read is widened with `as Int` and masked with `& 0xFF`
// before any comparison; every string equality check goes through
// compare.str_compare (never `==`); Ok/Err are constructed only in leaf
// helper functions because functions returning struct payloads miscompile
// with inline construction.

module xiom.l10n.time

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ASCII byte values (Int constants, so every comparison is an Int comparison).
const _LT_PLUS: Int = 43;
const _LT_MINUS: Int = 45;
const _LT_ZERO: Int = 48;
const _LT_NINE: Int = 57;
const _LT_COLON: Int = 58;
const _LT_UPPER_Z: Int = 90;
const _LT_SPACE: Int = 32;

// Offset limits in whole minutes: -12:00 .. +14:00 (real-world UTC range).
const _LT_OFF_MIN_MINUTES: Int = 0 - 720;
const _LT_OFF_MAX_MINUTES: Int = 840;

// Seconds in a day, for timezone wrapping.
const _LT_SECONDS_PER_DAY: Int = 86400;

/// Wall-clock time of day: hour 0..23, minute 0..59, second 0..59. The fields
/// are public, but construct values through l10n_time_of_day so the ranges
/// hold; functions that consume a TimeOfDay re-validate the fields.
pub type TimeOfDay = {
  hour: Int;
  minute: Int;
  second: Int;
}

/// Timezone offset from UTC: `sign` is -1 or +1, `hours` 0..14, `minutes`
/// 0..59, and sign * (hours*60 + minutes) lies in -720..840 (-12:00..+14:00).
/// The canonical zero offset is sign = 1, hours = 0, minutes = 0; it formats
/// as "Z" and every zero form compares equal.
pub type TimeOffset = {
  sign: Int;
  hours: Int;
  minutes: Int;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.62.0.
fn _time_ok(v: TimeOfDay) -> Result[TimeOfDay, Str] { return Ok(v); }
fn _time_err(m: Str) -> Result[TimeOfDay, Str] { return Err(m); }
fn _int_ok(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }
fn _str_ok(v: Str) -> Result[Str, Str] { return Ok(v); }
fn _str_err(m: Str) -> Result[Str, Str] { return Err(m); }
fn _off_ok(v: TimeOffset) -> Result[TimeOffset, Str] { return Ok(v); }
fn _off_err(m: Str) -> Result[TimeOffset, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte and string helpers
// ---------------------------------------------------------------------------

// Widen and mask one byte of `s` (never compare the raw UInt8).
fn _b(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _is_digit(b: Int) -> Bool {
  return b >= _LT_ZERO && b <= _LT_NINE;
}

// Two-digit zero-padded decimal text for 0 <= v <= 99 (larger v passes
// through as its full decimal text; callers format only validated values).
fn _pad2(v: Int) -> Str {
  if v >= 0 && v <= 9 {
    return "0" + convert.int_to_string(v);
  }
  return convert.int_to_string(v);
}

// True when `token` occurs in `s` at byte offset `at` (byte-wise match).
fn _tok_at(s: Str, at: Int, token: Str) -> Bool {
  let n = token.len();
  if at + n > s.len() {
    return false;
  }
  var k = 0;
  while k < n {
    if _b(s, at + k) != _b(token, k) {
      return false;
    }
    k = k + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// (a) Time-of-day model and validation
// ---------------------------------------------------------------------------

/// True when (hour, minute, second) is a valid wall-clock time.
/// Params: hour / minute / second - the components to check.
/// Returns: hour in 0..23, minute in 0..59 and second in 0..59.
/// Error case: none.
/// Complexity: O(1).
pub fn l10n_time_is_valid(hour: Int, minute: Int, second: Int) -> Bool {
  if hour < 0 || hour > 23 { return false; }
  if minute < 0 || minute > 59 { return false; }
  if second < 0 || second > 59 { return false; }
  return true;
}

/// Validating TimeOfDay constructor.
/// Params: hour / minute / second - the components.
/// Returns: Ok(TimeOfDay) when the ranges hold.
/// Error case: Err("l10n.time: hour out of range"), "minute out of range" or
/// "second out of range", in that check order.
/// Complexity: O(1).
pub fn l10n_time_of_day(hour: Int, minute: Int, second: Int) -> Result[TimeOfDay, Str] {
  if hour < 0 || hour > 23 {
    return _time_err("l10n.time: hour out of range");
  }
  if minute < 0 || minute > 59 {
    return _time_err("l10n.time: minute out of range");
  }
  if second < 0 || second > 59 {
    return _time_err("l10n.time: second out of range");
  }
  return _time_ok(TimeOfDay{ hour: hour; minute: minute; second: second });
}

/// Field-wise equality of two times. Never `==` on the structs themselves.
/// Params: a / b - the times to compare.
/// Returns: true when all three components are equal.
/// Error case: none.
/// Complexity: O(1).
pub fn l10n_time_equals(a: TimeOfDay, b: TimeOfDay) -> Bool {
  if a.hour != b.hour { return false; }
  if a.minute != b.minute { return false; }
  if a.second != b.second { return false; }
  return true;
}

/// Seconds since midnight of `t` (hour*3600 + minute*60 + second).
/// Params: t - the time; fields are trusted as validated.
/// Returns: 0..86399 for a valid time.
/// Error case: none (range checking lives in l10n_time_of_day and
/// l10n_time_from_total_seconds).
/// Complexity: O(1).
pub fn l10n_time_total_seconds(t: TimeOfDay) -> Int {
  return t.hour * 3600 + t.minute * 60 + t.second;
}

/// TimeOfDay from seconds since midnight.
/// Params: total - seconds since midnight.
/// Returns: Ok(TimeOfDay) for total in 0..86399; field extraction is exact.
/// Error case: Err("l10n.time: time out of range") otherwise.
/// Complexity: O(1).
pub fn l10n_time_from_total_seconds(total: Int) -> Result[TimeOfDay, Str] {
  if total < 0 || total > 86399 {
    return _time_err("l10n.time: time out of range");
  }
  let hour = total / 3600;
  let rem = total % 3600;
  let minute = rem / 60;
  let second = rem % 60;
  return _time_ok(TimeOfDay{ hour: hour; minute: minute; second: second });
}

// ---------------------------------------------------------------------------
// (b) 12h <-> 24h conversion (caller-supplied labels)
// ---------------------------------------------------------------------------

/// Convert a 24-hour clock hour to its 12-hour face value.
/// Params: hour24 - the hour in 0..23.
/// Returns: Ok(12) for 0 (midnight) and 12 (noon); Ok(1..11) for 1..11 and
/// 13..23 (hour - 12).
/// Error case: Err("l10n.time: hour out of range") outside 0..23.
/// Complexity: O(1).
pub fn l10n_hour_24_to_12(hour24: Int) -> Result[Int, Str] {
  if hour24 < 0 || hour24 > 23 {
    return _int_err("l10n.time: hour out of range");
  }
  if hour24 == 0 { return _int_ok(12); }
  if hour24 <= 12 { return _int_ok(hour24); }
  return _int_ok(hour24 - 12);
}

/// Convert a 12-hour clock hour plus period flag to its 24-hour value.
/// Params: hour12 - the face hour in 1..12; is_pm - true for the PM period.
/// Returns: Ok(0) for 12 AM (midnight), Ok(12) for 12 PM (noon), Ok(hour12)
/// for 1..11 AM and Ok(hour12 + 12) for 1..11 PM.
/// Error case: Err("l10n.time: hour out of range") outside 1..12.
/// Complexity: O(1).
pub fn l10n_hour_12_to_24(hour12: Int, is_pm: Bool) -> Result[Int, Str] {
  if hour12 < 1 || hour12 > 12 {
    return _int_err("l10n.time: hour out of range");
  }
  if hour12 == 12 {
    if is_pm { return _int_ok(12); }
    return _int_ok(0);
  }
  if is_pm { return _int_ok(hour12 + 12); }
  return _int_ok(hour12);
}

/// Period (AM/PM) label for a 24-hour hour, using caller-supplied labels.
/// Params: hour24 - the hour in 0..23; am_label / pm_label - the caller's
/// period labels (e.g. "AM"/"PM", "a.m."/"p.m.", or any other strings).
/// Returns: Ok(am_label) for hours 0..11, Ok(pm_label) for hours 12..23.
/// Error case: Err("l10n.time: hour out of range") outside 0..23.
/// Complexity: O(1).
pub fn l10n_hour_period(hour24: Int, am_label: Str, pm_label: Str) -> Result[Str, Str] {
  if hour24 < 0 || hour24 > 23 {
    return _str_err("l10n.time: hour out of range");
  }
  if hour24 < 12 {
    return _str_ok(am_label);
  }
  return _str_ok(pm_label);
}

/// 12-hour hour with its period label, e.g. "12 AM", "1 PM", "11 AM".
/// Params: hour24 - the hour in 0..23; am_label / pm_label - the period
/// labels. The label is joined with one ASCII space and is emitted exactly
/// as supplied.
/// Returns: Ok(label_text) like "12 AM" (0), "12 PM" (12), "1 PM" (13).
/// Error case: Err("l10n.time: hour out of range") outside 0..23.
/// Complexity: O(len(label)).
pub fn l10n_hour_12_label(hour24: Int, am_label: Str, pm_label: Str) -> Result[Str, Str] {
  let face = l10n_hour_24_to_12(hour24);
  match face {
    Ok(v) => {
      var period: Str = pm_label;
      if hour24 < 12 { period = am_label; }
      return _str_ok(convert.int_to_string(v) + " " + period);
    },
    Err(e) => { return _str_err(e); },
  }
  return _str_err("l10n.time: hour out of range");
}

// ---------------------------------------------------------------------------
// (c) Pattern formatting
// ---------------------------------------------------------------------------

/// Format a time with an HH:MM:SS-style pattern.
/// Params: t - the time (re-validated); pattern - the token pattern below;
/// am_label / pm_label - the labels emitted for token `A`.
/// Tokens (case-sensitive, matched longest first; any other byte is copied
/// literally):
///   HH zero-padded 24h hour    H unpadded 24h hour
///   hh zero-padded 12h hour    h unpadded 12h hour
///   MM / mm zero-padded minute M / m unpadded minute
///   SS / ss zero-padded second S / s unpadded second
///   A the caller's AM/PM label
/// Returns: Ok(text) with every token expanded. "HH:MM:SS" gives "13:05:09",
/// "h:mm:ss A" gives "1:05:09 PM".
/// Error case: Err("l10n.time: invalid time") when t's fields are out of
/// range.
/// Complexity: O(len(pattern) + len(labels)).
pub fn l10n_time_format(t: TimeOfDay, pattern: Str, am_label: Str, pm_label: Str) -> Result[Str, Str] {
  if !l10n_time_is_valid(t.hour, t.minute, t.second) {
    return _str_err("l10n.time: invalid time");
  }
  var face = t.hour;
  if t.hour > 12 { face = t.hour - 12; }
  if t.hour == 0 { face = 12; }
  var period: Str = pm_label;
  if t.hour < 12 { period = am_label; }
  var out = "";
  var i = 0;
  let n = pattern.len();
  while i < n {
    if _tok_at(pattern, i, "HH") {
      out = out + _pad2(t.hour);
      i = i + 2;
    } elif _tok_at(pattern, i, "H") {
      out = out + convert.int_to_string(t.hour);
      i = i + 1;
    } elif _tok_at(pattern, i, "hh") {
      out = out + _pad2(face);
      i = i + 2;
    } elif _tok_at(pattern, i, "h") {
      out = out + convert.int_to_string(face);
      i = i + 1;
    } elif _tok_at(pattern, i, "MM") {
      out = out + _pad2(t.minute);
      i = i + 2;
    } elif _tok_at(pattern, i, "M") {
      out = out + convert.int_to_string(t.minute);
      i = i + 1;
    } elif _tok_at(pattern, i, "mm") {
      out = out + _pad2(t.minute);
      i = i + 2;
    } elif _tok_at(pattern, i, "m") {
      out = out + convert.int_to_string(t.minute);
      i = i + 1;
    } elif _tok_at(pattern, i, "SS") {
      out = out + _pad2(t.second);
      i = i + 2;
    } elif _tok_at(pattern, i, "S") {
      out = out + convert.int_to_string(t.second);
      i = i + 1;
    } elif _tok_at(pattern, i, "ss") {
      out = out + _pad2(t.second);
      i = i + 2;
    } elif _tok_at(pattern, i, "s") {
      out = out + convert.int_to_string(t.second);
      i = i + 1;
    } elif _tok_at(pattern, i, "A") {
      out = out + period;
      i = i + 1;
    } else {
      out = out + string.str_slice(pattern, i, i + 1);
      i = i + 1;
    }
  }
  return _str_ok(out);
}

// ---------------------------------------------------------------------------
// (d) Parsing
// ---------------------------------------------------------------------------

/// Parse "HH:MM[:SS]" with optional AM/PM label.
/// Params: text - the time text; am_label / pm_label - the only accepted
/// trailing labels, matched case-sensitively with compare.str_compare.
/// Grammar: optional leading/trailing ASCII spaces; 1..2 digit hour;
/// required ':' ; 1..2 digit minute; optional ':' and 1..2 digit second;
/// optional spaces; an optional label that must equal am_label or pm_label
/// exactly. Without a label the hour must be 0..23; with a label it must be
/// 1..12 and "12 AM" maps to 00:00 while "12 PM" maps to 12:00.
/// Returns: Ok(TimeOfDay) for a well-formed, in-range time.
/// Error case: left-to-right, first error wins: "l10n.time: empty input",
/// "bad digit", "too many digits" (a field longer than two digits),
/// "expected ':'", "unknown label" (anything left over that matches neither
/// label, including junk), "hour out of range", "minute out of range",
/// "second out of range".
/// Complexity: O(len(text)).
pub fn l10n_time_parse(text: Str, am_label: Str, pm_label: Str) -> Result[TimeOfDay, Str] {
  let n = text.len();
  var lo = 0;
  while lo < n && _b(text, lo) == _LT_SPACE {
    lo = lo + 1;
  }
  var hi = n;
  while hi > lo && _b(text, hi - 1) == _LT_SPACE {
    hi = hi - 1;
  }
  if lo >= hi {
    return _time_err("l10n.time: empty input");
  }

  var i = lo;
  var hour = 0;
  var hcount = 0;
  while i < hi && _is_digit(_b(text, i)) {
    if hcount >= 2 {
      return _time_err("l10n.time: too many digits");
    }
    hour = hour * 10 + (_b(text, i) - _LT_ZERO);
    hcount = hcount + 1;
    i = i + 1;
  }
  if hcount == 0 {
    return _time_err("l10n.time: bad digit");
  }
  if i >= hi || _b(text, i) != _LT_COLON {
    return _time_err("l10n.time: expected ':'");
  }
  i = i + 1;

  var minute = 0;
  var mcount = 0;
  while i < hi && _is_digit(_b(text, i)) {
    if mcount >= 2 {
      return _time_err("l10n.time: too many digits");
    }
    minute = minute * 10 + (_b(text, i) - _LT_ZERO);
    mcount = mcount + 1;
    i = i + 1;
  }
  if mcount == 0 {
    return _time_err("l10n.time: bad digit");
  }

  var second = 0;
  var scount = 0;
  if i < hi && _b(text, i) == _LT_COLON {
    i = i + 1;
    while i < hi && _is_digit(_b(text, i)) {
      if scount >= 2 {
        return _time_err("l10n.time: too many digits");
      }
      second = second * 10 + (_b(text, i) - _LT_ZERO);
      scount = scount + 1;
      i = i + 1;
    }
    if scount == 0 {
      return _time_err("l10n.time: bad digit");
    }
  }

  while i < hi && _b(text, i) == _LT_SPACE {
    i = i + 1;
  }

  var label = 0;
  if i < hi {
    let rest: Str = string.str_slice(text, i, hi);
    let is_am = compare.str_compare(rest, am_label) == 0;
    let is_pm = compare.str_compare(rest, pm_label) == 0;
    if is_am {
      label = 1;
    } elif is_pm {
      label = 2;
    } else {
      return _time_err("l10n.time: unknown label");
    }
    i = hi;
  }

  if label == 0 {
    if hour < 0 || hour > 23 {
      return _time_err("l10n.time: hour out of range");
    }
  } else {
    if hour < 1 || hour > 12 {
      return _time_err("l10n.time: hour out of range");
    }
    if label == 1 {
      if hour == 12 { hour = 0; }
    } else {
      if hour != 12 { hour = hour + 12; }
    }
  }
  if minute < 0 || minute > 59 {
    return _time_err("l10n.time: minute out of range");
  }
  if second < 0 || second > 59 {
    return _time_err("l10n.time: second out of range");
  }
  return _time_ok(TimeOfDay{ hour: hour; minute: minute; second: second });
}

// ---------------------------------------------------------------------------
// (e) Day periods
// ---------------------------------------------------------------------------

/// Classify an hour into a day period using caller-supplied boundaries.
/// Params: hour - the hour in 0..23; morning_start / afternoon_start /
/// evening_start / night_start - hour boundaries in 0..23, strictly
/// increasing. A period covers [start, next_start), so morning is
/// [morning_start, afternoon_start), afternoon [afternoon_start,
/// evening_start), evening [evening_start, night_start) and night wraps the
/// rest: [night_start, 24) plus [0, morning_start).
/// Returns: Ok("morning"), Ok("afternoon"), Ok("evening") or Ok("night").
/// Error case: Err("l10n.time: hour out of range"), and for the boundaries
/// "l10n.time: boundary out of range" or "l10n.time: boundaries out of
/// order" (checked in parameter order after the hour).
/// Complexity: O(1).
pub fn l10n_day_period(hour: Int, morning_start: Int, afternoon_start: Int, evening_start: Int, night_start: Int) -> Result[Str, Str] {
  if hour < 0 || hour > 23 {
    return _str_err("l10n.time: hour out of range");
  }
  if morning_start < 0 || morning_start > 23 {
    return _str_err("l10n.time: boundary out of range");
  }
  if afternoon_start < 0 || afternoon_start > 23 {
    return _str_err("l10n.time: boundary out of range");
  }
  if evening_start < 0 || evening_start > 23 {
    return _str_err("l10n.time: boundary out of range");
  }
  if night_start < 0 || night_start > 23 {
    return _str_err("l10n.time: boundary out of range");
  }
  if !(morning_start < afternoon_start) || !(afternoon_start < evening_start) || !(evening_start < night_start) {
    return _str_err("l10n.time: boundaries out of order");
  }
  if hour >= morning_start && hour < afternoon_start {
    return _str_ok("morning");
  }
  if hour >= afternoon_start && hour < evening_start {
    return _str_ok("afternoon");
  }
  if hour >= evening_start && hour < night_start {
    return _str_ok("evening");
  }
  return _str_ok("night");
}

// ---------------------------------------------------------------------------
// (f) Timezone offsets
// ---------------------------------------------------------------------------

/// Validating TimeOffset constructor.
/// Params: sign - +1 or -1; hours - 0..14; minutes - 0..59. The total
/// sign * (hours*60 + minutes) must lie in -720..840 (-12:00..+14:00), so
/// "+14:00" is the maximum and "-12:00" the minimum. A zero total is
/// normalized to the canonical sign +1.
/// Returns: Ok(TimeOffset).
/// Error case: Err("l10n.time: bad offset sign"), "offset hour out of
/// range", "offset minute out of range" or "offset out of range", in that
/// order.
/// Complexity: O(1).
pub fn l10n_offset_new(sign: Int, hours: Int, minutes: Int) -> Result[TimeOffset, Str] {
  if sign != 1 && sign != 0 - 1 {
    return _off_err("l10n.time: bad offset sign");
  }
  if hours < 0 || hours > 14 {
    return _off_err("l10n.time: offset hour out of range");
  }
  if minutes < 0 || minutes > 59 {
    return _off_err("l10n.time: offset minute out of range");
  }
  let total = sign * (hours * 60 + minutes);
  if total < _LT_OFF_MIN_MINUTES || total > _LT_OFF_MAX_MINUTES {
    return _off_err("l10n.time: offset out of range");
  }
  if total == 0 {
    return _off_ok(TimeOffset{ sign: 1; hours: hours; minutes: minutes });
  }
  return _off_ok(TimeOffset{ sign: sign; hours: hours; minutes: minutes });
}

/// Parse an ISO-8601-style UTC offset.
/// Params: text - exactly "Z" (zero offset) or a six-byte "+HH:MM" /
/// "-HH:MM" with two decimal digits for hours and minutes.
/// Returns: Ok(TimeOffset). "+00:00" and "-00:00" normalize to the canonical
/// zero offset (sign +1).
/// Error case: Err("l10n.time: empty input") for ""; "l10n.time: bad offset"
/// for any shape other than "Z" or sign+2digits+':'+2digits; "l10n.time:
/// offset digit" for a non-digit in a numeric slot; "l10n.time: offset out
/// of range" when minutes exceed 59 or the total falls outside
/// -720..840.
/// Complexity: O(1).
pub fn l10n_offset_parse(text: Str) -> Result[TimeOffset, Str] {
  let n = text.len();
  if n == 0 {
    return _off_err("l10n.time: empty input");
  }
  if n == 1 && _b(text, 0) == _LT_UPPER_Z {
    return _off_ok(TimeOffset{ sign: 1; hours: 0; minutes: 0 });
  }
  if n != 6 {
    return _off_err("l10n.time: bad offset");
  }
  let b0 = _b(text, 0);
  if b0 != _LT_PLUS && b0 != _LT_MINUS {
    return _off_err("l10n.time: bad offset");
  }
  if _b(text, 3) != _LT_COLON {
    return _off_err("l10n.time: bad offset");
  }
  var k = 0;
  while k < 6 {
    if k != 0 && k != 3 {
      if !_is_digit(_b(text, k)) {
        return _off_err("l10n.time: offset digit");
      }
    }
    k = k + 1;
  }
  let hours = (_b(text, 1) - _LT_ZERO) * 10 + (_b(text, 2) - _LT_ZERO);
  let minutes = (_b(text, 4) - _LT_ZERO) * 10 + (_b(text, 5) - _LT_ZERO);
  if minutes > 59 {
    return _off_err("l10n.time: offset out of range");
  }
  var sign = 1;
  if b0 == _LT_MINUS { sign = 0 - 1; }
  let total = sign * (hours * 60 + minutes);
  if total < _LT_OFF_MIN_MINUTES || total > _LT_OFF_MAX_MINUTES {
    return _off_err("l10n.time: offset out of range");
  }
  if total == 0 {
    return _off_ok(TimeOffset{ sign: 1; hours: 0; minutes: 0 });
  }
  return _off_ok(TimeOffset{ sign: sign; hours: hours; minutes: minutes });
}

/// Canonical text for a TimeOffset: "Z" for a zero offset, else "+HH:MM" or
/// "-HH:MM".
/// Params: off - the offset; fields are trusted as validated (construct with
/// l10n_offset_new / l10n_offset_parse / l10n_offset_from_minutes). A
/// malformed literal still formats shape-consistently from its fields.
/// Returns: the canonical offset text.
/// Error case: none.
/// Complexity: O(1).
pub fn l10n_offset_format(off: TimeOffset) -> Str {
  let total = l10n_offset_total_minutes(off);
  if total == 0 {
    return "Z";
  }
  var sign_text = "+";
  var mag = total;
  if total < 0 {
    sign_text = "-";
    mag = 0 - total;
  }
  let hours = mag / 60;
  let minutes = mag % 60;
  return sign_text + _pad2(hours) + ":" + _pad2(minutes);
}

/// Signed minutes of a TimeOffset (sign * (hours*60 + minutes)).
/// Params: off - the offset. A sign other than -1 is treated as +1.
/// Returns: the signed minute count (-720..840 for a validated offset).
/// Error case: none (range checking lives in the constructors).
/// Complexity: O(1).
pub fn l10n_offset_total_minutes(off: TimeOffset) -> Int {
  var sign = 1;
  if off.sign < 0 { sign = 0 - 1; }
  return sign * (off.hours * 60 + off.minutes);
}

/// TimeOffset from signed minutes.
/// Params: total - signed minutes from UTC.
/// Returns: Ok(TimeOffset) for total in -720..840; zero normalizes to the
/// canonical sign +1.
/// Error case: Err("l10n.time: offset out of range") otherwise.
/// Complexity: O(1).
pub fn l10n_offset_from_minutes(total: Int) -> Result[TimeOffset, Str] {
  if total < _LT_OFF_MIN_MINUTES || total > _LT_OFF_MAX_MINUTES {
    return _off_err("l10n.time: offset out of range");
  }
  if total == 0 {
    return _off_ok(TimeOffset{ sign: 1; hours: 0; minutes: 0 });
  }
  var sign = 1;
  var mag = total;
  if total < 0 {
    sign = 0 - 1;
    mag = 0 - total;
  }
  let hours = mag / 60;
  let minutes = mag % 60;
  return _off_ok(TimeOffset{ sign: sign; hours: hours; minutes: minutes });
}

/// True when the offset denotes zero minutes from UTC (any zero form).
/// Params: off - the offset.
/// Returns: l10n_offset_total_minutes(off) == 0.
/// Error case: none.
/// Complexity: O(1).
pub fn l10n_offset_is_zero(off: TimeOffset) -> Bool {
  return l10n_offset_total_minutes(off) == 0;
}

/// Minute-value equality of two offsets.
/// Params: a / b - the offsets to compare.
/// Returns: true when both denote the same signed minute count, so "+00:00"
/// equals "-00:00" equals "Z".
/// Error case: none.
/// Complexity: O(1).
pub fn l10n_offset_equals(a: TimeOffset, b: TimeOffset) -> Bool {
  return l10n_offset_total_minutes(a) == l10n_offset_total_minutes(b);
}

/// Shift a UTC time by an offset, yielding local time. The result wraps
/// around midnight: 23:30 with +01:00 is 00:30.
/// Params: t - the UTC time (re-validated); off - the offset, which must be
/// a validated offset in -12:00..+14:00.
/// Returns: Ok(local TimeOfDay) = (t + off) modulo 24 hours.
/// Error case: Err("l10n.time: invalid time") when t's fields are out of
/// range; Err("l10n.time: offset out of range") when off's minute total is
/// outside -720..840.
/// Complexity: O(1).
pub fn l10n_time_apply_offset(t: TimeOfDay, off: TimeOffset) -> Result[TimeOfDay, Str] {
  if !l10n_time_is_valid(t.hour, t.minute, t.second) {
    return _time_err("l10n.time: invalid time");
  }
  let off_min = l10n_offset_total_minutes(off);
  if off_min < _LT_OFF_MIN_MINUTES || off_min > _LT_OFF_MAX_MINUTES {
    return _time_err("l10n.time: offset out of range");
  }
  let shifted = l10n_time_total_seconds(t) + off_min * 60;
  let wrapped = ((shifted % _LT_SECONDS_PER_DAY) + _LT_SECONDS_PER_DAY) % _LT_SECONDS_PER_DAY;
  return l10n_time_from_total_seconds(wrapped);
}

/// Inverse of l10n_time_apply_offset: strip an offset from local time,
/// yielding UTC. The result wraps around midnight.
/// Params: t - the local time (re-validated); off - the offset, which must
/// be a validated offset in -12:00..+14:00.
/// Returns: Ok(UTC TimeOfDay) = (t - off) modulo 24 hours.
/// Error case: Err("l10n.time: invalid time") when t's fields are out of
/// range; Err("l10n.time: offset out of range") when off's minute total is
/// outside -720..840.
/// Complexity: O(1).
pub fn l10n_time_remove_offset(t: TimeOfDay, off: TimeOffset) -> Result[TimeOfDay, Str] {
  if !l10n_time_is_valid(t.hour, t.minute, t.second) {
    return _time_err("l10n.time: invalid time");
  }
  let off_min = l10n_offset_total_minutes(off);
  if off_min < _LT_OFF_MIN_MINUTES || off_min > _LT_OFF_MAX_MINUTES {
    return _time_err("l10n.time: offset out of range");
  }
  let shifted = l10n_time_total_seconds(t) - off_min * 60;
  let wrapped = ((shifted % _LT_SECONDS_PER_DAY) + _LT_SECONDS_PER_DAY) % _LT_SECONDS_PER_DAY;
  return l10n_time_from_total_seconds(wrapped);
}
