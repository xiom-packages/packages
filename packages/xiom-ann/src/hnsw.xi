// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.ann.hnsw

// Navigable small-world ANN index (multi-layer HNSW, flat-array layout).
// The graph is stored as FLAT PARALLEL ARRAYS -- the bootstrap's nested
// Vec[Struct-with-Vec] graph hit 15 T001 borrow errors (AUDIT.md, "HNSW
// index"), so this implementation never borrows a nested aggregate.
//
// Layout: a fixed capacity of `hnsw_layer_capacity()` layers per node.
//   row(pos, layer) = pos * layer_capacity + layer      (into `deg`)
//   adj row base    = row(pos, layer) * m               (into `adj`)
// Live adjacency slots are `0 .. deg[row]`; unused (too-high) layers keep
// deg 0. Levels are assigned deterministically per insert (LCG seeded by the
// node's position): level 0 with probability 1 - 1/ml, then geometric.
//
// Build: for every layer the node belongs to (up to the existing top), the
// `m` nearest layer members are selected exactly and connected
// bidirectionally; a full adjacency block is pruned by replacing its
// farthest edge when the incoming edge is closer. Search: greedy descent on
// each layer above 0, then a best-first beam on layer 0 with breadth =
// max(k, ef). Results are `Vec[Neighbor]` with USER ids.

use xiom.num.float;
use xiom.vectors;

// Fixed layer capacity (levels 0..7; p(level >= l) ~ ml^-l, so > 3 is rare).
pub fn hnsw_layer_capacity() -> Int {
  return 8;
}

pub type HNSWGraph = {
  ids: Vec[Int];
  vectors: Vec[Vector];
  levels: Vec[Int];
  adj: Vec[Int];
  deg: Vec[Int];
  deleted: Vec[Bool];
  id_keys: Vec[Int];
  id_vals: Vec[Int];
  m: Int;
  ml: Float32;
  ef_construction: Int;
  build_ops: Int;
  entry: Int;
}

pub fn hnsw_new(m: Int, ml: Float32) -> HNSWGraph {
  var ids = Vec[Int].new();
  var vectors = Vec[Vector].new();
  var levels = Vec[Int].new();
  var adj = Vec[Int].new();
  var deg = Vec[Int].new();
  var deleted = Vec[Bool].new();
  var id_keys = Vec[Int].new();
  var id_vals = Vec[Int].new();
  return HNSWGraph{
    ids: ids,
    vectors: vectors,
    levels: levels,
    adj: adj,
    deg: deg,
    deleted: deleted,
    id_keys: id_keys,
    id_vals: id_vals,
    m: m,
    ml: ml,
    ef_construction: 200,
    build_ops: 0,
    entry: -1,
  };
}

// Build-work proxy: distance computations performed by the construction
// path (not persisted by the codec; it is a metric, not structure).
pub fn hnsw_build_ops(g: &HNSWGraph) -> Int {
  return g.build_ops;
}

// Distance helper for the build path (counts the work proxy).
fn dist_build(g: &mut HNSWGraph, a: Int, b: Int, metric: DistanceMetric) -> Float32 {
  g.build_ops = g.build_ops + 1;
  return vector_distance(&g.vectors[a], &g.vectors[b], metric);
}

// Build-time beam width (honoured by the construction search). Values below
// 1 are ignored; the build clamps the effective width to >= m.
pub fn hnsw_set_ef_construction(g: &mut HNSWGraph, ef: Int) {
  if ef < 1 { return; }
  g.ef_construction = ef;
}

pub fn hnsw_size(g: &HNSWGraph) -> Int {
  return g.ids.len();
}

pub fn hnsw_level_of(g: &HNSWGraph, pos: Int) -> Int {
  return g.levels[pos];
}

// Sorted id -> position map (binary search; ids are unique). Insert a new
// (id, pos) pair; returns false when the id already exists.
fn id_map_insert_raw(g: &mut HNSWGraph, id: Int, pos: Int) -> Bool {
  var lo: Int = 0;
  var hi: Int = g.id_keys.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if g.id_keys[mid] < id { lo = mid + 1; } else { hi = mid; }
  }
  if lo < g.id_keys.len() && g.id_keys[lo] == id { return false; }
  g.id_keys.push(id);
  g.id_vals.push(pos);
  var j: Int = g.id_keys.len() - 1;
  while j > lo {
    g.id_keys[j] = g.id_keys[j - 1];
    g.id_vals[j] = g.id_vals[j - 1];
    j = j - 1;
  }
  g.id_keys[lo] = id;
  g.id_vals[lo] = pos;
  return true;
}

// O(log n) id -> position lookup over the sorted map (-1 when absent).
pub fn hnsw_find_node_pos(g: &HNSWGraph, id: Int) -> Int {
  var lo: Int = 0;
  var hi: Int = g.id_keys.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if g.id_keys[mid] < id {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if lo < g.id_keys.len() && g.id_keys[lo] == id {
    return g.id_vals[lo];
  }
  return -1;
}

// Tombstone a node by id. The node stays in the graph as a routing node
// (its edges are kept) but `hnsw_search` never returns it. Idempotent:
// returns false for an unknown id or an already-deleted node.
pub fn hnsw_delete(g: &mut HNSWGraph, id: Int) -> Bool {
  var pos: Int = hnsw_find_node_pos(g, id);
  if pos < 0 { return false; }
  if g.deleted[pos] { return false; }
  g.deleted[pos] = true;
  return true;
}

// Live (non-tombstoned) node count.
pub fn hnsw_live_count(g: &HNSWGraph) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < g.deleted.len() {
    if !g.deleted[i] { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn adj_row(pos: Int, layer: Int) -> Int {
  return pos * hnsw_layer_capacity() + layer;
}

// Deterministic level assignment (LCG seeded by the node position).
fn assign_level(salt: Int, ml: Float32) -> Int {
  var s: Int = (salt + 1) * 2654435761;
  if s < 0 { s = 0 - s; }
  var den: Int = ml as Int;
  if den < 2 { den = 2; }
  var lv: Int = 0;
  var top: Int = hnsw_layer_capacity() - 1;
  while lv < top {
    s = (s * 1103515245 + 12345) % 2147483648;
    // Test HIGH bits: LCG low bits are degenerate (after s % 4 == 0 the next
    // sample is always 1 mod 4, so level >= 2 would be impossible).
    if (s / 65536) % den == 0 {
      lv = lv + 1;
    } else {
      return lv;
    }
  }
  return lv;
}

// Sorted (ascending) bounded insert of a Neighbor, capacity `cap`.
fn neighbor_push_bounded(list: &mut Vec[Neighbor], id: UInt64, distance: Float32, cap: Int) {
  list.push(Neighbor{ id: id, distance: distance });
  var pos: Int = list.len() - 1;
  while pos > 0 && list[pos - 1].distance > list[pos].distance {
    var tmp = list[pos];
    list[pos] = list[pos - 1];
    list[pos - 1] = tmp;
    pos = pos - 1;
  }
  if list.len() > cap {
    list.pop();
  }
}

// Slot of `b` in `a`'s block on `layer`, or -1.
fn edge_slot(g: &HNSWGraph, a: Int, layer: Int, b: Int) -> Int {
  var row = adj_row(a, layer);
  var i: Int = 0;
  while i < g.deg[row] {
    if g.adj[row * g.m + i] == b { return i; }
    i = i + 1;
  }
  return -1;
}

// Diversified neighbour selection (the HNSW heuristic): walk candidates in
// ascending distance to the anchor and keep up to `m` that are closer to the
// anchor than to every already-selected neighbour. Reads only; takes &mut so
// the build path can pass its mutable graph directly.
fn select_diverse(g: &mut HNSWGraph, cands: &Vec[Neighbor], m: Int, metric: DistanceMetric) -> Vec[Neighbor] {
  var selected = Vec[Neighbor].new();
  var i: Int = 0;
  while i < cands.len() && selected.len() < m {
    var c = cands[i];
    var good: Bool = true;
    var s: Int = 0;
    while s < selected.len() && good {
      var dcs = dist_build(g, c.id as Int, selected[s].id as Int, metric);
      if dcs < c.distance { good = false; }
      s = s + 1;
    }
    if good {
      selected.push(Neighbor{ id: c.id, distance: c.distance });
    }
    i = i + 1;
  }
  return selected;
}

// Add a directed edge a -> b on `layer`. A full block is pruned with the
// diversified heuristic over (existing edges + the new one).
fn add_edge(g: &mut HNSWGraph, a: Int, layer: Int, b: Int, metric: DistanceMetric) {
  if a == b { return; }
  if edge_slot(g, a, layer, b) >= 0 { return; }
  var row = adj_row(a, layer);
  if g.deg[row] < g.m {
    g.adj[row * g.m + g.deg[row]] = b;
    g.deg[row] = g.deg[row] + 1;
    return;
  }
  var cands = Vec[Neighbor].new();
  var j: Int = 0;
  while j < g.deg[row] {
    var nb = g.adj[row * g.m + j];
    var d = dist_build(g, a, nb, metric);
    cands.push(Neighbor{ id: nb as UInt64, distance: d });
    j = j + 1;
  }
  var dnb = dist_build(g, a, b, metric);
  cands.push(Neighbor{ id: b as UInt64, distance: dnb });
  var sorted = Vec[Neighbor].new();
  var q: Int = 0;
  while q < cands.len() {
    neighbor_push_bounded(&mut sorted, cands[q].id, cands[q].distance, cands.len());
    q = q + 1;
  }
  var sel = select_diverse(g, &sorted, g.m, metric);
  var w: Int = 0;
  while w < sel.len() {
    g.adj[row * g.m + w] = sel[w].id as Int;
    w = w + 1;
  }
  g.deg[row] = sel.len();
}

// Beam search + diversified selection for connecting a node on `layer`
// (read-only; the node itself may appear as its closest candidate and is
// filtered when edges are applied).
fn beam_select(g: &mut HNSWGraph, layer: Int, start: Int, ef: Int, nv: &Vector, metric: DistanceMetric) -> Vec[Neighbor] {
  var cands = search_layer_build(g, nv, start, ef, layer, metric);
  return select_diverse(g, &cands, g.m, metric);
}

// Replace `pos`'s adjacency block on `layer` with `sel` (bidirectional
// edges); the old slots are dropped (degree reset to 0).
fn apply_layer_edges(g: &mut HNSWGraph, pos: Int, layer: Int, sel: &Vec[Neighbor], metric: DistanceMetric) {
  var row = adj_row(pos, layer);
  g.deg[row] = 0;
  var c: Int = 0;
  while c < sel.len() {
    var cid = sel[c].id as Int;
    if cid != pos {
      add_edge(g, pos, layer, cid, metric);
      add_edge(g, cid, layer, pos, metric);
    }
    c = c + 1;
  }
}

// Refresh the out-edges of an existing node after its vector changed: per
// layer, beam through the OLD structure, then replace the block with the
// diversified selection for the new vector. Without this, updates keep
// stale edges and degrade recall.
fn refresh_edges(g: &mut HNSWGraph, pos: Int, metric: DistanceMetric) {
  var lv: Int = g.levels[pos];
  var nv = g.vectors[pos];
  var top: Int = g.levels[g.entry];
  var cur: Int = g.entry;
  var ef: Int = g.ef_construction;
  if ef < g.m { ef = g.m; }
  var l: Int = top;
  while l > lv {
    cur = greedy_layer_pos(g, &nv, cur, l, metric);
    l = l - 1;
  }
  var lc: Int = lv;
  if lc > top { lc = top; }
  l = lc;
  while l >= 0 {
    var sel = beam_select(g, l, cur, ef, &nv, metric);
    apply_layer_edges(g, pos, l, &sel, metric);
    if sel.len() > 0 { cur = sel[0].id as Int; }
    l = l - 1;
  }
}

// Insert a point. Re-inserting an existing id updates the vector in place,
// revives a tombstoned node, and refreshes its edges for the new vector. A
// dimension mismatch (vs the first inserted vector) is ignored; the engine
// validates dimensions before calling.
pub fn hnsw_insert(g: &mut HNSWGraph, id: Int, vec: Vector, metric: DistanceMetric) {
  if g.ids.len() > 0 {
    if vec.dimension != g.vectors[0].dimension { return; }
  }
  var existing: Int = hnsw_find_node_pos(g, id);
  if existing >= 0 {
    g.vectors[existing] = vec;
    g.deleted[existing] = false;
    refresh_edges(g, existing, metric);
    return;
  }
  var pos: Int = g.ids.len();
  g.ids.push(id);
  g.vectors.push(vec);
  g.deleted.push(false);
  id_map_insert_raw(g, id, pos);
  var lv: Int = assign_level(pos, g.ml);
  g.levels.push(lv);
  var i: Int = 0;
  while i < hnsw_layer_capacity() {
    g.deg.push(0);
    i = i + 1;
  }
  i = 0;
  while i < hnsw_layer_capacity() * g.m {
    g.adj.push(0);
    i = i + 1;
  }
  if g.entry < 0 {
    g.entry = pos;
    return;
  }
  var nv = g.vectors[pos];
  var top: Int = g.levels[g.entry];
  var cur: Int = g.entry;
  var l: Int = top;
  while l > lv {
    cur = greedy_layer_pos(g, &nv, cur, l, metric);
    l = l - 1;
  }
  var lc: Int = lv;
  if lc > top { lc = top; }
  var ef: Int = g.ef_construction;
  if ef < g.m { ef = g.m; }
  l = lc;
  while l >= 0 {
    var sel = beam_select(g, l, cur, ef, &nv, metric);
    apply_layer_edges(g, pos, l, &sel, metric);
    if sel.len() > 0 { cur = sel[0].id as Int; }
    l = l - 1;
  }
  if lv > top { g.entry = pos; }
}

// Greedy descent on one layer: walk to the local minimum from `start`.
fn greedy_layer(g: &HNSWGraph, query: &Vector, start: Int, layer: Int, metric: DistanceMetric) -> Int {
  var cur: Int = start;
  var cur_d = vector_distance(&g.vectors[cur], query, metric);
  var improved: Bool = true;
  while improved {
    improved = false;
    var row = adj_row(cur, layer);
    var j: Int = 0;
    while j < g.deg[row] {
      var nb = g.adj[row * g.m + j];
      var d = vector_distance(&g.vectors[nb], query, metric);
      if d < cur_d {
        cur = nb;
        cur_d = d;
        improved = true;
      }
      j = j + 1;
    }
  }
  return cur;
}

// Build-path greedy descent (takes the mutable graph directly).
fn greedy_layer_pos(g: &mut HNSWGraph, query: &Vector, start: Int, layer: Int, metric: DistanceMetric) -> Int {
  var cur: Int = start;
  g.build_ops = g.build_ops + 1;
  var cur_d = vector_distance(&g.vectors[cur], query, metric);
  var improved: Bool = true;
  while improved {
    improved = false;
    var row = adj_row(cur, layer);
    var j: Int = 0;
    while j < g.deg[row] {
      var nb = g.adj[row * g.m + j];
      g.build_ops = g.build_ops + 1;
      var d = vector_distance(&g.vectors[nb], query, metric);
      if d < cur_d {
        cur = nb;
        cur_d = d;
        improved = true;
      }
      j = j + 1;
    }
  }
  return cur;
}

// Beam search over one layer for construction: positions sorted by distance
// to `query`, capped at `ef`. Tombstoned nodes are included (they stay as
// routers). Build-path variant (mutable graph).
fn search_layer_build(g: &mut HNSWGraph, query: &Vector, start: Int, ef: Int, layer: Int, metric: DistanceMetric) -> Vec[Neighbor] {
  var visited = Vec[Bool].new();
  var i: Int = 0;
  while i < g.ids.len() {
    visited.push(false);
    i = i + 1;
  }
  var results = Vec[Neighbor].new();
  var frontier = Vec[Neighbor].new();
  g.build_ops = g.build_ops + 1;
  var dx = vector_distance(&g.vectors[start], query, metric);
  visited[start] = true;
  neighbor_push_bounded(&mut results, start as UInt64, dx, ef);
  neighbor_push_bounded(&mut frontier, start as UInt64, dx, ef);
  var done: Bool = false;
  while frontier.len() > 0 && !done {
    var cur = frontier[0];
    var s: Int = 1;
    while s < frontier.len() {
      frontier[s - 1] = frontier[s];
      s = s + 1;
    }
    frontier.pop();
    if results.len() >= ef {
      var worst = results[results.len() - 1].distance;
      if cur.distance > worst { done = true; }
    }
    if !done {
      var crow = adj_row(cur.id as Int, layer);
      var j: Int = 0;
      while j < g.deg[crow] {
        var npos = g.adj[crow * g.m + j];
        if !visited[npos] {
          visited[npos] = true;
          g.build_ops = g.build_ops + 1;
          var dist = vector_distance(&g.vectors[npos], query, metric);
          if results.len() < ef {
            neighbor_push_bounded(&mut results, npos as UInt64, dist, ef);
            neighbor_push_bounded(&mut frontier, npos as UInt64, dist, ef);
          } else {
            var worst2 = results[results.len() - 1].distance;
            if dist < worst2 {
              neighbor_push_bounded(&mut results, npos as UInt64, dist, ef);
              neighbor_push_bounded(&mut frontier, npos as UInt64, dist, ef);
            }
          }
        }
        j = j + 1;
      }
    }
  }
  return results;
}

// Shared search: greedy descent above layer 0, then a best-first beam on
// layer 0 into `out`. Returns the number of visited nodes.
fn hnsw_search_core(g: &HNSWGraph, query: &Vector, k: Int, ef: Int, metric: DistanceMetric, out: &mut Vec[Neighbor]) -> Int {
  if g.ids.len() == 0 { return 0; }
  if query.dimension != g.vectors[0].dimension { return 0; }
  var breadth: Int = ef;
  if breadth < k { breadth = k; }

  var start: Int = g.entry;
  var l: Int = g.levels[start];
  while l > 0 {
    start = greedy_layer(g, query, start, l, metric);
    l = l - 1;
  }

  var visited = Vec[Bool].new();
  var i: Int = 0;
  while i < g.ids.len() {
    visited.push(false);
    i = i + 1;
  }
  var seen: Int = 0;
  var results = Vec[Neighbor].new();
  var frontier = Vec[Neighbor].new();
  // NOTE: `frontier` entries carry node POSITIONS (internal expansion),
  // `results` entries carry USER ids (returned to the caller).
  var d0 = vector_distance(&g.vectors[start], query, metric);
  visited[start] = true;
  seen = seen + 1;
  // Tombstoned nodes stay in the graph as routers but are never returned.
  if !g.deleted[start] {
    neighbor_push_bounded(&mut results, g.ids[start] as UInt64, d0, breadth);
  }
  neighbor_push_bounded(&mut frontier, start as UInt64, d0, breadth);

  var done: Bool = false;
  while frontier.len() > 0 && !done {
    var cur = frontier[0];
    var s: Int = 1;
    while s < frontier.len() {
      frontier[s - 1] = frontier[s];
      s = s + 1;
    }
    frontier.pop();
    if results.len() >= breadth {
      var worst = results[results.len() - 1].distance;
      if cur.distance > worst { done = true; }
    }
    if !done {
      var cpos = cur.id as Int;
      var crow = adj_row(cpos, 0);
      var j: Int = 0;
      while j < g.deg[crow] {
        var npos = g.adj[crow * g.m + j];
        if !visited[npos] {
          visited[npos] = true;
          seen = seen + 1;
          var dist = vector_distance(&g.vectors[npos], query, metric);
          if results.len() < breadth {
            if !g.deleted[npos] {
              neighbor_push_bounded(&mut results, g.ids[npos] as UInt64, dist, breadth);
            }
            neighbor_push_bounded(&mut frontier, npos as UInt64, dist, breadth);
          } else {
            var worst2 = results[results.len() - 1].distance;
            if dist < worst2 {
              if !g.deleted[npos] {
                neighbor_push_bounded(&mut results, g.ids[npos] as UInt64, dist, breadth);
              }
              neighbor_push_bounded(&mut frontier, npos as UInt64, dist, breadth);
            }
          }
        }
        j = j + 1;
      }
    }
  }

  var limit: Int = k;
  if results.len() < k { limit = results.len(); }
  var t: Int = 0;
  while t < limit {
    out.push(Neighbor{ id: results[t].id, distance: results[t].distance });
    t = t + 1;
  }
  return seen;
}

// Copy-insert variant for callers that must keep their vector value (the
// engine feeds both the flat store and the graph from one upsert).
pub fn hnsw_insert_ref(g: &mut HNSWGraph, id: Int, vec: &Vector, metric: DistanceMetric) {
  var d: Int = vec.dimension as Int;
  var copy = Vector.new(d);
  var i: Int = 0;
  while i < d {
    copy.set(i, vec.get(i));
    i = i + 1;
  }
  hnsw_insert(g, id, copy, metric);
}

// Live count and a rebuild path: `hnsw_compact` returns a fresh graph built
// from the live nodes only (same m/ml, insertion order preserved). This is
// the tombstone compaction / edge-repair step -- deleted nodes no longer
// route or occupy slots; memory is reclaimed.
pub fn hnsw_compact(g: &HNSWGraph, metric: DistanceMetric) -> HNSWGraph {
  var fresh = hnsw_new(g.m, g.ml);
  var i: Int = 0;
  while i < g.ids.len() {
    if !g.deleted[i] {
      var v = g.vectors[i];
      hnsw_insert_ref(&mut fresh, g.ids[i], &v, metric);
    }
    i = i + 1;
  }
  return fresh;
}

// Best-first search. Returns up to k ascending-by-distance neighbors
// (`result.len() <= k`); empty graph or dimension mismatch -> empty.
pub fn hnsw_search(g: &HNSWGraph, query: &Vector, k: Int, ef: Int, metric: DistanceMetric) -> Vec[Neighbor] {
  var out = Vec[Neighbor].new();
  var seen = hnsw_search_core(g, query, k, ef, metric, &mut out);
  return out;
}

// Visited-node count of the last search shape (latency proxy for the
// harness): number of distinct nodes the descent+beam touched.
pub fn hnsw_search_visited(g: &HNSWGraph, query: &Vector, k: Int, ef: Int, metric: DistanceMetric) -> Int {
  var out = Vec[Neighbor].new();
  return hnsw_search_core(g, query, k, ef, metric, &mut out);
}

// ---- Graph codec (persistence) ----
// Deterministic word encoding (Vec[Int]) mirroring the WAL codec style:
//   [version=2, m, ml_bits(Float64), ef_construction, layer_capacity, entry,
//    node_count, per node: id, level, deleted(0|1), vector_words_len, vector
//    words..., per layer (0..capacity): degree, neighbor positions...]
// Vectors are encoded with xiom.vectors.vector_encode (dim + f32 bits).
// Decode is strict: malformed / truncated / out-of-range input returns None
// (torn-record tolerance).
pub fn hnsw_encode(g: &HNSWGraph) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(2);
  out.push(g.m);
  out.push(float.float_bits(g.ml as Float64));
  out.push(g.ef_construction);
  out.push(hnsw_layer_capacity());
  out.push(g.entry);
  out.push(g.ids.len());
  var i: Int = 0;
  while i < g.ids.len() {
    out.push(g.ids[i]);
    out.push(g.levels[i]);
    if g.deleted[i] { out.push(1); } else { out.push(0); }
    var vw = vector_encode(&g.vectors[i]);
    out.push(vw.len());
    var w: Int = 0;
    while w < vw.len() {
      out.push(vw[w]);
      w = w + 1;
    }
    var l: Int = 0;
    while l < hnsw_layer_capacity() {
      var row = adj_row(i, l);
      out.push(g.deg[row]);
      var s: Int = 0;
      while s < g.deg[row] {
        out.push(g.adj[row * g.m + s]);
        s = s + 1;
      }
      l = l + 1;
    }
    i = i + 1;
  }
  return out;
}

// Push `n` zero adjacency slots (decoder pad step; kept as its own function
// -- inlining the loop into hnsw_decode segfaulted at larger m, XVC-C-10).
fn pad_adj_slots(g: &mut HNSWGraph, n: Int) {
  var i: Int = 0;
  while i < n {
    g.adj.push(0);
    i = i + 1;
  }
}

pub fn hnsw_decode(words: &Vec[Int]) -> Option[HNSWGraph] {
  if words.len() < 7 { return None; }
  if words[0] != 2 { return None; }
  var m: Int = words[1];
  if m <= 0 { return None; }
  if m > 512 { return None; }   // sanctioned max graph degree (AnnParams)
  var ml = float.bits_to_float(words[2]) as Float32;
  if !(ml > 0.0) { return None; }
  var ef: Int = words[3];
  if ef < 1 { return None; }
  if words[4] != hnsw_layer_capacity() { return None; }
  var entry: Int = words[5];
  var count: Int = words[6];
  if count < 0 { return None; }
  if count > words.len() { return None; }   // each node needs >= 1 word
  var g = hnsw_new(m, ml);
  hnsw_set_ef_construction(&mut g, ef);
  var expected_dim: Int = -1;
  var pos: Int = 7;
  var i: Int = 0;
  while i < count {
    if pos + 3 > words.len() { return None; }
    var id: Int = words[pos];
    var level: Int = words[pos + 1];
    var del: Int = words[pos + 2];
    pos = pos + 3;
    if level < 0 || level >= hnsw_layer_capacity() { return None; }
    if del != 0 && del != 1 { return None; }
    if pos >= words.len() { return None; }
    var vw_len: Int = words[pos];
    pos = pos + 1;
    if vw_len <= 0 || pos + vw_len > words.len() { return None; }
    var vw = Vec[Int].new();
    var w: Int = 0;
    while w < vw_len {
      vw.push(words[pos + w]);
      w = w + 1;
    }
    pos = pos + vw_len;
    var vv = vector_decode(&vw);
    match vv {
      Some(v) => {
        if expected_dim < 0 {
          expected_dim = v.dimension;
        } else {
          if v.dimension != expected_dim { return None; }
        }
        g.ids.push(id);
        g.vectors.push(v);
        g.levels.push(level);
        if del == 1 { g.deleted.push(true); } else { g.deleted.push(false); }
        if !id_map_insert_raw(&mut g, id, i) { return None; }
        var l: Int = 0;
        while l < hnsw_layer_capacity() {
          if pos >= words.len() { return None; }
          var dg: Int = words[pos];
          pos = pos + 1;
          if dg < 0 || dg > m { return None; }
          if pos + dg > words.len() { return None; }
          g.deg.push(dg);
          var s: Int = 0;
          while s < dg {
            var nb: Int = words[pos + s];
            if nb < 0 || nb >= count { return None; }
            g.adj.push(nb);
            s = s + 1;
          }
          pos = pos + dg;
          pad_adj_slots(&mut g, m - dg);
          l = l + 1;
        }
      }
      None => { return None; }
    }
    i = i + 1;
  }
  if pos != words.len() { return None; }
  if count == 0 {
    g.entry = -1;
  } else {
    if entry < 0 || entry >= count { return None; }
    g.entry = entry;
  }
  return Some(g);
}
