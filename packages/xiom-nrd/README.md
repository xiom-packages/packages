# xiom.nrd

NVIDIA Real-time Denoisers (NRD) integration surface for XIOM via a
**reference-only dynamic loader**: `nrd_load()` resolves `NRD.dll` (built
locally from the pinned upstream by the licensee) and every call goes
through the nine public `NRD_API extern "C"` entry points. No link-time
dependency, no headers, no vendored code -- the suite reports **SKIP**
(green) when no runtime module is present.

> **License finding (2026-10-13):** the upstream is **NOT MIT**. It is the
> proprietary *NVIDIA RTX SDKs License*, which forbids source redistribution
> and open-source-license application, so nothing from NRD ships in this
> repository (no source, headers, shader blobs or binaries). This package
> follows the FFmpeg precedent: independent XIOM code against the public
> header declarations + a runtime loader. See `PROVENANCE.md`.

> **Status:** `incubating` -- suite green on the pin (v0.64.4):
> **29/29 x2** with a locally built `NRD.dll` (v4.17.3) and **29/29 x2**
> SKIP-classified on the default PATH.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.nrd;

fn main() {
  let l = nrd_load();
  if !l.is_ok {
    io.println("NRD unavailable: " + l.error.message);  // SKIP in CI
    return;
  }
  let lib: NrdLibrary = l.value;
  let info = nrd_library_info(&lib);
  if info.is_ok {
    io.println("NRD v" + convert.int_to_string(info.value.version_major));
  }
}
```

## Surface (0.1.0)

- Instance lifecycle: `nrd_create_instance` / `nrd_destroy_instance`,
  `nrd_instance_info` (pipelines, pool sizes, register/space indices),
  `nrd_instance_shader_entry`.
- Settings into owned structs: `nrd_image_default` /
  `nrd_common_settings_for_frame` plus field accessors for all 99 fields of
  `CommonSettings`/`ReblurSettings`/`RelaxSettings`/`SigmaSettings`/
  `ReferenceSettings` (layouts fetched from the bridge's offset tables);
  `nrd_set_common_settings` / `nrd_set_denoiser_settings`.
- Dispatch plans: `nrd_dispatch_plan` -> `NrdPlan` (per-dispatch
  identifier/pipeline/grids, resource records, constant buffers in owned
  slots), `nrd_plan_validate`, per-denoiser resource queries;
  `nrd_execute` returns the typed `NRD_EXEC_NO_DEVICE` (GPU execution needs
  the application's device bridge; out of scope for 0.1.0).
- Typed errors: `SUCCESS`/`FAILURE`/`INVALID_ARGUMENT`/`UNSUPPORTED`/
  `NON_UNIQUE_IDENTIFIER` plus loader classification
  (`NRD_LOAD_ABSENT` -> SKIP).

Run the suite:

```
$env:XIOM_NRD_DLL = 'E:\repos\nrd\_Bin\Release\NRD.dll'   # optional present path
.\scripts\port.ps1 -Package xiom.nrd -TimeoutSec 300
```

`SPEC.md` documents the coverage matrix and owned-slot record layouts;
`PROVENANCE.md` the declaration oracle, the license finding, and the local
runtime sample recipe.
