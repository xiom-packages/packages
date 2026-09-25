// XIOM -- xiom.sgf conformance tests (24 checks)
// Greenfield package: prove the pure-XIOM xiom.sgf codec against its
// documented SGF subset grammar, value rules, error catalog, accessors and
// canonical emit.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: full games, multi-values, escapes and soft line breaks, whitespace
// normalization, nested variations, multiple game trees, case-normalized
// identifiers, empty nodes and empty documents, every error class in SPEC.md
// section 6, out-of-range accessors, duplicate properties, round-tripping,
// long sequences, deep nesting and canonical emit (spacing, escaping, trailing
// LF).
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/prop_id_is/value_is instead of `==`.

module sgf_tests
use xiom.io; use xiom.test; use xiom.sgf;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn parent_is(c: &SgfCollection, n: Int, want: Int) -> Bool {
  return sgf_node_parent(c, n) == want;
}

fn depth_is(c: &SgfCollection, n: Int, want: Int) -> Bool {
  return sgf_node_depth(c, n) == want;
}

fn start_is(c: &SgfCollection, n: Int, want: Int) -> Bool {
  return sgf_node_start(c, n) == want;
}

fn child_count_is(c: &SgfCollection, n: Int, want: Int) -> Bool {
  return sgf_node_child_count(c, n) == want;
}

fn child_is(c: &SgfCollection, n: Int, k: Int, want: Int) -> Bool {
  return sgf_node_child(c, n, k) == want;
}

fn prop_id_is(c: &SgfCollection, n: Int, p: Int, want: Str) -> Bool {
  return streq(sgf_node_prop_id(c, n, p), want);
}

fn value_is(c: &SgfCollection, n: Int, p: Int, v: Int, want: Str) -> Bool {
  return streq(sgf_node_value(c, n, p, v), want);
}

fn vstart_is(c: &SgfCollection, n: Int, p: Int, v: Int, want: Int) -> Bool {
  return sgf_node_value_start(c, n, p, v) == want;
}

fn err_is(text: Str, want: Str) -> Bool {
  let r = sgf_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn emit_of(text: Str) -> Str {
  let r = sgf_parse(text);
  match r {
    Ok(c) => { return sgf_emit(&c); },
    Err(_) => { return ""; },
  }
  return "";
}

// Structural equality of two parsed collections: roots, node links, property
// identifiers and decoded values, in order. Byte offsets are intentionally not
// compared (canonical emit moves them).
fn same_coll(ca: &SgfCollection, cb: &SgfCollection) -> Bool {
  if ca.node_parent.len() != cb.node_parent.len() { return false; }
  if ca.roots.len() != cb.roots.len() { return false; }
  var i = 0;
  while i < ca.roots.len() {
    let ra: Int = ca.roots[i];
    let rb: Int = cb.roots[i];
    if ra != rb { return false; }
    i = i + 1;
  }
  i = 0;
  while i < ca.node_parent.len() {
    let pa: Int = ca.node_parent[i];
    let pb: Int = cb.node_parent[i];
    if pa != pb { return false; }
    let da: Int = ca.node_depth[i];
    let db: Int = cb.node_depth[i];
    if da != db { return false; }
    let sa: Int = ca.node_seq[i];
    let sb: Int = cb.node_seq[i];
    if sa != sb { return false; }
    let cca: Int = ca.node_child_count[i];
    let ccb: Int = cb.node_child_count[i];
    if cca != ccb { return false; }
    var k = 0;
    while k < cca {
      let xa: Int = sgf_node_child(ca, i, k);
      let xb: Int = sgf_node_child(cb, i, k);
      if xa != xb { return false; }
      k = k + 1;
    }
    let pca: Int = ca.node_prop_count[i];
    let pcb: Int = cb.node_prop_count[i];
    if pca != pcb { return false; }
    var p = 0;
    while p < pca {
      let ida: Str = sgf_node_prop_id(ca, i, p);
      let idb: Str = sgf_node_prop_id(cb, i, p);
      if !streq(ida, idb) { return false; }
      let vca: Int = sgf_node_value_count(ca, i, p);
      let vcb: Int = sgf_node_value_count(cb, i, p);
      if vca != vcb { return false; }
      var v = 0;
      while v < vca {
        let va: Str = sgf_node_value(ca, i, p, v);
        let vb: Str = sgf_node_value(cb, i, p, v);
        if !streq(va, vb) { return false; }
        v = v + 1;
      }
      p = p + 1;
    }
    i = i + 1;
  }
  return true;
}

fn model_same(a: Str, b: Str) -> Bool {
  let ra = sgf_parse(a);
  let rb = sgf_parse(b);
  match ra {
    Ok(ca) => {
      match rb {
        Ok(cb) => { return same_coll(&ca, &cb); },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let r = sgf_parse("(;FF[4]GM[1]SZ[19];B[aa];W[bb])");
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_game_count(&c) == 1;
      if sgf_node_count(&c) != 3 { ok = false; }
      if sgf_root(&c, 0) != 0 { ok = false; }
      if !parent_is(&c, 0, -1) { ok = false; }
      if !parent_is(&c, 1, 0) { ok = false; }
      if !parent_is(&c, 2, 1) { ok = false; }
      if !depth_is(&c, 0, 0) { ok = false; }
      if !depth_is(&c, 1, 1) { ok = false; }
      if !depth_is(&c, 2, 2) { ok = false; }
      if sgf_node_seq(&c, 0) != 0 { ok = false; }
      if sgf_node_seq(&c, 1) != 1 { ok = false; }
      if sgf_node_seq(&c, 2) != 1 { ok = false; }
      if !start_is(&c, 0, 1) { ok = false; }
      if !start_is(&c, 1, 18) { ok = false; }
      if !start_is(&c, 2, 24) { ok = false; }
      if !child_count_is(&c, 0, 1) { ok = false; }
      if !child_count_is(&c, 1, 1) { ok = false; }
      if !child_count_is(&c, 2, 0) { ok = false; }
      if !child_is(&c, 0, 0, 1) { ok = false; }
      if !child_is(&c, 1, 0, 2) { ok = false; }
      if sgf_node_prop_count(&c, 0) != 3 { ok = false; }
      if !prop_id_is(&c, 0, 0, "FF") { ok = false; }
      if !prop_id_is(&c, 0, 1, "GM") { ok = false; }
      if !prop_id_is(&c, 0, 2, "SZ") { ok = false; }
      if !value_is(&c, 0, 0, 0, "4") { ok = false; }
      if !value_is(&c, 0, 1, 0, "1") { ok = false; }
      if !value_is(&c, 0, 2, 0, "19") { ok = false; }
      if !vstart_is(&c, 0, 0, 0, 4) { ok = false; }
      if !prop_id_is(&c, 1, 0, "B") { ok = false; }
      if !value_is(&c, 1, 0, 0, "aa") { ok = false; }
      if !prop_id_is(&c, 2, 0, "W") { ok = false; }
      if !value_is(&c, 2, 0, 0, "bb") { ok = false; }
      if !streq(sgf_root_prop_value(&c, 0, "FF"), "4") { ok = false; }
      if !streq(sgf_root_prop_value(&c, 0, "ff"), "4") { ok = false; }
      if !streq(sgf_prop_value(&c, 1, "b"), "aa") { ok = false; }
      if sgf_prop_find(&c, 0, "GM") != 1 { ok = false; }
      if sgf_prop_find(&c, 0, "XX") != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full game: properties, sequence links and accessors");
}

fn t2() -> TestResult {
  let r = sgf_parse("(;AB[aa][bb][cc]AW[dd])");
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_prop_count(&c, 0) == 2;
      if sgf_node_value_count(&c, 0, 0) != 3 { ok = false; }
      if sgf_node_value_count(&c, 0, 1) != 1 { ok = false; }
      if !value_is(&c, 0, 0, 0, "aa") { ok = false; }
      if !value_is(&c, 0, 0, 1, "bb") { ok = false; }
      if !value_is(&c, 0, 0, 2, "cc") { ok = false; }
      if !value_is(&c, 0, 1, 0, "dd") { ok = false; }
      if !vstart_is(&c, 0, 0, 0, 4) { ok = false; }
      if !vstart_is(&c, 0, 0, 1, 8) { ok = false; }
      if !vstart_is(&c, 0, 0, 2, 12) { ok = false; }
      if !vstart_is(&c, 0, 1, 0, 18) { ok = false; }
      if sgf_prop_find(&c, 0, "AB") != 0 { ok = false; }
      if sgf_prop_find(&c, 0, "AW") != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multi-values stay in order on one property");
}

fn t3() -> TestResult {
  let src = "(;C[a\\]b\\\\c]N[x\\:y])";
  let r = sgf_parse(src);
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_prop_count(&c, 0) == 2;
      if !prop_id_is(&c, 0, 0, "C") { ok = false; }
      if !value_is(&c, 0, 0, 0, "a]b\\c") { ok = false; }
      if !prop_id_is(&c, 0, 1, "N") { ok = false; }
      if !value_is(&c, 0, 1, 0, "x:y") { ok = false; }
      if !streq(sgf_emit(&c), "(;C[a\\]b\\\\c]N[x:y])\n") { ok = false; }
      if !model_same(src, sgf_emit(&c)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "\\] and \\\\ decode; a backslash before another byte is dropped");
}

fn t4() -> TestResult {
  let src = "(;C[a\r\nb\tc\nd]D[p\\\nq]E[r\\\r\ns])";
  let r = sgf_parse(src);
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_prop_count(&c, 0) == 3;
      if !value_is(&c, 0, 0, 0, "a b\tc d") { ok = false; }
      if !value_is(&c, 0, 1, 0, "pq") { ok = false; }
      if !value_is(&c, 0, 2, 0, "rs") { ok = false; }
      if !streq(sgf_emit(&c), "(;C[a b\tc d]D[pq]E[rs])\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "line breaks become spaces, tabs stay, backslash breaks vanish");
}

fn t5() -> TestResult {
  let src = "(;A[x](;B[y])(;C[z](;D[w])))";
  let r = sgf_parse(src);
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_game_count(&c) == 1;
      if sgf_node_count(&c) != 4 { ok = false; }
      if !parent_is(&c, 0, -1) { ok = false; }
      if !parent_is(&c, 1, 0) { ok = false; }
      if !parent_is(&c, 2, 0) { ok = false; }
      if !parent_is(&c, 3, 2) { ok = false; }
      if !depth_is(&c, 3, 2) { ok = false; }
      if sgf_node_seq(&c, 0) != 0 { ok = false; }
      if sgf_node_seq(&c, 1) != 0 { ok = false; }
      if sgf_node_seq(&c, 2) != 0 { ok = false; }
      if sgf_node_seq(&c, 3) != 0 { ok = false; }
      if !child_count_is(&c, 0, 2) { ok = false; }
      if !child_is(&c, 0, 0, 1) { ok = false; }
      if !child_is(&c, 0, 1, 2) { ok = false; }
      if !child_count_is(&c, 1, 0) { ok = false; }
      if !child_count_is(&c, 2, 1) { ok = false; }
      if !child_is(&c, 2, 0, 3) { ok = false; }
      if !start_is(&c, 1, 7) { ok = false; }
      if !start_is(&c, 2, 14) { ok = false; }
      if !start_is(&c, 3, 20) { ok = false; }
      if !value_is(&c, 3, 0, 0, "w") { ok = false; }
      if !streq(sgf_emit(&c), "(;A[x](;B[y])(;C[z](;D[w])))\n") { ok = false; }
      if !model_same(src, sgf_emit(&c)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "nested variations keep parent/child ranges and order");
}

fn t6() -> TestResult {
  let r = sgf_parse("(;GM[1])\n(;GM[2])");
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_game_count(&c) == 2;
      if sgf_node_count(&c) != 2 { ok = false; }
      if sgf_root(&c, 0) != 0 { ok = false; }
      if sgf_root(&c, 1) != 1 { ok = false; }
      if !parent_is(&c, 0, -1) { ok = false; }
      if !parent_is(&c, 1, -1) { ok = false; }
      if !depth_is(&c, 1, 0) { ok = false; }
      if sgf_node_seq(&c, 1) != 0 { ok = false; }
      if !streq(sgf_root_prop_value(&c, 1, "gm"), "2") { ok = false; }
      if !streq(sgf_emit(&c), "(;GM[1])\n(;GM[2])\n") { ok = false; }
      if !model_same("(;GM[1])  (;GM[2])", sgf_emit(&c)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a collection holds several game trees in document order");
}

fn t7() -> TestResult {
  let r = sgf_parse("(;ff[4]B[aa])");
  var ok = false;
  match r {
    Ok(c) => {
      ok = prop_id_is(&c, 0, 0, "FF");
      if !prop_id_is(&c, 0, 1, "B") { ok = false; }
      if sgf_prop_find(&c, 0, "ff") != 0 { ok = false; }
      if sgf_prop_find(&c, 0, "FF") != 0 { ok = false; }
      if sgf_prop_find(&c, 0, "Ff") != 0 { ok = false; }
      if sgf_prop_find(&c, 0, "gm") != -1 { ok = false; }
      if !streq(sgf_root_prop_value(&c, 0, "FF"), "4") { ok = false; }
      if !streq(sgf_root_prop_value(&c, 0, "ff"), "4") { ok = false; }
      if !streq(sgf_emit(&c), "(;FF[4]B[aa])\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "identifiers normalize to uppercase and look up case-insensitively");
}

fn t8() -> TestResult {
  let r = sgf_parse("(;)");
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_count(&c) == 1;
      if sgf_node_prop_count(&c, 0) != 0 { ok = false; }
      if !streq(sgf_emit(&c), "(;)\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = sgf_parse("( ; A[x] ; )");
  match r2 {
    Ok(c2) => {
      if sgf_node_count(&c2) != 2 { ok = false; }
      if sgf_node_prop_count(&c2, 1) != 0 { ok = false; }
      if !child_is(&c2, 0, 0, 1) { ok = false; }
      if sgf_node_seq(&c2, 1) != 1 { ok = false; }
      if !value_is(&c2, 0, 0, 0, "x") { ok = false; }
      if !streq(sgf_emit(&c2), "(;A[x];)\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = sgf_parse("(;A[x]B[y])");
  match r3 {
    Ok(c3) => {
      if sgf_node_prop_count(&c3, 0) != 2 { ok = false; }
      if !prop_id_is(&c3, 0, 1, "B") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty nodes are legal and whitespace separates optional tokens");
}

fn t9() -> TestResult {
  let r = sgf_parse("(;A[x])");
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_count(&c) == 1;
      if !streq(sgf_node_value(&c, 0, 0, 0), "x") { ok = false; }
      if sgf_node_value_start(&c, 0, 0, 0) != 3 { ok = false; }
      if !streq(sgf_prop_value(&c, 0, "a"), "x") { ok = false; }
      if !streq(sgf_root_prop_value(&c, 0, "a"), "x") { ok = false; }
      if sgf_node_parent(&c, -1) != -1 { ok = false; }
      if sgf_node_parent(&c, 9) != -1 { ok = false; }
      if sgf_node_depth(&c, 9) != -1 { ok = false; }
      if sgf_node_seq(&c, 9) != -1 { ok = false; }
      if sgf_node_start(&c, 9) != -1 { ok = false; }
      if sgf_node_child_count(&c, 9) != -1 { ok = false; }
      if sgf_node_child(&c, 0, 5) != -1 { ok = false; }
      if sgf_node_child(&c, -1, 0) != -1 { ok = false; }
      if sgf_node_prop_count(&c, 9) != -1 { ok = false; }
      if !streq(sgf_node_prop_id(&c, 0, 3), "") { ok = false; }
      if sgf_node_value_count(&c, 0, 3) != -1 { ok = false; }
      if !streq(sgf_node_value(&c, 0, 0, 7), "") { ok = false; }
      if sgf_node_value_start(&c, 0, 0, 7) != -1 { ok = false; }
      if sgf_node_value_start(&c, 0, -1, 0) != -1 { ok = false; }
      if sgf_root(&c, -1) != -1 { ok = false; }
      if sgf_root(&c, 2) != -1 { ok = false; }
      if sgf_prop_find(&c, -1, "A") != -1 { ok = false; }
      if !streq(sgf_prop_value(&c, 0, "Z"), "") { ok = false; }
      if !streq(sgf_root_prop_value(&c, 4, "A"), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessors are total: out-of-range reads return -1 or empty");
}

fn t10() -> TestResult {
  let r = sgf_parse("");
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_game_count(&c) == 0;
      if sgf_node_count(&c) != 0 { ok = false; }
      if !streq(sgf_emit(&c), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = sgf_parse(" \n\t ");
  match r2 {
    Ok(c2) => {
      if sgf_game_count(&c2) != 0 { ok = false; }
      if sgf_node_count(&c2) != 0 { ok = false; }
      if !streq(sgf_emit(&c2), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and whitespace-only documents parse as empty collections");
}

fn t11() -> TestResult {
  var ok = streq(emit_of("(;FF[4]\n  ;B[aa]\n)\n"), "(;FF[4];B[aa])\n");
  if !streq(emit_of("( ; A[x]   ;  B[y] )"), "(;A[x];B[y])\n") { ok = false; }
  if !streq(emit_of("(;A[x])(;A[y])"), "(;A[x])\n(;A[y])\n") { ok = false; }
  let once = emit_of("(;FF[4]C[a b];B[aa](;W[bb])(;W[cc]))");
  if !streq(emit_of(once), once) { ok = false; }
  return assert(ok, "canonical emit normalizes layout and is idempotent");
}

fn t12() -> TestResult {
  let src = "(;FF[4]C[a\\]b\\\\c\nnext];B[aa](;W[bb])(;W[cc](;B[dd];W[ee])))";
  let r = sgf_parse(src);
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_count(&c) == 6;
      if !value_is(&c, 0, 1, 0, "a]b\\c next") { ok = false; }
      if !depth_is(&c, 5, 4) { ok = false; }
      if !child_count_is(&c, 1, 2) { ok = false; }
      if !model_same(src, sgf_emit(&c)) { ok = false; }
      if !model_same(sgf_emit(&c), emit_of(sgf_emit(&c))) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse preserves the whole model");
}

fn t13() -> TestResult {
  let r = sgf_parse("(;C[a[b])");
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_value_count(&c, 0, 0) == 1;
      if !value_is(&c, 0, 0, 0, "a[b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = sgf_parse("(;C[])");
  match r2 {
    Ok(c2) => {
      if !value_is(&c2, 0, 0, 0, "") { ok = false; }
      if sgf_node_value_count(&c2, 0, 0) != 1 { ok = false; }
      if !streq(sgf_emit(&c2), "(;C[])\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = sgf_parse("(;C[a\\]])");
  match r3 {
    Ok(c3) => {
      if !value_is(&c3, 0, 0, 0, "a]") { ok = false; }
      if !streq(sgf_emit(&c3), "(;C[a\\]])\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r4 = sgf_parse("(;C[a\\\\])");
  match r4 {
    Ok(c4) => {
      if !value_is(&c4, 0, 0, 0, "a\\") { ok = false; }
      if !streq(sgf_emit(&c4), "(;C[a\\\\])\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r5 = sgf_parse("(;AB[][xy])");
  match r5 {
    Ok(c5) => {
      if sgf_node_value_count(&c5, 0, 0) != 2 { ok = false; }
      if !value_is(&c5, 0, 0, 0, "") { ok = false; }
      if !value_is(&c5, 0, 0, 1, "xy") { ok = false; }
      if !vstart_is(&c5, 0, 0, 1, 6) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "raw [, empty values and trailing escapes are exact");
}

fn t14() -> TestResult {
  var ok = err_is("(;C[abc", "sgf: unterminated value at 3");
  if !err_is("(;C[a\\", "sgf: unterminated value at 3") { ok = false; }
  if !err_is("(;C[a\\])", "sgf: unterminated value at 3") { ok = false; }
  if !err_is("(;C[", "sgf: unterminated value at 3") { ok = false; }
  return assert(ok, "an unclosed value reports its opening bracket");
}

fn t15() -> TestResult {
  var ok = err_is("()", "sgf: missing ; after ( at 1");
  if !err_is("( )", "sgf: missing ; after ( at 2") { ok = false; }
  if !err_is("((;A[x]))", "sgf: missing ; after ( at 1") { ok = false; }
  if !err_is("(", "sgf: missing ; after ( at 1") { ok = false; }
  if !err_is("([x])", "sgf: missing ; after ( at 1") { ok = false; }
  if !err_is("(;A[x](", "sgf: missing ; after ( at 7") { ok = false; }
  if !err_is("(;A[x]()", "sgf: missing ; after ( at 7") { ok = false; }
  return assert(ok, "every ( must be followed by a node semicolon");
}

fn t16() -> TestResult {
  var ok = err_is(")", "sgf: stray ) at 0");
  if !err_is("(;A[x]))", "sgf: stray ) at 7") { ok = false; }
  if !err_is("(;A[x]) )", "sgf: stray ) at 8") { ok = false; }
  return assert(ok, ") without an open tree is a stray parenthesis");
}

fn t17() -> TestResult {
  var ok = err_is("(;[]x)", "sgf: empty property id at 2");
  if !err_is("(; [aa])", "sgf: empty property id at 3") { ok = false; }
  if !err_is("(;A[x] [y])", "sgf: empty property id at 7") { ok = false; }
  return assert(ok, "a value with no identifier is an empty property id");
}

fn t18() -> TestResult {
  var ok = err_is("(;A1[x])", "sgf: bad property id char at 3");
  if !err_is("(;A [x])", "sgf: bad property id char at 3") { ok = false; }
  if !err_is("(;A)", "sgf: bad property id char at 3") { ok = false; }
  if !err_is("(;1[x])", "sgf: bad property id char at 2") { ok = false; }
  if !err_is("(;AB", "sgf: bad property id char at 4") { ok = false; }
  if !err_is("(;A.b[x])", "sgf: bad property id char at 3") { ok = false; }
  if !err_is("(;@)", "sgf: bad property id char at 2") { ok = false; }
  return assert(ok, "identifiers are letter runs immediately followed by [");
}

fn t19() -> TestResult {
  var ok = err_is("(;A[x]", "sgf: unmatched ( at 0");
  if !err_is("(;A[x](;B[y])", "sgf: unmatched ( at 0") { ok = false; }
  if !err_is("(;A[x](;B[y]", "sgf: unmatched ( at 6") { ok = false; }
  if !err_is("(;A[x](;B[y])(;C[z]", "sgf: unmatched ( at 13") { ok = false; }
  return assert(ok, "an unclosed tree reports the innermost open (");
}

fn t20() -> TestResult {
  var ok = err_is("(;A[x])x", "sgf: trailing garbage at 7");
  if !err_is("x(;A[x])", "sgf: trailing garbage at 0") { ok = false; }
  if !err_is("(;A[x])garbage", "sgf: trailing garbage at 7") { ok = false; }
  if !err_is("(;A[x](;B[y]);C[z])", "sgf: trailing garbage at 13") { ok = false; }
  if !err_is("(;A[x](;B[y])C[z])", "sgf: trailing garbage at 13") { ok = false; }
  return assert(ok, "junk where a tree boundary is expected is trailing garbage");
}

fn t21() -> TestResult {
  let r = sgf_parse("(;AB[aa]AB[bb])");
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_prop_count(&c, 0) == 2;
      if !prop_id_is(&c, 0, 1, "AB") { ok = false; }
      if sgf_prop_find(&c, 0, "AB") != 0 { ok = false; }
      if !streq(sgf_prop_value(&c, 0, "ab"), "aa") { ok = false; }
      if !value_is(&c, 0, 1, 0, "bb") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate identifiers are preserved; lookup returns the first");
}

fn t22() -> TestResult {
  let src = "(;C[a b  c])";
  let r = sgf_parse(src);
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_value_count(&c, 0, 0) == 1;
      if !value_is(&c, 0, 0, 0, "a b  c") { ok = false; }
      if !vstart_is(&c, 0, 0, 0, 3) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = sgf_parse("( ;C[a b] )");
  match r2 {
    Ok(c2) => {
      if !start_is(&c2, 0, 2) { ok = false; }
      if !vstart_is(&c2, 0, 0, 0, 4) { ok = false; }
      if !value_is(&c2, 0, 0, 0, "a b") { ok = false; }
      if !streq(sgf_emit(&c2), "(;C[a b])\n") { ok = false; }
      if !model_same("( ;C[a b] )", sgf_emit(&c2)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "spaces inside values are preserved; structural space is not");
}

fn t23() -> TestResult {
  var flat: Str = "(;A[x]";
  var k = 0;
  while k < 40 {
    flat = flat + ";N[x]";
    k = k + 1;
  }
  flat = flat + ")";
  let r = sgf_parse(flat);
  var ok = false;
  match r {
    Ok(c) => {
      ok = sgf_node_count(&c) == 41;
      if !depth_is(&c, 40, 40) { ok = false; }
      if !parent_is(&c, 40, 39) { ok = false; }
      if sgf_node_seq(&c, 40) != 1 { ok = false; }
      if sgf_node_seq(&c, 0) != 0 { ok = false; }
      var cur: Int = sgf_root(&c, 0);
      var steps = 0;
      while sgf_node_child_count(&c, cur) == 1 {
        cur = sgf_node_child(&c, cur, 0);
        steps = steps + 1;
      }
      if steps != 40 { ok = false; }
      if cur != 40 { ok = false; }
      if !streq(sgf_emit(&c), flat + "\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let deep = sgf_parse("(;A[a](;B[b](;C[c](;D[d]))))");
  match deep {
    Ok(d) => {
      if sgf_node_count(&d) != 4 { ok = false; }
      if !depth_is(&d, 3, 3) { ok = false; }
      if !parent_is(&d, 3, 2) { ok = false; }
      if !child_count_is(&d, 2, 1) { ok = false; }
      if !model_same("(;A[a](;B[b](;C[c](;D[d]))))", sgf_emit(&d)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "long sequences and deep nesting stay flat and exact");
}

fn t24() -> TestResult {
  let src = "( ;AB[aa][bb] ; W[cc] )";
  let r = sgf_parse(src);
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(sgf_emit(&c), "(;AB[aa][bb];W[cc])\n");
      if !start_is(&c, 0, 2) { ok = false; }
      if !start_is(&c, 1, 14) { ok = false; }
      if !vstart_is(&c, 0, 0, 0, 5) { ok = false; }
      if !vstart_is(&c, 0, 0, 1, 9) { ok = false; }
      if !vstart_is(&c, 1, 0, 0, 17) { ok = false; }
      if !child_is(&c, 0, 0, 1) { ok = false; }
      if !prop_id_is(&c, 1, 0, "W") { ok = false; }
      if !model_same(src, sgf_emit(&c)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "offsets point at tokens and emit drops all layout");
}

fn main() -> Int {
  io.println("=== xiom.sgf conformance tests ===");
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
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.sgf: all tests passed");
  } else {
    io.println("xiom.sgf: tests failed");
  }
  return failed;
}
