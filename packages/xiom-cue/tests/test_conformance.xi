// XIOM -- xiom.cue conformance tests (22 checks)
// Greenfield package: prove the pure-XIOM xiom.cue module against its
// documented CUE subset, error catalog and round-trip rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: full sheets, CRLF and indentation, bare/quoted values, doubled
// quotes and literal backslashes, boundary numbers and times, every error in
// the catalog (track number, track type, index number, index/gap time shape,
// second and frame ranges, missing INDEX 01, unterminated quote, trailing
// text, unknown keyword, keyword position, stray text, FILE/CATALOG/ISRC
// shapes), canonical emission, round trips, multi-FILE association,
// out-of-range accessor sentinels, REM pass-through and empty documents.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq and every Vec element read binds
// a typed local first. Test functions are called directly from main (no
// indexed Vec[fn] dispatch, which miscompiles).

module cue_tests
use xiom.io; use xiom.test; use xiom.cue;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `text` fails to parse with exactly the message `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = cue_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `text` fails to parse with an error message starting with
// `prefix`.
fn parse_err_prefix(text: Str, prefix: Str) -> Bool {
  let r = cue_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

// Deep equality over the whole observable element surface.
fn same_cue(a: &Cue, b: &Cue) -> Bool {
  if cue_element_count(a) != cue_element_count(b) { return false; }
  var i = 0;
  while i < cue_element_count(a) {
    if cue_element_kind(a, i) != cue_element_kind(b, i) { return false; }
    if cue_element_num(a, i) != cue_element_num(b, i) { return false; }
    if cue_element_min(a, i) != cue_element_min(b, i) { return false; }
    if cue_element_sec(a, i) != cue_element_sec(b, i) { return false; }
    if cue_element_frame(a, i) != cue_element_frame(b, i) { return false; }
    if cue_element_quoted(a, i) != cue_element_quoted(b, i) { return false; }
    if cue_element_file(a, i) != cue_element_file(b, i) { return false; }
    if cue_element_track(a, i) != cue_element_track(b, i) { return false; }
    let ta: Str = cue_element_text(a, i);
    let tb: Str = cue_element_text(b, i);
    if !streq(ta, tb) { return false; }
    let t2a: Str = cue_element_text2(a, i);
    let t2b: Str = cue_element_text2(b, i);
    if !streq(t2a, t2b) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = cue_parse("REM GENRE \"Jazz\"\nREM DATE 1994\nPERFORMER \"John Doe\"\nTITLE \"Album Title\"\nFILE \"album.wav\" WAVE\n  TRACK 01 AUDIO\n    TITLE \"Track One\"\n    PERFORMER \"John Doe\"\n    INDEX 01 00:00:00\n  TRACK 02 AUDIO\n    TITLE \"Track Two\"\n    PERFORMER \"Jane Roe\"\n    INDEX 00 04:32:00\n    INDEX 01 04:34:12\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 14;
      if !streq(cue_element_text(&c, 0), "GENRE \"Jazz\"") { ok = false; }
      if !streq(cue_element_text(&c, 1), "DATE 1994") { ok = false; }
      if cue_element_kind(&c, 2) != EK_PERFORMER { ok = false; }
      if cue_element_kind(&c, 3) != EK_TITLE { ok = false; }
      if cue_element_kind(&c, 4) != EK_FILE { ok = false; }
      if cue_element_kind(&c, 5) != EK_TRACK { ok = false; }
      if cue_element_kind(&c, 8) != EK_INDEX { ok = false; }
      if cue_element_kind_count(&c, EK_REM) != 2 { ok = false; }
      if cue_file_count(&c) != 1 { ok = false; }
      if !streq(cue_file_name(&c, 0), "album.wav") { ok = false; }
      if !streq(cue_file_type(&c, 0), "WAVE") { ok = false; }
      if cue_file_element(&c, 0) != 4 { ok = false; }
      if cue_track_count(&c) != 2 { ok = false; }
      if cue_track_number(&c, 0) != 1 { ok = false; }
      if cue_track_number(&c, 1) != 2 { ok = false; }
      if !streq(cue_track_type(&c, 0), "AUDIO") { ok = false; }
      if cue_track_element(&c, 1) != 9 { ok = false; }
      if cue_track_file(&c, 1) != 0 { ok = false; }
      if cue_index_count(&c) != 3 { ok = false; }
      if cue_index_number(&c, 1) != 0 { ok = false; }
      if cue_index_min(&c, 1) != 4 { ok = false; }
      if cue_index_sec(&c, 1) != 32 { ok = false; }
      if cue_index_frame(&c, 1) != 0 { ok = false; }
      if cue_index_frames(&c, 1) != 20400 { ok = false; }
      if cue_index_number(&c, 2) != 1 { ok = false; }
      if cue_index_min(&c, 2) != 4 { ok = false; }
      if cue_index_sec(&c, 2) != 34 { ok = false; }
      if cue_index_frame(&c, 2) != 12 { ok = false; }
      if cue_index_frames(&c, 2) != 20562 { ok = false; }
      if cue_index_track(&c, 0) != 0 { ok = false; }
      if cue_index_track(&c, 1) != 1 { ok = false; }
      if cue_track_index_count(&c, 0) != 1 { ok = false; }
      if cue_track_index_count(&c, 1) != 2 { ok = false; }
      if cue_track_index(&c, 1, 0) != 1 { ok = false; }
      if cue_track_index(&c, 1, 1) != 2 { ok = false; }
      if cue_track_index(&c, 1, 2) != -1 { ok = false; }
      if !cue_track_has_index01(&c, 0) { ok = false; }
      if !cue_track_has_index01(&c, 1) { ok = false; }
      if cue_element_track(&c, 2) != -1 { ok = false; }
      if cue_element_track(&c, 6) != 0 { ok = false; }
      if cue_element_track(&c, 12) != 1 { ok = false; }
      if cue_element_file(&c, 0) != -1 { ok = false; }
      if cue_element_file(&c, 4) != 0 { ok = false; }
      if !cue_element_quoted(&c, 2) { ok = false; }
      if cue_element_quoted(&c, 0) { ok = false; }
      if !streq(cue_element_text(&c, 6), "Track One") { ok = false; }
      if !streq(cue_element_text2(&c, 5), "AUDIO") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full sheet: element stream, files, tracks, indices");
}

fn t2() -> TestResult {
  let r = cue_parse("\r\nREM GENRE \"Jazz\"\r\n\r\nFILE \"album.wav\" WAVE\r\n  TRACK 01 AUDIO\r\n\tTITLE \"One\"\r\n    INDEX 01 00:00:00\r\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 5;
      if !streq(cue_element_text(&c, 0), "GENRE \"Jazz\"") { ok = false; }
      if !streq(cue_file_name(&c, 0), "album.wav") { ok = false; }
      if cue_track_number(&c, 0) != 1 { ok = false; }
      if !streq(cue_element_text(&c, 3), "One") { ok = false; }
      if cue_index_min(&c, 0) != 0 { ok = false; }
      if cue_index_sec(&c, 0) != 0 { ok = false; }
      if cue_index_frame(&c, 0) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF, indentation and blank lines are normalized");
}

fn t3() -> TestResult {
  let r = cue_parse("PERFORMER John Doe\nTITLE \"\"\nFILE \"a.wav\" WAVE\nTRACK 01 AUDIO\nTITLE Track One\nSONGWRITER A. Writer\nINDEX 01 00:00:00\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 7;
      if !streq(cue_element_text(&c, 0), "John Doe") { ok = false; }
      if cue_element_quoted(&c, 0) { ok = false; }
      if cue_element_kind(&c, 1) != EK_TITLE { ok = false; }
      if !streq(cue_element_text(&c, 1), "") { ok = false; }
      if !cue_element_quoted(&c, 1) { ok = false; }
      if cue_element_kind(&c, 4) != EK_TITLE { ok = false; }
      if !streq(cue_element_text(&c, 4), "Track One") { ok = false; }
      if cue_element_quoted(&c, 4) { ok = false; }
      if cue_element_kind(&c, 5) != EK_SONGWRITER { ok = false; }
      if !streq(cue_element_text(&c, 5), "A. Writer") { ok = false; }
      if cue_element_kind(&c, 6) != EK_INDEX { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bare and quoted values; empty quoted title");
}

fn t4() -> TestResult {
  let r = cue_parse("PERFORMER \"The \"\"Quoted\"\" Band\"\nFILE \"C:\\Music\\album.wav\" WAVE\nTRACK 01 AUDIO\nTITLE \"back\\slash\"\nINDEX 01 00:00:00\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 5;
      if !streq(cue_element_text(&c, 0), "The \"Quoted\" Band") { ok = false; }
      if !cue_element_quoted(&c, 0) { ok = false; }
      if !streq(cue_file_name(&c, 0), "C:\\Music\\album.wav") { ok = false; }
      if !streq(cue_element_text(&c, 3), "back\\slash") { ok = false; }
      let got = cue_emit(&c);
      let want = "PERFORMER \"The \"\"Quoted\"\" Band\"\nFILE \"C:\\Music\\album.wav\" WAVE\nTRACK 01 AUDIO\n  TITLE \"back\\slash\"\n  INDEX 01 00:00:00\n";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "doubled quotes and literal backslashes survive");
}

fn t5() -> TestResult {
  let r = cue_parse("FILE \"x.bin\" BINARY\nTRACK 99 MODE1/2352\nPREGAP 00:00:01\nPOSTGAP 00:00:02\nINDEX 00 00:00:00\nINDEX 01 99:59:74\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 6;
      if cue_track_count(&c) != 1 { ok = false; }
      if cue_track_number(&c, 0) != 99 { ok = false; }
      if !streq(cue_track_type(&c, 0), "MODE1/2352") { ok = false; }
      if cue_index_count(&c) != 2 { ok = false; }
      if cue_index_number(&c, 0) != 0 { ok = false; }
      if cue_index_number(&c, 1) != 1 { ok = false; }
      if cue_index_min(&c, 1) != 99 { ok = false; }
      if cue_index_sec(&c, 1) != 59 { ok = false; }
      if cue_index_frame(&c, 1) != 74 { ok = false; }
      if cue_index_frames(&c, 1) != 449999 { ok = false; }
      if !cue_track_has_index01(&c, 0) { ok = false; }
      if cue_element_kind(&c, 2) != EK_PREGAP { ok = false; }
      if cue_element_frame(&c, 2) != 1 { ok = false; }
      if cue_element_frames(&c, 3) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "boundary track/index numbers and 99:59:74 time");
}

fn t6() -> TestResult {
  var ok = parse_err_prefix("TRACK 1 AUDIO\n", "cue: bad track number: ");
  if !parse_err_prefix("TRACK 00 AUDIO\n", "cue: bad track number: ") { ok = false; }
  if !parse_err_prefix("TRACK 100 AUDIO\n", "cue: bad track number: ") { ok = false; }
  if !parse_err_prefix("TRACK 0A AUDIO\n", "cue: bad track number: ") { ok = false; }
  if !parse_err_prefix("TRACK 01\n", "cue: bad track type: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO EXTRA\n", "cue: bad track type: ") { ok = false; }
  return assert(ok, "bad track numbers are Err");
}

fn t7() -> TestResult {
  var ok = parse_err_prefix("TRACK 01 AUDIO\nINDEX 1 00:00:00\n", "cue: bad index number: ");
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 100 00:00:00\n", "cue: bad index number: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 0A 00:00:00\n", "cue: bad index number: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01\n", "cue: bad index time: ") { ok = false; }
  return assert(ok, "bad index numbers are Err");
}

fn t8() -> TestResult {
  var ok = parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 0:00:00\n", "cue: bad index time: ");
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 00:00\n", "cue: bad index time: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 00:0:00\n", "cue: bad index time: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 00:00:0\n", "cue: bad index time: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 00:00:0X\n", "cue: bad index time: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 aa:00:00\n", "cue: bad index time: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 00:00:00:00\n", "cue: bad index time: ") { ok = false; }
  return assert(ok, "bad mm:ss:ff shapes are Err");
}

fn t9() -> TestResult {
  var ok = parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 00:60:00\n", "cue: second out of range: ");
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 00:00:75\n", "cue: frame out of range: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nINDEX 01 00:00:99\n", "cue: frame out of range: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nPREGAP 00:00:99\nINDEX 01 00:00:00\n", "cue: frame out of range: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nPREGAP 00:0:00\nINDEX 01 00:00:00\n", "cue: bad gap time: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nPOSTGAP 00:99:00\nINDEX 01 00:00:00\n", "cue: second out of range: ") { ok = false; }
  return assert(ok, "second/frame range checks");
}

fn t10() -> TestResult {
  var ok = parse_err_is("TRACK 01 AUDIO\nINDEX 00 00:00:00\n", "cue: track 01 has no INDEX 01");
  if !parse_err_is("FILE \"x\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00\nTRACK 02 AUDIO\nINDEX 00 00:00:00\n", "cue: track 02 has no INDEX 01") { ok = false; }
  if !parse_err_is("FILE \"x\" WAVE\nTRACK 01 AUDIO\n", "cue: track 01 has no INDEX 01") { ok = false; }
  let r = cue_parse("TRACK 01 AUDIO\nINDEX 00 00:00:00\nINDEX 01 00:00:00\n");
  match r {
    Ok(c) => {
      if !cue_track_has_index01(&c, 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a track without INDEX 01 is Err");
}

fn t11() -> TestResult {
  var ok = parse_err_prefix("TITLE \"abc\n", "cue: unterminated quote: ");
  if !parse_err_prefix("PERFORMER \"abc\n", "cue: unterminated quote: ") { ok = false; }
  if !parse_err_prefix("FILE \"x.wav WAVE\n", "cue: unterminated quote: ") { ok = false; }
  if !parse_err_prefix("CATALOG \"1234567890123\n", "cue: unterminated quote: ") { ok = false; }
  if !parse_err_prefix("TITLE \"abc\" junk\n", "cue: trailing text after quote: ") { ok = false; }
  if !parse_err_prefix("CATALOG \"1234567890123\" junk\n", "cue: trailing text after quote: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nISRC \"USRC17607839\" junk\n", "cue: trailing text after quote: ") { ok = false; }
  return assert(ok, "unterminated quote and trailing text are Err");
}

fn t12() -> TestResult {
  var ok = parse_err_is("FOO bar\n", "cue: unknown keyword: FOO");
  if !parse_err_is("TRACKX 01 AUDIO\n", "cue: unknown keyword: TRACKX") { ok = false; }
  if !parse_err_is("track 01 AUDIO\n", "cue: unknown keyword: track") { ok = false; }
  if !parse_err_is("1234\n", "cue: text outside catalog: 1234") { ok = false; }
  if !parse_err_is("\"quoted\"\n", "cue: text outside catalog: \"quoted\"") { ok = false; }
  if !parse_err_is("# comment\n", "cue: text outside catalog: # comment") { ok = false; }
  if !parse_err_is("INDEX 01 00:00:00\n", "cue: keyword not allowed here: INDEX") { ok = false; }
  if !parse_err_is("ISRC USRC17607839\n", "cue: keyword not allowed here: ISRC") { ok = false; }
  if !parse_err_is("PREGAP 00:00:00\n", "cue: keyword not allowed here: PREGAP") { ok = false; }
  if !parse_err_is("POSTGAP 00:00:00\n", "cue: keyword not allowed here: POSTGAP") { ok = false; }
  if !parse_err_is("FILE \"x\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00\nCATALOG 1234567890123\n", "cue: keyword not allowed here: CATALOG") { ok = false; }
  return assert(ok, "unknown keyword, positioned keyword and stray text are Err");
}

fn t13() -> TestResult {
  var ok = parse_err_prefix("FILE x.wav WAVE\n", "cue: bad FILE: ");
  if !parse_err_prefix("FILE \"x.wav\"\n", "cue: bad FILE: ") { ok = false; }
  if !parse_err_prefix("FILE\n", "cue: bad FILE: ") { ok = false; }
  if !parse_err_prefix("FILE \"x.wav\" WAVE EXTRA\n", "cue: bad FILE: ") { ok = false; }
  if !parse_err_prefix("FILE \"x.wav\" \"WAVE\"\n", "cue: bad FILE: ") { ok = false; }
  return assert(ok, "bad FILE shapes are Err");
}

fn t14() -> TestResult {
  var ok = parse_err_prefix("CATALOG 123456789012\n", "cue: bad CATALOG: ");
  if !parse_err_prefix("CATALOG 12345678901234\n", "cue: bad CATALOG: ") { ok = false; }
  if !parse_err_prefix("CATALOG ABCDEFGHIJKLM\n", "cue: bad CATALOG: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nISRC USRC1760783\nINDEX 01 00:00:00\n", "cue: bad ISRC: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nISRC USRC176078390\nINDEX 01 00:00:00\n", "cue: bad ISRC: ") { ok = false; }
  if !parse_err_prefix("TRACK 01 AUDIO\nISRC USRC-7607839\nINDEX 01 00:00:00\n", "cue: bad ISRC: ") { ok = false; }
  let r = cue_parse("CATALOG 1234567890123\nFILE \"x.wav\" WAVE\nTRACK 01 AUDIO\nISRC USRC17607839\nINDEX 01 00:00:00\n");
  match r {
    Ok(c) => {
      if !streq(cue_element_text(&c, 0), "1234567890123") { ok = false; }
      if cue_element_quoted(&c, 0) { ok = false; }
      if !streq(cue_element_text(&c, 3), "USRC17607839") { ok = false; }
      if cue_element_quoted(&c, 3) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bad CATALOG and ISRC values are Err");
}

fn t15() -> TestResult {
  let r = cue_parse("REM GENRE \"Jazz\"\r\nPERFORMER John Doe\nFILE \"album.wav\" WAVE\n\n  TRACK 01 AUDIO\n    TITLE \"One\"\n    INDEX 01 00:00:00\n  TRACK 02 AUDIO\n    TITLE \"\"\n    PERFORMER \"A \"\"B\"\" C\"\n    PREGAP 00:00:02\n    INDEX 01 00:02:00\n");
  var ok = false;
  match r {
    Ok(c) => {
      let got = cue_emit(&c);
      let want = "REM GENRE \"Jazz\"\nPERFORMER John Doe\nFILE \"album.wav\" WAVE\nTRACK 01 AUDIO\n  TITLE \"One\"\n  INDEX 01 00:00:00\nTRACK 02 AUDIO\n  TITLE \"\"\n  PERFORMER \"A \"\"B\"\" C\"\n  PREGAP 00:00:02\n  INDEX 01 00:02:00\n";
      ok = streq(got, want);
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emission: digits, indentation, quoting");
}

fn t16() -> TestResult {
  let r1 = cue_parse("REM GENRE \"Jazz\"\r\nPERFORMER John Doe\nFILE \"album.wav\" WAVE\n\n  TRACK 01 AUDIO\n    TITLE \"One\"\n    INDEX 01 00:00:00\n  TRACK 02 AUDIO\n    TITLE \"Two\"\n    PERFORMER \"Jane Roe\"\n    INDEX 00 04:32:00\n    INDEX 01 04:34:12\n");
  var ok = false;
  match r1 {
    Ok(p1) => {
      let s1 = cue_emit(&p1);
      let r2 = cue_parse(s1);
      match r2 {
        Ok(p2) => {
          ok = same_cue(&p1, &p2);
          let s2 = cue_emit(&p2);
          if !streq(s1, s2) { ok = false; }
          if cue_element_count(&p2) != cue_element_count(&p1) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let r3 = cue_parse("FILE \"x\" BINARY\nTRACK 05 MODE2/2352\nINDEX 01 00:00:00\n");
  match r3 {
    Ok(p3) => {
      let s3 = cue_emit(&p3);
      let r4 = cue_parse(s3);
      match r4 {
        Ok(p4) => {
          if !same_cue(&p3, &p4) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse round trip and idempotence");
}

fn t17() -> TestResult {
  let r = cue_parse("FILE \"cd1.wav\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00\nFILE \"cd2.wav\" WAVE\nTRACK 02 AUDIO\nINDEX 01 00:00:00\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 6;
      if cue_file_count(&c) != 2 { ok = false; }
      if !streq(cue_file_name(&c, 1), "cd2.wav") { ok = false; }
      if cue_track_count(&c) != 2 { ok = false; }
      if cue_track_file(&c, 0) != 0 { ok = false; }
      if cue_track_file(&c, 1) != 1 { ok = false; }
      if cue_element_file(&c, 2) != 0 { ok = false; }
      if cue_element_file(&c, 3) != 1 { ok = false; }
      if cue_element_track(&c, 3) != -1 { ok = false; }
      if cue_element_track(&c, 5) != 1 { ok = false; }
      if cue_index_track(&c, 0) != 0 { ok = false; }
      if cue_index_track(&c, 1) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multiple FILEs: file/track association");
}

fn t18() -> TestResult {
  let r = cue_parse("FILE \"x.wav\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 3;
      if cue_element_kind(&c, -1) != -1 { ok = false; }
      if cue_element_kind(&c, 99) != -1 { ok = false; }
      if cue_element_num(&c, -1) != -1 { ok = false; }
      if cue_element_min(&c, 99) != -1 { ok = false; }
      if cue_element_sec(&c, -2) != -1 { ok = false; }
      if cue_element_frame(&c, 99) != -1 { ok = false; }
      if cue_element_frames(&c, 0) != -1 { ok = false; }
      if cue_element_frames(&c, 99) != -1 { ok = false; }
      if !streq(cue_element_text(&c, -1), "") { ok = false; }
      if !streq(cue_element_text(&c, 99), "") { ok = false; }
      if !streq(cue_element_text2(&c, 99), "") { ok = false; }
      if cue_element_quoted(&c, 99) { ok = false; }
      if cue_element_file(&c, 99) != -1 { ok = false; }
      if cue_element_track(&c, 99) != -1 { ok = false; }
      if cue_element_kind_count(&c, 123) != 0 { ok = false; }
      if !streq(cue_file_name(&c, -1), "") { ok = false; }
      if !streq(cue_file_type(&c, 9), "") { ok = false; }
      if cue_file_element(&c, 5) != -1 { ok = false; }
      if cue_track_number(&c, 5) != -1 { ok = false; }
      if !streq(cue_track_type(&c, -2), "") { ok = false; }
      if cue_track_element(&c, 3) != -1 { ok = false; }
      if cue_track_file(&c, 3) != -1 { ok = false; }
      if cue_track_index_count(&c, 9) != 0 { ok = false; }
      if cue_track_index(&c, 9, 0) != -1 { ok = false; }
      if cue_track_index(&c, 0, 1) != -1 { ok = false; }
      if cue_track_has_index01(&c, 3) { ok = false; }
      if cue_index_number(&c, -1) != -1 { ok = false; }
      if cue_index_min(&c, 3) != -1 { ok = false; }
      if cue_index_frames(&c, 3) != -1 { ok = false; }
      if cue_index_track(&c, 3) != -1 { ok = false; }
      if cue_index_element(&c, 0) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return documented sentinels");
}

fn t19() -> TestResult {
  let r = cue_parse("REM GENRE \"Jazz\"\nREM\nREM   spaced   text\nFILE \"x.wav\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 6;
      if cue_element_kind(&c, 0) != EK_REM { ok = false; }
      if !streq(cue_element_text(&c, 0), "GENRE \"Jazz\"") { ok = false; }
      if !streq(cue_element_text(&c, 1), "") { ok = false; }
      if !streq(cue_element_text(&c, 2), "spaced   text") { ok = false; }
      if cue_element_quoted(&c, 0) { ok = false; }
      let got = cue_emit(&c);
      let want = "REM GENRE \"Jazz\"\nREM\nREM spaced   text\nFILE \"x.wav\" WAVE\nTRACK 01 AUDIO\n  INDEX 01 00:00:00\n";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "REM lines pass through verbatim (modulo line trim)");
}

fn t20() -> TestResult {
  var ok = false;
  let r1 = cue_parse("");
  match r1 {
    Ok(c) => {
      ok = cue_element_count(&c) == 0;
      if cue_file_count(&c) != 0 { ok = false; }
      if cue_track_count(&c) != 0 { ok = false; }
      if cue_index_count(&c) != 0 { ok = false; }
      if !streq(cue_emit(&c), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = cue_parse("\r\n  \r\n\t\n\n");
  match r2 {
    Ok(c) => {
      if cue_element_count(&c) != 0 { ok = false; }
      if !streq(cue_emit(&c), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and blank-only documents");
}

fn t21() -> TestResult {
  let r = cue_parse("FILE \"b.bin\" BINARY\nTRACK 07 MODE2/2352\nPREGAP 00:00:02\nINDEX 01 00:02:00\nPOSTGAP 00:00:03\nTRACK 08 AUDIO\nINDEX 99 99:59:74\nINDEX 01 00:00:00\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = cue_element_count(&c) == 8;
      if cue_track_number(&c, 0) != 7 { ok = false; }
      if cue_track_number(&c, 1) != 8 { ok = false; }
      if cue_index_number(&c, 0) != 1 { ok = false; }
      if cue_index_number(&c, 1) != 99 { ok = false; }
      if cue_index_frames(&c, 1) != 449999 { ok = false; }
      if cue_element_kind(&c, 2) != EK_PREGAP { ok = false; }
      if cue_element_kind(&c, 4) != EK_POSTGAP { ok = false; }
      let got = cue_emit(&c);
      let want = "FILE \"b.bin\" BINARY\nTRACK 07 MODE2/2352\n  PREGAP 00:00:02\n  INDEX 01 00:02:00\n  POSTGAP 00:00:03\nTRACK 08 AUDIO\n  INDEX 99 99:59:74\n  INDEX 01 00:00:00\n";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "gaps and two-digit formatting");
}

fn t22() -> TestResult {
  let r1 = cue_parse("CATALOG \"1234567890123\"\nFILE \"x.wav\" WAVE\nTRACK 01 AUDIO\nISRC \"USRC17607839\"\nINDEX 01 00:00:00\n");
  var ok = false;
  match r1 {
    Ok(c) => {
      ok = cue_element_kind(&c, 0) == EK_CATALOG;
      if !cue_element_quoted(&c, 0) { ok = false; }
      if !streq(cue_element_text(&c, 0), "1234567890123") { ok = false; }
      if cue_element_kind(&c, 3) != EK_ISRC { ok = false; }
      if !cue_element_quoted(&c, 3) { ok = false; }
      if !streq(cue_element_text(&c, 3), "USRC17607839") { ok = false; }
      let got = cue_emit(&c);
      let want = "CATALOG \"1234567890123\"\nFILE \"x.wav\" WAVE\nTRACK 01 AUDIO\n  ISRC \"USRC17607839\"\n  INDEX 01 00:00:00\n";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = cue_parse("CATALOG 1234567890123\nFILE \"x.wav\" WAVE\nTRACK 01 AUDIO\nISRC USRC17607839\nINDEX 01 00:00:00\n");
  match r2 {
    Ok(c) => {
      if cue_element_quoted(&c, 0) { ok = false; }
      if cue_element_quoted(&c, 3) { ok = false; }
      let got = cue_emit(&c);
      let want = "CATALOG 1234567890123\nFILE \"x.wav\" WAVE\nTRACK 01 AUDIO\n  ISRC USRC17607839\n  INDEX 01 00:00:00\n";
      if !streq(got, want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "quoted CATALOG and ISRC round trip");
}

fn main() -> Int {
  io.println("=== xiom.cue conformance tests ===");
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
    io.println("xiom.cue: all tests passed");
  } else {
    io.println("xiom.cue: tests failed");
  }
  return failed;
}
