# xiom.phonon -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-09

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `phonon.dll` at runtime |
| G2 pin (version + ABI layouts + header hashes) | Done -- `SPEC.md` §2 |
| Context lifecycle (create/retain/release) | Done -- probe |
| SKIP/FAIL classification | Done |
| HRTF creation (`iplHRTFCreate`) | Phase 2 |
| Binaural/panning/virtual-surround effects | Phase 2 |
| Ambisonics effects | Phase 2 |
| Scenes/geometry (static + instanced meshes) | Phase 2 |
| Serialization | Phase 2 |
| Simulator + probes | Phase 2 |

## Phase 2 (next touches)

1. HRTF: `iplHRTFCreate` with `IPL_HRTFTYPE_DEFAULT` (embedded SOFA data)
   and derived settings (`iplHRTFGetBinauralFilter`, normalization volume) --
   the key spatial-audio capability.
2. Core effects: binaural (`iplBinauralEffectCreate` + `...Apply` on an
   `IPLAudioBuffer`) with an in-memory mono impulse, plus panning and
   virtual-surround.
3. Ambisonics: encode/rotation/decode chain on owned buffers.
4. Scenes: `iplSceneCreate` + `iplStaticMeshCreate` from an XIOM vertex
   array; `iplSimulator*` for occlusion/propagation probes (Embree/RadeonRays
   optional -- keep the default ray tracer).
5. Struct marshalling: XIOM-owned byte buffers with documented layouts for
   `IPLAudioBuffer`/`IPLVector3`/`IPLCoordinateSpace3` (the byte-pinned style
   used across this lane).
6. Batch the surface deliberately: the pre-pilot module declared ~125
   functions; rebuild the safe wrappers in reviewable slices with a suite per
   slice.

## Sector note

Audio sector, package 3 of 3 (`xiom.miniaudio`, `xiom.portaudio`,
`xiom.phonon` -- this package). Next sector per the proposal: accelerators
(gated on XVECTOR) then crypto/media.
