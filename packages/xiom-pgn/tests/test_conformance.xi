// XIOM -- xiom.pgn conformance tests (24 checks)
// Greenfield package: prove the pure-XIOM xiom.pgn codec against its
// documented PGN subset grammar, validation rules, error catalog and
// canonical emit.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: full games, tag decoding, duplicate tags and tag lookup, brace
// and semicolon comments (multiline included), NAGs, attached move numbers,
// "%" escape lines, move-number sequence validation, SAN lexical acceptance
// and rejection, every error class in SPEC.md section 6, round-tripping,
// canonical emit (spacing, escaping, trailing newline), result handling,
// empty documents and out-of-range accessors.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/tok_is/tag_is instead of `==`.

module pgn_tests
use xiom.io; use xiom.test; use xiom.pgn;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn tag_count_is(g: &Game, want: Int) -> Bool {
  return g.tags.names.len() == want;
}

fn move_count_is(g: &Game, want: Int) -> Bool {
  return g.moves.kinds.len() == want;
}

fn tag_is(g: &Game, i: Int, name: Str, value: Str) -> Bool {
  if i < 0 || i >= g.tags.names.len() { return false; }
  let n: Str = g.tags.names[i];
  let v: Str = g.tags.values[i];
  return streq(n, name) && streq(v, value);
}

fn tok_is(g: &Game, i: Int, kind: Str, text: Str) -> Bool {
  if i < 0 || i >= g.moves.kinds.len() { return false; }
  let k: Str = g.moves.kinds[i];
  let t: Str = g.moves.texts[i];
  return streq(k, kind) && streq(t, text);
}

// pgn_result through a local copy of the stream (never borrow a nested field
// directly: `&struct.field` borrows miscompile for Vec-shaped fields).
fn result_is(g: &Game, want: Str) -> Bool {
  let m: MoveText = g.moves;
  return streq(pgn_result(&m), want);
}

fn tag_of_is(g: &Game, name: Str, want: Str) -> Bool {
  let t: TagList = g.tags;
  let o = pgn_tag_of(&t, name);
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn tag_of_none(g: &Game, name: Str) -> Bool {
  let t: TagList = g.tags;
  let o = pgn_tag_of(&t, name);
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn ok_game(text: Str) -> Bool {
  let r = pgn_parse(text);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

fn err_is(text: Str, want: Str) -> Bool {
  let r = pgn_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn emit_of(text: Str) -> Str {
  let r = pgn_parse(text);
  match r {
    Ok(g) => { return pgn_emit(&g); },
    Err(_) => { return ""; },
  }
  return "";
}

// True when parsing `a` and `b` yields exactly the same tags and movetext
// tokens (text and kind; offsets may differ after normalization).
fn same_tokens(a: Str, b: Str) -> Bool {
  let ra = pgn_parse(a);
  let rb = pgn_parse(b);
  match ra {
    Ok(ga) => {
      match rb {
        Ok(gb) => {
          if ga.tags.names.len() != gb.tags.names.len() { return false; }
          if ga.moves.kinds.len() != gb.moves.kinds.len() { return false; }
          var i = 0;
          while i < ga.tags.names.len() {
            let na: Str = ga.tags.names[i];
            let nb: Str = gb.tags.names[i];
            if !streq(na, nb) { return false; }
            let va: Str = ga.tags.values[i];
            let vb: Str = gb.tags.values[i];
            if !streq(va, vb) { return false; }
            i = i + 1;
          }
          i = 0;
          while i < ga.moves.kinds.len() {
            let ka: Str = ga.moves.kinds[i];
            let kb: Str = gb.moves.kinds[i];
            if !streq(ka, kb) { return false; }
            let ta: Str = ga.moves.texts[i];
            let tb: Str = gb.moves.texts[i];
            if !streq(ta, tb) { return false; }
            i = i + 1;
          }
          return true;
        },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let r = pgn_parse("[Event \"Casual\"]\n[White \"Ada\"]\n[Black \"Bob\"]\n[Result \"1-0\"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = tag_count_is(&g, 4);
      if !tag_is(&g, 0, "Event", "Casual") { ok = false; }
      if !tag_is(&g, 1, "White", "Ada") { ok = false; }
      if !tag_is(&g, 2, "Black", "Bob") { ok = false; }
      if !tag_is(&g, 3, "Result", "1-0") { ok = false; }
      if !move_count_is(&g, 10) { ok = false; }
      if !tok_is(&g, 0, "num", "1.") { ok = false; }
      if !tok_is(&g, 1, "san", "e4") { ok = false; }
      if !tok_is(&g, 3, "num", "2.") { ok = false; }
      if !tok_is(&g, 6, "num", "3.") { ok = false; }
      if !tok_is(&g, 7, "san", "Bb5") { ok = false; }
      if !tok_is(&g, 9, "result", "1-0") { ok = false; }
      if !result_is(&g, "1-0") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full game: tag pairs, movetext tokens and result");
}

fn t2() -> TestResult {
  let r = pgn_parse("[Event \"a\\\"b\\\\c\"]\n\n*\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = tag_is(&g, 0, "Event", "a\"b\\c");
      if !streq(emit_of("[Event \"a\\\"b\\\\c\"]\n\n*\n"), "[Event \"a\\\"b\\\\c\"]\n\n*\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "tag values decode \\\" and \\\\ and re-escape on emit");
}

fn t3() -> TestResult {
  let r = pgn_parse("[Event \"First\"]\n[Event \"Second\"]\n\n*\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = tag_count_is(&g, 2);
      if !tag_is(&g, 0, "Event", "First") { ok = false; }
      if !tag_is(&g, 1, "Event", "Second") { ok = false; }
      if !tag_of_is(&g, "Event", "First") { ok = false; }
      if !tag_of_none(&g, "White") { ok = false; }
      if !tag_of_none(&g, "event") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate tags are preserved; tag_of is exact and returns the first");
}

fn t4() -> TestResult {
  let r = pgn_parse("1. e4 {king pawn\nnote} e5 *\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = move_count_is(&g, 5);
      if !tok_is(&g, 2, "comment", "king pawn\nnote") { ok = false; }
      let m: MoveText = g.moves;
      if pgn_move_start(&m, 2) != 6 { ok = false; }
      if pgn_move_start(&m, -1) != -1 { ok = false; }
      if !tok_is(&g, 3, "san", "e5") { ok = false; }
      if !tok_is(&g, 4, "result", "*") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "brace comments are preserved verbatim, newlines included");
}

fn t5() -> TestResult {
  let r = pgn_parse("1. e4 ; best by test\n1... e5 *\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = move_count_is(&g, 6);
      if !tok_is(&g, 2, "comment_line", " best by test") { ok = false; }
      if !tok_is(&g, 3, "num", "1...") { ok = false; }
      if !tok_is(&g, 5, "result", "*") { ok = false; }
      let m: MoveText = g.moves;
      if pgn_move_start(&m, 3) != 21 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "semicolon comments run to end of line and are kept as tokens");
}

fn t6() -> TestResult {
  let r = pgn_parse("1. e4 $1 e5 $14 *\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = move_count_is(&g, 6);
      if !tok_is(&g, 2, "nag", "1") { ok = false; }
      if !tok_is(&g, 4, "nag", "14") { ok = false; }
      if !tok_is(&g, 5, "result", "*") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "NAGs are digit tokens without the $ sign");
}

fn t7() -> TestResult {
  let r = pgn_parse("1.e4 e5 2.Nf3 2...Nc6 *\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = move_count_is(&g, 8);
      if !tok_is(&g, 0, "num", "1.") { ok = false; }
      if !tok_is(&g, 3, "num", "2.") { ok = false; }
      if !tok_is(&g, 5, "num", "2...") { ok = false; }
      if !tok_is(&g, 6, "san", "Nc6") { ok = false; }
      if !tok_is(&g, 7, "result", "*") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "move numbers hug the next move: 1.e4 and 2...Nc6 tokenize cleanly");
}

fn t8() -> TestResult {
  let r = pgn_parse("% header note\n1. e4 % trailing note\n*\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = move_count_is(&g, 3);
      if !tok_is(&g, 0, "num", "1.") { ok = false; }
      if !tok_is(&g, 1, "san", "e4") { ok = false; }
      if !tok_is(&g, 2, "result", "*") { ok = false; }
      let m: MoveText = g.moves;
      if pgn_move_start(&m, 0) != 14 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "% escape lines are skipped in both sections");
}

fn t9() -> TestResult {
  var ok = err_is("1. e4 3. Nf3 *", "pgn: bad move number sequence at 6");
  if !err_is("2. e4 *", "pgn: bad move number sequence at 0") { ok = false; }
  if !err_is("1... e5 *", "pgn: bad move number sequence at 0") { ok = false; }
  if !err_is("1. e4 e5 3... Nc6", "pgn: bad move number sequence at 9") { ok = false; }
  return assert(ok, "move numbers must start at 1 and advance by one (or repeat with ...)");
}

fn t10() -> TestResult {
  let r = pgn_parse("1. e4 e5 2. Nf3 2... Nc6 *\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = move_count_is(&g, 8);
      if !tok_is(&g, 5, "num", "2...") { ok = false; }
      if !tok_is(&g, 6, "san", "Nc6") { ok = false; }
      let m: MoveText = g.moves;
      if pgn_move_start(&m, 5) != 16 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the ellipsis form repeats the current move number");
}

fn t11() -> TestResult {
  let r = pgn_parse("1. e4 Nf3 Nbd2 N1d2 Nb1d2 Nxf3 exd5 e8=Q exd8=Q O-O O-O-O e4+ Qh5# exd6+ *\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = move_count_is(&g, 16);
      var i = 1;
      while i <= 14 {
        let k: Str = g.moves.kinds[i];
        if !streq(k, "san") { ok = false; }
        i = i + 1;
      }
      if !tok_is(&g, 1, "san", "e4") { ok = false; }
      if !tok_is(&g, 3, "san", "Nbd2") { ok = false; }
      if !tok_is(&g, 6, "san", "Nxf3") { ok = false; }
      if !tok_is(&g, 7, "san", "exd5") { ok = false; }
      if !tok_is(&g, 8, "san", "e8=Q") { ok = false; }
      if !tok_is(&g, 10, "san", "O-O") { ok = false; }
      if !tok_is(&g, 13, "san", "Qh5#") { ok = false; }
      if !tok_is(&g, 14, "san", "exd6+") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "SAN lexical acceptance: pieces, disambiguation, captures, promotion, castling, suffixes");
}

fn t12() -> TestResult {
  var ok = err_is("1. e9 *", "pgn: illegal san token 'e9' at 3");
  if !err_is("1. Nf9 *", "pgn: illegal san token 'Nf9' at 3") { ok = false; }
  if !err_is("1. e4Q *", "pgn: illegal san token 'e4Q' at 3") { ok = false; }
  if !err_is("1. i4 *", "pgn: stray character at 3") { ok = false; }
  if !err_is("1. P e4 *", "pgn: stray character at 3") { ok = false; }
  return assert(ok, "SAN lexical rejection: bad squares, bad promotion form, unknown letters");
}

fn t13() -> TestResult {
  var ok = err_is("1. e4 {oops", "pgn: unterminated comment at 6");
  if !err_is("1. e4 {a\nb\nc", "pgn: unterminated comment at 6") { ok = false; }
  return assert(ok, "an unclosed brace comment reports its opening brace");
}

fn t14() -> TestResult {
  var ok = err_is("[Event \"abc\n*\n", "pgn: unterminated quote at 7");
  if !err_is("[Event \"abc", "pgn: unterminated quote at 7") { ok = false; }
  if !err_is("[Event \"a\\qb\"]", "pgn: invalid escape at 9") { ok = false; }
  return assert(ok, "tag values must close before end of line and only \\\" and \\\\ escape");
}

fn t15() -> TestResult {
  var ok = err_is("[Event \"abc\"", "pgn: unterminated tag at 0");
  if !err_is("[Event \"abc\"\n*\n", "pgn: unterminated tag at 0") { ok = false; }
  if !err_is("[Event \"abc\" x]", "pgn: stray character at 13") { ok = false; }
  return assert(ok, "a tag pair must close with ] on the same physical line");
}

fn t16() -> TestResult {
  var ok = err_is("[ \"x\"]", "pgn: bad tag name at 2");
  if !err_is("[Event]", "pgn: missing tag value at 6") { ok = false; }
  if !err_is("[Event ]", "pgn: missing tag value at 7") { ok = false; }
  if !err_is("[Event x]", "pgn: missing tag value at 7") { ok = false; }
  return assert(ok, "tag names are non-empty and values must be quoted");
}

fn t17() -> TestResult {
  var ok = err_is("1. e4 @e5 *", "pgn: stray character at 6");
  if !err_is("1. e4 ] *", "pgn: stray character at 6") { ok = false; }
  if !err_is("1. 2-0 *", "pgn: illegal result token at 3") { ok = false; }
  if !err_is("1. 0-0 *", "pgn: illegal result token at 3") { ok = false; }
  if !err_is("1. e4 12 *", "pgn: bad move number at 6") { ok = false; }
  if !err_is("1. e4 $ *", "pgn: bad nag at 6") { ok = false; }
  return assert(ok, "stray characters, illegal results, bare digits and bare $ are errors");
}

fn t18() -> TestResult {
  var ok = err_is("1. e4 (1... e5) *", "pgn: unsupported variation at 6");
  if !err_is("1. e4 ) *", "pgn: unsupported variation at 6") { ok = false; }
  return assert(ok, "variation parentheses are a documented unsupported error");
}

fn t19() -> TestResult {
  let messy = "[Event \"X\"]\n\n1.   e4\t{hi}  e5 ; ok\n2.Nf3 *";
  var ok = streq(emit_of(messy), "[Event \"X\"]\n\n1. e4 {hi} e5 ; ok\n2. Nf3 *\n");
  if !same_tokens(messy, emit_of(messy)) { ok = false; }
  return assert(ok, "emit normalizes spacing and the result reparses to the same tokens");
}

fn t20() -> TestResult {
  var ok = streq(emit_of("[Event \"Test\"]\n[Site \"?\"]\n\n1. e4 e5 2. Nf3 Nc6 1-0\n"), "[Event \"Test\"]\n[Site \"?\"]\n\n1. e4 e5 2. Nf3 Nc6 1-0\n");
  if !streq(emit_of("[Event \"a\\\"b\\\\c\"]"), "[Event \"a\\\"b\\\\c\"]\n\n") { ok = false; }
  return assert(ok, "canonical emit is byte-exact (tags, blank line, movetext, trailing newline)");
}

fn t21() -> TestResult {
  var ok = false;
  let empty = pgn_parse("");
  match empty {
    Ok(g) => {
      ok = tag_count_is(&g, 0);
      if !move_count_is(&g, 0) { ok = false; }
      if !result_is(&g, "") { ok = false; }
      if !streq(pgn_emit(&g), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !ok_game("*") { ok = false; }
  if !streq(emit_of("*"), "*\n") { ok = false; }
  let no_result = pgn_parse("1. e4");
  match no_result {
    Ok(g) => {
      if !move_count_is(&g, 2) { ok = false; }
      if !result_is(&g, "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty documents and missing results are valid; a lone result emits canonically");
}

fn t22() -> TestResult {
  var ok = ok_game("1. e4 * {game over}\n; note\n");
  if !err_is("1. e4 * e5", "pgn: token after result at 8") { ok = false; }
  if !err_is("1. e4 1-0 0-1", "pgn: token after result at 10") { ok = false; }
  if !err_is("1. e4 * $1", "pgn: token after result at 8") { ok = false; }
  let r = pgn_parse("1. e4 * {game over}\n; note\n");
  match r {
    Ok(g) => {
      if !move_count_is(&g, 5) { ok = false; }
      if !tok_is(&g, 3, "comment", "game over") { ok = false; }
      if !tok_is(&g, 4, "comment_line", " note") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments may follow the result; any other token after it is an error");
}

fn t23() -> TestResult {
  let r = pgn_parse("[White \"Ada\"]\n\n1. e4 *\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = tag_count_is(&g, 1);
      if !tag_of_is(&g, "White", "Ada") { ok = false; }
      if !tag_of_none(&g, "Black") { ok = false; }
      if !result_is(&g, "*") { ok = false; }
      let t: TagList = g.tags;
      let m: MoveText = g.moves;
      if !streq(pgn_tag_name(&t, 0), "White") { ok = false; }
      if !streq(pgn_tag_value(&t, 0), "Ada") { ok = false; }
      if !streq(pgn_tag_name(&t, 5), "") { ok = false; }
      if !streq(pgn_tag_value(&t, -1), "") { ok = false; }
      if pgn_tag_count(&t) != 1 { ok = false; }
      if !streq(pgn_move_kind(&m, 0), "num") { ok = false; }
      if !streq(pgn_move_text(&m, 0), "1.") { ok = false; }
      if pgn_move_count(&m) != 3 { ok = false; }
      if !streq(pgn_move_kind(&m, 99), "") { ok = false; }
      if !streq(pgn_move_text(&m, -1), "") { ok = false; }
      if pgn_move_start(&m, 99) != -1 { ok = false; }
      if pgn_move_start(&m, -1) != -1 { ok = false; }
      if pgn_move_start(&m, 0) != 15 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "tag/movetext accessors and result lookup, in and out of range");
}

fn t24() -> TestResult {
  var ok = pgn_is_san("e4");
  if !pgn_is_san("Nf3") { ok = false; }
  if !pgn_is_san("Nbd2") { ok = false; }
  if !pgn_is_san("N1d2") { ok = false; }
  if !pgn_is_san("Nb1d2") { ok = false; }
  if !pgn_is_san("Nxf3") { ok = false; }
  if !pgn_is_san("exd5") { ok = false; }
  if !pgn_is_san("e8=Q") { ok = false; }
  if !pgn_is_san("exd8=Q") { ok = false; }
  if !pgn_is_san("O-O") { ok = false; }
  if !pgn_is_san("O-O-O") { ok = false; }
  if !pgn_is_san("e4+") { ok = false; }
  if !pgn_is_san("Qh5#") { ok = false; }
  if !pgn_is_san("exd6+") { ok = false; }
  if !pgn_is_san("e8=Q+") { ok = false; }
  if pgn_is_san("") { ok = false; }
  if pgn_is_san("e9") { ok = false; }
  if pgn_is_san("Nf9") { ok = false; }
  if pgn_is_san("e4Q") { ok = false; }
  if pgn_is_san("OO") { ok = false; }
  if pgn_is_san("0-0") { ok = false; }
  if pgn_is_san("P") { ok = false; }
  if pgn_is_san("e") { ok = false; }
  if pgn_is_san("Nf3x") { ok = false; }
  if pgn_is_san("e4 ") { ok = false; }
  if pgn_is_san("a8=K") { ok = false; }
  return assert(ok, "pgn_is_san accepts the lexical forms and rejects everything else");
}

fn main() -> Int {
  io.println("=== xiom.pgn conformance tests ===");
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
    io.println("xiom.pgn: all tests passed");
  } else {
    io.println("xiom.pgn: tests failed");
  }
  return failed;
}
