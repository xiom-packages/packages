# xiom.smbios

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM SMBIOS/DMI codec for a documented subset: both
> entry-point variants (32-bit `_SM_`, 64-bit `_SM3_`) with a documented
> preference rule, the structure table stream, the documented structure
> types 0/1/2/3/4/16/17 and canonical builders.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.encoding`). The tests
> use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI.

## What it is

`xiom.smbios` decodes and encodes the SMBIOS (DMI) firmware tables:

- **Entry points.** `smbios_entry32_parse` validates the 31-byte `_SM_`
  entry point (anchor, checksum, length 1Fh, major/minor, max structure
  size, entry revision, `_DMI_` intermediate anchor plus checksum, table
  length/address, structure count, BCD revision).
  `smbios_entry64_parse` validates the 24-byte `_SM3_` entry point
  (anchor, checksum, length 18h, major/minor, docrev, revision, table
  maximum size, u64 table address). `smbios_entry_parse` scans
  16-byte-aligned offsets and applies the documented preference rule:
  the first `_SM3_` anchor wins; `_SM_` is used only when there is none.
- **Structure table.** `smbios_table_parse` walks a standalone table;
  `smbios_parse` locates the preferred entry point in an image and parses
  the table it points at. Every structure keeps its type, formatted
  length, little-endian handle, raw formatted span and string spans in
  flat parallel vectors -- unknown types are preserved, never decoded.
  Strings are 1-indexed, index 0 means "no string provided", and each
  string set is terminated by the documented double NUL.
- **Documented fields.** Accessors for BIOS Information (type 0), System
  Information (type 1, including the raw 16-byte UUID), Baseboard
  (type 2), Chassis (type 3, with the type name table), Processor
  (type 4), Physical Memory Array (type 16) and Memory Device (type 17).
  Pass-through fields are documented as raw (ROM size, processor family,
  memory type, memory size/speed/capacity). Type 127 ends the walk.
- **Builders.** `smbios_entry32_build` and `smbios_entry64_build` emit
  canonical entry points with computed checksums; `smbios_struct_build`
  emits one canonical structure with its string set; and
  `smbios_image_build32(table, ...)` emits a complete canonical 32-bit
  image (entry point at offset 0, table at offset 32) that parses back to
  the same structures.

## API

| Function | Returns | Description |
|---|---|---|
| `smbios_entry32_parse(data)` | `Result[SmbiosEntry, Str]` | Validate the `_SM_` entry point at offset 0. |
| `smbios_entry64_parse(data)` | `Result[SmbiosEntry, Str]` | Validate the `_SM3_` entry point at offset 0. |
| `smbios_entry_parse(data)` | `Result[SmbiosEntry, Str]` | Preferred entry point (first aligned `_SM3_`, else `_SM_`). |
| `smbios_entry_points(data)` | `Int` | Number of aligned entry-point anchors (normally 1 or 2). |
| `smbios_entry_checksum_ok(data)` | `Bool` | Preferred entry point's own checksum. |
| `smbios_entry32_checksum_ok(data)` | `Bool` | `_SM_` 31-byte checksum. |
| `smbios_entry32_intermediate_checksum_ok(data)` | `Bool` | `_DMI_` 15-byte intermediate checksum. |
| `smbios_entry64_checksum_ok(data)` | `Bool` | `_SM3_` 24-byte checksum. |
| `smbios_checksum8(data, off, len)` | `Int` | Modulo-256 sum of a span, or -1 when the span is invalid. |
| `smbios_table_parse(table)` | `Result[SmbiosTable, Str]` | Walk and validate a standalone structure table. |
| `smbios_parse(data)` | `Result[SmbiosTable, Str]` | Preferred entry point plus the table it points at. |
| `smbios_count(t)` / `smbios_type(t, i)` | `Int` | Structure count / type (`-1` out of range). |
| `smbios_length(t, i)` / `smbios_handle(t, i)` | `Int` | Formatted length / handle. |
| `smbios_struct_start(t, i)` / `smbios_formatted_len(t, i)` | `Int` | Buffer offset / formatted length of structure `i`. |
| `smbios_find_type(t, stype)` | `Int` | First structure of a type, or -1. |
| `smbios_formatted(data, t, i)` | `Result[Vec[UInt8], Str]` | Raw formatted bytes. |
| `smbios_string_count(t, i)` | `Int` | Number of strings of structure `i`. |
| `smbios_string_bytes(data, t, i, s)` | `Result[Vec[UInt8], Str]` | Raw bytes of 1-indexed string `s` (0 = empty). |
| `smbios_string(data, t, i, s)` | `Result[Str, Str]` | UTF-8 text of 1-indexed string `s`. |
| `smbios_uuid(data, t, i)` | `Result[Vec[UInt8], Str]` | 16 raw UUID bytes of a System Information structure. |
| `smbios_*_build(...)` | `Result[Vec[UInt8], Str]` | Canonical entry-point / structure / image builders. |

Field accessors (`smbios_bios_vendor`, `smbios_system_serial`,
`smbios_chassis_type`, `smbios_chassis_type_name`,
`smbios_processor_version`, `smbios_memory_array_capacity`,
`smbios_memory_device_size`, ...) return the raw little-endian value,
or -1 when the index is out of range, the structure has another type or
the field does not fit the formatted area. See SPEC.md for the full
offset table, the chassis name table and the UUID byte-order note.

Errors: `smbios: 32-bit entry point too short`, `bad 32-bit signature`,
`bad 32-bit entry length`, `bad 32-bit checksum`, `bad intermediate
anchor`, `bad intermediate checksum`, `64-bit entry point too short`,
`bad 64-bit signature`, `bad 64-bit entry length`, `bad 64-bit
checksum`, `no entry point`, `truncated structure`, `invalid structure
length`, `duplicate handle`, `unterminated string set`, `structure count
mismatch`, `table out of buffer`, `structure index out of range`,
`string index out of range`, `structure out of bounds`, `string out of
bounds`, `invalid string bytes`, `uuid out of range` plus the builder
range errors (see SPEC.md for the exact conditions).

## Usage

```xi
use xiom.smbios;
use xiom.io;
use xiom.convert;

// One BIOS Information structure (type 0), three strings.
var formatted = Vec[UInt8].new();
formatted.push(1 as UInt8);      // 04h vendor string index
formatted.push(2 as UInt8);      // 05h BIOS version string index
formatted.push(0 as UInt8);      // 06h starting segment (LE 0xE800 below)
formatted.push(232 as UInt8);
formatted.push(3 as UInt8);      // 08h release date string index
formatted.push(127 as UInt8);    // 09h ROM size byte (pass-through)
var k = 0;
while k < 8 {                    // 0Ah..11h characteristics
  formatted.push(0 as UInt8);
  k = k + 1;
}
var strings = Vec[Str].new();
strings.push("Vendor Inc");
strings.push("1.2.3");
strings.push("01/01/2026");
let sr = smbios_struct_build(SMBIOS_TYPE_BIOS, 0, &formatted, &strings);
var empty_bytes = Vec[UInt8].new();
var empty_strings = Vec[Str].new();
let er = smbios_struct_build(SMBIOS_TYPE_END_OF_TABLE, 1, &empty_bytes,
  &empty_strings);
if sr.is_ok && er.is_ok {
  let bios: Vec[UInt8] = sr.value;
  let eot: Vec[UInt8] = er.value;
  var table = Vec[UInt8].new();
  var i = 0;
  while i < bios.len() { table.push(bios[i]); i = i + 1; }
  i = 0;
  while i < eot.len() { table.push(eot[i]); i = i + 1; }

  // Canonical 32-bit image; then parse it back.
  let ir = smbios_image_build32(&table, 2, 8, 40);
  if ir.is_ok {
    let image: Vec[UInt8] = ir.value;
    let pr = smbios_parse(&image);
    if pr.is_ok {
      let t: SmbiosTable = pr.value;
      let b = smbios_find_type(&t, SMBIOS_TYPE_BIOS);
      io.println("structures: " + convert.int_to_string(smbios_count(&t)));
      io.println("vendor idx: " + convert.int_to_string(smbios_bios_vendor(&image, &t, b)));
      let v = smbios_string(&image, &t, b, 1);
      if v.is_ok {
        let vendor: Str = v.value;
        io.println("vendor: " + vendor);   // Vendor Inc
      }
    }
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.smbios
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Documented subset only.** Types 0, 1, 2, 3, 4, 16, 17 and 127 are
  decoded; everything else is preserved raw. Value tables other than the
  chassis type name table (processor family, memory type, ROM size
  scaling, UUID text form) are not decoded.
- **Documented lengths only.** Entry-point lengths must be exactly 1Fh
  (`_SM_`) or 18h (`_SM3_`); other revisions are rejected.
- **Addresses are offsets.** `smbios_parse` uses the entry point's table
  address as an offset into the buffer it is given; there is no
  physical-address mapping and no scan of the real 0xF0000 firmware
  window.
- **64-bit table bounds.** A `_SM3_` table runs to the buffer end or to
  `table_addr + max_size` when that is smaller and non-zero; the walk
  stops at type 127 or the bound.
- **Strict handle policy.** Handles must be unique; a repeat is always
  `smbios: duplicate handle`.
- **Strings are UTF-8 text or raw bytes.** `smbios_string` reports
  invalid UTF-8; use `smbios_string_bytes` for arbitrary vendor bytes.
- **No streaming.** Buffers are in-memory `Vec[UInt8]`; the parsed store
  holds offsets into the buffer it was parsed from, so that buffer must
  stay alive.
- Not thread-safe; `SmbiosEntry` / `SmbiosTable` are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
