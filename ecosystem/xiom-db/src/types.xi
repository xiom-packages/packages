module xiom.db.legacy.types
// SUPERSEDED by the layered structure — this file is dead and should be deleted.
// The old `xiom.db.types` god-module was split into focused modules:
//   Page / BufferPool / StorageEngine  -> src/storage/page.xi   (xiom.db.storage.page)
//   Row / ResultSet                     -> src/storage/tuple.xi  (xiom.db.storage.tuple)
//   ColumnDef / Schema / IndexDef       -> src/catalog/schema.xi (xiom.db.catalog.schema)
//   Transaction / TxState / WALOp       -> src/txn/transaction.xi (xiom.db.txn.transaction)
//   DbError / DbResult                  -> src/error.xi          (xiom.db.error)
//   DatabaseConfig                      -> src/config.xi         (xiom.db.config)
// The `Vec<Str>` bug in the old ResultSet was fixed to `Vec[Str]` during the move.
