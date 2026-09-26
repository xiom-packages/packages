// XIOM -- xiom.pop3 conformance tests (27 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.pop3 codec against its
// documented RFC 1939 command grammar, response grammar, dot-stuffing
// rules, listing pairs and error catalog.
//
// Coverage: all twelve commands with their argument shapes, keyword
// case-insensitivity, CRLF handling, the printable-byte rule, canonical
// decimal arguments, TOP n, PASS rest-of-line, APOP digests, canonical
// request building and round-trips, single-line and multi-line responses,
// status-marker and CRLF errors, dot-stuffing both directions, LIST/UIDL
// pair materialization, bounds-safe accessors, byte caps and response
// building.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq instead of `==`.

module pop3_tests
use xiom.io; use xiom.test; use xiom.pop3;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Build a request without Result plumbing.
fn req(kind: Int, text: Str, digest: Str, msg: Int, n: Int) -> Pop3Request {
  return Pop3Request{ kind: kind; text: text; digest: digest; msg: msg; n: n; };
}

// Build a response without Result plumbing (empty payload).
fn resp(ok: Bool, multiline: Bool, text: Str) -> Pop3Response {
  return Pop3Response{
    ok: ok;
    multiline: multiline;
    text: text;
    lines: Vec[Str].new();
    pair_nums: Vec[Int].new();
    pair_vals: Vec[Str].new();
  };
}

// Build a response with payload lines.
fn resp_lines(ok: Bool, multiline: Bool, text: Str, lines: Vec[Str]) -> Pop3Response {
  return Pop3Response{
    ok: ok;
    multiline: multiline;
    text: text;
    lines: lines;
    pair_nums: Vec[Int].new();
    pair_vals: Vec[Str].new();
  };
}

// True when the command line fails to parse with a "pop3: " error.
fn req_err(line: Str) -> Bool {
  let r = pop3_parse_request(line);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "pop3: "); },
  }
  return false;
}

// True when the text fails to parse as a response with a "pop3: " error.
fn resp_err(multiline: Bool, text: Str) -> Bool {
  let r = pop3_parse_response(multiline, text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "pop3: "); },
  }
  return false;
}

// True when the text fails to parse as a listing with a "pop3: " error.
fn listing_err(kind: Int, text: Str) -> Bool {
  let r = pop3_parse_listing(kind, text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "pop3: "); },
  }
  return false;
}

// True when the request fails to build with a "pop3: " error.
fn req_build_err(q: Pop3Request) -> Bool {
  let b = pop3_build_request(&q);
  match b {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "pop3: "); },
  }
  return false;
}

// True when the response fails to build with a "pop3: " error.
fn build_err(r: Pop3Response) -> Bool {
  let b = pop3_build_response(&r);
  match b {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "pop3: "); },
  }
  return false;
}

// True when the request builds exactly to `want`.
fn built_is(q: Pop3Request, want: Str) -> Bool {
  let b = pop3_build_request(&q);
  match b {
    Ok(s) => { return streq(s, want); },
    Err(_) => { return false; },
  }
  return false;
}

// True when the response builds exactly to `want`.
fn built_response_is(r: Pop3Response, want: Str) -> Bool {
  let b = pop3_build_response(&r);
  match b {
    Ok(s) => { return streq(s, want); },
    Err(_) => { return false; },
  }
  return false;
}

// Message number parsed from a command line, or -999 on error.
fn msg_of(line: Str) -> Int {
  let r = pop3_parse_request(line);
  match r {
    Ok(q) => { return q.msg; },
    Err(_) => { return -999; },
  }
  return -999;
}

// TOP line count parsed from a command line, or -999 on error.
fn top_n_of(line: Str) -> Int {
  let r = pop3_parse_request(line);
  match r {
    Ok(q) => { return q.n; },
    Err(_) => { return -999; },
  }
  return -999;
}

// Build -> parse -> build must be byte-identical and keep the kind.
fn round_trip(q: Pop3Request) -> Bool {
  let b1 = pop3_build_request(&q);
  match b1 {
    Ok(line) => {
      let p = pop3_parse_request(line);
      match p {
        Ok(q2) => {
          if q2.kind != q.kind { return false; }
          let b2 = pop3_build_request(&q2);
          match b2 {
            Ok(line2) => { return streq(line, line2); },
            Err(_) => { return false; },
          }
        },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  var ok = true;
  let u = pop3_parse_request("USER alice\r\n");
  match u {
    Ok(q) => {
      if q.kind != POP3_USER { ok = false; }
      if !streq(q.text, "alice") { ok = false; }
      if q.msg != -1 { ok = false; }
      if q.n != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let p = pop3_parse_request("PASS s3cr3t");
  match p {
    Ok(q) => {
      if q.kind != POP3_PASS { ok = false; }
      if !streq(q.text, "s3cr3t") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let s = pop3_parse_request("STAT");
  match s {
    Ok(q) => {
      if q.kind != POP3_STAT { ok = false; }
      if q.text.len() != 0 { ok = false; }
      if q.digest.len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "USER/PASS/STAT parse with an optional trailing CRLF");
}

fn t2() -> TestResult {
  var ok = true;
  let l0 = pop3_parse_request("LIST");
  match l0 {
    Ok(q) => {
      if q.kind != POP3_LIST { ok = false; }
      if q.msg != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let l1 = pop3_parse_request("list 42\r\n");
  match l1 {
    Ok(q) => {
      if q.kind != POP3_LIST { ok = false; }
      if q.msg != 42 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let u0 = pop3_parse_request("UIDL");
  match u0 {
    Ok(q) => {
      if q.kind != POP3_UIDL { ok = false; }
      if q.msg != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let u1 = pop3_parse_request("UIDL 7");
  match u1 {
    Ok(q) => {
      if q.kind != POP3_UIDL { ok = false; }
      if q.msg != 7 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r1 = pop3_parse_request("RETR 2147483647");
  match r1 {
    Ok(q) => {
      if q.kind != POP3_RETR { ok = false; }
      if q.msg != 2147483647 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let d1 = pop3_parse_request("DELE 3");
  match d1 {
    Ok(q) => {
      if q.kind != POP3_DELE { ok = false; }
      if q.msg != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "LIST/UIDL take an optional msg; RETR/DELE require one");
}

fn t3() -> TestResult {
  var ok = true;
  let n1 = pop3_parse_request("NOOP");
  match n1 {
    Ok(q) => { if q.kind != POP3_NOOP { ok = false; } },
    Err(_) => { ok = false; },
  }
  let n2 = pop3_parse_request("RSET\r\n");
  match n2 {
    Ok(q) => { if q.kind != POP3_RSET { ok = false; } },
    Err(_) => { ok = false; },
  }
  let n3 = pop3_parse_request("QUIT");
  match n3 {
    Ok(q) => {
      if q.kind != POP3_QUIT { ok = false; }
      if q.text.len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let tp = pop3_parse_request("TOP 2 0");
  match tp {
    Ok(q) => {
      if q.kind != POP3_TOP { ok = false; }
      if q.msg != 2 { ok = false; }
      if q.n != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let ap = pop3_parse_request("APOP bob C4C9334BAC560ECC979E58001B3E22FB");
  match ap {
    Ok(q) => {
      if q.kind != POP3_APOP { ok = false; }
      if !streq(q.text, "bob") { ok = false; }
      if !streq(q.digest, "c4c9334bac560ecc979e58001b3e22fb") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "NOOP/RSET/QUIT parse; TOP n=0; APOP folds the digest to lowercase");
}

fn t4() -> TestResult {
  var ok = true;
  let a = pop3_parse_request("stat");
  match a {
    Ok(q) => { if q.kind != POP3_STAT { ok = false; } },
    Err(_) => { ok = false; },
  }
  let b = pop3_parse_request("UsEr alice");
  match b {
    Ok(q) => {
      if q.kind != POP3_USER { ok = false; }
      if !streq(q.text, "alice") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = pop3_parse_request("ReTr 1\r\n");
  match c {
    Ok(q) => { if q.kind != POP3_RETR { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !req_err("USERX alice") { ok = false; }
  if !req_err("TOPS 1 1") { ok = false; }
  if !req_err("LISTING") { ok = false; }
  if !req_err("TO") { ok = false; }
  return assert(ok, "keywords match case-insensitively and only at full length");
}

fn t5() -> TestResult {
  var ok = true;
  if !built_is(req(POP3_USER, "alice", "", -1, -1), "USER alice\r\n") { ok = false; }
  if !built_is(req(POP3_PASS, "p w", "", -1, -1), "PASS p w\r\n") { ok = false; }
  if !built_is(req(POP3_STAT, "", "", -1, -1), "STAT\r\n") { ok = false; }
  if !built_is(req(POP3_LIST, "", "", -1, -1), "LIST\r\n") { ok = false; }
  if !built_is(req(POP3_LIST, "", "", 4, -1), "LIST 4\r\n") { ok = false; }
  if !built_is(req(POP3_UIDL, "", "", -1, -1), "UIDL\r\n") { ok = false; }
  if !built_is(req(POP3_UIDL, "", "", 9, -1), "UIDL 9\r\n") { ok = false; }
  if !built_is(req(POP3_RETR, "", "", 1, -1), "RETR 1\r\n") { ok = false; }
  if !built_is(req(POP3_DELE, "", "", 2, -1), "DELE 2\r\n") { ok = false; }
  if !built_is(req(POP3_NOOP, "", "", -1, -1), "NOOP\r\n") { ok = false; }
  if !built_is(req(POP3_RSET, "", "", -1, -1), "RSET\r\n") { ok = false; }
  if !built_is(req(POP3_QUIT, "", "", -1, -1), "QUIT\r\n") { ok = false; }
  if !built_is(req(POP3_TOP, "", "", 3, 0), "TOP 3 0\r\n") { ok = false; }
  if !built_is(req(POP3_TOP, "", "", 2147483647, 2147483647), "TOP 2147483647 2147483647\r\n") { ok = false; }
  if !built_is(req(POP3_APOP, "bob", "C4C9334BAC560ECC979E58001B3E22FB", -1, -1), "APOP bob c4c9334bac560ecc979e58001b3e22fb\r\n") { ok = false; }
  return assert(ok, "build_request emits canonical uppercase keywords and CRLF");
}

fn t6() -> TestResult {
  var ok = true;
  if !req_build_err(req(99, "", "", -1, -1)) { ok = false; }
  if !req_build_err(req(0, "", "", -1, -1)) { ok = false; }
  if !req_build_err(req(POP3_USER, "", "", -1, -1)) { ok = false; }
  if !req_build_err(req(POP3_USER, "a b", "", -1, -1)) { ok = false; }
  if !req_build_err(req(POP3_PASS, "", "", -1, -1)) { ok = false; }
  if !req_build_err(req(POP3_LIST, "", "", 0, -1)) { ok = false; }
  if !req_build_err(req(POP3_RETR, "", "", -1, -1)) { ok = false; }
  if !req_build_err(req(POP3_RETR, "", "", 2147483648, -1)) { ok = false; }
  if !req_build_err(req(POP3_TOP, "", "", 1, -1)) { ok = false; }
  if !req_build_err(req(POP3_TOP, "", "", 0, 0)) { ok = false; }
  if !req_build_err(req(POP3_APOP, "bob", "xyz", -1, -1)) { ok = false; }
  if !req_build_err(req(POP3_APOP, "", "c4c9334bac560ecc979e58001b3e22fb", -1, -1)) { ok = false; }
  if !built_is(req(POP3_STAT, "junk", "", 5, 7), "STAT\r\n") { ok = false; }
  return assert(ok, "build_request validates each kind and ignores unused fields");
}

fn t7() -> TestResult {
  var ok = true;
  if !round_trip(req(POP3_USER, "alice", "", -1, -1)) { ok = false; }
  if !round_trip(req(POP3_PASS, "p w", "", -1, -1)) { ok = false; }
  if !round_trip(req(POP3_STAT, "", "", -1, -1)) { ok = false; }
  if !round_trip(req(POP3_LIST, "", "", -1, -1)) { ok = false; }
  if !round_trip(req(POP3_LIST, "", "", 3, -1)) { ok = false; }
  if !round_trip(req(POP3_UIDL, "", "", -1, -1)) { ok = false; }
  if !round_trip(req(POP3_UIDL, "", "", 70, -1)) { ok = false; }
  if !round_trip(req(POP3_RETR, "", "", 1, -1)) { ok = false; }
  if !round_trip(req(POP3_DELE, "", "", 2, -1)) { ok = false; }
  if !round_trip(req(POP3_NOOP, "", "", -1, -1)) { ok = false; }
  if !round_trip(req(POP3_RSET, "", "", -1, -1)) { ok = false; }
  if !round_trip(req(POP3_QUIT, "", "", -1, -1)) { ok = false; }
  if !round_trip(req(POP3_TOP, "", "", 9, 12)) { ok = false; }
  if !round_trip(req(POP3_APOP, "bob", "c4c9334bac560ecc979e58001b3e22fb", -1, -1)) { ok = false; }
  return assert(ok, "every command kind round-trips through build and parse");
}

fn t8() -> TestResult {
  var ok = true;
  if !req_err("STAT\r") { ok = false; }
  if !req_err("STAT\n") { ok = false; }
  if !req_err("STAT\r\n\r\n") { ok = false; }
  if !req_err("") { ok = false; }
  if !req_err("\r\n") { ok = false; }
  if !req_err(" ") { ok = false; }
  if !req_err("\r\nSTAT") { ok = false; }
  let bare = pop3_parse_request("STAT");
  match bare {
    Ok(q) => { if q.kind != POP3_STAT { ok = false; } },
    Err(_) => { ok = false; },
  }
  let term = pop3_parse_request("STAT\r\n");
  match term {
    Ok(q) => { if q.kind != POP3_STAT { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "only one exact trailing CRLF is stripped; empty commands are rejected");
}

fn t9() -> TestResult {
  var ok = true;
  let name40 = string.str_repeat("a", 40);
  let user40 = "USER " + name40;
  let p40 = pop3_parse_request(user40);
  match p40 {
    Ok(q) => {
      if q.kind != POP3_USER { ok = false; }
      if !streq(q.text, name40) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let user41 = "USER " + string.str_repeat("a", 41);
  if !req_err(user41) { ok = false; }
  if !req_err("USER a\u{0009}b") { ok = false; }
  if !req_err("STAT \u{007F}") { ok = false; }
  if !req_err("USER \u{00C9}") { ok = false; }
  let punct = pop3_parse_request("USER a.b-c_d");
  match punct {
    Ok(q) => { if !streq(q.text, "a.b-c_d") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "names cap at 40 bytes and non-printable bytes are rejected");
}

fn t10() -> TestResult {
  var ok = true;
  if msg_of("RETR 1") != 1 { ok = false; }
  if msg_of("RETR 2147483647") != 2147483647 { ok = false; }
  if msg_of("LIST 999999999") != 999999999 { ok = false; }
  if msg_of("UIDL 007") != -999 { ok = false; }
  if msg_of("RETR 0") != -999 { ok = false; }
  if msg_of("RETR 01") != -999 { ok = false; }
  if msg_of("RETR 2147483648") != -999 { ok = false; }
  if msg_of("RETR 99999999999") != -999 { ok = false; }
  if msg_of("RETR -1") != -999 { ok = false; }
  if msg_of("RETR 1 2") != -999 { ok = false; }
  if msg_of("RETR abc") != -999 { ok = false; }
  if msg_of("RETR 1a") != -999 { ok = false; }
  if msg_of("LIST") != -1 { ok = false; }
  return assert(ok, "message numbers are canonical decimal in 1..2^31-1");
}

fn t11() -> TestResult {
  var ok = true;
  if top_n_of("TOP 1 0") != 0 { ok = false; }
  if top_n_of("TOP 1 10") != 10 { ok = false; }
  if top_n_of("TOP 2147483647 2147483647") != 2147483647 { ok = false; }
  if top_n_of("TOP 1") != -999 { ok = false; }
  if top_n_of("TOP 0 1") != -999 { ok = false; }
  if top_n_of("TOP 1 00") != -999 { ok = false; }
  if top_n_of("TOP 1 2147483648") != -999 { ok = false; }
  if top_n_of("TOP 1 1 2") != -999 { ok = false; }
  if top_n_of("TOP 1 x") != -999 { ok = false; }
  return assert(ok, "TOP takes msg and a non-negative canonical line count");
}

fn t12() -> TestResult {
  var ok = true;
  let p1 = pop3_parse_request("PASS a b c");
  match p1 {
    Ok(q) => {
      if q.kind != POP3_PASS { ok = false; }
      if !streq(q.text, "a b c") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !built_is(req(POP3_PASS, "a b c", "", -1, -1), "PASS a b c\r\n") { ok = false; }
  let p2 = pop3_parse_request("PASS  x");
  match p2 {
    Ok(q) => { if !streq(q.text, " x") { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !built_is(req(POP3_PASS, " x", "", -1, -1), "PASS  x\r\n") { ok = false; }
  if !req_err("PASS") { ok = false; }
  if !req_err("PASS ") { ok = false; }
  if !req_err("USER a b") { ok = false; }
  if !req_err("PASS a\u{0009}b") { ok = false; }
  return assert(ok, "PASS is rest-of-line; USER is a single token");
}

fn t13() -> TestResult {
  var ok = true;
  let d = "c4c9334bac560ecc979e58001b3e22fb";
  if !built_is(req(POP3_APOP, "bob", d, -1, -1), "APOP bob c4c9334bac560ecc979e58001b3e22fb\r\n") { ok = false; }
  let short = string.str_slice(d, 0, 31);
  let long = d + "0";
  if !req_build_err(req(POP3_APOP, "bob", short, -1, -1)) { ok = false; }
  if !req_build_err(req(POP3_APOP, "bob", long, -1, -1)) { ok = false; }
  if !req_err("APOP bob c4c9334bac560ecc979e58001b3e22fz") { ok = false; }
  if !req_err("APOP") { ok = false; }
  if !req_err("APOP bob") { ok = false; }
  if !req_err("APOP a b c") { ok = false; }
  if !req_err("APOP " + string.str_repeat("a", 41) + " " + d) { ok = false; }
  return assert(ok, "APOP needs a name and exactly 32 hex digest bytes");
}

fn t14() -> TestResult {
  var ok = true;
  let r1 = pop3_parse_response(false, "+OK\r\n");
  match r1 {
    Ok(p) => {
      if !pop3_is_ok(&p) { ok = false; }
      if pop3_is_multiline(&p) { ok = false; }
      if !streq(pop3_response_text(&p), "") { ok = false; }
      if pop3_line_count(&p) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = pop3_parse_response(false, "+OK waldo is dead\r\n");
  match r2 {
    Ok(p) => { if !streq(pop3_response_text(&p), "waldo is dead") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let r3 = pop3_parse_response(false, "-ERR no such message\r\n");
  match r3 {
    Ok(p) => {
      if pop3_is_ok(&p) { ok = false; }
      if !streq(pop3_response_text(&p), "no such message") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r4 = pop3_parse_response(false, "+OK 2 messages (320 octets)\r\n");
  match r4 {
    Ok(p) => { if !streq(pop3_response_text(&p), "2 messages (320 octets)") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let r5 = pop3_parse_response(false, "-ERR\r\n");
  match r5 {
    Ok(p) => {
      if pop3_is_ok(&p) { ok = false; }
      if !streq(pop3_response_text(&p), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "single-line status markers, text with spaces, empty text");
}

fn t15() -> TestResult {
  var ok = true;
  if !resp_err(false, "+ok hi\r\n") { ok = false; }
  if !resp_err(false, "-ERRx\r\n") { ok = false; }
  if !resp_err(false, "+OKAY\r\n") { ok = false; }
  if !resp_err(false, "OK\r\n") { ok = false; }
  if !resp_err(false, "X+OK\r\n") { ok = false; }
  if !resp_err(false, "+OK hi\r\nextra") { ok = false; }
  if !resp_err(true, "-ERR nope\r\njunk") { ok = false; }
  if !resp_err(true, "-ERR nope\r\n.\r\n") { ok = false; }
  return assert(ok, "status markers are exact and single-line responses reject trailing bytes");
}

fn t16() -> TestResult {
  var ok = true;
  if !resp_err(false, "+OK") { ok = false; }
  if !resp_err(false, "-ERR hi") { ok = false; }
  if !resp_err(false, "+OK\nhi\r\n") { ok = false; }
  if !resp_err(false, "+OK h\ri\r\n") { ok = false; }
  if !resp_err(false, "+OK \u{0001}\r\n") { ok = false; }
  if !resp_err(false, "+OK \u{007F}\r\n") { ok = false; }
  if !resp_err(false, "+OK hi\rX\r\n") { ok = false; }
  return assert(ok, "unterminated status lines and non-printable text are rejected");
}

fn t17() -> TestResult {
  let text = "+OK 120 octets\r\nFrom: alice\r\nSubject: hi\r\n\r\nbody line\r\n.\r\n";
  let r = pop3_parse_response(true, text);
  var ok = false;
  match r {
    Ok(p) => {
      ok = pop3_is_ok(&p);
      if !pop3_is_multiline(&p) { ok = false; }
      if !streq(pop3_response_text(&p), "120 octets") { ok = false; }
      if pop3_line_count(&p) != 4 { ok = false; }
      if !streq(pop3_line(&p, 0), "From: alice") { ok = false; }
      if !streq(pop3_line(&p, 1), "Subject: hi") { ok = false; }
      if !streq(pop3_line(&p, 2), "") { ok = false; }
      if !streq(pop3_line(&p, 3), "body line") { ok = false; }
      if !streq(pop3_payload(&p), "From: alice\r\nSubject: hi\r\n\r\nbody line\r\n") { ok = false; }
      let b = pop3_build_response(&p);
      match b {
        Ok(s) => { if !streq(s, text) { ok = false; } },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multi-line RETR response keeps lines, blanks and payload");
}

fn t18() -> TestResult {
  var ok = true;
  let text = "+OK\r\n..leading\r\n...\r\n..\r\nplain\r\n.\r\n";
  let r = pop3_parse_response(true, text);
  match r {
    Ok(p) => {
      if pop3_line_count(&p) != 4 { ok = false; }
      if !streq(pop3_line(&p, 0), ".leading") { ok = false; }
      if !streq(pop3_line(&p, 1), "..") { ok = false; }
      if !streq(pop3_line(&p, 2), ".") { ok = false; }
      if !streq(pop3_line(&p, 3), "plain") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !streq(pop3_dot_stuff(""), "") { ok = false; }
  if !streq(pop3_dot_stuff("plain"), "plain") { ok = false; }
  if !streq(pop3_dot_stuff("."), "..") { ok = false; }
  if !streq(pop3_dot_stuff(".x"), "..x") { ok = false; }
  if !streq(pop3_dot_unstuff(""), "") { ok = false; }
  if !streq(pop3_dot_unstuff("."), ".") { ok = false; }
  if !streq(pop3_dot_unstuff(".."), ".") { ok = false; }
  if !streq(pop3_dot_unstuff("..x"), ".x") { ok = false; }
  if !streq(pop3_dot_unstuff("plain"), "plain") { ok = false; }
  return assert(ok, "a leading dot line is stuffed and unstuffed by one byte");
}

fn t19() -> TestResult {
  var ok = true;
  if !resp_err(true, "+OK\r\n1 120\r\n") { ok = false; }
  if !resp_err(true, "+OK\r\nabc") { ok = false; }
  if !resp_err(true, "+OK\r\n") { ok = false; }
  if !resp_err(true, "+OK\r\n.\r\njunk") { ok = false; }
  if !resp_err(true, "+OK\r\nx\ny\r\n.\r\n") { ok = false; }
  let opaque = pop3_parse_response(true, "+OK\r\nx\u{007F}y\r\n.\r\n");
  match opaque {
    Ok(p) => { if !streq(pop3_line(&p, 0), "x\u{007F}y") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a payload needs its dot terminator and rejects stray CR/LF");
}

fn t20() -> TestResult {
  var ok = true;
  let empty = pop3_parse_response(true, "+OK\r\n.\r\n");
  match empty {
    Ok(p) => {
      if !pop3_is_ok(&p) { ok = false; }
      if !pop3_is_multiline(&p) { ok = false; }
      if pop3_line_count(&p) != 0 { ok = false; }
      if !built_response_is(p, "+OK\r\n.\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let err = pop3_parse_response(true, "-ERR no such message\r\n");
  match err {
    Ok(p) => {
      if pop3_is_ok(&p) { ok = false; }
      if pop3_is_multiline(&p) { ok = false; }
      if pop3_line_count(&p) != 0 { ok = false; }
      if !built_response_is(p, "-ERR no such message\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "an empty multi-line payload is legal and round-trips");
}

fn t21() -> TestResult {
  let text = "+OK 2 messages (320 octets)\r\n1 120\r\n2 200\r\n.\r\n";
  let r = pop3_parse_listing(POP3_LIST, text);
  var ok = false;
  match r {
    Ok(p) => {
      ok = pop3_is_ok(&p);
      if pop3_pair_count(&p) != 2 { ok = false; }
      if pop3_line_count(&p) != 2 { ok = false; }
      if pop3_pair_num(&p, 0) != 1 { ok = false; }
      if pop3_pair_num(&p, 1) != 2 { ok = false; }
      if !streq(pop3_pair_val(&p, 0), "120") { ok = false; }
      if !streq(pop3_pair_val(&p, 1), "200") { ok = false; }
      if !streq(pop3_line(&p, 0), "1 120") { ok = false; }
      if pop3_lookup_line(&p, 1) != 0 { ok = false; }
      if pop3_lookup_line(&p, 2) != 1 { ok = false; }
      if pop3_lookup_line(&p, 3) != -1 { ok = false; }
      if pop3_list_size(&p, 1) != 120 { ok = false; }
      if pop3_list_size(&p, 2) != 200 { ok = false; }
      if pop3_list_size(&p, 9) != -1 { ok = false; }
      if !built_response_is(p, text) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "LIST pairs materialize and rebuild byte-identically");
}

fn t22() -> TestResult {
  var ok = true;
  if !listing_err(POP3_LIST, "+OK\r\n1 0120\r\n.\r\n") { ok = false; }
  if !listing_err(POP3_LIST, "+OK\r\n0 120\r\n.\r\n") { ok = false; }
  if !listing_err(POP3_LIST, "+OK\r\n1 120 extra\r\n.\r\n") { ok = false; }
  if !listing_err(POP3_LIST, "+OK\r\nabc\r\n.\r\n") { ok = false; }
  if !listing_err(POP3_LIST, "+OK\r\n1 \r\n.\r\n") { ok = false; }
  if !listing_err(POP3_STAT, "+OK\r\n1 1\r\n.\r\n") { ok = false; }
  let zero = pop3_parse_listing(POP3_LIST, "+OK\r\n1 0\r\n.\r\n");
  match zero {
    Ok(p) => { if pop3_list_size(&p, 1) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let err = pop3_parse_listing(POP3_LIST, "-ERR no such message\r\n");
  match err {
    Ok(p) => {
      if pop3_is_ok(&p) { ok = false; }
      if pop3_pair_count(&p) != 0 { ok = false; }
      if pop3_list_size(&p, 1) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "LIST entries need canonical msg and size; -ERR listings parse");
}

fn t23() -> TestResult {
  var ok = true;
  let text = "+OK\r\n1 abc\r\n2 QhdPYR:00WBw1Ph7x7\r\n.\r\n";
  let r = pop3_parse_listing(POP3_UIDL, text);
  match r {
    Ok(p) => {
      if pop3_pair_count(&p) != 2 { ok = false; }
      if !streq(pop3_uidl_id(&p, 1), "abc") { ok = false; }
      if !streq(pop3_uidl_id(&p, 2), "QhdPYR:00WBw1Ph7x7") { ok = false; }
      if !streq(pop3_uidl_id(&p, 3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !listing_err(POP3_UIDL, "+OK\r\n1 a b\r\n.\r\n") { ok = false; }
  if !listing_err(POP3_UIDL, "+OK\r\n1 \r\n.\r\n") { ok = false; }
  if !listing_err(POP3_UIDL, "+OK\r\n1 " + string.str_repeat("a", 71) + "\r\n.\r\n") { ok = false; }
  if !listing_err(POP3_UIDL, "+OK\r\n1 a\u{0001}b\r\n.\r\n") { ok = false; }
  if !listing_err(POP3_UIDL, "+OK\r\n0 abc\r\n.\r\n") { ok = false; }
  let uid70 = string.str_repeat("a", 70);
  let good = pop3_parse_listing(POP3_UIDL, "+OK\r\n1 " + uid70 + "\r\n.\r\n");
  match good {
    Ok(p) => { if !streq(pop3_uidl_id(&p, 1), uid70) { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "UIDL unique-ids are 1..70 bytes in 0x21..0x7E");
}

fn t24() -> TestResult {
  var ok = true;
  if !built_response_is(resp(true, false, "scan listing follows"), "+OK scan listing follows\r\n") { ok = false; }
  if !built_response_is(resp(true, false, ""), "+OK\r\n") { ok = false; }
  if !built_response_is(resp(false, false, "no such message"), "-ERR no such message\r\n") { ok = false; }
  if !built_response_is(resp(false, false, ""), "-ERR\r\n") { ok = false; }
  if !built_response_is(resp(true, true, ""), "+OK\r\n.\r\n") { ok = false; }
  var lines = Vec[Str].new();
  lines.push(".x");
  lines.push("plain");
  lines.push("");
  if !built_response_is(resp_lines(true, true, "", lines), "+OK\r\n..x\r\nplain\r\n\r\n.\r\n") { ok = false; }
  return assert(ok, "build_response emits canonical single-line and multi-line bytes");
}

fn t25() -> TestResult {
  var ok = true;
  var bad = Vec[Str].new();
  bad.push(".x");
  if !build_err(resp_lines(true, false, "", bad)) { ok = false; }
  if !build_err(resp(false, true, "")) { ok = false; }
  if !build_err(resp(true, false, "bad\u{0009}text")) { ok = false; }
  var cr = Vec[Str].new();
  cr.push("a\rb");
  if !build_err(resp_lines(true, true, "", cr)) { ok = false; }
  var lf = Vec[Str].new();
  lf.push("a\nb");
  if !build_err(resp_lines(true, true, "", lf)) { ok = false; }
  var longline = Vec[Str].new();
  longline.push(string.str_repeat("a", 511));
  if !build_err(resp_lines(true, true, "", longline)) { ok = false; }
  if !build_err(resp(true, false, string.str_repeat("a", 507))) { ok = false; }
  return assert(ok, "build_response rejects bad shapes, control bytes and CR/LF payload");
}

fn t26() -> TestResult {
  var ok = true;
  let cap = string.str_repeat("x", 505);
  let over = string.str_repeat("x", 506);
  let pass_cap = "PASS " + cap;
  let pass_over = "PASS " + over;
  if !built_is(req(POP3_PASS, cap, "", -1, -1), pass_cap + "\r\n") { ok = false; }
  let p = pop3_parse_request(pass_cap + "\r\n");
  match p {
    Ok(q) => { if !streq(q.text, cap) { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !req_err(pass_over + "\r\n") { ok = false; }
  if !req_build_err(req(POP3_PASS, over, "", -1, -1)) { ok = false; }
  let status_cap = "+OK " + string.str_repeat("x", 505);
  let rc = pop3_parse_response(false, status_cap + "\r\n");
  match rc {
    Ok(p2) => { if pop3_response_text(&p2).len() != 505 { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !resp_err(false, "+OK " + string.str_repeat("x", 507) + "\r\n") { ok = false; }
  return assert(ok, "line content caps at 510 bytes in both directions");
}

fn t27() -> TestResult {
  let text = "+OK\r\n1 120\r\n.\r\n";
  let r = pop3_parse_listing(POP3_LIST, text);
  var ok = false;
  match r {
    Ok(p) => {
      ok = pop3_pair_count(&p) == 1;
      if !streq(pop3_line(&p, -1), "") { ok = false; }
      if !streq(pop3_line(&p, 99), "") { ok = false; }
      if pop3_pair_num(&p, -1) != -1 { ok = false; }
      if pop3_pair_num(&p, 99) != -1 { ok = false; }
      if !streq(pop3_pair_val(&p, -1), "") { ok = false; }
      if !streq(pop3_pair_val(&p, 99), "") { ok = false; }
      if pop3_lookup_line(&p, 0) != -1 { ok = false; }
      if pop3_lookup_line(&p, 99) != -1 { ok = false; }
      if pop3_list_size(&p, 99) != -1 { ok = false; }
      if !streq(pop3_uidl_id(&p, 99), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let single = pop3_parse_response(false, "+OK done\r\n");
  match single {
    Ok(p) => {
      if pop3_pair_count(&p) != 0 { ok = false; }
      if !streq(pop3_payload(&p), "") { ok = false; }
      if pop3_line_count(&p) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessors are bounds-safe and return documented sentinels");
}

fn main() -> Int {
  io.println("=== xiom.pop3 conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.pop3: all tests passed");
  } else {
    io.println("xiom.pop3: tests failed");
  }
  return failed;
}
