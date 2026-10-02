module xiom.control.filter

use xiom.math;

pub type LowPassFilter = {
  alpha: Float64;
  prev_output: Float64;
  initialized: Bool;
  invariant: alpha >= 0.0 && alpha <= 1.0;
}

pub fn lpf_new(cutoff_freq: Float64, sample_rate: Float64) -> LowPassFilter
  requires: cutoff_freq > 0.0;
  requires: sample_rate > 0.0;
  ensures: result.alpha >= 0.0 && result.alpha <= 1.0;
  ensures: result.prev_output == 0.0 && result.initialized == false;
{
  var dt: Float64 = 1.0 / sample_rate;
  var rc: Float64 = 1.0 / (2.0 * 3.14159265358979323846 * cutoff_freq);
  var alpha: Float64 = dt / (rc + dt);
  return LowPassFilter{
    alpha: alpha,
    prev_output: 0.0,
    initialized: false,
  };
}

pub fn lpf_compute(filt: &mut LowPassFilter, input: Float64) -> Float64
  ensures: filt.initialized == true;
  ensures: filt.prev_output == result;
{
  if !filt.initialized {
    filt.prev_output = input;
    filt.initialized = true;
    return input;
  };
  filt.prev_output = filt.alpha * input + (1.0 - filt.alpha) * filt.prev_output;
  return filt.prev_output;
}

pub fn lpf_reset(filt: &mut LowPassFilter)
  ensures: filt.prev_output == 0.0 && filt.initialized == false;
{
  filt.prev_output = 0.0;
  filt.initialized = false;
}

pub type MovingAverage = {
  window: Vec[Float64];
  window_size: Int;
  index: Int;
  sum: Float64;
  count: Int;
  invariant: window_size > 0;
}

pub fn ma_new(window_size: Int) -> MovingAverage
  requires: window_size > 0;
  ensures: result.window_size == window_size && result.count == 0 && result.index == 0;
  ensures: result.sum == 0.0 && result.window.len() == window_size;
{
  var window = Vec[Float64].new();
  var i = 0;
  while i < window_size {
    window.push(0.0);
    i = i + 1;
  };
  return MovingAverage{
    window: window,
    window_size: window_size,
    index: 0,
    sum: 0.0,
    count: 0,
  };
}

pub fn ma_compute(ma: &mut MovingAverage, input: Float64) -> Float64
  requires: ma.window_size > 0;
  ensures: ma.count <= ma.window_size;
  ensures: ma.index >= 0 && ma.index < ma.window_size;
{
  if ma.count < ma.window_size {
    ma.sum = ma.sum + input;
    ma.window[ma.count] = input;
    ma.count = ma.count + 1;
    return ma.sum / (ma.count as Float64);
  };

  var old_val = ma.window[ma.index];
  ma.sum = ma.sum - old_val + input;
  ma.window[ma.index] = input;
  ma.index = (ma.index + 1) % ma.window_size;
  return ma.sum / (ma.window_size as Float64);
}

pub type KalmanFilter1D = {
  q: Float64;
  r: Float64;
  x: Float64;
  p: Float64;
  k: Float64;
  initialized: Bool;
  invariant: q > 0.0 && r > 0.0;
}

pub fn kalman_new(process_noise: Float64, measurement_noise: Float64) -> KalmanFilter1D
  requires: process_noise > 0.0;
  requires: measurement_noise > 0.0;
  ensures: result.q == process_noise && result.r == measurement_noise;
  ensures: result.p == 1.0 && result.k == 0.0 && result.initialized == false;
{
  return KalmanFilter1D{
    q: process_noise,
    r: measurement_noise,
    x: 0.0,
    p: 1.0,
    k: 0.0,
    initialized: false,
  };
}

pub fn kalman_compute(kf: &mut KalmanFilter1D, measurement: Float64) -> Float64
  ensures: kf.initialized == true;
  ensures: kf.k >= 0.0 && kf.k <= 1.0;
{
  if !kf.initialized {
    kf.x = measurement;
    kf.p = 1.0;
    kf.initialized = true;
    return kf.x;
  };

  kf.p = kf.p + kf.q;
  kf.k = kf.p / (kf.p + kf.r);
  kf.x = kf.x + kf.k * (measurement - kf.x);
  kf.p = (1.0 - kf.k) * kf.p;
  return kf.x;
}
