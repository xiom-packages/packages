# xiom.nii -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.nii`, version `0.1.0`).
Module: `src/nii.xi` (`module xiom.nii`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.convert`, `xiom.encoding.hex`); the tests additionally use `xiom.io`
and `xiom.test`. The package declares no `extern "C"` blocks.

## Scope

A pure-XIOM (no FFI) codec for the 348-byte NIfTI-1 header:

- `nii_parse` decodes and validates a header buffer, auto-detecting the
  little-endian form and the big-endian (byteswapped) form and normalizing
  both to canonical little-endian field values;
- `nii_to_bytes` re-emits the canonical 348 little-endian bytes;
- accessors expose dims, datatype/bitpix, form codes, intent/slice fields,
  text fields, magic kind, the extension flag and every float32 field as a
  raw 4-byte token and an 8-character lowercase hex string;
- `NiftiBuilder` emits a canonical little-endian single-file header
  (magic `n+1`), with per-field setters that validate and leave the builder
  unchanged on Err;
- deterministic `Err(Str)` messages for malformed input (see the catalog
  below).

## Non-goals

- Voxel data reading/writing; the codec never touches the image payload.
- sform/qform matrix math: quaternion and srow values stay raw float32
  tokens.
- NIfTI-2, Analyze 7.5 (no magic) and compressed variants (`.nii.gz`).
- Extension payload parsing: the flag byte is reported, reserved bytes and
  extension data are ignored.
- Floating-point storage or arithmetic; `vox_offset >= 0` uses the IEEE-754
  sign bit only.
- Charset handling or escaping for the text fields beyond NUL trimming.
- Streaming: the whole header is an in-memory `Vec[UInt8]`.

## Byte-level layout

The header is 348 bytes. `off` is relative to the header start; all
multi-byte fields are little-endian in the canonical form. `char[N]`
fields are NUL-padded text.

| off | size | field | type |
|---|---|---|---|
| 0 | 4 | sizeof_hdr | int32 (must be 348) |
| 4 | 10 | data_type (unused) | char[10] |
| 14 | 18 | db_name (unused) | char[18] |
| 32 | 4 | extents (unused) | int32 |
| 36 | 2 | session_error (unused) | int16 |
| 38 | 1 | regular (unused) | char |
| 39 | 1 | dim_info (unused) | char |
| 40 | 16 | dim[8] | int16[8] |
| 56 | 4 | intent_p1 | float32 |
| 60 | 4 | intent_p2 | float32 |
| 64 | 4 | intent_p3 | float32 |
| 68 | 2 | intent_code | int16 |
| 70 | 2 | datatype | int16 |
| 72 | 2 | bitpix | int16 |
| 74 | 2 | slice_start | int16 |
| 76 | 32 | pixdim[8] | float32[8] |
| 108 | 4 | vox_offset | float32 |
| 112 | 4 | scl_slope | float32 |
| 116 | 4 | scl_inter | float32 |
| 120 | 2 | slice_end | int16 |
| 122 | 1 | slice_code | char (0..255) |
| 123 | 1 | xyzt_units | char (0..255) |
| 124 | 4 | cal_max | float32 |
| 128 | 4 | cal_min | float32 |
| 132 | 4 | slice_duration | float32 |
| 136 | 4 | toffset | float32 |
| 140 | 4 | glmax (unused) | int32 |
| 144 | 4 | glmin (unused) | int32 |
| 148 | 80 | descrip | char[80] |
| 228 | 24 | aux_file | char[24] |
| 252 | 2 | qform_code | int16 |
| 254 | 2 | sform_code | int16 |
| 256 | 4 | quatern_b | float32 |
| 260 | 4 | quatern_c | float32 |
| 264 | 4 | quatern_d | float32 |
| 268 | 4 | qoffset_x | float32 |
| 272 | 4 | qoffset_y | float32 |
| 276 | 4 | qoffset_z | float32 |
| 280 | 16 | srow_x[4] | float32[4] |
| 296 | 16 | srow_y[4] | float32[4] |
| 312 | 16 | srow_z[4] | float32[4] |
| 328 | 16 | intent_name | char[16] |
| 344 | 4 | magic | `n+1\0` or `ni1\0` |

Immediately after the header, byte 348 starts the 4-byte extension flag:
first byte `0` means no extensions, nonzero means extensions are present
(the reserved bytes 349..351 and any extension payloads are outside this
codec). For `n+1` single-file headers the image data starts at
`vox_offset` (>= 352 when an extension flag is present); for `ni1` the
voxels live in an external `.img` file.

## Datatype table

The only datatype codes accepted by validation (and by
`nii_builder_set_datatype`, which also writes the matching bitpix):

| Code | Name | bitpix |
|---|---|---|
| 2 | `NIFTI_TYPE_UINT8` | 8 |
| 4 | `NIFTI_TYPE_INT16` | 16 |
| 8 | `NIFTI_TYPE_INT32` | 32 |
| 16 | `NIFTI_TYPE_FLOAT32` | 32 |
| 32 | `NIFTI_TYPE_COMPLEX64` | 64 |
| 64 | `NIFTI_TYPE_FLOAT64` | 64 |
| any other | rejected | -- |

`nii_datatype_bitpix` returns `-1` and `nii_datatype_name` returns `""` for
any code outside the table (including the legacy `NIFTI_TYPE_UNKNOWN` 0).

## Endianness rules

1. `sizeof_hdr` is decoded as little-endian u32 from bytes 0..4. When it is
   348, the buffer is little-endian and no fields are swapped.
2. Otherwise the same bytes are decoded as big-endian u32. When that is
   348, the buffer is big-endian: all multi-byte fields are byteswapped in
   file order (including the unused `extents`, `session_error`, `glmax`,
   `glmin`) into the canonical little-endian form, and `nii_swapped` is
   true.
3. When neither decode is 348, parsing fails with
   `nii: unsupported sizeof_hdr <n>`, where `<n>` is the little-endian
   decode reported deterministically.

`nii_to_bytes` always emits the canonical little-endian 348 bytes, so a
big-endian fixture and the equivalent little-endian fixture parse to equal
field values and produce the same output bytes.

## API signatures

All functions are free functions in module `xiom.nii` (no self methods):

```xi
pub const NII_HEADER_LEN: Int = 348;
pub const NII_MAGIC_SINGLE: Int = 0;   // "n+1\0"
pub const NII_MAGIC_PAIR: Int = 1;     // "ni1\0"
pub const NII_EXT_NONE: Int = 0;
pub const NII_EXT_UNKNOWN: Int = -1;
pub const NII_FLOAT_VOX_OFFSET: Int = 0;   // .. through
pub const NII_FLOAT_QOFFSET_Z: Int = 15;   // 16 singleton float ids

pub type NiftiHeader = { raw: Vec[UInt8]; swapped: Bool; ext_flag: Int; }
pub type NiftiBuilder = { raw: Vec[UInt8]; }

pub fn nii_parse(buffer: &Vec[UInt8]) -> Result[NiftiHeader, Str]
pub fn nii_to_bytes(h: &NiftiHeader) -> Vec[UInt8]
pub fn nii_swapped(h: &NiftiHeader) -> Bool
pub fn nii_ext_flag(h: &NiftiHeader) -> Int

pub fn nii_datatype_bitpix(datatype: Int) -> Int
pub fn nii_datatype_name(datatype: Int) -> Str
pub fn nii_datatype_known(datatype: Int) -> Bool

pub fn nii_sizeof_hdr(h: &NiftiHeader) -> Int
pub fn nii_dim_count(h: &NiftiHeader) -> Int
pub fn nii_dim(h: &NiftiHeader, i: Int) -> Result[Int, Str]
pub fn nii_datatype(h: &NiftiHeader) -> Int
pub fn nii_bitpix(h: &NiftiHeader) -> Int
pub fn nii_intent_code(h: &NiftiHeader) -> Int
pub fn nii_qform_code(h: &NiftiHeader) -> Int
pub fn nii_sform_code(h: &NiftiHeader) -> Int
pub fn nii_slice_start(h: &NiftiHeader) -> Int
pub fn nii_slice_end(h: &NiftiHeader) -> Int
pub fn nii_slice_code(h: &NiftiHeader) -> Int
pub fn nii_xyzt_units(h: &NiftiHeader) -> Int
pub fn nii_magic_kind(h: &NiftiHeader) -> Int
pub fn nii_descrip(h: &NiftiHeader) -> Str
pub fn nii_aux_file(h: &NiftiHeader) -> Str
pub fn nii_intent_name(h: &NiftiHeader) -> Str

pub fn nii_raw_hex(v: &Vec[UInt8]) -> Str
pub fn nii_float_raw(h: &NiftiHeader, field: Int) -> Result[Vec[UInt8], Str]
pub fn nii_float_hex(h: &NiftiHeader, field: Int) -> Result[Str, Str]
pub fn nii_pixdim_raw(h: &NiftiHeader, i: Int) -> Result[Vec[UInt8], Str]
pub fn nii_pixdim_hex(h: &NiftiHeader, i: Int) -> Result[Str, Str]
pub fn nii_srow_raw(h: &NiftiHeader, row: Int, col: Int) -> Result[Vec[UInt8], Str]
pub fn nii_srow_hex(h: &NiftiHeader, row: Int, col: Int) -> Result[Str, Str]

pub fn nii_builder_new() -> NiftiBuilder
pub fn nii_builder_finish(b: &NiftiBuilder) -> Result[Vec[UInt8], Str]
pub fn nii_builder_set_dim(b: &mut NiftiBuilder, i: Int, v: Int) -> Result[Unit, Str]
pub fn nii_builder_set_datatype(b: &mut NiftiBuilder, datatype: Int) -> Result[Unit, Str]
pub fn nii_builder_set_float(b: &mut NiftiBuilder, field: Int, token: &Vec[UInt8]) -> Result[Unit, Str]
pub fn nii_builder_set_pixdim(b: &mut NiftiBuilder, i: Int, token: &Vec[UInt8]) -> Result[Unit, Str]
pub fn nii_builder_set_srow(b: &mut NiftiBuilder, row: Int, col: Int, token: &Vec[UInt8]) -> Result[Unit, Str]
pub fn nii_builder_set_qform_code(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str]
pub fn nii_builder_set_sform_code(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str]
pub fn nii_builder_set_intent_code(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str]
pub fn nii_builder_set_slice_start(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str]
pub fn nii_builder_set_slice_end(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str]
pub fn nii_builder_set_slice_code(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str]
pub fn nii_builder_set_xyzt_units(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str]
pub fn nii_builder_set_magic(b: &mut NiftiBuilder, kind: Int) -> Result[Unit, Str]
pub fn nii_builder_set_descrip(b: &mut NiftiBuilder, s: Str) -> Result[Unit, Str]
pub fn nii_builder_set_aux_file(b: &mut NiftiBuilder, s: Str) -> Result[Unit, Str]
pub fn nii_builder_set_intent_name(b: &mut NiftiBuilder, s: Str) -> Result[Unit, Str]
```

## Singleton float field ids

`nii_float_raw` / `nii_float_hex` / `nii_builder_set_float` use these
`NII_FLOAT_*` ids (pixdim and srow have dedicated indexed accessors):

| id | field | off | id | field | off |
|---|---|---|---|---|---|
| 0 | vox_offset | 108 | 8 | intent_p2 | 60 |
| 1 | scl_slope | 112 | 9 | intent_p3 | 64 |
| 2 | scl_inter | 116 | 10 | quatern_b | 256 |
| 3 | cal_max | 124 | 11 | quatern_c | 260 |
| 4 | cal_min | 128 | 12 | quatern_d | 264 |
| 5 | slice_duration | 132 | 13 | qoffset_x | 268 |
| 6 | toffset | 136 | 14 | qoffset_y | 272 |
| 7 | intent_p1 | 56 | 15 | qoffset_z | 276 |

Raw tokens are exactly 4 bytes in canonical little-endian order; hex tokens
are exactly 8 lowercase characters (`nii_raw_hex` of the same 4 bytes).
`nii_builder_set_float` / `_pixdim` / `_srow` reject tokens whose length is
not 4.

## Semantics

`nii_parse(buffer)`
: Requires `buffer.len() >= 348`. Detects endianness, copies the 348 header
  bytes (byteswapping a big-endian source), validates in the documented
  order, and returns the header. When at least 4 bytes follow the header,
  byte 348 is read into `ext_flag` (`0` = no extensions); otherwise the
  flag is `NII_EXT_UNKNOWN`. Bytes after the header (and after the flag)
  are ignored.

`nii_to_bytes(h)` / `nii_swapped(h)` / `nii_ext_flag(h)`
: Canonical byte re-emission and parse provenance; O(348) / O(1).

`nii_dim(h, i)`
: `i` in `0..7`; `dim[0]` is the declared dimension count and is returned
  as stored (no clamping). `Err("nii: dim index out of range")` otherwise.

`nii_datatype_bitpix` / `nii_datatype_name` / `nii_datatype_known`
: Pure lookup helpers over the documented table; no error channel.

Text accessors
: Return the bytes from the field start up to the first NUL (or the whole
  field when no NUL is present), as a byte string; an all-zero field yields
  `""`. The slice handed to `sb_to_str` is NUL-free by construction.

`nii_float_raw` / `nii_float_hex` / `nii_pixdim_*` / `nii_srow_*`
: Raw tokens are fresh 4-byte copies; hex tokens are lowercase. Bounds:
  singleton ids 0..15, pixdim 0..7, srow row 0..2 / col 0..3.

`nii_builder_new()`
: Emits a canonical single-file header: `sizeof_hdr` 348, `dim`
  `[3,1,1,1,1,1,1,1]`, `datatype` `NIFTI_TYPE_UINT8` with `bitpix` 8,
  `pixdim[0..7]` = 1.0f (raw `0000803f`), `vox_offset` = 352.0f (raw
  `0000b043`), every other byte zero, magic `n+1\0`.

`nii_builder_set_*`
: Validate first, write only after every check passes, so a failed setter
  leaves the builder byte-for-byte unchanged. `set_datatype` writes both
  `datatype` and the table `bitpix`; `set_magic` rewrites the 4-byte magic.

`nii_builder_finish(b)`
: Re-runs the same validation as `nii_parse` and returns the canonical 348
  little-endian bytes; Err with the same messages. Because setters can
  write arbitrary raw float tokens, the only reachable finish-time errors
  are `nii: negative vox_offset` (and `nii: invalid magic` / datatype /
  dims if a future edit bypassed the setters).

## Validation order (parse and finish)

1. `sizeof_hdr` decode is 348 (parse detects the endianness here).
2. All eight `dim[]` values are >= 0.
3. `datatype` is in the documented table.
4. `bitpix` equals `nii_datatype_bitpix(datatype)`.
5. Magic is `n+1\0` or `ni1\0` (both `\0`-terminated).
6. `vox_offset` is non-negative: the IEEE-754 sign bit (bit 7 of byte 3) is
   clear, which also rejects negative zero.

## Error string catalog

Parse (`nii_parse`) and builder finish share the validation messages:

| Condition | Message |
|---|---|
| `buffer.len() < 348` | `nii: buffer too small for header` |
| neither LE nor BE `sizeof_hdr` is 348 | `nii: unsupported sizeof_hdr <n>` (LE decode) |
| any `dim[i] < 0` | `nii: negative dimension` |
| `datatype` not in the table | `nii: unknown datatype <code>` |
| `bitpix != nii_datatype_bitpix(datatype)` | `nii: bitpix does not match datatype` |
| magic is not `n+1\0` / `ni1\0` | `nii: invalid magic` |
| `vox_offset` sign bit set | `nii: negative vox_offset` |

Accessors:

| Condition | Message |
|---|---|
| `i` outside 0..7 (`nii_dim`) | `nii: dim index out of range` |
| singleton float id outside 0..15 | `nii: float field out of range` |
| pixdim index outside 0..7 | `nii: pixdim index out of range` |
| srow row outside 0..2 or col outside 0..3 | `nii: srow index out of range` |

Builder setters:

| Condition | Message |
|---|---|
| `dim` index outside 0..7 | `nii: dim index out of range` |
| `v < 0` (`set_dim`) | `nii: negative dimension` |
| `v > 32767` (`set_dim`) | `nii: dimension out of range` |
| datatype not in the table | `nii: unknown datatype <code>` |
| float token length != 4 | `nii: float token must be 4 bytes` |
| qform/sform code outside 0..32767 | `nii: form code out of range` |
| intent code outside 0..32767 | `nii: intent code out of range` |
| slice start/end outside -32768..32767 | `nii: slice index out of range` |
| slice code outside 0..255 | `nii: slice code out of range` |
| xyzt_units outside 0..255 | `nii: units out of range` |
| magic kind not 0/1 | `nii: invalid magic kind` |
| text longer than 80/24/16 bytes | `nii: text too long` |

## Complexity

| Operation | Complexity |
|---|---|
| `nii_parse` | O(header) = O(348) |
| `nii_to_bytes` | O(348) |
| scalar/datatype accessors | O(1) |
| `nii_float_raw` / `_pixdim_raw` / `_srow_raw` | O(1) |
| `nii_builder_*` setters | O(1) (`_set_text_field` O(field size)) |
| `nii_builder_finish` | O(348) |

## Test matrix

`tests/test_conformance.xi` (`module nii_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. default builder: 348 bytes, `dim` count/extents, uint8/8, magic `n+1`,
   float defaults, `nii_to_bytes` round-trip;
2. canonical bytes: pinned offsets (`sizeof_hdr`, dim, datatype/bitpix,
   pixdim, vox_offset, magic) and zeroed regions;
3. datatype table: `UINT8..FLOAT64` bitpix and names, unknown codes (`0`,
   `1`, `128`, `256`, `2048`, `-5`) rejected;
4. dims: extents, out-of-range indices, setter errors (index/negative/
   overflow);
5. singleton float ids 0..15: distinct raw/hex tokens for every id,
   `nii_raw_hex`, out-of-range ids, 3-byte token rejection;
6. pixdim and srow: raw/hex tokens at pinned indices and index errors;
7. magic: `n+1`/`ni1` builder kinds, byte-exact magic field, invalid magic
   bytes and invalid builder kind;
8. endianness: byte-swapped fixture is detected, accessors match the LE
   fixture and both normalize to the same canonical bytes;
9. `sizeof_hdr`: short buffers and non-348 sizes (`0`, `347`, `540`) with
   the decoded value in the message;
10. dims validation: negative values in `dim[0]`, `dim[1]`, `dim[7]`;
11. datatype validation: unknown codes, bitpix mismatch, float64 round-trip
    and setter rejection;
12. vox_offset: `-0.0` and `-1.0` rejected by finish and parse, `1.0`
    accepted, negative `scl_slope` allowed;
13. scalar accessors: intent/qform/sform/slice/units values, signed slice
    bounds, range errors;
14. text fields: value round-trip, NUL trimming with trailing garbage, full
    80-byte descrip, 81/25/17-byte rejection;
15. extension flag: unknown below 352 bytes, `0`/`1`/`7` reported for
    longer buffers, flag bytes beyond the header ignored by `to_bytes`;
16. builder errors: every documented setter failure leaves the canonical
    header unchanged;
17. `ni1` header pair: magic kind 1, int16/16 datatype and dims round-trip;
18. full field matrix: builder -> parse -> canonical bytes with a padded
    (352-byte) variant.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.nii
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Validation is structural only (see the order above): form/intent/slice
  codes and `vox_offset` vs data-start relationships are not range-checked
  beyond what is listed.
- The extension flag is reported but not validated (`1` is not enforced for
  "extensions present"), and extension bytes are never parsed.
- The builder emits exactly 348 bytes; it does not write the extension flag
  byte at offset 348.
- Big-endian support normalizes on read; the builder always writes
  little-endian.
- Raw float tokens are opaque 4-byte values; no float formatting or
  endian-float decoding is provided.
- `NiftiHeader.raw`/`NiftiBuilder.raw` are implementation details; no
  arbitrary byte mutation API is exposed.
- No voxel payload, no compression, no NIfTI-2, no Analyze 7.5.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers at the top of
  the module, one helper pair per payload type (`NiftiHeader`, `Int`, `Str`,
  `Vec[UInt8]`, `Unit`).
- Every `UInt8` read is widened with `(b as Int) & 0xFF` before entering Int
  arithmetic or comparisons; `sizeof_hdr` is compared as an Int constant.
- Endianness handling is arithmetic only (byte reads plus reversed
  multiplication), avoiding bit tricks on sign-extended values.
- Builder setters write through the `&mut NiftiBuilder` with the private
  `_store_u16_le` / `_store_u8` / `_store_raw4` helpers so no `Vec` borrow
  survives a field read (no `&struct.field` passed to a `&Vec` parameter and
  no copy-out/copy-back pattern; the compiler emits advisory E001 on the
  latter).
- No `Vec[Float64]`, no `Vec[StructType]`, no self methods, no indexed
  `Vec[fn]` dispatch; the tests call each `tN()` directly.
- Tests compare `Str` values through `xiom.string.compare.str_compare`
  (BUG 17) and bind every `Vec` element read to a typed local.
- The library imports only `xiom.std` modules and declares no FFI.
