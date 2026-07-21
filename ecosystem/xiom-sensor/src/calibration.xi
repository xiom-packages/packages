module xiom.sensor.calibration

use xiom.math;

pub type CalibrationData = {
  offset_x: Float64;
  offset_y: Float64;
  offset_z: Float64;
  scale_x: Float64;
  scale_y: Float64;
  scale_z: Float64;
}

pub fn calibration_identity() -> CalibrationData {
  return CalibrationData{
    offset_x: 0.0,
    offset_y: 0.0,
    offset_z: 0.0,
    scale_x: 1.0,
    scale_y: 1.0,
    scale_z: 1.0,
  };
}

pub fn calibration_compute_offset(readings: &Vec[Float64]) -> Float64 {
  if readings.len() == 0 {
    return 0.0;
  };
  var sum: Float64 = 0.0;
  var i = 0;
  while i < readings.len() {
    sum = sum + readings[i];
    i = i + 1;
  };
  return sum / (readings.len() as Float64);
}

pub fn calibration_apply(value: Float64, cal: &CalibrationData, axis: Int) -> Float64
  requires: axis >= 0
  requires: axis <= 2
{
  if axis == 0 {
    return (value - cal.offset_x) * cal.scale_x;
  }
  elif axis == 1 {
    return (value - cal.offset_y) * cal.scale_y;
  }
  elif axis == 2 {
    return (value - cal.offset_z) * cal.scale_z;
  };
  return value;
}

pub fn calibration_from_samples(samples: &Vec[(Float64, Float64, Float64)]) -> CalibrationData {
  if samples.len() == 0 {
    return calibration_identity();
  };

  var x_vals = Vec[Float64].new();
  var y_vals = Vec[Float64].new();
  var z_vals = Vec[Float64].new();

  var i = 0;
  while i < samples.len() {
    var (sx, sy, sz) = samples[i];
    x_vals.push(sx);
    y_vals.push(sy);
    z_vals.push(sz);
    i = i + 1;
  };

  var offset_x = calibration_compute_offset(&x_vals);

  var sum_sq: Float64 = 0.0;
  var j = 0;
  while j < x_vals.len() {
    var diff = x_vals[j] - offset_x;
    sum_sq = sum_sq + diff * diff;
    j = j + 1;
  };
  var scale_x: Float64 = 1.0;
  if sum_sq > 0.0000001 {
    var target_mag: Float64 = 1.0;
    var actual_mag = xiom.math.sqrt(sum_sq / (x_vals.len() as Float64));
    if actual_mag > 0.0000001 {
      scale_x = target_mag / actual_mag;
    };
  };

  var offset_y = calibration_compute_offset(&y_vals);

  sum_sq = 0.0;
  j = 0;
  while j < y_vals.len() {
    var diff = y_vals[j] - offset_y;
    sum_sq = sum_sq + diff * diff;
    j = j + 1;
  };
  var scale_y: Float64 = 1.0;
  if sum_sq > 0.0000001 {
    var target_mag: Float64 = 1.0;
    var actual_mag = xiom.math.sqrt(sum_sq / (y_vals.len() as Float64));
    if actual_mag > 0.0000001 {
      scale_y = target_mag / actual_mag;
    };
  };

  var offset_z = calibration_compute_offset(&z_vals);

  sum_sq = 0.0;
  j = 0;
  while j < z_vals.len() {
    var diff = z_vals[j] - offset_z;
    sum_sq = sum_sq + diff * diff;
    j = j + 1;
  };
  var scale_z: Float64 = 1.0;
  if sum_sq > 0.0000001 {
    var target_mag: Float64 = 1.0;
    var actual_mag = xiom.math.sqrt(sum_sq / (z_vals.len() as Float64));
    if actual_mag > 0.0000001 {
      scale_z = target_mag / actual_mag;
    };
  };

  return CalibrationData{
    offset_x: offset_x,
    offset_y: offset_y,
    offset_z: offset_z,
    scale_x: scale_x,
    scale_y: scale_y,
    scale_z: scale_z,
  };
}
