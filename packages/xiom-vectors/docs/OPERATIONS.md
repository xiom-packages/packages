<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Operations runbook -- xiom-xvector (M-O / O3)

How to run, monitor, back up, and recover the database. Commands are the
lane's scripts; all paths are relative to the repo root. The runnable
server (`out/xvectord.exe`, `api.httpd`) serves HTTP/1.1 on the stdlib
`xiom.net` socket layer and carries the `api.http_service` byte pipeline;
the embedded surface is `xiom.vector.engine`.

## 1. Start / stop

| Mode | How | Notes |
|---|---|---|
| Embedded | link `xiom.vector.engine`; `create_collection` -> `upsert`/`search` | trusted caller; auth off |
| Embedded + durable | `open_durable(ckpt, ckpt+".seg", manifest, dim, metric)` | fsync-on-ack; checkpoint + rotate on shutdown |
| Service (socket) | `out/xvectord.exe [--bind 127.0.0.1] [--port 7707]` | HTTP/1.1; auth/limits/metrics; quit: header `X-Xvector-Quit: 1` |
| Service + durable | `XVECTORD_WAL=home/xvector.ckpt [XVECTORD_MANIFEST=home/xvector.manifest] out/xvectord.exe` | every mutating request fsyncs before its response; clean quit persists the checkpoint and rotates the segment |

Shutdown (embedded): **always** call `http_service_shutdown(eng, wal_path)`
for a drain + whole-file WAL checkpoint; it returns `false` on an
unwritable path (treat as an alert, keep the old checkpoint). In durable
mode a hard kill is safe for every **acknowledged** write: records are
appended to the delta segment and fsynced before the ack (WAL-before-ack),
verified by the file-level kill matrix (`scripts/kill_matrix.ps1|.sh`).
The boundary that remains is power-loss fault injection (see §5).

## 2. Configuration reference

`ServiceConfig` (defaults): `max_request_bytes=65536`, `max_top_k=1000`,
`max_batch=256`, `max_dim=1024`.

| Source | Key | Notes |
|---|---|---|
| env | `XVECTOR_MAX_REQUEST_BYTES`, `XVECTOR_MAX_TOP_K`, `XVECTOR_MAX_BATCH`, `XVECTOR_MAX_DIM` | limits; malformed values ignored |
| env | `XVECTOR_API_KEYS="key1:admin,key2:read"` | enables auth; keys 8..128 `[A-Za-z0-9_.-]` |
| env | `XVECTORD_WAL=<ckpt path>` | durable home (M-D5): fsync-on-ack; `XVECTORD_MANIFEST=<path>` optional |
| env | `XVECTORD_CHECKPOINT_EVERY=<n>` | auto compact+swap every n commits (M-D6; 0/absent = off; clean quit always swaps) |
| env | `XVECTORD_SEAL_EVERY=<n>` + `XVECTORD_SEAL_DIR=<dir>` | auto-roll (M-D7): move the active collection into an immutable sealed segment at n points; dir defaults to the durable home's dir; off by default |
| file | `key=value` lines (`#` comments) via `service_config_load` | unknown keys ignored; malformed line -> `valid=false` |
| code | `service_config_apply`, `service_auth_add_key`, `rate_limiter_new(capacity, refill_per_sec)` | programmatic control |

Auth is **off** by default (embedded); the socket adapter must enable it
(register keys or set `XVECTOR_API_KEYS`). Scopes: read < write < admin;
`/health` and `/metrics` are public.

## 3. Monitoring

- `GET /health` -> `{"status":"ok","service":"xvector","ready":true}`
  (liveness/readiness).
- `GET /metrics` -> prometheus-style text:
  - counters `xvector_requests_total`, `xvector_errors_total`
    (status >= 400), `xvector_search_ops`, `xvector_upsert_ops`,
    `xvector_auth_failures`, `xvector_rate_limited`;
  - histograms `xvector_latency_ms` + `xvector_search_latency_ms`
    (buckets 1/5/10/50/100/500/1000 ms + `+Inf`, `_sum`, `_count`,
    `_p50`/`_p95`/`_p99` as bucket upper bounds);
  - gauges `xvector_collections`, `xvector_points_active`, `xvector_lsn`.
- Structured logs: bounded JSON-line ring (`ServiceState.log`, default
  256 lines, `slow_ms=250`): `{"method","path","status","ms","slow"}`;
  `log.dropped` counts evictions. Pipe the ring to stdout/file in the
  adapter; keys never appear in logs.
- Suggested alerts: `errors_total` rate, `auth_failures > 0`, p99 above
  your SLO, `rate_limited` sustained, `log.dropped` growing.

## 4. Backup / restore drill (embedded)

```text
checkpoint: http_service_shutdown(eng, "backup/xvector.wal")      # whole-file persist (no compaction)
            engine_checkpoint_swap(eng)                            # M-D6: compact + fsync-ordered swap + segment rotate
            engine_manifest_save(eng, "backup/xvector.manifest")   # registry
            seal_segment(eng, seg_id, "backup/segment-N.seg")      # optional per collection
snapshot:   snapshot_create(eng, "backup", "nightly")              # M-D6: compacts, then writes
                                                                   # backup/nightly.{ckpt,manifest,meta}
restore:    snapshot_load("backup/nightly", "import/xvector.seg", dim, metric)  # meta-gated
            (or manually: wr = wal_load("backup/xvector.wal")
             eng = open_engine(wr, "backup/xvector.manifest", dim, metric)
             per collection: restore_segment(eng, "backup/segment-N.seg") when sealed segments were used)
verify:  engine_size / search sanity; collection_stats per collection;
         xvector_lsn gauge monotonic; snapshot: engine_list_collections matches source
```

All file formats are torn-tail safe (longest-valid-prefix load) and
atomically written (temp+rename); the D6 checkpoint and snapshot persists
additionally fsync the temp BEFORE the rename (`wal_persist_sync`), so a
crash never leaves the target replaced by non-durable content.
`engine_manifest_save` is the registry of record; without it, recovery
falls back to the in-WAL manifests. Retention guidance: set
`XVECTORD_CHECKPOINT_EVERY` so the checkpoint stays near live-state size
and recovery stays bounded (measured: 4000 points reload in ~10 ms; a
128k-commit smoke log would otherwise be replayed in full); snapshots are
point-in-time files -- rotate them yourself with your backup tooling (no
in-repo retention/delete policy by design). Multi-segment guidance (M-D7):
roll when the active collection reaches the size your RAM budget tolerates
(the `/stats` mem estimate plus the point count is the guide); sealed
sources are read whole-file and stay in RAM once loaded (no mmap yet), so
compact periodically to bound the source count; the auto-roll policy is
opt-in (`XVECTORD_SEAL_EVERY` + `XVECTORD_SEAL_DIR`) and never deletes
anything -- old segment files after a compaction are left for your tooling.

## 5. Failure domains (known, honest)

| Domain | Behavior today | Mitigation / status |
|---|---|---|
| Process kill (no drain) | **durable mode: every acknowledged write survives** (fsync-on-ack delta segment; kill matrix 6/6 Windows + 6/6 WSL); in-memory mode: prefix recovery only | set `XVECTORD_WAL` / `open_durable`; `scripts/kill_matrix.ps1|.sh` |
| Machine crash / power loss | **fsync-on-ack flushes acknowledged bytes to stable storage**, but power-loss safety is not fault-injected in CI (process-kill durability is what the matrix proves) | OS-level fault injection is future work; `docs/PRODUCTION-READINESS.md` D-phase states the boundary |
| Torn checkpoint / segment / manifest | prefix/line-safe load keeps all complete records; malformed lines skipped (segment), torn tails healed | `probe_wal_file`, `probe_manifest_file`, `probe_segment_file`, `probe_wal_segment` |
| Checkpoint swap fails (disk full / locked) | the ack is unaffected (already fsynced in the segment); the swap is retried on the next commit and at quit; the segment is never reset | `probe_snapshot` (swap failure ordering), alert on the quit-path warning |
| Corrupt/missing snapshot meta | `snapshot_load` refuses (meta-gated); the ckpt/manifest are not touched | `snapshot_valid`, `probe_snapshot` |
| Roll/compaction policy fails | the ack is already durable; the policy retries at the next commit; compaction refuses when a registered source is not loaded | `/stats sealed_*`, server log line at quit |
| Sealed file unreadable at restart | counted in `sealed_missing`; the union serves the rest and never goes silent | `/stats sealed_loaded|sealed_missing`, `probe_multisegment` |
| Interrupted artifact copy (collection move, L-2) | `attach_segment` refuses (integrity footer missing or mismatched): no partial collection attaches, both homes stay consistent | `probe_collection_move` |
| Deep-nested JSON body | rejected 400 by `json_depth_ok` (64) before the parser | stdlib `json_parse` depth cap filed in the wishlist |
| Oversized / abusive requests | 413/400/405 by limits; fuzz gate green | `probe_service_limits`, `probe_http_fuzz` |
| Brute force / key guessing | 401/403 with constant-time compare; token bucket 429 | `probe_service_auth` |
| Disk full / unwritable path | persist returns false; old file intact | alert on `false`; never leave a rebuilt binary from a red build |
| Compiler/stdlib regression | full batteries (suite x2 + sbom + 42 probes x2 + bench smoke + kill matrix) on Windows + WSL | `scripts/ci.ps1` / `ci.sh`; red build = rejection |

## 6. Upgrade / migration notes

- On-disk format versions: checkpoint/WAL magic `xvector-wal 1`
  (ManifestUpdate v1/v2/v3 families), manifest `xvector-manifest 1`,
  sealed segment `xvector-segment 1` (v2 when SQ-armed; since L-2 every
  persisted segment appends a `z <count> <crc32>` integrity footer --
  ignored by old readers, REQUIRED by attach), snapshot meta
  `xvector-snapshot 1 <lsn> <collections>`, and the **D5 delta segment**
  (`<ckpt>.seg`, `xiom.wal` codec v1 lines
  `lsn|op|key|value|timestamp[|p0,p1,...]`; append-only, fsync-on-ack,
  line-tolerant replay with LSN-gap stop, heal-on-open, checkpoint-deduped
  merge; rotated empty after every clean checkpoint). The
  checkpoint file remains a `xvector-wal 1` whole-file compaction output,
  so pre-D5 readers keep working; a delta segment is ignored by pre-D5
  readers (old process = old behavior, no silent misread).
  Loaders accept older records (v1 WAL manifests migrate to the `default`
  collection) and reject unknown headers as invalid rather than guessing.
- Compiler/toolchain pins live in `SESSION.md` + `out/sbom.json`; re-run
  the batteries after any toolchain change and re-record the pins.
- Rollback: checkpoints/manifests/segments are plain text; the previous
  release's loader reads them unchanged as long as the format version
  stays 1 (or the new version ships a migration note here).

## 7. Quick diagnostics

| Symptom | Check |
|---|---|
| Reopen shows fewer points than expected | durable mode: the `.seg` beside your checkpoint missing/stale? recovery = checkpoint + segment merge; in-memory mode: last writes not drained -- check `xvector_lsn` before shutdown (`wal_load` returns a prefix by design) |
| 401 on every call | `XVECTOR_API_KEYS` set? key scope vs route (read vs write vs admin) |
| 413/400 on valid-looking payloads | `max_request_bytes` / `max_batch` / `max_top_k` / `max_dim` env overrides |
| 429 bursts | `rate_limiter` capacity/refill or a misbehaving client; counters show `xvector_rate_limited` |
| Slow tail | `xvector_latency_ms_p99`, `slow:true` log lines, `selection` of Hnsw `ef` params |
| Checkpoint file keeps growing / slow restart | set `XVECTORD_CHECKPOINT_EVERY` (compact+swap); the swap fires at the next commit threshold or clean quit |
| Size/recall unexpectedly low after rolling | `/stats` `sealed_segments` vs `sealed_loaded` vs `sealed_missing`; a missing/unloaded source degrades the union to active+loaded only |
| Battery red | rerun `scripts/ci.ps1`; per-probe logs in `out/ci_<probe>.log`; crash forensics in `out/fuzz_mark.txt` |

## 8. Memory budget (M-P P2)

The engine exposes a documented accounting estimate per collection:
`GET /stats?collection={n}` carries `mem_store`, `mem_graph`,
`mem_payloads`, `mem_total` (per-collection) and `mem_wal`
(engine-wide, the shared log; **not** part of `mem_total`). Model
constants live in `hnsw_memory_estimate` (`src/index/hnsw.xi`); deltas
are exact, absolutes are within struct-padding tolerance (gate:
`probe_memory_estimate`).

Sizing rules of thumb (model-derived, 64-bit):

- **HNSW adjacency dominates**: all `hnsw_layer_capacity()` (=8) row
  slots are allocated per node, each `m0` Ints wide -> `adj` alone is
  `64 * m0` bytes/point (2 KiB/point at the generous default
  m0 = 2m, m = 16). Vector data is stored twice (flat store + graph
  copy): `56 + 8*dim` bytes/point across both.
- 5k x dim-25 HNSW (m = 16): ~10.9 MiB graph + ~0.76 MiB store
  (~2.3 KiB/point); the WAL estimate grows with the un-checkpointed
  record buffer (64 B/record + 8 B/word payload).
- Budget check: estimate `mem_total` for the largest collection, add
  `mem_wal`, and keep 2-3x headroom for the WAL buffer before a
  checkpoint. Re-check after bulk loads.
- **Seal/compact thresholds**: `compact_index` reclaims tombstoned
  graph nodes; the estimate makes the loss visible (`mem_graph` vs the
  live-node model). Recommended trigger: tombstones > 25% of nodes
  (`/stats` `tombstones`/`nodes`) or `mem_graph` > 1.5x the live-node
  model; seal a segment (`seal_segment`) before compaction when a
  durable copy is wanted. Compaction cost is a full HNSW rebuild, so
  batch it (admin path), not per-delete.

## 9. Collection move (offline, L-2)

Move ONE collection between homes with two engine calls plus a file copy
(the grid-runner/drain CLI and roll-then-move support land in L-5):

```text
src:  export_collection(eng, "docs", "move/docs.seg")   # durable roll: the collection's
                                                         # full live state -> ONE segment artifact
                                                         # (the source keeps serving via its sealed
                                                         # entry; v1: no pre-existing sealed
                                                         # segments, non-empty)
copy: <your tooling> copies move/docs.seg to the destination host
dst:  create_named_collection(dst, "docs", dim, metric)  # same dim/metric as the source
      attach_segment(dst, "move/docs.seg")               # installs points+payloads+index config;
                                                         # re-checkpoints (durable before the ack)
verify: search sanity vs the source; engine_size; the index kind/params travel in the artifact
drop: drop_collection(src, "docs")                       # after verification; durable
```

Integrity: every segment persisted since L-2 ends with a `z <count>
<crc32>` footer (declared point count + crc over the content bytes).
Old loaders ignore it (prefix semantics unchanged); **attach REQUIRES a
verified footer** -- a truncated, corrupted, or pre-L-2 copy is refused
with `Corruption` instead of attaching a partial collection. Kill during
the copy touches only the artifact file; both homes stay consistent (the
destination has no half-attached registry entry).

Known limits (documented, gated): the source must be non-empty; attach
targets a freshly created collection (same dim/metric; name is the
caller's choice). L-5 landed the compaction-aware export: a collection
with pre-existing sealed segments (auto-roll policy or an earlier
export) merges through the D7 compaction path -- bit-exact union -- so
sealed collections move too; the cluster-level move/drain operations are
section 11.

## 10. Cluster router (stateless, L-3)

The lattice router (`src/api/router.xi`) sits in front of N single-writer
shards and forwards every collection-scoped request to the owning shard.
It holds a MAPPING, never data state (P4): restart it any time; run
several behind an edge proxy.

**Mapping file** (JSON; owned by admin tooling, read by routers; every
edit bumps `version`):

    {
      "version": 2,
      "shards": [
        {"id": "s1", "url": "http://127.0.0.1:7711"},
        {"id": "s2", "url": "http://127.0.0.1:7712"}
      ],
      "collections": {"docs": "s2", "logs": "s2"}
    }

Loader rules (refuse-start on any violation): `version` is an integer
>= 1; `shards` is a non-empty array of `{id, url}` with unique valid ids
(1..64 chars of `[A-Za-z0-9_.-]`; urls 1..256 chars); `collections` maps
valid names to KNOWN shard ids. Placement is EXPLICIT: a collection is
routable only when the mapping declares it -- record the shard first,
then create the collection through the router (unmapped names answer 404
`not_found`).

**Surfaces:** the route set is forwarded verbatim (the client's key
travels with the request -- shards re-check auth independently, defense
in depth): `POST /collections`, `/collections/{n}/points`
(GET/POST/DELETE), `POST /search` (knn/range/pagination/batch),
`GET /stats?collection={n}`. Router-owned: `GET /health` and
`GET /version` (public; both surface `mapping_version`), `GET /collections`
(the mapped names), and admin-scope `GET /cluster/mapping` (the placement
view) plus `GET /cluster/stats` (the aggregate; a bare `GET /stats` with
no collection parameter is the same aggregate). `/metrics` stays
per-shard (scrape the shards directly).

**Stale mapping (the move window):** when a forwarded request returns
404, the router re-reads the mapping file once. A NEW generation is
accepted only when every referenced shard has a local context; the
request is retried once -- but only when the owner actually changed.
Otherwise the original 404 passes through unchanged. Clients see at most
one retry.

**Aggregation:** `/cluster/stats` walks each shard's own `/collections`
and `/stats?collection=` endpoints using `internal_key` (the router's
configured shard credential; empty = no key). Unreachable or
unauthenticated shards report `reachable: false` with zeros -- never
guessed numbers.

**Transport (v1):** forwarding is IN-PROCESS (the router embeds shard
service contexts); the mapping already carries per-shard `url`s for the
socket hop, which lands with the `xiom.http` client half
(`REL-20261016-1129-xvector-2`). Until then the router ships as a
library + gates (`probe_router_2shards`), not as a standalone binary.

**Non-goals (v1):** cross-collection batches in one `/search` body,
automatic placement, failover; intra-collection scatter-gather is L-6
(phase B).

## 11. Cluster operations (move / drain, L-5)

Online move (admin): `POST /cluster/move` `{"collection": "<n>", "to":
"<shard id>"}` against the router. The router (with its configured
artifact dir) runs:

1. compaction-aware export on the source -- every sealed entry + the
   active remainder merge into ONE artifact (tombstones applied,
   active-wins; bit-exact with the pre-export union). The source keeps
   serving throughout.
2. fresh collection + attach on the destination (artifact integrity
   footer verified; index config travels with the artifact).
3. drop on the source; the artifact file stays for ops to clean/archive.
4. mapping flip + atomic persist (version bump; a failed persist
   reinstalls the source from the artifact and reports loudly).

Semantics (single-writer): every write acked before the export is inside
the artifact; writes after the flip route to the new owner; a router with
a stale mapping cache sees exactly ONE bounded retry (forwarded 404 ->
reload -> retry). Gated by `probe_move_under_load` (no acked write lost
across a 30-id sweep; sealed+active merge exactness; the stale-cache
window == one reload).

Drain a node (decommission step): `POST /cluster/drain` `{"shard":
"<id>"}` moves every collection owned by that shard, round-robin over the
remaining shards, stopping at the first failure (reported, never silent).
The drained shard stays configured but owns nothing -- no new placement;
remove its entry from the mapping file once it leaves the cluster. A
single-shard cluster refuses (400). There is no standalone CLI yet: the
admin route IS the operation while the router is the in-process library;
the CLI ships with the socket transport.

Artifacts: moves write `xvmove_<collection>.seg` into the router's
artifact dir. In the in-process transport the artifact doubles as the
source's sealed file until the drop; ops that ship bytes over the wire
should copy the artifact and verify sha256 on the receiving side.

### Cluster templates (sketch)

Edge proxy terminates TLS for now (the ecosystem TLS binding is a PULSE
gap; see `docs/SECURITY.md`); router and shards speak plain HTTP/1.1
inside the trust boundary.

systemd (per node):

    # /etc/systemd/system/xvectord.service   (one per shard home)
    [Service]
    ExecStart=/opt/xvector/xvectord --port 7701
    Environment=XVECTORD_WAL=/var/lib/xvector/node1/manifest.db
    # + XVECTOR_API_KEYS / XVECTORD_SEAL_EVERY / XVECTORD_SEAL_DIR as needed
    Restart=on-failure

    # /etc/systemd/system/xvector-router.service   (one per cluster)
    [Service]
    ExecStart=/opt/xvector/xvector-router --mapping /etc/xvector/mapping.json
    Restart=on-failure

Docker Compose (sketch):

    services:
      shard1: { image: xvector/xvectord:rc.1, command: "--port 7701" }
      shard2: { image: xvector/xvectord:rc.1, command: "--port 7702" }
      router: { image: xvector/router:rc.1, command: "--mapping /etc/xvector/mapping.json" }

The router image/templates activate when the socket transport lands
(replacing the in-process forward at the `router_forward_direct` seam,
gated on the `xiom.http` client half); until then the router ships as
the L-3/L-5 library and the gates above are its acceptance.

## 12. Replicas (async catch-up, manual promotion, L-4)

A replica is an ordinary durable home fed by `xiom.vector.api.replica`:
each sync byte-ships the leader's whole-file checkpoint (when its size
changed -- a swap rewrites it) and the append+fsync delta segment into
the follower home, then advances the shipped-frontier watermark
(`<follower_ckpt>.ack`, atomic temp+rename). Serving reads from the
follower is plain `open_durable(follower_ckpt, follower_seg)` -- the
loader's checkpoint-dedupe merge is the "apply with checkpoint skip"
rule. Lag = leader frontier - ack; the embedder copies it into
`ServiceState.replica_lag`, which surfaces as `/stats`'s `replica_lag`
field and the `xvector_replica_lag` gauge.

Runbook (manual promotion):

1. Stop the writer (or fence it); run one final ship -- the follower
   must report lag 0.
2. Reopen the follower home as the new writer (`open_durable`); it is
   canonical (leader-shaped files), so the D5/D6 durable machinery owns
   it from then on.
3. Flip the mapping: point the collection at the replica's shard id and
   bump the version (the router's single retry covers the window).

Crash windows: checkpoint first, segment second, ack last -- an
interruption leaves the follower OPENABLE at the previous or partial
point (prefix-exact merge), never corrupt; the next ship repairs it.

Known v1 scope: WAL/active state only -- a rolled collection needs its
sealed segment files shipped via the artifact path (export + copy +
attach); that file-ship loop is an L-4 follow-up. Homes on
shared/network filesystems remain unsupported (local disks only).

Note (found and fixed in the L-4 slice): a durable home that was
REOPENED and then written used to lose the post-reopen writes on the
NEXT reopen. `engine_enable_durable` adopted `max(segment file,
in-memory log)` as the durable frontier, but `engine_recover` renumbers
the recovered log above the file; the first commit then appended past
the never-persisted renumbered block and the segment developed a gap
that the next merge stopped at. Fixed in the engine: the segment file
IS the durable frontier, and the first commit re-sends the block.
Regression line: `probe_reopen_write` (in both batteries).
