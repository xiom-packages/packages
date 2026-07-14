# Segment Lifecycle

`src/segment/` — how vectors are physically organised for bounded memory,
efficient indexing, and compaction. SCAFFOLD: the state machine and types are in
place; the side effects (building immutable indexes, fan-out search, compaction)
land in Phase 5.

## Why segments

A single mutable store grows unbounded and can't be immutably indexed while it's
being written. The LSM-style answer: writes land in one small **mutable**
segment; when it fills, it is **sealed** (frozen), **indexed** (an immutable HNSW
is built), and thereafter only read. Search fans out across all live segments;
background **compaction** merges small immutable segments into larger ones.

## The state machine (`segment_state.xi`)

```
enum SegmentStateKind { Mutable, Sealing, Sealed, Indexing, Immutable, Compacting, Dropped }
```

Legal transitions (enforced by `segment_state_can_transition`):

```
Mutable ──▶ Sealing ──▶ Sealed ──▶ Indexing ──▶ Immutable
                                                   │  ▲
                                                   ▼  │
                                              Compacting
                                                   │
                    Immutable/Compacting ──────────┴──▶ Dropped   (terminal)
```

| State | Writable? | Meaning |
|-------|-----------|---------|
| `Mutable` | ✅ | Accepts new upserts. |
| `Sealing` | ❌ | Being frozen; no new writes. |
| `Sealed` | ❌ | Frozen; contents final. |
| `Indexing` | ❌ | Building the immutable ANN index. |
| `Immutable` | ❌ | Read-only, fully indexed, searchable. |
| `Compacting` | ❌ | Being merged with other segments. |
| `Dropped` | ❌ | Terminal; storage reclaimed. |

Helpers: `segment_state_is_writable` (only `Mutable`), `segment_state_is_terminal`
(only `Dropped`), `segment_state_code` (dense ordinal used to express the table).

## The segment (`segment.xi`)

```
Segment { id: SegmentId; state: SegmentStateKind; store: VectorIndex }
```

- `segment_new(id, dim)` starts `Mutable` with an empty store.
- `segment_insert` appends (Phase 5 will reject writes unless writable).
- `segment_transition(seg, to)` consults `segment_state_can_transition` and is a
  no-op (returns `false`) for illegal moves.
- `segment_size`, `segment_is_writable`.

## The manifest (`manifest.xi`)

```
Manifest { collection: CollectionId; active_segments: Vec[SegmentId]; last_lsn: Int }
```

The manifest is the durable list of a collection's live segments plus the LSN it
was last consistent at. On recovery the engine replays the WAL up to `last_lsn`
and rebuilds in-memory indexes from `active_segments`.

- `manifest_add_segment` / `manifest_remove_segment` / `manifest_set_lsn`.
- TODO(Phase 2): each change is written as a `WalOpKind.ManifestUpdate` record
  *before* the segment becomes visible to readers.

## Lifecycle timeline

```
upsert ─▶ [Mutable segment] grows
        │
        └▶ size ≥ threshold
              ├▶ transition Mutable→Sealing→Sealed   (+ SegmentSeal WAL event)
              ├▶ transition Sealed→Indexing           (build immutable HNSW)
              └▶ transition Indexing→Immutable         (add to manifest, searchable)

background: many small Immutable segments
        └▶ Immutable→Compacting→Immutable             (merge) → old segments Dropped
```

## Interaction with search

Multi-segment search (Phase 5) inserts a fan-out step into the query pipeline:
iterate `manifest.active_segments`, search each (flat for the mutable one, HNSW
for immutables), and merge all hits into a single bounded top-K heap. Because the
heap enforces `len() <= k` regardless of how many segments contribute, the
`result.len() <= k` guarantee survives fan-out unchanged.
