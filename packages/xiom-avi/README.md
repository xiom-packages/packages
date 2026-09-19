# xiom.avi

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** AVI container: RIFF-based demuxing, muxing, and index handling.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `riff` | RIFF chunk reader and writer |
| `demux` | AVI demuxer with stream interleaving |
| `mux` | AVI muxer with index generation |
| `index` | idx1 index parsing and frame lookup |
