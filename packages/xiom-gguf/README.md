<!-- XIOM -- xiom.gguf README -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.gguf

> **Status:** `stable` -- conformance-tested (30/30); `0.1.3` published 2026-10-16 (string-array origin fix, XGGUF-ARRSTR; live sha256 `2d79e76c...`; `0.1.2` was the previous line). The non-ASCII string-value fix and its tests are post-0.1.3 work in this tree.

A production-grade, dependency-free GGUF container **header** codec for
XIOM: parse the metadata KV table and tensor-info table of llama.cpp-family
model files (version 2 and 3), query every field, or build a byte-exact
header to append tensor payloads to.

* Pure XIOM, no FFI, deps: `xiom.std` only.
* Deterministic `Err(Str)` catalog (see SPEC.md §6).
* Integer-only internals: floats are preserved as raw LE bytes in hex.
* 30 conformance checks (`tests/test_conformance.xi`) -- includes the
  two-string-array origin isolation regression (XGGUF-ARRSTR) and
  byte-exact non-ASCII GPT-2/SPM token values.
* String values are arbitrary length-prefixed bytes (usually UTF-8), so
  escaped GPT-2 vocabularies and SPM `\u2581` tokens load unchanged; use
  `gguf_kv_str_bytes` for lossless access or `gguf_kv_str_utf8` for text.

## Install

```toml
xiom.gguf = "0.1.3"
```

## Quick start

```xi
use xiom.gguf;

// Read a model header
let r = gguf_parse(&bytes);
if !r.is_ok {
  io.println("gguf: " + r.error);
  return 1;
}
let g = r.value;
io.println("version " + convert.int_to_string(gguf_version(&g)));
let kv = gguf_find_kv(&g, "general.name");
if kv.is_ok {
  let name = gguf_kv_str(&g, kv.value);
  io.println("model: " + name.value);
}
let t = gguf_find_tensor(&g, "token_embd.weight");
let dim0 = gguf_tensor_dim(&g, t.value, 0);
io.println("dim0: " + convert.int_to_string(dim0.value));

// Build a header (append payload bytes after finish)
var b = gguf_builder_new();
let a1 = gguf_builder_add_kv_str(&mut b, "general.name", "tiny");
let a2 = gguf_builder_add_tensor(&mut b, "w", &dims, 0, 0);
let hdr = gguf_builder_finish(&b);
var out = hdr.value;      // header up to the alignment boundary
// out.push(...)           // append tensor payload here
```

## API summary

| Group | Functions |
|---|---|
| Parse | `gguf_parse` |
| Header | `gguf_version`, `gguf_kv_count`, `gguf_tensor_count`, `gguf_alignment`, `gguf_data_offset`, `gguf_data_len` |
| KV | `gguf_kv_key`, `gguf_kv_type`, `gguf_kv_int`, `gguf_kv_str`, `gguf_kv_str_bytes`, `gguf_kv_str_utf8`, `gguf_kv_arr_type`, `gguf_kv_arr_count`, `gguf_kv_arr_int`, `gguf_kv_arr_str`, `gguf_kv_arr_str_bytes`, `gguf_kv_arr_str_utf8`, `gguf_find_kv` |
| Tensors | `gguf_tensor_name`, `gguf_tensor_ndims`, `gguf_tensor_type`, `gguf_tensor_offset`, `gguf_tensor_dim`, `gguf_find_tensor`, `gguf_type_name` |
| Builder | `gguf_builder_new`, `gguf_builder_set_alignment`, `gguf_builder_add_kv_int`, `gguf_builder_add_kv_str`, `gguf_builder_add_kv_float`, `gguf_builder_add_kv_arr_int`, `gguf_builder_add_kv_arr_str`, `gguf_builder_add_tensor`, `gguf_builder_finish` |

## Error model

Every fallible function returns `Result[..., Str]` with deterministic
messages prefixed `gguf: `. Parse failures include bad magic, unsupported
version, truncation, NUL in any string, non-printable keys/tensor names,
unknown or nested value types, u64 values that do not fit Int, duplicate
tensor names, invalid alignment, and offsets past the data section.
Accessors report out-of-range indices, wrong-kind reads, and (only for the
explicit UTF-8 text accessors) malformed UTF-8 via
`gguf: string is not valid UTF-8`. See SPEC.md §6 for the exact catalog.

## Limitations

* Header only: tensor payloads are not decoded and their extents are not
  validated (only declared offsets, bounded by the data-section length).
* `gguf_builder_set_alignment` controls the padding; `gguf_builder_finish`
  emits an implicit `general.alignment` KV for non-default alignments
  unless one was added explicitly, so built headers declare their
  alignment.
* `i64` values with the sign bit set are rejected; integers must fit Int.
* `f32`/`f64` values are opaque raw bytes rendered as lowercase hex.
* Metadata keys and tensor names are printable ASCII. String values are
  arbitrary bytes; they are not validated as UTF-8 on parse, and a value
  containing NUL is rejected because `Str` is NUL-terminated. Non-UTF-8
  values round-trip losslessly through `gguf_kv_str`/`_bytes`, while the
  `_utf8` accessors return a typed error.

## License

MIT OR Apache-2.0. See the package headers and the repository LICENSE
files.
