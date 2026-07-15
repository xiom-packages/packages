module xiom.vector.index.hnsw
// PENDING FIX — HNSW graph implementation has pre-existing type-checker issues with
// the borrow checker interacting with struct field access patterns (T001 errors).
// The engine defaults to flat brute-force search via consolidated engine.xi.
// See AUDIT.md for details.