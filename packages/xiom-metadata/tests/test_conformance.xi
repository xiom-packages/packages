// XIOM -- xiom.metadata conformance tests (28 checks)
// Port task: prove the pure-XIOM xiom.metadata block model against its
// documented rules: case-insensitive identity, duplicate policies, scoping
// and nesting, merge precedence and provenance, diff, canonical
// serialization with parse round-trip, validation catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq/opt_is/blocks_equal.
// Fixtures are literal text fed through md_parse or explicit md_set calls.

module metadata_tests
use xiom.io; use xiom.test; use xiom.metadata;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// md_set with a fixture policy; on Err the input block is returned
// unchanged so a bad fixture fails the assertions instead of crashing.
fn set_ok(b: MetaBlock, section: Str, key: Str, value: Str, policy: Int) -> MetaBlock {
  let r = md_set(&b, section, key, value, policy);
  match r {
    Ok(x) => { return x; },
    Err(_) => { return b; },
  }
  return b;
}

fn parse_ok(text: Str, policy: Int) -> MetaBlock {
  let r = md_parse(text, policy);
  match r {
    Ok(x) => { return x; },
    Err(_) => { return md_new(); },
  }
  return md_new();
}

fn parse_err_eq(text: Str, policy: Int, want: Str) -> Bool {
  let r = md_parse(text, policy);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn blocks_equal(a: &MetaBlock, b: &MetaBlock) -> Bool {
  if md_len(a) != md_len(b) { return false; }
  var i = 0;
  while i < md_len(a) {
    if !streq(md_entry_section(a, i), md_entry_section(b, i)) { return false; }
    if !streq(md_entry_key(a, i), md_entry_key(b, i)) { return false; }
    if !streq(md_entry_value(a, i), md_entry_value(b, i)) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let b = md_new();
  var ok = md_len(&b) == 0;
  if !opt_none(md_get(&b, "", "any")) { ok = false; }
  if !streq(md_serialize(&b), "") { ok = false; }
  if !streq(md_serialize_sorted(&b), "") { ok = false; }
  if !streq(md_validate(&b), "") { ok = false; }
  if md_first_duplicate(&b) != -1 { ok = false; }
  return assert(ok, "empty block: no entries, empty text, valid, no duplicates");
}

fn t2() -> TestResult {
  let b = set_ok(set_ok(set_ok(md_new(), "", "a", "1", md_dup_last()), "", "b", "2", md_dup_last()), "", "c", "3", md_dup_last());
  var ok = md_len(&b) == 3;
  if !streq(md_entry_key(&b, 0), "a") { ok = false; }
  if !streq(md_entry_value(&b, 0), "1") { ok = false; }
  if !streq(md_entry_section(&b, 0), "") { ok = false; }
  if md_entry_origin(&b, 0) != md_origin_primary() { ok = false; }
  if !streq(md_entry_key(&b, 1), "b") { ok = false; }
  if !streq(md_entry_value(&b, 2), "3") { ok = false; }
  if !streq(md_entry_key(&b, 9), "") { ok = false; }
  if md_entry_origin(&b, 9) != -1 { ok = false; }
  if !streq(md_serialize(&b), "a = 1\nb = 2\nc = 3") { ok = false; }
  return assert(ok, "md_set appends in insertion order and accessors read entries");
}

fn t3() -> TestResult {
  let b = parse_ok("Server.Host = example.org\n", md_dup_last());
  var ok = opt_is(md_get(&b, "server", "host"), "example.org");
  if !opt_is(md_get(&b, "SERVER", "HOST"), "example.org") { ok = false; }
  if !md_has(&b, "sErVeR", "HoSt") { ok = false; }
  if md_index(&b, "server", "HOST") != 0 { ok = false; }
  if !streq(md_entry_section(&b, 0), "Server") { ok = false; }
  if !streq(md_entry_key(&b, 0), "Host") { ok = false; }
  return assert(ok, "lookups are case-insensitive on ASCII and preserve stored spelling");
}

fn t4() -> TestResult {
  let b = parse_ok("a = 1\n", md_dup_last());
  var ok = !md_has(&b, "", "missing");
  if md_index(&b, "", "missing") != -1 { ok = false; }
  if !opt_none(md_get(&b, "", "missing")) { ok = false; }
  if !opt_int_none(md_origin(&b, "", "missing")) { ok = false; }
  return assert(ok, "absent pairs yield false, -1 and None");
}

fn t5() -> TestResult {
  let p = parse_ok("k = 1\nk = 2\nk = 3\n", md_dup_first());
  var ok = md_len(&p) == 1;
  if !opt_is(md_get(&p, "", "k"), "1") { ok = false; }
  let b = set_ok(md_new(), "", "k", "1", md_dup_last());
  let b2 = set_ok(b, "", "K", "2", md_dup_first());
  if md_len(&b2) != 1 { ok = false; }
  if !opt_is(md_get(&b2, "", "k"), "1") { ok = false; }
  return assert(ok, "policy first: first value and position win");
}

fn t6() -> TestResult {
  let p = parse_ok("k = 1\nk = 2\nk = 3\n", md_dup_last());
  var ok = md_len(&p) == 1;
  if !opt_is(md_get(&p, "", "k"), "3") { ok = false; }
  var b = set_ok(md_new(), "", "k", "1", md_dup_last());
  b = set_ok(b, "", "K", "2", md_dup_last());
  b = set_ok(b, "", "k", "3", md_dup_last());
  if md_len(&b) != 1 { ok = false; }
  if md_index(&b, "", "k") != 0 { ok = false; }
  if !opt_is(md_get(&b, "", "k"), "3") { ok = false; }
  return assert(ok, "policy last: last value wins in the first position");
}

fn t7() -> TestResult {
  let b = set_ok(md_new(), "", "k", "1", md_dup_last());
  let r = md_set(&b, "", "K", "2", md_dup_error());
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = streq(e, "metadata: duplicate key: K"); },
  }
  if md_len(&b) != 1 { ok = false; }
  if !opt_is(md_get(&b, "", "k"), "1") { ok = false; }
  if !parse_err_eq("k = 1\nK = 2\n", md_dup_error(), "metadata: duplicate key: K") { ok = false; }
  return assert(ok, "policy error: duplicate assignment fails with the catalog message");
}

fn t8() -> TestResult {
  let b = md_new();
  let r = md_set(&b, "", "k", "v", 9);
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = streq(e, "metadata: unknown duplicate policy: 9"); },
  }
  let r2 = md_parse("k = 1\n", 7);
  match r2 {
    Ok(_) => { ok = false; },
    Err(e2) => { if !streq(e2, "metadata: unknown duplicate policy: 7") { ok = false; } },
  }
  return assert(ok, "unknown duplicate policy codes fail closed");
}

fn t9() -> TestResult {
  var ok = md_key_valid("name");
  if !md_key_valid("track_01") { ok = false; }
  if md_key_valid("") { ok = false; }
  if md_key_valid("a b") { ok = false; }
  if md_key_valid("a.b") { ok = false; }
  if md_key_valid("a=b") { ok = false; }
  if md_key_valid("a#b") { ok = false; }
  if md_key_valid("a;b") { ok = false; }
  if md_key_valid("a[b") { ok = false; }
  if md_key_valid("a]b") { ok = false; }
  if md_key_valid("a\tb") { ok = false; }
  if !md_section_valid("") { ok = false; }
  if !md_section_valid("server") { ok = false; }
  if !md_section_valid("server.tls") { ok = false; }
  if md_section_valid("a..b") { ok = false; }
  if md_section_valid(".a") { ok = false; }
  if md_section_valid("a.") { ok = false; }
  if md_section_valid("a b") { ok = false; }
  if md_section_valid("a=b") { ok = false; }
  return assert(ok, "key and section rules: dot-free key, dotted non-empty section segments");
}

fn t10() -> TestResult {
  var ok = md_value_valid("");
  if !md_value_valid("plain") { ok = false; }
  if !md_value_valid("two words") { ok = false; }
  if !md_value_valid("a\tb") { ok = false; }
  if !md_value_valid("x = y") { ok = false; }
  if md_value_valid(" lead") { ok = false; }
  if md_value_valid("trail ") { ok = false; }
  if md_value_valid(" both ") { ok = false; }
  if md_value_valid("tab\t") { ok = false; }
  if md_value_valid("\ttab") { ok = false; }
  if md_value_valid("line\nbreak") { ok = false; }
  if md_value_valid("car\rreturn") { ok = false; }
  return assert(ok, "value rules: no CR/LF/NUL, no edge space/tab, interior bytes free");
}

fn t11() -> TestResult {
  var ok = md_validate_code("a.b", "k", "v") == md_val_ok();
  if !streq(md_val_name(md_val_ok()), "ok") { ok = false; }
  if md_validate_code("a..b", "k", "v") != md_val_bad_section() { ok = false; }
  if !streq(md_val_name(md_val_bad_section()), "invalid-section") { ok = false; }
  if md_validate_code("", "a.b", "v") != md_val_bad_key() { ok = false; }
  if !streq(md_val_name(md_val_bad_key()), "invalid-key") { ok = false; }
  if md_validate_code("", "k", " v") != md_val_bad_value() { ok = false; }
  if !streq(md_val_name(md_val_bad_value()), "invalid-value") { ok = false; }
  if !streq(md_validate_message("a..b", "k", "v"), "metadata: invalid section: a..b") { ok = false; }
  if !streq(md_validate_message("", "a.b", "v"), "metadata: invalid key: a.b") { ok = false; }
  if !streq(md_validate_message("", "k", " v"), "metadata: invalid value:  v") { ok = false; }
  if !streq(md_validate_message("", "k", "v"), "") { ok = false; }
  return assert(ok, "validation catalog: codes, names and pinned messages");
}

fn t12() -> TestResult {
  let good = parse_ok("a.b = 1\nc = 2\n", md_dup_last());
  var ok = streq(md_validate(&good), "");
  let bad1 = set_ok(md_new(), "a..b", "k", "v", md_dup_last());
  if !streq(md_validate(&bad1), "metadata: invalid section: a..b") { ok = false; }
  let bad2 = set_ok(md_new(), "", "a b", "v", md_dup_last());
  if !streq(md_validate(&bad2), "metadata: invalid key: a b") { ok = false; }
  let bad3 = set_ok(md_new(), "", "k", " v", md_dup_last());
  if !streq(md_validate(&bad3), "metadata: invalid value:  v") { ok = false; }
  return assert(ok, "md_validate returns the first failure in insertion order");
}

fn t13() -> TestResult {
  let b = md_append(md_append(md_append(md_new(), "", "a", "1"), "", "b", "2"), "", "A", "3");
  var ok = md_len(&b) == 3;
  if md_first_duplicate(&b) != 2 { ok = false; }
  if !streq(md_entry_key(&b, 2), "A") { ok = false; }
  let u = parse_ok("a = 1\nb = 2\n", md_dup_last());
  if md_first_duplicate(&u) != -1 { ok = false; }
  if !streq(md_serialize(&b), "a = 1\nb = 2\nA = 3") { ok = false; }
  return assert(ok, "md_append can build duplicates; md_first_duplicate finds the later entry");
}

fn t14() -> TestResult {
  let base = parse_ok("host = localhost\nserver.port = 8080\n", md_dup_last());
  let sc = md_scoped(&base, "app");
  var ok = md_len(&sc) == 2;
  if !streq(md_serialize(&sc), "app.host = localhost\napp.server.port = 8080") { ok = false; }
  if !opt_is(md_get(&sc, "APP", "host"), "localhost") { ok = false; }
  if !opt_is(md_get(&sc, "app.server", "port"), "8080") { ok = false; }
  let same = md_scoped(&base, "");
  if !blocks_equal(&same, &base) { ok = false; }
  return assert(ok, "md_scoped re-parents root and nested entries under a prefix");
}

fn t15() -> TestResult {
  let base = parse_ok("host = localhost\nserver.port = 8080\nserver.tls.mode = on\n", md_dup_last());
  let sub = md_subblock(&base, "server");
  var ok = md_len(&sub) == 1;
  if !streq(md_serialize(&sub), "port = 8080") { ok = false; }
  if !opt_is(md_get(&sub, "", "port"), "8080") { ok = false; }
  let deep = md_subblock(&base, "SERVER.TLS");
  if md_len(&deep) != 1 { ok = false; }
  if !streq(md_entry_value(&deep, 0), "on") { ok = false; }
  let none = md_subblock(&base, "missing");
  if md_len(&none) != 0 { ok = false; }
  return assert(ok, "md_subblock extracts one exact section level and re-roots it");
}

fn t16() -> TestResult {
  let base = parse_ok("debug = 0\nserver.host = localhost\nserver.port = 8080\n", md_dup_last());
  let over = parse_ok("server.HOST = example.org\nserver.port = 9090\nname = app\n", md_dup_last());
  let m = md_merge(&base, &over);
  var ok = md_len(&m) == 4;
  if !opt_is(md_get(&m, "", "debug"), "0") { ok = false; }
  if !opt_is(md_get(&m, "server", "host"), "example.org") { ok = false; }
  if !opt_is(md_get(&m, "server", "port"), "9090") { ok = false; }
  if !opt_is(md_get(&m, "", "name"), "app") { ok = false; }
  if !streq(md_serialize(&m), "debug = 0\nserver.host = example.org\nserver.port = 9090\nname = app") { ok = false; }
  return assert(ok, "merge is over-wins per folded pair, base order then over-only entries");
}

fn t17() -> TestResult {
  let base = parse_ok("a = base-only\nb = base\n", md_dup_last());
  let over = parse_ok("b = over\nc = over-only\n", md_dup_last());
  let m = md_merge(&base, &over);
  var ok = opt_int_is(md_origin(&m, "", "a"), md_origin_primary());
  if !opt_int_is(md_origin(&m, "", "b"), md_origin_override()) { ok = false; }
  if !opt_int_is(md_origin(&m, "", "c"), md_origin_override()) { ok = false; }
  if !opt_int_is(md_origin(&m, "", "a"), md_entry_origin(&m, 0)) { ok = false; }
  if !streq(md_origin_name(md_origin_primary()), "primary") { ok = false; }
  if !streq(md_origin_name(md_origin_override()), "override") { ok = false; }
  let e1 = md_new();
  let all_over = md_merge(&e1, &over);
  if !opt_int_is(md_origin(&all_over, "", "b"), md_origin_override()) { ok = false; }
  let e2 = md_new();
  let all_base = md_merge(&base, &e2);
  if !opt_int_is(md_origin(&all_base, "", "a"), md_origin_primary()) { ok = false; }
  let e3 = md_new();
  let e4 = md_new();
  let both = md_merge(&e3, &e4);
  if md_len(&both) != 0 { ok = false; }
  return assert(ok, "merge provenance: primary for base, override for over, across empty sides");
}

fn t18() -> TestResult {
  let base = parse_ok("Server.Host = a\n", md_dup_last());
  let over = parse_ok("SERVER.HOST = b\n", md_dup_last());
  let m = md_merge(&base, &over);
  var ok = md_len(&m) == 1;
  if !streq(md_entry_section(&m, 0), "Server") { ok = false; }
  if !streq(md_entry_key(&m, 0), "Host") { ok = false; }
  if !streq(md_entry_value(&m, 0), "b") { ok = false; }
  if !streq(md_serialize(&m), "Server.Host = b") { ok = false; }
  return assert(ok, "merge keeps the first-seen spelling while the over value wins");
}

fn t19() -> TestResult {
  let left = parse_ok("a = 1\nb = 2\nc = 3\n", md_dup_last());
  let right = parse_ok("a = 1\nb = 20\nd = 4\n", md_dup_last());
  let d = md_diff(&left, &right);
  var ok = md_diff_len(&d, md_kind_added()) == 1;
  if md_diff_len(&d, md_kind_removed()) != 1 { ok = false; }
  if md_diff_len(&d, md_kind_changed()) != 1 { ok = false; }
  if !streq(md_diff_key(&d, md_kind_added(), 0), "d") { ok = false; }
  if !streq(md_diff_value(&d, md_kind_added(), 0), "4") { ok = false; }
  if !streq(md_diff_key(&d, md_kind_removed(), 0), "c") { ok = false; }
  if !streq(md_diff_value(&d, md_kind_removed(), 0), "3") { ok = false; }
  if !streq(md_diff_key(&d, md_kind_changed(), 0), "b") { ok = false; }
  if !streq(md_diff_value(&d, md_kind_changed(), 0), "2") { ok = false; }
  if !streq(md_diff_new_value(&d, 0), "20") { ok = false; }
  if !streq(md_diff_render(&d), "+ d = 4\n- c = 3\n~ b = 2 -> 20") { ok = false; }
  return assert(ok, "diff reports added, removed and changed pairs with both values");
}

fn t20() -> TestResult {
  let a = parse_ok("x = 1\nserver.k = 2\n", md_dup_last());
  let d0 = md_diff(&a, &a);
  var ok = md_diff_len(&d0, md_kind_added()) == 0;
  if md_diff_len(&d0, md_kind_removed()) != 0 { ok = false; }
  if md_diff_len(&d0, md_kind_changed()) != 0 { ok = false; }
  if !streq(md_diff_render(&d0), "") { ok = false; }
  let b = parse_ok("x = 1\na.k = 2\n", md_dup_last());
  let d1 = md_diff(&a, &b);
  if md_diff_len(&d1, md_kind_added()) != 1 { ok = false; }
  if md_diff_len(&d1, md_kind_removed()) != 1 { ok = false; }
  if md_diff_len(&d1, md_kind_changed()) != 0 { ok = false; }
  if !streq(md_diff_section(&d1, md_kind_added(), 0), "a") { ok = false; }
  if !streq(md_diff_section(&d1, md_kind_removed(), 0), "server") { ok = false; }
  if md_diff_len(&d1, 9) != 0 { ok = false; }
  if !streq(md_diff_section(&d1, 9, 0), "") { ok = false; }
  if !streq(md_diff_value(&d1, md_kind_added(), 5), "") { ok = false; }
  if !streq(md_diff_new_value(&d1, 5), "") { ok = false; }
  if !streq(md_kind_name(md_kind_added()), "added") { ok = false; }
  if !streq(md_kind_name(md_kind_removed()), "removed") { ok = false; }
  if !streq(md_kind_name(md_kind_changed()), "changed") { ok = false; }
  if !streq(md_kind_name(9), "unknown") { ok = false; }
  return assert(ok, "diff identity includes the section; empty and unknown-kind edges are safe");
}

fn t21() -> TestResult {
  let text = "g = 1\nserver.host = localhost\nserver.port = 8080\ndebug = 1\n";
  let b = parse_ok(text, md_dup_last());
  var ok = streq(md_serialize(&b), "g = 1\nserver.host = localhost\nserver.port = 8080\ndebug = 1");
  if !streq(md_serialize(&b) + "\n", text) { ok = false; }
  return assert(ok, "canonical serialization is insertion order with qualified dotted paths");
}

fn t22() -> TestResult {
  let b = parse_ok("z = 1\na = 2\nm.k = 3\nb.q = 4\n", md_dup_last());
  var ok = streq(md_serialize_sorted(&b), "a = 2\nz = 1\nb.q = 4\nm.k = 3");
  if !streq(md_serialize(&b), "z = 1\na = 2\nm.k = 3\nb.q = 4") { ok = false; }
  return assert(ok, "md_serialize_sorted orders by folded section then folded key");
}

fn t23() -> TestResult {
  let b1 = parse_ok("# comment\n; other\n\nserver.host =   localhost  \r\nserver.port=8080\nempty =\n", md_dup_last());
  let text = md_serialize(&b1);
  let b2 = parse_ok(text, md_dup_last());
  var ok = blocks_equal(&b1, &b2);
  if !streq(md_serialize(&b2), text) { ok = false; }
  if !streq(text, "server.host = localhost\nserver.port = 8080\nempty = ") { ok = false; }
  return assert(ok, "serialize then parse round-trips a valid block byte-exact");
}

fn t24() -> TestResult {
  let b = parse_ok("; comment\n# comment\n\n  g  =  1  \n\tk\t=\tv\t\nblob = a=b\tc\n", md_dup_last());
  var ok = md_len(&b) == 3;
  if !opt_is(md_get(&b, "", "g"), "1") { ok = false; }
  if !opt_is(md_get(&b, "", "k"), "v") { ok = false; }
  if !opt_is(md_get(&b, "", "blob"), "a=b\tc") { ok = false; }
  return assert(ok, "parse skips blank/comment lines and trims keys and values");
}

fn t25() -> TestResult {
  var ok = parse_err_eq("noequals", md_dup_last(), "metadata: expected '=' in line: noequals");
  if !parse_err_eq(" = 1", md_dup_last(), "metadata: empty key in line: = 1") { ok = false; }
  if !parse_err_eq("a..b = 1", md_dup_last(), "metadata: invalid section: a.") { ok = false; }
  if !parse_err_eq(".a = 1", md_dup_last(), "metadata: invalid section: ") { ok = false; }
  if !parse_err_eq("a. = 1", md_dup_last(), "metadata: empty key in line: a. = 1") { ok = false; }
  if !parse_err_eq("a b = 1", md_dup_last(), "metadata: invalid key: a b") { ok = false; }
  if !parse_err_eq("a = x\ry", md_dup_last(), "metadata: invalid value: x\ry") { ok = false; }
  if !parse_err_eq("a: 1", md_dup_last(), "metadata: expected '=' in line: a: 1") { ok = false; }
  return assert(ok, "parse errors carry the pinned catalog messages");
}

fn t26() -> TestResult {
  let last = parse_ok("k=1\nK=2\nk=3", md_dup_last());
  var ok = md_len(&last) == 1;
  if !opt_is(md_get(&last, "", "k"), "3") { ok = false; }
  let first = parse_ok("k=1\nK=2\nk=3", md_dup_first());
  if !opt_is(md_get(&first, "", "k"), "1") { ok = false; }
  if !parse_err_eq("k=1\nK=2\n", md_dup_error(), "metadata: duplicate key: K") { ok = false; }
  return assert(ok, "parse applies the selected duplicate policy (first/last/error)");
}

fn t27() -> TestResult {
  let b = parse_ok("k =\na = x = y\nb = a\tb\n", md_dup_last());
  var ok = md_len(&b) == 3;
  if !opt_is(md_get(&b, "", "k"), "") { ok = false; }
  if !opt_is(md_get(&b, "", "a"), "x = y") { ok = false; }
  if !opt_is(md_get(&b, "", "b"), "a\tb") { ok = false; }
  let text = md_serialize(&b);
  if !streq(text, "k = \na = x = y\nb = a\tb") { ok = false; }
  let b2 = parse_ok(text, md_dup_last());
  if !blocks_equal(&b, &b2) { ok = false; }
  return assert(ok, "empty values, embedded '=' and interior tabs survive the round trip");
}

fn t28() -> TestResult {
  let b = md_append(md_new(), "s", "k", "v");
  var ok = opt_int_is(md_origin(&b, "s", "k"), md_origin_primary());
  if !opt_int_is(md_origin(&b, "S", "K"), md_entry_origin(&b, 0)) { ok = false; }
  if !opt_is(md_get(&b, "s", "k"), "v") { ok = false; }
  let p = parse_ok("s.k = v\n", md_dup_last());
  if !opt_int_is(md_origin(&p, "s", "k"), md_origin_primary()) { ok = false; }
  return assert(ok, "append and parse stamp provenance primary");
}

fn main() -> Int {
  io.println("=== xiom.metadata conformance tests ===");
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
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.metadata: all tests passed");
  } else {
    io.println("xiom.metadata: tests failed");
  }
  return failed;
}
