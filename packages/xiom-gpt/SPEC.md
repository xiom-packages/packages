# xiom.gpt -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.gpt`, version `0.1.0`).
Module: `src/gpt.xi` (`module xiom.gpt`).
Depends on `xiom.std` (`xiom.string`: `byte_at`; `Str::from_utf8` is a
compiler builtin). Tests additionally use `xiom.test`, `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex`.

## 1. Scope

A pure-XIOM (no FFI) structural codec for the GUID Partition Table (GPT):

- protective-MBR detection (`gpt_has_protective_mbr`) with the documented
  shape: 0x55AA signature at bytes 510..511 of LBA 0 and a single 0xEE
  partition entry in slot 0;
- `gpt_parse` reads the LBA-1 header, validates it and indexes the partition
  entry array into a `GptTable` of flat parallel vectors (one element per
  entry slot for type GUIDs, unique GUIDs, first LBAs, last LBAs,
  attributes and names);
- O(1) header/entry accessors (`gpt_revision`, `gpt_disk_guid`,
  `gpt_first_usable_lba`, `gpt_last_usable_lba`, `gpt_entry_count`,
  `gpt_type_guid`, `gpt_unique_guid`, `gpt_entry_first_lba`,
  `gpt_entry_last_lba`, `gpt_entry_attributes`, `gpt_entry_name`,
  `gpt_entry_in_use`, plus the remaining header readers);
- CRC-32 helpers: `gpt_crc32`, `gpt_crc32_range`, `gpt_header_crc_ok`,
  `gpt_entries_crc_ok`;
- `gpt_build` writes a canonical primary GPT (protective MBR + 92-byte
  header + zero-padded entry array) with recomputed header and entry-array
  CRCs.

The logical block size is fixed at 512 bytes. All APIs are buffer-in /
buffer-out: nothing touches the filesystem.

## 2. Non-goals

- **No backup-GPT consistency checks.** `backup_lba` is parsed and written
  as a number; the codec never reads, writes or compares a backup header or
  entry array.
- **No MBR partition semantics.** The protective MBR is only detected (and
  written by the builder); no other MBR entry type is interpreted, no
  boot/CHS logic, no hybrid MBR support.
- **No filesystem detection** and no partition content inspection.
- **No 4Kn / larger logical blocks.** Everything is expressed in 512-byte
  LBAs; a 4096-byte-sector image is out of scope.
- **No partition insertion/removal.** Parse and whole-array build only.
- **No UTF-16 validation beyond the documented ASCII projection**: surrogate
  pairs, RTL text and non-BMP characters are not decoded (see section 4.2).
- **No checksum enforcement on parse**: CRC mismatches are only reported by
  the explicit helpers (section 4.3).
- No FFI, no registry integration, no thread safety.

## 3. Disk layout

### 3.1 Protective MBR (LBA 0, bytes 0..511)

The documented detection shape (`gpt_has_protective_mbr`):

| Condition | Check |
|---|---|
| buffer length | `>= 512` |
| signature | bytes 510..511 are `0x55 0xAA` |
| slot 0 type | byte 450 (446 + 4) is `0xEE` |
| other slots | bytes 462..509 (slots 1..3) are all zero |

Nothing else is inspected: the start LBA, size and CHS bytes of slot 0 are
not validated. A false result means "not the documented shape"; it is not an
error channel. `gpt_parse` does not require the MBR and never looks at LBA 0.

The builder writes the canonical Linux-shape protective entry in slot 0:
status `0x00`, start CHS `00 02 00`, type `0xEE`, end CHS `FF FF FF`, start
LBA `1`, size `min(total_sectors - 1, 0xFFFFFFFF)`, then the 0x55AA
signature; all other MBR bytes are zero.

### 3.2 GPT header (LBA 1, bytes 512..1023)

Little-endian numerics; the header is 92 bytes and the remaining bytes of its
512-byte sector are ignored on parse.

| Header offset | Absolute | Size | Field | Rule |
|---|---|---|---|---|
| 0 | 512 | 8 | signature | Must be `EFI PART` (45 46 49 20 50 41 52 54). |
| 8 | 520 | 4 | revision | Stored raw; never validated. |
| 12 | 524 | 4 | header size | 92..512; the builder always writes 92. |
| 16 | 528 | 4 | header CRC32 | Raw value; see section 4.3. |
| 20 | 532 | 4 | reserved | Stored raw; the builder writes 0. |
| 24 | 536 | 8 | current LBA | Must be 1..2^63-1 (zero/negative rejected). |
| 32 | 544 | 8 | backup LBA | Must be 1..2^63-1 (not cross-checked). |
| 40 | 552 | 8 | first usable LBA | Must be 1..2^63-1. |
| 48 | 560 | 8 | last usable LBA | Must be 1..2^63-1 and `>= first usable`. |
| 56 | 568 | 16 | disk GUID | 16 raw bytes; exposed as 32 lowercase hex characters. |
| 72 | 584 | 8 | entries LBA | Must be 1..2^63-1; the array is located here. |
| 80 | 592 | 4 | entry count | 1..4096 (documented cap). |
| 84 | 596 | 4 | entry size | `>= 128` and a multiple of 8. |
| 88 | 600 | 4 | entries CRC32 | Raw value; see section 4.3. |

The 64-bit fields are accumulated little-endian into a signed `Int`; a value
with bit 63 set comes out negative and is rejected by the LBA checks
("gpt: bad LBA"). LBAs up to 2^63-1 are representable.

### 3.3 Partition entry array

Entry `i` starts at `entries_lba * 512 + i * entry_size`; the whole array
`entry_count * entry_size` bytes must fit in the buffer. Each entry has this
fixed 56-byte head followed by `entry_size - 56` name bytes:

| Entry offset | Size | Field |
|---|---|---|
| 0 | 16 | type GUID (all-zero = unused slot) |
| 16 | 16 | unique GUID |
| 32 | 8 | first LBA (LE64; negative rejected) |
| 40 | 8 | last LBA (LE64; negative rejected) |
| 48 | 8 | attributes (LE64, raw) |
| 56 | `entry_size - 56` | name, UTF-16LE (section 4.2) |

All-zero type-GUID slots (`00000000-0000-0000-0000-000000000000`) are legal
and are documented as unused: `gpt_parse` keeps them in the index and
`gpt_entry_in_use` reports them false. The builder accepts unused slots in
the middle of the vectors (a zero type GUID with zero LBAs), and it
zero-fills every slot between the last provided entry and `entry_count`.

## 4. Text and CRC policy

### 4.1 GUID text

Every GUID is exposed as the 32 lowercase hex characters of its 16 raw
on-disk bytes, with no byte-order rewriting (a canonical, hyphenated UUID
rendering is the caller's business). The builder accepts exactly 32 hex
characters per GUID (upper or lower case) and rejects anything else with
"gpt: bad guid"; `00000000000000000000000000000000` is the all-zero GUID.

### 4.2 Name decoding and encoding

Names are UTF-16LE. Decoding (`gpt_parse`, `gpt_entry_name`):

- code units are read little-endian in 2-byte steps until the end of the
  name field or the first `0x0000` code unit, whichever comes first;
- each code unit in `0x0020..0x007E` is kept as that ASCII character;
- every other code unit is replaced with `?` (0x3F), so a surrogate pair,
  a CJK character or a control byte all become one `?`; the terminator
  itself is never emitted;
- a name field with no `0x0000` yields the full printable projection (no
  error).

Encoding (`gpt_build`): each byte of the supplied ASCII name must be in
`0x20..0x7E`, and the name plus a terminating `0x0000` must fit, i.e.
`name.len() <= (entry_size - 56 - 2) / 2` (35 characters for the canonical
128-byte entry). Otherwise the build fails with "gpt: bad entry name". Each
character is written as one code unit (ASCII byte then `0x00`), and the rest
of the field is zero.

### 4.3 CRC-32

The module implements the standard CRC-32 locally (IEEE 802.3 / zlib /
PKZIP): reflected polynomial `0xEDB88320`, init `0xFFFFFFFF`, reflected
input/output, final xor `0xFFFFFFFF`. It is table-free and bitwise; the
check value for `"123456789"` is `0xCBF43926` = 3421780262 and the empty
buffer is 0.

- `gpt_parse` copies both stored CRC fields into the table raw and **never**
  rejects or reports a mismatch. The caller verifies explicitly:
- `gpt_header_crc_ok` recomputes the CRC over the recorded `header_size`
  bytes at byte 512 **with the 4 HeaderCRC32 bytes treated as zero** (the
  UEFI rule that the field is not part of its own computation) and compares
  it with the stored value;
- `gpt_entries_crc_ok` recomputes the CRC over the recorded
  `entry_count * entry_size` bytes at `entries_lba * 512` (no zeroing) and
  compares it with the stored value; both helpers return `false` when the
  recorded ranges are malformed or do not fit the buffer;
- `gpt_build` computes the entry-array CRC over the raw array and the header
  CRC with its own field still zero, then patches both fields.

## 5. Validation order

`gpt_parse` (first failure wins):

1. `data.len() < 1024` -> `gpt: truncated header`.
2. Signature at 512..519 not `EFI PART` -> `gpt: bad signature`.
3. `header_size < 92` or `header_size > 512` -> `gpt: bad header size`.
4. (A defensive `512 + header_size > data.len()` check follows; with the
   1024-byte precondition and the 92..512 range it can never fire.)
5. `current_lba`, `backup_lba`, `first_usable_lba`, `last_usable_lba` or
   `entries_lba` zero or negative (bit 63 set) -> `gpt: bad LBA`.
6. `first_usable_lba > last_usable_lba` -> `gpt: bad usable range`.
7. `entry_size < 128` or `entry_size % 8 != 0` -> `gpt: bad entry size`.
8. `entry_count < 1` or `entry_count > 4096` -> `gpt: bad entry count`.
9. `entries_lba > data.len() / 512`, or
   `entry_count * entry_size > data.len() - entries_lba * 512` ->
   `gpt: truncated entries` (the division form keeps the products safe; with
   the 4096 cap and a 32-bit entry size the product is below 2^44).
10. Per entry, in array order: `first_lba < 0` or `last_lba < 0` ->
    `gpt: bad LBA`.

`entry_count` and `entry_size` are validated before the array bound, so an
oversized count is reported as `gpt: bad entry count` even on a short
buffer. Bytes after the array are ignored, so a buffer may hold LBA 0
up to the array only.

## 6. Builder rules and canonical output

`gpt_build(t, total_sectors)` validates in this order: revision in
`0..2^32-1` -> `gpt: bad revision`; entry size in `128..2^32-1` and a
multiple of 8 -> `gpt: bad entry size`; declared entry count in `1..4096` ->
`gpt: bad entry count`; the six entry vectors equal in length ->
`gpt: entry vector mismatch`; declared count >= vector length ->
`gpt: entry count too small`; the disk GUID -> `gpt: bad guid`; per entry
the two GUIDs -> `gpt: bad guid`, negative or `first > last` LBAs ->
`gpt: bad entry LBA`, the name (section 4.2) -> `gpt: bad entry name`; the
disk size: `total_sectors <= 0` or `last_usable < first_usable` ->
`gpt: disk too small`.

Geometry (512-byte sectors; `entry_bytes = entry_count * entry_size`,
`entry_sectors = ceil(entry_bytes / 512)`):

| Field | Value |
|---|---|
| image length | `1024 + entry_bytes` |
| current LBA | 1 |
| backup LBA | `total_sectors - 1` |
| first usable LBA | `2 + entry_sectors` |
| last usable LBA | `backup_lba - 1 - entry_sectors` |
| entries LBA | 2 |
| header size | 92 (canonical) |
| reserved | 0 |

The first `n` slots come from the vectors; slots `n..entry_count` are
written as all-zero entries. Both CRC fields are patched (section 4.3).
Only the primary GPT is emitted: the result is not padded to
`total_sectors`, and no backup header/array is written even though
`backup_lba` points at one. `header_crc`, `reserved`, `current_lba`,
`backup_lba`, `first_usable_lba`, `last_usable_lba`, `entries_lba` and
`entries_crc` of `t` are therefore ignored.

## 7. API signatures

All functions are free functions in module `xiom.gpt` (no self methods):

```xi
pub type GptTable = {
  revision: Int; header_size: Int; header_crc: Int; reserved: Int;
  current_lba: Int; backup_lba: Int; first_usable_lba: Int;
  last_usable_lba: Int; disk_guid: Str; entries_lba: Int;
  entry_count: Int; entry_size: Int; entries_crc: Int;
  type_guids: Vec[Str]; unique_guids: Vec[Str];
  first_lbas: Vec[Int]; last_lbas: Vec[Int];
  attributes: Vec[Int]; names: Vec[Str];
}

pub fn gpt_has_protective_mbr(data: &Vec[UInt8]) -> Bool
pub fn gpt_crc32(data: &Vec[UInt8]) -> Int
pub fn gpt_crc32_range(data: &Vec[UInt8], start: Int, count: Int) -> Int
pub fn gpt_header_crc_ok(data: &Vec[UInt8], t: &GptTable) -> Bool
pub fn gpt_entries_crc_ok(data: &Vec[UInt8], t: &GptTable) -> Bool
pub fn gpt_parse(data: &Vec[UInt8]) -> Result[GptTable, Str]
pub fn gpt_revision(t: &GptTable) -> Int
pub fn gpt_header_size(t: &GptTable) -> Int
pub fn gpt_header_crc(t: &GptTable) -> Int
pub fn gpt_reserved(t: &GptTable) -> Int
pub fn gpt_current_lba(t: &GptTable) -> Int
pub fn gpt_backup_lba(t: &GptTable) -> Int
pub fn gpt_first_usable_lba(t: &GptTable) -> Int
pub fn gpt_last_usable_lba(t: &GptTable) -> Int
pub fn gpt_disk_guid(t: &GptTable) -> Str
pub fn gpt_entries_lba(t: &GptTable) -> Int
pub fn gpt_entry_size(t: &GptTable) -> Int
pub fn gpt_entries_crc(t: &GptTable) -> Int
pub fn gpt_entry_count(t: &GptTable) -> Int
pub fn gpt_type_guid(t: &GptTable, i: Int) -> Str
pub fn gpt_unique_guid(t: &GptTable, i: Int) -> Str
pub fn gpt_entry_first_lba(t: &GptTable, i: Int) -> Int
pub fn gpt_entry_last_lba(t: &GptTable, i: Int) -> Int
pub fn gpt_entry_attributes(t: &GptTable, i: Int) -> Int
pub fn gpt_entry_name(t: &GptTable, i: Int) -> Str
pub fn gpt_entry_in_use(t: &GptTable, i: Int) -> Bool
pub fn gpt_build(t: &GptTable, total_sectors: Int) -> Result[Vec[UInt8], Str]
```

## 8. Semantics of the accessors

- **Header readers** (`gpt_revision`, `gpt_header_size`, `gpt_header_crc`,
  `gpt_reserved`, `gpt_current_lba`, `gpt_backup_lba`,
  `gpt_first_usable_lba`, `gpt_last_usable_lba`, `gpt_disk_guid`,
  `gpt_entries_lba`, `gpt_entry_size`, `gpt_entries_crc`) are O(1) and
  infallible.
- **`gpt_entry_count`** is the minimum of the declared header count and the
  six entry-vector lengths, so index-based access is safe even for a
  hand-built table whose parallel vectors drifted; a parsed table reports the
  header count.
- **Entry readers** guard their own vector: `gpt_type_guid`,
  `gpt_unique_guid` and `gpt_entry_name` return `""`, `gpt_entry_first_lba`
  and `gpt_entry_last_lba` return `-1`, and `gpt_entry_attributes` returns
  `0` for an index that is negative or beyond that particular vector (which
  can be past `gpt_entry_count` on a drifted table).
- **`gpt_entry_attributes`** returns the raw 64-bit flags; bit 63 set makes
  the value negative (documented 64-bit limitation), and the value
  round-trips through `gpt_build` unchanged because the writer emits the low
  64 bits.
- **`gpt_entry_in_use`** is true only when the stored type GUID text is
  exactly 32 characters and not the all-zero GUID; a malformed or shorter
  string is "not in use" rather than an error.
- **`gpt_crc32_range`** returns `-1` for a negative `start`/`count` or a span
  that does not fit; a zero-length span at `data.len()` returns `0`.
- **`gpt_header_crc_ok`** / **`gpt_entries_crc_ok`** are boolean and
  bounds-checked; they are the only places a CRC mismatch is reported.
- **`gpt_build`** derives every header field it ignores (section 6) and
  zero-fills unused slots.

## 9. Error string catalog

| Condition | Error text |
|---|---|
| Buffer shorter than 1024 bytes (the defensive header bound above) | `gpt: truncated header` |
| Header signature not `EFI PART` | `gpt: bad signature` |
| `header_size < 92` or `> 512` | `gpt: bad header size` |
| Header LBA field zero or negative; per-entry LBA negative | `gpt: bad LBA` |
| `first_usable_lba > last_usable_lba` | `gpt: bad usable range` |
| `entry_size < 128` or not a multiple of 8, or a build entry size outside `128..2^32-1` | `gpt: bad entry size` |
| `entry_count` outside `1..4096` | `gpt: bad entry count` |
| Entry array (or a declared entry) past the buffer end | `gpt: truncated entries` |
| Build revision outside `0..2^32-1` | `gpt: bad revision` |
| Build GUID string that is not exactly 32 hex characters | `gpt: bad guid` |
| Build name byte outside printable ASCII, or too long for the field | `gpt: bad entry name` |
| Build entry vectors of different lengths | `gpt: entry vector mismatch` |
| Build declared count smaller than the provided vector length | `gpt: entry count too small` |
| Build entry `first_lba < 0`, `last_lba < 0`, or `first_lba > last_lba` | `gpt: bad entry LBA` |
| Build disk too small for the primary array plus the backup region | `gpt: disk too small` |

## 10. Complexity

| Operation | Complexity |
|---|---|
| `gpt_has_protective_mbr` | O(1) |
| `gpt_parse` | O(entry_count * entry_size) |
| `gpt_entry_count`, all header readers | O(1) |
| `gpt_type_guid` / `gpt_unique_guid` / `gpt_entry_name` / `gpt_entry_in_use` | O(1) |
| `gpt_entry_first_lba` / `gpt_entry_last_lba` / `gpt_entry_attributes` | O(1) |
| `gpt_crc32` / `gpt_crc32_range` | O(count) |
| `gpt_header_crc_ok` | O(header_size) |
| `gpt_entries_crc_ok` | O(entry_count * entry_size) |
| `gpt_build` | O(entry_count * entry_size) |

## 11. Test plan

`tests/test_conformance.xi` (`module gpt_tests`, 17 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check and returns the failure
count). Fixtures are assembled byte by byte, so `gpt_parse` is exercised
against bytes the test controls, not only against `gpt_build`. Coverage:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | protective MBR | shape accepted; bad signature, non-0xEE slot 0, occupied slot 1 and a 511-byte buffer rejected |
| t2 | header scalars | revision, sizes, LBAs, usable range, disk GUID text (re-encoded through `xiom.encoding.hex`) and both stored CRCs |
| t3 | entries | type/unique GUID text, first/last LBA, attributes, name, in-use predicate and an all-zero unused slot |
| t4 | names | NUL stops the scan; `0x20..0x7E` kept; U+00E9, U+4E2D, DEL and 0x1F become `?`; a full unterminated field decodes |
| t5 | CRC-32 | `"123456789"` = 3421780262; empty = 0; range guards return -1 |
| t6 | CRC helpers | valid fixture verifies; a changed reserved byte fails the header CRC; a changed entry byte fails the entries CRC; parse still succeeds on both (no CRC enforcement) |
| t7 | parse errors (header) | short buffer, bad signature, header size 91/513, zeroed current/entries/first-usable/last-usable, usable range inversion |
| t8 | parse errors (entries) | entry size 127/132, count 0/4097, truncated array, far entries LBA, negative entry LBA |
| t9 | builder round trip | length, geometry (3/2045/2047), four slots with two unused, names, in-use pattern, CRC helpers and byte-identical rebuild |
| t10 | builder bytes | MBR fields, signature, revision/sizes/LBAs, CRC fields, disk GUID bytes, entry type GUID bytes, UTF-16LE name bytes and zero-filled unused slots |
| t11 | builder shape errors | bad revision, short/non-hex GUID, entry size 127/132, count 0/4097, disk too small (small disk, zero sectors) |
| t12 | builder entry errors | vector mismatch, count too small, 40-char name, first > last, negative first LBA, non-hex entry GUID |
| t13 | out-of-range accessors | `""` / `-1` / `0` / `false` at negative and past-the-vector indices |
| t14 | drifted vectors | per-vector guards still read; `gpt_entry_count` reports the safe minimum; build rejects |
| t15 | entries LBA | an array at LBA 3 is located through the header field and both CRC helpers verify |
| t16 | canonical 128 slots | 16 KiB array, first usable 34, last usable 2014, zero-filled tail, byte-identical rebuild |
| t17 | 64-bit fields | 2^32/2^33 LBAs and a 2^62 attribute round-trip; a built image with 2^32-1 MBR sectors keeps backup LBA 2^32 |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.gpt
```

Last verified: compiler 0.61.3,
`port: PASS (passed=17 failed=0 program_exit=0 exit=0)`.

## 12. Known limitations

- **Primary GPT only.** `gpt_build` writes the protective MBR, the LBA-1
  header and the entry array; no backup header/array is emitted and
  `backup_lba` is only a number. `gpt_parse` never compares primary and
  backup.
- **Fixed 512-byte logical blocks.** 4Kn images are out of scope.
- **CRCs are opt-in.** `gpt_parse` returns whatever is stored; callers must
  invoke `gpt_header_crc_ok` / `gpt_entries_crc_ok` to detect corruption.
- **UUID text is raw hex.** The 32-character form is the on-disk byte order,
  not the canonical hyphenated mixed-endian UUID; every GUID (disk, type,
  unique) is rendered the same way.
- **ASCII-only names.** Decoding projects UTF-16LE to `0x20..0x7E` and maps
  everything else (including surrogate pairs) to `?`; encoding accepts only
  printable ASCII. Non-BMP and RTL names do not survive a round trip.
- **64-bit signed range.** Fields with bit 63 set come out negative; the LBA
  checks reject them, while attributes are stored raw and can be negative.
- **Builder layout is unaligned.** Entries start at LBA 2 with no 1 MiB
  alignment policy, and `first_usable_lba` is simply the first LBA after the
  array; images are not padded to `total_sectors`.
- **No MBR semantics, no filesystem detection, no partition editing.**
- Not thread-safe; `GptTable` is a plain value type holding six parallel
  vectors (no `Vec` of structs).

## 13. Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_table`,
  `_err_table`, `_ok_bytes`, `_err_bytes`; every other function returns
  through one of them.
- Every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8 values
  are never compared against Int constants without widening.
- 64-bit fields use the xiom.bson `_read_le_int64` accumulator shape
  (`v = v * 256 + byte`, most significant byte last), whose two's-complement
  wrap is documented above.
- CRC-32 is table-free and bitwise; `&` is only ever applied with the small
  masks 1 and 0xFF (the large-mask AND bug does not apply).
- The builder's CRC patching goes through `_seal_crc` / `_seal_header_crc`,
  which compute and patch inside one helper so the mutable reference is
  never held across two borrows of the same buffer (avoids the advisory
  E001 warning while keeping the write exact).
- Str values read from `Vec[Str]` fields are bound to typed locals and never
  compared with `==` (BUG 17); the module performs no string equality at
  all, and the tests use `xiom.string.compare.str_compare`.
- All `&mut Vec[UInt8]` calls pass `&mut` at the call site; nested helpers
  receive the existing reference (aiff/tar precedent).
- Accessors verify their own parallel vector before indexing, so a
  hand-built `GptTable` with drifted vectors cannot read out of bounds.
- **Malformed bracket audit:** v0.61.3 silently accepts `Vec<UInt8>` /
  `Result<...>` in parameter and local type positions (wave-20
  trap-14 extension). Both files were grep-audited for `Vec<` / `Result<`
  after writing and the occurrences found were fixed before the green run.
