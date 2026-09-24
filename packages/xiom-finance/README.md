# xiom.finance

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** integer time-value-of-money: simple and compound interest, APY,
> annuity payments, total interest, net present value, and a rule-of-72
> doubling indicator.
> **Deps:** `xiom.std` only (`deps` declares the platform dependency; the
> library module itself imports nothing). Pure XIOM, no FFI.

## What it is

`xiom.finance` is a small, dependency-free toolkit for time-value-of-money
arithmetic. Money is carried in **cents** (`Int`), rates are carried in
**permille** (`Int`, 1% = 10 permille), and there is no floating point and no
calendar: a "period" is just one application of the caller's rate. Every
returned value is an integer.

The module exposes seven public free functions plus one internal helper:
two interest primitives (`finance_simple_interest_cents`,
`finance_compound_cents`), one effective annual rate (`finance_apy_permille`),
two annuity functions (`finance_payment_cents`,
`finance_total_interest_cents`), one discounted cash-flow function
(`finance_npv_cents`), and one doubling-time indicator
(`finance_rule_of_72_periods`).

**Rounding.** Every division in the module uses the native `Int` operator,
which truncates toward zero -- positive magnitudes round down, negative
magnitudes round up (toward zero). The exact truncation points (per period
for compounding, per flow for NPV, once at the end for simple interest) are
documented in each function's comment and pinned by tests; no other rounding
mode is offered.

## API

| Function | Returns | Description |
|---|---|---|
| `finance_simple_interest_cents(principal_cents, rate_permille, periods)` | `Int` | `principal * rate * periods / 1000`, one division truncating toward zero. Negative principals and rates allowed. |
| `finance_compound_cents(principal_cents, rate_permille, periods)` | `Int` | Per-period compounding `p = p * (1000 + rate) / 1000`, truncated every period. `periods <= 0` returns the principal. |
| `finance_apy_permille(nominal_permille, periods_per_year)` | `Int` | Effective annual rate: nominal spread over `max(1, periods_per_year)` periods, compounded with the growth factor tracked in millionths, truncated toward zero. Annual compounding returns the nominal rate exactly. |
| `finance_payment_cents(principal_cents, rate_permille, periods)` | `Int` | Fully amortizing level payment: the annuity factor is iterated in millionths (truncating each discount step), then `principal * 1000000 / accum`. Rate 0 gives `ceil(principal / periods)`; `periods <= 0` gives 0; rates at or below -100% give 0. |
| `finance_total_interest_cents(principal_cents, rate_permille, periods)` | `Int` | `payment * periods - principal`, clamped to a minimum of 0. At rate 0 it is only the payment-rounding excess. |
| `finance_npv_cents(rate_permille, flows)` | `Int` | `flow[0]` undiscounted, then `factor = factor * 1000 / (1000 + rate)` per period; each `flow * factor / 1000` truncates toward zero. Empty series is 0; rate 0 is exactly the sum. |
| `finance_rule_of_72_periods(rate_permille)` | `Int` | `ceil(72000 / rate_permille)` periods; `-1` for a non-positive rate. |

## Usage

```xi
use xiom.finance;

let simple   = finance_simple_interest_cents(100000, 50, 2);  // 10000 cents
let balance  = finance_compound_cents(10000, 50, 2);          // 11025 cents
let apy      = finance_apy_permille(100, 12);                 // 104 permille (10.4%)
let payment  = finance_payment_cents(100000, 50, 2);          // 53780 cents
let interest = finance_total_interest_cents(100000, 50, 2);   // 7560 cents

let flows = ...;                       // Vec[Int], one flow per period
let npv   = finance_npv_cents(50, &flows);

let double_periods = finance_rule_of_72_periods(100);         // 720 periods
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.finance
```

Expected: the namespaced module passes the section-4 namespace rule, 31
`[PASS]` lines, and a final
`port: PASS (passed=31 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integer cents and permille only.** There is no floating-point path
  (`Vec[Float64]` is not used): fractional cents are dropped at every
  truncation point, and rates coarser than 0.1% (1 permille) cannot be
  expressed directly.
- **Truncation compounds.** Compound interest truncates once per period and
  the annuity factor once per discount step, so repeated results sit slightly
  below exact rational values for positive rates. The deviation is pinned by
  tests, not hidden.
- **Rule of 72 scaling.** `finance_rule_of_72_periods` applies the documented
  package convention `ceil(72000 / rate_permille)`; it is a quick integer
  indicator, not an exact doubling calculation.
- **No overflow guards.** Products such as `principal * rate * periods`,
  `p * (1000 + rate)` and `flow * factor` can overflow `Int` (i64) for
  extreme magnitudes; values are used as given.
- **Not regulatory or accounting accuracy.** Results are deterministic
  integer arithmetic for planning and simulation, not bank-grade accrual,
  day-count, amortization-schedule or tax output, and nothing here is
  financial advice.
- **Single-threaded.** No locks, atomics or async variants; callers serialize
  access.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
