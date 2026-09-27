# xiom.windows -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.windows`, version `0.1.0`).
Module: `src/windows.xi` (`module xiom.windows`).
Depends on `xiom.std`; the library module imports `xiom.string` (for
`str_lower` / `str_compare`). The tests add `xiom.test`, `xiom.io` and
`xiom.string.compare`. No FFI.

## Scope

A pure-XIOM (no FFI) read-only structure parser for Windows Registry hive
files (REGF):

- base block (`regf`, 4096 bytes);
- hbin blocks and their cell lists (allocated and free/deleted cells);
- cell records: nk, vk, sk, lf/lh/li/ri, db;
- value data storage: inline, direct data cells, db big data;
- a BFS walk from the root nk with flat key/value tables;
- accessors, case-insensitive child lookup and path resolution;
- byte-offset-carrying errors for bad signatures, versions, offsets and
  sizes.

## Non-goals

- Hive writes, cell allocation, defragmentation or log replay.
- Interpreting key/value names or REG_* data semantics beyond decoding.
- Security descriptor interpretation (opaque bytes; span validated).
- Streaming: the whole hive is an in-memory `Vec[UInt8]`.
- Negative cell-index arithmetic (only the all-ones sentinel and
  non-negative offsets are handled).
- Recovery of deleted records (they are exposed, not parsed).

## Byte-level layouts implemented

All multi-byte integers are little-endian. Cell offsets inside records
are u32 values relative to the start of the hive bins data (file offset
0x1000).

### Base block (4096 bytes)

| Offset | Size | Field | Handling |
|---|---|---|---|
| 0x00 | 4 | signature `"regf"` | validated |
| 0x04 | 4 | primary sequence number | stored |
| 0x08 | 4 | secondary sequence number | stored; mismatch sets the warning state |
| 0x0C | 8 | last written timestamp | stored raw (u64 two's-complement Int) |
| 0x14 | 4 | major version | must be 1 |
| 0x18 | 4 | minor version | must be 3..5 |
| 0x1C | 4 | file type (0 primary, 1 log, 2 external) | must be 0..2 |
| 0x20 | 4 | file format | must be 1 |
| 0x24 | 4 | root cell offset (hive-bins-relative) | validated (not all-ones, < declared size) |
| 0x28 | 4 | hive bins data size | > 0, multiple of 4096, inside the buffer |
| 0x2C | 4 | cluster factor | stored (pass-through) |
| 0x30 | 64 | file name (UTF-16LE, up to 32 code units) | decoded to UTF-8, stops at the first NUL |
| 0x70 | 4 | checksum | stored, not validated |
| 0x74 | 396 | reserved | not read |

### hbin block

| Offset | Size | Field | Handling |
|---|---|---|---|
| 0x00 | 4 | signature `"hbin"` | validated |
| 0x04 | 4 | offset from first hbin | must equal the running relative offset (monotonic, exact) |
| 0x08 | 4 | size | > 0, multiple of 4096, inside the declared region |
| 0x0C | 8 | reserved | not read |
| 0x14 | 8 | timestamp | stored raw |
| 0x1C | 4 | spare | stored |
| 0x20 | .. | cells | iterated to the hbin end |

The parser accepts hbins larger than 4096 (any multiple of 4096); the
declared hive-bins data size must be consumed exactly by the hbin sizes.

### Cell size field

The first 4 bytes of every cell are a signed size including the 4-byte
size field: **negative = allocated, positive = free (deleted)**; the
absolute value is the cell size. A cell must be at least 8 bytes, a
multiple of 8, and lie entirely inside its hbin. Free cells stay in the
cell table (visible as deleted content) and are never walked.

### nk record (key)

Record data starts 4 bytes after the cell size field.

| Offset | Size | Field |
|---|---|---|
| 0x00 | 2 | signature `"nk"` |
| 0x02 | 2 | flags |
| 0x04 | 8 | last written timestamp |
| 0x0C | 4 | access bits |
| 0x10 | 4 | parent key offset (0xFFFFFFFF for the root) |
| 0x14 | 4 | stable subkey count |
| 0x18 | 4 | volatile subkey count |
| 0x1C | 4 | stable subkey list offset |
| 0x20 | 4 | volatile subkey list offset |
| 0x24 | 4 | value count |
| 0x28 | 4 | value list offset |
| 0x2C | 4 | security cell (sk) offset |
| 0x30 | 4 | class name offset |
| 0x34 | 4 | largest subkey name length |
| 0x38 | 4 | largest subkey class name length |
| 0x3C | 4 | largest value name length |
| 0x40 | 4 | largest value data length |
| 0x44 | 4 | work var |
| 0x48 | 2 | key name length (bytes) |
| 0x4A | 2 | class name length |
| 0x4C | .. | key name bytes |

nk flags bits implemented: 0x0001 VOLATILE, 0x0002 HIVE_EXIT, 0x0004
HIVE_ENTRY (root), 0x0008 NO_DELETE, 0x0010 SYM_LINK, 0x0020 COMP_NAME
(name is compressed ASCII), 0x0040 PREDEF_HANDLE. The fixed part must fit
the cell; the name bytes must fit the cell. A UTF-16 name with an odd
byte length is rejected.

### vk record (value)

| Offset | Size | Field |
|---|---|---|
| 0x00 | 2 | signature `"vk"` |
| 0x02 | 2 | value name length (bytes) |
| 0x04 | 4 | data size; bit 31 set = data stored inline in the data offset field |
| 0x08 | 4 | data offset (or inline data bytes) |
| 0x0C | 4 | data type (REG_*) |
| 0x10 | 2 | flags (bit 0: value name is compressed ASCII) |
| 0x12 | 2 | spare |
| 0x14 | .. | value name bytes |

Data storage classes implemented:

- **inline:** bit 31 of the size field set; the real size (bit 31
  removed) must be 0..4; the bytes are the first `size` bytes of the data
  offset field at vk data offset 0x08.
- **direct:** size 1..16344; the data offset names an allocated cell whose
  data span (`cell + 4`, `size` bytes) fits inside the cell.
- **big data:** size > 16344; the data offset names a `db` cell (see
  below) whose segment list is resolved and every segment validated.
- **empty:** size 0; no data offset validation.

### sk record (security)

| Offset | Size | Field |
|---|---|---|
| 0x00 | 2 | signature `"sk"` |
| 0x02 | 2 | flags (reserved) |
| 0x04 | 4 | flink |
| 0x08 | 4 | blink |
| 0x0C | 4 | reference count |
| 0x10 | 4 | security descriptor size |
| 0x14 | .. | security descriptor bytes (opaque) |

The fixed part and the descriptor span must fit the cell. A key whose
security offset is 0 or 0xFFFFFFFF has no sk cell.

### Subkey lists

All list cells start with a 2-byte signature and a 2-byte entry count.

| Kind | Signature | Entry | Layout |
|---|---|---|---|
| lf | `"lf"` | 8 bytes: offset u32 + name-hash u32 | entries at 0x04 |
| lh | `"lh"` | 8 bytes: offset u32 + name-hash u32 | entries at 0x04 |
| li | `"li"` | 4 bytes: offset u32 | entries at 0x04 |
| ri | `"ri"` | 4 bytes: offset u32 (list cell) | entries at 0x04 |

The fixed part plus all entries must fit the cell. lf/lh/li entries are
resolved as allocated `nk` cells; ri entries are resolved recursively as
lists (depth limit 8). Hash bytes are ignored. The resolved count must
equal the nk's stable count (and volatile count for the volatile list).

### Value lists

A value list cell has no signature: it is an array of `value_count` u32
vk offsets at the cell data start. The fixed array must fit the cell and
every entry is resolved as an allocated `vk` cell.

### db record (big data)

| Offset | Size | Field |
|---|---|---|
| 0x00 | 2 | signature `"db"` |
| 0x02 | 2 | segment count |
| 0x04 | 4 | segment list offset (cell of segment count u32 data-cell offsets) |

Validation: segment count >= 1 and >= ceil(size / 16344); the segment list
cell holds `count` u32 offsets; segments are resolved as allocated cells
with `4 + take <= cell size`, where `take` is `min(16344, remaining)`;
the produced total must equal the value's data size.

### Name decoding

- ASCII/compressed names decode byte by byte; bytes >= 128 and byte 0
  decode to U+FFFD, keeping the result valid UTF-8 and NUL-free.
- UTF-16LE names decode code unit pairs; surrogate pairs encode to
  the proper 4-byte UTF-8 sequence; lone surrogates and code unit 0
  decode to U+FFFD; a trailing odd byte is ignored by the decoder (but
  key/value names with an odd byte length are rejected earlier).
- The base block file name stops at the first zero code unit.
- REG_MULTI_SZ decoding splits on zero code units, drops empty groups,
  and therefore ignores the terminating double NUL.
- `regf_value_str` removes one trailing zero code unit before decoding.

## Validation order

1. `regf_parse`: base block length -> signature -> version -> file type
   -> format -> hive bins data size -> root cell offset (raw) -> file
   name decode (no error) -> sequence mismatch warning.
2. hbin loop: header fits region -> signature -> offset-from-first ->
   size -> per-cell size (alignment, minimum, hbin bound); the region
   must be consumed exactly.
3. Root cell: resolved as an allocated `nk` cell.
4. BFS walk per key: stable subkey list -> volatile subkey list (only
   when count > 0 and the offset is not the all-ones sentinel) -> value
   list -> sk cell.
5. Value data: inline size -> direct cell span -> db indirection.

Checks short-circuit: the first failure is returned, so an early error
masks later ones. No partial hive is returned.

## Error catalog

Structural errors have the form `regf: <reason> at 0x<8 hex digits>`; the
offset is the absolute file offset of the offending field, cell or
record (documented per row). Accessor misuse errors carry no offset.

| Condition | Error text | Offset |
|---|---|---|
| buffer shorter than 4096 bytes | `regf: truncated base block` | 0x00000000 |
| any `"regf"` byte wrong | `regf: bad base block signature` | 0x00000000 |
| major != 1 or minor not 3..5 | `regf: bad version` | 0x00000014 (major/minor field) |
| file type > 2 | `regf: bad file type` | 0x0000001C |
| file format != 1 | `regf: bad file format` | 0x00000020 |
| hive bins size 0, not a 4096 multiple, or past the buffer | `regf: bad hive bins data size` | 0x00000028 |
| root offset all-ones, with bit 31 set, or past the region | `regf: bad root cell offset` | 0x00000024 |
| hbin header does not fit the declared region | `regf: truncated hbin` | hbin offset |
| any `"hbin"` byte wrong | `regf: bad hbin signature` | hbin offset |
| offset-from-first != running relative offset | `regf: bad hbin offset` | hbin offset + 4 |
| hbin size 0, not a 4096 multiple, or past the region | `regf: bad hbin size` | hbin offset + 8 |
| cell header does not fit | `regf: truncated cell` | cell offset |
| cell size < 8, not a multiple of 8, or past the hbin end | `regf: bad cell size` | cell offset |
| referenced offset with bit 31 set/out of range/not a cell start | `regf: bad cell offset` | referencing field |
| referenced cell is free | `regf: cell not allocated` | cell offset |
| referenced cell has the wrong signature | `regf: unexpected cell kind` | cell offset |
| nk fixed part does not fit the cell | `regf: truncated nk record` | cell offset |
| nk name does not fit, or UTF-16 name with odd length | `regf: bad key name length` | nk name-length field |
| sk fixed part does not fit | `regf: bad sk record` | cell offset |
| descriptor span past the sk cell | `regf: bad security descriptor size` | descriptor-size field |
| lf/lh/li/ri fixed part or entries past the cell | `regf: bad subkey list size` | list cell offset |
| subset signature is not lf/lh/li/ri | `regf: bad subkey list` | list cell offset |
| ri nesting deeper than 8 | `regf: ri nesting too deep` | referencing field |
| resolved children count != nk count | `regf: subkey count mismatch` | nk count field |
| value list array past the cell | `regf: bad value list size` | list cell offset |
| vk fixed part does not fit | `regf: truncated vk record` | cell offset |
| vk name does not fit, or UTF-16 name with odd length | `regf: bad value name length` | vk name-length field |
| inline size > 4 | `regf: bad inline data size` | vk size field |
| direct data span past the data cell | `regf: bad value data size` | vk size field |
| db cell shorter than its fixed part | `regf: bad big data record` | db cell offset |
| segment count < 1 or < ceil(size / 16344) | `regf: bad big data segment count` | db segment-count field |
| segment list array past its cell | `regf: bad big data segment list` | list cell offset |
| a segment's bytes do not fit its cell | `regf: bad big data segment size` | segment cell offset |
| segments do not produce the full data size | `regf: bad big data size` | db segment-count field |
| path component has no matching child | `regf: key not found` | -- |
| index negative or past the table | `regf: index out of range` | -- |
| field selector not a `REGF_*_FIELD_*` constant | `regf: bad field selector` | -- |
| `regf_value_dword` on a non-DWORD | `regf: value is not a dword` | -- |
| `regf_value_qword` on a non-QWORD | `regf: value is not a qword` | -- |
| `regf_value_str` on a non-SZ type | `regf: value is not a string` | -- |
| `regf_value_multi_str` on a non-MULTI_SZ type | `regf: value is not a multi string` | -- |

A primary/secondary sequence-number mismatch is **not** an error: the
parse succeeds and `regf_sequence_mismatch` returns true.

## API signatures

All functions are free functions in module `xiom.windows` (no methods):

```xi
pub type RegfHive = { ... flat scalar/vector fields ... }

pub fn regf_parse(data: &Vec[UInt8]) -> Result[RegfHive, Str]

// base block
pub fn regf_primary_sequence(f: &RegfHive) -> Int
pub fn regf_secondary_sequence(f: &RegfHive) -> Int
pub fn regf_sequence_mismatch(f: &RegfHive) -> Bool
pub fn regf_timestamp(f: &RegfHive) -> Int
pub fn regf_version_major(f: &RegfHive) -> Int
pub fn regf_version_minor(f: &RegfHive) -> Int
pub fn regf_file_type(f: &RegfHive) -> Int
pub fn regf_file_format(f: &RegfHive) -> Int
pub fn regf_root_cell_offset(f: &RegfHive) -> Int
pub fn regf_root_offset(f: &RegfHive) -> Int
pub fn regf_hbin_data_size(f: &RegfHive) -> Int
pub fn regf_cluster_factor(f: &RegfHive) -> Int
pub fn regf_checksum(f: &RegfHive) -> Int
pub fn regf_file_name(f: &RegfHive) -> Str

// hbins
pub fn regf_hbin_count(f: &RegfHive) -> Int
pub fn regf_hbin_offset(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_hbin_rel_offset(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_hbin_size(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_hbin_timestamp(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_hbin_spare(f: &RegfHive, i: Int) -> Result[Int, Str]

// cells
pub fn regf_cell_count(f: &RegfHive) -> Int
pub fn regf_cell_offset(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_cell_size(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_cell_allocated(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_cell_kind(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_cell_hbin(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_free_cell_count(f: &RegfHive) -> Int
pub fn regf_deleted_nk_count(f: &RegfHive) -> Int
pub fn regf_cell_index_by_offset(f: &RegfHive, off: Int) -> Int

// keys (BFS walk index)
pub fn regf_key_count(f: &RegfHive) -> Int
pub fn regf_key_name(f: &RegfHive, i: Int) -> Result[Str, Str]
pub fn regf_key_parent(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_key_subkey_count(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_key_subkey(f: &RegfHive, i: Int, j: Int) -> Result[Int, Str]
pub fn regf_key_value_count(f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_key_value(f: &RegfHive, i: Int, j: Int) -> Result[Int, Str]
pub fn regf_key_field(f: &RegfHive, i: Int, field: Int) -> Result[Int, Str]
pub fn regf_key_sk(f: &RegfHive, i: Int, field: Int) -> Result[Int, Str]
pub fn regf_name_equal(a: Str, b: Str) -> Bool
pub fn regf_key_find(f: &RegfHive, i: Int, name: Str) -> Int
pub fn regf_path_resolve(f: &RegfHive, path: Str) -> Result[Int, Str]

// values
pub fn regf_value_count(f: &RegfHive) -> Int
pub fn regf_value_field(f: &RegfHive, i: Int, field: Int) -> Result[Int, Str]
pub fn regf_value_name(f: &RegfHive, i: Int) -> Result[Str, Str]
pub fn regf_value_data(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Vec[UInt8], Str]
pub fn regf_value_dword(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_value_qword(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Int, Str]
pub fn regf_value_str(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Str, Str]
pub fn regf_value_multi_str(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Vec[Str], Str]
```

Selectors: `REGF_KEY_FIELD_*` (22 selectors), `REGF_VALUE_FIELD_*`
(9), `REGF_SK_FIELD_*` (4). Kind tags: `REGF_KIND_*` (nk, vk, sk, lf,
lh, li, ri, db). Data types: `REGF_REG_*` (NONE, SZ, EXPAND_SZ, BINARY,
DWORD, DWORD_BIG_ENDIAN, LINK, MULTI_SZ, RESOURCE_LIST,
FULL_RESOURCE_DESCRIPTOR, RESOURCE_REQUIREMENTS_LIST, QWORD).

Semantics notes:

- `regf_value_dword` accepts REG_DWORD (LE) and REG_DWORD_BIG_ENDIAN
  (BE) with data size exactly 4.
- `regf_value_qword` accepts REG_QWORD with data size exactly 8 and
  returns the raw two's-complement Int.
- `regf_path_resolve`: the first component may name the root itself
  (case-insensitive); empty components from leading/trailing/doubled
  separators are skipped; the empty path resolves to key 0.
- `regf_key_find` returns -1 when absent; comparisons are ASCII
  case-insensitive (via `xiom.string.str_lower` + `str_compare`).

## Complexity

| Operation | Complexity |
|---|---|
| `regf_parse` | O(buffer length) cell scan + O(cells log cells) offset lookups + walk over records |
| cell index lookup | O(log cells) |
| key/value field accessors | O(1) |
| `regf_key_find` / `regf_path_resolve` | O(children * name length) per component |
| `regf_value_data` | O(data size) |

## Test plan

`tests/test_conformance.xi` (`module windows_tests`, 25 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Fixtures are assembled byte by byte in the
test file, independent of `src/windows.xi`. Coverage:

1. the full synthetic hive parses: 6 keys, 6 values, 31 cells, 3 hbins,
   3 free cells;
2. base block scalars (sequence, timestamp, version 1.5, file type,
   format, root offsets, hive bins size, cluster, checksum, name);
3. hbin table (absolute/relative offsets, 4096 and 16384 sizes,
   timestamps, bounds error);
4. cell table (offsets, sizes, allocated flags, kind tags, hbin index,
   binary-search lookup, bounds error);
5. root nk fields through every `REGF_KEY_FIELD_*` selector;
6. key names: ASCII COMP_NAME ("ROOT"), UTF-16LE ("Child"), UTF-16LE
   non-ASCII ("Cafe" with U+00E9), lengths, bounds errors;
7. BFS walk: parent links, subkey/value CSR ranges, bounds errors;
8. remaining key-field selectors and accessor error strings;
9. case-insensitive `regf_key_find` and backslash path resolution
   (root-named first component, trailing separators, missing component);
10. value metadata: sizes, raw offsets, types, inline/big flags, segment
    counts, selector errors;
11. value names (compressed ASCII) and bounds errors;
12. inline DWORD 0x11223344 and its raw bytes in the data-offset field;
13. direct QWORD 0x1122334455667788 little-endian;
14. REG_SZ: 12 raw bytes (UTF-16LE + NUL), text decoded without the
    terminator, type guard;
15. REG_MULTI_SZ: "A" and "B" recovered, trailing empty group dropped,
    type guard;
16. db big data: 16345 bytes reassembled across two segments in order;
17. sk records: offset, reference count, descriptor size, flags;
18. free/deleted cells: allocated flag 0, stale nk tag visible, counts;
19. sequence mismatch is a warning state (parse succeeds, flag set);
20. malformed base block: truncation, signature, major/minor version,
    file type, format, hive-bins size (0, non-multiple, past buffer),
    root offset (all-ones, past region);
21. malformed hbin: signature, non-monotonic offset, zero/non-multiple
    size;
22. malformed cell sizes: zero, non-multiple of 8, past the hbin end;
23. subkey list errors: lf span, nk/list count mismatch, wrong list kind,
    free-cell child, wrong child kind;
24. value data errors: inline size > 4, out-of-range offset, free data
    cell, data span past the cell, db segment count;
25. accessor error strings (index out of range, bad field selector).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.windows
```

Last verified: compiler 0.61.3,
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)` (two consecutive
runs).

## Known limitations

- **Structure only.** No semantic interpretation of names, no
  transaction-log replay, no cell allocation, no write path.
- **Negative cell offsets are rejected.** Only the all-ones sentinel and
  non-negative offsets are understood; a negative (bit-31) cell index in
  any field is `regf: bad cell offset`.
- **Free cells are not parsed.** A deleted nk's kind tag is visible and
  its byte span is skippable, but its fields are not decoded.
- **Odd UTF-16 name lengths rejected** for key and value names; the base
  block file name simply stops at the first NUL.
- **Inline data is limited to 4 bytes** by the format; larger values must
  be direct or db storage.
- **Value list has no self-count.** The nk value count drives reading, so
  a stale third entry in an over-large cell is ignored, not reported.
- **The checksum is stored, not validated**, and the reserved base-block
  bytes are not read.
- **Hash bytes in lf/lh are ignored** (entries are ordered as stored).
- **Memory:** the whole hive stays in the caller's buffer; `RegfHive`
  holds decoded names and table metadata only.
- Duplicate key names are allowed; `regf_key_find` returns the first
  match. Not thread-safe; `RegfHive` is a plain value type.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_*`/`_err_*` per result type; error-offset variants call them).
- Every `Vec[UInt8]` byte read is widened with `(v[i] as Int) & 0xFF`
  before entering Int arithmetic.
- `Vec[Int]`/`Vec[Str]` element reads are bound to typed locals; results
  are read via `let x: T = r.value;`.
- 64-bit values use the overflow-safe shape (low seven bytes with a
  `place` factor, the top byte applied separately); the highest bit
  decodes as a negative Int.
- High-bit field handling avoids `&` masks on u32 read values: the inline
  bit is `size_raw >= 2147483648` and the size is
  `size_raw - 2147483648`; cell sizes use `raw - 4294967296`.
- `Str` comparisons go through `xiom.string.compare`/`str_compare`;
  `regf_name_equal` folds with `str_lower` first (BUG 17 discipline).
- The module declares no `extern "C"` blocks (no FFI).
- Note for test authors: a call with more arguments than parameters is
  accepted silently by v0.61.3 (an extra argument is dropped), so the
  helper arities were double-checked by hand.

