# xiom.exr -- ROADMAP

## Phase 1 (Done) -- 0.1.0 reader
- [x] Vendored tinyexr v3.2.0 (BSD-3) + miniz with recorded transform
- [x] Memory/file read into owned planar float32 channels; metadata
      (dimensions, channel count/names, declared pixel types, compression,
      data window); typed errors
- [x] Save-to-memory path (tinyexr's writer) for fixtures/round trips, fp32 + fp16
- [x] 12/12 x2 on v0.64.4; `modules:` declared; PROVENANCE + CLEANUP row

## Phase 2 (Planned)
- [ ] Tiled + multipart reads (tot / EXRTile paths)
- [ ] Custom-attribute enumeration (EXRAttribute surface)
- [ ] `LoadEXR`/`LoadEXRWithLayer` RGBA convenience wrappers
- [ ] File save (`SaveEXRImageToFile`) + ZIP/PIZ compression knobs
- [ ] Re-pin when the drift guard flags a new tinyexr tag
