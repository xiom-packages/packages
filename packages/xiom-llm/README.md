<!-- XIOM -- xiom.llm README -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.llm

> **Status:** `incubating` -- conformance-tested (38/38, twice); not
> published (`excluded_reason`: new name: pending ops scope + allowlist,
> coverage program).
> **Milestone 1:** llama.cpp-family vocab extraction from a GGUF header +
> byte-level BPE decode/encode, over `xiom.gguf`. The rest of the runner
> surface (payload/tensor loading, dequant, matmul, forward pass,
> generation loop) is declared in `SPEC.md` and planned in `ROADMAP.md`.

The llama.cpp-family runner tier of the XIOM ML/AI coverage program: read a
GGUF model header with `xiom.gguf`, extract the tokenizer vocabulary from
its metadata, and tokenize / detokenize text with byte-level BPE that
follows llama.cpp's merge-table semantics (`llama-vocab.cpp`, commit
`23f7aabc16c72f6f707dba227251c35d7bd1ed96`, MIT reference).

* Pure XIOM, no FFI. Deps: `xiom.std`, `xiom.gguf` (header codec),
  `xiom.tensor` (reserved for the M2 forward-pass plan).
* Deterministic `Err(Str)` catalog prefixed `llm: ` (see SPEC.md section 7).
* 38 conformance checks (`tests/test_conformance.xi`) over a synthetic
  deterministic GGUF fixture built with `xiom.gguf`'s builder -- no model
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

## API summary (M1)

| Group | Functions |
|---|---|
| Extraction | `llm_vocab_from_gguf` |
| Vocab accessors | `llm_vocab_model`, `llm_vocab_size`, `llm_vocab_token`, `llm_vocab_token_type`, `llm_vocab_bos`, `llm_vocab_eos`, `llm_vocab_merge_count`, `llm_vocab_merge`, `llm_vocab_find_token` |
| Tokenizer | `llm_bpe_encode`, `llm_bpe_decode` |

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
Decode concatenates the token strings. Over the M1 printable-ASCII
domain: no GPT-2 `bytes_to_unicode` escape layer yet, no regex
pre-tokenizer yet, and unknown symbols fail closed with a deterministic
error (llama.cpp falls back to per-byte tokens and drops misses; see
SPEC.md section 8 for the documented deviations).

## Limitations (M1)

* **ASCII domain.** `xiom.gguf` parses printable-ASCII strings only
  (0x20..0x7E), so real model vocabs -- whose tokens are stored in the
  GPT-2 escaped form (`G`-dot etc., non-ASCII) -- cannot be parsed yet.
  M1 targets the synthetic ASCII fixture; the escape layer and UTF-8
  string support are M3 work (see ROADMAP.md).
* **No payload/tensor decoding, no numerics.** Tensor infos are visible
  through `xiom.gguf`; loading extents, Q8_0/Q4_K dequant, matmul,
  forward pass and the generation loop are declared in SPEC.md section 10
  and planned in ROADMAP.md (M2+).
* **No SPM/WPM vocabularies** (`"llama"`/`"bert"` model strings are
  rejected; declared for M3).
* **Merge lookup is a linear scan** per candidate pair; fine at fixture
  scale, indexed merge maps are an M2+ option if profiling asks for them.

## Testing

From the repository root (sibling `xiom.gguf` is consumed as a path
dependency via `xiom.toml`):

```
& .\scripts\port.ps1 -Package xiom-llm -TimeoutSec 180
```

Expected tail: 38 `[PASS]` lines, `xiom.llm: all tests passed`, then
`port: PASS (passed=38 failed=0 program_exit=0 exit=0)`.

## License

MIT OR Apache-2.0. See the package headers and the repository LICENSE
files. The llama.cpp reference (commit recorded in SPEC.md section 13) is
MIT-licensed and was used read-only for semantics; no code was copied.
