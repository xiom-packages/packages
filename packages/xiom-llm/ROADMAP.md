<!-- XIOM -- xiom.llm roadmap -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.llm -- roadmap

Lane: llama.cpp-family runner tier of the ML/AI coverage program.
Current: v0.1.0, milestone 1 (M1) complete and conformance-green (38/38
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

1. **GGUF payload/tensor loading** (SPEC.md 10.1)
   - `llm_ggml_*` size tables (f32/f16/Q8_0 first, then Q4_K-class).
   - `llm_tensor_nbytes` + `llm_tensor_data` with extent validation.
   - Fixture: extend the builder fixture with real payload bytes at
     declared offsets; cover good extents + every reject arm.
2. **Deterministic float-free numerics** (SPEC.md 10.2/10.3)
   - Integer f16/f32 -> (sign, mantissa, exponent) bit decode.
   - `llm_dequant_q8_0` first: scaled-int values + `(m, e)` scale; error
     bounds documented and unit-pinned on hand-built blocks
     (known mantissa/exponent bytes, e.g. scale 1.0/0.5/2.0 patterns).
3. **Matmul + forward composition** (SPEC.md 10.4)
   - `llm_matmul_i32` (overflow fail-closed) + xiom.tensor for shape
     construction/dump (the "where sensible" boundary).
   - RMSNorm -> QKV -> RoPE -> attention -> softmax plan -> FFN ->
     logits; each step integer with a documented error bound.
4. **Tiny-model fixture** (concrete):
   - dims `emb=4, heads=1, vocab=20, ffn=8`, 1 layer, Q8_0 weights (plus
     f32 tensors for exactness anchors), written with `xiom.gguf`'s
     builder in `tests/`;
   - golden logits computed by hand in the suite (small enough to do in
     integers), asserted exactly; a second check asserts that perturbing
     one weight byte changes the argmax (sensitivity, not magic).
5. **Acceptance**: `port.ps1` green x2 with the M2 suite; SPEC sections
   10.1-10.4 move from DECLARED to implemented; README/STATUS updated.

Dependencies: none external (no downloads); `xiom.gguf` path dep stays.
Risk: integer softmax/RoPE error bounds -- mitigation: declare bounds
first, fixture dims chosen so every oracle value is exact.

## M3 -- tokenizer completion + generation loop

1. Generate loop: `llm_greedy_next` (argmax, lowest-index tie) +
   `llm_generate` with append-only KV cache; stop at EOS/max_new.
2. Tokenizer: GPT-2 `bytes_to_unicode` escape/unescape and the GPT-2
   regex pre-tokenizer, **blocked on non-ASCII GGUF strings** (see
   maintenance item); BOS/EOS insertion flags
   (`tokenizer.ggml.add_bos_token` / `add_eos_token`).
3. SPM (`"llama"`) and WPM (`"bert"`) extraction + tokenize paths,
   `tokenizer.ggml.scores` handling.
4. Acceptance: prompt -> generated ids -> decode roundtrip on the tiny
   fixture; escape-layer golden vectors (hand-computed byte-unicode
   table values).

## M4 -- quantization breadth + sampling

1. Q4_K-class dequant (`llm_dequant_q4_k`) + Q4_0/Q5_0/Q5_1/Q6_K as
   sized; block-table conformance + error-bound pins.
2. Sampling beyond greedy (temperature/top-k/top-p) with deterministic
   integer PRNG (seeded, reproducible), declared in SPEC.
3. Attention on longer contexts; KV cache growth policy; benchmark
   harness (package-local, `xiom bench` compatible).

## Maintenance / cross-lane items

* **xiom.gguf string-array fix (XGGUF-ARRSTR)**: coordinator to schedule
  upstream patch (origin for element types 6/8/12; add an arr_str
  conformance case). When a fixed `xiom.gguf` is pinned, delete
  `_arr_str_origin`/`_arr_str_at` from `src/llm.xi` and re-green.
* **xiom.gguf UTF-8 strings**: non-ASCII string support unblocks the
  real-vocab escape layer (M3 tokenizer completion).
* **Registry publish**: pending ops scope decision + allowlist for the
  `xiom.llm` name (same gate as the other coverage-program names).
* **xiom.tensor**: revisit once it grows matmul/views; move kernels out
  of xiom.llm if the shape fits (keep the "over xiom.tensor where
  sensible" contract current).
