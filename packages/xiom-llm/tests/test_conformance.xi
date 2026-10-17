// XIOM -- xiom.llm conformance tests (M1: vocab extraction + byte-level BPE)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// M1 coverage: a synthetic deterministic GGUF fixture built entirely with
// xiom.gguf's builder (no external model downloads), vocab extraction from
// its metadata (model/tokens/merges/token_type/bos/eos), the accessor
// errors, byte-level BPE decode, encode and roundtrips over the fixture
// vocabulary (including the leftmost tie-break and dead merge entries),
// and the deterministic error catalog for malformed headers.
//
// Harness style mirrors xiom.gguf/xiom.safetensors: one fn tN() -> Int per
// check, called directly from main; main prints [PASS]/[FAIL] and returns
// the failure count. Str payloads are compared with str_compare, and every
// Vec/Result field read is bound to a typed local first.

module llm_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.string.builder;
use xiom.gguf;
use xiom.llm;
use bench.llm_bench;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ids_eq(a: &Vec[Int], w: &Vec[Int]) -> Bool {
  if a.len() != w.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = w[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn expect_vocab_err(r: Result[LlmVocab, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn expect_ids_err(r: Result[Vec[Int], Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn expect_str_err(r: Result[Str, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn expect_int_err(r: Result[Int, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn want1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn want2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn want3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn want4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn want5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn check_encode(v: &LlmVocab, text: Str, want: &Vec[Int], name: Str) -> Int {
  let r = llm_bpe_encode(v, text);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got_ids: Vec[Int] = r.value;
  return report(ids_eq(&got_ids, want), name);
}

fn check_decode(v: &LlmVocab, ids: &Vec[Int], want: Str, name: Str) -> Int {
  let r = llm_bpe_decode(v, ids);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got: Str = r.value;
  return report(str_eq(got, want), name);
}

// --------------------------------------------------
//  Synthetic fixture (built with xiom.gguf's builder)
// --------------------------------------------------

// Deterministic token list (20 tokens, ids 0..19). Byte-level BPE over a
// printable-ASCII alphabet; pieces beyond single bytes are exactly the
// results of the merge table below. Ids 18/19 are control tokens.
fn vocab_tokens() -> Vec[Str] {
  var t = Vec[Str].new();
  t.push("h");        // 0
  t.push("e");        // 1
  t.push("l");        // 2
  t.push("o");        // 3
  t.push("w");        // 4
  t.push("r");        // 5
  t.push("d");        // 6
  t.push(" ");        // 7
  t.push("!");        // 8
  t.push("he");       // 9
  t.push("ll");       // 10
  t.push("hell");     // 11
  t.push("hello");    // 12
  t.push("wo");       // 13
  t.push("wor");      // 14
  t.push("worl");     // 15
  t.push("world");    // 16
  t.push("lo");       // 17
  t.push("<s>");      // 18
  t.push("</s>");     // 19
  return t;
}

// Merge table (rank = index). Entry 9 has no space at byte index >= 1 and
// is therefore a dead pair ("" + " " + ""), pinning the llama.cpp
// `word.find(' ', 1)` split semantics and rank indexing.
fn vocab_merges() -> Vec[Str] {
  var m = Vec[Str].new();
  m.push("h e");     // 0 -> "he" (9)
  m.push("l l");     // 1 -> "ll" (10)
  m.push("he ll");   // 2 -> "hell" (11)
  m.push("hell o");  // 3 -> "hello" (12)
  m.push("w o");     // 4 -> "wo" (13)
  m.push("wo r");    // 5 -> "wor" (14)
  m.push("wor l");   // 6 -> "worl" (15)
  m.push("worl d");  // 7 -> "world" (16)
  m.push("l o");     // 8 -> "lo" (17)
  m.push("q");       // 9 -> dead pair
  return m;
}

// Token types for the 20 tokens: 1 (normal) except the two control tokens.
fn vocab_types() -> Vec[Int] {
  var t = Vec[Int].new();
  var i = 0;
  while i < 18 {
    t.push(1);
    i = i + 1;
  }
  t.push(3);  // 18 "<s>" control
  t.push(3);  // 19 "</s>" control
  return t;
}

// The full synthetic fixture: 6 metadata KVs, one tensor info
// (token_embd.weight, 20 x 2, ggml type 0, offset 0) and a 32-byte
// zero payload appended after the header.
fn tiny_gguf() -> Vec[UInt8] {
  let tokens = vocab_tokens();
  let merges = vocab_merges();
  let types = vocab_types();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let a4 = gguf_builder_add_kv_arr_int(&mut b, "tokenizer.ggml.token_type", 5, &types);
  let a5 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.bos_token_id", 4, 18);
  let a6 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.eos_token_id", 4, 19);
  var dims = Vec[Int].new();
  dims.push(20);
  dims.push(2);
  let a7 = gguf_builder_add_tensor(&mut b, "token_embd.weight", &dims, 0, 0);
  let fr = gguf_builder_finish(&b);
  var buf = fr.value;
  var pad = 0;
  while pad < 32 {
    buf.push((0 as UInt8));
    pad = pad + 1;
  }
  return buf;
}

// Fixture parsed and extracted. The fixture is deterministic and must
// extract; the explicit failure path is checked in t2 via tiny_gguf().
fn fixture_vocab() -> LlmVocab {
  let buf = tiny_gguf();
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return vr.value;
}

// Minimal header: fixed model/tokens/merges, no token types, no specials,
// no tensors.
fn header_plain(model: Str) -> Vec[UInt8] {
  let tokens = vocab_tokens();
  let merges = vocab_merges();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", model);
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let fr = gguf_builder_finish(&b);
  return fr.value;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

// The synthetic fixture parses: 6 KVs, 1 tensor, 32-byte data section.
fn t1() -> Int {
  let buf = tiny_gguf();
  let r = gguf_parse(&buf);
  if !r.is_ok {
    return report(false, "fixture parses");
  }
  let g = r.value;
  if gguf_kv_count(&g) != 6 || gguf_tensor_count(&g) != 1 {
    return report(false, "fixture: 6 KVs, 1 tensor");
  }
  return report(gguf_data_len(&g) == 32, "fixture: 32-byte data section");
}

// Vocab extraction: model and size.
fn t2() -> Int {
  let buf = tiny_gguf();
  let pr = gguf_parse(&buf);
  if !pr.is_ok {
    return report(false, "vocab extraction: parse");
  }
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  if !vr.is_ok {
    return report(false, "vocab extraction ok");
  }
  let v = vr.value;
  let m = llm_vocab_model(&v);
  if !str_eq(m, "gpt2") {
    return report(false, "vocab model gpt2");
  }
  return report(llm_vocab_size(&v) == 20, "vocab size 20");
}

// Token accessor strings.
fn t3() -> Int {
  let v = fixture_vocab();
  let t0 = llm_vocab_token(&v, 0);
  let t12 = llm_vocab_token(&v, 12);
  let t19 = llm_vocab_token(&v, 19);
  if !t0.is_ok || !t12.is_ok || !t19.is_ok {
    return report(false, "token accessors ok");
  }
  let s0: Str = t0.value;
  let s12: Str = t12.value;
  let s19: Str = t19.value;
  return report(str_eq(s0, "h") && str_eq(s12, "hello") && str_eq(s19, "</s>"), "token strings");
}

// Token types: stored values, normal default and both control tokens.
fn t4() -> Int {
  let v = fixture_vocab();
  let t0 = llm_vocab_token_type(&v, 0);
  let t18 = llm_vocab_token_type(&v, 18);
  let t19 = llm_vocab_token_type(&v, 19);
  return report(t0.value == 1 && t18.value == 3 && t19.value == 3, "token types");
}

// bos/eos ids from the fixture metadata.
fn t5() -> Int {
  let v = fixture_vocab();
  return report(llm_vocab_bos(&v) == 18 && llm_vocab_eos(&v) == 19, "bos/eos ids");
}

// find_token: hit and miss.
fn t6() -> Int {
  let v = fixture_vocab();
  return report(llm_vocab_find_token(&v, "hello") == 12 && llm_vocab_find_token(&v, "nope") == -1, "find_token hit/miss");
}

// Merge table: count, canonical rendering, dead entry.
fn t7() -> Int {
  let v = fixture_vocab();
  if llm_vocab_merge_count(&v) != 10 {
    return report(false, "merge count 10");
  }
  let m0 = llm_vocab_merge(&v, 0);
  let m3 = llm_vocab_merge(&v, 3);
  let m9 = llm_vocab_merge(&v, 9);
  if !m0.is_ok || !m3.is_ok || !m9.is_ok {
    return report(false, "merge accessors ok");
  }
  let s0: Str = m0.value;
  let s3: Str = m3.value;
  let s9: Str = m9.value;
  return report(str_eq(s0, "h e") && str_eq(s3, "hell o") && str_eq(s9, " "), "merge entries and dead pair");
}

// Accessor range errors.
fn t8() -> Int {
  let v = fixture_vocab();
  let a = llm_vocab_token(&v, -1);
  let b = llm_vocab_token(&v, 20);
  let c = llm_vocab_token_type(&v, 99);
  let d = llm_vocab_merge(&v, 10);
  var sum = 0;
  sum = sum + expect_str_err(a, "llm: token index out of range", "token(-1) rejected");
  sum = sum + expect_str_err(b, "llm: token index out of range", "token(20) rejected");
  sum = sum + expect_int_err(c, "llm: token index out of range", "token_type(99) rejected");
  sum = sum + expect_str_err(d, "llm: merge index out of range", "merge(10) rejected");
  return sum;
}

// Decode single id and multi-id sequences.
fn t9() -> Int {
  let v = fixture_vocab();
  let w1 = want1(12);
  let w2 = want4(12, 7, 16, 8);
  let w3 = want4(11, 7, 16, 8);
  var sum = 0;
  sum = sum + check_decode(&v, &w1, "hello", "decode [12]");
  sum = sum + check_decode(&v, &w2, "hello world!", "decode [12,7,16,8]");
  sum = sum + check_decode(&v, &w3, "hell world!", "decode [11,7,16,8]");
  return sum;
}

// Decode of the empty id list.
fn t10() -> Int {
  let v = fixture_vocab();
  var none = Vec[Int].new();
  return check_decode(&v, &none, "", "decode []");
}

// Encode: single-token and multi-token texts.
fn t11() -> Int {
  let v = fixture_vocab();
  let w1 = want1(12);
  let w2 = want3(12, 7, 16);
  let w3 = want4(11, 7, 16, 8);
  var sum = 0;
  sum = sum + check_encode(&v, "hello", &w1, "encode hello");
  sum = sum + check_encode(&v, "hello world", &w2, "encode hello world");
  sum = sum + check_encode(&v, "hell world!", &w3, "encode hell world!");
  return sum;
}

// Encode: partial merges stop at the vocabulary boundary.
fn t12() -> Int {
  let v = fixture_vocab();
  let w1 = want3(9, 2, 6);
  let w2 = want2(17, 2);
  var sum = 0;
  sum = sum + check_encode(&v, "held", &w1, "encode held");
  sum = sum + check_encode(&v, "lol", &w2, "encode lol");
  return sum;
}

// Encode tie-break: "llll" merges leftmost-first into [ll, ll]; the
// alternative pairing would yield [l, ll, l].
fn t13() -> Int {
  let v = fixture_vocab();
  let w1 = want2(10, 10);
  let w2 = want1(7);
  var sum = 0;
  sum = sum + check_encode(&v, "llll", &w1, "encode llll (leftmost tie-break)");
  sum = sum + check_encode(&v, " ", &w2, "encode single space");
  return sum;
}

// Encode of empty text is the empty id list.
fn t14() -> Int {
  let v = fixture_vocab();
  var none = Vec[Int].new();
  return check_encode(&v, "", &none, "encode empty");
}

// Roundtrips: decode(encode(x)) == x over the fixture domain.
fn t15() -> Int {
  let v = fixture_vocab();
  var texts = Vec[Str].new();
  texts.push("hello");
  texts.push("hello world");
  texts.push("hell world!");
  texts.push("held");
  texts.push("lol");
  texts.push("llll");
  texts.push(" ");
  texts.push("!");
  var bad = 0;
  var i = 0;
  while i < texts.len() {
    let x: Str = texts[i];
    let er = llm_bpe_encode(&v, x);
    if !er.is_ok {
      bad = bad + 1;
    } else {
      let ids: Vec[Int] = er.value;
      let dr = llm_bpe_decode(&v, &ids);
      if !dr.is_ok {
        bad = bad + 1;
      } else {
        let y: Str = dr.value;
        if !str_eq(y, x) {
          bad = bad + 1;
        }
      }
    }
    i = i + 1;
  }
  return report(bad == 0, "encode/decode roundtrips (8 texts)");
}

// Encode canonical ids: re-encoding a decoded sequence gives the same ids.
fn t16() -> Int {
  let v = fixture_vocab();
  let ids = want3(11, 7, 16);
  let dr = llm_bpe_decode(&v, &ids);
  if !dr.is_ok {
    return report(false, "re-encode: decode ok");
  }
  let s: Str = dr.value;
  let er = llm_bpe_encode(&v, s);
  if !er.is_ok {
    return report(false, "re-encode: encode ok");
  }
  let back: Vec[Int] = er.value;
  return report(ids_eq(&back, &ids), "encode(decode(ids)) == ids");
}

// A byte outside the vocabulary is a fail-closed encode error.
fn t17() -> Int {
  let v = fixture_vocab();
  let r = llm_bpe_encode(&v, "z");
  return expect_ids_err(r, "llm: byte not in vocabulary", "unknown byte rejected");
}

// Out-of-range decode ids.
fn t18() -> Int {
  let v = fixture_vocab();
  let w1 = want1(20);
  let w2 = want1(-1);
  let a = llm_bpe_decode(&v, &w1);
  let b = llm_bpe_decode(&v, &w2);
  var sum = 0;
  sum = sum + expect_str_err(a, "llm: token id out of range", "decode [20] rejected");
  sum = sum + expect_str_err(b, "llm: token id out of range", "decode [-1] rejected");
  return sum;
}

// Unsupported tokenizer model.
fn t19() -> Int {
  let buf = header_plain("llama");
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: unsupported tokenizer model", "model llama rejected");
}

// Missing model key.
fn t20() -> Int {
  let tokens = vocab_tokens();
  let merges = vocab_merges();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let fr = gguf_builder_finish(&b);
  let buf = fr.value;
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: tokenizer model missing", "model missing rejected");
}

// Model of the wrong value kind.
fn t21() -> Int {
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_float(&mut b, "tokenizer.ggml.model", 6, "0000803f");
  let fr = gguf_builder_finish(&b);
  let buf = fr.value;
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: tokenizer model is not a string", "non-string model rejected");
}

// Missing tokens key.
fn t22() -> Int {
  let merges = vocab_merges();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let fr = gguf_builder_finish(&b);
  let buf = fr.value;
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: tokenizer tokens missing", "tokens missing rejected");
}

// Tokens of the wrong array kind.
fn t23() -> Int {
  let merges = vocab_merges();
  var ints = Vec[Int].new();
  ints.push(1);
  ints.push(2);
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_int(&mut b, "tokenizer.ggml.tokens", 4, &ints);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let fr = gguf_builder_finish(&b);
  let buf = fr.value;
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: tokenizer tokens is not a string array", "int tokens rejected");
}

// Missing merges key.
fn t24() -> Int {
  let tokens = vocab_tokens();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let fr = gguf_builder_finish(&b);
  let buf = fr.value;
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: tokenizer merges missing", "merges missing rejected");
}

// token_type array shorter than the token count.
fn t25() -> Int {
  let tokens = vocab_tokens();
  let merges = vocab_merges();
  var short_types = Vec[Int].new();
  var i = 0;
  while i < 19 {
    short_types.push(1);
    i = i + 1;
  }
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let a4 = gguf_builder_add_kv_arr_int(&mut b, "tokenizer.ggml.token_type", 5, &short_types);
  let fr = gguf_builder_finish(&b);
  let buf = fr.value;
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: token type count smaller than token count", "short token_type rejected");
}

// token_type of the wrong array kind.
fn t26() -> Int {
  let tokens = vocab_tokens();
  let merges = vocab_merges();
  var strs = Vec[Str].new();
  strs.push("1");
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let a4 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.token_type", &strs);
  let fr = gguf_builder_finish(&b);
  let buf = fr.value;
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: token types are not an integer array", "string token_type rejected");
}

// bos id of the wrong value kind.
fn t27() -> Int {
  let tokens = vocab_tokens();
  let merges = vocab_merges();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let a4 = gguf_builder_add_kv_float(&mut b, "tokenizer.ggml.bos_token_id", 6, "0000803f");
  let fr = gguf_builder_finish(&b);
  let buf = fr.value;
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  return expect_vocab_err(vr, "llm: bos token id is not an integer", "non-integer bos rejected");
}

// Plain header: token types default to 1, bos/eos absent (-1).
fn t28() -> Int {
  let buf = header_plain("gpt2");
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  if !vr.is_ok {
    return report(false, "plain header extracts");
  }
  let v = vr.value;
  let t0 = llm_vocab_token_type(&v, 0);
  if t0.value != 1 {
    return report(false, "plain header: default type 1");
  }
  return report(llm_vocab_bos(&v) == -1 && llm_vocab_eos(&v) == -1, "plain header: bos/eos absent (-1)");
}

// --------------------------------------------------
//  M2a: GGML size tables + tensor extent validation
// --------------------------------------------------

// Header with one f32 tensor (d0 x d1) at offset 0 and `payload_len` bytes
// of zero payload appended after the header.
fn tensor_fixture(ty: Int, d0: Int, d1: Int, payload_len: Int) -> Vec[UInt8] {
  var b = gguf_builder_new();
  var dims = Vec[Int].new();
  dims.push(d0);
  dims.push(d1);
  let a1 = gguf_builder_add_tensor(&mut b, "w", &dims, ty, 0);
  let fr = gguf_builder_finish(&b);
  var buf = fr.value;
  var i = 0;
  while i < payload_len {
    buf.push((0 as UInt8));
    i = i + 1;
  }
  return buf;
}

// Same, but the payload byte at offset k is (k + 1) mod 256, so extraction
// can be checked position-by-position.
fn tensor_fixture_pattern(ty: Int, d0: Int, d1: Int, payload_len: Int) -> Vec[UInt8] {
  var b = gguf_builder_new();
  var dims = Vec[Int].new();
  dims.push(d0);
  dims.push(d1);
  let a1 = gguf_builder_add_tensor(&mut b, "w", &dims, ty, 0);
  let fr = gguf_builder_finish(&b);
  var buf = fr.value;
  var i = 0;
  while i < payload_len {
    buf.push(((i + 1) as UInt8));
    i = i + 1;
  }
  return buf;
}

fn expect_int_bytes_err(r: Result[Vec[UInt8], Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

// GGML type name / block-elements / block-bytes tables.
fn t29() -> Int {
  if !str_eq(llm_ggml_type_name(0), "f32") { return report(false, "type name f32"); }
  if !str_eq(llm_ggml_type_name(8), "q8_0") { return report(false, "type name q8_0"); }
  if !str_eq(llm_ggml_type_name(14), "q6_K") { return report(false, "type name q6_K"); }
  if !str_eq(llm_ggml_type_name(999), "unknown") { return report(false, "type name unknown"); }
  if llm_ggml_block_elems(0) != 1 || llm_ggml_block_elems(1) != 1 {
    return report(false, "block elems f32/f16 = 1");
  }
  if llm_ggml_block_elems(2) != 32 || llm_ggml_block_elems(8) != 32 {
    return report(false, "block elems q4_0/q8_0 = 32");
  }
  if llm_ggml_block_elems(12) != 256 || llm_ggml_block_elems(999) != 0 {
    return report(false, "block elems q4_K = 256 / unknown = 0");
  }
  if llm_ggml_block_bytes(0) != 4 || llm_ggml_block_bytes(1) != 2 {
    return report(false, "block bytes f32=4 f16=2");
  }
  if llm_ggml_block_bytes(2) != 18 || llm_ggml_block_bytes(8) != 34 {
    return report(false, "block bytes q4_0=18 q8_0=34");
  }
  if llm_ggml_block_bytes(12) != 144 || llm_ggml_block_bytes(14) != 210 || llm_ggml_block_bytes(999) != 0 {
    return report(false, "block bytes q4_K/q6_K/unknown");
  }
  return report(true, "ggml size tables");
}

// nbytes: 20 x 2 f32 = 40 elements * 4 bytes = 160.
fn t30() -> Int {
  let buf = tensor_fixture(0, 20, 2, 0);
  let pr = gguf_parse(&buf);
  if !pr.is_ok {
    return report(false, "nbytes: parse");
  }
  let g = pr.value;
  let r = llm_tensor_nbytes(&g, 0);
  if !r.is_ok {
    return report(false, "nbytes: ok");
  }
  let n: Int = r.value;
  return report(n == 160, "nbytes 20x2 f32 = 160");
}

// nbytes rejects a ggml type with no size entry (type 4).
fn t31() -> Int {
  let buf = tensor_fixture(4, 8, 1, 0);
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let r = llm_tensor_nbytes(&g, 0);
  return expect_int_err(r, "llm: unknown ggml type", "nbytes unknown type rejected");
}

// nbytes rejects dims not divisible by the block element count (q4_0 = 32).
fn t32() -> Int {
  let buf = tensor_fixture(2, 20, 1, 0);
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let r = llm_tensor_nbytes(&g, 0);
  return expect_int_err(r, "llm: tensor dims not divisible by block size", "nbytes non-divisible dims rejected");
}

// nbytes rejects an out-of-range tensor index.
fn t33() -> Int {
  let buf = tensor_fixture(0, 20, 2, 0);
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let a = llm_tensor_nbytes(&g, -1);
  let b = llm_tensor_nbytes(&g, 9);
  var sum = 0;
  sum = sum + expect_int_err(a, "llm: tensor index out of range", "nbytes(-1) rejected");
  sum = sum + expect_int_err(b, "llm: tensor index out of range", "nbytes(9) rejected");
  return sum;
}

// tensor_data extracts the exact 160-byte payload slice, position-checked.
fn t34() -> Int {
  let buf = tensor_fixture_pattern(0, 20, 2, 160);
  let pr = gguf_parse(&buf);
  if !pr.is_ok {
    return report(false, "tensor_data: parse");
  }
  let g = pr.value;
  let r = llm_tensor_data(&g, &buf, 0);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, "tensor_data: ok (Err: " + got + ")");
  }
  let out: Vec[UInt8] = r.value;
  if out.len() != 160 {
    return report(false, "tensor_data length 160");
  }
  let b0: UInt8 = out[0];
  let b5: UInt8 = out[5];
  let b159: UInt8 = out[159];
  let v0 = (b0 as Int) & 0xFF;
  let v5 = (b5 as Int) & 0xFF;
  let v159 = (b159 as Int) & 0xFF;
  return report(v0 == 1 && v5 == 6 && v159 == 160 % 256, "tensor_data pattern bytes");
}

// tensor_data rejects an extent that exceeds the declared data section
// (needs 160 bytes, container declares 32).
fn t35() -> Int {
  let buf = tensor_fixture(0, 20, 2, 32);
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let r = llm_tensor_data(&g, &buf, 0);
  return expect_int_bytes_err(r, "llm: tensor extent out of data section", "oversize extent rejected");
}

// tensor_data rejects a container buffer that is too small for the slice.
fn t36() -> Int {
  let buf = tensor_fixture(0, 20, 2, 160);
  let pr = gguf_parse(&buf);
  let g = pr.value;
  var small = Vec[UInt8].new();
  let r = llm_tensor_data(&g, &small, 0);
  return expect_int_bytes_err(r, "llm: buffer too small for tensor extent", "short buffer rejected");
}

// --------------------------------------------------
//  M2a: integer bit-decode + Q8_0 dequantization
// --------------------------------------------------

fn expect_scale_err(r: Result[LlmScale, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

// One Q8_0 block: little-endian f16 `scale_bits` then the 32 int8 quants
// (each written as its low byte; negatives use two's complement).
fn q8_block(scale_bits: Int, quants: &Vec[Int]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(((scale_bits & 0xFF) as UInt8));
  v.push((((scale_bits >> 8) & 0xFF) as UInt8));
  var i = 0;
  while i < quants.len() {
    let q: Int = quants[i];
    v.push(((q & 0xFF) as UInt8));
    i = i + 1;
  }
  return v;
}

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) -> Int {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
  return 0;
}

// f16 bit decode: normalised, subnormal, negative and zero (exact vectors).
fn t37() -> Int {
  let a = llm_f16_to_scaled(0x3C00);   // 1.0
  let b = llm_f16_to_scaled(0x3800);   // 0.5
  let c = llm_f16_to_scaled(0x4000);   // 2.0
  let d = llm_f16_to_scaled(0xBC00);   // -1.0
  let e = llm_f16_to_scaled(0x0001);   // smallest subnormal
  let f = llm_f16_to_scaled(0x0000);   // +0.0
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok || !e.is_ok || !f.is_ok {
    return report(false, "f16 decode ok");
  }
  let sa: LlmScale = a.value;
  let sb: LlmScale = b.value;
  let sc: LlmScale = c.value;
  let sd: LlmScale = d.value;
  let se: LlmScale = e.value;
  let sf: LlmScale = f.value;
  if sa.m != 1024 || sa.e != 10 { return report(false, "f16 1.0 = 1024/2^10"); }
  if sb.m != 1024 || sb.e != 11 { return report(false, "f16 0.5 = 1024/2^11"); }
  if sc.m != 1024 || sc.e != 9 { return report(false, "f16 2.0 = 1024/2^9"); }
  if sd.m != -1024 || sd.e != 10 { return report(false, "f16 -1.0 = -1024/2^10"); }
  if se.m != 1 || se.e != 24 { return report(false, "f16 subnormal = 1/2^24"); }
  if sf.m != 0 || sf.e != 0 { return report(false, "f16 +0.0 = 0"); }
  return report(true, "f16 bit decode");
}

// f16 inf/nan reject arms.
fn t38() -> Int {
  let a = llm_f16_to_scaled(0x7C00);
  let b = llm_f16_to_scaled(0x7E00);
  var sum = 0;
  sum = sum + expect_scale_err(a, "llm: f16 is inf", "f16 inf rejected");
  sum = sum + expect_scale_err(b, "llm: f16 is nan", "f16 nan rejected");
  return sum;
}

// f32 bit decode: normalised, negative and subnormal (exact vectors).
fn t39() -> Int {
  let a = llm_f32_to_scaled(0x3F800000);  // 1.0
  let b = llm_f32_to_scaled(0x40000000);  // 2.0
  let c = llm_f32_to_scaled(0x3F000000);  // 0.5
  let d = llm_f32_to_scaled(0xBF800000);  // -1.0
  let e = llm_f32_to_scaled(0x00000001);  // smallest subnormal
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok || !e.is_ok {
    return report(false, "f32 decode ok");
  }
  let sa: LlmScale = a.value;
  let sb: LlmScale = b.value;
  let sc: LlmScale = c.value;
  let sd: LlmScale = d.value;
  let se: LlmScale = e.value;
  if sa.m != 8388608 || sa.e != 23 { return report(false, "f32 1.0 = 8388608/2^23"); }
  if sb.m != 8388608 || sb.e != 22 { return report(false, "f32 2.0 = 8388608/2^22"); }
  if sc.m != 8388608 || sc.e != 24 { return report(false, "f32 0.5 = 8388608/2^24"); }
  if sd.m != -8388608 || sd.e != 23 { return report(false, "f32 -1.0 = -8388608/2^23"); }
  if se.m != 1 || se.e != 149 { return report(false, "f32 subnormal = 1/2^149"); }
  return report(true, "f32 bit decode");
}

// Q8_0 golden vector: one block, scale 1.0 (0x3C00), quants -8..23.
// Exact scaled-int asserts: out[i] == (i-8) * 1024, shared scale (1024, 10).
fn t40() -> Int {
  var quants = Vec[Int].new();
  var i = 0;
  while i < 32 {
    quants.push(i - 8);
    i = i + 1;
  }
  let payload = q8_block(0x3C00, &quants);
  var out = Vec[Int].new();
  let r = llm_dequant_q8_0(&payload, &mut out);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, "q8_0 decode ok (Err: " + got + ")");
  }
  let s: LlmScale = r.value;
  if s.m != 1024 || s.e != 10 {
    return report(false, "q8_0 scale (1024,10)");
  }
  if out.len() != 32 {
    return report(false, "q8_0 out length 32");
  }
  var bad = 0;
  var k = 0;
  while k < 32 {
    let got: Int = out[k];
    if got != (k - 8) * 1024 {
      bad = bad + 1;
    }
    k = k + 1;
  }
  let o0: Int = out[0];
  let o8: Int = out[8];
  let o31: Int = out[31];
  if o0 != -8192 || o8 != 0 || o31 != 23552 {
    return report(false, "q8_0 spot values");
  }
  return report(bad == 0, "q8_0 golden vector exact (scale 1.0)");
}

// Q8_0 negative scale and two blocks: scale -1.0 (0xBC00), quants all +1.
// Exact: out[i] == -1024 for all 64 outputs, shared scale (-1024, 10).
fn t41() -> Int {
  var ones = Vec[Int].new();
  var i = 0;
  while i < 32 {
    ones.push(1);
    i = i + 1;
  }
  var payload = q8_block(0xBC00, &ones);
  let blk2 = q8_block(0xBC00, &ones);
  let a = append_bytes(&mut payload, &blk2);
  var out = Vec[Int].new();
  let r = llm_dequant_q8_0(&payload, &mut out);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, "q8_0 2-block decode ok (Err: " + got + ")");
  }
  let s: LlmScale = r.value;
  if s.m != -1024 || s.e != 10 {
    return report(false, "q8_0 -1.0 scale (-1024,10)");
  }
  if out.len() != 64 {
    return report(false, "q8_0 2-block out length 64");
  }
  var bad = 0;
  var k = 0;
  while k < 64 {
    let got: Int = out[k];
    if got != -1024 {
      bad = bad + 1;
    }
    k = k + 1;
  }
  return report(bad == 0, "q8_0 negative scale, two blocks exact");
}

// Q8_0 rejects a payload whose length is not a multiple of 34 and an empty one.
fn t42() -> Int {
  var short = Vec[UInt8].new();
  var i = 0;
  while i < 33 {
    short.push((0 as UInt8));
    i = i + 1;
  }
  var empty = Vec[UInt8].new();
  var out1 = Vec[Int].new();
  var out2 = Vec[Int].new();
  let a = llm_dequant_q8_0(&short, &mut out1);
  let b = llm_dequant_q8_0(&empty, &mut out2);
  var sum = 0;
  sum = sum + expect_scale_err(a, "llm: q8_0 payload length not a multiple of block size", "q8_0 bad length rejected");
  sum = sum + expect_scale_err(b, "llm: q8_0 payload is empty", "q8_0 empty payload rejected");
  return sum;
}

// Q8_0 rejects mixed per-block scales (single shared (m,e) surface).
fn t43() -> Int {
  var ones = Vec[Int].new();
  var i = 0;
  while i < 32 {
    ones.push(1);
    i = i + 1;
  }
  var payload = q8_block(0x3C00, &ones);
  let blk2 = q8_block(0x3800, &ones);
  let a = append_bytes(&mut payload, &blk2);
  var out = Vec[Int].new();
  let r = llm_dequant_q8_0(&payload, &mut out);
  return expect_scale_err(r, "llm: q8_0 mixed block scales are not supported", "q8_0 mixed scales rejected");
}

// --------------------------------------------------
//  M2b: matmul + forward primitives (golden vectors)
// --------------------------------------------------

fn expect_mat_err(r: Result[Vec[Int], Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

// 2x3 @ 3x2 integer matmul, exact golden; plus overflow and size rejects.
fn t44() -> Int {
  var a = Vec[Int].new();
  a.push(1); a.push(2); a.push(3);
  a.push(4); a.push(5); a.push(6);
  var b = Vec[Int].new();
  b.push(7); b.push(8);
  b.push(9); b.push(10);
  b.push(11); b.push(12);
  let r = llm_matmul_i32(&a, 2, 3, &b, 2);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, "matmul 2x3 @ 3x2 ok (Err: " + got + ")");
  }
  let m: Vec[Int] = r.value;
  if m.len() != 4 {
    return report(false, "matmul out length 4");
  }
  let want = want4(58, 64, 139, 154);
  if !ids_eq(&m, &want) {
    return report(false, "matmul golden [58,64,139,154]");
  }
  // overflow: 3e9 * 3e9 exceeds the Int guard
  var oa = Vec[Int].new();
  oa.push(3000000000); oa.push(3000000000);
  var ob = Vec[Int].new();
  ob.push(3000000000); ob.push(3000000000);
  let ov = llm_matmul_i32(&oa, 1, 2, &ob, 1);
  // size mismatch
  var bad = Vec[Int].new();
  bad.push(1); bad.push(2); bad.push(3); bad.push(4); bad.push(5);
  let mm = llm_matmul_i32(&bad, 2, 3, &b, 2);
  var sum = 0;
  sum = sum + expect_mat_err(ov, "llm: matmul overflow", "matmul overflow rejected");
  sum = sum + expect_mat_err(mm, "llm: matmul a size mismatch", "matmul size mismatch rejected");
  return sum;
}

// RMSNorm: exact golden on [4,4,0,0] (mean square 8, rms 2) and zero-norm reject.
fn t45() -> Int {
  var x = Vec[Int].new();
  x.push(4); x.push(4); x.push(0); x.push(0);
  var g = Vec[Int].new();
  g.push(1); g.push(1); g.push(1); g.push(1);
  let r = llm_rmsnorm_i32(&x, &g, 0, 0);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, "rmsnorm ok (Err: " + got + ")");
  }
  let y: Vec[Int] = r.value;
  let want = want4(2, 2, 0, 0);
  var sum = 0;
  sum = sum + report(ids_eq(&y, &want), "rmsnorm golden [2,2,0,0]");
  var z = Vec[Int].new();
  z.push(0); z.push(0); z.push(0); z.push(0);
  let zr = llm_rmsnorm_i32(&z, &g, 0, 0);
  sum = sum + expect_mat_err(zr, "llm: rmsnorm zero norm", "rmsnorm zero norm rejected");
  return sum;
}

// RoPE: exact identity table (pos 0) and exact 90-degree rotation.
fn t46() -> Int {
  let s = 12;
  var cq = Vec[Int].new();
  cq.push(1 << s); cq.push(1 << s);
  var sq = Vec[Int].new();
  sq.push(0); sq.push(0);
  var x = Vec[Int].new();
  x.push(3); x.push(5); x.push(7); x.push(9);
  let idr = llm_rope_i32(&x, 4, &cq, &sq, s);
  if !idr.is_ok {
    let got: Str = idr.error;
    return report(false, "rope identity ok (Err: " + got + ")");
  }
  let idv: Vec[Int] = idr.value;
  let want_id = want4(3, 5, 7, 9);
  var sum = 0;
  sum = sum + report(ids_eq(&idv, &want_id), "rope identity golden");
  // 90-degree: cos 0, sin 1.0 -> (x0,x1) -> (-x1, x0)
  var cq90 = Vec[Int].new();
  cq90.push(0); cq90.push(0);
  var sq90 = Vec[Int].new();
  sq90.push(1 << s); sq90.push(1 << s);
  let rr = llm_rope_i32(&x, 4, &cq90, &sq90, s);
  if !rr.is_ok {
    let got2: Str = rr.error;
    return report(false, "rope 90-degree ok (Err: " + got2 + ")");
  }
  let rv: Vec[Int] = rr.value;
  let want_90 = want4(-5, 3, -9, 7);
  sum = sum + report(ids_eq(&rv, &want_90), "rope 90-degree golden [-5,3,-9,7]");
  return sum;
}

// Softmax: exact single-element (one-hot) and uniform goldens; empty reject.
fn t47() -> Int {
  var one = Vec[Int].new();
  one.push(4);
  let sr = llm_softmax_i32(&one, 10);
  if !sr.is_ok {
    let got: Str = sr.error;
    return report(false, "softmax single ok (Err: " + got + ")");
  }
  let sv: Vec[Int] = sr.value;
  let want_1 = want1(1024);
  var sum = 0;
  sum = sum + report(ids_eq(&sv, &want_1), "softmax single golden [1024]");
  var uni = Vec[Int].new();
  uni.push(0); uni.push(0);
  let ur = llm_softmax_i32(&uni, 10);
  let uv: Vec[Int] = ur.value;
  let want_u = want2(512, 512);
  sum = sum + report(ids_eq(&uv, &want_u), "softmax uniform golden [512,512]");
  var none = Vec[Int].new();
  let er = llm_softmax_i32(&none, 10);
  sum = sum + expect_mat_err(er, "llm: softmax empty input", "softmax empty rejected");
  return sum;
}

// SiLU saturating-region exactness and SwiGLU exact golden.
fn t48() -> Int {
  var sum = 0;
  sum = sum + report(llm_silu_q(5, 0) == 5, "silu(5) = 5 exact");
  sum = sum + report(llm_silu_q(-5, 0) == 0, "silu(-5) = 0 exact");
  sum = sum + report(llm_silu_q(0, 0) == 0, "silu(0) = 0 exact");
  var gate = Vec[Int].new();
  gate.push(5); gate.push(5);
  var up = Vec[Int].new();
  up.push(-2); up.push(-2);
  let r = llm_swiglu_i32(&gate, &up, 0);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, "swiglu ok (Err: " + got + ")");
  }
  let a: Vec[Int] = r.value;
  let want = want2(-10, -10);
  sum = sum + report(ids_eq(&a, &want), "swiglu golden [-10,-10]");
  return sum;
}

// --------------------------------------------------
//  M2b: tiny deterministic model fixture
// --------------------------------------------------

// float32 bit pattern of a small integer (0..19 and -1), exactly representable.
fn f32_bits_of_int(n: Int) -> Int {
  if n == 0 {
    return 0;
  }
  if n < 0 {
    return f32_bits_of_int(0 - n) | 0x80000000;
  }
  var e = 0;
  var m = n;
  while m >= 2 {
    m = m / 2;
    e = e + 1;
  }
  let mant = (n << (23 - e)) - 0x800000;
  return ((127 + e) << 23) | mant;
}

// Append the little-endian 4-byte encoding of small integer `n` as f32.
fn push_f32(dst: &mut Vec[UInt8], n: Int) -> Int {
  let bits = f32_bits_of_int(n);
  dst.push(((bits & 0xFF) as UInt8));
  dst.push((((bits >> 8) & 0xFF) as UInt8));
  dst.push((((bits >> 16) & 0xFF) as UInt8));
  dst.push((((bits >> 24) & 0xFF) as UInt8));
  return 0;
}

// Append one Q8_0 block: scale 1.0 (0x3C00) and 32 quant bytes.
fn push_q8_scale1(dst: &mut Vec[UInt8], quants: &Vec[Int]) -> Int {
  dst.push((0x00 as UInt8));
  dst.push((0x3C as UInt8));
  var i = 0;
  while i < quants.len() {
    let q: Int = quants[i];
    dst.push(((q & 0xFF) as UInt8));
    i = i + 1;
  }
  return 0;
}

// Append one Q8_0 block followed by zero padding to a 128-byte f32 slice.
// xiom.gguf's builder rejects types 8/9, so the fixture stores quantized weights
// as Q8_0 block bytes inside a f32-declared 8x4/4x8 slice (documented
// deviation); llm_dequant_q8_0 consumes the leading 34 bytes.
fn push_q8_padded(dst: &mut Vec[UInt8], quants: &Vec<Int>) -> Int {
  let a = push_q8_scale1(dst, quants);
  var pad = 0;
  while pad < 94 {
    dst.push((0 as UInt8));
    pad = pad + 1;
  }
  return 0;
}

// The tiny model container: emb=4, heads=1, vocab=20, ffn=8, 1 layer. Eleven
// tensor infos (token_embd, attn_norm, wq/wk/wv/wo, ffn_norm, ffn_gate/up/down,
// output); Q8_0 for the 8x4 / 4x8 FFN matrices, f32 elsewhere. `w1_first` is
// the ffn_gate first quant (4 normally, 3 in the sensitivity variant).
// Build the fixture model with explicit token-embedding row values: row 0 =
// [e00,e01,0,0], row 1 = [e10,e11,0,0] (rows 2..19 zero). `model_container`
// keeps the M2/M3a values (4,4,4,4); `mp_container` uses (4,4,3,0) so the two
// forwardable tokens normalize to different q/k/v (multi-position goldens).
fn model_container_emb(e00: Int, e01: Int, e10: Int, e11: Int, w1_first: Int) -> Vec[UInt8] {
  let tokens = vocab_tokens();
  let merges = vocab_merges();
  let types = vocab_types();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let a4 = gguf_builder_add_kv_arr_int(&mut b, "tokenizer.ggml.token_type", 5, &types);
  let a5 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.bos_token_id", 4, 18);
  let a6 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.eos_token_id", 4, 19);

  var d_emb = Vec[Int].new();
  d_emb.push(20); d_emb.push(4);
  var d_n = Vec[Int].new();
  d_n.push(4);
  var d_m = Vec[Int].new();
  d_m.push(4); d_m.push(4);
  var d_g = Vec[Int].new();
  d_g.push(8); d_g.push(4);
  var d_d = Vec[Int].new();
  d_d.push(4); d_d.push(8);

  let t1 = gguf_builder_add_tensor(&mut b, "token_embd.weight", &d_emb, 0, 0);
  let t2 = gguf_builder_add_tensor(&mut b, "attn_norm.weight", &d_n, 0, 320);
  let t3 = gguf_builder_add_tensor(&mut b, "wq.weight", &d_m, 0, 336);
  let t4 = gguf_builder_add_tensor(&mut b, "wk.weight", &d_m, 0, 400);
  let t5 = gguf_builder_add_tensor(&mut b, "wv.weight", &d_m, 0, 464);
  let t6 = gguf_builder_add_tensor(&mut b, "wo.weight", &d_m, 0, 528);
  let t7 = gguf_builder_add_tensor(&mut b, "ffn_norm.weight", &d_n, 0, 592);
  let t8 = gguf_builder_add_tensor(&mut b, "ffn_gate.weight", &d_g, 0, 608);
  let t9 = gguf_builder_add_tensor(&mut b, "ffn_up.weight", &d_g, 0, 736);
  let t10 = gguf_builder_add_tensor(&mut b, "ffn_down.weight", &d_d, 0, 864);
  let t11 = gguf_builder_add_tensor(&mut b, "output.weight", &d_emb, 0, 992);
  let fr = gguf_builder_finish(&b);
  var buf = fr.value;

  // 1. token_embd [20,4] f32: rows 0 and 1 = [4,4,0,0], all other rows zero.
  // Row 0 is given a non-degenerate embedding so the M3 generation loop can
  // forward the greedy-selected token 0 (rows 2..19 stay zero).
  var r = 0;
  while r < 20 {
    var c = 0;
    while c < 4 {
      var ev = 0;
      if r == 0 {
        if c == 0 {
          ev = e00;
        } else if c == 1 {
          ev = e01;
        }
      } else if r == 1 {
        if c == 0 {
          ev = e10;
        } else if c == 1 {
          ev = e11;
        }
      }
      let z = push_f32(&mut buf, ev);
      c = c + 1;
    }
    r = r + 1;
  }
  // 2. attn_norm [4] f32 = ones.
  var i2 = 0;
  while i2 < 4 {
    let z3 = push_f32(&mut buf, 1);
    i2 = i2 + 1;
  }
  // 3-5. wq, wk, wv [4,4] f32: every row [1,0,0,0].
  var mi = 0;
  while mi < 3 {
    var rr = 0;
    while rr < 4 {
      let z4 = push_f32(&mut buf, 1);
      let z5 = push_f32(&mut buf, 0);
      let z6 = push_f32(&mut buf, 0);
      let z7 = push_f32(&mut buf, 0);
      rr = rr + 1;
    }
    mi = mi + 1;
  }
  // 6. wo [4,4] f32: every row [-1,0,0,0].
  var rw = 0;
  while rw < 4 {
    let z8 = push_f32(&mut buf, -1);
    let z9 = push_f32(&mut buf, 0);
    let z10 = push_f32(&mut buf, 0);
    let z11 = push_f32(&mut buf, 0);
    rw = rw + 1;
  }
  // 7. ffn_norm [4] f32 = ones.
  var i3 = 0;
  while i3 < 4 {
    let z12 = push_f32(&mut buf, 1);
    i3 = i3 + 1;
  }
  // 8. ffn_gate [8,4] Q8_0: rows [w1_first,1,0,0] x8.
  var qg = Vec[Int].new();
  var rg = 0;
  while rg < 8 {
    qg.push(w1_first); qg.push(1); qg.push(0); qg.push(0);
    rg = rg + 1;
  }
  let g8 = push_q8_padded(&mut buf, &qg);
  // 9. ffn_up [8,4] f32-slice Q8_0: rows [0,0,1,1] x8.
  var qu = Vec[Int].new();
  var ru = 0;
  while ru < 8 {
    qu.push(0); qu.push(0); qu.push(1); qu.push(1);
    ru = ru + 1;
  }
  let g9 = push_q8_padded(&mut buf, &qu);
  // 10. ffn_down [4,8] f32-slice Q8_0: rows [1,0,0,0,0,0,0,0] x4.
  var qd = Vec[Int].new();
  var rd = 0;
  while rd < 4 {
    qd.push(1); qd.push(0); qd.push(0); qd.push(0);
    qd.push(0); qd.push(0); qd.push(0); qd.push(0);
    rd = rd + 1;
  }
  let g10 = push_q8_padded(&mut buf, &qd);
  // 11. output [20,4] f32: row i = [i,0,0,0].
  var ro = 0;
  while ro < 20 {
    let z13 = push_f32(&mut buf, ro);
    let z14 = push_f32(&mut buf, 0);
    let z15 = push_f32(&mut buf, 0);
    let z16 = push_f32(&mut buf, 0);
    ro = ro + 1;
  }
  return buf;
}

// M2/M3a fixture (rows 0 and 1 both [4,4,0,0]).
fn model_container(w1_first: Int) -> Vec[UInt8] {
  return model_container_emb(4, 4, 4, 4, w1_first);
}

// Multi-position fixture: row 0 = [4,4,0,0] (xn0 = 2), row 1 = [3,0,0,0]
// (xn0 = 3), so the two forwardable tokens produce different q/k/v.
fn mp_container() -> Vec[UInt8] {
  return model_container_emb(4, 4, 3, 0, 4);
}

// Load an f32 tensor as plain Ints (each value must be an exact integer).
fn load_f32(g: &Gguf, buf: &Vec[UInt8], name: Str) -> Vec[Int] {
  let fir = gguf_find_tensor(g, name);
  let idx: Int = fir.value;
  let ndr = gguf_tensor_ndims(g, idx);
  let nd: Int = ndr.value;
  var cnt = 1;
  var d = 0;
  while d < nd {
    let dr = gguf_tensor_dim(g, idx, d);
    let dv: Int = dr.value;
    cnt = cnt * dv;
    d = d + 1;
  }
  let tdr = llm_tensor_data(g, buf, idx);
  let pay: Vec[UInt8] = tdr.value;
  var out = Vec[Int].new();
  var i = 0;
  while i < cnt {
    let vr = llm_f32_at(&pay, i * 4);
    let vv: Int = vr.value;
    out.push(vv);
    i = i + 1;
  }
  return out;
}

// Load a Q8_0 tensor as plain Ints (scale must reduce to exact integers).
fn load_q8(g: &Gguf, buf: &Vec[UInt8], name: Str) -> Vec[Int] {
  let fir = gguf_find_tensor(g, name);
  let idx: Int = fir.value;
  let tdr = llm_tensor_data(g, buf, idx);
  let pay: Vec[UInt8] = tdr.value;
  var out = Vec[Int].new();
  var blk = Vec[UInt8].new();
  var k = 0;
  while k < 34 && k < pay.len() {
    let b: UInt8 = pay[k];
    blk.push(b);
    k = k + 1;
  }
  let sr = llm_q8_0_ints(&blk, &mut out);
  return out;
}

// Element-wise add of two equal-length integer vectors.
fn vec_add(a: &Vec[Int], b: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    out.push(x + y);
    i = i + 1;
  }
  return out;
}

// model_open: parse + vocab + extent validation succeeds on the fixture;
// error propagation for a bad header, and a tensor container without vocab.
fn t49() -> Int {
  let buf = model_container(4);
  var empty = Vec[UInt8].new();
  let mr = llm_model_open(&buf, &empty);
  if !mr.is_ok {
    let got: Str = mr.error;
    return report(false, "model_open ok (Err: " + got + ")");
  }
  let model: LlmModel = mr.value;
  let g: Gguf = model.g;
  let v: LlmVocab = model.vocab;
  let n = model.n_tensors;
  var sum = 0;
  sum = sum + report(n == 11, "model_open: n_tensors = " + n);
  sum = sum + report(llm_vocab_size(&v) == 20, "model_open: vocab 20");
  // parse failure: empty buffer
  var er = Vec[UInt8].new();
  let bad = llm_model_open(&er, &empty);
  if bad.is_ok {
    sum = sum + report(false, "model_open bad header rejected (expected Err)");
  } else {
    let be: Str = bad.error;
    sum = sum + report(str_eq(be, "llm: model header parse failed"), "model_open bad header rejected");
  }
  // vocab failure: tensor container without tokenizer metadata
  let tv = tensor_fixture(0, 20, 2, 0);
  let noVocab = llm_model_open(&tv, &empty);
  if noVocab.is_ok {
    sum = sum + report(false, "model_open vocab failure propagated (expected Err)");
  } else {
    let ne: Str = noVocab.error;
    sum = sum + report(str_eq(ne, "llm: tokenizer model missing"), "model_open vocab failure propagated");
  }
  return sum;
}

// Full single-token forward (emb=4, heads=1, 1 layer): returns the 20 logits,
// or a single sentinel -999 on any assembly error. Shared by t50 and t51.
fn forward_logits(cbuf: &Vec[UInt8]) -> Vec[Int] {
  var empty = Vec[UInt8].new();
  let mr = llm_model_open(cbuf, &empty);
  if !mr.is_ok {
    var e = Vec[Int].new();
    e.push(-999);
    return e;
  }
  let model: LlmModel = mr.value;
  let g: Gguf = model.g;

  let embed = load_f32(&g, cbuf, "token_embd.weight");
  let gamma1 = load_f32(&g, cbuf, "attn_norm.weight");
  let wq = load_f32(&g, cbuf, "wq.weight");
  let wk = load_f32(&g, cbuf, "wk.weight");
  let wv = load_f32(&g, cbuf, "wv.weight");
  let wo = load_f32(&g, cbuf, "wo.weight");
  let gamma2 = load_f32(&g, cbuf, "ffn_norm.weight");
  let w1 = load_q8(&g, cbuf, "ffn_gate.weight");
  let w3 = load_q8(&g, cbuf, "ffn_up.weight");
  let w2 = load_q8(&g, cbuf, "ffn_down.weight");
  let wout = load_f32(&g, cbuf, "output.weight");

  var x = Vec[Int].new();
  var c = 0;
  while c < 4 {
    let v: Int = embed[1 * 4 + c];
    x.push(v);
    c = c + 1;
  }
  let xnr = llm_rmsnorm_i32(&x, &gamma1, 0, 0);
  let xn: Vec[Int] = xnr.value;
  let qr = llm_matmul_i32(&wq, 4, 4, &xn, 1);
  let q0: Vec[Int] = qr.value;
  let kr = llm_matmul_i32(&wk, 4, 4, &xn, 1);
  let k0: Vec[Int] = kr.value;
  let vr = llm_matmul_i32(&wv, 4, 4, &xn, 1);
  let v0: Vec[Int] = vr.value;
  let s = 12;
  var cq = Vec[Int].new();
  cq.push(1 << s); cq.push(1 << s);
  var sq = Vec[Int].new();
  sq.push(0); sq.push(0);
  let qrr = llm_rope_i32(&q0, 4, &cq, &sq, s);
  let q: Vec[Int] = qrr.value;
  let krr = llm_rope_i32(&k0, 4, &cq, &sq, s);
  let k: Vec[Int] = krr.value;
  let dr = llm_dot_i32(&q, &k);
  let dot: Int = dr.value;
  let score = dot / 2;
  var sc = Vec[Int].new();
  sc.push(score);
  let smr = llm_softmax_i32(&sc, 10);
  // single-position attention: softmax weight 1024/1024 = 1 -> attn = v0
  let wovr = llm_matmul_i32(&wo, 4, 4, &v0, 1);
  let wov: Vec[Int] = wovr.value;
  let h = vec_add(&x, &wov);
  let hnr = llm_rmsnorm_i32(&h, &gamma2, 0, 0);
  let hn: Vec[Int] = hnr.value;
  let gr = llm_matmul_i32(&w1, 8, 4, &hn, 1);
  let gate: Vec[Int] = gr.value;
  let ur = llm_matmul_i32(&w3, 8, 4, &hn, 1);
  let up: Vec[Int] = ur.value;
  let ar = llm_swiglu_i32(&gate, &up, 0);
  let a: Vec[Int] = ar.value;
  let fr = llm_matmul_i32(&w2, 4, 8, &a, 1);
  let ffn: Vec[Int] = fr.value;
  let h2 = vec_add(&h, &ffn);
  let lr = llm_matmul_i32(&wout, 20, 4, &h2, 1);
  let logits: Vec[Int] = lr.value;
  return logits;
}

// Golden logits: the full single-token forward asserted EXACTLY.
// Provenance: token 1 embedding row = [4,4,0,0]; RMSNorm rms=2 -> xn=[2,2,0,0];
// Wq/Wk/Wv pick column 1 -> q=k=v=[2,2,2,2]; pos-0 RoPE is identity; the single
// attention position has softmax weight 1.0 so attn=v; Wo=[-1,0,0,0] rows give
// Wo@v=[-2,-2,-2,-2] and residual h=[2,2,-2,-2]; RMSNorm rms=2 -> hn=[1,1,-1,-1];
// W1 rows [4,1,0,0] -> gate=[5,...] (saturated SiLU = 5); W3 rows [0,0,1,1] ->
// up=[-2,...]; SwiGLU a=[-10,...]; W2 picks a[0] -> ffn=[-10,...]; h2=[-8,-8,-12,-12];
// Wout[i]=[i,0,0,0] -> logits[i] = i * (-8) = -8*i.
fn t50() -> Int {
  let buf = model_container(4);
  let logits = forward_logits(&buf);
  if logits.len() != 20 {
    return report(false, "golden logits: forward produced 20 logits");
  }
  var bad = 0;
  var i = 0;
  while i < 20 {
    let got: Int = logits[i];
    if got != (0 - 8) * i {
      bad = bad + 1;
    }
    i = i + 1;
  }
  if bad != 0 {
    return report(false, "golden logits exact (-8*i for i in 0..19)");
  }
  return report(true, "golden logits exact (-8*i for i in 0..19)");
}

// Sensitivity: one ffn_gate weight byte (4 -> 3) changes the logits. The
// perturbed forward gives gate=[4,...] -> SiLU 4 -> a=[-8,...] -> ffn=[-8,...]
// -> h2=[-6,-6,-10,-10] -> logits[i] = -6*i.
fn t51() -> Int {
  let base = model_container(4);
  let pert = model_container(3);
  var sum = 0;
  // the only payload difference is the gate block: locate it via the loaded
  // weights (header bytes may differ in builder padding, so compare weights).
  var empty = Vec[UInt8].new();
  let mr = llm_model_open(&base, &empty);
  if !mr.is_ok {
    return report(false, "sensitivity: base model_open ok");
  }
  let model: LlmModel = mr.value;
  let g: Gguf = model.g;
  let w1b = load_q8(&g, &base, "ffn_gate.weight");
  let pr = llm_model_open(&pert, &empty);
  if !pr.is_ok {
    return report(false, "sensitivity: pert model_open ok");
  }
  let pmodel: LlmModel = pr.value;
  let pg: Gguf = pmodel.g;
  let w1p = load_q8(&pg, &pert, "ffn_gate.weight");
  let b0: Int = w1b[0];
  let p0: Int = w1p[0];
  sum = sum + report(b0 == 4 && p0 == 3, "sensitivity: gate weight 4 -> 3 loaded");
  // gate value 0 for the perturbed model = 3*hn[0] + 1*hn[1] = 4; SiLU exact
  sum = sum + report(llm_silu_q(4, 0) == 4, "sensitivity: silu(4) = 4 exact");

  let lb = forward_logits(&base);
  let lp = forward_logits(&pert);
  if lb.len() != 20 || lp.len() != 20 {
    return sum + report(false, "sensitivity: forward produced 20 logits");
  }
  var changed = 0;
  var i = 0;
  while i < 20 {
    let a: Int = lb[i];
    let b: Int = lp[i];
    if a != b {
      changed = changed + 1;
    }
    i = i + 1;
  }
  sum = sum + report(changed == 19, "sensitivity: one weight byte changes 19 of 20 logits");
  var bad = 0;
  var k = 0;
  while k < 20 {
    let got: Int = lp[k];
    if got != (0 - 6) * k {
      bad = bad + 1;
    }
    k = k + 1;
  }
  sum = sum + report(bad == 0, "sensitivity: perturbed logits exact (-6*k)");
  return sum;
}

// xiom.tensor "where sensible" boundary: shape construction + canonical dump.
fn t52() -> Int {
  var vals = Vec[Int].new();
  vals.push(1); vals.push(2); vals.push(3); vals.push(4);
  let d = llm_shape_dump(2, 2, &vals);
  let n = string.str_len(d);
  return report(n > 0, "tensor shape dump non-empty");
}

// --------------------------------------------------
//  M3a: PRNG, sampling, generation loop
// --------------------------------------------------

// Deterministic 32-bit LCG: seed normalization, exact hand-computed steps and
// the uniform-below reduction.
fn t53() -> Int {
  var sum = 0;
  sum = sum + report(llm_rng_seed(42) == 42, "rng seed(42) = 42");
  sum = sum + report(llm_rng_seed(-1) == 4294967295, "rng seed(-1) normalized to 2^32-1");
  // next(42) = 1664525*42 + 1013904223 = 1083814273
  sum = sum + report(llm_rng_next(42) == 1083814273, "rng next(42) = 1083814273");
  // next(1083814273) = 378494188 (hand-computed mod 2^32)
  sum = sum + report(llm_rng_next(1083814273) == 378494188, "rng next(1083814273) = 378494188");
  // 1083814273 mod 1024 = 385, mod 10 = 3
  sum = sum + report(llm_rng_below(1083814273, 1024) == 385, "rng below(1083814273,1024) = 385");
  sum = sum + report(llm_rng_below(1083814273, 10) == 3, "rng below(1083814273,10) = 3");
  sum = sum + report(llm_rng_below(12345, 0) == 0, "rng below(_,0) = 0");
  return sum;
}

// Greedy argmax with lowest-index tie-break and the empty-input reject.
fn t54() -> Int {
  var sum = 0;
  var a = want4(3, 5, 5, 2);
  let r = llm_greedy_next(&a);
  sum = sum + report(r.value == 1, "greedy [3,5,5,2] -> 1 (lowest tie)");
  var b = want1(7);
  let r2 = llm_greedy_next(&b);
  sum = sum + report(r2.value == 0, "greedy [7] -> 0");
  var c = want3(-5, -3, -9);
  let r3 = llm_greedy_next(&c);
  sum = sum + report(r3.value == 1, "greedy [-5,-3,-9] -> 1");
  var d = want3(2, 2, 2);
  let r4 = llm_greedy_next(&d);
  sum = sum + report(r4.value == 0, "greedy ties -> first index");
  var e = Vec[Int].new();
  sum = sum + expect_int_err(llm_greedy_next(&e), "llm: sampler empty logits", "greedy empty rejected");
  return sum;
}

// Temperature scaling: identity, flatten (T=2), sharpen (T=1/2), rounding and
// the non-positive reject.
fn t55() -> Int {
  var sum = 0;
  let base = want3(100, -100, 0);
  let idr = llm_apply_temperature(&base, 1, 1);
  sum = sum + report(ids_eq(&idr.value, &base), "temperature 1/1 identity");
  let fl = llm_apply_temperature(&base, 2, 1);
  let wf = want3(50, -50, 0);
  sum = sum + report(ids_eq(&fl.value, &wf), "temperature 2/1 halves logits");
  let sh = llm_apply_temperature(&base, 1, 2);
  let ws = want3(200, -200, 0);
  sum = sum + report(ids_eq(&sh.value, &ws), "temperature 1/2 doubles logits");
  let rd = llm_apply_temperature(&base, 3, 2);
  let wr = want3(67, -67, 0);
  sum = sum + report(ids_eq(&rd.value, &wr), "temperature 3/2 rounds half away");
  sum = sum + expect_ids_err(llm_apply_temperature(&base, 0, 1), "llm: sampler temperature not positive", "temperature t_num 0 rejected");
  sum = sum + expect_ids_err(llm_apply_temperature(&base, 1, 0), "llm: sampler temperature not positive", "temperature t_den 0 rejected");
  return sum;
}

// Top-k membership mask: exact selection and disabled/oversize arms.
fn t56() -> Int {
  var sum = 0;
  let logits = want4(10, 30, 20, 30);
  var k2 = Vec[Int].new();
  let r = llm_top_k_keep(&logits, 2, &mut k2);
  let w2 = want4(0, 1, 0, 1);
  sum = sum + report(r.value == 2 && ids_eq(&k2, &w2), "top_k k=2 keeps {1,3}");
  var k1 = Vec[Int].new();
  let r1 = llm_top_k_keep(&logits, 1, &mut k1);
  let w1 = want4(0, 1, 0, 0);
  sum = sum + report(ids_eq(&k1, &w1), "top_k k=1 keeps lowest-index max");
  var k4 = Vec[Int].new();
  let r4 = llm_top_k_keep(&logits, 4, &mut k4);
  let w4 = want4(1, 1, 1, 1);
  sum = sum + report(ids_eq(&k4, &w4), "top_k k=n keeps all");
  var k0 = Vec[Int].new();
  let r0 = llm_top_k_keep(&logits, 0, &mut k0);
  sum = sum + report(ids_eq(&k0, &w4), "top_k k=0 disabled (keeps all)");
  var k9 = Vec[Int].new();
  let r9 = llm_top_k_keep(&logits, 9, &mut k9);
  sum = sum + report(ids_eq(&k9, &w4), "top_k k>n keeps all");
  var e = Vec[Int].new();
  var ke = Vec[Int].new();
  sum = sum + expect_int_err(llm_top_k_keep(&e, 2, &mut ke), "llm: sampler empty logits", "top_k empty rejected");
  return sum;
}

// Top-p nucleus membership: exact prefix selection, p=0 top-1, p>total all,
// and the empty-input reject.
fn t57() -> Int {
  var sum = 0;
  let probs = want4(512, 256, 256, 0);
  var p100 = Vec[Int].new();
  let r1 = llm_top_p_keep(&probs, 100, &mut p100);
  let w0 = want4(1, 0, 0, 0);
  sum = sum + report(ids_eq(&p100, &w0), "top_p p=100 keeps top-1");
  var p768 = Vec[Int].new();
  let r2 = llm_top_p_keep(&probs, 768, &mut p768);
  let w768 = want4(1, 1, 0, 0);
  sum = sum + report(ids_eq(&p768, &w768), "top_p p=768 keeps {0,1}");
  var p1024 = Vec[Int].new();
  let r3 = llm_top_p_keep(&probs, 1024, &mut p1024);
  let w1024 = want4(1, 1, 1, 0);
  sum = sum + report(ids_eq(&p1024, &w1024), "top_p p=1024 keeps nonzero mass");
  var p0 = Vec[Int].new();
  let r4 = llm_top_p_keep(&probs, 0, &mut p0);
  sum = sum + report(ids_eq(&p0, &w0), "top_p p=0 keeps top-1");
  var pbig = Vec[Int].new();
  let r5 = llm_top_p_keep(&probs, 2000, &mut pbig);
  let wbig = want4(1, 1, 1, 1);
  sum = sum + report(ids_eq(&pbig, &wbig), "top_p p>total keeps all");
  var e = Vec[Int].new();
  var pe = Vec[Int].new();
  sum = sum + expect_int_err(llm_top_p_keep(&e, 1, &mut pe), "llm: sampler empty logits", "top_p empty rejected");
  return sum;
}

// Category draw from a probability vector: exact bucket boundaries, a
// restricted mask, the zero-mass fallback and the size-mismatch reject.
fn t58() -> Int {
  var sum = 0;
  let probs = want4(512, 256, 256, 0);
  let keepall = want4(1, 1, 1, 1);
  let d0 = llm_sample_choice(&probs, &keepall, 100);
  sum = sum + report(d0.value == 0, "choice state 100 -> 0");
  let d1 = llm_sample_choice(&probs, &keepall, 600);
  sum = sum + report(d1.value == 1, "choice state 600 -> 1");
  let d2 = llm_sample_choice(&probs, &keepall, 900);
  sum = sum + report(d2.value == 2, "choice state 900 -> 2");
  let keep02 = want4(1, 0, 1, 0);
  let d3 = llm_sample_choice(&probs, &keep02, 600);
  sum = sum + report(d3.value == 2, "choice masked {0,2} state 600 -> 2");
  let z = want2(0, 0);
  let zk = want2(1, 1);
  let d4 = llm_sample_choice(&z, &zk, 7);
  sum = sum + report(d4.value == 0, "choice zero mass falls back to argmax");
  let bad = want3(1, 1, 1);
  sum = sum + expect_int_err(llm_sample_choice(&probs, &bad, 1), "llm: sampler keep size mismatch", "choice keep mismatch rejected");
  return sum;
}

// Composed sampler: greedy arm plus a seeded arm whose uniform draw is
// verified against hand-computed bucket boundaries; determinism and the
// temperature reject propagate.
fn t59() -> Int {
  var sum = 0;
  let g = llm_sampler_greedy();
  let lg = want3(1, 9, 3);
  let gr = llm_sample_next(&lg, &g, 12345);
  sum = sum + report(gr.value == 1, "sample_next greedy -> 1");
  let uni = want4(0, 0, 0, 0);
  let s600 = llm_sampler_seeded(600, 1, 1, 0, 1024, 10);
  let a = llm_sample_next(&uni, &s600, 600);
  let b = llm_sample_next(&uni, &s600, 600);
  sum = sum + report(a.value == 2 && b.value == 2, "sample_next seeded state 600 -> 2, deterministic");
  let s100 = llm_sampler_seeded(100, 1, 1, 0, 1024, 10);
  let c = llm_sample_next(&uni, &s100, 100);
  sum = sum + report(c.value == 0, "sample_next seeded state 100 -> 0");
  let sbad = llm_sampler_seeded(1, 0, 1, 0, 0, 10);
  sum = sum + expect_int_err(llm_sample_next(&uni, &sbad, 1), "llm: sampler temperature not positive", "sample_next bad temperature rejected");
  return sum;
}

// Open the fixture model; shared by the generation tests (assumes ok).
fn open_model(cbuf: &Vec[UInt8]) -> LlmModel {
  var empty = Vec[UInt8].new();
  let mr = llm_model_open(cbuf, &empty);
  return mr.value;
}

// Greedy generation over the tiny fixture: constant deterministic sequence
// (the forward of any supported token yields argmax 0), then decode roundtrip.
fn t60() -> Int {
  var sum = 0;
  let cbuf = model_container(4);
  let model = open_model(&cbuf);
  let prompt = want1(1);
  let s = llm_sampler_greedy();
  var out = Vec[Int].new();
  let gr = llm_generate(&model, &cbuf, &prompt, 3, -1, &s, &mut out);
  let w = want3(0, 0, 0);
  sum = sum + report(gr.value == 3 && ids_eq(&out, &w), "generate greedy 3 steps -> [0,0,0]");
  let v: LlmVocab = model.vocab;
  let dr = llm_bpe_decode(&v, &out);
  sum = sum + report(str_eq(dr.value, "hhh"), "generated [0,0,0] decodes to \"hhh\"");
  return sum;
}

// Stop-token handling: generation halts on the sampled stop id (appended).
fn t61() -> Int {
  var sum = 0;
  let cbuf = model_container(4);
  let model = open_model(&cbuf);
  let prompt = want1(1);
  let s = llm_sampler_greedy();
  var out = Vec[Int].new();
  let gr = llm_generate(&model, &cbuf, &prompt, 5, 0, &s, &mut out);
  let w = want1(0);
  sum = sum + report(gr.value == 1 && ids_eq(&out, &w), "generate stops at token 0 (appended)");
  return sum;
}

// Seeded sampling through the loop is reproducible and yields an exact golden
// id sequence. top_k=2 restricts the draw to tokens {0,1}, both of which the
// fixture forwards (rows 2..19 are zero embeddings). With seed 7 the kept mass
// is 110 (probs[0]=probs[1]=55), so r = state mod 110 selects index 0 while
// r < 55; the LCG states 7, 1025555898, 3923423697, 2630631676 give r =
// 7, 48, 17, 46 -> [0,0,0,0], and the next state 3981355051 gives r = 91 -> 1.
fn t62() -> Int {
  var sum = 0;
  let cbuf = model_container(4);
  let model = open_model(&cbuf);
  let prompt = want1(1);
  let s = llm_sampler_seeded(7, 1, 1, 2, 1024, 10);
  var out1 = Vec[Int].new();
  var out2 = Vec[Int].new();
  let r1 = llm_generate(&model, &cbuf, &prompt, 5, -1, &s, &mut out1);
  let r2 = llm_generate(&model, &cbuf, &prompt, 5, -1, &s, &mut out2);
  let w = want5(0, 0, 0, 0, 1);
  sum = sum + report(r1.value == 5 && r2.value == 5, "generate seeded runs 5 steps");
  sum = sum + report(ids_eq(&out1, &w), "generate seeded golden ids [0,0,0,0,1]");
  sum = sum + report(ids_eq(&out1, &out2), "generate seeded deterministic (same seed)");
  return sum;
}

// Generation edge cases and the src forward-pass entry point.
fn t63() -> Int {
  var sum = 0;
  let cbuf = model_container(4);
  let model = open_model(&cbuf);
  let s = llm_sampler_greedy();
  var out = Vec[Int].new();
  var prompt = Vec[Int].new();
  sum = sum + expect_int_err(llm_generate(&model, &cbuf, &prompt, 3, -1, &s, &mut out), "llm: generate empty prompt", "generate empty prompt rejected");
  let p2 = want1(1);
  var out2 = Vec[Int].new();
  let z = llm_generate(&model, &cbuf, &p2, 0, -1, &s, &mut out2);
  sum = sum + report(z.value == 0 && out2.len() == 0, "generate max_new=0 -> no ids");
  sum = sum + expect_ids_err(llm_forward_token(&model, &cbuf, 99), "llm: token id out of range", "forward token id out of range rejected");
  let lr = llm_forward_token(&model, &cbuf, 1);
  let logits: Vec[Int] = lr.value;
  var bad = 0;
  var i = 0;
  while i < 20 {
    let got: Int = logits[i];
    if got != (0 - 8) * i {
      bad = bad + 1;
    }
    i = i + 1;
  }
  sum = sum + report(logits.len() == 20 && bad == 0, "src forward token 1 logits exact (-8*i)");
  return sum;
}

// M3b: append-only KV cache -- allocation, append, length and read-back.
fn t64() -> Int {
  var sum = 0;
  var c = llm_kv_cache_new(1, 2, 3);
  sum = sum + report(llm_kv_cache_len(&c) == 0 && llm_kv_cache_cap(&c) == 3, "kv new: len 0 cap 3");
  var cn = llm_kv_cache_new(1, 2, -1);
  sum = sum + report(llm_kv_cache_cap(&cn) == 0, "kv new: negative cap clamped to 0");
  var k1 = want2(1, 2);
  var v1 = want2(3, 4);
  let a1 = llm_kv_cache_append(&mut c, &k1, &v1);
  sum = sum + report(a1.value == 1 && llm_kv_cache_len(&c) == 1, "kv append step -> len 1");
  var k2 = want2(5, 6);
  var v2 = want2(7, 8);
  let a2 = llm_kv_cache_append(&mut c, &k2, &v2);
  sum = sum + report(a2.value == 2 && llm_kv_cache_len(&c) == 2, "kv append step -> len 2");
  let kr0 = llm_kv_cache_key(&c, 0, 0);
  let kk0: Vec[Int] = kr0.value;
  let w20 = want2(1, 2);
  sum = sum + report(ids_eq(&kk0, &w20), "kv key pos0 [1,2]");
  let kr1 = llm_kv_cache_key(&c, 0, 1);
  let kk1: Vec[Int] = kr1.value;
  let w21 = want2(5, 6);
  sum = sum + report(ids_eq(&kk1, &w21), "kv key pos1 [5,6]");
  let vr1 = llm_kv_cache_val(&c, 0, 1);
  let vv1: Vec[Int] = vr1.value;
  let wv1 = want2(7, 8);
  sum = sum + report(ids_eq(&vv1, &wv1), "kv val pos1 [7,8]");
  sum = sum + expect_ids_err(llm_kv_cache_key(&c, 0, 2), "llm: kv cache index out of range", "kv key pos2 rejected");
  sum = sum + expect_ids_err(llm_kv_cache_val(&c, 1, 0), "llm: kv cache index out of range", "kv val layer1 rejected");
  var kbad = want3(1, 2, 3);
  sum = sum + expect_int_err(llm_kv_cache_append(&mut c, &kbad, &v1), "llm: kv cache size mismatch", "kv append size mismatch rejected");
  let a3 = llm_kv_cache_append(&mut c, &k1, &v1);
  sum = sum + report(a3.value == 3, "kv append step -> len 3 (cap)");
  sum = sum + expect_int_err(llm_kv_cache_append(&mut c, &k1, &v1), "llm: kv cache full", "kv append beyond cap rejected");
  return sum;
}

// M3b: multi-position attention goldens (exact weights and value mixtures).
fn t65() -> Int {
  var sum = 0;
  let q = want2(2, 2);
  // uniform weights (two equal keys) mix two distinct values.
  let keys = want4(2, 2, 2, 2);
  let vals = want4(4, 0, 0, 8);
  let r = llm_attention_i32(&q, &keys, &vals, 2, 10);
  let w = want2(2, 4);
  sum = sum + report(ids_eq(&r.value, &w), "attention uniform weights -> [2,4]");
  // a single position is exactly the value (softmax [1024]).
  let k1 = want2(2, 2);
  let v1 = want2(5, 7);
  let r1 = llm_attention_i32(&q, &k1, &v1, 1, 10);
  let w1 = want2(5, 7);
  sum = sum + report(ids_eq(&r1.value, &w1), "attention single position -> value");
  // distinct scores: keys [2,2],[0,0] -> weights [513,511]; isolate each.
  let keys2 = want4(2, 2, 0, 0);
  let vals_a = want4(1024, 0, 0, 0);
  let ra = llm_attention_i32(&q, &keys2, &vals_a, 2, 10);
  let wa = want2(513, 0);
  sum = sum + report(ids_eq(&ra.value, &wa), "attention weights 513/511 -> high key yields 513");
  let vals_b = want4(0, 0, 1024, 0);
  let rb = llm_attention_i32(&q, &keys2, &vals_b, 2, 10);
  let wb = want2(511, 0);
  sum = sum + report(ids_eq(&rb.value, &wb), "attention weights 513/511 -> low key yields 511");
  let badv = want3(1, 2, 3);
  sum = sum + expect_ids_err(llm_attention_i32(&q, &keys2, &badv, 2, 10), "llm: attention size mismatch", "attention size mismatch rejected");
  return sum;
}

// M3b: cached multi-position forward. (A) a one-position cache reproduces the
// single-position forward exactly; (B) a hand-computed two-position anchor
// (-19*i) on the distinct-embedding fixture; (C) the single-position mp
// forward is all zeros (token 1 saturates SiLU).
fn t66() -> Int {
  var sum = 0;
  let cbuf = model_container(4);
  let model = open_model(&cbuf);
  var cos = Vec[Int].new();
  var sin = Vec[Int].new();
  var t = 0;
  while t < 4 * 2 {
    cos.push(1 << 12);
    sin.push(0);
    t = t + 1;
  }
  var c = llm_kv_cache_new(1, 4, 4);
  let cr = llm_forward_cache(&model, &cbuf, 1, &cos, &sin, 12, &mut c);
  let clogits: Vec[Int] = cr.value;
  let src = llm_forward_token(&model, &cbuf, 1);
  let slogits: Vec[Int] = src.value;
  sum = sum + report(ids_eq(&clogits, &slogits), "cached forward 1 pos == single forward");
  sum = sum + report(llm_kv_cache_len(&c) == 1, "cached forward appended 1 position");

  // (B) mp fixture: token 1 at pos0, token 0 at pos1 (pos-1 stretch table).
  let mbuf = mp_container();
  let mmodel = open_model(&mbuf);
  var cos2 = Vec[Int].new();
  var sin2 = Vec[Int].new();
  cos2.push(4096); sin2.push(0);
  cos2.push(4096); sin2.push(0);
  cos2.push(4096); sin2.push(2048);
  cos2.push(4096); sin2.push(2048);
  var c2 = llm_kv_cache_new(1, 4, 4);
  let f1 = llm_forward_cache(&mmodel, &mbuf, 1, &cos2, &sin2, 12, &mut c2);
  let f1l: Vec[Int] = f1.value;
  sum = sum + report(llm_kv_cache_len(&c2) == 1, "mp cached forward pos0 appended");
  let f2 = llm_forward_cache(&mmodel, &mbuf, 0, &cos2, &sin2, 12, &mut c2);
  let f2l: Vec[Int] = f2.value;
  sum = sum + report(llm_kv_cache_len(&c2) == 2, "mp cached forward pos1 appended");
  var bad2 = 0;
  var k = 0;
  while k < 20 {
    let got2: Int = f2l[k];
    if got2 != (0 - 19) * k {
      bad2 = bad2 + 1;
    }
    k = k + 1;
  }
  sum = sum + report(f2l.len() == 20 && bad2 == 0, "mp 2-position attention golden (-19*i)");

  // (C) mp single-position forward of token 1 is all zeros.
  let single = llm_forward_token(&mmodel, &mbuf, 1);
  let sl: Vec[Int] = single.value;
  var bad3 = 0;
  var m = 0;
  while m < 20 {
    let got3: Int = sl[m];
    if got3 != 0 {
      bad3 = bad3 + 1;
    }
    m = m + 1;
  }
  sum = sum + report(sl.len() == 20 && bad3 == 0, "mp single forward token 1 -> all zero");
  return sum;
}

// M3b: cached generation loop conditions on every prefilled prompt position.
fn t67() -> Int {
  var sum = 0;
  let cbuf = model_container(4);
  let model = open_model(&cbuf);
  let s = llm_sampler_greedy();
  var p1 = want1(1);
  var o1 = Vec[Int].new();
  let g1 = llm_generate_cached(&model, &cbuf, &p1, 3, -1, &s, &mut o1);
  var o2 = Vec[Int].new();
  let g2 = llm_generate(&model, &cbuf, &p1, 3, -1, &s, &mut o2);
  let w3 = want3(0, 0, 0);
  sum = sum + report(g1.value == 3 && ids_eq(&o1, &w3), "cached generate greedy 3 -> [0,0,0]");
  sum = sum + report(g2.value == 3 && ids_eq(&o1, &o2), "cached generate == single generate (1-token prompt)");
  var p2 = want2(1, 0);
  var o3 = Vec[Int].new();
  let g3 = llm_generate_cached(&model, &cbuf, &p2, 3, -1, &s, &mut o3);
  sum = sum + report(g3.value == 3 && ids_eq(&o3, &w3), "cached generate 2-token prompt -> [0,0,0]");
  var o4 = Vec[Int].new();
  let g4 = llm_generate_cached(&model, &cbuf, &p2, 3, -1, &s, &mut o4);
  sum = sum + report(ids_eq(&o3, &o4), "cached generate deterministic");
  var o5 = Vec[Int].new();
  let g5 = llm_generate_cached(&model, &cbuf, &p1, 5, 0, &s, &mut o5);
  let w1 = want1(0);
  sum = sum + report(g5.value == 1 && ids_eq(&o5, &w1), "cached generate stops at token 0 (appended)");
  var o6 = Vec[Int].new();
  var pe = Vec[Int].new();
  sum = sum + expect_int_err(llm_generate_cached(&model, &cbuf, &pe, 3, -1, &s, &mut o6), "llm: generate empty prompt", "cached generate empty prompt rejected");
  var o7 = Vec[Int].new();
  let z = llm_generate_cached(&model, &cbuf, &p1, 0, -1, &s, &mut o7);
  sum = sum + report(z.value == 0 && o7.len() == 0, "cached generate max_new=0 -> no ids");
  return sum;
}

// M3b: cached-forward error arms (capacity, width, token range, rope table).
fn t68() -> Int {
  var sum = 0;
  let cbuf = model_container(4);
  let model = open_model(&cbuf);
  var cos = Vec[Int].new();
  var sin = Vec[Int].new();
  var t = 0;
  while t < 2 {
    cos.push(4096);
    sin.push(0);
    t = t + 1;
  }
  var c0 = llm_kv_cache_new(1, 4, 0);
  sum = sum + expect_ids_err(llm_forward_cache(&model, &cbuf, 1, &cos, &sin, 12, &mut c0), "llm: kv cache full", "cached forward cap 0 rejected");
  var cw = llm_kv_cache_new(1, 3, 4);
  sum = sum + expect_ids_err(llm_forward_cache(&model, &cbuf, 1, &cos, &sin, 12, &mut cw), "llm: kv cache size mismatch", "cached forward wrong n_kv rejected");
  var c1 = llm_kv_cache_new(1, 4, 4);
  sum = sum + expect_ids_err(llm_forward_cache(&model, &cbuf, 99, &cos, &sin, 12, &mut c1), "llm: token id out of range", "cached forward token id rejected");
  var c2 = llm_kv_cache_new(1, 4, 4);
  var short = want1(4096);
  sum = sum + expect_ids_err(llm_forward_cache(&model, &cbuf, 1, &short, &short, 12, &mut c2), "llm: kv cache rope table too small", "cached forward short rope rejected");
  return sum;
}

// --------------------------------------------------
//  M3 second-half remainder: Q5_0 + Q4_K dequantization
// --------------------------------------------------

// One Q5_0 block: little-endian f16 `dbits`, four little-endian bytes of the
// fifth bits `qh`, then 16 nibble bytes (22 bytes total).
fn q5_0_block(dbits: Int, qh: Int, qsbyte: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(((dbits & 0xFF) as UInt8));
  v.push((((dbits >> 8) & 0xFF) as UInt8));
  v.push(((qh & 0xFF) as UInt8));
  v.push((((qh >> 8) & 0xFF) as UInt8));
  v.push((((qh >> 16) & 0xFF) as UInt8));
  v.push((((qh >> 24) & 0xFF) as UInt8));
  var i = 0;
  while i < 16 {
    v.push(((qsbyte & 0xFF) as UInt8));
    i = i + 1;
  }
  return v;
}

// One Q4_K super-block: f16 `dbits`, f16 `dminbits`, 12 scale/min bytes, then
// 128 nibble bytes with both nibbles set to `nibble` (144 bytes total).
fn q4_k_block(dbits: Int, dminbits: Int, scales: &Vec[Int], nibble: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(((dbits & 0xFF) as UInt8));
  v.push((((dbits >> 8) & 0xFF) as UInt8));
  v.push(((dminbits & 0xFF) as UInt8));
  v.push((((dminbits >> 8) & 0xFF) as UInt8));
  var i = 0;
  while i < scales.len() {
    let s: Int = scales[i];
    v.push(((s & 0xFF) as UInt8));
    i = i + 1;
  }
  let packed = ((nibble & 0xF) | ((nibble & 0xF) << 4)) & 0xFF;
  var k = 0;
  while k < 128 {
    v.push((packed as UInt8));
    k = k + 1;
  }
  return v;
}

fn bytes12(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, q: Int, r: Int, s: Int, t: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(q);
  v.push(r);
  v.push(s);
  v.push(t);
  return v;
}

fn all_eq(v: &Vec[Int], want: Int) -> Bool {
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    if x != want {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Q5_0 golden vectors: 5-bit quants (high bit from `qh`, nibble from qs).
fn t69() -> Int {
  var sum = 0;
  // d = 1.0, qh 0, nibbles 0 -> every quant (0 | 0) - 16 = -16.
  let b1 = q5_0_block(0x3C00, 0, 0x00);
  var o1 = Vec[Int].new();
  let r1 = llm_dequant_q5_0(&b1, &mut o1);
  if !r1.is_ok {
    let got: Str = r1.error;
    return report(false, "q5_0 all -16 decode (Err: " + got + ")");
  }
  let s1: LlmScale = r1.value;
  sum = sum + report(s1.m == 1024 && s1.e == 10 && o1.len() == 32 && all_eq(&o1, -16384), "q5_0 golden all -16 (scale 1.0)");
  // qh all high, nibbles 0 -> (0 | 16) - 16 = 0 for every quant.
  var o2 = Vec[Int].new();
  let b2 = q5_0_block(0x3C00, 0xFFFFFFFF, 0x00);
  let r2 = llm_dequant_q5_0(&b2, &mut o2);
  sum = sum + report(r2.is_ok && all_eq(&o2, 0), "q5_0 qh all-high -> all zero");
  // Fifth-bit mapping: only bit 0 set -> only value 0 gets +16 (-> 0).
  var o3 = Vec[Int].new();
  let b3 = q5_0_block(0x3C00, 0x00000001, 0x00);
  let r3 = llm_dequant_q5_0(&b3, &mut o3);
  var fifth_ok = false;
  if r3.is_ok {
    let o30: Int = o3[0];
    let o31: Int = o3[1];
    let o316: Int = o3[16];
    fifth_ok = o30 == 0 && o31 == -16384 && o316 == -16384;
  }
  sum = sum + report(fifth_ok, "q5_0 fifth bit sets value 0 only");
  // Nibble 15 with qh 0 -> quant 15 - 16 = -1 (times 1.0 * 1024).
  var o4 = Vec[Int].new();
  let b4 = q5_0_block(0x3C00, 0, 0xFF);
  let r4 = llm_dequant_q5_0(&b4, &mut o4);
  sum = sum + report(r4.is_ok && all_eq(&o4, -1024), "q5_0 nibble 15 -> -1 * 1024");
  // Error arms: malformed length, empty, mixed per-block scales.
  var short = Vec[UInt8].new();
  var z = 0;
  while z < 21 {
    short.push((0 as UInt8));
    z = z + 1;
  }
  var empty = Vec[UInt8].new();
  var ose = Vec[Int].new();
  var oe = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q5_0(&short, &mut ose), "llm: q5_0 payload length not a multiple of block size", "q5_0 bad length rejected");
  sum = sum + expect_scale_err(llm_dequant_q5_0(&empty, &mut oe), "llm: q5_0 payload is empty", "q5_0 empty rejected");
  var two = q5_0_block(0x3C00, 0, 0x00);
  let b2nd = q5_0_block(0x3800, 0, 0x00);
  let a2 = append_bytes(&mut two, &b2nd);
  var om = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q5_0(&two, &mut om), "llm: q5_0 mixed block scales are not supported", "q5_0 mixed scales rejected");
  return sum;
}

// Q4_K 6-bit sub-scale/sub-min unpacking (llama.cpp get_scale_min_k4).
fn t70() -> Int {
  var sum = 0;
  let s = bytes12(1, 2, 3, 4, 1, 2, 3, 4, 0x55, 0x66, 0x77, 0x88);
  var ok = true;
  var g = 0;
  while g < 8 {
    let r = llm_k_get_scale_min_k4(g, &s);
    if !r.is_ok {
      ok = false;
    } else {
      let v: Vec[Int] = r.value;
      let sc: Int = v[0];
      let mn: Int = v[1];
      if sc != g + 1 || mn != g + 1 {
        ok = false;
      }
    }
    g = g + 1;
  }
  sum = sum + report(ok, "q4_k 6-bit unpack j=0..7 (sc=m=j+1)");
  // High two bits of the packed word exercised for groups 4..7.
  let s2 = bytes12(0x41, 0x00, 0x00, 0x00, 0x42, 0x00, 0x00, 0x00, 0x35, 0x00, 0x00, 0x00);
  let r0 = llm_k_get_scale_min_k4(0, &s2);
  let r4 = llm_k_get_scale_min_k4(4, &s2);
  var hi_ok = false;
  if r0.is_ok && r4.is_ok {
    let v0: Vec[Int] = r0.value;
    let v4: Vec[Int] = r4.value;
    hi_ok = v0[0] == 1 && v0[1] == 2 && v4[0] == 21 && v4[1] == 19;
  }
  sum = sum + report(hi_ok, "q4_k 6-bit unpack high bits (j=4 -> 21/19)");
  // Error arms: index out of range and a short scales array.
  let s12 = bytes12(1, 2, 3, 4, 1, 2, 3, 4, 0x55, 0x66, 0x77, 0x88);
  sum = sum + expect_ids_err(llm_k_get_scale_min_k4(8, &s12), "llm: q4_k scale index out of range", "q4_k scale index 8 rejected");
  sum = sum + expect_ids_err(llm_k_get_scale_min_k4(-1, &s12), "llm: q4_k scale index out of range", "q4_k scale index -1 rejected");
  var shortv = Vec[UInt8].new();
  var z = 0;
  while z < 11 {
    shortv.push((1 as UInt8));
    z = z + 1;
  }
  sum = sum + expect_ids_err(llm_k_get_scale_min_k4(0, &shortv), "llm: q4_k scales too short", "q4_k short scales rejected");
  return sum;
}

// Q4_K golden super-block: d = dmin = 1.0, sc = mn = group+1, nibbles all 3.
// value = 1.0*(g+1)*3 - 1.0*(g+1) = 2*(g+1); out = value * 2^10.
fn t71() -> Int {
  let scales = bytes12(1, 2, 3, 4, 1, 2, 3, 4, 0x55, 0x66, 0x77, 0x88);
  var blk = q4_k_block(0x3C00, 0x3C00, &scales, 3);
  var out = Vec[Int].new();
  let r = llm_dequant_q4_k(&blk, &mut out);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, "q4_k golden decode (Err: " + got + ")");
  }
  let s: LlmScale = r.value;
  var sum = 0;
  sum = sum + report(s.m == 1 && s.e == 10 && out.len() == 256, "q4_k unit scale (1,10), 256 values");
  var bad = 0;
  var g = 0;
  while g < 8 {
    var l = 0;
    while l < 32 {
      let got: Int = out[g * 32 + l];
      if got != 2 * (g + 1) * 1024 {
        bad = bad + 1;
      }
      l = l + 1;
    }
    g = g + 1;
  }
  sum = sum + report(bad == 0, "q4_k golden values exact (8 groups)");
  let o0: Int = out[0];
  let o32: Int = out[32];
  let o224: Int = out[224];
  let o255: Int = out[255];
  sum = sum + report(o0 == 2048 && o32 == 4096 && o224 == 16384 && o255 == 16384, "q4_k spot values");
  return sum;
}

// Q4_K distinct d/dmin exponents: d = 0.5 (de=11), dmin = 0.25 (dme=12) -> the
// shared exponent is E = 12; sc = mn = 1, nibbles 3 -> value = 1.5 - 0.25 =
// 1.25, out = 1.25 * 2^12 = 5120 exactly.
fn t72() -> Int {
  let scales = bytes12(1, 1, 1, 1, 1, 1, 1, 1, 0x11, 0x11, 0x11, 0x11);
  var blk = q4_k_block(0x3800, 0x3400, &scales, 3);
  var out = Vec[Int].new();
  let r = llm_dequant_q4_k(&blk, &mut out);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, "q4_k exponent decode (Err: " + got + ")");
  }
  let s: LlmScale = r.value;
  var sum = 0;
  sum = sum + report(s.m == 1 && s.e == 12 && out.len() == 256, "q4_k common exponent E=12");
  sum = sum + report(all_eq(&out, 5120), "q4_k 1.25 exact at 2^12");
  return sum;
}

// Q4_K malformed block sizes.
fn t73() -> Int {
  var sum = 0;
  var empty = Vec[UInt8].new();
  var oe = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q4_k(&empty, &mut oe), "llm: q4_k payload is empty", "q4_k empty rejected");
  var short = Vec[UInt8].new();
  var z = 0;
  while z < 143 {
    short.push((0 as UInt8));
    z = z + 1;
  }
  var os = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q4_k(&short, &mut os), "llm: q4_k payload length not a multiple of block size", "q4_k bad length rejected");
  return sum;
}

// --------------------------------------------------
//  M3 remainder: Q4_0 + Q5_1 + Q6_K dequantization
// --------------------------------------------------

// One Q4_0 block: little-endian f16 `dbits`, a first nibble byte `first`,
// then 15 copies of `fill` (18 bytes total).
fn q4_0_block(dbits: Int, first: Int, fill: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(((dbits & 0xFF) as UInt8));
  v.push((((dbits >> 8) & 0xFF) as UInt8));
  v.push(((first & 0xFF) as UInt8));
  var i = 1;
  while i < 16 {
    v.push(((fill & 0xFF) as UInt8));
    i = i + 1;
  }
  return v;
}

// One Q5_1 block: f16 `dbits`, f16 `mbits`, four little-endian bytes of the
// fifth bits `qh`, then 16 nibble bytes (24 bytes total).
fn q5_1_block(dbits: Int, mbits: Int, qh: Int, qsbyte: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(((dbits & 0xFF) as UInt8));
  v.push((((dbits >> 8) & 0xFF) as UInt8));
  v.push(((mbits & 0xFF) as UInt8));
  v.push((((mbits >> 8) & 0xFF) as UInt8));
  v.push(((qh & 0xFF) as UInt8));
  v.push((((qh >> 8) & 0xFF) as UInt8));
  v.push((((qh >> 16) & 0xFF) as UInt8));
  v.push((((qh >> 24) & 0xFF) as UInt8));
  var i = 0;
  while i < 16 {
    v.push(((qsbyte & 0xFF) as UInt8));
    i = i + 1;
  }
  return v;
}

// One Q6_K super-block: 128 ql bytes (`ql0` at index 0, `ql32` at index 32,
// `qlfill` elsewhere), 64 qh bytes (`qh0` at 0, `qhfill` elsewhere), 16
// signed scale bytes, then f16 `dbits` (210 bytes total).
fn q6_k_block(dbits: Int, scales: &Vec[Int], qlfill: Int, qhfill: Int, ql0: Int, ql32: Int, qh0: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 128 {
    if i == 0 {
      v.push(((ql0 & 0xFF) as UInt8));
    } else {
      if i == 32 {
        v.push(((ql32 & 0xFF) as UInt8));
      } else {
        v.push(((qlfill & 0xFF) as UInt8));
      }
    }
    i = i + 1;
  }
  var j = 0;
  while j < 64 {
    if j == 0 {
      v.push(((qh0 & 0xFF) as UInt8));
    } else {
      v.push(((qhfill & 0xFF) as UInt8));
    }
    j = j + 1;
  }
  var k = 0;
  while k < 16 {
    let s: Int = scales[k];
    v.push(((s & 0xFF) as UInt8));
    k = k + 1;
  }
  v.push(((dbits & 0xFF) as UInt8));
  v.push((((dbits >> 8) & 0xFF) as UInt8));
  return v;
}

fn scales16(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(a);
  v.push(a);
  v.push(a);
  v.push(a);
  v.push(a);
  v.push(a);
  v.push(a);
  v.push(a);
  return v;
}

// Q4_0 golden vectors: 4-bit quants centered at 8 (values -8..7).
fn t91() -> Int {
  var sum = 0;
  // d = 1.0, all nibbles 0 -> (0 - 8) * 1024 = -8192.
  var b1 = q4_0_block(0x3C00, 0x00, 0x00);
  var o1 = Vec[Int].new();
  let r1 = llm_dequant_q4_0(&b1, &mut o1);
  if !r1.is_ok {
    let got: Str = r1.error;
    return report(false, "q4_0 golden decode (Err: " + got + ")");
  }
  let s1: LlmScale = r1.value;
  sum = sum + report(s1.m == 1024 && s1.e == 10 && o1.len() == 32 && all_eq(&o1, -8192), "q4_0 golden all -8 (scale 1.0)");
  // Nibble 15 -> (15 - 8) * 1024 = 7168.
  var b2 = q4_0_block(0x3C00, 0xFF, 0xFF);
  var o2 = Vec[Int].new();
  let r2 = llm_dequant_q4_0(&b2, &mut o2);
  sum = sum + report(r2.is_ok && all_eq(&o2, 7168), "q4_0 nibble 15 -> 7 * 1024");
  // Low nibbles are values 0..15, high nibbles values 16..31.
  var b3 = q4_0_block(0x3C00, 0x30, 0x00);
  var o3 = Vec[Int].new();
  let r3 = llm_dequant_q4_0(&b3, &mut o3);
  var order_ok = false;
  if r3.is_ok && o3.len() == 32 {
    let v0: Int = o3[0];
    let v1: Int = o3[1];
    let v15: Int = o3[15];
    let v16: Int = o3[16];
    let v31: Int = o3[31];
    order_ok = v0 == -8192 && v1 == -8192 && v15 == -8192 && v16 == -5120 && v31 == -8192;
  }
  sum = sum + report(order_ok, "q4_0 low/high nibble order");
  // d = 0.5 -> (m, e) = (1024, 11); quants still -8 * 1024.
  var b4 = q4_0_block(0x3800, 0x00, 0x00);
  var o4 = Vec[Int].new();
  let r4 = llm_dequant_q4_0(&b4, &mut o4);
  var exp_ok = false;
  if r4.is_ok {
    let s4: LlmScale = r4.value;
    exp_ok = s4.m == 1024 && s4.e == 11 && all_eq(&o4, -8192);
  }
  sum = sum + report(exp_ok, "q4_0 scale 0.5 shifts exponent to 11");
  // Error arms: empty, bad length, mixed per-block scales.
  var empty = Vec[UInt8].new();
  var oe = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q4_0(&empty, &mut oe), "llm: q4_0 payload is empty", "q4_0 empty rejected");
  var short = Vec[UInt8].new();
  var z = 0;
  while z < 17 {
    short.push((0 as UInt8));
    z = z + 1;
  }
  var os = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q4_0(&short, &mut os), "llm: q4_0 payload length not a multiple of block size", "q4_0 bad length rejected");
  var two = q4_0_block(0x3C00, 0x00, 0x00);
  let b2nd = q4_0_block(0x3800, 0x00, 0x00);
  let a2 = append_bytes(&mut two, &b2nd);
  var om = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q4_0(&two, &mut om), "llm: q4_0 mixed block scales are not supported", "q4_0 mixed scales rejected");
  return sum;
}

// Q5_1 golden vectors: unsigned 5-bit quants with an additive f16 offset m.
fn t92() -> Int {
  var sum = 0;
  // d = 1.0, m = 0, qh and nibbles 0 -> every value 0.
  var b1 = q5_1_block(0x3C00, 0x0000, 0, 0x00);
  var o1 = Vec[Int].new();
  let r1 = llm_dequant_q5_1(&b1, &mut o1);
  if !r1.is_ok {
    let got: Str = r1.error;
    return report(false, "q5_1 golden decode (Err: " + got + ")");
  }
  let s1: LlmScale = r1.value;
  sum = sum + report(s1.m == 1 && s1.e == 10 && o1.len() == 32 && all_eq(&o1, 0), "q5_1 zero quants -> all zero (unit scale)");
  // Fifth bit 0 set only: value 0 has q = 16, the rest 0.
  var b2 = q5_1_block(0x3C00, 0x0000, 0x00000001, 0x00);
  var o2 = Vec[Int].new();
  let r2 = llm_dequant_q5_1(&b2, &mut o2);
  var fifth_ok = false;
  if r2.is_ok {
    let v0: Int = o2[0];
    let v1: Int = o2[1];
    let v16: Int = o2[16];
    fifth_ok = v0 == 16384 && v1 == 0 && v16 == 0;
  }
  sum = sum + report(fifth_ok, "q5_1 fifth bit 0 -> value 0 only");
  // Asymmetric distinct exponents: d = 0.5 (de=11), m = 0.25 (dme=12),
  // q = 1 -> 0.75, represented exactly at E = 12 as 3072.
  var b3 = q5_1_block(0x3800, 0x3400, 0, 0x11);
  var o3 = Vec[Int].new();
  let r3 = llm_dequant_q5_1(&b3, &mut o3);
  var asym_ok = false;
  if r3.is_ok {
    let s3: LlmScale = r3.value;
    asym_ok = s3.m == 1 && s3.e == 12 && o3.len() == 32 && all_eq(&o3, 3072);
  }
  sum = sum + report(asym_ok, "q5_1 0.5*q + 0.25 exact at E=12 (3072)");
  // Mixed per-block d/m are handled over one global exponent: block 0 is
  // 1.0*1 + 0 = 1 -> 4096, block 1 is 0.5*1 + 0.25 = 0.75 -> 3072.
  var two = q5_1_block(0x3C00, 0x0000, 0, 0x11);
  let b2nd = q5_1_block(0x3800, 0x3400, 0, 0x11);
  let a2 = append_bytes(&mut two, &b2nd);
  var o4 = Vec[Int].new();
  let r4 = llm_dequant_q5_1(&two, &mut o4);
  var mixed_ok = false;
  if r4.is_ok && o4.len() == 64 {
    let s4: LlmScale = r4.value;
    let v0: Int = o4[0];
    let v31: Int = o4[31];
    let v32: Int = o4[32];
    let v63: Int = o4[63];
    mixed_ok = s4.m == 1 && s4.e == 12 && v0 == 4096 && v31 == 4096 && v32 == 3072 && v63 == 3072;
  }
  sum = sum + report(mixed_ok, "q5_1 mixed block d/m share E=12");
  // Error arms: empty, bad length, f16 inf scale.
  var empty = Vec[UInt8].new();
  var oe = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q5_1(&empty, &mut oe), "llm: q5_1 payload is empty", "q5_1 empty rejected");
  var short = Vec[UInt8].new();
  var z = 0;
  while z < 23 {
    short.push((0 as UInt8));
    z = z + 1;
  }
  var os = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q5_1(&short, &mut os), "llm: q5_1 payload length not a multiple of block size", "q5_1 bad length rejected");
  var inf = q5_1_block(0x7C00, 0x0000, 0, 0x00);
  var oi = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q5_1(&inf, &mut oi), "llm: f16 is inf", "q5_1 inf scale rejected");
  return sum;
}

// Q6_K golden vectors: 6-bit quants -32..31 with signed per-16 int8 scales.
fn t93() -> Int {
  var sum = 0;
  var ones = scales16(1, 1, 1, 1, 1, 1, 1, 1);
  // d = 1.0, ql/qh zero -> every 6-bit quant is -32.
  var b1 = q6_k_block(0x3C00, &ones, 0x00, 0x00, 0x00, 0x00, 0x00);
  var o1 = Vec[Int].new();
  let r1 = llm_dequant_q6_k(&b1, &mut o1);
  if !r1.is_ok {
    let got: Str = r1.error;
    return report(false, "q6_k golden decode (Err: " + got + ")");
  }
  let s1: LlmScale = r1.value;
  sum = sum + report(s1.m == 1 && s1.e == 10 && o1.len() == 256, "q6_k unit scale (1,10), 256 values");
  sum = sum + report(all_eq(&o1, -32768), "q6_k golden all -32 * 1024");
  // Quant ordering: ql[0] = 0x21, ql[32] = 0x43, qh[0] = 0xE4 decompose into
  // q1 = -31 (index 0), q2 = -13 (32), q3 = 2 (64), q4 = 20 (96).
  var b2 = q6_k_block(0x3C00, &ones, 0x00, 0x00, 0x21, 0x43, 0xE4);
  var o2 = Vec[Int].new();
  let r2 = llm_dequant_q6_k(&b2, &mut o2);
  var order_ok = false;
  if r2.is_ok {
    let v0: Int = o2[0];
    let v1: Int = o2[1];
    let v31: Int = o2[31];
    let v32: Int = o2[32];
    let v64: Int = o2[64];
    let v96: Int = o2[96];
    order_ok = v0 == -31744 && v1 == -32768 && v31 == -32768 && v32 == -13312 && v64 == 2048 && v96 == 20480;
  }
  sum = sum + report(order_ok, "q6_k q1..q4 ordering and 2-bit fields");
  // Signed scales and the is = l/16 index mapping. qh = 0xFF makes every
  // quant 16; half-0 scales [1,-1,1,2,1,-2,1,3], half-1 all 1.
  var sc = scales16(1, 0 - 1, 1, 2, 1, 0 - 2, 1, 3);
  var b3 = q6_k_block(0x3C00, &sc, 0x00, 0xFF, 0x00, 0x00, 0xFF);
  var o3 = Vec[Int].new();
  let r3 = llm_dequant_q6_k(&b3, &mut o3);
  var sign_ok = false;
  var index_ok = false;
  if r3.is_ok {
    let v0: Int = o3[0];
    let v15: Int = o3[15];
    let v16: Int = o3[16];
    let v31: Int = o3[31];
    let v32: Int = o3[32];
    let v48: Int = o3[48];
    let v64: Int = o3[64];
    let v80: Int = o3[80];
    let v96: Int = o3[96];
    let v112: Int = o3[112];
    sign_ok = v0 == 16384 && v16 == -16384 && v48 == 32768 && v80 == -32768 && v112 == 49152;
    index_ok = v15 == 16384 && v31 == -16384 && v32 == 16384 && v64 == 16384 && v96 == 16384;
  }
  sum = sum + report(sign_ok, "q6_k signed scales [+1,-1,+2,-2,+3] exact");
  sum = sum + report(index_ok, "q6_k is = l/16 scale index at l=15/16");
  // Distinct d exponent: d = 0.5, q = 16 -> value 8 at E = 11 (16384).
  var b4 = q6_k_block(0x3800, &ones, 0x00, 0xFF, 0x00, 0x00, 0xFF);
  var o4 = Vec[Int].new();
  let r4 = llm_dequant_q6_k(&b4, &mut o4);
  var exp_ok = false;
  if r4.is_ok {
    let s4: LlmScale = r4.value;
    exp_ok = s4.m == 1 && s4.e == 11 && all_eq(&o4, 16384);
  }
  sum = sum + report(exp_ok, "q6_k d=0.5 value 8 at E=11");
  // Mixed super-block d over one global exponent: 16 -> 32768, then 8 -> 16384.
  var two = q6_k_block(0x3C00, &ones, 0x00, 0xFF, 0x00, 0x00, 0xFF);
  let b2nd = q6_k_block(0x3800, &ones, 0x00, 0xFF, 0x00, 0x00, 0xFF);
  let a2 = append_bytes(&mut two, &b2nd);
  var o5 = Vec[Int].new();
  let r5 = llm_dequant_q6_k(&two, &mut o5);
  var mixed_ok = false;
  if r5.is_ok && o5.len() == 512 {
    let s5: LlmScale = r5.value;
    let v0: Int = o5[0];
    let v255: Int = o5[255];
    let v256: Int = o5[256];
    let v511: Int = o5[511];
    mixed_ok = s5.m == 1 && s5.e == 11 && v0 == 32768 && v255 == 32768 && v256 == 16384 && v511 == 16384;
  }
  sum = sum + report(mixed_ok, "q6_k mixed d blocks share E=11");
  // Error arms: empty, bad length, f16 inf scale.
  var empty = Vec[UInt8].new();
  var oe = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q6_k(&empty, &mut oe), "llm: q6_k payload is empty", "q6_k empty rejected");
  var short = Vec[UInt8].new();
  var z = 0;
  while z < 209 {
    short.push((0 as UInt8));
    z = z + 1;
  }
  var os = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q6_k(&short, &mut os), "llm: q6_k payload length not a multiple of block size", "q6_k bad length rejected");
  var inf = q6_k_block(0x7C00, &ones, 0x00, 0x00, 0x00, 0x00, 0x00);
  var oi = Vec[Int].new();
  sum = sum + expect_scale_err(llm_dequant_q6_k(&inf, &mut oi), "llm: f16 is inf", "q6_k inf scale rejected");
  return sum;
}

// --------------------------------------------------
//  Tokenizer completion fixtures (GPT-2 escape + pre-tokenizer + SPM)
// --------------------------------------------------

fn bytes_eq(a: &Vec[UInt8], w: &Vec[UInt8]) -> Bool {
  if a.len() != w.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = w[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn strs_eq(a: &Vec[Str], w: &Vec[Str]) -> Bool {
  if a.len() != w.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Str = a[i];
    let y: Str = w[i];
    if !str_eq(x, y) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn u8v(vals: &Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vals.len() {
    let x: Int = vals[i];
    out.push((x as UInt8));
    i = i + 1;
  }
  return out;
}

// Build a Str holding arbitrary raw bytes (used for non-ASCII token strings
// in the builder-based GGUF fixtures).
fn str_of_bytes(vals: &Vec[Int]) -> Str {
  let raw = u8v(vals);
  return builder.sb_to_str(&raw);
}

fn str_u8v(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn str_bytes_eq(s: Str, want: &Vec[Int]) -> Bool {
  let got = str_u8v(s);
  let w = u8v(want);
  return bytes_eq(&got, &w);
}

fn s1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn s2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn s3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn s4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn want_n6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn check_chunks(text: Str, want: &Vec[Str], name: Str) -> Int {
  let r = llm_gpt2_pretokenize(text);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got_chunks: Vec[Str] = r.value;
  return report(strs_eq(&got_chunks, want), name);
}

fn expect_spm_err(r: Result[LlmSpmVocab, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

// Raw GGUF writer helpers for the SPM fixture (xiom.gguf's builder has no
// float-array entry, and the test needs real f32 scores to pin score-order
// traversal).
fn wu32(out: &mut Vec[UInt8], x: Int) {
  out.push(((x & 255) as UInt8));
  out.push((((x >> 8) & 255) as UInt8));
  out.push((((x >> 16) & 255) as UInt8));
  out.push((((x >> 24) & 255) as UInt8));
}

fn wu64(out: &mut Vec[UInt8], x: Int) {
  wu32(out, x & 0xFFFFFFFF);
  wu32(out, (x >> 32) & 0xFFFFFFFF);
}

fn wascii(out: &mut Vec[UInt8], s: Str) {
  let n = string.str_len(s);
  wu64(out, n);
  var i = 0;
  while i < n {
    let raw: UInt8 = string.byte_at(s, i);
    out.push(raw);
    i = i + 1;
  }
}

// SPM ASCII tokens used by the scored fixtures.
fn spm_tokens() -> Vec[Str] {
  var t = Vec[Str].new();
  t.push("a");   // 0
  t.push("b");   // 1
  t.push("c");   // 2
  t.push("ab");  // 3
  t.push("bc");  // 4
  return t;
}

// Raw f32 bit patterns for -1.0, -2.0, -3.0, -10.0, -1.0 (scores of the
// tokens above) and for five copies of -1.0 (the tie fixture).
fn spm_score_bits_ordered() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(3212836864);  // -1.0  a
  v.push(3221225472);  // -2.0  b
  v.push(3225419776);  // -3.0  c
  v.push(3240099840);  // -10.0 ab
  v.push(3212836864);  // -1.0  bc
  return v;
}

fn spm_score_bits_tied() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < 5 {
    v.push(3212836864);
    i = i + 1;
  }
  return v;
}

// Header: model "llama", tokens, scores (f32 array, first `score_count`
// bit patterns written), no tensors, zero padding to the 32-byte alignment.
fn raw_spm_gguf(tokens: &Vec[Str], bits: &Vec[Int], score_count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((71 as UInt8));
  out.push((71 as UInt8));
  out.push((85 as UInt8));
  out.push((70 as UInt8));
  wu32(out, 3);
  wu64(out, 0);
  wu64(out, 3);
  wascii(out, "tokenizer.ggml.model");
  wu32(out, 8);
  wascii(out, "llama");
  wascii(out, "tokenizer.ggml.tokens");
  wu32(out, 9);
  wu32(out, 8);
  wu64(out, tokens.len());
  var t = 0;
  while t < tokens.len() {
    let ts: Str = tokens[t];
    wascii(out, ts);
    t = t + 1;
  }
  wascii(out, "tokenizer.ggml.scores");
  wu32(out, 9);
  wu32(out, 6);
  wu64(out, score_count);
  var k = 0;
  while k < score_count {
    let b: Int = bits[k];
    wu32(out, b);
    k = k + 1;
  }
  while out.len() % 32 != 0 {
    out.push((0 as UInt8));
  }
  return out;
}

fn spm_vocab(bits: &Vec[Int]) -> LlmSpmVocab {
  let tokens = spm_tokens();
  let buf = raw_spm_gguf(&tokens, bits, tokens.len());
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_spm_vocab_from_gguf(&g);
  return vr.value;
}

// Non-ASCII probe: a GGUF string value "gpt2" followed by the UTF-8 bytes
// C4 A0 (U+0120, the escaped form of byte 0x20). The container rejects it.
fn raw_nonascii_gguf() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((71 as UInt8));
  out.push((71 as UInt8));
  out.push((85 as UInt8));
  out.push((70 as UInt8));
  wu32(out, 3);
  wu64(out, 0);
  wu64(out, 1);
  wascii(out, "tokenizer.ggml.model");
  wu32(out, 8);
  wu64(out, 6);
  out.push((103 as UInt8));  // g
  out.push((112 as UInt8));  // p
  out.push((116 as UInt8));  // t
  out.push((50 as UInt8));   // 2
  out.push((196 as UInt8));  // U+0120 UTF-8 byte 1
  out.push((160 as UInt8));  // U+0120 UTF-8 byte 2
  while out.len() % 32 != 0 {
    out.push((0 as UInt8));
  }
  return out;
}

fn check_spm_encode(v: &LlmSpmVocab, text: Str, want: &Vec[Int], name: Str) -> Int {
  let r = llm_spm_encode(v, text);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got_ids: Vec[Int] = r.value;
  return report(ids_eq(&got_ids, want), name);
}

// GPT-2 bytes_to_unicode mapping: visible bytes identity, 68 escapes.
fn t74() -> Int {
  var sum = 0;
  let c21 = llm_gpt2_byte_to_codepoint(33);
  let c20 = llm_gpt2_byte_to_codepoint(32);
  let c7e = llm_gpt2_byte_to_codepoint(126);
  let c7f = llm_gpt2_byte_to_codepoint(127);
  let ca1 = llm_gpt2_byte_to_codepoint(161);
  let cad = llm_gpt2_byte_to_codepoint(173);
  let cff = llm_gpt2_byte_to_codepoint(255);
  if !c21.is_ok || !c20.is_ok || !c7e.is_ok || !c7f.is_ok || !ca1.is_ok || !cad.is_ok || !cff.is_ok {
    return report(false, "gpt2 byte map accessors ok");
  }
  sum = sum + report(c21.value == 33, "gpt2 0x21 -> U+0021");
  sum = sum + report(c7e.value == 126, "gpt2 0x7E -> U+007E");
  sum = sum + report(c20.value == 288, "gpt2 0x20 -> U+0120 (288)");
  sum = sum + report(c7f.value == 289, "gpt2 0x7F -> U+0121 (289)");
  sum = sum + report(ca1.value == 161, "gpt2 0xA1 -> U+00A1");
  sum = sum + report(cad.value == 323, "gpt2 0xAD -> U+0143 (323)");
  sum = sum + report(cff.value == 255, "gpt2 0xFF -> U+00FF");

  let i288 = llm_gpt2_codepoint_to_byte(288);
  let i323 = llm_gpt2_codepoint_to_byte(323);
  let i33 = llm_gpt2_codepoint_to_byte(33);
  if !i288.is_ok || !i323.is_ok || !i33.is_ok {
    return sum + report(false, "gpt2 inverse accessors ok");
  }
  sum = sum + report(i288.value == 32, "gpt2 U+0120 -> 0x20");
  sum = sum + report(i323.value == 173, "gpt2 U+0143 -> 0xAD");
  sum = sum + report(i33.value == 33, "gpt2 U+0021 -> 0x21");

  var all_ok = true;
  var b = 0;
  while b < 256 {
    let cr = llm_gpt2_byte_to_codepoint(b);
    let cp: Int = cr.value;
    let br = llm_gpt2_codepoint_to_byte(cp);
    if !br.is_ok || br.value != b {
      all_ok = false;
    }
    b = b + 1;
  }
  sum = sum + report(all_ok, "gpt2 byte/codepoint roundtrip (256)");
  sum = sum + expect_int_err(llm_gpt2_byte_to_codepoint(256), "llm: byte out of range", "gpt2 byte 256 rejected");
  sum = sum + expect_int_err(llm_gpt2_codepoint_to_byte(0), "llm: codepoint not in gpt2 byte map", "gpt2 U+0000 rejected");
  return sum;
}

// UTF-8 + escape/unescape golden vectors.
fn t75() -> Int {
  var sum = 0;
  var e0 = Vec[UInt8].new();
  let r0 = llm_gpt2_escape(&u8v(&want2(104, 105)), &mut e0);
  if !r0.is_ok {
    return report(false, "escape ascii ok");
  }
  sum = sum + report(r0.value == 2 && bytes_eq(&e0, &u8v(&want2(104, 105))), "gpt2 escape hi -> hi");

  var e1 = Vec[UInt8].new();
  let r1 = llm_gpt2_escape(&u8v(&want1(32)), &mut e1);
  sum = sum + report(r1.is_ok && bytes_eq(&e1, &u8v(&want2(196, 160))), "gpt2 escape 0x20 -> C4 A0");

  var e2 = Vec[UInt8].new();
  let src3 = want3(0, 127, 173);
  let r2 = llm_gpt2_escape(&u8v(&src3), &mut e2);
  let want_e = want_n6(196, 128, 196, 161, 197, 131);
  sum = sum + report(r2.is_ok && r2.value == 3 && bytes_eq(&e2, &u8v(&want_e)), "gpt2 escape 0x00 0x7F 0xAD");

  var d1 = Vec[UInt8].new();
  let q1 = llm_gpt2_unescape(&u8v(&want2(196, 160)), &mut d1);
  sum = sum + report(q1.is_ok && bytes_eq(&d1, &u8v(&want1(32))), "gpt2 unescape C4 A0 -> 0x20");

  var all_bytes = Vec[UInt8].new();
  var b = 0;
  while b < 256 {
    all_bytes.push((b as UInt8));
    b = b + 1;
  }
  var esc = Vec[UInt8].new();
  let er = llm_gpt2_escape(&all_bytes, &mut esc);
  var un = Vec[UInt8].new();
  let ur = llm_gpt2_unescape(&esc, &mut un);
  sum = sum + report(er.is_ok && ur.is_ok && bytes_eq(&un, &all_bytes), "gpt2 escape/unescape roundtrip (256)");

  var bad1 = Vec[UInt8].new();
  sum = sum + expect_int_err(llm_gpt2_unescape(&u8v(&want1(196)), &mut bad1), "llm: invalid utf8", "gpt2 truncated utf8 rejected");
  var bad2 = Vec[UInt8].new();
  sum = sum + expect_int_err(llm_gpt2_unescape(&u8v(&want1(128)), &mut bad2), "llm: invalid utf8", "gpt2 stray continuation rejected");
  var bad3 = Vec[UInt8].new();
  sum = sum + expect_int_err(llm_gpt2_unescape(&u8v(&want1(1)), &mut bad3), "llm: codepoint not in gpt2 byte map", "gpt2 unmapped codepoint rejected");

  var us = Vec[UInt8].new();
  let usr = llm_gpt2_unescape_str("hi", &mut us);
  sum = sum + report(usr.is_ok && bytes_eq(&us, &u8v(&want2(104, 105))), "gpt2 unescape_str hi");

  var u4 = Vec[UInt8].new();
  let a4 = llm_utf8_append(128512, &mut u4);
  sum = sum + report(a4.is_ok && a4.value == 4 && bytes_eq(&u4, &u8v(&want4(240, 159, 152, 128))), "utf8 append U+1F600 (4 bytes)");
  var u2 = Vec[UInt8].new();
  let a2 = llm_utf8_append(233, &mut u2);
  sum = sum + report(a2.is_ok && a2.value == 2 && bytes_eq(&u2, &u8v(&want2(195, 169))), "utf8 append U+00E9 (2 bytes)");
  var uz = Vec[UInt8].new();
  sum = sum + expect_int_err(llm_utf8_append(1114112, &mut uz), "llm: codepoint out of range", "utf8 append U+110000 rejected");
  return sum;
}

// GPT-2 regex pre-tokenizer golden chunks.
fn t76() -> Int {
  var sum = 0;
  sum = sum + check_chunks("hello world", &s2("hello", " world"), "split hello world");
  sum = sum + check_chunks("hello  world", &s3("hello", " ", " world"), "split double space");
  sum = sum + check_chunks("a1b2", &s4("a", "1", "b", "2"), "split letters/digits");
  sum = sum + check_chunks("  ", &s1("  "), "split trailing whitespace run");
  sum = sum + check_chunks("", &Vec[Str].new(), "split empty");
  sum = sum + check_chunks("it's a test", &s4("it", "'s", " a", " test"), "split contraction 's");
  sum = sum + check_chunks("don't", &s2("don", "'t"), "split contraction 't");
  sum = sum + check_chunks("I'll go", &s3("I", "'ll", " go"), "split contraction 'll");
  sum = sum + check_chunks("x'y", &s3("x", "'", "y"), "split unknown apostrophe run");
  sum = sum + check_chunks("abc\n\ndef", &s4("abc", "\n", "\n", "def"), "split newline run");
  sum = sum + check_chunks("hello  ", &s2("hello", "  "), "split trailing run");
  sum = sum + check_chunks("!? x", &s2("!?", " x"), "split punctuation + space word");
  sum = sum + check_chunks("abc \ndef", &s4("abc", " ", "\n", "def"), "split space then newline");
  return sum;
}

// Pre-tokenizer edge cases.
fn t77() -> Int {
  var sum = 0;
  sum = sum + check_chunks("'s", &s1("'s"), "split bare contraction");
  sum = sum + check_chunks("'S", &s2("'", "S"), "split uppercase not a contraction");
  sum = sum + check_chunks("a  b", &s3("a", " ", " b"), "split two-space gap");
  sum = sum + check_chunks("1 2", &s2("1", " 2"), "split digit space digit");
  sum = sum + check_chunks("3.14", &s3("3", ".", "14"), "split decimal point");
  sum = sum + check_chunks("  hi", &s2(" ", " hi"), "split leading two spaces");
  return sum;
}

// SPM extraction from the raw scored fixture.
fn t78() -> Int {
  let bits = spm_score_bits_ordered();
  let v = spm_vocab(&bits);
  var sum = 0;
  let model = llm_spm_model(&v);
  sum = sum + report(str_eq(model, "llama"), "spm model llama");
  sum = sum + report(llm_spm_size(&v) == 5, "spm size 5");
  let tk3 = llm_spm_token(&v, 3);
  let tk5 = llm_spm_token(&v, 5);
  sum = sum + report(tk3.is_ok && str_eq(tk3.value, "ab"), "spm token 3 = ab");
  sum = sum + expect_str_err(tk5, "llm: token index out of range", "spm token 5 rejected");
  let sc0 = llm_spm_score(&v, 0);
  let sc3 = llm_spm_score(&v, 3);
  if !sc0.is_ok || !sc3.is_ok {
    return sum + report(false, "spm score accessors ok");
  }
  let s0: LlmScale = sc0.value;
  let s3: LlmScale = sc3.value;
  sum = sum + report(s0.m == -8388608 && s0.e == 23, "spm score 0 = -1.0 at e=23");
  sum = sum + report(s3.m == -83886080 && s3.e == 23, "spm score 3 = -10.0 folded exactly");
  sum = sum + report(llm_spm_find_token(&v, "bc") == 4, "spm find bc = 4");
  sum = sum + report(llm_spm_find_token(&v, "zz") == -1, "spm find miss = -1");
  let tt = v.token_types;
  let t0: Int = tt[0];
  sum = sum + report(t0 == 1, "spm token type default 1");
  sum = sum + report(llm_spm_bos(&v) == -1, "spm bos absent -1");
  return sum;
}

// SPM scored merge traversal: highest score first.
fn t79() -> Int {
  let bits = spm_score_bits_ordered();
  let v = spm_vocab(&bits);
  var sum = 0;
  sum = sum + check_spm_encode(&v, "abc", &want2(0, 4), "spm abc -> a + bc (score order)");
  sum = sum + check_spm_encode(&v, "ab", &want1(3), "spm ab -> ab");
  sum = sum + check_spm_encode(&v, "bc", &want1(4), "spm bc -> bc");
  sum = sum + check_spm_encode(&v, "a", &want1(0), "spm a -> a");
  sum = sum + check_spm_encode(&v, "", &Vec[Int].new(), "spm empty");
  sum = sum + check_spm_encode(&v, "cab", &want2(2, 3), "spm cab -> c + ab");
  return sum;
}

// SPM tie-break: equal scores merge the leftmost pair.
fn t80() -> Int {
  let bits = spm_score_bits_tied();
  let v = spm_vocab(&bits);
  var sum = 0;
  sum = sum + check_spm_encode(&v, "abc", &want2(3, 2), "spm tie -> leftmost ab");
  sum = sum + check_spm_encode(&v, "abcabc", &want4(3, 2, 3, 2), "spm tie repeated");
  return sum;
}

// SPM decode, roundtrip and unknown-byte failure.
fn t81() -> Int {
  let bits = spm_score_bits_ordered();
  let v = spm_vocab(&bits);
  var sum = 0;
  let d1 = llm_spm_decode(&v, &want2(0, 4));
  sum = sum + report(d1.is_ok && str_eq(d1.value, "abc"), "spm decode [0,4] = abc");
  let d0 = llm_spm_decode(&v, &Vec[Int].new());
  sum = sum + report(d0.is_ok && str_eq(d0.value, ""), "spm decode []");
  sum = sum + expect_str_err(llm_spm_decode(&v, &want1(5)), "llm: token id out of range", "spm decode id 5 rejected");

  var texts = Vec[Str].new();
  texts.push("abc");
  texts.push("ab");
  texts.push("cab");
  texts.push("bcbc");
  var rt_ok = true;
  var i = 0;
  while i < texts.len() {
    let tx: Str = texts[i];
    let er = llm_spm_encode(&v, tx);
    if !er.is_ok {
      rt_ok = false;
    } else {
      let idsv: Vec[Int] = er.value;
      let dr = llm_spm_decode(&v, &idsv);
      if !dr.is_ok || !str_eq(dr.value, tx) {
        rt_ok = false;
      }
    }
    i = i + 1;
  }
  sum = sum + report(rt_ok, "spm encode/decode roundtrip (4 texts)");
  sum = sum + expect_ids_err(llm_spm_encode(&v, "z"), "llm: spm byte not in vocabulary", "spm unknown byte rejected");
  return sum;
}

// SPM extraction error arms.
fn t82() -> Int {
  var sum = 0;
  let gpt2buf = header_plain("gpt2");
  let pr = gguf_parse(&gpt2buf);
  let g = pr.value;
  sum = sum + expect_spm_err(llm_spm_vocab_from_gguf(&g), "llm: spm tokenizer model is not llama", "spm gpt2 model rejected");

  let tokens = spm_tokens();
  var ints = Vec[Int].new();
  ints.push(0);
  ints.push(0);
  ints.push(0);
  ints.push(0);
  ints.push(0);
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "llama");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a3 = gguf_builder_add_kv_arr_int(&mut b, "tokenizer.ggml.scores", 5, &ints);
  let fr = gguf_builder_finish(&b);
  let wbuf = fr.value;
  let wpr = gguf_parse(&wbuf);
  let wg = wpr.value;
  sum = sum + expect_spm_err(llm_spm_vocab_from_gguf(&wg), "llm: spm scores are not a float array", "spm int scores rejected");

  let bits = spm_score_bits_ordered();
  let short_buf = raw_spm_gguf(&tokens, &bits, 2);
  let spr = gguf_parse(&short_buf);
  let sg = spr.value;
  sum = sum + expect_spm_err(llm_spm_vocab_from_gguf(&sg), "llm: spm score count smaller than token count", "spm short scores rejected");
  return sum;
}

// Non-ASCII GGUF probe (resolved): the container now accepts arbitrary
// string bytes and the byte accessors return them losslessly.
fn t83() -> Int {
  var sum = 0;
  let buf = raw_nonascii_gguf();
  let pr = gguf_parse(&buf);
  sum = sum + report(pr.is_ok, "non-ascii gguf probe: parsed (container fixed)");
  if pr.is_ok {
    let g = pr.value;
    let ki = gguf_find_kv(&g, "tokenizer.ggml.model");
    if ki.is_ok {
      let br = gguf_kv_str_bytes(&g, ki.value);
      // "gpt2" + C4 A0: six bytes.
      var w6 = Vec[Int].new();
      w6.push(103); w6.push(112); w6.push(116); w6.push(50); w6.push(196); w6.push(160);
      let raw = br.value;
      sum = sum + report(br.is_ok && bytes_eq(&raw, &u8v(&w6)), "non-ascii gguf probe: byte accessor is lossless");
    } else {
      sum = sum + report(false, "non-ascii gguf probe: model key missing");
    }
  }
  // The escape layer itself produces exactly those bytes for a space.
  var e = Vec[UInt8].new();
  let er = llm_gpt2_escape(&u8v(&want1(32)), &mut e);
  sum = sum + report(er.is_ok && bytes_eq(&e, &u8v(&want2(196, 160))), "non-ascii probe: escape emits C4 A0");
  return sum;
}

// --------------------------------------------------
//  Real-vocabulary fixtures (non-ASCII token bytes)
// --------------------------------------------------

// Real-SPM fixture tokens: ASCII pieces, U+2581 (E2 96 81) word-boundary
// pieces, a non-ASCII UTF-8 token (C3 A9 = "é"), a <0xXX> byte fallback and
// control tokens. Ids: 0 a, 1 b, 2 c, 3 ab, 4 ▁, 5 ▁a, 6 ▁ab, 7 é,
// 8 <0x7A>, 9 <s>, 10 </s>.
fn spm_real_tokens() -> Vec[Str] {
  var t = Vec[Str].new();
  t.push("a");
  t.push("b");
  t.push("c");
  t.push("ab");
  t.push(str_of_bytes(&want3(226, 150, 129)));
  t.push(str_of_bytes(&want4(226, 150, 129, 97)));
  t.push(str_of_bytes(&want5(226, 150, 129, 97, 98)));
  t.push(str_of_bytes(&want2(195, 169)));
  t.push("<0x7A>");
  t.push("<s>");
  t.push("</s>");
  return t;
}

// f32 bits: a/b/c -1, ab -10, ▁ -5, ▁a -2, ▁ab -1, é -3, <0x7A> -20,
// <s>/</s> -100. The ordering makes " ab" merge ▁a before ▁ab, and "ab"
// merge directly to id 3.
fn spm_real_score_bits() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(3212836864);  // -1.0   a
  v.push(3212836864);  // -1.0   b
  v.push(3212836864);  // -1.0   c
  v.push(3240099840);  // -10.0  ab
  v.push(3231711232);  // -5.0   ▁
  v.push(3221225472);  // -2.0   ▁a
  v.push(3212836864);  // -1.0   ▁ab
  v.push(3225419776);  // -3.0   é
  v.push(3248488448);  // -20.0  <0x7A>
  v.push(3267887104);  // -100.0 <s>
  v.push(3267887104);  // -100.0 </s>
  return v;
}

// Raw header: model "llama", the 11 tokens above, an f32 score array, and
// (when with_flags != 0) bos/eos ids plus add_bos_token/add_eos_token = 1.
// Token payloads are written byte-for-byte, including non-ASCII bytes.
fn raw_spm_real_gguf(tokens: &Vec[Str], bits: &Vec[Int], with_flags: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((71 as UInt8));
  out.push((71 as UInt8));
  out.push((85 as UInt8));
  out.push((70 as UInt8));
  wu32(out, 3);
  wu64(out, 0);
  if with_flags != 0 {
    wu64(out, 7);
  } else {
    wu64(out, 3);
  }
  wascii(out, "tokenizer.ggml.model");
  wu32(out, 8);
  wascii(out, "llama");
  wascii(out, "tokenizer.ggml.tokens");
  wu32(out, 9);
  wu32(out, 8);
  wu64(out, tokens.len());
  var t = 0;
  while t < tokens.len() {
    let ts: Str = tokens[t];
    wascii(out, ts);
    t = t + 1;
  }
  wascii(out, "tokenizer.ggml.scores");
  wu32(out, 9);
  wu32(out, 6);
  wu64(out, bits.len());
  var k = 0;
  while k < bits.len() {
    let b: Int = bits[k];
    wu32(out, b);
    k = k + 1;
  }
  if with_flags != 0 {
    wascii(out, "tokenizer.ggml.bos_token_id");
    wu32(out, 4);
    wu32(out, 9);
    wascii(out, "tokenizer.ggml.eos_token_id");
    wu32(out, 4);
    wu32(out, 10);
    wascii(out, "tokenizer.ggml.add_bos_token");
    wu32(out, 4);
    wu32(out, 1);
    wascii(out, "tokenizer.ggml.add_eos_token");
    wu32(out, 4);
    wu32(out, 1);
  }
  while out.len() % 32 != 0 {
    out.push((0 as UInt8));
  }
  return out;
}

fn spm_real_vocab(with_flags: Int) -> LlmSpmVocab {
  let tokens = spm_real_tokens();
  let bits = spm_real_score_bits();
  let buf = raw_spm_real_gguf(&tokens, &bits, with_flags);
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_spm_vocab_from_gguf(&g);
  return vr.value;
}

fn check_spm_decode(v: &LlmSpmVocab, ids: &Vec[Int], want: Str, name: Str) -> Int {
  let r = llm_spm_decode(v, ids);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got: Str = r.value;
  return report(str_eq(got, want), name);
}

fn check_spm_decode_bytes(v: &LlmSpmVocab, ids: &Vec[Int], want: &Vec[Int], name: Str) -> Int {
  let r = llm_spm_decode(v, ids);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got: Str = r.value;
  return report(str_bytes_eq(got, want), name);
}

// t84: real SPM extraction over non-ASCII GGUF tokens (byte accessors).
fn t84() -> Int {
  var sum = 0;
  let v = spm_real_vocab(0);
  let model = llm_spm_model(&v);
  sum = sum + report(str_eq(model, "llama"), "spm real model llama");
  sum = sum + report(llm_spm_size(&v) == 11, "spm real size 11");
  let t4 = llm_spm_token(&v, 4);
  let t7 = llm_spm_token(&v, 7);
  sum = sum + report(t4.is_ok && str_bytes_eq(t4.value, &want3(226, 150, 129)), "spm real token 4 = U+2581 (E2 96 81)");
  sum = sum + report(t7.is_ok && str_bytes_eq(t7.value, &want2(195, 169)), "spm real token 7 = é (C3 A9)");
  let s0 = llm_spm_score(&v, 0);
  let s6 = llm_spm_score(&v, 6);
  sum = sum + report(s0.is_ok && s0.value.m == 0 - 8388608 && s0.value.e == 23, "spm real score a = -1.0 (e=23)");
  sum = sum + report(s6.is_ok && s6.value.m == 0 - 8388608 && s6.value.e == 23, "spm real score ▁ab = -1.0");
  let marker = str_of_bytes(&want3(226, 150, 129));
  let accent = str_of_bytes(&want2(195, 169));
  sum = sum + report(llm_spm_find_token(&v, marker) == 4, "spm real find ▁ = 4");
  sum = sum + report(llm_spm_find_token(&v, accent) == 7, "spm real find é = 7");
  sum = sum + report(llm_spm_add_bos(&v) == 0 && llm_spm_add_eos(&v) == 0, "spm real flags absent default 0");
  return sum;
}

// t85: SentencePiece ▁ normalization on encode, reverse on decode, non-ASCII
// token, byte-fallback path, and roundtrips.
fn t85() -> Int {
  var sum = 0;
  let v = spm_real_vocab(0);
  sum = sum + check_spm_encode(&v, " ", &want1(4), "spm real space -> ▁ (id 4)");
  sum = sum + check_spm_encode(&v, " ab", &want1(6), "spm real ' ab' -> ▁ab (id 6)");
  sum = sum + check_spm_encode(&v, "ab", &want1(3), "spm real ab -> id 3");
  sum = sum + check_spm_encode(&v, "a", &want1(0), "spm real a -> id 0");
  sum = sum + check_spm_encode(&v, "é", &want1(7), "spm real é -> id 7 (non-ASCII)");
  sum = sum + check_spm_encode(&v, "z", &want1(8), "spm real z -> byte fallback <0x7A>");
  sum = sum + check_spm_decode(&v, &want1(4), " ", "spm real decode ▁ -> space");
  sum = sum + check_spm_decode(&v, &want1(6), " ab", "spm real decode ▁ab -> ' ab'");
  sum = sum + check_spm_decode_bytes(&v, &want1(7), &want2(195, 169), "spm real decode é bytes");
  sum = sum + check_spm_decode(&v, &want1(8), "z", "spm real decode byte fallback -> z");

  let texts = Vec[Str].new();
  texts.push(" ");
  texts.push(" ab");
  texts.push("ab");
  texts.push(str_of_bytes(&want2(195, 169)));
  texts.push("z");
  var ok = 1;
  var i = 0;
  while i < texts.len() {
    let tx: Str = texts[i];
    let er = llm_spm_encode(&v, tx);
    if !er.is_ok {
      ok = 0;
    } else {
      let ids: Vec[Int] = er.value;
      let dr = llm_spm_decode(&v, &ids);
      if !dr.is_ok {
        ok = 0;
      } else {
        let back: Str = dr.value;
        if !str_eq(back, tx) {
          ok = 0;
        }
      }
    }
    i = i + 1;
  }
  sum = sum + report(ok == 1, "spm real encode/decode roundtrip (5 texts, incl ▁ + é)");
  return sum;
}

// t86: BOS/EOS insertion flags from tokenizer.ggml.add_bos_token /
// add_eos_token.
fn t86() -> Int {
  var sum = 0;
  let v = spm_real_vocab(1);
  sum = sum + report(llm_spm_add_bos(&v) == 1 && llm_spm_add_eos(&v) == 1, "spm flags read 1/1");
  sum = sum + report(llm_spm_bos(&v) == 9 && llm_spm_eos(&v) == 10, "spm flagged bos/eos 9/10");
  sum = sum + check_spm_encode(&v, "ab", &want3(9, 3, 10), "spm encode inserts BOS/EOS");
  sum = sum + check_spm_encode(&v, "", &want2(9, 10), "spm empty text still gets BOS/EOS");
  sum = sum + check_spm_encode(&v, " ", &want3(9, 4, 10), "spm ▁ with BOS/EOS");
  sum = sum + check_spm_encode(&v, "z", &want3(9, 8, 10), "spm byte fallback with BOS/EOS");
  return sum;
}

// --------------------------------------------------
//  GPT-2 real-vocabulary fixture (builder, escaped non-ASCII keys)
// --------------------------------------------------

// Escaped GPT-2 tokens: ids 0 h, 1 i, 2 hi, 3 Ġ (U+0120 = space), 4 Ġhi
// (" hi"), 5 Ã (raw byte C3), 6 © (raw byte A9), 7 Ã© (raw bytes C3 A9 =
// "é"). The loader applies bytes_to_unicode inverse to every key.
fn gpt2_real_tokens() -> Vec[Str] {
  var t = Vec[Str].new();
  t.push("h");
  t.push("i");
  t.push("hi");
  t.push(str_of_bytes(&want2(196, 160)));
  t.push(str_of_bytes(&want4(196, 160, 104, 105)));
  t.push(str_of_bytes(&want2(195, 131)));
  t.push(str_of_bytes(&want2(194, 169)));
  t.push(str_of_bytes(&want4(195, 131, 194, 169)));
  return t;
}

// Escaped merge table in rank order: "Ġ h", "h i", "Ġh i", "Ã ©".
// Rank 0 ("Ġ h") precedes rank 1 ("h i") so " hi" merges to the single token
// id 4 (BPE picks the lowest rank first, exactly as llama.cpp does).
fn gpt2_real_merges() -> Vec[Str] {
  var m = Vec[Str].new();
  m.push(str_of_bytes(&want3(196, 160, 32)) + "h");
  m.push("h i");
  m.push(str_of_bytes(&want3(196, 160, 104)) + " i");
  m.push(str_of_bytes(&want3(195, 131, 32)) + str_of_bytes(&want2(194, 169)));
  return m;
}

fn gpt2_real_buffer() -> Vec[UInt8] {
  let tokens = gpt2_real_tokens();
  let merges = gpt2_real_merges();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &tokens);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &merges);
  let a4 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.bos_token_id", 4, 0);
  let a5 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.eos_token_id", 4, 1);
  let a6 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.add_bos_token", 7, 1);
  let a7 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.add_eos_token", 7, 0);
  let fr = gguf_builder_finish(&b);
  return fr.value;
}

// t87: GPT-2 real-vocab loading over escaped keys, raw-byte encode/decode.
fn t87() -> Int {
  var sum = 0;
  let buf = gpt2_real_buffer();
  let pr = gguf_parse(&buf);
  sum = sum + report(pr.is_ok, "gpt2 real gguf built + parsed");
  if !pr.is_ok {
    return sum;
  }
  let g = pr.value;
  let vr = llm_gpt2_vocab_from_gguf(&g);
  if !vr.is_ok {
    let got: Str = vr.error;
    return sum + report(false, "gpt2 real vocab loaded (Err: " + got + ")");
  }
  let v = vr.value;
  let model = llm_vocab_model(&v);
  sum = sum + report(str_eq(model, "gpt2"), "gpt2 real model");
  sum = sum + report(llm_vocab_size(&v) == 8, "gpt2 real size 8");
  let t3 = llm_vocab_token(&v, 3);
  let t7 = llm_vocab_token(&v, 7);
  sum = sum + report(t3.is_ok && str_bytes_eq(t3.value, &want1(32)), "gpt2 real token 3 unescaped to space");
  sum = sum + report(t7.is_ok && str_bytes_eq(t7.value, &want2(195, 169)), "gpt2 real token 7 unescaped to é bytes");
  sum = sum + report(llm_vocab_merge_count(&v) == 4, "gpt2 real merge count 4");
  let m0 = llm_vocab_merge(&v, 0);
  let m3 = llm_vocab_merge(&v, 3);
  sum = sum + report(m0.is_ok && str_bytes_eq(m0.value, &want3(32, 32, 104)), "gpt2 real merge 0 = ' h' (escaped side unescaped)");
  sum = sum + report(m3.is_ok && str_bytes_eq(m3.value, &want3(195, 32, 169)), "gpt2 real merge 3 = C3 + space + A9");
  sum = sum + report(llm_vocab_add_bos(&v) == 1 && llm_vocab_add_eos(&v) == 0, "gpt2 real flags 1/0");
  sum = sum + report(llm_vocab_bos(&v) == 0 && llm_vocab_eos(&v) == 1, "gpt2 real bos/eos 0/1");
  sum = sum + check_encode(&v, " hi", &want1(4), "gpt2 real encode ' hi' -> id 4");
  sum = sum + check_encode(&v, "hi", &want1(2), "gpt2 real encode hi -> id 2");
  sum = sum + check_encode(&v, str_of_bytes(&want2(195, 169)), &want1(7), "gpt2 real encode é -> id 7");
  sum = sum + check_decode(&v, &want1(4), " hi", "gpt2 real decode id 4 -> ' hi'");
  let d7 = llm_bpe_decode(&v, &want1(7));
  sum = sum + report(d7.is_ok && str_bytes_eq(d7.value, &want2(195, 169)), "gpt2 real decode id 7 -> é bytes");
  return sum;
}

// t88: the ASCII-safe loader keeps escaped keys verbatim; the real loader
// rejects invalid escaped strings with exact messages.
fn t88() -> Int {
  var sum = 0;
  let buf = gpt2_real_buffer();
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let ar = llm_vocab_from_gguf(&g);
  sum = sum + report(ar.is_ok, "gpt2 ascii-safe loader still accepts header");
  if ar.is_ok {
    let av = ar.value;
    let t3 = llm_vocab_token(&av, 3);
    sum = sum + report(t3.is_ok && str_bytes_eq(t3.value, &want2(196, 160)), "gpt2 ascii-safe loader keeps escaped C4 A0");
  } else {
    sum = sum + report(false, "gpt2 ascii-safe loader result");
  }

  // A literal space token is not a valid escaped GPT-2 vocabulary string.
  var bad_tokens = Vec[Str].new();
  bad_tokens.push(" ");
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &bad_tokens);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &Vec[Str].new());
  let fr = gguf_builder_finish(&b);
  let br = gguf_parse(&fr.value);
  let bg = br.value;
  sum = sum + expect_vocab_err(llm_gpt2_vocab_from_gguf(&bg), "llm: codepoint not in gpt2 byte map", "gpt2 real literal-space token rejected");

  // Truncated UTF-8 in an escaped token.
  var bad2 = Vec[Str].new();
  bad2.push(str_of_bytes(&want1(196)));
  var b2 = gguf_builder_new();
  let c1 = gguf_builder_add_kv_str(&mut b2, "tokenizer.ggml.model", "gpt2");
  let c2 = gguf_builder_add_kv_arr_str(&mut b2, "tokenizer.ggml.tokens", &bad2);
  let c3 = gguf_builder_add_kv_arr_str(&mut b2, "tokenizer.ggml.merges", &Vec[Str].new());
  let fr2 = gguf_builder_finish(&b2);
  let br2 = gguf_parse(&fr2.value);
  let bg2 = br2.value;
  sum = sum + expect_vocab_err(llm_gpt2_vocab_from_gguf(&bg2), "llm: invalid utf8", "gpt2 real truncated utf8 token rejected");
  return sum;
}

// t89: non-integer BOS/EOS insertion flags fail closed with exact messages.
fn t89() -> Int {
  var sum = 0;
  let empty = Vec[Str].new();

  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "gpt2");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &empty);
  let a3 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.merges", &empty);
  let a4 = gguf_builder_add_kv_float(&mut b, "tokenizer.ggml.add_bos_token", 6, "0000803f");
  let fr = gguf_builder_finish(&b);
  let pr = gguf_parse(&fr.value);
  let g = pr.value;
  sum = sum + expect_vocab_err(llm_gpt2_vocab_from_gguf(&g), "llm: add_bos token flag is not an integer", "add_bos non-integer flag rejected");

  var b2 = gguf_builder_new();
  let c1 = gguf_builder_add_kv_str(&mut b2, "tokenizer.ggml.model", "llama");
  let c2 = gguf_builder_add_kv_arr_str(&mut b2, "tokenizer.ggml.tokens", &empty);
  let c3 = gguf_builder_add_kv_str(&mut b2, "tokenizer.ggml.add_eos_token", "yes");
  let fr2 = gguf_builder_finish(&b2);
  let pr2 = gguf_parse(&fr2.value);
  let g2 = pr2.value;
  sum = sum + expect_spm_err(llm_spm_vocab_from_gguf(&g2), "llm: add_eos token flag is not an integer", "add_eos non-integer flag rejected");
  return sum;
}

// t90: the package-local benchmark entry (bench/bench_llm.xi) type-checks.
// The suite imports the module (so every harness function is type-checked)
// and calls the compile/link marker only -- no iterations run here.
fn t90() -> Int {
  let rows = bench_smoke();
  return report(rows == 4, "bench entry type-checks (4 rows, no iterations)");
}

// --------------------------------------------------
//  WPM ("bert") tokenizer core (t94-t100)
// --------------------------------------------------

// Synthetic WordPiece vocabulary. Ids: 0 [UNK], 1 [CLS], 2 [SEP], 3 hello,
// 4 world, 5 he, 6 ##llo, 7 ##lo, 8 caf, 9 ##é (C3 A9), 10 é (C3 A9),
// 11 a, 12 ##b, 13 ##c, 14 abc, 15 ##s, 16 z, 17 ##d, 18 +, 19 ##+.
// The continuations make greedy longest-match distinction observable:
// "hello" must prefer id 3 over [5, 6], and "hellos" must use [3, 15].
fn wpm_tokens_with_first(first: Str) -> Vec[Str] {
  var t = Vec[Str].new();
  t.push(first);                               // 0
  t.push("[CLS]");                             // 1
  t.push("[SEP]");                             // 2
  t.push("hello");                             // 3
  t.push("world");                             // 4
  t.push("he");                                // 5
  t.push("##llo");                             // 6
  t.push("##lo");                              // 7
  t.push("caf");                               // 8
  t.push(str_of_bytes(&want4(35, 35, 195, 169)));  // 9 ##é
  t.push(str_of_bytes(&want2(195, 169)));      // 10 é
  t.push("a");                                 // 11
  t.push("##b");                               // 12
  t.push("##c");                               // 13
  t.push("abc");                               // 14
  t.push("##s");                               // 15
  t.push("z");                                 // 16
  t.push("##d");                               // 17
  t.push("+");                                 // 18
  t.push("##+");                               // 19
  return t;
}

fn wpm_tokens() -> Vec[Str] {
  return wpm_tokens_with_first("[UNK]");
}

fn wpm_tokens_no_unk() -> Vec[Str] {
  return wpm_tokens_with_first("[PAD]");
}

// Token types: 2 (unknown) for [UNK]/[PAD], 3 (control) for [CLS]/[SEP],
// 1 (normal) for every other id.
fn wpm_types() -> Vec[Int] {
  var t = Vec[Int].new();
  t.push(2);
  t.push(3);
  t.push(3);
  var i = 3;
  while i < 20 {
    t.push(1);
    i = i + 1;
  }
  return t;
}

fn wpm_gguf(with_unk: Int, with_flags: Int) -> Vec[UInt8] {
  var toks = wpm_tokens();
  if with_unk == 0 {
    toks = wpm_tokens_no_unk();
  }
  let types = wpm_types();
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "bert");
  let a2 = gguf_builder_add_kv_arr_str(&mut b, "tokenizer.ggml.tokens", &toks);
  let a3 = gguf_builder_add_kv_arr_int(&mut b, "tokenizer.ggml.token_type", 5, &types);
  if with_flags != 0 {
    let a4 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.bos_token_id", 4, 1);
    let a5 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.eos_token_id", 4, 2);
    let a6 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.add_bos_token", 4, 1);
    let a7 = gguf_builder_add_kv_int(&mut b, "tokenizer.ggml.add_eos_token", 4, 1);
  }
  let fr = gguf_builder_finish(&b);
  return fr.value;
}

fn wpm_vocab(with_unk: Int, with_flags: Int) -> LlmWpmVocab {
  let buf = wpm_gguf(with_unk, with_flags);
  let pr = gguf_parse(&buf);
  let g = pr.value;
  let vr = llm_wpm_vocab_from_gguf(&g);
  return vr.value;
}

fn expect_wpm_err(r: Result[LlmWpmVocab, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn check_wpm_encode(v: &LlmWpmVocab, text: Str, want: &Vec[Int], name: Str) -> Int {
  let r = llm_wpm_encode(v, text);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got_ids: Vec[Int] = r.value;
  return report(ids_eq(&got_ids, want), name);
}

fn check_wpm_wordpiece(v: &LlmWpmVocab, word: Str, want: &Vec[Int], name: Str) -> Int {
  let r = llm_wpm_wordpiece(v, word);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got_ids: Vec[Int] = r.value;
  return report(ids_eq(&got_ids, want), name);
}

// ASCII bytes of `s` as an Int vector (decode expectations).
fn ascii_ints(s: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    out.push((string.byte_at(s, i) as Int) & 0xFF);
    i = i + 1;
  }
  return out;
}

fn check_wpm_decode_bytes(v: &LlmWpmVocab, ids: &Vec[Int], want: &Vec[Int], name: Str) -> Int {
  let r = llm_wpm_decode(v, ids);
  if !r.is_ok {
    let got: Str = r.error;
    return report(false, name + " (Err: " + got + ")");
  }
  let got: Str = r.value;
  return report(str_bytes_eq(got, want), name);
}

// t94: WPM extraction/accessors over the synthetic bert fixture.
fn t94() -> Int {
  let v = wpm_vocab(1, 0);
  var sum = 0;
  let model = llm_wpm_model(&v);
  sum = sum + report(str_eq(model, "bert"), "wpm model bert");
  sum = sum + report(llm_wpm_size(&v) == 20, "wpm size 20");
  let t3 = llm_wpm_token(&v, 3);
  sum = sum + report(t3.is_ok && str_eq(t3.value, "hello"), "wpm token 3 = hello");
  let t6 = llm_wpm_token(&v, 6);
  sum = sum + report(t6.is_ok && str_eq(t6.value, "##llo"), "wpm token 6 = ##llo continuation");
  let t9 = llm_wpm_token(&v, 9);
  sum = sum + report(t9.is_ok && str_bytes_eq(t9.value, &want4(35, 35, 195, 169)), "wpm token 9 = ##é bytes 23 23 C3 A9");
  sum = sum + report(llm_wpm_unk(&v) == 0, "wpm unk id 0");
  sum = sum + report(llm_wpm_find_token(&v, "##llo") == 6, "wpm find ##llo = 6");
  sum = sum + report(llm_wpm_find_token(&v, str_of_bytes(&want4(35, 35, 195, 169))) == 9, "wpm find ##é = 9");
  sum = sum + report(llm_wpm_find_token(&v, "zz") == -1, "wpm find miss = -1");
  let tt0 = llm_wpm_token_type(&v, 0);
  let tt1 = llm_wpm_token_type(&v, 1);
  let tt3 = llm_wpm_token_type(&v, 3);
  sum = sum + report(tt0.is_ok && tt0.value == 2, "wpm token_type 0 = unknown");
  sum = sum + report(tt1.is_ok && tt1.value == 3, "wpm token_type 1 = control");
  sum = sum + report(tt3.is_ok && tt3.value == 1, "wpm token_type 3 = normal");
  sum = sum + report(llm_wpm_bos(&v) == -1 && llm_wpm_eos(&v) == -1, "wpm bos/eos absent -1");
  sum = sum + report(llm_wpm_add_bos(&v) == 0 && llm_wpm_add_eos(&v) == 0, "wpm flags absent 0");
  let t20 = llm_wpm_token(&v, 20);
  let tt99 = llm_wpm_token_type(&v, -1);
  sum = sum + expect_str_err(t20, "llm: token index out of range", "wpm token 20 rejected");
  sum = sum + expect_int_err(tt99, "llm: token index out of range", "wpm token_type -1 rejected");
  return sum;
}

// t95: greedy longest-match-prefix with the ## continuation convention.
fn t95() -> Int {
  let v = wpm_vocab(1, 0);
  var sum = 0;
  sum = sum + check_wpm_wordpiece(&v, "hello", &want1(3), "wpm greedy hello -> hello (not he + ##llo)");
  sum = sum + check_wpm_wordpiece(&v, "hellos", &want2(3, 15), "wpm hellos -> hello + ##s");
  sum = sum + check_wpm_wordpiece(&v, "he", &want1(5), "wpm he -> he");
  sum = sum + check_wpm_wordpiece(&v, "abc", &want1(14), "wpm abc -> abc (longest)");
  sum = sum + check_wpm_wordpiece(&v, "z", &want1(16), "wpm z -> z");
  sum = sum + check_wpm_wordpiece(&v, "q", &want1(0), "wpm unknown q -> [UNK]");
  sum = sum + check_wpm_wordpiece(&v, "abcq", &want1(0), "wpm partial match then miss -> whole [UNK]");
  sum = sum + check_wpm_wordpiece(&v, "a+b", &want3(11, 19, 12), "wpm a+b -> a ##+ ##b (no punctuation split)");
  sum = sum + check_wpm_wordpiece(&v, "", &Vec[Int].new(), "wpm empty word -> []");
  let cafe = "caf" + str_of_bytes(&want2(195, 169));
  sum = sum + check_wpm_wordpiece(&v, cafe, &want2(8, 9), "wpm café -> caf + ##é (multi-byte codepoint)");
  sum = sum + check_wpm_wordpiece(&v, str_of_bytes(&want2(195, 169)), &want1(10), "wpm é -> é (single multi-byte token)");
  return sum;
}

// t96: whitespace splitting + BOS/EOS flags.
fn t96() -> Int {
  let v = wpm_vocab(1, 0);
  var sum = 0;
  sum = sum + check_wpm_encode(&v, "", &Vec[Int].new(), "wpm encode empty");
  sum = sum + check_wpm_encode(&v, "hello world", &want2(3, 4), "wpm encode hello world");
  sum = sum + check_wpm_encode(&v, "  hello   world  ", &want2(3, 4), "wpm encode collapses separators");
  sum = sum + check_wpm_encode(&v, "he hello", &want2(5, 3), "wpm encode he hello");
  let cafe = "caf" + str_of_bytes(&want2(195, 169));
  sum = sum + check_wpm_encode(&v, "hello " + cafe, &want3(3, 8, 9), "wpm encode hello café");
  sum = sum + check_wpm_encode(&v, "a+b", &want3(11, 19, 12), "wpm encode a+b stays one word");

  let fv = wpm_vocab(1, 1);
  sum = sum + report(llm_wpm_add_bos(&fv) == 1 && llm_wpm_add_eos(&fv) == 1, "wpm flags read 1/1");
  sum = sum + report(llm_wpm_bos(&fv) == 1 && llm_wpm_eos(&fv) == 2, "wpm flagged bos/eos 1/2");
  sum = sum + check_wpm_encode(&fv, "hello", &want3(1, 3, 2), "wpm encode inserts BOS/EOS");
  sum = sum + check_wpm_encode(&fv, "", &want2(1, 2), "wpm empty text still gets BOS/EOS");
  return sum;
}

// t97: decode (space join + ## attach), multi-byte bytes, roundtrip, errors.
fn t97() -> Int {
  let v = wpm_vocab(1, 0);
  var sum = 0;
  sum = sum + check_wpm_decode_bytes(&v, &Vec[Int].new(), &Vec[Int].new(), "wpm decode [] = empty");
  sum = sum + check_wpm_decode_bytes(&v, &want2(3, 4), &ascii_ints("hello world"), "wpm decode [3,4] = hello world");
  sum = sum + check_wpm_decode_bytes(&v, &want2(3, 15), &ascii_ints("hellos"), "wpm decode [3,15] attaches ##s");
  sum = sum + check_wpm_decode_bytes(&v, &want3(11, 19, 12), &want3(97, 43, 98), "wpm decode a+b");
  let cafe_ids = want2(8, 9);
  sum = sum + check_wpm_decode_bytes(&v, &cafe_ids, &want5(99, 97, 102, 195, 169), "wpm decode café bytes");
  sum = sum + check_wpm_decode_bytes(&v, &want1(10), &want2(195, 169), "wpm decode é bytes");
  sum = sum + expect_str_err(llm_wpm_decode(&v, &want1(20)), "llm: token id out of range", "wpm decode id 20 rejected");
  sum = sum + expect_str_err(llm_wpm_decode(&v, &want1(-1)), "llm: token id out of range", "wpm decode id -1 rejected");

  let cafe = "caf" + str_of_bytes(&want2(195, 169));
  var texts = Vec[Str].new();
  texts.push("hello world");
  texts.push("hellos");
  texts.push("he hello");
  texts.push(cafe);
  texts.push("a+b");
  var rt_ok = true;
  var i = 0;
  while i < texts.len() {
    let tx: Str = texts[i];
    let er = llm_wpm_encode(&v, tx);
    if !er.is_ok {
      rt_ok = false;
    } else {
      let idsv: Vec[Int] = er.value;
      let dr = llm_wpm_decode(&v, &idsv);
      if !dr.is_ok {
        rt_ok = false;
      } else {
        let gotb = str_u8v(dr.value);
        let wantb = str_u8v(tx);
        if !bytes_eq(&gotb, &wantb) {
          rt_ok = false;
        }
      }
    }
    i = i + 1;
  }
  sum = sum + report(rt_ok, "wpm encode/decode roundtrip (5 texts, incl multi-byte)");

  let fv = wpm_vocab(1, 1);
  sum = sum + check_wpm_decode_bytes(&fv, &want3(1, 3, 2), &ascii_ints("[CLS] hello [SEP]"), "wpm decode specials join with spaces");
  return sum;
}

// t98: extraction error arms.
fn t98() -> Int {
  var sum = 0;
  let gpt2buf = header_plain("gpt2");
  let pr = gguf_parse(&gpt2buf);
  let g = pr.value;
  sum = sum + expect_wpm_err(llm_wpm_vocab_from_gguf(&g), "llm: wpm tokenizer model is not bert", "wpm gpt2 model rejected");

  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_str(&mut b, "tokenizer.ggml.model", "bert");
  let fr = gguf_builder_finish(&b);
  let pr2 = gguf_parse(&fr.value);
  let g2 = pr2.value;
  sum = sum + expect_wpm_err(llm_wpm_vocab_from_gguf(&g2), "llm: tokenizer tokens missing", "wpm tokens missing rejected");

  let toks = wpm_tokens();
  var short_types = Vec[Int].new();
  short_types.push(1);
  short_types.push(1);
  short_types.push(1);
  var b2 = gguf_builder_new();
  let c1 = gguf_builder_add_kv_str(&mut b2, "tokenizer.ggml.model", "bert");
  let c2 = gguf_builder_add_kv_arr_str(&mut b2, "tokenizer.ggml.tokens", &toks);
  let c3 = gguf_builder_add_kv_arr_int(&mut b2, "tokenizer.ggml.token_type", 5, &short_types);
  let fr2 = gguf_builder_finish(&b2);
  let pr3 = gguf_parse(&fr2.value);
  let g3 = pr3.value;
  sum = sum + expect_wpm_err(llm_wpm_vocab_from_gguf(&g3), "llm: token type count smaller than token count", "wpm short token_type rejected");

  var b3 = gguf_builder_new();
  let d1 = gguf_builder_add_kv_str(&mut b3, "tokenizer.ggml.model", "bert");
  let d2 = gguf_builder_add_kv_arr_str(&mut b3, "tokenizer.ggml.tokens", &toks);
  let d3 = gguf_builder_add_kv_str(&mut b3, "tokenizer.ggml.token_type", "normal");
  let fr3 = gguf_builder_finish(&b3);
  let pr4 = gguf_parse(&fr3.value);
  let g4 = pr4.value;
  sum = sum + expect_wpm_err(llm_wpm_vocab_from_gguf(&g4), "llm: token types are not an integer array", "wpm string token_type rejected");
  return sum;
}

// t99: a vocabulary without [UNK] fails closed on an unmatched piece.
fn t99() -> Int {
  let v = wpm_vocab(0, 0);
  var sum = 0;
  sum = sum + report(llm_wpm_unk(&v) == -1, "wpm no-unk fixture unk = -1");
  sum = sum + expect_ids_err(llm_wpm_encode(&v, "q"), "llm: wpm unk token missing", "wpm unknown without [UNK] rejected");
  sum = sum + expect_ids_err(llm_wpm_wordpiece(&v, "abcq"), "llm: wpm unk token missing", "wpm partial without [UNK] rejected");
  return sum;
}

// t100: WPM is normalization-free (SPEC unpinned): case and accents are
// preserved, so uppercase "HELLO" does not match the lowercase token.
fn t100() -> Int {
  let v = wpm_vocab(1, 0);
  var sum = 0;
  sum = sum + check_wpm_encode(&v, "hello", &want1(3), "wpm lowercase matches");
  sum = sum + check_wpm_encode(&v, "HELLO", &want1(0), "wpm uppercase not normalized -> [UNK]");
  let cafe_upper = "CAF" + str_of_bytes(&want2(195, 169));
  sum = sum + check_wpm_encode(&v, cafe_upper, &want1(0), "wpm accent/case normalization not applied");
  return sum;
}

// --------------------------------------------------
//  Main
// --------------------------------------------------
fn main() -> Int {
  var failed = 0;
  failed = failed + t1();
  failed = failed + t2();
  failed = failed + t3();
  failed = failed + t4();
  failed = failed + t5();
  failed = failed + t6();
  failed = failed + t7();
  failed = failed + t8();
  failed = failed + t9();
  failed = failed + t10();
  failed = failed + t11();
  failed = failed + t12();
  failed = failed + t13();
  failed = failed + t14();
  failed = failed + t15();
  failed = failed + t16();
  failed = failed + t17();
  failed = failed + t18();
  failed = failed + t19();
  failed = failed + t20();
  failed = failed + t21();
  failed = failed + t22();
  failed = failed + t23();
  failed = failed + t24();
  failed = failed + t25();
  failed = failed + t26();
  failed = failed + t27();
  failed = failed + t28();
  failed = failed + t29();
  failed = failed + t30();
  failed = failed + t31();
  failed = failed + t32();
  failed = failed + t33();
  failed = failed + t34();
  failed = failed + t35();
  failed = failed + t36();
  failed = failed + t37();
  failed = failed + t38();
  failed = failed + t39();
  failed = failed + t40();
  failed = failed + t41();
  failed = failed + t42();
  failed = failed + t43();
  failed = failed + t44();
  failed = failed + t45();
  failed = failed + t46();
  failed = failed + t47();
  failed = failed + t48();
  failed = failed + t49();
  failed = failed + t50();
  failed = failed + t51();
  failed = failed + t52();
  failed = failed + t53();
  failed = failed + t54();
  failed = failed + t55();
  failed = failed + t56();
  failed = failed + t57();
  failed = failed + t58();
  failed = failed + t59();
  failed = failed + t60();
  failed = failed + t61();
  failed = failed + t62();
  failed = failed + t63();
  failed = failed + t64();
  failed = failed + t65();
  failed = failed + t66();
  failed = failed + t67();
  failed = failed + t68();
  failed = failed + t69();
  failed = failed + t70();
  failed = failed + t71();
  failed = failed + t72();
  failed = failed + t73();
  failed = failed + t74();
  failed = failed + t75();
  failed = failed + t76();
  failed = failed + t77();
  failed = failed + t78();
  failed = failed + t79();
  failed = failed + t80();
  failed = failed + t81();
  failed = failed + t82();
  failed = failed + t83();
  failed = failed + t84();
  failed = failed + t85();
  failed = failed + t86();
  failed = failed + t87();
  failed = failed + t88();
  failed = failed + t89();
  failed = failed + t90();
  failed = failed + t91();
  failed = failed + t92();
  failed = failed + t93();
  failed = failed + t94();
  failed = failed + t95();
  failed = failed + t96();
  failed = failed + t97();
  failed = failed + t98();
  failed = failed + t99();
  failed = failed + t100();
  if failed == 0 {
    io.println("xiom.llm: all tests passed");
  }
  return failed;
}
