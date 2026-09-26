# xiom.cab -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.cab`, version `0.1.0`).
Module: `src/cab.xi` (`module xiom.cab`).
Depends on `xiom.std` (`xiom.string`: `byte_at`); the tests additionally use
`xiom.test`, `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for the Microsoft Cabinet (CAB) header and
directory structures ([MS-CAB]: `CFHEADER`, `CFFOLDER`, `CFFILE`):

- `cab_parse` validates a cabinet buffer and returns a flat `CabArchive`
  index (header scalars plus parallel folder and file columns);
- the `cab_*` accessors read the index back (cabinet size, version, flags,
  setID/iCabinet, folder start/data count/compression/reserve offset, file
  name/size/offset/folder/date/time/attribs/UTF flag, reserved spans);
- `cab_build` emits a canonical version-1.3 header plus directory for
  uncompressed files (one folder, `typeCompress` 0, no CFDATA);
- helper predicates decode the compression code and the packed DOS
  date/time;
- deterministic `Err(Str)` messages for malformed input and invalid build
  arguments.

## Non-goals

- **CFDATA records**: data blocks are never parsed. `cCFData` is indexed and
  the minimal block extent is bounds-checked, but checksums, `cbData`,
  `cbUncomp` and payload bytes are not read.
- **Decompression**: MSZIP, Quantum and LZX algorithms are out of scope.
  `typeCompress` is stored raw and an unknown algorithm code is accepted
  (documented pass-through).
- **File extraction**: no file data is copied out and no filesystem I/O of
  any kind is performed.
- **Multi-cabinet sets**: the prev/next cabinet strings are validated and
  skipped so the folder array can be located, but their names are not
  stored; `setID`/`iCabinet` are exposed but no set traversal is offered.
- **Builder extras**: `cab_build` emits no CFDATA, no reserve areas and no
  prev/next links.
- **Full UTF-8 validation**: with the UTF attribute bit set, bytes
  0x80..0xFF are accepted verbatim; sequences are not decoded.
- Streaming: the API operates on whole in-memory `Vec[UInt8]` buffers.

## Byte-level layout

All multi-byte integers are little-endian. Offsets are decimal.

### CFHEADER

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | signature | Exactly `"MSCF"` (`4D 53 43 46`). |
| 4 | 4 | reserved1 | Must be 0. |
| 8 | 4 | cbCabinet | Total cabinet size, header included. |
| 12 | 4 | reserved2 | Must be 0. |
| 16 | 4 | coffFiles | Absolute offset of the first CFFILE. |
| 20 | 4 | reserved3 | Must be 0. |
| 24 | 1 | versionMinor | |
| 25 | 1 | versionMajor | |
| 26 | 2 | cFolders | Number of CFFOLDER entries. |
| 28 | 2 | cFiles | Number of CFFILE entries. |
| 30 | 2 | flags | See the flag bits below. |
| 32 | 2 | setID | Present only when the version is 1.3 or greater. |
| 34 | 2 | iCabinet | Present only when the version is 1.3 or greater. |
| 36 | 2 | cbCFHeader | Present only with CAB_FLAG_RESERVE_PRESENT. |
| 38 | 1 | cbCFFolder | Present only with CAB_FLAG_RESERVE_PRESENT. |
| 39 | 1 | cbCFData | Present only with CAB_FLAG_RESERVE_PRESENT. |
| 40 | cbCFHeader | abReserve | Header reserve area (raw span). |
| ... | n | szCabinetPrev | NUL-terminated, only with CAB_FLAG_PREV_CABINET. |
| ... | n | szDiskPrev | NUL-terminated, only with CAB_FLAG_PREV_CABINET. |
| ... | n | szCabinetNext | NUL-terminated, only with CAB_FLAG_NEXT_CABINET. |
| ... | n | szDiskNext | NUL-terminated, only with CAB_FLAG_NEXT_CABINET. |

The documented "1.3 or greater" rule is `major > 1`, or `major == 1` and
`minor >= 3` (exposed as `cab_version_has_setid`). Flag bits:

| Bit | Constant | Meaning |
|---|---|---|
| 0x0001 | `CAB_FLAG_RESERVE_PRESENT` | Reserve descriptor and header reserve follow. |
| 0x0002 | `CAB_FLAG_LOCK` | Exposed raw; not interpreted. |
| 0x0004 | `CAB_FLAG_PREV_CABINET` | Two prev-cabinet strings follow. |
| 0x0008 | `CAB_FLAG_NEXT_CABINET` | Two next-cabinet strings follow. |

### CFFOLDER

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | coffCabStart | Absolute offset of the folder's first CFDATA. |
| 4 | 2 | cCFData | Number of CFDATA records in the folder. |
| 6 | 2 | typeCompress | Raw word: low nibble is the algorithm. |
| 8 | cbCFFolder | abReserve | Per-folder reserve area (raw span). |

`typeCompress` codes (`cab_compression_code`, low nibble): 0 none,
1 MSZIP, 2 Quantum (Q), 3 LZX. Higher bits carry algorithm parameters
(for example the LZX window bits); `cab_compression_known` returns true when
the code is 0..3 and false otherwise, but parsing never rejects an unknown
code -- the raw word is passed through.

### CFFILE

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | cbFile | Uncompressed size in bytes. |
| 4 | 4 | uoffFolderStart | Uncompressed offset inside the folder. |
| 8 | 2 | iFolder | Owning folder index; must be < cFolders. |
| 10 | 2 | date | Packed MS-DOS date. |
| 12 | 2 | time | Packed MS-DOS time. |
| 14 | 2 | attribs | Raw DOS attribute word. |
| 16 | n | szName | NUL-terminated name, not stored with the NUL. |

DOS attribute bits (`CAB_ATTRIB_*`): 0x01 read-only, 0x02 hidden,
0x04 system, 0x08 volume, 0x10 directory, 0x20 archive, 0x40 device,
0x80 name is UTF-8 (honored only for version 1.3+ cabinets).

Packed date/time, decoded arithmetically (`cab_dos_date_*`,
`cab_dos_time_*`): date = `((year - 1980) << 9) | (month << 5) | day`,
time = `(hour << 11) | (minute << 5) | (second / 2)`. Worked example:
date 23866 decodes to 2026-09-26, time 25692 to 12:34:56 (56 s = 28
two-second units).

### Directory placement

The CFFOLDER array starts immediately after the CFHEADER optional parts
(including prev/next strings), one entry of `8 + cbCFFolder` bytes each.
The CFFILE array starts at `coffFiles`, one entry of `16 + len(name) + 1`
bytes each. CFDATA blocks follow per folder at `coffCabStart`. Bytes at or
past `cbCabinet` are ignored; the buffer must contain the whole cabinet.

## API signatures

All functions are free functions in module `xiom.cab`:

```xi
pub const CAB_SIGNATURE_LEN: Int = 4
pub const CAB_HEADER_MIN: Int = 32
pub const CAB_HEADER_LEN: Int = 36
pub const CAB_FOLDER_LEN: Int = 8
pub const CAB_FILE_LEN: Int = 16
pub const CAB_MAX_NAME: Int = 255
pub const CAB_MAX_FILES: Int = 65535
pub const CAB_FLAG_RESERVE_PRESENT: Int = 1
pub const CAB_FLAG_LOCK: Int = 2
pub const CAB_FLAG_PREV_CABINET: Int = 4
pub const CAB_FLAG_NEXT_CABINET: Int = 8
pub const CAB_COMPRESSION_NONE: Int = 0
pub const CAB_COMPRESSION_MSZIP: Int = 1
pub const CAB_COMPRESSION_QUANTUM: Int = 2
pub const CAB_COMPRESSION_LZX: Int = 3
pub const CAB_ATTRIB_READONLY: Int = 1
pub const CAB_ATTRIB_HIDDEN: Int = 2
pub const CAB_ATTRIB_SYSTEM: Int = 4
pub const CAB_ATTRIB_VOLUME: Int = 8
pub const CAB_ATTRIB_DIRECTORY: Int = 16
pub const CAB_ATTRIB_ARCHIVE: Int = 32
pub const CAB_ATTRIB_DEVICE: Int = 64
pub const CAB_ATTRIB_UTF_NAME: Int = 128

pub type CabArchive = {
  cabinet_size: Int; version_major: Int; version_minor: Int; flags: Int;
  set_id: Int; i_cabinet: Int;
  reserve_header_len: Int; reserve_folder_len: Int; reserve_data_len: Int;
  reserved_header_offset: Int;
  names: Vec[Str]; file_sizes: Vec[Int]; file_offsets: Vec[Int];
  file_folders: Vec[Int]; file_dates: Vec[Int]; file_times: Vec[Int];
  file_attribs: Vec[Int];
  folder_starts: Vec[Int]; folder_data_counts: Vec[Int];
  folder_compress: Vec[Int]; folder_offsets: Vec[Int];
}

pub fn cab_parse(data: &Vec[UInt8]) -> Result[CabArchive, Str]
pub fn cab_cabinet_size(a: &CabArchive) -> Int
pub fn cab_version_major(a: &CabArchive) -> Int
pub fn cab_version_minor(a: &CabArchive) -> Int
pub fn cab_flags(a: &CabArchive) -> Int
pub fn cab_set_id(a: &CabArchive) -> Int
pub fn cab_i_cabinet(a: &CabArchive) -> Int
pub fn cab_folder_count(a: &CabArchive) -> Int
pub fn cab_file_count(a: &CabArchive) -> Int
pub fn cab_reserved_header_len(a: &CabArchive) -> Int
pub fn cab_reserved_folder_len(a: &CabArchive) -> Int
pub fn cab_reserved_data_len(a: &CabArchive) -> Int
pub fn cab_reserved_header_offset(a: &CabArchive) -> Int
pub fn cab_folder_start(a: &CabArchive, i: Int) -> Int
pub fn cab_folder_data_count(a: &CabArchive, i: Int) -> Int
pub fn cab_folder_compression(a: &CabArchive, i: Int) -> Int
pub fn cab_folder_reserve_offset(a: &CabArchive, i: Int) -> Int
pub fn cab_file_name(a: &CabArchive, i: Int) -> Str
pub fn cab_file_size(a: &CabArchive, i: Int) -> Int
pub fn cab_file_offset(a: &CabArchive, i: Int) -> Int
pub fn cab_file_folder(a: &CabArchive, i: Int) -> Int
pub fn cab_file_date(a: &CabArchive, i: Int) -> Int
pub fn cab_file_time(a: &CabArchive, i: Int) -> Int
pub fn cab_file_attribs(a: &CabArchive, i: Int) -> Int
pub fn cab_file_utf(a: &CabArchive, i: Int) -> Bool
pub fn cab_compression_code(type_compress: Int) -> Int
pub fn cab_compression_known(type_compress: Int) -> Bool
pub fn cab_version_has_setid(major: Int, minor: Int) -> Bool
pub fn cab_dos_date_year(d: Int) -> Int
pub fn cab_dos_date_month(d: Int) -> Int
pub fn cab_dos_date_day(d: Int) -> Int
pub fn cab_dos_time_hour(t: Int) -> Int
pub fn cab_dos_time_minute(t: Int) -> Int
pub fn cab_dos_time_second(t: Int) -> Int
pub fn cab_build(names: &Vec[Str], sizes: &Vec[Int]) -> Result[Vec[UInt8], Str]
```

## Semantics

`cab_parse(data)`
: Validation order, first failure wins:

  1. at least 4 bytes and the signature `"MSCF"` -> else
     `Err("cab: bad signature")`;
  2. at least the 32-byte fixed prefix -> else
     `Err("cab: truncated header")`;
  3. reserved1, reserved2 and reserved3 are zero -> else
     `Err("cab: reserved field set")`;
  4. `cbCabinet <= data.len()` -> else `Err("cab: truncated cabinet")`,
     and `cbCabinet >= 32` -> else `Err("cab: bad cabinet size")`;
  5. the version-1.3 setID/iCabinet pair fits `cbCabinet` -> else
     `Err("cab: truncated header")` (absent fields read -1);
  6. with the reserve flag: the 4 descriptor bytes and the `cbCFHeader`
     reserve bytes fit `cbCabinet` -> else `Err("cab: truncated header")`
     (absent descriptor reads 0/0/0);
  7. each present prev/next string has a NUL before `cbCabinet` -> else
     `Err("cab: truncated string")`; the strings are skipped, not stored;
  8. `cFolders * (8 + cbCFFolder)` fits `cbCabinet` after the header ->
     else `Err("cab: folder directory overflow")`;
  9. when `cFiles > 0`: `coffFiles` is between the folder array end and
     `cbCabinet` -> else `Err("cab: coffFiles out of range")`, and the
     minimal file directory `cFiles * 17` fits -> else
     `Err("cab: file directory overflow")`. When `cFiles == 0` `coffFiles`
     is ignored (0 is allowed);
  10. per folder in order: `coffCabStart <= cbCabinet` and
      `cCFData * (8 + cbCFData)` fits after it -> else
      `Err("cab: folder data out of range")`;
  11. per file in order from `coffFiles`: the 16 fixed bytes fit ->
      else `Err("cab: truncated file directory")`; `iFolder < cFolders` ->
      else `Err("cab: bad folder index")`; `uoffFolderStart + cbFile` is
      representable in 32 bits -> else `Err("cab: file span out of range")`;
      the name has a NUL before `cbCabinet` -> else
      `Err("cab: truncated name")`, is non-empty, and passes the printable
      policy -> else `Err("cab: bad name")`.

  Printable policy: bytes 0x20..0x7E are accepted always; bytes 0x80..0xFF
  are accepted only when the UTF attribute bit 0x80 is set and the cabinet
  version is 1.3 or greater. UTF-8 sequences are not decoded. Bytes at or
  past `cbCabinet` are ignored, so trailing data after a cabinet is
  tolerated.

`cab_*` scalar/name accessors
: Return the recorded value for an in-range index; `-1` (`""` for
  `cab_file_name`, `false` for `cab_file_utf`) when the index is negative or
  at/above the owning vector length. If a hand-built `CabArchive` has
  differently sized parallel columns, each accessor is still safe: it guards
  its own column.

`cab_reserved_header_offset(a)`
: Absolute offset of the `abReserve` area; when
  `cab_reserved_header_len(a) == 0` the span is empty and the offset is
  just past the optional header fields.

`cab_folder_reserve_offset(a, i)`
: `folder_offsets[i] + 8`, the start of folder `i`'s reserve bytes; the span
  length is `cab_reserved_folder_len(a)` (0 when no reserve area exists).

`cab_compression_code` / `cab_compression_known`
: Low nibble of the raw `typeCompress` word, and a predicate for codes 0..3.
  Unknown codes still parse (documented pass-through); a negative input
  reads -1 / false.

`cab_dos_date_*` / `cab_dos_time_*`
: Arithmetic bit-field extraction from the packed u16 (see the layout
  table); no calendar validation -- month/day/hour fields are returned as
  stored (0 means unset).

`cab_build(names, sizes)`
: Emits a canonical, structurally valid but dataless cabinet:

  - a version-1.3 CFHEADER (`minor 3`, `major 1`), `setID 0`, `iCabinet 0`,
    no flags, no reserve area and no prev/next strings;
  - one CFFOLDER with `typeCompress CAB_COMPRESSION_NONE`, `cCFData 0` and
    `coffCabStart` = the end of the directory (where CFDATA would begin);
  - one CFFILE per name in order: `cbFile = sizes[i]`,
    `uoffFolderStart` = running sum of the declared sizes, `iFolder 0`,
    date/time 0, `attribs CAB_ATTRIB_ARCHIVE` (0x20), name + NUL;
  - `coffFiles = 44` (36-byte header + one 8-byte folder entry) and
    `cbCabinet` = the exact emitted length.

  Validation runs before the first byte is written: count mismatch ->
  `cab: entry count mismatch`; more than 65535 entries ->
  `cab: too many files`; a size outside 0..2^32-1 -> `cab: size overflow`;
  an empty name or a byte outside 0x20..0x7E -> `cab: bad name`; a name
  above 255 bytes -> `cab: name too long`. An empty build yields exactly the
  44-byte header + folder entry.

## Error string catalog

| Condition | Error text |
|---|---|
| Buffer shorter than 4 bytes, or bytes 0..3 are not `"MSCF"` | `cab: bad signature` |
| Fewer than the 32 fixed CFHEADER bytes | `cab: truncated header` |
| A version-1.3 setID/iCabinet pair, the reserve descriptor or the header reserve bytes extend past `cbCabinet` | `cab: truncated header` |
| reserved1, reserved2 or reserved3 is non-zero | `cab: reserved field set` |
| `cbCabinet` extends past the supplied buffer | `cab: truncated cabinet` |
| `cbCabinet` below the 32-byte fixed header | `cab: bad cabinet size` |
| A prev/next cabinet or disk string has no NUL before `cbCabinet` | `cab: truncated string` |
| The CFFOLDER array does not fit `cbCabinet` | `cab: folder directory overflow` |
| The minimal CFFILE directory does not fit `cbCabinet` | `cab: file directory overflow` |
| `cFiles > 0` and `coffFiles` is below the folder array end or above `cbCabinet` | `cab: coffFiles out of range` |
| A CFFILE entry's 16 fixed bytes cross `cbCabinet` | `cab: truncated file directory` |
| A CFFILE name has no NUL before `cbCabinet` | `cab: truncated name` |
| A name is empty, or a byte violates the printable/UTF policy | `cab: bad name` |
| A CFFILE `iFolder` is >= `cFolders` | `cab: bad folder index` |
| `coffCabStart > cbCabinet`, or the minimal CFDATA extent does not fit | `cab: folder data out of range` |
| `uoffFolderStart + cbFile` exceeds 2^32-1 | `cab: file span out of range` |
| `cab_build`: `names.len() != sizes.len()` | `cab: entry count mismatch` |
| `cab_build`: more than 65535 entries | `cab: too many files` |
| `cab_build`: a size is negative or above 2^32-1 | `cab: size overflow` |
| `cab_build`: empty name or byte outside 0x20..0x7E | `cab: bad name` |
| `cab_build`: name above 255 bytes | `cab: name too long` |

The same text is used in decode and encode where the condition is the same.
Parse validation is first-error-wins in the order listed for `cab_parse`.

## Complexity

| Operation | Complexity |
|---|---|
| `cab_parse` | O(data.len()) |
| all accessors and decoders | O(1) |
| `cab_build` | O(total name bytes) |

## Test plan

`tests/test_conformance.xi` (`module cab_tests`, 17 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Fixtures are assembled byte by byte in the test
file (little-endian helpers, `hdr`/`fent`/`file_ent` builders) so the parser
is exercised against bytes the test controls, not only against `cab_build`.
Coverage:

1. `cab_build` emits the exact pinned 88-byte canonical directory for
   `a.txt` (3 bytes) and `b.bin` (5 bytes); parsing pins size, version 1.3,
   flags 0, setID/iCabinet 0, one folder, two files, names, sizes, running
   offsets, folder 0, attribs 0x20, UTF false, folder start = 88, zero
   reserve lengths and header reserve offset 36;
2. version handling: `cab_version_has_setid` truth table; a 1.1 fixture
   parses with `set_id`/`i_cabinet` -1; 1.3 (setID 4660, iCabinet 7) and
   2.0 (setID 255, iCabinet 9) fixtures carry both fields;
3. signature/short-buffer errors: empty, `"MSC"`, `"MSCF"` + wrong byte ->
   `cab: bad signature`; 4- and 16-byte buffers -> `cab: truncated header`;
4. each of reserved1/reserved2/reserved3 set to 1 ->
   `cab: reserved field set`;
5. `cbCabinet` 89 > buffer -> `cab: truncated cabinet`; 31 ->
   `cab: bad cabinet size`; three trailing junk bytes beyond a valid
   cabinet are ignored;
6. reserve area: flags 1, `cbCFHeader` 4, `cbCFFolder` 2, `cbCFData` 3,
   four header reserve bytes and two folders with two reserve bytes each:
   reserved lengths, header reserve offset 40, folder reserve offsets 52/62,
   folder compressions 0/1 and the single file all read back;
7. prev/next flags 12 with four strings: folders/files parse, reserve offset
   pinned; a buffer cut inside the first string ->
   `cab: truncated string`;
8. name policy: control byte, DEL 0x7F, empty name and a 0xE9 byte without
   the UTF bit -> `cab: bad name`; the same 0xE9 byte with attribs 0x80 in a
   1.3 cabinet parses (name bytes preserved, UTF flag true); the identical
   bytes in a 1.1 cabinet -> `cab: bad name` (version gate); a cabinet cut
   inside the name -> `cab: truncated name`;
9. `iFolder` 1 and 65535 against one folder -> `cab: bad folder index`;
10. folder data span: `coffCabStart` 89 on an 88-byte cabinet, and
    `coffCabStart` 88 with `cCFData` 1 -> `cab: folder data out of range`;
    `coffCabStart` 80 with `cCFData` 1 parses;
11. `typeCompress` raw pass-through: folders with 0 and 259 (LZX + window
    bits) decode to codes 0/3; 0, 1, 2, 3, 16 are known and 15/negative are
    not; an unknown code 15 still parses with the raw word preserved;
12. packed DOS date/time: date 23866 -> 2026-09-26, time 25692 -> 12:34:56;
    zero decodes to 1980/0/0 and 0:00:00;
13. directory extents: 100 folders with an 8-byte folder area ->
    `cab: folder directory overflow`; 100 files with an empty file area ->
    `cab: file directory overflow`; `coffFiles` 43 and 89 on the canonical
    fixture -> `cab: coffFiles out of range`; a cut file directory ->
    `cab: truncated file directory`;
14. accessor sentinels: `-1` scalars, `""` names, `false` UTF flag,
    folder/file indices out of range;
15. two folders / three files fixture: folder starts 90/100, data counts
    2/1, compressions 1/3, file-to-folder mapping, sizes and offsets,
    attribs, UTF flag on an ASCII name, folder reserve offsets 44/52;
    `cbFile` 2^32-1 with offset 1 -> `cab: file span out of range`;
16. build validation: count mismatch, negative and 2^32 sizes, empty name,
    tab byte, 256-byte name -> the documented errors; a 255-byte name builds
    to 316 bytes and round-trips; a space is a printable name byte;
17. build -> parse -> build is byte-identical for sizes 0/1/1000, and an
    empty build is the pinned 44-byte cabinet with one dataless folder.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.cab
```

Last verified: compiler 0.61.3,
`port: PASS (passed=17 failed=0 program_exit=0 exit=0)`.

## Known limitations

- CFDATA is not parsed: `cbData`/`cbUncomp`/checksums are not validated and
  the compressed payload is never read. `cCFData` extents are only
  lower-bounded by their 8 + `cbCFData` byte headers.
- No decompression (MSZIP/Quantum/LZX) and no extraction; unknown
  compression codes parse on purpose.
- Prev/next cabinet and disk names are skipped, not stored; multi-cabinet
  sets are therefore indexable one cabinet at a time.
- `cab_build` emits dataless directories only: `cCFData` 0, no reserve
  areas, no prev/next links, version 1.3 with `setID`/`iCabinet` 0. The
  output is structurally valid and parses, but is not extractable.
- Builder names are capped at `CAB_MAX_NAME` (255) bytes and must be
  printable ASCII; the parser accepts longer names in principle (bounded
  only by `cbCabinet`) but the builder never emits them.
- The UTF policy accepts bytes 0x80..0xFF verbatim for 1.3+ cabinets with
  the attribute bit set; no UTF-8 sequence validation and no path
  sanitization is applied.
- The whole buffer and every parsed name live in memory; plain value types,
  no thread safety.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_archive`,
  `_err_archive`, `_ok_bytes`, `_err_bytes`, `_ok_int`, `_err_int`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- Every byte read from a `Vec[UInt8]` is widened with
  `(data[pos] as Int) & 0xFF` before entering arithmetic; multi-byte fields
  are assembled with multiplication (`_le16`, `_le32`), never shifts on
  values that can carry a sign bit.
- `CabArchive` (mixed scalar and parallel `Vec` fields) is constructed
  inside `cab_parse` and crosses function boundaries only by reference or
  through `_ok_archive`, following the `xiom.aiff` `AiffInfo` and
  `xiom.mbr` precedents.
- Str values read from `Vec[Str]` fields are bound to typed locals and
  compared through `xiom.string.compare.str_compare` only (BUG 17: `==` on
  such values lowers to a pointer comparison). `cab_file_name` documents
  this contract.
- A reference to a `Result` field (`&r.value`) can read stale data; every
  result is bound with `let x = r.value;` before use.
- Bit tests are written `(x & MASK) != 0` with explicit mask constants on
  values already masked to u8/u16 range; date/time decoding is arithmetic
  (`/`, `%`).
- The package declares no `extern "C"` blocks (no FFI).
