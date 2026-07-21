module xiom.db.config
use xiom.core.config;

// Database tuning parameters. Validation lives here so an invalid profile fails
// fast at `db_open` rather than deep inside the storage or index layers. The
// database config is a thin, engine-facing view; the durable-systems substrate
// config (`xiom.core.config.CoreConfig`) is the source of truth for on-disk
// behaviour and is projected in via `database_config_from_core`.

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

fn default_btree_order() -> Int {
  return 64;
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

// Project a substrate CoreConfig into the database-facing view. The B-tree
// order defaults to the core limit; callers may override afterwards.
pub fn database_config_from_core(core: &CoreConfig) -> DatabaseConfig {
  return DatabaseConfig{
    page_size: core.page_size,
    buffer_pool_capacity: core.buffer_pool_size,
    wal_enabled: core.wal_enabled,
    btree_order: default_btree_order(),
  };
}
