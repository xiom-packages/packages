# xiom.phonon

Steam Audio (Phonon) spatial-audio bindings for XIOM via a **dynamic
loader**: `phonon_load()` resolves `phonon.dll` at runtime and every call
goes through resolved function pointers. No link-time dependency, no headers,
no vendored code -- and the suite reports **SKIP** (green) when the library
is not installed.

The runtime surface is **generated from the pinned public `phonon.h`**
(`tools/gen_phonon.py` -> `xiom.phonon.abi` / `xiom.phonon.exports`): every
enum value, struct size/offset and export name comes from the header, never
from hand-typed constants.

> **Status:** `incubating` -- 0.3.0 full audio-processing surface (context,
> HRTF incl. SOFA, owned planar audio buffers, binaural/panning/virtual
> surround/direct/path effects, ambisonics encode/panning/binaural/rotation/
> decode, version + capability probes) green **38/38 (present)** and
> **6/6 (absent, SKIP)** on compiler v0.64.4 -- see `AUDIT.md`.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.phonon;
use xiom.phonon.abi;

fn main() {
  let l = phonon_load();                       // phonon.dll
  if !l.is_ok { return; }                      // SKIP in CI
  let lib: PhononLibrary = l.value;

  let ctx = phonon_context_create(&lib, abi.STEAMAUDIO_VERSION, abi.IPL_SIMDLEVEL_SSE2, 0);
  let hrtf = phonon_hrtf_create(&lib, ctx.handle, 48000, 256,
    abi.IPL_HRTFTYPE_DEFAULT, abi.IPL_HRTFNORMTYPE_NONE, 1.0);

  // XIOM-owned planar buffers; the DLL never reads foreign pointers.
  var in_buf = phonon_audio_buffer_new(1, 256);
  var out_buf = phonon_audio_buffer_new(2, 256);
  phonon_audio_buffer_set(&mut in_buf, 0, 0, 1.0);      // impulse

  let be = phonon_binaural_create(&lib, ctx.handle, 48000, 256, hrtf.handle);
  let dir = PhononVector3{ x: 0.0; y: 0.0; z: -1.0 };   // ahead
  let st = phonon_binaural_apply(&lib, be.handle, &in_buf, &mut out_buf, &dir,
    abi.IPL_HRTFINTERPOLATION_NEAREST, 1.0, hrtf.handle);
  io.println("energy " + float_to_string(phonon_audio_buffer_total_energy(&out_buf)));

  let r1 = phonon_binaural_release(&lib, be.handle);
  let r2 = phonon_hrtf_release(&lib, hrtf.handle);
  let r3 = phonon_context_release(&lib, ctx.handle);
  let c = phonon_close(&lib);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `phonon_load`, `phonon_load_named(soname)`, `phonon_close`, `PhononLibrary`, `phonon_fn_of`, `phonon_export_index` |
| Probes | `phonon_probe(lib)`, `phonon_probe_default`, `phonon_probe_named(soname)`, `phonon_capabilities(lib)`, `PhononCapabilities`, `PhononInfo` |
| Context | `phonon_context_create`, `phonon_context_retain`, `phonon_context_release` |
| HRTF | `phonon_hrtf_create` (built-in), `phonon_hrtf_create_sofa_file` (SOFA), `phonon_hrtf_retain`, `phonon_hrtf_release` |
| Audio buffers | `phonon_audio_buffer_new` (XIOM-owned, planar) + `set`/`get`/`channel_energy`/`total_energy`; managed DLL buffers: `alloc_managed`/`free_managed`/`interleave`/`deinterleave`/`mix`/`downmix`/`convert_ambisonics` |
| Effects (each: create/apply/reset/retain/release/tail_size/get_tail) | `phonon_binaural_*`, `phonon_panning_*`, `phonon_virtual_surround_*`, `phonon_ambisonics_encode_*`, `phonon_ambisonics_panning_*`, `phonon_ambisonics_binaural_*`, `phonon_ambisonics_rotation_*`, `phonon_ambisonics_decode_*`, `phonon_direct_*` (+ `phonon_direct_apply_inplace`), `phonon_path_*` |
| Geometry | `PhononVector3`, `PhononOrientation`, `phonon_orientation_identity` |
| Constants | everything in `xiom.phonon.abi` (version, enums, struct layouts) and `xiom.phonon.exports` (export manifest); SKIP kinds `PHONON_LOAD_ABSENT/ABI/PROBE_FAILED` |

Outcomes are flat structs (`PhononHandleOutcome { ok; status; error; handle }`,
`PhononStatusOutcome`, `PhononEffectOutcome { ok; state; error }`) -- no
`Result[Option]` shapes.

### Declared surface vs. out of scope

Declared (typed wrappers): context, HRTF, audio buffers and the ten effect
groups -- **87 of the 216 public header functions**, 100% generated from the
pinned header, 100% resolved at load.  The **complete** 216-name manifest is
resolved at load time (`phonon_capabilities().resolved_fn_count`), so the
simulation domain (scenes, simulators, probes, reflection/path baking,
serialization, device backends) is reachable through `phonon_fn_of` with the
generated `exports.PHONON_IDX_*` indexes; typed wrappers for it are explicit
non-goals of 0.3.0 (`SPEC.md` §5, `docs/COVERAGE.md`).

## Runtime requirements (present path)

- `phonon.dll` resolvable by name -- put the directory containing it on
  `PATH` (Windows). The official Steam Audio **v4.8.1** release DLL is the
  verified runtime (`AUDIT.md`); the suite asserts 216/216 entry points.
- Without the DLL the loader classifies `PHONON_LOAD_ABSENT` and every
  runtime test prints SKIP under `[PASS]`.

## Tests

```
scripts/port.ps1 -Package xiom.phonon
```

- Without `phonon.dll` on PATH: **6 [PASS]** (generated manifest/ABI checks,
  f32 encoder table, owned-buffer round-trip, deterministic SKIP).
- With it: **38 [PASS]** -- 216/216 symbols, context lifecycle, HRTF
  (built-in + SOFA file when the upstream fixture is present), and every
  declared effect group measured against the C ground truth
  (`tools/path_check.c`).

## Verification tools (not part of the package)

| Tool | Purpose |
|------|---------|
| `tools/gen_phonon.py` | parses the pinned `phonon.h`; emits `src/phonon_abi.xi` + `src/phonon_exports.xi`; `--check` (drift guard), `--coverage`, `--verify-dll <path>` (PE export table vs header) |
| `tools/layout_check.c` | prints real Win64 `sizeof`/`offsetof` for every wrapped struct (clang cross-check of the generated layouts) |
| `tools/path_check.c` | C ground-truth harness for the DSP flows the suite asserts (energies recorded in the suite constants) |
