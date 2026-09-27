<!-- XIOM -- xiom.orc README -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.orc

A production-grade, dependency-free Apache ORC **file metadata** codec for
XIOM: parse and validate the postscript, the protobuf-encoded file footer,
the stripe table, the schema type tree, each stripe footer's stream list
and the statistics-presence flags of ORC files. Column data is never
decoded.

* Pure XIOM, no FFI, deps: `xiom.std` only.
* Self-contained protobuf wire-format subset decoder (varints, wire types
  0/1/2/5, length-delimited submessages, packed repeated varints) applied
  to the ORC postscript, footer, stripe footers and metadata.
* Deterministic `Err(Str)` catalog with byte offsets (see SPEC.md §8).
* 33 conformance checks (`tests/test_conformance.xi`), including synthetic
  ORC buffers with hand-encoded protobufs built in the test file.

## Install

```toml
xiom.orc = "0.1.0"
```

## Quick start

```xi
use xiom.orc;

let r = orc_parse(&bytes);           // the whole file buffer
if !r.is_ok {
  io.println("orc: " + r.error);
  return 1;
}
let o = r.value;
io.println("compression: " + orc_compression_name(orc_compression(&o)));
io.println("block size:  " + convert.int_to_string(orc_block_size(&o)));
io.println("version:     " + convert.int_to_string(orc_version_major(&o))
  + "." + convert.int_to_string(orc_version_minor(&o)));

if orc_footer_available(&o) {        // uncompressed files only
  let stripes = orc_stripe_count(&o);
  let rows = orc_rows(&o);
  let columns = orc_columns(&o);
  let streams = orc_stream_count(&o);
  io.println("stripes/rows/columns/streams: "
    + convert.int_to_string(stripes.value) + "/"
    + convert.int_to_string(rows.value) + "/"
    + convert.int_to_string(columns.value) + "/"
    + convert.int_to_string(streams.value));

  let kind = orc_column_kind(&o, 0);            // root column
  io.println("root column: " + orc_column_kind_name(kind.value));
  let name = orc_column_field_name(&o, 0, 0);   // first root field
  if name.is_ok {
    io.println("first field: " + name.value);
  }
  let s0 = orc_stripe_offset(&o, 0);
  let st0 = orc_stream_kind(&o, 0, 0);
  io.println("stripe 0 at " + convert.int_to_string(s0.value)
    + ", first stream " + orc_stream_kind_name(st0.value));
}
```

## API summary

| Group | Functions |
|---|---|
| Parse | `orc_parse` |
| Postscript | `orc_file_length`, `orc_postscript_offset`, `orc_postscript_length`, `orc_footer_offset`, `orc_compression`, `orc_compression_name`, `orc_block_size`, `orc_version_count`, `orc_version_part`, `orc_version_major`, `orc_version_minor`, `orc_writer_version`, `orc_writer_version_name`, `orc_footer_length`, `orc_metadata_length`, `orc_footer_available` |
| Footer | `orc_header_length`, `orc_content_length`, `orc_row_index_stride`, `orc_rows`, `orc_footer_writer_version`, `orc_stripe_count`, `orc_stripe_offset`, `orc_stripe_index_length`, `orc_stripe_data_length`, `orc_stripe_footer_length`, `orc_stripe_rows` |
| Type tree | `orc_columns`, `orc_column_kind`, `orc_column_kind_name`, `orc_column_field_count`, `orc_column_field_name`, `orc_column_subtype_count`, `orc_column_subtype`, `orc_column_max_length`, `orc_column_precision`, `orc_column_scale` |
| Statistics | `orc_stats_count`, `orc_column_has_stats`, `orc_stripe_stats_count`, `orc_stripe_stats_cols` |
| Streams | `orc_stream_count`, `orc_stripe_stream_count`, `orc_stream_kind`, `orc_stream_kind_name`, `orc_stream_column`, `orc_stream_offset`, `orc_stream_length` |

## Error model

Every fallible function returns `Result[..., Str]` with deterministic
messages prefixed `orc: `. Parse failures cover bad magic, postscript
bounds, unsupported compression kinds, footer/metadata length overflows,
truncated or overlong or overflowing varints, invalid field numbers and
wire types, out-of-bounds field lengths, non-printable field names,
type-tree violations (subtype ids, struct field counts), stripes extending
past the buffer and stream columns out of range. Protobuf failures carry
the absolute byte offset of the failure. Footer-derived accessors report
`orc: footer not available (compressed file)` for compressed files and
index-specific out-of-range errors otherwise. See SPEC.md §8 for the exact
catalog.

## Limitations

* Metadata only: column data, indexes, bloom filters and dictionary
  streams are neither parsed nor validated.
* No decompression: the footer, metadata and stripe footers are decoded
  only when the postscript declares compression `NONE`. For `ZLIB`,
  `SNAPPY`, `LZ4` and `ZSTD` files, `orc_parse` validates the postscript
  and exposes compression/version/block-size information, but
  `orc_footer_available` is false and footer-derived accessors return an
  error.
* The whole file buffer (through the last stripe footer) is expected; a
  prefix that omits stripe footers is rejected with
  `orc: stripe extends past end of buffer (stripe=N)`.
* Statistics presence is positional: footer statistics entry `i` is
  attributed to column `i` (ORC stores entries in column order).
* Stream offsets are synthesized from the running total of stream lengths
  because ORC streams store only lengths.
* Field names must be printable ASCII (`0x20..0x7E`); UTF-8 names are
  rejected.
* Encryption and column-encoding fields are skipped as unknown fields.

## License

MIT OR Apache-2.0. See the package headers and the repository LICENSE
files.
