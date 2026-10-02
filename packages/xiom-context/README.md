# xiom.context

> **Status:** `incubating` -- conformance-tested (23/23); published at `v0.1.0` on the XIOM registry.
> **Scope:** immutable context propagation as a pure, deterministic parent
> chain: shadowing key lookups, inherited logical-tick deadlines, cancellation
> with reason codes and subtree propagation, key-value flattening, path
> strings and structural invariants. No threads, no atomics, no locks, no
> wall clock and no I/O.
> **Deps:** `xiom.std` (manifest only); the library module imports
> `xiom.string` and `xiom.convert`, the tests use `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.convert`.

## What it is

`xiom.context` models execution-context propagation as a plain value type and
a set of free functions. A `Context` holds a forest of immutable nodes stored
as parallel vectors:

- ids and parent links (a parent always precedes its child, so the chain is
  acyclic);
- one shared immutable text buffer holding every key and value, addressed by
  parallel offset/length vectors;
- an effective (earliest) absolute-tick deadline per node;
- cancellation flags with a reason code, an origin source and the logical
  tick at cancellation;
- a monotonic integer clock (`now`).

There is no concurrency in the library, so every operation is a total,
deterministic transition over ordinary values. A real runtime (async
executor, request pipeline, thread pool) owns concurrency and blocking; this
module owns the *semantics* -- what correct context propagation must do -- in
a form that can be tested exactly, without sleeps or races.

Rules:

- **Immutable parent chain.** A node is created once under an existing
  parent; its chain never changes, so a node's view of the world never
  changes under it.
- **Lookup and shadowing.** `ctx_lookup(id, key)` walks from the queried node
  up to the root and returns the value of the first (nearest/deepest)
  binding; nearer bindings shadow farther ones, and keys never leak into
  sibling subtrees. A node with an empty key is not a binding.
- **Deadlines.** A node's effective deadline is the earliest deadline on its
  chain: a child inherits the parent's effective deadline when it declares
  none and can only move it earlier, never later (monotone deadlines). A node
  is due when `now >= deadline`.
- **Cancellation.** `ctx_cancel(id, reason)` cancels one ACTIVE node and,
  transitively, every ACTIVE descendant (reason `PARENT`, source = the
  initiating node). Cancellation is a one-way `ACTIVE -> CANCELLED`
  transition; strict `ctx_cancel` refuses a repeat with
  `context: already cancelled`, while `ctx_cancel_idempotent` returns
  `Ok(0)`. A child added under an already-cancelled parent is born
  `CANCELLED` with reason `PARENT` and the parent's origin source.
- **Expiry.** `ctx_check_deadline(id)` checks one node; `ctx_tick(to)`
  advances the clock and expires every due node in creation order with reason
  `DEADLINE`, propagating like any other cancel.
- **Flattening.** `ctx_flatten(id)` materialises the effective key-value
  listing visible from a node: distinct keys in root-to-leaf
  first-appearance order, each with its nearest binding's value.

## API

| Function | Returns | Description |
|---|---|---|
| `ctx_new()` | `Context` | Empty registry, clock 0. |
| `ctx_add_root(&mut c, id)` | `Result[Int, Str]` | Add a root node (`ACTIVE`); `Ok(id)`. |
| `ctx_add_child(&mut c, parent, id, key, value, deadline)` | `Result[Int, Str]` | Add a child with one binding; born cancelled under a cancelled parent. |
| `ctx_has(c, id)` | `Bool` | Node existence. |
| `ctx_count(c)` | `Int` | Number of nodes (never shrinks). |
| `ctx_parent(c, id)` | `Int` | Parent id, `-1` for a root or unknown id. |
| `ctx_depth(c, id)` | `Int` | Root = 0, `-1` when unknown. |
| `ctx_root_of(c, id)` | `Int` | Topmost ancestor, `-1` when unknown. |
| `ctx_is_ancestor(c, ancestor, id)` | `Bool` | Strict ancestor test. |
| `ctx_path(c, id)` | `Str` | `"root/child/.../node"`, `""` when unknown. |
| `ctx_lookup(c, id, key)` | `Str` | Nearest visible value, `""` when unbound. |
| `ctx_has_key(c, id, key)` | `Bool` | Key resolves on the chain. |
| `ctx_lookup_owner(c, id, key)` | `Int` | Node owning the nearest binding, `-1` when unbound. |
| `ctx_lookup_depth(c, id, key)` | `Int` | Depth of that owner, `-1` when unbound. |
| `ctx_now(c)` | `Int` | Current logical clock. |
| `ctx_deadline(c, id)` | `Int` | Effective deadline tick, `-1` when none/unknown. |
| `ctx_has_deadline(c, id)` | `Bool` | Effective deadline presence. |
| `ctx_advance(&mut c, to)` | `Result[Int, Str]` | Move the clock forward (no deadline check). |
| `ctx_check_deadline(&mut c, id)` | `Result[Int, Str]` | Cancel this node if due; `Ok(newly cancelled)`. |
| `ctx_tick(&mut c, to)` | `Result[Int, Str]` | Advance + expire; `Ok(newly cancelled)`. |
| `ctx_cancel(&mut c, id, reason)` | `Result[Int, Str]` | Cancel the node and its `ACTIVE` descendants; `Ok(newly cancelled)`. |
| `ctx_cancel_idempotent(&mut c, id, reason)` | `Result[Int, Str]` | Same, but repeat calls return `Ok(0)`. |
| `ctx_state(c, id)` | `Int` | `CTX_STATE_*` code, `-1` when unknown. |
| `ctx_is_cancelled(c, id)` | `Bool` | Node exists and is `CANCELLED`. |
| `ctx_is_active(c, id)` | `Bool` | Node exists and is `ACTIVE`. |
| `ctx_cancel_reason(c, id)` | `Int` | Why this node is cancelled (0 while active). |
| `ctx_cancel_source(c, id)` | `Int` | Origin node, `-1` while active/unknown. |
| `ctx_cancel_tick(c, id)` | `Int` | Clock value at cancellation, `-1` while active/unknown. |
| `ctx_cancelled_count(c)` | `Int` | Nodes in `CANCELLED`. |
| `ctx_active_count(c)` | `Int` | Nodes in `ACTIVE`. |
| `ctx_flatten(c, id)` | `Listing` | Effective key-value listing visible from the node. |
| `lst_new()` | `Listing` | Empty listing. |
| `lst_count(l)` | `Int` | Number of pairs. |
| `lst_key(l, i)` | `Str` | Key at index, `""` when out of range. |
| `lst_val(l, i)` | `Str` | Value at index, `""` when out of range. |
| `lst_find(l, key)` | `Int` | Index of key, `-1` when absent. |
| `lst_has(l, key)` | `Bool` | Key presence. |
| `lst_value_of(l, key)` | `Str` | Value of key, `""` when absent. |
| `lst_to_str(l)` | `Str` | `"key=value"` lines joined by `"\n"`. |
| `ctx_state_name(state)` | `Str` | `"active"`, `"cancelled"` or `"unknown"`. |
| `ctx_reason_name(code)` | `Str` | `"none"`, `"user"`, `"deadline"`, `"parent"`, `"shutdown"`, `"custom"` or `"unknown"`. |
| `ctx_chain_acyclic(c)` | `Bool` | Parent links form a forest. |
| `ctx_deadlines_monotone(c)` | `Bool` | Child deadlines never follow parent deadlines. |
| `ctx_check_invariant(c)` | `Bool` | Full structural invariant (see SPEC.md). |

Public constants: states `CTX_STATE_ACTIVE` (0), `CTX_STATE_CANCELLED` (1);
reasons `CTX_REASON_NONE` (0), `CTX_REASON_USER` (1),
`CTX_REASON_DEADLINE` (2, reserved), `CTX_REASON_PARENT` (3, reserved),
`CTX_REASON_SHUTDOWN` (4); sentinels `CTX_NO_PARENT` (-1),
`CTX_NO_DEADLINE` (-1), `CTX_NOT_FOUND` (-1). `ctx_cancel` accepts
`CTX_REASON_USER`, `CTX_REASON_SHUTDOWN` or any custom code `>= 5`; codes 0,
2 and 3 are rejected.

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Usage

```xi
use xiom.context;

// root with no binding, then a chain of bindings.
var c = ctx_new();
ctx_add_root(&mut c, 1);
ctx_add_child(&mut c, 1, 2, "tenant", "acme", -1);
ctx_add_child(&mut c, 2, 3, "route", "/v1", 50);
ctx_add_child(&mut c, 3, 4, "stage", "canary", -1);   // inherits deadline 50

// shadowing: the nearest binding wins.
ctx_add_child(&mut c, 2, 5, "tenant", "beta", -1);
// ctx_lookup(&c, 5, "tenant") == "beta"
// ctx_lookup(&c, 2, "tenant") == "acme"

// deadlines are inherited as the earliest tick on the chain.
// ctx_deadline(&c, 3) == 50, ctx_deadline(&c, 4) == 50

// explicit clock advancement expires due subtrees (nodes 3 and 4).
ctx_tick(&mut c, 50);

// cancellation with reason codes propagates to descendants (nodes 2 and 5).
match ctx_cancel(&mut c, 2, CTX_REASON_USER) {
  Ok(n) => { /* n == 2 */ },
  Err(_) => { /* "context: already cancelled" */ },
}

// flatten a node's effective key-value listing.
var l = ctx_flatten(&c, 4);
// lst_to_str(&l) == "tenant=acme\nroute=/v1\nstage=canary"
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.context
```

Expected: the namespaced module passes the section-4 namespace rule, 23
`[PASS]` lines, and a final `port: PASS (passed=23 failed=0 program_exit=0
exit=0)`.

## Limitations

- **Deterministic model, no real threads.** There is no concurrency,
  atomicity or memory ordering here; a backend that shares a context between
  threads must serialize access to the `Context` value itself.
- **Logical time only.** Deadlines are integer ticks checked explicitly by
  `ctx_check_deadline` / `ctx_tick`; the library never consults a wall clock
  and never expires anything on its own.
- **Nodes are never removed or reparented.** The forest only grows; ids are
  never reused, and a node's chain is fixed at creation.
- **One binding per node.** A node carries exactly one key/value pair; a
  chain expresses multiple bindings, and a repeated key shadows.
- **Flattening is a materialised snapshot.** A `Listing` is a copy; later
  context changes do not update it, and serialization (`lst_to_str`) does not
  escape keys or values.
- **Linear scans.** Node lookup scans the node vectors and flattening scans
  each chain node's keys, so worst cases are quadratic in node count; fine
  for the model, not tuned for very large trees.
- Not thread-safe: values follow ordinary XIOM move/borrow rules.

## Install / publish

```
xiom pkg install xiom.context@0.1.0    # consumer
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

The package is not yet published; the commands above become usable after the
first publish to the XIOM registry.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
