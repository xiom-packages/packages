<!-- XIOM -- xiom.orc specification -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.orc -- specification

## 1. Scope

A pure-XIOM, dependency-free codec for the **metadata** of an Apache ORC
file:

* validate the 3-byte `ORC` magic and parse the postscript (compression
  kind and block size, footer/metadata lengths, format version parts,
  writer version, postscript magic);
* for uncompressed files, decode the file footer (stripe table, schema
  type tree, row count, row-index stride, writer version, number of
  statistics entries), every stripe footer (stream kind/column/length
  lists) and the file metadata (per-stripe statistics counts);
* expose all of the above through free functions;
* report every malformed input deterministically, with byte offsets for
  protobuf-level failures.

## 2. Non-goals

* No column data decode: no RLE/bit-packing, dictionary, present-bit,
  secondary, row-index, bloom-filter or stripe-statistics payload
  decoding. Statistics entries are counted, never inspected.
* No decompression. The footer, metadata and stripe footers of compressed
  ORC files are themselves compressed streams; without a decompressor the
  codec cannot read them. Such files yield postscript metadata only.
* No writing, no mmap/streaming; the whole buffer is parsed in one call.
* No encryption support; encryption-related fields are skipped.
* Field names are restricted to printable ASCII (see §12).
* No semantic validation of the type tree beyond column-id and
  struct-field-count consistency.

## 3. Container layout

| Offset | Size | Field |
|---|---|---|
| 0 | 3 | magic `ORC` (0x4F 0x52 0x43) |
| 3 | .. | stripes (index/data streams plus each stripe footer) |
| footer_start | footerLength | file footer (`Footer` protobuf) |
| metadata_start | metadataLength | file metadata (`Metadata` protobuf, optional) |
| ps_start | ps_len | postscript (`PostScript` protobuf, never compressed) |
| total-1 | 1 | postscript length byte (`ps_len`, 1..255) |

Derived offsets:

```
ps_start       = total - 1 - ps_len
footer_start   = ps_start - metadataLength - footerLength
metadata_start = footer_start + footerLength
```

The footer, metadata and stripe footers are decoded only when the
postscript declares `compression == NONE`. Region bounds are always
validated: `footer_start >= 3` and `metadata_start + metadataLength ==
ps_start`, otherwise `orc: footer length out of bounds` or
`orc: metadata length out of bounds`.

## 4. Postscript fields

| Field | Wire | Name | Handling |
|---|---|---|---|
| 1 | 0 | `footerLength` | footer region size in bytes |
| 2 | 0 | `compression` | `CompressionKind`; values above 4 rejected |
| 3 | 0 | `compressionBlockSize` | exposed as declared |
| 4 | 0 or 2 | `version` | repeated uint32, packed or unpacked; parts exposed in order |
| 5 | 0 | `metadataLength` | metadata region size (0 when absent) |
| 6 | 0 | `writerVersion` | writer-version code (see §7) |
| 8000 | 2 | `magic` | when present it must be exactly `ORC` |

All other fields are skipped. A postscript without `footerLength` or
`metadataLength` describes zero-length regions and is accepted (real
writers always set them).

## 5. Protobuf wire-format subset

The decoder is self-contained and implements exactly what ORC needs:

* **varint**: base-128, little-endian groups, at most 10 bytes. The 10th
  byte may contribute only bit 63 (non-minimal encodings are accepted).
  Errors: `orc: truncated varint`, `orc: varint too long`,
  `orc: varint overflow`, all with the offset of the varint start.
* **tag**: `field = tag / 8`, `wire = tag % 8`. `field` must be
  `1..2^29-1`; `wire` must be 0, 1, 2 or 5 (groups 3/4 and the reserved
  6/7 are rejected as `orc: invalid wire type W`).
* **wire types**: 0 varint; 1 fixed 64-bit (8 bytes, skipped);
  2 length-delimited; 5 fixed 32-bit (4 bytes, skipped).
* **length prefix**: the payload must fit the current message window,
  else `orc: field length out of bounds` at the prefix offset. A fixed
  read that would cross the window is `orc: truncated field`.
* **packed repeated**: a repeated numeric field accepts the packed form
  (wire 2, a run of varints inside one length-delimited payload) and the
  unpacked form (wire 0, one element per tag).
* **unknown fields** and known fields carrying an unexpected wire type are
  skipped, preserving protobuf forward compatibility.
* Submessages are parsed inside their own window, so a length cannot leak
  reads into the enclosing message.

## 6. Decoded messages

`Footer`:

| Field | Wire | Name | Handling |
|---|---|---|---|
| 1 | 0 | `headerLength` | exposed |
| 2 | 0 | `contentLength` | exposed |
| 3 | 2 | `stripes` | `StripeInformation`, appended in order |
| 4 | 2 | `types` | `Type`, appended in column-id order |
| 5 | 0 | `numberOfRows` | exposed |
| 6 | 2 | `statistics` | `ColumnStatistics` counted, payload skipped |
| 7 | 0 | `rowIndexStride` | exposed |
| 8 | 0 | `writerVersion` | exposed |

`StripeInformation`: 1 `offset`, 2 `indexLength`, 3 `dataLength`,
4 `footerLength`, 5 `numberOfRows` (all varints, default 0).

`Type`: 1 `kind`, 2 `subtypes` (packed/unpacked column ids), 3
`fieldNames` (length-delimited printable strings), 4 `maximumLength`,
5 `precision`, 6 `scale`; other fields skipped.

`StripeFooter`: 1 `streams` (`Stream`: 1 `kind`, 2 `column`, 3 `length`);
column encodings, timezone and other fields skipped. Streams are stored
with a **synthesized offset**: 0 for the first stream and the running
total of preceding lengths afterwards, because ORC streams carry only
lengths.

`Metadata`: 1 `stripeStats` (`StripeStatistics`); for each entry the
number of `colStats` (field 1) entries is recorded, payloads are skipped.

Type-tree validation after the footer parse:

* every subtype value must be a valid column id, else
  `orc: subtype column out of range (column=N)`;
* a `STRUCT` column must declare as many field names as subtypes, else
  `orc: struct field name count mismatch (column=N)`.

Stripe extent validation before a stripe footer is parsed (conditions use
non-negative remainders, values are checked in order): `offset`,
`offset + indexLength`, `offset + indexLength + dataLength` and
`offset + indexLength + dataLength + footerLength` must all be at most
the buffer length, else
`orc: stripe extends past end of buffer (stripe=N)`. Each stream's column
must be a valid column id, else
`orc: stream column out of range (stripe=N, stream=M)`.

## 7. Enumerations

Compression kinds (`PostScript.compression`): 0 `NONE`, 1 `ZLIB`,
2 `SNAPPY`, 3 `LZ4`, 4 `ZSTD`; others are rejected at parse time.

Writer versions (`writerVersion`): 0 `ORIGINAL`, 1 `HIVE_8732`,
2 `HIVE_4243`, 3 `HIVE_12055`, 4 `HIVE_13083`, 5 `ORC_101`,
6 `ORC_135`, 7 `ORC_517`, 8 `ORC_203`, 9 `ORC_14`; other codes render as
`unknown` (the numeric accessor still returns the raw code).

Type kinds (`Type.kind`): 0 `BOOLEAN`, 1 `BYTE`, 2 `SHORT`, 3 `INT`,
4 `LONG`, 5 `FLOAT`, 6 `DOUBLE`, 7 `STRING`, 8 `BINARY`, 9 `TIMESTAMP`,
10 `LIST`, 11 `MAP`, 12 `STRUCT`, 13 `UNION`, 14 `DECIMAL`, 15 `DATE`,
16 `VARCHAR`, 17 `CHAR`, 18 `TIMESTAMP_INSTANT`; others render as
`unknown`.

Stream kinds (`Stream.kind`): 0 `PRESENT`, 1 `DATA`, 2 `LENGTH`,
3 `DICTIONARY_DATA`, 4 `DICTIONARY_COUNT`, 5 `SECONDARY`, 6 `ROW_INDEX`,
7 `BLOOM_FILTER`, 8 `BLOOM_FILTER_UTF8`; others render as `unknown`.

## 8. Error catalog (exact messages)

Structural (`orc_parse`):

* `orc: file too small` -- fewer than 4 bytes.
* `orc: bad magic` -- bytes 0..2 are not `ORC`.
* `orc: empty postscript` -- the trailing length byte is 0.
* `orc: postscript length out of bounds (len=N)` -- the postscript would
  start before the magic.
* `orc: bad postscript magic` -- the postscript magic field is present and
  is not exactly `ORC`.
* `orc: unsupported compression kind (kind=N)` -- `N > 4`.
* `orc: footer length out of bounds (len=N)`.
* `orc: metadata length out of bounds (len=N)`.

Protobuf (all carry the detected byte offset; from the postscript, footer,
stripe footers or metadata):

* `orc: truncated varint at offset N`
* `orc: varint too long at offset N`
* `orc: varint overflow at offset N`
* `orc: invalid field number at offset N`
* `orc: invalid wire type W at offset N`
* `orc: truncated field at offset N`
* `orc: field length out of bounds at offset N`

Content:

* `orc: field name is not printable at offset N`
* `orc: subtype column out of range (column=N)`
* `orc: struct field name count mismatch (column=N)`
* `orc: stripe extends past end of buffer (stripe=N)`
* `orc: stream column out of range (stripe=N, stream=M)`

Accessors:

* `orc: footer not available (compressed file)`
* `orc: version part index out of range`
* `orc: stripe index out of range`
* `orc: column index out of range`
* `orc: subtype index out of range`
* `orc: field name index out of range`
* `orc: stream index out of range`
* `orc: stripe stats index out of range`

## 9. API contract

Parsing: `orc_parse(&Vec[UInt8]) -> Result[Orc, Str]`.

Postscript accessors (always available): `orc_file_length`,
`orc_postscript_offset`, `orc_postscript_length`, `orc_footer_offset`,
`orc_compression`, `orc_compression_name`, `orc_block_size`,
`orc_version_count`, `orc_version_part`, `orc_version_major`,
`orc_version_minor`, `orc_writer_version`, `orc_writer_version_name`,
`orc_footer_length`, `orc_metadata_length`, `orc_footer_available`.

Footer accessors (available when `orc_footer_available` is true):
`orc_header_length`, `orc_content_length`, `orc_row_index_stride`,
`orc_rows`, `orc_footer_writer_version`, `orc_stripe_count`,
`orc_stripe_offset`, `orc_stripe_index_length`, `orc_stripe_data_length`,
`orc_stripe_footer_length`, `orc_stripe_rows`.

Type-tree accessors: `orc_columns`, `orc_column_kind`,
`orc_column_kind_name`, `orc_column_field_count`, `orc_column_field_name`,
`orc_column_subtype_count`, `orc_column_subtype`,
`orc_column_max_length`, `orc_column_precision`, `orc_column_scale`.

Statistics accessors: `orc_stats_count`, `orc_column_has_stats`,
`orc_stripe_stats_count`, `orc_stripe_stats_cols`.

Stream accessors: `orc_stream_count`, `orc_stripe_stream_count`,
`orc_stream_kind`, `orc_stream_kind_name`, `orc_stream_column`,
`orc_stream_offset`, `orc_stream_length`.

`Orc` stores everything in parallel vectors (the pinned compiler
miscompiles `Vec[StructType]`); field groups are documented on the type.
Values are only produced by `orc_parse`, so the invariants always hold.

`orc_footer_available` is true exactly when `compression == NONE`; for
compressed files every footer-derived accessor returns
`Err("orc: footer not available (compressed file)")`.

## 10. Validation order (parse)

1. length >= 4; magic; `ps_len != 0`; `ps_start >= 3`.
2. parse the postscript (protobuf rules; magic field if present).
3. `compression <= 4`; footer/metadata region fit.
4. `compression != NONE`: stop successfully with postscript metadata only.
5. parse the footer; validate the type tree.
6. per stripe: extent bound checks; parse the stripe footer; validate
   stream columns.
7. parse the metadata (stripe statistics counts).

## 11. Test matrix (33 checks)

| Test | Checks |
|---|---|
| t1 | minimal file: compression, block size, version 0.12, writer version, postscript/file bounds, footer availability, zero stripes/columns/rows |
| t2 | bad file magic |
| t3 | buffer shorter than 4 bytes |
| t4 | zero postscript length |
| t5 | postscript length beyond the header |
| t6 | postscript magic `ORX` |
| t7 | compression kind 9 |
| t8 | ZLIB file: postscript metadata, gated footer accessor message |
| t9 | footer length over the postscript region |
| t10 | metadata length over the postscript region |
| t11 | postscript ending inside a varint |
| t12 | footer ending inside a varint |
| t13 | footer: two stripes, three types, rows, statistics flags and their bounds errors |
| t14 | stripe footer streams: kinds/columns/synthesized offsets/lengths and bounds |
| t15 | metadata stripe statistics counts and bounds |
| t16 | subtype column out of range |
| t17 | struct field name count mismatch |
| t18 | non-printable field name with exact offset |
| t19 | stripe extending past the buffer |
| t20 | wire type 3 (group) rejected with offset |
| t21 | unknown wire types 1 and 5 skipped |
| t22 | accessor bounds: version part, stripe, column, stream |
| t23 | unpacked version parts and unpacked single subtype |
| t24 | compression/type/stream/writer name tables |
| t25 | full integration: schema tree, stripe with streams, statistics, metadata |

## 12. Documented limitations

* Compressed files expose postscript metadata only (no decompressor).
* The whole file buffer is expected; a prefix omitting stripe footers is
  rejected.
* Statistics presence is positional: entry `i` is attributed to column
  `i`; per-entry column ids are not decoded.
* Stream offsets are synthesized from lengths.
* Field names must be printable ASCII (`0x20..0x7E`), non-empty is not
  required; NUL and UTF-8 are rejected.
* Stripe offsets are only checked against the buffer length, not against
  `headerLength`/`contentLength`; overlapping stripes are not rejected.
* The root column is not required to be a `STRUCT`, and subtype arity is
  not checked per kind except for `STRUCT` field names.
* Version parts are exposed verbatim; no range checking beyond varint
  bounds.

## 13. Compiler notes (v0.61.3)

Ok/Err construction is confined to leaf helpers; every `Vec[Int]` element
read is bound to a typed local; every `UInt8` is widened with
`(b as Int) & 0xFF`; parallel vectors are appended with mirrored pushes
only; field names are validated printable before `sb_to_str` so it never
sees a 0x00 byte; no `&struct.field` is passed as a `&Vec[UInt8]`
argument; no generics other than the `Result[...]`/`Vec[...]` built-ins.
