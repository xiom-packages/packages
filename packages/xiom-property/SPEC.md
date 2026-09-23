# xiom.property -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.property` (`src/property.xi`). Pure XIOM, no FFI.

## 1. Scope

A deterministic, dependency-free property-testing engine for Int and Str
inputs:

- a seeded 31-bit PRNG (`Rng`, `prop_rng_new`, `prop_rng_next`),
- value generators (`prop_rng_bool`, `prop_rng_range`, `prop_rng_string`),
- deterministic seed derivation (`prop_seeds`),
- runners that execute a named predicate over a seed vector and report the
  first counterexample (`prop_run_int`, `prop_run_range`, `prop_run_str`,
  `prop_report_ok`),
- counterexample shrinking toward zero (`prop_shrink_int`).

There is no clock, environment, file or OS randomness source: every value is
a pure function of the seed, so a run replays exactly.

## 2. Non-goals

- No Float64, Bool, collection or user-defined-type generators (the compiler
  v0.61.3 rejects `Vec[Float64]` and generic callbacks).
- No automagic test-framework integration: the caller wires runners into
  `main` (or a future `xiom.test` bridge).
- No shrinking of Str/vector counterexamples (only the Int halving chain).
- No cryptographic or statistically validated randomness.
- No re-generation of dependent inputs during shrinking (no integrated
  shrinking).
- No FFI, threading or time dependence.

## 3. PRNG definition

`Int` is a signed 64-bit two's-complement integer. All shifts below are
performed on the value as written; `>>` on a non-negative value is equivalent
to a logical shift, and the recipe only left-shifts values already masked
below `2^56`, so no shift overflows.

### 3.1 Core mixer

```
mix(v):
  h = v
  h = h ^ (h >> 13)            // arithmetic shift; sign may appear here
  h = h & 0x00FFFFFFFFFFFFFF   // clear the top 8 bits (drop the sign)
  h = h ^ (h << 7)             // h < 2^56 here, so h << 7 stays < 2^63
  h = h ^ (h >> 17)
  h = h & 0x7FFFFFFF           // 31-bit mask: result in [0, 2^31 - 1]
  return h
```

The `0x00FFFFFFFFFFFFFF` mask is what makes the recipe total: after it, the
left shift cannot leave the non-negative domain for any input, including
`Int` minimum. `mix` is a pure function and deterministic.

### 3.2 Construction and advance

```
prop_rng_new(seed):
  state = mix(seed)
  if state == 0 { state = 0x1F123BB5 }
  return Rng{ state }

prop_rng_next(r):
  h = r.state
  h = h ^ (h >> 13)
  h = h ^ (h << 7)             // state < 2^31, so this is < 2^38
  h = h ^ (h >> 17)
  h = h & 0x7FFFFFFF
  if h == 0 { h = 0x1F123BB5 } // zero fixed point is excluded, not entered
  r.state = h
  return h
```

`prop_rng_next` differs from `mix` only in that it skips the
`0x00FFFFFFFFFFFFFF` mask (unnecessary because the state is already
non-negative) and keeps the same zero safety valve. It is a pure function of
the previous state.

### 3.3 Guarantees

1. `prop_rng_next(r)` is always in `[0, 2^31 - 1]` (the final mask) and never
   0, so the state stays in `[1, 2^31 - 1]` forever.
2. Same state => same draw, on every platform and every run.
3. Streams for the same seed are identical; the suite does not assume any
   particular relationship between different seeds (only that a specific
   sampled pair differs).
4. The mixer is a test-grade scramble, not a validated PRNG; it is not
   suitable for cryptography, simulation or any adversarial setting.

## 4. Seed derivation

```
seed_at(base, index):
  h = base + index * 2654435761
  h = h ^ (h >> 13)
  h = h & 0x00FFFFFFFFFFFFFF
  h = h ^ (h << 7)
  h = h ^ (h >> 17)
  h = h & 0x7FFFFFFF
  return h

prop_seeds(count, base):
  out = []
  i = 0
  while i < count { out.push(seed_at(base, i)); i = i + 1 }
  return out
```

`count <= 0` yields an empty vector; otherwise the length is exactly `count`
and every element is in `[0, 2^31 - 1]`. Multiplication by the odd constant
before the mix spreads consecutive indices apart. Distinctness is **not**
guaranteed for arbitrary inputs (the suite checks a representative sample
only).

## 5. Generators

- `prop_rng_bool(r)`: `prop_rng_next(r) % 2 == 0`. One bit of the mixed
  stream.
- `prop_rng_range(r, lo, hi)`: when `hi < lo` returns `lo` and consumes **no**
  randomness. Otherwise `lo + (prop_rng_next(r) % (hi - lo + 1))`, i.e. an
  inclusive, modulo-uniform draw. Precondition: `hi - lo + 1` fits in `Int`
  (not checked).
- `prop_rng_string(r, len, alphabet)`: `len <= 0` or empty alphabet returns
  `""` without consuming randomness. Otherwise:
  1. the alphabet is scanned once at real UTF-8 boundaries into a char table
     (leading byte + sequence width; a truncated trailing sequence is copied
     as-is),
  2. the character count `k` is drawn with `prop_rng_range(r, 0, len)`,
  3. `k` characters are drawn with `prop_rng_range(r, 0, chars - 1)` and
     copied whole into a `Vec[UInt8]` accumulator,
  4. the accumulator is returned via `Str::from_utf8`.

  The result therefore has exactly `k` characters (`0 <= k <= len`) and only
  alphabet characters. Its **byte** length may exceed `k` for non-ASCII
  alphabets.

## 6. Reports and runners

`PropReport{ passed, failed, first_seed, first_value }`:

| Field | Green run | Red run |
|---|---|---|
| `passed` | number of seeds executed (`seeds.len()`) | seeds executed before the failing one |
| `failed` | `0` | `1` |
| `first_seed` | `0` | the failing seed |
| `first_value` | `0` | the failing draw (Str runners: the counterexample's **byte length**) |

Runner semantics (all three share one loop):

1. iterate the seed vector in order;
2. for seed `s`: `rng = prop_rng_new(s)`, draw the input (`[-1000, 1000]` for
   `prop_run_int`, `[lo, hi]` for `prop_run_range`, `prop_rng_string(rng,
   max_len, alphabet)` for `prop_run_str`);
3. call the predicate; on pass increment `passed`, on failure record the
   counterexample and stop immediately (no further seeds are executed);
4. return the report.

`prop_report_ok(r)` is `r.failed == 0`. Because every step is deterministic,
`prop_rng_new(first_seed)` plus the matching generator reproduces the exact
counterexample (the suite asserts this for the Int, range and Str runners).

## 7. Shrinking

```
prop_shrink_int(value, f):
  current = value
  if f(current) is false:
    loop:
      candidate = current / 2        // Int division, truncates toward zero
      if candidate == 0 { break }
      if f(candidate) is true { break }
      current = candidate
  return current
```

Guarantees:

1. If `f(value)` is true, `value` is returned unchanged.
2. Otherwise the result `r` is an element of the chain `value, value/2,
   value/4, ...` and `f(r)` is false (the result still fails).
3. Let `next = r / 2`. Either `next == 0` or `f(next)` is true: nothing
   further along the chain still fails, so `r` has the smallest magnitude in
   the chain for which the property fails.
4. Termination: each iteration halves the magnitude, so there are at most 63
   iterations before the candidate becomes 0.
5. Signs are preserved (truncating division moves toward 0); the magnitude is
   what shrinks.

## 8. API signatures

```xi
pub type Rng = { state: Int; }
pub type PropReport = { passed: Int; failed: Int; first_seed: Int; first_value: Int; }

pub fn prop_rng_new(seed: Int) -> Rng
pub fn prop_rng_next(r: &mut Rng) -> Int
pub fn prop_rng_bool(r: &mut Rng) -> Bool
pub fn prop_rng_range(r: &mut Rng, lo: Int, hi: Int) -> Int
pub fn prop_rng_string(r: &mut Rng, len: Int, alphabet: Str) -> Str
pub fn prop_seeds(count: Int, base: Int) -> Vec[Int]
pub fn prop_run_int(f: fn(&Int) -> Bool, seeds: &Vec[Int]) -> PropReport
pub fn prop_run_range(f: fn(&Int) -> Bool, seeds: &Vec[Int], lo: Int, hi: Int) -> PropReport
pub fn prop_run_str(f: fn(&Str) -> Bool, seeds: &Vec[Int], max_len: Int, alphabet: Str) -> PropReport
pub fn prop_report_ok(r: &PropReport) -> Bool
pub fn prop_shrink_int(value: Int, f: fn(&Int) -> Bool) -> Int
```

Complexity: generators are O(1) except `prop_rng_string` (O(|alphabet| +
result length)); `prop_seeds` is O(count); runners are O(seeds * cost of the
predicate); `prop_shrink_int` is O(log |value| * cost of the predicate).

## 9. Test plan

`tests/test_conformance.xi` (module `property_tests`) runs 26 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every callback is a named top-level function.
Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | same seed, five draws | determinism of the stream |
| t2 | different seeds differ | not a constant stream |
| t3 | bool both outcomes (20 draws) | usable bit, not stuck |
| t4 | range bounds, 200 draws + `[5,5]` | inclusive bounds, pinned point |
| t5 | `hi < lo` => `lo` | degenerate range + no draw consumed |
| t6 | `[0,3]` hits every value | inclusivity at both ends |
| t7 | `next` in `[0, 2^31-1]` from a negative seed | sign normalization, mask |
| t8 | string draws | byte length <= len, alphabet-only, non-empty seen |
| t9 | empty alphabet | `""` |
| t10 | `len <= 0` | `""` |
| t11 | seeds deterministic, counted, non-negative, distinct sample | seed derivation |
| t12 | always-true Int run | `passed == count`, `failed == 0` |
| t13 | green report sentinels | `first_seed == first_value == 0` |
| t14 | always-false Int run | fails seed[0], value in bounds, not ok |
| t15 | failing run stops early | `passed < count`, `first_seed == seeds[passed]` |
| t16 | bounded run + replay | green bounds; failing draw in `[lo,hi]` and replayable |
| t17 | always-true Str run | `passed == count` |
| t18 | failing Str run | replays length, alphabet-only, predicate fails |
| t19 | pinned `[0,0]` / `[1,1]` with `is_even` | deterministic verdicts |
| t20 | shrink `below_100` from 1,000,000 | exact 122, still failing, half passes |
| t21 | shrink with always-true predicate | input returned unchanged |
| t22 | shrink `not_700` from 700 | stops when the half passes |
| t23 | shrink `non_positive` from 1,000,000 | chain floor 1 (candidate 0 breaks) |
| t24 | shrink `beyond_neg_100` from -1,000,000 | exact -122, sign kept, half passes |
| t25 | `prop_report_ok` | true for green, false for red |
| t26 | bool draws reproducible | same seed => same bits |

## 10. Known limitations

- Deterministic test-grade PRNG; not cryptographic, no distribution proofs.
- `prop_seeds` distinctness is not guaranteed for arbitrary `(count, base)`.
- `prop_rng_range` does not detect `hi - lo + 1` overflow.
- `prop_rng_string` does not validate the alphabet's UTF-8; malformed input
  is copied conservatively.
- Str failures record a length, not the content; content is recovered by
  replaying the seed.
- Shrinking is limited to one Int and its halving chain; there is no
  vector-aware or integrated shrinking, and the predicate is called on chain
  values only.
- No runner for `Bool` or Float64 predicates; no parallel or timed execution.
- No integration with `xiom.test` (no discovery, no per-test reporting).

## 11. Compiler / stdlib notes

- Free functions only; no `self` methods (XIOM v0.61.x has none).
- Callbacks are NAMED top-level functions with concrete signatures; inline
  lambdas are rejected by the function-pointer codegen and were not used.
- `Vec[Int]` element reads are bound with an explicitly typed `let`
  (`let seed: Int = seeds[i];`) to avoid inference drift.
- String building uses a `Vec[UInt8]` accumulator plus `Str::from_utf8`
  (the proven `xiom.string` idiom); the source module never compares Str
  values with `==` (it only measures `.len()`), and the tests route string
  equality through `xiom.string.compare.str_compare` (BUG 17).
- `byte_at` results are compared against other `byte_at` results only; no
  comparison with UInt8 constants >= 128 occurs.
- Struct-returning functions build their report in locals and use a single
  `return PropReport{...}`; no `Ok`/`Err` constructors appear in them.
