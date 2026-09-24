# xiom.finance SPEC

## Package Overview

`xiom.finance` is a pure-XIOM, FFI-free toolkit for integer
time-value-of-money arithmetic: simple and compound interest, effective
annual rate (APY), annuity payments, total interest, net present value, and a
rule-of-72 doubling indicator. One module: `xiom.finance`
(`src/finance.xi`). Money crosses the API in **cents** (`Int`), rates cross
it in **permille** (`Int`, 1% = 10 permille), and time crosses it as a plain
count of periods. There is no floating point and no calendar.

## Scope

- Simple interest (`finance_simple_interest_cents`).
- Per-period compound interest (`finance_compound_cents`).
- Effective annual rate from a nominal annual rate (`finance_apy_permille`).
- Fully amortizing annuity payment (`finance_payment_cents`) and lifetime
  interest (`finance_total_interest_cents`).
- Discounted cash-flow sum (`finance_npv_cents`).
- Rule-of-72 doubling indicator (`finance_rule_of_72_periods`).

## Non-Goals

- No floating point; `Vec[Float64]` is never used (v0.61.3 trap).
- No dates, calendars, day-count conventions, or amortization schedules;
  a period is whatever the caller says it is.
- No currencies, exchange rates, rounding modes, or locale formatting.
- No structs, no `Vec[StructType]`, no `Vec[fn]` dispatch, no match
  statements -- the whole module is scalar `Int` / `&Vec[Int]` arithmetic.
- No mutation: the only reference parameter is `&Vec[Int]` (read-only) and
  every result is a fresh scalar.
- Not for regulatory or accounting accuracy; results are planning-grade
  integer arithmetic, not financial advice.

## Data Model

| Concept | Representation |
|---|---|
| Money | `Int` cents (100 cents = 1 major unit) |
| Rate | `Int` permille (1% = 10 permille; 100% = 1000 permille) |
| Time | `Int` periods (periods per year are a caller convention) |
| Cash flows | `Vec[Int]` cents, index 0 = period 0 |

## API Signatures

```
pub fn finance_simple_interest_cents(principal_cents: Int, rate_permille: Int, periods: Int) -> Int
pub fn finance_compound_cents(principal_cents: Int, rate_permille: Int, periods: Int) -> Int
pub fn finance_apy_permille(nominal_permille: Int, periods_per_year: Int) -> Int
pub fn finance_payment_cents(principal_cents: Int, rate_permille: Int, periods: Int) -> Int
pub fn finance_total_interest_cents(principal_cents: Int, rate_permille: Int, periods: Int) -> Int
pub fn finance_npv_cents(rate_permille: Int, flows: &Vec[Int]) -> Int
pub fn finance_rule_of_72_periods(rate_permille: Int) -> Int
```

Internal helper (not public API): `_finance_ceil_div(a: Int, b: Int) -> Int`
for `b > 0`.

## Semantics

Let `P` be the principal in cents, `r` the rate in permille, `n` the number
of periods.

- **`finance_simple_interest_cents(P, r, n)`** --
  `P * r * n / 1000`, evaluated as one product and one truncating division.
  No per-period iteration, so no compounding. Negative `P` or `r` and
  non-positive `n` are all defined (the product simply carries the sign or
  is 0).
- **`finance_compound_cents(P, r, n)`** -- `n <= 0` returns `P`. Otherwise
  the recurrence `p = p * (1000 + r) / 1000` is applied exactly `n` times,
  each division truncating toward zero before the next period begins, so
  truncation compounds (unlike simple interest).
- **`finance_apy_permille(nominal, k)`** -- `m = max(1, k)`.
  `denom = 1000*m + nominal`; if `denom <= 0` return `-1000` (clamped total
  loss; at or beyond -100% per period compounding is undefined upward).
  Otherwise the growth factor is tracked in millionths:
  `growth = 1000000`, repeated `m` times
  `growth = growth * denom / (1000*m)`, then
  `apy = (growth - 1000000) / 1000`, every division truncating toward zero.
  With `m == 1` the result is exactly `nominal`.
- **`finance_payment_cents(P, r, n)`** -- `n <= 0` returns 0. `r == 0`
  returns `ceil(P / n)` (`_finance_ceil_div`, exact for negative `P` because
  truncation toward zero is the ceiling there). `r <= -1000` returns 0.
  Otherwise the annuity factor is iterated in millionths:
  `scale = 1000000`, `factor = scale`, and for each of the `n` periods
  `factor = factor * 1000 / (1000 + r)` then `accum = accum + factor`
  (truncating each step); the result is `P * scale / accum`, truncated
  toward zero. This is `P / a` with
  `a = sum_{i=1..n} (1000/(1000+r))^i` approximated from below.
- **`finance_total_interest_cents(P, r, n)`** --
  `payment = finance_payment_cents(P, r, n)`;
  result `max(0, payment * n - P)`. At `r == 0` the only nonzero source is
  the rounding excess of the ceiling payment.
- **`finance_npv_cents(r, flows)`** -- `div = max(1, 1000 + r)`;
  `factor = 1000`; `total = 0`. For each element in order:
  `discounted = flow[i] * factor / 1000`, `total += discounted`, then
  `factor = factor * 1000 / div`. Each division truncates toward zero, so
  each contribution is truncated before summing. Empty input returns 0 and
  `r == 0` returns the exact sum.
- **`finance_rule_of_72_periods(r)`** -- `r <= 0` returns `-1`; otherwise
  `ceil(72000 / r)` (`_finance_ceil_div`).

## Rounding Rules

- **Single convention: truncation toward zero.** Every `/` in the module is
  the native `Int` operator. Positive magnitudes round down, negative
  magnitudes round up (toward zero); there is no floor, half-up, or banker's
  rounding anywhere.
- **Truncation points.** Simple interest truncates once, after the full
  product. Compound interest truncates once per period. APY truncates once
  per compounding period (on a millionths-scale factor, so per-period loss
  is at most 1e-6 of value) and once more when converting millionths to
  permille. The annuity truncates at every discount step and once on the
  final division. NPV truncates once per flow.
- **Ceilings.** `finance_payment_cents` at rate 0 and
  `finance_rule_of_72_periods` use ceiling division; `_finance_ceil_div`
  achieves it because for `a > 0` truncation is one below the ceiling and
  for `a <= 0` truncation already equals the ceiling.
- **Why millionths.** The annuity factor and the APY growth factor are
  accumulated at scale 1,000,000 (not 1000) so that per-step truncation does
  not visibly bias the result; the permille-scale iteration would lose
  several permille of accuracy over a year of periods.

## Edge Cases

| Input | Result |
|---|---|
| `periods <= 0` in simple interest | product is 0 (or signed 0) -- returns 0 |
| `periods <= 0` in compound | returns the principal unchanged |
| `periods <= 0` in payment / total interest | payment 0, total interest 0 |
| rate 0 in payment | `ceil(P / n)` |
| rate 0 in total interest | payment-rounding excess only, e.g. `P=100000, n=3` -> 2 cents |
| negative rate in simple interest / compound | allowed, sign carried, truncation toward zero |
| `rate <= -1000` in payment | 0 (annuity factor diverges) |
| `rate <= -1000` in NPV | divisor clamped to 1 (factor grows 1000x per period) |
| `nominal <= -1000*m` in APY | clamped to -1000 permille |
| `periods_per_year < 1` in APY | clamped to 1 (APY equals the nominal rate) |
| empty `flows` in NPV | 0 |
| `flows` of zeros | 0 |
| `rate <= 0` in rule of 72 | -1 |
| negative `principal` | defined for every function; truncation toward zero |

## Error Paths

The API is total: no `Result` returns, no contracts, no panics. Every
function is defined for every `Int` argument (and every `Vec[Int]`,
including empty) under pure two's-complement arithmetic; only overflow is
not detected (see Known Limitations).

## Complexity

| Function | Time | Extra memory |
|---|---|---|
| `finance_simple_interest_cents` | O(1) | O(1) |
| `finance_compound_cents` | O(n) | O(1) |
| `finance_apy_permille` | O(periods_per_year) | O(1) |
| `finance_payment_cents` | O(n) | O(1) |
| `finance_total_interest_cents` | O(n) | O(1) |
| `finance_npv_cents` | O(flows.len()) | O(1) |
| `finance_rule_of_72_periods` | O(1) | O(1) |

## Test Plan

`tests/test_conformance.xi` (31 deterministic named tests; expected flows are
built with `fvN` helpers and every `Vec[Int]` read uses a typed `let` binding
per the v0.61.3 trap).

| Test | Checks | Exact expectations |
|---|---|---|
| t01 simple known | canonical case | `(100000, 50, 2) -> 10000` |
| t02 simple zero | zero rate / zero principal | `(100000, 0, 5) -> 0`, `(0, 50, 10) -> 0` |
| t03 simple negative rate | signed result | `(100000, -50, 2) -> -10000`, `(100000, -3, 7) -> -2100` |
| t04 simple truncation | toward zero, both signs | `(101, 10, 1) -> 1`, `(-101, 10, 1) -> -1`, `(199, 10, 1) -> 1` |
| t05 compound known | canonical case | `(10000, 50, 2) -> 11025` |
| t06 compound single step | truncation once | `(101, 10, 1) -> 102`, `(9999, 10, 1) -> 10098` |
| t07 compound truncation compounds | 349.65 then 366.45 | `(333, 50, 1) -> 349`, `(333, 50, 2) -> 366` |
| t08 compound zero / nonpositive periods | identity paths | `(10000, 0, 10) -> 10000`, `(12345, 50, 0) -> 12345`, `(12345, 50, -3) -> 12345` |
| t09 compound negative rate | signed | `(10000, -50, 2) -> 9025`, `(-10000, 50, 2) -> -11025` |
| t10 APY zero | any frequency | `(0, 12) -> 0`, `(0, 1) -> 0`, `(0, -5) -> 0` |
| t11 APY monthly known | 10% nominal monthly | `(100, 12) -> 104` (exact 104.713) |
| t12 APY exact cases | exact integer paths | `(200, 2) -> 210`, `(100, 1) -> 100` |
| t13 APY clamps periods | `k < 1 -> 1` | `(75, 0) -> 75`, `(75, -4) -> 75`, `(-100, 1) -> -100` |
| t14 APY total loss clamp | at/below -100%/period | `(-2000, 1) -> -1000`, `(-1000, 1) -> -1000` |
| t15 payment zero rate | ceiling, both signs | `(100000, 0, 3) -> 33334`, `(100000, 0, 4) -> 25000`, `(7, 0, 2) -> 4`, `(-7, 0, 2) -> -3` |
| t16 payment known annuity | 2 periods @ 50 | `(100000, 50, 2) -> 53780` (exact 53780.48) |
| t17 payment known annuity | 12 periods @ 10 | `(100000, 10, 12) -> 8884` (exact 8884.88) |
| t18 payment periods nonpositive | 0 | `(100000, 50, 0) -> 0`, `(100000, 50, -2) -> 0` |
| t19 payment negative rate | -50 permille | `(100000, -50, 2) -> 46282` |
| t20 payment rate <= -1000 | clamp | `(100000, -1000, 2) -> 0`, `(100000, -5000, 2) -> 0` |
| t21 total interest zero rate | exact division vs excess | `(100000, 0, 4) -> 0`, `(100000, 0, 3) -> 2` |
| t22 total interest positive | 2 periods @ 50 | `(100000, 50, 2) -> 7560` |
| t23 total interest clamped | raw -7436 -> 0 | `(100000, -50, 2) -> 0`, `(100000, 50, 0) -> 0` |
| t24 NPV zero rate | exact sum | `[100, -20, 5] @ 0 -> 85`, `[777] @ 0 -> 777` |
| t25 NPV positive rate | factor 1000 then 952 | `[10000, 10000] @ 50 -> 19520`, three flows -> 28580 |
| t26 NPV negative rate | factor 1000 then 1052 | `[10000, 10000] @ -50 -> 20520` |
| t27 NPV empty/zeros | 0 | `[] @ 50 -> 0`, `[0,0,0] @ 50 -> 0` |
| t28 rule of 72 known | exact multiples | `100 -> 720`, `90 -> 800`, `200 -> 360` |
| t29 rule of 72 ceiling | 1028.57 -> 1029 | `70 -> 1029` |
| t30 rule of 72 nonpositive | -1 | `0 -> -1`, `-50 -> -1` |
| t31 large values | trillion-cent exactness | `(1e12, 25, 4) -> 1e11`; `(1e12, 10, 2) -> 1020100000000`; NPV `[1e12,1e12,1e12] @ 0 -> 3e12`; payment `(1e12, 0, 8) -> 125000000000`; rule `1 -> 72000` |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.finance
```

Expected: `port: PASS (passed=31 failed=0 program_exit=0 exit=0)`.

## Known Limitations

- **No overflow protection.** `P * r * n`, `p * (1000 + r)`,
  `P * 1000000` and `flow * factor` can exceed `Int` (i64) for extreme
  magnitudes; results are then two's-complement arithmetic. Tests pin
  trillion-cent inputs as a safe scale.
- **Truncation, not rounding.** Results for positive rates sit at or below
  exact rational values; compounding truncation is observable and pinned
  (e.g. 333 @ 50 permille over 2 periods gives 366, not 367).
- **Rule of 72 is an indicator.** The `ceil(72000 / rate_permille)` convention
  is integer and monotone but not the exact doubling solution
  `n = ceil(log(2)/log(1 + r/1000))`; e.g. it returns 720 periods at 100
  permille by construction.
- **APY assumes the nominal rate is spread evenly** over
  `periods_per_year` periods; no day-count conventions and no intra-year
  cash flows.
- **Payment has no amortization schedule.** It returns the level payment
  only; there is no per-period split into interest and principal, and the
  final payment is not adjusted for accumulated truncation.
- **No negative periods or fractional rates.** Periods are integers; rates
  below 1 permille (0.1%) cannot be represented directly -- scale the rate
  and the periods with the same factor when needed.
