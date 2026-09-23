// XIOM -- xiom.scheduler: cron expression parsing and next-run computation (UTC)
// Port task: replace the xiom.scheduler placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a 5-field cron expression ("minute hour day-of-month month weekday")
// parses into CronSchedule, a struct of five ascending, duplicate-free Vec[Int]
// fields. Matching and next-run computation use pure civil-date math from
// epoch seconds (UTC); no FFI and no stdlib time module. Day-of-month and
// weekday interact with the standard cron OR rule when both are restricted
// (see SPEC.md section 3). Ok/Err are constructed only inside the
// _ok_*/_err_* helpers (XIOM v0.61.3 miscompiles direct Result construction in
// struct-returning functions; see xiom-patch SPEC.md section 7 and this
// package's SPEC.md).
//
// Language notes (XIOM v0.61.3): free functions only, no Vec[StructType];
// Str values read from Vec[Str] elements are compared with str_compare
// (BUG 17: `==` on such elements lowers to a pointer comparison); Vec[Int]
// element reads are bound with a typed `let`.

module xiom.scheduler

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _CRON_TAB: UInt8 = 9u8;
const _CRON_SPACE: UInt8 = 32u8;
const _CRON_STAR: UInt8 = 42u8;
const _CRON_COMMA: UInt8 = 44u8;
const _CRON_DASH: UInt8 = 45u8;
const _CRON_SLASH: UInt8 = 47u8;
const _MINS_PER_HOUR: Int = 60;
const _MINS_PER_DAY: Int = 1440;
const _SECS_PER_MIN: Int = 60;
const _SECS_PER_HOUR: Int = 3600;
const _SECS_PER_DAY: Int = 86400;
const _DAYS_SCAN_LIMIT: Int = 1461;

/// Allowed values of one cron schedule. Every vector is sorted ascending and
/// duplicate-free: minutes 0-59, hours 0-23, days 1-31, months 1-12,
/// weekdays 0-6 (0 = Sunday). The full allowed range means "unrestricted".
pub type CronSchedule = {
  minutes: Vec[Int];
  hours: Vec[Int];
  days: Vec[Int];
  months: Vec[Int];
  weekdays: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (compiler workaround; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_vec(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }
fn _err_vec(m: Str) -> Result[Vec[Int], Str] { return Err(m); }
fn _ok_sched(s: CronSchedule) -> Result[CronSchedule, Str] { return Ok(s); }
fn _err_sched(m: Str) -> Result[CronSchedule, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte and vector helpers
// ---------------------------------------------------------------------------

fn _is_ws_byte(b: UInt8) -> Bool {
  return b == _CRON_SPACE || b == _CRON_TAB;
}

// Byte index of the first `target` in s, or -1.
fn _find_byte(s: Str, target: UInt8) -> Int {
  var i = 0;
  while i < s.len() {
    if string.byte_at(s, i) == target { return i; }
    i = i + 1;
  }
  return -1;
}

fn _has_int(v: &Vec[Int], x: Int) -> Bool {
  var i = 0;
  while i < v.len() {
    let e: Int = v[i];
    if e == x { return true; }
    i = i + 1;
  }
  return false;
}

fn _merge_values(dst: &mut Vec[Int], src: &Vec[Int]) {
  var i = 0;
  while i < src.len() {
    let x: Int = src[i];
    if !_has_int(dst, x) { dst.push(x); }
    i = i + 1;
  }
}

// Emit `values` in the allowed range lo..hi, ascending and deduplicated.
fn _canonicalize(values: &Vec[Int], lo: Int, hi: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var x = lo;
  while x <= hi {
    if _has_int(values, x) { out.push(x); }
    x = x + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Field parsing
// ---------------------------------------------------------------------------

// Decimal value of s[start, end); Err on an empty run or a non-digit.
fn _parse_digits(s: Str, start: Int, end: Int, name: Str, seg: Str) -> Result[Int, Str] {
  if start >= end {
    return _err_int("cron: invalid value in " + name + " field: " + seg);
  }
  var acc = 0;
  var i = start;
  while i < end {
    let b = string.byte_at(s, i);
    if b < 48 || b > 57 {
      return _err_int("cron: invalid value in " + name + " field: " + seg);
    }
    acc = acc * 10 + (b as Int - 48);
    i = i + 1;
  }
  return _ok_int(acc);
}

// Parse one comma-separated element: * | */n | a | a-b | a-b/n. `a/n` is not
// a supported step form (only `*/n` and `a-b/n`); Err("cron: ...") otherwise.
fn _parse_segment(seg: Str, lo: Int, hi: Int, name: Str) -> Result[Vec[Int], Str] {
  let n = seg.len();
  var step: Int = 1;
  var body_end = n;
  let slash = _find_byte(seg, _CRON_SLASH);
  if slash >= 0 {
    body_end = slash;
    let sr = _parse_digits(seg, slash + 1, n, name, seg);
    match sr {
      Ok(v) => { step = v; },
      Err(e) => { return _err_vec(e); },
    }
    if step < 1 {
      return _err_vec("cron: invalid step in " + name + " field: " + seg);
    }
  }
  if body_end == 0 {
    return _err_vec("cron: invalid " + name + " field: " + seg);
  }
  let body = string.str_slice(seg, 0, body_end);
  if string.byte_at(body, 0) == _CRON_STAR {
    if body.len() != 1 {
      return _err_vec("cron: invalid " + name + " field: " + seg);
    }
    var out = Vec[Int].new();
    var v = lo;
    while v <= hi {
      out.push(v);
      v = v + step;
    }
    return _ok_vec(out);
  }
  let dash = _find_byte(body, _CRON_DASH);
  if dash >= 0 {
    if dash == 0 || dash + 1 >= body.len() {
      return _err_vec("cron: invalid range in " + name + " field: " + seg);
    }
    let ar = _parse_digits(body, 0, dash, name, seg);
    let br = _parse_digits(body, dash + 1, body.len(), name, seg);
    var a: Int = 0;
    var b: Int = 0;
    match ar {
      Ok(v) => { a = v; },
      Err(e) => { return _err_vec(e); },
    }
    match br {
      Ok(v) => { b = v; },
      Err(e) => { return _err_vec(e); },
    }
    if a > b {
      return _err_vec("cron: invalid range in " + name + " field: " + seg);
    }
    if a < lo || a > hi || b < lo || b > hi {
      return _err_vec("cron: out-of-range value in " + name + " field: " + seg);
    }
    var out = Vec[Int].new();
    var v = a;
    while v <= b {
      out.push(v);
      v = v + step;
    }
    return _ok_vec(out);
  }
  if slash >= 0 {
    return _err_vec("cron: invalid step in " + name + " field: " + seg);
  }
  let vr = _parse_digits(body, 0, body.len(), name, seg);
  var value: Int = 0;
  match vr {
    Ok(v) => { value = v; },
    Err(e) => { return _err_vec(e); },
  }
  if value < lo || value > hi {
    return _err_vec("cron: out-of-range value in " + name + " field: " + seg);
  }
  var out = Vec[Int].new();
  out.push(value);
  return _ok_vec(out);
}

// Parse one comma-separated field into canonical (ascending, deduplicated)
// allowed values.
fn _parse_field(text: Str, lo: Int, hi: Int, name: Str) -> Result[Vec[Int], Str] {
  var collected = Vec[Int].new();
  let n = text.len();
  var i = 0;
  while i <= n {
    var j = i;
    while j < n {
      if string.byte_at(text, j) == _CRON_COMMA { break; }
      j = j + 1;
    }
    if j == i {
      return _err_vec("cron: empty " + name + " field");
    }
    let seg = string.str_slice(text, i, j);
    let sr = _parse_segment(seg, lo, hi, name);
    match sr {
      Ok(vals) => { _merge_values(&mut collected, &vals); },
      Err(e) => { return _err_vec(e); },
    }
    i = j + 1;
  }
  let canon = _canonicalize(&collected, lo, hi);
  return _ok_vec(canon);
}

// Split on ASCII space/tab; runs of whitespace are one separator.
fn _split_fields(expr: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = expr.len();
  var i = 0;
  while i < n {
    while i < n && _is_ws_byte(string.byte_at(expr, i)) { i = i + 1; }
    if i >= n { break; }
    var j = i;
    while j < n && !_is_ws_byte(string.byte_at(expr, j)) { j = j + 1; }
    out.push(string.str_slice(expr, i, j));
    i = j;
  }
  return out;
}

// Struct literal helper: CronSchedule is built here and never through Ok/Err
// (compiler workaround; see the header comment).
fn _make_schedule(minutes: Vec[Int], hours: Vec[Int], days: Vec[Int], months: Vec[Int], weekdays: Vec[Int]) -> CronSchedule {
  return CronSchedule{
    minutes: minutes;
    hours: hours;
    days: days;
    months: months;
    weekdays: weekdays;
  };
}

// ---------------------------------------------------------------------------
// Civil-date math (pure, from epoch days; Howard Hinnant's algorithm)
// ---------------------------------------------------------------------------

// Floor division; callers pass b > 0.
fn _floor_div(a: Int, b: Int) -> Int {
  var q = a / b;
  let r = a - q * b;
  if r < 0 { q = q - 1; }
  return q;
}

fn _floor_mod(a: Int, b: Int) -> Int {
  let q = _floor_div(a, b);
  return a - q * b;
}

// Civil (proleptic Gregorian) year, month and day of a day number counted from
// 1970-01-01. Always Some; Option keeps the 3-tuple lowering explicit (no
// struct return). Valid for day numbers >= -719468 (year 0 and later).
fn _civil_ymd(days_since_epoch: Int) -> Option[(Int, Int, Int)] {
  let z = days_since_epoch + 719468;
  let era = _floor_div(z, 146097);
  let doe = z - era * 146097;
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  var y = yoe + era * 400;
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  let mp = (5 * doy + 2) / 153;
  let d = doy - (153 * mp + 2) / 5 + 1;
  var m = mp + 3;
  if mp >= 10 { m = mp - 9; }
  if m <= 2 { y = y + 1; }
  return Some((y, m, d));
}

// Standard cron day rule: with only one of day-of-month / weekday restricted,
// that field decides; with both restricted, either may match (OR); with both
// unrestricted, every day matches.
fn _day_matches(s: &CronSchedule, dom: Int, weekday: Int) -> Bool {
  let dom_restricted = s.days.len() < 31;
  let wd_restricted = s.weekdays.len() < 7;
  if dom_restricted && wd_restricted {
    if _has_int(&s.days, dom) { return true; }
    return _has_int(&s.weekdays, weekday);
  }
  if dom_restricted { return _has_int(&s.days, dom); }
  if wd_restricted { return _has_int(&s.weekdays, weekday); }
  return true;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse a 5-field cron expression: "minute hour day-of-month month weekday".
/// Fields accept `*`, lists (`a,b`), ranges (`a-b`), steps (`*/n`, `a-b/n`)
/// and single values; lists may mix those element forms. Weekdays are 0-6
/// with 0 = Sunday (no 7 synonym). All values are validated against their
/// allowed range and stored sorted ascending, duplicate-free.
/// Params: expr - the whole expression; ASCII space/tab separate fields.
/// Returns: Ok(CronSchedule); Err with a "cron: ..." message for a wrong
/// field count, a malformed list, range, step or value, or an out-of-range
/// value.
/// Complexity: O(len(expr) + 60) (canonicalization scans the allowed range).
pub fn cron_parse(expr: Str) -> Result[CronSchedule, Str] {
  let fields = _split_fields(expr);
  if fields.len() != 5 {
    return _err_sched("cron: expected 5 fields, got " + convert.int_to_string(fields.len()));
  }
  var minutes = Vec[Int].new();
  match _parse_field(fields[0], 0, 59, "minute") {
    Ok(v) => { minutes = v; },
    Err(e) => { return _err_sched(e); },
  }
  var hours = Vec[Int].new();
  match _parse_field(fields[1], 0, 23, "hour") {
    Ok(v) => { hours = v; },
    Err(e) => { return _err_sched(e); },
  }
  var days = Vec[Int].new();
  match _parse_field(fields[2], 1, 31, "day-of-month") {
    Ok(v) => { days = v; },
    Err(e) => { return _err_sched(e); },
  }
  var months = Vec[Int].new();
  match _parse_field(fields[3], 1, 12, "month") {
    Ok(v) => { months = v; },
    Err(e) => { return _err_sched(e); },
  }
  var weekdays = Vec[Int].new();
  match _parse_field(fields[4], 0, 6, "weekday") {
    Ok(v) => { weekdays = v; },
    Err(e) => { return _err_sched(e); },
  }
  return _ok_sched(_make_schedule(minutes, hours, days, months, weekdays));
}

// One field rendered canonically: "*" for the full allowed range, else the
// ascending comma-joined values.
fn _field_text(v: &Vec[Int], lo: Int, hi: Int) -> Str {
  if v.len() == hi - lo + 1 {
    return "*";
  }
  var out = "";
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(x);
    i = i + 1;
  }
  return out;
}

/// Canonical text form: "minute hour day-of-month month weekday" with each
/// field rendered as "*" (unrestricted) or its ascending comma-joined values.
/// Params: s - the schedule to describe.
/// Returns: the canonical expression; cron_parse round-trips it to an
/// equivalent schedule.
/// Complexity: O(60).
pub fn cron_describe(s: &CronSchedule) -> Str {
  return _field_text(&s.minutes, 0, 59) + " " + _field_text(&s.hours, 0, 23) + " " + _field_text(&s.days, 1, 31) + " " + _field_text(&s.months, 1, 12) + " " + _field_text(&s.weekdays, 0, 6);
}

/// True when the UTC minute containing `epoch_secs` satisfies the schedule.
/// Seconds within the minute are ignored (minute granularity): a timestamp of
/// 00:00:30 matches a schedule whose minute is 0. The UTC weekday is derived
/// as (days_since_epoch + 4) mod 7 (1970-01-01 was Thursday = 4) and the
/// day-of-month / weekday OR rule is documented in SPEC.md section 3.
/// Params: s - the schedule; epoch_secs - Unix seconds (UTC; may be negative).
/// Returns: true on a match.
/// Complexity: O(31 + |fields|).
pub fn cron_matches(s: &CronSchedule, epoch_secs: Int) -> Bool {
  let minute_index = _floor_div(epoch_secs, _SECS_PER_MIN);
  let days = _floor_div(minute_index, _MINS_PER_DAY);
  let minute_of_day = minute_index - days * _MINS_PER_DAY;
  let hour = minute_of_day / _MINS_PER_HOUR;
  let minute = minute_of_day - hour * _MINS_PER_HOUR;
  if !_has_int(&s.minutes, minute) { return false; }
  if !_has_int(&s.hours, hour) { return false; }
  var month: Int = 0;
  var dom: Int = 0;
  match _civil_ymd(days) {
    Some((_, mm, dd)) => { month = mm; dom = dd; },
    None => { return false; },
  }
  if !_has_int(&s.months, month) { return false; }
  return _day_matches(s, dom, _floor_mod(days + 4, 7));
}

/// Earliest matching whole-minute timestamp strictly greater than
/// `from_secs` (UTC). Days are scanned up to 4 years (1461 days) ahead;
/// hours and minutes are tried in ascending order inside each matching day.
/// Params: s - the schedule; from_secs - Unix seconds (UTC; may be negative).
/// Returns: Ok(t) with t > from_secs and t mod 60 == 0; Err("cron: no match
/// within 4 years") when no day matches in the scan window (e.g. "0 0 30 2 *").
/// Complexity: O(1461 * |hours| * |minutes|).
pub fn cron_next(s: &CronSchedule, from_secs: Int) -> Result[Int, Str] {
  let start_day = _floor_div(_floor_div(from_secs, _SECS_PER_MIN) + 1, _MINS_PER_DAY);
  let last_day = start_day + _DAYS_SCAN_LIMIT;
  var d = start_day;
  while d <= last_day {
    var month: Int = 0;
    var dom: Int = 0;
    match _civil_ymd(d) {
      Some((_, mm, dd)) => { month = mm; dom = dd; },
      None => { month = 0; dom = 0; },
    }
    let weekday = _floor_mod(d + 4, 7);
    if _has_int(&s.months, month) && _day_matches(s, dom, weekday) {
      var hi = 0;
      while hi < s.hours.len() {
        let hour: Int = s.hours[hi];
        var mi = 0;
        while mi < s.minutes.len() {
          let minute: Int = s.minutes[mi];
          let t = d * _SECS_PER_DAY + hour * _SECS_PER_HOUR + minute * _SECS_PER_MIN;
          if t > from_secs {
            return _ok_int(t);
          }
          mi = mi + 1;
        }
        hi = hi + 1;
      }
    }
    d = d + 1;
  }
  return _err_int("cron: no match within 4 years");
}

/// Convenience composition: parse `expr`, then cron_next from `from_secs`.
/// Params: expr - the cron expression; from_secs - Unix seconds (UTC).
/// Returns: the cron_next result; parse errors are returned unchanged.
/// Complexity: as cron_parse plus cron_next.
pub fn cron_parse_next(expr: Str, from_secs: Int) -> Result[Int, Str] {
  let parsed = cron_parse(expr);
  match parsed {
    Ok(s) => { return cron_next(&s, from_secs); },
    Err(e) => { return _err_int(e); },
  }
  return _err_int("cron: parse failed");
}
