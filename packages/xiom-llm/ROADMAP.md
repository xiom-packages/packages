<!-- XIOM -- xiom.llm roadmap -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.llm -- roadmap

Lane: llama.cpp-family runner tier of the ML/AI coverage program.
Current: v0.1.0, milestones M1 + M2 complete, M3 first and second halves
(generation loop + sampling, the append-only KV cache + longer-context
attention, and the Q4_K-class / Q5_0 / Q4_0 / Q5_1 / Q6_K dequantizers)
complete plus the tokenizer completion (GPT-2 escape layer, GPT-2 regex
pre-tokenizer, SPM scored-merge core, WPM `"bert"` WordPiece core),
real-vocabulary loading (lossless GGUF string bytes, SPM U+2581
normalization + `<0xXX>` byte fallback, BOS/EOS insertion flags, escaped
GPT-2 vocab loader), and the package-local benchmark harness
(`bench/bench_llm.xi`, SPEC.md section 10.7); conformance-green
(384/384 x2). No ROADMAP items remain.
`publish: false` pending ops scope + allowlist.

## M1 -- vocab + byte-level BPE (DONE, 2026-10-16)

Delivered: package scaffold to house rules; in-GGUF vocab extraction
(tokenizer.ggml.* family) into `LlmVocab`; byte-level BPE decode/encode
with llama.cpp merge-table semantics (min-rank merge, leftmost ties,
`find(' ', 1)` split, dead pairs, last-wins token lookup); deterministic
`llm: ` error catalog; 38-check suite over a synthetic ASCII GGUF fixture
built with `xiom.gguf`'s builder; XGGUF-ARRSTR workaround (string-array
parse offset) documented in SPEC.md section 9.

Exit criteria met: `port.ps1 -Package xiom-llm -TimeoutSec 180` green
twice (passed=38 failed=0), namespace-check clean, docs in sync.

## M2 -- dequant -> matmul -> forward -> tiny-model fixture

Goal: run a real forward pass over a tiny GGUF container, integer-only,
and pin it against an in-test hand-computed oracle.

1. **GGUF payload/tensor loading** (SPEC.md 10.1) -- DONE in M2a
   - `llm_ggml_*` size tables (f32/f16/Q4_0/Q5_* /Q8_0/Q8_1/K-quants).
   - `llm_tensor_nbytes` + `llm_tensor_data` with extent validation.
   - Fixture: tensor headers with real payload bytes at declared offsets;
     good extents + oversize/short-buffer/unknown-type/non-divisible rejects.
   - Not yet: `llm_model_open` composite (deferred with the forward wave).
2. **Deterministic float-free numerics** (SPEC.md 10.2/10.3) -- DONE in M2a
   - Integer f16/f32 -> exact scaled-int `(m, e)` bit decode
     (`llm_f16_to_scaled`, `llm_f32_to_scaled`; no Float arithmetic).
   - `llm_dequant_q8_0`: scaled-int values + `LlmScale (m, e)`; exact
     integer asserts on hand-built blocks (scale 1.0/-1.0, quants -8..23;
     error bound pinned at 0). Limitation: single shared block scale
     (mixed per-block scales rejected). Q4_K-class deferred (landed later in
     the M3 second-half remainder).
3. **Matmul + forward composition** (SPEC.md 10.4) -- DONE in M2b
   - `llm_matmul_i32` (overflow fail-closed, typed Err) plus `llm_dot_i32`;
     `xiom.tensor` used for shape construction/canonical dump
     (`llm_shape_dump`), the "where sensible" boundary.
   - Forward primitives as pure integer functions with documented error
     bounds: `llm_rmsnorm_i32`, `llm_rope_i32`, `llm_softmax_i32`,
     `llm_silu_q`, `llm_swiglu_i32`. Exact in the fixture regions (rms root,
     position-0 RoPE identity, saturated SiLU); bounded elsewhere.
4. **Tiny-model fixture** -- DONE in M2b
   - dims `emb=4, heads=1, vocab=20, ffn=8`, 1 layer; eleven tensor infos
     (token_embd, attn_norm, wq/wk/wv/wo, ffn_norm, ffn_gate/up/down,
     output), built with `xiom.gguf`'s builder in `tests/`; Q8_0 block bytes
     inside f32-declared FFN slices plus f32 anchor tensors. Deviation:
     `xiom.gguf`'s builder rejects types 8/9, so no type-8 tensor info can
     be declared (SPEC.md section 8 item 7).
   - golden logits `logits[i] = -8*i` (i in 0..19) asserted EXACTLY,
     hand-computed from the integer algorithm; a single-byte sensitivity
     check (ffn_gate first quant 4 -> 3) changes 19 of 20 logits
     (perturbed logits exactly `-6*k`).
5. **Acceptance**: `port.ps1` green x2 with the M2 suite (passed=79
   failed=0); SPEC sections 10.1-10.4 marked implemented; ROADMAP updated.

Dependencies: none external (no downloads); `xiom.gguf` path dep stays.
Risk: integer softmax/RoPE error bounds -- mitigation: declare bounds
first, fixture dims chosen so every oracle value is exact.

## M3 -- generation loop, sampling, KV cache, Q4_K

1. Generate loop -- **DONE (M3a first half + M3b second half,
   2026-10-16)**: `llm_greedy_next` (argmax, lowest-index tie) +
   `llm_generate` with stop-token handling and a single-position-per-step
   loop over the new `llm_forward_token` entry point (M3a); the append-only
   per-layer KV cache (`llm_kv_cache_new`/`_append`/`_len`/`_key`/`_val`),
   the multi-position `llm_attention_i32`, the cached forward
   `llm_forward_cache` and the cached generation loop `llm_generate_cached`
   (M3b). A one-position cache reproduces the single-position path exactly.
2. Sampling beyond greedy -- **FIRST HALF DONE (M3a)**: temperature (integer
   `t_num/t_den` scale), top-k, top-p (nucleus) and a deterministic seeded
   32-bit LCG PRNG (`llm_rng_seed` / `llm_rng_next` / `llm_rng_below`), all
   declared in SPEC.md 10.5. Golden seeded id sequence pinned in the suite.
3. KV cache growth policy and attention on longer contexts -- **DONE (M3b)**:
   append-only `LlmKvCache` (flat `[layer][position][n_kv]`), exact
   append/read goldens, `llm_attention_i32` over all cached positions and the
   cached forward/loop. Benchmark harness -- **DONE (M3 remainder,
   2026-10-17)**: `bench/bench_llm.xi` (off-suite, offline) measures fixture
   prefill / decode token throughput plus SPM / GPT-2 encode throughput from
   a caller-supplied iteration count, with a fixed deterministic output
   shape. The conformance suite type-checks the entry (marker `t90`) without
   running iterations; invocation and number interpretation are in SPEC.md
   section 10.7.
4. Q4_K-class dequant (`llm_dequant_q4_k`) + Q4_0/Q5_0/Q5_1/Q6_K as
   sized; block-table conformance + error-bound pins -- **DONE (M3
   second-half remainder, 2026-10-16)**: `llm_dequant_q4_k` (144-byte
   super-blocks, f16 d/dmin, 12 packed 6-bit scales/mins unpacked by the
   exposed `llm_k_get_scale_min_k4`, 4-bit quants) and the neighboring
   `llm_dequant_q5_0` (22-byte blocks, 5-bit quants, shared scale). Values
   are EXACT (error bound 0); Q4_K folds per-group scales/mins into a single
   global exponent `E = max(de, dme)`. Malformed block sizes get typed
   errors. The remaining formats landed with the M3 remainder follow-up
   (2026-10-17): `llm_dequant_q4_0` (18-byte blocks, centered 4-bit quants,
   shared scale), `llm_dequant_q5_1` (24-byte blocks, unsigned 5-bit quants
   plus an f16 offset `m`, global `E = max(de, dme)`) and
   `llm_dequant_q6_k` (210-byte super-blocks, 6-bit quants with signed int8
   per-16 scales, global `E = max(de)`). All are EXACT with hand-computed
   goldens and typed empty / bad-length / scale-error arms.
5. Tokenizer: GPT-2 `bytes_to_unicode` escape/unescape and the GPT-2
   regex pre-tokenizer, SPM (`"llama"`) extraction + tokenize core, BOS/EOS
   insertion flags, WPM (`"bert"`) -- **DONE (2026-10-17)**:
   * escape layer -- DONE as exact pure surfaces (`llm_gpt2_byte_to_codepoint`
     / `_codepoint_to_byte`, `llm_utf8_append`, `llm_gpt2_escape` /
     `llm_gpt2_unescape` / `llm_gpt2_unescape_str`); all-256-byte inverse
     pinned. RESOLVED: the current `xiom.gguf` accepts arbitrary string
     bytes and exposes the lossless `gguf_kv_str_bytes` /
     `gguf_kv_arr_str_bytes` accessors, so real escaped vocabularies load
     (`docs/probe-nonascii-gguf.md`, test `t83`).
   * regex pre-tokenizer -- DONE for the GPT-2 expression with a
     hand-rolled ASCII byte matcher (`llm_gpt2_pretokenize`), exact chunk
     goldens; Unicode category classes are the documented ASCII subset.
   * SPM -- DONE for the core and real vocabularies: `LlmSpmVocab`
     extraction over `gguf_kv_arr_str_bytes` (non-ASCII tokens including
     U+2581), exact f32 `tokenizer.ggml.scores` folded to a common exponent,
     score-ordered merge traversal with leftmost ties, `▁` normalization
     (space on encode, back on decode), `<0xXX>` byte fallback, encode/
     decode and error arms. WPM (`"bert"`) -- DONE (2026-10-17): a
     `LlmWpmVocab` extractor/accessors plus the WordPiece core
     (`llm_wpm_wordpiece` / `llm_wpm_encode` / `llm_wpm_decode`): greedy
     longest-match-prefix over UTF-8 codepoint boundaries, `##`
     continuation tokens, all-or-nothing `[UNK]` mapping, whitespace
     splitting and BOS/EOS flags. Normalization is intentionally not
     applied because the SPEC pins no WPM lowercase/accent option
     (SPEC.md section 8 item 8).
   * BOS/EOS insertion -- DONE: `tokenizer.ggml.add_bos_token` /
     `add_eos_token` are extracted as 0/1 flags (absent -> 0) and applied by
     `llm_spm_encode`.
   * real GPT-2 vocabularies -- DONE: `llm_gpt2_vocab_from_gguf` reads the
     escaped token/merge arrays through the lossless byte accessors and
     applies the `bytes_to_unicode` inverse to every key, so the existing
     raw-byte BPE encode/decode is exact.
6. Acceptance: prompt -> generated ids -> decode roundtrip on the tiny
   fixture; escape-layer golden vectors (hand-computed byte-unicode
   table values). **DONE**: greedy and seeded prompt -> ids -> decode
   roundtrips are green, the cached multi-position loop adds a
   two-token-prompt roundtrip, the escape-layer vectors are pinned, the
   WPM WordPiece goldens (including `##` continuations, `[UNK]` and a
   multi-byte `é` piece) are pinned, the benchmark entry is type-checked,
   and the suite is green (384/384 x2).

## Maintenance / cross-lane items

* **xiom.gguf string-array fix (XGGUF-ARRSTR)**: RESOLVED -- fixed in
  `xiom.gguf` 0.1.3 (origin for element types 6/8/12); the M1 workaround
  was deleted in M2a and the suite re-greened (SPEC.md section 9).
* **xiom.gguf UTF-8 strings**: RESOLVED -- string values accept arbitrary
  bytes and `gguf_kv_str_bytes` / `gguf_kv_arr_str_bytes` read them
  losslessly; the real GPT-2/SPM loaders consume those accessors.
* **xiom.gguf builder type 8/9**: the builder rejects `q8_0`/`q8_1` tensor
  infos, forcing the M2b fixture to carry Q8_0 block bytes in f32-declared
  slices (SPEC.md section 8 item 7). Lifting this lets the fixture declare
  real type-8 tensors.
* **Registry publish**: pending ops scope decision + allowlist for the
  `xiom.llm` name (same gate as the other coverage-program names).
* **xiom.tensor**: revisit once it grows matmul/views; move kernels out
  of xiom.llm if the shape fits (keep the "over xiom.tensor where
  sensible" contract current).
