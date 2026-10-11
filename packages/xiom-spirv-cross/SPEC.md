# SPEC -- xiom.spirv-cross

## G2 pin

| Item | Value |
|---|---|
| Runtime soname | `spirv-cross-c-shared.dll` (Windows; `dl.dl_open` -> `LoadLibraryA`) |
| SDK | Khronos Vulkan SDK **1.4.350.0** |
| Upstream pin | SPIRV-Cross `1a6169566c73d3da552748fc372fe2bbb856e46e` (`vulkan-sdk-1.4.341.0-67-g1a616956`, Apache-2.0; clone `E:\repos\SPIRV-Cross`; equivalence proof in PROVENANCE.md) |
| Header (oracle) | `C:\VulkanSDK\1.4.350.0\Include\spirv_cross\spirv_cross_c.h` |
| Header SHA256 | `8939834EFB802521AD36F97F2AFD83FA03A0DAECBEFC2124C4E56BE77D126D4F` |
| Companion header (ABI enums) | `...\Include\spirv_cross\spirv.h` |
| spirv.h SHA256 | `62E24E3F287D612B47163350A04AA0B49822C1437BE407FBE10E488B9E4ADF3A` |
| DLL | `C:\VulkanSDK\1.4.350.0\Bin\spirv-cross-c-shared.dll` |
| DLL SHA256 | `E4B9CE3C72F6676B12F8950E49BA3C64B99DF962E28874F0E2D9A782A2C2FC38` |
| DLL size | 2,171,832 bytes |
| SPVC_C_API_VERSION | 0.68.0 (`spvc_get_version` cross-checked at runtime) |
| Oracle size | 169 `SPVC_PUBLIC_API` functions |
| Exported `spvc_*` | 169/169 (tools/check_exports.py; no missing, no extra) |
| Fixture toolchain | `spirv-as`/`spirv-val` from the same SDK; `tools/shaders/min.frag.spvasm` |
| Fixture blob | `min.frag.spv`: 141 words / 564 bytes, SPIR-V 1.0 magic `0x07230203` |

## Entry-point set

The oracle is the full `SPVC_PUBLIC_API` declaration list, resolved by name at
runtime. Family split (header sections), 169 total:

| Fragment | Family | Functions |
|---|---|---|
| `10_context` | context (incl. version/revision) | 9 |
| `11_compiler` | compiler core (compile, id bound, mask/flatten, samplers) | 6 |
| `12_glsl` | option surface + header lines + required extensions | 8 |
| `13_hlsl` | HLSL specifics + resource-binding struct init | 9 |
| `14_msl` | MSL specifics + struct inits + aux-buffer version | 40 |
| `15_resources` | shader-resource reflection surface | 6 |
| `16_type` | SPIR-V type introspection | 20 |
| `17_constant` | specialization constants (get/set scalar, subconstants) | 27 |
| `18_buffer` | buffer layout (sizes, offsets, strides, HLSL counters) | 8 |
| `19_reflect` | decorations, entry points, execution modes, misc reflection | 36 |

The full per-function inventory is in `docs/COVERAGE.md` (generated from the
same parse as the loader table, so the oracle cannot drift silently).

## Caller-visible boundary

Safe boundary: **nothing is exposed that cannot be validated by the caller**.
Every wrapper operates on owned, caller-supplied storage:

- Out-params are **one owned `&mut Vec[UInt8]` slot per out-param**, with a
  `requires:` contract of `slot.len() >= <sizeof>` where sizeof is the
  x64 C layout size computed by the generator (also exported as
  `SPVC_SIZEOF_<STRUCT>` constants).
- Input aggregates (`const T *` + count) are owned `&mut Vec[UInt8]` buffers
  with a `requires:` of `buf.len() >= count * SPVC_SIZEOF_<T>`; SPIR-V word
  buffers are `Vec[UInt8]` with `len >= words * 4`.
- Scalars cross the C ABI as `Int` (the sdl3 loader pattern; x64 ABI passes
  integers in 64-bit registers); returns are the exact C width (`Int32`,
  `UInt32`, `UInt64`, `UInt8`, `Float32`, `Float64`).
- All writes/reads of slot bytes are byte-indexed little-endian helpers
  (`spvc_read_u32_at`, `spvc_read_u64_at`, `spvc_write_u32_le`, ...). No
  `ffi.ptr_write_*` at offsets, no pointer arithmetic anywhere.
- Opaque handles (`spvc_context`, `spvc_compiler`, ...) cross as `Int`; they
  are never dereferenced on the XIOM side.
- Strings returned by the C API (`const char*`) are copied into `Str` via
  `Str::from_c_str` inside `unsafe` at the copy site only.

## Ownership / lifetimes

Per the C API: the `spvc_context` owns the parsed IR, compiler(s), options,
resources and all returned strings. `spvc_context_release_allocations` frees
the payload but keeps the context; `spvc_context_destroy` frees everything.
`SPVC_CAPTURE_MODE_TAKE_OWNERSHIP` lets the context own the IR word buffer
after `spvc_context_parse_spirv` returns -- the suite passes its owned
`Vec[UInt8]` fixture and does not touch it afterwards.

## Error mapping

| Failure | Result |
|---|---|
| DLL not loadable | `spirv_cross_load()` -> `Err(kind: SPVC_LOAD_ABSENT)`; suite reports SKIP |
| DLL loaded, symbol missing | `Err(kind: SPVC_LOAD_ABI, message: "<first missing name>")`; handle closed, nothing leaks |
| C call failure | `spvc_result` returned as `Int`; compare against `SPVC_SUCCESS` (0) |
| Stack corruption / older DLL | `spvc_get_version` mismatch vs the header pin fails the suite explicitly |

## Platform

Windows x64 only for now (soname + `dl_open` semantics). The loader goes
through `xiom.ffi.dl`, which wraps `LoadLibraryA`; a `.so` port only needs a
per-platform soname constant. x64 C layout sizes are pinned in the generator;
32-bit would need a layout pass.

## Re-pin procedure

1. Drop the new `spirv_cross_c.h` in place (keep the path).
2. `python tools/gen_spirv_cross.py` -- fragments + assembled module are
   regenerated deterministically; the run prints the new counts; assertions
   fail loudly on an unparsed declaration or an empty family.
3. `python tools/embed_spv_xiom.py` -- reassembles including the fixture.
4. `python tools/check_exports.py` -- proves missing=0 against the new DLL.
5. `& scripts\port.ps1 -Package xiom.spirv-cross` -- green; then
   `scripts/status.ps1 -Action update`.
6. Update the hashes and counts in this SPEC and `docs/COVERAGE.md`.
