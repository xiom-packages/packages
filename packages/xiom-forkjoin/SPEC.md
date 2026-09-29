# xiom.forkjoin -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.forkjoin` (`src/forkjoin.xi`). Manifest: `package.xi` (name
`xiom.forkjoin`, version `0.1.0`, categories `concurrency` + `systems`).
`xiom.std` is a manifest dependency; the library module imports `xiom.string`
and `xiom.convert` only.

## 1. Scope

Fork/join task modeling as a pure, deterministic state machine -- the
semantic core that a work-stealing scheduler would drive:

- fixed-threshold recursive splitting of a work range `[0, n)` into a task
  tree (`ForkTree`, all node data in parallel `Vec[Int]` fields) or a flat
  leaf-range list (`LeafRanges`);
- exact-coverage validation helpers for the produced leaf ranges;
- ordered result combining: sum and max reducers over per-leaf results, and
  ordered concatenation of per-leaf result vectors;
- bottom-up tree reduction that fills every internal node's result slot;
- a work-stealing deque (`StealDeque`) with owner-side LIFO push/pop,
  thief-side FIFO pop-from-tail, and a deterministic `(thief, item)` trace;
- a depth-limit policy error and joined tree/deque statistics (`ForkStats`).

No threads, no atomics, no locks, no clock, no I/O, no FFI, no global state.
The library owns semantics only; a runtime owns concurrency, scheduling and
execution.

## 2. Split rule and tree layout

### 2.1 Nodes

A task node owns the half-open work range `[lo, hi)` with size `s = hi - lo`
(`1 <= s <= n`). The root is node 0 with range `[0, n)`.

- A node is a **leaf** exactly when `s <= t` (threshold `t >= 1`).
- A non-leaf ("internal") node splits at `mid = lo + (hi - lo) / 2`
  (truncating integer division, `hi > lo`) into two children:
  `left = [lo, mid)` and `right = [mid, hi)`.
- Because `s > t >= 1` implies `s >= 2`, both children are non-empty:
  `left` has size `floor(s/2)`, `right` has size `ceil(s/2)`.

The tree is a **full** binary tree: every internal node has exactly two
children, and `nodes = 2 * leaves - 1`.

### 2.2 Node numbering

Nodes are created in **BFS (level) order**: node 0 is the root; when node
`i` (processed in increasing index order) is internal, its left child is
appended first and its right child second. Consequences:

- `parent[i] < i` for every non-root node, so one reverse index sweep
  reduces the tree bottom-up;
- `depth[0] = 0`; `depth[child] = depth[parent] + 1`;
- `max_depth` is the depth of the deepest node (a single-leaf tree has
  `max_depth = 0`).

### 2.3 Leaves are ordered by range

Leaves are enumerated by an explicit left-first DFS from the root (the
implementation pushes right then left on a LIFO stack). This yields exactly
the leaves in **ascending range order**, independent of their BFS node ids.

Theorem (exact cover): for any `n >= 1`, `t >= 1`, the leaves
`L0, L1, ..., Lk-1` satisfy `lo(L0) = 0`, `hi(Li) = lo(Li+1)` for every `i`,
`hi(Lk-1) = n`, and `1 <= size(Li) <= t`. There is no gap and no overlap.

Worked examples:

| n | t | leaves (ascending) | nodes | leaves | max depth |
|---|---|---|---|---|---|
| 3 | 4 | `[0,3)` | 1 | 1 | 0 |
| 9 | 4 | `[0,4) [4,6) [6,9)` | 5 | 3 | 2 |
| 10 | 3 | `[0,2) [2,5) [5,7) [7,10)` | 7 | 4 | 2 |
| 16 | 1 | sixteen singletons | 31 | 16 | 4 |
| 5 | 2 | `[0,2) [2,3) [3,5)` | 5 | 3 | 2 |

### 2.4 Depth limit

`fdj_tree_build_limited(n, t, max_depth)` builds the same natural tree but
fails with `Err("forkjoin: depth limit exceeded")` as soon as an internal
node sits at depth `>= max_depth` (it would need children at depth
`max_depth + 1`). A leaf at depth `max_depth` is fine. `max_depth` must be
`>= 0` (root depth is 0); no partial tree is produced on error.

## 3. State

```xi
pub type LeafRanges = {
  lo: Vec[Int];   // inclusive start of leaf i, ascending order
  hi: Vec[Int];   // exclusive end of leaf i (same length as lo)
}

pub type ForkTree = {
  n: Int;              // work size, >= 1
  threshold: Int;      // t, >= 1
  node_count: Int;     // == parent.len()
  leaf_count: Int;     // number of leaves
  max_depth: Int;      // deepest node depth (root 0)
  parent: Vec[Int];    // parent id, root = -1
  depth: Vec[Int];     // root = 0
  lo: Vec[Int];        // range start, inclusive
  hi: Vec[Int];        // range end, exclusive
  weight: Vec[Int];    // hi - lo
  result: Vec[Int];    // result slot, 0 until written
  is_leaf: Vec[Int];   // 1 = leaf, 0 = internal
  left: Vec[Int];      // left child id, -1 at leaves
  right: Vec[Int];     // right child id, -1 at leaves
}

pub type StealDeque = {
  items: Vec[Int];         // tail-to-head (see section 5)
  thief_ids: Vec[Int];     // trace: thief of each steal, in order
  stolen_items: Vec[Int];  // trace: item of each steal (mirrored)
  pushes: Int;             // owner pushes
  owner_pops: Int;         // owner pops
  steals: Int;             // successful steals
}

pub type ForkStats = {
  nodes: Int;      // tree node count
  leaves: Int;     // tree leaf count
  max_depth: Int;  // tree max depth
  steals: Int;     // deque steal count
}
```

All `ForkTree`/`StealDeque` fields are internal implementation details;
callers go through the free functions. `ForkStats` is plain derived data and
its fields are read directly.

## 4. Tree invariant

`fdj_tree_check(t)` is true exactly when:

1. every node Vec (`parent`, `depth`, `lo`, `hi`, `weight`, `result`,
   `is_leaf`, `left`, `right`) has length `node_count`, and `node_count > 0`;
2. `n >= 1` and `threshold >= 1`;
3. node 0 is the root: `parent = -1`, `depth = 0`, `lo = 0`, `hi = n`;
4. every node has `0 <= lo < hi <= n` and `weight == hi - lo`;
5. `is_leaf == 1` iff `weight <= threshold`; leaves have `left == right == -1`;
6. every internal node has valid (in-range, distinct) children with
   `parent[child] == i`, `depth[child] == depth[i] + 1`, and ranges that
   partition the parent: `left.lo == lo`, `left.hi == right.lo`,
   `right.hi == hi`;
7. every non-root node has `0 <= parent[i] < i`;
8. `leaf_count` and `max_depth` equal the recomputed counts;
9. the leaves in ascending range order exactly cover `[0, n)` (section 2.3).

The empty tree is invalid (`fdj_tree_check` is false).

## 5. Work-stealing deque

### 5.1 Layout and ends

`items` is laid out tail-to-head:

- **tail = index 0** -- the oldest queued item, the **thief end**;
- **head = the back of the Vec** -- the newest item, the **owner end**.

```text
    tail (thief end)                          head (owner end)
    items[0]   items[1]   ...   items[len-2]   items[len-1]
      oldest                                  newest
```

### 5.2 Transitions

- **Owner push** (`fdj_deque_push(d, item)`): append at the head;
  `pushes += 1`; returns the new length. O(1).
- **Owner pop** (`fdj_deque_pop(d)`): remove the newest item (the head,
  LIFO); `owner_pops += 1` on success; `None` on empty (no state change).
  O(1).
- **Thief steal** (`fdj_deque_steal(d, thief)`): remove the oldest item (the
  tail, index 0, FIFO across successive steals). On success the pair
  `(thief, item)` is appended to both trace Vecs in the same function and
  `steals += 1`; returns `Ok(item)`. O(deque length) (tail removal rebuilds
  the Vec).

Steal ordering property: if the deque holds items pushed in order
`a, b, c, ...`, then successive steals return `a`, then `b`, then `c`, ...
(i.e. FIFO), while owner pops return the newest remaining item (LIFO).

### 5.3 Steal trace

`thief_ids[i]` and `stolen_items[i]` are the thief id and item of the `i`-th
successful steal. `fdj_deque_trace_str` renders them as comma-separated
`thief:item` pairs (e.g. `"7:10,9:20,7:30"`), and `fdj_deque_trace_is`
compares that string with `str_compare`. A refused steal (empty deque or
negative thief) never appends to the trace.

### 5.4 Invariant

`fdj_deque_check(d)` is true exactly when:

1. `pushes >= 0`, `owner_pops >= 0`, `steals >= 0`;
2. `thief_ids.len() == stolen_items.len() == steals` (mirrored trace);
3. **conservation**: `pushes == items.len() + owner_pops + steals` -- every
   push is accounted for exactly once by the current items, the owner pops or
   the steals.

An empty deque is valid.

### 5.5 Seeding from a tree

`fdj_tree_push_leaves(t, d)` pushes every leaf node id of `t` in ascending
range order (leaf 0 first), so the oldest queued item is the leftmost leaf
and `fdj_deque_steal` hands out leaves left to right. It returns the number
of pushes.

## 6. Join semantics

Leaf result slots are the inputs; reductions only overwrite internal slots.

- `fdj_combine_sum(results)`: ordered sum; empty -> `0`.
- `fdj_combine_max(results)`: ordered max; empty -> `None`.
- `fdj_concat(chunks)`: ordered concatenation of per-leaf `Vec[Int]` outputs;
  empty chunks contribute nothing; zero chunks -> empty vector.
- `fdj_tree_reduce_sum(t)` / `fdj_tree_reduce_max(t)`: one reverse index
  sweep (children have larger ids than parents) computes every internal
  node's slot from its two children; returns the root slot. An empty tree is
  `Err("forkjoin: tree is empty")`.

## 7. Error catalog

All error strings are stable and prefixed `forkjoin: `.

| Function | Condition | Err message | State on error |
|---|---|---|---|
| `fdj_tree_build` / `fdj_tree_build_limited` / `fdj_split_leaves` | `n < 1` | `forkjoin: n must be >= 1` | no value produced |
| `fdj_tree_build` / `fdj_tree_build_limited` / `fdj_split_leaves` | `t < 1` | `forkjoin: threshold must be >= 1` | no value produced |
| `fdj_tree_build_limited` | `max_depth < 0` | `forkjoin: max_depth must be >= 0` | no value produced |
| `fdj_tree_build_limited` | internal node at depth `>= max_depth` | `forkjoin: depth limit exceeded` | no value produced |
| `fdj_tree_set_result` / `fdj_tree_result` | `node` out of `[0, node_count)` | `forkjoin: node index out of range` | unchanged |
| `fdj_tree_reduce_sum` / `fdj_tree_reduce_max` | tree has no nodes | `forkjoin: tree is empty` | unchanged |
| `fdj_deque_steal` | `thief < 0` | `forkjoin: thief id must be >= 0` | unchanged |
| `fdj_deque_steal` | deque empty | `forkjoin: deque is empty` | unchanged |

Validation order: `n`, then `t`, then `max_depth` for the build entry points;
`thief`, then emptiness for `fdj_deque_steal`.

No panicking input exists: every function is total, and read accessors return
`-1` sentinels or `None`/`Err` instead of trapping (`fdj_leaf_lo`,
`fdj_leaf_hi`, `fdj_tree_leaf_node`, `fdj_tree_leaf_lo`,
`fdj_tree_leaf_hi`, `fdj_deque_trace_thief`, `fdj_deque_trace_item` return
`-1` out of range; `fdj_combine_max` returns `None`; `fdj_deque_pop` returns
`None`).

## 8. Complexity

| Operation | Complexity |
|---|---|
| `fdj_tree_build` / `fdj_tree_build_limited` | O(nodes) |
| `fdj_split_leaves` | O(nodes + leaves) |
| `fdj_leaf_*`, `fdj_ranges_str`, `fdj_leaves_cover` / `fdj_leaves_within` | O(leaves) |
| `fdj_tree_n` / `fdj_tree_threshold` / counts / `fdj_tree_max_depth` | O(1) |
| `fdj_tree_leaf_node` / `fdj_tree_leaf_lo` / `fdj_tree_leaf_hi` / `fdj_tree_leaf_results` | O(nodes + leaves) |
| `fdj_tree_set_result` / `fdj_tree_result` | O(1) |
| `fdj_tree_check` | O(nodes + leaves) |
| `fdj_combine_sum` / `fdj_combine_max` | O(leaves) |
| `fdj_concat` | O(total elements) |
| `fdj_tree_reduce_sum` / `fdj_tree_reduce_max` | O(nodes) |
| `fdj_deque_push` / `fdj_deque_pop` / scalar accessors | O(1) |
| `fdj_deque_steal` | O(deque length) (tail removal rebuilds the Vec) |
| `fdj_deque_trace_str` / `fdj_deque_trace_is` | O(trace length) |
| `fdj_tree_push_leaves` | O(nodes + leaves) |
| `fdj_stats` | O(1) |

## 9. Test plan

`tests/test_conformance.xi` (`module forkjoin_tests`, 22 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test through the public
API; every string comparison routes through `compare.str_compare`, and every
read-only call on a mutable fixture goes through a small `&mut` wrapper
(advisory E001 discipline).

1. `n <= t` is a single leaf root (field-level shape checks);
2. `n=9, t=4` splits into `[0,4) [4,6) [6,9)` with BFS node ids and children;
3. leaf ranges cover `[0,10)` with `t=3` in ascending order (`"0-2,2-5,5-7,7-10"`);
4. coverage holds for every `n <= 20, t <= 5`; a gap/overlap/empty fixture is rejected;
5. `n`, `t` and `max_depth` validation errors are stable;
6. threshold edges: `t > n`, `t == n`, `t = 1`, `n = t = 1`;
7. `t = 1` splits `[0,16)` into sixteen singleton leaves at depth 4 (nodes 31);
8. the depth limit rejects exactly the trees that exceed it (and accepts the exact bound);
9. sum reducer over ordered results (`6`, empty `0`, negatives);
10. max reducer (`Some(max)`, `None` when empty, one result);
11. concat joins per-leaf vectors in order, including empty chunks;
12. tree result slots are writable, read back in leaf order, and oob is rejected;
13. bottom-up sum reduction fills internal nodes and the root (`1,2,3,4 -> 10`);
14. bottom-up max reduction with positives, negatives and a lone leaf;
15. accessors report counts, bounds and out-of-range sentinels;
16. the tree invariant holds for `n <= 25, t <= 6` and rejects corruption (weight/flag/parent);
17. owner push/pop is LIFO; pop on empty is `None`;
18. thieves take the oldest item first; trace is `"7:10,9:20,7:30"` and conservation holds;
19. steal validation: negative thief and empty deque leave the state unchanged;
20. tree-to-deque integration: leaf ids flow through `fdj_tree_push_leaves`, then steals/pops; `fdj_stats` joins tree and deque facts;
21. stats of a single-leaf tree and an untouched deque;
22. invariants hold across 240 splits (`n <= 40`, `t <= 6`) and 30 deque transitions.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.forkjoin
```

Last verified: compiler v0.62.1, `port: PASS (passed=22 failed=0
program_exit=0 exit=0)`.

## 10. Compiler / stdlib notes for v0.62.1

- Free functions only (no methods), with explicit `&`/`&mut` parameters and
  explicit `&mut` at every mutating call site (omitting it can silently write
  to a copy; E001 advisories otherwise).
- `Ok`/`Err` are constructed only inside the `_ok_*` / `_err_*` leaf helper
  functions; struct literals are built at their construction sites and
  returned through those helpers.
- `Vec[Int]` element reads are bound with a typed `let` before use.
- All parallel node Vecs are appended by one `_push_node` helper in a single
  function, and both deque trace Vecs are pushed in the same function, so the
  parallel arrays can never skew.
- Str equality (tests) goes through `str_compare`; `==` on `Str` values read
  from Vec elements lowers to a pointer comparison.
- `fdj_deque_trace_is` uses `string.str_compare` (the only `xiom.string` use
  in the library; `xiom.convert.int_to_string` renders the traces and ranges).
- No `Vec[StructType]` (parallel Vec fields instead), no indexed `Vec[fn]`
  dispatch, no generic callbacks, no `Vec[Float64]`, no `mut` in match
  patterns, no FFI, no threads, no `log`-named function.
- `FDJ`-prefixed names keep every symbol unique in the module (no
  overloading); no locals named `fn`, `use` or `as`.
- `fdj_concat` takes `&Vec[Vec[Int]]`; nested `Vec` parameters and typed
  nested element reads (`let chunk: Vec[Int] = chunks[i];`) are supported.
- Depth is a policy value, never a recursion limit: the split is iterative.

## 11. Known limitations

- The model is single-threaded and non-atomic; a concurrent runtime must
  provide the critical section around every deque transition.
- `fdj_deque_steal` rebuilds the tail (O(queue length)); very long deques
  want a ring buffer or an owner-end removal policy.
- Leaf payloads/bodies are not modeled; only `Vec[Int]` result slots and
  per-leaf result vectors (`fdj_concat`) exist. There is no automatic
  leaf-to-result storage.
- Splitting is fixed halving with no weighted or adaptive splitter, and no
  split-policy callback (no `[T,U]` callbacks on this compiler line).
- `n = 0` is an error by design; an empty work range is not a split.
- The depth limit is a policy check, not a workaround for stack growth (the
  build loop is iterative).
- No cancellation, no exceptions, no result aggregation across deque steals
  beyond the trace; the runtime decides what an `item` id means.
