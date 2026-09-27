# xiom.apple SPEC

## Scope

Pure-XIOM structure parser for Apple Mach-O containers, exactly as
implemented in `src/apple.xi`:

- thin Mach-O: magic/class/byte-order detection, `mach_header` (28 bytes)
  and `mach_header_64` (32 bytes), and the load-command walk with the
  decoded payloads listed below;
- fat/universal archives: `fat_header` + 20-byte `fat_arch` records in the
  big-endian `FAT_MAGIC` and little-endian `FAT_CIGAM` forms, slice
  selection and slice copy/parse helpers.

Storage is flat: `MachOFile` holds the load commands, segments and
sections as parallel `Vec`s (one slot per entry); `FatFile` holds the arch
records the same way. Never `Vec[StructType]`. Raw bytes stay in the parse
buffer.

## Non-goals

Instruction, symbol (the `LC_SYMTAB` table locations are recorded, the
nlist entries are never decoded), relocation and Objective-C decoding;
dyld bind/export/lazy-linkedit semantics; code-signature verification;
encryption; disassembly; fat64 (`FAT_MAGIC_64` / `FAT_CIGAM_64`) arch
records; building Mach-O files; streaming I/O.

## Container layout

Unless noted, multi-byte fields use the byte order of the image (thin) or
of the fat header (fat). All offsets below are relative to the start of
the relevant structure.

### Magics (first 4 bytes)

The parser reads the first four bytes as a big-endian `u32`, so the
on-disk byte order is visible in the value:

| On-disk bytes | Big-endian read | Meaning |
|---|---|---|
| `FE ED FA CE` | `0xFEEDFACE` | 32-bit, big-endian (legacy) |
| `FE ED FA CF` | `0xFEEDFACF` | 64-bit, big-endian (legacy) |
| `CE FA ED FE` | `0xCEFAEDFE` | 32-bit, little-endian |
| `CF FA ED FE` | `0xCFFAEDFE` | 64-bit, little-endian |
| `CA FE BA BE` | `0xCAFEBABE` | fat, big-endian records |
| `BE BA FE CA` | `0xBEBAFECA` | fat, little-endian records |
| `CA FE BA BF` | `0xCAFEBABF` | fat64 -- detected, rejected |
| `BF BA FE CA` | `0xBFBAFECA` | fat64 -- detected, rejected |

Anything else (or a buffer shorter than four bytes) is
`APPLE_FORMAT_UNKNOWN`. Format codes are `APPLE_FORMAT_MACHO32_BE = 1`,
`_MACHO32_LE = 2`, `_MACHO64_BE = 3`, `_MACHO64_LE = 4`, `_FAT_BE = 5`,
`_FAT_LE = 6`, `_FAT64_BE = 7`, `_FAT64_LE = 8`, `_UNKNOWN = 0`.

### mach_header (28 bytes) / mach_header_64 (32 bytes)

| Offset | Size | Field | 32-bit | 64-bit |
|---|---|---|---|---|
| 0 | 4 | `magic` | yes | yes |
| 4 | 4 | `cputype` | yes | yes |
| 8 | 4 | `cpusubtype` | yes | yes |
| 12 | 4 | `filetype` | yes | yes |
| 16 | 4 | `ncmds` | yes | yes |
| 20 | 4 | `sizeofcmds` | yes | yes |
| 24 | 4 | `flags` | yes | yes |
| 28 | 4 | `reserved` | - | yes |

The load-command region is `[header_size, header_size + sizeofcmds)` and
must lie inside the buffer (header size 28 or 32). `sizeofcmds` must equal
the exact sum of the walked `cmdsize` values.

Decoded cputypes: `7` x86, `0x01000007` x86_64, `12` arm, `0x0100000C`
arm64, `0x0200000C` arm64_32, `18` ppc, `0x01000012` ppc64; exact matches
only (the ABI bits are part of the value). Everything else is
`APPLE_CPU_CLASS_UNKNOWN`.

Decoded filetypes: 1 object, 2 executable, 3 fvmlib, 4 core, 5 preload,
6 dylib, 7 dylinker, 8 bundle, 9 dylib-stub, 10 dsym, 11 kext-bundle,
12 fileset. The raw value is carried through untouched.

The `flags` field and all `APPLE_MH_*` constants are single-bit masks
(`macho_has_flag` extracts `(flags / mask) % 2`). `APPLE_MH_NOUNDEFS`
0x1, `_DYLDLINK` 0x4, `_TWOLEVEL` 0x80, `_NO_REEXPORTED_DYLIBS` 0x100000,
`_PIE` 0x200000, `_NO_HEAP_EXECUTION` 0x1000000,
`_APP_EXTENSION_SAFE` 0x2000000, `_DYLIB_IN_CACHE` 0x80000000, and the
rest of the documented `MH_*` set.

### Load commands

Every command starts with an 8-byte header:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `cmd` |
| 4 | 4 | `cmdsize` (bytes, including the 8-byte header) |

Rules enforced on every command:

1. `pos + 8 <= header_size + sizeofcmds`, else
   `apple: truncated load command at <pos>`;
2. `cmdsize >= 8`, else `apple: bad cmdsize at <pos+4>`;
3. `cmdsize % 4 == 0` in a 32-bit image, `cmdsize % 8 == 0` in a 64-bit
   image, else `apple: misaligned cmdsize at <pos+4>`;
4. the command must end inside `sizeofcmds`, else
   `apple: command exceeds sizeofcmds at <pos+4>`;
5. after `ncmds` commands the walked total must equal `sizeofcmds`, else
   `apple: load commands do not fill sizeofcmds at <pos>`.

A record is appended to the parallel `lc_*` vectors for **every** command;
the kind discriminates what was decoded:

| Kind | Commands | Decoded |
|---|---|---|
| `APPLE_LCK_SEGMENT` | `LC_SEGMENT` (0x1) | segment + sections |
| `APPLE_LCK_SEGMENT_64` | `LC_SEGMENT_64` (0x19) | segment + sections |
| `APPLE_LCK_DYLIB` | `LC_LOAD_DYLIB` (0xC), `LC_ID_DYLIB` (0xD), `LC_LOAD_WEAK_DYLIB` (0x80000018), `LC_REEXPORT_DYLIB` (0x8000001F), `LC_LOAD_UPWARD_DYLIB` (0x80000023), `LC_LAZY_LOAD_DYLIB` (0x20) | name + versions |
| `APPLE_LCK_UUID` | `LC_UUID` (0x1B) | 16 raw bytes |
| `APPLE_LCK_MAIN` | `LC_MAIN` (0x80000028) | entryoff, stacksize |
| `APPLE_LCK_LINKEDIT_DATA` | `LC_CODE_SIGNATURE` (0x1D), `LC_FUNCTION_STARTS` (0x26), `LC_DATA_IN_CODE` (0x29), `LC_DYLIB_CODE_SIGN_DRS` (0x2B), `LC_SEGMENT_SPLIT_INFO` (0x1E), `LC_DYLD_EXPORTS_TRIE` (0x80000033), `LC_DYLD_CHAINED_FIXUPS` (0x80000034), `LC_LINKER_OPTIMIZATION_HINT` (0x2E) | dataoff, datasize |
| `APPLE_LCK_BUILD_VERSION` | `LC_BUILD_VERSION` (0x32) | platform, minos, sdk, ntools |
| `APPLE_LCK_VERSION_MIN` | `LC_VERSION_MIN_MACOSX/IPHONEOS/TVOS/WATCHOS` (0x24/0x25/0x2F/0x30) | version, sdk |
| `APPLE_LCK_SYMTAB` | `LC_SYMTAB` (0x2) | symoff, nsyms, stroff, strsize |
| `APPLE_LCK_DYSYMTAB` | `LC_DYSYMTAB` (0xB) | kind only |
| `APPLE_LCK_DYLD_INFO` | `LC_DYLD_INFO` (0x22), `LC_DYLD_INFO_ONLY` (0x80000022) | kind only |
| `APPLE_LCK_SOURCE_VERSION` | `LC_SOURCE_VERSION` (0x2A) | raw 64-bit version |
| `APPLE_LCK_ENCRYPTION_INFO` | `LC_ENCRYPTION_INFO` (0x21), `LC_ENCRYPTION_INFO_64` (0x2C) | cryptoff, cryptsize, cryptid |
| `APPLE_LCK_DYLINKER` | `LC_LOAD_DYLINKER` (0xE), `LC_ID_DYLINKER` (0xF), `LC_DYLD_ENVIRONMENT` (0x27) | name |
| `APPLE_LCK_RPATH` | `LC_RPATH` (0x8000001C) | name |
| `APPLE_LCK_SUB` | `LC_SUB_FRAMEWORK/UMBRELLA/CLIENT/LIBRARY` (0x12..0x15) | name |
| `APPLE_LCK_THREAD` | `LC_THREAD` (0x4), `LC_UNIXTHREAD` (0x5) | kind only |
| `APPLE_LCK_OTHER` | recognized legacy commands (`LC_SYMSEG`, `LC_LOADFVMLIB`, `LC_FVMFILE`, `LC_PREPAGE`, `LC_PREBOUND_DYLIB`, `LC_ROUTINES(_64)`, `LC_TWOLEVEL_HINTS`, `LC_PREBIND_CKSUM`, `LC_LINKER_OPTION`, `LC_NOTE`, `LC_FILESET_ENTRY`, ...) | kind only |
| `APPLE_LCK_UNKNOWN` | anything else | kind only |

Unknown and kind-only commands keep their raw `cmd` / `cmdsize` / file
offset in the `lc_*` vectors; nothing is discarded. For the two segment
kinds, val1..val4 are `vmaddr`, `vmsize`, `fileoff`, `filesize` (the full
segment record lives in the `seg_*` vectors).

#### LC_SEGMENT / LC_SEGMENT_64

| Offset | Size | Field | 32-bit | 64-bit |
|---|---|---|---|---|
| 0 | 4 | `cmd` | yes | yes |
| 4 | 4 | `cmdsize` (>= 56 / 72, plus sections) | yes | yes |
| 8 | 16 | `segname` (NUL-padded) | yes | yes |
| 24 | 4/8 | `vmaddr` | yes | yes |
| 28/32 | 4/8 | `vmsize` | yes | yes |
| 32/40 | 4/8 | `fileoff` | yes | yes |
| 36/48 | 4/8 | `filesize` | yes | yes |
| 40/56 | 4 | `maxprot` | yes | yes |
| 44/60 | 4 | `initprot` | yes | yes |
| 48/64 | 4 | `nsects` | yes | yes |
| 52/68 | 4 | `flags` | yes | yes |

Section records follow at `56` (32-bit, 68 bytes each) or `72` (64-bit,
80 bytes each); `base + nsects * section_size` must fit `cmdsize` or
`apple: segment sections exceed cmdsize at <pos + 48|64>` is returned.
`maxprot`/`initprot` are decoded with the divisor-modulo rule: the low
three bits (`prot % 8`, normalized for negative raw values) map bit 0 =
read, bit 1 = write, bit 2 = execute; `macho_prot_text(5)` = `"r-x"`.

#### section / section_64

| Offset | Size | Field | 32-bit | 64-bit |
|---|---|---|---|---|
| 0 | 16 | `sectname` (NUL-padded) | yes | yes |
| 16 | 16 | `segname` (NUL-padded) | yes | yes |
| 32 | 4/8 | `addr` | yes | yes |
| 36/40 | 4/8 | `size` | yes | yes |
| 40/48 | 4 | `offset` | yes | yes |
| 44/52 | 4 | `align` (0..31) | yes | yes |
| 48/56 | 4 | `reloff` (carried, unused) | yes | yes |
| 52/60 | 4 | `nreloc` (carried, unused) | yes | yes |
| 56/64 | 4 | `flags` | yes | yes |
| 60/68 | 8/12 | `reserved1..3` (unused) | yes | yes |

`align` outside 0..31 is `apple: bad section alignment at <record +
44|52>`. A section with `size > 0` whose type (`flags % 256`) is not
`S_ZEROFILL` (1), `S_GB_ZEROFILL` (12) or `S_THREAD_LOCAL_ZEROFILL` (18)
must satisfy `offset + size <= buffer length`; otherwise
`apple: section data out of bounds at <record>`. A segment with
`filesize > 0` must satisfy `fileoff + filesize <= buffer length`
(`apple: segment data out of bounds at <command>`); `filesize == 0`
skips the offset check.

Segment and section names: bytes up to the first NUL (or all 16 bytes
when there is no NUL) must be printable ASCII `0x20..0x7E`, else
`apple: name not printable ASCII at <byte>`.

#### dylib_command (24 bytes; the six dylib-family commands)

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `cmd` |
| 4 | 4 | `cmdsize` (>= 24) |
| 8 | 4 | `name.offset` (relative to the command start) |
| 12 | 4 | `timestamp` |
| 16 | 4 | `current_version` (x.y.z packed) |
| 20 | 4 | `compatibility_version` (x.y.z packed) |
| `name.offset` | .. | NUL-terminated name inside the command |

`cmdsize < 24` is `apple: bad dylib command at <pos>`. The name offset
must satisfy `24 <= offset < cmdsize`, else `apple: bad name offset at
<pos+8>`. The name must be NUL-terminated inside the command and
printable ASCII. val1..val4 = name offset, timestamp, current,
compatibility; the name is decoded via `macho_command_name` and is `""`
for every other kind.

#### lc_str commands (12-byte payload header)

`LC_LOAD_DYLINKER`, `LC_ID_DYLINKER`, `LC_DYLD_ENVIRONMENT`,
`LC_RPATH`, `LC_SUB_*`: `cmdsize >= 12`, name offset at `+8` must
satisfy `12 <= offset < cmdsize`, name NUL-terminated and printable
inside the command. Errors: `apple: bad lc_str command at <pos>`,
`apple: bad name offset at <pos+8>`. val1 = name offset.

#### Fixed-size commands

| Command | cmdsize | Fields (offset: meaning) |
|---|---|---|
| `LC_UUID` | exactly 24 | 8..23: 16 raw UUID bytes (flat `uuid_bytes`) |
| `LC_MAIN` | exactly 24 | 8: `entryoff` (u64), 16: `stacksize` (u64) |
| linkedit data | exactly 16 | 8: `dataoff` (u32), 12: `datasize` (u32); a non-empty blob must fit the buffer (`apple: linkedit data out of bounds at <pos+8>`) |
| `LC_VERSION_MIN_*` | exactly 16 | 8: `version`, 12: `sdk` |
| `LC_SYMTAB` | exactly 24 | 8: `symoff`, 12: `nsyms`, 16: `stroff`, 20: `strsize` (locations only, no nlist decoding) |
| `LC_SOURCE_VERSION` | exactly 16 | 8: raw u64 version |
| `LC_ENCRYPTION_INFO` | exactly 20 | 8: `cryptoff`, 12: `cryptsize`, 16: `cryptid` |
| `LC_ENCRYPTION_INFO_64` | exactly 24 | as above, plus 4-byte pad at 20 |
| `LC_BUILD_VERSION` | >= 24 | 8: `platform`, 12: `minos`, 16: `sdk`, 20: `ntools`; `ntools * 8 <= cmdsize - 24` (`apple: build version tools exceed cmdsize at <pos+20>`); tool records are not decoded |

Wrong sizes produce `apple: bad LC_UUID size`, `bad LC_MAIN size`, `bad
linkedit command size`, `bad LC_BUILD_VERSION size`, `bad
LC_VERSION_MIN size`, `bad LC_SYMTAB size`, `bad LC_SOURCE_VERSION
size`, `bad LC_ENCRYPTION_INFO size`, each `... at <command offset>`.

All 64-bit fields (`entryoff`, `stacksize`, `LC_SOURCE_VERSION`, segment
and section addresses) decode as raw two's complement: bit 63 set
decodes as a negative `Int`, using the xiom.pack overflow-safe shape
(low seven bytes accumulate with a `place` factor, the top byte applied
separately).

### UUID access

`lc_uuid_starts[i]` / `lc_uuid_lens[i]` locate the 16 raw bytes of
command `i` inside the flat `uuid_bytes` vector (`-1` / `0` otherwise).
`macho_uuid_byte` returns 0..255 per byte; `macho_uuid_text` returns the
canonical 8-4-4-4-12 lowercase hex form (e.g. UUID bytes 1..16 ->
`"01020304-0506-0708-090a-0b0c0d0e0f10"`).

### Fat header (8 bytes) and fat_arch (20 bytes each)

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `magic` (`FAT_MAGIC` big-endian, `FAT_CIGAM` little-endian) |
| 4 | 4 | `nfat_arch` (must be >= 1) |
| 8 + 20*i | 4 | arch i `cputype` |
| 12 + 20*i | 4 | arch i `cpusubtype` |
| 16 + 20*i | 4 | arch i `offset` (slice start) |
| 20 + 20*i | 4 | arch i `size` (slice length) |
| 24 + 20*i | 4 | arch i `align` (power-of-two exponent) |

Validation, in order:

1. buffer >= 8 bytes, else `apple: truncated fat header at 0`;
2. magic is `FAT_MAGIC` (big-endian records) or `FAT_CIGAM`
   (little-endian records); fat64 magics are rejected as `apple: fat64
   header unsupported at 0`, anything else as `apple: not a fat archive
   at 0`;
3. `nfat_arch >= 1`, else `apple: bad fat arch count at 4`;
4. `nfat_arch * 20 <= buffer length - 8`, else `apple: fat arch table
   out of bounds at 4`;
5. per arch: `align` in 0..32, else `apple: bad fat arch alignment at
   <record+16>`; a slice with `size > 0` must satisfy
   `offset + size <= buffer length` (`apple: fat slice out of bounds at
   <record+8>`) and must start at or after the end of the arch table
   (`apple: fat slice overlaps the arch table at <record+8>`); when
   `align > 0`, `offset % 2^align == 0`, else `apple: misaligned fat
   slice at <record+16>`;
6. every arch pair must be disjoint: for slices a and b with positive
   sizes, `a.offset >= b.offset + b.size` or `b.offset >= a.offset +
   a.size`, else `apple: fat slices overlap at <later record + 8>`.

Conventional align exponents: 12 = 4 KB pages, 14 = 16 KB pages; 0 means
no alignment requirement. Slice payloads are not validated as Mach-O;
use `fat_slice_bytes` (copy) or `fat_slice_macho` (copy + `macho_parse`).

## Validation order summary

Thin: magic/length, thin-ness, header length, `sizeofcmds` bound, then
command-by-command (size rules, decode); the first failure aborts with the
error string above and no partial file.

Fat: length, magic, count, table span, per-arch fields, pair overlaps.

## Error catalog

Every thin Mach-O and fat error message is
`"apple: <what> at <n>"`, where `n` is the byte offset of the offending
field or structure; the exact strings are:

`truncated magic` (0), `bad magic` (0), `fat header where a thin Mach-O
was expected` (0), `truncated header` (0), `sizeofcmds out of bounds`
(20), `truncated load command` (command start), `bad cmdsize` (size
field), `misaligned cmdsize` (size field), `command exceeds sizeofcmds`
(size field), `load commands do not fill sizeofcmds` (first byte past
the walked commands), `bad segment command` (command start), `segment
sections exceed cmdsize` (nsects field), `segment data out of bounds`
(command start), `bad section alignment` (align field), `section data
out of bounds` (section start), `name not printable ASCII` (name byte),
`bad dylib command` (command start), `bad lc_str command` (command
start), `bad name offset` (name-offset field), `name not NUL-terminated`
(name start), `bad LC_UUID size` (command start), `bad LC_MAIN size`
(command start), `bad linkedit command size` (command start), `linkedit
data out of bounds` (dataoff field), `bad LC_BUILD_VERSION size`
(command start), `build version tools exceed cmdsize` (ntools field),
`bad LC_VERSION_MIN size` (command start), `bad LC_SYMTAB size`
(command start), `bad LC_SOURCE_VERSION size` (command start), `bad
LC_ENCRYPTION_INFO size` (command start), `truncated fat header` (0),
`bad fat arch count` (4), `fat arch table out of bounds` (4), `fat slice
out of bounds` (offset field), `fat slice overlaps the arch table`
(offset field), `misaligned fat slice` (align field), `bad fat arch
alignment` (align field), `fat slices overlap` (later offset field),
`not a fat archive` (0), `fat64 header unsupported` (0).

Selector/index errors carry no offset: `index out of range`, `bad field
selector`, `no uuid on this command`.

## Test plan

`tests/test_conformance.xi` (21 checks, all synthetic fixtures built in
the test file):

1. all eight magics plus unknown/short buffers, format bits/endianness/
   names, fat/thin predicates;
2. `mach_header_64` scalar fields and cpu/filetype names;
3. header flag bits (NOUNDEFS/DYLDLINK/TWOLEVEL/PIE true, others false;
   32-bit SUBSECTIONS_VIA_SYMBOLS);
4. all 11 load commands of the fixture pinned by cmd/cmdsize/offset/kind;
5. LC_SEGMENT_64 + one section, every field selector, protection text;
6. dylib name/versions, and the same payload as LOAD_WEAK/REEXPORT;
7. LC_UUID raw bytes and canonical text;
8. LC_MAIN, code signature, build version (macos 13.1.0 / sdk 14.0.0),
   source version, version_min (10.15.0 / 11.0.0), symtab, encryption;
9. 32-bit LE fixture (LC_SEGMENT with two sections, LC_UUID);
10. 32-bit BE fixture and all cputype classifications;
11. truncated magic/header, bad magic, sizeofcmds bound, fat-in-thin;
12. cmdsize too small / misaligned / over sizeofcmds / not filling it,
    plus a valid two-command walk;
13. command crossing sizeofcmds is a truncation; empty tables parse;
14. segment nsects overflow, segment/section span bounds, alignment,
    non-printable names, S_ZEROFILL exemption;
15. dylib name offset bounds, NUL termination, printable ASCII;
16. fixed-size command size errors and linkedit/build-version bounds;
17. raw two's-complement decoding of high-bit 64-bit fields;
18. big-endian fat: 2 archs (x86_64 @4 KB align 12, arm64 @16 KB align
    14), field selectors, selection, slice copy/parse;
19. little-endian FAT_CIGAM archive;
20. fat count/table/slice bounds, misalignment, table overlap, slice
    overlap, fat64, not-fat, OOR slice, truncation;
21. index/field-selector errors across all tables.

Fixture bytes are assembled in the test file independently of
`src/apple.xi`; `Str` equality goes through
`xiom.string.compare.str_compare` (BUG 17 discipline).
