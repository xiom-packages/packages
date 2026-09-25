// XIOM -- xiom.systemd conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: typical two-section documents, full-line comments of both kinds
// with inline markers kept as data, leading-space trimming and empty values,
// continuation joins (values, repeated joins, comment swallowing), duplicate
// keys preserved with first/last accessors, reopened sections merged into one
// range, CRLF input, blank and indented lines, malformed/empty section
// headers, keys before the first section, missing '=', empty and malformed
// keys, continuation at end of input, C0 control bytes, lone CR, canonical
// emit layout, emit/parse round trip with idempotence, empty document
// handling, index accessor bounds and case sensitivity.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/opt_str_is/str_at instead of `==`.

module systemd_tests
use xiom.io; use xiom.test; use xiom.systemd;
use xiom.string;
use xiom.string.compare;

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

fn str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let got: Str = v[i];
  return streq(got, want);
}

fn sec_at(u: &Unit, i: Int, want: Str) -> Bool {
  return opt_str_is(unit_section_name(u, i), want);
}

// True when `text` fails to parse with a message starting with `prefix`.
fn parse_err_prefix(text: Str, prefix: Str) -> Bool {
  let r = unit_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = unit_parse("[Unit]\nDescription=Demo\nAfter=network.target\n\n[Service]\nExecStart=/bin/true\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 2;
      if unit_key_count(&u) != 3 { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Description"), "Demo") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "After"), "network.target") { ok = false; }
      if !opt_str_is(unit_get(&u, "Service", "ExecStart"), "/bin/true") { ok = false; }
      if !opt_str_none(unit_get(&u, "Unit", "ExecStart")) { ok = false; }
      if !opt_str_none(unit_get(&u, "Install", "WantedBy")) { ok = false; }
      if !sec_at(&u, 0, "Unit") { ok = false; }
      if !sec_at(&u, 1, "Service") { ok = false; }
      if unit_section_key_count(&u, 0) != 2 { ok = false; }
      if unit_section_key_count(&u, 1) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse a typical unit with two sections");
}

fn t2() -> TestResult {
  let r = unit_parse("# top\n; top2\n   # indented\n\n[Unit]\n#Description=no\n;After=no\nDescription=Demo\nExecStart=/bin/echo # not a comment ; neither\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 1;
      if unit_key_count(&u) != 2 { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Description"), "Demo") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "ExecStart"), "/bin/echo # not a comment ; neither") { ok = false; }
      if !opt_str_none(unit_get(&u, "Unit", "After")) { ok = false; }
      var ks = unit_section_keys(&u, 0);
      if ks.len() != 2 { ok = false; }
      if !str_at(&ks, 0, "Description") { ok = false; }
      if !str_at(&ks, 1, "ExecStart") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full-line # and ; comments are skipped; inline markers are data");
}

fn t3() -> TestResult {
  let r = unit_parse("[Unit]\nDescription=   spaced   \nEmpty=\nBlank=\t  \nTabs=\tvalue\t\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 1;
      if unit_key_count(&u) != 4 { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Description"), "spaced   ") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Empty"), "") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Blank"), "") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Tabs"), "value\t") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "leading value whitespace is trimmed, trailing whitespace is kept");
}

fn t4() -> TestResult {
  let r = unit_parse("[Service]\nExecStart=/bin/echo one \\\n  two\nDescription=multi\\\nline\\\nvalue\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 1;
      if unit_key_count(&u) != 2 { ok = false; }
      if !opt_str_is(unit_get(&u, "Service", "ExecStart"), "/bin/echo one   two") { ok = false; }
      if !opt_str_is(unit_get(&u, "Service", "Description"), "multilinevalue") { ok = false; }
      var ks = unit_section_keys(&u, 0);
      if !str_at(&ks, 0, "ExecStart") { ok = false; }
      if !str_at(&ks, 1, "Description") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "trailing backslash joins lines with no inserted separator");
}

fn t5() -> TestResult {
  let r = unit_parse("[Unit]\nDescription=one\\\ntwo\n# note \\\nDescription=hidden\nAfter=x\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 1;
      if unit_key_count(&u) != 2 { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Description"), "onetwo") { ok = false; }
      if !opt_str_is(unit_get_last(&u, "Unit", "Description"), "onetwo") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "After"), "x") { ok = false; }
      var ks = unit_section_keys(&u, 0);
      if ks.len() != 2 { ok = false; }
      if !str_at(&ks, 0, "Description") { ok = false; }
      if !str_at(&ks, 1, "After") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a trailing backslash also continues a comment line");
}

fn t6() -> TestResult {
  let r = unit_parse("[Unit]\nAfter=a\nAfter=b\nAfter=c\nWants=w\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_key_count(&u) == 4;
      if unit_section_key_count(&u, 0) != 4 { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "After"), "a") { ok = false; }
      if !opt_str_is(unit_get_last(&u, "Unit", "After"), "c") { ok = false; }
      if !opt_str_is(unit_key_at(&u, 1), "After") { ok = false; }
      if !opt_str_is(unit_value_at(&u, 1), "b") { ok = false; }
      if !opt_str_is(unit_value_at(&u, 3), "w") { ok = false; }
      var ks = unit_section_keys(&u, 0);
      if ks.len() != 4 { ok = false; }
      if !str_at(&ks, 0, "After") { ok = false; }
      if !str_at(&ks, 1, "After") { ok = false; }
      if !str_at(&ks, 2, "After") { ok = false; }
      if !str_at(&ks, 3, "Wants") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate keys are preserved in order with first/last accessors");
}

fn t7() -> TestResult {
  let r = unit_parse("[A]\nx=1\n[B]\ny=2\n[A]\nz=3\n[B]\nw=4\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 2;
      if !sec_at(&u, 0, "A") { ok = false; }
      if !sec_at(&u, 1, "B") { ok = false; }
      if unit_key_count(&u) != 4 { ok = false; }
      var ka = unit_section_keys(&u, 0);
      if ka.len() != 2 { ok = false; }
      if !str_at(&ka, 0, "x") { ok = false; }
      if !str_at(&ka, 1, "z") { ok = false; }
      var kb = unit_section_keys(&u, 1);
      if kb.len() != 2 { ok = false; }
      if !str_at(&kb, 0, "y") { ok = false; }
      if !str_at(&kb, 1, "w") { ok = false; }
      if !opt_str_is(unit_get(&u, "A", "z"), "3") { ok = false; }
      if !opt_str_is(unit_get(&u, "B", "w"), "4") { ok = false; }
      if !opt_str_is(unit_key_at(&u, 0), "x") { ok = false; }
      if !opt_str_is(unit_value_at(&u, 1), "3") { ok = false; }
      if !opt_str_is(unit_key_at(&u, 2), "y") { ok = false; }
      if !opt_str_is(unit_value_at(&u, 3), "4") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a repeated section header reopens one contiguous section range");
}

fn t8() -> TestResult {
  let r = unit_parse("[Unit]\r\nDescription=win\r\nPath=C:\\tmp\r\nWants=keep \r\n\r\n[Service]\r\nExecStart=/bin/true\r\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 2;
      if unit_key_count(&u) != 4 { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Description"), "win") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Path"), "C:\\tmp") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Wants"), "keep ") { ok = false; }
      if !opt_str_is(unit_get(&u, "Service", "ExecStart"), "/bin/true") { ok = false; }
      if !sec_at(&u, 0, "Unit") { ok = false; }
      if !sec_at(&u, 1, "Service") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF input parses and the CR bytes are stripped");
}

fn t9() -> TestResult {
  let r = unit_parse("\n   \n\t\n  [Unit]  \n\tDescription=ok\n  After=a\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 1;
      if unit_key_count(&u) != 2 { ok = false; }
      if !sec_at(&u, 0, "Unit") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Description"), "ok") { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "After"), "a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "blank lines are skipped and leading line whitespace is ignored");
}

fn t10() -> TestResult {
  var ok = parse_err_prefix("[]", "systemd: empty section name");
  if !parse_err_prefix("[  ]", "systemd: malformed section header") { ok = false; }
  if !parse_err_prefix("[Unit", "systemd: malformed section header") { ok = false; }
  if !parse_err_prefix("[Un it]", "systemd: malformed section header") { ok = false; }
  if !parse_err_prefix("[Unit]junk", "systemd: malformed section header") { ok = false; }
  if !parse_err_prefix("[[Unit]]", "systemd: malformed section header") { ok = false; }
  if !parse_err_prefix("[]x", "systemd: malformed section header") { ok = false; }
  return assert(ok, "empty and malformed section headers are Err");
}

fn t11() -> TestResult {
  var ok = parse_err_prefix("Description=x", "systemd: key before any section");
  if !parse_err_prefix("# c\n\nDescription=x\n[Unit]\n", "systemd: key before any section") { ok = false; }
  if !parse_err_prefix("Key=1\n[Unit]\n", "systemd: key before any section") { ok = false; }
  return assert(ok, "a key line before the first section header is Err");
}

fn t12() -> TestResult {
  var ok = parse_err_prefix("[Unit]\njustakey\n", "systemd: line without '='");
  if !parse_err_prefix("[Unit]\nKey value\n", "systemd: line without '='") { ok = false; }
  if !parse_err_prefix("[Unit]\n=value\n", "systemd: empty key in line") { ok = false; }
  if !parse_err_prefix("[Unit]\n   =\n", "systemd: empty key in line") { ok = false; }
  if !parse_err_prefix("[Unit]\nKey name=v\n", "systemd: malformed key in line") { ok = false; }
  if !parse_err_prefix("[Unit]\nKey\tname=v\n", "systemd: malformed key in line") { ok = false; }
  return assert(ok, "missing '=', empty keys and whitespace-bearing keys are Err");
}

fn t13() -> TestResult {
  var ok = parse_err_prefix("[Unit]\nKey=a\\", "systemd: continuation at end of input");
  if !parse_err_prefix("[Unit]\nKey=a\\\n", "systemd: continuation at end of input") { ok = false; }
  if !parse_err_prefix("[Unit]\nKey=a\\\r\n", "systemd: continuation at end of input") { ok = false; }
  let r = unit_parse("[Unit]\nKey=a\\\n\n");
  match r {
    Ok(u) => {
      if unit_key_count(&u) != 1 { ok = false; }
      if !opt_str_is(unit_get(&u, "Unit", "Key"), "a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a continuation on the final physical line is Err; a blank line completes it");
}

fn t14() -> TestResult {
  var ok = parse_err_prefix("[Unit]\nKey=a\x01b\n", "systemd: control byte 0x01");
  if !parse_err_prefix("[Unit]\nKey=a\x1fb\n", "systemd: control byte 0x1f") { ok = false; }
  if !parse_err_prefix("# comment\x07\n[Unit]\n", "systemd: control byte 0x07") { ok = false; }
  if !parse_err_prefix("[Unit]\nKey=a\x0bb\n", "systemd: control byte 0x0b") { ok = false; }
  return assert(ok, "C0 control bytes anywhere in the input are Err");
}

fn t15() -> TestResult {
  var ok = parse_err_prefix("[Unit]\nKey=x\r", "systemd: control byte 0x0d");
  if !parse_err_prefix("[Unit]\nKey=a\rb\n", "systemd: control byte 0x0d") { ok = false; }
  if !parse_err_prefix("[Unit]\rKey=x\n", "systemd: control byte 0x0d") { ok = false; }
  return assert(ok, "a CR outside a CRLF pair is Err");
}

fn t16() -> TestResult {
  let r = unit_parse("[B]\nq=1\n\n[A]\np=2\nk=3\nk=4\n\n[Empty]\n");
  var ok = false;
  match r {
    Ok(u) => {
      let got = unit_emit(&u);
      let want = "[B]\nq=1\n\n[A]\np=2\nk=3\nk=4\n\n[Empty]";
      ok = streq(got, want);
      let r2 = unit_parse(got);
      match r2 {
        Ok(u2) => {
          if unit_section_count(&u2) != 3 { ok = false; }
          if !sec_at(&u2, 2, "Empty") { ok = false; }
          if unit_section_key_count(&u2, 2) != 0 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit writes canonical LF layout with one blank line between sections");
}

fn t17() -> TestResult {
  let r1 = unit_parse("[Unit]\r\nDescription=one\\\r\ntwo\r\nAfter=a\r\nAfter=b\r\nEmpty=\r\n\r\n[Service]\r\nExecStart=/bin/true   \r\n");
  var ok = false;
  match r1 {
    Ok(u1) => {
      let e1 = unit_emit(&u1);
      let r2 = unit_parse(e1);
      match r2 {
        Ok(u2) => {
          ok = unit_section_count(&u2) == 2;
          if unit_key_count(&u2) != 5 { ok = false; }
          if !opt_str_is(unit_get(&u2, "Unit", "Description"), "onetwo") { ok = false; }
          if !opt_str_is(unit_get(&u2, "Unit", "After"), "a") { ok = false; }
          if !opt_str_is(unit_get_last(&u2, "Unit", "After"), "b") { ok = false; }
          if !opt_str_is(unit_get(&u2, "Unit", "Empty"), "") { ok = false; }
          if !opt_str_is(unit_get(&u2, "Service", "ExecStart"), "/bin/true   ") { ok = false; }
          var ks = unit_section_keys(&u2, 0);
          if ks.len() != 4 { ok = false; }
          if !str_at(&ks, 0, "Description") { ok = false; }
          if !str_at(&ks, 1, "After") { ok = false; }
          if !str_at(&ks, 2, "After") { ok = false; }
          if !str_at(&ks, 3, "Empty") { ok = false; }
          let e2 = unit_emit(&u2);
          if !streq(e1, e2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse round trip is stable and idempotent");
}

fn t18() -> TestResult {
  let r1 = unit_parse("");
  var ok = false;
  match r1 {
    Ok(u1) => {
      ok = unit_section_count(&u1) == 0;
      if unit_key_count(&u1) != 0 { ok = false; }
      if !streq(unit_emit(&u1), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = unit_parse("# only a comment\n; and another\n\n   \n\t\n");
  match r2 {
    Ok(u2) => {
      if unit_section_count(&u2) != 0 { ok = false; }
      if unit_key_count(&u2) != 0 { ok = false; }
      if !streq(unit_emit(&u2), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and comment-only documents parse to zero sections and emit nothing");
}

fn t19() -> TestResult {
  let r = unit_parse("[A]\nx=1\ny=2\n[B]\nz=3\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = unit_section_count(&u) == 2;
      if !opt_str_is(unit_section_name(&u, 0), "A") { ok = false; }
      if !opt_str_is(unit_section_name(&u, 1), "B") { ok = false; }
      if !opt_str_none(unit_section_name(&u, 2)) { ok = false; }
      if !opt_str_none(unit_section_name(&u, -1)) { ok = false; }
      if unit_section_key_count(&u, 0) != 2 { ok = false; }
      if unit_section_key_count(&u, 1) != 1 { ok = false; }
      if unit_section_key_count(&u, 2) != -1 { ok = false; }
      if unit_section_key_count(&u, -1) != -1 { ok = false; }
      var ka = unit_section_keys(&u, 0);
      if ka.len() != 2 { ok = false; }
      if !str_at(&ka, 0, "x") { ok = false; }
      if !str_at(&ka, 1, "y") { ok = false; }
      var kbad = unit_section_keys(&u, 7);
      if kbad.len() != 0 { ok = false; }
      if !opt_str_is(unit_section_value_at(&u, 0, 0), "1") { ok = false; }
      if !opt_str_is(unit_section_value_at(&u, 0, 1), "2") { ok = false; }
      if !opt_str_none(unit_section_value_at(&u, 0, 2)) { ok = false; }
      if !opt_str_none(unit_section_value_at(&u, 5, 0)) { ok = false; }
      if !opt_str_is(unit_key_at(&u, 2), "z") { ok = false; }
      if !opt_str_is(unit_value_at(&u, 2), "3") { ok = false; }
      if !opt_str_none(unit_key_at(&u, 3)) { ok = false; }
      if !opt_str_none(unit_value_at(&u, -1)) { ok = false; }
      if unit_section_index(&u, "A") != 0 { ok = false; }
      if unit_section_index(&u, "B") != 1 { ok = false; }
      if unit_section_index(&u, "C") != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "index accessors return entries and bound-check cleanly");
}

fn t20() -> TestResult {
  let r = unit_parse("[Unit]\nDescription=Demo\n");
  var ok = false;
  match r {
    Ok(u) => {
      ok = opt_str_is(unit_get(&u, "Unit", "Description"), "Demo");
      if !opt_str_none(unit_get(&u, "unit", "Description")) { ok = false; }
      if !opt_str_none(unit_get(&u, "Unit", "description")) { ok = false; }
      if !opt_str_none(unit_get(&u, "UNIT", "DESCRIPTION")) { ok = false; }
      if unit_section_index(&u, "unit") != -1 { ok = false; }
      if unit_section_index(&u, "Unit") != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "section names and keys are byte-exact and case-sensitive");
}

fn main() -> Int {
  io.println("=== xiom.systemd conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.systemd: all tests passed");
  } else {
    io.println("xiom.systemd: tests failed");
  }
  return failed;
}
