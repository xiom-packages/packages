# xiom.dbase -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.dbase`, version `0.1.0`).
Module: `src/dbase.xi` (`module xiom.dbase`).
Depends on `xiom.std` (`xiom.string`: `byte_at`, `str_trim`; `Str::from_utf8`
is a compiler builtin). Tests additionally use `xiom.test`, `xiom.io` and
`xiom.string.compare`.

## 1. Scope

A pure-XIOM (no FFI) structural codec for dBASE III/III+ (and the documented
Visual FoxPro `0x30` header shape) tables:

- `dbase_parse` validates a buffer and returns a `DbaseTable` of flat
  parallel vectors: header scalars, one element per field for
  names/types/lengths/decimals/addresses/offsets, one element per record for
  record offsets/spans;
- O(1) header and descriptor readers (`dbase_version`, `dbase_last_update`,
  `dbase_record_count`, `dbase_header_size`, `dbase_record_size`,
  `dbase_field_count`, `dbase_field_name`, `dbase_field_type`,
  `dbase_field_length`, `dbase_field_decimals`, `dbase_field_address`,
  `dbase_field_offset`, `dbase_record_offset`, `dbase_record_span`);
- record/field byte copiers out of the parse buffer
  (`dbase_record_bytes`, `dbase_field_bytes`) plus the typed C/N accessors
  (`dbase_field_text`, `dbase_field_number`);
- `dbase_build` writes a canonical table from descriptors + records.

The record area is fixed-size: every record occupies exactly `record_size`
bytes and stays in the caller's buffer.

## 2. Non-goals

- **No memo (`.dbt`/`.fpt`) access.** `M` fields are 10-byte pointer values;
  the pointed-to blocks are never read. The `0x83` version is accepted as a
  header shape only.
- **No index files** (`.ndx`, `.idx`, `.cdx`) and no file I/O: the API is
  buffer-in / buffer-out.
- **No code-page conversion** (no `0x30` language-driver byte, no `.cpg`
  handling); text is returned as raw bytes.
- **No typed value conversion**: `D`/`L`/`F` fields are not decoded;
  `dbase_field_number` returns validated text, never a `Float64`/`Int`.
- **No record deletion semantics**: the `0x20`/`0x2A` flag is part of the
  record span and is not reported or filtered.
- **No append/update/delete, no streaming**, no multi-table work areas.
- **No support for variable-length (VFP nullable/varchar) records**, and no
  `0x30` backlink field (bytes 28..31 are reserved and ignored).
- No FFI, no registry integration, no thread safety.

## 3. Byte layout

### 3.1 Table header (32 bytes, little-endian numerics)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 1 | version | Required; `0x03` dBASE III, `0x83` dBASE III+ with memo, `0x30` Visual FoxPro. |
| 1 | 1 | last update YY | Stored verbatim; not interpreted (packed accessor `y*10000+m*100+d`). |
| 2 | 1 | last update MM | Stored verbatim; not interpreted. |
| 3 | 1 | last update DD | Stored verbatim; not interpreted. |
| 4 | 4 | record count | LE32, `>= 0`. Drives the record-area bound check. |
| 8 | 2 | header size | LE16; includes the `0x0D` terminator; `>= 33` and `(header_size - 33) % 32 == 0`. |
| 10 | 2 | record size | LE16; must equal `1 + sum(field lengths)`. |
| 12 | 20 | reserved | Ignored on parse; `dbase_build` writes zero. |

### 3.2 Field descriptors (32 bytes each)

With `N = (header_size - 33) / 32`, descriptor `i` starts at
`32 + i * 32`, followed by the `0x0D` terminator at `header_size - 1`.

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 11 | name | NUL-padded; 1..11 bytes; first byte `A-Z`; later bytes `A-Z`, `0-9`, `_`. Bytes after the first NUL are ignored. |
| 11 | 1 | type | One of `C` (67), `N` (78), `D` (68), `L` (76), `M` (77), `F` (70). Required. |
| 12 | 4 | field address | LE32; preserved as parsed and exposed by `dbase_field_address`; never used to locate data. |
| 16 | 1 | length | `0..255`; summed into the record-size equation. |
| 17 | 1 | decimals | `0..255`; stored, not interpreted. |
| 18 | 14 | reserved | Ignored on parse; `dbase_build` writes zero. |

Field `i` occupies `lengths[i]` bytes inside a record starting at
`offsets[i] = 1 + sum(lengths[0..i])`; `offsets` is stored in the table so
the accessors are O(1) after the parse.

### 3.3 Record area

- Record `r` (`0 <= r < record_count`) starts at `header_size + r *
  record_size` and spans `record_size` bytes; `record_offsets[r]` and
  `record_spans[r]` mirror those values as parallel vectors.
- Byte 0 of every record is the deletion flag (`0x20` active, `0x2A`
  deleted); it is preserved in the span and not interpreted. `offsets[0]`
  is therefore always `1` for a non-empty table.
- The parse requires `data.len() >= header_size + record_count * record_size`
  -> `Err("dbase: truncated records")` otherwise. Bytes after the record
  area (for example the legacy `0x1A` EOF mark) are ignored.
- `dbase_build` writes all records as active (`0x20`), each cell verbatim
  followed by ASCII spaces up to its field length, and emits no `0x1A` mark.

## 4. Validation order

`dbase_parse` (first failure wins):

1. `data.len() < 32` -> `dbase: truncated header`.
2. version not in {3, 131, 48} -> `dbase: unsupported version`.
3. `header_size < 33` -> `dbase: bad header size`.
4. `header_size > data.len()` -> `dbase: truncated header`.
5. byte at `header_size - 1` != `0x0D` -> `dbase: missing terminator`.
6. `(header_size - 33) % 32 != 0` -> `dbase: bad header size`.
7. per descriptor, in order: name -> `dbase: bad field name`; type byte ->
   `dbase: bad field type`.
8. `record_size != 1 + sum(lengths)` -> `dbase: bad record size`.
9. `header_size + record_count * record_size > data.len()` ->
   `dbase: truncated records`.

`dbase_build` (first failure wins):

1. version -> `dbase: unsupported version`.
2. any last-update byte outside `0..255` -> `dbase: bad date`.
3. `names.len() != types.len() != lengths.len() != decimals.len()` ->
   `dbase: descriptor count mismatch`.
4. `32 + 32 * n + 1 > 65535` -> `dbase: bad header size`.
5. per descriptor: name -> `dbase: bad field name`; type ->
   `dbase: bad field type`; length outside `0..255` -> `dbase: bad field
   length`; decimals outside `0..255` -> `dbase: bad field decimals`.
6. `1 + sum(lengths) > 65535` -> `dbase: bad record size`.
7. per record: cell count != `n` -> `dbase: field count mismatch`; a cell
   longer than its field -> `dbase: field too long`.

## 5. API signatures

```xi
pub type DbaseTable = {
  version: Int; last_update_y: Int; last_update_m: Int; last_update_d: Int;
  record_count: Int; header_size: Int; record_size: Int;
  names: Vec[Str]; types: Vec[Int]; lengths: Vec[Int]; decimals: Vec[Int];
  addresses: Vec[Int]; offsets: Vec[Int];
  record_offsets: Vec[Int]; record_spans: Vec[Int];
}

pub fn dbase_parse(data: &Vec[UInt8]) -> Result[DbaseTable, Str]
pub fn dbase_version(t: &DbaseTable) -> Int
pub fn dbase_last_update(t: &DbaseTable) -> Int
pub fn dbase_record_count(t: &DbaseTable) -> Int
pub fn dbase_header_size(t: &DbaseTable) -> Int
pub fn dbase_record_size(t: &DbaseTable) -> Int
pub fn dbase_field_count(t: &DbaseTable) -> Int
pub fn dbase_field_name(t: &DbaseTable, i: Int) -> Str
pub fn dbase_field_type(t: &DbaseTable, i: Int) -> Int
pub fn dbase_field_length(t: &DbaseTable, i: Int) -> Int
pub fn dbase_field_decimals(t: &DbaseTable, i: Int) -> Int
pub fn dbase_field_address(t: &DbaseTable, i: Int) -> Int
pub fn dbase_field_offset(t: &DbaseTable, i: Int) -> Int
pub fn dbase_record_offset(t: &DbaseTable, r: Int) -> Int
pub fn dbase_record_span(t: &DbaseTable, r: Int) -> Int
pub fn dbase_record_bytes(data: &Vec[UInt8], t: &DbaseTable, r: Int) -> Result[Vec[UInt8], Str]
pub fn dbase_field_bytes(data: &Vec[UInt8], t: &DbaseTable, r: Int, f: Int) -> Result[Vec[UInt8], Str]
pub fn dbase_field_text(data: &Vec[UInt8], t: &DbaseTable, r: Int, f: Int) -> Result[Str, Str]
pub fn dbase_field_number(data: &Vec[UInt8], t: &DbaseTable, r: Int, f: Int) -> Result[Str, Str]
pub fn dbase_build(t: &DbaseTable, records: &Vec[Vec[Str]]) -> Result[Vec[UInt8], Str]
```

## 6. Semantics of the accessors

- **Scalar readers** (`dbase_version`, `dbase_last_update`,
  `dbase_record_count`, `dbase_header_size`, `dbase_record_size`) are O(1)
  and infallible.
- **Descriptor readers** guard their own vector: `dbase_field_name` returns
  `""`, and the `Int` readers return `0`, for `i < 0` or `i >=` the length
  of that particular vector.
- **`dbase_field_count`** is `min(names.len(), types.len(), lengths.len(),
  decimals.len(), addresses.len(), offsets.len())`, so index-based field
  access is safe even for a hand-built table whose parallel vectors drifted.
- **`dbase_record_offset(t, r)`** returns `-1` when `r < 0` or
  `r >= dbase_record_count`. When `record_offsets.len() == record_count` the
  stored value is returned; otherwise it falls back to
  `header_size + r * record_size` (hand-built tables need no span vectors).
- **`dbase_record_span(t, r)`** returns `0` when `r` is out of range,
  otherwise `record_spans[r]` when intact, else `record_size`.
- **`dbase_record_bytes`** copies the whole span (deletion flag included) and
  reports `dbase: record out of range` / `dbase: truncated data`.
- **`dbase_field_bytes(data, t, r, f)`** checks `f` first (`dbase: field out
  of range`), then `r` (`dbase: record out of range`), then the buffer bound
  (`dbase: truncated data`). Bytes are copied verbatim; a zero-length field
  yields an empty `Ok`.
- **`dbase_field_text`** requires type `C` (`dbase: field type mismatch`
  otherwise) and returns the field bytes as a `Str` with padding included
  (use `xiom.string.str_trim` for a trimmed view).
- **`dbase_field_number`** requires type `N`; it trims the field with
  `xiom.string.str_trim` and accepts exactly `[+-]?digits(.digits)?` --
  optional sign, at least one digit, and a fractional part that has digits
  on both sides of a single `.`. The trimmed text is returned unchanged
  (never parsed or rounded); malformed text is
  `dbase: bad numeric text`.
- **`dbase_build`** derives header size, record size and record count from
  its arguments; the matching `DbaseTable` fields are ignored. Version and
  last-update bytes are copied, descriptor names/types/lengths/decimals are
  written in order, address words and reserved bytes are zeroed. An empty
  `records` vector builds a header-only table.

## 7. Error string catalog

| Condition | Error text |
|---|---|
| Buffer < 32 bytes, or `header_size` past the buffer | `dbase: truncated header` |
| Version byte not `0x03`/`0x83`/`0x30` | `dbase: unsupported version` |
| `header_size < 33`, misaligned descriptor count, or build header > 65535 | `dbase: bad header size` |
| Byte `header_size - 1` not `0x0D` | `dbase: missing terminator` |
| Descriptor name empty/long/bad charset | `dbase: bad field name` |
| Type byte not in `C N D L M F` | `dbase: bad field type` |
| `record_size != 1 + sum(lengths)`, or build record > 65535 | `dbase: bad record size` |
| `header_size + record_count * record_size > data.len()` | `dbase: truncated records` |
| Field index out of range | `dbase: field out of range` |
| Record index out of range | `dbase: record out of range` |
| Accessed range past the supplied buffer | `dbase: truncated data` |
| Typed accessor on the wrong type byte | `dbase: field type mismatch` |
| N text not `[+-]?digits(.digits)?` after trimming | `dbase: bad numeric text` |
| Build last-update byte outside `0..255` | `dbase: bad date` |
| Build descriptor vectors differ in length | `dbase: descriptor count mismatch` |
| Build length byte outside `0..255` | `dbase: bad field length` |
| Build decimals byte outside `0..255` | `dbase: bad field decimals` |
| Build record does not have one cell per field | `dbase: field count mismatch` |
| Build cell longer than its field | `dbase: field too long` |

## 8. Complexity

| Operation | Complexity |
|---|---|
| `dbase_parse` | O(data bytes + fields + records) |
| Scalar and descriptor readers, `dbase_field_count` | O(1) |
| `dbase_record_offset` / `dbase_record_span` | O(1) |
| `dbase_field_bytes` | O(field length) |
| `dbase_record_bytes` | O(record size) |
| `dbase_field_text` / `dbase_field_number` | O(field length) |
| `dbase_build` | O(fields + records * record size) |

## 9. Test plan

`tests/test_conformance.xi` (`module dbase_tests`, 25 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check and returns the failure
count). Fixtures are assembled byte by byte so `dbase_parse` is exercised
against bytes the test controls, not only against `dbase_build`. Coverage:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | header + descriptors | version, packed date, counts, sizes, names, types, lengths, decimals, address |
| t2 | little-endian | LE16/LE32 decode pinned through header/record size and record count |
| t3 | record spans | offsets 129/146, span 17, `-1`/`0` out of range, first record byte `0x20` |
| t4 | field offsets | `1/6/9` from the deletion-flag rule; out of range `0` |
| t5 | raw fields | all six fixture cells returned verbatim (padding included) |
| t6 | field bounds | field/record range errors and truncated-buffer error |
| t7 | record bytes | exact span copy plus range/truncation errors |
| t8 | C accessor | padded text; mismatch on N/D; range and record errors |
| t9 | N accessor | `" 36"` -> `"36"`, `"  7"` -> `"7"`; mismatch on C/D |
| t10 | N accepted forms | `0`, `-12`, `+3.5`, `3.14`, `0007`, leading space; text preserved |
| t11 | N rejected forms | empty, `abc`, `1.2.3`, `1.`, `.5`, `-`, `+`, `1e3`, internal space |
| t12 | parse head errors | short buffer, two bad versions, `header_size` 32, misaligned 34, oversized 258 |
| t13 | terminator | byte `header_size - 1` must be `0x0D` |
| t14 | name charset | empty, digit-first, lowercase, `-`, byte 128 rejected |
| t15 | type byte | `X`, `0x00`, `0xFF` rejected |
| t16 | record equation | 18 and 0 rejected; count 3 -> truncated; count 1 ignores trailing record bytes |
| t17 | trailing bytes | `0x1A` after the record area tolerated, offsets unchanged |
| t18 | degenerate tables | zero fields with 3 records; zero fields/zero records; build round-trip |
| t19 | build layout | exact 65-byte header+descriptor for one field (every byte pinned) |
| t20 | byte round-trip | parse -> extract records -> build == fixture bytes |
| t21 | cell padding | short cells space-padded; parse-back sees `"36 "` and `"Ada  "` |
| t22 | builder errors | descriptor mismatch, name/type/length/decimals/date/version, cell count, cell too long, header/record size overflow |
| t23 | drifted vectors | `field_count` min, per-vector guards, computed record offset/span fallback |
| t24 | name limits | 11-byte name fits and round-trips; 12-byte and `_`-first rejected; `F1_2` accepted |
| t25 | version variants | `0x83` and `0x30` parse; `0x30` builds and reads back |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.dbase
```

Last verified: compiler 0.61.3,
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## 10. Known limitations

- Memo (`.dbt`), index (`.ndx`/`.idx`) and code-page (`.cpg`) files are out
  of scope; `M` fields are pointer text and text bytes are never recoded.
- `dbase_build` canonicalizes: address words and reserved bytes are zero, all
  records are active, cells are space-padded on the right and no `0x1A` EOF
  mark is written. Parse -> build is not byte-identical for a source file
  that stored non-zero address words or a `0x1A` mark (build -> parse ->
  build is byte-stable).
- Field lengths are bytes, not characters; text access is raw and
  encoding-agnostic.
- The header/record size fields are 16-bit: at most 2046 descriptors
  (header `<= 65535`) and `record_size <= 65535`.
- `dbase_field_number` validates text but does not parse it, so no precision
  is lost or invented (no `Vec[Float64]` is used anywhere).
- Record deletion flags are preserved in spans but not interpreted; deleted
  records are still indexed and accessible.
- Whole-buffer API: a very large table and every copied payload live in
  memory. Plain value types only; not thread-safe.

## 11. Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_table`,
  `_err_table`, `_ok_bytes`, `_err_bytes`, `_ok_str`, `_err_str`; every other
  function returns through one of them.
- Every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8 values
  are never compared against Int constants without widening.
- Str values read from `Vec[Str]` fields are bound to typed locals and never
  compared with `==` (BUG 17); the module performs no string equality at all.
- All `&mut Vec[UInt8]` calls pass `&mut` at the call site, and nested
  helpers receive the existing reference (tar precedent).
- Accessors and the builder verify parallel-vector lengths before indexing,
  so a hand-built `DbaseTable` with drifted vectors cannot read out of
  bounds; `dbase_field_count` is the safe maximum.
- The test suite binds every `&` argument to a local (never
  `&result.value`, a struct field or a call result), following the
  `docs/repro/struct-field-vec` findings.
