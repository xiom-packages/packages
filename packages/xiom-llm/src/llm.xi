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
//   * string-array elements are read through a local workaround for an
//     observed xiom.gguf 0.1.2 parse-offset defect (XGGUF-ARRSTR; see the
//     _arr_str_origin comment below and SPEC.md section 9).
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

// True for array element type codes whose parsed elements are stored in
// `Gguf.arr_strs` (strings and the raw-byte hex forms of f32/f64).
fn _elem_in_arr_strs(et: Int) -> Bool {
  return et == 6 || et == 8 || et == 12;
}

// Workaround origin for entry `i`'s string-array elements (XGGUF-ARRSTR).
//
// Observed on xiom.gguf 0.1.2 (24/24 conformance suite green, which does
// not exercise string arrays): `gguf_parse` initializes the per-entry array
// origin as `g.arr_ints.len()` (src/gguf.xi, `_parse_kv_value`), which is
// the correct origin only for integer arrays. For an array whose elements
// live in `arr_strs` the recorded `kv_arr_off` is therefore 0 (or some
// stale `arr_ints` length), and `gguf_kv_arr_str` then returns elements of
// an EARLIER string array (the first one is accidentally right only because
// it starts at 0 with no int-array contamination).
//
// The parse itself appends `arr_strs` elements in KV declaration order, so
// the true origin is recoverable: the number of `arr_strs` elements
// contributed by all earlier KVs. This helper computes exactly that;
// xiom.llm reads string-array elements through it and never through the
// recorded offset. The builder side of xiom.gguf is unaffected (it records
// `arr_strs.len()` at add time and its bytes are exact). Reported to the
// lane coordinator for an upstream xiom.gguf patch; the workaround is
// local and can be deleted once a fixed xiom.gguf lands.
fn _arr_str_origin(g: &Gguf, i: Int) -> Int {
  let types: Vec[Int] = g.kv_types;
  let ats: Vec[Int] = g.kv_arr_type;
  let cnts: Vec[Int] = g.kv_arr_count;
  var sum = 0;
  var j = 0;
  while j < i {
    let t: Int = types[j];
    if t == 9 {
      let et: Int = ats[j];
      let c: Int = cnts[j];
      if _elem_in_arr_strs(et) {
        sum = sum + c;
      }
    }
    j = j + 1;
  }
  return sum;
}

// String-array element `e` of entry `i` through the recovered origin.
// Callers pre-validate `cnt`; the failure arm is defensive only and maps to
// the caller's own deterministic message.
fn _arr_str_at(g: &Gguf, i: Int, e: Int, cnt: Int) -> Result[Str, Str] {
  if e < 0 || e >= cnt {
    return _err_str("llm: array element out of range");
  }
  let off = _arr_str_origin(g, i);
  let sv: Vec[Str] = g.arr_strs;
  if off + e >= sv.len() {
    return _err_str("llm: array element out of range");
  }
  let s: Str = sv[off + e];
  return _ok_str(s);
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
    let er = _arr_str_at(g, ti, e, n_tokens);
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
    let mr2 = _arr_str_at(g, gi, m, n_merges);
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
