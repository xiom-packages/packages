# xiom.elf

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM ELF header and program/section table codec for
> 32/64-bit, little- and big-endian files, including section-name
> resolution through the section-header string table.
> **Deps:** `xiom.std` only. The library module imports `xiom.string`; the
> tests use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI.

## What it is

`xiom.elf` parses the structural layer of an ELF file: the 16-byte
`e_ident`, the fixed header, the program-header table and the
section-header table. Tables are stored flat in parallel vectors (one
vector per field, plus decoded section names), and section/segment bytes
stay in the source buffer at the offsets the headers declare.

`elf_parse` validates the magic, class and data codes, the ident and
header versions, the fixed header/entry sizes, every table span, every
segment's file bytes, every non-`SHT_NOBITS` section span, `e_shstrndx` and
every section name (index bounds, NUL termination, printable ASCII).
`elf_build_minimal_64le` emits a canonical 64-bit little-endian header
with no tables. No symbol tables, relocations, dynamic-linking semantics
or disassembly.

## API

| Function | Returns | Description |
|---|---|---|
| `elf_parse(data)` | `Result[ElfFile, Str]` | Validate and index the header and both tables. |
| `elf_class(f)` | `Int` | `EI_CLASS`: 1 (32-bit) or 2 (64-bit). |
| `elf_endianness(f)` | `Int` | `EI_DATA`: 1 (LE) or 2 (BE). |
| `elf_osabi(f)` | `Int` | `EI_OSABI` pass-through. |
| `elf_file_type(f)` | `Int` | `e_type` (`ET_*`). |
| `elf_machine(f)` | `Int` | `e_machine` (`EM_*`). |
| `elf_entry(f)` | `Int` | `e_entry` (raw field). |
| `elf_flags(f)` / `elf_phoff(f)` / `elf_shoff(f)` | `Int` | Header scalars. |
| `elf_shstrndx(f)` | `Int` | Section-name string table index. |
| `elf_program_count(f)` | `Int` | Number of program headers. |
| `elf_section_count(f)` | `Int` | Number of section headers. |
| `elf_program_field(f, i, field)` | `Result[Int, Str]` | One program-header field (`ELF_PH_FIELD_*`). |
| `elf_section_field(f, i, field)` | `Result[Int, Str]` | One section-header field (`ELF_SH_FIELD_*`). |
| `elf_section_name(f, i)` | `Result[Str, Str]` | Decoded name of section `i`. |
| `elf_section_index(f, name)` | `Int` | First section with that name; `-1` when absent. |
| `elf_build_minimal_64le(entry)` | `Result[Vec[UInt8], Str]` | Canonical 64-byte 64-bit LE header, no tables. |

Errors: `elf: truncated ident`, `elf: bad magic`, `elf: bad class`,
`elf: bad data encoding`, `elf: bad ident version`, `elf: truncated
header`, `elf: bad e_version`, `elf: bad e_ehsize`,
`elf: bad e_phentsize`, `elf: program headers out of bounds`,
`elf: segment data out of bounds`, `elf: bad e_shentsize`,
`elf: section headers out of bounds`, `elf: section data out of bounds`,
`elf: extended section index unsupported (SHN_XINDEX)`,
`elf: shstrndx out of range`, `elf: shstrndx is not a string table`,
`elf: no section name string table`,
`elf: section name index out of bounds`, `elf: section name not
NUL-terminated`, `elf: section name not printable ASCII`,
`elf: negative entry`, `elf: index out of range`,
`elf: bad field selector` (see SPEC.md for the exact conditions and
validation order).

## Usage

```xi
use xiom.elf;
use xiom.io;

// Build a minimal 64-bit LE header (64 bytes, no tables).
let built = elf_build_minimal_64le(0x401000);
if built.is_ok {
  let bytes: Vec[UInt8] = built.value;

  // Parse it back.
  let parsed = elf_parse(&bytes);
  if parsed.is_ok {
    let f: ElfFile = parsed.value;
    io.println("class: " + xiom.convert.int_to_string(elf_class(&f))); // 2
    io.println("entry: " + xiom.convert.int_to_string(elf_entry(&f))); // 4198400
    io.println("programs: " + xiom.convert.int_to_string(elf_program_count(&f))); // 0
  }
}

// Read one field of a parsed file: p_type of program header 0.
let t = elf_program_field(&f, 0, ELF_PH_FIELD_TYPE);
if t.is_ok {
  io.println("p_type: " + xiom.convert.int_to_string(t.value));
}
```

Field selectors: `ELF_PH_FIELD_TYPE`, `ELF_PH_FIELD_FLAGS`,
`ELF_PH_FIELD_OFFSET`, `ELF_PH_FIELD_VADDR`, `ELF_PH_FIELD_PADDR`,
`ELF_PH_FIELD_FILESZ`, `ELF_PH_FIELD_MEMSZ`, `ELF_PH_FIELD_ALIGN`;
`ELF_SH_FIELD_NAME`, `ELF_SH_FIELD_TYPE`, `ELF_SH_FIELD_FLAGS`,
`ELF_SH_FIELD_ADDR`, `ELF_SH_FIELD_OFFSET`, `ELF_SH_FIELD_SIZE`,
`ELF_SH_FIELD_LINK`, `ELF_SH_FIELD_INFO`, `ELF_SH_FIELD_ADDRAALIGN`,
`ELF_SH_FIELD_ENTSIZE`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.elf
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Header/table layer only.** No symbol tables, relocations,
  dynamic-linking semantics, disassembly or section-content decoding.
- **No extended numbering.** `e_shnum == 0xFFFF`, `e_phnum == 0xFFFF` and
  `e_shstrndx == SHN_XINDEX` are not resolved (the last is rejected
  explicitly).
- **Strict entry sizes.** With a non-empty table, `e_phentsize` /
  `e_shentsize` must equal the exact 32/64-bit entry size.
- **64-bit fields are raw two's complement.** A value with bit 63 set
  decodes as a negative `Int` (there is no unsigned 64-bit type).
- **`SHT_NOBITS` spans are unchecked** (no file bytes); `sh_offset` and
  `sh_size` only have to decode non-negative.
- **ASCII section names.** Any name byte outside `0x20..0x7E` is rejected.
- **No section-byte accessor.** `ElfFile` carries offsets/sizes; callers
  slice the parse buffer.
- `ElfFile` values are read from `Vec[Str]` fields for names: compare with
  `xiom.string.compare.str_compare`, not `==` (BUG 17 discipline).
- Not thread-safe; `ElfFile` is a plain value type.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
