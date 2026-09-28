// XIOM -- xiom.l10n.time conformance tests (24 checks).
// Port task: prove the pure-XIOM xiom.l10n.time module against its documented
// time-of-day, 12h/24h, pattern, day-period and timezone-offset contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module l10n_time_tests
use xiom.io; use xiom.test; use xiom.l10n.time;
use xiom.string; use xiom.string.compare; use xiom.convert;

// All Str equality goes through str_compare (BUG 17 family: `==` on Str
// values read from vectors lowers to pointer comparison); every string check
// below is routed through streq, and every struct field read is bound to a
// typed local before use.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --- Fixture builders -------------------------------------------------------

fn time_of(h: Int, m: Int, s: Int) -> TimeOfDay {
  return TimeOfDay{ hour: h; minute: m; second: s };
}

fn off_of(sign: Int, h: Int, m: Int) -> TimeOffset {
  return TimeOffset{ sign: sign; hours: h; minutes: m };
}

// --- Result inspectors (no inline Ok/Err construction anywhere) -------------

fn parse_is(text: Str, am: Str, pm: Str, h: Int, m: Int, s: Int) -> Bool {
  let r = l10n_time_parse(text, am, pm);
  match r {
    Ok(t) => {
      let th: Int = t.hour;
      let tm: Int = t.minute;
      let ts: Int = t.second;
      return th == h && tm == m && ts == s;
    },
    Err(e) => { return false; },
  }
  return false;
}

fn parse_err_is(text: Str, am: Str, pm: Str, want: Str) -> Bool {
  let r = l10n_time_parse(text, am, pm);
  match r {
    Ok(t) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn ctor_is(h: Int, m: Int, s: Int, wh: Int, wm: Int, ws: Int) -> Bool {
  let r = l10n_time_of_day(h, m, s);
  match r {
    Ok(t) => {
      let th: Int = t.hour;
      let tm: Int = t.minute;
      let ts: Int = t.second;
      return th == wh && tm == wm && ts == ws;
    },
    Err(e) => { return false; },
  }
  return false;
}

fn ctor_err_is(h: Int, m: Int, s: Int, want: Str) -> Bool {
  let r = l10n_time_of_day(h, m, s);
  match r {
    Ok(t) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn h12_is(hour24: Int, want: Int) -> Bool {
  let r = l10n_hour_24_to_12(hour24);
  match r {
    Ok(v) => { return v == want; },
    Err(e) => { return false; },
  }
  return false;
}

fn h12_err_is(hour24: Int, want: Str) -> Bool {
  let r = l10n_hour_24_to_12(hour24);
  match r {
    Ok(v) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn h24_is(hour12: Int, is_pm: Bool, want: Int) -> Bool {
  let r = l10n_hour_12_to_24(hour12, is_pm);
  match r {
    Ok(v) => { return v == want; },
    Err(e) => { return false; },
  }
  return false;
}

fn h24_err_is(hour12: Int, is_pm: Bool, want: Str) -> Bool {
  let r = l10n_hour_12_to_24(hour12, is_pm);
  match r {
    Ok(v) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn period_is(hour: Int, am: Str, pm: Str, want: Str) -> Bool {
  let r = l10n_hour_period(hour, am, pm);
  match r {
    Ok(s) => {
      let got: Str = s;
      return streq(got, want);
    },
    Err(e) => { return false; },
  }
  return false;
}

fn period_err_is(hour: Int, am: Str, pm: Str, want: Str) -> Bool {
  let r = l10n_hour_period(hour, am, pm);
  match r {
    Ok(s) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn label_is(hour: Int, am: Str, pm: Str, want: Str) -> Bool {
  let r = l10n_hour_12_label(hour, am, pm);
  match r {
    Ok(s) => {
      let got: Str = s;
      return streq(got, want);
    },
    Err(e) => { return false; },
  }
  return false;
}

fn label_err_is(hour: Int, am: Str, pm: Str, want: Str) -> Bool {
  let r = l10n_hour_12_label(hour, am, pm);
  match r {
    Ok(s) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn fmt_is(h: Int, m: Int, s: Int, pattern: Str, am: Str, pm: Str, want: Str) -> Bool {
  let t = time_of(h, m, s);
  let r = l10n_time_format(t, pattern, am, pm);
  match r {
    Ok(out) => {
      let got: Str = out;
      return streq(got, want);
    },
    Err(e) => { return false; },
  }
  return false;
}

fn fmt_err_is(h: Int, m: Int, s: Int, pattern: Str, am: Str, pm: Str, want: Str) -> Bool {
  let t = time_of(h, m, s);
  let r = l10n_time_format(t, pattern, am, pm);
  match r {
    Ok(out) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn day_is(hour: Int, mstart: Int, astart: Int, estart: Int, nstart: Int, want: Str) -> Bool {
  let r = l10n_day_period(hour, mstart, astart, estart, nstart);
  match r {
    Ok(s) => {
      let got: Str = s;
      return streq(got, want);
    },
    Err(e) => { return false; },
  }
  return false;
}

fn day_err_is(hour: Int, mstart: Int, astart: Int, estart: Int, nstart: Int, want: Str) -> Bool {
  let r = l10n_day_period(hour, mstart, astart, estart, nstart);
  match r {
    Ok(s) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn off_parse_is(text: Str, sign: Int, hours: Int, minutes: Int) -> Bool {
  let r = l10n_offset_parse(text);
  match r {
    Ok(o) => {
      let os: Int = o.sign;
      let oh: Int = o.hours;
      let om: Int = o.minutes;
      return os == sign && oh == hours && om == minutes;
    },
    Err(e) => { return false; },
  }
  return false;
}

fn off_parse_err_is(text: Str, want: Str) -> Bool {
  let r = l10n_offset_parse(text);
  match r {
    Ok(o) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn off_fmt_is(sign: Int, hours: Int, minutes: Int, want: Str) -> Bool {
  let o = off_of(sign, hours, minutes);
  let got = l10n_offset_format(o);
  return streq(got, want);
}

fn off_min_is(text: Str, want: Int) -> Bool {
  let r = l10n_offset_parse(text);
  match r {
    Ok(o) => { return l10n_offset_total_minutes(o) == want; },
    Err(e) => { return false; },
  }
  return false;
}

fn from_min_is(total: Int, sign: Int, hours: Int, minutes: Int) -> Bool {
  let r = l10n_offset_from_minutes(total);
  match r {
    Ok(o) => {
      let os: Int = o.sign;
      let oh: Int = o.hours;
      let om: Int = o.minutes;
      return os == sign && oh == hours && om == minutes;
    },
    Err(e) => { return false; },
  }
  return false;
}

fn from_min_err_is(total: Int, want: Str) -> Bool {
  let r = l10n_offset_from_minutes(total);
  match r {
    Ok(o) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn new_is(sign: Int, hours: Int, minutes: Int, ws: Int, wh: Int, wm: Int) -> Bool {
  let r = l10n_offset_new(sign, hours, minutes);
  match r {
    Ok(o) => {
      let os: Int = o.sign;
      let oh: Int = o.hours;
      let om: Int = o.minutes;
      return os == ws && oh == wh && om == wm;
    },
    Err(e) => { return false; },
  }
  return false;
}

fn new_err_is(sign: Int, hours: Int, minutes: Int, want: Str) -> Bool {
  let r = l10n_offset_new(sign, hours, minutes);
  match r {
    Ok(o) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn apply_is(h: Int, m: Int, s: Int, osign: Int, oh: Int, om: Int, wh: Int, wm: Int, ws: Int) -> Bool {
  let t = time_of(h, m, s);
  let o = off_of(osign, oh, om);
  let r = l10n_time_apply_offset(t, o);
  match r {
    Ok(v) => {
      let vh: Int = v.hour;
      let vm: Int = v.minute;
      let vs: Int = v.second;
      return vh == wh && vm == wm && vs == ws;
    },
    Err(e) => { return false; },
  }
  return false;
}

fn apply_err_is(h: Int, m: Int, s: Int, osign: Int, oh: Int, om: Int, want: Str) -> Bool {
  let t = time_of(h, m, s);
  let o = off_of(osign, oh, om);
  let r = l10n_time_apply_offset(t, o);
  match r {
    Ok(v) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

fn remove_is(h: Int, m: Int, s: Int, osign: Int, oh: Int, om: Int, wh: Int, wm: Int, ws: Int) -> Bool {
  let t = time_of(h, m, s);
  let o = off_of(osign, oh, om);
  let r = l10n_time_remove_offset(t, o);
  match r {
    Ok(v) => {
      let vh: Int = v.hour;
      let vm: Int = v.minute;
      let vs: Int = v.second;
      return vh == wh && vm == wm && vs == ws;
    },
    Err(e) => { return false; },
  }
  return false;
}

fn remove_err_is(h: Int, m: Int, s: Int, osign: Int, oh: Int, om: Int, want: Str) -> Bool {
  let t = time_of(h, m, s);
  let o = off_of(osign, oh, om);
  let r = l10n_time_remove_offset(t, o);
  match r {
    Ok(v) => { return false; },
    Err(e) => {
      let msg: Str = e;
      return streq(msg, want);
    },
  }
  return false;
}

// --- Tests ------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = l10n_time_is_valid(0, 0, 0);
  if !l10n_time_is_valid(23, 59, 59) { ok = false; }
  if !l10n_time_is_valid(12, 30, 9) { ok = false; }
  if l10n_time_is_valid(24, 0, 0) { ok = false; }
  if l10n_time_is_valid(0, 60, 0) { ok = false; }
  if l10n_time_is_valid(0, 0, 60) { ok = false; }
  if l10n_time_is_valid(0 - 1, 0, 0) { ok = false; }
  return assert(ok, "validation: 00:00:00 and 23:59:59 are valid, out-of-range fields are not");
}

fn t2() -> TestResult {
  var ok = ctor_is(7, 8, 9, 7, 8, 9);
  if !ctor_is(0, 0, 0, 0, 0, 0) { ok = false; }
  if !ctor_is(23, 59, 59, 23, 59, 59) { ok = false; }
  if !ctor_err_is(24, 0, 0, "l10n.time: hour out of range") { ok = false; }
  if !ctor_err_is(0 - 1, 0, 0, "l10n.time: hour out of range") { ok = false; }
  if !ctor_err_is(0, 60, 0, "l10n.time: minute out of range") { ok = false; }
  if !ctor_err_is(0, 0, 60, "l10n.time: second out of range") { ok = false; }
  return assert(ok, "constructor: valid components build a TimeOfDay, invalid ones carry a catalog error");
}

fn t3() -> TestResult {
  var ok = h12_is(0, 12);
  if !h12_is(1, 1) { ok = false; }
  if !h12_is(11, 11) { ok = false; }
  if !h12_is(12, 12) { ok = false; }
  if !h12_is(13, 1) { ok = false; }
  if !h12_is(23, 11) { ok = false; }
  if !h12_err_is(24, "l10n.time: hour out of range") { ok = false; }
  if !h12_err_is(0 - 1, "l10n.time: hour out of range") { ok = false; }
  return assert(ok, "24h -> 12h: 00 and 12 both map to 12, 13 -> 1, 23 -> 11");
}

fn t4() -> TestResult {
  var ok = h24_is(12, false, 0);
  if !h24_is(12, true, 12) { ok = false; }
  if !h24_is(1, true, 13) { ok = false; }
  if !h24_is(1, false, 1) { ok = false; }
  if !h24_is(11, true, 23) { ok = false; }
  if !h24_is(11, false, 11) { ok = false; }
  if !h24_err_is(0, false, "l10n.time: hour out of range") { ok = false; }
  if !h24_err_is(13, true, "l10n.time: hour out of range") { ok = false; }
  return assert(ok, "12h -> 24h: 12 AM = 00 and 12 PM = 12 are the midnight/noon edge rules");
}

fn t5() -> TestResult {
  var ok = period_is(0, "AM", "PM", "AM");
  if !period_is(11, "AM", "PM", "AM") { ok = false; }
  if !period_is(12, "AM", "PM", "PM") { ok = false; }
  if !period_is(23, "AM", "PM", "PM") { ok = false; }
  if !period_is(13, "a.m.", "p.m.", "p.m.") { ok = false; }
  if !period_is(5, "a.m.", "p.m.", "a.m.") { ok = false; }
  if !period_err_is(24, "AM", "PM", "l10n.time: hour out of range") { ok = false; }
  return assert(ok, "period labels: the caller's AM/PM strings are emitted verbatim, hour first validated");
}

fn t6() -> TestResult {
  var ok = label_is(0, "AM", "PM", "12 AM");
  if !label_is(12, "AM", "PM", "12 PM") { ok = false; }
  if !label_is(13, "AM", "PM", "1 PM") { ok = false; }
  if !label_is(9, "AM", "PM", "9 AM") { ok = false; }
  if !label_is(23, "AM", "PM", "11 PM") { ok = false; }
  if !label_err_is(24, "AM", "PM", "l10n.time: hour out of range") { ok = false; }
  var h = 0;
  while h < 24 {
    let face_r = l10n_hour_24_to_12(h);
    match face_r {
      Ok(face) => {
        var period: Str = "PM";
        if h < 12 { period = "AM"; }
        let want: Str = convert.int_to_string(face) + " " + period;
        if !label_is(h, "AM", "PM", want) { ok = false; }
        let full: Str = convert.int_to_string(face) + ":00 " + period;
        let back = l10n_time_parse(full, "AM", "PM");
        match back {
          Ok(t) => {
            let th: Int = t.hour;
            let tm: Int = t.minute;
            if th != h || tm != 0 { ok = false; }
          },
          Err(e) => { ok = false; },
        }
      },
      Err(e) => { ok = false; },
    }
    h = h + 1;
  }
  return assert(ok, "12-hour labels: every hour 0..23 round-trips through its face and label back to 24h");
}

fn t7() -> TestResult {
  var ok = fmt_is(13, 5, 9, "HH:MM:SS", "AM", "PM", "13:05:09");
  if !fmt_is(13, 5, 9, "H:M:S", "AM", "PM", "13:5:9") { ok = false; }
  if !fmt_is(13, 5, 9, "at HH:MM", "AM", "PM", "at 13:05") { ok = false; }
  if !fmt_is(0, 0, 0, "HH:MM:SS", "AM", "PM", "00:00:00") { ok = false; }
  if !fmt_is(23, 59, 59, "HH:MM:SS", "AM", "PM", "23:59:59") { ok = false; }
  if !fmt_is(13, 5, 9, "", "AM", "PM", "") { ok = false; }
  return assert(ok, "24h patterns: HH/H, MM/M and SS/S expand padded and bare, literals pass through");
}

fn t8() -> TestResult {
  var ok = fmt_is(0, 0, 0, "hh:mm:ss A", "AM", "PM", "12:00:00 AM");
  if !fmt_is(13, 5, 9, "h:mm:ss A", "AM", "PM", "1:05:09 PM") { ok = false; }
  if !fmt_is(12, 0, 0, "hh:mm A", "AM", "PM", "12:00 PM") { ok = false; }
  if !fmt_is(11, 59, 59, "h:mm:ss A", "AM", "PM", "11:59:59 AM") { ok = false; }
  if !fmt_is(23, 0, 1, "hh:mm:ssA", "AM", "PM", "11:00:01PM") { ok = false; }
  if !fmt_is(0, 30, 0, "h:mm A", "a.m.", "p.m.", "12:30 a.m.") { ok = false; }
  return assert(ok, "12h patterns: hh/h use the 12-hour face, A emits the caller's label");
}

fn t9() -> TestResult {
  var ok = fmt_is(9, 8, 7, "HH:mm:ss", "AM", "PM", "09:08:07");
  if !fmt_is(9, 8, 7, "hh:MM:SS", "AM", "PM", "09:08:07") { ok = false; }
  if !fmt_is(9, 8, 7, "hh o'clock", "AM", "PM", "09 o'clock") { ok = false; }
  if !fmt_is(9, 8, 7, "[HH]-[mm]", "AM", "PM", "[09]-[08]") { ok = false; }
  if !fmt_is(0, 0, 0, "H:M:S", "AM", "PM", "0:0:0") { ok = false; }
  if !fmt_err_is(24, 0, 0, "HH", "AM", "PM", "l10n.time: invalid time") { ok = false; }
  return assert(ok, "patterns: minute/second tokens work in either case convention, literals and invalid times behave");
}

fn t10() -> TestResult {
  var ok = parse_is("13:45", "AM", "PM", 13, 45, 0);
  if !parse_is("13:45:09", "AM", "PM", 13, 45, 9) { ok = false; }
  if !parse_is("0:05", "AM", "PM", 0, 5, 0) { ok = false; }
  if !parse_is("23:59:59", "AM", "PM", 23, 59, 59) { ok = false; }
  if !parse_is(" 7:30 ", "AM", "PM", 7, 30, 0) { ok = false; }
  if !parse_is("07:08:09", "AM", "PM", 7, 8, 9) { ok = false; }
  if !parse_is("1:2:3", "AM", "PM", 1, 2, 3) { ok = false; }
  return assert(ok, "parse 24h: 1..2 digit fields, optional seconds, surrounding spaces");
}

fn t11() -> TestResult {
  var ok = parse_is("12:30 AM", "AM", "PM", 0, 30, 0);
  if !parse_is("12:30 PM", "AM", "PM", 12, 30, 0) { ok = false; }
  if !parse_is("1:00 PM", "AM", "PM", 13, 0, 0) { ok = false; }
  if !parse_is("1:00PM", "AM", "PM", 13, 0, 0) { ok = false; }
  if !parse_is("11:59:59 PM", "AM", "PM", 23, 59, 59) { ok = false; }
  if !parse_is("12:00:00 AM", "AM", "PM", 0, 0, 0) { ok = false; }
  if !parse_is("12:00 a.m.", "a.m.", "p.m.", 0, 0, 0) { ok = false; }
  return assert(ok, "parse 12h: labels are caller-supplied and 12 AM/12 PM follow the midnight/noon rules");
}

fn t12() -> TestResult {
  var ok = parse_err_is("1:00 pm", "AM", "PM", "l10n.time: unknown label");
  if !parse_err_is("13:00 PM", "AM", "PM", "l10n.time: hour out of range") { ok = false; }
  if !parse_err_is("0:30 AM", "AM", "PM", "l10n.time: hour out of range") { ok = false; }
  if !parse_err_is("12:30 XX", "AM", "PM", "l10n.time: unknown label") { ok = false; }
  if !parse_err_is("12:30:09 extra", "AM", "PM", "l10n.time: unknown label") { ok = false; }
  if !parse_is("1:00", "AM", "PM", 1, 0, 0) { ok = false; }
  return assert(ok, "parse labels: case-sensitive matching, labeled hours 1..12, label-less text stays 24h");
}

fn t13() -> TestResult {
  var ok = parse_err_is("", "AM", "PM", "l10n.time: empty input");
  if !parse_err_is("   ", "AM", "PM", "l10n.time: empty input") { ok = false; }
  if !parse_err_is("abc", "AM", "PM", "l10n.time: bad digit") { ok = false; }
  if !parse_err_is(":30", "AM", "PM", "l10n.time: bad digit") { ok = false; }
  if !parse_err_is("12:", "AM", "PM", "l10n.time: bad digit") { ok = false; }
  if !parse_err_is("12:30:", "AM", "PM", "l10n.time: bad digit") { ok = false; }
  if !parse_err_is("12", "AM", "PM", "l10n.time: expected ':'") { ok = false; }
  if !parse_err_is("12.30", "AM", "PM", "l10n.time: expected ':'") { ok = false; }
  if !parse_err_is("123:00", "AM", "PM", "l10n.time: too many digits") { ok = false; }
  if !parse_err_is("12:345", "AM", "PM", "l10n.time: too many digits") { ok = false; }
  return assert(ok, "parse shape: empty input, missing digits, missing colon and >2-digit fields carry exact errors");
}

fn t14() -> TestResult {
  var ok = parse_err_is("24:00", "AM", "PM", "l10n.time: hour out of range");
  if !parse_err_is("99:00", "AM", "PM", "l10n.time: hour out of range") { ok = false; }
  if !parse_err_is("12:60", "AM", "PM", "l10n.time: minute out of range") { ok = false; }
  if !parse_err_is("12:00:60", "AM", "PM", "l10n.time: second out of range") { ok = false; }
  return assert(ok, "parse ranges: hour > 23, minute > 59 and second > 59 are rejected by name");
}

fn t15() -> TestResult {
  var ok = day_is(4, 5, 12, 17, 21, "night");
  if !day_is(5, 5, 12, 17, 21, "morning") { ok = false; }
  if !day_is(11, 5, 12, 17, 21, "morning") { ok = false; }
  if !day_is(12, 5, 12, 17, 21, "afternoon") { ok = false; }
  if !day_is(16, 5, 12, 17, 21, "afternoon") { ok = false; }
  if !day_is(17, 5, 12, 17, 21, "evening") { ok = false; }
  if !day_is(20, 5, 12, 17, 21, "evening") { ok = false; }
  if !day_is(21, 5, 12, 17, 21, "night") { ok = false; }
  if !day_is(23, 5, 12, 17, 21, "night") { ok = false; }
  if !day_is(0, 5, 12, 17, 21, "night") { ok = false; }
  return assert(ok, "day periods: boundaries are inclusive starts, night wraps past midnight");
}

fn t16() -> TestResult {
  var ok = day_is(0, 0, 6, 12, 18, "morning");
  if !day_is(5, 0, 6, 12, 18, "morning") { ok = false; }
  if !day_is(6, 0, 6, 12, 18, "afternoon") { ok = false; }
  if !day_is(12, 0, 6, 12, 18, "evening") { ok = false; }
  if !day_is(17, 0, 6, 12, 18, "evening") { ok = false; }
  if !day_is(18, 0, 6, 12, 18, "night") { ok = false; }
  if !day_is(23, 0, 6, 12, 18, "night") { ok = false; }
  if !day_err_is(24, 5, 12, 17, 21, "l10n.time: hour out of range") { ok = false; }
  if !day_err_is(12, 24, 12, 17, 21, "l10n.time: boundary out of range") { ok = false; }
  if !day_err_is(12, 5, 5, 17, 21, "l10n.time: boundaries out of order") { ok = false; }
  if !day_err_is(12, 12, 6, 17, 21, "l10n.time: boundaries out of order") { ok = false; }
  return assert(ok, "day periods: custom boundaries classify, invalid boundaries and order are errors");
}

fn t17() -> TestResult {
  var ok = off_parse_is("Z", 1, 0, 0);
  if !off_parse_is("+05:30", 1, 5, 30) { ok = false; }
  if !off_parse_is("-08:00", 0 - 1, 8, 0) { ok = false; }
  if !off_parse_is("+14:00", 1, 14, 0) { ok = false; }
  if !off_parse_is("-12:00", 0 - 1, 12, 0) { ok = false; }
  if !off_parse_is("-00:30", 0 - 1, 0, 30) { ok = false; }
  if !off_parse_is("+00:00", 1, 0, 0) { ok = false; }
  if !off_parse_is("-00:00", 1, 0, 0) { ok = false; }
  return assert(ok, "offset parse: Z, positive, negative and zero forms with canonical zero");
}

fn t18() -> TestResult {
  var ok = off_parse_err_is("", "l10n.time: empty input");
  if !off_parse_err_is("z", "l10n.time: bad offset") { ok = false; }
  if !off_parse_err_is("05:30", "l10n.time: bad offset") { ok = false; }
  if !off_parse_err_is("+5:30", "l10n.time: bad offset") { ok = false; }
  if !off_parse_err_is("+05-30", "l10n.time: bad offset") { ok = false; }
  if !off_parse_err_is("+05:3a", "l10n.time: offset digit") { ok = false; }
  if !off_parse_err_is("+15:00", "l10n.time: offset out of range") { ok = false; }
  if !off_parse_err_is("+13:60", "l10n.time: offset out of range") { ok = false; }
  if !off_parse_err_is("-12:30", "l10n.time: offset out of range") { ok = false; }
  if !off_parse_err_is("+00:99", "l10n.time: offset out of range") { ok = false; }
  return assert(ok, "offset parse errors: shape, digit and range diagnostics are exact");
}

fn t19() -> TestResult {
  var ok = off_fmt_is(1, 0, 0, "Z");
  if !off_fmt_is(1, 5, 30, "+05:30") { ok = false; }
  if !off_fmt_is(0 - 1, 8, 0, "-08:00") { ok = false; }
  if !off_fmt_is(1, 14, 0, "+14:00") { ok = false; }
  if !off_fmt_is(0 - 1, 12, 0, "-12:00") { ok = false; }
  if !off_fmt_is(0 - 1, 0, 30, "-00:30") { ok = false; }
  if !off_fmt_is(0 - 1, 0, 0, "Z") { ok = false; }
  if !off_fmt_is(0, 0, 0, "Z") { ok = false; }
  return assert(ok, "offset format: Z for every zero form, two-digit +HH:MM / -HH:MM otherwise");
}

fn t20() -> TestResult {
  var ok = off_min_is("+05:30", 330);
  if !off_min_is("-08:00", 0 - 480) { ok = false; }
  if !off_min_is("Z", 0) { ok = false; }
  if !off_min_is("-12:00", 0 - 720) { ok = false; }
  if !off_min_is("+14:00", 840) { ok = false; }
  if !from_min_is(330, 1, 5, 30) { ok = false; }
  if !from_min_is(0 - 480, 0 - 1, 8, 0) { ok = false; }
  if !from_min_is(0, 1, 0, 0) { ok = false; }
  if !from_min_is(0 - 30, 0 - 1, 0, 30) { ok = false; }
  if !from_min_is(840, 1, 14, 0) { ok = false; }
  if !from_min_is(0 - 720, 0 - 1, 12, 0) { ok = false; }
  if !from_min_err_is(841, "l10n.time: offset out of range") { ok = false; }
  if !from_min_err_is(0 - 721, "l10n.time: offset out of range") { ok = false; }
  return assert(ok, "offset minutes: signed totals convert both ways at the -12:00/+14:00 edges");
}

fn t21() -> TestResult {
  var ok = new_is(1, 5, 30, 1, 5, 30);
  if !new_is(0 - 1, 8, 0, 0 - 1, 8, 0) { ok = false; }
  if !new_is(0 - 1, 0, 0, 1, 0, 0) { ok = false; }
  if !new_is(1, 14, 0, 1, 14, 0) { ok = false; }
  if !new_err_is(1, 14, 1, "l10n.time: offset out of range") { ok = false; }
  if !new_err_is(0 - 1, 12, 1, "l10n.time: offset out of range") { ok = false; }
  if !new_err_is(0, 1, 0, "l10n.time: bad offset sign") { ok = false; }
  if !new_err_is(1, 24, 0, "l10n.time: offset hour out of range") { ok = false; }
  if !new_err_is(1, 1, 60, "l10n.time: offset minute out of range") { ok = false; }
  return assert(ok, "offset constructor: range is -12:00..+14:00 and zero normalizes to sign +1");
}

fn t22() -> TestResult {
  var ok = apply_is(23, 30, 0, 1, 1, 0, 0, 30, 0);
  if !apply_is(12, 0, 0, 0 - 1, 8, 0, 4, 0, 0) { ok = false; }
  if !apply_is(10, 0, 0, 1, 14, 0, 0, 0, 0) { ok = false; }
  if !apply_is(0, 0, 0, 1, 0, 0, 0, 0, 0) { ok = false; }
  if !apply_is(15, 45, 30, 1, 5, 30, 21, 15, 30) { ok = false; }
  if !apply_err_is(24, 0, 0, 1, 0, 0, "l10n.time: invalid time") { ok = false; }
  if !apply_err_is(12, 0, 0, 1, 15, 0, "l10n.time: offset out of range") { ok = false; }
  return assert(ok, "apply offset: UTC -> local wraps past midnight and validates both operands");
}

fn t23() -> TestResult {
  var ok = remove_is(0, 30, 0, 1, 1, 0, 23, 30, 0);
  if !remove_is(4, 0, 0, 0 - 1, 8, 0, 12, 0, 0) { ok = false; }
  if !remove_is(12, 0, 0, 1, 0, 0, 12, 0, 0) { ok = false; }
  if !remove_err_is(12, 0, 0, 1, 15, 0, "l10n.time: offset out of range") { ok = false; }
  if !remove_err_is(0, 0, 60, 1, 0, 0, "l10n.time: invalid time") { ok = false; }
  return assert(ok, "remove offset: local -> UTC wraps backwards, mirroring apply");
}

fn h12_roundtrip() -> Bool {
  var h = 0;
  while h < 24 {
    let r = l10n_hour_24_to_12(h);
    match r {
      Ok(v) => {
        let back = l10n_hour_12_to_24(v, h >= 12);
        match back {
          Ok(b) => { if b != h { return false; } },
          Err(e) => { return false; },
        }
      },
      Err(e) => { return false; },
    }
    h = h + 1;
  }
  return true;
}

fn apply_remove_roundtrip() -> Bool {
  var h = 0;
  while h < 24 {
    let t = time_of(h, 17, 42);
    let o = off_of(1, 5, 30);
    let a = l10n_time_apply_offset(t, o);
    match a {
      Ok(local) => {
        let b = l10n_time_remove_offset(local, o);
        match b {
          Ok(utc) => {
            let same = l10n_time_equals(utc, t);
            if !same { return false; }
          },
          Err(e) => { return false; },
        }
      },
      Err(e) => { return false; },
    }
    h = h + 1;
  }
  return true;
}

fn t24() -> TestResult {
  var ok = h12_roundtrip();
  if !apply_remove_roundtrip() { ok = false; }
  let p1 = l10n_time_parse("11:59:59 PM", "AM", "PM");
  match p1 {
    Ok(t1) => {
      let f1 = l10n_time_format(t1, "HH:MM:SS", "AM", "PM");
      match f1 {
        Ok(s1) => {
          let text1: Str = s1;
          if !streq(text1, "23:59:59") { ok = false; }
        },
        Err(e) => { ok = false; },
      }
    },
    Err(e) => { ok = false; },
  }
  let p2 = l10n_time_parse("13:05", "AM", "PM");
  match p2 {
    Ok(t2) => {
      let f2 = l10n_time_format(t2, "hh:mm:ss A", "AM", "PM");
      match f2 {
        Ok(s2) => {
          let text2: Str = s2;
          if !streq(text2, "01:05:00 PM") { ok = false; }
          let p3 = l10n_time_parse(text2, "AM", "PM");
          match p3 {
            Ok(t3) => {
              if !l10n_time_equals(t3, t2) { ok = false; }
            },
            Err(e) => { ok = false; },
          }
        },
        Err(e) => { ok = false; },
      }
    },
    Err(e) => { ok = false; },
  }
  return assert(ok, "round-trips: 12h face, offset apply/remove and parse -> format -> parse are exact");
}

fn main() -> Int {
  io.println("=== xiom.l10n.time conformance tests ===");
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
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.l10n.time: all tests passed");
  } else {
    io.println("xiom.l10n.time: tests failed");
  }
  return failed;
}
