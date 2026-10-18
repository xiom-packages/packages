<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Package wishlist from the XVECTOR lane

## Lattice-tier asks (2026-10-16, top-tier directive)

For `xvector-lattice` (`docs/PRODUCT-ARCHITECTURE.md`; owners: L-1 mote
publication, L-3 router, L-4 replica, L-5 ops). Deliverables go through
this lane's relay items; publication of the mote package itself
coordinates here when package-ready (owner directive 2026-10-16).

- **`xiom.http` client half (or a `xiom.http_client` split)** -- the
  router IS a reverse proxy: it needs a robust OUTBOUND HTTP client
  (keep-alive, timeouts, streaming bodies for snapshot/WAL transfer
  between homes, a pluggable TLS hook). The 2026-10-10 eval adopted only
  `http_status_text` and parked the client because the lane's server
  dispatch is static/gate-pinned (`docs/XIOM-HTTP-EVAL.md`); the client
  is exactly the piece L-3/L-4 needs now. Ask: stabilise the client half
  as its own surface + probe so we can adopt it without touching the
  server module. **Priority: medium-high** (otherwise hand-rolled).
- **TLS binding package** (openssl/schannel route per stdlib
  `docs/TLS_DECISION.md`; PULSE filed the ecosystem asks -- XVECTOR adds
  itself as a requester): enterprise serving + shard-to-shard auth.
  **Priority: high** (ecosystem).
- **zstd (real; the custom brotli frame is non-RFC)** -- snapshot/WAL/
  segment shipping for L-4 replicas, backups, cross-node moves.
  **Priority: medium.**
- **OTLP exporter** (join PULSE's ask) -- cluster telemetry beyond the
  scrape endpoint. **Priority: low-medium.**
- **`xiom.btree` / `xiom.kv`** -- unchanged: watch for future
  multi-segment metadata; no adoption now.
- **`xiom.vectors` stays the mote-tier contract** (`docs/PRODUCT-LAYERS.md`);
  no new extraction ask at this time.

> **Coordination bus (2026-10-10):** open cross-lane items are migrated to
> the private `xiom-lang/xiom-relays` repo: `xiom.vectors` extraction =
> **REL-20261010-1550-xvector-9** (packages), `xiom.ann` extraction =
> **-10** (packages), accelerator gating = **-11** (bindings), owner
> greenlight = **-12** (owner). This file keeps the closed history and
> the lane's own adoption ledger; new asks go to the bus.

Proposals and adoption notes from the xiom-xvector lane (vector database).
Checked against the packages-lane tree (`E:\xiom-packages\packages\packages`)
on 2026-10-10, packages lane HEAD `47202b72` (xiom.durable port + WAL
reconciliation wrap). Format:
`| Proposed name | Purpose | Why not stdlib | Deps | Evidence |`.

Registry consumption note (C-PULSE-02): the v0.64.0 concern (registry
`[dependencies]` parsed but not mapped to source roots) is **RESOLVED in
v0.64.2** -- the dependency-root resolver reads `xiom.toml [dependencies]`
and adds installed package roots from `$XIOM_HOME/packages` to the catalog
(the legacy `package.xi deps:` block is not consumed for source roots).
XVECTOR completed its first adoptions on 2026-10-10 (`xiom.wal` 0.1.0,
`xiom.metrics` 0.2.0, `xiom.rate` 0.2.0, plus the `xiom.http.status`
helper subset; see below) and verified file-mode builds against the
installed packages.

## Packages lane status (2026-10-11, 73rd pass) -- wishlist deltas

- HEAD `fb73c5c8` (2026-10-11, bindings batch 52 -- `xiom.sdl3` 0.15.0,
  eco-v0.1.151); this period: **`xiom.ann` 0.2.0 LIVE + verified by this
  lane** (`0a243ce4...`), **`xiom.http` 0.1.6 CONSUMED** (native 507),
  and the earlier `xiom.durable` port + WAL reconciliation (152/152 x2)
  -- the reconciliation confirms `xiom.wal` is the shared WAL vocabulary
  (`xiom.durable` consumes it via `xiom.toml [dependencies]`), which is
  what our first adoption verified end-to-end.
- **`xiom.wal` 0.1.0 is REGISTRY-LIVE and now ADOPTED by XVECTOR**
  (2026-10-10): installed on Windows + WSL from
  `https://registry.xiom-lang.org` (sha256 `c727fb43...a9ab4` + ed25519
  verified; registry key pinned with `xiom pkg trust`, fingerprint
  `4f:3b:47:f3:ae:17:b1:3c`); `xiom.toml` declares
  `[dependencies] xiom.wal = "0.1.0"`; gate `probe_package_wal` (9 checks:
  op codes 1..7 byte-identical to our codec, tagged roundtrip, LSN resume,
  torn-tail skip + heal-on-open, missing-path open). Full design record:
  `docs/XIOM-WAL-ADOPTION.md` (alignment table + D5 migration plan).
- **`xiom.btree` 0.1.0 is in the tree** (`packages/xiom-btree`, tests 22/22,
  revision `c78fe78a`). In-memory `Int -> Int` B-tree extracted from
  ORBITDB -- watch for future xvector metadata/index use (our id -> slot
  map and payload key index are bespoke today).
- **`xiom.metrics` 0.2.0 is ADOPTED by XVECTOR** (2026-10-10, second
  adoption): the `observability.metrics` internals run on the package
  behind the same surface (`/metrics` byte-identical), the engine stat
  counters moved onto it, and the core shim's local `Counter` was retired
  (single-type rule -- compiler finding **XVC-C-14**: struct-field layouts
  resolve by short name across modules; repro
  `docs/repro/xv-counter-type-shadow/`, relay Addendum 10). Gates:
  `probe_package_metrics` (12 checks, direct package) + `probe_metrics`
  (24 checks, lane surface incl. package min/max/mean alignment); full
  design record: `docs/XIOM-METRICS-ADOPTION.md`.
- **`xiom.rate` 0.2.0 is ADOPTED by XVECTOR** (2026-10-10, third
  adoption): the S3 `RateLimiter` internals run on the package behind the
  same API (`rate_limiter_new/_allow` unchanged; 429 path + counters
  unchanged). Accuracy delta: unearned sub-token remainders are now
  carried (fractional refill exact -- the lane limiter discarded them);
  all gate-visible boundaries unchanged. Gates: `probe_package_rate`
  (14 checks, direct package, incl. the carry case) +
  `probe_service_auth`/`probe_metrics` re-run green; full design record:
  `docs/XIOM-RATE-ADOPTION.md`.
- **Discovery (2026-10-10):** `XIOM_HOME/packages` on this machine already
  carries several lane-relevant primitives the wishlist had marked "later
  phase": `xiom.rate` 0.2.0 (adopted), `xiom.router` 0.1.0,
  `xiom.http` 0.1.4 (+ `xiom.kv` 0.1.0, still fsync-gated). Gated
  adoption slices in the same style as `xiom.wal`/`xiom.metrics`
  (install + trust + dependency + probe + migration note).

## Proposed packages (still to extract)

| Proposed name | Purpose | Why not stdlib | Deps | Evidence |
|---|---|---|---|---|
| `xiom.vectors` | Shared dense-vector primitives for XIOM vector engines: `Vector` (Vec[Float32] + dim), distance metrics (cosine/dot/L2), normalization, bounded top-K heap, and the WAL value codec (`[dim, f32-bits...]`) with recovery replay. The portable pure-XIOM baseline under any SIMD/BLAS binding. | Domain layer that changes with index/quantization research (IVF/PQ, fusion scoring); stdlib keeps a minimal surface; two XIOM products need the same types. | stdlib (`xiom.math`, `xiom.num.float`) | Duplication between **xvector** and **orbitdb** (both implement vector math + metrics + top-K); xvector's reference implementation now sits behind the facade/extracted tree with a **169-check suite** + 18 probes (all green x2 Windows + WSL on v0.64.2); the porter extraction gate ("after HNSW hardening") is **met** (multi-layer HNSW, tombstones, compaction, codec, update re-linking, recall harness all landed 2026-10-08/09). **Extraction LIVE (xiom.vectors 0.1.0)**; XVECTOR wired + gated it and **executed the atomic internals swap (2026-10-10, 60th pass)** -- the package now backs the reference lane's vector types, metrics, top-K and value codec (`docs/XIOM-VECTORS-EVAL.md`). |
| `xiom.ann` | Approximate nearest-neighbour indexes: flat exact scan, HNSW graph (build/search/tombstones), recall harness against the exact oracle. | Index parameters and algorithms evolve fast; stdlib should not freeze an ANN API. | `xiom.vectors` | xvector's HNSW is hardened in-memory (recall vs the flat oracle: n=200 300/300 at ef=64, n=800 200/200; tombstones + compaction + strict codec + build-work/latency metrics; gates `probe_hnsw_recall` / `probe_engine_hnsw` / `probe_hnsw_codec`); extraction after `xiom.vectors` (avoid freezing a half-tuned graph -- now satisfied, so extraction can follow the vectors extraction). |

## Adoption notes (existing registry packages)

| Package | Status for XVECTOR | Evidence | Blocked by |
|---|---|---|---|
| `xiom.metrics` 0.2.0 | **ADOPTED 2026-10-10** (second adoption after `xiom.wal`): `observability.metrics` internals on the package behind the same surface; engine stat counters unified; shim `Counter` retired (XVC-C-14). | Gates `probe_package_metrics` (12 checks) + `probe_metrics` (24 checks, incl. package min/max/mean alignment); full batteries green (suite 171/171 x2 + sbom + 34 probes x2 + bench smoke, Windows + WSL); record: `docs/XIOM-METRICS-ADOPTION.md`. | -- (done) |
| `xiom.rate` 0.2.0 | **ADOPTED 2026-10-10** (third adoption): S3 `RateLimiter` internals on the package behind the same API; remainder carry makes fractional refill exact (all gate-visible boundaries unchanged). | Gates `probe_package_rate` (14 checks, direct package) + `probe_service_auth` (24) / `probe_metrics` (24) re-run green; batteries 35 probes; record: `docs/XIOM-RATE-ADOPTION.md`. | -- (done) |
| `xiom.router` 0.1.0 / `xiom.http` 0.1.4 | **EVALUATED 2026-10-10** (58th pass): `xiom.http.status.http_status_text` **ADOPTED** behind the lane adapter (wire-identical; 507 gap lane-owned + `probe_package_http` tripwire); `xiom.router` and the xiom.http parser/types/client **not adopted** (static 7-route dispatch + strict byte pipeline are gate-pinned -- reasons in `docs/XIOM-HTTP-EVAL.md`). | Gates: `probe_package_http` (5 checks) + `probe_http_service` 507 line pin (41 checks); batteries 36 probes, Windows + WSL green. | upstream: 507 missing (`REL-20261010-2002-xvector`); router SPEC status drift noted |
| `xiom.vectors` 0.1.0 | **WIRED + GATED + SWAPPED 2026-10-10** (59th/60th passes): extraction pins **6/6 match** (byte-exact carve); `probe_package_vectors` (13 checks) + the package's own codec probe green; **internals swap EXECUTED atomically** -- all consumers import `xiom.vectors`, the five local modules deleted, codec extracted from `vector_store` (`docs/XIOM-VECTORS-EVAL.md`). | Batteries 37 probes, Windows + WSL green; `probe_reference_oracle` + `probe_floatval_roundtrip` bit-exact gates hold. | remaining: replay-loop delegation at the D-ledger store migration; sequence with the `xiom.ann` porter flow |
| `xiom.kv` 0.1.0 | **Candidate** segment metadata / manifest store; **not adopted now**. | PULSE: `kv_get` returned address-like Str on WSL Linux v0.64.0 (C-PULSE-10; Windows green); packages lane repinned v0.64.2 (io rows re-tested); XVECTOR additionally needs fsync before any KV store can back a durable manifest. | C-PULSE-10 (Linux `kv_get`) + the stdlib fsync gap (`STDLIB-WISHLIST-XVECTOR.md`) |
| `xiom.btree` 0.1.0 | **Watch** (in-tree; see status above). | Ordered Int->Int map with range scans; could back future multi-segment metadata; our current maps are specialised. | publication+adoption path open (same as xiom.wal) |
| `xiom-blas` / `xiom-eigen` / `xiom-openblas` | **GATED** -- bindings relay 2026-10-09: verified incubating placeholders (tests unknown, no timeline); when built they mirror the `xiom.vectors` contract, never define it; no SIMD kernel package from that lane; pilot complete through batch 22, so **accelerators are the sole unscheduled sector**. The portable `xiom.vectors` API stays the contract. | Packages lane FFI/bindings status (bindings worktree); xvector `distance/` is the future call-site seam. | gated on the bindings lane scheduling (no date) |
| `xiom.simd`-class (no exact name found) | If a pure-XIOM SIMD/vector intrinsic package appears, XVECTOR will adopt it for distance kernels; if not, `xiom.ann`/`xiom.vectors` kernels stay scalar. | `xiom-blas`/`xiom-openblas` are bindings, not pure-XIOM kernels; no `xiom-simd` in the tree. | future; coordinate with packages lane before proposing a second kernel package |

## Bindings lane reply (2026-10-08, relayed via packages)

The bindings lane answered the kernel questions above:

- `xiom-blas` / `xiom-eigen` / `xiom-openblas` are **pre-rostered incubating
  placeholders in the bindings worktree** -- stub code, no tests, no promised
  timeline. When built they are **opt-in FFI accelerators that mirror the
  portable `xiom.vectors` contract, never define it** (matches our design:
  `xiom.vectors` is the contract, bindings are drop-in accelerators).
- The bindings lane plans **no pure-XIOM SIMD kernel package** -- that is
  native/stdlib territory; if an `xiom.simd`-class package lands there, the
  bindings libs become accelerators behind it.
- The bindings lane has **no storage-format stake**; `xiom.wal` name/scope
  coordination (ORBITDB vs XVECTOR) is the native lane's call.
- The bindings pilot is gated on the **eco-v0.1.89 publish confirmation**;
  blas-class work is Phase 2+, unscheduled.

XVECTOR consequence: nothing to adopt or block on today; the portable
`xiom.vectors` API remains the only contract we depend on, and the `xiom.wal`
coordination stays with the native/packages lanes (ORBITDB is the second
user).

**Addendum (2026-10-09, inbound relay):** the accelerator row **stays
GATED** -- `xiom-blas`/`xiom-eigen`/`xiom-openblas` are verified incubating
placeholders (tests unknown, no timeline); when built they mirror the
`xiom.vectors` contract, never define it. No SIMD kernel package from that
lane; the bindings pilot is complete through batch 22, so accelerators are
the sole unscheduled sector. XVECTOR's SIMD path (M-P3) therefore stays
seam-first with pure-XIOM kernels. **Follow-up (2026-10-09):** the bindings
durable-DB sector closed (`xiom.sqlite`/`xiom.libpq`/`xiom.odbc` live and
signed); the bindings lane will pick up **accelerators once the
`xiom.vectors` extraction lands** (owner greenlight still pending on our
side).

## Packages lane reply (2026-10-08)

(Historical; superseded in part by the 2026-10-09 status above.)

- **Names frozen:** `xiom.vectors`, `xiom.wal`, `xiom.ann`. XVECTOR owns the
  `xiom.vectors` reference implementation (the conformance suite was then
  **156 checks**, all green x2 in separate units); extraction happens via the
  **porter flow after HNSW hardening / WAL stabilization**.
- **Correction (important):** `xiom.durable` DOES carry `src/wal/*` + `src/txn/*`
  (unpublished) -- do **not** build a competing WAL under durable;
  `xiom.wal` is the **single home** for the WAL.
- **Users:** ORBITDB is the second user for `xiom.vectors` + `xiom.wal`;
  PULSE's JSONL event store is the third WAL user.
- **Kernels:** no pure-XIOM SIMD kernel is planned (native/stdlib territory);
  if one lands, consume it as the portable path -- coordinate before
  proposing a second kernel package.
- **Adoption:** `xiom.metrics` 0.2.0 fine at Phase 10; `xiom.kv` still gated
  on C-PULSE-10 + fsync. New package names get ops scope + allowlist at
  build-green (as `sqlite` did).

## Inbound relay (2026-10-10, via the packages lane) -- accelerator gate

The packages side confirms this wishlist is accurate: the accelerator row
(`xiom-blas` / `xiom-eigen` / `xiom-openblas`) **stays GATED on the owner
greenlight for the `xiom.vectors` extraction** (verified incubating
placeholders, no timeline); the bindings lane picks accelerators up once
that extraction lands. **XVECTOR's v1.0.0-rc.1 release does not change
that gate** -- the extraction still waits on the owner's greenlight, and
the portable `xiom.vectors` API remains the only kernel contract we
depend on (M-P3 stays seam-first).
