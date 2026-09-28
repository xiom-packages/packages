# xiom-packages/packages

The staging and release home of the XIOM package ecosystem.

Hundreds of packages live here -- codecs and structures for file formats,
network protocols, hardware registers, scientific data, and the platforms
around them -- each one ported to pure XIOM, verified, and released through
the process described below.

## How this corpus is built

This is the staging and release home of the XIOM package ecosystem. The
corpus is ported and maintained with AI assistance; that is not hidden, and
it is why the ecosystem has grown to hundreds of packages this fast. What
makes the result trustworthy is not the absence of assistance but the
process around it: every package must pass its conformance suite on a
pinned toolchain, findings are filed upstream with reproductions, and
nothing publishes without the release gate. If that method is not for you,
the ecosystem is not for you -- we would rather say this plainly than have
you discover it later.

## What is in this repository

- `packages/` -- one directory per package. A finished package carries a
  manifest (`package.xi`), the module under `src/`, a conformance suite
  under `tests/`, a public `README.md`, a byte-level `SPEC.md`, and a
  `STATUS.json` record of the last verified run (commit, tests passed,
  release stage).
- `docs/` -- the working record: the generated package status report and
  namespace snapshot, compiler findings with minimal reproductions, and the
  standard-library wishlist fed by porting work.
- `scripts/` -- the local toolchain wrapper and the gates: `port.ps1`
  (compile + run a package's conformance suite on the pinned compiler),
  `status.ps1` (record and validate `STATUS.json`), `allowlist-guard.ps1`,
  `namespace-check.ps1`, `export-namespaces.ps1`.
- `.github/` -- the publish allowlist and the release workflows.

## The release path

A package moves toward release through explicit, inspectable steps:

1. **Green on a pinned toolchain.** The suite must pass on the compiler
   version pinned in `COMPILER_VERSION`, run from a clean checkout; the
   coordinator re-runs it before recording.
2. **Recorded.** The verified run is written into the package's
   `STATUS.json` with the commit, the counts, and the stage.
3. **Allowlisted.** A published name must be present in
   `.github/publish-allowlist.txt` and pass all repository gates.
4. **Gate.** Releases are cut by tag and published through the registry
   pipeline behind an environment approval; published versions are
   immutable and signed.

Compiler and standard-library defects found along the way are documented
with minimal reproductions under `docs/` and filed upstream rather than
worked around silently.

### Maturity stages

Every published version carries a maturity stage, and the registry badges it
accordingly. First-party packages from this repository publish as
**`incubating`** by default; **`stable`** is an explicit promotion for
packages that have earned it. `deprecated` marks retired names. A corrected
stage cannot be backfilled -- the registry stores it per published version --
so a stage correction ships as the package's next version.

## Internal working notes

`SESSION.md` and the notes under `docs/` are the internal record of that
process. They are kept public for transparency and describe how the work is
coordinated, not the product story; the product story is what ships:
verified, signed and immutable releases.
