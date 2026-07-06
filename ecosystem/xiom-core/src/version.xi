module xiom.core.version

// Explicit, auditable format versions. Storage engines must be able to reject
// or migrate data written by an incompatible build, so each on-disk artifact
// carries its own format version rather than sharing one global number.

pub fn engine_version() -> Str {
  return "0.1.0";
}

pub fn storage_format_version() -> Int {
  return 1;
}

pub fn wal_format_version() -> Int {
  return 1;
}

pub fn protocol_version() -> Int {
  return 1;
}

pub fn snapshot_format_version() -> Int {
  return 1;
}
