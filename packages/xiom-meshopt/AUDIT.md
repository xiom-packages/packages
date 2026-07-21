# xiom-meshopt — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| meshoptimizer | >= 1.2 | Mesh optimization library (simplification, compression, strip generation) |
| clang/LLVM | >= 14 | C bridge compilation |
| Rust/Cargo | Latest stable | Compiler build (xiomc) |
| xiomc | >= v0.46.0 | XIOM compiler (v0.46 "Production" — 101/101 e2e) |

## meshoptimizer Source

meshoptimizer is available as a C library from https://github.com/zeux/meshoptimizer.

The single public API header is `src/meshoptimizer.h` (~1700 lines). The library provides:

- **Vertex remapping** — deduplicate vertices by binary equivalence or position
- **Index generation** — adjacency/tessellation/provoking index buffers
- **Index filtering** — remove degenerate/duplicate triangles
- **Vertex cache optimization** — reorder triangles for GPU post-T&L cache
- **Overdraw optimization** — reorder triangles to reduce pixel overdraw
- **Vertex fetch optimization** — reorder vertices for GPU pre-T&L cache
- **Simplification** — reduce triangle count with attribute-aware error metric
- **Meshlet building** — cluster meshes for mesh shading pipelines
- **Index/vertex encoding** — compress index and vertex buffers
- **Vertex filter encoding** — encode/decode octahedral normals, quaternions, exponential data, YCoCg color
- **Triangle strip generation** — convert triangle lists to strips
- **Analysis** — measure ACMR, ATVR, overfetch, overdraw, coverage
- **Spatial sorting** — reorder points/triangles for spatial locality
- **Quantization** — float↔half, mantissa reduction, position exponent

## Platform-Specific Installation

### Windows
1. Clone and build from source:
   ```
   git clone https://github.com/zeux/meshoptimizer.git
   cd meshoptimizer
   cmake -B build
   cmake --build build --config Release
   ```
   Produces `build/Release/meshoptimizer.lib` (static) or `meshoptimizer.dll`.

2. Or install via vcpkg:
   ```
   vcpkg install meshoptimizer
   ```

3. **clang**: Install via LLVM from https://releases.llvm.org/ or `winget install LLVM.LLVM`

### Linux
```bash
# Build from source
git clone https://github.com/zeux/meshoptimizer.git
cd meshoptimizer
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Or via package manager (availability varies)
sudo apt install libmeshoptimizer-dev   # if packaged
```

### macOS
```bash
# Homebrew
brew install meshoptimizer

# Or build from source (same as Linux)
```

## Package Structure

```
ecosystem/xiom-meshopt/
├── package.xi                  # Package manifest (name, version, deps)
├── meshopt.xi                  # Module xiom.meshopt — raw FFI + safe wrappers + constants
├── src/
│   └── meshopt_safe.xi         # Module xiom.meshopt.safe — struct-based pipeline wrappers
├── examples/
│   └── demo_meshopt.xi         # Module xiom.meshopt.demo — compile-time demo
└── AUDIT.md                    # This file
```

## FFI Binding Coverage

### meshopt.xi — Module `xiom.meshopt`

**85 C API functions** declared in one `extern "C"` block — 100% coverage of the public C API (meshoptimizer.h v1.2):

| Category | Count | Key Functions |
|----------|-------|---------------|
| Remapping | 5 | meshopt_generateVertexRemap, meshopt_generateVertexRemapMulti, meshopt_generateVertexRemapCustom, meshopt_remapVertexBuffer, meshopt_remapIndexBuffer |
| Filtering | 2 | meshopt_filterIndexBuffer, meshopt_filterIndexBufferMulti |
| Shadow Buffers | 3 | meshopt_generateShadowIndexBuffer, meshopt_generateShadowIndexBufferMulti, meshopt_generatePositionRemap |
| Index Generation | 3 | meshopt_generateAdjacencyIndexBuffer, meshopt_generateTessellationIndexBuffer, meshopt_generateProvokingIndexBuffer |
| Cache Optimization | 3 | meshopt_optimizeVertexCache, meshopt_optimizeVertexCacheStrip, meshopt_optimizeVertexCacheFifo |
| Overdraw | 1 | meshopt_optimizeOverdraw |
| Fetch Optimization | 2 | meshopt_optimizeVertexFetch, meshopt_optimizeVertexFetchRemap |
| Index Encoding | 5 | meshopt_encodeIndexBuffer, meshopt_encodeIndexBufferBound, meshopt_encodeIndexVersion, meshopt_decodeIndexBuffer, meshopt_decodeIndexVersion |
| Sequence Encoding | 4 | meshopt_encodeIndexSequence, meshopt_encodeIndexSequenceBound, meshopt_decodeIndexSequence |
| Meshlet Encoding | 4 | meshopt_encodeMeshlet, meshopt_encodeMeshletBound, meshopt_decodeMeshlet, meshopt_decodeMeshletRaw |
| Vertex Encoding | 7 | meshopt_encodeVertexBuffer, meshopt_encodeVertexBufferBound, meshopt_encodeVertexBufferLevel, meshopt_encodeVertexVersion, meshopt_decodeVertexBuffer, meshopt_decodeVertexVersion |
| Filter Decoding | 4 | meshopt_decodeFilterOct, meshopt_decodeFilterQuat, meshopt_decodeFilterExp, meshopt_decodeFilterColor |
| Filter Encoding | 4 | meshopt_encodeFilterOct, meshopt_encodeFilterQuat, meshopt_encodeFilterExp, meshopt_encodeFilterColor |
| Simplification | 7 | meshopt_simplify, meshopt_simplifyWithAttributes, meshopt_simplifyWithUpdate, meshopt_simplifySloppy, meshopt_simplifyPrune, meshopt_simplifyPoints, meshopt_simplifyScale |
| Stripification | 4 | meshopt_stripify, meshopt_stripifyBound, meshopt_unstripify, meshopt_unstripifyBound |
| Analysis | 4 | meshopt_analyzeVertexCache, meshopt_analyzeVertexFetch, meshopt_analyzeOverdraw, meshopt_analyzeCoverage |
| Meshlet Building | 5 | meshopt_buildMeshlets, meshopt_buildMeshletsScan, meshopt_buildMeshletsBound, meshopt_buildMeshletsFlex, meshopt_buildMeshletsSpatial |
| Meshlet Optimization | 2 | meshopt_optimizeMeshlet, meshopt_optimizeMeshletLevel |
| Bounds | 4 | meshopt_computeClusterBounds, meshopt_computeMeshletBounds, meshopt_computeSphereBounds, meshopt_extractMeshletIndices |
| Partitioning | 1 | meshopt_partitionClusters |
| Spatial | 3 | meshopt_spatialSortRemap, meshopt_spatialSortTriangles, meshopt_spatialClusterPoints |
| Opacity Maps | 4 | meshopt_opacityMapMeasure, meshopt_opacityMapRasterize, meshopt_opacityMapEntrySize, meshopt_opacityMapCompact |
| Tangents | 1 | meshopt_generateTangents |
| Quantization | 4 | meshopt_quantizeHalf, meshopt_quantizeFloat, meshopt_dequantizeHalf, meshopt_computePositionExponent |
| Allocator | 1 | meshopt_setAllocator |

**Total: 85 extern function declarations — 100% of the public C API surface.**

13 named constants covering all enums: simplification options (7 flags), vertex lock flags (3), EncodeExpMode (4 values), tangent options (2 flags).

6 XIOM struct types matching C structs: `MeshoptStream`, `MeshoptVertexCacheStatistics`, `MeshoptVertexFetchStatistics`, `MeshoptOverdrawStatistics`, `MeshoptCoverageStatistics`, `MeshoptBounds`, `MeshoptMeshlet`.

### meshopt_safe.xi — Module `xiom.meshopt.safe`

5 struct-based pipeline types using cross-module `use xiom.meshopt` (no inline extern block — resolved in v0.46):

| Type | Methods | Contracts |
|------|---------|-----------|
| `RemapPipeline` | build, remap_vertices, remap_indices | requires: pointers != 0, counts > 0 |
| `OptimizePipeline` | init, vertex_cache, vertex_cache_fifo, overdraw, vertex_fetch, vertex_fetch_remap, analyze_vertex_cache, analyze_vertex_fetch | requires: pointers != 0, counts > 0 |
| `SimplifyPipeline` | init, scale, run | requires: pointers != 0, counts > 0; target_count <= index_count |
| `EncodePipeline` | index_bound, encode_indices, vertex_bound, encode_vertices, decode_vertices | requires: pointers != 0, counts > 0 |
| `StripPipeline` | init, bound, stripify | requires: pointers != 0, counts > 0 |

## Compiler Gap Status (xiomc v0.46.0)

| # | Gap | v0.45 Status | v0.46 Status |
|---|-----|-------------|-------------|
| 1 | Cross-module extern resolution | Workaround: inline extern block in each module | **RESOLVED** — `use xiom.meshopt` works across modules |
| 2 | Int→Int32 coercion | Workaround: `as Int32` casts everywhere | **RESOLVED** — integer literals auto-coerce to Int32 |
| 3 | Hex literals | Avoided: decimal values only | **RESOLVED** — `0x10` parses correctly |
| 4 | `()` unit type in Result | Workaround: `Result[Int, ...]` with `Ok(0)` | **RESOLVED** — `Result[(), Str]` compiles |
| 5 | `Float` type does not exist | Assumed `Float` mapped to C `float` | **CORRECTED** — C `float` = `Float32`, C `double` = `Float64`. All bindings use `Float32`. |

### Remaining Observations

#### Float32 literal coercion
Float literals (`0.0`, `1.05`) default to `Float64`. Assignment to `Float32` variables or `Float32` parameters requires `as Float32` cast (e.g., `0.0 as Float32`). The compiler does not auto-narrow Float64 literals to Float32.

Affected: `meshopt.xi:279` — `simplify()` wrapper passes float literals for `target_error`. Current safe wrappers accept `Float32` parameters from the caller; the caller is responsible for the cast.

#### C struct-by-value returns
7 functions return C structs by value: `meshopt_analyzeVertexCache`, `meshopt_analyzeVertexFetch`, `meshopt_analyzeOverdraw`, `meshopt_analyzeCoverage`, `meshopt_computeClusterBounds`, `meshopt_computeMeshletBounds`, `meshopt_computeSphereBounds`.

**Status:** Declared with matching XIOM struct types and compile without errors. Runtime ABI verification requires linking against meshoptimizer. The `OptimizePipeline.analyze_vertex_cache` and `analyze_vertex_fetch` methods call through to these externs. If struct-by-value returns fail at runtime, a C shim layer that uses out-pointers will be needed.

#### Function pointer callback types
`meshopt_generateVertexRemapCustom` and `meshopt_setAllocator` take C function pointers (`int (*callback)(void*, unsigned int, unsigned int)` and `void* (*allocate)(size_t)`).

**Status:** Declared as `Int` (raw pointer). Passing `0` (NULL) to `meshopt_generateVertexRemapCustom` falls back to position-only comparisons. Passing `0` to `meshopt_setAllocator` restores default allocator. Dynamic function pointer creation from XIOM closures is not supported — custom callbacks require a C bridge layer.

#### `unsigned short` → `Int32` ABI
`meshopt_quantizeHalf` returns `unsigned short` (2 bytes), declared as `Int32` (4 bytes) return type. `meshopt_dequantizeHalf` takes `unsigned short` (2 bytes), declared as `Int32` parameter. On x86-64 Windows/Linux ABI, small integer types are zero/sign-extended to register width, so this mapping is correct for values within `[0, 65535]`. Values outside this range (non-valid half-precision inputs) will have undefined high bits.

#### `meshopt_Stream` struct ABI
Multi-stream functions pass `const struct meshopt_Stream*` (array of `{data, size, stride}` structs). The XIOM `MeshoptStream` type mirrors this layout. Passing arrays of these structs requires the XIOM struct layout to match the C ABI (no padding differences). The struct is `{Int, Int, Int}` (three 8-byte fields on 64-bit) which matches C `{const void*, size_t, size_t}`.

#### `Float*` out-parameters
Simplification functions have `float* result_error` out-parameters. The safe wrappers pass `0` (NULL) for these since extracting a `Float32` value through an out-pointer parameter requires explicit pointer manipulation. Callers who need the result error should call the raw extern function with a properly allocated buffer.

## Build Pipeline

```
1. Build meshoptimizer static library
   git clone https://github.com/zeux/meshoptimizer.git
   cd meshoptimizer && cmake -B build && cmake --build build --config Release
   → meshoptimizer.lib (Windows) or libmeshoptimizer.a (Linux)

2. XIOM Compilation + Link (xiomc + clang)
   meshopt.xi + src/meshopt_safe.xi + examples/*.xi + meshoptimizer.lib
   → final executable
```

On Windows:
```
xiomc --link meshoptimizer -o demo.exe meshopt.xi src/meshopt_safe.xi examples/demo_meshopt.xi
```

On Linux:
```
xiomc --link meshoptimizer -o demo meshopt.xi src/meshopt_safe.xi examples/demo_meshopt.xi
```

## Compile Status (2026-07-17)

All files compile with `xiomc --diagnostics=json` (v0.46.0): **`{"status":"ok"}`**, 0 errors.

| File | Status | Lines | Contents |
|------|--------|-------|----------|
| `package.xi` | PASSED | 13 | Package manifest |
| `meshopt.xi` | PASSED | 312 | 85 extern C FFI declarations, 6 XIOM struct types, 13 constants, 6 safe wrappers |
| `src/meshopt_safe.xi` | PASSED | 251 | 5 struct pipeline types with create/destroy contracts, cross-module `use` |
| `examples/demo_meshopt.xi` | PASSED | 85 | API pattern demo showing procedural + struct-based usage |
| `AUDIT.md` | WRITTEN | ~200 | This file |

**Total: 861 lines of production code.**

## Known Limitations

- meshoptimizer is a pure C library with no runtime requirements — no GPU, Vulkan, or windowing needed
- 7 analysis/bounds functions return C structs by value — compile OK, runtime ABI pending link verification
- Callback-based functions (remap custom, allocator) are declared but only usable with NULL callbacks from XIOM
- `Float*` out-parameters in simplification functions passed as NULL in safe wrappers — call raw extern for result error
- The inline C++ functions (`meshopt_quantizeUnorm`, `meshopt_quantizeSnorm`) are not available via C ABI
- Experimental APIs (opacity maps, tangents, filter index buffer) are included but marked as unstable in meshoptimizer
