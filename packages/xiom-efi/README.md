# xiom.efi

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** UEFI Firmware File System (FFS) codec for one file: the 24-byte
> small header, the 32-byte large-file header with the documented `0xFFFFFF`
> extended-size rule, the section walk over the documented PI section types,
> the raw integrity-check stances and a canonical single-section builder.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`). Tests
> additionally use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.efi` reads and writes the structural part of a UEFI FFS file. `ffs_parse`
validates the file header (name GUID, integrity check, type, attributes, size,
state; including the large-file rule) and walks the section stream into an
`FfsFile` of flat parallel vectors: one element per section for its type,
declared size, absolute section offset, absolute data offset and data size.

The name GUID is surfaced as the 32 lowercase hex characters of the 16 raw
on-disk bytes; the integrity check, type, attributes and state bytes are
stored raw. Unknown section types pass through as raw spans. The documented
per-type metadata is decoded on demand: COMPRESSION uncompressed length,
GUID_DEFINED and FREEFORM_SUBTYPE_GUID GUIDs, VERSION build number/version
and USER_INTERFACE strings (UTF-16LE decoded to printable ASCII, stop at the
first `0x0000`, non-ASCII becomes `?`). Compression payloads and disposable
sections are never expanded, PE32/TE/PIC stay raw, and depex sections are not
evaluated.

`ffs_build` emits a canonical file: the 24-byte header (or an error, large
files are not built), exactly one section whose body the caller supplies
including any per-type header bytes, zero padding to the 4-byte section and
8-byte file alignment, and the documented additive checksums when
`FFS_ATTRIB_CHECKSUM` is set.

Integrity checks are opt-in: `ffs_integrity_ok` implements both documented
stances (zero vector when bit `0x40` is clear, additive 8-bit header/data
checksums when set) and `ffs_parse` never rejects a mismatch.

## Install

Not yet published. Consume it from this repository with the package harness:

```
& .\scripts\port.ps1 -Package xiom.efi
```

Once published, the manifest name is `xiom.efi` version `0.1.0`.

## API

All functions are free functions in module `xiom.efi`.

| Function | Returns | Description |
|---|---|---|
| `ffs_parse(data)` | `Result[FfsFile, Str]` | Validate one file and index its sections. |
| `ffs_build(name, file_type, attributes, state, section_type, body)` | `Result[Vec[UInt8], Str]` | Build a canonical small-header file with one section. |
| `ffs_file_name(f)` | `Str` | Name GUID as 32 lowercase hex characters. |
| `ffs_file_type(f)` | `Int` | Raw type byte. |
| `ffs_file_type_name(t)` | `Str` | Documented name of a file type byte. |
| `ffs_file_attributes(f)` | `Int` | Raw attributes byte (bit `0x01` large, `0x40` checksum). |
| `ffs_file_size(f)` | `Int` | Declared file size (24-bit or extended u64). |
| `ffs_file_state(f)` | `Int` | Raw state byte. |
| `ffs_file_integrity_check(f)` | `Int` | Raw 16-bit integrity check. |
| `ffs_file_is_large(f)` | `Bool` | True when the large-file attribute is set. |
| `ffs_file_header_size(f)` | `Int` | 24 for small files, 32 for large files. |
| `ffs_section_count(f)` | `Int` | Safe section count (parallel-vector minimum). |
| `ffs_section_type(f, i)` | `Int` | Type byte of section `i`; `-1` out of range. |
| `ffs_section_type_name(t)` | `Str` | Documented name of a section type byte. |
| `ffs_section_size(f, i)` | `Int` | Declared total size incl. padding; `-1` out of range. |
| `ffs_section_offset(f, i)` | `Int` | Absolute section header offset; `-1` out of range. |
| `ffs_section_data_offset(f, i)` | `Int` | Absolute data offset; `-1` out of range. |
| `ffs_section_data_size(f, i)` | `Int` | Data byte count; `-1` out of range. |
| `ffs_section_raw(data, f, i)` | `Result[Vec[UInt8], Str]` | Copy the whole raw section. |
| `ffs_section_data(data, f, i)` | `Result[Vec[UInt8], Str]` | Copy the section data bytes verbatim. |
| `ffs_section_build_number(data, f, i)` | `Int` | VERSION build number; `-1` when not applicable. |
| `ffs_section_version(data, f, i)` | `Int` | VERSION version field; `-1` when not applicable. |
| `ffs_section_ui_string(data, f, i)` | `Str` | UI string decoded to printable ASCII; `""` otherwise. |
| `ffs_section_guid(data, f, i)` | `Str` | GUID of a GUID_DEFINED/`FREEFORM_SUBTYPE_GUID` section. |
| `ffs_section_guid_data_offset(data, f, i)` | `Int` | GUID_DEFINED `DataOffset` field; `-1` otherwise. |
| `ffs_section_guid_attributes(data, f, i)` | `Int` | GUID_DEFINED `Attributes` field; `-1` otherwise. |
| `ffs_section_compression_length(data, f, i)` | `Int` | COMPRESSION uncompressed length; `-1` otherwise. |
| `ffs_header_checksum(data, f)` | `Int` | Additive 8-bit header checksum; `-1` when the span is invalid. |
| `ffs_data_checksum(data, f)` | `Int` | Additive 8-bit data checksum; `-1` when the span is invalid. |
| `ffs_integrity_ok(data, f)` | `Bool` | Documented integrity-check stance for the stored value. |

`FfsFile` holds the header scalars plus five parallel section vectors
(`section_types`, `section_sizes`, `section_offsets`, `section_data_offsets`,
`section_data_sizes`); no `Vec` of structs is used.

## Quick start

Reading a file image (`data` holds at least the declared file size):

```xi
use xiom.efi;
use xiom.io;
use xiom.convert;

fn report(data: &Vec[UInt8]) {
  let pr = ffs_parse(data);
  if !pr.is_ok {
    io.println("error: " + pr.error);
    return;
  }
  let f = pr.value;
  io.println("file: " + ffs_file_name(&f));
  io.println("type: " + ffs_file_type_name(ffs_file_type(&f)));
  io.println("size: " + convert.int_to_string(ffs_file_size(&f)));

  if !ffs_integrity_ok(data, &f) {
    io.println("warning: integrity check mismatch");
  }

  var i = 0;
  while i < ffs_section_count(&f) {
    io.println("section " + convert.int_to_string(i) + ": " + ffs_section_type_name(ffs_section_type(&f, i)));
    if ffs_section_type(&f, i) == 21 {
      io.println("  ui: " + ffs_section_ui_string(data, &f, i));
    }
    i = i + 1;
  }
}
```

Building a file with one RAW section (`body` is the section body after the
4-byte common header):

```xi
use xiom.efi;

var body = Vec[UInt8].new();
body.push(1 as UInt8);
body.push(2 as UInt8);
body.push(3 as UInt8);
body.push(4 as UInt8);

let built = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 7, 25, &body);
```

The builder writes a 32-byte file (24-byte header + an 8-byte RAW section),
zero-pads to the 4/8-byte alignment boundaries and writes a zero integrity
check. Pass attributes `0x40` to have the additive checksums computed and
patched.

## Errors

Every parse/build failure is an `Err(Str)` with a deterministic `efi:`
message:

| Message | Condition |
|---|---|
| `efi: truncated header` | Buffer shorter than 24 bytes (or 32 when the large bit is set). |
| `efi: bad large-file size` | Large bit set but the 24-bit size field is not `0xFFFFFF`. |
| `efi: bad file size` | Size below the header size, or a negative extended size. |
| `efi: truncated file` | Declared size exceeds the buffer. |
| `efi: bad section size` | Declared section size below 4. |
| `efi: section overruns file` | Declared section size exceeds the remaining bytes. |
| `efi: truncated section` | Non-zero trailing bytes shorter than a section header. |
| `efi: section too small` | Section smaller than its documented type header. |
| `efi: bad section data offset` | GUID_DEFINED data offset outside `20..Size`. |
| `efi: bad ui string` | UI body odd-sized or missing its terminal `0x0000`. |
| `efi: index out of range` | `ffs_section_raw`/`ffs_section_data` bad index. |
| `efi: span out of bounds` | Recorded span does not fit the supplied buffer. |
| `efi: bad name` | Build name is not exactly 32 hex characters. |
| `efi: bad file type` / `efi: bad attributes` / `efi: bad state` / `efi: bad section type` | Build byte outside `0..255`. |
| `efi: large files unsupported` | Build attributes have bit `0x01` set. |
| `efi: bad section body` | Body violates the documented per-type minimums. |
| `efi: file too large` | Padded build would exceed `0xFFFFFF` bytes. |

Integrity mismatches are **not** errors: `ffs_parse` stores the value raw and
`ffs_integrity_ok` reports the stance as a `Bool`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.efi
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines,
`xiom.efi: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`. Fixtures are
assembled byte by byte, so `ffs_parse` is exercised independently of
`ffs_build`.

## Limitations

- **One file.** Firmware volume structure (FV headers, block maps, free
  space) is not parsed.
- **Parse-only large files.** The builder always emits the 24-byte header.
- **Raw leaves.** PE32/TE/PIC, depex, disposable and unknown sections are
  returned verbatim; compression payloads are never decompressed and nested
  sections are never walked.
- **Documented subset.** The file/section type name tables are narrow
  subsets (see `SPEC.md`); unnamed type bytes pass through as `UNKNOWN`.
- **ASCII-only UI strings.** Non-ASCII UTF-16 code units become `?` and
  cannot be reproduced by the builder.
- **Opt-in integrity.** Checks are never enforced during parse; call
  `ffs_integrity_ok` explicitly.
- **Alignment not enforced.** Section sizes are expected to be multiples of
  4, but the parser accepts any size >= 4; the builder always pads.
- **Signed 64-bit range.** Extended sizes with bit 63 set are rejected.
- Not thread-safe; `FfsFile` is a plain value type.

See `SPEC.md` for the full byte layout, type tables, error catalog and test
matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
