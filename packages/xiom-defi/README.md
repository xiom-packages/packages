# xiom.defi

> **Status:** `incubating` -- conformance-tested (28/28); published at `v0.1.0` on the XIOM registry.
> **Scope:** integer fixed-point DeFi pool models: a constant-product AMM
> (x*y=k) with fees, slippage guards and LP shares, and a share-index lending
> pool with per-tick accrual, health factor and liquidation math.
> **Deps:** `xiom.std` only (`deps` declares the platform dependency; the
> library module imports `xiom.core` for `INT_MAX`). Pure XIOM, no FFI.

## What it is

`xiom.defi` is a small, deterministic toolkit for decentralised-finance pool
arithmetic. Every value is an integer: there is no floating point, no
randomness and no clock. All fractions cross the API at the fixed-point scale
1e-4 (`DEFI_SCALE = 10000` parts per 1.0), so one basis point is exactly one
scale unit: fees, per-tick rates, liquidation thresholds, close factors and
bonuses are all parts per 10000, and an index of 10000 means 1.0.

The module exposes two models:

- **Constant-product AMM** (`AmmPool`): reserve-based x*y=k quotes with a
  fee in basis points, exact amount-in/amount-out helpers, a slippage-guarded
  swap, LP share mint/burn and the k-growth invariant check.
- **Share-index lending pool** (`LendPool`): supply and borrow shares priced
  by monotone indexes, per-tick interest accrual with a reserve factor,
  collateral ratio, health factor and close-factor/bonus liquidation math.

**Rounding.** Every division in the module uses the native `Int` operator,
which truncates toward zero. For the non-negative magnitudes used here that
is a floor: swap outputs, share credits, index increments, repayments and
liquidation repayments round in the pool's favor. The only ceiling divisions
are the amount-in quote for a desired output and the seizure amount including
the liquidation bonus. No other rounding mode is offered.

**Overflow.** Every product goes through `_defi_mul_sat` and every sum
through `_defi_add_sat`; both saturate at `core.INT_MAX` instead of wrapping,
so extreme inputs stay deterministic. The guards are pinned by tests.

## API

### Constant-product AMM

| Function | Returns | Description |
|---|---|---|
| `amm_new(reserve_a, reserve_b, fee_bps)` | `AmmPool` | Seed a pool; negative reserves clamp to 0, fee clamps to [0, 10000], initial LP shares are `floor(sqrt(reserve_a * reserve_b))` (1 when that truncates to 0). |
| `amm_fee_amount(amount_in, fee_bps)` | `Int` | `floor(amount_in * fee_bps / 10000)`; 0 for non-positive amounts. |
| `amm_get_amount_out(reserve_in, reserve_out, amount_in, fee_bps)` | `Int` | `in_with_fee = amount_in - fee`, then `out = floor(in_with_fee * reserve_out / (reserve_in + in_with_fee))`, capped at `reserve_out`. 0 for non-positive inputs/reserves or a 100% fee. |
| `amm_get_amount_in(reserve_in, reserve_out, amount_out, fee_bps)` | `Int` | Inverse quote with two ceiling divisions so the input is always sufficient; 0 when `amount_out >= reserve_out` or the fee is 100%. |
| `amm_spot_price_bps(reserve_a, reserve_b)` | `Int` | `floor(reserve_b * 10000 / reserve_a)`: B per A in parts per 10000. |
| `amm_swap(p, amount_in, min_out, a_to_b)` | `Result[Int, Str]` | Quote, guard (`min_out`), then move reserves; `a_to_b` selects direction. Rejections leave the pool unchanged. |
| `amm_mint(p, amount_a, amount_b)` | `Int` | Mint `min(floor(amount_a * lp_total / reserve_a), floor(amount_b * lp_total / reserve_b))` shares and deposit both amounts; geometric mean for a share-less pool. |
| `amm_burn(p, shares)` | `(Int, Int)` | Withdraw `floor(shares * reserve / lp_total)` of both tokens. |
| `amm_k(p)` | `Int` | Current `reserve_a * reserve_b` (saturating). |
| `amm_k_check(ra0, rb0, ra1, rb1)` | `Bool` | True when `k` did not shrink between two snapshots. |

### Share-index lending pool

| Function | Returns | Description |
|---|---|---|
| `lend_new(reserve_bps)` | `LendPool` | Empty pool, both indexes at 1.0 (10000), reserve factor clamped to [0, 10000]. |
| `lend_total_supply(p)` | `Int` | `floor(supply_shares * supply_index / 10000)`. |
| `lend_total_borrow(p)` | `Int` | `floor(borrow_shares * borrow_index / 10000)`. |
| `lend_supply_balance(p, shares)` | `Int` | Value of `shares` supply shares at the current index. |
| `lend_borrow_balance(p, shares)` | `Int` | Debt of `shares` borrow shares at the current index. |
| `lend_supply(p, amount)` | `Int` | Mint `floor(amount * 10000 / supply_index)` shares. |
| `lend_withdraw(p, shares)` | `Int` | Burn shares for `floor(shares * supply_index / 10000)` units, capped by available liquidity (`total_supply - total_borrow`). |
| `lend_borrow(p, amount)` | `Int` | Mint `floor(amount * 10000 / borrow_index)` shares, capped by available liquidity. |
| `lend_repay(p, shares)` | `Int` | Burn borrow shares for `floor(shares * borrow_index / 10000)` units. |
| `lend_accrue(p, rate_bps, ticks)` | `Int` | Compound the borrow index `ticks` times at `rate_bps` per tick; suppliers receive the interest net of `reserve_bps`. Returns total interest credited to suppliers. |
| `lend_collateral_ratio_bps(collateral, debt)` | `Int` | `floor(collateral * 10000 / debt)`; `INT_MAX` when debt is 0, 0 when collateral is 0. |
| `lend_health_factor_bps(collateral, debt, threshold_bps)` | `Int` | `floor(collateral * threshold_bps / debt)`; liquidatable below 10000. |
| `lend_is_liquidatable(health_factor_bps)` | `Bool` | `health_factor_bps < 10000`. |
| `lend_liquidation_amounts(debt, collateral, close_factor_bps, bonus_bps)` | `(Int, Int)` | `repay = floor(debt * close_factor / 10000)`, `seize = ceil(repay * (10000 + bonus) / 10000)` capped at collateral. |
| `lend_check_indexes(p, supply_index_before, borrow_index_before)` | `Bool` | True when both indexes are at least their recorded values. |

## Usage

```xi
use xiom.defi;

// AMM: 100000/100000 pool, 30 bps fee.
var pool = amm_new(100000, 100000, 30);
let quote = amm_get_amount_out(100000, 100000, 10000, 30);  // 9066
match amm_swap(&mut pool, 10000, 9000, true) {
  Ok(out)  => { /* out == 9066, reserves are now 110000 / 90934 */ },
  Err(msg) => { /* min_out not met or invalid input; pool unchanged */ },
}

// Lending: 100000 supplied, 50000 borrowed, 10% reserve factor.
var market = lend_new(1000);
let supplied_shares = lend_supply(&mut market, 100000);   // 100000 shares
let borrowed_shares = lend_borrow(&mut market, 50000);    // 50000 shares
let credited = lend_accrue(&mut market, 100, 2);          // 905 units to suppliers

let healthy = lend_health_factor_bps(150000, 100000, 8000); // 12000 (healthy)
let (repay, seize) = lend_liquidation_amounts(100002, 150000, 5000, 800);
// repay == 50001, seize == 54002
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.defi
```

Expected: the namespaced module passes the section-4 namespace rule, 28
`[PASS]` lines, and a final
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integers only.** There is no floating-point path; fractional base units
  are dropped at every truncation point and rates coarser than 1 basis point
  cannot be expressed directly.
- **Truncation compounds.** The borrow index truncates once per tick and the
  supplier per-share increment floors once per tick, so repeated accrual sits
  at or below the exact rational value for positive rates. The deviation is
  pinned by tests, not hidden.
- **Documented donations.** An unbalanced `amm_mint` credits the smaller
  proportional share count while depositing both full amounts; the imbalance
  stays in the pool for existing LPs.
- **Saturating, not erroring.** Products and sums that would exceed `Int`
  saturate at `core.INT_MAX`; extreme inputs are deterministic but no
  overflow error is reported.
- **No oracle, prices or decimals.** Collateral, debt and reserves are plain
  integers in caller-chosen units; there is no price feed, token registry or
  decimal scaling.
- **No interest-rate model or bad-debt handling.** `lend_accrue` takes the
  per-tick rate as an argument; there is no utilisation curve, and a
  liquidation that cannot cover the debt is simply capped at the posted
  collateral.
- **Not audited and not financial advice.** Deterministic integer arithmetic
  for simulation and testing, not a production protocol.
- **Single-threaded.** No locks, atomics or async variants; callers serialize
  access.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
