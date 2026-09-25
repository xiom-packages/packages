# xiom.pe

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (18/18); NOT published yet.
> **Scope:** PE/COFF header codec for a documented subset: `"MZ"` DOS header and stub, `"PE\0\0"` signature, the 20-byte COFF file header, the PE32 (0x10B) / PE32+ (0x20B) optional header, up to 16 raw data directory records, the section table, and a canonical builder. No imports, exports, relocations, resources, .NET metadata or Authenticode.
> **Deps:** `xiom.std` only (the library module imports `xiom.string` and `xiom.string.compare`). No FFI in v0.1.

## What it is

`xiom.pe` reads and writes the structural header layer of a Windows Portable
Executable image: the DOS header with its stub span, the PE signature, the
COFF file header, the optional header (PE32 and PE32+), the data directory
array and the section table. It is a pure-XIOM byte codec -- no payload
byte is decoded and no directory is interpreted -- which makes it the right
front end for validators, signature/section inspectors, packers, asset
pipelines and downstream parsers.

Storage is flat: one `PeImage` holds the sections and the data directories
as parallel `Vec`s (no `Vec[StructType]`), and a hand-built `PeImage` is
also the builder's spec.

| Layer | What is decoded |
|---|---|
| DOS header | `"MZ"`, e_lfanew at 0x3C, the opaque stub span (`pe_stub` copies it) |
| COFF header | machine, numberOfSections (1..96), timeDateStamp, symbol table pointer/count, sizeOfOptionalHeader, characteristics |
| Optional header | magic 0x10B/0x20B, addressOfEntryPoint, imageBase (u32/u64), sectionAlignment, fileAlignment, sizeOfImage, sizeOfHeaders, subsystem, numberOfRvaAndSizes (0..16) |
| Data directories | every record as raw `(virtualAddress, size)`; nothing is interpreted |
| Sections | 8-byte printable name, virtualSize/Address, raw size/pointer, reloc/line pointers, characteristics |

Everything else (linker/OS/image versions, `sizeOfCode`, checksum, DLL
characteristics, stack/heap sizes, loader flags, `numberOfRelocations` /
`numberOfLineNumbers`) is not retained; the builder emits those fields as
zero, so a rebuild is byte-exact for files already in that canonical form.

## API

| Function | Returns | Description |
|---|---|---|
| `pe_parse(data)` | `Result[PeImage, Str]` | Validate the header layer and decode every documented field. |
| `pe_is_valid(data)` | `Bool` | True when `pe_parse` succeeds. |
| `pe_stub(data)` | `Result[Vec[UInt8], Str]` | Copy the DOS stub span `64..e_lfanew`. |
| `pe_build_headers(img, stub)` | `Result[Vec[UInt8], Str]` | Emit the whole header block (DOS header + stub + COFF + optional + directories + section table). |
| `pe_build(img, stub, raw)` | `Result[Vec[UInt8], Str]` | Emit a whole file: header block plus every section's raw bytes at `pointerToRawData`, zero-filled elsewhere; re-parsed before returning. |
| `pe_machine(img)` / `pe_machine_name(machine)` | `Int` / `Str` | Machine code and its name (`i386`, `arm`, `ia64`, `amd64`, `arm64`, `unknown`). |
| `pe_section_count(img)` | `Int` | Number of sections. |
| `pe_section_name(img, i)` | `Str` | Section name (`""` out of range; compare with `str_compare`). |
| `pe_section_virtual_size(img, i)` / `pe_section_virtual_address(img, i)` | `Int` | Virtual span (RVA); -1 out of range. |
| `pe_section_raw_size(img, i)` / `pe_section_raw_pointer(img, i)` | `Int` | On-disk span; -1 out of range. |
| `pe_section_reloc_pointer(img, i)` / `pe_section_line_pointer(img, i)` | `Int` | The two auxiliary pointers; -1 out of range. |
| `pe_section_characteristics(img, i)` | `Int` | Section flags; -1 out of range. |
| `pe_find_section(img, name)` | `Int` | Exact-case lookup by `str_compare`; -1 when absent. |
| `pe_entry_point(img)` / `pe_image_base(img)` / `pe_subsystem(img)` | `Int` | AddressOfEntryPoint, ImageBase (bit 63 clear) and Subsystem. |
| `pe_directory_count(img)` | `Int` | NumberOfRvaAndSizes (0..16). |
| `pe_directory_virtual_address(img, i)` / `pe_directory_size(img, i)` | `Int` | Raw directory record; -1 out of range. |
| `pe_pe_offset(img)` / `pe_stub_size(img)` / `pe_optional_offset(img)` / `pe_optional_magic(img)` / `pe_file_size(img)` | `Int` | Structural facts. |
| `pe_size_of_image(img)` / `pe_size_of_headers(img)` | `Int` | Optional-header sizes. |
| `pe_section_alignment(img)` / `pe_file_alignment(img)` | `Int` | Alignments. |
| `pe_characteristics(img)` / `pe_time_date_stamp(img)` | `Int` | COFF fields. |

Public constants cover the structural sizes, both magic values, the caps
(96 sections, 16 directories, fileAlignment 512..65536), the `PE_MACHINE_*`
codes, the `PE_FILE_*` / `PE_SCN_*` flag bits and the two subsystem values.

## Install / use

```
xiom pkg install xiom.pe@0.1.0     # consumer
```

Then import the module from any XIOM source file with `use xiom.pe;`. The
library pulls in nothing but `xiom.std` as a platform dependency.

## Quick start

```xiom
use xiom.pe;

// Inspect a PE file (bytes from disk, network, ...).
let parsed = pe_parse(bytes);
if parsed.is_ok {
  let img: PeImage = parsed.value;
  // pe_machine_name(pe_machine(&img)) is "amd64" for a typical x64 image
  // pe_entry_point(&img), pe_image_base(&img), pe_subsystem(&img)
  // pe_directory_count(&img) and pe_directory_virtual_address(&img, 1) are
  // raw records; nothing is imported above this layer.
  let n = pe_section_count(&img);
  var i = 0;
  while i < n {
    let nm: Str = pe_section_name(&img, i);
    // inspect the section: pe_section_virtual_address(&img, i),
    // pe_section_raw_pointer(&img, i), pe_section_raw_size(&img, i), ...
    i = i + 1;
  }

  // Rebuild a file byte for byte from the parsed image: the DOS stub, then
  // the sections' raw bytes concatenated in table order.
  let stubr = pe_stub(bytes);                  // Result[Vec[UInt8], Str]
  if stubr.is_ok {
    let stub: Vec[UInt8] = stubr.value;
    let raw = /* collect_raw(&img, bytes) from the fixture pattern in tests */;
    let out = pe_build(&img, &stub, &raw);     // Result[Vec[UInt8], Str]
  }
} else {
  // parsed.error is a deterministic "pe: ..." message, see SPEC.md
}
```

## Error model

Every fallible function returns `Result[..., Str]` with deterministic
`pe: `-prefixed messages. Truncation, bad DOS/PE magics, out-of-range
e_lfanew, a bad section count, optional-header size/magic mismatches, an
out-of-range PE32+ image base, non-power-of-two alignments, a bad
`fileAlignment` window, too many directories, directory/table/section-table
overruns, slash-comment or non-printable section names and out-of-bounds
raw spans each have their own message; the builders add field range errors,
Vec-drift cross-checks (`pe: section table length mismatch`, `pe: directory
count mismatch`), raw-data and span checks. The full catalog and the
validation order are in SPEC.md.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.pe
```

18 conformance checks cover a canonical PE32+ fixture (two sections, a
64-byte DOS stub, 16 directories) and a canonical PE32 fixture (one
section, no stub): every decoded field and accessor, byte-for-byte
`pe_build_headers` and `pe_build` round-trips, directory and section
lookups, high-bit u32 fields, and the full error catalog.

## Limitations

- Header layer only: no imports/exports/relocations, resources, .NET
  metadata, Authenticode or payload decoding; no RVA-to-offset translation.
- Undecoded fields are not retained and are written as zero by the builder,
  so byte-exact rebuilds hold for files already in that canonical form.
- Directory records are raw: no known-directory table and no cross-check
  against `sizeOfImage`.
- Raw spans must not overlap the header block, but section spans are not
  required to be disjoint from each other.
- The documented subset is strict: 1..96 sections, <= 16 directories,
  1..8 printable NUL-padded names, nonzero power-of-two alignments and
  `fileAlignment` in 512..65536.
- The whole buffer is in memory; there is no streaming API.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
