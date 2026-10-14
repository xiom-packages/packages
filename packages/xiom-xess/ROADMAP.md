# ROADMAP: xiom.xess

- **0.2.0 -- XeLL + XeSS-FG modules** (`libxell.dll`, `libxess_fg.dll`;
  `xell.h`/`xell_d3d12.h`, `xefg_swapchain*.h`): the two companion
  technologies are separate DLLs at the same pin; declare them as companion
  modules/packages with the same loader + SKIP discipline.
- **0.2.x -- logging dispatcher**: a top-level C dispatcher +
  module-level handler registry for `xessSetLoggingCallback` (sdl3 0.5.0
  precedent) once fn-values-to-C lands (findings B-13/B-18/B-22).
- **0.2.x -- typed enums**: expose quality/init-flag/result/logging enums as
  nominal XIOM enums with `Int` interop shims (the flat `Int` constants stay
  for FFI honesty).
- **0.3.0 -- present-path depth**: parse `xessGetProfilingData` /
  `xess_resources_to_dump_t` interiors from an owned slot once a context can
  be created on CI-class hardware (needs a caller-owned D3D12/Vulkan device).
- **0.3.x -- D3D11-only loader**: a core-less mode resolving the 23-entry
  generic+D3D11 surface from `libxess_dx11.dll` alone (today the companion is
  an add-on to the core).
- **Re-carve**: at the next XeSS SDK tag carrying headers (procedure in
  `PROVENANCE.md`).
