# xiom.cpio -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.cpio`, version `0.1.0`).
Module: `src/cpio.xi` (`module xiom.cpio`).
Depends on `xiom.std` (`xiom.string`: `byte_at`); the tests additionally use
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
`xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for the ASCII cpio header formats `newc`
(`"070701"`, 13 eight-digit hexadecimal fields) and `odc` (`"070707"`, ten
octal fields):

- `cpio_parse` walks a buffer of concatenated entries until the first
  `TRAILER!!!` entry and returns a flat `CpioArchive` index: names, format
  codes, one stride-11 metadata vector, declared file sizes, data offsets
  and next-header offsets;
- `cpio_detect_format` reports the format of the first entry;
- `cpio_count`, `cpio_entry_name`, `cpio_entry_format`,
  `cpio_entry_field`, the named field accessors,
  `cpio_entry_filesize`, `cpio_entry_data_offset` and
  `cpio_entry_next_offset` read the index back;
- `cpio_entry_data` copies one declared data span out of the parse buffer;
- `cpio_append`, `cpio_append_trailer` and `cpio_build` write the same
  layout with the format's alignment, ending in the canonical trailer;
- deterministic `Err(Str)` messages for malformed input and invalid build
  arguments.

## Non-goals

- Filesystem I/O: no extraction, no archive creation on disk, no file
  metadata lookup.
- Compression (gzip/bzip2/xz/zstd wrappers) and block-size padding.
- Binary cpio formats (old binary, `070707` binary) and the `crc` ASCII
  format (`"070702"`): only `newc` and `odc` are recognized.
- Device semantics: no major/minor packing or unpacking; `odc`'s combined
  `dev`/`rdev` numbers are exposed through the devmajor/rdevmajor
  accessors as parsed.
- Hardlink/symlink resolution, file type dispatch, ownership mapping or
  permission enforcement.
- Path sanitization (absolute paths and `..` segments pass through
  verbatim) and UTF-8 validation of names.
- Streaming/incremental parsing: the API operates on whole in-memory
  `Vec[UInt8]` buffers.

## Byte-level layout

### newc

Magic `"070701"` (6 bytes, no NUL), then 13 fields of 8 ASCII hexadecimal
digits each (lowercase on output, upper or lower accepted on input), then
the name and its NUL. The fixed header is 110 bytes.

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 6 | magic | `"070701"` |
| 6 | 8 | ino | hex, 0..0xFFFFFFFF |
| 14 | 8 | mode | hex |
| 22 | 8 | uid | hex |
| 30 | 8 | gid | hex |
| 38 | 8 | nlink | hex |
| 46 | 8 | mtime | hex |
| 54 | 8 | filesize | hex |
| 62 | 8 | devmajor | hex |
| 70 | 8 | devminor | hex |
| 78 | 8 | rdevmajor | hex |
| 86 | 8 | rdevminor | hex |
| 94 | 8 | namesize | hex, 1..0xFFFFFFFF, includes the NUL |
| 102 | 8 | check | hex, stored verbatim |
| 110 | `namesize` | name | NUL-terminated, NUL is the final byte |
| 110 + `namesize` | 0..3 | padding | NUL bytes to a 4-byte boundary |
| aligned | `filesize` | data | raw bytes |
| aligned + `filesize` | 0..3 | padding | NUL bytes to a 4-byte boundary |

### odc

Magic `"070707"` (6 bytes), then ten fields of ASCII octal digits, then the
name and its NUL. The fixed header is 76 bytes.

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 6 | magic | `"070707"` |
| 6 | 6 | dev | octal, combined device number |
| 12 | 6 | ino | octal |
| 18 | 6 | mode | octal |
| 24 | 6 | uid | octal |
| 30 | 6 | gid | octal |
| 36 | 6 | nlink | octal |
| 42 | 6 | rdev | octal, combined rdev number |
| 48 | 11 | mtime | octal |
| 59 | 6 | namesize | octal, 1..262143, includes the NUL |
| 65 | 11 | filesize | octal |
| 76 | `namesize` | name | NUL-terminated, NUL is the final byte |
| 76 + `namesize` | 0 or 1 | padding | NUL byte to a 2-byte boundary |
| aligned | `filesize` | data | raw bytes |
| aligned + `filesize` | 0 or 1 | padding | NUL byte to a 2-byte boundary |

### Canonical metadata field order

`cpio_append`/`cpio_build` take a flat metadata buffer with stride 11 and
`cpio_parse` stores the same order in `CpioArchive.fields`:

| Index | Constant | Field |
|---|---|---|
| 0 | `CPIO_META_INO` | ino |
| 1 | `CPIO_META_MODE` | mode |
| 2 | `CPIO_META_UID` | uid |
| 3 | `CPIO_META_GID` | gid |
| 4 | `CPIO_META_NLINK` | nlink |
| 5 | `CPIO_META_MTIME` | mtime |
| 6 | `CPIO_META_DEVMAJOR` | devmajor (newc) / combined `dev` (odc) |
| 7 | `CPIO_META_DEVMINOR` | devminor (newc); `-1` in odc entries |
| 8 | `CPIO_META_RDEVMAJOR` | rdevmajor (newc) / combined `rdev` (odc) |
| 9 | `CPIO_META_RDEVMINOR` | rdevminor (newc); `-1` in odc entries |
| 10 | `CPIO_META_CHECK` | newc check; `-1` in odc entries |

`CPIO_META_LEN` is 11.

### Alignment rules

`newc` pads the fixed header plus the name (110 + `namesize`) with NUL
bytes up to the next multiple of 4, and pads the data (after the aligned
data start) with NUL bytes up to the next multiple of 4. `odc` uses a
2-byte boundary for both. Parsing requires every padding byte to exist and
be zero: a truncated or non-NUL pad is `Err("cpio: alignment mismatch")`.

### Trailer

An archive ends with an entry whose name is exactly `"TRAILER!!!"`: the
magic of its format, namesize 11, filesize 0, nlink 1 and every other
metadata field 0. `cpio_append_trailer`/`cpio_build` emit it with the
format's padding: the canonical trailer is 124 bytes for newc and 88 bytes
for odc. `cpio_parse` stops *at* the first exact trailer name without
storing it and without validating its metadata, so the trailer's own
padding may be absent and any bytes after the trailer are ignored.

## API signatures

All functions are free functions in module `xiom.cpio` (no self methods):

```xi
pub const CPIO_FORMAT_NEWC: Int = 0
pub const CPIO_FORMAT_ODC: Int = 1
pub const CPIO_META_INO: Int = 0
pub const CPIO_META_MODE: Int = 1
pub const CPIO_META_UID: Int = 2
pub const CPIO_META_GID: Int = 3
pub const CPIO_META_NLINK: Int = 4
pub const CPIO_META_MTIME: Int = 5
pub const CPIO_META_DEVMAJOR: Int = 6
pub const CPIO_META_DEVMINOR: Int = 7
pub const CPIO_META_RDEVMAJOR: Int = 8
pub const CPIO_META_RDEVMINOR: Int = 9
pub const CPIO_META_CHECK: Int = 10
pub const CPIO_META_LEN: Int = 11

pub type CpioArchive = {
  names: Vec[Str];
  formats: Vec[Int];
  fields: Vec[Int];
  filesizes: Vec[Int];
  data_offsets: Vec[Int];
  next_offsets: Vec[Int];
}

pub fn cpio_parse(data: &Vec[UInt8]) -> Result[CpioArchive, Str]
pub fn cpio_detect_format(data: &Vec[UInt8]) -> Int
pub fn cpio_count(a: &CpioArchive) -> Int
pub fn cpio_entry_format(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_field(a: &CpioArchive, i: Int, k: Int) -> Int
pub fn cpio_entry_name(a: &CpioArchive, i: Int) -> Str
pub fn cpio_entry_ino(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_mode(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_uid(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_gid(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_nlink(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_mtime(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_devmajor(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_devminor(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_rdevmajor(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_rdevminor(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_check(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_filesize(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_data_offset(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_next_offset(a: &CpioArchive, i: Int) -> Int
pub fn cpio_entry_data(data: &Vec[UInt8], a: &CpioArchive, i: Int) -> Result[Vec[UInt8], Str]
pub fn cpio_append(out: &mut Vec[UInt8], format: Int, name: Str, meta: &Vec[Int], data: &Vec[UInt8]) -> Result[Unit, Str]
pub fn cpio_append_trailer(out: &mut Vec[UInt8], format: Int) -> Result[Unit, Str]
pub fn cpio_build(format: Int, names: &Vec[Str], datas: &Vec[Vec[UInt8]], metas: &Vec[Int]) -> Result[Vec[UInt8], Str]
```

## Semantics

`cpio_parse(data)`
: Walks entries from offset 0; each entry's six-byte magic selects its
  format and alignment. For every entry the validation order is:

  1. six readable bytes -> else `Err("cpio: truncated header")`;
  2. magic in {`070701`, `070707`} -> else `Err("cpio: bad magic")`;
  3. the full fixed header (110 or 76 bytes) -> else
     `Err("cpio: truncated header")`;
  4. all field bytes are hex digits (newc) -> `Err("cpio: non-hex digit")`,
     or octal digits (odc) -> `Err("cpio: bad octal")`;
  5. `namesize >= 1` -> else `Err("cpio: bad namesize")`;
  6. the name field fits the buffer -> else `Err("cpio: truncated name")`;
  7. a NUL byte inside the name field -> else
     `Err("cpio: name missing NUL")`;
  8. the first NUL is the final name byte -> else
     `Err("cpio: bad namesize")`;
  9. (stop here when the name is exactly `TRAILER!!!`);
  10. header/name padding exists and is all NUL ->
      `Err("cpio: alignment mismatch")`;
  11. `filesize` fits the remaining buffer -> else
      `Err("cpio: truncated data")`;
  12. data padding exists and is all NUL ->
      `Err("cpio: alignment mismatch")`.

  On success the entry is appended: `names[i]` is the name as a `Str`,
  `formats[i]` is `CPIO_FORMAT_NEWC`/`CPIO_FORMAT_ODC`, the 11 metadata
  values (newc wire order permuted; odc combined dev/rdev mapped as in the
  field table) are appended to the flat `fields`, `filesizes[i]` is the
  declared size, `data_offsets[i]` is the absolute index of the first data
  byte and `next_offsets[i]` is the index just past the entry's data
  padding. Parsing resumes there. An empty buffer and any stream that ends
  before a trailer is `Err("cpio: missing trailer")`.

`cpio_detect_format(data)`
: `-1` when fewer than six bytes are present or the magic is neither
  `070701` nor `070707`; otherwise the first entry's format code.

`cpio_count(a)` / `cpio_entry_format(a, i)` / `cpio_entry_field(a, i, k)`
: `cpio_count` is `a.names.len()`. Out-of-range `i` (negative or
  `>= cpio_count`) yields `-1`; `cpio_entry_field` additionally yields `-1`
  for `k` outside `0..10`.

`cpio_entry_name(a, i)`
: `a.names[i]` for `0 <= i < cpio_count(a)`, `""` otherwise. The result is
  a `Str` read from a `Vec[Str]` field; callers must compare it with
  `str_compare` (see the compiler notes).

Named field accessors
: `cpio_entry_ino`/`mode`/`uid`/`gid`/`nlink`/`mtime`/`devmajor`/
  `devminor`/`rdevmajor`/`rdevminor`/`check` are thin wrappers over
  `cpio_entry_field` with the corresponding `CPIO_META_*` index; they
  return `-1` out of range. For odc entries `devminor`, `rdevminor` and
  `check` are always `-1` because the format has no such fields.

`cpio_entry_filesize(a, i)` / `cpio_entry_data_offset(a, i)` /
`cpio_entry_next_offset(a, i)`
: `-1` when `i` is out of range; otherwise the recorded value. For the last
  entry `next_offsets[i]` is the offset of the trailer header.

`cpio_entry_data(data, a, i)`
: `Err("cpio: entry out of range")` for a bad `i` (or a hand-built archive
  with a negative offset/size); `Err("cpio: truncated data")` when the
  recorded span does not fit `data`; otherwise a fresh vector holding
  `filesizes[i]` bytes copied from `data_offsets[i]`. A zero-size entry
  yields an empty `Ok`.

`cpio_append(out, format, name, meta, data)`
: Validates `format`, then `meta.len() == 11`, then every used field and
  the derived `namesize`/`filesize`, all before writing a single byte (so
  `out` is byte-for-byte unchanged on `Err`). For newc all 11 metadata
  values and `namesize`/`filesize` must be `<= 0xFFFFFFFF`; for odc
  ino/mode/uid/gid/nlink/dev/rdev must be `<= 262143`, mtime/filesize
  `<= 8589934591` and namesize `<= 262143`, while devminor, rdevminor and
  check are ignored. On success the entry is emitted with lowercase hex /
  zero-padded octal fields, name + NUL, NUL alignment padding, data and
  NUL data padding, exactly as the layout tables specify.

`cpio_append_trailer(out, format)`
: Validates `format` (Err unchanged) and appends the canonical trailer
  entry described above (124 bytes for newc, 88 for odc).

`cpio_build(format, names, datas, metas)`
: Validates `format`, then `names.len() == datas.len()`, then
  `metas.len() == names.len() * 11`, then appends each entry with the
  entry writer and finishes with the canonical trailer. The first failing
  entry surfaces its error unchanged. An empty build yields exactly the
  trailer entry.

## Error string catalog

| Condition | Error text |
|---|---|
| Six bytes at an entry start are neither `070701` nor `070707` (including an invalid format argument) | `cpio: bad magic` |
| Fewer than 6 bytes remain, or fewer than 110/76 bytes for the fixed header | `cpio: truncated header` |
| A newc field byte is not `[0-9a-fA-F]` | `cpio: non-hex digit` |
| An odc field byte is not `[0-7]` | `cpio: bad octal` |
| `namesize < 1`, or the first NUL is not the last name byte | `cpio: bad namesize` |
| The name field extends past the buffer | `cpio: truncated name` |
| No NUL byte inside the name field | `cpio: name missing NUL` |
| Header/name or data padding is truncated or non-NUL | `cpio: alignment mismatch` |
| Declared `filesize` does not fit the remaining buffer | `cpio: truncated data` |
| The stream ends before a `TRAILER!!!` entry (empty buffer included) | `cpio: missing trailer` |
| `cpio_entry_data` index out of range (or negative recorded span) | `cpio: entry out of range` |
| `cpio_entry_data` recorded span beyond the supplied buffer | `cpio: truncated data` |
| Build: `format` is neither 0 nor 1 | `cpio: bad format` |
| Build: `meta.len() != 11`, or `metas.len() != names.len() * 11` | `cpio: metadata length mismatch` |
| `cpio_build`: `names.len() != datas.len()` | `cpio: entry count mismatch` |
| Build: a used field is negative or exceeds its field width, or the name/data length exceeds the namesize/filesize width | `cpio: size overflow` |

The same `Str` texts are used in encode and decode where the condition is
the same (`cpio: truncated data` for a declared size that does not fit the
supplied buffer). Per-entry validation is first-error-wins in the order
listed for `cpio_parse`; `cpio_append` checks format, then metadata length,
then field widths/name/data sizes, then writes.

## Complexity

| Operation | Complexity |
|---|---|
| `cpio_parse` | O(data.len()) |
| `cpio_detect_format` / `cpio_count` / all `cpio_entry_*` scalar accessors | O(1) |
| `cpio_entry_name` | O(1) |
| `cpio_entry_data` | O(filesize) |
| `cpio_append` | O(name + data) |
| `cpio_append_trailer` | O(1) |
| `cpio_build` | O(total name + data bytes) |

## Test plan

`tests/test_conformance.xi` (`module cpio_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Hand-built archives are assembled byte by byte
in the test file, so the parser is exercised against bytes the test controls
rather than against `cpio_build`. Coverage:

1. empty newc archive: the independently built 124-byte trailer parses to
   zero entries; an empty `cpio_build` reproduces those exact bytes;
2. hand-built newc entry: pinned magic/ino/filesize/namesize bytes, name
   bytes, data-padding zero, every parsed field, data offset 116, next
   offset 120, exact data slice, trailer start byte;
3. newc 4-byte alignment: names `bc`/`b` produce data offsets 116/236 and
   next offsets 124/236, all padding zero; non-zero name padding, non-zero
   data padding and a truncated pad are `cpio: alignment mismatch`;
4. hand-built odc entry: pinned dev/ino/mode/namesize/filesize bytes, name
   bytes, parsed fields with devminor/rdevminor/check `-1`, data offset 78,
   next offset 80, exact data, and a rebuild byte-identical to the
   hand-built stream;
5. odc 2-byte alignment: name pad 1, data pad 1, offsets 80/82, non-zero
   pads Err; the empty odc archive is the pinned 88-byte trailer;
6. three entries in order (sizes 0/1/8), exact data slices, junk after the
   trailer ignored, and missing trailer (cut stream and empty buffer) Err;
7. magic detection (`070701` -> newc, `070707` -> odc, `070702`/short
   buffers -> -1) and header truncation for 5-byte tails, bare 6-byte
   magics and two corrupt magic bytes;
8. non-hex digit in the ino and check fields Err; uppercase hex digits
   parse (`0000002A` -> 42);
9. non-octal odc digits in ino/mtime/namesize/filesize Err; leading zeros
   parse;
10. name validation: missing NUL, non-final NUL (namesize too large),
    namesize 0, and an empty name (namesize 1) that parses as `""`;
11. truncated name (namesize beyond the buffer) and truncated data (cut
    buffer, and a declared filesize far beyond the buffer);
12. encode errors leave `out` untouched: bad format, metadata length
    mismatch, 2^32 newc field, negative field, 2^18 odc field, 2^33 odc
    mtime, 262143-byte odc name, bad `cpio_append_trailer` format; a valid
    trailer appends 124 bytes;
13. `cpio_build` argument errors (bad format, count mismatch, metadata
    mismatch) and the 88-byte empty odc build;
14. newc round-trip of three entries (sizes 6/0/17, fields including
    `0xFFFFFFFF` values) and rebuild from parsed accessors is
    byte-identical;
15. odc round-trip of two entries with rebuild byte-identical, confirming
    the ignored odc-absent fields survive as `-1` through a rebuild;
16. a single stream mixing a newc entry and an odc entry: formats, names,
    offsets 112/116 and 194/196 and exact data;
17. out-of-range accessor behavior: `""` names, `-1` formats/fields/sizes/
    offsets, `cpio_entry_field` over all 11 indices, and
    `cpio: entry out of range`;
18. `cpio_entry_data`: exact slice, short buffer -> `cpio: truncated data`,
    zero-size entry -> empty `Ok`;
19. only the exact `TRAILER!!!` name terminates: `TRAILER!!` and
    `TRAILER!!!!` parse as ordinary entries, a padding-truncated trailer
    still ends the archive, and the two trailer sizes are pinned;
20. alignment invariants across name sizes 3/4/5/6 and data sizes 0..5 for
    both formats: data/next offsets are aligned, the pad never exceeds the
    alignment, and data slices round-trip.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.cpio
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Header codec only: no extraction, no file creation, no filesystem
  metadata, no device-number packing, no compression, no block-size
  padding.
- Only `newc` and `odc`; the old binary and `crc` formats are rejected as
  `cpio: bad magic`.
- Padding must be NUL and complete; writers that leave dirty padding are
  rejected.
- The first exact `TRAILER!!!` ends parsing; following entries and the
  trailer's own fields are ignored. A stream without a trailer is an error.
- Field widths bound build values: 32-bit newc fields and 18-bit/33-bit odc
  fields; larger values are `cpio: size overflow`.
- Names round-trip as `Str` (NUL-terminated, no embedded NUL); the bytes
  are not checked for UTF-8 validity, and no path sanitization is applied.
- The whole archive and every data copy live in memory; plain value types,
  no thread safety.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_archive`,
  `_err_archive`, `_ok_bytes`, `_err_bytes`, `_ok_ints`, `_err_ints`,
  `_ok_int`, `_err_int`, `_ok_unit` and `_err_unit` (constructing Results
  directly in other functions miscompiles in this compiler).
- Every byte read from a `Vec[UInt8]` is widened with
  `(data[pos] as Int) & 0xFF` before entering arithmetic; UInt8 values are
  never compared against Int constants without widening.
- The per-entry metadata is one flat stride-11 `Vec[Int]` (no
  `Vec[StructType]`, no `Vec[Vec[Int]]`); `CpioArchive` (six `Vec` fields)
  is constructed inside `cpio_parse` and crosses function boundaries only
  by reference or through `_ok_archive`, following the `xiom.bmp` `BmpInfo`
  and `xiom.tar` `TarArchive` precedents.
- `Vec[Int]` element reads are always bound to typed locals (`let x: Int =
  v[i];`); untyped element reads can mis-lower to pointer/Str comparisons.
- Str values read from `Vec[Str]` fields are bound to typed locals and
  compared only through `xiom.string.compare.str_compare` (BUG 17: `==` on
  such values lowers to a pointer comparison). The parser matches
  `TRAILER!!!` byte-wise and never compares names with `==`.
- Result-returning helpers are called one per field and their `.value` is
  read only after `.is_ok`; the compiler note that `&r.value` in a nested
  call can read stale data is avoided by binding `let x = r.value` first.
- The package declares no `extern "C"` blocks (no FFI).
