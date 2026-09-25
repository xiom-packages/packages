// XIOM -- xiom.hostfile conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 7. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// No Vec[fn] dispatch and no `==` on Str values read from Vec[Str] elements
// (BUG 17: that lowers to a pointer comparison); every string comparison
// goes through compare.str_compare and every element read binds a typed
// local first.

module hostfile_tests
use xiom.io; use xiom.test; use xiom.hostfile;
use xiom.string;
use xiom.string.compare;

// String equality through the stdlib comparator (never `==` on Str).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when entry i's address equals `want`.
fn addr_at(d: &HostsFile, i: Int, want: Str) -> Bool {
  let o = hostfile_address(d, i);
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

// True when entry i's hostname j equals `want`.
fn host_at(d: &HostsFile, i: Int, j: Int, want: Str) -> Bool {
  let names = hostfile_hostnames(d, i);
  if j < 0 || j >= names.len() { return false; }
  let x: Str = names[j];
  return streq(x, want);
}

// True when entry i starts on line `want`.
fn line_at(d: &HostsFile, i: Int, want: Int) -> Bool {
  return hostfile_line(d, i) == want;
}

// True when hostname count of entry i equals `want`.
fn hosts_count(d: &HostsFile, i: Int, want: Int) -> Bool {
  return hostfile_hostname_count(d, i) == want;
}

// True when v[i] equals `want`.
fn int_at(v: &Vec[Int], i: Int, want: Int) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let x: Int = v[i];
  return x == want;
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

// True when hostfile_parse(text) is Err with exactly `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = hostfile_parse(text);
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

// True when entries i of x and j of y have equal addresses.
fn addr_eq(x: &HostsFile, i: Int, y: &HostsFile, j: Int) -> Bool {
  let o1 = hostfile_address(x, i);
  let o2 = hostfile_address(y, j);
  match o1 {
    Some(v1) => {
      match o2 {
        Some(v2) => { return streq(v1, v2); },
        None => { return false; },
      }
    },
    None => {
      match o2 {
        Some(_) => { return false; },
        None => { return true; },
      }
    },
  }
  return false;
}

// True when entries i of x and j of y have equal hostname lists.
fn hosts_eq(x: &HostsFile, i: Int, y: &HostsFile, j: Int) -> Bool {
  let hx = hostfile_hostnames(x, i);
  let hy = hostfile_hostnames(y, j);
  if hx.len() != hy.len() { return false; }
  var k = 0;
  while k < hx.len() {
    let u: Str = hx[k];
    let v: Str = hy[k];
    if !streq(u, v) { return false; }
    k = k + 1;
  }
  return true;
}

// True when both documents hold the same entries in the same order
// (addresses and hostnames; line numbers are layout, not content).
fn same_entries(a: &HostsFile, b: &HostsFile) -> Bool {
  let na = hostfile_entry_count(a);
  if na != hostfile_entry_count(b) { return false; }
  var i = 0;
  while i < na {
    if !addr_eq(a, i, b, i) { return false; }
    if !hosts_eq(a, i, b, i) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = hostfile_parse("127.0.0.1 localhost\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 1;
      if !addr_at(&d, 0, "127.0.0.1") { ok = false; }
      if !hosts_count(&d, 0, 1) { ok = false; }
      if !host_at(&d, 0, 0, "localhost") { ok = false; }
      if !line_at(&d, 0, 1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "single entry: address, hostname, line");
}

fn t2() -> TestResult {
  let r = hostfile_parse("10.0.0.5 alpha beta.example GAMMA\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 1;
      if !hosts_count(&d, 0, 3) { ok = false; }
      if !host_at(&d, 0, 0, "alpha") { ok = false; }
      if !host_at(&d, 0, 1, "beta.example") { ok = false; }
      if !host_at(&d, 0, 2, "gamma") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multiple hostnames: order kept, lowered");
}

fn t3() -> TestResult {
  let r = hostfile_parse("\n# comment\n127.0.0.1 localhost\n\n::1 localhost ip6-localhost\n10.0.0.9 srv\r\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 3;
      if !addr_at(&d, 0, "127.0.0.1") { ok = false; }
      if !line_at(&d, 0, 3) { ok = false; }
      if !addr_at(&d, 1, "::1") { ok = false; }
      if !hosts_count(&d, 1, 2) { ok = false; }
      if !line_at(&d, 1, 5) { ok = false; }
      if !addr_at(&d, 2, "10.0.0.9") { ok = false; }
      if !line_at(&d, 2, 6) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multiple entries: blank/comment lines skipped, CRLF ok");
}

fn t4() -> TestResult {
  let r = hostfile_parse("  10.0.0.1\thost1   # trailing note\n# full line\n5.6.7.8 h2#tight\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 2;
      if !addr_at(&d, 0, "10.0.0.1") { ok = false; }
      if !host_at(&d, 0, 0, "host1") { ok = false; }
      if !addr_at(&d, 1, "5.6.7.8") { ok = false; }
      if !hosts_count(&d, 1, 1) { ok = false; }
      if !host_at(&d, 1, 0, "h2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments cut at unquoted #, whitespace tolerated");
}

fn t5() -> TestResult {
  let r = hostfile_parse("0:0:0:0:0:0:0:1 a\n::1 b\n2001:0DB8:0000:0000:0000:0000:0000:0001 c\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 3;
      if !addr_at(&d, 0, "::1") { ok = false; }
      if !addr_at(&d, 1, "::1") { ok = false; }
      if !addr_at(&d, 2, "2001:db8::1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "IPv6 canonicalization: lowercase, zeros compressed");
}

fn t6() -> TestResult {
  let r = hostfile_parse("1:0:0:2:0:0:3:4 t1\n1:2:3:4:5:6:0:8 t2\n0:1:0:0:2:0:0:0 t3\n0:0:0:0:0:0:0:0 t4\n1:2:3:4:5:6:7:8 t5\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 5;
      if !addr_at(&d, 0, "1::2:0:0:3:4") { ok = false; }
      if !addr_at(&d, 1, "1:2:3:4:5:6:0:8") { ok = false; }
      if !addr_at(&d, 2, "0:1:0:0:2::") { ok = false; }
      if !addr_at(&d, 3, "::") { ok = false; }
      if !addr_at(&d, 4, "1:2:3:4:5:6:7:8") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "IPv6 compression: leftmost longest run, lone 0 kept");
}

fn t7() -> TestResult {
  let r = hostfile_parse("::ffff:192.168.1.1 m1\n0:0:0:0:0:ffff:192.168.1.1 m2\n1:2:3:4:5:6:1.2.3.4 m3\n::1.2.3.4 m4\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 4;
      if !addr_at(&d, 0, "::ffff:c0a8:101") { ok = false; }
      if !addr_at(&d, 1, "::ffff:c0a8:101") { ok = false; }
      if !addr_at(&d, 2, "1:2:3:4:5:6:102:304") { ok = false; }
      if !addr_at(&d, 3, "::102:304") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "IPv6 embedded IPv4 tail folds into hex groups");
}

fn t8() -> TestResult {
  var ok = parse_err_is("256.0.0.1 host", "hostfile: bad address: 256.0.0.1");
  if !parse_err_is("01.2.3.4 host", "hostfile: bad address: 01.2.3.4") { ok = false; }
  if !parse_err_is("1.2.3.04 host", "hostfile: bad address: 1.2.3.04") { ok = false; }
  if !parse_err_is("1.2.3 host", "hostfile: bad address: 1.2.3") { ok = false; }
  if !parse_err_is("1.2.3.4.5 host", "hostfile: bad address: 1.2.3.4.5") { ok = false; }
  if !parse_err_is("1.2.3.4/24 host", "hostfile: bad address: 1.2.3.4/24") { ok = false; }
  if !parse_err_is("host", "hostfile: bad address: host") { ok = false; }
  if !parse_err_is("1:2:3:4:5:6:7 host", "hostfile: bad address: 1:2:3:4:5:6:7") { ok = false; }
  if !parse_err_is("1:2:3:4:5:6:7:8:9 host", "hostfile: bad address: 1:2:3:4:5:6:7:8:9") { ok = false; }
  if !parse_err_is("1:2:3:4:5:6:7: host", "hostfile: bad address: 1:2:3:4:5:6:7:") { ok = false; }
  if !parse_err_is("1::2::3 host", "hostfile: bad address: 1::2::3") { ok = false; }
  if !parse_err_is("1:2:3:4:5:6:7:8:: host", "hostfile: bad address: 1:2:3:4:5:6:7:8::") { ok = false; }
  if !parse_err_is("10000:: host", "hostfile: bad address: 10000::") { ok = false; }
  if !parse_err_is("g::1 host", "hostfile: bad address: g::1") { ok = false; }
  if !parse_err_is("::: host", "hostfile: bad address: :::") { ok = false; }
  if !parse_err_is("::%eth0 host", "hostfile: bad address: ::%eth0") { ok = false; }
  if !parse_err_is("fe80::1%lo host", "hostfile: bad address: fe80::1%lo") { ok = false; }
  return assert(ok, "bad addresses rejected with exact errors");
}

fn t9() -> TestResult {
  var ok = parse_err_is("10.0.0.1 -bad", "hostfile: bad hostname: -bad");
  if !parse_err_is("10.0.0.1 bad-", "hostfile: bad hostname: bad-") { ok = false; }
  if !parse_err_is("10.0.0.1 a..b", "hostfile: bad hostname: a..b") { ok = false; }
  if !parse_err_is("10.0.0.1 .a", "hostfile: bad hostname: .a") { ok = false; }
  if !parse_err_is("10.0.0.1 a.", "hostfile: bad hostname: a.") { ok = false; }
  if !parse_err_is("10.0.0.1 under_score", "hostfile: bad hostname: under_score") { ok = false; }
  if !parse_err_is("10.0.0.1 a_b", "hostfile: bad hostname: a_b") { ok = false; }
  if !parse_err_is("10.0.0.1 ok?", "hostfile: bad hostname: ok?") { ok = false; }
  if !parse_err_is("10.0.0.1 a b!#c", "hostfile: bad hostname: b!") { ok = false; }
  return assert(ok, "bad hostnames rejected with exact errors");
}

fn t10() -> TestResult {
  var ok = parse_err_is("10.0.0.1", "hostfile: entry with no hostname: 10.0.0.1");
  if !parse_err_is("10.0.0.1 # note", "hostfile: entry with no hostname: 10.0.0.1") { ok = false; }
  if !parse_err_is("10.0.0.1\t", "hostfile: entry with no hostname: 10.0.0.1") { ok = false; }
  if !parse_err_is("10.0.0.1   \t  ", "hostfile: entry with no hostname: 10.0.0.1") { ok = false; }
  if !parse_err_is("256.0.0.1", "hostfile: bad address: 256.0.0.1") { ok = false; }
  return assert(ok, "address with no hostname is an exact error");
}

fn t11() -> TestResult {
  var ok = parse_err_is(mk_ctrl("10.0.0.1 ho", 1, "st"), "hostfile: control byte in line 1");
  if !parse_err_is(mk_ctrl("10.0.0.1 a", 127, ""), "hostfile: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("10.0.0.1 a", 13, " b"), "hostfile: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("# comment", 1, ""), "hostfile: control byte in line 1") { ok = false; }
  if !parse_err_is("10.0.0.1 a\n" + (mk_ctrl("10.0.0.2 b", 1, "")), "hostfile: control byte in line 2") { ok = false; }
  let r = hostfile_parse("10.0.0.1\thost\n" + (mk_ctrl("10.0.0.2 a", 13, "")) + "\n10.0.0.3 b\n");
  var crlf_ok = false;
  match r {
    Ok(d) => {
      crlf_ok = hostfile_entry_count(&d) == 3;
      if !addr_at(&d, 1, "10.0.0.2") { crlf_ok = false; }
    },
    Err(_) => { crlf_ok = false; },
  }
  if !crlf_ok { ok = false; }
  return assert(ok, "control bytes rejected, TAB and CRLF accepted");
}

fn t12() -> TestResult {
  let cap = repeat_str("a", 4095);
  let over = repeat_str("a", 4096);
  let r = hostfile_parse("#" + cap);
  var ok = false;
  match r {
    Ok(d) => { ok = hostfile_entry_count(&d) == 0; },
    Err(_) => { ok = false; },
  }
  if !parse_err_is("#" + over, "hostfile: line too long: 1") { ok = false; }
  if !parse_err_is("10.0.0.1 a\n#" + over, "hostfile: line too long: 2") { ok = false; }
  return assert(ok, "line cap: 4096 bytes ok, 4097 rejected");
}

fn t13() -> TestResult {
  let r = hostfile_parse("10.0.0.1 dup first\n10.0.0.2 other\n10.0.0.3 dup second\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_lookup_index(&d, "dup") == 0;
      if hostfile_lookup_index(&d, "DUP") != 0 { ok = false; }
      if hostfile_lookup_index(&d, "other") != 1 { ok = false; }
      if hostfile_lookup_index(&d, "missing") != -1 { ok = false; }
      if !opt_str_is(hostfile_lookup(&d, "dup"), "10.0.0.1") { ok = false; }
      if !opt_str_is(hostfile_lookup(&d, "OTHER"), "10.0.0.2") { ok = false; }
      if !opt_str_none(hostfile_lookup(&d, "missing")) { ok = false; }
      if !opt_str_none(hostfile_lookup(&d, "not a name")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "lookup: first match in document order, case-insensitive");
}

fn t14() -> TestResult {
  let r = hostfile_parse("10.0.0.1 a\n10.0.0.1 b\n10.0.0.2 c\n::1 v6a\n0:0:0:0:0:0:0:1 v6b\n");
  var ok = false;
  match r {
    Ok(d) => {
      let v4 = hostfile_entries_for_address(&d, "10.0.0.1");
      ok = v4.len() == 2;
      if !int_at(&v4, 0, 0) { ok = false; }
      if !int_at(&v4, 1, 1) { ok = false; }
      let v6a = hostfile_entries_for_address(&d, "0:0:0:0:0:0:0:1");
      if v6a.len() != 2 { ok = false; }
      if !int_at(&v6a, 0, 3) { ok = false; }
      if !int_at(&v6a, 1, 4) { ok = false; }
      let v6b = hostfile_entries_for_address(&d, "::1");
      if v6b.len() != 2 { ok = false; }
      if hostfile_entries_for_address(&d, "999.1.1.1").len() != 0 { ok = false; }
      if hostfile_entries_for_address(&d, "10.0.0.9").len() != 0 { ok = false; }
      if hostfile_entries_for_address(&d, "junk").len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "all entries for address: canonical query, in order");
}

fn t15() -> TestResult {
  var ok = false;
  let r = hostfile_parse("127.0.0.1   localhost    localhost.localdomain\n\n::1\tip6-localhost\n");
  match r {
    Ok(d) => {
      ok = streq(hostfile_emit(&d), "127.0.0.1 localhost localhost.localdomain\n::1 ip6-localhost\n");
    },
    Err(_) => { ok = false; },
  }
  let e = hostfile_parse("");
  match e {
    Ok(d2) => {
      if !streq(hostfile_emit(&d2), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = hostfile_parse("\n\n# only comments\n   \n");
  match c {
    Ok(d3) => {
      if hostfile_entry_count(&d3) != 0 { ok = false; }
      if !streq(hostfile_emit(&d3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit: single spaces, trailing newline, empty doc");
}

fn t16() -> TestResult {
  let text = "# header\r\n127.0.0.1 localhost   loopback # trailing\n\n10.0.0.2  A B\n";
  let r1 = hostfile_parse(text);
  var ok = false;
  match r1 {
    Ok(d1) => {
      let s1 = hostfile_emit(&d1);
      let r2 = hostfile_parse(s1);
      match r2 {
        Ok(d2) => {
          ok = same_entries(&d1, &d2);
          if hostfile_entry_count(&d1) != 2 { ok = false; }
          if !streq(s1, "127.0.0.1 localhost loopback\n10.0.0.2 a b\n") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "round-trip: parse(emit(parse(x))) keeps entries");
}

fn t17() -> TestResult {
  let text = "  127.0.0.1\tlocalhost\n\n::1  ip6-localhost\n";
  let r1 = hostfile_parse(text);
  var ok = false;
  match r1 {
    Ok(d1) => {
      let s1 = hostfile_emit(&d1);
      let r2 = hostfile_parse(s1);
      match r2 {
        Ok(d2) => {
          let s2 = hostfile_emit(&d2);
          ok = streq(s1, s2);
          if !streq(s2, "127.0.0.1 localhost\n::1 ip6-localhost\n") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit is a fixed point on the canonical form");
}

fn t18() -> TestResult {
  let r = hostfile_parse("\t 10.0.0.1 \t first \t second \t\n10.0.0.1    a     b   c\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 2;
      if !hosts_count(&d, 0, 2) { ok = false; }
      if !host_at(&d, 0, 0, "first") { ok = false; }
      if !host_at(&d, 0, 1, "second") { ok = false; }
      if !hosts_count(&d, 1, 3) { ok = false; }
      if !host_at(&d, 1, 2, "c") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "leading/trailing whitespace and runs of spaces/tabs");
}

fn t19() -> TestResult {
  let r = hostfile_parse("0.0.0.0 z\n255.255.255.255 z\n1.2.3.0 z\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 3;
      if !addr_at(&d, 0, "0.0.0.0") { ok = false; }
      if !addr_at(&d, 1, "255.255.255.255") { ok = false; }
      if !addr_at(&d, 2, "1.2.3.0") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "IPv4 boundaries: 0.0.0.0 and 255.255.255.255 accepted");
}

fn t20() -> TestResult {
  let r = hostfile_parse(":: z\n1:: z\n::1 z\n1:2:3:4:5:6:7:8 z\nffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff z\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 5;
      if !addr_at(&d, 0, "::") { ok = false; }
      if !addr_at(&d, 1, "1::") { ok = false; }
      if !addr_at(&d, 2, "::1") { ok = false; }
      if !addr_at(&d, 3, "1:2:3:4:5:6:7:8") { ok = false; }
      if !addr_at(&d, 4, "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "IPv6 boundaries: ::, 1::, ::1, full and all-f forms");
}

fn t21() -> TestResult {
  let r1 = hostfile_parse("10.0.0.1 a");
  var ok = false;
  match r1 {
    Ok(d) => { ok = hostfile_entry_count(&d) == 1; },
    Err(_) => { ok = false; },
  }
  let r2 = hostfile_parse("10.0.0.1 a\r\n10.0.0.2 b\r\n");
  match r2 {
    Ok(d) => {
      if hostfile_entry_count(&d) != 2 { ok = false; }
      if !addr_at(&d, 1, "10.0.0.2") { ok = false; }
      if !line_at(&d, 1, 2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = hostfile_parse("10.0.0.1 a\r");
  match r3 {
    Ok(d) => {
      if hostfile_entry_count(&d) != 1 { ok = false; }
      if !addr_at(&d, 0, "10.0.0.1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "missing final newline and CRLF line endings");
}

fn t22() -> TestResult {
  var ok = hostfile_address_valid("1.2.3.4");
  if !hostfile_address_valid("0.0.0.0") { ok = false; }
  if !hostfile_address_valid("255.255.255.255") { ok = false; }
  if !hostfile_address_valid("::1") { ok = false; }
  if !hostfile_address_valid("::") { ok = false; }
  if !hostfile_address_valid("::ffff:1.2.3.4") { ok = false; }
  if !hostfile_address_valid("1:2:3:4:5:6:7:8") { ok = false; }
  if hostfile_address_valid("256.0.0.1") { ok = false; }
  if hostfile_address_valid("01.2.3.4") { ok = false; }
  if hostfile_address_valid("1.2.3") { ok = false; }
  if hostfile_address_valid("") { ok = false; }
  if hostfile_address_valid("1.2.3.4/24") { ok = false; }
  if hostfile_address_valid("1::2::3") { ok = false; }
  if hostfile_address_valid("10000::") { ok = false; }
  if hostfile_address_valid("::%1") { ok = false; }
  if hostfile_address_valid(":1:2:3:4:5:6:7:8") { ok = false; }
  if hostfile_address_valid("1:2:3:4:5:6:7:") { ok = false; }
  if hostfile_address_valid("localhost") { ok = false; }
  if !hostfile_hostname_valid("localhost") { ok = false; }
  if !hostfile_hostname_valid("a") { ok = false; }
  if !hostfile_hostname_valid("a-b.example") { ok = false; }
  if !hostfile_hostname_valid("123") { ok = false; }
  if hostfile_hostname_valid("") { ok = false; }
  if hostfile_hostname_valid("-a") { ok = false; }
  if hostfile_hostname_valid("a-") { ok = false; }
  if hostfile_hostname_valid("a..b") { ok = false; }
  if hostfile_hostname_valid(".a") { ok = false; }
  if hostfile_hostname_valid("a.") { ok = false; }
  if hostfile_hostname_valid("under_score") { ok = false; }
  if hostfile_hostname_valid("a b") { ok = false; }
  return assert(ok, "public validators: documented accept/reject sets");
}

fn t23() -> TestResult {
  let label63 = repeat_str("a", 63);
  let label64 = repeat_str("a", 64);
  let name253 = repeat_str("a", 63) + "." + repeat_str("b", 63) + "." + repeat_str("c", 63) + "." + repeat_str("d", 61);
  let name254 = repeat_str("a", 63) + "." + repeat_str("b", 63) + "." + repeat_str("c", 63) + "." + repeat_str("d", 62);
  var ok = hostfile_hostname_valid(label63);
  if hostfile_hostname_valid(label64) { ok = false; }
  if name253.len() != 253 { ok = false; }
  if !hostfile_hostname_valid(name253) { ok = false; }
  if name254.len() != 254 { ok = false; }
  if hostfile_hostname_valid(name254) { ok = false; }
  if !parse_err_is("10.0.0.1 " + name254, "hostfile: bad hostname: " + name254) { ok = false; }
  let r = hostfile_parse("10.0.0.1 " + name253 + "\n");
  match r {
    Ok(d) => {
      if hostfile_entry_count(&d) != 1 { ok = false; }
      if !host_at(&d, 0, 0, name253) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "hostname limits: label 63 ok / 64 bad, name 253 ok / 254 bad");
}

fn t24() -> TestResult {
  let r = hostfile_parse("10.0.0.1 a b\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = hostfile_entry_count(&d) == 1;
      var names = hostfile_hostnames(&d, 0);
      if names.len() != 2 { ok = false; }
      names.push("mutated");
      let again = hostfile_hostnames(&d, 0);
      if again.len() != 2 { ok = false; }
      if !opt_str_none(hostfile_address(&d, -1)) { ok = false; }
      if !opt_str_none(hostfile_address(&d, 1)) { ok = false; }
      if hostfile_line(&d, 5) != 0 { ok = false; }
      if hostfile_hostname_count(&d, -1) != 0 { ok = false; }
      if hostfile_hostnames(&d, 7).len() != 0 { ok = false; }
      if hostfile_lookup_index(&d, "nope") != -1 { ok = false; }
      if !opt_str_none(hostfile_lookup(&d, "nope")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessor guards and copy semantics");
}

fn main() -> Int {
  io.println("=== xiom.hostfile conformance tests ===");
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
    io.println("xiom.hostfile: all tests passed");
  } else {
    io.println("xiom.hostfile: tests failed");
  }
  return failed;
}
