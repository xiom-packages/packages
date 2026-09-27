// XIOM -- xiom.merkle conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: the empty tree (root == SHA256(""), RFC 6962) and the pinned
// one/two/three/four/five/six/seven-leaf roots; SHA-256 vectors exercised
// through leaf hashing (empty leaf, "abc", and the 55/56-byte padding
// boundary); promotion (odd node carried up unchanged) at several shapes;
// the level-by-level API (sizes and node hashes, independently recomputed);
// proof round-trips for every leaf of a 7-leaf tree; tampered leaf, root,
// sibling, sibling order and leaf-index rejection; structural proof errors;
// tree-offset error paths with pinned messages; hex casing; determinism and
// leaf-order sensitivity.
//
// All inputs are built in-test. Str equality goes through
// compare.str_compare on typed locals (BUG 17 discipline); Vec[Int] reads
// are bound to typed locals before use; every UInt8 is widened with
// `(x as Int) & 0xFF`.

module merkle_tests
use xiom.io; use xiom.test; use xiom.merkle;
use xiom.string; use xiom.string.compare;

// --------------------------------------------------
//  Result and accessor helpers
// --------------------------------------------------

fn str_is(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_tree_is(r: Result[MerkleTree, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_proof_is(r: Result[MerkleProof, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

// Tree for inputs the test expects to be valid; an empty-tree fallback keeps
// a broken expectation failing loudly in the assertions that follow.
fn tree_of(data: &Vec[UInt8], offsets: &Vec[Int]) -> MerkleTree {
  let r = merkle_tree_from_leaves(data, offsets);
  if r.is_ok {
    return r.value;
  }
  var d = Vec[UInt8].new();
  var o = Vec[Int].new();
  o.push(0);
  let f = merkle_tree_from_leaves(&d, &o);
  return f.value;
}

fn internal_of(l: &Vec[UInt8], r: &Vec[UInt8]) -> Vec[UInt8] {
  let res = merkle_internal_hash(l, r);
  if res.is_ok {
    return res.value;
  }
  return Vec[UInt8].new();
}

fn lvl_hash(t: &MerkleTree, level: Int, index: Int) -> Vec[UInt8] {
  let res = merkle_level_hash(t, level, index);
  if res.is_ok {
    return res.value;
  }
  return Vec[UInt8].new();
}

fn lvl_size(t: &MerkleTree, level: Int) -> Int {
  let res = merkle_level_size(t, level);
  if res.is_ok {
    return res.value;
  }
  return -1;
}

fn proof_of(t: &MerkleTree, idx: Int) -> MerkleProof {
  let res = merkle_proof_generate(t, idx);
  if res.is_ok {
    return res.value;
  }
  var sibs = Vec[UInt8].new();
  return proof_literal(0, 1, 0, sibs);
}

fn proof_literal(li: Int, lc: Int, sc: Int, sibs: Vec[UInt8]) -> MerkleProof {
  return MerkleProof{ leaf_index: li; leaf_count: lc; sibling_count: sc; siblings: sibs };
}

fn verifies(p: &MerkleProof, leaf: &Vec[UInt8], root: &Vec[UInt8]) -> Bool {
  let res = merkle_proof_verify(p, leaf, root);
  if !res.is_ok {
    return false;
  }
  return res.value;
}

fn verify_err(p: &MerkleProof, leaf: &Vec[UInt8], root: &Vec[UInt8], want: Str) -> Bool {
  let res = merkle_proof_verify(p, leaf, root);
  if res.is_ok {
    return false;
  }
  let got = res.error;
  return str_is(got, want);
}

// --------------------------------------------------
//  Byte helpers (independent of src/merkle.xi)
// --------------------------------------------------

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn repeat_byte(n: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x = (a[i] as Int) & 0xFF;
    let y = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Copy of `v` with byte `pos` replaced.
fn set_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// Leaf slice data[start..end) as a fresh buffer.
fn leaf_of(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Offsets 0,1,...,n (one byte per leaf).
fn range_offsets(n: Int) -> Vec[Int] {
  var o = Vec[Int].new();
  var i = 0;
  while i <= n {
    o.push(i);
    i = i + 1;
  }
  return o;
}

fn hex_is(buf: Vec[UInt8], want: Str) -> Bool {
  let got = merkle_hex(&buf);
  return str_is(got, want);
}

fn root_hex_is(t: &MerkleTree, want: Str) -> Bool {
  let got = merkle_root_hex(t);
  return str_is(got, want);
}

// All sibling hashes of a proof, copied out through the public accessor.
fn sibling_bytes(p: &MerkleProof) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = merkle_proof_sibling_count(p);
  var i = 0;
  while i < n {
    let s = merkle_proof_sibling(p, i);
    if s.is_ok {
      var k = 0;
      while k < 32 {
        out.push(s.value[k]);
        k = k + 1;
      }
    }
    i = i + 1;
  }
  return out;
}

// Same proof with a different declared leaf index.
fn proof_with_index(p: &MerkleProof, new_idx: Int) -> MerkleProof {
  let lc = merkle_proof_leaf_count(p);
  let sc = merkle_proof_sibling_count(p);
  return proof_literal(new_idx, lc, sc, sibling_bytes(p));
}

// Same proof with a different declared sibling count.
fn proof_with_count(p: &MerkleProof, new_sc: Int) -> MerkleProof {
  let li = merkle_proof_leaf_index(p);
  let lc = merkle_proof_leaf_count(p);
  return proof_literal(li, lc, new_sc, sibling_bytes(p));
}

// Same proof with one sibling byte replaced.
fn proof_with_sibling_byte(p: &MerkleProof, pos: Int, b: Int) -> MerkleProof {
  let li = merkle_proof_leaf_index(p);
  let lc = merkle_proof_leaf_count(p);
  let sc = merkle_proof_sibling_count(p);
  return proof_literal(li, lc, sc, set_byte(sibling_bytes(p), pos, b));
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = merkle_hash_len() == 32;
  var empty = Vec[UInt8].new();
  if !str_is(merkle_hex(&empty), "") { ok = false; }
  var one = Vec[UInt8].new();
  one.push(0xAB as UInt8);
  if !hex_is(one, "ab") { ok = false; }
  var four = Vec[UInt8].new();
  four.push(0 as UInt8);
  four.push(15 as UInt8);
  four.push(240 as UInt8);
  four.push(255 as UInt8);
  if !hex_is(four, "000ff0ff") { ok = false; }
  return assert(ok, "hash length and hex rendering are pinned");
}

fn t2() -> TestResult {
  var data = Vec[UInt8].new();
  var offsets = Vec[Int].new();
  offsets.push(0);
  var t = tree_of(&data, &offsets);
  var ok = merkle_leaf_count(&t) == 0;
  if merkle_level_count(&t) != 0 { ok = false; }
  let root = merkle_root(&t);
  if root.len() != 32 { ok = false; }
  if !hex_is(root, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") { ok = false; }
  if !root_hex_is(&t, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") { ok = false; }
  if !err_proof_is(merkle_proof_generate(&t, 0), "merkle: empty tree has no inclusion proofs") { ok = false; }
  return assert(ok, "empty tree root is SHA256(\"\") and has no proofs");
}

fn t3() -> TestResult {
  let empty = Vec[UInt8].new();
  let heap = merkle_leaf_hash(&empty);
  var ok = heap.len() == 32;
  if !hex_is(heap, "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d") { ok = false; }
  let abc = bytes_of("abc");
  if !hex_is(merkle_leaf_hash(&abc), "609f6e36d2405585188d5cfd761f407c7cc46a7d3f314c88270469dde315fcd1") { ok = false; }
  let a55 = repeat_byte(55, 97);
  if !hex_is(merkle_leaf_hash(&a55), "2f96780fb415b287dd95897a04ef96fde6a5f5b0c771d0a1175543bc3250718e") { ok = false; }
  let a56 = repeat_byte(56, 97);
  if !hex_is(merkle_leaf_hash(&a56), "4632d4b47c0932896996fe232ae65a5af500608fabd0bdbfbb6856795eaf9d85") { ok = false; }
  return assert(ok, "leaf hash vectors: empty, abc, 55/56-byte padding boundary");
}

fn t4() -> TestResult {
  let data = bytes_of("a");
  var offs = range_offsets(1);
  var t = tree_of(&data, &offs);
  var ok = merkle_leaf_count(&t) == 1;
  if merkle_level_count(&t) != 1 { ok = false; }
  if lvl_size(&t, 0) != 1 { ok = false; }
  let la = merkle_leaf_hash(&data);
  if !bytes_equal(lvl_hash(&t, 0, 0), la) { ok = false; }
  if !root_hex_is(&t, "022a6979e6dab7aa5ae4c3e5e45f7e977112a7e63593820dbec1ec738a24f93c") { ok = false; }
  var p = proof_of(&t, 0);
  if merkle_proof_sibling_count(&p) != 0 { ok = false; }
  let root = merkle_root(&t);
  if !verifies(&p, &data, &root) { ok = false; }
  return assert(ok, "one-leaf tree: root equals the leaf hash, proof is empty");
}

fn t5() -> TestResult {
  let data = bytes_of("ab");
  var offs = range_offsets(2);
  var t = tree_of(&data, &offs);
  var ok = merkle_leaf_count(&t) == 2;
  if merkle_level_count(&t) != 2 { ok = false; }
  if lvl_size(&t, 0) != 2 { ok = false; }
  if lvl_size(&t, 1) != 1 { ok = false; }
  let leaf_a = leaf_of(&data, 0, 1);
  let leaf_b = leaf_of(&data, 1, 2);
  let la = merkle_leaf_hash(&leaf_a);
  let lb = merkle_leaf_hash(&leaf_b);
  if !bytes_equal(lvl_hash(&t, 0, 0), la) { ok = false; }
  if !bytes_equal(lvl_hash(&t, 0, 1), lb) { ok = false; }
  let manual = internal_of(&la, &lb);
  if !bytes_equal(lvl_hash(&t, 1, 0), manual) { ok = false; }
  let root = merkle_root(&t);
  if !bytes_equal(root, manual) { ok = false; }
  if !root_hex_is(&t, "b137985ff484fb600db93107c77b0365c80d78f5b429ded0fd97361d077999eb") { ok = false; }
  var p0 = proof_of(&t, 0);
  var p1 = proof_of(&t, 1);
  if merkle_proof_sibling_count(&p0) != 1 { ok = false; }
  if merkle_proof_sibling_count(&p1) != 1 { ok = false; }
  let s0 = merkle_proof_sibling(&p0, 0);
  if !s0.is_ok { ok = false; } else { if !bytes_equal(s0.value, lb) { ok = false; } }
  let s1 = merkle_proof_sibling(&p1, 0);
  if !s1.is_ok { ok = false; } else { if !bytes_equal(s1.value, la) { ok = false; } }
  if !verifies(&p0, &leaf_a, &root) { ok = false; }
  if !verifies(&p1, &leaf_b, &root) { ok = false; }
  return assert(ok, "two-leaf tree: levels and proofs pinned level by level");
}

fn t6() -> TestResult {
  let data = bytes_of("abc");
  var offs = range_offsets(3);
  var t = tree_of(&data, &offs);
  var ok = merkle_leaf_count(&t) == 3;
  if merkle_level_count(&t) != 3 { ok = false; }
  if lvl_size(&t, 0) != 3 { ok = false; }
  if lvl_size(&t, 1) != 2 { ok = false; }
  if lvl_size(&t, 2) != 1 { ok = false; }
  let leaf_a = leaf_of(&data, 0, 1);
  let leaf_b = leaf_of(&data, 1, 2);
  let leaf_c = leaf_of(&data, 2, 3);
  let la = merkle_leaf_hash(&leaf_a);
  let lb = merkle_leaf_hash(&leaf_b);
  let lc = merkle_leaf_hash(&leaf_c);
  let iab = internal_of(&la, &lb);
  if !bytes_equal(lvl_hash(&t, 1, 0), iab) { ok = false; }
  if !bytes_equal(lvl_hash(&t, 1, 1), lc) { ok = false; }
  if !hex_is(iab, "b137985ff484fb600db93107c77b0365c80d78f5b429ded0fd97361d077999eb") { ok = false; }
  let root = merkle_root(&t);
  if !bytes_equal(root, internal_of(&iab, &lc)) { ok = false; }
  if !root_hex_is(&t, "36642e73c2540ab121e3a6bf9545b0a24982cd830eb13d3cd19de3ce6c021ec1") { ok = false; }
  var p2 = proof_of(&t, 2);
  if merkle_proof_sibling_count(&p2) != 1 { ok = false; }
  let s2 = merkle_proof_sibling(&p2, 0);
  if !s2.is_ok { ok = false; } else { if !bytes_equal(s2.value, iab) { ok = false; } }
  if !verifies(&p2, &leaf_c, &root) { ok = false; }
  var p0 = proof_of(&t, 0);
  if merkle_proof_sibling_count(&p0) != 2 { ok = false; }
  if !verifies(&p0, &leaf_a, &root) { ok = false; }
  return assert(ok, "three-leaf tree: odd node promoted, not duplicated");
}

fn t7() -> TestResult {
  let data = bytes_of("abcdefg");
  var offs = range_offsets(7);
  var t = tree_of(&data, &offs);
  var ok = merkle_leaf_count(&t) == 7;
  if merkle_level_count(&t) != 4 { ok = false; }
  if lvl_size(&t, 0) != 7 { ok = false; }
  if lvl_size(&t, 1) != 4 { ok = false; }
  if lvl_size(&t, 2) != 2 { ok = false; }
  if lvl_size(&t, 3) != 1 { ok = false; }
  let leaf_a = leaf_of(&data, 0, 1);
  let leaf_b = leaf_of(&data, 1, 2);
  let leaf_c = leaf_of(&data, 2, 3);
  let leaf_d = leaf_of(&data, 3, 4);
  let leaf_e = leaf_of(&data, 4, 5);
  let leaf_f = leaf_of(&data, 5, 6);
  let leaf_g = leaf_of(&data, 6, 7);
  let la = merkle_leaf_hash(&leaf_a);
  let lb = merkle_leaf_hash(&leaf_b);
  let lc = merkle_leaf_hash(&leaf_c);
  let ld = merkle_leaf_hash(&leaf_d);
  let le = merkle_leaf_hash(&leaf_e);
  let lf = merkle_leaf_hash(&leaf_f);
  let lg = merkle_leaf_hash(&leaf_g);
  let i01 = internal_of(&la, &lb);
  let i23 = internal_of(&lc, &ld);
  let i45 = internal_of(&le, &lf);
  if !bytes_equal(lvl_hash(&t, 1, 0), i01) { ok = false; }
  if !bytes_equal(lvl_hash(&t, 1, 1), i23) { ok = false; }
  if !bytes_equal(lvl_hash(&t, 1, 2), i45) { ok = false; }
  if !bytes_equal(lvl_hash(&t, 1, 3), lg) { ok = false; }
  if !bytes_equal(lvl_hash(&t, 2, 0), internal_of(&i01, &i23)) { ok = false; }
  if !bytes_equal(lvl_hash(&t, 2, 1), internal_of(&i45, &lg)) { ok = false; }
  if !hex_is(lg, "5aeb196e83598231b45c61f3e0c5a0fda49b0d4f86a6db5f893aacccf514fa99") { ok = false; }
  if !root_hex_is(&t, "4ae191939f548d9934740b88dea2c5cb89bb8870fc4505cd79dec6bbfaaee9cb") { ok = false; }
  return assert(ok, "seven-leaf tree: levels pinned, root pinned");
}

fn t8() -> TestResult {
  let data4 = bytes_of("abcd");
  var offs4 = range_offsets(4);
  var t4 = tree_of(&data4, &offs4);
  var ok = merkle_level_count(&t4) == 3;
  if lvl_size(&t4, 0) != 4 { ok = false; }
  if lvl_size(&t4, 1) != 2 { ok = false; }
  if lvl_size(&t4, 2) != 1 { ok = false; }
  let leaf_4a = leaf_of(&data4, 0, 1);
  let leaf_4b = leaf_of(&data4, 1, 2);
  let leaf_4c = leaf_of(&data4, 2, 3);
  let leaf_4d = leaf_of(&data4, 3, 4);
  let la = merkle_leaf_hash(&leaf_4a);
  let lb = merkle_leaf_hash(&leaf_4b);
  let lc = merkle_leaf_hash(&leaf_4c);
  let ld = merkle_leaf_hash(&leaf_4d);
  let l1a = internal_of(&la, &lb);
  let l1b = internal_of(&lc, &ld);
  if !bytes_equal(lvl_hash(&t4, 1, 0), l1a) { ok = false; }
  if !bytes_equal(lvl_hash(&t4, 1, 1), l1b) { ok = false; }
  if !bytes_equal(lvl_hash(&t4, 2, 0), internal_of(&l1a, &l1b)) { ok = false; }
  if !root_hex_is(&t4, "33376a3bd63e9993708a84ddfe6c28ae58b83505dd1fed711bd924ec5a6239f0") { ok = false; }
  let data5 = bytes_of("abcde");
  var offs5 = range_offsets(5);
  var t5 = tree_of(&data5, &offs5);
  if merkle_level_count(&t5) != 4 { ok = false; }
  if lvl_size(&t5, 0) != 5 { ok = false; }
  if lvl_size(&t5, 1) != 3 { ok = false; }
  if lvl_size(&t5, 2) != 2 { ok = false; }
  if lvl_size(&t5, 3) != 1 { ok = false; }
  let leaf_e5 = leaf_of(&data5, 4, 5);
  let le5 = merkle_leaf_hash(&leaf_e5);
  if !bytes_equal(lvl_hash(&t5, 1, 2), le5) { ok = false; }
  if !bytes_equal(lvl_hash(&t5, 2, 1), le5) { ok = false; }
  if !root_hex_is(&t5, "fe14a5426fbd70c0fa73f52342afed0da0bd23c4838662ccf6b88a3070ead97b") { ok = false; }
  let data6 = bytes_of("abcdef");
  var offs6 = range_offsets(6);
  var t6 = tree_of(&data6, &offs6);
  if lvl_size(&t6, 0) != 6 { ok = false; }
  if lvl_size(&t6, 1) != 3 { ok = false; }
  if lvl_size(&t6, 2) != 2 { ok = false; }
  if !root_hex_is(&t6, "e069fc12e231ccfd4516bf1617945fb3ccd5cc8910d92d6265289f088f777fdd") { ok = false; }
  return assert(ok, "four/five/six-leaf roots and promotion chains pinned");
}

fn t9() -> TestResult {
  let data = bytes_of("ab");
  var none = Vec[Int].new();
  var ok = err_tree_is(merkle_tree_from_leaves(&data, &none), "merkle: offsets must be non-empty");
  var bad_first = Vec[Int].new();
  bad_first.push(2);
  bad_first.push(2);
  if !err_tree_is(merkle_tree_from_leaves(&data, &bad_first), "merkle: offsets[0] must be 0 (got 2)") { ok = false; }
  var down = Vec[Int].new();
  down.push(0);
  down.push(3);
  down.push(2);
  if !err_tree_is(merkle_tree_from_leaves(&data, &down), "merkle: offsets[2]=2 is below offsets[1]=3") { ok = false; }
  var short = Vec[Int].new();
  short.push(0);
  short.push(1);
  if !err_tree_is(merkle_tree_from_leaves(&data, &short), "merkle: offsets[1]=1 must equal data length 2") { ok = false; }
  var over = Vec[Int].new();
  over.push(0);
  over.push(4);
  if !err_tree_is(merkle_tree_from_leaves(&data, &over), "merkle: offsets[1]=4 must equal data length 2") { ok = false; }
  return assert(ok, "tree offset errors carry indices and values");
}

fn t10() -> TestResult {
  let data = bytes_of("a");
  var offs = Vec[Int].new();
  offs.push(0);
  offs.push(0);
  offs.push(1);
  var t = tree_of(&data, &offs);
  var ok = merkle_leaf_count(&t) == 2;
  let empty = Vec[UInt8].new();
  let l0 = merkle_leaf_hash(&empty);
  let l1 = merkle_leaf_hash(&data);
  let manual = internal_of(&l0, &l1);
  let root = merkle_root(&t);
  if !bytes_equal(root, manual) { ok = false; }
  var p0 = proof_of(&t, 0);
  var p1 = proof_of(&t, 1);
  if !verifies(&p0, &empty, &root) { ok = false; }
  if !verifies(&p1, &data, &root) { ok = false; }
  return assert(ok, "empty leaves are valid (equal consecutive offsets)");
}

fn t11() -> TestResult {
  var data = Vec[UInt8].new();
  var offsets = Vec[Int].new();
  offsets.push(0);
  var empty = tree_of(&data, &offsets);
  var ok = err_int_is(merkle_level_size(&empty, 0), "merkle: tree has no levels (empty tree)");
  if !err_bytes_is(merkle_level_hash(&empty, 0, 0), "merkle: tree has no levels (empty tree)") { ok = false; }
  let d3 = bytes_of("abc");
  var o3 = range_offsets(3);
  var t = tree_of(&d3, &o3);
  if !err_int_is(merkle_level_size(&t, 3), "merkle: level 3 out of range 0..2") { ok = false; }
  if !err_int_is(merkle_level_size(&t, -1), "merkle: level -1 out of range 0..2") { ok = false; }
  if !err_bytes_is(merkle_level_hash(&t, 3, 0), "merkle: level 3 out of range 0..2") { ok = false; }
  if !err_bytes_is(merkle_level_hash(&t, 0, 3), "merkle: node 3 out of range at level 0 (size 3)") { ok = false; }
  if !err_bytes_is(merkle_level_hash(&t, 1, 2), "merkle: node 2 out of range at level 1 (size 2)") { ok = false; }
  return assert(ok, "level accessors reject out-of-range levels and nodes");
}

fn t12() -> TestResult {
  let left31 = repeat_byte(31, 1);
  let right32 = repeat_byte(32, 2);
  var ok = err_bytes_is(merkle_internal_hash(&left31, &right32), "merkle: internal hash children must be 32 bytes each (left 31, right 32)");
  if !err_bytes_is(merkle_internal_hash(&right32, &left31), "merkle: internal hash children must be 32 bytes each (left 32, right 31)") { ok = false; }
  var a32 = repeat_byte(32, 3);
  var b32 = repeat_byte(32, 4);
  let res = merkle_internal_hash(&a32, &b32);
  let ab = internal_of(&a32, &b32);
  let ba = internal_of(&b32, &a32);
  if !res.is_ok { ok = false; } else { if !bytes_equal(res.value, ab) { ok = false; } }
  if ab.len() != 32 { ok = false; }
  if bytes_equal(ab, ba) { ok = false; }
  return assert(ok, "internal hash rejects non-32-byte children (with lengths)");
}

fn t13() -> TestResult {
  let data = bytes_of("abcdefg");
  var offs = range_offsets(7);
  var t = tree_of(&data, &offs);
  let root = merkle_root(&t);
  var want = Vec[Int].new();
  want.push(3);
  want.push(3);
  want.push(3);
  want.push(3);
  want.push(3);
  want.push(3);
  want.push(2);
  var ok = true;
  var i = 0;
  while i < 7 {
    var p = proof_of(&t, i);
    let leaf = leaf_of(&data, i, i + 1);
    let want_count = want[i];
    if merkle_proof_sibling_count(&p) != want_count { ok = false; }
    if !verifies(&p, &leaf, &root) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "inclusion proofs round-trip for all 7 leaves");
}

fn t14() -> TestResult {
  let data = bytes_of("abcde");
  var offs = range_offsets(5);
  var t = tree_of(&data, &offs);
  let root = merkle_root(&t);
  var p4 = proof_of(&t, 4);
  var ok = merkle_proof_sibling_count(&p4) == 1;
  let leaf4 = leaf_of(&data, 4, 5);
  let leaf3 = leaf_of(&data, 3, 4);
  let s0 = merkle_proof_sibling(&p4, 0);
  if !s0.is_ok { ok = false; } else { if !bytes_equal(s0.value, lvl_hash(&t, 2, 0)) { ok = false; } }
  if !verifies(&p4, &leaf4, &root) { ok = false; }
  var p3 = proof_of(&t, 3);
  if merkle_proof_sibling_count(&p3) != 3 { ok = false; }
  if !verifies(&p3, &leaf3, &root) { ok = false; }
  return assert(ok, "five-leaf promotion: leaf 4 has a single sibling");
}

fn t15() -> TestResult {
  let data = bytes_of("abcdefg");
  var offs = range_offsets(7);
  var t = tree_of(&data, &offs);
  let root = merkle_root(&t);
  var ok = true;
  var p6 = proof_of(&t, 6);
  var p5 = proof_of(&t, 5);
  if merkle_proof_sibling_count(&p6) != 2 { ok = false; }
  if merkle_proof_sibling_count(&p5) != 3 { ok = false; }
  let wrong = set_byte(leaf_of(&data, 3, 4), 0, 122);
  let leaf3 = leaf_of(&data, 3, 4);
  var p3 = proof_of(&t, 3);
  if verifies(&p3, &wrong, &root) { ok = false; }
  let res = merkle_proof_verify(&p3, &wrong, &root);
  if !res.is_ok { ok = false; } else { if res.value { ok = false; } }
  if !verifies(&p3, &leaf3, &root) { ok = false; }
  return assert(ok, "tampered leaf is rejected (Ok(false), not an error)");
}

fn t16() -> TestResult {
  let data = bytes_of("abcdefg");
  var offs = range_offsets(7);
  var t = tree_of(&data, &offs);
  let root = merkle_root(&t);
  var p3 = proof_of(&t, 3);
  let leaf = leaf_of(&data, 3, 4);
  var ok = verifies(&p3, &leaf, &root);
  let bad_root = set_byte(root, 0, 0);
  if verifies(&p3, &leaf, &bad_root) { ok = false; }
  let last_bad = set_byte(root, 31, 254);
  if verifies(&p3, &leaf, &last_bad) { ok = false; }
  let short_root = leaf_of(&root, 0, 31);
  if verifies(&p3, &leaf, &short_root) { ok = false; }
  return assert(ok, "tampered or short root is rejected");
}

fn t17() -> TestResult {
  let data = bytes_of("abcdefg");
  var offs = range_offsets(7);
  var t = tree_of(&data, &offs);
  let root = merkle_root(&t);
  var p3 = proof_of(&t, 3);
  let leaf = leaf_of(&data, 3, 4);
  var ok = verifies(&p3, &leaf, &root);
  var flipped = proof_with_sibling_byte(&p3, 0, 7);
  if verifies(&flipped, &leaf, &root) { ok = false; }
  var flipped_last = proof_with_sibling_byte(&p3, 95, 7);
  if verifies(&flipped_last, &leaf, &root) { ok = false; }
  let sibs = sibling_bytes(&p3);
  let tail = leaf_of(&sibs, 64, 96);
  let middle = leaf_of(&sibs, 32, 64);
  let head = leaf_of(&sibs, 0, 32);
  var reversed = proof_literal(3, 7, 3, cat(cat(tail, middle), head));
  if verifies(&reversed, &leaf, &root) { ok = false; }
  return assert(ok, "tampered or reordered siblings are rejected");
}

fn t18() -> TestResult {
  let data = bytes_of("abcdefg");
  var offs = range_offsets(7);
  var t = tree_of(&data, &offs);
  let root = merkle_root(&t);
  var p0 = proof_of(&t, 0);
  let leaf0 = leaf_of(&data, 0, 1);
  let leaf6 = leaf_of(&data, 6, 7);
  var wrong_idx = proof_with_index(&p0, 1);
  var ok = !verifies(&wrong_idx, &leaf0, &root);
  var p6 = proof_of(&t, 6);
  var wrong_idx6 = proof_with_index(&p6, 5);
  if verifies(&wrong_idx6, &leaf6, &root) { ok = false; }
  if !err_proof_is(merkle_proof_generate(&t, 7), "merkle: leaf index 7 out of range 0..6") { ok = false; }
  if !err_proof_is(merkle_proof_generate(&t, -1), "merkle: leaf index -1 out of range 0..6") { ok = false; }
  return assert(ok, "wrong leaf index is rejected; out-of-range generate is Err");
}

fn t19() -> TestResult {
  let empty_leaf = Vec[UInt8].new();
  let empty_root = Vec[UInt8].new();
  var p_lc0 = proof_literal(0, 0, 0, empty_leaf);
  var ok = err_bool_is(merkle_proof_verify(&p_lc0, &empty_leaf, &empty_root), "merkle: proof leaf count 0 must be positive");
  var p_bad_idx = proof_literal(5, 3, 0, Vec[UInt8].new());
  if !err_bool_is(merkle_proof_verify(&p_bad_idx, &empty_leaf, &empty_root), "merkle: proof leaf index 5 out of range 0..2") { ok = false; }
  var p_neg_sc = proof_literal(0, 1, -1, Vec[UInt8].new());
  if !err_bool_is(merkle_proof_verify(&p_neg_sc, &empty_leaf, &empty_root), "merkle: proof sibling count -1 is negative") { ok = false; }
  var p_odd_len = proof_literal(0, 1, 1, repeat_byte(33, 9));
  if !err_bool_is(merkle_proof_verify(&p_odd_len, &empty_leaf, &empty_root), "merkle: proof siblings length 33 is not a multiple of 32") { ok = false; }
  let d3 = bytes_of("abc");
  var o3 = range_offsets(3);
  var t = tree_of(&d3, &o3);
  let root = merkle_root(&t);
  var p = proof_of(&t, 0);
  var plus = proof_with_count(&p, 3);
  let leaf = leaf_of(&d3, 0, 1);
  if !verify_err(&plus, &leaf, &root, "merkle: proof sibling count 3 does not match siblings length 64") { ok = false; }
  let base = sibling_bytes(&p);
  let filler = repeat_byte(32, 0);
  let stretched = cat(base, filler);
  var extra = proof_literal(0, 3, 2, stretched);
  if !verify_err(&extra, &leaf, &root, "merkle: proof sibling count 2 does not match siblings length 96") { ok = false; }
  return assert(ok, "structural proof errors are Err with pinned messages");
}

fn t20() -> TestResult {
  let data = bytes_of("abcdefg");
  var offs = range_offsets(7);
  var t = tree_of(&data, &offs);
  var p = proof_of(&t, 0);
  var ok = merkle_proof_leaf_index(&p) == 0;
  if merkle_proof_leaf_count(&p) != 7 { ok = false; }
  if merkle_proof_sibling_count(&p) != 3 { ok = false; }
  let leaf_b20 = leaf_of(&data, 1, 2);
  let lb = merkle_leaf_hash(&leaf_b20);
  let s0 = merkle_proof_sibling(&p, 0);
  if !s0.is_ok { ok = false; } else { if !bytes_equal(s0.value, lb) { ok = false; } }
  let s2 = merkle_proof_sibling(&p, 2);
  if !s2.is_ok { ok = false; } else { if !bytes_equal(s2.value, lvl_hash(&t, 2, 1)) { ok = false; } }
  if !err_bytes_is(merkle_proof_sibling(&p, 3), "merkle: sibling index 3 out of range 0..2") { ok = false; }
  if !err_bytes_is(merkle_proof_sibling(&p, -1), "merkle: sibling index -1 out of range 0..2") { ok = false; }
  var short_p = proof_literal(0, 7, 3, repeat_byte(33, 1));
  if !err_bytes_is(merkle_proof_sibling(&short_p, 1), "merkle: sibling 1 is missing from the proof buffer") { ok = false; }
  return assert(ok, "proof accessors: siblings match the tree levels");
}

fn t21() -> TestResult {
  let data = bytes_of("abcdefg");
  var offs = range_offsets(7);
  var t1 = tree_of(&data, &offs);
  var t2 = tree_of(&data, &offs);
  let h1 = merkle_root_hex(&t1);
  let h2 = merkle_root_hex(&t2);
  var ok = str_is(h1, h2);
  if h1.len() != 64 { ok = false; }
  if !str_is(h1, "4ae191939f548d9934740b88dea2c5cb89bb8870fc4505cd79dec6bbfaaee9cb") { ok = false; }
  if str_is(h1, "4AE191939F548D9934740B88DEA2C5CB89BB8870FC4505CD79DEC6BBFAAEE9CB") { ok = false; }
  let data_sw = bytes_of("bacdefg");
  var t3 = tree_of(&data_sw, &offs);
  let h3 = merkle_root_hex(&t3);
  if str_is(h1, h3) { ok = false; }
  return assert(ok, "root hex is lowercase; roots are deterministic and order-sensitive");
}

fn t22() -> TestResult {
  var letters = "abcdefg";
  var ok = true;
  var n = 1;
  while n <= 7 {
    let data = bytes_of(string.str_slice(letters, 0, n));
    var offs = range_offsets(n);
    var t = tree_of(&data, &offs);
    if merkle_leaf_count(&t) != n { ok = false; }
    if lvl_size(&t, 0) != n { ok = false; }
    let last = merkle_level_count(&t) - 1;
    if lvl_size(&t, last) != 1 { ok = false; }
    let root = merkle_root(&t);
    if root.len() != 32 { ok = false; }
    n = n + 1;
  }
  return assert(ok, "shapes 1..7: leaf count, leaf level and single root hold");
}

fn main() -> Int {
  io.println("=== xiom.merkle conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.merkle: all tests passed");
  } else {
    io.println("xiom.merkle: tests failed");
  }
  return failed;
}
