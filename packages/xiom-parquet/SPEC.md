<!-- XIOM -- xiom.parquet specification -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.parquet -- specification

This document describes the byte-level layouts that `src/parquet.xi`
actually implements. It is a structural reader for Apache Parquet file
metadata: the Thrift **compact protocol** footer (FileMetaData) and page
headers, not page data.

## 1. Scope

Implemented:

* the `PAR1` header/footer magic, the little-endian u32 footer length and
  the `FileMetaData` struct at `len - 8 - footer_len`;
* the compact-protocol primitive layer (varint, zigzag, bool, byte,
  i16/i32/i64, double, binary/string, list, set, map, struct, skip) with a
  64-level nesting cap;
* FileMetaData: version, schema list, num_rows, row groups, file-level
  key/value metadata, created_by, column orders;
* SchemaElement: type, type_length, repetition_type, name, num_children,
  converted_type, scale, precision, field_id, logicalType presence
  (union member id only);
* RowGroup: columns, total_byte_size, num_rows, sorting_columns,
  file_offset, total_compressed_size, ordinal;
* ColumnChunk: file_path, file_offset, meta_data, offset-index and
  column-index offsets/lengths; ColumnMetaData: type, encodings,
  path_in_schema, codec, num_values, total_uncompressed_size,
  total_compressed_size, key_value_metadata, data/index/dictionary page
  offsets, statistics raw bytes, encoding_stats;
* PageHeader: type, page sizes, crc, DataPageHeader, IndexPageHeader,
  DictionaryPageHeader, DataPageHeaderV2, page-level statistics as raw
  byte ranges, and the header's consumed byte count;
* a computed schema tree walk: parent, depth, dotted path, maximum
  definition level, maximum repetition level, leaf ordinal.

Non-goals (documented, not implemented):

* **No page data decoding.** No PLAIN, RLE/bit-packing, dictionary
  (`PLAIN_DICTIONARY`, `RLE_DICTIONARY`), `DELTA_BINARY_PACKED`,
  `DELTA_LENGTH_BYTE_ARRAY`, `DELTA_BYTE_ARRAY`, `BYTE_STREAM_SPLIT`, `ALP`
  or definition/repetition level decoding. Encoding *codes* are read and
  preserved raw.
* **No compression.** `CompressionCodec` codes are exposed; no codec is
  implemented.
* **No page index/bloom filter/encryption payloads.** Their location
  fields are exposed where specified; bodies are not read.
* **No compact-protocol writer, no transport, no mmap/streaming.**
* **No semantic validation** of statistic bytes against column types.

## 2. Container layout

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `PAR1` (0x50 0x41 0x52 0x31) |
| 4 | .. | row-group data: column chunks (page headers + encoded pages) |
| metadata_start | footer_len | `FileMetaData` (Thrift compact protocol struct) |
| len-8 | 4 | footer length: u32 **little-endian** byte count of FileMetaData |
| len-4 | 4 | magic `PAR1` |

Derived:

```
footer_len     = buf[len-8] + buf[len-7]*2^8 + buf[len-6]*2^16 + buf[len-5]*2^24
metadata_start = len - 8 - footer_len
```

Validation order: `len >= 12`; header magic; footer magic; then
`footer_len <= len - 12` (equivalently `metadata_start >= 4`). The
FileMetaData reader is windowed to `[metadata_start, len-8)`, so reads can
never leak into the length or the trailing magic. After the top-level
struct's STOP the cursor must equal the window end (otherwise
`parquet: trailing data in metadata at offset N`).

## 3. Compact protocol subset

Parquet metadata uses the Thrift **compact** protocol (not the binary
protocol). The implemented subset is self-contained.

### 3.1 Varint (ULEB128)

Base-128 little-endian groups, each byte's low 7 bits payload, high bit =
continuation. At most 10 bytes. The 10th byte may contribute only one bit
(bit 63); non-minimal encodings are accepted.

`parquet_read_varint` returns the 64-bit pattern **reinterpreted as a
signed Int** (bit 63 set means a negative result). Errors (offset of the
varint start):

| Condition | Message |
|---|---|
| window ends inside the varint | `parquet: truncated varint at offset N` |
| an 11th byte would follow | `parquet: varint too long at offset N` |
| 10th byte payload > 1 | `parquet: varint overflow at offset N` |

### 3.2 Zigzag

`parquet_read_zigzag` reads one varint `u` (as the 64-bit pattern `p`
above) and decodes `n = (u >>> 1) ^ -(u & 1)` with divisor/modulo
arithmetic:

* `p >= 0`: even -> `p / 2`; odd -> `-(p / 2) - 1`.
* `p < 0`: even -> `p / 2 + 2^63`; odd -> `-(p - 1) / 2 - 2^63 - 1`.

The full signed 64-bit range round-trips, including `-2^63` (raw bytes
`FF FF FF FF FF FF FF FF FF 01`) and `2^63-1`
(`FE FF FF FF FF FF FF FF FF 01`). `parquet_read_i16/i32/i64` are all
zigzag varints; widths are not enforced (see README limitations).

### 3.3 Field headers

One byte: high nibble `delta`, low nibble `type`. If `delta` is 1..15 the
field id is `last_fid + delta`; otherwise (including 0) the long form is
used: a zero high nibble plus the field id as a zigzag varint. `0x00` is
the struct terminator (STOP). `last_fid` starts at 0 for each struct; the
caller tracks it (`parquet_read_field_header(r, last_fid)`).

Type nibbles:

| Code | Meaning |
|---|---|
| 0 | STOP (struct end, also `0x00`) |
| 1 | BOOLEAN_TRUE (value in the nibble, no bytes follow) |
| 2 | BOOLEAN_FALSE (value in the nibble, no bytes follow) |
| 3 | BYTE / I8 (one byte, sign-extended) |
| 4 | I16 (zigzag varint) |
| 5 | I32 (zigzag varint) |
| 6 | I64 (zigzag varint) |
| 7 | DOUBLE (8 bytes little-endian IEEE-754 bit pattern) |
| 8 | BINARY / STRING (varint length + bytes) |
| 9 | LIST |
| 10 | SET |
| 11 | MAP |
| 12 | STRUCT |

Codes 13+ (UUID) and gaps are rejected with
`parquet: unknown compact type N at offset M` when they appear as a field
or element type.

### 3.4 Values

* **bool**: as a *field*, the value is the header nibble (1 true, 2
  false), zero payload bytes (`parquet_field_bool`). As a *list/set/map
  element*, one byte: 1 = true, 2 = false; anything else is
  `parquet: invalid compact bool value N at offset M`.
* **byte**: one byte, sign-extended to -128..127.
* **double**: 8 bytes little-endian, first byte = least significant. The
  raw 64-bit pattern is returned in an `Int`; 1.0 is
  `0x3FF0000000000000` = 4607182418800017408.
* **binary/string**: varint length + payload. `parquet_read_binary` does
  no content validation; a negative or overrunning length is
  `parquet: binary length out of bounds at offset N` (offset of the length
  prefix). `parquet_read_string` additionally requires strict UTF-8
  (overlong forms and surrogate halves rejected) and no 0x00 byte:
  `parquet: invalid utf-8 at offset N` /
  `parquet: string contains nul at offset N`.

### 3.5 Containers

List and set share one layout:

```
short form (size 0..14):  [ size(4) | etype(4) ] elements...
long form  (size >= 15):  [ 1111   | etype(4) ] size varint  elements...
```

The long form is signalled by a size nibble of 15. The element count is
validated: negative or larger than the bytes remaining (every element
needs at least one byte) is
`parquet: oversized collection at offset N` (header offset).

Map:

```
empty:     00
non-empty: size varint  [ ktype(4) | vtype(4) ]  key value ...
```

The pair count is validated against half the remaining bytes.

### 3.6 Struct, skip, nesting

A struct is a sequence of field headers + values ended by STOP. Since
containers are self-delimiting, a struct's window is its STOP.

`parquet_skip_value(r, ctype)` consumes one field value structurally
(recursively for struct/map/list/set) and returns the byte count. Bool
*fields* consume 0 bytes; bool *elements* consume 1 byte. Skipped payloads
are not content-validated. Containers are depth-checked: the value passed
in has depth 0, a container at depth 63 is accepted, one at depth 64 is
`parquet: nesting depth exceeds limit of 64 at offset N`.

Truncation anywhere inside a primitive or container is
`parquet: truncated input at offset N`.

## 4. Decoded messages

Field ids, wire types and handling ("raw" = value preserved including
unknown enum codes). Required fields missing from the wire default to
0 / empty.

### 4.1 FileMetaData

| Field | Type | Name | Handling |
|---|---|---|---|
| 1 | i32 | version | `parquet_version` |
| 2 | list\<SchemaElement\> | schema | appended, then tree walk |
| 3 | i64 | num_rows | `parquet_num_rows` |
| 4 | list\<RowGroup\> | row_groups | appended |
| 5 | list\<KeyValue\> | key_value_metadata | shared KV pools |
| 6 | string | created_by | + presence |
| 7 | list\<ColumnOrder\> | column_orders | union member id raw |
| 8 | EncryptionAlgorithm | encryption_algorithm | skipped |
| 9 | binary | footer_signing_key_metadata | skipped |

### 4.2 SchemaElement

| Field | Type | Name | Handling |
|---|---|---|---|
| 1 | i32 (Type) | type | raw + presence; 0 BOOLEAN, 1 INT32, 2 INT64, 3 INT96, 4 FLOAT, 5 DOUBLE, 6 BYTE_ARRAY, 7 FIXED_LEN_BYTE_ARRAY |
| 2 | i32 | type_length | raw + presence |
| 3 | i32 (FieldRepetitionType) | repetition_type | raw + presence; 0 REQUIRED, 1 OPTIONAL, 2 REPEATED |
| 4 | string | name | |
| 5 | i32 | num_children | raw + presence |
| 6 | i32 (ConvertedType) | converted_type | raw + presence (22 names, see §7) |
| 7 | i32 | scale | |
| 8 | i32 | precision | |
| 9 | i32 | field_id | |
| 10 | LogicalType union | logicalType | member field id raw + presence; body skipped |

### 4.3 RowGroup

| Field | Type | Name | Handling |
|---|---|---|---|
| 1 | list\<ColumnChunk\> | columns | appended |
| 2 | i64 | total_byte_size | |
| 3 | i64 | num_rows | |
| 4 | list\<SortingColumn\> | sorting_columns | appended |
| 5 | i64 | file_offset | + presence |
| 6 | i64 | total_compressed_size | + presence |
| 7 | i16 | ordinal | + presence |

`SortingColumn`: 1 i32 `column_idx`, 2 bool `descending`, 3 bool
`nulls_first`.

### 4.4 ColumnChunk

| Field | Type | Name | Handling |
|---|---|---|---|
| 1 | string | file_path | + presence |
| 2 | i64 | file_offset | |
| 3 | ColumnMetaData | meta_data | + presence |
| 4 | i64 | offset_index_offset | + presence |
| 5 | i32 | offset_index_length | + presence |
| 6 | i64 | column_index_offset | + presence |
| 7 | i32 | column_index_length | + presence |
| 8 | ColumnCryptoMetaData | crypto_metadata | skipped |
| 9 | binary | encrypted_column_metadata | skipped |

### 4.5 ColumnMetaData

| Field | Type | Name | Handling |
|---|---|---|---|
| 1 | i32 (Type) | type | raw + presence |
| 2 | list\<i32\> | encodings | raw codes in `enc_pool` |
| 3 | list\<string\> | path_in_schema | `path_pool` + span |
| 4 | i32 (CompressionCodec) | codec | raw + presence |
| 5 | i64 | num_values | + presence |
| 6 | i64 | total_uncompressed_size | + presence |
| 7 | i64 | total_compressed_size | + presence |
| 8 | list\<KeyValue\> | key_value_metadata | KV pools + span |
| 9 | i64 | data_page_offset | + presence |
| 10 | i64 | index_page_offset | + presence |
| 11 | i64 | dictionary_page_offset | + presence |
| 12 | Statistics | statistics | one block per chunk |
| 13 | list\<PageEncodingStats\> | encoding_stats | appended |
| 14 | i64 | bloom_filter_offset | skipped |
| 15 | i32 | bloom_filter_length | skipped |
| 16 | SizeStatistics | size_statistics | skipped |
| 17 | GeospatialStatistics | geospatial_statistics | skipped |

`CompressionCodec`: 0 UNCOMPRESSED, 1 SNAPPY, 2 GZIP, 3 LZO, 4 BROTLI,
5 LZ4, 6 ZSTD, 7 LZ4_RAW.

### 4.6 Statistics

All fields optional. Raw byte fields are appended to the shared
`st_pool` and located by `(off, len)`; a chunk without a Statistics
struct gets an all-absent block so every per-chunk vector stays aligned.

| Field | Type | Name | Handling |
|---|---|---|---|
| 1 | binary | max | raw bytes (deprecated) |
| 2 | binary | min | raw bytes (deprecated) |
| 3 | i64 | null_count | + presence |
| 4 | i64 | distinct_count | + presence |
| 5 | binary | max_value | raw bytes |
| 6 | binary | min_value | raw bytes |
| 7 | bool | is_max_value_exact | + presence |
| 8 | bool | is_min_value_exact | + presence |
| 9 | i64 | nan_count | skipped |

The bytes are the PLAIN-encoded bound without a length prefix, exactly as
Parquet defines them; this reader does not interpret them.

### 4.7 PageEncodingStats and KeyValue

`PageEncodingStats`: 1 i32 `page_type`, 2 i32 `encoding`, 3 i32 `count`
(all raw). `KeyValue`: 1 string `key`, 2 optional string `value`
(presence recorded).

### 4.8 ColumnOrder and LogicalType unions

Only the union **member field id** is recorded raw (plus presence); the
member body is skipped. ColumnOrder member names: 1 TYPE_ORDER,
2 IEEE_754_TOTAL_ORDER, 3 INT96_TIMESTAMP_ORDER. LogicalType member
names: 1 STRING, 2 MAP, 3 LIST, 4 ENUM, 5 DECIMAL, 6 DATE, 7 TIME,
8 TIMESTAMP, 10 INTEGER, 11 UNKNOWN, 12 JSON, 13 BSON, 14 UUID,
15 FLOAT16, 16 VARIANT, 17 GEOMETRY, 18 GEOGRAPHY, 19 FILE.

## 5. Schema tree walk

The schema list is depth-first; element 0 is the root. Every element's
`num_children` (default 0) claims that many following subtrees. The walk
computes, for every element:

* `parent` (root = -1) and `depth` (root = 0);
* `path`: root = `""`, root children = `name`, deeper = `parent.path + "." + name`;
* `max_def` = parent's + 1 when the element's repetition is present and
  not REQUIRED (OPTIONAL or REPEATED), else parent's;
* `max_rep` = parent's + 1 when repetition is REPEATED, else parent's;
* `leaf_index`: 0, 1, ... in depth-first order for elements with
  `num_children == 0`; groups get -1. Leaf ordinals match the order of
  `RowGroup.columns`.

Structural errors (offset = metadata_start):

| Condition | Message |
|---|---|
| more elements than declared children | `parquet: schema element count does not match num_children at offset N` |
| a group's children are not fully present | same message |
| negative `num_children` | `parquet: schema element has negative num_children at offset N` |

## 6. PageHeader

`parquet_parse_page_header(buffer, offset)` decodes one header starting at
an absolute offset; `consumed` is the header's byte length. The page body
is not touched. Sub-header members may all be absent; each has a
presence accessor.

| Field | Type | Name | Handling |
|---|---|---|---|
| 1 | i32 (PageType) | type | + presence; 0 DATA_PAGE, 1 INDEX_PAGE, 2 DICTIONARY_PAGE, 3 DATA_PAGE_V2 |
| 2 | i32 | uncompressed_page_size | + presence |
| 3 | i32 | compressed_page_size | + presence |
| 4 | i32 | crc | + presence (`parquet_page_crc` errs when absent) |
| 5 | DataPageHeader | data_page_header | + presence |
| 6 | IndexPageHeader | index_page_header | + presence (body skipped) |
| 7 | DictionaryPageHeader | dictionary_page_header | + presence |
| 8 | DataPageHeaderV2 | data_page_header_v2 | + presence |

`DataPageHeader`: 1 i32 `num_values`, 2 i32 `encoding`, 3 i32
`definition_level_encoding`, 4 i32 `repetition_level_encoding`,
5 Statistics (recorded as raw range: `dp_stats_offset` .. `dp_stats_end`,
end = just past the STOP).

`DictionaryPageHeader`: 1 i32 `num_values`, 2 i32 `encoding`, 3 optional
bool `is_sorted` (+ presence).

`DataPageHeaderV2`: 1 i32 `num_values`, 2 i32 `num_nulls`, 3 i32
`num_rows`, 4 i32 `encoding`, 5 i32 `definition_levels_byte_length`,
6 i32 `repetition_levels_byte_length`, 7 optional bool `is_compressed`
(+ presence; accessor errs when absent rather than assuming the Parquet
default), 8 Statistics (raw range `v2_stats_offset` .. `v2_stats_end`).

Parse error for an offset outside `[0, len)`: 
`parquet: page header offset out of range (offset=N)`.

## 7. Enum name tables (accessors)

* Type: 0 BOOLEAN .. 7 FIXED_LEN_BYTE_ARRAY (§4.2).
* FieldRepetitionType: 0 REQUIRED, 1 OPTIONAL, 2 REPEATED.
* ConvertedType: 0 UTF8, 1 MAP, 2 MAP_KEY_VALUE, 3 LIST, 4 ENUM,
  5 DECIMAL, 6 DATE, 7 TIME_MILLIS, 8 TIME_MICROS, 9 TIMESTAMP_MILLIS,
  10 TIMESTAMP_MICROS, 11 UINT_8, 12 UINT_16, 13 UINT_32, 14 UINT_64,
  15 INT_8, 16 INT_16, 17 INT_32, 18 INT_64, 19 JSON, 20 BSON,
  21 INTERVAL.
* Encoding: 0 PLAIN, 2 PLAIN_DICTIONARY, 3 RLE, 4 BIT_PACKED,
  5 DELTA_BINARY_PACKED, 6 DELTA_LENGTH_BYTE_ARRAY, 7 DELTA_BYTE_ARRAY,
  8 RLE_DICTIONARY, 9 BYTE_STREAM_SPLIT, 10 ALP. The retired
  GROUP_VAR_INT (1) and values beyond 10 are `"unknown"`.
* CompressionCodec, PageType, ColumnOrder, LogicalType: §4.5/§4.8/§6.

Every `*_name` helper returns `"unknown"` for values outside its table;
the raw code is always preserved by the accessor.

## 8. Error catalog

`parquet: ` prefixed, deterministic. Offsets are absolute buffer offsets.

Container level:

| Message |
|---|
| `parquet: file too small` |
| `parquet: bad header magic` |
| `parquet: bad footer magic` |
| `parquet: footer length out of bounds (len=N)` |
| `parquet: trailing data in metadata at offset N` |
| `parquet: schema element count does not match num_children at offset N` |
| `parquet: schema element has negative num_children at offset N` |

Compact layer (offset = where the construct starts):

| Message |
|---|
| `parquet: truncated varint at offset N` |
| `parquet: varint too long at offset N` |
| `parquet: varint overflow at offset N` |
| `parquet: truncated input at offset N` |
| `parquet: unknown compact type N at offset M` |
| `parquet: invalid compact bool value N at offset M` |
| `parquet: binary length out of bounds at offset N` |
| `parquet: oversized collection at offset N` |
| `parquet: nesting depth exceeds limit of 64 at offset N` |
| `parquet: string contains nul at offset N` |
| `parquet: invalid utf-8 at offset N` |
| `parquet: unexpected list element type N at offset M` |

Page headers:

| Message |
|---|
| `parquet: page header offset out of range (offset=N)` |

Accessors (no offsets; deterministic index/name errors):

| Message |
|---|
| `parquet: schema index out of range` |
| `parquet: row group index out of range` |
| `parquet: row group column index out of range` |
| `parquet: column chunk index out of range` |
| `parquet: sorting column index out of range` |
| `parquet: encoding index out of range` |
| `parquet: path index out of range` |
| `parquet: key value index out of range` |
| `parquet: encoding stats index out of range` |
| `parquet: column order index out of range` |
| `parquet: column chunk has no file_path` |
| `parquet: column chunk has no index_page_offset` |
| `parquet: column chunk has no dictionary_page_offset` |
| `parquet: column chunk has no path_in_schema` |
| `parquet: key value entry has no value` |
| `parquet: statistic not present (chunk=N, stat=NAME)` |
| `parquet: page header has no crc` |
| `parquet: dictionary page header has no is_sorted` |
| `parquet: data page header v2 has no is_compressed` |

## 9. Data model

A parsed file is a single flat `ParquetFile` struct of parallel vectors
(never `Vec[StructType]`): schema vectors, per-row-group vectors,
per-chunk vectors with `*_off`/`*_count` spans into shared pools
(`enc_pool`, `path_pool`, `kv_key`/`kv_value`/`kv_value_present`,
`es_page_type`/`es_encoding`/`es_count`, `st_pool`), and one statistics
block per column chunk. A `ParquetFile` is only produced by
`parquet_parse`, so accessors trust the layout; all public accessors
range-check their indices.
