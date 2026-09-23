module xiom.core.wal.lsn

// WAL-local log sequence number. Mirrors xiom.core.ids.Lsn but is kept in the
// wal namespace so WAL code can evolve its ordering rules independently of the
// engine-wide id set. LSNs are strictly monotonic and never reused.

pub type WalLsn = { value: Int; } derive[Clone]

pub fn wal_lsn(v: Int) -> WalLsn {
  return WalLsn{ value: v };
}

pub fn wal_lsn_value(l: &WalLsn) -> Int {
  return l.value;
}

pub fn wal_lsn_next(l: &WalLsn) -> WalLsn {
  return WalLsn{ value: l.value + 1 };
}
