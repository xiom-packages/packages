module xiom.db.btree_stdlib
use xiom.collections.BTreeMap;
use xiom.math;

pub type BTree = BTreeMap[Int, Int];

pub fn btree_new(order: Int) -> BTree {
  return BTreeMap.new[Int, Int]();
}

pub fn btree_insert(tree: &mut BTree, key: Int, value: Int) -> Bool {
  tree.insert(key, value);
  return true;
}

pub fn btree_search(tree: &BTree, key: Int) -> Option[Int] {
  return tree.get(&key);
}

pub fn btree_delete(tree: &mut BTree, key: Int) -> Bool {
  return tree.remove(&key);
}

pub fn btree_range_query(tree: &BTree, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  var results = Vec[Int].new();
  tree.range(low, high, &mut |k: Int, v: Int| {
    results.push(v);
    return true;
  });
  return results;
}

pub fn btree_size(tree: &BTree) -> Int {
  return tree.len();
}

pub fn btree_min(tree: &BTree) -> Option[Int] {
  return tree.first();
}

pub fn btree_max(tree: &BTree) -> Option[Int] {
  return tree.last();
}

pub fn btree_to_vec(tree: &BTree) -> Vec[Int] {
  var results = Vec[Int].new();
  tree.iter(&mut |k: Int, v: Int| {
    results.push(v);
    return true;
  });
  return results;
}
