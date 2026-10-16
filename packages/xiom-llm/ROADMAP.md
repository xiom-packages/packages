<!-- XIOM -- xiom.llm roadmap -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.llm -- roadmap

Lane: llama.cpp-family runner tier of the ML/AI coverage program.
Current: v0.1.0, milestones M1 + M2 complete and conformance-green (79/79
x2); `publish: false` pending ops scope + allowlist.

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
     (mixed per-block scales rejected). Q4_K-class deferred to M4.
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

1. Generate loop: `llm_greedy_next` (argmax, lowest-index tie) +
   `llm_generate` with append-only KV cache; stop at EOS/max_new.
2. Sampling beyond greedy (temperature/top-k/top-p) with a deterministic
   integer PRNG (seeded, reproducible), declared in SPEC.
3. KV cache growth policy and attention on longer contexts; benchmark
   harness (package-local, `xiom bench` compatible).
4. Q4_K-class dequant (`llm_dequant_q4_k`) + Q4_0/Q5_0/Q5_1/Q6_K as
   sized; block-table conformance + error-bound pins.
5. Tokenizer: GPT-2 `bytes_to_unicode` escape/unescape and the GPT-2
   regex pre-tokenizer, **blocked on non-ASCII GGUF strings** (see
   maintenance item); BOS/EOS insertion flags
   (`tokenizer.ggml.add_bos_token` / `add_eos_token`); SPM (`"llama"`)
   and WPM (`"bert"`) extraction + tokenize paths,
   `tokenizer.ggml.scores` handling.
6. Acceptance: prompt -> generated ids -> decode roundtrip on the tiny
   fixture; escape-layer golden vectors (hand-computed byte-unicode
   table values).

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
