// XIOM -- xiom.llm: llama.cpp-family runner tier (M1: vocab + byte-level BPE)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Milestone 1 of the llama.cpp-family runner tier:
//
//   * extract the tokenizer vocabulary from the metadata of a GGUF header
//     parsed by xiom.gguf (tokenizer.ggml.model / tokens / merges /
//     token_type / bos_token_id / eos_token_id) into a queryable LlmV ocab;
//   * byte-level BPE over that vocabulary with llama.cpp-family semantics
//     (merge-table ranks, decode = token bytes concatenation, encode =
//     repeated min-rank adjacent-pair merge), following llama.cpp
//     src/llama-vocab.cpp at commit 23f7aabc16c72f6f707dba227251c35d7bd1ed96
//     (recorded in SPEC.md; MIT, read-only reference).
//
// Documented M1 subset (see SPEC.md sections 5-6 for the exact rules):
//   * xiom.gguf restricts GGUF strings to printable ASCII (0x20..0x7E), so
//     the vocabulary domain of this milestone is printable ASCII, and the
//     GPT-2 byte-to-unicode escape layer (llama.cpp unicode_byte_to_utf8,
//     which maps byte 0x20 to U+0120 "G-dot", a non-ASCII codepoint) cannot
//     be represented in a parsed GGUF string. M1 therefore treats token
//     strings as raw byte sequences (the fixture stores a literal space
//     token) and defers the escape layer and the regex pre-tokenizer to M3.
//   * merge entries split at the first space at byte index >= 1 exactly as
//     llama.cpp `word.find(' ', 1)`; entries without such a space are dead
//     pairs that still occupy their rank index.
//   * llama.cpp's per-byte fallback for unknown final symbols is replaced by
//     a fail-closed error (documented deviation; see SPEC.md section 8).
//   * string-array elements are read through gguf_kv_arr_str; the temporary
//     XGGUF-ARRSTR parse-offset workaround was removed once xiom.gguf 0.1.3
//     carried the upstream origin fix (element types 6/8/12 now record the
//     arr_strs origin; see SPEC.md section 9, now resolved).
//
// v0.61.3+ compiler notes that shaped this module: free functions only;
// Ok/Err construction is confined to the leaf helpers below; Str values
// read from Vec[Str]/struct fields are bound to typed locals and compared
// with str_compare, never `==`; every UInt8 is widened with `(b as Int) &
// 0xFF`; struct fields are bound to locals before being passed where a
// `&Vec[...]` parameter is expected.

// M2a/M2b additions (2026-10-16): GGML size tables, tensor extent
// validation, integer f16/f32 bit-decode, Q8_0 dequantization and the
// `llm_model_open` composite (M2a); and the integer forward tier -- overflow
// fail-closed `llm_matmul_i32`, `llm_rmsnorm_i32`, `llm_rope_i32`,
// `llm_softmax_i32`, `llm_silu_q`/`llm_swiglu_i32` and `llm_shape_dump`
// (M2b). Each numeric kernel documents its integer error bound; the M2
// fixture is built so every step is exact (golden logits pinned in the
// suite). The M3 first half (M3a) adds the deterministic seeded PRNG,
// sampling (temperature / top-k / top-p), stop-token handling, the
// `llm_forward_token` single-position entry point and the `llm_generate`
// loop (SPEC.md 10.5); the KV cache, longer-context attention, benchmark
// harness and quant breadth (Q4_K etc.) remain for the M3 second half.

module xiom.llm

use xiom.string;
use xiom.string.compare;
use xiom.gguf;
use xiom.tensor;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ids(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ids(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[LlmVocab, Str].
fn _ok_vocab(v: LlmVocab) -> Result[LlmVocab, Str] {
  return Ok(v);
}

// Err(m) for Result[LlmVocab, Str].
fn _err_vocab(m: Str) -> Result[LlmVocab, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[LlmScale, Str].
fn _ok_scale(v: LlmScale) -> Result[LlmScale, Str] {
  return Ok(v);
}

// Err(m) for Result[LlmScale, Str].
fn _err_scale(m: Str) -> Result[LlmScale, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Tokenizer vocabulary extracted from a GGUF header (M1 surface).
///
/// `tokens[i]` is the string of token id `i` (byte buffer as stored in the
/// GGUF metadata; over the M1 printable-ASCII domain this is also the raw
/// decoded byte sequence). `token_types[i]` mirrors the file's
/// `tokenizer.ggml.token_type` array when present, else 1
/// (LLAMA_TOKEN_TYPE_NORMAL, the llama.cpp default); `has_types` is 0/1.
/// `merge_l[i]`/`merge_r[i]` are the two parts of merge entry `i`; its rank
/// is `i`. A merge entry with no space at byte index >= 1 is stored as a
/// dead pair ("", "") that occupies its rank but can never match a symbol
/// pair (llama.cpp `word.find(' ', 1)` semantics). `bos`/`eos` are -1 when
/// the corresponding key is absent.
///
/// Fields are implementation details; use the llm_* accessors. A value is
/// only produced by llm_vocab_from_gguf, so the invariants always hold.
pub type LlmVocab = {
  model: Str;
  tokens: Vec[Str];
  has_types: Int;
  token_types: Vec[Int];
  merge_l: Vec[Str];
  merge_r: Vec[Str];
  bos: Int;
  eos: Int;
}

/// Exact scaled-integer representation of a real number: the value is
/// `m / 2^e` with `m` and `e` plain Ints (no floating point anywhere). A
/// decoded f16/f32 scale or a dequantized tensor block carries one of these;
/// `llm_dequant_q8_0` returns the shared block scale as the pair (m, e) such
/// that the exact real value of output `i` is `out_values[i] / 2^e`.
pub type LlmScale = {
  m: Int;
  e: Int;
}

// --------------------------------------------------
//  Small helpers
// --------------------------------------------------

// True when `s` equals `want` (BUG-17 lowering: never compare Str with ==).
fn _str_is(s: Str, want: Str) -> Bool {
  return compare.str_compare(s, want) == 0;
}

// Byte `pos` of `s` widened to 0..255. Callers bound-check first.
fn _byte_at(s: Str, pos: Int) -> Int {
  let raw: UInt8 = string.byte_at(s, pos);
  return (raw as Int) & 0xFF;
}

// First occurrence of byte `b` in `s` at index >= `from`, else -1.
fn _find_byte(s: Str, b: Int, from: Int) -> Int {
  let n = string.str_len(s);
  var k = from;
  while k < n {
    if _byte_at(s, k) == b {
      return k;
    }
    k = k + 1;
  }
  return -1;
}

// True for GGUF value type codes that read as integers through
// gguf_kv_arr_int (unsigned/signed ints, bool, u64/i64): 0..5, 7, 10, 11.
fn _type_is_integer(t: Int) -> Bool {
  if t >= 0 && t <= 5 {
    return true;
  }
  if t == 7 {
    return true;
  }
  return t == 10 || t == 11;
}

// Last id whose token string equals `s`, else -1. llama.cpp `token_to_id`
// uses map assignment, so a duplicated token string resolves to its
// HIGHEST id; this helper mirrors that overwrite semantics.
fn _find_token_id(v: &LlmVocab, s: Str) -> Int {
  let toks: Vec[Str] = v.tokens;
  var found = -1;
  var i = 0;
  while i < toks.len() {
    let t: Str = toks[i];
    if _str_is(t, s) {
      found = i;
    }
    i = i + 1;
  }
  return found;
}

// Rank (index) of the merge pair (l, r), else -1. Dead pairs never match
// because symbols are always non-empty.
fn _merge_rank(v: &LlmVocab, l: Str, r: Str) -> Int {
  let lefts: Vec[Str] = v.merge_l;
  let rights: Vec[Str] = v.merge_r;
  var i = 0;
  while i < lefts.len() {
    let a: Str = lefts[i];
    let b: Str = rights[i];
    if _str_is(a, l) && _str_is(b, r) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Vocab extraction from a parsed GGUF header
// --------------------------------------------------

// KV lookup that distinguishes "missing" from other errors: returns the
// index or -1, never an Err.
fn _kv_index_or_neg(g: &Gguf, key: Str) -> Int {
  let fr = gguf_find_kv(g, key);
  if fr.is_ok {
    return fr.value;
  }
  return -1;
}

/// Extract the tokenizer vocabulary from a GGUF header parsed by
/// xiom.gguf. Params: g - the parsed header. Returns: the LlmV ocab with
/// tokens, merge table, optional token types and optional bos/eos ids.
/// Semantics mirror llama.cpp src/llama-vocab.cpp (commit 23f7aabc) for
/// `tokenizer.ggml.model == "gpt2"`; any other model string is rejected in
/// M1 (SPM/WPM vocabularies are declared for M3). Error cases (deterministic
/// `llm: ` messages, see SPEC.md section 7): missing or non-string model,
/// unsupported model, missing or non-string-array tokens/merges, non-integer
/// token_type array, token_type count smaller than the token count, bos/eos
/// ids that are not integer values.
pub fn llm_vocab_from_gguf(g: &Gguf) -> Result[LlmVocab, Str] {
  // 1. tokenizer.ggml.model (required string, "gpt2" only in M1).
  let mi = _kv_index_or_neg(g, "tokenizer.ggml.model");
  if mi < 0 {
    return _err_vocab("llm: tokenizer model missing");
  }
  let mt = gguf_kv_type(g, mi);
  if !mt.is_ok || mt.value != 8 {
    return _err_vocab("llm: tokenizer model is not a string");
  }
  let mr = gguf_kv_str(g, mi);
  if !mr.is_ok {
    return _err_vocab("llm: tokenizer model is not a string");
  }
  let model: Str = mr.value;
  if !_str_is(model, "gpt2") {
    return _err_vocab("llm: unsupported tokenizer model");
  }

  // 2. tokenizer.ggml.tokens (required string array).
  let ti = _kv_index_or_neg(g, "tokenizer.ggml.tokens");
  if ti < 0 {
    return _err_vocab("llm: tokenizer tokens missing");
  }
  let tt = gguf_kv_type(g, ti);
  if !tt.is_ok || tt.value != 9 {
    return _err_vocab("llm: tokenizer tokens is not a string array");
  }
  let ta = gguf_kv_arr_type(g, ti);
  if !ta.is_ok || ta.value != 8 {
    return _err_vocab("llm: tokenizer tokens is not a string array");
  }
  let tc = gguf_kv_arr_count(g, ti);
  if !tc.is_ok {
    return _err_vocab("llm: tokenizer tokens is not a string array");
  }
  let n_tokens = tc.value;
  var tokens = Vec[Str].new();
  var e = 0;
  while e < n_tokens {
    let er = gguf_kv_arr_str(g, ti, e);
    if !er.is_ok {
      return _err_vocab("llm: tokenizer tokens is not a string array");
    }
    let s: Str = er.value;
    tokens.push(s);
    e = e + 1;
  }

  // 3. tokenizer.ggml.merges (required string array for gpt2).
  let gi = _kv_index_or_neg(g, "tokenizer.ggml.merges");
  if gi < 0 {
    return _err_vocab("llm: tokenizer merges missing");
  }
  let gt = gguf_kv_type(g, gi);
  if !gt.is_ok || gt.value != 9 {
    return _err_vocab("llm: tokenizer merges is not a string array");
  }
  let ga = gguf_kv_arr_type(g, gi);
  if !ga.is_ok || ga.value != 8 {
    return _err_vocab("llm: tokenizer merges is not a string array");
  }
  let gc = gguf_kv_arr_count(g, gi);
  if !gc.is_ok {
    return _err_vocab("llm: tokenizer merges is not a string array");
  }
  let n_merges = gc.value;
  var merge_l = Vec[Str].new();
  var merge_r = Vec[Str].new();
  var m = 0;
  while m < n_merges {
    let mr2 = gguf_kv_arr_str(g, gi, m);
    if !mr2.is_ok {
      return _err_vocab("llm: tokenizer merges is not a string array");
    }
    let entry: Str = mr2.value;
    // llama.cpp: pos = word.find(' ', 1); no pos -> the ("", "") dead pair.
    let pos = _find_byte(entry, 32, 1);
    if pos < 0 {
      merge_l.push("");
      merge_r.push("");
    } else {
      let left = string.str_slice(entry, 0, pos);
      let right = string.str_slice(entry, pos + 1, string.str_len(entry));
      merge_l.push(left);
      merge_r.push(right);
    }
    m = m + 1;
  }

  // 4. tokenizer.ggml.token_type (optional integer array; default 1 each).
  var has_types = 0;
  var token_types = Vec[Int].new();
  let si = _kv_index_or_neg(g, "tokenizer.ggml.token_type");
  if si >= 0 {
    let st = gguf_kv_type(g, si);
    if !st.is_ok || st.value != 9 {
      return _err_vocab("llm: token types are not an integer array");
    }
    let sa = gguf_kv_arr_type(g, si);
    if !sa.is_ok || !_type_is_integer(sa.value) {
      return _err_vocab("llm: token types are not an integer array");
    }
    let sc = gguf_kv_arr_count(g, si);
    if !sc.is_ok || sc.value < n_tokens {
      return _err_vocab("llm: token type count smaller than token count");
    }
    has_types = 1;
    var k = 0;
    while k < n_tokens {
      let kr = gguf_kv_arr_int(g, si, k);
      if !kr.is_ok {
        return _err_vocab("llm: token types are not an integer array");
      }
      let tv: Int = kr.value;
      token_types.push(tv);
      k = k + 1;
    }
  } else {
    var d = 0;
    while d < n_tokens {
      token_types.push(1);
      d = d + 1;
    }
  }

  // 5. bos / eos ids (optional integer values; -1 when absent).
  var bos = -1;
  let bi = _kv_index_or_neg(g, "tokenizer.ggml.bos_token_id");
  if bi >= 0 {
    let bv = gguf_kv_int(g, bi);
    if !bv.is_ok {
      return _err_vocab("llm: bos token id is not an integer");
    }
    bos = bv.value;
  }
  var eos = -1;
  let ei = _kv_index_or_neg(g, "tokenizer.ggml.eos_token_id");
  if ei >= 0 {
    let ev = gguf_kv_int(g, ei);
    if !ev.is_ok {
      return _err_vocab("llm: eos token id is not an integer");
    }
    eos = ev.value;
  }

  let vocab = LlmVocab{
    model: model;
    tokens: tokens;
    has_types: has_types;
    token_types: token_types;
    merge_l: merge_l;
    merge_r: merge_r;
    bos: bos;
    eos: eos;
  };
  return _ok_vocab(vocab);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Tokenizer model string as stored in the GGUF metadata ("gpt2" in M1).
pub fn llm_vocab_model(v: &LlmVocab) -> Str {
  return v.model;
}

/// Number of tokens (vocabulary size); token ids are 0..size-1.
pub fn llm_vocab_size(v: &LlmVocab) -> Int {
  let toks: Vec[Str] = v.tokens;
  return toks.len();
}

/// Token string of id `i`. Error case: i outside 0..size-1 ->
/// `llm: token index out of range`.
pub fn llm_vocab_token(v: &LlmVocab, i: Int) -> Result[Str, Str] {
  let toks: Vec[Str] = v.tokens;
  if i < 0 || i >= toks.len() {
    return _err_str("llm: token index out of range");
  }
  let s: Str = toks[i];
  return _ok_str(s);
}

/// Token type of id `i` (llama.cpp LLAMA_TOKEN_TYPE_* value: 1 normal,
/// 2 unknown, 3 control, 4 user-defined, 5 unused, 6 byte). When the GGUF
/// has no token_type array every token reports 1 (the llama.cpp default
/// attribute). Error case: i outside 0..size-1 -> `llm: token index out of
/// range`.
pub fn llm_vocab_token_type(v: &LlmVocab, i: Int) -> Result[Int, Str] {
  let toks: Vec[Str] = v.tokens;
  if i < 0 || i >= toks.len() {
    return _err_int("llm: token index out of range");
  }
  let types: Vec[Int] = v.token_types;
  let t: Int = types[i];
  return _ok_int(t);
}

/// Beginning-of-sequence token id, or -1 when the GGUF declares none.
pub fn llm_vocab_bos(v: &LlmVocab) -> Int {
  return v.bos;
}

/// End-of-sequence token id, or -1 when the GGUF declares none.
pub fn llm_vocab_eos(v: &LlmVocab) -> Int {
  return v.eos;
}

/// Number of merge-table entries (rank = index).
pub fn llm_vocab_merge_count(v: &LlmVocab) -> Int {
  let lefts: Vec[Str] = v.merge_l;
  return lefts.len();
}

/// Merge-table entry `i` rendered as `left + " " + right` (the canonical
/// GGUF text form; a dead entry with no split space renders as a single
/// space). Error case: i outside 0..count-1 -> `llm: merge index out of
/// range`.
pub fn llm_vocab_merge(v: &LlmVocab, i: Int) -> Result[Str, Str] {
  let lefts: Vec[Str] = v.merge_l;
  if i < 0 || i >= lefts.len() {
    return _err_str("llm: merge index out of range");
  }
  let rights: Vec[Str] = v.merge_r;
  let l: Str = lefts[i];
  let r: Str = rights[i];
  return _ok_str(l + " " + r);
}

/// Id of token string `s`, or -1 when absent. Duplicate token strings
/// resolve to the highest id (llama.cpp token_to_id overwrite semantics).
pub fn llm_vocab_find_token(v: &LlmVocab, s: Str) -> Int {
  return _find_token_id(v, s);
}

// --------------------------------------------------
//  Byte-level BPE
// --------------------------------------------------

/// Encode `text` into token ids with llama.cpp-family byte-level BPE.
/// Params: v - the vocabulary; text - the byte sequence to encode (M1
/// domain: printable ASCII, see SPEC.md section 6). Returns: the token ids.
/// Semantics: the text is one work chunk (the regex pre-tokenizer is
/// deferred); symbols start as single bytes; while an adjacent pair has a
/// merge rank, the fresh minimum-rank pair (leftmost on ties) is merged;
/// each final symbol must exist in the vocabulary as an exact token string.
/// Empty text yields the empty id list. Error cases:
/// `llm: byte not in vocabulary` (a single non-mergeable byte has no
/// token), `llm: symbol not in vocabulary` (a merged symbol has no token).
pub fn llm_bpe_encode(v: &LlmVocab, text: Str) -> Result[Vec[Int], Str] {
  var syms = Vec[Str].new();
  let n = string.str_len(text);
  var i = 0;
  while i < n {
    let s = string.str_slice(text, i, i + 1);
    syms.push(s);
    i = i + 1;
  }

  // Repeatedly merge the fresh minimum-rank adjacent pair; ties resolve to
  // the leftmost pair (llama.cpp work-queue priority: rank asc, left asc).
  while syms.len() >= 2 {
    var best_rank = -1;
    var best_at = -1;
    var p = 0;
    while p + 1 < syms.len() {
      let l: Str = syms[p];
      let r: Str = syms[p + 1];
      let rank = _merge_rank(v, l, r);
      if rank >= 0 {
        if best_at < 0 || rank < best_rank {
          best_rank = rank;
          best_at = p;
        }
      }
      p = p + 1;
    }
    if best_at < 0 {
      break;
    }
    var next = Vec[Str].new();
    var q = 0;
    while q < syms.len() {
      if q == best_at {
        let l2: Str = syms[q];
        let r2: Str = syms[q + 1];
        next.push(l2 + r2);
        q = q + 2;
      } else {
        let s2: Str = syms[q];
        next.push(s2);
        q = q + 1;
      }
    }
    syms = next;
  }

  var ids = Vec[Int].new();
  var k = 0;
  while k < syms.len() {
    let s3: Str = syms[k];
    let id = _find_token_id(v, s3);
    if id < 0 {
      if string.str_len(s3) == 1 {
        return _err_ids("llm: byte not in vocabulary");
      }
      return _err_ids("llm: symbol not in vocabulary");
    }
    ids.push(id);
    k = k + 1;
  }
  return _ok_ids(ids);
}

/// Decode token ids back to their byte sequence (concatenation of the
/// token strings; over the M1 printable-ASCII domain the identity escape
/// makes this the raw text). Params: v - the vocabulary; ids - the token
/// ids. Returns: the decoded byte sequence; an empty id list decodes to "".
/// Error case: an id outside 0..size-1 -> `llm: token id out of range`.
pub fn llm_bpe_decode(v: &LlmVocab, ids: &Vec[Int]) -> Result[Str, Str] {
  let toks: Vec[Str] = v.tokens;
  var out = "";
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    if id < 0 || id >= toks.len() {
      return _err_str("llm: token id out of range");
    }
    let s: Str = toks[id];
    out = out + s;
    i = i + 1;
  }
  return _ok_str(out);
}

// --------------------------------------------------
//  GGML element-size tables (SPEC.md 10.1)
// --------------------------------------------------

// Human-readable ggml type name for the standard llama.cpp type codes;
// "unknown" for anything else. Codes follow ggml.h (GGML_TYPE_*).
pub fn llm_ggml_type_name(t: Int) -> Str {
  if t == 0 { return "f32"; }
  if t == 1 { return "f16"; }
  if t == 2 { return "q4_0"; }
  if t == 3 { return "q4_1"; }
  if t == 6 { return "q5_0"; }
  if t == 7 { return "q5_1"; }
  if t == 8 { return "q8_0"; }
  if t == 9 { return "q8_1"; }
  if t == 10 { return "q2_K"; }
  if t == 11 { return "q3_K"; }
  if t == 12 { return "q4_K"; }
  if t == 13 { return "q5_K"; }
  if t == 14 { return "q6_K"; }
  if t == 15 { return "q8_K"; }
  return "unknown";
}

// Elements per block for ggml type `t`; 0 when the type is unknown.
// f32/f16 are 1 element per "block"; the 4/5/8-bit families are 32;
// the K-quants are 256 (QK_K).
pub fn llm_ggml_block_elems(t: Int) -> Int {
  if t == 0 || t == 1 {
    return 1;
  }
  if t == 2 || t == 3 || t == 6 || t == 7 || t == 8 || t == 9 {
    return 32;
  }
  if t >= 10 && t <= 15 {
    return 256;
  }
  return 0;
}

// Bytes per block for ggml type `t`; 0 when the type is unknown. These are
// the on-disk block sizes from llama.cpp ggml (f32 4, f16 2, q4_0 18,
// q8_0 34, the K-quants 84..292), reproduced as an exact integer table.
pub fn llm_ggml_block_bytes(t: Int) -> Int {
  if t == 0 { return 4; }
  if t == 1 { return 2; }
  if t == 2 { return 18; }
  if t == 3 { return 20; }
  if t == 6 { return 22; }
  if t == 7 { return 24; }
  if t == 8 { return 34; }
  if t == 9 { return 36; }
  if t == 10 { return 84; }
  if t == 11 { return 110; }
  if t == 12 { return 144; }
  if t == 13 { return 176; }
  if t == 14 { return 210; }
  if t == 15 { return 292; }
  return 0;
}

// --------------------------------------------------
//  Tensor extent validation (SPEC.md 10.1)
// --------------------------------------------------

/// Exact byte size of tensor `ti` in `g`: the product of its dimensions
/// divided by the type's block element count, times the type's block byte
/// count (exact integer arithmetic; no floats). Error cases:
/// `llm: tensor index out of range`, `llm: tensor has negative dimension`,
/// `llm: unknown ggml type`, `llm: tensor dims not divisible by block size`.
pub fn llm_tensor_nbytes(g: &Gguf, ti: Int) -> Result[Int, Str] {
  let nr = gguf_tensor_ndims(g, ti);
  if !nr.is_ok {
    return _err_int("llm: tensor index out of range");
  }
  let nd: Int = nr.value;
  var nelem = 1;
  var d = 0;
  while d < nd {
    let dr = gguf_tensor_dim(g, ti, d);
    if !dr.is_ok {
      return _err_int("llm: tensor index out of range");
    }
    let dv: Int = dr.value;
    if dv < 0 {
      return _err_int("llm: tensor has negative dimension");
    }
    nelem = nelem * dv;
    d = d + 1;
  }
  let tr = gguf_tensor_type(g, ti);
  if !tr.is_ok {
    return _err_int("llm: tensor index out of range");
  }
  let ty: Int = tr.value;
  let be = llm_ggml_block_elems(ty);
  let bb = llm_ggml_block_bytes(ty);
  if be <= 0 || bb <= 0 {
    return _err_int("llm: unknown ggml type");
  }
  if nelem % be != 0 {
    return _err_int("llm: tensor dims not divisible by block size");
  }
  return _ok_int((nelem / be) * bb);
}

/// Copy the payload of tensor `ti` out of container buffer `buf`. The slice
/// is `data_offset + tensor_offset` for `llm_tensor_nbytes(g, ti)` bytes,
/// after validating that the extent lies inside the declared data section
/// (`gguf_data_len`) and inside `buf` itself. Error cases propagate the
/// `llm_tensor_nbytes` errors, plus `llm: tensor extent out of data section`
/// and `llm: buffer too small for tensor extent`.
pub fn llm_tensor_data(g: &Gguf, buf: &Vec[UInt8], ti: Int) -> Result[Vec[UInt8], Str] {
  let nr = llm_tensor_nbytes(g, ti);
  if !nr.is_ok {
    let m: Str = nr.error;
    return _err_bytes(m);
  }
  let nbytes: Int = nr.value;
  let orr = gguf_tensor_offset(g, ti);
  if !orr.is_ok {
    return _err_bytes("llm: tensor index out of range");
  }
  let toff: Int = orr.value;
  let dl = gguf_data_len(g);
  if toff < 0 || nbytes < 0 || toff + nbytes > dl {
    return _err_bytes("llm: tensor extent out of data section");
  }
  let base = gguf_data_offset(g);
  let start = base + toff;
  if start + nbytes > buf.len() {
    return _err_bytes("llm: buffer too small for tensor extent");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < nbytes {
    let b: UInt8 = buf[start + i];
    out.push(b);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Deterministic float-free numerics (SPEC.md 10.2/10.3)
// --------------------------------------------------

// Little-endian u16 assembled from two 0..255 integer bytes.
pub fn llm_u16_le(b0: Int, b1: Int) -> Int {
  return (b0 & 0xFF) | ((b1 & 0xFF) << 8);
}

// Little-endian u32 assembled from four 0..255 integer bytes.
pub fn llm_u32_le(b0: Int, b1: Int, b2: Int, b3: Int) -> Int {
  return (b0 & 0xFF) | ((b1 & 0xFF) << 8) | ((b2 & 0xFF) << 16) | ((b3 & 0xFF) << 24);
}

/// Decode an IEEE-754 binary16 bit pattern (low 16 bits of `bits`) into the
/// exact scaled integer `(m, e)` with value = m / 2^e. Integer shifts/masks
/// only (no Float64/Float32 arithmetic): the mantissa and exponent of the
/// half float are extracted directly. Normalised values become (1024+mant,
/// 25-exp); subnormals (mant, 24); negative zero decodes to (0, 0). The
/// decode is exact -- there is no rounding step. Error cases:
/// `llm: f16 is inf`, `llm: f16 is nan` (exponent field all ones).
pub fn llm_f16_to_scaled(bits: Int) -> Result[LlmScale, Str] {
  let b = bits & 0xFFFF;
  let sign = (b >> 15) & 1;
  let exp = (b >> 10) & 0x1F;
  let mant = b & 0x3FF;
  if exp == 31 {
    if mant == 0 {
      return _err_scale("llm: f16 is inf");
    }
    return _err_scale("llm: f16 is nan");
  }
  if exp == 0 {
    if mant == 0 {
      return _ok_scale(LlmScale{ m: 0; e: 0; });
    }
    var mz = mant;
    if sign == 1 {
      mz = 0 - mz;
    }
    return _ok_scale(LlmScale{ m: mz; e: 24; });
  }
  let mm = 1024 + mant;
  let E = exp - 25;
  var m = mm;
  var e = 0;
  if E >= 0 {
    m = mm << E;
  } else {
    e = 0 - E;
  }
  if sign == 1 {
    m = 0 - m;
  }
  return _ok_scale(LlmScale{ m: m; e: e; });
}

/// Decode an IEEE-754 binary32 bit pattern (low 32 bits of `bits`) into the
/// exact scaled integer `(m, e)` with value = m / 2^e. Integer shifts/masks
/// only. Normalised values become (8388608+mant, 150-exp); subnormals
/// (mant, 149). Decode is exact (no rounding). Error cases: `llm: f32 is
/// inf`, `llm: f32 is nan`. Overflow note: a value whose exponent is larger
/// than the host Int width cannot be represented; callers only pass scale
/// patterns in the tensor-scale range (see SPEC.md 10.2).
pub fn llm_f32_to_scaled(bits: Int) -> Result[LlmScale, Str] {
  let b = bits & 0xFFFFFFFF;
  let sign = (b >> 31) & 1;
  let exp = (b >> 23) & 0xFF;
  let mant = b & 0x7FFFFF;
  if exp == 255 {
    if mant == 0 {
      return _err_scale("llm: f32 is inf");
    }
    return _err_scale("llm: f32 is nan");
  }
  if exp == 0 {
    if mant == 0 {
      return _ok_scale(LlmScale{ m: 0; e: 0; });
    }
    var mz = mant;
    if sign == 1 {
      mz = 0 - mz;
    }
    return _ok_scale(LlmScale{ m: mz; e: 149; });
  }
  let mm = 8388608 + mant;
  let E = exp - 150;
  var m = mm;
  var e = 0;
  if E >= 0 {
    m = mm << E;
  } else {
    e = 0 - E;
  }
  if sign == 1 {
    m = 0 - m;
  }
  return _ok_scale(LlmScale{ m: m; e: e; });
}

// Block byte size and element count of Q8_0 (ggml block_q8_0: a little-endian
// f16 scale `d` followed by 32 signed int8 quants).
fn _q8_0_block_bytes() -> Int {
  return 34;
}

/// Dequantize a Q8_0 payload into scaled integers. Params: payload - the raw
/// block bytes (little-endian f16 scale, then 32 int8 quants per 34-byte
/// block); out_values - appended with one Int per quant. Returns: the shared
/// block scale as `(m, e)` where the exact real value of output `i` is
/// `out_values[i] / 2^e`, i.e. output `i` is `q[i] * m` for the signed quant
/// `q[i]`. The f16 scale is decoded with llm_f16_to_scaled, so the mapping is
/// EXACT integer arithmetic: the pinned error bound is 0 (no rounding step).
/// Documented limitation: all blocks must carry the same scale bits, since
/// the surface returns a single shared (m, e); differing scales are rejected.
/// Error cases: `llm: q8_0 payload is empty`, `llm: q8_0 payload length not
/// a multiple of block size`, the f16 decode errors, and
/// `llm: q8_0 mixed block scales are not supported`.
pub fn llm_dequant_q8_0(payload: &Vec[UInt8], out_values: &mut Vec[Int]) -> Result[LlmScale, Str] {
  let n = payload.len();
  if n == 0 {
    return _err_scale("llm: q8_0 payload is empty");
  }
  if n % 34 != 0 {
    return _err_scale("llm: q8_0 payload length not a multiple of block size");
  }
  let nblocks = n / 34;
  let s0lo = (payload[0] as Int) & 0xFF;
  let s0hi = (payload[1] as Int) & 0xFF;
  let sc0 = llm_f16_to_scaled(llm_u16_le(s0lo, s0hi));
  if !sc0.is_ok {
    let mm: Str = sc0.error;
    return _err_scale(mm);
  }
  let first: LlmScale = sc0.value;
  let m0: Int = first.m;
  let e0: Int = first.e;
  var blk = 0;
  while blk < nblocks {
    let base = blk * 34;
    if blk > 0 {
      let lo = (payload[base] as Int) & 0xFF;
      let hi = (payload[base + 1] as Int) & 0xFF;
      let csr = llm_f16_to_scaled(llm_u16_le(lo, hi));
      if !csr.is_ok {
        let mm: Str = csr.error;
        return _err_scale(mm);
      }
      let cs: LlmScale = csr.value;
      if cs.m != m0 || cs.e != e0 {
        return _err_scale("llm: q8_0 mixed block scales are not supported");
      }
    }
    var k = 0;
    while k < 32 {
      let raw = (payload[base + 2 + k] as Int) & 0xFF;
      var q = raw;
      if raw >= 128 {
        q = raw - 256;
      }
      let v = q * m0;
      out_values.push(v);
      k = k + 1;
    }
    blk = blk + 1;
  }
  return _ok_scale(LlmScale{ m: m0; e: e0; });
}

// --------------------------------------------------
//  Model assembly (SPEC.md 10.1 composite)
// --------------------------------------------------

// Ok(v) for Result[LlmModel, Str].
fn _ok_model(v: LlmModel) -> Result[LlmModel, Str] {
  return Ok(v);
}

// Err(m) for Result[LlmModel, Str].
fn _err_model(m: Str) -> Result[LlmModel, Str] {
  return Err(m);
}

/// Parsed container plus validated tensors, produced only by llm_model_open.
/// `g` is the header parsed by xiom.gguf, `vocab` the extracted tokenizer
/// vocabulary, `n_tensors` the number of declared tensor infos whose extents
/// were validated against the payload.
pub type LlmModel = {
  g: Gguf;
  vocab: LlmVocab;
  n_tensors: Int;
}

/// Sampler configuration for the M3 generation loop (SPEC.md 10.5). All
/// fields are plain Ints (no floats). `greedy != 0` selects argmax and ignores
/// the sampling fields. Otherwise the pipeline is: temperature scale by
/// `t_num / t_den`, integer softmax at `shift`, top-k by adjusted logit rank,
/// top-p nucleus over the softmax mass (`top_p_q` in units of `2^shift`), and
/// a uniform draw from a deterministic LCG seeded with `seed`. `top_k <= 0`
/// or `top_k >= vocab` disables top-k; `top_p_q <= 0` keeps the single
/// highest-probability token.
pub type LlmSampler = {
  greedy: Int;
  t_num: Int;
  t_den: Int;
  top_k: Int;
  top_p_q: Int;
  shift: Int;
  seed: Int;
}

/// llm_model_open-equivalent assembly of tensor data: concatenate `header`
/// and `payload` (callers may instead pass one concatenated container buffer
/// as `header` and an empty `payload`), parse it with xiom.gguf, extract the
/// vocabulary (llm_vocab_from_gguf) and validate every declared tensor extent
/// against the data section. Returns the model on success. Error cases:
/// `llm: model header parse failed`, any vocabulary error message, and
/// `llm: model tensor extent invalid`.
pub fn llm_model_open(header: &Vec[UInt8], payload: &Vec[UInt8]) -> Result[LlmModel, Str] {
  var buf = Vec[UInt8].new();
  var i = 0;
  while i < header.len() {
    let b: UInt8 = header[i];
    buf.push(b);
    i = i + 1;
  }
  var j = 0;
  while j < payload.len() {
    let b2: UInt8 = payload[j];
    buf.push(b2);
    j = j + 1;
  }
  let pr = gguf_parse(&buf);
  if !pr.is_ok {
    return _err_model("llm: model header parse failed");
  }
  let g: Gguf = pr.value;
  let vr = llm_vocab_from_gguf(&g);
  if !vr.is_ok {
    let vm: Str = vr.error;
    return _err_model(vm);
  }
  let vv: LlmVocab = vr.value;
  let nt = gguf_tensor_count(&g);
  var t = 0;
  while t < nt {
    let nr = llm_tensor_nbytes(&g, t);
    if !nr.is_ok {
      return _err_model("llm: model tensor extent invalid");
    }
    let offr = gguf_tensor_offset(&g, t);
    if !offr.is_ok {
      return _err_model("llm: model tensor extent invalid");
    }
    let off: Int = offr.value;
    let nb: Int = nr.value;
    if off < 0 || off + nb > gguf_data_len(&g) {
      return _err_model("llm: model tensor extent invalid");
    }
    t = t + 1;
  }
  let model = LlmModel{ g: g; vocab: vv; n_tensors: nt; };
  return _ok_model(model);
}

// --------------------------------------------------
//  Integer helpers (overflow fail-closed)
// --------------------------------------------------

// Absolute value without a stdlib dependency (Int stays inside i64).
fn _iabs(x: Int) -> Int {
  if x < 0 {
    return 0 - x;
  }
  return x;
}

// Conservative overflow ceiling, safely below the i64 maximum; every value in
// this package is far smaller, so a false overflow cannot arise in practice.
fn _imax() -> Int {
  return 4000000000000000000;
}

// True when a*b would overflow the Int width (wraparound guard).
fn _mul_ovf(a: Int, b: Int) -> Bool {
  if a == 0 || b == 0 {
    return false;
  }
  return _iabs(a) > _imax() / _iabs(b);
}

// True when a+b would overflow the Int width (wraparound guard).
fn _add_ovf(a: Int, b: Int) -> Bool {
  if a > 0 && b > 0 {
    return a > _imax() - b;
  }
  if a < 0 && b < 0 {
    return _iabs(a) > _imax() - _iabs(b);
  }
  return false;
}

// Round-half-away-from-zero integer division; the only declared rounding step
// in the numeric kernels (error <= 1/2 LSB of the result).
fn _idiv_round(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  if r == 0 {
    return q;
  }
  let tr = _iabs(r) * 2;
  let ab = _iabs(b);
  if tr >= ab {
    if (a > 0) == (b > 0) {
      return q + 1;
    }
    return q - 1;
  }
  return q;
}

/// Integer square root (floor). Used by the RMSNorm kernel; the floor is part
/// of that kernel's documented error bound.
pub fn llm_isqrt(n: Int) -> Int {
  if n <= 0 {
    return 0;
  }
  var x = n;
  var y = (x + 1) / 2;
  while y < x {
    x = y;
    y = (x + n / x) / 2;
  }
  return x;
}

// Decode a scaled integer m/2^e into a plain Int when it is an exact integer;
// error otherwise. e <= 0 scales up (m << -e); e > 0 requires divisibility.
fn _scale_to_exact_int(m: Int, e: Int) -> Result[Int, Str] {
  if e <= 0 {
    if e < -60 {
      return _err_int("llm: scaled value out of range");
    }
    return _ok_int(m << (0 - e));
  }
  let d = 1 << e;
  if m % d != 0 {
    return _err_int("llm: value is not an exact integer");
  }
  return _ok_int(m / d);
}

/// Read the f32 stored little-endian at byte offset `off` of `payload` and
/// return it as an exact plain Int (via the integer bit decode). Error cases:
/// `llm: f32 offset out of range`, the f32 inf/nan decode errors, and
/// `llm: value is not an exact integer` for a non-integral value.
pub fn llm_f32_at(payload: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  if off < 0 || off + 4 > payload.len() {
    return _err_int("llm: f32 offset out of range");
  }
  let b0 = (payload[off] as Int) & 0xFF;
  let b1 = (payload[off + 1] as Int) & 0xFF;
  let b2 = (payload[off + 2] as Int) & 0xFF;
  let b3 = (payload[off + 3] as Int) & 0xFF;
  let sc = llm_f32_to_scaled(llm_u32_le(b0, b1, b2, b3));
  if !sc.is_ok {
    let m: Str = sc.error;
    return _err_int(m);
  }
  let s: LlmScale = sc.value;
  return _scale_to_exact_int(s.m, s.e);
}

/// Dequantize a Q8_0 payload and reduce to plain integer weights: the exact
/// real value of output `i` is `q[i] * m / 2^e`, so when `(m / 2^e)` is not an
/// integer this fails closed. For the standard scale-1.0 blocks (m=1024, e=10)
/// the result is exactly the signed quant q[i]; this is the bridge from the
/// scaled-int `(m, e)` form into the flat integer kernels. Error cases: the
/// llm_dequant_q8_0 errors plus `llm: value is not an exact integer`.
pub fn llm_q8_0_ints(payload: &Vec[UInt8], out_values: &mut Vec[Int]) -> Result[LlmScale, Str] {
  var tmp = Vec[Int].new();
  let dr = llm_dequant_q8_0(payload, &mut tmp);
  if !dr.is_ok {
    let m: Str = dr.error;
    return _err_scale(m);
  }
  let sc: LlmScale = dr.value;
  var i = 0;
  while i < tmp.len() {
    let v: Int = tmp[i];
    let r = _scale_to_exact_int(v, sc.e);
    if !r.is_ok {
      let m2: Str = r.error;
      return _err_scale(m2);
    }
    let iv: Int = r.value;
    out_values.push(iv);
    i = i + 1;
  }
  return _ok_scale(sc);
}

// --------------------------------------------------
//  Matmul + forward primitives (SPEC.md 10.4)
// --------------------------------------------------

/// Flat row-major integer matmul with overflow-checked accumulation (fail
/// closed: it never wraps around and never silently saturates). Params: `a` is
/// `a_rows x a_cols` row-major; `b` is `a_cols x b_cols` row-major (its row
/// count is implicit in `a_cols`); `b_cols` is the number of columns of `b`.
/// Returns the `a_rows x b_cols` product, row-major.
///
/// Error bounds: none -- the operation is exact over the scaled-int `(m, e)`
/// form; the caller carries the combined exponent (the real value of a product
/// element is the integer result divided by `2^(e_a + e_b)`). Error cases:
/// `llm: matmul negative dimension`, `llm: matmul a size mismatch`,
/// `llm: matmul b size mismatch`, `llm: matmul overflow`.
pub fn llm_matmul_i32(a: &Vec[Int], a_rows: Int, a_cols: Int, b: &Vec[Int], b_cols: Int) -> Result[Vec[Int], Str] {
  if a_rows < 0 || a_cols < 0 || b_cols < 0 {
    return _err_ids("llm: matmul negative dimension");
  }
  if a.len() != a_rows * a_cols {
    return _err_ids("llm: matmul a size mismatch");
  }
  if b.len() != a_cols * b_cols {
    return _err_ids("llm: matmul b size mismatch");
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < a_rows {
    var j = 0;
    while j < b_cols {
      var acc = 0;
      var k = 0;
      while k < a_cols {
        let av: Int = a[i * a_cols + k];
        let bv: Int = b[k * b_cols + j];
        if _mul_ovf(av, bv) {
          return _err_ids("llm: matmul overflow");
        }
        let p = av * bv;
        if _add_ovf(acc, p) {
          return _err_ids("llm: matmul overflow");
        }
        acc = acc + p;
        k = k + 1;
      }
      out.push(acc);
      j = j + 1;
    }
    i = i + 1;
  }
  return _ok_ids(out);
}

/// Integer dot product with overflow-checked accumulation (used for attention
/// scores). Error cases: `llm: dot size mismatch`, `llm: dot overflow`.
pub fn llm_dot_i32(a: &Vec[Int], b: &Vec[Int]) -> Result[Int, Str] {
  if a.len() != b.len() {
    return _err_int("llm: dot size mismatch");
  }
  var acc = 0;
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if _mul_ovf(x, y) {
      return _err_int("llm: dot overflow");
    }
    let p = x * y;
    if _add_ovf(acc, p) {
      return _err_int("llm: dot overflow");
    }
    acc = acc + p;
    i = i + 1;
  }
  return _ok_int(acc);
}

/// Integer RMSNorm: `out[i] = gamma[i] * x[i] * 2^out_shift / rms` where
/// `rms = isqrt(sum(x[i]^2)/n + eps)` (all integer). Returns the plain-int
/// normalized vector; the real value of output `i` is `out[i] / 2^out_shift`.
///
/// Error bounds (documented): `rms` is the floor integer square root, so the
/// relative error from the root is < 1/rms; the final `_idiv_round` adds at
/// most 1/2 LSB. Total absolute error <= 1 LSB of `(gamma[i]*x[i]*2^shift)`
/// plus a term bounded by `|gamma[i]*x[i]*2^shift| / rms^2`. Exact when the
/// mean square is a perfect square and the division divides evenly (the M2
/// fixture is constructed so both hold). Error cases: `llm: rmsnorm empty
/// input`, `llm: rmsnorm gamma size mismatch`, `llm: rmsnorm negative shift`,
/// `llm: rmsnorm overflow`, `llm: rmsnorm zero norm`.
pub fn llm_rmsnorm_i32(x: &Vec[Int], gamma: &Vec[Int], eps: Int, out_shift: Int) -> Result[Vec[Int], Str] {
  let n = x.len();
  if n == 0 {
    return _err_ids("llm: rmsnorm empty input");
  }
  if gamma.len() != n {
    return _err_ids("llm: rmsnorm gamma size mismatch");
  }
  if out_shift < 0 {
    return _err_ids("llm: rmsnorm negative shift");
  }
  var ss = 0;
  var i = 0;
  while i < n {
    let xi: Int = x[i];
    if _mul_ovf(xi, xi) {
      return _err_ids("llm: rmsnorm overflow");
    }
    let sq = xi * xi;
    if _add_ovf(ss, sq) {
      return _err_ids("llm: rmsnorm overflow");
    }
    ss = ss + sq;
    i = i + 1;
  }
  let ms = ss / n;
  let rms = llm_isqrt(ms + eps);
  if rms <= 0 {
    return _err_ids("llm: rmsnorm zero norm");
  }
  let scale = 1 << out_shift;
  var out = Vec[Int].new();
  var k = 0;
  while k < n {
    let gv: Int = gamma[k];
    let xv: Int = x[k];
    if _mul_ovf(gv, xv) {
      return _err_ids("llm: rmsnorm overflow");
    }
    let gx = gv * xv;
    if _mul_ovf(gx, scale) {
      return _err_ids("llm: rmsnorm overflow");
    }
    out.push(_idiv_round(gx * scale, rms));
    k = k + 1;
  }
  return _ok_ids(out);
}

/// Integer RoPE applied to consecutive pairs with a caller-supplied fixed-point
/// sine/cosine table: `(x0,x1) -> ((x0*c - x1*s + rnd) >> shift,
/// (x0*s + x1*c + rnd) >> shift)` where `rnd = 2^(shift-1)` (round-half-up).
/// `cos_q`/`sin_q` hold `head_dim/2` values scaled by `2^shift`; at position 0
/// the table is `(2^shift, 0)`, giving the exact identity.
///
/// Error bound (documented): each component is truncated after adding half an
/// LSB, so the absolute error is <= 1 LSB of `|x|` (plus the table's own
/// quantization error, zero for the identity and the exact 90-degree table).
/// Error cases: `llm: rope head_dim not even`, `llm: rope size mismatch`,
/// `llm: rope table size mismatch`, `llm: rope shift too small`,
/// `llm: rope overflow`.
pub fn llm_rope_i32(x: &Vec[Int], head_dim: Int, cos_q: &Vec[Int], sin_q: &Vec[Int], shift: Int) -> Result[Vec[Int], Str] {
  if head_dim < 2 || head_dim % 2 != 0 {
    return _err_ids("llm: rope head_dim not even");
  }
  if x.len() != head_dim {
    return _err_ids("llm: rope size mismatch");
  }
  let half = head_dim / 2;
  if cos_q.len() != half || sin_q.len() != half {
    return _err_ids("llm: rope table size mismatch");
  }
  if shift < 1 {
    return _err_ids("llm: rope shift too small");
  }
  let rnd = 1 << (shift - 1);
  var out = Vec[Int].new();
  var p = 0;
  while p < half {
    let x0: Int = x[2 * p];
    let x1: Int = x[2 * p + 1];
    let c: Int = cos_q[p];
    let s: Int = sin_q[p];
    if _mul_ovf(x0, c) || _mul_ovf(x1, s) || _mul_ovf(x0, s) || _mul_ovf(x1, c) {
      return _err_ids("llm: rope overflow");
    }
    let a = x0 * c - x1 * s;
    let b = x0 * s + x1 * c;
    out.push((a + rnd) >> shift);
    out.push((b + rnd) >> shift);
    p = p + 1;
  }
  return _ok_ids(out);
}

/// Integer softmax over fixed-point logits (each real logit is
/// `logits_q[i] / 2^shift`). The exponent is approximated by the quadratic
/// `exp(t) ~ 1 + t + t^2/2` on `t = (logit - max) / 2^shift <= 0` (computed in
/// integer arithmetic), and the weights are normalized to sum to `2^shift`.
///
/// Error bound (documented): EXACT for a uniform input (all logits equal ->
/// uniform `2^shift/n`) and for a single element (`[2^shift]`). Otherwise the
/// quadratic exponential has a relative error that stays within a few percent
/// on `[-1,0]` and grows outside it; the result is a deterministic bounded
/// approximation, never NaN and never a division by zero. Error cases:
/// `llm: softmax empty input`, `llm: softmax shift too small`,
/// `llm: softmax overflow`, `llm: softmax zero mass`.
pub fn llm_softmax_i32(logits_q: &Vec[Int], shift: Int) -> Result[Vec[Int], Str] {
  let n = logits_q.len();
  if n == 0 {
    return _err_ids("llm: softmax empty input");
  }
  if shift < 1 {
    return _err_ids("llm: softmax shift too small");
  }
  let one = 1 << shift;
  var m: Int = logits_q[0];
  var i = 1;
  while i < n {
    let v: Int = logits_q[i];
    if v > m {
      m = v;
    }
    i = i + 1;
  }
  var w = Vec[Int].new();
  var sum = 0;
  var k = 0;
  while k < n {
    let d: Int = logits_q[k] - m;
    var wi = one + d;
    if _mul_ovf(d, d) {
      return _err_ids("llm: softmax overflow");
    }
    wi = wi + (d * d) / (2 * one);
    if wi < 0 {
      wi = 0;
    }
    w.push(wi);
    if _add_ovf(sum, wi) {
      return _err_ids("llm: softmax overflow");
    }
    sum = sum + wi;
    k = k + 1;
  }
  if sum <= 0 {
    return _err_ids("llm: softmax zero mass");
  }
  var out = Vec[Int].new();
  var t = 0;
  while t < n {
    let wi2: Int = w[t];
    if _mul_ovf(wi2, one) {
      return _err_ids("llm: softmax overflow");
    }
    out.push(_idiv_round(wi2 * one, sum));
    t = t + 1;
  }
  return _ok_ids(out);
}

/// Integer SiLU with a piecewise sigmoid: `sig = 2^shift` (g >= 4*2^shift),
/// `0` (g <= -4*2^shift), else the linear ramp `(g + 4*2^shift)/8`; the result
/// is `g * sig / 2^shift` rounded half away from zero.
///
/// Error bound (documented): EXACT in the saturated region `|g| >= 4*2^shift`
/// (there `sig` is 0 or `2^shift`, so `silu(g) = g` or `0` exactly) and at
/// `g = 0`. Inside the linear ramp the sigmoid error is at most the difference
/// between the ramp and the true logistic, bounded by ~0.1 on the interval.
pub fn llm_silu_q(g: Int, shift: Int) -> Int {
  let one = 1 << shift;
  let four = 4 << shift;
  var sig = 0;
  if g >= four {
    sig = one;
  } else if g <= (0 - four) {
    sig = 0;
  } else {
    sig = (g + four) / 8;
  }
  return _idiv_round(g * sig, one);
}

/// Integer SwiGLU: `out[j] = silu(gate[j]) * up[j] / 2^shift` (rounded half
/// away from zero). The gate/up vectors are fixed-point `2^shift`; the
/// product is `2^(2*shift)` and is rescaled back. Error bound: exact whenever
/// the SiLU term is exact (see llm_silu_q), plus <= 1/2 LSB from the rescale.
/// Error cases: `llm: swiglu size mismatch`, `llm: swiglu overflow`.
pub fn llm_swiglu_i32(gate: &Vec[Int], up: &Vec[Int], shift: Int) -> Result[Vec[Int], Str] {
  if gate.len() != up.len() {
    return _err_ids("llm: swiglu size mismatch");
  }
  let one = 1 << shift;
  var out = Vec[Int].new();
  var i = 0;
  while i < gate.len() {
    let gv: Int = gate[i];
    let uv: Int = up[i];
    let s = llm_silu_q(gv, shift);
    if _mul_ovf(s, uv) {
      return _err_ids("llm: swiglu overflow");
    }
    out.push(_idiv_round(s * uv, one));
    i = i + 1;
  }
  return _ok_ids(out);
}

/// Canonical `xiom.tensor` diagnostic dump of a flat row-major `rows x cols`
/// vector ("over xiom.tensor where sensible": the integer tensor core supplies
/// shape construction and dumps, while the hot kernels above stay over flat
/// Vec[Int] because xiom.tensor has no matmul/views/elementwise ops).
pub fn llm_shape_dump(rows: Int, cols: Int, values: &Vec[Int]) -> Str {
  var dims = Vec[Int].new();
  dims.push(rows);
  dims.push(cols);
  let tr = tensor_from_flat(2, &dims, values);
  if !tr.is_ok {
    let m: Str = tr.error;
    return "tensor: " + m;
  }
  let tv: Tensor = tr.value;
  return tensor_dump(&tv);
}

// --------------------------------------------------
//  M3a: deterministic PRNG, sampling, generation loop (SPEC.md 10.5)
// --------------------------------------------------

// --- forward pass over the M3 fixture model ---

// Product of a tensor's declared dims, or -1 when any accessor fails.
fn _tensor_elem_count(g: &Gguf, idx: Int) -> Int {
  let ndr = gguf_tensor_ndims(g, idx);
  if !ndr.is_ok {
    return -1;
  }
  let nd: Int = ndr.value;
  var cnt = 1;
  var d = 0;
  while d < nd {
    let dr = gguf_tensor_dim(g, idx, d);
    if !dr.is_ok {
      return -1;
    }
    let dv: Int = dr.value;
    cnt = cnt * dv;
    d = d + 1;
  }
  return cnt;
}

// Load an f32 tensor as plain Ints (every value must be an exact integer;
// llm_f32_at fails closed otherwise). Error: `llm: model tensor missing`,
// `llm: model tensor extent invalid`.
fn _load_f32_tensor(g: &Gguf, buf: &Vec[UInt8], name: Str) -> Result[Vec[Int], Str] {
  let fir = gguf_find_tensor(g, name);
  if !fir.is_ok {
    return _err_ids("llm: model tensor missing");
  }
  let idx: Int = fir.value;
  let cnt = _tensor_elem_count(g, idx);
  if cnt < 0 {
    return _err_ids("llm: model tensor extent invalid");
  }
  let tdr = llm_tensor_data(g, buf, idx);
  if !tdr.is_ok {
    return _err_ids("llm: model tensor extent invalid");
  }
  let pay: Vec[UInt8] = tdr.value;
  var out = Vec[Int].new();
  var i = 0;
  while i < cnt {
    let vr = llm_f32_at(&pay, i * 4);
    if !vr.is_ok {
      return _err_ids("llm: model tensor extent invalid");
    }
    let vv: Int = vr.value;
    out.push(vv);
    i = i + 1;
  }
  return _ok_ids(out);
}

// Load the FIRST Q8_0 block of a tensor as plain Ints. The M3 fixture stores
// the three FFN matrices as f32-declared slices whose leading 34 bytes are one
// Q8_0 block (SPEC.md section 8 item 7), so this reads exactly those bytes.
fn _load_q8_block(g: &Gguf, buf: &Vec[UInt8], name: Str) -> Result[Vec[Int], Str] {
  let fir = gguf_find_tensor(g, name);
  if !fir.is_ok {
    return _err_ids("llm: model tensor missing");
  }
  let idx: Int = fir.value;
  let tdr = llm_tensor_data(g, buf, idx);
  if !tdr.is_ok {
    return _err_ids("llm: model tensor extent invalid");
  }
  let pay: Vec[UInt8] = tdr.value;
  let blen = _q8_0_block_bytes();
  var blk = Vec[UInt8].new();
  var k = 0;
  while k < blen && k < pay.len() {
    let b: UInt8 = pay[k];
    blk.push(b);
    k = k + 1;
  }
  var out = Vec[Int].new();
  let sr = llm_q8_0_ints(&blk, &mut out);
  if !sr.is_ok {
    return _err_ids("llm: model tensor extent invalid");
  }
  return _ok_ids(out);
}

/// Single-position forward pass for the M3 fixture model (emb=4, heads=1,
/// ffn=8, 1 layer): gather the `token_id` embedding row, RMSNorm -> Q/K/V ->
/// position-0 RoPE (identity) -> single-position attention -> output residual
/// -> SwiGLU FFN with residual -> output projection. This mirrors the M2b
/// hand-computed composition (SPEC.md section 10.4) and is the per-step core of
/// `llm_generate`; there is no KV cache yet (one position per step). The three
/// FFN matrices are read as one Q8_0 block (fixture convention). Error cases:
/// `llm: token id out of range`, `llm: model tensor missing`,
/// `llm: model tensor extent invalid`, and any kernel error.
pub fn llm_forward_token(model: &LlmModel, buf: &Vec[UInt8], token_id: Int) -> Result[Vec[Int], Str] {
  let g: Gguf = model.g;
  let v: LlmVocab = model.vocab;
  let vsz = llm_vocab_size(&v);
  if token_id < 0 || token_id >= vsz {
    return _err_ids("llm: token id out of range");
  }
  let embr = _load_f32_tensor(&g, buf, "token_embd.weight");
  if !embr.is_ok {
    let e: Str = embr.error;
    return _err_ids(e);
  }
  let embed: Vec[Int] = embr.value;
  let g1r = _load_f32_tensor(&g, buf, "attn_norm.weight");
  if !g1r.is_ok {
    let e1: Str = g1r.error;
    return _err_ids(e1);
  }
  let gamma1: Vec[Int] = g1r.value;
  let wqr = _load_f32_tensor(&g, buf, "wq.weight");
  if !wqr.is_ok {
    let e2: Str = wqr.error;
    return _err_ids(e2);
  }
  let wq: Vec[Int] = wqr.value;
  let wkr = _load_f32_tensor(&g, buf, "wk.weight");
  if !wkr.is_ok {
    let e3: Str = wkr.error;
    return _err_ids(e3);
  }
  let wk: Vec[Int] = wkr.value;
  let wvr = _load_f32_tensor(&g, buf, "wv.weight");
  if !wvr.is_ok {
    let e4: Str = wvr.error;
    return _err_ids(e4);
  }
  let wv: Vec[Int] = wvr.value;
  let wor = _load_f32_tensor(&g, buf, "wo.weight");
  if !wor.is_ok {
    let e5: Str = wor.error;
    return _err_ids(e5);
  }
  let wo: Vec[Int] = wor.value;
  let g2r = _load_f32_tensor(&g, buf, "ffn_norm.weight");
  if !g2r.is_ok {
    let e6: Str = g2r.error;
    return _err_ids(e6);
  }
  let gamma2: Vec[Int] = g2r.value;
  let w1r = _load_q8_block(&g, buf, "ffn_gate.weight");
  if !w1r.is_ok {
    let e7: Str = w1r.error;
    return _err_ids(e7);
  }
  let w1: Vec[Int] = w1r.value;
  let w3r = _load_q8_block(&g, buf, "ffn_up.weight");
  if !w3r.is_ok {
    let e8: Str = w3r.error;
    return _err_ids(e8);
  }
  let w3: Vec[Int] = w3r.value;
  let w2r = _load_q8_block(&g, buf, "ffn_down.weight");
  if !w2r.is_ok {
    let e9: Str = w2r.error;
    return _err_ids(e9);
  }
  let w2: Vec[Int] = w2r.value;
  let woutr = _load_f32_tensor(&g, buf, "output.weight");
  if !woutr.is_ok {
    let e10: Str = woutr.error;
    return _err_ids(e10);
  }
  let wout: Vec[Int] = woutr.value;
  // Dims from the declared tensors: token_embd = [vocab, emb], ffn_gate = [ffn, emb].
  let eidx = gguf_find_tensor(&g, "token_embd.weight");
  let embidx: Int = eidx.value;
  let dd = gguf_tensor_dim(&g, embidx, 1);
  let emb: Int = dd.value;
  let fidx = gguf_find_tensor(&g, "ffn_gate.weight");
  let ffi: Int = fidx.value;
  let fd = gguf_tensor_dim(&g, ffi, 0);
  let ffn: Int = fd.value;

  var x = Vec[Int].new();
  var c = 0;
  while c < emb {
    let xv: Int = embed[token_id * emb + c];
    x.push(xv);
    c = c + 1;
  }
  let xnr = llm_rmsnorm_i32(&x, &gamma1, 0, 0);
  if !xnr.is_ok {
    let en: Str = xnr.error;
    return _err_ids(en);
  }
  let xn: Vec[Int] = xnr.value;
  let qr = llm_matmul_i32(&wq, emb, emb, &xn, 1);
  if !qr.is_ok {
    let eq: Str = qr.error;
    return _err_ids(eq);
  }
  let q0: Vec[Int] = qr.value;
  let kr = llm_matmul_i32(&wk, emb, emb, &xn, 1);
  if !kr.is_ok {
    let ek: Str = kr.error;
    return _err_ids(ek);
  }
  let k0: Vec[Int] = kr.value;
  let vr = llm_matmul_i32(&wv, emb, emb, &xn, 1);
  if !vr.is_ok {
    let ev: Str = vr.error;
    return _err_ids(ev);
  }
  let v0: Vec[Int] = vr.value;
  // Position-0 RoPE: the exact identity table (2^shift, 0).
  let s = 12;
  var cq = Vec[Int].new();
  var sq = Vec[Int].new();
  var hp = 0;
  while hp < emb / 2 {
    cq.push(1 << s);
    sq.push(0);
    hp = hp + 1;
  }
  let qrr = llm_rope_i32(&q0, emb, &cq, &sq, s);
  if !qrr.is_ok {
    let eqr: Str = qrr.error;
    return _err_ids(eqr);
  }
  let q: Vec[Int] = qrr.value;
  let krr = llm_rope_i32(&k0, emb, &cq, &sq, s);
  if !krr.is_ok {
    let ekr: Str = krr.error;
    return _err_ids(ekr);
  }
  let k: Vec[Int] = krr.value;
  let dr = llm_dot_i32(&q, &k);
  if !dr.is_ok {
    let ed: Str = dr.error;
    return _err_ids(ed);
  }
  let dot: Int = dr.value;
  let score = dot / 2;
  var sc = Vec[Int].new();
  sc.push(score);
  let smr = llm_softmax_i32(&sc, 10);
  if !smr.is_ok {
    let esm: Str = smr.error;
    return _err_ids(esm);
  }
  // Single-position attention: the softmax weight is 1 -> attn = v0.
  let wovr = llm_matmul_i32(&wo, emb, emb, &v0, 1);
  if !wovr.is_ok {
    let ewo: Str = wovr.error;
    return _err_ids(ewo);
  }
  let wov: Vec[Int] = wovr.value;
  var h = Vec[Int].new();
  var hi = 0;
  while hi < emb {
    let hx: Int = x[hi];
    let hw: Int = wov[hi];
    h.push(hx + hw);
    hi = hi + 1;
  }
  let hnr = llm_rmsnorm_i32(&h, &gamma2, 0, 0);
  if !hnr.is_ok {
    let ehn: Str = hnr.error;
    return _err_ids(ehn);
  }
  let hn: Vec[Int] = hnr.value;
  let gr = llm_matmul_i32(&w1, ffn, emb, &hn, 1);
  if !gr.is_ok {
    let eg: Str = gr.error;
    return _err_ids(eg);
  }
  let gate: Vec[Int] = gr.value;
  let ur = llm_matmul_i32(&w3, ffn, emb, &hn, 1);
  if !ur.is_ok {
    let eu: Str = ur.error;
    return _err_ids(eu);
  }
  let up: Vec[Int] = ur.value;
  let ar = llm_swiglu_i32(&gate, &up, 0);
  if !ar.is_ok {
    let ea: Str = ar.error;
    return _err_ids(ea);
  }
  let a: Vec[Int] = ar.value;
  let fr = llm_matmul_i32(&w2, emb, ffn, &a, 1);
  if !fr.is_ok {
    let ef: Str = fr.error;
    return _err_ids(ef);
  }
  let ffnv: Vec[Int] = fr.value;
  var h2 = Vec[Int].new();
  var hj = 0;
  while hj < emb {
    let hx2: Int = h[hj];
    let hf: Int = ffnv[hj];
    h2.push(hx2 + hf);
    hj = hj + 1;
  }
  let lr = llm_matmul_i32(&wout, vsz, emb, &h2, 1);
  if !lr.is_ok {
    let el: Str = lr.error;
    return _err_ids(el);
  }
  let logits: Vec[Int] = lr.value;
  return _ok_ids(logits);
}

// --- deterministic seeded PRNG (32-bit LCG; SPEC.md 10.5) ---

/// Normalize a seed into the PRNG state domain [0, 2^32).
pub fn llm_rng_seed(seed: Int) -> Int {
  let m = 4294967296;
  var v = seed % m;
  if v < 0 {
    v = v + m;
  }
  return v;
}

/// Advance the LCG state: `s -> (1664525*s + 1013904223) mod 2^32`. Exact on
/// the stated domain (the product stays far below the Int ceiling).
pub fn llm_rng_next(state: Int) -> Int {
  let m = 4294967296;
  var s = state % m;
  if s < 0 {
    s = s + m;
  }
  let prod = 1664525 * s + 1013904223;
  return prod % m;
}

/// Uniform integer in [0, bound) from a state; 0 when `bound <= 0`.
pub fn llm_rng_below(state: Int, bound: Int) -> Int {
  if bound <= 0 {
    return 0;
  }
  let m = 4294967296;
  var s = state % m;
  if s < 0 {
    s = s + m;
  }
  return s % bound;
}

// --- samplers ---

/// Argmax with lowest-index tie-break. Error: `llm: sampler empty logits`.
pub fn llm_greedy_next(logits: &Vec[Int]) -> Result[Int, Str] {
  if logits.len() == 0 {
    return _err_int("llm: sampler empty logits");
  }
  var best = 0;
  var bv: Int = logits[0];
  var i = 1;
  while i < logits.len() {
    let v: Int = logits[i];
    if v > bv {
      bv = v;
      best = i;
    }
    i = i + 1;
  }
  return _ok_int(best);
}

/// Temperature scale: `out[i] = round_half_away(logits[i] * t_den / t_num)`,
/// i.e. divide the logits by `T = t_num / t_den` (T > 1 flattens the
/// distribution, T < 1 sharpens it); `t_num == t_den` is the identity.
/// Errors: `llm: sampler temperature not positive`, `llm: sampler overflow`.
pub fn llm_apply_temperature(logits: &Vec[Int], t_num: Int, t_den: Int) -> Result[Vec[Int], Str] {
  if t_num <= 0 || t_den <= 0 {
    return _err_ids("llm: sampler temperature not positive");
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < logits.len() {
    let v: Int = logits[i];
    if _mul_ovf(v, t_den) {
      return _err_ids("llm: sampler overflow");
    }
    out.push(_idiv_round(v * t_den, t_num));
    i = i + 1;
  }
  return _ok_ids(out);
}

/// Top-k membership mask over `logits`, written in index order into `keep`
/// (which callers pass empty). The k largest logits are kept, ties broken to
/// the lower index. `k <= 0` or `k >= n` keeps all. Returns the kept count.
/// Error: `llm: sampler empty logits`.
pub fn llm_top_k_keep(logits: &Vec[Int], k: Int, keep: &mut Vec[Int]) -> Result[Int, Str] {
  let n = logits.len();
  if n == 0 {
    return _err_int("llm: sampler empty logits");
  }
  if k <= 0 || k >= n {
    var a = 0;
    while a < n {
      keep.push(1);
      a = a + 1;
    }
    return _ok_int(n);
  }
  var kept = 0;
  var i = 0;
  while i < n {
    let vi: Int = logits[i];
    var greater = 0;
    var j = 0;
    while j < n {
      let vj: Int = logits[j];
      if vj > vi {
        greater = greater + 1;
      } else if vj == vi && j < i {
        greater = greater + 1;
      }
      j = j + 1;
    }
    if greater < k {
      keep.push(1);
      kept = kept + 1;
    } else {
      keep.push(0);
    }
    i = i + 1;
  }
  return _ok_int(kept);
}

/// Top-p (nucleus) membership mask over `probs` (softmax mass summing to
/// `2^shift`): rank tokens by probability (descending, lower index on ties)
/// and keep the shortest prefix whose cumulative mass reaches `p_q`. Always
/// keeps at least the single highest-probability token; `p_q <= 0` keeps only
/// that token. The mask is written in index order into `keep` (passed empty).
/// Returns the kept count. Error: `llm: sampler empty logits`.
pub fn llm_top_p_keep(probs: &Vec[Int], p_q: Int, keep: &mut Vec[Int]) -> Result[Int, Str] {
  let n = probs.len();
  if n == 0 {
    return _err_int("llm: sampler empty logits");
  }
  // rank[i] = number of strictly better entries (prob desc, lower-index tie).
  var rank = Vec[Int].new();
  var i = 0;
  while i < n {
    let vi: Int = probs[i];
    var r = 0;
    var j = 0;
    while j < n {
      let vj: Int = probs[j];
      if vj > vi {
        r = r + 1;
      } else if vj == vi && j < i {
        r = r + 1;
      }
      j = j + 1;
    }
    rank.push(r);
    i = i + 1;
  }
  // Minimal prefix count whose cumulative probability reaches p_q (>= 1).
  var count = 1;
  var cum = 0;
  var c = 0;
  while c < n && cum < p_q {
    var idx = -1;
    var k = 0;
    while k < n {
      let rk: Int = rank[k];
      if rk == c {
        idx = k;
      }
      k = k + 1;
    }
    if idx >= 0 {
      let pv: Int = probs[idx];
      cum = cum + pv;
      count = c + 1;
    }
    c = c + 1;
  }
  var kept = 0;
  var t = 0;
  while t < n {
    let rt: Int = rank[t];
    if rt < count {
      keep.push(1);
      kept = kept + 1;
    } else {
      keep.push(0);
    }
    t = t + 1;
  }
  return _ok_int(kept);
}

/// Draw one token id from `probs` restricted to the `keep` mask, using a
/// uniform integer draw from `state` (advance the state with `llm_rng_next`
/// between steps). When the kept mass is zero it falls back to the highest
/// kept probability. Errors: `llm: sampler empty logits`,
/// `llm: sampler keep size mismatch`, `llm: sampler zero mass`.
pub fn llm_sample_choice(probs: &Vec[Int], keep: &Vec[Int], state: Int) -> Result[Int, Str] {
  let n = probs.len();
  if n == 0 {
    return _err_int("llm: sampler empty logits");
  }
  if keep.len() != n {
    return _err_int("llm: sampler keep size mismatch");
  }
  var total = 0;
  var i = 0;
  while i < n {
    let kv: Int = keep[i];
    if kv != 0 {
      let pv: Int = probs[i];
      if pv > 0 {
        total = total + pv;
      }
    }
    i = i + 1;
  }
  if total <= 0 {
    var best = -1;
    var bv = 0;
    var j = 0;
    while j < n {
      let kv2: Int = keep[j];
      if kv2 != 0 {
        let pv2: Int = probs[j];
        if best < 0 || pv2 > bv {
          bv = pv2;
          best = j;
        }
      }
      j = j + 1;
    }
    if best < 0 {
      return _err_int("llm: sampler zero mass");
    }
    return _ok_int(best);
  }
  let r = llm_rng_below(state, total);
  var cum = 0;
  var k = 0;
  while k < n {
    let kv3: Int = keep[k];
    if kv3 != 0 {
      let pv3: Int = probs[k];
      if pv3 > 0 {
        cum = cum + pv3;
        if r < cum {
          return _ok_int(k);
        }
      }
    }
    k = k + 1;
  }
  return _err_int("llm: sampler zero mass");
}

/// Greedy sampler configuration (argmax; deterministic, seed unused).
pub fn llm_sampler_greedy() -> LlmSampler {
  return LlmSampler{ greedy: 1; t_num: 1; t_den: 1; top_k: 0; top_p_q: 0; shift: 10; seed: 0; };
}

/// Seeded sampler configuration: temperature `t_num / t_den`, top-k and
/// top-p filters, softmax shift and RNG seed (see `LlmSampler`).
pub fn llm_sampler_seeded(seed: Int, t_num: Int, t_den: Int, top_k: Int, top_p_q: Int, shift: Int) -> LlmSampler {
  return LlmSampler{ greedy: 0; t_num: t_num; t_den: t_den; top_k: top_k; top_p_q: top_p_q; shift: shift; seed: seed; };
}

/// Sample the next token id from `logits` under sampler `s`, using the RNG
/// `state` for the uniform draw. Greedy (`s.greedy != 0`) is argmax; otherwise
/// temperature -> softmax -> top-k -> top-p -> draw. Errors: `llm: sampler
/// empty logits`, any temperature overflow, any softmax error.
pub fn llm_sample_next(logits: &Vec[Int], s: &LlmSampler, state: Int) -> Result[Int, Str] {
  if logits.len() == 0 {
    return _err_int("llm: sampler empty logits");
  }
  if s.greedy != 0 {
    return llm_greedy_next(logits);
  }
  let tr = llm_apply_temperature(logits, s.t_num, s.t_den);
  if !tr.is_ok {
    let e: Str = tr.error;
    return _err_int(e);
  }
  let adj: Vec[Int] = tr.value;
  let sr = llm_softmax_i32(&adj, s.shift);
  if !sr.is_ok {
    let e2: Str = sr.error;
    return _err_int(e2);
  }
  let probs: Vec[Int] = sr.value;
  var kk = Vec[Int].new();
  let kr = llm_top_k_keep(&adj, s.top_k, &mut kk);
  if !kr.is_ok {
    let e3: Str = kr.error;
    return _err_int(e3);
  }
  var pk = Vec[Int].new();
  let pr = llm_top_p_keep(&probs, s.top_p_q, &mut pk);
  if !pr.is_ok {
    let e4: Str = pr.error;
    return _err_int(e4);
  }
  var keep = Vec[Int].new();
  var i = 0;
  while i < probs.len() {
    let a: Int = kk[i];
    let b: Int = pk[i];
    if a != 0 && b != 0 {
      keep.push(1);
    } else {
      keep.push(0);
    }
    i = i + 1;
  }
  return llm_sample_choice(&probs, &keep, state);
}

/// True when `id` equals the stop token `stop_id`; a negative `stop_id`
/// disables stopping.
pub fn llm_is_stop(id: Int, stop_id: Int) -> Bool {
  if stop_id < 0 {
    return false;
  }
  return id == stop_id;
}

/// Generation loop over the single-position forward pass: starting from the
/// last prompt id, repeatedly forward -> sample -> append, stopping when the
/// sampled id equals `stop_id` (the stop token is appended) or after `max_new`
/// steps. `out_ids` receives the generated ids (passed in, appended to).
/// Returns the number of generated ids. Error: `llm: generate empty prompt`
/// plus any forward or sampler error. Note: no KV cache in this milestone, so
/// each step conditions only on the current token (SPEC.md 10.5).
pub fn llm_generate(model: &LlmModel, buf: &Vec[UInt8], prompt_ids: &Vec[Int], max_new: Int, stop_id: Int, s: &LlmSampler, out_ids: &mut Vec[Int]) -> Result[Int, Str] {
  if prompt_ids.len() == 0 {
    return _err_int("llm: generate empty prompt");
  }
  if max_new <= 0 {
    return _ok_int(0);
  }
  let lastp = prompt_ids.len() - 1;
  var cur: Int = prompt_ids[lastp];
  var state = llm_rng_seed(s.seed);
  var step = 0;
  while step < max_new {
    let lr = llm_forward_token(model, buf, cur);
    if !lr.is_ok {
      let e: Str = lr.error;
      return _err_int(e);
    }
    let logits: Vec[Int] = lr.value;
    let idr = llm_sample_next(&logits, s, state);
    if !idr.is_ok {
      let e2: Str = idr.error;
      return _err_int(e2);
    }
    let id: Int = idr.value;
    out_ids.push(id);
    step = step + 1;
    if llm_is_stop(id, stop_id) {
      return _ok_int(step);
    }
    state = llm_rng_next(state);
    cur = id;
  }
  return _ok_int(step);
}
