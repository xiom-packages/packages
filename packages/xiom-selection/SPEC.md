# xiom.selection -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.selection` (`src/selection.xi`). Pure XIOM, no FFI.

## 1. Scope

Deterministic selection operators for evolutionary and genetic loops over
`Int` weight/fitness vectors:

- weight summing with the negative-as-zero rule (`sel_sum`),
- roulette-wheel selection with an explicit draw (`sel_roulette_index`) and a
  seeded variant (`sel_roulette`),
- tournament selection (`sel_tournament_index`),
- elite selection (`sel_elite_indices`),
- best/worst index queries (`sel_best_index`, `sel_worst_index`),
- linear rank weights (`sel_rank_weights`).

There is no clock, environment, file or OS randomness source: every operator is
a pure function of its arguments, so every run replays exactly.

## 2. Non-goals

- No Float64 or other weight/fitness element types.
- No `Vec[StructType]`, generics or callbacks (compiler v0.61.3 limits).
- No stochastic hill climbing, mutation, crossover or population containers:
  this package only *selects* indices.
- No statistically validated or cryptographic randomness.
- No allocation-free or indexed data structures: scans are linear.
- No FFI, threading or time dependence.

## 3. Data model

`Int` is a signed 64-bit two's-complement integer. Weights and fitnesses are
plain `Vec[Int]`; the operators never store derived vectors except
`sel_elite_indices`' result and the internal index order (O(n) extra space).

**Negative-as-zero rule.** In every operator, a negative weight/fitness entry
is treated as 0 for selection purposes: `sel_sum` adds `max(w, 0)` and the
cumulative walk skips entries with `w <= 0`. `sel_elite_indices`,
`sel_best_index` and `sel_worst_index` compare raw fitness values (they choose
they extreme, so negative values are meaningful there).

## 4. PRNG definition

A 31-bit xorshift-style mixer over an `Int` state. All shifts below are
performed on the value as written; the recipe only left-shifts values already
masked below `2^56`, so no shift overflows for any `Int` input, including the
`Int` minimum.

### 4.1 Core

```
mix(v):
  h = v
  h = h ^ (h >> 13)            // arithmetic shift; sign may appear here
  h = h & 0x00FFFFFFFFFFFFFF   // clear the top 8 bits (drop the sign)
  h = h ^ (h << 7)             // h < 2^56 here, so h << 7 stays < 2^63
  h = h ^ (h >> 17)
  h = h & 0x7FFFFFFF           // 31-bit mask: result in [0, 2^31 - 1]
  return h

seed_state(seed):
  s = mix(seed)
  if s == 0 { s = 0x1F123BB5 }
  return s

rng_next(state):
  h = state
  h = h ^ (h >> 13)
  h = h ^ (h << 7)             // state < 2^31, so this is < 2^38
  h = h ^ (h >> 17)
  h = h & 0x7FFFFFFF
  if h == 0 { h = 0x1F123BB5 }
  return h
```

`seed_state` and `rng_next` are private (`_sel_` prefix) implementation
details; they are pinned here because the seeded operators' outputs depend on
the exact bit recipe.

### 4.2 Guarantees

1. `seed_state(seed)` and `rng_next(state)` are always in `[1, 2^31 - 1]`:
   non-negative, never 0 (the zero fixed point is replaced by the constant
   `0x1F123BB5`), for every `Int` input including negatives and 0.
2. Same state => same output, on every platform and every run.
3. The mixer is a test-grade scramble, not a validated PRNG; it is not
   suitable for cryptography, simulation or any adversarial setting.

## 5. Roulette

### 5.1 `sel_sum(weights)`

Sum of `max(weights[i], 0)` in index order; 0 for an empty or all-nonpositive
vector. O(n). Precondition (documented): the sum fits in an `Int`.

### 5.2 `sel_roulette_index(weights, draw)`

Deterministic core; no PRNG. Walks the cumulative sum of the positive weights
in index order and returns the first index `i` with
`cumulative(i) > draw` (equivalently, the bucket
`[cumulative(i-1), cumulative(i))` containing `draw`). Returns `-1` without
trapping when:

- `draw < 0`, or
- `draw >= sel_sum(weights)` (which includes the empty and all-zero vector).

So the function is total: every `(weights, draw)` pair yields a valid index or
`-1`. O(n).

### 5.3 `sel_roulette(weights, seed)`

```
total = sel_sum(weights)
if total <= 0 { return -1 }                      // no draw is consumed
draw = rng_next(seed_state(seed)) % total        // exactly one PRNG draw
return sel_roulette_index(weights, draw)
```

The modulo reduction is slightly biased when `total` is not a power of two
(standard `%` caveat); the draw itself is exact. O(n).

## 6. Tournament

`sel_tournament_index(fitness, k, seed)`:

```
n = len(fitness)
if n == 0 { return -1 }                          // no draw is consumed
k' = clamp(k, 1, n)                              // k <= 0 means one contender
state = seed_state(seed)
best = -1
for c in 0 .. k'-1:
  state = rng_next(state)                        // exactly one draw per contender
  pick = state % n                               // sampling with replacement
  if best == -1 or fitness[pick] > fitness[best]           { best = pick }
  elif fitness[pick] == fitness[best] and pick < best      { best = pick }
return best
```

Rules:

- `k` is clamped to `[1, n]`: `k <= 0` samples one contender, `k > n` samples
  `n` contenders (not more).
- Contenders are sampled with replacement; the same index may be drawn again
  (a repeat of the current best changes nothing).
- Ties keep the earlier (smaller) index: an equal-fitness contender replaces
  the incumbent only when its index is smaller, so the winner is the smallest
  index among the sampled contenders that attain the best fitness.
- O(k' + n): one PRNG step and one fitness read per contender.

## 7. Elite

`sel_elite_indices(fitness, k)`:

```
n = len(fitness)
if k <= 0 or n == 0 { return [] }
order = [0, 1, ..., n-1]
insertion sort order by key (fitness desc, index asc):
  for a in 1 .. n-1:
    key = order[a]; key_fitness = fitness[key]; b = a
    while b > 0 and fitness[order[b-1]] < key_fitness:
      order[b] = order[b-1]; b = b - 1
    order[b] = key
return order[0 .. min(k, n) - 1]
```

- The insertion sort is **stable**: the scan shifts an element right only when
  its fitness is strictly lower than the key's, so equal fitness keeps the
  pre-existing (ascending) index order. The key is `(fitness desc, index asc)`
  exactly.
- `k` is clamped to `n`; `k <= 0` yields an empty vector (not an error).
- Complexity: O(n^2) worst case, O(n) on near-sorted inputs; O(n) extra space.

## 8. Best / worst / rank

- `sel_best_index(fitness)`: smallest index attaining the maximum; `-1` for an
  empty vector. Strict `>` scanning keeps the first occurrence on ties. O(n).
- `sel_worst_index(fitness)`: smallest index attaining the minimum; `-1` for an
  empty vector. Strict `<`. O(n).
- `sel_rank_weights(n)`: `[n, n-1, ..., 1]`; empty for `n < 1`. O(n).

## 9. Tie rules (summary)

| Operator | Tie rule |
|---|---|
| `sel_roulette_index` | No ties: the first bucket containing the draw wins. |
| `sel_tournament_index` | Equal fitness: smaller index wins; repeats change nothing. |
| `sel_elite_indices` | Equal fitness: earlier (smaller) index first (stable). |
| `sel_best_index` | First occurrence of the maximum. |
| `sel_worst_index` | First occurrence of the minimum. |

## 10. API signatures

```xi
pub fn sel_sum(weights: &Vec[Int]) -> Int
pub fn sel_roulette_index(weights: &Vec[Int], draw: Int) -> Int
pub fn sel_roulette(weights: &Vec[Int], seed: Int) -> Int
pub fn sel_tournament_index(fitness: &Vec[Int], k: Int, seed: Int) -> Int
pub fn sel_elite_indices(fitness: &Vec[Int], k: Int) -> Vec[Int]
pub fn sel_best_index(fitness: &Vec[Int]) -> Int
pub fn sel_worst_index(fitness: &Vec[Int]) -> Int
pub fn sel_rank_weights(n: Int) -> Vec[Int]
```

## 11. Test plan

`tests/test_conformance.xi` (module `selection_tests`) runs 25 named checks
through `assert(cond, "name")`, one `fn` per check; `main` returns the failure
count (0 = green). PRNG-dependent expectations are pinned constants derived
from the recipe in section 4 and cross-checked with an independent simulator.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | sum: empty/positive/negative/zero | `max(w,0)` rule, empty = 0 |
| t2 | sum: single/large/all-negative | large sums, negatives contribute 0 |
| t3 | roulette_index `[3,5,2]` draws 0,2,3,7,8,9 | every bucket and cumulative edge |
| t4 | roulette_index 10, 11, 999, -1, -999 | out-of-range draws are -1 |
| t5 | roulette_index empty/zeros/`[-4,3,-1,2]` | degenerate vectors, negative entries skipped |
| t6 | roulette `[5,3,2]` seeds 0..9 twice | pinned buckets `[0,1,0,1,0,1,0,1,0,0]`, same-seed stability, negative seed |
| t7 | roulette `[1,1,1]` seeds 0 and 1 | pinned first/last bucket draws |
| t8 | roulette `[1,1,1]` seeds 0..99 | pinned histogram `30/26/44`, results in range |
| t9 | roulette on empty/all-zero/all-negative | always -1 |
| t10 | tournament `[10,20,30,40,50]` seed 12345, seeds 0..4 | same-seed determinism, range |
| t11 | tournament k = 0,1,2,5,99,-7 seed 12345 | pinned winners `0,0,4,4,4,0` (clamp) |
| t12 | tournament 100-element, k = 10/100/500/1000 seed 5 | pinned `65`; k >= n all clamp to the same winner `30` |
| t13 | tournament all-equal `[7,7,7,7]` k=3,4; `[3,1,3,1]` k=4 | earliest sampled index wins ties |
| t14 | tournament empty (k=5,0) and single (k=5,-3) | -1 empty; 0 for one element |
| t15 | tournament `[1,2,3,2,1]` k=5 seed 3; `[10..50]` seed 12345 | pinned highest-fitness winners |
| t16 | elite `[5,1,5,3]` k=1,2,3,4,9 | pinned `[0] [0,2] [0,2,3] [0,2,3,1]`, sorted check |
| t17 | elite k=0,-2 and empty population | empty vector, no error |
| t18 | elite `[4,4,4]`, `[2,1,2,1]`, `[-5,-5,-1]` | tie stability: ascending index for equal fitness |
| t19 | best/worst `[4,9,9,2]`, `[3,3,3]`, `[-5,-5,-1]`, `[7]` | first occurrence of the extreme |
| t20 | best/worst empty | -1 |
| t21 | rank 0,-3,1,5,2 | `[n..1]`, empty for n < 1 |
| t22 | elite 100-element (pinned generator) | pinned top-5 `[30,60,90,19,49]`, full order is a sorted permutation, top-5 prefix consistency, max = 50 |
| t23 | roulette 100-element (weights 1..100) | pinned draws for seeds 1000..1004, 100-seed determinism, range, total 5050 |
| t24 | tournament 100-element k=10/100/500/1000 seed 5 | pinned `65`, determinism, clamp |
| t25 | roulette `[-4,3,-1,2]` seeds 0..49 | negative entries never selected; pinned histogram `32/18` |

The 100-element fitness generator is `f(i) = (i * 37) % 101 - 50` for
`i in [0, 100)`; its maximum is 50 at index 30.

## 12. Known limitations

- Linear scans; elite is an insertion sort (O(n^2) worst case). No heap/partial
  selection shortcuts.
- Deterministic test-grade PRNG; not cryptographic, no distribution proofs.
- `% total` roulette reduction is slightly biased for non-power-of-two totals.
- `sel_sum` does not detect `Int` overflow (documented precondition).
- `sel_roulette_index` accepts any draw but only draws in `[0, total)` are
  meaningful; other values return -1.
- Int-only weights/fitness; no Float64, no struct elements, no generic element
  types.
- No population-level API (no crossover/mutation/population container); the
  package only selects indices.

## 13. Compiler / stdlib notes

- Free functions only; no `self` methods (XIOM v0.61.x has none).
- No `match`, no `Ok`/`Err`, no inline lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch anywhere in the module or the suite.
- Every `Vec[Int]` element read is bound with an explicitly typed `let`
  (e.g. `let w: Int = weights[i];`) to avoid inference drift.
- The library module has no `use` statements at all (Int/Vec[Int] only); the
  tests `use xiom.io; use xiom.test; use xiom.selection;`.
- The suite contains no string comparison (`==`) on `Str` values; only
  `assert` names are Str, and they are passed through unchanged.
