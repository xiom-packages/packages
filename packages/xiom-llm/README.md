<!-- XIOM -- xiom.llm README -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.llm

> **Status:** `incubating` -- conformance-tested (327/327, twice);
> published in `eco-v0.1.196` (sha256 `3c85e858...`, 2026-10-17).
> **Milestones 1-2 + M3 first and second halves + tokenizer completion +
> real vocabularies + benchmark harness:**
> llama.cpp-family vocab extraction from a GGUF header + byte-level BPE
> decode/encode (M1), GGUF payload/tensor loading, Q8_0 dequantization,
> integer matmul and the forward primitives with a tiny deterministic
> golden-logit fixture (M2), the generation loop with a deterministic seeded
> sampler -- greedy / temperature / top-k / top-p -- plus stop-token handling
> (M3a), the append-only KV cache with longer-context multi-position
> attention and the cached generation loop (M3b), Q8_0/Q5_0/Q4_K/Q4_0/Q5_1/
> Q6_K dequantization, the tokenizer completion (GPT-2 escape layer, GPT-2
> regex pre-tokenizer,
> SPM scored-merge core), and real-vocabulary loading (lossless GGUF string
> bytes, escaped GPT-2 keys, SPM `▁` normalization + `<0xXX>` fallback,
> BOS/EOS flags), and the package-local benchmark harness (fixture prefill /
> decode and SPM / GPT-2 encode throughput). WPM remains (`SPEC.md` /
> `ROADMAP.md`).

The llama.cpp-family runner tier of the XIOM ML/AI coverage program: read a
GGUF model header with `xiom.gguf`, extract the tokenizer vocabulary from
its metadata, and tokenize / detokenize text with byte-level BPE that
follows llama.cpp's merge-table semantics (`llama-vocab.cpp`, commit
`23f7aabc16c72f6f707dba227251c35d7bd1ed96`, MIT reference).

* Pure XIOM, no FFI. Deps: `xiom.std`, `xiom.gguf` (header codec),
  `xiom.tensor` (shape construction + canonical dumps).
* Deterministic `Err(Str)` catalog prefixed `llm: ` (see SPEC.md section 7).
* 327 conformance checks (`tests/test_conformance.xi`) over synthetic
  deterministic GGUF fixtures built with `xiom.gguf`'s builder (including
  non-ASCII escaped GPT-2 keys and SPM `▁` tokens) -- no model downloads.
* Offline benchmark harness (`bench/bench_llm.xi`); the conformance suite
  type-checks it (marker `t90`) without running iterations.

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
| Extraction | `llm_vocab_from_gguf`, `llm_gpt2_vocab_from_gguf` |
| Vocab accessors | `llm_vocab_model`, `llm_vocab_size`, `llm_vocab_token`, `llm_vocab_token_type`, `llm_vocab_bos`, `llm_vocab_eos`, `llm_vocab_add_bos`, `llm_vocab_add_eos`, `llm_vocab_merge_count`, `llm_vocab_merge`, `llm_vocab_find_token` |
| Tokenizer | `llm_bpe_encode`, `llm_bpe_decode` |
| Loading (M2) | `llm_ggml_type_name`, `llm_ggml_block_elems`, `llm_ggml_block_bytes`, `llm_tensor_nbytes`, `llm_tensor_data`, `llm_model_open` |
| Numerics (M2) | `llm_u16_le`, `llm_u32_le`, `llm_f16_to_scaled`, `llm_f32_to_scaled`, `llm_dequant_q8_0`, `llm_q8_0_ints`, `llm_f32_at` |
| Dequant (M3) | `llm_dequant_q8_0`, `llm_dequant_q5_0`, `llm_dequant_q4_k`, `llm_k_get_scale_min_k4`, `llm_dequant_q4_0`, `llm_dequant_q5_1`, `llm_dequant_q6_k` |
| Forward (M2) | `llm_matmul_i32`, `llm_dot_i32`, `llm_rmsnorm_i32`, `llm_rope_i32`, `llm_softmax_i32`, `llm_silu_q`, `llm_swiglu_i32`, `llm_isqrt`, `llm_shape_dump` |
| Generation (M3a) | `llm_forward_token`, `llm_generate`, `llm_is_stop`, `llm_greedy_next`, `llm_apply_temperature`, `llm_top_k_keep`, `llm_top_p_keep`, `llm_sample_choice`, `llm_sample_next`, `llm_sampler_greedy`, `llm_sampler_seeded`, `llm_rng_seed`, `llm_rng_next`, `llm_rng_below` |
| KV cache (M3b) | `llm_kv_cache_new`, `llm_kv_cache_len`, `llm_kv_cache_cap`, `llm_kv_cache_append`, `llm_kv_cache_key`, `llm_kv_cache_val`, `llm_attention_i32`, `llm_forward_cache`, `llm_generate_cached` |
| Tokenizer completion / real vocab | `llm_gpt2_byte_to_codepoint`, `llm_gpt2_codepoint_to_byte`, `llm_utf8_append`, `llm_gpt2_escape`, `llm_gpt2_unescape`, `llm_gpt2_unescape_str`, `llm_gpt2_pretokenize`, `llm_gpt2_vocab_from_gguf`, `llm_spm_vocab_from_gguf`, `llm_spm_model`, `llm_spm_size`, `llm_spm_token`, `llm_spm_score`, `llm_spm_find_token`, `llm_spm_bos`, `llm_spm_eos`, `llm_spm_add_bos`, `llm_spm_add_eos`, `llm_spm_encode`, `llm_spm_decode` |

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
byte domain (the escape layer is a separate, tested surface:
`llm_gpt2_escape` / `llm_gpt2_unescape`), unknown symbols fail closed with
a deterministic error (llama.cpp falls back to per-byte tokens and drops
misses), and the GPT-2 pre-tokenizer is available separately as
`llm_gpt2_pretokenize`. Real GPT-2 vocabularies are loaded through
`llm_gpt2_vocab_from_gguf`, which unescapes every token/merge key to raw
bytes. SPM (`llm_spm_encode` / `llm_spm_decode`) rewrites spaces to
U+2581 (`▁`) and back, and uses `<0xXX>` fallback tokens when present (see
SPEC.md sections 8 and 10.6 for the documented deviations).

## Limitations

* **WPM only.** `xiom.gguf` now accepts arbitrary string bytes, so real
  GPT-2 escaped vocabularies and SPM `▁` vocabularies load losslessly
  (`docs/probe-nonascii-gguf.md` records the resolved probe). WPM
  (`"bert"`) remains unimplemented (ROADMAP.md).
* **Generation is single-layer (M3a/M3b).** `llm_generate` conditions on the
  current token only; `llm_generate_cached` prefills every prompt position
  into an append-only KV cache and attends over the whole cache. The M3
  fixture is one layer, so no multi-layer attention kernel is implemented
  (the cache itself is per-layer). `bench/bench_llm.xi` is the offline
  throughput harness (see below); sampling is greedy / temperature / top-k /
  top-p over a deterministic seeded integer PRNG. SPM (`"llama"`) is
  implemented with `▁` normalization, byte fallback and BOS/EOS insertion
  flags; WPM (`"bert"`) remains (ROADMAP.md).
* **Q8_0 tensor infos.** `xiom.gguf`'s builder rejects GGML types 8/9, so
  the M2 fixture stores Q8_0 block bytes inside f32-declared FFN slices
  (SPEC.md section 8 item 7); `llm_dequant_q8_0` itself is exercised on the
  real block bytes.
* **Merge lookup is a linear scan** per candidate pair; fine at fixture
  scale, indexed merge maps are an option if profiling asks for them.

## Benchmark harness

Offline and fixture-based (no network, no external model files). Run it from
the package directory:

```
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"   # if the toolchain resolver has not set it
xiom --run bench/bench_llm.xi
```

The iteration count is caller-supplied through the environment (default
1000, capped at 4096 because the decode row appends one KV position per
iteration):

```
$env:XIOM_LLM_BENCH_ITERS = 5000
xiom --run bench/bench_llm.xi
```

`xiom --run` does not forward trailing CLI arguments to the compiled program,
so the environment variable is the canonical input; `--iters N` /
`--iters=N` is also accepted when the compiled binary is executed directly.
The pinned toolchain has no `xiom bench` subcommand, so the entry is invoked
with `xiom --run`; its rows follow the `xiom.bench` stdlib result fields and
print a fixed set of integer values:

```
xiom.llm bench: fixture=tiny-gpt2 emb=4 heads=1 layers=1 vocab=20 iterations=1000
prefill: ops=2000 total_ns=180000000 ops_per_sec=11111 checksum=-304000
decode: ops=1000 total_ns=563000000 ops_per_sec=1776 checksum=-175522
tokenizer.spm.encode: ops=1000 total_ns=394000000 ops_per_sec=2538 checksum=6000
tokenizer.gpt2.encode: ops=1000 total_ns=175000000 ops_per_sec=5714 checksum=4000
bench: done
```

How to read the numbers:

* `ops` -- operations performed: prefill counts two token forwards per
  iteration (a fresh 2-token cache), decode counts one cached forward per
  iteration, and each tokenizer row counts one encode of its fixed
  eight-piece text.
* `total_ns` -- wall time for the whole batch, measured with the monotonic
  clock (millisecond resolution, so it is a multiple of `1000000`).
* `ops_per_sec` -- `ops * 1_000_000_000 / total_ns`; `0` means the batch
  finished inside one clock tick, so raise the iteration count.
* `checksum` -- deterministic sink accumulated from the fixture outputs; it
  keeps the measured work observable and must not change between runs.

Absolute numbers are machine-dependent: use the harness for relative
tracking on the same machine, not as an absolute performance claim.

## Testing

From the repository root (sibling `xiom.gguf` is consumed as a path
dependency via `xiom.toml`):

```
& .\scripts\port.ps1 -Package xiom-llm -TimeoutSec 180
```

Expected tail: 327 `[PASS]` lines, `xiom.llm: all tests passed`, then
`port: PASS (passed=327 failed=0 program_exit=0 exit=0)`.

## License

MIT OR Apache-2.0. See the package headers and the repository LICENSE
files. The llama.cpp reference (commit recorded in SPEC.md section 13) is
MIT-licensed and was used read-only for semantics; no code was copied.
