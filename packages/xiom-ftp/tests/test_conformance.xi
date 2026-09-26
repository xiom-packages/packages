// XIOM -- xiom.ftp conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 10. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green),
// dispatching t1()..t24() directly (no Vec[fn]). Every Str comparison goes
// through compare.str_compare (BUG 17: `==` on Str values read from a Vec
// lowers to a pointer comparison); Result payloads are read through
// .is_ok/.value/.error with typed locals; Vec[Int] reads are bound to typed
// locals before use.

module ftp_tests
use xiom.io; use xiom.test;
use xiom.ftp;
use xiom.string.compare;
use xiom.string.builder;

// --------------------------------------------------
//  String and byte helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// `s` repeated `n` times (used to build cap-sized fixtures).
fn rep(s: Str, n: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    builder.sb_push_str(&mut out, s);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// prefix + one raw byte + suffix (control-byte fixtures).
fn with_byte(prefix: Str, b: Int, suffix: Str) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, prefix);
  out.push(b as UInt8);
  builder.sb_push_str(&mut out, suffix);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Command accessor helpers (each parses once)
// --------------------------------------------------

fn cerr_of(line: Str) -> Str {
  let r = ftp_parse_command(line);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn cname_of(line: Str) -> Str {
  let r = ftp_parse_command(line);
  if !r.is_ok {
    return "";
  }
  let c: Command = r.value;
  return ftp_command_name(&c);
}

fn carg_of(line: Str) -> Str {
  let r = ftp_parse_command(line);
  if !r.is_ok {
    return "";
  }
  let c: Command = r.value;
  return ftp_command_argument(&c);
}

fn craw_of(line: Str) -> Str {
  let r = ftp_parse_command(line);
  if !r.is_ok {
    return "";
  }
  let c: Command = r.value;
  return ftp_command_raw(&c);
}

fn cemit_of(line: Str) -> Str {
  let r = ftp_parse_command(line);
  if !r.is_ok {
    return "";
  }
  let c: Command = r.value;
  return ftp_emit_command(&c);
}

// which: 0 = type code, 1 = mode code, 2 = stru code.
fn ccode_of(line: Str, which: Int) -> Str {
  let r = ftp_parse_command(line);
  if !r.is_ok {
    return "";
  }
  let c: Command = r.value;
  if which == 0 {
    return ftp_type_code(&c);
  }
  if which == 1 {
    return ftp_mode_code(&c);
  }
  return ftp_stru_code(&c);
}

fn cport_of(line: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let r = ftp_parse_command(line);
  if !r.is_ok {
    return out;
  }
  let c: Command = r.value;
  return ftp_port_octets(&c);
}

// True when the line parses and re-emits byte-for-byte.
fn cmd_roundtrip(line: Str) -> Bool {
  let r = ftp_parse_command(line);
  if !r.is_ok {
    return false;
  }
  let c: Command = r.value;
  let e = ftp_emit_command(&c);
  return str_eq(e, line);
}

// --------------------------------------------------
//  Reply accessor helpers (each parses once)
// --------------------------------------------------

fn rerr_of(s: Str) -> Str {
  let r = ftp_parse_response(s);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn rcode_of(s: Str) -> Int {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return -1;
  }
  let v: Response = r.value;
  return ftp_response_code(&v);
}

fn rclass_of(s: Str) -> Int {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return -1;
  }
  let v: Response = r.value;
  return ftp_response_class(&v);
}

fn rmulti_of(s: Str) -> Bool {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return false;
  }
  let v: Response = r.value;
  return ftp_response_is_multiline(&v);
}

fn rcount_of(s: Str) -> Int {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return -1;
  }
  let v: Response = r.value;
  return ftp_response_line_count(&v);
}

fn rline_of(s: Str, i: Int) -> Str {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return "";
  }
  let v: Response = r.value;
  return ftp_response_line(&v, i);
}

fn rlcode_of(s: Str, i: Int) -> Int {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return -1;
  }
  let v: Response = r.value;
  return ftp_response_line_code(&v, i);
}

fn rtext_of(s: Str) -> Str {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return "";
  }
  let v: Response = r.value;
  return ftp_response_text(&v);
}

fn rraw_of(s: Str) -> Str {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return "";
  }
  let v: Response = r.value;
  return ftp_response_raw(&v);
}

fn remit_of(s: Str) -> Str {
  let r = ftp_parse_response(s);
  if !r.is_ok {
    return "";
  }
  let v: Response = r.value;
  return ftp_emit_response(&v);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let s = "USER alice\r\n";
  var ok = str_eq(cname_of(s), "USER");
  if !str_eq(carg_of(s), "alice") { ok = false; }
  if !str_eq(craw_of(s), s) { ok = false; }
  if !str_eq(cemit_of(s), s) { ok = false; }
  return assert(ok, "USER: name/argument/raw/emit");
}

fn t2() -> TestResult {
  var ok = str_eq(cname_of("user alice\r\n"), "USER");
  if !str_eq(cemit_of("user alice\r\n"), "USER alice\r\n") { ok = false; }
  if !str_eq(cname_of("type a n\r\n"), "TYPE") { ok = false; }
  if !str_eq(carg_of("type a n\r\n"), "A N") { ok = false; }
  if !str_eq(ccode_of("type a n\r\n", 0), "A") { ok = false; }
  if !str_eq(cemit_of("type a n\r\n"), "TYPE A N\r\n") { ok = false; }
  if !str_eq(carg_of("mode b\r\n"), "B") { ok = false; }
  if !str_eq(ccode_of("mode b\r\n", 1), "B") { ok = false; }
  if !str_eq(carg_of("stru p\r\n"), "P") { ok = false; }
  if !str_eq(ccode_of("stru p\r\n", 2), "P") { ok = false; }
  return assert(ok, "lowercase verbs and code canonicalization");
}

fn t3() -> TestResult {
  var ok = cmd_roundtrip("PWD\r\n");
  if !cmd_roundtrip("PASV\r\n") { ok = false; }
  if !cmd_roundtrip("QUIT\r\n") { ok = false; }
  if !cmd_roundtrip("FEAT\r\n") { ok = false; }
  if !cmd_roundtrip("CDUP\r\n") { ok = false; }
  if !cmd_roundtrip("ABOR\r\n") { ok = false; }
  if !cmd_roundtrip("SYST\r\n") { ok = false; }
  if !str_eq(carg_of("PWD\r\n"), "") { ok = false; }
  if !str_eq(cname_of("pwd\r\n"), "PWD") { ok = false; }
  return assert(ok, "no-argument verbs round-trip");
}

fn t4() -> TestResult {
  var ok = str_eq(cerr_of("USER a"), "ftp: missing CRLF");
  if !str_eq(cerr_of("USER a\n"), "ftp: missing CRLF") { ok = false; }
  if !str_eq(cerr_of("USER a\r"), "ftp: missing CRLF") { ok = false; }
  if !str_eq(cerr_of(""), "ftp: missing CRLF") { ok = false; }
  if !str_eq(cerr_of("\r\n"), "ftp: empty command") { ok = false; }
  return assert(ok, "CRLF framing and empty command");
}

fn t5() -> TestResult {
  var ok = str_eq(cerr_of("SITE HELP\r\n"), "ftp: unknown verb: SITE");
  if !str_eq(cerr_of("NOOP\r\n"), "ftp: unknown verb: NOOP") { ok = false; }
  if !str_eq(cerr_of("1USER a\r\n"), "ftp: bad verb: 1USER") { ok = false; }
  if !str_eq(cerr_of(" PWD\r\n"), "ftp: bad verb: ") { ok = false; }
  if !str_eq(cerr_of("PWD/\r\n"), "ftp: bad argument shape: PWD") { ok = false; }
  return assert(ok, "unknown and malformed verbs");
}

fn t6() -> TestResult {
  var ok = str_eq(cerr_of("USER\r\n"), "ftp: bad argument shape: USER");
  if !str_eq(cerr_of("CWD\r\n"), "ftp: bad argument shape: CWD") { ok = false; }
  if !str_eq(cerr_of("PWD /tmp\r\n"), "ftp: bad argument shape: PWD") { ok = false; }
  if !str_eq(cerr_of("PWD \r\n"), "ftp: bad argument shape: PWD") { ok = false; }
  if !str_eq(cerr_of("STAT \r\n"), "ftp: bad argument shape: STAT") { ok = false; }
  if !str_eq(carg_of("STAT\r\n"), "") { ok = false; }
  if !str_eq(carg_of("STAT /pub\r\n"), "/pub") { ok = false; }
  if !str_eq(carg_of("LIST\r\n"), "") { ok = false; }
  if !str_eq(carg_of("LIST /tmp\r\n"), "/tmp") { ok = false; }
  if !str_eq(carg_of("PASS \r\n"), "") { ok = false; }
  if !str_eq(cerr_of("PASS\r\n"), "ftp: bad argument shape: PASS") { ok = false; }
  return assert(ok, "required/optional/no-argument arity");
}

fn t7() -> TestResult {
  let s = "PORT 192,168,0,1,4,1\r\n";
  var ok = cmd_roundtrip(s);
  let v = cport_of(s);
  if v.len() != 6 { ok = false; }
  if v.len() == 6 {
    let o0: Int = v[0];
    let o5: Int = v[5];
    if o0 != 192 { ok = false; }
    if o5 != 1 { ok = false; }
  }
  let z = cport_of("PORT 010,0,0,0,0,0\r\n");
  if z.len() != 6 { ok = false; }
  if z.len() == 6 {
    let z0: Int = z[0];
    if z0 != 10 { ok = false; }
  }
  if !str_eq(carg_of("PORT 010,0,0,0,0,0\r\n"), "10,0,0,0,0,0") { ok = false; }
  if cport_of("USER alice\r\n").len() != 0 { ok = false; }
  if cport_of("PORT 255,255,255,255,255,255\r\n").len() != 6 { ok = false; }
  return assert(ok, "PORT octet parsing and canonicalization");
}

fn t8() -> TestResult {
  var ok = str_eq(cerr_of("PORT 1,2,3,4,5\r\n"), "ftp: bad argument shape: PORT");
  if !str_eq(cerr_of("PORT 1,2,3,4,5,6,7\r\n"), "ftp: bad argument shape: PORT") { ok = false; }
  if !str_eq(cerr_of("PORT 256,0,0,0,0,0\r\n"), "ftp: bad argument shape: PORT") { ok = false; }
  if !str_eq(cerr_of("PORT 1,,3,4,5,6\r\n"), "ftp: bad argument shape: PORT") { ok = false; }
  if !str_eq(cerr_of("PORT -1,2,3,4,5,6\r\n"), "ftp: bad argument shape: PORT") { ok = false; }
  if !str_eq(cerr_of("PORT 1,2,3,4,5,6,\r\n"), "ftp: bad argument shape: PORT") { ok = false; }
  if !str_eq(cerr_of("PORT 1234,2,3,4,5,6\r\n"), "ftp: bad argument shape: PORT") { ok = false; }
  return assert(ok, "PORT octet validation errors");
}

fn t9() -> TestResult {
  var ok = str_eq(ccode_of("TYPE A\r\n", 0), "A");
  if !cmd_roundtrip("TYPE A\r\n") { ok = false; }
  if !str_eq(carg_of("TYPE A N\r\n"), "A N") { ok = false; }
  if !str_eq(carg_of("type a t\r\n"), "A T") { ok = false; }
  if !str_eq(ccode_of("TYPE E\r\n", 0), "E") { ok = false; }
  if !str_eq(ccode_of("TYPE I\r\n", 0), "I") { ok = false; }
  if !str_eq(carg_of("TYPE L 8\r\n"), "L 8") { ok = false; }
  if !str_eq(carg_of("TYPE l 1024\r\n"), "L 1024") { ok = false; }
  if !str_eq(ccode_of("TYPE L 8\r\n", 0), "L") { ok = false; }
  if !str_eq(cerr_of("TYPE X\r\n"), "ftp: bad argument shape: TYPE") { ok = false; }
  if !str_eq(cerr_of("TYPE A Q\r\n"), "ftp: bad argument shape: TYPE") { ok = false; }
  if !str_eq(cerr_of("TYPE I N\r\n"), "ftp: bad argument shape: TYPE") { ok = false; }
  if !str_eq(cerr_of("TYPE L\r\n"), "ftp: bad argument shape: TYPE") { ok = false; }
  if !str_eq(cerr_of("TYPE L 0\r\n"), "ftp: bad argument shape: TYPE") { ok = false; }
  if !str_eq(cerr_of("TYPE L 0123\r\n"), "ftp: bad argument shape: TYPE") { ok = false; }
  if !str_eq(cerr_of("TYPE L 1234567\r\n"), "ftp: bad argument shape: TYPE") { ok = false; }
  return assert(ok, "TYPE A/I/E/L forms");
}

fn t10() -> TestResult {
  var ok = str_eq(ccode_of("MODE S\r\n", 1), "S");
  if !str_eq(ccode_of("mode b\r\n", 1), "B") { ok = false; }
  if !str_eq(ccode_of("MODE C\r\n", 1), "C") { ok = false; }
  if !str_eq(cerr_of("MODE X\r\n"), "ftp: bad argument shape: MODE") { ok = false; }
  if !str_eq(cerr_of("MODE S B\r\n"), "ftp: bad argument shape: MODE") { ok = false; }
  if !str_eq(ccode_of("STRU F\r\n", 2), "F") { ok = false; }
  if !str_eq(ccode_of("stru r\r\n", 2), "R") { ok = false; }
  if !str_eq(ccode_of("STRU P\r\n", 2), "P") { ok = false; }
  if !str_eq(cerr_of("STRU X\r\n"), "ftp: bad argument shape: STRU") { ok = false; }
  if !str_eq(ccode_of("TYPE I\r\n", 1), "") { ok = false; }
  if !str_eq(ccode_of("MODE S\r\n", 0), "") { ok = false; }
  return assert(ok, "MODE and STRU codes");
}

fn t11() -> TestResult {
  let tab = with_byte("USER ali", 9, "ce\r\n");
  var ok = str_eq(cerr_of(tab), "ftp: control byte in command");
  let soh = with_byte("USER a", 1, "b\r\n");
  if !str_eq(cerr_of(soh), "ftp: control byte in command") { ok = false; }
  let del = with_byte("USER a", 127, "b\r\n");
  if !str_eq(cerr_of(del), "ftp: control byte in command") { ok = false; }
  let cr = with_byte("USER a", 13, "b\r\n");
  if !str_eq(cerr_of(cr), "ftp: control byte in command") { ok = false; }
  return assert(ok, "control bytes rejected in commands");
}

fn t12() -> TestResult {
  let cap = "USER " + rep("a", 505) + "\r\n";
  var ok = cap.len() == 512;
  if !cmd_roundtrip(cap) { ok = false; }
  let over = "USER " + rep("a", 506) + "\r\n";
  if !str_eq(cerr_of(over), "ftp: command too long") { ok = false; }
  let rcap = "220 " + rep("x", 8186) + "\r\n";
  if rcap.len() != 8192 { ok = false; }
  if !str_eq(rtext_of(rcap), rep("x", 8186)) { ok = false; }
  let rover = "220 " + rep("x", 8187) + "\r\n";
  if !str_eq(rerr_of(rover), "ftp: response too long") { ok = false; }
  return assert(ok, "command and response length caps");
}

fn t13() -> TestResult {
  let s = "220 Service ready\r\n";
  var ok = rcode_of(s) == 220;
  if rclass_of(s) != 2 { ok = false; }
  if rmulti_of(s) { ok = false; }
  if rcount_of(s) != 1 { ok = false; }
  if !str_eq(rline_of(s, 0), "220 Service ready") { ok = false; }
  if !str_eq(rtext_of(s), "Service ready") { ok = false; }
  if !str_eq(rraw_of(s), s) { ok = false; }
  if !str_eq(remit_of(s), s) { ok = false; }
  return assert(ok, "single-line reply 220");
}

fn t14() -> TestResult {
  let s = "230-User logged in\r\n230-\r\n230 Welcome\r\n";
  var ok = rcode_of(s) == 230;
  if !rmulti_of(s) { ok = false; }
  if rcount_of(s) != 3 { ok = false; }
  if !str_eq(rline_of(s, 2), "230 Welcome") { ok = false; }
  if !str_eq(rtext_of(s), "User logged in") { ok = false; }
  if rlcode_of(s, 0) != 230 { ok = false; }
  if rlcode_of(s, 1) != 230 { ok = false; }
  if !str_eq(rline_of(s, 1), "230-") { ok = false; }
  if rclass_of(s) != 2 { ok = false; }
  if !str_eq(remit_of(s), s) { ok = false; }
  return assert(ok, "multiline reply with matching codes");
}

fn t15() -> TestResult {
  let s = "211-Features:\r\n SIZE\r\n MDTM\r\n211 End\r\n";
  var ok = rcount_of(s) == 4;
  if !rmulti_of(s) { ok = false; }
  if !str_eq(rline_of(s, 1), " SIZE") { ok = false; }
  if rlcode_of(s, 1) != -1 { ok = false; }
  if rlcode_of(s, 3) != 211 { ok = false; }
  if !str_eq(rtext_of(s), "Features:") { ok = false; }
  if !str_eq(remit_of(s), s) { ok = false; }
  return assert(ok, "FEAT multiline with uncoded lines");
}

fn t16() -> TestResult {
  var ok = str_eq(rerr_of("220-Welcome\r\n230 Done\r\n"), "ftp: multiline code mismatch: 230 Done");
  if !str_eq(rerr_of("211-A\r\n200 B\r\n"), "ftp: multiline code mismatch: 200 B") { ok = false; }
  if !str_eq(rerr_of("220-A\r\n221-B\r\n220 Z\r\n"), "ftp: multiline code mismatch: 221-B") { ok = false; }
  return assert(ok, "multiline terminator code must match");
}

fn t17() -> TestResult {
  var ok = str_eq(rerr_of("220-Hello\r\nmore text\r\n"), "ftp: unterminated multiline response");
  if !str_eq(rerr_of("220-\r\n"), "ftp: unterminated multiline response") { ok = false; }
  if !str_eq(rerr_of("211-Features:\r\n SIZE\r\n"), "ftp: unterminated multiline response") { ok = false; }
  return assert(ok, "unterminated multiline blocks");
}

fn t18() -> TestResult {
  var ok = str_eq(rerr_of("22x Service\r\n"), "ftp: bad code digits: 22x Service");
  if !str_eq(rerr_of("12 Service\r\n"), "ftp: bad code digits: 12 Service") { ok = false; }
  if !str_eq(rerr_of("000 Nothing\r\n"), "ftp: bad response class: 000 Nothing") { ok = false; }
  if !str_eq(rerr_of("600 Weird\r\n"), "ftp: bad response class: 600 Weird") { ok = false; }
  if !str_eq(rerr_of("999 Bad\r\n"), "ftp: bad response class: 999 Bad") { ok = false; }
  return assert(ok, "reply code digits and class range");
}

fn t19() -> TestResult {
  var ok = str_eq(rerr_of("220\r\n"), "ftp: malformed response line: 220");
  if !str_eq(rerr_of("220Service\r\n"), "ftp: malformed response line: 220Service") { ok = false; }
  let tab = with_byte("220 O", 9, "k\r\n");
  if !str_eq(rerr_of(tab), "ftp: control byte in response line") { ok = false; }
  if !str_eq(rerr_of("220 O\nk\r\n"), "ftp: control byte in response line") { ok = false; }
  return assert(ok, "malformed reply lines and control bytes");
}

fn t20() -> TestResult {
  var ok = str_eq(rerr_of("220 Ok\r\n221 More\r\n"), "ftp: trailing data after response");
  if !str_eq(rerr_of("220 Ok"), "ftp: missing CRLF") { ok = false; }
  if !str_eq(rerr_of("220-\r\n230"), "ftp: missing CRLF") { ok = false; }
  if !str_eq(rerr_of(""), "ftp: missing CRLF") { ok = false; }
  return assert(ok, "trailing data and missing CRLF");
}

fn t21() -> TestResult {
  var ok = rclass_of("150 Opening\r\n") == 1;
  if rclass_of("220 Ready\r\n") != 2 { ok = false; }
  if rclass_of("331 Need password\r\n") != 3 { ok = false; }
  if rclass_of("426 Connection closed\r\n") != 4 { ok = false; }
  if rclass_of("550 No such file\r\n") != 5 { ok = false; }
  if rcode_of("550 No such file\r\n") != 550 { ok = false; }
  return assert(ok, "reply classes 1xx..5xx");
}

fn t22() -> TestResult {
  let s = "220 \r\n";
  var ok = rcount_of(s) == 1;
  if !str_eq(rtext_of(s), "") { ok = false; }
  if !str_eq(rline_of(s, 0), "220 ") { ok = false; }
  if !str_eq(rline_of(s, 99), "") { ok = false; }
  if rlcode_of(s, 99) != -1 { ok = false; }
  if rlcode_of(s, -1) != -1 { ok = false; }
  if !str_eq(rline_of(s, -1), "") { ok = false; }
  if !str_eq(remit_of(s), s) { ok = false; }
  return assert(ok, "empty reply text and out-of-range accessors");
}

fn t23() -> TestResult {
  var ok = cmd_roundtrip("USER alice\r\n");
  if !cmd_roundtrip("PASS secret\r\n") { ok = false; }
  if !cmd_roundtrip("ACCT acct\r\n") { ok = false; }
  if !cmd_roundtrip("CWD /pub\r\n") { ok = false; }
  if !cmd_roundtrip("CDUP\r\n") { ok = false; }
  if !cmd_roundtrip("PWD\r\n") { ok = false; }
  if !cmd_roundtrip("QUIT\r\n") { ok = false; }
  if !cmd_roundtrip("PORT 192,168,0,1,4,1\r\n") { ok = false; }
  if !cmd_roundtrip("PASV\r\n") { ok = false; }
  if !cmd_roundtrip("TYPE I\r\n") { ok = false; }
  if !cmd_roundtrip("MODE S\r\n") { ok = false; }
  if !cmd_roundtrip("STRU F\r\n") { ok = false; }
  if !cmd_roundtrip("RETR f.txt\r\n") { ok = false; }
  if !cmd_roundtrip("STOR f.txt\r\n") { ok = false; }
  if !cmd_roundtrip("STOU f.txt\r\n") { ok = false; }
  if !cmd_roundtrip("APPE f.txt\r\n") { ok = false; }
  if !cmd_roundtrip("LIST\r\n") { ok = false; }
  if !cmd_roundtrip("LIST -la /pub\r\n") { ok = false; }
  if !cmd_roundtrip("NLST -a\r\n") { ok = false; }
  if !cmd_roundtrip("DELE f.txt\r\n") { ok = false; }
  if !cmd_roundtrip("RMD d\r\n") { ok = false; }
  if !cmd_roundtrip("MKD d\r\n") { ok = false; }
  if !cmd_roundtrip("RNFR old.txt\r\n") { ok = false; }
  if !cmd_roundtrip("RNTO new.txt\r\n") { ok = false; }
  if !cmd_roundtrip("ABOR\r\n") { ok = false; }
  if !cmd_roundtrip("SYST\r\n") { ok = false; }
  if !cmd_roundtrip("STAT /pub\r\n") { ok = false; }
  if !cmd_roundtrip("FEAT\r\n") { ok = false; }
  if !cmd_roundtrip("OPTS UTF8 ON\r\n") { ok = false; }
  if !cmd_roundtrip("SIZE f.txt\r\n") { ok = false; }
  if !cmd_roundtrip("MDTM f.txt\r\n") { ok = false; }
  return assert(ok, "all 31 verbs round-trip");
}

fn t24() -> TestResult {
  var ok = str_eq(carg_of("OPTS UTF8 ON\r\n"), "UTF8 ON");
  if !str_eq(carg_of("OPTS MLST Type;Size;\r\n"), "MLST Type;Size;") { ok = false; }
  if !str_eq(carg_of("OPTS UTF8\r\n"), "UTF8") { ok = false; }
  if !cmd_roundtrip("OPTS UTF8 ON\r\n") { ok = false; }
  if !str_eq(cerr_of("OPTS \r\n"), "ftp: bad argument shape: OPTS") { ok = false; }
  if !str_eq(cerr_of("OPTS  UTF8\r\n"), "ftp: bad argument shape: OPTS") { ok = false; }
  if !str_eq(cerr_of("OPTS UTF8 \r\n"), "ftp: bad argument shape: OPTS") { ok = false; }
  return assert(ok, "OPTS option and value parsing");
}

fn main() -> Int {
  io.println("=== xiom.ftp conformance tests ===");
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
    io.println("xiom.ftp: all tests passed");
  } else {
    io.println("xiom.ftp: tests failed");
  }
  return failed;
}
