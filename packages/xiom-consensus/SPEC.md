# xiom.consensus -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.consensus` (`src/consensus.xi`). Pure XIOM, no FFI.

## 1. Scope

A deterministic, caller-driven model of a small Raft cluster:

- persistent per-node state: current term, voted-for, log (parallel
  `Vec[Int]` term/command arrays in a flat slab);
- explicit-vote elections with the Raft election restriction and quorum math;
- follower / candidate / leader transitions, including higher-term step-down;
- log replication: leader append, per-follower next/match indices,
  one-entry AppendEntries, previous-entry consistency check,
  conflicting-suffix truncation, next-index backoff, and commit advance by
  majority (current-term entries only);
- message records (`RaftMessage`) for RequestVote, RequestVote reply,
  AppendEntries (heartbeat or one entry) and AppendEntries reply;
- a seven-check safety-invariants checker plus raw force probes;
- a deterministic event trace.

The module never spawns a thread, never reads a clock, never uses a timer and
never calls FFI. Every message delivery is a caller call; there is no timeout
and no automatic retry.

## 2. Non-goals

- Real threads, atomics, networking or interleaving; timeouts, retries,
  liveness, election timers.
- Persistence, restarts, snapshots or log compaction.
- Batched AppendEntries (the model carries at most one entry per message).
- Dynamic membership changes, learners, pre-vote or joint consensus.
- Multiple clusters per process; ffI.

## 3. Cluster and state

`raft_configure(nodes)` validates `1 <= nodes <= raft_max_nodes()` (max 8) and
performs a full reset: every node becomes a follower in term 0 with no vote,
commit 0, an empty log and next = 1 / match = 0; the vote matrix and the trace
are cleared. A failed configure leaves the previous cluster untouched. The
default cluster (3 nodes) is built lazily on first use.

Per-node state vectors: `term`, `voted_for` (-1 none), `role` (0 follower,
1 candidate, 2 leader), `commit`, `leader_id` (-1 none), `log_len`,
`leader_term` (term in which the node last became leader, 0 never), and the
leader view `next`/`match`. Logs live in a flat slab of `nodes * 64` Ints:
entry `i` (1-based) of node `id` is at slot `id * 64 + (i - 1)`. Votes live in
a flat `nodes * nodes` matrix: slot `candidate * nodes + voter` holds the term
in which that voter's grant was counted (0 none).

## 4. Quorum math

```
raft_quorum_size(n)   = n / 2 + 1        (0 for n <= 0)
raft_has_majority(v,n)= v >= raft_quorum_size(n)
```

A candidate holds a majority when `raft_election_vote_count(id)` reaches
`raft_quorum_size(nodes)`. The vote count is the number of distinct voters
(including the self-vote) whose recorded grant term equals the candidate's
current term.

## 5. Elections

### 5.1 Start

`raft_election_start(id)`: error code 1 for an out-of-range id, code 3 when the
node is already a leader. Otherwise the node increments its term, votes for
itself, becomes a candidate, clears its known leader, records the self-vote in
the matrix, and — when the self-vote alone is a majority (single-node cluster)
— promotes itself to leader immediately. Returns `Ok(new term)`.

### 5.2 RequestVote handling

`raft_handle_request_vote(m)` at recipient `to` from candidate `from` in term
`m.term`:

1. `m.term < current`: reject, reply term = current, granted = 0 (outcome 0,
   stale).
2. `m.term > current`: adopt the term (clear the vote, become follower,
   forget the leader).
3. Grant when `voted_for` is -1 or already `from`, **and** the candidate log is
   at least as up to date: `last_log_term(from) > last_log_term(to)`, or equal
   terms and `last_log_index(from) >= last_log_index(to)`. On grant store
   `voted_for = from`.
4. Store a RequestVote reply (`from = to`, `to = from`, `term = message term`,
   `a = granted`); outcome 1.

### 5.3 RequestVote-reply handling

`raft_handle_request_vote_reply(m)` at candidate `to`:

- reply term > current: adopt the term, do not count the vote (outcome 1);
- reply term < current: ignore (outcome 0, stale);
- equal term, not a candidate: ignore (outcome 1);
- equal term, not granted: ignore (outcome 1);
- equal term and granted: record `votes[to * n + from] = term`, count the
  distinct grants, and promote to leader when the count reaches a majority.

### 5.4 Promotion

`_cs_promote(id)` sets the role to leader, records `leader_term = current term`
and sets every follower's cursor to `next = last log index + 1`, `match = 0`.

## 6. Log replication

### 6.1 Leader append

`raft_leader_append(id, cmd)` requires the leader role (code 4 otherwise) and
space in the log (code 5 when 64 entries are present). It stores the command
at index `log_len + 1` with the leader's current term and returns
`Ok(index)`. Commit does not advance here.

### 6.2 Building a message

`raft_msg_from_leader(leader, follower)` reads the follower cursor:
`prev = next - 1` (at least 0); `prev_term = log term at prev` (0 when prev is
0); leader commit = the leader's commit index. When `next <= log_len` the entry
at `next` is added (`d = entry term`, `e = entry command`); otherwise the
message is a heartbeat (`d = -1`). Returns a kind-0 empty message for an
out-of-range id.

### 6.3 AppendEntries handling

`raft_handle_append_entries(m)` at recipient `to` from `from`:

1. `m.term < current`: reply success 0 with `match = log_len` (outcome 0).
2. `m.term > current`: adopt the term. Then become a follower and remember
   `from` as the leader.
3. Consistency: `prev` must be `0 <= prev <= log_len`, and when `prev > 0` the
   local term at `prev` must equal `m.b`. On failure reply success 0 with
   `match = log_len` (outcome 1).
4. When an entry is present (`m.d >= 0`), index `idx = prev + 1`: if an entry
   already exists at `idx` with a different term, truncate the log to `prev`;
   then when `log_len == prev`, append the entry (`term = m.d`,
   `cmd = m.e`). Matching existing entries and a matching longer suffix are
   kept.
5. Commit: when `m.c > commit`, set `commit = min(m.c, log_len, index of the
   last entry in this message)` where the last-entry bound is `prev` for a
   heartbeat and `prev + 1` for an entry-carrying message.
6. Reply success 1 with `match = log_len` (outcome 1).

### 6.4 AppendEntries-reply handling

`raft_handle_append_entries_reply(m)` at leader `to` from follower `from`:

- higher reply term: adopt and step down (outcome 1); lower: ignore (outcome
  0, stale); equal but not a leader: ignore (outcome 1);
- success: `match[from] = max(match[from], m.b)`, `next[from] = match + 1`, then
  recompute the commit index;
- failure: `next[from] = min(next[from], max(1, m.b + 1))`, so the leader
  retries with an earlier `prev` (one-step backoff per reply).

### 6.5 Commit advance

`raft_commit_advance(id)` (and the internal step after a successful reply)
finds the highest index `N > commit` such that the leader's term at `N` equals
its current term and a majority of replica match indices (the leader counted
as its full log length) are `>= N`; it sets `commit = N`. Entries from older
terms are never committed directly; they become committed once a current-term
entry above them commits. `Err` code 4 when the node is not a leader.

## 7. Message records, pending replies, traces, invariants

`RaftMessage` fields and per-kind meaning are documented in the module header:
kind 1 RequestVote (`a` last index, `b` last term), kind 2 RequestVote reply
(`a` granted), kind 3 AppendEntries (`a` prev index, `b` prev term,
`c` leader commit, `d` entry term, `e` entry command; `d = -1` heartbeat),
kind 4 AppendEntries reply (`a` success, `b` match). `raft_deliver` dispatches
on kind: 1 handled, 0 stale term, -1 unknown kind or id. The RequestVote and
AppendEntries handlers store the outbound reply in the pending slot
(`raft_pending_reply`, `raft_has_pending_reply`, `raft_clear_pending_reply`);
reply handlers do not.

Traces record one line per semantic step (`elect`, `adopt`, `grant`, `deny`,
`reject`, `vote`, `vote_denied`, `leader`, `append`, `replicate`, `heartbeat`,
`ae`, `ae_fail`, `ae_stale`, `truncate`, `ack`, `backoff`, `commit`,
`force_commit`, `force_entry`). `raft_configure` clears the trace and turns it
back on.

The invariants checker (`raft_invariants_check` / `raft_invariants_report`)
validates, in order: 101 vote bounds (`voted_for` in {-1} u [0, n)), 102 vote
grant terms (no recorded grant term exceeds either party's current term),
103 one leader per term (distinct non-zero `leader_term` values), 104 commit
bounds (`0 <= commit <= log_len`), 105 committed-log agreement (every index
committed on one node matches every node's log that reaches it), 106 log
matching (equal term at an index implies equal prefixes up to it), 107 term
sanity (non-negative terms, `leader_term <= term`). It returns 0 or the first
violated code. `raft_force_commit` and `raft_force_entry` are raw probes that
bypass the rules so the failure paths are reachable in tests.

## 8. Error catalog

`ConsensusError = { code: Int; value: Int; extra: Int; }`; `raft_error_message`
is pinned:

| Code | Message | Trigger (`value`, `extra`) |
|---|---|---|
| 1 | `consensus: node id out of range` | any operation with an invalid id (`value` = id, `extra` = node count) |
| 2 | `consensus: node count out of range` | `raft_configure` with nodes < 1 or > 8 (`value` = nodes, `extra` = 8) |
| 3 | `consensus: node cannot start an election in its current role` | `raft_election_start` on a leader (`value` = id, `extra` = role) |
| 4 | `consensus: operation requires the leader role` | `raft_leader_append` / `raft_commit_advance` on a non-leader (same fields) |
| 5 | `consensus: node log capacity exhausted` | `raft_leader_append` with 64 entries (`value` = cmd, `extra` = 64) |
| 101..107 | `consensus: invariant violated: ...` | the corresponding checker failure |
| other | `consensus: unknown error` | any other code |

## 9. API signatures

```xi
pub fn raft_configure(nodes: Int) -> Result[Int, ConsensusError]
pub fn raft_max_nodes() -> Int
pub fn raft_log_capacity() -> Int
pub fn raft_node_count() -> Int
pub fn raft_quorum_size(n: Int) -> Int
pub fn raft_has_majority(votes: Int, n: Int) -> Bool
pub fn raft_election_start(id: Int) -> Result[Int, ConsensusError]
pub fn raft_election_vote_count(id: Int) -> Int
pub fn raft_election_has_quorum(id: Int) -> Bool
pub fn raft_leader_append(id: Int, cmd: Int) -> Result[Int, ConsensusError]
pub fn raft_commit_advance(id: Int) -> Result[Int, ConsensusError]
pub fn raft_node_role(id: Int) -> Int
pub fn raft_node_role_name(id: Int) -> Str
pub fn raft_node_term(id: Int) -> Int
pub fn raft_node_voted_for(id: Int) -> Int
pub fn raft_node_commit(id: Int) -> Int
pub fn raft_node_leader_id(id: Int) -> Int
pub fn raft_node_log_len(id: Int) -> Int
pub fn raft_node_last_log_term(id: Int) -> Int
pub fn raft_node_log_term(id: Int, index: Int) -> Int
pub fn raft_node_log_cmd(id: Int, index: Int) -> Int
pub fn raft_next_index(id: Int) -> Int
pub fn raft_match_index(id: Int) -> Int
pub fn raft_msg_empty() -> RaftMessage
pub fn raft_msg_request_vote(from: Int, to: Int, term: Int, last_index: Int, last_term: Int) -> RaftMessage
pub fn raft_msg_request_vote_reply(from: Int, to: Int, term: Int, granted: Int) -> RaftMessage
pub fn raft_msg_append_entries(from: Int, to: Int, term: Int, prev_index: Int, prev_term: Int, leader_commit: Int) -> RaftMessage
pub fn raft_msg_append_entry(from: Int, to: Int, term: Int, prev_index: Int, prev_term: Int, leader_commit: Int, entry_term: Int, entry_cmd: Int) -> RaftMessage
pub fn raft_msg_append_entries_reply(from: Int, to: Int, term: Int, success: Int, match_index: Int) -> RaftMessage
pub fn raft_msg_kind(m: RaftMessage) -> Int
pub fn raft_msg_from(m: RaftMessage) -> Int
pub fn raft_msg_to(m: RaftMessage) -> Int
pub fn raft_msg_term(m: RaftMessage) -> Int
pub fn raft_msg_a(m: RaftMessage) -> Int
pub fn raft_msg_b(m: RaftMessage) -> Int
pub fn raft_msg_c(m: RaftMessage) -> Int
pub fn raft_msg_d(m: RaftMessage) -> Int
pub fn raft_msg_e(m: RaftMessage) -> Int
pub fn raft_msg_kind_name(m: RaftMessage) -> Str
pub fn raft_msg_dump(m: RaftMessage) -> Str
pub fn raft_msg_from_leader(leader: Int, follower: Int) -> RaftMessage
pub fn raft_deliver(m: RaftMessage) -> Int
pub fn raft_handle_request_vote(m: RaftMessage) -> Int
pub fn raft_handle_request_vote_reply(m: RaftMessage) -> Int
pub fn raft_handle_append_entries(m: RaftMessage) -> Int
pub fn raft_handle_append_entries_reply(m: RaftMessage) -> Int
pub fn raft_has_pending_reply() -> Bool
pub fn raft_clear_pending_reply()
pub fn raft_pending_reply() -> RaftMessage
pub fn raft_invariants_check() -> Int
pub fn raft_invariants_report() -> Str
pub fn raft_force_commit(id: Int, index: Int) -> Bool
pub fn raft_force_entry(id: Int, index: Int, term: Int, cmd: Int) -> Bool
pub fn raft_node_dump(id: Int) -> Str
pub fn raft_dump() -> Str
pub fn raft_trace_is_enabled() -> Bool
pub fn raft_trace_enable(on: Bool)
pub fn raft_trace_clear()
pub fn raft_trace_count() -> Int
pub fn raft_trace_line(i: Int) -> Str
pub fn raft_trace_dump() -> Str
pub fn raft_error_message(code: Int) -> Str
```

## 10. Test plan

`tests/test_conformance.xi` (module `consensus_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every fixture is built in-test and each check starts
with `raft_configure` (a full reset), so the suite is order-independent. All
dispatch is direct calls; there is no `Vec[fn]` table.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | configure + quorum math | bounds 1..8, previous config kept on `Err`, fresh state, majority values |
| t2 | single-node cluster | self-election, immediate majority, append + commit, leader cannot re-elect |
| t3 | quorum election | candidate stays candidate at one grant, promotes at two; reply record fields |
| t4 | one vote per term | second candidate in the same term rejected; stale-term request rejected |
| t5 | higher term steps down | leader adopts the term, clears the vote; new candidate wins |
| t6 | election restriction | stale-log candidate rejected even at a higher term; equal-log candidate granted |
| t7 | replication + commit | next/match advance, commit by majority, heartbeat propagates commit |
| t8 | consistency failure | prev beyond log and wrong prev term reply success 0; backoff sets next |
| t9 | divergence repair | a term-1 follower entry is truncated and replaced by the term-2 entry |
| t10 | majority commit | commit stays 0 until a majority of 5 matches, then advances |
| t11 | current-term commit | a replicated previous-term entry is not committed directly; committed with a current-term entry above it |
| t12 | split vote | two candidates with two grants each; a higher term resolves the split |
| t13 | reply handling | stale reply ignored; higher-term reply steps the leader down |
| t14 | validation | codes 1/3/4/5, log capacity 64, election on a leader |
| t15 | invariants | green baseline; force probes drive 104 and 105; reconfigure recovers |
| t16 | message records | all four kinds and the empty record construct, decode and dump; unknown kind |
| t17 | pending reply | request handlers set it, reply handlers do not, clear resets to kind 0 |
| t18 | accessors + dumps | bounds return -1, index-0 sentinel, role names, node/cluster dumps |
| t19 | traces | deterministic line count and text; disable/enable; out-of-range line |
| t20 | stress | 40 single-node entries committed; 20 replicated rounds to a 3-node quorum |

Str equality goes through `xiom.string.compare`'s `str_compare` (BUG 17
discipline); dumps are matched with `xiom.string.str_contains`. Tests consume
each `Result` exactly once and use no `Vec[Str]`, `Vec[fn]`, lambdas, `self`
methods or `Vec[StructType]`.

## 11. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows sibling pure-model idioms
(XIOM v0.62.2):

- `Vec[StructType]` is unsupported, so all state is parallel `Vec[Int]` fields
  and `RaftMessage`/`ConsensusError` are scalar structs constructed in leaf
  constructors;
- `Ok`/`Err` are constructed only inside `_cs_ok` / `_cs_err`;
- every `Vec[Int]` element read is bound with a typed `let`;
- no bitwise operators; indices, terms and votes use plain Int arithmetic;
- module header has no trailing semicolon; each `use` has one; free functions
  only, no methods;
- every loop decrements/increments its bound variable, so all loops and the
  suite terminate.

## 12. Known limitations

- The model is caller-driven: no timers, retries, liveness or fairness.
- One global cluster; `raft_configure` is a full reset, not a resize.
- At most one entry per AppendEntries message; no batching.
- Log capacity 64 per node; no compaction or snapshots.
- No persistence across restarts.
- The next/match cursors are the most recently promoted leader's view; at most
  one leader per term is enforced as an invariant.
- The invariant checker is a structural check, not a machine-checked proof.
- Raw force probes do not validate their arguments beyond id/index bounds.
- Dump and trace formats are test-facing and not a stable public API.
