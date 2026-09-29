# xiom.pwm

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** integer PWM channel, duty-cycle, timing and servo mapping math;
> no hardware access.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.compare` and
> `xiom.convert`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.pwm` computes everything a PWM driver needs to decide before touching
a register, with exact integer arithmetic and documented rounding:

- **Channel** -- `clock_hz`, `freq_hz`, the derived `period_ticks`
  (`clock_hz / freq_hz`, floored) and a duty in per-mille (0..1000, so no
  floating point is ever needed). `pwm_channel` validates the clock
  (1..1,000,000,000), the frequency (1..clock) and the duty (0..1000) in a
  fixed order with deterministic `Err`s.
- **Duty control** -- `pwm_set_duty` (per-mille), `pwm_duty_ticks`
  (`period * duty / 1000` floored), `pwm_set_duty_ticks` (floored back to
  per-mille), `pwm_period_micros`, `pwm_duty_micros` and
  `pwm_actual_freq_hz` (the frequency the floored period really produces).
- **Servo mapping** -- `pwm_servo_duty` linearly interpolates an angle onto
  a duty range with floored integer math; `pwm_servo_channel` combines the
  mapping with channel construction.

The package never configures a pin, timer or register: callers capture the
values and hand them to their platform layer.

## API

| Function | Returns | Description |
|---|---|---|
| `pwm_channel(clock_hz, freq_hz, duty_permille)` | `Result[PwmChannel, Str]` | Validated channel with floored period. |
| `pwm_clock_hz(c)` / `pwm_freq_hz(c)` / `pwm_period_ticks(c)` / `pwm_duty_permille(c)` | `Int` | Channel fields. |
| `pwm_actual_freq_hz(c)` | `Int` | `clock / period` floored; never below `freq_hz`. |
| `pwm_set_duty(c, permille)` | `Result[Int, Str]` | Set duty 0..1000; `Ok(duty)`. |
| `pwm_duty_ticks(c)` | `Int` | High ticks: `period * duty / 1000` floored. |
| `pwm_set_duty_ticks(c, ticks)` | `Result[Int, Str]` | Set duty from ticks 0..period. |
| `pwm_period_micros(c)` / `pwm_duty_micros(c)` | `Int` | Period / high time in whole microseconds. |
| `pwm_servo_duty(angle, min_deg, max_deg, min_permille, max_permille)` | `Result[Int, Str]` | Linear, floored angle-to-duty mapping. |
| `pwm_servo_channel(clock_hz, freq_hz, angle, min_deg, max_deg, min_permille, max_permille)` | `Result[PwmChannel, Str]` | Servo-positioned channel. |

## Usage

```xi
use xiom.pwm;
use xiom.io;

fn main() -> Int {
  // 1 MHz clock, 1 kHz PWM, 25% duty.
  let r = pwm_channel(1000000, 1000, 250);
  match r {
    Ok(c) => {
      io.println(pwm_period_ticks(&c));   // 1000
      io.println(pwm_duty_ticks(&c));     // 250
      io.println(pwm_duty_micros(&c));    // 250
    },
    Err(e) => { io.println(e); },
  }

  // Standard hobby servo: 50 Hz frame, 0..180 degrees mapped to 50..100.
  let s = pwm_servo_channel(1000000, 50, 90, 0, 180, 50, 100);
  match s {
    Ok(servo) => { io.println(pwm_duty_ticks(&servo)); },  // 1500 of 20000
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.pwm
```

Expected tail: 20 `[PASS]` lines, `xiom.pwm: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- No hardware access: no pin, timer or register configuration and no FFI;
  callers apply the computed values.
- Fixed integer domain: duty is per-mille; the clock is capped at
  1,000,000,000 Hz so every microsecond conversion stays in range.
- Rounding is floor everywhere and documented per function; converting
  duty -> ticks -> duty is lossy (for example a 3-tick period).
- No phase, dead-time, complementary-output, DMA or capture modelling.
- Servo mapping is a plain linear interpolation; no per-servo calibration
  curves.
- A channel is a plain value: no mutable global state, no concurrency.
- In-memory only: no file I/O, no FFI.

See `SPEC.md` for the exact formulas, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
