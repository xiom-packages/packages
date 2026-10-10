# xiom.cuda -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot static-extern Toolkit surface (preserved in git history)

## Phase 2 (Done) -- 0.2.0 driver-API probe
- [x] Runtime-loaded `nvcuda.dll`, packed-return bridge (B-11-safe ABI)
- [x] Driver version, device count/name, compute capability
- [x] Real host -> device -> host memory round trip on a fresh context
- [x] Conformance suite (5 checks incl. deterministic SKIP classification)

## Phase 3 (Planned)
- [ ] Multi-device enumeration + per-device attributes
- [ ] Primary context / `cuCtxCreate` lifetime wrappers usable by later calls
- [ ] Stream + event wrappers
- [ ] VMM API (virtual memory management)
- [ ] Toolkit libraries as *separate decisions* (cuBLAS/cuDNN/cuFFT/cuRAND; system-lib SKIP pattern, nothing vendored by default)
- [ ] Linux `libcuda.so.1` soname support + a Linux run
