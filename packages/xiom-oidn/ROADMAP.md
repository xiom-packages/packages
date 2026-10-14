# ROADMAP: xiom.oidn

## 0.1.0 -- shipped

- Loader-tier binding over the OIDN v2.5.1 public C API (67/67 functions,
  CPU scope) with typed errors, owned-buffer data movement, and a real
  CPU-denoise conformance suite (33 checks present / 4 absent, x2 recorded).
- Deterministic in-test fixtures (exact IEEE-754 bit patterns).
- Bridge-owned error callback + progress monitor counters.

## Next (not scheduled)

1. **Compile-tier CPU build** -- blocked on ISPC support in the `--c-source`
   pipeline. If the compiler lane ever exposes ISPC-compiled objects (or an
   authorized binary-artifact carve), the vendored-source CPU library path
   from `E:\repos\oidn` becomes viable (`SPEC.md` section 2.1 documents the
   current constraint). This is the only route to a no-DLL, all-source
   package; today the loader tier + official runtime sample is deliberate.
2. **GPU scopes** -- SYCL/CUDA/HIP/Metal device creation, physical-device
   UUID/LUID/PCI selection, external-memory buffers and external semaphores
   on a GPU present machine. The C surface for these is already bound; what
   is missing is a GPU present-path test profile and the C++-only SYCL trio
   (`oidnIsSYCLDeviceSupported`, `oidnNewSYCLDevice`,
   `oidnExecuteSYCLFilterAsync`).
3. **XIOM callback values** -- re-evaluate `oidnSetDeviceErrorFunction` /
   `oidnSetFilterProgressMonitorFunction` with a real XIOM `fn` value once
   B-13/B-18/B-22 are settled; today the bridge owns the callbacks.
4. **Custom weight blobs** -- present-path test for
   `oidnSetSharedFilterData` with a valid `weights` TZA blob (needs an
   upstream-format blob or a tiny generated one).
5. **Larger image profiles** -- 64x64 / 256x256 fixtures behind an env
   toggle for perf smoke (deterministic, slower).

## Non-goals

- The upstream CLI tools (`oidnDenoise`, `oidnBenchmark`) and the C++
  `oidn.hpp` convenience layer.
- Shipping OIDN binaries in this repository (see `SPEC.md` section 2.1).
