# xiom.elf -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.elf`, version `0.1.0`).
Module: `src/elf.xi` (`module xiom.elf`).
Depends on `xiom.std`; the library module imports `xiom.string` (for
`str_compare`). The tests add `xiom.test`, `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex` from it. No FFI.

## Scope

A pure-XIOM (no FFI) codec for the ELF header and table layer:

- `elf_parse` validates and reads the 16-byte `e_ident`, the fixed header,
  the program-header table and the section-header table of a 32- or 64-bit,
  little- or big-endian ELF file, and resolves every section name through
  the section-header string table;
- the tables are stored flat: one parallel `Vec[Int]` field per program /
  section header field, plus the decoded names (`Vec[Str]`) and the raw
  `sh_name` indices. Section and segment bytes are never copied; they stay
  in the parse buffer and are located by offset/size fields;
- accessors read the header scalars (class, endianness, type, machine,
  entry, ...), one program-header field by index and `ELF_PH_FIELD_*`
  selector, one section-header field by index and `ELF_SH_FIELD_*`
  selector, one decoded section name by index, and the index of the first
  section with a given name;
- `elf_build_minimal_64le` writes a canonical minimal 64-bit little-endian
  header with no program or section tables;
- deterministic `Err(Str)` messages for malformed input (see the catalog).

## Non-goals

- Symbol tables, relocations, dynamic linking semantics: no `.symtab`,
  `.dynsym`, `.rela.*` interpretation, no PLT/GOT modeling.
- Disassembly or machine-code decoding of section contents.
- Writing complete executables; the only builder emits a header.
- Extended numbering: `e_shnum == 0xFFFF` (real count in `sh_size[0]`) and
  `e_phnum == 0xFFFF` (PN_XNUM) are not resolved; `e_shstrndx == 0xFFFF`
  (SHN_XINDEX) is rejected explicitly.
- Streaming/incremental parsing: the whole file is an in-memory
  `Vec[UInt8]`.
- Semantic validation of section/segment contents: `sh_type`, `sh_flags`,
  `p_type`, `p_flags`, `sh_link`/`sh_info` and `sh_entsize` are stored raw
  and not interpreted.
- OSABI/ABI-version semantics: both ident bytes are pass-through.
- Writing or rewriting program/section tables.

## Byte-level layout

### e_ident (16 bytes)

| Offset | Size | Field | Handling |
|---|---|---|---|
| 0..3 | 4 | magic `0x7F 'E' 'L' 'F'` | validated |
| 4 | 1 | EI_CLASS: 1 = 32-bit, 2 = 64-bit | validated |
| 5 | 1 | EI_DATA: 1 = little-endian, 2 = big-endian | validated |
| 6 | 1 | EI_VERSION: must be 1 (EV_CURRENT) | validated |
| 7 | 1 | EI_OSABI | pass-through (`elf_osabi`) |
| 8 | 1 | EI_ABIVERSION | pass-through |
| 9..15 | 7 | padding | not validated |

### ELF header after e_ident

| Field | Offset (class 1) | Size (class 1) | Offset (class 2) | Size (class 2) |
|---|---|---|---|---|
| e_type | 16 | 2 | 16 | 2 |
| e_machine | 18 | 2 | 18 | 2 |
| e_version | 20 | 4 | 20 | 4 |
| e_entry | 24 | 4 | 24 | 8 |
| e_phoff | 28 | 4 | 32 | 8 |
| e_shoff | 32 | 4 | 40 | 8 |
| e_flags | 36 | 4 | 48 | 4 |
| e_ehsize | 40 | 2 | 52 | 2 |
| e_phentsize | 42 | 2 | 54 | 2 |
| e_phnum | 44 | 2 | 56 | 2 |
| e_shentsize | 46 | 2 | 58 | 2 |
| e_shnum | 48 | 2 | 60 | 2 |
| e_shstrndx | 50 | 2 | 62 | 2 |

Fixed sizes: `ELF_EHDR32_SIZE` = 52, `ELF_EHDR64_SIZE` = 64;
`ELF_PHDR32_SIZE` = 32, `ELF_PHDR64_SIZE` = 56;
`ELF_SHDR32_SIZE` = 40, `ELF_SHDR64_SIZE` = 64.

### Program header

| Field | Offset (class 1) | Size (class 1) | Offset (class 2) | Size (class 2) |
|---|---|---|---|---|
| p_type | 0 | 4 | 0 | 4 |
| p_flags | 24 | 4 | 4 | 4 |
| p_offset | 4 | 4 | 8 | 8 |
| p_vaddr | 8 | 4 | 16 | 8 |
| p_paddr | 12 | 4 | 24 | 8 |
| p_filesz | 16 | 4 | 32 | 8 |
| p_memsz | 20 | 4 | 40 | 8 |
| p_align | 28 | 4 | 48 | 8 |

### Section header

| Field | Offset (class 1) | Size (class 1) | Offset (class 2) | Size (class 2) |
|---|---|---|---|---|
| sh_name | 0 | 4 | 0 | 4 |
| sh_type | 4 | 4 | 4 | 4 |
| sh_flags | 8 | 4 | 8 | 8 |
| sh_addr | 12 | 4 | 16 | 8 |
| sh_offset | 16 | 4 | 24 | 8 |
| sh_size | 20 | 4 | 32 | 8 |
| sh_link | 24 | 4 | 40 | 4 |
| sh_info | 28 | 4 | 44 | 4 |
| sh_addralign | 32 | 4 | 48 | 8 |
| sh_entsize | 36 | 4 | 56 | 8 |

## API signatures

All functions are free functions in module `xiom.elf` (no self methods):

```xi
pub type ElfFile = {
  class: Int; endianness: Int; ident_version: Int; osabi: Int;
  abiversion: Int; e_type: Int; e_machine: Int; e_version: Int;
  e_entry: Int; e_phoff: Int; e_shoff: Int; e_flags: Int;
  e_ehsize: Int; e_phentsize: Int; e_phnum: Int;
  e_shentsize: Int; e_shnum: Int; e_shstrndx: Int;
  seg_types: Vec[Int]; seg_flags: Vec[Int]; seg_offsets: Vec[Int];
  seg_vaddrs: Vec[Int]; seg_paddrs: Vec[Int]; seg_filesz: Vec[Int];
  seg_memsz: Vec[Int]; seg_aligns: Vec[Int];
  sec_name_indices: Vec[Int]; sec_names: Vec[Str]; sec_types: Vec[Int];
  sec_flags: Vec[Int]; sec_addrs: Vec[Int]; sec_offsets: Vec[Int];
  sec_sizes: Vec[Int]; sec_links: Vec[Int]; sec_infos: Vec[Int];
  sec_addraligns: Vec[Int]; sec_entsizes: Vec[Int];
}

pub fn elf_parse(data: &Vec[UInt8]) -> Result[ElfFile, Str]
pub fn elf_class(f: &ElfFile) -> Int
pub fn elf_endianness(f: &ElfFile) -> Int
pub fn elf_osabi(f: &ElfFile) -> Int
pub fn elf_file_type(f: &ElfFile) -> Int
pub fn elf_machine(f: &ElfFile) -> Int
pub fn elf_entry(f: &ElfFile) -> Int
pub fn elf_flags(f: &ElfFile) -> Int
pub fn elf_phoff(f: &ElfFile) -> Int
pub fn elf_shoff(f: &ElfFile) -> Int
pub fn elf_shstrndx(f: &ElfFile) -> Int
pub fn elf_program_count(f: &ElfFile) -> Int
pub fn elf_section_count(f: &ElfFile) -> Int
pub fn elf_program_field(f: &ElfFile, i: Int, field: Int) -> Result[Int, Str]
pub fn elf_section_field(f: &ElfFile, i: Int, field: Int) -> Result[Int, Str]
pub fn elf_section_name(f: &ElfFile, i: Int) -> Result[Str, Str]
pub fn elf_section_index(f: &ElfFile, name: Str) -> Int
pub fn elf_build_minimal_64le(entry: Int) -> Result[Vec[UInt8], Str]
```

Field selectors (documented constants): `ELF_PH_FIELD_TYPE`,
`ELF_PH_FIELD_FLAGS`, `ELF_PH_FIELD_OFFSET`, `ELF_PH_FIELD_VADDR`,
`ELF_PH_FIELD_PADDR`, `ELF_PH_FIELD_FILESZ`, `ELF_PH_FIELD_MEMSZ`,
`ELF_PH_FIELD_ALIGN`; `ELF_SH_FIELD_NAME`, `ELF_SH_FIELD_TYPE`,
`ELF_SH_FIELD_FLAGS`, `ELF_SH_FIELD_ADDR`, `ELF_SH_FIELD_OFFSET`,
`ELF_SH_FIELD_SIZE`, `ELF_SH_FIELD_LINK`, `ELF_SH_FIELD_INFO`,
`ELF_SH_FIELD_ADDRAALIGN`, `ELF_SH_FIELD_ENTSIZE`. Value constants for
common codes are exported too: `ELF_CLASS_32/64`, `ELF_DATA_2LSB/2MSB`,
`ELF_EV_CURRENT`, `ELF_ET_REL/EXEC/DYN/CORE`, `ELF_EM_386/PPC64/X86_64/AARCH64`,
`ELF_PT_NULL/LOAD/DYNAMIC/INTERP/NOTE/PHDR`, `ELF_PF_X/W/R`,
`ELF_SHT_NULL/PROGBITS/STRTAB/NOBITS`, `ELF_SHF_WRITE/ALLOC/EXECINSTR`,
`ELF_SHN_UNDEF`, `ELF_SHN_XINDEX`.

## Semantics

`elf_parse(data)`
: Validates in fixed order and returns a complete `ElfFile` or the first
  error; no partial file is produced. Validation order: ident (length,
  magic, class, data encoding, ident version) -> header (length,
  e_version, e_ehsize) -> program table (entry size, span, per-segment
  file bytes) -> section table (entry size, span, per-section span) ->
  section names (shstrndx, index bounds, NUL termination, printable
  ASCII).

Table presence
: When `e_phnum == 0` there is no program table: `e_phoff` and
  `e_phentsize` are stored but not validated. When `e_shnum == 0` there is
  no section table: `e_shoff` and `e_shentsize` are stored but not
  validated. When a table is present its entry size must equal the class
  entry size exactly (`ELF_PHDR32_SIZE`/`ELF_PHDR64_SIZE`,
  `ELF_SHDR32_SIZE`/`ELF_SHDR64_SIZE`) -- this is the documented "entsize
  consistency" check; `sh_entsize` values inside section headers are
  stored raw and not validated.

64-bit field decoding
: Every 8-byte field (`e_entry`, `e_phoff`, `e_shoff`, `p_offset`,
  `p_vaddr`, `p_paddr`, `p_filesz`, `p_memsz`, `p_align`, `sh_flags`,
  `sh_addr`, `sh_offset`, `sh_size`, `sh_addralign`, `sh_entsize`) is
  returned as the raw two's-complement Int of its 64-bit pattern (the
  xiom.pack u64 convention): a value with bit 63 set decodes as a negative
  Int. Offsets/sizes that decode negative are rejected as out of bounds;
  addresses (`e_entry`, `p_vaddr`, `p_paddr`, `sh_addr`) are passed
  through unvalidated.

Segment span
: For every program header with `p_filesz > 0`, `p_offset >= 0` and
  `[p_offset, p_offset + p_filesz)` must lie inside the buffer. A segment
  with `p_filesz == 0` carries no file bytes, so its `p_offset` is not
  validated.

Section span
: For every section header except `SHT_NOBITS`, `sh_offset >= 0` and
  `[sh_offset, sh_offset + sh_size)` must lie inside the buffer.
  `SHT_NOBITS` occupies no file bytes, so its span is not checked, but
  `sh_offset` and `sh_size` must still decode non-negative.

Section names
: `e_shstrndx == SHN_UNDEF (0)` means there is no name table; every
  `sh_name` must then be 0 and every decoded name is `""`. Otherwise
  `e_shstrndx` must be a valid section index and that section must be
  `SHT_STRTAB`. For each section, `sh_name` must be a non-negative byte
  offset strictly inside the table's `sh_size`; the bytes from there to
  the first NUL must all be printable ASCII (`0x20..0x7E`) and the NUL must
  occur before the end of the table. `e_shstrndx == SHN_XINDEX (0xFFFF)`
  is rejected. Names are decoded into fresh `Str` values; the raw indices
  remain available via `ELF_SH_FIELD_NAME`.

`elf_program_field(f, i, field)` / `elf_section_field(f, i, field)`
: Return the raw parsed value; `Err("elf: index out of range")` for a bad
  `i`, `Err("elf: bad field selector")` for an unknown selector. No range,
  alignment or semantic validation is applied to the field.

`elf_section_name(f, i)`
: Returns the decoded name; `Err("elf: index out of range")` for a bad
  `i`. The value is a `Str` read from a `Vec[Str]`: compare it with
  `xiom.string.compare.str_compare` rather than `==` (BUG 17).

`elf_section_index(f, name)`
: Linear scan; returns the first matching index or `-1` (including on an
  empty section table). Comparison is exact and case-sensitive.

`elf_build_minimal_64le(entry)`
: Emits exactly 64 bytes: `e_ident` class 2 / data 1 / version 1 with zero
  OSABI, ABI version and padding; `e_type` `ELF_ET_EXEC` (2); `e_machine`
  `ELF_EM_X86_64` (62); `e_version` 1; `entry`; zero `e_phoff`/`e_shoff`;
  zero `e_flags`; `e_ehsize` 64, `e_phentsize` 56, `e_phnum` 0,
  `e_shentsize` 64, `e_shnum` 0, `e_shstrndx` 0. The output therefore
  declares no program and no section tables and parses back cleanly.
  `Err("elf: negative entry")` when `entry < 0`.

## Error string catalog

| Condition | Error text |
|---|---|
| buffer shorter than 16 bytes | `elf: truncated ident` |
| any of the four magic bytes wrong | `elf: bad magic` |
| `EI_CLASS` not 1 or 2 | `elf: bad class` |
| `EI_DATA` not 1 or 2 | `elf: bad data encoding` |
| `EI_VERSION` not 1 | `elf: bad ident version` |
| buffer shorter than the class header size | `elf: truncated header` |
| `e_version` not 1 | `elf: bad e_version` |
| `e_ehsize` not 52 (class 1) / 64 (class 2) | `elf: bad e_ehsize` |
| `e_phnum > 0` and `e_phentsize` wrong | `elf: bad e_phentsize` |
| program table span outside the buffer (incl. negative `e_phoff`) | `elf: program headers out of bounds` |
| `p_filesz < 0`, or `p_filesz > 0` and its file span outside the buffer | `elf: segment data out of bounds` |
| `e_shnum > 0` and `e_shentsize` wrong | `elf: bad e_shentsize` |
| section table span outside the buffer (incl. negative `e_shoff`) | `elf: section headers out of bounds` |
| `sh_offset < 0`, `sh_size < 0`, or a non-`SHT_NOBITS` span outside the buffer | `elf: section data out of bounds` |
| `e_shstrndx == SHN_XINDEX (0xFFFF)` | `elf: extended section index unsupported (SHN_XINDEX)` |
| `e_shnum == 0` and `e_shstrndx != 0`, or `e_shstrndx >= e_shnum` | `elf: shstrndx out of range` |
| `e_shstrndx > 0` but that section is not `SHT_STRTAB` | `elf: shstrndx is not a string table` |
| `e_shstrndx == SHN_UNDEF` but some `sh_name != 0` | `elf: no section name string table` |
| `sh_name` negative or `>= shstrtab sh_size` | `elf: section name index out of bounds` |
| no NUL before the end of the string table | `elf: section name not NUL-terminated` |
| a name byte outside `0x20..0x7E` | `elf: section name not printable ASCII` |
| builder `entry < 0` | `elf: negative entry` |
| accessor index negative or past the count | `elf: index out of range` |
| accessor field not an `ELF_PH_FIELD_*` / `ELF_SH_FIELD_*` constant | `elf: bad field selector` |

Checks short-circuit in the validation order above, so an earlier failure
masks later ones (for example a bad magic always reports `elf: bad magic`
even when the buffer is also truncated below the header).

## Complexity

| Operation | Complexity |
|---|---|
| `elf_parse` | O(data.len() + table entries + total name bytes) |
| header/count/table-field accessors | O(1) |
| `elf_section_name` | O(name length) |
| `elf_section_index` | O(sections * name length) |
| `elf_build_minimal_64le` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module elf_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Fixtures are assembled byte by byte in the
test file, independent of `src/elf.xi`. Coverage:

1. pinned 64-byte minimal builder output (verified hex) and a parse-back
   of exactly 64 bytes with class 2 / data 1 / ET_EXEC / EM_X86_64 /
   `entry`, zero tables; `entry < 0` is the documented builder error;
2. hand-built 64-bit LE fixture header fields (osabi, type, machine,
   entry, `e_phoff`, `e_shoff`, counts, `shstrndx`);
3. all eight program-header selectors of the fixture, plus bad index and
   bad selector errors;
4. all ten section-header selectors of the `.text` and `.shstrtab`
   headers, plus bad index and bad selector errors;
5. names resolve to `""`, `".text"`, `".shstrtab"`; name accessor bounds;
6. `elf_section_index` is exact and case-sensitive; `""` maps to the NULL
   section; missing names are `-1`;
7. 32-bit LE fixture: 32-bit program/section layouts parse, class 1,
   EM_386, 32-bit field values;
8. 64-bit BE fixture: big-endian header and program fields decode in the
   right byte order;
9. each of the four magic bytes wrong is `elf: bad magic`;
10. empty/10-byte buffers are `elf: truncated ident`; 16/63-byte buffers
    are `elf: truncated header`; a header-only 64-byte prefix fails on the
    declared but absent program table;
11. class 0/3, data 0/3 and ident version 2 are the documented errors;
12. bad `e_version`, `e_ehsize`, `e_phentsize` and `e_shentsize` are the
    documented errors;
13. table spans outside the buffer (and raw negative `e_phoff`/`e_shoff`)
    are `elf: program headers out of bounds` /
    `elf: section headers out of bounds`;
14. segment file bytes outside the buffer and negative `p_filesz` are Err;
    a zero-filesz segment with an out-of-range `p_offset` parses and keeps
    the offset raw;
15. section spans outside the buffer and negative `sh_offset` are Err; a
    `SHT_NOBITS` section with a 1000-byte `sh_size` and an in-buffer offset
    parses, and the same section with `sh_offset < 0` is Err;
16. `shstrndx` past `e_shnum`, `SHN_XINDEX`, a non-STRTAB target and
    `SHN_UNDEF` with a nonzero `sh_name` are the documented errors;
    `SHN_UNDEF` with all-zero names parses with empty names;
17. name index out of bounds, missing NUL terminator (short `sh_size`) and
    non-printable name bytes (0x01 and 0x7F) are the documented errors;
18. 64-bit high-bit fields decode raw: `e_entry` `-1` stays `-1`,
    `0x7FFFFFFFFFFFFFFF` round-trips, a raw bit-63 `e_phoff` is out of
    bounds and a negative `p_vaddr` is preserved.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.elf
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **Header/table layer only.** Symbol tables, relocations, dynamic-linking
  metadata and section contents are not interpreted.
- **No extended numbering.** `e_shnum == 0xFFFF` and `e_phnum == 0xFFFF`
  are taken literally, so a file using extended numbering fails the table
  span check; `e_shstrndx == 0xFFFF` is rejected with a dedicated error.
- **Strict table entry sizes.** A file whose `e_phentsize`/`e_shentsize`
  differs from the class entry size is rejected even though the ELF spec
  allows larger entries (`e_phnum > 0` / `e_shnum > 0`).
- **No section-byte accessor.** `ElfFile` stores offsets/sizes; callers
  slice the parse buffer themselves.
- **64-bit values are Int-limited.** Raw bit patterns are preserved two's
  complement, but there is no unsigned 64-bit type; values above `2^63-1`
  appear negative.
- **`SHT_NOBITS` span is unchecked.** Its `sh_offset` only has to decode
  non-negative.
- **OSABI/ABI version and ident padding are not validated**; `e_flags` is
  machine-specific pass-through.
- **Names are ASCII-only.** A section name with any byte outside
  `0x20..0x7E` (including UTF-8) is rejected.
- Duplicate section names are allowed; `elf_section_index` returns the
  first match.
- Not thread-safe; `ElfFile` is a plain value type.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_file`/`_err_file`/`_ok_int`/`_err_int`/`_ok_str`/`_err_str`/
  `_ok_bytes`/`_err_bytes`/`_ok_unit`/`_err_unit` (constructing Results
  directly in other functions miscompiles in this compiler).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic; `Vec[Int]` and `Vec[Str]` element reads are
  bound to typed locals.
- 64-bit decoding uses the xiom.pack shape (low seven bytes accumulate
  with a `place` factor, the top byte is applied separately) because
  `& 0xFF`/shifts on operands with bit 31 set miscompile in v0.61.3.
- Builder byte packing is arithmetic (`_low_byte` with negative-remainder
  correction), never `<<`.
- `Str` comparisons in tests and in `elf_section_index` go through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison).
- The package declares no `extern "C"` blocks (no FFI).
