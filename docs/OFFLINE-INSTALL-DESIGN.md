<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Design note: offline / vendored production installs + platform matrix

Status: DESIGN NOTE (2026-10-12, packages lane). Ask: ORBITDB
`REL-20261012-1945-orbitdb-3` P2 (reproducible production dependency sets,
airgapped builds, pinned local mirrors, platform-support matrix). Related:
PULSE `-1946-pulse-2` dep-set health; registry rows (yank/resolve/publish
guard).

## 1. What exists today

- Registry installs verify **sha256 + ed25519 signature** and print the key
  fingerprint; trust can be pinned (`xiom pkg trust --registry <url> --key
  <hex>`). Store: `XIOM_HOME/packages/<name>-<version>/`.
- Consumer deps resolve from `xiom.toml [dependencies]` / `package.xi`
  `dependencies`; **exact version specs work** (2026-10-12 verified).
- Static site + GitHub releases provide the tarballs; the repo carries
  `packages/index.json` (repo-side) and the live registry index.

## 2. Gaps against a production dependency story

- **No offline path**: installs fetch from the network; no mirror/fetch
  command; airgapped builds have no supported flow.
- **Local artifact fallback is broken**: `xiom pkg --root <pkg-dir> install`
  reports success but lands nothing (`REL-20261010-1549-packages-7`,
  bounced still-red on v0.64.4) -- the vendored/local route cannot be
  trusted until fixed.
- **Range specs unresolved**: `>=x` specs do not resolve (same item);
  consumers must pin exact versions (fine for prod, but it is the current
  mechanism, not a choice).
- **No platform-support matrix**: each package knows its platforms in
  SPEC/tests (SKIP-when-absent classes), but there is no single declared
  matrix per package/version.
- **Vendored-C consumer build**: the dep's shipped `port.args.json` is not
  applied at consumer build time (`-1549-packages-5`, bounced; fix with
  compiler, `-1548-bindings-11`), so vendored-C packages need the manual
  `--c-source` recipe today.

## 3. Target flows (to build)

### A. Online, pinned (usable today -- interim recommendation)
Pin **exact versions** in `xiom.toml`; pin the registry key with
`xiom pkg trust`; keep the resolved `XIOM_HOME` store; record each
artifact's sha256 (from the install output) in deployment docs. Verified
at build time; reproducible while the registry is reachable.

### B. Offline mirror (near-term deliverable)
1. `xiom pkg fetch <pkg>@<exact> --to <mirror-dir>` writes the tarball +
   `SHA256SUMS` (+ the registry signature) -- one command, no installs.
2. Consumers install from the mirror with
   `XIOM_REGISTRY=file://<mirror-dir>` (or `--registry`); verification is
   **identical** to online (sha256 + signature, no downgrade, no
   `--insecure`).
3. The mirror directory is content-addressed and safe to commit to an
   internal artifact store or carry into an airgap.
Depends on: the `-7` local-fallback fix (the copy mechanics) + a `fetch`
subcommand (packages/registry ride the same `xiom-pkg`).

### C. Vendored-in-repo (after B)
Commit `vendor/xiom-<name>-<version>.tar.gz` + `SHA256SUMS` into the
consumer repo; `xiom pkg install --local vendor/...` with the same
verification. Smallest blast radius for single-service deployments.

## 4. Platform-support matrix (deliverable)

- Per package, extend STATUS/SPEC with a declared matrix row:
  `platforms: [windows-x64, linux-x64, macos-x64, macos-arm64]` + runtime
  deps (system DLL/.so presence, SKIP classes) + required toolchain pin.
- Generate `docs/PLATFORM-MATRIX.md` from STATUS (script in this repo);
  the registry can serve the same table later (registry lane).
- Acceptance: a consumer can answer "does xiom.X@Y run on my target, and
  what must be present?" from one table.

## 5. Blockers + owners

| Blocker | Item | Owner |
|---|---|---|
| Local fallback silent no-op; range specs | `REL-20261010-1549-packages-7` (bounced red on v0.64.4) | compiler |
| Consumer build-hook for vendored-C deps | `REL-20261010-1548-bindings-11` | compiler |
| `fetch`/`--local`/`file://` registry support | new | packages + registry (scope when B starts) |
| yank / resolve-outside-workspace / publish guard | `REL-20261010-1549-registry*` rows | registry |

## 6. Interim guidance for ORBITDB deployment docs

Use flow A now (exact pins + key pin + recorded sha256); state the platform
matrix per package from its STATUS/SKIP classes; mark airgap support as
"pending flow B" with the `-7` fix as the named prerequisite. No consumer
change will be required when B/C land -- the same commands gain the
offline flags.
