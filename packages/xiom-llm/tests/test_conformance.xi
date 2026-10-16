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
use xiom.gguf;
use xiom.llm;

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
  if failed == 0 {
    io.println("xiom.llm: all tests passed");
  }
  return failed;
}
