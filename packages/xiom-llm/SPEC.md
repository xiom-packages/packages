<!-- XIOM -- xiom.llm specification -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.llm -- specification

Version: 0.1.0 (incubating; not yet published).
Module: `src/llm.xi` (`module xiom.llm`).

## 1. Scope

The llama.cpp-family runner tier of the XIOM ML/AI coverage program. This
document specifies the **full runner surface**; milestone 1 (this release)
implements the vocabulary/tokenizer core, and the remaining sections are
declared designs that later milestones implement (each marked
**[DECLARED -- NOT IMPLEMENTED in 0.1.0]**).

Implemented in 0.1.0:

* in-GGUF vocab extraction from a header parsed by `xiom.gguf` (metadata
  -> `LlmVocab`, section 5);
* byte-level BPE tokenizer with llama.cpp-family merge-table semantics:
  decode and encode (section 6).

Declared for later milestones (section 10):

* GGUF payload/tensor loading over `xiom.gguf` header data;
* deterministic float-free numerics for dequantization (Q8_0 first,
  Q4_K-class later);
* matmul / forward-pass composition (over `xiom.tensor` where sensible);
* generation loop (greedy first; sampling deferred).

## 2. Non-goals

* No training, fine-tuning, gradient computation, optimizer state.
* No float arithmetic anywhere in the runner core: floats are preserved as
  raw little-endian bytes (hex) exactly as `xiom.gguf` stores them; all
  planned compute is integer/scaled-int (sections 10.3-10.5).
* No simulator/placeholder model: the M2 fixture is a real (tiny) GGUF
  container with real tensor payload bytes.
* No GPU backends, no mmap/streaming IO, no multi-file shards (split GGUF)
  in M1/M2; whole-buffer parsing in memory.
* No sampling strategies beyond greedy argmax until the generation-loop
  milestone declares them (temperature/top-k/top-p are deferred).
* No UTF-8 vocabularies in M1: `xiom.gguf` parses printable-ASCII strings
  only (see section 4).

## 3. Dependencies and references

* `xiom.std >=0.60.0 <1.0.0` -- `xiom.string`, `xiom.string.compare`
  (library); `xiom.test`, `xiom.io`, `xiom.convert` (tests).
* `xiom.gguf` (0.1.2) -- GGUF header codec: parse, KV accessors, tensor
  infos, builder. Consumed as a path dependency in `xiom.toml`
  (`../xiom-gguf`); the canonical lane manifest is `package.xi`.
* `xiom.tensor` (0.1.0) -- integer n-d tensor core, reserved for the M2
  forward-pass plan (section 10.5).
* llama.cpp reference (read-only, MIT): commit
  `23f7aabc16c72f6f707dba227251c35d7bd1ed96` (2026-10-16, "model :
  Granite Switch Decision (#30676)"), light clone `--depth 1`. Semantics
  were read from `src/llama-vocab.cpp` and `src/unicode.cpp`; no code was
  copied.

## 4. Container integration (over xiom.gguf)

`xiom.gguf` parses the GGUF v2/v3 header: metadata KV table and tensor-info
table, with `f32`/`f64` values as raw-byte hex and strings restricted to
printable ASCII (0x20..0x7E). xiom.llm consumes the parsed `Gguf` value;
it never re-parses bytes in M1.

Metadata keys read by `llm_vocab_from_gguf` (all in the
`tokenizer.ggml.` family, the llama.cpp names):

| Key | Type | Required | Meaning |
|---|---|---|---|
| `tokenizer.ggml.model` | string | yes | tokenizer family; M1 requires exactly `gpt2` |
| `tokenizer.ggml.tokens` | string array | yes | token id -> token string (id = index) |
| `tokenizer.ggml.merges` | string array | yes (gpt2) | merge table; rank = index |
| `tokenizer.ggml.token_type` | integer array | no | per-token type; default 1 (normal) |
| `tokenizer.ggml.bos_token_id` | integer | no | BOS id; -1 when absent |
| `tokenizer.ggml.eos_token_id` | integer | no | EOS id; -1 when absent |

Tensor infos (names, dims, ggml types, offsets, data section) are visible
through `xiom.gguf` and are the input of the M2 loading plan (section
10.2); M1 does not read them.

## 5. Vocab extraction semantics (implemented)

`llm_vocab_from_gguf(g: &Gguf) -> Result[LlmVocab, Str]`, in order:

1. `tokenizer.ggml.model` must exist, be a string (GGUF type 8) and equal
   `gpt2`; anything else is an error (section 7).
2. `tokenizer.ggml.tokens` must exist and be an array of strings (GGUF
   value type 9, element type 8). The elements are copied in order; token
   id = index. An empty list is accepted (every later lookup then fails
   closed at use sites).
3. `tokenizer.ggml.merges` must exist and be an array of strings. Each
   entry is split at the **first space at byte index >= 1** (llama.cpp
   `word.find(' ', 1)`): `left = entry[0..pos]`,
   `right = entry[pos+1..len]`. An entry without such a space is stored as
   the dead pair `("", "")`: it occupies its rank index but can never match
   a symbol pair (symbols are never empty). Duplicate pairs resolve to the
   **lowest** index (llama.cpp `emplace` first-wins).
4. `tokenizer.ggml.token_type`, when present, must be an integer-element
   array whose element count is >= the token count; the first
   `n_tokens` values are stored. When absent, every token reports type 1
   (`LLAMA_TOKEN_TYPE_NORMAL`, the llama.cpp default attribute).
   Documented relaxation: any GGUF integer element type (0..5, 7, 10, 11)
   is accepted; the canonical converter output is i32.
5. `tokenizer.ggml.bos_token_id` / `eos_token_id`, when present, must be
   integer values; they are stored verbatim (no range check; -1 when
   absent).

`LlmVocab` invariants: `token_types.len() == tokens.len()`;
`merge_l.len() == merge_r.len()`; `has_types` is 0/1; `bos`/`eos` are -1
when absent. A value is only produced by `llm_vocab_from_gguf`.

Accessors (all pure; Str values are copies):

| Function | Returns | Notes |
|---|---|---|
| `llm_vocab_model(v)` | `Str` | "gpt2" in M1 |
| `llm_vocab_size(v)` | `Int` | `tokens.len()` |
| `llm_vocab_token(v, i)` | `Result[Str, Str]` | Err when i outside 0..size-1 |
| `llm_vocab_token_type(v, i)` | `Result[Int, Str]` | stored value or 1; Err when out of range |
| `llm_vocab_bos(v)` / `llm_vocab_eos(v)` | `Int` | -1 when absent |
| `llm_vocab_merge_count(v)` | `Int` | rank count |
| `llm_vocab_merge(v, i)` | `Result[Str, Str]` | `left + " " + right` (dead: single space) |
| `llm_vocab_find_token(v, s)` | `Int` | id or -1; duplicate strings resolve to the **highest** id (llama.cpp `token_to_id` overwrite) |

## 6. Byte-level BPE semantics (implemented)

M1 operates on a **printable-ASCII byte domain** (0x20..0x7E): that is the
only domain representable in a `Gguf` string today. Two llama.cpp stages
are therefore deferred (declared in section 10.6): the GPT-2
`bytes_to_unicode` escape layer (`unicode_byte_to_utf8`, identity only for
0x21..0x7E; byte 0x20 escapes to the non-ASCII `U+0120`) and the regex
pre-tokenizer (`unicode_regex_split`). M1's synthetic fixture stores the
space as a literal token, i.e. the escape is the identity **by fixture
construction**, not by file semantics.

`llm_bpe_encode(v, text) -> Result[Vec[Int], Str]`:

1. Empty text -> empty id list.
2. The whole text is one work chunk; symbols start as single-byte strings
   (in order).
3. While `symbols.len() >= 2`: find the fresh adjacent pair with the
   minimum merge rank, ties resolved to the **leftmost** pair (llama.cpp
   work-queue priority: rank ascending, left index ascending); merge that
   one occurrence (replace the two symbols by their concatenation);
   repeat. Pairs with no rank are never merged. This reproduces the
   llama.cpp queue algorithm: one merge per step, new candidate pairs
   formed by a merge are reconsidered immediately, stale entries skipped.
4. Each final symbol must exist in the vocabulary as an exact token
   string (last-wins on duplicates); the id list follows left to right.
   Failure: a 1-byte symbol -> `llm: byte not in vocabulary`; a longer
   symbol -> `llm: symbol not in vocabulary`.

`llm_bpe_decode(v, ids) -> Result[Str, Str]`: concatenation of the token
strings; empty list -> `""`; an id outside 0..size-1 ->
`llm: token id out of range`. Over the M1 domain this is the byte-exact
inverse of encode for every text whose encode succeeds.

Roundtrip guarantees (conformance-pinned): `decode(encode(x)) == x` for
all fixture texts; `encode(decode(ids)) == ids` for encode-produced id
lists.

## 7. Error catalog (exact messages)

Extraction (`Result[LlmVocab, Str]` from `llm_vocab_from_gguf`):

* `llm: tokenizer model missing`
* `llm: tokenizer model is not a string`
* `llm: unsupported tokenizer model`
* `llm: tokenizer tokens missing`
* `llm: tokenizer tokens is not a string array`
* `llm: tokenizer merges missing`
* `llm: tokenizer merges is not a string array`
* `llm: token types are not an integer array`
* `llm: token type count smaller than token count`
* `llm: bos token id is not an integer`
* `llm: eos token id is not an integer`

Accessors and tokenizer:

* `llm: token index out of range` (token / token_type)
* `llm: merge index out of range` (merge)
* `llm: byte not in vocabulary` (encode)
* `llm: symbol not in vocabulary` (encode)
* `llm: token id out of range` (decode)
* `llm: array element out of range` (defensive, internal workaround path
  only -- pre-validation makes it unreachable through the public API)

## 8. Documented deviations from llama.cpp (M1)

1. **Fail-closed symbol lookup.** llama.cpp's BPE session falls back to
   per-character byte tokens for an unknown final symbol and silently
   drops bytes with no token. M1 fails closed with the deterministic
   errors above (no silent data loss).
2. **ASCII domain / escape layer deferred.** See section 6; real
   (non-ASCII) vocabularies cannot be read until `xiom.gguf` accepts the
   GPT-2 escaped strings (M3 item).
3. **No regex pre-tokenizer.** llama.cpp splits text with model-family
   regexes before BPE. M1 treats the whole input as one chunk; that is
   byte-exact equivalent whenever no regex chunk boundary falls inside a
   token span, and is the declared starting point for the fixture domain.
4. **token_type element type.** llama.cpp requires the array element type
   to be i32 exactly; M1 accepts any GGUF integer element type.
5. **token_type longer than tokens.** Both accept longer arrays (extra
   values ignored); M1 errors when the count is *smaller*, same as
   llama.cpp.
6. **No special-token partitioning.** llama.cpp splits special tokens
   (`<s>`, `</s>`, ...) by their attrs before BPE and can add BOS/EOS per
   model flags; M1 encodes raw text only (BOS/EOS insertion is declared
   for M3 alongside the generation loop).

## 9. XGGUF-ARRSTR: string-array offset workaround (observed defect)

While building the M1 fixture we observed that **`xiom.gguf` 0.1.2
mis-reads every string array that does not start at `arr_strs[0]`**:

* Evidence (debug probe, 2026-10-16): a built header with two string
  arrays (`tokenizer.ggml.tokens` then `tokenizer.ggml.merges`) parses
  fine, but `gguf_kv_arr_str` on the second array returns elements of the
  first (entry `"h e"` read back as `"h"`; single-array headers read
  correctly). The built bytes are exact -- the first array's payload is
  found verbatim in the buffer -- so the defect is parse-side only.
* Root cause: `_parse_kv_value` (src/gguf.xi) initializes the per-entry
  origin as `g.arr_ints.len()`; string/hex-float arrays (element types 6,
  8, 12) append to `g.arr_strs`, so their recorded `kv_arr_off` is 0 (or
  a stale int count) instead of the true `arr_strs` origin. The 24/24
  conformance suite does not cover string arrays, hence green.
* Workaround in xiom.llm: `_arr_str_origin(g, i)` recomputes the true
  origin as the `arr_strs` element count contributed by all earlier KVs
  (parse order is declaration order), and `_arr_str_at` reads through it.
  The builder side needs no workaround.
* Exit plan: report to the lane coordinator for an upstream fix
  (change the origin to `arr_strs.len()` for element types 6/8/12 in
  `_parse_kv_value`, add an array-of-strings conformance case); delete
  the workaround here once a fixed `xiom.gguf` is pinned.

## 10. Declared runner surface [DECLARED -- NOT IMPLEMENTED in 0.1.0]

Signatures below are the planned public surface; they are not present in
`src/llm.xi` yet. Milestone mapping is in ROADMAP.md.

### 10.1 GGUF payload and tensor loading

`xiom.gguf` bounds-checks declared tensor offsets against the data-section
length but has no ggml element-size table. xiom.llm supplies it:

* `llm_ggml_type_name(t: Int) -> Str` -- "f32", "f16", "q4_0", "q8_0", ...
* `llm_ggml_block_elems(t: Int) -> Int` -- elements per block (f32/f16: 1;
  q4_0/q4_1/q5_0/q5_1/q8_0: 32; q2_K..q6_K: 256).
* `llm_ggml_block_bytes(t: Int) -> Int` -- bytes per block (f32: 4; f16:
  2; q4_0: 18; q8_0: 34; ...).
* `llm_tensor_nbytes(g: &Gguf, ti: Int) -> Result[Int, Str]` -- product of
  dims / block_elems * block_bytes, exact integer arithmetic; errors on
  non-divisible dims and unknown ggml types.
* `llm_tensor_data(g: &Gguf, buf: &Vec[UInt8], ti: Int) -> Result[Vec[UInt8], Str]`
  -- copies the tensor's payload slice out of the container buffer
  (`data_offset + offset`, `nbytes`), after validating the extent against
  `gguf_data_len`.
* `llm_model_open(header: &Vec[UInt8], payload: &Vec[UInt8]) -> Result[LlmModel, Str]`
  -- composite: parse header, extract vocab, validate every tensor extent
  against the payload; callers may pass one concatenated container buffer.

### 10.2 Deterministic float-free numerics plan

All planned numerics stay in `Int` (no `Float64`/`Float32` arithmetic:
`xiom.tensor` is integer-only and the toolchain has no `Vec[Float64]`).
The representation:

* f16 and f32 factors are decoded **bit-by-bit with integer ops** into
  `(sign, mantissa, exponent)` triples (llama.cpp's `ggml_fp16_to_fp32`
  bit trick, reproduced with shifts/masks);
* every dequantized tensor is a **scaled-int array**: `values[i] = q[i] *
  m` with a shared pair `(m: Int, e: Int)` such that the exact real value
  is `q[i] * m / 2^e`; `m` and `e` come from the block scale's
  decoded mantissa/exponent;
* rounding is round-half-away-from-zero on integer division, applied at
  declared points only; the maximum error of each step is documented next
  to the step (mirroring the `xiom.inference` shift-quantization style);
* f32/f64 metadata values stay opaque raw-byte hex exactly as `xiom.gguf`
  delivers them; a tensor-embedded f32 is only ever decoded by the
  integer bit routine above.

### 10.3 Dequantization

* `llm_dequant_q8_0(payload: &Vec[UInt8], out_values: &mut Vec[Int]) -> Result[LlmScale, Str]`
  -- Q8_0 first: blocks of 32 x i8 quants + f16 scale; values scaled-int.
* `llm_dequant_q4_k(payload: &Vec[UInt8], out_values: &mut Vec[Int]) -> Result[LlmScale, Str]`
  -- Q4_K-class later: 256-value superblocks, f16 d/dmin, 6-bit
  sub-scales, 4-bit quants.
* Every dequantizer validates the payload length against the block table
  and returns the block scale as `(m, e)` plus per-block sub-scales where
  the class requires them.

### 10.4 Matmul / forward-pass composition

* `llm_matmul_i32(a: &Vec[Int], a_rows: Int, a_cols: Int, b: &Vec[Int], b_cols: Int) -> Result[Vec[Int], Str]`
  -- flat row-major integer matmul with overflow-checked accumulation
  (fail closed, no wraparound), the workhorse for every weight multiply.
* `xiom.tensor` is used where it fits the integer model: shape
  construction (`tensor_from_flat`), geometry accessors, axis slicing for
  row windows, and canonical `tensor_dump` diagnostics. It has no matmul,
  views or elementwise scaled-int ops, so the hot kernels stay in-package
  over flat `Vec[Int]`; this boundary is the "over xiom.tensor where
  sensible" contract.
* Forward composition (llama-style skeleton for the M2 fixture):
  token embedding row gather -> RMSNorm (integer rsqrt plan) -> Q/K/V
  projections via `llm_matmul_i32` -> RoPE (integer sin/cos table,
  declared in M2) -> scaled attention scores -> softmax plan (integer
  exp/max normalization, declared with error bounds) -> output projection
  -> SwiGLU FFN -> logits.

### 10.5 Generation loop

* `llm_greedy_next(logits: &Vec[Int]) -> Result[Int, Str]` -- argmax with
  lowest-index tie-break; the only sampler in M2/M3.
* `llm_generate(model: &LlmModel, prompt_ids: &Vec[Int], max_new: Int, out_ids: &mut Vec[Int]) -> Result[Int, Str]`
  -- decode-loop composition with a KV cache plan (append-only per layer);
  stops at EOS or `max_new`. Temperature/top-k/top-p sampling is declared
  for a later milestone (section 2).

### 10.6 Tokenizer milestones (deferred pieces)

* GPT-2 `bytes_to_unicode` escape/unescape layer (requires non-ASCII GGUF
  strings; blocked on `xiom.gguf` string domain).
* Regex pre-tokenizer families (at minimum the GPT-2/llama3 expressions
  from `llama-vocab.cpp`) with a documented subset guarantee.
* SPM (`tokenizer.ggml.model == "llama"`) and WPM (`"bert"`)
  vocabulary extraction + their tokenize paths.

## 11. Test matrix (38 checks, `tests/test_conformance.xi`)

All checks run against a synthetic deterministic fixture built with
`xiom.gguf`'s builder: 6 metadata KVs, one tensor info
(`token_embd.weight`, 20 x 2, ggml type 0, offset 0) and a 32-byte zero
payload appended after the header. Vocab: 20 tokens (ids 0..19: single
bytes `h e l o w r d ' ' !`, the merge results `he ll hell hello wo wor
worl world lo`, control tokens `<s>`/`</s>` at ids 18/19); merge table
ranks 0..9 with rank 9 a dead pair (`"q"`); token types 1 except 3 for
the two control tokens; bos/eos 18/19.

| # | Check |
|---|---|
| 1 | fixture parses (6 KVs, 1 tensor, 32-byte data section) |
| 2 | extraction: model gpt2, size 20 |
| 3 | token strings (`h`, `hello`, `</s>`) |
| 4 | token types (1 normal, 3 control) |
| 5 | bos/eos ids (18/19) |
| 6 | find_token hit/miss (12, -1) |
| 7 | merge table: count 10, `"h e"`, `"hell o"`, dead pair `" "` |
| 8 | accessor range errors (token/token_type/merge) |
| 9 | decode [12], [12,7,16,8], [11,7,16,8] |
| 10 | decode [] |
| 11 | encode "hello", "hello world", "hell world!" |
| 12 | encode "held" (partial merge), "lol" |
| 13 | encode "llll" (leftmost tie-break: [10,10]), " " |
| 14 | encode "" |
| 15 | decode(encode(x)) == x for 8 texts |
| 16 | encode(decode(ids)) == ids |
| 17 | unknown byte fails closed |
| 18 | decode id range errors (20, -1) |
| 19-27 | extraction error catalog (unsupported/missing/non-string model, missing/int tokens, missing merges, short/string token_type, non-integer bos) |
| 28 | plain header: token types default 1, bos/eos -1 |

## 12. Compiler notes (v0.64.5)

Free functions only; `Ok`/`Err` construction is confined to the leaf
helpers in `src/llm.xi`; `Str` values read from vectors and struct fields
are bound to typed locals and compared with `str_compare` (never `==`);
every `UInt8` is widened with `(as Int) & 0xFF`; `&struct.field` is never
passed where a `&Vec[...]` parameter is expected; test Result values are
unwrapped through locals (`let r = f(); let v = r.value;`), never by
chaining `.value` on a call. No contracts are declared on the M1
functions (lane policy for new names).

## 13. Reference notes

* llama.cpp commit `23f7aabc16c72f6f707dba227251c35d7bd1ed96`
  (2026-10-16). Files consulted: `src/llama-vocab.cpp`
  (`llm_tokenizer_bpe`, `llm_tokenizer_bpe_session`, vocab load for
  `"gpt2"`), `src/unicode.cpp` (`unicode_regex_split`,
  `unicode_byte_to_utf8`), `include/llama.h` (token type enum). Light
  clone `git clone --depth 1 https://github.com/ggml-org/llama.cpp`,
  read-only; llama.cpp is MIT-licensed (compatible).
* Merge split semantics: `llama-vocab.cpp`, `word.find(' ', 1)`.
* BPE priority: `llm_bigram_bpe::comparator` (rank asc, left asc),
  one-merge-per-step with requeue of neighbours.
* Token types: `LLAMA_TOKEN_TYPE_UNDEFINED=0, NORMAL=1, UNKNOWN=2,
  CONTROL=3, USER_DEFINED=4, UNUSED=5, BYTE=6` (`include/llama.h`).
