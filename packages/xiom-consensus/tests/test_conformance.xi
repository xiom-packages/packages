// XIOM -- xiom.consensus conformance tests (20 checks)
// Port task: prove the deterministic caller-driven Raft model against its
// documented semantics (SPEC.md): quorum math, explicit-vote elections, role
// transitions, log replication with next/match/commit indices, divergence
// repair, message records, the invariants checker and the traces.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures are built in-test and every check starts with raft_configure, a
// full reset (state, logs, vote matrix, pending reply, trace), so the suite is
// order-independent. Str equality goes through compare.str_compare (BUG 17
// discipline); every vec element read happens inside the module.

module consensus_tests
use xiom.io; use xiom.test; use xiom.consensus;
use xiom.string;
use xiom.string.compare;

// 2^62 - 1 is not needed here; the module owns all state arithmetic.

// --------------------------------------------------
//  Result / Str helpers
// --------------------------------------------------

// True when the Result is Err with exactly the (code, value, extra) triple.
fn err_is(r: Result[Int, ConsensusError], code: Int, value: Int, extra: Int) -> Bool {
  if r.is_ok { return false; }
  let e: ConsensusError = r.error;
  if e.code != code { return false; }
  if e.value != value { return false; }
  return e.extra == extra;
}

// True when the Result is Ok with the given value.
fn ok_is(r: Result[Int, ConsensusError], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

// Ok value, or -999999 on Err (keeps a broken expectation failing loudly).
fn ok_val(r: Result[Int, ConsensusError]) -> Int {
  if !r.is_ok { return -999999; }
  let v: Int = r.value;
  return v;
}

// Byte-wise Str equality through str_compare (BUG 17 discipline).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when raft_error_message(code) equals `want` byte-wise.
fn msg_is(code: Int, want: Str) -> Bool {
  return streq(raft_error_message(code), want);
}

// --------------------------------------------------
//  Scenario helpers (direct calls, no fn tables)
// --------------------------------------------------

// Send a RequestVote from `cand` to `voter` in `term` (empty log claim) and
// deliver the reply back; returns the granted bit (0/1), or -1 on a delivery
// failure.
fn grant_of(cand: Int, voter: Int, term: Int) -> Int {
  let m = raft_msg_request_vote(cand, voter, term, 0, 0);
  if raft_deliver(m) != 1 { return -1; }
  let rep = raft_pending_reply();
  if raft_deliver(rep) != 1 { return -1; }
  return raft_msg_a(rep);
}

// Build the next leader AppendEntries for `follower`, deliver it and deliver
// its reply back; returns the success bit (0/1), or -1 on a delivery failure.
fn replicate(leader: Int, follower: Int) -> Int {
  let m = raft_msg_from_leader(leader, follower);
  if raft_deliver(m) != 1 { return -1; }
  let rep = raft_pending_reply();
  if raft_deliver(rep) != 1 { return -1; }
  return raft_msg_a(rep);
}

// Elect node 0 in a freshly configured 3-node cluster (term 1) with one
// grant from node 1.
fn make_leader_3_0() -> Bool {
  var ok = true;
  if !ok_is(raft_election_start(0), 1) { ok = false; }
  if grant_of(0, 1, 1) != 1 { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_node_term(0) != 1 { ok = false; }
  return ok;
}

// --------------------------------------------------
//  Cluster setup, quorum math
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if raft_node_count() != 3 { ok = false; }
  if raft_max_nodes() != 8 { ok = false; }
  if raft_log_capacity() != 64 { ok = false; }
  if raft_quorum_size(1) != 1 { ok = false; }
  if raft_quorum_size(2) != 2 { ok = false; }
  if raft_quorum_size(3) != 2 { ok = false; }
  if raft_quorum_size(4) != 3 { ok = false; }
  if raft_quorum_size(5) != 3 { ok = false; }
  if raft_quorum_size(7) != 4 { ok = false; }
  if raft_quorum_size(8) != 5 { ok = false; }
  if !raft_has_majority(3, 5) { ok = false; }
  if raft_has_majority(2, 5) { ok = false; }
  if !raft_has_majority(1, 1) { ok = false; }
  if !err_is(raft_configure(0), 2, 0, 8) { ok = false; }
  if !err_is(raft_configure(9), 2, 9, 8) { ok = false; }
  if raft_node_count() != 3 { ok = false; }
  if raft_node_role(0) != 0 { ok = false; }
  if raft_node_term(1) != 0 { ok = false; }
  if raft_node_voted_for(2) != -1 { ok = false; }
  if raft_node_commit(1) != 0 { ok = false; }
  if raft_node_log_len(2) != 0 { ok = false; }
  if raft_next_index(1) != 1 { ok = false; }
  if raft_match_index(1) != 0 { ok = false; }
  if raft_node_role(-1) != -1 { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  return assert(ok, "configure validates and resets a fresh cluster; quorum math");
}

fn t2() -> TestResult {
  var ok = ok_is(raft_configure(1), 1);
  if !ok_is(raft_election_start(0), 1) { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_node_term(0) != 1 { ok = false; }
  if raft_node_voted_for(0) != 0 { ok = false; }
  if raft_election_vote_count(0) != 1 { ok = false; }
  if !raft_election_has_quorum(0) { ok = false; }
  if !ok_is(raft_leader_append(0, 42), 1) { ok = false; }
  if raft_node_log_len(0) != 1 { ok = false; }
  if raft_node_log_term(0, 1) != 1 { ok = false; }
  if raft_node_log_cmd(0, 1) != 42 { ok = false; }
  if raft_node_last_log_term(0) != 1 { ok = false; }
  if raft_node_commit(0) != 0 { ok = false; }
  if !ok_is(raft_commit_advance(0), 1) { ok = false; }
  if raft_node_commit(0) != 1 { ok = false; }
  if !err_is(raft_election_start(0), 3, 0, 2) { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  return assert(ok, "single-node cluster elects itself, committable immediately");
}

fn t3() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !ok_is(raft_election_start(0), 1) { ok = false; }
  if raft_node_role(0) != 1 { ok = false; }
  if raft_node_voted_for(0) != 0 { ok = false; }
  if raft_election_vote_count(0) != 1 { ok = false; }
  if raft_election_has_quorum(0) { ok = false; }
  let m = raft_msg_request_vote(0, 1, 1, 0, 0);
  if raft_deliver(m) != 1 { ok = false; }
  let rep = raft_pending_reply();
  if raft_msg_kind(rep) != 2 { ok = false; }
  if raft_msg_from(rep) != 1 { ok = false; }
  if raft_msg_to(rep) != 0 { ok = false; }
  if raft_msg_term(rep) != 1 { ok = false; }
  if raft_msg_a(rep) != 1 { ok = false; }
  if raft_node_voted_for(1) != 0 { ok = false; }
  if raft_node_role(0) == 2 { ok = false; }
  if raft_deliver(rep) != 1 { ok = false; }
  if raft_election_vote_count(0) != 2 { ok = false; }
  if !raft_election_has_quorum(0) { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_node_leader_id(0) != 0 { ok = false; }
  if raft_node_commit(0) != 0 { ok = false; }
  return assert(ok, "three-node election needs a quorum of two grants");
}

fn t4() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !make_leader_3_0() { ok = false; }
  if !ok_is(raft_election_start(2), 1) { ok = false; }
  if raft_node_role(2) != 1 { ok = false; }
  if grant_of(2, 1, 1) != 0 { ok = false; }
  if raft_node_voted_for(1) != 0 { ok = false; }
  let stale = raft_msg_request_vote(1, 0, 0, 0, 0);
  if raft_deliver(stale) != 0 { ok = false; }
  let rep = raft_pending_reply();
  if raft_msg_term(rep) != 1 { ok = false; }
  if raft_msg_a(rep) != 0 { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_node_term(0) != 1 { ok = false; }
  return assert(ok, "one vote per term; stale-term requests are rejected");
}

fn t5() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !make_leader_3_0() { ok = false; }
  if !ok_is(raft_election_start(1), 2) { ok = false; }
  if raft_node_role(1) != 1 { ok = false; }
  let m = raft_msg_request_vote(1, 0, 2, 0, 0);
  if raft_deliver(m) != 1 { ok = false; }
  let rep = raft_pending_reply();
  if raft_msg_a(rep) != 1 { ok = false; }
  if raft_msg_term(rep) != 2 { ok = false; }
  if raft_node_term(0) != 2 { ok = false; }
  if raft_node_role(0) != 0 { ok = false; }
  if raft_node_voted_for(0) != 1 { ok = false; }
  if raft_node_leader_id(0) != -1 { ok = false; }
  if raft_deliver(rep) != 1 { ok = false; }
  if raft_node_role(1) != 2 { ok = false; }
  if raft_node_term(1) != 2 { ok = false; }
  return assert(ok, "higher term steps a leader down and clears its vote");
}

fn t6() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !make_leader_3_0() { ok = false; }
  if !ok_is(raft_leader_append(0, 7), 1) { ok = false; }
  if replicate(0, 1) != 1 { ok = false; }
  if raft_node_log_len(1) != 1 { ok = false; }
  let stale = raft_msg_request_vote(2, 1, 2, 0, 0);
  if raft_deliver(stale) != 1 { ok = false; }
  let r1 = raft_pending_reply();
  if raft_msg_a(r1) != 0 { ok = false; }
  if raft_msg_term(r1) != 2 { ok = false; }
  if raft_node_term(1) != 2 { ok = false; }
  if raft_node_voted_for(1) != -1 { ok = false; }
  let uptodate = raft_msg_request_vote(0, 1, 3, 1, 1);
  if raft_deliver(uptodate) != 1 { ok = false; }
  let r2 = raft_pending_reply();
  if raft_msg_a(r2) != 1 { ok = false; }
  if raft_msg_term(r2) != 3 { ok = false; }
  if raft_node_voted_for(1) != 0 { ok = false; }
  if raft_node_term(1) != 3 { ok = false; }
  return assert(ok, "election restriction: stale log rejected, equal log granted");
}

// --------------------------------------------------
//  Replication and commit
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !make_leader_3_0() { ok = false; }
  if !ok_is(raft_leader_append(0, 11), 1) { ok = false; }
  if !ok_is(raft_leader_append(0, 22), 2) { ok = false; }
  if raft_node_commit(0) != 0 { ok = false; }
  if replicate(0, 1) != 1 { ok = false; }
  if raft_match_index(1) != 1 { ok = false; }
  if raft_next_index(1) != 2 { ok = false; }
  if raft_node_commit(0) != 1 { ok = false; }
  if replicate(0, 1) != 1 { ok = false; }
  if raft_match_index(1) != 2 { ok = false; }
  if raft_next_index(1) != 3 { ok = false; }
  if raft_node_commit(0) != 2 { ok = false; }
  if raft_node_log_len(1) != 2 { ok = false; }
  if raft_node_log_cmd(1, 2) != 22 { ok = false; }
  if raft_node_commit(1) != 1 { ok = false; }
  if replicate(0, 1) != 1 { ok = false; }
  if raft_node_commit(1) != 2 { ok = false; }
  if raft_node_log_len(2) != 0 { ok = false; }
  if raft_node_commit(2) != 0 { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  return assert(ok, "replication advances match/next and commits by majority");
}

fn t8() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !make_leader_3_0() { ok = false; }
  if !ok_is(raft_leader_append(0, 5), 1) { ok = false; }
  let bad = raft_msg_append_entry(0, 2, 1, 1, 0, 0, 1, 5);
  if raft_deliver(bad) != 1 { ok = false; }
  let r1 = raft_pending_reply();
  if raft_msg_kind(r1) != 4 { ok = false; }
  if raft_msg_a(r1) != 0 { ok = false; }
  if raft_msg_b(r1) != 0 { ok = false; }
  if raft_deliver(r1) != 1 { ok = false; }
  if raft_next_index(2) != 1 { ok = false; }
  if replicate(0, 2) != 1 { ok = false; }
  if raft_match_index(2) != 1 { ok = false; }
  if raft_next_index(2) != 2 { ok = false; }
  if raft_node_log_len(2) != 1 { ok = false; }
  if raft_node_log_cmd(2, 1) != 5 { ok = false; }
  if raft_node_commit(0) != 1 { ok = false; }
  let wrong = raft_msg_append_entry(0, 2, 1, 1, 99, 1, 2, 6);
  if raft_deliver(wrong) != 1 { ok = false; }
  let r2 = raft_pending_reply();
  if raft_msg_a(r2) != 0 { ok = false; }
  if raft_msg_b(r2) != 1 { ok = false; }
  if raft_deliver(r2) != 1 { ok = false; }
  if raft_next_index(2) != 2 { ok = false; }
  if raft_node_log_len(2) != 1 { ok = false; }
  if raft_node_log_term(2, 1) != 1 { ok = false; }
  return assert(ok, "AppendEntries consistency failure and leader backoff");
}

fn t9() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !ok_is(raft_election_start(2), 1) { ok = false; }
  if grant_of(2, 0, 1) != 1 { ok = false; }
  if grant_of(2, 1, 1) != 1 { ok = false; }
  if raft_node_role(2) != 2 { ok = false; }
  if !ok_is(raft_leader_append(2, 99), 1) { ok = false; }
  if !ok_is(raft_election_start(0), 2) { ok = false; }
  if grant_of(0, 1, 2) != 1 { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_node_term(0) != 2 { ok = false; }
  if !ok_is(raft_leader_append(0, 10), 1) { ok = false; }
  if replicate(0, 2) != 1 { ok = false; }
  if raft_node_log_len(2) != 1 { ok = false; }
  if raft_node_log_term(2, 1) != 2 { ok = false; }
  if raft_node_log_cmd(2, 1) != 10 { ok = false; }
  if replicate(0, 2) != 1 { ok = false; }
  if raft_node_commit(2) != 1 { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  return assert(ok, "conflicting suffix is truncated and replaced");
}

fn t10() -> TestResult {
  var ok = ok_is(raft_configure(5), 5);
  if raft_quorum_size(5) != 3 { ok = false; }
  if !ok_is(raft_election_start(0), 1) { ok = false; }
  if grant_of(0, 1, 1) != 1 { ok = false; }
  if raft_node_role(0) != 1 { ok = false; }
  if raft_election_vote_count(0) != 2 { ok = false; }
  if grant_of(0, 2, 1) != 1 { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_election_vote_count(0) != 3 { ok = false; }
  if !ok_is(raft_leader_append(0, 7), 1) { ok = false; }
  if replicate(0, 1) != 1 { ok = false; }
  if raft_node_commit(0) != 0 { ok = false; }
  if replicate(0, 2) != 1 { ok = false; }
  if raft_node_commit(0) != 1 { ok = false; }
  if raft_match_index(1) != 1 { ok = false; }
  if raft_match_index(2) != 1 { ok = false; }
  if raft_node_commit(1) != 0 { ok = false; }
  return assert(ok, "commit index advances only on a majority of matches");
}

fn t11() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !ok_is(raft_election_start(2), 1) { ok = false; }
  if grant_of(2, 0, 1) != 1 { ok = false; }
  if grant_of(2, 1, 1) != 1 { ok = false; }
  if raft_node_role(2) != 2 { ok = false; }
  if !ok_is(raft_leader_append(2, 99), 1) { ok = false; }
  let m0 = raft_msg_from_leader(2, 0);
  if raft_deliver(m0) != 1 { ok = false; }
  let m1 = raft_msg_from_leader(2, 1);
  if raft_deliver(m1) != 1 { ok = false; }
  if raft_node_commit(2) != 0 { ok = false; }
  if raft_node_log_len(0) != 1 { ok = false; }
  if raft_node_log_len(1) != 1 { ok = false; }
  if !ok_is(raft_election_start(0), 2) { ok = false; }
  let req = raft_msg_request_vote(0, 1, 2, 1, 1);
  if raft_deliver(req) != 1 { ok = false; }
  let rep = raft_pending_reply();
  if raft_msg_a(rep) != 1 { ok = false; }
  if raft_deliver(rep) != 1 { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_node_term(0) != 2 { ok = false; }
  if !ok_is(raft_commit_advance(0), 0) { ok = false; }
  if raft_node_commit(0) != 0 { ok = false; }
  if !ok_is(raft_leader_append(0, 20), 2) { ok = false; }
  if replicate(0, 1) != 1 { ok = false; }
  if raft_node_commit(0) != 2 { ok = false; }
  if replicate(0, 1) != 1 { ok = false; }
  if raft_node_commit(1) != 2 { ok = false; }
  if raft_node_log_cmd(0, 1) != 99 { ok = false; }
  if raft_node_log_term(0, 1) != 1 { ok = false; }
  if raft_node_log_cmd(0, 2) != 20 { ok = false; }
  if raft_node_log_term(0, 2) != 2 { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  return assert(ok, "commit counts only the leader's current-term entries");
}

fn t12() -> TestResult {
  var ok = ok_is(raft_configure(4), 4);
  if raft_quorum_size(4) != 3 { ok = false; }
  if !ok_is(raft_election_start(0), 1) { ok = false; }
  if grant_of(0, 1, 1) != 1 { ok = false; }
  if raft_election_vote_count(0) != 2 { ok = false; }
  if raft_node_role(0) != 1 { ok = false; }
  if !ok_is(raft_election_start(2), 1) { ok = false; }
  if grant_of(2, 3, 1) != 1 { ok = false; }
  if raft_election_vote_count(2) != 2 { ok = false; }
  if grant_of(2, 1, 1) != 0 { ok = false; }
  if raft_node_role(0) == 2 { ok = false; }
  if raft_node_role(2) == 2 { ok = false; }
  if !ok_is(raft_election_start(0), 2) { ok = false; }
  if grant_of(0, 1, 2) != 1 { ok = false; }
  if raft_election_vote_count(0) != 2 { ok = false; }
  if grant_of(0, 2, 2) != 1 { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_node_term(0) != 2 { ok = false; }
  if raft_election_vote_count(0) != 3 { ok = false; }
  if replicate(0, 3) != 1 { ok = false; }
  if raft_node_term(3) != 2 { ok = false; }
  if raft_node_role(3) != 0 { ok = false; }
  if raft_node_leader_id(3) != 0 { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  return assert(ok, "split vote persists, then a higher term resolves it");
}

fn t13() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !make_leader_3_0() { ok = false; }
  let stale = raft_msg_request_vote_reply(1, 0, 0, 1);
  if raft_deliver(stale) != 0 { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  if raft_node_term(0) != 1 { ok = false; }
  let higher = raft_msg_request_vote_reply(1, 0, 5, 0);
  if raft_deliver(higher) != 1 { ok = false; }
  if raft_node_role(0) != 0 { ok = false; }
  if raft_node_term(0) != 5 { ok = false; }
  if raft_node_voted_for(0) != -1 { ok = false; }
  if raft_node_leader_id(0) != -1 { ok = false; }
  return assert(ok, "stale replies are ignored, higher-term replies step down");
}

// --------------------------------------------------
//  Validation, invariants, records, dumps, traces
// --------------------------------------------------

fn t14() -> TestResult {
  var ok = ok_is(raft_configure(2), 2);
  if !make_leader_3_0() { ok = false; }
  if !err_is(raft_election_start(0), 3, 0, 2) { ok = false; }
  if !err_is(raft_leader_append(1, 5), 4, 1, 0) { ok = false; }
  if !err_is(raft_leader_append(9, 5), 1, 9, 2) { ok = false; }
  if !err_is(raft_leader_append(-1, 5), 1, -1, 2) { ok = false; }
  if !err_is(raft_election_start(5), 1, 5, 2) { ok = false; }
  if !err_is(raft_commit_advance(1), 4, 1, 0) { ok = false; }
  var i = 0;
  while i < 64 {
    if !ok_is(raft_leader_append(0, i), i + 1) { ok = false; }
    i = i + 1;
  }
  if raft_node_log_len(0) != 64 { ok = false; }
  if !err_is(raft_leader_append(0, 999), 5, 999, 64) { ok = false; }
  return assert(ok, "role and log-capacity validation on append and election");
}

fn t15() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if raft_invariants_check() != 0 { ok = false; }
  if !str_contains(raft_invariants_report(), "committed_agreement=ok") { ok = false; }
  if !raft_force_commit(1, 3) { ok = false; }
  if raft_invariants_check() != 104 { ok = false; }
  if !str_contains(raft_invariants_report(), "commit_bounds=FAIL") { ok = false; }
  if !ok_is(raft_configure(3), 3) { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  if !raft_force_entry(0, 1, 1, 7) { ok = false; }
  if !raft_force_commit(0, 1) { ok = false; }
  if !raft_force_entry(1, 1, 1, 8) { ok = false; }
  if !raft_force_commit(1, 1) { ok = false; }
  if raft_invariants_check() != 105 { ok = false; }
  if !str_contains(raft_invariants_report(), "committed_agreement=FAIL") { ok = false; }
  if raft_force_entry(0, 65, 1, 1) { ok = false; }
  if raft_force_commit(9, 1) { ok = false; }
  if raft_force_commit(0, -1) { ok = false; }
  if !ok_is(raft_configure(3), 3) { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  if !str_contains(raft_invariants_report(), "vote_bounds=ok") { ok = false; }
  return assert(ok, "invariants checker detects raw-probe corruption and recovers");
}

fn t16() -> TestResult {
  var ok = true;
  let m = raft_msg_request_vote(0, 1, 7, 3, 2);
  if raft_msg_kind(m) != 1 { ok = false; }
  if raft_msg_from(m) != 0 { ok = false; }
  if raft_msg_to(m) != 1 { ok = false; }
  if raft_msg_term(m) != 7 { ok = false; }
  if raft_msg_a(m) != 3 { ok = false; }
  if raft_msg_b(m) != 2 { ok = false; }
  if raft_msg_d(m) != -1 { ok = false; }
  if raft_msg_e(m) != 0 { ok = false; }
  if !streq(raft_msg_kind_name(m), "request_vote") { ok = false; }
  let ar = raft_msg_append_entry(1, 2, 4, 5, 3, 2, 4, 99);
  if raft_msg_kind(ar) != 3 { ok = false; }
  if raft_msg_c(ar) != 2 { ok = false; }
  if raft_msg_d(ar) != 4 { ok = false; }
  if raft_msg_e(ar) != 99 { ok = false; }
  if !streq(raft_msg_kind_name(ar), "append_entries") { ok = false; }
  let hb = raft_msg_append_entries(0, 1, 1, 0, 0, 0);
  if raft_msg_kind(hb) != 3 { ok = false; }
  if raft_msg_d(hb) != -1 { ok = false; }
  let vr = raft_msg_request_vote_reply(2, 0, 3, 1);
  if raft_msg_kind(vr) != 2 { ok = false; }
  if raft_msg_a(vr) != 1 { ok = false; }
  if !streq(raft_msg_kind_name(vr), "request_vote_reply") { ok = false; }
  let aer = raft_msg_append_entries_reply(1, 0, 3, 0, 1);
  if raft_msg_kind(aer) != 4 { ok = false; }
  if raft_msg_a(aer) != 0 { ok = false; }
  if raft_msg_b(aer) != 1 { ok = false; }
  if !streq(raft_msg_kind_name(aer), "append_entries_reply") { ok = false; }
  let em = raft_msg_empty();
  if raft_msg_kind(em) != 0 { ok = false; }
  if !streq(raft_msg_kind_name(em), "unknown") { ok = false; }
  if !str_contains(raft_msg_dump(m), "kind=request_vote") { ok = false; }
  if !str_contains(raft_msg_dump(m), "term=7") { ok = false; }
  if !str_contains(raft_msg_dump(m), "a=3") { ok = false; }
  if raft_deliver(em) != -1 { ok = false; }
  return assert(ok, "message records construct, decode and dump");
}

fn t17() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if raft_has_pending_reply() { ok = false; }
  if raft_msg_kind(raft_pending_reply()) != 0 { ok = false; }
  let m = raft_msg_request_vote(0, 1, 1, 0, 0);
  if raft_deliver(m) != 1 { ok = false; }
  if !raft_has_pending_reply() { ok = false; }
  let p = raft_pending_reply();
  if raft_msg_kind(p) != 2 { ok = false; }
  if raft_msg_from(p) != 1 { ok = false; }
  if raft_msg_to(p) != 0 { ok = false; }
  if raft_msg_a(p) != 1 { ok = false; }
  raft_clear_pending_reply();
  if raft_has_pending_reply() { ok = false; }
  if raft_msg_kind(raft_pending_reply()) != 0 { ok = false; }
  let vr = raft_msg_request_vote_reply(1, 0, 1, 1);
  if raft_deliver(vr) != 1 { ok = false; }
  if raft_has_pending_reply() { ok = false; }
  let hb = raft_msg_append_entries(0, 1, 2, 0, 0, 0);
  if raft_deliver(hb) != 1 { ok = false; }
  if !raft_has_pending_reply() { ok = false; }
  let q = raft_pending_reply();
  if raft_msg_kind(q) != 4 { ok = false; }
  if raft_msg_from(q) != 1 { ok = false; }
  if raft_msg_to(q) != 0 { ok = false; }
  if raft_msg_term(q) != 2 { ok = false; }
  if raft_msg_a(q) != 1 { ok = false; }
  if raft_msg_b(q) != 0 { ok = false; }
  return assert(ok, "pending reply lifecycle across request and reply handlers");
}

fn t18() -> TestResult {
  var ok = ok_is(raft_configure(3), 3);
  if !make_leader_3_0() { ok = false; }
  if !ok_is(raft_leader_append(0, 7), 1) { ok = false; }
  if !streq(raft_node_role_name(0), "leader") { ok = false; }
  if !streq(raft_node_role_name(1), "follower") { ok = false; }
  if !streq(raft_node_role_name(2), "follower") { ok = false; }
  if !streq(raft_node_role_name(99), "unknown") { ok = false; }
  if raft_node_role(99) != -1 { ok = false; }
  if raft_node_term(99) != -1 { ok = false; }
  if raft_node_voted_for(99) != -1 { ok = false; }
  if raft_node_commit(99) != -1 { ok = false; }
  if raft_node_leader_id(99) != -1 { ok = false; }
  if raft_node_log_len(99) != -1 { ok = false; }
  if raft_next_index(99) != -1 { ok = false; }
  if raft_match_index(99) != -1 { ok = false; }
  if raft_election_vote_count(99) != -1 { ok = false; }
  if raft_node_last_log_term(99) != -1 { ok = false; }
  if raft_node_log_term(0, 0) != 0 { ok = false; }
  if raft_node_log_term(0, 1) != 1 { ok = false; }
  if raft_node_log_term(0, 2) != -1 { ok = false; }
  if raft_node_log_cmd(0, 0) != -1 { ok = false; }
  if raft_node_log_cmd(0, 1) != 7 { ok = false; }
  if raft_node_log_cmd(0, 2) != -1 { ok = false; }
  let nd = raft_node_dump(0);
  if !str_contains(nd, "role=leader") { ok = false; }
  if !str_contains(nd, "term=1") { ok = false; }
  if !str_contains(nd, "loglen=1") { ok = false; }
  if !str_contains(nd, "log=1:7") { ok = false; }
  let cd = raft_dump();
  if !str_contains(cd, "node[id=0") { ok = false; }
  if !str_contains(cd, "node[id=1") { ok = false; }
  if !str_contains(cd, "node[id=2") { ok = false; }
  if !str_contains(cd, "role=follower") { ok = false; }
  return assert(ok, "node accessors, bounds and cluster dumps");
}

fn t19() -> TestResult {
  var ok = ok_is(raft_configure(1), 1);
  if !raft_trace_is_enabled() { ok = false; }
  if raft_trace_count() != 0 { ok = false; }
  if !ok_is(raft_election_start(0), 1) { ok = false; }
  if raft_trace_count() != 2 { ok = false; }
  if !ok_is(raft_leader_append(0, 5), 1) { ok = false; }
  if raft_trace_count() != 3 { ok = false; }
  if !ok_is(raft_commit_advance(0), 1) { ok = false; }
  if raft_trace_count() != 4 { ok = false; }
  if !str_contains(raft_trace_line(0), "elect id=0 term=1") { ok = false; }
  if !str_contains(raft_trace_line(1), "leader id=0 term=1") { ok = false; }
  if !str_contains(raft_trace_line(2), "append id=0 index=1") { ok = false; }
  if !str_contains(raft_trace_line(3), "commit id=0 index=1") { ok = false; }
  if !streq(raft_trace_line(99), "") { ok = false; }
  if !str_contains(raft_trace_dump(), "elect id=0 term=1") { ok = false; }
  raft_trace_enable(false);
  if !ok_is(raft_leader_append(0, 6), 2) { ok = false; }
  if raft_trace_count() != 4 { ok = false; }
  raft_trace_enable(true);
  if !ok_is(raft_leader_append(0, 7), 3) { ok = false; }
  if raft_trace_count() != 5 { ok = false; }
  return assert(ok, "traces are deterministic and can be disabled");
}

fn t20() -> TestResult {
  var ok = ok_is(raft_configure(1), 1);
  if !ok_is(raft_election_start(0), 1) { ok = false; }
  if raft_node_role(0) != 2 { ok = false; }
  var i = 0;
  while i < 40 {
    if !ok_is(raft_leader_append(0, i), i + 1) { ok = false; }
    i = i + 1;
  }
  if !ok_is(raft_commit_advance(0), 40) { ok = false; }
  if raft_node_commit(0) != 40 { ok = false; }
  if raft_node_log_len(0) != 40 { ok = false; }
  if !ok_is(raft_configure(3), 3) { ok = false; }
  if !make_leader_3_0() { ok = false; }
  var r = 0;
  while r < 20 {
    if !ok_is(raft_leader_append(0, 1000 + r), r + 1) { ok = false; }
    if replicate(0, 1) != 1 { ok = false; }
    if replicate(0, 2) != 1 { ok = false; }
    r = r + 1;
  }
  if raft_node_commit(0) != 20 { ok = false; }
  if raft_node_log_len(1) != 20 { ok = false; }
  if raft_node_log_len(2) != 20 { ok = false; }
  if replicate(0, 1) != 1 { ok = false; }
  if replicate(0, 2) != 1 { ok = false; }
  if raft_node_commit(1) != 20 { ok = false; }
  if raft_node_commit(2) != 20 { ok = false; }
  if raft_invariants_check() != 0 { ok = false; }
  return assert(ok, "stress: 40 single-node entries and 20 replicated rounds");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.consensus conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.consensus: all tests passed");
  } else {
    io.println("xiom.consensus: tests failed");
  }
  return failed;
}
