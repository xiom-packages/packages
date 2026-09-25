// XIOM -- xiom.ldif conformance tests (22 checks)
// Greenfield package: prove the pure-XIOM xiom.ldif module against its
// documented record grammar, folding rules, base64 subset and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: one-entry and multi-entry documents, blank-line record
// separators, folded attributes (plain and base64), all three value forms
// (plain / base64 / URL) with kind and binary accessors, comments everywhere,
// CRLF input, empty and comment-only input, the full error catalog (missing
// dn, attribute before dn, duplicate dn, line without colon, malformed
// attribute name, bad base64, control bytes, changetype, continuation without
// previous line), case-insensitive dn and name lookup, first-value-by-name,
// canonical emit layout including 76-character base64 wrapping, exact emit
// text, emit/parse round trip with idempotence, and out-of-range accessors.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq/str_at/opt_str_is instead of `==`.

module ldif_tests
use xiom.io; use xiom.test; use xiom.ldif;
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

// True when the byte vector holds exactly the bytes of `want`.
fn bytes_are(v: &Vec[UInt8], want: Str) -> Bool {
  if v.len() != want.len() { return false; }
  var i = 0;
  while i < v.len() {
    let b: UInt8 = v[i];
    if ((b as Int) & 0xFF) != ((string.byte_at(want, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the byte vector is exactly {0x00, 0x01}. A NUL byte cannot be
// written as a Str literal (the compiler truncates the literal at it), so the
// expectation is built from the numeric values.
fn bytes_are_nul_one(v: &Vec[UInt8]) -> Bool {
  if v.len() != 2 { return false; }
  let b0: UInt8 = v[0];
  let b1: UInt8 = v[1];
  if ((b0 as Int) & 0xFF) != 0 { return false; }
  return ((b1 as Int) & 0xFF) == 1;
}

// `n` copies of `s` (used to build exact wrap fixtures).
fn rep(s: Str, n: Int) -> Str {
  var out = "";
  var i = 0;
  while i < n {
    out = out + s;
    i = i + 1;
  }
  return out;
}

// True when `text` fails to parse with a message starting with `prefix`.
fn parse_err_prefix(text: Str, prefix: Str) -> Bool {
  let r = ldif_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = ldif_parse("dn: cn=Ada,dc=example,dc=org\ncn: Ada\nsn: Lovelace\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_count(&l) == 1;
      if ldif_entry_attr_count(&l, 0) != 3 { ok = false; }
      if !streq(ldif_dn(&l, 0), "cn=Ada,dc=example,dc=org") { ok = false; }
      if !streq(ldif_attr_name(&l, 0, 0), "dn") { ok = false; }
      if !streq(ldif_attr_name(&l, 0, 1), "cn") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 1), "Ada") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 2), "Lovelace") { ok = false; }
      if ldif_attr_kind(&l, 0, 1) != LDIF_KIND_PLAIN { ok = false; }
      if ldif_attr_is_url(&l, 0, 1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "one entry: dn first, plain attributes in order");
}

fn t2() -> TestResult {
  let r = ldif_parse("dn: cn=a\ncn: A\n\ndn: cn=b\ncn: B\n\n\ndn: cn=c\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_count(&l) == 3;
      if ldif_entry_attr_count(&l, 0) != 2 { ok = false; }
      if ldif_entry_attr_count(&l, 1) != 2 { ok = false; }
      if ldif_entry_attr_count(&l, 2) != 1 { ok = false; }
      if !streq(ldif_dn(&l, 1), "cn=b") { ok = false; }
      if !streq(ldif_dn(&l, 2), "cn=c") { ok = false; }
      if !opt_str_is(ldif_first_value(&l, 0, "cn"), "A") { ok = false; }
      if !opt_str_is(ldif_first_value(&l, 1, "cn"), "B") { ok = false; }
      if !opt_str_none(ldif_first_value(&l, 2, "cn")) { ok = false; }
      if !opt_str_none(ldif_first_value(&l, 2, "sn")) { ok = false; }
      if !opt_str_is(ldif_first_value(&l, 0, "dn"), "cn=a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "blank lines separate entries; runs of blanks collapse");
}

fn t3() -> TestResult {
  let r = ldif_parse("dn: cn=a\ncn: Ada\n  Lovelace\nsn: Lovelace\ndescription: line one\n  line two\n  line three\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_count(&l) == 1;
      if ldif_entry_attr_count(&l, 0) != 4 { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 1), "Ada Lovelace") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 2), "Lovelace") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 3), "line one line two line three") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a line starting with one space folds into the previous value");
}

fn t4() -> TestResult {
  let r = ldif_parse("dn:: Y249YQ==\ncn: A\ndescription:: aGVsbG8=\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_count(&l) == 1;
      if !streq(ldif_dn(&l, 0), "cn=a") { ok = false; }
      if ldif_attr_kind(&l, 0, 0) != LDIF_KIND_BASE64 { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 2), "hello") { ok = false; }
      if !bytes_are(ldif_attr_bytes(&l, 0, 2), "hello") { ok = false; }
      if !streq(ldif_kind_label(ldif_attr_kind(&l, 0, 2)), "base64") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "base64 values decode in place (dn included); kind and bytes agree");
}

fn t5() -> TestResult {
  let r = ldif_parse("dn: cn=a\nnote:: YQ==\nflag:: YWI=\nlong:: aGVs\n bG8=\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_attr_count(&l, 0) == 4;
      if !streq(ldif_attr_value(&l, 0, 1), "a") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 2), "ab") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 3), "hello") { ok = false; }
      if ldif_attr_kind(&l, 0, 1) != LDIF_KIND_BASE64 { ok = false; }
      if ldif_attr_kind(&l, 0, 3) != LDIF_KIND_BASE64 { ok = false; }
      if !bytes_are(ldif_attr_bytes(&l, 0, 1), "a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "both padding shapes decode; base64 payloads may be folded");
}

fn t6() -> TestResult {
  let r = ldif_parse("dn: cn=a\nseeAlso:< https://example.org/a?b=1#f\nhome:< ldap://host:389/dc=x\nnote: <not-a-url>\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_attr_count(&l, 0) == 4;
      if !streq(ldif_attr_value(&l, 0, 1), "https://example.org/a?b=1#f") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 2), "ldap://host:389/dc=x") { ok = false; }
      if !ldif_attr_is_url(&l, 0, 1) { ok = false; }
      if !ldif_attr_is_url(&l, 0, 2) { ok = false; }
      if ldif_attr_kind(&l, 0, 1) != LDIF_KIND_URL { ok = false; }
      if !streq(ldif_kind_label(ldif_attr_kind(&l, 0, 1)), "url") { ok = false; }
      if ldif_attr_is_url(&l, 0, 3) { ok = false; }
      if ldif_attr_kind(&l, 0, 3) != LDIF_KIND_PLAIN { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 3), "<not-a-url>") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "URL form is a raw token with a predicate; a leading < stays plain");
}

fn t7() -> TestResult {
  let r = ldif_parse("# top comment\n\ndn: cn=a\n# inside\ncn: A\n# between\n  continued\n\ndn: cn=b\n#\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_count(&l) == 2;
      if ldif_entry_attr_count(&l, 0) != 2 { ok = false; }
      if ldif_entry_attr_count(&l, 1) != 1 { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 1), "A continued") { ok = false; }
      if !streq(ldif_dn(&l, 1), "cn=b") { ok = false; }
      if !opt_str_none(ldif_first_value(&l, 0, "top")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments are skipped; a fold survives a comment between its lines");
}

fn t8() -> TestResult {
  let r = ldif_parse("dn: cn=a\r\ncn: A\r\ndescription:: aGVsbG8=\r\n\r\ndn: cn=b\r\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_count(&l) == 2;
      if !streq(ldif_dn(&l, 0), "cn=a") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 1), "A") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 2), "hello") { ok = false; }
      if !streq(ldif_dn(&l, 1), "cn=b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF input parses identically to LF");
}

fn t9() -> TestResult {
  let r = ldif_parse("");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_count(&l) == 0;
      if !streq(ldif_emit(&l), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = ldif_parse("   \n\t\n# just a comment\n\n# indented? no, this starts with #\n");
  match r2 {
    Ok(l2) => {
      if ldif_entry_count(&l2) != 0 { ok = false; }
      if !streq(ldif_emit(&l2), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and blank/comment-only input parse to zero entries");
}

fn t10() -> TestResult {
  var ok = parse_err_prefix("cn: Ada\nsn: Lovelace\n", "ldif: missing dn");
  if !parse_err_prefix("cn: Ada\n", "ldif: missing dn") { ok = false; }
  return assert(ok, "an entry without dn is Err");
}

fn t11() -> TestResult {
  var ok = parse_err_prefix("cn: Ada\ndn: cn=Ada\n", "ldif: attribute before dn");
  if !parse_err_prefix("sn: x\ncn: y\nDN: cn=a\n", "ldif: attribute before dn") { ok = false; }
  return assert(ok, "dn must be the first attribute of its entry");
}

fn t12() -> TestResult {
  var ok = parse_err_prefix("dn: cn=a\ndn: cn=b\n", "ldif: duplicate dn");
  if !parse_err_prefix("dn: cn=a\nDN: cn=a\n", "ldif: duplicate dn") { ok = false; }
  return assert(ok, "a repeated dn (case-insensitive) is rejected");
}

fn t13() -> TestResult {
  var ok = parse_err_prefix("dn: cn=a\nno colon here\n", "ldif: line without colon");
  if !parse_err_prefix("justtext", "ldif: line without colon") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nsecond line\n", "ldif: line without colon") { ok = false; }
  return assert(ok, "a non-blank line without ':' is Err");
}

fn t14() -> TestResult {
  var ok = parse_err_prefix("dn: cn=a\nbad name: x\n", "ldif: malformed attribute name");
  if !parse_err_prefix("dn: cn=a\n1abc: x\n", "ldif: malformed attribute name") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nbad;: x\n", "ldif: malformed attribute name") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nbad;;b: x\n", "ldif: malformed attribute name") { ok = false; }
  if !parse_err_prefix("dn: cn=a\n: x\n", "ldif: malformed attribute name") { ok = false; }
  let r = ldif_parse("dn: cn=a\nok-name;lang-en: x\n");
  match r {
    Ok(l) => {
      if !streq(ldif_attr_name(&l, 0, 1), "ok-name;lang-en") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "attribute descriptions are validated; options are allowed");
}

fn t15() -> TestResult {
  var ok = parse_err_prefix("dn: cn=a\nx:: aGVsbG8\n", "ldif: bad base64");
  if !parse_err_prefix("dn: cn=a\nx:: aGVsbG8==\n", "ldif: bad base64") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nx:: aGVsbG*o\n", "ldif: bad base64") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nx:: =\n", "ldif: bad base64") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nx:: aGVs bG8=\n", "ldif: bad base64") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nx::\n", "ldif: bad base64") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nx:: AAAA=\n", "ldif: bad base64") { ok = false; }
  if !parse_err_prefix("dn: cn=a\nx:: A===\n", "ldif: bad base64") { ok = false; }
  return assert(ok, "strict base64 rejects length, alphabet and padding violations");
}

fn t16() -> TestResult {
  var ok = parse_err_prefix("dn: cn=a\nnote: x\x01y\n", "ldif: control byte 0x01");
  if !parse_err_prefix("dn: cn=a\nnote: x\x0by\n", "ldif: control byte 0x0b") { ok = false; }
  if !parse_err_prefix("dn: cn=a\rx\n", "ldif: control byte 0x0d") { ok = false; }
  let r = ldif_parse("dn: cn=a\nnote: x\ty\n");
  match r {
    Ok(l) => {
      if !streq(ldif_attr_value(&l, 0, 1), "x\ty") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "C0 control bytes are rejected; TAB and CRLF are allowed");
}

fn t17() -> TestResult {
  var ok = parse_err_prefix("dn: cn=a\nchangetype: modify\n", "ldif: changetype records are not supported");
  if !parse_err_prefix("dn: cn=a\nCHANGETYPE: add\n", "ldif: changetype records are not supported") { ok = false; }
  return assert(ok, "change records are rejected (non-goal, documented)");
}

fn t18() -> TestResult {
  var ok = parse_err_prefix(" x\n", "ldif: continuation without previous line");
  if !parse_err_prefix("dn: cn=a\n\n cont\n", "ldif: continuation without previous line") { ok = false; }
  let r = ldif_parse("dn: cn=a\ncn: A\n \n\ndn: cn=b\n");
  match r {
    Ok(l) => {
      if ldif_entry_count(&l) != 2 { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 1), "A") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a fold with no previous line is Err; whitespace-only lines are blank");
}

fn t19() -> TestResult {
  let doc = "# comment\ndn: cn=Ada,dc=x\ncn: Ada\ncn: Ada Lovelace\n  (folded)\ndescription:: aGVsbG8gd29ybGQ=\nbin:: AAE=\nseeAlso:< https://example.org/x\nempty:\nspaced:   trailing  \n\ndn: cn=Bob\nsn: B\n";
  let r1 = ldif_parse(doc);
  var ok = false;
  match r1 {
    Ok(l1) => {
      ok = ldif_entry_count(&l1) == 2;
      if ldif_entry_attr_count(&l1, 0) != 8 { ok = false; }
      if !opt_str_is(ldif_first_value(&l1, 0, "cn"), "Ada") { ok = false; }
      if !streq(ldif_attr_value(&l1, 0, 2), "Ada Lovelace (folded)") { ok = false; }
      if !streq(ldif_attr_value(&l1, 0, 3), "hello world") { ok = false; }
      if !bytes_are_nul_one(ldif_attr_bytes(&l1, 0, 4)) { ok = false; }
      if ldif_attr_value(&l1, 0, 4).len() != 0 { ok = false; }
      if !ldif_attr_is_url(&l1, 0, 5) { ok = false; }
      if !streq(ldif_attr_value(&l1, 0, 6), "") { ok = false; }
      if !streq(ldif_attr_value(&l1, 0, 7), "trailing  ") { ok = false; }
      if !streq(ldif_attr_value(&l1, 1, 1), "B") { ok = false; }
      let text = ldif_emit(&l1);
      if string.str_contains(text, "\r") { ok = false; }
      if string.str_ends_with(text, "\n") { ok = false; }
      let r2 = ldif_parse(text);
      match r2 {
        Ok(l2) => {
          if ldif_entry_count(&l2) != 2 { ok = false; }
          if ldif_entry_attr_count(&l2, 0) != 8 { ok = false; }
          if !streq(ldif_attr_value(&l2, 0, 2), "Ada Lovelace (folded)") { ok = false; }
          if !streq(ldif_attr_value(&l2, 0, 3), "hello world") { ok = false; }
          if !bytes_are_nul_one(ldif_attr_bytes(&l2, 0, 4)) { ok = false; }
          if !streq(ldif_attr_value(&l2, 0, 7), "trailing  ") { ok = false; }
          if !streq(ldif_emit(&l2), text) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse preserves entries, values and kinds");
}

fn t20() -> TestResult {
  let doc = "dn: cn=x\na:: " + rep("YWFh", 20) + "\nb:: " + rep("YWFh", 19) + "\nc:: YQ==\n";
  let r = ldif_parse(doc);
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_attr_count(&l, 0) == 4;
      let want = "dn: cn=x\na:: " + rep("YWFh", 19) + "\n YWFh\nb:: " + rep("YWFh", 19) + "\nc:: YQ==";
      if !streq(ldif_emit(&l), want) { ok = false; }
      let r2 = ldif_parse(ldif_emit(&l));
      match r2 {
        Ok(l2) => {
          if !streq(ldif_attr_value(&l2, 0, 1), rep("a", 60)) { ok = false; }
          if !streq(ldif_attr_value(&l2, 0, 2), rep("a", 57)) { ok = false; }
          if !streq(ldif_attr_value(&l2, 0, 3), "a") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit wraps base64 at 76 characters with a leading-space continuation");
}

fn t21() -> TestResult {
  let r = ldif_parse("DN: cn=a\nCN: Ada\ncn: Ada2\n\ndn: cn=b\nsn: B\n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_count(&l) == 2;
      if !streq(ldif_dn(&l, 0), "cn=a") { ok = false; }
      if !streq(ldif_attr_name(&l, 0, 0), "DN") { ok = false; }
      if !streq(ldif_attr_name(&l, 0, 1), "CN") { ok = false; }
      if !opt_str_is(ldif_first_value(&l, 0, "cn"), "Ada") { ok = false; }
      if !opt_str_is(ldif_first_value(&l, 0, "CN"), "Ada") { ok = false; }
      if !opt_str_none(ldif_first_value(&l, 0, "sn")) { ok = false; }
      if !opt_str_none(ldif_first_value(&l, 1, "cn")) { ok = false; }
      if !opt_str_is(ldif_first_value(&l, 1, "sN"), "B") { ok = false; }
      if !opt_str_none(ldif_first_value(&l, 9, "cn")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "dn and first-value lookup are ASCII case-insensitive");
}

fn t22() -> TestResult {
  let r = ldif_parse("dn: cn=a\nempty:\nblank: \t\ntrail: x  \n");
  var ok = false;
  match r {
    Ok(l) => {
      ok = ldif_entry_attr_count(&l, 0) == 4;
      if !streq(ldif_attr_value(&l, 0, 1), "") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 2), "\t") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 3), "x  ") { ok = false; }
      if !streq(ldif_attr_name(&l, 5, 0), "") { ok = false; }
      if !streq(ldif_attr_value(&l, 0, 9), "") { ok = false; }
      if !streq(ldif_dn(&l, 9), "") { ok = false; }
      if ldif_entry_attr_count(&l, 9) != 0 { ok = false; }
      if ldif_attr_kind(&l, 9, 0) != LDIF_KIND_PLAIN { ok = false; }
      if ldif_attr_is_url(&l, 9, 9) { ok = false; }
      if !opt_str_none(ldif_first_value(&l, 9, "x")) { ok = false; }
      if ldif_attr_bytes(&l, 9, 9).len() != 0 { ok = false; }
      if !streq(ldif_kind_label(LDIF_KIND_PLAIN), "plain") { ok = false; }
      if !streq(ldif_kind_label(LDIF_KIND_BASE64), "base64") { ok = false; }
      if !streq(ldif_kind_label(LDIF_KIND_URL), "url") { ok = false; }
      if !streq(ldif_kind_label(42), "unknown") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty/TAB values survive; out-of-range accessors are total");
}

fn main() -> Int {
  io.println("=== xiom.ldif conformance tests ===");
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
    io.println("xiom.ldif: all tests passed");
  } else {
    io.println("xiom.ldif: tests failed");
  }
  return failed;
}
