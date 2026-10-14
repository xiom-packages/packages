# SPEC: xiom.vdb 0.1.0

> Status: `incubating` / conformance-tested 30/30 on XIOM v0.64.4
> (recorded via `scripts/status.ps1`). No pinned upstream bytes are read at
> test time; see §10 for exactly what is and is not verified.
>
> Scope: a **minimal, surface-first OpenVDB `.vdb` container reader** in pure
> XIOM. It opens a `.vdb` image, enumerates grids (name / type / class /
> transform metadata), reads the tree topology, and decodes dense 8x8x8 leaf
> blocks of **float / half / double / vec3f / vec3d** grids with bounds
> checks and typed errors. There is no writer, no FFI, no I/O: the API is a
> pure function surface over an in-memory `Vec[UInt8]` file image.
> `xiom.io.read_file_bytes(path)` is the intended byte source for callers.

---

## 1. File layout (supported file format versions 222..225)

All multi-byte scalars are little-endian. Offsets below are absolute in the
image.

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 8 | magic | `0x56444220` stored zero-extended in an i64 (`20 42 44 56 00 00 00 00`). The upper 4 bytes must be 0. |
| 8 | 4 | file format version | Accepted: `222..225`. `< 222` (pre mask-compression formats) and `> 225` are typed errors. |
| 12 | 4 | library major | recorded only |
| 16 | 4 | library minor | recorded only |
| 20 | 1 | has-grid-offsets | 1 = seekable image: per-grid stream positions are valid; 0 = streamed image: the three positions per descriptor are zeros and every grid body must be walked to reach the next descriptor. |
| 21 | 36 | UUID | exposed as `Str` only when all 36 bytes are printable ASCII, else `""` (upstream writes an empty UUID's first byte as 0x00). |
| 57 | var | file MetaMap | same layout as grid MetaMaps (§3). |
| end | 4 | grid count | sanity cap 65536. |
| — | var | grid descriptors + bodies | see below. |

Each grid descriptor is three length-prefixed strings (unique name, raw tree
type name, instance-parent name) followed by three i64 stream positions
(grid position, block position, end position), and then immediately that
grid's body:

```
body := u32 compression-flags
        MetaMap                     (grid metadata)
        transform                   (name + fixed map payload)
        topology                    (tree structure)
        buffers                     (leaf buffers); absent for instance grids
```

Rules enforced at open:

- strings are `u32 length` + bytes, every byte must be printable ASCII
  (0x20..0x7E), length cap 4096 (no NUL-terminated strings; no UTF-8);
- for seekable images `grid position == descriptor end` is checked, and
  `end position <= image size`; bodies are skipped by jumping to the stored
  end position (unknown grid types and instance grids are fine here);
- for streamed images the open walks every grid body (instance grids stop
  after the transform) so unsupported grid types are typed errors at open;
- the unique name may carry a 0x1E (`RS`) duplicate suffix; the stripped
  name is exposed as `names[i]`, the raw stored name as `unique_names[i]`.

## 2. Compression flags

`u32` per grid, bits 0..2 defined; any other bit is a typed error.

| Flag | Value | Meaning |
|---|---|---|
| NONE | 0 | raw values |
| ZIP | 1 | zlib (RFC 1950/1951) value chunks |
| ACTIVE_MASK | 2 | mask compression: value chunks store only active values plus metadata (§6) |
| BLOSC | 4 | blosc value chunks: **structure walks (chunk skipping), values are a typed error** (documented limitation) |

A chunk under ZIP/BLOSC is an i64 size prefix followed by payload bytes:

- prefix `> 0`: that many bytes of the compressed/encoded stream (ZIP: zlib
  stream; BLOSC: opaque);
- prefix `<= 0`: `-prefix` raw fallback bytes (both ZIP and BLOSC define
  this). The reader accepts both forms; when values are decoded, the raw
  fallback length is verified against the expected value count.

## 3. MetaMap (file-level and grid-level)

```
u32 item count                       (cap 65536)
items: u32 name length + name bytes  (printable ASCII)
       u32 type length + type bytes  (printable ASCII)
       u32 value byte count          (cap 16 MiB)
       value bytes                   (opaque; typed decoders below)
```

Typed decoders implemented: `"string"` (payload is the string bytes),
`"int32"` (4 bytes LE, sign-extended), `"int64"` (8 bytes LE, two's
complement), `"bool"` (1 byte, 0/1), `"float"` (4-byte IEEE-754 binary32,
promoted exactly to Float64), `"double"` (8-byte IEEE-754 binary64). Wrong
type name or payload size is a typed error. Everything else
(`"vec3s"`, `"delayed load"` metadata, …) stays available as a raw value
copy. The grid class is the metadata item named `class` (`"fog volume"`,
`"level set"`, `"staggered"`, …); an absent item means the class is unset.

## 4. Transform

A length-prefixed map type name plus a fixed-size map payload:

| Map type | Payload | Voxel size source | Kind |
|---|---|---|---|
| `UniformScaleMap`, `ScaleMap` | 5 Vec3d (`scale`, `voxelSize`, `inv`, `invSqr`, `invTwice`) = 120 B | field 2 | 1 |
| `UniformScaleTranslateMap`, `ScaleTranslateMap` | 6 Vec3d (`translation`, + the 5 above) = 144 B | field 3 | 2 |
| `TranslationMap` | 3 doubles = 24 B | `(1,1,1)` | 3 |
| `AffineMap`, `UnitaryMap` | row-major 4x4 doubles = 128 B | norms of the three 3x3 columns | 4 |

`voxel_size` and `translation` are always 3 Float64 values. Any other map
type (`NonlinearFrustumMap`, …) is a typed `UNSUPPORTED_TRANSFORM` error —
a documented limitation (the grid can still be enumerated).

## 5. Tree topology

For every supported grid the tree is the standard (and only supported) node
chain `Tree_<type>_5_4_3`: leaf 8^3 (log2dim 3), internal 16^3 (log2dim 4),
internal 32^3 (log2dim 5), root children spanning 4096 voxels per axis.

```
topology := i32 buffer count (must be 1)
            root background  (logical type width; NOT half-storage)
            u32 tile count
            u32 child count
            tiles:   3 x i32 origin, logical-width value, u8 active
            children (in file order): 3 x i32 origin, node
node (log2dim 3 = leaf) := 64-byte value mask          (topology part)
                           64-byte value mask+metadata+values (buffers part, §6)
node (log2dim 4/5)     := child mask (512/4096 B), value mask (512/4096 B),
                          mask-compressed value array, children in
                          increasing offset order
```

Masks are packed bit arrays, little-endian 64-bit words; bit `n` lives in
byte `n >> 3`, bit `n & 7`, and offset `n` maps to local voxel
`x = n / dim^2, y = (n / dim) % dim, z = n % dim` with `dim` the node
dimension (8 leaf, 16 internal-4, 32 internal-5; x slowest, z fastest).
Leaf origins are **not stored**: they are computed from the root child
origin plus `local << 7` (internal 4) and `local << 3` (leaf), in exactly
the writer's iteration order. Root tile values and internal tile values are
walked and validated but not exposed (documented limitation; dense leaf
blocks are the declared value surface).

The topology section is followed by the leaf buffers section: for each leaf
in file order, the leaf's 64-byte value mask again, then the value chunk
(§6).

## 6. Value chunks and mask compression

Per node, the value array is encoded as:

```
i8 metadata
[1 or 2 inactive values]   (logical width each)
[64-byte selection mask]   (leaf-sized; internal nodes: mask bytes)
value chunk                (§2 framing when ZIP/BLOSC, else raw)
```

| metadata | name | records | reconstruction of inactive voxels |
|---|---|---|---|
| 0 | no-mask/or-inactive | — | `+background` |
| 1 | no-mask/and-minus-bg | — | `-background` |
| 2 | no-mask/and-one-inactive | one value | that value |
| 3 | mask/and-no-inactive | selection mask | `+/-background` by selection bit |
| 4 | mask/and-one-inactive | one value + mask | value / `+background` |
| 5 | mask/and-two-inactive | two values + mask | value0 / value1 by selection bit |
| 6 | no-mask/and-all-vals | — | full array (no reconstruction) |

Count of stored payload values: `mask.countOn()` when ACTIVE_MASK is set and
`metadata != 6`, otherwise the full node value count (512 for leaves, 4096 /
32768 for internal nodes). Inactive values are written at **logical** width
(4 bytes for a half-storage float grid), while payload values use the
**storage** width (2 bytes when stored as binary16). Reconstructed
`-background` is computed in binary64; a negative zero in a reconstructed
inactive value is therefore not distinguished from positive zero (the raw
storage payload is exposed for exact bits). A reconstructed NaN payload may
canonicalize.

### Supported grid types (element kinds)

| Tree type name | Kind | Logical width | Storage width | Components |
|---|---|---|---|---|
| `Tree_float_5_4_3` | 1 | 4 | 4 | 1 |
| `Tree_float_5_4_3_HalfFloat` | 1 | 4 | 2 | 1 |
| `Tree_double_5_4_3` | 2 | 8 | 8 | 1 |
| `Tree_half_5_4_3` | 3 | 2 | 2 | 1 |
| `Tree_vec3s_5_4_3` | 4 | 12 | 12 | 3 |
| `Tree_vec3s_5_4_3_HalfFloat` | 4 | 12 | 6 | 3 |
| `Tree_vec3d_5_4_3` | 5 | 24 | 24 | 3 |

Halfs are promoted exactly (sign/exp/mantissa widening; subnormals via
`man * 2^-24`, NaN payloads preserved). Any other registered tree type
(`Tree_bool_5_4_3`, int trees, `Tree_pointdata...`, …) is available for
enumeration but `vdb_grid_tree` returns `UNSUPPORTED_GRID_TYPE`.

## 7. Data model (all types exported)

`VdbError = { code: Int; message: Str }` — `code` is one of the
`VDB_ERR_*` constants (§8); messages are stable strings of the form
`"vdb: ..."`.

`VdbHeader = { file_version; library_major; library_minor;
has_grid_offsets: Bool; uuid: Str }`

`VdbMetaMap = { count: Int; names: Vec[Str]; types: Vec[Str];
value_offsets: Vec[Int]; value_bytes: Vec[Int]; end: Int }`

`VdbFile = { header: VdbHeader; meta: VdbMetaMap; grid_count: Int;
unique_names / names / types / instance_parents: Vec[Str];
grid_pos / block_pos / end_pos / body_offsets: Vec[Int] }` — `body_offsets`
is the absolute offset of each grid body (compression flags); for seekable
images it equals the stored grid position.

`VdbTransform = { map_type: Str; map_kind: Int; voxel_size: Vec[Float64];
translation: Vec[Float64]; map_offset: Int; map_end: Int }`

`VdbTree = { grid_index: Int; element_kind: Int; from_half: Bool;
components: Int; compression: Int; leaf_count: Int; origins: Vec[Int];
buffer_offsets: Vec[Int]; background: Vec[Float64];
background_bits: Vec[Int]; root_tile_count: Int; root_child_count: Int;
topology_offset / topology_end / buffers_offset / buffers_end: Int }` —
`origins` holds 3 values per leaf, `buffer_offsets` one value per leaf
(absolute offset of the leaf's 64-byte mask in the buffers section).

`VdbLeaf = { leaf_index: Int; origin: Vec[Int]; active: Vec[UInt8];
metadata: Int; value_count: Int; components: Int; element_kind: Int;
from_half: Bool; logical_width: Int; payload_width: Int;
payload: Vec[UInt8]; values: Vec[Float64] }` — `values` has
`value_count * components` entries, component-interleaved, indexed by local
offset `x*64 + y*8 + z`; `payload` is the decompressed stored payload
(active values only when mask compression applies).

`VdbVoxel = { found: Bool; active: Bool; components: Int;
values: Vec[Float64] }` — `found == false` means no leaf contains the
coordinate (background domain); it is not an error.

## 8. Public function surface (37 functions)

Container / header:

| Function | Returns |
|---|---|
| `vdb_magic_ok(data)` | `Bool` — first 8 bytes carry the zero-extended magic |
| `vdb_parse_header(data)` | `Result[VdbHeader, VdbError]` |
| `vdb_open(data)` | `Result[VdbFile, VdbError]` |
| `vdb_grid_count(f)` | `Int` |
| `vdb_grid_name(f, i)` | stripped name; `""` out of range |
| `vdb_grid_unique_name(f, i)` | raw stored name; `""` out of range |
| `vdb_grid_type(f, i)` | raw tree type name; `""` out of range |
| `vdb_grid_instance_parent(f, i)` | `""` when not an instance |
| `vdb_grid_pos(f, i)` / `vdb_grid_block_pos(f, i)` / `vdb_grid_end_pos(f, i)` | stored positions (0 when streamed); `-1` out of range |
| `vdb_grid_body_offset(f, i)` | absolute body offset; `-1` out of range |
| `vdb_find_grid(f, name)` | first index matching unique or stripped name; `-1` |

Grid sections:

| Function | Returns |
|---|---|
| `vdb_grid_meta(data, f, i)` | `Result[VdbMetaMap, VdbError]` (instance grids included) |
| `vdb_grid_transform(data, f, i)` | `Result[VdbTransform, VdbError]` (instance grids included) |
| `vdb_grid_tree(data, f, i)` | `Result[VdbTree, VdbError]` — instance grids are `INSTANCE_GRID` |

Metadata:

| Function | Returns |
|---|---|
| `vdb_meta_count(m)` | `Int` |
| `vdb_meta_name(m, i)` / `vdb_meta_type(m, i)` | `""` out of range |
| `vdb_meta_value_offset(m, i)` / `vdb_meta_value_bytes(m, i)` | `-1` out of range |
| `vdb_meta_find(m, name)` | `-1` when absent |
| `vdb_meta_value(data, m, i)` | `Result[Vec[UInt8], VdbError]` — raw copy |
| `vdb_meta_string(data, m, i)` | `Result[Str, VdbError]` ("string") |
| `vdb_meta_int(data, m, i)` | `Result[Int, VdbError]` ("int32"/"int64"/"bool") |
| `vdb_meta_bool(data, m, i)` | `Result[Bool, VdbError]` ("bool") |
| `vdb_meta_float(data, m, i)` | `Result[Float64, VdbError]` ("float"/"double") |

Leaves and voxels:

| Function | Returns |
|---|---|
| `vdb_read_leaf(data, tree, leaf_index)` | `Result[VdbLeaf, VdbError]` |
| `vdb_find_leaf(tree, x, y, z)` | leaf index or `-1` (linear; documented minimal-reader behaviour) |
| `vdb_leaf_contains(leaf, x, y, z)` | `Bool` |
| `vdb_leaf_voxel_offset(leaf, x, y, z)` | local offset or `-1` |
| `vdb_leaf_is_active(leaf, x, y, z)` | `Bool` (false out of range) |
| `vdb_leaf_active_count(leaf)` | `Int` |
| `vdb_leaf_component(leaf, x, y, z, c)` | `Result[Float64, VdbError]` |
| `vdb_read_voxel(data, tree, x, y, z)` | `Result[VdbVoxel, VdbError]` |

Inflate (pure XIOM RFC 1950/1951, exposed for reuse and testing):

| Function | Returns |
|---|---|
| `vdb_adler32(data)` | `Int` (mod 65521) |
| `vdb_zip_inflate(zdata, expected)` | `Result[Vec[UInt8], VdbError]` — full zlib stream, exact output size enforced |

### Constants

- `VDB_MAGIC = 1447313952`, `VDB_HEADER_BYTES = 57`,
  `VDB_FILE_VERSION_MIN = 222`, `VDB_FILE_VERSION_MAX = 225`
- `VDB_COMPRESS_NONE/ZIP/ACTIVE_MASK/BLOSC = 0/1/2/4`
- `VDB_ELEM_F32/F64/F16/VEC3F/VEC3D = 1/2/3/4/5`
- `VDB_LEAF_DIM = 8`, `VDB_LEAF_VOXELS = 512`, `VDB_LEAF_MASK_BYTES = 64`
- `VDB_MAP_KIND_SCALE/SCALE_TRANSLATE/TRANSLATION/AFFINE = 1/2/3/4`
- 17 error codes, below.

## 9. Error catalog

Codes are stable; messages are illustrative excerpts (each code has one
fixed message per call site).

| Code | Constant | Raised for |
|---|---|---|
| 1 | `VDB_ERR_TRUNCATED_HEADER` | image shorter than 57 bytes |
| 2 | `VDB_ERR_BAD_MAGIC` | first 8 bytes not the zero-extended magic |
| 3 | `VDB_ERR_UNSUPPORTED_VERSION` | file version < 222 or > 225 |
| 4 | `VDB_ERR_TRUNCATED` | any declared section extends past the buffer |
| 5 | `VDB_ERR_BAD_NAME` | non-printable name/type/string bytes |
| 6 | `VDB_ERR_LIMIT_EXCEEDED` | count/length beyond a documented cap (§11) |
| 7 | `VDB_ERR_BAD_LAYOUT` | stored positions disagree with the walk; multi-buffer trees |
| 8 | `VDB_ERR_UNSUPPORTED_GRID_TYPE` | tree type not in the supported set |
| 9 | `VDB_ERR_UNSUPPORTED_TRANSFORM` | unknown transform map type |
| 10 | `VDB_ERR_UNSUPPORTED_COMPRESSION` | unknown flag bits; blosc value decode |
| 11 | `VDB_ERR_ZIP_INVALID` | malformed zlib/deflate stream or size mismatch |
| 12 | `VDB_ERR_ZIP_ADLER` | Adler-32 mismatch after inflate |
| 13 | `VDB_ERR_BAD_NODE_DATA` | metadata byte > 6; raw chunk size mismatch |
| 14 | `VDB_ERR_INDEX_OUT_OF_RANGE` | index argument out of range |
| 15 | `VDB_ERR_META_TYPE_MISMATCH` | typed metadata accessor on the wrong type |
| 16 | `VDB_ERR_INSTANCE_GRID` | `vdb_grid_tree` on an instance grid |
| 17 | `VDB_ERR_META_BAD_SIZE` | typed metadata payload has the wrong byte count |

## 10. Fixtures and what is verified

- No `.vdb` file produced by upstream OpenVDB is read by this suite. The
  upstream oracle clone is a **read-only semantic reference** for the layout;
  building upstream (Boost/TBB/Imath/zlib) or installing an OpenVDB Python
  wheel (none available for this platform, attempted and recorded in
  `PROVENANCE.md`) is out of scope for this port. **This limitation is
  explicit: the fixtures are hand-constructed from the documented layout and
  the reader is not claimed to have consumed genuine upstream output.**
- The suite assembles three fixtures byte by byte from the layout above
  (`fx_a`: seekable, 4 grids — mask-compressed density with a dense and a
  sparse/selection-mask leaf, a fully ZIP-compressed grid, an instance grid,
  an empty grid; `fx_b`: streamed, half-storage float grid + vec3f grid with
  two leaves and an AffineMap; `fx_c`: seekable, ZIP + selection-mask sparse
  grid), plus small corruption fixtures.
- The zlib streams embedded in the suite were generated with CPython 3.7's
  `zlib` (an independent implementation) and re-verified byte-for-byte:
  `zlib.compress` (dense/sparse leaf payloads), `compressobj(level=0)` (a
  stored-block stream), `Z_FIXED` strategy (a fixed-Huffman stream) and a
  larger skewed payload (a dynamic-Huffman stream), plus the inflate of the
  empty payload. `vdb_zip_inflate` passes all of them; Adler-32 values are
  pinned from Python (`"" -> 1`, `"123456789" -> 152961502`).
- Half floats, f32/f64 promotion, mask metadata (0 and 3 on leaves, 2 on
  internal nodes), inactive-value reconstruction, chunk framing (raw, raw
  fallback under ZIP/BLOSC flags, zlib), position cross-checks, caps,
  truncation and corrupt-input paths (bad magic, version range, oversized
  and misdeclared positions, metadata byte, unknown flags, corrupt zlib,
  Adler mismatch, blosc value decode) are asserted. 30 checks total.

## 11. Caps (enforced, typed `LIMIT_EXCEEDED`)

| Cap | Value |
|---|---|
| name/type byte length | 4096 |
| metadata items per map | 65536 |
| metadata value bytes | 16 MiB |
| grids per file | 65536 |
| leaves per grid | 1048576 |
| inflate output per chunk | 16 MiB |

## 12. Non-goals (declared, not silently missing)

Writers; spline/render codecs (`.vdb` only); blosc/zstd value decode
(structure only); point-data, bool, mask and integer trees; multi-buffer
(multi-pass) trees; `NonlinearFrustumMap`; file versions < 222 or > 225;
non-little-endian images; exposure of root/internal *tile* values or
internal node structure beyond counts; streamed images containing
unsupported grid types (open refuses because it cannot skip them); UTF-8
names (names are printable-ASCII by contract); negative-zero and NaN-payload
fidelity of *reconstructed* inactive values (raw payload bytes are exposed).

## 13. Compiler notes (v0.64.4)

- The module uses **no `?` operator**: with this toolchain `?` corrupts the
  error payload when the enclosing `Result` payload type differs from the
  callee's (minimally reproduced, see `src/vdb.xi` header and the port
  report). Every propagation is an explicit `is_err` check plus a fresh
  `VdbError` through a leaf constructor.
- No FFI/`unsafe` at all; every byte read is bounds-checked before the
  unchecked widened readers run (B-20/B-23/B-24/B-25 discipline holds by
  construction — there are no foreign pointers in this package).
- Integer overflow wraps (two's complement), which the raw-bit readers rely
  on; `Str` equality goes through `compare.str_compare`.

## 14. Provenance

Independent pure-XIOM implementation; no upstream code vendored or copied.
See `PROVENANCE.md` for the pinned oracle (OpenVDB v13.1.0,
`e26f5a569201d3236e0c30580572101022d3d754`, Apache-2.0), the files consulted
for layout semantics, and the fixture/stream generation record.
