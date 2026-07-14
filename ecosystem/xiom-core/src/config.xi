module xiom.core.config

// Central engine configuration. Validation lives here so invalid profiles
// fail fast at startup rather than deep inside the storage layer.

pub type CoreConfig = {
  page_size: Int;
  buffer_pool_size: Int;
  wal_enabled: Bool;
  sync_on_commit: Bool;
  data_dir: Str;
  max_open_files: Int;
}

pub fn core_config_default() -> CoreConfig {
  return CoreConfig{
    page_size: 4096,
    buffer_pool_size: 1024,
    wal_enabled: true,
    sync_on_commit: true,
    data_dir: "./data",
    max_open_files: 256,
  };
}

// page_size must be a power of two; buffer_pool_size and max_open_files must be
// strictly positive. Power-of-two is checked inline to keep config self-contained.
pub fn core_config_validate(cfg: &CoreConfig) -> Bool {
  if cfg.buffer_pool_size <= 0 { return false; }
  if cfg.max_open_files <= 0 { return false; }
  if cfg.page_size < 512 { return false; }
  if cfg.page_size > 65536 { return false; }
  var n = cfg.page_size;
  while n > 1 {
    if n % 2 != 0 { return false; }
    n = n / 2;
  }
  return true;
}

// Developer profile: small buffers, sync disabled for fast iteration.
pub fn core_config_dev() -> CoreConfig {
  return CoreConfig{
    page_size: 4096,
    buffer_pool_size: 64,
    wal_enabled: true,
    sync_on_commit: false,
    data_dir: "./data-dev",
    max_open_files: 64,
  };
}

// Production profile: large buffers, durable sync-on-commit.
pub fn core_config_prod() -> CoreConfig {
  return CoreConfig{
    page_size: 8192,
    buffer_pool_size: 8192,
    wal_enabled: true,
    sync_on_commit: true,
    data_dir: "/var/lib/xiom",
    max_open_files: 1024,
  };
}
