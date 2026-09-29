# xiom.apple

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM Apple executable/container STRUCTURE parser for thin
> Mach-O images (32/64-bit, little- and big-endian) and fat/universal
> archives (32-bit arch records). No code, symbols, relocations or dyld
> semantics.
> **Deps:** `xiom.std` only. The library module imports `xiom.convert.itos`;
> the tests use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare` from it. No FFI.

## What it is

`xiom.apple` parses the structural layer of Apple containers:

- **Thin Mach-O**: the four magics (`0xFEEDFACE` / `0xFEEDFACF` and the
  byte-swapped `0xCEFAEDFE` / `0xCFFAEDFE`), the `mach_header` and
  `mach_header_64` fields, and the load-command walk: `LC_SEGMENT` /
  `LC_SEGMENT_64` with their section records, the dylib family
  (`LC_LOAD_DYLIB`, `LC_ID_DYLIB`, `LC_LOAD_WEAK_DYLIB`,
  `LC_REEXPORT_DYLIB`, `LC_LOAD_UPWARD_DYLIB`, `LC_LAZY_LOAD_DYLIB`: name
  offset + timestamp + current/compatibility version), `LC_UUID` (16 raw
  bytes), `LC_MAIN` (entryoff, stacksize), `LC_CODE_SIGNATURE` and the
  linkedit-data family (dataoff, datasize), `LC_BUILD_VERSION` (platform,
  minos, sdk, ntools), `LC_VERSION_MIN_*` (version, sdk), `LC_SYMTAB`
  (table locations only), `LC_SOURCE_VERSION`, `LC_ENCRYPTION_INFO(_64)`,
  and the plain `lc_str` commands (`LC_LOAD_DYLINKER`, `LC_ID_DYLINKER`,
  `LC_DYLD_ENVIRONMENT`, `LC_RPATH`, `LC_SUB_*`). Recognized-but-undecoded
  and unknown commands are preserved with their raw `cmd`, `cmdsize` and
  file offset.
- **Fat/universal**: the `fat_header` and its `fat_arch` records
  (`nfat_arch`, cputype, cpusubtype, offset, size, align) in both the
  big-endian `FAT_MAGIC` and little-endian `FAT_CIGAM` forms, with slice
  bounds, power-of-two alignment and overlap validation, a cputype slice
  selector and slice copy/parse helpers.

Tables are stored flat in parallel vectors (one vector per field, one slot
per command/segment/section/arch). Bytes stay in the source buffer at the
offsets the headers declare. Every error is an `"apple: ..."` string that
carries the offending byte offset.

## API

| Function | Returns | Description |
|---|---|---|
| `apple_format(data)` | `Int` | `APPLE_FORMAT_*` of the first four bytes. |
| `apple_format_bits(fmt)` | `Int` | 32 / 64 for thin, 0 otherwise. |
| `apple_format_endianness(fmt)` | `Int` | `APPLE_ENDIAN_LE/_BE`; 0 for unknown. |
| `apple_is_fat_format(fmt)` / `apple_is_thin_format(fmt)` | `Bool` | Format-class tests. |
| `apple_format_name(fmt)` | `Str` | `"macho64-le"`, `"fat-be"`, ... |
| `macho_parse(data)` | `Result[MachOFile, Str]` | Validate and index a thin Mach-O. |
| `macho_magic/bits/endianness/cputype/cpusubtype/filetype/flags/ncmds/sizeofcmds/reserved/header_size(f)` | `Int` | Header scalars. |
| `macho_command_count/segment_count/section_count(f)` | `Int` | Flat table sizes. |
| `macho_cpu_class(cputype)` | `Int` | `APPLE_CPU_CLASS_*` classification. |
| `macho_cpu_name(cputype)` | `Str` | `"x86_64"`, `"arm64"`, ... |
| `macho_file_type_name(filetype)` | `Str` | `"object"`, `"executable"`, `"dylib"`, ... |
| `macho_has_flag(f, mask)` | `Bool` | Single-bit `APPLE_MH_*` test. |
| `macho_prot_bits(prot)` / `macho_prot_text(prot)` | `Int` / `Str` | maxprot/initprot decode (`5` -> `"r-x"`). |
| `macho_version_text(v)` | `Str` | Packed `x.y.z` -> `"13.1.0"`. |
| `macho_platform_name(p)` | `Str` | `"macos"`, `"ios"`, ... |
| `macho_command_field(f, i, field)` | `Result[Int, Str]` | One `APPLE_LC_FIELD_*` of command `i`. |
| `macho_command_name(f, i)` | `Result[Str, Str]` | Decoded dylib/lc_str name (`""` otherwise). |
| `macho_uuid_byte(f, i, k)` / `macho_uuid_text(f, i)` | `Result[Int/Str, Str]` | LC_UUID bytes / canonical text. |
| `macho_segment_field(f, j, field)` / `macho_segment_name(f, j)` | `Result[Int/Str, Str]` | Segment record. |
| `macho_section_field(f, k, field)` / `macho_section_name(f, k)` / `macho_section_segment_name(f, k)` | `Result[Int/Str, Str]` | Section record. |
| `fat_parse(data)` | `Result[FatFile, Str]` | Validate and index a fat archive. |
| `fat_magic/endianness/arch_count(f)` | `Int` | Fat header scalars. |
| `fat_arch_field(f, i, field)` | `Result[Int, Str]` | One `APPLE_FAT_FIELD_*` of arch `i`. |
| `fat_select(f, cputype)` / `fat_select_subtype(f, cputype, sub)` | `Int` | First matching arch or `-1`. |
| `fat_slice_bytes(data, f, i)` | `Result[Vec[UInt8], Str]` | Copy slice `i` out. |
| `fat_slice_macho(data, f, i)` | `Result[MachOFile, Str]` | Copy and parse slice `i`. |
| `apple_version()` | `Str` | `"0.1.0"`. |

Field selectors: `APPLE_LC_FIELD_CMD`, `_SIZE`, `_OFFSET`, `_KIND`,
`_VAL1`..`_VAL4`, `_NAME_OFFSET`, `_UUID_START`, `_UUID_LEN`;
`APPLE_SEG_FIELD_CMD_INDEX`, `_VMADDR`, `_VMSIZE`, `_FILEOFF`,
`_FILESIZE`, `_MAXPROT`, `_INITPROT`, `_NSECTS`, `_FLAGS`;
`APPLE_SEC_FIELD_SEG_INDEX`, `_ADDR`, `_SIZE`, `_OFFSET`, `_ALIGN`,
`_FLAGS`; `APPLE_FAT_FIELD_CPUTYPE`, `_CPUSUBTYPE`, `_OFFSET`, `_SIZE`,
`_ALIGN`.

The meaning of val1..val4 depends on the decoded command kind
(`APPLE_LCK_*`): segment (vmaddr, vmsize, fileoff, filesize), dylib (name
offset, timestamp, current, compatibility), main (entryoff, stacksize),
linkedit data (dataoff, datasize), build version (platform, minos, sdk,
ntools), version min (version, sdk), symtab (symoff, nsyms, stroff,
strsize), source version (version), encryption info (cryptoff,
cryptsize, cryptid), lc_str (name offset).

Errors: every message is `"apple: <what> at <byte offset>"` --
`truncated magic`, `bad magic`, `fat header where a thin Mach-O was
expected`, `truncated header`, `sizeofcmds out of bounds`, `truncated
load command`, `bad cmdsize`, `misaligned cmdsize`, `command exceeds
sizeofcmds`, `load commands do not fill sizeofcmds`, `bad segment
command`, `segment sections exceed cmdsize`, `segment data out of
bounds`, `bad section alignment`, `section data out of bounds`, `name not
printable ASCII`, `bad dylib command`, `bad lc_str command`, `bad name
offset`, `name not NUL-terminated`, `bad LC_UUID size`, `bad LC_MAIN
size`, `bad linkedit command size`, `linkedit data out of bounds`, `bad
LC_BUILD_VERSION size`, `build version tools exceed cmdsize`, `bad
LC_VERSION_MIN size`, `bad LC_SYMTAB size`, `bad LC_SOURCE_VERSION
size`, `bad LC_ENCRYPTION_INFO size`, `truncated fat header`, `bad fat
arch count`, `fat arch table out of bounds`, `fat slice out of bounds`,
`fat slice overlaps the arch table`, `misaligned fat slice`, `bad fat
arch alignment`, `fat slices overlap`, `not a fat archive`, `fat64
header unsupported`, `index out of range`, `bad field selector`, `no
uuid on this command` (the last three carry no offset). See SPEC.md for
the exact conditions.

## Usage

```xi
use xiom.apple;
use xiom.io;
use xiom.convert.itos;

// `data` is a Vec[UInt8] holding the whole file.
let fmt = apple_format(&data);
io.println("format: " + apple_format_name(fmt));

if apple_is_fat_format(fmt) {
  let rf = fat_parse(&data);
  if rf.is_ok {
    let fat: FatFile = rf.value;
    let idx = fat_select(&fat, APPLE_CPU_TYPE_ARM64);
    if idx >= 0 {
      let rm = fat_slice_macho(&data, &fat, idx);
      if rm.is_ok {
        let slice: MachOFile = rm.value;
        io.println("arm64 slice commands: " + itos.itos(macho_command_count(&slice)));
      }
    }
  }
} else if apple_is_thin_format(fmt) {
  let rm = macho_parse(&data);
  if rm.is_ok {
    let m: MachOFile = rm.value;
    io.println("filetype: " + macho_file_type_name(macho_filetype(&m)));
    io.println("bits: " + itos.itos(macho_bits(&m)));
    // Find LC_MAIN and print its entry offset.
    var i = 0;
    while i < macho_command_count(&m) {
      let k = macho_command_field(&m, i, APPLE_LC_FIELD_KIND);
      if k.is_ok {
        if k.value == APPLE_LCK_MAIN {
          let e = macho_command_field(&m, i, APPLE_LC_FIELD_VAL1);
          if e.is_ok {
            io.println("entryoff: " + itos.itos(e.value));
          }
        }
      }
      i = i + 1;
    }
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.apple
```

Expected: the section-4 namespace check passes, 21 `[PASS]` lines, and a
final `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Structure only.** `LC_SYMTAB` records the table locations; nlist
  entries, relocations, dyld bind/export/lazy info, Objective-C metadata
  and code-signature contents are never decoded or verified.
- **fat64 rejected.** `FAT_MAGIC_64` / `FAT_CIGAM_64` archives (8-byte
  offset/size records) are detected and rejected explicitly.
- **Strict load-command walk.** Each `cmdsize` must be >= 8, a multiple
  of 4 in a 32-bit image and of 8 in a 64-bit image, stay inside
  `sizeofcmds`, and the commands must fill `sizeofcmds` exactly.
- **Names are printable ASCII.** Segment/section names (NUL-padded) and
  dylib/lc_str names (NUL-terminated inside the command) must use bytes
  `0x20..0x7E`.
- **Section align bound 0..31**; segment `filesize > 0` and non-zerofill
  section spans (`S_ZEROFILL`, `S_GB_ZEROFILL`,
  `S_THREAD_LOCAL_ZEROFILL` exempt) must lie inside the buffer.
- **64-bit fields are raw two's complement.** A value with bit 63 set
  decodes as a negative `Int` (there is no unsigned 64-bit type).
- **Fat validation is structural.** Slices must be in bounds, clear of
  the arch table, aligned to `2^align` (`align` in 0..32; 12 = 4 KB and
  14 = 16 KB are the conventional page alignments) and pairwise
  non-overlapping; slice payloads are not required to be Mach-O.
- Raw `cputype`, `cpusubtype`, `filetype` and `flags` values are
  pass-through.
- `MachOFile`/`FatFile` names are read from `Vec[Str]` fields: compare
  them with `xiom.string.compare.str_compare`, not `==` (BUG 17
  discipline).
- Not thread-safe; `MachOFile` and `FatFile` are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
