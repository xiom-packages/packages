# xiom-ogg

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** OGG container: page-based multiplexing of audio/video logical streams.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `pages` | OGG page reader and writer |
| `crc` | Ogg CRC-32 checksums |
| `streams` | Logical bitstream demultiplexing and multiplexing |
| `seek` | Page and granule position seeking |
