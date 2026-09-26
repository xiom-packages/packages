# xiom.pcf -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.pcf`, version `0.1.0`).
Module: `src/pcf.xi` (`module xiom.pcf`).
Depends on `xiom.std`; the library module imports nothing from it (tests add
`xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) codec for a documented subset of the X11 PCF compiled
bitmap-font format:

- `pcf_parse` validates a whole buffer and returns a flat `PcfFont` index;
- the table directory is kept as parallel vectors and readable through
  `pcf_table_count` / `pcf_table_type` / `pcf_table_format` /
  `pcf_table_offset` / `pcf_table_size` / `pcf_table_find` /
  `pcf_has_table`;
- any table is copyable verbatim with `pcf_table_raw`, so the optional
  tables (properties, ink metrics, swidths, glyph names, BDF encodings,
  accelerators) and unknown table types are preserved as raw spans;
- metrics are parsed in the three documented word orders and readable
  field-by-field (`pcf_metric_*`, `pcf_metrics_at`);
- bitmap offsets/spans and padded bitmap bytes are readable
  (`pcf_bitmap_span`, `pcf_bitmap_raw_offset`, `pcf_glyph_metrics_offset`,
  `pcf_bitmap_size`, `pcf_bitmap_bytes`);
- encodings are parsed structurally and readable per glyph and by codepoint
  first match (`pcf_encoding_min/max`, `pcf_encoding_count`,
  `pcf_encoding_at`, `pcf_encodings_at`, `pcf_glyph_for_encoding`);
- deterministic `Err(Str)` messages for malformed input.

## Non-goals

- **No compression.** The compressed-metrics markers `0x00010000` (the
  task-documented marker) and `0x00000100` (the historical PCF marker) are
  recognized and rejected; compressed metric bodies are never decoded.
- **No semantics for properties / ink metrics / swidths / glyph names /
  BDF encodings / accelerators.** They are raw spans: offset/size in the
  directory, bytes available through `pcf_table_raw`. No property parsing,
  no glyph-name tables, no accelerator metrics.
- **No rendering.** Glyph width/height, scan order, bit order and row
  padding are not interpreted; the stored padded size is authoritative and
  is only checked to fit the bitmaps table.
- **No building / emitting.** This codec parses and copies; it does not
  serialize a `PcfFont` back to PCF bytes.
- **No streaming.** The whole font is an in-memory `Vec[UInt8]`.
- **No overlap/aliasing checks.** The directory entries are bounds-checked
  against the buffer; overlapping table spans are preserved as-is.

## Byte-level layout

### File header and table directory

| Field | Width | Encoding |
|---|---|---|
| magic | 4 bytes | `0x01` `'f'` (0x66) `'c'` (0x63) `'p'` (0x70) |
| table count | u32 | little-endian |
| table entries | 16 bytes each | see below |

Each directory entry:

| Field | Width | Encoding |
|---|---|---|
| type | u32 | little-endian |
| format | u32 | little-endian (table-specific; see metrics) |
| size | u32 | little-endian, bytes |
| offset | u32 | little-endian, absolute from the file start |

Documented table types:

| Constant | Value | Handling |
|---|---|---|
| `PCF_TABLE_PROPERTIES` | 1 | optional, raw span |
| `PCF_TABLE_METRICS` | 2 | **required**, parsed |
| `PCF_TABLE_BITMAPS` | 4 | **required**, parsed |
| `PCF_TABLE_INK_METRICS` | 8 | optional, raw span |
| `PCF_TABLE_ENCODINGS` | 16 | optional, parsed |
| `PCF_TABLE_SWIDTHS` | 256 | optional, raw span |
| `PCF_TABLE_GLYPH_NAMES` | 512 | optional, raw span |
| `PCF_TABLE_BDF_ENCODINGS` | 1024 | optional, raw span |
| `PCF_TABLE_ACCELERATORS` | 2048 | optional, raw span |

Duplicate types are tolerated: the first occurrence is indexed for
structured parsing and returned by `pcf_table_find` / `pcf_table_raw`.
Unknown types are accepted and preserved as raw spans. Directory order is
free.

### Metrics table

Layout: a u32 glyph count, then `count` 12-byte records.

The count word order and the record word order are selected by the table's
format field:

| Format | Name | Glyph count | Record words |
|---|---|---|---|
| 0 | big-endian | big-endian | big-endian |
| 1 | little-endian | little-endian | little-endian |
| 2 | byte-mixed | little-endian | big-endian |

Any other format is rejected; in particular `0x00010000` and `0x00000100`
are the documented compressed-metrics markers and get their own message.

A record is six 16-bit fields, in this order:

| Field | Type |
|---|---|
| left side bearing | i16 |
| right side bearing | i16 |
| character width / advance | i16 |
| ascent | i16 |
| descent | i16 |
| attributes | u16 |

The five signed fields are sign-extended to `Int`; attributes stay unsigned
(0..65535). The table size must be exactly `4 + 12*count`.

### Bitmaps table

Layout:

| Field | Width | Notes |
|---|---|---|
| glyph count | u32 LE | must equal the metrics count |
| metrics offset | u32 LE per glyph | metrics-table-relative; must equal `4 + 12*g` |
| bitmap offset | u32 LE per glyph | bitmaps-table-relative; inside the data area |
| padded size | u32 LE per glyph | bitmap byte span; inside the data area |
| bitmap bytes | rest of the table | concatenated glyph bitmaps |

The offset pairs come first (one 8-byte pair per glyph, in glyph order),
then the padded sizes (4 bytes per glyph), then the bitmap bytes. The data
area therefore starts at `4 + 8*count + 4*count = 4 + 12*count`.

Glyph rows are documented to be padded to 4 bytes
(`PCF_ROW_PADDING`), but the codec does not re-derive the padded size from
row geometry (glyph dimensions are out of scope): the stored size is
authoritative. Validation requires `bitmap_offset >= data_start` and
`bitmap_offset + padded_size <= table size`.

### Encodings table

Layout (all fields u16 little-endian):

| Field | Width | Notes |
|---|---|---|
| minimum encoding | u16 | must be `<= maximum` |
| maximum encoding | u16 | |
| first pool index | u16 per glyph | `0` when the glyph has no mappings |
| mapping count | u16 per glyph | |
| value pool | u16 per value | every value in `[minimum, maximum]` |

The size must satisfy `size = 4 + 4*glyph_count + 2*pool_len` with an even
remainder, so the pool consumes every byte after the two per-glyph arrays.
A glyph's mappings are
`pool[first .. first + count)`; runs must fit the pool
(`first + count <= pool_len`), a zero count requires `first == 0`, and the
pool may hold at most 65536 values (u16 indexes).

## API signatures

All functions are free functions in module `xiom.pcf` (no self methods):

```xi
pub const PCF_TABLE_PROPERTIES: Int = 1;
pub const PCF_TABLE_METRICS: Int = 2;
pub const PCF_TABLE_BITMAPS: Int = 4;
pub const PCF_TABLE_INK_METRICS: Int = 8;
pub const PCF_TABLE_ENCODINGS: Int = 16;
pub const PCF_TABLE_SWIDTHS: Int = 256;
pub const PCF_TABLE_GLYPH_NAMES: Int = 512;
pub const PCF_TABLE_BDF_ENCODINGS: Int = 1024;
pub const PCF_TABLE_ACCELERATORS: Int = 2048;
pub const PCF_METRICS_FORMAT_BE: Int = 0;
pub const PCF_METRICS_FORMAT_LE: Int = 1;
pub const PCF_METRICS_FORMAT_MIXED: Int = 2;
pub const PCF_COMPRESSED_METRICS_FORMAT: Int = 65536;
pub const PCF_LEGACY_COMPRESSED_FORMAT: Int = 256;

pub fn pcf_parse(data: &Vec[UInt8]) -> Result[PcfFont, Str]
pub fn pcf_table_count(p: &PcfFont) -> Int
pub fn pcf_table_type(p: &PcfFont, i: Int) -> Int
pub fn pcf_table_format(p: &PcfFont, i: Int) -> Int
pub fn pcf_table_offset(p: &PcfFont, i: Int) -> Int
pub fn pcf_table_size(p: &PcfFont, i: Int) -> Int
pub fn pcf_table_find(p: &PcfFont, ttype: Int) -> Int
pub fn pcf_has_table(p: &PcfFont, ttype: Int) -> Bool
pub fn pcf_table_raw(data: &Vec[UInt8], p: &PcfFont, ttype: Int) -> Result[Vec[UInt8], Str]
pub fn pcf_glyph_count(p: &PcfFont) -> Int
pub fn pcf_metrics_format(p: &PcfFont) -> Int
pub fn pcf_metric_lsb(p: &PcfFont, g: Int) -> Int
pub fn pcf_metric_rsb(p: &PcfFont, g: Int) -> Int
pub fn pcf_metric_advance(p: &PcfFont, g: Int) -> Int
pub fn pcf_metric_ascent(p: &PcfFont, g: Int) -> Int
pub fn pcf_metric_descent(p: &PcfFont, g: Int) -> Int
pub fn pcf_metric_attributes(p: &PcfFont, g: Int) -> Int
pub fn pcf_metrics_at(p: &PcfFont, g: Int) -> Result[Vec[Int], Str]
pub fn pcf_bitmap_span(p: &PcfFont, g: Int) -> Int
pub fn pcf_bitmap_raw_offset(p: &PcfFont, g: Int) -> Int
pub fn pcf_glyph_metrics_offset(p: &PcfFont, g: Int) -> Int
pub fn pcf_bitmap_size(p: &PcfFont) -> Int
pub fn pcf_bitmap_bytes(data: &Vec[UInt8], p: &PcfFont, g: Int) -> Result[Vec[UInt8], Str]
pub fn pcf_has_encodings(p: &PcfFont) -> Bool
pub fn pcf_encoding_min(p: &PcfFont) -> Int
pub fn pcf_encoding_max(p: &PcfFont) -> Int
pub fn pcf_encoding_count(p: &PcfFont, g: Int) -> Int
pub fn pcf_encoding_at(p: &PcfFont, g: Int, i: Int) -> Int
pub fn pcf_encodings_at(p: &PcfFont, g: Int) -> Result[Vec[Int], Str]
pub fn pcf_glyph_for_encoding(p: &PcfFont, cp: Int) -> Int
```

`PcfFont` fields are implementation details (flat parallel vectors, no
`Vec` of structs); callers go through the functions above.

## Semantics

`pcf_parse(data)`
: Validates the header, directory, required tables and optional encodings
  (order below) and returns a `PcfFont`; on `Err` no partial index is
  returned.

`pcf_table_count` / `pcf_table_type` / `pcf_table_format` /
`pcf_table_offset` / `pcf_table_size`
: Directory reads; the scalar accessors return `-1` for `i` outside
  `0..pcf_table_count(p)-1` (no error channel). Offsets are absolute file
  offsets; sizes are byte counts.

`pcf_table_find(p, ttype)`
: First directory index whose type equals `ttype`, in directory order;
  `-1` when absent (including an empty directory).

`pcf_has_table(p, ttype)`
: `pcf_table_find(p, ttype) >= 0`.

`pcf_table_raw(data, p, ttype)`
: `Err("pcf: no such table")` when no entry has that type; otherwise the
  recorded span is re-checked against `data` and copied into a fresh
  vector, so a stale index or a shorter buffer is
  `Err("pcf: table out of bounds")`.

`pcf_glyph_count` / `pcf_metrics_format`
: The glyph count and the metrics format actually parsed (0, 1 or 2).

`pcf_metric_lsb` / `pcf_metric_rsb` / `pcf_metric_advance` /
`pcf_metric_ascent` / `pcf_metric_descent` / `pcf_metric_attributes`
: The named field of glyph `g`; the first five are signed i16 values,
  attributes is unsigned u16. `0` for `g` outside
  `0..pcf_glyph_count(p)-1`; use `pcf_metrics_at` for an error channel.

`pcf_metrics_at(p, g)`
: `Err("pcf: index out of range")` for a bad `g`; otherwise
  `[lsb, rsb, advance, ascent, descent, attributes]` in a fresh vector.

`pcf_bitmap_span(p, g)`
: Padded bitmap byte size of glyph `g`, `-1` out of range.

`pcf_bitmap_raw_offset(p, g)`
: Bitmaps-table-relative byte offset of glyph `g`'s bitmap bytes, `-1` out
  of range.

`pcf_glyph_metrics_offset(p, g)`
: Metrics-table-relative offset of glyph `g`'s 12-byte record; parse time
  guarantees this is the canonical `4 + 12*g`. `-1` out of range.

`pcf_bitmap_size(p)`
: Total bytes of the bitmaps table's data area
  (`table size - (4 + 12*glyph_count)`), including row padding.

`pcf_bitmap_bytes(data, p, g)`
: `Err("pcf: index out of range")` for a bad `g`; otherwise the padded
  bytes are copied verbatim from the absolute position
  `bitmaps_table_offset + pcf_bitmap_raw_offset(p, g)`.
  `Err("pcf: bitmap bytes out of bounds")` when the span does not fit
  `data`.

`pcf_has_encodings`
: True when an encodings table was parsed.

`pcf_encoding_min` / `pcf_encoding_max`
: The documented `[minimum, maximum]` range, or `-1` when no encodings
  table is present (encodings are unsigned, so `-1` is unambiguous).

`pcf_encoding_count(p, g)`
: Mapping count of glyph `g`; `0` when no encodings table is present, `-1`
  when `g` is out of range.

`pcf_encoding_at(p, g, i)`
: The `i`-th mapping of glyph `g` in pool order, or `-1` when no encodings
  table is present or `g`/`i` is out of range. Mappings are unsigned, so
  `-1` is unambiguous.

`pcf_encodings_at(p, g)`
: `Err("pcf: no encodings table")` when absent;
  `Err("pcf: index out of range")` for a bad `g`; otherwise all mappings of
  glyph `g` in pool order in a fresh vector.

`pcf_glyph_for_encoding(p, cp)`
: The documented first-match rule: glyphs are scanned in glyph-index order
  and each glyph's mappings in pool order; the first glyph containing `cp`
  wins, so duplicates are tolerated. Returns `-1` when no glyph maps `cp`,
  when `cp` lies outside `[minimum, maximum]`, or when no encodings table
  is present.

## Validation order

`pcf_parse` checks, in this order:

1. `data.len() >= 8`, then the four magic bytes (`pcf: truncated header`,
   `pcf: bad magic`);
2. table count fits the remaining bytes: `count <= (len - 8) / 16`
   (`pcf: truncated table directory`);
3. every directory entry: `offset <= len` and `size <= len - offset`
   (`pcf: table out of bounds`);
4. a metrics table exists (`pcf: missing metrics table`); its format is
   not compressed (`pcf: compressed metrics unsupported`), is 0/1/2
   (`pcf: unsupported metrics format`), and its size is exactly
   `4 + 12*count` (`pcf: bad metrics table size`);
5. a bitmaps table exists (`pcf: missing bitmaps table`); its glyph count
   equals the metrics count (`pcf: glyph count mismatch`); its size holds
   the offset pairs and padded sizes (`pcf: bad bitmaps table size`); each
   `metrics_offset` is the canonical `4 + 12*g` (`pcf: bad metrics
   offset`); each `bitmap_offset`/`padded_size` fits the data area
   (`pcf: bitmap out of bounds`);
6. when an encodings table is present: size fits the layout without an odd
   pool remainder (`pcf: bad encodings table size`), the pool is at most
   65536 values (`pcf: encodings pool too large`), `minimum <= maximum`
   (`pcf: bad encoding range`), every run fits the pool and a zero count
   has `first == 0` (`pcf: bad encoding run`), and every pooled value lies
   inside the range (`pcf: encoding out of range`).

## Error string catalog

| Condition | Error text |
|---|---|
| `pcf_parse`: `data.len() < 8` | `pcf: truncated header` |
| `pcf_parse`: magic bytes wrong | `pcf: bad magic` |
| `pcf_parse`: table count exceeds the remaining bytes | `pcf: truncated table directory` |
| `pcf_parse`/`pcf_table_raw`: span beyond the buffer | `pcf: table out of bounds` |
| `pcf_parse`: no table of type 2 | `pcf: missing metrics table` |
| `pcf_parse`: no table of type 4 | `pcf: missing bitmaps table` |
| `pcf_parse`: metrics format `0x00010000` or `0x00000100` | `pcf: compressed metrics unsupported` |
| `pcf_parse`: metrics format not 0/1/2 | `pcf: unsupported metrics format` |
| `pcf_parse`: metrics size not `4 + 12*count` | `pcf: bad metrics table size` |
| `pcf_parse`: bitmaps count != metrics count | `pcf: glyph count mismatch` |
| `pcf_parse`: bitmaps size below `4 + 12*count` | `pcf: bad bitmaps table size` |
| `pcf_parse`: `metrics_offset != 4 + 12*g` | `pcf: bad metrics offset` |
| `pcf_parse`: bitmap offset/span outside the data area | `pcf: bitmap out of bounds` |
| `pcf_parse`: encodings size below the layout or odd pool remainder | `pcf: bad encodings table size` |
| `pcf_parse`: encodings pool longer than 65536 values | `pcf: encodings pool too large` |
| `pcf_parse`: `minimum > maximum` | `pcf: bad encoding range` |
| `pcf_parse`: run exceeds the pool, or `count == 0` with `first != 0` | `pcf: bad encoding run` |
| `pcf_parse`: pooled value outside `[minimum, maximum]` | `pcf: encoding out of range` |
| `pcf_table_raw`: no directory entry of that type | `pcf: no such table` |
| `pcf_metrics_at`/`pcf_bitmap_bytes`/`pcf_encodings_at`: bad glyph index | `pcf: index out of range` |
| `pcf_bitmap_bytes`: span does not fit the supplied buffer | `pcf: bitmap bytes out of bounds` |
| `pcf_encodings_at`: no encodings table | `pcf: no encodings table` |

The metrics accessors and the scalar encoding accessors report `-1`, and
the scalar metric accessors report `0`, instead of an error channel, for
out-of-range indexes (documented above).

## Complexity

| Operation | Complexity |
|---|---|
| `pcf_parse` | O(tables + glyphs + pooled encodings) |
| directory accessors / `pcf_has_table` | O(1) / O(tables) |
| `pcf_table_raw` | O(table size) |
| `pcf_metric_*`, `pcf_metrics_at`, `pcf_bitmap_span`, `pcf_bitmap_raw_offset`, `pcf_glyph_metrics_offset`, `pcf_bitmap_size`, encoding scalar accessors | O(1) |
| `pcf_bitmap_bytes` | O(bitmap span) |
| `pcf_encodings_at` | O(mappings) |
| `pcf_glyph_for_encoding` | O(total pooled encodings) |

## Test plan

`tests/test_conformance.xi` (`module pcf_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). The canonical fixture is a hand-built 268-byte,
nine-table PCF file (types 2, 4, 16, 1, 8, 256, 512, 1024, 2048; two
glyphs; metrics format 1; per-glyph bitmap spans 4 and 8; encodings 65..67)
with every table offset, size and payload pinned. Coverage:

1. canonical nine-table fixture: length 268, directory types/formats/
   offsets/sizes pinned, first-match `pcf_table_find`, `pcf_has_table`,
   out-of-range accessors report `-1`;
2. little-endian metrics: all six fields of both glyphs (`-1/2/5/8/-2/1`
   and `-3/6/7/9/-4/43981`), `pcf_metrics_at` order, out-of-range errors;
3. metrics format 0 (big-endian): values, raw table bytes pinned
   (`00000002 ffff 0002 ... abcd`) and direct big-endian reads;
4. metrics format 2 (byte-mixed): count little-endian, words big-endian,
   raw bytes pinned (`02000000 ffff ... abcd`);
5. bitmap spans (4/8), table-relative offsets (28/32), canonical metrics
   offsets (4/16), total bitmap size 12, exact padded bytes for both
   glyphs, out-of-range and short-buffer errors;
6. encodings: minimum 65, maximum 67, counts 2/1, values 65/66/67, copied
   runs, `pcf_glyph_for_encoding` first match (`65->0`, `66->0`, `67->1`)
   and `-1` for 64/68/65535/-1;
7. every optional table is preserved as an exact raw span (properties,
   ink metrics, swidths, glyph names, BDF encodings, accelerators, plus
   metrics/bitmaps/encodings), missing type and short-buffer errors;
8. parse -> raw spans -> reassemble is byte-exact (directory rebuilt and
   every span compared with its file slice), pinning the round trip;
9. header-only (count 0) and truncated-directory inputs are errors;
10. empty and shortened headers plus every wrong magic byte are errors;
11. metrics and bitmaps are required (all four missing-table shapes);
12. the compressed markers `0x00010000`/`0x00000100` and other formats are
    rejected with their documented messages;
13. metrics size must be exactly `4 + 12*count` (small, large, count 3,
    count 0);
14. bitmaps glyph count must equal the metrics count (3 and 1);
15. bitmap offset/span bounds, the canonical metrics offset rule, and the
    documented permissive authority of a non-multiple-of-4 stored span;
16. encodings size/range/pool/run validation (seven malformed variants);
17. directory table spans must lie inside the buffer (offset, size, last
    table, oversized count);
18. zero-glyph two-table font parses; absent encodings read as no
    mappings;
19. unknown table types are preserved (type `1<<20`, format 3, raw
    `deadbeef`); duplicate types keep the first occurrence; directory
    order is free (bitmaps before metrics);
20. all three metrics formats agree field-by-field and parsing is
    deterministic across repeated parses.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.pcf
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Documented subset only: no compression, no properties/glyph-name/
  accelerator semantics, no rendering, no building.
- The metrics `metrics_offset[g]` field must be the canonical
  `4 + 12*g`; the codec does not tolerate arbitrary in-table offsets.
- Bitmap offsets are bitmaps-table-relative and must lie in the data area;
  overlap between glyph bitmaps is not checked.
- The stored padded size is authoritative even when it is not a multiple of
  the documented 4-byte row padding (glyph geometry is out of scope).
- The encodings layout is this codec's documented simplification of a
  PCF-style mapping table; the pool is u16-indexed, so it cannot exceed
  65536 values.
- Unknown table types are preserved but never validated beyond bounds.
- The directory is bounds-checked only; overlapping spans and duplicate
  types are preserved (first occurrence wins for structured reads).
- `PcfFont` holds offsets into the original buffer for byte copies;
  `pcf_table_raw`/`pcf_bitmap_bytes` need a buffer holding those spans.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_font`/`_err_font`/`_ok_bytes`/`_err_bytes`/`_ok_ints`/`_err_ints`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- All byte extraction is arithmetic (`+`, `*`, `%`, `/`), with every byte
  widened through `(b as Int) & 0xFF`; no shifts and no bit tests are used
  anywhere, and the documented table-type constants are plain `Int`
  constants.
- Every `Vec` element read is bound to a typed local before use; no
  `Vec` of structs is used anywhere (flat parallel vectors only).
- The package declares no `extern "C"` blocks (no FFI) and no
  `Vec[Float64]`.
- Signature audit for the angle-bracket trap (`Vec<...`/`Result<...`) is
  clean in both `src/pcf.xi` and `tests/test_conformance.xi`.
- Str values in the tests are compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison).
