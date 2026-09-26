// XIOM -- xiom.passwd conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 8. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// No Vec[fn] dispatch and no `==` on Str values read from Vec[Str] elements
// (BUG 17: that lowers to a pointer comparison); every string comparison goes
// through compare.str_compare and every element read binds a typed local
// first. Control-byte inputs are built with mk_ctrl so the test source keeps
// no raw control bytes, and byte 0x00 is never used because a Str cannot
// carry a NUL (bytes 1..31 and DEL cover the same class).

module passwd_tests
use xiom.io; use xiom.test; use xiom.passwd;
use xiom.string;
use xiom.string.compare;

// String equality through the stdlib comparator (never `==` on Str).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when v[i] equals `want`.
fn str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let got: Str = v[i];
  return streq(got, want);
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

// True when the Option[Int] is Some with exactly `want`.
fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

// True when the Option[Int] is None.
fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// True when two Option[Str] values are equal (None == None).
fn opt_str_eq(a: Option[Str], b: Option[Str]) -> Bool {
  match a {
    Some(x) => {
      match b {
        Some(y) => { return streq(x, y); },
        None => { return false; },
      }
    },
    None => {
      match b {
        Some(_) => { return false; },
        None => { return true; },
      }
    },
  }
  return false;
}

// True when two Option[Int] values are equal (None == None).
fn opt_int_eq(a: Option[Int], b: Option[Int]) -> Bool {
  match a {
    Some(x) => {
      match b {
        Some(y) => { return x == y; },
        None => { return false; },
      }
    },
    None => {
      match b {
        Some(_) => { return false; },
        None => { return true; },
      }
    },
  }
  return false;
}

// True when passwd_parse(text) is Err with exactly `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = passwd_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// A Str containing `prefix`, one raw byte `c` and `suffix` (test inputs only;
// the parser must reject control bytes before they are ever emitted).
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

// True when both documents hold the same entries in the same order (all seven
// fields; line numbers are layout, not content).
fn same_entries(a: &Passwd, b: &Passwd) -> Bool {
  let na = passwd_entry_count(a);
  if na != passwd_entry_count(b) { return false; }
  var i = 0;
  while i < na {
    if !opt_str_eq(passwd_name(a, i), passwd_name(b, i)) { return false; }
    if !opt_str_eq(passwd_password(a, i), passwd_password(b, i)) { return false; }
    if !opt_int_eq(passwd_uid(a, i), passwd_uid(b, i)) { return false; }
    if !opt_int_eq(passwd_gid(a, i), passwd_gid(b, i)) { return false; }
    if !opt_str_eq(passwd_gecos(a, i), passwd_gecos(b, i)) { return false; }
    if !opt_str_eq(passwd_home(a, i), passwd_home(b, i)) { return false; }
    if !opt_str_eq(passwd_shell(a, i), passwd_shell(b, i)) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = passwd_parse("root:x:0:0:root:/root:/bin/bash\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 1;
      if !opt_str_is(passwd_name(&d, 0), "root") { ok = false; }
      if !opt_str_is(passwd_password(&d, 0), "x") { ok = false; }
      if !opt_int_is(passwd_uid(&d, 0), 0) { ok = false; }
      if !opt_int_is(passwd_gid(&d, 0), 0) { ok = false; }
      if !opt_str_is(passwd_gecos(&d, 0), "root") { ok = false; }
      if !opt_str_is(passwd_home(&d, 0), "/root") { ok = false; }
      if !opt_str_is(passwd_shell(&d, 0), "/bin/bash") { ok = false; }
      if passwd_line(&d, 0) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "single entry: seven fields and line number");
}

fn t2() -> TestResult {
  let r = passwd_parse("daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\r\nsync:*:4:65534:sync:/bin:/bin/sync");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 2;
      if !opt_str_is(passwd_name(&d, 0), "daemon") { ok = false; }
      if !opt_str_is(passwd_shell(&d, 0), "/usr/sbin/nologin") { ok = false; }
      if !opt_int_is(passwd_gid(&d, 0), 1) { ok = false; }
      if passwd_line(&d, 0) != 1 { ok = false; }
      if !opt_str_is(passwd_name(&d, 1), "sync") { ok = false; }
      if !opt_str_is(passwd_password(&d, 1), "*") { ok = false; }
      if !opt_int_is(passwd_uid(&d, 1), 4) { ok = false; }
      if !opt_int_is(passwd_gid(&d, 1), 65534) { ok = false; }
      if passwd_line(&d, 1) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multiple entries: CRLF and missing final newline");
}

fn t3() -> TestResult {
  let r = passwd_parse("# /etc/passwd: user database\n\n# another\nroot:x:0:0:root:/root:/bin/bash # not a comment\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 1;
      if !opt_str_is(passwd_name(&d, 0), "root") { ok = false; }
      if !opt_str_is(passwd_shell(&d, 0), "/bin/bash # not a comment") { ok = false; }
      if passwd_line(&d, 0) != 4 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e = passwd_parse("");
  match e {
    Ok(d2) => { if passwd_entry_count(&d2) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let c = passwd_parse("\n\n# only comments\n");
  match c {
    Ok(d3) => { if passwd_entry_count(&d3) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments and blank lines skipped; line numbering");
}

fn t4() -> TestResult {
  var ok = parse_err_is("root:x:0:0:root:/root\n", "passwd: wrong field count in line 1");
  if !parse_err_is("root:x:0:0:root:/root:/bin/bash:extra\n", "passwd: wrong field count in line 1") { ok = false; }
  if !parse_err_is("root\n", "passwd: wrong field count in line 1") { ok = false; }
  if !parse_err_is("# c\n\nroot:x:0:0:root:/root\n", "passwd: wrong field count in line 3") { ok = false; }
  let e = passwd_parse("\n\n");
  match e {
    Ok(d) => { if passwd_entry_count(&d) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "wrong field count: exact errors and line numbers");
}

fn t5() -> TestResult {
  let r = passwd_parse("a:x:1:1:g:/h:/s\n_svc:x:1:1:g:/h:/s\n_a-b_c9:x:1:1:g:/h:/s\naaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:x:1:1:g:/h:/s\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 4;
      if !opt_str_is(passwd_name(&d, 0), "a") { ok = false; }
      if !opt_str_is(passwd_name(&d, 1), "_svc") { ok = false; }
      if !opt_str_is(passwd_name(&d, 2), "_a-b_c9") { ok = false; }
      if !opt_str_is(passwd_name(&d, 3), "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is(":x:1:1:g:/h:/s\n", "passwd: bad name: ") { ok = false; }
  if !parse_err_is("Root:x:1:1:g:/h:/s\n", "passwd: bad name: Root") { ok = false; }
  if !parse_err_is("9x:x:1:1:g:/h:/s\n", "passwd: bad name: 9x") { ok = false; }
  if !parse_err_is("-x:x:1:1:g:/h:/s\n", "passwd: bad name: -x") { ok = false; }
  if !parse_err_is("a.b:x:1:1:g:/h:/s\n", "passwd: bad name: a.b") { ok = false; }
  if !parse_err_is("a b:x:1:1:g:/h:/s\n", "passwd: bad name: a b") { ok = false; }
  if !parse_err_is("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:x:1:1:g:/h:/s\n", "passwd: bad name: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") { ok = false; }
  return assert(ok, "name charset and 32-byte cap");
}

fn t6() -> TestResult {
  let r = passwd_parse("a:x:0:0::/:/bin/sh\nb:x:4294967295:4294967295::/:/bin/sh\nc:x:0007:0008::/:/bin/sh\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 3;
      if !opt_int_is(passwd_uid(&d, 0), 0) { ok = false; }
      if !opt_int_is(passwd_uid(&d, 1), 4294967295) { ok = false; }
      if !opt_int_is(passwd_gid(&d, 1), 4294967295) { ok = false; }
      if !opt_int_is(passwd_uid(&d, 2), 7) { ok = false; }
      if !opt_int_is(passwd_gid(&d, 2), 8) { ok = false; }
      if !streq(passwd_emit(&d), "a:x:0:0::/:/bin/sh\nb:x:4294967295:4294967295::/:/bin/sh\nc:x:7:8::/:/bin/sh\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is("a:x::1::/:/bin/sh\n", "passwd: bad uid: ") { ok = false; }
  if !parse_err_is("a:x:+1:1::/:/bin/sh\n", "passwd: bad uid: +1") { ok = false; }
  if !parse_err_is("a:x:-1:1::/:/bin/sh\n", "passwd: bad uid: -1") { ok = false; }
  if !parse_err_is("a:x:1a:1::/:/bin/sh\n", "passwd: bad uid: 1a") { ok = false; }
  if !parse_err_is("a:x:4294967296:1::/:/bin/sh\n", "passwd: bad uid: 4294967296") { ok = false; }
  if !parse_err_is("a:x:99999999999:1::/:/bin/sh\n", "passwd: bad uid: 99999999999") { ok = false; }
  if !parse_err_is("a:x: 1:1::/:/bin/sh\n", "passwd: bad uid:  1") { ok = false; }
  if !parse_err_is("a:x:1::g:/h:/s\n", "passwd: bad gid: ") { ok = false; }
  if !parse_err_is("a:x:1:4294967296:g:/h:/s\n", "passwd: bad gid: 4294967296") { ok = false; }
  if !parse_err_is("a:x:1:12x:g:/h:/s\n", "passwd: bad gid: 12x") { ok = false; }
  if !parse_err_is("a:x:1:+5:g:/h:/s\n", "passwd: bad gid: +5") { ok = false; }
  return assert(ok, "uid/gid digits, range and leading-zero normalization");
}

fn t7() -> TestResult {
  let r = passwd_parse("nobody:x:65534:65534::/nonexistent:/usr/sbin/nologin\nanon::1000:1000::/:/bin/sh\na:*:1:1:g::\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 3;
      if !opt_str_is(passwd_gecos(&d, 0), "") { ok = false; }
      if !opt_str_is(passwd_password(&d, 0), "x") { ok = false; }
      if !opt_str_is(passwd_password(&d, 1), "") { ok = false; }
      if !opt_str_is(passwd_gecos(&d, 1), "") { ok = false; }
      if !opt_str_is(passwd_home(&d, 1), "/") { ok = false; }
      if !opt_str_is(passwd_password(&d, 2), "*") { ok = false; }
      if !opt_str_is(passwd_home(&d, 2), "") { ok = false; }
      if !opt_str_is(passwd_shell(&d, 2), "") { ok = false; }
      if !streq(passwd_emit(&d), "nobody:x:65534:65534::/nonexistent:/usr/sbin/nologin\nanon::1000:1000::/:/bin/sh\na:*:1:1:g::\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty passwd, gecos, home and shell are real values");
}

fn t8() -> TestResult {
  let r = passwd_parse("a:x:1:1:g:/:/bin/sh\nb:x:1:1:g:/home/x o:/usr/sbin/nologin\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 2;
      if !opt_str_is(passwd_home(&d, 0), "/") { ok = false; }
      if !opt_str_is(passwd_home(&d, 1), "/home/x o") { ok = false; }
      if !opt_str_is(passwd_shell(&d, 1), "/usr/sbin/nologin") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is("a:x:1:1:g:home:/bin/sh\n", "passwd: bad home: home") { ok = false; }
  if !parse_err_is("a:x:1:1:g:./x:/bin/sh\n", "passwd: bad home: ./x") { ok = false; }
  if !parse_err_is("a:x:1:1:g:~/x:/bin/sh\n", "passwd: bad home: ~/x") { ok = false; }
  if !parse_err_is("a:x:1:1:g:x/y:/bin/sh\n", "passwd: bad home: x/y") { ok = false; }
  if !parse_err_is("a:x:1:1:g:..:/bin/sh\n", "passwd: bad home: ..") { ok = false; }
  if !parse_err_is("a:x:1:1:g:/h:sh\n", "passwd: bad shell: sh") { ok = false; }
  if !parse_err_is("a:x:1:1:g:/h:bin/sh\n", "passwd: bad shell: bin/sh") { ok = false; }
  if !parse_err_is("a:x:1:1:g:/h:./sh\n", "passwd: bad shell: ./sh") { ok = false; }
  return assert(ok, "home/shell must be empty or absolute");
}

fn t9() -> TestResult {
  var ok = parse_err_is(mk_ctrl("root:x:0:0:ro", 1, "ot:/root:/bin/sh\n"), "passwd: control byte in line 1");
  if !parse_err_is(mk_ctrl("a:x:1:1:g", 9, "ecos:/h:/s\n"), "passwd: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("a:x:1:1:g:/h", 127, ":/s\n"), "passwd: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("# ok", 1, "\n"), "passwd: control byte in line 1") { ok = false; }
  if !parse_err_is("a:x:1:1:g:/h:/s\n" + mk_ctrl("b:x:1:1:g:/h", 11, ":/s\n"), "passwd: control byte in line 2") { ok = false; }
  let r = passwd_parse("a:x:1:1::/:/s\r\nb:x:2:2::/:/s\n");
  match r {
    Ok(d) => { if passwd_entry_count(&d) != 2 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "control bytes rejected in fields and comments; CRLF ok");
}

fn t10() -> TestResult {
  let r = passwd_parse("a:x:1:1:g:/h:/s\nb:*:2:2:Gecos, with spaces and λ:/h:/s\nc:!:3:3::/h:/s\nd::4:4::/h:/s\ne:$6$salt$hash:5:5::/h:/s\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 5;
      if !opt_str_is(passwd_password(&d, 0), "x") { ok = false; }
      if !opt_str_is(passwd_password(&d, 1), "*") { ok = false; }
      if !opt_str_is(passwd_gecos(&d, 1), "Gecos, with spaces and λ") { ok = false; }
      if !opt_str_is(passwd_password(&d, 2), "!") { ok = false; }
      if !opt_str_is(passwd_gecos(&d, 2), "") { ok = false; }
      if !opt_str_is(passwd_password(&d, 3), "") { ok = false; }
      if !opt_str_is(passwd_password(&d, 4), "$6$salt$hash") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "passwd and gecos are opaque printable text");
}

fn t11() -> TestResult {
  let r = passwd_parse("dup:x:1000:1000::/home/first:/bin/bash\ndup:x:1001:1001::/home/second:/bin/sh\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 2;
      if passwd_name_index(&d, "dup") != 0 { ok = false; }
      if passwd_name_index(&d, "DUP") != -1 { ok = false; }
      if passwd_name_index(&d, "absent") != -1 { ok = false; }
      if !opt_str_is(passwd_home_for_name(&d, "dup"), "/home/first") { ok = false; }
      if !opt_str_is(passwd_shell_for_name(&d, "dup"), "/bin/bash") { ok = false; }
      if !opt_int_is(passwd_uid_for_name(&d, "dup"), 1000) { ok = false; }
      if !opt_str_is(passwd_name(&d, 1), "dup") { ok = false; }
      if !opt_int_is(passwd_uid(&d, 1), 1001) { ok = false; }
      if !opt_str_is(passwd_home(&d, 1), "/home/second") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate names preserved; first-match lookups");
}

fn t12() -> TestResult {
  let r = passwd_parse("a:x:1000:1000::/home/a:/bin/sh\nb:x:1000:1000::/home/b:/bin/bash\nc:x:1001:1001::/home/c:/bin/sh\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 3;
      if passwd_uid_count(&d, 1000) != 2 { ok = false; }
      if passwd_uid_count(&d, 1001) != 1 { ok = false; }
      if passwd_uid_count(&d, 999) != 0 { ok = false; }
      let names = passwd_names_for_uid(&d, 1000);
      if names.len() != 2 { ok = false; }
      if !str_at(&names, 0, "a") { ok = false; }
      if !str_at(&names, 1, "b") { ok = false; }
      if passwd_names_for_uid(&d, 999).len() != 0 { ok = false; }
      if !opt_str_is(passwd_name_for_uid(&d, 1000), "a") { ok = false; }
      if !opt_str_is(passwd_name_for_uid(&d, 1001), "c") { ok = false; }
      if !opt_str_none(passwd_name_for_uid(&d, 999)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate uids: count, name list and first name");
}

fn t13() -> TestResult {
  let r = passwd_parse("solo:x:7:8:g:/h:/s\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 1;
      if !opt_str_none(passwd_name(&d, -1)) { ok = false; }
      if !opt_str_none(passwd_name(&d, 1)) { ok = false; }
      if !opt_str_none(passwd_password(&d, 1)) { ok = false; }
      if !opt_int_none(passwd_uid(&d, 1)) { ok = false; }
      if !opt_int_none(passwd_gid(&d, -1)) { ok = false; }
      if !opt_str_none(passwd_gecos(&d, 9)) { ok = false; }
      if !opt_str_none(passwd_home(&d, 1)) { ok = false; }
      if !opt_str_none(passwd_shell(&d, 1)) { ok = false; }
      if passwd_line(&d, -1) != 0 { ok = false; }
      if passwd_line(&d, 1) != 0 { ok = false; }
      if passwd_name_index(&d, "solo") != 0 { ok = false; }
      if passwd_name_index(&d, "") != -1 { ok = false; }
      if !opt_str_none(passwd_home_for_name(&d, "absent")) { ok = false; }
      if !opt_str_none(passwd_shell_for_name(&d, "absent")) { ok = false; }
      if !opt_int_none(passwd_uid_for_name(&d, "absent")) { ok = false; }
      if passwd_uid_count(&d, 7) != 1 { ok = false; }
      if passwd_uid_count(&d, -1) != 0 { ok = false; }
      if !opt_str_is(passwd_name_for_uid(&d, 7), "solo") { ok = false; }
      if !opt_str_none(passwd_name_for_uid(&d, -1)) { ok = false; }
      if passwd_names_for_uid(&d, -1).len() != 0 { ok = false; }
      var names = passwd_names_for_uid(&d, 7);
      if names.len() != 1 { ok = false; }
      names.push("mutated");
      if passwd_names_for_uid(&d, 7).len() != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessor guards, absent lookups and fresh copies");
}

fn t14() -> TestResult {
  let r = passwd_parse("root:x:0:0::/root:/bin/sh\nsys:x:999:999::/:/sbin/nologin\npriv:x:1000:1000::/home/priv:/bin/sh\nnobody:x:65534:65534::/nonexistent:/usr/sbin/nologin\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 4;
      if passwd_system_user_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e = passwd_parse("");
  match e {
    Ok(d2) => { if passwd_system_user_count(&d2) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "system-user count uses the documented uid < 1000 predicate");
}

fn t15() -> TestResult {
  let r = passwd_parse("# header\r\nroot:x:0:0:root:/root:/bin/bash\r\n\r\ndaemon:x:0001:0001:daemon:/usr/sbin:/usr/sbin/nologin");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(passwd_emit(&d), "root:x:0:0:root:/root:/bin/bash\ndaemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\n");
    },
    Err(_) => { ok = false; },
  }
  let s = passwd_parse("a:x:1:1: g :/h o:/s\n");
  match s {
    Ok(d2) => {
      if !streq(passwd_emit(&d2), "a:x:1:1: g :/h o:/s\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e1 = passwd_parse("");
  match e1 {
    Ok(d3) => { if !streq(passwd_emit(&d3), "") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let e2 = passwd_parse("# only comments\n\n");
  match e2 {
    Ok(d4) => { if !streq(passwd_emit(&d4), "") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emit: single colons, LF, empty docs, spaces kept");
}

fn t16() -> TestResult {
  let text = "# passwd fixture\r\nroot:x:0:0:root:/root:/bin/bash\r\nwww-data:x:33:33::/var/www:/usr/sbin/nologin\r\nguest::1000:1000:Gecos field:/home/guest:\r\n";
  let canonical = "root:x:0:0:root:/root:/bin/bash\nwww-data:x:33:33::/var/www:/usr/sbin/nologin\nguest::1000:1000:Gecos field:/home/guest:\n";
  let r1 = passwd_parse(text);
  var ok = true;
  match r1 {
    Ok(d1) => {
      if !streq(passwd_emit(&d1), canonical) { ok = false; }
      let r2 = passwd_parse(canonical);
      match r2 {
        Ok(d2) => {
          if !same_entries(&d1, &d2) { ok = false; }
          if !streq(passwd_emit(&d2), canonical) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "round-trip: empty gecos and x passwd fixture");
}

fn t17() -> TestResult {
  let r = passwd_parse("jorg:x:1000:1000:Jörg Müller, Raum 12:/home/jörg:/bin/sh\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 1;
      if !opt_str_is(passwd_gecos(&d, 0), "Jörg Müller, Raum 12") { ok = false; }
      if !opt_str_is(passwd_home(&d, 0), "/home/jörg") { ok = false; }
      if !streq(passwd_emit(&d), "jorg:x:1000:1000:Jörg Müller, Raum 12:/home/jörg:/bin/sh\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "non-ASCII bytes pass through gecos and home");
}

fn t18() -> TestResult {
  var ok = parse_err_is("   \n", "passwd: wrong field count in line 1");
  if !parse_err_is(mk_ctrl("", 9, "\n"), "passwd: control byte in line 1") { ok = false; }
  if !parse_err_is(" # c\n", "passwd: wrong field count in line 1") { ok = false; }
  if !parse_err_is(":\n", "passwd: wrong field count in line 1") { ok = false; }
  let a = passwd_parse("#\n");
  match a {
    Ok(d) => { if passwd_entry_count(&d) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let b = passwd_parse("#");
  match b {
    Ok(d2) => { if passwd_entry_count(&d2) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let c = passwd_parse("\n");
  match c {
    Ok(d3) => { if passwd_entry_count(&d3) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "blank is empty only; comment needs column-1 #");
}

fn t19() -> TestResult {
  let r = passwd_parse("a:x:1:1:c#d:/h#x:/s#y\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = passwd_entry_count(&d) == 1;
      if !opt_str_is(passwd_gecos(&d, 0), "c#d") { ok = false; }
      if !opt_str_is(passwd_home(&d, 0), "/h#x") { ok = false; }
      if !opt_str_is(passwd_shell(&d, 0), "/s#y") { ok = false; }
      if !streq(passwd_emit(&d), "a:x:1:1:c#d:/h#x:/s#y\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "# is data anywhere but the first column");
}

fn t20() -> TestResult {
  var ok = parse_err_is(mk_ctrl("a:x:1:1:g:/h:/s:extra", 1, "\n"), "passwd: control byte in line 1");
  if !parse_err_is("a:x::1::/h:/s:extra\n", "passwd: wrong field count in line 1") { ok = false; }
  if !parse_err_is("Bad:x:1:1:g:/h:/s\na:x::1::/h:/s\n", "passwd: bad name: Bad") { ok = false; }
  return assert(ok, "error order: control, field count, then fields");
}

fn main() -> Int {
  io.println("=== xiom.passwd conformance tests ===");
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
    io.println("xiom.passwd: all tests passed");
  } else {
    io.println("xiom.passwd: tests failed");
  }
  return failed;
}
