# ROADMAP: xiom.uf2

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Current shipped surface: 0.1.0 (`SPEC.md`).  Everything below is unshipped
and explicitly out of the declared 0.1.0 surface.

## 0.2.0 -- checksum + extension tags (proposed)

| Item | Basis |
|---|---|
| MD5 verification when `UF2_FLAG_MD5_CHKSUM` is set | Upstream `README.md` "MD5 checksum" section; the 8th field holds the checksum. Use the stdlib MD5 (or a local implementation if the pinned stdlib path is red) and compare against the concatenated payload. |
| Extension-tag parsing (`UF2_FLAG_EXTENSION_TAGS`) | Upstream README; tags live at the end of the payload. Needs the tag grammar pinned at the upstream pin. |
| `uf2_image_parse` family-table completeness check | Warning/optional strict mode when a valid block carries a family ID not in the 0.1.0 catalog. |

## 0.3.0 -- streaming and mount discovery (proposed)

| Item | Basis |
|---|---|
| Streaming flash (block-at-a-time write instead of whole-file memory) | Large images (1-2 MiB) currently need the whole file in memory for validation + read-back. A streaming writer can validate and write as blocks arrive. |
| Volume auto-discovery (`uf2_find_bootsel_mounts`) | Enumerate drive roots / `/media` / `/Volumes` and probe `INFO_UF2.TXT`; keeps the caller from guessing the mount letter. Host-OS-specific, so a separate seam. |
| Copy-progress callback/status | Useful for CLI front-ends; a pure `Uf2FlashProgress` value passed to an optional reporter. |
| `CURRENT.UF2` readback parsing | Upstream README documents the bootloader-side readback file; the same block parser can validate it. |

## 0.4.0 -- picotool orchestration (proposed)

| Item | Basis |
|---|---|
| `uf2_picotool_*` orchestration | Owner plan: picotool (BSD-3) is a user-installed tool; the package should locate it, pass `-f`/`-v`/`-x` flags and parse output, without vendoring it. |
| `uf2_flash_and_verify(path, mount, opts)` | Compose copy + reboot wait + optional post-flash `picotool verify` when the tool is present. |
| Multi-family concatenated images | The spec lets multiple family IDs coexist for a bootloader to pick; 0.1.0 rejects mixed families. A future mode can parse and expose the per-family groups. |

## 0.5.0 -- ESP/other bootloader families (proposed)

| Item | Basis |
|---|---|
| Extended family catalog refresh | Pull `utils/uf2families.json` at each upstream pin bump; the table is data, so this stays additive. |
| ESP32-S2/S3/C3/C6 family IDs + C6/S3 UF2 variants | Already in the upstream table at the pin; add constants when a consumer asks. |
| Windows volume-change wait | Replace the poll loop with a filesystem-watch seam if the stdlib grows one; preserve the same COMPLETE/COPIED contract. |
