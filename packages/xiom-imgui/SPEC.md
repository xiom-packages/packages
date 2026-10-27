# SPEC: xiom.imgui -- Dear ImGui bindings (vendored C++ core, v1.92.9b)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.imgui` |
| Version | 0.4.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Dear ImGui -- https://github.com/ocornut/imgui |
| Upstream version | **v1.92.9b** (tag) |
| Upstream license | MIT (`vendor/LICENSE.txt`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored path is portable |
| Compiler pin | v0.65.2 |

## 2. Vendored path (G2 pin)

The upstream core (`imgui.cpp`, `imgui_draw.cpp`, `imgui_tables.cpp`,
`imgui_widgets.cpp` + `imgui.h`, `imgui_internal.h`, `imconfig.h`,
`imstb_*.h`) and upstream's headless **null backends**
(`imgui_impl_null.cpp/h`, the supported "blind context, no input, no
output" flow from `examples/example_null`) are vendored **unmodified** in
`vendor/` in a flat layout; every include is same-directory quoted, so no
`-I` passthrough is needed. The four core sources, the null backend, and our
bridge (`src/imgui_bridge.cpp`) compile into the test binary with
`--c-source` (`port.args.json`). `imgui_demo.cpp` and the GLFW backend are
not vendored. No precompiled objects.

0.4.0 adds the upstream **SDL3 platform** and **Vulkan renderer** backends
(`imgui_impl_sdl3.cpp/h`, `imgui_impl_vulkan.cpp/h`, upstream v1.92.9b) and
the SDK trees they need, all under `vendor/`:

- `vendor/SDL3/` -- SDL3 3.4.8 headers from Vulkan SDK 1.4.350.0.
- `vendor/vulkan/` -- Vulkan-Headers 1.4.350 (with `vk_video/`).
- `vendor/lib/SDL3.lib`, `vendor/lib/vulkan-1.lib` -- import libs.
  Integrity pins: `SDL3.lib` sha256
  `280d34f2beb9fa1252eb9f03a0cc1a93f44f365fdf0bc8801aed575f60c19b0e`
  (283,572 B); `vulkan-1.lib` sha256
  `dd768491a91c365e3c487427915413e6c40b394f06357008d9d250556cf8c813`
  (66,154 B). Both are tracked with `git add -f` because the repository
  `.gitignore` excludes `*.lib` globally; this package is intentionally
  self-contained (no system SDK at build time).
- `vendor/licenses/` -- SDL3 (zlib), Vulkan-Headers (Apache-2.0), Vulkan SDK.

The only mechanical edit to vendored files is include normalization
(`<SDL3/...>` -> `"..."`, `<vulkan/vulkan.h>` -> `"vulkan/vulkan.h"`) so the
compiler's no-`-I` link line resolves them. `port.args.json` adds
`--cxx-standard 17 --link-path vendor/lib --link SDL3 --link vulkan-1`.
Runtime needs `SDL3.dll` and `vulkan-1.dll`; no SDK at run time.

### Pinned archive

| Artifact | Value |
|----------|-------|
| Download | https://github.com/ocornut/imgui/archive/refs/tags/v1.92.9b.tar.gz |
| Size | 2,123,074 bytes |
| SHA256 (computed at vendor time) | `21D8A0A565E85DCE943E375DB00812C2F3F0AB21F3F0F7964E364A63422D7F99` |

### Re-pin procedure

1. Download the new tag archive and record its SHA256; verify before
   extracting.
2. Re-copy the core `.cpp`/`.h` files and the SDL3/Vulkan backends
   byte-for-byte into `vendor/` (plus `LICENSE.txt`); re-apply the include
   normalization only (quoted same-directory includes). Refresh the
   `vendor/SDL3`, `vendor/vulkan`, `vendor/vk_video` header trees and the
   two import libs from the documented Vulkan SDK version if they moved.
3. Recompute the per-file table below; update `IMGUI_VERSION_NUM` and the
   version expectation in the suite (`19291` for 1.92.9b) plus the rows in
   this SPEC, `README.md`, and `AUDIT.md` in one commit.
4. Re-run `scripts/port.ps1 -Package xiom.imgui` x2 and record `STATUS.json`.

### Per-file SHA256 (vendor tree, LF-normalized upstream bytes)

```
vendor/imconfig.h          5755E1B8D6AB0D7811A9D7CAC0F509878B51FC5EE77E09BD0F235BCB414971E7
vendor/imgui.cpp           5A1E5128C0305F50B6556A77F71FDE35836505883B74C1D6AE44723243F1E8DE
vendor/imgui.h             0D8DB1045DB01D908853ADFD26AE07C5BC5AB4789D4515F6EA34234A69ADE0CA
vendor/imgui_draw.cpp      83D30419A8E06A5F0A8692EE6DE186F7ECFDDECDC33769E76244837E2975B400
vendor/imgui_impl_null.cpp 43A91209FA70302174B22C9241C6F95A8EDF799BB06536B783D31419DE58007E
vendor/imgui_impl_null.h   49C6BD69DE307AF5C7ED532AB46C2D42941AF3EC667D9AFC6F39D481501819CC
vendor/imgui_internal.h    EFBA9BCCC971CC49EC3DA3168968BA412C7EA89745C104A7F5C004C8349BC71F
vendor/imgui_tables.cpp    B5DEABE5B569AB712C11B6556562A646BF88327320FC60A451071B2A36498D72
vendor/imgui_widgets.cpp   A8A0B2F65CAA5711467D9E3CA4028FDED48329EA65E11EC92A968293DC2AA231
vendor/imstb_rectpack.h    889B396795202D1457560A797A7242E96F6F132D4B88CA2D69BE58BF05E1771F
vendor/imstb_textedit.h    A985F5FA0ED97353D493B497961E9EEF52082EDCD045CF6954B69990EC9D0741
vendor/imstb_truetype.h    C51A0F7E7EA760F2366BD3752635EC58E21FCCFEC4A832501639990BA6CE0528
vendor/LICENSE.txt         173506A2D6F7FB67990D257FB2507F188690ECA39060C39469AE7BEF43AAE2A3
vendor/imgui_impl_sdl3.cpp AB831390E680F71D36FEF6AD1F9EC9A67DB0AC163B558D784CC44ABB60C07D37
vendor/imgui_impl_sdl3.h   FA184F17D59D31E986DF2E827EF964D7B3C28BCBA7789643A4AAAED344CB868E
vendor/imgui_impl_vulkan.cpp 659590D8B74BCBD2BA6612D84A6D8871F97314F04DA06A8A05508244ADABF086
vendor/imgui_impl_vulkan.h D34DCA25DFD31A7559F539B1960AED76F177D51E5E688F55B8D3B18B2D500EFA
vendor/lib/SDL3.lib       280D34F2BEB9FA1252EB9F03A0CC1A93F44F365FDF0BC8801AED575F60C19B0E
vendor/lib/vulkan-1.lib   DD768491A91C365E3C487427915413E6C40B394F06357008D9D250556CF8C813
```

Backend/SDK provenance: imgui backends from tag `v1.92.9b`; SDL3 3.4.8 and
Vulkan-Headers 1.4.350 from Vulkan SDK `1.4.350.0` (`Include/`, `Lib/`).
License texts in `vendor/licenses/`. The header trees are vendored as a
tree (86 SDL3 + 40 Vulkan + 12 `vk_video` headers); their hashes are
covered by the vendor-tree pin above and the SDK version.

## 3. Design and safe boundary (G5)

`imgui.xi` is the only module with `unsafe`/`extern "C"`; it calls an
integer-only C++ bridge (`src/imgui_bridge.cpp`) that owns the C++ API and
the `ImVec2`/`ImDrawData` internals. Out-params are written into XIOM-owned
8-byte `Vec[UInt8]` slots (no malloc/free -- finding B-05) and read with a
signed 32-bit helper. Public surface: `imgui_version`, `imgui_version_str`,
`imgui_frame` -> `ImguiFrameStats`, `imgui_empty_frame`. The probe is
**headless** via upstream's null backends (no GLFW/Vulkan): a context plus
**two** `NewFrame`/`Begin`/`Text`/`End`/`Render` cycles; ImGui hides a
newly created window on its very first frame, so the reported stats are the
steady-state second frame. There is no SKIP path -- the vendored core
always compiles in.

0.3.0 adds long-lived context handles (registry, assimp pattern):
`imgui_context_create(width, height)` -> 1-based handle (<= 4 live),
`imgui_context_frame(handle)` -> stats, `imgui_context_destroy(handle)`,
plus `imgui_context_count` / `imgui_context_frames`. A newly created window
is hidden on its first frame and the auto-size settles by the 4th frame, so
the suite drives five frames and requires frames 4 and 5 to match.
Contexts must be bound with the RETURN value of `ImGui::CreateContext`:
upstream only makes the new context current when none is, so
`GetCurrentContext()` otherwise aliases every slot to the first context
(this showed up as a shared pointer and a NewFrame assertion -- the fix
pins the returned pointer with `SetCurrentContext`). All probes set
`io.IniFilename = 0` / `io.LogFilename = 0` so runs are side-effect-free
(the earlier behavior updated a tracked `imgui.ini` on every run; the
artifact is removed and ignored).

0.4.0 adds a separate **backend context registry** (<= 2 live, so probe
contexts are never disturbed): `imgui_backend_create` -> handle;
`imgui_backend_sdl3_init(handle, window, for_vulkan)` attaches the real
SDL3 platform backend to an engine-owned `SDL_Window`;
`imgui_backend_sdl3_process_event` forwards an engine `SDL_Event`;
`imgui_backend_vulkan_init` attaches the Vulkan renderer to the engine's
instance/physical device/device/queue/descriptor pool/render pass (all
handles 64-bit, engine-owned; dynamic rendering is a follow-up);
`imgui_backend_frame` drives platform+renderer NewFrame;
`imgui_backend_draw_data` / `imgui_backend_vulkan_render` hand the draw
data to the engine command buffer; `imgui_backend_shutdown` tears the
backends down. Missing handles fail typed (no crash). The suite's real
SDL3 path uses a hidden window plus the vendored null renderer; the engine
pairs SDL3 with Vulkan.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- 11 checks: version pin
(`19291` / `"1.92.9b"`), headless frame tessellation (two-frame warmup;
vertices > 0, indices > 0, cmd_lists >= 1), empty frame (cmd_lists == 0),
frame determinism (repeated counts identical), context create (two handles,
distinct, registry count 2), long-lived frames (first hidden, frames 4/5
identical, frame counter 5), destroy semantics (h1 gone while h2 keeps
framing, registry counts, double-destroy false), SDL3 platform-backend
selftest (hidden window, two frames, draw data; SKIP only when the host
has no video driver), backend create/registry, missing-handle rejection
(SDL window + Vulkan handle set, no crash), and backend shutdown semantics.

Command (cwd = this package directory; the runner hook adds the C sources):

```
scripts/port.ps1 -Package xiom.imgui
```

Watchdog: allow >=600 s on a cold cache -- clang compiles the four core
sources, both backends (Vulkan is ~111 KB), and the bridge; warm runs are
fast (~5 s) because dependency C sources are cached.

## 5. Scope

0.4.0: version + headless frame lifecycle + tessellation stats + long-lived
context handles + the SDL3 platform and Vulkan renderer backend tier over
engine-owned handles (the engine render-pass path; dynamic rendering is a
follow-up). Widget wrappers, tables, draw-list APIs, and the GLFW backend
are Phase 3 (`ROADMAP.md`). The pre-pilot implementation (90 externs,
precompiled bridge objects, GLFW/Vulkan backends, demo) is preserved in git
history.
