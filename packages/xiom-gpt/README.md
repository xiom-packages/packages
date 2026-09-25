# xiom.gpt

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** GUID Partition Table (GPT) codec: protective-MBR detection, the
> LBA-1 header, the partition entry array and a canonical builder for the
> primary GPT.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`). Tests
> additionally use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.gpt` reads and writes the structural part of a GUID Partition Table on
512-byte logical blocks. `gpt_parse` validates the LBA-1 header (signature,
header size, the 64-bit LBA fields, usable range, entry size/count, entry
array bounds) and indexes the partition entry array into a `GptTable` of flat
parallel vectors: one element per entry slot for type GUIDs, unique GUIDs,
first LBAs, last LBAs, attributes and decoded names. All-zero type-GUID slots
are legal and stay in the index; `gpt_entry_in_use` separates used entries
from unused ones.

GUIDs are surfaced as the 32 lowercase hex characters of their 16 raw on-disk
bytes, names are UTF-16LE decoded to printable ASCII (stop at the first
`0x0000`, non-ASCII code units become `?`), and both CRC-32 fields are stored
raw. `gpt_parse` never rejects a CRC mismatch: call `gpt_header_crc_ok` /
`gpt_entries_crc_ok` (or `gpt_crc32` / `gpt_crc32_range`) to verify. The
CRC-32 is implemented locally with the standard reflected polynomial and is
table-free.

`gpt_build` writes a canonical primary GPT: the protective MBR (`0x55AA`,
single `0xEE` entry covering the disk from LBA 1), a 92-byte header and the
entry array at LBA 2, zero-filling any unused slots, with both CRCs
recomputed. No backup GPT is emitted or checked, and the result is not padded
to the disk size (see `SPEC.md`).

## Install

Not yet published. Consume it from this repository with the package harness:

```
& .\scripts\port.ps1 -Package xiom.gpt
```

Once published, the manifest name is `xiom.gpt` version `0.1.0`.

## API

All functions are free functions in module `xiom.gpt`.

| Function | Returns | Description |
|---|---|---|
| `gpt_has_protective_mbr(data)` | `Bool` | True for the documented protective MBR shape (0x55AA, one 0xEE slot-0 entry, empty slots 1..3). |
| `gpt_parse(data)` | `Result[GptTable, Str]` | Validate the header and index the entry array. |
| `gpt_build(t, total_sectors)` | `Result[Vec[UInt8], Str]` | Build a canonical primary GPT image (1024 + entry array bytes). |
| `gpt_crc32(data)` | `Int` | Standard CRC-32 of the whole buffer. |
| `gpt_crc32_range(data, start, count)` | `Int` | Standard CRC-32 of a span; `-1` when the span is invalid. |
| `gpt_header_crc_ok(data, t)` | `Bool` | Recompute the header CRC (its own field zeroed) and compare. |
| `gpt_entries_crc_ok(data, t)` | `Bool` | Recompute the entry-array CRC and compare. |
| `gpt_revision(t)` | `Int` | Header revision (raw). |
| `gpt_header_size(t)` | `Int` | Header size field (92..512 after a parse). |
| `gpt_header_crc(t)` | `Int` | Stored header CRC-32, raw. |
| `gpt_reserved(t)` | `Int` | Reserved field, preserved as parsed. |
| `gpt_current_lba(t)` | `Int` | MyLBA (1 for a primary GPT). |
| `gpt_backup_lba(t)` | `Int` | AlternateLBA (not cross-checked). |
| `gpt_first_usable_lba(t)` | `Int` | FirstUsableLBA. |
| `gpt_last_usable_lba(t)` | `Int` | LastUsableLBA. |
| `gpt_disk_guid(t)` | `Str` | Disk GUID as 32 lowercase hex characters. |
| `gpt_entries_lba(t)` | `Int` | PartitionEntryLBA. |
| `gpt_entry_size(t)` | `Int` | SizeOfPartitionEntry (>= 128, multiple of 8). |
| `gpt_entries_crc(t)` | `Int` | Stored entry-array CRC-32, raw. |
| `gpt_entry_count(t)` | `Int` | Safe entry count (declared count capped by the six vector lengths). |
| `gpt_type_guid(t, i)` | `Str` | Type GUID of entry `i`; all-zero means unused. |
| `gpt_unique_guid(t, i)` | `Str` | Unique GUID of entry `i`. |
| `gpt_entry_first_lba(t, i)` | `Int` | FirstLBA of entry `i`; `-1` out of range. |
| `gpt_entry_last_lba(t, i)` | `Int` | LastLBA of entry `i`; `-1` out of range. |
| `gpt_entry_attributes(t, i)` | `Int` | Raw 64-bit attributes; `0` out of range. |
| `gpt_entry_name(t, i)` | `Str` | Name decoded to printable ASCII; `""` out of range. |
| `gpt_entry_in_use(t, i)` | `Bool` | True when the type GUID is a non-zero 32-character GUID. |

`GptTable` holds the header scalars plus six parallel entry vectors
(`type_guids`, `unique_guids`, `first_lbas`, `last_lbas`, `attributes`,
`names`); no `Vec` of structs is used.

## Quick start

Reading an image (`data` is at least the MBR + header + entry array the
caller already loaded):

```xi
use xiom.gpt;
use xiom.io;
use xiom.convert;

fn report(data: &Vec[UInt8]) {
  let pr = gpt_parse(data);
  if !pr.is_ok {
    io.println("error: " + pr.error);
    return;
  }
  let t = pr.value;
  io.println("disk GUID: " + gpt_disk_guid(&t));
  io.println("entries: " + convert.int_to_string(gpt_entry_count(&t)));

  if !gpt_header_crc_ok(data, &t) {
    io.println("warning: header CRC mismatch");
  }

  var i = 0;
  while i < gpt_entry_count(&t) {
    if gpt_entry_in_use(&t, i) {
      io.println("part " + convert.int_to_string(i) + ": " + gpt_entry_name(&t, i));
      io.println("  first LBA: " + convert.int_to_string(gpt_entry_first_lba(&t, i)));
      io.println("  last LBA:  " + convert.int_to_string(gpt_entry_last_lba(&t, i)));
    }
    i = i + 1;
  }
}
```

Building a two-entry primary GPT on a 2048-sector disk:

```xi
use xiom.gpt;

var tys = Vec[Str].new();
tys.push("00112233445566778899aabbccddeeff");   // raw type GUID text
tys.push("aabbccddeeff00112233445566778899");
var ugs = Vec[Str].new();
ugs.push("fedcba98765432100123456789abcdef");
ugs.push("0123456789abcdeffedcba9876543210");
var fls = Vec[Int].new();
fls.push(2048);
fls.push(8192);
var lls = Vec[Int].new();
lls.push(4095);
lls.push(12287);
var ats = Vec[Int].new();
ats.push(5);
ats.push(0);
var nms = Vec[Str].new();
nms.push("EFI System");
nms.push("data");

let t = GptTable{
  revision: 65536;                // 0x00010000
  header_size: 92;
  header_crc: 0;
  reserved: 0;
  current_lba: 1;
  backup_lba: 0;
  first_usable_lba: 0;
  last_usable_lba: 0;
  disk_guid: "0123456789abcdef0123456789abcdef";
  entries_lba: 2;
  entry_count: 128;               // 128 slots, 2 used
  entry_size: 128;
  entries_crc: 0;
  type_guids: tys;
  unique_guids: ugs;
  first_lbas: fls;
  last_lbas: lls;
  attributes: ats;
  names: nms;
};

let built = gpt_build(&t, 2048);
```

The builder recomputes `first_usable_lba` (LBA 2 + the array sectors),
`last_usable_lba` and `backup_lba`, zero-fills slots 2..127 and patches both
CRC fields. See `SPEC.md` for the exact byte layout and geometry formulas.

## Errors

Every failure is an `Err(Str)` with a deterministic `gpt:` message:

| Message | Condition |
|---|---|
| `gpt: truncated header` | Buffer shorter than 1024 bytes (LBA 0 + LBA 1). |
| `gpt: bad signature` | Bytes 512..519 are not `EFI PART`. |
| `gpt: bad header size` | Header size outside `92..512`. |
| `gpt: bad LBA` | A header LBA field (current/backup/usable/entries) is zero or negative, or an entry LBA is negative. |
| `gpt: bad usable range` | `first_usable_lba > last_usable_lba`. |
| `gpt: bad entry size` | Entry size below 128 or not a multiple of 8. |
| `gpt: bad entry count` | Entry count outside `1..4096`. |
| `gpt: truncated entries` | The entry array does not fit in the buffer. |
| `gpt: bad revision` | Build revision outside `0..2^32-1`. |
| `gpt: bad guid` | A build GUID is not exactly 32 hex characters. |
| `gpt: bad entry name` | A build name has a non-printable byte or does not fit with its terminator. |
| `gpt: entry vector mismatch` | The six build entry vectors differ in length. |
| `gpt: entry count too small` | The declared count is smaller than the provided vectors. |
| `gpt: bad entry LBA` | A build entry has a negative LBA or `first_lba > last_lba`. |
| `gpt: disk too small` | `total_sectors` cannot hold the primary array plus the backup region. |

CRC mismatches are **not** errors: `gpt_parse` stores both CRC fields raw and
the verification helpers return `Bool`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.gpt
```

Expected: the section-4 namespace check passes, 17 `[PASS]` lines,
`xiom.gpt: all tests passed`, then
`port: PASS (passed=17 failed=0 program_exit=0 exit=0)`. Fixtures are
assembled byte by byte, so `gpt_parse` is exercised independently of
`gpt_build`.

## Limitations

- **Primary GPT only.** No backup header/array is written or compared;
  `backup_lba` is just a number.
- **512-byte logical blocks only.** 4Kn images are out of scope.
- **CRCs are opt-in.** Call the verification helpers; `gpt_parse` accepts a
  corrupt CRC.
- **Raw hex GUIDs.** No canonical hyphenated UUID rendering and no
  byte-order swapping.
- **ASCII-only names.** Non-ASCII UTF-16 code units (including surrogate
  pairs) decode to `?` and cannot be represented by the builder.
- **64-bit signed range.** LBAs with bit 63 set are rejected; attributes
  with bit 63 set read back negative.
- **Builder layout is unaligned.** Entries start at LBA 2, no 1 MiB
  alignment, the image is not padded to the disk size, and there is no
  partition insertion/removal API.
- Not thread-safe; all values are plain value types.

See `SPEC.md` for the full byte layout, validation order and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
