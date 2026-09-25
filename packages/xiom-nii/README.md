# xiom.nii

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM NIfTI-1 header codec: parse, validate and build the
> canonical 348-byte header, with little- and big-endian detection.
> **Deps:** `xiom.std` only. The library module imports
> `xiom.string`, `xiom.string.builder`, `xiom.convert` and
> `xiom.encoding.hex` from it; the tests add `xiom.io` and `xiom.test`.
> No FFI.

## What it is

NIfTI-1 stores imaging metadata in a fixed 348-byte header. The record is
little-endian on disk, but some writers emit the same record with every
multi-byte field byteswapped. `xiom.nii` reads both: `nii_parse` decodes
`sizeof_hdr` as little-endian first and, when that is not 348, as
big-endian, then normalizes the fields into the canonical little-endian
form. `nii_to_bytes` re-emits the canonical 348 bytes, so a big-endian file
parses to the same field values and re-serializes as little-endian.

The codec exposes scalar accessors (`dim[]`, `datatype`/`bitpix`,
`intent_code`, qform/sform codes, slice fields, `xyzt_units`, magic kind),
text fields (`descrip`, `aux_file`, `intent_name`, trimmed at the first
NUL), and every float32 field as a raw 4-byte little-endian token and as an
8-character lowercase hex string. No floating-point storage or arithmetic is
used anywhere.

## API

| Function | Returns | Description |
|---|---|---|
| `nii_parse(buffer)` | `Result[NiftiHeader, Str]` | Decode + validate a header buffer (>= 348 bytes). |
| `nii_to_bytes(h)` | `Vec[UInt8]` | Canonical little-endian 348 bytes. |
| `nii_swapped(h)` | `Bool` | True when the source buffer was big-endian. |
| `nii_ext_flag(h)` | `Int` | Extension-flag byte at offset 348, or `NII_EXT_UNKNOWN`. |
| `nii_sizeof_hdr(h)` | `Int` | sizeof_hdr (always 348 after parse). |
| `nii_dim_count(h)` | `Int` | dim[0], the declared dimension count. |
| `nii_dim(h, i)` | `Result[Int, Str]` | dim[i] for i in 0..7. |
| `nii_datatype(h)` | `Int` | Datatype code. |
| `nii_bitpix(h)` | `Int` | Bitpix field. |
| `nii_datatype_bitpix(dt)` | `Int` | Documented bitpix per datatype, -1 when unknown. |
| `nii_datatype_name(dt)` | `Str` | Documented name, "" when unknown. |
| `nii_datatype_known(dt)` | `Bool` | True for the documented table. |
| `nii_intent_code(h)` | `Int` | intent_code. |
| `nii_qform_code(h)` / `nii_sform_code(h)` | `Int` | Form codes (0 unknown .. 4 mni). |
| `nii_slice_start(h)` / `nii_slice_end(h)` | `Int` | Signed slice indices. |
| `nii_slice_code(h)` | `Int` | Slice order code 0..255. |
| `nii_xyzt_units(h)` | `Int` | Packed units byte. |
| `nii_magic_kind(h)` | `Int` | `NII_MAGIC_SINGLE` (`n+1\0`) or `NII_MAGIC_PAIR` (`ni1\0`). |
| `nii_descrip(h)` / `nii_aux_file(h)` / `nii_intent_name(h)` | `Str` | Text fields, NUL-trimmed. |
| `nii_float_raw(h, field)` | `Result[Vec[UInt8], Str]` | Raw 4-byte float32 token (field ids below). |
| `nii_float_hex(h, field)` | `Result[Str, Str]` | 8-char lowercase hex token. |
| `nii_pixdim_raw(h, i)` / `nii_pixdim_hex(h, i)` | `Result[.., Str]` | pixdim[i], i in 0..7. |
| `nii_srow_raw(h, row, col)` / `nii_srow_hex(h, row, col)` | `Result[.., Str]` | srow_{row}[col], row 0..2, col 0..3. |
| `nii_raw_hex(v)` | `Str` | Lowercase hex of any raw token. |
| `nii_builder_new()` | `NiftiBuilder` | Canonical single-file builder (see defaults below). |
| `nii_builder_finish(b)` | `Result[Vec[UInt8], Str]` | Re-validate and emit the canonical 348 bytes. |
| `nii_builder_set_dim(b, i, v)` | `Result[Unit, Str]` | dim[i]. |
| `nii_builder_set_datatype(b, dt)` | `Result[Unit, Str]` | Datatype and matching bitpix in one step. |
| `nii_builder_set_float(b, field, token)` | `Result[Unit, Str]` | Singleton float from a 4-byte token. |
| `nii_builder_set_pixdim(b, i, token)` | `Result[Unit, Str]` | pixdim[i] from a 4-byte token. |
| `nii_builder_set_srow(b, row, col, token)` | `Result[Unit, Str]` | srow_{row}[col] from a 4-byte token. |
| `nii_builder_set_qform_code(b, v)` / `nii_builder_set_sform_code(b, v)` | `Result[Unit, Str]` | Form codes 0..32767. |
| `nii_builder_set_intent_code(b, v)` | `Result[Unit, Str]` | intent_code 0..32767. |
| `nii_builder_set_slice_start(b, v)` / `nii_builder_set_slice_end(b, v)` | `Result[Unit, Str]` | Any signed 16-bit value. |
| `nii_builder_set_slice_code(b, v)` | `Result[Unit, Str]` | 0..255. |
| `nii_builder_set_xyzt_units(b, v)` | `Result[Unit, Str]` | 0..255. |
| `nii_builder_set_magic(b, kind)` | `Result[Unit, Str]` | `NII_MAGIC_SINGLE` or `NII_MAGIC_PAIR`. |
| `nii_builder_set_descrip(b, s)` / `_set_aux_file` / `_set_intent_name` | `Result[Unit, Str]` | Text fields, NUL-padded (80/24/16 bytes). |

Singleton float field ids (`NII_FLOAT_*` constants):

| id | Field | id | Field |
|---|---|---|---|
| 0 | `vox_offset` | 8 | `intent_p2` |
| 1 | `scl_slope` | 9 | `intent_p3` |
| 2 | `scl_inter` | 10 | `quatern_b` |
| 3 | `cal_max` | 11 | `quatern_c` |
| 4 | `cal_min` | 12 | `quatern_d` |
| 5 | `slice_duration` | 13 | `qoffset_x` |
| 6 | `toffset` | 14 | `qoffset_y` |
| 7 | `intent_p1` | 15 | `qoffset_z` |

Documented datatypes (the only codes accepted by validation and
`nii_builder_set_datatype`):

| Code | Name | bitpix |
|---|---|---|
| 2 | `NIFTI_TYPE_UINT8` | 8 |
| 4 | `NIFTI_TYPE_INT16` | 16 |
| 8 | `NIFTI_TYPE_INT32` | 32 |
| 16 | `NIFTI_TYPE_FLOAT32` | 32 |
| 32 | `NIFTI_TYPE_COMPLEX64` | 64 |
| 64 | `NIFTI_TYPE_FLOAT64` | 64 |

## Usage

```xi
use xiom.nii;
use xiom.nii.NII_FLOAT_SCL_SLOPE;
use xiom.io;
use xiom.convert;

// Build a single-file header: 256 x 256 float32 slices, 2.0x scaling.
var b = nii_builder_new();
nii_builder_set_dim(&mut b, 1, 256);
nii_builder_set_dim(&mut b, 2, 256);
nii_builder_set_datatype(&mut b, 16);        // NIFTI_TYPE_FLOAT32, bitpix 32

var slope = Vec[UInt8].new();                // raw float32 2.0f = 00 00 00 40
slope.push(0 as UInt8);
slope.push(0 as UInt8);
slope.push(0 as UInt8);
slope.push(64 as UInt8);
nii_builder_set_float(&mut b, NII_FLOAT_SCL_SLOPE, &slope);

let fin = nii_builder_finish(&b);
if fin.is_ok {
  let bytes: Vec[UInt8] = fin.value;         // canonical 348 bytes, LE magic n+1
  let parsed = nii_parse(&bytes);
  if parsed.is_ok {
    let h: NiftiHeader = parsed.value;
    io.println(nii_datatype_name(nii_datatype(&h)));        // NIFTI_TYPE_FLOAT32
    let d1 = nii_dim(&h, 1);
    if d1.is_ok {
      io.println("dim1: " + convert.int_to_string(d1.value));  // 256
    }
    let sh = nii_float_hex(&h, NII_FLOAT_SCL_SLOPE);
    if sh.is_ok {
      io.println(sh.value);                                   // 00000040
    }
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.nii
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Headers only.** No voxel data reading or writing, no extents/extension
  payload parsing, no gzip/zip-compressed variants, no NIfTI-2.
- **No matrix math.** The quaternion (`quatern_b/c/d`, `qoffset_x/y/z`) and
  `srow_x/y/z` fields are exposed as raw float32 tokens; composing or
  inverting the sform/qform matrices is out of scope.
- **No floating-point arithmetic.** All float32 fields are raw 4-byte
  tokens or hex strings. The only float semantics applied is the IEEE-754
  sign bit for the documented `vox_offset >= 0` rule.
- **Validation is structural.** `sizeof_hdr` must be 348, dims must be
  non-negative, the datatype must be in the table, `bitpix` must match it,
  the magic must be `n+1\0` or `ni1\0`, and `vox_offset` must be
  non-negative. `qform_code`/`sform_code`/`intent_code`/slice fields are not
  range-checked on parse, and `vox_offset` is not compared against the data
  start.
- **The extension flag is read, not interpreted.** When the buffer extends
  past byte 348 the flag byte is reported as-is (`0` = no extensions); its
  reserved bytes and any extension payloads are not parsed. The builder
  emits exactly 348 bytes and never writes an extension flag.
- **Text fields are byte strings.** NUL trimming only; no charset
  validation or escaping.
- `NiftiHeader` and `NiftiBuilder` hold a plain byte vector (no FFI, no
  mmap); `nii_parse` copies the header out of the caller's buffer.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
