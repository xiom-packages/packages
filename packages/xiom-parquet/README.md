# xiom.parquet

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM Apache Parquet **file metadata structure** parser:
> the Thrift compact-protocol footer (FileMetaData, schema tree, row
> groups, column chunks, statistics raw bytes, page headers). Page *data*
> is never decoded; no data encodings, no compression, no FFI.
> **Deps:** `xiom.std` only. The library module uses
> `xiom.string.builder`, `xiom.convert` and `xiom.string.compare`; the
> tests add `xiom.test`, `xiom.io` and `xiom.string`.

## What it is

`xiom.parquet` parses the structure of an Apache Parquet file without
touching column data:

```
[4]   magic "PAR1"
[..]  row-group data (column chunks: page headers + encoded pages)
[..]  FileMetaData          Thrift compact protocol struct
[4]   footer length         u32 little-endian byte count of FileMetaData
[4]   magic "PAR1"
```

`parquet_parse` validates both magics, reads the footer length, decodes
the FileMetaData struct at `len - 8 - footer_len`, then computes the
schema tree walk (parent, depth, dotted path, maximum definition and
repetition levels, leaf ordinals). `parquet_parse_page_header` decodes a
PageHeader at any absolute offset and reports how many bytes it consumed.

The embedded compact-protocol reader is a full primitive layer: varints
(LEB128), zigzag, bool (field value in the header nibble, element value as
`1`/`2`), byte, i16/i32/i64, double (raw 64-bit IEEE-754 pattern from 8
little-endian bytes), binary/string with strict UTF-8 + NUL validation,
list/set (short and long headers), map (including the single-byte empty
map), struct with delta/long-form field headers and STOP, plus a
structural `parquet_skip_value` with a 64-level nesting cap. Every parse
error names the byte offset where it was detected.

Unknown enum values are preserved raw (the `*_name` helpers return
`"unknown"` beyond the documented range) and unknown struct fields of any
supported type are skipped, so files written by newer Parquet writers
remain readable.

## API

| Function | Returns | Description |
|---|---|---|
| `parquet_parse(buffer)` | `Result[ParquetFile, Str]` | Parse magics, footer length and FileMetaData. |
| `parquet_file_length/metadata_offset/footer_length/version/num_rows` | `Int` | Top-level metadata. |
| `parquet_created_by(f)` / `parquet_created_by_present(f)` | `Str` / `Bool` | Writer string and its presence. |
| `parquet_schema_count/leaf_count(f)` | `Int` | Schema element / leaf counts. |
| `parquet_schema_name/type/type_length/repetition/num_children/converted_type/scale/precision/field_id/logical_type` | accessors | Raw SchemaElement fields (0/"absent" defaults plus `*_present` helpers). |
| `parquet_schema_parent/depth/path/max_definition_level/max_repetition_level/is_leaf/leaf_index` | accessors | Computed tree walk per element. |
| `parquet_schema_find_path(f, path)` | `Int` | Schema index with that dotted path, or -1. |
| `parquet_schema_type_name/parquet_converted_type_name/parquet_logical_type_name/parquet_schema_repetition_name` | `Str` | Enum names ("unknown" beyond the documented range). |
| `parquet_row_group_count(f)` | `Int` | Row group count. |
| `parquet_row_group_num_rows/total_byte_size/file_offset/total_compressed_size/ordinal/column_count` | accessors | RowGroup fields with presence helpers. |
| `parquet_row_group_column(f, g, c)` | `Result[Int, Str]` | Global column-chunk index of a row-group column. |
| `parquet_row_group_sorting_count` / `parquet_sorting_column_idx/descending/nulls_first` | accessors | SortingColumn entries. |
| `parquet_chunk_count(f)` | `Int` | Total column chunks. |
| `parquet_chunk_file_offset/type/codec/num_values/total_uncompressed_size/total_compressed_size/data_page_offset` | accessors | ColumnChunk + ColumnMetaData fields. |
| `parquet_chunk_file_path/index_page_offset/dictionary_page_offset` | `Result` | Optional fields (Err when absent). |
| `parquet_chunk_offset_index_offset/length`, `parquet_chunk_column_index_offset/length` | accessors | Page-index locations (payloads not read). |
| `parquet_chunk_encoding_count` / `parquet_chunk_encoding(f, c, e)` | `Int` / `Result` | Encodings list (raw codes). |
| `parquet_chunk_path_count` / `parquet_chunk_path(f, c, p)` / `parquet_chunk_path_joined(f, c)` | accessors | `path_in_schema` parts / dotted join. |
| `parquet_chunk_key_value_count/key/value` | accessors | Per-chunk `key_value_metadata`. |
| `parquet_chunk_stat_present(f, c)` | `Result[Bool, Str]` | Statistics presence. |
| `parquet_chunk_stat_max/min/max_value/min_value(f, c)` | `Result[Vec[UInt8], Str]` | Raw PLAIN-encoded bytes. |
| `parquet_chunk_stat_null_count/distinct_count(f, c)` | `Result[Int, Str]` | Counters. |
| `parquet_chunk_stat_max_exact/min_exact(f, c)` | `Result[Bool, Str]` | Exactness flags. |
| `parquet_chunk_encoding_stats_count` / `parquet_chunk_encoding_stat_page_type/encoding/count` | accessors | PageEncodingStats entries. |
| `parquet_file_key_value_count/key/value` | accessors | File-level `key_value_metadata`. |
| `parquet_column_order_count` / `parquet_column_order(f, i)` / `parquet_column_order_name(m)` | accessors | ColumnOrder union member ids (raw). |
| `parquet_encoding_name` / `parquet_codec_name` / `parquet_page_type_name` | `Str` | Enum names. |
| `parquet_parse_page_header(buffer, offset)` | `Result[ParquetPageHeader, Str]` | Decode one PageHeader at an offset. |
| `parquet_page_*` accessors | various | Page type/sizes/crc, consumed count, DataPageHeader, IndexPageHeader, DictionaryPageHeader, DataPageHeaderV2 and raw statistics ranges. |
| `parquet_reader_new/new_at/pos/remaining` | `ParquetReader` accessors | Cursor lifecycle over a buffer or window. |
| `parquet_read_varint/zigzag/bool/byte/i16/i32/i64/double_bits/binary/string` | `Result` | Compact primitives. |
| `parquet_read_field_header(r, last_fid)` | `Result[ParquetField, Str]` | Delta/long-form field header (bool value in the nibble). |
| `parquet_read_list_header/set_header/map_header` | `Result` | Container headers. |
| `parquet_skip_value(r, ctype)` | `Result[Int, Str]` | Structurally skip one value; bytes consumed. |
| `parquet_max_depth()`, `parquet_compact_type_known/name`, `parquet_compact_*()` | `Int`/`Bool`/`Str` | Codec metadata. |

Errors are deterministic `parquet: ...` strings; the exact catalog and
check order are in SPEC.md.

## Usage

```xi
use xiom.parquet;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  var buf = Vec[UInt8].new();
  // ... load a Parquet file into buf ...
  let pr = parquet_parse(&buf);
  if !pr.is_ok {
    io.println("parse error: " + pr.error);
    return 1;
  }
  let f: ParquetFile = pr.value;
  io.println("rows: " + convert.int_to_string(parquet_num_rows(&f)));
  io.println("columns: " + convert.int_to_string(parquet_schema_leaf_count(&f)));

  // Walk the schema tree.
  var i = 0;
  while i < parquet_schema_count(&f) {
    let p = parquet_schema_path(&f, i);
    let d = parquet_schema_max_definition_level(&f, i);
    if p.is_ok && d.is_ok {
      io.println(p.value + " maxdef=" + convert.int_to_string(d.value));
    }
    i = i + 1;
  }

  // Column chunk statistics (raw PLAIN bytes).
  if parquet_chunk_count(&f) > 0 {
    let mn = parquet_chunk_stat_min_value(&f, 0);
    if mn.is_ok {
      io.println("min bytes: " + convert.int_to_string(mn.value.len()));
    }
  }

  // A page header at a known offset (e.g. data_page_offset).
  let dpo = parquet_chunk_data_page_offset(&f, 0);
  if dpo.is_ok {
    let h = parquet_parse_page_header(&buf, dpo.value);
    if h.is_ok {
      io.println("page type: " + parquet_page_type_name(parquet_page_type(&h.value)));
      io.println("header bytes: " + convert.int_to_string(parquet_page_consumed(&h.value)));
    }
  }
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.parquet
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Metadata structure only.** Page payloads (PLAIN, RLE/bit-packing,
  dictionary, delta, byte-stream-split values, repetition/definition
  levels) are never decoded, and no compression codec is implemented.
  Page indexes, bloom filters, encryption and external column data are not
  read (their location fields are exposed where specified).
- **Compact protocol only, no transport.** The reader works on in-memory
  byte buffers; there is no framing, socket or file I/O layer and no
  compact-protocol *writer*.
- **Doubles are raw bit patterns.** There is no `Float64` API because
  v0.61.3 cannot bitcast; `parquet_read_double_bits` returns the 64-bit
  IEEE-754 pattern carried in an `Int` (8 little-endian wire bytes).
- **Strings are validated on read.** `parquet_read_string` requires valid
  UTF-8 and rejects 0x00 (`parquet: string contains nul at offset N`)
  because the v0.61.3 string builder aborts on NUL. Schema names,
  paths, `created_by` and key/value strings therefore must be NUL-free
  UTF-8; use `parquet_read_binary` for arbitrary bytes.
- **i16/i32 are not width-checked.** Compact protocol integers travel as
  zigzag varints without a fixed width, so a value that does not fit the
  nominal Thrift width round-trips as read instead of being rejected.
- **Collection sizes are bounded by the bytes remaining** (1 byte per
  list/set element, 2 per map pair): an absurd size is
  `parquet: oversized collection` instead of a huge loop.
- **Skip nesting is capped** at 64 container levels; deeper values are
  `parquet: nesting depth exceeds limit of 64 at offset N`.
- **Required fields are lenient.** A missing Thrift-required field decodes
  to its default (0 / empty) rather than failing, for forward
  compatibility with newer writers.
- **Page-level statistics are raw ranges.** `dp_stats_offset`/`_end` and
  `v2_stats_offset`/`_end` delimit the Statistics struct inside the buffer;
  its contents are not decoded (column-chunk statistics are).
- Fields are decoded into flat parallel vectors; plain value types; not
  thread-safe.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
