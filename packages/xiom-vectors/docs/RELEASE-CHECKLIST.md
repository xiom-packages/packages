<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# Release checklist (XVECTOR)

The repo is **private by default**; a release only happens on explicit owner
greenlight. Nothing here authorizes a push.

## Preconditions

- [x] Working tree clean; all slices committed signed (`-s`).
- [x] Quiet machine (check free memory; a concurrent heavy build can produce
      spurious reds).
- [x] Toolchain hashes recorded in `SESSION.md` (compiler v0.64.2 /
      `c51170a6`; stdlib `d2b18dc`; packages `26f7d0ae`).

## Steps

1. **Freeze**: no uncommitted changes; note HEAD. -- done: the candidate
   commit (version + notes + sbom + handoff) is the frozen state; batteries
   ran **after** committing it so the tag points at a battery-verified
   commit (deliberate ordering refinement; documented here).
2. **Full battery, both platforms**:
   - Windows: `./scripts/ci.ps1` (suite x2 + sbom + all probes x2)
   - WSL: `bash scripts/ci.sh`
   - Both must print `ALL GATES GREEN` and exit 0. -- done: suite
     171/171 x2 + SBOM/unsafe gate + 32 probes x2 + bench smoke, both
     platforms, exit 0 (see `SESSION.md` green evidence).
3. **Repro bundles** (`docs/repro/*/README.md`): re-run the revision-pinned
   probes at the current compiler; update status rows. -- done at v0.64.2:
   all primary probes rebuilt and run; 9 exit 0 green,
   `contract-trap-exit0` exits 1 (the fixed symptom per its README),
   `xv-str-ref-param` exits 1 (open finding XVC-C-13, red by design).
4. **Compiler findings**: re-test the OPEN rows against the release
   compiler; refresh `docs/COMPILER-FINDINGS-XVECTOR.md` and
   `docs/RELAY-COMPILER.md`. -- done: the only OPEN row is XVC-C-13
   (reproduced on Windows + WSL this session; workaround is lane
   convention). All other findings verified fixed / in-context green.
5. **Readiness**: recompute `docs/PRODUCTION-READINESS.md`; never raise a
   score without evidence. -- done: 80 % (fifty-first pass entry names the
   evidence per dimension).
6. **SESSION**: update STATE, green evidence, relay rows, next tasks. --
   done in the wrap commit that accompanies the tag.
7. **Version**: bump `VERSION` (`0.1.0-dev` -> `1.0.0-rc.1`), commit
   `chore(release): vX.Y.Z`. -- done.
8. **Tag**: `git tag -s vX.Y.Z -m "xvector vX.Y.Z"` (signed; no push yet).
   -- done as an **annotated** tag: no GPG/signing key is configured on
   this machine (`user.signingkey` empty, no `gpg`); commits carry DCO
   sign-off. Re-tag with a key if the owner wants cryptographic signing.
9. **Release notes**: summarize from SESSION + the readiness change log. --
   done: `docs/RELEASE-NOTES-v1.0.0-rc.1.md`; owner package in
   `docs/OWNER-HANDOFF.md` (repo public, runners, rulesets, publish flow,
   benchmark protocol).
10. **Owner gate**: the owner approves and pushes the branch/tag and
    publishes the release. Until then everything stays local. -- pending
    owner action; the lane has reported ready.

## CI

`.github/workflows/ci.yml` runs the same battery once self-hosted runners
labelled `xiom,windows` / `xiom,linux` exist (SHA-pinned actions only).
