# xiom.smbios -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.smbios`, version `0.1.0`).
Module: `src/smbios.xi` (`module xiom.smbios`).
Depends on `xiom.std` (`xiom.string`, `xiom.encoding`); tests add
`xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for a documented SMBIOS/DMI subset:

- `smbios_entry32_parse` / `smbios_entry64_parse` decode and validate one
  entry-point variant; `smbios_entry_parse` applies the documented
  preference rule over both;
- `smbios_table_parse` walks a standalone structure table;
  `smbios_parse` locates the preferred entry point in an image and parses
  the table it points at;
- accessors report entry-point fields, structure type/length/handle/raw
  spans, 1-indexed strings (raw bytes and UTF-8 text) and the documented
  fields of structure types 0, 1, 2, 3, 4, 16 and 17;
- `smbios_entry32_build`, `smbios_entry64_build`, `smbios_struct_build`
  and `smbios_image_build32` emit canonical bytes with computed
  checksums;
- deterministic `Err(Str)` messages for every malformed shape.

Every structure type outside the documented subset is preserved with its
raw formatted span and string spans (nothing is decoded).

## Non-goals

- Vendor/OEM extension decoding; types outside 0..4, 16, 17 and 127 stay
  raw.
- DMI-to-sysfs mapping, `/sys/firmware/dmi` paths or Linux-specific names.
- UUID string formatting (RFC 4122 text form, little-endian field swap).
- The memory-device type table, processor family table, chassis OEM
  values and any other SMBIOS value table except the chassis type table.
- Address-to-offset translation: the entry-point table address is used
  as an offset into the buffer handed to `smbios_parse` (see below).
- Finding the entry point in a real firmware address window (0xF0000..):
  the scan is over the caller-provided buffer only.
- Incremental/streaming parsing; buffers are in-memory `Vec[UInt8]`.

## Documented preference rule

`smbios_entry_parse(data)` scans 16-byte-aligned offsets from 0 (the
alignment SMBIOS requires for both entry points):

1. the first aligned `_SM3_` anchor wins: when it exists, the 64-bit
   entry point is authoritative and **its errors propagate** even when a
   valid `_SM_` entry point follows;
2. only when no `_SM3_` anchor exists is the first aligned `_SM_` anchor
   parsed;
3. when neither anchor exists: `Err("smbios: no entry point")`.

`smbios_entry32_parse` and `smbios_entry64_parse` look at offset 0 only
and require the matching signature. `smbios_entry_points(data)` counts
every aligned anchor (normal images have 1 or 2).

## Byte-level layout

### 32-bit entry point (`_SM_`, 31 bytes)

| Offset | Width | Field |
|---|---|---|
| 00h | 4 | anchor `_SM_` (5Fh 53h 4Dh 5Fh) |
| 04h | 1 | checksum: bytes 00h..1Eh sum to 0 mod 256 |
| 05h | 1 | entry point length, must be 1Fh |
| 06h | 1 | major version |
| 07h | 1 | minor version |
| 08h | 2 | max structure size |
| 0Ah | 1 | entry point revision |
| 0Bh | 5 | formatted area (not interpreted; the builder zeroes it) |
| 10h | 5 | intermediate anchor `_DMI_` (5Fh 44h 4Dh 49h 5Fh) |
| 15h | 1 | intermediate checksum: bytes 10h..1Eh sum to 0 mod 256 |
| 16h | 2 | structure table length |
| 18h | 4 | structure table address (u32) |
| 1Ch | 2 | number of structures (0 means "unknown") |
| 1Eh | 1 | BCD revision |

A buffer shorter than 31 bytes is `smbios: 32-bit entry point too
short`; the declared length must be exactly 1Fh (only length is
documented here).

### 64-bit entry point (`_SM3_`, 24 bytes)

| Offset | Width | Field |
|---|---|---|
| 00h | 5 | anchor `_SM3_` (5Fh 53h 4Dh 33h 5Fh) |
| 05h | 1 | checksum: bytes 00h..17h sum to 0 mod 256 |
| 06h | 1 | entry point length, must be 18h |
| 07h | 1 | major version |
| 08h | 1 | minor version |
| 09h | 1 | documentation revision |
| 0Ah | 1 | entry point revision |
| 0Bh | 1 | reserved (not interpreted) |
| 0Ch | 4 | structure table maximum size (u32) |
| 10h | 8 | structure table address (u64) |

A buffer shorter than 24 bytes is `smbios: 64-bit entry point too
short`; the declared length must be exactly 18h. An 8-byte address with
bit 63 set is held as the same signed two's-complement `Int` bit
pattern; the builder rejects negative addresses.

### Structure table stream

Each structure is:

| Field | Width | Notes |
|---|---|---|
| type | 1 | |
| length | 1 | formatted length, header included; must be >= 4 |
| handle | 2 | little-endian, unique across the table |
| formatted area | `length - 4` | raw; documented fields read from here |
| string set | variable | NUL-terminated strings plus a double-NUL terminator |

The string set ends at the first pair of consecutive 00h bytes found at
or after the formatted area; the NUL at the start of that pair is the
last string's terminator. Therefore a set with N strings occupies
`sum(len(s) + 1) + 1` bytes and an empty set is exactly the two bytes
`00 00` (the canonical End-of-Table structure is `7F 04 hh hh 00 00`).

Strings are **1-indexed** in order of appearance. Index 0 is the
documented "no string provided" and yields `Ok("")`; indices above the
structure's string count are `Err("smbios: string index out of
range")`. String bytes are arbitrary (not required to be UTF-8);
`smbios_string_bytes` returns them verbatim and `smbios_string` decodes
UTF-8, reporting `Err("smbios: invalid string bytes")` otherwise.

A type 127 (End of Table) structure ends the walk: structures after it
are not parsed and trailing bytes are ignored. A table without a type
127 structure is accepted and ends at the buffer (or span) end. The type
127 structure itself counts toward the structure count.

### Image parsing (`smbios_parse`)

The entry point's table address is interpreted as an offset into the
same buffer:

- **32-bit entry point:** the table spans
  `[table_addr, table_addr + table_len)` and must fit the buffer
  (`smbios: table out of buffer` otherwise). A declared structure count
  above 0 must equal the number of structures parsed
  (`smbios: structure count mismatch`); a declared count of 0 means
  "unknown" and skips the check. Table addresses are offsets, so
  32-bit images must be laid out accordingly; `smbios_image_build32`
  emits the canonical layout (entry point at 0, table at 32).
- **64-bit entry point:** the table spans `[table_addr, end)` where
  `end` is the buffer end, or `table_addr + max_size` when `max_size`
  is non-zero and smaller. `table_addr` must be before `end`
  (`smbios: table out of buffer` otherwise). There is no declared count.

Offsets in the returned `SmbiosTable` are absolute in the buffer passed
to the parse function (`smbios_table_parse` uses the table's own
offsets). Accessors re-derive and bounds-check every span, so an
out-of-range index or a span that does not fit the buffer is an `Err` or
`-1`, never a fault.

## Documented fields

All field accessors take `(data, table, i)`, return -1 when `i` is out
of range, when structure `i` is not of the documented type, or when the
field does not fit the formatted area, and read little-endian values.

| Type | Function | Offset | Width | Meaning |
|---|---|---|---|---|
| 0 | `smbios_bios_vendor` | 04h | 1 | vendor string index |
| 0 | `smbios_bios_version` | 05h | 1 | BIOS version string index |
| 0 | `smbios_bios_release_date` | 08h | 1 | release date string index |
| 0 | `smbios_bios_rom_size` | 09h | 1 | ROM size byte, pass-through (no 64 KiB scaling) |
| 1 | `smbios_system_manufacturer` | 04h | 1 | manufacturer string index |
| 1 | `smbios_system_product` | 05h | 1 | product name string index |
| 1 | `smbios_system_version` | 06h | 1 | version string index |
| 1 | `smbios_system_serial` | 07h | 1 | serial number string index |
| 1 | `smbios_uuid` | 08h | 16 | raw UUID bytes (see note) |
| 2 | `smbios_baseboard_manufacturer` | 04h | 1 | manufacturer string index |
| 2 | `smbios_baseboard_product` | 05h | 1 | product string index |
| 2 | `smbios_baseboard_version` | 06h | 1 | version string index |
| 2 | `smbios_baseboard_serial` | 07h | 1 | serial string index |
| 2 | `smbios_baseboard_asset_tag` | 08h | 1 | asset tag string index |
| 3 | `smbios_chassis_manufacturer` | 04h | 1 | manufacturer string index |
| 3 | `smbios_chassis_type` | 05h | 1 | raw type byte (bit 7 = lock flag) |
| 3 | `smbios_chassis_version` | 06h | 1 | version string index |
| 3 | `smbios_chassis_serial` | 07h | 1 | serial string index |
| 3 | `smbios_chassis_asset_tag` | 08h | 1 | asset tag string index |
| 4 | `smbios_processor_socket` | 04h | 1 | socket designation string index |
| 4 | `smbios_processor_family` | 06h | 1 | family byte, pass-through (table not decoded) |
| 4 | `smbios_processor_version` | 10h | 1 | version string index |
| 16 | `smbios_memory_array_capacity` | 07h | 4 | max capacity in KiB, pass-through (0x80000000 = unknown) |
| 17 | `smbios_memory_device_size` | 0Ch | 2 | size in MiB, pass-through (0 = empty, FFFFh = unknown, 7FFFh = extended) |
| 17 | `smbios_memory_device_type` | 12h | 1 | memory type byte, pass-through (table not decoded) |
| 17 | `smbios_memory_device_speed` | 15h | 2 | speed in MT/s, pass-through |
| 17 | `smbios_memory_device_manufacturer` | 17h | 1 | manufacturer string index |

### UUID byte-order note

SMBIOS 2.6+ stores the System Information UUID at offset 08h as 16 raw
bytes; the first three RFC 4122 fields (time_low u32, time_mid u16,
time_hi_and_version u16) are conventionally stored little-endian and the
remaining 8 bytes as-is. `smbios_uuid` returns the on-wire bytes without
reordering or formatting.

### Chassis type table

`smbios_chassis_type_name(t)` strips bit 7 (the lock flag) and maps the
low 7 bits: 1 Other, 2 Unknown, 3 Desktop, 4 Low Profile Desktop,
5 Pizza Box, 6 Mini Tower, 7 Tower, 8 Portable, 9 Laptop, 10 Notebook,
11 Hand Held, 12 Docking Station, 13 All in One, 14 Sub Notebook,
15 Space-saving, 16 Lunch Box, 17 Main Server Chassis,
18 Expansion Chassis, 19 Sub Chassis, 20 Bus Expansion Chassis,
21 Peripheral Chassis, 22 RAID Chassis, 23 Rack Mount Chassis,
24 Sealed-case PC, 25 Multi-system, 26 CompactPCI, 27 AdvancedTCA,
28 Blade, 29 Blade Enclosure, 30 Tablet, 31 Convertible, 32 Detachable,
33 IoT Gateway, 34 Embedded PC, 35 Mini PC, 36 Stick PC. Anything else
(including 0 and negative values) yields `"Unknown"`.

## Validation

- signatures: `_SM_`, `_SM3_`, `_DMI_` anchors byte-exact;
- the four checksum predicates: `smbios_entry32_checksum_ok`,
  `smbios_entry32_intermediate_checksum_ok`,
  `smbios_entry64_checksum_ok` and `smbios_entry_checksum_ok` (the
  preferred form's own checksum), all built on `smbios_checksum8`;
- entry length bounds: 31 bytes / 1Fh and 24 bytes / 18h;
- structure length >= 4 and the whole formatted area inside the span;
- exactly one structure cannot be short at a structure boundary
  (fewer than 4 bytes left is `smbios: truncated structure`);
- string-set termination by double NUL inside the span;
- **handle uniqueness policy:** strict. Handles must be unique across
  the table; the first repeated handle is
  `Err("smbios: duplicate handle")`. (SMBIOS requires unique handles;
  no lenient mode is offered. Checked in O(structures^2).)
- table address vs buffer: 32-bit address + length inside the buffer;
  64-bit address inside the buffer, bounded by `max_size` when set;
- 32-bit structure count: exact match when the declared count is
  non-zero.

`smbios_checksum8(data, off, len)` returns the modulo-256 sum of a span,
or -1 when `off`/`len` are negative or the span exceeds `data`. Note
that a checksum predicate only proves the sum; a zero-filled buffer
trivially passes it, so signatures are validated separately by the
parsers.

## API signatures

All functions are free functions in module `xiom.smbios` (no self
methods):

```xi
pub type SmbiosEntry = {
  kind: Int; major: Int; minor: Int; docrev: Int; revision: Int;
  max_size: Int; table_len: Int; table_addr: Int; count: Int; bcd_rev: Int;
}

pub type SmbiosTable = {
  types: Vec[Int]; lengths: Vec[Int]; handles: Vec[Int]; starts: Vec[Int];
  str_first: Vec[Int]; str_count: Vec[Int];
  str_struct: Vec[Int]; str_off: Vec[Int]; str_len: Vec[Int];
}

pub fn smbios_checksum8(data: &Vec[UInt8], off: Int, len: Int) -> Int
pub fn smbios_entry32_checksum_ok(data: &Vec[UInt8]) -> Bool
pub fn smbios_entry32_intermediate_checksum_ok(data: &Vec[UInt8]) -> Bool
pub fn smbios_entry64_checksum_ok(data: &Vec[UInt8]) -> Bool
pub fn smbios_entry_checksum_ok(data: &Vec[UInt8]) -> Bool

pub fn smbios_entry32_parse(data: &Vec[UInt8]) -> Result[SmbiosEntry, Str]
pub fn smbios_entry64_parse(data: &Vec[UInt8]) -> Result[SmbiosEntry, Str]
pub fn smbios_entry_parse(data: &Vec[UInt8]) -> Result[SmbiosEntry, Str]
pub fn smbios_entry_points(data: &Vec[UInt8]) -> Int

pub fn smbios_entry_kind(e: &SmbiosEntry) -> Int
pub fn smbios_entry_major(e: &SmbiosEntry) -> Int
pub fn smbios_entry_minor(e: &SmbiosEntry) -> Int
pub fn smbios_entry_docrev(e: &SmbiosEntry) -> Int
pub fn smbios_entry_revision(e: &SmbiosEntry) -> Int
pub fn smbios_entry_max_size(e: &SmbiosEntry) -> Int
pub fn smbios_entry_table_len(e: &SmbiosEntry) -> Int
pub fn smbios_entry_table_addr(e: &SmbiosEntry) -> Int
pub fn smbios_entry_count(e: &SmbiosEntry) -> Int
pub fn smbios_entry_bcd(e: &SmbiosEntry) -> Int

pub fn smbios_table_parse(table: &Vec[UInt8]) -> Result[SmbiosTable, Str]
pub fn smbios_parse(data: &Vec[UInt8]) -> Result[SmbiosTable, Str]

pub fn smbios_count(t: &SmbiosTable) -> Int
pub fn smbios_type(t: &SmbiosTable, i: Int) -> Int
pub fn smbios_length(t: &SmbiosTable, i: Int) -> Int
pub fn smbios_handle(t: &SmbiosTable, i: Int) -> Int
pub fn smbios_struct_start(t: &SmbiosTable, i: Int) -> Int
pub fn smbios_formatted_len(t: &SmbiosTable, i: Int) -> Int
pub fn smbios_find_type(t: &SmbiosTable, stype: Int) -> Int
pub fn smbios_formatted(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Result[Vec[UInt8], Str]

pub fn smbios_string_count(t: &SmbiosTable, i: Int) -> Int
pub fn smbios_string_bytes(data: &Vec[UInt8], t: &SmbiosTable, i: Int, s: Int) -> Result[Vec[UInt8], Str]
pub fn smbios_string(data: &Vec[UInt8], t: &SmbiosTable, i: Int, s: Int) -> Result[Str, Str]

pub fn smbios_bios_vendor(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_bios_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_bios_release_date(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_bios_rom_size(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_system_manufacturer(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_system_product(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_system_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_system_serial(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_uuid(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Result[Vec[UInt8], Str]
pub fn smbios_baseboard_manufacturer(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_baseboard_product(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_baseboard_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_baseboard_serial(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_baseboard_asset_tag(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_chassis_manufacturer(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_chassis_type(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_chassis_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_chassis_serial(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_chassis_asset_tag(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_chassis_type_name(chassis_type: Int) -> Str
pub fn smbios_processor_socket(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_processor_family(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_processor_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_memory_array_capacity(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_memory_device_size(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_memory_device_type(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_memory_device_speed(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int
pub fn smbios_memory_device_manufacturer(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int

pub fn smbios_entry32_build(major: Int, minor: Int, max_size: Int, table_addr: Int, table_len: Int, count: Int, bcd_rev: Int) -> Result[Vec[UInt8], Str]
pub fn smbios_entry64_build(major: Int, minor: Int, docrev: Int, revision: Int, max_size: Int, table_addr: Int) -> Result[Vec[UInt8], Str]
pub fn smbios_struct_build(stype: Int, handle: Int, formatted: &Vec[UInt8], strings: &Vec[Str]) -> Result[Vec[UInt8], Str]
pub fn smbios_image_build32(table: &Vec[UInt8], major: Int, minor: Int, bcd_rev: Int) -> Result[Vec[UInt8], Str]
```

Constants: `SMBIOS_ENTRY_32`, `SMBIOS_ENTRY_64`, `SMBIOS_TYPE_BIOS`,
`SMBIOS_TYPE_SYSTEM`, `SMBIOS_TYPE_BASEBOARD`, `SMBIOS_TYPE_CHASSIS`,
`SMBIOS_TYPE_PROCESSOR`, `SMBIOS_TYPE_MEMORY_ARRAY`,
`SMBIOS_TYPE_MEMORY_DEVICE`, `SMBIOS_TYPE_END_OF_TABLE`.

## Canonical builders

`smbios_entry32_build` writes the 31 bytes above with entry point
revision 0, five zero formatted bytes and `max_size` as passed; the
intermediate checksum (offset 15h) is sealed first and the entry-point
checksum (offset 04h) last, so both spans sum to 0.

`smbios_entry64_build` writes the 24 bytes above with a zero reserved
byte and the u64 address as the low 8 bytes of the non-negative Int, then
seals the checksum.

`smbios_struct_build(stype, handle, formatted, strings)` writes the
header, the formatted bytes verbatim and the canonical string set:
each string's UTF-8 bytes plus NUL, then one extra NUL; a zero-string
set is the documented two-NUL pair. It validates everything before
writing (atomic failure): type 0..255, handle 0..65535, formatted at
most 251 bytes, no empty strings and no string containing 00h.

`smbios_image_build32(table, major, minor, bcd_rev)` parses `table`
(surfacing any parse error), then emits the entry point at offset 0
padded with zeros to 32, followed by the table at offset 32, with
`table_addr` 32, `table_len` = the table length, the parsed structure
count and `max_size` 0. The result round-trips through `smbios_parse`
and yields the same structures; parsing and rebuilding is byte-identical
for builder output.

## Error string catalog

| Condition | Error text |
|---|---|
| `_SM_` buffer shorter than 31 bytes | `smbios: 32-bit entry point too short` |
| `_SM_` anchor mismatch at the parse offset | `smbios: bad 32-bit signature` |
| `_SM_` length byte != 1Fh | `smbios: bad 32-bit entry length` |
| `_SM_` 31-byte sum != 0 | `smbios: bad 32-bit checksum` |
| `_DMI_` anchor mismatch | `smbios: bad intermediate anchor` |
| intermediate 15-byte sum != 0 | `smbios: bad intermediate checksum` |
| `_SM3_` buffer shorter than 24 bytes | `smbios: 64-bit entry point too short` |
| `_SM3_` anchor mismatch | `smbios: bad 64-bit signature` |
| `_SM3_` length byte != 18h | `smbios: bad 64-bit entry length` |
| `_SM3_` 24-byte sum != 0 | `smbios: bad 64-bit checksum` |
| no aligned anchor anywhere | `smbios: no entry point` |
| fewer than 4 bytes left at a structure boundary, or the formatted area runs past the span | `smbios: truncated structure` |
| structure length < 4 | `smbios: invalid structure length` |
| repeated handle | `smbios: duplicate handle` |
| no double NUL before the span end | `smbios: unterminated string set` |
| declared 32-bit structure count disagrees (count > 0) | `smbios: structure count mismatch` |
| table address/length outside the image buffer | `smbios: table out of buffer` |
| structure index negative or >= count | `smbios: structure index out of range` |
| string index negative or > string count | `smbios: string index out of range` |
| recorded structure or string span outside the buffer | `smbios: structure out of bounds` / `smbios: string out of bounds` |
| string bytes are not valid UTF-8 | `smbios: invalid string bytes` |
| `smbios_uuid` on a non-System or too-short structure | `smbios: uuid out of range` |
| `smbios_entry32_build`: major/minor/bcd outside 0..255 | `smbios: major version out of range` / `smbios: minor version out of range` / `smbios: bcd revision out of range` |
| `smbios_entry32_build`: max_size outside u16 | `smbios: max structure size out of range` |
| `smbios_entry32_build`: table_addr outside u32 or negative | `smbios: table address out of range` |
| `smbios_entry32_build`: table_len outside u16 | `smbios: table length out of range` |
| `smbios_entry32_build`: count outside u16 | `smbios: structure count out of range` |
| `smbios_entry64_build`: major/minor outside 0..255 | `smbios: major version out of range` / `smbios: minor version out of range` |
| `smbios_entry64_build`: docrev/revision outside 0..255 | `smbios: docrev out of range` / `smbios: entry revision out of range` |
| `smbios_entry64_build`: max_size outside u32 | `smbios: max structure size out of range` |
| `smbios_entry64_build`: negative address | `smbios: table address out of range` |
| `smbios_struct_build`: type outside 0..255 | `smbios: structure type out of range` |
| `smbios_struct_build`: handle outside 0..65535 | `smbios: handle out of range` |
| `smbios_struct_build`: formatted area > 251 bytes | `smbios: formatted area too long` |
| `smbios_struct_build`: empty string in the set | `smbios: empty string` |
| `smbios_struct_build`: string byte 00h (defensive; an XIOM `Str` normally cannot hold it) | `smbios: string contains NUL` |

## Complexity

| Operation | Complexity |
|---|---|
| `smbios_checksum8` and the four predicates | O(len) / O(1) per entry point |
| `smbios_entry32_parse` / `smbios_entry64_parse` | O(1) |
| `smbios_entry_parse` / `smbios_entry_points` | O(data.len()/16) |
| `smbios_table_parse` / `smbios_parse` | O(bytes + structures^2) (duplicate-handle scan) |
| `smbios_count` / `smbios_type` / `smbios_length` / `smbios_handle` / `smbios_struct_start` / `smbios_formatted_len` / `smbios_string_count` | O(1) |
| `smbios_find_type` | O(structures) |
| `smbios_formatted` / `smbios_string_bytes` / `smbios_string` | O(field/string length) |
| `smbios_uuid` | O(1) |
| field accessors | O(1) |
| `smbios_chassis_type_name` | O(1) |
| `smbios_entry32_build` / `smbios_entry64_build` | O(1) |
| `smbios_struct_build` | O(formatted + string bytes) |
| `smbios_image_build32` | O(table bytes + structures^2) |

## Test plan

`tests/test_conformance.xi` (`module smbios_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. canonical `_SM_` entry point: pinned 31 bytes for
   `(2, 8, 0, 32, 0, 0, 0x28)`, both checksum predicates, preference
   parse, all ten accessors;
2. `_SM_` error catalog: short buffer, signature, length byte, checksum,
   intermediate anchor and intermediate checksum (each resealed so the
   intended error surfaces);
3. canonical `_SM3_` entry point: pinned 24 bytes, checksum, accessors,
   plus a second pinned build with docrev/revision/max-size/128-bit
   address values;
4. `_SM3_` error catalog: short, signature, length, checksum;
5. preference rule: both entry points present (64-bit wins), lone
   `_SM_` at aligned offset 16, misaligned anchor ignored, no anchor;
6. structure table: pinned counts/types/lengths/handles/starts on the
   BIOS + System + End-of-Table fixture (117 bytes) and out-of-range
   accessors;
7. string accessors: 1-indexing, index 0, out-of-range indices, raw
   bytes, and a short buffer for the bounds errors;
8. field accessors for types 0, 1, 2, 3, 4, 16 and 17 including the raw
   UUID; wrong-type and absent-field reads return -1;
9. chassis type name table including bit-7 lock stripping;
10. unknown types (200, 201) keep raw formatted and string spans; a
    non-UTF-8 string byte is `Err("smbios: invalid string bytes")`;
11. table validation: length < 4, truncation, unterminated string set,
    duplicate handle, and a unique-handle table that parses;
12. canonical no-string pair, one-string structure, type 127 stop with
    trailing bytes ignored, empty table;
13. 32-bit fixture round-trip: image layout, entry fields, absolute
    starts, strings, formatted areas, byte-identical rebuild and
    re-image;
14. `smbios_parse` 32-bit policies: count mismatch, count 0 accepted,
    address and length out of buffer, short table length, empty table;
15. 64-bit image: u64 address, `max_size` 0 / equal / cutting inside a
    structure, address outside the buffer and at the buffer end;
16. builder error catalog for entry points, structures and
    `smbios_image_build32`;
17. `smbios_checksum8` sums and invalid spans, and the four checksum
    predicates on positive and negative fixtures;
18. 32-bit image byte layout with pinned entry-point and structure
    bytes, plus the table slice.

The builder's `smbios: string contains NUL` guard is defensive and not
exercised by the suite (an XIOM `Str` cannot normally hold a 00h byte);
everything else in the catalog is covered.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.smbios
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Only the documented entry lengths 1Fh/18h; longer/revisioned entry
  point layouts are rejected.
- The 32-bit formatted area (offset 0Bh) and the `_SM3_` reserved byte
  are not interpreted.
- Value tables other than the chassis type name table are not decoded
  (processor family, memory type, ROM size scaling, UUID text form).
- Entry-point scanning is alignment-based over the given buffer; real
  firmware windows (0xF0000) are out of scope.
- A 64-bit table is bounded by the buffer end or `max_size`; a table
  whose `max_size` ends exactly between structures simply stops there
  (no error), while a bound that cuts inside a structure surfaces
  `smbios: truncated structure` or `smbios: unterminated string set`.
- Duplicate handles are always an error: no lenient mode.
- Strings are decoded as UTF-8 only; arbitrary encodings must use
  `smbios_string_bytes`.
- The store is a plain value type referencing offsets into the buffer it
  was parsed from; that buffer must stay alive for the accessors.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_entry`/`_err_entry`/`_ok_table`/`_err_table`/`_ok_str`/`_err_str`/
  `_ok_bytes`/`_err_bytes` (constructing struct payloads such as
  `Result[SmbiosTable, Str]` directly in other functions miscompiles).
- All little-endian extraction/packing is arithmetic
  (multiplication/division or modulo) because bitwise operations on
  operands with bit 31 set miscompile.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF`
  before entering Int arithmetic.
- Every `Vec[Int]` and `Vec[Str]` element read is bound to a typed local,
  and `Str` values read from vectors are compared through
  `xiom.string.compare.str_compare` (BUG 17).
- Strings are decoded with `xiom.encoding.utf8_decode`; the string
  builder's to_str path is avoided (its builder contract aborts on a
  00h byte and SMBIOS string sets are NUL-separated by construction).
- Advisory E001 ("cannot return a borrow from a function") is avoided:
  no helper returns a `Vec` derived from a `&Vec` parameter; the tests
  inline the one reseal helper instead.
- All parallel vectors are pushed together in `_table_parse` and every
  accessor re-derives and bounds-checks its spans.
- The package declares no `extern "C"` blocks (no FFI).
