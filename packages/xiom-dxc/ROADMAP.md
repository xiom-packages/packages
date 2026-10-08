# xiom.dxc -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no SDK/header/link dependency) | Done -- `DxcCreateInstance` seam |
| Header-free COM ABI (GUIDs + vtable slots pinned) | Done |
| G2 pin (soname + header hashes + ABI) | Done -- `SPEC.md` §2 |
| Capability probe (instance + trivial compile) | Done -- 3/3 x2 (2,532-byte DXIL blob) |
| SKIP/FAIL classification | Done |
| Generic compile API (source/target/entry/defines) | Phase 2 |
| Include handler + multi-entry/library targets | Phase 2 |
| Validator (`IDxcValidator`, `dxil.dll`) + signature info | Phase 2 |
| Reflection / disassembly (`IDxcResult` extra outputs) | Phase 2 |

## Phase 2 (next touches)

1. Generic compile: `dxc_compile(source, target, entry, args)` returning the
   object blob as an owned XIOM buffer plus the error text blob; expose
   `dxc_compile_hlsl(...)` with defines.
2. Error surfacing: `DXC_OUT_ERRORS` blob as `Str` on failure (currently only
   the HRESULT is reported).
3. Validator: create `CLSID_DxcValidator` (IID `IDxcValidator`) and report
   validation success/hash; requires `dxil.dll` on the host (SKIP when
   absent).
4. Reflection/disassembly: `DXC_OUT_REFLECTION` + `IDxcCompiler3::Disassemble`
   for tooling consumers.
5. Feed compiled DXIL into the directx11/12 tier when those land (SPIR-V
   output via `-spirv` also enables Vulkan content later).
