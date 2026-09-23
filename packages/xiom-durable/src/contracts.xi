module xiom.durable.contracts

// Shared predicate helpers used across storage, WAL, config, and recovery.
// These encode the engine's correctness rules as reusable boolean checks so
// that `requires:` / `ensures:` clauses and runtime validation stay in sync.

pub fn is_power_of_two(n: Int) -> Bool {
  if n <= 0 { return false; }
  var m = n;
  while m > 1 {
    if m % 2 != 0 { return false; }
    m = m / 2;
  }
  return true;
}

// A valid page size is a power of two between 512 and 65536 bytes.
pub fn is_valid_page_size(size: Int) -> Bool {
  if size < 512 { return false; }
  if size > 65536 { return false; }
  return is_power_of_two(size);
}

// Vector dimensionality must be in [1, 65536].
pub fn is_valid_dimension(dim: Int) -> Bool {
  return dim >= 1 && dim <= 65536;
}

// Keys must be non-empty and no larger than the max key size.
pub fn is_valid_key_size(size: Int) -> Bool {
  return size >= 1 && size <= 4096;
}

// top_k requests must be in [1, max_top_k].
pub fn is_valid_top_k(k: Int) -> Bool {
  return k >= 1 && k <= 10000;
}

// LSNs are strictly monotonic: the next record must advance past the previous.
pub fn is_valid_lsn_ordering(prev: Int, next: Int) -> Bool {
  return next > prev;
}

// Non-decreasing order check used to validate sorted key runs / merge inputs.
pub fn is_sorted_ints(v: &Vec[Int]) -> Bool {
  var i = 1;
  while i < v.len() {
    if v[i] < v[i - 1] { return false; }
    i = i + 1;
  }
  return true;
}
