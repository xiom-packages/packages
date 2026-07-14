# Sharding & Replication (Distributed Layer)

`src/cluster/` (planned) — how `xiom-vector` scales beyond a single node. NOT
IMPLEMENTED: this is Phase 8 in [`../ROADMAP.md`](../ROADMAP.md). `ShardId` already
exists in `core.ids`; the modules below build the distributed layer on top of the
single-node engine.

## Purpose

Scale **beyond a single node** while preserving clear consistency and failure
behavior. Distributed vector search **fans out per segment or shard** across
workers and **merges top-K** results back into one globally-ranked answer. The
guiding principle: distribution must never blur what a result means — consistency
mode and failure behavior stay explicit and testable.

## `cluster/` modules (planned)

| Module | Purpose |
|--------|---------|
| `shard_id.xi` | Strongly-typed shard identifier for placement and routing (bridged to `core.ids.ShardId`). |
| `replica_id.xi` | Strongly-typed replica identifier for a specific copy of a shard. |
| `shard_map.xi` | Routing table mapping collections → shards → replicas; the lookup structure every request consults. |
| `placement.xi` | Placement policy deciding how shards and replicas are distributed across nodes and zones (spread for fault tolerance). |
| `replication.xi` | Replication protocol + consistency policy; early versions may use simple async follower replication. |
| `distributed_search.xi` | Fan-out search across shards/nodes + global top-K merge. |
| `rebalance.xi` | Moves segments/shards between nodes, updates the shard map, and controls traffic draining during the move. |

## Distributed search flow

```
request
   │  parse request
   ▼
route to shards           (shard_map: collection → shards → replicas)
   │
   ▼
parallel per-shard         (each shard/replica generates local top-K candidates)
candidate generation
   │
   ▼
merge global top-K         (single globally-ranked heap across all shards)
   │
   ▼
materialize payloads       (hydrate the winning ids into full results)
```

Because the merge step re-applies the bounded top-K heap (`len() <= k`), the
`result.len() <= k` guarantee survives fan-out exactly as it does for
single-node multi-segment search (see [`segment-lifecycle.md`](segment-lifecycle.md)).

## Failure modes (handled explicitly)

Distribution introduces failure states that must be **modelled, not swallowed**:

- **Partial failures** — some shards answer, others time out or error. The query
  must decide between a degraded-but-labelled result and a hard failure, never
  silently return an incomplete top-K as if it were complete.
- **Stale replicas** — a follower lagging the leader may miss recent writes.
  Replica lag must be observable and bounded by the requested consistency mode.
- **Degraded search paths** — when a shard is unavailable, the fan-out must record
  which shards contributed so callers can reason about completeness.

## Exit criteria (from roadmap)

- Searches **fan out across shards and merge globally-ranked top-K correctly** —
  the distributed result matches what a single-node index would return for the
  same data.
- **Replica lag and consistency mode are visible and testable** — lag is
  measurable and the chosen consistency mode is observable per request.
- **Rebalance never corrupts manifests or loses acknowledged data** — moving
  segments/shards between nodes preserves every acknowledged write and leaves
  manifests consistent.

## Related

- [`segment-lifecycle.md`](segment-lifecycle.md) — per-node segment fan-out that distributed search generalizes.
- [`query-execution.md`](query-execution.md) — the single-node query pipeline the fan-out wraps.
- [`ivf-roadmap.md`](ivf-roadmap.md) — the scale tier that pairs with distribution for billion-scale serving.
- [`../ROADMAP.md`](../ROADMAP.md) — Phase 8 status and exit criteria.
