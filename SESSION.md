# xiom-packages/packages -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-09-26, by the packages session (continuation of the
2026-09-23 handoff; refreshed after wave 31, including the first staging
canary batch and the `eco-v0.1.1` production release). Check
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
- Folder inventory (2026-09-26, after wave 31): **305 implemented dirs (with
  `package.xi`) + 210 README-only placeholders + the umbrella
  `packages/package.xi`**. Since the 2026-09-23 handoff: 238 new packages were
  implemented (85 by converting placeholders, 153 brand-new dirs); the four
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
 `resolv`).
- `STATUS.json` totals: **238 stable, 4 ported, 63 incubating**;
  **242 green suites, 5,236 recorded tests**.
  - stable = the 238 greenfield packages. The wave 18-30 stable set is
    published to **staging** (130/130 in the 2026-09-26 batch) and included
    in the **eco-v0.1.1** production batch; new stable packages still carry
    `publish: false` until the next scope delta / tag.
  - ported = `xiom.sensor`, `xiom.control`, `xiom.json` (pure, promotable) and
    `xiom.kafka` (librdkafka FFI stubs remain; keep `ported`).
  - incubating = 63 legacy packages (includes `xiom.durable`, the renamed
    core, not yet ported).
- `.github/publish-allowlist.txt`: **290 names** = 238 stable ready + 52
  grandfathered legacy names (`.github/allowlist-baseline.txt`, warn-only in
  the guard). `scripts/allowlist-guard.ps1`: 0 failures.
- Namespace audit **resolved**: `namespace-check` reports
  **305 packages, 403 modules, 0 conflicts** (2026-09-26, after wave 31).
- Toolchain: pin `COMPILER_VERSION` = **v0.61.3**; installed compiler
  v0.61.3 (`C:\Users\lefte\AppData\Local\xiom\bin`); repo release dir has
  v0.61.1; GitHub releases v0.61.1 + v0.61.3 exist. Stdlib
  `E:\xiom-lang\stdlib` (1627 module namespaces, still evolving).
- Signing: `XIOM_SIGNING_KEY` is SET; staging/production artifacts share the
  first-party key `4f3b47f3ae17b13c...`.
- Licensing: `LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE` and a pointer
  `LICENSE` are committed per LICENSING.md §2. SPDX pass repo-wide and the
  §1 `.md` header block remain .github-session scope.
- 542 commits landed since the previous handoff (`b2bdde1..`).

### Commit trail (recent milestones)

| Commit | What |
|---|---|
| this | SESSION.md refresh after wave 31 + first staging batch + eco-v0.1.1 |
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

## 5. Publishing / registry state (2026-09-26)

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
- **Production: `eco-v0.1.1` cut (2026-09-26)** on `a6e678e` (annotated:
  waves 18-30, 130 packages staging-verified). Tag run `36240424222`:
  readiness guard success, publish job waiting for the **owner's single
  approval**; it publishes the full ready batch at the tag commit (228
  stable names; grandfathered names are skipped by the readiness filter).
  No production tags before this one besides `eco-v0.1.0`.
- **Wave 31 delta pending** (relay to the registry/ops for the next scope
  update and a possible `eco-v0.1.2`): `ext, acpi, usb, smbios, mbr,
  sparse, uboot, psf, pcf, resolv` (10 names; green, allowlisted).
- Historical scope deltas (waves 18-30) are fully covered by the 290-name
  staging entry; no names remain "awaiting scopes" from before wave 31.
  - wave 20 (10 names): `can, dhcp, dns, ical, irc, modbus, mqtt, ntp, socks,
    vcf` -> the delta after wave 19 (dispatched/green 2026-09-25; not yet
    scoped, so no canary can be dispatched).
  - wave 21 (10 names): `bencode, ble, cpio, dimacs, fits, gbnf, ply, stun,
    syslog, tga` -> the delta after wave 20 (green 2026-09-25; not yet scoped).
  - wave 22 (10 names): `ar, bibtex, cron, gpx, hl7, nbt, netstring, pgn,
    vdf, vtt` -> the delta after wave 21 (green 2026-09-25; not yet scoped).
  - wave 23 (10 names): `aiff, base32, bloom, cbor, ico, m3u, ntriples,
    quotedprintable, sgf, wkt` -> the delta after wave 22 (green
    2026-09-25; not yet scoped).
  - wave 24 (10 names): `fnv, gcode, iban, iso8583, lrc, pbm, pcx, ris, cue,
    ulid` -> the delta after wave 23 (green 2026-09-25; not yet scoped).
  - wave 25 (10 names): `ean, geohash, junit, murmur3, pam, plist, pls, srt,
    tap, xbm` -> the delta after wave 24 (green 2026-09-25; not yet scoped).
  - wave 26 (10 names): `smtlib, safetensors, dbase, systemd, gemtext, radix,
    luhn, fletcher, farbfeld, hostfile` -> the delta after wave 25 (green
    2026-09-25; not yet scoped).
  - wave 27 (10 names): `adler32, lcov, snbt, robots, edl, fstab, marc, fix,
    xpm, gguf` -> the delta after wave 26 (green 2026-09-25; not yet scoped).
  - wave 28 (10 names): `sarif, zonefile, gedcom, pem, maidenhead, rtf, ldif,
    spf, bech32, mbox` -> the delta after wave 27 (green 2026-09-25; not yet
    scoped).
  - wave 29 (10 names): `nii, hcl, dds, tzif, au, sbv, ktx, osrelease,
    duration, tcx` -> the delta after wave 28 (green 2026-09-25; not yet
    scoped).
  - wave 30 (10 names): `elf, pe, dtb, pcapng, gpt, radiotap, woff, qoi,
    miniseed, ass` -> the delta after wave 29 (green 2026-09-25; not yet
    scoped).
  - 129 names total pending enumeration before their canaries can run.
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
2. **Phase 1 -- small greenfield packages: DONE and expanded.** 238 packages
   built, conformance-tested, `stable`, allowlisted (waves 1-31). All pass
   the namespace rule; each has SPEC/README/tests and a STATUS record.
   Waves 18-30 are staging-verified and in the `eco-v0.1.1` production
   batch; wave 31 rides the next tag/delta.
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

1. **Wave 31 scope delta** (next allowlist/scopes update) for
   `ext, acpi, usb, smbios, mbr, sparse, uboot, psf, pcf, resolv`; a
   possible `eco-v0.1.2` (or per-name production dispatch) after the
   `eco-v0.1.1` batch completes. Waves 18-30 are fully covered by the
   290-name staging entry and the `eco-v0.1.1` tag.
2. **`eco-v0.1.1` production approval**: tag cut, run `36240424222` waiting
   at the `registry-publish` gate for the owner's single approval (this
   doubles as the remaining production greenlight for waves 18-30).
3. **Repo protection closure**: the required-reviewer environment is live;
   confirm this satisfies the §8.3 decision.
4. **OAuth callback URL check** (owner): both GitHub OAuth app callback URLs,
   outstanding from the earlier relay; kept separate from publish relays.
5. **Wave 32+ queue**: 210 placeholders remain; strong small candidates are
   more format/protocol codecs (`passwd`, `uboot`-siblings, `fstab`-siblings,
   `pci`, `hid`, `cab`, and other names that pass namespace-check).
   Owner relayed the ecosystem page's
   canonical categories (Data and storage; Networking and web; AI and machine
   learning; Scientific computing; Graphics and games; Systems and tooling;
   Interoperability and bridges; Verification and analysis) -- use them to
   balance wave selection. Manifest `categories:` tokens still mix `network`
   vs `networking` etc.; harmonizing them is an owner decision.
6. **Repo-wide SPDX/`.md` header pass** and the 71 legacy manifests still
   using `authors: ["XIOM Team"]` -- .github-session scope.
7. **`xiom.durable` port** (Phase 2 opener) and the pure legacy frontier.
8. Note: the local Kilo build rejects new `.kilo/agent`/command frontmatter
   (`No context found for instance`); persistent agent definitions were
   removed to keep config clean. Use `task` subagents / Agent Manager local
   sessions instead.
9. **`xiom.gguf` circuit breaker -- RESOLVED** (wave 27/28): three porter
   workers produced zero files and empty results
   (`ses_f258975e8ffeUokkSYbqp76R4X`, `ses_f25757fecffeR0eOx7NFjXFxrT`,
   `ses_f2571292affeCvAExPY0TBHjNA`); owner chose direct implementation and
   the coordinator shipped `xiom.gguf` 24/24 (`674b728`/`631030c`/`8bff9ab`,
   resolution recorded in `docs/failed_attempts.md`). Post-breaker fallback:
   coordinator implements directly; delegate aborts are environmental.

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
- **Harness/tooling (this session):** `scripts/port.ps1` now **fails closed**
  when a suite prints zero `[PASS]` markers (a quiet run had accepted an
  interrupted suite as green; see `a0d7fc4`). PowerShell scripting pitfalls
  hit while running the publish lane: variable-colon parsing
  (`"$RunId:"` needs `${RunId}:`), `[int]` overflow on GitHub run IDs
  (use `[long]`), and `--input -` stdin pipes for JSON bodies are
  unreliable from background PowerShell (use a temp file).
- **.github session:** licensing pass done here (LICENSE-MIT/APACHE/NOTICE,
  canonical holder); SPDX/`.md` header pass and rulesets remain theirs.
- **Owner:** relays, scope deltas, production greenlight, OAuth callback
  check, Phase 2 direction.
