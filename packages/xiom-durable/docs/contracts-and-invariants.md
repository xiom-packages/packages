# xiom.durable -- Contracts and Invariants

This is the machine-readable-in-prose companion to the `requires:` / `ensures:` clauses and the predicate helpers in `src/contracts.xi`. Every invariant the shared core enforces is listed here with its rationale, where it lives, and how it is checked. Downstream engines (`xiom-db`, `xiom-vector`) inherit and rely on all of these.

---

## 1. LSN monotonic ordering

**Invariant.** Every WAL record is assigned a log sequence number strictly greater than every previously assigned LSN. LSNs are never reused.

- **Why.** Recovery replays records in LSN order; a non-monotonic or reused LSN would make replay ambiguous and could resurrect or drop effects.
- **Where.** `wal/wal_writer.xi::wal_writer_append` (single point of assignment); `contracts.xi::is_valid_lsn_ordering(prev, next)` returns `next > prev`.
- **Check.** `wal_writer` increments `next_lsn` by exactly one per append; `wal_writer_new` starts at `1` so `0` is reserved for "before any record" (`lsn_zero`).

## 2. Page size is a power of two

**Invariant.** `page_size` is a power of two within [512, 65536] bytes.

- **Why.** Power-of-two blocks align to device sectors and allow index/offset math by masking; out-of-range sizes waste space or break alignment.
- **Where.** `contracts.xi::is_power_of_two`, `contracts.xi::is_valid_page_size`; enforced by `config.xi::core_config_validate`.
- **Check.** Repeated division by two must reduce the value to exactly `1`.

## 3. WAL-before-ack (durability ordering)

**Invariant.** A write may only be acknowledged after its WAL record is durable -- i.e. its LSN is <= the writer's `synced_lsn`.

- **Why.** This is the core crash-safety guarantee: on restart, any acknowledged write is guaranteed to be replayable from the log.
- **Where.** `wal/wal_writer.xi` -- `wal_writer_append` buffers the record and returns its LSN; `wal_writer_flush` advances `synced_lsn` to the last appended LSN.
- **Check.** Callers must call `wal_writer_flush` (or confirm `wal_writer_synced_lsn(&w) >= lsn`) before returning success to the client.
- **Phase note.** In Phase 0 the buffer is trivially durable; Phase 2 replaces `wal_writer_flush` with a real `fsync`, at which point this becomes a hard guarantee.

## 4. Checkpoint truncation safety

**Invariant.** A WAL record may be truncated only if its LSN is strictly less than the checkpoint LSN.

- **Why.** Records at or after the checkpoint may still be needed for replay; discarding them would lose committed effects.
- **Where.** `wal/checkpoint.xi::checkpoint_can_truncate(cp, record_lsn)` returns `record_lsn < cp.lsn`.
- **Check.** Truncation routines must gate every candidate record through `checkpoint_can_truncate`.

## 5. Snapshot visibility

**Invariant.** A record is visible to a read snapshot if and only if its LSN is <= the snapshot's LSN.

- **Why.** Queries fan out across mutable and immutable data; a stable visibility horizon ensures a consistent view for the whole query.
- **Where.** `txn/snapshot.xi::snapshot_is_visible(snap, record_lsn)` returns `record_lsn <= snap.lsn`.
- **Check.** Search/scan paths must filter candidate records through the snapshot before returning them.

## 6. Transaction state transitions

**Invariant.** A transaction moves only through legal states:

```
Open      -> Prepared | Committed | Aborted
Prepared  -> Committed | Aborted
Recovered -> Committed | Aborted
Committed -> (terminal)
Aborted   -> (terminal)
```

- **Why.** Ambiguous transitions make recovery and visibility undecidable; terminal states must be final.
- **Where.** `txn/txn_state.xi::txn_state_can_commit` (Open or Prepared), `txn_state_is_terminal` (Committed or Aborted).
- **Check.** `txn_manager` only commits/aborts and reconstructs the whole `Txn` record on transition; it never mutates a terminal transaction back to an active state.

## 7. Checksum integrity

**Invariant.** A block/record read back must produce the same checksum it was written with.

- **Why.** Detect accidental corruption (bad sectors, partial writes) before trusting data.
- **Where.** `storage/checksum.xi::crc32` (FNV-1a 32-bit), `verify_checksum(data, expected)`.
- **Check.** `verify_checksum` compares a freshly computed hash to the stored value; a mismatch surfaces as `CoreError.ChecksumMismatch`.

## 8. Pin-count / eviction safety

**Invariant.** A page with `pin_count > 0` is in use and must not be evicted; a `dirty` page must be written back before eviction.

- **Why.** Evicting a pinned page invalidates a live borrow; dropping a dirty page loses data.
- **Where.** `storage/page.xi` (`page_pin`, `page_unpin`, `page_is_dirty`), `storage/buffer_pool.xi`.
- **Phase note.** Enforcement in eviction is Phase 1 work (`buffer_pool_put` currently uses a placeholder eviction slot); the pin/dirty accounting itself is implemented today.

## 9. System limits (capacity ceilings)

**Invariant.** Requests must respect the ceilings in `limits.xi` (max dimensions, page size, batch size, key/value size, segment count, graph degree, top-k).

- **Why.** Consistent guardrails prevent resource exhaustion and undefined behaviour at the edges.
- **Where.** `limits.xi` plus `contracts.xi` validators (`is_valid_dimension`, `is_valid_key_size`, `is_valid_top_k`).
- **Check.** Exceeding a ceiling surfaces as `CoreError.CapacityExceeded` or `CoreError.InvalidInput`.

## 10. Format version compatibility

**Invariant.** Data written under one on-disk format version is only read by a build that understands it.

- **Why.** Silent misinterpretation of a changed layout corrupts data; versions make upgrades auditable.
- **Where.** `version.xi` (`storage_format_version`, `wal_format_version`, `snapshot_format_version`, `protocol_version`).
- **Check.** Readers compare the embedded version to the expected one; a mismatch surfaces as `CoreError.VersionMismatch`.

---

## Error mapping summary

| Invariant violated | Surfaced as |
|--------------------|-------------|
| Lookup miss / bad index | `NotFound` / `OutOfBounds` |
| Bad input / over-limit | `InvalidInput` / `CapacityExceeded` |
| Corruption / checksum | `Corruption` / `ChecksumMismatch` |
| IO fault (transient) | `IOFailure` (retryable) |
| Illegal state transition | `InvalidState` |
| Format mismatch / unsupported | `VersionMismatch` / `Unsupported` |
