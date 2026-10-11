# PROVENANCE -- xiom.vulkan

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage; relay
`REL-20261011-2131-packages`).

- **Upstream (oracle):** `KhronosGroup/Vulkan-Headers` (Apache-2.0), clone at
  `E:\repos\Vulkan-Headers`, pinned at tag **`v1.4.350`** (commit `8864cdc`
  "Update for Vulkan-Docs 1.4.350").
- **SDK runtime/headers:** Vulkan SDK 1.4.350.0 at `C:\VulkanSDK\1.4.350.0`
  (`vulkan-1.dll` loader + system ICD; headers under `Include\vulkan`).
- **Oracle equality (verified 2026-10-11):** the SDK copy
  `share\vulkan\registry\vk.xml` and the pinned clone's `registry\vk.xml` are
  **byte-identical** (SHA256
  `F6F43874297CE094769714DE2FC51EC683C12EED9B7615DA20B34AB4A2F81470`).
- **Generated surface** (committed on branch `bindings`, `8cf95606`):
  - `src/cmds_01..08.xi` -- 845 command wrappers (740 real + 105 alias; the 7
    `vulkansc`-only registry twins excluded, listed in `docs/gen_manifest.json`);
  - `src/consts_1..12.xi` + `consts_float.xi` + `consts_str.xi` -- 5,983
    constants (5,284 int + 4 float + 695 string) harvested from all registry
    sources (enum blocks, feature requires, extension requires);
  - `src/names.xi`, `src/api.xi` -- command/class/group/exclusion tables +
    the loader (`VkApi`).
  - Generator: `tools/gen_vk.py` (Python stdlib only, deterministic).
- **Derived vs independent:** declarations/constants are **derived** (mechanical
  extracts of the Apache-2.0 registry); the C bridges in `src/*.c` and all XIOM
  code are original to this package. No upstream C source is copied.
- **Coverage proof:** `tests/test_full_surface.xi` (loadability PASS x2:
  `unresolved_relevant=0`; 766/766 advertised-surface commands resolved;
  75 platform-foreign/SC exclusions; 4 extensions verified unadvertised by the
  loader on this box). Existing RHI conformance suite stays 22/22.
- **Clone ledger:** `E:\repos\CLEANUP.md` row `Vulkan-Headers` (bindings;
  review after 2026-12-01).
- **License:** registry-derived material Apache-2.0 (notice retained here);
  package code MIT OR Apache-2.0 (repo default).
