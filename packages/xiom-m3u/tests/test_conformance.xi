// XIOM -- xiom.m3u conformance tests (20 checks)
// Greenfield package: prove the pure-XIOM xiom.m3u module against its
// documented M3U/M3U8 line grammar, error catalog and round-trip rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: extended and plain playlists, CRLF and missing final newline,
// blank lines and whitespace-only lines, HLS tags and comments preserved,
// per-entry tag ranges, trailing tags, zero/leading-zero/max-digit durations,
// titles with commas and empty titles, all three parse errors, the documented
// path-before-header rule, canonical emission, round trips, empty and
// comment-only documents, and out-of-range accessor sentinels.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq and every Vec element read binds
// a typed local first. Test functions are called directly from main (no
// indexed Vec[fn] dispatch, which miscompiles).

module m3u_tests
use xiom.io; use xiom.test; use xiom.m3u;
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

// True when the text fails to parse with an error message carrying `prefix`.
fn parse_err_prefix(text: Str, prefix: Str) -> Bool {
  let r = m3u_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

// True when entries `i` of `a` and `b` carry the same raw tag lines.
fn same_entry_tags(a: &Playlist, b: &Playlist, i: Int) -> Bool {
  if m3u_entry_tag_count(a, i) != m3u_entry_tag_count(b, i) { return false; }
  var j = 0;
  while j < m3u_entry_tag_count(a, i) {
    let ta: Str = m3u_entry_tag(a, i, j);
    let tb: Str = m3u_entry_tag(b, i, j);
    if !streq(ta, tb) { return false; }
    j = j + 1;
  }
  return true;
}

// Deep equality over the observable playlist surface (not the parallel Vecs).
fn same_playlist(a: &Playlist, b: &Playlist) -> Bool {
  if m3u_has_header(a) != m3u_has_header(b) { return false; }
  if m3u_entry_count(a) != m3u_entry_count(b) { return false; }
  if m3u_tag_count(a) != m3u_tag_count(b) { return false; }
  if m3u_trailing_tag_count(a) != m3u_trailing_tag_count(b) { return false; }
  var i = 0;
  while i < m3u_entry_count(a) {
    if m3u_duration_seconds(a, i) != m3u_duration_seconds(b, i) { return false; }
    let ta: Str = m3u_title(a, i);
    let tb: Str = m3u_title(b, i);
    if !streq(ta, tb) { return false; }
    let pa: Str = m3u_path(a, i);
    let pb: Str = m3u_path(b, i);
    if !streq(pa, pb) { return false; }
    if !same_entry_tags(a, b, i) { return false; }
    i = i + 1;
  }
  var j = 0;
  while j < m3u_trailing_tag_count(a) {
    let t1: Str = m3u_trailing_tag(a, j);
    let t2: Str = m3u_trailing_tag(b, j);
    if !streq(t1, t2) { return false; }
    j = j + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = m3u_parse("#EXTM3U\n#EXTINF:5,Intro\nintro.mp3\n#EXTINF:123,Second Track\nsub/second.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = m3u_has_header(&p);
      if m3u_entry_count(&p) != 2 { ok = false; }
      if m3u_duration_seconds(&p, 0) != 5 { ok = false; }
      if !streq(m3u_title(&p, 0), "Intro") { ok = false; }
      if !streq(m3u_path(&p, 0), "intro.mp3") { ok = false; }
      if m3u_duration_seconds(&p, 1) != 123 { ok = false; }
      if !streq(m3u_title(&p, 1), "Second Track") { ok = false; }
      if !streq(m3u_path(&p, 1), "sub/second.mp3") { ok = false; }
      if m3u_tag_count(&p) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "extended playlist: header, durations, titles, paths");
}

fn t2() -> TestResult {
  let r = m3u_parse("one.mp3\nsub/two.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = !m3u_has_header(&p);
      if m3u_entry_count(&p) != 2 { ok = false; }
      if m3u_duration_seconds(&p, 0) != -1 { ok = false; }
      if !streq(m3u_title(&p, 0), "") { ok = false; }
      if !streq(m3u_path(&p, 0), "one.mp3") { ok = false; }
      if !streq(m3u_path(&p, 1), "sub/two.mp3") { ok = false; }
      if m3u_duration_seconds(&p, 1) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "plain headerless M3U: paths only, no durations");
}

fn t3() -> TestResult {
  let r = m3u_parse("#EXTM3U\r\n#EXTINF:3,One\r\na.mp3\r\n#EXTINF:4,Two\r\nb.mp3\r\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = m3u_has_header(&p);
      if m3u_entry_count(&p) != 2 { ok = false; }
      if m3u_duration_seconds(&p, 0) != 3 { ok = false; }
      if !streq(m3u_title(&p, 0), "One") { ok = false; }
      if !streq(m3u_path(&p, 0), "a.mp3") { ok = false; }
      if m3u_duration_seconds(&p, 1) != 4 { ok = false; }
      if !streq(m3u_title(&p, 1), "Two") { ok = false; }
      if !streq(m3u_path(&p, 1), "b.mp3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF line endings parse like LF");
}

fn t4() -> TestResult {
  let r = m3u_parse("a.mp3\r\nb.mp3");
  var ok = false;
  match r {
    Ok(p) => {
      ok = m3u_entry_count(&p) == 2;
      if !streq(m3u_path(&p, 0), "a.mp3") { ok = false; }
      if !streq(m3u_path(&p, 1), "b.mp3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a final line without LF is a line; CRLF is stripped");
}

fn t5() -> TestResult {
  let r1 = m3u_parse("\n\n#EXTM3U\n\n\na.mp3\n\n\n#EXTINF:1,x\nb.mp3\n\n");
  var ok = false;
  match r1 {
    Ok(p) => {
      ok = m3u_has_header(&p);
      if m3u_entry_count(&p) != 2 { ok = false; }
      if !streq(m3u_path(&p, 0), "a.mp3") { ok = false; }
      if !streq(m3u_path(&p, 1), "b.mp3") { ok = false; }
      if m3u_duration_seconds(&p, 1) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = m3u_parse("#EXTM3U\n   \n");
  match r2 {
    Ok(q) => {
      if m3u_entry_count(&q) != 1 { ok = false; }
      if !streq(m3u_path(&q, 0), "   ") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = m3u_parse("#EXTM3U\n#EXTINF:5,t\n\n\np.mp3\n");
  match r3 {
    Ok(s) => {
      if m3u_entry_count(&s) != 1 { ok = false; }
      if m3u_duration_seconds(&s, 0) != 5 { ok = false; }
      if !streq(m3u_path(&s, 0), "p.mp3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "blank lines are ignored anywhere; whitespace-only lines are paths");
}

fn t6() -> TestResult {
  let r = m3u_parse("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXTINF:9,seg0.ts\nseg0.ts\n#EXT-X-ENDLIST\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = m3u_tag_count(&p) == 3;
      if !streq(m3u_tag(&p, 0), "#EXT-X-VERSION:3") { ok = false; }
      if !streq(m3u_tag(&p, 1), "#EXT-X-TARGETDURATION:10") { ok = false; }
      if !streq(m3u_tag(&p, 2), "#EXT-X-ENDLIST") { ok = false; }
      if m3u_entry_tag_count(&p, 0) != 2 { ok = false; }
      if !streq(m3u_entry_tag(&p, 0, 0), "#EXT-X-VERSION:3") { ok = false; }
      if !streq(m3u_entry_tag(&p, 0, 1), "#EXT-X-TARGETDURATION:10") { ok = false; }
      if m3u_trailing_tag_count(&p) != 1 { ok = false; }
      if !streq(m3u_trailing_tag(&p, 0), "#EXT-X-ENDLIST") { ok = false; }
      if m3u_entry_count(&p) != 1 { ok = false; }
      if !streq(m3u_path(&p, 0), "seg0.ts") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "HLS tags are preserved raw; ENDLIST is a trailing tag");
}

fn t7() -> TestResult {
  let r = m3u_parse("# note a\none.mp3\n# note b\n# note c\ntwo.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = m3u_entry_count(&p) == 2;
      if m3u_tag_count(&p) != 3 { ok = false; }
      if m3u_entry_tag_count(&p, 0) != 1 { ok = false; }
      if !streq(m3u_entry_tag(&p, 0, 0), "# note a") { ok = false; }
      if m3u_entry_tag_count(&p, 1) != 2 { ok = false; }
      if !streq(m3u_entry_tag(&p, 1, 0), "# note b") { ok = false; }
      if !streq(m3u_entry_tag(&p, 1, 1), "# note c") { ok = false; }
      if m3u_trailing_tag_count(&p) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = m3u_parse("#EXTM3U\n#EXTINF:5,x\n#between\np.mp3\n");
  match r2 {
    Ok(q) => {
      if m3u_entry_count(&q) != 1 { ok = false; }
      if m3u_duration_seconds(&q, 0) != 5 { ok = false; }
      if !streq(m3u_title(&q, 0), "x") { ok = false; }
      if !streq(m3u_path(&q, 0), "p.mp3") { ok = false; }
      if m3u_entry_tag_count(&q, 0) != 1 { ok = false; }
      if !streq(m3u_entry_tag(&q, 0, 0), "#between") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "tags attach to the entry that follows them");
}

fn t8() -> TestResult {
  let r = m3u_parse("#EXTM3U\n#EXTINF:0,\nzero.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = m3u_duration_seconds(&p, 0) == 0;
      if !streq(m3u_title(&p, 0), "") { ok = false; }
      if !streq(m3u_path(&p, 0), "zero.mp3") { ok = false; }
      if m3u_entry_count(&p) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "zero seconds and an empty title are valid");
}

fn t9() -> TestResult {
  let r = m3u_parse("#EXTM3U\n#EXTINF:007,Lead In\n007.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = m3u_duration_seconds(&p, 0) == 7;
      if !streq(m3u_title(&p, 0), "Lead In") { ok = false; }
      if !streq(m3u_path(&p, 0), "007.mp3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "leading zeros in the seconds field are accepted");
}

fn t10() -> TestResult {
  let r = m3u_parse("#EXTM3U\n#EXTINF:12,Hello, world\ntrack10.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = m3u_duration_seconds(&p, 0) == 12;
      if !streq(m3u_title(&p, 0), "Hello, world") { ok = false; }
      if !streq(m3u_path(&p, 0), "track10.mp3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the first comma splits duration from a title with commas");
}

fn t11() -> TestResult {
  var ok = parse_err_prefix("#EXTM3U\n#EXTINF:5,a\n", "m3u: missing path after #EXTINF");
  if !parse_err_prefix("#EXTM3U\n#EXTINF:5,a\n#EXTINF:6,b\nx.mp3\n", "m3u: missing path after #EXTINF") { ok = false; }
  if !parse_err_prefix("#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:5,a\n#EXT-X-ENDLIST\n", "m3u: missing path after #EXTINF") { ok = false; }
  return assert(ok, "an #EXTINF with no path line before EOF or the next #EXTINF is Err");
}

fn t12() -> TestResult {
  var ok = parse_err_prefix("#EXTM3U\n#EXTINF\nx.mp3\n", "m3u: bad #EXTINF: ");
  if !parse_err_prefix("#EXTM3U\n#EXTINF5,x\nx.mp3\n", "m3u: bad #EXTINF: ") { ok = false; }
  if !parse_err_prefix("#EXTM3U\n#EXTINF:5\nx.mp3\n", "m3u: bad #EXTINF: ") { ok = false; }
  if !parse_err_prefix("#EXTM3U\n#EXTINF:5 title\nx.mp3\n", "m3u: bad #EXTINF: ") { ok = false; }
  return assert(ok, "malformed #EXTINF shapes are Err");
}

fn t13() -> TestResult {
  var ok = parse_err_prefix("#EXTM3U\n#EXTINF:,x\np\n", "m3u: bad duration in #EXTINF: ");
  if !parse_err_prefix("#EXTM3U\n#EXTINF:-1,x\np\n", "m3u: bad duration in #EXTINF: ") { ok = false; }
  if !parse_err_prefix("#EXTM3U\n#EXTINF:1.5,x\np\n", "m3u: bad duration in #EXTINF: ") { ok = false; }
  if !parse_err_prefix("#EXTM3U\n#EXTINF:abc,x\np\n", "m3u: bad duration in #EXTINF: ") { ok = false; }
  if !parse_err_prefix("#EXTM3U\n#EXTINF:1 2,x\np\n", "m3u: bad duration in #EXTINF: ") { ok = false; }
  return assert(ok, "empty, negative, float, non-numeric and spaced durations are Err");
}

fn t14() -> TestResult {
  var ok = parse_err_prefix("#EXTM3U\n#EXTINF:123456789012345678901234567890,x\np\n", "m3u: bad duration in #EXTINF: ");
  let r = m3u_parse("#EXTM3U\n#EXTINF:999999999999999999,Big\np\n");
  match r {
    Ok(p) => {
      if m3u_duration_seconds(&p, 0) != 999999999999999999 { ok = false; }
      if !streq(m3u_title(&p, 0), "Big") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "18 digits are the accepted maximum; more is Err");
}

fn t15() -> TestResult {
  let r = m3u_parse("first.mp3\n#EXTM3U\nsecond.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = !m3u_has_header(&p);
      if m3u_entry_count(&p) != 2 { ok = false; }
      if m3u_entry_tag_count(&p, 0) != 0 { ok = false; }
      if m3u_entry_tag_count(&p, 1) != 1 { ok = false; }
      if !streq(m3u_entry_tag(&p, 1, 0), "#EXTM3U") { ok = false; }
      if m3u_tag_count(&p) != 1 { ok = false; }
      if m3u_trailing_tag_count(&p) != 0 { ok = false; }
      if !streq(m3u_path(&p, 1), "second.mp3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a path before #EXTM3U is accepted; the late #EXTM3U is a raw tag");
}

fn t16() -> TestResult {
  let r = m3u_parse("\r\n#EXTM3U\r\n\r\n#EXT-X-VERSION:3\r\n#EXTINF:5,Intro\r\nintro.mp3\r\n\r\n#EXTINF:0,\r\nzero.mp3\r\n#EXT-X-ENDLIST\r\n");
  var ok = false;
  match r {
    Ok(p) => {
      let got = m3u_emit(&p);
      let want = "#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:5,Intro\nintro.mp3\n#EXTINF:0,\nzero.mp3\n#EXT-X-ENDLIST\n";
      ok = streq(got, want);
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit writes the canonical LF layout with a #EXTM3U header");
}

fn t17() -> TestResult {
  let r1 = m3u_parse("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,First\na/one.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:10,Second\na/two.ts\n#EXTINF:0,\na/three.ts\n#EXT-X-ENDLIST\n");
  var ok = false;
  match r1 {
    Ok(p1) => {
      let text = m3u_emit(&p1);
      let r2 = m3u_parse(text);
      match r2 {
        Ok(p2) => {
          ok = same_playlist(&p1, &p2);
          if m3u_entry_count(&p2) != 3 { ok = false; }
          if m3u_duration_seconds(&p2, 1) != 10 { ok = false; }
          if !streq(m3u_entry_tag(&p2, 1, 0), "#EXT-X-DISCONTINUITY") { ok = false; }
          if !streq(m3u_trailing_tag(&p2, 0), "#EXT-X-ENDLIST") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse round-trips entries, tags and trailing tags");
}

fn t18() -> TestResult {
  let r = m3u_parse("one.mp3\ntwo.mp3\n");
  var ok = false;
  match r {
    Ok(p1) => {
      let got = m3u_emit(&p1);
      ok = streq(got, "#EXTM3U\none.mp3\ntwo.mp3\n");
      let r2 = m3u_parse(got);
      match r2 {
        Ok(p2) => {
          if !m3u_has_header(&p2) { ok = false; }
          if m3u_entry_count(&p2) != 2 { ok = false; }
          if !streq(m3u_path(&p2, 1), "two.mp3") { ok = false; }
          if m3u_duration_seconds(&p2, 0) != -1 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a headerless playlist is normalized to extended M3U on emit");
}

fn t19() -> TestResult {
  var ok = false;
  let r1 = m3u_parse("");
  match r1 {
    Ok(p) => {
      ok = m3u_entry_count(&p) == 0;
      if m3u_has_header(&p) { ok = false; }
      if !streq(m3u_emit(&p), "#EXTM3U\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = m3u_parse("\n\n\n");
  match r2 {
    Ok(p) => {
      if m3u_entry_count(&p) != 0 { ok = false; }
      if !streq(m3u_emit(&p), "#EXTM3U\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = m3u_parse("#EXTM3U\n");
  match r3 {
    Ok(p) => {
      if m3u_entry_count(&p) != 0 { ok = false; }
      if !m3u_has_header(&p) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r4 = m3u_parse("#just a comment\n");
  match r4 {
    Ok(p) => {
      if m3u_entry_count(&p) != 0 { ok = false; }
      if m3u_has_header(&p) { ok = false; }
      if m3u_tag_count(&p) != 1 { ok = false; }
      if m3u_trailing_tag_count(&p) != 1 { ok = false; }
      if !streq(m3u_trailing_tag(&p, 0), "#just a comment") { ok = false; }
      if !streq(m3u_emit(&p), "#EXTM3U\n#just a comment\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty, blank-only, header-only and comment-only documents are valid");
}

fn t20() -> TestResult {
  let r = m3u_parse("#EXTM3U\n#EXTINF:3,T\np.mp3\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = !streq(m3u_path(&p, -1), "p.mp3");
      if !streq(m3u_path(&p, -1), "") { ok = false; }
      if !streq(m3u_path(&p, 1), "") { ok = false; }
      if !streq(m3u_title(&p, 9), "") { ok = false; }
      if m3u_duration_seconds(&p, -1) != -1 { ok = false; }
      if m3u_duration_seconds(&p, 5) != -1 { ok = false; }
      if m3u_entry_tag_count(&p, 5) != 0 { ok = false; }
      if !streq(m3u_entry_tag(&p, 0, 0), "") { ok = false; }
      if !streq(m3u_entry_tag(&p, 7, 0), "") { ok = false; }
      if !streq(m3u_tag(&p, 0), "") { ok = false; }
      if m3u_trailing_tag_count(&p) != 0 { ok = false; }
      if !streq(m3u_trailing_tag(&p, 0), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return documented sentinels");
}

fn main() -> Int {
  io.println("=== xiom.m3u conformance tests ===");
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
    io.println("xiom.m3u: all tests passed");
  } else {
    io.println("xiom.m3u: tests failed");
  }
  return failed;
}
