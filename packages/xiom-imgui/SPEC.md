# SPEC: xiom.imgui -- Dear ImGui bindings (vendored C++ core, v1.92.9b)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.imgui` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Dear ImGui -- https://github.com/ocornut/imgui |
| Upstream version | **v1.92.9b** (tag) |
| Upstream license | MIT (`vendor/LICENSE.txt`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored path is portable |
| Compiler pin | v0.64.2 |

## 2. Vendored path (G2 pin)

The upstream core (`imgui.cpp`, `imgui_draw.cpp`, `imgui_tables.cpp`,
`imgui_widgets.cpp` + `imgui.h`, `imgui_internal.h`, `imconfig.h`,
`imstb_*.h`) and upstream's headless **null backends**
(`imgui_impl_null.cpp/h`, the supported "blind context, no input, no
output" flow from `examples/example_null`) are vendored **unmodified** in
`vendor/` in a flat layout; every include is same-directory quoted, so no
`-I` passthrough is needed. The four core sources, the null backend, and our
bridge (`src/imgui_bridge.cpp`) compile into the test binary with
`--c-source` (`port.args.json`). `imgui_demo.cpp` and the GLFW/Vulkan
backends are intentionally not vendored (Phase 2). No precompiled objects,
no SDK.

### Pinned archive

| Artifact | Value |
|----------|-------|
| Download | https://github.com/ocornut/imgui/archive/refs/tags/v1.92.9b.tar.gz |
| Size | 2,123,074 bytes |
| SHA256 (computed at vendor time) | `21D8A0A565E85DCE943E375DB00812C2F3F0AB21F3F0F7964E364A63422D7F99` |

### Re-pin procedure

1. Download the new tag archive and record its SHA256; verify before
   extracting.
2. Re-copy the core `.cpp`/`.h` files byte-for-byte into `vendor/` (plus
   `LICENSE.txt`); do not edit vendored files.
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
```

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

## 4. Test contract

Suite: `tests/test_conformance.xi` -- 4 checks: version pin
(`19291` / `"1.92.9b"`), headless frame tessellation (two-frame warmup;
vertices > 0, indices > 0, cmd_lists >= 1), empty frame (cmd_lists == 0),
and frame determinism (repeated counts identical).

Command (cwd = this package directory; the runner hook adds the C sources):

```
scripts/port.ps1 -Package xiom.imgui
```

Watchdog: allow >=180 s -- clang compiles the four core sources plus the
bridge (observed ~5 s on the development machine).

## 5. Scope

Pilot: version + headless frame lifecycle + tessellation stats. Widget
wrappers, tables, draw-list APIs, and the GLFW/Vulkan backend integration
(the pre-pilot `bridge/` tree) are Phase 2 (`ROADMAP.md`). The pre-pilot
implementation (90 externs, precompiled bridge objects, GLFW/Vulkan
backends, demo) is preserved in git history.
