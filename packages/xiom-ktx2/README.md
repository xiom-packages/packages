# xiom.ktx2

KTX2 texture container and Basis Universal transcode bindings for XIOM,
backed by a vendored **libktx** (Khronos KTX-Software v4.4.2, Apache-2.0).

```xiom
use xiom.ktx2;

fn main() -> Int {
  var image = ktx2_test_image_rgb8();       // 48-byte 4x4 RGB8 fixture
  var generated = ktx2_slot(4096);          // caller-owned KTX2 byte slot
  var record = ktx2_slot(128);              // caller-owned probe record
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut record);
  match rt {
    Err(rc) => { /* setup/overflow: rc is a KTX error code */ return 1; },
    Ok(r) => {
      if r.write_rc == 0 && r.read_rc == 0 && !r.level0_mismatch {
        // generated now holds a valid KTX2 file; r.data_size == 48,
        // r.vk_format == 23 (VK_FORMAT_R8G8B8_UNORM), r.class_id == 2
        return 0;
      }
      return 1;
    }
  }
}
```
**Published**: `0.1.0` in `eco-v0.1.178` (sha256 `3c36e2b8...`).

## What this package does

| Area | API |
|---|---|
| KTX2 read/write | `ktx2_create`, `ktx2_set_image`, `ktx2_write_memory`, `ktx2_read_info`, `ktx2_read_level`, `ktx2_roundtrip`, `ktx2_named_file_probe` |
| KTX1 + KTX1→KTX2 | `ktx2_ktx1_probe` (plus `ktx2_create(kind=1)`) |
| Streams | `ktx2_stream_probe` (custom `ktxStream` + stdio) |
| Basis transcode | `ktx2_basis_probe` (ETC1S→BC1/ETC1/RGBA32, UASTC→BC7) |
| ASTC | `ktx2_astc_probe` (`CompressAstcEx` + `DecodeAstc`) |
| Metadata | `ktx2_hashlist_probe` (full `ktxHashList_*` family) |
| Strings | `ktx2_c_string` (`ktxErrorString`, scheme/format tables) |
| GL loader | `ktx2_gl_probe` |
| Corrupt input | `ktx2_corrupt_probe` (typed KTX error codes) |
| Declared surface | `ktx2_symbol_count`, `ktx2_symbol_name`, `ktx2_symbol_lookup` (93/93 pinned `ktx.h` functions) |
| Utilities | `ktx2_slot` (owned slot allocator), `ktx2_u32` / `ktx2_u64` (little-endian reads), `ktx2_handle_is_null` |

The full 93-function extern surface is declared in the module for ABI
documentation; runtime calls go through the bridge (see `SPEC.md` §3 for the
memory-safety boundary and record layouts).

## Boundary rules (v0.64.4 discipline)

* Handles are opaque 8-byte tokens in caller-owned slots; XIOM never casts a
  handle to a pointer (B-25) and never reads through a foreign pointer
  (B-20).
* Out-parameters are caller-owned byte slots read little-endian;
  statuses are C return values (B-24).
* All `extern "C"` lives in `ktx2.xi` (G5).

## Build

```
scripts/port.ps1 -Package xiom.ktx2 -TimeoutSec 1800
```

Compiles 69 vendored TUs (libktx + Basis transcoder/encoder + dfdutils +
Arm ASTC + vendored zstd) plus the bridge and links the 41-check suite.

## Related

* `xiom.ktx` — pure-XIOM KTX1 reader (untouched, complementary).
* `xiom.zstd` — standalone zstd; libktx embeds its own zstd 1.5.5 copy
  (`PROVENANCE.md`).

## Licence

MIT OR Apache-2.0 (XIOM code). Vendored components keep their own licences
(Apache-2.0 libktx/Basis/Arm-ASTC, BSD-3-Clause zstd); see
`PROVENANCE.md`.
