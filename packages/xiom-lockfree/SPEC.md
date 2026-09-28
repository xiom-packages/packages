# xiom.lockfree -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.lockfree` (`src/lockfree.xi`). Pure XIOM, no FFI.

## 1. Scope

Deterministic single-threaded models of three classic lock-free algorithms,
expressed as explicit atomic-step sequences:

- **Treiber stack** over a pre-sized node pool, with a head word packing an
  ABA tag and a node index;
- **bounded MPMC ring queue** with monotonic head/tail counters and an exact
  element count for full/empty disambiguation;
- **atomic counter** with CAS-step emulation (`counter_cas_step`),

plus state-dump helpers for tests and a pinned error catalog. Each fallible
operation returns `Result[Int, LockfreeError]`.

The module never spawns a thread, never executes an atomic instruction, never
reads a clock and never calls FFI (including `xiom.sync`). Concurrency is
modeled, not executed: an operation is the same read-snapshot / compute /
CAS-step / retry loop a real implementation uses, and the CAS step is a
public function whose success and failure branches tests can drive directly.
In a single deterministic thread the internal CAS always succeeds on the
first attempt; real contention, liveness and memory ordering are out of
scope.

## 2. Non-goals

- Real threads, atomics, fences/memory ordering, spinning or blocking.
- Safe memory reclamation (hazard pointers, epochs, RCU, garbage lists); ABA
  is modeled with a tag, but the ABA reclamation hazard is not solved.
- Multiple concurrent instances or handles: state is module-level, so there
  is exactly one stack, one queue and one counter per process.
- Timed waits, fairness, progress guarantees, wall-clock behavior.
- Hashing, resizing, dynamic growth, iteration order guarantees beyond LIFO
  (stack) and FIFO (queue).
- Any FFI.

## 3. Treiber stack

### 3.1 Node pool

Storage is parallel primitive vectors, one entry per node index
`0..capacity-1`: `value`, `next` and a `free` list link. `stack_configure`
pre-sizes every vector with exactly `capacity` mirrored pushes and chains the
free list `0 -> 1 -> ... -> capacity-1 -> -1`; no later push reallocates.
`capacity` must be in `1..4096` (default 16, built lazily on first use).
A push takes the free-list head; a pop returns the node to the free-list
head. Exhaustion (`free_head == -1`, i.e. `count == capacity`) is
`Err` code 3.

### 3.2 Head word packing

The modeled atomic head word packs a tag and a node index into one Int:

```
stride = capacity + 1
token  = tag * stride + (index + 1)
index  = token % stride - 1          // -1 encodes empty
tag    = token / stride
```

Residue 0 encodes "no node"; residues 1..capacity encode nodes
0..capacity-1, so `stride = capacity + 1` avoids the collision between node
`capacity - 1` and empty. The fresh state is token 0 (tag 0, empty). Every
successful head CAS increments the tag by exactly one, so
`stack_head_tag()` equals the number of successful head CAS steps since the
last `stack_configure`, and an empty stack after operations still carries the
last tag (`token % stride == 0`). No bitwise operators are used anywhere:
tags are extracted with division and modulo only.

### 3.3 Push (modeled atomic steps)

```
if free list empty            -> Err(3, value, capacity)
idx      = free_head; free_head = free[idx]; value[idx] = value
repeat:
  old      = head                     // snapshot step
  next[idx] = index(old)
  desired  = token(tag(old) + 1, idx)
  if stack_cas_step(old, desired): break   // retry on failure
count += 1
return Ok(desired)
```

The retry re-links the node to the fresh head snapshot. In the deterministic
model the first CAS attempt succeeds.

### 3.4 Pop (modeled atomic steps)

```
if index(head) < 0            -> Err(2, -1, capacity)
repeat:
  old      = head                     // snapshot step
  idx      = index(old)
  desired  = token(tag(old) + 1, next[idx])
  if stack_cas_step(old, desired): break   // retry on failure
value = value[idx]; release idx to the free list
count -= 1
return Ok(value)
```

`stack_peek` performs the same empty check and reads `value[index(head)]`
without mutating anything.

### 3.5 ABA tags

After `push A`, `pop`, `push B`, node 0 is reused: the two push tokens name
the same node index but have different tags (`1` vs `3` with capacity 2), so
a stale token from the first push can never equal the fresh head word. A
successful push or pop increments the tag whether or not the node index
changes; a failed CAS leaves the head word untouched and only bumps
`stack_cas_failures()`.

### 3.6 Raw CAS step

`stack_cas_step(expected, desired)` performs one modeled atomic step: if
`head == expected`, store `desired`, count a success and return true; else
count a failure and return false. It is the exact step the retry loops use,
exposed for tests. It does not maintain pool invariants; pass only tokens
consistent with the structure (`stack_cas_step(t, t)` with the current token
is always safe).

## 4. Bounded MPMC ring queue

### 4.1 Counters and slots

`queue_configure` pre-fills `capacity` data slots (`1..65536`, default 16)
and zeroes `head`, `tail` and the statistics. `head` and `tail` are
**monotonic operation counters**, not slot indices: the next enqueue writes
slot `tail % capacity` and the next dequeue reads slot `head % capacity`.
Counters keep growing past `capacity` (12 laps of a 5-slot ring reach
head = tail = 60 in the tests); the ring wraps because the slot index is the
counter modulo capacity.

### 4.2 Full/empty disambiguation

`head == tail` (even modulo capacity) is ambiguous between full and empty, so
the model maintains an exact element `count` as the disambiguator
(equivalent to a per-lap phase bit):

- empty: `count == 0` (`queue_is_empty`),
- full: `count == capacity` (`queue_is_full`),
- enqueue: rejected with `Err` code 6 before any write when full,
- dequeue: rejected with `Err` code 5 before any read when empty.

In a real MPMC queue the count would be an atomic that is updated in the same
linearization step as the slot CAS; the model documents that pairing.

### 4.3 Enqueue / dequeue (modeled atomic steps)

```
enqueue(v):
  if count == capacity        -> Err(6, v, capacity)
  repeat:
    old = tail                          // snapshot step
    data[old % capacity] = v            // publish payload
    if queue_cas_tail_step(old, old+1): break   // retry on failure
  count += 1; return Ok(old % capacity)

dequeue():
  if count == 0               -> Err(5, -1, capacity)
  repeat:
    old = head                          // snapshot step
    v   = data[old % capacity]
    if queue_cas_head_step(old, old+1): break   // retry on failure
  count -= 1; return Ok(v)
```

The count is bumped only after the slot CAS succeeds, so a successful
enqueue/dequeue is one modeled atomic step that both publishes/consumes the
slot and moves the count. Both CAS probes are public and count
`queue_cas_successes()` / `queue_cas_failures()`.

### 4.4 Wrap-around

With capacity 3: enqueue 1,2,3 fills slots 0,1,2; dequeue 1 moves head to 1;
enqueue 4 writes slot 0 (`tail = 3`, `3 % 3 = 0`); and so on. The order
guarantee is FIFO; `queue_enqueue` returns the slot index it used, which
makes wrap-around directly visible (`Ok(0)` again after three enqueues).

## 5. Atomic counter

### 5.1 Range

The counter is an Int in `[0, 2^62 - 1]` = `[counter_min(), counter_max()]`.
The limit keeps every intermediate sum inside i64:
`|value| <= limit and |delta| <= limit` imply
`|value + delta| <= 2^63 - 2`. `counter_reset(v)` stores `v` and clears the
statistics (documented setup helper; the range contract is the caller's).
The raw `counter_cas_step(expected, desired)` stores `desired` unconditionally
on a match (same probe contract as the stack step).

### 5.2 counter_add (CAS-loop)

```
if |delta| > limit            -> Err(7|8, delta, current)   // pre-guard
repeat:
  cur       = value                   // snapshot step
  candidate = cur + delta
  if candidate > counter_max() -> Err(7, delta, current)     // no mutation
  if candidate < counter_min() -> Err(8, delta, current)     // no mutation
  if counter_cas_step(cur, candidate): break    // retry on failure
return Ok(candidate)
```

On `Err` the counter is unchanged, the call is not counted in
`counter_add_count()`, and no failure CAS is counted (the range check happens
before the CAS). The success count equals the number of successful
`counter_cas_step` calls.

### 5.3 counter_add_saturating (CAS-loop, clamped)

`delta` is clamped before the addition, then `cur + delta` is clamped to
`[counter_min(), counter_max()]` (high and low), and the candidate is
installed with the same CAS loop. It never returns `Err`, counts one
successful CAS per call, and increments
`counter_saturating_add_count()`. Examples: `max - 2` plus 10 saturates at
`max`; `2` plus `-10` saturates at `0`; adding `max` twice from 0 stays at
`max`.

## 6. Error catalog

`LockfreeError = { code: Int; value: Int; extra: Int; }`. `value` is the
offending input (-1 when none); `extra` is the bound or current context (-1
when none). `lockfree_error_message` is pinned:

| Code | Message | Trigger (`value`, `extra`) |
|---|---|---|
| 1 | `lockfree: stack capacity out of range` | stack_configure with capacity < 1 or > 4096 (`value` = capacity, `extra` = 4096) |
| 2 | `lockfree: stack is empty` | stack_pop / stack_peek on an empty stack (`value` = -1, `extra` = capacity) |
| 3 | `lockfree: stack node pool exhausted` | stack_push with all capacity nodes stacked (`value` = pushed value, `extra` = capacity) |
| 4 | `lockfree: queue capacity out of range` | queue_configure with capacity < 1 or > 65536 (`value` = capacity, `extra` = 65536) |
| 5 | `lockfree: queue is empty` | queue_dequeue with count == 0 (`value` = -1, `extra` = capacity) |
| 6 | `lockfree: queue is full` | queue_enqueue with count == capacity (`value` = rejected value, `extra` = capacity) |
| 7 | `lockfree: counter overflow` | counter_add whose result would exceed `counter_max()` (`value` = delta, `extra` = value before the call) |
| 8 | `lockfree: counter underflow` | counter_add whose result would drop below `counter_min()` (same fields) |
| other | `lockfree: unknown error` | any code outside 1..8 |

Failed `stack_configure` / `queue_configure` leave the previous configuration,
entries and counters untouched. Failed push/pop/enqueue/dequeue/add calls
change no state and are not counted as successful operations.

## 7. API signatures

```xi
// Stack
pub fn stack_configure(capacity: Int) -> Result[Int, LockfreeError]
pub fn stack_max_capacity() -> Int
pub fn stack_capacity() -> Int
pub fn stack_count() -> Int
pub fn stack_free_count() -> Int
pub fn stack_head_token() -> Int
pub fn stack_head_index() -> Int
pub fn stack_head_tag() -> Int
pub fn stack_cas_successes() -> Int
pub fn stack_cas_failures() -> Int
pub fn stack_push_count() -> Int
pub fn stack_pop_count() -> Int
pub fn stack_cas_step(expected: Int, desired: Int) -> Bool
pub fn stack_push(value: Int) -> Result[Int, LockfreeError]
pub fn stack_pop() -> Result[Int, LockfreeError]
pub fn stack_peek() -> Result[Int, LockfreeError]
pub fn stack_dump() -> Str

// Ring queue
pub fn queue_configure(capacity: Int) -> Result[Int, LockfreeError]
pub fn queue_max_capacity() -> Int
pub fn queue_capacity() -> Int
pub fn queue_count() -> Int
pub fn queue_head_counter() -> Int
pub fn queue_tail_counter() -> Int
pub fn queue_is_empty() -> Bool
pub fn queue_is_full() -> Bool
pub fn queue_cas_successes() -> Int
pub fn queue_cas_failures() -> Int
pub fn queue_enqueue_count() -> Int
pub fn queue_dequeue_count() -> Int
pub fn queue_cas_tail_step(expected: Int, desired: Int) -> Bool
pub fn queue_cas_head_step(expected: Int, desired: Int) -> Bool
pub fn queue_enqueue(value: Int) -> Result[Int, LockfreeError]
pub fn queue_dequeue() -> Result[Int, LockfreeError]
pub fn queue_dump() -> Str

// Counter
pub fn counter_reset(v: Int)
pub fn counter_get() -> Int
pub fn counter_min() -> Int
pub fn counter_max() -> Int
pub fn counter_cas_successes() -> Int
pub fn counter_cas_failures() -> Int
pub fn counter_add_count() -> Int
pub fn counter_saturating_add_count() -> Int
pub fn counter_cas_step(expected: Int, desired: Int) -> Bool
pub fn counter_add(delta: Int) -> Result[Int, LockfreeError]
pub fn counter_add_saturating(delta: Int) -> Int
pub fn counter_dump() -> Str

// Combined / catalog
pub fn lockfree_dump() -> Str
pub fn lockfree_error_message(code: Int) -> Str
```

All non-raw operations are O(1); stack/queue configure is O(capacity); the
dumps are O(capacity).

## 8. State dumps

Test-facing one-line formats (fragment-matched by the suite):

```
stack[cap=.. count=.. head_idx=.. head_tag=.. free=.. top=a,b cas_ok=.. cas_fail=..]
queue[cap=.. count=.. head=.. tail=.. full=0/1 empty=0/1 slots=a,b,.. cas_ok=.. cas_fail=..]
counter[value=.. min=.. max=.. cas_ok=.. cas_fail=.. adds=.. sat_adds=..]
```

`top=` lists the stack from top to bottom; empty prints nothing after `top=`.
`slots=` lists the raw ring slots in index order (including stale values in
already-consumed slots). `lockfree_dump()` joins the three lines with `"\n"`.

## 9. Test plan

`tests/test_conformance.xi` (module `lockfree_tests`) runs 21 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every fixture is built in-test; the configure
calls are full resets, so the suite is order-independent.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | stack push/pop/peek with capacity 4 | LIFO order, token arithmetic 6/12/18, tag 1..6, empty token 30, statistics |
| t2 | empty pop/peek | Err code 2 with (-1, capacity), recovery push/pop, failed pop not counted |
| t3 | ABA | node 0 reused: tokens 4 then 10, tags 1 then 3, stale token differs |
| t4 | pool exhaustion | Err code 3 at capacity, node reuse after pop, capacity 2 tokens |
| t5 | stack CAS probes | stale expected fails (counted), `cas(t, t)` succeeds, push/pop after |
| t6 | peek | repeated peeks do not mutate; peek on empty is Err code 2 |
| t7 | queue FIFO | slots 0,1,2; counters 0/3; enqueue/dequeue counts; empty error |
| t8 | full/empty | Err codes 5/6 with capacity, count-based transitions, slot 0 reuse |
| t9 | wrap-around | capacity 3, head/tail reach 5 after 5 operations, FIFO across laps |
| t10 | queue CAS probes | stale tail/head probes fail (counted), no-op successes, sequential ops |
| t11 | capacity validation | codes 1/4 with (capacity, max), previous config kept, bounds 1/4096/65536 accepted |
| t12 | counter CAS success | `cas(5, 9)` true, value 9, one success, range accessors |
| t13 | counter CAS failure | `cas(6, 9)` false, value unchanged, one failure, then success |
| t14 | counter add | CAS loop returns 7/12/12, add count and CAS count match |
| t15 | counter bounds | codes 8/7 with (delta, value), no mutation, `max-2` boundary, add count |
| t16 | saturating | clamp high (`max-2`+10), clamp low (2-10), 0+max stays max, counts |
| t17 | dumps | stack/queue/counter fragments, raw slots `4,0`, combined dump sections |
| t18 | error catalog | all eight pinned messages plus unknown codes 0 and 99 |
| t19 | independence | per-structure statistics and state do not leak across structures |
| t20 | stack stress | 25 rounds x 4 push/pop through a 4-node pool: 200 CAS, tag 200, token 1000 |
| t21 | queue stress | 12 rounds x 5 FIFO elements through a 5-slot ring: head/tail 60, 120 CAS |

Str equality goes through `xiom.string.compare`'s `str_compare` (BUG 17
discipline); dumps are matched with `xiom.string.str_contains`. Tests consume
each `Result` exactly once; no `Vec[fn]` indexed dispatch and no `Vec[Str]`
element equality are used.

## 10. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the timer / scheduler
pure-model idioms and documents these compiler-driven choices
(XIOM v0.62.x):

- `Vec[StructType]` is unsupported, so every structure is parallel
  `Vec[Int]` fields (stack `value`/`next`/`free`; queue `data`) and
  `LockfreeError` is only ever a scalar struct constructed in the leaf
  helpers.
- `Ok`/`Err` are constructed only inside `_lf_ok` / `_lf_err`, never directly
  in a public body.
- Every `Vec[Int]` element read is bound with a typed `let` first.
- No bitwise operators (`&`, `|`, shifts) anywhere: tags are packed and
  unpacked with `*`, `/` and `%`, so no sign-bit or precedence issues arise.
- Module header has no trailing semicolon; each `use` has one. Free
  functions only; no methods; no `&mut` out-parameters (results returned).
- Parallel vectors are filled with mirrored pushes in one loop per structure.
- Modulo/division operands are non-negative by construction (tokens, ring
  counters and the counter range), so truncation semantics are exact.

## 11. Known limitations

- The model is deterministic: internal CAS never fails; only the raw probes
  produce failures. There is no real interleaving, no memory ordering, no
  liveness/fairness and no progress guarantee.
- ABA is demonstrated through tag increments; safe reclamation of popped
  nodes is not part of the model (no hazard pointers/epochs).
- One module-level instance per structure; configure/reset are full resets,
  not resizes; no handles, no generics.
- Monotonic ring counters and CAS tags grow without masking; only the ring
  slot index wraps (`counter % capacity`). Tag arithmetic would overflow far
  beyond any realistic test scale.
- The exact `count` is the only full/empty disambiguator; a phase-bit
  variant is described but not implemented.
- `counter_reset` and the raw CAS probes are setup/test helpers: they do not
  validate range or structural invariants.
- Dump formats are test-facing and not a stable public API.
- Errors carry no position information beyond the (code, value, extra)
  triple.
