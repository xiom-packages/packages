# xiom.pe SPEC

## Scope

Pure-XIOM structural codec for the header layer of a Windows Portable
Executable image: the DOS header (`"MZ"`, e_lfanew at offset 0x3C) with its
stub span, the `"PE\0\0"` signature, the 20-byte COFF file header, the
optional header in its PE32 (0x10B) and PE32+ (0x20B) forms through a
documented field subset, the raw data directory records, the section table,
and a canonical builder. Storage is flat: `PeImage` holds the sections and
the data directories as parallel `Vec`s, never `Vec[StructType]`.

## Non-goals

Imports, exports and relocations (the `pointerToRelocations` /
`pointerToLineNumbers` fields are carried, the relocation and line-number
counts are not); resource parsing; .NET metadata (CLI headers, COR20);
Authenticode / certificate tables; debug directories; delay imports; bound
imports; payload or instruction decoding; RVA-to-file-offset translation;
loading, mapping or relocation; streaming I/O. Every data directory is an
opaque `(virtualAddress, size)` record.

## Container layout

All multi-byte fields are little-endian.

### DOS header (64 bytes at offset 0)

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | magic `"MZ"` (0x5A4D) |
| 2 | 58 | DOS header remainder (not decoded; builder emits zero) |
| 60 | 4 | `e_lfanew` (`0x3C`), must be >= 64 and fit the signature |

The DOS stub is the opaque run `64..e_lfanew`; `pe_stub` copies it and
`pe_build_headers` requires exactly `stub_size` bytes from the caller.

### PE signature

`"PE\0\0"` (bytes 0x50 0x45 0x00 0x00) at `e_lfanew`.

### COFF file header (20 bytes at `e_lfanew + 4`)

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | `machine` |
| 2 | 2 | `numberOfSections` (documented range 1..96) |
| 4 | 4 | `timeDateStamp` |
| 8 | 4 | `pointerToSymbolTable` |
| 12 | 4 | `numberOfSymbols` |
| 16 | 2 | `sizeOfOptionalHeader` |
| 18 | 2 | `characteristics` |

`pe_machine_name` maps the documented machines: `0x14C` i386, `0x1C0` arm,
`0x200` ia64, `0x8664` amd64, `0xAA64` arm64; anything else is "unknown".
The documented `characteristics` bits are `PE_FILE_RELOCS_STRIPPED` (0x1),
`PE_FILE_EXECUTABLE_IMAGE` (0x2), `PE_FILE_LARGE_ADDRESS_AWARE` (0x20),
`PE_FILE_32BIT_MACHINE` (0x100), `PE_FILE_SYSTEM` (0x1000) and `PE_FILE_DLL`
(0x2000); the 16-bit field itself is carried through untouched.

### Optional header

The decoded subset, with offsets relative to the start of the optional
header (which is at `e_lfanew + 24`):

| Offset | Size | Field | PE32 | PE32+ |
|---|---|---|---|---|
| 0 | 2 | `magic` (0x10B / 0x20B) | yes | yes |
| 16 | 4 | `addressOfEntryPoint` | yes | yes |
| 24 | 8 | `imageBase` (u64) | - | yes |
| 28 | 4 | `imageBase` (u32) | yes | - |
| 32 | 4 | `sectionAlignment` | yes | yes |
| 36 | 4 | `fileAlignment` | yes | yes |
| 56 | 4 | `sizeOfImage` | yes | yes |
| 60 | 4 | `sizeOfHeaders` | yes | yes |
| 68 | 2 | `subsystem` | yes | yes |
| 92 | 4 | `numberOfRvaAndSizes` | yes | - |
| 108 | 4 | `numberOfRvaAndSizes` | - | yes |

Base size: 96 (PE32), 112 (PE32+), including the `numberOfRvaAndSizes`
field. Every other optional-header byte (linker/OS/image/subsystem version
fields, `sizeOfCode`, `baseOfCode`, `baseOfData`, checksum, DLL
characteristics, stack/heap sizes, loader flags, and any padding between the
directories and `sizeOfOptionalHeader`) is not decoded; the builder emits
zero there.

`imageBase` is carried as a signed 64-bit `Int`. PE32+ values with bit 63
set are rejected (`pe: image base out of range`), so 0 <= imageBase <
2^63; PE32 values must fit 32 bits.

### Data directories

`numberOfRvaAndSizes` directories of 8 bytes each start at offset
`base` (96 / 112):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `virtualAddress` |
| 4 | 4 | `size` |

`numberOfRvaAndSizes` must be 0..16 (`PE_MAX_RVA_AND_SIZES`), the
directories must fit inside `sizeOfOptionalHeader`, and each record is
carried raw: no directory is interpreted or cross-checked against
`sizeOfImage`.

### Section table

`numberOfSections` 40-byte entries start at `optionalOffset +
sizeOfOptionalHeader`:

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | `name` |
| 8 | 4 | `virtualSize` |
| 12 | 4 | `virtualAddress` |
| 16 | 4 | `sizeOfRawData` |
| 20 | 4 | `pointerToRawData` |
| 24 | 4 | `pointerToRelocations` |
| 28 | 4 | `pointerToLineNumbers` |
| 32 | 2 | `numberOfRelocations` (not retained; builder writes 0) |
| 34 | 2 | `numberOfLineNumbers` (not retained; builder writes 0) |
| 36 | 4 | `characteristics` |

Name rules: the field is 1..8 printable ASCII bytes (0x20..0x7E), NUL
padded; bytes after the first NUL must be NUL; an all-NUL field is `pe:
empty section name`; a leading `/` is the linker slash-comment long-name
form and is rejected (`pe: slash-comment section name`); any other
non-printable byte is `pe: invalid section name`. The name is rebuilt from
a printable-ASCII table, so a `Str` name can never contain a NUL.

Raw span rules: `sizeOfRawData == 0` requires `pointerToRawData == 0`;
`sizeOfRawData > 0` requires `pointerToRawData >= end of the section table`
(no overlap with the header block) and `pointerToRawData + sizeOfRawData <=
buffer length`, else `pe: section raw span out of bounds`.

The documented `characteristics` bits are `PE_SCN_CNT_CODE` (0x20),
`PE_SCN_CNT_INITIALIZED_DATA` (0x40),
`PE_SCN_CNT_UNINITIALIZED_DATA` (0x80), `PE_SCN_MEM_DISCARDABLE`
(0x02000000), `PE_SCN_MEM_EXECUTE` (0x20000000), `PE_SCN_MEM_READ`
(0x40000000) and `PE_SCN_MEM_WRITE` (0x80000000); the u32 field itself is
carried through untouched.

## Validation rules and order

`pe_parse` checks, in this order (tests assert the exact messages):

1. `data.len() < 64` -> `pe: truncated dos header`.
2. Bytes 0..1 not `"MZ"` -> `pe: bad dos magic`.
3. `e_lfanew < 64` -> `pe: invalid e_lfanew`.
4. `e_lfanew > data.len() - 4` -> `pe: e_lfanew out of range`.
5. Bytes `e_lfanew..e_lfanew+4` not `"PE\0\0"` -> `pe: bad pe signature`.
6. `e_lfanew + 24 > data.len()` -> `pe: truncated coff header`.
7. `numberOfSections` outside 1..96 -> `pe: invalid section count`.
8. Optional header not fully inside the buffer -> `pe: truncated optional
   header`.
9. `sizeOfOptionalHeader < 2` -> `pe: optional header too small`.
10. `magic` not 0x10B / 0x20B -> `pe: unsupported optional header magic`.
11. `sizeOfOptionalHeader < 96` (PE32) / `< 112` (PE32+) -> `pe: optional
    header too small`.
12. PE32+ `imageBase` high dword > 0x7FFFFFFF -> `pe: image base out of
    range`.
13. `sectionAlignment` not a nonzero power of two -> `pe: invalid section
    alignment`.
14. `fileAlignment` not a power of two in 512..65536 -> `pe: invalid file
    alignment`.
15. `numberOfRvaAndSizes > 16` -> `pe: invalid numberOfRvaAndSizes`.
16. `96|112 + 8 * numberOfRvaAndSizes > sizeOfOptionalHeader` -> `pe: data
    directories exceed optional header`.
17. Section table (`40 * numberOfSections` bytes after the optional header)
    not fully inside the buffer -> `pe: truncated section table`.
18. Per section, in table order: name rules, then raw span rules.

The parse never requires `numberOfRvaAndSizes` directory records to be
nonzero, and it accepts a file whose section raw sizes are all zero
(header-only).

## API

```xiom
pub type PeImage = {
  file_size: Int; pe_offset: Int; stub_size: Int;
  machine: Int; number_of_sections: Int; time_date_stamp: Int;
  pointer_to_symbol_table: Int; number_of_symbols: Int;
  size_of_optional_header: Int; characteristics: Int;
  optional_magic: Int; address_of_entry_point: Int; image_base: Int;
  section_alignment: Int; file_alignment: Int;
  size_of_image: Int; size_of_headers: Int; subsystem: Int;
  number_of_rva_and_sizes: Int;
  dir_virtual_addresses: Vec[Int]; dir_sizes: Vec[Int];
  section_names: Vec[Str];
  section_virtual_sizes: Vec[Int]; section_virtual_addresses: Vec[Int];
  section_raw_sizes: Vec[Int]; section_raw_pointers: Vec[Int];
  section_reloc_pointers: Vec[Int]; section_line_pointers: Vec[Int];
  section_characteristics: Vec[Int];
}

pub fn pe_parse(data: &Vec[UInt8]) -> Result[PeImage, Str]
pub fn pe_is_valid(data: &Vec[UInt8]) -> Bool
pub fn pe_stub(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn pe_build_headers(img: &PeImage, stub: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn pe_build(img: &PeImage, stub: &Vec[UInt8], raw: &Vec[UInt8]) -> Result[Vec[UInt8], Str]

pub fn pe_machine(img: &PeImage) -> Int
pub fn pe_machine_name(machine: Int) -> Str
pub fn pe_section_count(img: &PeImage) -> Int
pub fn pe_section_name(img: &PeImage, i: Int) -> Str
pub fn pe_section_virtual_size(img: &PeImage, i: Int) -> Int
pub fn pe_section_virtual_address(img: &PeImage, i: Int) -> Int
pub fn pe_section_raw_size(img: &PeImage, i: Int) -> Int
pub fn pe_section_raw_pointer(img: &PeImage, i: Int) -> Int
pub fn pe_section_reloc_pointer(img: &PeImage, i: Int) -> Int
pub fn pe_section_line_pointer(img: &PeImage, i: Int) -> Int
pub fn pe_section_characteristics(img: &PeImage, i: Int) -> Int
pub fn pe_find_section(img: &PeImage, name: Str) -> Int
pub fn pe_entry_point(img: &PeImage) -> Int
pub fn pe_image_base(img: &PeImage) -> Int
pub fn pe_subsystem(img: &PeImage) -> Int
pub fn pe_directory_count(img: &PeImage) -> Int
pub fn pe_directory_virtual_address(img: &PeImage, i: Int) -> Int
pub fn pe_directory_size(img: &PeImage, i: Int) -> Int
pub fn pe_pe_offset(img: &PeImage) -> Int
pub fn pe_stub_size(img: &PeImage) -> Int
pub fn pe_optional_offset(img: &PeImage) -> Int
pub fn pe_optional_magic(img: &PeImage) -> Int
pub fn pe_file_size(img: &PeImage) -> Int
pub fn pe_size_of_image(img: &PeImage) -> Int
pub fn pe_size_of_headers(img: &PeImage) -> Int
pub fn pe_section_alignment(img: &PeImage) -> Int
pub fn pe_file_alignment(img: &PeImage) -> Int
pub fn pe_characteristics(img: &PeImage) -> Int
pub fn pe_time_date_stamp(img: &PeImage) -> Int
```

Public constants: `PE_DOS_MAGIC`, `PE_DOS_HEADER_SIZE`, `PE_LFANEW_OFFSET`,
`PE_SIGNATURE`, `PE_COFF_HEADER_SIZE`, `PE_SECTION_ENTRY_SIZE`,
`PE_DIRECTORY_ENTRY_SIZE`, `PE32_MAGIC`, `PE32_PLUS_MAGIC`,
`PE32_OPTIONAL_SIZE`, `PE32_PLUS_OPTIONAL_SIZE`, `PE_MAX_SECTIONS`,
`PE_MAX_RVA_AND_SIZES`, `PE_MIN_FILE_ALIGNMENT`, `PE_MAX_FILE_ALIGNMENT`,
the `PE_MACHINE_*` values, the `PE_FILE_*` and `PE_SCN_*` bits, and
`PE_SUBSYSTEM_WINDOWS_GUI` / `PE_SUBSYSTEM_WINDOWS_CUI`.

### Contract notes

- `pe_parse` requires only the header layer and the section table; section
  raw data is located and bounds-checked but never copied.
- `PeImage` is the builder's spec as well as the parse result: all section
  Vecs must be the same length as `section_names`, and
  `number_of_sections` must equal that length; `number_of_rva_and_sizes`
  must equal the length of both directory Vecs.
- `pe_build_headers` emits exactly `e_lfanew + 24 + sizeOfOptionalHeader +
  40 * numberOfSections` bytes: `"MZ"`, 58 zero bytes, `e_lfanew`,
  `stub`, `"PE\0\0"`, the COFF header, the optional header with the
  undecoded fields zeroed and any padding between the directories and
  `sizeOfOptionalHeader` zero-filled, then the section table with
  `numberOfRelocations` / `numberOfLineNumbers` written as zero.
- `pe_build` emits the header block, then every section's raw bytes at its
  absolute `pointerToRawData`, zero-filling everything else; `raw` holds the
  sections' on-disk bytes in table order (its length must equal the sum of
  the nonzero `sizeOfRawData` values); a nonzero raw span must start at or
  after the end of the header block; overlapping spans are written in table
  order. The result is re-parsed with `pe_parse` and its error forwarded, so
  a successful build always parses back.
- `pe_stub` runs the full parse first, then copies
  `64..e_lfanew`.
- Str names are compared with `xiom.string.compare.str_compare`
  (`pe_find_section` is exact-case); never with `==`.
- All functions are free functions; no function is named `log`; no
  `Vec[StructType]` and no `Vec[fn]` are declared.

## Error catalog

### Parsing

| Condition | Message |
|---|---|
| buffer shorter than 64 bytes | `pe: truncated dos header` |
| bytes 0-1 are not `MZ` | `pe: bad dos magic` |
| `e_lfanew < 64` | `pe: invalid e_lfanew` |
| `e_lfanew + 4 > buffer length` | `pe: e_lfanew out of range` |
| bytes at `e_lfanew` are not `PE\0\0` | `pe: bad pe signature` |
| `e_lfanew + 24 > buffer length` | `pe: truncated coff header` |
| `numberOfSections` 0 or > 96 | `pe: invalid section count` |
| optional header extends past the buffer | `pe: truncated optional header` |
| `sizeOfOptionalHeader < 2`, or below 96/112 for the magic | `pe: optional header too small` |
| magic not 0x10B / 0x20B | `pe: unsupported optional header magic` |
| PE32+ `imageBase` with bit 63 set | `pe: image base out of range` |
| `sectionAlignment` 0 or not a power of two | `pe: invalid section alignment` |
| `fileAlignment` not a power of two in 512..65536 | `pe: invalid file alignment` |
| `numberOfRvaAndSizes > 16` | `pe: invalid numberOfRvaAndSizes` |
| directories do not fit `sizeOfOptionalHeader` | `pe: data directories exceed optional header` |
| section table extends past the buffer | `pe: truncated section table` |
| section name starts with `/` | `pe: slash-comment section name` |
| section name byte outside 0x20..0x7E, or nonzero after NUL | `pe: invalid section name` |
| section name all NUL | `pe: empty section name` |
| zero-size section with a nonzero raw pointer | `pe: section raw span out of bounds` |
| nonzero raw span starting before the section table or ending past the buffer | `pe: section raw span out of bounds` |

### Building

| Condition | Message |
|---|---|
| `pe_offset` negative, > 2^32-1, or < 64 | `pe: invalid e_lfanew` |
| `stub_size != pe_offset - 64`, or `stub.len() != stub_size` | `pe: stub size mismatch` |
| `machine` outside 0..65535 | `pe: machine out of range` |
| `number_of_sections` outside 0..65535 | `pe: section count out of range` |
| `number_of_sections` outside 1..96 | `pe: invalid section count` |
| `number_of_sections != section_names.len()` | `pe: section count mismatch` |
| any other section Vec length differs | `pe: section table length mismatch` |
| `time_date_stamp` outside 0..2^32-1 | `pe: time date stamp out of range` |
| `pointer_to_symbol_table` outside 0..2^32-1 | `pe: symbol table pointer out of range` |
| `number_of_symbols` outside 0..2^32-1 | `pe: symbol count out of range` |
| `size_of_optional_header` outside 0..65535 | `pe: optional header size out of range` |
| `characteristics` outside 0..65535 | `pe: characteristics out of range` |
| magic not 0x10B / 0x20B | `pe: unsupported optional header magic` |
| `size_of_optional_header` below 96/112 | `pe: optional header too small` |
| `address_of_entry_point` outside 0..2^32-1 | `pe: entry point out of range` |
| PE32 `image_base` outside 0..2^32-1, or PE32+ negative | `pe: image base out of range` |
| `section_alignment` 0 or not a power of two | `pe: invalid section alignment` |
| `file_alignment` not a power of two in 512..65536 | `pe: invalid file alignment` |
| `size_of_image` outside 0..2^32-1 | `pe: size of image out of range` |
| `size_of_headers` outside 0..2^32-1 | `pe: size of headers out of range` |
| `subsystem` outside 0..65535 | `pe: subsystem out of range` |
| `number_of_rva_and_sizes` negative or > 16 | `pe: invalid numberOfRvaAndSizes` |
| directory Vec lengths differ from the count | `pe: directory count mismatch` |
| the two directory Vecs differ | `pe: directory table length mismatch` |
| directories do not fit `size_of_optional_header` | `pe: data directories exceed optional header` |
| directory `virtualAddress` outside 0..2^32-1 | `pe: directory virtual address out of range` |
| directory `size` outside 0..2^32-1 | `pe: directory size out of range` |
| section name fails the name rules | `pe: invalid section name` |
| section `virtualSize` outside 0..2^32-1 | `pe: section virtual size out of range` |
| section `virtualAddress` outside 0..2^32-1 | `pe: section virtual address out of range` |
| section `sizeOfRawData` outside 0..2^32-1 | `pe: section raw size out of range` |
| section `pointerToRawData` outside 0..2^32-1 | `pe: section raw pointer out of range` |
| section `pointerToRelocations` outside 0..2^32-1 | `pe: relocation pointer out of range` |
| section `pointerToLineNumbers` outside 0..2^32-1 | `pe: line number pointer out of range` |
| section `characteristics` outside 0..2^32-1 | `pe: section characteristics out of range` |
| zero-size section with a nonzero raw pointer | `pe: section raw span out of bounds` |
| `pe_build`: nonzero raw size with pointer before the header block | `pe: section raw span out of bounds` |
| `pe_build`: `raw.len()` != sum of nonzero raw sizes | `pe: raw data size mismatch` |

`pe_build` forwards every `pe_build_headers` message, and its final
re-parse forwards every `pe_parse` message.

## Test matrix

| # | Check |
|---|---|
| 1 | PE32+ fixture (2560 bytes) decodes every documented COFF/optional-header field, `pe_is_valid` and the structural accessors. |
| 2 | DOS magic and e_lfanew bytes, stub span accessors, `pe_stub` byte-exact copy (with pinned first bytes), and its truncation error. |
| 3 | Section accessors: names, virtual size/address, raw size/pointer, reloc/line pointers, characteristics; `pe_find_section` hit/miss. |
| 4 | Optional-header accessors, all 16 raw directory records, out-of-range directory sentinels, `pe_machine_name` table. |
| 5 | `pe_build_headers` reproduces the 472-byte fixture header block byte for byte (pinned magic/signature/sizes/entry/imageBase/directories/section-table bytes). |
| 6 | `pe_build` reproduces the whole PE32+ fixture byte for byte, twice (determinism), and the rebuild parses to the same fields. |
| 7 | PE32 fixture (0x10B, no stub, one section, 2 directories) parses, copies its empty stub, and rebuilds byte for byte. |
| 8 | A spec with all raw sizes zero builds a 472-byte header-only file from both builders, parses back, and copies its stub. |
| 9 | DOS header/signature catalog: truncation at 63, both magic bytes, e_lfanew below 64 / out of range, truncated COFF, all four signature bytes. |
| 10 | COFF/optional catalog: section count 0/97, truncated optional header, size 2 and 111, magic 0x10A/0x20A, truncated section table, directories exceeding the optional header, `numberOfRvaAndSizes` 17, PE32+ imageBase bit 63. |
| 11 | Alignment rules: section 3 and 0, file 0x300, 256, 131072 and 0 rejected; 512/512 accepted. |
| 12 | Name rules: slash form (both sections), non-printable byte, nonzero after NUL, all-NUL name, an 8-character name, and a NUL-filled 8th byte. |
| 13 | Raw span rules: size overrun, pointer into the header block, zero size with nonzero pointer, second-section overrun, and a valid zero/zero span. |
| 14 | Builder ranges/cross-checks: stub size, count mismatch, table length drift, machine, entry point, imageBase, both alignments, raw-size range, name, `numberOfRvaAndSizes`, directory count, directories-exceed, and a forwarded raw-size error. |
| 15 | `pe_build`: raw size mismatch (empty and short), span overlap, forwarded `e_lfanew` error, and a successful byte-exact build. |
| 16 | Out-of-range sentinels for every section accessor and `pe_find_section`, plus exact-case lookup. |
| 17 | Directory Vec drift: truncated `dir_virtual_addresses` (count mismatch) and truncated `dir_sizes` (table length mismatch). |
| 18 | High-bit u32 fields (`timeDateStamp`, `numberOfSymbols`, section characteristics 0x80000000) round-trip; `pe_stub` forwards parse errors and reproduces the stub. |

## Known limitations

- The header layer only: no imports/exports/relocations/resources/.NET
  metadata/Authenticode/debug data, and no RVA-to-offset translation.
- Raw spans may not overlap the header block, but section spans are not
  required to be disjoint from each other (the builder writes them in table
  order) and are not checked against `fileAlignment`.
- `numberOfRelocations` and `numberOfLineNumbers` are not retained, and the
  builder writes them as zero; the same holds for every undecoded optional
  header field (`sizeOfCode`, `baseOfCode`, `baseOfData`, checksum, DLL
  characteristics, stack/heap sizes, loader flags, version fields). A
  byte-exact rebuild therefore holds for files that are already in the
  builder's canonical form (those fields zero).
- Directory records are raw: no cross-check against `sizeOfImage`, no
  overlap analysis, no known-directory table.
- `sizeOfHeaders` and `sizeOfImage` are carried but never recomputed or
  validated against the layout.
- The documented subset is strict: 1..96 sections, at most 16 directories,
  printable NUL-padded names, nonzero power-of-two alignments and a
  512..65536 `fileAlignment`.
- The whole buffer is in memory; there is no streaming API.
