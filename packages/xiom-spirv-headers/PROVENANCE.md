# PROVENANCE: xiom.spirv.headers

Per the upstream-first doctrine (`docs/UPSTREAM-FIRST.md`, owner policy
2026-10-11), this package is generated against its authoritative upstream
source; no constant name or value was written from model memory.

## Upstream

| Field | Value |
|-------|-------|
| Project | SPIRV-Headers (KhronosGroup) |
| Repo | https://github.com/KhronosGroup/SPIRV-Headers |
| Clone | `E:\repos\SPIRV-Headers` (shallow, single tag) |
| Pin | tag `vulkan-sdk-1.4.350.0`, commit `ad9184e76a66b1001c29db9b0a3e87f646c64de0` |
| License | MIT (Khronos; `LICENSE` + `LICENSES/MIT.txt`); the generated `spirv.h` header itself carries the Khronos MIT notice |
| Oracle (used for generation) | shipped header `C:\VulkanSDK\1.4.350.0\Include\spirv-headers\spirv.h`, sha256 `93F82C0B51984974E60485C126945C40F264B89FD4D395A580A1BC59D211E24E` |
| Oracle cross-check | byte-identical to the clone copy `include/spirv/unified1/spirv.h` (same sha256); the generator re-verifies this when the clone is present |

## What was derived vs independently implemented

- **Derived (verbatim facts)**: every `Spv*` constant name and its numeric
  value, taken mechanically from the pinned `spirv.h`
  (`typedef enum` enumerators, `#define SPV_VERSION`/`SPV_REVISION`, the
  five `static const unsigned int` header constants). These are interface
  facts of the SPIR-V standard, not creative expression; no other header
  content (comments, string functions, types) is copied.
- **Independently implemented**: `tools/gen_spirv_headers.py` (parsing,
  family split, spot checks, manifest, drift gate), the family/module
  layout, the conformance suite, and every documentation file in this
  package. No upstream code (generator `spirv.core.grammar.json` tooling,
  CMake, etc.) is vendored or copied.
- **No vendored files**: nothing from the clone is committed; the generated
  modules are derivative constants with the upstream notice reproduced in
  each file header.

## Test vectors / golden data

- Spot-check values (61 in the generator, ~90 asserted in the suite) are
  imported *by reading the oracle* at generation time -- the generator
  asserts the header still carries them, so a silent oracle change fails
  generation. The canonical four required by the task
  (`SpvOpTypeVoid==19`, `SpvExecutionModelVertex==0`,
  `SpvStorageClassUniform==2`, `SpvCapabilityShader==1`) were verified from
  the header before being embedded.
- The oracle sha256 and per-generated-file sha256 hashes live in
  `tools/spirv_manifest.json`.

## Re-carve procedure

1. Fetch the new upstream tag into the shared clone:
   `git -C E:\repos\SPIRV-Headers fetch --depth 1 origin tag vulkan-sdk-<VER>`
   and `git -C E:\repos\SPIRV-Headers checkout FETCH_HEAD`.
2. Update `DEFAULT_HEADER`/`DEFAULT_CLONE_HEADER` and
   `UPSTREAM_TAG`/`UPSTREAM_COMMIT` in `tools/gen_spirv_headers.py`; rerun
   `python tools\gen_spirv_headers.py` from the package directory.
   The tool re-verifies byte-identity, re-asserts the spot checks, rewrites
   the modules and the manifest, and re-audits counts.
3. Run `python tools\gen_spirv_headers.py --check` (must print "no drift").
4. Run the suite x2 and `port.ps1 -Package xiom.spirv.headers`; record the
   run via `scripts/status.ps1 -Action update ... -Commit <sha>`.
5. If a spot check changed value, STOP: that is a normative header change
   worth a SPEC note (the generator intentionally fails closed).

## Retention

The `E:\repos\SPIRV-Headers` clone is kept for re-carves/debug under the
`E:\repos\CLEANUP.md` ledger (row text reported to the coordinator; the
ledger itself is not edited by this lane).
