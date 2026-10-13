# SPEC: xiom.meshopt -- meshoptimizer bindings (vendored C++ tree)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.meshopt` |
| Version | 0.5.0 |
| Kind | binding (`categories: ["graphics"]`) |
| Upstream project | meshoptimizer -- https://github.com/zeux/meshoptimizer |
| Upstream version pinned | commit `f843aae0` (post-tag `v1.2`, `v1.2-17-gf843aae0`; `MESHOPTIMIZER_VERSION` 1020) |
| Upstream license | MIT (`vendor/LICENSE.md`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored C++ path is portable |
| Compiler pin | v0.64.4 |
| Modules | `xiom.meshopt` (root: FFI surface + probes + wrappers), `xiom.meshopt_safe` (pipeline wrappers), `xiom.meshopt_cooked` (XMC1 container) |

## 2. Vendored path (G2 pin)

The upstream `src/**` tree is vendored **verbatim** into `vendor/src/**`
(plus `LICENSE.md`) and compiled TU by TU with `--c-source` via
`port.args.json`; `src/meshopt_bridge.cpp` (the reviewable probe bridge) is
compiled first. No include rewriting is needed: each `.cpp` includes
`"meshoptimizer.h"`, which resolves against its own directory.

`.gitattributes` pins `vendor/** -text`; the bytes below are the canonical
LF blobs from the upstream object store.

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/LICENSE.md` | 1,079 | `F03037CA7BAD1E3EB7F4A63FA6084A8BAABD5BA30D3C239A9A7F35705D873E26` |
| `vendor/src/meshoptimizer.h` | 104,802 | `21A72040A75BACF6DDEFB7E74F1CF566AF1E68EA5E4DC0DB598278F4681E0B87` |
| `vendor/src/allocator.cpp` | 607 | `D2CC48691FE2F4C6D097BF7A766389CFB7F83CA14A5F747E3944332656D02254` |
| `vendor/src/clusterizer.cpp` | 47,507 | `71A5B826D16AB107D91F3BAF620A718318694B9060DA1D74614FF8E04E8939E7` |
| `vendor/src/indexanalyzer.cpp` | 3,820 | `BFF37AECB10CEFA33F3F6A217413C6AC98899C23E6DE5282420C60E6BAF786EC` |
| `vendor/src/indexcodec.cpp` | 21,390 | `2B98EDE67AB4731E8AB54DA794C46B735D659EA360666FE66BC5725C027FFF6E` |
| `vendor/src/indexgenerator.cpp` | 24,513 | `0E971DD8CC2CED68CD0374163461FC6C3E846267AEE7B47203837164991A015E` |
| `vendor/src/meshletcodec.cpp` | 33,807 | `F7BAD517CB77A646BA0BEEF916AC42715C2FE18002F29E12C6CD4CCD5835E678` |
| `vendor/src/meshletutils.cpp` | 20,635 | `4813A0C9E8648C6DE53F317322FA17C9486FF024F186AA9D631E7C60BA96C33E` |
| `vendor/src/opacitymap.cpp` | 18,567 | `81037B530D10AAAC80A43197294AEF5B27B3CCF8D1E323C5CCDC0945FC4C5D69` |
| `vendor/src/overdrawoptimizer.cpp` | 11,671 | `A70412562F991133CE52B2833ADEE9DE0A9029DC45312ADA1EB5C2452DC4F3EE` |
| `vendor/src/partition.cpp` | 19,202 | `CB988381000256E42B6E2759C908F37C935228FDE322958FB227533F39B139F5` |
| `vendor/src/quantization.cpp` | 3,503 | `28282F555D42A118A6735F161B1BA78FCBE0D1810A6A337A399BD8471F79105E` |
| `vendor/src/rasterizer.cpp` | 8,739 | `2172E0AC82359A19F2880763E2088F51B7EC361B23FB54F743B618691967DBE5` |
| `vendor/src/simplifier.cpp` | 104,083 | `DC40AADB307577ED3F7ADB5102A506263DE8B9FEA1D5582A24C04BFF2874A2CC` |
| `vendor/src/spatialorder.cpp` | 11,093 | `9005EE0069ED8C56797606DE80C0CD951AB55FFB608BC3AF83C4E5B2517371B1` |
| `vendor/src/stripifier.cpp` | 7,752 | `E653E6BE3A9B821016A1F6A90B756B971422F1246EBD03E60B478251A288BFD4` |
| `vendor/src/tangentspace.cpp` | 17,241 | `B006A329F9C90FE042A8BDC5DFCAB7422D5ADA3FD1864A0CD79EC1F2C5597AF3` |
| `vendor/src/vcacheoptimizer.cpp` | 14,171 | `618429EF4DB8AB9B16FDE4E73DCF425D89452ACBF103085478BC8B1761FA6689` |
| `vendor/src/vertexcodec.cpp` | 60,509 | `28770D1089650FCDA90D2EE6966D8638E44F2210596C10040BEDB87393513EA7` |
| `vendor/src/vertexfilter.cpp` | 55,477 | `780E7F95024B577B8ADCB8EE2A2E442294EBD62A1B6AAF37627FC1FF3CAC4FF3` |
| `vendor/src/vfetchoptimizer.cpp` | 1,915 | `AA534BB8150CA27AE229C58A0DC51F85F9ACCCBC5D4214F4C82EDD91FC08E478` |

### Provenance

| Artifact | Value |
|----------|-------|
| Source of record | `E:\repos\meshoptimizer` clone, clean working tree at commit `f843aae0b3070306bd2aeef43ffcf09509fee526` |
| Upstream repo | https://github.com/zeux/meshoptimizer (tag `v1.2` + 17 commits) |
| Extraction | `git cat-file blob HEAD:<path>` (canonical LF bytes, no EOL conversion) |
| Verification | each written file passes `git hash-object <file> == git rev-parse HEAD:<path>` |

Re-pin: advance the clone to the new commit, re-run the object-store
extraction loop (hash-verify every file), recompute this table, re-run
`scripts/port.ps1 -Package xiom.meshopt -TimeoutSec 900` x2, update the
version rows.

## 3. Design and safe boundary (G5)

`meshopt.xi` is the only module in the package with `extern "C"`: the raw
85-function surface (100% of the C API, still declared) plus the `xmo_*`
probe bridge compiled from `src/meshopt_bridge.cpp`.

Runtime probes (12): `meshopt_version`, `meshopt_remap_probe`,
`meshopt_cache_probe`, `meshopt_fetch_probe`, `meshopt_simplify_probe`,
`meshopt_index_codec_probe`, `meshopt_vertex_codec_probe`,
`meshopt_strip_probe`, `meshopt_quant_probe`, `meshopt_sphere_bounds_probe`,
`meshopt_meshlet_probe`, `meshopt_oct_filter_probe`.

Owned-buffer direction (3, the B-20-safe path): `meshopt_probe_build_indices`
(C writes the 294-index grid into an XIOM-owned byte slot),
`meshopt_probe_optimize_inplace` (C optimizes in place and verifies the
triangle multiset before copying back), `meshopt_probe_checksum` (FNV-1a
order-change evidence, read byte-indexed).

0.3.0 owned-buffer wrappers (ROADMAP Phase 3 item 1), the consumer-facing
shapes over the same safe direction: `meshopt_remap_mesh` (merge
byte-identical vertices; indices rewritten in place, remapped vertices
copied into an owned out slot), `meshopt_optimize_mesh` (in-place cache
optimize with the triangle multiset verified before write-back), and
`meshopt_simplify_mesh` (simplify toward a target count at a relative error
budget, result list into an owned out slot, count + error out). Plus
`meshopt_fill_grid`, a deterministic fixture filler (f32 positions stride
12, u32 indices in reversed triangle order) used by the suite. Inputs are
caller-owned `Vec[UInt8]` buffers (f32 positions, u32 indices); C reads the
inputs and writes results into XIOM-owned outputs; XIOM reads results back
byte-indexed (B-16/B-17/B-20 discipline).

0.4.0 codec-family probes (ROADMAP Phase 3 item 2):
`meshopt_index_sequence_probe` (index sequence codec -- arbitrary topology,
**byte-exact order preserved**, unlike the triangle-list codec),
`meshopt_filter_quat_probe` / `meshopt_filter_exp_probe` /
`meshopt_filter_color_probe` (quat/exp/color filter round trips; max error
in micro units) and `meshopt_meshlet_codec_probe` (meshlet encode/decode
typed 4/3: vertex refs byte-exact, triangle corners may rotate -- the
meshlet triangle coder rotates corners to line up next-bits, so the check
is rotation-invariant).

0.5.0 cooked-mesh container (ROADMAP Phase 3 item 3, section 4 below):
`meshopt_cooked_encode` wraps both EncodePipeline codec streams (vertex +
index) into the "XMC1" container; `meshopt_cooked_decode` opens it from
owned bytes and returns the decoded mesh (counts + XIOM-owned vertex/index
buffers) in one call, with typed `MeshoptError` codes 10..15 for
corrupt/truncated input. The module is pure-XIOM (no `unsafe`).

0.5.0 module layout: `extern "C"` names are module-private on the pin and a
dotted child cannot import its parent (B-04), so `src/meshopt_safe.xi`
(module `xiom.meshopt_safe`) and `src/meshopt_cooked.xi` (module
`xiom.meshopt_cooked`) use flat sibling names and reach the C surface
through thin pub wrappers exported by the root module (`generate_vertex_remap_into`,
`remap_vertex_buffer`, `optimize_vertex_cache_fifo`, `optimize_overdraw`,
`optimize_vertex_fetch`, `optimize_vertex_fetch_remap`,
`analyze_vertex_fetch`, `simplify_with_options`, `encode_index_bound`,
`encode_indices_raw`, `encode_vertices_bound`, `encode_vertices_raw`,
`decode_vertex_buffer`, `decode_index_buffer`, `stripify_bound`,
`byte_slot`). FFI stays confined to `meshopt.xi` (G5). The wrappers also
fixed two latent landmines in the previously-uncompiled safe module:
`generate_vertex_remap` no longer passes a NULL destination to
`meshopt_generateVertexRemap` (upstream memsets it unconditionally), and
`RemapPipeline` now owns its remap table instead of carrying a zero
pointer. `EncodePipeline` gained the missing `decode_indices` half so the
codec surface is symmetric.

ABI discipline: probes return scalars or write 4-byte ints into XIOM-owned
slots read little-endian (B-11/B-16/B-17); C++ structs (vertex-cache/fetch
statistics, `meshopt_Bounds`, meshlets) never cross the boundary by value;
no probe reads through a foreign pointer (B-20); no malloc/free from XIOM.

Probe meshes are deterministic and self-contained: an 8x8 grid (64 vertices /
98 triangles / 294 indices, triangle order reversed to be cache-hostile) and
an 11x11 bumpy grid (121 vertices / 200 triangles / 600 indices) for
simplification. The index codec check is rotation-invariant: upstream
`meshopt_encodeIndexBuffer` implicitly rotates triangle corners to match the
edge FIFO (README: use `meshopt_encodeIndexSequence` to preserve exact
order), so the probe asserts triangle-multiset equality, not byte equality.
The vertex codec round trip is byte-exact.

## 4. Cooked container "XMC1" (0.5.0)

`meshopt_cooked_encode` / `meshopt_cooked_decode` (module
`xiom.meshopt_cooked`) wrap the EncodePipeline streams into a small
self-describing container so an asset pipeline can store one byte blob and
recover the mesh without pointer juggling. All integers are little-endian
u32:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | magic `"XMC1"` (bytes `0x58 0x4D 0x43 0x31`) |
| 4 | 4 | format version (`1`) |
| 8 | 4 | vertex_count |
| 12 | 4 | vertex_size (bytes per vertex, 1..256) |
| 16 | 4 | index_count (u32 indices, multiple of 3) |
| 20 | 4 | vertex_stream_size (encoded bytes) |
| 24 | 4 | index_stream_size (encoded bytes) |
| 28 | 4 | total_size = 32 + vertex_stream_size + index_stream_size |
| 32 | ... | vertex stream (`meshopt_encodeVertexBuffer`), then index stream (`meshopt_encodeIndexBuffer`) |

Writer: caller-owned `Vec[UInt8]` mesh in, container bytes out (both
streams encoded through the existing `EncodePipeline` bounds/calls).
Reader (`meshopt_cooked_decode`, the single-call integration helper):
validates the header, copies each stream into an owned staging slot, decodes
into owned destination slots via `EncodePipeline.decode_vertices` /
`decode_indices`, range-checks every decoded index against `vertex_count`
and returns `MeshoptCookedMesh { vertex_count, vertex_size, index_count,
vertices, indices }`. Reading is byte-indexed on XIOM-owned memory only; C
only ever reads owned input and writes owned output (B-16/B-17/B-20/B-24/
B-25 discipline; no pointer arithmetic, no foreign-pointer reads).

Because the triangle-list index codec rotates corners (edge FIFO), the
lossless contract of the index stream is the triangle multiset, not byte
order; the vertex stream is byte-exact. Decode failures surface as typed
`MeshoptError` codes:

| Code | Constant | Meaning |
|------|----------|---------|
| 10 | `MESHOPT_COOKED_ERR_HEADER` | truncated header / invalid counts |
| 11 | `MESHOPT_COOKED_ERR_MAGIC` | bad magic (want `XMC1`) |
| 12 | `MESHOPT_COOKED_ERR_VERSION` | unsupported format version |
| 13 | `MESHOPT_COOKED_ERR_SIZE` | declared size mismatch / truncation |
| 14 | `MESHOPT_COOKED_ERR_DECODE` | codec stream encode/decode failure |
| 15 | `MESHOPT_COOKED_ERR_RANGE` | decoded index >= vertex_count |

## 5. Test matrix (0.5.0 recorded 2026-10-13, compiler v0.64.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored tree (always compiled in) | `scripts/port.ps1 -Package xiom.meshopt -TimeoutSec 900` | **PASS 43/43 x2** -- 16 constants + 12 runtime probes + 2 owned-buffer probes + 3 owned-buffer wrappers + 5 codec-family checks + 5 cooked-container checks; all 0.4.0 evidence plus: encode -> container -> decode identical vertex bytes (768/768), decoded indices valid and triangle multiset preserved, corrupt-magic/truncated-header/version/size container errors map to typed codes 11/10/12/13 |

Build cost: 20 vendored TUs + the bridge, `--timeout 900` carried by
`port.args.json` (watchdog headroom; ~25 s/run on this host). There is no
library-absence SKIP path -- the sources are vendored and always compiled in.

## 6. Scope

0.3.0 delivered the owned-buffer wrappers (remap/optimize/simplify),
0.4.0 the codec-family probes (index sequence, quat/exp/color filters,
meshlet codec) and 0.5.0 the cooked-mesh container plus the decoder
integration surface (and the pinned-wrapper floor that makes the previously
uncompiled `xiom.meshopt_safe` module real). The cluster pipeline
(buildMeshlets -> optimizeMeshlet -> computeMeshletBounds), the remaining
family probes (partition, spatial sort, opacity maps, tangents) and a re-pin
to the next upstream tag are Phase 3 (`ROADMAP.md`). The legacy pre-vendor
72-check declaration-only suite is preserved in git history; its 72/72
re-verify on v0.64.3 was recorded before the modernization.
