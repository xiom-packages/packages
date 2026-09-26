# xiom.pcf

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM X11 PCF bitmap-font codec subset: file header and
> table directory, metrics, bitmaps, encodings, and raw-span preservation of
> the remaining documented tables.
> **Deps:** `xiom.std` only. The library module is dependency-free; the tests
> use `xiom.test`, `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`
> from it. No FFI, no compression, no rendering.

## What it is

`xiom.pcf` reads the compiled bitmap-font format used by the X11 font
system. A PCF buffer starts with the magic bytes `0x01 'f' 'c' 'p'`, a
little-endian u32 table count, then 16-byte table entries (type, format,
size, offset). `pcf_parse` validates the directory and indexes the font into
a flat `PcfFont` value: the directory as parallel vectors, the per-glyph
metrics, the per-glyph bitmap offsets/spans, and the per-glyph encoding
runs. `metrics` and `bitmaps` are required; `encodings` is parsed
structurally when present; every other documented table (properties, ink
metrics, swidths, glyph names, BDF encodings, accelerators) is preserved as
a raw span and copied out byte-for-byte on demand.

Metrics tables are supported in the three documented word orders: 0
(big-endian), 1 (little-endian) and 2 (byte-mixed: little-endian count,
big-endian metric words). The compressed-metrics markers `0x00010000` and
`0x00000100` are recognized and rejected with their own message. Glyph
bitmap rows are documented to be padded to 4 bytes; the stored padded size
is authoritative and only span-checked against the bitmaps table.

## API

| Function | Returns | Description |
|---|---|---|
| `pcf_parse(data)` | `Result[PcfFont, Str]` | Validate and index a whole PCF buffer. |
| `pcf_table_count(p)` | `Int` | Number of table directory entries. |
| `pcf_table_type/format/offset/size(p, i)` | `Int` | Directory fields of entry `i`; `-1` out of range. |
| `pcf_table_find(p, ttype)` | `Int` | First entry index of type `ttype`; `-1` when absent. |
| `pcf_has_table(p, ttype)` | `Bool` | Whether any entry has type `ttype`. |
| `pcf_table_raw(data, p, ttype)` | `Result[Vec[UInt8], Str]` | Copy the first table of `ttype` verbatim. |
| `pcf_glyph_count(p)` | `Int` | Glyph count (metrics/bitmaps count). |
| `pcf_metrics_format(p)` | `Int` | `0` big-endian, `1` little-endian, `2` byte-mixed. |
| `pcf_metric_lsb/rsb/advance/ascent/descent(p, g)` | `Int` | Signed i16 metric fields; `0` out of range. |
| `pcf_metric_attributes(p, g)` | `Int` | Unsigned u16 attributes; `0` out of range. |
| `pcf_metrics_at(p, g)` | `Result[Vec[Int], Str]` | All six fields as `[lsb, rsb, advance, ascent, descent, attributes]`. |
| `pcf_bitmap_span(p, g)` | `Int` | Padded bitmap size in bytes; `-1` out of range. |
| `pcf_bitmap_raw_offset(p, g)` | `Int` | Bitmaps-table-relative bitmap offset; `-1` out of range. |
| `pcf_glyph_metrics_offset(p, g)` | `Int` | Metrics-table-relative record offset (`4 + 12*g`); `-1` out of range. |
| `pcf_bitmap_size(p)` | `Int` | Total bitmap data bytes in the bitmaps table. |
| `pcf_bitmap_bytes(data, p, g)` | `Result[Vec[UInt8], Str]` | Copy glyph `g`'s padded bitmap bytes. |
| `pcf_has_encodings(p)` | `Bool` | Whether an encodings table was parsed. |
| `pcf_encoding_min/max(p)` | `Int` | Documented encoding range; `-1` when absent. |
| `pcf_encoding_count(p, g)` | `Int` | Mappings of glyph `g`; `0` absent, `-1` out of range. |
| `pcf_encoding_at(p, g, i)` | `Int` | `i`-th mapping of glyph `g`; `-1` when unavailable. |
| `pcf_encodings_at(p, g)` | `Result[Vec[Int], Str]` | All mappings of glyph `g`, in pool order. |
| `pcf_glyph_for_encoding(p, cp)` | `Int` | First glyph mapped to `cp` (glyph order, then pool order); `-1` when none. |

Table type constants: `PCF_TABLE_PROPERTIES` (1), `PCF_TABLE_METRICS` (2),
`PCF_TABLE_BITMAPS` (4), `PCF_TABLE_INK_METRICS` (8), `PCF_TABLE_ENCODINGS`
(16), `PCF_TABLE_SWIDTHS` (256), `PCF_TABLE_GLYPH_NAMES` (512),
`PCF_TABLE_BDF_ENCODINGS` (1024), `PCF_TABLE_ACCELERATORS` (2048).

Errors: `pcf: truncated header`, `pcf: bad magic`,
`pcf: truncated table directory`, `pcf: table out of bounds`,
`pcf: missing metrics table`, `pcf: missing bitmaps table`,
`pcf: compressed metrics unsupported`, `pcf: unsupported metrics format`,
`pcf: bad metrics table size`, `pcf: glyph count mismatch`,
`pcf: bad bitmaps table size`, `pcf: bad metrics offset`,
`pcf: bitmap out of bounds`, `pcf: bad encodings table size`,
`pcf: encodings pool too large`, `pcf: bad encoding range`,
`pcf: bad encoding run`, `pcf: encoding out of range`,
`pcf: no such table`, `pcf: index out of range`,
`pcf: bitmap bytes out of bounds`, `pcf: no encodings table`
(see SPEC.md for the exact conditions and the validation order).

## Usage

```xi
use xiom.pcf;
use xiom.io;

let parsed = pcf_parse(&data);
match parsed {
  Ok(f) => {
    io.println("glyphs: " + xiom.convert.int_to_string(pcf_glyph_count(&f)));
    io.println("advance of glyph 0: "
      + xiom.convert.int_to_string(pcf_metric_advance(&f, 0)));
    let raw = pcf_table_raw(&data, &f, PCF_TABLE_PROPERTIES);
    if raw.is_ok {
      io.println("properties bytes: " + xiom.convert.int_to_string(raw.value.len()));
    }
    let cp = pcf_glyph_for_encoding(&f, 65);   // 'A', first match
    io.println("glyph for 65: " + xiom.convert.int_to_string(cp));
  },
  Err(e) => { io.println("pcf error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.pcf
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Documented subset only.** Only the header/directory, metrics, bitmaps
  and encodings are modeled structurally; properties, ink metrics, swidths,
  glyph names, BDF encodings and accelerators are raw spans with no
  semantic decoding, and unknown table types are preserved the same way.
- **No compression.** The compressed-metrics markers `0x00010000` and
  `0x00000100` are recognized and rejected; compressed metrics bodies are
  never decoded.
- **No rendering.** Bitmap bytes are copied verbatim; glyph width/height,
  scan order, bit order and padding are not interpreted. The stored padded
  size is authoritative and only checked against the bitmaps table.
- **Per-glyph offsets are table-relative and canonical for metrics.**
  `metrics_offset[g]` must be the canonical `4 + 12*g`; `bitmap_offset[g]`
  only has to lie inside the bitmaps table's data area.
- **Encodings layout is this codec's documented simplification**: a u16
  range, two per-glyph u16 arrays and one flat u16 pool, with every pooled
  value inside `[minimum, maximum]` and pool indexes bounded (pool at most
  65536 values).
- Not thread-safe; `PcfFont` is a plain value type holding copies of the
  parsed scalars plus offsets into the original buffer for byte copies.
- The table directory is validated for bounds only; overlapping or aliased
  table spans are preserved as-is.
- When a documented type appears more than once, the first occurrence is
  the one indexed for structured parsing and for `pcf_table_raw`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
