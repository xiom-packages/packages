<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Owner handoff -- xiom-xvector v1.0.0-rc.1 (PULSE-style)

The lane reports **ready for the owner's public release + benchmark**. The
repository stays private; nothing below happens until the owner greenlights.

## 1. State at handoff

- **Candidate:** `v1.0.0-rc.1` (annotated tag, local, no push). `VERSION` =
  `1.0.0-rc.1`. HEAD and pins are recorded in `SESSION.md`.
- **Batteries (at the candidate):** suite 171/171 x2 + SBOM/unsafe gate +
  32 probes x2 + bench smoke on Windows **and** WSL -- ALL GATES GREEN.
- **Readiness:** `docs/PRODUCTION-READINESS.md` -- weighted **88 %**
  today (81 % at the candidate; "hardened core"; remaining gaps are the
  gated durability primitives, concurrency, and release-runner activation,
  all documented).
- **Security:** `docs/SECURITY.md` + `docs/sbom-v1.0.0-rc.1.json`
  (44 modules, `unsafe` = 0, compiler v0.64.2, stdlib pin).
- **Benchmark:** `docs/BENCHMARKS.md` (baseline + protocol) with kernel
  fidelity pinned by `probe_reference_oracle`.

## 2. Owner actions (in order)

1. **Greenlight:** review `docs/RELEASE-NOTES-v1.0.0-rc.1.md`,
   `docs/PRODUCTION-READINESS.md`, `docs/SECURITY.md`,
   `docs/OPERATIONS.md`.
2. **Make the repository public** (owner-only). The lane never pushed.
3. **Runners:** register self-hosted runners labelled `xiom,windows` /
   `xiom,linux` (or adjust labels) so `.github/workflows/ci.yml`
   (SHA-pinned actions, runs `scripts/ci.ps1` / `ci.sh`) can execute.
4. **Branch rulesets:** protect `main` (require the CI matrix, signed-off
   commits, no force-push) on the owner's GitHub settings.
5. **Publish the release:** push the branch + the `v1.0.0-rc.1` tag (or a
   final `v1.0.0` after any last review), publish the release notes, and
   attach `docs/sbom-v1.0.0-rc.1.json`.
6. **Benchmark protocol (PULSE-style):** two paths, both ready today:
   (a) in-repo deterministic harness -- `scripts/bench.ps1 -Mode quick|medium`
   (hard-capped loops; watch free memory) -> `out/bench_report.json`
   (`docs/BENCHMARKS.md`); (b) external suites over the live server --
   `out\xvectord.exe` speaks HTTP/1.1 on a real socket (stdlib `xiom.net`),
   with drop-in adapters for ann-benchmarks (`bench/adapters/ann_benchmarks/`)
   and VectorDBBench (`bench/adapters/vectordbbench/`); both live smokes
   are green on the current pin (re-run 2026-10-12: recall@10 1.000 at
   ef>=64; insert 400/400). Run with raised caps
   (`XVECTOR_MAX_REQUEST_BYTES=33554432`, `XVECTOR_MAX_BATCH=1000`) and read
   the honest notes in `bench/adapters/README.md` (single-threaded server;
   no fsync-grade durability claims yet; metadata/filter routes not exposed).
7. **Feedback loop:** file compiler/stdlib findings back through
   `docs/RELAY-COMPILER.md` / `docs/STDLIB-WISHLIST-XVECTOR.md` (they are
   written for the sibling lanes).

## 3. Gated pivots (re-check on every lane pass)

| Gate | Primitive | Unblocks |
|---|---|---|
| stdlib fsync/fdatasync/`truncate` + fd write path + `append_file_bytes` | **LANDED** (waves 115/117, verified in-lane) -- **D5 + D6 shipped on them** (fsync-on-ack + kill matrix + compact/swap + snapshots) | **M-D remaining: multi-segment read path + power-loss injection** |
| stdlib `xiom.net` socket layer | CLOSED for the lane -- `xvectord` ships on it (sequential accept; 2026-10-11) | TLS/proxy deployment (ops-side) |
| stdlib `mmap` | pending (`mmap_anonymous` still an Err stub at `cd281b7`) | P5 memory-mapped reads |
| packages adoptions | `xiom.wal` + `xiom.metrics` + `xiom.rate` + `xiom.http` (status subset) + `xiom.vectors` all wired + gated; **`xiom.vectors` internals swap EXECUTED** (2026-10-10); **`xiom.ann` 0.2.0 live + verified** | the `xiom.ann` swap awaits owner greenlight (`REL-20261011-1308-xvector`) |
| compiler archive | **v0.64.7 pinned 2026-10-18 -- re-pin COMPLETE on BOTH platforms** (release 2026-10-17T22:59Z, run 39076930839; win sha `16a436c4`, linux `153f0cc9`, both installed lane-local incl. WSL; **new linux-arm64 target**; stdlib pin tag `1271dd5`); **full batteries ALL GATES GREEN both platforms** (suite 177/177 x2 + 53 probes x2 + sbom 46 + bench + kill matrix) on stdlib tree `6727526` + packages `2e7c5524` (xiom.http 0.1.9; orbitdb 0.2.1 + pulse 0.2.1 gated); no findings open | keep the latest-toolchain protocol: re-run repros -> suite -> probes -> bench at each archive |

## 4. Evidence index

| Claim | Artifact |
|---|---|
| Everything above | `SESSION.md` (STATE + green evidence + relay rows) |
| Gates | `scripts/ci.ps1` / `ci.sh` (suite x2 + sbom + 41 probes x2 + bench smoke) |
| Correctness | `tests/test_conformance.xi` (177), `tests/probes/*.xi` (41) |
| Crash safety | `probe_kill_recovery`, `probe_wal_file`, `probe_manifest_file`, `probe_segment_file` |
| Fidelity | `probe_reference_oracle`, `probe_hnsw_recall`, `probe_hnsw_codec`, `probe_fuzz_codecs` |
| Service | `probe_http_service`, `probe_service_limits`, `probe_service_auth`, `probe_http_fuzz`, `probe_metrics` |
| Compiler history | `docs/COMPILER-FINDINGS-XVECTOR.md`, `docs/repro/*` (re-run at rc: 9 green, 1 fixed-symptom, C-13 open by design) |
| Security/SBOM | `docs/SECURITY.md`, `docs/sbom-v1.0.0-rc.1.json`, `scripts/sbom.*` |
| Ops | `docs/OPERATIONS.md` |

## 5. Note on signing

No cryptographic signing key is configured on this machine
(`user.signingkey` empty, no `gpg`), so the candidate tag is **annotated,
not GPG-signed**; all commits carry DCO `Signed-off-by`. If the owner wants
signed tags, configure a key and re-tag before publishing.
