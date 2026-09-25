# xiom.safetensors

> **Status:** IMPLEMENTED -- port-green with compiler 0.61.3 / pinned stdlib.
> Conformance: 21/21 PASS (`scripts/port.ps1 -Package xiom.safetensors`,
> `program_exit=0`). **Not published** -- publication remains out of scope.
> **Scope:** a pure-XIOM safetensors container codec: header parsing and
> validation, tensor-table accessors, payload extraction and a builder.
> **Deps:** `xiom.std` only (no FFI, no third-party dependencies).

## What it is

`xiom.safetensors` reads and writes the [safetensors] container layout:

```
[8 bytes]  little-endian u64 N (header length)
[N bytes]  JSON header
[rest]     tensor data section
```

The header maps a tensor name to `{"dtype": <string>, "shape":
[<non-negative ints>], "data_offsets": [<start>, <end>]}`; offsets are
relative to the start of the data section (absolute byte `8 + N`). The
module parses a documented JSON subset (ASCII strings, basic escapes,
integers, flat arrays, no nested objects), validates the tensor table
(unique names, monotonic non-overlapping offsets inside the data section,
shape size vs dtype size), exposes the table through free accessors, copies
payload spans out of a caller-held buffer, and builds containers whose
header is padded with spaces to an 8-byte boundary.

The scope is deliberately narrow: this is a container codec, not a tensor
library. There is no tensor math, no memory mapping, no dtype conversion and
no framework integration.

[safetensors]: https://github.com/huggingface/safetensors

## Install / use

```
xiom pkg install xiom.safetensors@0.1.0     # consumer
```

```xi
use xiom.safetensors;
```

## Quick start

Build a container and read it back:

```xi
module example
use xiom.safetensors;

fn main() -> Int {
  var b = st_builder_new();
  var dims = Vec[Int].new();
  dims.push(2);
  dims.push(2);
  var data = Vec[UInt8].new();          // 4 F32 bytes = 16 total
  var i = 0;
  while i < 16 { data.push(0 as UInt8); i = i + 1; }
  let added = st_builder_add(&mut b, "weight", "F32", &dims, &data);
  if !added.is_ok {
    return 1;
  }
  let container = st_builder_finish(&b);

  let parsed = st_parse(&container);
  if !parsed.is_ok {
    return 2;
  }
  let f: SafetensorsFile = parsed.value;
  let name = st_tensor_name(&f, 0);
  let bytes = st_tensor_bytes(&f, 0, &container);
  // name == "weight", bytes == data
  return 0;
}
```

## API summary

All functions are free functions in module `xiom.safetensors`.

| Function | Returns | Description |
|---|---|---|
| `st_parse(buffer)` | `Result[SafetensorsFile, Str]` | Parse and validate a whole container. |
| `st_tensor_count(f)` | `Int` | Number of tensors. |
| `st_header_len(f)` | `Int` | Raw header length N. |
| `st_data_start(f)` / `st_data_len(f)` | `Int` | Absolute data-section start (8 + N) / payload size. |
| `st_tensor_name(f, i)` | `Result[Str, Str]` | Name at index `i`. |
| `st_tensor_dtype(f, i)` | `Result[Str, Str]` | Dtype token at index `i`. |
| `st_tensor_rank(f, i)` | `Result[Int, Str]` | Rank (0 for a scalar). |
| `st_tensor_dim(f, i, d)` | `Result[Int, Str]` | Dimension `d` of tensor `i`. |
| `st_tensor_offset_start(f, i)` / `st_tensor_offset_end(f, i)` | `Result[Int, Str]` | Payload span relative to the data section. |
| `st_tensor_data_len(f, i)` | `Result[Int, Str]` | Payload size in bytes. |
| `st_tensor_bytes(f, i, container)` | `Result[Vec[UInt8], Str]` | Copy of the payload bytes from `container`. |
| `st_find_tensor(f, name)` | `Result[Int, Str]` | Index of a tensor by name. |
| `st_dtype_size(dtype)` | `Int` | Bytes per element for documented tokens, 0 otherwise. |
| `st_shape_element_count(dims)` | `Int` | Shape product; -1 on negative/overflow. |
| `st_builder_new()` | `SafetensorsBuilder` | New empty builder. |
| `st_builder_add(b, name, dtype, dims, data)` | `Result[Int, Str]` | Append one tensor; returns its index. |
| `st_builder_tensor_count(b)` / `st_builder_payload_len(b)` | `Int` | Builder state. |
| `st_builder_header_json(b)` | `Str` | Compact header JSON (no padding). |
| `st_builder_finish(b)` | `Vec[UInt8]` | Serialize the full container. |

## Error model

Every fallible call returns `Result[_, Str]` with a deterministic message
that starts with `safetensors: `; parser errors additionally carry the byte
position of the offending character. Messages are stable, so callers may
match them (the module itself never does). The full catalog is in
[SPEC.md](SPEC.md#error-string-catalog); the families are:

- container prefix errors: short buffer, header length out of signed range,
  header length past the buffer, empty header, NUL byte in the header;
- JSON-subset errors: unexpected token, missing `:`/`,`/`]`/`}`, bad
  escapes, control/non-ASCII bytes, unterminated strings, trailing data;
- semantic errors: empty tensor name, duplicate names, duplicate/unknown/
  missing keys, `__metadata__`, `start > end`, offsets past the data
  section, non-monotonic offsets, shape size mismatch, overflow;
- accessor errors: tensor index out of range, dim index out of range,
  tensor not found, container smaller than the tensor data;
- builder errors: empty/non-ASCII name or dtype, duplicate name, negative
  dimension, overflow, data length mismatch.

## Limitations

- **ASCII-only headers.** Tensor names and dtype tokens must be printable
  ASCII in the builder, and the parser rejects raw bytes `>= 0x80`;
  `\uXXXX` escapes are accepted only for code points `0x20..0x7E`.
- **No `__metadata__`.** Metadata objects are a nested object kind, which
  the documented subset excludes; they are rejected with a dedicated error.
- **No nested objects.** A tensor's value must be a flat object with exactly
  `dtype`, `shape` and `data_offsets`.
- **Unknown dtype tokens are opaque.** They parse and round-trip, but
  `st_dtype_size` returns 0 and shape/size validation is skipped for them.
- **Holes are allowed.** Offsets must be monotonic and non-overlapping, but
  need not cover the data section contiguously (a documented relaxation).
- **No tensor math, mmap, dtype conversion, lazy views or framework
  integration.** Payloads are copied out of an in-memory `Vec[UInt8]`.
- The container header length N is accepted as any value (padded or not);
  the builder always pads with spaces to a multiple of 8.

## Tests

```
& .\scripts\port.ps1 -Package xiom.safetensors
```

Expected: 21 `[PASS]` lines, then `xiom.safetensors: all tests passed`, and
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
