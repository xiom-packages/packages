// XIOM -- xiom.chaincore conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.chaincore model against its documented
// append validation, fork choice, reorg undo/redo, orphan promotion,
// finality tracking and structural invariants.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: genesis defaults, append and work accumulation, header
// accessors, side branches, the exact append error catalog, duplicate
// detection (inserted and parked), cumulative-work fork choice, the
// deterministic lower-tag tie-break, reorg bookkeeping and multi-block
// undo/redo, orphan parking, parent-arrival promotion, deep orphan cascades,
// invalid-orphan drop, status codes, transaction attribution and its error
// catalog, global transaction-id uniqueness, finality depth, finalized
// height/is_final, the invariant bitmask (clean state plus three injected
// corruptions) and the pinned genesis layout and unknown-tag sentinels.
//
// Harness style mirrors xiom.hello / xiom.transaction: one fn tN() ->
// TestResult per check, called directly from main; main prints [PASS]/[FAIL]
// and returns the failure count. All Str equality goes through str_compare
// (BUG 17 discipline: `==` on Str values read from a Vec lowers to a pointer
// comparison). Store-taking helpers take `&mut` so no `&local` read call is
// followed by a `&mut local` call inside one body (advisory E001).

module chaincore_tests
use xiom.io; use xiom.test;
use xiom.string.compare;
use xiom.chaincore;

// --------------------------------------------------
//  Fixtures and helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Fresh store: genesis tag 1 with opaque state root 1000.
fn mk() -> ChainStore {
  return chain_new(1000);
}

// Append and return the status (0 orphan, 1 side, 2 best chain), or -1 on
// rejection.
fn ap(c: &mut ChainStore, tag: Int, parent: Int, height: Int, work: Int, root: Int) -> Int {
  let r = chain_append(c, tag, chain_header(parent, height, work, root));
  match r {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

// Append and compare the status against `want`.
fn ap_is(c: &mut ChainStore, tag: Int, parent: Int, height: Int, work: Int, root: Int, want: Int) -> Bool {
  return ap(c, tag, parent, height, work, root) == want;
}

// Append and return the exact error message, or "" when accepted.
fn ap_err(c: &mut ChainStore, tag: Int, parent: Int, height: Int, work: Int, root: Int) -> Str {
  let r = chain_append(c, tag, chain_header(parent, height, work, root));
  match r {
    Ok(_) => { return ""; },
    Err(e) => { return e; },
  }
  return "";
}

// Append and compare the rejection message against `want`.
fn ap_err_is(c: &mut ChainStore, tag: Int, parent: Int, height: Int, work: Int, root: Int, want: Str) -> Bool {
  return streq(ap_err(c, tag, parent, height, work, root), want);
}

// Add a transaction; true on Ok.
fn tx_add(c: &mut ChainStore, block_tag: Int, tx_id: Int, fee: Int) -> Bool {
  let r = chain_add_tx(c, block_tag, tx_id, fee);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

// Add a transaction and compare the rejection message against `want`.
fn tx_err_is(c: &mut ChainStore, block_tag: Int, tx_id: Int, fee: Int, want: Str) -> Bool {
  let r = chain_add_tx(c, block_tag, tx_id, fee);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  var c = mk();
  var ok = chain_best_tag(&mut c) == 1;
  if chain_genesis_tag() != 1 { ok = false; }
  if chain_best_height(&mut c) != 0 { ok = false; }
  if chain_best_work(&mut c) != 1 { ok = false; }
  if chain_block_count(&mut c) != 1 { ok = false; }
  if chain_best_chain_len(&mut c) != 1 { ok = false; }
  if chain_orphan_count(&mut c) != 0 { ok = false; }
  if chain_tx_count(&mut c) != 0 { ok = false; }
  if chain_reorg_events(&mut c) != 0 { ok = false; }
  if chain_finality_depth(&mut c) != chain_default_finality_depth() { ok = false; }
  if !chain_known(&mut c, 1) { ok = false; }
  if chain_known(&mut c, 2) { ok = false; }
  if !chain_on_best(&mut c, 1) { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "chain_new seeds only genesis and a clean default state");
}

fn t2() -> TestResult {
  var c = mk();
  var ok = ap_is(&mut c, 2, 1, 1, 3, 200, chain_status_added());
  if chain_block_count(&mut c) != 2 { ok = false; }
  if chain_block_work(&mut c, 2) != 4 { ok = false; }
  if chain_block_own_work(&mut c, 2) != 3 { ok = false; }
  if chain_best_tag(&mut c) != 2 { ok = false; }
  if chain_best_height(&mut c) != 1 { ok = false; }
  if chain_best_work(&mut c) != 4 { ok = false; }
  if !chain_on_best(&mut c, 2) { ok = false; }
  if !chain_known(&mut c, 2) { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "append extends the chain and accumulates work");
}

fn t3() -> TestResult {
  var c = mk();
  ap(&mut c, 5, 1, 1, 2, 555);
  var ok = chain_block_parent(&mut c, 5) == 1;
  if chain_block_height(&mut c, 5) != 1 { ok = false; }
  if chain_block_root(&mut c, 5) != 555 { ok = false; }
  if chain_block_own_work(&mut c, 5) != 2 { ok = false; }
  if chain_block_work(&mut c, 5) != 3 { ok = false; }
  if chain_tag_at(&mut c, 1) != 5 { ok = false; }
  if chain_tag_at(&mut c, 9) != -1 { ok = false; }
  if chain_tag_at(&mut c, -1) != -1 { ok = false; }
  return assert(ok, "block accessors expose the declared header fields");
}

fn t4() -> TestResult {
  var c = mk();
  ap(&mut c, 2, 1, 1, 5, 200);
  var s = ap(&mut c, 3, 1, 1, 4, 300);
  var ok = s == chain_status_side();
  if chain_best_tag(&mut c) != 2 { ok = false; }
  if chain_on_best(&mut c, 3) { ok = false; }
  if !chain_known(&mut c, 3) { ok = false; }
  if chain_reorg_events(&mut c) != 0 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "a lighter fork attaches as a side branch");
}

fn t5() -> TestResult {
  var c = mk();
  ap(&mut c, 2, 1, 1, 1, 20);
  var ok = ap_err_is(&mut c, 3, 2, 3, 1, 30, "chaincore: height must be parent height + 1");
  if chain_known(&mut c, 3) { ok = false; }
  if chain_orphan_count(&mut c) != 0 { ok = false; }
  if chain_block_count(&mut c) != 2 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "height must be exactly parent height + 1");
}

fn t6() -> TestResult {
  var c = mk();
  var ok = ap_err_is(&mut c, 0, 1, 1, 1, 1, "chaincore: tag must be positive");
  if !ap_err_is(&mut c, -7, 1, 1, 1, 1, "chaincore: tag must be positive") { ok = false; }
  if !ap_err_is(&mut c, 1, 1, 1, 1, 1, "chaincore: genesis tag is reserved") { ok = false; }
  if !ap_err_is(&mut c, 2, 0, 1, 1, 1, "chaincore: parent tag must be positive") { ok = false; }
  if !ap_err_is(&mut c, 2, 2, 1, 1, 1, "chaincore: block cannot parent itself") { ok = false; }
  if !ap_err_is(&mut c, 2, 1, 0, 1, 1, "chaincore: height must be positive") { ok = false; }
  if !ap_err_is(&mut c, 2, 1, 1, 0, 1, "chaincore: work must be positive") { ok = false; }
  if !ap_err_is(&mut c, 2, 1, 1, -3, 1, "chaincore: work must be positive") { ok = false; }
  if chain_block_count(&mut c) != 1 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "the append error catalog pins every structural rejection");
}

fn t7() -> TestResult {
  var c = mk();
  ap(&mut c, 2, 1, 1, 1, 20);
  var ok = ap_err_is(&mut c, 2, 1, 1, 1, 20, "chaincore: duplicate block tag: 2");
  if !ap_err_is(&mut c, 2, 1, 2, 5, 99, "chaincore: duplicate block tag: 2") { ok = false; }
  ap(&mut c, 9, 8, 2, 1, 90);
  if chain_orphan_count(&mut c) != 1 { ok = false; }
  if !ap_err_is(&mut c, 9, 1, 1, 1, 90, "chaincore: duplicate block tag: 9") { ok = false; }
  if chain_block_count(&mut c) != 2 { ok = false; }
  if chain_orphan_count(&mut c) != 1 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "duplicate inserted and parked tags are rejected");
}

fn t8() -> TestResult {
  var c = mk();
  ap(&mut c, 2, 1, 1, 1, 20);
  ap(&mut c, 3, 2, 2, 1, 30);
  ap(&mut c, 20, 1, 1, 1, 200);
  var ok = chain_best_tag(&mut c) == 3;
  if ap(&mut c, 21, 20, 2, 2, 210) != chain_status_added() { ok = false; }
  if chain_best_tag(&mut c) != 21 { ok = false; }
  if chain_on_best(&mut c, 3) { ok = false; }
  if chain_on_best(&mut c, 2) { ok = false; }
  if !chain_on_best(&mut c, 20) { ok = false; }
  if !chain_on_best(&mut c, 21) { ok = false; }
  if chain_reorg_events(&mut c) != 1 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "fork choice follows the heaviest cumulative work");
}

fn t9() -> TestResult {
  var c = mk();
  ap(&mut c, 30, 1, 1, 2, 300);
  ap(&mut c, 10, 1, 1, 2, 100);
  var ok = chain_best_tag(&mut c) == 10;
  if chain_reorg_events(&mut c) != 1 { ok = false; }
  ap(&mut c, 11, 10, 2, 3, 110);
  if chain_best_tag(&mut c) != 11 { ok = false; }
  if chain_reorg_events(&mut c) != 1 { ok = false; }
  if !chain_on_best(&mut c, 10) { ok = false; }
  if chain_on_best(&mut c, 30) { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "equal work resolves to the lower tag and extensions are silent");
}

fn t10() -> TestResult {
  var c = mk();
  ap(&mut c, 10, 1, 1, 1, 100);
  ap(&mut c, 20, 1, 1, 1, 200);
  ap(&mut c, 21, 20, 2, 2, 210);
  var ok = chain_reorg_events(&mut c) == 1;
  if chain_reorg_state(&mut c) != 1 { ok = false; }
  if chain_reorg_common(&mut c) != 1 { ok = false; }
  if chain_reorg_old_tag(&mut c) != 10 { ok = false; }
  if chain_reorg_new_tag(&mut c) != 21 { ok = false; }
  if chain_reorg_undo_count(&mut c) != 1 { ok = false; }
  if chain_reorg_redo_count(&mut c) != 2 { ok = false; }
  if chain_reorg_undo_tag(&mut c, 0) != 10 { ok = false; }
  if chain_reorg_redo_tag(&mut c, 0) != 20 { ok = false; }
  if chain_reorg_redo_tag(&mut c, 1) != 21 { ok = false; }
  if chain_reorg_undo_tag(&mut c, 3) != -1 { ok = false; }
  if chain_reorg_redo_tag(&mut c, -1) != -1 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "a branch switch records ancestor, undo and redo");
}

fn t11() -> TestResult {
  var c = mk();
  ap(&mut c, 10, 1, 1, 1, 100);
  ap(&mut c, 20, 1, 1, 1, 200);
  ap(&mut c, 21, 20, 2, 2, 210);
  var ok = chain_best_tag(&mut c) == 21;
  if !chain_reorg_undo(&mut c) { ok = false; }
  if chain_best_tag(&mut c) != 10 { ok = false; }
  if chain_reorg_state(&mut c) != 2 { ok = false; }
  if chain_on_best(&mut c, 21) { ok = false; }
  if chain_reorg_undo(&mut c) { ok = false; }
  if !chain_reorg_redo(&mut c) { ok = false; }
  if chain_best_tag(&mut c) != 21 { ok = false; }
  if chain_reorg_state(&mut c) != 1 { ok = false; }
  if chain_reorg_redo(&mut c) { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "reorg undo and redo restore each best tip exactly once");
}

fn t12() -> TestResult {
  var c = mk();
  ap(&mut c, 10, 1, 1, 1, 100);
  ap(&mut c, 11, 10, 2, 1, 110);
  ap(&mut c, 20, 1, 1, 1, 200);
  ap(&mut c, 21, 20, 2, 1, 210);
  ap(&mut c, 22, 21, 3, 1, 220);
  var ok = chain_best_tag(&mut c) == 22;
  if chain_reorg_events(&mut c) != 1 { ok = false; }
  if chain_reorg_common(&mut c) != 1 { ok = false; }
  if chain_reorg_undo_count(&mut c) != 2 { ok = false; }
  if chain_reorg_redo_count(&mut c) != 3 { ok = false; }
  if chain_reorg_undo_tag(&mut c, 0) != 11 { ok = false; }
  if chain_reorg_undo_tag(&mut c, 1) != 10 { ok = false; }
  if chain_reorg_redo_tag(&mut c, 0) != 20 { ok = false; }
  if chain_reorg_redo_tag(&mut c, 1) != 21 { ok = false; }
  if chain_reorg_redo_tag(&mut c, 2) != 22 { ok = false; }
  if chain_best_chain_len(&mut c) != 4 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "a two-for-three reorg records both suffixes in order");
}

fn t13() -> TestResult {
  var c = mk();
  var s = ap(&mut c, 7, 6, 2, 1, 70);
  var ok = s == chain_status_orphan();
  if chain_known(&mut c, 7) { ok = false; }
  if chain_orphan_count(&mut c) != 1 { ok = false; }
  if chain_orphan_tag(&mut c, 0) != 7 { ok = false; }
  if chain_orphan_parent(&mut c, 0) != 6 { ok = false; }
  if chain_orphan_height(&mut c, 0) != 2 { ok = false; }
  if chain_orphan_work(&mut c, 0) != 1 { ok = false; }
  if chain_orphan_root(&mut c, 0) != 70 { ok = false; }
  if chain_orphan_tag(&mut c, 5) != -1 { ok = false; }
  if chain_orphan_parent(&mut c, -1) != -1 { ok = false; }
  if chain_orphan_height(&mut c, 5) != -1 { ok = false; }
  if chain_orphan_work(&mut c, 5) != -1 { ok = false; }
  if chain_orphan_root(&mut c, 5) != -1 { ok = false; }
  if chain_best_tag(&mut c) != 1 { ok = false; }
  if chain_last_promoted(&mut c) != 0 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "an unknown parent parks the block in the orphan pool");
}

fn t14() -> TestResult {
  var c = mk();
  ap(&mut c, 7, 6, 2, 1, 70);
  var s = ap(&mut c, 6, 1, 1, 1, 60);
  var ok = s == chain_status_added();
  if chain_last_promoted(&mut c) != 1 { ok = false; }
  if chain_orphan_count(&mut c) != 0 { ok = false; }
  if !chain_known(&mut c, 7) { ok = false; }
  if chain_block_height(&mut c, 7) != 2 { ok = false; }
  if chain_block_work(&mut c, 7) != 3 { ok = false; }
  if chain_best_tag(&mut c) != 7 { ok = false; }
  if !chain_on_best(&mut c, 6) { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "parent arrival promotes a parked child");
}

fn t15() -> TestResult {
  var c = mk();
  ap(&mut c, 5, 4, 3, 1, 50);
  ap(&mut c, 4, 2, 2, 1, 40);
  var ok = chain_orphan_count(&mut c) == 2;
  if ap(&mut c, 2, 1, 1, 1, 20) != chain_status_added() { ok = false; }
  if chain_last_promoted(&mut c) != 2 { ok = false; }
  if chain_orphan_count(&mut c) != 0 { ok = false; }
  if !chain_known(&mut c, 4) { ok = false; }
  if !chain_known(&mut c, 5) { ok = false; }
  if chain_block_height(&mut c, 5) != 3 { ok = false; }
  if chain_block_work(&mut c, 5) != 4 { ok = false; }
  if chain_best_tag(&mut c) != 5 { ok = false; }
  if chain_best_chain_len(&mut c) != 4 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "a deep orphan chain promotes across repeated passes");
}

fn t16() -> TestResult {
  var c = mk();
  ap(&mut c, 9, 2, 7, 1, 90);
  var s = ap(&mut c, 2, 1, 1, 1, 20);
  var ok = s == chain_status_added();
  if chain_last_promoted(&mut c) != 0 { ok = false; }
  if chain_orphan_count(&mut c) != 0 { ok = false; }
  if chain_known(&mut c, 9) { ok = false; }
  if chain_best_tag(&mut c) != 2 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "an orphan that fails the height rule is dropped at promotion");
}

fn t17() -> TestResult {
  var c = mk();
  var ok = chain_status_added() == 2;
  if chain_status_side() != 1 { ok = false; }
  if chain_status_orphan() != 0 { ok = false; }
  if ap(&mut c, 2, 1, 1, 1, 20) != chain_status_added() { ok = false; }
  if ap(&mut c, 3, 2, 2, 1, 30) != chain_status_added() { ok = false; }
  if ap(&mut c, 4, 1, 1, 1, 40) != chain_status_side() { ok = false; }
  if ap(&mut c, 5, 9, 1, 1, 50) != chain_status_orphan() { ok = false; }
  if chain_best_chain_len(&mut c) != 3 { ok = false; }
  if chain_best_height(&mut c) != 2 { ok = false; }
  if chain_block_count(&mut c) != 4 { ok = false; }
  if chain_orphan_count(&mut c) != 1 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "statuses distinguish best chain, side branch and orphan");
}

fn t18() -> TestResult {
  var c = mk();
  ap(&mut c, 2, 1, 1, 1, 20);
  var ok = tx_add(&mut c, 2, 100, 7);
  if !tx_add(&mut c, 2, 101, 3) { ok = false; }
  if chain_tx_count(&mut c) != 2 { ok = false; }
  if chain_block_tx_count(&mut c, 2) != 2 { ok = false; }
  if chain_block_fees(&mut c, 2) != 10 { ok = false; }
  if chain_total_fees(&mut c) != 10 { ok = false; }
  if chain_tx_id_at(&mut c, 0) != 100 { ok = false; }
  if chain_tx_block_at(&mut c, 0) != 2 { ok = false; }
  if chain_tx_fee_at(&mut c, 0) != 7 { ok = false; }
  if chain_tx_fee_at(&mut c, 1) != 3 { ok = false; }
  if chain_tx_id_at(&mut c, 9) != -1 { ok = false; }
  if chain_tx_block_at(&mut c, -1) != -1 { ok = false; }
  if chain_tx_fee_at(&mut c, 9) != -1 { ok = false; }
  if chain_block_tx_count(&mut c, 3) != 0 { ok = false; }
  if chain_block_fees(&mut c, 3) != 0 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "transaction records are attributed to their block");
}

fn t19() -> TestResult {
  var c = mk();
  ap(&mut c, 2, 1, 1, 1, 20);
  var ok = tx_err_is(&mut c, 77, 1, 1, "chaincore: unknown block: 77");
  if !tx_err_is(&mut c, 2, 1, -5, "chaincore: fee must be non-negative") { ok = false; }
  if !tx_add(&mut c, 2, 100, 4) { ok = false; }
  if !tx_err_is(&mut c, 2, 100, 1, "chaincore: duplicate transaction id: 100") { ok = false; }
  if chain_tx_count(&mut c) != 1 { ok = false; }
  ap(&mut c, 8, 7, 1, 1, 80);
  if !tx_err_is(&mut c, 8, 200, 1, "chaincore: unknown block: 8") { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "the transaction error catalog pins every rejection");
}

fn t20() -> TestResult {
  var c = mk();
  ap(&mut c, 2, 1, 1, 1, 20);
  ap(&mut c, 3, 2, 2, 1, 30);
  var ok = tx_add(&mut c, 2, 500, 2);
  if tx_add(&mut c, 3, 500, 2) { ok = false; }
  if chain_tx_count(&mut c) != 1 { ok = false; }
  if chain_block_tx_count(&mut c, 3) != 0 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "transaction ids are unique across the whole store");
}

fn t21() -> TestResult {
  var c = mk();
  var ok = chain_finality_depth(&mut c) == 6;
  if !chain_set_finality_depth(&mut c, 2) { ok = false; }
  if chain_finality_depth(&mut c) != 2 { ok = false; }
  if chain_set_finality_depth(&mut c, -1) { ok = false; }
  if chain_finality_depth(&mut c) != 2 { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "finality depth is configurable and rejects negatives");
}

fn t22() -> TestResult {
  var c = mk();
  ap(&mut c, 2, 1, 1, 1, 20);
  ap(&mut c, 3, 2, 2, 1, 30);
  ap(&mut c, 4, 3, 3, 1, 40);
  ap(&mut c, 5, 4, 4, 1, 50);
  var ok = chain_best_height(&mut c) == 4;
  chain_set_finality_depth(&mut c, 2);
  if chain_finalized_height(&mut c) != 2 { ok = false; }
  if !chain_is_final(&mut c, 1) { ok = false; }
  if !chain_is_final(&mut c, 3) { ok = false; }
  if chain_is_final(&mut c, 4) { ok = false; }
  if chain_is_final(&mut c, 5) { ok = false; }
  if chain_is_final(&mut c, 99) { ok = false; }
  chain_set_finality_depth(&mut c, 0);
  if chain_finalized_height(&mut c) != 4 { ok = false; }
  if !chain_is_final(&mut c, 5) { ok = false; }
  chain_set_finality_depth(&mut c, 10);
  if chain_finalized_height(&mut c) != 0 { ok = false; }
  if !chain_is_final(&mut c, 1) { ok = false; }
  if chain_is_final(&mut c, 2) { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "finalized height follows best height minus depth");
}

fn t23() -> TestResult {
  var c = mk();
  ap(&mut c, 10, 1, 1, 1, 100);
  ap(&mut c, 11, 10, 2, 1, 110);
  ap(&mut c, 20, 1, 1, 1, 200);
  ap(&mut c, 21, 20, 2, 1, 210);
  ap(&mut c, 22, 21, 3, 1, 220);
  ap(&mut c, 4, 8, 1, 1, 400);
  var ok = chain_invariants(&mut c);
  if chain_violations(&mut c) != 0 { ok = false; }
  c.works[0] = 2;
  if chain_violations(&mut c) != chain_violation_work() { ok = false; }
  c.works[0] = 1;
  c.tags.push(22);
  c.parents.push(1);
  c.heights.push(1);
  c.own.push(1);
  c.works.push(2);
  c.roots.push(0);
  if chain_violations(&mut c) != chain_violation_duplicate() { ok = false; }
  c.tags.pop();
  c.parents.pop();
  c.heights.pop();
  c.own.pop();
  c.works.pop();
  c.roots.pop();
  c.best = 999;
  if chain_violations(&mut c) != chain_violation_best() { ok = false; }
  c.best = 22;
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "invariant checker reports clean state and each corruption bit");
}

fn t24() -> TestResult {
  var c = mk();
  var ok = chain_genesis_tag() == 1;
  if chain_block_count(&mut c) != 1 { ok = false; }
  if chain_tag_at(&mut c, 0) != 1 { ok = false; }
  if chain_block_parent(&mut c, 1) != 0 { ok = false; }
  if chain_block_height(&mut c, 1) != 0 { ok = false; }
  if chain_block_own_work(&mut c, 1) != 1 { ok = false; }
  if chain_block_work(&mut c, 1) != 1 { ok = false; }
  if chain_block_root(&mut c, 1) != 1000 { ok = false; }
  if chain_block_height(&mut c, 2) != -1 { ok = false; }
  if chain_block_parent(&mut c, 2) != -1 { ok = false; }
  if chain_block_work(&mut c, 2) != -1 { ok = false; }
  if chain_block_own_work(&mut c, 2) != -1 { ok = false; }
  if chain_block_root(&mut c, 2) != -1 { ok = false; }
  if chain_best_chain_len(&mut c) != 1 { ok = false; }
  if chain_finalized_height(&mut c) != 0 { ok = false; }
  if !chain_is_final(&mut c, 1) { ok = false; }
  if !chain_invariants(&mut c) { ok = false; }
  return assert(ok, "genesis layout and unknown-tag sentinels are pinned");
}

fn main() -> Int {
  io.println("=== xiom.chaincore conformance tests ===");
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
    io.println("xiom.chaincore: all tests passed");
  } else {
    io.println("xiom.chaincore: tests failed");
  }
  return failed;
}
