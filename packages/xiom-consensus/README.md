# xiom.consensus

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.0` on the XIOM registry.
> **Scope:** deterministic, caller-driven Raft-style consensus model: terms and
> explicit-vote elections with quorum math, log replication with next/match/commit
> indices, leader/follower/candidate transitions, message records, a safety-invariant
> checker and deterministic traces. A semantic model, not a runtime: no threads,
> no timers, no clock, no FFI.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.convert.int`). Tests
> additionally use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`.

## What it is

`xiom.consensus` models a small Raft cluster (1..8 nodes) in a single
deterministic thread of control. It never spawns a thread, never reads a clock,
never uses a timer and never calls FFI. The caller drives every step explicitly:

1. configure a cluster (`raft_configure`),
2. start an election (`raft_election_start`) and pass RequestVote *records*
   between nodes (`raft_deliver`), reading each reply with
   `raft_pending_reply` and delivering it back,
3. append commands on the leader (`raft_leader_append`) and replicate one entry
   at a time with the AppendEntries record built from the leader view
   (`raft_msg_from_leader`),
4. watch `raft_match_index` / `raft_next_index` and the commit index advance by
   majority (`raft_commit_advance`), and
5. check the seven safety invariants (`raft_invariants_check`) and inspect the
   deterministic trace (`raft_trace_dump`).

Because the caller drives every step, elections, vote splits, term bumps, log
divergence and repair are all reproducible fixtures rather than races. The model
demonstrates Raft's election restriction, one-vote-per-term rule, majority
promotion, previous-entry consistency check, conflicting-suffix truncation,
next-index backoff and current-term commit rule, but it does **not** provide
timeouts, retries, real interleavings, persistence or a network. See `SPEC.md`
for the full semantics and the test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `raft_configure(nodes)` | `Result[Int, ConsensusError]` | Full reset; node count 1..8 (`Err` code 2 otherwise). |
| `raft_node_count()/` `raft_max_nodes()/` `raft_log_capacity()` | `Int` | Cluster geometry (max 8 nodes, 64 log entries per node). |
| `raft_quorum_size(n)/` `raft_has_majority(votes, n)` | `Int`/`Bool` | Majority = `n / 2 + 1`. |
| `raft_election_start(id)` | `Result[Int, ConsensusError]` | Increment term, self-vote, become candidate; single-node cluster promotes at once. `Err` 1/3. |
| `raft_election_vote_count(id)/` `raft_election_has_quorum(id)` | `Int`/`Bool` | Distinct current-term grants (self included) and majority test. |
| `raft_node_role(id)/` `raft_node_role_name(id)` | `Int`/`Str` | 0 follower / 1 candidate / 2 leader, and its name. |
| `raft_node_term(id)/` `raft_node_voted_for(id)/` `raft_node_commit(id)/` `raft_node_leader_id(id)` | `Int` | Persistent/volatile per-node state (`-1` when absent or out of range). |
| `raft_node_log_len(id)/` `raft_node_last_log_term(id)/` `raft_node_log_term(id, i)/` `raft_node_log_cmd(id, i)` | `Int` | 1-based log accessors; index 0 is the empty prefix, out-of-range is `-1`. |
| `raft_next_index(id)/` `raft_match_index(id)` | `Int` | Leader-side replication cursors for a follower. |
| `raft_leader_append(id, cmd)` | `Result[Int, ConsensusError]` | Append at the next index; `Ok(index)`. `Err` 1/4/5. |
| `raft_commit_advance(id)` | `Result[Int, ConsensusError]` | Recompute commit by majority of matches; only current-term entries count. `Err` 1/4. |
| `raft_msg_request_vote(from, to, term, last_index, last_term)` | `RaftMessage` | RequestVote record. |
| `raft_msg_request_vote_reply(from, to, term, granted)` | `RaftMessage` | RequestVote reply record. |
| `raft_msg_append_entries(from, to, term, prev_index, prev_term, leader_commit)` | `RaftMessage` | AppendEntries heartbeat record. |
| `raft_msg_append_entry(from, to, term, prev_index, prev_term, leader_commit, entry_term, entry_cmd)` | `RaftMessage` | AppendEntries record carrying one entry. |
| `raft_msg_append_entries_reply(from, to, term, success, match_index)` | `RaftMessage` | AppendEntries reply record. |
| `raft_msg_empty()/` `raft_msg_kind(m)/` `raft_msg_kind_name(m)/` `raft_msg_from/to/term/a/b/c/d/e(m)` | various | Record constructors, decoders and kind names. |
| `raft_msg_dump(m)` | `Str` | One-line record dump for tests. |
| `raft_msg_from_leader(leader, follower)` | `RaftMessage` | Next AppendEntries from the leader's replication cursor. |
| `raft_deliver(m)` | `Int` | Dispatch a record to its handler: `1` handled, `0` stale term, `-1` unknown. |
| `raft_handle_request_vote(m)/` `raft_handle_request_vote_reply(m)/` `raft_handle_append_entries(m)/` `raft_handle_append_entries_reply(m)` | `Int` | Direct handler entry points (same outcome codes). |
| `raft_pending_reply()/` `raft_has_pending_reply()/` `raft_clear_pending_reply()` | `RaftMessage`/`Bool`/`Unit` | The outbound reply a request handler produced. |
| `raft_invariants_check()` | `Int` | `0` or the first violated invariant code (101..107). |
| `raft_invariants_report()` | `Str` | One-line `name=ok/FAIL` report for all seven invariants. |
| `raft_force_commit(id, i)/` `raft_force_entry(id, i, term, cmd)` | `Bool` | Raw probes that bypass the rules, to drive the checker's failure paths. |
| `raft_node_dump(id)/` `raft_dump()` | `Str` | Per-node and whole-cluster dumps. |
| `raft_trace_enable(on)/` `raft_trace_is_enabled()/` `raft_trace_clear()/` `raft_trace_count()/` `raft_trace_line(i)/` `raft_trace_dump()` | various | Deterministic event trace. |
| `raft_error_message(code)` | `Str` | Pinned error/invariant catalog text. |

Every `ConsensusError` carries `(code, value, extra)`: `value` is the offending
input (`-1` when none), `extra` is the bound or context (`-1` when none). Failed
operations change no state.

## Usage

```xi
use xiom.consensus;
use xiom.io;
use xiom.convert.int;

fn main() -> Int {
  match raft_configure(3) {
    Ok(n) => { io.println("cluster of " + int_to_base(n, 10)); },
    Err(e) => { io.println(raft_error_message(e.code)); },
  }
  // Node 0 campaigns in term 1; node 1 grants; node 0 becomes leader.
  match raft_election_start(0) {
    Ok(term) => {
      let req = raft_msg_request_vote(0, 1, term, 0, 0);
      if raft_deliver(req) == 1 {
        let reply = raft_pending_reply();
        if raft_deliver(reply) == 1 {
          io.println(raft_node_role_name(0));          // "leader"
        }
      }
    },
    Err(e) => { io.println(raft_error_message(e.code)); },
  }
  // Append and replicate one entry.
  match raft_leader_append(0, 42) {
    Ok(index) => {
      let m = raft_msg_from_leader(0, 1);
      if raft_deliver(m) == 1 {
        let ack = raft_pending_reply();
        if raft_deliver(ack) == 1 {
          io.println(raft_node_dump(0));
          // node[id=0 role=leader term=1 ... commit=1 loglen=1 ... log=1:42]
        }
      }
      io.println(int_to_base(index, 10));              // 1
    },
    Err(e) => { io.println(raft_error_message(e.code)); },
  }
  io.println(int_to_base(raft_invariants_check(), 10)); // 0
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.consensus
```

Expected tail: 20 `[PASS]` lines, `xiom.consensus: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`. Every fixture is built
in-test (`raft_configure` is a full reset), so the suite is order-independent.
See `SPEC.md` section 8 for the coverage map.

## Limitations

- **Deterministic model only.** No threads, no timers, no clock, no network,
  no FFI. The caller drives every message delivery; there is no timeout or
  automatic retry.
- **One global cluster.** State is module-level (parallel `Vec[Int]` fields),
  so there is exactly one cluster per process; `raft_configure` is a full
  reset, not a resize.
- **One entry per AppendEntries.** Replication carries a single entry (or is a
  heartbeat), built by `raft_msg_from_leader`; batches are out of scope.
- **Fixed log capacity.** 64 entries per node; `raft_leader_append` returns
  `Err` code 5 when the log is full. Log compaction/snapshots are out of scope.
- **No persistence.** Terms, votes and logs live in memory only; restarts are
  not modeled.
- **Leader-view cursors are shared.** `_cs_next`/`_cs_match` hold the most
  recently promoted leader's view. The model permits at most one leader per
  term (an invariant), so a split-brain state is not reachable through the API.
- **Invariant checker is structural, not a proof.** It checks the states the
  model can reach plus the raw force-probe states; it is not a machine-checked
  refinement proof.
- **Dump/trace formats are test-facing** and may gain fields; tests match
  fragments, not whole lines, except where the format is pinned.

See `SPEC.md` for the full semantics, the error catalog and the test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
