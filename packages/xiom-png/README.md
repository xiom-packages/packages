# xiom-png

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** PNG image codec: decoding and encoding of the Portable Network Graphics format.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `decode` | PNG decoder for all bit depths and color types |
| `encode` | PNG encoder with configurable filter strategy |
| `filter` | Per-row pre-filter selection and reconstruction |
| `palette` | Palette (PLTE) and transparency (tRNS) handling |
