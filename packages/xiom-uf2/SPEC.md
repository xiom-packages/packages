# xiom.uf2 -- format and flashing specification

> **Package:** `xiom.uf2` 0.1.0
> **Scope:** host-side, pure-XIOM UF2 codec and BOOTSEL-mount flashing.
> **Upstream format:** microsoft/uf2, commit
> `90e9741f217f5a40c98ba74d663e408041037578` (MIT); see `PROVENANCE.md`.
> **Compiler pin:** v0.64.7.

## 1. What this package does

`xiom.uf2` implements the structural half of the UF2 (USB Flashing Format)
ecosystem:

1. **Block codec** -- validate, decode and build one 512-byte UF2 block.
2. **Image codec** -- build a complete UF2 file from a byte image and
   validate/parse a complete file back into ordered blocks and concatenated
   payload.
3. **Host flashing** -- detect a mounted BOOTSEL volume through
   `INFO_UF2.TXT`, validate the image, copy the UF2 file to the volume,
   verify the copied size, and poll for the volume's disappearance (the
   bootloader reboot signal). A missing volume is a typed **SKIP**, never
   an error.

The package does not talk to USB, does not enumerate devices, does not
reset a board, and does not execute a bootloader protocol beyond the MSC
"copy a file to the mounted volume" contract. It is pure XIOM built on the
stdlib `xiom.io.fs` and `xiom.time` modules.

## 2. Block layout

All multi-byte fields are unsigned 32-bit little-endian integers.

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0 | 4 | `magicStart0` | `0x0A324655` (`"UF2\n"`) |
| 4 | 4 | `magicStart1` | `0x9E5D5157` |
| 8 | 4 | `flags` | flag word, see section 3 |
| 12 | 4 | `targetAddr` | flash address where the payload is written |
| 16 | 4 | `payloadSize` | number of payload bytes (`0..476`) |
| 20 | 4 | `blockNo` | sequential block number, starts at 0 |
| 24 | 4 | `numBlocks` | total blocks in the file (`>= 1`) |
| 28 | 4 | `fileSize` / `familyID` | family ID when `flags & 0x2000`, else legacy file size |
| 32 | 476 | `data` | payload, zero-padded by producers |
| 508 | 4 | `magicEnd` | `0x0AB16F30` |

`UF2_BLOCK_SIZE = 512`, `UF2_HEADER_SIZE = 32`, `UF2_PAYLOAD_MAX = 476`,
`UF2_DEFAULT_PAYLOAD_SIZE = 256`.

`Uf2Block` exposes `flags`, `target_address`, `payload_size`, `block_no`,
`num_blocks`, `family_id` (the raw word 7), `family_id_present` and
`payload` (exactly `payload_size` bytes; padding is not copied). It is an
implementation detail that the eighth word is also called `fileSize` in
legacy files: the parser never interprets it as a size.

## 3. Flags

| Constant | Value | Upstream meaning |
|---|---|---|
| `UF2_FLAG_NOT_MAIN_FLASH` | `0x00000001` | comment block; skip when flashing |
| `UF2_FLAG_FILE_CONTAINER` | `0x00001000` | block belongs to a file container |
| `UF2_FLAG_FAMILY_ID` | `0x00002000` | word 7 holds a board family ID |
| `UF2_FLAG_MD5` | `0x00004000` | last 24 payload bytes hold an MD5 record |
| `UF2_FLAG_EXTENSION_TAGS` | `0x00008000` | extension tags follow the payload |
| `UF2_FLAG_ALL` | `0x0000F001` | union of the five defined bits |

The codec decodes all five bits and **accepts unknown flag bits** (the
format is extensible). `uf2_flags_have(flags, bit)` and
`uf2_block_has_flag(block, bit)` test a power-of-two bit with
division/modulo, so a sign-bit-set flag word (up to `0xFFFFFFFF`) is safe.
The codec does not filter `NOT_MAIN_FLASH` blocks, does not verify MD5
records and does not decode extension tags (see section 9).

## 4. Family IDs

Pinned from `utils/uf2families.json` at the upstream commit in
`PROVENANCE.md`. The table order is the public ABI of
`uf2_family_table` / `uf2_family_id_at` / `uf2_family_name_at`.

| Index | Constant | ID | `uf2_family_name` |
|---|---|---|---|
| 0 | `UF2_FAMILY_RP2040` | `0xE48BFF56` | `RP2040` |
| 1 | `UF2_FAMILY_RP2350_ARM_S` | `0xE48BFF59` | `RP2350_ARM_S` |
| 2 | `UF2_FAMILY_RP2350_RISCV` | `0xE48BFF5A` | `RP2350_RISCV` |
| 3 | `UF2_FAMILY_RP2350_ARM_NS` | `0xE48BFF5B` | `RP2350_ARM_NS` |
| 4 | `UF2_FAMILY_SAMD21` | `0x68ED2B88` | `SAMD21` |
| 5 | `UF2_FAMILY_SAMD51` | `0x55114460` | `SAMD51` |

`uf2_family_name(id)` returns `"unknown"` for any ID outside the subset;
`uf2_family_known(id)` is the membership test. Unknown IDs are never an
error: a bootloader family may be newer than this package.

## 5. Block validation and errors

`uf2_block_parse(data)` requires exactly 512 bytes and delegates to
`uf2_block_parse_at(data, 0)`. `uf2_block_parse_at` accepts any
non-negative offset whose block fits in the buffer.

Validation order (first failure wins):

1. buffer length (block) or `offset + 512 > data.len()` -> `UF2_ERR_BLOCK_SIZE`
2. word 0 -> `UF2_ERR_MAGIC_START0`
3. word 1 -> `UF2_ERR_MAGIC_START1`
4. word 508 -> `UF2_ERR_MAGIC_END`
5. `payloadSize > 476` -> `UF2_ERR_PAYLOAD_SIZE`
6. `numBlocks == 0` -> `UF2_ERR_BLOCK_COUNT`
7. `blockNo >= numBlocks` -> `UF2_ERR_BLOCK_NUMBER`

A block with `payloadSize == 0` is structurally valid. Alignment of
`targetAddr` and `payloadSize` is a producer rule (section 6), not a parse
rule, because the upstream text says "should", not "must".

Error shape:

```xi
pub type Uf2Error = { code: Int; offset: Int; message: Str; }
```

`offset` is the absolute byte position of the offending field in the input
buffer; `-1` for scalar-argument and host-I/O errors. Messages are stable
lowercase `uf2:` strings. `Err` never carries a partially decoded block.

| Code | Constant | Message(s) |
|---|---|---|
| 1 | `UF2_ERR_BLOCK_SIZE` | `uf2: block size`, `uf2: image size` |
| 2 | `UF2_ERR_MAGIC_START0` | `uf2: bad start magic 0` |
| 3 | `UF2_ERR_MAGIC_START1` | `uf2: bad start magic 1` |
| 4 | `UF2_ERR_MAGIC_END` | `uf2: bad end magic` |
| 5 | `UF2_ERR_PAYLOAD_SIZE` | `uf2: payload size out of range`, `uf2: payload size not aligned` |
| 6 | `UF2_ERR_BLOCK_NUMBER` | `uf2: block number out of range` |
| 7 | `UF2_ERR_BLOCK_COUNT` | `uf2: block count is zero`, `uf2: block count out of range`, `uf2: block count mismatch` |
| 8 | `UF2_ERR_FAMILY_ID` | `uf2: family id out of range`, `uf2: inconsistent family id` |
| 9 | `UF2_ERR_IMAGE_EMPTY` | `uf2: empty image` |
| 10 | `UF2_ERR_MISSING_BLOCK` | `uf2: missing block` (defensive invariant; see below) |
| 11 | `UF2_ERR_DUPLICATE_BLOCK` | `uf2: duplicate block` |
| 12 | `UF2_ERR_ADDRESS` | `uf2: address out of range`, `uf2: address overflow` |
| 13 | `UF2_ERR_FLAGS` | `uf2: flags out of range` |
| 20 | `UF2_ERR_MOUNT` | `uf2: empty mount path` |
| 21 | `UF2_ERR_FILENAME` | `uf2: invalid filename` |
| 22 | `UF2_ERR_ARGUMENT` | `uf2: negative offset`, `uf2: negative timeout`, `uf2: invalid poll interval` |
| 23 | `UF2_ERR_IO` | `uf2: write failed: ...`, `uf2: stat failed: ...`, `uf2: short write` |

`UF2_ERR_MISSING_BLOCK` cannot be reached for a buffer that passes the
image rules: the image parser requires `numBlocks == block count` and
rejects duplicates, so `n` distinct block numbers in `0..n-1` always cover
the range. The check is kept as a defensive invariant and is documented
rather than silently omitted.

## 6. Block builder

`uf2_block_build(address, payload, block_no, num_blocks, family_id, flags)`
validates, in order: `flags` in `0..2^32-1` (`UF2_ERR_FLAGS`, offset 8),
`address` in `0..2^32-1` (`UF2_ERR_ADDRESS`, offset 12), payload length
`<= 476` (`UF2_ERR_PAYLOAD_SIZE`, offset 16), `num_blocks` in
`1..2^32-1` (`UF2_ERR_BLOCK_COUNT`, offset 24), `block_no` in
`0..num_blocks-1` (`UF2_ERR_BLOCK_NUMBER`, offset 20), `family_id` in
`0..2^32-1` (`UF2_ERR_FAMILY_ID`, offset 28).

The output is always 512 bytes: header, payload, zero padding to offset
508, end magic. `uf2_block_build_family` is the same call with
`flags = UF2_FLAG_FAMILY_ID`.

`uf2_block_parse` followed by `uf2_block_build` reproduces the input bytes
exactly for a canonical block (the suite pins this against a synthetic
fixture).

## 7. Image builder

`uf2_image_build(base_address, data, family_id)` uses
`UF2_DEFAULT_PAYLOAD_SIZE = 256`.
`uf2_image_build_ex(base_address, data, payload_size, family_id)` allows
any `payload_size` in `4..476` that is a multiple of 4.

Rules:

* empty `data` -> `UF2_ERR_IMAGE_EMPTY`;
* `payload_size` outside `4..476` -> `UF2_ERR_PAYLOAD_SIZE` (offset 16);
* `payload_size % 4 != 0` -> `UF2_ERR_PAYLOAD_SIZE` with
  `uf2: payload size not aligned`;
* `base_address` outside `0..2^32-1` -> `UF2_ERR_ADDRESS` (offset 12);
* `base_address + (n-1) * payload_size > 2^32-1` -> `UF2_ERR_ADDRESS`
  with `uf2: address overflow`;
* `family_id` outside `0..2^32-1` -> `UF2_ERR_FAMILY_ID` (offset 28);
* `n = ceil(data.len() / payload_size)`;
* block `i` starts at `base_address + i * payload_size` and carries
  `payload_size` bytes; the final block is zero-padded to `payload_size`;
* `family_id != 0` sets `UF2_FLAG_FAMILY_ID`; `family_id == 0` leaves the
  flag clear (legacy/no-family image);
* every block reports `numBlocks = n` and `blockNo = i`.

The output length is exactly `n * 512`. Padding the final block (rather
than emitting a short final payload) matches the upstream `uf2conv`
behavior and keeps every block uniform.

## 8. Image parser

`uf2_image_parse(data)` validates, in order:

1. non-empty -> `UF2_ERR_IMAGE_EMPTY`;
2. length multiple of 512 -> `UF2_ERR_BLOCK_SIZE` (`uf2: image size`);
3. each 512-byte block in file order through `uf2_block_parse_at`
   (propagating its code, offset and message);
4. `numBlocks` of every block equals the actual block count `n`
   -> `UF2_ERR_BLOCK_COUNT` (`uf2: block count mismatch`, offset block+24);
5. family presence and value agree across all blocks
   -> `UF2_ERR_FAMILY_ID` (`uf2: inconsistent family id`, offset block+28);
6. no duplicate `blockNo` -> `UF2_ERR_DUPLICATE_BLOCK`
   (offset file position+20);
7. every slot `0..n-1` is filled (defensive; section 5).

The result orders blocks by `blockNo` (file order is irrelevant -- the
format is designed for out-of-order MSC writes) and concatenates payloads
in that order. `Uf2Image` carries `blocks`, `data`, `block_count`,
`family_id`, `family_id_present`, `base_address` (block 0's target) and
`payload_bytes` (sum of payload sizes, including final-block padding).

Concatenated UF2 files with different family IDs (an upstream-supported
scenario) are **not** accepted by `uf2_image_parse`; they would need a
future multi-image splitter. A file with one family ID is the supported
case.

## 9. Host flashing to a BOOTSEL volume

### Detection

A directory is treated as a UF2 volume when it exists and contains
`INFO_UF2.TXT` (or lower-case `info_uf2.txt`), the upstream detection
rule. `INDEX.HTM`, `CURRENT.UF2` and directory names are not used for
detection. The probe is `fs.fs_is_dir` + `fs.fs_exists`; no device API is
involved. FAT volumes are case-insensitive, so either capitalization is
accepted.

### Plan

`uf2_flash_plan(mount, image, filename)` validates the mount is non-empty,
`filename` is a safe plain name, and the image parses. It then computes:

* `target_path = uf2_mount_join(mount, filename)`;
* `volume_present = uf2_volume_present(mount)`;
* `block_count`, `bytes` (UF2 file size), family fields.

A missing volume is **not** an error at plan time. This is what makes the
whole path SKIP-safe on CI hosts with no board.

### Copy

`uf2_flash_to_mount(mount, image, filename)`:

1. plans as above (typed errors for bad input);
2. if no volume -> `Ok` with `status = UF2_FLASH_SKIPPED`,
   `bytes_written = 0`, `volume_present = false`; nothing is written;
3. otherwise writes the image with `fs.fs_write` (binary truncate);
4. verifies the copied size with `fs.fs_size`; any write or size mismatch
   is `UF2_ERR_IO`;
5. probes the volume again:
   * disappeared -> `UF2_FLASH_DONE` (the bootloader consumed the file and
     rebooted);
   * still present -> `UF2_FLASH_COPIED` (the caller may wait).

### Completion detection

`uf2_flash_wait(mount, timeout_ms, poll_ms)` polls
`uf2_volume_present` until it becomes false. A volume that is already
absent at entry counts as completed immediately (the normal state after a
successful flash). Timeout is **not** an error: it returns
`completed = false`, `volume_present = true`, the elapsed `waited_ms` and
the number of `polls`. `timeout_ms` must be `>= 0` and `poll_ms > 0`.
The loop is bounded by `timeout_ms / poll_ms + 2` probes and sleeps
`min(poll_ms, remaining)` between probes.

`uf2_flash_status_name(status)` maps `DONE`/`COPIED`/`SKIPPED` to
`"done"`/`"copied"`/`"skipped"`.

### File-name and join rules

`uf2_filename_valid(name)`: 1..255 bytes, no `/` or `\`, not `.` or `..`.
`uf2_mount_join(mount, name)` appends `/` unless `mount` already ends in
`/` or `\`; an empty mount returns the file name unchanged. This handles
drive roots (`E:` -> `E:/f.uf2`), POSIX mounts (`/media/x` ->
`/media/x/f.uf2`) and Windows paths with either separator.

## 10. Test plan (20 checks)

| Check | Pins |
|---|---|
| t1 | magic words, geometry, five flags and six family IDs |
| t2 | pinned 512-byte fixture decodes every field and drops padding |
| t3 | short/long buffers, three magic words and parse offsets |
| t4 | payload-size and block-number/count boundaries |
| t5 | block build canonical bytes and parse-back |
| t6 | every builder range error and its offset |
| t7 | 700-byte image -> 3 blocks -> parse -> rebuild byte-identical; reversed file order |
| t8 | payload sizes 128 and 476; unaligned/oversized rejection |
| t9 | image builder empty input, bad base address and family ID |
| t10 | image size must be non-zero and a multiple of 512 |
| t11 | count mismatch, duplicate block, mixed family ID |
| t12 | documented family table, names and membership |
| t13 | flag-bit helpers including sign-bit-set words |
| t14 | no-volume plan and flash are a typed SKIP |
| t15 | mount/filename/image validation before any write |
| t16 | mount join rules for all separator shapes |
| t17 | synthetic BOOTSEL volume: detect, plan, copy, size, readback, timeout wait |
| t18 | wait completion on an absent volume and argument errors |
| t19 | pinned fixture parse -> build is byte-identical |
| t20 | aligned payload sizes 4..476 roundtrip exact image data |

The synthetic volume in t17 is a temp directory containing
`INFO_UF2.TXT`; no real board or mount is required. A real mount is
optional and never assumed.

## 11. Non-goals and limitations

* No MD5 verification (`UF2_FLAG_MD5`) and no extension-tag decoding
  (`UF2_FLAG_EXTENSION_TAGS`); the flags are exposed.
* No file-container writing (`UF2_FLAG_FILE_CONTAINER`); the flag is
  exposed and blocks still parse.
* No filtering of `NOT_MAIN_FLASH` comment blocks during flashing: this
  package copies a file, it does not program flash.
* No concatenated multi-family image splitting.
* No USB enumeration, reset, picotool/dfu-util orchestration or device
  verification beyond the copied file size and volume disappearance.
* No assumption that a mounted volume is a board: detection requires
  `INFO_UF2.TXT`.
* Payload sizes above 476 are impossible by the block layout; payload
  sizes are not required to match the target page size (the bootloader
  buffers when needed).
* Host filesystem semantics are the stdlib's: no fsync, no atomic rename,
  no removable-media lock. A user removing the volume early can produce an
  I/O error rather than a completed flash.
