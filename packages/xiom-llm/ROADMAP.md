<!-- XIOM -- xiom.llm roadmap -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.llm -- roadmap

Lane: llama.cpp-family runner tier of the ML/AI coverage program.
Current: v0.1.0, milestones M1 + M2 complete, M3 first and second halves
(generation loop + sampling, the append-only KV cache + longer-context
attention, and Q4_K-class dequantization with the neighboring Q5_0) complete
plus the ASCII-safe tokenizer completion (GPT-2 escape layer, GPT-2 regex
pre-tokenizer, SPM scored-merge core) and conformance-green (254/254 x2).
Remaining: the benchmark harness, WPM, and real non-ASCII vocabularies
(blocked on `xiom.gguf`). `publish: false` pending ops scope + allowlist.

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
   cached forward/loop. Benchmark harness (package-local, `xiom bench`
   compatible) -- **REMAINS**.
4. Q4_K-class dequant (`llm_dequant_q4_k`) + Q4_0/Q5_0/Q5_1/Q6_K as
   sized; block-table conformance + error-bound pins -- **DONE (M3
   second-half remainder, 2026-10-16)**: `llm_dequant_q4_k` (144-byte
   super-blocks, f16 d/dmin, 12 packed 6-bit scales/mins unpacked by the
   exposed `llm_k_get_scale_min_k4`, 4-bit quants) and the neighboring
   `llm_dequant_q5_0` (22-byte blocks, 5-bit quants, shared scale). Values
   are EXACT (error bound 0); Q4_K folds per-group scales/mins into a single
   global exponent `E = max(de, dme)`. Malformed block sizes get typed
   errors. Q4_0/Q5_1/Q6_K remain unscheduled.
5. Tokenizer: GPT-2 `bytes_to_unicode` escape/unescape and the GPT-2
   regex pre-tokenizer, SPM (`"llama"`) extraction + tokenize core, BOS/EOS
   insertion flags, WPM (`"bert"`) -- **PARTIAL / DONE (2026-10-17)**:
   * escape layer -- DONE as exact pure surfaces (`llm_gpt2_byte_to_codepoint`
     / `_codepoint_to_byte`, `llm_utf8_append`, `llm_gpt2_escape` /
     `llm_gpt2_unescape` / `llm_gpt2_unescape_str`); all-256-byte inverse
     pinned. Real GGUF vocabularies with escaped non-ASCII token strings
     remain blocked: `xiom.gguf` 0.1.3 rejects any byte outside 0x20..0x7E
     with `gguf: string is not printable ASCII` (probe recorded in
     `docs/probe-nonascii-gguf.md`, test `t83`).
   * regex pre-tokenizer -- DONE for the GPT-2 expression with a
     hand-rolled ASCII byte matcher (`llm_gpt2_pretokenize`), exact chunk
     goldens; Unicode category classes are the documented ASCII subset.
   * SPM -- DONE for the core: `LlmSpmVocab` extraction (tokens, exact f32
     `tokenizer.ggml.scores` folded to a common exponent), score-ordered
     merge traversal with leftmost ties, encode/decode and error arms.
     SentencePiece `▁` normalization / byte fallback, WPM (`"bert"`) and the
     `add_bos_token` / `add_eos_token` flags REMAIN.
6. Acceptance: prompt -> generated ids -> decode roundtrip on the tiny
   fixture; escape-layer golden vectors (hand-computed byte-unicode
   table values). **DONE**: greedy and seeded prompt -> ids -> decode
   roundtrips are green, the cached multi-position loop adds a
   two-token-prompt roundtrip, the escape-layer vectors are pinned, and the
   suite is green (254/254 x2).

## Maintenance / cross-lane items

* **xiom.gguf string-array fix (XGGUF-ARRSTR)**: RESOLVED -- fixed in
  `xiom.gguf` 0.1.3 (origin for element types 6/8/12); the M1 workaround
  was deleted in M2a and the suite re-greened (SPEC.md section 9).
* **xiom.gguf UTF-8 strings**: non-ASCII string support unblocks the
  real-vocab escape layer (M3 tokenizer completion).
* **xiom.gguf builder type 8/9**: the builder rejects `q8_0`/`q8_1` tensor
  infos, forcing the M2b fixture to carry Q8_0 block bytes in f32-declared
  slices (SPEC.md section 8 item 7). Lifting this lets the fixture declare
  real type-8 tensors.
* **Registry publish**: pending ops scope decision + allowlist for the
  `xiom.llm` name (same gate as the other coverage-program names).
* **xiom.tensor**: revisit once it grows matmul/views; move kernels out
  of xiom.llm if the shape fits (keep the "over xiom.tensor where
  sensible" contract current).
