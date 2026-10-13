# PROVENANCE: xiom.xess

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11) and the
closed-SDK pattern (precedent: the FFmpeg reference-only decision).

## Upstream

| Field | Value |
|-------|-------|
| Project | Intel XeSS SDK -- https://github.com/intel/xess |
| Product pin | **v3.0.2** (XeSS 3 SDK; annotated tag dereferenced to commit `8fe81bdbbaf00b3c1b733fd0d830c333dc84e6f0`, 2026-07-23) |
| Upstream license | **Intel Simplified Software License (Version October 2022)** -- the XeSS SDK License (`LICENSE.txt` at the pin). Binary-form SDK; no modification; no reverse engineering; redistribution only under the license conditions. The README also points at `third-party-programs.txt` for bundled components. |
| Policy | **Reference-only. NEVER vendored.** No SDK header, library, binary, sample, or table is copied into this package (`docs/BINDINGS-LANE.md` sec. 4; the FX/GPU-SDK dynamic-loader pattern). The package's own code is MIT OR Apache-2.0. |
| Reference clone | `E:\repos\xess` -- shallow (`--depth 1`) at the tag above; ledger row `E:\repos\CLEANUP.md` (added 2026-10-14, review-after 2026-12-01). |
| Distribution model | The runtime (`libxess.dll`, `libxess_dx11.dll`, ...) is resolved from the host at run time via `xiom.ffi.dl`; the suite reports typed **SKIP** when absent. Nothing is committed: the `bin/` DLLs referenced below stay in the clone only. |

## Declaration oracle (files read at the pinned commit)

All hashes are SHA256 over the exact file bytes at `v3.0.2`.

| File | SHA256 |
|------|--------|
| `inc/xess/xess.h` | `98DC435F5AED252D83A161FC1F86223F20C67EB863214FE3B5CB215A3F6E3319` |
| `inc/xess/xess_d3d11.h` | `F154E48039EE4DE4CB1AB94C908EEACFCBCD72CE46C5A44A57AD972B7907D1BB` |
| `inc/xess/xess_d3d12.h` | `A582A60C3E39EE6FD6AA4871E23082CFB5EC510F98A19FC04ACF7A7EDB2F6B6C` |
| `inc/xess/xess_d3d12_debug.h` | `A1C1C2A2F10FA3602FBEFBBB89D567C3CE92EAACC13448587B8D9EFF1F151F53` |
| `inc/xess/xess_debug.h` | `067D2BA4CC8380D83B36D4648412CD1F911F7990085B0A063AE5B4ADB0CCE358` |
| `inc/xess/xess_vk.h` | `859086DF3C531CECCAB628B287F69BD9A4528045BCBDD8C639589082DCBF8977` |
| `inc/xess/xess_vk_debug.h` | `4357D6BF06966682CC9DF3C0BE5390CAD20EAA290165AE2EB017E0E3DE5E670C` |

Bound declarations (signatures, enum values, struct member order and
sizes/offsets) come from exactly these seven public headers.  The companion
products in the same `inc/` tree -- `xell/` (`xell.h`, `xell_d3d12.h`) and
`xess_fg/` (`xefg_swapchain*.h`) -- are **separate technologies on separate
DLLs** (`libxell.dll`, `libxess_fg.dll`) and are explicit non-goals for
`xiom.xess` 0.1.0 (SPEC.md sec. 3).

## Derived vs independent

- `xess.xi` (root module, all `unsafe`): **independent** XIOM code.  The
  loader, the entry-point table, the slot discipline, the pinned-struct
  serializers and the pure-arithmetic f32 codec are ours; no SDK code, table,
  comment, or generated file was copied.  What the module encodes are
  *interface facts* from the headers above: entry names and signatures, enum
  values, and the pack(8) struct layouts.
- No C bridge is shipped (unlike `xiom.ffmpeg`): the surface needs no
  pointer-side helper beyond `Str.c_str()` for the one `const char*` field
  (`xess_dump_parameters_t::path`), so a C bridge / `port.args.json` stay
  unnecessary.

## Runtime samples (not the pin, nothing committed)

Present-path proof used the SDK's own Windows binaries **from the clone**
(`E:\repos\xess\bin\`, reference-only, never copied into the repo):

| Sample | Size | SHA256 |
|--------|------|--------|
| `libxess.dll` | 77,795,704 B | `251659DD84A3E84DE67C886A4186E01F3ECA49B00641906FE38BB6B807E5D5B7` |
| `libxess_dx11.dll` | 156,016 B | `C7CFE86F0C9D94E4FB3696D3CD5035E2BBB6A8B1B0572F8B7395A4CDFD0C625E` |

Export-table ground truth from the same binaries (PE export directory, parsed
read-only): `libxess.dll` 72 exports (37 header-declared, 35 undocumented),
`libxess_dx11.dll` 51 exports (23 header-declared, 28 undocumented).  The
undocumented names (`INTC_D3D11_Xess*`, `INTC_D3D12_*`, `xessAIL*`,
`xessTrinity*`, `xessVKAILGetDecision`, context-parameter accessors) are not in
the public headers and are non-goals.

## Test vectors

None imported from upstream.  The suite's numeric expectations (f32 bit
patterns, struct field offsets, enum values) are independent constants written
from the header declarations and IEEE-754.

## Re-carve procedure (upstream moves)

1. Re-clone/refresh `E:\repos\xess` at the new release tag that carries
   headers; update the pin here and the `E:\repos\CLEANUP.md` row.
2. Re-hash the seven headers into the oracle table; re-verify the 41 entry
   names, enum values and struct sizes/offsets; re-run the export-table parse
   on the new `bin/libxess.dll` + `bin/libxess_dx11.dll`.
3. `scripts/port.ps1 -Package xiom.xess` (default SKIP x2 + `bin` on PATH for
   the present path x2); `scripts/status.ps1 -Action update`; conventional
   commit; sync SPEC/AUDIT counts in the same commit.
