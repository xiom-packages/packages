<!-- XIOM -- xiom.xlsx specification -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.xlsx -- specification

This document describes exactly what `src/xlsx.xi` implements: a minimal
ZIP container and a minimal SpreadsheetML subset for reading and writing
Excel OpenXML (`.xlsx`) workbooks, in pure XIOM on top of `xiom.std` (the
real `xiom.compress.deflate` stack and `xiom.hash.hash.crc32_ieee`).

## 1. Scope

Implemented:

* a deterministic **ZIP writer**: local file headers (`PK\x03\x04`),
  central directory (`PK\x01\x02`) and EOCD (`PK\x05\x06`), STORED and
  DEFLATE entries, CRC-32/ISO-HDLC, no data descriptors;
* a **ZIP reader**: backwards EOCD scan, central-directory walk, eager
  extraction, CRC verification, STORED + DEFLATE inflate through
  `deflate_decompress_capped`, ZIP64 rejection;
* a **SpreadsheetML subset**: `[Content_Types].xml`, `_rels/.rels`,
  `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/worksheets/sheetN.xml`,
  `xl/styles.xml`, `xl/sharedStrings.xml`;
* a **sparse workbook model** (parallel vectors, no `Vec[StructType]`) with
  last-write-wins cell lookups, string interning and workbook styles;
* **cell types** on read: number (`t` absent or `t="n"`), shared string
  (`t="s"`), inline string (`t="inlineStr"`), formula string (`t="str"`,
  also `t="e"` error cells read as strings), bool (`t="b"`);
* **cell types** on write: number, shared string, bool; styles per cell.

Non-goals (documented, not implemented):

* **No dynamic-Huffman DEFLATE read.** The stdlib inflater rejects
  dynamic blocks (and repeat codes); see section 7. This is the single
  most important limitation: most files produced by Excel/zlib use
  dynamic Huffman and will fail with a deterministic error.
* No ZIP64, encryption, data-descriptor *writing*, multi-disk archives,
  comments or extra fields (extra fields are tolerated on read).
* No formula evaluation, no `calcChain`, no pivot tables, no charts, no
  drawings, no defined names, no conditional formatting, no merged cells,
  no column/row dimensions, no hyperlinks, no number-format *rendering*.
* No float/date semantics: numbers are raw fixed-point scaled `Int`s
  (section 5). Dates are serial numbers and stay numbers.
* No namespace-prefixed SpreadsheetML tags (elements are matched by their
  literal name; default-namespace documents only), no CDATA, no DTD, no
  `xml:space` semantics beyond capturing the text verbatim.

## 2. ZIP container

### 2.1 Writer (`xlsx_zip_write`)

Entry `i` has a name, a method (0 STORED, 8 DEFLATE) and a byte range of
the caller's payload pool. DEFLATE entries are compressed with
`deflate_compress_level(data, 6)` (fixed-Huffman producer); STORED entries
are copied verbatim.

Local file header (30 bytes + name):

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 4 | signature | `50 4B 03 04` |
| 4 | 2 | version needed | 20 |
| 6 | 2 | flags | 0 |
| 8 | 2 | method | 0 or 8 |
| 10 | 2 | mod time | 0 |
| 12 | 2 | mod date | 0x21 (1980-01-01) |
| 14 | 4 | CRC-32 | of the uncompressed payload |
| 18 | 4 | compressed size | |
| 22 | 4 | uncompressed size | |
| 26 | 2 | name length | |
| 28 | 2 | extra length | 0 |
| 30 | n | name | UTF-8 bytes |

Central directory record (46 bytes + name) adds version-made-by 20,
comment length 0, disk 0, internal/external attributes 0 and the local
header offset at +42. The EOCD is 22 bytes with both entry counts equal.
Output is byte-for-byte deterministic. Limits: at most 4096 entries, name
lengths must fit u16, CRC and sizes must fit u32; payload > 4 GiB is not
representable (writer truncates fields, reader rejects via ZIP64).

### 2.2 Reader (`xlsx_zip_scan`)

1. Scan backwards from `len-22` down to `len-22-65535` (floor 0) for the
   EOCD signature. `len < 22` is `xlsx: zip too small`.
2. Read entry count / CD size / CD offset. `0xFFFF` entries or
   `0xFFFFFFFF` CD offset is `xlsx: zip64 not supported`.
3. Walk `count` central-directory records from the CD offset: validate
   each signature, bounds, and the entry name (NUL-free).
4. Extract each entry: locate its local header (validated signature),
   compute the data offset from the local name/extra lengths, then use
   the **central directory's** sizes (so streamed entries with flag bit 3
   and a data descriptor are readable):
   * method 0: copy `usize` bytes (requires `usize <= csize`);
   * method 8: `deflate_decompress_capped(comp, usize)`; the result must
     be exactly `usize` bytes;
   * other methods: `xlsx: unsupported zip compression method`.
5. Verify CRC-32 of every extracted payload.

All payloads are concatenated into one pool in the archive struct
(`pool` + `poff` + `usize`), so the archive never keeps pointers into the
input buffer. Limits: 4096 entries, 64 MiB per entry.

## 3. SpreadsheetML parts

### 3.1 Written parts

| Part | Content |
|---|---|
| `[Content_Types].xml` | default rels/xml types + overrides for workbook, every sheet, styles, sharedStrings |
| `_rels/.rels` | rId1 officeDocument -> `xl/workbook.xml` |
| `xl/workbook.xml` | one `<sheet name sheetId r:id>` per sheet |
| `xl/_rels/workbook.xml.rels` | sheet rIds first, then styles, then sharedStrings |
| `xl/worksheets/sheetN.xml` | `<sheetData>` with ascending `<row r>` and `<c r>` |
| `xl/styles.xml` | see 3.3 |
| `xl/sharedStrings.xml` | `<si><t xml:space="preserve">` per interned string |

A sheet part is:

```xml
<worksheet xmlns="...spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1"><v>3.14</v></c><c r="B1" t="s"><v>0</v></c></row>
</sheetData></worksheet>
```

Cells are sorted by (row, col) at write time regardless of insertion
order. Style references are written as `s="style_index + 1"` because
`cellXfs` entry 0 is the default style.

### 3.2 Reader tolerance

The reader walks tags with a quote-aware scanner (comments and processing
instructions are skipped, `>` inside attribute values does not terminate a
tag). It matches elements by literal name and ignores unknown elements and
attributes. Attribute values have the predefined entities and numeric
character references decoded. A missing `r:id` falls back to
`xl/worksheets/sheetN.xml` by sheet position; relationship targets may be
absolute (`/xl/...`) or relative to `xl/`; targets containing `..` are
rejected. `r:id` ordering must match sheet order.

Cell parsing:

* `r` is required on every `<c>` (`xlsx: cell missing r attribute`);
  `A1`-style references with optional `$` markers, up to 3 letters and
  7 digits; cells with no `<v>`/`<t>` content (blank/self-closing cells)
  are skipped;
* `t="s"` reads an integer shared-string index into the pool; out of
  range is an error;
* `t="inlineStr"` collects the text of every `<t>` inside `<is>` (rich
  runs are concatenated); `t="str"` and `t="e"` take the raw `<v>` text
  as the string value;
* numbers parse the `<v>` text per section 5; bools parse `0`/`1`;
* `t="d"` (ISO dates) and unknown `t` values are
  `xlsx: unsupported cell type` (strict, so silent type confusion cannot
  happen);
* `s="0"` means no style; `s="k"` (k>0) maps to workbook style k-1.

Shared strings support plain `<si><t>text</t></si>`, empty/self-closing
`<si/>`, and rich text (concatenation of all `<t>` runs).

### 3.3 Styles

The writer emits one deduplicated `<font>` per unique
(bold, italic, size, color) combination (font 0 is the 11 pt black
default), two fills (`none`, `gray125`), one border, one `cellStyleXfs`
and one `cellStyles` entry. Number formats recognized as builtins are
written by id, any other non-empty code becomes a custom `<numFmt>` with
id `164 + n`; duplicates of a custom code share one id.

Builtin map: `0.00`=2, `#,##0`=3, `#,##0.00`=4, `0%`=9, `0.00%`=10,
`mm-dd-yy`=14, `@`=49. All other ids read back as `""` (General), since
the full builtin table is not reproduced.

The reader parses `<numFmts>`, `<fonts>` (detects `<b/>`, `<i/>`,
`<sz val>`, `<color rgb>`) and `<cellXfs>` in order; every `xf` after the
default becomes a workbook style. Font ids out of range fall back to the
default font.

## 4. Data model

`XlsxWorkbook` is a flat struct of parallel vectors (never
`Vec[StructType]`):

| Field | Meaning |
|---|---|
| `sheet_names` | sheet names, in workbook order |
| `cell_sheet/cell_row/cell_col` | zero-based cell coordinates |
| `cell_kind` | 0 number, 1 string, 2 bool |
| `cell_num` | fixed-point micro-units (section 5) |
| `cell_bool` | 0/1 |
| `cell_str` | index into `str_pool` (-1 otherwise) |
| `cell_style` | style index (-1 = none) |
| `str_pool` | deduplicated string values |
| `sty_bold/sty_italic/sty_size/sty_color/sty_fmt` | style records |

Every mutation appends one entry to each parallel vector in lockstep;
`_wb_push_cell` is the only writer of cell state. A coordinate lookup
returns the **last** matching cell, so setting the same coordinate twice
overrides the first (the earlier row remains in the flat arrays but is
never read or written). Model caps: 1024 sheets, 1,000,000 cells,
1,000,000 strings, 100,000 styles.

`XlsxZip` is likewise flat: `names/methods/crcs/csize/usize/poff` plus
the shared `pool`; accessors verify the lengths before slicing.

## 5. Numbers (fixed point, scale 1_000_000)

XIOM v0.62.x bans `Vec[Float64]`, so all numeric cells are signed Ints in
micro-units: `3140000` is `3.14`. Functions: `xlsx_number_parse`,
`xlsx_number_to_str`, `xlsx_scale` (= 1_000_000).

Parsing accepts an optional sign, digits, an optional fraction and an
optional decimal exponent (`1.5e3`). Semantics:

* up to 18 significant digits are kept; more are truncated (documented);
* if the value has more than 6 fractional digits, it is rounded half
  away from zero on the 6th digit (`0.0000005` -> 1, `-0.0000005` -> -1);
* exponents beyond ±320 or magnitudes that would overflow `Int` are
  errors (`xlsx: exponent out of range`,
  `xlsx: numeric literal out of range`);
* whitespace around the literal is tolerated; empty, `1.2.3`, `1,000`
  and similar are `xlsx: invalid numeric literal`.

Formatting emits the shortest plain decimal with trailing fractional
zeros trimmed (`3`, `3.14`, `-2.25`, `0.000001`); it never emits
exponents.

## 6. Error catalog

Zip container (`xlsx: ` prefix, deterministic):

| Message |
|---|
| `xlsx: zip too small` |
| `xlsx: end of central directory not found` |
| `xlsx: zip64 not supported` |
| `xlsx: truncated zip structure` |
| `xlsx: truncated central directory` |
| `xlsx: truncated central directory entry` |
| `xlsx: bad central directory signature` |
| `xlsx: bad local file header` |
| `xlsx: truncated zip entry header` |
| `xlsx: truncated zip entry data` |
| `xlsx: stored entry size mismatch` |
| `xlsx: entry inflate failed: <deflate error>` |
| `xlsx: entry inflate size mismatch` |
| `xlsx: unsupported zip compression method` |
| `xlsx: zip entry too large` (per-entry cap 64 MiB) |
| `xlsx: too many zip entries` (cap 4096) |
| `xlsx: crc mismatch for zip entry '<name>'` |
| `xlsx: zip entry name contains nul` |
| `xlsx: zip input arrays differ in length` |
| `xlsx: zip input range out of bounds` |
| `xlsx: zip entry index out of range` |
| `xlsx: zip archive state corrupted` |

Workbook / XML:

| Message |
|---|
| `xlsx: missing xl/workbook.xml` |
| `xlsx: missing worksheet part` |
| `xlsx: relationship not found` |
| `xlsx: relationship missing target` |
| `xlsx: unsupported relationship target` |
| `xlsx: sheet missing name attribute` |
| `xlsx: sheet limit exceeded` |
| `xlsx: invalid sheet name` / `xlsx: duplicate sheet name` |
| `xlsx: cell missing r attribute` |
| `xlsx: invalid cell reference` |
| `xlsx: unsupported cell type` |
| `xlsx: shared string index out of range` |
| `xlsx: string pool limit exceeded` |
| `xlsx: cell limit exceeded` |
| `xlsx: cell coordinate out of range` |
| `xlsx: style index out of range` |
| `xlsx: style limit exceeded` |
| `xlsx: cell not found` |
| `xlsx: cell is not a number|string|boolean` |
| `xlsx: string index out of range` |
| `xlsx: sheet index out of range` |
| `xlsx: xml unterminated tag` / `xlsx: unclosed cell element` / `xlsx: unclosed si element` |
| `xlsx: xml unterminated entity` / `xlsx: unknown xml entity` |
| `xlsx: invalid xml character reference` / `xlsx: xml character reference out of range` / `xlsx: xml character reference to nul` |
| `xlsx: xml raw nul byte` / `xlsx: xml raw control byte` |
| `xlsx: invalid numeric literal` / `xlsx: invalid integer literal` |
| `xlsx: numeric literal out of range` / `xlsx: integer literal out of range` / `xlsx: exponent out of range` |
| `xlsx: byte range out of bounds` / `xlsx: byte range contains nul` |
| `xlsx: unsupported compression level` (not 0..9) |

## 7. Documented limitations

1. **Dynamic-Huffman DEFLATE cannot be read.** The stdlib inflater
   supports STORED and FIXED Huffman blocks and rejects dynamic headers,
   repeat codes, and dynamic blocks generally. Archives written by this
   module are always readable (STORED or fixed-Huffman). Most real-world
   `.xlsx` files (Excel, LibreOffice, zlib) use dynamic Huffman and fail
   with `xlsx: entry inflate failed: deflate: dynamic ...`. The payload
   layout is fully modeled; only the inflater is the boundary. The
   stdlib source documents the same boundary.
2. **ZIP64 unsupported** (entry counts/offsets/sizes above 32-bit).
3. **Encrypted / Agile-encrypted packages** are not detected specially:
   the OLE container is not a ZIP and fails with an EOCD error.
4. **Reader strictness.** Cells need `r=`; `t="d"` and unknown `t` values
   error; prefixed/namespaced elements are not matched; CDATA is not
   handled; `<!-- -->` comments are skipped properly but a comment may
   not contain `-->`.
5. **Writer scope.** No formulas, no inline strings, no dates, no number
   formats beyond one code string per style, no widths/merges/filters.
   Sheets are always written in position order; workbook styles are
   written exactly as registered.
6. **Text handling.** XML text is materialized with `sb_to_str`, which
   aborts on NUL, so any part containing a raw 0x00 byte is rejected
   (`xlsx: byte range contains nul`). The writer escapes control
   characters as `&#xNN;`; the reader decodes any numeric reference
   except NUL and rejects raw control bytes. UTF-8 bytes pass through
   untouched (no re-validation is performed beyond NUL).
7. **String pool semantics.** Strings are shared per workbook on write
   (dedup by byte comparison) and read back through one shared pool;
   `xlsx_string_count` therefore counts unique values, not cell count.
8. **Fixed-point numbers only** (section 5); very large/small magnitudes
   beyond the documented bounds are rejected rather than approximated.

## 8. Public API (module `xiom.xlsx`)

Number helpers: `xlsx_number_parse`, `xlsx_number_to_str`, `xlsx_scale`.

XML helpers: `xlsx_xml_escape`, `xlsx_xml_unescape`.

ZIP: `xlsx_zip_write`, `xlsx_zip_scan`, `xlsx_zip_count`,
`xlsx_zip_name`, `xlsx_zip_entry_method`, `xlsx_zip_entry_size`,
`xlsx_zip_entry_crc`, `xlsx_zip_find`, `xlsx_zip_data`.

Model: `xlsx_workbook_new`, `xlsx_add_sheet`, `xlsx_sheet_name_valid`,
`xlsx_sheet_count`, `xlsx_sheet_name`, `xlsx_sheet_cell_count`,
`xlsx_cell_count`, `xlsx_set_number`, `xlsx_set_string`, `xlsx_set_bool`,
`xlsx_set_style`, `xlsx_cell_kind`, `xlsx_cell_number_scaled`,
`xlsx_cell_string`, `xlsx_cell_bool`, `xlsx_cell_style`,
`xlsx_string_count`, `xlsx_string`, `xlsx_string_find`.

Styles: `xlsx_add_style`, `xlsx_style_count`, `xlsx_style_bold`,
`xlsx_style_italic`, `xlsx_style_size`, `xlsx_style_color`,
`xlsx_style_numfmt`.

Workbook I/O: `xlsx_write(wb, level)`, `xlsx_read(buffer)`.

## 9. Round-trip guarantee

For any workbook built through the model API, `xlsx_read(xlsx_write(wb,
level))` returns a model with the same sheet names/order, the same set of
cells (kind and value), the same style records and per-cell style
references; string values compare byte-for-byte. This is exercised by
`tests/test_conformance.xi` for both STORED (level 0) and fixed-Huffman
DEFLATE (level 6) archives.
