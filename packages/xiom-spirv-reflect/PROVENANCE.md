# PROVENANCE: xiom.spirv-reflect

Upstream-first record (docs/UPSTREAM-FIRST.md). Recorded 2026-10-11.

## Upstream

| Field | Value |
|-------|-------|
| Upstream repo | https://github.com/KhronosGroup/SPIRV-Reflect |
| Pinned tag | `vulkan-sdk-1.4.350.0` |
| Pinned commit | `c90b7b781cdcff63cf1b409ffc7ca0a714e0425e` (2026-03-31) |
| License | Apache-2.0 (`LICENSE` at the pin; notice embedded in every source file) |
| Clone | `E:\repos\SPIRV-Reflect` (full clone, 2026-10-11; pin is the tag, not the clone HEAD) |

The SDK-exported sources (`C:\VulkanSDK\1.4.350.0\Source\SPIRV-Reflect\`) are
byte-identical to the upstream tag: verified by comparing git blob hashes of
the vendored files against `vulkan-sdk-1.4.350.0:<path>` in the clone.

| Vendored file | git blob (prefix) | Upstream match |
|---------------|-------------------|----------------|
| `vendor/spirv_reflect.h` | `0d800e37126b36c39961406c215426577e07082e` | `vulkan-sdk-1.4.350.0:spirv_reflect.h` |
| `vendor/spirv_reflect.c` | `1a2fe22f4051bd33f6943f0efaaa70867edc4157` | `vulkan-sdk-1.4.350.0:spirv_reflect.c` |
| `vendor/include/spirv/unified1/spirv.h` | `48bc24691a6d690ec19b8c0997c45f53e0c905d3` | `vulkan-sdk-1.4.350.0:include/spirv/unified1/spirv.h` |
| `vendor/LICENSE` | `261eeb9e9f8b2b4b0d119366dda99c6fd7d35c64` | `vulkan-sdk-1.4.350.0:LICENSE` |

(SHA256 pins over the raw bytes live in `SPEC.md` section 2.)

## Derived vs independent

- **Vendored verbatim, unmodified**: `vendor/**` (the upstream header,
  implementation, `spirv.h`, and `LICENSE`). No edits, no include rewriting,
  no EOL conversion (`.gitattributes: vendor/** -text`).
- **Independently written for this package**: `src/spvref_bridge.c` (the
  owned-slot probe bridge, written against the pinned header),
  `spirvreflect.xi` (constants generated from the pinned header by
  `tools/oracle_spvreflect.py`; declarations and report wrappers written for
  this package), `tests/test_conformance.xi`, and the two SPIR-V fixtures
  (`tests/fixtures/*.spvasm`, authored here and assembled with the SDK's
  `spirv-as.exe --target-env spv1.0`; `spirv-val` clean).
- No upstream code was copied into the package outside `vendor/`; nothing was
  written from memory -- the oracle is the pinned header itself.

## Oracle source

`tools/oracle_spvreflect.py` parses `vendor/spirv_reflect.h` (the pinned
blob) and emits the function/enum inventory (45 functions, 186 enum/macro
values) and the `check` mode that verifies bound + called coverage against
`spirvreflect.xi` and `src/spvref_bridge.c`. The header is the single source
of truth; no manual lists.

## Test vectors / golden data

The SPIR-V fixtures are locally authored, deterministic, and committed as
`.spvasm` with their assembled bytes embedded in the bridge (no runtime file
I/O). No upstream test vectors were imported; parity evidence is the suite
(`PASS 40/40 x2`, `resolved=45/45`). If upstream adds published golden
modules later, they can be imported into `tests/fixtures/` unchanged.

## Re-pin / re-carve

Documented in `SPEC.md` section 2: point at the new SDK export (or the
matching upstream tag), re-copy the three source files plus `LICENSE` as raw
bytes, recompute the SHA256 table, regenerate the constant block
(`oracle_spvreflect.py emit-consts`) and diff it, run
`oracle_spvreflect.py check` (must stay 45/45 + 186/186), then
`scripts/port.ps1 -Package xiom.spirv-reflect -TimeoutSec 700` x2.

## Clone ledger

Clone registered for the shared ledger (owner edits `E:\repos\CLEANUP.md`;
this package only reports the row):

`| SPIRV-Reflect | https://github.com/KhronosGroup/SPIRV-Reflect (Apache-2.0) | 2026-10-11 | bindings (xiom.spirv-reflect) | 2026-12-01 | active |`
