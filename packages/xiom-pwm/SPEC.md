# xiom.pwm -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.pwm` (`src/pwm.xi`). Pure XIOM, no FFI, no hardware.

## 1. Scope

Integer PWM math:

- `pwm_channel` builds a validated `PwmChannel` from a clock, a frequency
  and a per-mille duty;
- accessors expose the clock, frequency, floored period, realized frequency
  and duty;
- `pwm_set_duty`, `pwm_duty_ticks`, `pwm_set_duty_ticks`,
  `pwm_period_micros` and `pwm_duty_micros` implement duty and timing
  conversions;
- `pwm_servo_duty` and `pwm_servo_channel` map servo angles onto duty.

Every operation is integer-only, deterministic and side-effect free; the
mutation points take `&mut PwmChannel` explicitly.

## 2. Non-goals

- **No hardware access**: no pins, timers, registers, DMA or capture; no FFI.
- **No floating point**: duty is per-mille and every conversion floors.
- **No waveform features**: phase, dead time, complementary outputs,
  dithering and spread-spectrum are not modelled.
- **No servo calibration**: mapping is a plain linear interpolation.
- **No scheduling**: the package computes values; it does not control time.
- In-memory only: no file I/O, no registry integration.

## 3. Data model

```xi
pub type PwmChannel = {
  clock_hz: Int;      // 1..1000000000
  freq_hz: Int;       // 1..clock_hz
  period_ticks: Int;  // clock_hz / freq_hz (floored, >= 1)
  duty_permille: Int; // 0..1000
}
```

Construct channels with `pwm_channel`; hand-built channels with inconsistent
fields are not repaired, and the read-only functions document their behavior
for degenerate input (`period_ticks < 1` reads as 0 in `pwm_actual_freq_hz`,
`clock_hz < 1` reads as 0 in the microsecond conversions).

## 4. Formulas

All divisions are integer division on non-negative operands (floor):

| Quantity | Formula |
|---|---|
| period ticks | `clock_hz / freq_hz` |
| realized frequency | `clock_hz / period_ticks` |
| duty ticks | `period_ticks * duty_permille / 1000` |
| duty from ticks | `ticks * 1000 / period_ticks` |
| period microseconds | `period_ticks * 1000000 / clock_hz` |
| duty microseconds | `duty_ticks * 1000000 / clock_hz` |
| servo duty | `min_permille + (angle - min_deg) * (max_permille - min_permille) / (max_deg - min_deg)` |

The clock guard (1..1,000,000,000) keeps `period_ticks * 1000000` inside
`Int` range; `freq_hz <= clock_hz` keeps `period_ticks >= 1`; and duty is
bounded to 0..1000, so no intermediate can overflow.

Rounding examples pinned by the suite: a 3-tick period with duty 500 has 1
duty tick; duty 999 has 2; a 1-tick period has 0 duty ticks at any duty
below 1000. Converting ticks back to duty is lossy: a 3-tick period with 1
tick becomes duty 333, whose duty ticks are 0 again.

## 5. Validation and error catalog

Validation order is part of the contract.

`pwm_channel`:

| Condition | Exact message |
|---|---|
| `clock_hz < 1` or `clock_hz > 1000000000` | `pwm: bad clock <n>` |
| `freq_hz < 1` | `pwm: bad frequency <n>` |
| `freq_hz > clock_hz` | `pwm: frequency <f> exceeds clock <c>` |
| `duty_permille` outside 0..1000 | `pwm: bad duty <d>` |

`pwm_set_duty`:

| Condition | Exact message |
|---|---|
| `permille` outside 0..1000 | `pwm: bad duty <d>` |

`pwm_set_duty_ticks`:

| Condition | Exact message |
|---|---|
| `ticks < 0` or `ticks > period_ticks` | `pwm: bad duty ticks <t> for period <p>` |

`pwm_servo_duty`:

| Condition | Exact message |
|---|---|
| `min_deg >= max_deg` | `pwm: bad angle range [<min>, <max>]` |
| a per-mille bound outside 0..1000, or `min_permille > max_permille` | `pwm: bad duty range [<min>, <max>]` |
| `angle < min_deg` or `angle > max_deg` | `pwm: angle <a> outside [<min>, <max>]` |

Failed mutating calls leave the channel unchanged. `pwm_servo_channel`
returns the mapping error first, then the channel error.

## 6. API contract

```xi
pub fn pwm_channel(clock_hz: Int, freq_hz: Int, duty_permille: Int) -> Result[PwmChannel, Str]
pub fn pwm_clock_hz(c: &PwmChannel) -> Int
pub fn pwm_freq_hz(c: &PwmChannel) -> Int
pub fn pwm_period_ticks(c: &PwmChannel) -> Int
pub fn pwm_actual_freq_hz(c: &PwmChannel) -> Int
pub fn pwm_duty_permille(c: &PwmChannel) -> Int
pub fn pwm_set_duty(c: &mut PwmChannel, permille: Int) -> Result[Int, Str]
pub fn pwm_duty_ticks(c: &PwmChannel) -> Int
pub fn pwm_set_duty_ticks(c: &mut PwmChannel, ticks: Int) -> Result[Int, Str]
pub fn pwm_period_micros(c: &PwmChannel) -> Int
pub fn pwm_duty_micros(c: &PwmChannel) -> Int
pub fn pwm_servo_duty(angle_deg: Int, min_deg: Int, max_deg: Int, min_permille: Int, max_permille: Int) -> Result[Int, Str]
pub fn pwm_servo_channel(clock_hz: Int, freq_hz: Int, angle_deg: Int, min_deg: Int, max_deg: Int, min_permille: Int, max_permille: Int) -> Result[PwmChannel, Str]
```

`pwm_actual_freq_hz` returns 0 for a hand-built channel with
`period_ticks < 1`; the microsecond conversions return 0 for
`clock_hz < 1`. Complexity: every function is O(1).

## 7. Test matrix

`tests/test_conformance.xi` (module `pwm_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All expected values are hand-computed integers.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | 1 MHz / 1 kHz channel | section 4 |
| t2 | non-dividing frequency | floor + realized frequency |
| t3 | channel validation order | section 5 |
| t4 | set_duty boundaries | section 5 |
| t5 | duty-tick flooring | section 4 |
| t6 | set_duty_ticks bounds | section 5 |
| t7 | lossy ticks -> duty -> ticks | section 4 |
| t8 | microsecond conversions | section 4 |
| t9 | realized frequency | section 4 |
| t10 | accessors | section 6 |
| t11 | servo midpoint | section 4 |
| t12 | servo endpoints and ranges | section 4 |
| t13 | servo validation | section 5 |
| t14 | servo flooring | section 4 |
| t15 | 50 Hz servo channel | sections 4-6 |
| t16 | one-tick period | section 4 |
| t17 | clock guard / no overflow | section 4 |
| t18 | set_duty mutation | section 6 |
| t19 | failed set_duty leaves state | section 5 |
| t20 | servo_channel error propagation | section 5 |

## 8. Known limitations

- The clock is capped at 1,000,000,000 Hz; larger clocks are rejected so
  microsecond math cannot overflow.
- All rounding is floor; duty in per-mille caps resolution at 0.1%.
- No phase, dead time, complementary outputs, dithering, DMA or capture.
- Servo mapping assumes a linear relationship between angle and duty.
- Hand-built channels with inconsistent fields are not validated by the
  read-only functions.
- No scheduling, no concurrency, no persistence.

## 9. Compiler / stdlib notes (v0.62.1)

Free functions only; plain struct values (no `Vec[StructType]`);
`Result` construction confined to the leaf helpers `_ok_channel` /
`_err_channel` / `_ok_int` / `_err_int`; mutation through explicit
`&mut PwmChannel` parameters. The suite deliberately avoids comparing
`Result` values with `==` and routes success checks through a local
`set_is` helper, and every expected number is an integer literal. The suite
is green on v0.62.1 with `program_exit=0`.
