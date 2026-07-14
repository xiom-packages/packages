module xiom.vector.types.neighbor

// A (id, distance) pair — the low-level result edge used inside index
// implementations (HNSW candidate lists, flat scans) and graph adjacency.
// The query layer maps this onto the public `SearchResult`.

pub type Neighbor = {
  id: UInt64;
  distance: Float32;
} derive[Clone]

pub fn neighbor_new(id: UInt64, distance: Float32) -> Neighbor {
  return Neighbor{ id: id, distance: distance };
}

pub fn neighbor_closer(a: &Neighbor, b: &Neighbor) -> Bool {
  return a.distance < b.distance;
}
