// XIOM -- xiom.legacy-proto conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.legacy_proto module against its
// SPEC.md -- Finger query/response codecs, Gopher menu items and documents,
// WHOIS key-value records, the codec escape convention and the exact error
// catalogs -- with fixture-driven deterministic tests.
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison, so every comparison below
// (user names, keys, values, error messages) is routed through streq instead
// of `==`. The harness calls t1() ... t24() directly from main; indexed
// Vec[fn] dispatch is not used.

module legacy_proto_tests
use xiom.io; use xiom.test; use xiom.legacy_proto;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `r` parses as a Finger query with exactly this user/verbose pair.
fn q_is(r: Result[FingerQuery, Str], user: Str, verbose: Bool) -> Bool {
  match r {
    Ok(q) => {
      if !streq(q.username, user) { return false; }
      return q.verbose == verbose;
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when `r` fails with exactly the documented query error.
fn q_err_is(r: Result[FingerQuery, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `r` fails with exactly the documented response error.
fn resp_err_is(r: Result[FingerResponse, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `r` parses as a Gopher item with exactly these fields.
fn item_is(r: Result[GopherItem, Str], ty: Str, disp: Str, sel: Str, host: Str, port: Int) -> Bool {
  match r {
    Ok(it) => {
      if !streq(it.item_type, ty) { return false; }
      if !streq(it.display, disp) { return false; }
      if !streq(it.selector, sel) { return false; }
      if !streq(it.host, host) { return false; }
      return it.port == port;
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when `r` fails with exactly the documented item error.
fn item_err_is(r: Result[GopherItem, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `r` fails with exactly the documented menu error.
fn menu_err_is(r: Result[GopherMenu, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `r` fails with exactly the documented WHOIS error.
fn whois_err_is(r: Result[WhoisRecord, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when menu item `i` holds exactly these fields.
fn menu_item_is(m: &GopherMenu, i: Int, ty: Str, disp: Str, sel: Str, host: Str, port: Int) -> Bool {
  if !streq(gopher_item_type(m, i), ty) { return false; }
  if !streq(gopher_item_display(m, i), disp) { return false; }
  if !streq(gopher_item_selector(m, i), sel) { return false; }
  if !streq(gopher_item_host(m, i), host) { return false; }
  return gopher_item_port(m, i) == port;
}

// True when `o` is Some(want).
fn opt_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

// True when `o` is None.
fn opt_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// ---------------------------------------------------------------------------
// Finger (t1 - t8)
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = FINGER_PORT_DEFAULT == 79;
  if !q_is(finger_parse_query("ghost"), "ghost", false) { ok = false; }
  if !q_is(finger_parse_query("ghost/W"), "ghost", true) { ok = false; }
  if !q_is(finger_parse_query("ghost/w"), "ghost", true) { ok = false; }
  if !q_is(finger_parse_query("/W"), "", true) { ok = false; }
  if !q_is(finger_parse_query("  ghost/W  "), "ghost", true) { ok = false; }
  if !q_is(finger_parse_query("ghost\r\n"), "ghost", false) { ok = false; }
  return assert(ok, "finger query: user, /W, trimming, CRLF");
}

fn t2() -> TestResult {
  var ok = q_err_is(finger_parse_query(""), "finger: empty query");
  if !q_err_is(finger_parse_query("   "), "finger: empty query") { ok = false; }
  if !q_err_is(finger_parse_query("\r\n"), "finger: empty query") { ok = false; }
  if !q_err_is(finger_parse_query("gh ost"), "finger: whitespace in query") { ok = false; }
  if !q_err_is(finger_parse_query("a\tb"), "finger: whitespace in query") { ok = false; }
  return assert(ok, "finger query error catalog");
}

fn t3() -> TestResult {
  let q = FingerQuery{ username: "ghost"; verbose: false; };
  var ok = streq(finger_render_query(&q), "ghost\r\n");
  let q2 = FingerQuery{ username: "ghost"; verbose: true; };
  if !streq(finger_render_query(&q2), "ghost/W\r\n") { ok = false; }
  let q3 = FingerQuery{ username: ""; verbose: true; };
  if !streq(finger_render_query(&q3), "/W\r\n") { ok = false; }
  let rp = finger_parse_query(finger_render_query(&q2));
  if !q_is(rp, "ghost", true) { ok = false; }
  return assert(ok, "finger query canonical render and round-trip");
}

fn t4() -> TestResult {
  let r = finger_parse_response("Hello, world");
  var ok = false;
  match r {
    Ok(resp) => {
      ok = finger_line_count(&resp) == 1;
      if finger_is_multiline(&resp) { ok = false; }
      if resp.had_terminator { ok = false; }
      if !streq(finger_line(&resp, 0), "Hello, world") { ok = false; }
      if !streq(finger_render_response(&resp), "Hello, world\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = finger_parse_response("Hello, world\r\n");
  match r2 {
    Ok(resp2) => {
      if finger_line_count(&resp2) != 1 { ok = false; }
      if finger_is_multiline(&resp2) { ok = false; }
      if resp2.had_terminator { ok = false; }
      if !streq(finger_render_response(&resp2), "Hello, world\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "finger single-line response");
}

fn t5() -> TestResult {
  let r = finger_parse_response("Plan:\r\n1. be nice\r\n2. stay\r\n.\r\n");
  var ok = false;
  match r {
    Ok(resp) => {
      ok = finger_line_count(&resp) == 3;
      if !finger_is_multiline(&resp) { ok = false; }
      if !resp.had_terminator { ok = false; }
      if !streq(finger_line(&resp, 0), "Plan:") { ok = false; }
      if !streq(finger_line(&resp, 1), "1. be nice") { ok = false; }
      if !streq(finger_line(&resp, 2), "2. stay") { ok = false; }
      if !streq(finger_render_response(&resp), "Plan:\r\n1. be nice\r\n2. stay\r\n.\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "finger multi-line response with terminator");
}

fn t6() -> TestResult {
  let r = finger_parse_response("a\nb\rc");
  var ok = false;
  match r {
    Ok(resp) => {
      ok = finger_line_count(&resp) == 3;
      if !finger_is_multiline(&resp) { ok = false; }
      if resp.had_terminator { ok = false; }
      if !streq(finger_line(&resp, 0), "a") { ok = false; }
      if !streq(finger_line(&resp, 1), "b") { ok = false; }
      if !streq(finger_line(&resp, 2), "c") { ok = false; }
      if !streq(finger_render_response(&resp), "a\r\nb\r\nc\r\n.\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = finger_parse_response("a\r\n\r\nb");
  match r2 {
    Ok(resp2) => {
      if finger_line_count(&resp2) != 3 { ok = false; }
      if !streq(finger_line(&resp2, 1), "") { ok = false; }
      if !streq(finger_line(&resp2, 2), "b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "finger CRLF/LF/CR endings and empty lines");
}

fn t7() -> TestResult {
  let r = finger_parse_response("first\r\n.\r\nJUNK LINE\r\n");
  var ok = false;
  match r {
    Ok(resp) => {
      ok = finger_line_count(&resp) == 1;
      if !resp.had_terminator { ok = false; }
      if !finger_is_multiline(&resp) { ok = false; }
      if !streq(finger_line(&resp, 0), "first") { ok = false; }
      if !streq(finger_render_response(&resp), "first\r\n.\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "finger terminator ends the response");
}

fn t8() -> TestResult {
  var ok = resp_err_is(finger_parse_response(""), "finger: empty response");
  if !resp_err_is(finger_parse_response(".\r\n"), "finger: empty response") { ok = false; }
  let r = finger_parse_response("\r\n");
  match r {
    Ok(resp) => {
      if finger_line_count(&resp) != 1 { ok = false; }
      if !streq(finger_line(&resp, 0), "") { ok = false; }
      if !streq(finger_line(&resp, -1), "") { ok = false; }
      if !streq(finger_line(&resp, 5), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "finger response errors and accessor bounds");
}

// ---------------------------------------------------------------------------
// Gopher (t9 - t16)
// ---------------------------------------------------------------------------

fn t9() -> TestResult {
  var ok = GOPHER_PORT_DEFAULT == 70;
  let r = gopher_parse_item("1Floodgap Gopher\t/\tfloodgap.com\t70\r\n");
  if !item_is(r, "1", "Floodgap Gopher", "/", "floodgap.com", 70) { ok = false; }
  let r2 = gopher_parse_item("1Floodgap Gopher\t/\tfloodgap.com\t70\r\n");
  match r2 {
    Ok(it) => {
      if !streq(gopher_render_item(&it), "1Floodgap Gopher\t/\tfloodgap.com\t70\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "gopher item: type/display/selector/host/port");
}

fn t10() -> TestResult {
  let r = gopher_parse_item(".  Welcome to the menu");
  var ok = item_is(r, ".", "  Welcome to the menu", "", "", 0);
  let r2 = gopher_parse_item("iAbout us\t\tserver.example\t70\r\n");
  if !item_is(r2, "i", "About us", "", "server.example", 70) { ok = false; }
  let r3 = gopher_parse_item(".  Welcome to the menu");
  match r3 {
    Ok(it) => {
      if !streq(gopher_render_item(&it), ".  Welcome to the menu\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "gopher info text and empty selector");
}

fn t11() -> TestResult {
  let wire = ".a\\tb\\nc\\rd\\\\e\r\n";
  let r = gopher_parse_item(wire);
  var ok = false;
  match r {
    Ok(it) => {
      ok = streq(it.display, "a\tb\nc\rd\\e");
      if !streq(it.item_type, ".") { ok = false; }
      if !streq(gopher_render_item(&it), wire) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gopher_parse_item("1x\\qy\t/\thost\t70\r\n");
  match r2 {
    Ok(it2) => {
      if !streq(it2.display, "x\\qy") { ok = false; }
      if !streq(gopher_render_item(&it2), "1x\\\\qy\t/\thost\t70\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = gopher_parse_item(".x\\\r\n");
  match r3 {
    Ok(it3) => {
      if !streq(it3.display, "x\\") { ok = false; }
      if !streq(gopher_render_item(&it3), ".x\\\\\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "gopher field escaping round-trip");
}

fn t12() -> TestResult {
  var ok = item_is(gopher_parse_item("1a\t/\th\t0\r\n"), "1", "a", "/", "h", 0);
  let b = gopher_parse_item("1a\t/\th\t0070\r\n");
  match b {
    Ok(it) => {
      if it.port != 70 { ok = false; }
      if !streq(gopher_render_item(&it), "1a\t/\th\t70\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !item_is(gopher_parse_item("1a\t/\th\t65535"), "1", "a", "/", "h", 65535) { ok = false; }
  if !item_err_is(gopher_parse_item("1a\t/\th\t65536\r\n"), "gopher: invalid port") { ok = false; }
  if !item_err_is(gopher_parse_item("1a\t/\th\t12x\r\n"), "gopher: invalid port") { ok = false; }
  if !item_err_is(gopher_parse_item("1a\t/\th\t\r\n"), "gopher: invalid port") { ok = false; }
  if !item_err_is(gopher_parse_item("1a\t/\th\t123456\r\n"), "gopher: invalid port") { ok = false; }
  return assert(ok, "gopher port parsing");
}

fn t13() -> TestResult {
  var ok = item_err_is(gopher_parse_item(""), "gopher: empty line");
  if !item_err_is(gopher_parse_item("\r\n"), "gopher: empty line") { ok = false; }
  if !item_err_is(gopher_parse_item("1abc"), "gopher: missing fields") { ok = false; }
  if !item_err_is(gopher_parse_item("1a\tb\tc"), "gopher: missing fields") { ok = false; }
  if !item_err_is(gopher_parse_item("1a\tb\tc\td\te"), "gopher: too many fields") { ok = false; }
  if !item_err_is(gopher_parse_item(" \t/\thost\t70"), "gopher: invalid item type") { ok = false; }
  if !item_err_is(gopher_parse_item("\u{e9}x\t/\thost\t70"), "gopher: invalid item type") { ok = false; }
  if !item_is(gopher_parse_item("1a\tb\tc\t70"), "1", "a", "b", "c", 70) { ok = false; }
  return assert(ok, "gopher malformed line catalog");
}

fn t14() -> TestResult {
  let wire = "1Root\t/\tserver.example\t70\r\n. Please choose:\r\niAbout\t\tserver.example\t70\n";
  let r = gopher_parse_menu(wire);
  var ok = false;
  match r {
    Ok(m) => {
      ok = gopher_item_count(&m) == 3;
      if !menu_item_is(&m, 0, "1", "Root", "/", "server.example", 70) { ok = false; }
      if gopher_item_is_text(&m, 0) { ok = false; }
      if !gopher_item_is_text(&m, 1) { ok = false; }
      if !streq(gopher_item_display(&m, 1), " Please choose:") { ok = false; }
      if !streq(gopher_item_selector(&m, 1), "") { ok = false; }
      if gopher_item_port(&m, 1) != 0 { ok = false; }
      if !menu_item_is(&m, 2, "i", "About", "", "server.example", 70) { ok = false; }
      if !streq(gopher_render_menu(&m), "1Root\t/\tserver.example\t70\r\n. Please choose:\r\niAbout\t\tserver.example\t70\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "gopher menu parse and canonical render");
}

fn t15() -> TestResult {
  var ok = menu_err_is(gopher_parse_menu(""), "gopher: empty menu");
  if !menu_err_is(gopher_parse_menu("\r\n"), "gopher: line 1: empty line") { ok = false; }
  if !menu_err_is(gopher_parse_menu("1ok\t/\th\t70\r\n1bad\t/\th\t99999\r\n"), "gopher: line 2: invalid port") { ok = false; }
  if !menu_err_is(gopher_parse_menu("1a\tb\tc\t70\r\n2x\ty\tz\tw\tv\r\n"), "gopher: line 2: too many fields") { ok = false; }
  return assert(ok, "gopher menu error catalog");
}

fn t16() -> TestResult {
  let wire = "1A\t/a\ta.example\t70\r\n.gopher menu\r\n0B\t/b\tb.example\t71\r\n";
  let r = gopher_parse_menu(wire);
  var ok = false;
  match r {
    Ok(m) => {
      ok = streq(gopher_render_menu(&m), wire);
      let r2 = gopher_parse_menu(gopher_render_menu(&m));
      match r2 {
        Ok(m2) => {
          if gopher_item_count(&m2) != 3 { ok = false; }
          if !menu_item_is(&m2, 0, "1", "A", "/a", "a.example", 70) { ok = false; }
          if !streq(gopher_item_display(&m2, 1), "gopher menu") { ok = false; }
          if !menu_item_is(&m2, 2, "0", "B", "/b", "b.example", 71) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "gopher menu round-trip");
}

// ---------------------------------------------------------------------------
// WHOIS (t17 - t24)
// ---------------------------------------------------------------------------

fn t17() -> TestResult {
  var ok = WHOIS_PORT_DEFAULT == 43;
  let text = "Domain Name: EXAMPLE.COM\r\nRegistrar: Example Registrar, Inc.\r\n";
  let r = whois_parse(text);
  match r {
    Ok(rec) => {
      if whois_field_count(&rec) != 2 { ok = false; }
      if !streq(whois_key(&rec, 0), "Domain Name") { ok = false; }
      if !streq(whois_value(&rec, 0), "EXAMPLE.COM") { ok = false; }
      if !streq(whois_key(&rec, 1), "Registrar") { ok = false; }
      if !streq(whois_value(&rec, 1), "Example Registrar, Inc.") { ok = false; }
      if whois_comment_count(&rec) != 0 { ok = false; }
      if whois_continuation_count(&rec, 0) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !ok { ok = false; }
  return assert(ok, "whois basic fields");
}

fn t18() -> TestResult {
  let text = "% The data in this whois database is provided for information\r\n# second comment\r\n\r\nDomain Name: EXAMPLE.COM\r\n";
  let r = whois_parse(text);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = whois_comment_count(&rec) == 2;
      if !streq(whois_comment(&rec, 0), "% The data in this whois database is provided for information") { ok = false; }
      if !streq(whois_comment(&rec, 1), "# second comment") { ok = false; }
      if whois_field_count(&rec) != 1 { ok = false; }
      if !streq(whois_key(&rec, 0), "Domain Name") { ok = false; }
      if !streq(whois_comment(&rec, -1), "") { ok = false; }
      if !streq(whois_comment(&rec, 9), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whois comments and blank lines");
}

fn t19() -> TestResult {
  let text = "Registrant: Jane Doe\r\n   Acme Widgets\r\n  123 Main St\r\nAdmin: Bob\r\n";
  let r = whois_parse(text);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = whois_field_count(&rec) == 2;
      if whois_continuation_count(&rec, 0) != 2 { ok = false; }
      if !streq(whois_continuation(&rec, 0, 0), "Acme Widgets") { ok = false; }
      if !streq(whois_continuation(&rec, 0, 1), "123 Main St") { ok = false; }
      if !streq(whois_continuation(&rec, 0, 2), "") { ok = false; }
      if !streq(whois_value(&rec, 0), "Jane Doe") { ok = false; }
      if whois_continuation_count(&rec, 1) != 0 { ok = false; }
      if !streq(whois_continuation(&rec, 1, 0), "") { ok = false; }
      if whois_continuation_count(&rec, -1) != 0 { ok = false; }
      if !streq(whois_key(&rec, 1), "Admin") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whois continuations");
}

fn t20() -> TestResult {
  let text = "Name Server: NS1.EXAMPLE.COM\r\nName Server: NS2.EXAMPLE.COM\r\nStatus: active\r\n";
  let r = whois_parse(text);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = whois_field_count(&rec) == 3;
      if whois_count(&rec, "Name Server") != 2 { ok = false; }
      if whois_count(&rec, "nope") != 0 { ok = false; }
      if !opt_is(whois_field(&rec, "Name Server"), "NS2.EXAMPLE.COM") { ok = false; }
      if !opt_is(whois_field(&rec, "Status"), "active") { ok = false; }
      if !opt_none(whois_field(&rec, "Nope")) { ok = false; }
      if !streq(whois_key(&rec, 1), "Name Server") { ok = false; }
      if !streq(whois_value(&rec, 1), "NS2.EXAMPLE.COM") { ok = false; }
      if !streq(whois_key(&rec, 3), "") { ok = false; }
      if !streq(whois_value(&rec, 3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whois repeated keys and lookup");
}

fn t21() -> TestResult {
  let text = "URL: http://example.com/x\r\nStatus:\r\nComment: a: b: c\r\n";
  let r = whois_parse(text);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = whois_field_count(&rec) == 3;
      if !streq(whois_value(&rec, 0), "http://example.com/x") { ok = false; }
      if !streq(whois_key(&rec, 1), "Status") { ok = false; }
      if !streq(whois_value(&rec, 1), "") { ok = false; }
      if !streq(whois_value(&rec, 2), "a: b: c") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whois values with colons and empty values");
}

fn t22() -> TestResult {
  let text = "% note\r\nDomain Name: X\r\nRegistrant: Jane\r\n  Acme\r\n";
  let r = whois_parse(text);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = streq(whois_render(&rec), "% note\r\nDomain Name: X\r\nRegistrant: Jane\r\nAcme\r\n");
      let r2 = whois_parse(whois_render(&rec));
      match r2 {
        Ok(rec2) => {
          if whois_field_count(&rec2) != whois_field_count(&rec) { ok = false; }
          if whois_comment_count(&rec2) != whois_comment_count(&rec) { ok = false; }
          if whois_continuation_count(&rec2, 1) != 1 { ok = false; }
          if !opt_is(whois_field(&rec2, "Registrant"), "Jane") { ok = false; }
          if !streq(whois_continuation(&rec2, 1, 0), "Acme") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let tail = whois_parse("Domain Name: Y\r\n% trailing note\r\n");
  match tail {
    Ok(rec3) => {
      if !streq(whois_render(&rec3), "% trailing note\r\nDomain Name: Y\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whois canonical render and reparse");
}

fn t23() -> TestResult {
  var ok = whois_err_is(whois_parse(""), "whois: empty response");
  if !whois_err_is(whois_parse("   \r\n"), "whois: empty response") { ok = false; }
  if !whois_err_is(whois_parse(": bad"), "whois: empty key") { ok = false; }
  if !whois_err_is(whois_parse("   :x"), "whois: empty key") { ok = false; }
  if !whois_err_is(whois_parse("orphan continuation"), "whois: continuation before any field") { ok = false; }
  return assert(ok, "whois error catalog");
}

fn t24() -> TestResult {
  let doc = "% WHOIS server\r\n% For more information\r\nDomain Name: EXAMPLE.COM\r\nRegistry Domain ID: 2336799_DOMAIN_COM-VRSN\r\nRegistrar WHOIS Server: whois.example-registrar.com\r\nName Server: NS1.EXAMPLE.COM\r\nName Server: NS2.EXAMPLE.COM\r\nDNSSEC: unsigned\r\n\r\n>>> Last update of whois database: 2026-01-01T00:00:00Z <<<\r\n";
  let r = whois_parse(doc);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = whois_field_count(&rec) == 7;
      if whois_comment_count(&rec) != 2 { ok = false; }
      if whois_count(&rec, "Name Server") != 2 { ok = false; }
      if !opt_is(whois_field(&rec, "Name Server"), "NS2.EXAMPLE.COM") { ok = false; }
      if !opt_is(whois_field(&rec, "DNSSEC"), "unsigned") { ok = false; }
      if !streq(whois_key(&rec, 6), ">>> Last update of whois database") { ok = false; }
      if !streq(whois_value(&rec, 6), "2026-01-01T00:00:00Z <<<") { ok = false; }
      let rendered = whois_render(&rec);
      let r2 = whois_parse(rendered);
      match r2 {
        Ok(rec2) => {
          if whois_field_count(&rec2) != whois_field_count(&rec) { ok = false; }
          if whois_comment_count(&rec2) != whois_comment_count(&rec) { ok = false; }
          if whois_count(&rec2, "Name Server") != 2 { ok = false; }
          if !opt_is(whois_field(&rec2, "Registry Domain ID"), "2336799_DOMAIN_COM-VRSN") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whois realistic record round-trip");
}

fn main() -> Int {
  io.println("=== xiom.legacy_proto conformance tests ===");
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
    io.println("xiom.legacy_proto: all tests passed");
  } else {
    io.println("xiom.legacy_proto: tests failed");
  }
  return failed;
}
