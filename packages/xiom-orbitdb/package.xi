// XIOM ORBITDB -- Satellite (embedded engine) package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Satellite is the embedded/registry tier of the ORBITDB two-tier line
// (Satellite = embedded engine, registry package; Station = PostgreSQL-class
// server tier, standalone releases). Zero registry dependencies: the engine
// imports only xiom.std (platform dependency, excluded from the registry
// install closure) and its own xiom.db.* modules.
//
// Public surface: xiom.db.api.database (facade), xiom.db.engine (engine),
// plus the storage/query/catalog modules the engine composes. The CLI lives
// at apps/orbitdb_cli.xi. Source pin: see the packages-lane coordination
// item (REL-20261017-*-orbitdb) -- the carve cites this repo + commit.

package xiom_orbitdb {
  stage: "incubating";
  name: "xiom.orbitdb";
  version: "0.3.0";
  description: "ORBITDB Satellite -- production-grade embedded database engine: durable WAL with real fsync, crash recovery (snapshot + tail replay, torn-tail heal), typed rows + typed predicates, secondary index + ORDER/LIMIT, transactions with savepoints and in-process snapshot pins, v2 page container, paged B-tree store with checkpoint/GC (A3/A4), db-file locks + held-fd writes (A6); zero registry dependencies";
  categories: ["database", "storage", "systems"];
  keywords: ["database", "embedded", "wal", "btree", "transactions", "crash-recovery", "satellite"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-lang/xiom-orbitdb";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: [
    "xiom.db.api.database",
    "xiom.db.catalog.schema",
    "xiom.db.catalog.schema_row",
    "xiom.db.catalog.schema_validator",
    "xiom.db.config",
    "xiom.db.contracts",
    "xiom.db.engine",
    "xiom.db.engine.core",
    "xiom.db.engine.snapshot",
    "xiom.db.engine.txn",
    "xiom.db.error",
    "xiom.db.ids",
    "xiom.db.index.btree",
    "xiom.db.index.node_page",
    "xiom.db.legacy.btree",
    "xiom.db.legacy.btree_stdlib",
    "xiom.db.legacy.query",
    "xiom.db.legacy.types",
    "xiom.db.legacy.wal",
    "xiom.db.query.planner",
    "xiom.db.query.query",
    "xiom.db.secondary_index",
    "xiom.db.storage.block",
    "xiom.db.storage.block_store",
    "xiom.db.storage.byte_io",
    "xiom.db.storage.fault",
    "xiom.db.storage.free_space_map",
    "xiom.db.storage.page",
    "xiom.db.storage.page_file",
    "xiom.db.storage.tuple",
    "xiom.db.txn.transaction",
    "xiom.db.wal.wal",
    "xiom.db.wal.wal_record",
    "xiom.db.wal_file"
  ];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
