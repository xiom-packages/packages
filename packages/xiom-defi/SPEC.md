# xiom.defi SPEC

## Package Overview

`xiom.defi` is a pure-XIOM, FFI-free toolkit of deterministic DeFi pool
models: a constant-product automated market maker (x*y=k) and a share-index
lending pool. One module: `xiom.defi` (`src/defi.xi`). All arithmetic is
integer; the only import is `xiom.core` (for `INT_MAX` in the saturation
guards and the no-debt health sentinel).

**Fixed-point scale.** `DEFI_SCALE = 10000` parts per 1.0 (scale 1e-4), so
one basis point is exactly one scale unit. Fee rates (`fee_bps`), per-tick
interest (`rate_bps`), liquidation thresholds, close factors and bonuses all
cross the API in parts per 10000 and are clamped to `[0, 10000]`. Indexes and
prices are parts per 10000 as well: index `10000` = 1.0, price `15000` = 1.5.

## Scope

- Constant-product quotes, fees and slippage-guarded swaps (`AmmPool`).
- LP share mint/burn with proportional accounting and a round-trip guarantee.
- Invariant checks: k never shrinks; lending indexes never decrease.
- Share-index lending: supply/withdraw, borrow/repay, per-tick accrual with a
  reserve factor.
- Collateral ratio, health factor and close-factor/bonus liquidation math.

## Non-Goals

- No floating point anywhere (no `Float64`, no `Vec[Float64]`).
- No oracle, price feed, token registry, decimals or price impact curve; the
  AMM price is strictly the reserve ratio.
- No interest-rate model (utilisation curve), no bad-debt socialisation, no
  flash loans, no governance or access control.
- No `Vec[StructType]`, no lambdas, no fn tables, no methods/`self`; the API
  is free functions over two plain structs.
- Not audited and not financial advice; results are exact integer arithmetic
  for deterministic simulation and testing.

## Data Model

```
pub type AmmPool = {
  reserve_a: Int;   // token A base units
  reserve_b: Int;   // token B base units
  lp_total: Int;    // outstanding LP shares
  fee_bps: Int;     // swap fee, parts per 10000, [0, 10000]
}

pub type LendPool = {
  supply_shares: Int;  // supply share count
  borrow_shares: Int;  // borrow share count
  supply_index: Int;   // parts per 10000; 1.0 = 10000; monotone
  borrow_index: Int;   // parts per 10000; 1.0 = 10000; monotone
  reserve_bps: Int;    // interest reserve factor, [0, 10000]
}
```

Live amounts are always `shares * index / 10000` (floor). Reserves, amounts,
debt and collateral are plain integers in caller-chosen units; the module
performs no decimal scaling.

## Constants

| Name | Value | Meaning |
|---|---|---|
| `DEFI_SCALE` | 10000 | Fixed-point scale: parts per 1.0 (1e-4), one basis point. |
| `DEFI_BPS` | 10000 | Maximum accepted basis-point value (100%). |

## Internal Helpers (not public API)

| Helper | Contract |
|---|---|
| `_defi_ok(v)` / `_defi_err(m)` | Leaf `Ok(v)` / `Err(m)` constructors for `Result[Int, Str]` (v0.62.2 leaf-helpers rule). |
| `_defi_clamp_bps(v)` | `0` if `v < 0`, `10000` if `v > 10000`, else `v`. |
| `_defi_mul_sat(a, b)` | `min(a * b, INT_MAX)` for non-negative `a`, `b`; a non-positive operand yields `0`. Overflow is detected with `a > INT_MAX / b`, so no wrapping multiply occurs. |
| `_defi_add_sat(a, b)` | `min(a + b, INT_MAX)`; negative operands are treated as `0`; zero is the identity. Detects overflow with `a > INT_MAX - b`. |
| `_defi_ceil_div(a, b)` | `ceil(a / b)` for `a >= 0`, `b > 0`; returns `0` when `b <= 0`. Uses the native truncating division plus one when `a > 0` and `a % b != 0`. |
| `_defi_isqrt(n)` | `floor(sqrt(n))` for `n >= 0`, `0` for `n <= 0`, via integer Newton iteration (`x = n/2 + 1`, then `next = (x + n/x)/2` while `next < x`). |

## Public API: Constant-Product AMM

```
pub fn amm_new(reserve_a: Int, reserve_b: Int, fee_bps: Int) -> AmmPool
pub fn amm_fee_amount(amount_in: Int, fee_bps: Int) -> Int
pub fn amm_get_amount_out(reserve_in: Int, reserve_out: Int, amount_in: Int, fee_bps: Int) -> Int
pub fn amm_get_amount_in(reserve_in: Int, reserve_out: Int, amount_out: Int, fee_bps: Int) -> Int
pub fn amm_spot_price_bps(reserve_a: Int, reserve_b: Int) -> Int
pub fn amm_swap(p: &mut AmmPool, amount_in: Int, min_out: Int, a_to_b: Bool) -> Result[Int, Str]
pub fn amm_mint(p: &mut AmmPool, amount_a: Int, amount_b: Int) -> Int
pub fn amm_burn(p: &mut AmmPool, shares: Int) -> (Int, Int)
pub fn amm_k(p: &AmmPool) -> Int
pub fn amm_k_check(reserve_a_before: Int, reserve_b_before: Int, reserve_a_after: Int, reserve_b_after: Int) -> Bool
```

## Public API: Share-Index Lending Pool

```
pub fn lend_new(reserve_bps: Int) -> LendPool
pub fn lend_total_supply(p: &LendPool) -> Int
pub fn lend_total_borrow(p: &LendPool) -> Int
pub fn lend_supply_balance(p: &LendPool, shares: Int) -> Int
pub fn lend_borrow_balance(p: &LendPool, shares: Int) -> Int
pub fn lend_supply(p: &mut LendPool, amount: Int) -> Int
pub fn lend_withdraw(p: &mut LendPool, shares: Int) -> Int
pub fn lend_borrow(p: &mut LendPool, amount: Int) -> Int
pub fn lend_repay(p: &mut LendPool, shares: Int) -> Int
pub fn lend_accrue(p: &mut LendPool, rate_bps: Int, ticks: Int) -> Int
pub fn lend_collateral_ratio_bps(collateral: Int, debt: Int) -> Int
pub fn lend_health_factor_bps(collateral: Int, debt: Int, threshold_bps: Int) -> Int
pub fn lend_is_liquidatable(health_factor_bps: Int) -> Bool
pub fn lend_liquidation_amounts(debt: Int, collateral: Int, close_factor_bps: Int, bonus_bps: Int) -> (Int, Int)
pub fn lend_check_indexes(p: &LendPool, supply_index_before: Int, borrow_index_before: Int) -> Bool
```

## Semantics

### AMM

- **`amm_new(ra, rb, fee)`** -- negative reserves clamp to 0, fee clamps to
  `[0, 10000]`. With `ra, rb > 0` and `shares = _defi_isqrt(_defi_mul_sat(ra,
  rb))`, `lp_total = shares`, or 1 when `shares == 0`. A zero reserve yields
  `lp_total = 0`; the pool is then bootstrapped by the first `amm_mint`.
- **`amm_fee_amount(a, fee)`** -- `a <= 0` returns 0; otherwise
  `mul_sat(a, clamp(fee)) / 10000` (floor).
- **`amm_get_amount_out(ri, ro, a, fee)`** -- 0 when `a <= 0` or either
  reserve `<= 0`. Otherwise
  `in_fee = a - amm_fee_amount(a, fee)`;
  `out = mul_sat(in_fee, ro) / add_sat(ri, in_fee)` (floor), capped at `ro`.
  `in_fee == 0` (100% fee) returns 0.
- **`amm_get_amount_in(ri, ro, out, fee)`** -- 0 when `out <= 0`, a reserve
  `<= 0`, `out >= ro`, or `fee >= 10000`. Otherwise
  `without_fee = _defi_ceil_div(mul_sat(ri, out), ro - out)` and
  `result = _defi_ceil_div(mul_sat(without_fee, 10000), 10000 - fee)`.
  Both ceilings make the quoted input sufficient:
  `get_amount_out(ri, ro, get_amount_in(...), fee) >= out` for serviceable
  quotes.
- **`amm_spot_price_bps(ra, rb)`** -- `mul_sat(rb, 10000) / ra` (floor);
  0 when a reserve is `<= 0`.
- **`amm_swap(p, a, min_out, a_to_b)`** -- guard order: `a <= 0`,
  reserves `<= 0`, quote `<= 0`, `quote < min_out`. On success (and only
  then) `a_to_b` adds `a` to `reserve_a` and subtracts the quote from
  `reserve_b`; the reverse direction is symmetric. `min_out <= 0` disables
  the slippage guard. Errors: `"amm: amount_in must be > 0"`,
  `"amm: empty reserves"`, `"amm: zero output"`, `"amm: slippage"`.
- **`amm_mint(p, amount_a, amount_b)`** -- 0 when an amount is `<= 0`. With
  `lp_total == 0`: `shares = max(1, _defi_isqrt(mul_sat(amount_a,
  amount_b)))`. With `lp_total > 0`: both reserves must be `> 0`, then
  `shares = min(mul_sat(amount_a, lp_total) / reserve_a,
  mul_sat(amount_b, lp_total) / reserve_b)` and 0 shares reject the mint.
  On success both full amounts are deposited and `lp_total += shares`; any
  deposit imbalance is documented as a donation to existing LPs.
- **`amm_burn(p, shares)`** -- `(0, 0)` when `shares <= 0`,
  `lp_total <= 0`, or `shares > lp_total`. Otherwise
  `amount_a = mul_sat(shares, reserve_a) / lp_total` (floor) and likewise
  for B; if both round to 0 the burn is rejected so dust shares are not
  destroyed for nothing. On success reserves shrink and `lp_total -= shares`.
  A proportional mint followed by an equal burn round-trips exactly whenever
  the floors are exact, and never returns more than deposited otherwise.
- **`amm_k(p)`** -- `mul_sat(reserve_a, reserve_b)`.
- **`amm_k_check(...)`** -- `mul_sat(after) >= mul_sat(before)`; fee-bearing
  swaps make k strictly grow, so this invariant holds across every public
  transition.

### Lending

- **`lend_new(reserve_bps)`** -- zero shares, both indexes `10000`,
  reserve factor clamped to `[0, 10000]`.
- **Totals/balances** -- `lend_total_supply = mul_sat(supply_shares,
  supply_index) / 10000`; `lend_total_borrow` is the same with the borrow
  side; `lend_supply_balance(p, s)` and `lend_borrow_balance(p, s)` value an
  arbitrary non-negative share count (`s <= 0` gives 0).
- **`lend_supply(p, amount)`** -- `shares = mul_sat(amount, 10000) /
  supply_index`; 0 for `amount <= 0` or 0 shares; otherwise
  `supply_shares += shares`.
- **`lend_withdraw(p, shares)`** -- 0 when `shares <= 0`,
  `shares > supply_shares`, the amount floors to 0, or the amount exceeds
  available liquidity `total_supply - total_borrow`. Otherwise
  `amount = mul_sat(shares, supply_index) / 10000`, `supply_shares -= shares`.
- **`lend_borrow(p, amount)`** -- 0 when `amount <= 0`, `amount` exceeds
  available liquidity, or 0 shares. Otherwise
  `shares = mul_sat(amount, 10000) / borrow_index`, `borrow_shares += shares`.
- **`lend_repay(p, shares)`** -- 0 when `shares <= 0`,
  `shares > borrow_shares`, or the amount floors to 0. Otherwise
  `amount = mul_sat(shares, borrow_index) / 10000`, `borrow_shares -= shares`.
- **`lend_accrue(p, rate_bps, ticks)`** -- no-op returning 0 when
  `ticks <= 0`, the clamped rate is 0, or an index is non-positive. For each
  of `ticks` iterations (counter strictly increases):
  `new_index = mul_sat(borrow_index, 10000 + rate) / 10000`;
  `delta = new_index - borrow_index`;
  `borrow_interest = mul_sat(borrow_shares, delta) / 10000`;
  `reserve_cut = mul_sat(borrow_interest, reserve_bps) / 10000`;
  `supply_interest = borrow_interest - reserve_cut`; and when both
  `supply_interest > 0` and `supply_shares > 0`,
  `supply_index += mul_sat(supply_interest, 10000) / supply_shares`
  (each floor favors the pool). `borrow_index = new_index` always. Returns
  the total supplier interest credited; with no supply shares the borrow
  index still compounds but nothing is credited.
- **`lend_collateral_ratio_bps(c, d)`** -- `d <= 0` returns `INT_MAX`
  (infinitely healthy); `c <= 0` returns 0; otherwise
  `mul_sat(c, 10000) / d`.
- **`lend_health_factor_bps(c, d, t)`** -- same sentinels; otherwise
  `mul_sat(c, clamp(t)) / d`. 1.0 (10000) is the boundary.
- **`lend_is_liquidatable(hf)`** -- `hf < 10000`.
- **`lend_liquidation_amounts(d, c, cf, bonus)`** -- `(0, 0)` when `d <= 0`
  or `c <= 0` or the repayment floors to 0. Otherwise
  `repay = mul_sat(d, clamp(cf)) / 10000` and
  `seize = min(c, _defi_ceil_div(mul_sat(repay, 10000 + clamp(bonus)),
  10000))`.
- **`lend_check_indexes(p, si0, bi0)`** -- true when
  `p.supply_index >= si0 && p.borrow_index >= bi0`; accrual never decreases
  either index.

## Rounding Rules

- **Single convention: truncation toward zero.** Every `/` in the module is
  the native `Int` operator. Positive magnitudes floor; there is no floor
  helper, half-up, or banker's rounding anywhere.
- **Pool-favoring floors.** Swap outputs (`get_amount_out`), LP shares
  (`mint`), withdrawal amounts (`burn`, `withdraw`, `repay`), index
  increments and liquidation repayment are floored, so the pool's invariant
  or solvency never worsens through rounding. Fee amounts floor toward the
  trader by less than one base unit.
- **Ceilings.** `_defi_ceil_div` is used only in `amm_get_amount_in` (twice,
  so the quoted input is sufficient) and in `lend_liquidation_amounts` (the
  bonus seizure rounds up, favoring the protocol).
- **Truncation points.** AMM: once per fee, once per quote, once per
  proportional share/amount. Lending: once per share mint/burn, once per
  borrow index step, once per interest split, once per per-share increment.
- **Saturation.** Products and sums saturate at `INT_MAX` rather than
  wrapping; saturation only occurs far beyond the safe test scale and is
  pinned by t18.

## Edge Cases

| Input | Result |
|---|---|
| negative reserves in `amm_new` | clamped to 0; `lp_total` 0 unless both are positive |
| fee/rate/threshold/close-factor/bonus outside [0, 10000] | clamped |
| 100% swap fee | `get_amount_out` 0, `get_amount_in` 0 |
| `amount_out >= reserve_out` | `get_amount_in` 0 |
| `min_out <= 0` in `amm_swap` | slippage guard disabled |
| rejected `amm_swap` / `amm_mint` / burn | state left exactly unchanged |
| `shares > lp_total` in `amm_burn` | `(0, 0)` |
| both burn withdrawals floor to 0 | `(0, 0)`, shares kept |
| zero reserve with outstanding `lp_total` in `amm_mint` | 0, no state change |
| overflow-sized products | saturate at `INT_MAX` |
| `amount <= 0` in supply/borrow or `shares <= 0` in withdraw/repay | 0, no state change |
| borrow/withdraw above available liquidity | 0, no state change |
| `ticks <= 0` or `rate_bps <= 0` in `lend_accrue` | 0, indexes unchanged |
| no supply shares during accrual | borrow index compounds, 0 credited |
| `debt <= 0` in ratio/health | `INT_MAX` |
| `collateral <= 0` with positive debt | 0 (liquidatable) |
| seizure above collateral | capped at collateral |
| unused `Vec` | none: the module has no vector parameters |

## Error Paths

Only `amm_swap` returns `Result[Int, Str]` (the three guard errors plus
slippage). Every other function is total: invalid inputs return `0`,
`(0, 0)`, or `INT_MAX` (the no-debt sentinel) and never mutate state. There
are no contracts, no panics and no overflow traps: saturation is the
documented overflow behavior.

## Complexity

| Function | Time | Extra memory |
|---|---|---|
| `amm_new` | O(log(reserve_a * reserve_b)) | O(1) |
| `amm_fee_amount`, `amm_get_amount_out`, `amm_get_amount_in`, `amm_spot_price_bps` | O(1) | O(1) |
| `amm_swap` | O(1) | O(1) |
| `amm_mint` (bootstrap) | O(log(amount_a * amount_b)) | O(1) |
| `amm_mint` (existing supply), `amm_burn`, `amm_k`, `amm_k_check` | O(1) | O(1) |
| `lend_total_supply`, `lend_total_borrow`, `lend_supply_balance`, `lend_borrow_balance` | O(1) | O(1) |
| `lend_supply`, `lend_withdraw`, `lend_borrow`, `lend_repay` | O(1) | O(1) |
| `lend_accrue` | O(ticks) | O(1) |
| ratio / health / liquidatable / liquidation amounts / check indexes | O(1) | O(1) |

Every loop counter strictly increases; `lend_accrue` runs exactly `ticks`
iterations and `_defi_isqrt`'s Newton sequence strictly decreases before it
returns, so the suite terminates in milliseconds.

## Test Plan

`tests/test_conformance.xi` -- 28 deterministic named checks, direct calls
only (no fn tables), fixture-driven (`amm_even_fixture`,
`amm_pair_fixture`, `amm_after_mint_fixture`, `lend_active_fixture`), with
the swap `Result` collapsed by the small `swap_code` classifier.

| Test | Checks | Exact expectations |
|---|---|---|
| t01 `amm_new` seeds/clamps | sqrt(k) shares, negative reserves, fee clamp | `(100000, 400000, 30) -> lp 200000`; `(-5, 100, 20000) -> (0, 100, fee 10000, lp 0)`; `(1, 1, -3) -> lp 1, fee 0` |
| t02 fee amount | floor + clamp | `(1000, 30) -> 3`, `(999, 30) -> 2`, `(50, 30) -> 0`, `(-5, 30) -> 0`, `(100, 20000) -> 100` |
| t03 out no fee | canonical quotes | `(100000, 100000, 10000, 0) -> 9090`, `(100000, 200000, 10000, 0) -> 18181` |
| t04 out with fee | fee effect | `(100000, 100000, 10000, 30) -> 9066`, 100% fee -> 0 |
| t05 out guards | zero/negative inputs | reserves 0 or amount `<= 0` -> 0 |
| t06 amount-in | inverse + ceilings | `(100000, 100000, 9066, 30) -> 10000`, `(100000, 100000, 9090, 0) -> 9999`, `out >= reserve` -> 0, 100% fee -> 0 |
| t07 spot price | floor ratio | `(100000, 200000) -> 20000`, `(300000, 100000) -> 3333`, bad reserves -> 0 |
| t08 swap moves reserves | success path + k | in 10000, fee 30 -> 9066; reserves `110000 / 90934`; `k = 10002740000 > 1e10` |
| t09 slippage | rejection atomicity | min_out 9067 -> -1; reserves unchanged |
| t10 invalid swap | zero/negative/empty | -1 each; state unchanged |
| t11 reverse swap | direction select | b_to_a in 10000 -> 9066; `reserve_b 110000`, `reserve_a 90934` |
| t12 k invariant | k-check + `amm_k` read | accepts growth/equality, rejects shrink; `amm_k(100000,100000) = 1e10` |
| t13 mint proportional | min share formula | `(10000, 20000)` on lp 100000 -> 10000 shares; `(110000, 220000, lp 110000)` |
| t14 mint rejects | zero/negative/dust | 0 and unchanged each time |
| t15 burn round trip | exact exit | burn 10000 -> `(10000, 20000)`; restores `100000 / 200000 / lp 100000` |
| t16 burn guards | invalid and full burn | `0` and `lp+1` -> `(0,0)`; burning all 100000 -> `(100000, 200000)`, pool drained |
| t17 burn partial | proportional withdrawal | burn 50000 -> `(50000, 100000)`; left `(60000, 120000, lp 60000)` |
| t18 saturation | overflow guards | `get_amount_out(INT_MAX, INT_MAX, INT_MAX, 0) = 1` (no wrap); `fee(INT_MAX, 100%) = 922337203685477` |
| t19 lend new/supply | index 1.0 mint | supply 100000 -> 100000 shares; total 100000; non-positive -> 0 |
| t20 borrow limits | liquidity cap | 100001 -> 0, 50000 -> 50000, 50001 -> 0, 50000 -> 50000; total borrow 100000 |
| t21 accrual two ticks | compounding + split | `accrue(100 bps, 2) -> 905`; borrow index 10201, supply index 10090; totals 51005 / 100900 |
| t22 accrual no-op | ticks/rate guards + monotonicity | ticks `0`, rate `0`/negative -> 0 unchanged; 50 bps x 3 credits > 0 and indexes never drop |
| t23 read helpers | totals/valuations/invariant | empty totals 0; 5 shares worth 5 at 1.0; index check true/false |
| t24 round trip | supply/withdraw at 1.0 + guards | 100000 -> 100000; 123456 -> 123456 then burn 23456 -> 23456; bad share counts -> 0 |
| t25 lifecycle | available-liquidity guard | after 2 ticks: full withdraw -> 0; 40000 shares -> 40360 (60000 left); repay 50000 -> 51005; 60000 shares -> 60540; both sides 0 |
| t26 repay guards | index 1.0 + invalid | repay 50000 -> 50000; then 1 and 0 -> 0 |
| t27 health/ratio | ratios + boundary | ratio `(150000, 100000) -> 15000`, debt 0 -> INT_MAX, collateral 0 -> 0; hf 12000 / 6000; liquidatable exactly below 10000 |
| t28 liquidation | close factor + bonus + cap | `(100002, 150000, 5000, 800) -> (50001, 54002)`; cap at collateral 30000; close-factor clamp; zero debt/collateral -> `(0, 0)` |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.defi
```

Expected: `port: PASS (passed=28 failed=0 program_exit=0 exit=0)`.

## Known Limitations

- **No overflow errors.** `_defi_mul_sat` / `_defi_add_sat` saturate at
  `INT_MAX`; extreme inputs produce deterministic but economically saturated
  results. Tests pin the guard behavior at the `INT_MAX` boundary.
- **Truncation, not rounding.** Results for positive rates sit at or below
  the exact rational values; accrual truncation is observable and pinned
  (e.g. 50 000 borrowed at 100 bps over 2 ticks pays 905 to suppliers after
  the 10% reserve cut).
- **Donation on unbalanced mint.** `amm_mint` credits the smaller
  proportional share count and deposits both amounts; the imbalance accrues
  to existing LPs.
- **Bootstrap shares are geometric.** A share-less pool mints
  `floor(sqrt(amount_a * amount_b))`; the first depositor therefore sets the
  initial price at the reserve ratio of the deposit, not at an oracle.
- **No interest-rate model.** `rate_bps` is caller-supplied per tick; there
  is no utilisation-based curve and no per-second/per-year convention.
- **Liquidation is capped, not socialised.** Seizure cannot exceed posted
  collateral, and the pool does not model bad debt or insurance.
- **No safety module, pause, fees-on-transfer or token decimals.** Amounts
  are plain integers in the caller's units.
