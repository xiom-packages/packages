# xiom.openpgl

Intel Open Path Guiding Library (Open PGL) v0.7.1 bindings for XIOM:
train a guiding field from deterministic sensor samples, then query
surface sampling distributions (direction samples + PDFs) for path-guiding
renderers.  The full C++ core — Open PGL plus its oneTBB runtime and the
embreeSrc support subset — is vendored at the pin and compiled into the
test binary at port time; nothing is loaded dynamically.

- Upstream: https://github.com/RenderKit/openpgl (Apache-2.0), tag v0.7.1
- Runtime: oneTBB v2021.13.0 (Apache-2.0) vendored sources
- Package code: MIT OR Apache-2.0
- Declared surface: 31/103 upstream C symbols across device, guiding
  field, sample storage, surface sampling distribution and field
  statistics (SPEC.md section 1)
**Published**: `0.1.0` in `eco-v0.1.179` (sha256 `a5e7f5a9...`).

## Quick start

```xiom
module demo

use xiom.io;
use xiom.openpgl;

fn main() -> Int {
  let dev_r = device_create(PGL_DEVICE_CPU_4, 1);
  if !dev_r.is_ok { return 1; }
  let dev = dev_r.value;

  let field_r = field_create(dev, true, 5000);
  if !field_r.is_ok { return 1; }
  let field = field_r.value;

  let stor_r = storage_create();
  if !stor_r.is_ok { return 1; }
  let storage = stor_r.value;
  let _ = storage_reserve(storage, 256, 0);

  var feed: Vec[Float32] = Vec[Float32].new();
  var i = 0;
  while i < 256 {
    sample_push(&mut feed, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, PGL_FLAG_SURFACE);
    i = i + 1;
  }
  let _ = storage_add_samples(storage, &mut feed, 256);

  var it = 0;
  while it < 3 {
    let tr = field_train(field, storage);
    if !tr.is_ok { return 1; }
    it = it + 1;
  }

  let dist_r = sampling_distribution_create(field);
  if !dist_r.is_ok { return 1; }
  let dist = dist_r.value;
  let pos = PglVec3{ x: 0.0; y: 0.0; z: 0.0 };
  let _ = sampling_distribution_init(field, dist, pos, 0.5);
  let dir_r = sampling_distribution_sample(dist, 0.25, 0.75);
  if !dir_r.is_ok { return 1; }
  io.println("sample dir ok");
  return 0;
}
```

The conformance suite (`tests/test_conformance.xi`) is the complete
worked example: deterministic 256-sample feed, 3 training iterations,
fixed/sampled PDF checks, statistics snapshot, typed misuse errors and a
bit-identical repeat run.

## Build and test

```
scripts/port.ps1 -Package xiom.openpgl -TimeoutSec 1500
```

The run compiles 46 vendored C++ TUs plus the bridge (C++17, the
`port.args.json` list) — expect ~5-7 minutes on the reference machine
dominated by the one-time compile.

## Layout

| Path | What |
|---|---|
| `src/openpgl.xi` | public safe API (`xiom.openpgl`), typed `PglError` |
| `src/openpgl_ffi.xi` | confined FFI core (`xiom.openpgl.ffi`), the only `unsafe` |
| `src/pgl_bridge.cpp` | reviewable C++ bridge over the Open PGL C API |
| `vendor/openpgl/**` | pinned upstream: Open PGL v0.7.1, oneTBB v2021.13.0, embreeSrc subset, generated TU wrappers |
| `tools/vendor.py` | the vendoring generator (re-carve; PROVENANCE.md) |
| `tests/test_conformance.xi` | 14-check conformance suite |
| `SPEC.md`, `PROVENANCE.md`, `ROADMAP.md`, `AUDIT.md` | surface, pins, plan, audit |

Note: this port builds the x86-64 SSE2 baseline and exposes the CPU_4
device only — see SPEC.md section 5 for the ISA rationale and the CPU_8
status.
