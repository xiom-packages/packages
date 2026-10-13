# xiom.spz

Gaussian-splat compression bindings for XIOM. The [nianticlabs/spz]
library (**v3.0.0**, MIT) is vendored in `vendor/spz/` with zlib 1.3.1 and
the zstd 1.5.7 amalgamation, and compiled into the test binary -- no system
library, no runtime DLL, no network at build time.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.4): 74/74
> (`scripts/port.ps1 -Package xiom.spz -TimeoutSec 900`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.spz;

fn main() {
  // 1 point: position (1, 2, 3), log-scale -3, identity rotation,
  // alpha 0 (logit), color 0.5, SH degree 0.
  var w: Vec[Float32] = Vec[Float32].new();
  w.push(1.0); w.push(2.0); w.push(3.0);
  w.push(-3.0); w.push(-3.0); w.push(-3.0);
  w.push(0.0); w.push(0.0); w.push(0.0); w.push(1.0);
  w.push(0.0);
  w.push(0.5); w.push(0.5); w.push(0.5);

  let packed = spz_pack(&mut w, 1, 0, false, SPZ_LATEST_HEADER_VERSION,
    SPZ_COORD_UNSPECIFIED, SPZ_DEFAULT_SH1_BITS, SPZ_DEFAULT_SH_REST_BITS);
  if !packed.is_ok {
    io.println("pack failed: " + packed.error.message);
    return;
  }
  var bytes: Vec[UInt8] = packed.value.bytes;
  io.println("packed to " + to_string(bytes.len()) + " bytes (NGSP v4/zstd)");

  let loaded = spz_unpack(&mut bytes, SPZ_COORD_UNSPECIFIED);
  if loaded.is_ok {
    io.println("unpacked " + to_string(loaded.value.num_points) + " gaussians");
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Constants | `SPZ_*` header/coord/stream/offset constants, `spz_constants_match`, `spz_coordinate_values_match` |
| Workspace | `spz_work_size`, `spz_work_offset`, `SPZ_STREAM_*` |
| Pack | `spz_pack(work, n, degree, antialiased, version, from, sh1Bits, shRestBits)` |
| Read | `spz_load_packed`, `spz_unpack`, `spz_packed_gaussian`, `spz_packed_gaussian_unpack` |
| Files | `spz_save_file`, `spz_load_file`, `spz_save_ply`, `spz_load_ply` |
| Raw codecs | `spz_serialize_packed`, `spz_compress_gzipped` |
| Cloud methods | `spz_cloud_data`, `spz_cloud_convert`, `spz_cloud_rotate180`, `spz_median_volume` |
| Math (`xiom.spz.math`) | `spz_half_to_float`, `spz_float_to_half`, `spz_norm3/4`, `spz_normalized3/4`, `spz_axis_angle_quat`, `spz_vec3f`, `spz_quat4f`, `spz_dot3`, `spz_squared_norm3`, `spz_times_qv/_qq/_qs/_vs/_vv`, `spz_plus_qq/_vv`, `spz_copy_float_buffer` |

Fallible calls return `Result[_, SpzError]` with a typed `SPZ_ERR_*` code and
a stable message.  Gaussians cross the boundary as one owned `Vec[Float32]`
workspace (layout in SPEC.md sec. 4); `&mut` inputs mirror the proven
`as_mut_ptr` idiom of the other bindings packages.

## Coverage

`docs/COVERAGE.md`: 53 declared items from the three pinned headers --
29 bridged, 21 modeled, 3 audited non-goals (extensions build flag off,
header-local logging template, PLY-only struct with no public accessor).

[nianticlabs/spz]: https://github.com/nianticlabs/spz
