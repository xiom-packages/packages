# xiom.dlss

NVIDIA DLSS / NGX bindings for XIOM, built with the CLOSED-SDK pattern:
the NVIDIA DLSS SDK (NVIDIA RTX SDKs License) is studied at a pinned commit
and **nothing from it is vendored** -- this package ships independent
declarations of the NGX API surface and dynamic-loads the user's own
runtime modules, with typed SKIP when they are absent.
**Published**: `0.1.0` in `eco-v0.1.178` (sha256 `f9780ec3...`).

## What you get

- **85-entry resolvable table**: every `NVSDK_NGX_*` entry point the public
  headers declare for D3D11/D3D12/CUDA/Vulkan (init/shutdown, parameters,
  create/evaluate/release, feature requirements, scratch size) plus the
  16-function parameter C API and the two globals.
- **435 parameter keys** and **74 effective-key byte codes**, transcribed
  from the pinned headers (`src/surface.xi`, regenerable with
  `tools/gen_surface.py`).
- **DLSS-SR typed flow**: `dlss_sr_create_d3d12` / `dlss_sr_evaluate_d3d12`
  / `dlss_sr_destroy_d3d12` / `dlss_sr_optimal_settings` + availability
  queries; DLSS-FG and DLSS-RR run through the same entries with feature
  ids 11/13 and their declared keys.
- Result codes, feature/flag enums, SR+RR render presets.

## Runtime model (SKIP-safe)

```xiom
use xiom.dlss;

let l = dlss_load();                      // common locations, no download
if l.is_ok {
  let lib: DlssLibrary = l.value;
  // typed flow (needs a real D3D12 device + the NVIDIA runtime):
  //   dlss_d3d12_init -> dlss_d3d12_get_capability_parameters
  //   -> dlss_sr_available -> dlss_sr_optimal_settings
  //   -> dlss_sr_create_d3d12 -> dlss_sr_evaluate_d3d12 ...
  let _ = dlss_close(&lib);
} else {
  // l.error.kind == DLSS_LOAD_ABSENT: typed SKIP (runtime not installed)
}
```

`dlss_load_from(dlss_path, core_path, fg_path, rr_path)` takes explicit
paths for hosts or games that ship their own copy.  The modules are never
downloaded or committed.

Reflex (PCL stats/markers) is not part of the pinned public headers, so it
is not declared (`DLSS_REFLEX_COVERED`).

## Verify

```
.\scripts\port.ps1 -Package xiom.dlss
# optional present path (no download):
$env:XIOM_DLSS_DIR = "<dir containing nvngx_dlss.dll>"; .\scripts\port.ps1 -Package xiom.dlss
```

See `SPEC.md` (surface inventory, oracle counts, SKIP semantics),
`PROVENANCE.md` (upstream-first + license record, Reflex scan) and
`AUDIT.md` (run evidence).
