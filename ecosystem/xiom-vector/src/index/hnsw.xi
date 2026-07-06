module xiom.vector.index.hnsw

use xiom.vector.types.dense_vector;
use xiom.vector.types.neighbor;
use xiom.vector.types.metric;

// Hierarchical Navigable Small World graph — the approximate nearest neighbour
// index. This is the WORKING simplified implementation migrated from the flat
// layout: hierarchical layers, greedy descent, node-id cross-layer mapping, and
// brute-force neighbour selection within a layer. Results are expressed as
// `Neighbor` (id, distance) so the index layer never depends on the query
// layer. See docs/hnsw-design.md for the full design and production TODOs.

pub type HNSWNode = {
  id: UInt64;
  neighbors: Vec[Neighbor];
} derive[Clone]

pub fn HNSWNode.new(id: UInt64) -> HNSWNode {
  return HNSWNode{ id: id, neighbors: Vec[Neighbor].new() };
}

pub type HNSWLayer = {
  nodes: Vec[HNSWNode];
  vectors: Vec[Vector];
}

pub type HNSWGraph = {
  layers: Vec[HNSWLayer];
  max_neighbors: Int;
  ml: Float32;
}

pub fn hnsw_new(max_neighbors: Int, ml: Float32) -> HNSWGraph
  requires: max_neighbors > 0
  requires: ml > 0.0
{
  return HNSWGraph{
    layers: Vec[HNSWLayer].new();
    max_neighbors: max_neighbors;
    ml: ml;
  };
}

fn layer_new() -> HNSWLayer {
  return HNSWLayer{
    nodes: Vec[HNSWNode].new();
    vectors: Vec[Vector].new();
  };
}

fn find_node_pos(layer: &HNSWLayer, node_id: UInt64) -> Int {
  var i: Int = 0;
  while i < layer.nodes.len() {
    if layer.nodes[i].id == node_id {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn assign_level(node_count: Int, ml: Float32) -> UInt {
  var level: UInt = 0;
  var prob: Float32 = 1.0 / ml;
  var seed: UInt = node_count;
  while seed > 0 {
    seed = seed * 1103515245 + 12345;
    seed = seed % 2147483647;
    var r: Float32 = seed / 2147483647.0;
    if r > prob {
      return level;
    }
    level = level + 1;
    prob = prob / ml;
  }
  return level;
}

fn greedy_search_layer(layer: &HNSWLayer, entry_pos: Int, query: &Vector) -> Int {
  var current: Int = entry_pos;
  if current < 0 || current >= layer.nodes.len() {
    return current;
  }
  var current_dist: Float32 = vector_distance(&layer.vectors[current], query, Euclidean);
  var improved: Bool = true;
  while improved {
    improved = false;
    var node = &layer.nodes[current];
    var j: Int = 0;
    while j < node.neighbors.len() {
      var neighbor_id: UInt64 = node.neighbors[j].id;
      var neighbor_pos: Int = find_node_pos(layer, neighbor_id);
      if neighbor_pos != -1 {
        var ndist = vector_distance(&layer.vectors[neighbor_pos], query, Euclidean);
        if ndist < current_dist {
          current = neighbor_pos;
          current_dist = ndist;
          improved = true;
        }
      }
      j = j + 1;
    }
  }
  return current;
}

fn select_neighbors(layer: &HNSWLayer, vec: &Vector, max_n: Int) -> Vec[UInt64] {
  var result = Vec[UInt64].new();
  var pairs = Vec[Neighbor].new();
  var i: Int = 0;
  while i < layer.nodes.len() {
    var dist = vector_distance(&layer.vectors[i], vec, Euclidean);
    pairs.push(Neighbor{ id: layer.nodes[i].id, distance: dist });
    i = i + 1;
  }
  var sorted: Int = 0;
  while sorted < pairs.len() {
    var best: Int = sorted;
    var j: Int = sorted + 1;
    while j < pairs.len() {
      if pairs[j].distance < pairs[best].distance {
        best = j;
      }
      j = j + 1;
    }
    var tmp = pairs[sorted];
    pairs[sorted] = pairs[best];
    pairs[best] = tmp;
    sorted = sorted + 1;
  }
  var m: Int = 0;
  while m < pairs.len() && result.len() < max_n {
    result.push(pairs[m].id);
    m = m + 1;
  }
  return result;
}

fn ensure_layers(graph: &mut HNSWGraph, target_level: UInt) {
  while graph.layers.len() <= target_level {
    graph.layers.push(layer_new());
  }
}

pub fn hnsw_insert(graph: &mut HNSWGraph, id: Int, vec: Vector) -> Bool {
  var node_id: UInt64 = id;
  var total = hnsw_node_count(graph);
  var level = assign_level(total, graph.ml);
  ensure_layers(graph, level);
  if graph.layers.len() == 0 {
    return false;
  }
  if total == 0 {
    var ll: Int = graph.layers.len() - 1;
    while ll >= 0 {
      graph.layers[ll].nodes.push(HNSWNode.new(node_id));
      graph.layers[ll].vectors.push(vec);
      ll = ll - 1;
    }
    return true;
  }
  var top: Int = graph.layers.len() - 1;
  var entry_pos: Int = 0;
  var l: Int = top;
  while l > level {
    entry_pos = greedy_search_layer(&graph.layers[l], entry_pos, &vec);
    if l > 0 {
      var entry_id: UInt64 = graph.layers[l].nodes[entry_pos].id;
      entry_pos = find_node_pos(&graph.layers[l - 1], entry_id);
      if entry_pos == -1 {
        entry_pos = 0;
      }
    }
    l = l - 1;
  }
  while l >= 0 {
    var best = greedy_search_layer(&graph.layers[l], entry_pos, &vec);
    var neighbors = select_neighbors(&graph.layers[l], &vec, graph.max_neighbors);
    graph.layers[l].nodes.push(HNSWNode.new(node_id));
    graph.layers[l].vectors.push(vec);
    var new_idx: Int = graph.layers[l].nodes.len() - 1;
    var n: Int = 0;
    while n < neighbors.len() {
      graph.layers[l].nodes[new_idx].neighbors.push(Neighbor{ id: neighbors[n], distance: 0.0 });
      var tpos = find_node_pos(&graph.layers[l], neighbors[n]);
      if tpos != -1 && tpos != new_idx {
        graph.layers[l].nodes[tpos].neighbors.push(Neighbor{ id: node_id, distance: 0.0 });
      }
      n = n + 1;
    }
    if l > 0 {
      entry_pos = find_node_pos(&graph.layers[l - 1], node_id);
      if entry_pos == -1 {
        entry_pos = 0;
      }
    }
    l = l - 1;
  }
  return true;
}

pub fn hnsw_search(graph: &HNSWGraph, query: &Vector, k: Int) -> Vec[Neighbor]
  requires: k > 0
  ensures: result.len() <= k
{
  var results = Vec[Neighbor].new();
  if graph.layers.len() == 0 {
    return results;
  }
  var top: Int = graph.layers.len() - 1;
  if graph.layers[top].nodes.len() == 0 {
    return results;
  }
  var current: Int = 0;
  var l: Int = top;
  while l > 0 {
    current = greedy_search_layer(&graph.layers[l], current, query);
    var cur_id: UInt64 = graph.layers[l].nodes[current].id;
    var next_pos = find_node_pos(&graph.layers[l - 1], cur_id);
    if next_pos != -1 {
      current = next_pos;
    }
    l = l - 1;
  }
  var visited = Vec[UInt64].new();
  var candidates = Vec[Neighbor].new();
  var cur_dist = vector_distance(&graph.layers[0].vectors[current], query, Euclidean);
  candidates.push(Neighbor{ id: graph.layers[0].nodes[current].id, distance: cur_dist });
  var frontier: Int = 0;
  while frontier < candidates.len() {
    var best: Int = frontier;
    var c: Int = frontier + 1;
    while c < candidates.len() {
      if candidates[c].distance < candidates[best].distance {
        best = c;
      }
      c = c + 1;
    }
    var tmp = candidates[frontier];
    candidates[frontier] = candidates[best];
    candidates[best] = tmp;
    var cur_id: UInt64 = candidates[frontier].id;
    var cur_pos = find_node_pos(&graph.layers[0], cur_id);
    if cur_pos != -1 {
      var node = &graph.layers[0].nodes[cur_pos];
      var j: Int = 0;
      while j < node.neighbors.len() {
        var nid: UInt64 = node.neighbors[j].id;
        var already: Bool = false;
        var a: Int = 0;
        while a < visited.len() {
          if visited[a] == nid {
            already = true;
          }
          a = a + 1;
        }
        if !already {
          visited.push(nid);
          var npos = find_node_pos(&graph.layers[0], nid);
          if npos != -1 {
            var ndist = vector_distance(&graph.layers[0].vectors[npos], query, Euclidean);
            candidates.push(Neighbor{ id: nid, distance: ndist });
          }
        }
        j = j + 1;
      }
    }
    frontier = frontier + 1;
  }
  var r: Int = 0;
  while r < candidates.len() && r < k {
    results.push(candidates[r]);
    r = r + 1;
  }
  return results;
}

pub fn hnsw_layer_count(graph: &HNSWGraph) -> Int {
  return graph.layers.len();
}

pub fn hnsw_node_count(graph: &HNSWGraph) -> Int {
  var count: Int = 0;
  var i: Int = 0;
  while i < graph.layers.len() {
    count = count + graph.layers[i].nodes.len();
    i = i + 1;
  }
  return count;
}
