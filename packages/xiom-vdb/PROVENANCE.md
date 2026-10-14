# PROVENANCE: xiom.vdb

Upstream-first record (owner policy 2026-10-11, `docs/UPSTREAM-FIRST.md`).
This package itself is an **EXPLICITLY INDEPENDENT declaration: no vendored
upstream code, no translated code, no generated code.** It is a pure-XIOM,
from-scratch reader for the OpenVDB container format.

## Upstream

| Field | Value |
|-------|-------|
| Project | OpenVDB (AcademySoftwareFoundation/OpenVDB) |
| Repository | https://github.com/AcademySoftwareFoundation/openvdb |
| Pinned commit | `e26f5a569201d3236e0c30580572101022d3d754` (v13.1.0) |
| License | Apache License 2.0 (`LICENSE` at the pinned commit); MPL-2.0 files are excluded from scope and were not consulted |
| Clone | `E:\repos\OpenVDB` at the pin (read-only oracle; cleanup ledger row exists, owned by the coordinator — this package does not edit the shared ledger) |

## Oracle source (semantic reference only)

The pinned clone was read to establish the byte-level layout of the
following, and only the following, artifacts. **No source text was copied;
only the format semantics were extracted** (field order, widths, framing and
reconstruction rules), then re-implemented independently in XIOM:

- `openvdb/openvdb/version.h.in` — magic value, file version constants
  (222..225), library version fields;
- `openvdb/openvdb/io/Archive.cc`, `io/File.cc`, `io/Stream.cc` —
  header/meta/grid-count/descriptor-table ordering, seekable vs streamed
  layout, per-grid section order;
- `openvdb/openvdb/io/GridDescriptor.cc/.h`, `util/Name.h` — length-prefixed
  strings, `_HalfFloat` type suffix, three i64 stream positions;
- `openvdb/openvdb/io/Compression.h/.cc` — compression flags, zip/blosc i64
  chunk framing and raw fallback, the mask-compression metadata byte table,
  inactive-value and selection-mask records, half storage widths;
- `openvdb/openvdb/util/NodeMasks.h` — mask word packing;
- `openvdb/openvdb/tree/RootNode.h`, `InternalNode.h`, `LeafNode.h`,
  `Tree.h`, `Iterator.h` — topology order (depth-first, offset-ascending
  children), implicit leaf origins, 5/4/3 node chain and dimensions;
- `openvdb/openvdb/io/io.h`, `openvdb/openvdb/MetaMap.cc`,
  `openvdb/openvdb/Metadata.h` — MetaMap and metadata value layout;
- `openvdb/openvdb/math/Transform.cc`, `math/Maps.h`, `math/NodeMasks.h` —
  transform type names and fixed map payload sizes;
- `openvdb/openvdb/openvdb.cc`, `openvdb/openvdb/openvdb.h`,
  `openvdb/openvdb/Types.h` — registered tree type names and element
  geometry (`Tree_float_5_4_3`, `Tree_vec3s_5_4_3`, …).

No upstream implementation source (tree algorithms, tools, points, nanovdb,
renderers) was read or re-implemented; this package reads the file container
only, exactly as declared in `SPEC.md` §12.

## Derived vs independent

- **Nothing is copied from upstream.** The file layout facts reproduced here
  are the container's interoperability surface (magic, field order, widths,
  framing), reproduced from the pinned source as a specification, not as
  code. The XIOM implementation was written from scratch after the format
  notes above; it shares no identifiers, structure or text with OpenVDB.
- The zlib/deflate implementation (RFC 1950/1951) and Adler-32 are likewise
  implemented from the public RFCs, with no upstream zlib or OpenVDB code.

## Fixture provenance (honest record)

- **No .vdb file produced by upstream OpenVDB is read by the test suite.**
  Building upstream (Boost/TBB/Imath/zlib) is out of scope for this port,
  and no OpenVDB Python wheel exists for this platform: `pip install openvdb`
  on CPython 3.12/win_amd64 was attempted on 2026-10-13 and failed with
  "No matching distribution found for openvdb". No earlier version of
  OpenVDB output was read either.
- The suite therefore assembles fixtures **byte by byte from the documented
  layout** (test-local writer, no shared code with `src/vdb.xi`) and marks
  all format expectations as documented-layout-verified in `SPEC.md` §10.
  If a future port gains access to upstream output, the fixtures should be
  extended with an oracle-file regression test.
- The embedded zlib streams were generated with **CPython 3.7 `zlib`** (an
  independent implementation of RFC 1950/1951): `zlib.compress(payload, 6)`
  for the dense (2048 B -> 76 B) and sparse (684 B -> 38 B) leaf payloads,
  `compressobj(0)` (stored blocks, 32 B), `Z_FIXED` strategy (fixed
  Huffman, 28 B) and a skewed 200 B payload (dynamic Huffman, 161 B); the
  empty payload compresses to 8 B. Every stream was decompressed in Python
  and compared with its expected payload at generation time, and the byte
  arrays embedded in `tests/test_conformance.xi` were re-verified against
  the generator afterwards. Pinned Adler-32 values: `"" -> 1`,
  `"123456789" -> 152961502`, the 200-byte dynamic payload -> 3366075432.

## Tooling note

The reader was developed against XIOM v0.64.4
(`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`, stdlib `E:\xiom-lang\stdlib`) as a
read-only consumer. The `?`-propagation defect documented in `SPEC.md` §13
was found and minimally reproduced while building this package (explicit
unpack/rewrap is used throughout instead).
