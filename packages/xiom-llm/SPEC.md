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

Implemented in 0.1.0 (M1 + M2):

* in-GGUF vocab extraction from a header parsed by `xiom.gguf` (metadata
  -> `LlmVocab`, section 5);
* byte-level BPE tokenizer with llama.cpp-family merge-table semantics:
  decode and encode (section 6);
* GGUF payload/tensor loading, extent validation and the `llm_model_open`
  composite (M2a/M2b, section 10.1);
* deterministic float-free numerics: integer f16/f32 bit-decode, exact
  scaled-int `(m, e)` handling and `llm_dequant_q8_0` (M2a, sections
  10.2/10.3);
* integer matmul plus the forward primitives RMSNorm / RoPE / attention
  score / softmax / SiLU-SwiGLU FFN, and a tiny deterministic model fixture
  whose single-token golden logits are asserted exactly (M2b, section 10.4);
* generation loop (M3a, section 10.5): deterministic seeded integer PRNG,
  greedy / temperature / top-k / top-p sampling, stop-token handling and a
  single-position generate loop + the `llm_forward_token` entry point.

Declared for later milestones (section 10):

* KV cache, longer-context attention, benchmark harness, Q4_K-class
  dequantization and quantization breadth (M3 second half);
* tokenizer completion: escape layer, regex pre-tokenizer, SPM/WPM
  (section 10.6).

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
  milestone declares them. M3a implements greedy argmax plus a deterministic
  integer sampler (temperature / top-k / top-p over a seeded LCG); the KV
  cache and longer-context attention remain deferred.
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

Model assembly and forward kernels (M2):

* `llm: model header parse failed`, `llm: model tensor extent invalid`
  (`llm_model_open`)
* `llm: matmul negative dimension`, `llm: matmul a size mismatch`,
  `llm: matmul b size mismatch`, `llm: matmul overflow`
* `llm: dot size mismatch`, `llm: dot overflow`
* `llm: rmsnorm empty input`, `llm: rmsnorm gamma size mismatch`,
  `llm: rmsnorm negative shift`, `llm: rmsnorm overflow`,
  `llm: rmsnorm zero norm`
* `llm: rope head_dim not even`, `llm: rope size mismatch`,
  `llm: rope table size mismatch`, `llm: rope shift too small`,
  `llm: rope overflow`
* `llm: softmax empty input`, `llm: softmax shift too small`,
  `llm: softmax overflow`, `llm: softmax zero mass`
* `llm: swiglu size mismatch`, `llm: swiglu overflow`
* `llm: f32 offset out of range`, `llm: scaled value out of range`,
  `llm: value is not an exact integer` (bit-decode bridge)

Generation, sampling and forward entry point (M3a):

* `llm: token id out of range` (`llm_forward_token`; same message as decode)
* `llm: model tensor missing`, `llm: model tensor extent invalid`
  (`llm_forward_token` weight loads)
* `llm: sampler empty logits` (greedy / temperature / top-k / top-p / choice
  / sample-next on an empty logit vector)
* `llm: sampler temperature not positive` (t_num or t_den <= 0)
* `llm: sampler overflow` (temperature scaling overflow)
* `llm: sampler keep size mismatch` (choice mask length != prob length)
* `llm: sampler zero mass` (choice with no kept probability)
* `llm: generate empty prompt` (`llm_generate` with an empty prompt list)

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
7. **Quantized tensor infos in the M2 fixture (M2b).** `xiom.gguf`'s
   builder rejects GGML types 8 (`q8_0`) and 9 (`q8_1`), so the fixture
   cannot declare a type-8 tensor. The three FFN matrices are therefore
   declared as `f32` slices whose stored payload begins with one Q8_0 block
   (34 bytes) followed by zero padding to the f32 extent;
   `llm_dequant_q8_0` consumes the leading 34 bytes. The dequant path is
   exercised on real container tensor data, but the container carries no
   type-8 tensor info. Lifting this needs a `xiom.gguf` builder change
   (out of lane scope).

## 9. XGGUF-ARRSTR: string-array offset workaround (RESOLVED)

While building the M1 fixture we observed that **`xiom.gguf` 0.1.2 mis-read
every string array that did not start at `arr_strs[0]`**:

* Evidence (debug probe, 2026-10-16): a built header with two string arrays
  (`tokenizer.ggml.tokens` then `tokenizer.ggml.merges`) parsed fine, but
  `gguf_kv_arr_str` on the second array returned elements of the first;
  single-array headers read correctly.
* Root cause: `_parse_kv_value` (src/gguf.xi) initialized the per-entry
  origin as `g.arr_ints.len()`; string/hex-float arrays (element types 6,
  8, 12) append to `g.arr_strs`, so their recorded `kv_arr_off` was 0 (or
  a stale int count) instead of the true `arr_strs` origin.
* M1 workaround: `_arr_str_origin`/`_arr_str_at` recomputed the true origin
  locally.
* **Resolution (M2a, 2026-10-16):** `xiom.gguf` 0.1.3 carries the upstream
  fix -- `_parse_kv_value` now records `aoff = g.arr_strs.len()` for element
  types 6/8/12 (src/gguf.xi line ~469). The path dependency picks the fix
  up automatically, and the `_arr_str_origin`/`_arr_str_at` workaround was
  deleted from `src/llm.xi`; string-array elements are read straight through
  `gguf_kv_arr_str`. Suite re-greened.

## 10. Declared runner surface

Signatures below are the planned public surface. **Implemented in M2a/M2b
(2026-10-16):** section 10.1 size tables / `llm_tensor_nbytes` /
`llm_tensor_data` / `llm_model_open`; section 10.2/10.3 integer bit-decode,
`llm_dequant_q8_0` and `llm_q8_0_ints`; and section 10.4 matmul
(`llm_matmul_i32`), the forward primitives and the tiny-fixture golden-logit
conformance. The generation loop (10.5) remains declared. Milestone mapping
is in ROADMAP.md.

### 10.1 GGUF payload and tensor loading

**[IMPLEMENTED in M2a; `llm_model_open` added in M2b, 2026-10-16]**

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

**[IMPLEMENTED in M2a, 2026-10-16]**

* `llm_dequant_q8_0(payload: &Vec[UInt8], out_values: &mut Vec[Int]) -> Result[LlmScale, Str]`
  -- Q8_0 first: blocks of 32 x i8 quants + f16 scale; values scaled-int.
  The f16 scale is decoded with `llm_f16_to_scaled`, so the mapping is EXACT
  integer arithmetic (pinned error bound 0). Limitation: a single shared
  block scale `(m, e)` is returned, so mixed per-block scales are rejected.
* `llm_q8_0_ints(payload: &Vec[UInt8], out_values: &mut Vec[Int]) -> Result[LlmScale, Str]`
  -- the bridge from the scaled-int `(m, e)` form into flat integer kernels:
  dequantizes then reduces by `2^e`, returning plain integer weights; fails
  closed with `llm: value is not an exact integer` when `m / 2^e` is not an
  integer (for the standard scale-1.0 blocks the result is exactly `q[i]`).
* `llm_dequant_q4_k(payload: &Vec[UInt8], out_values: &mut Vec[Int]) -> Result[LlmScale, Str]`
  -- Q4_K-class later (M3): 256-value superblocks, f16 d/dmin, 6-bit
  sub-scales, 4-bit quants. Still DECLARED.
* Every dequantizer validates the payload length against the block table
  and returns the block scale as `(m, e)` plus per-block sub-scales where
  the class requires them.

### 10.4 Matmul / forward-pass composition

**[IMPLEMENTED in M2b, 2026-10-16]**

* `llm_matmul_i32(a: &Vec[Int], a_rows: Int, a_cols: Int, b: &Vec[Int], b_cols: Int) -> Result[Vec[Int], Str]`
  -- flat row-major integer matmul with overflow-checked accumulation
  (fail closed: `llm: matmul overflow`, never wraparound), the workhorse for
  every weight multiply. Exact over the scaled-int `(m, e)` form; the caller
  carries the combined exponent `e_a + e_b`. Size mismatches and negative
  dimensions fail closed.
* Forward primitives (all pure integer functions; error bounds documented on
  the functions in `src/llm.xi`):
  - `llm_rmsnorm_i32(x, gamma, eps, out_shift)` -- `out[i] = gamma[i]*x[i]*2^out_shift / rms`,
    `rms = isqrt(sum(x[i]^2)/n + eps)`; bound: < 1 LSB from the floor root plus
    1/2 LSB rounding; exact for the fixture.
  - `llm_rope_i32(x, head_dim, cos_q, sin_q, shift)` -- pairwise rotation with a
    caller-supplied integer sin/cos table; bound <= 1 LSB per component; the
    position-0 table `(2^shift, 0)` is the exact identity.
  - `llm_dot_i32(a, b)` -- overflow-checked attention score dot product.
  - `llm_softmax_i32(logits_q, shift)` -- max-shifted quadratic
    `exp(t) ~ 1 + t + t^2/2` normalized to sum `2^shift`; EXACT for uniform and
    one-hot inputs, a deterministic bounded approximation otherwise.
  - `llm_silu_q(g, shift)` / `llm_swiglu_i32(gate, up, shift)` -- piecewise
    SiLU (`sig = 1` for `g >= 4*2^shift`, `0` for `g <= -4*2^shift`, else a
    linear ramp); EXACT in the saturated region and at 0.
* `xiom.tensor` is used where it fits the integer model: shape construction
  (`tensor_from_flat`) and canonical `tensor_dump` diagnostics via
  `llm_shape_dump`. It has no matmul, views or elementwise scaled-int ops, so
  the hot kernels stay in-package over flat `Vec[Int]`; this boundary is the
  "over xiom.tensor where sensible" contract.
* Model assembly: `llm_model_open(header, payload) -> Result[LlmModel, Str]`
  concatenates the two buffers, parses with `xiom.gguf`, extracts the vocab and
  validates every tensor extent; the M2 fixture loads its weights through it
  (`llm_tensor_data` + `llm_q8_0_ints` / `llm_f32_at`).
* Forward composition (llama-style skeleton, M2 fixture): token embedding row
  gather -> RMSNorm -> Q/K/V projections via `llm_matmul_i32` -> RoPE
  (identity at position 0) -> scaled attention score -> softmax (one
  position) -> output projection with residual -> SwiGLU FFN with residual ->
  logits. The fixture (emb=4, heads=1, vocab=20, ffn=8, 1 layer) is built so
  every integer step is exact and the golden logits are asserted exactly
  (`-8*i`, section 11).

### 10.5 Generation loop

**[IMPLEMENTED in M3a, 2026-10-16 -- first half: greedy + sampling]**

* `llm_greedy_next(logits: &Vec[Int]) -> Result[Int, Str]` -- argmax with
  lowest-index tie-break. Error: `llm: sampler empty logits`.
* `llm_apply_temperature(logits, t_num, t_den) -> Result[Vec[Int], Str]` --
  `out[i] = round_half_away(logits[i] * t_den / t_num)` (T = t_num / t_den;
  T == 1 is the identity). Errors: `llm: sampler temperature not positive`,
  `llm: sampler overflow`.
* `llm_top_k_keep(logits, k, keep: &mut Vec[Int]) -> Result[Int, Str]` --
  index-ordered membership mask of the k largest logits (lower-index ties);
  `k <= 0` or `k >= n` keeps all. Returns the kept count.
* `llm_top_p_keep(probs, p_q, keep: &mut Vec[Int]) -> Result[Int, Str]` --
  nucleus mask: the shortest probability-descending prefix whose cumulative
  mass reaches `p_q` (units of `2^shift`), always keeping the top-1; `p_q <= 0`
  keeps only the top-1.
* `llm_sample_choice(probs, keep, state) -> Result[Int, Str]` -- one uniform
  draw from the kept mass (`state` a PRNG state); zero kept mass falls back to
  the highest kept probability.
* `llm_sample_next(logits, s: &LlmSampler, state) -> Result[Int, Str]` -- the
  composed pipeline: greedy argmax, else temperature -> integer softmax ->
  top-k -> top-p -> draw.
* `LlmSampler` (greedy flag, temperature num/den, top-k, top-p, shift, seed)
  with `llm_sampler_greedy()` / `llm_sampler_seeded(...)`.
* Deterministic PRNG: `llm_rng_seed` / `llm_rng_next` / `llm_rng_below` --
  a 32-bit LCG `s -> (1664525*s + 1013904223) mod 2^32`, exact integer
  arithmetic, fully reproducible from the seed.
* `llm_is_stop(id, stop_id) -> Bool` -- stop-token predicate (`stop_id < 0`
  disables stopping).
* `llm_generate(model, buf, prompt_ids, max_new, stop_id, s, out_ids) ->
  Result[Int, Str]` -- generation loop composing `llm_forward_token` (single
  position per step) with the sampler; stops at `stop_id` (appended to
  `out_ids`) or after `max_new` steps; returns the generated count.
* `llm_forward_token(model, buf, token_id) -> Result[Vec[Int], Str]` -- the
  M2b single-position forward (section 10.4) as a library entry point, used
  per step by `llm_generate`.

**Deferred (M3 second half):** append-only per-layer KV cache and attention
over longer contexts (multi-position forward), a package-local benchmark
harness, Q4_K-class dequantization, and the tokenizer escape/regex/SPM/WPM
work (section 10.6). The M3a loop has no KV cache, so each step conditions
only on the current token.

### 10.6 Tokenizer milestones (deferred pieces)

* GPT-2 `bytes_to_unicode` escape/unescape layer (requires non-ASCII GGUF
  strings; blocked on `xiom.gguf` string domain).
* Regex pre-tokenizer families (at minimum the GPT-2/llama3 expressions
  from `llama-vocab.cpp`) with a documented subset guarantee.
* SPM (`tokenizer.ggml.model == "llama"`) and WPM (`"bert"`)
  vocabulary extraction + their tokenize paths.

## 11. Test matrix (129 checks, `tests/test_conformance.xi`)

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

M2a additions (checks 29-43): GGML type name/element/byte tables; tensor
nbytes (20x2 f32 = 160) with unknown-type, non-divisible-dims and index
reject arms; `llm_tensor_data` position-checked extraction with oversize
(extent > `gguf_data_len`) and short-buffer rejects; exact f16 and f32
bit-decode vectors (1.0/0.5/2.0/-1.0/subnormal) plus inf/nan rejects;
`llm_dequant_q8_0` golden block (scale 1.0, quants -8..23, exact
`out[i] == (i-8)*1024`, scale `(1024,10)`), negative-scale two-block
exactness, and the bad-length / empty / mixed-scale rejects.

M2b additions (checks 44-79): `llm_matmul_i32` golden (2x3 @ 3x2 ->
`[58,64,139,154]`) with overflow and size-mismatch rejects; `llm_rmsnorm_i32`
exact `[4,4,0,0] -> [2,2,0,0]` plus zero-norm reject; `llm_rope_i32` exact
identity and 90-degree (`[3,5,7,9] -> [-5,3,-9,7]`) goldens;
`llm_softmax_i32` exact one-hot `[1024]` and uniform `[512,512]` plus empty
reject; `llm_silu_q` saturated-region exactness and `llm_swiglu_i32` golden
`[-10,-10]`; `llm_model_open` on the 11-tensor fixture (n=11, vocab 20) with
bad-header and missing-vocab rejects; the **tiny model fixture** (emb=4,
heads=1, vocab=20, ffn=8, 1 layer; eleven tensors, Q8_0 block bytes inside
f32-declared FFN slices as a documented builder deviation, f32 anchors
elsewhere) whose full single-token forward yields the EXACT hand-computed
golden logits `logits[i] = -8*i` for i in 0..19; the single-byte sensitivity
check (ffn_gate first quant 4 -> 3 changes 19 of 20 logits, perturbed logits
exactly `-6*k`); and the `xiom.tensor` shape/dump smoke check.

M3a additions (checks 80-129): the deterministic PRNG (seed normalization,
two hand-computed LCG steps `next(42)=1083814273`,
`next(1083814273)=378494188`, `below(1083814273,1024)=385`,
`below(1083814273,10)=3`, `below(_,0)=0`); greedy argmax (tie-break,
negatives, empty reject); temperature identity/flatten/sharpen/rounding plus
the non-positive rejects; top-k mask (exact set, lowest-index tie, disabled and
oversize arms, empty reject); top-p nucleus (exact prefix sets, `p=0` top-1,
`p>total` all, empty reject); category draw (`llm_sample_choice`) bucket
boundaries, restricted mask, zero-mass fallback and keep-size-mismatch reject;
the composed `llm_sample_next` greedy arm plus a seeded arm verified against
hand-computed bucket boundaries and the temperature reject; `llm_generate`
greedy sequence `[0,0,0]`, decode roundtrip `"hhh"`, stop-token handling,
seeded golden sequence `[0,0,0,0,1]` and same-seed reproducibility, empty
prompt / `max_new=0` edge cases, and the `llm_forward_token` golden
(`-8*i`) with the token-id reject. The M3 generation fixture gives
`token_embd` rows 0 and 1 the value `[4,4,0,0]` (rows 2..19 remain zero) so
the greedy-selected token 0 forwards without tripping the RMSNorm zero-norm
guard; the M2b golden-logit provenance (rows for token 1) is unchanged.

Golden-logit provenance (checks 75-78). The fixture is built so every integer
step is exact: token 1 embedding row `[4,4,0,0]` (mean square 8, rms 2) ->
`xn=[2,2,0,0]`; `Wq/Wk/Wv` select column 1 -> `q=k=v=[2,2,2,2]`; position-0
RoPE is the identity; the single attention position has softmax weight 1.0 so
`attn=v`; `Wo` rows `[-1,0,0,0]` give `Wo@v=[-2,-2,-2,-2]` and residual
`h=[2,2,-2,-2]` -> `hn=[1,1,-1,-1]`; `W1` rows `[4,1,0,0]` give
`gate=[5,...]` in the exact SiLU-saturated region; `W3` rows `[0,0,1,1]` give
`up=[-2,...]`; SwiGLU `a=[-10,...]`; `W2` selects `a[0]` -> `ffn=[-10,...]`;
`h2=[-8,-8,-12,-12]`; `Wout[i]=[i,0,0,0]` -> `logits[i] = i * (-8)`. Every
value is derived by hand from the integer algorithm above, not from a float
reference.

## 12. Compiler notes (v0.64.5, re-verified on v0.64.6)

Free functions only; `Ok`/`Err` construction is confined to the leaf
helpers in `src/llm.xi`; `Str` values read from vectors and struct fields
are bound to typed locals and compared with `str_compare` (never `==`);
every `UInt8` is widened with `(as Int) & 0xFF`; `&struct.field` is never
passed where a `&Vec[...]` parameter is expected; test Result values are
unwrapped through locals (`let r = f(); let v = r.value;`), never by
chaining `.value` on a call. `LlmModel` carries the parsed `Gguf` by value
and is only produced by `llm_model_open`. No contracts are declared on any
function (lane policy for new names, M1 and M2 alike).

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
