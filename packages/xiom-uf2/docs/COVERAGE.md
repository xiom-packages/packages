# COVERAGE: xiom.uf2 0.1.0 -- declared surface vs evidence

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0
>
> Policy: 100% of the declared surface (`SPEC.md` sec. 5) is implemented
> and evidenced.  Runs x2 at 58/58 on v0.64.7 (`STATUS.json`).

## 1. Format functions (11/11)

| # | Function | Suite evidence |
|---|---|---|
| 1 | `uf2_block_build` | `block-golden: 512 bytes, all header fields, zero padding, end magic`; `block-roundtrip`; every image roundtrip |
| 2 | `uf2_block_build_with_flags` | `image-noflash` (NOFLASH+FAMILY_ID), `image-container` (FILECONTAINER+FAMILY_ID), `block-build-reject: reserved flag` |
| 3 | `uf2_block_parse` | `block-roundtrip`, `block: family_id 0`, all `block-reject` cases |
| 4 | `uf2_block_parse_at` | `image-roundtrip` (block 1/2 addresses), `image-chunked` (476/224) |
| 5 | `uf2_block_validate` | exercised by the validate/rejection paths through the same parser |
| 6 | `uf2_block_is_uf2` | `is_uf2: true for valid start magics, false after corruption` |
| 7 | `uf2_image_build` | `image-roundtrip` (700 bytes -> 3 blocks), `image-noflash`, `image-container`, `validate` |
| 8 | `uf2_image_build_chunked` | `image-chunked: 476-byte chunk -> 476 + 224`; `image-build-reject` (chunk 0/477) |
| 9 | `uf2_image_parse` | `image-roundtrip`, `image-order`, `image-reject` x6 |
| 10 | `uf2_image_validate` | `validate: a built image validates clean`; `validate: bad magic` |
| 11 | `uf2_image_payload` | `payload: uf2_image_payload returns the exact source bytes` |

## 2. Flash functions (5/5)

| # | Function | Suite evidence |
|---|---|---|
| 12 | `uf2_mount_present` | `mount: absent path -> not present`; `mount: directory present` |
| 13 | `uf2_mount_is_bootsel` | `mount: ... INFO_UF2.TXT toggles the BOOTSEL probe` |
| 14 | `uf2_basename` | `basename: backslash/slash/plain paths and trailing separator` |
| 15 | `uf2_flash_wait_complete` | `flash-complete: absent destination -> COMPLETE`; `present destination with timeout 0 -> COPIED` |
| 16 | `uf2_flash_to_mount` | `flash-skip`, `flash-args` x4, `flash-source` x3, `flash-copy` (binary copy + read-back + COPIED) |

## 3. Catalog functions (4/4)

| # | Function | Suite evidence |
|---|---|---|
| 17 | `uf2_family_name` | `names: family catalog` (RP2040/RP2350/SAMD21/SAMD51 + unknown) |
| 18 | `uf2_flags_name` | `names: flag catalog` (NONE / single / combined / reserved) |
| 19 | `uf2_error_kind_name` | `names: error-kind and flash-status catalogs` |
| 20 | `uf2_flash_status_name` | `names: error-kind and flash-status catalogs` |

## 4. Types, constants, error kinds

| Declared | Evidence |
|---|---|
| `Uf2Error`, 10 error kinds | Every `*-reject`/`flash-source` check asserts the exact `kind`; `names: error-kind` maps them |
| `Uf2Block` (12 fields) | `block-roundtrip` asserts every field; `has_family` false case; flag-derived booleans in the noflash/container tests |
| `Uf2Image` (9 fields) | `image-roundtrip`, `image-chunked`, `image-noflash`, `image-container` assert payload/data_bytes/target_addr/contiguous/file_container |
| `Uf2FlashResult` (9 fields) | `flash-copy` asserts status/verified/source_bytes/copied_bytes/blocks/dest_path; `flash-skip` asserts status/detail |
| All format constants | `constants:` asserts magics, sizes, flags and family IDs |
| Flash statuses | `flash-skip`/`flash-copy`/`flash-complete` assert SKIP/COPIED/COMPLETE |

## 5. SKIP path

The suite never requires a real BOOTSEL volume.  `flash-skip` passes a
nonexistent mount and asserts `Ok` + `UF2_FLASH_SKIP`; the host-touching
tests use `fs_temp_dir()` only and clean up after themselves.  A real
mount, when present, follows the same code path (binary copy -> read-back
-> completion wait); the post-write disappearance race reports COMPLETE
with `verified = false` instead of a verify error.
