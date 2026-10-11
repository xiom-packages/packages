# PROVENANCE: xiom.glslang

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | glslang -- Khronos GLSL/ESSL/HLSL compiler, SPIR-V generator |
| Repository | https://github.com/KhronosGroup/glslang |
| Pinned tag | `vulkan-sdk-1.4.350.0` (`git describe` -> `16.3.0`; the tag Khronos maintains for Vulkan SDK 1.4.350.0) |
| Pinned commit | `275822a6261ee689aadb1da5f09a0ec2f058685c` |
| Local clone | `E:\repos\glslang` (shallow, shared read-only reference; ledger row requested in `E:\repos\CLEANUP.md`) |
| Runtime artifact pin | `C:\VulkanSDK\1.4.350.0\Bin\glslang.dll` + `glslang-default-resource-limits.dll` (SHA256 in `SPEC.md` §2) |
| Upstream license | glslang proper is **BSD-3-Clause**; `LICENSE.txt` also carries BSD-2-Clause, MIT and Apache-2.0 for constituent parts (see §License below) |
| Package license | MIT OR Apache-2.0 (repo default; no upstream code copied into the package) |

## Clone/source verification (2026-10-11)

- The shallow clone was taken at the pinned tag; `git rev-parse HEAD` =
  `275822a6261ee689aadb1da5f09a0ec2f058685c`, `git describe --tags` = `16.3.0`.
- Header parity against the SDK pin (`SPEC.md` §2): 5 of the 6 pinned headers
  are **byte-identical** between `E:\repos\glslang` and
  `C:\VulkanSDK\1.4.350.0\Include\glslang` (`Public/ShaderLang.h`,
  `Include/glslang_c_interface.h`, `Include/glslang_c_shader_types.h`,
  `Public/resource_limits_c.h`, `MachineIndependent/Versions.h`).
  `build_info.h` is **generated at build time** (from `build_info.h.tmpl` +
  `CHANGES.md` via `build_info.py`, wired in `CMakeLists.txt`), so it is not
  in the source tree; the generated SDK instance reports 16.3.0, matching the
  tag.
- The three translation units that define every bound export exist at the
  pinned commit: `glslang/CInterface/glslang_c_interface.cpp` (41 entry
  points), `SPIRV/CInterface/spirv_c_interface.cpp` (SPIR-V generate/get
  family), `glslang/ResourceLimits/resource_limits_c.cpp` (the 4
  resource-limit helpers, shipped in the companion DLL).

## Derived vs independent

- **No upstream code, data or table is copied into this package.** The XIOM
  module (`glslang.xi`) is independently written for this lane (dynamic
  loader, typed wrappers, owned-slot discipline).
- **Extracted (not hand-written) artifacts**: the oracle inventory
  (61 C entry points) and the constant tables (290 values) are computed
  mechanically from the pinned headers by `tools/gen_glslang.ps1`; the
  committed `docs/oracle-*.txt` and the generated constant block in
  `glslang.xi` are derived data with the generator as the reproducible
  procedure. Header SHA256 pins live in `SPEC.md` §2.
- **Parts studied for call semantics** (read, not copied):
  `glslang/CInterface/glslang_c_interface.cpp` and
  `SPIRV/CInterface/spirv_c_interface.cpp` pinned the preprocess-before-parse
  flow, the create-time `setStrings` pointer, the owned-buffer
  `memcpy` copy-out of `glslang_program_SPIRV_get`, and the
  `glslang_default_resource_string` malloc (no free in the C surface);
  `glslang/ResourceLimits/resource_limits_c.cpp` pinned the companion-DLL
  split; `glslang/MachineIndependent/ShaderLang.cpp` pinned the legacy
  `Sh*` semantics (refcounted process init via `NumberOfClients`;
  `ShGetUniformLocation` -> `getLocation`).

## Test vectors / golden data

- None imported from upstream. The conformance suite's runtime assertions
  are observations of the pinned DLLs (recorded in `docs/COVERAGE.md` §3):
  `glslang_get_version` = 16.3.0 = the pinned `GLSLANG_VERSION_*` macros;
  SPIR-V word 0 = `119734787` (0x07230203) and word 1 = 65536 (SPIR-V 1.0);
  decode round-trip `MaxLights 42 / MaxClipPlanes 7`; the invalid-source
  info log contains `ERROR`.
- Two runtime-lifetime findings are recorded in `AUDIT.md` (companion-DLL
  unload dangles `glslang_default_resource`; `ShGetUniformLocation` returns 0
  for absent names on this build).

## Re-carve procedure (upstream moves)

1. `git -C E:\repos\glslang fetch --unshallow` (or re-clone) at the new
   tag; record the new commit here and update the ledger review date.
2. Re-hash the six headers + two DLLs; update `SPEC.md` §2 and
   `docs/COVERAGE.md` counts in one commit.
3. `tools/gen_glslang.ps1 -Action emit` against the SDK include dir,
   re-splice the constants block, refresh `docs/oracle-*.txt` +
   `docs/exports-*.txt`, then `-Action verify` (must be OK).
4. `scripts/port.ps1 -Package xiom.glslang` x2 (present) + absent-path
   SKIP-green run; `scripts/status.ps1 -Action update`; conventional commit.
