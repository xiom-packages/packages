# xiom.oracle

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.0` on the XIOM registry.
> **Scope:** deterministic multi-source oracle feed aggregation: quorum,
> freshness, weighted median, deviation filter and the full aggregate
> pipeline, in integer fixed-point arithmetic.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.compare` and
> `xiom.convert`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.oracle` models an off-chain data-oracle round over a blockchain feed: a
round collects one observation per oracle source, and consumers ask whether
there is a quorum, whether the feed is still fresh, what price to aggregate,
and which observations are outliers. Everything is integer arithmetic at the
fixed-point scale 1e-4 (`10000` parts per 1.0), matching the sibling
chain-family packages (`xiom.defi`, `xiom.chaincore`); time is a logical tick
counter supplied by the caller, never wall time.

- **Observations** -- `oracle_observe` records source, fixed-point price,
  tick and voting weight; sources are unique and case-sensitive within a
  round, and every field is range-checked without mutating on failure.
- **Quorum and freshness** -- `oracle_quorum_met`, `oracle_latest_tick`,
  `oracle_age_ticks`, `oracle_is_stale`; a future-dated observation is not
  stale, and a feed with no observations is.
- **Aggregation** -- `oracle_median` (plain), `oracle_weighted_median`
  (cumulative-weight rule), `oracle_deviation_rejects` (basis-point
  outliers) and `oracle_aggregate`, the full pipeline: quorum, freshness,
  weighted median, deviation filter, second weighted median over the
  survivors (which must still form a quorum).

Attestation signing is an explicit non-goal: no key material and no
cryptography live here.

## API

| Function | Returns | Description |
|---|---|---|
| `oracle_round_new(feed, min_sources, max_age_ticks, max_deviation_bps)` | `Result[OracleRound, Str]` | Validated round configuration. |
| `oracle_observe(r, source, price, tick, weight)` | `Result[Int, Str]` | Record one observation; `Ok(count)`. |
| `oracle_feed(r)` / `oracle_min_sources(r)` / `oracle_max_age_ticks(r)` / `oracle_max_deviation_bps(r)` | `Str` / `Int` | Round configuration. |
| `oracle_observation_count(r)` | `Int` | Observations collected. |
| `oracle_source(r, i)` / `oracle_price(r, i)` / `oracle_tick(r, i)` / `oracle_weight(r, i)` | `Str` / `Int` | Positional observation fields; `""` / `-1` out of range. |
| `oracle_quorum_met(r)` | `Bool` | `count >= min_sources`. |
| `oracle_latest_tick(r)` | `Int` | Newest observation tick; `-1` when empty. |
| `oracle_age_ticks(r, now_tick)` | `Int` | `now - latest`; `-1` when empty. |
| `oracle_is_stale(r, now_tick)` | `Bool` | Empty, or age beyond `max_age_ticks`. |
| `oracle_median(r)` | `Result[Int, Str]` | Plain median (floored even average). |
| `oracle_weighted_median(r)` | `Result[Int, Str]` | Cumulative-weight median. |
| `oracle_deviation_rejects(r)` | `Result[Int, Str]` | Outlier count beyond `max_deviation_bps`. |
| `oracle_aggregate(r, now_tick)` | `Result[Int, Str]` | Full pipeline. |
| `oracle_reset(r)` | nothing | Clear observations, keep configuration. |

## Usage

```xi
use xiom.oracle;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  let rr = oracle_round_new("ETH/USD", 2, 10, 500);   // 2 sources, 5% band
  match rr {
    Ok(r) => {
      var round = r;
      oracle_observe(&mut round, "binance", 100, 0, 1);
      oracle_observe(&mut round, "coinbase", 104, 0, 3);
      oracle_observe(&mut round, "sketchy", 500, 0, 1);

      if oracle_quorum_met(&round) { io.println("quorum ok"); }
      let wm = oracle_weighted_median(&round);
      match wm {
        Ok(v) => { io.println("weighted median " + int_to_string(v)); },  // 104
        Err(e) => { io.println(e); },
      }
      let fails = oracle_deviation_rejects(&round);
      match fails {
        Ok(n) => { io.println("outliers " + int_to_string(n)); },         // 1
        Err(e) => { io.println(e); },
      }
      let agg = oracle_aggregate(&round, 5);
      match agg {
        Ok(v) => { io.println("aggregate " + int_to_string(v)); },        // 104
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.oracle
```

Expected tail: 22 `[PASS]` lines, `xiom.oracle: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- One observation per source per round (case-sensitive ids); re-feeding a
  source requires `oracle_reset` or a new round.
- Median and filtering use an O(n^2) insertion sort -- fine for oracle
  round sizes, not for bulk statistics.
- Rounding is floor everywhere; weighted medians resolve ties to the lowest
  price whose cumulative weight reaches half of the total.
- Prices are bounded to `1..1000000000000` and weights to `1..1000000`
  (total weight `<= 1000000000000`) so every intermediate stays in range.
- Attestation signing, replay protection, storage and transport are
  non-goals: this package is the math and state model only.
- A round is a plain value: single-threaded, no persistence, no FFI.

See `SPEC.md` for the exact rules, error catalog and test matrix. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
