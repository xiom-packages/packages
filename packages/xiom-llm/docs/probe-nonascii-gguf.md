<!-- XIOM -- xiom.llm probe: non-ASCII GGUF strings -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Probe: non-ASCII GGUF strings (tokenizer escape-layer blocker)

Date: 2026-10-17. Dependency: `xiom.gguf` 0.1.3 (path `../xiom-gguf`).

## Purpose

M2/M3 assumed the real-vocabulary GPT-2/SPM escape layer was blocked by
`xiom.gguf`'s printable-ASCII string domain. This probe re-checks 0.1.3,
which carries the XGGUF-ARRSTR origin fix but (as verified) not a UTF-8 /
non-ASCII string domain.

## Minimal failing case

A GGUF v3 header with one metadata KV:

* key: `tokenizer.ggml.model`
* value type: 8 (string)
* value bytes: `67 70 74 32 C4 A0` (`gpt2` followed by the UTF-8 encoding of
  U+0120, the GPT-2 escaped form of byte 0x20)

Header bytes: magic `GGUF`, version 3, `n_tensors = 0`, `n_kv = 1`, then the
KV, then zero padding to the 32-byte alignment boundary.

## Result

`gguf_parse` returns (exact):

```
Err("gguf: string is not printable ASCII")
```

Cause: `_rd_str` in `xiom-gguf/src/gguf.xi` rejects any string byte `< 32` or
`> 126`. `gguf_builder_add_kv_str` / `gguf_builder_add_kv_arr_str` reject the
same bytes, so the fixture builder cannot bypass the check.

Consequence for `xiom.llm`:

* the GPT-2 `bytes_to_unicode` escape/unescape layer and its golden vectors
  are implemented as pure byte/codepoint surfaces (`llm_gpt2_*`,
  `llm_utf8_append`) and tested directly;
* a real GGUF vocabulary containing escaped tokens (for example `U+0120` for
  space, or SPM's `U+2581` `▁` marker) still cannot be loaded, because
  `llm_vocab_from_gguf` / `llm_spm_vocab_from_gguf` only see parsed strings;
* the regex pre-tokenizer and SPM core are therefore pinned over the
  ASCII-safe domain (literal space, plain ASCII pieces). See SPEC.md
  sections 8 and 10.6.

## Reproduction

The probe is pinned in `tests/test_conformance.xi` (`t83`): it builds the
header above and asserts the exact error string, and asserts that
`llm_gpt2_escape([0x20])` produces `C4 A0`.
