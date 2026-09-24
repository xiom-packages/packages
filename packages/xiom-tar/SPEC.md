# xiom.tar -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.tar`, version `0.1.0`).
Module: `src/tar.xi` (`module xiom.tar`).
Depends on `xiom.std` (`xiom.string`: `byte_at`, `str_concat`).

## Scope

A pure-XIOM (no FFI) codec for uncompressed POSIX ustar archives:

- `tar_parse` validates a buffer and returns a `TarArchive` index (names,
  types, sizes, modes, mtimes, data offsets);
- `tar_entry_count` / `tar_entry_name` / `tar_entry_size` are O(1) readers;
- `tar_entry_data` copies one payload out of the parse buffer;
- `tar_build` writes a canonical ustar archive (regular files only) with
  correct checksums, 512-byte payload padding and the two-zero-block
  terminator.

## Non-goals

- GNU long names/long links (`././@LongLink`), GNU sparse files, PAX
  extended headers (`PaxHeaders.*`) and any other extension record.
- Compression (gzip/bzip2/xz/zstd): only the uncompressed container.
- Link resolution, hardlink/symlink semantics, device nodes, ownership
  mapping, permission enforcement or extraction to disk.
- Prefix splitting on build: names longer than 100 bytes are rejected
  instead of being split into `prefix`; `tar_parse` does join an existing
  prefix with `name`.
- Streaming: the API operates on whole in-memory `Vec[UInt8]` buffers.
- Archives above 8^11 - 1 bytes per entry (the 11-octal-digit size field).

## Byte layout (512-byte ustar header)

Offsets are decimal; all numeric fields are ASCII octal. Parsing skips
leading NULs and spaces; the first NUL or space after the digits terminates
the field. Bytes after the terminator are ignored only while they are NUL or
space; any non-octal, non-terminator byte is `Err("tar: bad octal")`, as is
a digit that appears after a terminator.

| Offset | Size | Field | Value / rule |
|---|---|---|---|
| 0 | 100 | name | NUL-terminated (may fill the field). |
| 100 | 8 | mode | Octal; required by `tar_parse`, written as `"0000644\0"`. |
| 108 | 8 | uid | Octal; written as `"0000000\0"`. |
| 116 | 8 | gid | Octal; written as `"0000000\0"`. |
| 124 | 12 | size | Octal; written as 11 digits + NUL. |
| 136 | 12 | mtime | Octal; written as `"00000000000\0"`. |
| 148 | 8 | chksum | 6 octal digits + NUL + space in output; validated on parse. |
| 156 | 1 | typeflag | `'0'`/NUL regular, `'5'` directory, raw byte otherwise. |
| 157 | 100 | linkname | Ignored. |
| 257 | 6 | magic | Bytes 257..261 must be `"ustar"`; byte 262 NUL (POSIX) or space (GNU). |
| 263 | 2 | version | Not validated. |
| 265 | 32 | uname | Ignored. |
| 297 | 32 | gname | Ignored. |
| 329 | 8 | devmajor | Ignored; written zeroed octal. |
| 337 | 8 | devminor | Ignored; written zeroed octal. |
| 345 | 155 | prefix | Joined with `name` through `/` when non-empty. |
| 500 | 12 | pad | Ignored. |

Payloads start at `header + 512`, occupy `size` bytes and are followed by
zero padding up to the next multiple of 512. Two consecutive all-zero
512-byte blocks terminate the archive; `tar_build` always writes them.

Checksum: the unsigned sum of all 512 header bytes with the checksum field
read as eight spaces (`0x20`). `tar_build` stores `sum % 8^6` as six octal
digits + NUL + space (`"%06o\0 "`). Worked example -- the `a.txt` entry with
a 3-byte payload emits checksum 4207 decimal = `010157` octal.

## API signatures

All functions are free functions in module `xiom.tar`:

```xi
pub type TarArchive = {
  names: Vec[Str]; types: Vec[Int]; sizes: Vec[Int];
  modes: Vec[Int]; mtimes: Vec[Int]; data_offsets: Vec[Int];
}

pub fn tar_parse(data: &Vec[UInt8]) -> Result[TarArchive, Str]
pub fn tar_entry_count(a: &TarArchive) -> Int
pub fn tar_entry_name(a: &TarArchive, i: Int) -> Str
pub fn tar_entry_size(a: &TarArchive, i: Int) -> Int
pub fn tar_entry_data(data: &Vec[UInt8], a: &TarArchive, i: Int) -> Result[Vec[UInt8], Str]
pub fn tar_build(names: &Vec[Str], payloads: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
```

## Semantics

`tar_parse(data)`
: Walks header blocks from offset 0 while at least 512 bytes remain.

  - An all-zero 512-byte block ends the archive: parsing stops, any
    following bytes (including a second zero block) are ignored.
  - When fewer than 512 bytes remain and every remaining byte is zero,
    parsing stops (the short tail counts as the start of a terminator).
    A short non-zero tail is `Err("tar: truncated header")`.
  - For a non-zero block, validation runs in this order (first failure
    wins): magic bytes -> `Err("tar: bad magic")`; the checksum field must
    be octal -> `Err("tar: bad octal")`; the stored checksum must equal the
    computed unsigned sum -> `Err("tar: bad checksum")`; mode, size and
    mtime must be octal -> `Err("tar: bad octal")`; `size` must fit in the
    remaining buffer -> `Err("tar: truncated data")`.
  - On success one entry is appended: `name` is
    `prefix + "/" + name` when the `prefix` field is non-empty (byte-wise
    `str_concat`; an empty name with a non-empty prefix yields
    `"prefix/"`); `types[i]` is 0 for `'0'`/NUL, 5 for `'5'`, else the raw
    typeflag byte; `sizes`/`modes`/`mtimes` are the parsed octal values;
    `data_offsets[i]` is the absolute index of the first payload byte.
  - Parsing resumes at `data_offset + ceil(size/512)*512`; a missing final
    padding or terminator at EOF is tolerated. Trailing garbage after a
    zero block is ignored.

  Some structural choices are lenient by design: an all-NUL octal field
  parses as 0, a zero-filled short tail is an end-of-archive, and a single
  zero block terminates the archive. An empty buffer parses to zero entries.

`tar_entry_count(a)`
: `a.names.len()`.

`tar_entry_name(a, i)`
: `a.names[i]` for `0 <= i < tar_entry_count(a)`; `""` otherwise. The
  result is a `Str` read from a `Vec[Str]`; callers must compare it with
  `str_compare` (see the compiler notes).

`tar_entry_size(a, i)`
: `a.sizes[i]` for `0 <= i < tar_entry_count(a)`; `0` otherwise.

`tar_entry_data(data, a, i)`
: Copies `a.sizes[i]` bytes starting at `a.data_offsets[i]` out of `data`
  into a fresh vector. Err("tar: entry out of range") when `i` is out of
  range (or a hand-built archive carries a negative offset/size);
  Err("tar: truncated data") when the recorded range does not fit in
  `data`. A zero-size entry yields an empty `Ok`.

`tar_build(names, payloads)`
: Requires `names.len() == payloads.len()` (Err("tar: payload count
  mismatch")) and every name <= 100 bytes (Err("tar: name too long")).
  For each entry, in order: a 512-byte header (name left-aligned and
  NUL-padded; mode `"0000644\0"`; uid/gid `"0000000\0"`; size as 11 octal
  digits + NUL; mtime `0`; devmajor/devminor `"0000000\0"`; typeflag `'0'`;
  linkname/uname/gname/prefix zeroed; magic `"ustar\0"`; version `"00"`;
  checksum as above), then the payload verbatim, then zero padding to the
  next multiple of 512. The archive ends with exactly 1024 zero bytes. An
  empty build returns exactly those 1024 terminator bytes.

## Error string catalog

| Condition | Error text |
|---|---|
| Partial non-zero header block (< 512 bytes, or a partial block mid-file) | `tar: truncated header` |
| Magic bytes 257..262 wrong | `tar: bad magic` |
| Checksum, mode, size or mtime field not octal | `tar: bad octal` |
| Stored checksum != unsigned 512-byte sum (field read as spaces) | `tar: bad checksum` |
| Declared size extends past the buffer | `tar: truncated data` |
| `tar_build` name longer than 100 bytes | `tar: name too long` |
| `tar_build` names/payloads counts differ | `tar: payload count mismatch` |
| Entry index out of range | `tar: entry out of range` |
| Entry range outside the supplied buffer | `tar: truncated data` |

## Complexity

| Operation | Complexity |
|---|---|
| `tar_parse` | O(entries * 512 + total payload span) |
| `tar_entry_count` / `tar_entry_name` / `tar_entry_size` | O(1) |
| `tar_entry_data` | O(size) |
| `tar_build` | O(total payload + 512 * entries) |

## Test plan

`tests/test_conformance.xi` (`module tar_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Hand-built archives are assembled byte by byte
in the test file, so the parser is exercised against bytes the test controls
rather than against `tar_build`. Coverage:

1. exact pinned 345-byte header prefix (name, octal fields, checksum,
   typeflag, linkname, magic/version, uname/gname, dev fields) plus
   zero 345..512, exact payload bytes, zero padding/terminator, and a
   parse round-trip;
2. stored checksum equals an independent 512-byte sum (and is non-zero);
3. corrupted header byte -> `tar: bad checksum`; non-octal checksum -> `tar:
   bad octal`;
4. bad magic in the magic field, the last magic byte and the version byte
   (checksum re-computed so only magic fails) -> `tar: bad magic`;
5. GNU magic variant (`"ustar "` + NUL version) parses;
6. pinned name/mode(493)/size(7)/mtime(1700000000)/offset(512)/type and the
   exact 7-byte data slice;
7. prefix join: `dir/sub` + `file.txt` -> `dir/sub/file.txt`; empty prefix
   leaves the name unchanged;
8. typeflag mapping: `'5'` -> 5 (directory, empty data), `'2'` -> 50 (raw),
   NUL -> 0;
9. payload padding for sizes 0/1/511/512/513/1024: exact total lengths,
   `tar_entry_size` and byte-exact data slices;
10. two-zero-block terminator, single zero block, and trailing garbage after
    the terminator (ignored);
11. EOF tolerance: no terminator, missing final padding (size 3, data only),
    partial zero tail, and a 512-byte payload ending at EOF;
12. truncation: 300-byte header cut, a second header cut mid-block,
    over-declared size with a short payload -> documented errors; the full
    archive still parses;
13. 100-byte name builds and round-trips; 101-byte name -> `tar: name too
    long`; count mismatch (2 names/1 payload and 0 names/1 payload) -> `tar:
    payload count mismatch`; empty name builds and parses as one entry;
14. two-file build/parse round-trip (sizes 0 and 1000) with byte-exact data,
    plus `tar: entry out of range` at -1 and count;
15. empty archives: empty build (1024 zero bytes), empty input, one zero
    block and a 100-byte zero tail all parse to zero entries;
16. octal forms: mode `"  644\0\0\0"` and size with leading NULs parse;
    a `'9'` in mode and a `'z'` in size -> `tar: bad octal`;
17. `tar_entry_data` on a buffer cut before the payload -> `tar: truncated
    data`; the full buffer yields the exact bytes;
18. accessors out of range: name `""`, size 0, valid values in range;
19. three mixed entries keep order, names (with and without prefix), types,
    modes and sizes;
20. build -> parse -> build is byte-identical for 1- and 513-byte payloads;
21. `data_offsets` pinned at 512 and 1536 across 512-byte payloads;
22. zero padding between entries (bytes 515..1024 zero) and the second
    header at 1024 / second payload at 1536.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.tar
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- POSIX ustar only; GNU longname/longlink, PAX headers and sparse extensions
  are not supported and will be parsed as ordinary entry names or fail the
  documented checks.
- No compression, no link handling, no path sanitization; callers extracting
  entries must apply their own traversal policy.
- `tar_build` never emits a prefix field, uname/gname, non-zero uid/gid or
  non-zero mtime; it always writes typeflag `'0'` and mode `0644` for names
  up to 100 bytes.
- The size field is 11 octal digits; larger entries are not representable.
- The full archive and each returned payload copy live in memory.
- No thread safety; plain value types only.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_archive`,
  `_err_archive`, `_ok_bytes`, `_err_bytes`, `_ok_int`, `_err_int`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- Every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8 values
  are never compared against Int constants without widening.
- `TarArchive` (six `Vec` fields) is constructed inside `tar_parse` and
  crosses function boundaries by reference or through `_ok_archive`; this
  follows the `xiom.bmp` `BmpInfo` precedent.
- Str values read from `Vec[Str]` fields are bound to typed locals; callers
  compare them with `str_compare` (BUG 17: `==` on a Str read from a `Vec`
  lowers to a pointer comparison).
- A reference to a `Result` field, e.g. `tar_parse(&r.value)`, can read
  stale data in v0.61.3 (observed here: the parse returned an empty archive
  while the same buffer bound to a local parsed correctly). Always bind
  `let x = r.value;` first.
- Index assignment through a `&mut Vec[UInt8]` parameter works and is used
  for the checksum field; `&mut` on a `let` binding is only an E001 warning,
  so mutating buffers are declared with `var`.
- `Str::from_utf8(Vec[UInt8])` is the stdlib byte-to-string conversion used
  for header fields; `string.byte_at` / `string.str_concat` come from
  `xiom.string`. The module declares no `extern "C"` blocks (no FFI).
