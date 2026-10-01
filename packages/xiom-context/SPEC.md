# xiom.context -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.context` (`src/context.xi`). Manifest: `package.xi` (name
`xiom.context`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library module imports `xiom.string` and `xiom.convert`, the tests use
`xiom.test`, `xiom.io`, `xiom.string.compare` and `xiom.convert`.

## 1. Scope

Immutable context propagation as a pure, deterministic parent chain -- the
semantic core that an async executor, request pipeline or task scheduler
would drive:

- node construction as a forest: `ctx_add_root`, `ctx_add_child`, with
  parent-chain queries (`ctx_parent`, `ctx_depth`, `ctx_root_of`,
  `ctx_is_ancestor`, `ctx_path`);
- shadowing key lookup with ownership queries (`ctx_lookup`, `ctx_has_key`,
  `ctx_lookup_owner`, `ctx_lookup_depth`);
- effective deadlines as absolute logical ticks with inheritance of the
  earliest (`ctx_deadline`, `ctx_has_deadline`), a monotonic integer clock
  (`ctx_advance`) and explicit expiry (`ctx_check_deadline`, `ctx_tick`);
- cancellation with reason codes (`ctx_cancel`), idempotent cancellation
  (`ctx_cancel_idempotent`) and transitive subtree propagation;
- effective key-value flattening (`ctx_flatten` plus the `lst_*` listing
  accessors);
- state accessors (`ctx_state`, `ctx_is_cancelled`, `ctx_cancel_reason`,
  `ctx_cancel_source`, `ctx_cancel_tick`), counts and structural invariants
  (`ctx_chain_acyclic`, `ctx_deadlines_monotone`, `ctx_check_invariant`).

No threads, no atomics, no locks, no wall clock, no I/O, no FFI, no global
state. The library owns semantics only; a backend owns concurrency,
blocking and the decision of when to advance the clock.

## 2. Non-goals

- Actual asynchronous propagation, task scheduling, waiting or callbacks. A
  context is a value; a backend reads the lookup/deadline/cancellation
  accessors and decides what to do.
- Real-time or OS deadlines. Deadlines are logical ticks the caller
  advances; the library never reads a clock.
- Task execution or futures. `xiom.executor` (a separate package) is the
  deterministic execution model; `xiom.cancel` (a separate package) is the
  standalone cancellation-token model.
- Node removal, detach or reparent; the forest only grows and ids are never
  reused.
- Multiple bindings per node. A node carries exactly one key/value pair;
  multiple bindings are expressed by a chain, and repeated keys shadow.
- Atomicity or memory ordering; the value follows ordinary XIOM move/borrow
  rules and a concurrent backend must serialize access.

## 3. State

```xi
pub type Context = {
  ids: Vec[Int];            // node ids, unique, >= 0
  parents: Vec[Int];        // parent node id, or -1 for a root
  text: Str;                // shared immutable key/value byte buffer
  key_off: Vec[Int];        // key start offset in text
  key_len: Vec[Int];        // key byte length
  val_off: Vec[Int];        // value start offset in text
  val_len: Vec[Int];        // value byte length
  deadlines: Vec[Int];      // EFFECTIVE (earliest) absolute tick, or -1
  cancelled: Vec[Int];      // CTX_STATE_ACTIVE | CTX_STATE_CANCELLED
  cancel_reasons: Vec[Int]; // CTX_REASON_* (or custom): why THIS node is cancelled
  cancel_sources: Vec[Int]; // originating node: self, or the cancelled ancestor
  cancel_ticks: Vec[Int];   // logical clock value at cancellation, or -1
  now: Int;                 // monotonic logical clock, starts at 0
}
```

Every field is an internal implementation detail; callers go through the
free functions. The eleven node vectors are pushed together by every
mutation, so they can never skew. Because each node stores its *effective*
deadline, the effective tick is recovered in O(node count) without walking
the chain.

`ctx_flatten` returns a materialised listing with the same addressing shape:

```xi
pub type Listing = {
  text: Str;                // the listing's own byte buffer
  key_off: Vec[Int];
  key_len: Vec[Int];
  val_off: Vec[Int];
  val_len: Vec[Int];
  count: Int;               // number of distinct keys
}
```

State codes: `CTX_STATE_ACTIVE` (0), `CTX_STATE_CANCELLED` (1).
Reason codes: `CTX_REASON_NONE` (0, only on `ACTIVE` nodes),
`CTX_REASON_USER` (1), `CTX_REASON_DEADLINE` (2, reserved),
`CTX_REASON_PARENT` (3, reserved), `CTX_REASON_SHUTDOWN` (4);
`ctx_cancel` / `ctx_cancel_idempotent` accept 1, 4 or any custom code `>= 5`
and reject 0, 2 and 3. Sentinels: `CTX_NO_PARENT` (-1),
`CTX_NO_DEADLINE` (-1), `CTX_NOT_FOUND` (-1).

### 3.1 Invariant

`ctx_check_invariant(c)` is true exactly when:

1. the eleven node vectors have equal length `n`, `now >= 0`, and the parent
   chain is acyclic (`ctx_chain_acyclic`);
2. every node id is `>= 0` and unique; every deadline is `>= -1` and the
   deadlines are monotone (`ctx_deadlines_monotone`);
3. every stored range is well-formed: `0 <= key_off`, `0 <= key_len`,
   `key_off + key_len <= text.len()`, `val_off == key_off + key_len`,
   `0 <= val_len` and `val_off + val_len <= text.len()`;
4. every state is a `CTX_STATE_*` code; an `ACTIVE` node has reason `NONE`
   (0), source `-1` and cancel_tick `-1`; a `CANCELLED` node has reason
   `>= 1`, source `>= 0` naming an existing node, and `0 <= cancel_tick <=
   now`; when the reason is `PARENT` the source is a proper ancestor whose
   own reason is not `PARENT`; otherwise the source is the node itself;
5. propagation closure: a node whose parent is `CANCELLED` is itself
   `CANCELLED`.

`ctx_chain_acyclic(c)` is true when every parent is `-1` or names an existing
node at a strictly smaller slot. Nodes are always appended after their
parent, so the parent graph is a forest and the slot rule is the acyclicity
proof.

`ctx_deadlines_monotone(c)` is true when for every child, if the parent's
effective deadline is set then the child's is set and `child <= parent`. A
chain can therefore only move a deadline earlier, never later.

## 4. Semantics

Notation: `c` is a `Context`; `p`, `id` are node ids; `r` is a reason code;
`t` is a logical tick.

### 4.1 Construction

`ctx_new()` -- empty vectors, empty text, clock 0; total.

`ctx_add_root(id)` validation order:

1. `id < 0` -> `Err("context: id must be >= 0")`;
2. `id` already known -> `Err("context: duplicate id")`;
3. otherwise append a root node: parent `-1`, empty key and value, deadline
   `-1`, state `ACTIVE`, reason `NONE`, source `-1`, cancel_tick `-1`;
   `Ok(id)`.

`ctx_add_child(parent, id, key, value, deadline)` validation order:

1. `id < 0` -> `Err("context: id must be >= 0")`;
2. `id` already known -> `Err("context: duplicate id")`;
3. `parent` unknown -> `Err("context: unknown parent id")`;
4. `deadline < -1` -> `Err("context: deadline must be >= -1")`;
5. otherwise append the node with parent = `parent` and effective deadline
   `eff`:
   - `eff = deadline` when the parent's effective deadline `pdl` is `-1` or
     `deadline` is `-1`;
   - when both are set, `eff = min(pdl, deadline)`;
   - when `deadline` is `-1` and `pdl` is set, `eff = pdl` (inheritance);
   if the parent is `ACTIVE` the child is `ACTIVE` (reason `NONE`, source
   `-1`, tick `-1`); if the parent is `CANCELLED` the child is **born
   cancelled**: state `CANCELLED`, reason `PARENT`, source = the parent's
   origin source, cancel_tick = the current clock; `Ok(id)`.

Every error leaves the state unchanged.

### 4.2 Lookup and shadowing

`ctx_lookup(id, key)` walks from the node at `id` up to its root. A node
matches when its stored key has non-zero length and `str_compare(stored,
key) == 0`; the first match (nearest to the queried node) wins and its value
is returned. Nodes with an empty key never match. `""` is returned when the
id is unknown or the key is unbound.

Consequences:

- **Nearest wins.** A binding on a descendant shadows the same key on every
  ancestor.
- **Scoped to the chain.** A binding on a sibling or on an unrelated node is
  not visible; lookup only walks the queried node's own ancestors.
- **Upward invisibility.** A node never sees bindings that exist only below
  it.
- `ctx_has_key` reports whether the walk finds a match; `ctx_lookup_owner`
  returns the owning node id; `ctx_lookup_depth` returns that node's depth.

### 4.3 Clock and deadlines

Deadlines are absolute logical ticks. The effective deadline of a node is
computed at creation (4.1) and is the earliest deadline on its chain, so
`ctx_deadline` is exact without walking.

- `ctx_advance(t)`: `t < now` -> `Err("context: clock cannot go
  backwards")` (state unchanged); otherwise `now = t`, `Ok(t)`. Deadlines
  are **not** evaluated.
- `ctx_check_deadline(id)`: unknown -> `Err("context: unknown id")`; not
  `ACTIVE`, no deadline, or `now < deadline` -> `Ok(0)`; otherwise cancel the
  node exactly as 4.4 with reason `DEADLINE` and source = its own id
  (propagation included), `Ok(newly cancelled nodes)`.
- `ctx_tick(t)`: `t < now` -> `Err("context: clock cannot go backwards")`
  (state unchanged; nothing expires); otherwise `now = t`, then scan nodes
  in creation order and cancel every `ACTIVE` node with `now >= deadline`
  (reason `DEADLINE`, source = itself, propagation included). A node already
  `CANCELLED` -- including one just cancelled by a due ancestor in the same
  scan -- is skipped. Returns `Ok(newly cancelled nodes)`.

Because parents always precede children and a child's effective deadline is
never later than its parent's, a due parent cancels its whole due subtree in
one step and each node is cancelled at most once per tick.

### 4.4 Cancellation

`ctx_cancel(id, r)` validation order:

1. unknown `id` -> `Err("context: unknown id")`;
2. `r < 1` -> `Err("context: reason must be >= 1")`;
3. `r` is `CTX_REASON_DEADLINE` (2) or `CTX_REASON_PARENT` (3) ->
   `Err("context: reason code is reserved")`;
4. node `CANCELLED` -> `Err("context: already cancelled")`;
5. otherwise the target becomes `CANCELLED` with reason `r`, source = its own
   id, cancel_tick = `now`; every `ACTIVE` descendant becomes `CANCELLED`
   with reason `PARENT`, source = the target id and cancel_tick = `now`;
   `Ok(newly cancelled count)`.

Descendants already `CANCELLED` keep their original reason/source/tick.
Every error leaves the state unchanged.

`ctx_cancel_idempotent(id, r)` has the same validation order except step 4:
an already `CANCELLED` node returns `Ok(0)` and changes nothing.

### 4.5 Propagation properties

1. **One-way transition.** `ACTIVE -> CANCELLED` only; `CANCELLED` is
   terminal. No operation moves a node back or rewrites its
   reason/source/tick.
2. **Origin recorded.** A direct or deadline cancel records source = self; a
   propagated cancel records the initiating node, so `ctx_cancel_source(id)`
   answers "which node caused this".
3. **Reason partition.** `PARENT` means "cancelled because an ancestor was";
   `DEADLINE` means "this node's own effective deadline expired"; anything
   else is an explicit caller reason.
4. **Closure.** A child added under a `CANCELLED` parent is born cancelled
   (4.1), and every cancel call cancels all `ACTIVE` descendants, so
   `parent CANCELLED => child CANCELLED` holds in every reachable state
   (invariant clause 5). A born-cancelled child records the parent's origin
   source, so chains of born-cancelled nodes still point at the origin.
5. **Cancelled-descendant precedence.** An already-cancelled descendant
   keeps its own reason/source/tick; propagation never overwrites it.
6. **Exactly-once cancellation.** A node is cancelled at most once
   (`CANCELLED` is terminal), only `ACTIVE` descendants are touched, and a
   tick skips already-cancelled nodes.

### 4.6 Path rendering

`ctx_path(id)` renders the id chain from the root down to the node,
inclusive, joined by `"/"`: a root renders as `"<id>"`, its child as
`"<root>/<child>"`, and so on. An unknown id renders as `""`. Ids are
rendered with `convert.int_to_string` (decimal, sign-aware).

### 4.7 Flattening and listings

`ctx_flatten(id)` walks the chain root-to-node and builds the effective
listing:

- a node with an empty key is skipped;
- a key seen for the first time is appended with its value, in
  root-to-leaf first-appearance order;
- a key already present has its value replaced in place by the nearer
  binding (the key keeps its original position), so shadowed values are
  replaced, never duplicated;
- `count` is the number of distinct keys; an unknown id yields an empty
  listing.

`lst_key` / `lst_val` return `""` out of range; `lst_find` returns the index
or `-1`; `lst_has` and `lst_value_of` are the boolean/value conveniences;
`lst_to_str` renders one `"key=value"` line per pair joined by `"\n"` (no
escaping; an empty listing renders as `""`). A listing is an independent
materialised copy: later context changes do not affect it.

## 5. Error catalog

All error strings are stable and prefixed `context: `.

| Function | Condition | Err message | State on error |
|---|---|---|---|
| `ctx_add_root` / `ctx_add_child` | `id < 0` | `context: id must be >= 0` | unchanged |
| `ctx_add_root` / `ctx_add_child` | id already known | `context: duplicate id` | unchanged |
| `ctx_add_child` | unknown parent | `context: unknown parent id` | unchanged |
| `ctx_add_child` | `deadline < -1` | `context: deadline must be >= -1` | unchanged |
| `ctx_cancel` / `ctx_cancel_idempotent` | unknown id | `context: unknown id` | unchanged |
| `ctx_cancel` / `ctx_cancel_idempotent` | `reason < 1` | `context: reason must be >= 1` | unchanged |
| `ctx_cancel` / `ctx_cancel_idempotent` | reason 2 or 3 | `context: reason code is reserved` | unchanged |
| `ctx_cancel` | already cancelled | `context: already cancelled` | unchanged |
| `ctx_cancel_idempotent` | already cancelled | -- (`Ok(0)`) | unchanged |
| `ctx_advance` / `ctx_tick` | `to < now` | `context: clock cannot go backwards` | unchanged |
| `ctx_check_deadline` | unknown id | `context: unknown id` | unchanged |

No panicking input exists: every function is total, and read accessors return
`-1` / `false` / `""` sentinels instead of erroring.

## 6. Complexity

| Operation | Complexity |
|---|---|
| `ctx_new` / `ctx_now` / `ctx_count` / `lst_count` / counters | O(1) |
| `ctx_advance` | O(1) |
| `ctx_add_root` / `ctx_add_child` | O(node count) -- duplicate and parent scans |
| `ctx_has` / `ctx_parent` / `ctx_deadline` / state, reason, source, tick accessors | O(node count) |
| `ctx_lookup` / `ctx_has_key` / `ctx_lookup_owner` / `ctx_lookup_depth` | O(depth x key length) |
| `ctx_depth` / `ctx_root_of` / `ctx_is_ancestor` | O(depth) |
| `ctx_path` | O(depth^2) bytes (cubic in pathological depth) |
| `ctx_cancel` / `ctx_cancel_idempotent` / `ctx_check_deadline` | O(node count^2) -- descendant scan |
| `ctx_tick` | O(node count^2) |
| `ctx_flatten` | O(depth^2 x key length) |
| `lst_*` accessors | O(count x key length) |
| `ctx_chain_acyclic` / `ctx_deadlines_monotone` | O(node count^2) |
| `ctx_check_invariant` | O(node count^2) |

## 7. Test plan

`tests/test_conformance.xi` (`module context_tests`, 23 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test through
`ctx_new`; every string comparison routes through `compare.str_compare`;
tests are called directly (no `Vec[fn]` dispatch), and no `Vec[Str]` is
constructed anywhere.

1. `ctx_new` starts empty: every accessor yields its sentinel;
2. `add_root` validates ids and creates an `ACTIVE` parentless node;
3. `add_child` validates ids and links the child to its parent;
4. lookup resolves found keys, misses and unknown ids;
5. nearer bindings shadow farther ones and keys stay scoped to their
   subtree;
6. `ctx_path` renders the whole root-to-node id chain;
7. depth, roots and strict ancestor relations follow the parent chain;
8. a child inherits the earliest deadline of its chain;
9. deadline validation accepts `>= -1` and an explicit tick can only
   tighten;
10. the logical clock only moves forward (no deadline evaluation);
11. `check_deadline` cancels a due node exactly once with reason `DEADLINE`;
12. `ctx_tick` expires the inherited deadline and cascades to the subtree;
13. cancelling a node propagates `PARENT` to `ACTIVE` descendants only;
14. strict cancel refuses repeats, idempotent returns `Ok(0)`, custom
    reasons pass;
15. a child of a cancelled node is born cancelled with the origin source;
16. flatten lists distinct keys with the nearest shadowing value;
17. flatten is a per-node snapshot: sibling subtrees do not leak;
18. unknown ids yield sentinels instead of errors everywhere;
19. the invariant holds across 16 deterministic add/tick/cancel cycles;
20. chain acyclicity and deadline monotonicity hold on mixed trees;
21. state and reason name helpers are stable;
22. listing accessors are total: out-of-range and empty cases are safe;
23. listings are independent snapshots and ticking leaves values intact.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.context
```

Last verified: compiler v0.62.2, `port: PASS (passed=23 failed=0
program_exit=0 exit=0)`.

## 8. Compiler / stdlib notes for v0.62.2

- Free functions only (no methods), with explicit `&`/`&mut` parameters and
  `&mut` at every call site.
- `Ok`/`Err` are constructed only inside the `_ok_int` / `_err_int` leaf
  helper functions.
- Every element read is bound with a typed `let` before use.
- All eleven node vectors (and the five listing fields) are pushed together
  in one function per mutation, so they cannot skew.
- Keys and values avoid `Vec[Str]` entirely: one `Str` buffer plus parallel
  offset/length `Vec[Int]` pairs; reads go through `string.str_slice`, writes
  through `Str` concatenation. `Vec[Str].push` (mis-lowered in this compiler
  family) is never used, and no `Vec[StructType]`, indexed `Vec[fn]`
  dispatch, generic callbacks, `Vec[Float64]`, `mut` in match patterns,
  `break`/`continue`, FFI, threads or `log`-named function appears.
- Conversions go through the module-qualified `convert.int_to_string`; a
  bare `int_to_string` does not resolve in a library module.
- Wrapper functions in the test suite take `&mut` for read-only access, so a
  `&local` read call is never followed by a `&mut local` call in the same
  function body (advisory E001).

## 9. Known limitations

- The model is single-threaded and non-atomic; a concurrent backend must
  provide the critical section around every transition.
- Deadlines fire only when checked: the library never advances time or
  expires anything on its own.
- The node table only grows; there is no removal, detach or reparent, and
  ids cannot be reused.
- A node carries one binding; `ctx_lookup` is a linear chain walk, and
  `ctx_flatten` re-walks and re-compares keys per level.
- `ctx_tick` cancels due parents before their due descendants in creation
  order, so a descendant with the same effective deadline is reported with
  reason `PARENT` (source = the ancestor) rather than `DEADLINE`; a
  descendant with an earlier deadline can expire first and keep
  `DEADLINE`.
- Deep chains make `ctx_path` and flattening quadratic in depth; a backend
  with very deep chains would cache rendered paths or index bindings.
