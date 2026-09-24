# xiom.selection

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** deterministic selection operators for evolutionary loops:
> roulette-wheel, tournament, elite and linear-rank selection over Int vectors.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (platform dependency). The library
> module imports nothing, not even the stdlib; the tests use `xiom.test`,
> `xiom.io` and `xiom.core` from it.

## Scope

`xiom.selection` picks individuals out of a population: by fitness-proportional
roulette, by k-way tournament, by preserving the elite, or by linear rank
weights. Every operator is a pure function of its inputs -- weights/fitness
plus, where randomness is needed, an explicit `Int` seed -- so a run replays
exactly. There is no clock, environment or OS randomness anywhere in the
module. Negative weights count as 0 in every operator, and ties always resolve
toward the earlier (smaller) index.

## API

| Function | Returns | Description |
|---|---|---|
| `sel_sum(weights)` | `Int` | Sum of the usable weights (`max(w, 0)` each); 0 for empty/all-negative. |
| `sel_roulette_index(weights, draw)` | `Int` | Deterministic core: bucket of an explicit draw in `[0, total)`; `-1` when the draw is out of range or the total is 0. |
| `sel_roulette(weights, seed)` | `Int` | Seeded roulette: draws `rng_next(seed_state(seed)) % total` and resolves it; `-1` when the total is 0. |
| `sel_tournament_index(fitness, k, seed)` | `Int` | k contenders sampled with the PRNG (k clamped to `[1, len]`); highest fitness wins, ties keep the earliest sampled index; `-1` when empty. |
| `sel_elite_indices(fitness, k)` | `Vec[Int]` | Top-k indices by (fitness desc, index asc) via stable insertion sort; k clamped to `len`; empty for `k <= 0`. |
| `sel_best_index(fitness)` | `Int` | First index attaining the maximum fitness; `-1` when empty. |
| `sel_worst_index(fitness)` | `Int` | First index attaining the minimum fitness; `-1` when empty. |
| `sel_rank_weights(n)` | `Vec[Int]` | Linear ranks `[n, n-1, ..., 1]`; empty for `n < 1`. |

## Determinism and the PRNG

All randomness comes from one documented 31-bit xorshift-style mixer over an
`Int` state (no floating point, no library RNG):

```
mix(v):                              seed_state(seed):          rng_next(state):
  h = v                                s = mix(seed)              h = state
  h = h ^ (h >> 13)                    if s == 0 {                h = h ^ (h >> 13)
  h = h & 0x00FFFFFFFFFFFFFF             s = 0x1F123BB5 }         h = h ^ (h << 7)
  h = h ^ (h << 7)                     return s                   h = h ^ (h >> 17)
  h = h ^ (h >> 17)                                               h = h & 0x7FFFFFFF
  h = h & 0x7FFFFFFF                                              if h == 0 {
return h                                                            h = 0x1F123BB5 }
                                                                  return h
```

The state is always in `[1, 2^31 - 1]` (zero is replaced by the fixed nonzero
constant `0x1F123BB5`), so a stream can never collapse and every draw is
non-negative for every seed, including negative ones.

**Draw convention.** `sel_roulette` consumes exactly one draw:
`draw = rng_next(seed_state(seed)) % sel_sum(weights)`. `sel_tournament_index`
consumes exactly `clamp(k, 1, len)` draws: contender `c` is
`rng_next^(c+1)(seed_state(seed)) % len` (each contender one draw of the
stream, with replacement). Same seed plus same vector always selects the same
index on every platform and every run.

## Usage

```xi
use xiom.selection;

fn main() -> Int {
  var weights = Vec[Int].new();
  weights.push(50); weights.push(30); weights.push(20);
  var fitness = Vec[Int].new();
  fitness.push(12); fitness.push(40); fitness.push(27);

  let parent = sel_roulette(&weights, 20260924);
  let rival = sel_tournament_index(&fitness, 3, 20260924);
  let elite = sel_elite_indices(&fitness, 2);
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.selection
```

Expected tail: 25 `[PASS]` lines, `xiom.selection: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Linear scans.** `sel_sum`, `sel_roulette_index`, `sel_roulette`,
  `sel_best_index` and `sel_worst_index` are O(n); `sel_elite_indices` is a
  stable insertion sort, O(n^2) worst case (near-sorted inputs are O(n)); a
  tournament is O(k + n). No indexed/heap shortcuts are used.
- **Deterministic, not cryptographic.** The 31-bit mixer is meant for
  reproducible evolutionary loops, not for secrets, simulation or adversarial
  settings; it has no statistical validation.
- **Int weights/fitness only.** No Float64 vectors (the compiler v0.61.3
  rejects `Vec[Float64]`), no `Vec[StructType]`, no generics.
- **Modulo reduction is slightly biased when the total is not a power of two**
  (the standard `% total` caveat); `sel_roulette_index` itself is exact.
- **Documented preconditions, not errors:** the weight sum must fit in an
  `Int`, and `sel_roulette_index` expects the draw in `[0, total)` -- though an
  out-of-range draw returns `-1` instead of trapping.
- **Tie rules are fixed:** ties keep the earlier index everywhere (elite and
  tournament both resolve to the smallest qualifying index).

See `SPEC.md` for the pinned algorithms, tie rules and the full test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
