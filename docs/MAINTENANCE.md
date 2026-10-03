# Ecosystem maintenance loop (release-triggered)

Owner request 2026-09-28: on every XIOM compiler release and every stdlib
release, bring the packages that are actually affected up to date, so the
growth system keeps working hand to hand with the toolchain lanes. This is
deliberately **not** a repo-wide lockstep: every package versions
independently, and a package only moves when it is touched, affected, or
stale.

## Triggers

1. **Compiler release** (`COMPILER_VERSION` bump in this repo):
   - Refresh `STATUS.json` records to the new pin -- the 2026-09-28
     v0.62.0 shape (`2183ac4`): compiler field for every record; run
     provenance (`run_by`/`commit`/`checked`) only for records with a
     recorded run (the schema forbids run fields under
     `tests.status: unknown`).
   - Re-run the fleet sweep over every implemented package (batched chunk
     jobs; raw logs under `%TEMP%\kilo\sweep\`), re-record green runs,
     fix whatever the sweep breaks (not production), keep stages;
     `validate` + `allowlist-guard` until green.
   - `scripts/status.ps1 -Action repin` is a helper only (aligns the
     compiler field, keeps stale provenance); it is not a substitute for
     the re-run sweep.
2. **Stdlib release**:
   - Re-run packages that import changed modules and every package with an
     open row in `docs/STDLIB-WISHLIST.md`.
   - When a release closes a gap, switch the local workaround to the
     stdlib API at that package's next touch (never a drive-by refactor of
     a green package) and update the wishlist row.
3. **Registry / ops change** (scope delta, publisher, rate policy):
   append the allowlist delta, wrap (`generate_index.ps1` +
   `status.ps1 -Action report` + `export-namespaces.ps1`), tag one
   `eco-*` batch, ping ops for the batch rate window, have ops re-verify
   that allowlist and stacks sets match exactly. After every publish
   batch, sync the published names' README `Status` blocks (stage +
   published version) -- README text is a build-time snapshot and lags
   the records/registry otherwise. **Verify with a README-vs-manifest
   version pair scan after each batch** (baseline 2026-10-02: 445/445
   pairs match after the wave-53 sync; the missed sync caused that
   442-README cleanup). **Registry ruling (2026-09-29): no
   version-less metadata refresh; stale registry pages are fixed by
   chunked patch-bump republishes (~50/batch, staging first, ops
   supports the rate window).**
4. **Dependency-driven**: when a package publishes a new minor/major,
   schedule a check for its dependents (`deps:` in `package.xi`).
5. **Opportunistic**: any package touched for a fix rides the next batch
   (patch bump, re-run, re-record).
6. **Promotion to stable** (owner-approved 2026-10-02): apply the gate in
   `docs/PROMOTION.md` -- contracts mandatory; runs after Tier-2
   maintenance and README sync, before growth.

## Compiler-release triage (2026-10-02, owner-approved)

Not every release deserves the same response. Classify each compiler
release before scheduling work; reserve the expensive path for releases
that can change existing package behavior.

| Tier | Release kind | Response |
|---|---|---|
| 0 | Non-semantic (docs, tooling, parser) or fixes to constructs no package exercises | Pin bump + `validate` + `allowlist-guard` + re-run the relevant repro probes. No sweep, no wave. |
| 1 | Semantic fix that does NOT unlock a workaround or change codegen for used patterns | Grep the workaround registry below, re-run only the affected packages + the fixed bug's probe. No fleet sweep. |
| 2 | Semantic fix that unlocks workaround retirement (or plausibly changes existing generated code) | Full fleet sweep as the detector, then a **maintenance wave** (10 lanes) whose items are workaround retirements; evidence-gated; publish as one patch-bump `eco-*` batch (no allowlist delta). |

Rules:

- **Compiler lane provides the triage input:** each release names the
  affected constructs and ships/points at a minimal repro probe.
- **Evidence-gated retirement:** a workaround class is retired only when
  its probe flips RED -> GREEN on the new pin AND each package re-runs
  green (port x2 + trap-14). Never retire by assumption.
- **Scope by pattern, detect by sweep:** the registry selects the wave
  items; the sweep catches affected packages outside the pattern list.
- **One package = one commit + record.** Workaround removal with
  identical behavior is `refactor:`/`chore:`; patch-bump only when
  published code changes (no lockstep versions).
- **Sweep hygiene:** kill by PID/process tree only -- never a blanket
  `Get-Process a | Stop-Process`; clean shadow stdlib worktrees and
  stale `%TEMP%\kilo\stdlib-rel` copies before sweeping; serialize or
  isolate chunk temp outputs.
- **Program order:** Tier-2 maintenance > README `Status` sync >
  promotion waves (`docs/PROMOTION.md`) > growth.

## Category vocabulary (registry, 2026-10-02)

The registry accepts exactly these 16 category tokens (from
`registry.xiom-lang.org/index.json`):

`ai-ml`, `cloud-infra`, `concurrency`, `core`, `crypto-security`,
`data`, `database`, `graphics`, `media`, `network`, `science`,
`systems`, `testing`, `text-nlp`, `tooling`, `web`.

Unknown tokens are dropped silently -- the package page then shows
`categories: []`. Manifests MUST use only accepted tokens. Legacy-token
mapping used in the wave-53.5 fix:

- `text` / `l10n` / `i18n` -> `text-nlp`
- `protocol` -> `network` (comms protocols) or `systems` (embedded
  bus/device protocols)
- `networking` -> `network`
- `security` -> `crypto-security`
- `concurrent` -> `concurrency`
- `compiler` -> `tooling`
- `finance` -> `data`
- `interoperability` -> `text-nlp` (documents) / `data`
- `safety` -> `crypto-security` / `tooling` / `core` by domain

Wave-56 sweep (2026-10-03): all 90 manifests that mixed unknown tokens with
accepted ones were normalized repo-side (metadata-only -- no version bumps,
no republish; the registry already ignored the unknown tokens). Additional
domain resolutions: `engineering` -> `systems` (embedded/hardware: adc, dac,
electronics, robotics) or `science` (materials, thermo; deduped into the
existing token); `safety` -> `crypto-security` (audit, html, jwt, password,
rbac, sanitize, secret) or `tooling` (compliance, validation); `protocol` ->
`network`. Unknown tokens that mapped onto an already-present token were
deduped. Zero unknown category tokens remain across the 514 manifests.

Registry note: the web UI renders the README **of each published
version**; owner chose policy **1b (opportunistic refresh, 2026-10-02)**
-- stale README text inside already-published artifacts refreshes at
each package's next republish, with no dedicated republish program.

## Workaround registry (retirement candidates)

Each row maps a carried workaround to its probe, the packages that use
it, and whether the fix has landed on the pin.

| Workaround class | Probe | Affected packages | Status on v0.62.2 |
|---|---|---|---|
| `byte_at` widen+mask `(x as Int) & 0xFF` | `docs/repro/byte-at-128` | every binary/codec package | **RETIRED on v0.62.2** -- battery `bad=0` (re-run 2026-10-03); direct compares are safe in new code; existing widen+mask sites simplify at next touch (no drive-by refactors) |
| No global `Vec[Str].push` / avoid `Vec[Str]` | `docs/repro/v0622-regressions/vec_str_push_global.xi` (+ param shape) | `consensus`, all blob+offset packages | OPEN (compiler queue) |
| No `&mut Int` scalar params (state via returns) | `docs/repro/mut-int-write-through` + `docs/repro/v0622-regressions/mut_int_write_drop_matrix.xi` | numerical/stateful packages (wave-46 set, `upnp`) | OPEN for BARE assignment (`s = 99`) in both call forms; DEREF writes (`*s = ...`) work on v0.62.2 (matrix probe `bad=2`; `gbnf` 30/30 in production with deref writes); `&mut Struct` field writes work. Tier-2 can narrow the ban accordingly |
| Mixed/full-angle bracket grep after every write | byte-level grep shapes: `Vec<`, `Result<`, `Option<`, `&Vec<`, `<]`, `>]` (parameter/local/FIELD positions; never audit from Read output -- it renders `Vec<Int>` as `Vec[Int]`) | all packages (authoring hazard) | OPEN (compiler still accepts malformed shapes silently; keep the two-pass grep); repo re-audited 2026-10-03 -- 1712 `.xi` files, 0 real sites (31 raw hits = comments/XML strings) |
| Bare imported type names (no qualified type references) | COMPILER-FINDINGS nominal-identity row (`saml`/`k8s` params, `gcp` struct literals) | multi-module packages | OPEN (qualified function calls resolve; qualified types fail) |
| No cross-type bindings (Str field -> `Vec[UInt8]` local) | `xiom.pptx` probe (COMPILER-FINDINGS row) | `pptx`, potentially all | OPEN |
| `Str` equality / `str_len` on `Vec[Str]` elements (pointer-compare trap) | `docs/repro/str-vec-eq/probe_str_vec_eq.xi` | `upnp` (historical t18 slips); `training` tests keep `str_compare` discipline | NOT REPRODUCED on v0.62.2 (2026-10-03: `elem==elem`, `elem==literal`, runtime-derived `==literal` and `str_len` all correct, `bad=0`); keep existing `str_compare` sites; full retirement candidate for Tier-2 after the release sweep |
| `&r.value` on `Result[Vec[UInt8], Str]` payloads (empty-vector trap; local-binding workaround) | `docs/repro/struct-field-vec` | wave-26 packages that bind the payload into a local | **RETIRED on v0.62.2** (2026-10-03 re-run: `result payload: 3`, all 3 probes exit 0); existing local-binding sites may simplify at next touch |
| Concrete callbacks instead of generic fn-values (v0.61.3 ABI family) | `docs/repro/generic-fnptr` (7 probes) | packages that hand-rolled concrete callbacks / avoided `Vec[U]` maps | **RETIRED on v0.62.2** (2026-10-03 re-run: all 7 probes exit 0; the ABI unification sprint is in the pin) |
| Manual arity audit (missing args accepted) | missing-arg call probe (to add) | all packages | OPEN (extra args rejected; missing args silent) |
| Child->parent module calls: declare helpers `pub` (NOT siblings-only) | `docs/repro/child-parent-calls/README.md` (v0.62.2 re-verification) | multi-module packages: `helm`, `docker`, `vault`, `k8s` (refactored under the old blanket rule); `training`/`data`/`video`/`serverless` use `pub` parent calls in production | RE-SCOPED 2026-10-03: non-pub cross-module names are T001-invisible; acyclic + cyclic + alias-qualified calls all work with `pub`; the siblings-only rule can be relaxed at Tier-2 |
| Bare `loop` needs trailing `return` | `terraform` probe (COMPILER-FINDINGS row) | parser/scan-heavy packages | OPEN |
| Runtime table builders instead of module const arrays | `docs/repro/const-tables/probe_const_tables.xi` (v0.62.2) | `merkle`, `l10n-currency`, `l10n-unicode` | simple `[N]Int` shapes CORRECT (`sum=9`); **complex `Str`/struct tables BROKEN on v0.62.2** (Str lens 30 vs 14, struct reads all zero, deterministic `bad=5`; runtime controls pass) -- keep runtime builders; row 25 not retirable for complex shapes |
| Parallel Vec fields instead of `Vec[StructType]` (trap 10) | `docs/repro/vec-struct/probe_vec_struct.xi` | `nats`, `i2c` (mirrored Vecs); struct-list packages | **NOT REPRODUCED on v0.62.2** (2026-10-03: push/len/read/field-write/loop-push/`&Vec` param all correct, `bad=0`); existing sites simplify at next touch; retirement candidate for the next release sweep |
| Hand-rolled SHA-256/HMAC | `use xiom.crypto; crypto.sha256_hex(&abc)` | `aws`, `saml` | OPEN (stdlib link failure: `undefined symbol: xiom_sha256_hash`) |
| In-package `_u64_lshr` `n == 63` special case | COMPILER-FINDINGS row (Keccak KAT) | `web3` | OPEN (stdlib defect) |
| Stored+fixed fallback inflater (dynamic-Huffman read limit) | deflate round-trip KATs | `docx`, `pptx`, `xlsx` | OPEN (stdlib capability gap) |
| No enum payload mutation through match bindings (silent drop) | COMPILER-FINDINGS row (`json`) | `json`; enum-heavy packages | rebuild payload + `*obj = ...` | OPEN (silent no-op) |
| No `derive[Clone]` on aggregate-payload types (clone corrupts; crash) | COMPILER-FINDINGS row (`json`, `0xC000001D`) | `json`; any aggregate type | explicit deep-clone functions (`json_clone`) | OPEN (memory-unsafe crash) |
| Contract verification is review-only for record-heavy packages | `xiom-verify --check` output + isolation probes | `json`, `control`, `sensor` promotion candidates | single `&&` requires; solver-unproven documented in SPEC | OPEN (tooling encoding gaps) |

## Cadence rules

- No lockstep versions: a package's version bumps only when its
  code/metadata changes; published versions are immutable, so any fix is a
  patch bump.
- Stable/published packages: maintenance pass = patch bump + fresh green
  run + record.
- Incubating/declaration-only packages: untouched unless ported or fixed.
- Every pass leaves evidence: `STATUS.json` (`run_by`/`commit`/`checked`),
  the growth docs below, and a regenerated
  `docs/PACKAGE-NAMESPACES.txt` at wrap.

## Triage (what "might need maintenance" means, concretely)

- `scripts/status.ps1 -Action validate`: pin drift = must refresh.
- `scripts/status.ps1 -Action list`, sorted by `checked`: oldest recorded
  verification is the head of the maintenance queue.
- `docs/STDLIB-WISHLIST.md` + `docs/COMPILER-FINDINGS.md`: open rows name
  the packages carrying local workarounds and the modules to watch.
- Registry index vs local versions (ops side): packages whose published
  version predates local code with no newer publish are bump candidates
  (the `tftp`/`tap` same-version class).

## Evidence channels

- `docs/COMPILER-FINDINGS.md` -- compiler bugs/behaviors found while
  sweeping; feeds trigger 1.
- `docs/STDLIB-WISHLIST.md` -- stdlib gaps + requesters; feeds trigger 2.
- `docs/PACKAGE_STATUS.md` (generated) -- the human-facing readiness list.
- `%TEMP%\kilo\sweep\` -- raw sweep logs (session-local, not committed).

## Current state (2026-10-03)

- Pin `v0.62.2` (deployed into `%LOCALAPPDATA%\xiom.new\bin`); stdlib
  checkout `E:\xiom-lang\stdlib` (`stdlib-perf1`). Waves 41-55 published
  through `eco-v0.1.34`; allowlist **497**; registry **450 packages +
  2 infra**.
- **`port.ps1` watchdog fixed (2026-10-03, `07301ee6`)**: timeout cleanup
  now kills only the run's own PID tree (the old global
  `Get-Process a | Stop-Process` killed other concurrent lanes' suites);
  per-run `a.exe`/`a.exe.ll` cleanup added. Parallel lanes are stable.
- **Legacy bracket-repair program complete**: 24 packages / 94 real
  sites canonicalized (scan with `Vec<|Result<|Option<|&Vec<` only --
  the `>]` probe false-positives on XML/DOCTYPE strings; byte-level
  grep only, Read output lies).
- The v0.62.2 fleet sweep (2026-09-30, logs `%TEMP%\kilo\sweep-v0622*`)
  re-recorded fleet runs. The expat/nbt "silent `-1`" was root-caused to
  the 4-chunk sweep harness cross-killing in-flight `a.exe` (see
  `docs/repro/v0622-regressions/HARNESS-NOTES.md` UPDATE), not the
  compiler; both suites are green on the pin.
- Open workarounds: the registry above (12 rows). Apply the triage tiers
  at the next compiler release; fixes to the Open rows in
  `docs/COMPILER-FINDINGS.md` trigger a Tier-2 maintenance wave, and the
  `byte-at-128` battery gates the first retirement.
- Stage/README hygiene: repo-side README `Status` sync COMPLETE
  (wave-53: 442 READMEs canonicalized, 445/445 version pairs match;
  unpublished four normalized to `not yet published`). Registry PAGES
  still embed the pre-sync README until a package is republished --
  fold page refreshes into promotion/Tier-2 batches, or the owner may
  schedule a chunked patch-bump republish program; category
  harmonization owner-decided; the registry ruling (no
  version-less metadata refresh; chunked patch-bump republishes behind
  an ops rate window) stands.
