// XIOM -- xiom.resolv conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 10. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// No Vec[fn] dispatch and no `==` on Str values read from Vec[Str] elements
// (BUG 17: that lowers to a pointer comparison); every string comparison
// goes through compare.str_compare and every element read binds a typed
// local first.

module resolv_tests
use xiom.io; use xiom.test; use xiom.resolv;
use xiom.string;
use xiom.string.compare;

// String equality through the stdlib comparator (never `==` on Str).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when the Option[Str] is Some with exactly `want`.
fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

// True when the Option[Str] is None.
fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// True when both options are None or both are Some with equal text.
fn opt_eq(x: Option[Str], y: Option[Str]) -> Bool {
  match x {
    Some(v) => { return opt_str_is(y, v); },
    None => { return opt_str_none(y); },
  }
  return false;
}

// True when nameserver i equals `want`.
fn ns_at(d: &ResolvConf, i: Int, want: Str) -> Bool {
  return opt_str_is(resolv_nameserver(d, i), want);
}

// True when search domain i equals `want`.
fn search_at(d: &ResolvConf, i: Int, want: Str) -> Bool {
  return opt_str_is(resolv_search_domain(d, i), want);
}

// True when option token i equals `want`.
fn option_at(d: &ResolvConf, i: Int, want: Str) -> Bool {
  return opt_str_is(resolv_option(d, i), want);
}

// True when sortlist address i equals `want`.
fn sort_at(d: &ResolvConf, i: Int, want: Str) -> Bool {
  return opt_str_is(resolv_sortlist_addr(d, i), want);
}

// True when sortlist mask i equals `want`.
fn mask_at(d: &ResolvConf, i: Int, want: Int) -> Bool {
  return resolv_sortlist_mask(d, i) == want;
}

// True when unknown/legacy line i equals `want`.
fn unknown_at(d: &ResolvConf, i: Int, want: Str) -> Bool {
  return opt_str_is(resolv_unknown_line(d, i), want);
}

// True when resolv_parse(text) is Err with exactly `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = resolv_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Repeated concatenation, for length-boundary inputs.
fn repeat_str(s: Str, n: Int) -> Str {
  var out = "";
  var i = 0;
  while i < n {
    out = out + s;
    i = i + 1;
  }
  return out;
}

// A Str containing `prefix`, one raw byte `c` and `suffix` (test inputs only;
// the parser must reject the control byte before it is ever emitted).
fn mk_ctrl(prefix: Str, c: Int, suffix: Str) -> Str {
  var b = Vec[UInt8].new();
  var i = 0;
  while i < prefix.len() {
    b.push(string.byte_at(prefix, i));
    i = i + 1;
  }
  b.push(c as UInt8);
  i = 0;
  while i < suffix.len() {
    b.push(string.byte_at(suffix, i));
    i = i + 1;
  }
  return Str::from_utf8(b);
}

// True when two documents hold the same content in the same order
// (nameservers, domain, search, options, sortlist addresses/masks and
// unknown lines; nothing else is stored).
fn same_doc(a: &ResolvConf, b: &ResolvConf) -> Bool {
  if resolv_nameserver_count(a) != resolv_nameserver_count(b) { return false; }
  var i = 0;
  while i < resolv_nameserver_count(a) {
    if !opt_eq(resolv_nameserver(a, i), resolv_nameserver(b, i)) { return false; }
    i = i + 1;
  }
  if !opt_eq(resolv_domain(a), resolv_domain(b)) { return false; }
  if resolv_search_count(a) != resolv_search_count(b) { return false; }
  i = 0;
  while i < resolv_search_count(a) {
    if !opt_eq(resolv_search_domain(a, i), resolv_search_domain(b, i)) { return false; }
    i = i + 1;
  }
  if resolv_option_count(a) != resolv_option_count(b) { return false; }
  i = 0;
  while i < resolv_option_count(a) {
    if !opt_eq(resolv_option(a, i), resolv_option(b, i)) { return false; }
    i = i + 1;
  }
  if resolv_sortlist_count(a) != resolv_sortlist_count(b) { return false; }
  i = 0;
  while i < resolv_sortlist_count(a) {
    if !opt_eq(resolv_sortlist_addr(a, i), resolv_sortlist_addr(b, i)) { return false; }
    if resolv_sortlist_mask(a, i) != resolv_sortlist_mask(b, i) { return false; }
    i = i + 1;
  }
  if resolv_unknown_count(a) != resolv_unknown_count(b) { return false; }
  i = 0;
  while i < resolv_unknown_count(a) {
    if !opt_eq(resolv_unknown_line(a, i), resolv_unknown_line(b, i)) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = resolv_parse("nameserver 192.0.2.1\nnameserver 2001:DB8::53\ndomain example.com\nsearch a.example b.example\noptions ndots:5 rotate\nsortlist 10.0.0.0/8 2001:db8::1/128\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_nameserver_count(&d) == 2;
      if !ns_at(&d, 0, "192.0.2.1") { ok = false; }
      if !ns_at(&d, 1, "2001:db8::53") { ok = false; }
      if !opt_str_is(resolv_domain(&d), "example.com") { ok = false; }
      if resolv_search_count(&d) != 2 { ok = false; }
      if !search_at(&d, 0, "a.example") { ok = false; }
      if !search_at(&d, 1, "b.example") { ok = false; }
      if resolv_option_count(&d) != 2 { ok = false; }
      if !option_at(&d, 0, "ndots:5") { ok = false; }
      if !streq(resolv_option_name(&d, 0), "ndots") { ok = false; }
      if !opt_str_is(resolv_option_value(&d, 0), "5") { ok = false; }
      if !streq(resolv_option_name(&d, 1), "rotate") { ok = false; }
      if !opt_str_none(resolv_option_value(&d, 1)) { ok = false; }
      if resolv_sortlist_count(&d) != 2 { ok = false; }
      if !sort_at(&d, 0, "10.0.0.0") { ok = false; }
      if !mask_at(&d, 0, 8) { ok = false; }
      if !sort_at(&d, 1, "2001:db8::1") { ok = false; }
      if !mask_at(&d, 1, 128) { ok = false; }
      if resolv_unknown_count(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full document: directive counts and accessors");
}

fn t2() -> TestResult {
  let r = resolv_parse("nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_nameserver_count(&d) == 3;
      if !ns_at(&d, 0, "1.1.1.1") { ok = false; }
      if !ns_at(&d, 1, "8.8.8.8") { ok = false; }
      if !ns_at(&d, 2, "9.9.9.9") { ok = false; }
      let all = resolv_nameservers(&d);
      if all.len() != 3 { ok = false; }
      let a0: Str = all[0];
      let a2: Str = all[2];
      if !streq(a0, "1.1.1.1") { ok = false; }
      if !streq(a2, "9.9.9.9") { ok = false; }
      all.push("mutated");
      let fresh = resolv_nameservers(&d);
      if fresh.len() != 3 { ok = false; }
      if resolv_nameserver_count(&d) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "nameservers accumulate in order; list helper is fresh");
}

fn t3() -> TestResult {
  let r4 = resolv_parse("nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\nnameserver 4.4.4.4\n");
  var ok = false;
  match r4 {
    Ok(d) => {
      ok = resolv_nameserver_count(&d) == 4;
      if !resolv_nameserver_over_limit(&d) { ok = false; }
      if !ns_at(&d, 3, "4.4.4.4") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = resolv_parse("nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\n");
  match r3 {
    Ok(d) => {
      if resolv_nameserver_over_limit(&d) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r0 = resolv_parse("");
  match r0 {
    Ok(d) => {
      if resolv_nameserver_count(&d) != 0 { ok = false; }
      if resolv_nameserver_over_limit(&d) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r5 = resolv_parse("nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\nnameserver 4.4.4.4\nnameserver 6.6.6.6\n");
  match r5 {
    Ok(d) => {
      if resolv_nameserver_count(&d) != 5 { ok = false; }
      if !resolv_nameserver_over_limit(&d) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "more than three nameservers accepted; over-limit is informational");
}

fn t4() -> TestResult {
  let r = resolv_parse("nameserver 2001:DB8::1\nnameserver 0:0:0:0:0:0:0:1\nnameserver ::FFFF:192.168.1.1\nnameserver ::1\nnameserver 1:2:3:4:5:6:7:8\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_nameserver_count(&d) == 5;
      if !ns_at(&d, 0, "2001:db8::1") { ok = false; }
      if !ns_at(&d, 1, "0:0:0:0:0:0:0:1") { ok = false; }
      if !ns_at(&d, 2, "::ffff:192.168.1.1") { ok = false; }
      if !ns_at(&d, 3, "::1") { ok = false; }
      if !ns_at(&d, 4, "1:2:3:4:5:6:7:8") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "IPv6 nameservers lowercased, not compressed; v4 tail kept");
}

fn t5() -> TestResult {
  let r = resolv_parse("domain first.example\nsearch a.example b.example c.example\ndomain second.example\nsearch d.example\nsearch e.example f.example\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(resolv_domain(&d), "second.example");
      if resolv_search_count(&d) != 2 { ok = false; }
      if !search_at(&d, 0, "e.example") { ok = false; }
      if !search_at(&d, 1, "f.example") { ok = false; }
      if !opt_str_none(resolv_search_domain(&d, 2)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = resolv_parse("search only.example\n");
  match r2 {
    Ok(d2) => {
      if resolv_search_count(&d2) != 1 { ok = false; }
      if !search_at(&d2, 0, "only.example") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "domain and search are last-directive-wins");
}

fn t6() -> TestResult {
  let r = resolv_parse("search A.Example _tcp.b.example 3com.example\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_search_count(&d) == 3;
      if !search_at(&d, 0, "A.Example") { ok = false; }
      if !search_at(&d, 1, "_tcp.b.example") { ok = false; }
      if !search_at(&d, 2, "3com.example") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "search domains kept verbatim, in written order");
}

fn t7() -> TestResult {
  let r = resolv_parse("options ndots:5\noptions timeout:2 rotate\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_option_count(&d) == 3;
      if !option_at(&d, 0, "ndots:5") { ok = false; }
      if !streq(resolv_option_name(&d, 0), "ndots") { ok = false; }
      if !opt_str_is(resolv_option_value(&d, 0), "5") { ok = false; }
      if !option_at(&d, 1, "timeout:2") { ok = false; }
      if !streq(resolv_option_name(&d, 1), "timeout") { ok = false; }
      if !opt_str_is(resolv_option_value(&d, 1), "2") { ok = false; }
      if !option_at(&d, 2, "rotate") { ok = false; }
      if !streq(resolv_option_name(&d, 2), "rotate") { ok = false; }
      if !opt_str_none(resolv_option_value(&d, 2)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "options: tokens verbatim, name/value split on first colon");
}

fn t8() -> TestResult {
  let r = resolv_parse("options ndots:5 timeout:2 rotate ndots:9\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_option_index(&d, "ndots") == 0;
      if resolv_option_index(&d, "timeout") != 1 { ok = false; }
      if resolv_option_index(&d, "rotate") != 2 { ok = false; }
      if resolv_option_index(&d, "NDOTS") != -1 { ok = false; }
      if resolv_option_index(&d, "attempts") != -1 { ok = false; }
      if resolv_option_index(&d, "ndots:5") != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "option lookup: first match by name, case-sensitive");
}

fn t9() -> TestResult {
  let r = resolv_parse("sortlist 192.0.2.0/24 198.51.100.7\nsortlist 2001:DB8::/32 ::1/128\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_sortlist_count(&d) == 4;
      if !sort_at(&d, 0, "192.0.2.0") { ok = false; }
      if !mask_at(&d, 0, 24) { ok = false; }
      if !sort_at(&d, 1, "198.51.100.7") { ok = false; }
      if !mask_at(&d, 1, -1) { ok = false; }
      if !sort_at(&d, 2, "2001:db8::") { ok = false; }
      if !mask_at(&d, 2, 32) { ok = false; }
      if !sort_at(&d, 3, "::1") { ok = false; }
      if !mask_at(&d, 3, 128) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "sortlist: v4/v6 entries with and without masks, in order");
}

fn t10() -> TestResult {
  let r = resolv_parse("sortlist 0.0.0.0/0 ::/0 255.255.255.255/32 1:2:3:4:5:6:7:8/128\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_sortlist_count(&d) == 4;
      if !mask_at(&d, 0, 0) { ok = false; }
      if !mask_at(&d, 1, 0) { ok = false; }
      if !mask_at(&d, 2, 32) { ok = false; }
      if !mask_at(&d, 3, 128) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is("sortlist 1.2.3.4/33\n", "resolv: bad mask: 1.2.3.4/33") { ok = false; }
  if !parse_err_is("sortlist 2001:db8::1/129\n", "resolv: bad mask: 2001:db8::1/129") { ok = false; }
  if !parse_err_is("sortlist 1.2.3.4/\n", "resolv: bad mask: 1.2.3.4/") { ok = false; }
  if !parse_err_is("sortlist 1.2.3.4/024\n", "resolv: bad mask: 1.2.3.4/024") { ok = false; }
  if !parse_err_is("sortlist 1.2.3.4/abc\n", "resolv: bad mask: 1.2.3.4/abc") { ok = false; }
  if !parse_err_is("sortlist 1.2.3.4/24/8\n", "resolv: bad mask: 1.2.3.4/24/8") { ok = false; }
  if !parse_err_is("sortlist 1.2.3.4/+1\n", "resolv: bad mask: 1.2.3.4/+1") { ok = false; }
  if !parse_err_is("sortlist 1.2.3.4/-1\n", "resolv: bad mask: 1.2.3.4/-1") { ok = false; }
  return assert(ok, "sortlist masks: 0/32/128 boundaries, bad masks rejected");
}

fn t11() -> TestResult {
  var ok = parse_err_is("nameserver 256.0.0.1\n", "resolv: bad address: 256.0.0.1");
  if !parse_err_is("nameserver 01.2.3.4\n", "resolv: bad address: 01.2.3.4") { ok = false; }
  if !parse_err_is("nameserver 1.2.3\n", "resolv: bad address: 1.2.3") { ok = false; }
  if !parse_err_is("nameserver 1.2.3.4.5\n", "resolv: bad address: 1.2.3.4.5") { ok = false; }
  if !parse_err_is("nameserver 1:2:3:4:5:6:7\n", "resolv: bad address: 1:2:3:4:5:6:7") { ok = false; }
  if !parse_err_is("nameserver 1::2::3\n", "resolv: bad address: 1::2::3") { ok = false; }
  if !parse_err_is("nameserver 10000::\n", "resolv: bad address: 10000::") { ok = false; }
  if !parse_err_is("nameserver :::\n", "resolv: bad address: :::") { ok = false; }
  if !parse_err_is("nameserver ::%eth0\n", "resolv: bad address: ::%eth0") { ok = false; }
  if !parse_err_is("nameserver host\n", "resolv: bad address: host") { ok = false; }
  if !parse_err_is("nameserver 1.2.3.4/24\n", "resolv: bad address: 1.2.3.4/24") { ok = false; }
  if !parse_err_is("sortlist abc/24\n", "resolv: bad address: abc/24") { ok = false; }
  if !parse_err_is("sortlist 1.2.3.4/x\n", "resolv: bad mask: 1.2.3.4/x") { ok = false; }
  let r = resolv_parse("nameserver 1:2:3:4:5:6:1.2.3.4\n");
  match r {
    Ok(d) => {
      if resolv_nameserver_count(&d) != 1 { ok = false; }
      if !ns_at(&d, 0, "1:2:3:4:5:6:1.2.3.4") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bad addresses rejected with exact errors; v4 tail accepted");
}

fn t12() -> TestResult {
  var ok = parse_err_is("nameserver\n", "resolv: empty directive value: nameserver");
  if !parse_err_is("domain\n", "resolv: empty directive value: domain") { ok = false; }
  if !parse_err_is("search\n", "resolv: empty directive value: search") { ok = false; }
  if !parse_err_is("options\n", "resolv: empty directive value: options") { ok = false; }
  if !parse_err_is("sortlist\n", "resolv: empty directive value: sortlist") { ok = false; }
  if !parse_err_is("nameserver   # note\n", "resolv: empty directive value: nameserver") { ok = false; }
  if !parse_err_is("nameserver\t \n", "resolv: empty directive value: nameserver") { ok = false; }
  if !parse_err_is("domain # c\n", "resolv: empty directive value: domain") { ok = false; }
  if !parse_err_is("search ; c\n", "resolv: empty directive value: search") { ok = false; }
  if !parse_err_is("options \t# c\n", "resolv: empty directive value: options") { ok = false; }
  if !parse_err_is("nameserver 1.1.1.1\nsortlist\n", "resolv: empty directive value: sortlist") { ok = false; }
  return assert(ok, "empty directive value for the five modelled keywords");
}

fn t13() -> TestResult {
  var ok = parse_err_is("nameserver 1.1.1.1 8.8.8.8\n", "resolv: unexpected argument: 8.8.8.8");
  if !parse_err_is("nameserver 999.1.1.1 8.8.8.8\n", "resolv: unexpected argument: 8.8.8.8") { ok = false; }
  if !parse_err_is("domain a.example b.example\n", "resolv: unexpected argument: b.example") { ok = false; }
  if !parse_err_is("domain a.example b\n", "resolv: unexpected argument: b") { ok = false; }
  let r = resolv_parse("domain a.example # note\nsearch a b c\noptions a b c\nsortlist 1.1.1.1 8.8.8.8\n");
  match r {
    Ok(d) => {
      if !opt_str_is(resolv_domain(&d), "a.example") { ok = false; }
      if resolv_search_count(&d) != 3 { ok = false; }
      if resolv_option_count(&d) != 3 { ok = false; }
      if resolv_sortlist_count(&d) != 2 { ok = false; }
      if !mask_at(&d, 0, -1) { ok = false; }
      if !mask_at(&d, 1, -1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unexpected argument: argument count checked first");
}

fn t14() -> TestResult {
  var ok = parse_err_is("options :5\n", "resolv: bad option: :5");
  if !parse_err_is("options ndots:\n", "resolv: bad option: ndots:") { ok = false; }
  if !parse_err_is("options a:b:c\n", "resolv: bad option: a:b:c") { ok = false; }
  if !parse_err_is("options rotate :5\n", "resolv: bad option: :5") { ok = false; }
  if !parse_err_is("options ndots:5 ndots:\n", "resolv: bad option: ndots:") { ok = false; }
  let r = resolv_parse("options rotate no-check-names trust-ad edns0 a-b_c:1\n");
  match r {
    Ok(d) => {
      if resolv_option_count(&d) != 5 { ok = false; }
      if !option_at(&d, 0, "rotate") { ok = false; }
      if !option_at(&d, 1, "no-check-names") { ok = false; }
      if !option_at(&d, 2, "trust-ad") { ok = false; }
      if !option_at(&d, 3, "edns0") { ok = false; }
      if !option_at(&d, 4, "a-b_c:1") { ok = false; }
      if !streq(resolv_option_name(&d, 4), "a-b_c") { ok = false; }
      if !opt_str_is(resolv_option_value(&d, 4), "1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bad option tokens rejected; documented forms accepted");
}

fn t15() -> TestResult {
  let r = resolv_parse("# full line comment\n; semicolon line\nnameserver 192.0.2.1 # note\nnameserver 192.0.2.2;note\nnameserver 192.0.2.3#tight\noptions rotate#cut\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_nameserver_count(&d) == 3;
      if !ns_at(&d, 0, "192.0.2.1") { ok = false; }
      if !ns_at(&d, 1, "192.0.2.2") { ok = false; }
      if !ns_at(&d, 2, "192.0.2.3") { ok = false; }
      if resolv_option_count(&d) != 1 { ok = false; }
      if !option_at(&d, 0, "rotate") { ok = false; }
      if resolv_unknown_count(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments start at the first # or ;, even mid-token");
}

fn t16() -> TestResult {
  let r1 = resolv_parse("search a.example \\\n  b.example\n");
  var ok = false;
  match r1 {
    Ok(d) => {
      ok = resolv_search_count(&d) == 2;
      if !search_at(&d, 0, "a.example") { ok = false; }
      if !search_at(&d, 1, "b.example") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = resolv_parse("search a.example\\\nb.example\n");
  match r2 {
    Ok(d2) => {
      if resolv_search_count(&d2) != 1 { ok = false; }
      if !search_at(&d2, 0, "a.exampleb.example") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = resolv_parse("search a.example \\# note\nb.example\n");
  match r3 {
    Ok(d3) => {
      if resolv_search_count(&d3) != 2 { ok = false; }
      if !search_at(&d3, 1, "b.example") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is("nameserver 1.1.1.1\\x\n", "resolv: bad address: 1.1.1.1\\x") { ok = false; }
  let r4 = resolv_parse("lookup file \\\nbind\n");
  match r4 {
    Ok(d4) => {
      if resolv_unknown_count(&d4) != 1 { ok = false; }
      if !unknown_at(&d4, 0, "lookup file bind") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "continuation: backslash joins with the next physical line");
}

fn t17() -> TestResult {
  var ok = parse_err_is("nameserver 1.1.1.1\\", "resolv: backslash at end of input");
  if !parse_err_is("nameserver 1.1.1.1\\\n", "resolv: backslash at end of input") { ok = false; }
  if !parse_err_is("nameserver 1.1.1.1\\\r\n", "resolv: backslash at end of input") { ok = false; }
  if !parse_err_is("search a.example\\", "resolv: backslash at end of input") { ok = false; }
  let r1 = resolv_parse("nameserver 1.1.1.1\\\n\n");
  var pos = false;
  match r1 {
    Ok(d) => {
      pos = resolv_nameserver_count(&d) == 1;
      if !ns_at(&d, 0, "1.1.1.1") { pos = false; }
    },
    Err(_) => { pos = false; },
  }
  if !pos { ok = false; }
  let r2 = resolv_parse("nameserver 1.1.1.1\\\n# done\n");
  match r2 {
    Ok(d2) => {
      if resolv_nameserver_count(&d2) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "backslash on the final physical line is an error");
}

fn t18() -> TestResult {
  let r = resolv_parse("\r\nnameserver 1.1.1.1\r\n\r\nnameserver 8.8.8.8");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_nameserver_count(&d) == 2;
      if !ns_at(&d, 0, "1.1.1.1") { ok = false; }
      if !ns_at(&d, 1, "8.8.8.8") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = resolv_parse("nameserver 1.1.1.1\r");
  match r2 {
    Ok(d2) => {
      if resolv_nameserver_count(&d2) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e = resolv_parse("");
  match e {
    Ok(d3) => {
      if resolv_nameserver_count(&d3) != 0 { ok = false; }
      if resolv_unknown_count(&d3) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = resolv_parse("\n\n   \n\t\n");
  match b {
    Ok(d4) => {
      if resolv_nameserver_count(&d4) != 0 { ok = false; }
      if resolv_unknown_count(&d4) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "blank lines, CRLF, lone trailing CR and missing final newline");
}

fn t19() -> TestResult {
  var ok = parse_err_is(mk_ctrl("nameserver 1.1.1.1", 1, ""), "resolv: control byte in line 1");
  if !parse_err_is(mk_ctrl("nameserver 1.1.1.1", 127, ""), "resolv: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("nameserver 1.1.1.1", 13, " x"), "resolv: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("# comment", 1, ""), "resolv: control byte in line 1") { ok = false; }
  if !parse_err_is("nameserver 1.1.1.1\n" + (mk_ctrl("nameserver 8.8.8.8", 1, "")), "resolv: control byte in line 2") { ok = false; }
  let r = resolv_parse("nameserver\t1.1.1.1\nnameserver 8.8.8.8\r\n");
  var pos = false;
  match r {
    Ok(d) => {
      pos = resolv_nameserver_count(&d) == 2;
      if !ns_at(&d, 0, "1.1.1.1") { pos = false; }
    },
    Err(_) => { pos = false; },
  }
  if !pos { ok = false; }
  return assert(ok, "control bytes rejected; TAB and CRLF accepted; line numbering");
}

fn t20() -> TestResult {
  let cap = repeat_str("k", 4096);
  let over = repeat_str("k", 4097);
  let r = resolv_parse(cap + "\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_unknown_count(&d) == 1;
      if !unknown_at(&d, 0, cap) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is(over + "\n", "resolv: line too long: 1") { ok = false; }
  if !parse_err_is("nameserver 1.1.1.1\n" + over, "resolv: line too long: 2") { ok = false; }
  let c4096 = "#" + repeat_str("a", 4095);
  let rc = resolv_parse(c4096 + "\n");
  match rc {
    Ok(d2) => {
      if resolv_unknown_count(&d2) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let rc2 = resolv_parse(cap + "\r\n");
  match rc2 {
    Ok(d3) => {
      if resolv_unknown_count(&d3) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "physical line cap: 4096 accepted, 4097 rejected");
}

fn t21() -> TestResult {
  let r = resolv_parse("lookup file bind\nfamily inet6\nweird foo bar\nnameserver 1.1.1.1\nlookup dns\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = resolv_unknown_count(&d) == 4;
      if !unknown_at(&d, 0, "lookup file bind") { ok = false; }
      if !unknown_at(&d, 1, "family inet6") { ok = false; }
      if !unknown_at(&d, 2, "weird foo bar") { ok = false; }
      if !unknown_at(&d, 3, "lookup dns") { ok = false; }
      if resolv_nameserver_count(&d) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = resolv_parse("  lookup   file   bind  \n");
  match r2 {
    Ok(d2) => {
      if resolv_unknown_count(&d2) != 1 { ok = false; }
      if !unknown_at(&d2, 0, "lookup   file   bind") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = resolv_parse("NAMESERVER 1.1.1.1\n");
  match r3 {
    Ok(d3) => {
      if resolv_nameserver_count(&d3) != 0 { ok = false; }
      if resolv_unknown_count(&d3) != 1 { ok = false; }
      if !unknown_at(&d3, 0, "NAMESERVER 1.1.1.1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "lookup/family/unknown keywords pass through in order");
}

fn t22() -> TestResult {
  let r = resolv_parse("search b.example a.example\nnameserver 1.1.1.1\ndomain d.example\noptions rotate ndots:5\nsortlist 10.0.0.0/8\nlookup file bind\nnameserver 8.8.8.8\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(resolv_emit(&d), "nameserver 1.1.1.1\nnameserver 8.8.8.8\ndomain d.example\nsearch b.example a.example\noptions rotate ndots:5\nsortlist 10.0.0.0/8\nlookup file bind\n");
    },
    Err(_) => { ok = false; },
  }
  let e = resolv_parse("");
  match e {
    Ok(d2) => {
      if !streq(resolv_emit(&d2), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = resolv_parse("\n# only comments\n; more\n   \n");
  match c {
    Ok(d3) => {
      if !streq(resolv_emit(&d3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let n = resolv_parse("sortlist 1.2.3.4 5.6.7.8/24\n");
  match n {
    Ok(d4) => {
      if !streq(resolv_emit(&d4), "sortlist 1.2.3.4 5.6.7.8/24\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit: documented order, single spaces, LF, empty doc");
}

fn t23() -> TestResult {
  let text = "nameserver 1.1.1.1  # primary\r\nsearch A.example\\\n  b.example\ndomain D.example\noptions ndots:5 rotate\nsortlist 192.0.2.0/24 198.51.100.7\nlookup file bind\nnameserver 2001:DB8::53\nfamily inet6\n";
  let r1 = resolv_parse(text);
  var ok = false;
  match r1 {
    Ok(d1) => {
      let s1 = resolv_emit(&d1);
      let want = "nameserver 1.1.1.1\nnameserver 2001:db8::53\ndomain D.example\nsearch A.example b.example\noptions ndots:5 rotate\nsortlist 192.0.2.0/24 198.51.100.7\nlookup file bind\nfamily inet6\n";
      ok = streq(s1, want);
      let r2 = resolv_parse(s1);
      match r2 {
        Ok(d2) => {
          if !same_doc(&d1, &d2) { ok = false; }
          let s2 = resolv_emit(&d2);
          if !streq(s1, s2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "round-trip: emit(parse(x)) is a fixed point");
}

fn t24() -> TestResult {
  let r = resolv_parse("nameserver 1.1.1.1\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_none(resolv_nameserver(&d, -1));
      if !opt_str_none(resolv_nameserver(&d, 1)) { ok = false; }
      if !opt_str_none(resolv_domain(&d)) { ok = false; }
      if resolv_search_count(&d) != 0 { ok = false; }
      if !opt_str_none(resolv_search_domain(&d, 0)) { ok = false; }
      if resolv_option_count(&d) != 0 { ok = false; }
      if !opt_str_none(resolv_option(&d, 0)) { ok = false; }
      if !streq(resolv_option_name(&d, 0), "") { ok = false; }
      if !opt_str_none(resolv_option_value(&d, 0)) { ok = false; }
      if resolv_option_index(&d, "ndots") != -1 { ok = false; }
      if resolv_sortlist_count(&d) != 0 { ok = false; }
      if !opt_str_none(resolv_sortlist_addr(&d, 0)) { ok = false; }
      if resolv_sortlist_mask(&d, 0) != -1 { ok = false; }
      if resolv_unknown_count(&d) != 0 { ok = false; }
      if !opt_str_none(resolv_unknown_line(&d, 0)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessor guards: out-of-range results and mask sentinel");
}

fn t25() -> TestResult {
  var ok = resolv_address_valid("1.2.3.4");
  if !resolv_address_valid("0.0.0.0") { ok = false; }
  if !resolv_address_valid("255.255.255.255") { ok = false; }
  if !resolv_address_valid("::") { ok = false; }
  if !resolv_address_valid("::1") { ok = false; }
  if !resolv_address_valid("1::") { ok = false; }
  if !resolv_address_valid("1:2:3:4:5:6:7:8") { ok = false; }
  if !resolv_address_valid("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff") { ok = false; }
  if !resolv_address_valid("::ffff:1.2.3.4") { ok = false; }
  if !resolv_address_valid("1:2:3:4:5:6:1.2.3.4") { ok = false; }
  if resolv_address_valid("") { ok = false; }
  if resolv_address_valid("256.0.0.1") { ok = false; }
  if resolv_address_valid("01.2.3.4") { ok = false; }
  if resolv_address_valid("1.2.3") { ok = false; }
  if resolv_address_valid("1.2.3.4.5") { ok = false; }
  if resolv_address_valid("1.2.3.4/24") { ok = false; }
  if resolv_address_valid("1::2::3") { ok = false; }
  if resolv_address_valid("10000::") { ok = false; }
  if resolv_address_valid("::%1") { ok = false; }
  if resolv_address_valid(":1:2:3:4:5:6:7:8") { ok = false; }
  if resolv_address_valid("1:2:3:4:5:6:7:") { ok = false; }
  if resolv_address_valid("g::1") { ok = false; }
  if resolv_address_valid(":::") { ok = false; }
  if resolv_address_valid("1:2:3:4:5:6:7") { ok = false; }
  if resolv_address_valid("1:2:3:4:5:6:7:8:9") { ok = false; }
  if resolv_address_valid("1:2:3:4:5:6:1.2.3.4.5") { ok = false; }
  if resolv_address_valid("1.2.3.4::") { ok = false; }
  if resolv_address_valid("host") { ok = false; }
  if !opt_str_is(resolv_address_normalize("1.2.3.4"), "1.2.3.4") { ok = false; }
  if !opt_str_is(resolv_address_normalize("2001:DB8::1"), "2001:db8::1") { ok = false; }
  if !opt_str_none(resolv_address_normalize("1.2.3.4/24")) { ok = false; }
  if !opt_str_none(resolv_address_normalize("")) { ok = false; }
  return assert(ok, "public validators: documented accept/reject sets");
}

fn main() -> Int {
  io.println("=== xiom.resolv conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.resolv: all tests passed");
  } else {
    io.println("xiom.resolv: tests failed");
  }
  return failed;
}
