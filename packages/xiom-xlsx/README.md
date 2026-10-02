# xiom.xlsx

> **Status:** `incubating` -- conformance-tested (28/28); published at `v0.1.0` on the XIOM registry.
> **Scope:** pure-XIOM Excel OpenXML (`.xlsx`) spreadsheet reader/writer:
> a minimal ZIP container plus a minimal SpreadsheetML subset (workbook,
> sheets, shared strings, styles). No FFI.
> **Deps:** `xiom.std` only. The library uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare`, `xiom.convert`,
> `xiom.compress.deflate` (real RFC 1951 fixed-Huffman producer and capped
> inflater) and `xiom.hash.hash` (CRC32-IEEE); the tests add `xiom.test`
> and `xiom.io`.

## What it is

`.xlsx` is a ZIP archive of XML parts. `xiom.xlsx` implements both halves:

- a **ZIP container** built by hand: local file headers, central
  directory and EOCD; STORED and DEFLATE entries written with the stdlib
  deflate stack; CRC-32 verified on read; ZIP64 rejected;
- a **SpreadsheetML subset**: `[Content_Types].xml`, `_rels/.rels`,
  `xl/workbook.xml` (+rels), `xl/worksheets/sheetN.xml`,
  `xl/styles.xml`, `xl/sharedStrings.xml`;
- a **sparse cell model** (`XlsxWorkbook`) of parallel vectors --
  sheet/row/col/kind/value tuples with string interning and workbook
  styles -- that serializes deterministically and reads back.

Numeric cells are fixed-point micro-units (`3.14` is `3140000`): XIOM
v0.62.x bans `Vec[Float64]`. Parsing accepts decimals and `e` exponents,
rounds half away from zero on the sixth fractional digit, and errors on
overflow (see SPEC.md section 5).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `xlsx-read` | ZIP scan (`xlsx_zip_scan`, `xlsx_zip_data`, `xlsx_zip_find`, `xlsx_zip_name`, `xlsx_zip_entry_method/size/crc`) and workbook reader (`xlsx_read`) producing a sparse `XlsxWorkbook`; number parsing (`xlsx_number_parse`). |
| `xlsx-write` | ZIP writer (`xlsx_zip_write`) and deterministic workbook writer (`xlsx_write(wb, level)`; level 0 = STORED, 1..9 = fixed-Huffman DEFLATE); number formatting (`xlsx_number_to_str`); XML escaping (`xlsx_xml_escape`/`xlsx_xml_unescape`). |
| `xlsx-style` | Workbook style records (`xlsx_add_style`, `xlsx_style_bold/italic/size/color/numfmt`, `xlsx_style_count`), per-cell style references (`xlsx_set_style`, `xlsx_cell_style`) and `xl/styles.xml` read/write (fonts dedup, builtin/custom number formats). |

## API sketch

Build a workbook, set sparse cells, serialize, read it back:

```xi
use xiom.xlsx;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  var wb = xlsx_workbook_new();
  let s = xlsx_add_sheet(&mut wb, "Report");
  // 3.14 with two decimal places, styled bold
  let st = xlsx_add_style(&mut wb, true, false, 12, 0xFF0000, "0.00");
  xlsx_set_number(&mut wb, 0, 0, 0, 3140000);
  xlsx_set_style(&mut wb, 0, 0, 0, st);
  xlsx_set_string(&mut wb, 0, 1, 0, "total");
  xlsx_set_bool(&mut wb, 0, 2, 0, true);

  let bytes = xlsx_write(&wb, 6);     // 0 = stored, 1..9 = deflate
  if !bytes.is_ok { io.println(bytes.error); return 1; }

  let back = xlsx_read(&bytes.value);
  if !back.is_ok { io.println(back.error); return 1; }
  let v = xlsx_cell_number_scaled(&back.value, 0, 0, 0);
  io.println(xlsx_number_to_str(v.value));   // "3.14"
  return 0;
}
```

All index-taking accessors return `Result` with the deterministic
`xlsx: ...` error strings catalogued in SPEC.md section 6; all mutators
range-check their arguments.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom-xlsx
```

Expected: the namespace check passes, 28 `[PASS]` lines, and a final
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`.

The suite is fully self-contained: ZIP archives and workbook parts are
built in-memory (including malformed ones crafted by patching bytes), so
no external fixtures are needed.

## Limitations

**Dynamic-Huffman DEFLATE cannot be read.** The stdlib inflater supports
STORED and FIXED Huffman blocks; dynamic blocks (what Excel/zlib normally
emit) fail with `xlsx: entry inflate failed: ...`. Archives written by
`xlsx_write` are always readable. ZIP64, encryption, formulas, dates,
merged cells and multi-code number formats are out of scope; the full
list, error catalog, wire formats and data model are in **SPEC.md**.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
