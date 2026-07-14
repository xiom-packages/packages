module xiom.vector.query.topk_heap

use xiom.vector.types.neighbor;

// Bounded top-K collector. Maintains at most `capacity` neighbours in ascending
// distance order using the same insertion-sort-then-truncate strategy as the
// brute-force scan. The core invariant — items.len() <= capacity after every
// push — is what lets the query layer guarantee `search` never returns more
// than the requested k.

pub type TopKHeap = {
  capacity: Int;
  items: Vec[Neighbor];
}

pub fn topk_new(capacity: Int) -> TopKHeap
  requires: capacity > 0
  ensures: result.items.len() == 0
{
  var items = Vec[Neighbor].new();
  return TopKHeap{ capacity: capacity, items: items };
}

pub fn topk_push(h: &mut TopKHeap, n: Neighbor)
  requires: h.capacity > 0
  ensures: h.items.len() <= h.capacity
{
  h.items.push(n);
  var pos: Int = h.items.len() - 1;
  while pos > 0 && h.items[pos - 1].distance > h.items[pos].distance {
    var tmp = h.items[pos];
    h.items[pos] = h.items[pos - 1];
    h.items[pos - 1] = tmp;
    pos = pos - 1;
  }
  if h.items.len() > h.capacity {
    h.items.pop();
  }
}

pub fn topk_len(h: &TopKHeap) -> Int {
  return h.items.len();
}

pub fn topk_is_full(h: &TopKHeap) -> Bool {
  return h.items.len() >= h.capacity;
}

// The current worst (largest-distance) member, i.e. the eviction candidate.
pub fn topk_worst(h: &TopKHeap) -> Option[Neighbor] {
  if h.items.len() == 0 {
    return None;
  }
  return Some(h.items[h.items.len() - 1]);
}
