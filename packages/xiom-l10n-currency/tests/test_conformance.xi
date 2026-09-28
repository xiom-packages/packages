// XIOM -- xiom.l10n-currency conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every table fixture (alpha, numeric, exponent, name, symbol) is
// taken from the ISO 4217 "List One" published 2026-09-17; the parse/format
// fixtures are hand-computed exact integer values, never floats. The
// table-integrity test walks every row through the public API and checks
// uniqueness, widths, exponent classes, ordering and the documented counts.
//
// BUG 17 note: all Str equality goes through str_compare (via streq); values
// read from Vec[Str] are always bound to typed locals before any comparison.
//
// Compiler note: test dispatch is a direct call chain (t1..t21 from main),
// never a Vec[fn] table. The parallel Vecs of the integrity test are pushed
// in one arm per row so they cannot drift.

module l10n_currency_tests
use xiom.io; use xiom.test;
use xiom.l10n.currency;
use xiom.string.compare;
use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Result probes (never compare Str with ==; always return typed locals)
// ---------------------------------------------------------------------------

fn alpha_of(code: Str) -> Str {
  match l10n_currency_by_alpha(code) {
    Ok(c) => { let a: Str = c.alpha; return a; },
    Err(e) => { return ""; },
  }
  return "";
}

fn num_of(code: Str) -> Str {
  match l10n_currency_by_alpha(code) {
    Ok(c) => { let n: Str = c.numeric; return n; },
    Err(e) => { return ""; },
  }
  return "";
}

fn exp_of(code: Str) -> Int {
  match l10n_currency_by_alpha(code) {
    Ok(c) => { let x: Int = c.exponent; return x; },
    Err(e) => { return -1; },
  }
  return -1;
}

fn name_of(code: Str) -> Str {
  match l10n_currency_by_alpha(code) {
    Ok(c) => { let n: Str = c.name; return n; },
    Err(e) => { return ""; },
  }
  return "";
}

fn sym_of(code: Str) -> Str {
  match l10n_currency_by_alpha(code) {
    Ok(c) => { let s: Str = c.symbol; return s; },
    Err(e) => { return ""; },
  }
  return "";
}

fn alpha_err_is(code: Str, want: Str) -> Bool {
  match l10n_currency_by_alpha(code) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn numeric_of(code: Str) -> Str {
  match l10n_currency_by_numeric(code) {
    Ok(c) => { let a: Str = c.alpha; return a; },
    Err(e) => { return ""; },
  }
  return "";
}

fn numeric_err_is(code: Str, want: Str) -> Bool {
  match l10n_currency_by_numeric(code) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn name_lookup_alpha(name: Str) -> Str {
  match l10n_currency_by_name(name) {
    Ok(c) => { let a: Str = c.alpha; return a; },
    Err(e) => { return ""; },
  }
  return "";
}

fn name_err_is(name: Str, want: Str) -> Bool {
  match l10n_currency_by_name(name) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn symbol_lookup_alpha(sym: Str) -> Str {
  match l10n_currency_by_symbol(sym) {
    Ok(c) => { let a: Str = c.alpha; return a; },
    Err(e) => { return ""; },
  }
  return "";
}

fn symbol_err_is(sym: Str, want: Str) -> Bool {
  match l10n_currency_by_symbol(sym) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn at_alpha(index: Int) -> Str {
  match l10n_currency_at(index) {
    Ok(c) => { let a: Str = c.alpha; return a; },
    Err(e) => { return ""; },
  }
  return "";
}

fn at_err_is(index: Int, want: Str) -> Bool {
  match l10n_currency_at(index) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Parse / format probes
// ---------------------------------------------------------------------------

fn parse_is(text: Str, code: Str, dsep: Str, gsep: Str, want: Int) -> Bool {
  match l10n_currency_parse_amount_code(text, code, dsep, gsep) {
    Ok(m) => { let v: Int = l10n_currency_money_minor(&m); return v == want; },
    Err(e) => { return false; },
  }
  return false;
}

fn parse_err_is(text: Str, code: Str, dsep: Str, gsep: Str, want: Str) -> Bool {
  match l10n_currency_parse_amount_code(text, code, dsep, gsep) {
    Ok(m) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn parse_exp_of(text: Str, code: Str, dsep: Str, gsep: Str) -> Int {
  match l10n_currency_parse_amount_code(text, code, dsep, gsep) {
    Ok(m) => { let x: Int = l10n_currency_money_exponent(&m); return x; },
    Err(e) => { return -1; },
  }
  return -1;
}

fn fmt_is(minor: Int, code: Str, gsep: Str, dsep: Str, use_sym: Bool, parens: Bool, want: Str) -> Bool {
  let m = Money{ alpha: code; minor: minor; exponent: 0 };
  match l10n_currency_format_amount(&m, gsep, dsep, use_sym, parens) {
    Ok(s) => { return streq(s, want); },
    Err(e) => { return false; },
  }
  return false;
}

fn fmt_err_is(minor: Int, code: Str, want: Str) -> Bool {
  let m = Money{ alpha: code; minor: minor; exponent: 0 };
  match l10n_currency_format_amount(&m, ",", ".", false, false) {
    Ok(s) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn roundtrip_is(text: Str, code: Str, dsep: Str, gsep: Str, use_sym: Bool, want: Str) -> Bool {
  match l10n_currency_parse_amount_code(text, code, dsep, gsep) {
    Ok(m) => {
      match l10n_currency_format_amount(&m, gsep, dsep, use_sym, false) {
        Ok(s) => { return streq(s, want); },
        Err(e) => { return false; },
      }
    },
    Err(e) => { return false; },
  }
  return false;
}

fn round_to_is(scaled: Int, from_dec: Int, code: Str, want: Int) -> Bool {
  match l10n_currency_by_alpha(code) {
    Ok(c) => {
      let cur = c;
      match l10n_currency_round_to_currency(scaled, from_dec, &cur) {
        Ok(v) => { return v == want; },
        Err(e) => { return false; },
      }
    },
    Err(e) => { return false; },
  }
  return false;
}

fn round_to_err_is(scaled: Int, from_dec: Int, code: Str, want: Str) -> Bool {
  match l10n_currency_by_alpha(code) {
    Ok(c) => {
      let cur = c;
      match l10n_currency_round_to_currency(scaled, from_dec, &cur) {
        Ok(v) => { return false; },
        Err(e) => { return streq(e, want); },
      }
    },
    Err(e) => { return false; },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = exp_of("JPY") == 0;
  if exp_of("KRW") != 0 { ok = false; }
  if exp_of("CLP") != 0 { ok = false; }
  if exp_of("ISK") != 0 { ok = false; }
  if exp_of("VND") != 0 { ok = false; }
  if exp_of("XOF") != 0 { ok = false; }
  if exp_of("XAF") != 0 { ok = false; }
  if exp_of("XPF") != 0 { ok = false; }
  if exp_of("BIF") != 0 { ok = false; }
  if exp_of("PYG") != 0 { ok = false; }
  if exp_of("UGX") != 0 { ok = false; }
  if exp_of("UYI") != 0 { ok = false; }
  if exp_of("VUV") != 0 { ok = false; }
  if exp_of("RWF") != 0 { ok = false; }
  if exp_of("GNF") != 0 { ok = false; }
  if exp_of("DJF") != 0 { ok = false; }
  if exp_of("KMF") != 0 { ok = false; }
  return assert(ok, "exponent 0: the 17 zero-decimal currencies of the table");
}

fn t2() -> TestResult {
  var ok = exp_of("USD") == 2;
  if exp_of("EUR") != 2 { ok = false; }
  if exp_of("GBP") != 2 { ok = false; }
  if exp_of("CNY") != 2 { ok = false; }
  if exp_of("BHD") != 3 { ok = false; }
  if exp_of("IQD") != 3 { ok = false; }
  if exp_of("JOD") != 3 { ok = false; }
  if exp_of("KWD") != 3 { ok = false; }
  if exp_of("LYD") != 3 { ok = false; }
  if exp_of("OMR") != 3 { ok = false; }
  if exp_of("TND") != 3 { ok = false; }
  if exp_of("CLF") != 4 { ok = false; }
  if exp_of("UYW") != 4 { ok = false; }
  return assert(ok, "exponents 2/3/4: the three-decimal set and the two four-decimal funds codes");
}

fn t3() -> TestResult {
  var ok = streq(alpha_of("USD"), "USD");
  if !streq(alpha_of("usd"), "USD") { ok = false; }
  if !streq(alpha_of("UsD"), "USD") { ok = false; }
  if !streq(alpha_of("EUR"), "EUR") { ok = false; }
  if !streq(alpha_of("JPY"), "JPY") { ok = false; }
  if !streq(alpha_of("ZWG"), "ZWG") { ok = false; }
  if !l10n_currency_is_valid("GBP") { ok = false; }
  if l10n_currency_is_valid("ZZZ") { ok = false; }
  if l10n_currency_is_valid("US") { ok = false; }
  if l10n_currency_is_valid("") { ok = false; }
  if !alpha_err_is("ZZZ", "l10n-currency: unknown currency: ZZZ") { ok = false; }
  if !alpha_err_is("XAU", "l10n-currency: unknown currency: XAU") { ok = false; }
  if !alpha_err_is("US", "l10n-currency: bad currency code: US") { ok = false; }
  if !alpha_err_is("US1", "l10n-currency: bad currency code: US1") { ok = false; }
  if !alpha_err_is("", "l10n-currency: bad currency code: ") { ok = false; }
  return assert(ok, "lookup by alpha: case-insensitive, validity, malformed and unknown errors");
}

fn t4() -> TestResult {
  var ok = streq(numeric_of("840"), "USD");
  if !streq(numeric_of("978"), "EUR") { ok = false; }
  if !streq(numeric_of("008"), "ALL") { ok = false; }
  if !streq(numeric_of("392"), "JPY") { ok = false; }
  if !streq(numeric_of("048"), "BHD") { ok = false; }
  if !streq(numeric_of("990"), "CLF") { ok = false; }
  if !streq(numeric_of("532"), "XCG") { ok = false; }
  if !numeric_err_is("84", "l10n-currency: bad numeric code: 84") { ok = false; }
  if !numeric_err_is("8A0", "l10n-currency: bad numeric code: 8A0") { ok = false; }
  if !numeric_err_is("999", "l10n-currency: unknown numeric code: 999") { ok = false; }
  if !numeric_err_is("959", "l10n-currency: unknown numeric code: 959") { ok = false; }
  return assert(ok, "lookup by numeric: zero-padded match, width/charset errors, cut-off codes absent");
}

fn t5() -> TestResult {
  var ok = streq(name_lookup_alpha("US Dollar"), "USD");
  if !streq(name_lookup_alpha("us dollar"), "USD") { ok = false; }
  if !streq(name_lookup_alpha("Euro"), "EUR") { ok = false; }
  if !streq(name_lookup_alpha("Yen"), "JPY") { ok = false; }
  if !streq(name_lookup_alpha("Pound Sterling"), "GBP") { ok = false; }
  if !streq(name_lookup_alpha("Swiss Franc"), "CHF") { ok = false; }
  if !name_err_is("Nonexistent", "l10n-currency: unknown currency name: Nonexistent") { ok = false; }
  if !name_err_is("", "l10n-currency: unknown currency name: ") { ok = false; }
  return assert(ok, "lookup by name: exact English names, ASCII case-insensitive, unknown error");
}

fn t6() -> TestResult {
  var ok = streq(symbol_lookup_alpha("$"), "USD");
  if !streq(symbol_lookup_alpha("€"), "EUR") { ok = false; }
  if !streq(symbol_lookup_alpha("£"), "GBP") { ok = false; }
  if !streq(symbol_lookup_alpha("¥"), "JPY") { ok = false; }
  if !streq(symbol_lookup_alpha("₹"), "INR") { ok = false; }
  if !streq(symbol_lookup_alpha("₩"), "KRW") { ok = false; }
  if !symbol_err_is("xx", "l10n-currency: unknown currency symbol: xx") { ok = false; }
  if !symbol_err_is("", "l10n-currency: bad symbol: ") { ok = false; }
  return assert(ok, "lookup by symbol: majors resolve, unknown and empty symbols error");
}

fn t7() -> TestResult {
  var ok = l10n_currency_cross_check("USD", "840");
  if !l10n_currency_cross_check("usd", "840") { ok = false; }
  if l10n_currency_cross_check("USD", "978") { ok = false; }
  if l10n_currency_cross_check("ZZZ", "840") { ok = false; }
  if l10n_currency_cross_check("USD", "84") { ok = false; }
  if !l10n_currency_cross_check("XCG", "532") { ok = false; }
  return assert(ok, "alpha<->numeric cross-check: matches, mismatches and malformed inputs");
}

fn t8() -> TestResult {
  var ok = l10n_currency_count() == 165;
  if !streq(at_alpha(0), "AED") { ok = false; }
  if !streq(at_alpha(164), "ZWG") { ok = false; }
  if !at_err_is(165, "l10n-currency: index out of range: 165") { ok = false; }
  if !at_err_is(-1, "l10n-currency: index out of range: -1") { ok = false; }
  return assert(ok, "count and index access: 0..164, out-of-range errors, AED first / ZWG last");
}

fn t9() -> TestResult {
  var alphas = Vec[Str].new();
  var nums = Vec[Str].new();
  var exps = Vec[Int].new();
  var names = Vec[Str].new();
  var syms = Vec[Str].new();
  var ok = true;
  var i = 0;
  while i < l10n_currency_count() {
    match l10n_currency_at(i) {
      Ok(c) => {
        let a: Str = c.alpha;
        let n: Str = c.numeric;
        let e: Int = c.exponent;
        let nm: Str = c.name;
        let s: Str = c.symbol;
        alphas.push(a);
        nums.push(n);
        exps.push(e);
        names.push(nm);
        syms.push(s);
      },
      Err(e) => { ok = false; },
    }
    i = i + 1;
  }
  if alphas.len() != 165 { ok = false; }
  if nums.len() != 165 { ok = false; }
  if exps.len() != 165 { ok = false; }
  if names.len() != 165 { ok = false; }
  if syms.len() != 165 { ok = false; }
  var count0 = 0;
  var count2 = 0;
  var count3 = 0;
  var count4 = 0;
  i = 0;
  while i < l10n_currency_count() {
    let a: Str = alphas[i];
    let n: Str = nums[i];
    let e: Int = exps[i];
    let nm: Str = names[i];
    if a.len() != 3 { ok = false; }
    if !l10n_currency_is_valid(a) { ok = false; }
    if n.len() != 3 { ok = false; }
    if !streq(numeric_of(n), a) { ok = false; }
    if nm.len() == 0 { ok = false; }
    if e == 0 { count0 = count0 + 1; }
    if e == 2 { count2 = count2 + 1; }
    if e == 3 { count3 = count3 + 1; }
    if e == 4 { count4 = count4 + 1; }
    if i > 0 {
      let prev: Str = alphas[i - 1];
      if compare.str_compare(prev, a) >= 0 { ok = false; }
    }
    i = i + 1;
  }
  if count0 != 17 { ok = false; }
  if count2 != 139 { ok = false; }
  if count3 != 7 { ok = false; }
  if count4 != 2 { ok = false; }
  var j = 0;
  while j < alphas.len() {
    var k = j + 1;
    while k < alphas.len() {
      let a1: Str = alphas[j];
      let a2: Str = alphas[k];
      if streq(a1, a2) { ok = false; }
      let n1: Str = nums[j];
      let n2: Str = nums[k];
      if streq(n1, n2) { ok = false; }
      let s1: Str = syms[j];
      let s2: Str = syms[k];
      if s1.len() > 0 && s2.len() > 0 && streq(s1, s2) { ok = false; }
      k = k + 1;
    }
    j = j + 1;
  }
  return assert(ok, "table integrity: 165 rows, unique alpha/numeric/symbol, widths, classes, order");
}

fn t10() -> TestResult {
  var ok = parse_is("1,234.56", "USD", ".", ",", 123456);
  if !parse_is("1.234,56", "USD", ",", ".", 123456) { ok = false; }
  if !parse_is("$1,234.56", "USD", ".", ",", 123456) { ok = false; }
  if !parse_is("USD 1,234.56", "USD", ".", ",", 123456) { ok = false; }
  if !parse_is("usd 1,234.56", "USD", ".", ",", 123456) { ok = false; }
  if !parse_is("1234.56", "USD", ".", "", 123456) { ok = false; }
  if !parse_is(".5", "USD", ".", "", 50) { ok = false; }
  if !parse_is("5.", "USD", ".", "", 500) { ok = false; }
  if !parse_is("1 234,56", "EUR", ",", " ", 123456) { ok = false; }
  if !parse_is("€1.234,56", "EUR", ",", ".", 123456) { ok = false; }
  return assert(ok, "parse exponent 2: separator pairs, symbol/code prefixes, partial fractions");
}

fn t11() -> TestResult {
  var ok = parse_is("-$5.00", "USD", ".", ",", 0 - 500);
  if !parse_is("-EUR 5,00", "EUR", ",", ".", 0 - 500) { ok = false; }
  if !parse_is("-1,234.56", "USD", ".", ",", 0 - 123456) { ok = false; }
  if !parse_is("+0.50", "USD", ".", "", 50) { ok = false; }
  if !parse_is("-0.00", "USD", ".", "", 0) { ok = false; }
  return assert(ok, "sign handling: leading sign before or after the prefix, -0 is 0, '+' ignored");
}

fn t12() -> TestResult {
  var ok = parse_is("1234", "JPY", ".", ",", 1234);
  if !parse_is("¥1,234", "JPY", ".", ",", 1234) { ok = false; }
  if !parse_is("JPY 1234", "JPY", ".", ",", 1234) { ok = false; }
  if !parse_is("1,234", "KRW", ".", ",", 1234) { ok = false; }
  if !parse_err_is("1.234", "JPY", ".", ",", "l10n-currency: too many decimals at byte 2") { ok = false; }
  return assert(ok, "parse exponent 0: whole units only, symbols/codes accepted, any fraction rejected");
}

fn t13() -> TestResult {
  var ok = parse_is("1.234", "BHD", ".", ",", 1234);
  if !parse_is("0.001", "BHD", ".", ",", 1) { ok = false; }
  if !parse_is("12.345", "KWD", ".", "", 12345) { ok = false; }
  if !parse_is("1,234.567", "TND", ".", ",", 1234567) { ok = false; }
  if !parse_err_is("1.2345", "BHD", ".", ",", "l10n-currency: too many decimals at byte 5") { ok = false; }
  return assert(ok, "parse exponent 3: three fraction digits, fourth digit rejected with its offset");
}

fn t14() -> TestResult {
  var ok = parse_is("1.2345", "CLF", ".", "", 12345);
  if !parse_is("0.0001", "UYW", ".", "", 1) { ok = false; }
  if !parse_is("100.0000", "CLF", ".", "", 1000000) { ok = false; }
  if !parse_err_is("1.23456", "CLF", ".", ",", "l10n-currency: too many decimals at byte 6") { ok = false; }
  return assert(ok, "parse exponent 4: four fraction digits, fifth digit rejected with its offset");
}

fn t15() -> TestResult {
  var ok = parse_err_is("", "USD", ".", ",", "l10n-currency: empty input");
  if !parse_err_is("abc", "USD", ".", ",", "l10n-currency: unexpected character at byte 0") { ok = false; }
  if !parse_err_is("1 234.56", "USD", ".", ",", "l10n-currency: unexpected character at byte 1") { ok = false; }
  if !parse_err_is("1.2.3", "USD", ".", ",", "l10n-currency: multiple decimal separators at byte 3") { ok = false; }
  if !parse_err_is("$", "USD", ".", ",", "l10n-currency: no digits at byte 1") { ok = false; }
  if !parse_err_is("99999999999999999999", "USD", ".", ",", "l10n-currency: number too large at byte 18") { ok = false; }
  return assert(ok, "parse errors carry byte offsets: unexpected char, second separator, no digits, overflow");
}

fn t16() -> TestResult {
  var ok = parse_err_is("92233720368547758.08", "USD", ".", ",", "l10n-currency: number too large at byte 20");
  if !parse_err_is("1.00", "us", ".", ",", "l10n-currency: bad currency code: us") { ok = false; }
  if !parse_err_is("1.00", "ZZZ", ".", ",", "l10n-currency: unknown currency: ZZZ") { ok = false; }
  if parse_exp_of("1.2345", "CLF", ".", "") != 4 { ok = false; }
  return assert(ok, "late overflow is reported at end of input; unknown parse codes fail via the lookup");
}

fn t17() -> TestResult {
  var ok = fmt_is(123456, "USD", ",", ".", false, false, "USD 1,234.56");
  if !fmt_is(123456, "USD", ",", ".", true, false, "$1,234.56") { ok = false; }
  if !fmt_is(-123456, "USD", ",", ".", true, false, "-$1,234.56") { ok = false; }
  if !fmt_is(-123456, "USD", ",", ".", true, true, "($1,234.56)") { ok = false; }
  if !fmt_is(-123456, "USD", ",", ".", false, true, "(USD 1,234.56)") { ok = false; }
  if !fmt_is(0, "USD", ",", ".", true, false, "$0.00") { ok = false; }
  if !fmt_is(5, "USD", ",", ".", true, false, "$0.05") { ok = false; }
  if !fmt_is(-5, "EUR", ".", ",", true, false, "-€0,05") { ok = false; }
  if !fmt_is(123456, "EUR", ".", ",", true, false, "€1.234,56") { ok = false; }
  if !fmt_is(123456, "USD", "", ".", false, false, "USD 1234.56") { ok = false; }
  return assert(ok, "format exponent 2: symbol/code, minus/parens, zero padding, locale separator swap");
}

fn t18() -> TestResult {
  var ok = fmt_is(1234, "JPY", ",", ".", true, false, "¥1,234");
  if !fmt_is(1234, "JPY", ",", ".", false, false, "JPY 1,234") { ok = false; }
  if !fmt_is(0, "JPY", ",", ".", false, false, "JPY 0") { ok = false; }
  if !fmt_is(1234, "BHD", ",", ".", false, false, "BHD 1.234") { ok = false; }
  if !fmt_is(1234, "TND", ",", ".", false, false, "TND 1.234") { ok = false; }
  if !fmt_is(12345, "CLF", ",", ".", false, false, "CLF 1.2345") { ok = false; }
  if !fmt_is(1, "CLF", ",", ".", false, false, "CLF 0.0001") { ok = false; }
  if !fmt_is(1, "UYW", ",", ".", false, false, "UYW 0.0001") { ok = false; }
  if !fmt_is(-1234, "KWD", ",", ".", false, true, "(KWD 1.234)") { ok = false; }
  if !fmt_is(1234, "TWD", ",", ".", true, false, "TWD 12.34") { ok = false; }
  return assert(ok, "format exponents 0/3/4: no separator, three and four fraction digits, symbol fallback");
}

fn t19() -> TestResult {
  var ok = fmt_err_is(1, "ZZZ", "l10n-currency: unknown currency: ZZZ");
  if !fmt_err_is(1, "us", "l10n-currency: bad currency code: us") { ok = false; }
  return assert(ok, "format errors: unknown and malformed alpha of a hand-built Money");
}

fn t20() -> TestResult {
  var ok = l10n_currency_round_half_up(25, 1, 0) == 3;
  if l10n_currency_round_half_up(0 - 25, 1, 0) != 0 - 3 { ok = false; }
  if l10n_currency_round_half_up(15, 1, 0) != 2 { ok = false; }
  if l10n_currency_round_half_up(0 - 15, 1, 0) != 0 - 2 { ok = false; }
  if l10n_currency_round_half_up(14, 1, 0) != 1 { ok = false; }
  if l10n_currency_round_half_up(0 - 14, 1, 0) != 0 - 1 { ok = false; }
  if l10n_currency_round_half_up(24, 1, 0) != 2 { ok = false; }
  if l10n_currency_round_half_up(0 - 24, 1, 0) != 0 - 2 { ok = false; }
  if l10n_currency_round_half_up(5, 1, 0) != 1 { ok = false; }
  if l10n_currency_round_half_up(0 - 5, 1, 0) != 0 - 1 { ok = false; }
  if l10n_currency_round_half_up(4, 1, 0) != 0 { ok = false; }
  if l10n_currency_round_half_up(0 - 1, 1, 0) != 0 { ok = false; }
  return assert(ok, "half-up rounding: halves away from zero for both signs, below-half goes to zero");
}

fn t21() -> TestResult {
  var ok = l10n_currency_round_half_up(995, 1, 0) == 100;
  if l10n_currency_round_half_up(0 - 995, 1, 0) != 0 - 100 { ok = false; }
  if l10n_currency_round_half_up(123456, 4, 2) != 1235 { ok = false; }
  if l10n_currency_round_half_up(0 - 123456, 4, 2) != 0 - 1235 { ok = false; }
  if l10n_currency_round_half_up(1234, 2, 2) != 1234 { ok = false; }
  if l10n_currency_round_half_up(1234, 2, 7) != 1234 { ok = false; }
  if l10n_currency_round_half_up(1234, 2, 0 - 1) != 12 { ok = false; }
  if l10n_currency_round_half_up(999999999999999999, 19, 0) != 0 { ok = false; }
  if l10n_currency_round_half_up(5000000000000000000, 19, 0) != 1 { ok = false; }
  if l10n_currency_round_half_up(0 - 5000000000000000000, 19, 0) != 0 - 1 { ok = false; }
  if l10n_currency_round_half_up(4999999999999999999, 19, 0) != 0 { ok = false; }
  return assert(ok, "half-up: carries, no-op scale, clamped negative counts, 19-digit drops");
}

fn t22() -> TestResult {
  var ok = round_to_is(123456, 6, "CLF", 1235);
  if !round_to_is(123456, 4, "USD", 1235) { ok = false; }
  if !round_to_is(5432, 4, "JPY", 1) { ok = false; }
  if !round_to_is(1234, 4, "JPY", 0) { ok = false; }
  if !round_to_is(0 - 123456, 4, "BHD", 0 - 12346) { ok = false; }
  if !round_to_err_is(1234, 1, "USD", "l10n-currency: scale up not supported: from 1 to 2") { ok = false; }
  return assert(ok, "round to a currency exponent: normal drops and the explicit scale-up refusal");
}

fn t23() -> TestResult {
  var ok = roundtrip_is("1,234.56", "USD", ".", ",", false, "USD 1,234.56");
  if !roundtrip_is("-€1.234,56", "EUR", ",", ".", true, "-€1.234,56") { ok = false; }
  if !roundtrip_is("¥1,234", "JPY", ".", ",", true, "¥1,234") { ok = false; }
  if !roundtrip_is("1.2345", "CLF", ".", ",", false, "CLF 1.2345") { ok = false; }
  if !roundtrip_is("1.234", "BHD", ".", ",", false, "BHD 1.234") { ok = false; }
  return assert(ok, "parse -> format round-trips for exponents 0/2/3/4 in both locale styles");
}

fn t24() -> TestResult {
  match l10n_currency_parse_amount_code("-0.00", "USD", ".", ",") {
    Ok(m) => {
      var ok = l10n_currency_money_minor(&m) == 0;
      let a: Str = l10n_currency_money_alpha(&m);
      if !streq(a, "USD") { ok = false; }
      if l10n_currency_money_exponent(&m) != 2 { ok = false; }
      if !parse_is("+USD 7.77", "USD", ".", "", 777) { ok = false; }
      return assert(ok, "money accessors: -0.00 is 0 with alpha/exponent captured, + prefix ignored");
    },
    Err(e) => { return assert(false, "money accessors: -0.00 must parse"); },
  }
  return assert(false, "money accessors: unreachable");
}

fn main() -> Int {
  io.println("=== xiom.l10n-currency conformance tests ===");
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
    io.println("xiom.l10n-currency: all tests passed");
  } else {
    io.println("xiom.l10n-currency: tests failed");
  }
  return failed;
}
