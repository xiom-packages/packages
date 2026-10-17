# ROADMAP: xiom.optix

## Phase 1 (0.1.0, current)

Reference-only dynamic loader pinned to OptiX 9.1 ABI 118.  Declared
essentials: device context create/destroy/validate + options, PTX module
load, raygen/miss/hitgroup program groups, SBT build, pipeline create/link,
launch-params buffer, launch.  Typed errors; SKIP-safe suite.

Live evidence on the development host (RTX 3070 Ti, driver 616.92): context
+ options + properties, module error path, null-miss group, SBT packing +
device readback, raygen-less pipeline validation, params round trip.  The
full launch happy path waits on user-supplied PTX (SDK registration-gated;
nothing vendored).

## Phase 2 candidates

- **Acceleration structures**: `optixAccelComputeMemoryUsage`, build,
  relocate/compact, traversable-handle conversion; typed build-input
  mirrors (triangles first).  This is the other half of a usable ray tracer
  and the natural next slice.
- **PTX helpers**: `optix_module_load_file(path, ...)` using the stdlib
  filesystem plus a byte-slice loader, and a `optix_module_load_bytes`
  variant for embedded PTX.
- **Multi-record SBTs**: arrays of groups per kind, per-record user data
  setters, multiple miss/hit records with strides/counts; keep the current
  one-record convenience path.
- **Callables + exceptions**: direct/continuation callable groups and the
  exception program group (the table slots are already declared).
- **External CUDA context / streams**: let a caller pass an existing
  `xiom.cuda` context/handle instead of creating one, and accept a stream
  for launch (currently default stream + synchronize).
- **Denoiser**: `optixDenoiserCreate/Destroy/ComputeMemoryResources/Setup/
  Invoke` with owned image descriptors (the table slots are in the pinned
  ABI; the package currently stops at launch).
- **Older-ABI negotiation**: per-version table sizes/slot maps so drivers
  older than ABI 118 can at least create a context (0.1.0 requires 118 and
  reports a typed ABI failure).
- **Linux**: `nvoptix.so` + `libcuda.so` loader variant; same bridge shape,
  POSIX `dlopen`.
- **SDK sample bridge**: optional build-time helper (behind a user-supplied
  SDK path, never vendored) that compiles the stock samples to PTX and runs
  a smoke launch; useful as a re-pin gate.
- **Compile caching/validation**: expose OptiX module cache options and
  `validationMode` profiles as typed options; record the cost.

## Explicit non-goals

- Vendoring or redistributing any NVIDIA SDK header, sample, shader, import
  library or runtime DLL.
- Shipping a prebuilt raygen PTX unless the user supplies it.
- Downloading the gated SDK automatically.
- Reverse engineering the runtime beyond its public export table and the
  published ABI headers.
