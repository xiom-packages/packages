# xiom.dxc

DirectX Shader Compiler **100% COM binding** for XIOM: 27 `IDxc*` interfaces /
128 methods across 13 generated wrapper modules, driven through a runtime
loader (`dxcompiler.dll` resolved with `LoadLibraryA` + `GetProcAddress`; no
`dxcapi.h`, no import library, no build-time SDK dependency).

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.3): 20/20 with
> `bound=128/128`, DXC 1.9.0.5347 (Vulkan SDK 1.4.350.0); SKIP when the DLL is
> absent. **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.dxc;                  // probe API (dxc_probe)
use xiom.dxc.gen_runtime;      // loader + DxcCreateInstance + bound-surface
use xiom.dxc.gen_compiler3;    // IDxcCompiler3 wrappers
use xiom.dxc.gen_result;       // IDxcResult wrappers
use xiom.dxc.gen_support;      // slots + little-endian readers

fn main() -> Int {
  if dxc_load() == DXC_RC_ABSENT { return 0; }   // SKIP: no compiler
  let compiler = dxc_create_compiler();          // CLSID_DxcCompiler -> IDxcCompiler3
  let source = "float4 main(uint vid : SV_VertexID) : SV_Position { return 0; }\n";
  var src = dxc_bytes(source);
  var result_slot = dxc_slot(8);
  let rc = dxc_compiler3_compile(compiler, &mut src, src.len() as Int32, 0 as Int32,
                                 "-T\nvs_6_0\n-E\nmain\n", 4, 0,
                                 dxc_iid_index("IDxcResult"), &mut result_slot);
  let result = dxc_rd_u64(&result_slot);
  var status = dxc_slot(4);
  dxc_operationresult_get_status(result, &mut status);
  io.println("compile status=" + dxc_i2s(dxc_rd_u32(&status)));
  dxc_release(result);
  dxc_release(compiler);
  dxc_unload();
  return 0;
}
```

## API

| Area | Modules / functions |
|------|---------------------|
| Probe | `xiom.dxc`: `dxc_probe`, `dxc_probe_named(soname)`, `DxcInfo`, `DxcLoadError` |
| Runtime | `xiom.dxc.gen_runtime`: `dxc_load`, `dxc_create_instance`, `dxc_create_compiler/utils/linker/...` (11 CLSID helpers), `dxc_query_interface`, `dxc_addref/release`, `dxc_method_count/name/interface`, `dxc_iid_*`, `dxc_clsid_*`, `DXC_ORACLE_*`, `DXC_RC_*` |
| Interface wrappers | `xiom.dxc.gen_blob` (7), `gen_handler` (6), `gen_legacy` (19), `gen_utils` (13), `gen_compiler3` (2), `gen_result` (7), `gen_container` (11), `gen_optimizer` (8), `gen_validator` (6), `gen_pdb` (24), `gen_pdb2` (25) |
| Slots | `xiom.dxc.gen_support`: `dxc_slot`, `dxc_rd_u32`, `dxc_rd_u64`, `dxc_bytes`, `dxc_i2s` |

Out-params are caller-owned `&mut Vec[UInt8]` slots written little-endian by
the bridge; objects cross as opaque `Int` handles. Failure model: compiler
missing -> SKIP (rc 1); missing `DxcCreateInstance` -> FAIL (rc 2); a present
compiler is expected to compile the probe shader.

## Build note

`port.args.json` compiles `src/dxc_probe.c` (0.2.0 probe) and the generated
`src/dxc_bridge.cpp` (100% surface) with no `--link` flags. Regenerate with:

```
python tools/gen_dxc.py --header "C:\VulkanSDK\1.4.350.0\Include\dxc\dxcapi.h" --package-dir .
python tools/gen_dxc.py ... --check    # fails on drift from the pinned header
```

Upstream-first: the oracle header was verified against the upstream clone at
the pinned commit (`E:\repos\DirectXShaderCompiler`); see `PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.dxc -TimeoutSec 900
```

Expected: `bound=128/128`, 20 `[PASS]`, exit 0; `docs/COVERAGE.md` maps every
interface/method to its runtime evidence. G2 pin + re-pin: `SPEC.md` §2.
