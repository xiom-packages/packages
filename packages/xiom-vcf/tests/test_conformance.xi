// XIOM -- xiom.vcf conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: minimal and full cards, property order, group/parameter capture,
// quoted parameters containing ":" and ";", value unescaping, escape
// round-trips, CR/LF normalization in escaping, folded continuations
// (space/tab/multi-line), LF/CR/lone-CR input and CRLF-only output, BOM
// tolerance, multi-card streams, stream round-trips, the full error catalog,
// card building from FN/N/ORG/TEL/EMAIL/ADR, composed N/ADR builders, empty
// values, colons inside values, tolerant unescaping, accessor bounds, and a
// parse -> write -> parse model round-trip.
//
// All Str equality goes through str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison), and every
// Vec[Str] element is read into an explicitly typed local first.

module vcf_tests
use xiom.io; use xiom.test; use xiom.vcf;
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

fn card_err(text: Str, prefix: Str) -> Bool {
  let r = vcf_parse_card(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

fn stream_err(text: Str, prefix: Str) -> Bool {
  let r = vcf_parse_stream(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

fn build_err(version: Str, formatted_name: Str, prefix: Str) -> Bool {
  let r = vcf_build_card(version, formatted_name, "", "", "", "", "");
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

fn count_byte(s: Str, ch: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < s.len() {
    if (((string.byte_at(s, i) as Int) & 0xFF)) == ch { n = n + 1; }
    i = i + 1;
  }
  return n;
}

// Longest physical line in bytes, excluding a CR that is part of CRLF.
fn max_line_len(s: Str) -> Int {
  var mx = 0;
  var start = 0;
  let n = s.len();
  var i = 0;
  while i < n {
    let b = ((string.byte_at(s, i) as Int) & 0xFF);
    if b == 10 {
      var len = i - start;
      if i > start && ((string.byte_at(s, i - 1) as Int) & 0xFF) == 13 { len = len - 1; }
      if len > mx { mx = len; }
      start = i + 1;
    }
    i = i + 1;
  }
  if n - start > mx { mx = n - start; }
  return mx;
}

fn t1() -> TestResult {
  var ok = false;
  let r = vcf_parse_card("BEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\n");
  match r {
    Ok(c) => {
      ok = streq(c.version, "3.0");
      if vcf_property_count(&c) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = vcf_parse_card("\r\n\r\nBEGIN:VCARD\r\nVERSION:4.0\r\nEND:VCARD\r\n");
  match r2 {
    Ok(c2) => {
      if !streq(c2.version, "4.0") { ok = false; }
      if vcf_property_count(&c2) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "minimal 3.0 and 4.0 cards parse; blank lines around are ignored");
}

fn t2() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ada Lovelace\r\nN:Lovelace;Ada;;;\r\nORG:Analytical Engines\r\nTEL:+44 20 7946 0958\r\nEMAIL:ada@example.com\r\nADR:;;12 St James Sq;London;Greater London;SW1Y 4LE;United Kingdom\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_card(text);
  match r {
    Ok(c) => {
      ok = streq(c.version, "3.0");
      if vcf_property_count(&c) != 6 { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "fn"), "Ada Lovelace") { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "FN"), "Ada Lovelace") { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "n"), "Lovelace;Ada;;;") { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "org"), "Analytical Engines") { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "tel"), "+44 20 7946 0958") { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "email"), "ada@example.com") { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "adr"), ";;12 St James Sq;London;Greater London;SW1Y 4LE;United Kingdom") { ok = false; }
      let p1 = vcf_property(&c, 1);
      if !streq(p1.name, "N") { ok = false; }
      let p0 = vcf_property(&c, 0);
      if !streq(p0.name, "FN") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a full card yields all six fields in document order with case-insensitive lookup");
}

fn t3() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:4.0\r\nitem1.TEL;TYPE=WORK,VOICE:+1-555-0100\r\nitem2.EMAIL;PREF=1:jane@example.com\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_card(text);
  match r {
    Ok(c) => {
      ok = vcf_property_count(&c) == 2;
      let p0 = vcf_property(&c, 0);
      if !streq(p0.group, "item1") { ok = false; }
      if !streq(p0.name, "TEL") { ok = false; }
      if !streq(p0.params, "TYPE=WORK,VOICE") { ok = false; }
      if !streq(p0.value, "+1-555-0100") { ok = false; }
      if !opt_str_is(vcf_param_value(&c, 0, "TYPE"), "WORK") { ok = false; }
      if !opt_str_is(vcf_param_value(&c, 0, "type"), "WORK") { ok = false; }
      if !opt_str_none(vcf_param_value(&c, 0, "PREF")) { ok = false; }
      let p1 = vcf_property(&c, 1);
      if !streq(p1.group, "item2") { ok = false; }
      if !streq(p1.params, "PREF=1") { ok = false; }
      if !opt_str_is(vcf_param_value(&c, 1, "PREF"), "1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "groups and parameters are captured; parameter lookup takes the first list value");
}

fn t4() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:4.0\r\nTEL;TYPE=\"a:b;c\";X=1:123\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_card(text);
  match r {
    Ok(c) => {
      let p = vcf_property(&c, 0);
      ok = streq(p.params, "TYPE=\"a:b;c\";X=1");
      if !streq(p.value, "123") { ok = false; }
      if !opt_str_is(vcf_param_value(&c, 0, "TYPE"), "a:b;c") { ok = false; }
      if !opt_str_is(vcf_param_value(&c, 0, "x"), "1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a quoted parameter may contain ':' and ';' and loses its quotes");
}

fn t5() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ren\\,e\\; \\\\ \\n\r\nNOTE:a\\Nb\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_card(text);
  match r {
    Ok(c) => {
      ok = opt_str_is(vcf_prop_value(&c, "fn"), "Ren,e; \\ \n");
      if !opt_str_is(vcf_prop_value(&c, "note"), "a\nb") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "escaped commas, semicolons, backslashes and line breaks are decoded");
}

fn t6() -> TestResult {
  let raw = "a,b;c\\d\ne";
  let esc = vcf_escape(raw);
  var ok = streq(esc, "a\\,b\\;c\\\\d\\ne");
  if !streq(vcf_unescape(esc), raw) { ok = false; }
  if !streq(vcf_escape("x\r\ny"), "x\\ny") { ok = false; }
  if !streq(vcf_escape("x\ry"), "x\\ny") { ok = false; }
  let tricky = "caf\u{00E9}, ; \\" + "\n";
  if !streq(vcf_unescape(vcf_escape(tricky)), tricky) { ok = false; }
  return assert(ok, "vcf_escape/vcf_unescape round-trip and CRLF/CR collapse to one \\n");
}

fn t7() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:AAAA\r\n BBBB\r\n\tCCCC\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_card(text);
  match r {
    Ok(c) => { ok = opt_str_is(vcf_prop_value(&c, "fn"), "AAAABBBBCCCC"); },
    Err(_) => { ok = false; },
  }
  let text2 = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:one \r\n two\r\nEND:VCARD\r\n";
  match vcf_parse_card(text2) {
    Ok(c2) => { if !opt_str_is(vcf_prop_value(&c2, "fn"), "one two") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "space and tab continuations unfold by removing exactly one leading whitespace byte");
}

fn t8() -> TestResult {
  let lf = vcf_parse_card("BEGIN:VCARD\nVERSION:3.0\nFN:LF Card\nEND:VCARD\n");
  let cr = vcf_parse_card("BEGIN:VCARD\rVERSION:3.0\rFN:CR Card\rEND:VCARD\r");
  let mixed = vcf_parse_card("BEGIN:VCARD\r\nVERSION:3.0\nFN:Mixed Card\rEND:VCARD\r\n");
  var ok = false;
  match lf {
    Ok(c) => { ok = opt_str_is(vcf_prop_value(&c, "fn"), "LF Card"); },
    Err(_) => { ok = false; },
  }
  match cr {
    Ok(c) => { if !opt_str_is(vcf_prop_value(&c, "fn"), "CR Card") { ok = false; } },
    Err(_) => { ok = false; },
  }
  match mixed {
    Ok(c) => { if !opt_str_is(vcf_prop_value(&c, "fn"), "Mixed Card") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "LF, lone CR and mixed terminators all parse");
}

fn t9() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\n\r\nBEGIN:VCARD\r\nVERSION:4.0\r\nFN:B\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:3.0\r\nFN:C1\r\nFN:C2\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_stream(text);
  match r {
    Ok(s) => {
      ok = vcf_stream_count(&s) == 3;
      if !streq(vcf_stream_version(&s, 0), "3.0") { ok = false; }
      if !streq(vcf_stream_version(&s, 1), "4.0") { ok = false; }
      if !streq(vcf_stream_version(&s, 2), "3.0") { ok = false; }
      if vcf_stream_property_count(&s, 0) != 0 { ok = false; }
      if vcf_stream_property_count(&s, 1) != 1 { ok = false; }
      if vcf_stream_property_count(&s, 2) != 2 { ok = false; }
      let p20 = vcf_stream_property(&s, 2, 0);
      if !streq(p20.name, "FN") { ok = false; }
      if !streq(p20.value, "C1") { ok = false; }
      let p21 = vcf_stream_property(&s, 2, 1);
      if !streq(p21.value, "C2") { ok = false; }
      let pmiss = vcf_stream_property(&s, 3, 0);
      if !streq(pmiss.name, "") { ok = false; }
      if !streq(vcf_stream_version(&s, 3), "") { ok = false; }
      if vcf_stream_property_count(&s, 3) != 0 { ok = false; }
      let pneg = vcf_stream_property(&s, 0, -1);
      if !streq(pneg.name, "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a three-card stream is counted, versioned and indexed per card");
}

fn t10() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:One\r\nTEL;TYPE=HOME:1\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:4.0\r\nFN:Two\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_stream(text);
  match r {
    Ok(s) => {
      let out = vcf_write_stream(&s);
      match vcf_parse_stream(out) {
        Ok(s2) => {
          ok = vcf_stream_count(&s2) == vcf_stream_count(&s);
          if !streq(vcf_stream_version(&s2, 0), vcf_stream_version(&s, 0)) { ok = false; }
          if !streq(vcf_stream_version(&s2, 1), vcf_stream_version(&s, 1)) { ok = false; }
          if vcf_stream_property_count(&s2, 0) != vcf_stream_property_count(&s, 0) { ok = false; }
          if vcf_stream_property_count(&s2, 1) != vcf_stream_property_count(&s, 1) { ok = false; }
          let a0 = vcf_stream_property(&s, 0, 0);
          let b0 = vcf_stream_property(&s2, 0, 0);
          if !streq(a0.value, b0.value) { ok = false; }
          if !streq(a0.name, b0.name) { ok = false; }
          let a1 = vcf_stream_property(&s, 0, 1);
          let b1 = vcf_stream_property(&s2, 0, 1);
          if !streq(a1.value, b1.value) { ok = false; }
          if !streq(a1.params, b1.params) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "stream write -> parse round-trips cards, versions and properties");
}

fn t11() -> TestResult {
  var ok = card_err("", "vcf: empty input");
  if !card_err("\r\n\r\n", "vcf: empty input") { ok = false; }
  if !card_err("garbage", "vcf: malformed content line: garbage") { ok = false; }
  if !card_err("FN:x\r\n", "vcf: expected BEGIN:VCARD, got: FN:x") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\n", "vcf: missing END:VCARD") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nVERSION:3.0\r\nBEGIN:VCARD\r\nEND:VCARD\r\n", "vcf: nested BEGIN:VCARD") { ok = false; }
  if !stream_err("", "vcf: empty input") { ok = false; }
  if !stream_err("junk\r\n", "vcf: malformed content line: junk") { ok = false; }
  return assert(ok, "empty input, junk input, missing END and nested BEGIN are Err");
}

fn t12() -> TestResult {
  var ok = card_err("BEGIN:VCARD\r\nEND:VCARD\r\n", "vcf: missing VERSION");
  if !card_err("BEGIN:VCARD\r\nFN:x\r\nEND:VCARD\r\n", "vcf: missing VERSION") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nFN:x\r\nVERSION:3.0\r\nEND:VCARD\r\n", "vcf: missing VERSION") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nVERSION:2.1\r\nEND:VCARD\r\n", "vcf: unsupported version: 2.1") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nVERSION:4.1\r\nEND:VCARD\r\n", "vcf: unsupported version: 4.1") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nVERSION:3.0\r\nVERSION:3.0\r\nEND:VCARD\r\n", "vcf: duplicate VERSION") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\nVERSION:4.0\r\nEND:VCARD\r\n", "vcf: duplicate VERSION") { ok = false; }
  return assert(ok, "VERSION is mandatory, unique, before any property and one of 3.0/4.0");
}

fn t13() -> TestResult {
  var ok = card_err("BEGIN:VCARD\r\nVERSION:3.0\r\nNOT A LINE\r\nEND:VCARD\r\n", "vcf: malformed content line: NOT A LINE");
  if !card_err("BEGIN:VCARD\r\nVERSION:3.0\r\n:v\r\nEND:VCARD\r\n", "vcf: malformed content line: :v") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nVERSION:3.0\r\nitem1.:v\r\nEND:VCARD\r\n", "vcf: malformed content line: item1.:v") { ok = false; }
  if !card_err("BEGIN:VCARD\r\nVERSION:3.0\r\nTEL;TYPE=\"oops:1\r\nEND:VCARD\r\n", "vcf: malformed content line: TEL;TYPE=\"oops:1") { ok = false; }
  let two = "BEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\n";
  if !card_err(two, "vcf: unexpected content after END:VCARD: BEGIN:VCARD") { ok = false; }
  match vcf_parse_stream(two) {
    Ok(s) => { if vcf_stream_count(&s) != 2 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "malformed lines are Err; parse_card rejects a second card that parse_stream accepts");
}

fn t14() -> TestResult {
  var ok = false;
  let r = vcf_build_card("4.0", "Ada Lovelace", vcf_build_n("Lovelace", "Ada", "", "", ""), "Analytical Engines", "+44 20 7946 0958", "ada@example.com", vcf_build_adr("", "", "12 St James Sq", "London", "Greater London", "SW1Y 4LE", "United Kingdom"));
  match r {
    Ok(text) => {
      ok = string.str_starts_with(text, "BEGIN:VCARD\r\n");
      if !string.str_ends_with(text, "END:VCARD\r\n") { ok = false; }
      if count_byte(text, 10) != count_byte(text, 13) { ok = false; }
      match vcf_parse_card(text) {
        Ok(c) => {
          if !streq(c.version, "4.0") { ok = false; }
          if vcf_property_count(&c) != 6 { ok = false; }
          if !opt_str_is(vcf_prop_value(&c, "fn"), "Ada Lovelace") { ok = false; }
          if !opt_str_is(vcf_prop_value(&c, "n"), "Lovelace;Ada;;;") { ok = false; }
          if !opt_str_is(vcf_prop_value(&c, "org"), "Analytical Engines") { ok = false; }
          if !opt_str_is(vcf_prop_value(&c, "tel"), "+44 20 7946 0958") { ok = false; }
          if !opt_str_is(vcf_prop_value(&c, "email"), "ada@example.com") { ok = false; }
          if !opt_str_is(vcf_prop_value(&c, "adr"), ";;12 St James Sq;London;Greater London;SW1Y 4LE;United Kingdom") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "build_card emits CRLF text from FN/N/ORG/TEL/EMAIL/ADR that parses back");
}

fn t15() -> TestResult {
  var ok = build_err("2.1", "x", "vcf: unsupported version: 2.1");
  if !build_err("4.1", "x", "vcf: unsupported version: 4.1") { ok = false; }
  if !build_err("", "x", "vcf: unsupported version: ") { ok = false; }
  if !build_err("4.0", "", "vcf: FN is required") { ok = false; }
  if !build_err("3.0", "", "vcf: FN is required") { ok = false; }
  return assert(ok, "build_card rejects unsupported versions and an empty FN");
}

fn t16() -> TestResult {
  var ok = false;
  let r = vcf_build_card("3.0", "Only Name", "", "", "", "", "");
  match r {
    Ok(text) => {
      ok = count_byte(text, 10) == count_byte(text, 13);
      match vcf_parse_card(text) {
        Ok(c) => {
          if vcf_property_count(&c) != 1 { ok = false; }
          if !opt_str_is(vcf_prop_value(&c, "fn"), "Only Name") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  var long = "";
  var i = 0;
  while i < 200 {
    long = long + "y";
    i = i + 1;
  }
  let r2 = vcf_build_card("3.0", long, "", "", "", "", "");
  match r2 {
    Ok(text2) => {
      if max_line_len(text2) > 75 { ok = false; }
      if count_byte(text2, 10) != count_byte(text2, 13) { ok = false; }
      if count_byte(text2, 10) < 4 { ok = false; }
      match vcf_parse_card(text2) {
        Ok(c2) => { if !opt_str_is(vcf_prop_value(&c2, "fn"), long) { ok = false; } },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty optional fields are omitted; a 200-byte FN folds to 75-byte CRLF lines and reparses");
}

fn t17() -> TestResult {
  let n = vcf_build_n("Doe", "John,Q", "Jr\\", "", "");
  var ok = streq(n, "Doe;John\\,Q;Jr\\\\;;");
  let adr = vcf_build_adr("Box 1", "", "1 Main St, Apt 2", "Town", "Region", "12345", "Country");
  if !streq(adr, "Box 1;;1 Main St\\, Apt 2;Town;Region;12345;Country") { ok = false; }
  if !streq(vcf_escape_component("a;b,c\\d"), "a;b\\,c\\\\d") { ok = false; }
  let r = vcf_build_card("3.0", "Jane", n, "", "", "", adr);
  match r {
    Ok(text) => {
      match vcf_parse_card(text) {
        Ok(c) => {
          if !opt_str_is(vcf_prop_value(&c, "n"), "Doe;John,Q;Jr\\;;") { ok = false; }
          if !opt_str_is(vcf_prop_value(&c, "adr"), "Box 1;;1 Main St, Apt 2;Town;Region;12345;Country") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "build_n/build_adr escape components (not ';') and compose with build_card");
}

fn t18() -> TestResult {
  var ok = false;
  let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nX:\r\nTEL;:1\r\nNOTE:   \r\nEND:VCARD\r\n";
  let r = vcf_parse_card(text);
  match r {
    Ok(c) => {
      ok = vcf_property_count(&c) == 3;
      if !opt_str_is(vcf_prop_value(&c, "x"), "") { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "tel"), "1") { ok = false; }
      let p1 = vcf_property(&c, 1);
      if !streq(p1.params, "") { ok = false; }
      if !opt_str_none(vcf_param_value(&c, 1, "TYPE")) { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "note"), "   ") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty values and empty parameter sections are tolerated and preserved");
}

fn t19() -> TestResult {
  var ok = false;
  let text = "BEGIN:VCARD\r\nVERSION:4.0\r\nNOTE:a:b:c\r\nURL:https://example.com/p?q=1:2\r\nEND:VCARD\r\n";
  let r = vcf_parse_card(text);
  match r {
    Ok(c) => {
      ok = opt_str_is(vcf_prop_value(&c, "note"), "a:b:c");
      if !opt_str_is(vcf_prop_value(&c, "url"), "https://example.com/p?q=1:2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "colons after the first one stay in the value");
}

fn t20() -> TestResult {
  var ok = streq(vcf_unescape("a\\qb"), "aqb");
  if !streq(vcf_unescape("tail\\"), "tail\\") { ok = false; }
  if !streq(vcf_unescape("a\\Nb"), "a\nb") { ok = false; }
  if !streq(vcf_unescape("\\\\"), "\\") { ok = false; }
  if !streq(vcf_unescape("plain"), "plain") { ok = false; }
  return assert(ok, "unknown escapes drop the backslash; a trailing backslash survives");
}

fn t21() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nTEL:111\r\nFN:First\r\nTEL:222\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_card(text);
  match r {
    Ok(c) => {
      ok = vcf_prop_index(&c, "tel") == 0;
      if vcf_prop_index(&c, "TEL") != 0 { ok = false; }
      if vcf_prop_index(&c, "email") != -1 { ok = false; }
      let all = vcf_props_all(&c, "TEL");
      if all.len() != 2 { ok = false; }
      if !str_at(&all, 0, "111") { ok = false; }
      if !str_at(&all, 1, "222") { ok = false; }
      if !opt_str_is(vcf_prop_value(&c, "tel"), "111") { ok = false; }
      if !opt_str_none(vcf_prop_value(&c, "email")) { ok = false; }
      if vcf_props_all(&c, "email").len() != 0 { ok = false; }
      let pmiss = vcf_property(&c, 99);
      if !streq(pmiss.name, "") { ok = false; }
      let pneg = vcf_property(&c, -1);
      if !streq(pneg.name, "") { ok = false; }
      let p0 = vcf_property(&c, 0);
      if !streq(p0.value, "111") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "property accessors return first/all values and empty properties out of range");
}

fn t22() -> TestResult {
  var ok = false;
  let r = vcf_parse_card("\u{FEFF}BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Bom\r\nEND:VCARD\r\n");
  match r {
    Ok(c) => { ok = opt_str_is(vcf_prop_value(&c, "fn"), "Bom"); },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a UTF-8 byte-order mark on the first line is ignored");
}

fn t23() -> TestResult {
  var long = "";
  var i = 0;
  while i < 100 {
    long = long + "z";
    i = i + 1;
  }
  let built = vcf_build_card("4.0", long, "", "", "tel:123", "", "");
  var ok = false;
  match built {
    Ok(text) => {
      match vcf_parse_card(text) {
        Ok(c) => {
          let written = vcf_write(&c);
          ok = max_line_len(written) <= 75;
          if count_byte(written, 10) != count_byte(written, 13) { ok = false; }
          match vcf_parse_card(written) {
            Ok(c2) => {
              if !opt_str_is(vcf_prop_value(&c2, "fn"), long) { ok = false; }
              if !opt_str_is(vcf_prop_value(&c2, "tel"), "tel:123") { ok = false; }
            },
            Err(_) => { ok = false; },
          }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "write folds at 75 bytes, emits CRLF only, and the folded text reparses");
}

fn t24() -> TestResult {
  let text = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ren\\,e\\; \\\\ \\n\r\nitem1.TEL;TYPE=WORK,VOICE:+1-555\r\nN:Lovelace;Ada;;;\r\nADR:;;12 St James Sq;London;;SW1Y;UK\r\nNOTE:line1\\nline2\r\nEND:VCARD\r\n";
  var ok = false;
  let r = vcf_parse_card(text);
  match r {
    Ok(c1) => {
      let written = vcf_write(&c1);
      match vcf_parse_card(written) {
        Ok(c2) => {
          ok = streq(c1.version, c2.version);
          if vcf_property_count(&c1) != vcf_property_count(&c2) { ok = false; }
          var i = 0;
          while i < vcf_property_count(&c1) {
            let p1 = vcf_property(&c1, i);
            let p2 = vcf_property(&c2, i);
            if !streq(p1.name, p2.name) { ok = false; }
            if !streq(p1.group, p2.group) { ok = false; }
            if !streq(p1.params, p2.params) { ok = false; }
            if !streq(p1.value, p2.value) { ok = false; }
            i = i + 1;
          }
          let p0 = vcf_property(&c2, 0);
          if !streq(p0.value, "Ren,e; \\ \n") { ok = false; }
          let p3 = vcf_property(&c2, 3);
          if !streq(p3.value, ";;12 St James Sq;London;;SW1Y;UK") { ok = false; }
          let p4 = vcf_property(&c2, 4);
          if !streq(p4.value, "line1\nline2") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> write -> parse preserves version, names, groups, params and values");
}

fn main() -> Int {
  io.println("=== xiom.vcf conformance tests ===");
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
    io.println("xiom.vcf: all tests passed");
  } else {
    io.println("xiom.vcf: tests failed");
  }
  return failed;
}
