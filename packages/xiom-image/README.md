# xiom-image

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** Core image decoding/encoding dispatcher with shared pixel and color handling across formats.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `decode` | Unified image decode pipeline with format detection |
| `encode` | Unified image encode pipeline to a target format |
| `format` | Format sniffing and image metadata extraction |
| `convert` | Pixel format and color space conversion |
