# xiom.dxc -- Roadmap

**Version**: v0.3.0 | **Compiler**: xiom v0.64.3 | **Last updated**: 2026-10-12

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no SDK/header/link dependency) | Done -- `DxcCreateInstance(2)` seam |
| Header-free COM ABI (GUIDs + flattened vtable structs, generated) | Done -- `src/dxc_abi.h` |
| G2 pin (soname + header hashes + ABI counts) | Done -- `SPEC.md` Â§2 |
| 100% dxcapi.h COM surface (27 interfaces / 128 methods) | Done -- `bound=128/128` x2 |
| Generated bridge + family-split wrappers + `--check` drift gate | Done -- `tools/gen_dxc.py` |
| Capability probe + SKIP/FAIL classification | Done -- 20/20, SKIP exercise per run |
| Runtime pipeline probes (compile, errors, reflection, disasm, version, factory) | Done -- `docs/COVERAGE.md` |
| Validator (`IDxcValidator`, `dxil.dll` signing) | Phase 2 (bound; `dxil.dll` absent on host) |
| PDB tooling exercises (`IDxcPdbUtils*`) | Phase 2 (bound; needs full PDB inputs) |
| Linker/assembler/optimizer execution probes | Phase 2 (bound; need library/bitcode/pass inputs) |

## Phase 2 (next touches)

1. Validator: install `dxil.dll` in CI and exercise `Validate`/`ValidateWithDebug`
   end to end (hash + status), promoting `IDxcValidator(2)` from bound to
   functional.
2. PDB pipeline: compile with `-Zi/-Qembed_debug`, read back sources/flags/args
   via `IDxcPdbUtils2`, promoting the 49 PDB methods.
3. Linker flow: register two `IDxcBlob` libraries and `Link` them; assemble
   LLVM bitcode through `IDxcAssembler`; run `IDxcOptimizer` passes.
4. Reflection consumers: `IDxcUtils::CreateReflection` + `IDxcContainerReflection`
   `GetPartReflection` with a D3D12 reflection IID when the directx tier lands.
5. Feed compiled DXIL into the directx11/12 tier; `-spirv` output enables
   Vulkan content later (shares the generated bridge).
