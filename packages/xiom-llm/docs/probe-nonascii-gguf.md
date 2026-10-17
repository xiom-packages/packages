<!-- XIOM -- xiom.llm probe: non-ASCII GGUF strings -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Probe: non-ASCII GGUF strings (RESOLVED)

Date: 2026-10-17. Dependency: `xiom.gguf` path `../xiom-gguf`.

## Original blocker (xiom.gguf 0.1.3)

A GGUF v3 header with one metadata KV:

* key: `tokenizer.ggml.model`
* value type: 8 (string)
* value bytes: `67 70 74 32 C4 A0` (`gpt2` followed by the UTF-8 encoding of
  U+0120, the GPT-2 escaped form of byte 0x20)

`gguf_parse` returned exactly:

```
Err("gguf: string is not printable ASCII")
```

`_rd_str` rejected every string byte `< 32` or `> 126`, and the builder
rejected the same bytes, so real GPT-2/SPM vocabularies could not be loaded.

## Resolution

`xiom.gguf` now copies string payloads byte-for-byte (NUL remains the only
rejected byte because `Str` is NUL-terminated) and exposes:

* `gguf_kv_str_bytes(g, i)` / `gguf_kv_arr_str_bytes(g, i, e)` -- lossless
  raw bytes, including bytes >= 0x80;
* `gguf_kv_str_utf8(g, i)` / `gguf_kv_arr_str_utf8(g, i, e)` -- strict
  UTF-8 validation when callers want text.

The builder accepts arbitrary string bytes (`gguf_builder_add_kv_str` /
`gguf_builder_add_kv_arr_str`), so the probe fixture now parses and can be
built in-code.

Consequences for `xiom.llm`:

* `llm_spm_vocab_from_gguf` reads real SPM vocabularies through the byte
  accessors, including U+2581 (`▁`, E2 96 81); encode rewrites spaces to
  the marker and decode maps it back, with `<0xXX>` byte fallback.
* `llm_gpt2_vocab_from_gguf` reads escaped GPT-2 tokens/merges and applies
  the `bytes_to_unicode` inverse to every key, yielding raw-byte tokens for
  the existing BPE encode/decode.
* `tokenizer.ggml.add_bos_token` / `add_eos_token` are extracted and applied
  by `llm_spm_encode`.

## Reproduction

Pinned in `tests/test_conformance.xi`:

* `t83` -- the header above parses, `gguf_kv_str_bytes` returns all six
  bytes (`gpt2` + C4 A0) losslessly, and `llm_gpt2_escape([0x20])` still
  emits C4 A0.
* `t84`-`t86` -- real SPM vocabulary, `▁` normalization/round-trip, byte
  fallback and BOS/EOS flags.
* `t87`-`t88` -- builder-made escaped GPT-2 vocabulary, unescape, raw-byte
  encode/decode, and the invalid-escape error arms.
