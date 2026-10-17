// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.config

// Database tuning parameters. Validation lives here so an invalid profile fails
// fast at `db_open` rather than deep inside the storage or index layers. The
// durable-systems substrate (`xiom.core.config.CoreConfig`) was never published
// and its projection (`database_config_from_core`) is RETIRED (2026-10-10) --
// re-introduce it when the `xiom-core` package lands.

pub type DatabaseConfig = {
  page_size: Int;
  buffer_pool_capacity: Int;
  wal_enabled: Bool;
  btree_order: Int;
}

pub fn is_power_of_two(n: Int) -> Bool {
  if n <= 0 { return false; }
  var m = n;
  while m > 1 {
    if m % 2 != 0 { return false; }
    m = m / 2;
  }
  return true;
}

pub fn is_valid_page_size(size: Int) -> Bool {
  if size < 512 { return false; }
  if size > 65536 { return false; }
  return is_power_of_two(size);
}

pub fn DatabaseConfig.default() -> DatabaseConfig {
  return DatabaseConfig{
    page_size: 4096,
    buffer_pool_capacity: 64,
    wal_enabled: true,
    btree_order: 4,
  };
}

// A config is valid when the page size is a legal storage block, the buffer
// pool holds at least one frame, and the B-tree order satisfies the minimum
// branching factor (>= 3) required by the index invariants.
pub fn database_config_validate(cfg: &DatabaseConfig) -> Bool {
  if !is_valid_page_size(cfg.page_size) { return false; }
  if cfg.buffer_pool_capacity < 1 { return false; }
  if cfg.btree_order < 3 { return false; }
  return true;
}
