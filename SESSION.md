# xiom-packages/packages -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-09-23, by the packages session. The commit that adds this
file is HEAD; check `git log -1 --format=%h %s` before starting.

**Mission:** turn this staging monorepo into real, production-grade package
repos. Start from small packages that can reach production grade quickly,
port the legacy code in dependency order, and graduate stable packages to
`xiom-packages/xiom-<name>` with OIDC publishing and enumerated scopes.

---

## 1. State (all pushed to origin/main)

- Repo: `xiom-packages/packages`, local `E:\xiom-packages\packages`, private
  (Free org). Remote `https://github.com/xiom-packages/packages.git`.
- Identity: repo-local `Lefteris Notas <lefterisnotas@gmail.com>`. Org-wide
  decision: gmail is the author identity in every repo; never the work email.
- Folder inventory (2026-09-23): **366 directories = 71 implemented
  (with `package.xi`) + 295 README-only placeholders** (no SPEC.md, no
  manifest). All 295 placeholder names are collision-free with the stdlib
  namespaces, so they are safe candidates for new packages.
- Manifests: 71 package manifests + the umbrella `packages/package.xi`
  (`xiom.ecosystem`) = 72.
- Package names are dotted (`xiom.core`); folders, repo names and release
  URLs stay hyphenated. The registry reserves both forms and shows the
  official badge.
- Registry: first real package `xiom.hello 0.1.0` is live on staging AND
  production, signed, with metadata; installed back successfully on both.
  - staging sha256 `b12f2a8136c5fe7707c45f2d6841998437fc79bd47350ac6a1a716900a8c83de`
  - production sha256 `2fc7a2aa296abe93dcda09c52787b5c31d9e0b87d6bba338c69c94103ab5d6e8`
  - publisher key `91db373fae4b2891e8aa2616ea9e2347c7c5752f70aab5d7fcdf2a2f9f9b47f1`,
    fingerprint `91:db:37:3f:ae:4b:28:91`
- CI publish path exists but is NOT usable yet: `.github/workflows/publish-registry.yml`
  needs the compiler GitHub release `v0.61.0` (latest is `v0.60.1`, which
  predates `xiom pkg`) and a repo-protection decision.

### Commit trail (newest first)

| Commit | What |
|---|---|
| this | handoff update: namespace audit, deprecations, phased port plan |
| (previous handoff) | SESSION.md first version |
| 8f17170 | readiness allowlist + stable signing-key support in the workflow |
| bbabfa1 | OIDC publish workflow + `COMPILER_VERSION` (v0.61.0) |
| 2d2513b | registry metadata for all 72 manifests (categories/keywords/license/repository) |
| 8e7112f | copyright pass: 149 notices -> `Eleftherios Notas and The XIOM Authors` |
| 7ca0cd3 | xiom.hello xiom.std platform dep; plain `assert` |
| 0d17b1e | xiom.hello package added |
| f743308 | dotted package names + `generate_index.ps1` fixes + index regen |

---

## 2. Key paths

| Path | What |
|---|---|
| `packages/<name>/package.xi` | manifest (name, version, description, authors, modules, deps, categories, keywords, license, repository) |
| `packages/<name>/STATUS.json` | **to be created** (readiness file; see §5) |
| `packages/index.json` | generated legacy fallback index; run `.\generate_index.ps1` after manifest changes |
| `generate_index.ps1` | legacy generator: manifest name (folder fallback + warning), `deps:` parsing, folder-keyed release URLs |
| `.github/workflows/publish-registry.yml` | OIDC batch/canary publish (dispatch + `eco-v*` tags) |
| `.github/publish-allowlist.txt` | current publish gate, **52 names** (see §4) |
| `COMPILER_VERSION` | `v0.61.0` (workflow toolchain pin) |
| `ecosystem/` | historical reports -- do NOT edit |
| `.kilo/worktrees/second-sprout` | stale clean worktree at `7ca0cd3`; can be pruned |

Toolchain on this machine:

- Installed `xiom` is **v0.58.0** (`C:\Users\lefte\AppData\Local\xiom\bin`) --
  stale, has no `xiom pkg`. Upgrade is a Phase 0 task.
- Working v0.61.0 binaries: `E:\xiom-lang\xiom\target\release\xiom.exe` and
  `xiom-pkg.exe` (also a newer debug build).
- Current stdlib: `E:\xiom-lang\stdlib` (`XIOM_STDLIB`); its manifest still
  declares the legacy `xiom-std`, the compiler resolves both names.
- Signing key: `C:\Users\lefte\AppData\Local\xiom\keys\default.key`
  (fingerprint `91:db:37:3f:ae:4b:28:91`).
- Run tests: `$env:XIOM_STDLIB='E:\xiom-lang\stdlib'; xiom --run tests\<suite>.xi`
  (run from the package dir; `a.exe` is a compiler output and gitignored).

---

## 3. Readiness classification (2026-09-21)

Criterion: README marks the package implemented, non-test source has functions
with bodies (not declaration-only), no stub markers dominating, and no
wholesale "FFI bridge not linked" error paths.

- **62 REAL** of 71 non-umbrella manifests; 57 were publishable.
- Excluded: 7 declaration-only (`xiom.bullet`, `xiom.libsodium`, `xiom.libuv`,
  `xiom.openal`, `xiom.ros2`, `xiom.stb`, `xiom.wasmtime`), `xiom.sql` (stub
  body), `xiom.ffi` (no source in this repo; stdlib owns the module), 5
  FFI-not-linked (`xiom.redis`, `xiom.postgres`, `xiom.libtorch`, `xiom.numpy`,
  `xiom.sqlite`), plus policy exclusions `xiom.std` + `xiom.ecosystem`.
- "REAL" does NOT mean ported: the code targets the old stdlib (e.g.
  `xiom.log` fails with T001 API drift). Porting is the workstream.

---

## 4. Namespace audit (2026-09-23) -- new policy

**Rule: a package may not declare modules equal to, or nested under, a stdlib
module namespace.** stdlib has 1614 modules; a package living inside one of
them makes `use xiom.<x>;` ambiguous (the compiler picks one silently; W001
warnings already show this for duplicate module files).

Five packages are affected:

| Package | Evidence | Decision (proposed) |
|---|---|---|
| `xiom-math` | package modules `xiom.math.{prelude,vec2,vec3,vec4,mat4,quat}`; stdlib has `xiom.math.vectors`, `xiom.math.matrices` and `xiom.geom.{vector,matrix,quat,quaternion}` | **Deprecate** -- duplicate of stdlib math/geom |
| `xiom-log` | package modules `xiom.log.{logger,format,types}`; stdlib has `xiom.log.{color,json,levels,sinks}` | **Deprecate** -- stdlib owns logging |
| `xiom-net` | package modules `xiom.net.{dns,tcp,udp}` are exact duplicates; stdlib has 30 `xiom.net.*` modules | **Deprecate** -- stdlib owns networking |
| `xiom-test` | package declares `module xiom.test`; stdlib has `xiom.test`, `.assert`, `.harness` (all suites use it) | **Deprecate** -- stdlib owns the test framework |
| `xiom-core` | package is durable-storage/WAL/txn for db engines under `xiom.core.*`; stdlib owns `xiom.core` (error/ids/limits/contracts) | **Rename** to `xiom.durable` (package + modules) before porting; folder `packages/xiom-core` -> `packages/xiom-durable` in the same commit |

Consequences already applied:

- `.github/publish-allowlist.txt` is now **52 names** (the 5 above removed).
- Registry scope enumeration must be updated (relay to the registry session):
  71 -> 66 names (drop `xiom.math`, `xiom.log`, `xiom.net`, `xiom.test`,
  `xiom.core`), plus `xiom.durable` if/when it is published.
- The umbrella `packages/package.xi` `packages:` list still contains the five
  names; clean it up together with the deprecation banners once the owner
  confirms.
- Deprecation handling for the four: add a `Deprecated` banner to each README,
  set `STATUS.json` `stage: "deprecated"`, `excluded_reason: "superseded by
  stdlib"`, keep the folder for history, never publish.

Pending owner confirmation: the four deprecations and the `xiom.durable`
rename. The allowlist change is a safety gate and is already in.

---

## 5. Readiness model to adopt (Phase 0)

Per-package `STATUS.json` inside the folder (travels with the repo split):

```json
{
  "package": "xiom.durable",
  "stage": "incubating",            // incubating | ported | stable | deprecated
  "compiler": "v0.61.0",
  "stdlib": ">=0.60.0 <1.0.0",
  "tests": {
    "suite": "tests/test_conformance.xi",
    "status": "unknown",            // unknown | pass | fail
    "passed": null, "failed": null,
    "run_by": null,                 // subagent id/session that ran it
    "commit": null, "checked": null
  },
  "publish": false,
  "excluded_reason": null
}
```

Rules:

- `publish: true` requires `stage: stable`; `stable` requires a green suite on
  the pinned compiler.
- **The subagent that works on a package must run its conformance suite and
  record `run_by`, `commit`, `checked`, and the pass/fail counts.** No stage
  advance without a green run from the working agent. At graduation a second
  agent re-runs the suite from a fresh checkout.
- The workflow derives the publish gate from these files once every package
  has one (keep the allowlist in sync until then).
- Keep readiness out of `package.xi`; the registry manifest stays clean.

---

## 6. Roadmap (updated 2026-09-23)

1. **Phase 0 -- toolchain + harness + triage.**
   - Upgrade the local compiler to the pinned v0.61.0 (installed v0.58 is
     stale; use the repo release meanwhile).
   - Add `scripts/xiom.ps1` (resolve `XIOM_COMPILER` -> installed pin -> repo
     release; set `XIOM_STDLIB`), `scripts/status.ps1` (validate/list/update
     STATUS.json), `scripts/namespace-check.ps1` (the §4 rule),
     `scripts/port.ps1 -Package <name>` (compile + conformance suite, print
     diagnostics, never flip stage/publish itself).
   - Seed `STATUS.json`: 52 allowlisted -> `incubating`; the 4 deprecations ->
     `deprecated`; `xiom-core` -> blocked pending rename; placeholders
     untouched.
2. **Phase 1 -- small greenfield packages first** (no legacy debt, fast
   production grade). Pick 4-6 from the collision-free placeholders, e.g.
   `xiom.lru`, `xiom.ttl`, `xiom.flags`, `xiom.option`, `xiom.retry`,
   `xiom.plural`. Each gets a SPEC (placeholders only have READMEs), source,
   tests, `STATUS.json`, then a staging publish + install-back. These are also
   the first graduation candidates. Note: every new name needs a registry
   scope addition (relay via owner) before OIDC publish.
3. **Phase 2 -- foundations port:** `xiom.durable` (renamed core) first, then
   `xiom.algo`, `xiom.json`, and the small pure-XIOM set.
4. **Phase 3 -- network/web port:** http, websocket, rest, graphql, realtime,
   micro (`net` is deprecated).
5. **Phase 4 -- data/ai port:** arrow, pandas, protobuf, kafka, onnx,
   tensorflow, torch, opencv; numpy/sqlite when linked.
6. **Phase 5 -- bridges + graphics/db:** freeze the FFI ABI with the
   compiler/stdlib sessions, build ONE reference bridge (`xiom.zstd`) plus a
   bridge CI template, then batch the rest (incl. the 5 FFI-not-linked).
7. **Phase 6 -- graduation cohorts:** `ops/docs/REPO_MIGRATION_RUNBOOK.md`
   §5.6 filter-repo per package into `xiom-packages/xiom-<name>` (history
   preserved); §6 wiring (README, LICENSE-MIT/LICENSE-APACHE/NOTICE per
   LICENSING.md §2, `.kilo/` + `kilo.json`, CI, rulesets, per-package OIDC).

**Publish vs promote (answer):** yes, a folder publishes without becoming a
repo -- the workflow packs `packages/<folder>` and publishes it. Promotion is
orthogonal. Recommended order: port -> green suite -> `STATUS: stable` ->
staging publish + install-back -> production publish (registry scope already
enumerated) -> make the folder repo-ready -> graduate via §5.6 -> switch that
package's publishing to its own repo workflow. Graduate a package when its
API is stable and it has consumers or an independent release cadence, not
merely because it is green.

**Port definition of done:** dotted manifest + metadata, compiles on the
pinned compiler + current stdlib, conformance tests pass (run by the working
subagent), no `not linked` paths, honest README/SPEC, `STATUS.json` stable +
publish, one staging publish installed back.

---

## 7. Agent / MCP plan

- Use the compiler's own MCP (`xiom-mcp`, specced in `xiom/docs/MCP_SERVER.md`;
  MVP tools `compile_and_analyze`, `explain_error`, `audit_safety`) instead of
  shell-parsing diagnostics. Coordinate with the compiler session to ship the
  3-tool MVP.
- Add a small read-only registry MCP later (search/package info/verify).
  Publishing stays in the OIDC workflow; agents never publish.
- Per-package agents in `.kilo/agent/`: `porter`, `tester`, `docs`; one
  worktree per package; copy `.kilo/` + `kilo.json` into each graduated repo.
- Agents must use the pinned local compiler via `scripts/xiom.ps1`; never
  build the compiler from source unless the pin is unavailable.

---

## 8. Open decisions (owner)

1. **Confirm the four deprecations** (`xiom.math`, `xiom.log`, `xiom.net`,
   `xiom.test`) and the `xiom.core` -> `xiom.durable` rename (or move that
   package to the foundation db/vector repos).
2. **Registry scope update:** 71 -> 66 names + `xiom.durable` later.
3. **Repo protection:** private + Free org => no environment reviewers and no
   tag rulesets. Make the repo public (registry session's recommendation) so
   `registry-publish` gets required reviewers, or accept no GitHub-side gate.
   The registry production OIDC entry stays disabled until settled.
4. **Stable first-party signing key:** set the `XIOM_SIGNING_KEY` secret
   (64 hex) so the batch shares one publisher fingerprint. Proposal: reuse the
   key that signed `xiom.hello` (`91:db:37:3f:ae:4b:28:91`):
   `gh secret set XIOM_SIGNING_KEY --repo xiom-packages/packages < "C:\Users\lefte\AppData\Local\xiom\keys\default.key"`
5. **Compiler v0.61.0 GitHub release:** required for the canary and the batch
   (`xiom-0.61.0-linux-x64.tar.gz` with `bin/xiom` + `bin/xiom-pkg`).
6. **`eco-v0.1.0` tag:** only after the compiler release, a green Phase 1
   cohort, and the protection decision. `xiom.ecosystem` stays excluded.
7. **License follow-ups (separate pass):** only 3/341 `.xi` files carry the
   dual SPDX identifier; no `LICENSE-MIT`/`LICENSE-APACHE`/`NOTICE` in the
   monorepo (LICENSING.md §2); 71 manifests still use `authors: ["XIOM Team"]`;
   no `.md` files carry the §1 header block.

---

## 9. Guardrails (do not violate)

- Never publish from a session manually; publish only through the workflow,
  only allowlisted names, only with a green suite run by the working subagent.
  Versions are immutable forever.
- Namespace rule (§4): no package module may equal or live under a stdlib
  module namespace; run `scripts/namespace-check.ps1` before adding a package.
- Do not rename folders or package directories except the explicitly planned
  `xiom-core` -> `xiom-durable` rename (one atomic commit).
- Do not touch `deps:`/`dev-deps:` except to fix dotted names.
- No history rewrites, no force pushes. Conventional commits, atomic,
  commit + push to `main`.
- No tokens in chat, repo, or commit messages. Token files live in
  `%TEMP%\kilo\` and are never committed. Publishing uses OIDC in CI.
- Leave `ecosystem/` historical reports and AUDIT/SESSION docs alone.
- PowerShell gotcha: `"$name: text"` parses as a drive-qualified variable;
  write `"${name}: text"`.

## 10. Coordination contracts

- **Registry session:** scope list 71 names accepted earlier; it must be
  updated per §4 (66 + `xiom.durable`). New package names (Phase 1
  greenfield) each need a scope addition before OIDC publish. `xiom.std`
  stays with the stdlib repo; batch from `eco-v*`; trusted tokens require
  signatures; the registry extracts
  description/categories/keywords/license/repository from the published
  tarball; the new server deploys before the canary.
- **Compiler session:** fixed in `1fcb4855` (unqualified `assert`,
  `xiom.std` platform dep, `keygen --help`, rebuilt release). Needs to cut the
  v0.61.0 GitHub release and ship the `xiom-mcp` MVP.
- **.github session:** licensing pass complete here (canonical holder
  `Copyright (c) 2026 Eleftherios Notas and The XIOM Authors`); SPDX pass and
  org protection/rulesets are their scope.
