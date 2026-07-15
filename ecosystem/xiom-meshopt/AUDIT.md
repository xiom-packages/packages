# xiom-meshopt — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| meshoptimizer | >= 1.2 | Mesh optimization library (simplification, compression, strip generation) |
| clang/LLVM | >= 14 | C bridge compilation |
| Rust/Cargo | Latest stable | Compiler build (xiomc) |
| xiomc | >= v0.45.3 | XIOM compiler |

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
├── meshopt.xi                  # Module xiom.meshopt — raw FFI + core safe wrappers + constants
├── src/
│   └── meshopt_safe.xi         # Module xiom.meshopt.safe — struct-based pipeline wrappers
├── examples/
│   └── demo_meshopt.xi         # Module xiom.meshopt.demo — compile-time demo
└── AUDIT.md                    # This file
```

## FFI Binding Coverage

### meshopt.xi — Module `xiom.meshopt`

~100 C API functions declared in one `extern "C"` block:

| Category | Functions | Key Functions |
|----------|-----------|---------------|
| Remapping | 5 | meshopt_generateVertexRemap, meshopt_generateVertexRemapMulti, meshopt_generateVertexRemapCustom, meshopt_remapVertexBuffer, meshopt_remapIndexBuffer |
| Filtering | 2 | meshopt_filterIndexBuffer, meshopt_filterIndexBufferMulti |
| Shadow Buffers | 3 | meshopt_generateShadowIndexBuffer, meshopt_generateShadowIndexBufferMulti, meshopt_generatePositionRemap |
| Index Generation | 3 | meshopt_generateAdjacencyIndexBuffer, meshopt_generateTessellationIndexBuffer, meshopt_generateProvokingIndexBuffer |
| Cache Optimization | 3 | meshopt_optimizeVertexCache, meshopt_optimizeVertexCacheStrip, meshopt_optimizeVertexCacheFifo |
| Overdraw | 1 | meshopt_optimizeOverdraw |
| Fetch Optimization | 2 | meshopt_optimizeVertexFetch, meshopt_optimizeVertexFetchRemap |
| Index Encoding | 4 | meshopt_encodeIndexBuffer, meshopt_encodeIndexBufferBound, meshopt_encodeIndexVersion, meshopt_decodeIndexBuffer |
| Index Version | 1 | meshopt_decodeIndexVersion |
| Sequence Encoding | 4 | meshopt_encodeIndexSequence, meshopt_encodeIndexSequenceBound, meshopt_decodeIndexSequence |
| Meshlet Encoding | 4 | meshopt_encodeMeshlet, meshopt_encodeMeshletBound, meshopt_decodeMeshlet, meshopt_decodeMeshletRaw |
| Vertex Encoding | 5 | meshopt_encodeVertexBuffer, meshopt_encodeVertexBufferBound, meshopt_encodeVertexBufferLevel, meshopt_encodeVertexVersion, meshopt_decodeVertexBuffer |
| Vertex Version | 1 | meshopt_decodeVertexVersion |
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

**Total: ~100 extern function declarations.**

### meshopt_safe.xi — Module `xiom.meshopt.safe`

5 struct-based pipeline types (with duplicate inline `extern "C"` block — cross-module resolution is broken in v0.45.3):

| Type | Methods | Contracts |
|------|---------|-----------|
| `RemapPipeline` | build, remap_vertices, remap_indices | requires: pointers != 0, counts > 0 |
| `OptimizePipeline` | init, vertex_cache, vertex_cache_fifo, overdraw, vertex_fetch, vertex_fetch_remap, analyze_vertex_cache, analyze_vertex_fetch | requires: pointers != 0, counts > 0 |
| `SimplifyPipeline` | init, scale, run | requires: pointers != 0, counts > 0; target_count <= index_count |
| `EncodePipeline` | index_bound, encode_indices, vertex_bound, encode_vertices, decode_vertices | requires: pointers != 0, counts > 0 |
| `StripPipeline` | init, bound, stripify | requires: pointers != 0, counts > 0 |

## Compiler Gaps Worked Around

### 1. Cross-module extern resolution (T001)
**Symptom:** `extern "C"` functions declared in module A resolve to `()` when called from module B via `use` import.
**Workaround:** `src/meshopt_safe.xi` duplicates the `extern "C"` block it needs inline.
**Impact:** ~20-line duplicate extern block in meshopt_safe.xi.

### 2. Int→Int32 coercion
**Symptom:** Integer literals (`1`, `0`) default to `Int` and do not auto-coerce to `Int32`.
**Workaround:** Use `as Int32` casts everywhere (e.g., `1 as Int32`).
**Impact:** All constants, enum values, and extern calls with Int32 params use explicit `as Int32`.

### 3. No hex literals
**Symptom:** Hex literals (`0x00000001`) cause parse errors.
**Workaround:** Use decimal values only.
**Impact:** All flag constants are defined in decimal.

### 4. No `()` unit type in Result
**Symptom:** `Result[(), Error]` is not supported.
**Workaround:** Use `Result[Int, MeshoptError]` with `Ok(0)` for success.

### 5. C struct-by-value returns (uncertain status)
**Symptom:** meshoptimizer returns `struct meshopt_Bounds`, `struct meshopt_VertexCacheStatistics`, etc. by value.
**Status:** Declared with corresponding XIOM struct types. If the compiler does not support C struct-by-value returns from extern functions, these functions will fail at link/call time. In that case, C bridge wrappers that write results via out-pointers would be needed.
**Functions affected:** `meshopt_analyzeVertexCache`, `meshopt_analyzeVertexFetch`, `meshopt_analyzeOverdraw`, `meshopt_analyzeCoverage`, `meshopt_computeClusterBounds`, `meshopt_computeMeshletBounds`, `meshopt_computeSphereBounds`.
**Mitigation:** These functions are declared but not called in safe wrappers (except `analyzeVertexCache` and `analyzeVertexFetch` which are used in OptimizePipeline). If the compiler supports them, no action needed. If not, a C shim layer that converts to out-pointer calls would be required.

### 6. Function pointer callback types
**Symptom:** `meshopt_generateVertexRemapCustom` and `meshopt_setAllocator` take C function pointers as parameters.
**Status:** Declared as `Int` (raw pointer). Dynamic function pointer creation from XIOM closures is not yet supported.
**Functions affected:** `meshopt_generateVertexRemapCustom`, `meshopt_setAllocator`.
**Impact:** These functions are callable with `0` (NULL) for the callback, falling back to position-only comparisons. Actual custom callbacks require a C bridge layer.

### 7. No `Float` type verification
**Symptom:** `float` in C maps to `Float` in XIOM; this mapping is assumed but not confirmed against the compiler.
**Status:** If the compiler does not have a `Float` primitive matching C `float` (4 bytes, IEEE 754), all float-based APIs will fail.
**Impact:** ~50 functions use `float` or `float*` parameters.

### 8. `meshopt_Stream` struct and streaming APIs
**Symptom:** Multi-stream functions (`meshopt_generateVertexRemapMulti`, `meshopt_filterIndexBufferMulti`, etc.) take `const struct meshopt_Stream*` which is an array of inline structs.
**Status:** `MeshoptStream` is defined as a XIOM struct type. Passing arrays of structs via FFI requires the struct layout to match C ABI exactly.
**Impact:** If XIOM struct layout does not match C (especially padding), these functions will receive corrupted stream descriptors. Workaround would require a C shim that manually assembles the stream array.

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

## Known Limitations

- meshoptimizer is a pure C library with no runtime requirements — no GPU, Vulkan, or windowing is needed
- 7 of ~100 functions (analysis, bounds) return C structs by value — may need C bridge wrappers depending on compiler support
- Callback-based functions (remap custom, allocator) are declared but only usable with NULL callbacks from XIOM
- Multi-stream APIs require struct layout to match C ABI exactly
- The inline C++ functions (`meshopt_quantizeUnorm`, `meshopt_quantizeSnorm`) are not available via FFI
- Experimental APIs (opacity maps, tangents, filter index buffer) are included but marked as unstable
