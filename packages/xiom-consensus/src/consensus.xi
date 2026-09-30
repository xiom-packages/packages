// XIOM -- xiom.consensus: deterministic caller-driven Raft-style consensus model
// Port task: replace the xiom.consensus placeholder with a real, tested,
// pure-XIOM package (no FFI, no threads, no timers, no clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (full rules in SPEC.md): this module is a deterministic, single-
// threaded model of a small Raft cluster. It never spawns a thread, never
// reads a clock, never uses a timer and never calls FFI. The caller drives
// every step explicitly: elections are started with raft_election_start,
// messages are value records handed to raft_deliver, and replies are read
// back with raft_pending_reply and delivered again. Timeouts, scheduling and
// real interleaving are out of scope.
//
// What it models:
//   * persistent per-node state -- current term, voted-for, and a per-node
//     log stored as parallel Vec[Int] term/command arrays in a flat slab
//     (node id * log capacity + position - 1);
//   * the Raft election restriction -- a node grants at most one vote per
//     term, and only to a candidate whose log is at least as up to date as
//     its own (last log term, then last log index);
//   * quorum math -- majority = n / 2 + 1 (raft_quorum_size), and a
//     candidate promotes itself to leader the moment it holds a majority of
//     grants (raft_election_vote_count / raft_election_has_quorum);
//   * role transitions -- follower / candidate / leader, with higher-term
//     messages forcing a step-down and clearing the vote;
//   * log replication -- leader append (raft_leader_append), per-follower
//     next/match indices (raft_next_index / raft_match_index), one-entry
//     AppendEntries built from the leader view (raft_msg_from_leader), a
//     follower consistency check, conflicting-suffix truncation, and commit
//     advance by majority of replica match indices
//     (raft_commit_advance), which only counts entries from the leader's
//     current term;
//   * message records -- RaftMessage values for RequestVote,
//     RequestVote-reply, AppendEntries (heartbeat or one entry) and
//     AppendEntries-reply, built and decoded with raft_msg_* constructors
//     and accessors;
//   * a safety-invariants checker -- raft_invariants_check /
//     raft_invariants_report (vote bounds, vote-grant terms, one leader per
//     term, commit bounds, committed-log agreement, log matching, term
//     sanity), plus raw force probes that bypass the rules so the checker's
//     failure paths are testable;
//   * deterministic traces -- every semantic step appends a fixed-format
//     line to a module trace (raft_trace_*).
//
// Error model: every fallible operation returns Result[Int, ConsensusError]
// where ConsensusError carries (code, value, extra); raft_error_message is
// the pinned catalog.
//
// Language notes (XIOM v0.62.2) that shaped this module:
//   * free functions only; module-level parallel Vec[Int] state, no
//     Vec[StructType], no struct out-parameters;
//   * every Vec[Int] element read is bound with a typed `let`;
//   * Ok/Err are constructed only inside the leaf helpers below;
//   * no bitwise operators: log indices, terms and votes are plain Int
//     arithmetic;
//   * message records are value structs constructed in leaf constructors.

module xiom.consensus

use xiom.convert.int;
use xiom.string;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Cluster geometry.
const _CS_MAX_NODES: Int = 8;
const _CS_DEF_NODES: Int = 3;
const _CS_LOG_CAP: Int = 64;

// Roles.
const _CS_ROLE_FOLLOWER: Int = 0;
const _CS_ROLE_CANDIDATE: Int = 1;
const _CS_ROLE_LEADER: Int = 2;

// Message kinds.
const _CS_MSG_REQUEST_VOTE: Int = 1;
const _CS_MSG_REQUEST_VOTE_REPLY: Int = 2;
const _CS_MSG_APPEND_ENTRIES: Int = 3;
const _CS_MSG_APPEND_ENTRIES_REPLY: Int = 4;

// "Not applicable" filler for an unused Int field.
const _CS_NONE: Int = -1;

// AppendEntries entry_term sentinel: no entry (heartbeat).
const _CS_NO_ENTRY: Int = -1;

// raft_deliver outcome codes.
const _CS_DELIVER_HANDLED: Int = 1;
const _CS_DELIVER_STALE: Int = 0;
const _CS_DELIVER_UNKNOWN: Int = -1;

// ConsensusError API codes (pinned messages in raft_error_message).
const _CS_ERR_NODE_RANGE: Int = 1;
const _CS_ERR_NODE_COUNT: Int = 2;
const _CS_ERR_NOT_ELECTABLE: Int = 3;
const _CS_ERR_NOT_LEADER: Int = 4;
const _CS_ERR_LOG_FULL: Int = 5;

// Safety-invariant codes (101..107, also pinned in raft_error_message).
const _CS_INV_VOTE_BOUNDS: Int = 101;
const _CS_INV_GRANT_TERMS: Int = 102;
const _CS_INV_LEADER_UNIQUE: Int = 103;
const _CS_INV_COMMIT_BOUNDS: Int = 104;
const _CS_INV_COMMITTED_AGREE: Int = 105;
const _CS_INV_LOG_MATCHING: Int = 106;
const _CS_INV_TERM_SANITY: Int = 107;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Typed error carried by every fallible consensus operation.
/// `code` identifies the failure; `value` is the offending input (-1 when
/// none); `extra` is the bound or context (node count, role, capacity; -1
/// when none).
pub type ConsensusError = {
  code: Int;
  value: Int;
  extra: Int;
}

/// A Raft message record. `kind` selects the meaning of the trailing
/// fields:
///   1 RequestVote          a = candidate last log index, b = last log term
///   2 RequestVote reply    a = granted (0/1)
///   3 AppendEntries        a = prev log index, b = prev log term,
///                          c = leader commit, d = entry term
///                          (-1 = heartbeat, no entry), e = entry command
///   4 AppendEntries reply  a = success (0/1), b = match index
pub type RaftMessage = {
  kind: Int;
  from: Int;
  to: Int;
  term: Int;
  a: Int;
  b: Int;
  c: Int;
  d: Int;
  e: Int;
}

// --------------------------------------------------
//  Module state
// --------------------------------------------------

var _cs_ready: Bool = false;
var _cs_n: Int = _CS_DEF_NODES;

// Per-node persistent and volatile state (parallel Vec[Int]).
var _cs_term: Vec[Int] = Vec[Int].new();
var _cs_voted_for: Vec[Int] = Vec[Int].new();
var _cs_role: Vec[Int] = Vec[Int].new();
var _cs_commit: Vec[Int] = Vec[Int].new();
var _cs_leader_id: Vec[Int] = Vec[Int].new();
var _cs_log_len: Vec[Int] = Vec[Int].new();
var _cs_leader_term: Vec[Int] = Vec[Int].new();
var _cs_next: Vec[Int] = Vec[Int].new();
var _cs_match: Vec[Int] = Vec[Int].new();

// Flat log slab: node id * _CS_LOG_CAP + (index - 1), index is 1-based.
var _cs_log_term: Vec[Int] = Vec[Int].new();
var _cs_log_cmd: Vec[Int] = Vec[Int].new();

// Vote-grant matrix: candidate * n + voter -> term granted (0 = none).
var _cs_votes: Vec[Int] = Vec[Int].new();

// Pending outbound reply record (set by the request handlers).
var _cs_has_reply: Bool = false;
var _cs_reply_kind: Int = 0;
var _cs_reply_from: Int = _CS_NONE;
var _cs_reply_to: Int = _CS_NONE;
var _cs_reply_term: Int = 0;
var _cs_reply_a: Int = 0;
var _cs_reply_b: Int = 0;
var _cs_reply_c: Int = 0;
var _cs_reply_d: Int = _CS_NO_ENTRY;
var _cs_reply_e: Int = 0;

// Deterministic event trace: all lines joined with '\n' in one Str, plus the
// byte offset of each line (parallel Vec[Int]) so lines can be sliced back
// out. A Str is never stored into a Vec here: Vec[Str] element pushes mis-
// lower on this compiler, so the trace keeps only Int and Str scalars.
var _cs_trace_text: Str = "";
var _cs_trace_start: Vec[Int] = Vec[Int].new();
var _cs_trace_n: Int = 0;
var _cs_trace_on: Bool = true;

// --------------------------------------------------
//  Result leaves (Ok/Err construction is confined here)
// --------------------------------------------------

fn _cs_ok(v: Int) -> Result[Int, ConsensusError] {
  return Ok(v);
}

fn _cs_err(code: Int, value: Int, extra: Int) -> Result[Int, ConsensusError] {
  let e = ConsensusError{ code: code; value: value; extra: extra; };
  return Err(e);
}

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Decimal text for an Int (int_to_base is exact across the full Int range).
fn _cs_dec(n: Int) -> Str {
  return int_to_base(n, 10);
}

// Append one trace line when tracing is enabled.
fn _cs_trace_ev(s: Str) {
  if _cs_trace_on {
    if _cs_trace_n > 0 {
      _cs_trace_text = _cs_trace_text + "\n";
    }
    let off = str_len(_cs_trace_text);
    _cs_trace_start.push(off);
    _cs_trace_text = _cs_trace_text + s;
    _cs_trace_n = _cs_trace_n + 1;
  }
}

// Flat log slot for a 1-based index.
fn _cs_slot(id: Int, index: Int) -> Int {
  return id * _CS_LOG_CAP + (index - 1);
}

// Log term at a 1-based index (callers guarantee 1 <= index <= log_len).
fn _cs_log_term_at(id: Int, index: Int) -> Int {
  let slot = _cs_slot(id, index);
  let t: Int = _cs_log_term[slot];
  return t;
}

// Log command at a 1-based index (callers guarantee 1 <= index <= log_len).
fn _cs_log_cmd_at(id: Int, index: Int) -> Int {
  let slot = _cs_slot(id, index);
  let c: Int = _cs_log_cmd[slot];
  return c;
}

// --------------------------------------------------
//  Cluster setup
// --------------------------------------------------

// Reset and (re)build the whole cluster for a validated node count. Every
// parallel vector receives exactly `n` mirrored pushes in one loop, the log
// slab receives exactly `n * _CS_LOG_CAP` mirrored pushes, and the vote
// matrix exactly `n * n`; no later operation reallocates.
// Complexity: O(n * log capacity).
fn _cs_configure(n: Int) {
  _cs_n = n;
  _cs_term.clear();
  _cs_voted_for.clear();
  _cs_role.clear();
  _cs_commit.clear();
  _cs_leader_id.clear();
  _cs_log_len.clear();
  _cs_leader_term.clear();
  _cs_next.clear();
  _cs_match.clear();
  var i = 0;
  while i < n {
    _cs_term.push(0);
    _cs_voted_for.push(_CS_NONE);
    _cs_role.push(_CS_ROLE_FOLLOWER);
    _cs_commit.push(0);
    _cs_leader_id.push(_CS_NONE);
    _cs_log_len.push(0);
    _cs_leader_term.push(0);
    _cs_next.push(1);
    _cs_match.push(0);
    i = i + 1;
  }
  _cs_log_term.clear();
  _cs_log_cmd.clear();
  var j = 0;
  while j < n * _CS_LOG_CAP {
    _cs_log_term.push(0);
    _cs_log_cmd.push(0);
    j = j + 1;
  }
  _cs_votes.clear();
  var k = 0;
  while k < n * n {
    _cs_votes.push(0);
    k = k + 1;
  }
  _cs_has_reply = false;
  _cs_reply_kind = 0;
  _cs_reply_from = _CS_NONE;
  _cs_reply_to = _CS_NONE;
  _cs_reply_term = 0;
  _cs_reply_a = 0;
  _cs_reply_b = 0;
  _cs_reply_c = 0;
  _cs_reply_d = _CS_NO_ENTRY;
  _cs_reply_e = 0;
  _cs_trace_text = "";
  _cs_trace_start.clear();
  _cs_trace_n = 0;
  _cs_trace_on = true;
  _cs_ready = true;
}

// Build the default cluster when nothing was configured yet, so the public
// API works without an explicit raft_configure call.
fn _cs_ensure() {
  if !_cs_ready {
    _cs_configure(_CS_DEF_NODES);
  }
}

// --------------------------------------------------
//  Term / role transitions
// --------------------------------------------------

// Adopt a higher term: store it, clear the vote, become a follower and
// forget the known leader.
fn _cs_adopt_term(id: Int, t: Int) {
  _cs_term[id] = t;
  _cs_voted_for[id] = _CS_NONE;
  _cs_role[id] = _CS_ROLE_FOLLOWER;
  _cs_leader_id[id] = _CS_NONE;
  _cs_trace_ev("adopt id=" + _cs_dec(id) + " term=" + _cs_dec(t));
}

// Promote a candidate to leader for its current term and (re)initialise the
// per-follower replication cursors: next = last log index + 1, match = 0.
fn _cs_promote(id: Int) {
  _cs_role[id] = _CS_ROLE_LEADER;
  let t: Int = _cs_term[id];
  _cs_leader_term[id] = t;
  _cs_leader_id[id] = id;
  let len: Int = _cs_log_len[id];
  var i = 0;
  while i < _cs_n {
    if i != id {
      _cs_next[i] = len + 1;
      _cs_match[i] = 0;
    }
    i = i + 1;
  }
  _cs_trace_ev("leader id=" + _cs_dec(id) + " term=" + _cs_dec(t));
}

// Distinct voters (including the self-vote) that granted in the node's
// current term.
fn _cs_vote_count(id: Int) -> Int {
  let t: Int = _cs_term[id];
  var cnt = 0;
  var i = 0;
  while i < _cs_n {
    let g: Int = _cs_votes[id * _cs_n + i];
    if g == t {
      cnt = cnt + 1;
    }
    i = i + 1;
  }
  return cnt;
}

// --------------------------------------------------
//  Quorum math
// --------------------------------------------------

/// Majority size of a cluster of `n` nodes: floor(n / 2) + 1. Returns 0 for
/// n <= 0. Complexity: O(1).
pub fn raft_quorum_size(n: Int) -> Int {
  if n <= 0 {
    return 0;
  }
  return n / 2 + 1;
}

/// True when `votes` reaches the majority of `n` nodes.
/// Complexity: O(1).
pub fn raft_has_majority(votes: Int, n: Int) -> Bool {
  return votes >= raft_quorum_size(n);
}

// --------------------------------------------------
//  Public cluster setup / geometry
// --------------------------------------------------

/// Configure the cluster: validate the node count, then reset every node's
/// term, vote, role, commit index, log and replication cursor, and clear the
/// vote matrix and trace.
/// Params: nodes - cluster size, 1..raft_max_nodes().
/// Returns: Ok(nodes). On Err code 2 (value = nodes, extra =
/// raft_max_nodes()) the previous configuration is unchanged.
/// Complexity: O(nodes * log capacity).
pub fn raft_configure(nodes: Int) -> Result[Int, ConsensusError] {
  if nodes < 1 || nodes > _CS_MAX_NODES {
    return _cs_err(_CS_ERR_NODE_COUNT, nodes, _CS_MAX_NODES);
  }
  _cs_configure(nodes);
  return _cs_ok(nodes);
}

/// Largest node count raft_configure accepts: 8. Complexity: O(1).
pub fn raft_max_nodes() -> Int {
  return _CS_MAX_NODES;
}

/// Per-node log capacity: 64 entries. Complexity: O(1).
pub fn raft_log_capacity() -> Int {
  return _CS_LOG_CAP;
}

/// Current cluster size. Complexity: O(1).
pub fn raft_node_count() -> Int {
  _cs_ensure();
  return _cs_n;
}

// --------------------------------------------------
//  Per-node accessors
// --------------------------------------------------

/// Role of a node: 0 follower, 1 candidate, 2 leader; -1 when the id is out
/// of range. Complexity: O(1).
pub fn raft_node_role(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let v: Int = _cs_role[id];
  return v;
}

/// Role of a node as text: "follower", "candidate", "leader"; "unknown" when
/// the id is out of range. Compare with xiom.string.compare::str_compare.
/// Complexity: O(1).
pub fn raft_node_role_name(id: Int) -> Str {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return "unknown";
  }
  let r: Int = _cs_role[id];
  if r == _CS_ROLE_FOLLOWER {
    return "follower";
  }
  if r == _CS_ROLE_CANDIDATE {
    return "candidate";
  }
  if r == _CS_ROLE_LEADER {
    return "leader";
  }
  return "unknown";
}

/// Current term of a node; -1 when the id is out of range. Complexity: O(1).
pub fn raft_node_term(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let v: Int = _cs_term[id];
  return v;
}

/// Node voted for in the current term, -1 when none or the id is out of
/// range. Complexity: O(1).
pub fn raft_node_voted_for(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let v: Int = _cs_voted_for[id];
  return v;
}

/// Commit index of a node; -1 when the id is out of range. Complexity: O(1).
pub fn raft_node_commit(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let v: Int = _cs_commit[id];
  return v;
}

/// Last leader a node learned about, -1 when none or the id is out of range.
/// Complexity: O(1).
pub fn raft_node_leader_id(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let v: Int = _cs_leader_id[id];
  return v;
}

/// Number of log entries on a node; -1 when the id is out of range.
/// Complexity: O(1).
pub fn raft_node_log_len(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let v: Int = _cs_log_len[id];
  return v;
}

/// Term of the last log entry, 0 for an empty log, -1 when the id is out of
/// range. Complexity: O(1).
pub fn raft_node_last_log_term(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let len: Int = _cs_log_len[id];
  if len <= 0 {
    return 0;
  }
  return _cs_log_term_at(id, len);
}

/// Log term at a 1-based index: 0 for index 0 (the empty prefix), -1 when the
/// index is out of the log or the node id is out of range. Complexity: O(1).
pub fn raft_node_log_term(id: Int, index: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  if index <= 0 {
    return 0;
  }
  let len: Int = _cs_log_len[id];
  if index > len {
    return _CS_NONE;
  }
  return _cs_log_term_at(id, index);
}

/// Log command at a 1-based index; -1 when the index is out of the log or the
/// node id is out of range. Complexity: O(1).
pub fn raft_node_log_cmd(id: Int, index: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  if index <= 0 {
    return _CS_NONE;
  }
  let len: Int = _cs_log_len[id];
  if index > len {
    return _CS_NONE;
  }
  return _cs_log_cmd_at(id, index);
}

/// Leader-side next index for a follower; -1 when the id is out of range.
/// Meaningful only for the most recently promoted leader's view.
/// Complexity: O(1).
pub fn raft_next_index(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let v: Int = _cs_next[id];
  return v;
}

/// Leader-side match index for a follower; -1 when the id is out of range.
/// Meaningful only for the most recently promoted leader's view.
/// Complexity: O(1).
pub fn raft_match_index(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  let v: Int = _cs_match[id];
  return v;
}

// --------------------------------------------------
//  Elections
// --------------------------------------------------

/// Start an election on a node: increment its term, vote for itself, become a
/// candidate and, in a single-node cluster (self-vote alone is a majority),
/// promote itself immediately.
/// Params: id - node id.
/// Returns: Ok(new term).
/// Error case: 1 node id out of range (value = id, extra = node count); 3
/// the node is already a leader in its current term (value = id, extra =
/// role).
/// Complexity: O(nodes).
pub fn raft_election_start(id: Int) -> Result[Int, ConsensusError] {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _cs_err(_CS_ERR_NODE_RANGE, id, _cs_n);
  }
  let role: Int = _cs_role[id];
  if role == _CS_ROLE_LEADER {
    return _cs_err(_CS_ERR_NOT_ELECTABLE, id, role);
  }
  let t: Int = _cs_term[id] + 1;
  _cs_term[id] = t;
  _cs_voted_for[id] = id;
  _cs_role[id] = _CS_ROLE_CANDIDATE;
  _cs_leader_id[id] = _CS_NONE;
  _cs_votes[id * _cs_n + id] = t;
  _cs_trace_ev("elect id=" + _cs_dec(id) + " term=" + _cs_dec(t));
  if _cs_vote_count(id) >= raft_quorum_size(_cs_n) {
    _cs_promote(id);
  }
  return _cs_ok(t);
}

/// Distinct voters that granted in the node's current term, self-vote
/// included (the node must have started an election); -1 when the id is out
/// of range. Complexity: O(nodes).
pub fn raft_election_vote_count(id: Int) -> Int {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _CS_NONE;
  }
  return _cs_vote_count(id);
}

/// True when the node's current-term vote grants reach a majority.
/// Complexity: O(nodes).
pub fn raft_election_has_quorum(id: Int) -> Bool {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return false;
  }
  return _cs_vote_count(id) >= raft_quorum_size(_cs_n);
}

// --------------------------------------------------
//  Log append / commit
// --------------------------------------------------

/// Append one command to the leader's log at the next index, stamped with the
/// leader's current term. Commit does not advance here; it advances through
/// raft_commit_advance once a majority of followers have matched.
/// Params: id - leader node id; cmd - command value.
/// Returns: Ok(index) - the 1-based index of the new entry.
/// Error cases: 1 id out of range (value = id, extra = node count); 4 not a
/// leader (value = id, extra = role); 5 log full (value = cmd, extra =
/// log capacity).
/// Complexity: O(1).
pub fn raft_leader_append(id: Int, cmd: Int) -> Result[Int, ConsensusError] {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _cs_err(_CS_ERR_NODE_RANGE, id, _cs_n);
  }
  let role: Int = _cs_role[id];
  if role != _CS_ROLE_LEADER {
    return _cs_err(_CS_ERR_NOT_LEADER, id, role);
  }
  let len: Int = _cs_log_len[id];
  if len >= _CS_LOG_CAP {
    return _cs_err(_CS_ERR_LOG_FULL, cmd, _CS_LOG_CAP);
  }
  let idx = len + 1;
  let slot = _cs_slot(id, idx);
  let t: Int = _cs_term[id];
  _cs_log_term[slot] = t;
  _cs_log_cmd[slot] = cmd;
  _cs_log_len[id] = idx;
  _cs_trace_ev("append id=" + _cs_dec(id) + " index=" + _cs_dec(idx) + " term=" + _cs_dec(t) + " cmd=" + _cs_dec(cmd));
  return _cs_ok(idx);
}

// Recompute the commit index of a leader from the follower match indices:
// the highest index N above the current commit where the leader's log term
// equals its current term and a majority of match indices (self counted as
// the full log length) are >= N. No-op when no such N exists.
// Complexity: O(log length * nodes).
fn _cs_commit_advance(id: Int) -> Int {
  let len: Int = _cs_log_len[id];
  let t: Int = _cs_term[id];
  let cur: Int = _cs_commit[id];
  var n = len;
  var found = false;
  while n > cur && !found {
    let et = _cs_log_term_at(id, n);
    if et == t {
      var cnt = 1;
      var i = 0;
      while i < _cs_n {
        if i != id {
          let mi: Int = _cs_match[i];
          if mi >= n {
            cnt = cnt + 1;
          }
        }
        i = i + 1;
      }
      if cnt >= raft_quorum_size(_cs_n) {
        found = true;
      } else {
        n = n - 1;
      }
    } else {
      n = n - 1;
    }
  }
  if found {
    _cs_commit[id] = n;
    _cs_trace_ev("commit id=" + _cs_dec(id) + " index=" + _cs_dec(n));
    return n;
  }
  return cur;
}

/// Advance a leader's commit index by majority of replica match indices; only
/// entries from the leader's current term are counted directly (older-term
/// entries become committed once a current-term entry above them commits).
/// Returns: Ok(commit index after the call).
/// Error cases: 1 id out of range (value = id, extra = node count); 4 not a
/// leader (value = id, extra = role).
/// Complexity: O(log length * nodes).
pub fn raft_commit_advance(id: Int) -> Result[Int, ConsensusError] {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return _cs_err(_CS_ERR_NODE_RANGE, id, _cs_n);
  }
  let role: Int = _cs_role[id];
  if role != _CS_ROLE_LEADER {
    return _cs_err(_CS_ERR_NOT_LEADER, id, role);
  }
  let c = _cs_commit_advance(id);
  return _cs_ok(c);
}

// --------------------------------------------------
//  Message records
// --------------------------------------------------

// Leaf message constructor (all fields explicit).
fn _cs_msg(kind: Int, from: Int, to: Int, term: Int, a: Int, b: Int, c: Int, d: Int, e: Int) -> RaftMessage {
  return RaftMessage{ kind: kind; from: from; to: to; term: term; a: a; b: b; c: c; d: d; e: e; };
}

/// Kind-0 empty message (no fields meaningful).
/// Complexity: O(1).
pub fn raft_msg_empty() -> RaftMessage {
  return _cs_msg(0, _CS_NONE, _CS_NONE, 0, 0, 0, 0, _CS_NO_ENTRY, 0);
}

/// RequestVote record: `from` asks `to` for a vote in `term`, declaring
/// last_log_index / last_log_term. Complexity: O(1).
pub fn raft_msg_request_vote(from: Int, to: Int, term: Int, last_index: Int, last_term: Int) -> RaftMessage {
  return _cs_msg(_CS_MSG_REQUEST_VOTE, from, to, term, last_index, last_term, 0, _CS_NO_ENTRY, 0);
}

/// RequestVote-reply record: granted is 1 (granted) or 0 (denied).
/// Complexity: O(1).
pub fn raft_msg_request_vote_reply(from: Int, to: Int, term: Int, granted: Int) -> RaftMessage {
  return _cs_msg(_CS_MSG_REQUEST_VOTE_REPLY, from, to, term, granted, 0, 0, _CS_NO_ENTRY, 0);
}

/// AppendEntries heartbeat record: no entry carried (d = -1).
/// Complexity: O(1).
pub fn raft_msg_append_entries(from: Int, to: Int, term: Int, prev_index: Int, prev_term: Int, leader_commit: Int) -> RaftMessage {
  return _cs_msg(_CS_MSG_APPEND_ENTRIES, from, to, term, prev_index, prev_term, leader_commit, _CS_NO_ENTRY, 0);
}

/// AppendEntries record carrying exactly one entry (entry_term >= 0).
/// Complexity: O(1).
pub fn raft_msg_append_entry(from: Int, to: Int, term: Int, prev_index: Int, prev_term: Int, leader_commit: Int, entry_term: Int, entry_cmd: Int) -> RaftMessage {
  return _cs_msg(_CS_MSG_APPEND_ENTRIES, from, to, term, prev_index, prev_term, leader_commit, entry_term, entry_cmd);
}

/// AppendEntries-reply record: success is 1/0 and match_index is the highest
/// replicated index the follower reports (its log length on failure).
/// Complexity: O(1).
pub fn raft_msg_append_entries_reply(from: Int, to: Int, term: Int, success: Int, match_index: Int) -> RaftMessage {
  return _cs_msg(_CS_MSG_APPEND_ENTRIES_REPLY, from, to, term, success, match_index, 0, _CS_NO_ENTRY, 0);
}

/// Message kind of a record. Complexity: O(1).
pub fn raft_msg_kind(m: RaftMessage) -> Int {
  let v: Int = m.kind;
  return v;
}

/// Sender node of a record. Complexity: O(1).
pub fn raft_msg_from(m: RaftMessage) -> Int {
  let v: Int = m.from;
  return v;
}

/// Recipient node of a record. Complexity: O(1).
pub fn raft_msg_to(m: RaftMessage) -> Int {
  let v: Int = m.to;
  return v;
}

/// Sender term of a record. Complexity: O(1).
pub fn raft_msg_term(m: RaftMessage) -> Int {
  let v: Int = m.term;
  return v;
}

/// Field a of a record (kind-specific; see RaftMessage). Complexity: O(1).
pub fn raft_msg_a(m: RaftMessage) -> Int {
  let v: Int = m.a;
  return v;
}

/// Field b of a record (kind-specific; see RaftMessage). Complexity: O(1).
pub fn raft_msg_b(m: RaftMessage) -> Int {
  let v: Int = m.b;
  return v;
}

/// Field c of a record (kind-specific; see RaftMessage). Complexity: O(1).
pub fn raft_msg_c(m: RaftMessage) -> Int {
  let v: Int = m.c;
  return v;
}

/// Field d of a record (kind-specific; see RaftMessage). Complexity: O(1).
pub fn raft_msg_d(m: RaftMessage) -> Int {
  let v: Int = m.d;
  return v;
}

/// Field e of a record (kind-specific; see RaftMessage). Complexity: O(1).
pub fn raft_msg_e(m: RaftMessage) -> Int {
  let v: Int = m.e;
  return v;
}

/// Kind name as text: "request_vote", "request_vote_reply",
/// "append_entries", "append_entries_reply"; "unknown" otherwise. Compare
/// with xiom.string.compare::str_compare. Complexity: O(1).
pub fn raft_msg_kind_name(m: RaftMessage) -> Str {
  let k: Int = m.kind;
  if k == _CS_MSG_REQUEST_VOTE {
    return "request_vote";
  }
  if k == _CS_MSG_REQUEST_VOTE_REPLY {
    return "request_vote_reply";
  }
  if k == _CS_MSG_APPEND_ENTRIES {
    return "append_entries";
  }
  if k == _CS_MSG_APPEND_ENTRIES_REPLY {
    return "append_entries_reply";
  }
  return "unknown";
}

/// One-line message dump for tests:
/// `msg[kind=.. from=.. to=.. term=.. a=.. b=.. c=.. d=.. e=..]`.
/// Complexity: O(1).
pub fn raft_msg_dump(m: RaftMessage) -> Str {
  var out = "msg[kind=" + raft_msg_kind_name(m);
  out = out + " from=" + _cs_dec(raft_msg_from(m));
  out = out + " to=" + _cs_dec(raft_msg_to(m));
  out = out + " term=" + _cs_dec(raft_msg_term(m));
  out = out + " a=" + _cs_dec(raft_msg_a(m));
  out = out + " b=" + _cs_dec(raft_msg_b(m));
  out = out + " c=" + _cs_dec(raft_msg_c(m));
  out = out + " d=" + _cs_dec(raft_msg_d(m));
  out = out + " e=" + _cs_dec(raft_msg_e(m)) + "]";
  return out;
}

// --------------------------------------------------
//  Pending reply record
// --------------------------------------------------

// Store an outbound reply record.
fn _cs_reply_set(kind: Int, from: Int, to: Int, term: Int, a: Int, b: Int) {
  _cs_reply_kind = kind;
  _cs_reply_from = from;
  _cs_reply_to = to;
  _cs_reply_term = term;
  _cs_reply_a = a;
  _cs_reply_b = b;
  _cs_reply_c = 0;
  _cs_reply_d = _CS_NO_ENTRY;
  _cs_reply_e = 0;
  _cs_has_reply = true;
}

/// True when a request handler produced an outbound reply since the last
/// raft_clear_pending_reply. Complexity: O(1).
pub fn raft_has_pending_reply() -> Bool {
  _cs_ensure();
  return _cs_has_reply;
}

/// Drop the pending reply (the record becomes kind 0). Complexity: O(1).
pub fn raft_clear_pending_reply() {
  _cs_ensure();
  _cs_has_reply = false;
  _cs_reply_kind = 0;
}

/// The pending outbound reply as a message record; a kind-0 empty message
/// when there is none. The request handlers (RequestVote, AppendEntries) set
/// it; the reply handlers do not. Complexity: O(1).
pub fn raft_pending_reply() -> RaftMessage {
  _cs_ensure();
  if !_cs_has_reply {
    return raft_msg_empty();
  }
  return _cs_msg(_cs_reply_kind, _cs_reply_from, _cs_reply_to, _cs_reply_term, _cs_reply_a, _cs_reply_b, _cs_reply_c, _cs_reply_d, _cs_reply_e);
}

// --------------------------------------------------
//  Message handlers
// --------------------------------------------------

/// Handle a RequestVote at its recipient: adopt a higher term (clearing the
/// vote), reject a stale term, then grant when the recipient has not voted in
/// this term and the candidate's log is at least as up to date. Stores a
/// RequestVote-reply in the pending reply slot.
/// Returns: 1 handled (reply generated), 0 stale term (reply still
/// generated), -1 unknown recipient or sender id.
/// Complexity: O(nodes).
pub fn raft_handle_request_vote(m: RaftMessage) -> Int {
  _cs_ensure();
  let to: Int = m.to;
  let from: Int = m.from;
  if to < 0 || to >= _cs_n {
    return _CS_DELIVER_UNKNOWN;
  }
  if from < 0 || from >= _cs_n {
    return _CS_DELIVER_UNKNOWN;
  }
  let mterm: Int = m.term;
  let cur: Int = _cs_term[to];
  if mterm < cur {
    _cs_reply_set(_CS_MSG_REQUEST_VOTE_REPLY, to, from, cur, 0, 0);
    _cs_trace_ev("reject id=" + _cs_dec(to) + " term=" + _cs_dec(mterm) + " cand=" + _cs_dec(from));
    return _CS_DELIVER_STALE;
  }
  if mterm > cur {
    _cs_adopt_term(to, mterm);
  }
  let cli: Int = m.a;
  let clt: Int = m.b;
  let olt: Int = raft_node_last_log_term(to);
  let oli: Int = _cs_log_len[to];
  var up = false;
  if clt > olt {
    up = true;
  } else {
    if clt == olt && cli >= oli {
      up = true;
    }
  }
  let vt: Int = _cs_voted_for[to];
  var granted = 0;
  if up && (vt == _CS_NONE || vt == from) {
    _cs_voted_for[to] = from;
    granted = 1;
  }
  _cs_reply_set(_CS_MSG_REQUEST_VOTE_REPLY, to, from, mterm, granted, 0);
  if granted == 1 {
    _cs_trace_ev("grant id=" + _cs_dec(to) + " term=" + _cs_dec(mterm) + " cand=" + _cs_dec(from));
  } else {
    _cs_trace_ev("deny id=" + _cs_dec(to) + " term=" + _cs_dec(mterm) + " cand=" + _cs_dec(from));
  }
  return _CS_DELIVER_HANDLED;
}

/// Handle a RequestVote reply at the candidate: adopt a higher term (and do
/// not count the vote), ignore a stale term, ignore a reply when not a
/// candidate, otherwise record the grant (once per candidate/voter/term) and
/// promote to leader on a majority.
/// Returns: 1 handled, 0 stale term, -1 unknown ids.
/// Complexity: O(nodes).
pub fn raft_handle_request_vote_reply(m: RaftMessage) -> Int {
  _cs_ensure();
  let to: Int = m.to;
  let from: Int = m.from;
  if to < 0 || to >= _cs_n {
    return _CS_DELIVER_UNKNOWN;
  }
  if from < 0 || from >= _cs_n {
    return _CS_DELIVER_UNKNOWN;
  }
  let mterm: Int = m.term;
  let cur: Int = _cs_term[to];
  if mterm > cur {
    _cs_adopt_term(to, mterm);
    return _CS_DELIVER_HANDLED;
  }
  if mterm < cur {
    return _CS_DELIVER_STALE;
  }
  let role: Int = _cs_role[to];
  if role != _CS_ROLE_CANDIDATE {
    return _CS_DELIVER_HANDLED;
  }
  let granted: Int = m.a;
  if granted != 1 {
    _cs_trace_ev("vote_denied id=" + _cs_dec(to) + " voter=" + _cs_dec(from));
    return _CS_DELIVER_HANDLED;
  }
  _cs_votes[to * _cs_n + from] = mterm;
  let cnt = _cs_vote_count(to);
  _cs_trace_ev("vote id=" + _cs_dec(to) + " voter=" + _cs_dec(from) + " count=" + _cs_dec(cnt));
  if cnt >= raft_quorum_size(_cs_n) {
    _cs_promote(to);
  }
  return _CS_DELIVER_HANDLED;
}

/// Handle an AppendEntries at its recipient: reject a stale term, adopt a
/// higher term, become a follower and remember the leader, run the previous-
/// entry consistency check, truncate a conflicting suffix, append the carried
/// entry, and advance the commit index to min(leader commit, index of the
/// last entry in this message). Stores an AppendEntries-reply.
/// Returns: 1 handled (including a consistency failure, which replies
/// success 0), 0 stale term, -1 unknown ids.
/// Complexity: O(1).
pub fn raft_handle_append_entries(m: RaftMessage) -> Int {
  _cs_ensure();
  let to: Int = m.to;
  let from: Int = m.from;
  if to < 0 || to >= _cs_n {
    return _CS_DELIVER_UNKNOWN;
  }
  if from < 0 || from >= _cs_n {
    return _CS_DELIVER_UNKNOWN;
  }
  let mterm: Int = m.term;
  let cur: Int = _cs_term[to];
  if mterm < cur {
    let lfail: Int = _cs_log_len[to];
    _cs_reply_set(_CS_MSG_APPEND_ENTRIES_REPLY, to, from, cur, 0, lfail);
    _cs_trace_ev("ae_stale id=" + _cs_dec(to) + " from=" + _cs_dec(from) + " term=" + _cs_dec(mterm));
    return _CS_DELIVER_STALE;
  }
  if mterm > cur {
    _cs_adopt_term(to, mterm);
  }
  _cs_role[to] = _CS_ROLE_FOLLOWER;
  _cs_leader_id[to] = from;
  let prev: Int = m.a;
  let pterm: Int = m.b;
  let len: Int = _cs_log_len[to];
  var consistent = false;
  if prev >= 0 && prev <= len {
    if prev == 0 {
      consistent = true;
    } else {
      let t: Int = _cs_log_term_at(to, prev);
      if t == pterm {
        consistent = true;
      }
    }
  }
  if !consistent {
    _cs_reply_set(_CS_MSG_APPEND_ENTRIES_REPLY, to, from, mterm, 0, len);
    _cs_trace_ev("ae_fail id=" + _cs_dec(to) + " from=" + _cs_dec(from) + " prev=" + _cs_dec(prev));
    return _CS_DELIVER_HANDLED;
  }
  let d: Int = m.d;
  if d >= 0 {
    let idx = prev + 1;
    let l2: Int = _cs_log_len[to];
    if l2 >= idx {
      let et: Int = _cs_log_term_at(to, idx);
      if et != d {
        _cs_log_len[to] = prev;
        _cs_trace_ev("truncate id=" + _cs_dec(to) + " index=" + _cs_dec(idx));
      }
    }
    let l3: Int = _cs_log_len[to];
    if l3 == prev {
      let slot = _cs_slot(to, idx);
      _cs_log_term[slot] = d;
      _cs_log_cmd[slot] = m.e;
      _cs_log_len[to] = idx;
    }
  }
  let lc: Int = m.c;
  let cl: Int = _cs_commit[to];
  if lc > cl {
    var bound = prev;
    if d >= 0 {
      bound = prev + 1;
    }
    var nc = lc;
    let l4: Int = _cs_log_len[to];
    if nc > l4 {
      nc = l4;
    }
    if nc > bound {
      nc = bound;
    }
    if nc > cl {
      _cs_commit[to] = nc;
      _cs_trace_ev("commit id=" + _cs_dec(to) + " index=" + _cs_dec(nc));
    }
  }
  let ml: Int = _cs_log_len[to];
  _cs_reply_set(_CS_MSG_APPEND_ENTRIES_REPLY, to, from, mterm, 1, ml);
  _cs_trace_ev("ae id=" + _cs_dec(to) + " from=" + _cs_dec(from) + " match=" + _cs_dec(ml));
  return _CS_DELIVER_HANDLED;
}

/// Handle an AppendEntries reply at the leader: adopt a higher term (stepping
/// down), ignore a stale term or a reply when not a leader, on success raise
/// the follower match index, set next = match + 1 and advance the commit
/// index, on failure back the follower next index off to match + 1 (at least
/// 1).
/// Returns: 1 handled, 0 stale term, -1 unknown ids.
/// Complexity: O(log length * nodes).
pub fn raft_handle_append_entries_reply(m: RaftMessage) -> Int {
  _cs_ensure();
  let to: Int = m.to;
  let from: Int = m.from;
  if to < 0 || to >= _cs_n {
    return _CS_DELIVER_UNKNOWN;
  }
  if from < 0 || from >= _cs_n {
    return _CS_DELIVER_UNKNOWN;
  }
  let mterm: Int = m.term;
  let cur: Int = _cs_term[to];
  if mterm > cur {
    _cs_adopt_term(to, mterm);
    return _CS_DELIVER_HANDLED;
  }
  if mterm < cur {
    return _CS_DELIVER_STALE;
  }
  let role: Int = _cs_role[to];
  if role != _CS_ROLE_LEADER {
    return _CS_DELIVER_HANDLED;
  }
  let success: Int = m.a;
  if success == 1 {
    let mm: Int = m.b;
    let old: Int = _cs_match[from];
    if mm > old {
      _cs_match[from] = mm;
    }
    let m2: Int = _cs_match[from];
    _cs_next[from] = m2 + 1;
    _cs_trace_ev("ack leader=" + _cs_dec(to) + " follower=" + _cs_dec(from) + " match=" + _cs_dec(m2));
    _cs_commit_advance(to);
  } else {
    var nm: Int = m.b + 1;
    if nm < 1 {
      nm = 1;
    }
    let oldnext: Int = _cs_next[from];
    if nm < oldnext {
      _cs_next[from] = nm;
    }
    let nn: Int = _cs_next[from];
    _cs_trace_ev("backoff leader=" + _cs_dec(to) + " follower=" + _cs_dec(from) + " next=" + _cs_dec(nn));
  }
  return _CS_DELIVER_HANDLED;
}

/// Build the next AppendEntries record a leader would send to one follower
/// from its replication cursor: prev = next - 1, the leader's commit index,
/// and the entry at next when one exists (otherwise a heartbeat). Also
/// records a trace line.
/// Returns: the record, or a kind-0 empty message when either id is out of
/// range. Complexity: O(1).
pub fn raft_msg_from_leader(leader: Int, follower: Int) -> RaftMessage {
  _cs_ensure();
  if leader < 0 || leader >= _cs_n {
    return raft_msg_empty();
  }
  if follower < 0 || follower >= _cs_n {
    return raft_msg_empty();
  }
  var ni: Int = _cs_next[follower];
  if ni < 1 {
    ni = 1;
  }
  let len: Int = _cs_log_len[leader];
  let t: Int = _cs_term[leader];
  let lc: Int = _cs_commit[leader];
  let prev = ni - 1;
  var pterm = 0;
  if prev > 0 && prev <= len {
    let pt: Int = _cs_log_term_at(leader, prev);
    if pt >= 0 {
      pterm = pt;
    }
  }
  if ni <= len {
    let et: Int = _cs_log_term_at(leader, ni);
    let ec: Int = _cs_log_cmd_at(leader, ni);
    _cs_trace_ev("replicate from=" + _cs_dec(leader) + " to=" + _cs_dec(follower) + " prev=" + _cs_dec(prev) + " entry=" + _cs_dec(ni));
    return _cs_msg(_CS_MSG_APPEND_ENTRIES, leader, follower, t, prev, pterm, lc, et, ec);
  }
  _cs_trace_ev("heartbeat from=" + _cs_dec(leader) + " to=" + _cs_dec(follower) + " prev=" + _cs_dec(prev));
  return _cs_msg(_CS_MSG_APPEND_ENTRIES, leader, follower, t, prev, pterm, lc, _CS_NO_ENTRY, 0);
}

/// Deliver a message record to its recipient, dispatching on kind to the
/// matching handler.
/// Returns: the handler's outcome (1 handled, 0 stale term, -1 unknown kind
/// or unknown ids). Complexity: O(nodes).
pub fn raft_deliver(m: RaftMessage) -> Int {
  _cs_ensure();
  let k: Int = m.kind;
  if k == _CS_MSG_REQUEST_VOTE {
    return raft_handle_request_vote(m);
  }
  if k == _CS_MSG_REQUEST_VOTE_REPLY {
    return raft_handle_request_vote_reply(m);
  }
  if k == _CS_MSG_APPEND_ENTRIES {
    return raft_handle_append_entries(m);
  }
  if k == _CS_MSG_APPEND_ENTRIES_REPLY {
    return raft_handle_append_entries_reply(m);
  }
  return _CS_DELIVER_UNKNOWN;
}

// --------------------------------------------------
//  Safety invariants
// --------------------------------------------------

// Every vote is for a valid node or absent.
fn _cs_inv_vote_bounds() -> Bool {
  var ok = true;
  var i = 0;
  while i < _cs_n {
    let v: Int = _cs_voted_for[i];
    if v < -1 || v >= _cs_n {
      ok = false;
    }
    i = i + 1;
  }
  return ok;
}

// Every recorded vote grant is stamped with a term no later than the current
// terms of both parties.
fn _cs_inv_grant_terms() -> Bool {
  var ok = true;
  var i = 0;
  while i < _cs_n {
    var j = 0;
    while j < _cs_n {
      let g: Int = _cs_votes[i * _cs_n + j];
      if g > 0 {
        let ti: Int = _cs_term[i];
        let tj: Int = _cs_term[j];
        if g > ti || g > tj {
          ok = false;
        }
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return ok;
}

// At most one node became leader in any single term.
fn _cs_inv_leader_unique() -> Bool {
  var ok = true;
  var i = 0;
  while i < _cs_n {
    let lt: Int = _cs_leader_term[i];
    if lt > 0 {
      var j = i + 1;
      while j < _cs_n {
        let lt2: Int = _cs_leader_term[j];
        if lt2 == lt {
          ok = false;
        }
        j = j + 1;
      }
    }
    i = i + 1;
  }
  return ok;
}

// 0 <= commit <= log length for every node.
fn _cs_inv_commit_bounds() -> Bool {
  var ok = true;
  var i = 0;
  while i < _cs_n {
    let c: Int = _cs_commit[i];
    let l: Int = _cs_log_len[i];
    if c < 0 || c > l {
      ok = false;
    }
    i = i + 1;
  }
  return ok;
}

// Any index committed on one node matches every other node's log at that
// index (state-machine safety).
fn _cs_inv_committed_agree() -> Bool {
  var ok = true;
  var i = 0;
  while i < _cs_n {
    let ci: Int = _cs_commit[i];
    var j = 0;
    while j < _cs_n {
      if j != i {
        let lj: Int = _cs_log_len[j];
        var p = 1;
        while p <= ci {
          if p <= lj {
            let ti = _cs_log_term_at(i, p);
            let tj = _cs_log_term_at(j, p);
            if ti != tj {
              ok = false;
            }
            let c1 = _cs_log_cmd_at(i, p);
            let c2 = _cs_log_cmd_at(j, p);
            if c1 != c2 {
              ok = false;
            }
          }
          p = p + 1;
        }
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return ok;
}

// Log matching: wherever two logs carry the same term at the same index,
// both prefixes up to that index are identical.
fn _cs_inv_log_matching() -> Bool {
  var ok = true;
  var i = 0;
  while i < _cs_n {
    var j = i + 1;
    while j < _cs_n {
      let li: Int = _cs_log_len[i];
      let lj: Int = _cs_log_len[j];
      var m = li;
      if lj < m {
        m = lj;
      }
      var p = 1;
      while p <= m && ok {
        let ti = _cs_log_term_at(i, p);
        let tj = _cs_log_term_at(j, p);
        if ti == tj {
          var q = 1;
          while q <= p && ok {
            let t1 = _cs_log_term_at(i, q);
            let t2 = _cs_log_term_at(j, q);
            if t1 != t2 {
              ok = false;
            }
            if ok {
              let c1 = _cs_log_cmd_at(i, q);
              let c2 = _cs_log_cmd_at(j, q);
              if c1 != c2 {
                ok = false;
              }
            }
            q = q + 1;
          }
        }
        p = p + 1;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return ok;
}

// Terms are non-negative and a leader term never exceeds the node term.
fn _cs_inv_term_sanity() -> Bool {
  var ok = true;
  var i = 0;
  while i < _cs_n {
    let t: Int = _cs_term[i];
    let lt: Int = _cs_leader_term[i];
    if t < 0 {
      ok = false;
    }
    if lt < 0 || lt > t {
      ok = false;
    }
    i = i + 1;
  }
  return ok;
}

/// Check the seven safety invariants in order and return the code of the
/// first violation (101 vote bounds, 102 vote grant terms, 103 one leader per
/// term, 104 commit bounds, 105 committed-log agreement, 106 log matching,
/// 107 term sanity); 0 when all hold. Complexity: O(nodes^2 * log length^2)
/// worst case.
pub fn raft_invariants_check() -> Int {
  _cs_ensure();
  if !_cs_inv_vote_bounds() {
    return _CS_INV_VOTE_BOUNDS;
  }
  if !_cs_inv_grant_terms() {
    return _CS_INV_GRANT_TERMS;
  }
  if !_cs_inv_leader_unique() {
    return _CS_INV_LEADER_UNIQUE;
  }
  if !_cs_inv_commit_bounds() {
    return _CS_INV_COMMIT_BOUNDS;
  }
  if !_cs_inv_committed_agree() {
    return _CS_INV_COMMITTED_AGREE;
  }
  if !_cs_inv_log_matching() {
    return _CS_INV_LOG_MATCHING;
  }
  if !_cs_inv_term_sanity() {
    return _CS_INV_TERM_SANITY;
  }
  return 0;
}

/// One-line invariant report for tests:
/// `invariants[vote_bounds=ok grant_terms=ok one_leader_per_term=ok
/// commit_bounds=ok committed_agreement=ok log_matching=ok term_sanity=ok]`.
/// Complexity: O(nodes^2 * log length^2).
pub fn raft_invariants_report() -> Str {
  _cs_ensure();
  var out = "invariants[vote_bounds=";
  if _cs_inv_vote_bounds() { out = out + "ok"; } else { out = out + "FAIL"; }
  out = out + " grant_terms=";
  if _cs_inv_grant_terms() { out = out + "ok"; } else { out = out + "FAIL"; }
  out = out + " one_leader_per_term=";
  if _cs_inv_leader_unique() { out = out + "ok"; } else { out = out + "FAIL"; }
  out = out + " commit_bounds=";
  if _cs_inv_commit_bounds() { out = out + "ok"; } else { out = out + "FAIL"; }
  out = out + " committed_agreement=";
  if _cs_inv_committed_agree() { out = out + "ok"; } else { out = out + "FAIL"; }
  out = out + " log_matching=";
  if _cs_inv_log_matching() { out = out + "ok"; } else { out = out + "FAIL"; }
  out = out + " term_sanity=";
  if _cs_inv_term_sanity() { out = out + "ok"; } else { out = out + "FAIL"; }
  out = out + "]";
  return out;
}

// --------------------------------------------------
//  Raw test probes (bypass the replication rules)
// --------------------------------------------------

/// Raw probe: store a commit index directly, without the log-length bound,
/// so raft_invariants_check can be driven to its commit-bounds failure path.
/// Returns false when the node id is out of range or index < 0.
/// Complexity: O(1).
pub fn raft_force_commit(id: Int, index: Int) -> Bool {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return false;
  }
  if index < 0 {
    return false;
  }
  _cs_commit[id] = index;
  _cs_trace_ev("force_commit id=" + _cs_dec(id) + " index=" + _cs_dec(index));
  return true;
}

/// Raw probe: write one log entry directly at a 1-based index (extending the
/// log length when needed), without the consistency or term rules, so
/// raft_invariants_check can be driven to its log-order failure paths.
/// Returns false when the node id is out of range or index is outside
/// 1..raft_log_capacity(). Complexity: O(1).
pub fn raft_force_entry(id: Int, index: Int, term: Int, cmd: Int) -> Bool {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return false;
  }
  if index < 1 || index > _CS_LOG_CAP {
    return false;
  }
  let slot = _cs_slot(id, index);
  _cs_log_term[slot] = term;
  _cs_log_cmd[slot] = cmd;
  let len: Int = _cs_log_len[id];
  if index > len {
    _cs_log_len[id] = index;
  }
  _cs_trace_ev("force_entry id=" + _cs_dec(id) + " index=" + _cs_dec(index) + " term=" + _cs_dec(term) + " cmd=" + _cs_dec(cmd));
  return true;
}

// --------------------------------------------------
//  Dumps and traces
// --------------------------------------------------

/// One-line node dump for tests:
/// `node[id=.. role=.. term=.. voted=.. commit=.. loglen=.. leader=.. next=..
/// match=.. log=t1:c1,t2:c2]`; `node[invalid]` for an out-of-range id.
/// Complexity: O(log length).
pub fn raft_node_dump(id: Int) -> Str {
  _cs_ensure();
  if id < 0 || id >= _cs_n {
    return "node[invalid]";
  }
  let term: Int = _cs_term[id];
  let voted: Int = _cs_voted_for[id];
  let commit: Int = _cs_commit[id];
  let len: Int = _cs_log_len[id];
  let ldr: Int = _cs_leader_id[id];
  let nx: Int = _cs_next[id];
  let mt: Int = _cs_match[id];
  var out = "node[id=" + _cs_dec(id);
  out = out + " role=" + raft_node_role_name(id);
  out = out + " term=" + _cs_dec(term);
  out = out + " voted=" + _cs_dec(voted);
  out = out + " commit=" + _cs_dec(commit);
  out = out + " loglen=" + _cs_dec(len);
  out = out + " leader=" + _cs_dec(ldr);
  out = out + " next=" + _cs_dec(nx);
  out = out + " match=" + _cs_dec(mt);
  out = out + " log=";
  var i = 1;
  while i <= len {
    if i > 1 {
      out = out + ",";
    }
    let t: Int = _cs_log_term_at(id, i);
    let c: Int = _cs_log_cmd_at(id, i);
    out = out + _cs_dec(t) + ":" + _cs_dec(c);
    i = i + 1;
  }
  out = out + "]";
  return out;
}

/// All node dumps joined with newlines, in node-id order.
/// Complexity: O(nodes * log length).
pub fn raft_dump() -> Str {
  _cs_ensure();
  var out = "";
  var i = 0;
  while i < _cs_n {
    if i > 0 {
      out = out + "\n";
    }
    out = out + raft_node_dump(i);
    i = i + 1;
  }
  return out;
}

/// True when trace recording is on (it starts on and raft_configure resets it
/// to on). Complexity: O(1).
pub fn raft_trace_is_enabled() -> Bool {
  _cs_ensure();
  return _cs_trace_on;
}

/// Turn trace recording on or off. Complexity: O(1).
pub fn raft_trace_enable(on: Bool) {
  _cs_ensure();
  _cs_trace_on = on;
}

/// Drop all recorded trace lines. Complexity: O(1).
pub fn raft_trace_clear() {
  _cs_ensure();
  _cs_trace_text = "";
  _cs_trace_start.clear();
  _cs_trace_n = 0;
}

/// Number of recorded trace lines. Complexity: O(1).
pub fn raft_trace_count() -> Int {
  _cs_ensure();
  return _cs_trace_n;
}

/// Recorded trace line at a 0-based position; "" when out of range.
/// Complexity: O(1).
pub fn raft_trace_line(i: Int) -> Str {
  _cs_ensure();
  if i < 0 || i >= _cs_trace_n {
    return "";
  }
  let start: Int = _cs_trace_start[i];
  var end = str_len(_cs_trace_text);
  if i + 1 < _cs_trace_n {
    let ns: Int = _cs_trace_start[i + 1];
    end = ns - 1;
  }
  return str_slice(_cs_trace_text, start, end);
}

/// All recorded trace lines joined with newlines. Complexity: O(1).
pub fn raft_trace_dump() -> Str {
  _cs_ensure();
  return _cs_trace_text;
}

// --------------------------------------------------
//  Error catalog
// --------------------------------------------------

/// Pinned message for a ConsensusError or invariant code; "consensus: unknown
/// error" outside the catalog. Complexity: O(1).
pub fn raft_error_message(code: Int) -> Str {
  if code == _CS_ERR_NODE_RANGE {
    return "consensus: node id out of range";
  }
  if code == _CS_ERR_NODE_COUNT {
    return "consensus: node count out of range";
  }
  if code == _CS_ERR_NOT_ELECTABLE {
    return "consensus: node cannot start an election in its current role";
  }
  if code == _CS_ERR_NOT_LEADER {
    return "consensus: operation requires the leader role";
  }
  if code == _CS_ERR_LOG_FULL {
    return "consensus: node log capacity exhausted";
  }
  if code == _CS_INV_VOTE_BOUNDS {
    return "consensus: invariant violated: vote bounds";
  }
  if code == _CS_INV_GRANT_TERMS {
    return "consensus: invariant violated: vote grant terms";
  }
  if code == _CS_INV_LEADER_UNIQUE {
    return "consensus: invariant violated: one leader per term";
  }
  if code == _CS_INV_COMMIT_BOUNDS {
    return "consensus: invariant violated: commit index bounds";
  }
  if code == _CS_INV_COMMITTED_AGREE {
    return "consensus: invariant violated: committed log agreement";
  }
  if code == _CS_INV_LOG_MATCHING {
    return "consensus: invariant violated: log matching prefix";
  }
  if code == _CS_INV_TERM_SANITY {
    return "consensus: invariant violated: term sanity";
  }
  return "consensus: unknown error";
}
