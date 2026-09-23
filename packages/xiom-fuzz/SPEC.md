# xiom.fuzz -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.fuzz` (`src/fuzz.xi`). Pure XIOM, no FFI.

## 1. Scope

A deterministic, dependency-free mutation engine for byte buffers and strings:

- a seeded 31-bit PRNG (`FuzzRng`, `fuzz_rng_new`, `fuzz_next`),
- five single-step mutators (`fuzz_flip_byte`, `fuzz_flip_bit`,
  `fuzz_insert_byte`, `fuzz_delete_byte`, `fuzz_duplicate_range`),
- a multi-step driver that selects among them (`fuzz_mutate`),
- a byte-level Str wrapper (`fuzz_mutate_str`).

Every value is a pure function of `(data, seed, mutations)`; there is no
clock, environment, file or OS randomness source, so a run replays exactly.

## 2. Non-goals

- No fuzz loop, corpus storage, minimisation, queue or scheduler.
- No coverage instrumentation or feedback-driven input selection.
- No target execution, crash detection or timeouts.
- No grammar/structure-aware mutation (lengths, checksums, magic values).
- No UTF-8 validation or repair in the Str wrapper.
- No cryptographic or statistically validated randomness.
- No FFI, threading or time dependence.

## 3. PRNG definition

`Int` is a signed 64-bit two's-complement integer. The recipe mirrors the
proven `xiom.property` mixer; it is a test-grade scramble, not a validated
generator.

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

The `0x00FFFFFFFFFFFFFF` mask is what makes the recipe total: after it the
left shift cannot leave the non-negative domain for any input, including the
`Int` minimum. `mix` is pure and deterministic.

### 3.2 Construction and advance

```
fuzz_rng_new(seed):
  state = mix(seed)
  if state == 0 { state = 0x1F123BB5 }
  return FuzzRng{ state }      // state in [1, 2^31 - 1]

fuzz_next(r):
  h = r.state
  h = h ^ (h >> 13)
  h = h ^ (h << 7)             // state < 2^31, so this is < 2^38
  h = h ^ (h >> 17)
  h = h & 0x7FFFFFFF
  if h == 0 { h = 0x1F123BB5 } // zero fixed point is excluded, not entered
  r.state = h
  return h
```

### 3.3 Guarantees

1. `fuzz_next(r)` is always in `[0, 2^31 - 1]` and never 0, so the state stays
   in `[1, 2^31 - 1]` forever.
2. Same state => same draw, on every platform and every run.
3. Streams for the same seed are identical; different seeds are not required
   to differ at any specific position (the suite samples representative
   pairs).

## 4. Step-seed derivation

Used only by `fuzz_mutate` (single-step mutators seed a fresh generator
directly from their `seed` argument):

```
seed_at(base, index):
  return mix(base + index * 2654435761)   // odd golden-ratio multiplier

fuzz_mutate(data, seed, mutations):
  r = fuzz_rng_new(seed)
  step i: op = fuzz_next(r) % 5
          step_seed = seed_at(seed, i)
```

The odd multiplier spreads consecutive steps far apart; the same
`(seed, index)` pair always yields the same step seed. No overflow checking
is performed (`seed + i * 2654435761` is evaluated as a plain `Int`).

## 5. Single-step mutators

Each mutator builds a fresh `Vec[UInt8]` (the input is never aliased or
modified) and derives all choices from `r = fuzz_rng_new(seed)` in the order
below. `n = data.len()`. Draws are the public `fuzz_next`.

| Operation | Empty input | Derivation (draw order) | Effect |
|---|---|---|---|
| `fuzz_flip_byte` | empty | `pos = d0 % n`; `mask = (d1 % 255) + 1` | `out[pos] ^= mask`; mask >= 1, so the byte always changes |
| `fuzz_flip_bit` | empty | `pos = d0 % n`; `bit = d1 % 8` | `out[pos] ^= 1 << bit`; exactly one bit toggles |
| `fuzz_insert_byte` | length 1 | `pos = d0 % (n + 1)`; `value = d1 % 256` | inserts `value` before index `pos` (append when `pos == n`); length `n + 1` |
| `fuzz_delete_byte` | empty | `pos = d0 % n` | removes index `pos`; length `n - 1` |
| `fuzz_duplicate_range` | empty | `start = d0 % n`; `len = 1 + d1 % (n - start)`; `dest = d2 % (n + 1)` | inserts a copy of `data[start .. start + len)` before index `dest` (append when `dest == n`); `len >= 1`, so length `n + len` |

When the input is empty, `fuzz_flip_byte`, `fuzz_flip_bit`, `fuzz_delete_byte`
and `fuzz_duplicate_range` return an empty vector without consuming draws;
`fuzz_insert_byte` consumes two draws and returns a one-byte vector
(`pos = 0 % 1 = 0`).

Structural invariants for every non-empty input:

- flip ops: length unchanged, exactly one byte differs (flip_byte: exactly one
  byte, mask non-zero; flip_bit: exactly one bit).
- insert/delete: length changes by `+1` / `-1`; the original bytes keep their
  relative order.
- duplicate_range: length grows by `len >= 1`; the original bytes keep their
  relative order (the input is a subsequence of the output).

## 6. fuzz_mutate

```
fuzz_mutate(data, seed, mutations):
  out = copy of data
  if mutations <= 0 { return out }         // unchanged
  r = fuzz_rng_new(seed)
  i = 0
  while i < mutations:
    op = fuzz_next(r) % 5                  // advances once per step
    ss = seed_at(seed, i)
    op 0 -> out = fuzz_flip_byte(out, ss)
    op 1 -> out = fuzz_flip_bit(out, ss)
    op 2 -> out = fuzz_insert_byte(out, ss)
    op 3 -> out = fuzz_delete_byte(out, ss)
    op 4 -> out = fuzz_duplicate_range(out, ss)
    i = i + 1
  return out
```

Op selection is `% 5` over the advancing stream, so the sequence of
operations is itself deterministic and pinned. Per-step seeds are derived from
`seed + i` as in section 4, independent of the op stream. Consequences:

- `mutations <= 0` returns an exact copy.
- One step with a non-empty input always changes the vector (every op
  changes at least one byte or the length).
- Length is not monotone across steps: flip ops preserve it, insert grows by
  1, delete shrinks by 1, duplicate grows by `len >= 1`.

## 7. fuzz_mutate_str

```
fuzz_mutate_str(s, seed, mutations):
  bytes = UTF-8 bytes of s (byte_at scan)
  mutated = fuzz_mutate(bytes, seed, mutations)
  return builder.sb_to_str(mutated)
```

The transformation is byte-level: the bytes are mutated exactly as in
`fuzz_mutate` and materialized back into a `Str` with the `xiom.string`
builder (`sb_to_str`). No UTF-8 validation, normalization or repair is
performed, so the result may contain invalid UTF-8 (a flipped lead or
continuation byte can break a sequence). For ASCII input the round-trip is
exact byte-for-byte, and `mutations <= 0` returns the input unchanged.

## 8. API signatures

```xi
pub type FuzzRng = { state: Int; }

pub fn fuzz_rng_new(seed: Int) -> FuzzRng
pub fn fuzz_next(r: &mut FuzzRng) -> Int
pub fn fuzz_flip_byte(data: &Vec[UInt8], seed: Int) -> Vec[UInt8]
pub fn fuzz_flip_bit(data: &Vec[UInt8], seed: Int) -> Vec[UInt8]
pub fn fuzz_insert_byte(data: &Vec[UInt8], seed: Int) -> Vec[UInt8]
pub fn fuzz_delete_byte(data: &Vec[UInt8], seed: Int) -> Vec[UInt8]
pub fn fuzz_duplicate_range(data: &Vec[UInt8], seed: Int) -> Vec[UInt8]
pub fn fuzz_mutate(data: &Vec[UInt8], seed: Int, mutations: Int) -> Vec[UInt8]
pub fn fuzz_mutate_str(s: Str, seed: Int, mutations: Int) -> Str
```

Complexity: `fuzz_next` is O(1); every single-step mutator is O(n);
`fuzz_mutate` is O(mutations * n) (worst case, due to repeated copies);
`fuzz_mutate_str` is O(|s| + mutations * |s|).

## 9. Test plan

`tests/test_conformance.xi` (module `fuzz_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). The suite replicates the section 3.1 mixer as `test_mix`
and section 4 derivation as `step_seed` to predict `fuzz_mutate`'s exact
choreography. Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | same seed, eight draws | stream determinism |
| t2 | different seeds differ | not a constant stream |
| t3 | 300 draws from a negative seed | `[0, 2^31 - 1]` bounds |
| t4 | draw stream not constant | state advances |
| t5 | flip_byte on "abcd" | same length, exactly one byte differs |
| t6 | flip_byte twice with seed 99 | determinism; never a no-op |
| t7 | flip ops on empty | stay empty |
| t8 | flip_bit | same length; one byte differs; popcount(delta) == 1 |
| t9 | flip_bit twice with seed 21 | determinism; never a no-op |
| t10 | insert_byte on "xyz" | length +1; removing one position recovers the input |
| t11 | insert_byte twice + empty | determinism; empty grows to 1 |
| t12 | delete_byte on "abcdef" | length -1; deleting one original position recovers the result |
| t13 | delete_byte twice + empty | determinism; empty stays empty |
| t14 | duplicate_range on "keep me" | grows; input is a subsequence; determinism |
| t15 | duplicate_range + 0-step mutate on empty | stay empty |
| t16 | mutate at 0 and -4 steps | unchanged copy |
| t17 | mutate twice with seed 2026 + five other seeds | determinism; seed sensitivity |
| t18 | replay simulation over 12 steps | exact op selection and step-seed derivation |
| t19 | one-step mutate over 12 seeds | always changes; both growth and shrink occur |
| t20 | str mutation | determinism; seed sensitivity; 0 steps = identity |
| t21 | ASCII "hello fuzz", 12 steps | mutated Str equals mutated bytes byte-for-byte |
| t22 | empty inputs for all ops | no-op ops stay empty; insert grows to 1; mutate deterministic |

## 10. Known limitations

- Test-grade 31-bit scramble; not cryptographic, no distribution proofs.
- No corpus, scheduler, coverage feedback, target execution or crash
  detection: `xiom.fuzz` transforms bytes and stops there.
- `fuzz_mutate` grows the buffer on average (two of five ops grow, one
  shrinks, two preserve); long chains need caller-side re-seeding or caps.
- `fuzz_mutate_str` can return invalid UTF-8 and does not report it.
- No overflow checking in `seed_at`; `seed + i * 2654435761` wraps like any
  `Int` arithmetic.
- Empty-input draw behavior is defined per table in section 5 but not
  "balanced": short inputs get short mutation chains.

## 11. Compiler / stdlib notes

- Free functions only; no `self` methods (XIOM v0.61.x has none).
- No `Result` channels: every mutator returns its value directly, so
  `Ok`/`Err` construction bugs cannot arise.
- `Vec[UInt8]` element reads are cast to `Int` before any masking,
  comparison or shift (`(out[pos] as Int) ^ mask`); no `byte_at` result is
  ever compared directly against a `UInt8` constant >= 128.
- Str output is built with `xiom.string.builder.sb_to_str` over a
  `Vec[UInt8]` accumulator (the proven `xiom.string` idiom); the module only
  measures `.len()` on Str values and never compares them with `==`.
- Self-reassignment through a `&` borrow (`out = fuzz_flip_byte(&out, s)`) is
  the stdlib-proven pattern for immutable-input transforms.
