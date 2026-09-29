// XIOM -- xiom.pwm: integer PWM channel, duty-cycle and servo math
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no hardware access.
//
// Everything a PWM driver needs to decide before touching a register, as
// exact integer arithmetic:
//   * a channel is (clock_hz, freq_hz, duty_permille) with the derived
//     period_ticks = clock_hz / freq_hz;
//   * duty is expressed in per-mille (0..1000) so no floating point is ever
//     needed; conversions to duty ticks, microseconds and back floor the
//     result, and the rounding rule is documented per function;
//   * servo positioning maps an angle onto a duty range with a linear,
//     floored interpolation.
//
// The package never configures a pin, timer or register: callers capture the
// values and hand them to their platform layer.
//
// Language notes (XIOM v0.61.3): free functions only; Str equality goes
// through xiom.string.compare.str_compare; Ok/Err are constructed only in the
// leaf helpers _ok_channel/_err_channel and _ok_int/_err_int.

module xiom.pwm

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(c) for Result[PwmChannel, Str].
fn _ok_channel(c: PwmChannel) -> Result[PwmChannel, Str] {
  return Ok(c);
}

// Err(m) for Result[PwmChannel, Str].
fn _err_channel(m: Str) -> Result[PwmChannel, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Limits
// --------------------------------------------------

// Duty is expressed in per-mille.
const _PWM_DUTY_MAX: Int = 1000;

// Clock guard: keeps every microsecond conversion inside Int range.
const _PWM_CLOCK_MAX: Int = 1000000000;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One PWM channel: source clock in hertz, target frequency in hertz, the
/// derived period in clock ticks (floor(clock_hz / freq_hz), always >= 1)
/// and the duty cycle in per-mille (0 = always low, 1000 = always high).
/// Construct channels with pwm_channel, which validates every field.
pub type PwmChannel = {
  clock_hz: Int;
  freq_hz: Int;
  period_ticks: Int;
  duty_permille: Int;
}

// --------------------------------------------------
//  Channel construction and accessors
// --------------------------------------------------

/// A PWM channel for a clock and a target frequency.
/// Params: clock_hz - the source clock in hertz (1..1000000000);
/// freq_hz - the PWM frequency in hertz (1..clock_hz);
/// duty_permille - the initial duty in per-mille (0..1000).
/// Returns: Ok(PwmChannel) with period_ticks = clock_hz / freq_hz floored
/// (always >= 1, and 1 when the frequency equals the clock).
/// Error case: Err("pwm: bad clock <n>") for a clock outside
/// 1..1000000000; Err("pwm: bad frequency <n>") for freq < 1;
/// Err("pwm: frequency <f> exceeds clock <c>"); Err("pwm: bad duty <d>") for
/// a duty outside 0..1000. Validation order: clock, frequency,
/// frequency-vs-clock, duty.
/// Complexity: O(1).
pub fn pwm_channel(clock_hz: Int, freq_hz: Int, duty_permille: Int) -> Result[PwmChannel, Str] {
  if clock_hz < 1 || clock_hz > _PWM_CLOCK_MAX {
    return _err_channel("pwm: bad clock " + int_to_string(clock_hz));
  }
  if freq_hz < 1 {
    return _err_channel("pwm: bad frequency " + int_to_string(freq_hz));
  }
  if freq_hz > clock_hz {
    return _err_channel("pwm: frequency " + int_to_string(freq_hz)
      + " exceeds clock " + int_to_string(clock_hz));
  }
  if duty_permille < 0 || duty_permille > _PWM_DUTY_MAX {
    return _err_channel("pwm: bad duty " + int_to_string(duty_permille));
  }
  return _ok_channel(PwmChannel{
    clock_hz: clock_hz;
    freq_hz: freq_hz;
    period_ticks: clock_hz / freq_hz;
    duty_permille: duty_permille;
  });
}

/// Source clock of the channel, in hertz.
/// Params: c - the channel.
/// Returns: clock_hz.
/// Error case: none.
/// Complexity: O(1).
pub fn pwm_clock_hz(c: &PwmChannel) -> Int {
  let v: Int = c.clock_hz;
  return v;
}

/// Target frequency of the channel, in hertz.
/// Params: c - the channel.
/// Returns: freq_hz.
/// Error case: none.
/// Complexity: O(1).
pub fn pwm_freq_hz(c: &PwmChannel) -> Int {
  let v: Int = c.freq_hz;
  return v;
}

/// Period of the channel, in clock ticks.
/// Params: c - the channel.
/// Returns: period_ticks (floor of clock_hz / freq_hz).
/// Error case: none.
/// Complexity: O(1).
pub fn pwm_period_ticks(c: &PwmChannel) -> Int {
  let v: Int = c.period_ticks;
  return v;
}

/// Frequency actually produced by the floored period, in hertz:
/// clock_hz / period_ticks floored, which is never below freq_hz.
/// Params: c - the channel.
/// Returns: the realized frequency.
/// Error case: none.
/// Complexity: O(1).
pub fn pwm_actual_freq_hz(c: &PwmChannel) -> Int {
  let p: Int = c.period_ticks;
  if p < 1 {
    return 0;
  }
  let clk: Int = c.clock_hz;
  return clk / p;
}

/// Current duty of the channel, in per-mille.
/// Params: c - the channel.
/// Returns: duty_permille.
/// Error case: none.
/// Complexity: O(1).
pub fn pwm_duty_permille(c: &PwmChannel) -> Int {
  let v: Int = c.duty_permille;
  return v;
}

// --------------------------------------------------
//  Duty control
// --------------------------------------------------

/// Set the duty in per-mille.
/// Params: c - the channel to mutate; permille - the new duty (0..1000).
/// Returns: Ok(permille) after the channel was updated.
/// Error case: Err("pwm: bad duty <d>") for a duty outside 0..1000; a failed
/// call leaves the channel unchanged.
/// Complexity: O(1).
pub fn pwm_set_duty(c: &mut PwmChannel, permille: Int) -> Result[Int, Str] {
  if permille < 0 || permille > _PWM_DUTY_MAX {
    return _err_int("pwm: bad duty " + int_to_string(permille));
  }
  c.duty_permille = permille;
  return _ok_int(permille);
}

/// High ticks of the current duty: floor(period_ticks * duty / 1000).
/// Params: c - the channel.
/// Returns: the number of clock ticks the output stays high (0..period).
/// Error case: none.
/// Complexity: O(1).
pub fn pwm_duty_ticks(c: &PwmChannel) -> Int {
  let p: Int = c.period_ticks;
  let d: Int = c.duty_permille;
  return p * d / _PWM_DUTY_MAX;
}

/// Set the duty from a high-tick count.
/// Params: c - the channel to mutate; ticks - the high ticks (0..period).
/// Returns: Ok(duty) with the stored per-mille duty, computed as
/// floor(ticks * 1000 / period).
/// Error case: Err("pwm: bad duty ticks <t> for period <p>") when `ticks`
/// is negative or above the period; a failed call leaves the channel
/// unchanged.
/// Complexity: O(1).
pub fn pwm_set_duty_ticks(c: &mut PwmChannel, ticks: Int) -> Result[Int, Str] {
  let p: Int = c.period_ticks;
  if ticks < 0 || ticks > p {
    return _err_int("pwm: bad duty ticks " + int_to_string(ticks)
      + " for period " + int_to_string(p));
  }
  let duty = ticks * _PWM_DUTY_MAX / p;
  c.duty_permille = duty;
  return _ok_int(duty);
}

/// Period of the channel in microseconds: floor(period_ticks * 1000000 /
/// clock_hz).
/// Params: c - the channel.
/// Returns: the period in whole microseconds.
/// Error case: none.
/// Complexity: O(1).
pub fn pwm_period_micros(c: &PwmChannel) -> Int {
  let p: Int = c.period_ticks;
  let clk: Int = c.clock_hz;
  if clk < 1 {
    return 0;
  }
  return p * 1000000 / clk;
}

/// High time of the current duty in microseconds: floor(duty_ticks * 1000000
/// / clock_hz).
/// Params: c - the channel.
/// Returns: the high time in whole microseconds.
/// Error case: none.
/// Complexity: O(1).
pub fn pwm_duty_micros(c: &PwmChannel) -> Int {
  let ticks = pwm_duty_ticks(c);
  let clk: Int = c.clock_hz;
  if clk < 1 {
    return 0;
  }
  return ticks * 1000000 / clk;
}

// --------------------------------------------------
//  Servo mapping
// --------------------------------------------------

/// Map a servo angle onto a duty per-mille with linear, floored
/// interpolation: min_permille + (angle - min_deg) * (max_permille -
/// min_permille) / (max_deg - min_deg).
/// Params: angle_deg - the requested angle; min_deg / max_deg - the angle
/// range (min_deg < max_deg); min_permille / max_permille - the duty range
/// (each 0..1000, min <= max).
/// Returns: Ok(permille) inside the inclusive range.
/// Error case: Err("pwm: bad angle range [<min>, <max>]") when
/// min_deg >= max_deg; Err("pwm: bad duty range [<min>, <max>]") when a
/// per-mille bound is outside 0..1000 or min > max;
/// Err("pwm: angle <a> outside [<min>, <max>]") when the angle is out of
/// range. Validation order: angle range, duty range, angle.
/// Complexity: O(1).
pub fn pwm_servo_duty(angle_deg: Int, min_deg: Int, max_deg: Int, min_permille: Int, max_permille: Int) -> Result[Int, Str] {
  if min_deg >= max_deg {
    return _err_int("pwm: bad angle range [" + int_to_string(min_deg) + ", " + int_to_string(max_deg) + "]");
  }
  if min_permille < 0 || max_permille < 0 || min_permille > _PWM_DUTY_MAX || max_permille > _PWM_DUTY_MAX || min_permille > max_permille {
    return _err_int("pwm: bad duty range [" + int_to_string(min_permille) + ", " + int_to_string(max_permille) + "]");
  }
  if angle_deg < min_deg || angle_deg > max_deg {
    return _err_int("pwm: angle " + int_to_string(angle_deg) + " outside [" + int_to_string(min_deg) + ", " + int_to_string(max_deg) + "]");
  }
  let span = max_permille - min_permille;
  let duty = min_permille + (angle_deg - min_deg) * span / (max_deg - min_deg);
  return _ok_int(duty);
}

/// Convenience: a PWM channel whose duty positions a servo at `angle_deg`.
/// Params: clock_hz / freq_hz - the channel's clock and frequency; the
/// remaining parameters match pwm_servo_duty.
/// Returns: Ok(PwmChannel) with the mapped duty; servo channels usually use
/// a low frequency (for example 50 Hz) so the pulse width maps to per-mille.
/// Error case: whatever pwm_servo_duty or pwm_channel reports, in that
/// order.
/// Complexity: O(1).
pub fn pwm_servo_channel(clock_hz: Int, freq_hz: Int, angle_deg: Int, min_deg: Int, max_deg: Int, min_permille: Int, max_permille: Int) -> Result[PwmChannel, Str] {
  let d = pwm_servo_duty(angle_deg, min_deg, max_deg, min_permille, max_permille);
  match d {
    Ok(permille) => {
      return pwm_channel(clock_hz, freq_hz, permille);
    },
    Err(e) => {
      return _err_channel(e);
    },
  }
  return _err_channel("pwm: bad servo mapping");
}
