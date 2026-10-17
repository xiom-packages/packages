# PROVENANCE: xiom.nvapi

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | **NVIDIA/nvapi** -- https://github.com/NVIDIA/nvapi (public NVAPI SDK headers, interface ids, samples) |
| Contents | `nvapi.h`, `nvapi_interface.h`, `nvapi_lite_common.h` and the public SDK documentation |
| Upstream license | **MIT** (`License.txt`: "SPDX-License-Identifier: MIT"; README: "This project is licensed under the MIT License") |
| Policy | **Reference-only. NEVER vendored.** The shipped package contains no header, no import library and no NVIDIA code. `nvapi64.dll` is a system component of the installed NVIDIA display driver and is loaded at run time. |
| Reference clone | `E:\repos\nvapi` -- pinned commit `70d337db9186e968eab622f7e786de7e437faf3d` (2026-09-18); light clone (`--depth 1`) retained locally, not committed |
| Package license | MIT OR Apache-2.0 (no upstream code copied into this package) |

The shipped surface is **independent XIOM + C code** written against the
public interface declarations in the pinned clone (the "declaration oracle"
below). The C bridge is original XIOM-side code; it encodes only interface
facts (function ids, signatures, struct field order, version macros, enum
values) and asserts every offset/size it relies on at compile time.

## Declaration oracle (files read at the pinned commit)

| File | SHA256 |
|------|--------|
| `nvapi.h` | `4EE1BFF7568CEEC72124B8B3E43BF65CCB69DBB878B08C634B128F7EDCD28F3B` |
| `nvapi_interface.h` | `A3E3F84A25926B76B73199E861EE4692875B935CFC2E19E90E7BE3E43E7F0756` |
| `nvapi_lite_common.h` | `5DDC178D1D504B89907DAD59D41D670E92647E5B7847D4DE1461E6765D8871E8` |

What the bridge takes from each file:

- `nvapi_interface.h` -- the numeric ids for `NvAPI_Initialize`,
  `NvAPI_Unload`, `NvAPI_GetErrorMessage`,
  `NvAPI_GetInterfaceVersionString`,
  `NvAPI_SYS_GetDriverAndBranchVersion`, `NvAPI_EnumPhysicalGPUs`,
  `NvAPI_GPU_GetFullName`, `NvAPI_GPU_GetPCIIdentifiers`,
  `NvAPI_GPU_GetBusId`, `NvAPI_GPU_GetThermalSettings`,
  `NvAPI_GPU_GetDynamicPstatesInfoEx`.
- `nvapi.h` -- the thermal and dynamic-P-state struct layouts/versions,
  thermal target values and the documented GPU utilization-domain order.
- `nvapi_lite_common.h` -- `NvAPI_ShortString` (64), `NvPhysicalGpuHandle`
  (opaque pointer), `NVAPI_MAX_PHYSICAL_GPUS` (64), the status enum used for
  classification, and `MAKE_NVAPI_VERSION(type, ver) = sizeof(type) |
  (ver << 16)`.

## Derived vs independent

- `nvapi.xi` (root module; all `unsafe`/`extern`): **independent** XIOM
  code -- typed errors, the declared presence/identity surface.
- `nvapi_bridge.c`: **original XIOM-side helper** (ours, MIT OR
  Apache-2.0), compiled with `--c-source`; it never links NVIDIA code. It
  loads `nvapi64.dll`, resolves `nvapi_QueryInterface`, fetches the declared
  function pointers by id, and keeps all foreign handles and memory in C.
  The struct declarations are hand-written interface facts guarded by
  `_Static_assert`.
- No upstream test vectors or samples are imported; the live checks read the
  installed driver's real identity/telemetry.

## Local runtime samples (present-path evidence; not the pin)

Host: NVIDIA GeForce RTX 3070 Ti, driver 616.92 (Windows driver version
32.0.16.1692).

| Module | Size | SHA256 |
|--------|------|--------|
| `C:\Windows\System32\nvapi64.dll` | 574,040 B | `11F66428948436B666DFC987A8D3DF4A0CA6293D10E4F9DDF7E40A10D759EF73` |

The suite reports interface version, driver raw/decoded version and branch,
physical GPU count, GPU 0 name/PCI identifiers/bus id, temperature and
utilization.

## Re-carve procedure (upstream moves)

1. Refresh `E:\repos\nvapi` at the new commit/tag; update the pin and the
   `E:\repos\CLEANUP.md` review date.
2. Re-hash the oracle files into the table above; re-verify the function
   ids, struct versions/layouts and status values against the new headers.
3. Update the `_Static_assert` block and the interface facts in
   `nvapi_bridge.c` in the same commit as the pin update.
4. `scripts/port.ps1 -Package xiom.nvapi -TimeoutSec 180` x2 (live RTX
   host); `scripts/status.ps1 -Action update`; conventional commit; sync
   `SPEC.md`/`AUDIT.md` counts in the same commit.
