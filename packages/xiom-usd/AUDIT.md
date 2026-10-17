# AUDIT: xiom.usd

## Status (2026-10-17)

| Item | State |
|------|-------|
| Version | 0.1.0 (declared surface complete) |
| Compiler | v0.64.6 |
| Upstream pin | OpenUSD **v26.08** commit `ee47c679abde5b467a7b6a41f3b2285564a4222e`; TOST-1.0 |
| Runtime | `usd-core` 26.8 cp311 win_amd64 wheel, sha256 `D39CEF20...578F`; `usd_ms.dll` |
| Link model | **none**: local x64 trampolines; no import library, no delay-load flag; process starts without USD |
| FFI confinement | all `unsafe` + FFI calls in `xiom.usd`; the C bridge is the only C++ |
| Data ABI shim | local Sdf pool arrays (mirrored), local `UsdPrimDefaultPredicate`, disabled `TfMallocTag` init |
| C ABI surface | **58** functions; `usdbridge_resolve_all` is internal; suite asserts equality |
| Public surface | **100%** implemented, mapped in `docs/COVERAGE.md` |
| Suite | `tests/test_conformance.xi`, **65 checks**, 65/65 green on the pin; typed SKIP when absent |
| Platform | Windows x64 |

## Runtime verification

The positive path uses the official wheel unpacked at
`E:/repos/usd-core/wheel/pxr` plus the Python 3.11.9 embeddable runtime.
The suite exercises:

- loader: absent dir -> typed `RUNTIME_ABSENT`; wheel bound -> `usd_ms.dll`,
  ABI 2608;
- traversal/prim read, mesh extraction, material binding/surface/inputs/
  connections, time samples, typed mesh/material/path errors, empty stage,
  stale-handle and stage-close invalidation;
- negative double (`-1.5`) and negative `point3f` components (the sign-bit
  path of the F64 decoder).

Run record: `scripts/port.ps1 -Package xiom.usd -TimeoutSec 300`, x2,
65 passed / 0 failed (both runs). The absent-runtime shape is same-binary:
the executable has no `usd_ms.dll` import, and the loader returns a typed
SKIP before any USD call.

## ABI findings (v0.64.6) and workarounds

These were observed while bringing the surface up; each is encoded in the
shipped module and covered by the suite.

| Finding | Evidence | Shipped handling |
|---------|----------|------------------|
| `Result[Vec[Float64], UsdError]` returns are not reliable through the FFI/trampoline path (the returned Vec reads uninitialized/fill values; `Result[Vec[Int]]` is fine). | Mesh points / diffuse color returned `-4.616e18` (the f32 garbage pattern) while the C component functions printed `-1` / `0.8,0.2,0.1`; switching `usd_mesh_points` to a plain `Vec[Float64]` fixed it. | The four Float64 array getters return a **plain `Vec[Float64]`**; failures set the bridge last error and are read with `usd_error()`. Scalar/string/status calls keep `Result`. |
| A 4-argument FFI call with two `Int32` arguments and an `out` pointer does not deliver the out buffer (the C writes succeed; the XIOM slot stays unchanged). | Packed/4-arg component calls printed the correct values at the out pointers; the public vec3/point values stayed garbage. | `out` is restricted to proven shapes: **3 arguments** (out in R8) for packed index+component and named material components; **4 arguments with one `Float64`** for the at-time x/y/z functions. |
| Manual `u64` assembly (`lo \| (hi << 32)`) overflows/corrupts negative double bit patterns. | Negative `-1.0` components decoded as `-4.616e18`; positive time doubles were fine. | All 8-byte reads use `ffi.ptr_read_u64_le(slot.as_mut_ptr())`; the F64 decoder handles negative `Int` bit patterns (the `requires: bits >= 0` contract was removed). |
| Double-negation in the error helper (`return -fail(...)`) turned errors into positive counts. | `usd_attr_time_count("noSuchAttr")` returned `Ok(9)`. | All count/index error returns use `fail(...)` (already negative). |
| `std::strcmp` name lookups with an early debug print produced an unbraced unconditional return. | Index lookups returned 0 for every name. | Braced match + exact-name lookups; the suite verifies `subdivisionScheme`, `testInput`, `useSpecularWorkflow`, etc. |
| Compiler object/program caching can look like a code bug while iterating (`a.exe`/`a.lib` and the JIT cache). | Identical stale values across suite renames; the C debug proved the fresh code; clearing the caches did not change the final behavior. | Not a shipped workaround; CI starts from a clean cache. The final source/config compiles fresh. |

### Sdf pool sync shim

The prebuilt wheel is the runtime; the bridge is compiled separately. Inline
USD header code in the bridge touches the Sdf path pool's **data** tables,
which a function trampoline cannot resolve. The bridge:

- defines the `Sdf_Pool<...>::_regionStarts` arrays (257 slots each) and
  `UsdPrimDefaultPredicate` locally;
- exports the local pool arrays via linker `/export` pragmas so
  `sync_pools` can address them with `GetProcAddress` on the executable
  module;
- copies the DLL's 257-slot tables into the local arrays before and around
  USD calls (the tables grow only when new path regions are allocated).

Residual risk: a future USD version with different pool geometry or a
different namespace requires regenerating the trampolines and re-checking
the shim. The names are pinned to `v26.08` (`pxrInternal_v0_26_8`).

## Security / robustness

- No secrets, no network at runtime; inputs are file paths and names.
- All C ABI handles are IDs, validated against live maps; stale stage/prim/
  iter use returns `INVALID_HANDLE` instead of dereferencing freed memory.
- Buffer capacities are checked; string copies are bounded and NUL
  terminated; mesh counts/indices are validated before array access.
- Errors from USD are mapped to typed codes with messages; the library is
  serialized under one mutex.
- The runtime is optional: `RUNTIME_ABSENT`/`DEPS`/`ABI` are typed and the
  suite treats them as SKIP, so a CI machine without the wheel still gates
  the package's constants/loader contract.

## Known limits (documented, not defects)

- Windows x64 only (PE trampolines); `libusd.so` is a typed ABI gate.
- The material subset reads constant inputs and reports connections; it
  does not resolve textures or shader networks beyond the surface output.
- Mesh extraction covers points/face counts/indices; normals/UVs/primvars
  are roadmap.
- Time samples expose the essentials (count/bounds/sample/value), not
  interpolation controls or all value types.
- In-process concurrency is serialized.

## Verdict

`0.1.0` is a complete, typed, SKIP-safe implementation of the declared
OpenUSD import surface on the pinned wheel. The ABI gates above are
explicitly handled rather than hidden; `docs/COVERAGE.md` is the 100%
checklist.
