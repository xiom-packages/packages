// XIOM -- xiom.fits conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: minimal and classic multi-card headers (keyword, kind, raw
// token, comment, first-match lookup), quoted strings with '' unescaping
// and empty strings, integer/real raw-token preservation, COMMENT/HISTORY/
// blank continuation cards, undefined values, the fixed-width per-kind card
// formatting with pinned 80-character output, builder -> encode -> parse
// round-trips, parse -> encode byte-exact reproduction (including
// non-canonical spacing), a two-block header with a card crossing the
// boundary, out-of-range accessors, and the whole error catalog: card not
// 80 chars, unexpected END, missing END, bad block padding (zero/odd
// lengths, junk after END, junk inside the END card), quote not closed,
// bad logical (parse and format), junk after value, missing '=', bad
// keyword, bad kind, invalid integer, invalid real, invalid value and card
// too long.
//
// Str values read from Vec[Str] elements are always bound to a typed local
// and compared through compare.str_compare (BUG 17 discipline: `==` on such
// values lowers to a pointer comparison). There is no Vec[fn] dispatch;
// main calls every test function directly.

module fits_tests
use xiom.io; use xiom.test;
use xiom.fits;
use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// `n` spaces.
fn sp(n: Int) -> Str {
  var s = "";
  var i = 0;
  while i < n {
    s = s + " ";
    i = i + 1;
  }
  return s;
}

// `unit` repeated `n` times.
fn rep(unit: Str, n: Int) -> Str {
  var s = "";
  var i = 0;
  while i < n {
    s = s + unit;
    i = i + 1;
  }
  return s;
}

// `text` padded with ASCII spaces to exactly 80 characters.
fn card80(text: Str) -> Str {
  var s = text;
  while s.len() < 80 {
    s = s + " ";
  }
  return s;
}

fn push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Concatenate 80-character cards, append an END card, pad to 2880 bytes.
fn pack_cards(cards: Vec[Str]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < cards.len() {
    let c: Str = cards[i];
    push_str(&mut out, c);
    i = i + 1;
  }
  push_str(&mut out, card80("END"));
  while out.len() % 2880 != 0 {
    out.push(32u8);
  }
  return out;
}

// Like pack_cards but without an END card. Always one 2880-byte block.
fn pack_no_end(cards: Vec[Str]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < cards.len() {
    let c: Str = cards[i];
    push_str(&mut out, c);
    i = i + 1;
  }
  if out.len() == 0 {
    out.push(32u8);
  }
  while out.len() % 2880 != 0 {
    out.push(32u8);
  }
  return out;
}

// First `n` bytes of `v`.
fn prefix(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    let b: UInt8 = v[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() {
    return false;
  }
  let s: Str = v[i];
  return streq(s, want);
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

fn opt_bool_is(o: Option[Bool], want: Bool) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

fn opt_bool_none(o: Option[Bool]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn ok_unit(r: Result[Unit, Str]) -> Bool {
  return r.is_ok;
}

fn err_header_is(r: Result[FitsHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("SIMPLE  = " + sp(19) + "T"));
  let data = pack_cards(cards);
  var ok = data.len() == 2880;
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "minimal header must parse");
  }
  let h: FitsHeader = r.value;
  if fits_card_count(&h) != 1 {
    ok = false;
  }
  if !streq(fits_keyword(&h, 0), "SIMPLE") {
    ok = false;
  }
  if fits_kind(&h, 0) != FITK_LOGICAL {
    ok = false;
  }
  if !opt_str_is(fits_value(&h, 0), "T") {
    ok = false;
  }
  if !opt_bool_is(fits_bool_value(&h, "simple"), true) {
    ok = false;
  }
  return assert(ok, "minimal one-card header: keyword, kind, logical value");
}

fn t2() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("SIMPLE  = " + sp(19) + "T / file does conform to FITS standard"));
  cards.push(card80("BITPIX  = " + sp(19) + "16 / number of bits per data pixel"));
  cards.push(card80("NAXIS   = " + sp(20) + "0 / number of data axes"));
  cards.push(card80("EXTEND  = " + sp(19) + "T / FITS dataset may contain extensions"));
  let data = pack_cards(cards);
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "classic header must parse");
  }
  let h: FitsHeader = r.value;
  var ok = fits_card_count(&h) == 4;
  if fits_kind(&h, 0) != FITK_LOGICAL {
    ok = false;
  }
  if fits_kind(&h, 1) != FITK_INT {
    ok = false;
  }
  if fits_kind(&h, 2) != FITK_INT {
    ok = false;
  }
  if fits_kind(&h, 3) != FITK_LOGICAL {
    ok = false;
  }
  if !streq(fits_keyword(&h, 1), "BITPIX") {
    ok = false;
  }
  if !opt_str_is(fits_value(&h, 1), "16") {
    ok = false;
  }
  if !streq(fits_comment(&h, 1), "number of bits per data pixel") {
    ok = false;
  }
  if !streq(fits_comment(&h, 0), "file does conform to FITS standard") {
    ok = false;
  }
  if fits_find(&h, "NAXIS") != 2 {
    ok = false;
  }
  if !opt_str_is(fits_int_token(&h, "BITPIX"), "16") {
    ok = false;
  }
  if !opt_bool_is(fits_bool_value(&h, "EXTEND"), true) {
    ok = false;
  }
  return assert(ok, "classic four-card header: kinds, values, comments, find");
}

fn t3() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("OBJECT  = 'M31'" + sp(15) + " / object name"));
  cards.push(card80("OBSERVER= 'O''HARA'"));
  cards.push(card80("EMPTY   = ''"));
  let data = pack_cards(cards);
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "string header must parse");
  }
  let h: FitsHeader = r.value;
  var ok = fits_kind(&h, 0) == FITK_STR;
  if !opt_str_is(fits_value(&h, 0), "M31") {
    ok = false;
  }
  if !streq(fits_comment(&h, 0), "object name") {
    ok = false;
  }
  if !opt_str_is(fits_str_value(&h, "observer"), "O'HARA") {
    ok = false;
  }
  if !opt_str_is(fits_value(&h, 2), "") {
    ok = false;
  }
  return assert(ok, "quoted strings: decode, '' escaping and empty string");
}

fn t4() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("KEY1    = " + sp(15) + "+0042"));
  cards.push(card80("KEY2    = " + sp(11) + "-1.50E+02"));
  cards.push(card80("KEY3    = " + sp(18) + ".5"));
  cards.push(card80("KEY4    = " + sp(18) + "-0"));
  cards.push(card80("KEY5    = 2.5D-3 / exposure"));
  let data = pack_cards(cards);
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "numeric header must parse");
  }
  let h: FitsHeader = r.value;
  var ok = fits_kind(&h, 0) == FITK_INT;
  if fits_kind(&h, 1) != FITK_REAL {
    ok = false;
  }
  if fits_kind(&h, 2) != FITK_REAL {
    ok = false;
  }
  if fits_kind(&h, 3) != FITK_INT {
    ok = false;
  }
  if fits_kind(&h, 4) != FITK_REAL {
    ok = false;
  }
  if !opt_str_is(fits_value(&h, 0), "+0042") {
    ok = false;
  }
  if !opt_str_is(fits_value(&h, 1), "-1.50E+02") {
    ok = false;
  }
  if !opt_str_is(fits_value(&h, 2), ".5") {
    ok = false;
  }
  if !opt_str_is(fits_value(&h, 3), "-0") {
    ok = false;
  }
  if !opt_str_is(fits_float_token(&h, "KEY5"), "2.5D-3") {
    ok = false;
  }
  if !streq(fits_comment(&h, 4), "exposure") {
    ok = false;
  }
  return assert(ok, "integer/real tokens are preserved exactly as written");
}

fn t5() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("COMMENT   FITS header codec test"));
  cards.push(card80("HISTORY   created by xiom.fits"));
  cards.push(card80("          continuation text without a keyword"));
  let data = pack_cards(cards);
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "comment header must parse");
  }
  let h: FitsHeader = r.value;
  var ok = fits_card_count(&h) == 3;
  if fits_kind(&h, 0) != FITK_COMMENT {
    ok = false;
  }
  if fits_kind(&h, 1) != FITK_HISTORY {
    ok = false;
  }
  if fits_kind(&h, 2) != FITK_BLANK {
    ok = false;
  }
  if !streq(fits_comment(&h, 0), "FITS header codec test") {
    ok = false;
  }
  if !streq(fits_comment(&h, 1), "created by xiom.fits") {
    ok = false;
  }
  if !streq(fits_comment(&h, 2), "continuation text without a keyword") {
    ok = false;
  }
  if !streq(fits_keyword(&h, 2), "") {
    ok = false;
  }
  if !opt_str_none(fits_value(&h, 0)) {
    ok = false;
  }
  if !opt_str_none(fits_value(&h, 1)) {
    ok = false;
  }
  if !opt_str_none(fits_value(&h, 2)) {
    ok = false;
  }
  if fits_find(&h, "COMMENT") != 0 {
    ok = false;
  }
  if fits_find(&h, "HISTORY") != 1 {
    ok = false;
  }
  if fits_find(&h, "") != -1 {
    ok = false;
  }
  return assert(ok, "COMMENT/HISTORY/blank cards carry their text, not values");
}

fn t6() -> TestResult {
  var h = fits_new();
  let good = card80("SIMPLE  = " + sp(19) + "T");
  let r_short = fits_push_card(&mut h, "TOO SHORT");
  let r_long = fits_push_card(&mut h, sp(81));
  let r_79 = fits_push_card(&mut h, sp(79));
  let r_end = fits_push_card(&mut h, card80("END"));
  let r_good = fits_push_card(&mut h, good);
  var ok = err_unit_is(r_short, "fits: card not 80 chars");
  if !err_unit_is(r_long, "fits: card not 80 chars") {
    ok = false;
  }
  if !err_unit_is(r_79, "fits: card not 80 chars") {
    ok = false;
  }
  if !err_unit_is(r_end, "fits: unexpected END") {
    ok = false;
  }
  if !ok_unit(r_good) {
    ok = false;
  }
  if fits_card_count(&h) != 1 {
    ok = false;
  }
  return assert(ok, "fits_push_card enforces 80 chars and rejects END atomically");
}

fn t7() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("SIMPLE  = " + sp(19) + "T"));
  let data = pack_no_end(cards);
  var ok = err_header_is(fits_parse(&data), "fits: missing END");
  var none = Vec[Str].new();
  let blank = pack_no_end(none);
  if !err_header_is(fits_parse(&blank), "fits: missing END") {
    ok = false;
  }
  return assert(ok, "a header without an END card is Err(fits: missing END)");
}

fn t8() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_header_is(fits_parse(&empty), "fits: bad block padding");
  var cards = Vec[Str].new();
  cards.push(card80("SIMPLE  = " + sp(19) + "T"));
  let data = pack_cards(cards);
  let trunc = prefix(&data, 1440);
  if !err_header_is(fits_parse(&trunc), "fits: bad block padding") {
    ok = false;
  }
  var odd = prefix(&data, 2880);
  odd.push(32u8);
  if !err_header_is(fits_parse(&odd), "fits: bad block padding") {
    ok = false;
  }
  var junk_after = prefix(&data, 2880);
  junk_after[200] = 88u8;
  if !err_header_is(fits_parse(&junk_after), "fits: bad block padding") {
    ok = false;
  }
  var junk_end = prefix(&data, 2880);
  junk_end[90] = 88u8;
  if !err_header_is(fits_parse(&junk_end), "fits: bad block padding") {
    ok = false;
  }
  return assert(ok, "block length and space-padding violations are bad block padding");
}

fn t9() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("NAME    = 'unterminated"));
  let data = pack_cards(cards);
  var ok = err_header_is(fits_parse(&data), "fits: quote not closed");
  var cards2 = Vec[Str].new();
  cards2.push(card80("NAME    = 'abc''"));
  let data2 = pack_cards(cards2);
  if !err_header_is(fits_parse(&data2), "fits: quote not closed") {
    ok = false;
  }
  return assert(ok, "a string whose closing quote is missing is Err");
}

fn t10() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("FLAG    = Y"));
  let data = pack_cards(cards);
  var ok = err_header_is(fits_parse(&data), "fits: bad logical");
  var cards2 = Vec[Str].new();
  cards2.push(card80("FLAG    = TRUE"));
  let data2 = pack_cards(cards2);
  if !err_header_is(fits_parse(&data2), "fits: bad logical") {
    ok = false;
  }
  if !err_str_is(fits_card_format("FLAG", FITK_LOGICAL, "Maybe", ""), "fits: bad logical") {
    ok = false;
  }
  if !err_str_is(fits_card_format("FLAG", FITK_LOGICAL, "t", ""), "fits: bad logical") {
    ok = false;
  }
  return assert(ok, "only uppercase T/F are logicals, in parse and in format");
}

fn t11() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("KEY     = 42 x"));
  let data = pack_cards(cards);
  var ok = err_header_is(fits_parse(&data), "fits: junk after value");
  var cards2 = Vec[Str].new();
  cards2.push(card80("NAME    = 'abc' x"));
  let data2 = pack_cards(cards2);
  if !err_header_is(fits_parse(&data2), "fits: junk after value") {
    ok = false;
  }
  var cards3 = Vec[Str].new();
  cards3.push(card80("KEY     = 42 /ok"));
  let data3 = pack_cards(cards3);
  let r3 = fits_parse(&data3);
  if !r3.is_ok {
    ok = false;
  } else {
    let h3: FitsHeader = r3.value;
    if !streq(fits_comment(&h3, 0), "ok") {
      ok = false;
    }
    if !opt_str_is(fits_int_token(&h3, "KEY"), "42") {
      ok = false;
    }
  }
  return assert(ok, "bytes between a value and '/' are Err, a comment is not");
}

fn t12() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("KEYWORD   value"));
  let data = pack_cards(cards);
  var ok = err_header_is(fits_parse(&data), "fits: missing '='");
  var cards2 = Vec[Str].new();
  cards2.push(card80("lower   = 1"));
  let data2 = pack_cards(cards2);
  if !err_header_is(fits_parse(&data2), "fits: bad keyword") {
    ok = false;
  }
  var cards3 = Vec[Str].new();
  cards3.push(card80("KEY WORD= 1"));
  let data3 = pack_cards(cards3);
  if !err_header_is(fits_parse(&data3), "fits: bad keyword") {
    ok = false;
  }
  return assert(ok, "a value card needs '=' in column 9 and a valid keyword");
}

fn t13() -> TestResult {
  var ok = err_str_is(fits_card_format("TOOLONGKEYWORD", FITK_STR, "x", ""), "fits: bad keyword");
  if !err_str_is(fits_card_format("bad", FITK_INT, "1", ""), "fits: bad keyword") {
    ok = false;
  }
  if !err_str_is(fits_card_format("END", FITK_STR, "x", ""), "fits: bad keyword") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", 9, "x", ""), "fits: bad kind") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", -1, "x", ""), "fits: bad kind") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_INT, "12x", ""), "fits: invalid integer") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_INT, "+", ""), "fits: invalid integer") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_REAL, "12", ""), "fits: invalid real") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_REAL, "1.2.3", ""), "fits: invalid real") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_REAL, "1E", ""), "fits: invalid real") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_REAL, ".", ""), "fits: invalid real") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_UNDEFINED, "x", ""), "fits: invalid value") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_STR, rep("x", 69), ""), "fits: card too long") {
    ok = false;
  }
  if !err_str_is(fits_card_format("K", FITK_LOGICAL, "T", sp(48)), "fits: card too long") {
    ok = false;
  }
  if !err_str_is(fits_card_format("", FITK_COMMENT, rep("x", 73), ""), "fits: card too long") {
    ok = false;
  }
  return assert(ok, "format rejects bad keywords/kinds/tokens and over-long cards");
}

fn t14() -> TestResult {
  var ok = true;
  let r1 = fits_card_format("SIMPLE", FITK_LOGICAL, "T", "file does conform to FITS standard");
  if !r1.is_ok {
    return assert(false, "logical card must format");
  }
  let c1: Str = r1.value;
  if !streq(c1, "SIMPLE  = " + sp(19) + "T" + " / file does conform to FITS standard" + sp(13)) {
    ok = false;
  }
  if c1.len() != 80 {
    ok = false;
  }
  let r2 = fits_card_format("OBJECT", FITK_STR, "M31", "object name");
  if !r2.is_ok {
    return assert(false, "string card must format");
  }
  let c2: Str = r2.value;
  if !streq(c2, "OBJECT  = " + "'M31'" + sp(15) + " / object name" + sp(36)) {
    ok = false;
  }
  if c2.len() != 80 {
    ok = false;
  }
  let r3 = fits_card_format("BITPIX", FITK_INT, "16", "");
  if !r3.is_ok {
    return assert(false, "integer card must format");
  }
  let c3: Str = r3.value;
  if !streq(c3, "BITPIX  = " + sp(18) + "16" + sp(50)) {
    ok = false;
  }
  if c3.len() != 80 {
    ok = false;
  }
  let r4 = fits_card_format("EXPTIME", FITK_REAL, "-1.5E+02", "seconds");
  if !r4.is_ok {
    return assert(false, "real card must format");
  }
  let c4: Str = r4.value;
  if !streq(c4, "EXPTIME = " + sp(12) + "-1.5E+02" + " / seconds" + sp(40)) {
    ok = false;
  }
  if c4.len() != 80 {
    ok = false;
  }
  let r5 = fits_card_format("", FITK_COMMENT, "hello", "");
  if !r5.is_ok {
    return assert(false, "comment card must format");
  }
  let c5: Str = r5.value;
  if !streq(c5, "COMMENT " + "hello" + sp(67)) {
    ok = false;
  }
  if c5.len() != 80 {
    ok = false;
  }
  let r6 = fits_card_format("", FITK_BLANK, "cont", "");
  if !r6.is_ok {
    return assert(false, "blank card must format");
  }
  let c6: Str = r6.value;
  if !streq(c6, sp(8) + "cont" + sp(68)) {
    ok = false;
  }
  if c6.len() != 80 {
    ok = false;
  }
  let r7 = fits_card_format("OBSERVER", FITK_STR, "O'HARA", "");
  if !r7.is_ok {
    return assert(false, "escaped string card must format");
  }
  let c7: Str = r7.value;
  if !streq(c7, "OBSERVER= " + "'O''HARA'" + sp(11) + sp(50)) {
    ok = false;
  }
  if c7.len() != 80 {
    ok = false;
  }
  return assert(ok, "fixed-width card formatting matches pinned 80-character output");
}

fn t15() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("UNDEF1  ="));
  cards.push(card80("UNDEF2  = / why not"));
  let data = pack_cards(cards);
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "undefined header must parse");
  }
  let h: FitsHeader = r.value;
  var ok = fits_kind(&h, 0) == FITK_UNDEFINED;
  if fits_kind(&h, 1) != FITK_UNDEFINED {
    ok = false;
  }
  if !opt_str_none(fits_value(&h, 0)) {
    ok = false;
  }
  if !streq(fits_comment(&h, 0), "") {
    ok = false;
  }
  if !streq(fits_comment(&h, 1), "why not") {
    ok = false;
  }
  var built = fits_new();
  if !ok_unit(fits_push_undefined(&mut built, "XPIXELS", "unknown")) {
    ok = false;
  }
  let bytes = fits_encode(&built);
  let r2 = fits_parse(&bytes);
  if !r2.is_ok {
    ok = false;
  } else {
    let h2: FitsHeader = r2.value;
    if fits_kind(&h2, 0) != FITK_UNDEFINED {
      ok = false;
    }
    if !streq(fits_comment(&h2, 0), "unknown") {
      ok = false;
    }
  }
  return assert(ok, "undefined values parse, format and round-trip");
}

fn t16() -> TestResult {
  var h = fits_new();
  var ok = fits_card_count(&h) == 0;
  if !ok_unit(fits_push_logical(&mut h, "SIMPLE", true, "file does conform to FITS standard")) {
    ok = false;
  }
  if !ok_unit(fits_push_int(&mut h, "BITPIX", "16", "number of bits per data pixel")) {
    ok = false;
  }
  if !ok_unit(fits_push_str(&mut h, "OBJECT", "M31", "object name")) {
    ok = false;
  }
  if !ok_unit(fits_push_str(&mut h, "OBSERVER", "O'Hara", "")) {
    ok = false;
  }
  if !ok_unit(fits_push_float(&mut h, "EXPTIME", "1.25E+01", "seconds")) {
    ok = false;
  }
  if !ok_unit(fits_push_comment(&mut h, "built by xiom.fits")) {
    ok = false;
  }
  if !ok_unit(fits_push_history(&mut h, "xiom.fits 0.1.0")) {
    ok = false;
  }
  if !ok_unit(fits_push_blank(&mut h, "continuation text")) {
    ok = false;
  }
  if !ok_unit(fits_push_undefined(&mut h, "XPIXELS", "not set")) {
    ok = false;
  }
  let bytes = fits_encode(&h);
  if bytes.len() != 2880 {
    ok = false;
  }
  let r = fits_parse(&bytes);
  if !r.is_ok {
    return assert(false, "round-trip header must parse");
  }
  let h2: FitsHeader = r.value;
  if fits_card_count(&h2) != 9 {
    ok = false;
  }
  if !opt_bool_is(fits_bool_value(&h2, "SIMPLE"), true) {
    ok = false;
  }
  if !opt_str_is(fits_int_token(&h2, "BITPIX"), "16") {
    ok = false;
  }
  if !opt_str_is(fits_str_value(&h2, "OBJECT"), "M31") {
    ok = false;
  }
  if !opt_str_is(fits_str_value(&h2, "OBSERVER"), "O'Hara") {
    ok = false;
  }
  if !opt_str_is(fits_float_token(&h2, "EXPTIME"), "1.25E+01") {
    ok = false;
  }
  if fits_kind(&h2, 5) != FITK_COMMENT {
    ok = false;
  }
  if !streq(fits_comment(&h2, 5), "built by xiom.fits") {
    ok = false;
  }
  if fits_kind(&h2, 6) != FITK_HISTORY {
    ok = false;
  }
  if fits_kind(&h2, 7) != FITK_BLANK {
    ok = false;
  }
  if fits_kind(&h2, 8) != FITK_UNDEFINED {
    ok = false;
  }
  if !streq(fits_comment(&h2, 8), "not set") {
    ok = false;
  }
  let again = fits_encode(&h2);
  if !bytes_equal(bytes, again) {
    ok = false;
  }
  return assert(ok, "builder -> encode -> parse round-trip preserves every card");
}

fn t17() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("SIMPLE  = " + sp(19) + "T / file does conform to FITS standard"));
  cards.push(card80("OBJECT  = 'M31'" + sp(15) + " / object name"));
  cards.push(card80("COMMENT   non-canonical   spacing   preserved"));
  cards.push(card80("NAXIS   = " + sp(20) + "0 / no data axes"));
  let data = pack_cards(cards);
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "header must parse");
  }
  let h: FitsHeader = r.value;
  let out = fits_encode(&h);
  return assert(bytes_equal(data, out), "parse -> encode reproduces the original header bytes");
}

fn t18() -> TestResult {
  var h = fits_new();
  var ok = true;
  var i = 0;
  while i < 40 {
    let kw = "CARD" + convert.int_to_string(i);
    if !ok_unit(fits_push_int(&mut h, kw, convert.int_to_string(i), "")) {
      ok = false;
    }
    i = i + 1;
  }
  let bytes = fits_encode(&h);
  if bytes.len() != 5760 {
    ok = false;
  }
  let r = fits_parse(&bytes);
  if !r.is_ok {
    return assert(false, "two-block header must parse");
  }
  let h2: FitsHeader = r.value;
  if fits_card_count(&h2) != 40 {
    ok = false;
  }
  if !streq(fits_keyword(&h2, 0), "CARD0") {
    ok = false;
  }
  if !streq(fits_keyword(&h2, 35), "CARD35") {
    ok = false;
  }
  if !streq(fits_keyword(&h2, 36), "CARD36") {
    ok = false;
  }
  if !opt_str_is(fits_int_token(&h2, "CARD39"), "39") {
    ok = false;
  }
  return assert(ok, "40 cards span two blocks; the boundary card is intact");
}

fn t19() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("SIMPLE  = " + sp(19) + "T"));
  let data = pack_cards(cards);
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "header must parse");
  }
  let h: FitsHeader = r.value;
  var ok = fits_card_count(&h) == 1;
  if !streq(fits_keyword(&h, -1), "") {
    ok = false;
  }
  if !streq(fits_keyword(&h, 1), "") {
    ok = false;
  }
  if fits_kind(&h, -1) != -1 {
    ok = false;
  }
  if fits_kind(&h, 1) != -1 {
    ok = false;
  }
  if !opt_str_none(fits_value(&h, -1)) {
    ok = false;
  }
  if !opt_str_none(fits_value(&h, 1)) {
    ok = false;
  }
  if !streq(fits_comment(&h, 1), "") {
    ok = false;
  }
  if !streq(fits_card(&h, 1), "") {
    ok = false;
  }
  if fits_find(&h, "MISSING") != -1 {
    ok = false;
  }
  if !opt_str_none(fits_str_value(&h, "SIMPLE")) {
    ok = false;
  }
  if !opt_str_none(fits_int_token(&h, "SIMPLE")) {
    ok = false;
  }
  if !opt_bool_none(fits_bool_value(&h, "MISSING")) {
    ok = false;
  }
  if !streq(fits_comment_of(&h, "MISSING"), "") {
    ok = false;
  }
  let e = fits_new();
  if fits_card_count(&e) != 0 {
    ok = false;
  }
  if fits_kind(&e, 0) != -1 {
    ok = false;
  }
  if !opt_str_none(fits_value(&e, 0)) {
    ok = false;
  }
  if fits_find(&e, "X") != -1 {
    ok = false;
  }
  return assert(ok, "out-of-range accessors and empty-header lookups are safe");
}

fn t20() -> TestResult {
  var cards = Vec[Str].new();
  cards.push(card80("NAXIS   = " + sp(20) + "1 / first"));
  cards.push(card80("NAXIS   = " + sp(20) + "2 / second"));
  cards.push(card80("NAME    = 'x'"));
  let data = pack_cards(cards);
  let r = fits_parse(&data);
  if !r.is_ok {
    return assert(false, "duplicate-keyword header must parse");
  }
  let h: FitsHeader = r.value;
  var ok = fits_card_count(&h) == 3;
  if fits_find(&h, "naxis") != 0 {
    ok = false;
  }
  if !opt_str_is(fits_int_token(&h, "NAXIS"), "1") {
    ok = false;
  }
  if !streq(fits_comment_of(&h, "NAXIS"), "first") {
    ok = false;
  }
  if fits_find(&h, "NAXIS ") != 0 {
    ok = false;
  }
  if !opt_str_none(fits_int_token(&h, "NAME")) {
    ok = false;
  }
  if !opt_str_none(fits_str_value(&h, "NAXIS")) {
    ok = false;
  }
  if !opt_bool_none(fits_bool_value(&h, "NAME")) {
    ok = false;
  }
  return assert(ok, "lookup is first-match and case-insensitive; accessors enforce kind");
}

fn main() -> Int {
  io.println("=== xiom.fits conformance tests ===");
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
    io.println("xiom.fits: all tests passed");
  } else {
    io.println("xiom.fits: tests failed");
  }
  return failed;
}
