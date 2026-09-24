// XIOM -- xiom.chemistry conformance tests (25 checks)
// Port task: prove the pure-XIOM xiom.chemistry module against its documented
// formula grammar and pinned element masses.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module chemistry_tests
use xiom.io; use xiom.test; use xiom.chemistry;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so element checks below
// are routed through compare.str_compare instead of `==`.

fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn mass_is(formula: Str, want: Int) -> Bool {
  let r = chem_molar_mass_mg_per_mol(formula);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn mass_err(formula: Str) -> Bool {
  let r = chem_molar_mass_mg_per_mol(formula);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "chemistry: "); },
  }
  return false;
}

// Vec[Str] element reads go through a typed local (`let e: Str = v[i];`) and
// comparisons through str_compare: BUG 17 family -- a Vec[Str] element read
// straight into an expression can carry a bogus length, and `==` on such
// values lowers to a pointer comparison.

fn elems_len_is(formula: Str, want: Int) -> Bool {
  let r = chem_formula_elements(formula);
  match r {
    Ok(v) => {
      let n: Int = v.len();
      return n == want;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn elem_at_is(formula: Str, idx: Int, want: Str) -> Bool {
  let r = chem_formula_elements(formula);
  match r {
    Ok(v) => {
      let n: Int = v.len();
      if idx < 0 || idx >= n { return false; }
      let e: Str = v[idx];
      return compare.str_compare(e, want) == 0;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn elems_err(formula: Str) -> Bool {
  let r = chem_formula_elements(formula);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "chemistry: "); },
  }
  return false;
}

fn permille_is(formula: Str, symbol: Str, want: Int) -> Bool {
  let r = chem_mass_fraction_permille(formula, symbol);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn permille_err(formula: Str, symbol: Str) -> Bool {
  let r = chem_mass_fraction_permille(formula, symbol);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "chemistry: "); },
  }
  return false;
}

fn symbols_contain(symbol: Str) -> Bool {
  let syms = chem_symbols();
  var i = 0;
  while i < syms.len() {
    let e: Str = syms[i];
    if compare.str_compare(e, symbol) == 0 { return true; }
    i = i + 1;
  }
  return false;
}

fn t1() -> TestResult {
  var ok = opt_int_is(chem_element_mass_mg("H"), 1008);
  if !opt_int_is(chem_element_mass_mg("C"), 12011) { ok = false; }
  if !opt_int_is(chem_element_mass_mg("O"), 15999) { ok = false; }
  return assert(ok, "element masses H=1008, C=12011, O=15999");
}

fn t2() -> TestResult {
  var ok = opt_int_is(chem_element_mass_mg("Na"), 22990);
  if !opt_int_is(chem_element_mass_mg("Cl"), 35453) { ok = false; }
  if !opt_int_is(chem_element_mass_mg("Fe"), 55845) { ok = false; }
  return assert(ok, "element masses Na=22990, Cl=35453, Fe=55845");
}

fn t3() -> TestResult {
  var ok = opt_int_none(chem_element_mass_mg("Xx"));
  if !opt_int_none(chem_element_mass_mg("")) { ok = false; }
  if !opt_int_none(chem_element_mass_mg("cl")) { ok = false; }
  if !opt_int_none(chem_element_mass_mg("CL")) { ok = false; }
  return assert(ok, "unknown or mis-cased symbol is None");
}

fn t4() -> TestResult {
  var syms = chem_symbols();
  var ok = syms.len() == 27;
  var i = 1;
  while i < syms.len() {
    let a: Str = syms[i - 1];
    let b: Str = syms[i];
    if compare.str_compare(a, b) >= 0 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "symbols: 27 entries, strictly sorted and unique");
}

fn t5() -> TestResult {
  var ok = symbols_contain("H");
  if !symbols_contain("C") { ok = false; }
  if !symbols_contain("O") { ok = false; }
  if !symbols_contain("Na") { ok = false; }
  if !symbols_contain("Cl") { ok = false; }
  if !symbols_contain("Fe") { ok = false; }
  let syms = chem_symbols();
  var i = 0;
  while i < syms.len() {
    let s: Str = syms[i];
    let got = chem_element_mass_mg(s);
    match got {
      Some(m) => { if m <= 0 { ok = false; } },
      None => { ok = false; },
    }
    i = i + 1;
  }
  return assert(ok, "table symbols are present and have positive masses");
}

fn t6() -> TestResult {
  return assert(mass_is("H2O", 18015), "H2O molar mass is 18015 mg/mol");
}

fn t7() -> TestResult {
  return assert(mass_is("CO2", 44009), "CO2 molar mass is 44009 mg/mol");
}

fn t8() -> TestResult {
  return assert(mass_is("NaCl", 58443), "NaCl molar mass is 58443 mg/mol");
}

fn t9() -> TestResult {
  return assert(mass_is("Ca(OH)2", 74092), "Ca(OH)2 molar mass is 74092 mg/mol");
}

fn t10() -> TestResult {
  return assert(mass_is("C12H22O11", 342297), "C12H22O11 molar mass is 342297 mg/mol");
}

fn t11() -> TestResult {
  var ok = mass_is("Fe3O4", 231531);
  if !mass_is("C60", 720660) { ok = false; }
  return assert(ok, "multi-digit counts: Fe3O4=231531, C60=720660");
}

fn t12() -> TestResult {
  var ok = mass_is("((OH)2)", 34014);
  if !mass_is("(H2O)2", 36030) { ok = false; }
  return assert(ok, "nested parentheses: ((OH)2)=34014, (H2O)2=36030");
}

fn t13() -> TestResult {
  var ok = mass_is("H2O1", 18015);
  if !mass_is("NaOH", 39997) { ok = false; }
  if !mass_is("Fe", 55845) { ok = false; }
  if !mass_is("NaCl1", 58443) { ok = false; }
  return assert(ok, "implicit count is 1: H2O1, NaOH, Fe, NaCl1");
}

fn t14() -> TestResult {
  var ok = mass_is("Cl2", 70906);
  if !mass_is("C2", 24022) { ok = false; }
  if !mass_is("Cl", 35453) { ok = false; }
  return assert(ok, "lowercase second letter: Cl2=70906 vs C2=24022");
}

fn t15() -> TestResult {
  var ok = mass_err("Xx2");
  if !mass_err("Co2") { ok = false; }
  if !mass_err("H2Zz") { ok = false; }
  if !mass_err("NaCq") { ok = false; }
  return assert(ok, "unknown symbols are rejected");
}

fn t16() -> TestResult {
  var ok = mass_err("Ca(OH2");
  if !mass_err("(H2O") { ok = false; }
  if !mass_err("H2O)") { ok = false; }
  if !mass_err(")") { ok = false; }
  return assert(ok, "unbalanced parentheses are rejected");
}

fn t17() -> TestResult {
  return assert(mass_err(""), "empty formula is rejected");
}

fn t18() -> TestResult {
  var ok = mass_err("H2O!");
  if !mass_err("2H2O") { ok = false; }
  if !mass_err("h2o") { ok = false; }
  if !mass_err("H2O ") { ok = false; }
  if !mass_err("H2O#") { ok = false; }
  return assert(ok, "trailing junk and non-symbol starts are rejected");
}

fn t19() -> TestResult {
  var ok = elems_len_is("C12H22O11", 3);
  if !elem_at_is("C12H22O11", 0, "C") { ok = false; }
  if !elem_at_is("C12H22O11", 1, "H") { ok = false; }
  if !elem_at_is("C12H22O11", 2, "O") { ok = false; }
  if !elems_len_is("H2O", 2) { ok = false; }
  if !elem_at_is("H2O", 0, "H") { ok = false; }
  if !elem_at_is("H2O", 1, "O") { ok = false; }
  if !elems_len_is("NaCl", 2) { ok = false; }
  if !elem_at_is("NaCl", 0, "Na") { ok = false; }
  if !elem_at_is("NaCl", 1, "Cl") { ok = false; }
  return assert(ok, "formula_elements: distinct symbols in first-seen order");
}

fn t20() -> TestResult {
  var ok = elems_len_is("(NH4)2SO4", 4);
  if !elem_at_is("(NH4)2SO4", 0, "N") { ok = false; }
  if !elem_at_is("(NH4)2SO4", 1, "H") { ok = false; }
  if !elem_at_is("(NH4)2SO4", 2, "S") { ok = false; }
  if !elem_at_is("(NH4)2SO4", 3, "O") { ok = false; }
  if !elems_len_is("H(H)2", 1) { ok = false; }
  if !elem_at_is("H(H)2", 0, "H") { ok = false; }
  if !elems_len_is("Ca(OH)2", 3) { ok = false; }
  if !elem_at_is("Ca(OH)2", 0, "Ca") { ok = false; }
  if !elem_at_is("Ca(OH)2", 1, "O") { ok = false; }
  if !elem_at_is("Ca(OH)2", 2, "H") { ok = false; }
  return assert(ok, "formula_elements: groups keep textual order, dedup works");
}

fn t21() -> TestResult {
  var ok = elems_err("");
  if !elems_err("Xx") { ok = false; }
  if !elems_err("H2O)") { ok = false; }
  return assert(ok, "formula_elements rejects malformed formulas");
}

fn t22() -> TestResult {
  var ok = permille_is("H2O", "H", 111);
  if !permille_is("H2O", "O", 888) { ok = false; }
  return assert(ok, "water mass fraction: H=111, O=888 permille (truncated)");
}

fn t23() -> TestResult {
  var ok = permille_is("NaCl", "Na", 393);
  if !permille_is("NaCl", "Cl", 606) { ok = false; }
  if !permille_is("(OH)2", "H", 59) { ok = false; }
  if !permille_is("(OH)2", "O", 940) { ok = false; }
  return assert(ok, "NaCl and (OH)2 mass fractions truncate correctly");
}

fn t24() -> TestResult {
  var ok = permille_is("C12H22O11", "C", 421);
  if !permille_is("C12H22O11", "H", 64) { ok = false; }
  if !permille_is("C12H22O11", "O", 514) { ok = false; }
  return assert(ok, "sucrose mass fractions: C=421, H=64, O=514 permille");
}

fn t25() -> TestResult {
  var ok = permille_err("H2O", "Na");
  if !permille_err("NaCl", "Xx") { ok = false; }
  if !permille_err("H2O!", "H") { ok = false; }
  if !permille_err("H2O", "H2O") { ok = false; }
  return assert(ok, "absent symbol or malformed formula is an error");
}

fn main() -> Int {
  io.println("=== xiom.chemistry conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.chemistry: all tests passed");
  } else {
    io.println("xiom.chemistry: tests failed");
  }
  return failed;
}
