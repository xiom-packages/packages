// XIOM -- xiom.ical conformance tests (22 checks)
// Prove the pure-XIOM xiom.ical module against its documented RFC 5545
// subset: folding, content lines, parameters, TEXT escaping, component trees,
// first-match lookup and round-trips.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/opt_str_is instead of `==`. Backslashes are
// built with bs() so no literal depends on compiler escape corner cases.

module ical_tests
use xiom.io; use xiom.test; use xiom.ical;
use xiom.string;
use xiom.string.compare;

fn bs() -> Str {
  return "\\";
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

// True when the text fails to parse with an "ical: " error message.
fn parse_err_prefix(text: Str) -> Bool {
  let r = ical_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "ical: "); },
  }
  return false;
}

// True when the text fails to parse with exactly `want` as the message.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = ical_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Number of CRLF-terminated physical lines (serializer output has no other
// CR or LF bytes).
fn phys_line_count(s: Str) -> Int {
  var n = 0;
  var i = 0;
  while i + 1 < s.len() {
    let a: UInt8 = string.byte_at(s, i);
    let b: UInt8 = string.byte_at(s, i + 1);
    if a == 13u8 && b == 10u8 {
      n = n + 1;
      i = i + 2;
    } else {
      i = i + 1;
    }
  }
  return n;
}

// True when every physical line of `s` is at most `limit` bytes long
// (excluding CRLF).
fn phys_lines_at_most(s: Str, limit: Int) -> Bool {
  var start = 0;
  var i = 0;
  while i <= s.len() {
    if i == s.len() || string.byte_at(s, i) == 13u8 || string.byte_at(s, i) == 10u8 {
      let seg = string.str_slice(s, start, i);
      if seg.len() > limit {
        return false;
      }
      if i == s.len() {
        break;
      }
      if string.byte_at(s, i) == 13u8 && i + 1 < s.len() && string.byte_at(s, i + 1) == 10u8 {
        i = i + 2;
      } else {
        i = i + 1;
      }
      start = i;
    } else {
      i = i + 1;
    }
  }
  return true;
}

fn t1() -> TestResult {
  let r = ical_parse("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//X//EN\r\nBEGIN:VEVENT\r\nUID:1@example.com\r\nDTSTAMP:20260925T090000Z\r\nDTSTART:20260925T100000Z\r\nDTEND:20260925T110000Z\r\nSUMMARY:Standup\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = ical_component_count(&c) == 2;
      if ical_root_count(&c) != 1 { ok = false; }
      if ical_root(&c, 0) != 0 { ok = false; }
      if ical_root(&c, 1) != -1 { ok = false; }
      if !streq(ical_component_name(&c, 0), "vcalendar") { ok = false; }
      if !streq(ical_component_name(&c, 1), "vevent") { ok = false; }
      if ical_component_parent(&c, 0) != -1 { ok = false; }
      if ical_component_parent(&c, 1) != 0 { ok = false; }
      if ical_component_parent(&c, 9) != -2 { ok = false; }
      if !streq(ical_component_name(&c, 9), "") { ok = false; }
      if ical_child_count(&c, 0) != 1 { ok = false; }
      if ical_child(&c, 0, 0) != 1 { ok = false; }
      if ical_child(&c, 0, 1) != -1 { ok = false; }
      if ical_child_count(&c, -1) != 1 { ok = false; }
      if ical_prop_count(&c, 0) != 2 { ok = false; }
      if ical_prop_count(&c, 1) != 5 { ok = false; }
      if !opt_str_is(ical_get(&c, 0, "VERSION"), "2.0") { ok = false; }
      if !opt_str_is(ical_get(&c, 0, "PRODID"), "-//X//EN") { ok = false; }
      if !opt_str_is(ical_get(&c, 1, "UID"), "1@example.com") { ok = false; }
      if !opt_str_is(ical_get(&c, 1, "DTSTAMP"), "20260925T090000Z") { ok = false; }
      if !opt_str_is(ical_get(&c, 1, "DTSTART"), "20260925T100000Z") { ok = false; }
      if !opt_str_is(ical_get(&c, 1, "DTEND"), "20260925T110000Z") { ok = false; }
      if !opt_str_is(ical_get(&c, 1, "SUMMARY"), "Standup") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "calendar parses into a component tree with properties");
}

fn t2() -> TestResult {
  let r = ical_parse("BEGIN:VCALENDAR\r\nX-TAG:one\r\nX-TAG:two\r\nX-Tag:three\r\nEND:VCALENDAR\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = ical_prop_count(&c, 0) == 3;
      if !opt_str_is(ical_get(&c, 0, "x-tag"), "one") { ok = false; }
      if !opt_str_is(ical_get(&c, 0, "X-TAG"), "one") { ok = false; }
      if ical_find_prop(&c, 0, "X-Tag") != 0 { ok = false; }
      if !streq(ical_prop_name(&c, 0, 1), "x-tag") { ok = false; }
      if !streq(ical_prop_value(&c, 0, 2), "three") { ok = false; }
      if !opt_str_none(ical_get(&c, 0, "missing")) { ok = false; }
      if ical_find_prop(&c, 0, "missing") != -1 { ok = false; }
      if !streq(ical_prop_name(&c, 0, 7), "") { ok = false; }
      if !streq(ical_prop_value(&c, 0, 7), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "property lookup is case-insensitive, first match wins");
}

fn t3() -> TestResult {
  var ok = false;
  let a = ical_parse("BEGIN:VEVENT\r\nSUMMARY:a\r\n b\r\nEND:VEVENT\r\n");
  match a {
    Ok(c) => {
      ok = ical_component_count(&c) == 1;
      if !opt_str_is(ical_get(&c, 0, "summary"), "ab") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = ical_parse("BEGIN:VEVENT\r\nSUMMARY:a\r\n\tb\r\nEND:VEVENT\r\n");
  match b {
    Ok(c) => { if !opt_str_is(ical_get(&c, 0, "summary"), "ab") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let d = ical_parse("BEGIN:VEVENT\r\nSUMMARY:a\r\n b\r\n c\r\nEND:VEVENT\r\n");
  match d {
    Ok(c) => { if !opt_str_is(ical_get(&c, 0, "summary"), "abc") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let e = ical_parse("BEGIN:VEVENT\r\nSUMMARY:a\r\n  b\r\nEND:VEVENT\r\n");
  match e {
    Ok(c) => { if !opt_str_is(ical_get(&c, 0, "summary"), "a b") { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !streq(ical_unfold("x\r\n y\n\tz"), "xyz") { ok = false; }
  if !streq(ical_unfold("a\r\nb"), "a\r\nb") { ok = false; }
  return assert(ok, "folded continuations unfold by dropping one whitespace byte");
}

fn t4() -> TestResult {
  let raw = "a;b,c\nd" + bs() + "e";
  var ok = streq(ical_escape_text(raw), "a" + bs() + ";b" + bs() + ",c" + bs() + "nd" + bs() + bs() + "e");
  if !streq(ical_unescape_text(ical_escape_text(raw)), raw) { ok = false; }
  if !streq(ical_unescape_text("a" + bs() + bs() + "b"), "a" + bs() + "b") { ok = false; }
  if !streq(ical_unescape_text("a" + bs() + ";b"), "a;b") { ok = false; }
  if !streq(ical_unescape_text("a" + bs() + ",b"), "a,b") { ok = false; }
  if !streq(ical_unescape_text("a" + bs() + "nb"), "a\nb") { ok = false; }
  if !streq(ical_unescape_text("a" + bs() + "Nb"), "a\nb") { ok = false; }
  if !streq(ical_unescape_text("a" + bs() + "qb"), "a" + bs() + "qb") { ok = false; }
  if !streq(ical_unescape_text("a" + bs()), "a" + bs()) { ok = false; }
  if !streq(ical_escape_text("a\r\nb"), "a" + bs() + "nb") { ok = false; }
  if !streq(ical_escape_text("plain"), "plain") { ok = false; }
  if !streq(ical_unescape_text("plain"), "plain") { ok = false; }
  return assert(ok, "TEXT escapes cover backslash, semicolon, comma, newline");
}

fn t5() -> TestResult {
  let r = ical_parse("BEGIN:VEVENT\r\nDTSTART;TZID=Europe/Athens;VALUE=DATE:20260925\r\nATTENDEE;CN=\"Doe: John\";ROLE=REQ-PARTICIPANT:mailto:j@example.com\r\nEND:VEVENT\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = ical_prop_count(&c, 0) == 2;
      if ical_prop_param_count(&c, 0, 0) != 2 { ok = false; }
      if !streq(ical_prop_param_name(&c, 0, 0, 0), "tzid") { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 0, 0), "Europe/Athens") { ok = false; }
      if !streq(ical_prop_param_name(&c, 0, 0, 1), "value") { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 0, 1), "DATE") { ok = false; }
      if !streq(ical_prop_value(&c, 0, 0), "20260925") { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 1, 0), "\"Doe: John\"") { ok = false; }
      if !streq(ical_prop_param_name(&c, 0, 1, 1), "role") { ok = false; }
      if !streq(ical_prop_value(&c, 0, 1), "mailto:j@example.com") { ok = false; }
      if ical_prop_param_count(&c, 0, 9) != 0 { ok = false; }
      if !streq(ical_prop_param_name(&c, 0, 0, 9), "") { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 0, 9), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parameters parse; quotes protect colons inside values");
}

fn t6() -> TestResult {
  var ok = parse_err_prefix("BEGIN:VCALENDAR\r\nnot a line\r\nEND:VCALENDAR\r\n");
  if !parse_err_prefix("BEGIN:VCALENDAR\r\nX Y:1\r\nEND:VCALENDAR\r\n") { ok = false; }
  if !parse_err_prefix("BEGIN:VCALENDAR\r\nX_Y:1\r\nEND:VCALENDAR\r\n") { ok = false; }
  if !parse_err_prefix("BEGIN:VCALENDAR\r\n:1\r\nEND:VCALENDAR\r\n") { ok = false; }
  if !parse_err_is("BEGIN:VCALENDAR\r\nBADLINE\r\nEND:VCALENDAR\r\n", "ical: malformed content line: BADLINE") { ok = false; }
  return assert(ok, "malformed content lines are Err with an \"ical: \" message");
}

fn t7() -> TestResult {
  var ok = parse_err_is("END:VCALENDAR\r\n", "ical: unexpected END: VCALENDAR");
  if !parse_err_is("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nEND:VCALENDAR\r\n", "ical: END:VCALENDAR does not match BEGIN:vevent") { ok = false; }
  if !parse_err_is("BEGIN:VCALENDAR\r\nVERSION:2.0", "ical: unterminated component: vcalendar") { ok = false; }
  let good = ical_parse("BEGIN:VCALENDAR\r\nEND:vcalendar\r\n");
  match good {
    Ok(c) => {
      if ical_component_count(&c) != 1 { ok = false; }
      if !streq(ical_component_name(&c, 0), "vcalendar") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "BEGIN/END pair by name; unpaired ends are Err");
}

fn t8() -> TestResult {
  var ok = parse_err_is("VERSION:2.0\r\nBEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n", "ical: property outside component: VERSION");
  let r = ical_parse("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
  match r {
    Ok(c) => { if ical_prop_count(&c, 0) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "properties outside any component are Err");
}

fn t9() -> TestResult {
  let r = ical_parse("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:a\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:b\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = ical_component_count(&c) == 4;
      if ical_child_count(&c, 0) != 2 { ok = false; }
      if ical_child(&c, 0, 0) != 1 { ok = false; }
      if ical_child(&c, 0, 1) != 3 { ok = false; }
      if ical_child_count(&c, 1) != 1 { ok = false; }
      if ical_child(&c, 1, 0) != 2 { ok = false; }
      if ical_child_count(&c, 2) != 0 { ok = false; }
      if !streq(ical_component_name(&c, 2), "valarm") { ok = false; }
      if ical_component_parent(&c, 2) != 1 { ok = false; }
      if ical_find_child(&c, 0, "VEVENT") != 1 { ok = false; }
      if ical_find_child(&c, 0, "vevent") != 1 { ok = false; }
      if ical_find_child(&c, 0, "vtimezone") != -1 { ok = false; }
      if !opt_str_is(ical_get(&c, 1, "UID"), "a") { ok = false; }
      if !opt_str_is(ical_get(&c, 3, "UID"), "b") { ok = false; }
      if !opt_str_is(ical_get(&c, 2, "ACTION"), "DISPLAY") { ok = false; }
      if !opt_str_none(ical_get(&c, 1, "ACTION")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = ical_parse("BEGIN:VTIMEZONE\r\nEND:VTIMEZONE\r\nBEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n");
  match r2 {
    Ok(c2) => {
      if ical_root_count(&c2) != 2 { ok = false; }
      if ical_root(&c2, 0) != 0 { ok = false; }
      if ical_root(&c2, 1) != 1 { ok = false; }
      if ical_child_count(&c2, -1) != 2 { ok = false; }
      if ical_find_child(&c2, -1, "VCALENDAR") != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "nested components and multiple roots form the tree");
}

fn t10() -> TestResult {
  let text = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Example//EN\r\nBEGIN:VEVENT\r\nUID:1@example.com\r\nDTSTAMP:20260925T090000Z\r\nDTSTART:20260925T100000Z\r\nDTEND:20260925T110000Z\r\nSUMMARY:Team sync\r\nDESCRIPTION:Line one\\nLine two\r\nLOCATION:Room 1\\, floor 2\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
  let r = ical_parse(text);
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(ical_serialize(&c), text);
      let again = ical_parse(ical_serialize(&c));
      match again {
        Ok(c2) => {
          if ical_component_count(&c2) != 2 { ok = false; }
          if !opt_str_is(ical_get(&c2, 1, "DESCRIPTION"), "Line one" + bs() + "nLine two") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> serialize round-trips canonical text byte-for-byte");
}

fn t11() -> TestResult {
  var c = ical_new();
  let ev = ical_add_component(&mut c, -1, "VEVENT");
  ical_add_text_prop(&mut c, ev, "SUMMARY", string.str_repeat("long meeting ", 10));
  let plain = ical_serialize(&c);
  let folded = ical_serialize_folded(&c);
  var ok = phys_lines_at_most(folded, 75);
  if !streq(ical_unfold(folded), plain) { ok = false; }
  if phys_line_count(folded) <= phys_line_count(plain) { ok = false; }
  let r = ical_parse(folded);
  match r {
    Ok(p) => {
      if !opt_str_is(ical_get(&p, 0, "summary"), string.str_repeat("long meeting ", 10)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "folded serialization stays within 75 octets per line");
}

fn t12() -> TestResult {
  let c = ical_build_event("uid-1@example.com", "20260925T090000Z", "20260925T100000Z", "20260925T110000Z", "Planning; Q3, review", "Agenda:\n1. Budget\n2. Hiring", "Room 4; East wing");
  var ok = ical_component_count(&c) == 2;
  if ical_root_count(&c) != 1 { ok = false; }
  if ical_child_count(&c, 0) != 1 { ok = false; }
  if ical_find_child(&c, 0, "VEVENT") != 1 { ok = false; }
  if !opt_str_is(ical_get(&c, 0, "VERSION"), "2.0") { ok = false; }
  if !opt_str_is(ical_get(&c, 0, "PRODID"), "-//xiom-packages//xiom.ical 0.1.0//EN") { ok = false; }
  if !opt_str_is(ical_get(&c, 1, "UID"), "uid-1@example.com") { ok = false; }
  if !opt_str_is(ical_get(&c, 1, "DTSTAMP"), "20260925T090000Z") { ok = false; }
  if !opt_str_is(ical_get(&c, 1, "DTSTART"), "20260925T100000Z") { ok = false; }
  if !opt_str_is(ical_get(&c, 1, "DTEND"), "20260925T110000Z") { ok = false; }
  if !opt_str_is(ical_get(&c, 1, "SUMMARY"), "Planning" + bs() + "; Q3" + bs() + ", review") { ok = false; }
  if !opt_str_is(ical_get_text(&c, 1, "SUMMARY"), "Planning; Q3, review") { ok = false; }
  if !opt_str_is(ical_get_text(&c, 1, "DESCRIPTION"), "Agenda:\n1. Budget\n2. Hiring") { ok = false; }
  if !opt_str_is(ical_get_text(&c, 1, "LOCATION"), "Room 4; East wing") { ok = false; }
  if ical_prop_count(&c, 1) != 7 { ok = false; }
  let s = ical_serialize(&c);
  let r = ical_parse(s);
  match r {
    Ok(p) => {
      if ical_component_count(&p) != 2 { ok = false; }
      if ical_prop_count(&p, 1) != 7 { ok = false; }
      if !opt_str_is(ical_get_text(&p, 1, "description"), "Agenda:\n1. Budget\n2. Hiring") { ok = false; }
      if !opt_str_is(ical_get(&p, 1, "dtstart"), "20260925T100000Z") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "build_event yields a minimal parseable VCALENDAR/VEVENT");
}

fn t13() -> TestResult {
  var ok = false;
  let r = ical_parse("");
  match r {
    Ok(c) => {
      ok = ical_component_count(&c) == 0;
      if ical_root_count(&c) != 0 { ok = false; }
      if ical_prop_count(&c, 0) != 0 { ok = false; }
      if !streq(ical_serialize(&c), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = ical_parse("\r\n\r\n \r\n\t\r\n");
  match r2 {
    Ok(c2) => { if ical_component_count(&c2) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !streq(ical_serialize(&ical_new()), "") { ok = false; }
  return assert(ok, "empty and blank-only streams parse as empty");
}

fn t14() -> TestResult {
  var ok = false;
  let a = ical_parse("BEGIN:VEVENT\nSUMMARY:lf\nEND:VEVENT\n");
  match a {
    Ok(c) => {
      ok = ical_component_count(&c) == 1;
      if !opt_str_is(ical_get(&c, 0, "summary"), "lf") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = ical_parse("BEGIN:VEVENT\rSUMMARY:cr\rEND:VEVENT\r");
  match b {
    Ok(c) => {
      if ical_component_count(&c) != 1 { ok = false; }
      if !opt_str_is(ical_get(&c, 0, "summary"), "cr") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let d = ical_parse("BEGIN:VEVENT\r\nSUMMARY:crlf\nEND:VEVENT");
  match d {
    Ok(c) => {
      if ical_component_count(&c) != 1 { ok = false; }
      if !opt_str_is(ical_get(&c, 0, "summary"), "crlf") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e = ical_parse("BEGIN:VEVENT\nSUMMARY:a\n b\nEND:VEVENT\n");
  match e {
    Ok(c) => { if !opt_str_is(ical_get(&c, 0, "summary"), "ab") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "LF, CR and CRLF line endings are tolerated");
}

fn t15() -> TestResult {
  let r = ical_parse("BEGIN:VEVENT\r\nSUMMARY:a\\,b\nEND:VEVENT\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = opt_str_is(ical_get(&c, 0, "summary"), "a" + bs() + ",b");
      if !opt_str_is(ical_get_text(&c, 0, "summary"), "a,b") { ok = false; }
      if !streq(ical_prop_value(&c, 0, 0), "a" + bs() + ",b") { ok = false; }
      if !streq(ical_prop_value_text(&c, 0, 0), "a,b") { ok = false; }
      if !opt_str_none(ical_get_text(&c, 0, "missing")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "raw reads keep escapes; text reads decode them");
}

fn t16() -> TestResult {
  let r = ical_parse("BEGIN:VEVENT\r\nUID:a\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nEND:VALARM\r\nEND:VEVENT\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = ical_component_count(&c) == 2;
      if ical_prop_count(&c, 0) != 1 { ok = false; }
      if ical_prop_count(&c, 1) != 1 { ok = false; }
      if !opt_str_is(ical_get(&c, 0, "uid"), "a") { ok = false; }
      if !opt_str_none(ical_get(&c, 0, "action")) { ok = false; }
      if !opt_str_is(ical_get(&c, 1, "action"), "DISPLAY") { ok = false; }
      if !opt_str_none(ical_get(&c, 1, "uid")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "property lookup is per component, children excluded");
}

fn t17() -> TestResult {
  let r = ical_parse("BEGIN:VEVENT\r\nX;A=1;B=2:v\r\nY;A=\"p;q\":w\r\nZ;TZID=\"Europe/Athens\";VALUE=DATE-TIME:20260925T100000\r\nEND:VEVENT\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = ical_prop_count(&c, 0) == 3;
      if ical_prop_param_count(&c, 0, 0) != 2 { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 0, 0), "1") { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 0, 1), "2") { ok = false; }
      if !streq(ical_prop_value(&c, 0, 0), "v") { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 1, 0), "\"p;q\"") { ok = false; }
      if !streq(ical_prop_value(&c, 0, 1), "w") { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 2, 0), "\"Europe/Athens\"") { ok = false; }
      if !streq(ical_prop_param_value(&c, 0, 2, 1), "DATE-TIME") { ok = false; }
      if !streq(ical_prop_value(&c, 0, 2), "20260925T100000") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parameter semicolons and quoted values split correctly");
}

fn t18() -> TestResult {
  var ok = parse_err_is("BEGIN:VEVENT\r\nUID;A:1\r\nEND:VEVENT\r\n", "ical: malformed parameter: UID;A:1");
  if !parse_err_prefix("BEGIN:VEVENT\r\nUID;=v:1\r\nEND:VEVENT\r\n") { ok = false; }
  if !parse_err_prefix("BEGIN:VEVENT\r\nUID;A=x\"y:v\r\nEND:VEVENT\r\n") { ok = false; }
  if !parse_err_prefix("BEGIN:VEVENT\r\nUID;A=1;:x\r\nEND:VEVENT\r\n") { ok = false; }
  return assert(ok, "malformed parameter syntax is Err");
}

fn t19() -> TestResult {
  var ok = parse_err_is("BEGIN:BAD NAME\r\nEND:BAD NAME\r\n", "ical: invalid component name: BAD NAME");
  if !parse_err_prefix("BEGIN:\r\n") { ok = false; }
  if !parse_err_prefix("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nEND:VEVENT\r\n") { ok = false; }
  let r = ical_parse("BEGIN:VCALENDAR\r\nEND:VCALENDAR");
  match r {
    Ok(c) => { if ical_component_count(&c) != 1 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "component names are validated; last line needs no newline");
}

fn t20() -> TestResult {
  var c = ical_new();
  let cal = ical_add_component(&mut c, -1, "vcalendar");
  ical_add_prop(&mut c, cal, "version", "2.0");
  let ev = ical_add_component(&mut c, cal, "vevent");
  ical_add_prop(&mut c, ev, "summary", "hi");
  var ok = ical_add_component(&mut c, -1, "bad name") == -1;
  if ical_add_component(&mut c, 99, "VEVENT") != -1 { ok = false; }
  if ical_add_prop(&mut c, 99, "X", "v") { ok = false; }
  if ical_add_prop(&mut c, ev, "bad name", "v") { ok = false; }
  if ical_add_prop(&mut c, ev, "X", "a\r\nb") { ok = false; }
  if !ical_add_text_prop(&mut c, ev, "X", "a,b") { ok = false; }
  if ical_component_count(&c) != 2 { ok = false; }
  let want = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nSUMMARY:hi\r\nX:a\\,b\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
  if !streq(ical_serialize(&c), want) { ok = false; }
  if !opt_str_is(ical_get(&c, ev, "x"), "a" + bs() + ",b") { ok = false; }
  if !opt_str_is(ical_get_text(&c, ev, "x"), "a,b") { ok = false; }
  return assert(ok, "builder serializes in order and rejects invalid input");
}

fn t21() -> TestResult {
  let v73 = string.str_repeat("a", 73);
  let v74 = string.str_repeat("a", 74);
  var c1 = ical_new();
  let e1 = ical_add_component(&mut c1, -1, "VTEST");
  ical_add_text_prop(&mut c1, e1, "X", v73);
  var c2 = ical_new();
  let e2 = ical_add_component(&mut c2, -1, "VTEST");
  ical_add_text_prop(&mut c2, e2, "X", v74);
  let f1 = ical_serialize_folded(&c1);
  let f2 = ical_serialize_folded(&c2);
  var ok = phys_line_count(f1) == 3;
  if !phys_lines_at_most(f1, 75) { ok = false; }
  if !streq(ical_unfold(f1), ical_serialize(&c1)) { ok = false; }
  if phys_line_count(f2) != 4 { ok = false; }
  if !phys_lines_at_most(f2, 75) { ok = false; }
  if !streq(ical_unfold(f2), ical_serialize(&c2)) { ok = false; }
  let r2 = ical_parse(f2);
  match r2 {
    Ok(p) => { if !opt_str_is(ical_get(&p, 0, "x"), v74) { ok = false; } },
    Err(_) => { ok = false; },
  }
  let uni = string.str_repeat("α", 40);
  var c3 = ical_new();
  let e3 = ical_add_component(&mut c3, -1, "VTEST");
  ical_add_text_prop(&mut c3, e3, "X", uni);
  let f3 = ical_serialize_folded(&c3);
  if !phys_lines_at_most(f3, 75) { ok = false; }
  if !streq(ical_unfold(f3), ical_serialize(&c3)) { ok = false; }
  let r3 = ical_parse(f3);
  match r3 {
    Ok(p) => { if !opt_str_is(ical_get_text(&p, 0, "x"), uni) { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "folding honors 75-octet lines and UTF-8 boundaries");
}

fn t22() -> TestResult {
  let text = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nATTENDEE;CN=\"Doe: John\";ROLE=REQ-PARTICIPANT:mailto:j@example.com\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
  let r = ical_parse(text);
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(ical_serialize(&c), text);
      if ical_prop_param_count(&c, 1, 0) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parameters survive parse -> serialize round-trip");
}

fn main() -> Int {
  io.println("=== xiom.ical conformance tests ===");
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
    io.println("xiom.ical: all tests passed");
  } else {
    io.println("xiom.ical: tests failed");
  }
  return failed;
}
