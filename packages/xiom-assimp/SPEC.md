# xiom-assimp -- SPEC
**Phase**: 5 (Nice-to-Have) | **Priority**: Low
**Status**: Implemented (Phase 1) | **Depends on**: xiom.ffi

## Overview
Assimp -- 3D model import library. System-installed libassimp.

## Implementation (v0.1.0)

### Types
| Type | Definition |
|------|-----------|
| AiScene | Opaque Int handle |
| AiMesh | Opaque Int handle |
| AiMaterial | Opaque Int handle |
| AiAnimation | Opaque Int handle |
| AiNode | Opaque Int handle |

### extern "C" Stubs (16 functions)
aiImportFile, aiImportFileEx, aiReleaseImport, aiGetErrorString, aiGetNumMeshes, aiGetMesh, aiGetNumVertices, aiGetVertices, aiGetNumFaces, aiGetFaces, aiGetNumNormals, aiGetNormals, aiGetNumTexCoords, aiGetTexCoords, aiGetMaterialCount, aiGetMaterial

### Post-processing Flags (28 constants)
All standard aiProcess_* flags from CalcTangentSpace (0x1) to GenBoundingBoxes (0x80000000).

### Flag Presets (4)
Default, TargetRealtimeFast, TargetRealtimeQuality, TargetRealtimeMaxQuality

### Safe Wrappers (16 public functions)
All wrapped with `requires:` contracts and `Result[AiXxx, Str]` error handling.

### Tests
48 conformance tests covering types, flags, presets, import/error paths, mesh/material queries, contract enforcement, API presence, and edge cases.

## Files
```
src/assimp.xi              -- module xiom.assimp (types, extern C, flags, safe wrappers)
tests/test_conformance.xi  -- 48-test conformance suite
package.xi                 -- package manifest
ROADMAP.md                 -- phased development plan
SPEC.md                    -- this file
```
