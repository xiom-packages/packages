// XIOM -- xiom.wallet conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven deterministic tests, one direct call per check (no fn
// tables, no indexed dispatch). Coverage: derivation path parsing (canonical
// form, markers h/H normalization, component bounds, depth cap, every
// documented rejection with its exact error), accessors and structural
// equality, account book (add/find/rotate key/validation/duplicates),
// address book (structural validation/duplicates/lookups), ledger credits
// (posting sequences, overflow guards), transfer intents (reservation,
// insufficient funds, execution, cancellation, double-spend rejection),
// and the canonical text exports (account, address, ledger and wallet).
//
// All Str equality goes through str_compare (BUG-17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison).

module wallet_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.wallet;

// --------------------------------------------------
//  Test helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

fn path_err(r: Result[DerivationPath, Str]) -> Str {
  if r.is_ok {
    return "(ok)";
  }
  return r.error;
}

fn int_err(r: Result[Int, Str]) -> Str {
  if r.is_ok {
    return "(ok)";
  }
  return r.error;
}

fn str_err(r: Result[Str, Str]) -> Str {
  if r.is_ok {
    return "(ok)";
  }
  return r.error;
}

fn wallet_err(r: Result[Wallet, Str]) -> Str {
  if r.is_ok {
    return "(ok)";
  }
  return r.error;
}

// Ledger with a settled 10000 credit posting (sequence 1).
fn funded_ledger() -> Ledger {
  var l = ledger_new();
  let r = ledger_credit(&mut l, 10000, "fund");
  if !r.is_ok {
    return ledger_new();
  }
  return l;
}

// --------------------------------------------------
//  t1: canonical BIP32 path
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let r = derivation_path_parse("m/44'/0'/0'/0/0");
  if !r.is_ok {
    ok = false;
  } else {
    let p: DerivationPath = r.value;
    if derivation_path_depth(&p) != 5 { ok = false; }
    if derivation_path_component(&p, 0) != 44 { ok = false; }
    if derivation_path_component(&p, 1) != 0 { ok = false; }
    if derivation_path_component(&p, 2) != 0 { ok = false; }
    if derivation_path_component(&p, 3) != 0 { ok = false; }
    if derivation_path_component(&p, 4) != 0 { ok = false; }
    if !derivation_path_is_hardened(&p, 0) { ok = false; }
    if !derivation_path_is_hardened(&p, 1) { ok = false; }
    if !derivation_path_is_hardened(&p, 2) { ok = false; }
    if derivation_path_is_hardened(&p, 3) { ok = false; }
    if derivation_path_hardened_count(&p) != 3 { ok = false; }
    if !streq(derivation_path_format(&p), "m/44'/0'/0'/0/0") { ok = false; }
  }
  if !derivation_path_validate("m/44'/0'/0'/0/0") { ok = false; }
  return assert(ok, "canonical BIP32 path parses and reformats exactly");
}

// --------------------------------------------------
//  t2: path variants and marker normalization
// --------------------------------------------------

fn t2() -> TestResult {
  var ok = true;
  let rm = derivation_path_parse("m");
  if !rm.is_ok {
    ok = false;
  } else {
    let pm: DerivationPath = rm.value;
    if derivation_path_depth(&pm) != 0 { ok = false; }
    if !streq(derivation_path_format(&pm), "m") { ok = false; }
  }
  let r0 = derivation_path_parse("m/0");
  if !r0.is_ok {
    ok = false;
  } else {
    let p0: DerivationPath = r0.value;
    if derivation_path_component(&p0, 0) != 0 { ok = false; }
    if derivation_path_is_hardened(&p0, 0) { ok = false; }
    if !streq(derivation_path_format(&p0), "m/0") { ok = false; }
  }
  let rmax = derivation_path_parse("m/2147483647");
  if !rmax.is_ok {
    ok = false;
  } else {
    let pmx: DerivationPath = rmax.value;
    if derivation_path_component(&pmx, 0) != 2147483647 { ok = false; }
  }
  // "h" and "H" markers normalize to the canonical "'"
  let rh = derivation_path_parse("m/0h/1H/2'");
  if !rh.is_ok {
    ok = false;
  } else {
    let ph: DerivationPath = rh.value;
    if derivation_path_depth(&ph) != 3 { ok = false; }
    if derivation_path_hardened_count(&ph) != 3 { ok = false; }
    if !streq(derivation_path_format(&ph), "m/0'/1'/2'") { ok = false; }
    let rc = derivation_path_parse("m/0'/1'/2'");
    if !rc.is_ok {
      ok = false;
    } else {
      let pc: DerivationPath = rc.value;
      if !derivation_path_equal(&ph, &pc) { ok = false; }
    }
  }
  if !derivation_path_validate("m/0h") { ok = false; }
  return assert(ok, "m, single components, bounds and h/H normalization");
}

// --------------------------------------------------
//  t3: path rejections (exact errors)
// --------------------------------------------------

fn t3() -> TestResult {
  var ok = true;
  if !streq(path_err(derivation_path_parse("")), "wallet: empty derivation path") { ok = false; }
  if !streq(path_err(derivation_path_parse("M/0")), "wallet: derivation path must start with m") { ok = false; }
  if !streq(path_err(derivation_path_parse("x/0")), "wallet: derivation path must start with m") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/")), "wallet: empty path component at offset 2") { ok = false; }
  if !streq(path_err(derivation_path_parse("m//0")), "wallet: invalid path character at offset 2") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/00")), "wallet: leading zero in path component at offset 2") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/0''")), "wallet: invalid path character at offset 4") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/abc")), "wallet: invalid path character at offset 2") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/0x")), "wallet: invalid path character at offset 3") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/0 /1")), "wallet: invalid path character at offset 3") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/12a")), "wallet: invalid path character at offset 4") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/0/")), "wallet: empty path component at offset 4") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/2147483648")), "wallet: path component out of range at offset 2") { ok = false; }
  if !streq(path_err(derivation_path_parse("m/99999999999999999999")), "wallet: path component out of range at offset 2") { ok = false; }
  if derivation_path_validate("m/00") { ok = false; }
  return assert(ok, "path rejections report exact documented errors");
}

// --------------------------------------------------
//  t4: path depth cap (255 components)
// --------------------------------------------------

fn t4() -> TestResult {
  var ok = true;
  var deep = "m";
  var i = 0;
  while i < 255 {
    deep = deep + "/0";
    i = i + 1;
  }
  let r = derivation_path_parse(deep);
  if !r.is_ok {
    ok = false;
  } else {
    let p: DerivationPath = r.value;
    if derivation_path_depth(&p) != 255 { ok = false; }
    if derivation_path_component(&p, 254) != 0 { ok = false; }
  }
  let r2 = derivation_path_parse(deep + "/0");
  if !streq(path_err(r2), "wallet: derivation path depth exceeds 255") { ok = false; }
  return assert(ok, "255 components accepted, 256 rejected");
}

// --------------------------------------------------
//  t5: path accessors, equality, out-of-range
// --------------------------------------------------

fn t5() -> TestResult {
  var ok = true;
  let p = derivation_path_new();
  if derivation_path_depth(&p) != 0 { ok = false; }
  if derivation_path_component(&p, 0) != -1 { ok = false; }
  if derivation_path_component(&p, -1) != -1 { ok = false; }
  if derivation_path_is_hardened(&p, 0) { ok = false; }
  if derivation_path_hardened_count(&p) != 0 { ok = false; }
  if !streq(derivation_path_format(&p), "m") { ok = false; }
  let ra = derivation_path_parse("m/1H");
  let rb = derivation_path_parse("m/1'");
  if !ra.is_ok || !rb.is_ok {
    ok = false;
  } else {
    let pa: DerivationPath = ra.value;
    let pb: DerivationPath = rb.value;
    if !derivation_path_equal(&pa, &pb) { ok = false; }
    let rc = derivation_path_parse("m/1");
    if !rc.is_ok {
      ok = false;
    } else {
      let pc: DerivationPath = rc.value;
      if derivation_path_equal(&pa, &pc) { ok = false; }
      if !derivation_path_equal(&pc, &pc) { ok = false; }
    }
  }
  return assert(ok, "path accessors, equality and out-of-range defaults");
}

// --------------------------------------------------
//  t6: account book add / find / accessors
// --------------------------------------------------

fn t6() -> TestResult {
  var ok = true;
  var ab = account_book_new();
  if account_book_count(&ab) != 0 { ok = false; }
  let r1 = account_book_add(&mut ab, "hot", "xpubA");
  if !r1.is_ok {
    ok = false;
  } else {
    let i1: Int = r1.value;
    if i1 != 0 { ok = false; }
  }
  let r2 = account_book_add(&mut ab, "cold", "xpubB");
  if !r2.is_ok {
    ok = false;
  } else {
    let i2: Int = r2.value;
    if i2 != 1 { ok = false; }
  }
  if account_book_count(&ab) != 2 { ok = false; }
  if account_book_find(&ab, "cold") != 1 { ok = false; }
  if account_book_find(&ab, "hot") != 0 { ok = false; }
  if account_book_find(&ab, "nope") != -1 { ok = false; }
  if !streq(account_book_label(&ab, 0), "hot") { ok = false; }
  if !streq(account_book_key(&ab, 1), "xpubB") { ok = false; }
  if !streq(account_book_label(&ab, 9), "") { ok = false; }
  if !streq(account_book_key(&ab, -1), "") { ok = false; }
  return assert(ok, "account book add, find and accessors");
}

// --------------------------------------------------
//  t7: account book validation, duplicates, key rotation
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = true;
  var ab = account_book_new();
  if !streq(int_err(account_book_add(&mut ab, "", "x")), "wallet: empty label") { ok = false; }
  if !streq(int_err(account_book_add(&mut ab, "ok", "")), "wallet: empty account key") { ok = false; }
  if !streq(int_err(account_book_add(&mut ab, "bad\nlabel", "x")), "wallet: label contains control character at offset 3") { ok = false; }
  let longlabel = string.str_repeat("a", 65);
  if !streq(int_err(account_book_add(&mut ab, longlabel, "x")), "wallet: label too long (max 64 bytes)") { ok = false; }
  let longkey = string.str_repeat("k", 129);
  if !streq(int_err(account_book_add(&mut ab, "ok", longkey)), "wallet: account key too long (max 128 bytes)") { ok = false; }
  let r = account_book_add(&mut ab, "hot", "xpubA");
  if !r.is_ok { ok = false; }
  if !streq(int_err(account_book_add(&mut ab, "hot", "xpubC")), "wallet: duplicate account label") { ok = false; }
  let s = account_book_set_key(&mut ab, 0, "xpubZ");
  if !s.is_ok { ok = false; }
  if !streq(account_book_key(&ab, 0), "xpubZ") { ok = false; }
  if !streq(int_err(account_book_set_key(&mut ab, 5, "x")), "wallet: account index out of range") { ok = false; }
  if !streq(int_err(account_book_set_key(&mut ab, 0, "")), "wallet: empty account key") { ok = false; }
  if account_book_count(&ab) != 1 { ok = false; }
  return assert(ok, "account validation, duplicates and key rotation");
}

// --------------------------------------------------
//  t8: address book add / find / accessors
// --------------------------------------------------

fn t8() -> TestResult {
  var ok = true;
  var rb = address_book_new();
  if address_book_count(&rb) != 0 { ok = false; }
  let r1 = address_book_add(&mut rb, "home", "addr1");
  if !r1.is_ok {
    ok = false;
  } else {
    let i1: Int = r1.value;
    if i1 != 0 { ok = false; }
  }
  let r2 = address_book_add(&mut rb, "savings", "addr2");
  if !r2.is_ok {
    ok = false;
  } else {
    let i2: Int = r2.value;
    if i2 != 1 { ok = false; }
  }
  if address_book_count(&rb) != 2 { ok = false; }
  if address_book_find_label(&rb, "savings") != 1 { ok = false; }
  if address_book_find_label(&rb, "nope") != -1 { ok = false; }
  if address_book_find_address(&rb, "addr1") != 0 { ok = false; }
  if address_book_find_address(&rb, "nope") != -1 { ok = false; }
  if !streq(address_book_label(&rb, 0), "home") { ok = false; }
  if !streq(address_book_address(&rb, 1), "addr2") { ok = false; }
  if !streq(address_book_label(&rb, 9), "") { ok = false; }
  if !streq(address_book_address(&rb, -1), "") { ok = false; }
  return assert(ok, "address book add, find and accessors");
}

// --------------------------------------------------
//  t9: address structural validation and duplicates
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = true;
  var rb = address_book_new();
  let r0 = address_book_add(&mut rb, "home", "addr1");
  if !r0.is_ok { ok = false; }
  if !streq(int_err(address_book_add(&mut rb, "", "x")), "wallet: empty label") { ok = false; }
  if !streq(int_err(address_book_add(&mut rb, "x", "")), "wallet: empty address") { ok = false; }
  if !streq(int_err(address_book_add(&mut rb, "x", "has space")), "wallet: address contains invalid character at offset 3") { ok = false; }
  if !streq(int_err(address_book_add(&mut rb, "x", "ab\tcd")), "wallet: address contains invalid character at offset 2") { ok = false; }
  let longaddr = string.str_repeat("a", 129);
  if !streq(int_err(address_book_add(&mut rb, "x", longaddr)), "wallet: address too long (max 128 bytes)") { ok = false; }
  if !streq(int_err(address_book_add(&mut rb, "home", "addr9")), "wallet: duplicate address label") { ok = false; }
  if !streq(int_err(address_book_add(&mut rb, "other", "addr1")), "wallet: duplicate address") { ok = false; }
  if address_book_count(&rb) != 1 { ok = false; }
  return assert(ok, "address validation, invalid characters and duplicates");
}

// --------------------------------------------------
//  t10: ledger credits, postings and sequences
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = true;
  var l = ledger_new();
  if ledger_balance(&l) != 0 { ok = false; }
  if ledger_reserved(&l) != 0 { ok = false; }
  if ledger_available(&l) != 0 { ok = false; }
  if ledger_sequence(&l) != 0 { ok = false; }
  if ledger_posting_count(&l) != 0 { ok = false; }
  let r1 = ledger_credit(&mut l, 1000, "c1");
  if !r1.is_ok {
    ok = false;
  } else {
    let b1: Int = r1.value;
    if b1 != 1000 { ok = false; }
  }
  let r2 = ledger_credit(&mut l, 250, "c2");
  if !r2.is_ok {
    ok = false;
  } else {
    let b2: Int = r2.value;
    if b2 != 1250 { ok = false; }
  }
  if ledger_balance(&l) != 1250 { ok = false; }
  if ledger_reserved(&l) != 0 { ok = false; }
  if ledger_available(&l) != 1250 { ok = false; }
  if ledger_sequence(&l) != 2 { ok = false; }
  if ledger_posting_count(&l) != 2 { ok = false; }
  if ledger_posting_seq(&l, 0) != 1 { ok = false; }
  if ledger_posting_kind(&l, 0) != POSTING_CREDIT { ok = false; }
  if ledger_posting_delta(&l, 0) != 1000 { ok = false; }
  if ledger_posting_amount(&l, 0) != 1000 { ok = false; }
  if ledger_posting_fee(&l, 0) != 0 { ok = false; }
  if !streq(ledger_posting_ref(&l, 0), "c1") { ok = false; }
  if !streq(ledger_posting_to(&l, 0), "") { ok = false; }
  if ledger_posting_seq(&l, 1) != 2 { ok = false; }
  if !streq(ledger_posting_ref(&l, 1), "c2") { ok = false; }
  if ledger_posting_seq(&l, 9) != -1 { ok = false; }
  if ledger_posting_kind(&l, 9) != -1 { ok = false; }
  if ledger_posting_delta(&l, 9) != 0 { ok = false; }
  if !streq(ledger_posting_ref(&l, 9), "") { ok = false; }
  return assert(ok, "credits append sequenced postings and update the balance");
}

// --------------------------------------------------
//  t11: credit guards (amounts, references, overflow)
// --------------------------------------------------

fn t11() -> TestResult {
  var ok = true;
  var l = ledger_new();
  if !streq(int_err(ledger_credit(&mut l, 0, "r")), "wallet: amount must be positive") { ok = false; }
  if !streq(int_err(ledger_credit(&mut l, -5, "r")), "wallet: amount must be positive") { ok = false; }
  if !streq(int_err(ledger_credit(&mut l, 1, "")), "wallet: empty reference") { ok = false; }
  if !streq(int_err(ledger_credit(&mut l, 1, "a\nb")), "wallet: reference contains control character at offset 1") { ok = false; }
  let longref = string.str_repeat("r", 129);
  if !streq(int_err(ledger_credit(&mut l, 1, longref)), "wallet: reference too long (max 128 bytes)") { ok = false; }
  if ledger_balance(&l) != 0 { ok = false; }
  if ledger_sequence(&l) != 0 { ok = false; }
  let rmax = ledger_credit(&mut l, 9223372036854775807, "max");
  if !rmax.is_ok { ok = false; }
  if !streq(int_err(ledger_credit(&mut l, 1, "one")), "wallet: balance overflow") { ok = false; }
  if ledger_balance(&l) != 9223372036854775807 { ok = false; }
  if ledger_sequence(&l) != 1 { ok = false; }
  return assert(ok, "credit guards reject bad amounts, refs and overflow");
}

// --------------------------------------------------
//  t12: intent creation, reservation and rejection order
// --------------------------------------------------

fn t12() -> TestResult {
  var ok = true;
  var l = funded_ledger();
  let c1 = ledger_intent_create(&mut l, "t1", 3000, 10, "acct-cold");
  if !c1.is_ok {
    ok = false;
  } else {
    let idx: Int = c1.value;
    if idx != 0 { ok = false; }
  }
  if ledger_intent_count(&l) != 1 { ok = false; }
  if ledger_intent_status(&l, 0) != INTENT_PENDING { ok = false; }
  if ledger_intent_amount(&l, 0) != 3000 { ok = false; }
  if ledger_intent_fee(&l, 0) != 10 { ok = false; }
  if !streq(ledger_intent_to(&l, 0), "acct-cold") { ok = false; }
  if !streq(ledger_intent_id(&l, 0), "t1") { ok = false; }
  if ledger_reserved(&l) != 3010 { ok = false; }
  if ledger_available(&l) != 6990 { ok = false; }
  if ledger_intent_pending_count(&l) != 1 { ok = false; }
  let c2 = ledger_intent_create(&mut l, "t2", 500, 0, "acct-hot");
  if !c2.is_ok { ok = false; }
  if ledger_reserved(&l) != 3510 { ok = false; }
  if ledger_intent_index(&l, "t2") != 1 { ok = false; }
  if ledger_intent_index(&l, "nope") != -1 { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "t1", 1, 0, "x")), "wallet: duplicate intent") { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "", 1, 0, "x")), "wallet: empty intent id") { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "t3", 0, 0, "x")), "wallet: amount must be positive") { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "t3", 1, -1, "x")), "wallet: negative fee") { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "t3", 9223372036854775807, 1, "x")), "wallet: amount plus fee overflows") { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "t3", 1, 0, "")), "wallet: empty intent destination") { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "t3", 1, 0, "has space")), "wallet: intent destination contains invalid character at offset 3") { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "t3", 6491, 0, "x")), "wallet: insufficient funds") { ok = false; }
  let c3 = ledger_intent_create(&mut l, "t3", 6490, 0, "x");
  if !c3.is_ok { ok = false; }
  if ledger_reserved(&l) != 10000 { ok = false; }
  if ledger_available(&l) != 0 { ok = false; }
  return assert(ok, "intent creation reserves funds and validates in order");
}

// --------------------------------------------------
//  t13: intent execution and double-spend rejection
// --------------------------------------------------

fn t13() -> TestResult {
  var ok = true;
  var l = funded_ledger();
  let c = ledger_intent_create(&mut l, "t1", 3000, 10, "acct-cold");
  if !c.is_ok { ok = false; }
  let x = ledger_intent_execute(&mut l, "t1");
  if !x.is_ok {
    ok = false;
  } else {
    let b: Int = x.value;
    if b != 6990 { ok = false; }
  }
  if ledger_balance(&l) != 6990 { ok = false; }
  if ledger_reserved(&l) != 0 { ok = false; }
  if ledger_available(&l) != 6990 { ok = false; }
  if ledger_sequence(&l) != 2 { ok = false; }
  if ledger_posting_count(&l) != 2 { ok = false; }
  if ledger_posting_seq(&l, 1) != 2 { ok = false; }
  if ledger_posting_kind(&l, 1) != POSTING_TRANSFER { ok = false; }
  if ledger_posting_delta(&l, 1) != -3010 { ok = false; }
  if ledger_posting_amount(&l, 1) != 3000 { ok = false; }
  if ledger_posting_fee(&l, 1) != 10 { ok = false; }
  if !streq(ledger_posting_ref(&l, 1), "t1") { ok = false; }
  if !streq(ledger_posting_to(&l, 1), "acct-cold") { ok = false; }
  if ledger_intent_status(&l, 0) != INTENT_EXECUTED { ok = false; }
  if ledger_intent_pending_count(&l) != 0 { ok = false; }
  if !streq(int_err(ledger_intent_execute(&mut l, "t1")), "wallet: intent already settled") { ok = false; }
  if !streq(int_err(ledger_intent_execute(&mut l, "nope")), "wallet: unknown intent") { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "t1", 1, 0, "x")), "wallet: duplicate intent") { ok = false; }
  if ledger_balance(&l) != 6990 { ok = false; }
  if ledger_sequence(&l) != 2 { ok = false; }
  return assert(ok, "execution settles once and rejects double-spend");
}

// --------------------------------------------------
//  t14: intent cancellation releases funds
// --------------------------------------------------

fn t14() -> TestResult {
  var ok = true;
  var l = funded_ledger();
  let c = ledger_intent_create(&mut l, "t1", 3000, 10, "acct-cold");
  if !c.is_ok { ok = false; }
  let x = ledger_intent_cancel(&mut l, "t1");
  if !x.is_ok {
    ok = false;
  } else {
    let idx: Int = x.value;
    if idx != 0 { ok = false; }
  }
  if ledger_balance(&l) != 10000 { ok = false; }
  if ledger_reserved(&l) != 0 { ok = false; }
  if ledger_available(&l) != 10000 { ok = false; }
  if ledger_sequence(&l) != 1 { ok = false; }
  if ledger_posting_count(&l) != 1 { ok = false; }
  if ledger_intent_status(&l, 0) != INTENT_CANCELLED { ok = false; }
  if ledger_intent_pending_count(&l) != 0 { ok = false; }
  if !streq(int_err(ledger_intent_cancel(&mut l, "t1")), "wallet: intent already settled") { ok = false; }
  if !streq(int_err(ledger_intent_execute(&mut l, "t1")), "wallet: intent already settled") { ok = false; }
  if !streq(int_err(ledger_intent_cancel(&mut l, "nope")), "wallet: unknown intent") { ok = false; }
  return assert(ok, "cancellation releases reserved funds without a posting");
}

// --------------------------------------------------
//  t15: mixed ledger keeps strict posting sequences
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = true;
  var l = ledger_new();
  let r1 = ledger_credit(&mut l, 100, "c1");
  if !r1.is_ok { ok = false; }
  let a = ledger_intent_create(&mut l, "a", 40, 2, "dst");
  if !a.is_ok { ok = false; }
  let b = ledger_intent_create(&mut l, "b", 10, 0, "dst");
  if !b.is_ok { ok = false; }
  let x = ledger_intent_execute(&mut l, "b");
  if !x.is_ok { ok = false; }
  let cx = ledger_intent_cancel(&mut l, "a");
  if !cx.is_ok { ok = false; }
  let r2 = ledger_credit(&mut l, 50, "c2");
  if !r2.is_ok { ok = false; }
  if ledger_sequence(&l) != 3 { ok = false; }
  if ledger_posting_count(&l) != 3 { ok = false; }
  if ledger_posting_seq(&l, 0) != 1 { ok = false; }
  if ledger_posting_seq(&l, 1) != 2 { ok = false; }
  if ledger_posting_seq(&l, 2) != 3 { ok = false; }
  if ledger_posting_kind(&l, 0) != POSTING_CREDIT { ok = false; }
  if ledger_posting_kind(&l, 1) != POSTING_TRANSFER { ok = false; }
  if ledger_posting_kind(&l, 2) != POSTING_CREDIT { ok = false; }
  if ledger_posting_delta(&l, 1) != -10 { ok = false; }
  if ledger_balance(&l) != 140 { ok = false; }
  if ledger_reserved(&l) != 0 { ok = false; }
  if ledger_available(&l) != 140 { ok = false; }
  if ledger_intent_status(&l, 0) != INTENT_CANCELLED { ok = false; }
  if ledger_intent_status(&l, 1) != INTENT_EXECUTED { ok = false; }
  if ledger_intent_pending_count(&l) != 0 { ok = false; }
  return assert(ok, "mixed credit/execute/cancel keeps 1..N sequences");
}

// --------------------------------------------------
//  t16: available-funds arithmetic across intents
// --------------------------------------------------

fn t16() -> TestResult {
  var ok = true;
  var l = funded_ledger();
  let a = ledger_intent_create(&mut l, "a", 9400, 10, "dst");
  if !a.is_ok { ok = false; }
  if ledger_reserved(&l) != 9410 { ok = false; }
  if ledger_available(&l) != 590 { ok = false; }
  let b = ledger_intent_create(&mut l, "b", 500, 0, "dst");
  if !b.is_ok { ok = false; }
  if ledger_reserved(&l) != 9910 { ok = false; }
  if ledger_available(&l) != 90 { ok = false; }
  if !streq(int_err(ledger_intent_create(&mut l, "c", 100, 0, "dst")), "wallet: insufficient funds") { ok = false; }
  let cb = ledger_intent_cancel(&mut l, "b");
  if !cb.is_ok { ok = false; }
  if ledger_reserved(&l) != 9410 { ok = false; }
  if ledger_available(&l) != 590 { ok = false; }
  let c = ledger_intent_create(&mut l, "c", 590, 0, "dst");
  if !c.is_ok { ok = false; }
  if ledger_reserved(&l) != 10000 { ok = false; }
  if ledger_available(&l) != 0 { ok = false; }
  let ca = ledger_intent_cancel(&mut l, "a");
  if !ca.is_ok { ok = false; }
  if ledger_reserved(&l) != 590 { ok = false; }
  if ledger_available(&l) != 9410 { ok = false; }
  if ledger_intent_status(&l, 1) != INTENT_CANCELLED { ok = false; }
  if ledger_intent_pending_count(&l) != 1 { ok = false; }
  return assert(ok, "reservation arithmetic and insufficient-funds guard");
}

// --------------------------------------------------
//  t17: account book canonical export
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = true;
  var ab = account_book_new();
  let r1 = account_book_add(&mut ab, "hot", "xpubA");
  if !r1.is_ok { ok = false; }
  let r2 = account_book_add(&mut ab, "cold", "xpubB");
  if !r2.is_ok { ok = false; }
  let want = "accounts\t2\naccount\t0\thot\txpubA\naccount\t1\tcold\txpubB\n";
  if !streq(account_book_export(&ab), want) { ok = false; }
  var empty = account_book_new();
  if !streq(account_book_export(&empty), "accounts\t0\n") { ok = false; }
  return assert(ok, "account book export is canonical");
}

// --------------------------------------------------
//  t18: address book canonical export
// --------------------------------------------------

fn t18() -> TestResult {
  var ok = true;
  var rb = address_book_new();
  let r1 = address_book_add(&mut rb, "home", "addr1");
  if !r1.is_ok { ok = false; }
  let r2 = address_book_add(&mut rb, "work", "addr2");
  if !r2.is_ok { ok = false; }
  let want = "addresses\t2\naddress\t0\thome\taddr1\naddress\t1\twork\taddr2\n";
  if !streq(address_book_export(&rb), want) { ok = false; }
  var empty = address_book_new();
  if !streq(address_book_export(&empty), "addresses\t0\n") { ok = false; }
  return assert(ok, "address book export is canonical");
}

// --------------------------------------------------
//  t19: ledger canonical export (all intent statuses)
// --------------------------------------------------

fn t19() -> TestResult {
  var ok = true;
  var l = ledger_new();
  let r1 = ledger_credit(&mut l, 100, "c1");
  if !r1.is_ok { ok = false; }
  let c1 = ledger_intent_create(&mut l, "t1", 30, 2, "dest");
  if !c1.is_ok { ok = false; }
  let x = ledger_intent_execute(&mut l, "t1");
  if !x.is_ok { ok = false; }
  let c2 = ledger_intent_create(&mut l, "t2", 5, 0, "d2");
  if !c2.is_ok { ok = false; }
  let cx = ledger_intent_cancel(&mut l, "t2");
  if !cx.is_ok { ok = false; }
  let c3 = ledger_intent_create(&mut l, "t3", 5, 1, "d3");
  if !c3.is_ok { ok = false; }
  var want = "ledger\t68\t6\t2\t1\n";
  want = want + "postings\t2\n";
  want = want + "posting\t1\tcredit\t100\t100\t0\tc1\t\n";
  want = want + "posting\t2\ttransfer\t-32\t30\t2\tt1\tdest\n";
  want = want + "intents\t3\n";
  want = want + "intent\tt1\texecuted\t30\t2\tdest\n";
  want = want + "intent\tt2\tcancelled\t5\t0\td2\n";
  want = want + "intent\tt3\tpending\t5\t1\td3\n";
  if !streq(ledger_export(&l), want) { ok = false; }
  return assert(ok, "ledger export lists postings and every intent status");
}

// --------------------------------------------------
//  t20: wallet aggregate, canonical export and name validation
// --------------------------------------------------

fn t20() -> TestResult {
  var ok = true;
  var ab = account_book_new();
  let a = account_book_add(&mut ab, "hot", "xpubA");
  if !a.is_ok { ok = false; }
  var rb = address_book_new();
  let d = address_book_add(&mut rb, "home", "addr1");
  if !d.is_ok { ok = false; }
  var lg = ledger_new();
  let r = ledger_credit(&mut lg, 500, "fund");
  if !r.is_ok { ok = false; }
  let w = Wallet{ name: "primary"; accounts: ab; addresses: rb; ledger: lg; };
  if !streq(wallet_name(&w), "primary") { ok = false; }
  var want = "wallet\t1\tprimary\n";
  want = want + "accounts\t1\naccount\t0\thot\txpubA\n";
  want = want + "addresses\t1\naddress\t0\thome\taddr1\n";
  want = want + "ledger\t500\t0\t1\t0\n";
  want = want + "postings\t1\n";
  want = want + "posting\t1\tcredit\t500\t500\t0\tfund\t\n";
  want = want + "intents\t0\n";
  let e = wallet_export(&w);
  if !e.is_ok {
    ok = false;
  } else {
    let s: Str = e.value;
    if !streq(s, want) { ok = false; }
  }
  let bad = wallet_new("bad\nname");
  if !streq(str_err(wallet_export(&bad)), "wallet: wallet name contains control character at offset 3") { ok = false; }
  let wc = wallet_new_checked("fresh");
  if !wc.is_ok { ok = false; }
  let wce = wallet_new_checked("");
  if !streq(wallet_err(wce), "wallet: empty wallet name") { ok = false; }
  return assert(ok, "wallet export composes the canonical listing");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn report(r: TestResult, failed: Int) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return failed;
  }
  io.println("  [FAIL] " + r.name);
  return failed + 1;
}

fn main() -> Int {
  io.println("=== xiom.wallet conformance tests ===");
  var failed: Int = 0;
  failed = report(t1(), failed);
  failed = report(t2(), failed);
  failed = report(t3(), failed);
  failed = report(t4(), failed);
  failed = report(t5(), failed);
  failed = report(t6(), failed);
  failed = report(t7(), failed);
  failed = report(t8(), failed);
  failed = report(t9(), failed);
  failed = report(t10(), failed);
  failed = report(t11(), failed);
  failed = report(t12(), failed);
  failed = report(t13(), failed);
  failed = report(t14(), failed);
  failed = report(t15(), failed);
  failed = report(t16(), failed);
  failed = report(t17(), failed);
  failed = report(t18(), failed);
  failed = report(t19(), failed);
  failed = report(t20(), failed);
  if failed == 0 {
    io.println("xiom.wallet: all tests passed");
  } else {
    io.println("xiom.wallet: tests failed");
  }
  return failed;
}
