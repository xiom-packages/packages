<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Packages-lane wishlist (intake + triage)

Source: PULSE consumer lane relay 2026-10-05
(`E:\xiom-projects\xiom-pulse\docs\PACKAGE-WISHLIST-PULSE.md`, pin v0.63.1,
stdlib `15cb889`). Internal findings are appended here as they are triaged.
Status legend: **IN-FIX** / **APPROVED-NEW** / **EXTEND** / **MERGE-INTO** / **DECIDED**.

## 1. Consumer defects (fix before new packages)

| Item | Triage | Detail |
|---|---|---|
| `xiom.http` 0.1.0 parser (a/b/c) | **FIXED + PUBLISHED** (0.1.1, `eco-v0.1.59`, run `37335349031`; task `ses_ef3474d7...`, 2026-10-05) | (a) missing `use xiom.http.types;` in `src/parser.xi` -> consumer T001s; (b) bare `&mut Int` cursor reads yield the address on v0.63.1 (compiler C-PULSE-04) -> `Unexpected end of request line pos=372324169712`; (c) zero parser tests. Fix = explicit import + `*pos_ref` deref + parser KATs (request/response/headers/malformed). Publish as a single-package hotfix (0.1.1) because registry consumers are blocked. |
| `xiom.http` `src/server.xi` 32-line shell | **DECIDED + DOCUMENTED** (README server-stub section in 0.1.1) | No accept loop/routing; PULSE owns its server today. Owning HTTP serving would need sockets/threads and is deferred to a later scoped decision (possibly 0.2 with `xiom.router`). |

## 2. Proposed packages (PULSE intake, triaged against the registry)

| Proposed | Triage | Notes |
|---|---|---|
| `xiom.router` | **DONE + PUBLISHED** (0.1.0, `eco-v0.1.62`, run `37350671893` rerun SUCCESS after the ops scope extension; feat `67fdb45d`, live-verified) | exact + path-parameter routes, method matching, aggregated 404/405, deterministic first-match; stdlib-only. |
| `xiom.session` | **DONE + PUBLISHED** (0.1.0, run `37636386772` rerun SUCCESS; feat `7b7da18c`, 24/24 x2) | server-side store: CSPRNG ids with collision retries, absolute TTL, memory backend, cookie headers, rotate/prune; deps `xiom.std` only. |
| `xiom.jwt` v0.2 (HS256) | **DONE + PUBLISHED** (0.2.0, `eco-v0.1.60`, run `37338296689`; task `ses_ef3387e5...`) | HS256 sign/verify on top of existing structural decode: alg allowlist, `exp` required / `nbf` optional, constant-time MAC compare; deps `xiom.crypto` (HMAC links under `XIOM_RUNTIME_DIR`; the 0.64.0 archive should remove that requirement). |
| `xiom.ratelimit` | **DONE + PUBLISHED** -- keyed layer in `xiom.rate` (0.2.0, `eco-v0.1.61`, run `37340030888`; task `ses_ef329199...`) | `xiom.rate` 0.2.0 adds per-IP/route/user keyed buckets and windows plus prune hooks; the 429 envelope lives in `xiom.http.middleware`. |
| `xiom.metrics` | **EXTEND DONE** (0.2.0, feat `1680104b`, 40/40 x2; publish batch staged) | labels + registry + Prometheus 0.0.4 text exposition (`metric_exposition`) + `metric_latency_bounds_ms`; existing 0.1.x primitives unchanged. |
| `xiom.static` | **DONE + PUBLISHED** (0.1.0, run `37636386772` rerun; feat `50742952`, 25/25 x2) | MIME/ETag/Last-Modified/Range/cache-control + traversal guard + byte-safe serve pipeline (200/206/304/404/416). |
| `xiom.kv` | **DONE + PUBLISHED** (0.1.0, run `37636386772` rerun; feat `a4057093`, 28/28 x2) | log-structured KV: crc32c-framed segments, torn-tail repair, tombstones, compaction via atomic rename, snapshots; `io.list_dir` workaround documented. |
| `xiom.http.middleware` | **DONE + PUBLISHED** (0.1.0 already live -- the existing `xiom.http.*` registry scope covered it; feat `0bbd50c4`, 22/22 x2) | envelope-agnostic helpers: request-id, access log, CORS header lines, constant-time CSRF, JSON error body. |

## 3. Build order (agreed with PULSE's suggested sequence)

1. `xiom.http` 0.1.1 hotfix (IN-FIX).
2. `xiom.jwt` HS256 (0.2.0) -- unblocks PULSE Step 2 auth.
3. `xiom.router` + `xiom.http.middleware` (PULSE Step 2 skeleton).
4. `xiom.session`, `xiom.rate` keyed layer, `xiom.metrics` 0.2, `xiom.static`.

## 4. Process requirements

- The four new names (`router`, `session`, `static`, `http.middleware`) require the ops scope
  enumeration to be confirmed BEFORE the allowlist delta is appended (policy).
- New packages go through growth waves: port x2 + trap-14, `incubating` records, publish.
- Extensions are minors: `jwt` 0.2.0, `metrics` 0.2.0, `rate` 0.2.0.
- PULSE consumes the registry only; each README gets a 3-line consumer snippet (its explicit ask).
- PULSE positives to keep: `xiom.cookie` 0.1.1 and `xiom.jwt` 0.1.1 both 8/8 consumer probes;
  after the wave: `xiom.jwt` 0.2.0 (HS256) adopted/verified, `xiom.cookie` 0.1.1 verified,
  `xiom.rate` 0.2.0 recorded for its hardening slice (PULSE relay 2026-10-05).
- PULSE scope confirmation (2026-10-05): `router` first (replaces their router), then
  `session` (replaces their store), `static` and `http.middleware` as later slices; the
  registry allowlist delta remains the owner's call.
- PULSE adoption round (2026-10-05 v2): `xiom.router` 0.1.0 adopted cleanly (probe 8/8,
  suites x2 + smoke 44/44; their `src/router.xi` is now a thin wrapper); `xiom.jwt` 0.2.0
  adopted (probe 11/11 + 6 app checks); `xiom.rate` 0.2.0 recorded; PULSE order now
  **middleware next → session → rate adoption → metrics 0.2 (latency histograms) → static
  → kv**; `metrics` 0.2 must serve latency histograms (bounds preset added to the brief).
- PULSE cross-ref **C-PULSE-02** (installed packages absent from the compiler module
  catalog; `xiom.toml` source-roots workaround) -- same class as the packages-lane
  observation that raw `--run` inside a package dir can fail the catalog stage while
  `port.ps1`/the repo-root wrapper compile the same files.

## 5. Delta 2026-10-08 (PULSE adoption round 3, Linux/WSL session)

Source: PULSE relay 2026-10-08 (`E:\xiom-projects\xiom-pulse\docs\PACKAGE-WISHLIST-PULSE.md`
delta 2026-10-07; PULSE suites x2 all 0, smoke 61/61, crash/rate/store/proxy green).

| Package | Status | Detail |
|---|---|---|
| `xiom.metrics` 0.2.0 | **ADOPTED GREEN** | labeled status counters, 11-bound latency histogram, Prometheus exposition in `src/metrics.xi` (holder pattern); uptime gauge at render. |
| `xiom.http.middleware` 0.1.0 | **ADOPTED GREEN** | CSRF token + constant-time validate (`src/session.xi`); CORS header block (`src/cors.xi`). |
| `xiom.static` 0.1.0 | **ADOPTED GREEN** | favicon through `static_serve`: mime, ETag/Last-Modified/Cache-Control, If-None-Match 304, Range 206/416, traversal guard. |
| `xiom.session` 0.1.0 | **DEFERRED (compiler-gated C-PULSE-09)** | consumer probe green; store swap crashes when driven from wrapper modules (inline green). Recorded in `docs/COMPILER-FINDINGS.md`; local store retained; CSRF still adopted. |
| `xiom.kv` 0.1.0 | **BLOCKED (C-PULSE-10; Linux-target-specific)** | WSL Linux red (`kv_get` address-like Str + multi-key `kv_get_bytes` truncation); packages-lane Windows v0.64.0 probe GREEN for the identical shape (`packages\xiom-kv\tests\probe_kv_get_str.xi`). JSONL store stays the documented fallback on Linux. |

Carry-forwards:

- `xiom.static`: document that `static_resolve_path` rejects a leading `/` (consumers strip
  it from the request target) -- README line at the package's next touch (policy 1b).
- `xiom.kv`: at the next touch, add a `kv_get`-after-`kv_put` case with values >= 8 bytes
  and a multi-key overwrite case to the conformance suite (PULSE ask; Windows green today,
  Linux gates on the compiler fix).
- Cross-refs: **C-PULSE-08** (`dependency_roots_under` dotted-key mismatch, m212 latent --
  keep the `xiom.toml` source-roots workaround on both platforms until the next archive)
  and **C-PULSE-11** (type alias to a package type defaults to i64 with a warning; recorded
  in `docs/COMPILER-FINDINGS.md`).

## 6. Inbound lane proposals 2026-10-08 -- ORBITDB + XVECTOR (name freeze + shared-layer decision)

Sources: `E:\xiom-projects\xiom-orbitdb\docs\RELAY-PACKAGES-ORBITDB.md` (ORBITDB,
embedded DB; 93-test suite green x2 on v0.64.0; no registry consumer pass yet) and
`E:\xiom-projects\xiom-xvector\docs\PACKAGE-WISHLIST-XVECTOR.md` (XVECTOR, vector DB;
no registry consumer yet). Both lanes hit C-PULSE-02 (source-roots) on v0.64.0.

**Name freeze** (checked 2026-10-08: no in-repo dirs, nothing in the registry, 0
namespace conflicts): `xiom.wal`, `xiom.vectors`, `xiom.ann`. `xiom.btree` is a
tracked candidate -- ORBITDB's delete/underflow invariants for odd orders are still
debt, so extraction waits for a churn soak. `xiom.db` (the ORBITDB engine behind
`xiom.db.*`) is an owner-parked eventual publish.

**Shared-layer decision (one layer, not two forks):**
- `xiom.vectors` = the portable contract (dense vector types, cosine/dot/L2,
  normalization, bounded top-K, WAL value codec). Reference implementation:
  XVECTOR `src/engine.xi` (136 checks green x2). ORBITDB is the second user; freeze
  the name now, extract through the normal porter flow once HNSW hardening lands.
- `xiom.ann` = ANN indexes (flat exact scan + HNSW, recall harness vs the exact
  oracle). Extract after XVECTOR's HNSW hardening (tombstones/tuning), consuming
  `xiom.vectors`.
- `xiom.wal` = **standalone package** (answer to ORBITDB's boundary question: NOT
  folded into `xiom.kv`/`xiom.db`). Storage policy + file format is a domain layer
  with three users: ORBITDB's crash-tested core (reference), XVECTOR's in-memory
  codec, and PULSE's append-only JSONL store. ORBITDB shapes the API from its
  crash-probe evidence; XVECTOR aligns its codec; `xiom.kv` may adopt the format
  later without API churn (it remains a KV store).

**Overlap correction (important):** `xiom.durable` (in-repo, incubating, unpublished,
tests=unknown) already carries config/error/ids/storage/**WAL/txn** modules --
`src/wal/*.xi` (lsn, record, writer, reader, checkpoint, recovery) and `src/txn/*.xi`,
66 pub fns -- and its manifest description claims a "storage, WAL, transactions
substrate". The XVECTOR note that durable "covers foundation types, not a WAL" does
not match the tree. There is no registry conflict (both unpublished), but the WAL
home must be reconciled before either publishes. Native-lane proposal: `xiom.wal` is
the single shared WAL; `xiom.durable` keeps foundation/storage/txn-types scope, and
its WAL subtree is folded into `xiom.wal` (or removed) at the extraction, since
durable is unpublished and there is no compatibility cost. `xiom.snapshot` is
unrelated (text snapshot comparison), no overlap.

**Adoption notes:** `xiom.metrics` 0.2.0 planned (XVECTOR Phase 10); `xiom.kv` 0.1.0
is a candidate for both lanes but gated on C-PULSE-10 (Linux `kv_get`; Windows green)
plus the stdlib durable-write/fsync row (`docs/STDLIB-WISHLIST.md`, 2026-10-05); the
blas-class dirs (`xiom-blas`/`xiom-eigen`/`xiom-openblas`) are pre-rostered binding
placeholders -- opt-in accelerators behind the portable `xiom.vectors` contract,
never the contract (bindings-lane answers acknowledged in the XVECTOR wishlist); no
pure-XIOM SIMD kernel package is planned (native/stdlib territory) -- if `xiom.simd`-
class work lands, kernels live there and the FFI libs accelerate behind it.

**Process:** both lanes relay through their own docs to the owner/native lane. New
names get an ops scope enumeration + allowlist append at their build-green, same as
`xiom.sqlite` (bindings batch 1, `eco-v0.1.89`). Cross-lane coordination for
`xiom.vectors`/`xiom.wal`/`xiom.ann` goes through the native lane until the names
are published; the shared-layer roster above is the freeze point (reopen only by
relay, not by a second implementation).

**Response delta (ORBITDB -> packages, 2026-10-08; `RELAY-PACKAGES-RESPONSE-ORBITDB.md`):**
- `xiom.btree` gate **MET**: churn soak green (orders 4/5/6 x 20k ops at keyspace 4096,
  seed matrix, structural validator; suite 95/95 x2); three real defects fixed
  (child-node-index contract after merge, leaf-borrow placeholder, odd-order min-keys).
  Extraction unblocked; proposed surface `btree_new/insert/search/delete/range_query/
  min/max/size/to_vec`; documented invariant `min_keys = (order-2)/2` (odd orders
  included); the churn probe is the package acceptance test.
- `xiom.wal` format agreed: **one format = durable's record shape + ORBITDB's disk
  contract.** Keep `WalOpKind` + `WalRecord { lsn, op, key, value, payload, timestamp }`
  from `xiom.durable.wal.wal_record`; disk layer (`wal_open/append/flush/replay/
  last_lsn/len/truncate/close`) from ORBITDB's landed `src/wal_file.xi` reference.
  Codec v1: `lsn|op|key|value|timestamp[|payload_csv]`, torn-tail heal before append;
  per-record checksum deferred to the stdlib byte-IO/fsync row. Crash contract:
  write N -> hard kill -> torn tail -> reopen -> replay exactly N -> heal-append -> N+1
  (crash_test.ps1/sh green x2 + 200-record soak). Payload convention: `payload[0]` =
  subtype tag for xvector/xiom.db.
- `xiom.durable` reconciliation order: (a) packages moves `src/wal/*` under `xiom.wal`
  (types kept as-is); (b) ORBITDB lands the disk segment + replay + crash harness
  against that shape (their `wal_file.xi` is the drop-in reference; codec/heal/replay
  + the probe become the package acceptance test); (c) `xiom.durable` keeps `src/txn/*`
  and consumes `xiom.wal`. Nothing in durable's WAL names is lost.
- **Queued native-lane work:** create `xiom-wal` (extraction: durable's `src/wal/*`
  vocabulary + ORBITDB's disk layer; porter flow; new name -> ops scope + allowlist at
  build-green) and later `xiom-btree` (extraction ready; same flow), then
  `xiom.vectors`/`xiom.ann` after XVECTOR's hardening.

## 7. Lane deltas 2026-10-08 (evening) -- PULSE v0.64.1 sweep + ORBITDB/XVECTOR wishlist state

Source: PULSE `PACKAGE-WISHLIST-PULSE.md` delta 2026-10-08 (Linux v0.64.1 sweep),
ORBITDB `PACKAGE-WISHLIST-ORBITDB.md` + response, XVECTOR `PACKAGE-WISHLIST-XVECTOR.md`
(read 17:45Z; both already carry the packages-lane replies).

**PULSE (consumer-verified on Linux v0.64.1):**
- **C-PULSE-10 CLOSED on Linux** (fixed by m217): `xiom.kv` kv-mode smoke 73/73 and a
  20-minute store soak green (756 writes/0 fail, count stable across compact+reopen,
  hard-kill reopen intact). PULSE decision: default stays `jsonl`; kv remains the verified
  opt-in backend until the ops surface is kv-aware (Dockerfile/backup/crash_test/DEPLOYMENT).
- All ten adopted packages' probes green on the Linux archive (state-holder, session-inline,
  adopt-smoke, stdlib-server-parse, schema, audit-rotate, kv, middleware, metrics, static,
  session).
- **C-PULSE-13 (NEW, compiler/installer):** Unix shipped-installer layout mismatch --
  `xiom pkg` installs to `$HOME/xiom/packages` while the compiler resolves
  `~/.local/share/xiom` (canonical) -> dependency roots resolve zero; Windows unaffected.
  PULSE workaround: symlink `$HOME/xiom/packages` -> canonical `packages`, or `XIOM_HOME`.
  Recorded in `docs/COMPILER-FINDINGS.md` (compiler lane).
- **`xiom.http` 0.1.1 is the known-red republish gate on v0.64.1** (extern-unsafe
  enforcement; 67 T001s as a catalog dep; PULSE pruned it). Fix in flight (compat porter:
  unsafe confinement + republish as 0.1.2); see the findings doc for the fleet sweep list.
- Bindings routing: PULSE files binding requests here; likely first = a durable DB/KV
  client binding for the event store (`xiom.sqlite` 0.2.0 already covers the SQLite case).

**ORBITDB:** wishlist state unchanged since the response -- `xiom.btree` gate MET (churn
soak; invariant `min_keys=(order-2)/2`; acceptance = churn probe), `xiom.wal` ships
standalone (durable record shape + ORBITDB disk contract; `payload[0]` subtype tag),
`xiom.durable` reconciliation order fixed; extraction queue stands (`xiom-wal` then
`xiom-btree`, ops scope + allowlist at build-green). New docs since: storage-layout,
query-pipeline, PRODUCTION-READINESS (no new package asks).

**XVECTOR:** wishlist carries the packages-lane reply (names frozen, 156-check reference
suite, no pure-XIOM SIMD planned, durable-WAL correction). No new asks; adoption of
`xiom.metrics` at Phase 10 and kv gated on fsync as recorded.

## 8. Extraction relay results 2026-10-09 -- `xiom.wal` + `xiom.btree` (native lane)

**`xiom.wal` 0.1.0 extracted** (`packages/xiom-wal`, commit `137a8200`): durable's WAL
vocabulary (types + names as-is) + ORBITDB's crash-proven disk layer, single module
`xiom.wal` (487 lines). Native evidence: port **21/21 x2**; crash **x2 6/6** + 200-record
soak (segment **3,081 B**, matching the ORBITDB reference); truncate smoke keep `lsn >= 15`
-> 7; bracket scan clean. New compiler finding recorded
(`io.read_file_lines` false-contract on empty reads; workaround adopted in `wal_replay`;
`docs/COMPILER-FINDINGS.md`). Extraction is **additive**: `xiom.durable` is untouched;
reconciliation stays the sequenced step (durable keeps `src/txn/*`, drops its `src/wal/*`
at its own port and consumes `xiom.wal`).

**`xiom.btree` 0.1.0 extracted** (`packages/xiom-btree`, commit `c78fe78a`): verbatim carve
from ORBITDB `src/engine.xi` B-TREE section (only module/import-list changed; both existing
`requires:` clauses kept), 616 lines. Native evidence: port **22/22 x2**; churn matrix
orders **4/5/6 x 20k ops @ keyspace 4096 GREEN** (remaining=1355 each); bracket scan clean;
pins in SPEC section 2.

**NEW ORBITDB finding -- order-3 delete corrupts (relay + repro):**
`min_keys = (order-2)/2 = 0` at order 3 permits 0-key/1-child non-root internal nodes; a
later `fill_child` -> `merge_children` reads `children[pos+1]`/`keys[pos]` out of bounds
(observed: materialized garbage key `-8070446941336389272`, then
`MISMATCH search-missing op=69 key=4`). Repro:
`packages/xiom-btree/tests/churn.ps1 -Order 3 -Ops 100 -N 16 -Seed 777` -> exit 3
(confirmed native). The ORBITDB gate never ran order 3 (matrix 4/5/6), so this is new
information: fix the merge guard upstream **or** restate the invariant as `order >= 4`.
The package keeps the carve verbatim with the limitation documented (SPEC section 2.3,
README, ROADMAP) and the suite scoped to orders 4/5 for deletes. Re-sync the carve after
the upstream fix and re-expand the matrix to order 3.

**Ops:** both names are new (`xiom.wal`, `xiom.btree` not in the allowlist; the guard
ignores non-allowlisted names) -- scope enumeration + allowlist append (506 -> 508)
requested from ops via the owner; publish only after the confirmation.
