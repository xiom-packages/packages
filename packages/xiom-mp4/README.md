# xiom.mp4

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** MP4 container: ISO BMFF box parsing, demuxing, and muxing.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `box` | ISO BMFF box parser and builder |
| `moov` | Track, sample, and fragment tables |
| `demux` | MP4 demuxer with sample lookup |
| `mux` | MP4 muxer with fragmented output support |
