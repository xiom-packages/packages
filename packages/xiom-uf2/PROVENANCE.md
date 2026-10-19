# Provenance -- xiom.uf2

## Upstream reference (specification only)

| Item | Value |
|---|---|
| Repository | https://github.com/microsoft/uf2 |
| Commit pin | `90e9741f217f5a40c98ba74d663e408041037578` |
| License | MIT (Copyright (c) Microsoft Corporation) |
| License file | `LICENSE.txt` at the pinned commit |
| Files consulted | `README.md` (format, flags, family list, extension tags, file containers, MD5 record), `uf2.h` (struct layout and magic/flag constants), `utils/uf2families.json` (family IDs), `utils/uf2conv.py` (producer padding and family-flag behavior) |
| Clone used | depth-1 into a temporary directory for this port; not part of the repository |

## What was reproduced

The upstream project is a **format specification** plus C/Python tooling.
`xiom.uf2` is an independent pure-XIOM implementation of the specification:

* the 512-byte block layout, three magic words and five flag bits;
* the optional family-ID field and the family-ID values below;
* the 256-byte producer padding convention used by `uf2conv.py`;
* the `INFO_UF2.TXT` detection rule for a mounted UF2 MSC volume.

**Nothing from upstream is vendored, compiled or linked.** There are no
copied C sources, headers, generated tables or binaries in this package.
The upstream `uf2families.json` is not shipped; only the six IDs listed
below are transcribed as XIOM constants.

## Family-ID table used

| Constant | ID | Upstream short name | Description |
|---|---|---|---|
| `UF2_FAMILY_RP2040` | `0xE48BFF56` | `RP2040` | Raspberry Pi RP2040 |
| `UF2_FAMILY_RP2350_ARM_S` | `0xE48BFF59` | `RP2350_ARM_S` | Raspberry Pi RP2350, Secure Arm image |
| `UF2_FAMILY_RP2350_RISCV` | `0xE48BFF5A` | `RP2350_RISCV` | Raspberry Pi RP2350, RISC-V image |
| `UF2_FAMILY_RP2350_ARM_NS` | `0xE48BFF5B` | `RP2350_ARM_NS` | Raspberry Pi RP2350, Non-secure Arm image |
| `UF2_FAMILY_SAMD21` | `0x68ED2B88` | `SAMD21` | Microchip (Atmel) SAMD21 |
| `UF2_FAMILY_SAMD51` | `0x55114460` | `SAMD51` | Microchip (Atmel) SAMD51 |

The RP2350 family has three IDs at the pin (secure Arm, RISC-V and
non-secure Arm); all three are included. Unknown family IDs are accepted
and decode to the `"unknown"` name.

## Runtime dependencies

* `xiom.io` / `xiom.io.fs` from `xiom.std` -- file existence, directory
  existence, binary write, stat.
* `xiom.time` from `xiom.std` -- monotonic milliseconds and millisecond
  sleep for the completion poll.
* Tests additionally use `xiom.io`, `xiom.test`, `xiom.encoding.hex`,
  `xiom.string.compare`, `xiom.convert.int` and `xiom.time`.

No third-party runtime, SDK, bootloader binary or device driver is used.

## License

`xiom.uf2` is distributed under MIT OR Apache-2.0, matching the
repository. The upstream MIT notice is acknowledged here; no upstream code
is included, so no upstream license header is attached to source files.
