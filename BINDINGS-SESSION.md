# BINDINGS-SESSION -- xiom-packages bindings lane

Handoff file for the native session. Read the relay block first; the ledger
below records evidence and open asks.

**STATUS: EVERYTHING THIS LANE SHIPPED IS LIVE -- last: `eco-v0.1.199`
(NVIDIA wave COMPLETE: cublas/cufft/cusparse/tensorrt/nvml/nvapi/optix;
`eco-v0.1.198` = vectors 0.2.0 + pulse 0.2.2 + onnx 0.2.0 DML) -- through
`eco-v0.1.199` (114 eco releases); **pin = v0.64.7** (repin delta pushed;
slot verified; .7 re-verify: B-16/17/18/19/22/23/25/26 FIXED; glfw 37/37 +
sdl3 72/72 x2; retirement unlocked; B-26 sqlite restore wave launched);
recent cycle highlights: E-family COMPLETE (jolt 0.5.0/0.6.0/0.7.0,
E1-E7), LIFTS live (`eco-v0.1.185`: glfw 0.6.0 + sdl3 0.20.0 -- B-22/B-15
retired), PULSE top-tier live (`eco-v0.1.189`: brotli + ssl,
consumer-verified), family+Beacon (`eco-v0.1.192`), miniaudio 0.5.0
publish-requested; v0.64.6 REPIN WAVE COMPLETE (packages 569/0; m334
tuple closed; B-32 residual -> m358; W1.1/W1.3/W2.1 fixed; B-29/W1.4/W2.3
still red)** --
LIVE: jolt 0.7.0 (E4 soft bodies + E5 heightfield) + jolt 0.6.0
(E3 motors/limits + E6 convex/compound) + jolt 0.5.0 (E1 queries + E2
capsule + E7 contacts/sensors; 67/67 x2) + wave 2 (`eco-v0.1.178`: opus/
ogg/lz4/ktx2/vdb/phonon 0.3.0) + wave 3/A05 (`eco-v0.1.179`) + codec wave
A (`eco-v0.1.176`: jolt 0.3.0/zstd 0.3.0/meshopt 0.5.0/ffmpeg 0.3.0) +
wave B first (`eco-v0.1.177`: harfbuzz/basisu/spz 0.1.0); dx12 0.3.1
stable (`eco-v0.1.169`) +
dx12 0.4.0 (`eco-v0.1.172`), opengl 0.5.0 (`eco-v0.1.170`), gles 0.1.0
(`eco-v0.1.171`), sdl3 0.18.0 (`eco-v0.1.173`), sqlite 0.4.0
(`eco-v0.1.174`) + 0.4.1 modules fix (`eco-v0.1.175`; sha256
`21c1f673...`; x2 21/21 on `c239b90e`); Vulkan 0.6.0 live (OWNER lane);
SDK100 all slices live; v0.64.4 pin wave done.  **NEXT SESSION = ANDROID
first** (owner 2026-10-15; SDK `C:\Android\sdk` verified -- NDK r27b,
aarch64 cross-smoke green) **then the next compiler archive (v0.64.5+)
carrying the m277-m283 fix batch** (m277 B-22; m279
B-16/B-17; m280 `-2230`; m281 B-23/B-24/B-20/B-11 addendum; **m283
`3ef4d6a9` B-26 FIXED + B-25 green + contract-cycle guard**; B-05 stdlib
guard_free in wave 124 but still red on v0.64.4 even with
`XIOM_RUNTIME_DIR`) -- then the re-verify wave + glfw 0.6.0 lift + sdl3
widening + workaround retirement + **sqlite nested-shape restore**.
**glfw 0.6.0 lift parked until then.**  **WAVE-2 (12 pkgs: opus/ogg/
lz4/ktx2/vdb/phonon/fidelityfx/nis/dlss/xess/nrd/oidn) LIVE in
`eco-v0.1.178`** (engine relayed `-1259-packages`); **WAVE-3 (11 pkgs:
ffmpeg 0.4.1 SHIP-only, jolt 0.4.0, ozz 0.4.0, sdl3 0.19.0, rtxgi +
rtxdi, rpr, openpgl, stb 0.3.0, exr, photometrics) + A05 LIVE in
`eco-v0.1.179`** (run 38577890832 green; merge `945b795f`, wrap
`52dc853b`; ops allowlist 540; ffmpeg 0.4.0 stays held -- 0.4.1
supersedes).  B-27..B-31 canonized: B-27/28 REAL vs the stale stdlib
snapshot bundled in v0.64.4 (stdlib main fixed `45d0337`; retire the
workarounds at the next re-vendored pin); B-29/30/31 compiler open.**  PULSE co-verify: driver surface
GREEN 24/24 in-tree; registry-artifact re-run waits on the compiler
project-dependency fix (`REL-20261013-1731-packages`, "modules list
ignored"); sqlite 0.4.1 modules list published.  Ops clobber rules in
force; per-touch PROVENANCE rule in effect (dx12/opengl/gles/sdl3/sqlite
compliant; matrix declared=4, backlog 33; `modules:` retrofit at touch --
41 published + 26 unpublished remain fleet-wide).  UPDATE 2026-10-13
18:05Z (origin/bindings tip `9600ae26`)** (NEXT = Android first, then
watch v0.64.5+; the paste prompt below carries the wave).

**UPDATE 2026-10-12 00:00Z (doorbell)**: `xiom.sdl3` **0.16.1 (B-19
SDL_WasInit width fix) PUBLISHED in `eco-v0.1.160`** (batch 62; tally **76
eco releases**, `eco-v0.1.86`..`160`). SDK100 waves 1+2 **merged + staged**
by packages (eleven packages: six wave-1 + sdl2/spirv-headers/shaderc new,
vma 0.3.0, sdl3 additive full surface; publish gated on ops scope staging +
the v0.64.4 pin). Compiler v0.64.4 release pin commit `df493530` is on
origin/main; GitHub archive pending (watch `wku_12d5ced75001IgfN8Gx3fuV98t`,
00:17Z). Relay validate green (322 items); no new bindings items at 00:00Z.

**UPDATE 2026-10-12 13:40Z (context-limit handoff)**: **v0.64.4 IS
PUBLISHED** -- https://github.com/xiom-lang/xiom/releases/tag/v0.64.4
(13:36:58Z; assets include `xiom-0.64.4-windows-x64.zip` + `SHA256SUMS`).
The **archive wave is the NEXT ACTION** (pin + re-verify per the checklist
below; expected: B-13/14/15/1904/B-18 green, B-16/B-17 still red by design,
B-19 fixed package-side). The **SDK100 program is COMPLETE on the bindings
side** (12/12 slices, oracle==bound==resolved evidence,
`docs/SDK100-COVERAGE.md`); the **eleven packages are staged** by packages
and their publish is unblocked by this pin (also unblocks the jolt re-pin).
This session hits its context limit; the NEXT-SESSION PASTE PROMPT below is
rebuilt (archive wave = item 0).

**UPDATE 2026-10-12 13:57Z (v0.64.4 archive wave -- COMPLETE)**: Pin landed --
archive `44a41aea...` sha256-verified; the canonical slot
`%LOCALAPPDATA%\xiom.new` is byte-identical to the release zip (556/556 files;
exe `DB8A2EF0...`); `COMPILER_VERSION` bumped + `status.ps1 repin` **532
records** + validate **532/0**; commit `1f850919` pushed. Wave verdicts on the
v0.64.4 slot (`XIOM_COMPILER=%LOCALAPPDATA%\xiom.new\bin\xiom.exe`): **B-13
FIXED** (probe2 `local=42 relay=42`; probe4 `param_to_fnparam=42
local_to_fnparam=42 cast_fnparam=42`; probe5 `42/42/42`), **B-14/B-15 FIXED**
(probe7 now compiles -- r=1/exit 1, element call true + early(0)), **B-18
FIXED** (probe3 `fnparam=42`; probe6 `reg_double=42 reg_triple=63`; probe8
full output `after=42 / callee-after=42 / main-after r=7`), **1904/B-12
FIXED** (glfw probes: `advance_ms=304`, `after_set99_ms=99000`,
`opacity_x1000=1000`, `gettime_ms=5`, `vs_len=43`); probe control column
intact (`control=42 direct=42 stored=20`; `calls=1 key=65 sc=33 action=1
mods=5`; `close_win=4242`). **B-19 green package-side** (`elapsed=100 init=1
w_all=16384`). **B-10 NEWLY GREEN (not claimed by the wave)**: odbc
`alloc`-name scratch control -- v0.64.3-compiled exe spins+leaks (25 s cap;
338 MB / 41.7 CPU-s) vs v0.64.4-compiled exe **5/5 green**; the name-keyed
guard redirect is gone (row -3 can close at this pin; likely covered by the
batch-1 module-local precedence work). Still red / not in the wave: **B-16**
(`ptr_write_sum=11`, `byte_index_sum=66`), **B-17** (wild `d0=-16336..
d100=52208`; Int-typed `d12=12` exact), **B-20** (XIOM `0/0` vs C-side
`1065353216/1073741824`), **B-11** (`inside: a=3 b=0 c=1 rc=0`), **B-05**
(alloc-guard-spin still spins: 15 s cap, ~24 CPU-s, flat 4.5 MB), **B-07**
(2x T001 `c_strlen`). **B-02 re-verified**: scratch reconstruction (29 const
arms in `error_name` + `rc != SQLITE_OK` in the confined blocks) compiles +
suite **16/16**. **Jolt unblocked**: port **4/4 x2** with native
`--cxx-standard 17` (m258; threaded in `port.args.json`) -- `-1815`
satisfied; jolt re-pin/publish free. Suites: **sdl3 59/59** (B-19 witness
line PASS), **glfw 37/37** (no SKIP; callbacks 20/20; `--link user32`
auto). Next: compiler reply item + release-check row updates, then the
workaround lift (glfw/sdl3 dispatcher + registry, 1-arg handler shapes) via
the normal batch flow.

**UPDATE 2026-10-12 14:05Z (queue after the pin)**: relay reply pushed
(`f8fe214`: new item `REL-20261012-1400-bindings` + release-check rows filled;
`-3` B-10 moved to **verified**; `-1815` archive-verified; `-1533`/`-1731`
history updated). Packages batch 63 (`eco-v0.1.161`, run 38257991947, 77 eco
releases) delivered **xiom.jolt 0.2.0** (`f08d65ca`; jolt gate closed,
`REL-20261011-0008-bindings` fixed) + **xiom.vma 0.3.0** (`a1cc09e2`) +
**xiom.dxc 0.3.0** (`b4376744`). SDK100 scopes are LIVE (eco 518
production+staging; `REL-20261012-1354-ops`); the **nine remaining SDK100
publishes** -- the eight first-publish names + the sdl3 0.16.1 -> 0.17.0
full-surface bump -- run their port x2 + allowlist append now on the
v0.64.4 pin (vulkan full surface stays 0.5.0, owner bump).
`docs/SDK100-COVERAGE.md` gained the publish-status section. Next: workaround
lift (glfw dispatcher/registry + sdl3 1-arg handler shapes; sdl3 edits wait
for the in-flight bump to wrap).

**UPDATE 2026-10-12 15:00Z (doorbell)**: batch 64 = `eco-v0.1.162` (run
38260596476, 78 releases) published the eight SDK100 first-publishes +
**sdl3 0.17.0** (full surface 1270/1270): spirv-tools/spirv-cross/
spirv-reflect/glslang/slang/sdl2/shaderc 0.1.0 all live (x2 on v0.64.4
before tagging). **`xiom.spirv.headers` HELD** -- the staged scope is the
dash name, the manifest is dotted; correction `REL-20261012-1405-packages`;
it publishes alone once the dotted scope is live. Packages also filed
`REL-20261012-1403-packages`: nested fn types in fn casts warn `unknown
type ... defaulting to i64` on v0.64.4 (sdl3.xi:1599/1628/1640; 6x; suite
green) -- the same warning class we flagged in cb-abi probe4. New relay
asks answered: engine `-1348` (SDK100-0.6.0-first version allocation;
bindings agrees, bump to be cut with the owner session, mini-RHI 0.7.0+
after) and xvector `-1417` (accelerator mirror gate met; reply note -- no
batch surface exists in `xiom.vectors` today; accelerators stay
mirror-only + owner-gated). `docs/SDK100-COVERAGE.md` publish section
updated. v0.64.4 release-check bindings rows filled at the archive
(`b235493`; B-13/14/15/18/1904 verified fixed, B-19 verified,
B-11/B-05/B-07/B-16/B-17/B-21 red, -2230/-2320/-0304 not addressed).
Next: workaround lift (glfw 0.6.0 decision; sdl3 shapes now unblocked --
0.17.0 is live).

**UPDATE 2026-10-12 16:28Z (glfw lift attempt -- BLOCKED)**: started the
workaround lift (item 0a). Deleted the 18 dispatchers + 18 registries and
rewired the setters to direct handoff, then validated live on the
archive: BOTH handoff shapes fail on v0.64.4 --
- `handler as Int` through a flat cast-call: the callback fires but args
  are shifted (C's first arg eaten as a hidden env): key got `win=65
  key=30 sc=1 act=0 mods=<garbage>`, close got `win=0`; bare-name and
  local-of-name handoffs are exact.
- `handler` handed as a nested fn-typed cast-call param: marshals to 0
  (never fires; the `unknown type 'Unit) -> *UInt8'` warning family).
Minimal committed witness: `docs/repro/bindings-pilot/cb-abi/
probe9_castcall_param.xi` (`via_bare_arg=42`, `via_local_arg=42`,
`via_param_arg=0`). Filed **B-22** (`REL-20261012-1630-bindings`, high,
to compiler: fire the env->code-address unwrap at cast-call argument
positions). **glfw reverted to 0.5.0 unchanged** (lift edits + version
bump rolled back; the worktree is clean). The lift re-runs when the
unwrap fix ships; sdl3 shape widening stays open (item 0b). Note for
`-1348-engine`/-1417: unchanged otherwise.

**UPDATE 2026-10-12 17:50Z (graphics sweep -- user directive: Vulkan/DX12/
OpenGL 100%)**: Vulkan = 100% + working + published (0.6.0,
`eco-v0.1.163`; engine GPU tier green on it: probe_rhi_vulkan 8 checks +
demo_vk). OpenGL = **0.4.0 SHIPPED** (`bd402f55`, record `c2a7884f`): full
generated core-profile 4.6 surface -- 656 commands + 1358 enums from
`KhronosGroup/OpenGL-Registry` @ `6af574a1` (PROVENANCE + docs/COVERAGE +
tools/gen_gl.py); live session resolver (`opengl_session_open`);
suite **21/21 x2** (`surface: 656 core commands resolved (unresolved=0)`,
buffer roundtrip, shader compile on GL 4.6.0 NVIDIA 616.92); publish
requested (`REL-20261012-1750-bindings`). Extension commands documented
out of scope for 0.4.0. DX12 = STARTED: `microsoft/DirectX-Headers` cloned
+ pinned (`461ef513`; stable-tag reference `v1.619.5`; `include/directx/
d3d12.h` 1,692,148 B, SHA256 `AFA193D3...`); CLEANUP row added; next batch
= `xiom.dx12` skeleton (COM/vtable core, D3D12CreateDevice/DXGI probe,
SKIP-when-absent) + generator/coverage plan. Engine items answered
(`REL-20261012-1750-bindings-2`: 0.6.0 live + mini-RHI interop direction:
caller surface accepted, picked-physdev accessor added). Mini-RHI renumbers
to **0.7.0+** (packages SESSION; endorsed `-1348-engine`/`-1500-bindings`).
Engine scene tier green on the raw seam (`-1754-engine`: depth + lit
pipeline + indexed draws; mini-RHI no longer a hard gate) -- its ordering
highlights are folded into the batch inputs.

**UPDATE 2026-10-12 19:10Z (relay check + publishes)**: batch 66 =
**`xiom.opengl 0.4.0` PUBLISHED** (`eco-v0.1.164`, run 38291839545; live
sha256 `328674f1` @18:37:31Z; x2 21/21 on v0.64.4; merge tip `bb1ec3b7`;
`REL-20261012-1750-bindings` fixed). Batch 67 = **`xiom.spirv.headers`
0.1.0 PUBLISHED** (ops corrected the scope to the dotted name; live 18:55Z;
`eco-v0.1.165`, sha `a77f364a` @19:01:29Z) -- **SDK100 WAVE COMPLETE**: the
eight new names + sdl3 0.17.0 + vma 0.3.0 + dxc 0.3.0 + jolt 0.2.0 + vulkan
0.6.0 all live; tally 81 eco releases. Ops clobber incident
(`-1852-ops`, high): the toolchain installer/extract wipes non-archive dirs
in its target home (shared defaults included); new rules = lane-local
install dirs + `tools/home-snapshot.ps1` before risky windows, restore from
snapshot after a clobber; any lane that installed today reports. **Bindings
ran no installs/extracts today** and hash-verified the 13:35:22Z slot swap
byte-identical to the official archive -- bindings note filed on
`-1852-ops`; pin evidence stands. Promotion queue (policy sec. 7): vulkan
0.6.0 / sdl3 0.17.0 / opengl 0.4.0 / SDK100 names are candidates as settle
windows pass (sdl3 blocked while `-1403-packages` is open). DX12 wave
started (foundation build next).

**UPDATE 2026-10-12 19:30Z (DX12 foundation shipped)**: `xiom.dx12` 0.1.0
(`b353ed9c`, record `716b375f`): runtime `d3d12.dll` + hand-rolled COM
bridge; ABI pinned from `microsoft/DirectX-Headers` @ `461ef513`
(`IID_ID3D12Device`, vtable slots 7/9; PROVENANCE + SPEC); probe =
D3D12CreateDevice + GetNodeCount + CreateCommandAllocator out-param
roundtrip + Release; suite **5/5 x2** on the RTX 3070 Ti (node_count=1);
SKIP-when-absent / no-adapter; ABI failures never silent. Publish requested
(`REL-20261012-1930-bindings`; NEW name -> ops registry scope needed).
**DX12 status: the foundation is live-working; the 100% surface is the
0.2.0 wave** (generator from the pinned headers: all `ID3D12*` vtables +
free functions + enum/struct metadata, DXGI factory/adapters/swapchain +
WARP fallback, `docs/COVERAGE.md`) -- per the package ROADMAP.

**UPDATE 2026-10-12 19:30Z (DX12 0.2.0 -- full d3d12.h surface)**: same-day
follow-on (`f8992491`, records `c8dd1876`/`be22717d`): `tools/gen_dx12.py`
generated the full `d3d12.h` core surface from the pinned
DirectX-Headers -- 90 interfaces / **355 own-method wrappers** (absolute
vtable slots; `src/iface_01..12.xi` + `src/d3d12_calls.c`), **1162 enum
consts** (`consts_1..5.xi`), **9 free functions** (`functions.xi`); 22
struct-by-value shapes documented as skips in `docs/gen_manifest.json`
(struct-metadata wave). Suite **12/12 x2** on the RTX 3070 Ti: live device
pointer + GetNodeCount, CreateCommandQueue hr=0 + Release refcount 0,
D3D12SerializeRootSignature wrapper hr=0 + typed probe (88-byte blob).
`docs/COVERAGE.md` carries oracle==emitted==witness; publish request
updated to 0.2.0 (`REL-20261012-1930-bindings`). DX12 remaining: DXGI
factory/adapters/WARP/swapchain + struct metadata + `d3d12video.h`
(0.3.0 wave, per the package ROADMAP).

**UPDATE 2026-10-12 19:35Z (DX12 publish confirmed -- 0.3.0 wave STARTED)**:
**`xiom.dx12` 0.1.0 PUBLISHED**: `eco-v0.1.166` (batch 68, run 38297712793
green 3m50s; live sha256 `5ff65bed` @19:28:19Z, signed; ops scope live
eco 519 -> allowlist 520; merge `b8354f82`, record `18cd040e`; validate
533/0; port x2 5/5 on v0.64.4). Relay item `REL-20261012-1930-bindings`
moved to **fixed** by packages (relay tip `01de8fb`); packages note says
"0.2.0 (full ID3D12 surface + DXGI) is the next wave" -- **0.2.0 publish
still pending** (supersede note is on the same item; no new ask needed).
This session starts the **DX12 0.3.0 wave** per the package ROADMAP:
(a) struct metadata + typed shims for the 22 skipped shapes, (b) DXGI
(factory/adapters/WARP/swapchain), (c) `d3d12video.h`, then promotion.
Doorbell re-armed for this session.

**UPDATE 2026-10-12 20:55Z (DX12 0.3.0 wave COMPLETE -- all three slices
green)**: The whole 0.3.0 wave landed in this session, each slice with its
own feat commit + x2 record (all pushed on `bindings`):
- **(a) struct metadata** `fd82f394` (+ record `665804ae`): 19 typed shims
  for the sret/by-value shapes (member-return ABI pinned: RCX=this,
  RDX=hidden out for x64 member returns), the 3 callback-param methods
  bound (358 wrappers, 0 unmapped), clang `sizeof`/`offsetof` oracle at
  `docs/struct_dump.txt`; **18/18 x2**.
- **(b) DXGI** `55c26a8f` (+ record): dxgi.dll surface 43 interfaces / 163
  wrappers / 246 consts / 6 free fns; factory (CreateDXGIFactory2) + 3
  adapters + WARP adapter + `D3D12CreateDevice(WARP)` + hidden-window
  BGRA8/FIFO swapchain (create/GetBuffer/GetDesc1/Present all hr=0);
  **28/28 x2**.
- **(c) video** `a7f988d9` (+ record): d3d12video.h 30 interfaces / 190
  wrappers / 661 consts / 10 typed shims; `ID3D12VideoDevice` QI +
  VIDEO_DECODE command-list chain + generated `Close` hr=0; **31/31 x2**.
- Struct meta now 434 sizes + 1804 offsets = 2238 consts
  (`struct_meta_1..5`); 97 unparsed shapes documented.
- **B-23 FILED** (null literal crosses to C as garbage; workaround
  `xd12_null_ptr()`; repro `docs/repro/bindings-pilot/null-literal/`) and
  **B-24 FILED** (ffi out-slot reads after a C write unreliable --
  `ffi_bad=2 byte_bad=0 of 400`; suite now uses byte-indexed reads only;
  repro `docs/repro/bindings-pilot/ptr-read-stale/`).
- **Relay**: `REL-20261012-2051-bindings` (0.3.0 publish request --
  supersedes the 0.2.0 ask), `-2` (B-23/B-24 to compiler), `-3` (engine
  queue ack: vkCmdPushConstants routed to the Vulkan lane; mini-RHI
  extended tier + imgui noted), `-4` (packages ack: PULSE SQL driver
  accepted into xiom.sqlite 0.4.0). Relay commit `6f27f1b`, validate 378
  items green.
- Next: confirm the 0.3.0 publish in packages SESSION.md (record the eco
  version), then promotion readiness (policy sec. 7: contracts pass / G6
  workaround rows for B-23/B-24 / API review) after the settle window;
  `-1403-packages` could not block anything seen this session.

**UPDATE 2026-10-13 11:55Z (CONTEXT-LIMIT HANDOFF -- this session's
outcomes)**: The main session (19:34Z-20:55Z) completed the **entire DX12
0.3.0 wave** and its publish; four doorbell ticks (00:00/03:00/06:00/09:00Z)
found nothing new after the publish record.
- 0.1.0 publish confirm: `eco-v0.1.166` (relay `-1930` fixed).
- **0.3.0 wave, all three slices, feat + x2 record pushed**: (a) struct
  metadata `fd82f394` -- 19 typed shims (member-sret ABI: RCX=this,
  RDX=hidden out), 3 callback methods bound, 358 wrappers/0 unmapped,
  clang oracle dump; 18/18 x2. (b) DXGI `55c26a8f` -- 43 ifaces/163
  wrappers/246 consts/6 fns + factory/3 adapters/WARP/WARP device/
  BGRA8-FIFO swapchain; 28/28 x2. (c) video `a7f988d9` -- 30 ifaces/190
  wrappers/661 consts/10 typed shims + QI/VIDEO_DECODE chain; 31/31 x2.
  Struct meta 434 sizes + 1804 offsets (2238 consts).
- **B-23** (null literal -> C garbage; `xd12_null_ptr()` workaround) and
  **B-24** (ffi out-slot reads after a C write unreliable; byte-indexed
  reads only, pointer-edged flows via C return values) filed with repros
  under `docs/repro/bindings-pilot/`; MAINTENANCE.md rows added;
  relay `-2051-bindings-2` to compiler.
- **Relay batch** (`6f27f1b`): `-2051-bindings` 0.3.0 publish request ->
  **fixed** (batch 70, `eco-v0.1.168` sha256 `14ce3e67` @21:05:31Z);
  `-3` engine ack (vkCmdPushConstants routed to the owner Vulkan lane;
  mini-RHI tier + imgui noted); `-4` packages ack (PULSE SQL driver
  accepted into xiom.sqlite 0.4.0, queued behind graphics).
- Ledger/paste-prompt commits: `665804ae`/`55c26a8f`-record/`aab68680`/
  `3da3258d` (+ parallel-session doorbell commits). Worktree clean;
  `BINDINGS-SESSION.md` tip on `bindings`.
- **NEXT (paste prompt item 0b)**: promotion readiness per policy sec. 7
  (G1-G7: trap-14 byte-level grep, contracts pass on `dx12.xi`/`dxgi.xi`/
  `video.xi`, G6 rows already added, SPEC error catalog + API review,
  dependents check, `-1403-packages` watch) -- after the settle window;
  0.3.0 went live 21:05Z 2026-10-12.

**UPDATE 2026-10-13 12:10Z (DX12 PROMOTION GATE GREEN -- stable 0.3.1
publish requested)**: ran the policy sec.-7 promotion readiness pass for
xiom.dx12; all gates green -> **`incubating` -> `stable` at 0.3.1** (patch
bump over the published 0.3.0; same verified surface; versions are
immutable). Publish request: `REL-20261013-1207-bindings` (relay
`a9223a1`, validate 380 items green).
- **G1**: fresh `port.ps1 -Package xiom.dx12` x2 on `1a392b91` --
  **35/35 both runs, exit 0**; trap-14 byte-level grep over the package's
  45 `.xi` files = **0 hits** (`Vec<`/`Result<`/`Option<`/`&Vec<`/`<]`/
  `>]`; byte-level, never from Read output).
- **G5 hardening**: +4 deterministic error-path checks (NULL blob handle
  guard -> -1; queue priority=1 rejected; buffer Layout=UNKNOWN rejected;
  `EnumAdapters1(9999)` -> 0) -- suite **31 -> 35**.
- **G4**: contracts inventoried -- **1175 `requires:` / 0 `ensures:`
  across 44 files** (generated wrappers carry `obj != 0`); `xiom-verify
  --check` on dx12.xi/dxgi.xi/video.xi = **0 proven / 0 violated / 33
  unknown** (364 SMT emitter errors) -> solver-unproven, review-only; FFI
  pointer domains documented unasserted with reason (SPEC sec. 7).
- **G2/G3**: SPEC error catalog (sec. 6) + promotion notes (sec. 7);
  README Status -> stable (35/35) + stale struct-meta counts fixed
  (1308 -> 2238; 272/57 -> 434/97 shapes; `struct_meta_1..5`);
  ROADMAP/AUDIT refreshed; API review noted; no placeholders.
- **G6**: B-23/B-24 accepted rows stand (expiry = next compiler pin
  carrying the fixes; neither fix is in v0.64.4); B-22 raw-handler
  callback note stands; no stale rows. **G7**: no dependents (no
  `package.xi` declares `xiom.dx12` in `deps:`).
- **Commits**: prep `1a392b91` (7 files), record + stage flip `1f5473e7`
  (`status.ps1 -Action update ... -Commit 1a392b91 -Stage stable`;
  validate **533/0**); both pushed to origin/bindings.
- `-1403-packages` check: **fixed compiler-side** (m277 `29e35ef8`, same
  commit as the B-22 work) -- no promotion block.
- **NEXT**: watch `REL-20261013-1207-bindings` -> fixed (0.3.1 live
  sha256) in the packages batch/SESSION; record the eco version here.

**UPDATE 2026-10-13 12:25Z (opengl 0.5.0 WGL SURFACE -- shipped + publish
requested)**: the next graphics follow-on (paste item iv, WGL half) landed
while the dx12 0.3.1 promotion sits acked on the packages side.
- **Generated WGL surface** from the SAME pinned OpenGL-Registry clone
  (`6af574a1`), oracle `xml/wgl.xml` SHA256 `6401072F...`: **146 commands
  / 298 enums, 0 skips** -- `wgl_cmds_01..02` + `wgl_consts_1..2` +
  `wgl_names`; generator `tools/gen_wgl.py`; manifest
  `docs/gen_wgl_manifest.json`.  WGL_VERSION_1_0 = 26 commands, 24
  resolvable (the two `wingdi.h` macro aliases have no exported symbol);
  57 extensions -> 119 extension commands.
- **Bridge**: the session resolver gained the `gdi32` fallback (WGL 1.0
  pixel-format exports); new `xgl_session_dc`/`xgl_session_hglrc` ->
  public `opengl_session_dc`/`opengl_session_hglrc`.
- **Suite 21 -> 28, x2 28/28 on `468b73d1`** (feat `468b73d1`, record
  `d43a94e2`): 24/24 resolvable core-1.0 commands resolved, oracle 146
  (core 26), extensions string (809 chars), swap-interval roundtrip
  (1 -> 1, 0 -> 0), `ChoosePixelFormatARB` (1 format pf=9); the GL core
  surface stays 656/656.
- Docs synced (SPEC 0.5.0 + WGL pin in sec. 2, README WGL section, ROADMAP:
  GLES/EGL now next, AUDIT/COVERAGE/PROVENANCE); trap-14 byte-level grep
  clean (23 files, 0 hits).  Publish request
  `REL-20261013-1222-bindings` (relay `76e1908`, validate 381 green);
  origin/bindings tip `d43a94e2`.
- **dx12 promotion**: `REL-20261013-1207-bindings` -> **acked** by
  packages (0.3.1 stable in flight; watch for fixed + the eco version).
- **NEXT**: GLES/EGL via ANGLE (item iv remainder): EGL-Registry
  clone/pin + generated EGL/GLES2/GLES3 surfaces behind
  `libEGL.dll`/`libGLESv2.dll` + `eglGetProcAddress`.

**UPDATE 2026-10-13 12:35Z (NEW PACKAGE xiom.gles 0.1.0 -- GLES/EGL via
ANGLE shipped + publish requested)**: item (iv) completed in full -- the
WGL half shipped as opengl 0.5.0 (12:25Z), the GLES/EGL half is a NEW
package.
- **`xiom.gles` 0.1.0**: generated GLES 2.0->3.2 (**358 commands / 1001
  enums**; OpenGL-Registry pin `6af574a1`, `api="gles2"`) + full EGL
  1.0-1.5 + extensions (**158 commands / 694 enums**; NEW EGL-Registry
  clone pinned **`db3425b8`**, `api/egl.xml` SHA256 `1664DAC6...`;
  `E:\repos\CLEANUP.md` row added); generators `tools/gen_gles.py` /
  `tools/gen_egl.py`; manifests oracle==emitted, **0 skips**.
- Bridge `src/gles_probe.c`: runtime `libEGL.dll`+`libGLESv2.dll`
  (`EGL.dll`+`GLESv2.dll` fallback) + `eglGetProcAddress`; staged probe
  on a **64x64 pbuffer** (no window system dependency); classification
  ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL; session + `gles_session_display`
  + `gles_get_proc`/`gles_egl_proc`.
- **Suite 18/18 x2 on `ee741d77`** (feat; record `b32596c1`) with ANGLE
  2.1 (VS Code payload on PATH; D3D11 backend, RTX 3070 Ti): EGL_VERSION
  1.5, GL_VERSION `OpenGL ES 3.0`, **358/358 + 44/44 core commands
  resolved**, oracle counts 358+158, wrapper-level
  `glGetString`/`eglQueryString`, `GL_MAJOR_VERSION`=3, buffer roundtrip.
- Trap-14 clean (21 files, 0 hits); docs complete (SPEC incl. runtime
  sample + re-pin procedure, README, ROADMAP, AUDIT, COVERAGE,
  PROVENANCE).  Publish request `REL-20261013-1231-bindings` (relay
  `756c2e0`) -- **new name: registry scope/allowlist needed**.
- **NEXT**: confirm the three in-flight publishes (dx12 0.3.1 stable,
  opengl 0.5.0, gles 0.1.0) + record the eco versions; then the lane
  follow-ons: glfw 0.6.0 lift when B-22 ships, sdl3 handler widening,
  and the Phase-2 lists in each package ROADMAP.

**UPDATE 2026-10-13 13:15Z (dx12 0.4.0 COMMAND RECORDING -- shipped +
publish requested; B-25 found)**: after the promotion, the package's
declared next wave (ROADMAP 0.4.0) landed.
- **Command recording**: allocator `Reset`, graphics command list
  create/`Close`, submission (`dx12_execute_one` -> generated
  `ExecuteCommandLists`), fence signal + `dx12_fence_wait` (bridge:
  Win32 auto-reset event + `WaitForSingleObject`).  Suite **35 -> 42,
  x2 42/42 on `fd9f2a4d`** (feat `fd9f2a4d`, record `c6cd5172`): handle
  fidelity, allocator + Reset, list created + Close, fence created,
  queue signal + fence wait (completed=1).
- **B-25 FOUND + recorded (B-20 family)**: `Int as *UInt8` is NOT
  value-preserving on v0.64.4 -- a casted pointer reaches C at a
  different heap-shifted address (`true_ptr == int_param != cast_ptr`);
  D3D12 `CreateCommandList` returned `E_INVALIDARG` with the casted
  handle.  **Fix shipped**: the generated surface types single-star COM
  object params as `Int` (C side `void*`, exact); bridge helpers take
  int64 (`xd12_fence_wait`) and cast in C.  Repro
  `docs/repro/bindings-pilot/ptr-cast/`; B-25 rows in
  `docs/BINDINGS-COMPILER-FINDINGS.md` + `docs/MAINTENANCE.md`; INFO
  relayed to compiler `REL-20261013-1309-bindings` (`6646c8d`).
- Publish request `REL-20261013-1313-bindings` (relay `21eebb4`);
  validate 534/0; trap-14 clean (46 files, 0 hits); docs synced
  (SPEC 0.4.0 + recording pins + B-25; README recording section;
  ROADMAP Phase 4; AUDIT/COVERAGE/PROVENANCE).
- **NEXT**: confirm the gles `eco-v0.1.171` + dx12 0.4.0 publishes; then
  the B-22-gated lifts (glfw 0.6.0 re-attempt + probe9; sdl3 widening).

**UPDATE 2026-10-13 13:20Z (gles 0.1.0 PUBLISHED -- `eco-v0.1.171`)**:
the new ANGLE package is live.
- Scope LIVE 13:02Z (eco 520 both, `f8e284b`; allowlist 520 -> 521 +
  wrap `c106c10d`); **`eco-v0.1.171`** (run 38402059528 green; registry
  sha256 `017b7664...` @13:06:06Z); README/STATUS synced `ed6bc4da`;
  items `-1231-bindings` / `-1302-ops` fixed.  Platform row declared
  (windows-x64; matrix declared=3, backlog 34).
- **Still in flight**: dx12 0.4.0 (`REL-20261013-1313-bindings`, open
  with packages).
- **NEXT**: confirm the dx12 0.4.0 publish; then the B-22-gated lifts.

**UPDATE 2026-10-13 13:30Z (dx12 0.4.0 PUBLISHED -- `eco-v0.1.172`;
ALL PUBLISHES CONFIRMED)**: the command-recording wave is live and the
publish queue is empty.
- dx12 0.4.0: record `93120d3f`, wrap `ef1b8894`, **`eco-v0.1.172`**
  (run 38404632334 green; registry sha256 `38ff6d0b...` @13:25:27Z stage
  stable; README/STATUS synced `da377c75`; item `-1313-bindings`
  **fixed**).  B-25 landed in-surface (Int-typed COM object params).
- Confirmed live this session: dx12 0.3.1 stable (`eco-v0.1.169`),
  opengl 0.5.0 (`eco-v0.1.170`), gles 0.1.0 (`eco-v0.1.171`), dx12 0.4.0
  (`eco-v0.1.172`).  **Nothing in flight.**
- **NEXT**: the B-22-gated lifts when an archive carrying the fix ships
  (fix on compiler main `29e35ef8`); imgui SDL3+Vulkan P6 backends once
  the shared+dev build lands; else relay-driven work.

**UPDATE 2026-10-13 13:40Z (sdl3 0.18.0 -- foreign-written event
readback; B-11 ADDENDUM RETIRED on v0.64.4)**: the deferred readback item
(ROADMAP Phase-2 #3) is done.
- **Re-tested the B-11 addendum reproducer** (`REL-20261011-0304`) on the
  current pin: the SDL-written event buffer reads back EXACTLY
  (`type=32768`; previously `0x33323100`/`0x04040404` on v0.64.3) --
  FIXED for the no-GPU SDL3 shape.  The general B-11 (driver-thread slot
  recycle, `xiom.vma` packed returns) stays open and is NOT claimed.
- Shipped **xiom.sdl3 0.18.0**: suite 59 -> 61 (poll-into-owned-buffer
  user-event readback + full KEY_DOWN readback decode over the
  foreign-written buffer; bounded drains first -- SDL leaves
  `SDL_EVENT_POLL_SENTINEL` 0x7F00 ahead of pushed events); docs synced
  (SPEC "0.18.0 addition" + the 0.3.1 deferral marked RETIRED, ROADMAP
  item 3 DONE, README/AUDIT, MAINTENANCE row).  feat `75d8c339` + fix
  `5a26dee8`, record `37d8856d`; **x2 61/61 on `5a26dee8`**.
- Relay: INFO to compiler "B-11 addendum fixed on v0.64.4 -- close
  `-0304`" + publish request `REL-20261013-1338-bindings-2` (relay
  `7992cbd`; validate 391 items).  Merge note: main carries the published
  0.17.0 full-surface bump -- keep package.xi at 0.18.0.
- **NEXT**: confirm the sdl3 0.18.0 publish; then the B-22-gated lifts.

**UPDATE 2026-10-13 13:50Z (CONTEXT-LIMIT HANDOFF -- session trail)**:
this session's deliverables, all pushed (`origin/bindings` tip
`b85fa038`; relay tip `7992cbd`):
1. **dx12 0.3.1 stable promotion confirmed live** (`eco-v0.1.169`; first
   sec.7 gate promotion; relay `-1207` fixed).
2. **opengl 0.5.0 WGL surface confirmed live** (`eco-v0.1.170`; relay
   `-1222` fixed).
3. **gles 0.1.0 (new package) confirmed live** (`eco-v0.1.171`; scope
   `f8e284b`, allowlist 520 -> 521).
4. **dx12 0.4.0 command recording built + published** (`eco-v0.1.172`);
   **B-25 found/recorded/fixed in-surface** (`Int as *UInt8` not
   value-preserving -- B-20 family; repro
   `docs/repro/bindings-pilot/ptr-cast/`; findings + MAINTENANCE rows;
   INFO `-1309`; COM object params now typed `Int`).
5. **sdl3 0.18.0 shipped, publish requested**: B-11 addendum (`-0304`)
   re-tested **FIXED on v0.64.4** (foreign-written event readback exact;
   61/61 x2; SPEC/ROADMAP/AUDIT/README/MAINTENANCE synced; INFO
   `-1338-bindings` **acked**; request `-1338-bindings-2` open).
6. Ledger + `PACKAGE_STATUS.md` kept current; paste prompt rebuilt below;
   doorbell armed (`0 */3 * * *`).
- **NEXT**: confirm the sdl3 0.18.0 publish (item 0b); then the ordered
  tasks in the paste prompt.

**UPDATE 2026-10-13 14:10Z (sdl3 0.18.0 PUBLISH CONFIRMED -- all
publishes live; compiler m281 fix batch seen)**: item 0b closed.
- **`xiom.sdl3` 0.18.0 PUBLISHED**: `eco-v0.1.173` (run 38408548028
  green; registry sha256 `544c59b8...` @13:55:09Z; wrap `f70f02ae`;
  record `05d5feda`; README/STATUS synced `5000800a`); item
  `REL-20261013-1338-bindings-2` **fixed**.  The 6 known `-1403`
  unknown-type warnings persist on v0.64.4 -- the 0-warning re-check
  rides the next archive (m277).  Packages tally: 89 eco releases
  through `eco-v0.1.173`; nothing open addressed to packages from this
  lane.
- **Relay sweep**: no new bindings-addressed items (newest stays
  `REL-20261012-2032-packages`, acked).  Compiler lane updated OUR items
  in the m281 `77827766` batch (relay commit `438b714`): B-23 + B-24
  **fixed** (`-2051-bindings-2`), B-11 addendum + B-20 family **fixed**
  (`-0304`), `-1548-bindings-2` codegen **fixed** (RTX re-run pending);
  m279 `1a8141fb` had already fixed B-16 + B-17; m280 `e1207485` fixed
  `-2230` + re-probed `-1549-packages-3` green.  **No archive ships the
  batch yet** (v0.64.4 latest; rows appended to
  `release-checks/compiler-compiler-v0.64.4.md`).  Our INFO items
  `-1338-bindings` / `-1309-bindings` stay open on the compiler side
  (their sweep).
- **NEXT-ARCHIVE RE-VERIFY WAVE (prepared; item 0b)**: re-run the
  `docs/repro/bindings-pilot/` bundles -- null-literal (4 paths = 0),
  ptr-read-stale (ffi_bad=0/400), foreign-ptr-read (matching C
  1065353216/1073741824), ptr-slot-write + ptr-arith (exact),
  cb-abi probe9 (42/42/42), sdl3 synthetic-event raw-pointer readback
  variant, vulkan-slot-recycle (RTX host) -- then glfw 0.6.0 lift +
  probe9, sdl3 handler widening, workaround retirement, per-item
  release-check rows + compiler reply.  Worktree clean; doorbell
  re-armed (`0 */3 * * *`).

**UPDATE 2026-10-13 15:00Z (doorbell)**: relay sweep clean -- no new
bindings-addressed items; v0.64.4 still latest on GitHub (no v0.64.5);
packages tally unchanged (89 eco releases through `eco-v0.1.173`).
- Compiler main moved: **m282 `d6690868`** (thread/spawn env-cast fix;
  release-check rows appended; its stdlib half is `-1423-compiler`,
  pending) and an allocator batch that **root-caused B-05
  (alloc-guard-spin)**: `ffi.alloc` routes to the guard arena but
  `ffi.free` hit libc -> heap spin; fix (arena-aware `xiom_guard_free` +
  `ffi.free` route) verified in a scratch tree and handed to stdlib as
  **`REL-20261013-1445-compiler`** (open; acceptance = our
  `alloc-guard-spin` probe under a watchdog; our item `-1548-bindings-5`
  stays acked).  Stdlib-side, NOT in v0.64.4 -- **B-05 added to the
  next-archive re-verify wave (watchdog run)**.

**UPDATE 2026-10-13 15:35Z (xiom.sqlite 0.4.0 -- PULSE SQL DRIVER
SHIPPED; publish requested)**: the queue-behind-graphics item (paste task
vi) landed.
- **`xiom.sqlite` 0.4.0** (feat `4ba13167`, record `a075059a`): NEW
  `xiom.sqlite.driver` module (option A of
  `docs/requirements/pulse-sql-driver.md`): `SqlDsn.parse` (schemes
  `sqlite:`/`sqlite3:`/`sqlite://`; `busy_timeout` default 5000;
  `journal_mode` delete|truncate|persist|memory|wal|off; fail-closed),
  `open_from_dsn` (applies options, reads the effective journal mode
  back), `execute` (rows-affected + last rowid), `query`/`query_one`,
  explicit `transaction_begin/commit/rollback` + `in_transaction`
  (`sqlite3_get_autocommit` wrapper), `caps` + `transactional_ddl`,
  `last_error`; `rows.query_one` + by-name access
  (`SqliteResult.column_index`/`value_by_name`) + `RowOutcome`.
- Suite 16 -> 21; **x2 21/21 on `4ba13167` (v0.64.4)**; validate 534/0;
  trap-14 clean; docs synced (SPEC 3.1 driver section; ROADMAP; README
  driver section; AUDIT; STATUS record `a075059a`).
- **B-26 FOUND + filed with a minimal pure-XIOM repro**: nested enum
  payloads (`Result[Option[T]]`) corrupt struct-with-Vec values
  (`items.len=9` vs 2; flat + single-level controls green; silent
  corruption + AV when used).  Repro
  `docs/repro/bindings-pilot/nested-payload/`; rows added to
  `docs/BINDINGS-COMPILER-FINDINGS.md` + MAINTENANCE; INFO to compiler
  `REL-20261013-1524-bindings-2`.  Shipped workaround: flat `RowOutcome`.
- Relay: publish request `REL-20261013-1524-bindings` (to packages; PULSE
  co-verify per the requirements doc) + INFO `-3` to pulse (frozen
  co-verify surface).  Relay tip `51268ec`; validate 398 items.
- **NEXT**: packages verify x2 + publish 0.4.0 (their queue item 1); on
  live, record the eco version here.  Still parked: v0.64.5+ wave (B-22
  glfw lift, sdl3 widening).

**UPDATE 2026-10-13 15:42Z (sqlite 0.4.0 per-touch retrofits)**: the
per-touch rules closed out on the touched package.
- **`xiom.sqlite` PROVENANCE.md added** (commit `223aa239`): upstream
  SQLite 3.53.4 amalgamation pin (zip SHA256/SHA3-256 + vendored file
  SHA256s), declaration oracle `vendor/sqlite3.h`, source study clone
  `E:\repos\sqlite`, derived-vs-independent statement, declared surface =
  25 C functions bound (24 public wrappers + `sqlite3_db_handle` internal;
  0 skips), static link model (no runtime DLL), public-domain vendor +
  MIT/Apache package license.
- **Platform row declared** (same commit): `platforms: ["windows-x64"]`,
  `runtime_deps: []` (compile class) in STATUS.json -- retrofits
  `xiom.sqlite` off the native declaration backlog.  `status.ps1 -Action
  validate` 534/0 with the new fields; `excluded_reason` refreshed.
- Relay INFO `REL-20261013-1539-bindings` (to packages: merge the newest
  tip; the 0.4.0 publish request `-1524-bindings` is unchanged); relay tip
  `9aff0b9`, validate 399 items.
- Compiler lane triage seen (relay `b2cae28`): B-26 open, B-25 re-test
  pending, B-05 fix ready, sqlite 0.4.0 acknowledged; an m283
  contract-cycle guard is in progress.  The m277-m283 batch still rides
  the next archive (none shipped yet).

**UPDATE 2026-10-13 15:48Z (sqlite 0.4.0 PUBLISHED -- PULSE SQL DRIVER
LIVE; retrofits merged)**: item 0b(1) closed.
- **`xiom.sqlite` 0.4.0 PUBLISHED**: merge `345c05ba` (clean), validate
  534/0, native x2 **21/21**, record `60a0b383` + declared row
  (matrix declared=4, backlog 33), wrap `7786a34c`; **`eco-v0.1.174`**,
  run 38422417970 green; registry sha256 `1e142acc...` @15:31:42Z;
  README/STATUS synced `2269eb76`; item `REL-20261013-1524-bindings`
  fixed.  **PULSE co-verify pending** (`REL-20261013-1540-packages` sent
  by packages); promotion optional at the next touch with the sec.7 gate
  pack.
- **Per-touch retrofits merged** (`5bd95448`, tip `80a06b6b`):
  PROVENANCE.md (upstream pin + 25/25 declared surface) + platform row
  (`platforms: ["windows-x64"]`, `runtime_deps: []`); validator accepts
  explicit-none (`[]`); artifact unchanged (no republish).  My follow-up
  INFO `REL-20261013-1539-bindings` was processed and is closed
  (superseded -- retrofits already merged/published).
- Consumer-path verification (packages, scratch `XIOM_HOME`): today's
  registry releases install cleanly and compile as real consumers
  (sdl3 0.18.0 dependency-only green; gles 0.1.0 bridge recipe live).
- **NEXT**: v0.64.5+ watch (m277-m281 batch: B-22 glfw lift + sdl3
  widening + workaround retirement at the archive); relay-driven
  otherwise.

**UPDATE 2026-10-13 15:58Z (B-26 addendum: shape matrix + reliable AV
witness)**: localized the nested-payload corruption for the compiler.
- New `docs/repro/bindings-pilot/nested-payload/matrix.xi` (commit
  `d6fbfc35`): 7 shapes, 3/3 fresh builds -- D/E/B/C/F/A2 GREEN; shape A
  (`Result[Option[Bag]]` with a leading `Int` tag) **AVs 3/3** (0xC0000005
  at the second payload extraction / guard); `probe.xi` (same no-scalar
  nested shape, different module content) stays RED 4/4 (`items.len=9`)
  -> source/build-sensitive miscompile (B-01 family signature).  README +
  `docs/BINDINGS-COMPILER-FINDINGS.md` B-26 row refreshed.
- Addendum INFO to compiler `REL-20261013-1555-bindings` (refs
  `-1524-bindings-2`; suggests shape A as the primary witness to bisect
  against the m283 / Vec-churn work).  Relay tip `c1469e2`, validate 402
  items.
- **NEXT**: unchanged -- v0.64.5+ watch (m277-m281 batch); B-26 waits on
  the compiler lane.

**UPDATE 2026-10-13 16:05Z (relay delivered-ask sweep -- 8 items acked
-> fixed)**: the bus now reflects actual deliveries; reporters verify.
- `REL-20261011-1153-engine` + `-1159-engine` -- SDL3 present path
  DELIVERED in sdl3 0.8.0 (`3d7f6f3e`: SDL_UpdateTexture +
  SDL_RenderTexture + SDL_SetRenderVSync; demo probe green; 44/44 x2);
  engine window tier GREEN 2026-10-12 (their `-1702`); long since
  published.
- `REL-20261012-2032-packages` -- PULSE SQL driver DELIVERED (sqlite
  0.4.0; LIVE `eco-v0.1.174`; PULSE co-verify pending).
- `REL-20261011-1108-packages` -- glfw fixes DELIVERED (0.5.0,
  `5a213f30`; eco-v0.1.137).
- `REL-20261010-1900-packages` -- stb codec DELIVERED (0.2.0,
  `07f5b9da`; eco-v0.1.139, sha256 `41a205f7`).
- `REL-20261011-1539-engine` + `-1900-packages-2` -- assimp 0.8.0
  file-import group + CONTRACT.md DELIVERED (16/16 native suite;
  `a76bdef4`).
- `REL-20261011-2131-packages` -- upstream-first OWNER POLICY adopted
  (PROVENANCE per touched package; clone-at-pin; declared surface).
- xvector gate pair closed: `-1417` (answered via `-1500-bindings-2`;
  xvector recorded the seam shape) + `-1550` (gate met: vectors live).
- Remaining acked (board state for the next session):
  `-1600/-1841/-1852` (standing info), `-1834-engine-2`/`-2015`/
  `-2012-engine-2`/`-1948` (owner Vulkan lane), `-2012-engine-4` (imgui
  P6 blocked), `-1509/-1702/-1754` (mini-RHI interop info; owner lane).
  Relay tips `7507169` + `0556f51`, validate 402.

**UPDATE 2026-10-14 12:00Z (doorbell -- eco-v0.1.176/177 publish
confirmations recorded)**: two wave publishes landed:
- **`eco-v0.1.176` -- CODEC WAVE A** (run 38468818666 green; live
  21:14-21:17Z 2026-10-13): **jolt 0.3.0** (`3ac3df4e`; 18/18 x2),
  **zstd 0.3.0** (`6288ac84`; 24/24 x2), **meshopt 0.5.0** (`521dab9e`;
  43/43 x2), **ffmpeg 0.3.0** (`24a5c522`; 12/12 x2 present-path via
  Blender 5.1). Merge `f927952b`/`11a58915`, record `89527eac`, wrap
  `7caf0e42`, sync `f48acb15`.
- **`eco-v0.1.177` -- WAVE B FIRST BATCH** (run 38474684402 green; live
  22:00Z): **harfbuzz 0.1.0** (`a768c46a`; 27/27 x2), **basisu 0.1.0**
  (`17226cc9`; 31/31 x2), **spz 0.1.0** (`26ab52a6`; 74/74 x2). Record
  `ef4d32c7`, wrap `d33cc940`, sync `e2c5bca9`; engine relayed
  (`-2211-packages`).
- Tally **93 eco releases** (`eco-v0.1.86`..`177`). Unattended publish
  protocol in force for the 17 wave names (allowlist `f5e4c925`); 14
  remaining names publish as each goes ready; **ffmpeg 0.4.0 HELD**
  pending the generation fix `REL-20261013-2142-packages`.

**UPDATE 2026-10-13 21:45Z (unattended merge/publish wiring -- owner
directive)**:
- **OPS allowlist request filed** `REL-20261013-2143-bindings`: append
  **17 new names** (harfbuzz, basisu, spz, opus, lz4, ktx2, vdb, nis,
  fidelityfx, dlss, xess, nrd, oidn, rpr, rtxdi, rtxgi, openpgl) so
  packages can merge + publish without the owner present; existing-name
  updates (jolt/zstd/meshopt/ffmpeg/ogg/phonon) need no append.
- **Entire-suite manifest filed to packages** `-2143-bindings-2`:
  ready (7 filed requests) + in flight (wave B + upscaler +
  path-tracer), standing rules (newest tip per package; relay to engine
  after each publish per `-2125-bindings`).
- 13 agent sessions in flight; relay tip `4983164`, validate 452 items.

**UPDATE 2026-10-13 21:25Z (path-tracer/lighting wave + merge->engine
relay wiring; owner asks)**:
- **ENGINE RELAY protocol**: filed to packages `REL-20261013-2125-bindings`
  -- after each wave publishes, packages relays availability to the
  engine (eco versions) so the engine's adoption ledger stays current;
  same ask for all future waves (owner directive).
- **Path-tracer GPU open-source coverage launched** (request
  `am-1791926678679-46wing`):
  - `feat/rtxdi-rtxgi` -- xiom.rtxgi (DDGI volumes) + xiom.rtxdi
    (reSTIR DI) [NVIDIA, MIT, vendored C++ + shaders].
  - `feat/rpr-bindings` -- xiom.rpr, AMD Radeon ProRender SDK
    (Apache-2.0; full GPU path tracer C API; tests render a tiny frame).
  - `feat/openpgl-bindings` -- xiom.openpgl, Intel Open Path Guiding
    Library (Apache-2.0; pairs with xiom.oidn).
  - Backlog (not yet launched, on request): LuxCore (Apache-2.0,
    OpenCL GPU), MoonRay (Apache-2.0, production path tracer), Mitsuba 3
    (BSD-3, differentiable, CUDA/OptiX via Dr.Jit -- C++-only API),
    Embree (CPU ray kernels), PBRT-v4 (BSD, research).
- In flight totals: wave-B (opus, lz4, ktx2, vdb, phonon), upscaler
  (fidelityfx, dlss+nis, xess, nrd, oidn), path-tracer (rtxdi+rtxgi,
  rpr, openpgl); integrated/requested: harfbuzz, basisu, ffmpeg-demux,
  spz, jolt, zstd, meshopt, sqlite 0.4.1.  Relay tip `ceac487`,
  validate 446 items.

**UPDATE 2026-10-13 21:15Z (wave-B first results integrated + UPSCALER/
SAMPLER WAVE launched; owner ask "cover DLSS/FSR/XeSS-class")**: yes --
split by license class.
- Integrated (cherry-picked to `bindings`, tip `14acc078`; records
  re-pointed; x2 evidence from the delivery runs -- no re-run per the
  hurry directive; packages re-verifies at publish): **harfbuzz 0.1.0**
  (571/571 declared surface; suite 27/27 x2), **basisu 0.1.0**
  (68 `bt_*` + 13 `bu_*`; 31/31 x2), **ffmpeg 0.4.0** demux (23/23 x2
  present-path: 12 decode + 11 demux; SKIP 3/3 x2 default PATH),
  **spz 0.1.0** (100% declared; 74/74 x2).  Publish requests
  `REL-20261013-2105-bindings` x4 (new-name scope + allowlist notes
  included).  validate 537/0.
- **Upscaler/sampler wave (request `am-1791925519293-w3dsv4`)**:
  - open (full vendored bindings): `feat/fidelityfx-bindings` (AMD
    FidelityFX SDK, MIT: FSR1/2/3 + CAS/SPD + frame-gen surfaces;
    shader blobs vendored as shipped headers), `feat/nrd-bindings`
    (NVIDIA NRD, MIT), `feat/oidn-bindings` (Intel OIDN, Apache-2.0;
    CPU C API 100%; GPU excluded from declared scope).
  - closed runtimes (independent declarations + dynamic loader,
    SKIP-safe, NO SDK binaries vendored -- FFmpeg-style posture):
    `feat/dlss-ngx` (`xiom.dlss` NGX/DLSS-SR/FG/RR + Reflex decls; plus
    open `xiom.nis`), `feat/xess-bindings` (`xiom.xess`, XeSS SDK
    License, `libxess.dll` loader).
- "samplers" read as the sampling/downsample+upscale family (SPD/LPM/
  NIS); texture-sampling libraries (OIIO-class) would be a follow-up if
  that was intended.
- Still in flight from the earlier mega-wave: opus, ktx2, vdb, phonon,
  lz4 (spz's second half).  Relay tip `6e09bad`, validate 439.

**UPDATE 2026-10-13 20:25Z (FULL BUILD-OUT WAVE -- 8 agent sessions; no
more staging)**: owner directive: cover all requested packages now.
- Status answers: **wave A surfaces = 100% delivered** (jolt/zstd/
  meshopt/ffmpeg; x2 each, published-requested); **wave B = prep 100%
  but NOT bound** (8 clones pinned + CLEANUP rows + licenses verified);
  clone protocol per UPSTREAM-FIRST sec. 6 enforced (FFmpeg reference-
  only).  Building wave B to 100% now.
- Sessions (request `am-1791922388300-mcddk4`, worktrees, one branch
  each): `feat/opus-bindings` (xiom.opus 100% + xiom.ogg libogg layer),
  `feat/harfbuzz-bindings`, `feat/spz-lz4` (xiom.spz + xiom.lz4),
  `feat/ktx2-bindings`, `feat/basisu-bindings`, `feat/vdb-reader`
  (xiom.vdb minimal own reader; independent declaration),
  `feat/phonon-full` (steam-audio full surface), `feat/ffmpeg-demux`
  (0.4.0 avformat demux).
- All briefs: header-generated 100% declared surfaces + coverage tables
  (declared/bound/skips=0), v0.64.4 B-20..B-26 discipline, x2 + record.
  On completion THIS session integrates (cherry-pick to `bindings`),
  re-records with platform rows, files publish requests, and produces
  the consolidated **TEST REPORT** (`docs/CODEC-WAVE-REPORT.md`).
- Engine `PACKAGE-ASKS.md` B01-B10 note: B01-B03/B09 = owner-Vulkan/
  XR-decision; B10 filed but blocked (shared+dev imgui build); B04/B05/
  B07/B08 = surface tiers awaiting engine ask-time/new items.
- Parked unchanged: v0.64.5 archive wave (m277-m283); sdl3 widening;
  glfw 0.6.0 lift.

**UPDATE 2026-10-13 20:15Z (CODEC WAVE A COMPLETE -- all 5 agent
deliveries integrated; publish requests filed)**: every agent worktree
landed and merged to `bindings` (tip `8a33a448`).
- **xiom.jolt 0.3.0** (18/18 x2 @ `2ea26693`) -- solver world/body
  surface (engine `-1903`); publish `-2000-bindings`.
- **xiom.zstd 0.3.0** (24/24 x2 @ `55e12c14`) -- ZSTC container framing;
  publish `-2000-bindings-2`.
- **xiom.meshopt 0.5.0** (43/43 x2 @ `4799b7a0`) -- cooked container
  XMC1 + decoder surface; publish `-2005-bindings`.
- **xiom.ffmpeg 0.3.0** (12/12 x2 present-path @ `f9f0e2e1`; GIMP
  FFmpeg 6.1.1 + libdav1d 1.4.1, 3 real AV1 frames 64x48 yuv420p;
  3/3 SKIP x2 on the default PATH) -- AV1 decode surface; publish
  `-2005-bindings-2`.
- **Wave B prep** (`c49ecaa6`) -- 8 clones + CLEANUP rows + prep doc;
  INFO `-2000-bindings-3`.  Engine INFO `-2000-bindings-4`.
- Integration notes: all agent branches were cut from main ->
  cherry-picked onto `bindings`; every record re-pointed to the
  integrated feat sha and **platform rows re-added each time** (5th-8th
  occurrence of the branch-tooling drop; packages' merge on main brings
  the fixed script).  Relay tip `f054e1a`, validate 432 items.
- **Next**: packages publishes wave A (4 packages); record the eco
  versions here; wave B build-outs per packages sequencing; parked:
  v0.64.5 archive wave (m277-m283), sdl3 widening, glfw 0.6.0 lift.

**UPDATE 2026-10-13 20:05Z (wave A integration: jolt 0.3.0 + zstd 0.3.0
+ wave B prep MERGED to `bindings`; meshopt/ffmpeg imminent)**:
- **xiom.jolt 0.3.0** -- caller-usable world/body surface (engine
  `-1903-engine`): world create/destroy (gravity + fixed dt + capacity)
  + body add/remove/count (BOX + SPHERE) + step(w,dt) and step(w,dt,n)
  + state-by-id position/rotation/velocity/awake (owned values);
  suite 4 -> **18/18 x2 on `2ea26693`** (re-run on the integrated tree);
  publish requested `REL-20261013-2000-bindings`.
- **xiom.zstd 0.3.0** -- ZSTC container framing (own format v1; writer/
  builder/reader, `frame_at` random access, seek, robustness matrix);
  suite 8 -> **24/24 x2 on `55e12c14`**; platform row (matrix
  declared=5); publish requested `-2000-bindings-2`.
- **Wave B prep** (`c49ecaa6`): `docs/prep/codec-wave-b.md` -- 8 clones
  pinned + CLEANUP rows (opus/ogg/vorbis/OpenVDB/spz/KTX-Software/
  basis_universal/harfbuzz; steam-audio row refreshed) with per-library
  recommendations; INFO to packages `-2000-bindings-3`.
- Engine INFO `-2000-bindings-4` (jolt surface delivered).
- Integration notes: agent branches were cut from main -> **cherry-picked
  onto `bindings`** (records re-pointed: `daba9b11` jolt, `4cfd1254`
  zstd tip); the branch's older `status.ps1` keeps dropping platform
  rows on record rewrite -- re-added (4th occurrence; main's tooling
  fixes this at merge).
- **In flight**: meshopt 0.5.0 (`b92d7936`; record pending) + ffmpeg
  0.3.0 (`fe56d9fe`; record pending) -- integrate next, then file their
  publish requests.  Relay tip `8d0179b`, validate 430 items.

**UPDATE 2026-10-13 19:35Z (codec/container wave + solver bridge -- AGENT
FAN-OUT)**: owner-prioritized wave accepted and started in 5 isolated
Agent Manager worktrees.
- Accepted: `REL-20261013-1926-packages` (URGENT: codec/container prep
  wave; wave A quick wins + wave B candidates, clone-protocol per
  UPSTREAM-FIRST sec. 6) and `REL-20261013-1903-engine` (solver bridge
  world/body surface).  `REL-20261012-1948-engine` -> fixed (engine-side
  `c8bcd9e`; compiler item `-1819-engine`; the wrapper is correct);
  `-1819-engine-2` acked.  Relay tip `fcb545e`, validate 422 items.
- Agent sessions (worktree, independent; one branch each):
  `feat/jolt-world-body` (jolt 0.3.0: world/body add/remove/step/state),
  `feat/zstd-container` (zstd 0.3.0: indexed multi-frame container +
  random access), `feat/meshopt-cooked` (meshopt 0.5.0: cooked container
  + decode surface), `feat/ffmpeg-av1` (ffmpeg 0.3.0: AV1 decode
  surface, dynamic loader), `prep/codec-wave-b` (clones + CLEANUP rows +
  prep doc; no builds).  Request `am-1791919807965-sw6i5d`.
- Integration plan: each agent delivers feat + x2 + record on its
  branch; THIS session integrates (merge into `bindings`), files the
  per-library relay items to packages, records the eco publishes and
  updates this ledger.  **Do NOT duplicate agent moves on the bus.**
- Still parked: v0.64.5 archive wave (m277-m283 batch); sdl3 widening;
  glfw 0.6.0 lift.

**UPDATE 2026-10-13 18:05Z (sqlite 0.4.1 PUBLISHED -- `eco-v0.1.175`;
consumer blocker now compiler-side)**: doorbell tick; NOTE three
concurrent "bindings" acks landed on the fleet note (multiple sessions) --
coordinate, do not duplicate moves.
- **`xiom.sqlite` 0.4.1 LIVE**: `eco-v0.1.175`, run 38437966256 green,
  sha256 `21c1f673...`, sync `89d6b178` (tally 91 releases through
  `eco-v0.1.175`).  Republish request `-1721-bindings` (packages moves
  it; publication already happened).
- **Deeper consumer blocker is compiler-side**: packages filed
  `REL-20261013-1731-packages` (to compiler, acked) -- even WITH the
  modules list, `xiom build` project consumption fails for xiom.sqlite
  0.4.0/0.4.1 AND sdl3 0.18.0 ("modules list ignored"; xiom.kv passes).
  So the manifest field is the standing convention (and now correct),
  but external project resolution needs the compiler fix.  PULSE's
  artifact re-run waits on it (`-1718-pulse`: driver surface GREEN 24/24
  in-tree on v0.64.3 + v0.64.4; two doc suggestions -- rows_affected =
  LAST statement only; external examples resolve after the fix).
- Fleet note `-1731-packages-2` acked (three times, concurrent
  sessions): 41 published + 26 unpublished lack `modules:` (our scan:
  67 total); policy = retrofit at each real publish + generation
  templates (no scaffolder found in the lane tree).  sqlite done; our
  other packages ride their next publish.
- Compiler m285 `77dfc786` seen; B-05 overlay still red (17:30Z block);
  no v0.64.5 archive yet.  Relay tip `a423b58`, validate 411.

**UPDATE 2026-10-13 17:30Z (PULSE co-verify blocker: sqlite artifact not
consumable -- 0.4.1 modules fix; systemic 67-package scan; B-05 overlay
attempt)**: caught from the relay right after the m283 sweep.
- **PULSE `REL-20261013-1715`** (to packages): the published xiom.sqlite
  0.4.0 artifact has NO `modules:` in package.xi -> `use xiom.sqlite;`
  unresolved for external consumers (v0.64.3 + v0.64.4; control xiom.kv
  has `modules: ["xiom.kv"]`).  PULSE co-verify continues on an in-tree
  copy meanwhile.
- **FIX SHIPPED IN-LANE**: `xiom.sqlite` 0.4.1 (`c239b90e`) -- modules
  list restored (root + ffi/types/rows/query/schema/migration/driver);
  suite x2 21/21 (the port namespace check now reports the 8 modules);
  record `e2beb84e`; platform row restored `70e71a1d` (the branch's
  older `status.ps1` drops the matrix fields on record rewrite -- keep
  re-adding until main's tooling is merged); validate 534/0.  Republish
  requested `REL-20261013-1721-bindings`.
- **SYSTEMIC**: `modules:` is absent from **67 of 534** packages (full
  list in `-1721-bindings-2`) -- all native/binding packages incl.
  dx12/opengl/gles/sdl3/glfw/imgui; rollout ask filed to packages (fleet
  wave vs per-lane; bindings can execute its ~20 on request) + the
  registry-artifact consumer smoke for the publish gate.  PULSE reply
  `-1721-bindings-3`.  Relay tip `d6c9f0e`, validate 411.
- **B-05 overlay attempt (negative evidence, 17:26Z)**: with
  `XIOM_RUNTIME_DIR=E:\xiom-lang\stdlib\runtime` (wave 124, `252ec2d`)
  on v0.64.4 the alloc-guard-spin probe STILL spins (`before` then hang;
  watchdog killed `a.exe`).  The guard_free fix is in the stdlib tree,
  but the compiler-side call-site lowering is not on the installed pin --
  B-05 stays red until v0.64.5+ (wave re-run; keep the watchdog).
- Also seen: compiler m285 `77dfc786` (stdlib `-1549-stdlib-5`
  container-arg erasure); stdlib durable-IO bundle closed; registry 3.0
  pilot gate items (`-1707-registry`/`-2`) are pulse/orbitdb asks, not
  ours.

**UPDATE 2026-10-13 16:15Z (compiler m283 `3ef4d6a9`: B-26 FIXED; B-25
re-probe GREEN -- wave extended)**: the compiler lane closed our two open
findings on main (no archive yet).
- **B-26 FIXED**: root cause was `llvm_type_for` resolving the nested
  payload type to the erased base (`Option[Bag]` -> `%struct.Option`)
  while the concrete monomorph was registered; the boxed arm then loaded
  box bytes as an inline Option.  Fix: resolve `Option[T]`/`Result[T,E]`
  to the registered monomorph.  Witness: probe 2/2/2, failures=0, exit 0;
  CI lock `e2e_m283_nested_payload_read`.  Items: `-1524-bindings-2` ->
  fixed (we verify at the archive); the `-1555-bindings` addendum is
  consumed.  **Wave addition**: re-run nested-payload (probe + matrix),
  then **restore `Result[Option[SqliteRow]]`** in xiom.sqlite and retire
  the flat `RowOutcome`.
- **B-25 re-probe GREEN on m283** (`true_ptr == int_param == cast_ptr`,
  both FIDELITY OK; via the m280/m281 Copy-Out gates + m283):
  `-1309-bindings` -> fixed.  **Wave addition**: re-run `ptr-cast`, then
  revisit the `Int`-typed dx12 COM workaround and close the INFO.
- Compiler also fixed `REL-20261010-1549-packages-8` (contract-cycle
  guard) and recorded a NEW -O2 contract-pruning finding (constant-folded
  `requires` eliminated at O2 -- enforcement follow-up; watch suite
  contract checks under `--opt-level default`).  B-05 stdlib fix still
  ready (`-1445-compiler`).
- Relay tip `fbda2a7`; our board: everything delivered moved to fixed;
  only owner-lane + standing-info items remain acked.

**UPDATE 2026-10-13 12:55Z (DX12 0.3.1 STABLE PROMOTION PUBLISHED --
`eco-v0.1.169`)**: the first policy sec.-7 gate promotion is LIVE.
- Merge `46b45e76` (prep tip `4afec760`; conflicts resolved to theirs +
  published-history README lines restored); validate 533/0; native x2
  **35/35** on v0.64.4 (both runs, RTX 3070 Ti); record `261ba5f8`; wrap
  `1fd17353`; **`eco-v0.1.169`** (run 38397132232 green 12:30:20Z); live
  registry sha256 `355ecc6d...` @12:26:45Z stage **stable**;
  README/STATUS synced (`b2ddfe3c`); bus `REL-20261013-1207-bindings`
  **fixed**; G6 B-23/B-24 accepted rows (expiry = next pin carrying the
  fixes).  First declared platform-matrix row (windows-x64 +
  d3d12/dxgi deps) landed with it.
- **Still in flight**: opengl 0.5.0 (acked) and gles 0.1.0 (acked;
  registry scope step).  Watch the relay + packages batch notes; record
  the eco versions here when they land.
- **NEXT**: opengl/gles publish confirms; then the lane follow-ons
  (glfw lift when B-22 ships; sdl3 widening; Phase-2 items on ask).

**UPDATE 2026-10-13 13:05Z (opengl 0.5.0 PUBLISHED -- `eco-v0.1.170`;
gles 0.1.0 STAGED on the ops scope step)**:
- **opengl 0.5.0 LIVE**: record `d7714a92`, wrap `ee83ee45`,
  **`eco-v0.1.170`** (run 38398625056 green); registry sha256
  `daeb45a7...` @12:40:11Z; README/STATUS synced `7bd22576`; bus
  `-1222-bindings` **fixed**.  Platform row declared (windows-x64).
- **gles 0.1.0 STAGED**: holds for **registry scope**
  (`REL-20261013-1233-packages` open with ops); **publishes as
  `eco-v0.1.171` on confirmation** -- watch that item + the next batch,
  then record the eco + sha256 here.  Platform row declared with it
  (matrix declared=3, backlog 34).
- **NEXT**: confirm gles `eco-v0.1.171`, then the B-22-gated lifts (glfw
  0.6.0 re-attempt + probe9; sdl3 widening).

**UPDATE 2026-10-13 00:05Z (doorbell -- DX12 0.3.0 PUBLISHED)**: packages
**Batch 70: `xiom.dx12` 0.3.0 PUBLISHED** -- `eco-v0.1.168` (run
38308256176; live sha256 `14ce3e67` @21:05:31Z, signed); merge `4970096a`
(tip `aab68680`), bump `3fcb92aa` (0.2.0->0.3.0), wrap `113af041`,
validate 533/0, port x2 31/31 on v0.64.4 (struct sret + oracle sizeof
cross-check, DXGI 3 adapters/WARP/640x480 swapchain, video QI +
VIDEO_DECODE chain); README/STATUS synced by packages; relay item
`REL-20261012-2051-bindings` -> **fixed**. Also noted: **0.2.0 DID publish
first** (`eco-v0.1.167`, sha256 `7cfae765`, batch 69) before the 0.3.0
request landed -- 0.3.0 supersedes cleanly; tally **84 eco releases**.
Two packages-side protocol notes relevant to this lane: (1) **per-touch
PROVENANCE rule tightened** -- upstream-first + clone-repo + 100% coverage
for EVERY package, new AND pre-existing; any touched package gets
`PROVENANCE.md` at touch (audit `scripts/provenance-audit.ps1`, report
`docs/PROVENANCE-COMPLIANCE.md`; 14 compliant / 519 to retrofit) --
xiom.dx12 already carries PROVENANCE.md; (2) engine `-2012-2`/`-2012-4`
and packages `-2032` are now `acked` on their side (my acks dispatched).
Relay tip `f86adc1` (xvector/stdlib waves); no new bindings items. Doorbell
re-armed. Next action: promotion readiness (paste prompt item 0b).

**UPDATE 2026-10-12 21:05Z (doorbell)**: batch 69 = **`xiom.dx12` 0.2.0
PUBLISHED** (`eco-v0.1.167`, run 38301605558; live sha256 `7cfae765`);
0.1.0 (batch 68, `eco-v0.1.166`) remains live too -- the 0.3.0 request
supersedes both. Batch 70: packages **acked the 0.3.0 publish request**
(`REL-20261012-2051-bindings` open->acked 21:00Z; merge + validate + port
x2 + publish next; the name scope is already cleared since 0.1.0 is live).
No new bindings-addressed items beyond the owner-handled sets
(`-2051-bindings-2/-3/-4`); relay validate 378 green. Nothing else
actionable this tick.

**UPDATE 2026-10-13 00:00Z (doorbell)**: batch 70 = **`xiom.dx12` 0.3.0
PUBLISHED** (`eco-v0.1.168`, run 38308256176; live sha256 `14ce3e67`;
merge tip + bump `3fcb92aa` 0.2.0->0.3.0; validate 533/0; port x2 on
v0.64.4). The full DX12 0.3.0 surface -- struct metadata (434 shapes /
2238 size+offset consts), DXGI (43 ifaces / 163 wrappers + factory/
adapters/WARP + BGRA8/FIFO swapchain), video slice (30 ifaces / 190
wrappers) -- is now LIVE (packages fixed `REL-20261012-2051-bindings`,
`b3a2fc4`). No open bindings-addressed relay items at 00:00Z; relay
validate green. Promotion readiness (policy sec. 7) is the next DX12 step
after the settle window; B-23/B-24 remain the compiler-side workarounds to
retire when a pin ships.

**UPDATE 2026-10-15 03:05Z (doorbell -- jolt 0.6.0 PUBLISHED
`eco-v0.1.181`; v0.64.5 tag still held)**: packages confirms the second
E-family publish:
- **jolt 0.6.0 (E3/E6) LIVE**: `eco-v0.1.181` (merge `a857a7f2` tip
  `569202c4`; validate 553/0; native x2 **109/109** both runs; record
  `64a04549`, wrap `a68a8a93`; live sha256 `e5c777f8...` @01:35:43Z;
  run 38666089475 green; guard 540/524/16/0). E3 = motors/limits/state
  + full typed-error matrix; E6 = convex/compound + E1 query integration
  + contact manifold; determinism bit-identical. **Engine relayed**.
  Tally **97 eco releases** (`eco-v0.1.86`..`181`). Item `-0002-bindings`
  fixed (raced by the concurrent session; note appended).
- **E4/E5 launched** = the final E-family session (strict sequential).
- **v0.64.5 tag still HELD** (`-2123` stdlib regression fix in progress);
  on tag -> packages repin -> the lane's RE-VERIFY WAVE (m275-m294).

**UPDATE 2026-10-16 12:10Z (doorbell: eco .186/.187 recorded; brotli in
build; TLS naming forwarded; Android A3/A4 wave starting)**:
- **Published this window**: `xiom.template` 0.2.0 (`.186`); **`xiom.box2d`
  0.4.0 + `xiom.miniaudio` 0.4.0 (A02/A04) in `eco-v0.1.187`** (engine
  wave-5 relayed; tally **103 releases**).  `.188` in flight (allowlist
  543 -> 545).
- **PULSE top-tier builds**: the brotli session is deep in the build
  (`xiom-brotli` staged; ~42k additions).  The TLS session is early --
  the approved **`xiom.ssl`** naming + by-function scope was forwarded
  to it directly (libssl-class loader; mbedTLS explicitly NOT a switch;
  the ops registry scope is already queued with packages, so
  first-publish is uncoupled).
- Android program: wave-2 landed earlier; a new **A3/A4 wave** worktree
  is starting (`android/a3-a4`).  Relay `-1150-packages(-2)` acked
  (naming + token adoptions; box2d/miniaudio live note).  v0.64.6
  (darwin fix) still pending; installed v0.64.5.

**UPDATE 2026-10-16 11:15Z (doorbell: A02/A04 records re-pointed + their
publish requests filed; TLS/brotli sessions launched)**: 
- **A02 box2d 0.4.0 + A04 miniaudio 0.4.0** were landed by the morning
  pass but had **no publish requests** -> filed now
  (`REL-20261016-1112-bindings` box2d 26/26; `-1112-bindings-2`
  miniaudio 27/27) and their records re-pointed to the land commits
  (`d19090cc`/`c11b7ac2`) with platform rows restored; validate 559/0;
  tip `c7d9a968`.
- `-2302-packages` (TLS/brotli duplicate) closed as fixed per the dedupe
  note; canonical = `-2211-packages` + `-2211-packages-2` (both acked).
- **Launched the two PULSE top-tier builds** (`am-1792149214471-230ba6`):
  `feat/tls-binding` (libssl-class multi-soname loader composing with
  xiom.openssl; memory-BIO handshake headliner) + `feat/brotli-binding`
  (google/brotli pinned + vendored; 100% declared surface; quality 0-11
  round trips).  Publish requests follow as they land.
- Eco: **101 releases through `eco-v0.1.185`** (glfw 0.6.0 + sdl3 0.20.0
  lifts live; run green, 0 warnings).  Relay tip `8d4efae`; validate
  flags a pre-existing non-ASCII char in `REL-20261010-1549-registry-3`
  (other lane -- noted, not ours to edit).
- v0.64.6 (darwin fix) not out yet; installed compiler v0.64.5.

**UPDATE 2026-10-16 11:30Z (CONTEXT-LIMIT HANDOFF -- all waves landed;
next session starts on TLS/brotli + the Android remainder)**: this
session hands off on context.  Everything is landed, pushed, and the
worktree is clean.  The NEW paste prompt below (at the
`### NEXT-SESSION PASTE PROMPT` section; the 2026-10-15 11:30Z block is
SUPERSEDED) carries the full state.  One-paragraph state: v0.64.5
pinned + RE-VERIFY WAVE complete (only B-29 open; B-32 acked for the
v0.64.6 fixer wave); glfw 0.6.0 + sdl3 0.20.0 lifts live in
`eco-v0.1.185` (101 releases; `.186` armed); all 8 owner-directed agent
waves landed (6 Android units + box2d 0.4.0 + miniaudio 0.4.0; validate
559/0; gates 8/8 + 26/26 + 27/27); publish requests filed
(`REL-20261016-1125-bindings`); QUEUED HIGH for the next session: PULSE
TLS context binding + real brotli, then Android A3/A4 (serial), A9,
  A11, A12 remainder.  Doorbell: THIS session's cron is removed at
  handoff -- the continuation session re-arms its own (first action).

**UPDATE 2026-10-16 11:50Z (CONTINUATION session -- doorbell re-armed;
relay sweep; WAVE 5 LIVE; next wave in motion)**: this is the fresh
context-limit continuation writing its own records.  State found on
pickup: worktree clean at `9ecd5092`; nothing in flight un-landed.
- Doorbell re-armed (`0 */3 * * *`; next fire 12:00Z) with the
  corrected recipe: sync `E:\xiom-lang\xiom-relays` via fetch +
  `merge --ff-only origin/main` (never git pull there), then `python
  tools/relay.py view --lane bindings` with that workdir.
- Relay sweep: **WAVE 5 PUBLISHED -- `xiom.box2d 0.4.0` +
  `xiom.miniaudio 0.4.0` LIVE in `eco-v0.1.187`** (11:19:59Z /
  11:21:24Z; sha256 `04fe2147...` / `382a16f0...`; run 38892953795
  green; merge `80879547`; record `e32965dd` kept (26/26 + 27/27 @
  `43173d68`); validate 561/0).  `REL-20261016-1112-bindings` + `-2`
  fixed by packages; `REL-20261016-1124-packages` = Wave 5 engine
  relay.  **`eco-v0.1.186` = xiom.template 0.2.0** (packages lane,
  batch 88).  Tally **103 eco releases**.
- No NEW items addressed to bindings (`-2211` x2 stay acked =
  canonical; `-2302` fixed as the duplicate).  New scope intel:
  orbitdb `-1128-orbitdb-2` + xvector `-1129-xvector-2` both want the
  TLS binding too (folded into the TLS scope note).
- NEXT WAVE (owner: continue): **brotli session ACTIVE**
  (`feat/brotli-binding`; upstream google/brotli cloned to
  `E:\repos\brotli` 11:20Z; vendored build in progress -- no commits
  yet).  **TLS session produced no work by 11:40Z** -> naming/scope
  sync filed to packages (`REL-20261016-1142-bindings`; candidate
  name `xiom.ssl`; scope = the -2211 by-function list) + session
  being nudged.  **Android A3/A4 wave (`xiom.android` input +
  sensors) launching now** -- no xiom.android edit in flight
  (`android/w2c-lifecycle` clean + pushed at `0d46b033`).
- Base note: `feat/tls-binding` / `feat/brotli-binding` branches sit
  on the packages-side `main` tip with no unique commits yet -- land
  path-scoped per the standing recipe regardless of base.

**UPDATE 2026-10-16 12:10Z (doorbell 12:00Z processed + wave status)**:
- Two NEW packages replies to the wave processed:
  - `REL-20261016-1150-packages`: **`xiom.ssl` name + by-function
    scope ACCEPTED** (libssl-class confirmed; the "mbedTLS-class"
    mention in the -2211 acceptance history was stray text, NOT a
    switch).  First-publish path: packages queued the ops registry
    scope for the new name today; the request goes in after the build
    + suite.  Acked with the full build status (oracle pinned,
    loader probes green, ALPN-select limitation noted).
  - `REL-20261016-1150-packages-2`: **android platform tokens were
    already adopted 10-15** (`5aa4e63e` + `0d46b033`) -- the -2210
    wait is cleared; box2d/miniaudio live in `.187` confirmed;
    android first-publish = five NEW names need the ops scope
    (packages queued it) while `xiom.android` is the existing-name
    path.  Acked.
- `REL-20261016-1205-bindings` (lane-filed validate-red on the
  long-running registry non-ASCII item) -> registry repaired +
  closed it duplicate; `relay.py validate` is GREEN board-wide (592
  items) for the first time in three days.  Acks/confirms were
  committed in the shared relay clone (`21fd1cc`; tree clean).
- WAVE STATUS: **brotli** session busy (package growing; ~+42k
  additions).  **TLS** session busy -- recon green: oracle
  `E:\repos\openssl` @ `openssl-3.2.4` = `8ac42712...`; loader
  probes green on v0.64.5 (45-field struct, null cast, dl_open
  against the real libssl); building `xiom.ssl` (server+client ctx,
  cert/key/chain PEM/DER, step handshake + WANT_* pump, ALPN
  set/read, verify modes, clean shutdown, typed errors; documented
  limitation: server-side ALPN SELECT needs a C callback).
- **A3/A4**: the first Agent Manager request never attached a session
  (worktree `wt-1792151643502-3`/`android-a3-a4` sat sessionless) ->
  relaunch requested `am-1792152280034-m35wty` (branch
  `android/input-sensors`, FULL brief as the initial prompt); the
  stale `android/a3-a4` worktree gets removed once its session is
  confirmed dead.

**UPDATE 2026-10-16 12:22Z (WAVE LANDED: brotli + ssl IN; publish
requests filed; validate 561/0)**: both PULSE top-tier builds landed
and passed the integration gates on the landed state:
- **`xiom.brotli 0.1.0` LANDED** (`7e9892bc`, 137 files; record
  `a040cfd4`): real RFC 7932 brotli, vendored google/brotli v1.2.0
  (MIT), 16/16 declared surface (one-shot + streaming enc/dec,
  quality 0-11 + lgwin/mode typed params, corrupt/truncated typed
  errors, HTTP `Content-Encoding: br` helpers + body round trip).
  Integration **26/26 x2** on the landed state (upstream vectors
  decode byte-identically; q11 ratio 16384 -> 75).  Branch
  `feat/brotli-binding` pushed.
- **`xiom.ssl 0.1.0` LANDED** (`a65f34cc`, 14 files; record
  `d22e7774`): libssl-class multi-soname loader (xiom.openssl
  pattern; NOTHING vendored; SKIP-safe).  Live leg **23/23**
  (OpenSSL 3.2.4: loopback TLSv1.3 + TLS_AES_256_GCM_SHA384,
  encrypted ping/pong, ALPN set + negotiated read, verify trusted ->
  0 / untrusted -> typed with verify_result 18, clean shutdown,
  memory-BIO-only handshake 4 pump rounds) + SKIP leg **4/4**;
  documented limitation: server ALPN SELECT needs a C callback (no
  FFI callback bridging yet).  Branch `feat/tls-binding` pushed.
- **Publish requests filed**: `REL-20261016-1220-bindings` (brotli)
  + `-1220-bindings-2` (ssl) -- both NEW registry names; ops scopes
  queued by packages (their -1150 note).  `status.ps1 -Action
  validate` = **561/0**.
- **A3/A4 session ATTACHED late** (`ses_ebb64cce2ffe5Qicm603FfQQt6`,
  worktree `android-input-sensors`, branch `android/input-sensors`):
  busy; rebased onto origin/bindings; compiling.  The stale
  `android/a3-a4` worktree gets removed once its never-started
  session is confirmed dead.

**UPDATE 2026-10-16 13:10Z (batch-188 assembly visible; A3/A4 branch
green + pushed; awaiting session idle to land)**:
- A3/A4 branch state (pushed to origin): **`xiom.android 0.4.0`**
  export set **117 -> 209** (input.h 60 + sensor.h 32; generated const
  tables 538 values); record `02db287f` = **suite x2 14/14 on v0.64.5**
  (SKIP leg; run_by android-input-sensors @ c647aa86); docs regen
  `070d9082`; on-device app-probe re-captured `a16513b5` (live
  dispatcher block, probe window entry).  Session still active
  (detached-busy on an extra pass) -> LAND when idle (path-scoped;
  port x2; record re-point; validate; push).
- Packages batch plan (relay): `-1302-packages` x2 = ops scope asks
  for **xiom.brotli 0.1.0** (stacks with xiom.ssl into ONE batch,
  both held green); `-1150-packages-7` = ops scope queue:
  transport/otel hold `eco-v0.1.188`; android family (5 new names) +
  xiom.ssl queued.  `-1304-packages` (http 0.1.7 rider) = info.
- Sibling session filed the **android family first-publish request**
  (`REL-20261016-1305-bindings`: xiom.android 0.3.0 + five new names
  0.1.0, scopes staged).  NOTE: our A3/A4 land is **0.4.0** -- once
  landed, file the supersede note so packages publishes 0.4.0.

**UPDATE 2026-10-16 13:25Z (A3/A4 LANDED; family 0.4.0 update filed;
A9/A11/A12 wave launched)**:
- **A3/A4 LANDED**: land `f8ba590a` (23 files; xiom.android 0.4.0;
  export set 117 -> 209 = input.h 60 + sensor.h 32; generated const
  tables 538 values; docs/repro input + app probes + recorded
  app-probe output), record re-pointed `d0d85113`; integration
  **x2 14/14** on v0.64.5 (SKIP leg; namespace 5 modules OK);
  validate **561/0**; branch `android/input-sensors` pushed (session
  idle after final record re-point `34064e2c`).
- Family first-publish update filed: `REL-20261016-1322-bindings` --
  publish **xiom.android 0.4.0** (supersedes 0.3.0) in the -1305
  family batch; the five new names unchanged.
- **NEXT WAVE LAUNCHED** (`am-1792157066997-6uc3rf`): A9 gl leg
  (`android/a9-gl-leg`; generator-aware xiom.gles android pass),
  A11 JNI seam (`android/a11-jni`; new `xiom.jni`), A12 system-misc
  remainder (`android/a12-sys`; binder_ndk + NNAPI + z + icu subset
  in xiom.android-sys 0.2.0).
- 13:35Z follow-up: A9 + A11 sessions attached
  (`ses_ebb1a2334ffe...` / `ses_ebb165967ffe...`); A12's worktree
  never materialized -> relaunch requested
  (`am-1792157647638-q9o9o7`).  **Packages acked brotli + ssl publish
  execution** (`REL-20261016-1220-bindings` + `-2`): ssl scope LIVE at
  eco-release 550; brotli scope check in the same pass; both stacked
  into ONE eco batch (pipeline: merge tip -> validate -> x2 -> wrap ->
  publish -> PULSE relay).
- 13:47Z update: **A9 + A11 + A12 all WORKING** (A9
  `android/a9-gl-leg` active mid-rebase ~+6.4k; A11 `android/a11-jni`
  ~+5.7k; A12 relaunch `android/a12-sys` ~+5.7k ahead 9); the original
  A12 session materialized LATE -> stopped as duplicate (worktree
  removed).  Engine ask `REL-20261016-1341-engine-3` (vulkan campaign
  checklist) **ANSWERED**: raw surface 100% at 0.6.0
  (compute/bindless/mesh-shader/multi-draw-indirect/timestamps all
  present at the vk* level; per-area evidence in
  `REL-20261016-1347-bindings`); the engine-facing wrapper tier folds
  into the OWNER session's mini-RHI extended wave per the lane split
  (item acked).
- 14:12Z update: **`xiom.jni 0.1.0` LANDED** (A11 jni-seam; land
  `ea8dcc0e` + record `0a5e1aaf`; 97 helpers over the JNIEnv table +
  bitmap cluster via libjnigraphics; 9-export loader set;
  integration **x2 90/90**; on-device shell + app_process probes
  PASS; validate **562/0**; publish request
  `REL-20261016-1410-bindings`).  Eco: **batch 90 = `eco-v0.1.188` =
  transport + otel** (packages lane, own packages).  A9 + A12 still
  working (nothing pushed yet).
- 14:30Z: ops scoped **brotli + xiom.jni LIVE (eco-release 552)**;
  packages executing both the brotli+ssl batch and the android-family
  batch (`jni scope ask filed`; family batch continues with the
  sibling session).  A9 + A12 worktrees both active mid-op at 14:28Z.

**UPDATE 2026-10-16 15:10Z (doorbell 15:00Z + A9 LANDED)**:
- **`xiom.gles 0.2.0` LANDED** (A9 graphics-gl android leg; land
  `87763cbf` + record `7db2691a`): loader candidate pairs emitted by
  both generators (Windows ANGLE DLLs + android system sonames),
  generated NDK r27b delta (494 extension wrappers + 1225 constants;
  ES1 + 279 guard/token macros documented exclusions), EGL android
  family 0-delta.  Integration **x2 20/20** (ANGLE live: 358/358 ES +
  44/44 EGL resolved; 236/494 delta ext-conditional) + on-device
  SwiftShader PASS (ES2 context + glClear err=0).  validate **562/0**.
  Publish request `REL-20261016-1510-bindings` (existing name) --
  relay commit pending an index.lock window.
- `docs/ANDROID-SDK100.md` status refreshed (A9 row -> DONE; A3/A4/A11
  landings recorded; G3 scopes 550/552).
- Relay sweep: no new items addressed to bindings; info-only noise
  (-1429 pulse-extraction claim, -1446 codenames convention, -1304
  http rider).  Compiler: stdlib pin ask for the v0.64.6 cut.
- **A12** (`xiom.android-sys` 0.2.0) still working (no push yet).

**UPDATE 2026-10-16 15:45Z (A12 LANDED -- EVERY ANDROID SLICE IN)**:
- **`xiom.android-sys 0.2.0` LANDED** (A12 remainder; land `62201d7e`
  + record `04f4ee1a`): binder_ndk + NNAPI + zlib + icu-subset heads
  as per-lib runtime-load units with own SKIP classifications;
  integration **x2 16/16** on v0.64.5; on-device five-bridge probe
  PASS (per-lib export scans + functional smokes, recorded under
  docs/repro); validate **562/0**.  Publish request
  `REL-20261016-1545-bindings` (existing name).
- **The Android SDK100 program is landed lane-side**: A1-A9, A11,
  A12 all in-package (A10 = owner lane).  `docs/ANDROID-SDK100.md`
  status rows all current.
- Open now: publishes in flight at packages (brotli+ssl batch,
  android family -1305/-1322, gles -1510 acked, jni -1410, sys
  -1545) and the compiler v0.64.6 watch (B-32 fixer wave; m337/m338
  already in local main per the relay).
- 16:02Z: **stdlib-v0.64.6 TAGGED** (`b81430b` = e72288f + waves
  151-154; relay `b5b7293`) -- the compiler v0.64.6 archive is next;
  `gh release list` still shows v0.64.5 as latest.  On release: the
  B-32 re-verify wave is the lane action (no unilateral repin).
  Housekeeping: stale `android/a3-a4` branch deleted (workless, tip
  was old main); its deregistered worktree dir is file-locked --
  retry deletion later.

**UPDATE 2026-10-16 16:45Z (PUBLISHES LANDING -- brotli + ssl + gles
LIVE)**:
- **`xiom.brotli 0.1.0` LIVE in `eco-v0.1.189`** (sha256 `f37f3a39...`
  @15:09:19Z; batch 91): merge `5a22868a`; native x2 26/26 both runs
  (upstream vectors byte-identical); allowlist 545->547 (brotli
  eco-552 scope); run 38921431252 green; PULSE relayed -- top-tier
  item 4 closed.  The same tag carried the `xiom.http 0.1.7` rider.
- **`xiom.ssl 0.1.0` LIVE in `eco-v0.1.189`** (sha256 `ba42cf2b...`
  @15:11:44Z) -- **THE TLS HEADLINE GAP IS CLOSED** (PULSE item 2);
  native x2: live 23/23 (OpenSSL 3.2.4 via Git mingw64 on PATH; TLS
  1.3 over fd + memory BIOs, PEM/DER cert-chain incl. buffers, verify
  accept/reject, close_notify, ALPN wire) + SKIP 4/4 x2.
- **`xiom.gles 0.2.0` LIVE in `eco-v0.1.190`** (sha256 `40328c2a...`
  @15:33:47Z; batch 92): existing-name path (no scope delta); native
  x2 20/20 both runs; on-device SwiftShader PASS stands.
- Still open at packages: android family (`-1305`/`-1322`; continues
  with the sibling), `xiom.jni` (`-1410` acked), `xiom.android-sys`
  (`-1545` open).  Eco through `eco-v0.1.190`.
- 17:20Z: **family batch ACKED + executing** -- the combined
  publish = `xiom.android 0.4.0` (per -1322; 0.3.0 SKIPPED) +
  aaudio/mediandk/camera2ndk/opensl 0.1.0 + `xiom.android-sys 0.2.0`
  + `xiom.jni 0.1.0` (SEVEN units; all seven names being appended to
  the repo allowlist in this batch; scopes live 550/552); x2 sweep ->
  wrap -> publish.  Also: `xiom.pulse` scoped LIVE (eco-release 553).
  **v0.64.6 archive IMMINENT** (packages will coordinate ordering if
  it lands before the family batch wraps).  On release: B-32
  re-verify wave (nested `Result[Option]` restore probes) is the
  prepared lane action; no unilateral repin.  Probe paths ready:
  `docs/repro/bindings-pilot/nested-payload/` (probe.xi + matrix.xi)
  + `docs/repro/bindings-pilot/b32-sqlite-nested/`; on green, the
  xiom.sqlite nested restore (flat `RowOutcome` stays until then).

**UPDATE 2026-10-16 18:30Z (FAMILY 7/8 LIVE in eco-v0.1.192; android
0.4.0 on scope re-grant; v0.64.6 cut gate GREEN)**:
- Batch 94 = **`eco-v0.1.192`** (run 38944226590): **aaudio 0.1.0**
  (sha `ab97fe2e`) + **android-sys 0.2.0** (`9d611a16`) +
  **camera2ndk 0.1.0** (`0b7a0ba0`) + **mediandk 0.1.0** (`a18abb38`)
  + **opensl 0.1.0** (`22cee06c`) + **jni 0.1.0** (`61a0ed6f`) + the
  bonus **PULSE Beacon `xiom.pulse 0.1.0`** (`53fcc56e`).
- **`xiom.android 0.4.0` BLOCKED (1/8)**: registry `scope_denied` --
  the recreated registry's eco token never covered this legacy name
  (the 550 grant covered the five NEW names only); ops re-grant asked
  by packages; on LIVE they push the single-package tag
  `xiom-android/v0.4.0`.  No bindings action; item
  `REL-20261016-1810-packages-2` acked.
- Compiler: **cut gate GREEN on m334-m345** (full battery) -- v0.64.6
  release imminent; XVC-C-18 recon launched.  Eco through `.192`;
  PULSE already consumer-verified ssl+brotli x2 both platforms.
- 19:45Z: **family 8/8 CONFIRMED COMPLETE** -- `xiom.android 0.4.0`
  published 19:26Z via the single-package tag `xiom-android/v0.4.0`
  (run 38954866471; sha256 `2b9cf462...`; re-grant live eco-554).
  Closing `-1305`/`-1322` from our side is TOOL-BLOCKED (bindings
  cannot move `to=packages` items) -> closure request filed
  `REL-20261016-1943-bindings`.  R2 wave (serial/onnx/v4l/gps/epos/
  ros2; `am-1792178818502-r7skkf`) was launched by the sibling
  session per the owner go -- this lane watches + lands.  m346
  (XVC-C-18) integrated into the held v0.64.6 cut candidate (battery
  rerunning).

**UPDATE 2026-10-16 20:35Z (R2 LANDINGS: serial 0.1.0 + ros2 0.2.0 IN;
B-33 filed to compiler)**:
- **`xiom.serial 0.1.0` LANDED** (land `a9a2c8e3`; record head
  `4def4b3b`): Win32 comm API loader (kernel32+advapi32, 14 entry
  points) + DCB/timeout codecs (360/360 matrix, 180/180 invalid
  rejected) + 9 typed error kinds; integration **x2 52/52**; publish
  request `REL-20261016-2031-bindings` (NEW name; ops scope needed).
- **`xiom.ros2 0.2.0` LANDED** (land `a0184d9c`): rcl C surface behind
  the multi-soname loader (init/context/node/pub/sub/clock/timers/
  wait-sets, callback-free spin; QoS/node-opts builders; 24 rcl_ret
  codes; ABI host gate); integration **x2 82/82**; publish request
  `-2031-bindings-2` (existing name).  Landed with the B-33 findings
  entry + the `ros2-abi` probe bundle.
- **B-33 relayed to the compiler lane** (`-2031-bindings-3`):
  record-by-value fn-cast call = SILENT exit-0 (confinement trap
  non-recovery; IR emission well-formed -> bisect = confined-call
  lowering + fault-trampoline recovery for aggregates).  Workaround
  (pointer-pretend) shipped in ros2 0.2.0; probes
  `docs/repro/bindings-pilot/ros2-abi/`.
- validate **563/0** (serial + ros2 joined); pushed after rebase
  (records re-pointed to post-rebase shas).  Acks: `-1941-packages`
  (openblas/arrow to packages; NO conflicts) + `-1951-packages`
  (pandas leg-2 triage recorded).  R2 remaining: onnx/v4l/gps/epos
  in flight; a3-a4 stale dir finally removed.

**UPDATE 2026-10-16 21:15Z (v0.64.6 VERIFIED on the scratch slot; v4l
LANDED; B-32 restore session launched)**:
- **v0.64.6 scratch verification** (windows-x64 asset; SHA256SUMS OK;
  run with `XIOM_COMPILER` = scratch slot -- the repo pin STAYS
  v0.64.5 until the owner repins):
  - **B-26/B-32 core: GREEN** -- `nested-payload/probe.xi`
    failures=0; `matrix.xi` ALL shapes green (incl. the previously
    reliable-red A/A2: tag=2, items.len=2).  The m346 generic
    field-chain fix lands as advertised.
  - **B-30 owned-slot-cast: GREEN** (probe.xi + probe_fixed.xi both
    compile+run, ch=2).
  - **B-31 const-alias-cycle: still FIXED** (emit-ir exit 0).
  - **B-29 bigint-bitops: STILL RED** (shift20=2987 vs 2989;
    boundary-arithmetic workaround stays).
  - B-33: not re-run (needs the clang probe.dll; compiler queued it
    as m351 for v0.64.7).
  - **REPIN DECISION = owner/session** (`COMPILER_VERSION` on
    origin/bindings still v0.64.5).  Scratch slot path:
    `%TEMP%\kilo\xiom0646\slot`.
- **`xiom.v4l 0.1.0` LANDED** (agent chain rebased onto bindings:
    `bbd8cfaa` prep -> `18eaf107` feat -> `ce9f9f0c` docs ->
    `ddc97fe5` record; record re-pointed to the tested tree
    `18eaf107` in `962c5bb1` -- fixes the db08d746 slip): V4L2 UAPI
    bridge, 2079 consts + 1028 layout facts + 29 macro mirrors; x2
    14/14 (blanket SKIP off-Linux); validate **564/0**; publish
    request `REL-20261016-2115-bindings` (NEW name).
- **B-32 restore session launched** (`am-1792185444615-u3hosb`;
    branch `feat/sqlite-nested-restore`): in-situ
    `Result[Option[SqliteRow]]` restore attempt on the .6 scratch
    slot (patch + suite; clean restore -> 0.5.0 if green; evidence
    either way into the b32 README).
- Publishes in queue at packages: serial `-2031-bindings`, ros2
    `-2031-bindings-2`, v4l `-2115-bindings`; B-33 acked by compiler
    (m351).  R2 remaining: onnx + gps (record phase) + epos
    (relaunched session).

**UPDATE 2026-10-16 21:45Z (R2: onnx + gps LANDED; validate 565/0)**:
- **`xiom.onnx 0.1.0` (full C-API coverage) LANDED** (land
  `7485c6d5` + record `508bb5e9` + namespace registration): 95-slot
  runtime loader + session/tensor/value/allocator/run-options +
  high-level `load_model`/`onnx_run`; integration **x2 56/56 with a
  LIVE ORT leg** (real `A+B -> C` inference through Run/RunOptions +
  io-binding; onnxruntime.dll 1.17.1 on the reset box / 1.31.0 in the
  agent's run); publish `REL-20261016-2144-bindings` (existing name;
  bump to 0.2.0 if the registry already holds the stub line).
- **`xiom.gps 0.1.0` LANDED** (land `d16b2b61` + record `f2d2061f`):
  pure-XIOM gpsd JSON client + NMEA 0183 parsers (GGA/RMC/GSA/GSV;
  recorded upstream fixtures byte-pinned); integration **x2 28/28**
  (live client SKIPs typed without gpsd); publish
  `-2144-bindings-2` (NEW name; ops scope).
- validate **565/0**.  **R2 state: serial/ros2/v4l/onnx/gps ALL
  LANDED**; epos in flight (branch advanced `6a9f3afe`); B-32 restore
  session active (`feat/sqlite-nested-restore`).
- Publishes in queue: serial, ros2, v4l, onnx, gps (5 items) + the
    earlier family closes.

**UPDATE 2026-10-16 22:15Z (R2 COMPLETE -- epos LANDED; all six in;
validate 566/0)**:
- **`xiom.epos 0.1.0` LANDED** (land `85b0d9ee` + record `0944ff81`):
  closed-SDK loader -- 179/179 declared `VCS_*` wrapper shapes across
  system/config/operate/motion/io clusters, typed
  EPOS_LOAD_ABSENT/ABI classifications, acquisition contract in
  PROVENANCE (nothing vendored).  Integration **x2 29/29** (SKIP path
  on this box; suite runs ~127s -- needs `-TimeoutSec 300`).
  Publish **gated by the package's own terms** (Linux libEposCmd.so
  lane + a hardware bring-up run) -- NO request filed yet.
- **R2 WAVE FULLY LANDED**: serial (52/52), ros2 (82/82), v4l (14/14),
  onnx (56/56 live ORT), gps (28/28), epos (29/29) -- validate
  **566/0**.
- Engine ask folded: `REL-20261016-2139-packages-2` (miniaudio
  long-lived handle surface) ACKED -> next miniaudio wave.
- Publishes: serial/ros2/v4l ACKED by packages; onnx/gps in queue.
  B-32 restore session NOT yet producing commits (watching; relaunch
  if it stayed sessionless).  Repin: still v0.64.5 (owner).

**UPDATE 2026-10-16 22:45Z (batch 95 LIVE; v0.64.6 slot active;
sibling's 4-agent wave; B-32 relaunch + nudge)**:
- **`eco-v0.1.193` LIVE** (batch 95; run 38973537205 green; all
  registry live-verified): `xiom.serial 0.1.0` (`fdd4dde3`),
  `xiom.ros2 0.2.0` (`f510bb42`), `xiom.v4l 0.1.0` (`0e3d5390`),
  `xiom.onnx 0.1.0` (`1c1c599b`; first registry entry carries the
  full landed surface -- no 0.2.0 bump needed).  Items `-2031` x2 +
  `-2115` + `-2144` all fixed.
- **`xiom.gps`**: landed + verified in-tree by packages (merge
  `84bdc431`; x2 28/28 **on v0.64.6**; record `329aadfd`); NOT
  published (no allowlist/scope yet); our request `-2144-bindings-2`
  open with them -- publish rides the next batch after the scope ask.
- **v0.64.6 repin wave landed machine-wide** (packages repin
  `b0ba2a6b`; merge `84bdc431`; wrap `94ebce30`): the machine slot
  `%LOCALAPPDATA%\xiom.new\bin\xiom.exe` now IS **v0.64.6**
  (verified); packages re-ran our suites on .6 -- **no
  regressions** (52/52, 82/82, 14/14, 28/28).  NOTE: the
  bindings-branch `COMPILER_VERSION` file still reads v0.64.5 --
  the branch-side repin bump is PENDING (owner/sibling step; not
  done unilaterally here).
- v4l category warn fixed + family sweep (`8c9493c1`: media+systems
  / systems; kv/lz4/raylib/slang queued) -- sibling.
- **Sibling wave**: 4 more agents launched (`8baf0dc7`): miniaudio
  handle, torch+libtorch, tensorflow, blas fold (all visible busy
  at 22:39Z).
- **B-32**: the original restore session stalled (idle 75 min, zero
  work) -> relaunch requested (`am-1792190420316-3wr9px`, branch
  `feat/sqlite-nested-restore-2`) AND the stalled session NUDGED
  with the slot update (slot = .6 -> no scratch download needed).
  Whichever branch lands green first takes the restore; the other
  gets stopped.

**UPDATE 2026-10-16 23:05Z (B-32 re-attempt on v0.64.6: STILL RED
in-situ; filed to compiler; restore stays parked)**:
- The (nudged) restore session ran the briefed flow on the **v0.64.6
  slot** (exe sha256 `EB1F46C2ACBA5B95D46124FA7BB52426508BE5B81256E3ED1819CBFDA6979150`):
  **17/17 PASS then t18 `cols.len=140702801265104` -> 0xC0000005** --
  identical to the documented v0.64.5 signature.  Controls GREEN on
  the SAME slot (nested-payload probe + matrix all shapes) =>
  **m346 fixed the ISOLATED shapes only; the in-situ unit still
  miscompiles**.  Restore stays **PARKED** (flat `RowOutcome` 0.4.1;
  package untouched).
- Evidence: `%TEMP%\kilo\b32\` (attempt-1.log, tested-tree.diff,
  probe-1.log, matrix-1.log, slot-exe.sha256).  Docs-only README
  result section approved -> landing via the restore branch.
- **Compiler relay filed: `REL-20261016-2303-bindings`** -- fold the
  residual into the v0.64.7 fixer wave as an extension of the
  m346/XVC-C-18 class; re-verify = the same two commands + README.
- Bundle caveats for the next attempt: `restore-0.5.0-attempt.patch`
  is UTF-16LE (convert to UTF-8 before `git apply`); its README hunk
  predates the 0.4.1 modules-list paragraph (manual re-apply); the
  other 7 files apply cleanly.
- Duplicate restore session (`feat/sqlite-nested-restore-2`) to be
  stopped at the next sweep (Agent Manager timeouts this pass).
- 23:12Z cleanup: the restore-2 worktree turned out SESSIONLESS (the
  attach flake again) -> deregistered + its branch deleted; the dir
  is file-locked (sweep later, same as a3-a4).  NO duplicate session
  existed.  The README docs-commit GO-AHEAD was delivered to the
  evidence session (`ses_eb96482b9ffe...`) on the re-send.
- 23:40Z close-out: **B-32 evidence LANDED** (`3623f895` on the
  branch -> path-scoped `186555e1` on bindings; docs-only; package
  untouched) and the compiler **ACKED the residual as `m358`**
  (next fixer wave; stdlib cut note: pin PR -> `8d95815` per 1559;
  i128 division AV -> `m360`).  Sibling wins: **`xiom.miniaudio 0.5.0`
  handle surface LANDED** (x2 44/44 on v0.64.6; publish request +
  merge cue `a8902f4`) -- the engine's long-lived-handle ask is
  DELIVERED; compiler wave m347-m349 integrated (locks 39/39).

**UPDATE 2026-10-17 00:45Z (OVERNIGHT WAVE: M2 runtimes LANDED --
torch/libtorch/tensorflow/blas/openblas; B-34 filed; 566/0)**:
- **All five overnight wave branches LANDED** (sibling parked; this
  session completed the landings on the v0.64.6 slot):
  - **`xiom.torch 0.1.0` + `xiom.libtorch 0.1.0`** (land `012760fc`;
    records re-pointed): agent x2 LIVE 22/22 + 33/33 (libtorch 2.9.0
    CPU); SKIP-leg gate 19/19 + 8/8 x2.
  - **`xiom.tensorflow 0.1.0`** (land `be30e872`): 109/109 C API
    loader; agent x2 LIVE 74/74 (libtensorflow 2.18.1 CPU); SKIP-leg
    gate 17/17 x2.
  - **`xiom.blas 0.1.0`** (land `30c0d1ac`): safe linalg over the live
    xiom.openblas seam; 50/50 x2; + **`xiom.openblas`** STATUS pin fix
    (32/32).
  - validate **566/0**; pushed `6bf167ba`.
- **CHECKOUT-HYGIENE TRAP found + fixed (recipe addendum)**: `git
  checkout <branch> -- <dir>` does NOT apply the branch's DELETIONS --
  stale root stubs (`xiom-blas/blas.xi`, `xiom-tensorflow/tensorflow.xi`)
  shadowed the new `src/` modules (blas: 119 T001s + W001 module
  collision).  Fixed via `git rm` in `30c0d1ac`; tf re-verified 17/17
  after removal.  When a branch restructures a package dir: remove the
  dir first (`git rm -rf`) then checkout, or diff the branch manifest.
- **B-34 filed to compiler** (`REL-20261017-0042-bindings`; medium;
  probe bundle `docs/repro/bindings-pilot/vec-alias-generic/`, landed
  `294c28bc`): cross-module `Vec[alias]` generics do not unify -- RED
  on .5 AND .6 (pre-existing; NOT a .6 regression; found cross-checking
  tf; not blocking any landed package).
- **M2 publish request filed** (`-0042-bindings-2`, combined):
  torch/libtorch/tensorflow = NEW names (ops scopes); blas/openblas =
  confirm registry entries; one wave batch suggested.
- 03:15Z: **B-34 ACKED** by the compiler -> resolver/alias-unification batch (1548-stdlib-6 / 2100 family).
- MORNING TODO: gps scope still pending (`-2144-bindings-2` acked);
  branch-side `COMPILER_VERSION` bump still pending (owner/sibling);
  B-32 (m358) + B-34 ride the v0.64.7 wave.

**UPDATE 2026-10-17 15:05Z (doorbell -- `eco-v0.1.195` + `eco-v0.1.196`
LIVE; ML core tier + orbitdb shipped)**: packages confirms two more
batches carrying this lane's packages:
- **`eco-v0.1.195`** (run 39039228850 green; all registry live-verified;
  validate 571/0): **gguf 0.1.4** (sha256 `0dda8b2b...`; non-ASCII string
  values + byte/UTF-8 accessors), **http 0.1.9** (`f7b0c30f...`;
  binary-safe bodies; jev dep satisfied), **pulse 0.2.0**
  (`5cbf1ea8...`; hook seam + Server-token seam; PULSE `-1312` fixed,
  Station stage 2b unblocked). README/STATUS sync `e9250141`.
- **`eco-v0.1.196`** (run 39039898017 green; allowlist 561 -> 564; all
  live-verified; validate 571/0): **orbitdb 0.2.1** (`c8fc6548...`;
  160/160 x2 + db_crash 25/25; `-1245-orbitdb` fixed), **numpy 0.1.0**
  (`0eaa9185...`; Phase-3 COMPLETE 147/147), **llm 0.1.0**
  (`3c85e858...`; M3 COMPLETE 303/303; deps gguf 0.1.4 live).
  Registry now carries the full ML core (arrow/openblas/pandas/jev/onnx/
  gguf/llm/numpy) + orbitdb. README/STATUS sync `b1d49388`.
- Remaining: numpy Phase-4/real-BLAS, llm WPM+quant formats, jev M3
  remainder, pandas phases on the bindings arrow landing, compiler
  re-verify queue (B-29/W1.4/W2.3/B-34 + m348-m351); owner gates open:
  jev S6/S8, pandas section-6. Lane meanwhile launched the **NVIDIA
  backlog execution** (7 agents: cuda-math/cudnn/tensorrt/nvenc/nvml-nvapi/
  optix/onnx-directml; AMD hardware-gated).

**UPDATE 2026-10-17 12:05Z (MORNING: v0.64.6 REPIN on bindings +
`eco-v0.1.194` -- M2 wave + gps LIVE)**:
- **Branch repin landed**: `d2ef7ec2` -- `COMPILER_VERSION` -> **v0.64.6**
  + all 566 STATUS records aligned (validate 566/0); the slot/file
  mismatch is closed.
- **`eco-v0.1.194` LIVE** (run 39030226463 green; all registry
  live-verified; merge `ec548542`; publish-sync `c1d1d85d`):
  - `xiom.torch 0.1.0` (`bde0ce5c...`; SKIP gate 19/19 x2)
  - `xiom.libtorch 0.1.0` (`865c6d2a...`; 8/8 x2; scope LIVE 11:28Z)
  - `xiom.tensorflow 0.1.0` (`0f4bb6a5...`; 17/17 x2)
  - `xiom.blas 0.1.0` (`bee07a38...`; 50/50 x2)
  - `xiom.gps 0.1.0` (`020b50ac...`; live 11:52:45Z; scope LIVE
    11:28Z; allowlist 559 -> 561; 28/28 x2)
  - openblas metadata fix correctly skipped (version_exists; rides a
    future openblas bump).
- Both publish close-outs FIXED (`-0042-bindings-2`, `-2144-bindings-2`).
  Eco through **`.194`** (109 releases).  B-34 acked -> compiler
  alias-unification batch (1548-stdlib-6/2100 family); B-32 stays
  m358.  Both ride v0.64.7; nothing else in flight on this lane.

**UPDATE 2026-10-17 14:15Z (REAL-ACCEL WAVE LANDED: openblas real leg +
arrow/pandas sync; 566/0)**:
- **`xiom.openblas` Phase-1 REAL LEG LANDED** (land `cff4543a`; record
  `0a4cb027`): linked cblas + LAPACK (transA/B, SVD/eigen/solve real
  values, workspace query, leg marker); integration **x2 42/42** on
  the .6 slot (stub-leg gate; real-leg provenance v0.3.34 x64 LP64,
  BSD-3; `tests/run_real_leg.ps1` -- real leg green on the branch).
  NOTE: openblas 0.1.0 is already live (eco-v0.1.193); the tree change
  publishes with the NEXT version bump (packages' version_exists rule).
- **`xiom.arrow` synced to the main-line real-backend content** (land
  `e30db62e`): record refreshed **x2 32/32** on .6
  (`bridge/arrow_real.cpp`, port.args, real-backend probes; stub
  suite unchanged at 32).
- **`xiom.pandas` real Arrow-backed C++ bridge PREP landed** (same
  land): `bridge/xiom_pandas_arrow.cpp` (821 lines) +
  `REAL-BACKEND-REQUIREMENTS.md` + `probe_real_arrow.xi` + port.args;
  gate **80/80** (stub backend; the bridge prep is inert until the
  Arrow real backend lands -- pandas 2-4 follow per the program plan).
- validate **566/0**; pushed `74e93a35`.  No publish request this pass
  (openblas version_exists rider; arrow/pandas prep only) -- the next
  bump carries them.

**UPDATE 2026-10-17 15:10Z (doorbell 15:00Z: `xiom.usd` LANDED; eco
.195/.196 LIVE; NVIDIA wave launched)**:
- **`xiom.usd 0.1.0` LANDED** (content `6c8fa791`; record `7cea7786`;
  note: the sibling's concurrent commit swept the staged USD checkout,
  so content+docs share one commit -- consistent, watched): OpenUSD
  v26.08 scene-import (58-entry C-ABI + generated trampolines; stage/
  prim/attr/mesh/material/time; typed errors + stale-handle
  invalidation); gate **x2 65/65 LIVE on usd_ms.dll (ABI 2608)** +
  typed SKIP; validate **567/0**; publish request
  `REL-20261017-1507-bindings` (NEW name; ops scope).
- **Eco**: **`eco-v0.1.195` = gguf/http/pulse 0.2.0** + **`.196` =
  orbitdb/numpy/llm ML core** LIVE (111 releases; sibling doorbell).
- **NVIDIA vendor wave LAUNCHED** (sibling): 7 agents -- cuda-math/
  cudnn/tensorrt/nvenc/nvml-nvapi/optix/onnx-directml; AMD
  hardware-gated.  Compiler: v0.64.7 candidate tags being relayed
  (`compiler-compiler-v0.64.7`); not released yet.

**UPDATE 2026-10-17 16:55Z (NVIDIA WAVE PART 1 LANDED: cudnn +
nvenc; 569/0)**:
- **`xiom.cudnn 0.1.0` LANDED** (land `78fb1ae3`; record `6970134f`):
  cuDNN 9 essentials (25/25 loader surface; conv/act/pool/softmax +
  workspace query; nothing vendored); gate **x2 60/60 LIVE** on cuDNN
  9.27.0.42 (RTX 3070 Ti cc 8.6; conv parity 54/63/90/99) + typed
  SKIP path.
  - **LIVE-RIG NOTE**: the working recipe needs BOTH the cuDNN wheel
    bin dir AND the cuBLAS bin dir ON PATH.  `XIOM_CUDNN_DIR` alone
    classifies the DLL but the dependent sub-libraries fail to bind;
    the probe then aborts (0xC0000409) instead of skipping.  Flagged
    in the publish request; README addendum recommended to the
    package owner.
- **`xiom.nvenc 0.1.0` LANDED** (land `ae937669`; record `9d042f59`):
  NVENC + NVDEC loader-only (H.264/HEVC real bitstreams + cuvid decode
  roundtrips; typed errors); gate **x2 67/67 LIVE** on driver API 13.1
  (forced-IDR H.264 2442B + HEVC 3920B Annex-B, NVDEC back to NV12) +
  typed SKIP path.
- validate **569/0**; pushed `9d042f59`; publish request
  `REL-20261017-1653-bindings` (PART 1; part 2 agents in flight:
  cuda-math/tensorrt/nvml-nvapi/optix/onnx-directml).

**UPDATE 2026-10-17 18:20Z (NVIDIA PART 2 LANDED -- 7 packages; validate
576/0)**:
- **CUDA math trio** (land `929c233c` + record `d4b7caee`): `xiom.cublas
  0.1.0` **x2 62/62 LIVE** (12.9.2.10 wheel; sgemm/saxpy/sdot/scal/
  nrm2/gemv exact), `xiom.cufft 0.1.0` **x2 45/45 LIVE** (11.4.1.4;
  R2C/C2R/Z2Z/D2Z/Z2D roundtrips), `xiom.cusparse 0.1.0` **x2 56/56
  LIVE** (12.5.10.65; CSR spmv/spmm exact + i32 index roundtrip).
- **`xiom.tensorrt 0.1.0`** (land `1d3c2426` + record `ebade5b8`):
  **x2 55/55 LIVE** on TensorRT 10.16.1 -- plan build -> serialize
  (16-18KB) -> deserialize -> enqueueV3, Mul-by-2 output 2,4,6,8 exact;
  logger bridge (98 msgs).
- **`xiom.nvml 0.1.0`** + **`xiom.nvapi 0.1.0`** (land `6d42b87a` +
  record `5d4c2b77`): **x2 40/40 + 25/25 LIVE** on driver 616.92 --
  full GPU telemetry (mem/util/thermal/power/clocks/PCIe/energy) +
  presence/identity (driver branch, PCI ids).
- **`xiom.optix 0.1.0`** (land `c261c2ed` + record `321f4be8`): **x2
  37/37 LIVE** (ABI 118; real device RT-core + SBT readback + PTX +
  param roundtrips) + typed SKIP.
- **LIVE-RIG NOTES**: CUDA math needs the pip-wheel bin dirs on PATH
  (cuSPARSE also nvJitLink + nvRTCR bins for its dependent DLLs);
  TensorRT needs `XIOM_TENSORRT_DIR` = extracted wheel's tensorrt_libs
  + cuBLAS/cuDNN bins on PATH; NVML/NVAPI/OptiX need only the driver.
- validate **576/0**; pushed `321f4be8`; publish request PART 2 =
  `REL-20261017-1819-bindings`.  Only **onnx-directml** remains in
  flight on the NVIDIA wave.

**UPDATE 2026-10-17 19:50Z (NVIDIA WAVE COMPLETE; eco-v0.1.197 LIVE)**:
- **`eco-v0.1.197` LIVE** (run 39059605811 green; merge `38c41345`;
  registry live-verified): **`xiom.usd 0.1.0`** (sha `f38e85aa...`),
  **`xiom.cudnn 0.1.0`** (`a1377f4c...`), **`xiom.nvenc 0.1.0`**
  (`9ff4eb1d...`); scope LIVE eco-release 566; allowlist 564 -> 567;
  packages re-verified on landing (usd LIVE usd_ms path 65/65; cudnn
  60/60 with the PATH recipe; nvenc 67/67).  Engine can consume the
  USD importer per the accepted wishlist.
- **`xiom.onnx 0.2.0` LANDED** (last NVIDIA unit; land `bd2854bf` +
  record `ccb913d8`): DirectML EP leg (OrtDmlApi append + device_id;
  DML session A(2,3)+B(4,5) -> C(6,8) EXACT; slot-0 stability
  documented); **x2 60/60 LIVE** (onnxruntime 1.17.1 + DirectML
  1.24.4) + 59/59 CPU-only SKIP.  Addendum filed
  `REL-20261017-1947-bindings` (rides the part-2 batch).
- **NVIDIA WAVE COMPLETE**: 8 units all landed; part 1 LIVE in
  `.197`; part 2 (cublas/cufft/cusparse/tensorrt/nvml/nvapi/optix) +
  the onnx 0.2.0 addendum queued at packages.  validate **576/0**.
  Remaining lane watch: v0.64.7 (m351/B-33 + m358/B-32 in the cut);
  AMD side is hardware-gated.

**UPDATE 2026-10-18 18:05Z (doorbell -- `.198` + `.199` full records;
pulse 0.3.0 single tag; v0.64.7 repin + re-verify COMPLETE on bindings)**:
- **`eco-v0.1.198`** (run 39142312352 green; all live-verified):
  **vectors 0.2.0** (`130427a5...`; MOTE carve -- 45-module library
  type-check green, 177/177 x2 @ record `3de13359`; `-1520` fixed),
  **pulse 0.2.2** (`89ba66ec...`; version-identity fix; `-2102` fixed),
  **onnx 0.2.0** (`4c230691...`; DirectML EP; `-1947` fixed). Bindings
  `.7` repin delta merged into packages (`f9c08e2c`).
- **`eco-v0.1.199`** (run 39143579565 green; allowlist 567 -> 574; guard
  574/565/9/0; validate 581/0): **cublas** `930f602b`, **cufft**
  `3163d647`, **cusparse** `c1dc295f`, **tensorrt** `17d40789`, **nvml**
  `0aa65326`, **nvapi** `80873598`, **optix** `012dd8b6` (all 0.1.0;
  verify-on-landing x2 LIVE matched 62/45/56/55/40/25/37;
  `-1819-bindings` fixed). **NVIDIA WAVE COMPLETE** (part 1 in `.197`,
  onnx 0.2.0 in `.198`, part 2 in `.199`).
- **`xiom.pulse 0.3.0`** single tag `xiom-pulse/v0.3.0` (sha256
  `bae0dd08...`; stateful `HookCtx{state: Vec[Int]}` seam + ctx hook
  variants; 203/203 x2 @ record `2ab242f8`; `-1615-pulse` fixed;
  registry live; **PULSE Phase B unblocked**).
- **v0.64.7 repin on bindings DONE**: `04a06c9d` -- COMPILER_VERSION +
  **576 records** (validate 576/0; slot verified: sqlite 21/21 + nvenc
  67/67 live). **Re-verify COMPLETE** (`76674292`): **B-16/17/18/19/22/
  23/25/26 verified FIXED**; glfw 37/37 + sdl3 72/72 x2 live;
  workaround retirement unlocked (B-26 wave running).

**UPDATE 2026-10-19 18:15Z (v0.64.8 RELEASED + REPINNED; B-34 VERIFIED
FIXED -- bindings findings ALL CLOSED)**: doorbell tick.
- **v0.64.8 LIVE (17:49Z) + repinned** (installed v0.64.8; tag
  `4d040604b`, run 39296778685; arena/Vec/alias fixes + the engine
  memory/threads fixes).  The registry publish hit
  `publisher_not_mapped` (403; tag-ref retry requested by the release
  lane -- not ours).
- **B-34 VERIFIED FIXED on v0.64.8**: `vec-alias-generic/probe.xi`
  compiles + runs (returns length=1; was `T001` on .5/.6/.7).  Findings
  doc row added + the B-33 row updated to FIXED (m351, .7).  Relay INFO
  to compiler `REL-20261019-1801-bindings-2`.
- **Every bindings findings row is now closed/resolved**: B-13/14/15,
  B-30, B-31 fixed (.7); B-26/B-32 retired (sqlite 0.5.0 live with the
  restored nested shape); B-27/28 stdlib fixes bundled; B-29 closed as
  a probe defect; B-33 fixed (m351); B-34 fixed (.8).  **No open
  compiler findings from this lane.**
- Eco: `xiom.sqlite 0.5.0` LIVE (morning merge `772e9f34`; B-32
  retired); MCU Phase-1 publish request filed (firmata/micropython/uf2).
  Relay tip `bafca5f`; note: repo-wide validate flags other lanes' items
  (`-2057-engine` missing History; previously a registry non-ASCII) --
  theirs to fix.

**UPDATE 2026-10-19 15:05Z (doorbell -- `xiom.pulse` 0.3.1 LIVE;
sqlite 0.5.0 tag already recorded)**: packages confirms the Phase B
loop-switch publish:
- **`xiom.pulse 0.3.1`** single tag `xiom-pulse/v0.3.1` (sha256
  `38465713...`; registry live-verified; sync `2c167472`): **fallback
  seam** (`HookSet.fallback` on route kind 0 AFTER the TE/CL policy and
  BEFORE the package 404; `hooks_install_fallback`/`clear`/`has` +
  `FallbackAlreadyInstalled`; absent/empty = byte-identical 404, kind 2
  stays 405) + **HEAD body trim** (GET status/headers/Content-Length with
  zero body bytes across `handle_connection*`/`serve`/`serve_with`/
  `serve_with_ctx`, incl. hook/ctx/fallback paths); 231/231 x2 @ record
  `2e3b6f7f`; `-1150-pulse` fixed with API + sha (Station can retire its
  product loop; test-back requested). PULSE Phase B loop-switch unblocked.
- **`xiom.sqlite 0.5.0`** already recorded (single tag
  `xiom-sqlite/v0.5.0`, sha256 `35934316...`, run 39247791918 green;
  B-32 retired / nested `Result[Option[SqliteRow]]` restored; 21/21 x2
  on v0.64.7).
- Lane state: MCU Phase-1 landed (firmata 122/122 + micropython 19/19 +
  uf2 62/62; 579/0) with the publish request filed; findings ledger
  reconciled (B-13/14/15, B-30, B-31 fixed on v0.64.7; only B-21/B-24
  rows remain).

**UPDATE 2026-10-21 14:40Z (merge-ready update sent; charts+kafka publish
paths already acked; usb arm64 retry armed)**:
- Relay: **no inbound action items** -- charts 0.2.0 scope ask filed +
  request **acked** by packages ("queued behind kafka"); kafka 0.2.0
  publish queued (+ ORBITWIRE co-run).  Open items are to-all infos only
  (compiler announcements, xvector WSL-restart warning, orbitdb WSL/relay
  hygiene) -- no bindings action.
- **Merge-ready update filed**: `REL-20261021-1436-bindings` -- branch
  `c20dc646`, validate 579/0, charts + kafka landings ready for the next
  merge window.
- **usb arm64 retry armed** (`emulate-arm64.ps1 -Package usb
  -HardTimeoutSec 2700`, background): the fleet's only timeout gets a
  45-min cap.
- Tree clean; relay validate green (858 items).

**UPDATE 2026-10-21 13:30Z (charts 0.2.0 + kafka 0.2.0 LANDED; arm64 fleet
sweep 12/13 green; charts publish requested)**:
- **`xiom.charts 0.2.0` LANDED** (`fa9f5605`; x2 **71/71**): float geometry,
  linear/log scales, nice ticks, axes/grid/legends/annotations/markers,
  viridis/magma colormaps; line/scatter/bar(grouped/stacked)/area/step/
  pie/doughnut/histogram; byte-stable SVG; pure XIOM.  Publish request
  `REL-20261021-1233-bindings` filed (**new name -> ops scope**).
  Next: P2 = 2D advanced + 3D static projection/emitters (charts 0.3).
- **`xiom.kafka 0.2.0` LANDED** (`a43a2eda`; x2 **50/50 LIVE**): real
  librdkafka bindings -- producer/delivery callbacks, consumer
  (subscribe/assign/commit), metadata, transactions, config/error surface;
  mock-cluster live batteries (no broker); admin create/delete typed
  unsupported (-165) as expected.  Publish already queued with packages
  (+ ORBITWIRE co-run).
- **arm64 emulated fleet sweep COMPLETE**: **12/13 green** (serial, mqtt,
  i2c, spi, adc, pwm, sensor, can, ble, zigbee, hid, modbus all rc=0);
  **usb = rc=124** (hit the 20-min hard cap; suite too slow under qemu --
  retry with a higher per-suite cap if needed).  Note xvector's to-all
  warning: host WSL VM restarts kill long batteries -> keep emulated runs
  short + logged.
- validate **579/0**; tree clean, 3 commits pushed.

**UPDATE 2026-10-21 11:50Z (charts/plots program -- 2D + 3D COMPLETE coverage,
axes/grids everything; charts P1 launched; split approved)**: owner
clarification + design decision.
- **Program scope**: `xiom.charts` + `xiom.plots` cover **2D AND 3D**
  charts/plots on full axis/grid systems -- feature parity with
  matplotlib-class tooling, phased.
- **2D set** (charts): line/multi-line, scatter, bar (grouped/stacked/
  horizontal), histogram, area, step, pie/doughnut, stem, box/violin,
  heatmap/imshow, contour/contourf, candlestick/OHLC, error bars,
  fill-between, quiver/streamline, polar/radar, subplot tiles.
- **3D set** (static projection in charts, camera in plots): 3D axes +
  grid (orthographic + perspective; pan/rotate/zoom), surface, wireframe,
  scatter3D, line3D, bar3D, quiver3D, contour3D, voxels, trisurf;
  colorbars; depth sorting.
- **Axis/grid system**: linear/log/symlog scales, tick locators +
  formatters + minor ticks, dual/twin axes, colorbars, legends,
  annotations, spines, themes.
- **Split approved**: `xiom.charts` = static deterministic model + SVG
  emitters (pure XIOM); `xiom.plots` = figure/gridspec/camera API +
  interactive backends (SVG export via charts; OpenGL via xiom.opengl
  0.5.0 + glfw 0.6.0/sdl3 + typography 0.1.2; Vulkan later).  Name
  `xiom-plots` is free; ownership = bindings; packages merges/publishes.
- **Phasing**: P1 = 2D static core (**running**: `feat/charts-p1`,
  `am-1792582299742-2v93ak`); P2 = 2D advanced + **3D static
  projection/emitters** (charts 0.3); P3 = `xiom.plots` interactive 2D+3D
  on OpenGL; P4 = polish (animations, decimation, styles).

**UPDATE 2026-10-21 11:35Z (Kafka completion launched; matplotlib assessment)**:
- **`xiom.kafka` already exists** (0.1.0 "ported only": librdkafka FFI
  stubs -- handle -1 / poll None / admin Err(-999); not publishable).
  Owner asked for full coverage -> **`feat/kafka-real` launched**
  (`am-1792582075496-y6qhj1`): librdkafka (BSD-2) light clone at pin,
  real producer/consumer/admin/config/error surface, **mock-cluster live
  batteries** (no broker needed), 100% coverage table, x2, publish after
  landing.  No conflicts: stdlib owns protocol parsers only; the kafka
  client driver is a package (STDLIB_EXTENSION.md §3121 cites
  xiom-kafka), and no other lane has it.
- **matplotlib: not a viable native binding** -- pure Python, no stable C
  API (the C++ Agg internals are private).  Options: extend
  **`xiom.charts`** (existing: deterministic integer line/bar -> SVG;
  0.1.0 incubating, 28 tests), a CPython-embedding package as a Python
  gateway (program-scale), or a native C-ABI plot backend (plplot/Cairo
  loader, Skia, ImPlot).  No stdlib/package name conflict for it.
- Fleet sweep: serial/mqtt/i2c/spi/adc/pwm/sensor/can green; ble..modbus
  in flight.

**UPDATE 2026-10-21 10:20Z (morning -- pandas 0.2.1 live .201; Docker back;
fleet sweep restarted)**:
- **pandas resolved**: 0.2.0 was already live (parallel build found; lane
  re-synced to the live artifact 132/132), then **`xiom.pandas 0.2.1`
  (section-8 superset) LANDED + PUBLISHED in `eco-v0.1.201`** (164/164 x2;
  165-test superset live).  Requests `-2049` + `-1756` FIXED; merge-ready
  `-2021` fixed.  Lesson recorded: double-implementation on parallel
  pandas builds -- re-sync to the live artifact before re-landing.
- Relay: bus validate green (827) after the bindings repair of the
  owner->engine note (front matter + history) and the BOM/orbitdb item
  repair.  New arm64 finding filed: module-scope Vec init emits invalid IR
  on LLVM 14 (evidence recorded) -- surfaced by the emulation work.
- **Docker back (28.3.0)**; the previous watcher died with its session, so
  the sweep did not auto-run -> **arm64 fleet sweep restarted**
  (background, timeout-capped 20 min/suite).
- Remaining: MCU publish (next cycle), epos publish (packages/ops),
  compiler fixer wave (Map/Set AV + Vec4f, orbitdb soak, Err-push, arm64
  IR) -> next tag, AMD backlog, fleet sweep results.

**UPDATE 2026-10-20 12:35Z (morning -- pandas 2-4 merged; Docker engine
stuck; fleet sweep armed to auto-run)**:
- Overnight: **`xiom.pandas 0.2.0` LANDED** (section-8 real Arrow bridge:
  Acero-free groupby/join, f64 apply/filter, Parquet component, additive
  ownership frees; 110/110 x2; publish request `-2049-bindings` open) and
  **bindings merged to main** (`e95c6072`; validate 584/0; ops allowlist
  instruction sent -- epos now, MCU deferred).  `xiom.jev 0.2.0` live
  (M2+M3 complete); PULSE Phase B unblocked (m371).
- **Docker engine stuck**: Desktop app running since 21:12 but the
  docker-desktop distro is Stopped, `_ping` returns 500, and the CLI
  control channel hangs (stop/start/restart all hang) -> **manual Docker
  Desktop restart needed**.  The overnight fleet sweep failed on this
  (rc=125, 500 on _ping; no suite results).
- Watcher armed (`scripts/wait-docker-then-fleet.ps1`, background, 90 min
  of bounded probing): runs the arm64 fleet sweep as soon as the engine
  answers.
- Remaining: pandas 0.2.0 publish (packages), epos publish
  (packages/ops), MCU next cycle, compiler fixer wave (new findings:
  Map/Set AV + Vec4f, orbitdb soak, Err-push), AMD backlog, fleet sweep
  (after Docker).

**UPDATE 2026-10-19 20:10Z (MCU agents stopped+worktrees removed; Agent
Manager offline; arm64 sweep hardened+restarted)**:
- **MCU Phase-1 agents**: confirmed finished (worktrees clean at delivered
  commits).  Sessions stopped (stop timeouts were IPC lag; the registry now
  shows none) and the three worktrees removed (`feat/firmata`,
  `feat/micropython`, `feat/uf2-2` branches kept).  Deliveries landed;
  publish deferred to the next cycle.
- **Agent Manager is currently OFFLINE for all sessions** (driver
  included) -- that is why the cards looked stalled; tree/relay work
  continues independently.
- **arm64 fleet sweep**: serial's emulated compile ran 35+ min at 109% CPU
  (slow, not hung).  Harness now wraps each run in a hard per-suite
  `timeout` (default 1200s); the stuck sweep was killed and restarted.
- Ghost cards (`micropython-2`/`uf2-3`) are stale registry entries with no
  worktrees; they reconcile on extension reload.

**UPDATE 2026-10-19 19:30Z (arm64 gpio PASSES; fleet sweep fixed+restarted)**:
- **arm64 gpio suite: all 21 tests passed** (emulated, official
  linux-arm64 compiler) -- first fleet package green under arm64.
- Fleet sweep script had a PS 5.1 parse bug (`"$p:"` -> drive-variable
  reference); fixed to `${p}` and restarted in the background (13 suites,
  summary -> `%TEMP%\kilo\arm64-fleet\summary.txt`).

**UPDATE 2026-10-19 19:00Z (registry thread fixed; compiler scoped MCU +
fixed riscv; pandas P3 live; arm64 fleet sweep started)**:
- Relay: `-1755` registry blocker **RESOLVED** -- xiom-std 0.64.8 LIVE
  (independent verification, sha256 + OIDC provenance, tag refs retried).
  Compiler: **MCU request SCOPED** + **riscv link triple FIXED**
  (`383fe9dc6` -- our `-1419` finding) -> re-probe when the next tag
  ships.  Pulse 0.2.2 published (ops dogfood retest queued).
- Packages: **eco-v0.1.200 LIVE** (llm 0.2.0 / numpy 0.1.1 / openblas
  0.1.1 / arrow 0.1.1) + **pandas 0.2.0 single tag (Phase-3)**;
  validate 584/0; MCU acknowledged parked.
- arm64: gpio suite still compiling (emulated); **fleet sweep started in
  the background** (`scripts/emulate-arm64-fleet.ps1` ->
  `%TEMP%\kilo\arm64-fleet\{pkg}.log` + summary): serial/mqtt/i2c/spi/
  adc/pwm/sensor/can/ble/zigbee/hid/usb/modbus.

**UPDATE 2026-10-19 18:45Z (v0.64.8 re-verify COMPLETE -- B-21/B-24 fixed;
batteries green; arm64 harness added)**: continuation.
- **Last two findings verified FIXED on v0.64.8**: B-21 (`&mut` of a
  struct-return temp: probe compiles+runs, a=7 b=9 -- no codegen crash);
  B-24 (out-slot reads after C writes: ffi_bad=0 byte_bad=0 of 400).
  **All B-series rows now FIXED/verified -- the ledger is fully closed.**
- Batteries on .8: glfw **37/37 x2 LIVE** + sdl3 **72/72 x2** (STATUS
  run_by `reverify-v0.64.8`).
- **`scripts/emulate-arm64.ps1` added** -- one-command arm64 emulation
  harness (Docker Desktop linux/arm64 + clang-19 image + the official
  linux-arm64 compiler; `--timeout 0` for qemu).  mqtt suite proven green
  under arm64; emulated compiles are slow -> run fleet sweeps in the
  background (gpio smoke started).

**UPDATE 2026-10-19 18:10Z (relay check -- v0.64.8 repin MADE REAL; MCU
publish DEFERRED to next cycle; duplicates swept)**:
- **v0.64.8 repin completed**: the driver record claimed it, but the tree
  was still pinned v0.64.7 while the installed slot is v0.64.8 -> bumped
  `COMPILER_VERSION` + `status.ps1 -Action repin` (**579 records**),
  validate **579/0**.
- **MCU**: Phase-1 landed earlier (firmata 122/122, micropython 19/19,
  uf2 62/62; 579/0) but per owner "not this cycle" the publish request
  `REL-20261019-1454-bindings` is **CLOSED as deferred to the NEXT
  cycle** (do not publish now).
- Duplicates swept: `feat/micropython-2` + `feat/uf2-3` worktrees and
  branches removed; `feat/uf2` placeholder deleted; live = firmata,
  micropython, uf2-2.
- Relay inbox: only to-all compiler/playground info items (v0.64.8 GO +
  release + absorption claim).  Registry blocker: `-1755-stdlib`
  (publisher_not_mapped) blocks the stdlib .8 registry publish --
  packages/ops side.  Agent Manager: no busy sessions.

**UPDATE 2026-10-19 14:05Z (arm64 emulation PROVEN end-to-end; target probe
-- arm=AArch64-Linux, riscv=triple bug; MCU sessions deduped)**: docker
back up.
- **Suite proof**: `xiom.mqtt` conformance suite **PASSES under arm64
  emulation** (trixie/clang-19 image, `--timeout 0` for the slow emulated
  compile -- clang-19 accepts the IR; the earlier 300s cut was the xiom
  default).  Harness: `docker run --platform linux/arm64` + mounted
  repo/stdlib + official `xiom-0.64.7-linux-arm64` (sha256 verified).
- **Target probe**: `--target arm` = AArch64 **linux** PIE (not
  Cortex-M); `--target riscv` emits triple `riscv64gc-unknown-linux-gnu`
  -> clang rejects it -> riscv target not linkable as shipped (compiler
  finding relayed).  MCU request stands (thumbv6m/v7em + proper riscv32
  targets + no_std).
- MCU wave: duplicate micropython/uf2 sessions stopped; live sessions =
  firmata (`ses_eabe3783`), micropython (wt-1), uf2 (wt-2).
- sqlite 0.5.0 PUBLISHED (tag; sha 35934316) per the driver record.

**UPDATE 2026-10-19 13:10Z (MCU Phase-1 wave -- firmata + micropython + uf2;
compiler owner-request filed; post-restart recovery)**: owner go.
- **Launched**: `feat/firmata` (session `ses_eabe3783...`, wt-2); the PC
  restart dropped the other two -> relaunched (`am-1792415294827-v179h9`):
  `feat/micropython` (raw-REPL client) + `feat/uf2` (format + flashing).
  All host-side, fixture-testable (no hardware), v0.64.7 pin, x2,
  origin/bindings base.
- **Compiler relay filed**: `REL-20261019-1220-bindings` -- owner request
  for the MCU/bare-metal program (Cortex-M thumbv6m/v7em/v8m + RISC-V
  riscv32imc/imac, no_std profile, startup/linker contracts, QEMU
  Cortex-M/riscv32 emulated CI; vendor SDK licenses clean for static use).
- **QEMU/arm64**: `xiom-arm64-emu:trixie` (clang-19) image built before
  the restart; Docker engine restarting -> suite proof re-run pending.
  `xiom-arm64-emu:bookworm` (clang 14) too old for suite IR (hello-world
  green).
- Post-restart: stray `a.out.ll` removed; relay item committed
  (`c9d4f9f`); tree clean.

**UPDATE 2026-10-19 12:20Z (QEMU/arm64 emulation PROVEN; MCU package plan
backlogged)**: owner go for QEMU.
- **arm64 emulation via Docker Desktop** (no sudo): official
  `xiom-0.64.7-linux-arm64.tar.gz` (sha256 `de219935...` verified) runs in
  an arm64 container; hello-world compiles+runs.  Cached toolchain image
  `xiom-arm64-emu:bookworm` (clang 14) builds; clang 14 is too old for the
  suite IR (typed-pointer mismatch vs the lane's Windows **clang 22**) ->
  trixie/clang-19 image building.
- Unblocks: **Pi/edge arm64 smoke** (codegen/ABI) without hardware;
  device-I/O legs stay SKIP.  **NOT for AMD** (no ROCm/AMF GPU emulation)
  -- AMD stays backlog per owner.
- **MCU plan (backlog)**: direct XIOM-on-MCU needs bare-metal targets
  (thumbv6m/v7em/riscv32) + no_std runtime -> compiler program (Phase 2).
  Phase 1 (now, bindings, host-companion packages): `xiom.firmata`,
  `xiom.micropython`, `xiom.uf2` (+ picotool orchestration, BSD-3);
  esptool/OpenOCD/arduino-cli = GPL -> user-tool orchestration only;
  Arduino AVR core LGPL -> no vendoring.  Vendor SDKs clean for future
  on-MCU packages: Pico SDK BSD-3, STM32 HAL BSD-3, ESP-IDF / Zephyr /
  CMSIS Apache-2.0.  QEMU has Cortex-M boards (micro:bit nRF51, STM32,
  netduino) + riscv32 -> emulated MCU CI possible post-target.

**UPDATE 2026-10-19 11:55Z (findings-ledger reconciliation -- B-13/14/15,
B-30, B-31 verified FIXED on v0.64.7; B-27/28 stdlib fixes bundled)**:
morning continuation -- all stale rows re-probed.
- cb-abi: B-13 probes 2/4/5 = 42 across param/local/cast paths; B-14
  explicit `-> Unit` `return;` accepted; B-15 multi-arg element-call
  result usable (probe7 compiles+runs).
- B-30 owned-slot cast+mutate block compiles+runs; B-31 const-alias
  `--emit-ir` exit 0 (stack overflow gone).
- B-27/B-28: stdlib probe 312 green on the installed pin (fixes bundled
  since v0.64.6) -- retirement of `owned_bytes`/byte-writer workarounds is
  now possible (optional cleanup wave).
- Ledger updated (7 rows); verdicts relayed to compiler.  Open rows now:
  B-21 (acked), B-24 (fix-staged untested).
- Context: sqlite 0.5.0 publish queued packages-side for the morning;
  pulse 0.3.0 HookCtx live (PULSE Phase B unblocked).

**UPDATE 2026-10-18 16:40Z (B-26 retirement wave LAUNCHED -- sqlite restore;
coordinated plan acked by packages)**: continuing on the unlocked workarounds.
- **`feat/sqlite-restore`** (`am-1792341243306-9qysun`): `xiom.sqlite`
  0.4.1 -> 0.5.0 -- restore `query_one -> Result[Option[SqliteRow]]`
  (B-26 verified fixed on v0.64.7), remove the flat `RowOutcome`, suite
  updated, x2 on the pin.
- Coordination: **`-1254` ACKED by packages**: llm real vocabs DONE
  (302/302 x2) + bench harness dispatched; pandas 2-4 queued behind our
  arrow backend (now landed -- unblocked); **jev S6 formulas + S8 v0.2.0
  schemas + pandas section-6 ABI need the OWNER pin** (flagged, not
  guessed); accelerator extras on demand confirmed.
- B-27/B-28 (stdlib): filed + fixed (stale v0.64.4 bundled snapshot; fix
  on stdlib main, probe 312). v0.64.6/7 pins bundle the fixed stdlib ->
  the retirement gate is OPEN (candidates: fidelityfx `owned_bytes` /
  local byte-store writers; optional cleanup wave, not forced).
- Remaining reds at .7: B-29/B-34/W1.4/W2.3 (v0.64.8); B-32 in-situ
  parked.  Relay open to bindings: compiler info items only.

**UPDATE 2026-10-18 16:20Z (NVIDIA WAVE FULLY PUBLISHED -- .198 + .199;
all 7 part-2 names live)**: relay confirms the completion.
- `eco-v0.1.198`: `xiom.onnx 0.2.0` (DirectML EP; existing name).
- `eco-v0.1.199`: cublas 0.1.0, cufft 0.1.0, cusparse 0.1.0, tensorrt
  0.1.0, nvml 0.1.0, nvapi 0.1.0, optix 0.1.0 -- all registry
  live-verified (shas in `-1819-bindings` history); scopes LIVE
  eco-release 573; allowlist 567 -> 574; packages verified on-landing x2
  LIVE on v0.64.7 (62/45/56/55/40/25/37).
- `-1819` FIXED.  The whole NVIDIA program is out (build wave -> publish ->
  verify).  Open relay to bindings: only the two to-all compiler info items
  (no action).  Remaining: v0.64.8 reds (B-29/B-34/W1.4/W2.3), B-32
  in-situ parked, Pi smoke, AMD backlog, packages-half items.

**UPDATE 2026-10-18 16:15Z (retargeted v0.64.7 re-verify COMPLETE -- 8 staged
fixes verified FIXED; batteries green; workaround retirement unlocked)**:
- **B-16 / B-17 / B-18 / B-19 / B-22 / B-23 / B-25 / B-26 all verified fixed
  on v0.64.7** -- repro bundles re-run; outputs and new statuses recorded in
  `docs/BINDINGS-COMPILER-FINDINGS.md`.
- Batteries: **glfw 37/37 x2 LIVE** (GLFW 3.4.0 win64 fetched; 3/3 absent
  SKIP) + **sdl3 72/72 x2 LIVE**; STATUS records updated
  (run_by `reverify-v0.64.7`).
- Retirement candidates unlocked: sqlite `Result[Option[SqliteRow]]` restore
  (B-26), dx12 Int-typed handles / bare null (B-25/B-23), dispatcher
  simplification (B-18); pointer arithmetic usable again (byte-index stays
  the lane default -- no churn planned).
- Verdict filed to compiler: `REL-20261018-1540-bindings`; the
  `-0000-bindings` plan item closed.
- Remaining reds at .7: B-29 / B-34 / W1.4 / W2.3 (v0.64.8); B-32 in-situ
  parked (isolated green).  Housekeeping: the four locked orphan worktree
  dirs DELETED (locks cleared).

**UPDATE 2026-10-18 15:05Z (doorbell: LANE REPIN to v0.64.7 LANDED)**:
installed compiler = **v0.64.7** (`%LOCALAPPDATA%\xiom.new`; was v0.64.6
at the 23:55Z block).  Suites now run on .7; the re-verify verdicts
above stand (B-33 FIXED; B-32 red-in-situ but TYPED; B-34/B-29 red).
No new eco beyond `.197`; no new bindings-addressed items.  Pending
triggers: next fixer wave for B-32/B-29/B-34; ros2 B-33 workaround
retirement at its next touch.

**UPDATE 2026-10-17 23:55Z (v0.64.7 RELEASED + RE-VERIFIED: B-33 FIXED;
B-32 still red but TYPED)**:
- **v0.64.7 RELEASED** (22:59Z; run 39076930839; linux-arm64 target
  live; stdlib-v0.64.7; highlights = Win64 C ABI aggregates + typed
  confined faults (exit 70), host-arch targeting, etc.).  Scratch slot
  downloaded + SHA256SUMS verified (`%TEMP%\kilo\xiom0647\slot`).
- **B-33 FIXED (m351 verified)**: the ros2-abi ladder on .7 COMPLETES
  -- c2 16B-record-by-value returns 17036 (was silent death), c3
  fields 507/509, c4 1001/1005, c5 165, "done", exit 0.  The
  pointer-pretend workaround in xiom.ros2 0.2.0 can retire at the next
  touch.
- **B-32 STILL RED in-situ -- now TYPED**: restore patch + suite on .7:
  `cols.len=140701786528232` garbage -> `[FAIL] driver mem`, **exit 1**
  (was 0xC0000005 AV on .5/.6).  .7 made the failure SAFE and visible
  but did not fix the in-situ field-chain element loss; **m358 remains
  the target**.  In-repo b32 README updated with this verdict
  (`a19f78a4`).
- B-34 still RED (alias-unification batch not in this cut); B-29 still
  RED (expected).  Isolated nested probes/matrix GREEN on .7.
- Filed `REL-20261017-2350-bindings` (re-verify results to compiler).
  No unilateral repin; the bindings pin stays **v0.64.6** until the
  owner/sibling repin wave lands.

**UPDATE 2026-10-18 15:10Z (REPIN DELTA v0.64.7 PUSHED -- slot verified)**:
- The machine slot moved to **v0.64.7** (`XIOM Compiler v0.64.7`;
  stdlib-v0.64.7 production publish green per relay `e043e71`) --
  the repin is now in effect machine-wide.
- Sanity on the new slot: **xiom.sqlite flat-shape 21/21** (driver
  mem/tx/err/file all green) + **xiom.nvenc 67/67 LIVE** (driver 13.1
  H.264/HEVC encode+decode roundtrips) -- **no .7 regressions** on the
  lane's active packages.
- **Repin delta pushed** (`04a06c9d`): `COMPILER_VERSION`
  v0.64.6 -> **v0.64.7** + **576 STATUS records aligned**
  (`status.ps1 -Action repin`); validate **576/0**.
- Part 2 publish still queued at packages; the .7 re-verify item
  (`-2350`) open at compiler; **B-32 (m358)** remains the only
  prepared re-verify (re-ran on .7: still red but TYPED).

**UPDATE 2026-10-18 16:25Z (NVIDIA WAVE FULLY LIVE: eco .198 + .199;
pin/slot v0.64.7 consistent)**:
- **`eco-v0.1.198`**: **`xiom.onnx 0.2.0`** LIVE (sha `4c230691...`;
  15:53:57Z; packages verify-on-landing **x2 60/60 LIVE DirectML**).
- **`eco-v0.1.199`** (run 39143579568 green; scope LIVE eco-release
  573; allowlist 567 -> 574; all verify-on-landing **x2 LIVE on
  v0.64.7**): `xiom.cublas 0.1.0` (`930f602b...`), `xiom.cufft 0.1.0`
  (`3163d647...`), `xiom.cusparse 0.1.0` (`c1dc295f...`),
  `xiom.tensorrt 0.1.0` (`17d40789...`), `xiom.nvml 0.1.0`
  (`0aa65326...`), `xiom.nvapi 0.1.0` (`80873598...`),
  `xiom.optix 0.1.0` (`012dd8b6...`).  **THE WHOLE NVIDIA WAVE IS
  OUT** (part 1 in .197, onnx in .198, part 2 in .199).
- **Pin/slot CONSISTENT at v0.64.7** (branch `COMPILER_VERSION` +
  machine slot + 576 records).
- Sibling's .7 re-verify (`76674292`): **B-16/B-17/B-18/B-19/B-22/
  B-23/B-25/B-26 verified FIXED**; glfw 37/37 + sdl3 72/72 x2 LIVE;
  retirement unlocked (B-33 fixed per the ros2-abi ladder; B-32/B-34/
  B-29 remain red; B-29 boundary workaround stays).

**UPDATE 2026-10-18 18:05Z (B-32 RETIRED -- xiom.sqlite 0.5.0 LANDED)**:
- **`xiom.sqlite 0.5.0` LANDED** (sibling-launched retirement wave;
  branch `feat/sqlite-restore`; land `b3cbe464` + record `287675fd`):
  `query_one -> Result[Option[SqliteRow]]` restored, flat `RowOutcome`
  RETIRED; **x2 21/21 on v0.64.7** including `driver mem: caps,
  execute/query/query_one, by-name access` -- the exact nested path that
  failed under the workaround; validate **576/0**.
- **CORRECTION filed to the compiler** (`REL-20261018-1803-bindings`):
  B-32 is RETIRED -- my earlier "still red on .7" verdict used the
  STALE `restore-0.5.0-attempt.patch` bundle (predates the current
  package, old DBG instrumentation), NOT a compiler regression; **m358
  can close**.  b32 README updated to RETIRED (`9caa6caa`).
- Publish request `REL-20261018-1803-bindings-2` (xiom.sqlite 0.5.0;
  existing name; API change documented; in-tree consumers updated in
  the same land).
- Remaining reds: **B-34** (alias-unification batch pending cut),
  **B-29** (boundary-arithmetic workaround stays shipped).

**UPDATE 2026-10-18 19:20Z (B-29 CLOSED as PROBE DEFECT; B-34 witness
delivered -- remaining-red loop closed)**:
- **B-29 CLOSED -- NOT a compiler defect** (compiler triage m335 was
  right): the old probe compared ops on `3132620800` (0xBAB80000)
  against expectations derived from `0xBAD00000` (3134193664).
  Corrected witness on v0.64.7: `0xBAD00000` EXACT
  (2989/3134193664/2989) + control EXACT (2987/3132096512/2987) +
  decimal/hex literal parity exact (`parity=exact`, exit 0).  Probe
  rewritten in-repo (`cf6b4fa3`); the ngx boundary-arithmetic
  workaround is now a **retirement candidate** (next dlss/nis touch).
- **B-34 witness + exact command delivered** to the compiler
  (`REL-20261018-1915-bindings`; -1802 acked): cross-module
  `Vec[alias]` generics still RED on .5 + .7 (T001); files at
  `docs/repro/bindings-pilot/vec-alias-generic/`; matrix includes
  literal/typed/as-cast/fn-returned variants; local-alias control
  green.
- Net red state: **B-34 only** (alias-unification batch, next cut).
  B-32 retired; B-29 closed; B-33 fixed on .7.

**UPDATE 2026-10-19 13:35Z (sqlite 0.5.0 PUBLISHED; MCU Phase-1 wave
launched; arm64 emulation proven)**:
- **`xiom.sqlite 0.5.0` PUBLISHED** (single-package tag
  `xiom-sqlite/v0.5.0`, 2026-10-19T12:04:02Z; sha256
  `3593431683173a2a6a870c5a214c8178469cd919345fa929916b2b3df33f357c`;
  run 39247791918 green; registry live-verified; merge `772e9f34`;
  packages reproduced the nested restore x2 21/21 on v0.64.7 before
  close-out).  **B-32 fully retired both sides.**
- **MCU Phase-1 wave launched** (sibling): branches `feat/firmata`
  (`d3caf980`) + `feat/micropython` (`e18a1ebf`) (+ uf2);
  post-restart recovery noted; compiler owner-request filed.
- **arm64 emulation PROVEN** (`fc3d7f1f`): official linux-arm64
  compiler runs in an arm64 container; MCU host-companion plan
  backlogged; AMD stays hardware-gated.
- Findings ledger reconciled (B-13/14/15, B-30, B-31 fixed; B-27/28
  bundled; only B-21/B-24 rows remain).  B-34 witness item still open
  at the compiler (fix already upstream for the next cut).

**UPDATE 2026-10-19 15:00Z (MCU PHASE-1 LANDED: firmata + micropython +
uf2; validate 579/0)**:
- **`xiom.firmata 0.1.0` LANDED** (land `84165c27`; record `0c0ecfb0`):
  pure-XIOM Firmata 2.x host bindings (encode/decode/frame_len/session
  with port shadow + resync; typed errors; fixture-pinned traces);
  **x2 122/122** on v0.64.7 (transport SKIP seam by design).
- **`xiom.micropython 0.1.0` LANDED** (land `cd376f1f`; record
  `fc5bcf33`): host REPL protocol (Ctrl-A/B/C/D, exec/raw/eval framing,
  enter/exit, traceback passthrough, byte-trace fixtures); **x2 19/19**
  after the EOL fix below.
- **`xiom.uf2 0.1.0` LANDED** (land `c927516d`; record `8d59486d`):
  UF2 codec (block/image build/parse/validate, family catalog,
  FILECONTAINER) + BOOTSEL mount flashing seam (typed SKIP; copy +
  read-back verified); **x2 62/62**.
- **NEW TRAP (recipe addendum)**: line-oriented hex/trace fixtures are
  CRLF-sensitive on Windows checkouts (autocrlf) -- the micropython
  fixtures failed 11 loads until `packages/xiom-micropython/
  .gitattributes` (`tests/fixtures/*.trace text eol=lf`) + re-checkout.
  Other packages with such fixtures should carry the same guard.
- validate **579/0**; pushed `8d59486d`; publish request
  `REL-20261019-1454-bindings` (3 NEW names; combined MCU Phase-1).
- v0.64.8 cut is GO (owner; stdlib gate in progress; the B-34
  alias-resolution fix is a candidate) -- watch for the release.

**UPDATE 2026-10-19 18:05Z (v0.64.8 RELEASED + B-34 VERIFIED FIXED --
B-SERIES ZERO-OPEN)**:
- **v0.64.8 RELEASED** (17:49Z; annotated tag `4d040604b`; run
  39296778685 green; stdlib-v0.64.8; highlights: scoped arena for
  frame-shaped memory, zero-capacity Vec fix, m360 i128 div/rem, m368
  Vec-drop reclaim, m369 catalog index scan/cache, m370 generic-struct
  Vec elements, C-ORBIT-12/13, XVC-C-20, **B-34**).  Scratch slot
  downloaded + SHA256SUMS OK (`%TEMP%\kilo\xiom0648\slot`).
- **B-34 VERIFIED FIXED on .8**: the vec-alias-generic witness
  compiles + runs (exit 1 = len; NO T001) -- cross-module
  `Vec[alias]` unification works.  Filed
  `REL-20261019-1801-bindings` (verification to compiler).
- Spot-checks on .8: nested-payload failures=0 (B-26/B-32 stay
  retired-green); corrected B-29 witness exact.
- **B-SERIES ZERO-OPEN**: B-29 closed (probe defect); B-32 retired
  (.7) + published (`xiom-sqlite/v0.5.0`); B-33 fixed (m351); B-34
  fixed (.8); B-16..B-26 verified fixed; remaining ledger rows
  B-21/B-24 are other lanes'.
- Pending: bindings repin to v0.64.8 (owner/sibling wave; pin still
  v0.64.7); MCU publish still queued at packages; stdlib registry
  403 publisher_not_mapped blocker is packages-side.

**UPDATE 2026-10-19 19:25Z (repin v0.64.8 DONE; B-LEDGER FULLY CLOSED;
pandas 2-4 launched; MCU publish deferred)**:
- **v0.64.8 repin COMPLETE** (`COMPILER_VERSION` = v0.64.8 + records
  aligned via the sibling's re-verify `fa12730a`): **B-21/B-24 verified
  FIXED -> the findings ledger is FULLY CLOSED**; glfw 37/37 + sdl3
  72/72 x2 batteries; `scripts/emulate-arm64.ps1` harness added.
- **MCU publish DEFERRED by owner decision**: firmata/micropython/uf2
  stay LANDED but unpublished; a fresh request goes in next cycle
  (`REL-20261019-1454-bindings` closed with that note).
- **Pandas bridge section-6 decisions RESOLVED (owner GO)** --
  `REL-20261019-1917-packages`, section 8 (commit `108fdeae`):
  Acero-free fallbacks (build on Arrow 22 without Acero), TableGroupBy
  fallback, `series_apply` f64 (Float64-only; NA out of scope),
  ADDITIVE ownership frees (`pandas_c_dataframe_free` /
  `pandas_c_series_free` / `pandas_c_free` + pandas.xi + the
  "12 declared" marker), additive `dataframe_filter_f64`, Arrow-22
  parquet component (no separate stack).  **Pandas phases 2-4 agent
  LAUNCHED** (`am-1792437729398-crb6ad`; branch `feat/pandas-2-4`);
  existing 12 wrappers stay byte-identical.
- epos scope ask filed (ships next batch when ops stages it).

**UPDATE 2026-10-19 21:00Z (PANDAS 2-4 LANDED: xiom.pandas 0.2.0;
validate 579/0)**:
- **`xiom.pandas 0.2.0` LANDED** (land `ca612b98`; record `24191eb5`):
  phases 2-4 real Arrow bridge per the owner-approved section-8 pins --
  Acero-free groupby/join fallbacks (builds on Arrow 22.0.0 WITHOUT
  Acero headers), TableGroupBy fallback, `series_apply` f64
  (Float64-only; NA/NaN out of scope), ADDITIVE ownership frees
  (`pandas_c_dataframe_free` / `pandas_c_series_free` / `pandas_c_free`
  + pandas.xi + the declared-marker), additive
  `dataframe_filter_f64(bits: Int64)`, Arrow-22 parquet component
  (OpenFile/ReadTable/WriteTable; no separate stack).  18 C symbols;
  **existing 12 wrappers byte-identical**.
- Gates: agent record **110/110 x2 on v0.64.8 (Acero-free REAL
  bridge)**; the landed-tree gate re-ran 110/110 x2 (stub/absent-
  backend legs; live evidence in the record + PROVENANCE);
  validate **579/0**; pushed `24191eb5`.
- Publish request `REL-20261019-2049-bindings` (existing name;
  additive-only).
- Compiler watch: a NEW defect was filed packages-side -- Err(Str)
  payload lost on direct Err to Vec.push (v0.64.8; jev probe); not
  this lane's, watch the compiler ack.

**UPDATE 2026-10-20 16:40Z (pandas 0.2.0 was ALREADY LIVE; tree
re-synced; 0.2.1 merge wave launched)**:
- `REL-20261019-2049-bindings` closed by packages: **xiom.pandas 0.2.0
  was already LIVE** (single tag `xiom-pandas/v0.2.0`, 2026-10-19T18:53Z;
  registry sha256 `1cd063c3...`) from the in-tree main build (record
  **132/132 @ 8832fe61**; the batch also carried llm/numpy/openblas/
  arrow in `eco-v0.1.200`).
- **PARALLEL-BUILD DIVERGENCE found**: the live 0.2.0 = frame ops
  (p2 shape/columns/iloc/head/tail + p3 sort/drop/groupby; 132 tests;
  12 externs), while our landed feat/pandas-2-4 had the section-8
  surface (frees/filter_f64/parquet/Arrow bridge; 110 tests).
  Complementary, not identical.
- **Re-synced the bindings tree to the LIVE artifact** (`a701955b` +
  record `42b3afa9`; 132/132 x2; validate 579/0; pushed).  The
  parallel landing is retained on its branch for the merge.
- **0.2.1 MERGE WAVE LAUNCHED** (`am-1792514107159-cgxznv`; branch
  `feat/pandas-0-2-1`): port the section-8 additions onto the live
  132-test base -- all 132 must stay green, expect >132 total; bump
  `xiom.pandas` 0.2.1; suite x2; push.  Publish request follows
  (0.2.0 is immutable).
- Reconciliation note filed `REL-20261020-1635-bindings`.
- **LESSON (recipe addendum)**: double-implementation risk -- when a
  package request is accepted with "we implement / you implement"
  ambiguity, reconcile against the LIVE artifact BEFORE landing (or
  bump the version).  A parallel implementation that passes its own
  suite can silently diverge from the shipped registry content.

**UPDATE 2026-10-20 17:58Z (PANDAS 0.2.1 LANDED -- superset merge;
validate 579/0)**:
- **`xiom.pandas 0.2.1` LANDED** (land `c23c8616`; record `7a8a0d06`):
  the section-8 surface merged onto the LIVE 0.2.0 base -- **ALL 132
  live frame-op tests kept** + 32 section-8 checks (ownership frees,
  `filter_f64`, Parquet wrappers, f64 `series_apply` parity, Acero-free
  Arrow 22 real bridge incl. Parquet); 18 C symbols; 40 contracts;
  **x2 164/164 on v0.64.8** (agent record 164/164 x2 with the real
  probe green + the landed-tree gate 164/164 x2); validate **579/0**;
  pushed `7a8a0d06`.
- Publish request `REL-20261020-1756-bindings` (0.2.1; existing name;
  supersedes the immutable 0.2.0 -- per packages' bump-and-re-file
  instruction).
- The double-implementation lesson above stands; the 0.2.1 merge
  branch `feat/pandas-0-2-1` is the canonical merge history.

**UPDATE 2026-10-20 19:20Z (PANDAS 0.2.1 PUBLISHED in eco-v0.1.201)**:
- **`xiom.pandas 0.2.1` LIVE** in **`eco-v0.1.201`** (sha256
  `4c0818716b72627824a1d1f84a0fab81c1b990edcaa179157c4e111ada3e6062`;
  18:18:17Z): merge `d81a7f39` resolved the pandas files to the
  BINDINGS superset; validate **584/0**; native x2 **164/164** @
  `7e92c250`; record `1d6d5678`; run 39473068474 green
  (published=1 failed=0); README/STATUS synced (`5ae9d6ae`).
  Supersedes the immutable 0.2.0 as agreed.
- The pandas request (`-1756`) AND the reconciliation item (`-1635`)
  are closed.  No new branches; pin v0.64.8.

**UPDATE 2026-10-20 21:05Z (relay-bus repair: owner -> engine note)**:
- An OWNER note to the **engine** lane arrived WITHOUT front matter
  (`items/REL-20261020-2355-owner.md`: "create a screenshots/ folder
  with a UI-progress jpg in xiom-engine; write status here and close
  this relay") and **crashed `relay.py view` for every lane**
  ("missing front matter").
- Repaired the file (valid front matter routing `owner -> engine` +
  the History section; owner text preserved verbatim) -> `relay.py
  validate` GREEN again (**827 items**); committed/pushed `c3402b5`.
  The action itself is the ENGINE lane's.

**UPDATE 2026-10-21 18:05Z (A14 UI platform ask ACCEPTED; sdl3 0.21.0
wave launched)**:
- Engine wishlist `REL-20261021-1652-engine-5` (**A14: UI platform
  surface for S5/S6**) ACCEPTED by function: window identity + position
  get/set + size-in-pixels + display scale + monitor for a window;
  per-window focus + DPI-change routing (display-changed /
  pixel-size-changed in the existing filter/watch model); text-input
  start/stop + typed IME composition/commit/cancel events; clipboard
  UTF-8 get/set/has + primary selection where the platform has it.
- **sdl3 A14 wave LAUNCHED** (`am-1792605630402-w0kzfl`; branch
  `feat/sdl3-a14-ui-platform`): additive-only on `xiom.sdl3 0.20.0` ->
  **0.21.0**; SDL3-backed (the ask's no-backend-mandate honored);
  suite x2 on v0.64.8; publish request follows on green.  Until then
  the engine keeps in-canvas floats/internal clipboard with the OS
  items SKIP-gated as stated.
- Context: the sibling landed `xiom.kafka 0.2.0` (real librdkafka,
  x2 50/50 live via mock cluster) + `xiom.charts 0.2.0` (x2 71/71;
  publish requested) the same day.

**UPDATE 2026-10-21 19:30Z (A14 sdl3 0.21.0 LANDED -- x2 81/81 LIVE)**:
- **`xiom.sdl3 0.21.0` LANDED** (land `17927884`; record `4bbe50f2`):
  A14 UI platform surface, additive-only on 0.20.0:
  - window identity + position get/set (120,90 witnessed) +
    size-in-pixels + display scale + display id/index/bounds for a
    window; display enumeration (count/name/bounds/usable/modes);
  - per-window focus + DPI-change routing through the filter/watch
    model (focus gained/lost + pixel/display/scale; watch route
    calls=8 in the suite);
  - IME text-input start/stop + area/cursor + typed
    preedit/commit/cancel decode;
  - clipboard UTF-8 set/has/get + primary selection set/has/get.
- Gate: **x2 81/81 LIVE** on the real SDL3 runtime (hidden window; all
  A14 paths exercised); validate **579/0**; pushed `4bbe50f2`.
- Publish request `REL-20261021-1923-bindings` (existing name; the A14
  ask `-1652-engine-5` is acked and this closes it on green publish).
  Engine UI2 S5/S6 consumes on LIVE.

**UPDATE 2026-10-22 10:35Z (sdl3 0.21.0 PUBLISHED in eco-v0.1.202 --
A14 CLOSED end-to-end)**:
- **`xiom.sdl3 0.21.0` LIVE** in **`eco-v0.1.202`** (sha256
  `8bb7e9eef607475c3485d1ffa8dba17e1e57ed7b096788af8cb7d230579ae6d2`;
  09:05:55Z): merge `261feec5` (sdl3-only wave; 10 files auto-merged);
  validate **585/0**; regen `5d2a0e9d`; native x2 **81/81** @
  `5d2a0e9d` (SDL3.dll present path); record `3322ac44`; wrap
  `0a20f96d`; run 39752275202 green.
- **A14 is CLOSED end-to-end**: engine wishlist `-1652-engine-5` ->
  accepted -> landed -> published; engine UI2 S5/S6 (cross-monitor
  DPI, OS tear-off/dock-back, clipboard/IME, accessibility host,
  Project Manager window) can consume on LIVE.

**UPDATE 2026-10-22 15:05Z (v0.64.9 released; bindings scratch
pre-verify GREEN)**:
- **v0.64.9 RELEASED** (owner GO 13:01Z; tag `2bcf58db5`; run
  39791522014 SUCCESS; 11 assets; stdlib-v0.64.9 stable; contents incl.
  m1157 BOM catalog, 2045 part 2 Str payloads, XVC-C-22 Vec inference,
  m1731 borrowed enum, m1703 stored fn values, m1326 enum equality,
  m1520 adapter substitution, m365 shared deps, 1511 port args, 1531
  dead-builder lock, m375 opt-in XIOM_FAST_EXIT).
- **Bindings scratch pre-verify on v0.64.9**: SHA256SUMS OK; nested-
  payload probe + matrix **failures=0**; vec-alias (B-34) witness
  compiles+runs (success shape); corrected B-29 witness **exact** --
  the lane is ready for a .9 repin.
- CAVEAT: other lanes are isolating **v0.64.9 archive blockers**
  (1451/1550 fails per relay 1410/1414; m372 release binary / tuple-
   returning 1550 gap).  **Repin stays with the owner/sibling wave**
  (bindings pin v0.64.8 until then); no unilateral bump, especially
  while the archive blockers are open.

**UPDATE 2026-10-22 16:15Z (REPIN v0.64.9 DONE -- owner go; slot +
records aligned; slot sanity GREEN)**:
- **Owner go received** ("new release out, continue"): the pinned slot
  `%LOCALAPPDATA%\xiom.new` was updated to **`XIOM Compiler v0.64.9`**
  from the release archive (SHA256SUMS verified); the previous .8 slot
  is kept as `%LOCALAPPDATA%\xiom.new.v0.64.8`.
- **Repin delta pushed** (`d75e8f2d`): `COMPILER_VERSION` v0.64.8 ->
  **v0.64.9** + **579 STATUS records aligned** (`status.ps1 -Action
  repin`); validate **579/0**.
- **SLOT SANITY MATRIX on .9** (via `XIOM_COMPILER` = the slot):
  **xiom.sqlite 21/21** (nested `Result[Option]` shape -- B-32 stays
  retired on the new pin), **xiom.sdl3 81/81 LIVE** (all A14 paths),
  **xiom.nvenc 67/67 LIVE** (driver 13.1 H.264/HEVC encode+decode) --
  **no .9 regressions** on the lane.
- Scratch pre-verify was already green (nested/matrix failures=0; B-34
  success shape; corrected B-29 exact).  The 1451/1550 archive issues
  other lanes are isolating do NOT reproduce in this lane's
  probes/suites.  Repin info filed to all lanes
  (`REL-20261022-1611-bindings`).

**UPDATE 2026-10-22 16:35Z (v0.64.9 HOLD -- REPIN REVERTED to v0.64.8)**:
- The orbitdb **HOLD** `REL-20261022-1501-orbitdb` (15:01Z, high) is
  decisive: the OFFICIAL .9 archives fail **1451** (m372 nested-generic
  ptr read: `nested=0 local=0` vs 42/42) and **1550** (tuple-returning
  enumerate: `em[1].0=0` vs 10) in the **release-mode codegen path**
  (debug passes; `--release` / explicit opt-level reproduces).  Adoption
  is held fleet-wide.
- My 16:15Z repin (on the owner "continue") was therefore **REVERTED**:
  pinned slot restored to **v0.64.8** from the kept backup (the `.9`
  archive is preserved at `%LOCALAPPDATA%\xiom.new.v0.64.9` for instant
  re-adoption); `COMPILER_VERSION` + all 579 STATUS records repinned
  back (validate **579/0**; sqlite sanity **21/21** on the restored
  slot); commit `f72877b9`.
- NOTE: the lane's `.9` slot runs WERE green (sqlite 21/21 nested, sdl3
  81/81, nvenc 67/67) and the 1451 class did not reproduce in our
  probes -- but **a held archive is not adopted**.  Re-adoption on the
  fixed re-cut (v0.64.10) or when the HOLD clears; the swap is one
  folder copy + repin + validate.
- HOLD acknowledgement filed `REL-20261022-1629-bindings`.
- **ENGINE INCIDENT noted** (`REL-20261022-1622-engine`): a recursive
  delete inside `C:\Users\lefte` erased config dirs
  (`.agents/.cargo/.android/.aws/.azure/.claude/.buskeeper/etc.`);
  engine UI/release work paused.  Bindings data is UNAFFECTED (E:
  workspace + AppData safe); adb keys regenerate; no lane action.

**UPDATE 2026-10-22 17:40Z (PIN RE-ALIGNED to v0.64.9 -- shared-slot
split-brain resolved)**:
- After the HOLD revert, the **SHARED machine slot**
  `%LOCALAPPDATA%\xiom.new` was **re-flipped to v0.64.9 by the fleet
  repin wave** (benchmark re-pinned `c4a05f0` with correctness
  acceptance green; engine verified C09 on .9).
- **Bindings re-aligned to the machine state** (`408a3e09`):
  `COMPILER_VERSION` + **579 STATUS records back to v0.64.9**;
  validate **579/0**; **sqlite sanity 21/21 ACROSS the flip** (ran on
  both the `.8`-restored and the `.9` slot).  The `.8` backup slot is
  retained (`%LOCALAPPDATA%\xiom.new.v0.64.8`) for a one-command swap
  if the HOLD escalates.
- HOLD (`-1501-orbitdb`: official .9 archives fail 1451/1550 in the
  release-mode codegen path) remains OPEN for the affected stdlib
  paths; it does **not** reproduce in this lane's probes/suites
  (nested payload, sqlite nested Row, sdl3 A14, nvenc all green on
  .9).  Correction note filed `REL-20261022-1738-bindings`.
- LESSON: the machine slot is SHARED state -- the lane pin must follow
  the slot (or coordinate a fleet revert); flipping only the local pin
  creates a split-brain.

**UPDATE 2026-10-22 19:10Z (v0.64.9 WITHDRAWN -- production v0.64.8
RESTORED)**:
- **v0.64.9 WITHDRAWN FROM ADOPTION** (`REL-20261022-1826-compiler`,
  18:26Z): post-release verification found **source-level codegen
  defects** the pre-cut battery missed (debug-only battery; no
  nested-pattern lock): nested enum patterns `Some(Number(n))` /
  `Ok(...)` / `Err(E.Bad(msg))` never check the inner variant and bind
  the payload as 0 (1243/1615/1645 + the 1451/1550 family); m372/1451
  and the true 1550 tuple shape regressed in `d04cd3265`
  (revert-only breaks m1520 -> safe guard required); m1511 one-level
  dependency port.args; C07 capture-probe memory red.  The GitHub
  release is marked pre-release (tag/assets remain for audit);
  **production remains v0.64.8**.
- **Lane reverted**: slot restored + verified `XIOM Compiler v0.64.8`
  (the withdrawn .9 slot copy kept for audit only, NOT adopted);
  `COMPILER_VERSION` + **579 records repinned**; validate **579/0**;
  sqlite sanity **21/21**; commit `314d27c8`.
- **v0.65.0 production gate OPENED** (`docs/RELEASE_GATE_v0.65.0.md`;
  P0 correctness -> P1 hardening -> P2 MCU first wave -> P3 cut; no
  candidate/tag before the gate is green + owner GO).  Lane holds: the
  .9 rows/records stay HELD (not green) as the v0.65.0 acceptance
  input -- re-test on the v0.65.0 archive.  `stdlib-v0.64.9` is
  published but is not the production pin (v0.65.0 will pin
  stdlib-v0.65.0).
- Host note (from the withdrawal): the engine incident deleted
  `~/.cargo`; cargo works via `.rustup` toolchains; restore the shims
  when needed.  Packages filed the .9 data-loss cluster (jev
  Err-in-Vec, openblas Vec-in-tuple, http Err(Enum) match) -- those are
  the acceptance probes.
- 2026-10-23T18:55Z (late-delivered doorbell; host slept since ~01:30Z): the
  compiler's **MCU/freestanding contract** item
  (`REL-20261023-0423-compiler`) was ACKED/coordinated: the
  host-companion trio is already landed with its publish DEFERRED (so
  "no publish before a target passes the QEMU job" holds by
  construction); the HAL family is not started and will honor
  `docs/MCU_FREESTANDING.md` (per-board `--linker-script` with
  `_estack`/`__heap_start`/`__heap_end` + Cortex-M .data/.bss, strong
  `xiom_panic`, replaceable bump allocator via bare_runtime.c, no
  exceptions/unwinding, no vendor peripheral emulation); packages
  re-test on the v0.65.0 archive as acceptance input.  Production pin
  remains v0.64.8 (pin+slot verified).

**UPDATE 2026-10-23 23:50Z (doorbell cycle -- v0.65.0 gate GREEN through
MCU QEMU; MCU publish request FILED; pause for the double-charge
window)**:
- **Doorbell re-armed then paused**: the `0 */3 * * *` cron was armed
  for this session and is now DISARMED per the owner (API doubles
  between 04:00 and 13:00 Greek time); a single wakeup is set for
  10:05Z (13:05 Greek) to resume + re-arm. Relay repo synced
  (`fetch --prune` + `merge --ff-only`), `relay.py validate` green
  (**927 items**); no open asks to bindings (the only new items are
  `REL-20261023-1815-ops` -> buskeeper and `REL-20261023-1854-pulse`
  -> compiler).
- **v0.65.0 gate: P0/P1/P2 GREEN; P3 cut in progress.** Owner GO was
  granted 2026-10-23T18:31Z (six minutes after the handoff). CI run
  **40003313859** is SUCCESS on head `a840e6d3e`, including the
  **`mcu-qemu`** job (thumbv6m microbit + riscv32imac virt), build/test,
  release-parity x2 and arm64 floor. `stdlib-v0.65.0` is tagged
  `3eb9c05` and pinned by the compiler (`a0dc452dc` drops the C07
  shim). Remaining before adoption: the all-platform dry-run + the
  `v0.65.0` tag + registry `xiom-std 0.65.0`. **No adoption yet** --
  production stays v0.64.8 (pin + slot verified via
  `%LOCALAPPDATA%\xiom.new\bin\xiom.exe` = `XIOM Compiler v0.64.8`).
- **MCU publish unblocked and FILED**: the QEMU precondition is met, so
  the combined request went out as **`REL-20261023-2344-bindings`**
  (bindings -> packages, high): firmata 0.1.0 + micropython 0.1.0 +
  uf2 0.1.0, 3 NEW names -> ops scopes; PROD-only; allowlist +
  verify-on-landing x2 + next eco batch. Relay commit `2d4bf80`.
  Fresh suites on the v0.64.8 slot, each **x2**: firmata **122/122**,
  micropython **19/19**, uf2 **62/62** (tree `daa47e56`); records
  updated with the run evidence.
- **epos**: refreshed **x2 29/29** on v0.64.8 (tree `daa47e56`);
  scope is LIVE @574, so it rides the same next packages batch;
  record updated. **charts 0.2.0**: already PUBLISHED 2026-10-21 as
  `xiom-charts/v0.2.0` (sha256 `7dddb907...`; registry verified;
  verify-on-landing x2 71/71) -- stale "publish pending" record text
  corrected.
- Lane validate after the record touches: **579/0**; no in-flight
  branch. Pause state: cron disarmed, wakeup `10:05Z`; on resume,
  re-arm the `0 */3 * * *` doorbell and re-check the v0.65.0 cut.
- **POSTSCRIPT 23:57Z -- v0.65.0 IS RELEASED** (`REL-20261023-2346-compiler`):
  tag `v0.65.0` (annotated `f527d5a`) on `a0dc452dc`; 11 assets +
  SHA256SUMS re-verified after publication; CI `40035344317` **7/7
  green** (incl. the MCU QEMU job); final dry-run `40035350921` all six
  package legs + VSIX green; full e2e **2646/2646** on debug and
  release; registry `xiom-std 0.65.0` live (sha256 `c3629878...`).
  The shared slot is still **v0.64.8** (verified), so there is no
  split-brain; adoption is deferred to the **10:05Z resume** per the
  owner pause. The relay release item is noted: bindings verifies the
  archive, swaps the slot with a versioned backup, repins/validates,
  runs slot sanity + the .9 acceptance probes, fills the
  `release-checks/compiler-v0.65.0.md` row, and closes the v0.64.9
  HOLD on resume. No v0.64.9 deployment.

**UPDATE 2026-10-24 00:52Z (v0.65.0 ADOPTED -- archive verified; P0 family
and .9 data-loss cluster GREEN; .9 HOLD closed)**:
- Official windows archive `ff4abb4a...` (SHA256SUMS match); slot swapped,
  the v0.64.8 slot kept as `xiom.new-v0.64.8-20261024`;
  `XIOM Compiler v0.65.0`; the 5 installed packages were preserved.
- `COMPILER_VERSION` + **579 records** = v0.65.0; validate **579/0**;
  commit `2ba10003`.
- Slot sanity: sqlite **21/21** nested, sdl3 **81/81**, nvenc **67/67**
  live.
- P0/.9 acceptance: m1615 nested enum payloads ok; m372/1451
  `nested=42 local=42`; true 1550 ok; m1827 Err(Str) `direct=direct
  via=via returned=returned`; Err(Enum) match ok; cross-module
  Vec-in-tuple ok; nested-payload `failures=0`; the B-34 witness runs
  (exit 1 = the documented fixed shape).
- MCU trio on the archive x2: firmata 122/122, micropython 19/19, uf2
  62/62; epos 29/29 x2; records updated.
- Release-check bindings verdicts filed; `REL-20261022-1945-bindings`
  closed (.9 HOLD CLOSED); release item noted. No v0.64.9 deployment.
- Caveat: `%LOCALAPPDATA%\xiom.new` disappeared during the swap (a
  concurrent slot operation); recovered from the pre-swap backup +
  the verified archive. Slot is now v0.65.0; no split-brain.

**UPDATE 2026-10-24 10:10Z (doorbell -- MCU ack; scope re-filed; lane quiet)**:
- Doorbell re-armed (`0 */3 * * *`, next 12:00Z). Relay synced
  (fetch + ff, **930 items**, validate green). Slot + pin still
  **v0.65.0** (no split-brain); lane validate **579/0**.
- **MCU publish**: packages ACKED `REL-20261023-2344-bindings` and
  re-filed the PROD-only scope ask as **`REL-20261024-0020-packages`**
  (ops OPEN). Packages re-verified the trio x2 on the v0.65.0 archive
  (firmata 122/122, micropython 19/19, uf2 62/62). Publish executes on
  ops LIVE: allowlist + 3 single tags + sha verification + sync.
  No bindings action until the LIVE relay-back.
- **epos**: still scope LIVE @574, rides the same batch; no reply yet.
- No other open asks to bindings (new relay traffic is packages/ops/
  compiler release bookkeeping). Next doorbell 12:00Z.

**UPDATE 2026-10-24 18:05Z (doorbell -- relay hygiene; lane quiet)**:
- Relay sync: the new items are other-lane bookkeeping, but
  `relay.py validate` went **RED** on `REL-20261024-1501-orbitdb`
  (a stray U+FEFF BOM at the body start). Repaired by stripping the
  BOM (content unchanged); validate **934 items green**; relay commit
  `a5f61f0`.
- Slot + pin still **v0.65.0**; lane clean, validate unchanged. MCU
  scope `REL-20261024-0020-packages` still **OPEN** with ops; epos
  unchanged; no new asks to bindings.

**UPDATE 2026-10-25 14:55Z (MCU Phase-1 PUBLISHED; epos request filed)**:
- **MCU trio LIVE**: `xiom.firmata 0.1.0` sha256 `15223e05...`,
  `xiom.micropython 0.1.0` sha256 `c25c2014...`,
  `xiom.uf2 0.1.0` sha256 `065b895c...`; allowlist **576 -> 579**;
  registry live-verified; runs 40200865535 / 40200865254 / 40200865200;
  docs sync `ca5168ba`; scope LIVE 13:27Z (eco-release 575 -> 578).
  The three STATUS records now carry the live shas; the request item
  `REL-20261023-2344-bindings` is closed as delivered.
- **epos 0.1.0** publish request filed as
  **`REL-20261025-1453-bindings`** (bindings -> packages, high); the
  scope has been LIVE @574 since 2026-10-19 and the suite is 29/29 x2
  on v0.65.0; the MCU batch shipped without it. This is now the only
  bindings package awaiting publish.
- Relay validate green (935 items); pin + slot **v0.65.0**; lane
  validate **579/0**.

**UPDATE 2026-10-26 19:05Z (epos confirmed LIVE -- no bindings publishes
pending)**:
- `xiom.epos 0.1.0` is LIVE on the registry since 2026-10-21 (single
  tag `xiom-epos/v0.1.0`, sha256 `b5a565de...`; registry latest 0.1.0;
  allowlist entry present). The 2026-10-25 publish request
  (`REL-20261025-1453-bindings`) was closed as a **duplicate** by
  packages -- its premise (no registry entry) was stale. The epos
  STATUS record is corrected to published; suite re-verified 29/29 x2
  on v0.65.0.
- **No bindings publishes remain pending**: the MCU trio went live
  2026-10-25 and epos was already live.
- Relay validate green (**961 items**); pin + slot **v0.65.0**; lane
  validate **579/0**. Watch item: stdlib 0.65.1 is live (compiler
  `v0.64.8` field) -- it does not change the compiler pin; v0.65.0
  stays production until a compiler release passes its gate + owner GO.

**UPDATE 2026-10-26 20:10Z (v0.65.1 ADOPTED -- slot moved to
`%LOCALAPPDATA%\xiom`; owns_return leak gate green)**:
- v0.65.1 is PRODUCTION (owner GO; `docs/RELEASE_GATE_v0.65.1.md`).
  Tag `v0.65.1` (annotated `c4329915`) on `f2c01cf9c`; release run
  40388025015 with 11 assets + SHA256SUMS (windows zip `69de1e27...`);
  CI 40385480182; dry-run 40387243828; e2e 2647/2647; registry
  `xiom-std 0.65.1` signed.
- **Slot convention changed by the fleet**: PATH + the installer now use
  `%LOCALAPPDATA%\xiom` (proper bin/lib v0.65.1). The fleet swap briefly
  flattened `%LOCALAPPDATA%\xiom.new` and wiped the shared package store;
  both were repaired -- both roots now report v0.65.1 and the store is
  restored to 11 packages (incl. sdl3 0.21.0, stb, vulkan, harfbuzz,
  fontraster 0.1.1). The old versioned slot backups were removed by that
  swap. The lane resolver uses `xiom` (verified `XIOM Compiler v0.65.1`);
  `COMPILER_VERSION` + **579 records** = v0.65.1; validate **579/0**.
- Archive verified independently: windows zip checksum match; lib
  `package.xi` 0.65.1; C07 helper + freestanding present.
- Slot sanity: sqlite **21/21** nested, sdl3 **81/81**, nvenc **67/67**
  live.
- Acceptance: m1615 ok; m372/1451 `nested=42 local=42`; true 1550 ok;
  m1520 ok; m1827 Err(Str) ok, Err(Enum) ok, Vec-in-tuple ok;
  nested-payload `failures=0`; B-34 witness exit 1 (fixed shape);
  enum-payload `bad=0`; **new `ffi_owns_return_leak` gate exit 0**.
- Published packages re-verified x2 on v0.65.1: firmata 122/122,
  micropython 19/19, uf2 62/62, epos 29/29; records updated.
- Bindings verdicts filed in `compiler-compiler-v0.65.1.md`.

**UPDATE 2026-10-27 19:15Z (doorbell -- `%LOCALAPPDATA%\xiom` left
partial; resolver fell through to unreleased 0.65.2; repaired)**:
- A concurrent install/swap left `%LOCALAPPDATA%\xiom` with only
  `bin\{vcruntime140.dll,xiom-lsp.exe}` and no `lib`. With no valid
  installed candidate, `scripts\xiom.ps1 -Info` fell through to
  `E:\xiom-lang\xiom\target\release\xiom.exe` = **0.65.2
  (repo-release)** while the pin was v0.65.1 -- an unreleased local
  build. No suites were run in that state.
- Repaired in place from `%LOCALAPPDATA%\xiom.new` (v0.65.1;
  `lib/package.xi` 0.65.1), package store preserved (11); the running
  `xiom-lsp.exe` + its `vcruntime140.dll` were left alone. Resolver now
  reports **0.65.1 (installed)**.
- Full verified copy kept at
  `%LOCALAPPDATA%\xiom-v0.65.1-verified-20261027`; fleet info item
  filed for the fallback hazard (`REL-20261027-1901-bindings`).
- Relay green (981 before this note); pin + 579 records = v0.65.1;
  lane validate 579/0.

**UPDATE 2026-10-27 20:05Z (v0.65.2 ADOPTED -- slot repaired again;
packed Vec slots + borrow/aggregate reclaim)**:
- v0.65.2 is PRODUCTION (`REL-20261027-1919-compiler`). Annotated tag
  `v0.65.2` (`fe1994b1`) on `8ec0904a5`; release 40566604850 with 11
  assets + SHA256SUMS (windows-x64 `0a328560...`); CI 40559690805;
  dry-run 40559700656; e2e 2649/2649; `stdlib-v0.65.2`; registry
  `xiom-std 0.65.2` (`9638b576...`).
- The v0.65.2 cut left `%LOCALAPPDATA%\xiom` **partial again** (bin
  only, no lib), so the resolver fell through to the repo-release
  WIP build. Installed v0.65.2 from the checksum-verified archive into
  the canonical slot (bin/lib; store preserved), then the packages lane
  rebuilt both roots and restored the store to 17 dirs. Resolver now:
  **0.65.2 (installed)**.
- `COMPILER_VERSION` + **579 records** = v0.65.2; validate **579/0**.
- Slot sanity: sqlite **21/21** nested, sdl3 **81/81**, nvenc **67/67**.
- Acceptance: m1615 ok; m372/1451 `nested=42 local=42`; true 1550 ok;
  m1520 ok; m1827 Err(Str)/Err(Enum)/Vec-in-tuple ok; nested-payload
  `failures=0`; B-34 witness exit 1 (fixed); enum-payload `bad=0`;
  `ffi_owns_return_leak` exit 0; **m1731 borrowed-enum
  `s=borrowed-world` ok** (new reclaim path).
- Published packages re-verified x2 on v0.65.2: firmata 122/122,
  micropython 19/19, uf2 62/62, epos 29/29; records updated.
- Bindings verdicts filed in `compiler-compiler-v0.65.2.md`; the
  orbitdb partial-slot item is fixed; the engine non-ASCII relay item
  was repaired (validate green).

**UPDATE 2026-10-27 21:20Z (wishlist work -- imgui 0.4.0 SDL3+Vulkan
backends DELIVERED)**:
- `xiom.imgui 0.4.0`: vendored `imgui_impl_sdl3` + `imgui_impl_vulkan`
  (v1.92.9b) together with the SDL3 3.4.8 and Vulkan-Headers 1.4.350
  header trees and the `SDL3.lib`/`vulkan-1.lib` import libs from Vulkan
  SDK 1.4.350.0 (licenses vendored). Engine-owned backend registry: SDL3
  platform attach (engine `SDL_Window` + event forwarding), Vulkan
  renderer attach (engine instance/device/queue/descriptor pool/render
  pass), frame/draw-data/render/shutdown. Missing handles reject typed;
  dynamic rendering is the follow-up.
- Conformance **11/11 x2** on v0.65.2 (`8bf3e185`), including the real
  SDL3 hidden-window selftest (202 vertices / 327 indices / 1 cmd list)
  and the Vulkan missing-handle guard. Build is self-contained
  (`--cxx-standard 17 --link-path vendor/lib --link SDL3 --link
  vulkan-1`); the only mechanical vendored edit is include normalization
  (the link line has no `-I` passthrough). Docs updated: `package.xi`
  0.4.0, SPEC provenance/interop, README, AUDIT, ROADMAP.
- Publish request **`REL-20261027-2116-bindings`** (existing name; 0.4.0,
  single tag `xiom-imgui/v0.4.0`, next eco batch). Wishlist
  `REL-20261012-2012-engine-4` is **fixed**; engine can verify.
- Remaining wishlist `REL-20261012-2012-engine-2` (mini-RHI compute/
  indirect/timestamps/labels wrapper): the raw surface is 100% at
  `xiom.vulkan 0.6.0` and the engine-facing wrapper was routed to the
  OWNER mini-RHI extended wave (`REL-20261016-1341-engine-3` /
  `-1347-bindings`), so no bindings work is outstanding; the item stays
  acked with that routing on record.
- Relay validate green (999); lane validate 579/0.

**UPDATE 2026-10-28 01:05Z (imgui 0.4.0 publish BLOCKED by pack policy;
policy ask filed; v0.65.2 durable advisory noted)**:
- The tag workflow built and verified imgui 0.4.0 (11/11 x2 on v0.65.1)
  but `xiom-pkg` refused the two vendored import libs at pack time
  (`vendor/lib/SDL3.lib`, `vendor/lib/vulkan-1.lib`; run 40602199852).
  The tag was deleted; the publish is blocked on a pack-policy decision.
- Acked `REL-20261027-2329-packages` and filed
  **`REL-20261028-0101-bindings`** (bindings -> packages, high) with the
  exact SHA256 pins and three options: (a) a pack-policy/asset exception
  for exactly those two pinned `.lib` files (preferred), (b) an
  `xiom-pkg` manifest intentional-binary field, (c) remove the libs and
  link the system Vulkan SDK 1.4.350.0 on the tag runner. No code change
  until the path is chosen; re-tag after a green pack.
- Advisory: v0.65.2 has a durable/vector-lane `Vec[Struct]` push
  regression (compiler hotfix `bb8eccf5a`; v0.65.3 awaits owner GO).
  Bindings packages passed on v0.65.2 and the imgui publish used
  v0.65.1; the lane stays on the shared v0.65.2 slot (no split-brain)
  and will re-verify on v0.65.3 when released.
- Relay validate green; lane validate 579/0.

**UPDATE 2026-10-28 16:05Z (imgui pack policy -- option (a) chosen;
awaiting owner sign-off)**:
- Packages position on `REL-20261028-0101-bindings`: **option (a)** is
  the correct fix; option (c) is rejected (it drops the no-system-SDK
  property and the tag runner cannot guarantee SDL3). Packages will
  implement a narrow, auditable force-allowlist in the publish workflow
  -- only `xiom.imgui`, only `vendor/lib/SDL3.lib` +
  `vendor/lib/vulkan-1.lib`, both hashes asserted -- but it changes CI
  pack policy and needs **owner sign-off**.
- **Do not re-tag `xiom-imgui/v0.4.0` until that lands**; packages will
  message when the workflow is ready. In-tree evidence remains 11/11 x2.
- Relay validate green (1017); toolchain v0.65.2 installed; lane clean.

**UPDATE 2026-10-17 14:45Z (NVIDIA backlog -> EXECUTION -- 7 agents; AMD
stays hardware-gated; DirectML exception in flight)**: owner go.
- Launched (`am-1792248023196-fjuh2d`): `feat/cuda-math`
  (cublas+cufft+cusparse; pip math wheels; live on the host RTX 3070
  Ti), `feat/cudnn`, `feat/tensorrt`, `feat/nvenc` (NVENC+NVDEC via
  nv-codec-headers MIT), `feat/nvml-nvapi` (driver-present DLLs ->
  fully live-testable), `feat/optix` (SDK fetch attempt; else loader +
  SKIP + acquisition contract), `feat/onnx-directml` (vendor-neutral
  accelerator leg -- the one "accelerator extras" item testable on this
  box; extends the published xiom.onnx additively).
- Protocol: loader-only for closed/driver SDKs (nothing vendored; NVIDIA
  EULA runtime user-supplied; reference headers pinned), live legs on the
  host GPU where obtainable, SKIP-safe everywhere; v0.64.6 pin; x2
  suites; origin/bindings base; path-scoped landing.
- **AMD**: hip/rocblas/miopen/amf/ags/NPU stay BACKLOG until an AMD card
  exists for live legs -- no hardware-free path; the only exception
  (DirectML) is in flight now and validated on the NVIDIA GPU.

**UPDATE 2026-10-17 13:15Z (GPU VENDOR BACKLOG -- AMD + NVIDIA added)**:
owner asked to backlog both vendor sets (on top of the accelerator-extras
line in `-1254-bindings`).
- **AMD -- landed in-tree, green, unpublished (publish on consumption)**:
  `xiom.fidelityfx` 0.1.0 (FidelityFX SDK 2.3.0: FSR2/FSR3 + frame gen;
  43/43 x2 + 35/35 SKIP), `xiom.rpr` 0.1.0 (Radeon ProRender 3.1.7.1;
  35/35 x2 + 9/9 SKIP).
- **AMD -- backlog (not yet launched, on request)**: `xiom.hip` (HIP
  SDK/ROCm runtime loader; MIT), `xiom.rocblas`/`xiom.miopen`
  (+hipBLASLt on demand), `xiom.amf` (AMF hardware codec SDK; MIT),
  `xiom.ags` (GPU services; optional), Ryzen AI/XDNA NPU (on demand).
- **NVIDIA -- published**: `xiom.cuda` 0.2.0 (driver API; live RTX 3070
  Ti; eco-v0.1.126).
- **NVIDIA -- landed in-tree, green, unpublished (publish on
  consumption)**: `xiom.dlss` 0.1.0 (NGX; 21), `xiom.nrd` 0.1.0 (29),
  `xiom.rtxdi` 0.1.0 (RTXDI+RTXGI; 33).
- **NVIDIA -- backlog (not yet launched, on request)**: `xiom.cudnn`,
  `xiom.cublas` (+cufft/cusparse on demand), `xiom.tensorrt`,
  `xiom.nvenc` (Video Codec SDK: NVENC/NVDEC), `xiom.nvml` +
  `xiom.nvapi` (utils/telemetry), OptiX (optional ray tracing).
- **Shared**: DirectML execution-provider leg for `xiom.onnx`
  (vendor-neutral Windows GPU ML path across AMD/NVIDIA/Intel).
- Rule: accelerators stay loader-only (closed/driver SDKs user-supplied,
  nothing vendored; SKIP-safe; live legs need the hardware).

**UPDATE 2026-10-17 12:20Z (remaining builds LAUNCHED -- openblas real
accel + arrow real backend; USD prep in flight)**: acting on the
doorbell's own remaining-queue list.
- **`feat/openblas-real`**: Phase-1 real-acceleration remainder
  (ROADMAP unchecked set: real linked-OpenBLAS leg, cblas_* wiring via
  raw pointers, real LAPACK, workspace query, numerical verification;
  SKIP leg retained; official BSD-3 Windows build into E:\repos).
- **`feat/arrow-real-backend`**: `xiom.arrow` real backend per
  `xiom-pandas/bridge/REAL-BACKEND-REQUIREMENTS.md` (true ArrowArray/
  ArrowSchema structs + zero-copy export/import + ownership doc; the
  C++ pandas bridge prepared with an honest MSVC/ABI-gate note; 12-symbol
  ABI untouched; section-6 owner decisions flagged).
- Request `am-1792239272393-43e1df`; USD prep (`feat/usd-import`) in
  flight from 12:11Z.  Remaining queue now: epos publish request
  (hardware-gate), numpy grant (packages/ops), v0.64.7 re-verify rows,
  llm/jev/pandas items (packages half), Pi smoke (arm64 release),
  extras on demand.

**UPDATE 2026-10-17 12:10Z (all remainings pass -- eco .194 verified on
our side; stubs swept; USD prep LAUNCHED)**: continuation after the
morning sweep.
- **`eco-v0.1.194` verified**: torch/libtorch/tensorflow/blas/gps all
  registry live-verified (allowlist 559->561; guard 561/552/9/0);
  M2 request `-0042-bindings-2` + gps `-2144-bindings-2` both FIXED.
- **Worktree stubs swept**: sessionless `android/a12-sys` worktree +
  branch removed; `android/a3-a4` + `feat/sqlite-nested-restore-2`
  were already cleaned earlier; orphan dirs remain file-locked (OS
  handles; retry later).  68 live worktrees remain (idle sessions).
- **USD importer (import campaign) -- PREP LAUNCHED**: `feat/usd-import`
  (`am-1792238631823-at8f8f`): OpenUSD sparse light clone at pin,
  license/provenance first, usd-core wheel as the policy-clean loader
  leg, staged scenes/materials surface, v0.64.6 pin, x2 suites.
- Remaining after this: v0.64.7 wave (B-29/B-32/B-33/B-34/XVC-C-18),
  Pi/edge smoke (waits arm64 target release), accelerator extras (on
  demand), M1/M3 (packages half).

**UPDATE 2026-10-17 11:58Z (branch pin bump DONE -- COMPILER_VERSION
v0.64.6 + 566 records repinned; morning state)**: closes the 00:45Z
MORNING TODO.
- **`COMPILER_VERSION` -> v0.64.6** (matches the published stdlib 0.64.6
  and main's repin `ec548542`); `status.ps1 -Action repin` updated all
  **566** records (run totals/commits preserved); validate **566/0**.
- Morning state: miniaudio 0.5.0 PUBLISHED; M2 wave (torch/libtorch/
  tensorflow/blas + openblas fix) merged to main; gps + libtorch scopes
  LIVE (560); M2 publish in flight with packages; B-34 acked (v0.64.7
  batch).  Relay inbox zero (the stdlib 0.64.6 announcement is
  to-all -- the bus correctly refuses other-lane moves).

**UPDATE 2026-10-16 23:30Z (miniaudio 0.5.0 handle surface LANDED --
engine ask delivered; merge+publish relayed; wave parked overnight)**:
owner asked for the delivery + merge relay, then pause.
- **`xiom.miniaudio 0.5.0` LANDED**: land `c4000ba4` (path-scoped from
  `feat/miniaudio-handle` @ `e17a8ce3`), record re-pointed (44/44 x2 on
  **v0.64.6**; 27 -> 44 tests; handle battery: 4-slot registry, live
  render swaps, typed STATE/BAD_HANDLE/EXHAUSTED/NO_CONTEXT, clean
  teardown; live WASAPI/auto legs).  Delivers engine ask
  `REL-20261016-2139-packages-2` (fold of `-2134-engine-2`).
- **Merge+publish relayed to packages**: `REL-20261016-2324-bindings`
  (0.5.0 publish request + merge cue; existing name, allowlist path).
- **Queue wave parked**: torch-libtorch / tensorflow-coverage /
  blas-fold branches are mid-flight (sessions offline with the owner
  away); they resume + land next window, publish requests follow.
- validate 566/0 post-landing; relay validate green (686 items).

**UPDATE 2026-10-16 22:40Z (queue execution wave LAUNCHED -- 4 agents;
category sweep completed)**: acted on every accepted/queued bindings
item; no open relay items were pending.
- **`-2139-packages-2` (engine audio, miniaudio handle surface)** ->
  EXECUTION launched: `feat/miniaudio-handle` (open once ->
  callbacks/streams over time -> close, alongside the lifecycle bridge,
  0.4.x/0.5).
- **ML program remainder (`-1917-packages-3` queue)** -> EXECUTION
  launched: `feat/torch-libtorch` (xiom.libtorch + xiom.torch -> 100%
  coverage, pytorch BSD-3 sparse clone); `feat/tensorflow-coverage`
  (TF C API, Apache-2.0 sparse clone); `feat/blas-fold` (safe-linalg
  build-out -- openblas LIVE in .193 unblocks the parked fold).
  Request `am-1792190033460-61atj4`; all with the light-clone protocol,
  v0.64.5 pin, x2 suites, origin/bindings base, path-scoped landings.
- Category vocabulary now 100% clean: kv storage -> database; lz4
  compression -> data; raylib gamedev -> media; slang tools -> tooling
  (on top of the 9-manifest family fix `8c9493c1`); validate 566/0.
- Standing context: publishes with packages (gps -2144-2 open;
  serial/ros2/v4l/onnx live .193); v0.64.6 repin owner-gated (still on
  the v0.64.5 slot).

**UPDATE 2026-10-16 22:30Z (relay sweep -- category vocabulary fix;
gps request already out; audio fold confirmed)**: sweep + fix pass.
- **`-2220-packages` processed**: `.193` noted (serial/ros2/v4l/onnx
  live; sha256s listed); **gps publish request was already filed**
  (`REL-20261016-2144-bindings-2`, open -- awaiting packages ack); the
  requested **v4l category fix applied**, plus the same-bug siblings:
  **9 family manifests** moved to the controlled vocabulary
  (v4l/camera2ndk/mediandk/aaudio/opensl -> `["media","systems"]`;
  android/android-sys/jni/epos -> `["systems"]`).  Remaining
  out-of-vocabulary values flagged for future touches (not fixed
  now): `xiom-kv -> storage`, `xiom-lz4 -> compression`,
  `xiom-raylib -> gamedev`, `xiom-slang -> tools`.  validate **566/0**
  after the fix.
- Engine audio ask confirmed ours: `-2139-packages-2` (miniaudio
  long-lived handle surface) accepted -> next miniaudio wave; engine
  keeps the null-tier fallback meanwhile.
- No other open relay items addressed to bindings.

**UPDATE 2026-10-16 19:25Z (ML/AI + robotics program -- acked + queue
folded; 20 built names confirmed)**: owner directive (19:16Z) relayed by
packages; handled this pass.
- **`-1917-packages-3` acked + replied** (`REL-20261016-1921-bindings`;
  relay `794063b`): bindings half CONFIRMED against tip `2ba5854d` --
  **13 fleet names** (gpio/i2c/spi/adc/pwm/sensor/can/ble/zigbee/hid/usb
  + modbus + mqtt; all present in both trees, 0.1.3 line) + **7 in-tree
  ML/ros2 bodies** (blas/openblas/libtorch/torch/tensorflow/onnx 0.1.0,
  ros2 0.1.0) = **20 built names** (matches the bulk scope queue);
  serial/v4l/gps/epos = new work; no name/ownership corrections.
- **QUEUE FOLDED** (agents pick directly): R1 fleet publish (packages
  pipeline) -> R2 serial/v4l/gps/epos/ros2 (**serial FIRST**) -> M1
  foundation -> M2 runtimes (**onnx FIRST**; previously parked on the
  native-lane go-ahead -- now unblocked) -> M3 LLM runner.  Clone
  protocol: light `--depth 1`, license first, pin in PROVENANCE.
- Live context: family **7/8 in `eco-v0.1.192`** (android 0.4.0 on the
  ops legacy re-grant); v0.64.6 cut gate green (B-32 re-verify paths
  pinned); no open relay items after this pass.

**UPDATE 2026-10-16 19:35Z (ML/AI + robotics parallel wave LAUNCHED -- 6
agents; light-clone protocol; first picks serial + onnx)**: owner go
("start in parallel agents") -- requested 6 Agent Manager worktree
sessions (`am-1792178818502-r7skkf`):
- `feat/serial-binding` (**first pick**) -- xiom.serial UART core;
  `feat/onnx-coverage` (**first pick**) -- xiom.onnx 0.1.0 -> full C-API
  coverage + delivery (native-lane unblock); `feat/v4l-binding` --
  xiom.v4l V4L2 UAPI; `feat/gps-binding` -- xiom.gps gpsd-JSON + NMEA
  (pure-XIOM preferred); `feat/epos-binding` -- xiom.epos closed-SDK
  loader; `feat/ros2-coverage` -- xiom.ros2 rcl C surface completion.
- Protocol in every brief: LIGHT clones (`--depth 1`, no history) into
  `E:\repos\<name>`; license check first (MIT-or-compatible; closed ->
  loader pattern, nothing vendored); commit pinned in PROVENANCE; 100%
  declared-surface coverage; v0.64.5 pin; suite x2; path-scoped landing;
  start from origin/bindings.
- Landings via the standing recipe as branches go green; R1 fleet
  publish + android 0.4.0 re-grant remain with packages/ops.

**UPDATE 2026-10-16 13:10Z (live pass -- OPS SCOPES LIVE; android family
first-publish requested; brotli scope ask open)**: fresh pass on the live
state (`cdbbca63`; clean + pushed; validate 561/0).
- **Ops scope queue LIVE** (ops `f383c39`; registry restarted healthy
  12:58Z; eco-release **550**): production set verified for **transport +
  otel + the five android names + `xiom.ssl`**; `xiom.brotli` NOT yet
  present.  PULSE provenance (`REL-20261015-2137`) fixed + re-verified
  live.  Unblocks: packages transport/otel wrap (`.188`), the ssl publish
  path, and the family's five new names.
- **Android family first-publish requested**: `REL-20261016-1305-bindings`
  (`xiom.android` 0.3.0 + aaudio/mediandk/camera2ndk/android-sys/opensl
  0.1.0; docs/repro evidence per package; A3/A4 -> 0.4.0 follow-up noted;
  batching choice left to packages).
- **`xiom.brotli` scope ask already OPEN with ops** (`-1302-packages` +
  `-1302-packages-2`, filed 13:02Z; stacks with the ssl batch) -- no
  duplicate filed; watch for the fix before the `-1220-bindings` publish.
- `REL-20261016-1304-packages` (to all): xiom.http 0.1.7 bump rider for
  the brotli+ssl batch; our pass had cleared (clean + pushed), so the
  packages coverage session owns the bump per the note's fallback -- no
  bindings-side write taken.
- A3/A4 session still busy (`android/input-sensors`; compiling); no
  unprocessed to-bindings relay items; next doorbell 15:00Z (continuation
  cron).  Relay tip after this pass: `9446ed9`.

**UPDATE 2026-10-16 13:55Z (relay check -- USD wishlist accepted + queued;
A9/A11/A12 in flight; batch 90 live)**: sweep after the A3/A4 landing burst.
- **`REL-20261016-1346-packages-2`** (engine import campaign -- USD/
  openusd-class importer, routed by packages) -- **ACCEPTED + queued**:
  assimp-class treatment (upstream-first clone at pin; PROVENANCE/AUDIT;
  suite x2); slot after the in-flight Android remainder; no timeline
  commitment (engine noted none).  Acked; reply filed
  (`REL-20261016-1350-bindings`; relay `7dee615`).
- Wave: **A9 gl / A11 jni / A12 sys sessions all BUSY** (launched
  13:27-13:40Z; stale sessionless stubs `android/a3-a4` +
  `android/a12-sys` await cleanup once their sessions are confirmed dead).
- Eco: **batch 90 LIVE -- `eco-v0.1.188`** (transport 0.1.0 + otel 0.1.0;
  allowlist 543->545; ops PROD-only 550); xiom.http 0.1.7 rider applied by
  packages (`3489b7d0`); family publish riding the 0.4.0 supersede
  (`-1322-bindings`); brotli scope still open with ops (`-1302`).
- No other unprocessed to-bindings items; doorbell next 15:00Z.

**UPDATE 2026-10-16 14:05Z (relay check + WAVE FREEZE observed -- all
managed sessions offline; A9/A12 frozen mid-rebase)**: relay verified
clean; the wave hit an environment-level disconnect.
- Relay: engine batch all handled (transport-ext -> packages answered;
  USD accepted by us `-1350` + ack; Vulkan answered `-1347` -- awaiting
  engine's ack, their move).  No open items from engine for bindings;
  no new to-bindings items (only the to-all http rider `-1304`).
  Family publish still with packages (`-1322` refs `-1305`); brotli
  scope open with ops (`-1302` pair).
- **FREEZE (observed 14:00-14:05Z)**: every Agent Manager session reports
  `offline` (extension answers; sessions detached) -- including the
  continuation, so the doorbell is dark until it re-attaches.  Wave
  worktree state at the freeze:
  - **A11 jni: DONE + pushed** (`android/a11-jni` @ `07cad93b`; xiom-jni
    0.1.0 seam + bitmap, suite 89/89 x2 recorded; clean) -- ready to land
    path-scoped.
  - **A9 gl leg: frozen mid-interactive-rebase** (detached @ a92edf2a;
    onto 474cd291; 103/300 done; 0 unmerged at the freeze).
  - **A12 sys: frozen mid-interactive-rebase** (detached @ 7556d92f;
    onto 2a163255; 106/301 done; 1 unmerged -- docs/PACKAGE_STATUS.md).
  - Sessionless stubs `android/a3-a4` + `android/a12-sys` remain.
- Recovery notes for the next pass: re-attach the sessions first; A11
  lands (validate + record); A9/A12 either finish the rebase in-session
  or ABORT and land their package dirs path-scoped per the standing
  recipe (never wholesale).  Main worktree untouched by the freeze:
  clean at `52c23263`.

**UPDATE 2026-10-16 11:05Z (MORNING PASS -- ALL 8 WAVES LANDED; lane
PAUSED per owner directive)**:
- Remaining 3 branches landed (path-scoped; trees safety-verified to
  include current content): **`xiom.android 0.3.0`** (W2c A2: looper 9
  + native_activity 5 + configuration 50; export set 53->117; ALooper
  pipe/addFd/pollOnce on-device proof; native_app_glue closure check)
  `17ef7223`; **`xiom.box2d 0.4.0`** (A02 caller solver: world/bodies/
  step/state/raycast/overlap/contacts/joints) `d19090cc`;
  **`xiom.miniaudio 0.4.0`** (A04: device/engine/node-graph/capture/
  streamed decode) `c11b7ac2`.
- **Integration gates re-run on the landed state (all GREEN)**:
  xiom.android **8/8**; xiom.box2d **26/26** (raycast f=375; contacts
  begin/hit/end; weld/distance/wheel/motor); xiom.miniaudio **27/27**
  live WASAPI (mix-pull 5280 frames; engine lifecycle; graph mixes
  exact 0.375/0.25/0.375; capture 2400 frames; WAV/FLAC sample-exact +
  MP3) -- recorded `4247d3da`.
- **All 8 waves of this session are landed**: 6 Android units
  (xiom.android 0.3.0 + camera2ndk + aaudio + mediandk + android-sys +
  opensl) + box2d 0.4.0 + miniaudio 0.4.0; validate **559/0**.
- **PAUSED per owner directive** (land waves -> pause -> relay watch).
  Overnight main-session work queued two accepted high asks for a
  FUTURE wave: **TLS context binding** (`REL-20261015-2211-packages`;
  libssl-class loader composing with xiom.tls + xiom.openssl crypto)
  and **real brotli RFC 7932** (`-2211-packages-2`; libbrotli);
  `-2302` deduped into them. Android remaining: A3/A4 input+sensors,
  A9 gl leg, A11 JNI seam, A12 remainder; publishes gated on the G3
  token reply.
- Eco: `.185` live (glfw 0.6.0 + sdl3 0.20.0); `.186` armed (transport
  + otel + template; ops gate).

**UPDATE 2026-10-15 23:00Z (WAVE-2 LANDING PASS 1 -- 5 of 8 landed;
overnight watch armed)**:
- **LANDED**: `xiom.camera2ndk` (merge `ae7a72c3`; 70-export surface,
  ids 1/10 on-device), `xiom.aaudio` (`30951220`; 67 exports, OPEN->
  STARTED->close live), `xiom.mediandk` (`37c3b459`; 276 exports +
  MediaFormat fidelity), `xiom.android-sys` (`612f08dd`; logcat proof +
  EBADF path), `xiom.opensl` (`ae64c16e`; 114-symbol set + engine
  lifecycle) -- the four NEW packages landed **path-scoped**
  (`git checkout <branch> -- packages/<dir>`) because agent branches
  were seeded from **divergent bases** (wholesale merges conflict on
  old STATUS.json histories); validate after landing: **559 packages,
  0 errors**.
- **STILL IN FLIGHT**: `android/w2c-lifecycle` (0 commits, idle --
  nudged; will land via rebase request since it EDITS `xiom.android`),
  `box2d/a02-growth` + `miniaudio/a04-growth` (busy; bases near-tip ->
  normal merge expected).
- **Overnight watch**: doorbell cron rewritten as a combined pass
  (agent-landing with the path-scoped/no-wholesale-merge recipe +
  rebase requests for existing-package edits + relay items +
  SESSION.md eco notes). Owner directive: land everything, then pause
  and keep eyes on relay.
- Side intel (from branch inspection): the main session already
  published our lifts -- **eco-v0.1.185 live with glfw 0.6.0 +
  sdl3 0.20.0** (101 releases; redis live in `.184`).

**UPDATE 2026-10-15 22:35Z (A02 + A04 LAUNCHED in parallel -- 8 agents
in flight)** per the owner's go-parallel directive; the two queued
engine asks now run alongside the 6 Android sessions (all disjoint
packages):
- `box2d/a02-growth` -- xiom.box2d 0.3.0 -> 0.4.0 (A02): world/bodies
  (caller shapes)/step/state-read (no out-slot recycle)/queries/
  contacts/joints; fixed scenarios stay as probes.
- `miniaudio/a04-growth` -- xiom.miniaudio 0.3.0 -> 0.4.0 (A04): device
  lifecycle + playback engine + mixer/node graph + capture + streamed
  decode (built-in decoders; opus/ogg custom-backend staged).
- Relay items `-1904` x2 updated (work launched; the v0.64.5 wave is
  closed so the earlier queue gate is gone). Agent request
  `am-1792102594543-f87kzu`.
- Integration at completion; publish follows the standing flow
  (packages verifies + relays engine adoption).

**UPDATE 2026-10-15 22:30Z (relay check: PULSE top-tier directive; SQL
alias re-verified)**:
- `REL-20261015-2202-pulse-5` (to ALL, awareness; **no responses
  required**): PULSE escalated to top-tier #1-class; headline gap =
  **no TLS anywhere in-tree** (gates native HTTPS / wss:// / ALPN /
  ACME). Per-lane asks to stdlib/compiler/packages/ops -- **none to
  bindings**; two relevance notes: (a) the TLS route is a
  "schannel/OpenSSL binding via FFI" -- a vendored-C package event
  that would slot into the wave queue if it lands with bindings;
  (b) the compiler's `xiom-ffigen` C-header parsing ask would serve
  our own generator passes (A9 gles leg / future heads).
  Roadmap: PULSE repo `docs/ROADMAP-TOP-TIER.md`.
- `REL-20261015-2029-pulse`: **FIXED** -- SQL artifact rerun **GREEN
  24/24 on released v0.64.5** (xiom.sqlite 0.4.1 live); corroborates
  the parked B-32 decision: the flat RowOutcome state IS the live,
  verified artifact.
- Nothing new addressed to bindings needs action; A02/A04 stay queued
  behind the Android waves.

**UPDATE 2026-10-15 22:15Z (wave-2b + G3 filed -- 6 package units
live/in flight)**: two more agent sessions requested
(`am-1792101281743-6bucae`): **`android/android-sys`**
(`xiom.android-sys` -- A12 starter: log FUNCTIONAL + sync head) and
**`android/opensl`** (`xiom.opensl` -- A6 legacy tail: SLES/OMXAL/
AMidi; slCreateEngine + realize + destroy via C-side vtable).  The
family is now 1 live package + 6 agent units.  **G3 filed** to
packages: `REL-20261015-2210-bindings` -- propose android-arm64/
android-x86_64 platform tokens; NO artifacts needed (everything is a
system lib at runtime).  Program doc gained a full Status section (the
remaining map: A3/A4 serial to W2c, A9 generator-aware, A10 OWNER,
A11 JNI seam, A12 remainder).

**UPDATE 2026-10-15 22:05Z (ANDROID WAVE-2 LAUNCHED -- 4 agent
worktrees)** per the owner's "agents to 100%" directive; each session
owns disjoint files (integration at their completion via the normal
apply flow; ledgers stay coordinator-only):
- `android/w2c-lifecycle` -- **W2c A2 lifecycle-glue** in
  `xiom.android` 0.3.0: looper (11) FUNCTIONAL on-device (pipe + addFd
  callback + pollOnce proof; direct handoff), activity (24) +
  configuration (52) export-set, native_app_glue documented (source,
  not vendored).
- `android/aaudio` -- **xiom.aaudio 0.1.0** (A6 head): AAudio.h 72 fn
  surface + constants; functional builder lifecycle + honest open
  attempt (emulator may run -no-audio).
- `android/mediandk` -- **xiom.mediandk 0.1.0** (A7 core): MediaCodec/
  Format/Extractor/Muxer/DRM/DataSource; MediaFormat + codec-create
  functional; rest export-set.
- `android/camera2ndk` -- **xiom.camera2ndk 0.1.0** (A8 head): camera
  headers; manager create + camera-id list functional best-effort;
  rest export-set.
- Coming waves: A3 input + A4 sensors (serial to W2c -- same package),
  A9/A10 (existing gles/vulkan packages; A10 = OWNER lane), A11 JNI
  seam (gates live surfaces), A12 log/sync/binder, A6 tail (AMidi +
  OpenSL ES), engine asks A02/A04.
- Agent Manager requests: `am-1792098871905-thr1eg` (3 sessions) +
  `am-1792098889789-40i772` (camera).

**UPDATE 2026-10-15 21:55Z (doorbell: B-32 acked for v0.64.6; eco .183
live)**:
- Compiler **acked B-32** (`8aba9fa`): queued for the **v0.64.6 fixer
  wave**; no re-ask -- the sqlite restore re-tests from the bundle when
  the fix ships.
- **`eco-v0.1.183` LIVE** (20:15Z): `xiom.durable 0.1.0` (`9a5c9b4d...`)
  + `xiom.postgres 0.1.0` (`4363261c...`); run 38798162630 green; sync
  `a908563f`; tally 99 eco releases. **`.184` armed** (redis PROD-only
  scope acked 20:35Z; publish gated on ops LIVE -> allowlist 543).
- Engine lane's v0.64.5 packages sweep: 12/12 VERIFIED (34/34 registry
  re-probe).

**UPDATE 2026-10-15 (doorbell tick; v0.64.5 wave closed; lifts now
publish-requested)**: 
- **v0.64.5 LIVE** (19:18Z) + compiler repinned (installed v0.64.5).
- The evening wave (concurrent sessions) is CLOSED: all probes green
  except B-29 (filed `REL-20261015-1955-bindings`); B-05 cleared by the
  re-vendored stdlib; **glfw 0.6.0 lift DONE (37/37 LIVE)** + **sdl3
  0.20.0 widening DONE (72/72 LIVE)**; dx12 revisit resolved (`-1309`
  closed); sqlite nested restore BLOCKED in situ -> **B-32 filed**
  (acked; rides the v0.64.6 fixer wave).
- **GAP FILLED this tick: the two lifts had NO publish requests** ->
  filed now: `REL-20261015-2105-bindings` (glfw 0.6.0) + `-2105-bindings-2`
  (sdl3 0.20.0).  Relay tip `0d34121`, validate 536 items.
- A02 box2d + A04 miniaudio: acked + queued (triage `-2102-bindings`).
  PULSE `-2029` SQL artifact GREEN 24/24 on v0.64.5 (request satisfied;
  item fixed).  Android program running (W2b A5 head landed,
  `xiom.android` 0.2.0 4/4 SKIP leg; on-device 53/53 + SHM roundtrip
  exact).  Eco: `.183` live (durable+postgres; other lanes), `.184`
  armed (redis gate).

**UPDATE 2026-10-15 21:50Z (ANDROID W2b DONE -- A5 assets-storage head
lands, 53/53 on-device)**:
- xiom.android 0.2.0: export set 27 -> 53 (asset_manager 17 +
  storage_manager 6 + sharedmem 3); the bridge gained the POSIX
  ASharedMemory functional head (create/getSize/setProt + mmap probe
  write/read + fd close; Windows stubs compile clean).
- Suite green on Windows (SKIP leg) on the v0.64.5 pin; constants
  extended (asset modes + PROT bits).
- **On-device (API-36 emulator): 0 missing exports of 53; SHM
  `fd=9 size=4096 read=287454020` exact; HWB roundtrip unchanged;
  RESULT: PASS** (`docs/repro/bindings-pilot/android-core-probe/`).
- Android program ledger + wave brief updated (W2b DONE). Next: W2c
  (A2 lifecycle-glue; ALooper is shell-testable) or the A02/A04 asks.

**UPDATE 2026-10-15 21:40Z (dx12 COM revisit resolved; `-1309` CLOSED)**:
- Revisit verdict: the 0.4.0 `Int`-typed dx12 COM surface is RETAINED
  (both crossing paths value-preserving on v0.64.5; re-typing the
  780KB generated corpus parked -- no consumer breakage either way).
- `REL-20261013-1309-bindings` **fixed -> closed** on the re-verified
  witness (ptr-cast both FIDELITY OK in the wave); dx12 README/SPEC
  B-25 notes updated to the v0.64.5 status.
- `docs/BINDINGS-COMPILER-FINDINGS.md` gained a **v0.64.5 wave
  verification stamp** (B-23/24/25 FIXED; B-26 probe green but B-32
  residual -- restore parked; B-29 STILL RED; B-30/31 FIXED; B-05
  FIXED by the re-vendor; B-13/15/18/22 closed via the direct-handoff
  lifts).
- Queue next: Android W2b (A5 assets-storage head); A02/A04 behind.

**UPDATE 2026-10-15 21:30Z (sqlite nested restore ATTEMPTED -> BLOCKED;
B-32 filed)**: the planned 0.5.0 restore (`Result[Option[SqliteRow]]`;
retire RowOutcome) was applied and RED-ed **in situ** on the v0.64.5 pin:
driver-memory test `q1 ok=true; out some=true; cols.len=140697731719824`
then AV `0xC0000005` -- the B-26 pointer-garbage signature IN the real
package context.
- Isolation FAILED to reproduce: the nested-payload bundle (2/2/2) +
  SEVEN near-miss variants (same/cross-module builders; query-one
  shape; exact SqliteValueKind variant set; struct error type + Err
  paths) are ALL GREEN -- compilation-unit-sensitive residual
  (B-01 family).
- **Actions**: restore PARKED; `xiom.sqlite` reverted clean (stays
  0.4.1-flat; PULSE contract unchanged); repro bundle committed at
  `docs/repro/bindings-pilot/b32-sqlite-nested/` (patch + probes +
  recipe); **B-32 filed** to compiler (high); wave item corrected.
- Corrects the 20:00Z block's "sqlite restore unblocked" line: it was
  probe-level-unblocked only. Next queue: dx12 Int-typed revisit,
  Android W2b (A02/A04 queued).

**UPDATE 2026-10-15 21:05Z (sdl3 0.20.0 WIDENING DONE -- second lift
landed live)**: same m277 direct-handoff family:
- Filter/watch handlers now take the NATURAL C shape (userdata, event)
  and go straight to SDL; dispatchers, registries and the
  userdata-accessors are gone (B-15 closed via the same 2-arg shape).
- New `sdl3_event_copy(event)` helper for the 128-byte owned-buffer copy
  (0.4.0 decode accessors unchanged); removal passes the same
  (handler, userdata) pair; env-free handlers documented.
- Suite LIVE **72/72** on the pin (filter keep + drop proofs; watch
  removal; userdata delivered directly -- 0x77/0x88 seen in handlers).
- Commits `188e9ec7` + `5e4e966e`; relay history on the wave item.
  Queue next: sqlite nested restore, dx12 revisit, Android W2b
  (A02/A04 queued).

**UPDATE 2026-10-15 20:40Z (glfw 0.6.0 LIFT DONE -- dispatcher lift
landed live)**: first follow-up queue item cleared:
- 20 dispatchers + 20 registries removed; setters hand the caller's
  handler DIRECTLY to the DLL (B-22 fixed m277; probe9 witness; live
  key round trip exact).
- Raw-ABI adjustments: error handler `fn(Int32, *UInt8)` + helper
  `glfw_error_desc_read`; content-scale handler f32; drop handler
  `fn(Int, Int32, *UInt8)` + helper `glfw_drop_paths_read`; handlers
  must be env-free (documented in README/SPEC/ROADMAP).
- Suite LIVE **37/37** on the v0.64.5 pin with the GLFW 3.4 dll
  (`C:\glfw-3.4.bin.WIN64\lib-vc2022` on PATH): 20/20 setters;
  error/key/close round trips exact; allocator intact.
- Commits `bff40cb0` + `14df948c`; relay history on
  `REL-20261015-1955-bindings`. Next queue: sdl3 widening, sqlite
  nested restore, dx12 revisit, Android W2b (A02 box2d + A04 miniaudio
  asks still queued).

**UPDATE 2026-10-15 20:00Z (RE-VERIFY WAVE COMPLETE -- all green except
B-29; filed `REL-20261015-1955-bindings`)**: full wave on the v0.64.5
pin (as-shipped; `XIOM_COMPILER=%LOCALAPPDATA%\xiom.new\bin\xiom.exe`):
- Probes ALL GREEN: null-literal (4 paths=0); ptr-read-stale (0/400);
  foreign-ptr-read (C-matching); ptr-slot-write (66/66 exact);
  ptr-arith (d100=100 exact); cb-abi probe9 (42/42/42);
  nested-payload (failures=0; nested 2/2 -- sqlite restore unblocked);
  ptr-cast (BOTH fidelity paths OK -- the B-25 cast hazard is gone;
  dx12 COM revisit unblocked); vulkan-slot-recycle
  (`a=3 b=65536 c=1 rc=0` -- mini-RHI gate open); **B-05 guard-free
  spin GONE** (re-vendored stdlib clears it; B-05 retirement gate
  satisfied).
- STILL RED: **B-29 only** (bigint bitops >=2^31; m314 does not cover
  the class; boundary-arithmetic workaround stays shipped).
- Suites on the pin: **sdl3 72/72** (B-19 + B-11 witnesses green;
  sdl3+jolt runs recorded `68e5a6d3`), **jolt 159/159**; glfw
  SKIP-leg green (no glfw3.dll on this box; live 37/37 leg rides the
  0.6.0 lift).
- **NOW UNBLOCKED (follow-up queue, in order)**: (1) glfw 0.6.0 lift
  (B-22 fixed m277; 18 dispatchers + registries -> direct handoff);
  (2) sdl3 handler-shape widening (B-22-gated); (3) sqlite nested
  restore (`Result[Option[SqliteRow]]`) + RowOutcome retirement;
  (4) dx12 Int-typed COM-param revisit + `-1309` close; (5) B-25/B-30/
  B-31 workaround retirements at next touches; (6) Android W2b (A5
  assets-storage head). New asks queued: A02 box2d + A04 miniaudio.

**UPDATE 2026-10-15 19:45Z (v0.64.5 RELEASED + PINNED; RE-VERIFY WAVE
STARTED -- B-29/30/31 witnesses filed)**: the archive landed 19:18Z
(wrap 19:20Z: tag `84f761c5`, release run 38792051847 green, assets
live). Wave under way:
- **PIN DONE**: `xiom-0.64.5-windows-x64.zip` sha256 `bd71e2d3...`
  verified; canonical slot `%LOCALAPPDATA%\xiom.new` = 557/557 files
  (runs `XIOM Compiler v0.64.5`); `COMPILER_VERSION` -> v0.64.5;
  `status.ps1 repin` **554/554 updated** + validate **554/0**; commit
  `eedf6f53` pushed. Wave toolchain:
  `XIOM_COMPILER=%LOCALAPPDATA%\xiom.new\bin\xiom.exe` (as-shipped;
  no XIOM_STDLIB override).
- **Witness re-runs filed on `REL-20261014-1208-bindings-2`** (the
  compiler asked): **B-29 STILL RED** (shift20=2987 /
  and_mask=0xBAC00000 / div20=2987; want 2989/3132620800/2989; exit 1)
  -- m314 wide-int does NOT cover the big-int bitops class; workaround
  stays shipped. **B-30 FIXED** (probe.xi compiles + runs green rc 0,
  `ch=2`; probe_fixed green). **B-31 FIXED** (probe.xi `--emit-ir`
  rc 0, no stack overflow; control green). B-30/B-31 workarounds are
  retirement candidates at the next package touches.
- Inquiry `-1109` answered: v0.64.5 carries NO android target;
  cross-target scoping sits on the v0.64.6 roadmap (darwin is the
  v0.64.6 headline); **android priority = owner call**. Emulator
  evidence noted on the item; our Android prep continues in parallel.
- New asks filed to bindings (`REL-20261015-1904-packages` x2): A02
  box2d 2D-solver surface growth; A04 miniaudio audio-engine growth.
  Queued behind the wave.
- **WAVE CONTINUES**: remaining probes (null-literal, ptr-read-stale,
  foreign-ptr-read, ptr-slot-write, ptr-arith, cb-abi probe9, sdl3
  synthetic-event readback, vulkan-slot-recycle, nested-payload +
  sqlite restore, ptr-cast + dx12 revisit, B-05 alloc-guard-spin
  watcher) + package suites on the pin (sdl3/glfw/jolt) + the v0.64.5
  release-check rows; THEN glfw 0.6.0 lift + sdl3 widening + B-27/B-28
  re-vendor retirement.

**UPDATE 2026-10-15 18:30Z (ANDROID W2a DONE -- xiom.android A1 head
lands GREEN both ways)**: first Android package authored while the
release holds; nothing release-gated was needed.
- New package `packages/xiom-android` (candidate name `xiom.android`,
  rename-safe per the brief): runtime bridge (dlopen on Android /
  LoadLibraryA on Windows) + A1 window-core head = native_window.h
  (15 non-inline exports) + hardware_buffer.h (12 exports) --
  **27/27 resolved on-device**; functional AHardwareBuffer
  (isSupported/allocate/describe/lock-write/lock-read/release;
  pointers stay C-side per B-25).
- Suite on Windows (v0.64.4): **4/4 green** (constants; deterministic
  ABSENT skip path via bogus sonames; probe SKIP; unload).
- On-device probe (API-36 emulator; W2a evidence): load rc=0,
  missing_exports=0, is_supported=1, alloc OK, describe 64x64 / RGBA8
  / stride 64 / layers 1, pixel roundtrip exact (0x11223344);
  **RESULT: PASS**; repro
  `docs/repro/bindings-pilot/android-core-probe/`.
- JNI-surface exclusions documented (A11 seam). Next: W2b A5
  assets-storage head. RE-VERIFY WAVE still arms on the archive tag
  (signal pending on `-1739`; stdlib-v0.64.5 published 13:45Z).

**UPDATE 2026-10-15 12:15Z (ANDROID W1 DONE -- opus vendor-C spike
PASSES on the API-36 emulator)**: first on-device Android evidence:
- Cross-built the EXACT xiom.opus units (opus_bridge + 4 vendor unity
  units) with NDK r27b clang: x86_64-linux-android26 (run) +
  aarch64-linux-android26 (build) -- both ELF64/DYN (aarch64 machine
  = AArch64, readelf-verified).
- Flags found during the spike (now in the repro + build-spike.ps1):
  flat vendor tree needs `-I vendor/opus -I vendor/opus/float
  -I vendor/opus/fixed`; the float build MUST link `-lm` (DT_NEEDED
  libm.so) or on-device dlopen fails `cannot locate symbol "exp"`;
  `-Wl,-soname,libopus.so` pinned.
- Harness (dlopen by path = the xiom.ffi.dl load model + xo_* encode/
  decode roundtrip) on the emulator: dlopen OK; encoder_size=31668;
  encoder+decoder create OK; encode 127 bytes; decode 960 samples;
  **SPIKE RESULT: PASS**.
- Repro: `docs/repro/bindings-pilot/android-ndk-spike/` (README +
  build-spike.ps1 + opus_harness.c). Emulator kept running headless
  (session background process) for W2/W3; arm64 on-device run waits
  on a device (build green).
- Program doc `docs/ANDROID-SDK100.md` updated: W1 DONE; W2 STARTED --
  brief `docs/prep/android-wave.md` (oracle sizes per head + SKIP
  semantics + naming gate + order W2a-d); the committed
  `build-spike.ps1` re-run verified on Windows PowerShell 5.1.

**UPDATE 2026-10-15 11:55Z (ANDROID SDK100 PROGRAM STARTED -- blocker
map answered; oracles pinned)**: owner asked for the lane-by-lane
blocker map + a path to 100% Android support:
- New program ledger `docs/ANDROID-SDK100.md`: **"100% Android" = 100%
  of the NDK native surface** (the Java SDK is out of scope by design;
  reachable only via the JNI seam, slice A11). Oracles pinned: header
  families (android/ 68, vulkan/ 20, SLES/ 5, EGL/ 5, GLES3/ 5,
  aaudio/ 1, + media/camera/amidi/jni.h) + **26 link-stub libs for
  BOTH aarch64 + x86_64** (r27b sysroot links up to API 35). 12 slices
  A1-A12.
- **Blocker map**: **G1 compiler = the hard gate** (android-arm64 /
  x86_64 emission + bionic runtime; inquiry `-1109-bindings` still
  OPEN -- addendum pushed 11:55Z with toolchain + emulator evidence and
  the x86_64-first VALIDATE-vehicle note); G2 stdlib android runtime
  gaps (rides the G1 reply); G3 packages/eco android artifacts +
  `android-arm64`/`android-x86_64` platform tokens (coordination, not
  a start-gate); G4 validation infra = **local already**: API-36
  x86_64 emulator + AVD `Medium_Phone` + adb (arm64 = physical device,
  no sdkmanager adds under the read-only rule); G5 ours, no blockers.
- W1/W2 next: opus vendor-C spike (x86_64 emulator run + aarch64
  build) + SKIP-safe prep surfaces (A1/A2/A6 heads). The vendor-C
  half of Android is provable BEFORE the compiler target exists.
- Compiler intel refresh (relay): **v0.64.5 signal IMMINENT** -- all
  four `-2123` stdlib classes fixed (m323/m324/m325/m326) + m327
  bug55 follow-up landed; full e2e re-gate running, archive signal
  next. Darwin/macOS general fix OWNER-DECIDED to **v0.64.6**
  (v0.64.5 does NOT wait; dry-run 38626737822 job-verifies both
  macOS legs). On signal -> the RE-VERIFY WAVE (item 0) still stands.

**UPDATE 2026-10-15 11:35Z (ANDROID TOOLCHAIN LOCATED + VERIFIED -- owner
supplied path)**: owner pointed at `C:\Android\sdk` (his Unity/UE5/Flutter
SDK). Verified READ-ONLY on this box, all green:
- `ANDROID_SDK_ROOT=C:\Android\sdk` (user-level + process); `ANDROID_HOME`
  and `ANDROID_NDK_HOME` are NOT set (export `ANDROID_NDK_HOME`
  per-invocation only).
- NDK r27b `27.1.12297006` (`source.properties` Pkg.Revision) plus r27
  `27.0.12077973` and `26.3.11579264`; clang 18.0.2 (`Android
  (12285214, based on r522817b)`) at
  `ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64\bin`
  (clang / llvm-ar / ld.lld / llvm-readelf present).
- **CROSS-BUILD SMOKE PASSED**: `clang --target=aarch64-linux-android26
  -fPIC -shared` on a trivial C file -> `libsmoke.so` (5176 bytes;
  `llvm-readelf`: ELF64 / AArch64 / DYN). First cross-arch artifact this
  lane has produced.
- Prep-wave headers (r27b sysroot `usr\include`): `android\`
  (native_window.h / looper.h / asset_manager.h / bitmap.h /
  configuration.h), `aaudio\AAudio.h`, `SLES\OpenSLES.h`; native_app_glue
  is a SOURCE at `ndk\27.1.12297006\sources\android\native_app_glue\`
  (NOT in the sysroot -- compile it into the app).
- CMake 3.22.1 + ninja at `C:\Android\sdk\cmake\3.22.1\bin`; platforms
  android-33/35/36; build-tools through 36.0.0; PATH java is 1.8 (use
  Android Studio JBR `C:\Program Files\Android\Android Studio\jbr` if
  cmdline-tools are ever needed).
- **Shared toolchain (Unity/UE5/Flutter) -> READ-ONLY rule: no sdkmanager
  installs/upgrades without owner OK.** The next session's Android prep
  wave + opus NDK spike can run off this as-is.

**UPDATE 2026-10-15 11:30Z (CONTEXT-LIMIT HANDOFF -- owner directives;
paste prompt rebuilt)**: session handoff written.
- **Owner directives**: (1) the macOS/darwin legs fix is queued for the
  NEXT compiler candidate (v0.64.5 remains HELD on the Cell[Int8]/aes
  regression; watch for v0.64.5/v0.64.6); (2) **the next session starts
  with the ANDROID SDK work** (read the reply to the cross-target
  inquiry `REL-20261015-1109-bindings`, then the Android prep wave +
  NDK cross-build spike); (3) open package bugs are expected to surface
  in the new release's test runs -- no special sweep needed.
- Paste prompt rebuilt (2026-10-15 11:30Z): E-family-complete state,
  waves compressed, tag-gated RE-VERIFY WAVE with all current re-probes
  (incl. B-29/30/31 + the re-vendored-stdlib retirement gate),
  Android-first first actions.
- Current live state unchanged: 98 releases through `eco-v0.1.182`;
  no sessions in flight; relay tip `5b4a72f` (507 items).

**UPDATE 2026-10-15 06:05Z (doorbell -- jolt 0.7.0 PUBLISHED
`eco-v0.1.182`; E-FAMILY COMPLETE LIVE; v0.64.5 tag still held)**:
- **jolt 0.7.0 (E4/E5) LIVE**: `eco-v0.1.182` (merge `afd93d4c` tip
  `51601b52`; brace-glue fixes `f0e60f90`/`6a01201d`; validate 553/0;
  native x2 **159/159** both runs -- E4 soft bodies (volume/grid/rope +
  settle/drape + bulk out-buffer + 13 typed errors), E5 heightfield
  (plateau/ramp + quantization + settle + 8 typed errors); record
  `954dfcfb`, wrap `0780149d`; run 38684757867 green; live sha256
  `b1d09efd...` @05:05:29Z; README/STATUS synced `651c238f`; item
  `-0313-bindings` fixed). **Engine relayed with the family-complete
  notice** (`REL-20261015-0507-packages`; all E1-E7 wireable against
  0.7.0). Tally **98 eco releases** (`eco-v0.1.86`..`182`).
- The entire E-family workstream is DONE overnight (0.4.0 -> 0.7.0).
- **v0.64.5 tag still HELD** (`-2123` fix in progress); agenda/upscaler
  wave next after; on tag -> packages repin -> the lane's RE-VERIFY WAVE
  (m275-m294).

**UPDATE 2026-10-15 03:20Z (E-FAMILY COMPLETE -- jolt 0.6.0 LIVE in
`eco-v0.1.181`; 0.7.0 integrated + publish-requested)**:
- **0.6.0 PUBLISHED**: `eco-v0.1.181` (97 releases; engine relayed
  `REL-20261015-0158-packages`); my request `-0002` fixed.
- **0.7.0 DONE + integrated** (`1087a5d7`; record `51601b52`): E4 soft
  bodies (cloth/rope/volume presets; particle read-back incl. bulk
  out-buffer) + E5 heightfield (samples+scale+quantization; settle +
  E1 raycast); suite 109 -> **159/159 x2**.  Publish request
  `REL-20261015-0313-bindings`.  **E8 + E1-E7 all delivered** -- the
  engine's top dependency closes when 0.7.0 publishes.
- **v0.64.5 still HELD** (candidate regression Cell[Int8]/aes escalated
  pre-pin; candidate probes 310/315 otherwise green).  No archive yet;
  the re-verify wave stays armed.
- Relay tip `e8344e9`, validate 504 items.  No sessions in flight --
  the jolt E-family workstream is DONE (0.4.0 -> 0.7.0 in one night).

**UPDATE 2026-10-15 00:45Z (doorbell: jolt 0.6.0 integrated +
publish-requested; E4/E5 session launched; v0.64.5 tag HELD)**:
- **jolt 0.6.0 DONE + integrated** (`2d1d3a0a`; record re-pointed
  `569202c4`): E3 typed joints (fixed/hinge/slider/point + motors/
  limits/state reads) and E6 convex/compound; suite 67 ->
  **109/109 x2**.  Publish request `REL-20261015-0002-bindings`.
- **Final E session launched**: `feat/jolt-e4-e5`
  (`am-1792022598613-tp5dqu`) = 0.7.0: E4 particles/soft bodies + E5
  heightfield -- the last two tiers of E1-E7.
- **v0.64.5 tag HELD** (stdlib `d80bf1b`: candidate regressions filed as
  item 2123; tag held on 1739; candidate probes 310/315 OK) -- release
  not out; `gh` still v0.64.4, installed compiler still v0.64.4.  The
  re-verify wave stays armed for the tag.
- Relay tip `8964a3d`, validate 502 items.  (Push race with the
  concurrent session resolved; shared tip `569202c4`.)

**UPDATE 2026-10-15 00:05Z (doorbell -- jolt 0.5.0 PUBLISHED
`eco-v0.1.180`; v0.64.5 tag still held)**: packages confirms the publish
queue drained for this lane's top ask:
- **jolt 0.5.0 LIVE**: `eco-v0.1.180` (wrap `f5f899c5`, record
  `e8c6bf67`; native x2 **67/67** both runs; validate 553/0; engine
  relayed by packages at 96 eco releases, `eco-v0.1.86`..`180`). E3-E6
  stay queued as strict sequential follow-ons in `feat/jolt-e3-e6`.
- **v0.64.5 tag HELD** (packages 23:15Z): stdlib candidate regressions
  `-2123` gate the cut; the release wave (`1e4a444e`) + dry-run are
  green and the pre-repin home snapshot was refreshed
  (`20261015-000115`, 5019 files). Next archive carries m275-m294
  (incl. m281 B-23/B-24/B-20/B-11-addendum, m277 B-22) -> the lane's
  RE-VERIFY WAVE runs on tag.
- Relay: `-2101-bindings` (jolt publish request) fixed; no new
  bindings-addressed items this tick.

**UPDATE 2026-10-14 21:35Z (v0.64.5 TAG SIGNAL SENT; jolt E-family
moving -- 0.5.0 integrated + publish-requested; E3/E6 session up)**:
doorbell tick.
- **v0.64.5**: compiler sent the TAG SIGNAL (`06d0a7c`: release-wave
  push `1e4a444e` + dry-run 38626737822 green; stdlib frozen at
  `db2fbe8` -- "cut stdlib-v0.64.5").  `gh` still shows v0.64.4; the
  release is in progress.  **On tag: packages repins, then the
  RE-VERIFY WAVE runs** (all repro bundles + glfw 0.6.0 lift + sdl3
  widening + sqlite nested-shape restore + workaround retirement incl.
  the re-vendored-stdlib gate).  Also m318/m319 (2215/2238 family),
  m321 triage (2119/1213 probe-side) landed.
- **jolt 0.5.0 DONE + integrated** (`e61b57f8`; record re-pointed
  `73ea38a5`): E1 queries (raycast/sweep/overlap + deterministic
  broadphase order), E2 capsule, E7 contacts/sensors; suite 24 ->
  **67/67 x2**.  Publish request `REL-20261014-2101-bindings` (engine
  can wire E1/E2/E7 on publish).
- **Next E session launched**: `feat/jolt-e3-e6`
  (`am-1792011716674-4rcmkf`) = 0.6.0: E3 typed joints (+motors/limits/
  state reads) and E6 convex/compound.  E4/E5 queue behind it (same
  package -- strictly sequential).
- `-1510` nudge acked earlier (queue aligned); `-1800-bindings` (our
  ack item to engine) closed engine-side.  Relay tip `d2c7aac`,
  validate 499 items.

**UPDATE 2026-10-14 18:10Z (doorbell: v0.64.5 pin prep underway; jolt
E-family session launched)**:
- **v0.64.5 PREP SIGNAL**: compiler filed the pin request to stdlib
  (`af92693`: freeze sha carrying wave 139; tag on signal).  Release
  gate ON the 1423 runtime long-truncation fix (stdlib main `6937b7c`
  still has it; the runtime half landed `ae9c963`).  Also m314-m320:
  2042/2042-2/2227 (wide-int), 2139 geom collision, 1158 spawn-literal
  parse, 2256/2324-2/-3 (constant surface), **m320 `b672a19f` 1819
  Int-ptr arg + 2035 &Str param**; thread gate green pre-pin.
  **When the v0.64.5 tag lands -> the RE-VERIFY WAVE** (repros + glfw
  0.6.0 lift + sdl3 widening + sqlite nested-shape restore + workaround
  retirement, incl. the re-vendored-stdlib gate for B-27/B-28).
- Engine nudge `-1510-engine` (acked by the concurrent session):
  priority = **E-family E1-E7 > wave-B remainder > upscaler wave**; E8
  landed in jolt 0.4.0; wave-B/upscaler largely live (`.178`/`.179`).
- **Launched `feat/jolt-e1-e2-e7`** (`am-1792000864533-27vojc`): jolt
  0.5.0 = E1 queries (raycast/sweep/overlap + deterministic broadphase
  order), E2 capsule shape, E7 contacts/sensors.  E3/E4/E5/E6 are
  follow-on jolt sessions (same package -> strictly sequential; queued
  for when 0.5.0 lands).
- No new eco notes (95 through `.179`); no new bindings-addressed asks.
  Relay tip `af92693`, validate 490 items.

**UPDATE 2026-10-14 14:57Z (WAVE-3 + A05 PUBLISHED -- `eco-v0.1.179`,
11 packages incl. the A05 set; ops loop closed; stdlib B-27/28 root
cause)**: doorbell relay check.
- **WAVE-3 LIVE**: `eco-v0.1.179` (run 38577890832 green; merge
  `945b795f`, wrap `52dc853b`): ffmpeg 0.4.1 (0.4.0 stays held),
  jolt 0.4.0, ozz 0.4.0, sdl3 0.19.0, rtxgi 0.1.0, rtxdi 0.1.0,
  rpr 0.1.0, openpgl 0.1.0, stb 0.3.0, exr 0.1.0, photometrics 0.1.0.
  A05 (10)+(11) items fixed in the same release; ops closed the loop
  (allowlist 540; `992c4b1`).  Tally 95 releases through `.179`.
- **stdlib B-27/28 root cause** (`-1401-stdlib`, acked): the v0.64.4
  archive bundles a STALE stdlib snapshot -- the findings are real
  against the shipped toolchain; stdlib main is fixed (`45d0337`).  Our
  runner uses `XIOM_STDLIB=E:\xiom-lang\stdlib` (main) so in-lane is
  already on the fix; shipped workarounds stay for consumers on the
  bundle.  **Retirement gate = the next pin that re-vendors stdlib**
  (wave item; re-probe bundles ready).
- Compiler: m309 fixed `-2320-bindings` parts 2+3 (confined-block Vec
  Copy-Out + deep first-wins merge); m312/313 progress (1423 hang gone;
  B-05 spin still persists -- call-site lowering in flight).
- The A05 race corrections (`-1304`/`-1306`) were withdrawn/deleted by
  packages -- no action.  No sessions in flight.  Relay tip `b74b49c`,
  validate 490 items.  No v0.64.5 archive yet.

**UPDATE 2026-10-14 13:35Z (WAVE-3 integrated -- 11 packages; ffmpeg 0.4.1
FIX DONE; stdlib fixed B-27/B-28 within the hour)**: relay check turned
into a full integration pass; everything green.
- **ffmpeg 0.4.1 SHIPPED IN-LANE**: `-2142` root cause = demux codec id
  resolved BY NAME (the avformat 61 generation reports a different
  numeric id); x2 23/23 on BOTH generations (7.1.1 Blender + 6.1.1 GIMP)
  + SKIP 3/3.  **0.4.0 stays HELD; ship 0.4.1 only.**  Publish batch
  `REL-20261014-1331-bindings`.
- **Wave-3 integrated (11 packages; tip `cae7a9b1`; validate 553/0)**:
  jolt 0.4.0 (24/24 forces), ozz 0.4.0 (9/9 caller surface), sdl3 0.19.0
  (72/72 + absent 8/8; full surface 1269/1269 bound + 1270/1270
  resolved), rtxgi 0.1.0 (28/28), rtxdi 0.1.0 (33/33), rpr 0.1.0
  (35/35 present + 9/9 SKIP; ProRender SDK v3.1.7.1; 88 declared items),
  openpgl 0.1.0 (14/14; Open PGL v0.7.1 + oneTBB), stb 0.3.0 (18/18 HDR
  class), exr 0.1.0 (12/12; tinyexr v3.2.0), photometrics 0.1.0 (43/43;
  IES + .cube).  All records re-pointed; platform rows restored.
- **stdlib FIXED B-27/B-28** (`45d0337`, ~1h after filing): write_at
  offsets + reserve cap seed; probe + smokes green.  Workaround
  retirement becomes a wave item once a pin carries the fix (keep the
  shipped forms until then).
- Still open: B-29/B-30/B-31 (compiler); no v0.64.5 archive yet.
- **No sessions in flight** -- all 9 (wave-3 + A05) delivered and
  integrated.  Relay tip `811d35f`, validate 484 items.

**UPDATE 2026-10-14 13:05Z (WAVE-2 LIVE in `eco-v0.1.178`; engine
relayed; A05 launched)**: relay check -- the unattended flow closed the
loop end-to-end.
- **WAVE 2 PUBLISHED**: `eco-v0.1.178` (merge `858df12a`, tip
  `3a22a083`, wrap `eb21dc46`, run 38565995820 green; 12 packages, all
  x2).  Tally 94 releases through `.178`.  My batch item
  `-1208-bindings-3` fixed; **engine relay already sent** by packages
  (`REL-20261014-1259-packages`, per the standing `-2125` rule) with
  per-package sha256s.
- **B-27/B-28 acked** by the stdlib lane (fixes can ride the next pin;
  re-probe bundles ready).  B-29/B-30/B-31 still open on the compiler
  side.
- **A05 ask acked + sessions launched** (`am-1791982901082-notuk9`):
  `feat/stb-hdr-exr` (xiom.stb 0.3.0 `.hdr` surface + NEW `xiom.exr`
  tinyexr reader) and `feat/photometric-profiles` (NEW
  `xiom.photometrics`: IES LM-63 + `.cube`, pure XIOM independent).
- Still in flight: ffmpeg 0.4.1 fix, jolt 0.4.0 forces, ozz 0.4.0,
  sdl3 0.19.0, rtxdi+rtxgi, rpr, openpgl.  v0.64.4 still latest (no
  v0.64.5 archive yet).  Relay tip `d1b6b27`, validate 477 items.

**UPDATE 2026-10-14 12:15Z (WAVE-2 FULL INTEGRATION -- 12 packages;
B-27..B-31 canonized; publish batch filed)**: all overnight agent
deliveries integrated onto `bindings` (tip `5bc15161`); records
re-pointed; platform rows restored; validate 547/0.
- NEW packages: `xiom.opus` 0.1.0 (105/105; 26/26 x2), `xiom.lz4` 0.1.0
  (111/111; 81/81), `xiom.ktx2` 0.1.0 (93/93; 41/41), `xiom.vdb` 0.1.0
  (pure-XIOM minimal reader; 30/30), `xiom.nis` 0.1.0 (28/28),
  `xiom.fidelityfx` 0.1.0 (FSR SDK v2.3.0; 43/43 present + 35/35 SKIP),
  `xiom.dlss` 0.1.0 (closed-SDK independent declarations; 21/21 SKIP /
  22/22 present), `xiom.xess` 0.1.0 (29/29), `xiom.nrd` 0.1.0
  (reference-only loader, license NOT MIT; 29/29 both paths),
  `xiom.oidn` 0.1.0 (33/33 + 4/4).
- Updates: `xiom.ogg` 0.2.0 (libogg packet layer; 34/34), `xiom.phonon`
  0.3.0 (FULL 216/216 surface; 38/38 present + 6/6 absent).
- Publish batch to packages `REL-20261014-1208-bindings-3` (hold-and-
  report on any x2 failure; engine relay standing per `-2125`);
  new-name coverage already in the ops bulk confirm.
- **B-27..B-31 canonized** (three sessions collided on B-27/B-28):
  **B-27** `ffi.write_u32_at/u64_at` drop offset (STDLIB); **B-28**
  `Vec.reserve`/`with_len` HEAP OVERFLOW, ASan-proven (STDLIB);
  **B-29** big-int bitops >= 2^31 (compiler; dlss); **B-30**
  confined-block ptr-cast IR undef (compiler; phonon); **B-31**
  const-alias stack overflow (compiler; phonon).  Items: stdlib
  `-1208-bindings`, compiler `-1208-bindings-2`; rows/notes/repro refs
  updated; B-25/B-26 m283 rows restored (a cherry-pick take had
  regressed them).
- New sessions (`am-1791979162620-6ud3yt`): ffmpeg 0.4.1 demux fix
  (HIGH; 7.1.1-vs-6.1.1 ok-gate), jolt 0.4.0 forces (engine `-2115`),
  ozz 0.4.0 caller-data (`-2308`), sdl3 0.19.0 device surface
  (`-2324`), path-tracer re-request (rtxdi+rtxgi / rpr / openpgl --
  the first request never materialized).
- Acks: ffmpeg bug, three new engine asks, engine 2109/2112/2115-2;
  path-tracer survey answered to engine (`-1200-bindings`).  Relay
  tips `dd65a83` + `296bb0a`, validate 474 items.

**UPDATE 2026-10-14 12:05Z (doorbell -- wave A/B eco versions recorded)**:
- **Codec wave A LIVE as `eco-v0.1.176`** (run 38468818666): `xiom.jolt`
  0.3.0 (sha `3ac3df4e`), `xiom.zstd` 0.3.0 (`6288ac84`), `xiom.meshopt`
  0.5.0 (`521dab9e`), `xiom.ffmpeg` 0.3.0 (`24a5c522`); live 21:14-21:17Z
  on 2026-10-13; all x2 green.
- **Wave B first LIVE as `eco-v0.1.177`** (2026-10-13 22:00Z; ops
  bulk-confirmed the 17-name allowlist): `xiom.harfbuzz` 0.1.0 +
  `xiom.basisu` 0.1.0 + `xiom.spz` 0.1.0 (x2 green). `xiom.ffmpeg` 0.4.0
  demux stays HELD (`REL-20261013-2142-packages`: stream-info ok=false on
  FFmpeg 7.1.1).
- Tally **93 eco releases** (`eco-v0.1.86` -> `eco-v0.1.177`); validate
  **537/0**; guard **538 allowlisted / 508 ready / 30 grandfathered / 0
  failures**. No open relay items addressed to bindings at 12:00Z.

**UPDATE 2026-10-15 00:05Z (doorbell -- jolt 0.5.0 LIVE as `eco-v0.1.180`)**:
E-family first delivery published: `xiom.jolt` 0.5.0 (E1 world queries +
E2 capsule shape + E7 contacts/sensors; engine `-1510` priority 1) --
merge `10167d9d` (tip `73ea38a5`; validate 553/0), native x2 **67/67**
both runs (record `e8c6bf67`), wrap `f5f899c5`, **`eco-v0.1.180`** (run
38651812029 green; live sha256 `1035c987...` @23:06:27Z); item
`-2101-bindings` fixed; engine relayed (`REL-20261014-2310-packages`);
E3-E6 queued sequential follow-ons. Tally **96 eco releases**
(`eco-v0.1.86` -> `eco-v0.1.180`); guard **540 allowlisted / 524 ready /
16 grandfathered / 0 failures**. **v0.64.5 tag still HELD** (stdlib
candidate regressions `-2123` in triage; `d80bf1b`) -- no repin yet; zero
open bindings relay items at 00:00Z.

**UPDATE 2026-10-15 03:05Z (doorbell -- jolt 0.6.0 LIVE as `eco-v0.1.181`)**:
E-family second delivery published: `xiom.jolt` 0.6.0 (E3 motors/limits
+ full typed-error matrix; E6 convex/compound + E1 query integration +
contact manifold; determinism bit-identical) -- merge `a857a7f2` (tip
`569202c4`; validate 553/0), native x2 **109/109** both runs, record
`64a04549`, wrap `a68a8a93` (an interrupted earlier attempt had already
tagged `8eef455b`; both pushed), **`eco-v0.1.181`** (run 38666089475
green; live sha256 `e5c777f8...` @01:35:43Z); item `-0002-bindings` fixed
(raced by the concurrent session; note appended); engine relayed
(`REL-20261015-0158-packages`). Tally **97 eco releases**
(`eco-v0.1.86` -> `eco-v0.1.181`). **E4/E5 = the final E-family session
(launched)**; **v0.64.5 tag still HELD** (`-2123` Cell[Int8]/aes fix in
progress, escalated pre-pin). Zero open bindings relay items at 03:00Z.

**UPDATE 2026-10-15 06:05Z (doorbell -- jolt 0.7.0 LIVE as `eco-v0.1.182`;
E-FAMILY COMPLETE)**: `xiom.jolt` 0.7.0 (E4 soft bodies -- volume/grid/
rope + settle/drape + bulk out-buffer + 13 typed errors; E5 heightfield --
plateau/ramp + quantization + settle + 8 typed errors) -- merge `afd93d4c`
(tip `51601b52`; brace-glue fixes `f0e60f90`/`6a01201d`; validate 553/0),
native x2 **159/159** both runs (record `954dfcfb`), wrap `0780149d`,
**`eco-v0.1.182`** (run 38684757867 green; live sha256 `b1d09efd...`
@05:05:29Z); README/STATUS synced `651c238f`; item `-0313-bindings` fixed;
engine relayed with the **family-complete notice** (`REL-20261015-0507-
packages`; all E1-E7 wireable against 0.7.0). Tally **98 eco releases**
(`eco-v0.1.86` -> `eco-v0.1.182`). **v0.64.5 tag still HELD** (`-2123` fix
in progress); agenda/upscaler wave next. Zero open bindings relay items at
06:00Z.

**UPDATE 2026-10-15 21:05Z (doorbell -- v0.64.5 repin + batch 85
recorded)**: **v0.64.5 RELEASED 19:18Z**; repin `cb364af3`:
COMPILER_VERSION + **553 records** @ v0.64.5; archive SHA256 `bd71e2d3`
verified; canonical install `%LOCALAPPDATA%\xiom.new` byte-identical
**557/557**; validate **553/0** (packages block; `-1403` sdl3 re-verify
**72/72, 0 warnings** -- retire the sdl3 workaround at the next binds
touch; `-1549-packages-5/-7/-9/-11` all fixed->verified). **Batch 85 =
`eco-v0.1.183`**: `xiom.durable` 0.1.0 (`9a5c9b4d...`) + `xiom.postgres`
0.1.0 (`4363261c...`) LIVE (wrap `223d71db`; guard 542/526/16/0; index
559; run 38798162630 green); **`xiom.redis`** built 19/19 x2
(`5c313832`/`93918eff`) gate-pending on its scope confirm. Bindings-side
wave notes: **B-32 filed** (sqlite nested-shape restore blocked in situ;
parked for the v0.64.6 fixer wave; package stays 0.4.1-flat), `-1309`
closed (v0.64.5 witness green), B-25 notes value-preserving. Engine **A02
(box2d growth)** + **A04 (miniaudio growth)** accepted into the queue
(`-1904-packages(-2)` acked); PULSE artifact chain satisfied
(`-2029-pulse` noted).

**UPDATE 2026-10-16 11:05Z (doorbell -- batch 86/87 records + PULSE
TLS/brotli accepted)**: **batch 86 = `eco-v0.1.184`**: `xiom.redis` 0.1.0
LIVE (wrap `a4351a72`, allowlist 543; run 38806083545 green; live sha256
`215a95c1...` @21:00:52Z) -- **100 eco releases**. **Batch 87 (wave 4) =
`eco-v0.1.185`**: **`xiom.glfw 0.6.0` (dispatcher lift, B-22 retired) +
`xiom.sdl3 0.20.0` (filter/watch direct handoff, B-15)** LIVE (sha256s
`e0acf0cc...`/`b04a0ae4...`; x2 37/37 + 72/72 on v0.64.5, **0 warnings**;
run 38810046611 green) -- **101 eco releases**; the two parked workaround
lifts from the v0.64.4 wave are SHIPPED. `eco-v0.1.186` next (transport +
otel via `-2309-3`). Relay: PULSE top-tier asks **TLS context binding
(libssl-class; composes xiom.tls + xiom.openssl)** + **real brotli
(libbrotli)** accepted into the queue (`-2211-packages(-2)`; `-2302`
duplicate noted; `-2313` dedupe agreed). Android wave-2 landing: 5 of 8 in
(validate 559/0).

**UPDATE 2026-10-17 12:05Z (doorbell -- miniaudio 0.5.0 + `eco-v0.1.194`
publishes recorded; v0.64.6 repin DONE)**: packages confirms both queued
publishes from this lane:
- **`xiom.miniaudio 0.5.0` PUBLISHED** (single tag `xiom-miniaudio/v0.5.0`;
  sha256 `7d83c1ed...`; run 39027702853 green; registry live-verified;
  sync `35fea936`): handle surface (open once, callbacks/streams, close),
  x2 **44/44** on v0.64.6. `-2324-bindings` fixed; engine ask
  `-2134-engine-2` delivered+shipped; `-2139-packages-2` folded.
- **`eco-v0.1.194` LIVE** (M2 runtimes + gps; run 39030226463 green;
  allowlist 559 -> 561; guard 561/552/9/0): **torch** `bde0ce5c`,
  **libtorch** `865c6d2a`, **tensorflow** `0f4bb6a5`, **blas**
  `bee07a38`, **gps** `020b50ac` -- all registry live-verified; relays
  `-0042-bindings-2` + `-2144-bindings-2` fixed. openblas metadata fix
  stays unpublished until a future 0.1.x bump (0.1.0 already live in
  `.193`).
- **v0.64.6 repin landed in this repo** (`d2ef7ec2`): COMPILER_VERSION +
  **566 records** aligned (validate 566/0); the repin-wave trigger is
  cleared.
- Remaining queue (bindings side): epos publish request; numpy grant;
  compiler re-verify rows (B-29 / W1.4 / W2.3 / B-34 + m348-m351); llm
  tokenizer/bench; jev S8 + S6 SPEC pin; openblas real accel;
  pandas/arrow libarrow backends.

**UPDATE 2026-10-16 21:05Z (doorbell -- v0.64.6 RELEASED)**: compiler
**v0.64.6 RELEASED 2026-10-16 20:33Z** (`REL-20261016-2034-compiler`;
assets live). This is the **REPIN-WAVE TRIGGER** (next-session first
priority per the 11:30Z/18:15Z handoffs): download + sha256-verify +
install the lane-local slot (NEVER the shared home -- clobber rule), bump
`COMPILER_VERSION`, repin (563+ records), validate, then the queued
re-verify: **m334 tuple fix** (1941 green; 2022/2303/2309 verdicts),
**B-29/B-32** (B-32 = sqlite nested-shape restore; repro bundle
`b32-sqlite-nested`), editor rows, B-25/B-26 residuals, and the
workaround-retirement checks that ride this pin. Also this window:
**family 7/8 LIVE in `eco-v0.1.192`** (android family + `xiom.pulse`
Beacon; legacy android scope re-grant asked of ops); **R2 landed**
(`0d25d58b`: `xiom.serial 0.1.0` 52/52 + `xiom.ros2 0.2.0` 82/82 x2;
validate 563/0; publishes filed; B-33 to compiler). Beacon acceptance
stage 1 GREEN (125/125 x2 both platforms). Zero open bindings-addressed
relay items; validate 660 green.

**UPDATE 2026-10-17 12:05Z (doorbell -- `eco-v0.1.194` LIVE; in-tree repin
done)**: **`eco-v0.1.194`** (run 39030226463 green) -- 5 LIVE +
live-verified: `xiom.torch` `bde0ce5c`, `xiom.libtorch` `865c6d2a`,
`xiom.tensorflow` `0f4bb6a5`, `xiom.blas` `bee07a38`, `xiom.gps`
`020b50ac` (records @ `ec548542`; allowlist 559->561; guard 561/552/9/0;
README/STATUS sync `c1d1d85d`; relays `-0042-bindings-2` +
`-2144-bindings-2` fixed; the openblas metadata fix rides a future 0.1.x
bump). **`xiom.miniaudio 0.5.0`** published as a single tag
`xiom-miniaudio/v0.5.0` (`7d83c1ed...`; run 39027702853; engine
`-2134-engine-2` fixed as delivered+shipped; bindings `-2324` fixed).
**In-tree v0.64.6 repin landed** (`d2ef7ec2`: COMPILER_VERSION + 566
records aligned; validate 566/0) -- the machine-wide wave is now mirrored
in this tree. Zero open bindings relay items; validate 696 green.

**UPDATE 2026-10-17 15:05Z (doorbell -- `eco-v0.1.195` + `.196` LIVE)**:
- **`eco-v0.1.195`** (owner-ordered; run 39039228850): `xiom.gguf` 0.1.4
  (`0dda8b2b...`; non-ASCII string values + byte/UTF-8 accessors),
  `xiom.http` 0.1.9 (`f7b0c30f...`; binary-safe bodies, jev dep),
  `xiom.pulse` 0.2.0 (`5cbf1ea8...`; hook seam + Server-token seam; PULSE
  `-1312-pulse` fixed; Station stage 2b unblocked). validate 571/0.
- **`eco-v0.1.196`** (ML/AI core tier + ORBITDB; run 39039898017): ops
  allowlist 561->564; `xiom.orbitdb` 0.2.1 (`c8fc6548...`; 160/160 x2 +
  db_crash 25/25 + mvcc/fault-sync green; `-1245-orbitdb` fixed),
  `xiom.numpy` 0.1.0 (`0eaa9185...`; Phase-3 complete 147/147),
  `xiom.llm` 0.1.0 (`3c85e858...`; M3 303/303). Registry now carries the
  full ML core (arrow/openblas/pandas/jev/onnx/gguf/llm/numpy) + orbitdb.
- Remaining owner gates: jev S6/S8 + pandas sec.6. Lane: **NVIDIA backlog
  -> execution** (`8ec262b3`: 7 agents -- cuda-math/cudnn/tensorrt/nvenc/
  nvml-nvapi/optix/onnx-directml; AMD hardware-gated); real-accel wave
  landed (`0a87650f`: openblas real leg 42/42 x2 + arrow/pandas
  real-backend sync/prep; bindings validate 566/0). Zero open
  bindings-addressed relay items; validate 717 green.

Published through the window: `eco-v0.1.132`..`eco-v0.1.159` -- assimp 0.7.0,
glfw 0.3.0-0.5.0, vulkan 0.5.0 (`138`), ann 0.1.0 + stb 0.2.0 (`139`), sdl3
**0.7.0-0.16.0** (`142`-`152`), assimp **0.8.0** (`153`), miniaudio **0.3.0**
(`154`), meshopt **0.2.0** (`155`), ozz **0.3.0** + imgui **0.3.0** (`156`),
box2d **0.3.0** (`157`), meshopt **0.3.0** (`158`, `cbcd2ef7...`, 18:25:26Z),
meshopt **0.4.0** (`159`, `0e98c707...`, 18:36:32Z).
**Publish queue (packages): EMPTY** (jolt 0.2.0 m258-parked only).
**Pool drive complete + published**: miniaudio/meshopt/ozz/imgui/box2d all
re-verified on v0.64.3, each clearing a ROADMAP next item; meshopt Phase-3
items 1+2 additionally shipped (0.3.0 wrappers, 0.4.0 codec families).
**Assimp consumer mini-contract proposed + routed to engine**
(`packages/xiom-assimp/CONTRACT.md`; `-1811-bindings` -> packages fixed
routing -> `REL-20261011-1828` to engine, commit `9046b3d`).
**Compiler (staged build)**: owner-session re-verify (`-1801-bindings`):
B-13/B-14/B-15 fixed on staged `3b31599f`; B-16 stays assumed open;
fn-type mangling warning flagged; 1-arg handler restriction droppable at
release+pin. v0.64.4 archive NOT yet released (v0.64.3 latest as of 18:44Z);
all six batches m261-m271 staged (`-1731`).
Lane tree tip: handoff commit on top of `8b541db5` (clean; all pushed).
**Doorbell 21:00Z**: engine NEW ask **`REL-20261011-2015`** (Vulkan mini-RHI)
-- **ACKED** on the item (7-step order + acceptance shape); our
`-1113-bindings` info item **CLOSED**; compiler `-1731` updated (v0.64.4
wave staged; **pin pending the stdlib tag**); packages lane handed off
("batch lane drained", `-1828` awaiting engine adoption). **Owner session
(parallel, same worktree)**: fixed **B-19 package-side** (sdl3 0.16.1, suite
59/59 x2; items `-2048-bindings` -> packages, `-2048-bindings-2` -> compiler;
packages acked batch 62), acked the mini-RHI with planned batches
0.6.0-0.12.0 (`-2048-bindings-3`, `-2100-bindings`; engine acked 21:03Z and
will start `engine/rhi/vulkan.xi` on delivery), and **launched the Vulkan SDK
100 program** (`docs/checklists/vulkan-sdk-100.md` + the `730e926b` plan;
`sdk100-*` agent worktrees for dxc/glslang/shaderc/slang/spirv-tools/
spirv-cross/spirv-reflect).
Compiler findings filed this window: **B-13** (fn-param C-callback marshal=0),
**B-14** (`return;` in explicit `-> Unit`), **B-15** (Vec[fn] element call
>=2 args -> ()), **B-16** (`ffi.ptr_write_*` at base+N silently loses
writes), **B-17** (raw-pointer arithmetic `as_mut_ptr() + N` yields WILD
addresses; root cause of B-16 -- repro `docs/repro/bindings-pilot/ptr-arith/`),
**B-18** (regression in compiler fde5548e: bare-name -> fn-typed extern
param makes the enclosing fn return 0 early, silently -- repro
`docs/repro/bindings-pilot/cb-abi/probe8_name_fnparam.xi`), **B-19** (regression in fde5548e: `SDL_Init` through the loader cast-call returns
success but initializes nothing -- sdl3 suite 51/52 vs 52/52 -- repro
`docs/repro/bindings-pilot/sdl3-init-arg/`), **B-20** (v0.64.3 int-to-ptr
sanitization: foreign pointers cast to Int read zeros through the loader
idiom; C-copy-into-owned-slot is the shipped shape -- repro
`docs/repro/bindings-pilot/foreign-ptr-read/`).
Engine P3 asks: blit (0.8.0), typed input (0.6.0/0.9.0), wheel + audio
stream (0.12.0), capture streams + query (0.13.0), pointer/relative mouse
(0.14.0), live joystick (0.15.0), drag-drop payloads (0.16.0) -- ALL
PUBLISHED. Engine P4 ask DELIVERED: assimp 0.8.0 file-import + mesh-data
getters, relayed to packages (batch 54) and noted to engine
(`REL-20261011-1655-bindings(-2)`). Upstream sources live in `E:\repos`
(Vulkan-Headers, SDL3, FFmpeg + pool).

**HANDOFF NOTE (context limit, 2026-10-11 18:45Z)**: this session ran
17:19Z-18:45Z and shipped batches 56-61 -- meshopt 0.2.0 (vendored v1.2 +
bridge + 30/30), ozz 0.3.0 (clip pipeline + combine.py restored), imgui
0.3.0 (context handles + ini hygiene), box2d 0.3.0 (joint motors), meshopt
0.3.0 (owned-buffer wrappers) and meshopt 0.4.0 (codec families) -- plus
the assimp consumer mini-contract (proposed, then routed to the engine) and
the ledger records for the whole pool sweep (all five pool packages
published, `eco-v0.1.153`-`159`). The compiler staged-build re-verify
(B-13/14/15 green on `3b31599f`) came from the parallel owner session.
Everything is committed and pushed; the worktree is clean; the relay inbox
is clean. Pick up from RESUME HERE below -- the doorbell cron is
per-session, so re-arm it first.

## RESUME HERE (handoff, 2026-10-11)

**Lane**: bindings. Worktree `E:\xiom-packages\bindings`, branch `bindings`.
**Relay bus**: `xiom-lang/xiom-relays` at `E:\xiom-lang\xiom-relays` (shared
clone: stage ONLY your own item files). The two working rules are in
`docs/BINDINGS-LANE.md` section 12.

### State
- **CURRENT (2026-10-12 19:31Z)**: **GRAPHICS DRIVE**: Vulkan 0.6.0 LIVE
  (`eco-v0.1.163`; engine window + scene tiers green); **OpenGL 0.4.0
  LIVE** (`eco-v0.1.164`; full generated core-4.6: 656 cmds + 1358 consts;
  656/656 resolved x2); **DX12 0.1.0 + 0.2.0 SHIPPED**
  (`b353ed9c`/`f8992491`, records `c8dd1876`/`be22717d`): runtime
  `d3d12.dll` + COM/vtable ABI from the pinned DirectX-Headers `461ef513`;
  generated full `d3d12.h` surface (90 interfaces / 355 method wrappers /
  1162 consts / 9 free fns; 22 struct-value skips documented in
  `docs/gen_manifest.json`), suite 12/12 x2 (device, queue+release,
  root-signature serialize 88B); publish requested **0.2.0**
  (`REL-20261012-1930-bindings`; new name -> ops scope). **SDK100
  COMPLETE**: spirv.headers live (`eco-v0.1.165`; 81 releases). **v0.64.4
  pin**: `44a41aea` verified + slot byte-identical (556/556); repin 532 +
  validate 532/0 (`1f850919`); archive wave + compiler reply (`f8fe214`;
  release-check `b235493`); B-10 newly green; B-16/B-17/B-20/B-11/B-05/
  B-07/B-21 red by design. **B-22 OPEN** (glfw lift parked; witness
  `probe9_castcall_param.xi`). Ops clobber rules in force (bindings filed
  the no-install data point on `-1852-ops`). Worktree clean; relay tip
  `d439ee8`; next = DX12 0.3.0 wave.
- **Earlier state (2026-10-12 14:15Z)**: **v0.64.4 ARCHIVE WAVE COMPLETE** (this
  session): pin `44a41aea...` sha256-verified + slot byte-identical
  (556/556); `COMPILER_VERSION` + repin 532 + validate 532/0 (`1f850919`);
  all fixes VERIFIED (B-13/B-14/B-15/B-18/1904/B-12; B-19 package-side
  green; B-10 newly green -- odbc `alloc` control spins on v0.64.3,
  5/5 green on v0.64.4); not-in-wave rows stay red by design
  (B-16/B-17/B-20/B-11/B-05/B-07); B-02 re-verified 16/16; jolt 4/4 x2
  (m258 native `--cxx-standard 17`). Suites: sdl3 59/59 + glfw 37/37.
  Compiler reply `f8fe214` (`REL-20261012-1400-bindings`; release-check
  rows filled; `-3` B-10 moved to verified; `-1815` archive-verified).
  Batch 63 = jolt 0.2.0 + vma 0.3.0 + dxc 0.3.0 live in `eco-v0.1.161`;
  **batch 64 = `eco-v0.1.162` (15:00Z doorbell)**: the eight SDK100
  first-publishes + sdl3 0.17.0 LIVE; only `xiom.spirv.headers` held
  (dotted vs dash scope; `REL-20261012-1405-packages`). Engine `-1348`
  (vulkan version allocation) + xvector `-1417` (accelerator mirror)
  answered (`REL-20261012-1500-bindings(-2)`).
  Session ledger updates 13:57Z/14:05Z/15:00Z above; the paste prompt
  below is refreshed. NEXT: workaround lift. Worktree clean; relay tip
  `f8fe214` + this doorbell's reply commit.
- **Earlier state (2026-10-11 21:05Z, doorbell tick)**: batches 31-61 + the owner
  session's 62 (sdl3 0.16.1 B-19 fix) relayed; **ALL PUBLISHED through
  `eco-v0.1.159`** (meshopt 0.4.0 live 18:36:32Z); **publish queue EMPTY**
  (jolt m258-parked only). Pool sweep complete + published; meshopt
  Phase-3 1+2 shipped (0.3.0/0.4.0); assimp contract routed to engine
  (`-1828`). Compiler v0.64.4 wave staged -- **pin pending the stdlib tag**;
  staged-build re-verify green for B-13/14/15 (`-1801`), B-16 open.
  **Engine Vulkan mini-RHI `-2015` ACKED** (item status at 21:01Z + owner
  items `-2048-3`/`-2100`; engine acked 21:03Z, will build
  `engine/rhi/vulkan.xi` on delivery); **owner session drives the Vulkan SDK
  100 program** (checklist + `sdk100-*` agent worktrees). `-1113-bindings`
  closed. Relay: `-1553`..`-2100` items sent.
- **Doorbell 00:00Z (2026-10-12)**: relay re-checked -- processed the two
  open policy asks: **`-2131` ACKED** (upstream-first adopted; 100% coverage
  target; G6/G7) and **`-2141` FIXED** (fold `fbb773fd`; first applied
  instance `packages/xiom-vulkan/PROVENANCE.md`); relay commit `bf2fea1`.
  `eco-v0.1.160` (batch 62, sdl3 0.16.1, live `f2d99b9e...` @21:08:25Z)
  was already recorded here; no eco notes past `160`. `-2302` non-ASCII bug
  was already fixed+acked (`19f9d86`/`-2355`). v0.64.4 archive still not on
  GitHub (v0.64.3 latest; tag imminent per packages' 21:10Z note).
- **Doorbell 03:00Z (2026-10-12; resumed 13:26Z)**: packages acked our
  `-0000-bindings` (fold + validate-red confirmation) with "reporter may
  close" -> **closed** (`1e9eee0`). No items created today addressed to
  bindings and none open past the long-delivered engine/compiler rows; no
  eco notes past `0.1.160`; **v0.64.4 still not on GitHub** (v0.64.3
  latest 13:26Z). No action taken beyond the close.
- **Pickup (2026-10-11 18:47Z, new session)**: origin==local `f236925d`,
  worktree clean; relay re-checked -- no items newer than `-1731`; packages
  tip `555b501e` (75 eco releases; no notes past `eco-v0.1.159`); `status
  validate` 524 packages, 0 errors; compiler v0.64.4 archive NOT yet on
  GitHub (v0.64.3 latest; six-batch stack + release commit staged locally
  in the compiler worktree, origin/main still batch 1). Doorbell re-armed
  `wku_12c49bd1b001pDrS40ht1pQSup` (`0 */3 * * *`, next 21:00Z) + one-shot
  archive watch `wku_12c4c9f76001rgGvHSYUGPWn2b` (~19:49Z). Pre-archive
  baselines re-run on the v0.64.3 slot: `ptr-slot-write` B-16 still red
  (`ptr_write_sum=11`, `byte_index_sum=66`), `ptr-arith` B-17 still red
  (`d0=-16448`, `d1=-26864`; Int-typed `d12=12` exact) -- witnesses fresh
  for the archive post-pair.
- **Pre-archive baseline sweep (2026-10-11 19:32Z, v0.64.3 slot)**: cb-abi
  probes match the recorded v0.64.3 column -- `probe` control=42/direct=42/
  stored=20 + GLFW shapes (calls=1 key=65 sc=33 action=1 mods=5,
  close_win=4242); `probe2` relay=0 (B-13 pre); `probe3` fnparam=42,
  `probe6` reg 42/63, `probe8` full output (after=42, callee-after=42,
  main-after r=7) -- all B-18 shapes GREEN pre; `probe4` 0/42/42; `probe5`
  all 0; `probe7` 2x T001 (B-14/15 pre). B-20 `foreign-ptr-read`: C-side
  1065353216/1073741824, XIOM 0/0 (red pre). B-07 `ffi-alias-shadow`: 2x
  T001 `c_strlen` (red pre). Addendum 19:45Z: B-19 `sdl3-init-arg` green
  pre (`elapsed=100 init=1 w_all=16384`, SDL3 resolved from the Vulkan SDK
  dir); 1904 `glfw-fp-return` red pre (`advance_ms=0`, `after_set99_ms=0`,
  `opacity_x1000=262416000`, `gettime_ms=0`; probes run from
  `packages/xiom-glfw/tests/` with `--link user32`). Suite/heavy addendum
  19:58Z: sdl3 suite **59/59** (incl. `init: SDL_WasInit(TIMER|EVENTS)
  reflects the flags` PASS -- the suite grew past the README's 52; B-19's
  post witness is that line), glfw **37/37** (time check SKIP
  pre-1904-fix; `--link user32` auto), B-11 `vulkan-slot-recycle` red pre
  (`inside: a=3 b=0 c=1 rc=0`; vma bridge from the package, no extra
  args). B-05/B-10 `alloc-guard-spin` (20:10Z, after the archive watch):
  compiled clean (`compile_exit=0`, `-o` to temp); watchdog run on
  v0.64.3 = still spins (15 s wall cap hit, ~1 core, flat ~4-4.5 MB, no
  output after "before"). Archive-day procedure validated: use the
  tracked `background_process` runner (monitor + `stop` kills the tree);
  one direct `Start-Process` attempt escaped the harness kill -- if that
  recurs, kill by exact PID. Remaining pre-run gap: jolt (needs m258+)
  -- runs at the archive.
- **Archive watch fire (19:50Z)**: v0.64.4 still not on GitHub (v0.64.3
  latest; compiler origin/main still batch 1); relay gained `-1856`
  (stdlib->xvector), `-1904-pulse` (pulse A/B on m271: batch-5 witness
  green, SIGILL 1615 still red), `-1928`/`-1940` (jolt scope confirmed
  LIVE on both eco entries -- "repin + port x2 + publish when the archive
  lands"; no staging needed). None addressed to bindings; next check
  `wku_12c83f8e1001LZ9U7eXCfvp5xt` (~21:20Z), doorbell 21:00Z.
- **B-19 fixed package-side (20:48Z, pre-archive)**: the compiler's m274
  wave diagnosed B-19 as a package-side declaration (`SDL_WasInit` cast
  `fn(Int) -> UInt8`, but `SDL_InitFlags` is Uint32; m263+ honors declared
  return widths -> 16384 masked to low byte 0). Fix `c2d3330f` + record
  `7722369a` (sdl3 **0.16.1**): cast -> `UInt32`, doc + README updated,
  repro probe corrected + resolution note; evidence on the pin = probe x2
  `elapsed=100 init=1 w_all=16384`, suite **59/59 x2**. Relayed to packages
  (`REL-20261011-2048-bindings`) and closure evidence to compiler
  (`-2048-bindings-2`). **Engine Vulkan mini-RHI ask answered**
  (`REL-20261011-2015-engine` -> `-2048-bindings-3`): priority order
  adopted (sync/recording -> buffers -> pipelines -> textures -> depth ->
  visible-window swapchain via SDL3 `SDL_Vulkan_CreateSurface` ->
  acquire/present), queued after the archive wave; B-11 workaround shapes
  stand (B-16/B-17 not in the wave). Compiler stack PUSHED (origin
  `87c6ca3c`, m254-m274; m274 fixes B-18; B-19 resolved package-side);
  archive expectations per packages SESSION: B-13/14/15/B-18 green,
  B-16/B-17 stay red, packages rows `-4`/`-5`/`-6`/`-7`/`-2100` re-run.
- **SDK100 program progress (21:53Z)**: Vulkan slice COMPLETE on the branch --
  `xiom.vulkan` full surface: 845 commands (852 registry; 7 vulkansc twins
  excluded) in generated `src/cmds_01..08`; 5,983 constants (`consts_1..12` +
  float + str); 1,343 struct sizes + 6,905 member offsets
  (`struct_meta_1..19`) from a clang offsetof dump; loadability suite PASS x2
  (`unresolved_relevant=0`; 766/766 advertised-surface; 75 platform/SC
  exclusions; 4 unadvertised ext verified) + existing RHI suite 22/22;
  `PROVENANCE.md` + `docs/COVERAGE.md`; commits
  `8cf95606`/`c18912b1`/`513f57b3`/`fbb773fd`. Wave-1 agent packages
  integrated (`7c5fc26f`, re-validated in-lane): spirv-tools 39/39 (67/67
  bound; 55/55 exported resolved), spirv-cross 20/20 (169/169), spirv-reflect
  40/40 (45/45 vendored), glslang 29/29 (61/61), slang 20/20 (277/277), dxc
  20/20 (128/128). Relayed: `-2231` (batch to packages) + `-2230` (findings
  to compiler); CLEANUP rows appended centrally. Wave-2 in flight: sdl2,
  sdl3-100, vma-100, spirv-headers; shaderc still building. Owner
  upstream-first policy folded (`fbb773fd`). B-21 filed (`-2140`: `&mut` of
  a struct-return/Result-payload temp crashes codegen; repro
  `docs/repro/bindings-pilot/mut-of-struct-return/`).
- **SDK100 wave-2 complete (23:20Z)**: five slices integrated (`905fe004`,
  all coordinator-validated in-lane): xiom.sdl2 16/16 + resolved=**844/844**;
  xiom.sdl3 full surface resolved=**1270/1270** (74 additive modules; B-19
  fix preserved; existing 59/59 green); xiom.vma full bridge
  bound=**72/72** (volk + vulkan_win32 vendored); xiom.spirv-headers
  **2,385 consts** (oracle byte-identical to the pinned clone);
  xiom.shaderc **45/45** + suite 17/17. **Program matrix COMPLETE**
  (`docs/SDK100-COVERAGE.md`, `616e21f5`). Relayed: `-2305` (wave-2 batch)
  + `-2320` (findings: `Vec.with_len` heap-buffer-overflow HIGH; foreign-C++
  exceptions vs confined-call machinery; unqualified 4-segment const
  imports). Publish confirmations tracked via the doorbell.
- **Latest batch 61 (2026-10-11)**: `xiom.meshopt` **0.4.0 -- codec family
  (Phase 3 item 2)**: index SEQUENCE codec (byte-exact order; contrast
  pinned with the triangle-list codec, which rotates corners), quat filter
  (16-bit; decode -> 4 int16 in place; err <= 100 micro), exp filter
  (16-bit mantissa, separate; decode -> float bits in place; rel err <=
  200 micro), color filter (8-bit YCoCg; decode -> 4 unsigned bytes; err
  <= 0.02), and the meshlet codec (encode meshlet 0: 45 refs / 64 tris ->
  142 bytes; typed 4/3 decode; refs byte-exact, triangles rotation-
  invariant -- the meshlet triangle coder rotates corners to line up
  next-bits). Suite: **38/38 x2**. feat `e50b3f99` + record `bd059406`;
  relayed `REL-20261011-1829-bindings` (supersedes the just-published
  0.3.0 on the same lineage).
- **Latest batch 60 (2026-10-11)**: `xiom.meshopt` **0.3.0 -- owned-buffer
  wrappers (Phase 3 item 1)**: `meshopt_remap_mesh` (duplicate-vertex merge;
  indices rewritten in place, remapped vertices copied into an owned out
  slot, unique count out), `meshopt_optimize_mesh` (in-place cache optimize
  with the triangle multiset verified before write-back), and
  `meshopt_simplify_mesh` (simplify toward a target count at a relative
  error budget; result list into an owned out slot; count + error out),
  over caller-owned `Vec[UInt8]` byte meshes (f32 positions stride 12, u32
  indices). `meshopt_fill_grid` is the deterministic fixture filler. The
  bridge's triangle-set comparison went vector-backed (512-triangle cap
  removed). Suite: **33/33 x2**. feat `557dc39e` + record `89b48f07`;
  relayed `REL-20261011-1818-bindings`.
- **Latest batch 59 (2026-10-11)**: `xiom.box2d` **0.3.0 -- joint motors
  (pool drive)**: bridge gains `b2probe_revolute_motor` (2.0x0.2 bar
  hinged at the origin, gravity off, motor-only torque -> w settles at the
  motor speed; the joint angle pins Box2D's [-pi,pi] wrap: 4 - 2*pi ~
  -2283 milli) and `b2probe_prismatic_motor` (slider on +x under gravity
  -> translation ~1999 milli while y is held at ~1999). Joint defs stay
  inside C; the milli ABI is unchanged. Suite: **7/7 x2**. feat `56b7e31c`
  + record `0e4604f7`; relayed `REL-20261011-1754-bindings`.
- **Latest batch 58 (2026-10-11)**: `xiom.imgui` **0.3.0 -- long-lived
  context handles (pool drive)**: 4-slot registry of `ImGuiContext*` with
  1-based handles (`imgui_context_create/frame/destroy` + count/frames);
  window state persists across separate XIOM calls -- the suite drives 5
  frames on one handle (first hidden, auto-size settles by frame 4, frames
  4/5 identical) and checks registry counts across create/destroy of two
  handles. Two bridge lessons pinned (SPEC/AUDIT): `ImGui::CreateContext`
  returns the new context but only makes it current when none is -- bind
  the RETURN value with `SetCurrentContext` (GetCurrentContext() aliased
  every slot to the first context -> NewFrame assertion); windows settle
  over ~4 frames. Hygiene: probes now set `io.IniFilename = 0` /
  `io.LogFilename = 0`; the tracked `imgui.ini` artifact is removed and
  ignored. Suite: **7/7 x2**. feat `bb69c92a` + record `05c30982`; relayed
  `REL-20261011-1750-bindings`.
- **Latest batch 57 (2026-10-11)**: `xiom.ozz` **0.3.0 -- clip pipeline +
  bundler restoration (pool drive)**: bridge builds a two-track
  RawAnimation (child y 1 -> 3 over 1 s), converts via the offline
  AnimationBuilder, samples at ratio 0.5 (y == 2) and 1.0 (y == 3) through
  a `SamplingJob::Context` (hand-computed pose checks); library TU gains
  raw_animation/raw_animation_utils/animation_builder offline sources. The
  SPEC-referenced amalgamation bundler is now in-package
  (`tools/combine.py`) and was validated by regenerating both pinned TUs
  **byte-identically** before the additions (quoted includes resolve
  including-file-dir first, then roots; LF; prints sha256). New pins:
  ozz_all.cpp 772,432 B `126b6b55...`; ozz_bridge.cpp 409,991 B
  `730d5d10...`. Suite: **5/5 x2** (math, skeleton, LocalToModelJob, clip,
  aggregate). feat `926efce7` + record `1b1389e2`; relayed
  `REL-20261011-1740-bindings`.
- **Latest batch 56 (2026-10-11)**: `xiom.meshopt` **0.2.0 -- pool drive
  (vendored)**: meshoptimizer v1.2 vendored verbatim (commit `f843aae0`,
  20 C++ TUs + header + LICENSE; per-file SHA256 in SPEC §2; extraction
  from the clone object store, every staged blob byte-identical to
  upstream HEAD) compiled with the suite via `port.args.json` plus the
  reviewable bridge `src/meshopt_bridge.cpp` (integer/scalar ABI; B-20:
  C copies into XIOM-owned slots/buffers). Suite rewritten from the
  assert-only compile checks to **30/30 x2** real-library runs (16
  constants + 12 probes + 2 owned-buffer): remap 6->4, ACMR drops after
  optimizeVertexCache, analyzeVertexFetch, simplify 600->~100 @<=5%,
  index codec (rotation-invariant triangle-set equality -- upstream
  encodeIndexBuffer rotates corners by design), vertex codec byte-exact,
  stripify set-preserving, fp16 0x3C00/0xC000, sphere r=1414 on the 2x2
  square, meshlets conserve 98 tris, oct error <=0.02, in-place optimize
  preserves the set with checksum change. Legacy 72/72 re-verify recorded
  first (`157094bc`); building takes ~9 s (21 TUs). feat `5a45d3bd` +
  record `08bcde04`; relayed `REL-20261011-1733-bindings`.
- **Latest batch 55 (2026-10-11)**: `xiom.miniaudio` **0.3.0 -- encoder +
  file round trip** (pool drive, package 1): `ma_encode_roundtrip` encodes
  a 64-frame 8 kHz mono s16 tone to a temp WAV with `ma_encoder`, re-decodes
  it with `ma_decoder_init_file`, compares every sample, and removes the
  temp file -- device-free and deterministic; results read through scalar
  getters (B-20 rule). Ports: **6/6 x2** (0.11.25; playback=9/capture=4;
  decode 16/1/8000/s16; round trip sample-exact + temp removed). feat
  `9f1c1bcd` + record `ab8dc89e`.
- **Latest batch 54 (2026-10-11)**: `xiom.assimp` **0.8.0 -- file import +
  mesh-data getters** (engine P4 asset pipeline): `assimp_import_file(path)`
  (Triangulate + FlipUVs; 1-based registry, 4 live imports),
  `assimp_release`, mesh counts/has_uvs, `assimp_mesh_positions`
  Vec[Float64] xyz, `assimp_mesh_uvs` Vec[Float64] uv, `assimp_mesh_indices`
  Vec[UInt32].  Structural: the bridge COPIES into XIOM-owned slots read
  byte-indexed -- foreign-pointer round-trips read zeros on v0.64.3
  (**B-20** documented with a minimal host repro; T006 requires the owned
  conversion anyway).  New fixture `tests/fixtures/quad_uv.obj` (package
  `.gitignore` gained `!tests/fixtures/*.obj`).  Ports: **16/16 x2** native
  (125 TUs, ~4-5 min/build).  feat `fa372e07` + record `a76bdef4`.
- **Latest batch 53 (2026-10-11)**: `xiom.sdl3` **0.16.0 -- drag-drop
  payload decode**: NO new DLL symbols -- pure-buffer `SDL_DropEvent`
  accessors (windowID @16, x @20, y @24, source ptr @32, data ptr @40)
  with C-string copies (`""` when NULL) + `sdl3_str_c_ptr` for synthetic
  structures; the test carries REAL C-string pointers for source+data and
  decodes both exactly, and a NULL-payload event decodes safely.
  DLL-independent, so the absent baseline rises **4 -> 5 checks**. Ports:
  **59/59 x2** present + **5/5 x2** absent + **7/7 stability**. feat
  `ba7e5ebc` + record `16e94e8b`.
- **Latest batch 52 (2026-10-11)**: `xiom.sdl3` **0.15.0 -- live joystick
  path**: 10 symbols -- `SDL_OpenJoystick`/`SDL_CloseJoystick`,
  `SDL_JoystickConnected`, `SDL_GetJoystickName`, `SDL_GetJoystickAxis`
  (16-bit result sign-extended explicitly), `SDL_GetJoystickButton`,
  `SDL_SetJoystickVirtualAxis/Button`, `SDL_Attach/DetachVirtualJoystick`;
  `SDL_VIRTUAL_JOYSTICK_DESC_SIZE` = 136 (x64 pin; `version` =
  sizeof(desc) per `SDL_INIT_INTERFACE`). The desc slot is byte-indexed
  (B-16/B-17); name pointer must outlive the joystick (documented).
  **No SKIP**: the suite attaches a hardware-free virtual pad, opens it
  through the real read path, feeds axis0=16384 + button1, reads them
  back exactly (name `xiom-virtual-pad`, connected=true), then detaches.
  Ports: **58/58 x2** present + **4/4 x2** absent + **7/7 stability**.
  feat `fbd60b6e` + record `9f771f88`.
- **Latest batch 51 (2026-10-11)**: `xiom.sdl3` **0.14.0 -- pointer capture
  + relative mouse**: 5 symbols -- `SDL_GetGlobalMouseState`,
  `SDL_GetRelativeMouseState` (button mask + two f32 out-params into one
  owned slot per pointer, B-17 discipline), `SDL_SetWindowRelativeMouseMode`,
  `SDL_GetWindowRelativeMouseMode` (SDL3 relative mode is per-window),
  `SDL_CaptureMouse`. Proof: global state reads the live cursor (1684,386),
  relative state 0,0/mask 0, per-window relative-mode round trip
  **true/true/false/false**, capture toggle callable (enable=false on a
  hidden window per the foreground-only doc; disable=true). Ports:
  **56/56 x2** present + **4/4 x2** absent + **7/7 stability**. feat
  `dd878a98` + record `bfd7cd74`.
- **Compiler re-verify (2026-10-11, fde5548e m263-m265)**: rebuilt the
  toolchain (`cargo build --release` in `E:\xiom-lang\xiom`, HEAD
  `fde5548e`) and re-ran the lane's probes vs the pinned v0.64.3 slot.
  **FIXED**: B-13 param/local/cast-call routes (probe2 `relay=42` was 0;
  probe4 `42/42/42`; probe5 `42/42/42`), 1904/B-12 fp returns
  (`after_set99_ms` 0 -> **99000**, `advance_ms` 0 -> 311, `opacity_x1000`
  262416000 -> **1000**), B-14/B-15 (probe7 now COMPILES and runs, r=1 --
  element call true + `early(0)` OK). **REGRESSIONS on the fix build**:
  **B-18** -- bare top-level fn NAME as a fn-typed extern arg makes the
  enclosing function return 0 early, silently (probe8_name_fnparam.xi:
  old full output `after=42`/`callee r=7`; new `before/main-before/
  callee-before/main-after r=0`); **B-19** -- `SDL_Init(16385)` via the
  loader cast-call returns 1 but initializes NOTHING (`SDL_WasInit(0)` 0
  vs 16384; sdl3 suite **51/52** vs 52/52; `SDL_Delay(100)` arg passes,
  so not general arg loss). glfw suite 37/37 on both (needs
  `--link user32` from port.args.json when run manually). Both filed to
  compiler; workarounds stay until the next fix ships.
- **Latest batch 50 (2026-10-11)**: `xiom.sdl3` **0.13.0 -- capture streams
  + stream query**: 4 symbols -- `SDL_GetAudioStreamData`,
  `SDL_GetAudioStreamAvailable`, `SDL_ClearAudioStream`,
  `SDL_GetAudioStreamFormat`; `SDL_AUDIO_DEVICE_DEFAULT_RECORDING` (pull
  mode via `sdl3_open_audio_recording_stream`, sharing the 0.12.0 open
  path). Capture proof: default recording device (wasapi) opens, resumes,
  drains **8192 B** of PCM (avail=11520, pause/clear OK); format query
  src=dst=33056/2ch/48000Hz; available/clear determinism (push 4096 ->
  clear -> queued=0 avail=0 read=0). Ports: **52/52 x2** present + **4/4
  x2** absent + **10/10 direct-run stability**. feat `d07355ca` + record
  `06e9db74`, then the **B-17 native fix** `68e79444` + record `1c239a2a`.
  Along the way **B-17 found + filed + worked around**: raw-pointer
  arithmetic (`as_mut_ptr() + N`) compiles to a WILD address on v0.64.3
  (even +0; delta -30,929,264 for +12 in one probe); the first build's
  `SDL_GetAudioStreamFormat(stream, slot, slot + 12)` made SDL write the
  dst spec into unowned memory -> nondeterministic STATUS_HEAP_CORRUPTION
  (c0000374/ntdll) on ~30-50% of runs of the SAME binary; bisect:
  no-0.13.0 block 11/11 stable, format call alone 7/11 crash,
  open+destroy without calls 11/11 stable; fix = one owned slot PER
  out-param (two 12-byte slots for the format pair, two 4-byte slots for
  mouse state). The same fix corrected the shipped 0.9.0 `SDL_GetMouseState`
  y out-param (wild since batch 46; readback stayed 0; two-slot sentinel
  probe showed both out-params land). **B-17 is the ROOT CAUSE of B-16**
  (the "lost" +4/+8 `ptr_write` calls land at wild addresses). Repro
  `docs/repro/bindings-pilot/ptr-arith/` (pure XIOM); relayed
  `REL-20261011-1512-bindings-2`; batch item `REL-20261011-1512-bindings`.
- **Batches 45-48 (2026-10-11, compact)**: 45 sdl3 **0.8.0** display blit
  (`sdl3_update_texture`/`sdl3_render_texture`/`sdl3_set_render_vsync`;
  demo probe green; 44/44 x2; feat `3d7f6f3e`); 46 sdl3 **0.9.0** mouse +
  window contract (typed WINDOW_RESIZED via watch; 46/46 x2; feat
  `e712c4ca`); 47 sdl3 **0.10.0** audio/joystick enumeration + ABGR8888 +
  8888 note (wasapi/9/4; 48/48 x2; feat `b876d853`); 48 sdl3 **0.11.0**
  full source-generated constant tables (~190: full event enum, window
  flags, keymods, pixel formats; 48/48 x2; feat `f3feb77d`).
- **Latest batch 49 (2026-10-11)**: `xiom.sdl3` **0.12.0 -- push audio
  streaming + mouse wheel**: open default playback device (NULL callback),
  put PCM from an XIOM buffer, resume/pause/queued/destroy; wheel
  accessors (x @24/y @28/direction @32/mouse @36/@40) + MOUSEWHEEL
  constants (engine ask 1411-2). Along the way **B-16 found + filed**
  (ffi.ptr_write at base+N silently loses writes: repro
  `docs/repro/bindings-pilot/ptr-slot-write/`, ptr_write_sum=11 vs
  byte_index_sum=66; byte-indexed slot writes required). Ports: **49/49
  x2** (7680 B silence pushed, queued=7680, resumed, device-paused=false)
  + absent **4/4 x2**. feat `5d73b10a` + record `dc1f03c7`; B-16 relayed
  `REL-20261011-1437-bindings-3`.
- **Latest batch 44 (2026-10-11)**: `xiom.sdl3` **0.7.0 -- filesystem
  basics**: base/pref/current-dir paths (BasePath SDL-owned; others
  SDL_free'd after copy), create/remove directory, `SDL_GetPathInfo`
  (`Sdl3PathInfo`, `SDL_PATHTYPE_*`). Round trip under
  `%APPDATA%\xiom-lane\sdl3-conformance\` (created + removed by the
  suite; ops-hygiene compliant). Ports: **43/43 x2** + **4/4 x2** absent.
  feat `7317c433` + record `3e209d89`.
- **Latest batch 43 (2026-10-11)**: `xiom.sdl3` **0.6.0 -- displays +
  video modes + keyboard state**: SDL_GetDisplays/primary/name/bounds/
  usable-bounds/current+desktop mode, SDL_GetKeyboardState (+SDL_free of
  the array), SDL_GetModState, SDL_GetKeyboardFocus. Rect out-params via
  owned slots; display list + mode struct via ptr-reads (read direction);
  VIDEO-init SKIP for headless CI. Ports: **36/36 x2** (count=2, primary
  in list, name "C24F390", 1920x1080 @0Hz, usable 1920x1032, numkeys=512
  idle, lock-key-aware mod state) + **4/4 x2** absent. feat `55db02e5` +
  record `5a5485b7`.
- **Latest batch 42 (2026-10-11)**: `xiom.sdl3` **0.5.0 -- event filter +
  watch callbacks**: SDL_SetEventFilter / SDL_AddEventWatch /
  SDL_RemoveEventWatch over fixed top-level dispatchers + 1-arg handler
  registries (B-13 pattern; event copied into an owned 128-byte buffer via
  our memcpy -- B-11 path avoided). Two new findings: **B-15** (`Vec[fn]`
  element calls with >=2 args type the result as (), so handler shapes are
  1-arg + userdata getters) and **B-14** (`return;` rejected in explicitly
  `-> Unit` fns -- structured ifs instead); repro
  `docs/repro/bindings-pilot/cb-abi/probe7_element_units.xi`, items
  `REL-20261011-1121-bindings-2`. Ports: **27/27 x2** present (filter keep:
  calls=4 last=768 userdata=119; reject: push refused; watch
  non-consuming + removal) + **4/4 x2** absent. feat `b58f8071` + record
  `42059924`.
- **Wrap/fix cycle (2026-10-11 11:10Z)**: packages wrapped batches 38/39/
  40/41 on main: `eco-v0.1.136` (glfw 0.4.0), `eco-v0.1.137` (glfw 0.5.0,
  post-fixes), `470e13f3` (vulkan 0.5.0 + sdl3 0.4.0). Fixes `5a213f30`
  (glfw) + `799fceaa` (sdl3) carried into the lane by fast-forward
  `7869df27 -> 470e13f3`; lane re-verification post-merge: glfw **37/37 x2
  + absent 3/3**, sdl3 **24/24 x2** (reply `REL-20261011-1113-bindings`).
- **Latest batch 41 (2026-10-11)**: `xiom.sdl3` **0.4.0 -- SDL_Event
  decoding layer**: owned 128-byte buffer + typed accessors (header,
  keyboard, mouse motion/button, window data1/data2, f32 `_bits` +
  `sdl3_f32_from_bits`); offsets pinned by grep against the release-3.4.8
  header, byte-identical in the local release-3.2.10 clone; synthetic
  KEY_DOWN injected through the real queue (consume semantics). Ports:
  **24/24 x2** present + **4/4 x2** absent (decode runs DLL-free; absent
  reproduced by filtering the VulkanSDK dir out of PATH). No new DLL
  symbols. feat `df8cdf30` + record `9c1326ea`.
- **Latest batch 40 (2026-10-11)**: `xiom.vulkan` **0.5.0 -- render pipeline
  (build order #3)**: render pass (clear, TRANSFER_SRC final) + graphics
  pipeline from embedded SPIR-V (`src/shaders/tri.vert|frag` -> glslc ->
  `tools/embed_spv.py` -> committed `.inc`), 3-vertex draw via
  `gl_VertexIndex`, `vkCmdCopyImageToBuffer` readback, present. Pixel proof:
  center rgb(0,255,0) (triangle), bottom-left sample rgb(25,51,76) (0.1/0.2/0.3
  clear). Pinned against Vulkan-Headers 1.4.350 (draft corrections:
  TRANSFER_READ=0x800, VIEW_TYPE_2D=1; fixed 0.4.0's misnamed
  TRANSFER_DST layout 6->7). Ports: **22/22 x2** + skip-path per run; feat
  `2b08eb96` + record `7a941c1f`.
- **Compiler pin is now v0.64.3** (installed slot + `COMPILER_VERSION`);
  runs record `v0.64.3`.
- **Latest batches**: 33 vulkan 0.3.0 RHI bring-up (device/queue + real
  submit; 15/15 x2); 34 stb 0.2.0 (5/5 x2); 35 jolt 0.2.0 (4/4 x2 on the
  m258 local build); 36 sdl3 0.3.1 (22/22 x2; engine-3 fixed; B-11
  addendum); 37 **vulkan 0.4.0 WSI** (hidden Win32 window + surface +
  swapchain + clear/present; **18/18 x2**; feat `432eae2f`, record
  `27cc1b6b`); 38 **glfw 0.4.0** (gamma/cursors/icon/joystick-gamepad/
  loader hook; 105/124 exports; **32/32 x2**; feat `ad1cacc3`, record
  `949238bd`).
- **Upstream sources cloned into `E:\repos`** for source-truth binding:
  Vulkan-Headers (`vulkan-sdk-1.4.350.0`), SDL3 (`release-3.2.10`), FFmpeg
  (shallow) + the pool (box2d, imgui, JoltPhysics, lzfse, meshoptimizer,
  miniaudio, ozz-animation, phonon, steam-audio, GameNetworkingSockets,
  crypto-algorithms, bbolt, DiskANN, faiss, gin, h11, redb, sqlite,
  sqlite-vec). Godot is NOT a binding target (owner); mine its `thirdparty/`
  only for useful bits.
- **Owner instruction for this window**: bind from the cloned upstream
  repos ("100% coverage" drive); sources can be deleted once we're good.
- **Published**: batches 21-29 -> `eco-v0.1.122`..`eco-v0.1.130` (openssl
  0.2.0, sqlite 0.3.0, box2d 0.2.0, imgui 0.2.0, vma 0.2.0, cuda 0.2.0,
  assimp 0.2.0/0.3.0/0.4.0/0.5.0 in `eco-v0.1.127`/`128`/`129`/`130`).
- **Batch 27** (`xiom.assimp` 0.3.0, glTF2): merged, verified 5/5 x2, wrapped
  (`fffdc3f9`, guard 508/491/17/0); **published** `eco-v0.1.128` (run
  `38067436940`; live sha256 `5b30c6a8...`, 16:23:47Z; confirmed in packages
  SESSION 16:30Z).
- **Batch 28** (`xiom.assimp` 0.4.0, COLLADA; 96 TUs): merged (packages tip
  `154d1344`), port 6/6 x2, **published** `eco-v0.1.129` (live sha256
  `aeb44d02...`); bus item `REL-20261010-1623-bindings` fixed.
- **Batch 30** (`xiom.assimp` 0.6.0, BLEND; poly2tri contrib; 123 TUs; 8/8
  x2 with the committed `BlenderDefault_248.blend` fixture: 1 mesh / 24
  vertices / 6 faces): feat `c9513a2b` + record `14fc56e7` (+ provenance note
  `1524ad68`); bus item `REL-20261010-1824-bindings` **acked by packages**
  (`61d4016`), publish pending.
- **Batch 31** (`xiom.assimp` 0.7.0, OFF + SMD; 2 new TUs, 125 total; 10/10
  x2 -- minimal in-memory docs, 1 mesh / 3 verts / 1 face each): feat
  `dcbe6991` + record commit; relayed per bus item
  `REL-20261010-1837-bindings` (supersedes the 0.2.0-0.6.0 items).
- **Batch 32** (`xiom.glfw` 0.3.0 engine surface; 85+5 exports, no
  port.args -- pure dynamic loader): hints, window lifecycle + attrs,
  events, input polling, monitors + video modes, clipboard, time,
  GL-context basics, Win32 native (HWND), Vulkan helpers. **28/28 x2**
  positive with the official 3.4 win64 DLL; absent shape stays green. feat
  `d2e0d02c` + record commit; relayed to packages. Design dodges four
  v0.64.2 codegen landmines (fp cast-call returns -> **B-12**; Vec-of-struct
  extraction; Result[Vec] payload; Result[Float] payload) -- see the package
  AUDIT/SPEC. Engine items `-1834-engine-2/-3`, `-1841-engine` acked;
  **Vulkan mini-RHI is the next batch**; ffmpeg growth waits on a
  shared+dev build request (`C:\ffmpeg` on the box is static-only).
- **Batch 33** (`xiom.vulkan` 0.3.0 engine RHI bring-up; build order #1):
  `src/vk_rhi.c` C bridge (self-contained ABI decls; scalars only --
  B-11/B-12 discipline): instance with `VK_KHR_surface` +
  `VK_KHR_win32_surface` enabled, discrete-preferred device pick, graphics
  queue family, logical device + queue, command pool/buffer begin/end +
  **real `vkQueueSubmit`/`vkQueueWaitIdle`**. **15/15 x2** on the RTX 3070
  Ti (loader 1.4.350, ~9.4 s/run); absent/no-driver shapes stay green. Gotcha
  learned: resolve DEVICE-level pointers via `vkGetDeviceProcAddr` -- the
  1.4.x loader rejects a device passed to `vkGetInstanceProcAddr` (VUID;
  fast-fail). feat `93943978` + record commit; relayed to packages. Next:
  build order #2 (Win32 surface + swapchain + present) via the glfw HWND.
- **Batch 34** (`xiom.stb` 0.2.0: vendored stb_image + stb_image_write at
  commit `2c980bb5...`; one TU + probe bridge; PNG 85-byte encode +
  pixel-exact decode (checksum 8400) + 1x1 red BMP decode; **5/5 x2**):
  feat `a369fa52` + record commit; relayed with an ALLOWLIST-APPEND ask
  (packages acked; ops scope ask `REL-20261010-2301-packages`; publish
  pending the appends); closes the engine lane's image-codec wishlist
  (`REL-20261010-1900-packages`).
- **Batch 35** (`xiom.jolt` 0.2.0: vendored Jolt v5.6.0, 25 TUs + bridge
  shim, tree `ea20c2d1...`; **4/4 x2** on the locally built m258 compiler
  with `--cxx-standard 17` threaded in `port.args.json` -- drop settles at
  479 milli asleep, impulse vx=4995, ~34 s/run): feat `00cfc0c8` + record;
  bus item `REL-20261011-0008-bindings` (merge after the m258 archive is
  canonical; archive re-verdict of `-7`/`-1815` rides with it).
- **Batch 36** (`xiom.sdl3` 0.3.1: `SDL_PushEvent` in the loader +
  headless synthetic-event proof -- inject a user event (0x8000) into a
  128-byte slot, pump, `poll(NULL)` consumes; **22/22 x2** with SDL 3.4.8,
  absent shape green): feat `b12a1d77` + record; engine ask
  `REL-20261010-1834-engine-3` **fixed** with the present/missing coverage
  list; **B-11 addendum**: the slot-read corruption reproduces here with
  no GPU/driver context (minimal reproducer filed as
  `REL-20261011-0304-bindings`).
- **Batch 29** (`xiom.assimp` 0.5.0, FBX; 15 new TUs, 111 total; 7/7 x2):
  feat `a57cbd0b` (+ record commit); generator tree sha256 `dd05e67f...`;
  merged (packages tip `d96f4112`), **published** `eco-v0.1.130` (live sha256
  `c06a5131...`); bus item `REL-20261010-1655-bindings` fixed.
- **Open items from this lane** (release-check `compiler-v0.64.3` verdicts:
  `-6` B-02 **verified**; `-7` C++ passthrough **corrected to NOT fixed**
  (false-positive verdict; `REL-20261010-1815-bindings`); `-2/-3/-4/-5`
  reproduced and re-queued for v0.64.4): `-2` B-11 slot recycle, `-3` B-10
  alloc-name (m246 covers the plain local-fn shape only), `-4` B-07 alias
  shadow, `-5` B-05 guard spin, `-6` B-02 const resolver (verified), `-7`
  C++ standard passthrough (**not fixed -- jolt stays blocked**), `-8`
  guard-aware free, `-9` Vec sized buffer, `-10` dl out-param recipe, `-11`
  vendored-C consumer hook.
- **Incoming items**: `REL-20261010-1550-xvector-11` (accelerator gate, acked),
  `REL-20261010-1600-packages` (bus routing, acked).
- Detailed evidence: relay blocks + notes below; bus digests via
  `python tools/relay.py digest --to <lane>`.

### POLICY -- upstream-first + 100% coverage (owner, 2026-10-11)

POLICY (owner, 2026-10-11): upstream-first for ALL bindings work -- no code from
memory. For every library: clone the upstream SOURCE at a pinned commit into
E:\repos\<name> (shared, disposable) alongside the SDK/headers, study it, and
record packages/<pkg>/PROVENANCE.md (upstream, pin, license, derived vs
independent, vectors). License whitelist for anything copied: MIT/Apache-2.0/BSD/
ISC/zlib/PD/X11/Unicode/RFC-first; MPL/LGPL reference-only (no code/structure
copying); never GPL/AGPL/SSPL/Elastic (FFmpeg reference-only / system-lib
SKIP-only). COVERAGE TARGET = 100% of the target public API surface -- complete
export coverage, not partial (glfw 124/124 is the standard); SKIP-when-absent
stays a classified platform state, not a coverage gap. Register clones in
E:\repos\CLEANUP.md with a review-after date; delete only at quiet moments,
after ship+verify, with no open references and the owning lane's confirmation.
Canonical doc: docs/UPSTREAM-FIRST.md.

Relayed by packages as `REL-20261011-2131-packages` (ack) + the fold request
`REL-20261011-2141-packages`; lane gates G6/G7 updated in docs/BINDINGS-LANE.md.
Applied from the next touch onward (nothing shipped needs retraction).

### Next actions (ordered)
1. **Doorbell**: **RE-ARMED 18:47Z** (`wku_12c49bd1b001pDrS40ht1pQSup`,
   `0 */3 * * *`; next 21:00Z; the cron is per-session -- re-arm on each
   new session). Prompt = relay pull +
   process lane items + packages SESSION eco notes. Relay repo
   `E:\xiom-lang\xiom-relays`: sync with `git fetch origin` + compare --
   do NOT `git pull` ("Cannot fast-forward to multiple branches"); stage
   ONLY this lane's item files; only the REPORTING lane moves its own
   items (reply with new items). Inbox at 18:45Z: **clean** -- engine
   `1321`/`1411-2`/`1539` open but delivered/replied, xvector `1203` +
   engine `1153` acked by their lanes, compiler `1533` re-verified
   (B-18/B-19 filed), compiler `1731` (v0.64.4 staged, info -> re-verify
   on archive), compiler `1801` re-verify sent (B-13/14/15 green on the
   staged build), ops `1134` closed. Re-checked 18:47Z: still **clean**
   (nothing newer than `-1731`; `-1828` routed to engine, awaiting reply).
2. **Publish watch**: queue **EMPTY** -- everything through meshopt 0.4.0
   is live (`eco-v0.1.153`-`159`; meshopt 0.4.0 = `159`, `0e98c707...`,
   live 18:36:32Z); jolt 0.2.0 m258-parked only. sdl3 0.7.0-0.16.0 landed
   in `eco-v0.1.142`-`152`. Record new eco versions in the relay area of
   this file. The engine consumes only published packages -- if asked,
   nudge packages.
3. **SDL3 continuance** (source `E:\repos\SDL3` @ `release-3.2.10`;
   runtime/pin `release-3.4.8`): 0.4.0-0.16.0 shipped (batches 41-53;
   capture in 0.13.0, pointer/relative mouse in 0.14.0, live joystick
   reads in 0.15.0, drag-drop decode in 0.16.0). Remaining SDL3 candidate:
   POSIX soname (deferred -- no Linux CI target yet). Apply the 1-arg
   handler discipline (B-15), byte-indexed slot writes (B-16), **no
   pointer arithmetic (B-17: one owned slot per out-param; Int address
   math stays correct)**, and the **B-20 rule: never read through foreign
   pointers -- have C copy into an owned slot**. Ship each batch as: feat
   -> x2 (present + absent PATH-filtered) -> record -> relay -> ledger.
   Constant regeneration recipe: comment-strip + enum-parse + macro-eval
   vs the headers (ROADMAP item 1). **POOL DRIVE COMPLETE**: miniaudio
   0.3.0 + meshopt 0.2.0 + ozz 0.3.0 + imgui 0.3.0 + box2d 0.3.0 all
   re-verified on v0.64.3 and each cleared a ROADMAP next item (batches
   55-59); meshopt Phase-3 items 1+2 additionally shipped (0.3.0 wrappers,
   0.4.0 codec families; batches 60-61; all published). Remaining pool
   work is the package-local Phase 3 backlog (per each package's ROADMAP);
   pick the next item only when a consumer asks or the drift guard flags
   a re-pin.
4. ~~stb publish~~ **DONE** (`eco-v0.1.139`); batches 39/40/41 wrapped on
   main (`470e13f3`); vulkan 0.5.0 live (`eco-v0.1.138`).

### NEXT-SESSION PASTE PROMPT (copy the fenced block)

```
Bindings lane continuation -- seamless pickup (2026-10-16 11:30Z;
CONTEXT-LIMIT HANDOFF).  Everything this lane shipped is LIVE through
`eco-v0.1.185` (101 releases; our lifts glfw 0.6.0 + sdl3 0.20.0 in
.185; redis in .184; `.186` armed: transport+otel+template).

STATE (2026-10-16; trust the UPDATE stack + this block):
- Toolchain: v0.64.5 PINNED -- `XIOM_COMPILER=%LOCALAPPDATA%\xiom.new\
  bin\xiom.exe` (slot byte-identical to release bd71e2d3; 557/557);
  suites: `.\scripts\port.ps1 -Package <pkg> -TimeoutSec 300`.
- RE-VERIFY WAVE COMPLETE: all probes green EXCEPT B-29 (big-int
  bitops >= 2^31; boundary-arithmetic workaround stays shipped);
  B-30/B-31 FIXED; B-05 FIXED (re-vendored stdlib); glfw 0.6.0
  dispatcher lift + sdl3 0.20.0 filter/watch widening landed LIVE and
  published.  B-32 (B-26 residual inside the xiom.sqlite compilation
  unit; nested restore PARKED -- flat RowOutcome stays) ACKED by the
  compiler -> v0.64.6 fixer wave.  `-1309` CLOSED (dx12 Int-typed COM
  surface retained by choice).  v0.64.6 headline = darwin fix.
- ANDROID SDK100: 6 units LANDED, gate-green, validate 559/0:
  `xiom.android 0.3.0` (A1+A5+A2; export set 117; ALooper functional
  on-device) + `xiom.camera2ndk` + `xiom.aaudio` + `xiom.mediandk` +
  `xiom.android-sys` + `xiom.opensl` (0.1.0 each; on-device evidence
  in each package's docs/repro).  REMAINING: A3 input + A4 sensors
  (serial -- same package; next agent wave), A9 gl leg
  (generator-aware pass over xiom.gles), A11 JNI seam, A12 remainder;
  G1 compiler android target = owner call; G3 tokens asked
  (`REL-20261015-2210-bindings`; no artifacts needed -- system libs).
- ENGINE ASKS LANDED: `xiom.box2d 0.4.0` (A02; 26/26 x2) +
  `xiom.miniaudio 0.4.0` (A04; 27/27 x2, live WASAPI); publish
  requests filed (`REL-20261016-1125-bindings`) -- watch SESSION.md
  for confirmation, then packages relays engine adoption.
- QUEUED HIGH (accepted; NOT started): PULSE top-tier -- **TLS
  context binding** (`-2211-packages`; libssl-class loader composing
  with live xiom.tls + xiom.openssl) and **real brotli RFC 7932**
  (`-2211-packages-2`; libbrotli); `-2302` deduped into them.
  Clone-protocol prep first.
- METHODOLOGY: agent branches may sit on DIVERGENT bases -- land via
  path-scoped `git checkout <branch> -- packages/<dir>` + commit
  (NEVER wholesale-merge: old STATUS.json histories conflict); for
  edits to an existing package have the session rebase onto
  origin/bindings first, then re-run the suite, record, validate.

FIRST ACTIONS:
1. Re-arm the doorbell (`0 */3 * * *`): relay fetch + `python
   tools/relay.py view --lane bindings`; SESSION.md eco record; land
   any in-flight branch per the recipe above.
2. Relay sweep: read `-2211` x2 + `REL-20261016-1125` + replies;
   process (reply via new items; stage only this lane's files).
3. START THE NEXT WAVE (owner: continue): (a) real brotli (libbrotli;
   vendored C -- can start immediately as an agent wave, follow the
   clone-protocol prep pattern) + TLS context binding (libssl-class
   loader; sync naming/scope with packages first); (b) the Android
   A3/A4 agent wave on `xiom.android` (serial -- only if no
   xiom.android edit is in flight); then A9/A11/A12 remainder.
4. Standing rules: XIOM_COMPILER always the v0.64.5 slot; emulator
   `C:\Android\sdk\emulator\emulator.exe -avd Medium_Phone_API_36.0
   -no-window -no-audio -no-boot-anim -no-snapshot -gpu
   swiftshader_indirect`; provenance per touch; no silent failures;
   atomic commits + push with rebase-retry (shared worktree).
```

**SUPERSEDED prompt (2026-10-15 11:30Z, kept for history):**

```
Bindings lane continuation -- seamless pickup (2026-10-15 11:30Z;
CONTEXT-LIMIT HANDOFF.  Everything this lane shipped is LIVE through
`eco-v0.1.182` (98 releases).  OWNER DIRECTIVES for this session:
(1) the macOS/darwin legs fix is queued by the owner for the NEXT
compiler candidate (v0.64.5 is still HELD on the Cell[Int8]/aes
regression; watch `gh release list` for v0.64.5/v0.64.6);
(2) plan and START THE ANDROID work FIRST (read the compiler's reply to
the cross-target inquiry `REL-20261015-1109-bindings`, then the Android
prep wave + an NDK cross-build spike);
(3) any package bugs still open are expected to surface in the new
release's test runs -- no special sweep needed before it).

0. STATE (compressed; the UPDATE blocks + STATUS above carry full
   evidence):
   - **E-FAMILY COMPLETE** (engine's top ask, all delivered overnight):
     jolt 0.4.0 (E8 forces) -> 0.5.0 (E1 queries/E2 capsule/E7
     contacts+sensors) -> 0.6.0 (E3 joints/E6 convex+compound) -> 0.7.0
     (E4 soft bodies/E5 heightfield); suites 24 -> 67 -> 109 -> 159 x2;
     0.5.0/0.6.0/0.7.0 LIVE (`eco-v0.1.180`/`181`/`182`); engine relayed
     at each step (E1-E7 all wireable).
   - Live waves: codec A (`eco-v0.1.176`: jolt 0.3.0/zstd 0.3.0/meshopt
     0.5.0/ffmpeg 0.3.0); wave B first (`.177`: harfbuzz/basisu/spz);
     wave 2 (`.178`: opus/ogg/lz4/ktx2/vdb/phonon 0.3.0/fidelityfx/nis/
     dlss/xess/nrd/oidn); wave 3 + A05 (`.179`: ffmpeg 0.4.1 SHIP-only/
     jolt 0.4.0/ozz 0.4.0/sdl3 0.19.0/rtxgi+rtxdi/rpr/openpgl/stb 0.3.0/
     exr/photometrics); earlier: dx12 0.3.1 stable + 0.4.0, opengl
     0.5.0, gles 0.1.0, sdl3 0.18.0, sqlite 0.4.0/0.4.1 -- all LIVE.
   - **v0.64.5 HELD** (candidate regression Cell[Int8]/aes escalated
     pre-pin; tag signal sent then held; installed compiler still
     v0.64.4).  **On tag -> THE RE-VERIFY WAVE** + the 0.64.5
     release-check rows; the macOS/darwin legs fix rides the NEXT
     candidate (owner-queued).
   - Fixes staged for that wave: m277 B-22 + `-1403`; m279 B-16/17;
     m280 `-2230`; m281 B-23/24 + B-20 + `-0304` + `-1548`; m283 B-26 +
     B-25 green; m309 `-2320` (B-30 family, parts 2+3); m314-m321
     wide-int/constant-surface/parse families.  B-29/B-30/B-31 (our
     findings) still OPEN compiler-side.
   - **stdlib fixed B-27/B-28** (`45d0337`) but the v0.64.4 bundle
     carries a STALE snapshot (stdlib `-1401` note) -> workaround
     retirement gate = the pin that RE-VENDORS stdlib.
   - **RE-VERIFY WAVE at the tag (prepared; bundles ready)**: repros
     under `docs/repro/bindings-pilot/` -- null-literal (4 paths=0),
     ptr-read-stale (ffi_bad=0/400), foreign-ptr-read (C-matching),
     ptr-slot-write + ptr-arith (exact), cb-abi probe9 (42/42/42), sdl3
     synthetic-event raw-pointer readback, vulkan-slot-recycle (RTX
     host), nested-payload (2/2/2; then restore sqlite
     `Result[Option[SqliteRow]]` + retire `RowOutcome`), ptr-cast (cast
     fidelity; then revisit `Int`-typed dx12 COM params + close
     `-1309`), bigint-bitops (B-29), owned-slot-cast (B-30),
     const-alias-cycle (B-31), B-05 alloc-guard-spin (watchdog!; still
     red pre-lowering).  Then: **glfw 0.6.0 lift** (18 dispatchers +
     registries -> direct handoff), **sdl3 handler widening**,
     workaround retirement where re-verified.
   - Multi-session note: concurrent bindings sessions share this
     worktree -- fetch before every commit; retry pushes on races;
     keep ledger edits small (the doorbell fires on schedule).
0b. FIRST ACTIONS: (1) **read the compiler reply to
    `REL-20261015-1109-bindings`** (cross-target feasibility: android-
    arm64 effort, darwin/macOS leg ETA, apple-ios proximity, runtime
    gaps); (2) **plan/start the ANDROID work FIRST** per owner: a
    SKIP-safe prep wave (surfaces against the NDK headers --
    native_app_glue / ANativeWindow / ALooper / AAudio-OpenSL / asset
    manager; naming per the inquiry reply) + an NDK cross-build spike
    of one existing package (opus canary) once the compiler path is
    agreed; **SDK LOCATED: `C:\Android\sdk`, verified read-only
    (probe-grade evidence in the 11:35Z UPDATE): `ANDROID_SDK_ROOT`
    set; NDK r27b `27.1.12297006`; clang
    `--target=aarch64-linux-android26` smoke GREEN (ELF64/AArch64);
    headers in NDK sysroot `usr\include\{android,aaudio,SLES}`; glue
    at `sources\android\native_app_glue`; CMake+ninja
    `sdk\cmake\3.22.1\bin`; `ANDROID_NDK_HOME` per-invocation only**;
    (3) watch for the next archive (v0.64.5/v0.64.6): on tag
    run the RE-VERIFY WAVE (section 0) + the 0.64.5 release-check rows
    (+ macOS legs when the next candidate ships); (4) normal flow:
    relay sweep each doorbell, integrate finished agent deliveries,
    file per-package publish requests to packages with the standing
    engine relay.

1. RELAY: E:\xiom-lang\xiom-relays -- `git fetch origin` + compare (do
   NOT pull: "Cannot fast-forward to multiple branches"); `python
   tools/relay.py view --lane bindings`; process items addressed to
   bindings (only the REPORTING lane moves its own items; reply via new
   bindings items; stage ONLY this lane's files). Relay items must be
   PURE ASCII (`relay.py validate` is repo-wide). The parallel owner
   session works in this same worktree: `git fetch` + `git log` before
   every commit; if `.git/index.lock` exists another git op is running --
   wait, do not delete the lock.

2. Re-arm the session doorbell (the recurring task usually survives; if
   the session is new): `cron_create` schedule `0 */3 * * *`,
   prompt = "Bindings-lane doorbell. 1) E:\xiom-lang\xiom-relays: git
   fetch origin (not pull) + python tools/relay.py view --lane bindings;
   process new items (reply via new items; stage only this lane's files).
   2) Check E:\xiom-packages\packages\SESSION.md for new eco publish
   notes and record confirmed eco versions in BINDINGS-SESSION.md
   (commit+push if changed). 3) If nothing new, no action."
   Check-before-act (packages rule, 2026-10-13): if a doorbell prompt
   arrives twice for the same tick, verify state before acting again.

3. TRAPS / TOOLCHAIN:
   - Toolchain: `XIOM_COMPILER=%LOCALAPPDATA%\xiom.new\bin\xiom.exe`
     (read-only consumer). NEVER install/extract into the shared homes
     (`%LOCALAPPDATA%\xiom`, `xiom.new`, WSL `~/.local/share/xiom`) --
     the installer WIPES non-archive dirs there (ops `-1852-ops`); use
     lane-local dirs + `tools/home-snapshot.ps1`; restore from snapshot
     after a clobber.
   - **Android toolchain (READ-ONLY; owner's Unity/UE5/Flutter SDK)**:
     `C:\Android\sdk` (`ANDROID_SDK_ROOT` set user-level; `ANDROID_HOME`/
     `ANDROID_NDK_HOME` unset -- export `ANDROID_NDK_HOME` per
     invocation). NDK r27b `27.1.12297006` (clang 18.0.2 Android
     r522817b; `toolchains\llvm\prebuilt\windows-x86_64\bin`; r27 +
     26.3 also installed). Verified pattern (11:35Z smoke, green):
     `clang --target=aarch64-linux-android26 -fPIC -shared` ->
     ELF64/AArch64 `libsmoke.so` (5176 B). Headers in the NDK sysroot
     (`usr\include\android\` + `aaudio\AAudio.h` +
     `SLES\OpenSLES.h`); native_app_glue = `sources\android\
     native_app_glue\` under the NDK root (NOT sysroot -- it is a
     source; compile it into the app). CMake 3.22.1 + ninja at
     `sdk\cmake\3.22.1\bin`; platforms android-33/35/36. PATH java is
     1.8 -- use Android Studio JBR (`C:\Program Files\Android\Android
     Studio\jbr\bin\java.exe`) for cmdline-tools/sdkmanager IF ever
     needed; NO sdkmanager installs/upgrades (shared toolchain -- ask
     the owner).
   - Package traps: assimp `-TimeoutSec 600`; glfw needs `--link user32`
     when run manually; meshopt `-TimeoutSec 900`; opengl/dx12 suites
     compile their C bridges via port.args.json; heavy full-surface
     suites live at each package's tests/test_full_surface.xi. dx12 now
     needs `--link user32` plus eight --c-source files (dx12_probe,
     d3d12_calls, d3d12_structs, dxgi_probe, dxgi_calls, video_probe,
      video_calls, video_structs); suite slot reads are
      byte-indexed only; nullable C args use `dx12_null_ptr()` (B-23).
   - **B-25 discipline (v0.64.4)**: NEVER cast handles to pointers --
     `x as *UInt8` is NOT value-preserving (heap-shifted address at the C
     boundary; B-20 family).  COM object params are typed `Int` (C
     `void*`, exact; the dx12 generator emits `Int` for single-star
     `ID*` params) or int64 C-helper args.  Repro
     `docs/repro/bindings-pilot/ptr-cast/`.
   - sdl3 readback reproducers: SDL leaves `SDL_EVENT_POLL_SENTINEL`
     (0x7F00) ahead of pushed events -- do a bounded drain (poll(NULL))
     first, then the readback; live SDL3 comes from
     `C:\VulkanSDK\1.4.350.0\Bin` on PATH.
   - gles live runs: ANGLE pair (`libEGL.dll` + `libGLESv2.dll`) from an
     Electron payload on PATH (VS Code app dir works); without it the
     suite collapses to SKIP.  New clone row: `EGL-Registry` (`db3425b8`)
     in `E:\repos\CLEANUP.md`.
   - The shared `E:\xiom-lang\stdlib` is actively updated by another
     lane: module counts drift between runs and mid-wave commits can
     transiently break catalog builds (`mem.zeroed` signature mismatch
     seen 20:20Z). Retry minutes later; do not chase it as a package bug.
   - Upstream-first policy (POLICY block below): clone at pin +
     PROVENANCE.md per package; license whitelist; 100% export coverage
     is the standard; clones in E:\repos\CLEANUP.md (OpenGL-Registry
     `6af574a1`, DirectX-Headers `461ef513` active; DXGI oracle = Windows
     SDK 10.0.26100.0 shared headers, hashes in PROVENANCE.md).
     **Per-touch PROVENANCE rule (packages, 2026-10-12 20:36Z)**: it
     applies to EVERY package, new AND pre-existing -- any package
     merged/fixed/verified/published gets a `PROVENANCE.md` (upstream pin
     + license OR an explicit independent declaration) and carries 100%
     of its declared surface; audit via `scripts/provenance-audit.ps1`
     (report `docs/PROVENANCE-COMPLIANCE.md`; xiom.dx12 already
     compliant).

4. ORDERED TASKS after DX12: (i) **watch v0.64.5+** -- on ship run the
   RE-VERIFY WAVE (item 0.) + record the release-check rows; all
   publishes are confirmed live (last: sdl3 0.18.0);
   (ii) glfw 0.6.0 lift re-attempt + probe9 (B-22 fixed m277; run the
   wave first); (iii) sdl3 handler-shape widening (B-22-gated) -- the
   sdl3 readback item (Phase-2 #3) is DONE in 0.18.0 (B-11 addendum
   retired); (iv) **DONE -- GLES/EGL
   via ANGLE** (`xiom.gles` 0.1.0 shipped) + **WGL half DONE as opengl
   0.5.0**; dx12 0.4.0 command recording DONE (next candidates: barrier
   helpers/bundles/command signatures on ask);
   (v) optional Phase-3 / Phase-2 items only on consumer ask:
   imgui renderer backends now ASKED (`REL-20261012-2012-engine-4`;
   still blocked on a shared+dev imgui build), meshopt cluster pipeline,
   box2d broad-phase + contact events; ffmpeg stays blocked on a
   shared+dev build; (vi) **DONE -- PULSE SQL driver PUBLISHED as
   `xiom.sqlite` 0.4.0** (feat `4ba13167`, x2 21/21 on v0.64.4; LIVE in
   `eco-v0.1.174` sha256 `1e142acc...`; retrofits merged
   `5bd95448`/`80a06b6b`; PULSE co-verify pending `-1540-packages`;
   B-26 nested-payload filed with repro -- flat `RowOutcome` workaround).
   Vulkan mini-RHI is the OWNER session's lane (0.7.0-0.13.0 ladder;
   READ docs/checklists/vulkan-sdk-100.md before any Vulkan work;
   coordinate, do not duplicate; interop decision filed
   `REL-20261012-1800-bindings`; engine items -1948/-2012-2/-2012-4
   routed there).

Respect: B-11..B-25 discipline (byte-indexed slot writes; packed returns;
structured ifs; NO pointer arithmetic -- one owned slot per out-param;
never read through foreign pointers, have C copy into an owned slot
(B-20); B-21 = never take &mut of a struct-return/Result-payload temp;
B-22 = fn-typed PARAM values do not cross to C via cast-call positions;
B-23 = the `null` literal crosses to C as garbage (use `dx12_null_ptr()`);
B-24 = ffi out-slot reads after a C extern write are unreliable -- read
owned slots byte-indexed, keep pointer-edged flows on C return values;
B-25 = `Int as *UInt8` is not value-preserving -- never cast handles to
pointers; object params cross as `Int` / int64 C-helper args; B-26 = nested
enum payloads (`Result[Option[T]]`) corrupt struct-with-Vec values -- return
flat outcome structs, never Result-of-Option; B-27 = `ffi.write_u32_at`/
`write_u64_at` DROP their offset (use package-local byte-store writers);
B-28 = never `Vec.with_len` for FFI buffers (heap overflow; use
push-growth `owned_bytes`); B-29 = mask/compare big result codes
(>= 2^31) with boundary arithmetic, not bitwise ops; B-30 = one
`ptr as Int` cast per `unsafe` block; B-31 = one canonical home per
const name, no cross-module aliases).
Deliver batches as: feat -> x2 green -> record via scripts/status.ps1 ->
relay item to packages -> ledger update, all pushed; leave the worktree
   clean. TODO NOW: item 0b (watch v0.64.5+; on ship run the RE-VERIFY
   WAVE + the glfw/sdl3 lifts; else relay-driven only).

```
5. **ffmpeg** (blocked): needs a shared+dev build (`include/` + `av*.dll`);
   source clone at `E:\repos\FFmpeg` for headers/pins. On assets: dynamic
   loader, decode path (avformat/avcodec/swresample), same slot discipline.
6. **Open asks**: engine `-1834-engine-2` (vulkan growth; orders #1/#2/#3
   delivered; orders #4-7 gated on the slot-recycle fix), assimp consumer
   contract `REL-20261010-1900-2` -- **mini-contract proposed** (`CONTRACT.md`;
   relay `REL-20261011-1811-bindings`; packages to route to engine), stb
   scope `-1900` (delivered; live in eco-v0.1.139), `-1852` (assimp watchdog
   1800 s, done). Compiler `REL-20261011-1533` re-verified
   (B-13/1904/B-14/B-15 fixed; B-18/B-19 regressions filed); staged-build
   re-verify green (owner item `-1801-bindings`: B-13/14/15 on `3b31599f`,
   B-16 stays open); `REL-20261011-1731` (v0.64.4 stack staged) -> pin +
   full re-run when the archive lands. **Archive re-run checklist**
   (prepared 18:50Z; rows/fix refs in
   `release-checks/compiler-compiler-v0.64.3.md`, relay repo): pin
   (`COMPILER_VERSION` + installed slot), then (a) v0.64.3 release-check
   bindings rows B-11/B-10/B-07/B-05/B-02 + jolt re-verdict via `-1815`;
   (b) probes: `docs/repro/bindings-pilot/cb-abi/` (B-13/14/15/1904;
   `probe8_name_fnparam.xi` B-18), `ptr-slot-write/` (B-16 fresh),
   `ptr-arith/` (B-17), `foreign-ptr-read/` (B-20), `sdl3-init-arg/`
   (B-19); sdl3 suite (59 checks now -- B-19 post witness is the
   `SDL_WasInit(TIMER|EVENTS) reflects the flags` line; pre 59/59) + glfw
   37/37 (`--link user32`); jolt port x2 with `--cxx-standard 17`. Reply
   to compiler with evidence, then lift the workarounds the fixes cover.
   Engine
   `-1321`/`-1411-2`/`-1539`
   delivered (batches 47/49/54) and replied; the engine lane moves its own
   items.
7. **jolt**: parked on the m258 archive; on arrival: repin + merge tip
   `0aea531c` + port x2 + re-verdict `-1815` (then close).
8. Heavy runtimes (`xiom.onnx`/`xiom.opencv`) still need the native lane's
   go-ahead; accelerators stay gated on `xiom.vectors`.
9. **Full-coverage pool** (E:\repos): next candidates after/with SDL3 --
   miniaudio, meshoptimizer, ozz-animation, imgui, box2d (all have real
   sources now); generate/vendor + probe per the assimp pattern.
10. **Vulkan phase 4** (when the engine asks): compute pipeline + storage
    buffers, descriptors + textures, depth/stencil, frames-in-flight.

### Upstream-first policy (owner, 2026-10-11; folded per REL-20261011-2141-packages)

POLICY (owner, 2026-10-11): upstream-first for ALL bindings work -- no code from
memory. For every library: clone the upstream SOURCE at a pinned commit into
E:\repos\<name> (shared, disposable) alongside the SDK/headers, study it, and
record packages/<pkg>/PROVENANCE.md (upstream, pin, license, derived vs
independent, vectors). License whitelist for anything copied: MIT/Apache-2.0/BSD/
ISC/zlib/PD/X11/Unicode/RFC-first; MPL/LGPL reference-only (no code/structure
copying); never GPL/AGPL/SSPL/Elastic (FFmpeg reference-only / system-lib
SKIP-only). COVERAGE TARGET = 100% of the target public API surface -- complete
export coverage, not partial (glfw 124/124 is the standard); SKIP-when-absent
stays a classified platform state, not a coverage gap. Register clones in
E:\repos\CLEANUP.md with a review-after date; delete only at quiet moments,
after ship+verify, with no open references and the owning lane's confirmation.
Canonical doc: docs/UPSTREAM-FIRST.md (lane gates G6/G7 in docs/BINDINGS-LANE.md).

### Gotchas (learned this session)
- **Driver-heavy FFI**: return packed/scalar values; out-param slots can be
  recycled (B-11). Keep that ABI for new CUDA/Vulkan-style probes.
- **Direct `xiom --run` needs an ABSOLUTE suite path**: with a relative
  path, package-module discovery silently fails (`use xiom.<pkg>` resolves
  to nothing and every call is "undefined variable"). port.ps1 always uses
  absolute paths -- mimic that in ad-hoc runs.
- **Verification probes**: never use `if constexpr` to test "does this
  toolchain support C++17" -- clang accepts it as a C++14 extension
  (warning only). Use `std::string_view` / `std::align_val_t`.
- **Foreign-written buffer readback can be unreliable on this host**: the
  B-11 slot corruption reproduced in the SDL3 headless event probe (no
  driver context; recycled bytes after the call, e.g. 0x33323100). Prefer
  consume-semantics probes (`poll(NULL)`) when readback matters, and file
  readback evidence with the compiler lane.
- **Confined blocks**: no malloc/free (B-05); name locals `f_` (B-10);
  no enum payload reads if the compiler pin regresses (B-01).
- **Relays**: everything cross-lane goes through the bus now; file a
  `to: packages` info item per batch (template: branch tip + evidence +
  requested steps). BINDINGS-SESSION.md stays the lane work log.
- **Relay repo**: shared clone; `git add` only your own items. Never rewrite
  an item with PowerShell `Set-Content -Encoding UTF8` (BOM breaks front
  matter); use the write tool.
- **port.ps1 output**: `Write-Host` bypasses the pipeline; capture with
  `*>&1 | Out-File`.
- **Vendored trees**: `vendor/** -text` byte pins; regenerate assimp with the
  generator, never hand-edit vendor files. System headers must never be
  basename-remapped (the generator has a skip list). On this Windows clone
  (core.autocrlf=true) the working tree is CRLF: extract vendored bytes from
  the object store (`git cat-file blob HEAD:<path>`) and verify each file
  with `git hash-object == git rev-parse HEAD:<path>` (meshopt 0.2.0
  pattern; `git archive` does NOT avoid the EOL conversion).
- **Index codec rotation**: `meshopt_encodeIndexBuffer` implicitly rotates
  triangle corners to match the edge FIFO (upstream README: use
  `meshopt_encodeIndexSequence` to preserve exact order); round-trip checks
  must be triangle-set/rotation-invariant, not byte-exact. The vertex codec
  IS byte-exact. `meshopt_computeSphereBounds` is an enclosing-sphere
  heuristic (7-axis seeding + expansion), not the minimal sphere: assert on
  point sets where it is exact (2x2 planar square -> center 1,1, r=sqrt(2),
  i.e. 1414 milli).
- **ImGui contexts**: `ImGui::CreateContext` returns the new context but
  only makes it CURRENT when none is -- always bind the return value with
  `SetCurrentContext` (using `GetCurrentContext()` aliases every registry
  slot to the first context; it surfaced as a shared pointer and a
  "Forgot to call Render()" NewFrame assertion). Windows settle over ~4
  frames (first hidden, auto-size adjusts), and `io.IniFilename` /
  `io.LogFilename` must be nulled or every run rewrites `imgui.ini` in the
  CWD. Upstream null backends keep only per-context io flags, so multiple
  live contexts work if every call makes its context current.
- **Box2D revolute angles wrap**: `b2RevoluteJoint_GetAngle` returns the
  RELATIVE angle wrapped to [-pi, pi] (b2RelativeAngle), so a 4 rad
  integration reads back as 4 - 2*pi ~ -2283 milli; assert the wrapped
  value. The prismatic `GetTranslation` is not wrapped. Joint defs stay
  inside the bridge; milli ABI unchanged.
- **B-12: floating-point RETURNS through fn-pointer cast calls are broken**
  on v0.64.2/v0.64.3 (f64 -> 0, f32 -> garbage). Never rely on fp returns
  from casts; fp OUT-params via XIOM slots are fine. Repro:
  `docs/repro/bindings-pilot/glfw-fp-return/`; item
  `REL-20261010-1904-bindings-2`; glfw value checks carry labelled SKIPs.
- **B-13: fn-typed PARAM values cannot cross into C** (cast to Int -> 0,
  re-passed to extern fn-typed param -> 0, copied to a local -> 0, boxed in
  a struct field -> 0). Bare top-level fn names, locals initialized from
  names, and dynamic-loader cast-call args all marshal correctly. Callback
  bindings use: one fixed top-level dispatcher per event whose address goes
  to C + a `Vec[fn]` registry of user handlers (m130 element ABI). Repro:
  `docs/repro/bindings-pilot/cb-abi/`; item `REL-20261011-1055-bindings-2`.
- **Raw IEEE-754 bit patterns are signed Ints**: a `bits: Int` contract of
  `>= 0` traps on every negative float (sign bit set). Use `requires: true`
  for bit-pattern params (`f64_from_bits` fix `5a213f30`,
  `tests/probe_neg_f64.xi`); the same class applies to any readback that
  can go negative (cursor positions left of/above the window, joystick
  axes).
- **Bracket-scan hygiene**: the v0.64.3 surface parser accepted 7
  `Vec<UInt8>` signatures in `sdl3.xi` (compiled + suite green), but the
  canonical form is `Vec[UInt8]` -- packages normalized them (`799fceaa`).
  Keep the square-bracket form in new code.
- **Ops hygiene (REL-20261011-1134-ops, to: all)**: never delete/downgrade
  the shared toolchain homes; destructive tests go against an isolated
  XIOM_HOME + lane-local extraction and are announced with a to: all item.
  Lane audited compliant (`REL-20261011-1149-bindings`): Remove-Item only
  touches lane-local build/report artifacts; xiom.ps1 resolves the
  installed toolchain read-only.
- **B-14/B-15 (v0.64.3, filed + repro'd)**: a `Vec[fn]` ELEMENT call with
  >= 2 args types its result as `()` at use sites (statement-position calls
  silently discard -- glfw dispatchers were unaffected; handler shapes that
  NEED a result must be 1-arg, e.g. `fn(Vec[UInt8]) -> Bool`); and bare
  `return;` in explicitly `-> Unit` fns is a type error (use structured
  ifs). Repro: `docs/repro/bindings-pilot/cb-abi/probe7_element_units.xi`;
  item `REL-20261011-1121-bindings-2`.
- **B-16 (v0.64.3, filed + repro'd)**: `ffi.ptr_write_*` at a NON-ZERO
  offset into an XIOM slot silently loses the write (base write survives);
  byte-indexed slot writes are the reliable path (the lane's B-11
  discipline covers this). Repro:
  `docs/repro/bindings-pilot/ptr-slot-write/`; item
  `REL-20261011-1437-bindings-3`.
- **Lock keys**: `SDL_GetModState` reports lock bits (NumLock 0x1000 etc.)
  from the physical keyboard -- assert only the non-lock mask (0x0FFF)
  when checking "idle".
- **Vec-of-struct element extraction AVs** (`mons[0]`); use `Vec[Int]`
  handles + raw byte buffers (glfw monitors/video-modes pattern).
  `Result[Vec[...]]` and `Result[Float32/64]` payload extraction also
  miscompile -- return small structs or decode bytes (pure bit-decode
  helpers `f32_from_bits`/`f64_from_bits` in glfw.xi).
- **Vulkan WSI gotchas**: resolve DEVICE-level entry points via
  `vkGetDeviceProcAddr` (1.4.x loader VUID-fast-fails a device through
  `vkGetInstanceProcAddr`); the logical device must enable
  `VK_KHR_swapchain`; `user32` must be linked (`port.args.json`
  `--link user32`); struct layouts pinned in SPEC against the cloned
  Vulkan-Headers tag.
- **Console buffering**: `io.flush_stdout` does not force a CRT flush, so a
  crash loses buffered output; use `io.append_line(path, tag)` markers for
  crash bisects (see the glfw WSI debug session in git history).
- **Parallel actor**: the owner's session also commits in this worktree on
  the same branch (merges from main included). Always `git fetch` +
  `git log --oneline` before committing and re-check the tree state.

### Commands
- Suite: `& scripts\port.ps1 -Package xiom.<name> [-Quiet] [-TimeoutSec N]`
  (repo root; assimp needs >=600 s / 125 TUs with `--timeout 1800`; glfw
  ~15 s, now with `port.args.json` `--link user32` applied automatically
  (37/37 x2); vulkan ~25 s with its two C sources + `--link user32`
  (22/22 x2, triangle frames included)).
- Shaders (vulkan): `C:\VulkanSDK\1.4.350.0\Bin\glslc.exe <shader> -o
  <shader>.spv` then `python tools\embed_spv.py <name> <spv> src\<name>.inc`
  (run from `packages\xiom-vulkan`; regenerate + commit both in one change).
- glfw positive path: prepend the DLL dir:
  `$env:PATH = "C:\glfw-3.4.bin.WIN64\lib-vc2022;" + $env:PATH`.
- Shaders (vulkan #3): `C:\VulkanSDK\1.4.350.0\Bin\glslc.exe`.
- Bus (from `E:\xiom-lang\xiom-relays`): `git pull --ff-only` ->
  `python tools/relay.py view --lane bindings` -> `ack/fix/verify` ->
  commit+push only your files.
- Assimp regen: `python packages\xiom-assimp\tools\combine.py <upstream>
  packages\xiom-assimp` with the sparse clone at
  `C:\Users\lefte\AppData\Local\Temp\kilo\assimp-src\assimp` (recreate per
  SPEC: `git clone --depth 1 --branch v6.0.5 --filter=blob:none --sparse`
  + `sparse-checkout set code include contrib`).

## Relay bus onboarding (2026-10-10, owner rollout)

Cross-lane coordination now goes through the private `xiom-lang/xiom-relays`
repo (`E:\xiom-lang\xiom-relays`). Working instructions (also recorded in
`docs/BINDINGS-LANE.md` §12):

- At session start and before finishing any task: pull xiom-relays and
  process items addressed to this lane
  (`python tools/relay.py view --lane bindings`).
- Never edit another lane's item; open a new item instead.

Onboarded and acked (`REL-20261010-1548-bindings` to owner); 11 open
cross-lane items migrated (id map in `docs/BINDINGS-LANE.md` §12); the
recurring doorbell check is scheduled. Old docs keep closed history with
pointer headers.

## Relay (bindings -> native, per BINDINGS-LANE.md §6)

```
BINDINGS PUBLISH CONFIRM (graphics wave, 2026-10-12): xiom.vulkan 0.6.0
(SDK100 full surface, owner-approved bump) live in eco-v0.1.163;
xiom.opengl 0.4.0 (full generated core-4.6, 656/656 x2) live in
eco-v0.1.164; xiom.dx12 0.2.0 in eco-v0.1.167 and 0.3.0 (video slice,
31/31 x2) in eco-v0.1.168 -- allowlist through 520. Compiler findings
B-22 (fn-typed param at cast-call argument position marshals to 0; glfw
stays 0.5.0) and B-24 (ffi out-slot reads unreliable; dx12 repro) filed;
push-constant zero-read diagnosis delivered to the engine on -1948.
```

```
BINDINGS PUBLISH CONFIRM (batches 38-41 window): xiom.glfw 0.4.0 live in
eco-v0.1.136 (sha256 c393b079...); xiom.glfw 0.5.0 (124/124 exports --
callback ABI solved with a dispatcher+registry pattern) live in
eco-v0.1.137; the native fixes (f64_from_bits negative bit patterns +
layout-invariant key-name check) published as the eco-v0.1.138 fix
(0cd7bc00..., 11:16:09Z). xiom.ann + xiom.stb appends complete and live in
eco-v0.1.139 (ann 73f66ab5..., stb 41a205f7..., 11:39:26Z; allowlist
509 -> 511). xiom.sdl3 0.4.0 (a9006d4c... in the same eco-v0.1.138) and
0.5.0 filter/watch (a350dd46..., eco-v0.1.140, 11:46:56Z) are live. SDL3
growth continues: 0.6.0 displays+keyboard and 0.7.0 filesystem relayed
(batches 43/44); 0.8.0 display blit (engine ask REL-20261011-1153-engine:
texture upload + RenderTexture + vsync; demo probe green) relayed as
batch 45. xiom.btree 0.1.1 live in eco-v0.1.141 (other lane; noted).
```

```
BINDINGS BATCH 38: head=ad1cacc3 + this record commit; packages=xiom.glfw 0.4.0:
gamma ramps (raw 1536 B), cursors (standard + RGBA create/set/destroy), 1x1 RGBA window
icon, joystick/gamepad polling (axes/buttons/hats/names/GUIDs/state raw + button/axis
decoders + mapping update), glfwInitVulkanLoader hook -- 105/124 exports (the remaining
19 are the event-callback setters + initAllocator, queued 0.5.0 pending the C-callback
ABI). tests=32/32 x2 with the official 3.4 win64 DLL (v0.64.3 pin; ~7.5 s/run); gamma
ramp/cursor/icon exercised live; no joysticks on this box (enumeration path exercised).
needs=NONE.
```

```
BINDINGS BATCH 37: head=432eae2f + this record commit; packages=xiom.vulkan 0.4.0
(engine WSI, build order #2): hidden popup Win32 window (user32 via port.args --link),
VkSurfaceKHR, swapchain (FIFO; B8G8R8A8 preferred; caps extent; min+1 images), image
barriers + vkCmdClearColorImage, acquire/submit/present with binary semaphores; device
enables VK_KHR_swapchain when available (device lookups are null otherwise). tests=18/18
x2 on the RTX 3070 Ti: 320x240 format=44 images=3 + 3 real clear+present cycles.
Struct layouts pinned to the cloned Vulkan-Headers vulkan-sdk-1.4.350.0. needs=NONE.
```

```
BINDINGS PUBLISH CONFIRM (batches 31+32): xiom.assimp 0.7.0 (sha256
b5eb00f1...) and xiom.glfw 0.3.0 (present 28/28 x2 + absent shape) are live
in eco-v0.1.132 (run 38078757165). Batch 30 (0.6.0 BLEND) stays gated as
superseded -- its build is flaky under concurrent multi-lane compiles and
eco-v0.1.131 skipped it; 0.7.0 is the go-forward. Watchdog raised to 1800 s
in the assimp port.args (item REL-20261010-1852 acked).
```

```
BINDINGS PUBLISH CONFIRM (batch 33): xiom.vulkan 0.3.0 (engine RHI
bring-up) is live in eco-v0.1.133 (sha256 668b143b...; 21:07:37Z; native
15/15 x2 on the RTX 3070 Ti).
```

```
BINDINGS PUBLISH CONFIRM (batch 36): xiom.sdl3 0.3.1 (SDL_PushEvent +
headless synthetic-event pump) is live in eco-v0.1.134 (sha256
a779ae4b...; 10:33:55Z; native 22/22 x3 + sanitized-absent SKIP 3/3).
Jolt 0.2.0 stays gated (parked on the m258 archive).
```

```
BINDINGS BATCH 34 STATUS: xiom.stb 0.2.0 merged + native-verified (5/5 x2;
merge 07f5b9da, record 5fff08f9, wrap 8517c43e); publish pending the ops
allowlist appends (ann + stb, 509 -> 511; item REL-20261010-2301-packages).
```

```
BINDINGS BATCH 33: head=93943978 + this record commit; packages=xiom.vulkan 0.3.0
(engine RHI bring-up, build order #1): instance (VK_KHR_surface + VK_KHR_win32_surface
enabled), discrete-preferred physical-device pick, graphics queue family, logical
device+queue, command pool/buffer begin/end + real vkQueueSubmit/vkQueueWaitIdle.
tests=15/15 x2 on the RTX 3070 Ti (loader 1.4.350); absent/no-driver shapes stay green.
ABI note: device-level pointers resolved via vkGetDeviceProcAddr (1.4.x loader rejects a
device through vkGetInstanceProcAddr). next=build order #2 surface+swapchain+present.
needs=NONE.
```

```
BINDINGS BATCH 32: head=d2e0d02c + this record commit; packages=xiom.glfw 0.3.0
(engine surface; no port.args, pure dynamic loader; SKIP-when-absent): hints, window
lifecycle+attrs, events, input polling, monitors+video modes, clipboard, time,
GL-context basics, Win32 native (HWND), Vulkan helpers. tests=28/28 x2 positive with
the official 3.4 win64 DLL on PATH; absent shape stays green. New B-12 finding (fp
cast-call returns miscompiled; repro bundle docs/repro/bindings-pilot/glfw-fp-return/;
compiler item filed). pins=GLFW 3.4 header sha256 AA370985...; needs=NONE.
```

```
BINDINGS BATCH 31: head=dcbe6991 + this record commit; packages=xiom.assimp 0.7.0
(SUPERSEDES the assimp versions in the batch-26..30 bus items; merging the branch tip
gets everything): adds the OFF and SMD importers (2 TUs, now 125 TUs); tests=10/10 x2
(version major 6; in-memory OBJ/PLY/glTF2/COLLADA/ASCII-FBX/OFF/SMD docs; BLEND from the
committed 2.48 fixture; determinism); licenses unchanged (BSD-3-Clause vendored + package
MIT OR Apache-2.0); pins=tag v6.0.5 commit 392a658f... + generator + tree sha256
22d969e3... from the generator; port.args.json raises the compiler watchdog to 900 s
(--timeout 900) since the 125-TU link sits near the 300 s default under load; gate=G0..G5
OK; needs=NONE; watchdog >=600 s (~248 s observed both runs).
```

```
BINDINGS PUBLISH CONFIRM (batch 29): xiom.assimp 0.5.0 (FBX) is live in
eco-v0.1.130 (sha256 c06a5131...; merged as d96f4112; port 7/7 x2). Batch 28
0.4.0 stays in eco-v0.1.129.
```

```
BINDINGS v0.64.3 RELEASE-CHECK (sweep result, 2026-10-10): B-02 and the C++
standard ask VERIFIED (scratch reconstruction 16/16; cxx17 --c-source green);
B-05/B-07/B-10/B-11 reproduced on v0.64.3 and returned to acked with evidence
(queued for v0.64.4). Full detail: item histories + release-checks/
compiler-compiler-v0.64.3.md.
```

```
BINDINGS PUBLISH CONFIRM (batch 28): xiom.assimp 0.4.0 (COLLADA) is live in
eco-v0.1.129 (sha256 aeb44d02...; merged as 154d1344; port 6/6 x2); batch 27
0.3.0 stays in eco-v0.1.128.
```

```
BINDINGS BATCH 29: head=a57cbd0b + this record commit; packages=xiom.assimp 0.5.0
(SUPERSEDES the assimp versions in the batch-26/27/28 bus items; merging the branch tip
gets everything; 0.4.0 is already published in eco-v0.1.129 -- 0.5.0 is the go-forward):
adds the FBX importer option (ASCII + binary tokenizers compiled; 15 new TUs, now 111 TUs);
tests=7/7 x2 (version major 6; in-memory OBJ 1 mesh/3 verts/1 face; PLY 3 verts; glTF2
3 verts; COLLADA 3 verts; ASCII FBX 3 verts from a minimal FBX 7400 document; determinism);
licenses unchanged (BSD-3-Clause vendored + package MIT OR Apache-2.0); pins=tag v6.0.5
commit 392a658f... + generator (FBX added to ENABLED/ASSET_DIRS_BY_IMPORTER) + tree sha256
dd05e67f... from the generator; gate=G0..G5 OK; needs=NONE; port.args.json regenerated;
watchdog >=300 s (~143-145 s observed, 111 TUs).
```

```
BINDINGS PUBLISH CONFIRM (batch 27): xiom.assimp 0.3.0 (glTF2) is live in
eco-v0.1.128 (sha256 5b30c6a8...; 16:23:47Z; run 38067436940; guard
508/491/17/0); batch 26 0.2.0 stays in eco-v0.1.127. Batch 28 (0.4.0 COLLADA)
followed in eco-v0.1.129.
```

```
BINDINGS BATCH 28: head=494e0eb3 + this handoff commit; packages=xiom.assimp 0.4.0
(SUPERSEDES the assimp versions in the batch-26/27 bus items; merging the branch tip
gets everything): adds the COLLADA importer option (+ pugixml contrib), now 96 TUs;
tests=6/6 x2 (version major 6; in-memory OBJ 1 mesh/3 verts/1 face; PLY 3 verts; glTF2
3 verts; COLLADA 3 verts from a minimal 1.4.1 document; determinism); licenses unchanged;
pins=tag v6.0.5 commit 392a658f... + generator + tree sha256; gate=G0..G5 OK;
needs=NONE; port.args.json regenerated; watchdog >=300 s.
```

```
BINDINGS BATCH 27: head=10567ce2 + this handoff commit; packages=xiom.assimp 0.3.0
(SUPERSEDES the 0.2.0 in the batch-26 bus item; merging the branch tip gets both):
adds the GLTF importer option (legacy glTF + glTF2 + glTFCommon dirs; rapidjson
contrib), now 92 TUs; tests=5/5 x2 (version major 6; in-memory OBJ 1 mesh/3 verts/1
face; PLY 3 verts; glTF2 3 verts from an embedded base64 data-URI buffer; determinism);
licenses unchanged (BSD-3-Clause vendored + package MIT OR Apache-2.0); pins=tag v6.0.5
commit 392a658f... + generator (hardened: standard headers never remapped by basename --
rapidjson ships msinttypes/stdint.h; contrib include roots keyed per lib) + tree sha256
from the generator; gate=G0..G5 OK; needs=NONE; port.args.json regenerated; watchdog
>=300 s.
```

```
BINDINGS BATCH 26: head=56272e78 + this handoff commit; packages=xiom.assimp 0.2.0
(vendored v6.0.5 SUBSET generated by tools/combine.py: core Common/CApi/Geometry/Material/
PostProcessing + AssetLib OBJ/STL/PLY + zlib/minizip/earcut-hpp/utf8cpp; 89 TUs; export
API disabled; replaces the pre-pilot static-extern module); tests=4/4 x2 (version major 6;
in-memory OBJ import 1 mesh/3 vertices/1 face; in-memory PLY import 3 vertices;
determinism); licenses=BSD-3-Clause upstream (vendored) + package MIT OR Apache-2.0;
pins=tag v6.0.5 commit 392a658f... + generator (mirror + include rewriting + config/
revision synthesis) + generated-tree sha256 printed by the generator; gate=G0..G5 OK;
needs=NONE (grandfathered/allowlisted); port.args.json generated (89 --c-source entries);
watchdog >=300 s (compile ~90-150 s). Batch-ready info item filed on the relay bus
(xiom-relays) to packages per the new protocol.
```

```
BINDINGS BATCH 25: head=8027e46e + this handoff commit; packages=xiom.cuda 0.2.0
(CUDA driver-API probe replacing the pre-pilot Toolkit static-extern surface; NOTHING
vendored -- nvcuda.dll is a system component loaded at runtime, entry points via
GetProcAddress); tests=5/5 x2 (bogus-module SKIP classification; live probe: driver API
13040 (13.4), 1 device, 'NVIDIA GeForce RTX 3070 Ti', compute capability 806 (8.6), fresh
context + 64 KiB cuMemAlloc + HtoD/DtoH pattern round trip verified); licenses=package
MIT OR Apache-2.0 (the CUDA driver itself is proprietary, not vendored); pins=soname
nvcuda.dll + 11-entry-point set (_v2 stable ABI) + constants (CUDA_SUCCESS=0,
NO_DEVICE=100, attributes 75/76) + local sample (System32 nvcuda.dll 4,790,504 B,
version 32.0.16.1692, sha256 F2B550E8...); gate=G0..G5 OK; needs=NONE
(grandfathered/allowlisted); port.args.json present (one --c-source bridge TU;
packed/scalar returns per B-11).
WISHLISTS: PULSE/ORBITDB/XVECTOR re-fetched (10-10 revisions) -- no new binding asks
(PULSE served; ORBITDB pure-XIOM; XVECTOR accelerators still gated on the xiom.vectors
extraction); status recorded in docs/BINDINGS-PACKAGE-WISHLIST.md.
```

```
BINDINGS BATCH 24: head=db7cb594 + this handoff commit; packages=xiom.vma 0.2.0
(vendored VMA v3.4.0 header + pinned Vulkan-Headers vulkan-sdk-1.4.350.0 core replacing the
pre-pilot static-extern module; the only compiled TU is our bridge with VMA_IMPLEMENTATION;
the loader vulkan-1.dll is dlopen'd -- no SDK, no import library); tests=5/5 x2 (bogus-module
SKIP classification; live probe: heaps=3, 65536-byte host-visible allocation, mapped pattern
write/read-back verified); licenses=MIT (VMA) + Apache-2.0/MIT (Vulkan-Headers), nothing else
vendored + package MIT OR Apache-2.0; pins=VMA tarball sha256 822AA850... + Vulkan-Headers
tarball sha256 70270D10... + per-file table (vulkan_core.h matches the xiom.vulkan pin
6D2BA475...); one documented vendored rewrite (vk_mem_alloc.h: <vulkan/vulkan.h> ->
"vulkan/vulkan.h"); gate=G0..G5 OK; needs=NONE (grandfathered/allowlisted); port.args.json
present (one --c-source TU).
FINDING B-11 (NEW; runtime lane): out-param slot memory written by a Vulkan-heavy C call is
recycled before XIOM reads it (C volatile readback shows the correct value at return; XIOM
reads 0; byte vs u32 reads can disagree within one call; sentinels destroyed; only the
device+VMA+map sequence reproduces -- trivial/malloc/loader/instance-only variants are clean).
Workaround shipped: packed scalar returns (vmaprobe_run_packed). Repro bundle:
docs/repro/bindings-pilot/vulkan-slot-recycle/. Runtime lead: process-wide VEH + guard-arena
discard vs the NVIDIA loader (driver threads / internal SEH).
```

```
BINDINGS BATCH 23: head=2b3f4a66 + this handoff commit; packages=xiom.box2d 0.2.0 +
xiom.imgui 0.2.0; tests=box2d 5/5 x2 (vendored Box2D v3.1.1 C API via flat multi-source,
integer bridge: version 3.1.1, gravity (0,-10000) milli, resting drop settles at 499 milli
on a ground top at 0, impulse vx=5000 milli, drop determinism) and imgui 4/4 x2 (vendored
ImGui v1.92.9b core + upstream null backends; headless two-frame probe: version
1.92.9b/19291, steady frame 76 vtx/240 idx/1 cmd, empty frame 0, determinism);
licenses=MIT vendored (box2d + imgui only) + package MIT OR Apache-2.0;
pins=box2d v3.1.1 tarball sha256 FB6EF914... + per-file table (SPEC 2); imgui v1.92.9b
tarball sha256 21D8A0A5... + per-file table; gate=G0..G5 OK; needs=NONE (both
grandfathered/allowlisted); port.args.json present (flat multi-source; no -I, no generator).
BLOCKED ASK -- xiom.jolt v5.6.0 (pin 6E069EE0..., generator emits 25 per-directory TUs
with angle->quote include rewriting; the full library compiles under -std=c++17): the xiom
link line passes no standard flag and clang 22 defaults to C++14 (verified in
crates/xiom/src/lib.rs + a live probe), so C++17 libraries cannot build via --c-source.
Request: a --cxx-standard passthrough (or a default-standard bump). No jolt
module/tests committed until unblocked; the validated generator is staged at
packages/xiom-jolt/tools/combine.py.
```

```
BINDINGS BATCH 22: head=4e4d556a + this handoff commit; packages=xiom.sqlite 0.3.0
(B-01 workaround RETIRED: `SqliteValue` wraps the restored user enum `SqliteValueKind`
with payloads; same constructors/accessors for callers; obsolete `VALUE_*` constants
removed -- public type representation changed); tests=16/16 x6 fresh build cycles (the
B-01 signature was build-dependent; 2/6 bad on v0.64.0/v0.64.1) + full pin matrix x1
19/19 green on the official v0.64.2 (sqlite 16, zstd 8, lzfse 7, ozz 4, miniaudio 4,
sdl3 21, glfw 3, raylib 3, opengl 13, vulkan 10, dxc 3, directx11 5, directx12 5,
libpq 2, odbc 5, portaudio 2, phonon 3, openssl 4, ffmpeg 2); licenses=vendored SQLite
3.53.4 public domain + package MIT OR Apache-2.0 (unchanged); pins=SQLite amalgamation
hashes unchanged (SPEC §2) + compiler pin v0.64.2; gate=G0..G5 OK; needs=NONE
(allowlisted); NO port.args.json change. NOTE: 0.2.0 -> 0.3.0 bump of a live package --
publish is the native lane's call.
```

```
BINDINGS SWEEP v0.64.2: head=224e5c49 + this handoff commit; compiler=v0.64.2 (port.ps1 matrix used
the installed slot %LOCALAPPDATA%\xiom.new; direct probes used the repo-release build
E:\xiom-lang\xiom\target\release; repo pin still v0.64.1 -- native repin pending); matrix=19/19
binding suites green x1 via port.ps1 (sqlite 16, zstd 8, lzfse 7, ozz 4, miniaudio 4, sdl3 21,
glfw 3, raylib 3, opengl 13, vulkan 10, dxc 3, directx11 5, directx12 5, libpq 2, odbc 5,
portaudio 2, phonon 3, openssl 4, ffmpeg 2; absent/SKIP shapes where no DLL is on PATH);
findings=B-01 FIXED (6/6 enum-payload rebuilds all-true, m231; sqlite tagged-struct workaround
droppable once the official archive is installed/pinned), B-08 FIXED (program code 5 now printed
and exits 5, m228; new repro docs/repro/bindings-pilot/run-exit/), B-06 + B-09 still fixed
(up=1 down=1; win32-gl q1/q2 green, real GL 4.6.0), B-05 STILL OPEN (alloc-guard-spin: 10 s
watchdog kill, 8.7 CPU-s, flat 4.5 MB -- runtime side), B-10 STILL OPEN (odbc 3-way scratch
control: f_alloc 5/5 + my_alloc 5/5 green, alloc FAIL -- name-keyed redirect persists; f_ prefix
rule stays); B-02/B-03/B-04/B-07 not re-tested (no live trigger); workarounds kept (B-05, B-10,
sqlite enum until the repin); docs=BINDINGS-COMPILER-FINDINGS.md rows + repro README updated;
needs=NONE.
```

```
BINDINGS BATCH 21: head=224e5c49 + this handoff commit; packages=xiom.ffmpeg 0.2.0 (system-lib
generation loader replacing the pre-pilot 27-static-extern module; native decision BINDINGS-LANE
§11 followed: SKIP path only, nothing vendored); tests=default PATH SKIP 2/2 x2 (skip
classification via bogus sonames + probe SKIP) and Cascadeur 6.0 LGPL set on PATH 4/4 x2
(version FFmpeg 6.0; avcodec 60.3.100 / avformat 60.3.100 / avutil 58.2.100 / swresample 4.10.100;
license 'LGPL version 2.1 or later', gpl-configured false), plus Blender 7.1.1 GPL set 4/4
(second generation exercised; license 'GPL version 2 or later' reported as data, consistency
check) and partial-generation SKIP 2/2 each (OneDrive 8.x no swresample-6; DaVinci 6.x no
swresample-4 -- a generation must resolve all four libraries, never mixed across ABI generations);
licenses=LGPL-2.1+ upstream (nothing vendored or committed) + package MIT OR Apache-2.0;
pins=generation table (8.x 62/62/60/6, 7.x 61/61/59/5, 6.x 60/60/58/4, 5.x 59/59/57/4, 4.x
58/58/56/3) + 7 LGPL-safe entry points (av_version_info, avutil_version,
avcodec_version/configuration/license, avformat_version, swresample_version) + local sample
hashes (Cascadeur set 094CF53C/978F36BF/2FFE865E/43FF1854; Blender avcodec-61 1377146F; OneDrive
avcodec-62 6A194B53; DaVinci avcodec-60 83A94AD3 -- SPEC §3); gate=G0..G5 OK (ABSENT -> SKIP;
ABI/PROBE_FAILED -> FAIL; all unsafe in the single module); needs=NONE (allowlisted + baseline;
namespace-check OK, 0 conflicts); NO port.args.json (pure-XIOM loader).
```

```
BINDINGS BATCH 20: head=80d3e0a0 + this handoff commit; packages=xiom.openssl 0.2.0 (system-lib
multi-soname dynamic loader replacing the pre-pilot static-extern module); tests=default PATH
4/4 x2 (LibreSSL 3.8.2 via C:\Windows\System32\libcrypto.dll: version string, byte-exact
SHA-256("abc") digest check, RAND_bytes(16)) and Git for Windows on PATH 4/4 (OpenSSL 3.2.4,
num 807403584); deterministic SKIP classification per run; licenses=Apache-2.0 (OpenSSL) /
ISC-style (LibreSSL); nothing vendored + package MIT OR Apache-2.0; pins=candidate sonames
(libcrypto-3-x64.dll, libcrypto-1_1-x64.dll, libcrypto-1_1.dll, libcrypto.dll) + entry points
(OpenSSL_version, OpenSSL_version_num, SHA256, RAND_bytes) + local samples (Git 3.2.4 sha256
9C069DEC...; System32 libcrypto.dll sha256 7CEA4AC1...; DaVinci 1.1.1n C4202179...; Python 1.1.1g
594303E2...); gate=G0..G5 OK; needs=NONE (allowlisted + baseline); NO port.args.json.
DECISION RECORD -- openssl: SYSTEM path (OpenSSL source is too large/configuration-heavy to
vendor; libcrypto builds are ubiquitous on Windows; SKIP keeps CI green; present proof is real).
RECOMMENDATION -- ffmpeg (needs native approval before start): (1) LGPL-compatible
configuration ONLY (no GPL codecs, no --enable-gpl); (2) prefer the system-lib SKIP pattern
first (multi-soname avcodec/avformat/avutil/swresample), since ffmpeg DLL sets are rarely on
PATH and vendoring a prebuilt LGPL shared build is the fallback (license text + build config
recorded as the G2 pin); (3) until approved, the crypto/media sector is paused after openssl.
```

```
BINDINGS BATCH 16: head=76bc9556 + this handoff commit; packages=xiom.libpq 0.2.0 (dynamic
loader replacing static-extern stub wrappers); tests=present 4/4 x2 (DaVinci Resolve libpq
13.11 prepended to PATH: PQlibVersion 130011, closed-port connect -> CONNECTION_BAD + error
text 'timeout expired') and absent 2/2 x2 (default PATH: SKIP classification + SKIP probe),
all via scripts/port.ps1 on v0.64.1; licenses=PostgreSQL License (libpq not vendored; nothing
committed) + package MIT OR Apache-2.0; pins=soname libpq.dll + 13-entry-point set
(PQlibVersion/PQconnectdb/PQstatus/PQerrorMessage/PQfinish/PQexec/PQresultStatus/PQntuples/
PQnfields/PQfname/PQgetvalue/PQgetisnull/PQclear) + constants (CONNECTION_OK/BAD, PGRES_*) +
local samples: DaVinci 13.11 sha256 B43D05F89AC004934D8771F21D8BB0F3C80CD5C183221DFA6CB58BAFCE9F621E,
Reallusion 10.7 sha256 7D4A589E45ED04756DE72C8A94932EC94F88B9874E0AE9234AA88467255C002E (SPEC.md §2);
gate=G0..G5 OK (ABSENT -> SKIP; ABI/PROBE_FAILED -> FAIL; all unsafe in the single module);
needs=ALLOWLIST APPEND still pending for xiom.odbc (batch 15) -- xiom.libpq is already
allowlisted; NO port.args.json (pure-XIOM loader).
SECTOR STATUS: data/drivers complete (odbc + libpq). Next per proposal: audio --
xiom.miniaudio (single-header vendored C), then portaudio/phonon.
```

**STATUS: BATCH 19 RELAYED** -- `xiom.phonon` 0.2.0 green on the SKIP path
(3/3 x2); **present path deliberately unexercised** (no `phonon.dll` available
locally -- options recorded in `AUDIT.md`, probe ABI-verified against the
exact v4.8.1 headers and activates automatically when the DLL is on PATH).
**Audio sector COMPLETE** (miniaudio, portaudio, phonon). Awaiting native
merge/verify/publish.

## Relay (bindings -> native, per BINDINGS-LANE.md §6)

```
BINDINGS BATCH 19: head=f70eb9a1 + this handoff commit; packages=xiom.phonon 0.2.0 (dynamic
loader replacing the pre-pilot 125-static-extern module); tests=SKIP path 3/3 x2 via
scripts/port.ps1 on v0.64.1 (default PATH: version/SIMD/status constants, deterministic SKIP
classification via bogus soname, probe SKIP code 126). PRESENT PATH NOT EXERCISED (honest):
no phonon.dll on this host -- local SDK tree (E:\repos\steam-audio) is source+headers only,
integration release zips (wwise 52MB, downloaded+inspected) are source+docs, main SDK zip is
181MB (not fetched), core cmake build needs flatbuffers/pffft/zlib/mysofa fetches.
AUDIT.md records the three follow-up options; the suite needs no changes. licenses=Apache-2.0
(Steam Audio; nothing vendored) + package MIT OR Apache-2.0; pins=soname phonon.dll + tag
v4.8.1 + entry points (iplContextCreate/Retain/Release) + IPLContextSettings 40-byte layout
(version 0x040801 at 0, SIMD/status enums) + local header hashes (phonon.h CFAB6768...,
phonon_version.h ED3A14DA..., phonon_interfaces.h 90C9AE80...); gate=G0..G5 OK
(ABSENT -> SKIP, ABI/PROBE_FAILED -> FAIL; all unsafe in the single module); needs=NONE
(allowlisted + baseline); NO port.args.json. ASK/OPTION: if the native lane wants full
present-path evidence, fetching the 181MB SDK zip or running on a phonon.dll host completes
it with zero package changes.
SECTOR STATUS: audio complete (miniaudio, portaudio, phonon). Next per proposal:
accelerators (GATED on XVECTOR freezing xiom.vectors) or crypto/media (openssl needs a
vendored-vs-system decision; ffmpeg needs an LGPL/GPL configuration decision first).
```

```
BINDINGS BATCH 18: head=282754b0 + this handoff commit; packages=xiom.portaudio 0.2.0
(dynamic loader replacing static externs); tests=present 5/5 x2 (Audacity portaudio_x64.dll
V19.7.0 on PATH: version text 'PortAudio V19.7.0-devel, revision unknown' int 1246976,
52 devices, default output 'Speakers (Realtek(R) Audio)', default input Razer mic) and
absent 2/2 x2 (default PATH: SKIP classification + SKIP probe), all via scripts/port.ps1 on
v0.64.1; licenses=MIT (PortAudio not vendored) + package MIT OR Apache-2.0; pins=soname
portaudio_x64.dll + 8-entry-point set + PaDeviceInfo prefix (name pointer at offset 8) +
local samples: Audacity 221,696 B sha256
370E0FD6A9793EDBD0D0FA7F2CC7CDAA4EED86D3A747D765CAFC1DDB0E5968EF (used), DaVinci 102,400 B
sha256 12E0C6AE447F5C72F4EABD8CAFD6A036AEB33FAD392973FE46BEDF17A628D3AB (SPEC.md §2);
gate=G0..G5 OK; needs=NONE (allowlisted + baseline); NO port.args.json (pure-XIOM loader).
```

```
BINDINGS BATCH 17: head=89dccfae + this handoff commit; packages=xiom.miniaudio 0.2.0
(vendored single header replacing the pre-pilot bridge whose miniaudio header was never
vendored); tests=4/4 x2 via scripts/port.ps1 on v0.64.1 (2026-10-09: version 0.11.25,
context playback=9 capture=4, in-memory WAV decode 16 frames / 1 channel / 8000 Hz / s16
with sample spot-checks); licenses=Unlicense (public domain) OR MIT-0 (vendored miniaudio)
+ package MIT OR Apache-2.0; pins=tag 0.11.25 vendor/miniaudio.h sha256
AC7AF4DE748B7E26B777F37E01CEE313A308A7296A3EB080E2906B320CC55C89 (4,108,168 B; committed
blob verified) + vendor/LICENSE sha256 457F1B500E0ADF6BC059EDDDFA78A2F62012E7C3BB43476C20E0BD23B25BA0EB;
gate=G0..G5 OK; needs=NONE (allowlisted + baseline); port.args.json present
(--c-source src/miniaudio_all.c: MINIAUDIO_IMPLEMENTATION + probe bridge in one TU, no
--link). No library-absence SKIP path (vendored); a serviceless host reports the context
check as SKIP with the miniaudio result code.
```

## Sector proposal (bindings lane, post tier-3)

Ordered by risk retired per unit of work, each keeping the one-package-per-
relay discipline:

1. **Data/drivers (COMPLETE)**: `xiom.odbc` 0.2.0 + `xiom.libpq` 0.2.0; the
   `xiom.postgres` scope call (facade over libpq vs pure-XIOM wire) is the
   native lane's.
2. **Audio**: `xiom.miniaudio` (single-header vendored C -- fits the proven
   amalgamation path; context + device enumeration + in-memory WAV
   decode/encode as functional proof), then `xiom.portaudio` (system-lib
   SKIP pattern), then `xiom.phonon` (vendored).
3. **Accelerators (XVECTOR-facing)**: `xiom.openblas` / `xiom.eigen` /
   `xiom.blas` behind the portable `xiom.vectors` contract -- GATED on
   XVECTOR freezing that contract; do not start before then.
4. **Crypto/media/heavy**: `xiom.openssl` (vendored or system SKIP),
   `xiom.ffmpeg` (license-conditional: LGPL/GPL config choice needed before
   vendoring), ONNX/OpenCV last.

Next package: `xiom.miniaudio` (audio sector).

## Relay (bindings -> native, per BINDINGS-LANE.md §6)

```
BINDINGS BATCH 15: head=27e38bd3 + this handoff commit; packages=xiom.odbc 0.2.0 (first
implementation; the dir was a manifest-less placeholder, namespace-check OK before
activation); tests=5/5 x2 via scripts/port.ps1 on v0.64.1 (2026-10-08: ODBC manager
03.80.0000, 7 drivers incl. SQL Server / ODBC Driver 11, 3 configured DSNs; deterministic
SKIP classification via bogus soname); licenses=MIT OR Apache-2.0 (odbc32.dll is a system
component; nothing vendored); pins=soname odbc32.dll + entry-point set (SQLAllocHandle,
SQLSetEnvAttr, SQLDrivers, SQLDataSources, SQLGetInfo, SQLFreeHandle) + ODBC constants +
local System32 sample 10.0.26100.9549 sha256 8A120C65049E31B26CF1608E9D9E3253F386D29539A508B345E30390542B88D7
(SPEC.md §2); gate=G0 OK (keywords:["binding"], license), G1 OK, G2 OK, G3 OK (ABSENT ->
SKIP, ABI -> FAIL), G4 OK (5 checks), G5 OK (all unsafe in the single module xiom.odbc);
needs=ALLOWLIST APPEND for xiom.odbc (not in the publish allowlist; native lane does the
append + ops scope). NO port.args.json (pure-XIOM loader).
FINDING B-10 (recorded in docs/BINDINGS-COMPILER-FINDINGS.md): a local fn-pointer variable
named `alloc` inside a confined block has its calls silently rewritten to the guard
allocator (ODBC SQLAllocHandle appeared to succeed while the out-param stayed 0; renaming
to f_alloc fixed it). Guard pass should exclude non-builtin locals.
```

```
BINDINGS BATCH 14: head=f71fb8bf + this handoff commit; packages=xiom.ozz 0.2.0 (vendored
C++ amalgamations replacing the pre-pilot module whose C bridge was never present);
tests=4/4 x2 via scripts/port.ps1 on v0.64.1 (2026-10-08: math dot/cross + 90deg axis
rotation; offline RawSkeleton -> runtime Skeleton (2 joints, parents -1/0); LocalToModelJob
child at (0,1,0) in model space; aggregate green); licenses=MIT (vendored ozz) + package MIT
OR Apache-2.0; pins=tag 0.16.0 archive sha256
A7A34322344E9D839EAF637BBC463404C6AED3F52583DEA95C856FEA580C2693 + generated TUs
vendor/ozz_all.cpp 24117B0FBBAA5E1221C2F8FBEE9CB6A79EB42E28179A29CD5DE75E392C751457 and
vendor/ozz_bridge.cpp 0D2BA8800CADD74381ED907C8A9A35687A18EE014BA54C5D8D9DFFFFCCD6CA76
(LF-normalized, blobs verified against pins) + LICENSE.md; gate=G0..G5 OK; needs=NONE
(allowlisted + baseline); port.args.json present (--c-source x2, no --link).
METHOD NOTE: the xiom link line has no include passthrough, so ozz (C++, no C API) is
vendored as two generated TUs from the upstream-style combine.py (roots include/ + src/);
generator inputs are reviewable at src/ozz-in.cpp and src/ozz-bridge-in.cpp; the full
re-pin procedure is in SPEC.md §2. This method generalizes to any header-heavy C/C++ library.
```

```
BINDINGS BATCH 13: head=a528dfd8 + this handoff commit; packages=xiom.lzfse 0.2.0 (vendored
Apple lzfse-1.0 sources replacing placeholder wrappers); tests=7/7 x2 via scripts/port.ps1
on v0.64.1 (2026-10-08: scratch encode 684,384 B / decode 47,368 B, 4096->182 bytes,
round-trip identity incl. 65,536-byte and 1024-byte incompressible, invalid stream
rejected); licenses=BSD-3-Clause (vendored Apple sources) + package MIT OR Apache-2.0;
pins=tag lzfse-1.0 archive sha256
CF85F373F09E9177C0B21DBFBB427EFAEDC02D035D2AADE65EB58A3CBF9AD267 + per-file SHA256 table
(15 files, SPEC.md §2); gate=G0..G5 OK; needs=NONE (allowlisted + baseline);
port.args.json present (--c-source x7, upstream add_library source list, no --link);
.gitattributes vendor/** -text byte pin; lzfse_main.c (CLI) intentionally not vendored.
```

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

## Batch 28 notes (xiom.assimp COLLADA, 2026-10-10)

- 0.4.0 adds the COLLADA importer (+ pugixml contrib incl. its one C++ TU),
  96 TUs; new in-memory probe with a minimal 1.4.1 document -> 6/6 x2.
- The generator's contrib mechanism now carries C++ extras
  (`CONTRIB_EXTRA`: minizip .c + pugixml.cpp).
- Bus item filed for the tip merge; batches 26/27/28 collapse into one pass
  (the tip already carries all).

## Batch 27 notes (xiom.assimp glTF2 expansion, 2026-10-10)

- 0.3.0 adds the GLTF importer option (legacy glTF + glTF2 + glTFCommon
  dirs) and the rapidjson contrib; 92 TUs. New in-memory glTF2 probe
  (embedded base64 data-URI buffer) -> 5/5 x2.
- Generator hardening found while expanding: system headers must never be
  remapped by basename (rapidjson ships msinttypes/stdint.h, which stole
  <stdint.h>); contrib include roots are now keyed relative to the lib and
  its include/ dir. Batch 26's tree was unaffected (rapidjson was not
  mirrored then); the regenerated tree is byte-stable for the old files.
- Supersedes the 0.2.0 in the batch-26 bus item: the merged branch tip
  carries all of batch 26 + 27.

## Batch 26 notes (xiom.assimp, 2026-10-10)

- Generated-subset method proven at scale: the generator mirrors the tagged
  tree, rewrites every vendored-resolving include to an exact relative path
  (no -I passthrough), synthesizes config.h from config.h.in (all
  AI_CONFIG_* defaults kept + 47 NO_* switches + NO_EXPORT + NO_C4D),
  generates revision.h, copies zconf.h.included as zconf.h, and emits
  port.args.json. 89 TUs compile in ~90-150 s.
- Debug trail: doubled closing quote in the first rewriter version (extra
  tokens warnings; ioapi.h broken); .c files initially excluded from
  rewriting (unzip.c); CApi/AssimpCExport.cpp needed NO_EXPORT-aware
  exclusion; Geometry/CApi dirs and minizip unzip/ioapi were missing from
  the first source list.
- The subset compiles under the link line's default C++14 (upstream CMake
  sets CXX_STANDARD 17, but nothing in this subset needs it) -- the jolt
  C++ standard ask stays jolt-only.
- Relay bus: batch-ready item filed to packages on xiom-relays; the lane
  instructions + doorbell check are in the onboarding section.

## Batch 25 notes (xiom.cuda + wishlist refetch, 2026-10-10)

- `xiom.cuda` 0.2.0: driver-API-only probe (no Toolkit needed -- the
  system `nvcuda.dll` ships with the driver); one packed-return bridge call
  caches version/count/name/cc/memtest (B-11-safe ABI); 5/5 x2 with real
  device-memory traffic on the RTX 3070 Ti.
- Wishlist refetch (2026-10-10 revisions): no new binding asks; PULSE's
  durable-DB ask stays served (its new note is the `xiom.http` libcurl
  link-hook, already filed on the packages/compiler side); ORBITDB files
  no FFI; XVECTOR keeps the accelerator row gated on the `xiom.vectors`
  extraction (owner greenlight pending on their side). Recorded in
  `docs/BINDINGS-PACKAGE-WISHLIST.md`.
- Roster after this batch: `assimp` remains the last big graphics item;
  `jolt` blocked on the C++ standard flag; heavy runtimes need the native
  go-ahead; accelerators gated.

## Batch 24 notes (xiom.vma + finding B-11, 2026-10-09)

- `xiom.vma` 0.2.0: vendored header-only path; the bridge is the only TU;
  the loader is dlopen'd; the probe drives a real device -> VMA allocator ->
  64 KiB host-visible buffer -> mapped pattern -> cleanup. 5/5 x2 on the
  RTX 3070 Ti; the SKIP path is deterministic via a bogus module name.
- **Finding B-11 (new, runtime lane)**: while wiring the probe, out-param
  slots written by the Vulkan-heavy call were recycled before the caller
  could read them (C's own volatile readback: 65536 at return; XIOM read: 0;
  one run showed byte reads `[0,49,50,51]` beside a u32 read of 0). Bisect:
  trivial / malloc-churn / loader-only / instance-only variants clean; the
  device+VMA+map sequence reproduces every run. Shipped workaround: packed
  scalar returns. Row in `docs/BINDINGS-COMPILER-FINDINGS.md` + repro bundle;
  runtime lead: process-wide VEH + wholesale guard-arena discard vs NVIDIA
  driver threads/SEH.
- Pin: VMA v3.4.0 (MIT) + Vulkan-Headers vulkan-sdk-1.4.350.0 (Apache-2.0);
  the one-line vendored rewrite is documented in SPEC §2.

## Batch 23 notes (physics + UI roster, 2026-10-09)

- `xiom.box2d` 0.2.0: vendored v3.1.1 C via the flat layout (35 sources +
  bridge; the lzfse multi-source pattern): quoted includes resolve against
  each file's own directory, so no generator and no `-I`. Integer-only
  bridge (milli encoding); real simulation proof (drop settles at 499 milli
  = half-extent on the ground; impulse dv = J/m exactly).
- `xiom.imgui` 0.2.0: vendored v1.92.9b core + upstream null backends (the
  supported blind-context flow); headless two-frame probe -- ImGui hides a
  newly created window on frame 1, so the suite reports frame 2 (76 vtx /
  240 idx / 1 cmd). Replaces the pre-pilot precompiled-object + GLFW/Vulkan
  bridge tree (history only). Debug note: without `io.Fonts->Build()` or
  the RendererHasTextures flag the 1.92 font system asserts.
- `xiom.jolt` recon (BLOCKED): tarball v5.6.0 pinned (sha 6E069EE0...,
  19.4 MB); generator (mirror + `<Jolt/` -> `"Jolt/` rewrite + 25
  per-directory TUs) validated to compile the whole library under
  `-std=c++17` in ~30 s with system clang. The link line passes no standard
  flag and clang 22 defaults to C++14 -> cannot build via --c-source yet.
  Ask relayed; no jolt artifacts committed until unblocked.
- Namespace-check OK for both; no new compiler findings.

## Batch 22 notes (xiom.sqlite enum restore, 2026-10-09)

- B-01 workaround retired at the repin per the native rule ("droppable at
  the next touch"): `types.xi` restores the canonical enum model from the
  repro bundle (struct wrapping `SqliteValueKind`); `rows.xi` needed only a
  comment fix (constructors unchanged); `kind_name` kept (match-based).
- Validation: 6 fresh rebuild cycles (the defect was build-dependent;
  original evidence 2/6 bad) + the pin matrix x1 -- 16/16 each time.
- Docs updated: SPEC §1/§5 (0.3.0, v0.64.2 pin, item 1 rewritten as
  FIXED+restored), README status, AUDIT design note; obsolete `VALUE_*`
  constants removed with the struct.
- Version 0.3.0 (public type representation changed); the publish decision
  is the native lane's.

## v0.64.2 sweep notes (2026-10-09)

- Toolchain: v0.64.2 -- the installed slot `%LOCALAPPDATA%\xiom.new`
  (used by `port.ps1`) plus the repo-release build
  `E:\xiom-lang\xiom\target\release` (used by the direct repro probes);
  repo pin still v0.64.1 -- the native repin is pending. The old
  `%LOCALAPPDATA%\xiom.new` slot has been replaced by the shipped release.
- Repro batteries: B-01 6/6 all-true rebuilds (was 2/6 bad); B-08 compiler
  exits 5 for a program returning 5; B-05 spin reproduced under the 10 s
  watchdog (8.7 CPU-s, flat 4.5 MB); B-10 3-way scratch control
  (`f_alloc`/`my_alloc` green, `alloc` fail); B-06/B-09 green.
- Matrix: 19/19 suites x1; no new compiler findings from the sweep.
- Minimal-shape follow-ups (2026-10-09): B-03 + B-04 GREEN, B-07 STILL
  BROKEN (`undefined variable` in a `module ...ffi` + `use xiom.ffi;` shape);
  bundles committed under `docs/repro/bindings-pilot/` (const-alias,
  child-import-parent, ffi-alias-shadow); B-02 not re-tested (no trigger).
- Workaround retirement: B-01 (sqlite tagged-struct) RETIRED in `xiom.sqlite`
  0.3.0; B-05/B-10 workarounds stay; B-06/B-09 bridge/naming
  workarounds are optional-touch only (no drive-by reverts).

## Batch 21 notes (xiom.ffmpeg, 2026-10-09)

- Scope per the native decision (`BINDINGS-LANE.md` §11): system-lib SKIP
  path only, LGPL-safe probe; vendoring NOT approved. Present-path proof
  used the local Cascadeur 6.0 LGPL set placed on PATH at run time (nothing
  committed; hashes in SPEC §3).
- Generation model: one release generation = four libraries
  (avcodec/avformat/avutil/swresample); a partial set is skipped, never
  mixed across ABI generations. 8.x..4.x table in SPEC §3.
- Probe calls 7 LGPL-safe entry points only: version string + four packed
  versions + license/configuration evidence. GPL-configured host builds are
  reported as data (Blender 7.1.1 sample), not failed -- the package never
  depends on a GPL-only feature.
- Extra coverage beyond the required x2: second generation (7.x) exercised
  via Blender; two partial-generation SKIP cases (OneDrive 8.x, DaVinci
  6.x). Pre-pilot 27-static-extern module + 26-test suite preserved in git
  history.
- Namespace-check OK (0 conflicts vs 1758); no new compiler findings.

## Batch 20 notes (xiom.openssl, 2026-10-09)

- System-lib path chosen (decision recorded in SPEC §2 and the relay):
  OpenSSL source is too large/configuration-heavy to vendor; libcrypto
  builds are ubiquitous on Windows; the SKIP classification keeps CI green
  while the present-path proof is real (byte-exact SHA-256("abc") digest +
  RAND_bytes(16) via the resolved `SHA256`/`RAND_bytes` entry points).
- Multi-soname loader candidates: `libcrypto-3-x64.dll`,
  `libcrypto-1_1-x64.dll`, `libcrypto-1_1.dll`, `libcrypto.dll`.
- Run matrix: default PATH (System32 LibreSSL 3.8.2) 4/4 x2; Git for
  Windows on PATH (OpenSSL 3.2.4, num 807403584) 4/4; deterministic SKIP
  classification every run (bogus soname). Sample hashes in SPEC §2.
- Inbound compiler relay v0.64.2 recorded (lane copy under `docs/`):
  B-01 fixed (m231), B-08 fixed (m228); B-05 still open (runtime/stdlib
  side); B-10 (odbc `alloc` name rewrite) re-test queued with the sweep.
  The sweep is gated on the tag -- installed slot is still v0.64.1.
- ffmpeg recommendation sent (LGPL-only, system-lib first); crypto/media
  paused until the native lane decides. NO port.args.json.

## Batch 19 notes (xiom.phonon, 2026-10-09)

- Steam Audio (Valve) 4.8.1: ABI pinned from the exact local SDK headers
  (`phonon.h` + `phonon_version.h` at `E:\repos\steam-audio`); the probe
  builds the 40-byte `IPLContextSettings` (version `0x040801`, SSE2 baseline,
  NULL callbacks) and balances create/retain/release via slots.
- **Present path unexercised** -- exhaustive local search found no
  `phonon.dll`; official integration zips are source-only (wwise zip
  downloaded + inspected), the main SDK zip is 181MB, and a core cmake build
  needs four fetched dependencies. `AUDIT.md` records the options; this is
  the lane's first package whose primary present path is pending rather than
  proven -- flagged prominently in the relay.
- Absent path 3/3 x2 (constants + SKIP classification + SKIP probe).
- Audio sector complete; next sector awaits the XVECTOR gate (accelerators)
  or the openssl/ffmpeg configuration decisions (crypto/media).

## Batch 18 notes (xiom.portaudio, 2026-10-09)

- Dynamic loader replaces the pre-pilot static-extern module; present-path
  proof used the Audacity x64 build (PATH prepend only, nothing committed).
- `PaDeviceInfo` name extraction: `structVersion` + padding then `char* name`
  at offset 8, read via `xiom.ffi.ptr_read_u64_le` and copied with
  `Str::from_c_str` (pure-XIOM; no C bridge needed).
- Real evidence: V19.7.0 (int 1246976), 52 devices, Realtek speakers and
  Razer mic defaults. Matrix present 5/5 x2, absent 2/2 x2.
- Audio sector: package 2 of 3; next `xiom.phonon`.

## Batch 17 notes (xiom.miniaudio, 2026-10-09)

- Vendored single-header pattern proven: one compile unit
  (`src/miniaudio_all.c`) holds `MINIAUDIO_IMPLEMENTATION` plus the probe
  bridge; no include paths, no --link, no separate bridge object.
- Real functional evidence without any audio hardware/backend assumptions:
  context init enumerated 9 playback + 4 capture devices; the in-memory WAV
  decode (8 kHz mono s16, precomputed sine, byte-built header) verified
  frames/channels/rate/format and spot-checked samples.
- Probe bug found and fixed: the EOS read returns `MA_AT_END` on a drained
  decoder (`MA_SUCCESS || MA_AT_END` with zero frames is the correct check).
- Blob pin verified from git; `vendor/** -text` applied. Matrix 4/4 x2.
- Audio sector: package 1 of 3; next `xiom.portaudio`, then `xiom.phonon`.

## Batch 16 notes (xiom.libpq, 2026-10-08/09)

- Dynamic loader replaces the pre-pilot static-extern stub module; no server
  needed: `PQlibVersion` is connection-free and the connect probe targets a
  closed local port, so real `PQconnectdb`/`PQstatus`/`PQerrorMessage` /
  `PQfinish` behaviour is asserted (CONNECTION_BAD + non-empty error).
- Present-path proof used the x64 libpq 13.11 shipped with DaVinci Resolve
  (prepended to PATH for the run; nothing committed). Default PATH has no
  libpq.dll, so the absent/SKIP path is the CI-default shape here.
- Matrix: absent 2/2 x2, present 4/4 x2. Allowlisted + baseline;
  needs= odbc allowlist append only.
- Data/drivers sector complete; next: audio (`xiom.miniaudio`).

## Batch 15 notes (xiom.odbc, 2026-10-08)

- First implementation for a manifest-less placeholder; namespace-check ran
  before activation (OK, 0 conflicts).
- **New compiler finding B-10**: a local fn-pointer named `alloc` in a
  confined block is silently redirected to the guard allocator -- the ODBC
  env handle stayed 0 while every call reported success. A C reference probe
  outside XIOM proved the API call was correct; renaming the local to
  `f_alloc` fixed it. All bridge locals now use the `f_` prefix.
- Pure-XIOM loader (no bridge, no port.args.json): handles via XIOM-owned
  slots; `SQLDrivers`/`SQLDataSources` scans capped to bound misbehaving
  managers.
- Local evidence: manager `03.80.0000`, 7 drivers, 3 DSNs. Run matrix 5/5 x2.
- `xiom.odbc` is NOT allowlisted yet -- the relay carries the append ask.
- Sector proposal added above; next package: `xiom.libpq`.

## Batch 14 notes (xiom.ozz, 2026-10-08)

- **New capability proven: vendored C++ through the link line.** `xiom
  --help` has no include passthrough, so header-path-dependent C++ cannot be
  passed as individual sources; the upstream-style `combine.py` bundles the
  library into one TU (27 sources, first compile green in 2.3 s, no static
  collisions) plus a second TU for our `extern "C"` bridge. Reusable for any
  future header-heavy C/C++ package.
- Bridge API corrections found by compile iteration: quaternion rotation is
  `TransformVector(q, v)` (no `q * Float3`); matrix translation lanes need
  `GetX/GetY/GetZ` (SIMD values are not structs). Wrapper-vs-extern name
  shadowing bit again (lzfse lesson) -- public wrappers use `_ok`.
- The pilot exercises real runtime objects (offline SkeletonBuilder ->
  runtime Skeleton -> LocalToModelJob), not just symbol resolution.
- Generated TUs LF-normalized + pinned; committed blob hashes verified
  against the pins; `.gitattributes` `vendor/** -text`.
- Run matrix: 4/4 x2. Allowlisted + baseline; `port.args.json` passes both TUs.
- Compression/animation tier set complete (zstd, lzfse, ozz); next wave per
  native priority (data drivers / audio / accelerators are the remaining
  Phase-2 sectors).

## Batch 13 notes (xiom.lzfse, 2026-10-08)

- Multi-source vendoring worked without a shim: `port.args.json` passes the
  seven upstream `add_library` sources as separate `--c-source` entries
  (clang compiles them individually -- no cross-TU static collisions).
- Naming trap: a wrapper named like the extern (`lzfse_encode_scratch_size`)
  self-recurses; wrappers now use `_required` suffix. Worth remembering for
  other vendored C APIs whose names we might mirror.
- Scratch is allocated per call at library-reported sizes (684 KB encode) --
  documented; scratch reuse and a size-prefixed container helper are Phase 2
  roadmap items.
- Run matrix: 7/7 x2 first-try; allowlisted + baseline. Pre-pilot
  placeholder files removed to git history.
- Next: `xiom.ozz` (C++ -- expect a stronger shim/args need: C++ sources via
  --c-source will need the C++ frontend; check before committing the
  approach).

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

## Inbound package wishlists (2026-10-09 refresh)

- Fetched the three project-lane package wishlists (fresh, v0.64.2-era):
  `E:\xiom-projects\xiom-pulse\docs\PACKAGE-WISHLIST-PULSE.md`,
  `...\xiom-orbitdb\docs\PACKAGE-WISHLIST-ORBITDB.md`,
  `...\xiom-xvector\docs\PACKAGE-WISHLIST-XVECTOR.md`.
- Consolidated bindings-lane responses: **`docs/BINDINGS-PACKAGE-WISHLIST.md`**.
  - PULSE durable-DB ask **SERVED from the registry** (live-verified
    2026-10-09): `xiom.sqlite` 0.2.0, `xiom.libpq` 0.2.0 and `xiom.odbc`
    0.2.0 are all signed; the 0.3.0 sqlite enum restore is pending batch 22.
    Outbound HTTP is served by `xiom.http` 0.1.4 (libcurl); TLS
    not-a-binding ACKed.
  - ORBITDB: no FFI asks (pure XIOM through Phase 2) -- nothing to do.
  - XVECTOR: accelerators stay **GATED** on the `xiom.vectors` freeze
    (placeholders incubating/`unknown`); no SIMD kernel from this lane.
- Flagged to the packages/native lane: registry consumers of vendored-C
  packages (`xiom.sqlite`) need a `--c-source` build-hook story beyond the
  runner's `port.args.json`.
- Consumer-flow validation (registry installs into a scratch `XIOM_HOME`,
  v0.64.2, checksum+signature verified): `xiom.sqlite` 0.2.0 and
  `xiom.libpq` 0.2.0 both install and resolve via canonical
  `[dependencies]` (no `source-roots`). sqlite needs the explicit
  `--c-source <installed>/vendor/sqlite3.c` (gap confirmed: the shipped
  `port.args.json` is not applied by consumer builds) -- recipe in the
  package wishlist doc + the sqlite README (docs follow-up on batch 22);
  libpq runs plain with the SKIP classification.

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

## Next (superseded)

Superseded by the **RESUME HERE** section at the top of this file (2026-10-10
handoff). Kept only as history.

- Pin matrix re-run done: 19/19 green on the official v0.64.2 pin. The
  B-01 workaround is retired; B-05/B-10 workarounds stay in force; B-08
  probing may trust exit codes from v0.64.2 on (port.ps1 keeps marker
  counting for older pins).
- Roster: `box2d`/`imgui` (batch 23), `vma` (batch 24), `cuda` (batch 25),
  `assimp` (batch 26, expanded 27/28) done; `jolt` blocked on the standard
  flag; the heavy
  runtimes (`xiom.onnx`/`xiom.opencv`) need the native lane's go-ahead; the
  accelerators stay GATED on XVECTOR freezing `xiom.vectors`.
- Lane copy of the compiler relay: `docs/BINDINGS-COMPILER-RELAY-2026-10-09-v0.64.2.md`.
- PULSE/ORBITDB/XVECTOR package wishlists fetched and answered
  (`docs/BINDINGS-PACKAGE-WISHLIST.md`); no new in-lane work items
  (accelerators stay gated on `xiom.vectors`). Registry consumer flow for
  the DB bindings validated end-to-end (sqlite `--c-source` recipe + libpq
  plain); batch-22 docs follow-up adds the sqlite README consumer section.
  Revalidated on the published artifacts: sqlite 0.3.0 PASS, ffmpeg 0.2.0
  SKIP, libpq 0.2.0 SKIP (scratch `XIOM_HOME`, checksums matched).

## CONTEXT-LIMIT HANDOFF -- 2026-10-23 18:25Z (bindings lane)

Everything below is the authoritative pickup state.  The UPDATE stack
above (2026-10-16 .. 2026-10-22 blocks) holds the evidence trail; this
section is the summary + the next-session paste prompt.

### STATE
- **Toolchain: production pin `v0.64.8`** -- slot
  `%LOCALAPPDATA%\xiom.new` verified `XIOM Compiler v0.64.8`;
  backups kept: `%LOCALAPPDATA%\xiom.new.v0.64.8` and
  `%LOCALAPPDATA%\xiom.new.v0.64.9` (withdrawn archive, audit only).
  **v0.64.9 WITHDRAWN** (nested enum-pattern codegen defects
  1243/1615/1645 + 1451/1550 family, release-mode only; GitHub release
  marked pre-release).  **v0.65.0 production gate OPENED**
  (`docs/RELEASE_GATE_v0.65.0.md`; P0 correctness -> P1 hardening ->
  P2 MCU -> P3 cut; no candidate/tag before gate green + owner GO).
  Lane `COMPILER_VERSION` + all **579 records** = v0.64.8; validate
  **579/0**.
- **Lane shipments (ALL LIVE):** android SDK100 family (android 0.4.0 +
  aaudio/mediandk/camera2ndk/android-sys/opensl/jni; family 8/8 in
  `eco-v0.1.192`, gles 0.2.0 `.190`, sdl3 0.21.0 A14 `.202`); PULSE
  top-tier (brotli 0.1.0 + ssl 0.1.0 `.189`; TLS gap closed); R2/M2
  (serial/ros2/v4l/onnx/gps/torch/libtorch/tensorflow/blas `.193/.194`,
  onnx 0.2.0 DML `.198`); NVIDIA wave (cudnn/nvenc `.197`;
  cublas/cufft/cusparse/tensorrt/nvml/nvapi/optix `.199`); USD 0.1.0
  `.197`; kafka 0.2.0 + charts 0.2.0 (sibling landings); pandas 0.2.1
  `.201`; miniaudio 0.5.0 (handle surface); sqlite 0.5.0
  (`xiom-sqlite/v0.5.0`; B-32 retired).
- **Pending publishes:** MCU host-companion trio
  (firmata/micropython/uf2) -- landed + owner-DEFERRED; **do not file
  the publish request before the `mcu-qemu` gate is green in CI** (MCU
  freestanding contract `REL-20261023-0423-compiler` acked).  `epos`
  -- scope LIVE @574, rides the next batch.  `charts 0.2.0` -- sibling
  requested; check its item status.  The `.9` rows/records stay HELD
  (never green) as v0.65.0 acceptance input.
- **B-series: ZERO-OPEN.** B-29 closed (probe defect), B-32 retired
  (sqlite 0.5.0), B-33 fixed (m351, verified), B-34 fixed (.8,
  verified), B-16..B-26 verified fixed; findings ledger fully closed.
- **Open asks to bindings: NONE** (A14 closed end-to-end; miniaudio
  handle delivered; pandas closed; MCU contract coordinated).
- **Environment facts:** repo worktree `E:\xiom-packages\bindings`
  (shared repo: `main` = packages lane, `bindings` = our lane); relay
  bus clone `E:\xiom-lang\xiom-relays` (SHARED -- other actors may
  commit; always fetch + ff-merge, never `git pull`; `relay.py view`
  crashes on a malformed item -- repair pattern = valid front matter +
  `## History`, as done for `REL-20261022-2355-owner`).  Emulator:
  `C:\Android\sdk\emulator\emulator.exe -avd Medium_Phone_API_36.0
  -no-window -no-audio -no-boot-anim -no-snapshot -gpu
  swiftshader_indirect`.  Suites: `.\scripts\port.ps1 -Package <pkg>
  -TimeoutSec 300`; validate `.\scripts\status.ps1 -Action validate`;
  repin `-Action repin`.  Host note: the engine incident deleted
  `~/.cargo` and other home config dirs (workspace + AppData safe);
  cargo works via `.rustup` toolchains; the Windows package store was
  emptied that day.

### STANDING RULES (carry forward)
- XIOM_COMPILER = the pinned slot; **the lane pin follows the SHARED
  slot** (no split-brain); adopt a new release only on gate-green +
  owner GO; withdraw immediately on a fleet HOLD/WITHDRAWAL.
- Land path-scoped: `git fetch origin`; for restructured dirs
  `git rm -rf`/`Remove-Item` the package dir BEFORE `git checkout
  <branch> -- packages/<dir>` (checkout does not apply deletions);
  never wholesale-merge; re-run the suite x2 on the current pin;
  record with `status.ps1 -Action update` using the real (post-rebase)
  sha; validate; push with fetch-before-commit + rebase-retry.
- Line-oriented hex/trace fixtures need `.gitattributes` `eol=lf`
  guards on Windows (CRLF breaks parsers).
- Provenance per touch; no silent failures; B-series discipline (Int
  handles, owned byte slots, no pointer casts); atomic commits.
- Check `python tools/relay.py validate` after touching the relay.

### NEXT-SESSION PASTE PROMPT
Bindings lane continuation -- seamless pickup (2026-10-23 18:25Z;
CONTEXT-LIMIT HANDOFF).  Read `BINDINGS-SESSION.md` end-of-file
"CONTEXT-LIMIT HANDOFF" + the UPDATE stack; trust them over this
summary.

FIRST ACTIONS:
1. Re-arm the doorbell `0 */3 * * *` for THIS session:
   (a) `git -C E:\xiom-lang\xiom-relays fetch origin --prune` then
       `git -C E:\xiom-lang\xiom-relays merge --ff-only origin/main`
       (never `git pull` there);
   (b) `python tools/relay.py view --lane bindings` (workdir =
       E:\xiom-lang\xiom-relays); process only items whose `to` is
       bindings; record eco/relay results in the UPDATE stack; land any
       in-flight branch per the opening recipe; commit + push
       (fetch-first, rebase-retry).
2. Relay sweep: read all open items to bindings + replies; run
   `python tools/relay.py validate` (expect green, ~830+ items).
3. WATCH v0.65.0: no adoption until the gate is green AND the owner
   says GO.  On release adopter: swap the slot
   (`%LOCALAPPDATA%\xiom.new` <- the new archive; keep the old slot as
   a versioned backup), set `COMPILER_VERSION`, run
   `status.ps1 -Action repin`, validate, then the slot sanity matrix
   (xiom.sqlite 21/21 nested, xiom.sdl3 81/81, xiom.nvenc 67/67 live)
   AND the .9 acceptance probes: nested enum patterns
   `Some(Number(n))`/`Ok(Number(n))`/`Err(E.Bad(msg))`, the 1451
   nested-generic-ptr fixture, the true 1550 tuple-returning
   enumerate, and the .9 data-loss cluster (jev Err-in-Vec, openblas
   Vec-in-tuple, http Err(Enum) match) -- all in-repo under
   `docs/repro/bindings-pilot/` where applicable.
4. MCU publish ONLY after the `mcu-qemu` CI gate is green: file one
   combined request for `xiom.firmata 0.1.0` (x2 122/122),
   `xiom.micropython 0.1.0` (x2 19/19), `xiom.uf2 0.1.0` (x2 62/62)
   -- 3 NEW names -> ops scopes; the HAL family is not started; any
   board package must honor `docs/MCU_FREESTANDING.md` (per-board
   `--linker-script` with `_estack`/`__heap_start`/`__heap_end` +
   Cortex-M .data/.bss, strong `xiom_panic`, replaceable bump
   allocator, no unwinding/peripheral emulation).
5. `epos`: publish rides the next packages batch (scope LIVE @574);
   `charts 0.2.0`: check the sibling's request status.
6. Standing rules: production pin v0.64.8 (slot verified); suites on
   the pinned slot; provenance per touch; no silent failures; atomic
   commits + fetch-first push; the relay bus and the repo are SHARED
   with other lanes/sessions (expect concurrent commits; repair, don't
   rewrite).
