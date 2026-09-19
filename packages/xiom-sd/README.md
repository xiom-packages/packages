# xiom.sd

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** SD/MMC card block storage access over SPI or SDIO.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `card` | Card detection and initialization. |
| `block` | Block read/write access. |
| `fs` | File system mount helpers. |
| `status` | Card state and capacity info. |
