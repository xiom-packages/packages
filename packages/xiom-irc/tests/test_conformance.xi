// XIOM -- xiom.irc conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.irc module against its SPEC.md:
// parsing, prefix splitting, IRCv3 tags (escapes, valueless and empty
// values, duplicates), message building, numeric replies, error catalog and
// wire round-trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below (commands, params, tag names/values, error messages) is routed
// through streq instead of `==`.
//
// The test harness calls t1() ... t24() directly from main; Vec[fn] indexed
// dispatch is not used (it miscompiles on XIOM v0.61.3).

module irc_tests
use xiom.io; use xiom.test; use xiom.irc;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let got: Str = v[i];
  return streq(got, want);
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

fn ok_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok { return false; }
  return streq(r.value, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn ok_int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// True when parsing `text` fails with exactly the documented error.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = irc_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `raw` parses, renders byte-exactly as raw + CRLF, and the
// rendered line re-parses to the same command/params/trailing/tag counts.
fn round_trip(raw: Str) -> Bool {
  let r = irc_parse(raw);
  var ok = false;
  match r {
    Ok(m) => {
      let rendered: Str = irc_render(&m);
      ok = streq(rendered, raw + "\r\n");
      if ok {
        let r2 = irc_parse(rendered);
        match r2 {
          Ok(m2) => {
            let c1: Str = m.command;
            let c2: Str = m2.command;
            let t1: Str = m.trailing;
            let t2: Str = m2.trailing;
            if !streq(c1, c2) { ok = false; }
            if irc_param_count(&m2) != irc_param_count(&m) { ok = false; }
            if !streq(t1, t2) { ok = false; }
            if irc_tag_count(&m2) != irc_tag_count(&m) { ok = false; }
          },
          Err(_) => { ok = false; },
        }
      }
    },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn t1() -> TestResult {
  let r = irc_parse(":nick!user@host PRIVMSG #chan :Hello, world!");
  var ok = false;
  match r {
    Ok(m) => {
      ok = m.has_prefix;
      if !streq(m.prefix, "nick!user@host") { ok = false; }
      if !streq(m.nick, "nick") { ok = false; }
      if !streq(m.user, "user") { ok = false; }
      if !streq(m.host, "host") { ok = false; }
      if m.is_server_prefix { ok = false; }
      if !streq(m.command, "PRIVMSG") { ok = false; }
      if irc_param_count(&m) != 1 { ok = false; }
      if !streq(irc_param(&m, 0), "#chan") { ok = false; }
      if !m.has_trailing { ok = false; }
      if !streq(m.trailing, "Hello, world!") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple prefix/middle/trailing message");
}

fn t2() -> TestResult {
  let r1 = irc_parse("PING");
  var ok = false;
  match r1 {
    Ok(m) => {
      ok = !m.has_prefix;
      if !streq(m.command, "PING") { ok = false; }
      if irc_param_count(&m) != 0 { ok = false; }
      if m.has_trailing { ok = false; }
      if !streq(irc_render(&m), "PING\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = irc_parse("PING :token");
  match r2 {
    Ok(m2) => {
      if irc_param_count(&m2) != 0 { ok = false; }
      if !m2.has_trailing { ok = false; }
      if !streq(m2.trailing, "token") { ok = false; }
      if !streq(irc_render(&m2), "PING :token\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "command with and without a trailing token");
}

fn t3() -> TestResult {
  let r = irc_parse(":server 005 nick MODE=+i CASEMAPPING=ascii :are supported by this server");
  var ok = false;
  match r {
    Ok(m) => {
      ok = true;
      if !streq(m.command, "005") { ok = false; }
      if irc_param_count(&m) != 3 { ok = false; }
      if !streq(irc_param(&m, 0), "nick") { ok = false; }
      if !streq(irc_param(&m, 1), "MODE=+i") { ok = false; }
      if !streq(irc_param(&m, 2), "CASEMAPPING=ascii") { ok = false; }
      if !streq(m.trailing, "are supported by this server") { ok = false; }
      if !streq(irc_render(&m), ":server 005 nick MODE=+i CASEMAPPING=ascii :are supported by this server\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "numeric reply with three middle params");
}

fn t4() -> TestResult {
  let a = irc_parse("CMD a:b c");
  var ok = false;
  match a {
    Ok(m) => {
      ok = irc_param_count(&m) == 2;
      if !streq(irc_param(&m, 0), "a:b") { ok = false; }
      if !streq(irc_param(&m, 1), "c") { ok = false; }
      if m.has_trailing { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = irc_parse("CMD :trailing");
  match b {
    Ok(m2) => {
      if irc_param_count(&m2) != 0 { ok = false; }
      if !streq(m2.trailing, "trailing") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = irc_parse("CMD ::x");
  match c {
    Ok(m3) => {
      if !streq(m3.trailing, ":x") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let d = irc_parse("CMD :a b :c");
  match d {
    Ok(m4) => {
      if !streq(m4.trailing, "a b :c") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "colons in middle params and in trailing text");
}

fn t5() -> TestResult {
  let r = irc_parse("TOPIC #chan :");
  var ok = false;
  match r {
    Ok(m) => {
      ok = irc_param_count(&m) == 1;
      if !streq(irc_param(&m, 0), "#chan") { ok = false; }
      if !m.has_trailing { ok = false; }
      if !streq(m.trailing, "") { ok = false; }
      if !streq(irc_render(&m), "TOPIC #chan :\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "explicit empty trailing is preserved");
}

fn t6() -> TestResult {
  let a = irc_parse_prefix("nick!user@host");
  var ok = streq(a.raw, "nick!user@host");
  if !streq(a.nick, "nick") || !streq(a.user, "user") || !streq(a.host, "host") || a.is_server { ok = false; }
  let b = irc_parse_prefix("nick@host");
  if !streq(b.nick, "nick") || !streq(b.user, "") || !streq(b.host, "host") || b.is_server { ok = false; }
  let c = irc_parse_prefix("nick!user");
  if !streq(c.nick, "nick") || !streq(c.user, "user") || !streq(c.host, "") || c.is_server { ok = false; }
  let d = irc_parse_prefix("justanick");
  if !streq(d.nick, "justanick") || !streq(d.user, "") || !streq(d.host, "") || !d.is_server { ok = false; }
  let e = irc_parse_prefix(":nick!user@host");
  if !streq(e.raw, "nick!user@host") || !streq(e.nick, "nick") || !streq(e.host, "host") { ok = false; }
  let f = irc_parse_prefix("");
  if f.is_server || !streq(f.raw, "") || !streq(f.nick, "") { ok = false; }
  return assert(ok, "prefix parsing: nick/user/host split and ':' stripping");
}

fn t7() -> TestResult {
  let r = irc_parse(":irc.example.net NOTICE * :*** Looking up your hostname");
  var ok = false;
  match r {
    Ok(m) => {
      ok = m.has_prefix && m.is_server_prefix;
      if !streq(m.prefix, "irc.example.net") { ok = false; }
      if !streq(m.nick, "irc.example.net") { ok = false; }
      if !streq(m.user, "") { ok = false; }
      if !streq(m.host, "") { ok = false; }
      if !irc_command_is(&m, "notice") { ok = false; }
      if !streq(irc_param(&m, 0), "*") { ok = false; }
      if !streq(m.trailing, "*** Looking up your hostname") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "server-name prefix is flagged and split");
}

fn t8() -> TestResult {
  let raw = "@aaa=bbb;ccc;example.com/ddd=eee :nick!ident@host.com PRIVMSG me :Hello";
  let r = irc_parse(raw);
  var ok = false;
  match r {
    Ok(m) => {
      ok = irc_has_tags(&m) && irc_tag_count(&m) == 3;
      if !streq(irc_tag_name(&m, 0), "aaa") { ok = false; }
      if !streq(irc_tag_name(&m, 1), "ccc") { ok = false; }
      if !streq(irc_tag_name(&m, 2), "example.com/ddd") { ok = false; }
      if !irc_tag_has_value(&m, 0) { ok = false; }
      if irc_tag_has_value(&m, 1) { ok = false; }
      if !irc_tag_has_value(&m, 2) { ok = false; }
      if !streq(irc_tag_value(&m, 0), "bbb") { ok = false; }
      if !streq(irc_tag_value(&m, 1), "") { ok = false; }
      if !streq(irc_tag_value(&m, 2), "eee") { ok = false; }
      if !opt_str_is(irc_tag(&m, "aaa"), "bbb") { ok = false; }
      if !opt_str_is(irc_tag(&m, "ccc"), "") { ok = false; }
      if !opt_str_is(irc_tag(&m, "example.com/ddd"), "eee") { ok = false; }
      if !opt_str_none(irc_tag(&m, "AAA")) { ok = false; }
      if !opt_str_none(irc_tag(&m, "nope")) { ok = false; }
      if !streq(m.command, "PRIVMSG") { ok = false; }
      if !streq(irc_param(&m, 0), "me") { ok = false; }
      if !streq(m.trailing, "Hello") { ok = false; }
      if !streq(irc_render(&m), raw + "\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "IRCv3 example: three tags with full message fields");
}

fn t9() -> TestResult {
  let r = irc_parse("@k=a\\sb\\:c\\\\d\\re\\nf CMD");
  var ok = false;
  match r {
    Ok(m) => {
      ok = irc_tag_count(&m) == 1;
      if !opt_str_is(irc_tag(&m, "k"), "a b;c\\d\re\nf") { ok = false; }
      if !streq(irc_tag_value(&m, 0), "a b;c\\d\re\nf") { ok = false; }
      if !streq(irc_render(&m), "@k=a\\sb\\:c\\\\d\\re\\nf CMD\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = irc_parse("@k= CMD");
  match r2 {
    Ok(m2) => {
      if !irc_tag_has_value(&m2, 0) { ok = false; }
      if !streq(irc_tag_value(&m2, 0), "") { ok = false; }
      if !streq(irc_render(&m2), "@k= CMD\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "tag escapes decode and re-encode canonically");
}

fn t10() -> TestResult {
  let r = irc_parse("@k=\\bx\\ CMD");
  var ok = false;
  match r {
    Ok(m) => {
      ok = opt_str_is(irc_tag(&m, "k"), "bx");
      if !streq(irc_render(&m), "@k=bx CMD\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unknown escapes drop the backslash; a trailing backslash is dropped");
}

fn t11() -> TestResult {
  let r = irc_parse("@a=1;a=2;b=3 CMD");
  var ok = false;
  match r {
    Ok(m) => {
      ok = irc_tag_count(&m) == 3;
      if !streq(irc_tag_name(&m, 0), "a") { ok = false; }
      if !streq(irc_tag_name(&m, 1), "a") { ok = false; }
      if !opt_str_is(irc_tag(&m, "a"), "2") { ok = false; }
      if !opt_str_is(irc_tag(&m, "b"), "3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate tag keys keep the final value");
}

fn t12() -> TestResult {
  var ok = parse_err_is("@ CMD", "irc: empty tags");
  if !parse_err_is("@; CMD", "irc: empty tags") { ok = false; }
  let one = irc_parse("@a=1; CMD");
  match one {
    Ok(m) => {
      if irc_tag_count(&m) != 1 { ok = false; }
      if !streq(irc_tag_name(&m, 0), "a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let emptykey = irc_parse("@=v CMD");
  match emptykey {
    Ok(m2) => {
      if irc_tag_count(&m2) != 1 { ok = false; }
      if !streq(irc_tag_name(&m2, 0), "") { ok = false; }
      if !streq(irc_tag_value(&m2, 0), "v") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let lead = irc_parse("  @a=1 CMD");
  match lead {
    Ok(m3) => {
      if irc_tag_count(&m3) != 1 { ok = false; }
      if !streq(m3.command, "CMD") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty tag segments are skipped; empty keys are accepted verbatim");
}

fn t13() -> TestResult {
  var ok = parse_err_is("", "irc: empty message");
  if !parse_err_is("   ", "irc: empty message") { ok = false; }
  if !parse_err_is("\r\n", "irc: empty message") { ok = false; }
  if !parse_err_is(":nick", "irc: missing command") { ok = false; }
  if !parse_err_is(":nick ", "irc: missing command") { ok = false; }
  if !parse_err_is("@a=1", "irc: missing command") { ok = false; }
  if !parse_err_is("@a=1 ", "irc: missing command") { ok = false; }
  if !parse_err_is("@a=1 :nick", "irc: missing command") { ok = false; }
  return assert(ok, "empty messages and missing commands are deterministic errors");
}

fn t14() -> TestResult {
  var ok = parse_err_is(": CMD", "irc: empty prefix");
  if !parse_err_is(":", "irc: empty prefix") { ok = false; }
  return assert(ok, "an empty prefix is rejected");
}

fn t15() -> TestResult {
  let a = irc_parse("PING\r\n");
  var ok = false;
  match a {
    Ok(m) => { ok = irc_command_is(&m, "PING") && irc_param_count(&m) == 0 && !m.has_trailing; },
    Err(_) => { ok = false; },
  }
  let b = irc_parse("PING\n");
  match b {
    Ok(m2) => {
      if !streq(m2.command, "PING") { ok = false; }
      if !streq(irc_render(&m2), "PING\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = irc_parse("PING\r");
  match c {
    Ok(m3) => {
      if !streq(m3.command, "PING") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let d = irc_parse("PING\r\nJUNK COMMAND");
  match d {
    Ok(m4) => {
      if !streq(m4.command, "PING") { ok = false; }
      if m4.has_trailing { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e = irc_parse("PRIVMSG #c :hello\r\n");
  match e {
    Ok(m5) => {
      if !streq(m5.trailing, "hello") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF/LF/CR terminators and truncation at the first break");
}

fn t16() -> TestResult {
  var ps = Vec[Str].new();
  ps.push("#chan");
  let a = irc_build("PRIVMSG", ps, "Hello there", true);
  var ok = ok_str_is(a, "PRIVMSG #chan :Hello there\r\n");
  var none = Vec[Str].new();
  if !ok_str_is(irc_build("PING", none, "", false), "PING\r\n") { ok = false; }
  var none2 = Vec[Str].new();
  if !ok_str_is(irc_build("CMD", none2, "", true), "CMD :\r\n") { ok = false; }
  var two = Vec[Str].new();
  two.push("a");
  two.push("b");
  if !ok_str_is(irc_build("CMD", two, "", false), "CMD a b\r\n") { ok = false; }
  return assert(ok, "build emits params, trailing and CRLF");
}

fn t17() -> TestResult {
  var names = Vec[Str].new();
  names.push("aaa");
  names.push("ccc");
  var values = Vec[Str].new();
  values.push("bbb");
  values.push("");
  var ps = Vec[Str].new();
  ps.push("me");
  let built = irc_build_full(names, values, "nick!u@h", "PRIVMSG", ps, "Hello", true);
  var ok = ok_str_is(built, "@aaa=bbb;ccc :nick!u@h PRIVMSG me :Hello\r\n");
  let r = irc_parse("@aaa=bbb;ccc :nick!u@h PRIVMSG me :Hello\r\n");
  match r {
    Ok(m) => {
      if irc_tag_count(&m) != 2 { ok = false; }
      if !opt_str_is(irc_tag(&m, "aaa"), "bbb") { ok = false; }
      if !opt_str_is(irc_tag(&m, "ccc"), "") { ok = false; }
      if irc_tag_has_value(&m, 1) { ok = false; }
      if !streq(m.nick, "nick") { ok = false; }
      if !streq(m.user, "u") { ok = false; }
      if !streq(m.host, "h") { ok = false; }
      if !streq(irc_param(&m, 0), "me") { ok = false; }
      if !streq(m.trailing, "Hello") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "build_full tags/prefix round-trip through irc_parse");
}

fn t18() -> TestResult {
  var none = Vec[Str].new();
  let a = irc_build("", none, "", false);
  var ok = err_str_is(a, "irc: empty command");
  var none2 = Vec[Str].new();
  if !err_str_is(irc_build("PRIV MSG", none2, "", false), "irc: invalid command: PRIV MSG") { ok = false; }
  var ep = Vec[Str].new();
  ep.push("");
  if !err_str_is(irc_build("CMD", ep, "", false), "irc: empty parameter") { ok = false; }
  var sp = Vec[Str].new();
  sp.push("a b");
  if !err_str_is(irc_build("CMD", sp, "", false), "irc: invalid parameter: a b") { ok = false; }
  var cp = Vec[Str].new();
  cp.push(":x");
  if !err_str_is(irc_build("CMD", cp, "", false), "irc: invalid parameter: :x") { ok = false; }
  var none3 = Vec[Str].new();
  if !err_str_is(irc_build("CMD", none3, "bad\r\ntrail", true), "irc: trailing contains a line break") { ok = false; }
  var no_names = Vec[Str].new();
  var one_value = Vec[Str].new();
  one_value.push("v");
  var none4 = Vec[Str].new();
  if !err_str_is(irc_build_full(no_names, one_value, "", "CMD", none4, "", false), "irc: tag name/value count mismatch") { ok = false; }
  var bad_names = Vec[Str].new();
  bad_names.push("a b");
  var bad_values = Vec[Str].new();
  bad_values.push("v");
  var none5 = Vec[Str].new();
  if !err_str_is(irc_build_full(bad_names, bad_values, "", "CMD", none5, "", false), "irc: invalid tag name: a b") { ok = false; }
  var empty_names = Vec[Str].new();
  empty_names.push("");
  var empty_values = Vec[Str].new();
  empty_values.push("v");
  var none6 = Vec[Str].new();
  if !err_str_is(irc_build_full(empty_names, empty_values, "", "CMD", none6, "", false), "irc: empty tag name") { ok = false; }
  var no_names2 = Vec[Str].new();
  var no_values2 = Vec[Str].new();
  var none7 = Vec[Str].new();
  if !err_str_is(irc_build_full(no_names2, no_values2, "bad prefix", "CMD", none7, "", false), "irc: invalid prefix: bad prefix") { ok = false; }
  return assert(ok, "build validation error catalog");
}

fn t19() -> TestResult {
  var ps = Vec[Str].new();
  ps.push("nick");
  let a = irc_build_numeric("irc.example.net", 1, ps, "Welcome to the network", true);
  var ok = ok_str_is(a, ":irc.example.net 001 nick :Welcome to the network\r\n");
  var ps2 = Vec[Str].new();
  ps2.push("nick");
  if !ok_str_is(irc_build_numeric("", 433, ps2, "Nickname is already in use", true), "433 nick :Nickname is already in use\r\n") { ok = false; }
  var none = Vec[Str].new();
  if !ok_str_is(irc_build_numeric("s", 0, none, "", false), ":s 000\r\n") { ok = false; }
  var none2 = Vec[Str].new();
  if !err_str_is(irc_build_numeric("", 1000, none2, "", false), "irc: invalid numeric code: 1000") { ok = false; }
  var none3 = Vec[Str].new();
  if !err_str_is(irc_build_numeric("", -1, none3, "", false), "irc: invalid numeric code: -1") { ok = false; }
  let r = irc_parse(":irc.example.net 001 nick :Welcome");
  match r {
    Ok(m) => {
      if !irc_is_numeric(&m) { ok = false; }
      if !ok_int_is(irc_numeric_code(&m), 1) { ok = false; }
      if !streq(m.prefix, "irc.example.net") { ok = false; }
      if !streq(irc_param(&m, 0), "nick") { ok = false; }
      if !streq(m.trailing, "Welcome") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "numeric building and code parsing");
}

fn t20() -> TestResult {
  let a = irc_parse("001");
  var ok = false;
  match a {
    Ok(m) => {
      ok = irc_is_numeric(&m);
      if !ok_int_is(irc_numeric_code(&m), 1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = irc_parse(":s 007 nick :hi");
  match b {
    Ok(m2) => {
      if !ok_int_is(irc_numeric_code(&m2), 7) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = irc_parse("PING");
  match c {
    Ok(m3) => {
      if irc_is_numeric(&m3) { ok = false; }
      if !err_int_is(irc_numeric_code(&m3), "irc: not a numeric reply") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let d = irc_parse("12");
  match d {
    Ok(m4) => {
      if irc_is_numeric(&m4) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e = irc_parse("1234");
  match e {
    Ok(m5) => {
      if irc_is_numeric(&m5) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let f = irc_parse("12a");
  match f {
    Ok(m6) => {
      if irc_is_numeric(&m6) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "numeric detection and code parsing");
}

fn t21() -> TestResult {
  let r = irc_parse(":n!u@h pRiVmsg #c :hi");
  var ok = false;
  match r {
    Ok(m) => {
      ok = irc_command_is(&m, "privmsg");
      if !irc_command_is(&m, "PRIVMSG") { ok = false; }
      if !irc_command_is(&m, "pRiVmSg") { ok = false; }
      if irc_command_is(&m, "PRIVMSGX") { ok = false; }
      if irc_command_is(&m, "NOTICE") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !irc_eq_ci("Nick", "nick") { ok = false; }
  if !irc_eq_ci("", "") { ok = false; }
  if !irc_eq_ci("a1B", "A1b") { ok = false; }
  if irc_eq_ci("a", "ab") { ok = false; }
  if irc_eq_ci("abc", "abd") { ok = false; }
  if irc_eq_ci("[", "{") { ok = false; }
  return assert(ok, "ASCII case-insensitive command comparison");
}

fn t22() -> TestResult {
  let r = irc_parse("CMD a b c");
  var ok = false;
  match r {
    Ok(m) => {
      ok = irc_param_count(&m) == 3;
      if !streq(irc_param(&m, 0), "a") { ok = false; }
      if !streq(irc_param(&m, 1), "b") { ok = false; }
      if !streq(irc_param(&m, 2), "c") { ok = false; }
      if !streq(irc_param(&m, 3), "") { ok = false; }
      if !streq(irc_param(&m, -1), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let many = irc_parse("CMD p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13 p14 p15 :end");
  match many {
    Ok(m2) => {
      if irc_param_count(&m2) != 15 { ok = false; }
      if !streq(irc_param(&m2, 14), "p15") { ok = false; }
      if !streq(m2.trailing, "end") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parameter indexing and no 14-parameter limit");
}

fn t23() -> TestResult {
  var ok = round_trip("PING");
  if !round_trip(":n!u@h JOIN #chan") { ok = false; }
  if !round_trip("@a=1;b :n!u@h NOTICE * :hi there") { ok = false; }
  if !round_trip("CAP LS 302") { ok = false; }
  if !round_trip("@k=a\\sb\\:c\\\\d CMD #x :hello world") { ok = false; }
  return assert(ok, "parse/render round-trips are byte-exact");
}

fn t24() -> TestResult {
  let raw = "@x=a\\sb\\:c\\\\d\\re\\nf :n!u@h PRIVMSG #c :hello world";
  let r1 = irc_parse(raw);
  var ok = false;
  match r1 {
    Ok(m) => {
      ok = streq(irc_render(&m), raw + "\r\n");
      if ok {
        let r2 = irc_parse(irc_render(&m));
        match r2 {
          Ok(m2) => {
            if !opt_str_is(irc_tag(&m2, "x"), "a b;c\\d\re\nf") { ok = false; }
            if !streq(m2.command, "PRIVMSG") { ok = false; }
            if !streq(m2.nick, "n") { ok = false; }
            if !streq(m2.trailing, "hello world") { ok = false; }
          },
          Err(_) => { ok = false; },
        }
      }
    },
    Err(_) => { ok = false; },
  }
  let bare = irc_parse("@a;b= CMD");
  match bare {
    Ok(m3) => {
      if irc_tag_has_value(&m3, 0) { ok = false; }
      if !irc_tag_has_value(&m3, 1) { ok = false; }
      if !streq(irc_tag_value(&m3, 0), "") { ok = false; }
      if !streq(irc_render(&m3), "@a;b= CMD\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "escaped and value-less tag forms survive re-parse");
}

fn main() -> Int {
  io.println("=== xiom.irc conformance tests ===");
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
    io.println("xiom.irc: all tests passed");
  } else {
    io.println("xiom.irc: tests failed");
  }
  return failed;
}
