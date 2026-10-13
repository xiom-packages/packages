# xiom.oidn -- Intel Open Image Denoise for XIOM

Bindings for the public C API of Intel Open Image Denoise v2.5.1
(https://github.com/RenderKit/oidn, Apache-2.0), CPU device scope.
`xiom.oidn` is a **loader-tier binding**: the package ships a self-contained
C++ bridge (`src/oidn_bridge.cpp`) that resolves `OpenImageDenoise.dll` at
runtime; nothing from upstream is compiled into XIOM programs and no binary
is stored in this repository.

## What you get

- **100% of the public C API** of `oidn.h` v2.5.1: 67 functions -- physical
  device enumeration, device create/commit/sync/release, device parameters
  and typed errors, buffers (create/read/write, sync + async, shared buffers
  over your own memory), semaphores, and the full filter surface
  (create/set-image/set-param/commit/execute, sync + async, progress
  monitor).
- Filters `RT` (ray-tracing denoiser) and `RTLightmap`, HDR/LDR modes,
  quality modes, and clean-aux toggles -- see the OIDN documentation for
  the parameter meanings.
- Image and buffer data cross the FFI as **owned byte buffers**
  (`Vec[UInt8]`): no foreign pointers, no pointer arithmetic.

## Quick start

```xiom
use xiom.oidn;

pub fn main() -> Int {
  let lr = oidn_load();               // Result[OidnInfo, OidnLoadError]
  if !lr.is_ok { return 1; }

  let dr = oidn_new_device_cpu();     // Result[Int, OidnError] (a handle)
  if !dr.is_ok { oidn_unload(); return 1; }
  let dev = dr.value;
  oidn_commit_device(dev);

  let w = 8; let h = 8;
  let bytes = w * h * 3 * 4;
  let br = oidn_new_buffer(dev, bytes);
  let orr = oidn_new_buffer(dev, bytes);
  if !br.is_ok || !orr.is_ok { oidn_unload(); return 1; }
  let color = br.value;
  let output = orr.value;

  var pixels: Vec[UInt8] = /* f32 RGB bytes */;
  oidn_write_buffer(dev, color, 0, bytes, &pixels);

  let fr = oidn_new_filter(dev, "RT");
  if !fr.is_ok { oidn_unload(); return 1; }
  let filter = fr.value;
  oidn_set_filter_image(dev, filter, "color", color, OIDN_FORMAT_FLOAT3, w, h, 0, 0, 0);
  oidn_set_filter_image(dev, filter, "output", output, OIDN_FORMAT_FLOAT3, w, h, 0, 0, 0);
  oidn_commit_filter(dev, filter);
  oidn_execute_filter(dev, filter);

  var denoised = /* bytes */;
  oidn_read_buffer(dev, output, 0, bytes, &mut denoised);
  /* ... */
  oidn_release_filter(filter);
  oidn_release_buffer(color);
  oidn_release_buffer(output);
  oidn_release_device(dev);
  oidn_unload();
  return 0;
}
```

## Runtime requirements

Put `OpenImageDenoise.dll` (v2.5.1) plus its companions
`OpenImageDenoise_core.dll`, `OpenImageDenoise_device_cpu.dll` and
`tbb12.dll` on `PATH` (they are co-located in the official Windows release
archive). Classification is SKIP-safe: without the runtime, `oidn_load()`
returns `Err(kind = OIDN_LOAD_ABSENT)` and no other call is valid; a
resolved library missing required exports classifies as `OIDN_LOAD_ABI`.

| Platform | Status |
|----------|--------|
| Windows x64 | supported (pin evidence) |
| Other hosts | loader tier is portable in principle; not claimed |

## Types

| Type | Meaning |
|------|---------|
| `OidnInfo` | `{ soname, resolved, required }` from a successful load |
| `OidnLoadError` | `{ kind, message }`, kind `OIDN_LOAD_ABSENT`/`OIDN_LOAD_ABI` |
| `OidnError` | `{ code, message }`, code is the upstream `OIDN_ERROR_*` value |
| `OidnF32Stats` | analysis helper over f32 buffers: `{ finite, changed, min_milli, max_milli, mean_milli }` |

Handles (`device`, `buffer`, `filter`, `semaphore`) are `Int` values owned
by the runtime; release them with the matching `oidn_release_*` before
`oidn_unload()`.

## Tests

`.\scripts\port.ps1 -Package xiom.oidn -TimeoutSec 240` runs 33 checks with
the runtime on `PATH` (real 8x8 CPU denoise with albedo/normal guides,
bit-identical repeat determinism, typed error paths, enumeration, buffers)
and 4 SKIP-green classification checks without it. Details and the recorded
evidence are in `SPEC.md` sections 5-6; inner-workings and safety rules in
`SPEC.md` section 3 and `AUDIT.md`.

## License

Package code: MIT OR Apache-2.0. Vendored headers and license text:
Apache-2.0 (Intel Corporation). See `vendor/LICENSE.txt` and
`PROVENANCE.md`.
