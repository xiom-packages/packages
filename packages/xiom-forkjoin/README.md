# xiom.forkjoin

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.1` on the XIOM registry.
> **Scope:** fork/join task modeling as a pure, deterministic state machine:
> fixed-threshold recursive splitting of a work range into a task-node tree,
> ordered result combining (sum, max, concatenation), a work-stealing deque
> with owner LIFO push/pop and thief FIFO steals, a deterministic steal trace,
> depth-limit errors and joined stats. The model is the semantic core a
> fork/join scheduler would drive -- it contains no threads, no atomics, no
> locks and no clock.
> **Deps:** `xiom.std` (manifest only); the library imports `xiom.string` and
> `xiom.convert` from it, the tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.forkjoin` models the fork/join pattern the way a work-stealing runtime
experiences it, but as plain values and free functions:

1. **Split.** Given a work range `[0, n)` and a threshold `t`, a node splits
   while its size exceeds `t` (at `mid = lo + (hi - lo) / 2`). The result is
   either a `ForkTree` (all node data in parallel `Vec[Int]` fields: `parent`,
   `depth`, `lo`, `hi`, `weight`, `result`, `is_leaf`, `left`, `right`) or a
   flat `LeafRanges` pair. The leaves cover `[0, n)` exactly, in ascending
   order, with no overlap and no leaf larger than `t`. An optional depth limit
   turns "this decomposition is too deep" into a stable error instead of a
   surprise.
2. **Join.** Per-leaf results are combined in leaf order: `fdj_combine_sum`
   and `fdj_combine_max` for scalar reducers, `fdj_concat` for result vectors.
   `fdj_tree_reduce_sum` / `fdj_tree_reduce_max` fold the tree bottom-up so
   every internal node's result slot becomes the combination of its children.
3. **Steal.** A `StealDeque` is laid out tail-to-head: the owner pushes and
   pops at the head (LIFO, so it always works on its newest task) while
   thieves take from the tail (FIFO, so successive steals return the oldest
   remaining tasks). Every successful steal appends `(thief, item)` to a
   mirrored trace, so a backend test can assert the exact steal order.
4. **Stats.** `fdj_stats` joins tree facts (nodes, leaves, max depth) with the
   deque's steal count.

Because there is no concurrency in the library, every operation is a total,
deterministic transition: given the same state and inputs, the same state and
outcome follow. A real runtime (a thread pool, `xiom.sync` primitives, an
event loop) owns atomicity, parking and wakeups; this module owns the
*semantics* -- what a correct fork/join decomposition must do -- in a form
that can be tested exactly, without sleeps or races.

## API

### Splitting

| Function | Returns | Description |
|---|---|---|
| `fdj_tree_build(n, t)` | `Result[ForkTree, Str]` | Build the split tree of `[0, n)` with threshold `t`. |
| `fdj_tree_build_limited(n, t, max_depth)` | `Result[ForkTree, Str]` | Same, but fail when the natural split exceeds `max_depth`. |
| `fdj_split_leaves(n, t)` | `Result[LeafRanges, Str]` | Leaf ranges in ascending order (exact, non-overlapping cover). |
| `fdj_leaves_cover(r, n)` | `Bool` | True when `r` exactly covers `[0, n)` without overlap. |
| `fdj_leaves_within(r, t)` | `Bool` | True when every leaf size is in `[1, t]`. |
| `fdj_ranges_str(r)` | `Str` | Ranges as `"lo-hi"` pairs, e.g. `"0-2,2-5"` (ordering witness). |

### Tree and leaf accessors

| Function | Returns | Description |
|---|---|---|
| `fdj_leaf_count(r)` / `fdj_leaf_lo(r, i)` / `fdj_leaf_hi(r, i)` | `Int` | Leaf count; leaf bounds (`-1` out of range). |
| `fdj_tree_n(t)` / `fdj_tree_threshold(t)` | `Int` | Work size / threshold the tree was built with. |
| `fdj_tree_node_count(t)` / `fdj_tree_leaf_count(t)` / `fdj_tree_max_depth(t)` | `Int` | Cached counts (root depth is 0). |
| `fdj_tree_leaf_node(t, i)` / `fdj_tree_leaf_lo(t, i)` / `fdj_tree_leaf_hi(t, i)` | `Int` | Leaf `i` in ascending range order (`-1` out of range). |
| `fdj_tree_set_result(t, node, v)` | `Result[Int, Str]` | Write a node result slot. |
| `fdj_tree_result(t, node)` | `Result[Int, Str]` | Read a node result slot. |
| `fdj_tree_leaf_results(t)` | `Vec[Int]` | Leaf result slots in leaf order (reducer input). |
| `fdj_tree_check(t)` | `Bool` | Full structural invariant (see SPEC.md section 4). |

### Join / combine

| Function | Returns | Description |
|---|---|---|
| `fdj_combine_sum(results)` | `Int` | Ordered sum of per-leaf results (empty -> `0`). |
| `fdj_combine_max(results)` | `Option[Int]` | Ordered max (`None` when empty). |
| `fdj_concat(chunks)` | `Vec[Int]` | Ordered concatenation of per-leaf result vectors. |
| `fdj_tree_reduce_sum(t)` | `Result[Int, Str]` | Bottom-up sum reduction; returns the root result. |
| `fdj_tree_reduce_max(t)` | `Result[Int, Str]` | Bottom-up max reduction; returns the root result. |

### Work-stealing deque

| Function | Returns | Description |
|---|---|---|
| `fdj_deque_new()` | `StealDeque` | Empty deque. |
| `fdj_deque_push(d, item)` | `Int` | Owner push at the head (LIFO); returns the new length. |
| `fdj_deque_pop(d)` | `Option[Int]` | Owner pop of the newest item; `None` when empty. |
| `fdj_deque_steal(d, thief)` | `Result[Int, Str]` | Thief pop of the oldest item (FIFO); records `(thief, item)`. |
| `fdj_tree_push_leaves(t, d)` | `Int` | Push every leaf node id in order; returns the push count. |
| `fdj_deque_len(d)` | `Int` | Items currently queued. |
| `fdj_deque_push_count(d)` / `fdj_deque_pop_count(d)` / `fdj_deque_steal_count(d)` | `Int` | Transition counters. |
| `fdj_deque_trace_len(d)` | `Int` | Steal-trace length (`== steal count`). |
| `fdj_deque_trace_thief(d, i)` / `fdj_deque_trace_item(d, i)` | `Int` | Trace entry `i` (`-1` out of range). |
| `fdj_deque_trace_str(d)` | `Str` | Trace as `"thief:item"` pairs, e.g. `"7:3,9:4"`. |
| `fdj_deque_trace_is(d, want)` | `Bool` | Trace string equality through `str_compare`. |
| `fdj_deque_check(d)` | `Bool` | Conservation invariant (see SPEC.md section 5). |

### Stats

| Function | Returns | Description |
|---|---|---|
| `fdj_stats(t, d)` | `ForkStats` | `{ nodes, leaves, max_depth, steals }`. |

Every struct field is an internal implementation detail; callers should go
through the free functions (`ForkStats` fields are read directly, as they are
plain derived data).

## Usage

```xi
use xiom.forkjoin;

// Split [0, 100) with threshold 10 and combine the leaf results.
match fdj_tree_build(100, 10) {
  Ok(tree) => {
    var t = tree;
    var i = 0;
    while i < fdj_tree_leaf_count(&t) {
      // A real scheduler would compute each leaf's result here; the model
      // fills the result slots with the leaf weight (hi - lo).
      let node = fdj_tree_leaf_node(&t, i);
      let lo: Int = t.lo[node];
      let hi: Int = t.hi[node];
      fdj_tree_set_result(&mut t, node, hi - lo);
      i = i + 1;
    }
    match fdj_tree_reduce_sum(&mut t) {
      Ok(total) => { /* total == 100 */ },
      Err(_) => { /* "forkjoin: tree is empty" */ },
    }
  },
  Err(_) => { /* "forkjoin: n must be >= 1" | "forkjoin: threshold must be >= 1" */ },
}
```

A runtime driving the work-stealing model:

```xi
var d = fdj_deque_new();
fdj_tree_push_leaves(&t, &mut d);      // the owner seeds its deque
// Owner takes the newest task:
match fdj_deque_pop(&mut d) { Some(leaf) => { /* run leaf */ }, None => { } }
// A thief steals the oldest task and the steal is traced:
match fdj_deque_steal(&mut d, 7) {
  Ok(leaf) => { /* thief 7 runs leaf */ },
  Err(_) => { /* "forkjoin: deque is empty" | "forkjoin: thief id must be >= 0" */ },
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.forkjoin
```

Expected: the namespaced module passes the section-4 namespace rule, 22
`[PASS]` lines, and a final `port: PASS (passed=22 failed=0 program_exit=0
exit=0)`.

## Limitations

- **No threads, atomics, or locks.** This is a deterministic semantic model,
  not a thread pool. A real runtime must provide the critical sections around
  deque transitions and actually execute the leaves.
- **The deque is a model, not a lock-free structure.** Owner and thief
  operations are plain Vec operations; there is no CAS, no memory ordering and
  no contention model.
- **Leaf payloads are not stored.** Only result slots (`Vec[Int]`) are
  modeled; leaf bodies are the runtime's business. `fdj_concat` accepts
  per-leaf `Vec[Int]` outputs when a leaf's result is itself a vector.
- **Splitting is strictly halving.** The rule is fixed (`mid = lo +
  (hi - lo) / 2`); there is no custom splitter, weighted split, or grain
  adaptation, and no function-pointer split policy.
- **The tree is a full binary tree.** Every internal node has exactly two
  children; odd sizes make the left child the smaller one.
- **`n` and `t` are 1-based.** `n = 0` (no work) and `t = 0` are errors, not
  empty splits; a caller with no work should skip the split.
- **Recursion is iterative but the model is O(1)-depth.** The build loop uses
  an explicit queue (BFS node order); there is no recursion limit, only the
  optional `max_depth` policy check.
- **`fdj_deque_steal` is O(queue length)** because the tail removal rebuilds
  the Vec; a backend with very long deques would use a ring buffer or use the
  owner end for removals.
- Not thread-safe: values follow ordinary XIOM move/borrow rules.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
