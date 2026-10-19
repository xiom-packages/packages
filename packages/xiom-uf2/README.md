# xiom.uf2

> **Status:** `incubating` -- conformance-tested (**58/58 x2** on compiler pin
> v0.64.7; host-side format + flash legs; absent volume = SKIP); not yet
> published.
> **Scope (0.1.0):** UF2 512-byte block/image build, parse and validation
> (magics, flags, target address, payload, block numbering, family IDs);
> byte-exact built/source roundtrip; flash-to-mounted-BOOTSEL-volume with
> binary copy, read-back verification and unmount completion detection;
> typed errors; deterministic SKIP when no mount/volume is present.
> **Deps:** `xiom.std` only.

## What it is

`xiom.uf2` is the firmware-image half of the MCU host-companion set (with
`xiom.serial`, `xiom.firmata` and `xiom.micropython`).  It is a **pure-XIOM
implementation** of the UF2 format used by RP2040/RP2350 BOOTSEL,
SAMD21/SAMD51 Arduino bootloaders and many other MCUs.  The upstream
`microsoft/uf2` project (MIT, pin `90e9741f`) is reference-only: no code is
vendored (see `PROVENANCE.md`).

A UF2 file is a sequence of independent 512-byte blocks.  Each block has a
32-byte little-endian header, up to 476 payload bytes, zero padding to
offset 508 and the end magic `0x0AB16F30`.  The format leg is deterministic
and hardware-free; the flash leg only touches the mount path the caller
supplies.

## Quick start

```xiom
use xiom.uf2;

// Build an RP2040 image at 0x10000000 (flash XIP base).
let img = uf2_image_build(&firmware, 268435456, UF2_FAMILY_RP2040);
if !img.is_ok { io.println("build: " + img.error.message); }

// Validate any UF2 file (e.g. before copying it by hand).
let ok = uf2_image_validate(&bytes);

// Flash to a mounted BOOTSEL volume; wait up to 30 s for the reboot.
let r = uf2_flash_to_mount("app.uf2", "E:\\", 30000, 100);
if r.is_ok {
  if r.value.status == UF2_FLASH_SKIP { io.println("no board mounted"); }
  elif r.value.status == UF2_FLASH_COMPLETE { io.println("flashed + rebooted"); }
  else { io.println("copied; volume still mounted"); }
}
```

## Format API

| Function | Returns | Description |
|---|---|---|
| `uf2_block_build(&payload, addr, block_no, num_blocks, family_id)` | `Result[Vec[UInt8], Uf2Error]` | One 512-byte block; FAMILY_ID set when family_id != 0. |
| `uf2_block_build_with_flags(flags, &payload, addr, block_no, num_blocks, field)` | `Result[Vec[UInt8], Uf2Error]` | Explicit flags (comment/file-container/MD5). |
| `uf2_block_parse(&bytes)` | `Result[Uf2Block, Uf2Error]` | Parse one block. |
| `uf2_block_parse_at(&data, offset)` | `Result[Uf2Block, Uf2Error]` | Parse the block at an offset. |
| `uf2_block_validate(&bytes)` | `Result[Unit, Uf2Error]` | Validate one block. |
| `uf2_block_is_uf2(&bytes)` | `Bool` | Upstream `is_uf2` rule (first two magics). |
| `uf2_image_build(&payload, addr, family_id)` | `Result[Vec[UInt8], Uf2Error]` | 256-byte chunks (upstream converter default). |
| `uf2_image_build_chunked(&payload, addr, family_id, chunk)` | `Result[Vec[UInt8], Uf2Error]` | Chunk size 1..476; last block carries the remainder. |
| `uf2_image_parse(&data)` | `Result[Uf2Image, Uf2Error]` | Full validation + payload reconstruction. |
| `uf2_image_validate(&data)` | `Result[Unit, Uf2Error]` | Parse-only validation. |
| `uf2_image_payload(&data)` | `Result[Vec[UInt8], Uf2Error]` | Payload with comment blocks excluded. |

`Uf2Block` exposes every header field plus `has_family`, `no_flash`,
`file_container`, `has_md5`, `has_extension_tags` and the payload bytes.
`Uf2Image` adds `payload`, `data_bytes`, `target_addr`, `contiguous` and
`file_container`.

## Validation

Rejected with a typed `Uf2Error`: length not 512 / file not a positive
multiple of 512; either start magic or the end magic wrong; unknown flag
bits; FAMILY_ID + MD5_CHKSUM together; payload > 476; `blockNo >=
numBlocks`; `numBlocks == 0`; inconsistent `numBlocks`; duplicate or
missing block numbers; address + payload overflowing u32; mixed family
presence/value across non-comment blocks.  File order may differ from block
order (block numbers are normalized on parse).

Comment blocks (`NOFLASH`) are counted but excluded from the image payload;
`FILECONTAINER` addresses are accepted and reported as non-contiguous.

## Flashing

| Function | Description |
|---|---|
| `uf2_mount_present(path)` | Directory exists (volume present). |
| `uf2_mount_is_bootsel(path)` | Directory contains `INFO_UF2.TXT` (optional strict probe). |
| `uf2_basename(path)` | File name after the last `\` or `/`. |
| `uf2_flash_wait_complete(dest, mount, timeout_ms, poll_ms)` | COMPLETE when dest/mount disappears; COPIED after timeout. |
| `uf2_flash_to_mount(source, mount, timeout_ms, poll_ms)` | Read + validate + binary copy + read-back verify + completion wait. |

Statuses: `UF2_FLASH_SKIP` (no mount/volume; not an error),
`UF2_FLASH_COMPLETE` (volume/file disappeared -- the board rebooted),
`UF2_FLASH_COPIED` (verified, but the volume was still mounted when the
wait expired).

The copy uses binary `fs_write`; `fs_copy` is deliberately not used because
it is text-mode and would corrupt firmware bytes.  The written file is read
back and compared byte-for-byte before completion detection.

## Errors and SKIP

`Uf2Error.kind` is one of `UF2_ERR_ARG`, `SIZE`, `MAGIC`, `PAYLOAD`,
`INDEX`, `FLAGS`, `FAMILY`, `IO`, `MOUNT`, `VERIFY` (see `SPEC.md` sec. 6);
`uf2_error_kind_name` maps them.  An absent mount is **not** an error: the
flash returns `Ok` with `status = UF2_FLASH_SKIP`, so fleet hosts without a
board stay green.

## Tests

`scripts/port.ps1 -Package xiom.uf2 -TimeoutSec 300` -- 58 checks:
synthetic block goldens, every structural rejection, 256/476-byte image
roundtrips, out-of-order and no-flash/file-container images, catalogs,
basename/mount probes, flash SKIP and typed source errors, a real binary
copy to a temp "mount" with read-back verification, and completion-wait
states.  No real BOOTSEL hardware is required.
