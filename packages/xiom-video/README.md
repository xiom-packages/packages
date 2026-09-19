# xiom.video

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Core video container abstractions: format-agnostic demux, mux, and frame handling.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `container` | Format-agnostic container interface |
| `demux` | Demuxing of elementary streams from containers |
| `mux` | Muxing of streams into containers |
| `frame` | Frame buffers, timestamps, and duration |
