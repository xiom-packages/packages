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
   that allowlist and stacks sets match exactly.
4. **Dependency-driven**: when a package publishes a new minor/major,
   schedule a check for its dependents (`deps:` in `package.xi`).
5. **Opportunistic**: any package touched for a fix rides the next batch
   (patch bump, re-run, re-record).

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

## Current state (2026-09-29)

- Pin `v0.62.1` (bumped 2026-09-29 from v0.62.0; compiler release
  `f965bd1c`, stdlib stays `stdlib-v0.62.0`). Last full sweep **347/407
  green** (60 declaration-only expected, 0 regressions; 275 fleet records
  re-pointed to `fleet-sweep:v0.62.1`).
- Wave 41 complete and published (`eco-v0.1.13`, 13/13; registry 343 =
  242 stable / 63 incubating / 38 empty; allowlist 392 confirmed by ops
  with zero diff). Wave 42 candidates namespace-checked (`feature`,
  `clustering`, `loss`, `ensemble`, `streaming`, `linter`, `lexer-fw`,
  `barrier`, `forkjoin`, `executor`).
- Open follow-ups: `byte-at-128` direct comparison still open (the
  item-10 claim covers the cast path only; battery README updated), OIDC
  per-run token re-mint (`.github` scope), `tftp`/`tap` same-version
  republish decisions (owner).
