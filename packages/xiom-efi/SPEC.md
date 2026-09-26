# xiom.efi -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.efi`, version `0.1.0`).
Module: `src/efi.xi` (`module xiom.efi`).
Depends on `xiom.std` (uses `xiom.string.byte_at`); tests add `xiom.test`,
`xiom.io`, `xiom.string`, `xiom.string.compare`, `xiom.encoding.hex`. No FFI.

## Scope

A pure-XIOM (no FFI) codec for a single UEFI Firmware File System (FFS) file:

- `ffs_parse` validates the 24-byte small header or the 32-byte large-file
  header and walks the section stream into an `FfsFile` index of flat
  parallel vectors;
- accessors read the file fields and the five section columns back;
- raw-span readers (`ffs_section_raw`, `ffs_section_data`) and type-specific
  readers cover the documented section types;
- `ffs_header_checksum` / `ffs_data_checksum` / `ffs_integrity_ok` implement
  the two documented integrity-check stances;
- `ffs_build` emits a canonical small-header file containing exactly one
  section, with zero-filled padding and optional additive checksums.

## Non-goals

- Firmware volume parsing: FV headers, block maps and free-space scanning
  are out of scope; the caller supplies one file image.
- PE32/TE/PIC and other executable parsing: those sections stay raw spans.
- Dependency (depex) evaluation: depex sections stay raw.
- Compression: compression payloads are never decompressed and nested
  sections inside them are never parsed.
- Large-file building: the builder emits the 24-byte header only.
- Section 4-byte alignment is documented and emitted by the builder, but not
  enforced by the parser (see "Padding rules").
- Cross-file concerns: file ordering, FV insertion policy, NVRAM variables.

## Byte-level layout

### Small file header (24 bytes)

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 16 | Name | raw GUID bytes; surfaced as 32 lowercase hex characters |
| 16 | 2 | IntegrityCheck | u16 LE: low byte `Header`, high byte `File` |
| 18 | 1 | Type | file type byte (table below) |
| 19 | 1 | Attributes | bit field (table below) |
| 20 | 3 | Size | u24 LE, whole file including header, sections and padding |
| 23 | 1 | State | raw state byte (table below) |

### Large-file header (32 bytes)

Written when `Attributes & 0x01` is set:

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0..23 | 24 | base header | identical field order to the small header |
| 20 | 3 | Size | **must be `0xFFFFFF`** (the documented extended-size rule) |
| 24 | 8 | ExtendedSize | u64 LE, the real file size |

Large-file rule: if the 0x01 bit is set and the 3-byte size field is not
`0xFFFFFF`, parsing fails with `efi: bad large-file size` before the extended
size is read. `ExtendedSize` accumulates little-endian into a signed 64-bit
`Int`, so a value with bit 63 set comes out negative and fails with
`efi: bad file size` (documented signed-range limitation).

### Attributes (offset 19)

| Bit | Name | Codec behavior |
|---|---|---|
| `0x01` | `FFS_ATTRIB_LARGE_FILE` | selects the 32-byte header and the extended size |
| `0x40` | `FFS_ATTRIB_CHECKSUM` | selects the additive checksum integrity stance |
| other | `FIXED` (`0x04`), `DATA_ALIGNMENT` (`0x38`), `DATA_ALIGNMENT_2` (`0x02`) | preserved raw, never interpreted |

### State (offset 23)

Stored raw and never validated. The PI bit meanings are documented here for
reference: `0x01` header construction, `0x02` header valid, `0x04` data
valid, `0x08` marked for update, `0x10` deleted, `0x20` header invalid.

### File types (offset 18) -- documented subset

| Type | Name | | Type | Name |
|---|---|---|---|---|
| `0x01` | `RAW` | | `0x0C` | `COMBINED_PEIM` |
| `0x02` | `FREEFORM` | | `0x0D` | `PEIM` |
| `0x03` | `SECURITY_CORE` | | `0x0E` | `DXE_DRIVER` |
| `0x04` | `PEI_CORE` | | `0x0F` | `SMM_DRIVER` |
| `0x05` | `DXE_CORE` | | `0x10` | `SMM_CORE` |
| `0x07` | `DRIVER` | | `0xE0..0xEF` | `OEM` |
| `0x09` | `APPLICATION` | | `0xF0` | `PAD` |
| `0x0A` | `SMM` | | `0xF1..0xFE` | `FFS` |
| `0x0B` | `FIRMWARE_VOLUME_IMAGE` | | `0xFF` | `FREE_SPACE` |

Everything else (including the unnamed values below `0xE0`) is `UNKNOWN` and
passes through; the parser stores the raw byte and never rejects a file
because of its type. See "Documented subset reconciliation" for why this
table is narrower than the PI registry.

### Section common header

Every section starts with 4 bytes:

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 3 | Size | u24 LE; includes this 4-byte header, the type-specific header, the data and any 4-byte alignment padding |
| 3 | 1 | Type | section type byte (table below) |

Type-specific headers follow the common header; the section data begins at
the offset named in the table. `ffs_section_data_size` is `Size` minus the
type-specific header size, so for leaf sections it includes any alignment
padding and for UI sections it includes the terminal NUL.

| Type | Name | Extra header | Data starts at |
|---|---|---|---|
| `0x01` | `COMPRESSION` | 4: `UncompressedLength` u32 LE | section + 8; payload raw |
| `0x02` | `GUID_DEFINED` | 20: GUID 16, `DataOffset` u16 LE, `Attributes` u16 LE | section + `DataOffset` (`20 <= DataOffset <= Size`) |
| `0x03` | `DISPOSABLE` | none | section + 4; nested sections raw |
| `0x10` | `PE32` | none | section + 4; raw |
| `0x11` | `PIC` | none | section + 4; raw |
| `0x12` | `TE` | none | section + 4; raw |
| `0x13` | `DXE_DEPEX` | none | section + 4; raw |
| `0x14` | `VERSION` | 4: `BuildNumber` u16 LE, `Version` u16 LE | section + 4; span is the 4 payload bytes |
| `0x15` | `USER_INTERFACE` | none (body is the string) | section + 4; UTF-16LE, even length, ends in `0x0000` |
| `0x16` | `COMPATIBILITY16` | none | section + 4; raw |
| `0x17` | `FIRMWARE_VOLUME_IMAGE` | none | section + 4; raw |
| `0x18` | `FREEFORM_SUBTYPE_GUID` | 16: GUID | section + 20 |
| `0x19` | `RAW` | none | section + 4 |
| `0x1B` | `PEI_DEPEX` | none | section + 4; raw |
| `0x1C` | `SMM_DEPEX` | none | section + 4; raw |

Any other type is `UNKNOWN`: treated as a leaf with no extra header and kept
raw. VERSION sections use a documented 4-byte payload (build u16 + version
u16); the PI triple (build/minor/major) is not modeled. UI strings are
validated at parse time: an odd-sized body or a body whose last code unit is
not `0x0000` is `efi: bad ui string`.

### Padding rules

- The canonical builder pads a section to the next 4-byte boundary
  (section sizes are multiples of 4 on output) and then pads the whole file
  to the next 8-byte boundary; the declared `Size` fields include that
  padding.
- The parser accepts a section stream that ends with all-zero trailing bytes
  (the documented 8-byte file alignment pad): the walk stops at the first
  remainder that is entirely zero. A non-zero remainder shorter than a
  4-byte section header is `efi: truncated section`.
- Section sizes are not required to be multiples of 4 by the parser; the
  alignment expectation is documented and honored by the builder only.
- The parser accepts a buffer longer than the declared file size and ignores
  the extra bytes.

## API signatures

All functions are free functions in module `xiom.efi` (no self methods):

```xi
pub type FfsFile = {
  name: Str;
  integrity_check: Int;
  file_type: Int;
  attributes: Int;
  size: Int;
  state: Int;
  large: Bool;
  header_size: Int;
  section_types: Vec[Int];
  section_sizes: Vec[Int];
  section_offsets: Vec[Int];
  section_data_offsets: Vec[Int];
  section_data_sizes: Vec[Int];
}

pub fn ffs_parse(data: &Vec[UInt8]) -> Result[FfsFile, Str]
pub fn ffs_build(name: Str, file_type: Int, attributes: Int, state: Int, section_type: Int, body: &Vec[UInt8]) -> Result[Vec[UInt8], Str]

pub fn ffs_file_name(f: &FfsFile) -> Str
pub fn ffs_file_type(f: &FfsFile) -> Int
pub fn ffs_file_type_name(t: Int) -> Str
pub fn ffs_file_attributes(f: &FfsFile) -> Int
pub fn ffs_file_size(f: &FfsFile) -> Int
pub fn ffs_file_state(f: &FfsFile) -> Int
pub fn ffs_file_integrity_check(f: &FfsFile) -> Int
pub fn ffs_file_is_large(f: &FfsFile) -> Bool
pub fn ffs_file_header_size(f: &FfsFile) -> Int

pub fn ffs_section_count(f: &FfsFile) -> Int
pub fn ffs_section_type(f: &FfsFile, i: Int) -> Int
pub fn ffs_section_type_name(t: Int) -> Str
pub fn ffs_section_size(f: &FfsFile, i: Int) -> Int
pub fn ffs_section_offset(f: &FfsFile, i: Int) -> Int
pub fn ffs_section_data_offset(f: &FfsFile, i: Int) -> Int
pub fn ffs_section_data_size(f: &FfsFile, i: Int) -> Int

pub fn ffs_section_raw(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Result[Vec[UInt8], Str]
pub fn ffs_section_data(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Result[Vec[UInt8], Str]

pub fn ffs_section_build_number(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int
pub fn ffs_section_version(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int
pub fn ffs_section_ui_string(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Str
pub fn ffs_section_guid(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Str
pub fn ffs_section_guid_data_offset(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int
pub fn ffs_section_guid_attributes(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int
pub fn ffs_section_compression_length(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int

pub fn ffs_header_checksum(data: &Vec[UInt8], f: &FfsFile) -> Int
pub fn ffs_data_checksum(data: &Vec[UInt8], f: &FfsFile) -> Int
pub fn ffs_integrity_ok(data: &Vec[UInt8], f: &FfsFile) -> Bool
```

## Semantics

`ffs_parse(data)`
: Validation runs header-first (see the error catalog); the section walk then
  records one element per section in five parallel vectors. Offsets are
  absolute indices into `data`. Unknown types pass through. On `Err`, nothing
  is returned. An empty section stream (`size == header_size`) is valid.

`ffs_file_type_name(t)` / `ffs_section_type_name(t)`
: Pure mappings of the documented tables; `"UNKNOWN"` for unnamed values.

`ffs_section_count(f)`
: The minimum of the five parallel vector lengths, so a hand-built `FfsFile`
  with drifted vectors reports the indexing maximum. A parsed file reports
  the number of sections walked.

`ffs_section_type/size/offset/data_offset/data_size(f, i)`
: `-1` when `i < 0` or `i >= ffs_section_count(f)`; no error channel.

`ffs_section_raw(data, f, i)`
: Copies the whole section span (`section_size` bytes from `section_offset`).

`ffs_section_data(data, f, i)`
: Copies the data span (`section_data_size` bytes from
  `section_data_offset`); verbatim, so UI NUL terminators and padding are
  included.

`ffs_section_build_number/version(data, f, i)`
: `-1` unless section `i` is a VERSION section with a 4-byte data span that
  fits in `data`; otherwise the u16 LE at data offset +0 / +2.

`ffs_section_ui_string(data, f, i)`
: `""` unless section `i` is a UI section with a fitting span; otherwise the
  UTF-16LE body decoded to printable ASCII: scanning stops at the first
  `0x0000` code unit and every code unit outside `0x20..0x7E` becomes `?`.

`ffs_section_guid(data, f, i)`
: 32 lowercase hex characters for a GUID_DEFINED or FREEFORM_SUBTYPE_GUID
  section (the 16 bytes at section offset +4); `""` otherwise. The
  GUID_DEFINED `DataOffset` and `Attributes` fields have their own readers
  and return `-1` for other types.

`ffs_section_compression_length(data, f, i)`
: The `UncompressedLength` u32 LE of a COMPRESSION section, or `-1`. The
  payload is never decompressed.

`ffs_header_checksum` / `ffs_data_checksum`
: The documented additive 8-bit checksums: the value that, placed in the low
  (resp. high) integrity byte, makes the sum of the covered bytes 0 modulo
  256. The header checksum covers `[0, header_size)` with the low integrity
  byte treated as zero (all other bytes, including the high integrity byte
  and the extended size, as stored). The data checksum covers
  `[header_size, size)`. Both return `-1` when the recorded spans do not fit
  in `data`.

`ffs_integrity_ok(data, f)`
: The documented stance: when `FFS_ATTRIB_CHECKSUM` (`0x40`) is clear the
  16-bit integrity check must be `0x0000`; when set, the low byte must equal
  `ffs_header_checksum` and the high byte must equal `ffs_data_checksum`.
  `ffs_parse` never rejects a mismatch; this helper is opt-in. False when the
  recorded header/size span does not fit in `data`.

`ffs_build(name, file_type, attributes, state, section_type, body)`
: Validates in order: `name` is exactly 32 hex characters -> `efi: bad name`;
  `file_type` in `0..255` -> `efi: bad file type`; `attributes` in `0..255`
  -> `efi: bad attributes`; the large-file bit is clear ->
  `efi: large files unsupported`; `state` in `0..255` -> `efi: bad state`;
  `section_type` in `0..255` -> `efi: bad section type`; the body satisfies
  the documented per-type minimums (COMPRESSION >= 4, GUID_DEFINED >= 20 with
  a data offset in `20..4+len`, FREEFORM_SUBTYPE_GUID >= 16, VERSION >= 4, UI
  even and NUL-terminated) -> `efi: bad section body`. It then writes the
  24-byte header, the one section, 4-byte section padding and 8-byte file
  padding, and rejects a padded file above `0xFFFFFF` bytes with
  `efi: file too large`. With `FFS_ATTRIB_CHECKSUM` set, the data checksum is
  patched into byte 17 and the header checksum (computed afterwards) into
  byte 16. The result always has a length that is a multiple of 8.

## Error string catalog

| Condition | Error text |
|---|---|
| buffer shorter than 24 (small) or 32 (large) bytes | `efi: truncated header` |
| large bit set and the 3-byte size field is not `0xFFFFFF` | `efi: bad large-file size` |
| declared size below the header size, or a negative extended size | `efi: bad file size` |
| declared size exceeds the buffer | `efi: truncated file` |
| declared section size below 4 | `efi: bad section size` |
| declared section size exceeds the remaining bytes | `efi: section overruns file` |
| non-zero trailing remainder shorter than 4 bytes | `efi: truncated section` |
| section smaller than its documented type header | `efi: section too small` |
| GUID_DEFINED data offset outside `20..Size` | `efi: bad section data offset` |
| UI body odd-sized or missing the terminal `0x0000` | `efi: bad ui string` |
| `ffs_section_raw` / `ffs_section_data`: bad index | `efi: index out of range` |
| `ffs_section_raw` / `ffs_section_data`: recorded span beyond `data.len()` | `efi: span out of bounds` |
| build: name not exactly 32 hex characters | `efi: bad name` |
| build: file type outside `0..255` | `efi: bad file type` |
| build: attributes outside `0..255` | `efi: bad attributes` |
| build: large-file bit set | `efi: large files unsupported` |
| build: state outside `0..255` | `efi: bad state` |
| build: section type outside `0..255` | `efi: bad section type` |
| build: body violates the documented per-type minimums | `efi: bad section body` |
| build: padded file would exceed `0xFFFFFF` bytes | `efi: file too large` |

`ffs_parse` validation order: header size, large-file rule, extended-size
sign, size-vs-header, size-vs-buffer, then the section walk left to right.

## Complexity

| Operation | Complexity |
|---|---|
| `ffs_parse` | O(data.len()) |
| file and section accessors, `ffs_section_type_name`, `ffs_file_type_name` | O(1) |
| `ffs_section_raw` | O(section size) |
| `ffs_section_data` | O(section data size) |
| `ffs_section_ui_string` | O(section data size) |
| `ffs_header_checksum` / `ffs_data_checksum` | O(header_size) / O(size - header_size) |
| `ffs_integrity_ok` | O(size) |
| `ffs_build` | O(body length) |

## Test plan

`tests/test_conformance.xi` (`module efi_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. small fixture header fields pinned (name/type/attributes/size/state/
   integrity/large/header size);
2. small fixture section columns pinned (count, types, sizes, section/data
   offsets and data sizes);
3. exact raw and data spans for both sections;
4. UI string decode (`boot`), non-UI reads are `""`, non-ASCII -> `?`;
5. VERSION section build number/version and builder byte-equality;
6. GUID_DEFINED GUID text, data offset field, attributes, data span and the
   accepted trailing file pad;
7. COMPRESSION uncompressed length and raw nested payload (not walked);
8. unknown type `0x42` passes through raw;
9. the documented file/section type-name tables;
10. large-file fixture: 32-byte header, ExtendedSize, section at offset 32;
11. parse errors: empty/23-byte/31-byte truncation, bad large-file size
    field, negative extended size;
12. parse errors: size 0/23 below the header, size beyond the buffer;
13. parse errors: section size 0/3, overrun, non-zero 2-byte tail, and the
    accepted 1/2-byte all-zero pads;
14. parse errors: per-type minima (COMPRESSION/VERSION/FREEFORM_SUBTYPE_GUID/
    GUID_DEFINED) and both illegal GUID data offsets;
15. parse errors: UI without terminal NUL and odd-sized UI;
16. integrity stances: pinned header/data checksums (202/142), zero-vector
    requirement, checksum-bit fixture (252/142), corruption detection and
    `-1` on short buffers;
17. builder RAW exact bytes plus parse-back;
18. builder UI exact bytes, section size 16 and parse-back;
19. builder 4-byte section / 8-byte file alignment over body lengths 0..5;
20. builder errors: bad name/type/attributes/state/section type/body and
    large-file rejection;
21. accessor out-of-range `-1`/`""`/`Err` and a drifted `FfsFile`;
22. spans beyond a truncated buffer are `Err` and read as empty.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.efi
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Documented subset reconciliation

The port brief listed several section type codes with names that do not
match the PI registry (for example "0x19/0x18 GUID-defined", "PE32/TE/PIC
... 0x10/0x12/0x07", "0x01/0x02 VERSION/COMPAT/FEATURES"). This package
pins the PI section type table instead: `0x01` COMPRESSION, `0x02`
GUID_DEFINED, `0x14` VERSION, `0x15` USER_INTERFACE, `0x18`
FREEFORM_SUBTYPE_GUID, `0x19` RAW, and PE32/PIC/TE at `0x10/0x11/0x12` kept
as raw spans. The documented FFS file type subset follows the brief's table
verbatim even where it differs from the current PI registry (the brief's
`0x0D` PEIM and `0x10` SMM_CORE labels are preserved; the PI registry uses
`0x06` PEIM and `0x0D` MM_CORE). Both tables are documented subsets, not
validation gates: unknown values always pass through.

## Known limitations

- Single file only; firmware volume structure is not parsed.
- Large files can be parsed but not built; the canonical builder always
  emits the 24-byte header.
- The `Size` field must count the whole file; a file whose declared size is
  smaller than the buffer silently ignores the extra bytes.
- Section 4-byte alignment is a documented expectation, not a parse rule.
- VERSION payloads are modeled as 4 bytes (build u16 + version u16), not the
  PI build/minor/major triple.
- UI strings decode to printable ASCII; non-ASCII code units (including
  surrogate pairs) become `?` and cannot be reproduced by the builder.
- Integrity checks are opt-in and never enforced by `ffs_parse`.
- 64-bit extended sizes with bit 63 set are rejected (signed `Int`).
- Not thread-safe; `FfsFile` is a plain value type.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_file`/`_err_file`/`_ok_bytes`/`_err_bytes` (constructing Results
  directly in other functions miscompiles in this compiler).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic; `&` is only used with the small masks `1`,
  `0x01` and `0x40`.
- Little-endian packing is arithmetic (modulo/division), exact for values
  with bit 31 set; the xiom.gpt `_byte_at`/`_le64` shapes are reused.
- `file_type` is spelled out because `type` is a reserved keyword.
- The tests never use `==` on a `Str` read from a `Vec`; string comparisons
  go through `xiom.string.compare.str_compare` (BUG 17).
- The package declares no `extern "C"` blocks (no FFI).
