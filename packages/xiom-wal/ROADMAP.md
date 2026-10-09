# xiom.wal roadmap

Phase-2 items are deliberately out of scope for the 0.1.0 extraction (the
toolchain rows gate them); nothing here changes the frozen surface.

| Stage | Item | Gate |
| --- | --- | --- |
| reconciliation | `xiom.durable` consumes `xiom.wal`; its `src/wal/*` subtree is folded in and removed there (order fixed in `docs/PACKAGE-WISHLIST.md` section 6) | separate sequenced lane step; this package never edits `xiom.durable` |
| durability | wire `wal_flush` to fsync / `FlushFileBuffers` (the call site is already in place) | stdlib durable-write/fsync row lands |
| integrity | per-record checksum on append/replay (codec v2, backward-readable) | stdlib byte-IO + fsync row |
| recovery | wire the in-memory `WalWriter`/`recovery_scan` to disk replay (torn-page detection, redo/undo of uncommitted txns) | after the checksum row |
| lifecycle | make `wal_close` release a real persistent handle | persistent-handle IO API |
| tests | port `crash_test.ps1` to sh for the Linux lane; add a churn soak on reopen/truncate cycles | ops lane scheduling |
| surface | checkpoint-driven truncate helper (`wal_truncate` to checkpoint LSN) once a checkpoint record convention lands | consumer demand (ORBITDB/XVECTOR) |
