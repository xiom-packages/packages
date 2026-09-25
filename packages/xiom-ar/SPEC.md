# xiom.ar -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.ar`, version `0.1.0`).
Module: `src/ar.xi` (`module xiom.ar`).
Depends on `xiom.std` (`xiom.string`: `byte_at`, `str_slice`); the tests
additionally use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`
and `xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for the common Unix `ar(5)` container:

- `ar_parse` validates a buffer and returns a flat `ArArchive` index (names,
  header offsets, payload offsets, payload sizes, mtimes, uids, gids, modes);
- `ar_count` and the `ar_entry_*` scalar accessors read the index back;
- `ar_entry_data` copies one payload out of the parse buffer;
- `ar_append` writes one member into a caller-owned buffer with correct
  field formatting and odd-size padding;
- `ar_build` writes the global magic plus every member of parallel
  name/data/metadata vectors;
- deterministic `Err(Str)` messages for malformed input and invalid build
  arguments.

## Non-goals

- GNU special members: the symbol table `/`, the long-name table `//`,
  `/SYM64/` and `/N` references are rejected with
  `Err("ar: unsupported special member")`.
- GNU long names, BSD ranlib tables, thin archives and any other extension
  member.
- Symbol-table parsing/generation, index emission and archive updating.
- Filesystem I/O: no extraction, no archive creation on disk, no file
  metadata lookup.
- Compression (`.a` is uncompressed) and static-link semantics.
- Path sanitization (names pass through verbatim) and UTF-8 validation.
- Streaming/incremental parsing: the API operates on whole in-memory
  `Vec[UInt8]` buffers.

## Byte-level layout

### Global magic

Every archive starts with the 8 bytes `!<arch>\n`
(`0x21 0x3C 0x61 0x72 0x63 0x68 0x3E 0x0A`). A buffer shorter than 8 bytes is
`Err("ar: bad global magic")`, as is any other prefix.

### Member header (60 bytes)

Offsets are decimal. All numeric fields are ASCII digits, left aligned and
space padded (0x20) to their width. A field is parsed by skipping leading
spaces, requiring at least one digit, requiring spaces after the digits and
rejecting any other byte (including a digit after a space).

| Offset | Size | Field | Format | Notes |
|---|---|---|---|---|
| 0 | 16 | name | ASCII | Plain name, or `#1/<len>` BSD extended. |
| 16 | 12 | mtime | decimal | Seconds since the epoch, as stored. |
| 28 | 6 | uid | decimal | |
| 34 | 6 | gid | decimal | |
| 40 | 8 | mode | **octal** | `ar(5)` convention; `100644` = 33188. |
| 48 | 10 | size | decimal | Member data size, BSD name bytes included. |
| 58 | 2 | terminator | bytes | Exactly `0x60 0x0A`. |

After the header come `size` member-data bytes, then exactly one `0x0A` pad
byte when `size` is odd. The pad keeps the stream even; an even-sized member
is followed immediately by the next header (or ends the archive).

### Naming

Plain names (`name[0] != '#'`, or any field that is not `#1/`):

- Parsing takes the bytes up to the first space or the full 16-byte field,
  then drops one trailing `/` (the GNU/SysV regular-member marker).
- A plain field whose first byte is `/` belongs to the GNU special-member
  namespace and is rejected.
- An empty plain field (first byte space) is `Err("ar: bad name")`.
- A 16-byte name with no space is accepted and returned whole.

BSD extended names (`#1/` prefix):

- Bytes 3..15 are the decimal byte length `<len>` of the name.
- `<len>` must be >= 1 and <= `AR_MAX_NAME` (255).
- The name occupies the first `<len>` bytes of the member data; the declared
  `size` must be >= `<len>`. The payload is the remaining
  `size - <len>` bytes.
- The payload offset recorded in the index is `header + 60 + <len>`.

The builder writes a name in the plain form only when it is 1..16 bytes,
contains no space and neither starts nor ends with `/`; every other name
uses the BSD form. Plain names are never written with a trailing `/`.

### Empty archive

A buffer that is exactly the 8-byte global magic parses to an `ArArchive`
with zero entries. `ar_build` with no entries emits exactly those 8 bytes.
There is no terminator member in ar; parsing stops when the buffer is
exhausted.

## API signatures

All functions are free functions in module `xiom.ar` (no self methods):

```xi
pub const AR_MAGIC_LEN: Int = 8
pub const AR_HEADER_LEN: Int = 60
pub const AR_MAX_NAME: Int = 255
pub const AR_META_MTIME: Int = 0
pub const AR_META_UID: Int = 1
pub const AR_META_GID: Int = 2
pub const AR_META_MODE: Int = 3
pub const AR_META_LEN: Int = 4

pub type ArArchive = {
  names: Vec[Str];
  header_offsets: Vec[Int];
  data_offsets: Vec[Int];
  sizes: Vec[Int];
  mtimes: Vec[Int];
  uids: Vec[Int];
  gids: Vec[Int];
  modes: Vec[Int];
}

pub fn ar_global() -> Vec[UInt8]
pub fn ar_parse(data: &Vec[UInt8]) -> Result[ArArchive, Str]
pub fn ar_count(a: &ArArchive) -> Int
pub fn ar_entry_name(a: &ArArchive, i: Int) -> Str
pub fn ar_entry_header_offset(a: &ArArchive, i: Int) -> Int
pub fn ar_entry_size(a: &ArArchive, i: Int) -> Int
pub fn ar_entry_data_offset(a: &ArArchive, i: Int) -> Int
pub fn ar_entry_mtime(a: &ArArchive, i: Int) -> Int
pub fn ar_entry_uid(a: &ArArchive, i: Int) -> Int
pub fn ar_entry_gid(a: &ArArchive, i: Int) -> Int
pub fn ar_entry_mode(a: &ArArchive, i: Int) -> Int
pub fn ar_entry_data(data: &Vec[UInt8], a: &ArArchive, i: Int) -> Result[Vec[UInt8], Str]
pub fn ar_append(out: &mut Vec[UInt8], name: Str, meta: &Vec[Int], data: &Vec[UInt8]) -> Result[Unit, Str]
pub fn ar_build(names: &Vec[Str], datas: &Vec[Vec[UInt8]], metas: &Vec[Int]) -> Result[Vec[UInt8], Str]
```

`metas` uses stride `AR_META_LEN` (4) with entry `i`'s fields at
`metas[i*4 .. i*4+3]` in the order mtime, uid, gid, mode -- the same order
`ar_append` takes.

## Semantics

`ar_parse(data)`
: Requires the 8-byte global magic -> `Err("ar: bad global magic")`.
  Walks members from offset 8; for every member the validation order is
  (first failure wins):

  1. 60 header bytes remain -> else `Err("ar: truncated header")`;
  2. bytes 58..59 are `0x60 0x0A` -> else `Err("ar: bad terminator")`;
  3. the name field is valid: plain (non-empty, not starting with `/`) or
     BSD (numerical `<len>`, `1 <= <len> <= 255`) -> else
     `Err("ar: bad name")` / `Err("ar: unsupported special member")` /
     `Err("ar: name too long")` / `Err("ar: bad decimal field")`;
  4. mtime, uid, gid and size are decimal and mode is octal ->
     `Err("ar: bad decimal field")` / `Err("ar: bad octal field")`;
  5. `size` fits the remaining buffer -> else `Err("ar: truncated data")`;
  6. for BSD names, `size >= <len>` -> else
     `Err("ar: size/data mismatch")`;
  7. when `size` is odd: a pad byte exists -> `Err("ar: missing padding")`
     and equals `0x0A` -> `Err("ar: bad padding")`.

  On success the entry is appended with the decoded name, the header offset,
  the payload offset/size (`size` for plain names, `size - <len>` at
  `header + 60 + <len>` for BSD names) and the parsed metadata. Parsing
  resumes after the data and its pad. `ar_entry_data` later copies the
  payload; nothing is copied during parsing.

`ar_count(a)`
: `a.names.len()`.

`ar_entry_name(a, i)`
: `a.names[i]` for `0 <= i < ar_count(a)`, `""` otherwise. The result is a
  `Str` read from a `Vec[Str]` field; callers must compare it with
  `str_compare` (see the compiler notes).

`ar_entry_header_offset` / `ar_entry_size` / `ar_entry_data_offset` /
`ar_entry_mtime` / `ar_entry_uid` / `ar_entry_gid` / `ar_entry_mode`
: The recorded scalar for `0 <= i < ar_count(a)`, `-1` otherwise.
  `ar_entry_size` is the payload size (BSD name bytes excluded).

`ar_entry_data(data, a, i)`
: `Err("ar: entry out of range")` for a bad `i` (or a hand-built archive
  with a negative offset/size); `Err("ar: truncated data")` when the
  recorded span does not fit `data`; otherwise a fresh vector with
  `sizes[i]` bytes copied from `data_offsets[i]`. A zero-size member yields
  an empty `Ok`.

`ar_append(out, name, meta, data)`
: Validates `meta.len() == AR_META_LEN`, then the name and every used field,
  then writes: the 16-byte name field (plain or `#1/<len>`), mtime/uid/gid
  as decimal, mode as octal, `size` (=`name.len() + data.len()` for BSD,
  `data.len()` otherwise) as decimal, the `0x60 0x0A` terminator, the BSD
  name bytes when used, the data, and one `0x0A` pad byte when `size` is
  odd. Every check runs before the first byte is written, so `out` is
  byte-for-byte unchanged on `Err`. Errors: `ar: bad name` (empty name),
  `ar: name too long` (> 255 bytes), `ar: field overflow` (negative or
  too-wide mtime/uid/gid/mode/size), `ar: metadata length mismatch`.

`ar_build(names, datas, metas)`
: Validates `names.len() == datas.len()` -> `ar: entry count mismatch`,
  `metas.len() == names.len() * AR_META_LEN` -> `ar: metadata length
  mismatch`, then emits the global magic followed by every member via the
  `ar_append` writer. The first failing entry surfaces its error unchanged.
  An empty build yields exactly the 8-byte magic. There is no terminator.

## Error string catalog

| Condition | Error text |
|---|---|
| Buffer shorter than 8 bytes or the first 8 bytes are not `!<arch>\n` | `ar: bad global magic` |
| Fewer than 60 bytes remain at a member start | `ar: truncated header` |
| Header bytes 58..59 are not `0x60 0x0A` | `ar: bad terminator` |
| Plain name field empty, or BSD `<len>` below 1 | `ar: bad name` |
| Plain name field starts with `/` (GNU `/`, `//`, `/N`, `/SYM64/`) | `ar: unsupported special member` |
| BSD `<len>` above `AR_MAX_NAME` (255); builder name above 255 bytes | `ar: name too long` |
| mtime/uid/gid/size or the BSD `<len>` field is not a clean decimal field | `ar: bad decimal field` |
| mode field is not a clean octal field | `ar: bad octal field` |
| Declared `size` does not fit the remaining buffer | `ar: truncated data` |
| BSD `<len>` greater than the declared `size` | `ar: size/data mismatch` |
| Odd `size` with no trailing pad byte | `ar: missing padding` |
| Odd `size` with a pad byte other than `0x0A` | `ar: bad padding` |
| `ar_entry_data` index out of range (or negative recorded span) | `ar: entry out of range` |
| `ar_entry_data` recorded span beyond the supplied buffer | `ar: truncated data` |
| `ar_append` `meta.len() != 4`, or `ar_build` `metas.len() != count * 4` | `ar: metadata length mismatch` |
| `ar_build` `names.len() != datas.len()` | `ar: entry count mismatch` |
| Builder name empty | `ar: bad name` |
| A metadata value is negative or wider than its field (mtime 12, uid/gid 6, mode 8 octal digits, size 10 decimal digits) | `ar: field overflow` |

The same `Str` texts are used in decode and encode where the condition is
the same (`ar: truncated data` for a span that does not fit the supplied
buffer). Per-member parse validation is first-error-wins in the order listed
for `ar_parse`; `ar_append` checks metadata length, then name, then field
widths, then writes.

## Complexity

| Operation | Complexity |
|---|---|
| `ar_global` | O(1) |
| `ar_parse` | O(data.len()) |
| `ar_count` / all `ar_entry_*` scalar accessors | O(1) |
| `ar_entry_name` | O(1) |
| `ar_entry_data` | O(size) |
| `ar_append` | O(name + data) |
| `ar_build` | O(total name + data bytes) |

## Test plan

`tests/test_conformance.xi` (`module ar_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Hand-built archives are assembled byte by byte
in the test file, so the parser is exercised against bytes the test controls
rather than against `ar_build`. Coverage:

1. `ar_build` emits the exact pinned 72-byte archive for `a.txt`/`"abc"`
   (magic, space-padded name, decimal mtime/uid/gid, octal mode `100644`,
   size, terminator, `0x0A` pad) and the parse round-trip pins every field,
   both offsets and the data slice;
2. two hand-built plain members parse with pinned names, sizes, metadata,
   header offsets 8/72 and data offsets 68/132 (the first member's odd size
   pad included);
3. BSD `#1/<len>` members (`verylong.txt!`, `a b`): names, payload sizes,
   header offset 84, payload offsets 68/147, exact data, and the embedded
   name bytes at the start of the member data;
4. plain-name rules: `foo/` parses as `foo`, a full 16-byte field with no
   space parses whole, and a space terminates the name;
5. padding: member lengths 60/62/62/64 for sizes 0/1/2/3, the `0x0A` bytes
   at the expected positions, missing pad -> `ar: missing padding`, `0x00`
   and `0x20` pads -> `ar: bad padding`;
6. a three-member `ar_build` (sizes 1/0/4, one BSD name) parses and a
   rebuild from the parsed accessors is byte-identical;
7. global magic errors (empty, 7-byte, wrong last byte) and the magic-only
   archive parsing to zero entries; 59 trailing bytes and a 30-byte tail
   after a good member -> `ar: truncated header`;
8. terminator corruption (`0x60` replaced, `0x0A` replaced by space and by
   NUL) -> `ar: bad terminator`;
9. malformed decimal fields: non-digit bytes in mtime/uid/gid/size, a digit
   after a space, an all-space field and a malformed `#1/xx` length ->
   `ar: bad decimal field`;
10. mode is octal: `100644` -> 33188, `644` -> 420, and `8`/`g`/all-space
    mode fields -> `ar: bad octal field`;
11. declared size beyond the buffer (partial body and body-less header) ->
    `ar: truncated data`; a BSD `<len>` larger than the declared size ->
    `ar: size/data mismatch`; a BSD name that exactly consumes the size
    yields a zero-byte payload;
12. the GNU special members `/`, `//`, `/12` and `/SYM64/` ->
    `ar: unsupported special member`;
13. name boundaries: a 16-byte plain name fills the field with no space, a
    17-byte name emits `#1/17`, a 255-byte name builds and parses, a
    256-byte name and `#1/0` -> `ar: name too long` / `ar: bad name`, an
    empty build name -> `ar: bad name`;
14. build validation leaves `out` untouched: 3- and 5-value metadata
    vectors, negative mtime, 7-digit uid/gid, mode 16777216, 13-digit
    mtime, then a valid append produces exactly 60 bytes; `ar_build` count
    and metadata mismatches; an empty build is exactly the magic;
15. out-of-range accessors (`""` names, `-1` scalars, entry out of range)
    and `ar_entry_data` slicing on a cut buffer and a zero-size member;
16. `ar_global` + two `ar_append` calls compose a valid archive
    (8 + 64 + 64 bytes, names in order); a member stream without magic ->
    `ar: bad global magic`;
17. numeric field forms: 12/6/6/8/10-byte fields with leading zeros, an
    8-byte octal mode with a leading space, and a 10-byte size with leading
    zeros all parse to the same values;
18. member offset arithmetic for sizes 1/2/3: total 196 bytes, headers at
    8/70/132 and data at 68/130/192;
19. a name with a space (`a b.txt`) emits `#1/7` with payload offset 75 and
    size 2; a name ending in `/` (`dir/`) round-trips through the BSD form;
20. the magic-only archive (8 bytes) parses to zero entries; an empty
    `ar_build` reproduces it exactly; `ar_global()` returns the same bytes.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ar
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

The pinned canonical bytes were additionally cross-checked with
`llvm-ar 22.1.8`: the 72-byte archive of test 1 lists as `a.txt` and prints
`abc`, and the BSD `#1/<len>` form is read with the name and payload this
codec records. GNU symbol-table archives are intentionally rejected (see
non-goals).

## Known limitations

- GNU special members and the long-name table are rejected; GNU/llvm-ar
  archives that contain a symbol table do not parse.
- No thin archives, no ranlib tables, no archive updating.
- Names are capped at 255 bytes and round-trip as byte strings; no UTF-8
  validation and no path sanitization.
- Plain names are written without the trailing `/`; only one trailing `/`
  is stripped on input.
- Field widths bound build values (mtime 12, uid/gid 6, mode 8 octal, size
  10 decimal digits); larger values are `ar: field overflow`.
- The whole archive and every payload copy live in memory; plain value
  types, no thread safety.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_archive`,
  `_err_archive`, `_ok_bytes`, `_err_bytes`, `_ok_int`, `_err_int`,
  `_ok_unit` and `_err_unit` (constructing Results directly in other
  functions miscompiles in this compiler).
- Every byte read from a `Vec[UInt8]` is widened with
  `(data[pos] as Int) & 0xFF` before entering arithmetic; UInt8 values are
  never compared against Int constants without widening.
- `Vec[Int]` element reads are always bound to typed locals (`let x: Int =
  v[i];`); untyped reads can mis-lower to pointer/Str comparisons.
- `ArArchive` (eight `Vec` fields) is constructed inside `ar_parse` and
  crosses function boundaries only by reference or through `_ok_archive`,
  following the `xiom.tar` `TarArchive` and `xiom.cpio` `CpioArchive`
  precedents. Per-entry metadata uses flat parallel vectors only (no
  `Vec[StructType]`).
- Str values read from `Vec[Str]` fields are bound to typed locals and
  compared through `xiom.string.compare.str_compare` only (BUG 17: `==` on
  such values lowers to a pointer comparison). `ar_entry_name` documents
  this contract.
- A reference to a `Result` field (`&r.value`) can read stale data; every
  result is bound with `let x = r.value;` before use.
- `&mut Vec[UInt8]` call sites pass the mutable binding explicitly; build
  buffers are declared with `var`.
- Observed compiler quirk: a call with fewer arguments than the declared
  parameter list (`meta4(0, 0, 0)` where the helper takes four) compiles
  and fills the missing argument with 0. Test helpers therefore build
  short vectors with explicit `Vec[Int]` pushes.
- The package declares no `extern "C"` blocks (no FFI).
