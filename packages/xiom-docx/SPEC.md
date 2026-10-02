<!-- XIOM -- xiom.docx specification -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.docx -- specification

This document describes the byte-level and semantic behavior that
`src/docx.xi` actually implements: a minimal ZIP container writer/reader,
a DEFLATE read path (stdlib + built-in stored/fixed decoder), and a
round-trippable WordprocessingML paragraph/run/style subset. It is the
authoritative statement of what is supported and what is not.

## 1. Scope

Implemented:

* ZIP container: local file headers, central directory entries, EOCD;
  stored (method 0) and DEFLATE (method 8) entries; CRC-32 verification;
  EOCD scanning with a 64 KiB comment window; multi-disk rejection.
* DEFLATE read: stored and fixed-Huffman blocks always (built-in
  decoder); dynamic blocks via the stdlib `deflate_decompress_capped`
  when that succeeds.
* DEFLATE write: whatever the stdlib encoder emits for the requested
  level (stored for level 0, fixed-Huffman for levels 1..9).
* WordprocessingML: `[Content_Types].xml`, `_rels/.rels`,
  `word/document.xml`; paragraphs, runs, text, and the style properties
  bold (`w:b`), italic (`w:i`) and half-point size (`w:sz w:val`).
* XML text escaping/unescaping (named and numeric character references).
* A flat parallel-vector document model with index-checked accessors.
* Deterministic output (fixed DOS timestamp, fixed part order).

Non-goals (documented, not implemented):

* No ZIP64, encrypted entries, multi-disk archives, data descriptors,
  extra fields or archive comments (reader skips extras; writer emits
  none).
* No dynamic-Huffman *writer*; no DEFLATE compression-level tuning
  beyond the stdlib encoder's stored/fixed behavior.
* No dynamic-Huffman *reader* the stdlib cannot handle: streams using
  the 16/17/18 repeat codes are rejected
  (`docx: deflate dynamic huffman unsupported`).
* No WordprocessingML features beyond paragraphs/runs/text and the
  three style properties: no paragraph properties, tables, images,
  numbering, headers/footers, footnotes, comments, fields,
  `styles.xml`, content controls, or text-run constructs other than
  `w:t` (`w:tab`, `w:br`, `w:cr`, `w:drawing`, ... are skipped/ignored).
* No style inheritance, theme fonts, or paragraph/character style ids.
* No file I/O or streaming: buffers in, buffers out.

The module is a single file by design: v0.62.2 cannot reliably pass
package-defined structs across module boundaries (see the
`xiom.string.builder` design note), and the ZIP reader/writer state is
struct-shaped, so splitting would add a compiler hazard rather than
reduce one.

## 2. ZIP container

### 2.1 Write layout

Parts are added in this order (all offsets little-endian):

| Order | Name | Level |
|---|---|---|
| 1 | `[Content_Types].xml` | stored (method 0) |
| 2 | `_rels/.rels` | stored (method 0) |
| 3 | `word/document.xml` | `level <= 0`: stored; `level 1..9`: deflate |

Local file header (30 bytes + name):

| Offset | Size | Field | Written value |
|---|---|---|---|
| 0 | 4 | signature | `0x04034B50` |
| 4 | 2 | version needed | 20 |
| 6 | 2 | general purpose flags | 0 |
| 8 | 2 | compression method | 0 or 8 |
| 10 | 2 | last mod time | 0 (00:00:00) |
| 12 | 2 | last mod date | `0x0021` (1980-01-01) |
| 14 | 4 | CRC-32 | IEEE 802.3 of the uncompressed data |
| 18 | 4 | compressed size | payload bytes |
| 22 | 4 | uncompressed size | input bytes |
| 26 | 2 | name length | ASCII byte count |
| 28 | 2 | extra length | 0 |
| 30 | n | name | raw bytes |

Data follows immediately (no data descriptor). Central directory entry
(46 bytes + name):

| Offset | Size | Field | Written value |
|---|---|---|---|
| 0 | 4 | signature | `0x02014B50` |
| 4 | 2 | version made by | 20 |
| 6 | 2 | version needed | 20 |
| 8 | 2 | flags | 0 |
| 10 | 2 | method | as local |
| 12 | 2 | time | 0 |
| 14 | 2 | date | `0x0021` |
| 16 | 4 | CRC-32 | as local |
| 20 | 4 | compressed size | as local |
| 24 | 4 | uncompressed size | as local |
| 28 | 2 | name length | as local |
| 30 | 2 | extra length | 0 |
| 32 | 2 | comment length | 0 |
| 34 | 2 | disk number start | 0 |
| 36 | 2 | internal attributes | 0 |
| 38 | 4 | external attributes | 0 |
| 42 | 4 | local header offset | absolute |
| 46 | n | name | raw bytes |

End of central directory (22 bytes):

| Offset | Size | Field | Written value |
|---|---|---|---|
| 0 | 4 | signature | `0x06054B50` |
| 4 | 2 | disk number | 0 |
| 6 | 2 | central directory disk | 0 |
| 8 | 2 | entries on disk | count |
| 10 | 2 | total entries | count |
| 12 | 4 | central directory size | bytes |
| 16 | 4 | central directory offset | absolute |
| 20 | 2 | comment length | 0 |

The writer has no ZIP64 path: compressed and uncompressed sizes, offsets
and entry counts must stay within the 32-bit / 16-bit fields. Reader
entry-count and size caps (`_DOCX_MAX_ENTRY` = 64 MiB per entry) bound
decompression bombs.

### 2.2 Read layout and validation order

`docx_zip_open(buffer)` validates in this exact order:

1. `len >= 22`, else `docx: zip too small`.
2. Backward scan from `len - 22` down to `max(0, len - 22 - 65535)` for
   the EOCD signature; absent is
   `docx: end of central directory not found`.
3. Disk fields must all be 0 and `entries_disk == entries_total`, else
   `docx: multi-disk zip not supported`.
4. `cd_off + cd_size <= len`, else `docx: central directory out of bounds`.
5. For each of `entries_total` entries:
   * central header in bounds and signature `0x02014B50`, else
     `docx: truncated central directory` / `docx: bad central directory signature`;
   * name bytes must be in `[0x20, 0x7E]` (printable ASCII), no NUL:
     `docx: non-ascii entry name` / `docx: entry name contains nul`;
   * local header in bounds and signature `0x04034B50`, else
     `docx: local file header out of bounds` / `docx: bad local file header signature`;
   * payload range `[p_off, p_off + comp_size)` in bounds, else
     `docx: entry data out of bounds`.
6. Decompress:
   * method 0: raw copy (sizes must match: `docx: entry size mismatch`);
   * method 8: `usize <= 64 MiB`, inflate with cap `usize`, produced
     length must equal `usize` (`docx: entry size mismatch`);
   * anything else: `docx: unsupported compression method N`.
7. CRC-32 of the payload must equal the stored CRC, else
   `docx: crc mismatch`.
8. Entry metadata and payload are appended to the archive pools. The
   metadata vectors are pushed in lockstep with the payload; accessors
   guard pool spans (`docx: inconsistent zip model`).

Entry names are matched byte-exactly and case-sensitively by
`docx_zip_find`. Extra fields and comments are bounds-checked but not
preserved or interpreted.

### 2.3 Writer API and state

`DocxZipWriter` keeps the local section and central section as separate
buffers; `docx_zip_writer_finish` appends local, then central, then
EOCD and computes `cd_off`/`cd_size` from the accumulated lengths.
`docx_zip_writer_add` builds each header in a local buffer and appends it
byte-by-byte (v0.62.2 `&struct.field` -> `&Vec` parameter hazard), and
mirrors every bookkeeping push:

```
count == name_off.len() == name_len.len() == methods.len() == crcs.len()
      == comp_sizes.len() == uncomp_sizes.len() == offs.len()
```

`name_off`/`name_len` address `name_pool`. Names are written as raw
ASCII bytes with the UTF-8 name flag (bit 11) clear.

## 3. DEFLATE

### 3.1 Support matrix

| Block type | Writer | Reader |
|---|---|---|
| 0 stored | yes (`level = 0` raw ZIP; stdlib level 0 in method 8) | built-in decoder + stdlib |
| 1 fixed Huffman | yes (levels 1..9) | built-in decoder + stdlib |
| 2 dynamic Huffman | no | stdlib only, when `deflate_decompress_capped` succeeds (no 16/17/18 repeat codes); otherwise `docx: deflate dynamic huffman unsupported` |
| 3 reserved | no | `docx: deflate reserved block` |

`level` is only a selector: `level <= 0` stores, `1..9` calls the stdlib
fixed-Huffman encoder (`deflate_compress_level`, which clamps too). There
is no ratio tuning.

`docx_inflate_raw` first calls
`deflate.deflate_decompress_capped(data, max_out)`; on success its result
is returned. Otherwise `docx_inflate_fixed` handles the stream with this
module's decoder, so stored and fixed-Huffman entries are readable even
if the stdlib path rejects them. `docx_inflate_fixed` exposes the
built-in decoder directly.

### 3.2 Built-in inflated decoder behavior

* Bit order: the 3-bit block header and the length/distance extra bits
  are LSB-first integers; Huffman code words are accumulated MSB-first
  (RFC 1951 3.1.1), with fixed literal/length lengths 8/9/7/8 and 5-bit
  distance codes.
* Length/distance base and extra-bit tables are computed with the RFC
  formulas via if-chains; no module-level tables.
* Output is capped by `max_out`; a match distance beyond the bytes
  already produced is `docx: deflate bad distance`.
* Progress is bounded: bit position may not exceed
  `8 * data.len() + 64`, at most 1,000,000 blocks are accepted, and every
  stored-block length is validated against `LEN ^ 0xFFFF == NLEN`.
* Every push into the output is bounded by `max_out`, so a hostile stream
  cannot force unbounded allocation.

## 4. WordprocessingML subset

### 4.1 Parts

`[Content_Types].xml` (stored):

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
```

`_rels/.rels` (stored):

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Target="word/document.xml"/>
</Relationships>
```

`word/document.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:rPr><w:b/><w:i/><w:sz w:val="48"/></w:rPr>
        <w:t xml:space="preserve">text</w:t>
      </w:r>
    </w:p>
    <w:sectPr/>
  </w:body>
</w:document>
```

Rules:

* One `<w:rPr>` per run is written only when a style is set, in the order
  `w:b`, `w:i`, `w:sz`; nothing else is emitted inside it.
* `w:sz` carries half-points as decimal digits.
* Every run emits `<w:t xml:space="preserve">` even when the text is
  empty.
* `<w:sectPr/>` is always emitted before `</w:body>`; it is skipped on
  read.
* `docx_from_bytes` requires all three parts to be present (presence
  only; the Content_Types/relationship contents are not validated
  further).

### 4.2 Reader state machine

After locating `<w:body`, the parser scans tags:

| Tag | Behavior |
|---|---|
| `<w:p>` / `</w:p>` | Start/finish paragraph. A close while a run is open is `docx: malformed xml`. |
| `<w:r>` / `</w:r>` | Start/finish run; on close the accumulated text is materialized and appended with the current style. |
| `<w:rPr>` / `</w:rPr>` | Ignored container (children are parsed). |
| `<w:b>` | Bold = true (presence only, attributes ignored). |
| `<w:i>` | Italic = true (presence only). |
| `<w:sz>` | `w:val="D"` parsed as a decimal half-point size; absent/invalid leaves the current value. |
| `<w:t>` / `</w:t>` | Text region; bytes between the tags are decoded into the open run. `w:t` outside a run is `docx: text outside run`. |
| `<w:document>`, `<w:body>` | Ignored containers. |
| self-closing unknown | Ignored. |
| other unknown opening | The matching `</name>` is found and the whole element skipped (naive; nested same-name elements would be mis-skipped, which the documented subset does not produce). |
| `</w:body>` | Ends parsing. Missing before EOF: `docx: unterminated xml`. |

Text handling:

* Raw bytes `< 0x20` other than tab (0x09), LF (0x0A) and CR (0x0D) are
  rejected (`docx: control character in text`), as is NUL everywhere
  (`docx: nul byte in text`). No CR normalization is performed.
* Named entities `&amp; &lt; &gt; &quot; &apos;` decode to `& < > " '`.
* Numeric entities `&#DDD;` and `&#xHHH;` (also `X`) decode to a code
  point and are UTF-8 encoded. Code point 0, surrogates `D800..DFFF` and
  values above `0x10FFFF` are `docx: invalid entity`; an empty digit
  sequence is also invalid. An unterminated `&...` or an unknown name is
  `docx: unknown entity`.
* Everything else passes through as opaque bytes; multi-byte UTF-8 is
  neither validated nor altered.

Writer escaping: `& < > " '` become `&amp; &lt; &gt; &quot; &apos;`;
control bytes other than tab/LF/CR are `docx: control character in text`.

## 5. Data model

`DocxDoc` is a flat value (parallel vectors, one concatenated text
buffer; never `Vec[StructType]`, never `Vec[Str]`):

```text
para_start, para_count : Vec[Int]    paragraph -> run span
run_off, run_len       : Vec[Int]    run -> byte span in `text`
run_bold, run_italic   : Vec[Bool]   style flags
run_size               : Vec[Int]    half-points (0 = unspecified)
text                   : Str         concatenated UTF-8 run text
text_len               : Int         byte length of `text`
```

Invariants (enforced by the builders and the parser, guarded by every
consumer):

* `para_start.len() == para_count.len()` (paragraph count);
* `run_off.len() == run_len.len() == run_bold.len() == run_italic.len()
  == run_size.len()` (run count);
* `run_off[r] >= 0`, `run_len[r] >= 0`, `run_off[r] + run_len[r] <=
  text_len`, and `text_len == string.str_len(text)` for any model the
  public API produces;
* each paragraph span `[para_start[p], para_start[p] + para_count[p])`
  lies within the run arrays; spans are in order and non-overlapping.

`docx_add_paragraph` pushes `para_start = run count`, `para_count = 0`.
`docx_add_run` appends `text_len`/`str_len(text)` to the run arrays,
concatenates `text` (the only Str concatenation in the library) and
increments the last paragraph's `para_count`; if the document has no
paragraph, it creates one first. `run_size <= 0` is serialized as "no
`w:sz`" and comes back as 0.

`DocxZip` mirrors the same discipline: `name_off`/`name_len` address
`name_pool`; `pool_off`/`pool_len` address `data_pool`; the per-entry
metadata vectors (`methods`, `crcs`, `comp_sizes`, `uncomp_sizes`,
`local_offs`, `payload_off`) all share one length. A `DocxZip` is only
produced by `docx_zip_open`, and a `DocxZipWriter` only by
`docx_zip_writer_new`, so the invariants hold; all public accessors
range-check their indices.

Text is materialized as `Str` only through
`xiom.string.builder.sb_to_str` after the byte range was proven NUL-free
(the builder aborts on 0x00).

## 6. API reference

Document/read:

* `docx_version() -> Str`
* `docx_from_bytes(buffer: &Vec[UInt8]) -> Result[DocxDoc, Str]`
* `docx_paragraph_count(doc) -> Int`, `docx_run_count(doc) -> Int`
* `docx_para_run_count(doc, p) -> Result[Int, Str]`
* `docx_paragraph_text(doc, p) -> Result[Str, Str]`
* `docx_run_text(doc, r) -> Result[Str, Str]`
* `docx_run_bold(doc, r) -> Result[Bool, Str]`
* `docx_run_italic(doc, r) -> Result[Bool, Str]`
* `docx_run_size(doc, r) -> Result[Int, Str]`

Document/write and style:

* `docx_new() -> DocxDoc`
* `docx_add_paragraph(doc: &mut DocxDoc)`
* `docx_add_run(doc: &mut DocxDoc, text: Str, bold: Bool, italic: Bool, size: Int)`
* `docx_to_bytes(doc) -> Result[Vec[UInt8], Str]` (level 6)
* `docx_to_bytes_level(doc, level) -> Result[Vec[UInt8], Str]`
* `docx_points_to_half(points) -> Int`, `docx_half_to_points(half) -> Int`

ZIP:

* `docx_zip_writer_new() -> DocxZipWriter`
* `docx_zip_writer_add(w: &mut DocxZipWriter, name: Str, data: &Vec[UInt8], level: Int)`
* `docx_zip_writer_finish(w: &mut DocxZipWriter) -> Vec[UInt8]`
* `docx_zip_writer_count(w) -> Int`
* `docx_zip_open(buffer) -> Result[DocxZip, Str]`
* `docx_zip_count(z) -> Int`, `docx_zip_find(z, name) -> Int`
* `docx_zip_entry_name(z, i) -> Result[Str, Str]`
* `docx_zip_entry_data(z, i) -> Result[Vec[UInt8], Str]`
* `docx_zip_entry_method(z, i) -> Result[Int, Str]`
* `docx_zip_entry_size(z, i) -> Result[Int, Str]` (uncompressed)
* `docx_zip_entry_crc(z, i) -> Result[Int, Str]`

DEFLATE:

* `docx_inflate_raw(data, max_out) -> Result[Vec[UInt8], Str]`
* `docx_inflate_fixed(data, max_out) -> Result[Vec[UInt8], Str]`

## 7. Error catalog

All messages are deterministic and prefixed `docx: `. `N`/`M` are
decimal values.

Container / ZIP:

| Message |
|---|
| `docx: zip too small` |
| `docx: end of central directory not found` |
| `docx: multi-disk zip not supported` |
| `docx: central directory out of bounds` |
| `docx: truncated central directory` |
| `docx: bad central directory signature` |
| `docx: entry name contains nul` |
| `docx: non-ascii entry name` |
| `docx: local file header out of bounds` |
| `docx: bad local file header signature` |
| `docx: entry data out of bounds` |
| `docx: entry too large` |
| `docx: unsupported compression method N` |
| `docx: entry size mismatch` |
| `docx: crc mismatch` |
| `docx: inconsistent zip model` |
| `docx: entry index out of range` |

DEFLATE inflater:

| Message |
|---|
| `docx: deflate block limit exceeded` |
| `docx: deflate truncated` |
| `docx: deflate stored length mismatch` |
| `docx: deflate output cap exceeded` |
| `docx: deflate bad length symbol` |
| `docx: deflate bad distance symbol` |
| `docx: deflate bad distance` |
| `docx: deflate dynamic huffman unsupported` |
| `docx: deflate reserved block` |

Document / XML:

| Message |
|---|
| `docx: missing [Content_Types].xml` |
| `docx: missing _rels/.rels` |
| `docx: missing word/document.xml` |
| `docx: missing w:body` |
| `docx: malformed xml` |
| `docx: unterminated xml` |
| `docx: run outside paragraph` |
| `docx: text outside run` |
| `docx: nul byte in xml` |
| `docx: nul byte in text` |
| `docx: control character in text` |
| `docx: unknown entity` |
| `docx: invalid entity` |
| `docx: inconsistent document model` |
| `docx: paragraph index out of range` |
| `docx: run index out of range` |

The part-presence checks run in the order Content_Types, rels, document;
the first missing part wins. ZIP structural validation runs before any
part check; document parsing runs last.

## 8. Determinism and limits

* Output depends only on the document model: fixed DOS date `0x0021`,
  time 0, fixed entry order, no extra fields, no comments, no platform
  metadata.
* CRC-32 is IEEE 802.3 (init/final `0xFFFFFFFF`, reflected polynomial
  `0xEDB88320`), computed by the stdlib `gzip_crc32`; known answer:
  CRC-32("123456789") = `0xCBF43926` = 3421780262.
* Individual reads are capped at `_DOCX_MAX_ENTRY` = 67,108,864 bytes
  per entry; the EOCD search window is 65,557 bytes.
* Quantities are plain `Int` (64-bit); the ZIP writer has no oversized
  archive support.
* Types are all integer/boolean; no `Vec[Float64]` is used anywhere
  (v0.62.2 restriction).

## 9. Conformance tests

`tests/test_conformance.xi` (module `docx_tests`) runs 27 deterministic
in-memory checks and prints one `[PASS]`/`[FAIL]` line each:

| Group | Tests |
|---|---|
| version | `version is 0.1.0` |
| model round trips | `empty document round trip`, `two paragraphs and three runs round trip`, `bold/italic/size round trip`, `70000-byte stored round trip` |
| serialization | `serialization is deterministic`, `serialized document.xml carries bold markup` |
| ZIP structure | `zip has three expected entries`, `entry name and data accessors`, `mixed stored+deflate zip round trip`, `style converters, counts and CRC known answer` |
| ZIP errors | `two-byte input is rejected`, `missing EOCD is rejected`, `corrupt local signature is rejected`, `tampered stored payload fails CRC`, `unsupported compression method is rejected` |
| DEFLATE | `own inflater reads fixed and stored deflate blocks`, `dynamic huffman is a documented limitation` |
| document XML | `xml escaping round trip`, `utf-8 text round trip`, `control character in text is rejected`, `document without w:body is rejected`, `unknown entity is rejected`, `missing content types part is rejected` |
| accessors | `zip_find returns -1 for a missing entry`, `accessors range-check their indices` |

Expected suite tail:
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.
