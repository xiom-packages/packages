# xiom.mbr -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.mbr`, version `0.1.0`).
Module: `src/mbr.xi` (`module xiom.mbr`).
Depends on `xiom.std` (`>=0.60.0 <1.0.0`); the module imports nothing from
it (plain arithmetic and byte moves only). Tests additionally use
`xiom.test`, `xiom.io` and `xiom.string.compare`.

## 1. Scope

A pure-XIOM (no FFI) structural codec for the Master Boot Record: the
canonical 512-byte sector at LBA 0 of a partitioned disk.

- `mbr_parse` validates the sector length, the 0x55AA boot signature, the
  four boot flags and the documented type/LBA consistency policy, then
  returns an `Mbr` of flat parallel vectors: raw boot code, raw disk-area
  bytes and one element per entry slot for boot flags, packed raw CHS
  triples (start and end), type codes, LBA starts and LBA sector counts;
- `mbr_parse_sized` adds the optional disk-size bound for in-use entries;
- O(1) accessors for every entry field: boot flag/bootable, raw type and
  documented type name, packed raw CHS plus the decoded head/sector/cylinder,
  LBA start and LBA count, and the in-use predicate;
- `mbr_signature` / `mbr_signature_ok` for the 0x55AA check;
- `mbr_entries_overlap` / `mbr_has_overlap` for the documented pairwise
  extent-overlap check;
- `mbr_build` writes a canonical 512-byte sector with a recomputed
  signature.

All APIs are buffer-in / buffer-out: nothing touches the filesystem.

## 2. Non-goals

- **No extended partitions / EBR chains.** Only the four primary 16-byte
  entries of LBA 0 are read or written; logical partitions and the EBR
  sectors they live in are out of scope.
- **No GPT.** The 0xEE protective entry is only named, never interpreted;
  the GPT itself is the sibling `xiom.gpt`.
- **No boot code semantics.** The boot code span is preserved raw and never
  disassembled, validated or executed.
- **No filesystem detection.** Type bytes are named through the documented
  partial table; partition contents are never inspected.
- **No CHS/LBA cross-validation** beyond the type 0 policy: CHS triples are
  preserved and decoded but never checked against the LBA fields, and zero
  CHS is explicitly tolerated.
- **No disk-size assumption in `mbr_parse`**: LBA ranges are only bounded
  when a size is supplied through `mbr_parse_sized`.
- **No boot-sector checksum / disk signature interpretation.** The six
  bytes at 0x1B8..0x1BD are preserved but never read as a number.
- No partition editing, no serialization beyond the 512-byte sector, no
  registry integration, no thread safety.

## 3. Byte layout

The sector is exactly 512 bytes; all fields are little-endian where numeric.

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0x000 | 440 | boot code span | Preserved raw, never interpreted (`mbr_boot_code_span`). |
| 0x1B8 | 4 | disk signature | Optional Windows disk signature; preserved raw inside `disk_area`. |
| 0x1BC | 2 | reserved | Preserved raw inside `disk_area`. |
| 0x1BE + 16*i | 16 | partition entry `i` (`i` = 0..3) | See 3.1. |
| 0x1FE | 2 | boot signature | Must be the byte sequence `0x55 0xAA` -> `mbr_signature_ok`. |

Bytes after 0x1FF are ignored on parse; a build always emits exactly 512
bytes.

### 3.1 Partition entry (16 bytes)

| Entry offset | Absolute (entry 0) | Size | Field | Rule |
|---|---|---|---|---|
| 0 | 0x1BE | 1 | boot flag | Must be `0x00` (inactive) or `0x80` (active); anything else is `mbr: bad boot flag`. |
| 1 | 0x1BF | 3 | start CHS | Raw triple (head, sector/cylinder-high, cylinder-low); preserved, never validated. |
| 4 | 0x1C2 | 1 | type | Raw byte; `0x00` = unused. Named by the partial table (section 5); unknown values pass through. |
| 5 | 0x1C3 | 3 | end CHS | Raw triple; preserved, never validated. |
| 8 | 0x1C6 | 4 | LBA start | LE32, 0..2^32-1. |
| 12 | 0x1CA | 4 | LBA count | LE32, 0..2^32-1. |

### 3.2 CHS encoding

A CHS triple is stored raw as the three bytes `b0` (head), `b1`, `b2` and
exposed as the packed 24-bit value `head * 65536 + b1 * 256 + b2`. The
documented decoded form is:

| Component | Range | Decode |
|---|---|---|
| head | 0..255 | `p / 65536` |
| sector | 0..63 | `(p / 256) % 256 % 64` (low 6 bits of `b1`) |
| cylinder | 0..1023 | `((p / 256) % 256 / 64) * 256 + p % 256` (high 2 bits of `b1` plus `b2`) |

The decode is lossless: re-encoding head, sector and cylinder reproduces the
three raw bytes exactly. `xiom.mbr` therefore stores the packed raw value
and decodes on demand; no encoded value is ever dropped or normalized.

## 4. Policies

### 4.1 Type / LBA consistency

- A type byte of `0x00` marks an unused slot and implies **zero LBA
  fields**: both LBA start and LBA count must be `0`, otherwise `mbr_parse`
  and `mbr_build` fail with `mbr: unused entry not zero`. CHS bytes of an
  unused entry are *not* constrained and are preserved as stored.
- A non-zero type with zero LBA fields is tolerated (a degenerate or
  CHS-only entry); the codec reports it as in use and its extent as empty.
- A non-zero type with `lba_count == 0` is a zero-length extent: it is in
  use, covers nothing, and cannot overlap another entry.

### 4.2 CHS tolerance

CHS is never cross-checked against LBA. All-zero CHS on an in-use entry with
LBA fields set is legal and common (LBA-only partitioning), and the
0xFFFFFF style filler (`head 254`, `sector 63`, `cylinder 1023`) is
preserved exactly. The decoded accessors report stored values only.

### 4.3 Disk size

`mbr_parse` assumes no disk geometry. The opt-in `mbr_parse_sized` requires
`total_sectors >= 1` and, for every entry with a non-zero type, checks
`lba_start + lba_count <= total_sectors`; a violating entry yields
`mbr: entry beyond disk`. Unused entries are skipped. The sum is computed in
signed 64-bit `Int` (two u32 fields, at most 2^33 - 2) and cannot overflow.
There is no requirement that a partition avoid LBA 0.

### 4.4 Overlap detection

`mbr_entries_overlap(m, a, b)` uses the half-open extents
`[lba_start, lba_start + lba_count)`. It is false when either index is
negative or out of range, when `a == b`, when either entry is not in use
(type `0x00`) and when either count is zero. `mbr_has_overlap` checks all
six pairs `(0,1) (0,2) (0,3) (1,2) (1,3) (2,3)` within
`mbr_entry_count`. Adjacency (`end == next start`) is not an overlap.

## 5. Partition type name table

The table is deliberately partial; unknown in-range values pass through and
are reported as `"unknown"` while the raw byte stays available from
`mbr_entry_type`.

| Code | Name |
|---|---|
| 0x00 | `unused` |
| 0x07 | `NTFS/exFAT` |
| 0x0B | `FAT32 (CHS)` |
| 0x0C | `FAT32 (LBA)` |
| 0x82 | `Linux swap` |
| 0x83 | `Linux` |
| 0x8E | `Linux LVM` |
| 0xEE | `GPT protective` |
| 0xEF | `EFI system` |
| other 0..255 | `unknown` |
| outside 0..255 | `""` |

## 6. Validation order

`mbr_parse` (first failure wins):

1. `data.len() < 512` -> `mbr: truncated sector`.
2. bytes 0x1FE..0x1FF not `0x55 0xAA` -> `mbr: bad signature`.
3. per entry, in slot order 0..3: boot flag not `0x00`/`0x80` ->
   `mbr: bad boot flag`; type `0x00` with a non-zero LBA start or count ->
   `mbr: unused entry not zero`.

`mbr_parse_sized` = the above, then `total_sectors <= 0` ->
`mbr: bad disk size`, then per in-use entry the range bound of 4.3.

`mbr_build` (first failure wins):

1. `boot_code.len() != 440` -> `mbr: bad boot code`.
2. `disk_area.len() != 6` -> `mbr: bad disk area`.
3. the six entry vectors differ in length -> `mbr: entry vector mismatch`.
4. common length > 4 -> `mbr: bad entry count`.
5. per entry: flag -> `mbr: bad boot flag`; type outside 0..255 ->
   `mbr: bad entry type`; type `0x00` with a non-zero LBA field ->
   `mbr: unused entry not zero`; either CHS triple outside 0..0xFFFFFF ->
   `mbr: bad CHS`; either LBA field outside 0..2^32-1 -> `mbr: bad LBA`.

## 7. API signatures

All functions are free functions in module `xiom.mbr` (no self methods):

```xi
pub type Mbr = {
  boot_code: Vec[UInt8]; disk_area: Vec[UInt8];
  boot_flags: Vec[Int]; start_chs: Vec[Int]; types: Vec[Int];
  end_chs: Vec[Int]; lba_starts: Vec[Int]; lba_counts: Vec[Int];
}

pub fn mbr_parse(data: &Vec[UInt8]) -> Result[Mbr, Str]
pub fn mbr_parse_sized(data: &Vec[UInt8], total_sectors: Int) -> Result[Mbr, Str]
pub fn mbr_signature(data: &Vec[UInt8]) -> Int
pub fn mbr_signature_ok(data: &Vec[UInt8]) -> Bool
pub fn mbr_boot_code_span(m: &Mbr) -> Vec[UInt8]
pub fn mbr_disk_area_span(m: &Mbr) -> Vec[UInt8]
pub fn mbr_entry_count(m: &Mbr) -> Int
pub fn mbr_type_name(code: Int) -> Str
pub fn mbr_entry_boot_flag(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_bootable(m: &Mbr, i: Int) -> Bool
pub fn mbr_entry_type(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_type_name(m: &Mbr, i: Int) -> Str
pub fn mbr_entry_start_chs(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_start_chs_head(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_start_chs_sector(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_start_chs_cylinder(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_end_chs(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_end_chs_head(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_end_chs_sector(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_end_chs_cylinder(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_lba_start(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_lba_count(m: &Mbr, i: Int) -> Int
pub fn mbr_entry_in_use(m: &Mbr, i: Int) -> Bool
pub fn mbr_entries_overlap(m: &Mbr, a: Int, b: Int) -> Bool
pub fn mbr_has_overlap(m: &Mbr) -> Bool
pub fn mbr_build(m: &Mbr) -> Result[Vec[UInt8], Str]
```

## 8. Semantics of the accessors

- **Raw spans** (`mbr_boot_code_span`, `mbr_disk_area_span`) return fresh
  copies of the preserved bytes: 440 and 6 bytes respectively for a parsed
  table, and whatever the table holds for a hand-built one (the builder
  insists on exactly 440/6).
- **`mbr_signature`** returns the two signature bytes as a little-endian
  UInt16, or `-1` when the buffer is shorter than 512. The canonical byte
  sequence `0x55 0xAA` reads `0xAA55` = 43605; the wrong order reads
  `0x55AA` = 21930. `mbr_signature_ok` is the normative check (exact bytes,
  length >= 512).
- **`mbr_entry_count`** is the minimum length of the six parallel entry
  vectors, so index-based access is safe even for a hand-built table whose
  vectors drifted; a parsed table reports 4. A table whose vectors have more
  than four elements reports the minimum (the builder rejects it with
  `mbr: bad entry count`).
- **Entry readers guard their own vector**: `Int` readers return `-1` and
  the `Str` reader returns `""` for `i < 0` or `i >=` the length of that
  particular vector; `mbr_entry_bootable` and `mbr_entry_in_use` return
  `false` for out-of-range `i`. The decoded CHS readers additionally return
  `-1` when the stored packed triple is negative (a hand-built value the
  accessors refuse to decode).
- **`mbr_entry_in_use`** is true exactly when the type byte is not `0x00`.
- **`mbr_build`** ignores nothing except a stored signature (there is no
  signature field: the two bytes are always recomputed). `n` provided
  entries are written in order; slots `n..3` are all-zero unused entries;
  the result is always 512 bytes. A build of the fixture table is
  byte-identical to the fixture (t10).

## 9. Error string catalog

| Condition | Error text |
|---|---|
| Buffer shorter than 512 bytes | `mbr: truncated sector` |
| Bytes 0x1FE..0x1FF are not `0x55 0xAA` | `mbr: bad signature` |
| A boot flag is not `0x00` or `0x80` | `mbr: bad boot flag` |
| Type `0x00` entry with a non-zero LBA start or count (parse or build) | `mbr: unused entry not zero` |
| `mbr_parse_sized` with `total_sectors <= 0` | `mbr: bad disk size` |
| An in-use entry extends past `total_sectors` | `mbr: entry beyond disk` |
| Build `boot_code` is not exactly 440 bytes | `mbr: bad boot code` |
| Build `disk_area` is not exactly 6 bytes | `mbr: bad disk area` |
| Build entry vectors differ in length | `mbr: entry vector mismatch` |
| Build common vector length exceeds 4 | `mbr: bad entry count` |
| Build type byte outside 0..255 | `mbr: bad entry type` |
| Build CHS triple outside 0..0xFFFFFF | `mbr: bad CHS` |
| Build LBA field outside 0..2^32-1 | `mbr: bad LBA` |

## 10. Complexity

| Operation | Complexity |
|---|---|
| `mbr_parse` / `mbr_parse_sized` | O(512) |
| `mbr_signature` / `mbr_signature_ok` | O(1) |
| `mbr_boot_code_span` | O(440) |
| `mbr_disk_area_span` | O(6) |
| `mbr_entry_count`, all entry accessors, `mbr_type_name` | O(1) |
| `mbr_entries_overlap` | O(1) |
| `mbr_has_overlap` | O(1) (at most six pairs) |
| `mbr_build` | O(512) |

## 11. Test plan

`tests/test_conformance.xi` (`module mbr_tests`, 18 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check and returns the
failure count). Fixtures are assembled byte by byte, so `mbr_parse` is
exercised against bytes the test controls, not only against `mbr_build`.
Coverage:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | signature | 0x55AA accepted; both single-byte corruptions and the swapped pair rejected; raw LE16 43605/21930; 511-byte and empty buffers -> `-1`/false |
| t2 | raw spans | 440-byte boot code and 6-byte disk area preserved byte-for-byte (non-zero pattern/disk signature) |
| t3 | entry basics | flag 0x80/0x00, bootable, raw type, type name, in-use predicate |
| t4 | CHS | packed raw triples 65792/16711679 decode to head 1/254, sector 1/63, cylinder 0/1023; a high-cylinder entry (head 2, sector 5, cylinder 683; end 3/40/1000) |
| t5 | LBA | start 2048 / count 1024 and a u32-maximum round trip |
| t6 | type names | all nine documented names, unknown in-range -> `"unknown"`, negative and 256 -> `""`, entry-level unknown pass-through |
| t7 | parse errors | short buffers, bad signature (two forms), bad flag in two slots, type 0 with non-zero start/count within either byte lane |
| t8 | CHS tolerance | zero CHS + set LBA parses; an unused entry's non-zero CHS byte is preserved |
| t9 | sized parse | boundary `start + count == total` accepted, one sector less rejected, zero/negative disk size, structural error precedence, unused entries unbounded, zero-length extent at its start |
| t10 | round trip | the one-Linux + unused fixture: `mbr_build` output is byte-identical to the fixture and parse -> build is byte-stable |
| t11 | builder bytes | entry layout, zero fill of slots 1..3, raw spans, recomputed 0x55AA |
| t12 | four slots | Linux/unused/NTFS/unused pattern and a short two-entry input whose slots 2..3 are zero-filled |
| t13 | builder shape errors | boot code 439, disk area 5, vector mismatch, five entries |
| t14 | builder value errors | flag 0x7F, type -1/256, unused-not-zero (start and count), CHS -1/0x1000000 (start and end), LBA -1/2^32 (start and count) |
| t15 | overlap | intersecting pair (both orders), adjacency, zero-length, unused, `a == b`, negative and past-end indices, single-entry table |
| t16 | real types | 0xEE protective and 0x8E Linux LVM entries parse, name and rebuild; sized bound at the u32 edge |
| t17 | drifted vectors | `entry_count` reports the safe minimum; per-vector guards; build rejects the drift |
| t18 | out of range | every accessor returns `-1`/`""`/false at `i = -1` and past the vector |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.mbr
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## 12. Known limitations

- **Primary MBR only.** No EBR/extended-partition chains, no logical
  partitions and no more than the four fixed 16-byte slots.
- **No GPT.** The protective 0xEE entry is named only; GPT structures are
  the sibling `xiom.gpt`'s scope.
- **No boot code semantics.** The boot code and disk-area bytes are opaque,
  preserved data.
- **No filesystem detection.** Type names come from a partial table; no
  content is inspected.
- **CHS is not cross-validated with LBA.** Zero and filler CHS values are
  preserved and decoded as stored; the codec never re-encodes a decoded
  value on top of a different one (decode is lossless by construction).
- **Disk bounds are opt-in.** `mbr_parse` accepts entries of any LBA range;
  only `mbr_parse_sized` applies a disk size, and it does not exclude LBA 0.
- **Overlap is a helper, not a rejection.** `mbr_parse` accepts overlapping
  entries; callers decide with `mbr_has_overlap`.
- **The disk signature is not surfaced as a number**, only preserved in the
  6-byte `disk_area` span (4 signature bytes + 2 reserved).
- Whole-sector API: one 512-byte buffer in memory; plain value types only;
  not thread-safe.

## 13. Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_table`,
  `_err_table`, `_ok_bytes`, `_err_bytes`; every other function returns
  through one of them.
- Every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8 values
  are never compared against Int constants without widening.
- No `Vec` of structs is used; the entries are six flat parallel vectors and
  `_vecs_equal` / `_vecs_min` keep them honest, with per-vector guards in
  every accessor.
- CHS decoding uses division and modulo only, so no bitwise operator ever
  sees a sign-bit-set value; the writer's byte extraction uses the
  arithmetic `_byte_at` shape (gpt/bson precedent).
- Str values are never compared with `==` in the module (it performs no
  string equality at all); the tests use `xiom.string.compare.str_compare`
  and bind every `&` argument to a local.
- All `&mut Vec[UInt8]` calls pass `&mut` at the call site and receive the
  existing reference in nested helpers.
- **Malformed bracket audit:** v0.61.3 silently accepts `Vec<UInt8>` /
  `Result<...>` in parameter and local type positions. The first test run
  caught one such parameter (`push_entry`) because the angle-bracket grep
  was run before the compile; both files are grep-clean now.
