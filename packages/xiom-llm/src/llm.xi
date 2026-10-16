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

module xiom.llm

use xiom.string;
use xiom.string.compare;
use xiom.gguf;

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
