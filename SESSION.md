# xiom-packages/packages -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-09-25, by the packages session (continuation of the
2026-09-23 handoff). The commit that adds this file is HEAD; check
`git log -1 --format=%h %s` before starting.

**Mission:** turn this monorepo into real, production-grade package repos.
Start from small packages that can reach production grade quickly, port the
legacy code in dependency order, and graduate stable packages to
`xiom-packages/xiom-<name>` with OIDC publishing and enumerated scopes.

---

## 1. State (all pushed to origin/main)

- Repo: `xiom-packages/packages`, local `E:\xiom-packages\packages`, private
  (Free org). Remote `https://github.com/xiom-packages/packages.git`.
- Identity: repo-local `Lefteris Notas <lefterisnotas@gmail.com>`. Org-wide
  decision: gmail is the author identity in every repo; never the work email.
- Folder inventory (2026-09-25): **185 implemented dirs (with `package.xi`) +
  216 README-only placeholders + the umbrella `packages/package.xi`**.
  Since the 2026-09-23 handoff: 118 new packages were implemented (79 by
  converting placeholders, 39 brand-new dirs); the four deprecated dirs were
  deleted and `xiom-core` renamed to `xiom-durable`.
- `STATUS.json` totals: **118 stable, 4 ported, 63 incubating**;
  **122 green suites, 2,687 recorded tests**.
  - stable = the 118 greenfield packages (all `publish: false`, waiting on
    allowlist/registry/protection).
  - ported = `xiom.sensor`, `xiom.control`, `xiom.json` (pure, promotable) and
    `xiom.kafka` (librdkafka FFI stubs remain; keep `ported`).
  - incubating = 63 legacy packages (includes `xiom.durable`, the renamed
    core, not yet ported).
- `.github/publish-allowlist.txt`: **170 names** = 118 stable ready + 52
  grandfathered legacy names (`.github/allowlist-baseline.txt`, warn-only in
  the guard). `scripts/allowlist-guard.ps1`: 0 failures.
- Namespace audit **resolved**: `namespace-check` reports
  **185 packages, 283 modules, 0 conflicts** (2026-09-25).
- Toolchain: pin `COMPILER_VERSION` = **v0.61.3**; installed compiler
  v0.61.3 (`C:\Users\lefte\AppData\Local\xiom\bin`); repo release dir has
  v0.61.1; GitHub releases v0.61.1 + v0.61.3 exist. Stdlib
  `E:\xiom-lang\stdlib` (1627 module namespaces, still evolving).
- Signing: `XIOM_SIGNING_KEY` is SET; staging/production artifacts share the
  first-party key `4f3b47f3ae17b13c...`.
- Licensing: `LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE` and a pointer
  `LICENSE` are committed per LICENSING.md §2. SPDX pass repo-wide and the
  §1 `.md` header block remain .github-session scope.
- 265 commits landed since the previous handoff (`b2bdde1..`).

### Commit trail (recent milestones)

| Commit | What |
|---|---|
| this | SESSION.md refresh for the next packages session |
| e66afc7 | allowlist wave 19 + index/report regeneration |
| bb7d18b | bounded staging badge-canary override (`allow_unready`) |
| ad13b07 | allowlist wave 18 + index/report |
| 7e77457 | publish loop enforces readiness (skip/refuse) |
| c6690cb / 2080fda | badge `stage` written from STATUS.json into packaged manifests |
| cfe2b40 | readiness guard workflow + 6 allowlist additions (registry v2 names) |
| 8946171 / bcabb9c | `status.ps1 -Action repin` + pin bump to v0.61.3 |
| 54c241f | LICENSE-MIT/LICENSE-APACHE/NOTICE per LICENSING.md §2 |
| be6d1ec | Phase 0 harness (xiom/status/namespace-check/port) + STATUS seed |
| b2bdde1 | previous handoff (2026-09-23) |

Per-package commits (`feat: add <pkg>...` + `chore: record <pkg>...`) are in
`git log`; each package's `STATUS.json` names its `run_by` subagent/session id
and the tested commit.

---

## 2. Key paths and harness

| Path | What |
|---|---|
| `scripts/xiom.ps1` | toolchain resolver (`XIOM_COMPILER` -> installed >= pin -> repo release), sets `XIOM_STDLIB`; dot-sourceable |
| `scripts/port.ps1 -Package <name>` | namespace gate + compile + run conformance suite; `-Quiet` for scripted runs; `-NoRun` = `--emit-ir` compile-only; never writes STATUS |
| `scripts/status.ps1` | `-Action list` / `validate` / `seed` / `repin` / `report` / `update`; `update` records runs and enforces the readiness gates |
| `scripts/namespace-check.ps1` | the §3 rule; `-Package` for implemented names, `-Module` for proposed names |
| `scripts/allowlist-guard.ps1` | CI guard: allowlist entries must be `stable`+green; baseline names warn-only |
| `scripts/port.ps1` + `status.ps1` + `docs/PACKAGE_STATUS.md` | `status.ps1 -Action report` regenerates the doc |
| `generate_index.ps1` | legacy index generator; run after manifest changes |
| `.github/workflows/publish-registry.yml` | OIDC publish: `eco-v*` batch, `xiom-<folder>/v<version>` single package, dispatch canary |
| `.github/workflows/readiness-guard.yml` | CI guard on allowlist/STATUS/report changes |
| `docs/repro/generic-fnptr/` | committed compiler repros (fn-value ABI sprint evidence) |
| `ecosystem/` | historical reports -- do NOT edit |
| `.kilo/worktrees/second-sprout` | stale clean worktree at `7ca0cd3`; can be pruned |

Standard commands (repo root):

```powershell
& .\scripts\xiom.ps1 -Info
& .\scripts\port.ps1 -Package xiom.lru            # verify one package
& .\scripts\status.ps1 -Action validate           # 185/0 expected
& .\scripts\allowlist-guard.ps1                   # 170 allowlisted, 0 failures
& .\scripts\namespace-check.ps1                   # 0 conflicts expected
& .\generate_index.ps1 ; & .\scripts\status.ps1 -Action report
```

Publish gate recap: only allowlisted + `STATUS.json` `stage: stable` with
`tests.status: pass` publishes (batches skip unready with a warning; explicit
tag/dispatch targets on unready names are refused). The one exception is the
bounded staging badge canary (`workflow_dispatch` + `allow_unready=true` +
explicit `package` + staging registry; tags and batches can never use it).

---

## 3. Namespace audit -- RESOLVED (history)

**Rule (still enforced): a package may not declare modules equal to, or
nested under, a stdlib module namespace** (a shared first two dotted
segments is a collision; sharing only `xiom` is not).

Resolution executed 2026-09-23/24 under owner confirmation:

- `xiom.math`, `xiom.log`, `xiom.net`, `xiom.test`: deprecated and **deleted**
  (folders removed; not in the allowlist).
- `xiom.core` -> **`xiom.durable`**: folder, package ident, all 21 module
  namespaces, docs, umbrella list; `STATUS.json` notes "port to current
  stdlib pending". Registry scope pre-provisioned.

`namespace-check` now reports 0 conflicts. New names must pass
`namespace-check.ps1 -Module <name>` before a package is added (the wave
prompts all did).

---

## 4. Readiness model (implemented)

Per-package `STATUS.json` (see §5 example in the previous handoff) with
`stage` in `incubating | ported | stable | deprecated`, `tests.status` in
`unknown | pass | fail`, `publish`, `excluded_reason`. Enforced rules:
`publish: true` requires `stable`; `stable` requires a recorded green run
(`run_by` + `commit` + `checked` + counts). The working agent runs the suite;
the coordinator records it. `status.ps1 -Action repin` realigns `compiler`
after a pin change; `-Action report` regenerates `docs/PACKAGE_STATUS.md`,
which is the human-facing status list (green-light checklist included).

Pin change note: all recorded runs above were made on installed v0.61.3,
which is also the current pin, so records are consistent.

---

## 5. Publishing / registry state (2026-09-25)

- **Staging is live through scope delta v5** (`eco-canary`, 151 scopes +
  3 OIDC publisher entries). v4 covered waves 10-15; v5 covered waves 16-17.
- **Canary coverage**: all 78 previously scoped stable names were canaried
  43+35) and verified; the wave 16/17 sample (`xiom.tar`, `xiom.id3`,
  `xiom.jwt`) plus the **incubating badge canary `xiom.algo`** were dispatched
  and verified on staging (runs `36074481232`, `36074526832`, `36074580156`,
  `36074625612`). `xiom.algo`'s staging record carries
  `"stage": "incubating"` at package and version level -- badge path works.
- **Scope deltas pending** (relay to the registry/ops):
  - wave 18 (10 names): `base58, cidr, crc, macaddr, obj, querystring,
    roman, stl, uri, varint` -> planned v6 delta (151 -> 161).
  - wave 19 (10 names): `ascii85, bitfield, cobs, eml, nmea, pack, pcap,
    punycode, term, tlv` -> the delta after v6.
  - 40 names total pending enumeration before their canaries can run.
- **Environment**: `registry-publish` requires reviewer `Lefteris-Notas`
  (owner); the packages session approves *staging* canary deployments via the
  API as part of dispatching them; production approvals remain owner-side.
- **Production**: owner-account runs already succeeded for the `eco-v0.1.0`
  batch and the `xiom-flags/v0.1.0` per-package tag. Production is gated by
  the owner behind the staging canary + the `eco-v0.1.1` batch (one tag, one
  approval) with the combined delta. Nothing in this repo publishes to
  production by itself.
- Ops note: OIDC canaries are unrelated to browser sign-in; the **OAuth
  callback URL check remains a separate outstanding owner item** (do not fold
  it into publish relays).

---

## 6. Roadmap status

1. **Phase 0 -- toolchain + harness + triage: DONE.** Scripts above, STATUS
   seeded for every implemented package, pin v0.61.3, licenses, badge/guard
   pipeline, bounded badge canary.
2. **Phase 1 -- small greenfield packages: DONE and expanded.** 118 packages
   built, conformance-tested, `stable`, allowlisted (waves 1-19). All pass
   the namespace rule; each has SPEC/README/tests and a STATUS record.
3. **Phase 2 -- foundations port: NEXT.** `xiom.durable` (renamed; not yet
   ported) first, then the pure legacy set (`xiom.algo` etc.). 63 incubating
   package remain; the legacy compile triage is in the previous handoff's
   triage report and `ecosystem/`. The pure head starts are `xiom.algo` and
   the `graphql`/`micro`/`realtime` dependency chain; the mechanical
   `expected ';'` cluster and the T007/FFI clusters need compiler-side
   decisions first.
4. **Phases 3-5 (network/data/bridges): pending**; FFI ABI freeze with the
   compiler/stdlib sessions is the gate for the bridge batch.
5. **Phase 6 graduation:** publish first from the monorepo, promote later
   (filter-repo per §5.6 of the ops runbook, hooks, CI, per-repo OIDC) when a
   package's API is stable and it has consumers/cadence.

Port definition of done: dotted manifest + metadata; compiles on the pinned
compiler + current stdlib; conformance suite green (run by the working
agent); no not-linked paths; honest README/SPEC; `STATUS.json` stable +
publish; one staging publish installed back.

---

## 7. Porter conventions and compiler traps (v0.61.3)

Proven per-package recipe (see `docs/repro/generic-fnptr/`): spawn one
background `task` subagent per package (general agent) with a self-contained
brief: read `packages/xiom-hello` + a sibling of the same kind, deliver
`package.xi`, `src/<x>.xi` (module `xiom.<x>`), `tests/test_conformance.xi`,
`README.md`, `SPEC.md`, `.gitignore` (copy of xiom-hello's); iterate with
`scripts/port.ps1 -Package <name>` until `port: PASS (program_exit=0)`.
Subagents must not commit, must not touch STATUS.json, must not publish.
The coordinator then: verify (re-run), commit, run on the commit, record with
`status.ps1 -Action update ... -RunBy <task id> -Commit <sha>`, commit the
record, allowlist the wave, regenerate index + report, push. Optional
**Agent Manager local sessions** (visible in the UI) work the same way and
have succeeded repeatedly; keep waves at ~10 packages.

Language traps that must be in every porter brief:

1. BUG-17 family: never `==` on Str values read from `Vec[Str]` elements, and
   `str_len`/`.len()` is unreliable on them -- use `str_compare` from
   `xiom.string.compare` and typed locals `let e: Str = v[i];`.
2. Untyped `Vec[Int]` element reads can mis-lower to Str compares; always
   `let x: Int = v[i];`.
3. Never compare `byte_at(...)` directly to a UInt8 constant >= 128; widen
   `(x as Int) & 0xFF`.
4. Passing `&struct.field` (e.g. `&result.value`) into a `&Vec[UInt8]`
   parameter yields an empty vector; bind to a local first.
5. Indexed `Vec[fn]` calls miscompile (access violation): no table-driven
   test dispatch; call tests directly or via `run_test_at(index)`.
6. Do not construct `Ok`/`Err` inside struct-returning functions; use leaf
   helper constructors.
7. Generic fn-pointer limits: single-`T` generics with named callbacks are
   fine; `[T,U]` type-changing callbacks miscompile/crash -- use concrete
   specializations.
8. No `mut` bindings in match patterns; matches must be exhaustive; `module`
   headers take no `;`, `use` statements require one.
9. No `Vec[Float64]` (scalar `Float64` is fine); prefer integer/fixed-point
   units and document rounding.
10. Free functions only; no `self` methods, no inline lambdas, no
    `Vec[StructType]` (parallel `Vec` fields instead). Avoid a free function
    named `log` (collides with libm). E001 borrow warnings are advisory.
11. Every `.xi` starts with the copyright + SPDX lines.

---

## 8. Open decisions (owner) / outstanding items

1. **Scope deltas** for wave 18 (v6, 151 -> 161) and wave 19 (next delta);
   40 names total pending before those canaries.
2. **`eco-v0.1.1` production greenlight** (one tag, one approval) for the
   combined stable set; production is otherwise owner-gated.
3. **Repo protection closure**: the required-reviewer environment is live;
   confirm this satisfies the §8.3 decision.
4. **OAuth callback URL check** (owner): both GitHub OAuth app callback URLs,
   outstanding from the earlier relay; kept separate from publish relays.
5. **Wave 20+ queue**: 216 placeholders remain; strong small candidates are
   more format/protocol codecs (e.g. `ical`, `vcf`, `gbnf`, `dns`, `can`,
   `modbus`, `bitpack`-adjacent names as they pass namespace-check).
6. **Repo-wide SPDX/`.md` header pass** and the 71 legacy manifests still
   using `authors: ["XIOM Team"]` -- .github-session scope.
7. **`xiom.durable` port** (Phase 2 opener) and the pure legacy frontier.
8. Note: the local Kilo build rejects new `.kilo/agent`/command frontmatter
   (`No context found for instance`); persistent agent definitions were
   removed to keep config clean. Use `task` subagents / Agent Manager local
   sessions instead.

---

## 9. Guardrails (do not violate)

- Never publish manually; publish only through the workflow, only allowlisted
  names, only with a recorded green run. Versions are immutable forever.
- Namespace rule: run `namespace-check.ps1 -Module` before adding a name.
- The readiness filter stays: batches skip unready names, explicit targets
  are refused; the only override is the staging badge canary described in §2.
- Do not rename folders except the already-done `xiom-core` ->
  `xiom-durable`; do not touch `deps:`/`dev-deps:` except dotted-name fixes.
- No history rewrites, no force pushes. Conventional commits, atomic,
  commit + push to `main`.
- No tokens in chat, repo, or commit messages; publishing uses OIDC in CI.
- Leave `ecosystem/` historical reports alone. (SESSION.md is the live
  handoff and is updated by the packages session.)
- PowerShell gotcha: `"$name: text"` parses as a drive-qualified variable;
  write `"${name}: text"`.

---

## 10. Coordination contracts

- **Registry/ops session:** scope deltas per §8.1; staging eco-canary counts
  (`publishers: 3`, per-label scopes); production file gated behind the
  staging canary + `eco-v0.1.1`. Publisher identity is
  `xiom-packages/packages`, workflow `publish-registry.yml`,
  `refs/heads/main`, event `workflow_dispatch` (staging canaries) or tag
  pushes (production).
- **Compiler session:** accepted the three fn-value/ABI repros
  (`docs/repro/generic-fnptr/`) into their unification sprint; new findings
  from this session to relay: `&struct.field` -> `&Vec[UInt8]` empty-vector
  misbehavior, `str_len` on `Vec[Str]` elements, and the `Vec[fn]` dispatch
  miscompile (all with per-package SPEC notes).
- **.github session:** licensing pass done here (LICENSE-MIT/APACHE/NOTICE,
  canonical holder); SPDX/`.md` header pass and rulesets remain theirs.
- **Owner:** relays, scope deltas, production greenlight, OAuth callback
  check, Phase 2 direction.
