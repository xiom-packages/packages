# xiom.mbr

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Master Boot Record codec: parse and build the canonical 512-byte
> MBR sector -- raw boot code, four primary partition entries and the 0x55AA
> signature.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library module imports nothing
> from it). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.mbr` reads and writes the structural part of a Master Boot Record:
the 440-byte boot code span, the six bytes at 0x1B8..0x1BD (optional disk
signature plus reserved), the four 16-byte primary partition entries and the
0x55AA boot signature at 0x1FE. `mbr_parse` validates the sector length, the
signature, the four boot flags and the documented type 0 policy (an unused
slot must have zero LBA fields), then returns an `Mbr` of flat parallel
vectors: one element per entry slot for boot flags, packed raw CHS triples,
type codes, LBA starts and LBA counts. No `Vec` of structs is used.

CHS triples are preserved raw and decoded on demand (head u8, sector 6
bits, cylinder 10 bits); zero CHS is tolerated whenever the LBA fields are
set, because CHS is never cross-checked against LBA. LBA ranges are bounded
against a disk size only by the opt-in `mbr_parse_sized`. A partial
partition-type name table (0x00, 0x07, 0x0B, 0x0C, 0x82, 0x83, 0x8E, 0xEE,
0xEF) names known codes; unknown codes pass through as `"unknown"` while the
raw byte stays available. `mbr_has_overlap` runs the documented pairwise
extent check, and `mbr_build` emits a canonical 512-byte sector with a
recomputed signature.

The codec never touches the filesystem, never follows EBR chains, never
parses GPT and never inspects partition contents: it is a pure structural
codec over in-memory `Vec[UInt8]` buffers. See `SPEC.md` for the byte
layout, policies, validation order, error catalog and test plan.

## Install

Not yet published. Consume it from this repository with the package harness:

```
& .\scripts\port.ps1 -Package xiom.mbr
```

Once published, the manifest name is `xiom.mbr` version `0.1.0`.

## API

All functions are free functions in module `xiom.mbr`.

| Function | Returns | Description |
|---|---|---|
| `mbr_parse(data)` | `Result[Mbr, Str]` | Validate a 512-byte sector and index its four entries. |
| `mbr_parse_sized(data, total_sectors)` | `Result[Mbr, Str]` | `mbr_parse` plus the in-use entry disk-size bound. |
| `mbr_signature(data)` | `Int` | Bytes 0x1FE..0x1FF as a little-endian UInt16; `-1` when short. |
| `mbr_signature_ok(data)` | `Bool` | Exact 0x55 0xAA check on a >= 512-byte buffer. |
| `mbr_boot_code_span(m)` | `Vec[UInt8]` | Copy of the 440 raw boot code bytes (0x000..0x1B7). |
| `mbr_disk_area_span(m)` | `Vec[UInt8]` | Copy of the 6 raw bytes at 0x1B8..0x1BD. |
| `mbr_entry_count(m)` | `Int` | Safe entry count (minimum length of the six parallel vectors). |
| `mbr_type_name(code)` | `Str` | Documented name for a type byte; `"unknown"` in range, `""` outside 0..255. |
| `mbr_entry_boot_flag(m, i)` | `Int` | Raw flag byte (0x00/0x80); `-1` out of range. |
| `mbr_entry_bootable(m, i)` | `Bool` | True when the flag is 0x80. |
| `mbr_entry_type(m, i)` | `Int` | Raw type byte; `-1` out of range. |
| `mbr_entry_type_name(m, i)` | `Str` | Type name of entry `i`; `""` out of range. |
| `mbr_entry_start_chs(m, i)` | `Int` | Packed raw 24-bit start CHS triple; `-1` out of range. |
| `mbr_entry_start_chs_head(m, i)` | `Int` | Decoded start head (u8). |
| `mbr_entry_start_chs_sector(m, i)` | `Int` | Decoded start sector (6 bits). |
| `mbr_entry_start_chs_cylinder(m, i)` | `Int` | Decoded start cylinder (10 bits). |
| `mbr_entry_end_chs(m, i)` | `Int` | Packed raw 24-bit end CHS triple. |
| `mbr_entry_end_chs_head(m, i)` | `Int` | Decoded end head (u8). |
| `mbr_entry_end_chs_sector(m, i)` | `Int` | Decoded end sector (6 bits). |
| `mbr_entry_end_chs_cylinder(m, i)` | `Int` | Decoded end cylinder (10 bits). |
| `mbr_entry_lba_start(m, i)` | `Int` | LE32 first LBA; `-1` out of range. |
| `mbr_entry_lba_count(m, i)` | `Int` | LE32 sector count; `-1` out of range. |
| `mbr_entry_in_use(m, i)` | `Bool` | True when the type byte is not 0x00. |
| `mbr_entries_overlap(m, a, b)` | `Bool` | Pairwise half-open extent overlap; unused/zero-length/self are false. |
| `mbr_has_overlap(m)` | `Bool` | True when any two of the four in-use entries overlap. |
| `mbr_build(m)` | `Result[Vec[UInt8], Str]` | Build a canonical 512-byte sector with a recomputed signature. |

`Mbr = { boot_code: Vec[UInt8]; disk_area: Vec[UInt8]; boot_flags:
Vec[Int]; start_chs: Vec[Int]; types: Vec[Int]; end_chs: Vec[Int];
lba_starts: Vec[Int]; lba_counts: Vec[Int]; }` -- one element per entry slot
for the six entry vectors. No `Vec` of structs is used.

## Quick start

Reading an MBR (`data` is a 512-byte sector the caller already loaded):

```xi
use xiom.mbr;
use xiom.io;
use xiom.convert;

fn report(data: &Vec[UInt8]) {
  let pr = mbr_parse(data);
  if !pr.is_ok {
    io.println("error: " + pr.error);
    return;
  }
  let m = pr.value;
  if mbr_has_overlap(&m) {
    io.println("warning: partition extents overlap");
  }
  var i = 0;
  while i < mbr_entry_count(&m) {
    if mbr_entry_in_use(&m, i) {
      io.println("part " + convert.int_to_string(i) + ": " + mbr_entry_type_name(&m, i));
      io.println("  LBA start: " + convert.int_to_string(mbr_entry_lba_start(&m, i)));
      io.println("  sectors:   " + convert.int_to_string(mbr_entry_lba_count(&m, i)));
      if mbr_entry_bootable(&m, i) {
        io.println("  bootable");
      }
    }
    i = i + 1;
  }
}
```

Building a canonical MBR (one bootable Linux partition at LBA 2048):

```xi
use xiom.mbr;

var boot = Vec[UInt8].new();
var k = 0;
while k < 440 {
  boot.push(0 as UInt8);
  k = k + 1;
}
var area = Vec[UInt8].new();
area.push(0 as UInt8);
area.push(0 as UInt8);
area.push(0 as UInt8);
area.push(0 as UInt8);
area.push(0 as UInt8);
area.push(0 as UInt8);

var flags = Vec[Int].new();
flags.push(128);                       // bootable
var starts = Vec[Int].new();
starts.push(65792);                    // head 1, sector 1, cylinder 0
var types = Vec[Int].new();
types.push(131);                       // Linux
var ends = Vec[Int].new();
ends.push(16711679);                   // head 254, sector 63, cylinder 1023
var ls = Vec[Int].new();
ls.push(2048);
var lc = Vec[Int].new();
lc.push(1024);

let m = Mbr{
  boot_code: boot;
  disk_area: area;
  boot_flags: flags;
  start_chs: starts;
  types: types;
  end_chs: ends;
  lba_starts: ls;
  lba_counts: lc;
};
let built = mbr_build(&m);             // Ok(bytes), always 512 bytes
```

`mbr_build` zero-fills the entry slots the vectors do not cover and always
recomputes the 0x55 0xAA signature. See `SPEC.md` for the exact layout and
policies.

## Errors

Every parse/build failure is an `Err(Str)` with a deterministic `mbr:`
message:

| Message | Condition |
|---|---|
| `mbr: truncated sector` | Buffer shorter than 512 bytes. |
| `mbr: bad signature` | Bytes 0x1FE..0x1FF are not `0x55 0xAA`. |
| `mbr: bad boot flag` | A boot flag is not `0x00` or `0x80`. |
| `mbr: unused entry not zero` | A type `0x00` entry has a non-zero LBA start or count. |
| `mbr: bad disk size` | `mbr_parse_sized` called with `total_sectors <= 0`. |
| `mbr: entry beyond disk` | An in-use entry extends past `total_sectors`. |
| `mbr: bad boot code` | Build `boot_code` is not exactly 440 bytes. |
| `mbr: bad disk area` | Build `disk_area` is not exactly 6 bytes. |
| `mbr: entry vector mismatch` | The six build entry vectors differ in length. |
| `mbr: bad entry count` | The common vector length exceeds 4. |
| `mbr: bad entry type` | A build type byte is outside 0..255. |
| `mbr: bad CHS` | A build CHS triple is outside 0..0xFFFFFF. |
| `mbr: bad LBA` | A build LBA field is outside 0..2^32-1. |

Overlap is never an error: `mbr_parse` accepts overlapping entries and
`mbr_has_overlap` reports them as a boolean.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.mbr
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines,
`xiom.mbr: all tests passed`, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`. The main fixture
(one bootable Linux partition plus unused entries, with a non-zero disk
signature) is assembled byte by byte, so `mbr_parse` is exercised
independently of `mbr_build`, and `mbr_build` on that content is
byte-identical to the fixture.

## Limitations

- **Primary MBR only.** No EBR/extended-partition chains, no logical
  partitions, exactly four 16-byte slots.
- **No GPT.** The 0xEE protective entry is named only; for GPT see the
  sibling `xiom.gpt`.
- **No boot code semantics.** The boot code span and disk-area bytes are
  opaque payload, preserved raw.
- **No filesystem detection.** Type names come from a partial table; the
  raw byte is always available.
- **CHS is never cross-checked with LBA.** Zero CHS is legal on an in-use
  entry; decode is lossless and stale CHS is preserved.
- **Disk bounds are opt-in** through `mbr_parse_sized`; `mbr_parse` assumes
  no geometry, and LBA 0 is not excluded.
- **Overlap is reported, not rejected.**
- Whole-sector API: only the first 512 bytes are read; bytes after 0x1FF
  are ignored, and a build always emits exactly 512 bytes. Plain value
  types only; not thread-safe.

See `SPEC.md` for the full byte layout, policies and test matrix. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
