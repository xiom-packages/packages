# Typed values in storage -- the container decision (M5.2 -> M5.3)

Status: **S3 + typed query predicates LANDED 2026-10-11** (M5.1 codec, M5.2
schema layer, M5.3 engine persistence, M5-S4 typed predicates). Remaining
follow-on: typed SECONDARY INDEXES (value-ordered (typed value, pk) entries;
not required by the M5 checklist gates). This document is the contract that
was implemented; see "Landed details" for the as-built specifics.
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0

## Why this is a decision

M5.1 landed the typed value model and the tuple codec v2 (`TValue`,
`tuple2_*`, FORMATS 5A); M5.2 landed the schema layer (`schema_row`: kind
mapping, validation, encode/decode, id/pk consistency). Neither persists
anything: the engine (`DBFile`) stores Int keys and Int values today, and
"store typed rows" changes the value container in three places at once --
the B-tree node, the WAL record, and the snapshot page. The constraints:

1. **Keys stay Int.** Ordered scans, planner bounds, `query_key_range`, and
   the secondary index `(value, pk)` all assume ordered int keys; the typed
   model applies to VALUES only.
2. **Crash-safety rules unchanged.** WAL-before-ack, torn-tail WAL healing,
   torn-page/torn-block tolerance, generation-committed snapshots,
   single-writer (docs/ISOLATION.md).
3. **Old artifacts keep loading.** v1 snapshot pages and plain WAL records
   must decode without rewrite.
4. **House memory style.** Parallel vectors over `Vec[Option]` element
   writes in hot structures (m226 fixed the language bug; the pattern stays
   out of the tree).
5. **The engine stays value-agnostic.** Payloads are opaque `Vec[Int]`
   bytes; `schema_row` composes above (`validate -> encode -> put_typed`).

## Options considered

| Option | Shape | Verdict |
|--------|-------|---------|
| **A. Entry payloads in the nodes** | `BTreeNode` gains a parallel `payloads: Vec[Vec[Int]]`; empty = none. Snapshot node page v3 adds a payload section; WAL rides the existing tagged-payload records. | **CHOSEN** |
| B. Side payload store | Keep Int->Int tree; value = ordinal into a separate payload log. | Rejected: orphan payloads on overwrite/delete need the deferred-free/GC class (M1.1b) and add crash windows between tree and log; A is strictly simpler on consistency. |
| C. Per-table row trees | A second tree per table keyed by pk with payload values. | Rejected: same surgery as A, duplicated structures; table scoping belongs to the catalog layer later. |

Option A makes the payload part of the record: there is no state that can
outlive its row, no reclamation problem, and replay/snapshot carry it the
same way they carry the int value today.

## Chosen shapes (normative)

**In-memory (S3):** `BTreeNode.payloads: Vec[Vec[Int]]` parallel to
`keys`/`values`; for typed rows `values[i]` mirrors the pk (same int as the
WAL key). Tree search/compare paths touch keys only; insert/update/delete
carry the payload alongside. Int-only users see empty payloads (zero
format change for them).

**WAL (S3, container unchanged):** typed writes use the EXISTING tagged
extension -- `wal_file_append_tagged(w, op, key, value, payload, ts)` with
`payload[0] = 1` (subtype: tuple v2 row) and `payload[1..]` = the encoded
row bytes (FORMATS 5A). Plain int records carry no payload, byte-identical
to today. Replay classifies by payload presence + subtype; malformed
payloads are dropped exactly like malformed records (crash tests compare
counts, not content).

Example record (typed put):

```
7|1|42|42|0|1,219,2,6,1,42,0,0,0,0,0,0,0,3,2,0,0,0,104,105,...
 ^lsn ^op ^key ^value ^ts ^subtype=1 ^tuple v2 row bytes
```

**Snapshot (S3):** node page version 2 -- the existing sections (FORMATS
section 4) plus a payload section: `u64 LE payload_count` (= `key_count`)
then per entry `u64 LE length` + bytes (the node-page family's integer
width). Version 1 pages decode with empty payloads (no rewrite, both
containers auto-detect as before). Payload budget:
`db_file_typed_payload_max(order)` keeps the largest node page inside the
smaller container budget (v2 block payload capacity); `db_file_put_typed`
refuses larger payloads up front.

**API (S3):** `db_file_put_typed(db, key, payload)` (opaque bytes 0..255),
`db_file_get_typed(db, key) -> Option[Vec[Int]]`; delete/checkpoint/replay
unchanged in shape. `schema_row` composes: `schema_row_key` ->
`schema_row_encode` -> `put_typed`. Query filters stay int-based; typed
column predicates and typed secondary indexes are S4 (they compare decoded
values, so they build on S3, not beside it).

## Evidence ladder for S3 -- LANDED 2026-10-11

1. Engine: payloads survive insert/update/delete/search, checkpoint
   (both containers), generation regen, reopen (snapshot + WAL replay);
   legacy v1-node-page artifacts load unchanged (verified against
   pre-change snapshots: single-node CLI store + a 2994-row multi-node
   hybrid store, incl. write + checkpoint migration-on-write). Suite
   tests: `db_file typed: ...` x5 (149 total).
2. Crash: fault-injector scenario E (`probe_fault_sync`): typed put with a
   failing ack sync latches + reopens with the payload recovered; torn
   page/header fallback in section D keeps payloads consistent with values.
3. Fuzz: section (j) -- random put/put_typed/delete mixes with periodic
   checkpoints/reopens vs a model; size/get/get_typed/range checked after
   EVERY op (4 seeds x 200 iters).
4. Zero regressions: the full suite (144 pre-existing) stays green; node
   version 2 is additive and the readers keep accepting version 1.

## Landed details (as-built deltas from the original contract)

- **Typed predicates (M5-S4)**: `TypedQuery`/`TypedCond` +
  `db_file_query_typed` return matching pks in key order; `tuple2_compare`
  defines the total order Null < numeric < Text < Blob (`VInt(1) ==
  VFloat(1.0)`, NaN first/self-equal, text bytewise, blob element-wise);
  `col = -1` addresses the row id; int rows and undecodable payloads never
  match. Suite x3 (comparator table + ops/persistence) + fuzz (k) vs an
  independent model; CLI `qrow`. Typed secondary INDEXES remain a
  follow-on.
- **WAL example**: `7|1|42|42|0|1,219,2,6,...` -- subtype `1` then row bytes;
  the record `value` mirrors the key.
- **Byte discipline**: `db_file_put_typed` validates elements 0..255 and
  refuses otherwise (the snapshot codecs are byte-oriented; accepting
  > 255 would silently mask bits). Replay also drops crafted records with
  non-byte payload elements.
- **Index note**: typed writes drop any stale int-value secondary-index
  entry for the key and add none (typed-column indexes are S4).
- **Non-transactional**: `db_file_put_typed`/`get_typed` are refused/absent
  inside explicit transactions in S3; the replay path still buffers tagged
  payloads in TxOp, so a crafted committed window replays correctly and an
  unterminated one discards (test-pinned).
