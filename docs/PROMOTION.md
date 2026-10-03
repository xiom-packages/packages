# Promotion to stable (production tier)

Owner-approved 2026-10-02. `incubating` is the default experimental tier;
`stable` is a **gated production tier**. Both publish and install -- the
difference is what we certify. Nothing moves to `stable` without this
gate.

## Tier semantics

| Tier | Meaning | Tests | Contracts | API |
|---|---|---|---|---|
| `incubating` | Experimental; may break within 0.x; published and installable | >= 18 deterministic checks | not required | free to change |
| `stable` | Production intent; contract-gated; maintenance-tracked | >= 24 checks incl. error paths + determinism | **mandatory** (see below) | reviewed and frozen for the tier; changes via patch/minor with changelog |

Published versions are immutable; any change to a stable package is a new
patch/minor. The registry badge is a maturity tier, not a prerelease flag.

## The stable gate (all required)

- **G1 Fresh verification.** Allowlisted + published; `port.ps1` x2 green
  on the current pin; trap-14 byte-level grep clean (all angle shapes,
  parameter/local/FIELD positions).
- **G2 Docs complete.** SPEC covers the full documented subset with the
  error catalog; README `Status` block synced; no PLACEHOLDER/PENDING
  text anywhere.
- **G3 API review.** Public surface reviewed (naming, namespace, exports,
  no accidental API), error behavior documented, deterministic behavior
  stated.
- **G4 Contracts.** `requires:` / `ensures:` on the public entry points
  where expressible, plus type invariants where relevant (see the
  contracts section). Contract status recorded per entry point.
- **G5 Test depth.** >= 24 deterministic checks with explicit error-path
  coverage (bad input, bounds, truncation) -- not happy-path only.
- **G6 Workarounds.** Rows in the `docs/MAINTENANCE.md` workaround
  registry that apply to the package are either retired or explicitly
  accepted with a reason and an expiry (the next relevant release).
- **G7 Dependents.** Packages depending on it (per `deps:`) are
  re-checked or the promotion notes why none exist.

## Contracts (mandatory for stable)

XIOM contracts are standard library practice -- stdlib carries 1282
`requires:` and 5195 `ensures:` clauses across 193 files; package-side
coverage is thin and uneven: only **2 of the 276 grandfathered stable
packages** carry clauses (4 total: `bson` 3, `ttl` 1), while the
unpublished C-binding set and the `ported` candidates carry the bulk
(2658 clauses across 66 packages as of 2026-10-03 -- run
`scripts/contract-coverage.ps1`). New promotions must satisfy G4;
grandfathered records are hardened over time.

Syntax (from the contracts cheatsheet):

```xiom
fn divide(a: Int, b: Int) -> Int
  requires: b != 0;
  ensures: result * b == a;
{
  return a / b;
}

pub type NonEmptyStr = Str
  invariant: this.len() > 0;
```

What to annotate on public entry points (in priority order):

1. Scalar preconditions that prevent silent garbage: non-zero divisors,
   index ranges, non-empty inputs, scale/unit assumptions.
2. Postconditions that define success: round-trip equality, monotonicity,
   preserved lengths, result ranges.
3. Type invariants for wrapper types (spans, IDs, handles).
4. Where a property cannot be expressed safely today, document it in
   SPEC as "unasserted" with the reason -- do not write prose contracts
   the tooling cannot check.

Verification evidence:

- Run `xiom-verify` (Z3) on the package where functions are pure enough;
  record the result in the promotion notes.
- Contracts that the solver cannot discharge stay annotated for
  review/tests; the SPEC lists them as solver-unproven. (Contracts are a
  correctness floor, not a proof of bug-freedom.)

## Pre-release vehicle

- Pre-release builds use semver pre-release versions (`0.2.0-rc1`) while
  the record stage stays `incubating`.
- Promotion = final version (patch/minor as appropriate) + `status.ps1
  -Stage stable` + republish. The registry ruling stands: **no
  version-less metadata refresh** -- the badge moves on a real publish.

## Grandfathering (the existing stable set)

The 276 records already marked `stable` predate this gate (they were
promoted by earlier waves). They are **grandfathered**:

- No stage change and no forced republish solely for the gate.
- They enter **hardening batches** (contracts + API review, G3/G4) over
  time, prioritized by dependents, adoption signals, and `checked` age;
  a hardening pass touches a package only when it is its turn or when
  the package is touched for another reason.
- The full gate applies to every **new** promotion from now on.
- If a hardening pass finds a real defect, the fix is a patch/minor with
  a fresh run + record; the tier itself does not silently downgrade.
- Selection inputs as of 2026-10-03 are flat: all 276 stable `checked`
  timestamps are the 2026-09-30 fleet sweep (equal age) and no published
  package depends on another ecosystem package (published deps are
  `xiom.std` only), so batch selection is owner-driven until those
  signals differentiate.

## Wave mechanics

- Batches of 10-20 like growth waves.
- Per package: contract pass -> API review -> bump -> fresh x2 run ->
  record on the new commit -> README sync.
- Priority: (1) the `ported` four (`sensor`, `control`, `json` + the
  remaining legacy port) which explicitly await promotion; (2) oldest
  `checked` incubating records; (3) families with existing dependents or
  owner demand.
- Promotion rides the standard publish batch (names are already
  allowlisted; no scope delta).

## Sequencing

Program order, highest first:

1. Compiler-release Tier-2 maintenance (retire stale workarounds) --
   `docs/MAINTENANCE.md`.
2. README `Status` sync (published pages must match records).
3. Promotion waves (this document).
4. Growth waves.

Rationale: certifying stable on code that still carries retire-able
workarounds would freeze the wrong artifact.

## Asymmetric maturity (expected, by design)

- `stable` is a **verified floor**, not a claim of bug-freedom. We cannot
  prove absence of bugs; contracts bound documented behavior.
- Maturity beyond the gate is adoption-driven and therefore asymmetric:
  registry reviews, bug reports, dependents, and installs accrue per
  package. A package with no adoption stays stable-but-unexercised; a
  heavily used package earns fixes and hardening faster.
- Bug reports flow into patch releases (immutable versions, patch bump +
  fresh run + record). Community reports are the maturity engine; the
  gate only guarantees they start from a verified, contracted baseline.

## Evidence trail

- `STATUS.json`: stage change + `run_by`/`commit`/`checked` on the
  promotion commit.
- `docs/PACKAGE_STATUS.md` (generated) + README `Status` blocks.
- Promotion notes: contract inventory, solver results, accepted
  exceptions (kept in the package `SPEC.md` and summarised at the wrap).
