// XIOM -- xiom.osrelease conformance tests (20 checks)
// Greenfield package: prove the pure-XIOM xiom.osrelease module against its
// documented os-release (systemd spec) grammar, quoting rules, accessors and
// error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: the Fedora example document, all three value forms, '#' as data,
// the four double-quote escapes, empty values, duplicate keys (first/last),
// comments and blanks, CRLF, control bytes, key validation, unterminated
// quotes, invalid escapes, text after quotes, whitespace in unquoted values,
// lookups, by-index access, ID/ID_LIKE/VERSION_ID conveniences, the canonical
// emitter, emit -> parse round trips, empty documents and UTF-8 values.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq/str_at/opt_str_is instead of `==`.

module osrelease_tests
use xiom.io; use xiom.test; use xiom.osrelease;
use xiom.string;
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

fn opt_same(a: Option[Str], b: Option[Str]) -> Bool {
  var ra = "";
  var rb = "";
  var na = false;
  var nb = false;
  match a {
    Some(x) => { ra = x; na = true; },
    None => { na = false; },
  }
  match b {
    Some(y) => { rb = y; nb = true; },
    None => { nb = false; },
  }
  if na != nb { return false; }
  if !na { return true; }
  return streq(ra, rb);
}

// Entry-by-entry comparison of two files (order, keys and decoded values).
fn rel_same(a: &OsRelease, b: &OsRelease) -> Bool {
  if osrelease_len(a) != osrelease_len(b) { return false; }
  var i = 0;
  while i < osrelease_len(a) {
    let ka: Option[Str] = osrelease_key_at(a, i);
    let kb: Option[Str] = osrelease_key_at(b, i);
    let va: Option[Str] = osrelease_value_at(a, i);
    let vb: Option[Str] = osrelease_value_at(b, i);
    if !opt_same(ka, kb) { return false; }
    if !opt_same(va, vb) { return false; }
    i = i + 1;
  }
  return true;
}

// The exact error message for `text`, or "" when it parses.
fn parse_err_msg(text: Str) -> Str {
  let r = osrelease_parse(text);
  match r {
    Ok(_) => { return ""; },
    Err(e) => { return e; },
  }
  return "";
}

fn new_rel() -> OsRelease {
  return OsRelease{ keys: Vec[Str].new(); values: Vec[Str].new(); };
}

// The Fedora Workstation 32 example from the os-release(5) man page.
fn fedora_doc() -> Str {
  var s = "NAME=Fedora\n";
  s = s + "VERSION=\"32 (Workstation Edition)\"\n";
  s = s + "ID=fedora\n";
  s = s + "VERSION_ID=32\n";
  s = s + "PRETTY_NAME=\"Fedora 32 (Workstation Edition)\"\n";
  s = s + "ANSI_COLOR=\"0;38;2;60;110;180\"\n";
  s = s + "LOGO=fedora-logo-icon\n";
  s = s + "CPE_NAME=\"cpe:/o:fedoraproject:fedora:32\"\n";
  s = s + "HOME_URL=\"https://fedoraproject.org/\"\n";
  s = s + "DOCUMENTATION_URL=\"https://docs.fedoraproject.org/en-US/fedora/f32/system-administrators-guide/\"\n";
  s = s + "SUPPORT_URL=\"https://fedoraproject.org/wiki/Communicating_and_getting_help\"\n";
  s = s + "BUG_REPORT_URL=\"https://bugzilla.redhat.com/\"\n";
  s = s + "REDHAT_BUGZILLA_PRODUCT=\"Fedora\"\n";
  s = s + "REDHAT_BUGZILLA_PRODUCT_VERSION=32\n";
  s = s + "REDHAT_SUPPORT_PRODUCT=\"Fedora\"\n";
  s = s + "REDHAT_SUPPORT_PRODUCT_VERSION=32\n";
  s = s + "PRIVACY_POLICY_URL=\"https://fedoraproject.org/wiki/Legal:PrivacyPolicy\"\n";
  s = s + "VARIANT=\"Workstation Edition\"\n";
  s = s + "VARIANT_ID=workstation\n";
  return s;
}

fn t1() -> TestResult {
  let r = osrelease_parse(fedora_doc());
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 19;
      if !opt_str_is(osrelease_key_at(&x, 0), "NAME") { ok = false; }
      if !opt_str_is(osrelease_value_at(&x, 0), "Fedora") { ok = false; }
      if !opt_str_is(osrelease_value_at(&x, 1), "32 (Workstation Edition)") { ok = false; }
      if !opt_str_is(osrelease_value_at(&x, 6), "fedora-logo-icon") { ok = false; }
      if !opt_str_is(osrelease_value_at(&x, 8), "https://fedoraproject.org/") { ok = false; }
      if !opt_str_is(osrelease_value_at(&x, 18), "workstation") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "ID"), "fedora") { ok = false; }
      if !opt_str_is(osrelease_last(&x, "VERSION_ID"), "32") { ok = false; }
      if !osrelease_has(&x, "PRETTY_NAME") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse the Fedora Workstation example");
}

fn t2() -> TestResult {
  let r = osrelease_parse("A=bare\nB='single quoted # hash'\nC=\"double quoted # hash\"\nD=data#hash\nE='say \"hi\"'\nF=\nG=ab\"cd\nH=ab'cd");
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 8;
      if !opt_str_is(osrelease_first(&x, "A"), "bare") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "B"), "single quoted # hash") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "C"), "double quoted # hash") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "D"), "data#hash") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "E"), "say \"hi\"") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "F"), "") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "G"), "ab\"cd") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "H"), "ab'cd") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bare, single-quoted, double-quoted and # as data");
}

fn t3() -> TestResult {
  let r = osrelease_parse("A=\"a\\\"b\\\\c\\$d\\`e\"");
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 1;
      if !opt_str_is(osrelease_first(&x, "A"), "a\"b\\c$d`e") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "double-quoted values decode the four escapes");
}

fn t4() -> TestResult {
  let r = osrelease_parse("EMPTY=\nDQ=\"\"\nSQ=''\nLAST=x");
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 4;
      if !opt_str_is(osrelease_first(&x, "EMPTY"), "") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "DQ"), "") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "SQ"), "") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "LAST"), "x") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty values: KEY=, KEY=\"\" and KEY=''");
}

fn t5() -> TestResult {
  let r = osrelease_parse("ID=first\nNAME=one\nID=second\nID=third");
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 4;
      if !opt_str_is(osrelease_key_at(&x, 0), "ID") { ok = false; }
      if !opt_str_is(osrelease_key_at(&x, 2), "ID") { ok = false; }
      if !opt_str_is(osrelease_key_at(&x, 3), "ID") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "ID"), "first") { ok = false; }
      if !opt_str_is(osrelease_last(&x, "ID"), "third") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "NAME"), "one") { ok = false; }
      if !opt_str_is(osrelease_last(&x, "NAME"), "one") { ok = false; }
      if !opt_str_is(osrelease_id(&x), "third") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate keys are preserved in order with first/last accessors");
}

fn t6() -> TestResult {
  let r = osrelease_parse("# top\n\nID=x\n   \n# mid=1\n#\nOTHER=y\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 2;
      if !opt_str_is(osrelease_first(&x, "ID"), "x") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "OTHER"), "y") { ok = false; }
      if osrelease_has(&x, "top") { ok = false; }
      if osrelease_has(&x, "mid") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = osrelease_parse("#comment=1\nID=y");
  match r2 {
    Ok(y) => {
      if osrelease_len(&y) != 1 { ok = false; }
      if !opt_str_is(osrelease_first(&y, "ID"), "y") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !streq(parse_err_msg("  # x\n"), "osrelease: invalid key in line:   # x") { ok = false; }
  return assert(ok, "comments start at byte 0; blank and spaces-only lines are skipped");
}

fn t7() -> TestResult {
  let r = osrelease_parse("NAME=x\r\nID=y\r\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 2;
      if !opt_str_is(osrelease_first(&x, "NAME"), "x") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "ID"), "y") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = osrelease_parse("ID=z\r");
  match r2 {
    Ok(z) => {
      if !opt_str_is(osrelease_first(&z, "ID"), "z") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !streq(parse_err_msg("ID=x\ry"), "osrelease: control byte in line: ID=x\ry") { ok = false; }
  return assert(ok, "CRLF input strips one trailing CR; a lone CR is a control byte");
}

fn t8() -> TestResult {
  var ok = streq(parse_err_msg("ID=a\tb"), "osrelease: control byte in line: ID=a\tb");
  if !streq(parse_err_msg("ID=a\u{0001}b"), "osrelease: control byte in line: ID=a\u{0001}b") { ok = false; }
  if !streq(parse_err_msg("ID=a\u{007F}b"), "osrelease: control byte in line: ID=a\u{007F}b") { ok = false; }
  if !streq(parse_err_msg("ID=\"a\tb\""), "osrelease: control byte in line: ID=\"a\tb\"") { ok = false; }
  return assert(ok, "control bytes (tab, C0, DEL) are rejected, quotes included");
}

fn t9() -> TestResult {
  var ok = streq(parse_err_msg("1BAD=x"), "osrelease: invalid key in line: 1BAD=x");
  if !streq(parse_err_msg("BAD-KEY=x"), "osrelease: invalid key in line: BAD-KEY=x") { ok = false; }
  if !streq(parse_err_msg("NAME foo"), "osrelease: invalid key in line: NAME foo") { ok = false; }
  if !streq(parse_err_msg("NOEQ"), "osrelease: missing '=' in line: NOEQ") { ok = false; }
  if !streq(parse_err_msg("=x"), "osrelease: invalid key in line: =x") { ok = false; }
  let r = osrelease_parse("Id=x\n_X=1\nX_1=2\nLONG_KEY_42=v");
  match r {
    Ok(x) => {
      if osrelease_len(&x) != 4 { ok = false; }
      if !opt_str_is(osrelease_first(&x, "Id"), "x") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "_X"), "1") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "X_1"), "2") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "LONG_KEY_42"), "v") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "key grammar: letter/underscore start, then letters/digits/underscore");
}

fn t10() -> TestResult {
  var ok = streq(parse_err_msg("A=\"abc"), "osrelease: unterminated double quote in line: A=\"abc");
  if !streq(parse_err_msg("B='abc"), "osrelease: unterminated single quote in line: B='abc") { ok = false; }
  if !streq(parse_err_msg("C=\"abc\\"), "osrelease: unterminated double quote in line: C=\"abc\\") { ok = false; }
  return assert(ok, "unterminated quotes are Err, a trailing backslash included");
}

fn t11() -> TestResult {
  var ok = streq(parse_err_msg("A=\"x\\qy\""), "osrelease: invalid escape in line: A=\"x\\qy\"");
  if !streq(parse_err_msg("A=\"x\\ny\""), "osrelease: invalid escape in line: A=\"x\\ny\"") { ok = false; }
  if !streq(parse_err_msg("A=\"x\\0y\""), "osrelease: invalid escape in line: A=\"x\\0y\"") { ok = false; }
  return assert(ok, "escapes outside \\\" \\\\ \\$ and backtick are Err, \\n included");
}

fn t12() -> TestResult {
  var ok = streq(parse_err_msg("A=\"x\"junk"), "osrelease: unexpected text after quoted value in line: A=\"x\"junk");
  if !streq(parse_err_msg("B='x' y"), "osrelease: unexpected text after quoted value in line: B='x' y") { ok = false; }
  if !streq(parse_err_msg("C=\"x\" # c"), "osrelease: unexpected text after quoted value in line: C=\"x\" # c") { ok = false; }
  if !streq(parse_err_msg("D=x y"), "osrelease: whitespace in unquoted value in line: D=x y") { ok = false; }
  if !streq(parse_err_msg("E=  "), "osrelease: whitespace in unquoted value in line: E=  ") { ok = false; }
  if !streq(parse_err_msg("F= x"), "osrelease: whitespace in unquoted value in line: F= x") { ok = false; }
  return assert(ok, "text after a closing quote and unquoted whitespace are Err");
}

fn t13() -> TestResult {
  let r = osrelease_parse("ID=a\nNAME=n\nID=b\nOTHER=o\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = opt_str_is(osrelease_first(&x, "ID"), "a");
      if !opt_str_is(osrelease_last(&x, "ID"), "b") { ok = false; }
      if !opt_str_is(osrelease_first(&x, "NAME"), "n") { ok = false; }
      if !opt_str_is(osrelease_last(&x, "NAME"), "n") { ok = false; }
      if !osrelease_has(&x, "ID") { ok = false; }
      if !osrelease_has(&x, "OTHER") { ok = false; }
      if osrelease_has(&x, "id") { ok = false; }
      if osrelease_has(&x, "missing") { ok = false; }
      if !opt_str_none(osrelease_first(&x, "missing")) { ok = false; }
      if !opt_str_none(osrelease_last(&x, "missing")) { ok = false; }
      if !opt_str_none(osrelease_first(&x, "ID_LIKE")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "first/last/has are byte-exact, case-sensitive and None when absent");
}

fn t14() -> TestResult {
  let r = osrelease_parse("A=1\nB=2");
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 2;
      if !opt_str_is(osrelease_key_at(&x, 0), "A") { ok = false; }
      if !opt_str_is(osrelease_key_at(&x, 1), "B") { ok = false; }
      if !opt_str_is(osrelease_value_at(&x, 0), "1") { ok = false; }
      if !opt_str_is(osrelease_value_at(&x, 1), "2") { ok = false; }
      if !opt_str_none(osrelease_key_at(&x, -1)) { ok = false; }
      if !opt_str_none(osrelease_key_at(&x, 2)) { ok = false; }
      if !opt_str_none(osrelease_value_at(&x, -1)) { ok = false; }
      if !opt_str_none(osrelease_value_at(&x, 2)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = osrelease_parse("");
  match r2 {
    Ok(z) => {
      if osrelease_len(&z) != 0 { ok = false; }
      if !opt_str_none(osrelease_key_at(&z, 0)) { ok = false; }
      if !streq(osrelease_emit(&z), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "key/value by index; out-of-range yields None");
}

fn t15() -> TestResult {
  let r = osrelease_parse("NAME=n\nID=fedora\nID_LIKE=\"rhel centos\"\nVERSION_ID=40\nID=rhel\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = opt_str_is(osrelease_id(&x), "rhel");
      if !opt_str_is(osrelease_id_like(&x), "rhel centos") { ok = false; }
      if !opt_str_is(osrelease_version_id(&x), "40") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = osrelease_parse("NAME=n");
  match r2 {
    Ok(y) => {
      if !opt_str_none(osrelease_id(&y)) { ok = false; }
      if !opt_str_none(osrelease_id_like(&y)) { ok = false; }
      if !opt_str_none(osrelease_version_id(&y)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ID/ID_LIKE/VERSION_ID conveniences read the last entry");
}

fn t16() -> TestResult {
  var e = new_rel();
  e.keys.push("BUILD"); e.values.push("2026-09-25");
  e.keys.push("ID"); e.values.push("fedora");
  e.keys.push("EMPTY"); e.values.push("");
  e.keys.push("VER"); e.values.push("40.1");
  e.keys.push("URL"); e.values.push("https://fedoraproject.org/");
  e.keys.push("CPE"); e.values.push("cpe:/o:fedoraproject:fedora:40");
  let got = osrelease_emit(&e);
  let want = "BUILD=2026-09-25\nID=fedora\nEMPTY=\nVER=40.1\nURL=https://fedoraproject.org/\nCPE=cpe:/o:fedoraproject:fedora:40";
  var ok = streq(got, want);
  let r = osrelease_parse("ID=\"fedora\"\nNAME='Ex OS'\nNAME2=plain");
  match r {
    Ok(x) => {
      let canon = osrelease_emit(&x);
      if !streq(canon, "ID=fedora\nNAME=\"Ex OS\"\nNAME2=plain") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emitter writes bare URL-ish values and canonicalizes quotes");
}

fn t17() -> TestResult {
  var e = new_rel();
  e.keys.push("A"); e.values.push("a b");
  e.keys.push("B"); e.values.push("a\"b");
  e.keys.push("C"); e.values.push("a\\b");
  e.keys.push("D"); e.values.push("a$b");
  e.keys.push("E"); e.values.push("a`b");
  e.keys.push("F"); e.values.push("a'b");
  e.keys.push("G"); e.values.push("café");
  e.keys.push("H"); e.values.push("#x");
  e.keys.push("I"); e.values.push("a=b");
  e.keys.push("J"); e.values.push("x;y");
  e.keys.push("K"); e.values.push("~x^y+z");
  let got = osrelease_emit(&e);
  let want = "A=\"a b\"\nB=\"a\\\"b\"\nC=\"a\\\\b\"\nD=\"a\\$b\"\nE=\"a\\`b\"\nF=\"a'b\"\nG=\"café\"\nH=\"#x\"\nI=\"a=b\"\nJ=\"x;y\"\nK=\"~x^y+z\"";
  var ok = streq(got, want);
  return assert(ok, "emitter double-quotes and escapes everything outside the bare alphabet");
}

fn t18() -> TestResult {
  let r1 = osrelease_parse(fedora_doc());
  var ok = false;
  match r1 {
    Ok(x1) => {
      ok = true;
      let emitted = osrelease_emit(&x1);
      if !string.str_contains(emitted, "PRETTY_NAME=\"Fedora 32 (Workstation Edition)\"") { ok = false; }
      if !string.str_contains(emitted, "VERSION_ID=32") { ok = false; }
      let r2 = osrelease_parse(emitted);
      match r2 {
        Ok(x2) => {
          if !rel_same(&x1, &x2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let wild = "SINGLE='literal \\ backslash and \"double\"'\nESCAPES=\"a\\\"b\\\\c\\$d\\`e\"\nHOME_X=\"https://example.org/?a=1&b=2\"\nEMPTY=\nUTF8=\"café 日本語\"\n";
  let r3 = osrelease_parse(wild);
  match r3 {
    Ok(w1) => {
      if !opt_str_is(osrelease_first(&w1, "SINGLE"), "literal \\ backslash and \"double\"") { ok = false; }
      if !opt_str_is(osrelease_first(&w1, "ESCAPES"), "a\"b\\c$d`e") { ok = false; }
      if !opt_str_is(osrelease_first(&w1, "HOME_X"), "https://example.org/?a=1&b=2") { ok = false; }
      if !opt_str_is(osrelease_first(&w1, "UTF8"), "café 日本語") { ok = false; }
      let r4 = osrelease_parse(osrelease_emit(&w1));
      match r4 {
        Ok(w2) => {
          if !rel_same(&w1, &w2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit then parse round-trips every entry");
}

fn t19() -> TestResult {
  let r = osrelease_parse("");
  var ok = false;
  match r {
    Ok(x) => {
      ok = osrelease_len(&x) == 0;
      if !streq(osrelease_emit(&x), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = osrelease_parse("# only\n\n   \n");
  match r2 {
    Ok(y) => {
      if osrelease_len(&y) != 0 { ok = false; }
      if !streq(osrelease_emit(&y), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = osrelease_parse("\n\n");
  match r3 {
    Ok(z) => {
      if osrelease_len(&z) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and comment-only documents parse to zero entries");
}

fn t20() -> TestResult {
  let r = osrelease_parse("NAME=Ünïcödé\nPRETTY_NAME=\"Ubuntu 24.04 LTS 日本語\"\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = opt_str_is(osrelease_first(&x, "NAME"), "Ünïcödé");
      if !opt_str_is(osrelease_first(&x, "PRETTY_NAME"), "Ubuntu 24.04 LTS 日本語") { ok = false; }
      let got = osrelease_emit(&x);
      let want = "NAME=\"Ünïcödé\"\nPRETTY_NAME=\"Ubuntu 24.04 LTS 日本語\"";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "UTF-8 values survive parse, emit and canonical quoting");
}

fn main() -> Int {
  io.println("=== xiom.osrelease conformance tests ===");
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
    io.println("xiom.osrelease: all tests passed");
  } else {
    io.println("xiom.osrelease: tests failed");
  }
  return failed;
}
