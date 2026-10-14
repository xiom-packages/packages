# xiom.xess

Intel XeSS (Super Resolution) bindings for XIOM via a dynamic loader.

- **SKIP-safe**: `libxess.dll` is resolved from the OS search path at run
  time; when it is absent the suite reports a typed SKIP (CI stays green).
  `libxess_dx11.dll` is loaded opportunistically for the D3D11 surface.
- **100% of the declared public surface**: all 41 entry points of the XeSS
  3.0.2 public headers (xess.h, xess_d3d12.h, xess_d3d12_debug.h,
  xess_vk.h, xess_vk_debug.h, xess_debug.h, xess_d3d11.h) are exposed with
  typed wrappers and pinned-struct serializers.
- **Nothing vendored**: reference-only clone + independent declarations
  (`PROVENANCE.md`); the package itself is MIT OR Apache-2.0.

```xiom
module demo

use xiom.xess;

fn main() -> Int {
  let l = xess_load();
  if !l.is_ok {
    if l.error.kind == XESS_LOAD_ABSENT {
      // no runtime on this host: SKIP
      return 0;
    }
    return 1;
  }
  let lib: XessLibrary = l.value;
  let v = xess_get_version(&lib);
  if v.ok {
    // v.version.major / minor / patch
  }
  let c = xess_close(&lib);
  return 0;
}
```

Typical D3D12 flow (caller owns the device/command list):

```xiom
let h = xess_d3d12_create_context(&lib, device);
let p = XessD3D12InitParams{ output_width: 1920; output_height: 1080;
  quality: XESS_QUALITY_SETTING_BALANCED; init_flags: 0;
  creation_node_mask: 1; visible_node_mask: 1;
  temp_buffer_heap: 0; buffer_heap_offset: 0;
  temp_texture_heap: 0; texture_heap_offset: 0; pipeline_library: 0; };
let r = xess_d3d12_init(&lib, h.handle, &p);
// ... xess_d3d12_execute(&lib, h.handle, command_list, &exec_params); ...
let d = xess_destroy_context(&lib, h.handle);
```

Tests: `scripts/port.ps1 -Package xiom.xess` (SKIP x2 on a box without the
runtime).  Details, coverage matrix and pins: `SPEC.md`; provenance:
`PROVENANCE.md`; current status: `AUDIT.md`.
