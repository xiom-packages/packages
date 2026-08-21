# xiom-mp3

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** MP3 audio codec: MPEG audio layer III decoding and encoding.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `decode` | MPEG audio layer III decoder |
| `encode` | MP3 encoder with bitrate control |
| `frames` | Frame header, side info, and granule parsing |
| `huffman` | MP3 Huffman tables and bit reservoir handling |
