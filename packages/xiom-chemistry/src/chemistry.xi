// XIOM -- xiom.chemistry: chemical formula parsing, molar masses, mass fractions
// Port task: replace the xiom.chemistry placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: the element table is two parallel vectors -- `_table_symbols()`
// sorted byte-wise, `_table_masses_mg()` holding whole mg/mol in the same
// order. Formulas are handled by three independent linear scans over the
// input:
//   _chem_scan    -- validates the formula, returns the total molar mass;
//   _chem_collect -- validates the formula, returns the distinct symbols in
//                    first-seen order;
//   _count_atoms  -- validates the formula, returns the atom count of one
//                    target symbol.
// A group count is applied without a state struct or retroactive vector
// mutation: '(' pushes the running total on a Vec[Int] stack, ')' pops it and
// computes `saved + inner * count` (v0.61.3 has no Vec[StructType]). Scans
// build their own local vectors and never return a Vec that was filled through
// a `&mut` parameter (a v0.61.3 miscompile family).
//
// All masses are integer milligrams per mole (mg/mol): 1.008 g/mol -> 1008.
// See SPEC.md for the grammar, the full element table and the rounding rules.

module xiom.chemistry

use xiom.string;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Result constructors (compiler workaround; see xiom-patch/xiom-scheduler)
// ---------------------------------------------------------------------------

// XIOM v0.61.3 miscompiles direct Ok/Err construction in struct-returning
// functions; these leaf helpers keep construction in plain Result-returning
// functions.

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_vec(v: Vec[Str]) -> Result[Vec[Str], Str] { return Ok(v); }
fn _err_vec(m: Str) -> Result[Vec[Str], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Element table
// ---------------------------------------------------------------------------

// Symbols of the built-in table, sorted byte-wise (str_compare order).
// Masses live in the parallel _table_masses_mg() vector at the same index.
fn _table_symbols() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("Ag");
  v.push("Al");
  v.push("Ar");
  v.push("Au");
  v.push("B");
  v.push("Be");
  v.push("C");
  v.push("Ca");
  v.push("Cl");
  v.push("Cu");
  v.push("F");
  v.push("Fe");
  v.push("H");
  v.push("He");
  v.push("Hg");
  v.push("K");
  v.push("Li");
  v.push("Mg");
  v.push("N");
  v.push("Na");
  v.push("Ne");
  v.push("O");
  v.push("P");
  v.push("Pb");
  v.push("S");
  v.push("Si");
  v.push("Zn");
  return v;
}

// Whole mg/mol per symbol (same order as _table_symbols): the standard molar
// mass in g/mol times 1000, rounded half-up to the nearest whole mg. The
// comment states the g/mol value the entry was rounded from.
fn _table_masses_mg() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(107868);  // Ag 107.868
  v.push(26982);   // Al 26.982
  v.push(39948);   // Ar 39.948
  v.push(196967);  // Au 196.967
  v.push(10810);   // B 10.81
  v.push(9012);    // Be 9.012
  v.push(12011);   // C 12.011
  v.push(40078);   // Ca 40.078
  v.push(35453);   // Cl 35.453
  v.push(63546);   // Cu 63.546
  v.push(18998);   // F 18.998
  v.push(55845);   // Fe 55.845
  v.push(1008);    // H 1.008
  v.push(4003);    // He 4.0026
  v.push(200592);  // Hg 200.592
  v.push(39098);   // K 39.098
  v.push(6940);    // Li 6.94
  v.push(24305);   // Mg 24.305
  v.push(14007);   // N 14.007
  v.push(22990);   // Na 22.990
  v.push(20180);   // Ne 20.180
  v.push(15999);   // O 15.999
  v.push(30974);   // P 30.974
  v.push(207200);  // Pb 207.2
  v.push(32060);   // S 32.06
  v.push(28085);   // Si 28.085
  v.push(65380);   // Zn 65.38
  return v;
}

// ---------------------------------------------------------------------------
// Byte predicates and small scanners
// ---------------------------------------------------------------------------

// True for an ASCII decimal digit byte.
fn _is_digit(b: UInt8) -> Bool {
  return b >= 48 && b <= 57;
}

// True for an ASCII uppercase letter byte (a valid symbol start).
fn _is_upper(b: UInt8) -> Bool {
  return b >= 65 && b <= 90;
}

// True for an ASCII lowercase letter byte (an optional symbol second letter).
fn _is_lower(b: UInt8) -> Bool {
  return b >= 97 && b <= 122;
}

// Byte index just past the digit run starting at `start` (== start when none).
fn _digits_end(f: Str, start: Int) -> Int {
  let n = f.len();
  var j = start;
  while j < n {
    let b = string.byte_at(f, j);
    if !_is_digit(b) { break; }
    j = j + 1;
  }
  return j;
}

// Decimal value of f[start, end), a non-empty digit run.
fn _digits_value(f: Str, start: Int, end: Int) -> Int {
  var acc = 0;
  var j = start;
  while j < end {
    acc = acc * 10 + ((string.byte_at(f, j) as Int) - 48);
    j = j + 1;
  }
  return acc;
}

// One-byte slice used in "unexpected character" error messages.
fn _char_at(f: Str, i: Int) -> Str {
  return string.str_slice(f, i, i + 1);
}

// Mass of `symbol` from the table; None for an unknown or non-exact symbol.
fn _element_mass(symbol: Str) -> Option[Int] {
  let syms = _table_symbols();
  let masses = _table_masses_mg();
  var i = 0;
  while i < syms.len() {
    // Typed local: a Vec[Str] element read straight into an expression can
    // carry a bogus length (BUG 17 family), so bind it first.
    let e: Str = syms[i];
    if compare.str_compare(e, symbol) == 0 {
      let m: Int = masses[i];
      return Some(m);
    }
    i = i + 1;
  }
  return None;
}

// ---------------------------------------------------------------------------
// Formula scans
// ---------------------------------------------------------------------------

// Scan `f`, returning its total molar mass in mg/mol. Validates the grammar:
// unknown symbols, unmatched ')', unclosed '(', empty groups, zero counts and
// unexpected characters are Err("chemistry: ...").
fn _chem_scan(f: Str) -> Result[Int, Str] {
  let n = f.len();
  if n == 0 { return _err_int("chemistry: empty formula"); }
  var groups = Vec[Int].new();
  var total = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(f, i);
    if b == 40 {
      groups.push(total);
      total = 0;
      i = i + 1;
    } elif b == 41 {
      var saved: Int = 0;
      match groups.pop() {
        Some(v) => { saved = v; },
        None => { return _err_int("chemistry: unmatched ')'"); },
      }
      let inner = total;
      if inner == 0 { return _err_int("chemistry: empty group"); }
      let d_end = _digits_end(f, i + 1);
      var factor = 1;
      if d_end > i + 1 { factor = _digits_value(f, i + 1, d_end); }
      if factor == 0 { return _err_int("chemistry: invalid count"); }
      total = saved + inner * factor;
      i = d_end;
    } else {
      if !_is_upper(b) { return _err_int("chemistry: unexpected character: " + _char_at(f, i)); }
      var j = i + 1;
      if j < n {
        let b2 = string.byte_at(f, j);
        if _is_lower(b2) { j = j + 1; }
      }
      let sym = string.str_slice(f, i, j);
      match _element_mass(sym) {
        Some(mass) => {
          let d_end = _digits_end(f, j);
          var count = 1;
          if d_end > j { count = _digits_value(f, j, d_end); }
          if count == 0 { return _err_int("chemistry: invalid count"); }
          total = total + mass * count;
          i = d_end;
        },
        None => { return _err_int("chemistry: unknown symbol: " + sym); },
      }
    }
  }
  if groups.len() != 0 { return _err_int("chemistry: unclosed '('"); }
  return _ok_int(total);
}

// Scan `f` and return its distinct symbols in first-seen order. Validates the
// same grammar as _chem_scan (same error catalog, with "chemistry: " prefix).
fn _chem_collect(f: Str) -> Result[Vec[Str], Str] {
  let n = f.len();
  if n == 0 { return _err_vec("chemistry: empty formula"); }
  var syms = Vec[Str].new();
  var groups = Vec[Int].new();
  var atoms = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(f, i);
    if b == 40 {
      groups.push(atoms);
      i = i + 1;
    } elif b == 41 {
      var opened: Int = 0;
      match groups.pop() {
        Some(v) => { opened = v; },
        None => { return _err_vec("chemistry: unmatched ')'"); },
      }
      if atoms == opened { return _err_vec("chemistry: empty group"); }
      let d_end = _digits_end(f, i + 1);
      if d_end > i + 1 {
        let factor = _digits_value(f, i + 1, d_end);
        if factor == 0 { return _err_vec("chemistry: invalid count"); }
      }
      i = d_end;
    } else {
      if !_is_upper(b) { return _err_vec("chemistry: unexpected character: " + _char_at(f, i)); }
      var j = i + 1;
      if j < n {
        let b2 = string.byte_at(f, j);
        if _is_lower(b2) { j = j + 1; }
      }
      let sym = string.str_slice(f, i, j);
      match _element_mass(sym) {
        Some(_) => {
          let d_end = _digits_end(f, j);
          if d_end > j {
            let count = _digits_value(f, j, d_end);
            if count == 0 { return _err_vec("chemistry: invalid count"); }
          }
          atoms = atoms + 1;
          var seen = false;
          var k = 0;
          while k < syms.len() {
            let e: Str = syms[k];
            if compare.str_compare(e, sym) == 0 { seen = true; break; }
            k = k + 1;
          }
          if !seen { syms.push(sym); }
          i = d_end;
        },
        None => { return _err_vec("chemistry: unknown symbol: " + sym); },
      }
    }
  }
  if groups.len() != 0 { return _err_vec("chemistry: unclosed '('"); }
  return _ok_vec(syms);
}

// Scan `f` and return the atom count of `target` (0 when it does not occur).
// Applies group counts with a Vec[Int] stack of running counts. Assumes the
// same grammar as _chem_scan; still validates symbols and parentheses.
fn _count_atoms(f: Str, target: Str) -> Result[Int, Str] {
  let n = f.len();
  if n == 0 { return _err_int("chemistry: empty formula"); }
  var groups = Vec[Int].new();
  var total = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(f, i);
    if b == 40 {
      groups.push(total);
      total = 0;
      i = i + 1;
    } elif b == 41 {
      var saved: Int = 0;
      match groups.pop() {
        Some(v) => { saved = v; },
        None => { return _err_int("chemistry: unmatched ')'"); },
      }
      let inner = total;
      let d_end = _digits_end(f, i + 1);
      var factor = 1;
      if d_end > i + 1 { factor = _digits_value(f, i + 1, d_end); }
      if factor == 0 { return _err_int("chemistry: invalid count"); }
      total = saved + inner * factor;
      i = d_end;
    } else {
      if !_is_upper(b) { return _err_int("chemistry: unexpected character: " + _char_at(f, i)); }
      var j = i + 1;
      if j < n {
        let b2 = string.byte_at(f, j);
        if _is_lower(b2) { j = j + 1; }
      }
      let sym = string.str_slice(f, i, j);
      match _element_mass(sym) {
        Some(_) => {
          let d_end = _digits_end(f, j);
          var count = 1;
          if d_end > j { count = _digits_value(f, j, d_end); }
          if count == 0 { return _err_int("chemistry: invalid count"); }
          if compare.str_compare(sym, target) == 0 { total = total + count; }
          i = d_end;
        },
        None => { return _err_int("chemistry: unknown symbol: " + sym); },
      }
    }
  }
  if groups.len() != 0 { return _err_int("chemistry: unclosed '('"); }
  return _ok_int(total);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Every element symbol in the built-in table, sorted byte-wise.
/// Params: none.
/// Returns: a fresh Vec[Str] of the 27 table symbols in ascending str_compare
/// order (e.g. "Ag", "Al", ..., "Zn"); empty input never occurs.
/// Error case: none.
/// Complexity: O(table size).
pub fn chem_symbols() -> Vec[Str] {
  return _table_symbols();
}

/// Standard molar mass of one element in whole mg/mol.
/// Params: symbol - an exact, case-sensitive element symbol ("H", "Cl", "Na").
/// Returns: Some(mg/mol) for a table symbol, None otherwise (unknown symbol,
/// lowercase form, empty string). Examples: H=1008, C=12011, O=15999,
/// Na=22990, Cl=35453, Fe=55845.
/// Error case: none (failure is None).
/// Complexity: O(table size).
pub fn chem_element_mass_mg(symbol: Str) -> Option[Int] {
  return _element_mass(symbol);
}

/// Molar mass of a formula in whole mg/mol.
/// Params: formula - element symbols (uppercase plus an optional lowercase
/// second letter), optional decimal counts (default 1) and nested
/// parentheses with optional counts. Whitespace is not allowed.
/// Returns: Ok(total) with the exact integer sum of mass*count over all
/// atoms; e.g. H2O -> 18015, CO2 -> 44009, Ca(OH)2 -> 74092.
/// Error case: Err("chemistry: ...") for an empty formula, an unknown symbol,
/// an unmatched ')' or unclosed '(', an empty group, a zero count or any
/// unexpected character (trailing junk).
/// Complexity: O(len(formula)).
pub fn chem_molar_mass_mg_per_mol(formula: Str) -> Result[Int, Str] {
  return _chem_scan(formula);
}

/// Distinct element symbols of a formula, in first-seen order.
/// Params: formula - the same grammar as chem_molar_mass_mg_per_mol.
/// Returns: Ok(symbols) with each present symbol exactly once, ordered by its
/// first occurrence in the formula's left-to-right scan (parenthesized groups
/// keep their textual position); e.g. Ca(OH)2 -> ["Ca", "O", "H"].
/// Error case: Err("chemistry: ...") for the same malformed inputs as
/// chem_molar_mass_mg_per_mol.
/// Complexity: O(len(formula) * distinct symbols).
pub fn chem_formula_elements(formula: Str) -> Result[Vec[Str], Str] {
  return _chem_collect(formula);
}

/// Mass fraction of one element in a formula, in permille (parts per thousand).
/// Params: formula - the same grammar as chem_molar_mass_mg_per_mol; symbol -
/// the element to measure.
/// Returns: Ok(permille) = atoms(symbol) * mass(symbol) * 1000 / total,
/// truncated (integer division), e.g. H2O: H -> 111, O -> 888; NaCl: Na -> 393.
/// Error case: Err("chemistry: ...") when the formula is malformed (same
/// catalog as chem_molar_mass_mg_per_mol) or when `symbol` does not occur in
/// the formula ("chemistry: symbol not present: ...").
/// Complexity: O(len(formula)) + O(table size).
pub fn chem_mass_fraction_permille(formula: Str, symbol: Str) -> Result[Int, Str] {
  let scan = _chem_scan(formula);
  var total = 0;
  match scan {
    Ok(t) => { total = t; },
    Err(e) => { return _err_int(e); },
  }
  let counted = _count_atoms(formula, symbol);
  var atoms = 0;
  match counted {
    Ok(c) => { atoms = c; },
    Err(e) => { return _err_int(e); },
  }
  if atoms == 0 { return _err_int("chemistry: symbol not present: " + symbol); }
  match _element_mass(symbol) {
    Some(mass) => {
      if total <= 0 { return _err_int("chemistry: zero molar mass"); }
      return _ok_int(atoms * mass * 1000 / total);
    },
    None => { return _err_int("chemistry: symbol not present: " + symbol); },
  }
  return _err_int("chemistry: unreachable");
}
