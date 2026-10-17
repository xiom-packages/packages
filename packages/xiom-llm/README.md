<!-- XIOM -- xiom.llm README -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.llm

> **Status:** `incubating` -- conformance-tested (254/254, twice); not
> published (`excluded_reason`: new name: pending ops scope + allowlist,
> coverage program).
> **Milestones 1-2 + M3 first and second halves + tokenizer completion:**
> llama.cpp-family vocab extraction from a GGUF header + byte-level BPE
> decode/encode (M1), GGUF payload/tensor loading, Q8_0 dequantization,
> integer matmul and the forward primitives with a tiny deterministic
> golden-logit fixture (M2), the generation loop with a deterministic seeded
> sampler -- greedy / temperature / top-k / top-p -- plus stop-token handling
> (M3a), the append-only KV cache with longer-context multi-position
> attention and the cached generation loop (M3b), Q4_K/Q5_0 dequantization,
> and the ASCII-safe tokenizer completion (GPT-2 escape layer, GPT-2 regex
> pre-tokenizer, SPM scored-merge core). The benchmark harness, WPM and
> real non-ASCII vocabularies are declared in `SPEC.md` / `ROADMAP.md`.

The llama.cpp-family runner tier of the XIOM ML/AI coverage program: read a
GGUF model header with `xiom.gguf`, extract the tokenizer vocabulary from
its metadata, and tokenize / detokenize text with byte-level BPE that
follows llama.cpp's merge-table semantics (`llama-vocab.cpp`, commit
`23f7aabc16c72f6f707dba227251c35d7bd1ed96`, MIT reference).

* Pure XIOM, no FFI. Deps: `xiom.std`, `xiom.gguf` (header codec),
  `xiom.tensor` (shape construction + canonical dumps).
* Deterministic `Err(Str)` catalog prefixed `llm: ` (see SPEC.md section 7).
* 254 conformance checks (`tests/test_conformance.xi`) over synthetic
  deterministic GGUF fixtures built with `xiom.gguf`'s builder -- no model
  downloads.

## What Milestone 1 does

```xi
use xiom.gguf;
use xiom.llm;

// 1. parse a GGUF header (bytes from anywhere)
let pr = gguf_parse(&header_bytes);
let g = pr.value;

// 2. extract the vocabulary
let vr = llm_vocab_from_gguf(&g);
if !vr.is_ok { io.println(vr.error); return 1; }
let v = vr.value;

// 3. decode and encode
let ids: Vec[Int] = llm_bpe_encode(&v, "hello world").value;  // [12, 7, 16]
let text = llm_bpe_decode(&v, &ids).value;                    // "hello world"
```

## API summary (M1 + M2)

| Group | Functions |
|---|---|
| Extraction | `llm_vocab_from_gguf` |
| Vocab accessors | `llm_vocab_model`, `llm_vocab_size`, `llm_vocab_token`, `llm_vocab_token_type`, `llm_vocab_bos`, `llm_vocab_eos`, `llm_vocab_merge_count`, `llm_vocab_merge`, `llm_vocab_find_token` |
| Tokenizer | `llm_bpe_encode`, `llm_bpe_decode` |
| Loading (M2) | `llm_ggml_type_name`, `llm_ggml_block_elems`, `llm_ggml_block_bytes`, `llm_tensor_nbytes`, `llm_tensor_data`, `llm_model_open` |
| Numerics (M2) | `llm_u16_le`, `llm_u32_le`, `llm_f16_to_scaled`, `llm_f32_to_scaled`, `llm_dequant_q8_0`, `llm_q8_0_ints`, `llm_f32_at` |
| Forward (M2) | `llm_matmul_i32`, `llm_dot_i32`, `llm_rmsnorm_i32`, `llm_rope_i32`, `llm_softmax_i32`, `llm_silu_q`, `llm_swiglu_i32`, `llm_isqrt`, `llm_shape_dump` |
| Generation (M3a) | `llm_forward_token`, `llm_generate`, `llm_is_stop`, `llm_greedy_next`, `llm_apply_temperature`, `llm_top_k_keep`, `llm_top_p_keep`, `llm_sample_choice`, `llm_sample_next`, `llm_sampler_greedy`, `llm_sampler_seeded`, `llm_rng_seed`, `llm_rng_next`, `llm_rng_below` |
| KV cache (M3b) | `llm_kv_cache_new`, `llm_kv_cache_len`, `llm_kv_cache_cap`, `llm_kv_cache_append`, `llm_kv_cache_key`, `llm_kv_cache_val`, `llm_attention_i32`, `llm_forward_cache`, `llm_generate_cached` |
| Tokenizer completion | `llm_gpt2_byte_to_codepoint`, `llm_gpt2_codepoint_to_byte`, `llm_utf8_append`, `llm_gpt2_escape`, `llm_gpt2_unescape`, `llm_gpt2_unescape_str`, `llm_gpt2_pretokenize`, `llm_spm_vocab_from_gguf`, `llm_spm_model`, `llm_spm_size`, `llm_spm_token`, `llm_spm_score`, `llm_spm_find_token`, `llm_spm_bos`, `llm_spm_eos`, `llm_spm_encode`, `llm_spm_decode` |

## M1 semantics in one paragraph

The vocabulary is read from `tokenizer.ggml.model` (must be `"gpt2"` in
M1), `tokenizer.ggml.tokens`, `tokenizer.ggml.merges`,
`tokenizer.ggml.token_type` (optional; default 1 = normal), and the
optional `tokenizer.ggml.bos_token_id` / `eos_token_id`. Merge entries
split at the first space at byte index >= 1 (llama.cpp `find(' ', 1)`);
entries without one are dead pairs that still occupy their rank index.
Encode starts from single-byte symbols and repeatedly merges the fresh
minimum-rank adjacent pair, leftmost on ties (llama.cpp work-queue
priority), then maps every final symbol to its exact token id.
Decode concatenates the token strings. `llm_bpe_encode` keeps the raw
ASCII byte domain (the escape layer is a separate, tested surface:
`llm_gpt2_escape` / `llm_gpt2_unescape`), unknown symbols fail closed with
a deterministic error (llama.cpp falls back to per-byte tokens and drops
misses), and the GPT-2 pre-tokenizer is available separately as
`llm_gpt2_pretokenize` (see SPEC.md sections 8 and 10.6 for the documented
deviations).

## Limitations (M1)

* **ASCII domain.** `xiom.gguf` parses printable-ASCII strings only
  (0x20..0x7E), so real model vocabs -- whose tokens are stored in the
  GPT-2 escaped form (`G`-dot etc., non-ASCII) or SPM's `▁` -- cannot be
  parsed yet. The escape layer, ASCII pre-tokenizer and SPM scored-merge
  core are implemented and pinned over the synthetic ASCII fixtures; real
  non-ASCII vocabularies and WPM remain (see `docs/probe-nonascii-gguf.md`
  and ROADMAP.md).
* **Generation is single-layer (M3a/M3b).** `llm_generate` conditions on the
  current token only; `llm_generate_cached` prefills every prompt position
  into an append-only KV cache and attends over the whole cache. The M3
  fixture is one layer, so no multi-layer attention kernel is implemented
  (the cache itself is per-layer). The benchmark harness is still M3 work;
  sampling is greedy / temperature / top-k / top-p over a deterministic
  seeded integer PRNG. SPM (`"llama"`) is implemented as the scored-merge
  core; WPM (`"bert"`) and the BOS/EOS insertion flags remain
  (ROADMAP.md).
* **Q8_0 tensor infos.** `xiom.gguf`'s builder rejects GGML types 8/9, so
  the M2 fixture stores Q8_0 block bytes inside f32-declared FFN slices
  (SPEC.md section 8 item 7); `llm_dequant_q8_0` itself is exercised on the
  real block bytes.
* **Merge lookup is a linear scan** per candidate pair; fine at fixture
  scale, indexed merge maps are an option if profiling asks for them.

## Testing

From the repository root (sibling `xiom.gguf` is consumed as a path
dependency via `xiom.toml`):

```
& .\scripts\port.ps1 -Package xiom-llm -TimeoutSec 180
```

Expected tail: 163 `[PASS]` lines, `xiom.llm: all tests passed`, then
`port: PASS (passed=163 failed=0 program_exit=0 exit=0)`.

## License

MIT OR Apache-2.0. See the package headers and the repository LICENSE
files. The llama.cpp reference (commit recorded in SPEC.md section 13) is
MIT-licensed and was used read-only for semantics; no code was copied.
