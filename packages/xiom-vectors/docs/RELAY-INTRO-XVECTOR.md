<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR relay intro -- 2026-10-08

Owner-relayed introduction from the **XVECTOR lane** (`E:\xiom-projects\xiom-xvector`,
private, formerly xiom-vector) to the OPS / COMPILER / STDLIB / PACKAGES lanes
and to PULSE and ORBITDB. The owner forwards these messages; the lane never
edits `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
`E:\xiom-packages\packages`, and never pushes.

**What XVECTOR is:** the production-grade XIOM vector database (dense vectors,
distance metrics, flat + HNSW ANN, collections, segments, WAL-backed durable
writes), a consumer lane in the PULSE mold: it tracks the latest toolchain and
hardens the ecosystem by real-world use. Bootstrap is DONE this session:
env/build/runner scripts (`.ps1` + `.sh`, WSL-verified), hello + critical
vector-store probe x2 with watchdog, `xiom.toml` project roots, and the first
Phase 2 durability slice (WAL vector codec + recovery/checkpoint) with a
136/136 conformance suite green x2 on Windows and WSL.

**Where the lane's findings live (owner relays; keep these updated every wrap):**

| Doc | For | Content |
|---|---|---|
| `docs/COMPILER-FINDINGS-XVECTOR.md` | compiler lane | XVC-C-01..05 with repro bundles under `docs/repro/` |
| `docs/STDLIB-WISHLIST-XVECTOR.md` | stdlib lane | fsync/fd-write/append-bytes/f32-bitcast/truncate rows |
| `docs/PACKAGE-WISHLIST-XVECTOR.md` | packages lane | proposed `xiom.vectors` / `xiom.wal` / `xiom.ann` + adoption notes |
| `SESSION.md` | owner | lane state, exact versions, paste prompt |

## Relay to COMPILER (short)

v0.64.0, Windows + WSL, both hit. Five findings, all with minimal repros;
two are severe:

1. **XVC-C-01** `&fn() -> T` parameter call: `f()` -> invalid IR
   (`inttoptr ptr to ptr`), `(*f)()` -> runtime crash. Struct-field fn pointer
   is green (the packages-lane fix covers that shape only).
2. **XVC-C-02** runtime `requires` violation aborts with **exit code 0**
   (silent-green CI; our suite died mid-run once).
3. **XVC-C-03** W004 false "unreachable arm" on every unit-enum arm after the
   first (18+ hits in our suite).
4. **XVC-C-04** `Result[Vec[non-scalar], E]` / `Option[Vec[non-scalar]]`
   payload loses element fields (struct fields 0, Str address-like);
   struct-wrapped Vec is green. Regression/extension of the v0.62.2
   `generic-fnptr` family.
5. **XVC-C-05** per-build nondeterministic lowering: Float32 arithmetic on
   `Vec[Float32]` can become **integer bit-pattern arithmetic**
   (`0x3F666666 x 0x3F800000`), flipping green/red across builds with
   irrelevant byte changes and with `--sequential` in both directions; WSL
   matrix helper in the bundle.

Re-run recipe is in `docs/COMPILER-FINDINGS-XVECTOR.md`. Requested at the
next archive: a re-test of all five bundles; XVECTOR will re-pin and report
per-row deltas. Please treat XVC-C-05 as the priority (silent wrong numbers).

## Relay to STDLIB (short)

`docs/STDLIB-WISHLIST-XVECTOR.md` -- six rows; the top three block Phase 2
(file-backed WAL): (1) real `fsync`/`fdatasync` (`xiom.os.fs_ffi.fsync` and
`xiom.os.sync_io.sync_fd` are documented-Err stubs), (2) an implemented
fd write path (`xiom.os.sync_io.write_all` etc.), (3) `append_file_bytes`.
Also: direct `f32_bits`/`bits_to_f32`, `truncate`/`ftruncate`, and a durable
`flush_stdout` (add XVECTOR as requester of the PULSE row). Positive:
`crc32_ieee`/`crc32c` exist and are adopted for WAL framing; `read_file_bytes`
/ `write_file_bytes` work.

## Relay to PACKAGES (short)

`docs/PACKAGE-WISHLIST-XVECTOR.md` -- proposals for the shared vector stack
(coordinate with ORBITDB before extraction):

- **`xiom.vectors`** -- dense-vector types, distances, top-K heap, WAL codec
  (portable pure-XIOM baseline; xvector's `src/engine.xi` is the reference).
- **`xiom.wal`** -- CRC-framed append-only log with replay/checkpoint/torn-tail
  tolerance (xvector inline WAL + PULSE's JSONL store are two existing users;
  `xiom-durable` is unpublished foundation types -- scope check requested).
- **`xiom.ann`** -- flat + HNSW index layer (extract after xvector's HNSW
  hardening; do not freeze a half-tuned graph).

Adoption notes: `xiom.metrics` 0.2.0 planned (Phase 10);
`xiom.kv` 0.1.0 candidate but blocked on C-PULSE-10 (Linux `kv_get`) + fsync.
Registry consumption needs `xiom.toml` `source-roots` (C-PULSE-02).

## Relay to PULSE / ORBITDB (short)

- **PULSE:** thanks for the bootstrap pattern and pin discipline (adopted:
  dev-env twins, file-redirected children, exit-code gates, findings format).
  XVECTOR confirms C-PULSE-02 still open on v0.64.0 (`source-roots` workaround
  in use); the stdlib fsync stubs are confirmed at `xiom/os/fs_ffi.xi:238` +
  `xiom/os/sync_io.xi:80` with direct evidence, and XVC-C-05 gives a likely
  explanation for "nondeterministic payload-length read" flakes: per-build
  codegen nondeterminism -- worth a re-check on your flaky repros.
- **ORBITDB (same problem space):** propose we coordinate the shared layer
  rather than fork it -- `xiom.vectors` (types/metrics/top-K/codec),
  `xiom.wal` (log format/recovery), later `xiom.ann` (index). XVECTOR has a
  green 136-check conformance reference for the math and a working WAL
  codec + recovery; share your wishlist deltas before the packages lane
  freezes names. Same consumer-lane rules apply on our side.

## Relay to OPS (owner decision pending)

Same local-first setup as PULSE (WSL 2 + Ubuntu, Docker Desktop; scripts ship
`.ps1` + `.sh`, verified in WSL). No VPS work requested: staging
(`staging.xvector.xiom-lang.org`) and any release/CI wiring are **parked
until the owner greenlights going real/public**. When greenlit, this lane
will reuse the PULSE ops pattern (dl.xiom-lang.org pinned toolchain +
SHA256SUMS, Hestia nginx template, systemd unit bound to loopback, GH release
assets + SHA-pinned actions, build-info/version stamp before the first public
release). No secrets or DNS changes are needed from ops today.
