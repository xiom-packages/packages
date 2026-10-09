// XIOM ORBITDB -- B-tree churn soak (delete/underflow hardening).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Adapted for the xiom.btree package surface (module name + import only;
// validation logic unchanged) from ORBITDB tests/probes/probe_btree_churn.xi
// (commit c7d4901). Randomized insert/delete/search against a flat reference
// model, plus a structural validator over the real node array. This is the
// proof vehicle for the Phase-0 delete debt (odd-order min-key invariant,
// borrow/merge).
//
// Env:
//   ORBITDB_CHURN_ORDER  btree order      (default 4; try 4 and 5)
//   ORBITDB_CHURN_OPS    operations       (default 2000)
//   ORBITDB_CHURN_N      key space        (default 256)
//   ORBITDB_CHURN_SEED   RNG seed         (default 12345)
//   ORBITDB_CHURN_QUIET  1 = only the summary line
//
// Exit: 0 = green; 1..N = first mismatch class (printed); 124 untouched.

module probe_btree_churn

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.btree;

fn rand_next(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

fn value_of(key: Int) -> Int {
  return key * 7 + 1;
}

// Structural invariants:
//  - keys strictly ascending per node
//  - leaf => no children; internal => children.len() == keys.len() + 1
//  - non-root key count in [min_keys, max_keys]; root <= max_keys
//  - all leaves at the same depth
// min_keys follows the split scheme: (order - 2) / 2.
fn validate_node(tree: &BTree, idx: Int, depth: Int, leaf_depth: &mut Int, is_root: Bool) -> Int {
  var node = tree.nodes[idx];
  var max_keys = tree.order - 1;
  var min_keys = (tree.order - 2) / 2;

  var i = 1;
  while i < node.keys.len() {
    if node.keys[i] <= node.keys[i - 1] { return 10; }
    i = i + 1;
  }

  if node.keys.len() > max_keys { return 11; }
  if !is_root {
    if node.keys.len() < min_keys { return 12; }
  }

  if node.is_leaf {
    if node.children.len() != 0 { return 13; }
    if *leaf_depth < 0 {
      *leaf_depth = depth;
    } elif depth != *leaf_depth {
      return 14;
    }
    return 0;
  }

  if node.children.len() != node.keys.len() + 1 { return 15; }

  i = 0;
  while i < node.children.len() {
    let rc = validate_node(tree, node.children[i], depth + 1, leaf_depth, false);
    if rc != 0 { return rc; }
    i = i + 1;
  }
  return 0;
}

fn validate_tree(tree: &BTree) -> Int {
  var leaf_depth = -1;
  return validate_node(tree, tree.root, 0, &mut leaf_depth, true);
}

fn show(label: Str, n: Int) {
  io.println(label + "=" + convert.int_to_string(n));
}

// Walk the same child-selection rule delete uses and print the path.
fn dump_path(tree: &BTree, key: Int) {
  var out = "path:";
  var node_idx = tree.root;
  var depth = 0;
  var done = false;
  while !done {
    var node = tree.nodes[node_idx];
    out = out + " d" + convert.int_to_string(depth)
        + ":n" + convert.int_to_string(node_idx)
        + " k" + convert.int_to_string(node.keys.len());
    if node.is_leaf {
      done = true;
    } else {
      var idx = 0;
      while idx < node.keys.len() && node.keys[idx] < key {
        idx = idx + 1;
      }
      if idx >= node.children.len() {
        done = true;
      } else {
        node_idx = node.children[idx];
        depth = depth + 1;
      }
    }
  }
  io.println(out);
  var leaf = tree.nodes[node_idx];
  var s = "leaf keys:";
  var i = 0;
  while i < leaf.keys.len() {
    s = s + " " + convert.int_to_string(leaf.keys[i]);
    i = i + 1;
  }
  io.println(s);
}

fn main() -> Int {
  let quiet = env.var_or("ORBITDB_CHURN_QUIET", "0") == "1";
  var order = 4;
  var ops = 2000;
  var n = 256;
  var seed = 12345;
  match parse.parse_int(env.var_or("ORBITDB_CHURN_ORDER", "4")) {
    Ok(v) => { if v >= 3 { order = v; } }
    Err(_) => {}
  }
  match parse.parse_int(env.var_or("ORBITDB_CHURN_OPS", "2000")) {
    Ok(v) => { if v > 0 { ops = v; } }
    Err(_) => {}
  }
  match parse.parse_int(env.var_or("ORBITDB_CHURN_N", "256")) {
    Ok(v) => { if v > 0 { n = v; } }
    Err(_) => {}
  }
  match parse.parse_int(env.var_or("ORBITDB_CHURN_SEED", "12345")) {
    Ok(v) => { seed = v; }
    Err(_) => {}
  }

  var tree = btree_new(order);
  var present = Vec[Int].new();
  var values = Vec[Int].new();
  var i = 0;
  while i < n {
    present.push(0);
    values.push(0);
    i = i + 1;
  }

  var state = seed;
  var step = 0;
  while step < ops {
    let key = rand_next(&mut state) % n;
    let action = rand_next(&mut state) % 10;

    if action < 4 {
      // insert: true iff absent
      let should_insert = present[key] == 0;
      let got = btree_insert(&mut tree, key, value_of(key));
      if got != should_insert {
        io.println("MISMATCH insert op=" + convert.int_to_string(step) + " key=" + convert.int_to_string(key));
        return 1;
      }
      if should_insert {
        present[key] = 1;
        values[key] = value_of(key);
      }
    } elif action < 7 {
      // delete: true iff present
      let should_delete = present[key] == 1;
      let got = btree_delete(&mut tree, key);
      if got != should_delete {
        io.println("MISMATCH delete op=" + convert.int_to_string(step) + " key=" + convert.int_to_string(key));
        show("model_present", present[key]);
        show("btree_size", btree_size(&tree));
        let rc = validate_tree(&tree);
        show("structure", rc);
        let again = btree_search(&tree, key);
        match again {
          Some(v) => { show("search_val", v); }
          None => { io.println("search=None"); }
        }
        dump_path(&tree, key);
        return 2;
      }
      if should_delete {
        present[key] = 0;
      }
    } else {
      // search must mirror the model
      let got = btree_search(&tree, key);
      if present[key] == 1 {
        match got {
          None => {
            io.println("MISMATCH search-missing op=" + convert.int_to_string(step) + " key=" + convert.int_to_string(key));
            return 3;
          }
          Some(v) => {
            if v != values[key] {
              io.println("MISMATCH search-value op=" + convert.int_to_string(step) + " key=" + convert.int_to_string(key));
              return 4;
            }
          }
        }
      } else {
        match got {
          Some(_) => {
            io.println("MISMATCH search-ghost op=" + convert.int_to_string(step) + " key=" + convert.int_to_string(key));
            return 5;
          }
          None => {}
        }
      }
    }

    // Periodic structural validation keeps failures attributable.
    if step % 250 == 249 {
      let rc = validate_tree(&tree);
      if rc != 0 {
        io.println("MISMATCH structure op=" + convert.int_to_string(step) + " code=" + convert.int_to_string(rc));
        return 20 + rc;
      }
    }
    step = step + 1;
  }

  // Final: size and in-order content vs the model.
  var expected = 0;
  var k = 0;
  while k < n {
    if present[k] == 1 { expected = expected + 1; }
    k = k + 1;
  }
  let size = btree_size(&tree);
  if size != expected {
    io.println("MISMATCH size got=" + convert.int_to_string(size) + " want=" + convert.int_to_string(expected));
    return 6;
  }
  let vals = btree_to_vec(&tree);
  if vals.len() != expected {
    io.println("MISMATCH vec len=" + convert.int_to_string(vals.len()) + " want=" + convert.int_to_string(expected));
    return 7;
  }
  var idx = 0;
  k = 0;
  while k < n {
    if present[k] == 1 {
      if vals[idx] != values[k] {
        io.println("MISMATCH order key=" + convert.int_to_string(k));
        return 8;
      }
      idx = idx + 1;
    }
    k = k + 1;
  }
  let rc = validate_tree(&tree);
  if rc != 0 {
    io.println("MISMATCH structure final code=" + convert.int_to_string(rc));
    return 20 + rc;
  }

  if !quiet {
    show("churn.order", order);
    show("churn.ops", ops);
    show("churn.n", n);
    show("churn.remaining", size);
  }
  io.println("churn: OK order=" + convert.int_to_string(order)
    + " ops=" + convert.int_to_string(ops)
    + " remaining=" + convert.int_to_string(size));
  return 0;
}
