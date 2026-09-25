// XIOM -- xiom.syslog conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: the RFC 5424 example, PRI boundaries and the facility/severity
// mapping, every documented error path, RFC 3339 timestamp validation
// (valid and invalid forms), NILVALUE normalization, header charset and
// length limits, structured-data elements/parameters/escapes and their
// errors, MSG + UTF-8 BOM handling, byte-exact round-trips, canonical
// build output, build-time validation and accessor bounds.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq instead of `==`; Vec[Str] and
// Vec[Int] element reads are bound with typed locals first.

module syslog_tests
use xiom.io; use xiom.test; use xiom.syslog;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// The three UTF-8 BOM bytes (EF BB BF) as a Str.
fn bom() -> Str {
  var sb = Vec[UInt8].new();
  sb.push(239u8);
  sb.push(187u8);
  sb.push(191u8);
  return builder.sb_to_str(&sb);
}

fn ok_of(text: Str) -> Bool {
  match syslog_parse(text) {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

fn err_of(text: Str, want: Str) -> Bool {
  match syslog_parse(text) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when build(parse(text)) reproduces text byte for byte.
fn roundtrip(text: Str) -> Bool {
  if !ok_of(text) {
    return false;
  }
  let r = syslog_parse(text);
  match r {
    Ok(m) => {
      let b = syslog_build(&m);
      if !b.is_ok {
        return false;
      }
      let out: Str = b.value;
      return streq(out, text);
    },
    Err(_) => { return false; },
  }
  return false;
}

// Build result, or "<build error>" on failure (for equality checks).
fn built(m: &SyslogMsg) -> Str {
  let b = syslog_build(m);
  if !b.is_ok {
    return "<build error>";
  }
  let s: Str = b.value;
  return s;
}

// Build error text, or "<no error>" on success.
fn build_err(m: &SyslogMsg) -> Str {
  let b = syslog_build(m);
  if b.is_ok {
    return "<no error>";
  }
  let e: Str = b.error;
  return e;
}

// A valid RFC 5424 message struct: PRI 165 (facility 20, severity 5).
fn base() -> SyslogMsg {
  return SyslogMsg{
    facility: 20;
    severity: 5;
    version: 1;
    timestamp: "2003-10-11T22:14:15.003Z";
    hostname: "mymachine.example.com";
    app_name: "evntslog";
    procid: "";
    msgid: "ID47";
    msg: "";
    bom: false;
    has_msg: true;
    sd_ids: Vec[Str].new();
    sd_param_elem: Vec[Int].new();
    sd_param_names: Vec[Str].new();
    sd_param_values: Vec[Str].new();
  };
}

// base() plus one structured-data element with one parameter.
fn sd1(id: Str, pn: Str, pv: Str) -> SyslogMsg {
  var m = base();
  m.sd_ids.push(id);
  m.sd_param_elem.push(0);
  m.sd_param_names.push(pn);
  m.sd_param_values.push(pv);
  return m;
}

fn t1() -> TestResult {
  let text = "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [exampleSDID@32473 iut=\"3\" eventSource=\"Application\" eventID=\"1011\"] " + bom() + "An application event log entry...";
  let r = syslog_parse(text);
  var ok = false;
  match r {
    Ok(m) => {
      ok = syslog_facility(&m) == 20;
      if syslog_severity(&m) != 5 { ok = false; }
      if syslog_pri(&m) != 165 { ok = false; }
      if syslog_version(&m) != 1 { ok = false; }
      if !streq(syslog_timestamp(&m), "2003-10-11T22:14:15.003Z") { ok = false; }
      if !streq(syslog_hostname(&m), "mymachine.example.com") { ok = false; }
      if !streq(syslog_app_name(&m), "evntslog") { ok = false; }
      if !streq(syslog_procid(&m), "") { ok = false; }
      if !streq(syslog_msgid(&m), "ID47") { ok = false; }
      if !syslog_has_bom(&m) { ok = false; }
      if !syslog_has_msg(&m) { ok = false; }
      if !streq(syslog_msg(&m), "An application event log entry...") { ok = false; }
      if syslog_sd_count(&m) != 1 { ok = false; }
      if !streq(syslog_sd_id(&m, 0), "exampleSDID@32473") { ok = false; }
      if syslog_sd_param_count(&m, 0) != 3 { ok = false; }
      if !streq(syslog_sd_param_name(&m, 0, 0), "iut") { ok = false; }
      if !streq(syslog_sd_param_value(&m, 0, 0), "3") { ok = false; }
      if !streq(syslog_sd_param_name(&m, 0, 1), "eventSource") { ok = false; }
      if !streq(syslog_sd_param_value(&m, 0, 1), "Application") { ok = false; }
      if !streq(syslog_sd_param_name(&m, 0, 2), "eventID") { ok = false; }
      if !streq(syslog_sd_param_value(&m, 0, 2), "1011") { ok = false; }
      match syslog_sd_param(&m, 0, "eventSource") {
        Some(v) => { if !streq(v, "Application") { ok = false; } },
        None => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "RFC 5424 example: header, SD, BOM and MSG");
}

fn t2() -> TestResult {
  let r0 = syslog_parse("<0>1 - - - - - -");
  var ok = false;
  match r0 {
    Ok(m) => {
      ok = syslog_facility(&m) == 0;
      if syslog_severity(&m) != 0 { ok = false; }
      if syslog_pri(&m) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r1 = syslog_parse("<8>1 - - - - - -");
  match r1 {
    Ok(m) => {
      if syslog_facility(&m) != 1 { ok = false; }
      if syslog_severity(&m) != 0 { ok = false; }
      if syslog_pri(&m) != 8 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = syslog_parse("<191>1 - - - - - -");
  match r2 {
    Ok(m) => {
      if syslog_facility(&m) != 23 { ok = false; }
      if syslog_severity(&m) != 7 { ok = false; }
      if syslog_pri(&m) != 191 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var mhi = base();
  mhi.facility = 23;
  mhi.severity = 7;
  if !string.str_starts_with(built(&mhi), "<191>1 ") { ok = false; }
  var mlo = base();
  mlo.facility = 0;
  mlo.severity = 0;
  if !string.str_starts_with(built(&mlo), "<0>1 ") { ok = false; }
  return assert(ok, "PRI boundaries and facility/severity mapping");
}

fn t3() -> TestResult {
  var ok = err_of("", "syslog: missing PRI");
  if !err_of("hello", "syslog: missing PRI") { ok = false; }
  if !err_of("<>1 - - - - - -", "syslog: bad PRI") { ok = false; }
  if !err_of("<abc>1 - - - - - -", "syslog: bad PRI") { ok = false; }
  if !err_of("<12", "syslog: bad PRI") { ok = false; }
  if !err_of("<1234>1 - - - - - -", "syslog: bad PRI") { ok = false; }
  if !err_of("<-1>1 - - - - - -", "syslog: bad PRI") { ok = false; }
  if !err_of("<192>1 - - - - - -", "syslog: PRI out of range: 192") { ok = false; }
  if !err_of("<999>1 - - - - - -", "syslog: PRI out of range: 999") { ok = false; }
  return assert(ok, "PRI error paths");
}

fn t4() -> TestResult {
  var ok = err_of("<34>x - - - - - -", "syslog: bad version: x");
  if !err_of("<34>0 - - - - - -", "syslog: bad version: 0") { ok = false; }
  if !err_of("<34>01 - - - - - -", "syslog: bad version: 01") { ok = false; }
  if !err_of("<34>1000 - - - - -", "syslog: bad version: 1000") { ok = false; }
  if !err_of("<34>1.2 - - - - -", "syslog: bad version: 1.2") { ok = false; }
  if !err_of("<34>", "syslog: bad version: ") { ok = false; }
  if !err_of("<34> ", "syslog: bad version: ") { ok = false; }
  if !err_of("<34>1", "syslog: missing field: TIMESTAMP") { ok = false; }
  if !ok_of("<34>999 - - - - - -") { ok = false; }
  return assert(ok, "VERSION error paths and the 1..999 range");
}

fn t5() -> TestResult {
  var ok = err_of("<34>1 ", "syslog: missing field: TIMESTAMP");
  if !err_of("<34>1  - - - - -", "syslog: missing field: TIMESTAMP") { ok = false; }
  if !err_of("<34>1 - ", "syslog: missing field: HOSTNAME") { ok = false; }
  if !err_of("<34>1 - - ", "syslog: missing field: APP-NAME") { ok = false; }
  if !err_of("<34>1 - - - ", "syslog: missing field: PROCID") { ok = false; }
  if !err_of("<34>1 - - - -  -", "syslog: missing field: MSGID") { ok = false; }
  if !err_of("<34>1 - - - -", "syslog: missing field: PROCID") { ok = false; }
  if !err_of("<34>1 - - - - -", "syslog: truncated message") { ok = false; }
  return assert(ok, "missing header fields and truncation");
}

fn t6() -> TestResult {
  var ok = syslog_timestamp_valid("2003-10-11T22:14:15Z");
  if !syslog_timestamp_valid("2003-10-11T22:14:15.1Z") { ok = false; }
  if !syslog_timestamp_valid("2003-10-11T22:14:15.123456Z") { ok = false; }
  if !syslog_timestamp_valid("2003-10-11T22:14:15+02:00") { ok = false; }
  if !syslog_timestamp_valid("2003-10-11T22:14:15-00:00") { ok = false; }
  if !syslog_timestamp_valid("2000-02-29T00:00:00Z") { ok = false; }
  if !syslog_timestamp_valid("2024-02-29T23:59:59Z") { ok = false; }
  if !syslog_timestamp_valid("1900-02-28T00:00:00Z") { ok = false; }
  if !syslog_timestamp_valid("0000-01-01T00:00:00Z") { ok = false; }
  let r = syslog_parse("<34>1 2003-10-11T22:14:15.123456+02:00 - - - - -");
  match r {
    Ok(m) => {
      if !streq(syslog_timestamp(&m), "2003-10-11T22:14:15.123456+02:00") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "valid RFC 3339 / RFC 5424 timestamp forms");
}

fn t7() -> TestResult {
  var ok = !syslog_timestamp_valid("");
  if syslog_timestamp_valid("-") { ok = false; }
  if syslog_timestamp_valid("2003-10-11") { ok = false; }
  if syslog_timestamp_valid("2003-13-01T22:14:15Z") { ok = false; }
  if syslog_timestamp_valid("2003-02-30T22:14:15Z") { ok = false; }
  if syslog_timestamp_valid("1900-02-29T22:14:15Z") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T24:00:00Z") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T22:60:00Z") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T22:14:60Z") { ok = false; }
  if syslog_timestamp_valid("2003-10-11t22:14:15z") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T22:14:15.1234567Z") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T22:14:15.Z") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T22:14:15") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T22:14:15+24:00") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T22:14:15+02:60") { ok = false; }
  if syslog_timestamp_valid("2003-10-11T22:14:15Zx") { ok = false; }
  if !err_of("<34>1 not-a-time - - - - -", "syslog: bad TIMESTAMP: not-a-time") { ok = false; }
  return assert(ok, "invalid timestamp forms and the parse error");
}

fn t8() -> TestResult {
  let r = syslog_parse("<34>1 - - - - - -");
  var ok = false;
  match r {
    Ok(m) => {
      ok = streq(syslog_timestamp(&m), "");
      if !streq(syslog_hostname(&m), "") { ok = false; }
      if !streq(syslog_app_name(&m), "") { ok = false; }
      if !streq(syslog_procid(&m), "") { ok = false; }
      if !streq(syslog_msgid(&m), "") { ok = false; }
      if !streq(syslog_msg(&m), "") { ok = false; }
      if syslog_has_msg(&m) { ok = false; }
      if syslog_sd_count(&m) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !roundtrip("<34>1 - - - - - -") { ok = false; }
  if !roundtrip("<34>1 - - - - - - ") { ok = false; }
  return assert(ok, "NILVALUE header fields normalize to empty strings");
}

fn t9() -> TestResult {
  let h255 = string.str_repeat("h", 255);
  let r = syslog_parse("<34>1 - " + h255 + " - - - -");
  var ok = false;
  match r {
    Ok(m) => { ok = streq(syslog_hostname(&m), h255); },
    Err(_) => { ok = false; },
  }
  let h256 = string.str_repeat("h", 256);
  if !err_of("<34>1 - " + h256 + " - - - -", "syslog: HOSTNAME too long") { ok = false; }
  let a48 = string.str_repeat("a", 48);
  if !ok_of("<34>1 - - " + a48 + " - - -") { ok = false; }
  let a49 = string.str_repeat("a", 49);
  if !err_of("<34>1 - - " + a49 + " - - -", "syslog: APP-NAME too long") { ok = false; }
  let p128 = string.str_repeat("p", 128);
  if !ok_of("<34>1 - - - " + p128 + " - -") { ok = false; }
  let p129 = string.str_repeat("p", 129);
  if !err_of("<34>1 - - - " + p129 + " - -", "syslog: PROCID too long") { ok = false; }
  let g32 = string.str_repeat("g", 32);
  if !ok_of("<34>1 - - - - " + g32 + " -") { ok = false; }
  let g33 = string.str_repeat("g", 33);
  if !err_of("<34>1 - - - - " + g33 + " -", "syslog: MSGID too long") { ok = false; }
  if !err_of("<34>1 - h\tost - - - -", "syslog: bad HOSTNAME: h\tost") { ok = false; }
  return assert(ok, "header field charset and RFC 5424 length limits");
}

fn t10() -> TestResult {
  let r = syslog_parse("<34>1 - - - - - [exampleSDID@32473 iut=\"3\" eventSource=\"Application\" eventID=\"1011\"]");
  var ok = false;
  match r {
    Ok(m) => {
      ok = syslog_sd_count(&m) == 1;
      if !streq(syslog_sd_id(&m, 0), "exampleSDID@32473") { ok = false; }
      if syslog_sd_param_count(&m, 0) != 3 { ok = false; }
      if !streq(syslog_sd_param_name(&m, 0, 0), "iut") { ok = false; }
      if !streq(syslog_sd_param_value(&m, 0, 0), "3") { ok = false; }
      if !streq(syslog_sd_param_value(&m, 0, 2), "1011") { ok = false; }
      match syslog_sd_param(&m, 0, "iut") {
        Some(v) => { if !streq(v, "3") { ok = false; } },
        None => { ok = false; },
      }
      match syslog_sd_param(&m, 0, "nope") {
        Some(_) => { ok = false; },
        None => {},
      }
    },
    Err(_) => { ok = false; },
  }
  let r2 = syslog_parse("<34>1 - - - - - [id]");
  match r2 {
    Ok(m) => {
      if syslog_sd_count(&m) != 1 { ok = false; }
      if syslog_sd_param_count(&m, 0) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = syslog_parse("<34>1 - - - - - [id a=\"\"]");
  match r3 {
    Ok(m) => {
      if syslog_sd_param_count(&m, 0) != 1 { ok = false; }
      if !streq(syslog_sd_param_value(&m, 0, 0), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "structured-data elements and parameters");
}

fn t11() -> TestResult {
  let r = syslog_parse("<34>1 - - - - - [a x=\"1\"][b y=\"2\" z=\"3\"][c]");
  var ok = false;
  match r {
    Ok(m) => {
      ok = syslog_sd_count(&m) == 3;
      if !streq(syslog_sd_id(&m, 0), "a") { ok = false; }
      if !streq(syslog_sd_id(&m, 1), "b") { ok = false; }
      if !streq(syslog_sd_id(&m, 2), "c") { ok = false; }
      if syslog_sd_param_count(&m, 0) != 1 { ok = false; }
      if syslog_sd_param_count(&m, 1) != 2 { ok = false; }
      if syslog_sd_param_count(&m, 2) != 0 { ok = false; }
      if !streq(syslog_sd_param_value(&m, 1, 1), "3") { ok = false; }
      match syslog_sd_param(&m, 0, "y") {
        Some(_) => { ok = false; },
        None => {},
      }
      match syslog_sd_param(&m, 1, "z") {
        Some(v) => { if !streq(v, "3") { ok = false; } },
        None => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multiple SD elements keep order and element mapping");
}

fn t12() -> TestResult {
  let text = "<34>1 - - - - - [id quote=\"say \\\"hi\\\"\" back=\"a\\\\b\" bracket=\"x\\]y\"]";
  let r = syslog_parse(text);
  var ok = false;
  match r {
    Ok(m) => {
      ok = syslog_sd_param_count(&m, 0) == 3;
      if !streq(syslog_sd_param_value(&m, 0, 0), "say \"hi\"") { ok = false; }
      if !streq(syslog_sd_param_value(&m, 0, 1), "a\\b") { ok = false; }
      if !streq(syslog_sd_param_value(&m, 0, 2), "x]y") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !roundtrip(text) { ok = false; }
  return assert(ok, "escaped quote, backslash and bracket decode and re-encode");
}

fn t13() -> TestResult {
  var ok = err_of("<34>1 - - - - - [id", "syslog: unterminated structured data");
  if !err_of("<34>1 - - - - - [id a=\"v\"", "syslog: unterminated structured data") { ok = false; }
  if !err_of("<34>1 - - - - - [id a=v]", "syslog: bad param quote") { ok = false; }
  if !err_of("<34>1 - - - - - [id a=\"v", "syslog: bad param quote") { ok = false; }
  if !err_of("<34>1 - - - - - [id a=\"v]", "syslog: bad param value") { ok = false; }
  if !err_of("<34>1 - - - - - [id a=\"v\\q\"]", "syslog: bad param escape") { ok = false; }
  if !err_of("<34>1 - - - - - [id a=\"v\\", "syslog: bad param escape") { ok = false; }
  if !err_of("<34>1 - - - - - [id b x=\"y\"]", "syslog: bad param name: b") { ok = false; }
  if !err_of("<34>1 - - - - - [id b]", "syslog: bad param name: b") { ok = false; }
  if !err_of("<34>1 - - - - - []", "syslog: bad SD-ID: ") { ok = false; }
  if !err_of("<34>1 - - - - - [a=b]", "syslog: bad SD-ID: a=b") { ok = false; }
  if !err_of("<34>1 - - - - - [a]x", "syslog: bad structured data") { ok = false; }
  if !err_of("<34>1 - - - - - x", "syslog: bad structured data") { ok = false; }
  if !err_of("<34>1 - - - - - -x", "syslog: bad structured data") { ok = false; }
  if !err_of("<34>1 - - - - - [a q=\"1\"x]", "syslog: bad structured data") { ok = false; }
  return assert(ok, "structured-data error catalog");
}

fn t14() -> TestResult {
  let r1 = syslog_parse("<34>1 - - - - - - hello world");
  var ok = false;
  match r1 {
    Ok(m) => {
      ok = streq(syslog_msg(&m), "hello world");
      if !syslog_has_msg(&m) { ok = false; }
      if syslog_has_bom(&m) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let odd = "msg [x] - \\ end";
  let r2 = syslog_parse("<34>1 - - - - - - " + odd);
  match r2 {
    Ok(m) => { if !streq(syslog_msg(&m), odd) { ok = false; } },
    Err(_) => { ok = false; },
  }
  let only_bom = "<34>1 - - - - - - " + bom();
  let r3 = syslog_parse(only_bom);
  match r3 {
    Ok(m) => {
      if !streq(syslog_msg(&m), "") { ok = false; }
      if !syslog_has_bom(&m) { ok = false; }
      if !syslog_has_msg(&m) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let with_bom = "<34>1 - - - - - - " + bom() + "payload";
  let r4 = syslog_parse(with_bom);
  match r4 {
    Ok(m) => {
      if !streq(syslog_msg(&m), "payload") { ok = false; }
      if !syslog_has_bom(&m) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r5 = syslog_parse("<34>1 - - - - - -");
  match r5 {
    Ok(m) => {
      if syslog_has_msg(&m) { ok = false; }
      if !streq(syslog_msg(&m), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r6 = syslog_parse("<34>1 - - - - - - hi\n");
  match r6 {
    Ok(m) => { if !streq(syslog_msg(&m), "hi\n") { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !roundtrip(with_bom) { ok = false; }
  return assert(ok, "MSG, BOM stripping and the has_msg flag");
}

fn t15() -> TestResult {
  var fixtures = Vec[Str].new();
  fixtures.push("<0>1 - - - - - -");
  fixtures.push("<191>1 2003-10-11T22:14:15Z host app 12 ID47 - hello");
  fixtures.push("<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [exampleSDID@32473 iut=\"3\"] msg");
  fixtures.push("<34>1 - - - - - [a x=\"1\"][b y=\"2\"] ");
  fixtures.push("<34>1 2003-10-11T22:14:15+02:00 - - - - [id k=\"a b=c\"] x y");
  fixtures.push("<34>1 - - - - - - " + bom() + "boom");
  fixtures.push("<34>1 - - - - - [id quote=\"say \\\"hi\\\"\" back=\"a\\\\b\" bracket=\"x\\]y\"]");
  fixtures.push("<34>1 - - - - - -");
  var ok = true;
  var i = 0;
  while i < fixtures.len() {
    let f: Str = fixtures[i];
    if !roundtrip(f) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "byte-exact build(parse(text)) round-trips");
}

fn t16() -> TestResult {
  var m = base();
  m.msg = "An application event log entry...";
  m.sd_ids.push("exampleSDID@32473");
  m.sd_param_elem.push(0);
  m.sd_param_names.push("iut");
  m.sd_param_values.push("3");
  let want = "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [exampleSDID@32473 iut=\"3\"] An application event log entry...";
  var ok = streq(built(&m), want);
  let nil = base();
  if !streq(built(&nil), "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 - ") { ok = false; }
  var no_msg = base();
  no_msg.has_msg = false;
  if !streq(built(&no_msg), "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 -") { ok = false; }
  return assert(ok, "canonical build output and NILVALUE emission");
}

fn t17() -> TestResult {
  var m1 = base();
  m1.facility = 24;
  var ok = streq(build_err(&m1), "syslog: facility out of range");
  var m2 = base();
  m2.severity = 8;
  if !streq(build_err(&m2), "syslog: severity out of range") { ok = false; }
  var m3 = base();
  m3.version = 0;
  if !streq(build_err(&m3), "syslog: bad version: 0") { ok = false; }
  var m4 = base();
  m4.timestamp = "nope";
  if !streq(build_err(&m4), "syslog: bad TIMESTAMP: nope") { ok = false; }
  var m5 = base();
  m5.hostname = string.str_repeat("h", 256);
  if !streq(build_err(&m5), "syslog: HOSTNAME too long") { ok = false; }
  var m6 = base();
  m6.hostname = "a\tb";
  if !streq(build_err(&m6), "syslog: bad HOSTNAME: a\tb") { ok = false; }
  var m7 = base();
  m7.sd_ids.push("");
  if !streq(build_err(&m7), "syslog: bad SD-ID: ") { ok = false; }
  var m8 = base();
  m8.sd_ids.push("id");
  m8.sd_param_elem.push(0);
  m8.sd_param_names.push("a b");
  m8.sd_param_values.push("v");
  if !streq(build_err(&m8), "syslog: bad param name: a b") { ok = false; }
  var m9 = base();
  m9.sd_ids.push("id");
  m9.sd_param_elem.push(5);
  m9.sd_param_names.push("p");
  m9.sd_param_values.push("v");
  if !streq(build_err(&m9), "syslog: bad structured data: inconsistent layout") { ok = false; }
  var m10 = base();
  m10.sd_ids.push("id");
  m10.sd_param_names.push("p");
  if !streq(build_err(&m10), "syslog: bad structured data: inconsistent layout") { ok = false; }
  return assert(ok, "build-time validation errors");
}

fn t18() -> TestResult {
  var m = base();
  m.sd_ids.push("id");
  m.sd_param_elem.push(0);
  m.sd_param_elem.push(0);
  m.sd_param_names.push("a");
  m.sd_param_names.push("b");
  m.sd_param_values.push("1");
  m.sd_param_values.push("2");
  var ok = streq(syslog_sd_id(&m, -1), "");
  if !streq(syslog_sd_id(&m, 1), "") { ok = false; }
  if syslog_sd_param_count(&m, 1) != 0 { ok = false; }
  if syslog_sd_param_count(&m, -1) != 0 { ok = false; }
  if !streq(syslog_sd_param_name(&m, 0, 2), "") { ok = false; }
  if !streq(syslog_sd_param_value(&m, 0, -1), "") { ok = false; }
  match syslog_sd_param(&m, 0, "zzz") {
    Some(_) => { ok = false; },
    None => {},
  }
  match syslog_sd_param(&m, 1, "a") {
    Some(_) => { ok = false; },
    None => {},
  }
  return assert(ok, "accessor bounds and None results");
}

fn t19() -> TestResult {
  let r = syslog_parse("<34>1 - - - - - -");
  var ok = false;
  match r {
    Ok(m) => { ok = syslog_sd_count(&m) == 0; },
    Err(_) => { ok = false; },
  }
  var one = base();
  one.has_msg = false;
  one.msg = "";
  one.sd_ids.push("id");
  if !streq(built(&one), "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [id]") { ok = false; }
  if !roundtrip(built(&one)) { ok = false; }
  return assert(ok, "SD NILVALUE versus an id-only element");
}

fn t20() -> TestResult {
  var ok = syslog_ok("<34>1 - - - - - -");
  if syslog_ok("") { ok = false; }
  if syslog_ok("nope") { ok = false; }
  if syslog_ok("<34>1 - - - - - [id") { ok = false; }
  if !syslog_ok("<0>1 - - - - - -") { ok = false; }
  return assert(ok, "syslog_ok agrees with syslog_parse");
}

fn t21() -> TestResult {
  let r = syslog_parse("<034>1 - - - - - -");
  var ok = false;
  match r {
    Ok(m) => {
      ok = syslog_facility(&m) == 4;
      if syslog_severity(&m) != 2 { ok = false; }
      if syslog_pri(&m) != 34 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var m = base();
  m.facility = 4;
  m.severity = 2;
  m.has_msg = false;
  if !streq(built(&m), "<34>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 -") { ok = false; }
  return assert(ok, "PRI leading zeros parse and canonicalize away");
}

fn t22() -> TestResult {
  let r = syslog_parse("<34>1 - - - - - [id k=\"a b=c\"]");
  var ok = false;
  match r {
    Ok(m) => {
      ok = syslog_sd_param_count(&m, 0) == 1;
      if !streq(syslog_sd_param_value(&m, 0, 0), "a b=c") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = syslog_parse("<34>1 - - - - - [id k=\"[x\\]y\"]");
  match r2 {
    Ok(m) => {
      if !streq(syslog_sd_param_value(&m, 0, 0), "[x]y") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !roundtrip("<34>1 - - - - - [id k=\"[x\\]y\"]") { ok = false; }
  return assert(ok, "param values keep spaces and '='; brackets need escapes");
}

fn t23() -> TestResult {
  var m = base();
  m.has_msg = false;
  m.msg = "";
  m.sd_ids.push("a");
  m.sd_ids.push("b");
  m.sd_param_elem.push(0);
  m.sd_param_names.push("x");
  m.sd_param_values.push("1");
  m.sd_param_elem.push(1);
  m.sd_param_names.push("y");
  m.sd_param_values.push("2");
  m.sd_param_elem.push(0);
  m.sd_param_names.push("z");
  m.sd_param_values.push("3");
  let want = "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [a x=\"1\" z=\"3\"][b y=\"2\"]";
  return assert(streq(built(&m), want), "build groups parameters by element index");
}

fn t24() -> TestResult {
  var ok = syslog_timestamp_valid("2003-10-11T00:00:00-23:59");
  if !syslog_timestamp_valid("2003-12-31T23:59:59.999999Z") { ok = false; }
  if syslog_timestamp_valid("2003-04-31T23:59:59Z") { ok = false; }
  if syslog_timestamp_valid("2003-00-01T00:00:00Z") { ok = false; }
  if syslog_timestamp_valid("2003-10-00T00:00:00Z") { ok = false; }
  let r = syslog_parse("<34>1 - - - - - - body text");
  match r {
    Ok(m) => {
      if !streq(syslog_timestamp(&m), "") { ok = false; }
      if !streq(syslog_msg(&m), "body text") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !roundtrip("<34>1 - - - - - - body text") { ok = false; }
  return assert(ok, "timestamp boundaries and NILVALUE timestamp round-trip");
}

fn main() -> Int {
  io.println("=== xiom.syslog conformance tests ===");
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
    io.println("xiom.syslog: all tests passed");
  } else {
    io.println("xiom.syslog: tests failed");
  }
  return failed;
}
