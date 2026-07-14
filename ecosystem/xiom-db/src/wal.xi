module xiom.db.legacy.wal
// SUPERSEDED — this file is dead and should be deleted.
// The WAL was split and moved, and the missing btree import was fixed:
//   WALEntry / WALOpType -> src/wal/wal_record.xi (xiom.db.wal.wal_record)
//   WAL + append/replay/truncate/clear -> src/wal/wal.xi (xiom.db.wal.wal),
//     which now correctly `use xiom.db.index.btree;` for the tree it replays into.
