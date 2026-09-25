// XIOM -- xiom.plist conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented subset: the declaration/DOCTYPE prolog, the <plist
// version="1.0"> root, every supported value element (dict/array/string/
// integer/real/bool/data/date), entity decoding, attribute handling, the
// full error catalog, the accessors (root kind, dict lookup, array get) and
// the canonical emitter including exact indentation and round-trip
// stability.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// element check below is routed through the streq/opt_* helpers.

module plist_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.plist;

const K_DICT: Int = 0;
const K_ARRAY: Int = 1;
const K_STRING: Int = 2;
const K_INT: Int = 3;
const K_REAL: Int = 4;
const K_BOOL: Int = 5;
const K_DATA: Int = 6;
const K_DATE: Int = 7;
const K_DOC: Int = 8;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Expected error text; false when the parse unexpectedly succeeded.
fn err_is(is_ok: Bool, err: Str, want: Str) -> Bool {
  if is_ok {
    return false;
  }
  return streq(err, want);
}

fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => {
      return v == want;
    },
    None => {
      return false;
    },
  }
  return false;
}

fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => {
      return false;
    },
    None => {
      return true;
    },
  }
  return true;
}

fn opt_node_is(o: Option[Int], want: Int) -> Bool {
  return opt_int_is(o, want);
}

fn opt_node_none(o: Option[Int]) -> Bool {
  return opt_int_none(o);
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => {
      return streq(v, want);
    },
    None => {
      return false;
    },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => {
      return false;
    },
    None => {
      return true;
    },
  }
  return true;
}

fn opt_bool_is(o: Option[Bool], want: Bool) -> Bool {
  match o {
    Some(v) => {
      return v == want;
    },
    None => {
      return false;
    },
  }
  return false;
}

fn opt_bool_none(o: Option[Bool]) -> Bool {
  match o {
    Some(_) => {
      return false;
    },
    None => {
      return true;
    },
  }
  return true;
}

// Parse `body` as the root value of a plist and expect Err("plist: ...").
fn value_err(body: Str, want: Str) -> Bool {
  let r = plist_parse("<plist version=\"1.0\">" + body + "</plist>");
  return err_is(r.is_ok, r.error, want);
}

fn bad_integer(body: Str) -> Bool {
  return value_err("<integer>" + body + "</integer>", "plist: bad integer");
}

fn bad_real(body: Str) -> Bool {
  return value_err("<real>" + body + "</real>", "plist: bad real");
}

fn bad_data(body: Str) -> Bool {
  return value_err("<data>" + body + "</data>", "plist: bad data");
}

fn bad_date(body: Str) -> Bool {
  return value_err("<date>" + body + "</date>", "plist: bad date");
}

fn bad_entity(body: Str) -> Bool {
  return value_err("<string>" + body + "</string>", "plist: bad entity");
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let r = plist_parse("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><string>hello &amp; goodbye</string></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    let t: Str = plist_text(&d, 1);
    if plist_node_count(&d) != 2 { ok = false; }
    if plist_root(&d) != 1 { ok = false; }
    if plist_root_kind(&d) != K_STRING { ok = false; }
    if plist_kind(&d, 0) != K_DOC { ok = false; }
    if plist_kind(&d, 1) != K_STRING { ok = false; }
    if !streq(t, "hello & goodbye") { ok = false; }
    if !opt_int_is(plist_parent(&d, 1), 0) { ok = false; }
    if !opt_int_is(plist_parent(&d, 0), -1) { ok = false; }
  }
  return assert(ok, "root string parses; declaration and DOCTYPE are skipped");
}

fn t2() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><dict><key>name</key><string>Ada</string><key>age</key><integer>36</integer></dict></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    let root = plist_root(&d);
    if plist_root_kind(&d) != K_DICT { ok = false; }
    if root != 1 { ok = false; }
    if plist_node_count(&d) != 4 { ok = false; }
    if plist_dict_count(&d, root) != 2 { ok = false; }
    if !opt_str_is(plist_dict_key(&d, root, 0), "name") { ok = false; }
    if !opt_str_is(plist_dict_key(&d, root, 1), "age") { ok = false; }
    if !opt_str_none(plist_dict_key(&d, root, 2)) { ok = false; }
    if !opt_node_is(plist_dict_get(&d, root, "name"), 2) { ok = false; }
    let nt: Str = plist_text(&d, 2);
    if !streq(nt, "Ada") { ok = false; }
    if !opt_node_is(plist_dict_get(&d, root, "age"), 3) { ok = false; }
    if !opt_int_is(plist_int_value(&d, 3), 36) { ok = false; }
    if !opt_node_none(plist_dict_get(&d, root, "missing")) { ok = false; }
    if !opt_node_none(plist_dict_get(&d, root, "Name")) { ok = false; }
    if !opt_node_none(plist_dict_get(&d, 2, "name")) { ok = false; }
    if plist_array_count(&d, root) != 0 { ok = false; }
  }
  return assert(ok, "dict parses; lookup, order and counts are exact");
}

fn t3() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><dict><key>tags</key><array><string>a</string><string>b</string></array><key>empty</key><dict/></dict></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    if plist_node_count(&d) != 6 { ok = false; }
    if !opt_node_is(plist_dict_get(&d, 1, "tags"), 2) { ok = false; }
    if plist_kind(&d, 2) != K_ARRAY { ok = false; }
    if plist_array_count(&d, 2) != 2 { ok = false; }
    if !opt_node_is(plist_array_get(&d, 2, 0), 3) { ok = false; }
    if !opt_node_is(plist_array_get(&d, 2, 1), 4) { ok = false; }
    if !opt_node_none(plist_array_get(&d, 2, 2)) { ok = false; }
    if !opt_int_is(plist_parent(&d, 2), 1) { ok = false; }
    if !opt_int_is(plist_parent(&d, 3), 2) { ok = false; }
    if !opt_int_is(plist_parent(&d, 4), 2) { ok = false; }
    if !opt_node_is(plist_dict_get(&d, 1, "empty"), 5) { ok = false; }
    if plist_kind(&d, 5) != K_DICT { ok = false; }
    if plist_dict_count(&d, 5) != 0 { ok = false; }
    if plist_node_count(&d) != 6 { ok = false; }
  }
  return assert(ok, "nested array and empty dict expose child ranges and parents");
}

fn t4() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><array><true/><false/></array></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    if plist_root_kind(&d) != K_ARRAY { ok = false; }
    if plist_array_count(&d, 1) != 2 { ok = false; }
    if plist_kind(&d, 2) != K_BOOL { ok = false; }
    if plist_kind(&d, 3) != K_BOOL { ok = false; }
    if !opt_bool_is(plist_bool_value(&d, 2), true) { ok = false; }
    if !opt_bool_is(plist_bool_value(&d, 3), false) { ok = false; }
    if !opt_bool_none(plist_bool_value(&d, 1)) { ok = false; }
    let t2: Str = plist_text(&d, 2);
    let t3: Str = plist_text(&d, 3);
    if !streq(t2, "true") { ok = false; }
    if !streq(t3, "false") { ok = false; }
    if !opt_int_none(plist_int_value(&d, 2)) { ok = false; }
  }
  return assert(ok, "true and false parse as BOOL nodes with true/false text");
}

fn t5() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><array><integer>0</integer><integer>-42</integer><integer>9223372036854775807</integer><integer>-9223372036854775808</integer><integer>007</integer><integer>-0</integer></array></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    let want_min = 0 - 9223372036854775807 - 1;
    if !opt_int_is(plist_int_value(&d, 2), 0) { ok = false; }
    if !opt_int_is(plist_int_value(&d, 3), -42) { ok = false; }
    if !opt_int_is(plist_int_value(&d, 4), 9223372036854775807) { ok = false; }
    if !opt_int_is(plist_int_value(&d, 5), want_min) { ok = false; }
    if !opt_int_is(plist_int_value(&d, 6), 7) { ok = false; }
    if !opt_int_is(plist_int_value(&d, 7), 0) { ok = false; }
    let canon = plist_text(&d, 6);
    let zero = plist_text(&d, 7);
    if !streq(canon, "7") { ok = false; }
    if !streq(zero, "0") { ok = false; }
  }
  return assert(ok, "integers are 64-bit bounds-checked and canonicalized");
}

fn t6() -> TestResult {
  var ok = bad_integer("12x");
  if !bad_integer("") { ok = false; }
  if !bad_integer("9223372036854775808") { ok = false; }
  if !bad_integer("-9223372036854775809") { ok = false; }
  if !bad_integer("+5") { ok = false; }
  if !bad_integer("1.0") { ok = false; }
  if !bad_integer("1 2") { ok = false; }
  if !bad_integer("0x10") { ok = false; }
  if !value_err("<integer/>", "plist: bad integer") { ok = false; }
  return assert(ok, "malformed and out-of-range integers are Err");
}

fn t7() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><array><real>3.14</real><real>-2.5e10</real><real>1E-3</real><real>42</real><real>0.0</real></array></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    if plist_kind(&d, 2) != K_REAL { ok = false; }
    let a: Str = plist_text(&d, 2);
    let b: Str = plist_text(&d, 3);
    let c: Str = plist_text(&d, 4);
    let e: Str = plist_text(&d, 5);
    if !streq(a, "3.14") { ok = false; }
    if !streq(b, "-2.5e10") { ok = false; }
    if !streq(c, "1E-3") { ok = false; }
    if !streq(e, "42") { ok = false; }
    if !opt_int_none(plist_int_value(&d, 2)) { ok = false; }
  }
  if !bad_real("abc") { ok = false; }
  if !bad_real(".5") { ok = false; }
  if !bad_real("1.") { ok = false; }
  if !bad_real("1e") { ok = false; }
  if !bad_real("+1.5") { ok = false; }
  if !bad_real("1.2.3") { ok = false; }
  if !bad_real("") { ok = false; }
  if !bad_real("1 2") { ok = false; }
  return assert(ok, "reals are validated text tokens kept verbatim");
}

fn t8() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><array><data>AAECAw==</data><data>\n\tQUJD\n\tREU=\n</data><data/></array></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    let a: Str = plist_text(&d, 2);
    let b: Str = plist_text(&d, 3);
    let c: Str = plist_text(&d, 4);
    if plist_kind(&d, 2) != K_DATA { ok = false; }
    if !streq(a, "AAECAw==") { ok = false; }
    if !streq(b, "QUJDREU=") { ok = false; }
    if !streq(c, "") { ok = false; }
  }
  if !bad_data("not base64!") { ok = false; }
  if !bad_data("AA=A") { ok = false; }
  if !bad_data("%%%") { ok = false; }
  return assert(ok, "data is whitespace-stripped base64 text pass-through");
}

fn t9() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><date>2026-09-25T12:34:56Z</date></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    if plist_kind(&d, 1) != K_DATE { ok = false; }
    let t: Str = plist_text(&d, 1);
    if !streq(t, "2026-09-25T12:34:56Z") { ok = false; }
  }
  if !bad_date("2026-13-25T12:34:56Z") { ok = false; }
  if !bad_date("2026-00-25T12:34:56Z") { ok = false; }
  if !bad_date("2026-09-25 12:34:56Z") { ok = false; }
  if !bad_date("2026-09-25T12:34:56") { ok = false; }
  if !bad_date("2026-09-25T24:00:00Z") { ok = false; }
  if !bad_date("2026-9-25T12:34:56Z") { ok = false; }
  if !bad_date("") { ok = false; }
  return assert(ok, "dates are shape-validated text pass-through");
}

fn t10() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><string>&amp;&lt;&gt;&quot;&apos;&#65;&#x42;&#X43;&#233;</string></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    let t: Str = plist_text(&d, 1);
    if !streq(t, "&<>\"'ABCé") { ok = false; }
    if t.len() != 10 { ok = false; }
  }
  let k = plist_parse("<plist version=\"1.0\"><dict><key>a&amp;b</key><string>x</string></dict></plist>");
  if !k.is_ok { ok = false; }
  if k.is_ok {
    let kd = k.value;
    if !opt_node_is(plist_dict_get(&kd, 1, "a&b"), 2) { ok = false; }
    let kt: Str = plist_text(&kd, 2);
    if !streq(kt, "x") { ok = false; }
  }
  return assert(ok, "named, decimal, hex and >=128 entities decode in text and keys");
}

fn t11() -> TestResult {
  var ok = bad_entity("&nope;");
  if !bad_entity("&") { ok = false; }
  if !bad_entity("&#;") { ok = false; }
  if !bad_entity("&#x;") { ok = false; }
  if !bad_entity("&#0;") { ok = false; }
  if !bad_entity("&#x110000;") { ok = false; }
  if !bad_entity("&#xZZ;") { ok = false; }
  if !bad_entity("&#65") { ok = false; }
  if !bad_entity("a & b") { ok = false; }
  return assert(ok, "unknown, malformed and out-of-range entities are Err");
}

fn t12() -> TestResult {
  var ok = value_err("<string>a</array>", "plist: mismatched tag");
  if !value_err("<dict><key>a</key><string>b</dict>", "plist: mismatched tag") { ok = false; }
  if !value_err("<string>a</plist>", "plist: mismatched tag") { ok = false; }
  if !value_err("<array><string>a</string></other>", "plist: mismatched tag") { ok = false; }
  return assert(ok, "closing tags must match the open element");
}

fn t13() -> TestResult {
  var ok = value_err("<foo/>", "plist: unknown tag");
  if !value_err("<data2>AA==</data2>", "plist: unknown tag") { ok = false; }
  if !value_err("<dict><foo/></dict>", "plist: unknown tag") { ok = false; }
  if !value_err("<array><widget/></array>", "plist: unknown tag") { ok = false; }
  let top = plist_parse("<dict/>");
  if !err_is(top.is_ok, top.error, "plist: unknown tag") { ok = false; }
  return assert(ok, "unsupported elements are Err(\"plist: unknown tag\")");
}

fn t14() -> TestResult {
  var ok = value_err("<key>a</key>", "plist: key outside dict");
  if !value_err("<array><key>a</key></array>", "plist: key outside dict") { ok = false; }
  if !value_err("<dict><key>a</key></dict>", "plist: odd dict element count") { ok = false; }
  if !value_err("<dict><string>v</string></dict>", "plist: odd dict element count") { ok = false; }
  if !value_err("<dict><key>a</key><key>b</key><string>c</string></dict>", "plist: odd dict element count") { ok = false; }
  if !value_err("<dict><key>a</key><string>b</string><key>c</key></dict>", "plist: odd dict element count") { ok = false; }
  return assert(ok, "key placement and dict key/value parity are enforced");
}

fn t15() -> TestResult {
  let empty = plist_parse("");
  var ok = err_is(empty.is_ok, empty.error, "plist: premature EOF");
  let a = plist_parse("   ");
  if !err_is(a.is_ok, a.error, "plist: premature EOF") { ok = false; }
  let b = plist_parse("<plist version=\"1.0\"");
  if !err_is(b.is_ok, b.error, "plist: premature EOF") { ok = false; }
  let c = plist_parse("<plist version=\"1.0\"><string>abc");
  if !err_is(c.is_ok, c.error, "plist: premature EOF") { ok = false; }
  let d = plist_parse("<plist version=\"1.0\"><string>a</string>");
  if !err_is(d.is_ok, d.error, "plist: premature EOF") { ok = false; }
  let e = plist_parse("<plist version=\"1.0\"><string>a</string></plist");
  if !err_is(e.is_ok, e.error, "plist: premature EOF") { ok = false; }
  let f = plist_parse("<plist version=\"1.0\"><!-- open");
  if !err_is(f.is_ok, f.error, "plist: premature EOF") { ok = false; }
  let g = plist_parse("<plist version=\"1.0\"><dict><key>a</key><string>b</string>");
  if !err_is(g.is_ok, g.error, "plist: premature EOF") { ok = false; }
  return assert(ok, "unterminated input reports premature EOF");
}

fn t16() -> TestResult {
  let lead = plist_parse("junk<plist version=\"1.0\"><string>a</string></plist>");
  var ok = err_is(lead.is_ok, lead.error, "plist: text outside elements");
  if !value_err("junk<string>a</string>", "plist: text outside elements") { ok = false; }
  if !value_err("<array>hello</array>", "plist: text outside elements") { ok = false; }
  if !value_err("<string>a</string>tail", "plist: text outside elements") { ok = false; }
  let inside = plist_parse("<plist version=\"1.0\"><dict><key>a</key>oops<string>b</string></dict></plist>");
  if !err_is(inside.is_ok, inside.error, "plist: text outside elements") { ok = false; }
  return assert(ok, "raw text is only legal inside text leaf elements");
}

fn t17() -> TestResult {
  let a = plist_parse("<plist version=1.0><string>a</string></plist>");
  var ok = err_is(a.is_ok, a.error, "plist: unquoted attribute");
  let b = plist_parse("<plist foo=\"bar\"><string>a</string></plist>");
  if !err_is(b.is_ok, b.error, "plist: unknown attribute") { ok = false; }
  let c = plist_parse("<plist version=\"1.0\" foo=\"bar\"><string>a</string></plist>");
  if !err_is(c.is_ok, c.error, "plist: unknown attribute") { ok = false; }
  let d = plist_parse("<plist><string>a</string></plist>");
  if !err_is(d.is_ok, d.error, "plist: missing version attribute") { ok = false; }
  let e = plist_parse("<plist version=\"2.0\"><string>a</string></plist>");
  if !err_is(e.is_ok, e.error, "plist: unsupported version") { ok = false; }
  let f = plist_parse("<plist  version = '1.0' ><string>a</string></plist>");
  if !f.is_ok { ok = false; }
  if f.is_ok {
    let fd = f.value;
    let ft: Str = plist_text(&fd, 1);
    if !streq(ft, "a") { ok = false; }
  }
  return assert(ok, "the version attribute is quoted, known and pinned to 1.0");
}

fn t18() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><dict><key>name</key><string>Ada &amp; Bob</string><key>nums</key><array><integer>1</integer><integer>-2</integer></array><key>ok</key><true/></dict></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    var want = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    want = want + "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n";
    want = want + "<plist version=\"1.0\">\n";
    want = want + "\t<dict>\n";
    want = want + "\t\t<key>name</key>\n";
    want = want + "\t\t<string>Ada &amp; Bob</string>\n";
    want = want + "\t\t<key>nums</key>\n";
    want = want + "\t\t<array>\n";
    want = want + "\t\t\t<integer>1</integer>\n";
    want = want + "\t\t\t<integer>-2</integer>\n";
    want = want + "\t\t</array>\n";
    want = want + "\t\t<key>ok</key>\n";
    want = want + "\t\t<true/>\n";
    want = want + "\t</dict>\n";
    want = want + "</plist>\n";
    let got = plist_emit(&d);
    if !streq(got, want) { ok = false; }
  }
  return assert(ok, "canonical emitter output is exact (tabs, escapes, order)");
}

fn t19() -> TestResult {
  let src = "<plist version=\"1.0\"><dict><key>s</key><string>a&lt;b</string><key>i</key><integer>-7</integer><key>r</key><real>2.5e-3</real><key>d</key><data>AAECAw==</data><key>dt</key><date>2026-09-25T00:00:00Z</date><key>b</key><false/><key>a</key><array><string>x</string><dict/></array></dict></plist>";
  let r1 = plist_parse(src);
  var ok = r1.is_ok;
  if r1.is_ok {
    let d1 = r1.value;
    let e1 = plist_emit(&d1);
    let r2 = plist_parse(e1);
    if !r2.is_ok { ok = false; }
    if r2.is_ok {
      let d2 = r2.value;
      let e2 = plist_emit(&d2);
      if !streq(e1, e2) { ok = false; }
      if plist_node_count(&d1) != plist_node_count(&d2) { ok = false; }
      let ns = plist_dict_get(&d2, 1, "s");
      match ns {
        Some(n) => {
          let t: Str = plist_text(&d2, n);
          if !streq(t, "a<b") { ok = false; }
        },
        None => {
          ok = false;
        },
      }
      let ni = plist_dict_get(&d2, 1, "i");
      match ni {
        Some(n) => {
          if !opt_int_is(plist_int_value(&d2, n), -7) { ok = false; }
        },
        None => {
          ok = false;
        },
      }
      let nb = plist_dict_get(&d2, 1, "b");
      match nb {
        Some(n) => {
          if !opt_bool_is(plist_bool_value(&d2, n), false) { ok = false; }
        },
        None => {
          ok = false;
        },
      }
      let na = plist_dict_get(&d2, 1, "a");
      match na {
        Some(n) => {
          if plist_array_count(&d2, n) != 2 { ok = false; }
          let item = plist_array_get(&d2, n, 0);
          match item {
            Some(it) => {
              if plist_kind(&d2, it) != K_STRING { ok = false; }
            },
            None => {
              ok = false;
            },
          }
        },
        None => {
          ok = false;
        },
      }
    }
  }
  return assert(ok, "parse -> emit -> parse is stable and lossless");
}

fn t20() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><string>x</string></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    if plist_kind(&d, -1) != -1 { ok = false; }
    if plist_kind(&d, 99) != -1 { ok = false; }
    if !streq(plist_text(&d, -1), "") { ok = false; }
    if !streq(plist_text(&d, 0), "") { ok = false; }
    if plist_dict_count(&d, 1) != 0 { ok = false; }
    if plist_array_count(&d, 1) != 0 { ok = false; }
    if !opt_node_none(plist_array_get(&d, 1, 0)) { ok = false; }
    if !opt_node_none(plist_dict_get(&d, 1, "k")) { ok = false; }
    if !opt_node_none(plist_dict_get(&d, 99, "k")) { ok = false; }
    if !opt_str_none(plist_dict_key(&d, 1, 0)) { ok = false; }
    if !opt_int_none(plist_parent(&d, -1)) { ok = false; }
    if !opt_int_is(plist_parent(&d, 1), 0) { ok = false; }
    if !opt_int_none(plist_int_value(&d, 1)) { ok = false; }
    if !opt_bool_none(plist_bool_value(&d, 1)) { ok = false; }
    if plist_node_count(&d) != 2 { ok = false; }
    if plist_emit(&d).len() == 0 { ok = false; }
  }
  return assert(ok, "accessors are safe and kind-strict out of range");
}

fn t21() -> TestResult {
  let r = plist_parse("<plist version=\"1.0\"><dict><key>a</key><array/><key>b</key><dict/><key>c</key><string/><key>d</key><data/><key>e</key><integer>0</integer></dict></plist>");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    if plist_dict_count(&d, 1) != 5 { ok = false; }
    if plist_array_count(&d, 2) != 0 { ok = false; }
    if plist_dict_count(&d, 3) != 0 { ok = false; }
    if !streq(plist_text(&d, 4), "") { ok = false; }
    if !streq(plist_text(&d, 5), "") { ok = false; }
    if !opt_int_is(plist_int_value(&d, 6), 0) { ok = false; }
    let out = plist_emit(&d);
    if !string.str_contains(out, "<array/>") { ok = false; }
    if !string.str_contains(out, "<dict/>") { ok = false; }
    if !string.str_contains(out, "<string></string>") { ok = false; }
    if !string.str_contains(out, "<data></data>") { ok = false; }
  }
  let t = plist_parse("<plist version=\"1.0\"><true></true></plist>");
  if !err_is(t.is_ok, t.error, "plist: malformed tag") { ok = false; }
  let bt = plist_parse("<plist version=\"1.0\"><true/></plist>");
  if !bt.is_ok { ok = false; }
  if bt.is_ok {
    let bd = bt.value;
    if !opt_bool_is(plist_bool_value(&bd, 1), true) { ok = false; }
  }
  let bf = plist_parse("<plist version=\"1.0\"><false/></plist>");
  if !bf.is_ok { ok = false; }
  if bf.is_ok {
    let bfd = bf.value;
    if !opt_bool_is(plist_bool_value(&bfd, 1), false) { ok = false; }
  }
  return assert(ok, "empty containers and strict self-closing booleans");
}

fn t22() -> TestResult {
  var ok = value_err("", "plist: missing root value");
  let self_close = plist_parse("<plist version=\"1.0\"/>");
  if !err_is(self_close.is_ok, self_close.error, "plist: missing root value") { ok = false; }
  if !value_err("<string>a</string><string>b</string>", "plist: multiple root values") { ok = false; }
  let a = plist_parse("<plist version=\"1.0\"><string>a</string></plist><x/>");
  if !err_is(a.is_ok, a.error, "plist: content after document root") { ok = false; }
  let b = plist_parse("<plist version=\"1.0\"><string>a</string></plist>tail");
  if !err_is(b.is_ok, b.error, "plist: content after document root") { ok = false; }
  return assert(ok, "document-level structure errors are precise");
}

fn main() -> Int {
  io.println("=== xiom.plist conformance tests ===");
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
    io.println("xiom.plist: all tests passed");
  } else {
    io.println("xiom.plist: tests failed");
  }
  return failed;
}
