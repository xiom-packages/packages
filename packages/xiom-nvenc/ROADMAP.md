# xiom.nvenc -- ROADMAP

## Phase 1 (Done) -- 0.1.0: loader-only essentials
- [x] Runtime-loaded `nvEncodeAPI64.dll` + `nvcuvid.dll` + `nvcuda.dll`; nothing vendored
- [x] NVENC: version negotiation, session open, preset config + initialize,
      CUDA resource registration, bitstream create, one-frame encode,
      lock/copy/unlock, destroy (H.264 and HEVC)
- [x] NVDEC: decoder create, parser feed/decode, map, compact NV12 copy-out,
      unmap, destroy (H.264 and HEVC)
- [x] Typed errors with SKIP classification; deterministic skip paths
- [x] Conformance suite 67/67 x2 on v0.64.6 (live RTX 3070 Ti)

## Phase 2 (Planned)
- [ ] Multi-frame streaming API (GOP, timestamps, P/B frames, drain loop)
- [ ] Caller-supplied CUDA surfaces and D3D11/D3D12 interop registration
- [ ] Encoder stats, sequence-param payload, reconfigure
- [ ] 10-bit and YUV444 profiles; HEVC Main10 caps
- [ ] Zero-copy decode -> encode (NVDEC surface registered directly with NVENC)
- [ ] Linux loader names (`libnvidia-encode.so.1`, `libnvcuvid.so.1`) + a Linux run
- [ ] AV1 encode/decode once the driver baseline is raised
