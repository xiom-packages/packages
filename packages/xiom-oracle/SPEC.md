# xiom.oracle -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.oracle` (`src/oracle.xi`). Pure XIOM, no FFI, no clock.

## 1. Scope

A deterministic model for one oracle aggregation round:

- `oracle_round_new` validates the configuration (feed, quorum size, maximum
  age, deviation band);
- `oracle_observe` records one observation per source (price, tick, weight);
- accessors expose the configuration and the observations;
- `oracle_quorum_met`, `oracle_latest_tick`, `oracle_age_ticks` and
  `oracle_is_stale` answer quorum and freshness questions;
- `oracle_median`, `oracle_weighted_median` and `oracle_deviation_rejects`
  compute the aggregates and the outlier set;
- `oracle_aggregate` runs the full consumer pipeline;
- `oracle_reset` clears the round for reuse.

All arithmetic is integer fixed-point at scale 1e-4 (`ORACLE_SCALE = 10000`),
matching `xiom.defi` and `xiom.chaincore`.

## 2. Non-goals

- **No cryptography**: attestation signing, key management and signature
  verification are not modelled (see `xiom.chaincrypto` for such primitives).
- **No time source**: `ticks` are caller-supplied logical counters, not wall
  time; the package never reads a clock.
- **No randomness**: every function is a pure function of the state.
- **No transport or persistence**: no network, storage, serialization or
  feed ingestion loop.
- **No replay or slashing logic**: only the aggregation math and state.
- No FFI, no file I/O, no registry integration.

## 3. Data model

```xi
pub type OracleRound = {
  feed: Str;
  min_sources: Int;
  max_age_ticks: Int;
  max_deviation_bps: Int;
  sources: Vec[Str];
  prices: Vec[Int];
  ticks: Vec[Int];
  weights: Vec[Int];
}
```

The four observation vectors are index-aligned in arrival order; every
accessor operates on their shortest length, so a hand-built round cannot be
read out of range. `prices` are fixed-point magnitudes (1.0 = 10000), `ticks`
are logical times, `weights` are voting weights.

## 4. Rules

1. **Configuration.** `feed` must be non-empty; `min_sources >= 1`;
   `max_age_ticks >= 0`; `0 <= max_deviation_bps <= 10000` (basis points,
   where 10000 = 100%).
2. **Observation validation.** `source` must be non-empty and unique within
   the round (case-sensitive exact match); `1 <= price <= 1000000000000`;
   `tick >= 0`; `1 <= weight <= 1000000`. A failed call never mutates.
3. **Quorum.** `count >= min_sources`.
4. **Age.** `age = now_tick - latest_tick`; `-1` when there are no
   observations. A `now_tick` below the newest tick yields a negative age.
5. **Staleness.** An empty round is stale. Otherwise stale iff
   `age > max_age_ticks` (the boundary age equals the maximum is fresh;
   future-dated observations are fresh).
6. **Plain median.** Sort the prices; an odd count returns the middle price,
   an even count the floored average of the two middle prices.
7. **Weighted median.** Sort (price, weight) pairs by ascending price;
   accumulate total weight (guard: total `<= 1000000000000`, else
   `weight overflow`); return the price at the first position whose
   cumulative weight satisfies `2 * cumulative >= total`. Ties therefore
   resolve to the lowest price whose cumulative weight reaches half.
8. **Deviation.** For each observation,
   `bps = floor(|price - weighted_median| * 10000 / median)`; it is rejected
   when `bps > max_deviation_bps` (equality is accepted). The median is the
   weighted median of the whole round.
9. **Aggregate pipeline order.**
   `no observations` -> `quorum not met` -> `stale feed` -> weighted median
   -> deviation filter -> if the survivors number fewer than `min_sources`,
   `quorum lost after deviation filter` -> weighted median of the survivors.
10. **Determinism.** The same sequence of calls always produces the same
    results; the rounding rule is floor for every division.

## 5. Error catalog

All messages are prefixed `oracle: `.

| Condition | Exact message |
|---|---|
| Empty feed | `empty feed` |
| `min_sources < 1` | `bad min sources <n>` |
| `max_age_ticks < 0` | `bad max age <n>` |
| deviation outside 0..10000 | `bad deviation <n>` |
| Empty source | `empty source` |
| Source already observed | `duplicate source '<s>'` |
| price outside 1..1000000000000 | `bad price <p>` |
| tick < 0 | `bad tick <t>` |
| weight outside 1..1000000 | `bad weight <w>` |
| Median/filter/aggregate on an empty round | `no observations` |
| Aggregate below quorum | `quorum not met` |
| Newest observation older than the maximum | `stale feed` |
| Fewer survivors than `min_sources` | `quorum lost after deviation filter` |
| Total weight above 1000000000000 | `weight overflow` |

## 6. API contract

```xi
pub fn oracle_round_new(feed: Str, min_sources: Int, max_age_ticks: Int, max_deviation_bps: Int) -> Result[OracleRound, Str]
pub fn oracle_observe(r: &mut OracleRound, source: Str, price: Int, tick: Int, weight: Int) -> Result[Int, Str]
pub fn oracle_feed(r: &OracleRound) -> Str
pub fn oracle_min_sources(r: &OracleRound) -> Int
pub fn oracle_max_age_ticks(r: &OracleRound) -> Int
pub fn oracle_max_deviation_bps(r: &OracleRound) -> Int
pub fn oracle_observation_count(r: &OracleRound) -> Int
pub fn oracle_source(r: &OracleRound, i: Int) -> Str
pub fn oracle_price(r: &OracleRound, i: Int) -> Int
pub fn oracle_tick(r: &OracleRound, i: Int) -> Int
pub fn oracle_weight(r: &OracleRound, i: Int) -> Int
pub fn oracle_quorum_met(r: &OracleRound) -> Bool
pub fn oracle_latest_tick(r: &OracleRound) -> Int
pub fn oracle_age_ticks(r: &OracleRound, now_tick: Int) -> Int
pub fn oracle_is_stale(r: &OracleRound, now_tick: Int) -> Bool
pub fn oracle_median(r: &OracleRound) -> Result[Int, Str]
pub fn oracle_weighted_median(r: &OracleRound) -> Result[Int, Str]
pub fn oracle_deviation_rejects(r: &OracleRound) -> Result[Int, Str]
pub fn oracle_aggregate(r: &OracleRound, now_tick: Int) -> Result[Int, Str]
pub fn oracle_reset(r: &mut OracleRound)
```

Out-of-range accessors: `oracle_source` -> `""`, the numeric ones -> `-1`.
Complexity: construction and accessors are O(1); latest/age/staleness are
O(n); medians and the pipeline are O(n^2) because of the insertion sort.

## 7. Test matrix

`tests/test_conformance.xi` (module `oracle_tests`) runs 22 named checks
through `assert(cond, "name")` and returns the failure count from `main`.
All expected values are hand-computed integers.

| # | Check | Rules pinned |
|---|---|---|
| t1 | round construction | rule 1 |
| t2 | configuration errors | rule 1, section 5 |
| t3 | observation recording | rule 2 |
| t4 | observation errors and non-mutation | rule 2 |
| t5 | quorum boundary | rule 3 |
| t6 | freshness boundary | rules 4, 5 |
| t7 | odd weighted median | rule 7 |
| t8 | even count tie + floored plain median | rules 6, 7 |
| t9 | weights vs plain median | rules 6, 7 |
| t10 | weight overflow + empty errors | rule 7, section 5 |
| t11 | single and two-price medians | rule 6 |
| t12 | deviation rejects | rule 8 |
| t13 | deviation boundary accepted | rule 8 |
| t14 | full pipeline + stale boundary | rules 9, 5 |
| t15 | aggregate quorum/empty errors | rule 9 |
| t16 | quorum lost after filtering | rule 9 |
| t17 | filtered weighted median | rules 7, 9 |
| t18 | newest-tick age | rules 4, 5 |
| t19 | case-sensitive sources, inclusive limits | rule 2 |
| t20 | reset keeps configuration | rule 10 |
| t21 | accessor bounds | section 6 |
| t22 | observe count semantics | rule 2 |

## 8. Known limitations

- One observation per source per round; no updates or weighted duplicates.
- O(n^2) sorting; intended for oracle round sizes (tens of sources).
- Fixed integer ranges documented above; larger values are rejected rather
  than clamped.
- No cryptography, time, randomness, transport or persistence.
- A hand-built round with mismatched arrays is clamped, not repaired.

## 9. Compiler / stdlib notes (v0.62.2)

Free functions only; flat parallel Vecs instead of `Vec[StructType]`;
`Result` construction confined to leaf helpers; every element read bound to a
typed local; `&mut Vec` arguments passed with an explicit `&mut` (the
v0.61.3 write-through rule). Sorting swaps through indexed element writes,
the pattern proven in `xiom.ini`. The suite is green on v0.62.2 with
`program_exit=0`.
