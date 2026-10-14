# xiom.rpr

AMD **Radeon ProRender** SDK **v3.1.7.1** core-API bindings for XIOM.

The public C API of AMD's GPU/CPU path tracer: context create/destroy, scene,
camera + lights, basic PBR material nodes (`RPR_MATERIAL_NODE_UBERV2`),
triangle mesh creation, framebuffer create/render/resolve and read-back into
XIOM-owned buffers (float and byte-indexed).  100% of the declared surface is
covered: **34 bridged functions + 31 modeled constants + 23 modeled core
types = 88 declared items, 0 gaps** (`docs/COVERAGE.md`, regenerated
fail-closed from the pinned header by `tools/surface_rpr.py`).

- **Decision (SPEC.md sec. 2):** vendored headers + runtime DLL loader.
  `RadeonProRender64.dll` is loaded at runtime (`LoadLibraryA` +
  `GetProcAddress`); backend plugins (Northstar64 CPU / Tahoe64 / HybridPro
  GPU) are registered by path. **No SDK binaries are committed.**
- **SKIP-safe:** without the SDK every backend check reports a typed SKIP and
  the suite stays green. GPU backends on an unsupported host GPU report
  `SKIP(no render output on host)` after completing the full API flow.
- Handles never cross as pointers: the bridge owns a registry and XIOM sees
  typed integer-handle structs (toolchain v0.64.4 discipline, SPEC.md sec. 4).

## Quick start

```xiom
use xiom.rpr;

fn main() -> Int {
  // default name resolves through the DLL search order
  if !rpr.load("").is_ok { return 1; }
  let pid = rpr.register_plugin("Northstar64.dll");   // CPU backend
  if !pid.is_ok { return 1; }
  let ctx = rpr.context_create(rpr.RPR_API_VERSION, pid.value,
    rpr.RPR_CREATION_FLAGS_ENABLE_CPU, "");
  if !ctx.is_ok { return 1; }
  // ... rpr.scene_create / camera / mesh / material / framebuffer / render
  return 0;
}
```

Full pipeline: `tests/test_conformance.xi` (camera + plane + point light +
PBR material, 16x16, 8 iterations, read-back verification).

## Tests

```powershell
# SKIP path (no SDK): green with typed SKIPs
.\scripts\port.ps1 -Package xiom.rpr

# present path (local SDK sample; nothing committed)
$env:XIOM_RPR_SDK_DIR = "<sdk>\RadeonProRender\binWin64"
.\scripts\port.ps1 -Package xiom.rpr -TimeoutSec 600
```

## Layout

| Path | Role |
|------|------|
| `src/rpr.xi` | public safe API (`xiom.rpr`) |
| `src/rpr_ffi.xi` | confined FFI core (`xiom.rpr.ffi`) |
| `src/rpr_bridge.c` | runtime loader + flat C ABI (compiled via `port.args.json`) |
| `vendor/rpr/` | pinned `RadeonProRender.h` + Apache-2.0 `license.txt` |
| `tools/surface_rpr.py` | fail-closed coverage oracle |
| `docs/COVERAGE.md` | declared-surface table (88 items, 0 gaps) |
| `SPEC.md` / `PROVENANCE.md` | pin, decision, license, local-sample evidence |

## License

MIT OR Apache-2.0 (everything outside `vendor/`).  Vendored material:
Apache-2.0, (C) 2019-2023 Advanced Micro Devices, Inc. -- see
`vendor/rpr/license.txt` and `PROVENANCE.md`.
