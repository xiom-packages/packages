// XIOM -- xiom.pls conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.pls module against its
// documented PLS subset, decisions, error catalog and round-trip rules.
// Coverage: canonical documents, minimal documents, case-insensitive section
// header and keys, CRLF and a missing final newline, blank/whitespace lines
// and trimming, Length -1 vs 0, leading zeros, unknown keys in document
// order, duplicate last-wins, non-numeric/zero/huge indexes, missing FileN,
// bad lengths, lines without '=', empty keys, section-header errors, Version
// errors, NumberOfEntries bounds and last-wins, canonical emission, exact
// NumberOfEntries recomputation, parse -> emit -> parse round trips, empty
// documents and out-of-range sentinels.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq and every Vec element read binds
// a typed local first. Test functions are called directly from main (no
// indexed Vec[fn] dispatch, which miscompiles).

module pls_tests
use xiom.io; use xiom.test; use xiom.pls;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when the text fails to parse with an error message carrying `prefix`.
fn parse_err_prefix(text: Str, prefix: Str) -> Bool {
  let r = pls_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

// Deep equality over the observable playlist surface (entries plus unknown
// keys). `has_header` is intentionally not compared: emit always writes the
// header, so it normalizes to true after a round trip.
fn same_pls(a: &Pls, b: &Pls) -> Bool {
  if pls_entry_count(a) != pls_entry_count(b) { return false; }
  if pls_unknown_count(a) != pls_unknown_count(b) { return false; }
  var i = 1;
  while i <= pls_entry_count(a) {
    let fa: Str = pls_file(a, i);
    let fb: Str = pls_file(b, i);
    if !streq(fa, fb) { return false; }
    let ta: Str = pls_title(a, i);
    let tb: Str = pls_title(b, i);
    if !streq(ta, tb) { return false; }
    if pls_length(a, i) != pls_length(b, i) { return false; }
    i = i + 1;
  }
  var j = 0;
  while j < pls_unknown_count(a) {
    let ka: Str = pls_unknown_key(a, j);
    let kb: Str = pls_unknown_key(b, j);
    if !streq(ka, kb) { return false; }
    let va: Str = pls_unknown_value(a, j);
    let vb: Str = pls_unknown_value(b, j);
    if !streq(va, vb) { return false; }
    j = j + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = pls_parse("[playlist]\nVersion=2\nNumberOfEntries=2\nFile1=intro.mp3\nTitle1=Intro\nLength1=5\nFile2=sub/second.mp3\nTitle2=Second Track\nLength2=123\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_has_header(&p);
      if pls_entry_count(&p) != 2 { ok = false; }
      let f1: Str = pls_file(&p, 1);
      let t1: Str = pls_title(&p, 1);
      if !streq(f1, "intro.mp3") { ok = false; }
      if !streq(t1, "Intro") { ok = false; }
      if pls_length(&p, 1) != 5 { ok = false; }
      let f2: Str = pls_file(&p, 2);
      let t2: Str = pls_title(&p, 2);
      if !streq(f2, "sub/second.mp3") { ok = false; }
      if !streq(t2, "Second Track") { ok = false; }
      if pls_length(&p, 2) != 123 { ok = false; }
      if pls_unknown_count(&p) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical document: header, entries, 1-based accessors");
}

fn t2() -> TestResult {
  let r = pls_parse("File1=a.mp3\nFile2=b.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = !pls_has_header(&p);
      if pls_entry_count(&p) != 2 { ok = false; }
      let f1: Str = pls_file(&p, 1);
      let f2: Str = pls_file(&p, 2);
      let t1: Str = pls_title(&p, 1);
      if !streq(f1, "a.mp3") { ok = false; }
      if !streq(f2, "b.mp3") { ok = false; }
      if !streq(t1, "") { ok = false; }
      if pls_length(&p, 1) != -1 { ok = false; }
      if pls_length(&p, 2) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "minimal document: index infers count, metadata defaults to empty/-1");
}

fn t3() -> TestResult {
  let r = pls_parse("[PLAYLIST]\nvErSiOn=2\nnumberOFentries=1\nfIlE1=One.mp3\nTITLE1=One\nLENGTH1=9\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_has_header(&p);
      if pls_entry_count(&p) != 1 { ok = false; }
      let f: Str = pls_file(&p, 1);
      let t: Str = pls_title(&p, 1);
      if !streq(f, "One.mp3") { ok = false; }
      if !streq(t, "One") { ok = false; }
      if pls_length(&p, 1) != 9 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "section header, Version, NumberOfEntries and File/Title/Length keys are case-insensitive");
}

fn t4() -> TestResult {
  let r = pls_parse("[playlist]\r\nFile1=a.mp3\r\nTitle1=A\r\nLength1=4");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_has_header(&p);
      if pls_entry_count(&p) != 1 { ok = false; }
      let f: Str = pls_file(&p, 1);
      let t: Str = pls_title(&p, 1);
      if !streq(f, "a.mp3") { ok = false; }
      if !streq(t, "A") { ok = false; }
      if pls_length(&p, 1) != 4 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF line endings and a missing final newline parse");
}

fn t5() -> TestResult {
  let r = pls_parse("\n[playlist]\n\n  File1 = spaced path.mp3  \n\n\tTitle1\t=\tSoft Title  \n\nLength1 =\t 12 \n\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_has_header(&p);
      if pls_entry_count(&p) != 1 { ok = false; }
      let f: Str = pls_file(&p, 1);
      let t: Str = pls_title(&p, 1);
      if !streq(f, "spaced path.mp3") { ok = false; }
      if !streq(t, "Soft Title") { ok = false; }
      if pls_length(&p, 1) != 12 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "blank lines are skipped; keys, values and section lines are trimmed");
}

fn t6() -> TestResult {
  let r = pls_parse("File1=stream.mp3\nLength1=-1\nFile2=zero.mp3\nLength2=0\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_entry_count(&p) == 2;
      if pls_length(&p, 1) != -1 { ok = false; }
      if pls_length(&p, 2) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "Length=-1 (unknown/stream) and Length=0 (real zero) are distinct");
}

fn t7() -> TestResult {
  let r = pls_parse("File01=A1.mp3\nLength01=007\nNumberOfEntries=01\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_entry_count(&p) == 1;
      let f: Str = pls_file(&p, 1);
      if !streq(f, "A1.mp3") { ok = false; }
      if pls_length(&p, 1) != 7 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "leading zeros are accepted in indexes and numeric values");
}

fn t8() -> TestResult {
  let r = pls_parse("Comment=hello\nFile1=a.mp3\nX-Custom=1\nComment=again\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_unknown_count(&p) == 3;
      let k0: Str = pls_unknown_key(&p, 0);
      let v0: Str = pls_unknown_value(&p, 0);
      let k1: Str = pls_unknown_key(&p, 1);
      let v1: Str = pls_unknown_value(&p, 1);
      let k2: Str = pls_unknown_key(&p, 2);
      let v2: Str = pls_unknown_value(&p, 2);
      if !streq(k0, "Comment") { ok = false; }
      if !streq(v0, "hello") { ok = false; }
      if !streq(k1, "X-Custom") { ok = false; }
      if !streq(v1, "1") { ok = false; }
      if !streq(k2, "Comment") { ok = false; }
      if !streq(v2, "again") { ok = false; }
      if pls_entry_count(&p) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unknown keys survive verbatim in document order, duplicates included");
}

fn t9() -> TestResult {
  let r = pls_parse("File1=first.mp3\nFile1=second.mp3\nTitle1=t1\nTitle1=t2\nLength1=1\nLength1=2\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_entry_count(&p) == 1;
      let f: Str = pls_file(&p, 1);
      let t: Str = pls_title(&p, 1);
      if !streq(f, "second.mp3") { ok = false; }
      if !streq(t, "t2") { ok = false; }
      if pls_length(&p, 1) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate indexed keys: the last assignment wins");
}

fn t10() -> TestResult {
  var ok = parse_err_prefix("FileX=1\n", "pls: bad index in key: ");
  if !parse_err_prefix("File=1\n", "pls: bad index in key: ") { ok = false; }
  if !parse_err_prefix("Title1x=1\n", "pls: bad index in key: ") { ok = false; }
  if !parse_err_prefix("Length-1=1\n", "pls: bad index in key: ") { ok = false; }
  if !parse_err_prefix("lengthabc=1\n", "pls: bad index in key: ") { ok = false; }
  if !parse_err_prefix("File 1=1\n", "pls: bad index in key: ") { ok = false; }
  return assert(ok, "non-numeric indexes in file/title/length keys are Err");
}

fn t11() -> TestResult {
  var ok = parse_err_prefix("File0=x\n", "pls: bad index in key: ");
  if !parse_err_prefix("File1234567890123456789=x\n", "pls: bad index in key: ") { ok = false; }
  if !parse_err_prefix("File2000000=x\n", "pls: index out of range: ") { ok = false; }
  return assert(ok, "index 0, 19-digit indexes and indexes above the 1000000 cap are Err");
}

fn t12() -> TestResult {
  var ok = parse_err_prefix("NumberOfEntries=2\nFile1=a.mp3\n", "pls: missing File2");
  if !parse_err_prefix("File1=\n", "pls: missing File1") { ok = false; }
  if !parse_err_prefix("Title1=x\n", "pls: missing File1") { ok = false; }
  if !parse_err_prefix("NumberOfEntries=2\n", "pls: missing File1") { ok = false; }
  return assert(ok, "every entry needs a non-empty FileN; absent and empty are Err");
}

fn t13() -> TestResult {
  var ok = parse_err_prefix("Length1=abc\n", "pls: bad length in key Length1: ");
  if !parse_err_prefix("Length1=-2\n", "pls: bad length in key Length1: ") { ok = false; }
  if !parse_err_prefix("Length1=-0\n", "pls: bad length in key Length1: ") { ok = false; }
  if !parse_err_prefix("Length1=1.5\n", "pls: bad length in key Length1: ") { ok = false; }
  if !parse_err_prefix("Length1=+1\n", "pls: bad length in key Length1: ") { ok = false; }
  if !parse_err_prefix("Length1=\n", "pls: bad length in key Length1: ") { ok = false; }
  if !parse_err_prefix("Length1=1234567890123456789\n", "pls: bad length in key Length1: ") { ok = false; }
  return assert(ok, "bad Length values (alpha, < -1, float, signed, empty, 19 digits) are Err");
}

fn t14() -> TestResult {
  var ok = parse_err_prefix("File1=a.mp3\nplain text\n", "pls: missing '=' in line: ");
  if !parse_err_prefix("justakey", "pls: missing '=' in line: ") { ok = false; }
  if !parse_err_prefix("File1", "pls: missing '=' in line: ") { ok = false; }
  return assert(ok, "a non-blank, non-section line without '=' is Err");
}

fn t15() -> TestResult {
  var ok = parse_err_prefix("=value", "pls: empty key in line: ");
  if !parse_err_prefix("  =  ", "pls: empty key in line: ") { ok = false; }
  if !parse_err_prefix("File1=a\n = 1\n", "pls: empty key in line: ") { ok = false; }
  return assert(ok, "an empty or whitespace-only key is Err");
}

fn t16() -> TestResult {
  var ok = parse_err_prefix("[other]\n", "pls: unknown section: ");
  if !parse_err_prefix("[playlist", "pls: malformed section header: ") { ok = false; }
  if !parse_err_prefix("[]", "pls: malformed section header: ") { ok = false; }
  if !parse_err_prefix("[playlist]x", "pls: malformed section header: ") { ok = false; }
  let r = pls_parse("[PLAYLIST]\nFile1=a.mp3\n");
  match r {
    Ok(p) => { ok = pls_has_header(&p); },
    Err(_) => { ok = false; },
  }
  return assert(ok, "only a well-formed [playlist] section (case-insensitive) is accepted");
}

fn t17() -> TestResult {
  var ok = parse_err_prefix("Version=3\n", "pls: unsupported version: ");
  if !parse_err_prefix("Version=abc\n", "pls: bad version: ") { ok = false; }
  if !parse_err_prefix("Version=\n", "pls: bad version: ") { ok = false; }
  let r = pls_parse("Version=02\n");
  match r {
    Ok(p) => {
      if pls_entry_count(&p) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "Version must be 2; absent is allowed and leading zeros parse");
}

fn t18() -> TestResult {
  var ok = parse_err_prefix("File2=x\nNumberOfEntries=1\n", "pls: index out of range: File2");
  if !parse_err_prefix("NumberOfEntries=abc\n", "pls: bad NumberOfEntries: ") { ok = false; }
  if !parse_err_prefix("NumberOfEntries=-1\n", "pls: bad NumberOfEntries: ") { ok = false; }
  if !parse_err_prefix("NumberOfEntries=\n", "pls: bad NumberOfEntries: ") { ok = false; }
  if !parse_err_prefix("NumberOfEntries=1000001\n", "pls: too many entries: ") { ok = false; }
  let r1 = pls_parse("NumberOfEntries=0\n");
  match r1 {
    Ok(p0) => {
      if pls_entry_count(&p0) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = pls_parse("NumberOfEntries=1\nFile1=a\nNumberOfEntries=2\nFile2=b\n");
  match r2 {
    Ok(p2) => {
      if pls_entry_count(&p2) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "NumberOfEntries bounds indexes after the scan; duplicates last-win; 0 is empty");
}

fn t19() -> TestResult {
  let r = pls_parse("\r\n[playlist]\r\nVersion=2\r\nNumberOfEntries=1\r\nX-Note=hello\r\nFile1=a b.mp3\r\nTitle1=Song\r\nLength1=12\r\n");
  var ok = false;
  match r {
    Ok(p) => {
      let got = pls_emit(&p);
      let want = "[playlist]\nVersion=2\nNumberOfEntries=1\nFile1=a b.mp3\nTitle1=Song\nLength1=12\nX-Note=hello\n";
      ok = streq(got, want);
      if !pls_has_header(&p) { ok = false; }
      if pls_unknown_count(&p) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emit: LF layout, Version=2, entries then unknown keys");
}

fn t20() -> TestResult {
  let r1 = pls_parse("File1=a\nFile2=b\n");
  var ok = false;
  match r1 {
    Ok(p1) => {
      let got = pls_emit(&p1);
      let want = "[playlist]\nVersion=2\nNumberOfEntries=2\nFile1=a\nFile2=b\n";
      ok = streq(got, want);
    },
    Err(_) => { ok = false; },
  }
  let r2 = pls_parse("NumberOfEntries=0\n");
  match r2 {
    Ok(p2) => {
      let got2 = pls_emit(&p2);
      let want2 = "[playlist]\nVersion=2\nNumberOfEntries=0\n";
      if !streq(got2, want2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit recomputes NumberOfEntries from actual entries and omits empty Title/Length");
}

fn t21() -> TestResult {
  let r1 = pls_parse("[playlist]\nVersion=2\nNumberOfEntries=3\nFile1=one.mp3\nTitle1=One\nLength1=10\nFile2=two.mp3\nLength2=-1\nFile3=three.mp3\nTitle3=\nComment=hi\n");
  var ok = false;
  match r1 {
    Ok(p1) => {
      let text = pls_emit(&p1);
      let r2 = pls_parse(text);
      match r2 {
        Ok(p2) => {
          ok = same_pls(&p1, &p2);
          if pls_entry_count(&p2) != 3 { ok = false; }
          if pls_length(&p2, 2) != -1 { ok = false; }
          let t3: Str = pls_title(&p2, 3);
          if !streq(t3, "") { ok = false; }
          let uk: Str = pls_unknown_key(&p2, 0);
          let uv: Str = pls_unknown_value(&p2, 0);
          if !streq(uk, "Comment") { ok = false; }
          if !streq(uv, "hi") { ok = false; }
          let text2 = pls_emit(&p2);
          if !streq(text, text2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse round-trips entries and unknown keys; emit is idempotent");
}

fn t22() -> TestResult {
  var ok = false;
  let r1 = pls_parse("");
  match r1 {
    Ok(p) => {
      ok = pls_entry_count(&p) == 0;
      if pls_has_header(&p) { ok = false; }
      if pls_unknown_count(&p) != 0 { ok = false; }
      if !streq(pls_emit(&p), "[playlist]\nVersion=2\nNumberOfEntries=0\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = pls_parse("\n[playlist]\n\n");
  match r2 {
    Ok(p) => {
      if pls_entry_count(&p) != 0 { ok = false; }
      if !pls_has_header(&p) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and header-only documents are valid with zero entries");
}

fn t23() -> TestResult {
  let r = pls_parse("File1=a.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = pls_entry_count(&p) == 1;
      let f0: Str = pls_file(&p, 0);
      let f2: Str = pls_file(&p, 2);
      let fm: Str = pls_file(&p, -1);
      let t0: Str = pls_title(&p, 0);
      let t9: Str = pls_title(&p, 9);
      let uk: Str = pls_unknown_key(&p, 0);
      let uv: Str = pls_unknown_value(&p, 0);
      if !streq(f0, "") { ok = false; }
      if !streq(f2, "") { ok = false; }
      if !streq(fm, "") { ok = false; }
      if !streq(t0, "") { ok = false; }
      if !streq(t9, "") { ok = false; }
      if pls_length(&p, 0) != -1 { ok = false; }
      if pls_length(&p, 2) != -1 { ok = false; }
      if !streq(uk, "") { ok = false; }
      if !streq(uv, "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return documented sentinels");
}

fn main() -> Int {
  io.println("=== xiom.pls conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.pls: all tests passed");
  } else {
    io.println("xiom.pls: tests failed");
  }
  return failed;
}
