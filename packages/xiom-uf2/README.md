# xiom.uf2

> **Status:** `incubating` -- conformance-tested (20/20 on v0.64.7).
> **Scope:** host-side, pure-XIOM USB Flashing Format (UF2) codec and
> BOOTSEL-mount flashing. No vendored runtime, no USB/device APIs.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (`xiom.io.fs` + `xiom.time`).
> Tests additionally use `xiom.io`, `xiom.test`, `xiom.encoding.hex`,
> `xiom.string.compare` and `xiom.convert.int`.

## What it is

`xiom.uf2` parses, validates and builds the UF2 format used by Microsoft
MakeCode and MCU bootloaders (RP2040/RP2350 BOOTSEL, SAMD21, SAMD51), and
copies a valid image to a mounted BOOTSEL volume:

- **Blocks** -- decode one 512-byte block (three magic words, flags,
  target address, payload size, block number/count, family-ID field, end
  magic), build a canonical block, and detect the five defined flags.
- **Images** -- split a byte image into blocks at a chosen payload size
  (256 by default, any multiple of 4 up to 476), build a complete UF2
  file, and parse a file back into block-number order with block count,
  duplicate, family-ID, magic and size validation.
- **Families** -- a pinned subset: RP2040, RP2350 secure Arm / RISC-V /
  non-secure Arm, SAMD21 and SAMD51; unknown IDs decode as `"unknown"`.
- **Flashing** -- plan and copy a UF2 file to a mounted volume detected by
  `INFO_UF2.TXT`, verify the copied size, and poll until the volume
  disappears (the bootloader reboot signal). A missing volume is a typed
  **SKIP**, not an error.

The format reference is microsoft/uf2 at commit
`90e9741f217f5a40c98ba74d663e408041037578` (MIT). Nothing is vendored;
see `PROVENANCE.md` and `SPEC.md`.

## Install / use

```
xiom pkg install xiom.uf2       # consumer
xiom pkg publish                # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.uf2;

// Build a 3-block UF2 file for an RP2040 from a 700-byte image.
let data = Vec[UInt8].new();
// ... fill data ...
let r = uf2_image_build(0x10000000, &data, UF2_FAMILY_RP2040);
if r.is_ok {
  let uf2: Vec[UInt8] = r.value;

  // Validate and inspect it.
  let pr = uf2_image_parse(&uf2);
  if pr.is_ok {
    let img: Uf2Image = pr.value;
    // img.block_count == 3, img.family_id == UF2_FAMILY_RP2040
    // img.blocks[i].target_address == 0x10000000 + i * 256
  }
}

// Flash to a mounted BOOTSEL volume. No volume -> typed SKIP.
let out = uf2_flash_to_mount("E:", &uf2, "firmware.uf2");
if out.is_ok {
  let o: Uf2FlashOutcome = out.value;
  if o.status == UF2_FLASH_COPIED {
    let w = uf2_flash_wait("E:", 10000, 100);
    if w.is_ok {
      let wait: Uf2FlashWait = w.value;
      // wait.completed == true when the board rebooted and the volume left
    }
  }
}
```

Single blocks are just as direct:

```xi
let p = Vec[UInt8].new();
// ... fill p with up to 476 payload bytes ...
let br = uf2_block_build_family(0x10000000, &p, 0, 1, UF2_FAMILY_RP2040);
if br.is_ok {
  let block: Vec[UInt8] = br.value;
  let pr = uf2_block_parse(&block);
}
```

## API

All functions are free functions in module `xiom.uf2`.

### Constants

```xi
UF2_MAGIC_START0 = 0x0A324655      UF2_MAGIC_START1 = 0x9E5D5157
UF2_MAGIC_END    = 0x0AB16F30      UF2_BLOCK_SIZE   = 512
UF2_HEADER_SIZE  = 32              UF2_PAYLOAD_MAX  = 476
UF2_DEFAULT_PAYLOAD_SIZE = 256

UF2_FLAG_NOT_MAIN_FLASH   = 0x00000001
UF2_FLAG_FILE_CONTAINER   = 0x00001000
UF2_FLAG_FAMILY_ID        = 0x00002000
UF2_FLAG_MD5              = 0x00004000
UF2_FLAG_EXTENSION_TAGS   = 0x00008000
UF2_FLAG_ALL              = 0x0000F001

UF2_FAMILY_RP2040         = 0xE48BFF56
UF2_FAMILY_RP2350_ARM_S   = 0xE48BFF59
UF2_FAMILY_RP2350_RISCV   = 0xE48BFF5A
UF2_FAMILY_RP2350_ARM_NS  = 0xE48BFF5B
UF2_FAMILY_SAMD21         = 0x68ED2B88
UF2_FAMILY_SAMD51         = 0x55114460

UF2_FLASH_DONE = 0   UF2_FLASH_COPIED = 1   UF2_FLASH_SKIPPED = 2
```

The `UF2_ERR_*` code catalog is in `SPEC.md` section 5.

### Block codec

| Function | Returns | Description |
|---|---|---|
| `uf2_block_parse(data)` | `Result[Uf2Block, Uf2Error]` | Parse exactly one 512-byte block. |
| `uf2_block_parse_at(data, offset)` | `Result[Uf2Block, Uf2Error]` | Parse a block inside a larger buffer. |
| `uf2_block_build(address, payload, block_no, num_blocks, family_id, flags)` | `Result[Vec[UInt8], Uf2Error]` | Build canonical 512 bytes. |
| `uf2_block_build_family(address, payload, block_no, num_blocks, family_id)` | `Result[Vec[UInt8], Uf2Error]` | Same, with `UF2_FLAG_FAMILY_ID`. |
| `uf2_flags_have(flags, bit)` / `uf2_block_has_flag(block, bit)` | `Bool` | Flag-bit tests. |

### Image codec

| Function | Returns | Description |
|---|---|---|
| `uf2_image_build(base_address, data, family_id)` | `Result[Vec[UInt8], Uf2Error]` | Build with 256-byte payloads. |
| `uf2_image_build_ex(base_address, data, payload_size, family_id)` | `Result[Vec[UInt8], Uf2Error]` | Build with a chosen aligned payload size. |
| `uf2_image_parse(data)` | `Result[Uf2Image, Uf2Error]` | Validate, order by block number, concatenate payloads. |

### Family table

| Function | Returns | Description |
|---|---|---|
| `uf2_family_table()` | `Vec[Int]` | Six IDs in table order. |
| `uf2_family_count()` | `Int` | 6. |
| `uf2_family_id_at(index)` | `Int` | ID or -1. |
| `uf2_family_name_at(index)` | `Str` | Name or `"unknown"`. |
| `uf2_family_name(id)` | `Str` | Name or `"unknown"`. |
| `uf2_family_known(id)` | `Bool` | Subset membership. |

### Host flashing

| Function | Returns | Description |
|---|---|---|
| `uf2_mount_join(mount, filename)` | `Str` | Join with exactly one separator. |
| `uf2_filename_valid(filename)` | `Bool` | Safe plain file name (no separators, not `.`/`..`, 1..255 bytes). |
| `uf2_volume_present(mount)` | `Bool` | Directory + `INFO_UF2.TXT` detection. |
| `uf2_flash_plan(mount, image, filename)` | `Result[Uf2FlashPlan, Uf2Error]` | Validate and plan; missing volume is not an error. |
| `uf2_flash_to_mount(mount, image, filename)` | `Result[Uf2FlashOutcome, Uf2Error]` | SKIP / copy / size-check / completion probe. |
| `uf2_flash_wait(mount, timeout_ms, poll_ms)` | `Result[Uf2FlashWait, Uf2Error]` | Poll until the volume disappears or the timeout expires. |
| `uf2_flash_status_name(status)` | `Str` | `"done"`, `"copied"`, `"skipped"` or `"unknown"`. |

### Types

```xi
pub type Uf2Error = { code: Int; offset: Int; message: Str; }
pub type Uf2Block = {
  flags: Int; target_address: Int; payload_size: Int;
  block_no: Int; num_blocks: Int;
  family_id: Int; family_id_present: Bool;
  payload: Vec[UInt8];
}
pub type Uf2Image = {
  blocks: Vec[Uf2Block]; data: Vec[UInt8]; block_count: Int;
  family_id: Int; family_id_present: Bool;
  base_address: Int; payload_bytes: Int;
}
pub type Uf2FlashPlan = {
  mount: Str; filename: Str; target_path: Str; volume_present: Bool;
  block_count: Int; bytes: Int; family_id: Int; family_id_present: Bool;
}
pub type Uf2FlashOutcome = {
  status: Int; mount: Str; target_path: Str;
  bytes_written: Int; block_count: Int; volume_present: Bool;
}
pub type Uf2FlashWait = {
  completed: Bool; waited_ms: Int; polls: Int; volume_present: Bool;
}
```

## Error model

Every fallible function returns `Result[T, Uf2Error]` with a stable
lowercase `uf2:` message. `offset` is the absolute byte position of the
offending field, or `-1` for scalar-argument and host-I/O errors. `Err`
never carries a partially decoded block or image. Host I/O failures are
`UF2_ERR_IO` with the stdlib message appended. The full catalog, the
validation order and the builder range rules are in `SPEC.md`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.uf2 -TimeoutSec 300
```

Expected: the namespace check passes, 20 `[PASS]` lines, and a final
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

The suite is synthetic and hardware-free:

- a pinned 512-byte hex fixture (family `0xE48BFF56`, address
  `0x10000000`, 256 payload bytes) exercises every parsed field and the
  parse -> build identity;
- image tests build 700-byte and 3-byte images at payload sizes 4, 64,
  128, 256, 472 and 476, parse them back, and reverse the block order to
  prove order independence;
- error tests pin every message, code and offset (magic words, payload
  size, block count/number, count mismatch, duplicate block, mixed family,
  builder ranges, image size and empty input);
- the flash tests use a **synthetic BOOTSEL volume**: a temp directory with
  `INFO_UF2.TXT`, real file copy, size verification and byte readback;
- the no-volume path is exercised with a unique absent temp path (typed
  SKIP, nothing written).

A real board/mount is optional and never required by the suite.

## Limitations

- No MD5 verification, extension-tag decoding or file-container writing;
  those flags are exposed but not acted on.
- No concatenated multi-family image splitting.
- No USB enumeration, device reset, picotool/dfu-util orchestration or
  flash-content verification beyond copied size and volume disappearance.
- `NOT_MAIN_FLASH` comment blocks are not filtered when copying: this is a
  file copy, not a flash programmer.
- Host durability is whatever `xiom.io.fs` provides; no fsync, no atomic
  rename, no removable-media lock.
- A real mount is detected only by `INFO_UF2.TXT`, per the upstream rule.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`). The UF2 format
reference is MIT-licensed microsoft/uf2; see `PROVENANCE.md`.
