// XIOM -- xiom.duration: strict ISO 8601 duration parsing and canonical
// formatting.
// Port task: greenfield pure-XIOM package for ISO 8601 duration strings
// (no FFI, no calendar arithmetic).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   duration  := [ "+" | "-" ] "P" [ date-part ] [ "T" time-part ]
//   date-part := nY nM nW nD          ; in that order, each at most once
//   time-part := nH nM nS            ; in that order, each at most once
//   n         := 1*digit             ; leading zeros allowed, <= Int max
//   seconds   := n [ "." 1*9digit ]  ; fraction kept as validated text
//
// At least one component is required ("P" and "PT" are rejected), "T" must be
// followed by at least one time component, component order is enforced, and
// duplicates are rejected. Storage is flat: nine scalar fields (the sign, the
// seven Int components and the fraction text); there are no nested structures
// and no vector fields.
//
// v0.61.3 notes that shaped this module: free functions only (no self methods,
// no Vec[StructType], no Vec[Float64]); Ok/Err are constructed only in leaf
// helper functions because Result[Duration, Str] carries a struct payload;
// every string comparison goes through xiom.string.compare (never `==`); and
// every xiom.string.byte_at read is widened with `as Int` and masked with
// `& 0xFF`.

module xiom.duration

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ASCII bytes (Int constants, so every comparison is an Int comparison).
const _DUR_PLUS: Int = 43;
const _DUR_MINUS: Int = 45;
const _DUR_DOT: Int = 46;
const _DUR_ZERO: Int = 48;
const _DUR_NINE: Int = 57;
const _DUR_D: Int = 68;
const _DUR_H: Int = 72;
const _DUR_M: Int = 77;
const _DUR_P: Int = 80;
const _DUR_S: Int = 83;
const _DUR_T: Int = 84;
const _DUR_W: Int = 87;
const _DUR_Y: Int = 89;

// Signed 64-bit magnitude bounds (see _dur_number_overflow).
const _DUR_INT_MAX: Int = 9223372036854775807;
const _DUR_INT_MAX_DIV10: Int = 922337203685477580;
const _DUR_INT_MAX_LAST: Int = 7;

// floor(Int max / 3600) and floor(Int max / 60): the largest whole-hour and
// whole-minute values whose second counts still fit a signed 64-bit Int.
const _DUR_MAX_HOURS: Int = 2562047788015215;
const _DUR_MAX_MINUTES: Int = 153722867280912930;

// Maximum number of fractional-second digits (SPEC.md section 6).
const _DUR_MAX_FRACTION_DIGITS: Int = 9;

/// Parsed ISO 8601 duration. `sign` is 1 for an unsigned or "+" duration and
/// -1 for a "-" duration; the seven components are non-negative Int values;
/// `fraction` is the validated second-fraction digit text ("5" for PT0.5S,
/// "" when absent). A zero duration keeps every component at 0.
pub type Duration = {
  sign: Int;
  years: Int;
  months: Int;
  weeks: Int;
  days: Int;
  hours: Int;
  minutes: Int;
  seconds: Int;
  fraction: Str;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _duration_ok(v: Duration) -> Result[Duration, Str] { return Ok(v); }
fn _duration_err(m: Str) -> Result[Duration, Str] { return Err(m); }
fn _int_ok(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte predicates and scanning
// ---------------------------------------------------------------------------

fn _dur_is_digit(b: Int) -> Bool {
  return b >= _DUR_ZERO && b <= _DUR_NINE;
}

// Component designator bytes: Y M W D (date) and H M S (time); M is shared
// between months and minutes and is disambiguated by the section.
fn _dur_is_designator(b: Int) -> Bool {
  if b == _DUR_Y { return true; }
  if b == _DUR_M { return true; }
  if b == _DUR_W { return true; }
  if b == _DUR_D { return true; }
  if b == _DUR_H { return true; }
  if b == _DUR_S { return true; }
  return false;
}

// Widen and mask one byte of `s`.
fn _dur_byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// End of the ASCII digit run starting at `start`.
fn _dur_digits_end(s: Str, start: Int) -> Int {
  var i = start;
  while i < s.len() {
    if !_dur_is_digit(_dur_byte(s, i)) { break; }
    i = i + 1;
  }
  return i;
}

// True when the digit run [start, end) would not fit a signed 64-bit Int.
fn _dur_number_overflow(s: Str, start: Int, end: Int) -> Bool {
  var acc = 0;
  var i = start;
  while i < end {
    let d = _dur_byte(s, i) - _DUR_ZERO;
    if acc > _DUR_INT_MAX_DIV10 { return true; }
    if acc == _DUR_INT_MAX_DIV10 && d > _DUR_INT_MAX_LAST { return true; }
    acc = acc * 10 + d;
    i = i + 1;
  }
  return false;
}

// Value of a digit run [start, end) that is known to fit a signed 64-bit Int.
fn _dur_number_value(s: Str, start: Int, end: Int) -> Int {
  var acc = 0;
  var i = start;
  while i < end {
    acc = acc * 10 + (_dur_byte(s, i) - _DUR_ZERO);
    i = i + 1;
  }
  return acc;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

// Core scanner. Returns the parsed Duration, or a "duration: ..." error
// message (SPEC.md section 6). An empty component section is rejected and a
// component may appear at most once per section; the section rules are
// applied in scan order, so a string that is both out of order and a
// duplicate reports the violation reached first.
fn _duration_scan(s: Str) -> Result[Duration, Str] {
  let n = s.len();
  if n == 0 { return _duration_err("duration: empty input"); }

  var i = 0;
  var sign = 1;
  let first = _dur_byte(s, 0);
  if first == _DUR_MINUS {
    sign = -1;
    i = 1;
  } elif first == _DUR_PLUS {
    i = 1;
  }
  if i >= n { return _duration_err("duration: missing P: " + s); }
  if _dur_byte(s, i) != _DUR_P { return _duration_err("duration: missing P: " + s); }
  i = i + 1;

  var years = 0;
  var months = 0;
  var weeks = 0;
  var days = 0;
  var hours = 0;
  var minutes = 0;
  var seconds = 0;
  var fraction = "";
  var section = 0;    // 0 = date part, 1 = time part
  var last = -1;      // index of the last component accepted in this section
  var count = 0;      // components accepted across both sections
  var time_count = 0; // components accepted in the time section

  while i < n {
    let c = _dur_byte(s, i);
    if c == _DUR_T {
      if section == 1 { return _duration_err("duration: trailing tokens: " + s); }
      section = 1;
      last = -1;
      i = i + 1;
      continue;
    }
    if !_dur_is_digit(c) {
      if _dur_is_designator(c) { return _duration_err("duration: bad number: " + s); }
      return _duration_err("duration: trailing tokens: " + s);
    }

    let start = i;
    let end = _dur_digits_end(s, start);
    if _dur_number_overflow(s, start, end) { return _duration_err("duration: number too large: " + s); }

    var has_fraction = false;
    var fraction_start = 0;
    var fraction_end = 0;
    if end < n {
      if _dur_byte(s, end) == _DUR_DOT {
        fraction_start = end + 1;
        fraction_end = _dur_digits_end(s, fraction_start);
        let fraction_digits = fraction_end - fraction_start;
        if fraction_digits == 0 { return _duration_err("duration: bad fraction: " + s); }
        if fraction_digits > _DUR_MAX_FRACTION_DIGITS { return _duration_err("duration: bad fraction: " + s); }
        if fraction_end >= n { return _duration_err("duration: bad fraction: " + s); }
        if _dur_byte(s, fraction_end) != _DUR_S { return _duration_err("duration: bad fraction: " + s); }
        has_fraction = true;
      }
    }

    var dpos = end;
    if has_fraction { dpos = fraction_end; }
    if dpos >= n { return _duration_err("duration: bad number: " + s); }
    let d = _dur_byte(s, dpos);

    var sec = -1;
    var k = -1;
    if d == _DUR_Y { sec = 0; k = 0; }
    elif d == _DUR_W { sec = 0; k = 2; }
    elif d == _DUR_D { sec = 0; k = 3; }
    elif d == _DUR_H { sec = 1; k = 0; }
    elif d == _DUR_S { sec = 1; k = 2; }
    elif d == _DUR_M {
      if section == 0 { sec = 0; k = 1; } else { sec = 1; k = 1; }
    } else {
      return _duration_err("duration: bad number: " + s);
    }

    if sec != section { return _duration_err("duration: bad component order: " + s); }
    if k < last { return _duration_err("duration: bad component order: " + s); }
    if k == last { return _duration_err("duration: duplicate component: " + s); }
    last = k;
    count = count + 1;
    if section == 1 { time_count = time_count + 1; }

    let value = _dur_number_value(s, start, end);
    if section == 0 {
      if k == 0 { years = value; }
      elif k == 1 { months = value; }
      elif k == 2 { weeks = value; }
      else { days = value; }
    } else {
      if k == 0 { hours = value; }
      elif k == 1 { minutes = value; }
      else {
        seconds = value;
        if has_fraction { fraction = string.str_slice(s, fraction_start, fraction_end); }
      }
    }
    i = dpos + 1;
  }

  if section == 1 && time_count == 0 { return _duration_err("duration: T without components: " + s); }
  if count == 0 { return _duration_err("duration: empty duration: " + s); }

  let out = Duration{
    sign: sign;
    years: years;
    months: months;
    weeks: weeks;
    days: days;
    hours: hours;
    minutes: minutes;
    seconds: seconds;
    fraction: fraction;
  };
  return _duration_ok(out);
}

/// Parse a strict ISO 8601 duration string.
/// Params: s - a duration: optional "+"/"-" sign, "P", date components in
/// the order Y M W D, then an optional "T" followed by time components in
/// the order H M S. A component is a digit run (leading zeros accepted,
/// magnitude at most 9223372036854775807) followed by its designator; the
/// seconds component may carry one "." and 1..9 fraction digits.
/// Returns: Ok(Duration) for a strict duration; Err("duration: ...")
/// otherwise (see SPEC.md section 6 for the message catalog). "P0D" is
/// accepted; "P" and "PT" are not.
/// Complexity: O(len(s)).
pub fn duration_parse(s: Str) -> Result[Duration, Str] {
  return _duration_scan(s);
}

// ---------------------------------------------------------------------------
// Emitter
// ---------------------------------------------------------------------------

fn _dur_append_component(out: Str, value: Int, designator: Str) -> Str {
  return out + convert.int_to_string(value) + designator;
}

/// Render a duration in its canonical form.
/// Params: d - the duration; components are assumed non-negative and `sign`
/// to be -1 or 1 (as produced by duration_parse).
/// Returns: "-" when sign is negative, then "P", then every non-zero date
/// component in the order Y M W D, then "T" with every non-zero time
/// component in the order H M S; the seconds part is emitted when seconds is
/// non-zero or a fraction is present, and the fraction text is copied
/// verbatim. When no component is emitted the result is "0D" after the
/// prefix ("P0D", or "-P0D" when sign is negative). The output is stable:
/// duration_format(duration_parse(duration_format(d))) has the same fields
/// as d.
/// Error case: none.
/// Complexity: O(number of non-zero components + len(fraction)).
pub fn duration_format(d: &Duration) -> Str {
  var out = "P";
  if d.sign < 0 { out = "-P"; }
  var any = false;
  var time = "";
  if d.years != 0 { out = _dur_append_component(out, d.years, "Y"); any = true; }
  if d.months != 0 { out = _dur_append_component(out, d.months, "M"); any = true; }
  if d.weeks != 0 { out = _dur_append_component(out, d.weeks, "W"); any = true; }
  if d.days != 0 { out = _dur_append_component(out, d.days, "D"); any = true; }
  if d.hours != 0 { time = _dur_append_component(time, d.hours, "H"); any = true; }
  if d.minutes != 0 { time = _dur_append_component(time, d.minutes, "M"); any = true; }
  if d.seconds != 0 || d.fraction.len() > 0 {
    if d.fraction.len() > 0 {
      time = time + convert.int_to_string(d.seconds) + "." + d.fraction + "S";
    } else {
      time = time + convert.int_to_string(d.seconds) + "S";
    }
    any = true;
  }
  if time.len() > 0 { out = out + "T" + time; }
  if !any { out = out + "0D"; }
  return out;
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Sign of a duration: -1 when it was written with "-", else 1.
/// Error case: none.
/// Complexity: O(1).
pub fn duration_sign(d: &Duration) -> Int {
  return d.sign;
}

/// True when the years component is non-zero.
/// Error case: none.
/// Complexity: O(1).
pub fn duration_has_years(d: &Duration) -> Bool {
  return d.years != 0;
}

/// True when the months component is non-zero.
/// Error case: none.
/// Complexity: O(1).
pub fn duration_has_months(d: &Duration) -> Bool {
  return d.months != 0;
}

/// True when the weeks component is non-zero.
/// Error case: none.
/// Complexity: O(1).
pub fn duration_has_weeks(d: &Duration) -> Bool {
  return d.weeks != 0;
}

/// True when the days component is non-zero.
/// Error case: none.
/// Complexity: O(1).
pub fn duration_has_days(d: &Duration) -> Bool {
  return d.days != 0;
}

/// True when the hours component is non-zero.
/// Error case: none.
/// Complexity: O(1).
pub fn duration_has_hours(d: &Duration) -> Bool {
  return d.hours != 0;
}

/// True when the minutes component is non-zero.
/// Error case: none.
/// Complexity: O(1).
pub fn duration_has_minutes(d: &Duration) -> Bool {
  return d.minutes != 0;
}

/// True when the duration carries a second: a non-zero seconds value or any
/// fractional-second digits (PT0.5S has no seconds value but has seconds).
/// Error case: none.
/// Complexity: O(1).
pub fn duration_has_seconds(d: &Duration) -> Bool {
  if d.seconds != 0 { return true; }
  return d.fraction.len() > 0;
}

/// The validated fractional-second digit text exactly as written ("05" for
/// PT0.05S); "" when the duration has no fraction.
/// Error case: none.
/// Complexity: O(1).
pub fn duration_fraction(d: &Duration) -> Str {
  return d.fraction;
}

/// Value of one component selected by name.
/// Params: d - the duration; component - one of "years", "months", "weeks",
/// "days", "hours", "minutes", "seconds" (lowercase).
/// Returns: Ok(value) for a known name; Err("duration: unknown component:
/// <component>") otherwise. The fraction is not a component value; use
/// duration_fraction for it.
/// Error case: see above.
/// Complexity: O(len(component)).
pub fn duration_value(d: &Duration, component: Str) -> Result[Int, Str] {
  if compare.str_compare(component, "years") == 0 { return _int_ok(d.years); }
  if compare.str_compare(component, "months") == 0 { return _int_ok(d.months); }
  if compare.str_compare(component, "weeks") == 0 { return _int_ok(d.weeks); }
  if compare.str_compare(component, "days") == 0 { return _int_ok(d.days); }
  if compare.str_compare(component, "hours") == 0 { return _int_ok(d.hours); }
  if compare.str_compare(component, "minutes") == 0 { return _int_ok(d.minutes); }
  if compare.str_compare(component, "seconds") == 0 { return _int_ok(d.seconds); }
  return _int_err("duration: unknown component: " + component);
}

/// Total whole seconds of a time-only duration.
/// Params: d - the duration.
/// Returns: Ok(sign * (hours*3600 + minutes*60 + seconds)) when years,
/// months, weeks and days are all 0 and no fraction is present.
/// Err("duration: has date components: <canonical>") when any date component
/// is non-zero: a duration with months or years has no fixed second count
/// (calendar arithmetic is out of scope). Err("duration: has fractional
/// seconds: <canonical>") when a fraction is present: the fraction is text
/// of up to 9 digits; use duration_fraction. Err("duration: total seconds
/// overflow: <canonical>") when the total would not fit a signed 64-bit Int.
/// Error case: see above.
/// Complexity: O(len(component digits) + len(fraction)).
pub fn duration_total_seconds(d: &Duration) -> Result[Int, Str] {
  if d.years != 0 || d.months != 0 || d.weeks != 0 || d.days != 0 {
    return _int_err("duration: has date components: " + duration_format(d));
  }
  if d.fraction.len() > 0 {
    return _int_err("duration: has fractional seconds: " + duration_format(d));
  }
  if d.hours > _DUR_MAX_HOURS { return _int_err("duration: total seconds overflow: " + duration_format(d)); }
  var total = d.hours * 3600;
  if d.minutes > _DUR_MAX_MINUTES { return _int_err("duration: total seconds overflow: " + duration_format(d)); }
  let minute_seconds = d.minutes * 60;
  if minute_seconds > _DUR_INT_MAX - total { return _int_err("duration: total seconds overflow: " + duration_format(d)); }
  total = total + minute_seconds;
  if d.seconds > _DUR_INT_MAX - total { return _int_err("duration: total seconds overflow: " + duration_format(d)); }
  total = total + d.seconds;
  if d.sign < 0 { return _int_ok(0 - total); }
  return _int_ok(total);
}
