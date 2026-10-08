# BINDINGS-SESSION -- xiom-packages bindings lane

Handoff file for the native session. Read the relay block first; the ledger
below records evidence and open asks.

**STATUS: BATCH 12 RELAYED** -- `xiom.zstd` 0.2.0 green (8/8 x2 + a
post-normalization re-run via port.ps1 on v0.64.1: zstd 1.5.7 amalgamation,
8192 -> 34 bytes, byte-identical round-trips); awaiting native
merge/verify/publish. Next confirmed: `xiom.lzfse`, then `xiom.ozz`.

## Relay (bindings -> native, per BINDINGS-LANE.md §6)

```
BINDINGS BATCH 12: head=a0f3513e + this handoff commit; packages=xiom.zstd 0.2.0 (vendored
amalgamation replacing the pre-pilot null-pointer stubs); tests=8/8 x2 (+1 post-normalization
re-run) via scripts/port.ps1 on v0.64.1 (2026-10-08: version 1.5.7, compressBound sanity,
8192->34 bytes at level 3, frame content size 8192, round-trip identity incl. auto-size and
2048-byte incompressible, invalid frame rejected); licenses=BSD-3-Clause (vendored zstd,
chosen from the dual BSD-3/GPLv2) + package MIT OR Apache-2.0; pins=release tar.gz sha256
eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3 (verified against the
published .sha256), vendor/zstd.c sha256 208E110A1F052D007242D4EEF6ED20A03AB1DC6E13EB2C4FF8D158112120BA8E
(2,174,920 B, LF-normalized; Windows combine.py wrote CRLF), vendor/zstd.h sha256
9B4BC8245565C98CCFC61C07749928B57E7C0F6FDDB0530C4F6AA1971893D88B; gate=G0..G5 OK; needs=NONE
(allowlisted + baseline); port.args.json present (--c-source src/zstd_all.c; the 4-line shim
pins STATIC_BMI2 0 because the link line has no -mbmi2 -- vendored file itself unmodified).
NOTE: .gitattributes `vendor/** -text` pins the bytes against autocrlf (same as xiom.sqlite).
```

```
BINDINGS BATCH 11: head=4cf630ba + this handoff commit; packages=xiom.directx12 0.2.0 (capability probe replacing the pre-pilot static externs);
tests=5/5 x2 via scripts/port.ps1 on v0.64.1 (2026-10-08: highest accepted feature level 12_2
(49664) by descending D3D12CreateDevice attempts, 3 DXGI adapters, first = NVIDIA GeForce RTX
3070 Ti vendor_id 4318 device_id 9346; deterministic SKIP classification per run);
licenses=MIT OR Apache-2.0 (header-free bridge is our code; nothing vendored); pins=sonames
d3d12.dll + dxgi.dll + Windows SDK 10.0.22621.0 header hashes (um\d3d12.h 82EB3319...,
shared\dxgi.h 4B983AC7..., um\d3dcommon.h 62F7BF1A...) + ABI (IID_ID3D12Device
{189819f1-1db6-4b57-be54-1821339b85f7}; IID_IDXGIFactory1 + DXGI vtables/offsets shared with
directx11; feature levels 11_0..12_2); gate=G0..G5 OK (ABSENT/NO_DEVICE -> SKIP, ABI -> FAIL;
all unsafe in the single module xiom.directx12); needs=NONE (allowlisted + baseline);
port.args.json present (--c-source src/d3d12_probe.c, no --link).
```

```
BINDINGS BATCH 10: head=c7db19b7 (code) + this handoff commit; packages=xiom.directx11 0.2.0
(capability probe replacing the pre-pilot static externs); tests=5/5 x2 via scripts/port.ps1
on v0.64.1 (2026-10-08: hardware device at feature level 11_0 (45056), 3 DXGI adapters, first
= NVIDIA GeForce RTX 3070 Ti vendor_id 4318 device_id 9346; deterministic SKIP classification
per run); licenses=MIT OR Apache-2.0 (header-free bridge is our code; nothing vendored);
pins=sonames d3d11.dll + dxgi.dll + Windows SDK 10.0.22621.0 header hashes (um\d3d11.h
B2C0CAA5..., shared\dxgi.h 4B983AC7..., um\d3dcommon.h 62F7BF1A...) + ABI (IID_IDXGIFactory1
{770aae78-f26f-4dba-a829-253c83d1b387}; IDXGIFactory1 slot 12=EnumAdapters1; IDXGIAdapter
slot 8=GetDesc; DXGI_ADAPTER_DESC offsets 0/256/260; D3D11_SDK_VERSION=7;
DRIVER_TYPE_HARDWARE=1; feature levels 9_3..11_1); local samples System32 d3d11.dll/dxgi.dll
10.0.26100.9549 (sha256 3E6C8932.../023542BB...); gate=G0 OK, G1 OK, G2 OK, G3 OK
(ABSENT/NO_DEVICE -> SKIP, ABI -> FAIL), G4 OK, G5 OK (all unsafe in the single module
xiom.directx11); needs=NONE (allowlisted + baseline); port.args.json present
(--c-source src/d3d11_probe.c, no --link).
```

```
BINDINGS BATCH 9: head=b282cf82 (code) + this handoff commit; packages=xiom.dxc 0.2.0
(capability probe replacing the pre-pilot bridge); tests=3/3 x2 via scripts/port.ps1 on
v0.64.1 (2026-10-08: dxcompiler.dll 1.9.0.5347 from Vulkan SDK 1.4.350.0: ps_6_0 'main'
-> 2532-byte DXIL object, 4-byte aligned; deterministic SKIP classification per run);
licenses=MIT OR Apache-2.0 (header-free bridge is our code; nothing vendored);
pins=soname dxcompiler.dll + dxcapi.h hashes (SDK copy FF3CA20C... + upstream commit
fe2615732 A8D40964...) + COM ABI (CLSID_DxcCompiler 73e22d93..., IID_IDxcCompiler3
228b4687..., IID_IDxcResult 58346cda..., IID_IDxcBlob 8ba5fb08...; compiler slot 3=Compile;
result slots 3=GetStatus,7=GetOutput; blob slot 4=GetBufferSize; DxcBuffer 24B;
DXC_OUT_OBJECT=1); local sample dxcompiler.dll 1.9.0.5347 sha256
6E990D20E53390CDE413CE9A8016A8F43582E325A04CF72ECC706B4BEA504F0C (dxil.dll not present;
unsigned DXIL); gate=G0 OK, G1 OK, G2 OK, G3 OK (ABSENT -> SKIP; ABI/compile failure ->
FAIL), G4 OK, G5 OK (all unsafe in the single module xiom.dxc); needs=NONE (allowlisted +
baseline); port.args.json present (--c-source src/dxc_probe.c, no --link).
```

```
BINDINGS BATCH 8: head=af564de9 (code) + this handoff commit; packages=xiom.vulkan 0.2.0
(capability probe replacing the pre-pilot static bridge); tests=10/10 x2 via scripts/port.ps1
on v0.64.1 (2026-10-08: loader 1.4.350, 20 instance extensions + head, 15 layers, device
NVIDIA GeForce RTX 3070 Ti type 2 api 1.4; deterministic SKIP classification per run);
licenses=MIT OR Apache-2.0 (header-free bridge is our code; Khronos header pinned by hash,
not vendored); pins=soname vulkan-1.dll + Vulkan-Headers tag vulkan-sdk-1.4.350.0
vulkan_core.h sha256 6D2BA4755774B1D129DA6B8E661268B494D2D609DF6217C6B6485ACF7666B6C2 +
entry-point set + ABI details (SPEC.md §2); local sample C:\Windows\System32\vulkan-1.dll
1.4.350.0 sha256 0419974F00E82A3D619077BA414DA265A774F8DB9D45AD93BC1843F44B2C2C1F;
gate=G0 OK, G1 OK, G2 OK, G3 OK (ABSENT/NO_DEVICE -> SKIP, ABI -> FAIL; bogus-soname test
every run), G4 OK (capability suite), G5 OK (all unsafe in the single module xiom.vulkan);
needs=NONE (already allowlisted); port.args.json present (--c-source src/vk_probe.c, no
--link; no Vulkan SDK or headers required).
SCOPE NOTE (native decision requested): the ~1.7MB pre-pilot Vulkan engine bridge
(bridge/xvk_*, stb headers, shaders, build.ps1/build.sh/run.ps1, old wrappers/tests/docs)
was removed in this batch and is preserved in git history only. 0.2.0 replaces it with the
loader-capability path. If you want the bridge material preserved visibly under a
non-compiled legacy/ directory before merge, say so and I will push a follow-up.
```

```
BINDINGS BATCH 7: head=9eb9ef5b (code) + this handoff commit; packages=xiom.opengl 0.3.0;
tests=xiom.opengl 13/13 x2 via scripts/port.ps1 on v0.64.1 (2026-10-08, NVIDIA RTX 3070 Ti:
classic 4.6 context, 3.3 core negotiated, 404 extensions with head + exact-match scan, bogus
extension correctly absent, deterministic SKIP classification); licenses=MIT OR Apache-2.0
(bridge is our code; nothing vendored upstream); pins=opengl G2 extended -- soname opengl32.dll,
symbol set + wglGetProcAddress/glGetIntegerv/glGetStringi (context-scoped via
wglGetProcAddress), WGL core-context attribs (0x2091/0x2092/0x2094/0x9126, core bit 0x1) and
GL query constants (0x821B/0x821C/0x821D) recorded in SPEC.md §2; gate=G0..G5 OK (core probe
keeps ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL; all unsafe confined to xiom.opengl);
needs=NONE (already allowlisted); port.args.json unchanged (--c-source gl_probe.c).
```

```
BINDINGS BATCH 6: head=bef3e71c (code) + this handoff commit; packages=xiom.raylib 0.2.0;
tests=xiom.raylib present 12/12 x2 (official raylib 5.5.0 win64 DLL on PATH: hidden 320x200
window, size, time/frame-time/FPS, target FPS, begin/clear/end frame, CloseWindow) and absent
3/3 x2 (SKIP), both via scripts/port.ps1 on v0.64.1, 2026-10-08; licenses=MIT OR Apache-2.0
(nothing vendored; raylib zlib untouched); pins=soname raylib.dll + tag-5.5 src/raylib.h
sha256 AFB287ECD313DE61E0000921375190B7E1CC35CD381AD6CAF914489473A3C871 + 15-symbol smoke set
(size functions rename-tolerant: prefers GetWindowWidth/Height, falls back to
GetScreenWidth/Height); local positive-path sample: official raylib-5.5_win64_msvc16.zip
sha256 8D046084D12353183E701EF4C9D276C21FCD3243C2A368091FABFB2769B8507C, lib\raylib.dll
FileVersion 5.5.0 sha256 C8D29FBDA31417B900BB0220CFB6C288544264A93764F5EA7CF5727FEEC76994;
gate=G0 OK (keywords:["binding"], license), G1 OK, G2 OK, G3 OK (ABSENT/NO_WINDOW -> SKIP,
ABI -> FAIL), G4 OK, G5 OK (all unsafe confined to the single module xiom.raylib);
needs=NONE (already allowlisted); NO port.args.json. NOTE: upstream latest is raylib 6.0 --
next re-pin candidate; the loader already tolerates the 5.x/6.x size-function rename.
Pre-pilot static-extern module removed to git history as reference.
```

```
BINDINGS BATCH 5: head=4cbf7079 (code) + this handoff commit; packages=xiom.sdl3 0.3.0;
tests=xiom.sdl3 present 21/21 x2 (SDL 3.4.8: smoke + hidden window / renderer clear+present /
RGBA8888 texture / gamepad enumeration) and absent 3/3 x2 (SKIP), both via scripts/port.ps1,
2026-10-08, COMPILER v0.64.1 (see note below); licenses=MIT OR Apache-2.0 (nothing vendored);
pins=G2 unchanged (soname SDL3.dll + release-3.4.8 header-set manifest
FD61D35102FDAC6FDDB944ED0192DFE4058222FDC531327F74264FF53B0E3023); gate=G0..G5 OK;
needs=NONE (already allowlisted); NO port.args.json.
PIN NOTE: repo COMPILER_VERSION still says v0.64.0 but the installed slot (and scripts/xiom.ps1
-Info) resolve v0.64.1, so all batch-5 runs are v0.64.1. Native lane: repin records/SPEC rows
as per your process; package SPEC rows for sdl3 0.3.0 already state v0.64.1.
V0.64.1 FINDINGS SWEEP (docs/BINDINGS-COMPILER-FINDINGS.md): B-06 FIXED (full-catalog
MigrationManager.up/down shape builds + 16/16), B-09 FIXED (Win32/WGL mega-block runs green
2/2, real GL string); B-01 enum-payload nondeterminism STILL OPEN (2/6 builds), B-05
alloc/free guard spin STILL OPEN (8 s watchdog kill, flat 4.5 MB), B-08 --run exit masking
STILL OPEN (main returning 5 -> exit 0). B-02/B-03/B-04/B-07 not re-tested (pre-fix catalogs
no longer exist); rebuildable from the findings doc.
```

```
BINDINGS BATCH 4: head=34ccd6ba (code) + this handoff commit; packages=xiom.glfw 0.2.0;
tests=xiom.glfw present 9/9 x2 (GLFW 3.4.0 official win64 binary on PATH) and absent 3/3 x2
(SKIP path), both via scripts/port.ps1, v0.64.0, 2026-10-08; licenses=MIT OR Apache-2.0
(nothing vendored; GLFW zlib untouched); pins=soname glfw3.dll + tag-3.4 header
GLFW/glfw3.h sha256 AA370985F6B493BBE0358A36AB49F5780A6397C0209C6D98A62143DEA595B73C +
resolved symbol set (glfwInit/glfwTerminate/glfwGetVersion/glfwGetVersionString/glfwGetTime/
glfwGetError); local positive-path sample: official glfw-3.4.bin.WIN64.zip sha256
54EFA829400F2A0537F742B2B3BDD74E437BB4F2F048E4B7D3C5557D11A611E6, lib-vc2022\glfw3.dll
FileVersion 3.4.0 sha256 4429ADFF...C14BB1, runtime build string "3.4.0 Win32 WGL Null EGL
OSMesa VisualC DLL"; gate=G0 OK (keywords:["binding"], license), G1 OK, G2 OK (soname +
header hash + symbol set + re-pin), G3 OK (ABSENT/NO_PLATFORM -> SKIP, ABI -> FAIL), G4 OK
(loader smoke), G5 OK (all unsafe confined to the single module xiom.glfw); needs=NONE
(already allowlisted); NO port.args.json (pure-XIOM loader). Also fixed the pre-pilot
module-name typo (xiom.glwf -> xiom.glfw) and removed the unlinkable C bridge.
```

```
BINDINGS BATCH 3: head=df8c76aa (code) + this handoff commit; packages=xiom.opengl 0.2.0;
tests=xiom.opengl 8/8 PASS x2 via scripts/port.ps1 (2026-10-08, v0.64.0) on an NVIDIA
RTX 3070 Ti (GL 4.6.0 NVIDIA 616.92); both runs also exercise the deterministic SKIP
classification (bogus soname -> OPENGL_LOAD_ABSENT); licenses=MIT OR Apache-2.0 (nothing
vendored upstream; src/gl_probe.c is our bridge code); pins=soname opengl32.dll + resolved
symbol set (glGetString/wglCreateContext/wglMakeCurrent/wglDeleteContext + user32
CreateWindowExA/DestroyWindow/GetDC/ReleaseDC + gdi32 ChoosePixelFormat/SetPixelFormat) +
PIXELFORMATDESCRIPTOR layout; local sample opengl32.dll FileVersion 10.0.26100.9278
sha256 659BE03C...A5ECE, runtime strings in SPEC.md §2; gate=G0 OK (keywords:["binding"],
license), G1 OK, G2 OK (pin + re-pin procedure), G3 OK (ABSENT/NO_CONTEXT -> SKIP, ABI ->
FAIL; SKIP path deterministically testable on any host), G4 OK (staged probe suite), G5 OK
(all unsafe/extern confined to the root module xiom.opengl); needs=NONE (already
allowlisted). NOTE: this package DOES use port.args.json (--c-source ${PACKAGE_DIR}/
src/gl_probe.c) -- the runner hook compiles the bridge, no --link flags.
```

```
BINDINGS BATCH 2: head=f3553cc3 (code) + this handoff commit; packages=xiom.sdl3 0.2.0;
tests=xiom.sdl3 present 10/10 x2 (SDL 3.4.8 on PATH) and absent 3/3 x2 (SKIP path), both
through scripts/port.ps1, v0.64.0, 2026-10-08; licenses=MIT OR Apache-2.0 (nothing
vendored; SDL3 itself untouched, zlib); pins=soname SDL3.dll + SDL release-3.4.8 header
set manifest sha256 FD61D35102FDAC6FDDB944ED0192DFE4058222FDC531327F74264FF53B0E3023
(7 headers listed in SPEC.md §2; local positive-path sample: Vulkan SDK 1.4.350.0 SDL3.dll
FileVersion 3.4.8.0 sha256 6E2B4B6A...C263, runtime reports 3004008); gate=G0 OK
(keywords:["binding"], license), G1 OK, G2 OK (soname + header manifest pin + re-pin
procedure), G3 OK (SKIP path never FAILs; ABI mismatch is an explicit FAIL kind), G4 OK
(loader smoke: load/version/revision/init/was_init/ticks+delay/perf/pump/poll/quit/release),
G5 OK (all unsafe + fn-pointer casts confined to the single module xiom.sdl3); needs=NONE
(already allowlisted; no ops ask; NO port.args.json required -- the loader needs no C source
or extra compiler flags, which is the design point of the dynamic-loader path).
```

```
BINDINGS BATCH 1: head=dfaa17b2 (+ this handoff commit); packages=xiom.sqlite 0.2.0;
tests=xiom.sqlite 16/16 PASS x6 consecutive build+run cycles (default compiler flags,
2026-10-08, v0.64.0); licenses=package MIT OR Apache-2.0, vendored SQLite 3.53.4
Public Domain (vendor/LICENSE); pins=sqlite3.c sha256
B1DD5D74EC7F29055A6684FA06FB3C2F6821C87DD38F9A458DFD2E8A1DB28189, sqlite3.h sha256
919E7F2E8ED1D8F56AC17B412B8971C76AA5D1A879752CC6058F75E7D5910E1D, sqlite3ext.h sha256
AC9645E5C9FF0CF176EFDD6E75CB5E98F46295D38E02DB5C4D208826A39AB4BE, upstream
sqlite-amalgamation-3530400.zip sha3-256 628a44cf...27934e verified with certutil and
sha256 1E71DDF9...E87D; gate=G0 OK (keywords:["binding"], license), G1 OK (compiles on
the pin), G2 OK (SHA256 over vendored header set + version 3.53.4/libversion_number
3053004 pinned in SPEC.md), G3 n/a vendored path (no SKIP case: the amalgamation is
compiled in), G4 OK (16 functional checks incl. open/exec/prepared/bind/error codes),
G5 OK (all unsafe+extern confined to src/ffi.xi; facade+satellites pure); namespace-check
xiom.sqlite OK (0 conflicts vs 1724 namespaces);
needs=1) allowlist append + ops scope enumeration for xiom.sqlite (native lane);
2) port.ps1 runner hook for per-package extra compiler args, resolved package-relative:
   xiom --run tests/test_conformance.xi --c-source <abs>/vendor/sqlite3.c --opt-level
   default; --c-source needs an ABSOLUTE path (clang cwd is a scratch dir) and the
   suite needs >=180s watchdog (amalgamation compiles at link time, ~25-50s observed);
   same hook will serve the sdl3/opengl SKIP suites.
```

Suggested owner one-liner to forward to the native session:

> Bindings batch 1 (xiom.sqlite) is green on branch `bindings` at dfaa17b2:
> relay in E:\xiom-packages\bindings\BINDINGS-SESSION.md; merge + allowlist
> append for xiom.sqlite + port.ps1 per-package compiler-args hook requested.

## Session ledger

- Worktree: `E:\xiom-packages\bindings`, branch `bindings`, kept fresh
  (merged origin/main at 6fa4f9a6 before starting; relay transport commit
  ceeea349 noted).
- Pilot package 1 of 3: **xiom.sqlite** -- done, pending native merge/publish.
  Per the plan, work on xiom-sdl3 starts after the native session merges and
  publishes this batch.
- Suite command (from `packages/xiom-sqlite`):
  `xiom --run tests/test_conformance.xi --c-source <abs>\vendor\sqlite3.c`
  Evidence: 6 consecutive build+run cycles 16/16 PASS (22-31s each; first cold
  run ~50s). The compile+run is deterministic now -- see enum finding below.
- G2 pin verified from git blobs, not just the worktree:
  `git cat-file -p HEAD:packages/xiom-sqlite/vendor/sqlite3.c` SHA256 ==
  B1DD5D74... and byte length 9,515,341. `vendor/** -text` (package-local
  .gitattributes) prevents core.autocrlf from breaking the pins on fresh
  checkouts.

### Compiler findings (v0.64.0) -- details for docs/COMPILER-FINDINGS.md

1. **Enum payload reads miscompile nondeterministically across BUILDS.**
   `SqliteValue` as a user enum with payloads (`Integer(Int)`, `Text(Str)`,
   ...) made accessors fail in ~50% of rebuilds of the SAME source
   (11/16 vs 16/16 passes; a 4-check micro probe flipped to all-false in 1 of
   6 builds, i.e. the whole enum layout was wrong in that build). Same class
   as the existing `xiom.graphql` enum-payload finding. Fixed by a tagged
   struct (`kind` + plain fields); 8/8 micro builds and 6/6 suite builds
   green after the change. Re-test the enum model at the next pin.
2. **`pub const` references inside confined (`unsafe`) blocks and long
   const-if chains recurse the resolver** -> compiler stack overflow
   (exit 0xC00000FD) in full-catalog builds. Workaround: literals inside
   `src/ffi.xi` bodies and in `error_name`; public consts unchanged.
3. **Cross-module const aliases** (`pub const A: Int = other.B`) recurse the
   resolver when referenced. Facade consts use literal values.
4. **Child modules cannot import their parent** (known: documented in
   `xiom-vault`). FFI core is a sibling (`xiom.sqlite.ffi`); only the parent
   facade imports children.
5. **`xiom.ffi.alloc` inside a confined block + `xiom.ffi.free` spins.**
   The guard pass rewrites `alloc` to `xiom_guard_alloc` inside the block
   while `free` stays libc; the guard heap then loops (flat memory, 100% CPU
   -- watchdog it). Workaround: no malloc/free in confined blocks; C
   out-params write into an XIOM-owned `Vec[UInt8]` slot.
6. **A module exporting an associated fn whose last segment is `up` (or
   `down`) crashes the compiler with `xiom.test` in the catalog.**
   Migration methods renamed `migrate_up`/`migrate_down`.
7. **Unqualified imports from library modules do not resolve** (`use
   xiom.sqlite;` then bare `prepare(...)` -> undefined variable); sibling
   module qualification (`ffi.prepare(...)`) works. Also `use xiom.ffi;` in
   a module named `...ffi` shadows the alias -> avoid the stdlib import there.
8. Note: `xiom --run` returned exit 0 for a suite whose `main` returned 5;
   port.ps1's [PASS]/[FAIL] marker counting is the reliable signal.

### Safety note (owner-facing)

A hung test binary from this lane (the alloc/free guard-heap spin, finding 5,
before it was diagnosed) ran ~21 minutes burning CPU and is the most likely
contributor to the 98 GB memory event / restart at 11:54 on 2026-10-08.
After diagnosis all runs used a memory/time-capped watchdog; the final suite
runs peaked at ~7 MB RSS. No other lane process was touched.

## Inbound context (2026-10-08, after batch 1 merged @ 05a19deb, wrapped 5ea29bb5/2cb3f03a)

- Batch 1 merged and wrapped: `xiom.sqlite` 0.2.0 is on the allowlist (505 names);
  `port.args.json` hook live (`docs/BINDINGS-LANE.md` §10); findings recorded in
  `docs/COMPILER-FINDINGS.md`. **sdl3 starts only after the eco-v0.1.89 publish
  confirmation** (owner/native relay); keep-fresh before starting.
- New project lanes joined the ecosystem (Projects -> packages -> stdlib ->
  compiler): PULSE (web), ORBITDB (embedded DB), XVECTOR (vector DB). Relays were
  addressed to the packages lane; binding-relevant reads:
  - ORBITDB (`docs/RELAY-PACKAGES-ORBITDB.md`): **"No C-FFI/bindings need from
    ORBITDB (pure XIOM target)"** -- acknowledged, nothing for this lane.
  - XVECTOR (`docs/PACKAGE-WISHLIST-XVECTOR.md`): proposes `xiom.vectors`,
    `xiom.wal`, `xiom.ann` (pure-XIOM domain layers, native-lane coordination);
    the accelerator row asks the bindings lane to `Watch` for the Phase 10
    SIMD/kernel path and to say whether a pure-XIOM SIMD kernel package is
    planned before they propose a second kernel package.
- Bindings-lane position (for relay to XVECTOR/native):
  1. `xiom-blas` / `xiom-eigen` / `xiom-openblas` exist in THIS worktree as
     pre-rostered `incubating` placeholders (tests `unknown`; specs describe
     CBLAS/OpenBLAS FFI, current code is stubs -- same pre-pilot state
     `xiom.sqlite` was in). Nothing published; no timeline is promised. When the
     bindings Phase 2 reaches them they will be opt-in accelerators behind the
     portable `xiom.vectors` contract -- the binding API surface should mirror
     the pure-XIOM functions, never define them.
  2. The bindings lane plans **no pure-XIOM SIMD kernel package**; that is
     native/stdlib territory. If `xiom.simd`-class work appears there, bindings
     adopt it as the portable path and keep FFI libs as drop-in accelerators.
  3. Name/scope coordination for `xiom.wal` (ORBITDB vs XVECTOR duplication) is
     a native-lane call; this lane has no storage-format stake.

## Batch 2 notes (xiom.sdl3, 2026-10-08)

- Dynamic loader replaces static externs: `sdl3_load` (via `xiom.ffi.dl`)
  resolves SDL3.dll at runtime. Absent -> `SDL3_LOAD_ABSENT`; the suite prints
  explicit SKIP labels under `[PASS]` markers (green without the SDK).
  Present-but-missing-symbol -> `SDL3_LOAD_ABI` (explicit `[FAIL]`; handle
  closed, no leak).
- The static-extern module `src/sdl3_safe.xi` and the extern tail of the old
  root module were removed: they cannot satisfy G3 and would fail linking
  without SDL3. The full pre-pilot SDL3 3.4.8 constant tables and resource
  wrappers remain in git history (pre-0.2.0) and return in Phase 2
  (`ROADMAP.md`).
- Run matrix through `scripts/port.ps1`: absent 3/3 x2 (PATH without the
  Vulkan SDK dir), present 10/10 x2 (SDL 3.4.8 from the Vulkan SDK on PATH;
  runtime reports 3004008, revision `SDL-3.4.8-release-3.4.8`). The demo was
  run against the same DLL.
- **No `port.args.json`**: the pure-XIOM loader compiles no C source and needs
  no extra flags (contrast `xiom.sqlite`, which needs
  `--c-source vendor/sqlite3.c`). CI runs the suite unchanged.
- G2 pin: soname `SDL3.dll` + `release-3.4.8` header-set manifest
  `FD61D351...E3023` (per-file hashes in `SPEC.md` §2).

## Batch 3 notes (xiom.opengl, 2026-10-08)

- Loader/probe design: vendored `src/gl_probe.c` resolves opengl32/user32/
  gdi32 at runtime and stages symbol -> contextless -> real-context probes;
  classification ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL. The XIOM module is
  a thin safe wrapper (all `unsafe`/`extern` in one module, G5).
- The pure-XIOM Win32/WGL context path was abandoned first: it poisoned the
  binary pre-output (0xC0000409, deterministic). Bounded repro + control
  preserved in `docs/repro/bindings-pilot/win32-gl-unsafe/`; recorded as
  finding **B-09** (the first lane finding with a deterministic, no-watchdog
  runnable repro).
- `opengl_probe_named("bogus.dll")` gives every host (GPU or not) a
  deterministic SKIP-branch test, so the no-GPU CI shape is exercised even on
  developer machines.
- Run matrix: `port.ps1 -Package xiom.opengl` -> PASS 8/8 x2 (NVIDIA RTX 3070
  Ti, GL 4.6.0 NVIDIA 616.92, GLSL 4.60 NVIDIA; VENDOR/RENDERER strings in
  SPEC.md §2). No-context SKIP path code-reviewed, not force-tested locally.
- `port.args.json` is present (`--c-source ${PACKAGE_DIR}/src/gl_probe.c`);
  no `--link` flags are needed because the bridge loads everything
  dynamically.

## Batch 4 notes (xiom.glfw, 2026-10-08)

- Same system-lib SKIP pattern as xiom.sdl3: `glfw_load` resolves
  `glfw3.dll` via `xiom.ffi.dl`; classification ABSENT / NO_PLATFORM (init
  fails headless) -> SKIP, ABI -> FAIL. All `unsafe` in the single module.
- Pre-pilot defects fixed in passing: the module was declared `xiom.glwf`
  (typo) and the C bridge required GLFW headers/import libs at build time
  (could not satisfy G3). Bridge + stale tests/demos removed; history keeps
  them as reference.
- Run matrix: absent 3/3 x2 (no glfw3.dll on PATH); present 9/9 x2 against
  the official GLFW 3.4 win64 binary (`lib-vc2022`, FileVersion 3.4.0,
  build string `3.4.0 Win32 WGL Null EGL OSMesa VisualC DLL`).
- No `port.args.json`; no new compiler findings (the loader avoids the known
  v0.64.0 classes; out-params use XIOM-owned Vec slots per B-05).

## Batch 5 notes (xiom.sdl3 Phase 2, 2026-10-08)

- Resource stage is a separate loader (`sdl3_load_resources`, 19 symbols) so
  an older SDL3 still gets the smoke SKIP classification; a missing resource
  symbol fails only the resource stage. Window paths SKIP cleanly when the
  platform cannot create a window; gamepad open/close runs only when a
  device is attached (none here -> SKIP line).
- Runs on **v0.64.1** (installed slot; repo pin file still v0.64.0). The
  resolver picks 0.64.1 over the pin, so batch-5 STATUS/green evidence is
  v0.64.1; SPEC rows updated accordingly.
- v0.64.1 sweep of lane findings moved B-06 and B-09 to FIXED with
  reproductions re-run; B-01/B-05/B-08 remain open and their workarounds
  stay in force (tagged-struct value model, no malloc/free in confined
  blocks, marker-based pass/fail checks).

## Batch 6 notes (xiom.raylib, 2026-10-08)

- Same system-lib SKIP pattern: `raylib_load` resolves `raylib.dll` via
  `xiom.ffi.dl`; classification ABSENT / NO_WINDOW (headless) -> SKIP,
  ABI -> FAIL. The smoke sets `FLAG_WINDOW_HIDDEN` before `InitWindow` so a
  desktop session proceeds; `IsWindowReady()` checks the result because
  `InitWindow` is void.
- The 5.5 DLL exports `GetScreenWidth/GetScreenHeight` (not the 6.x
  `GetWindow*` names): the loader prefers the 6.x names and falls back, so
  both generations resolve -- the first present-path run surfaced this as an
  ABI FAIL, which is why the pin table records it.
- Run matrix: absent 3/3 x2 (no raylib.dll on PATH); present 12/12 x2
  against the official raylib 5.5 win64 binary (hidden 320x200 window, size
  320x200, begin/clear/end frame).
- Upstream latest is raylib 6.0 (package pins 5.5, the pre-pilot target);
  flagged as the next re-pin candidate in SPEC/relay.
- No `port.args.json`; no new compiler findings.

## Batch 7 notes (xiom.opengl Phase 2, 2026-10-08)

- Core-profile probe: a temporary classic context obtains
  `wglCreateContextAttribsARB`; the requested core context (3.3 here) is
  created and the negotiated version + extension count/head reported;
  `opengl_has_extension` scans `glGetStringi` with exact match. Probes stay
  atomic (load -> context -> query -> unload); no session state leaks.
- Runs on v0.64.1: 13/13 x2 (classic 4.6 strings, 3.3 core, 404 extensions,
  bogus extension absent, aniso present). The SKIP classification test runs
  in every suite invocation (bogus soname -> ABSENT).
- Bridge refactor kept everything in `src/gl_probe.c` (context helpers);
  `port.args.json` unchanged. All XIOM `unsafe` still in the single module.
- Next options for batch 8: `xiom.vulkan` (GPU tier per the Phase-2 order)
  or the opengl session API (`opengl_session_get_proc` function-table seam)
  -- native lane to pick; the roadmap lists both.

## Batch 8 notes (xiom.vulkan, 2026-10-08)

- Header-free capability bridge: `vkGetInstanceProcAddr` seam; minimal
  instance-create ABI declared locally; loader-written structs received into
  opaque 2048-byte buffers. No Vulkan SDK needed to build or run the probe.
- Two bugs found by the first present-path run and fixed in the bridge:
  (1) enumeration with capacity < count returns `VK_INCOMPLETE`(5), which was
  treated as failure (empty extension head); (2) instance-level functions were
  resolved via `vkGetInstanceProcAddr(NULL, ...)` -- they must use the
  instance handle, otherwise device enumeration silently yields 0 devices.
- Runs: 10/10 x2 (loader 1.4.350; 20 extensions; 15 layers; RTX 3070 Ti
  discrete, api 1.4). SKIP classification runs every suite invocation.
- Scope decision requested from the native lane: the pre-pilot static-bridge
  engine was removed to git history in this batch (same treatment as
  sdl3_safe.xi / glfw_bridge.c / opengl static wrappers).

## Batch 12 notes (xiom.zstd, 2026-10-08)

- Vendored path proven end-to-end for a multi-file C library: used the
  upstream `combine.py` to generate the official single-file amalgamation
  (v1.5.7), vendored it + `zstd.h` + LICENSE, and compiled it via a 4-line
  shim (`STATIC_BMI2 0`) because the xiom link line has no `-mbmi2` -- the
  first build failed exactly there and the shim fixed it without touching
  the vendored bytes.
- Real functional suite: 8192 -> 34 bytes at level 3, frame content size,
  auto-size decompress, incompressible round-trip, invalid-frame rejection.
- Line-ending trap caught: `combine.py` under Windows Python emits CRLF, so
  the committed (LF) blob differed from the first hash. Pin corrected to the
  stored LF bytes; `vendor/** -text` protects it from autocrlf (same as
  `xiom.sqlite`). Re-pin procedure now says to normalize before hashing.
- Run matrix: 8/8 x2 plus a re-run after normalization. Allowlisted +
  baseline; `port.args.json` compiles the shim; amalgamation compile ~40-60s
  (240 s watchdog headroom).
- Next: `xiom.lzfse` (small vendored C, same path), then `xiom.ozz`.

## Batch 11 notes (xiom.directx12, 2026-10-08)

- Max-level capability probe: descending `D3D12CreateDevice` attempts
  (12_2 -> 11_0); the RTX 3070 Ti accepts 12_2. The DXGI adapter
  vtables/offsets verified for directx11 were reused unchanged; the only new
  ABI is `IID_ID3D12Device` + the `D3D12CreateDevice` signature.
- Run matrix: 5/5 x2 first-try; SKIP classification (bogus sonames) every
  run. Allowlisted + baseline; `port.args.json` compiles the bridge.
- Pre-pilot module (~17 KB static D3D12 externs) removed to git history.
- Next: compression tier -- `xiom.zstd` (vendored C path; the sqlite
  `--c-source` machinery + `port.args.json` are proven, but zstd is many
  translation units: plan a `src/zstd_all.c` shim that #includes the vendored
  `lib/` sources, or vendor the official single-file amalgamation if one is
  published for the pinned release).

## Batch 10 notes (xiom.directx11, 2026-10-08)

- Header-free ABI extraction paid off again: the DXGI vtables were pinned
  from `dxgi.h` before writing the bridge (factory slot 12 = EnumAdapters1,
  adapter slot 8 = GetDesc, desc offsets 0/256/260) -- the first present-path
  run created a hardware device and read the adapter name with no iteration.
- `D3D11CreateDevice` with a NULL feature-level array returns 11_0 on this
  driver; explicit 11_1 needs a requested feature-level list (Phase 2).
- Adapter enumeration returns 3 entries on this host; the first is the
  NVIDIA RTX 3070 Ti (`vendor_id 4318` = 0x10DE, `device_id 9346` = 0x2482).
- Run matrix: 5/5 x2; SKIP classification (bogus sonames) every run.
  Allowlisted + baseline; `port.args.json` compiles the bridge.
- Pre-pilot module (22 KB static `extern "C"` D3D declarations) removed to
  git history.

## Batch 9 notes (xiom.dxc, 2026-10-08)

- Header-free COM bridge: `dxcapi.h` was read from the SDK and used as the
  specification (GUIDs + vtable slot offsets), but the bridge declares the
  ABI locally and drives `IDxcCompiler3`/`IDxcResult`/`IDxcBlob` through raw
  vtable pointers -- no SDK header or import library at build time.
- First present-path run compiled a real `ps_6_0` shader to a 2,532-byte DXIL
  object on the first try (ABI extraction paid off; a wrong slot would have
  crashed rather than failed softly).
- `dxil.dll` is not in the SDK `Bin` here; unsigned DXIL is fine for the
  capability probe (validator seam is a Phase 2 item).
- Run matrix: 3/3 x2; SKIP classification (bogus soname) every run. Already
  allowlisted; `port.args.json` compiles the bridge.
- Pre-pilot bridge (77 KB, SDK headers + import libs) removed to git history.

## Inbound checks (2026-10-08, post-batch-8: project lanes + stdlib)

- **PULSE** (`docs/PACKAGE-WISHLIST-PULSE.md` bindings section): first binding
  request is "a durable database/KV client binding (SQLite/Postgres or
  similar) to back the event store and sessions beyond JSONL". **Already
  served**: `xiom.sqlite` 0.2.0 is published (eco-v0.1.89) and is exactly that
  durable store path; PULSE keeps JSONL as its documented fallback until it
  adopts. Outbound HTTP client is explicitly "not yet needed"; TLS is
  explicitly NOT a binding (front proxy). No new work item for this lane.
- **ORBITDB**: `RELAY-PACKAGES-RESPONSE-ORBITDB.md` and
  `STDLIB-WISHLIST-ORBITDB.md` contain no bindings-lane asks ("No C-FFI
  needs", pure-XIOM target). Nothing to do.
- **XVECTOR**: `RELAY-PACKAGES.md` restates the accelerator watch
  (`xiom-blas`/`eigen`/`openblas` behind the portable `xiom.vectors` API);
  unscheduled here, no new ask.
- **Stdlib response** (`docs/BINDINGS-STDLIB-WISHLIST.md` updated):
  stdlib **0.64.2** delivered W-1 `fs_remove` (also the shared wishlist's
  2026-10-05 row) and corrected the W-4 `dl` cast note; `SafePtr`/`FFIBuffer`
  typed slot helpers pre-existed (W-2 re-scoped to a docs ask); W-3
  (guard-aware `free`) and W-5 (`Vec.with_len`) remain open.
- **Compatibility spot-check on stdlib 0.64.2**: `port.ps1` green for
  `xiom.glfw` (3/3, SKIP path) and `xiom.sqlite` (16/16). No suite changes
  needed.
- **Wave continuation**: batch 9 starts `xiom.dxc` (GPU tier: shader-compiler
  binding over the same runtime-loader + SKIP pattern), then dx11/12.

## Phase-2 sector order proposal (Phase 1 pilot complete)

Ordered by risk retired per unit of work, stable ABIs first, each slice
proving one lane pattern already established in the pilot:

1. **Window/input tier + reuse**: finish `xiom.sdl3` Phase 2 (window/renderer/
   texture/gamepad over the loader) and add `xiom.glfw` + `xiom.raylib` with
   the same system-lib SKIP pattern. Highest ecosystem pull (the projects
   consume these first); no new lane mechanics.
2. **GPU tier**: `xiom.opengl` Phase 2 (extension loading + context
   attributes + function table) then `xiom.vulkan` (bridge precedent already
   exists in-repo; loader + capabilities first), then `directx11/12` and
   `dxc` (Windows-only, keep the same classification model).
3. **Compression tier**: `xiom.zstd`, `xiom.lzfse`, `xiom.ozz` -- vendored-C
   path (proven by sqlite) with per-package `port.args.json`; smallest
   per-package effort, high publish value.
4. **Data/drivers**: `xiom.libpq`, `xiom.odbc` (system-lib SKIP or vendored
   client), after the sqlite pattern is already published.
5. **Audio tier**: `xiom.miniaudio`, `xiom.portaudio`, `xiom.phonon` --
   system-lib SKIP shape; device paths capability-gated.
6. **Accelerators (XVECTOR/ORBITDB-facing)**: `xiom.openblas`/`xiom.eigen`/
   `xiom.blas` behind a portable pure-XIOM contract (XVECTOR's `xiom.vectors`
   seam), unscheduled until the projects freeze that contract; no pure-XIOM
   SIMD kernel is planned in the bindings lane (position recorded in the
   inbound-context section).
7. **Crypto/media/heavy**: `xiom.openssl`, `xiom.ffmpeg`
   (license-conditional), `onnx`/`opencv` -- last, per the plan's phasing.

Each package keeps: G0-G5 gates, green x2 through `port.ps1`, a relay block
in this file, and any new compiler finding appended to
`docs/BINDINGS-COMPILER-FINDINGS.md` with a bounded repro.

## Next (after native merge + publish confirmation)

Phase 1 pilot is **complete** (sqlite published; sdl3 + opengl relayed). On
the native merge/publish confirmation for batches 2-3, batch 4 starts the
Phase-2 order above with slice 1 (`xiom.sdl3` Phase 2 completion or
`xiom.glfw`, whichever the native lane prioritizes), one package per relay.
