module xiom.core.limits

// System-wide guardrails. Kept in one place so every subsystem enforces the
// same ceilings. Exposed as functions because top-level `const` support is
// limited; the values are compile-time constant in practice.

pub fn max_dimensions() -> Int {
  return 65536;
}

pub fn max_page_size() -> Int {
  return 65536;
}

pub fn default_page_size() -> Int {
  return 4096;
}

pub fn max_batch_size() -> Int {
  return 100000;
}

pub fn max_key_size() -> Int {
  return 4096;
}

pub fn max_value_size() -> Int {
  return 1048576;
}

pub fn max_segment_count() -> Int {
  return 100000;
}

pub fn default_btree_order() -> Int {
  return 64;
}

pub fn max_graph_degree() -> Int {
  return 512;
}

pub fn max_top_k() -> Int {
  return 10000;
}
