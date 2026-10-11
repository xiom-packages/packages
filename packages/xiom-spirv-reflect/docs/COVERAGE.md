# COVERAGE: xiom.spirv-reflect (Vulkan SDK 1.4.350.0 -- SPIRV-Reflect)

Recorded 2026-10-11. All counts are produced by the committed tools below,
never by hand.

## Oracle vs bound vs resolved

| Metric | Oracle N | Bound N | Runtime resolved N |
|--------|----------|---------|--------------------|
| C API functions (`spvReflect*`) | **45** | **45** (declared in `spirvreflect.xi`; all 45 called in `src/spvref_bridge.c`) | **45/45** (`resolved=45/45` printed by the suite; `kApi[]` non-NULL count) |
| Enum/macro values (`spirv_reflect.h`) | **186** | **186** (`pub const` in `spirvreflect.xi`) | n/a (compile-time constants; 13 representative checks in the suite) |
| C++ wrapper class (`spv_reflect::ShaderModule`) | excluded | excluded | n/a (documented C++-sugar exclusion, program plan section 4) |

Oracle commands (run from `packages/xiom-spirv-reflect`):

```powershell
python tools/oracle_spvreflect.py inventory     # -> functions: 45 / enum-macro values: 186
python tools/oracle_spvreflect.py check spirvreflect.xi src/spvref_bridge.c
# -> bound fns 45/45, called fns 45/45, bound consts 186/186, check: OK
```

## Route

**Vendored + bridge.** `C:\VulkanSDK\1.4.350.0\Bin\SPIRV.dll` is a stub: its
PE export table contains exactly one symbol (`?stub_library_function@@YAHXZ`)
and no `spvReflect*` entry -- probed 2026-10-11 by parsing the PE export
directory. The upstream sources (`spirv_reflect.h`, `spirv_reflect.c`,
`include/spirv/unified1/spirv.h`) are vendored byte-pinned (SPEC.md section 2)
at upstream tag `vulkan-sdk-1.4.350.0` (commit `c90b7b78`; blob-verified --
`PROVENANCE.md`) and compiled via `port.args.json`; the C bridge adds
owned-slot probes.

## Evidence commands

```powershell
# from the worktree root
& scripts\port.ps1 -Package xiom.spirv-reflect -TimeoutSec 700   # x2, PASS 40/40
python packages\xiom-spirv-reflect\tools\oracle_spvreflect.py check `
  packages\xiom-spirv-reflect\spirvreflect.xi `
  packages\xiom-spirv-reflect\src\spvref_bridge.c
```

## Functional probe summary (suite: `tests/test_conformance.xi`)

- `resolved=45/45` link-surface line + 3 resolution checks.
- Fixture `minimal_frag.spvasm` (embedded): create rc 0, stage FRAGMENT
  (0x10), model Fragment (4), 1 entry point "main", 592 code bytes, source
  GLSL 450, generator 7 (spirv-as); CreateShaderModule2 with NO_COPY.
- Descriptor bindings: count == 1, set 0 / binding 0, type
  COMBINED_IMAGE_SAMPLER (1); 1 descriptor set.
- Interface variables: input count == 1 (`uv`, location 0, R32G32_SFLOAT),
  output count == 1 (location 0, R32G32B32A32_SFLOAT), interface count == 2;
  input name copied out through an XIOM-owned slot.
- Entry-point family: enumerate+get for bindings/sets/inputs/outputs/
  interfaces/push constants/spec constants on "main"; absent semantics and
  push block -> ELEMENT_NOT_FOUND (8); deprecated `EnumeratePushConstants`
  alias rc 0.
- Get family: found items SUCCESS + non-NULL; absent -> (8).
- Spec constants: 1 constant, SpecId 0, name "sc", 4-byte default.
- Strings: `spvReflectSourceLanguage` -> "GLSL"; `BlockVariableTypeName` on
  the UBO fixture -> "UBOBlock"; NULL input -> NULL.
- Change family: binding -> (set 3, binding 5) re-looked-up; set -> 7;
  input location -> 4; output location -> 6.
- Deprecated aliases: `GetShaderModule`, `GetInputVariable`,
  `GetOutputVariable`, `GetPushConstant`, `ChangeDescriptorBindingNumber`.
- Error paths: garbage -> INVALID_MAGIC_NUMBER (10); undersized /
  non-word-multiple size -> INVALID_CODE_SIZE (9); failed creates leave
  `_internal == NULL` (destroy-safe).
- Free chain: create/destroy twice + destroy of an empty module.
