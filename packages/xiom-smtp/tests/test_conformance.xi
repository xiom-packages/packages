// XIOM -- xiom.smtp conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.smtp codec against its documented RFC
// 5321 grammar subset, canonical emit rules and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: EHLO/HELO, MAIL/RCPT with paths and ESMTP parameters, the null
// reverse-path, quoted local parts, source-route rejection, DATA/RSET/QUIT/
// STARTTLS/NOOP/AUTH and the VRFY/EXPN/HELP pass-through, case-insensitive
// parse with uppercase canonical emit, CRLF framing, control bytes, the
// command length cap, single-line and multiline replies, code-class exposure,
// multiline code mismatch, unterminated blocks, bad code digits, control
// bytes in replies, enhanced status codes, reply building and a canonical
// round-trip battery.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq and every Vec[Str] read is bound to an
// explicitly typed local before use.

module smtp_tests
use xiom.io; use xiom.test; use xiom.smtp;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when parsing `line` as a command fails with a message that starts with
// `want`.
fn cmd_err_prefix(line: Str, want: Str) -> Bool {
  let r = cmd_parse(line);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, want); },
  }
  return false;
}

// True when parsing `line` as a command fails with exactly `want`.
fn cmd_err_is(line: Str, want: Str) -> Bool {
  let r = cmd_parse(line);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when parsing `text` as a reply fails with a message that starts with
// `want`.
fn resp_err_prefix(text: Str, want: Str) -> Bool {
  let r = resp_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, want); },
  }
  return false;
}

// True when parsing `text` as a reply fails with exactly `want`.
fn resp_err_is(text: Str, want: Str) -> Bool {
  let r = resp_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when a canonical command line parses and emits back byte-for-byte.
fn cmd_round_trip(line: Str) -> Bool {
  let r = cmd_parse(line);
  match r {
    Ok(c) => {
      let out: Str = cmd_emit(&c);
      return streq(out, line);
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when a canonical reply block parses and emits back byte-for-byte.
fn resp_round_trip(text: Str) -> Bool {
  let r = resp_parse(text);
  match r {
    Ok(p) => {
      let out: Str = resp_emit(&p);
      return streq(out, text);
    },
    Err(_) => { return false; },
  }
  return false;
}

// The canonical command lines of the round-trip battery.
fn canonical_commands() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("EHLO mail.example.com\r\n");
  v.push("HELO mail.example.com\r\n");
  v.push("MAIL FROM:<>\r\n");
  v.push("MAIL FROM:<alice@example.com> SIZE=100\r\n");
  v.push("RCPT TO:<bob@example.com>\r\n");
  v.push("DATA\r\n");
  v.push("RSET\r\n");
  v.push("NOOP\r\n");
  v.push("NOOP keepalive\r\n");
  v.push("QUIT\r\n");
  v.push("STARTTLS\r\n");
  v.push("AUTH PLAIN dGVzdA==\r\n");
  v.push("VRFY Smith\r\n");
  v.push("EXPN staff\r\n");
  v.push("HELP\r\n");
  return v;
}

// The canonical reply blocks of the round-trip battery.
fn canonical_replies() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("220 mail.example.com ESMTP\r\n");
  v.push("250\r\n");
  v.push("250-a\r\n250 b\r\n");
  v.push("354 Start mail input\r\n");
  v.push("421 Service not available\r\n");
  v.push("550 5.1.1 User unknown\r\n");
  return v;
}

fn t1() -> TestResult {
  let r = cmd_parse("EHLO example.com\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(cmd_name(&c), "EHLO");
      if !streq(cmd_argument(&c), "example.com") { ok = false; }
      if !streq(cmd_path(&c), "") { ok = false; }
      if cmd_param_count(&c) != 0 { ok = false; }
      if !streq(cmd_emit(&c), "EHLO example.com\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "EHLO parses and emits canonically");
}

fn t2() -> TestResult {
  let r = cmd_parse("MAIL FROM:<alice@example.com> SIZE=100 BODY=8BITMIME\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(cmd_name(&c), "MAIL");
      if !streq(cmd_path(&c), "<alice@example.com>") { ok = false; }
      if cmd_param_count(&c) != 2 { ok = false; }
      if !streq(cmd_param(&c, 0), "SIZE=100") { ok = false; }
      if !streq(cmd_param(&c, 1), "BODY=8BITMIME") { ok = false; }
      if !streq(cmd_argument(&c), "FROM:<alice@example.com> SIZE=100 BODY=8BITMIME") { ok = false; }
      if !streq(cmd_emit(&c), "MAIL FROM:<alice@example.com> SIZE=100 BODY=8BITMIME\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = cmd_parse("RCPT TO:<bob@example.com> NOTIFY=SUCCESS\r\n");
  match r2 {
    Ok(c2) => {
      if !streq(cmd_name(&c2), "RCPT") { ok = false; }
      if !streq(cmd_path(&c2), "<bob@example.com>") { ok = false; }
      if cmd_param_count(&c2) != 1 { ok = false; }
      if !streq(cmd_param(&c2, 0), "NOTIFY=SUCCESS") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "MAIL/RCPT expose path and ESMTP parameters");
}

fn t3() -> TestResult {
  var ok = cmd_round_trip("MAIL FROM:<> SIZE=100\r\n");
  let r = cmd_parse("MAIL FROM:<> SIZE=100\r\n");
  match r {
    Ok(c) => {
      if !streq(cmd_path(&c), "<>") { ok = false; }
      if cmd_param_count(&c) != 1 { ok = false; }
      if !streq(cmd_param(&c, 0), "SIZE=100") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var params = Vec[Str].new();
  params.push("SIZE=100");
  let b = cmd_mail("<>", &params);
  match b {
    Ok(c2) => {
      if !streq(cmd_emit(&c2), "MAIL FROM:<> SIZE=100\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var none = Vec[Str].new();
  let bad = cmd_rcpt("<>", &none);
  match bad {
    Ok(_) => { ok = false; },
    Err(e) => { if !string.str_starts_with(e, "smtp: bad path") { ok = false; } },
  }
  return assert(ok, "null reverse-path is legal, null forward-path is not");
}

fn t4() -> TestResult {
  let line = "MAIL FROM:<\"alice smith\"@example.com>\r\n";
  let r = cmd_parse(line);
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(cmd_path(&c), "<\"alice smith\"@example.com>");
      if !streq(cmd_emit(&c), line) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "quoted local part passes through unsplit");
}

fn t5() -> TestResult {
  var ok = cmd_err_prefix("MAIL FROM:<@relay.example.com,alice@example.com>\r\n", "smtp: bad path: source route");
  if !cmd_err_prefix("MAIL FROM:<unterminated\r\n", "smtp: bad path") { ok = false; }
  if !cmd_err_prefix("MAIL <a@b>\r\n", "smtp: bad path: missing FROM:") { ok = false; }
  if !cmd_err_prefix("RCPT TO:<a@b\r\n", "smtp: bad path") { ok = false; }
  return assert(ok, "malformed and source-routed paths are rejected");
}

fn t6() -> TestResult {
  var ok = cmd_round_trip("DATA\r\n");
  if !cmd_round_trip("RSET\r\n") { ok = false; }
  if !cmd_round_trip("QUIT\r\n") { ok = false; }
  if !cmd_round_trip("STARTTLS\r\n") { ok = false; }
  let d = cmd_data();
  if !streq(cmd_emit(&d), "DATA\r\n") { ok = false; }
  let s = cmd_starttls();
  if !streq(cmd_emit(&s), "STARTTLS\r\n") { ok = false; }
  if !cmd_err_prefix("DATA now\r\n", "smtp: bad verb: DATA takes no argument") { ok = false; }
  let n = cmd_parse("NOOP alive\r\n");
  match n {
    Ok(c) => { if !streq(cmd_argument(&c), "alive") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let n2 = cmd_parse("NOOP\r\n");
  match n2 {
    Ok(c2) => { if !streq(cmd_argument(&c2), "") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let nb = cmd_noop("ready");
  match nb {
    Ok(c3) => { if !streq(cmd_emit(&c3), "NOOP ready\r\n") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "DATA/RSET/QUIT/STARTTLS/NOOP forms");
}

fn t7() -> TestResult {
  var ok = true;
  let r = cmd_parse("AUTH PLAIN dGVzdA==\r\n");
  match r {
    Ok(c) => {
      if !streq(cmd_name(&c), "AUTH") { ok = false; }
      if !streq(cmd_argument(&c), "PLAIN dGVzdA==") { ok = false; }
      if !streq(cmd_emit(&c), "AUTH PLAIN dGVzdA==\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !cmd_err_prefix("AUTH\r\n", "smtp: bad verb: AUTH requires a mechanism") { ok = false; }
  let b = cmd_auth("PLAIN", "dGVzdA==");
  match b {
    Ok(c2) => { if !streq(cmd_emit(&c2), "AUTH PLAIN dGVzdA==\r\n") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let e2 = cmd_auth("", "");
  match e2 {
    Ok(_) => { ok = false; },
    Err(e) => { if !string.str_starts_with(e, "smtp: bad verb") { ok = false; } },
  }
  let r3 = cmd_parse("AUTH LOGIN\r\n");
  match r3 {
    Ok(c3) => { if !streq(cmd_argument(&c3), "LOGIN") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "AUTH mechanism and initial response");
}

fn t8() -> TestResult {
  var ok = cmd_round_trip("VRFY Smith\r\n");
  if !cmd_round_trip("EXPN staff\r\n") { ok = false; }
  if !cmd_round_trip("HELP\r\n") { ok = false; }
  if !cmd_round_trip("HELP MAIL\r\n") { ok = false; }
  let v = cmd_parse("VRFY Smith\r\n");
  match v {
    Ok(c) => { if !streq(cmd_argument(&c), "Smith") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let h = cmd_parse("HELP\r\n");
  match h {
    Ok(c2) => { if !streq(cmd_argument(&c2), "") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "VRFY/EXPN/HELP pass through verbatim");
}

fn t9() -> TestResult {
  var ok = true;
  let a = cmd_parse("ehlo lower.example\r\n");
  match a {
    Ok(c) => {
      if !streq(cmd_name(&c), "EHLO") { ok = false; }
      if !streq(cmd_emit(&c), "EHLO lower.example\r\n") { ok = false; }
      if !cmd_verb_is(&c, "ehlo") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let m = cmd_parse("mail from:<a@b>\r\n");
  match m {
    Ok(c2) => {
      if !streq(cmd_name(&c2), "MAIL") { ok = false; }
      if !streq(cmd_emit(&c2), "MAIL FROM:<a@b>\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let q = cmd_parse("QuIt\r\n");
  match q {
    Ok(c3) => { if !streq(cmd_name(&c3), "QUIT") { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !cmd_err_prefix("FROB x\r\n", "smtp: bad verb: FROB") { ok = false; }
  return assert(ok, "verb parsing is case-insensitive, emit is uppercase");
}

fn t10() -> TestResult {
  var ok = cmd_err_is("EHLO x", "smtp: missing CRLF");
  if !cmd_err_is("EHLO x\n", "smtp: missing CRLF") { ok = false; }
  if !cmd_err_is("EHLO x\r", "smtp: missing CRLF") { ok = false; }
  if !cmd_err_is("", "smtp: missing CRLF") { ok = false; }
  return assert(ok, "commands must be CRLF-framed");
}

fn t11() -> TestResult {
  var ok = cmd_err_is("NOOP a\tb\r\n", "smtp: control byte in command");
  if !cmd_err_is("NOOP a\rb\r\n", "smtp: control byte in command") { ok = false; }
  let b = cmd_build("NOOP", "a\tb");
  match b {
    Ok(_) => { ok = false; },
    Err(e) => { if !streq(e, "smtp: control byte in command") { ok = false; } },
  }
  return assert(ok, "control bytes are rejected in commands");
}

fn t12() -> TestResult {
  var ok = smtp_command_limit() == 512;
  let okline = "NOOP " + string.str_repeat("x", 505) + "\r\n";
  let r = cmd_parse(okline);
  match r {
    Ok(c) => { if !streq(cmd_name(&c), "NOOP") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let longline = "NOOP " + string.str_repeat("x", 506) + "\r\n";
  if !cmd_err_prefix(longline, "smtp: command too long") { ok = false; }
  return assert(ok, "command length cap is 512 octets including CRLF");
}

fn t13() -> TestResult {
  let r = resp_parse("220 smtp.example.com ESMTP ready\r\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = resp_code(&p) == 220;
      if resp_class(&p) != 2 { ok = false; }
      if resp_is_multiline(&p) { ok = false; }
      if resp_line_count(&p) != 1 { ok = false; }
      if !streq(resp_text(&p), "smtp.example.com ESMTP ready") { ok = false; }
      if !streq(resp_emit(&p), "220 smtp.example.com ESMTP ready\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = resp_parse("354 Start mail input\r\n");
  match r3 {
    Ok(p3) => { if resp_class(&p3) != 3 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let r4 = resp_parse("421 Service not available\r\n");
  match r4 {
    Ok(p4) => { if resp_class(&p4) != 4 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let r5 = resp_parse("550 No such user\r\n");
  match r5 {
    Ok(p5) => { if resp_class(&p5) != 5 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let rb = resp_parse("250\r\n");
  match rb {
    Ok(p6) => { if !streq(resp_text(&p6), "") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "single-line replies and 2xx..5xx classes");
}

fn t14() -> TestResult {
  let text = "250-mail.example.com\r\n250-PIPELINING\r\n250-8BITMIME\r\n250 SIZE 10240000\r\n";
  let r = resp_parse(text);
  var ok = false;
  match r {
    Ok(p) => {
      ok = resp_code(&p) == 250;
      if resp_class(&p) != 2 { ok = false; }
      if !resp_is_multiline(&p) { ok = false; }
      if resp_line_count(&p) != 4 { ok = false; }
      if !streq(resp_line(&p, 0), "mail.example.com") { ok = false; }
      if !streq(resp_line(&p, 1), "PIPELINING") { ok = false; }
      if !streq(resp_line(&p, 2), "8BITMIME") { ok = false; }
      if !streq(resp_line(&p, 3), "SIZE 10240000") { ok = false; }
      if !streq(resp_text(&p), "mail.example.com") { ok = false; }
      if !streq(resp_emit(&p), text) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multiline replies expose every line");
}

fn t15() -> TestResult {
  var ok = resp_err_prefix("250-a\r\n251 b\r\n", "smtp: multiline code mismatch");
  if !resp_err_is("250-a\r\n250-b\r\n", "smtp: unterminated multiline") { ok = false; }
  if !resp_err_is("250-\r\n", "smtp: unterminated multiline") { ok = false; }
  return assert(ok, "multiline code mismatch and unterminated block");
}

fn t16() -> TestResult {
  var ok = resp_err_prefix("2X0 OK\r\n", "smtp: bad code digits");
  if !resp_err_prefix("25 OK\r\n", "smtp: bad code digits") { ok = false; }
  if !resp_err_prefix("250X OK\r\n", "smtp: bad code digits") { ok = false; }
  if !resp_err_prefix("099 no\r\n", "smtp: bad code digits") { ok = false; }
  if !resp_err_prefix("\r\n", "smtp: bad code digits") { ok = false; }
  return assert(ok, "bad reply code digits are rejected");
}

fn t17() -> TestResult {
  let r = resp_parse("550 5.1.1 User unknown\r\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = resp_has_enhanced(&p);
      if !streq(resp_enhanced(&p), "5.1.1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = resp_parse("250 2.0.0 OK\r\n");
  match r2 {
    Ok(p2) => { if !streq(resp_enhanced(&p2), "2.0.0") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let r3 = resp_parse("250 OK\r\n");
  match r3 {
    Ok(p3) => {
      if resp_has_enhanced(&p3) { ok = false; }
      if !streq(resp_enhanced(&p3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r4 = resp_parse("250-2.1.0 queued\r\n250 OK\r\n");
  match r4 {
    Ok(p4) => { if !streq(resp_enhanced(&p4), "2.1.0") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let r5 = resp_parse("250 12.1.0 nope\r\n");
  match r5 {
    Ok(p5) => { if !streq(resp_enhanced(&p5), "") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let r6 = resp_parse("250 2.1.0\r\n");
  match r6 {
    Ok(p6) => { if !streq(resp_enhanced(&p6), "2.1.0") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "enhanced status codes at the start of the text");
}

fn t18() -> TestResult {
  var ok = resp_err_is("250 OK", "smtp: missing CRLF");
  if !resp_err_is("250 OK\n", "smtp: missing CRLF") { ok = false; }
  if !resp_err_is("250 OK\r", "smtp: missing CRLF") { ok = false; }
  if !resp_err_is("250-OK\r\n250 OK", "smtp: missing CRLF") { ok = false; }
  return assert(ok, "replies must be CRLF-framed");
}

fn t19() -> TestResult {
  var ok = true;
  var lines = Vec[Str].new();
  lines.push("mail.example.com");
  lines.push("PIPELINING");
  lines.push("SIZE 10240000");
  let b = resp_build(250, &lines);
  match b {
    Ok(p) => {
      if !streq(resp_emit(&p), "250-mail.example.com\r\n250-PIPELINING\r\n250 SIZE 10240000\r\n") { ok = false; }
      if resp_line_count(&p) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var single = Vec[Str].new();
  single.push("smtp.example.com ESMTP");
  let b2 = resp_build(220, &single);
  match b2 {
    Ok(p2) => { if !streq(resp_emit(&p2), "220 smtp.example.com ESMTP\r\n") { ok = false; } },
    Err(_) => { ok = false; },
  }
  var empty = Vec[Str].new();
  let b3 = resp_build(250, &empty);
  match b3 {
    Ok(_) => { ok = false; },
    Err(e3) => { if !string.str_starts_with(e3, "smtp: unterminated multiline") { ok = false; } },
  }
  let b4 = resp_build(99, &single);
  match b4 {
    Ok(_) => { ok = false; },
    Err(e4) => { if !string.str_starts_with(e4, "smtp: bad code digits") { ok = false; } },
  }
  var badline = Vec[Str].new();
  badline.push("a\rb");
  let b5 = resp_build(250, &badline);
  match b5 {
    Ok(_) => { ok = false; },
    Err(e5) => { if !string.str_starts_with(e5, "smtp: control byte in response") { ok = false; } },
  }
  return assert(ok, "resp_build validates code, lines and control bytes");
}

fn t20() -> TestResult {
  var ok = resp_round_trip("250\r\n");
  if !resp_round_trip("250-a\r\n250 b\r\n") { ok = false; }
  if !resp_round_trip("550 5.1.1 User unknown\r\n") { ok = false; }
  let r = resp_parse("250 \r\n");
  match r {
    Ok(p) => {
      if !streq(resp_text(&p), "") { ok = false; }
      if !streq(resp_emit(&p), "250\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical reply framing round-trips");
}

fn t21() -> TestResult {
  let r = cmd_parse("MAIL FROM:<a@b> SIZE=1\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = true;
      if !streq(cmd_param(&c, -1), "") { ok = false; }
      if !streq(cmd_param(&c, 7), "") { ok = false; }
      if !cmd_verb_is(&c, "mail") { ok = false; }
      if cmd_verb_is(&c, "rcpt") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let rp = resp_parse("250 OK\r\n");
  match rp {
    Ok(p) => {
      if !streq(resp_line(&p, -1), "") { ok = false; }
      if !streq(resp_line(&p, 3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return empty strings");
}

fn t22() -> TestResult {
  var ok = true;
  let cmds = canonical_commands();
  var i = 0;
  while i < cmds.len() {
    let line: Str = cmds[i];
    if !cmd_round_trip(line) { ok = false; }
    i = i + 1;
  }
  let reps = canonical_replies();
  var j = 0;
  while j < reps.len() {
    let text: Str = reps[j];
    if !resp_round_trip(text) { ok = false; }
    j = j + 1;
  }
  return assert(ok, "canonical command and reply round-trips");
}

fn main() -> Int {
  io.println("=== xiom.smtp conformance tests ===");
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
    io.println("xiom.smtp: all tests passed");
  } else {
    io.println("xiom.smtp: tests failed");
  }
  return failed;
}
