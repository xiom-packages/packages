# xiom.ktx

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (19/19); NOT published yet.
> **Scope:** KTX 1 texture-container structural codec: 12-byte identifier, 64-byte little/big-endian header, key/value metadata with flat spans, and mipmap-level record spans for non-array, non-cubemap textures. No pixel is decoded, no compression metadata is interpreted, and KTX 2 is rejected.
> **Deps:** `xiom.std` only (the library module imports nothing outside it). No FFI in v0.1.

## What it is

`xiom.ktx` reads and writes the structural parts of Khronos KTX 1 ("KTX 11")
texture containers: the exact identifier, the 64-byte header (with both
endianness forms), the key/value metadata region, and the mipmap-level
records of flat (non-array, non-cubemap) textures. It is a pure-XIOM byte
codec -- image payloads are located and copied, never decoded, and
`glInternalFormat` is carried through as an opaque integer. That makes it the
right front end for validators, asset pipelines, loaders and inspection
tools.

The supported subset is intentionally narrow:

| Area | Supported |
|---|---|
| Identifier | exact KTX 1 bytes; KTX 2 detected and rejected |
| Header | little-endian and big-endian; all 13 u32 fields |
| Header validation | identifier, endianness marker, `glTypeSize` 1..8, faces 1/6, `pixelWidth >= 1` |
| Key/value pairs | u32 size + printable-ASCII NUL-terminated key + opaque value, 4-byte aligned, flat spans |
| Levels | non-array, non-cubemap textures; u32 `imageSize` + data, 4-byte aligned between levels |
| Cubemap/array | header and key/value region parse; whole-buffer level spans out of scope |
| Builder | canonical 64-byte little-endian header, zero key/value bytes |

Endianness: the marker at offset 12 is read little-endian, so `0x04030201`
means the file is little-endian (bytes `01 02 03 04`) and `0x01020304` means
it is big-endian (bytes `04 03 02 01`); every other field then uses that
endianness.

## API

| Function | Returns | Description |
|---|---|---|
| `ktx_is_ktx(data)` | `Bool` | True when the buffer starts with the 12-byte KTX 1 identifier. |
| `ktx_parse_header(data)` | `Result[KtxHeader, Str]` | Validate the 64-byte header and decode every field. |
| `ktx_build_header(h)` | `Result[Vec[UInt8], Str]` | Emit the canonical 64-byte little-endian header, `bytesOfKeyValueData` pinned to 0. |
| `ktx_parse_key_values(data)` | `Result[KtxKeyValues, Str]` | Parse the header and index the full key/value region. |
| `ktx_parse(data)` | `Result[KtxInfo, Str]` | Full flat-texture parse: header, key/value region, level spans. |
| `ktx_level_count(h)` | `Int` | Effective level count (`numberOfMipmapLevels == 0` reads as 1). |
| `ktx_is_compressed(h)` | `Bool` | `glType == 0`. |
| `ktx_is_cubemap(h)` | `Bool` | `numberOfFaces == 6`. |
| `ktx_is_array(h)` | `Bool` | `numberOfArrayElements != 0`. |
| `ktx_data_offset(h)` | `Int` | `64 + bytesOfKeyValueData`. |
| `ktx_width(h)` / `ktx_height(h)` / `ktx_depth(h)` | `Int` | Level-0 dimensions (height/depth may be 0). |
| `ktx_gl_type(h)` / `ktx_gl_format(h)` | `Int` | GL type/format fields, carried through. |
| `ktx_gl_internal_format(h)` / `ktx_gl_base_internal_format(h)` | `Int` | Internal/base format fields (opaque). |
| `ktx_kv_count(kv)` | `Int` | Number of key/value pairs. |
| `ktx_kv_key(kv, i)` | `Str` | Key of pair `i`; "" out of range. |
| `ktx_kv_value_offset(kv, i)` / `ktx_kv_value_bytes(kv, i)` | `Int` | Value span of pair `i`; -1 out of range. |
| `ktx_kv_value(data, kv, i)` | `Result[Vec[UInt8], Str]` | Copy pair `i`'s opaque value bytes. |
| `ktx_level_offset(info, i)` / `ktx_level_size(info, i)` | `Int` | Offset of level `i`'s `imageSize` / its value; -1 out of range. |
| `ktx_payload_offset(info, i)` | `Int` | Offset of level `i`'s first image byte. |
| `ktx_level_data(data, info, i)` | `Result[Vec[UInt8], Str]` | Copy level `i`'s image bytes (padding excluded). |

## Install / use

```
xiom pkg install xiom.ktx@0.1.0     # consumer
```

Then import the module from any XIOM source file with `use xiom.ktx;`. The
library pulls in nothing but `xiom.std` as a platform dependency.

## Quick start

```xiom
use xiom.ktx;

// Read a whole KTX 1 file (bytes from disk, network, ...).
let parsed = ktx_parse(bytes);
match parsed {
  Ok(info) => {
    // info.header.pixel_width, info.header.gl_internal_format, ...
    // info.data_offset is the first level record; levels follow at
    // info.size_offsets[i] (u32 imageSize) with payloads at
    // ktx_payload_offset(info, i).
    let level0 = ktx_level_data(bytes, info, 0);  // opaque image bytes
    let key0 = ktx_kv_key(info.kv, 0);            // printable key
    let val0 = ktx_kv_value(bytes, info.kv, 0);   // opaque value bytes
  },
  Err(e) => { /* e is a ktx:-prefixed message, see SPEC.md */ },
}

// Build a canonical header and append one level by hand.
let h = KtxHeader{
  endianness: 0x04030201; big_endian: false; gl_type: 5121;
  gl_type_size: 1; gl_format: 6408; gl_internal_format: 32856;
  gl_base_internal_format: 6408; pixel_width: 4; pixel_height: 4;
  pixel_depth: 0; array_elements: 0; faces: 1; mipmap_levels: 1;
  kv_bytes: 0;
};
let header = ktx_build_header(h);   // 64 bytes, little-endian
```

## Error model

Every fallible function returns `Result[..., Str]` with deterministic
messages prefixed `ktx: `. Truncation, a bad identifier (with a dedicated
KTX 2 message), a bad endianness marker, an out-of-range `glTypeSize`, a bad
face count, a zero width, malformed key/value pairs, out-of-scope level
layouts and truncated level records each have their own message; header
errors are forwarded unchanged by `ktx_parse`, `ktx_parse_key_values` and
`ktx_build_header`. Accessor index errors and short caller buffers are
reported separately (`ktx: key/value index out of range`,
`ktx: level index out of range`, `ktx: truncated key/value data`,
`ktx: truncated level data`). The full catalog is in SPEC.md.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.ktx
```

19 conformance checks cover hand-built little- and big-endian header decode,
every accessor, exact identifier rejection (including KTX 2), endianness
markers, type size, face count and width validation, the specification
key/value example, multi-pair flat indexing with mixed padding and empty
values, the printable-key rule with opaque values, key/value bounds and
alignment errors, level span computation with 4-byte alignment, the
`numberOfMipmapLevels == 0` rule, level truncation limits, cubemap/array
header handling, canonical builder bytes and builder range errors, full
LE/BE file round-trips with key/value data and levels, and accessor range
behavior.

## Limitations

- No pixel decoding of any kind; image data is an opaque byte span.
- KTX 2 ("KTX 20") files are rejected, not converted.
- Array and cubemap files expose their header and key/value region only;
  `ktx_parse` rejects them with `ktx: unsupported level layout`.
- `glInternalFormat` and compression schemes carry no semantics here.
- The 1D/2D shape rules (height/depth zero) are not enforced, and
  `imageSize` is not cross-checked against the dimensions.
- Keys must be printable ASCII; values are unrestricted and may contain NUL
  and any other bytes.
- Duplicate keys and reserved `KTX`/`ktx` prefixes are not policed.
- Bytes after the final level are ignored; there is no trailing-data
  validation.
- The whole file is held in memory; there is no streaming API.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
