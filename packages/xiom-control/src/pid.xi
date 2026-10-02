module xiom.control.pid

pub type PIDController = {
  kp: Float64;
  ki: Float64;
  kd: Float64;
  setpoint: Float64;
  integral: Float64;
  prev_error: Float64;
  integral_limit: Float64;
  output_min: Float64;
  output_max: Float64;
  invariant: output_min < output_max;
  invariant: integral_limit > 0.0;
}

pub fn pid_new(kp: Float64, ki: Float64, kd: Float64) -> PIDController
  requires: kp > 0.0;
  requires: ki >= 0.0;
  requires: kd >= 0.0;
  ensures: result.kp == kp && result.ki == ki && result.kd == kd;
  ensures: result.integral == 0.0 && result.prev_error == 0.0;
  ensures: result.integral_limit > 0.0;
  ensures: result.output_min < result.output_max;
{
  return PIDController{
    kp: kp,
    ki: ki,
    kd: kd,
    setpoint: 0.0,
    integral: 0.0,
    prev_error: 0.0,
    integral_limit: 1000.0,
    output_min: -1000.0,
    output_max: 1000.0,
  };
}

pub fn pid_set_limits(ctrl: &mut PIDController, min: Float64, max: Float64)
  requires: min < max;
  ensures: ctrl.output_min == min && ctrl.output_max == max;
{
  ctrl.output_min = min;
  ctrl.output_max = max;
}

pub fn pid_set_integral_limit(ctrl: &mut PIDController, limit: Float64)
  requires: limit > 0.0;
  ensures: ctrl.integral_limit == limit;
{
  ctrl.integral_limit = limit;
}

pub fn pid_set_setpoint(ctrl: &mut PIDController, sp: Float64)
  ensures: ctrl.setpoint == sp;
{
  ctrl.setpoint = sp;
}

pub fn pid_compute(ctrl: &mut PIDController, measurement: Float64, dt: Float64) -> Float64
  requires: dt > 0.0;
  ensures: ctrl.integral >= -ctrl.integral_limit && ctrl.integral <= ctrl.integral_limit;
  ensures: result >= ctrl.output_min && result <= ctrl.output_max;
{
  var error = ctrl.setpoint - measurement;

  ctrl.integral = ctrl.integral + error * dt;
  if ctrl.integral > ctrl.integral_limit {
    ctrl.integral = ctrl.integral_limit;
  };
  if ctrl.integral < -ctrl.integral_limit {
    ctrl.integral = -ctrl.integral_limit;
  };

  var derivative: Float64 = 0.0;
  if dt > 0.0 {
    derivative = (error - ctrl.prev_error) / dt;
  };

  ctrl.prev_error = error;

  var output = ctrl.kp * error + ctrl.ki * ctrl.integral + ctrl.kd * derivative;

  if output > ctrl.output_max {
    output = ctrl.output_max;
  };
  if output < ctrl.output_min {
    output = ctrl.output_min;
  };

  return output;
}

pub fn pid_reset(ctrl: &mut PIDController)
  ensures: ctrl.integral == 0.0 && ctrl.prev_error == 0.0;
{
  ctrl.integral = 0.0;
  ctrl.prev_error = 0.0;
}

pub fn pid_get_error(ctrl: &PIDController) -> Float64
  ensures: result == ctrl.setpoint - ctrl.prev_error;
{
  return ctrl.setpoint - ctrl.prev_error;
}
