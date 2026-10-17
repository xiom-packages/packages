// XIOM -- xiom.llm benchmark harness (offline, deterministic shape)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Package-local bench entry, runnable off-suite:
//
//   xiom --run bench/bench_llm.xi
//   XIOM_LLM_BENCH_ITERS=5000 xiom --run bench/bench_llm.xi
//
// It measures prefill / decode token throughput over the existing tiny
// deterministic model fixture and encode throughput for the existing SPM and
// GPT-2 fixture vocabularies. No network, no external model files, no float
// arithmetic. The output is a fixed set of rows with integer fields:
//
//   <row>: ops=<n> total_ns=<n> ops_per_sec=<n> checksum=<n>
//
// Absolute numbers are machine-dependent; use the harness for relative
// tracking between runs on the same machine. The monotonic clock used by
// `xiom.time` has millisecond resolution, so each row times a whole batch of
// operations (the caller-supplied iteration count) rather than one operation.
//
// The module is imported by `tests/test_conformance.xi` (marker t90) so the
// conformance suite type-checks this entry without running any iterations.

module bench.llm_bench

use xiom.io;
use xiom.convert;
use xiom.convert.atoi;
use xiom.string;
use xiom.string.builder;
use xiom.gguf;
use xiom.llm;
use xiom.time;
use xiom.os.args;
use xiom.os.env;

// Caller-supplied iteration count: `XIOM_LLM_BENCH_ITERS` (environment) or
// `--iters N` / `--iters=N` when the bench binary is executed directly.
const BENCH_DEFAULT_ITERS: Int = 1000;

// Bounded KV window: the decode row appends one position per iteration, so
// the cap keeps the append-only cache (and the O(n^2) attention work) small.
const BENCH_MAX_ITERS: Int = 4096;

const BENCH_ROW_COUNT: Int = 4;

/// One benchmark row. Mirrors the `xiom.bench.BenchResult` naming
/// (iterations/mean/total) but adds the operation count and a deterministic
/// checksum so the optimizer cannot elide the measured work.
pub type BenchRow = {
  name: Str;
  ops: Int;
  total_ns: Int;
  ops_per_sec: Int;
  checksum: Int;
}

/// Compile/link marker used by the conformance suite (no iterations run).
pub fn bench_smoke() -> Int {
  return BENCH_ROW_COUNT;
}

// --------------------------------------------------
//  Tiny deterministic model fixture (same shape as the suite):
//  emb=4, heads=1, vocab=20, ffn=8, 1 layer, 11 tensors.
// --------------------------------------------------

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

fn push_f32(dst: &mut Vec[UInt8], n: Int) -> Int {
  let bits = f32_bits_of_int(n);
  dst.push(((bits & 0xFF) as UInt8));
  dst.push((((bits >> 8) & 0xFF) as UInt8));
  dst.push((((bits >> 16) & 0xFF) as UInt8));
  dst.push((((bits >> 24) & 0xFF) as UInt8));
  return 0;
}

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

// Q8_0 block bytes inside an f32-declared 128-byte slice (the documented
// builder deviation; `llm_dequant_q8_0` reads the leading 34 bytes).
fn push_q8_padded(dst: &mut Vec[UInt8], quants: &Vec[Int]) -> Int {
  let a = push_q8_scale1(dst, quants);
  var pad = 0;
  while pad < 94 {
    dst.push((0 as UInt8));
    pad = pad + 1;
  }
  return 0;
}

fn vocab_tokens() -> Vec[Str] {
  var t = Vec[Str].new();
  t.push("h");
  t.push("e");
  t.push("l");
  t.push("o");
  t.push("w");
  t.push("r");
  t.push("d");
  t.push(" ");
  t.push("!");
  t.push("he");
  t.push("ll");
  t.push("hell");
  t.push("hello");
  t.push("wo");
  t.push("wor");
  t.push("worl");
  t.push("world");
  t.push("lo");
  t.push("<s>");
  t.push("</s>");
  return t;
}

fn vocab_merges() -> Vec[Str] {
  var m = Vec[Str].new();
  m.push("h e");
  m.push("l l");
  m.push("he ll");
  m.push("hell o");
  m.push("w o");
  m.push("wo r");
  m.push("wor l");
  m.push("worl d");
  m.push("l o");
  m.push("q");
  return m;
}

fn vocab_types() -> Vec[Int] {
  var t = Vec[Int].new();
  var i = 0;
  while i < 18 {
    t.push(1);
    i = i + 1;
  }
  t.push(3);
  t.push(3);
  return t;
}

// Model container: rows 0 and 1 of token_embd are [4,4,0,0], all other rows
// zero. Both forwardable tokens therefore produce the same q/k/v (valid for
// multi-position cached forwards).
fn model_container() -> Vec[UInt8] {
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

  var r = 0;
  while r < 20 {
    var c = 0;
    while c < 4 {
      var ev = 0;
      if r == 0 || r == 1 {
        if c == 0 {
          ev = 4;
        } else if c == 1 {
          ev = 4;
        }
      }
      let z = push_f32(&mut buf, ev);
      c = c + 1;
    }
    r = r + 1;
  }
  var i2 = 0;
  while i2 < 4 {
    let z3 = push_f32(&mut buf, 1);
    i2 = i2 + 1;
  }
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
  var rw = 0;
  while rw < 4 {
    let z8 = push_f32(&mut buf, -1);
    let z9 = push_f32(&mut buf, 0);
    let z10 = push_f32(&mut buf, 0);
    let z11 = push_f32(&mut buf, 0);
    rw = rw + 1;
  }
  var i3 = 0;
  while i3 < 4 {
    let z12 = push_f32(&mut buf, 1);
    i3 = i3 + 1;
  }
  var qg = Vec[Int].new();
  var rg = 0;
  while rg < 8 {
    qg.push(4); qg.push(1); qg.push(0); qg.push(0);
    rg = rg + 1;
  }
  let g8 = push_q8_padded(&mut buf, &qg);
  var qu = Vec[Int].new();
  var ru = 0;
  while ru < 8 {
    qu.push(0); qu.push(0); qu.push(1); qu.push(1);
    ru = ru + 1;
  }
  let g9 = push_q8_padded(&mut buf, &qu);
  var qd = Vec[Int].new();
  var rd = 0;
  while rd < 4 {
    qd.push(1); qd.push(0); qd.push(0); qd.push(0);
    qd.push(0); qd.push(0); qd.push(0); qd.push(0);
    rd = rd + 1;
  }
  let g10 = push_q8_padded(&mut buf, &qd);
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

// --------------------------------------------------
//  Tokenizer fixtures (same vocabularies as the suite)
// --------------------------------------------------

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

fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a); v.push(b);
  return v;
}

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a); v.push(b); v.push(c);
  return v;
}

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a); v.push(b); v.push(c); v.push(d);
  return v;
}

fn v5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a); v.push(b); v.push(c); v.push(d); v.push(e);
  return v;
}

fn str_of_bytes(vals: &Vec[Int]) -> Str {
  let raw = u8v(vals);
  return builder.sb_to_str(&raw);
}

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

fn gpt2_real_tokens() -> Vec[Str] {
  var t = Vec[Str].new();
  t.push("h");
  t.push("i");
  t.push("hi");
  t.push(str_of_bytes(&v2(196, 160)));
  t.push(str_of_bytes(&v4(196, 160, 104, 105)));
  t.push(str_of_bytes(&v2(195, 131)));
  t.push(str_of_bytes(&v2(194, 169)));
  t.push(str_of_bytes(&v4(195, 131, 194, 169)));
  return t;
}

fn gpt2_real_merges() -> Vec[Str] {
  var m = Vec[Str].new();
  m.push(str_of_bytes(&v3(196, 160, 32)) + "h");
  m.push("h i");
  m.push(str_of_bytes(&v3(196, 160, 104)) + " i");
  m.push(str_of_bytes(&v3(195, 131, 32)) + str_of_bytes(&v2(194, 169)));
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

fn spm_real_tokens() -> Vec[Str] {
  var t = Vec[Str].new();
  t.push("a");
  t.push("b");
  t.push("c");
  t.push("ab");
  t.push(str_of_bytes(&v3(226, 150, 129)));
  t.push(str_of_bytes(&v4(226, 150, 129, 97)));
  t.push(str_of_bytes(&v5(226, 150, 129, 97, 98)));
  t.push(str_of_bytes(&v2(195, 169)));
  t.push("<0x7A>");
  t.push("<s>");
  t.push("</s>");
  return t;
}

fn spm_real_score_bits() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(3212836864);
  v.push(3212836864);
  v.push(3212836864);
  v.push(3240099840);
  v.push(3231711232);
  v.push(3221225472);
  v.push(3212836864);
  v.push(3225419776);
  v.push(3248488448);
  v.push(3267887104);
  v.push(3267887104);
  return v;
}

fn raw_spm_real_gguf(tokens: &Vec[Str], bits: &Vec<Int>) -> Vec[UInt8] {
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
  wu64(out, bits.len());
  var k = 0;
  while k < bits.len() {
    let b: Int = bits[k];
    wu32(out, b);
    k = k + 1;
  }
  while out.len() % 32 != 0 {
    out.push((0 as UInt8));
  }
  return out;
}

// --------------------------------------------------
//  Measurement helpers
// --------------------------------------------------

fn ops_per_sec(ops: Int, total_ns: Int) -> Int {
  if ops <= 0 || total_ns <= 0 {
    return 0;
  }
  return ops * 1000000000 / total_ns;
}

fn make_row(name: Str, ops: Int, total_ns: Int, checksum: Int) -> BenchRow {
  return BenchRow{
    name: name;
    ops: ops;
    total_ns: total_ns;
    ops_per_sec: ops_per_sec(ops, total_ns);
    checksum: checksum;
  };
}

// Identity RoPE table (cos=1.0, sin=0) for every position in `cap`.
fn identity_tables(cap: Int) -> Vec[Int] {
  var tab = Vec[Int].new();
  var i = 0;
  while i < cap * 2 {
    tab.push(1 << 12);
    i = i + 1;
  }
  return tab;
}

fn identity_sin(cap: Int) -> Vec[Int] {
  var tab = Vec[Int].new();
  var i = 0;
  while i < cap * 2 {
    tab.push(0);
    i = i + 1;
  }
  return tab;
}

// Prefill: one iteration builds a fresh 2-position cache and forwards the
// two-token prompt (tokens 0 and 1), i.e. two token operations per iteration.
fn bench_prefill(model: &LlmModel, buf: &Vec[UInt8], iters: Int) -> BenchRow {
  let cos = identity_tables(2);
  let sin = identity_sin(2);
  var checksum = 0;
  let start = time.Instant.now();
  var i = 0;
  while i < iters {
    var c = llm_kv_cache_new(1, 4, 2);
    let r0 = llm_forward_cache(model, buf, 0, &cos, &sin, 12, &mut c);
    if !r0.is_ok {
      return make_row("prefill", 0, 0, 0);
    }
    let l0: Vec[Int] = r0.value;
    let x0: Int = l0[0] + l0[19];
    checksum = checksum + x0;
    let r1 = llm_forward_cache(model, buf, 1, &cos, &sin, 12, &mut c);
    if !r1.is_ok {
      return make_row("prefill", 0, 0, 0);
    }
    let l1: Vec[Int] = r1.value;
    let x1: Int = l1[0] + l1[19];
    checksum = checksum + x1;
    i = i + 1;
  }
  let d = start.elapsed();
  return make_row("prefill", iters * 2, d.as_nanos(), checksum);
}

// Decode: prefill the two-token prompt once, then append one token per
// iteration into a bounded append-only cache. One operation per iteration.
fn bench_decode(model: &LlmModel, buf: &Vec<UInt8>, iters: Int) -> BenchRow {
  let cap = iters + 2;
  let cos = identity_tables(cap);
  let sin = identity_sin(cap);
  var c = llm_kv_cache_new(1, 4, cap);
  let p0 = llm_forward_cache(model, buf, 0, &cos, &sin, 12, &mut c);
  if !p0.is_ok {
    return make_row("decode", 0, 0, 0);
  }
  let p1 = llm_forward_cache(model, buf, 1, &cos, &sin, 12, &mut c);
  if !p1.is_ok {
    return make_row("decode", 0, 0, 0);
  }
  var checksum = 0;
  let start = time.Instant.now();
  var i = 0;
  while i < iters {
    let tok = i % 2;
    let r = llm_forward_cache(model, buf, tok, &cos, &sin, 12, &mut c);
    if !r.is_ok {
      return make_row("decode", 0, 0, 0);
    }
    let logits: Vec[Int] = r.value;
    let x: Int = logits[0] + logits[19];
    checksum = checksum + x;
    i = i + 1;
  }
  let d = start.elapsed();
  return make_row("decode", iters, d.as_nanos(), checksum);
}

// SPM encode throughput on a fixed text (eight " ab" pieces -> ids 6).
fn bench_spm_encode(iters: Int) -> BenchRow {
  let tokens = spm_real_tokens();
  let bits = spm_real_score_bits();
  let buf = raw_spm_real_gguf(&tokens, &bits);
  let pr = gguf_parse(&buf);
  if !pr.is_ok {
    return make_row("tokenizer.spm.encode", 0, 0, 0);
  }
  let g = pr.value;
  let vr = llm_spm_vocab_from_gguf(&g);
  if !vr.is_ok {
    return make_row("tokenizer.spm.encode", 0, 0, 0);
  }
  let v = vr.value;
  let text = " ab ab ab ab ab ab ab ab";
  var checksum = 0;
  let start = time.Instant.now();
  var i = 0;
  while i < iters {
    let r = llm_spm_encode(&v, text);
    if !r.is_ok {
      return make_row("tokenizer.spm.encode", 0, 0, 0);
    }
    let ids: Vec[Int] = r.value;
    let x: Int = ids[0];
    checksum = checksum + x;
    i = i + 1;
  }
  let d = start.elapsed();
  return make_row("tokenizer.spm.encode", iters, d.as_nanos(), checksum);
}

// GPT-2 BPE encode throughput on a fixed text (eight " hi" pieces -> id 4).
fn bench_gpt2_encode(iters: Int) -> BenchRow {
  let buf = gpt2_real_buffer();
  let pr = gguf_parse(&buf);
  if !pr.is_ok {
    let pe: Str = pr.error;
    io.println("bench: gpt2 parse: " + pe);
    return make_row("tokenizer.gpt2.encode", 0, 0, 0);
  }
  let g = pr.value;
  let vr = llm_gpt2_vocab_from_gguf(&g);
  if !vr.is_ok {
    let ve: Str = vr.error;
    io.println("bench: gpt2 vocab: " + ve);
    return make_row("tokenizer.gpt2.encode", 0, 0, 0);
  }
  let v = vr.value;
  let text = " hi hi hi hi hi hi hi hi";
  var checksum = 0;
  let start = time.Instant.now();
  var i = 0;
  while i < iters {
    let r = llm_bpe_encode(&v, text);
    if !r.is_ok {
      let re: Str = r.error;
      io.println("bench: gpt2 encode: " + re);
      return make_row("tokenizer.gpt2.encode", 0, 0, 0);
    }
    let ids: Vec[Int] = r.value;
    let x: Int = ids[0];
    checksum = checksum + x;
    i = i + 1;
  }
  let d = start.elapsed();
  return make_row("tokenizer.gpt2.encode", iters, d.as_nanos(), checksum);
}

// --------------------------------------------------
//  Reporting
// --------------------------------------------------

fn row_line(r: &BenchRow) -> Str {
  return r.name + ": ops=" + convert.int_to_string(r.ops)
    + " total_ns=" + convert.int_to_string(r.total_ns)
    + " ops_per_sec=" + convert.int_to_string(r.ops_per_sec)
    + " checksum=" + convert.int_to_string(r.checksum);
}

fn resolve_iters() -> Int {
  var raw = env.var_or("XIOM_LLM_BENCH_ITERS", convert.int_to_string(BENCH_DEFAULT_ITERS));
  let argv = args.args_raw();
  match args.option_value(&argv, "--iters") {
    Some(v) => { raw = v; }
    None => {}
  }
  var iters = atoi.atoi_or(raw, BENCH_DEFAULT_ITERS);
  if iters < 0 {
    iters = 0;
  }
  if iters > BENCH_MAX_ITERS {
    iters = BENCH_MAX_ITERS;
  }
  return iters;
}

/// Run the bench. Returns 0 on success, 2 when the model fixture cannot be
/// opened, 3 when a tokenizer fixture cannot be built.
pub fn bench_main() -> Int {
  let iters = resolve_iters();
  io.println("xiom.llm bench: fixture=tiny-gpt2 emb=4 heads=1 layers=1 vocab=20 iterations=" + convert.int_to_string(iters));

  let buf = model_container();
  var empty = Vec[UInt8].new();
  let mr = llm_model_open(&buf, &empty);
  if !mr.is_ok {
    let e: Str = mr.error;
    io.println("bench: error: " + e);
    return 2;
  }
  let model: LlmModel = mr.value;

  let prefill = bench_prefill(&model, &buf, iters);
  let decode = bench_decode(&model, &buf, iters);
  let spm = bench_spm_encode(iters);
  let gpt2 = bench_gpt2_encode(iters);

  if prefill.ops == 0 && iters > 0 {
    io.println("bench: error: prefill fixture failed");
    return 2;
  }
  if decode.ops == 0 && iters > 0 {
    io.println("bench: error: decode fixture failed");
    return 2;
  }
  if spm.ops == 0 && iters > 0 {
    io.println("bench: error: tokenizer.spm.encode fixture failed");
    return 3;
  }
  if gpt2.ops == 0 && iters > 0 {
    io.println("bench: error: tokenizer.gpt2.encode fixture failed");
    return 3;
  }

  io.println(row_line(&prefill));
  io.println(row_line(&decode));
  io.println(row_line(&spm));
  io.println(row_line(&gpt2));
  io.println("bench: done");
  return 0;
}

fn main() -> Int {
  return bench_main();
}
