# xiom.phonon -- Roadmap

**Version**: v0.3.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-13

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `phonon.dll` at runtime |
| G2 pin (version + 216-name manifest + ABI layouts + header hashes) | Done -- `SPEC.md` §2 |
| Generated surface (header -> `abi`/`exports`, drift-checked) | Done -- `tools/gen_phonon.py --check/--coverage/--verify-dll` |
| Context lifecycle (create/retain/release) | Done |
| Version + capability probes | Done (`phonon_capabilities`: 216/216 resolved, per-group availability) |
| HRTF creation (built-in + SOFA file) | Done |
| Owned planar audio buffers + DLL-managed interop | Done |
| Binaural / panning / virtual surround effects | Done (create/apply/reset/retain/release/tail) |
| Direct effect (forward on/off, attenuation, air absorption, directivity, occlusion, transmission) | Done (via generated params layout; in-place supported) |
| Path effect (SH coefficients, spatialized + ambisonic) | Done |
| Ambisonics encode / panning / binaural / rotation / decode | Done |
| Audio buffer mix / downmix / convert-ambisonics | Done (managed buffers) |
| Scenes/geometry (static + instanced meshes) | Phase 2 |
| Simulator + probes + occlusion | Phase 2 |
| Reflections + path baking | Phase 2 |
| Serialization | Phase 2 |
| Pathing helpers (`iplCalculateRelativeDirection`, fp calculators) | Deferred on B-12 (see SPEC §3) |
| Custom speaker layouts (caller speaker arrays) | Future slice |

## Phase 2 (next touches)

1. Scene + geometry: `iplSceneCreate` / `iplStaticMeshCreate` from XIOM
   vertex arrays; `iplSimulatorCreate` + `iplSourceCreate`/`SetInputs`/
   `RunDirect` for occlusion; keep the default ray tracer (Embree/RadeonRays
   optional devices stay non-goals).
2. Probe batches: `iplProbeArray*` + `iplProbeBatch*` (+ load/save) to feed
   `iplSimulatorRunReflections`.
3. Reflections: IR/reconstructor + reflection effect/mixer/baker slice once
   the probe + scene layers exist.
4. Re-attempt the four deferred helpers when the fp-return fix (B-12) is
   pinned; add `iplCalculateRelativeDirection` via a C-side sret probe.
5. Custom speaker layouts: expose the speaker-array pointer path for
   `IPL_SPEAKERLAYOUTTYPE_CUSTOM`.

## Sector note

Audio sector, package 3 of 3 (`xiom.miniaudio`, `xiom.portaudio`,
`xiom.phonon` -- this package). 0.3.0 completes the runtime DSP surface the
spatial-audio engine needs; the simulation half is the Phase 2 target.
