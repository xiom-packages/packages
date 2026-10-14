# xiom.fidelityfx

AMD FidelityFX SDK surface bindings for [XIOM](https://kilo.ai/docs), pinned
at **FidelityFX-SDK `v2.3.0`** (the latest release tag, "AMD FSR SDK 2.3.0").

The package binds the engine upscaler / post family exactly as the pinned
public headers expose it:

* **Unified FFX API** (`ffxCreateContext`, `ffxDestroyContext`,
  `ffxConfigure`, `ffxQuery`, `ffxDispatch`) resolved at runtime from any
  module exporting them — the shipped `amd_fidelityfx_loader_dx12.dll` /
  `amd_fidelityfx_upscaler_dx12.dll` /
  `amd_fidelityfx_framegeneration_dx12.dll` (FSR2, FSR3 upscaling, frame
  generation) or a source-built backend. Descriptors (upscale create /
  dispatch, frame generation, queries, configure) are built into
  caller-owned XIOM buffers.
* **The SDK's own loader helper** (`ffxLoadFunctions`) compiled from the
  vendored header.
* **CPU constant/config setup** from the pinned GPU headers: FSR1 EASU/RCAS
  constants and SPD dispatch setup — headless, byte-exact, golden-checked.
* **The six vendored compiled swapchain shader blobs** (DXIL byte headers
  shipped by AMD; vendored as-is, never recompiled) as a read/query registry
  with SHA256 evidence.
* **The full declared per-effect host API census** (FSR2 / FSR3 upscaler /
  frame interpolation / optical flow / SPD: 61 declared records, 11
  callable, 50 metadata with deterministic typed runtime classification,
  skips = 0) — plus a compiler-verified ABI table (70 structs / 1,553 field
  offsets) for every bound type.

CAS and LPM are not present in the 2.3.0 headers and are documented out of
scope. GPU rendering paths degrade to typed no-device classification; CI
without any AMD binary stays green (typed SKIP).

## Quick start

```xiom
use xiom.fidelityfx;

let load = ffx_engine_load();
if load.is_ok {
  let eng = load.value;
  let desc = desc_upscale_create(0, 1280, 720, 1920, 1080);
  let r = ffx_create_context(&eng, &desc);      // typed outcome, handle in r.handle
  let _ = ffx_engine_close(&eng);
}
```

Headless CPU helpers (no GPU, no DLL):

```xiom
var con = owned_bytes(64);
let e = fsr1_easu_constants(&con, 2560.0, 1440.0, 2560.0, 1440.0, 3840.0, 2160.0);
var spd = owned_bytes(24);
let s = spd_setup(&spd, 0, 0, 2560, 1440, -1);     // dtg(40,23) wgo(0,0) nwm(920,11)
```

## Running the suite

```
scripts\port.ps1 -Package xiom.fidelityfx -TimeoutSec 300
```

35 checks headless (typed SKIP for the runtime section). With the pinned
clone's `Kits\FidelityFX\signedbin` on `PATH` the runtime section runs for
real (43 checks) — provider versions enumerate (`3.1.5` first) and the signed
binaries' provider-only export surface is classified ABSENT record-by-record.
Nothing from the SDK is committed except the MIT-listed sources and shader
blobs under `vendor/fidelityfx/`.

Docs: [SPEC.md](SPEC.md) (surface model, error taxonomy, runtime matrix,
re-carve), [PROVENANCE.md](PROVENANCE.md) (pin, license verification,
evidence), [docs/COVERAGE.md](docs/COVERAGE.md) (generated coverage table).

## License

`MIT OR Apache-2.0` for this package. Vendored upstream files are MIT (each
individually listed in the vendored `LICENSE.md`, see PROVENANCE.md).
