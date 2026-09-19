# xiom.flac

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** FLAC audio codec: lossless decoding, encoding, and metadata handling.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `decode` | FLAC decoder with all channel assignments |
| `encode` | FLAC encoder with predictor selection |
| `frames` | Frame and subframe decoding |
| `residual` | Rice and constant residual coding |
