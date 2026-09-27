// XIOM -- xiom.logging conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.logging module against its SPEC.md:
// the PRI field and facility/severity tables, RFC 3164 parsing (month
// table, day padding, TAG/pid, content, consumed walk), RFC 5424 parsing
// (NILVALUEs, RFC 3339 timestamp fields, structured data with escapes and
// byte-exact spans, BOM handling), format auto-detection, the error catalog
// with byte offsets, and the accessors.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below (fields, codes, error messages, spans) is routed
// through streq instead of `==`.
//
// The test harness calls t1() ... t22() directly from main; Vec[fn] indexed
// dispatch is not used (it miscompiles on XIOM v0.61.3).

module logging_tests
use xiom.io; use xiom.test; use xiom.logging;
use xiom.string; use xiom.string.builder; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn fill(ch: UInt8, n: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < n {
    sb.push(ch);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

fn a_run(n: Int) -> Str {
  return fill(97u8, n);
}

fn utf8_bom() -> Str {
  var sb = Vec[UInt8].new();
  sb.push(239u8);
  sb.push(187u8);
  sb.push(191u8);
  return builder.sb_to_str(&sb);
}

fn err3164(text: Str, want: Str) -> Bool {
  let r = log3164_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn err5424(text: Str, want: Str) -> Bool {
  let r = log5424_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn errts(text: Str, want: Str) -> Bool {
  let r = log5424_timestamp_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn okint(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

fn errint(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// Month field of a 3164 message built around `name`, or -1 on a parse error.
fn month_of(name: Str) -> Int {
  let r = log3164_parse("<13>" + name + "  1 00:00:00 h t:x");
  match r {
    Ok(m) => { return m.month; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn day_of(text: Str) -> Int {
  let r = log3164_parse(text);
  match r {
    Ok(m) => { return m.day; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn content_of(text: Str) -> Str {
  let r = log3164_parse(text);
  match r {
    Ok(m) => { return m.content; },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn content_at_of(text: Str) -> Int {
  let r = log3164_parse(text);
  match r {
    Ok(m) => { return m.content_at; },
    Err(_) => { return -1; },
  }
  return -1;
}

// Detect the format and parse with the matching parser.
fn dispatch_ok(text: Str) -> Bool {
  let fmt = log_detect(text);
  if streq(fmt, "rfc3164") {
    return log3164_ok(text);
  }
  if streq(fmt, "rfc5424") {
    return log5424_ok(text);
  }
  return false;
}

fn t1() -> TestResult {
  var ok = okint(log_pri_make(0, 0), 0);
  if !okint(log_pri_make(0, 7), 7) { ok = false; }
  if !okint(log_pri_make(1, 0), 8) { ok = false; }
  if !okint(log_pri_make(23, 7), 191) { ok = false; }
  if !okint(log_pri_make(9, 4), 76) { ok = false; }
  if !errint(log_pri_make(24, 0), "logging: facility out of range: 24") { ok = false; }
  if !errint(log_pri_make(-1, 0), "logging: facility out of range: -1") { ok = false; }
  if !errint(log_pri_make(0, 8), "logging: severity out of range: 8") { ok = false; }
  if !errint(log_pri_make(0, -1), "logging: severity out of range: -1") { ok = false; }
  if !log_pri_valid(0) { ok = false; }
  if !log_pri_valid(191) { ok = false; }
  if log_pri_valid(192) { ok = false; }
  if log_pri_valid(-1) { ok = false; }
  if log_pri_facility(191) != 23 { ok = false; }
  if log_pri_severity(191) != 7 { ok = false; }
  if log_pri_facility(192) != -1 { ok = false; }
  if log_pri_severity(-1) != -1 { ok = false; }
  return assert(ok, "PRI construction and decode bounds (0..191)");
}

fn t2() -> TestResult {
  var ok = log3164_ok("<0>Jan  1 00:00:00 h t:x");
  let a = log3164_parse("<0>Jan  1 00:00:00 h t:x");
  match a {
    Ok(m) => {
      if log3164_pri(&m) != 0 { ok = false; }
      if log3164_facility(&m) != 0 { ok = false; }
      if log3164_severity(&m) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = log3164_parse("<191>Jan  1 00:00:00 h t:x");
  match b {
    Ok(m2) => {
      if log3164_pri(&m2) != 191 { ok = false; }
      if log3164_facility(&m2) != 23 { ok = false; }
      if log3164_severity(&m2) != 7 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !err3164("<192>Jan  1 00:00:00 h t:x", "logging: PRI out of range at 1") { ok = false; }
  if !err3164("<999>Jan  1 00:00:00 h t:x", "logging: PRI out of range at 1") { ok = false; }
  if !err3164("192>Jan  1 00:00:00 h t:x", "logging: missing PRI at 0") { ok = false; }
  if !err3164("", "logging: missing PRI at 0") { ok = false; }
  if !err3164("<>Jan  1 00:00:00 h t:x", "logging: bad PRI at 1") { ok = false; }
  if !err3164("<1a>Jan  1 00:00:00 h t:x", "logging: bad PRI at 2") { ok = false; }
  if !err3164("<1234>Jan  1 00:00:00 h t:x", "logging: bad PRI at 4") { ok = false; }
  if !err3164("<191", "logging: bad PRI at 4") { ok = false; }
  return assert(ok, "PRI parse boundaries 0/191/192 and malformed PRI");
}

fn t3() -> TestResult {
  var ok = streq(log_facility_name(0), "kern");
  if !streq(log_facility_name(1), "user") { ok = false; }
  if !streq(log_facility_name(2), "mail") { ok = false; }
  if !streq(log_facility_name(3), "daemon") { ok = false; }
  if !streq(log_facility_name(4), "auth") { ok = false; }
  if !streq(log_facility_name(5), "syslog") { ok = false; }
  if !streq(log_facility_name(6), "lpr") { ok = false; }
  if !streq(log_facility_name(7), "news") { ok = false; }
  if !streq(log_facility_name(8), "uucp") { ok = false; }
  if !streq(log_facility_name(9), "cron") { ok = false; }
  if !streq(log_facility_name(10), "authpriv") { ok = false; }
  if !streq(log_facility_name(11), "ftp") { ok = false; }
  if !streq(log_facility_name(12), "ntp") { ok = false; }
  if !streq(log_facility_name(13), "audit") { ok = false; }
  if !streq(log_facility_name(14), "alert") { ok = false; }
  if !streq(log_facility_name(15), "clock") { ok = false; }
  if !streq(log_facility_name(16), "local0") { ok = false; }
  if !streq(log_facility_name(23), "local7") { ok = false; }
  if !streq(log_facility_name(24), "") { ok = false; }
  if !streq(log_facility_name(-1), "") { ok = false; }
  if !streq(log_severity_name(0), "emerg") { ok = false; }
  if !streq(log_severity_name(1), "alert") { ok = false; }
  if !streq(log_severity_name(2), "crit") { ok = false; }
  if !streq(log_severity_name(3), "err") { ok = false; }
  if !streq(log_severity_name(4), "warning") { ok = false; }
  if !streq(log_severity_name(5), "notice") { ok = false; }
  if !streq(log_severity_name(6), "info") { ok = false; }
  if !streq(log_severity_name(7), "debug") { ok = false; }
  if !streq(log_severity_name(8), "") { ok = false; }
  if !okint(log_facility_code("local0"), 16) { ok = false; }
  if !okint(log_facility_code("clock"), 15) { ok = false; }
  if !errint(log_facility_code("LOCAL0"), "logging: unknown facility: LOCAL0") { ok = false; }
  if !errint(log_facility_code(""), "logging: unknown facility: ") { ok = false; }
  if !okint(log_severity_code("debug"), 7) { ok = false; }
  if !errint(log_severity_code("Debug"), "logging: unknown severity: Debug") { ok = false; }
  return assert(ok, "facility (0..23) and severity (0..7) name tables");
}

fn t4() -> TestResult {
  let text = "<34>Oct 11 22:14:15 mymachine su[123]: 'su root' failed";
  let r = log3164_parse(text);
  var ok = false;
  match r {
    Ok(m) => {
      ok = log3164_pri(&m) == 34;
      if log3164_facility(&m) != 4 { ok = false; }
      if log3164_severity(&m) != 2 { ok = false; }
      if !streq(log3164_timestamp(&m), "Oct 11 22:14:15") { ok = false; }
      if log3164_month(&m) != 10 { ok = false; }
      if log3164_day(&m) != 11 { ok = false; }
      if log3164_hour(&m) != 22 { ok = false; }
      if log3164_minute(&m) != 14 { ok = false; }
      if log3164_second(&m) != 15 { ok = false; }
      if !streq(log3164_hostname(&m), "mymachine") { ok = false; }
      if !streq(log3164_tag(&m), "su") { ok = false; }
      if !streq(log3164_pid(&m), "123") { ok = false; }
      if !log3164_has_pid(&m) { ok = false; }
      if !log3164_has_content(&m) { ok = false; }
      if !streq(log3164_content(&m), "'su root' failed") { ok = false; }
      if log3164_consumed(&m) != 55 { ok = false; }
      if m.ts_at != 4 { ok = false; }
      if m.host_at != 20 { ok = false; }
      if m.tag_at != 30 { ok = false; }
      if m.content_at != 39 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "3164 basic message: fields, offsets, consumed count");
}

fn t5() -> TestResult {
  let a = "<13>Aug  1 12:00:00 host tag:";
  var ok = day_of(a) == 1;
  let b = log3164_parse(a);
  match b {
    Ok(m) => {
      if m.has_content { ok = false; }
      if !streq(m.content, "") { ok = false; }
      if m.consumed != 29 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !streq(content_of("<13>Aug  1 12:00:00 host tag:hello"), "hello") { ok = false; }
  if !streq(content_of("<13>Aug  1 12:00:00 host tag: x"), "x") { ok = false; }
  if !streq(content_of("<13>Aug  1 12:00:00 host tag:  x"), " x") { ok = false; }
  if content_at_of("<13>Aug  1 12:00:00 host tag: x") != 30 { ok = false; }
  if content_at_of("<13>Aug  1 12:00:00 host tag:  x") != 30 { ok = false; }
  if day_of("<13>Aug 12 12:00:00 host tag:x") != 12 { ok = false; }
  if day_of("<13>Aug 01 12:00:00 host tag:x") != 1 { ok = false; }
  return assert(ok, "3164 day padding and content variants");
}

fn t6() -> TestResult {
  var ok = month_of("Jan") == 1;
  if month_of("Feb") != 2 { ok = false; }
  if month_of("Mar") != 3 { ok = false; }
  if month_of("Apr") != 4 { ok = false; }
  if month_of("May") != 5 { ok = false; }
  if month_of("Jun") != 6 { ok = false; }
  if month_of("Jul") != 7 { ok = false; }
  if month_of("Aug") != 8 { ok = false; }
  if month_of("Sep") != 9 { ok = false; }
  if month_of("Oct") != 10 { ok = false; }
  if month_of("Nov") != 11 { ok = false; }
  if month_of("Dec") != 12 { ok = false; }
  if !err3164("<13>Xxx  1 00:00:00 h t:x", "logging: bad TIMESTAMP at 4") { ok = false; }
  if !err3164("<13>oct  1 00:00:00 h t:x", "logging: bad TIMESTAMP at 4") { ok = false; }
  if !err3164("<13>Oct  0 00:00:00 h t:x", "logging: bad TIMESTAMP at 8") { ok = false; }
  if !err3164("<13>Oct 32 00:00:00 h t:x", "logging: bad TIMESTAMP at 8") { ok = false; }
  if !err3164("<13>Oct 11 24:00:00 h t:x", "logging: bad TIMESTAMP at 11") { ok = false; }
  if !err3164("<13>Oct 11 22:60:00 h t:x", "logging: bad TIMESTAMP at 14") { ok = false; }
  if !err3164("<13>Oct 11 22:14:60 h t:x", "logging: bad TIMESTAMP at 17") { ok = false; }
  if !err3164("<13>Oct 11 22-14:15 h t:x", "logging: bad TIMESTAMP at 13") { ok = false; }
  if !err3164("<13>Oct 11 2a:14:15 h t:x", "logging: bad TIMESTAMP at 11") { ok = false; }
  if !err3164("<13>Oct 11 22:14", "logging: bad TIMESTAMP at 16") { ok = false; }
  return assert(ok, "3164 month table and malformed timestamps");
}

fn t7() -> TestResult {
  var ok = err3164("<13>Aug  1 12:00:00 h " + a_run(33) + ":x", "logging: TAG too long at 22");
  if !err3164("<13>Aug  1 12:00:00 h sys-temd:x", "logging: bad TAG at 25") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 h t[a]:x", "logging: bad pid at 24") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 h t[12345678901]:x", "logging: bad pid at 24") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 h t[12:x", "logging: bad pid at 26") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 h t[]:x", "logging: bad pid at 24") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 h tag hello", "logging: bad TAG at 25") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 hh", "logging: missing TAG at 22") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 h  t:x", "logging: bad TAG at 22") { ok = false; }
  let a = log3164_parse("<13>Aug  1 12:00:00 h T9:x");
  match a {
    Ok(m) => {
      if !streq(m.tag, "T9") { ok = false; }
      if !streq(m.content, "x") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = log3164_parse("<13>Aug  1 12:00:00 h " + a_run(32) + ":x");
  match b {
    Ok(m2) => {
      if m2.tag.len() != 32 { ok = false; }
      if !streq(m2.pid, "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = log3164_parse("<13>Aug  1 12:00:00 h t[0]:x");
  match c {
    Ok(m3) => {
      if !streq(m3.pid, "0") { ok = false; }
      if !m3.has_pid { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "3164 TAG (alnum, 32 max) and optional [pid]");
}

fn t8() -> TestResult {
  let long_host = a_run(255);
  var ok = log3164_ok("<13>Aug  1 12:00:00 " + long_host + " t:x");
  if !err3164("<13>Aug  1 12:00:00 " + a_run(256) + " t:x", "logging: HOSTNAME too long at 20") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 " + fill(200u8, 3) + " t:x", "logging: bad HOSTNAME at 20") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00 ", "logging: missing HOSTNAME at 20") { ok = false; }
  if !err3164("<13>Aug  1 12:00:00", "logging: missing HOSTNAME at 19") { ok = false; }
  return assert(ok, "3164 hostname limits and malformed headers");
}

fn t9() -> TestResult {
  let buf = "<13>Aug  1 12:00:00 h1 t1:x\n<14>Aug  2 13:00:00 h2 t2:y\n";
  let r1 = log3164_parse(buf);
  var ok = false;
  match r1 {
    Ok(m) => {
      ok = m.consumed == 27;
      if !streq(m.content, "x") { ok = false; }
      let start = m.consumed + 1;
      let rest = string.str_slice(buf, start, buf.len());
      let r2 = log3164_parse(rest);
      match r2 {
        Ok(m2) => {
          if log3164_facility(&m2) != 1 { ok = false; }
          if log3164_severity(&m2) != 6 { ok = false; }
          if !streq(m2.hostname, "h2") { ok = false; }
          if !streq(m2.tag, "t2") { ok = false; }
          if !streq(m2.content, "y") { ok = false; }
          if m2.consumed != 27 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let crlf = "<13>Aug  1 12:00:00 h t:x\r\n";
  let r3 = log3164_parse(crlf);
  match r3 {
    Ok(m3) => {
      if m3.consumed != 25 { ok = false; }
      if !streq(m3.content, "x") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "3164 buffer walk with consumed counts and CRLF");
}

fn t10() -> TestResult {
  var ok = streq(log_detect("<34>Oct 11 22:14:15 h t:x"), "rfc3164");
  if !streq(log_detect("<34>1 - - - - - -"), "rfc5424") { ok = false; }
  if !streq(log_detect("<34>12 - - - - - -"), "rfc5424") { ok = false; }
  if !streq(log_detect("<34>123 - - - - -"), "rfc5424") { ok = false; }
  if !streq(log_detect("<34>1234 - - - - -"), "") { ok = false; }
  if !streq(log_detect("<34>1"), "") { ok = false; }
  if !streq(log_detect("<34>1x"), "") { ok = false; }
  if !streq(log_detect("<34>x"), "rfc3164") { ok = false; }
  if !streq(log_detect("<34> "), "") { ok = false; }
  if !streq(log_detect("<34"), "") { ok = false; }
  if !streq(log_detect("<34>"), "") { ok = false; }
  if !streq(log_detect(""), "") { ok = false; }
  if !streq(log_detect("abc"), "") { ok = false; }
  if !streq(log_detect("<192>x"), "rfc3164") { ok = false; }
  return assert(ok, "auto-detect 3164 vs 5424 from the byte after PRI");
}

fn t11() -> TestResult {
  let r = log5424_parse("<34>1 - - - - - -");
  var ok = false;
  match r {
    Ok(m) => {
      ok = log5424_pri(&m) == 34;
      if log5424_facility(&m) != 4 { ok = false; }
      if log5424_severity(&m) != 2 { ok = false; }
      if log5424_version(&m) != 1 { ok = false; }
      if log5424_has_timestamp(&m) { ok = false; }
      if !streq(log5424_timestamp_text(&m), "") { ok = false; }
      if !streq(log5424_hostname(&m), "") { ok = false; }
      if !streq(log5424_app_name(&m), "") { ok = false; }
      if !streq(log5424_procid(&m), "") { ok = false; }
      if !streq(log5424_msgid(&m), "") { ok = false; }
      if log5424_sd_count(&m) != 0 { ok = false; }
      if log5424_has_msg(&m) { ok = false; }
      if log5424_has_bom(&m) { ok = false; }
      let ts = log5424_timestamp(&m);
      if ts.present { ok = false; }
      if ts.year != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let a = log5424_parse("<34>1 - - - - - - hello");
  match a {
    Ok(m2) => {
      if !log5424_has_msg(&m2) { ok = false; }
      if !streq(log5424_msg(&m2), "hello") { ok = false; }
      if log5424_has_bom(&m2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = log5424_parse("<34>1 - - - - - - ");
  match b {
    Ok(m3) => {
      if !log5424_has_msg(&m3) { ok = false; }
      if !streq(log5424_msg(&m3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "5424 NILVALUE header and optional MSG handling");
}

fn t12() -> TestResult {
  let text = "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [exampleSDID@32473 iut=\"3\" eventSource=\"Application\" eventID=\"1011\"] " + utf8_bom() + "An application event log entry...";
  let r = log5424_parse(text);
  var ok = false;
  match r {
    Ok(m) => {
      ok = log5424_pri(&m) == 165;
      if log5424_facility(&m) != 20 { ok = false; }
      if log5424_severity(&m) != 5 { ok = false; }
      if !streq(log5424_timestamp_text(&m), "2003-10-11T22:14:15.003Z") { ok = false; }
      let ts = log5424_timestamp(&m);
      if !ts.present { ok = false; }
      if ts.year != 2003 { ok = false; }
      if ts.month != 10 { ok = false; }
      if ts.day != 11 { ok = false; }
      if ts.hour != 22 { ok = false; }
      if ts.minute != 14 { ok = false; }
      if ts.second != 15 { ok = false; }
      if !streq(ts.frac, "003") { ok = false; }
      if ts.offset_min != 0 { ok = false; }
      if !streq(log5424_hostname(&m), "mymachine.example.com") { ok = false; }
      if !streq(log5424_app_name(&m), "evntslog") { ok = false; }
      if !streq(log5424_procid(&m), "") { ok = false; }
      if !streq(log5424_msgid(&m), "ID47") { ok = false; }
      if log5424_sd_count(&m) != 1 { ok = false; }
      if !streq(log5424_sd_id(&m, 0), "exampleSDID@32473") { ok = false; }
      if log5424_sd_param_count(&m, 0) != 3 { ok = false; }
      if !streq(log5424_sd_param_name(&m, 0, 0), "iut") { ok = false; }
      if !streq(log5424_sd_param_value(&m, 0, 0), "3") { ok = false; }
      if !streq(log5424_sd_param_value(&m, 0, 1), "Application") { ok = false; }
      if !streq(log5424_sd_param_value(&m, 0, 2), "1011") { ok = false; }
      if !log5424_has_bom(&m) { ok = false; }
      if !streq(log5424_msg(&m), "An application event log entry...") { ok = false; }
      let at = log5424_sd_param_value_at(&m, 0, 1);
      let len = log5424_sd_param_value_len(&m, 0, 1);
      if !streq(string.str_slice(text, at, at + len), "Application") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "5424 RFC example: timestamp fields, SD, BOM, MSG");
}

fn t13() -> TestResult {
  let text = "<34>1 - - - - - [ex a=\"x\\\"\\]y\\\\z\\]w\"]";
  let r = log5424_parse(text);
  var ok = false;
  match r {
    Ok(m) => {
      ok = streq(log5424_sd_param_value(&m, 0, 0), "x\"]y\\z]w");
      if !streq(log5424_sd_param_value_wire(&m, text, 0, 0), "x\\\"\\]y\\\\z\\]w") { ok = false; }
      if log5424_sd_param_value_len(&m, 0, 0) != 12 { ok = false; }
      let at = log5424_sd_param_value_at(&m, 0, 0);
      if !streq(string.str_slice(text, at, at + 12), "x\\\"\\]y\\\\z\\]w") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let multi = "<34>1 - - - - - [a p=\"1\"][b q=\"2\" r=\"3\"]";
  let r2 = log5424_parse(multi);
  match r2 {
    Ok(m2) => {
      if log5424_sd_count(&m2) != 2 { ok = false; }
      if !streq(log5424_sd_id(&m2, 0), "a") { ok = false; }
      if !streq(log5424_sd_id(&m2, 1), "b") { ok = false; }
      if log5424_sd_param_count(&m2, 0) != 1 { ok = false; }
      if log5424_sd_param_count(&m2, 1) != 2 { ok = false; }
      if !streq(log5424_sd_param_value(&m2, 1, 1), "3") { ok = false; }
      if !opt_str_is(log5424_sd_param(&m2, 1, "r"), "3") { ok = false; }
      if !opt_str_none(log5424_sd_param(&m2, 0, "q")) { ok = false; }
      if !opt_str_none(log5424_sd_param(&m2, 0, "P")) { ok = false; }
      if !streq(log5424_sd_id(&m2, 2), "") { ok = false; }
      if log5424_sd_param_count(&m2, -1) != 0 { ok = false; }
      if !streq(log5424_sd_param_name(&m2, 0, 5), "") { ok = false; }
      if !streq(log5424_sd_param_value(&m2, 9, 0), "") { ok = false; }
      if log5424_sd_param_value_at(&m2, 0, 5) != -1 { ok = false; }
      if !streq(log5424_sd_param_value_wire(&m2, multi, 0, 5), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "5424 structured-data escapes, spans, multi-element lookup");
}

fn t14() -> TestResult {
  var ok = err5424("<34>1 - - - - - [ex a=\"unterminated", "logging: bad param quote at 35");
  if !err5424("<34>1 - - - - - [ex a=\"bad\\x\"]", "logging: bad param escape at 26") { ok = false; }
  if !err5424("<34>1 - - - - - [ex a=\"1\\", "logging: bad param escape at 24") { ok = false; }
  if !err5424("<34>1 - - - - - [ex a=\"bad]value\"]", "logging: bad param value at 26") { ok = false; }
  if !err5424("<34>1 - - - - - [ex a=b]", "logging: bad param quote at 22") { ok = false; }
  if !err5424("<34>1 - - - - - [ex a]", "logging: bad param name at 20") { ok = false; }
  if !err5424("<34>1 - - - - - [\"bad\"]", "logging: bad SD-ID at 17") { ok = false; }
  if !err5424("<34>1 - - - - - [ex a=\"1\"", "logging: unterminated structured data at 25") { ok = false; }
  if !err5424("<34>1 - - - - - [ex a=\"1\"]junk", "logging: bad structured data at 26") { ok = false; }
  if !err5424("<34>1 - - - - - x", "logging: bad structured data at 16") { ok = false; }
  if !err5424("<34>1 - - - - - -x", "logging: bad structured data at 17") { ok = false; }
  if !err5424("<34>1 - - - - - []", "logging: bad SD-ID at 17") { ok = false; }
  return assert(ok, "5424 structured-data malformed catalog");
}

fn t15() -> TestResult {
  var ok = log5424_ok("<34>1 - " + a_run(255) + " - - - -");
  if log5424_ok("<34>1 - " + a_run(256) + " - - - -") { ok = false; }
  if !err5424("<34>1 - " + a_run(256) + " - - - -", "logging: HOSTNAME too long at 8") { ok = false; }
  if log5424_ok("<34>1 - " + fill(200u8, 3) + " - - - -") { ok = false; }
  if !err5424("<34>1 - " + fill(200u8, 3) + " - - - -", "logging: bad HOSTNAME at 8") { ok = false; }
  if !log5424_ok("<34>1 - - " + a_run(48) + " - - -") { ok = false; }
  if !err5424("<34>1 - - " + a_run(49) + " - - -", "logging: APP-NAME too long at 10") { ok = false; }
  if !log5424_ok("<34>1 - - - " + a_run(128) + " - -") { ok = false; }
  if !err5424("<34>1 - - - " + a_run(129) + " - -", "logging: PROCID too long at 12") { ok = false; }
  if !log5424_ok("<34>1 - - - - " + a_run(32) + " -") { ok = false; }
  if !err5424("<34>1 - - - - " + a_run(33) + " -", "logging: MSGID too long at 14") { ok = false; }
  return assert(ok, "5424 header field limits 255/48/128/32 and charset");
}

fn t16() -> TestResult {
  var ok = err5424("", "logging: missing PRI at 0");
  if !err5424("x", "logging: missing PRI at 0") { ok = false; }
  if !err5424("<192>1 - - - - - -", "logging: PRI out of range at 1") { ok = false; }
  if !err5424("<1a>1 - - - - - -", "logging: bad PRI at 2") { ok = false; }
  if !err5424("<34>0 - - - - - -", "logging: bad version at 4") { ok = false; }
  if !err5424("<34>x - - - - - -", "logging: bad version at 4") { ok = false; }
  if !err5424("<34>1000 - - - - - -", "logging: bad version at 4") { ok = false; }
  if !err5424("<34>", "logging: bad version at 4") { ok = false; }
  if !err5424("<34>1", "logging: missing TIMESTAMP at 5") { ok = false; }
  if !err5424("<34>1 ", "logging: missing TIMESTAMP at 6") { ok = false; }
  if !err5424("<34>1  - - - - - -", "logging: missing TIMESTAMP at 6") { ok = false; }
  if !err5424("<34>1 x - - - - - -", "logging: bad TIMESTAMP at 7") { ok = false; }
  if !err5424("<34>1 -", "logging: missing TIMESTAMP at 7") { ok = false; }
  if !err5424("<34>1 - -", "logging: missing HOSTNAME at 9") { ok = false; }
  if !err5424("<34>1 - - -", "logging: missing APP-NAME at 11") { ok = false; }
  if !err5424("<34>1 - - - -", "logging: missing PROCID at 13") { ok = false; }
  if !err5424("<34>1 - - - - -", "logging: truncated message at 15") { ok = false; }
  return assert(ok, "5424 malformed header catalog with byte offsets");
}

fn t17() -> TestResult {
  let r = log5424_timestamp_parse("2003-10-11T22:14:15.003Z");
  var ok = false;
  match r {
    Ok(t) => {
      ok = t.year == 2003;
      if t.month != 10 { ok = false; }
      if t.day != 11 { ok = false; }
      if t.hour != 22 { ok = false; }
      if t.minute != 14 { ok = false; }
      if t.second != 15 { ok = false; }
      if !streq(t.frac, "003") { ok = false; }
      if t.offset_min != 0 { ok = false; }
      if !t.present { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let a = log5424_timestamp_parse("2024-02-29T00:00:01+02:30");
  match a {
    Ok(t2) => {
      if t2.offset_min != 150 { ok = false; }
      if t2.day != 29 { ok = false; }
      if !streq(t2.frac, "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = log5424_timestamp_parse("2024-02-29T00:00:01-07:00");
  match b {
    Ok(t3) => {
      if t3.offset_min != -420 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = log5424_timestamp_parse("2003-10-11T00:00:00-00:00");
  match c {
    Ok(t4) => {
      if t4.offset_min != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !log5424_timestamp_valid("2003-10-11T22:14:15.123456Z") { ok = false; }
  if !log5424_timestamp_valid("2003-10-11T22:14:15Z") { ok = false; }
  if log5424_timestamp_valid("") { ok = false; }
  if log5424_timestamp_valid("-") { ok = false; }
  if log5424_timestamp_valid("2003-10-11T22:14:15") { ok = false; }
  return assert(ok, "RFC 3339 timestamp parsed to structured fields");
}

fn t18() -> TestResult {
  var ok = errts("2003-10-11T22:14:15", "logging: bad TIMESTAMP at 19");
  if !errts("2003-10-11t22:14:15Z", "logging: bad TIMESTAMP at 10") { ok = false; }
  if !errts("2003-02-29T00:00:00Z", "logging: bad TIMESTAMP at 8") { ok = false; }
  if !log5424_timestamp_valid("2004-02-29T00:00:00Z") { ok = false; }
  if !errts("2003-13-01T00:00:00Z", "logging: bad TIMESTAMP at 5") { ok = false; }
  if !errts("2003-10-11T24:00:00Z", "logging: bad TIMESTAMP at 11") { ok = false; }
  if !errts("2003-10-11T22:14:60Z", "logging: bad TIMESTAMP at 17") { ok = false; }
  if !errts("2003-10-11T22:14:15.1234567Z", "logging: bad TIMESTAMP at 20") { ok = false; }
  if !errts("2003-10-11T22:14:15.Z", "logging: bad TIMESTAMP at 20") { ok = false; }
  if !errts("2003-10-11T22:14:15+2:30", "logging: bad TIMESTAMP at 20") { ok = false; }
  if !errts("2003-10-11T22:14:15Zx", "logging: bad TIMESTAMP at 20") { ok = false; }
  if !errts("2003-10-11T22:14:15+02:3", "logging: bad TIMESTAMP at 23") { ok = false; }
  if !errts("2003-10-11T22:14:15+02:30x", "logging: bad TIMESTAMP at 25") { ok = false; }
  return assert(ok, "RFC 3339 malformed catalog with byte offsets");
}

fn t19() -> TestResult {
  var ok = log3164_ok("<13>Aug  1 12:00:00 h t:x");
  if log3164_ok("<13>Aug  1 12:00:00 h t") { ok = false; }
  if !log5424_ok("<34>1 - - - - - -") { ok = false; }
  if log5424_ok("<34>1 - - - -") { ok = false; }
  if !dispatch_ok("<34>Oct 11 22:14:15 h su:") { ok = false; }
  if !dispatch_ok("<165>1 2003-10-11T22:14:15Z host app - - -") { ok = false; }
  if dispatch_ok("<34>nope") { ok = false; }
  if !dispatch_ok("<34>1 - - - - - -") { ok = false; }
  return assert(ok, "ok predicates and detect/parse dispatch");
}

fn t20() -> TestResult {
  let text = "<34>1 2003-10-11T22:14:15Z myhost myapp 1234 myid - hi";
  let r = log5424_parse(text);
  var ok = false;
  match r {
    Ok(m) => {
      ok = streq(log5424_hostname(&m), "myhost");
      if !streq(log5424_app_name(&m), "myapp") { ok = false; }
      if !streq(log5424_procid(&m), "1234") { ok = false; }
      if !streq(log5424_msgid(&m), "myid") { ok = false; }
      if !streq(log5424_msg(&m), "hi") { ok = false; }
      let ts = log5424_timestamp(&m);
      if !ts.present { ok = false; }
      if ts.year != 2003 { ok = false; }
      if ts.offset_min != 0 { ok = false; }
      if !streq(ts.frac, "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "5424 field accessors and timestamp structure");
}

fn t21() -> TestResult {
  var ok = true;
  var f = 0;
  while f < 24 {
    var s = 0;
    while s < 8 {
      let r = log_pri_make(f, s);
      if !r.is_ok {
        ok = false;
      } elif r.value != f * 8 + s {
        ok = false;
      }
      if log_pri_facility(f * 8 + s) != f { ok = false; }
      if log_pri_severity(f * 8 + s) != s { ok = false; }
      if !log_pri_valid(f * 8 + s) { ok = false; }
      s = s + 1;
    }
    let nm = log_facility_name(f);
    let rc = log_facility_code(nm);
    if !rc.is_ok {
      ok = false;
    } elif rc.value != f {
      ok = false;
    }
    f = f + 1;
  }
  var sv = 0;
  while sv < 8 {
    let nm = log_severity_name(sv);
    let rc = log_severity_code(nm);
    if !rc.is_ok {
      ok = false;
    } elif rc.value != sv {
      ok = false;
    }
    sv = sv + 1;
  }
  return assert(ok, "PRI/name round-trip over all 192 facility x severity pairs");
}

fn t22() -> TestResult {
  let empty_param = "<34>1 - - - - - [a p=\"\"]";
  let r = log5424_parse(empty_param);
  var ok = false;
  match r {
    Ok(m) => {
      ok = log5424_sd_param_count(&m, 0) == 1;
      if !streq(log5424_sd_param_value(&m, 0, 0), "") { ok = false; }
      if log5424_sd_param_value_len(&m, 0, 0) != 0 { ok = false; }
      if !streq(log5424_sd_param_value_wire(&m, empty_param, 0, 0), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let bare = log5424_parse("<34>1 - - - - - [a]");
  match bare {
    Ok(m2) => {
      if log5424_sd_count(&m2) != 1 { ok = false; }
      if log5424_sd_param_count(&m2, 0) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let bom_only = "<34>1 - - - - - - " + utf8_bom();
  let rb = log5424_parse(bom_only);
  match rb {
    Ok(m3) => {
      if !log5424_has_msg(&m3) { ok = false; }
      if !log5424_has_bom(&m3) { ok = false; }
      if !streq(log5424_msg(&m3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "5424 empty SD element, empty param value, BOM-only MSG");
}

fn main() -> Int {
  io.println("=== xiom.logging conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.logging: all tests passed");
  } else {
    io.println("xiom.logging: tests failed");
  }
  return failed;
}
