# xiom.acpi -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.acpi`, version `0.1.0`).
Module: `src/acpi.xi` (`module xiom.acpi`).
Depends on `xiom.std` (`xiom.string`); tests add `xiom.test`, `xiom.io`,
`xiom.string`, `xiom.string.compare`, `xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for the ACPI table layer:

- `acpi_rsdp_parse` validates an RSDP at offset 0 and returns an
  `AcpiRsdp` (revision, length, RSDT/XSDT addresses, OEMID copy);
- `acpi_walk_rsdt` / `acpi_walk_xsdt` / `acpi_tables_from_rsdp` walk the
  table chain over a caller-supplied buffer, resolving every entry to a
  validated span and storing the chain as flat parallel vectors;
- accessors report table count, offset, length, revision, packed
  signature, OEM IDs/revisions, body span and body bytes, plus
  first-match lookup by signature;
- `acpi_sum8` / `acpi_checksum_valid` / `acpi_range_printable` /
  `acpi_signature_value` are the documented helpers;
- `acpi_build_table` / `acpi_build_rsdt` / `acpi_build_xsdt` /
  `acpi_build_rsdp` emit canonical bytes with computed checksums;
- deterministic `Err(Str)` messages for every malformed shape.

All multi-byte fields are little-endian (the ACPI convention).

## Non-goals

- AML/DSDT interpretation, name-space traversal, method execution.
- FACS/SLIC semantics, FADT/GAS field decoding, or any table body schema:
  bodies are opaque bytes after byte 36.
- Linux/Windows firmware quirks beyond the documented ones: no RSDP search
  over the 0xE0000..0xFFFFF window or EBDA, no wrong-checksum tolerance,
  no 8-byte alignment enforcement, no blacklists.
- Locating the RSDP: `acpi_rsdp_parse` reads offset 0 only.
- Multiple RSDPs / RSDT-vs-XSDT priority beyond the documented fallback.
- Streaming/incremental parsing: the whole buffer is an in-memory
  `Vec[UInt8]`.
- Building a chain from a parsed store: the builders take explicit
  addresses/entries; the walker never re-emits (`AcpiTableSet` stores no
  bytes).

## Byte-level layout

### RSDP

| Offset | Width | Field | Notes |
|---|---|---|---|
| 0 | 8 | signature | `"RSD PTR "` (with trailing space) |
| 8 | 1 | base checksum | bytes 0..20 sum to 0 mod 256 |
| 9 | 6 | OEMID | printable ASCII |
| 15 | 1 | revision | `0` or `2` |
| 16 | 4 | RSDT address | u32 little-endian |
| 20 | 4 | length | revision 2 only; `>= 36`, within the buffer |
| 24 | 8 | XSDT address | revision 2 only; u64 little-endian |
| 32 | 1 | extended checksum | revision 2 only; bytes 20..length sum to 0 |
| 33 | 3 | reserved | not inspected |

Revision 0 is exactly 20 bytes; revision 2 is 36 bytes when the length
field is 36, but any stored length `>= 36` inside the buffer is accepted
and the extended checksum covers bytes 20..length.

### SDT header (36 bytes, every table)

| Offset | Width | Field | Notes |
|---|---|---|---|
| 0 | 4 | signature | printable ASCII |
| 4 | 4 | length | u32 little-endian, `>= 36`, within the buffer |
| 8 | 1 | revision | |
| 9 | 1 | checksum | whole table sums to 0 mod 256 |
| 10 | 6 | OEMID | printable ASCII in canonical output |
| 16 | 8 | OEM table ID | printable ASCII in canonical output |
| 24 | 4 | OEM revision | u32 little-endian |
| 28 | 4 | creator ID | printable ASCII in canonical output |
| 32 | 4 | creator revision | u32 little-endian |
| 36 | `length - 36` | body | opaque bytes |

### RSDT / XSDT

The root is itself a table with signature `"RSDT"` or `"XSDT"`. Its entry
array starts at byte 36:

- RSDT: `(length - 36) / 4` entries, each a u32 little-endian table
  address; `(length - 36) % 4` must be 0.
- XSDT: `(length - 36) / 8` entries, each a u64 little-endian table
  address; `(length - 36) % 8` must be 0.

Addresses above 2^63-1 read back as negative two's-complement `Int` values
(the `xiom.msgpack` convention) and fail validation as out of range.

## API signatures

All functions are free functions in module `xiom.acpi` (no self methods):

```xi
pub type AcpiRsdp = {
  revision: Int;
  length: Int;
  rsdt_address: Int;
  xsdt_address: Int;
  oem_id: Vec[UInt8];
}

pub type AcpiTableSet = {
  table_offsets: Vec[Int];
  table_lengths: Vec[Int];
  table_revisions: Vec[Int];
  table_sigs: Vec[Int];
}

pub const ACPI_RSDP_MIN_LEN: Int = 20;
pub const ACPI_RSDP_REV2_LEN: Int = 36;
pub const ACPI_SDT_HEADER_LEN: Int = 36;
pub const ACPI_RSDT_SIG: Int = 1381188692;   // "RSDT"
pub const ACPI_XSDT_SIG: Int = 1481851988;   // "XSDT"

pub fn acpi_rsdp_parse(data: &Vec[UInt8]) -> Result[AcpiRsdp, Str]
pub fn acpi_rsdp_revision(r: &AcpiRsdp) -> Int
pub fn acpi_rsdp_length(r: &AcpiRsdp) -> Int
pub fn acpi_rsdp_rsdt_address(r: &AcpiRsdp) -> Int
pub fn acpi_rsdp_xsdt_address(r: &AcpiRsdp) -> Int
pub fn acpi_rsdp_oem_id(r: &AcpiRsdp) -> Vec[UInt8]

pub fn acpi_walk_rsdt(data: &Vec[UInt8], offset: Int) -> Result[AcpiTableSet, Str]
pub fn acpi_walk_xsdt(data: &Vec[UInt8], offset: Int) -> Result[AcpiTableSet, Str]
pub fn acpi_tables_from_rsdp(data: &Vec[UInt8], r: &AcpiRsdp) -> Result[AcpiTableSet, Str]

pub fn acpi_table_count(t: &AcpiTableSet) -> Int
pub fn acpi_table_offset(t: &AcpiTableSet, i: Int) -> Int
pub fn acpi_table_length(t: &AcpiTableSet, i: Int) -> Int
pub fn acpi_table_revision(t: &AcpiTableSet, i: Int) -> Int
pub fn acpi_table_signature(t: &AcpiTableSet, i: Int) -> Int
pub fn acpi_find_table(t: &AcpiTableSet, sig: Str) -> Int

pub fn acpi_table_signature_bytes(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str]
pub fn acpi_table_oem_id(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str]
pub fn acpi_table_oem_table_id(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str]
pub fn acpi_table_creator_id(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str]
pub fn acpi_table_oem_revision(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Int
pub fn acpi_table_creator_revision(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Int
pub fn acpi_table_body_offset(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Int
pub fn acpi_table_body_length(t: &AcpiTableSet, i: Int) -> Int
pub fn acpi_table_span_ok(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Bool
pub fn acpi_table_body(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str]

pub fn acpi_sum8(data: &Vec[UInt8], offset: Int, length: Int) -> Int
pub fn acpi_checksum_valid(data: &Vec[UInt8], offset: Int, length: Int) -> Bool
pub fn acpi_range_printable(data: &Vec[UInt8], offset: Int, length: Int) -> Bool
pub fn acpi_signature_value(s: Str) -> Int

pub fn acpi_build_table(sig: Str, revision: Int, oem_id: Str, oem_table_id: Str, oem_revision: Int, creator_id: Str, creator_revision: Int, body: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn acpi_build_rsdt(entries: &Vec[Int], oem_id: Str, oem_table_id: Str, creator_id: Str, creator_revision: Int) -> Result[Vec[UInt8], Str]
pub fn acpi_build_xsdt(entries: &Vec[Int], oem_id: Str, oem_table_id: Str, creator_id: Str, creator_revision: Int) -> Result[Vec[UInt8], Str]
pub fn acpi_build_rsdp(revision: Int, rsdt_address: Int, xsdt_address: Int, oem_id: Str) -> Result[Vec[UInt8], Str]
```

Fields of `AcpiRsdp` and `AcpiTableSet` are implementation details; callers
should go through the free functions.

## Semantics

`acpi_rsdp_parse(data)`
: Validates in this order: `data.len() >= 20`, signature `"RSD PTR "`,
  base checksum (`acpi_sum8(data, 0, 20) == 0`), revision in `{0, 2}`,
  OEMID printability, then for revision 2 `data.len() >= 36`, stored length
  `>= 36` and `<= data.len()`, and the extended checksum
  (`acpi_sum8(data, 20, length - 20) == 0`). For revision 0 `length` is 20
  and `xsdt_address` is 0. The first failure in that order wins.

`acpi_walk_rsdt(data, offset)` / `acpi_walk_xsdt(data, offset)`
: Resolve the root first with the shared table checks (below), then require
  the packed root signature to be `ACPI_RSDT_SIG` / `ACPI_XSDT_SIG`
  (`acpi: bad root signature`), then require the entry-area length to be a
  multiple of 4 / 8 (`acpi: rsdt length misaligned` /
  `acpi: xsdt length misaligned`), then resolve every entry left to right.
  A zero entry is skipped and the walk continues; it neither adds a table
  nor terminates the walk. Each nonzero entry is resolved with the same
  shared checks; the first failing entry aborts with its error. The store
  receives one push on each of the four parallel vectors per resolved
  table, in walk order.

Shared table checks (`_resolve_table`, used for the root and every entry)
: Applied in this order:
  1. address negative -> `acpi: table address out of range` (only a u64
     entry above 2^63-1 can be negative);
  2. address not a multiple of 4 -> `acpi: table address not aligned`;
  3. address + 36 beyond the buffer -> `acpi: table header out of range`;
  4. the four signature bytes not all printable ASCII ->
     `acpi: table signature not printable`;
  5. `length < 36` or `address + length` beyond the buffer ->
     `acpi: table length out of range`;
  6. `acpi_sum8(data, address, length) != 0` ->
     `acpi: bad table checksum`.

`acpi_tables_from_rsdp(data, r)`
: Revision 2 with `xsdt_address > 0` walks the XSDT at that address;
  otherwise it walks the RSDT at `rsdt_address`, including a revision 2
  RSDP whose XSDT address is 0 (documented fallback). A selected address of
  0 is `acpi: no table root`.

`acpi_table_*` index accessors
: `acpi_table_offset` / `acpi_table_length` / `acpi_table_revision` /
  `acpi_table_signature` return `-1` when `i < 0` or
  `i >= acpi_table_count(t)`. `acpi_find_table` packs `sig` with
  `acpi_signature_value` and returns the first equal entry, or `-1` when
  the signature is not four printable characters or no table matches.
  Duplicate signatures are tolerated.

`acpi_table_*` byte getters
: `acpi_table_signature_bytes` / `_oem_id` / `_oem_table_id` /
  `_creator_id` / `_body` copy bytes out of `data`;
  `Err("acpi: index out of range")` for a bad index and
  `Err("acpi: table span out of bounds")` when the recorded span does not
  fit `data`. `acpi_table_oem_revision` / `acpi_table_creator_revision` /
  `acpi_table_body_offset` report the same conditions as `-1`;
  `acpi_table_body_length` needs only the store (index out of range or a
  stored length below 36 gives `-1`); `acpi_table_span_ok` is the `Bool`
  form.

`acpi_sum8` / `acpi_checksum_valid` / `acpi_range_printable`
: Return `-1` / `false` / `false` when the range is negative or does not
  fit the buffer. `acpi_checksum_valid` is the documented verify helper: it
  is true exactly when the bytes of the range sum to 0 modulo 256, which
  holds for a valid range that includes its checksum byte.

`acpi_signature_value(s)`
: Big-endian packing of four printable ASCII bytes (`"FACP"` is
  `1178682192`); `-1` when `s` is not exactly four characters or any byte
  is outside `0x20..0x7e`. Printable signatures never set bit 31.

Builders
: `acpi_build_table` validates the signature (exactly 4 printable), OEMID
  (`<= 6`), OEM table ID (`<= 8`) and creator ID (`<= 4`) as printable
  ASCII, the revision as `0..255` and both revisions as `0..4294967295`,
  then writes the header with text fields space-padded to their width, the
  length `36 + body.len()`, the body verbatim, and the checksum byte at
  offset 9 such that the whole table sums to 0. `acpi_build_rsdt` /
  `acpi_build_xsdt` validate the same texts and then the entries (negative,
  or above 4294967295 for the RSDT, is `acpi: entry address out of range`;
  text errors are reported first), build the little-endian entry body and
  delegate to `acpi_build_table` with revision 1 and OEM revision 1.
  `acpi_build_rsdp` validates the revision (`0` or `2`), the OEMID, the
  RSDT address (`0..4294967295`) and the XSDT address (non-negative; must
  be 0 for revision 0), writes a 20-byte revision 0 RSDP or a 36-byte
  revision 2 RSDP (length field 36), and computes both checksums.

## Canonical form

Builder output is canonical when:

1. `acpi_build_table` writes the 36-byte header, text fields padded with
   spaces (`0x20`), the recomputed little-endian length and the computed
   checksum;
2. `acpi_build_rsdt` / `acpi_build_xsdt` write signature `"RSDT"` /
   `"XSDT"`, revision 1, OEM revision 1 and the entry addresses in caller
   order as u32 / u64 little-endian;
3. `acpi_build_rsdp` writes `"RSD PTR "`, the OEMID, the revision, the RSDT
   address, and for revision 2 the length 36, the XSDT address, the
   extended checksum and three reserved zero bytes, with the base checksum
   over bytes 0..20.

Round-trips: for a buffer already in this form, parse -> walk -> field
accessors reproduce every copied field, and building the same inputs
reproduces the buffer byte-for-byte (pinned in the tests for both a
revision 0 and a revision 2 chain).

## Error string catalog

| Condition | Error text |
|---|---|
| `acpi_rsdp_parse`: `data.len() < 20` | `acpi: buffer too short` |
| `acpi_rsdp_parse`: signature mismatch | `acpi: bad rsdp signature` |
| `acpi_rsdp_parse`: base checksum nonzero | `acpi: bad rsdp checksum` |
| `acpi_rsdp_parse`: revision not 0 or 2 | `acpi: unsupported rsdp revision` |
| `acpi_rsdp_parse`: OEMID not printable | `acpi: rsdp oem id not printable` |
| `acpi_rsdp_parse`: revision 2, `data.len() < 36`, or length `< 36`, or length beyond the buffer | `acpi: bad rsdp length` |
| `acpi_rsdp_parse`: revision 2 extended checksum nonzero | `acpi: bad rsdp extended checksum` |
| `acpi_tables_from_rsdp`: selected root address is 0 | `acpi: no table root` |
| walker: root signature not `"RSDT"` / `"XSDT"` | `acpi: bad root signature` |
| `_resolve_table`: negative address | `acpi: table address out of range` |
| `_resolve_table`: address not a multiple of 4 | `acpi: table address not aligned` |
| `_resolve_table`: `address + 36 > data.len()` | `acpi: table header out of range` |
| `_resolve_table`: signature bytes not all printable | `acpi: table signature not printable` |
| `_resolve_table`: length `< 36` or `address + length > data.len()` | `acpi: table length out of range` |
| `_resolve_table`: checksum nonzero over the declared length | `acpi: bad table checksum` |
| walker: `(length - 36) % 4 != 0` | `acpi: rsdt length misaligned` |
| walker: `(length - 36) % 8 != 0` | `acpi: xsdt length misaligned` |
| byte getters: `i < 0` or `i >= count` | `acpi: index out of range` |
| byte getters / revision getters: recorded span outside `data` | `acpi: table span out of bounds` (`-1` for the `Int` getters) |
| `acpi_build_table` / index builders: signature not 4 printable chars | `acpi: bad signature text` |
| builders: OEMID longer than 6 or not printable | `acpi: bad oem id text` |
| builders: OEM table ID longer than 8 or not printable | `acpi: bad oem table id text` |
| builders: creator ID longer than 4 or not printable | `acpi: bad creator id text` |
| `acpi_build_table`: revision outside `0..255` | `acpi: bad revision` |
| `acpi_build_table`: OEM revision outside `0..4294967295` | `acpi: bad oem revision` |
| `acpi_build_table`: creator revision outside `0..4294967295` | `acpi: bad creator revision` |
| `acpi_build_table`: `body.len() > 4294967259` | `acpi: table too large` |
| index builders: entry negative, or above 4294967295 for the RSDT | `acpi: entry address out of range` |
| `acpi_build_rsdp`: revision not 0 or 2 | `acpi: rsdp revision must be 0 or 2` |
| `acpi_build_rsdp`: RSDT address outside `0..4294967295`, or negative XSDT address | `acpi: rsdp address out of range` |
| `acpi_build_rsdp`: revision 0 with a nonzero XSDT address | `acpi: rsdp revision 0 has no xsdt` |

`acpi_sum8`, `acpi_checksum_valid` and `acpi_range_printable` have no
error channel; an invalid range yields `-1` / `false`. The index accessors
report out-of-range with `-1`; only the copying getters use `Result`.

## Complexity

| Operation | Complexity |
|---|---|
| `acpi_rsdp_parse` | O(1) plus O(length) for the extended checksum |
| `acpi_walk_rsdt` / `acpi_walk_xsdt` | O(root length + resolved entries) |
| count / offset / length / revision / signature accessors | O(1) |
| `acpi_find_table` | O(tables) |
| byte getters / `acpi_table_body` | O(bytes copied) |
| `acpi_sum8` / `acpi_checksum_valid` / `acpi_range_printable` | O(length) |
| `acpi_signature_value` | O(1) |
| `acpi_build_table` | O(body length) |
| `acpi_build_rsdt` / `acpi_build_xsdt` | O(entries) |
| `acpi_build_rsdp` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module acpi_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Two fully hand-computed buffers are pinned as
hex literals:

- fixture A (104 bytes): RSDP revision 0 at 0, a 40-byte RSDT at 20 whose
  single u32 entry points to an FACP-like table at 60 (44 bytes, revision
  5, body `00..07`);
- fixture B (172 bytes): RSDP revision 2 at 0 (RDST address 0, XSDT address
  36), a 52-byte XSDT at 36 with u64 entries 88 and 128, a DSDT-like table
  at 88 (40 bytes, revision 2, body `deadbeef`) and an FACP-like table at
  128 (44 bytes, revision 6).

Coverage:

1. revision 0 RSDP: revision/length/RSDT address/XSDT address (0), OEMID
   bytes, base checksum helper;
2. RSDP errors: 19-byte buffer, bad signature, bad base checksum,
   revision 1 and 255 (checksum-corrected so the revision check is
   reached);
3. revision 2 RSDP: revision/length/XSDT address, base and extended
   checksums;
4. revision 2 errors: length 35, length 200, 30-byte buffer, corrupted
   reserved byte, non-printable OEMID (checksum-corrected);
5. RSDT walk: one table, pinned offset 60/length 44/revision 5/packed
   signature, `acpi_find_table` first match and misses (including a
   three-character signature);
6. table accessors: signature/OEMID/OEM table ID/creator ID bytes, OEM
   revision 1, creator revision 65536, body offset 96/length 8/body bytes,
   out-of-range `-1` and `Err`, a 100-byte truncated buffer for span
   checks;
7. RSDT root errors: offset 22 not aligned, offset 100 out of bounds,
   checksum-corrected `"XSDT"` signature, checksum-corrected
   non-printable signature, bad checksum, length 35, length 200, length
   41 (misaligned entry area, checksum-corrected);
8. zero-entry policy: `[0, 60]`, `[60, 0]` and `[0, 0]` RSDTs
   (builder-generated) walk to 1/1/0 tables without stopping;
9. entry errors: entry 62 (misaligned), entry 1000 (header out of range),
   a valid entry at 40, then bad table checksum, table length 200 and
   non-printable signature on that table;
10. XSDT fixture: two tables, signatures DSDT/FACP, offsets 88/128,
    lengths 40/44, revisions 2/6, lookup order and a `deadbeef` body;
11. XSDT errors: `acpi_walk_xsdt` on an RSDT root, bad XSDT checksum,
    length 48 (misaligned entry area, checksum-corrected), an entry with
    bit 63 set (checksum-corrected, out of range), a root offset 168 out
    of bounds;
12. `acpi_tables_from_rsdp`: fixture A -> RSDT, fixture B -> XSDT, a
    builder-made revision 2 RSDP with XSDT address 0 falling back to its
    RSDT, and `acpi: no table root` for revision 0 and revision 2 RSDPs
    with both addresses 0;
13. `acpi_build_table` reproduces the pinned FACP fixture byte-for-byte
    and passes `acpi_checksum_valid` / `acpi_sum8`;
14. builder errors: signature length 3 and 5, oversized OEMID/OEM table
    ID/creator ID, revision -1 and 256, negative OEM/creator revisions,
    RSDT entry -1 and 4294967296, RSDP revision 1, negative RSDT address,
    revision 0 with an XSDT address;
15. revision 0 round-trip: builder RSDP/RSDT/FACP equal the pinned fixture
    slices and the concatenated buffer; parse -> `acpi_tables_from_rsdp`
    recovers revision 5, an 8-byte body and the body bytes;
16. revision 2 round-trip: builder RSDP/XSDT/DSDT/FACP equal the pinned
    fixture slices and the concatenated buffer; parse -> walk recovers both
    tables and the DSDT body;
17. duplicate signatures (two FACPs via XSDT) and duplicate addresses
    (`[60, 60]` RSDT) are tolerated; `acpi_find_table` returns index 0 and
    both entries are stored;
18. signature packing values for FACP/RSDT/XSDT/DSDT and `-1` for
    invalid lengths, printability bounds (`-1`, beyond the buffer,
    non-printable body bytes), and `acpi_sum8` /
    `acpi_checksum_valid` bounds and semantics against an independent
    test-local summer.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.acpi
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Bodies are opaque; no AML/DSDT interpretation, no FACS/SLIC semantics.
- The RSDP must be at offset 0 of the buffer; no firmware search window.
- Checksum failures are always errors; no tolerated-checksum quirk mode.
- Every root and entry address must be 4-byte aligned (8-byte alignment is
  recommended by ACPI 6.x but not enforced).
- Zero RSDT/XSDT entries are skipped and the walk continues to the end of
  the entry area.
- Addresses above 2^63-1 are negative `Int` values and are rejected; the
  builders cannot emit them.
- OEMID/OEM table ID/creator ID printability is not enforced while
  walking; only signatures are. The builders enforce it for their inputs.
- `AcpiTableSet` stores offsets/lengths, so accessors need the original
  buffer; a truncated buffer reports `acpi: table span out of bounds`.
- `AcpiTableSet` is a plain value type built from parallel vectors; callers
  can corrupt its invariants (the walkers never drift them).
- Not thread-safe.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_rsdp`/`_err_rsdp`/`_ok_set`/`_err_set`/`_ok_desc`/`_err_desc`/
  `_ok_bytes`/`_err_bytes` (constructing Results directly in other
  functions miscompiles).
- All little-endian extraction/packing is arithmetic (modulo/division)
  because `& 0xFF` on operands with bit 31 set miscompiles (same bug
  documented in `xiom.convert.base58` and `xiom.msgpack`); this form is
  exact for negative two's-complement values.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic, and every `Vec[Int]` element read is bound to a
  typed local.
- Results are consumed with `.is_ok` / `.value` / `.error`, not `match`,
  inside the library; only the tests match.
- Every push on one parallel vector is mirrored on its siblings; the
  walkers append all four fields together.
- Str values are never compared with `==`; signatures and text fields are
  compared byte by byte (BUG 17 discipline). No `sb_to_str` is used, so no
  NUL handling is needed.
- The package declares no `extern "C"` blocks (no FFI).
