# xiom.uf2 -- SPEC (declared surface, 0.1.0)

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

This document is the contract for **xiom.uf2 0.1.0**: the UF2 block/image
format (build, parse, validate, roundtrip) and host-side flashing to a
mounted BOOTSEL volume.  "100% of the declared set" is the lane's
done-definition.  The upstream oracle is **microsoft/uf2** at pin
`90e9741f217f5a40c98ba74d663e408041037578` (MIT), consulted reference-only
(see PROVENANCE.md).

Module: `xiom.uf2` (single module, `src/uf2.xi`).  Imports:
`xiom.io`, `xiom.io.fs`, `xiom.serialize.endian`, `xiom.string`,
`xiom.string.compare`.  Platform dep: `xiom.std`.  No C, no vendored
upstream code, no runtime data files.

## 1. Constants

| Constant | Value | Meaning |
|---|---|---|
| `UF2_BLOCK_SIZE` | 512 | Bytes per block. |
| `UF2_HEADER_SIZE` | 32 | Fixed header before the payload. |
| `UF2_MAX_PAYLOAD` | 476 | 512 - 32 header - 4 end magic. |
| `UF2_MAGIC_START0` | 171066965 (`0x0A324655`) | First start magic ("UF2\n"). |
| `UF2_MAGIC_START1` | 2656915799 (`0x9E5D5157`) | Second start magic. |
| `UF2_MAGIC_END` | 179400496 (`0x0AB16F30`) | End magic at offset 508. |
| `UF2_U32_MAX` | 4294967295 | Largest 32-bit field value. |
| `UF2_FLAG_NOFLASH` | 1 (`0x00000001`) | Comment/not-main-flash block; excluded from payload. |
| `UF2_FLAG_FILECONTAINER` | 4096 (`0x00001000`) | File-container block (addresses arbitrary). |
| `UF2_FLAG_FAMILY_ID` | 8192 (`0x00002000`) | The 8th field is a family ID. |
| `UF2_FLAG_MD5_CHKSUM` | 16384 (`0x00004000`) | The 8th field is an MD5 checksum. |
| `UF2_FLAG_EXTENSION_TAGS` | 32768 (`0x00008000`) | Extension tags present. |
| `UF2_FLAG_KNOWN_MASK` | 61441 (`0x0000F001`) | All defined flag bits; reserved bits are rejected. |
| `UF2_INFO_FILE` | `"INFO_UF2.TXT"` | BOOTSEL volume info file probed by `uf2_mount_is_bootsel`. |
| `UF2_FLASH_SKIP` | 0 | No mount/volume -> SKIP. |
| `UF2_FLASH_COMPLETE` | 1 | Volume/file disappeared -> board rebooted. |
| `UF2_FLASH_COPIED` | 2 | Copy verified, volume still mounted when the wait expired. |

## 2. Family IDs

Source: upstream `utils/uf2families.json` at the pin (verbatim values).

| Constant | Short name | Value | Decimal |
|---|---|---|---|
| `UF2_FAMILY_RP2040` | RP2040 | `0xe48bff56` | 3834380118 |
| `UF2_FAMILY_RP2XXX_ABSOLUTE` | RP2XXX_ABSOLUTE | `0xe48bff57` | 3834380119 |
| `UF2_FAMILY_RP2XXX_DATA` | RP2XXX_DATA | `0xe48bff58` | 3834380120 |
| `UF2_FAMILY_RP2350_ARM_S` | RP2350_ARM_S | `0xe48bff59` | 3834380121 |
| `UF2_FAMILY_RP2350_RISCV` | RP2350_RISCV | `0xe48bff5a` | 3834380122 |
| `UF2_FAMILY_RP2350_ARM_NS` | RP2350_ARM_NS | `0xe48bff5b` | 3834380123 |
| `UF2_FAMILY_SAMD21` | SAMD21 | `0x68ed2b88` | 1760373640 |
| `UF2_FAMILY_SAMD51` | SAMD51 | `0x55114460` | 1427194976 |

`uf2_family_name` resolves exactly these eight IDs; any other value returns
`"unknown"`.  The table is data, not logic: adding a family is an additive
constant + catalog arm.

## 3. Block layout (all fields little-endian u32)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | `magicStart0` | Must equal `UF2_MAGIC_START0`. |
| 4 | 4 | `magicStart1` | Must equal `UF2_MAGIC_START1`. |
| 8 | 4 | `flags` | Known bits only; FAMILY_ID and MD5_CHKSUM are mutually exclusive. |
| 12 | 4 | `targetAddr` | Flash destination (family-relative on RP2040/RP2350). |
| 16 | 4 | `payloadSize` | 0..476; only these bytes are data. |
| 20 | 4 | `blockNo` | 0..numBlocks-1. |
| 24 | 4 | `numBlocks` | Total blocks in the file (>= 1). |
| 28 | 4 | `familyID` / fileSize / MD5 | Family ID when FAMILY_ID is set; MD5 when MD5_CHKSUM is set. |
| 32 | 476 | data | Payload; bytes beyond `payloadSize` are zero padding in our builder. |
| 508 | 4 | `magicEnd` | Must equal `UF2_MAGIC_END`. |

## 4. Public types

| Type | Fields | Meaning |
|---|---|---|
| `Uf2Error` | `kind`, `message` | Typed failure; `kind` is one of the constants in sec. 6. |
| `Uf2Block` | `flags`, `target_addr`, `payload_size`, `block_no`, `num_blocks`, `family_id`, `has_family`, `no_flash`, `file_container`, `has_md5`, `has_extension_tags`, `payload` | One parsed block; `family_id` is raw unless `has_family`. |
| `Uf2Image` | `blocks`, `num_blocks`, `family_id`, `has_family`, `payload`, `data_bytes`, `target_addr`, `contiguous`, `file_container` | Validated image. `blocks` keep file order; `payload` is reconstructed in block-number order from non-comment blocks. |
| `Uf2FlashResult` | `status`, `source_path`, `dest_path`, `source_bytes`, `copied_bytes`, `blocks`, `verified`, `elapsed_ms`, `detail` | Flash outcome; `status` is SKIP/COMPLETE/COPIED. |

## 5. Functions

### 5.1 Block

| Function | Returns | Behavior |
|---|---|---|
| `uf2_block_build(&payload, target_addr, block_no, num_blocks, family_id)` | `Result[Vec[UInt8], Uf2Error]` | Build one 512-byte block; sets FAMILY_ID automatically when `family_id != 0`. |
| `uf2_block_build_with_flags(flags, &payload, target_addr, block_no, num_blocks, family_field)` | `Result[Vec[UInt8], Uf2Error]` | Explicit flags/raw field (comment, file container, MD5 field). |
| `uf2_block_parse(&bytes)` | `Result[Uf2Block, Uf2Error]` | Parse one block; requires >= 512 bytes (extras ignored). |
| `uf2_block_parse_at(&data, offset)` | `Result[Uf2Block, Uf2Error]` | Parse the 512-byte block at `offset`. |
| `uf2_block_validate(&bytes)` | `Result[Unit, Uf2Error]` | Parse-only validation. |
| `uf2_block_is_uf2(&bytes)` | `Bool` | Both start magics present in the first 8 bytes (upstream `is_uf2`). |

### 5.2 Image

| Function | Returns | Behavior |
|---|---|---|
| `uf2_image_build(&payload, target_addr, family_id)` | `Result[Vec[UInt8], Uf2Error]` | Split into 256-byte blocks (upstream converter default). |
| `uf2_image_build_chunked(&payload, target_addr, family_id, chunk_size)` | `Result[Vec[UInt8], Uf2Error]` | Split into blocks of 1..476 bytes; the last block carries the remainder. |
| `uf2_image_parse(&data)` | `Result[Uf2Image, Uf2Error]` | Full structural validation + payload reconstruction (sec. 7). |
| `uf2_image_validate(&data)` | `Result[Unit, Uf2Error]` | Parse-only validation. |
| `uf2_image_payload(&data)` | `Result[Vec[UInt8], Uf2Error]` | Validated image payload (comments excluded). |

### 5.3 Catalogs

`uf2_family_name(id)`, `uf2_flags_name(flags)`, `uf2_error_kind_name(kind)`,
`uf2_flash_status_name(status)` -- deterministic strings; unknown inputs
return `"unknown"` (flags: `"NONE"` for 0, `"RESERVED"` for undefined bits).

### 5.4 Flashing

| Function | Returns | Behavior |
|---|---|---|
| `uf2_mount_present(mount_dir)` | `Bool` | Directory exists (volume present). |
| `uf2_mount_is_bootsel(mount_dir)` | `Bool` | Directory contains `INFO_UF2.TXT`. |
| `uf2_basename(path)` | `Str` | File name after the last `\` or `/` (empty for trailing separator). |
| `uf2_flash_wait_complete(dest_path, mount_dir, timeout_ms, poll_ms)` | `Result[Int, Uf2Error]` | COMPLETE when dest/mount disappears, else COPIED after the timeout; timeout 0 -> immediate COPIED. |
| `uf2_flash_to_mount(source_path, mount_dir, timeout_ms, poll_ms)` | `Result[Uf2FlashResult, Uf2Error]` | Full flash path (sec. 8). |

## 6. Error kinds

| Constant | Value | Raised when |
|---|---|---|
| `UF2_ERR_ARG` | 1 | Empty path, negative timeout, poll 0 with a nonzero timeout, bad chunk size, address/family overflow, or an empty image payload. |
| `UF2_ERR_SIZE` | 2 | Block shorter than 512; image empty or not a multiple of 512; source size not a multiple of 512. |
| `UF2_ERR_MAGIC` | 3 | Start magic 0/1 or end magic mismatch. |
| `UF2_ERR_PAYLOAD` | 4 | `payloadSize > 476`. |
| `UF2_ERR_INDEX` | 5 | `numBlocks == 0`, `blockNo >= numBlocks`, inconsistent `numBlocks`, duplicate or missing block number. |
| `UF2_ERR_FLAGS` | 6 | Reserved flag bits set, or FAMILY_ID and MD5_CHKSUM together. |
| `UF2_ERR_FAMILY` | 7 | Non-comment blocks disagree on family presence or value. |
| `UF2_ERR_IO` | 8 | Source read or destination write failure. |
| `UF2_ERR_MOUNT` | 9 | Reserved for explicit mount validation (public flash reports an absent mount as SKIP). |
| `UF2_ERR_VERIFY` | 10 | Written size or read-back bytes differ from the source. |

Public entry points never panic on caller input: validation returns
`Err(Uf2Error)` or the SKIP result before touching the filesystem.

## 7. Validation rules (`uf2_image_parse`)

1. File length is positive and a multiple of 512.
2. Every block passes the block rules: length, start/end magics, known
   flags, flag exclusivity, payload <= 476, `numBlocks >= 1`,
   `blockNo < numBlocks`, and `targetAddr + payloadSize <= 0xFFFFFFFF`.
3. Every block declares `numBlocks` equal to the file's block count.
4. Block numbers form a complete permutation of `0..n-1`; file order may
   differ (the OS may write blocks out of order).
5. Every non-NOFLASH block agrees on family presence and, when present, on
   family ID.  Mixed-family files are rejected (the bootloader may accept
   concatenated families; this host-side validator deliberately does not).
6. `payload` concatenates non-NOFLASH blocks in block-number order;
   `data_bytes` is the sum of their `payloadSize`; `target_addr` is the
   first flashing block's address; `contiguous` is true when each flashing
   block starts exactly where the previous one ended.

Padding bytes between the payload and offset 508 are **not** required to be
zero by the parser (the upstream reader ignores them); our builder writes
zeros.

## 8. Flash semantics (`uf2_flash_to_mount`)

1. Argument validation (`ARG`) happens first.
2. If `mount_dir` is not an existing directory, return `Ok` with
   `status = UF2_FLASH_SKIP` and `detail = "no mount/volume present"`.
   No source read is attempted (deterministic SKIP).
3. Read the source as binary (`fs_size` + `fs_read_range`), require a
   positive multiple of 512 (`SIZE`), and parse it (`uf2_image_parse`; its
   typed error is propagated with a `flash: source invalid:` prefix).
4. Destination is `<mount_dir>/<basename(source)>`.
5. Write with `fs_write` (binary `wb`).  `fs_copy` is deliberately NOT used:
   it is text-mode and would corrupt binary data.
6. Read the destination back (`fs_size` + `fs_read_range`) and compare size
   and every byte; a mismatch is `VERIFY`.  The board may reset as soon as
   the file is closed, so if the destination or the mount disappears during
   verification the result is COMPLETE with `verified = false` (the
   disappearance is the completion signal, not a write failure).
7. Completion detection: poll `fs_exists(dest)` and `fs_is_dir(mount_dir)`
   every `poll_ms`; COMPLETE when either disappears (the bootloader reboots
   when the last block lands).  If the volume is still mounted when
   `timeout_ms` expires, report COPIED (the image was written and verified).
8. `elapsed_ms` spans the copy + verification + wait.

A real BOOTSEL volume is not required by the suite; absent mounts exercise
the SKIP path and temp directories exercise the copy/verify/completion
paths.  `uf2_mount_is_bootsel` is the optional strict probe for callers that
want to require `INFO_UF2.TXT`.

## 9. Deliberate deviations / limits

- **Last-block payload**: our builder declares the actual remainder in the
  last block; the upstream converter declares 256 and zero-pads.  Both are
  spec-legal (README "Payload sizes"); our form round-trips exactly.
- **Reserved flag bits** are rejected; the spec defines only the five bits
  above.
- **Mixed-family files** are rejected rather than treated as concatenated
  images.
- **MD5 checksums** are decoded into `family_id` + `has_md5` but not
  verified in 0.1.0 (ROADMAP).
- **Extension tags** are decoded as a flag but not parsed; the payload is
  kept opaque.
- **No volume auto-discovery**: the caller supplies the mount path.  This
  keeps the module host-OS-neutral.
- **No picotool orchestration** in 0.1.0 (ROADMAP).
