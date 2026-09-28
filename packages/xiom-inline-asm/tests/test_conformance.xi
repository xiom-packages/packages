// XIOM -- xiom.inline-asm conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.inline.asm module against its
// documented template grammar, constraint table, clobber rules and emitter.
//
// Coverage: mixed templates, the "$n" and "${n}" / "${n:c}" operand forms,
// "$$" decoding, literal braces/commas, empty and literal-only inputs,
// constraint classification and validation, canonical emission with always
// braced operands and escaped dollars, full round trips, every error catalog
// entry with exact offsets, accessor bounds, multi-use counting, clobber
// parsing/emitting and the builder API.

module inline_asm_tests
use xiom.io; use xiom.test; use xiom.inline.asm;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when chunk `i` of `t` has exactly the wanted shape.
fn chunk_is(t: &AsmTemplate, i: Int, kind: Str, text: Str, index: Int) -> Bool {
  if !streq(asm_template_kind(t, i), kind) { return false; }
  if !streq(asm_template_text(t, i), text) { return false; }
  if asm_template_index(t, i) != index { return false; }
  return true;
}

// True when parsing fails with exactly the message `want`.
fn tpl_err(text: Str, want: Str) -> Bool {
  let r = asm_template_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when parsing fails with exactly the message `want`.
fn clob_err(text: Str, want: Str) -> Bool {
  let r = asm_clobbers_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `text` parses and re-emits as exactly `want`.
fn emits_as(text: Str, want: Str) -> Bool {
  let r = asm_template_parse(text);
  match r {
    Ok(t) => { return streq(asm_template_emit(&t), want); },
    Err(_) => { return false; },
  }
  return false;
}

// parse -> emit -> parse preserves every chunk and emit is idempotent.
fn round_trip(text: Str) -> Bool {
  let r1 = asm_template_parse(text);
  match r1 {
    Ok(t1) => {
      let e1 = asm_template_emit(&t1);
      let r2 = asm_template_parse(e1);
      match r2 {
        Ok(t2) => {
          if asm_template_chunk_count(&t1) != asm_template_chunk_count(&t2) { return false; }
          if asm_template_operand_count(&t1) != asm_template_operand_count(&t2) { return false; }
          var i = 0;
          while i < asm_template_chunk_count(&t1) {
            if !chunk_is(&t2, i, asm_template_kind(&t1, i), asm_template_text(&t1, i), asm_template_index(&t1, i)) { return false; }
            i = i + 1;
          }
          return streq(asm_template_emit(&t2), e1);
        },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when the result carries exactly the names `want`.
fn clob_is(text: Str, want: &Vec[Str]) -> Bool {
  let r = asm_clobbers_parse(text);
  match r {
    Ok(v) => {
      if v.len() != want.len() { return false; }
      var i = 0;
      while i < want.len() {
        let got: Str = v[i];
        let exp: Str = want[i];
        if !streq(got, exp) { return false; }
        i = i + 1;
      }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let r = asm_template_parse("${0:r} = ${1:r} + ${2:r}");
  var ok = false;
  match r {
    Ok(t) => {
      ok = asm_template_chunk_count(&t) == 5;
      if asm_template_operand_count(&t) != 3 { ok = false; }
      if !chunk_is(&t, 0, "op", "r", 0) { ok = false; }
      if !chunk_is(&t, 1, "lit", " = ", -1) { ok = false; }
      if !chunk_is(&t, 2, "op", "r", 1) { ok = false; }
      if !chunk_is(&t, 3, "lit", " + ", -1) { ok = false; }
      if !chunk_is(&t, 4, "op", "r", 2) { ok = false; }
      if asm_template_max_operand(&t) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "mixed template parses into flat literal and operand chunks");
}

fn t2() -> TestResult {
  let r = asm_template_parse("$0${1}$007");
  var ok = false;
  match r {
    Ok(t) => {
      ok = asm_template_chunk_count(&t) == 3;
      if asm_template_operand_count(&t) != 8 { ok = false; }
      if !chunk_is(&t, 0, "op", "", 0) { ok = false; }
      if !chunk_is(&t, 1, "op", "", 1) { ok = false; }
      if !chunk_is(&t, 2, "op", "", 7) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "short $n and braced ${n} forms parse with leading zeros");
}

fn t3() -> TestResult {
  let r = asm_template_parse("cost $$5");
  var ok = false;
  match r {
    Ok(t) => {
      ok = asm_template_chunk_count(&t) == 1;
      if !chunk_is(&t, 0, "lit", "cost $5", -1) { ok = false; }
      if asm_template_operand_count(&t) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "$$ decodes to one literal dollar");
}

fn t4() -> TestResult {
  let r = asm_template_parse("mov {a}, [b] 100% }");
  var ok = false;
  match r {
    Ok(t) => {
      ok = asm_template_chunk_count(&t) == 1;
      if !chunk_is(&t, 0, "lit", "mov {a}, [b] 100% }", -1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "literal braces, commas and percent need no escaping");
}

fn t5() -> TestResult {
  let empty = asm_template_parse("");
  var ok = false;
  match empty {
    Ok(t) => {
      ok = asm_template_chunk_count(&t) == 0;
      if asm_template_operand_count(&t) != 0 { ok = false; }
      if asm_template_max_operand(&t) != -1 { ok = false; }
      if !streq(asm_template_emit(&t), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let lit = asm_template_parse("plain text");
  var ok2 = false;
  match lit {
    Ok(t) => {
      ok2 = asm_template_chunk_count(&t) == 1;
      if !chunk_is(&t, 0, "lit", "plain text", -1) { ok2 = false; }
    },
    Err(_) => { ok2 = false; },
  }
  return assert(ok && ok2, "empty and literal-only templates parse");
}

fn t6() -> TestResult {
  var ok = streq(asm_constraint_class(""), "none");
  if !streq(asm_constraint_class("r"), "register") { ok = false; }
  if !streq(asm_constraint_class("m"), "memory") { ok = false; }
  if !streq(asm_constraint_class("o"), "offset_memory") { ok = false; }
  if !streq(asm_constraint_class("i"), "immediate") { ok = false; }
  if !streq(asm_constraint_class("n"), "immediate_integer") { ok = false; }
  if !streq(asm_constraint_class("g"), "general") { ok = false; }
  if !streq(asm_constraint_class("x"), "xmm_register") { ok = false; }
  if !streq(asm_constraint_class("rm"), "register_or_memory") { ok = false; }
  if !streq(asm_constraint_class("=r"), "register") { ok = false; }
  if !streq(asm_constraint_class("+&m"), "memory") { ok = false; }
  if !streq(asm_constraint_class("zz"), "unknown") { ok = false; }
  if !streq(asm_constraint_class("="), "none") { ok = false; }
  return assert(ok, "constraint classes follow the documented table");
}

fn t7() -> TestResult {
  var ok = asm_constraint_is_valid("r");
  if !asm_constraint_is_valid("=+r,!") { ok = false; }
  if asm_constraint_is_valid("") { ok = false; }
  if asm_constraint_is_valid("r@") { ok = false; }
  if asm_constraint_is_valid("r ") { ok = false; }
  if asm_constraint_is_valid("r;") { ok = false; }
  if !asm_constraint_is_valid("r1") { ok = false; }
  return assert(ok, "constraint validity uses the documented alphabet");
}

fn t8() -> TestResult {
  var ok = asm_constraint_is_output("=r");
  if !asm_constraint_is_output("+r") { ok = false; }
  if asm_constraint_is_output("r") { ok = false; }
  if asm_constraint_is_output("&r") { ok = false; }
  if asm_constraint_is_output("") { ok = false; }
  return assert(ok, "output modifiers are = and + only");
}

fn t9() -> TestResult {
  var ok = emits_as("$0 + $1", "${0} + ${1}");
  if !emits_as("${3:rm}", "${3:rm}") { ok = false; }
  if !emits_as("a$0b", "a${0}b") { ok = false; }
  if !emits_as("no operands", "no operands") { ok = false; }
  return assert(ok, "canonical emission always braces operands");
}

fn t10() -> TestResult {
  var ok = emits_as("cost $$5", "cost $$5");
  if !emits_as("$$$$", "$$$$") { ok = false; }
  if !emits_as("a$$b", "a$$b") { ok = false; }
  return assert(ok, "canonical emission re-escapes literal dollars");
}

fn t11() -> TestResult {
  var ok = round_trip("${0:r} = ${1:r} + ${2:r}");
  if !round_trip("x $0 y $1 z") { ok = false; }
  if !round_trip("${12:g}") { ok = false; }
  if !round_trip("") { ok = false; }
  if !round_trip("$0$1$2") { ok = false; }
  if !round_trip("cost $$5 and $3") { ok = false; }
  return assert(ok, "template round trips preserve structure and are idempotent");
}

fn t12() -> TestResult {
  var ok = tpl_err("$", "asm: dangling '$' at 0");
  if !tpl_err("ab$", "asm: dangling '$' at 2") { ok = false; }
  return assert(ok, "a dangling dollar is Err with its offset");
}

fn t13() -> TestResult {
  var ok = tpl_err("$x", "asm: bad operand index at 0");
  if !tpl_err("${}", "asm: bad operand index at 0") { ok = false; }
  if !tpl_err("${:r}", "asm: bad operand index at 0") { ok = false; }
  if !tpl_err("a${:r}", "asm: bad operand index at 1") { ok = false; }
  if !tpl_err("${", "asm: bad operand index at 0") { ok = false; }
  return assert(ok, "a missing operand index is Err with the dollar offset");
}

fn t14() -> TestResult {
  var ok = tpl_err("${0", "asm: unterminated operand at 0");
  if !tpl_err("${0:r", "asm: unterminated operand at 0") { ok = false; }
  if !tpl_err("x${12:i", "asm: unterminated operand at 1") { ok = false; }
  return assert(ok, "an unterminated operand is Err");
}

fn t15() -> TestResult {
  var ok = tpl_err("${0:}", "asm: empty constraint at 0");
  if !tpl_err("a${0:}", "asm: empty constraint at 1") { ok = false; }
  return assert(ok, "an empty constraint is Err");
}

fn t16() -> TestResult {
  var ok = tpl_err("${0:@}", "asm: bad constraint character at 4");
  if !tpl_err("${0:r@}", "asm: bad constraint character at 5") { ok = false; }
  if !tpl_err("${0x}", "asm: bad constraint character at 3") { ok = false; }
  if !tpl_err("${0: }", "asm: bad constraint character at 4") { ok = false; }
  return assert(ok, "a byte after the index must be : or }");
}

fn t17() -> TestResult {
  var ok = tpl_err("${10000000000}", "asm: operand index overflow at 0");
  if !tpl_err("$10000000000", "asm: operand index overflow at 0") { ok = false; }
  return assert(ok, "operand indexes are capped by the overflow guard");
}

fn t18() -> TestResult {
  let r = asm_template_parse("$0 x");
  var ok = false;
  match r {
    Ok(t) => {
      ok = streq(asm_template_kind(&t, -1), "");
      if !streq(asm_template_kind(&t, 5), "") { ok = false; }
      if !streq(asm_template_text(&t, 9), "") { ok = false; }
      if asm_template_index(&t, 9) != -1 { ok = false; }
      if asm_template_uses(&t, -1) != 0 { ok = false; }
      if asm_template_uses(&t, 4) != 0 { ok = false; }
      if asm_template_chunk_count(&t) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "chunk accessors are bounds-safe with empty sentinels");
}

fn t19() -> TestResult {
  var empty = Vec[Str].new();
  var ok = clob_is("", &empty);
  if !clob_is("   ", &empty) { ok = false; }
  var one = Vec[Str].new();
  one.push("rax");
  if !clob_is("rax", &one) { ok = false; }
  var two = Vec[Str].new();
  two.push("rax");
  two.push("rbx");
  if !clob_is("  rax,\trbx  ", &two) { ok = false; }
  var special = Vec[Str].new();
  special.push("memory");
  special.push("cc");
  if !clob_is("memory, cc", &special) { ok = false; }
  return assert(ok, "clobber lists split on commas and trim whitespace");
}

fn t20() -> TestResult {
  var ok = clob_err("rax,,rbx", "asm: empty clobber at 4");
  if !clob_err(",", "asm: empty clobber at 0") { ok = false; }
  if !clob_err("rax, rbx,", "asm: empty clobber at 9") { ok = false; }
  if !clob_err("r@x", "asm: bad clobber character at 1") { ok = false; }
  if !clob_err("rax,rax", "asm: duplicate clobber at 4") { ok = false; }
  return assert(ok, "empty, invalid and duplicate clobbers are Err");
}

fn t21() -> TestResult {
  let r = asm_clobbers_parse("rax, rbx");
  var ok = false;
  match r {
    Ok(v) => {
      ok = v.len() == 2;
      if !streq(asm_clobbers_emit(&v), "rax, rbx") { ok = false; }
      if !clob_is(asm_clobbers_emit(&v), &v) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var empty = Vec[Str].new();
  if !streq(asm_clobbers_emit(&empty), "") { ok = false; }
  return assert(ok, "clobber emission joins with a comma and round-trips");
}

fn t22() -> TestResult {
  var t = asm_template_new();
  asm_template_push_literal(&mut t, "mov ");
  asm_template_push_operand(&mut t, 0, "r");
  asm_template_push_literal(&mut t, " , ");
  asm_template_push_operand(&mut t, 1, "");
  asm_template_push_operand(&mut t, -1, "r");
  asm_template_push_literal(&mut t, "");
  var ok = streq(asm_template_emit(&t), "mov ${0:r} , ${1}");
  if asm_template_chunk_count(&t) != 4 { ok = false; }
  if asm_template_operand_count(&t) != 2 { ok = false; }
  if !round_trip(asm_template_emit(&t)) { ok = false; }
  return assert(ok, "the builder ignores empty text and negative indexes");
}

fn t23() -> TestResult {
  let r = asm_template_parse("$0 $0 ${2:r}");
  var ok = false;
  match r {
    Ok(t) => {
      ok = asm_template_uses(&t, 0) == 2;
      if asm_template_uses(&t, 1) != 0 { ok = false; }
      if asm_template_uses(&t, 2) != 1 { ok = false; }
      if asm_template_max_operand(&t) != 2 { ok = false; }
      if asm_template_operand_count(&t) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "operand use counting sees repeated references");
}

fn t24() -> TestResult {
  let r = asm_template_parse("${0:=r}");
  var ok = false;
  match r {
    Ok(t) => {
      ok = chunk_is(&t, 0, "op", "=r", 0);
      if !streq(asm_constraint_class(asm_template_text(&t, 0)), "register") { ok = false; }
      if !asm_constraint_is_output(asm_template_text(&t, 0)) { ok = false; }
      if !streq(asm_template_emit(&t), "${0:=r}") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "modifier constraints survive parse and emission verbatim");
}

fn main() -> Int {
  io.println("=== xiom.inline-asm conformance tests ===");
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
    io.println("xiom.inline-asm: all tests passed");
  } else {
    io.println("xiom.inline-asm: tests failed");
  }
  return failed;
}
