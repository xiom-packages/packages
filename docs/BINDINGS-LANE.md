# BINDINGS LANE — groundwork for FFI/C-binding packages

Status: PROPOSAL for owner approval (2026-10-08). This document is the operating plan for a
second session ("bindings lane"). No scripts or packages have been changed by writing it;
the native lane (main session) is unaffected.

## 1. Decision summary (recommendation)

- **Same repository, second git worktree on a long-lived `bindings` branch.** No new repo.
  No directory moves.
- **Reason:** the allowlist guard, `packages/index.json` generation, the registry-publish
  workflow, and the approval gate all live in THIS repo. A second repo would either
  duplicate that machinery (drift) or need registry multi-source support (an ops delta).
  The grandfathered FFI names are already in this repo's allowlist; each flips to "ready"
  as its package lands, with zero ops work.
- **Reversibility:** if scale later demands a split, `git subtree split -P packages` can
  lift the binding dirs into a new repo without losing history.
- **Single-writer rule:** the bindings session never touches shared artifacts; the native
  session is the only publisher (see §6).

## 2. Roster (already grandfathered in the allowlist)

From the guard's "GRANDFATHERED (not ready, pre-baseline entry)" list (40 names):
`algo, arrow, assimp, blas, box2d, cuda, directx11, directx12, dxc, eigen, ffmpeg, gazebo,
glfw, graphql, grpc, imgui, jolt, kafka, libpq, lzfse, miniaudio, moveit, onnx, openblas,
opencv, opengl, openssl, ozz, pandas, phonon, portaudio, raylib, scipy, sdl3, tensorflow,
torch, vma, vulkan, zeromq, zstd`.
Additionally, manifest-less package dirs exist for: `aac, bridge, c-binding, icu, jansson,
llvm, odbc` (add `package.xi` when activated).

Classification notes:
- `c-binding`, `bridge` are **tooling** (shared FFI helpers), not binding packages.
- `graphql`, `grpc`, `kafka` are not pure FFI bindings; keep them with native policy unless
  the owner reclassifies.
- `pandas`, `scipy`, `tensorflow`, `torch`, `arrow` are Python/C++ mixed ecosystems; treat
  as a separate "heavy runtimes" sub-class (likely thin C-ABI shims; decide per case).

## 3. Tiers and gates

| Tier | Examples | Gates |
|---|---|---|
| native | current queue (pure XIOM) | port x2, contract waves, zero-clause scan |
| **binding** | opengl, vulkan, sdl3, sqlite | **G0-G5 below**; excluded from contract waves and the zero-clause scan |
| tooling | c-binding, bridge, scripts | compile + smoke; no contract policy |

Binding gate, per package:

- **G0 Manifest/marker**: `package.xi` with `keywords` containing the binding marker
  `"binding"` (decided 2026-10-08: `keywords`, NOT `categories` -- the registry silently
  drops unknown category tokens and categories stay within the 16-token vocabulary), plus
  `license`.
- **G1 Compile**: the package compiles with the pinned compiler on the lane's platform.
- **G2 ABI pin**: `SPEC.md` records upstream project, pinned version, the soname/link
  libraries, and a **SHA256 over the pinned header set**; a re-pin procedure is documented.
- **G3 Loader smoke**: load the library and query version/capabilities. When the library is
  absent the suite reports **SKIP** (never FAIL) so CI without SDKs stays green.
- **G4 Function smoke**: vendored libraries get a real functional suite; system libraries a
  minimal probe; GPU/OS SDKs capability-only (no rendering in CI).
- **G5 Confinement**: `unsafe` blocks confined to one module per package; typed wrappers;
  SPEC documents the safe boundary and error mapping.
- **Drift guard** (CI job, report-only at first): re-hash headers/symbols vs the G2 pin;
  flag when upstream moved. Re-pin only when the hash changes.
- **Exclusion**: binding packages are excluded from `scripts/contract-coverage.ps1` (zero-
  clause scan) and from native hardening waves, by the `keywords: ["binding"]` marker
  (policy analogous to the documented `option` exclusion).

## 4. Licensing policy (recommended)

- **Allowed by default**: MIT, Apache-2.0, BSD-2/3-Clause, ISC, Zlib, public domain
  (SQLite), X11.
- **Conditional**: LGPL-2.1/LGPL-3 (e.g., FFmpeg) — dynamic linking only, never vendored,
  marked in `SPEC.md`; distribution must ship the dynamic-library requirement.
- **Excluded**: GPL/AGPL/SSPL and unknown/custom licenses without explicit owner review.
- **Evidence**: every package carries `license:` in `package.xi` and copies the upstream
  LICENSE text into its directory; vendored code keeps upstream headers verbatim.

## 5. Platform scoping

- Records a platform list (proposal: a `platforms:` field in `STATUS.json`/`package.xi`
  agreed with the release lane, e.g. `["win-x64"]` for D3D; `["linux-x64","win-x64","mac"]`
  for SDL3).
- CI semantics: absent platform/SDK ⇒ **SKIP** state for that package, never FAIL; the
  registry record shows passes for the platforms that ran and the SPEC notes the scope.
- Registry `kind`/platform metadata is an ops question for the release lane (see §9).

## 6. Worktree protocol (conflict avoidance)

Directories and branches:

- native lane: `E:\xiom-packages\packages` on branch `main` — THIS session.
- bindings lane: `E:\xiom-packages\bindings` on branch `bindings` — NEW session.

One-time setup (run in the main repo):

```powershell
git -C E:\xiom-packages\packages worktree add E:\xiom-packages\bindings -b bindings
```

Single-writer rules:

- **Bindings session edits ONLY**: `packages/<binding dirs>/**`, `BINDINGS-SESSION.md`
  (its own handoff file at the worktree root), and `docs/BINDINGS-LANE.md` appends. It must
  NOT touch `packages/index.json`, `docs/PACKAGE_STATUS.md`, `docs/PACKAGE-NAMESPACES.txt`,
  `SESSION.md`, `scripts/**`, or any native package.
- **Native session (this one) is the ONLY publisher**: regenerates index/status/namespaces,
  runs validate/guard, and cuts `eco-vX.Y.Z` tags. Script changes (e.g., the coverage
  exclusion, a future drift script) are made by the native lane.
- **Keep-fresh rule**: before starting any bindings batch, the bindings session runs
  `git fetch; git merge origin/main` inside its worktree. If that merge conflicts, it stops
  and reports (should not happen: file sets are disjoint by rule).
- **Names and conflicts**: binding names are pre-rostered (in-repo dirs; the 40 grandfathered
  names are already allowlisted). Before activating a pre-named/manifest-less dir, run
  `scripts/namespace-check.ps1 -Module <xiom.name>` (read-only) and include the result in the
  relay; pilot check 2026-10-08: `xiom.sqlite`, `xiom.sdl3`, `xiom.opengl` all OK vs the 1720
  stdlib namespaces. The native lane re-runs the check at merge and owns the allowlist append
  + ops scope enumeration for names not yet allowlisted (e.g. `xiom.sqlite`).
- **Merge/publish flow**: when a bindings batch is green, the bindings session reports to
  the native session: branch head SHA, package list, per-package test counts, licenses,
  pin hashes. The native session merges `bindings` → `main`, regenerates shared artifacts,
  runs the full gate (with binding exclusions), and publishes in the next eco tag.
- **Tags**: `eco-vX.Y.Z` includes everything merged. Optional `bind-vX.Y.Z` tags may be
  placed for traceability; they never trigger the registry-publish workflow.
- **Relay template** (bindings → native):
  `BINDINGS BATCH <n>: head=<sha>; packages=<list with versions>; tests=<pkg passed/total>;
  licenses=<list>; pins=<header hashes>; gate=<G0-G5 status>; needs=<ops/script asks>`.

## 7. Paste prompt for the bindings session

```
You are the BINDINGS session for the xiom-packages bindings lane (FFI/C-binding packages).
Worktree: E:\xiom-packages\bindings (git branch `bindings`, a worktree of the main repo
E:\xiom-packages\packages). Create it once with:
  git -C E:\xiom-packages\packages worktree add E:\xiom-packages\bindings -b bindings
Read E:\xiom-packages\bindings\docs\BINDINGS-LANE.md FIRST -- it is your operating plan
(tiers, gates G0-G5, licensing, platform scoping, single-writer and merge rules).

Identity: "Lefteris Notas <lefterisnotas@gmail.com>". Compiler pin: v0.64.0
($env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"); NEVER set
XIOM_RUNTIME_DIR.

ABSOLUTE RULES
- You NEVER touch shared files: packages/index.json, docs/PACKAGE_STATUS.md,
  docs/PACKAGE-NAMESPACES.txt, SESSION.md (main), scripts/**, or any native package.
- You NEVER publish: no eco tags, no registry gate approvals. The native session publishes
  merged work only.
- You edit ONLY packages/<binding dirs>/** , BINDINGS-SESSION.md, and appends to
  docs/BINDINGS-LANE.md.
- Keep fresh: `git fetch; git merge origin/main` before starting any batch; stop and report
  if that conflicts.
- One package at a time or a small fan-out with the same discipline as the native lane:
  green x2 runs, byte-level bracket scan, explicit-path cleanup, no silent failures.

START HERE (Phase 1 pilot, prove G0-G5):
1. xiom-sqlite: vendor the SQLite amalgamation into the package; full functional suite
   (open/exec/prepared statements/error codes); G2 pin = upstream version + amalgamation
   SHA256. This proves the vendored path.
2. xiom-sdl3: system-library smoke (init/version/quit + timer/event peek), SKIP when absent;
   G2 pin = SDL3 dev header hash + soname. This proves the system-lib path.
3. xiom-opengl: loader probe via dlopen/GetProcAddress (or GLFW/SDL loader if simpler),
   query VENDOR/VERSION strings; capability-only in CI. This proves the GPU-lite path.
For each: gate check, BINDINGS-SESSION.md entry, relay to the native session with the
template from the plan, THEN wait for the native session to merge+publish before starting
the next package. After the pilot, propose the Phase-2 sector order.

Environment notes: PowerShell 5.1, Windows. Use `C:\Users\lefte\AppData\Local\Temp\kilo`
for scratch. Report concisely; evidence over claims; ask the owner when licensing or scope
is ambiguous.
```

## 8. Phasing

- **Phase 0** (after owner approves): create the worktree/branch; native lane adds the
  binding exclusion to `scripts/contract-coverage.ps1` (one small commit) and optional
  guard wording. Bindings session starts.
- **Phase 1 pilot**: sqlite (vendored), sdl3 (system), opengl (loader/capability). Prove
  G0-G5 end-to-end, including the merge/relay flow.
- **Phase 2 sectors** (curated; stable ABIs first): data (`sqlite`), window/input (`sdl3`,
  `glfw`, `raylib`), graphics (`opengl` → `vulkan` → `directx11/12` → `dxc`), audio
  (`miniaudio`, `portaudio`, `phonon`), compression (`zstd`, `lzfse`, `ozz`), physics
  (`box2d`, `jolt`), db/drivers (`libpq`, `odbc`), crypto (`openssl`), media (`ffmpeg`,
  license-conditional), heavy runtimes (`onnx`, `opencv`, `eigen`/`openblas` vs native
  `blas`, `pandas`/`scipy`/`torch`/`tensorflow` — separate decision).
- **Re-pin cadence**: quarterly or on demand when the drift guard flags a hash change.

## 9. Open questions for the owner

1. ~~Binding marker: `categories: ["binding"]` in `package.xi` OK?~~ **RESOLVED 2026-10-08:
   the marker is `keywords: ["binding"]`** (registry-safe; categories stay
   vocabulary-clean). The registry `kind` field remains an optional ops ask to the release
   lane.
2. Platform encoding: `platforms:` field vs SPEC-only. (Recommend the field.)
3. Bindings in the same eco tags (my recommendation) vs `bind-*` releases.
4. Worktree path `E:\xiom-packages\bindings` OK?
5. Confirm the licensing lists in §4.
