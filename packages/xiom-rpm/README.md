# xiom.rpm

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM, read-only parser for the RPM package lead and the
> generic RPM header structure: magic/lead fields, index entries, tag lookup
> for the common metadata tags.
> **Deps:** `xiom.std` only (`xiom.string`; tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## What it is

`xiom.rpm` reads the structural layers every RPM file starts with:

- `rpm_parse` parses the 96-byte program lead, validates and skips the
  signature header and decodes the main header into an `RpmPackage`.
- `rpm_parse_lead` parses the lead alone (version, type, archnum, the
  66-byte name field, osnum, signature_type).
- `rpm_parse_header` parses one header structure at any absolute offset:
  the 4-byte magic word `8E AD E8 01`, the 4 reserved bytes, the
  big-endian index-entry count and data-store size, every 16-byte index
  entry (tag, type, offset, count) and the data store.
- `rpm_header_tag_str` / `rpm_header_tag_int` look tags up and render the
  documented types: `NULL` (0), `CHAR` (1), `INT32` (4, sign-extended),
  `STRING` (6) and `STRING_ARRAY` (8, rendered as its first element).
- `rpm_get_name` / `rpm_get_version` / `rpm_get_release` / `rpm_get_summary`
  / `rpm_get_license` / `rpm_get_group` / `rpm_get_os` / `rpm_get_arch` /
  `rpm_get_payload_compressor` / `rpm_get_buildtime` read the common tags
  from a parsed package.
- `rpm_validate` runs the same structural walk plus per-entry bounds and
  NUL checks and returns `Ok(())` or the documented `Err` string.

Read-only: nothing is ever written, and the payload (compressed cpio
archive) is not touched. See SPEC.md for the byte-level layout tables,
validation order, error catalog and the test plan.

## API

All functions are free functions in module `xiom.rpm`.

| Function | Returns | Description |
|---|---|---|
| `rpm_is_rpm(data)` | `Bool` | Four-byte lead magic `ED AB EE DB` probe. |
| `rpm_parse_lead(data)` | `Result[RpmLead, Str]` | Parse the 96-byte lead at offset 0. |
| `rpm_parse_header(data, off)` | `Result[RpmHeader, Str]` | Parse one header structure at `off`. |
| `rpm_parse(data)` | `Result[RpmPackage, Str]` | Lead + signature header skip + main header. |
| `rpm_validate(data)` | `Result[Unit, Str]` | Structural + entry-bounds validation. |
| `rpm_lead_arch_name(archnum)` | `Str` | Canonical arch family name (legacy lead number). |
| `rpm_lead_type_name(ptype)` | `Str` | `"binary"`, `"source"` or `"unknown"`. |
| `rpm_lead_os_name(osnum)` | `Str` | `"linux"` or `"unknown"`. |
| `rpm_header_count(h)` | `Int` | Number of index entries; `-1` on tags-vector drift. |
| `rpm_header_store_len(h)` | `Int` | Data-store size in bytes. |
| `rpm_header_entry_tag/type/offset/count(h, i)` | `Int` | One index entry field; `-1` out of range. |
| `rpm_header_find(h, tag)` | `Int` | Index of the first entry with `tag`; `-1` absent. |
| `rpm_header_has_tag(h, tag)` | `Bool` | Entry presence. |
| `rpm_header_tag_type(h, tag)` | `Int` | `RPM_TYPE_*` or `-1`. |
| `rpm_header_tag_str(h, tag)` | `Str` | STRING/STRING_ARRAY-first-element; `""` otherwise. Compare with `str_compare`. |
| `rpm_header_tag_int(h, tag)` | `Int` | INT32 (signed) / CHAR first byte; `-1` otherwise. |
| `rpm_header_tag_str_array_count(h, tag)` | `Int` | STRING_ARRAY element count; `-1` otherwise. |
| `rpm_header_tag_str_array_at(h, tag, idx)` | `Str` | STRING_ARRAY element; `""` out of range. |
| `rpm_get_*` | `Str`/`Int` | The ten common tags on a parsed package. |

`RpmLead = { major: Int; minor: Int; ptype: Int; archnum: Int; name: Str;
osnum: Int; signature_type: Int; }`.

`RpmHeader = { tags: Vec[Int]; store: Vec[UInt8]; }` -- `tags` is flat with
stride 4: entry `i` owns `tags[i*4 .. i*4+3]` in the order tag, type, offset,
count. `store` is a copy of the header data store; entry offsets are
relative to it.

`RpmPackage = { major; minor; ptype; archnum; lead_name: Str; osnum;
signature_type; header: RpmHeader; }` -- the lead fields plus the decoded
main header.

## Usage

```xi
use xiom.rpm;
use xiom.io;
use xiom.convert;

// `data` is a whole .rpm file already in memory.
if rpm_is_rpm(&data) {
  match rpm_parse(&data) {
    Ok(p) => {
      io.println("name:    " + rpm_get_name(&p));      // e.g. zlib
      io.println("version: " + rpm_get_version(&p));   // e.g. 1.3.1
      io.println("release: " + rpm_get_release(&p));   // e.g. 2.fc40
      io.println("arch:    " + rpm_get_arch(&p));      // e.g. x86_64
      io.println("summary: " + rpm_get_summary(&p));
      io.println("license: " + rpm_get_license(&p));
      io.println("payload: " + rpm_get_payload_compressor(&p)); // e.g. zstd
      io.println("built:   " + convert.int_to_string(rpm_get_buildtime(&p)));
    },
    Err(e) => { io.println("parse error: " + e); },
  },
} else {
  io.println("not an rpm file");
}
```

## Header layouts

Lead (96 bytes):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `ED AB EE DB` |
| 4 | 1 | major version |
| 5 | 1 | minor version |
| 6 | 2 | type (0 binary, 1 source), big-endian |
| 8 | 2 | archnum, big-endian (legacy; often 1) |
| 10 | 66 | name, NUL-terminated or full |
| 76 | 2 | osnum, big-endian (1 = linux) |
| 78 | 2 | signature_type, big-endian (5 = header signature) |
| 80 | 16 | reserved (skipped) |

Header structure (at offset 96 for the signature header, then immediately
after it for the main header):

| Offset | Size | Field |
|---|---|---|
| 0 | 3 | magic `8E AD E8` |
| 3 | 1 | version `01` |
| 4 | 4 | reserved (skipped, not required to be zero) |
| 8 | 4 | index-entry count, big-endian |
| 12 | 4 | data-store size in bytes, big-endian |
| 16 | `count` x 16 | index entries |
| 16 + `count`*16 | `store_size` | data store |

Each index entry: tag, type, offset, count -- four big-endian 32-bit words.
`offset` is relative to the store; for CHAR/INT32/STRING it is one value,
and `count` is the number of elements (bytes, 32-bit ints, strings).

## Errors

Lead: `rpm: truncated lead`, `rpm: bad lead magic`.

Header: `rpm: truncated header`, `rpm: bad header magic`,
`rpm: bad header version`, `rpm: truncated index`, `rpm: truncated store`.

Whole file: `rpm: bad signature header` (the header at offset 96).

Validation: the above plus `rpm: bad index entry`, `rpm: tag out of range`,
`rpm: string missing NUL`.

See SPEC.md for the exact condition behind every message.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.rpm
```

Expected: the namespace check passes, 19 `[PASS]` lines, and a final
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Read-only.** No RPM writing, no re-serialization, no header editing.
- **Structural layers only.** The main-header payload (a compressed cpio
  archive) is not located, decompressed or parsed; the file digest, GPG
  signatures and other signature-header tags are not verified or decoded.
- **Five tag types.** NULL(0), CHAR(1), INT32(4), STRING(6) and
  STRING_ARRAY(8). Real RPM files also carry BIN(7), INT16(3), INT8(5) and
  I18NSTRING(9) entries: they are parsed structurally and `rpm_validate`
  accepts them (offset-bounded only), but the typed accessors return `-1` /
  `""` for them. In particular modern RPM files usually store SUMMARY(1004)
  and GROUP(1016) as I18NSTRING(9), so `rpm_get_summary` / `rpm_get_group`
  return `""` on those files.
- **No payload offset.** The end of the main header is known to the parser
  internally but is not exposed; callers who need the payload start can
  re-walk the structures.
- **String accessors are lenient.** `rpm_header_tag_str` returns an
  unterminated string up to the end of the store; `rpm_validate` is the
  strict path and reports `rpm: string missing NUL`.
- **Strings are not UTF-8-validated** and may contain arbitrary non-NUL
  bytes.
- **Header version 1 only.** The 4 reserved bytes are skipped, not checked
  for zero; the 16 trailing lead bytes are skipped too.
- **`archnum` is legacy.** Many writers set it to 1 for the whole x86
  family; use the ARCH tag (1022) for the real architecture.
- **No dependency, file-list or scriptlet decoding.** Only the ten common
  scalar tags get named getters.
- **In-memory only.** The API operates on whole `Vec[UInt8]` buffers; the
  header data store is copied out of the source buffer. Not thread-safe; all
  values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
