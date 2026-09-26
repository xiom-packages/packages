# xiom.uboot

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** U-Boot **legacy** image header codec: parse and inspect the
> 64-byte `image_header_t`, verify both CRC-32 fields, and build a canonical
> header plus payload.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`). Tests
> additionally use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.uboot` reads and writes the fixed 64-byte U-Boot legacy image header
(the `ih_` struct): big-endian magic `27 05 19 56`, header CRC-32, timestamp,
data size, load address, entry point, data CRC-32, four id bytes (OS,
architecture, image type, compression) and a 32-byte NUL-padded printable
name. The payload follows the header at offset 64.

`uboot_parse_header` decodes and validates a header from a buffer of at least
64 bytes without looking at the payload; `uboot_parse` additionally requires
the declared data size to fit the buffer. Both return a flat `UbootHeader`
scalar struct (no vectors, no `Vec` of structs). `uboot_data_bytes` copies
the payload span and `uboot_data_offset` / `uboot_data_end` expose its
bounds.

Both CRC-32 fields are stored raw and `uboot_parse` never rejects a
mismatch: call `uboot_header_crc_ok` / `uboot_data_crc_ok` (or
`uboot_crc32` / `uboot_crc32_range`) to verify. The header CRC is computed
over the 64 header bytes with the `ih_hcrc` field itself treated as zero,
the U-Boot rule. The CRC-32 is implemented locally with the standard
reflected polynomial and is table-free.

The id name tables are **partial and documented** (see `SPEC.md` section 4):
ids outside a table are passed through unchanged and their name accessors
report `"unknown"`. `uboot_build` writes a canonical image: fixed magic, the
caller's timestamp/addresses/ids/name, the size derived from the payload and
both CRCs recomputed. FIT images (`d00dfeed`) are detected by
`uboot_is_fit` and rejected by both parsers with
`uboot: FIT image not supported`.

## Install

Not yet published. Consume it from this repository with the package harness:

```
& .\scripts\port.ps1 -Package xiom.uboot
```

Once published, the manifest name is `xiom.uboot` version `0.1.0`.

## API

All functions are free functions in module `xiom.uboot`.

| Function | Returns | Description |
|---|---|---|
| `uboot_header_size()` | `Int` | Header size in bytes (always 64). |
| `uboot_data_offset()` | `Int` | Payload offset (always 64). |
| `uboot_is_fit(data)` | `Bool` | True when the buffer starts with the FIT magic `d00dfeed`. |
| `uboot_parse(data)` | `Result[UbootHeader, Str]` | Parse a full image; requires `64 + ih_size <= data.len()`. |
| `uboot_parse_header(data)` | `Result[UbootHeader, Str]` | Parse a header from a buffer of at least 64 bytes (payload ignored). |
| `uboot_build(h, payload)` | `Result[Vec[UInt8], Str]` | Build a canonical header plus payload (size and CRCs derived/recomputed). |
| `uboot_magic(h)` | `Int` | Magic field (the legacy magic after a parse). |
| `uboot_timestamp(h)` | `Int` | Raw 32-bit creation timestamp. |
| `uboot_data_size(h)` | `Int` | Declared data size in bytes (`ih_size`). |
| `uboot_load_addr(h)` | `Int` | Raw 32-bit load address. |
| `uboot_entry_point(h)` | `Int` | Raw 32-bit entry point. |
| `uboot_header_crc(h)` | `Int` | Stored header CRC-32, raw. |
| `uboot_data_crc(h)` | `Int` | Stored data CRC-32, raw. |
| `uboot_os(h)` / `uboot_os_name(h)` | `Int` / `Str` | OS id byte and its documented name (else `"unknown"`). |
| `uboot_arch(h)` / `uboot_arch_name(h)` | `Int` / `Str` | Architecture id byte and its documented name (else `"unknown"`). |
| `uboot_image_type(h)` / `uboot_image_type_name(h)` | `Int` / `Str` | Image type id byte and its documented name (else `"unknown"`). |
| `uboot_compression(h)` / `uboot_compression_name(h)` | `Int` / `Str` | Compression id byte and its documented name (else `"unknown"`). |
| `uboot_name(h)` | `Str` | Name decoded up to the first NUL (or all 32 bytes). |
| `uboot_data_end(h)` | `Int` | `64 + ih_size`. |
| `uboot_data_bytes(data, h)` | `Result[Vec[UInt8], Str]` | Copy the payload span (or `Err` when it does not fit). |
| `uboot_crc32(data)` | `Int` | Standard CRC-32 of the whole buffer. |
| `uboot_crc32_range(data, start, count)` | `Int` | Standard CRC-32 of a span; `-1` when the span is invalid. |
| `uboot_header_crc_ok(data, h)` | `Bool` | Recompute the header CRC (its own field zeroed) and compare. |
| `uboot_data_crc_ok(data, h)` | `Bool` | Recompute the payload CRC over `[64, 64 + ih_size)` and compare. |

`UbootHeader` is a flat scalar struct: `magic`, `hcrc`, `time`, `size`,
`load`, `ep`, `dcrc`, `os`, `arch`, `image_type`, `comp`, `name`.

### Documented partial id tables

| Table | Ids |
|---|---|
| OS | 0 `invalid`, 1 `openbsd`, 3 `freebsd`, 5 `linux`, 6 `vxworks` |
| Architecture | 2 `arm`, 3 `i386`, 5 `mips`, 6 `mips64`, 7 `ppc`, 22 `aarch64` |
| Image type | 1 `standalone`, 2 `kernel`, 3 `ramdisk`, 4 `multi`, 5 `firmware`, 6 `script`, 8 `filesystem`, 14 `kernel-noload` |
| Compression | 0 `none`, 1 `gzip`, 2 `bzip2`, 3 `lzma`, 5 `lzo`, 6 `lz4`, 9 `zstd` |

Any other id is legal, is preserved by the parsers and the builder, and its
name accessor returns `"unknown"` (the tables are partial by design; see
`SPEC.md`).

## Quick start

Reading a legacy image (`data` holds the header plus as much payload as the
caller loaded):

```xi
use xiom.uboot;
use xiom.io;
use xiom.convert;

fn report(data: &Vec[UInt8]) {
  let pr = uboot_parse(&data);
  if !pr.is_ok {
    io.println("error: " + pr.error);
    return;
  }
  let h = pr.value;
  io.println("name: " + uboot_name(&h));
  io.println("os:   " + uboot_os_name(&h));
  io.println("arch: " + uboot_arch_name(&h));
  io.println("comp: " + uboot_compression_name(&h));
  io.println("size: " + convert.int_to_string(uboot_data_size(&h)));

  if !uboot_header_crc_ok(&data, &h) {
    io.println("warning: header CRC mismatch");
  }
  if !uboot_data_crc_ok(&data, &h) {
    io.println("warning: data CRC mismatch");
  }
}
```

Building a kernel image from a payload:

```xi
use xiom.uboot;

let h = UbootHeader{
  magic: 654645590;          // ignored by the builder (always canonical)
  hcrc: 0;                   // ignored (recomputed)
  time: 1735689600;          // 2025-01-01T00:00:00Z
  size: 0;                   // ignored (derived from the payload)
  load: 2147516416;          // 0x80008000
  ep: 2147516416;            // 0x80008000
  dcrc: 0;                   // ignored (recomputed)
  os: 5;                     // linux
  arch: 2;                   // arm
  image_type: 2;             // kernel
  comp: 1;                   // gzip
  name: "linux kernel";
};

let built = uboot_build(&h, &payload);   // 64 + payload.len() bytes
```

The payload is written verbatim: the codec never compresses or decompresses
(`comp` is only an id), and it does not interpret multi-image payloads.

## Errors

Every failure is an `Err(Str)` with a deterministic `uboot:` message:

| Message | Condition |
|---|---|
| `uboot: truncated header` | Buffer shorter than 64 bytes. |
| `uboot: FIT image not supported` | The first four bytes are `d00dfeed` (FIT is a non-goal). |
| `uboot: bad magic` | The first four bytes are neither the legacy magic nor the FIT magic. |
| `uboot: truncated data` | `uboot_parse` / `uboot_data_bytes`: `64 + ih_size` exceeds the buffer. |
| `uboot: bad image name` | A name byte outside `0x20..0x7E` before the NUL, or a build name longer than 32 characters / non-printable. |
| `uboot: bad timestamp` | Build `time` outside `0..2^32-1`. |
| `uboot: bad address` | Build `load` or `ep` outside `0..2^32-1`. |
| `uboot: bad id` | Build id byte outside `0..255`. |
| `uboot: data too large` | Build payload longer than `2^32-1` bytes. |

CRC mismatches are **not** errors: both parsers store the CRC fields raw and
the verification helpers return `Bool`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.uboot
```

Expected: the section-4 namespace check passes, 16 `[PASS]` lines,
`xiom.uboot: all tests passed`, then
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)`. The gzip fixture's
CRCs are pinned from an independent table-driven computation, so the parser
is exercised against bytes the module did not produce.

## Limitations

- **Legacy images only.** FIT (`d00dfeed`), the new U-Boot image format and
  any multi-file container semantics are out of scope.
- **No (de)compression.** `ih_comp` is only an id; the payload is opaque.
- **Partial id tables.** Unknown ids are legal and pass through, but their
  names are `"unknown"`.
- **No CRC enforcement on parse.** Call the verification helpers.
- **ASCII-only names.** Decoding rejects non-printable bytes and the builder
  accepts only printable ASCII.
- **Raw 32-bit fields.** Addresses are plain numbers; no relocation or
  memory-model interpretation.
- Not thread-safe; all values are plain value types.

See `SPEC.md` for the full byte layout, validation order, error catalog and
test matrix. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
