# PROVENANCE: xiom.uf2

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0
>
> Owner policy: upstream-first, 100% of the declared surface.  This package
> is an **independent pure-XIOM implementation**: no upstream code is
> vendored, ported, or copied.  Upstream is consulted as the format oracle.

## 1. Upstream project

| | |
|---|---|
| Project | **microsoft/uf2** -- "USB Flashing Format (UF2)" |
| Canonical repo | `https://github.com/microsoft/uf2` |
| Clone pin | `90e9741f217f5a40c98ba74d663e408041037578` (2026-02-08) |
| Clone | `git clone --depth 1 https://github.com/microsoft/uf2 E:\repos\uf2` (light clone; working tree clean at the pin) |
| License | **MIT** -- verified FIRST, before any study: the repo root carries `LICENSE.txt` ("Microsoft UF2 / The MIT License (MIT) / Copyright (c) Microsoft Corporation"). MIT is permissive, no copyleft, compatible with this package's MIT OR Apache-2.0. |
| Runtime use | None.  No UF2 code, no C, no data files ship with this package. |

## 2. What was consulted (reference-only)

| Upstream path at the pin | Used for |
|---|---|
| `uf2.h` | The 512-byte block layout, `UF2_Block` field order, the three magics (`0x0A324655`, `0x9E5D5157`, `0x0AB16F30`) and the five flag constants (`0x1`, `0x1000`, `0x2000`, `0x4000`, `0x8000`). |
| `README.md` | Semantics: 512-byte blocks, "up to 476 bytes of data", 32-byte header, little-endian u32 fields, zero padding, end-magic rationale, flag meanings, family-ID purpose and the statement that bootloaders ignore non-matching family blocks, block numbering/numBlocks, payload-size flexibility. |
| `utils/uf2conv.py` | The reference converter: default 256-byte chunks (`numblocks = (len + 255) // 256`), `is_uf2` checks the first two u32 magics, FAMILY_ID flag set when a family is given, family-field handling, zero padding to offset 508. |
| `utils/uf2families.json` | The family-ID table.  Exactly the values in SPEC.md sec. 2 were read at the pin (RP2040/RP2XXX/RP2350 ARM-S/RISCV/ARM-NS, SAMD21, SAMD51; the file lists 76 families in total). |
| `utils/uf2conv.py` (`INFO_FILE = "/INFO_UF2.TXT"`) | The BOOTSEL volume info-file name used by `uf2_mount_is_bootsel`. |

Nothing was translated: the XIOM code was written from the field layout
and the documented rules, then tested against synthetic fixtures built from
those rules (SPEC.md sec. 3).

## 3. Family-ID table used (verbatim values at the pin)

| Upstream `short_name` | Upstream `id` | XIOM constant |
|---|---|---|
| `RP2040` | `0xe48bff56` | `UF2_FAMILY_RP2040` (3834380118) |
| `RP2XXX_ABSOLUTE` | `0xe48bff57` | `UF2_FAMILY_RP2XXX_ABSOLUTE` (3834380119) |
| `RP2XXX_DATA` | `0xe48bff58` | `UF2_FAMILY_RP2XXX_DATA` (3834380120) |
| `RP2350_ARM_S` | `0xe48bff59` | `UF2_FAMILY_RP2350_ARM_S` (3834380121) |
| `RP2350_RISCV` | `0xe48bff5a` | `UF2_FAMILY_RP2350_RISCV` (3834380122) |
| `RP2350_ARM_NS` | `0xe48bff5b` | `UF2_FAMILY_RP2350_ARM_NS` (3834380123) |
| `SAMD21` | `0x68ed2b88` | `UF2_FAMILY_SAMD21` (1760373640) |
| `SAMD51` | `0x55114460` | `UF2_FAMILY_SAMD51` (1427194976) |

The mission-required four (RP2040, RP2350, SAMD21, SAMD51) are covered
directly; the RP2350 variants and RP2XXX absolute/data IDs are included
because the upstream table distinguishes them.

## 4. Test vectors

All fixtures are **synthetic**, generated in the suite from the package's
own builder (payload patterns `(i * 7 + seed) % 256`) and corrupted at
known offsets for the rejection cases.  No upstream test data was copied.
The byte-exact golden in `test_block_golden` is derived from the `uf2.h`
layout and the README field table at the pin, not from an upstream fixture.

## 5. Third-party dependencies at runtime

None beyond the XIOM standard library (`xiom.std`): `xiom.io`,
`xiom.io.fs`, `xiom.serialize.endian`, `xiom.string`,
`xiom.string.compare`.  The flash path uses only binary file I/O and
`io.sleep`/`io.time_now`; no OS-specific API is called, so the package is
host-OS-neutral.
