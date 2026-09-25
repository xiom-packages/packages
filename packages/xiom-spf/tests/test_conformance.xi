// XIOM -- xiom.spf conformance tests (26 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Greenfield package: prove the pure-XIOM xiom.spf module against its
// documented RFC 7208 syntax subset, flat term model, error catalog and
// canonical emitter.
//
// Coverage: bare and single-term records; the full mechanism catalog; the
// four qualifiers and the "+" default; ip4/ip6 and a/mx CIDR forms; macro
// pass-through and the spf_macro_valid predicate; redirect/exp and unknown
// modifiers with case-insensitive lookup; canonical emit (single spaces,
// lowercase mechanism names, omitted "+", verbatim values); round-trip and
// emit idempotence; the whole error catalog (version, unknown mechanism,
// bad mechanism syntax, bad CIDR, empty term, duplicate modifier, bad
// modifier, bad macro, control bytes); separator handling; bounded
// accessors; normalization equivalences; term order.
//
// All Str equality goes through compare.str_compare; element values are
// bound through the accessors, never through `==` on a Vec[Str] element.

module spf_tests
use xiom.io; use xiom.test; use xiom.spf;
use xiom.string.compare;

// String equality through the stdlib comparator (never `==` on Str).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Parse a known-good record; an unexpected failure yields spf_new() (zero
// terms), so a bug shows up as a failed assertion rather than a crash.
fn p(text: Str) -> Spf {
  let r = spf_parse(text);
  match r {
    Ok(d) => { return d; },
    Err(_) => { return spf_new(); },
  }
  return spf_new();
}

// True when term i has exactly the kind `want`.
fn k_is(r: &Spf, i: Int, want: Str) -> Bool {
  return streq(spf_term_kind(r, i), want);
}

// True when term i has exactly the qualifier `want`.
fn q_is(r: &Spf, i: Int, want: Str) -> Bool {
  return streq(spf_term_qualifier(r, i), want);
}

// True when term i has exactly the value `want`.
fn v_is(r: &Spf, i: Int, want: Str) -> Bool {
  return streq(spf_term_value(r, i), want);
}

// True when term i has exactly the CIDR `want`.
fn c_is(r: &Spf, i: Int, want: Int) -> Bool {
  return spf_term_cidr(r, i) == want;
}

// True when term i is a modifier.
fn ismod(r: &Spf, i: Int) -> Bool {
  return spf_term_is_modifier(r, i);
}

// True when spf_parse(text) is Err with exactly `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = spf_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Structural equality of two records, field by field through the accessors.
fn spf_same(a: &Spf, b: &Spf) -> Bool {
  let n = spf_term_count(a);
  if n != spf_term_count(b) {
    return false;
  }
  var i = 0;
  while i < n {
    if !streq(spf_term_kind(a, i), spf_term_kind(b, i)) {
      return false;
    }
    if !streq(spf_term_qualifier(a, i), spf_term_qualifier(b, i)) {
      return false;
    }
    if !streq(spf_term_value(a, i), spf_term_value(b, i)) {
      return false;
    }
    if spf_term_cidr(a, i) != spf_term_cidr(b, i) {
      return false;
    }
    if spf_term_is_modifier(a, i) != spf_term_is_modifier(b, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when parsing, emitting, reparsing and re-emitting are stable:
// parse(emit(r)) preserves r structurally and emit is idempotent.
fn roundtrip(text: Str) -> Bool {
  var ok = false;
  let a = spf_parse(text);
  match a {
    Ok(x) => {
      let e1 = spf_emit(&x);
      let b = spf_parse(e1);
      match b {
        Ok(y) => {
          if spf_same(&x, &y) {
            let e2 = spf_emit(&y);
            if streq(e1, e2) {
              ok = true;
            }
          }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn t1() -> TestResult {
  let r = p("v=spf1");
  var ok = spf_term_count(&r) == 0;
  if !streq(spf_emit(&r), "v=spf1") { ok = false; }
  if !roundtrip("v=spf1") { ok = false; }
  return assert(ok, "a bare v=spf1 record has zero terms, emits and round-trips");
}

fn t2() -> TestResult {
  let r = p("v=spf1 all");
  var ok = spf_term_count(&r) == 1;
  if !k_is(&r, 0, "all") { ok = false; }
  if !q_is(&r, 0, "+") { ok = false; }
  if !v_is(&r, 0, "") { ok = false; }
  if !c_is(&r, 0, -1) { ok = false; }
  if ismod(&r, 0) { ok = false; }
  let r2 = p("v=spf1 -all");
  if !q_is(&r2, 0, "-") { ok = false; }
  if !streq(spf_emit(&r2), "v=spf1 -all") { ok = false; }
  return assert(ok, "all defaults to the + qualifier and -all is preserved");
}

fn t3() -> TestResult {
  let r = p("v=spf1 a mx ptr include:one.example exists:two.example ip4:192.0.2.1 ip6:2001:db8::1");
  var ok = spf_term_count(&r) == 7;
  if !k_is(&r, 0, "a") { ok = false; }
  if !k_is(&r, 1, "mx") { ok = false; }
  if !k_is(&r, 2, "ptr") { ok = false; }
  if !v_is(&r, 2, "") { ok = false; }
  if !k_is(&r, 3, "include") { ok = false; }
  if !v_is(&r, 3, "one.example") { ok = false; }
  if !k_is(&r, 4, "exists") { ok = false; }
  if !v_is(&r, 4, "two.example") { ok = false; }
  if !k_is(&r, 5, "ip4") { ok = false; }
  if !v_is(&r, 5, "192.0.2.1") { ok = false; }
  if !k_is(&r, 6, "ip6") { ok = false; }
  if !v_is(&r, 6, "2001:db8::1") { ok = false; }
  if !q_is(&r, 6, "+") { ok = false; }
  if !c_is(&r, 5, -1) { ok = false; }
  return assert(ok, "all eight mechanism names parse with values and default qualifier");
}

fn t4() -> TestResult {
  let r = p("v=spf1 +a -mx ~ptr ?exists:x.example +all");
  var ok = spf_term_count(&r) == 5;
  if !q_is(&r, 0, "+") { ok = false; }
  if !q_is(&r, 1, "-") { ok = false; }
  if !q_is(&r, 2, "~") { ok = false; }
  if !q_is(&r, 3, "?") { ok = false; }
  if !q_is(&r, 4, "+") { ok = false; }
  let want = "v=spf1 a -mx ~ptr ?exists:x.example all";
  if !streq(spf_emit(&r), want) { ok = false; }
  return assert(ok, "all four qualifiers parse and the default + is canonicalized away");
}

fn t5() -> TestResult {
  let r = p("v=spf1 ip4:192.0.2.0/24 ip4:198.51.100.7 ip6:2001:db8::/32 ip6:2001:db8::1 ip6:2001:db8::/128");
  var ok = spf_term_count(&r) == 5;
  if !c_is(&r, 0, 24) { ok = false; }
  if !v_is(&r, 0, "192.0.2.0") { ok = false; }
  if !c_is(&r, 1, -1) { ok = false; }
  if !v_is(&r, 1, "198.51.100.7") { ok = false; }
  if !c_is(&r, 2, 32) { ok = false; }
  if !v_is(&r, 2, "2001:db8::") { ok = false; }
  if !c_is(&r, 3, -1) { ok = false; }
  if !v_is(&r, 3, "2001:db8::1") { ok = false; }
  if !c_is(&r, 4, 128) { ok = false; }
  return assert(ok, "ip4 CIDR 0..32 and ip6 CIDR 0..128 are stored and validated");
}

fn t6() -> TestResult {
  let r = p("v=spf1 a a/24 a:example.com a:example.com/28 mx mx/32 mx:mail.example.com/0");
  var ok = spf_term_count(&r) == 7;
  if !k_is(&r, 0, "a") { ok = false; }
  if !c_is(&r, 0, -1) { ok = false; }
  if !c_is(&r, 1, 24) { ok = false; }
  if !v_is(&r, 1, "") { ok = false; }
  if !v_is(&r, 2, "example.com") { ok = false; }
  if !c_is(&r, 2, -1) { ok = false; }
  if !v_is(&r, 3, "example.com") { ok = false; }
  if !c_is(&r, 3, 28) { ok = false; }
  if !k_is(&r, 4, "mx") { ok = false; }
  if !c_is(&r, 5, 32) { ok = false; }
  if !v_is(&r, 6, "mail.example.com") { ok = false; }
  if !c_is(&r, 6, 0) { ok = false; }
  let want = "v=spf1 a a/24 a:example.com a:example.com/28 mx mx/32 mx:mail.example.com/0";
  if !streq(spf_emit(&r), want) { ok = false; }
  return assert(ok, "a/mx accept an optional value and an optional CIDR 0..32");
}

fn t7() -> TestResult {
  let r = p("v=spf1 include:%{d}.%{ir}.example exists:%{i}._spf.%{d} a:%{l1r-}/24 redirect=%{d2}.%{d}");
  var ok = spf_term_count(&r) == 4;
  if !v_is(&r, 0, "%{d}.%{ir}.example") { ok = false; }
  if !v_is(&r, 1, "%{i}._spf.%{d}") { ok = false; }
  if !v_is(&r, 2, "%{l1r-}") { ok = false; }
  if !c_is(&r, 2, 24) { ok = false; }
  if spf_find_modifier(&r, "redirect") != 3 { ok = false; }
  if !v_is(&r, 3, "%{d2}.%{d}") { ok = false; }
  if !roundtrip("v=spf1 include:%{d}.%{ir}.example exists:%{i}._spf.%{d} a:%{l1r-}/24 redirect=%{d2}.%{d}") { ok = false; }
  return assert(ok, "macro strings pass through verbatim, including in a CIDR term");
}

fn t8() -> TestResult {
  let r = p("v=spf1 redirect=_spf.example.com exp=explain.example.com");
  var ok = spf_term_count(&r) == 2;
  if !ismod(&r, 0) { ok = false; }
  if !k_is(&r, 0, "redirect") { ok = false; }
  if !v_is(&r, 0, "_spf.example.com") { ok = false; }
  if !q_is(&r, 0, "") { ok = false; }
  if !c_is(&r, 0, -1) { ok = false; }
  if !ismod(&r, 1) { ok = false; }
  if !k_is(&r, 1, "exp") { ok = false; }
  if !v_is(&r, 1, "explain.example.com") { ok = false; }
  if spf_find_modifier(&r, "redirect") != 0 { ok = false; }
  if spf_find_modifier(&r, "exp") != 1 { ok = false; }
  if spf_find_modifier(&r, "EXP") != 1 { ok = false; }
  if spf_find_modifier(&r, "nope") != -1 { ok = false; }
  if !streq(spf_emit(&r), "v=spf1 redirect=_spf.example.com exp=explain.example.com") { ok = false; }
  return assert(ok, "redirect and exp are modifiers with case-insensitive lookup");
}

fn t9() -> TestResult {
  let r = p("v=spf1 foo=bar baz=a=b");
  var ok = spf_term_count(&r) == 2;
  if !ismod(&r, 0) { ok = false; }
  if !k_is(&r, 0, "foo") { ok = false; }
  if !v_is(&r, 0, "bar") { ok = false; }
  if !k_is(&r, 1, "baz") { ok = false; }
  if !v_is(&r, 1, "a=b") { ok = false; }
  if spf_find_modifier(&r, "foo") != 0 { ok = false; }
  if spf_find_modifier(&r, "baz") != 1 { ok = false; }
  if !streq(spf_emit(&r), "v=spf1 foo=bar baz=a=b") { ok = false; }
  let r2 = p("v=spf1 foo=");
  if spf_term_count(&r2) != 1 { ok = false; }
  if !v_is(&r2, 0, "") { ok = false; }
  let r3 = p("v=spf1 v=spf1");
  if spf_term_count(&r3) != 1 { ok = false; }
  if !k_is(&r3, 0, "v") { ok = false; }
  if !v_is(&r3, 0, "spf1") { ok = false; }
  return assert(ok, "unknown modifiers are preserved; a later v= token is a modifier named v");
}

fn t10() -> TestResult {
  let r = p("  \tV=SPF1\t+A   mx:Mail.Example.COM/24  ~IP4:192.0.2.1 REDIRECT=x.example  ");
  var ok = spf_term_count(&r) == 4;
  if !k_is(&r, 0, "a") { ok = false; }
  if !q_is(&r, 0, "+") { ok = false; }
  if !v_is(&r, 1, "Mail.Example.COM") { ok = false; }
  if !c_is(&r, 1, 24) { ok = false; }
  if !k_is(&r, 2, "ip4") { ok = false; }
  if !q_is(&r, 2, "~") { ok = false; }
  if !k_is(&r, 3, "REDIRECT") { ok = false; }
  if !v_is(&r, 3, "x.example") { ok = false; }
  let want = "v=spf1 a mx:Mail.Example.COM/24 ~ip4:192.0.2.1 REDIRECT=x.example";
  if !streq(spf_emit(&r), want) { ok = false; }
  return assert(ok, "canonical emit: lowercase mechanisms, verbatim values, single spaces");
}

fn t11() -> TestResult {
  let text = "v=spf1 all include:_spf.example.com a a/24 a:a.example.com/28 mx mx:mail.example.com/16 ptr ptr:p.example.com ip4:192.0.2.1 ip6:2001:db8::1/128 exists:%{i}._spf.%{d} redirect=_spf.example.com exp=%{d} foo=x=y -all";
  let r = p(text);
  var ok = spf_term_count(&r) == 16;
  if !roundtrip(text) { ok = false; }
  return assert(ok, "a 16-term mixed record round-trips and emit is idempotent");
}

fn t12() -> TestResult {
  var ok = err_is("", "spf: missing version");
  if !err_is("   \t ", "spf: missing version") { ok = false; }
  if !err_is("all -all", "spf: missing version") { ok = false; }
  if !err_is("spf1 -all", "spf: missing version") { ok = false; }
  if !err_is("v= -all", "spf: wrong version: v=") { ok = false; }
  if !err_is("v=spf2 -all", "spf: wrong version: v=spf2") { ok = false; }
  if !err_is("v=spf10 -all", "spf: wrong version: v=spf10") { ok = false; }
  let r = p("V=SPF1 -all");
  if spf_term_count(&r) != 1 { ok = false; }
  if !k_is(&r, 0, "all") { ok = false; }
  if !streq(spf_emit(&r), "v=spf1 -all") { ok = false; }
  return assert(ok, "the version is required, must be v=spf1, and is case-insensitive");
}

fn t13() -> TestResult {
  var ok = err_is("v=spf1 foo", "spf: unknown mechanism: foo");
  if !err_is("v=spf1 allx", "spf: unknown mechanism: allx") { ok = false; }
  if !err_is("v=spf1 ipv4:1.2.3.4", "spf: unknown mechanism: ipv4:1.2.3.4") { ok = false; }
  if !err_is("v=spf1 foo/24", "spf: unknown mechanism: foo/24") { ok = false; }
  if !err_is("v=spf1 a!b", "spf: unknown mechanism: a!b") { ok = false; }
  if !err_is("v=spf1 -foo", "spf: unknown mechanism: -foo") { ok = false; }
  if !err_is("v=spf1 1st", "spf: unknown mechanism: 1st") { ok = false; }
  if !err_is("v=spf1 1st=x", "spf: unknown mechanism: 1st=x") { ok = false; }
  return assert(ok, "unknown mechanism names are rejected with the whole term");
}

fn t14() -> TestResult {
  var ok = err_is("v=spf1 all:x", "spf: bad mechanism syntax: all:x");
  if !err_is("v=spf1 all/8", "spf: bad mechanism syntax: all/8") { ok = false; }
  if !err_is("v=spf1 include", "spf: bad mechanism syntax: include") { ok = false; }
  if !err_is("v=spf1 include:", "spf: bad mechanism syntax: include:") { ok = false; }
  if !err_is("v=spf1 include:x/24", "spf: bad mechanism syntax: include:x/24") { ok = false; }
  if !err_is("v=spf1 exists", "spf: bad mechanism syntax: exists") { ok = false; }
  if !err_is("v=spf1 ptr:", "spf: bad mechanism syntax: ptr:") { ok = false; }
  if !err_is("v=spf1 ptr:x/24", "spf: bad mechanism syntax: ptr:x/24") { ok = false; }
  if !err_is("v=spf1 ip4:", "spf: bad mechanism syntax: ip4:") { ok = false; }
  if !err_is("v=spf1 ip4/24", "spf: bad mechanism syntax: ip4/24") { ok = false; }
  if !err_is("v=spf1 ip6/64", "spf: bad mechanism syntax: ip6/64") { ok = false; }
  return assert(ok, "structural mechanism errors: unexpected value, slash or empty value");
}

fn t15() -> TestResult {
  var ok = err_is("v=spf1 a/33", "spf: bad cidr: a/33");
  if !err_is("v=spf1 mx/33", "spf: bad cidr: mx/33") { ok = false; }
  if !err_is("v=spf1 ip4:192.0.2.1/33", "spf: bad cidr: ip4:192.0.2.1/33") { ok = false; }
  if !err_is("v=spf1 ip6:::1/129", "spf: bad cidr: ip6:::1/129") { ok = false; }
  if !err_is("v=spf1 a/", "spf: bad cidr: a/") { ok = false; }
  if !err_is("v=spf1 a/024", "spf: bad cidr: a/024") { ok = false; }
  if !err_is("v=spf1 a/x", "spf: bad cidr: a/x") { ok = false; }
  if !err_is("v=spf1 a/1.5", "spf: bad cidr: a/1.5") { ok = false; }
  if !err_is("v=spf1 mx/-1", "spf: bad cidr: mx/-1") { ok = false; }
  let r = p("v=spf1 a/0 a/32 ip6:::1/0 ip6:::1/128");
  if spf_term_count(&r) != 4 { ok = false; }
  if !c_is(&r, 0, 0) { ok = false; }
  if !c_is(&r, 1, 32) { ok = false; }
  if !c_is(&r, 2, 0) { ok = false; }
  if !c_is(&r, 3, 128) { ok = false; }
  return assert(ok, "CIDR must be a canonical decimal within 0..32 or 0..128");
}

fn t16() -> TestResult {
  var ok = err_is("v=spf1 +", "spf: empty term: +");
  if !err_is("v=spf1 -", "spf: empty term: -") { ok = false; }
  if !err_is("v=spf1 ~", "spf: empty term: ~") { ok = false; }
  if !err_is("v=spf1 ?", "spf: empty term: ?") { ok = false; }
  if !err_is("v=spf1 :x", "spf: empty term: :x") { ok = false; }
  if !err_is("v=spf1 /24", "spf: empty term: /24") { ok = false; }
  if !err_is("v=spf1 =x", "spf: empty term: =x") { ok = false; }
  if !err_is("v=spf1 %{d}", "spf: empty term: %{d}") { ok = false; }
  return assert(ok, "a term with a qualifier but no name, or with no name at all, is empty");
}

fn t17() -> TestResult {
  var ok = err_is("v=spf1 redirect=a redirect=b", "spf: duplicate modifier: redirect");
  if !err_is("v=spf1 REDIRECT=a Redirect=b", "spf: duplicate modifier: Redirect") { ok = false; }
  if !err_is("v=spf1 exp=a exp=b", "spf: duplicate modifier: exp") { ok = false; }
  if !err_is("v=spf1 foo=a foo=b", "spf: duplicate modifier: foo") { ok = false; }
  if !err_is("v=spf1 foo=a FOO=b", "spf: duplicate modifier: FOO") { ok = false; }
  if !err_is("v=spf1 exp=a redirect=b exp=c", "spf: duplicate modifier: exp") { ok = false; }
  return assert(ok, "each modifier name may appear once, compared case-insensitively");
}

fn t18() -> TestResult {
  var ok = err_is("v=spf1 +redirect=x", "spf: bad modifier: +redirect=x");
  if !err_is("v=spf1 ~foo=x", "spf: bad modifier: ~foo=x") { ok = false; }
  if !err_is("v=spf1 redirect=", "spf: bad modifier: redirect=") { ok = false; }
  if !err_is("v=spf1 Exp=", "spf: bad modifier: Exp=") { ok = false; }
  let r = p("v=spf1 foo=");
  if spf_term_count(&r) != 1 { ok = false; }
  if !v_is(&r, 0, "") { ok = false; }
  return assert(ok, "qualifiers cannot precede modifiers and redirect/exp need a value");
}

fn t19() -> TestResult {
  var ok = err_is("v=spf1 include:%", "spf: bad macro: include:%");
  if !err_is("v=spf1 include:a%", "spf: bad macro: include:a%") { ok = false; }
  if !err_is("v=spf1 include:%{", "spf: bad macro: include:%{") { ok = false; }
  if !err_is("v=spf1 include:%{}", "spf: bad macro: include:%{}") { ok = false; }
  if !err_is("v=spf1 include:%{x}", "spf: bad macro: include:%{x}") { ok = false; }
  if !err_is("v=spf1 include:%{d", "spf: bad macro: include:%{d") { ok = false; }
  if !err_is("v=spf1 include:%{d2x}", "spf: bad macro: include:%{d2x}") { ok = false; }
  if !err_is("v=spf1 redirect=%{d", "spf: bad macro: redirect=%{d") { ok = false; }
  if !err_is("v=spf1 foo=%{2d}", "spf: bad macro: foo=%{2d}") { ok = false; }
  if !err_is("v=spf1 a:%/24", "spf: bad macro: a:%/24") { ok = false; }
  let r = p("v=spf1 include:%%%_%-");
  if spf_term_count(&r) != 1 { ok = false; }
  if !v_is(&r, 0, "%%%_%-") { ok = false; }
  return assert(ok, "malformed macros are rejected; %% %_ %- escapes are accepted");
}

fn t20() -> TestResult {
  var ok = spf_macro_valid("%{d}.%{d2}.%{ir}.%{l1r-}.%{D}.%{v}");
  if !spf_macro_valid("%%") { ok = false; }
  if !spf_macro_valid("%_") { ok = false; }
  if !spf_macro_valid("%-") { ok = false; }
  if !spf_macro_valid("plain.example") { ok = false; }
  if spf_macro_valid("%") { ok = false; }
  if spf_macro_valid("%{") { ok = false; }
  if spf_macro_valid("%{}") { ok = false; }
  if spf_macro_valid("%{x}") { ok = false; }
  if spf_macro_valid("%{d") { ok = false; }
  if spf_macro_valid("%{d2x}") { ok = false; }
  if spf_macro_valid("%{d%}") { ok = false; }
  if spf_macro_valid("a%") { ok = false; }
  return assert(ok, "spf_macro_valid pins the documented macro predicate");
}

fn t21() -> TestResult {
  var ok = err_is("v=spf1 \u{0001}all", "spf: control byte in input");
  if !err_is("\u{000B}v=spf1", "spf: control byte in input") { ok = false; }
  if !err_is("v=spf1\u{007F}", "spf: control byte in input") { ok = false; }
  if !err_is("v=spf1\n-all", "spf: control byte in input") { ok = false; }
  if !err_is("v=spf1\r-all", "spf: control byte in input") { ok = false; }
  return assert(ok, "C0 control bytes, LF, CR and DEL anywhere in the input are errors");
}

fn t22() -> TestResult {
  let r = p("\t v=spf1\t\t-all  \t");
  var ok = spf_term_count(&r) == 1;
  if !k_is(&r, 0, "all") { ok = false; }
  if !q_is(&r, 0, "-") { ok = false; }
  if !streq(spf_emit(&r), "v=spf1 -all") { ok = false; }
  if !roundtrip("\t v=spf1\t\t-all  \t") { ok = false; }
  return assert(ok, "SP and TAB runs separate terms and are stripped around the record");
}

fn t23() -> TestResult {
  let r = p("v=spf1 -all redirect=x");
  var ok = spf_term_count(&r) == 2;
  if !streq(spf_term_kind(&r, -1), "") { ok = false; }
  if !streq(spf_term_kind(&r, 2), "") { ok = false; }
  if !streq(spf_term_qualifier(&r, 1), "") { ok = false; }
  if !streq(spf_term_qualifier(&r, -3), "") { ok = false; }
  if !streq(spf_term_value(&r, 5), "") { ok = false; }
  if spf_term_cidr(&r, -1) != -1 { ok = false; }
  if spf_term_cidr(&r, 5) != -1 { ok = false; }
  if spf_term_is_modifier(&r, 2) { ok = false; }
  if !spf_term_is_modifier(&r, 1) { ok = false; }
  if spf_find_modifier(&r, "redirect") != 1 { ok = false; }
  if spf_find_modifier(&r, "REDIRECT") != 1 { ok = false; }
  if spf_find_modifier(&r, "exp") != -1 { ok = false; }
  return assert(ok, "out-of-range accessors return \"\"/-1/false and never trap");
}

fn t24() -> TestResult {
  let e = spf_new();
  var ok = spf_term_count(&e) == 0;
  if !streq(spf_term_kind(&e, 0), "") { ok = false; }
  if !streq(spf_emit(&e), "v=spf1") { ok = false; }
  if spf_find_modifier(&e, "redirect") != -1 { ok = false; }
  if !roundtrip("v=spf1") { ok = false; }
  return assert(ok, "spf_new is an empty record that emits v=spf1");
}

fn t25() -> TestResult {
  let r = p("v=spf1 a:/24 A:EXAMPLE.COM/24 a:%{d/}/24");
  var ok = spf_term_count(&r) == 3;
  if !k_is(&r, 0, "a") { ok = false; }
  if !v_is(&r, 0, "") { ok = false; }
  if !c_is(&r, 0, 24) { ok = false; }
  if !v_is(&r, 1, "EXAMPLE.COM") { ok = false; }
  if !c_is(&r, 1, 24) { ok = false; }
  if !v_is(&r, 2, "%{d/}") { ok = false; }
  if !c_is(&r, 2, 24) { ok = false; }
  let want = "v=spf1 a/24 a:EXAMPLE.COM/24 a:%{d/}/24";
  if !streq(spf_emit(&r), want) { ok = false; }
  return assert(ok, "a:/24 normalizes to a/24 and a macro-slash does not split the CIDR");
}

fn t26() -> TestResult {
  let r = p("v=spf1 redirect=x.example -all");
  var ok = spf_term_count(&r) == 2;
  if !ismod(&r, 0) { ok = false; }
  if !k_is(&r, 0, "redirect") { ok = false; }
  if ismod(&r, 1) { ok = false; }
  if !k_is(&r, 1, "all") { ok = false; }
  if !q_is(&r, 1, "-") { ok = false; }
  if !streq(spf_emit(&r), "v=spf1 redirect=x.example -all") { ok = false; }
  let r2 = p("v=spf1 all all");
  if spf_term_count(&r2) != 2 { ok = false; }
  return assert(ok, "term order is preserved and duplicate mechanisms are allowed");
}

fn main() -> Int {
  io.println("=== xiom.spf conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.spf: all tests passed");
  } else {
    io.println("xiom.spf: tests failed");
  }
  return failed;
}
