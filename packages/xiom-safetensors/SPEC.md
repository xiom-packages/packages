# xiom.safetensors -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.safetensors`, version `0.1.0`).
Module: `src/safetensors.xi` (`module xiom.safetensors`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`, `xiom.convert`).

## Scope

A pure-XIOM (no FFI) reader and builder for the safetensors container:

- decode the 8-byte little-endian u64 header length N and the N header
  bytes;
- parse the header as a constrained JSON subset: a top-level object mapping
  a tensor name to an object with exactly the keys `dtype` (string),
  `shape` (flat array of non-negative integers) and `data_offsets` (flat
  array of two non-negative integers);
- validate the assembled tensor table (unique names, offsets monotonic,
  non-overlapping and inside the data section, shape product vs dtype size
  for documented fixed-width dtypes);
- expose the table through free accessors (count, name, dtype, rank, dims,
  offsets, span) and copy a tensor's payload out of a caller-supplied
  container buffer;
- build containers: append tensors with concatenated payloads and emit the
  prefix, the compact header JSON padded with spaces to a multiple of 8
  bytes, and the payload;
- deterministic `Err(Str)` messages for every failure, with the byte
  position of the offending character where one exists.

## Non-goals

- Tensor math, dtype conversion, quantization, reshaping, slicing.
- `mmap`, streaming, lazy tensor views, zero-copy borrowed slices.
- Framework integration (PyTorch, NumPy, ONNX, ...).
- JSON features outside the documented subset: nested objects/arrays,
  floats, exponents, negative integers, `null`, `true`/`false`, raw UTF-8
  bytes in strings, escapes other than `\\`, `\"`, `\n`, `\t`, `\uXXXX`.
- `__metadata__` (a nested object of string pairs in the reference format);
  it is rejected with a dedicated error.
- Requiring contiguously indexed data (holes between tensors are allowed
  here, as long as offsets are monotonic and non-overlapping).
- Shape/size validation for dtype tokens outside the documented table
  (opaque pass-through).

## Container layout

```
offset 0           8 bytes   little-endian u64 N (header length)
offset 8           N bytes   header JSON (ASCII in this subset)
offset 8 + N       ...       tensor data section
```

- `N` is stored as an unsigned 64-bit integer; values above `INT64_MAX`
  are rejected (`safetensors: header length out of range`).
- `N` must satisfy `N <= buffer.len() - 8`; `N == 0` is rejected.
- `data_offsets` are relative to the start of the data section, so a tensor
  byte range `[start, end)` lives at absolute `[8 + N + start,
  8 + N + end)`.
- The reference implementation pads the header with spaces (`0x20`) so that
  N is a multiple of 8; this codec's builder always does that, while
  `st_parse` accepts any `N` (including unpadded headers).

## JSON subset

Grammar (whitespace is space, TAB, LF or CR anywhere between tokens):

```
header        = "{" [ pair { "," pair } ] "}"
pair          = string ":" tensor
tensor        = "{" info { "," info } "}"          (* non-empty *)
info          = "dtype" ":" string
              | "shape" ":" int_array
              | "data_offsets" ":" int_array
string        = '"' { char | escape } '"'
escape        = "\\" | "\"" | "\n" | "\t" | "\u" hex4
int_array     = "[" [ int { "," int } ] "]"
int           = "0" | digit1-9 { digit }           (* non-negative, no sign *)
hex4          = 4 * hexdigit                       (* value must be 0x20..0x7E *)
```

Semantics and documented restrictions:

| Item | Rule |
|---|---|
| Top level | Exactly one object; empty (`{}`) is a valid zero-tensor header. |
| Duplicate tensor names | Rejected. |
| Tensor object | Must contain `dtype`, `shape` and `data_offsets` exactly once each; empty object rejected. |
| Unknown tensor keys | Rejected, including `__metadata__` (dedicated message). |
| `dtype` | Non-empty string. Documented tokens get size validation; any other non-empty token is passed through opaquely. |
| `shape` | Flat array of non-negative integers; `[]` is a scalar (1 element); each dimension may be 0. Leading zeros (`01`) and a leading `-` are rejected. |
| `data_offsets` | Flat array of exactly two non-negative integers `[start, end]`; `start <= end` required. |
| Strings | Raw bytes must be printable ASCII (`0x20..0x7E`); control characters and bytes `>= 0x80` are rejected. |
| Escapes | `\\`, `\"`, `\n`, `\t` map to the literal characters; `\uXXXX` accepts code points `0x20..0x7E` only (others are rejected as non-printable). |
| Other values | `{...}` nested objects, arrays as tensor values, floats (`1.5`, `1e3`), negative integers, `null`, `true`, `false` are all rejected with a positional error. |
| Trailing data | Any non-whitespace after the top-level `}` is rejected. |
| Numbers | Only non-negative decimal integers without sign or leading zeros; the value must fit in a signed 64-bit `Int`. |

## Dtype table

`st_dtype_size(dtype)` returns the element width for these documented
tokens and `0` for any other token (opaque pass-through):

| Token | Bytes | Notes |
|---|---|---|
| `F64` | 8 | IEEE-754 binary64 |
| `F32` | 4 | IEEE-754 binary32 |
| `F16` | 2 | IEEE-754 binary16 |
| `BF16` | 2 | bfloat16 |
| `I64` | 8 | signed |
| `I32` | 4 | signed |
| `I16` | 2 | signed |
| `I8` | 1 | signed |
| `U8` | 1 | unsigned |
| `BOOL` | 1 | one byte per element |
| `F8_E4M3` | 1 | FP8 |
| `F8_E5M2` | 1 | FP8 |
| any other token | 0 | opaque: no shape/size validation |

For a documented token of width `w`, parsing requires
`st_shape_element_count(shape) * w == end - start` (with an explicit
overflow check); for width `0` the size check is skipped.

## Validation rules (st_parse)

In order per tensor `i` (declaration order):

1. `start <= end` (`safetensors: data_offsets start > end for tensor '<name>'`).
2. `end <= data_len` where `data_len = buffer.len() - (8 + N)`
   (`safetensors: data_offsets exceed data section for tensor '<name>'`).
3. For `i > 0`: `start >= offsets_end[i-1]`
   (`safetensors: data_offsets not monotonic for tensor '<name>'`).
   Overlap is therefore rejected; gaps (holes) are allowed.
4. For documented dtypes: element count times width equals the span
   (`safetensors: shape size does not match data length for tensor
   '<name>'`); an overflowing product is reported as `safetensors: shape
   product overflows for tensor '<name>'`.

Duplicate tensor names are rejected while reading the header, before the
second body is parsed. `dtype` may not be empty.

## API signatures

All functions are free functions in module `xiom.safetensors`:

```xi
pub type SafetensorsFile = { names: Vec[Str]; dtypes: Vec[Str];
  ranks: Vec[Int]; shape_offsets: Vec[Int]; dims: Vec[Int];
  offsets_start: Vec[Int]; offsets_end: Vec[Int];
  header_len: Int; data_start: Int; data_len: Int; }

pub type SafetensorsBuilder = { names: Vec[Str]; dtypes: Vec[Str];
  ranks: Vec[Int]; shape_offsets: Vec[Int]; dims: Vec[Int];
  payload: Vec[UInt8]; offsets_start: Vec[Int]; offsets_end: Vec[Int]; }

pub fn st_parse(buffer: &Vec[UInt8]) -> Result[SafetensorsFile, Str]

pub fn st_tensor_count(f: &SafetensorsFile) -> Int
pub fn st_header_len(f: &SafetensorsFile) -> Int
pub fn st_data_start(f: &SafetensorsFile) -> Int
pub fn st_data_len(f: &SafetensorsFile) -> Int
pub fn st_tensor_name(f: &SafetensorsFile, i: Int) -> Result[Str, Str]
pub fn st_tensor_dtype(f: &SafetensorsFile, i: Int) -> Result[Str, Str]
pub fn st_tensor_rank(f: &SafetensorsFile, i: Int) -> Result[Int, Str]
pub fn st_tensor_dim(f: &SafetensorsFile, i: Int, d: Int) -> Result[Int, Str]
pub fn st_tensor_offset_start(f: &SafetensorsFile, i: Int) -> Result[Int, Str]
pub fn st_tensor_offset_end(f: &SafetensorsFile, i: Int) -> Result[Int, Str]
pub fn st_tensor_data_len(f: &SafetensorsFile, i: Int) -> Result[Int, Str]
pub fn st_tensor_bytes(f: &SafetensorsFile, i: Int, container: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn st_find_tensor(f: &SafetensorsFile, name: Str) -> Result[Int, Str]
pub fn st_dtype_size(dtype: Str) -> Int
pub fn st_shape_element_count(dims: &Vec[Int]) -> Int

pub fn st_builder_new() -> SafetensorsBuilder
pub fn st_builder_tensor_count(b: &SafetensorsBuilder) -> Int
pub fn st_builder_payload_len(b: &SafetensorsBuilder) -> Int
pub fn st_builder_add(b: &mut SafetensorsBuilder, name: Str, dtype: Str, dims: &Vec[Int], data: &Vec[UInt8]) -> Result[Int, Str]
pub fn st_builder_header_json(b: &SafetensorsBuilder) -> Str
pub fn st_builder_finish(b: &SafetensorsBuilder) -> Vec[UInt8]
```

## Semantics

`st_parse(buffer)`
: Parses and validates; does not retain `buffer`. The returned file stores
  parallel per-tensor vectors (no `Vec[StructType]`) and the data-section
  bounds. Declaration order is preserved.

`st_tensor_name` / `st_tensor_dtype` / `st_tensor_rank` / `st_tensor_dim` /
`st_tensor_offset_start` / `st_tensor_offset_end` / `st_tensor_data_len`
: Read-only accessors. Tensor indices are `0..count-1`; out-of-range tensor
  indices return `safetensors: tensor index out of range`, dimension indices
  outside `0..rank-1` return `safetensors: dim index out of range`.
  A scalar has rank 0; `st_tensor_data_len` is `end - start`.

`st_tensor_bytes(f, i, container)`
: Copies `container[data_start + start .. data_start + end)`. The container
  should be the buffer that was parsed; a shorter buffer yields
  `safetensors: container is smaller than the tensor data`. Complexity
  O(span).

`st_find_tensor(f, name)`
: First matching name in declaration order, or
  `safetensors: tensor not found: '<name>'`.

`st_dtype_size` / `st_shape_element_count`
: Integer-only helpers. `st_shape_element_count` is `1` for `[]`, `0` when
  any dimension is 0, `-1` on a negative dimension or signed overflow.
  No floating point is used anywhere in the module.

`st_builder_add(b, name, dtype, dims, data)`
: Validates and appends. `name` and `dtype` must be non-empty printable
  ASCII; duplicate names, negative dimensions, overflows and (for
  documented dtypes) a `data.len()` different from
  `element_count * width` are rejected. The payload is concatenated in call
  order; `data_offsets` are relative to the start of that concatenation,
  i.e. the offset starts at `st_builder_payload_len` before the call.
  Returns the new tensor's index.

`st_builder_header_json(b)`
: Compact JSON, key order fixed as `dtype`, `shape`, `data_offsets`,
  tensors in insertion order; `"` and `\` in names/tokens are escaped.

`st_builder_finish(b)`
: Emits the 8-byte little-endian length, the header JSON, zero or more
  `0x20` padding bytes so that the total header length is a multiple of 8,
  then the payload. Consequence: the data section always starts at an
  8-byte-aligned absolute offset `8 + N`.

## Error string catalog

All messages start with `safetensors: `. `K` is a 0-based byte index into
the header string (not the container).

Container prefix:

| Condition | Message |
|---|---|
| `buffer.len() < 8` | `safetensors: buffer too small for header length` |
| u64 N above `INT64_MAX` | `safetensors: header length out of range` |
| `N > buffer.len() - 8` | `safetensors: header length exceeds buffer` |
| `N == 0` | `safetensors: header is empty` |
| header byte `0x00` | `safetensors: header contains NUL byte` |

Parser (positional, `<message>` below is followed by ` at byte K`):

| Condition | Message |
|---|---|
| top-level value is not `{` | `expected '{'` |
| tensor name is not a string | `expected '"' for tensor name` |
| tensor key is not a string | `expected '"' for tensor key` |
| missing `:` after a key or name | `expected ':'` |
| tensor value is not `{` | `tensor value must be an object` |
| `dtype` value is not a string | `dtype must be a string` |
| `shape` value is not `[` | `shape must be an array` |
| `data_offsets` value is not `[` | `data_offsets must be an array` |
| expected separator after an entry | `expected ',' or '}'` |
| expected separator after an array element | `expected ',' or ']'` |
| integer expected | `expected non-negative integer` |
| leading `-` | `negative integers are not supported` |
| digit after a leading `0` | `leading zero in integer` |
| value above `INT64_MAX` | `integer out of range` |
| escape other than `\\ \" \n \t \u` | `unsupported escape` |
| non-hex digit in `\uXXXX` | `invalid \u escape` |
| `\uXXXX` code point outside `0x20..0x7E` | `non-printable \u escape` |
| byte below `0x20` in a string | `control character in string` |
| byte `>= 0x80` in a string | `non-ASCII byte in string` |
| non-whitespace after the top-level object | `trailing data` |

Unpositioned parser/semantic errors:

| Condition | Message |
|---|---|
| string runs to end of header | `safetensors: unterminated string` |
| tensor object `{}` | `safetensors: tensor object is empty` |
| duplicate key inside a tensor | `safetensors: duplicate key '<key>'` |
| key other than the three documented ones | `safetensors: unknown tensor key '<key>'` |
| top-level `__metadata__` | `safetensors: '__metadata__' metadata objects are not supported` |
| missing mandatory key | `safetensors: missing key '<key>'` |
| `data_offsets` array length != 2 | `safetensors: data_offsets must contain exactly two integers` |
| empty top-level tensor name | `safetensors: tensor name must not be empty` |
| repeated tensor name | `safetensors: duplicate tensor name '<name>'` |
| empty dtype string | `safetensors: dtype must not be empty for tensor '<name>'` |
| `start > end` | `safetensors: data_offsets start > end for tensor '<name>'` |
| `end > data_len` | `safetensors: data_offsets exceed data section for tensor '<name>'` |
| overlap with the previous tensor | `safetensors: data_offsets not monotonic for tensor '<name>'` |
| shape product overflow | `safetensors: shape product overflows for tensor '<name>'` |
| `count * width != end - start` | `safetensors: shape size does not match data length for tensor '<name>'` |

Accessors:

| Condition | Message |
|---|---|
| tensor index out of `0..count-1` | `safetensors: tensor index out of range` |
| dimension index out of `0..rank-1` | `safetensors: dim index out of range` |
| `st_find_tensor` miss | `safetensors: tensor not found: '<name>'` |
| container shorter than the declared span | `safetensors: container is smaller than the tensor data` |

Builder:

| Condition | Message |
|---|---|
| empty name | `safetensors: builder: tensor name must not be empty` |
| non-printable-ASCII name | `safetensors: builder: tensor name must be printable ASCII` |
| empty dtype | `safetensors: builder: dtype must not be empty` |
| non-printable-ASCII dtype | `safetensors: builder: dtype must be printable ASCII` |
| duplicate name | `safetensors: builder: duplicate tensor name '<name>'` |
| negative dimension | `safetensors: builder: negative dimension for tensor '<name>'` |
| shape product overflow | `safetensors: builder: shape product overflows for tensor '<name>'` |
| documented dtype size mismatch | `safetensors: builder: data length does not match shape for tensor '<name>'` |

Two internal messages are unreachable from a parsed file (the parser cannot
produce them): `safetensors: negative shape dimension` and
`safetensors: shape product overflows` (the per-tensor message with the
name is used instead). They are documented for catalog completeness.

## Complexity

| Operation | Complexity |
|---|---|
| `st_parse` | O(N + tensor count) plus O(dim total) |
| accessors | O(1) (`st_tensor_bytes` O(span), `st_find_tensor` O(count)) |
| `st_builder_add` | O(data length + dims) incl. O(name) duplicate scan per call |
| `st_builder_header_json` / `st_builder_finish` | O(header + payload) |

## Test matrix

`tests/test_conformance.xi` (`module safetensors_tests`, 21 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. empty container round-trip: zero tensors, 8-aligned header, empty data;
2. single F32 tensor accessors (name/dtype/rank/dims/offsets/span);
3. payload byte round-trip through `st_tensor_bytes`;
4. two tensors: concatenated offsets, second payload, rank;
5. builder layout: LE u64 N, raw JSON prefix, space padding, payload start;
6. manually crafted unpadded header parses;
7. dtype size table (all 12 tokens + opaque 0) and shape element counts
   (product, zero dim, scalar, negative, overflow);
8. container errors: short buffer, `N=0`, `N` past the buffer;
9. header length above `INT64_MAX` rejected;
10. NUL byte in the header rejected;
11. structural errors: `{`, `:`, non-object tensor value, trailing data,
    empty tensor object;
12. escapes: valid `\u0041`, `\"`, `\\`, `\n`, `\t`; invalid `\u0080`,
    `\q`, raw `0x80`;
13. duplicate tensor name rejected;
14. missing `dtype`/`shape`/`data_offsets` rejected;
15. `__metadata__` and unknown tensor keys rejected;
16. offsets: `start > end`, beyond the data section, non-monotonic;
17. shape validation: fixed-width mismatch, opaque dtype pass-through,
    scalar (empty shape);
18. builder validation: empty/non-ASCII name, empty dtype, duplicate,
    negative dimension, size mismatch, opaque pass-through;
19. `st_find_tensor` and out-of-range accessor errors;
20. `st_tensor_bytes` with a truncated container and a bad index;
21. integer/value errors: negative, float token, leading zero, overflow,
    `null` dtype, empty tensor name.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.safetensors
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- ASCII-only string subset (see JSON subset); no UTF-8 names or dtype
  tokens, no `\u` code points above `0x7E`.
- `__metadata__` is not supported and is rejected explicitly.
- Unknown dtype tokens skip shape/size validation (opaque pass-through).
- Holes between tensor spans are accepted (only monotonicity and
  non-overlap are enforced), unlike the reference implementation's
  fully-indexed requirement.
- `st_parse` does not retain the container buffer; callers keep it and pass
  it to `st_tensor_bytes` for payload copies.
- No tensor math, mmap, dtype conversion, endianness conversion or
  framework integration.
- Strings are built with `xiom.string.builder.sb_to_str`, which requires
  NUL-free bytes; the parser rejects NULs (`header contains NUL byte`,
  control characters in strings) before materializing any `Str`.
- The file/builder types are plain structs with parallel `Vec` fields (the
  pinned compiler miscompiles `Vec[StructType]`); fields are implementation
  details reached through the accessors.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers at the top
  of the module (constructing Results directly in other functions
  miscompiles on this pin), one helper pair per payload type.
- Every `UInt8` is widened with `(b as Int) & 0xFF` before comparisons or
  arithmetic; `byte_at` results are never compared directly against UInt8
  constants (BUG-17 discipline).
- `Str` values read out of `Vec[Str]` are bound to typed locals and compared
  with `xiom.string.compare.str_compare`, never with `==`.
- `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
  expected (the installed compiler reads such an argument as an empty
  vector); tests bind the container to a local and pass `&local`.
- `&mut Vec[UInt8]` arguments are written with an explicit `&mut` at the
  call site; calls that forward an existing `&mut` binding pass it directly.
- No `Vec[Float64]`, no `Vec[StructType]`, no self methods, no indexed
  `Vec[fn]` dispatch; the tests call each `tN()` directly.
- Big-endian/little-endian prefix decoding uses arithmetic modulo/division
  rather than bit tricks on sign-extended bytes.
