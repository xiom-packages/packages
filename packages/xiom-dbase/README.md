# xiom.dbase

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** dBASE III/III+ / Visual FoxPro table header codec: parse and
> build `.dbf` headers, field descriptors and the fixed-size record area.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_trim` and
> `xiom.string.byte_at`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.dbase` reads and writes the structural part of dBASE tables: the
32-byte table header, the 32-byte field descriptors terminated by `0x0D`,
and the fixed-size record area. `dbase_parse` validates the header,
descriptor terminator, descriptor count implied by the header size, every
field name and type, the `record_size == 1 + sum(field lengths)` equation and
the record area bounds, then returns a `DbaseTable` of flat parallel vectors.
Record bytes stay in the caller's buffer: `record_offsets`/`record_spans`
locate every record, and the field accessors copy bytes out of the parse
buffer. `dbase_build` writes a canonical table (descriptor address words
zeroed, records space-padded, no `0x1A` EOF mark).

The codec never touches the filesystem, never follows memo (`.dbt`) or index
files, and never converts code pages: it is a pure structural codec over
in-memory `Vec[UInt8]` buffers. See `SPEC.md` for the byte layout, validation
order, error catalog and test plan.

## Install

Not yet published. Consume it from this repository with the package harness:

```
& .\scripts\port.ps1 -Package xiom.dbase
```

Once published, the manifest name is `xiom.dbase` version `0.1.0`.

## API

All functions are free functions in module `xiom.dbase`.

| Function | Returns | Description |
|---|---|---|
| `dbase_parse(data)` | `Result[DbaseTable, Str]` | Validate and index a table: header + descriptors + record spans. |
| `dbase_version(t)` | `Int` | Version byte (`0x03`, `0x83`, `0x30`). |
| `dbase_last_update(t)` | `Int` | Last-update date packed as `y * 10000 + m * 100 + d`. |
| `dbase_record_count(t)` | `Int` | Header record count (LE32). |
| `dbase_header_size(t)` | `Int` | Header size in bytes (LE16), terminator included. |
| `dbase_record_size(t)` | `Int` | Record size in bytes (LE16), deletion flag included. |
| `dbase_field_count(t)` | `Int` | Safe field count (minimum length of the parallel descriptor vectors). |
| `dbase_field_name(t, i)` | `Str` | Field name; `""` out of range. |
| `dbase_field_type(t, i)` | `Int` | ASCII type byte (C 67, N 78, D 68, L 76, M 77, F 70); `0` out of range. |
| `dbase_field_length(t, i)` | `Int` | Field length in bytes; `0` out of range. |
| `dbase_field_decimals(t, i)` | `Int` | Declared decimal count; `0` out of range. |
| `dbase_field_address(t, i)` | `Int` | Descriptor address word (LE32, preserved as parsed); `0` out of range. |
| `dbase_field_offset(t, i)` | `Int` | Byte offset of the field within a record, deletion flag included; `0` out of range. |
| `dbase_record_offset(t, r)` | `Int` | Absolute offset of record `r` in the parse buffer; `-1` out of range. |
| `dbase_record_span(t, r)` | `Int` | Byte span of record `r` (deletion flag included); `0` out of range. |
| `dbase_record_bytes(data, t, r)` | `Result[Vec[UInt8], Str]` | Copy the whole record span out of `data`. |
| `dbase_field_bytes(data, t, r, f)` | `Result[Vec[UInt8], Str]` | Copy the raw bytes of one field out of `data`. |
| `dbase_field_text(data, t, r, f)` | `Result[Str, Str]` | Raw text of a C field (padding included). |
| `dbase_field_number(data, t, r, f)` | `Result[Str, Str]` | Trimmed, validated numeric text of an N field. |
| `dbase_build(t, records)` | `Result[Vec[UInt8], Str]` | Build a canonical table from descriptors + records. |

`DbaseTable = { version; last_update_y; last_update_m; last_update_d;
record_count; header_size; record_size; names: Vec[Str]; types: Vec[Int];
lengths: Vec[Int]; decimals: Vec[Int]; addresses: Vec[Int]; offsets:
Vec[Int]; record_offsets: Vec[Int]; record_spans: Vec[Int]; }` -- one element
per field for the descriptor columns and `offsets`, one element per record
for `record_offsets`/`record_spans`. No `Vec` of structs is used.

## Quick start

Reading a table (`data` is a `.dbf` buffer the caller already loaded):

```xi
use xiom.dbase;
use xiom.io;
use xiom.convert;

fn report(data: &Vec[UInt8]) {
  let pr = dbase_parse(data);
  if !pr.is_ok {
    io.println("error: " + pr.error);
    return;
  }
  let t = pr.value;
  io.println("fields: " + convert.int_to_string(dbase_field_count(&t)));
  io.println("records: " + convert.int_to_string(dbase_record_count(&t)));

  let name = dbase_field_text(data, &t, 0, 0);
  if name.is_ok {
    let s: Str = name.value;
    io.println("first cell: " + s);
  }
  let age = dbase_field_number(data, &t, 0, 1);
  match age {
    Ok(v) => { io.println("age text: " + v); },
    Err(e) => { io.println("age error: " + e); },
  }
}
```

Building a table from scratch:

```xi
var names = Vec[Str].new();
names.push("NAME");
var types = Vec[Int].new();
types.push(67);                  // C
var lens = Vec[Int].new();
lens.push(10);
var decs = Vec[Int].new();
decs.push(0);
var addresses = Vec[Int].new();
var offsets = Vec[Int].new();
var ro = Vec[Int].new();
var rs = Vec[Int].new();
let t = DbaseTable{
  version: 3;
  last_update_y: 26;
  last_update_m: 9;
  last_update_d: 25;
  record_count: 0;
  header_size: 65;
  record_size: 11;
  names: names;
  types: types;
  lengths: lens;
  decimals: decs;
  addresses: addresses;
  offsets: offsets;
  record_offsets: ro;
  record_spans: rs;
};
var rec = Vec[Str].new();
rec.push("Ada");
var records = Vec[Vec[Str]].new();
records.push(rec);
let built = dbase_build(&t, &records);
```

`dbase_build` recomputes header size, record size and record count, writes
the descriptors in order (address words zeroed), pads short cells with spaces
and writes every record as active (`0x20`).

## Errors

Every failure is an `Err(Str)` with a deterministic `dbase:` message. The
full catalog:

| Message | Condition |
|---|---|
| `dbase: truncated header` | Buffer shorter than 32 bytes, or `header_size` extends past the buffer. |
| `dbase: unsupported version` | Version byte is not `0x03`, `0x83` or `0x30`. |
| `dbase: bad header size` | `header_size < 33`, `(header_size - 33) % 32 != 0`, or a build whose header would exceed 65535 bytes. |
| `dbase: missing terminator` | Byte at `header_size - 1` is not `0x0D`. |
| `dbase: bad field name` | Name empty, longer than 11 bytes, or outside `A-Z 0-9 _` (first byte must be `A-Z`). |
| `dbase: bad field type` | Type byte is not `C`, `N`, `D`, `L`, `M` or `F`. |
| `dbase: bad record size` | `record_size != 1 + sum(field lengths)`, or a build whose record would exceed 65535 bytes. |
| `dbase: truncated records` | Buffer shorter than `header_size + record_count * record_size`. |
| `dbase: field out of range` | Field index negative or >= `dbase_field_count`. |
| `dbase: record out of range` | Record index negative or >= `dbase_record_count`. |
| `dbase: truncated data` | The accessed field/record range does not fit in the supplied buffer. |
| `dbase: field type mismatch` | `dbase_field_text`/`dbase_field_number` called on the wrong type byte. |
| `dbase: bad numeric text` | N text (after trimming) is not `[+-]?digits[.digits]`. |
| `dbase: bad date` | A build last-update byte is outside `0..255`. |
| `dbase: descriptor count mismatch` | The four descriptor vectors of a build input have different lengths. |
| `dbase: bad field length` / `dbase: bad field decimals` | A build descriptor byte is outside `0..255`. |
| `dbase: field count mismatch` | A build record does not have exactly one cell per field. |
| `dbase: field too long` | A build cell is longer than its field length. |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.dbase
```

Expected: the section-4 namespace check passes, 25 `[PASS]` lines,
`xiom.dbase: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`. The main fixtures
are hand-built byte by byte, so `dbase_parse` is exercised independently of
`dbase_build`.

## Limitations

- **No memo files.** `M` fields are surfaced as their 10-byte pointer text
  only; `.dbt`/`.fpt` blocks are never read, and the `0x83` version is
  accepted purely as a header shape.
- **No index files** (`.ndx`, `.idx`, `.cdx`) and no file I/O at all: the
  API works on in-memory buffers.
- **No code-page conversion.** Text is returned as raw bytes; callers that
  need an encoding must convert themselves.
- **No date/logical decoding.** `D` and `L` fields are surfaced as raw field
  bytes or text; `F` fields are not validated as numeric text.
- **Record deletion is not interpreted.** The flag byte (`0x20` active,
  `0x2A` deleted) is part of the record span; the module does not filter or
  report it.
- **Address words are not meaningful.** Parsed values are preserved, but
  `dbase_build` always writes `0` (the canonical file form).
- **Build canonicalizes.** No `0x1A` EOF mark, no preserved descriptor
  address words, cells are space-padded on the right; a build -> parse ->
  build cycle is byte-stable but a parse -> build cycle may differ from a
  non-canonical source file.
- **No append/delete/update.** Whole-table parse and build only; the record
  area size is `header_size + record_count * record_size` bytes at most.
- Not thread-safe; all values are plain value types.

See `SPEC.md` for the full semantics and test matrix. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
