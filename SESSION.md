# xiom-packages/packages -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-09-23, by the packages session. The commit that adds this
file is HEAD; check `git log -1 --format=%h %s` before starting.

**Mission:** turn this staging monorepo into real, production-grade package
repos. Port the old-stdlib code to the current compiler + stdlib, make each
package repo-ready, then graduate stable packages to
`xiom-packages/xiom-<name>` with OIDC publishing and enumerated scopes.

---

## 1. State (all pushed to origin/main)

- Repo: `xiom-packages/packages`, local `E:\xiom-packages\packages`, private
  (Free org). Remote `https://github.com/xiom-packages/packages.git`.
- Identity: repo-local `Lefteris Notas <lefterisnotas@gmail.com>`. Org-wide
  decision: gmail is the author identity in every repo; never the work email.
- 72 manifests: 70 package manifests + `xiom.hello` + the umbrella
  `packages/package.xi` (`xiom.ecosystem`). 365 directories total; ~293 are
  README-only placeholders with no manifest.
- Package names are dotted (`xiom.core`); folders, repo names, release URLs
  stay hyphenated. The registry reserves both forms and shows the official
  badge for `xiom.*` / `xiom-*`.
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
| this | session handoff |
| 8f17170 | readiness allowlist (57) + stable signing-key support in the workflow |
| bbabfa1 | OIDC publish workflow + `COMPILER_VERSION` (v0.61.0) |
| 2d2513b | registry metadata for all 72 manifests (categories/keywords/license/repository) |
| 8e7112f | copyright pass: 149 notices -> `Eleftherios Notas and The XIOM Authors` |
| 7ca0cd3 | xiom.hello ixom.std platform dep; plain `assert` |
| 0d17b1e | xiom.hello package added |
| f743308 | dotted package names + `generate_index.ps1` fixes + index regen |

---

## 2. Key paths

| Path | What |
|---|---|
| `packages/<name>/package.xi` | manifest (name, version, description, authors, modules, deps, categories, keywords, license, repository) |
| `packages/<name>/STATUS.json` | **to be created** (readiness file; see §4) |
| `packages/index.json` | generated legacy fallback index; run `.\generate_index.ps1` after manifest changes |
| `generate_index.ps1` | legacy generator: manifest name (folder fallback + warning), `deps:` parsing, folder-keyed release URLs |
| `.github/workflows/publish-registry.yml` | OIDC batch/canary publish (dispatch + `eco-v*` tags) |
| `.github/publish-allowlist.txt` | current publish gate, 57 names |
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

## 3. Readiness classification (2026-09-21 pass)

Criterion: README marks the package implemented, non-test source has functions
with bodies (not declaration-only), no stub markers dominating, and no
wholesale "FFI bridge not linked" error paths.

- **62 REAL** of 71 non-umbrella manifests.
- 57 publishable (allowlist): the 62 minus the 5 FFI-not-linked below.
- Excluded 15: 7 declaration-only (`xiom.bullet`, `xiom.libsodium`,
  `xiom.libuv`, `xiom.openal`, `xiom.ros2`, `xiom.stb`, `xiom.wasmtime`),
  `xiom.sql` (stub body), `xiom.ffi` (no source in this repo; stdlib owns the
  module), 5 FFI-not-linked (`xiom.redis`, `xiom.postgres`, `xiom.libtorch`,
  `xiom.numpy`, `xiom.sqlite`), and policy exclusions `xiom.std` (not here) +
  `xiom.ecosystem` (umbrella).
- "REAL" does NOT mean ported: the code is written against the old stdlib
  (e.g. `xiom.log` fails with T001 API drift). Porting is the next workstream.

---

## 4. Readiness model to adopt (Phase 0)

Per-package `STATUS.json` inside the folder (travels with the repo split):

```json
{
  "package": "xiom.core",
  "stage": "incubating",            // incubating | ported | stable
  "compiler": "v0.61.0",
  "stdlib": ">=0.60.0 <1.0.0",
  "tests": { "suite": "tests/test_conformance.xi", "status": "unknown", "checked": null },
  "publish": true,                  // mirrors the allowlist until all files exist
  "excluded_reason": null
}
```

Rules: `publish: true` requires `stage: stable`; `stage: stable` requires a
green suite on the pinned compiler; agents may edit everything except flipping
`stable`/`publish` without a green run. The workflow derives the publish gate
from these files once every package has one (keep the allowlist in sync until
then). Do not put readiness into `package.xi`; keep the registry manifest
clean.

---

## 5. Roadmap

1. **Phase 0 -- toolchain + harness (start here).** Upgrade the local
   compiler to v0.61.0; add `scripts/xiom.ps1` (resolve `XIOM_COMPILER` ->
   installed pin -> repo release; set `XIOM_STDLIB`), `scripts/status.ps1`
   (validate/list/update STATUS.json), `scripts/port.ps1 -Package <name>`
   (compile + run the conformance suite, print diagnostics, never auto-set
   stage). Seed `STATUS.json` for the 57 allowlisted packages.
2. **Phase 1 -- foundations:** `xiom.core` (reference), `xiom.math`,
   `xiom.algo`, `xiom.json`, `xiom.log`, `xiom.test`.
3. **Phase 2 -- network/web:** net, http, websocket, rest, graphql, realtime,
   micro.
4. **Phase 3 -- data/ai:** arrow, pandas, protobuf, kafka, onnx, tensorflow,
   torch, opencv; numpy/sqlite when linked.
5. **Phase 4 -- bridges + graphics/db:** freeze the FFI ABI with the
   compiler/stdlib sessions, build ONE reference bridge (`xiom.zstd`) plus a
   bridge CI template, then batch the rest (incl. the 5 FFI-not-linked).
6. **Phase 5 -- graduation:** per `ops/docs/REPO_MIGRATION_RUNBOOK.md` §5.6,
   `git filter-repo --path packages/xiom-<name>/` into
   `xiom-packages/xiom-<name>` (history preserved); apply §6 wiring (README,
   LICENSE-MIT/LICENSE-APACHE/NOTICE per LICENSING.md §2, `.kilo/` +
   `kilo.json`, CI, rulesets, OIDC scope per package).

**Port definition of done:** dotted manifest + metadata, compiles on the
pinned compiler + current stdlib, conformance tests pass, no `not linked`
paths, honest README/SPEC, `STATUS.json` stable + publish, one staging publish
installed back.

---

## 6. Agent / MCP plan

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

## 7. Open decisions (owner)

1. **Repo protection:** private + Free org => no environment reviewers and no
   tag rulesets. Make the repo public (recommended by the registry session)
   so `registry-publish` gets required reviewers, or accept no GitHub-side
   gate. The registry production OIDC entry stays disabled until this is
   settled.
2. **Stable first-party signing key:** set the `XIOM_SIGNING_KEY` secret
   (64 hex) so the batch shares one publisher fingerprint. Proposal: reuse
   the existing key (fp `91:db:37:3f:ae:4b:28:91`) that signed `xiom.hello`:
   `gh secret set XIOM_SIGNING_KEY --repo xiom-packages/packages < "C:\Users\lefte\AppData\Local\xiom\keys\default.key"`
3. **Compiler v0.61.0 GitHub release:** required for both the canary and the
   batch (`xiom-0.61.0-linux-x64.tar.gz` with `bin/xiom` + `bin/xiom-pkg`).
4. **`eco-v0.1.0` tag:** only after the compiler release, the port gate, and
   the protection decision. `xiom.ecosystem` stays excluded unless it gets
   its own scope.
5. **License follow-ups (separate pass):** only 3/341 `.xi` files carry the
   dual SPDX identifier; no `LICENSE-MIT`/`LICENSE-APACHE`/`NOTICE` in the
   monorepo (LICENSING.md §2); 71 manifests still use `authors: ["XIOM Team"]`;
   no `.md` files carry the §1 header block.

---

## 8. Guardrails (do not violate)

- Never publish from a session: publish only through the workflow, only
  allowlisted names, only with a green suite. Versions are immutable forever.
- Do not rename folders or package directories; dotted names live only in
  `package.xi`.
- Do not touch `deps:`/`dev-deps:` except to fix dotted names.
- No history rewrites, no force pushes. Conventional commits, atomic,
  commit + push to `main`.
- No tokens in chat, repo, or commit messages. Token files live in
  `%TEMP%\kilo\` and are never committed. Publishing uses OIDC in CI.
- Leave `ecosystem/` historical reports and AUDIT/SESSION docs alone.
- PowerShell gotcha: `"$name: text"` parses as a drive-qualified variable;
  write `"${name}: text"`.

## 9. Coordination contracts

- **Registry session:** scope list accepted (71 names); `xiom.std` stays with
  the stdlib repo; batch from `eco-v*`; trusted tokens require signatures;
  stub gate satisfied by the allowlist. Registry extracts
  description/categories/keywords/license/repository from the published
  tarball; the new server deploys before the canary.
- **Compiler session:** fixed in `1fcb4855` (unqualified `assert`,
  `xiom.std` platform dep, `keygen --help`, rebuilt release). Needs to cut the
  v0.61.0 GitHub release and ship the `xiom-mcp` MVP.
- **.github session:** licensing pass complete here (canonical holder
  `Copyright (c) 2026 Eleftherios Notas and The XIOM Authors`); SPDX pass and
  org protection/rulesets are their scope.
