# xiom-packages/packages -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-09-26, by the packages session (continuation of the
2026-09-23 handoff; refreshed during waves 32/33, after `eco-v0.1.1`
completed and `eco-v0.1.2` hit the registry scope delta). Check
`git log -1 --format=%h %s` before starting.

## 0. Current state + next-session prompt (read this first)

**State at handoff refresh (2026-09-26 ~16:05, waves 32+33 complete):**
- 324 implemented dirs / 197 README-only placeholders; **257 stable / 4
  ported / 63 incubating**; **261 green suites / 5,634 recorded tests**;
  allowlist **309** (wave 32 +9, wave 33 +10); namespace **324 packages /
  422 modules / 0 conflicts**; `validate` = 324/0. Wave-33 wrap commit
  `471c5e3`.
- **Wave 33: COMPLETE (10/10).** `imap` 18/18, `avro` 20/20, `mp3` 21/21,
  `gif` 20/20, `mkv` 20/20, `amqp` 21/21, `png` 17/17, `mp4` 33/33,
  `snmp` 19/19, `thrift` 24/24 -- 213 tests, all seeded `stable` with
  RunBy/Commit records, allowlisted by the wrap. Trap-14 audits clean on
  every package (the write tooling reintroduced mixed brackets in `gif` and
  `mp3`; both fixed pre-commit).
- **Wave 32: COMPLETE (10/10).** `xiom.rpm` was recovered on the third
  attempt (skeleton-first brief; 19/19; `b7fc365` + record `d9f12a2`; the
  resolution is recorded in `docs/failed_attempts.md`). Wave-32 wrap commit
  `dccebd1` added **9** allowlist names (`pop3, smtp, ftp, passwd, efi, hid,
  cab, pci, rpm`); `xiom.tftp` was already allowlisted since wave 15
  (`f4ff9fa`), so the intended 10-name append was 9 net-new. Index/report
  regeneration was deferred to the wave-33 wrap so the wrap commit would
  not capture the ten in-flight wave-33 dirs as `(none)` rows.
- **Production `eco-v0.1.1`: SUCCESS** -- attempt 3 (`gh run rerun` +
  approval) completed 15:02Z, publishing the remaining waves 18-30 names;
  the registry index now carries **231 packages**. Run `36240424222`.
- **Production `eco-v0.1.2` (waves 31+32, 19 new names): CUT, FAILED on
  scopes -- attempts 1, 2 and 3.** Run `36251091427` attempt 1 failed
  15:25Z; attempt 2 (15:40Z, after the first ops recreate) failed 15:54Z;
  attempt 3 (16:55Z, after ops deploy `394db71` declared the rate-limit
  knobs and the registry restarted at 16:54:38Z) failed 17:08Z. All three
  reproduce HTTP 403 `token "eco-release" is not scoped to publish
  "xiom.<name>"` (`scope_denied`) for the delta names -- attempt 3's first
  403 hit `xiom.acpi` at 16:55:55Z, one second into the run, with **no 429s
  of any kind**. Later names show HTTP 401 `oidc_token_expired` only
  because each name retries after 30 s and the job's single minted OIDC
  token (~6 min life) expires mid-run. **BLOCKED on the registry/ops scope
  enumeration for the 19 names**; rate-limit config is orthogonal. Rerun
  `36251091427` after the scopes land (it skips published versions); do not
  re-cut the tag.
- **Workflow finding (secondary):** the publish job mints **one** OIDC
  token at job start and reuses it for every package; runs longer than
  ~6 min fail every remaining publish with `oidc_token_expired` (the retry
  storm on the 19 blocked names is what pushed `eco-v0.1.2` past the token
  life). Re-minting per attempt (or on 401) is a
  `.github/workflows/publish-registry.yml` fix for the .github session.
- **tftp version collision (owner decision):** `xiom.tftp@0.1.0` in the
  registry is the 2026-09-24 build published by `eco-v0.1.1` from tag
  `a6e678e` (STATUS record `be38152`); the wave-32 rewrite (`ae3c233`)
  carries the same version and cannot republish (versions immutable).
  Either accept the published build or bump tftp to 0.1.1 in a later batch.
- **Production-direct policy is in force** (owner standing instruction,
  section 5): one `eco-*` tag per ready batch, gate approvals handled by
  this session; staging only when the owner explicitly asks for it.

**Next actions, in order:**
1. **Relay the scope delta to registry/ops** -- the 19 wave 31+32 names need
   production publish scopes before `eco-v0.1.2` can succeed. Evidence is in
   section 5 (attempts 1 and 2 of run `36251091427`, `scope_denied`, no
   429s). Afterwards: `gh run rerun 36251091427` + approve the gate (JSON
   body via temp file:
   `{"state":"approved","environment_ids":[22424011031],"comment":"..."}`
   POSTed with `--input <file>`); it skips published versions and should
   take ~2 min with no retry storm. Then confirm "batch done" to ops (they
   restore `PUBLISH_RATE_MAX=20` per registry §21 D5).
2. Waves 32+33 are complete and wrapped (`dccebd1`, `471c5e3`); index and
   report are regenerated (257 stable, no `(none)` rows).
3. When `eco-v0.1.2` succeeds (after the scope delta), refresh this file and
   report the run ID.
4. Wave 34: pick ~10 collision-free names; request production scopes for the
   wave-33 names in the same relay if convenient (`png, gif, mp3, mp4, mkv,
   snmp, imap, amqp, thrift, avro`); run `namespace-check.ps1 -Module <each>`
   first; split 4 Agent Manager local + 6 background tasks with the full
   18-trap brief (section 7); integrate + wrap as usual.

**Copy-paste prompt for the next session:**

```text
You are the packages session for xiom-packages/packages (local
E:\xiom-packages\packages, remote github.com/xiom-packages/packages,
private). Read SESSION.md first -- sections 0 and 5 are the live handoff.
Repo-local identity must be "Lefteris Notas <lefterisnotas@gmail.com>".
Publishing policy: PRODUCTION-DIRECT by default (one eco-* tag per ready
batch; this session handles the registry-publish gate approval). Staging
only when the owner explicitly asks.

Start by running: git fetch; git status -sb; git log -1; then
& .\scripts\status.ps1 -Action validate and & .\scripts\allowlist-guard.ps1.

Then do, in order:
1. eco-v0.1.2 (run 36251091427) is BLOCKED on the registry/ops scope delta
   for the 19 wave 31+32 names (section 5; both attempts show scope_denied,
   no 429s). Confirm the scopes are live, then gh run rerun 36251091427 +
   approve the gate; it skips already-published versions. Never re-cut the
   tag. On success, confirm "batch done" to ops so they restore
   PUBLISH_RATE_MAX=20.
2. Request production scopes for the wave-33 names (10, section 5), then
   continue wave 34 with the standard recipe (namespace-check first,
   4 Agent Manager + 6 background tasks, 18 traps in every brief,
   integrate + wrap).
```

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
- Folder inventory (2026-09-26, waves 32+33 complete): **324 implemented
  dirs (with `package.xi`) + 197 README-only placeholders + the umbrella
  `packages/package.xi`**. Since the 2026-09-23 handoff: 257 new packages
  were implemented (placeholder conversions + brand-new dirs); the four
  deprecated dirs were deleted and `xiom-core` renamed to `xiom-durable`.
  Wave 27's `gguf` circuit-breaker was resolved the same session by direct
  coordinator implementation (`docs/failed_attempts.md`, 10/10 shipped).
  Wave 20 added 10 (conversions `dhcp`, `ntp`, `socks`, `irc`, `mqtt`; new
  `ical`, `vcf`, `dns`, `modbus`, `can`). Wave 21 added 10 (conversion `ble`;
  new `gbnf`, `fits`, `stun`, `bencode`, `ply`, `dimacs`, `syslog`, `tga`,
  `cpio`). Wave 22 added 10 all-new dirs (`netstring`, `ar`, `vdf`, `cron`,
  `pgn`, `vtt`, `nbt`, `hl7`, `gpx`, `bibtex`). Wave 23 added 10 more all-new
  dirs (`cbor`, `bloom`, `wkt`, `ico`, `base32`, `quotedprintable`, `aiff`,
  `m3u`, `sgf`, `ntriples`). Wave 24 added 10 more all-new dirs (`iso8583`,
  `ulid`, `pcx`, `cue`, `pbm`, `gcode`, `lrc`, `ris`, `iban`, `fnv`), all
  balanced across the ecosystem categories. Wave 25 added 10 more all-new
  dirs (`plist`, `geohash`, `murmur3`, `tap`, `xbm`, `pam`, `srt`, `pls`,
  `ean`, `junit`). Wave 26 added 10 more all-new dirs (`smtlib`,
  `safetensors`, `dbase`, `systemd`, `gemtext`, `radix`, `luhn`, `fletcher`,
  `farbfeld`, `hostfile`), all balanced across the ecosystem categories.
  Wave 27 added 10 all-new dirs (`adler32`, `lcov`, `snbt`, `robots`, `edl`,
  `fstab`, `marc`, `fix`, `xpm`, `gguf`). Wave 28 added 10 more all-new dirs
  (`sarif`, `zonefile`, `gedcom`, `pem`, `maidenhead`, `rtf`, `ldif`, `spf`,
  `bech32`, `mbox`). Wave 29 added 10 more all-new dirs (`nii`, `hcl`, `dds`,
  `tzif`, `au`, `sbv`, `ktx`, `osrelease`, `duration`, `tcx`). Wave 30 added
  10 more all-new dirs (`elf`, `pe`, `dtb`, `pcapng`, `gpt`, `radiotap`,
  `woff`, `qoi`, `miniseed`, `ass`). Wave 31 added 10 more all-new dirs
 (`ext`, `acpi`, `usb`, `smbios`, `mbr`, `sparse`, `uboot`, `psf`, `pcf`,
 `resolv`). Wave 32 added 10 dirs (placeholder conversions `tftp`, `pop3`,
 `smtp`, `ftp`, `passwd`, `efi`, `hid`, `cab`, `pci`, plus new `rpm`).
 Wave 33 added 10 dirs (`png`, `gif`, `mp3`, `mp4`, `mkv`, `snmp`,
 `imap`, `amqp`, `thrift`, `avro`; 213 tests across the ten).
- `STATUS.json` totals: **257 stable, 4 ported, 63 incubating**;
  **261 green suites, 5,634 recorded tests**.
  - stable = the greenfield packages plus conversions. The wave 18-30 stable
    set is **published to production** by `eco-v0.1.1` (231 packages in the
    registry index); waves 31+32 (19 names) are tagged as `eco-v0.1.2` but
    blocked on the registry scope delta (section 5). New stable packages
    still carry `publish: false` until the next scope delta / tag.
  - ported = `xiom.sensor`, `xiom.control`, `xiom.json` (pure, promotable) and
    `xiom.kafka` (librdkafka FFI stubs remain; keep `ported`).
  - incubating = 63 legacy packages (includes `xiom.durable`, the renamed
    core, not yet ported).
- `.github/publish-allowlist.txt`: **309 names** = 257 stable ready + 52
  grandfathered legacy names (`.github/allowlist-baseline.txt`, warn-only in
  the guard). `scripts/allowlist-guard.ps1`: 0 failures (2026-09-26, after
  the wave-33 +10).
- Namespace audit **resolved**: `namespace-check` reports **324 packages,
  422 modules, 0 conflicts** (2026-09-26, wave-33 wrap).
- Toolchain: pin `COMPILER_VERSION` = **v0.61.3**; installed compiler
  v0.61.3 (`C:\Users\lefte\AppData\Local\xiom\bin`); repo release dir has
  v0.61.1; GitHub releases v0.61.1 + v0.61.3 exist. Stdlib
  `E:\xiom-lang\stdlib` (1627 module namespaces, still evolving).
- Signing: `XIOM_SIGNING_KEY` is SET; staging/production artifacts share the
  first-party key `4f3b47f3ae17b13c...`.
- Licensing: `LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE` and a pointer
  `LICENSE` are committed per LICENSING.md §2. SPDX pass repo-wide and the
  §1 `.md` header block remain .github-session scope.
- 562 commits landed since the previous handoff (`b2bdde1..`).

### Commit trail (recent milestones)

| Commit | What |
|---|---|
| this | SESSION.md refresh after waves 32+33 complete, `eco-v0.1.1` success, `eco-v0.1.2` scope block |
| 471c5e3 | allowlist wave 33 (+10) + index/report regeneration (completes the wave-32 deferral) |
| aa0eda0 / c72c85d / c563fe9 / 3366016 | wave-33 feat commits (png, mp4, snmp, thrift) |
| f48a76b / 24b0827 / aeea0b8 / 69c6d80 | wave-33 STATUS records (png, mp4, snmp, thrift) |
| cefa9eb | ops rate-limit note + eco-v0.1.2 attempt 2 scope re-test |
| 1392110 | ignore XIOM MCP tool local state (`.xiom_ai.json`, `.xiom_ai_cache/`) |
| b14fadf | `docs/failed_attempts.md` rpm abort/resolution entry |
| b7fc365 / d9f12a2 | `xiom.rpm` recovered on attempt 3 (19/19) + STATUS record |
| dccebd1 | allowlist wave 32 (+9 names) |
| e36ae67 / 24fc00b / 6edcde7 / 0b8d1a5 / e873c3e / fe5ad54 | wave-33 STATUS records (imap, avro, mp3, gif, mkv, amqp) |
| c7e4412 / 32841d7 / 3f31106 / c47c1b4 / 5ca6457 / 6617dce | wave-33 feat commits (imap, avro, mp3, gif, mkv, amqp) |
| 9ac83d3 | allowlist wave 31 + index/report regeneration |
| b0d97fd..2bb8c14 | wave 31 per-package `feat:`/`chore:` pairs (10 packages) |
| a0d7fc4 | `port.ps1` fails closed when a suite reports zero checks |
| a6e678e | staging canary ledger complete (130/130 success); `eco-v0.1.1` tagged |
| 4fb356f / c68013f / 8f7e58e | staging batch list + runner (serialized protocol) |
| da1a851 | allowlist wave 30 + index/report regeneration |
| 7cc082a | allowlist wave 29 + index/report regeneration |
| 456c3da..e88b8b1 | wave 29 per-package `feat:`/`chore:` pairs (10 packages) |
| 0637303 | allowlist wave 28 + index/report regeneration |
| 465d181..bd2ffd4 | wave 28 per-package `feat:`/`chore:` pairs (10 packages) |
| 674b728 / 631030c / 8bff9ab | `xiom.gguf` direct implementation, record, allowlist + breaker resolution |
| 36b25eb | allowlist wave 27 + index/report regeneration |
| 4b05f0f | `docs/failed_attempts.md` created (xiom.gguf triple-abort) |
| c3bb8d4 | allowlist wave 21 + index/report regeneration |
| 7e76af7 | allowlist wave 20 + index/report regeneration |
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
& .\scripts\status.ps1 -Action validate           # 305/0 expected
& .\scripts\allowlist-guard.ps1                   # 290 allowlisted, 0 failures
& .\scripts\namespace-check.ps1                   # 0 conflicts expected
& .\generate_index.ps1 ; & .\scripts\status.ps1 -Action report
```

Publish gate recap: only allowlisted + `STATUS.json` `stage: stable` with
`tests.status: pass` publishes (batches skip unready with a warning; explicit
tag/dispatch targets on unready names are refused). Default target is
**production** per the owner standing instruction in section 5; staging
dispatches happen only when the owner explicitly requests a staging run
(site/feature testing). The bounded staging badge canary
(`workflow_dispatch` + `allow_unready=true` + explicit `package` + staging
registry) remains available for that case; tags and batches can never use it.

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

## 5. Publishing / registry state (2026-09-26)

**OWNER STANDING INSTRUCTION (2026-09-26, supersedes the canary-first flow):**
publish directly to **production** by default. Staging is now only for
site/feature testing when the owner explicitly asks for it -- it is no
longer a package-code gate. Mechanism: after a wave wrap, cut one `eco-*`
tag for the ready batch (the tag batch publishes every `stable` + green +
allowlisted name at that commit; grandfathered names are skipped) and
approve the `registry-publish` gate via the pending_deployments API
(production approvals are handled by this session under this instruction).
Report `name -> run ID` (batch runs report the single run ID + the
batch commit). Never overlap a tag run with a dispatch batch (shared
concurrency group). Production tags so far: `eco-v0.1.0`, `eco-v0.1.1`
(SUCCESS), `eco-v0.1.2` (cut, blocked on the registry scope delta).

- **Staging**: rebuilt from main (`06f6977`, registry 2.0.0) with the
  xiom-packages/packages entry carrying the **full 290-name allowlist**
  (`staging-scopes.txt/.json` from the registry lane) and
  `PUBLISH_RATE_MAX=600`. All pre-batch canaries (78 scoped names + wave
  16/17 samples + the `xiom.algo` badge canary) remain verified.
- **Wave 18-30 staging batch: 130/130 SUCCESS (2026-09-26)**. Ledger with
  every `name -> run id -> state` is committed at `docs/staging-batch-runs.txt`
  (final commit `a6e678e`); the batch list is `docs/staging-batch.txt` (130
  names). Runner: `scripts/staging-batch.ps1` (staging-only guard, dry-run
  default, serialized pipeline).
  - **Concurrency finding (important)**: the workflow has a repo-level
    concurrency group (`registry-publish`, `cancel-in-progress: false`).
    GitHub cancels a previously *pending* run when a newer run joins the
    same group, so bulk-dispatching the whole batch at once cancelled 128
    of 130 runs (only the first and last survived). Batches must be
    dispatched through the serialized runner (at most one `pending` run),
    and the eco tag must never overlap a dispatch batch.
  - Approvals: staging runs are approved by this session via
    `POST /actions/runs/<id>/pending_deployments` with a JSON body
    `{"state":"approved","environment_ids":[<env id>],"comment":"..."}`
    (the GET returns only pending entries and has no `state` field;
    `-f` sends strings and fails -- use `--input <tempfile>`).
- **Production: `eco-v0.1.1` SUCCESS (2026-09-26)**. Tag `eco-v0.1.1` on
  `a6e678e` (waves 18-30); run `36240424222` completed on attempt 3 at
  15:02Z after two 30-min job-ceiling cancellations (the loop is idempotent
  and skips published versions). The registry index now carries **231
  packages**; every wave 18-30 name that passed the readiness filter is
  published (grandfathered names skipped).
- **Production `eco-v0.1.2`: CUT, FAILED on scopes (2026-09-26)**. Tag
  `eco-v0.1.2` on `dccebd1` (wave-32 wrap; waves 31+32 = 19 new names:
  `ext, acpi, usb, smbios, mbr, sparse, uboot, psf, pcf, resolv` plus
  `pop3, smtp, ftp, passwd, efi, hid, cab, pci, rpm`). Run `36251091427`:
  readiness guard success, gate approved, publish job **FAILED 15:25Z with
  `scope_denied`** -- `token "eco-release" is not scoped to publish
  "xiom.<name>"` (HTTP 403) for the delta names; the tail shows HTTP 401
  `oidc_token_expired` because the job's single minted token (~6 min) aged
  out during the 30-s retry storm. **Action: registry/ops must enumerate
  production scopes for the 19 names; then `gh run rerun 36251091427` +
  gate approval; it skips published versions.** Do not re-cut the tag.
- **Workflow finding (secondary)**: `publish-registry.yml` mints **one**
  OIDC token at job start (`XIOM_REGISTRY_TOKEN` via `$GITHUB_ENV`) and
  reuses it for every package; runs longer than ~6 min fail all remaining
  publishes with `oidc_token_expired`. Re-mint per attempt (or on 401) is a
  .github-session fix.
- **tftp version collision (owner decision)**: `xiom.tftp@0.1.0` published
  by `eco-v0.1.1` is the 2026-09-24 build (`be38152`); the wave-32 rewrite
  (`ae3c233`) carries the same version and cannot republish. Accept the
  published build or bump tftp to 0.1.1 in a later batch.
- **Historical scope deltas (waves 18-30)** are fully covered by the
  `eco-v0.1.1` tag; no names remain "awaiting scopes" from before wave 31.
  The wave-33 names (10) are allowlisted by the wave-33 wrap (`471c5e3`);
  they are the next scope request after the wave 31+32 delta lands (a
  future `eco-v0.1.3` would carry them).
- **Ops rate-limit notes (2026-09-26, relays via the owner)**: ops first
  reported the 15:02Z stall as the restored 20/min default and "re-raised"
  `PUBLISH_RATE_MAX=600`; the corrected root cause (16:54Z relay) is that
  `PUBLISH_RATE_MAX` was **never declared** in the production service
  block, so both the bump and the planned restore were inert and the
  service ran the default **20/min** all along. Deploy `394db71` declares
  all rate-limit knobs; production now genuinely runs `PUBLISH_RATE_MAX=600`
  (ops verified with `printenv`; registry `/health` shows the restart at
  16:54:38Z, v2.1.0). Ops restores **20** on "batch done" (registry §21
  D5). Rate-limit config does **not** affect the `scope_denied` 403:
  attempt 3 ran against the new config and still failed on scopes, with no
  429s. Batch is **not** done; do not send the "batch done" confirmation
  until `eco-v0.1.2` publishes.
- **Environment**: `registry-publish` requires reviewer `Lefteris-Notas`
  (owner); per the 2026-09-26 standing instruction this session approves
  both staging canary deployments and production batch gates via the API
  (the `eco-v0.1.1` attempt-3 and `eco-v0.1.2` gates were approved this way).
- **Production**: `eco-v0.1.0` (owner-account), `xiom-flags/v0.1.0`
  (per-package tag) and `eco-v0.1.1` (waves 18-30, attempt 3, 15:02Z) have
  succeeded; `eco-v0.1.2` (waves 31+32) is cut but blocked on the registry
  scope delta (see above). Nothing in this repo publishes to production
  without the `eco-*` tag or an explicit workflow dispatch.
- Ops note: OIDC canaries are unrelated to browser sign-in; the **OAuth
  callback URL check remains a separate outstanding owner item** (do not fold
  it into publish relays).

---

## 6. Roadmap status

1. **Phase 0 -- toolchain + harness + triage: DONE.** Scripts above, STATUS
   seeded for every implemented package, pin v0.61.3, licenses, badge/guard
   pipeline, bounded badge canary.
2. **Phase 1 -- small greenfield packages: DONE and expanded.** 253+
   packages built, conformance-tested, `stable`, allowlisted (waves 1-32;
   wave 33 in flight). All pass the namespace rule; each has
   SPEC/README/tests and a STATUS record. Waves 18-30 are published by
   `eco-v0.1.1`; waves 31+32 (`eco-v0.1.2`) are tagged and blocked only on
   the registry scope delta.
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
   parameter yields an empty vector on the installed compiler; bind to a local
   first. The compiler session reports this fixed in the **next** build; it is
   NOT yet installed (re-verified 2026-09-25, wave 26: probe B still returns
   `result payload: 0`, exit 10, on `0.61.3` / pin `v0.61.3`). Keep the local
   binding until the pin bump, then re-run `docs/repro/struct-field-vec/`.
5. Indexed `Vec[fn]` calls miscompile (access violation): no table-driven
   test dispatch; call tests directly or via `run_test_at(index)`.
6. Do not construct `Ok`/`Err` inside struct-returning functions; use leaf
   helper constructors. Scalar payloads (`Result[Int, Str]`, `Result[Str, Str]`)
   accept direct `Ok`/`Err`; struct payloads (`Result[Doc, Str]`) need the
   leaf helpers (wave 25 `xiom.plist`).
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
12. `&mut Vec` parameters need an explicit `&mut` at every call site: passing
    the value silently copies and the mutation is lost (wave 21 `xiom.tga`;
    same family as trap 4).
13. Widened `UInt8` constants >= 128 must be masked too: `239u8 as Int`
    sign-extends to -17; write `(C as Int) & 0xFF` for constants (wave 21
    `xiom.syslog` BOM handling).
14. The compiler is lax about arity and punctuation: a call with fewer args
    than declared compiles (missing args default to 0) and mixed brackets
    (`-> Vec<UInt8]`) compile too -- including in **parameter and local**
    type positions, not just returns (wave 22 `xiom.ar`; wave 26
    `xiom.fletcher` found 6; wave 30 found 17 more across `gpt` 13, `qoi` 2,
    `radiotap` 1, `pcapng` 1). Verify argument counts and types explicitly;
    grep signatures for `Vec<`/`Result<` **after every write and again after
    green**; do not rely on the compiler to reject them.
15. Never build a `Str` via `xiom.string.builder.sb_to_str` from bytes that
    may contain `0x00`: its length contract aborts at run time (wave 23
    `xiom.aiff` validates chunk ids/types/names as printable ASCII before
    building any `Str`). Trap 4 extends to `Result` payload fields: bind
    `result.value` to a local before passing it to a `&Vec[UInt8]` parameter
    (wave 23 `xiom.quotedprintable`, `xiom.aiff`). Also, `\0` inside a `Str`
    **literal** truncates it (`"abc\0def"` measures 3, and a literal NUL byte
    cannot be represented at all) -- wave 27 `xiom.robots`; a NUL anywhere in
    a literal truncates from that point (`"\x00\x01"` measures 0, wave 28
    `xiom.ldif`). Test other control bytes with
    `\u{0001}`/`\u{000B}`/`\u{001F}`/`\u{007F}` escapes.
16. Never let parallel Vecs drift: every push on one array must be mirrored
    on all sibling arrays, and emit/accessors must guard mismatched lengths.
    `xiom.lrc` (wave 24) crashed with an access violation when one
    timestamped line pushed `times` without a matching `texts` entry; the AV
    was nondeterministic and stdout buffering hid all prior output, so pin
    the invariants in tests and treat exit codes as the signal.
17. `as` is a reserved keyword (`let as: Int` is `error[P001]`), and
    `xiom.convert` re-exports `int_to_string` but not `int_to_base` (that
    lives in `xiom.convert.int`) -- wave 24 `xiom.gcode`.
18. `Int` division truncates toward zero (LLVM sdiv), so the common
    ceil-division idiom `(a + b - 1) / b` is WRONG for negative numerators
    (`-28 / 3` is `-8`, ceil is `-9`). Use
    `let q = a / b; let r = a % b; if r > 0 { q + 1 } else { q }` (wave 28
    `xiom.maidenhead`; the naive form would have produced off-by-one cell
    minima across the western/southern hemisphere).

---

## 8. Open decisions (owner) / outstanding items

1. **Registry/ops scope delta needed (blocker)**: production publish scopes
   for the 19 wave 31+32 names (`ext, acpi, usb, smbios, mbr, sparse,
   uboot, psf, pcf, resolv`, `pop3, smtp, ftp, passwd, efi, hid, cab, pci,
   rpm`). Evidence: run `36251091427`, HTTP 403 `scope_denied` (section 5).
   After the scopes land, `gh run rerun 36251091427` + gate approval.
2. **`eco-v0.1.1`: DONE** (run `36240424222`, attempt 3, 15:02Z). Standing
   instruction from the owner: production-direct publishing from now on
   (section 5); waves 31+32 ride `eco-v0.1.2` (cut; blocked on item 1);
   wave 33 rides the next tag after its wrap.
3. **Repo protection closure**: the required-reviewer environment is live;
   confirm this satisfies the §8.3 decision.
4. **OAuth callback URL check** (owner): both GitHub OAuth app callback URLs,
   outstanding from the earlier relay; kept separate from publish relays.
5. **tftp version decision (owner)**: accept the published 2026-09-24
   `xiom.tftp@0.1.0` or bump the wave-32 rewrite to 0.1.1 in a later batch
   (section 5).
6. **Wave 34+ queue**: 197 placeholders remain; strong small candidates are
   more format/protocol codecs and hardware/file formats. Owner relayed the
   ecosystem page's canonical categories (Data and storage; Networking and
   web; AI and machine learning; Scientific computing; Graphics and games;
   Systems and tooling; Interoperability and bridges; Verification and
   analysis) -- use them to balance wave selection. Manifest `categories:`
   tokens still mix `network` vs `networking` etc.; harmonizing them is an
   owner decision.
7. **Repo-wide SPDX/`.md` header pass** and the 71 legacy manifests still
   using `authors: ["XIOM Team"]` -- .github-session scope. The publish
   workflow OIDC token-lifetime finding (section 5) is also theirs.
8. **`xiom.durable` port** (Phase 2 opener) and the pure legacy frontier.
9. Note: the local Kilo build rejects new `.kilo/agent`/command frontmatter
   (`No context found for instance`); persistent agent definitions were
   removed to keep config clean. Use `task` subagents / Agent Manager local
   sessions instead.
10. **`xiom.gguf` and `xiom.rpm` circuit breakers -- RESOLVED** (wave 27/28
    and wave 32 respectively): both recovered after silent subagent aborts
    (`docs/failed_attempts.md`). Post-breaker fallback: coordinator
    implements directly; delegate aborts are environmental.

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

- **Registry/ops session:** **scope delta needed now** -- production publish
  scopes for the 19 wave 31+32 names (section 5 evidence: run `36251091427`,
  `scope_denied`), plus optionally re-mint the publish OIDC token per
  attempt (workflow finding). Publisher identity is
  `xiom-packages/packages`, workflow `publish-registry.yml`,
  `refs/heads/main`, event `workflow_dispatch` (staging canaries) or tag
  pushes (production). Staging canaries remain available on request;
  production runs directly per the owner standing instruction.
- **Compiler session:** accepted the three fn-value/ABI repros
  (`docs/repro/generic-fnptr/`) into their unification sprint; findings to
  relay: `&struct.field` -> `&Vec[UInt8]` empty-vector misbehavior, `str_len`
  on `Vec[Str]` elements, the `Vec[fn]` dispatch miscompile, bitwise AND on
  bit-31 operands (wave 20 `xiom.can` used descending subtraction instead),
  the ABI NUL-termination of `Str` that makes DNS wire labels containing
  `0x00` unrepresentable (wave 20 `xiom.dns` rejects them); and wave 21's
  `&mut Vec` auto-copy at call sites (`xiom.tga`) plus `UInt8` constant
  sign-extension (`239u8 as Int` = -17, `xiom.syslog`). Wave 22 added: arity
  laxness (fewer args than declared compiles, missing args default 0) and a
  `-> Vec<UInt8]` bracket typo compiling (`xiom.ar`); `io.println` accepts
  only `Str` -- ints need `xiom.convert.int_to_string` (`xiom.pgn`); an
  immutable accessor before a `&mut` call on the same struct raises an E001
  advisory (`xiom.netstring`); `&struct.field` only misbehaves for `&Vec`
  parameters (plain `&Struct` params are fine, `xiom.pgn`). `xiom.ar` bytes
  were interop-checked with `llvm-ar`. Wave 23 added: `sb_to_str` aborting at
  run time on `0x00` in the built range (`xiom.aiff`); trap 4 extending to
  `Result.value` fields (`xiom.quotedprintable`, `xiom.aiff`); the masked
  widening trap biting raw UTF-8 (`(b as Int) & 0xFF` needed even for
  `< 0x20` checks, `xiom.ntriples`); E001 advisories at `&mut` call sites
  remain benign (pinned by `xiom.ntriples` t22). Wave 24 relay #2 result:
  arity laxness CONFIRMED (no exact-count validation on the primary path;
  extras dropped; silent-wrong-code; fix recorded), `Vec<UInt8]` mixed
  brackets CONFIRMED (parser accepts any opener/closer pairing; fix recorded:
  remember the opener and require its closer),
  `io.println` Str-only confirmed by design, E001 shape NOT reproduced --
  instead a by-value method receiver leaves the Vec field unchanged (same
  Vec-handle copy class), and `&struct.field` -> `&Vec` NOT reproduced in the
  simple shape. Our answer: `docs/repro/struct-field-vec/` (commit `6310dba`)
  shows the simple struct field is GREEN, `Result[Vec[UInt8], Str]` payload
  `&r.value` is the broken minimal repro (reads empty; bound local reads 3),
  and a struct field one hop deeper (`&r.value.data`) is GREEN. Compiler
  fixes are scheduled for the next release. Wave 25 relay #3 (strict-parser
  prep): a precise scan of this repo for mixed-bracket type syntax found
  **0 sites** (`Vec<X]` / `Vec[X>` patterns; the 18 sites across 7 files are
  stdlib-owned, incl. the `io/fs.xi` block); `xiom.cell` is not in this repo;
  the only receiver-style declaration here, `SqliteValue.is_null(val:)`, is
  called statically with exact arity (`xiom-sqlite`, so not the offset bug).
  Wave 26 relay #4/#5: compiler confirmed **packages #3 = 0 mixed-bracket
  sites, ready for the strict flip**; trap 6 refinement recorded; trap 4
  closure claimed for the next build but **still reproduces on the installed
  0.61.3** (see trap 4 / `docs/repro/struct-field-vec/`). New porting note
  from the wave-26 board: mixed brackets silently compile in parameter and
  local type positions too (`xiom.fletcher` fixed 6 in its own tests); the
  whole repo re-scanned clean afterwards. Wave 27: the trap-14
  parameter-position finding was independently confirmed by `xiom.snbt`
  (3 private emit-helper params) and `xiom.fletcher` (6 sites); `xiom.robots`
  added the `\0`-literal truncation finding (now in trap 15); indexed writes
  to `Vec[Int]` struct fields (`v[i] = v[i] + 1`) work (`xiom.lcov`).
  `xiom.gguf` triple-abort is logged in `docs/failed_attempts.md` (resolved
  by direct implementation). Wave 28: the ceil-division trap is now trap 18
  (`xiom.maidenhead`); RTF semantics: the space after a control word is a
  consumed delimiter and `\uNNNN` is DECIMAL (`\u66` = `B`); `xiom.spf`
  confirmed nested `&mut`/`&` forwarding and `break` work; `xiom.bech32`
  sharpened decode errors (`wrong variant` vs `bad checksum`; BIP-350
  ambiguity cannot occur). Wave 29: `xiom.hcl` confirmed mutual recursion,
  `while true` + `break` and discarded `Vec.pop()` under v0.61.3;
  `xiom.ktx` self-caught an identifier-table off-by-one; `xiom.nii` supports
  both sizeof_hdr endiannesses; `xiom.tcx` disambiguates same-named elements
  by the open-element stack. Two more delegate silent aborts (`tcx` #1,
  `hcl` #1) recovered by one retry each. Wave 30: trap 14's parameter/local
  bracket laxness is now the most-hit trap -- `xiom.gpt` alone found and
  fixed 13 sites after a green run (`qoi` 2, `radiotap` 1, `pcapng` 1);
  GREP `Vec<`/`Result<` AFTER EVERY WRITE, not just once. Bit tests on
  values with the sign bit set are unreliable -- `xiom.radiotap` used
  divisor/modulo arithmetic end-to-end (same family as `xiom.can`'s
  bit-31 note). UEFI/CRC: a stored CRC field must be treated as zero while
  computing its own CRC (`xiom.gpt`). `xiom.pcapng` needed an explicit
  LE/BE branch for 64-bit composition; `xiom.miniseed` corrected the
  brief's non-existent sample-count field (derived accessor), tenths range
  0..9999, and BE-only stance; `xiom.ass` hit the benign E001
  borrow-in-struct advisory when a Vec is both borrowed and moved. Two
  more delegate silent aborts (`pcapng` #1 recovered by one retry).
  Wave 31 added: trap 14 keeps recurring in **parameter** positions
  (`xiom.usb` found 8 after a green run, `xiom.mbr` 1) -- the post-green
  grep is mandatory. `str_len`/`byte_at` DO work on a typed local bound
  from a `Vec[Str]` element (`xiom.usb` probe; the dtb caution was
  over-broad), while `==` still must be avoided. USB strings:
  `bLength = 4 + 2*text_units` (the string index counts as one UTF-16
  unit). `xiom.gpt`: a stored CRC field must be zero while computing its
  own CRC. `xiom.miniseed`: no sample-count field in the fixed header,
  tenths range 0..9999, BE-only. Working patterns (not bugs):
  module-scope `pub const` resolves unqualified in importers; nested plain
  structs and `Vec[Vec[UInt8]]` struct fields compile and mutate; `--run`
  leaves a gitignored `a.exe` in the package dir.
  Wave 32: `xiom.rpm` recovered on the third attempt with the skeleton-first
  brief (19/19); the real RPM header prefix is 4-byte magic/version + 4
  reserved bytes, then count/store-size (not "magic + 8 reserved").
  Wave 33: the file-write tooling introduced mixed brackets again -- `gif`
  fixed 16, `mp3` several -- both verified clean by the post-green grep
  (trap 14 remains the top trap). `xiom.amqp` found a **loop-carried
  miscompile** on v0.61.3: a stack decoder reusing `ends.push(pos + 4 +
  sub_len)` returned the first container's end offset in the second
  iteration (any two containers in one parent failed with `bad table`/`bad
  array`, found by byte bisection); the workaround decodes nested containers
  with a recursive per-container function (comment at `src/amqp.xi:1266`).
  `xiom.mkv` treats an unknown-size Cluster end as a documented boundary
  heuristic and decodes EBML floats as fixed-point integer milli-units;
  `xiom.avro` accepts non-minimal varints <=10 bytes (spec does not require
  shortest form) and exposes float/double as raw LE octets (`Vec[Float64]`
  banned, no Int<->Float64 bitcast).
- **Harness/tooling (this session):** `scripts/port.ps1` now **fails closed**
  when a suite prints zero `[PASS]` markers (a quiet run had accepted an
  interrupted suite as green; see `a0d7fc4`). PowerShell scripting pitfalls
  hit while running the publish lane: variable-colon parsing
  (`"$RunId:"` needs `${RunId}:`), `[int]` overflow on GitHub run IDs
  (use `[long]`), and `--input -` stdin pipes for JSON bodies are
  unreliable from background PowerShell (use a temp file).
- **.github session:** licensing pass done here (LICENSE-MIT/APACHE/NOTICE,
  canonical holder); SPDX/`.md` header pass and rulesets remain theirs.
  New: `publish-registry.yml` should re-mint the OIDC token per publish
  attempt (or on 401) -- the single job-start token expires in ~6 min and
  fails long runs (section 5, run `36251091427`).
- **Owner:** relays, scope deltas, production greenlight, OAuth callback
  check, Phase 2 direction; new decisions queued: tftp 0.1.0 collision and
  the registry scope delta for waves 31+32.
