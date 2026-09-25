<!-- XIOM -- xiom.gguf specification -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.gguf -- specification

## 1. Scope

A pure-XIOM, dependency-free codec for the **header** of a GGUF container
(version 2 and 3), the format used by llama.cpp-family model files:

* parse the metadata KV table and the tensor-info table into a queryable
  value (`gguf_parse`);
* expose accessors for every stored field;
* build a byte-exact header, including alignment padding, so a caller can
  append tensor payloads (`gguf_builder_*`).

## 2. Non-goals

* No tensor payload decoding (no ggml quantization tables, no element
  sizes): only declared offsets are bounds-checked.
* No float arithmetic: `f32`/`f64` values are preserved as the lowercase
  hex form of their raw little-endian bytes.
* No mmap/streaming; the whole buffer is parsed in one call.
* No inference, tokenizer or model semantics.
* Strings/names are restricted to printable ASCII (see §5).

## 3. Container layout

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `GGUF` (0x47 0x47 0x55 0x46) |
| 4 | 4 | u32 LE version (2 or 3; others rejected) |
| 8 | 8 | u64 LE tensor count (<= 1,048,576) |
| 16 | 8 | u64 LE metadata KV count (<= 1,048,576) |
| 24 | .. | KV entries, in declaration order |
| .. | .. | tensor infos, in declaration order |
| .. | pad | zero padding to the alignment boundary |
| data_offset | .. | tensor data section (offsets are relative to it) |

KV entry: `name` = u64 LE length + bytes; `type` = u32 LE; `value` per §4.

Tensor info: `name` (u64 length + bytes); `rank` = u32 LE (<= 64);
`dims` = rank x u64 LE; `ggml type` = u32 LE (0..12, not 8/9);
`offset` = u64 LE, relative to the data section.

Alignment: the integer KV `general.alignment` when present (power of two,
1..1,048,576), else 32. `data_offset` is the first offset >= end of the
tensor table that is a multiple of the alignment.

## 4. Value types

| Code | Name | Storage in `Gguf` | Notes |
|---|---|---|---|
| 0 | u8 | `kv_ints` | unsigned |
| 1 | i8 | `kv_ints` | sign-extended |
| 2 | u16 | `kv_ints` | unsigned |
| 3 | i16 | `kv_ints` | sign-extended |
| 4 | u32 | `kv_ints` | unsigned |
| 5 | i32 | `kv_ints` | sign-extended |
| 6 | f32 | `kv_strs` | 8 hex chars of the raw LE bytes |
| 7 | bool | `kv_ints` | 0 or 1, else error |
| 8 | string | `kv_strs` | printable ASCII, no NUL |
| 9 | array | `kv_arr_*` + `arr_ints`/`arr_strs` | homogeneous, no nesting |
| 10 | u64 | `kv_ints` | rejected when >= 2^63 (does not fit Int) |
| 11 | i64 | `kv_ints` | same restriction as u64 (documented) |
| 12 | f64 | `kv_strs` | 16 hex chars of the raw LE bytes |

Array elements follow the same per-element rules; element type 9 is
rejected. Counts are capped at 1,048,576.

## 5. Strings

Keys, string values, array string elements and tensor names must be
non-empty for keys/names and every byte must be in `0x20..0x7E`; NUL bytes
are rejected with a distinct error. This keeps the `Str` (NUL-terminated)
ABI contract sound and makes byte lengths exact.

## 6. Error catalog (exact messages)

Parse errors (`Err(Str)` from `gguf_parse`):

* `gguf: buffer too small for header`
* `gguf: bad magic`
* `gguf: unsupported version`
* `gguf: truncated value`
* `gguf: integer out of Int range`
* `gguf: string length exceeds buffer`
* `gguf: string contains NUL byte`
* `gguf: string is not printable ASCII`
* `gguf: unknown value type`
* `gguf: nested arrays are not supported`
* `gguf: bad array element count`
* `gguf: boolean value out of range`
* `gguf: count out of range`
* `gguf: tensor rank exceeds limit`
* `gguf: bad tensor type`
* `gguf: duplicate tensor name`
* `gguf: alignment is not an integer`
* `gguf: alignment is not a power of two`
* `gguf: data section offset exceeds buffer`
* `gguf: tensor offset exceeds data section`

Accessor errors: `gguf: key index out of range`, `gguf: tensor index out of
range`, `gguf: dimension index out of range`, `gguf: array element out of
range`, `gguf: value is not an integer`, `gguf: value is not a string`,
`gguf: value is not an array`, `gguf: array is not an integer array`,
`gguf: array is not a string array`, `gguf: key not found`,
`gguf: tensor not found`.

Builder errors: `gguf: alignment is not a power of two`,
`gguf: bad integer type`, `gguf: bad float type`, `gguf: bad tensor type`,
`gguf: boolean value out of range`, `gguf: key is not printable ASCII`,
`gguf: string is not printable ASCII`, `gguf: name is not printable ASCII`,
`gguf: invalid hex payload`, `gguf: negative dimension`,
`gguf: tensor rank exceeds limit`, `gguf: duplicate tensor name`,
`gguf: bad array element count`.

## 7. API contract

Parsing: `gguf_parse(&Vec[UInt8]) -> Result[Gguf, Str]`.

Header accessors: `gguf_version`, `gguf_kv_count`, `gguf_tensor_count`,
`gguf_alignment`, `gguf_data_offset`, `gguf_data_len`.

KV accessors: `gguf_kv_key`, `gguf_kv_type`, `gguf_kv_int`, `gguf_kv_str`,
`gguf_kv_arr_type`, `gguf_kv_arr_count`, `gguf_kv_arr_int`,
`gguf_kv_arr_str`, `gguf_find_kv`.

Tensor accessors: `gguf_tensor_name`, `gguf_tensor_ndims`,
`gguf_tensor_type`, `gguf_tensor_offset`, `gguf_tensor_dim`,
`gguf_find_tensor`, `gguf_type_name`.

Builder: `gguf_builder_new`, `gguf_builder_set_alignment`,
`gguf_builder_add_kv_int`, `gguf_builder_add_kv_str`,
`gguf_builder_add_kv_float`, `gguf_builder_add_kv_arr_int`,
`gguf_builder_add_kv_arr_str`, `gguf_builder_add_tensor`,
`gguf_builder_finish`. `gguf_builder_finish` emits exactly the header
(magic through padding); append payload bytes afterwards. When the
alignment set with `gguf_builder_set_alignment` differs from the default
32 and no explicit `general.alignment` KV was added, `finish` emits that
KV implicitly (first in the table) so the built header declares the
alignment it pads to and round-trips through `gguf_parse`.

## 8. Validation order (parse)

1. length >= 24, magic, version;
2. counts (u64 -> Int, <= 1,048,576);
3. per KV: name, type, value (bounds and range checks inside);
4. per tensor: name, rank, dims, type, offset; duplicate-name scan;
5. alignment from `general.alignment`; power-of-two check;
6. `data_offset` past buffer check; per-tensor offset <= data length.

## 9. Test matrix

| # | Check |
|---|---|
| 1 | minimal header: version/counts/alignment/data offset/data length |
| 2 | bad magic |
| 3 | version 1 rejected |
| 4 | short buffer |
| 5 | u32 KV type/value/find |
| 6 | string KV |
| 7 | bool KV |
| 8 | negative i8 round-trip (sign extension) |
| 9 | integer array KV: type/count/elements |
| 10 | f32 raw-hex preservation |
| 11 | tensor info: name/rank/dims/type/offset |
| 12 | duplicate tensor rejected (builder) |
| 13 | alignment 64 honoured (data offset 64) |
| 14 | alignment 48 rejected |
| 15 | unknown value type rejected |
| 16 | NUL in key rejected |
| 17 | u64 sign-bit value rejected |
| 18 | nested array rejected |
| 19 | truncated value rejected |
| 20 | full builder round-trip (5 KVs, 2 tensors) |
| 21 | tensor offset past data section rejected |
| 22 | missing key reported |
| 23 | missing tensor reported |
| 24 | type-name table |

## 10. Documented limitations

* `i64` values with the sign bit set are rejected (values must fit Int).
* Float values are opaque raw bytes (hex); no numeric conversion.
* Tensor extents (bytes per element) are not validated, only declared
  offsets and their bound against the data-section length.
* Non-ASCII (UTF-8) strings are rejected.

## 11. Compiler notes (v0.61.3)

Ok/Err construction is confined to leaf helpers; `Str` values read from
`Vec[Str]` fields are bound to typed locals and compared with
`str_compare`; every `UInt8` is widened with `(b as Int) & 0xFF`; parallel
vectors are only appended where all sibling pushes are mirrored;
`&struct.field` is never passed as a `&Vec[UInt8]` argument.
