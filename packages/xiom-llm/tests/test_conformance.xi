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
fn model_container(w1_first: Int) -> Vec[UInt8] {
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

  // 1. token_embd [20,4] f32: row 1 = [4,4,0,0], all other rows zero.
  var r = 0;
  while r < 20 {
    var c = 0;
    while c < 4 {
      if r == 1 && (c == 0 || c == 1) {
        let z = push_f32(&mut buf, 4);
      } else {
        let z2 = push_f32(&mut buf, 0);
      }
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
  if failed == 0 {
    io.println("xiom.llm: all tests passed");
  }
  return failed;
}
