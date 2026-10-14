# ROADMAP: xiom.dlss

## Phase 1 (0.1.0, current)

Declared NGX surface (85 entries + 435 keys + 74 codes + enums/result
codes), dynamic loader with ABSENT/ABI classification, typed parameter C
API, DLSS-SR typed flow + optimal-settings query, present-path resolution
proven against the pinned `nvngx_dlss.dll` (41/85 direct).  See `SPEC.md`.

## Phase 2 candidates

- **Feature struct builders (owned buffers):** `NVSDK_NGX_FeatureDiscoveryInfo`
  and `NVSDK_NGX_FeatureRequirement` layouts as XIOM-owned byte buffers, so
  `dlss_d3d12_get_feature_requirements` becomes a self-contained typed call
  (currently caller-built pointers), plus the DLSS/DLSSD create-params
  structs.
- **B-11 hardening:** if a present-path host observes out-param slot
  recycling through NGX calls, move the parameter getters to a
  bridge-owned-state pattern (vma/zstd precedent) and re-record.
- **Registry-based core discovery:** read the NGXCore `NGXPath` keys
  (documented in the pinned loader header) in addition to common
  locations; requires a small C helper (registry APIs) or a stdlib winreg
  module.
- **Typed FG/RR flows:** `dlss_fg_create/evaluate` (DLSSG keys already
  declared) and `dlss_rr_create/evaluate` (DLSSD keys already declared),
  mirroring the pinned helpers' parameter order.
- **Vulkan typed wrappers:** the 20 VULKAN entries are resolvable; typed
  wrappers mirroring the D3D12 set are mechanical once a Vulkan consumer
  exists.
- **B-27 re-probe:** at v0.64.5+, run
  `docs/repro/bindings-pilot/bigint-bitops/probe.xi`; if fixed, restore the
  bitwise SUCCEED macro form and re-record.

## Explicit non-goals

- Vendoring or redistributing any NVIDIA artifact (license section 4).
- Shipping or downloading runtime binaries.
- Reverse engineering the runtime beyond its public export table (the
  oracle use documented in `SPEC.md` section 2).
- Reflex declarations (not present in the pinned headers; revisit only if a
  pinned header set adds them).
