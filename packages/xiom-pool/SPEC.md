# xiom.pool -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.pool` (`src/pool.xi`). Pure XIOM, no FFI, no threads.

## 1. Scope

A deterministic fixed-capacity pool of integer slots:

- `pool_new` builds the pool; capacity is fixed for its lifetime;
- `pool_borrow` / `pool_borrow_lease` hand out a free slot (raw id or lease
  token);
- `pool_release` / `pool_release_lease` return a slot, the latter
  generation-checked;
- `pool_drain` releases everything;
- read-only accessors expose capacity, in-use/available counts, the
  high-water mark, lifetime totals, slot state and slot generation.

The pool never allocates after construction, never blocks, never runs
destructors and never stores the caller's resources: it manages the slot
lifecycle, and callers index their own storage by slot id.

## 2. Non-goals

- **No generic resource storage**: XIOM v0.61.3 cannot hold
  `Vec[StructType]`; the pool is a slot allocator, not a container.
- **No thread safety**: no mutexes, atomics, blocking waits, or cross-thread
  publication. The state machine is single-threaded by construction.
- **No automatic release**: there are no destructors in XIOM; release is
  always explicit.
- **No growth or shrinking**: capacity is fixed at construction.
- **No lease cryptography**: lease tokens are opaque integers, not secrets
  or capabilities.
- No FFI, no file I/O, no registry integration; in-memory only.

## 3. Data model

```xi
pub type Pool = {
  capacity: Int;
  free: Vec[Int];        // free-slot stack; borrow pops, release pushes
  borrowed: Vec[Int];    // per slot: 1 = borrowed, 0 = free
  generations: Vec[Int]; // per slot: 0 before first borrow
  in_use: Int;
  high_water: Int;
  borrows: Int;
  releases: Int;
}
```

Invariants maintained by every operation:

- `free` contains each free slot id exactly once (a stack, top at the end);
- `borrowed` and `generations` have length `capacity` and are indexed by
  slot id;
- `in_use` equals the number of `borrowed` entries equal to 1 and also
  `capacity - free.len()`;
- `capacity == in_use + available`;
- `high_water >= in_use` and never decreases;
- `borrows` / `releases` never decrease and only count successful
  operations (a drain adds its released count to `releases`).

## 4. Semantics

1. **Fresh order.** `pool_new(c)` initializes the free stack so that a fresh
   pool hands out `0`, then `1`, ..., `c-1`. Internally the ids are pushed
   in descending order and popped from the end.
2. **Capacity clamp.** `c < 0` is clamped to 0. A zero-capacity pool is
   valid and every borrow fails with `pool: exhausted`.
3. **Borrow.** Pops the top of the free stack, sets `borrowed[id] = 1`,
   increments `generations[id]` by 1, `in_use` and `borrows`, and raises
   `high_water` when the new `in_use` exceeds it.
4. **Exhaustion.** When the free stack is empty, `pool_borrow` and
   `pool_borrow_lease` return `Err("pool: exhausted")` and change nothing.
5. **LIFO reuse.** A released slot is pushed back and is therefore the next
   slot handed out.
6. **Raw release.** `pool_release(p, id)` validates `id` in
   `[0, capacity)`, then requires `borrowed[id] == 1`; on success it clears
   the flag, pushes the id, decrements `in_use` and increments `releases`.
   A repeated release is rejected (`slot <id> is not borrowed`), so a slot
   can never appear twice in `free`.
7. **Lease encoding.** `pool_borrow_lease` issues
   `lease = generation * (capacity + 1) + id`, where `generation` is the
   value just after the borrow's increment. Leases are therefore `>= 1` and
   distinct for every borrow of every slot of this pool. With
   `capacity == 0` no lease is ever issued.
8. **Lease validation.** `pool_release_lease` decodes `id` and `generation`
   from the token. A token that is negative, or whose generation part is
   `0`, or whose slot part is `>= capacity`, is `bad`. A decodable token
   whose generation does not equal `generations[id]`, or whose slot is not
   currently borrowed, is `stale`. Only an exact, current lease releases the
   slot.
9. **Generation lifetime.** `generations[id]` starts at 0, increments on
   every borrow and is not reset by release or drain, so a lease from any
   earlier borrow cycle stays stale forever.
10. **High water.** `high_water` is the maximum of `in_use` over the pool's
    lifetime; it never decreases.
11. **Drain.** `pool_drain` clears every borrowed slot, rebuilds the free
    stack in fresh-pool order (`0` first), sets `in_use` to 0 and adds the
    released count to `releases`. It returns the count; an idle pool
    returns 0 and changes nothing (including `releases`).
12. **Determinism.** Every operation is a pure function of the state and its
    arguments; the same call sequence always produces the same results.

## 5. Error catalog

| Condition | Exact message |
|---|---|
| `pool_borrow` / `pool_borrow_lease` with no free slot | `pool: exhausted` |
| `pool_release` with `id < 0` or `id >= capacity` | `pool: bad slot <id>` |
| `pool_release` of a free slot (including a repeated release) | `pool: slot <id> is not borrowed` |
| `pool_release_lease` with an undecodable token | `pool: bad lease <lease>` |
| `pool_release_lease` with a decodable but outdated or non-borrowed token | `pool: stale lease <lease>` |

Failed operations never mutate the pool.

## 6. API contract

```xi
pub fn pool_new(capacity: Int) -> Pool
pub fn pool_capacity(p: &Pool) -> Int
pub fn pool_in_use(p: &Pool) -> Int
pub fn pool_available(p: &Pool) -> Int
pub fn pool_high_water(p: &Pool) -> Int
pub fn pool_total_borrows(p: &Pool) -> Int
pub fn pool_total_releases(p: &Pool) -> Int
pub fn pool_is_borrowed(p: &Pool, id: Int) -> Bool
pub fn pool_generation(p: &Pool, id: Int) -> Int
pub fn pool_borrow(p: &mut Pool) -> Result[Int, Str]
pub fn pool_borrow_lease(p: &mut Pool) -> Result[Int, Str]
pub fn pool_release(p: &mut Pool, id: Int) -> Result[Int, Str]
pub fn pool_release_lease(p: &mut Pool, lease: Int) -> Result[Int, Str]
pub fn pool_drain(p: &mut Pool) -> Int
```

Out-of-range reads: `pool_is_borrowed` -> `false`, `pool_generation` ->
`-1`. `pool_available` is clamped at 0 (it never returns a negative number
even if a hand-built `Pool` has inconsistent counters).

Complexity: `pool_new` and `pool_drain` are O(capacity); every other
operation is O(1).

## 7. Test matrix

`tests/test_conformance.xi` (module `pool_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All string comparisons go through `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | fresh pool | section 4 rule 1, counters |
| t2 | ascending borrow order | rule 1 |
| t3 | exhaustion | rule 4 |
| t4 | zero/negative capacity | rule 2 |
| t5 | LIFO reuse | rule 5 |
| t6 | raw release errors | rule 6, section 5 |
| t7 | lease encoding | rule 7 |
| t8 | stale leases | rule 8 |
| t9 | bad leases | rule 8 |
| t10 | high water | rule 10 |
| t11 | generations | rule 9 |
| t12 | drain | rule 11 |
| t13 | lifetime totals | rule 3, 6 |
| t14 | capacity invariant | section 3 |
| t15 | leases + raw borrows share the stack | rules 5, 7 |
| t16 | single-slot generations | rules 7, 9 |
| t17 | drain of an idle pool | rule 11 |
| t18 | generation bump invalidates lease | rules 8, 9 |
| t19 | available/in_use range | section 3 |
| t20 | lease uniqueness | rule 7 |
| t21 | accessor bounds | section 6 |
| t22 | drain vs leased slots | rule 11 |

## 8. Known limitations

- The pool stores no resources; slot ids are the only payload.
- No thread safety: concurrent use requires external synchronization.
- No automatic release; explicit release or drain only.
- Lease tokens are valid only for the issuing pool instance and are not
  authenticated.
- Generations are unbounded `Int`s; an eventual wrap would alias old leases
  (not reachable in practice).
- A hand-built `Pool` with inconsistent counters is not repaired; behavior
  is undefined except that accessors stay in bounds and `available` clamps
  at 0.

## 9. Compiler / stdlib notes (v0.61.3)

Free functions only, flat parallel `Vec`s instead of `Vec[StructType]`,
`Vec.pop()` returning `Option[T]` matched exhaustively, and `Result`
construction confined to the leaf helpers `_ok_int` / `_err_int`. Every
`Int` read from a `Vec[Int]` element is bound to a typed local before
comparison. The mutation helpers (`_take_free`, `_mark_borrowed`,
`_put_back`) take `&mut Pool` and are called with an explicit `&mut` at
every call site, per the v0.61.3 write-through rule. The test module emits
benign E001 "cannot borrow 'p' as mutable while immutably borrowed"
warnings on the interleaved `&`/`&mut` calls (the same advisory class seen
in `xiom.tls`); they do not affect the run, and the suite is green with
`program_exit=0`.
