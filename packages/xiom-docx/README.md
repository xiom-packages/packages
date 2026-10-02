# xiom.docx

> **Status:** `incubating` -- conformance-tested (27/27, pure XIOM, no FFI).
> **Scope:** minimal Word OpenXML (.docx) reader/writer: a self-contained
> ZIP container (local headers + central directory + EOCD) plus a
> WordprocessingML subset -- paragraphs, runs, text and the style
> properties bold / italic / half-point size.
> **Deps:** `xiom.std` only. The library module uses
> `xiom.string`, `xiom.string.builder`, `xiom.convert`,
> `xiom.compress.deflate` and `xiom.compress.gzip`; the tests add
> `xiom.io`, `xiom.string.compare` and `xiom.compress.deflate`.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `docx-read` | Document/paragraph/run reader: `docx_from_bytes`, paragraph and run accessors, ZIP entry accessors (`docx_zip_open` and friends). |
| `docx-write` | Document builder (`docx_new`, `docx_add_paragraph`, `docx_add_run`) and serializer (`docx_to_bytes`, `docx_to_bytes_level`); also the standalone ZIP writer (`docx_zip_writer_*`). |
| `docx-style` | Style model: bold/italic flags, half-point sizes with `docx_points_to_half` / `docx_half_to_points` and `docx_run_size`. |

## What it is

A .docx file is a ZIP container of XML parts. This package builds and
parses that container itself -- the stdlib `xiom.compress.deflate` stack
provides the DEFLATE payload codec, while the ZIP framing (signatures,
little-endian fields, offsets, CRC-32) is implemented here. The output is
byte-deterministic: fixed DOS timestamp (1980-01-01) and a fixed part
order.

The package always writes this minimal part set:

```
[Content_Types].xml   stored (ZIP method 0)
_rels/.rels           stored (ZIP method 0)
word/document.xml     stored (level 0) or fixed-Huffman deflate (level 1..9)
```

`word/document.xml` carries one `<w:body>` with `<w:p>` paragraphs and
`<w:r>` / `<w:rPr>` / `<w:b>` / `<w:i>` / `<w:sz w:val="N"/>` /
`<w:t xml:space="preserve">` runs. Text is XML-escaped on write and
entity-decoded (named and numeric) on read; multi-byte UTF-8 passes
through unchanged.

## API

| Function | Returns | Description |
|---|---|---|
| `docx_version()` | `Str` | Package version. |
| `docx_new()` | `DocxDoc` | New empty document. |
| `docx_add_paragraph(doc)` | `Unit` | Append an empty paragraph. |
| `docx_add_run(doc, text, bold, italic, size)` | `Unit` | Append a run (size in half-points; `<= 0` = unspecified). |
| `docx_add_paragraph` / `docx_add_run` | | Build model (docx-write). |
| `docx_to_bytes(doc)` | `Result[Vec[UInt8], Str]` | Serialize (document part at DEFLATE level 6). |
| `docx_to_bytes_level(doc, level)` | `Result[Vec[UInt8], Str]` | Serialize; `level <= 0` stores, `1..9` deflates. |
| `docx_from_bytes(buffer)` | `Result[DocxDoc, Str]` | Parse a .docx container. |
| `docx_paragraph_count(doc)` / `docx_run_count(doc)` | `Int` | Counts. |
| `docx_para_run_count(doc, p)` | `Result[Int, Str]` | Runs in paragraph `p`. |
| `docx_paragraph_text(doc, p)` | `Result[Str, Str]` | Paragraph text (runs concatenated). |
| `docx_run_text(doc, r)` | `Result[Str, Str]` | Run text. |
| `docx_run_bold(doc, r)` / `docx_run_italic(doc, r)` | `Result[Bool, Str]` | Style flags. |
| `docx_run_size(doc, r)` | `Result[Int, Str]` | Half-point size (0 = unspecified). |
| `docx_points_to_half(points)` / `docx_half_to_points(half)` | `Int` | Style unit conversion. |
| `docx_zip_open(buffer)` | `Result[DocxZip, Str]` | Parse a ZIP archive (stored + deflate, CRC-checked). |
| `docx_zip_count(z)` / `docx_zip_find(z, name)` | `Int` | Entry count / index (`-1` when absent). |
| `docx_zip_entry_name/data/method/size/crc(z, i)` | `Result` | Entry accessors (index-checked). |
| `docx_zip_writer_new()` | `DocxZipWriter` | New archive builder. |
| `docx_zip_writer_add(w, name, data, level)` | `Unit` | Add an entry (level 0 stored, 1..9 deflate). |
| `docx_zip_writer_finish(w)` / `docx_zip_writer_count(w)` | `Vec[UInt8]` / `Int` | Materialize / count. |
| `docx_inflate_raw(data, max_out)` | `Result[Vec[UInt8], Str]` | Inflate: stdlib first, then the built-in stored + fixed decoder. |
| `docx_inflate_fixed(data, max_out)` | `Result[Vec[UInt8], Str]` | Built-in stored + fixed-Huffman decoder only. |

Errors are deterministic `docx: ...` strings; the full catalog is in
SPEC.md.

## Usage

```xi
use xiom.docx;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  var d = docx_new();
  docx_add_paragraph(&mut d);
  docx_add_run(&mut d, "Hello ", false, false, 0);
  docx_add_run(&mut d, "world", true, false, docx_points_to_half(12));

  let br = docx_to_bytes(&d);
  if !br.is_ok { io.println(br.error); return 1; }
  let buf: Vec[UInt8] = br.value;

  let dr = docx_from_bytes(&buf);
  if !dr.is_ok { io.println(dr.error); return 1; }
  let doc: DocxDoc = dr.value;
  let p = docx_paragraph_text(&doc, 0);
  if p.is_ok { io.println(p.value); }   // "Hello world"
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom-docx
```

Expected: 27 `[PASS]` lines and
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Minimal WordprocessingML.** One document part; paragraphs, runs and
  text plus bold/italic/half-point size. Paragraph properties, tables,
  images, numbering, headers/footers, `styles.xml`, comments and fields
  are not modelled (unknown elements are skipped on read, never written).
- **Presence-only style flags.** `<w:b w:val="0"/>` is treated as bold;
  run style inheritance from `styles.xml` is not implemented.
- **DEFLATE read.** Stored and fixed-Huffman blocks always read; the
  stdlib `deflate_decompress_capped` is tried first (it also handles
  dynamic blocks without the 16/17/18 repeat codes). Dynamic-Huffman
  streams that use repeat codes fail with
  `docx: deflate dynamic huffman unsupported` (SPEC.md documents the
  boundary).
- **DEFLATE write** emits stored (level 0) or fixed-Huffman (level 1..9)
  blocks only; that is what the stdlib encoder produces.
- **No ZIP64, no encryption, no multi-disk, no data descriptors**;
  entry names must be printable ASCII (the UTF-8 name flag is not set);
  extra fields and comments are skipped/not written.
- **Not thread-safe**, no file I/O (byte buffers only), no streaming.
- The document model is a flat set of parallel vectors plus one
  concatenated text buffer; sizes are integer half-points because
  v0.62.2 has no `Vec[Float64]`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
