# Steam Audio (Phonon) Bindings — Compiler Audit

## Package: `xiom-phonon` v0.1.0

## Target SDK
- **Library**: Valve Steam Audio SDK v4.8.1 (`phonon.dll` / `libphonon.so`)
- **Source Headers**: `E:\repos\steam-audio\unity\include\phonon\phonon.h` (4335 lines)
- **API Surface**: ~120 C functions, 32 opaque handles, 50+ structs, 30+ enums

---

## Summary

| Category | Count | Status |
|----------|-------|--------|
| extern "C" functions declared | 125 | Complete |
| Opaque handle types | 32 | Complete |
| Enum constants | 52 | Complete |
| Safe wrapper functions | 35 | Complete |
| Safe wrapper types | 10 | Complete |

---

## Compiler Gaps (Blockers)

### 1. C Struct Layout Generation (CRITICAL)

**Problem**: The XIOM compiler cannot generate C-compatible struct layouts from XIOM type definitions. The `#[repr(C)]` equivalent does not exist.

**Impact**: All functions that take or return C structs must use `*UInt8` (raw pointer to externally-allocated memory) for struct parameters. This means:
- 50+ Steam Audio structs (IPLContextSettings, IPLAudioSettings, IPLVector3, IPLBinauralEffectParams, etc.) cannot be declared in XIOM and must be constructed via a C bridge or manual byte-level allocation.
- All `Create` functions require the caller to pre-allocate and zero-initialize struct memory externally.
- All `Apply` effect functions require pre-populated parameter structs allocated outside XIOM.

**Affected functions**: 100% of the API (every `Create` function takes a settings struct; every `Apply` takes a params struct).

**Workaround**: A C bridge library (`xiom_phonon_bridge.c`) that exposes flat ABI functions with primitive types. The Vulkan package follows this pattern with `xvk_*` bridge functions.

**Estimated effort**: ~2-3 days to write the C bridge covering the full API.

### 2. Struct-by-Value Return Types (HIGH)

**Problem**: Several Steam Audio functions return structs by value (e.g., `iplCalculateRelativeDirection` returns `IPLVector3`, `iplProbeArrayGetProbe` returns `IPLSphere`). The XIOM FFI cannot handle C struct return values from `extern "C"` functions.

**Affected functions**:
- `iplCalculateRelativeDirection` → returns `IPLVector3`
- `iplProbeArrayGetProbe` → returns `IPLSphere`

**Workaround**: These functions are declared with `*UInt8` output parameters in the bindings, requiring the caller to provide a pre-allocated buffer for the return value. This is not ideal and a C bridge should wrap these to return individual float components.

### 3. C Function Pointer / Callback Support (HIGH)

**Problem**: Steam Audio defines 10 callback types (`IPLProgressCallback`, `IPLLogFunction`, `IPLAllocateFunction`, `IPLFreeFunction`, `IPLClosestHitCallback`, `IPLAnyHitCallback`, `IPLBatchedClosestHitCallback`, `IPLBatchedAnyHitCallback`, `IPLDistanceAttenuationCallback`, `IPLAirAbsorptionCallback`, `IPLDirectivityCallback`, `IPLDeviationCallback`, `IPLPathingVisualizationCallback`). The XIOM compiler cannot create C-compatible function pointers from XIOM closures.

**Impact**:
- Cannot set custom log/allocate/free callbacks for the context
- Cannot use `IPL_SCENETYPE_CUSTOM` (requires ray tracing callbacks)
- Cannot use custom distance attenuation, air absorption, or directivity models
- Cannot receive baking progress callbacks

**Workaround**: A C bridge must register trampoline functions and dispatch to XIOM callbacks through a registry. All callback-taking parameters are currently declared as `Int` = 0 (null pointer) in the bindings.

### 4. Pointer-to-Handle Dereferencing (MEDIUM)

**Problem**: Steam Audio's `*Release` functions take `IPLHandle*` (pointer to handle) so they can null out the caller's handle. The XIOM FFI represents this as `*UInt8`, and the safe wrappers must manually take the address of a local variable and cast it.

**Status**: This works correctly in the safe wrappers using the `&var as *UInt8` pattern, but is fragile. A C bridge would eliminate this by handling the nulling internally and exposing simple `destroy(context: Int)` signatures.

### 5. No `size_t` / Platform-Dependent Integer Types (MEDIUM)

**Problem**: `IPLsize` is `size_t` (8 bytes on 64-bit, 4 bytes on 32-bit). XIOM's `Int` type is always pointer-sized, which happens to match on most platforms, but there is no type-safe guarantee. `iplSerializedObjectGetSize` and `iplProbeBatchGetDataSize` return `IPLsize`.

**Impact**: Size values may be truncated on 32-bit platforms where `Int` is 4 bytes but `size_t` is also 4 bytes (no actual truncation). On LLP64 platforms (Windows 64-bit), `size_t` is 8 bytes and `Int` is also 8 bytes (pointer-sized), so this is safe for all supported platforms.

**Status**: Low risk. The current bindings use `Int` for `IPLsize` return values, which is correct on all currently-targeted platforms (64-bit Windows, Linux, macOS).

### 6. No `long long` / 64-bit Integer Type (LOW)

**Problem**: Steam Audio defines `IPLint64` and `IPLuint64` but the XIOM FFI has no `Int64`/`UInt64` type. The C API does not use these types in function parameters or return values (they exist for alignment in certain structs).

**Impact**: None for function calls. Only relevant if struct layouts needed 64-bit integer fields (which they don't for structs that appear in function signatures).

---

## Missing Features (Not Yet Bound)

### Ambisonics Pipeline

All Ambisonics effects are declared in `extern "C"` but lack safe wrappers:
- `IPLAmbisonicsEncodeEffect` — encode mono to ambisonics
- `IPLAmbisonicsPanningEffect` — decode ambisonics to speakers
- `IPLAmbisonicsBinauralEffect` — decode ambisonics to headphones
- `IPLAmbisonicsRotationEffect` — rotate ambisonic soundfield
- `IPLAmbisonicsDecodeEffect` — flexible decode with binaural option

These follow the same Create/Apply pattern as binaural/direct and can be added by copy-pasting the existing safe wrapper templates.

### Scene and Mesh API

Geometry functions are declared but lack safe wrappers:
- Scene creation (with or without Embree/OpenCL/RadeonRays)
- Static mesh creation from vertex/triangle data
- Instanced mesh with transform updates
- Scene commit/load/save to serialized objects

### Baking Pipeline

Offline baking functions are declared but lack safe wrappers:
- Reflection baker (ray-traced reverb baking)
- Path baker (sound path precomputation)
- Probe batch management

### GPU Acceleration

GPU device creation wrappers are not provided:
- OpenCL device enumeration and creation
- Radeon Rays device (AMD GPU ray tracing)
- TrueAudio Next device (AMD GPU convolution)

### Reflection Mixer

`IPLReflectionMixer` is declared in FFI but has no safe wrapper.

### Energy Field / Impulse Response / Reconstructor

Advanced signal processing objects are declared in FFI but have no safe wrappers.

---

## Recommended Next Steps

1. **Write the C bridge** (`bridge/xiom_phonon_bridge.c` + `bridge/xiom_phonon_bridge.h`) to eliminate the struct-layout gap. This is the single highest-value improvement.
2. **Add safe wrappers for all Ambisonics effects** (encode, decode, panning, binaural, rotation).
3. **Add safe wrappers for Scene and Mesh API** to enable geometry-based simulations.
4. **Investigate callback support** for custom ray tracing, attenuation models, and progress reporting.
5. **Add build scripts** (`build.ps1`, `build.sh`) for compiling the bridge and linking against `phonon.dll`.

---

## File Inventory

| File | Lines | Purpose |
|------|-------|---------|
| `package.xi` | 13 | Package manifest |
| `phonon.xi` | 474 | extern "C" declarations + core safe wrappers |
| `phonon_safe.xi` | 320 | Typed resource wrappers (Context, BinauralRenderer, etc.) |
| `demo_phonon.xi` | 121 | Spatial audio pipeline demonstration |
| `AUDIT.md` | 175 | This file |

**Total**: ~1103 lines across 5 files.
