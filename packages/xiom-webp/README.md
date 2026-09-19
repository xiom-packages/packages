# xiom.webp

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** WebP image codec: lossy (VP8) and lossless (VP8L) decode and encode.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `decode` | WebP container and VP8/VP8L bitstream decoder |
| `encode` | Lossy and lossless WebP encoder |
| `vp8` | VP8 intra frame prediction and reconstruction |
| `vp8l` | Lossless VP8L entropy decoding with alpha support |
