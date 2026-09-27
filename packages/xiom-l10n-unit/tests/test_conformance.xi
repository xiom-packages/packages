// XIOM -- xiom.l10n-unit conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every table factor is derived from the unit's definitional
// rational (SI exact values; lb = 0.45359237 kg; in = 0.0254 m; psi from
// lb*g0/in^2; cal = 4.184 J; BTU(IT) = 1055.05585262 J; hp = 550 ft*lbf/s).
// All expected values below are hand-computed exact integers, never floats.
//
// BUG 17 note: all Str equality goes through str_compare (via streq);
// values read from Vec[Str] are always bound to typed locals before any
// comparison.
//
// Compiler note: test dispatch is a direct call chain (t1..t24 from main),
// never a Vec[fn] table. The parallel Vecs of the integrity test are pushed
// in one arm per row so they cannot drift.

module l10n_unit_tests
use xiom.io; use xiom.test;
use xiom.l10n.unit;
use xiom.string.compare;

const _T_BAD: Int = 0 - 777777;
const _T_PARSE_BAD: Int = 0 - 888888;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Conversion probes
// ---------------------------------------------------------------------------

fn conv(v: Int, a: Str, b: Str) -> Int {
  match l10n_unit_convert_by_symbol(v, a, b) {
    Ok(x) => { return x; },
    Err(e) => { return _T_BAD; },
  }
  return _T_BAD;
}

fn conv_err_is(v: Int, a: Str, b: Str, want: Str) -> Bool {
  match l10n_unit_convert_by_symbol(v, a, b) {
    Ok(x) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// |v - back(v)| after a there-and-back conversion, or _T_BAD on error.
fn roundtrip_gap(v: Int, a: Str, b: Str) -> Int {
  match l10n_unit_convert_by_symbol(v, a, b) {
    Ok(fwd) => {
      match l10n_unit_convert_by_symbol(fwd, b, a) {
        Ok(back) => {
          let d = v - back;
          if d < 0 { return 0 - d; }
          return d;
        },
        Err(e) => { return _T_BAD; },
      }
    },
    Err(e) => { return _T_BAD; },
  }
  return _T_BAD;
}

fn gap_ok(v: Int, a: Str, b: Str, tol: Int) -> Bool {
  let g = roundtrip_gap(v, a, b);
  if g < 0 { return false; }
  return g <= tol;
}

fn row_of(s: Str) -> Unit {
  match l10n_unit_by_symbol(s) {
    Ok(u) => { return u; },
    Err(e) => { return Unit{ category: 0 - 1; symbol: ""; name: ""; num: 0; den: 0; offset: 0 }; },
  }
  return Unit{ category: 0 - 1; symbol: ""; name: ""; num: 0; den: 0; offset: 0 };
}

fn conv_rows(v: Int, a: &Unit, b: &Unit) -> Int {
  match l10n_unit_convert(v, a, b) {
    Ok(x) => { return x; },
    Err(e) => { return _T_BAD; },
  }
  return _T_BAD;
}

fn base_of(v: Int, s: Str) -> Int {
  let u = row_of(s);
  match l10n_unit_base_micro(v, &u) {
    Ok(x) => { return x; },
    Err(e) => { return _T_BAD; },
  }
  return _T_BAD;
}

fn compat(a: Str, b: Str) -> Bool {
  let ua = row_of(a);
  let ub = row_of(b);
  return l10n_unit_is_compatible(&ua, &ub);
}

// ---------------------------------------------------------------------------
// Lookup probes
// ---------------------------------------------------------------------------

fn sym_ok(s: Str) -> Bool {
  match l10n_unit_by_symbol(s) {
    Ok(u) => { let x: Str = u.symbol; return streq(x, s); },
    Err(e) => { return false; },
  }
  return false;
}

fn sym_err_is(s: Str, want: Str) -> Bool {
  match l10n_unit_by_symbol(s) {
    Ok(u) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn at_sym(i: Int) -> Str {
  match l10n_unit_at(i) {
    Ok(u) => { let s: Str = u.symbol; return s; },
    Err(e) => { return ""; },
  }
  return "";
}

fn at_err_is(i: Int, want: Str) -> Bool {
  match l10n_unit_at(i) {
    Ok(u) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn cat_at_sym(c: Int, i: Int) -> Str {
  match l10n_unit_at_in_category(c, i) {
    Ok(u) => { let s: Str = u.symbol; return s; },
    Err(e) => { return ""; },
  }
  return "";
}

fn cat_at_err_is(c: Int, i: Int, want: Str) -> Bool {
  match l10n_unit_at_in_category(c, i) {
    Ok(u) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn cat_name_is(c: Int, want: Str) -> Bool {
  match l10n_unit_category_name(c) {
    Ok(s) => { return streq(s, want); },
    Err(e) => { return false; },
  }
  return false;
}

fn cat_name_err_is(c: Int, want: Str) -> Bool {
  match l10n_unit_category_name(c) {
    Ok(s) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn cat_count_is(c: Int, want: Int) -> Bool {
  match l10n_unit_count_in_category(c) {
    Ok(n) => { return n == want; },
    Err(e) => { return false; },
  }
  return false;
}

fn cat_count_err_is(c: Int, want: Str) -> Bool {
  match l10n_unit_count_in_category(c) {
    Ok(n) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn sym_cat_ok(c: Int, s: Str) -> Bool {
  match l10n_unit_by_symbol_in_category(c, s) {
    Ok(u) => { let x: Str = u.symbol; return streq(x, s); },
    Err(e) => { return false; },
  }
  return false;
}

fn sym_cat_err_is(c: Int, s: Str, want: Str) -> Bool {
  match l10n_unit_by_symbol_in_category(c, s) {
    Ok(u) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Parse / format probes
// ---------------------------------------------------------------------------

fn parse_val(text: Str) -> Int {
  match l10n_unit_parse(text) {
    Ok(m) => { let v: Int = l10n_unit_measurement_value(&m); return v; },
    Err(e) => { return _T_PARSE_BAD; },
  }
  return _T_PARSE_BAD;
}

fn parse_sym(text: Str) -> Str {
  match l10n_unit_parse(text) {
    Ok(m) => { let s: Str = l10n_unit_measurement_symbol(&m); return s; },
    Err(e) => { return ""; },
  }
  return "";
}

fn parse_err_is(text: Str, want: Str) -> Bool {
  match l10n_unit_parse(text) {
    Ok(m) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn fmt_is(v: Int, s: Str, want: Str) -> Bool {
  match l10n_unit_format(v, s) {
    Ok(t) => { return streq(t, want); },
    Err(e) => { return false; },
  }
  return false;
}

fn fmt_err_is(v: Int, s: Str, want: Str) -> Bool {
  match l10n_unit_format(v, s) {
    Ok(t) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn parse_to_val(text: Str, target: Str) -> Int {
  match l10n_unit_parse_to(text, target) {
    Ok(x) => { return x; },
    Err(e) => { return _T_BAD; },
  }
  return _T_BAD;
}

fn parse_to_err_is(text: Str, target: Str, want: Str) -> Bool {
  match l10n_unit_parse_to(text, target) {
    Ok(x) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = l10n_unit_category_count() == 13;
  if !cat_name_is(0, "length") { ok = false; }
  if !cat_name_is(3, "temperature") { ok = false; }
  if !cat_name_is(12, "frequency") { ok = false; }
  if !cat_name_err_is(13, "l10n-unit: category out of range: 13") { ok = false; }
  if !cat_name_err_is(0 - 1, "l10n-unit: category out of range: -1") { ok = false; }
  if l10n_unit_count() != 82 { ok = false; }
  return assert(ok, "category metadata: 13 categories, names, out-of-range errors, 82 rows");
}

fn t2() -> TestResult {
  var ok = cat_count_is(0, 10);
  if !cat_count_is(1, 7) { ok = false; }
  if !cat_count_is(2, 8) { ok = false; }
  if !cat_count_is(3, 3) { ok = false; }
  if !cat_count_is(4, 8) { ok = false; }
  if !cat_count_is(5, 6) { ok = false; }
  if !cat_count_is(6, 4) { ok = false; }
  if !cat_count_is(7, 7) { ok = false; }
  if !cat_count_is(8, 7) { ok = false; }
  if !cat_count_is(9, 4) { ok = false; }
  if !cat_count_is(10, 10) { ok = false; }
  if !cat_count_is(11, 4) { ok = false; }
  if !cat_count_is(12, 4) { ok = false; }
  if !cat_count_err_is(13, "l10n-unit: category out of range: 13") { ok = false; }
  return assert(ok, "per-category counts: 10/7/8/3/8/6/4/7/7/4/10/4/4 and range error");
}

fn t3() -> TestResult {
  var ok = streq(at_sym(0), "m");
  if !streq(at_sym(9), "nmi") { ok = false; }
  if !streq(at_sym(25), "K") { ok = false; }
  if !streq(at_sym(81), "GHz") { ok = false; }
  if !at_err_is(82, "l10n-unit: index out of range: 82") { ok = false; }
  if !at_err_is(0 - 1, "l10n-unit: index out of range: -1") { ok = false; }
  if !streq(cat_at_sym(0, 0), "m") { ok = false; }
  if !streq(cat_at_sym(3, 0), "K") { ok = false; }
  if !streq(cat_at_sym(3, 2), "degF") { ok = false; }
  if !streq(cat_at_sym(12, 3), "GHz") { ok = false; }
  if !cat_at_err_is(3, 3, "l10n-unit: index out of range: 3") { ok = false; }
  if !cat_at_err_is(13, 0, "l10n-unit: category out of range: 13") { ok = false; }
  return assert(ok, "index access: global and category+index, range errors");
}

fn t4() -> TestResult {
  let km = row_of("km");
  let degf = row_of("degF");
  let ev = row_of("eV");
  var ok = l10n_unit_category(&km) == 0;
  if !streq(l10n_unit_symbol(&km), "km") { ok = false; }
  if !streq(l10n_unit_name(&km), "kilometer") { ok = false; }
  if l10n_unit_factor_num(&km) != 1000 { ok = false; }
  if l10n_unit_factor_den(&km) != 1 { ok = false; }
  if l10n_unit_offset(&km) != 0 { ok = false; }
  if l10n_unit_offset(&degf) != 459670000 { ok = false; }
  if l10n_unit_factor_num(&degf) != 5 { ok = false; }
  if l10n_unit_factor_den(&degf) != 9 { ok = false; }
  if l10n_unit_factor_den(&ev) != 6241509074460762607 { ok = false; }
  if !streq(l10n_unit_name(&row_of("gal-US")), "US gallon") { ok = false; }
  return assert(ok, "row accessors: category/symbol/name/num/den/offset");
}

fn t5() -> TestResult {
  var ok = conv(12500000, "mi", "km") == 20116800;
  if conv(20116800, "km", "mi") != 12500000 { ok = false; }
  if conv(1000000, "mi", "m") != 1609344000 { ok = false; }
  if conv(1000000, "ft", "in") != 12000000 { ok = false; }
  if conv(1000000, "yd", "ft") != 3000000 { ok = false; }
  if conv(1000000, "nmi", "m") != 1852000000 { ok = false; }
  if conv(1000000, "cm", "mm") != 10000000 { ok = false; }
  if conv(1000000, "um", "mm") != 1000 { ok = false; }
  return assert(ok, "length: mi/km exact both ways, ft/in, yd/ft, nmi/m, cm/mm, um/mm");
}

fn t6() -> TestResult {
  var ok = conv(1000000, "lb", "kg") == 453592;
  if conv(1000000, "kg", "lb") != 2204622 { ok = false; }
  if conv(1000000, "st", "lb") != 14000000 { ok = false; }
  if conv(1000000, "oz", "g") != 28349523 { ok = false; }
  if conv(1000000, "t", "kg") != 1000000000 { ok = false; }
  if conv(1000000, "mg", "kg") != 1 { ok = false; }
  if conv(1000000, "g", "mg") != 1000000000 { ok = false; }
  return assert(ok, "mass: lb/kg truncation snapshot, st/lb, oz/g, t/kg, mg/kg, g/mg");
}

fn t7() -> TestResult {
  var ok = conv(1000000, "gal-US", "l") == 3785411;
  if conv(4000000, "qt-US", "gal-US") != 1000000 { ok = false; }
  if conv(1000000, "gal-UK", "l") != 4546090 { ok = false; }
  if conv(1000000, "ml", "l") != 1000 { ok = false; }
  if conv(1000000, "m3", "l") != 1000000000 { ok = false; }
  if conv(16000000, "floz-US", "pt-US") != 1000000 { ok = false; }
  return assert(ok, "volume: US gallon to liter, qt/gal, UK gallon, ml/l, m3/l, floz/pt");
}

fn t8() -> TestResult {
  var ok = conv(1000000, "GiB", "B") == 1073741824000000;
  if conv(1000000, "GiB", "MiB") != 1024000000 { ok = false; }
  if conv(1000000, "TB", "GB") != 1000000000 { ok = false; }
  if conv(1000000, "B", "bit") != 8000000 { ok = false; }
  if conv(1000000, "KiB", "B") != 1024000000 { ok = false; }
  if conv(1000000, "TiB", "GiB") != 1024000000 { ok = false; }
  return assert(ok, "data: GiB/B exact (2^30 bytes), GiB/MiB 1024, TB/GB 1000, B/bit 8, binary chain");
}

fn t9() -> TestResult {
  var ok = conv(1000000, "psi", "kPa") == 6894757;
  if conv(1000000, "bar", "Pa") != 100000000000 { ok = false; }
  if conv(1000000, "atm", "Pa") != 101325000000 { ok = false; }
  if conv(1000000, "kPa", "mbar") != 10000000 { ok = false; }
  if conv(1000000, "mmHg", "Pa") != 133322387 { ok = false; }
  if conv(1000000, "psi", "bar") != 68947 { ok = false; }
  return assert(ok, "pressure: psi/kPa exact rational, bar/Pa, atm/Pa, kPa/mbar, mmHg/Pa, psi/bar");
}

fn t10() -> TestResult {
  var ok = conv(1000000, "kWh", "J") == 3600000000000;
  if conv(1000000, "kcal", "kJ") != 4184000 { ok = false; }
  if conv(1000000, "cal", "J") != 4184000 { ok = false; }
  if conv(1000000, "hp", "W") != 745699871 { ok = false; }
  if conv(1000000, "BTU", "J") != 1055055852 { ok = false; }
  if conv(1000000, "kJ", "cal") != 239005736 { ok = false; }
  return assert(ok, "energy and power: kWh/J, kcal/kJ, cal/J, hp/W, BTU/J, kJ/cal");
}

fn t11() -> TestResult {
  var ok = conv(1000000, "h", "min") == 60000000;
  if conv(1000000, "d", "h") != 24000000 { ok = false; }
  if conv(1000000, "wk", "d") != 7000000 { ok = false; }
  if conv(3600000, "km/h", "m/s") != 1000000 { ok = false; }
  if conv(1000000, "mph", "m/s") != 447040 { ok = false; }
  if conv(1000000, "kn", "km/h") != 1852000 { ok = false; }
  if conv(1000000, "acre", "m2") != 4046856422 { ok = false; }
  if conv(1000000, "ha", "m2") != 10000000000 { ok = false; }
  if conv(1000000, "GHz", "MHz") != 1000000000 { ok = false; }
  if conv(1000000, "turn", "deg") != 360000000 { ok = false; }
  if conv(1000000, "rad", "deg") != 57295779 { ok = false; }
  return assert(ok, "time, speed, area, frequency, angle: h/min, d/h, wk/d, km/h to m/s, mph, kn, acre, ha, GHz/MHz, turn/deg, rad/deg");
}

fn t12() -> TestResult {
  var ok = conv(0, "degC", "K") == 273150000;
  if conv(100000000, "degC", "K") != 373150000 { ok = false; }
  if conv(0, "K", "degC") != 0 - 273150000 { ok = false; }
  if conv(32000000, "degF", "degC") != 0 { ok = false; }
  if conv(212000000, "degF", "degC") != 100000000 { ok = false; }
  if conv(0 - 40000000, "degF", "degC") != 0 - 40000000 { ok = false; }
  if conv(100000000, "degC", "degF") != 212000000 { ok = false; }
  if conv(0, "degC", "degF") != 32000000 { ok = false; }
  if conv(0 - 273150000, "degC", "K") != 0 { ok = false; }
  if conv(0 - 459670000, "degF", "K") != 0 { ok = false; }
  if conv(0, "K", "degF") != 0 - 459670000 { ok = false; }
  return assert(ok, "temperature affine: 0/100 degC, 32/212/-40 degF, absolute zero in all three scales");
}

fn t13() -> TestResult {
  var ok = gap_ok(12500000, "km", "mi", 9);
  if !gap_ok(1000000, "lb", "kg", 9) { ok = false; }
  if !gap_ok(1000000, "gal-US", "l", 9) { ok = false; }
  if !gap_ok(1000000, "psi", "kPa", 9) { ok = false; }
  if !gap_ok(1000000, "kWh", "J", 0) { ok = false; }
  if !gap_ok(1000000, "GiB", "B", 0) { ok = false; }
  if !gap_ok(1000000, "mph", "m/s", 0) { ok = false; }
  if !gap_ok(212000000, "degF", "degC", 0) { ok = false; }
  if !gap_ok(300000000, "K", "degC", 0) { ok = false; }
  if !gap_ok(1000000, "turn", "deg", 0) { ok = false; }
  return assert(ok, "round-trip: exact for exact-ratio pairs, <=9 micro tolerance for truncating pairs");
}

fn t14() -> TestResult {
  var ok = conv(9223372036854775, "m", "mm") == 9223372036854775000;
  if !conv_err_is(9223372036854776, "m", "mm", "l10n-unit: conversion overflow") { ok = false; }
  if !conv_err_is(9223372036854775807, "m", "um", "l10n-unit: conversion overflow") { ok = false; }
  if !conv_err_is(1000000, "J", "eV", "l10n-unit: conversion overflow") { ok = false; }
  if !conv_err_is(1, "kWh", "eV", "l10n-unit: conversion overflow") { ok = false; }
  if conv(1000000, "eV", "J") != 0 { ok = false; }
  if conv(0, "m", "km") != 0 { ok = false; }
  return assert(ok, "overflow boundaries: last representable product passes, the next is a typed error, eV limits documented");
}

fn t15() -> TestResult {
  var ok = conv_err_is(1, "m", "kg", "l10n-unit: category mismatch: m (length) -> kg (mass)");
  if !conv_err_is(1, "degC", "ft", "l10n-unit: category mismatch: degC (temperature) -> ft (length)") { ok = false; }
  if !conv_err_is(1, "m", "M", "l10n-unit: unknown unit: M") { ok = false; }
  if !conv_err_is(1, "", "m", "l10n-unit: bad symbol: ") { ok = false; }
  if !conv_err_is(1, "m", "", "l10n-unit: bad symbol: ") { ok = false; }
  if !sym_ok("min") { ok = false; }
  if !sym_ok("mmHg") { ok = false; }
  if sym_ok("M") { ok = false; }
  if sym_ok("MM") { ok = false; }
  if !sym_err_is("zz", "l10n-unit: unknown unit: zz") { ok = false; }
  if !sym_cat_ok(1, "kg") { ok = false; }
  if !sym_cat_err_is(1, "m", "l10n-unit: unknown unit in mass: m") { ok = false; }
  if !sym_cat_err_is(13, "m", "l10n-unit: category out of range: 13") { ok = false; }
  return assert(ok, "typed errors: category mismatch text, case-sensitive unknown symbols, in-category lookup");
}

fn t16() -> TestResult {
  var ok = parse_val("12.5 km/h") == 12500000;
  if !streq(parse_sym("12.5 km/h"), "km/h") { ok = false; }
  if parse_val("0.5m") != 500000 { ok = false; }
  if parse_val(" 3 ft ") != 3000000 { ok = false; }
  if parse_val("-40 degC") != 0 - 40000000 { ok = false; }
  if parse_val("+7 m") != 7000000 { ok = false; }
  if parse_val(".5 s") != 500000 { ok = false; }
  if parse_val("5. m") != 5000000 { ok = false; }
  if parse_val("1.0000009 m") != 1000000 { ok = false; }
  if parse_val("-0 K") != 0 { ok = false; }
  if !parse_err_is("1e3 m", "l10n-unit: unknown unit: e3 m at byte 1") { ok = false; }
  return assert(ok, "parse: number+symbol grammar, signs, empty integer part, micro truncation, symbol tail");
}

fn t17() -> TestResult {
  var ok = parse_err_is("", "l10n-unit: empty input");
  if !parse_err_is("   ", "l10n-unit: no digits at byte 3") { ok = false; }
  if !parse_err_is("m", "l10n-unit: no digits at byte 0") { ok = false; }
  if !parse_err_is("abc m", "l10n-unit: no digits at byte 0") { ok = false; }
  if !parse_err_is("1.2.3 m", "l10n-unit: multiple decimal separators at byte 3") { ok = false; }
  if !parse_err_is("1 ZZZ", "l10n-unit: unknown unit: ZZZ at byte 2") { ok = false; }
  if !parse_err_is("12.5", "l10n-unit: missing unit at byte 4") { ok = false; }
  if !parse_err_is("12.5 ", "l10n-unit: missing unit at byte 5") { ok = false; }
  if !parse_err_is("+ m", "l10n-unit: no digits at byte 2") { ok = false; }
  if !parse_err_is("99999999999999999999 m", "l10n-unit: number too large at byte 18") { ok = false; }
  return assert(ok, "parse errors carry byte offsets: empty, no digits, second separator, unknown unit, missing unit, overflow");
}

fn t18() -> TestResult {
  var ok = fmt_is(12500000, "km/h", "12.5 km/h");
  if !fmt_is(0, "m", "0 m") { ok = false; }
  if !fmt_is(0 - 500000, "h", "-0.5 h") { ok = false; }
  if !fmt_is(1, "m", "0.000001 m") { ok = false; }
  if !fmt_is(10, "m", "0.00001 m") { ok = false; }
  if !fmt_is(1000000, "s", "1 s") { ok = false; }
  if !fmt_is(123456789, "m", "123.456789 m") { ok = false; }
  if !fmt_is(0 - 1000000, "m", "-1 m") { ok = false; }
  if !fmt_err_is(1, "ZZZ", "l10n-unit: unknown unit: ZZZ") { ok = false; }
  if !fmt_err_is(1, "", "l10n-unit: bad symbol: ") { ok = false; }
  return assert(ok, "format: integer and fractional rendering, trailing zeros trimmed, sign, unknown symbol");
}

fn t19() -> TestResult {
  var ok = parse_to_val("12.5 km/h", "mph") == 7767139;
  if parse_to_val("100 degC", "degF") != 212000000 { ok = false; }
  if parse_to_val("1 GiB", "MiB") != 1024000000 { ok = false; }
  if !parse_to_err_is("1 m", "kg", "l10n-unit: category mismatch: m (length) -> kg (mass)") { ok = false; }
  if !parse_to_err_is("bogus", "m", "l10n-unit: no digits at byte 0") { ok = false; }
  if !parse_to_err_is("1 m", "ZZZ", "l10n-unit: unknown unit: ZZZ") { ok = false; }
  return assert(ok, "parse_to: measurement cross-conversion and the parse/convert/target error paths");
}

fn t20() -> TestResult {
  var syms = Vec[Str].new();
  var cats = Vec[Int].new();
  var nums = Vec[Int].new();
  var dens = Vec[Int].new();
  var offs = Vec[Int].new();
  var ok = true;
  var i = 0;
  while i < l10n_unit_count() {
    match l10n_unit_at(i) {
      Ok(u) => {
        let s: Str = u.symbol;
        let c: Int = u.category;
        let n: Int = u.num;
        let d: Int = u.den;
        let o: Int = u.offset;
        syms.push(s);
        cats.push(c);
        nums.push(n);
        dens.push(d);
        offs.push(o);
      },
      Err(e) => { ok = false; },
    }
    i = i + 1;
  }
  if syms.len() != 82 { ok = false; }
  if cats.len() != 82 { ok = false; }
  if nums.len() != 82 { ok = false; }
  if dens.len() != 82 { ok = false; }
  if offs.len() != 82 { ok = false; }
  var c0 = 0;
  var c1 = 0;
  var c2 = 0;
  var c3 = 0;
  var c4 = 0;
  var c5 = 0;
  var c6 = 0;
  var c7 = 0;
  var c8 = 0;
  var c9 = 0;
  var c10 = 0;
  var c11 = 0;
  var c12 = 0;
  i = 0;
  while i < l10n_unit_count() {
    let s: Str = syms[i];
    let c: Int = cats[i];
    let n: Int = nums[i];
    let d: Int = dens[i];
    let o: Int = offs[i];
    if s.len() == 0 { ok = false; }
    if n <= 0 { ok = false; }
    if d <= 0 { ok = false; }
    if c < 0 { ok = false; }
    if c >= l10n_unit_category_count() { ok = false; }
    if c != 3 {
      if o != 0 { ok = false; }
    }
    if !sym_ok(s) { ok = false; }
    if c == 0 { c0 = c0 + 1; }
    if c == 1 { c1 = c1 + 1; }
    if c == 2 { c2 = c2 + 1; }
    if c == 3 { c3 = c3 + 1; }
    if c == 4 { c4 = c4 + 1; }
    if c == 5 { c5 = c5 + 1; }
    if c == 6 { c6 = c6 + 1; }
    if c == 7 { c7 = c7 + 1; }
    if c == 8 { c8 = c8 + 1; }
    if c == 9 { c9 = c9 + 1; }
    if c == 10 { c10 = c10 + 1; }
    if c == 11 { c11 = c11 + 1; }
    if c == 12 { c12 = c12 + 1; }
    i = i + 1;
  }
  if c0 != 10 { ok = false; }
  if c1 != 7 { ok = false; }
  if c2 != 8 { ok = false; }
  if c3 != 3 { ok = false; }
  if c4 != 8 { ok = false; }
  if c5 != 6 { ok = false; }
  if c6 != 4 { ok = false; }
  if c7 != 7 { ok = false; }
  if c8 != 7 { ok = false; }
  if c9 != 4 { ok = false; }
  if c10 != 10 { ok = false; }
  if c11 != 4 { ok = false; }
  if c12 != 4 { ok = false; }
  var j = 0;
  while j < syms.len() {
    var k = j + 1;
    while k < syms.len() {
      let s1: Str = syms[j];
      let s2: Str = syms[k];
      if streq(s1, s2) { ok = false; }
      k = k + 1;
    }
    j = j + 1;
  }
  let krow = row_of("K");
  let crow = row_of("degC");
  let frow = row_of("degF");
  if l10n_unit_offset(&krow) != 0 { ok = false; }
  if l10n_unit_offset(&crow) != 273150000 { ok = false; }
  if l10n_unit_offset(&frow) != 459670000 { ok = false; }
  return assert(ok, "table integrity: 82 rows, unique symbols, positive factors, non-zero denominators, offsets only on temperature");
}

fn t21() -> TestResult {
  var ok = base_of(1000000, "mi") == 1609344000;
  if base_of(1000000, "km") != 1000000000 { ok = false; }
  if base_of(1000000, "degC") != 274150000 { ok = false; }
  if base_of(32000000, "degF") != 273150000 { ok = false; }
  if base_of(0 - 459670000, "degF") != 0 { ok = false; }
  if base_of(1000000, "K") != 1000000 { ok = false; }
  if !compat("m", "km") { ok = false; }
  if compat("m", "kg") { ok = false; }
  if !compat("degC", "degF") { ok = false; }
  if !compat("J", "eV") { ok = false; }
  let km = row_of("km");
  let um = row_of("um");
  if conv_rows(1000000, &km, &um) != 1000000000000000 { ok = false; }
  return assert(ok, "base values and compatibility: mi/m, km/m, degC/K, degF/K affine at 32 degF, row-based convert");
}

fn t22() -> TestResult {
  var ok = conv(180000000, "deg", "rad") == 3141592;
  if conv(90000000, "deg", "rad") != 1570796 { ok = false; }
  if conv(100000000, "grad", "deg") != 90000000 { ok = false; }
  if conv(1000000, "turn", "grad") != 400000000 { ok = false; }
  if conv(360000000, "deg", "turn") != 1000000 { ok = false; }
  if conv(400000000, "grad", "turn") != 1000000 { ok = false; }
  if !gap_ok(1000000, "deg", "rad", 64) { ok = false; }
  if !gap_ok(1000000, "turn", "grad", 0) { ok = false; }
  return assert(ok, "angle: documented pi rational, 180/90 deg to rad, turn/grad/deg exact ratios");
}

fn t23() -> TestResult {
  var ok = conv(1000000, "eV", "J") == 0;
  if conv(6241509074460762607, "eV", "J") != 1 { ok = false; }
  if !conv_err_is(1000000, "J", "eV", "l10n-unit: conversion overflow") { ok = false; }
  if l10n_unit_factor_den(&row_of("eV")) != 6241509074460762607 { ok = false; }
  return assert(ok, "eV: documented reciprocal approximation, micro truncation to 0, overflow in the reverse direction");
}

fn t24() -> TestResult {
  var ok = conv(1, "m", "km") == 0;
  if conv(0 - 1, "m", "km") != 0 { ok = false; }
  if conv(999999, "m", "km") != 999 { ok = false; }
  if conv(1000000, "lb", "kg") != 453592 { ok = false; }
  if conv(1000000, "gal-US", "l") != 3785411 { ok = false; }
  if conv(1, "K", "degC") != 0 - 273149999 { ok = false; }
  if conv(500, "m", "um") != 500000000 { ok = false; }
  return assert(ok, "documented truncation toward zero: 1 micro-m is 0 km, both signs, exact snapshot values");
}

fn main() -> Int {
  io.println("=== xiom.l10n-unit conformance tests ===");
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
    io.println("xiom.l10n-unit: all tests passed");
  } else {
    io.println("xiom.l10n-unit: tests failed");
  }
  return failed;
}
