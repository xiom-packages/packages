module xiom.sensor.imu

use xiom.math;

pub type IMUReading = {
  accel_x: Float64;
  accel_y: Float64;
  accel_z: Float64;
  gyro_x: Float64;
  gyro_y: Float64;
  gyro_z: Float64;
  mag_x: Float64;
  mag_y: Float64;
  mag_z: Float64;
  timestamp: Int;
}

pub type Quaternion = {
  w: Float64;
  x: Float64;
  y: Float64;
  z: Float64;
}

pub type EulerAngles = {
  roll: Float64;
  pitch: Float64;
  yaw: Float64;
}

pub fn imu_reading_new() -> IMUReading {
  return IMUReading{
    accel_x: 0.0, accel_y: 0.0, accel_z: 0.0,
    gyro_x: 0.0, gyro_y: 0.0, gyro_z: 0.0,
    mag_x: 0.0, mag_y: 0.0, mag_z: 0.0,
    timestamp: 0,
  };
}

pub fn quat_identity() -> Quaternion {
  return Quaternion{ w: 1.0, x: 0.0, y: 0.0, z: 0.0 };
}

pub fn quat_normalize(q: &Quaternion) -> Quaternion {
  var mag = xiom.math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
  if mag < 0.0000001 {
    return quat_identity();
  };
  return Quaternion{
    w: q.w / mag,
    x: q.x / mag,
    y: q.y / mag,
    z: q.z / mag,
  };
}

pub fn quat_conjugate(q: &Quaternion) -> Quaternion {
  return Quaternion{ w: q.w, x: -q.x, y: -q.y, z: -q.z };
}

pub fn quat_multiply(a: &Quaternion, b: &Quaternion) -> Quaternion {
  return Quaternion{
    w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
  };
}

pub fn quat_from_euler(roll: Float64, pitch: Float64, yaw: Float64) -> Quaternion {
  return euler_to_quat(roll, pitch, yaw);
}

pub fn euler_to_quat(roll: Float64, pitch: Float64, yaw: Float64) -> Quaternion {
  var cy = xiom.math.cos(yaw * 0.5);
  var sy = xiom.math.sin(yaw * 0.5);
  var cp = xiom.math.cos(pitch * 0.5);
  var sp = xiom.math.sin(pitch * 0.5);
  var cr = xiom.math.cos(roll * 0.5);
  var sr = xiom.math.sin(roll * 0.5);

  return Quaternion{
    w: cr * cp * cy + sr * sp * sy,
    x: sr * cp * cy - cr * sp * sy,
    y: cr * sp * cy + sr * cp * sy,
    z: cr * cp * sy - sr * sp * cy,
  };
}

pub fn quat_to_euler(q: &Quaternion) -> EulerAngles {
  var sinr_cosp: Float64 = 2.0 * (q.w * q.x + q.y * q.z);
  var cosr_cosp: Float64 = 1.0 - 2.0 * (q.x * q.x + q.y * q.y);
  var roll: Float64 = xiom.math.atan2(sinr_cosp, cosr_cosp);

  var sinp_holder = Quaternion{ w: 2.0 * (q.w * q.y - q.z * q.x), x: 0.0, y: 0.0, z: 0.0 };
  var pitch: Float64 = 0.0;
  if xiom.math.abs_float(sinp_holder.w) >= 1.0 {
    if sinp_holder.w > 0.0 {
      pitch = 1.5707963267948966;
    } else {
      pitch = -1.5707963267948966;
    };
  } else {
    pitch = xiom.math.asin(sinp_holder.w);
  };

  var siny_cosp: Float64 = 2.0 * (q.w * q.z + q.x * q.y);
  var cosy_cosp: Float64 = 1.0 - 2.0 * (q.y * q.y + q.z * q.z);
  var yaw: Float64 = xiom.math.atan2(siny_cosp, cosy_cosp);

  return EulerAngles{ roll: roll, pitch: pitch, yaw: yaw };
}

pub fn quat_rotate_vector(q: &Quaternion, vx: Float64, vy: Float64, vz: Float64) -> (Float64, Float64, Float64) {
  var qv = Quaternion{ w: 0.0, x: vx, y: vy, z: vz };
  var q_conj = quat_conjugate(q);
  var q_mul = quat_multiply(q, &qv);
  var q_rot = quat_multiply(&q_mul, &q_conj);
  return (q_rot.x, q_rot.y, q_rot.z);
}

pub fn imu_compute_orientation(reading: &IMUReading) -> Quaternion {
  var accel_norm = xiom.math.sqrt(reading.accel_x * reading.accel_x + reading.accel_y * reading.accel_y + reading.accel_z * reading.accel_z);
  if accel_norm < 0.0000001 {
    return quat_identity();
  };

  var accel = Quaternion{
    w: 0.0,
    x: reading.accel_x / accel_norm,
    y: reading.accel_y / accel_norm,
    z: reading.accel_z / accel_norm,
  };

  var angles = EulerAngles{
    roll: xiom.math.atan2(accel.y, accel.z),
    pitch: xiom.math.atan2(-accel.x, xiom.math.sqrt(accel.y * accel.y + accel.z * accel.z)),
    yaw: 0.0,
  };

  var mag_norm = xiom.math.sqrt(reading.mag_x * reading.mag_x + reading.mag_y * reading.mag_y + reading.mag_z * reading.mag_z);
  if mag_norm < 0.0000001 {
    return quat_from_euler(angles.roll, angles.pitch, 0.0);
  };

  var mag = Quaternion{
    w: 0.0,
    x: reading.mag_x / mag_norm,
    y: reading.mag_y / mag_norm,
    z: reading.mag_z / mag_norm,
  };

  var cr = xiom.math.cos(angles.roll);
  var sr = xiom.math.sin(angles.roll);
  var cp = xiom.math.cos(angles.pitch);
  var sp = xiom.math.sin(angles.pitch);

  var mag_x_tilt = mag.x * cp + mag.y * sp * sr + mag.z * sp * cr;
  var mag_y_tilt = mag.y * cr - mag.z * sr;
  var yaw = xiom.math.atan2(-mag_y_tilt, mag_x_tilt);

  return quat_from_euler(angles.roll, angles.pitch, yaw);
}
