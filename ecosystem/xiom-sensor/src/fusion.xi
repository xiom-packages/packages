module xiom.sensor.fusion

use xiom.math;

pub type FusedPose = {
  x: Float64;
  y: Float64;
  z: Float64;
  roll: Float64;
  pitch: Float64;
  yaw: Float64;
  confidence: Float64;
  timestamp: Int;
}

pub fn fusion_complementary(imu: &IMUReading, gps: &GPSFix, alpha: Float64) -> FusedPose
  requires: alpha >= 0.0
  requires: alpha <= 1.0
{
  var q = imu_compute_orientation(imu);
  var euler = quat_to_euler(&q);

  var gps_valid = gps_is_valid(gps);
  var conf_imu: Float64 = 0.7;
  var conf_gps: Float64 = 0.0;

  if gps_valid {
    conf_gps = 1.0 - gps.hdop / 100.0;
    if conf_gps < 0.0 { conf_gps = 0.0; };
    if conf_gps > 1.0 { conf_gps = 1.0; };
  };

  var conf = alpha * conf_imu + (1.0 - alpha) * conf_gps;

  var x: Float64 = 0.0;
  var y: Float64 = 0.0;
  var z: Float64 = gps.alt;

  if gps_valid {
    x = gps.lat;
    y = gps.lon;
  };

  return FusedPose{
    x: x,
    y: y,
    z: z,
    roll: euler.roll,
    pitch: euler.pitch,
    yaw: euler.yaw,
    confidence: conf,
    timestamp: imu.timestamp,
  };
}

pub fn fusion_weighted(poses: &Vec[FusedPose]) -> FusedPose {
  if poses.len() == 0 {
    return FusedPose{
      x: 0.0, y: 0.0, z: 0.0,
      roll: 0.0, pitch: 0.0, yaw: 0.0,
      confidence: 0.0, timestamp: 0,
    };
  };

  var sum_weight: Float64 = 0.0;
  var wx: Float64 = 0.0;
  var wy: Float64 = 0.0;
  var wz: Float64 = 0.0;
  var wr: Float64 = 0.0;
  var wp: Float64 = 0.0;
  var wyaw: Float64 = 0.0;
  var max_ts: Int = 0;

  var i = 0;
  while i < poses.len() {
    var pose = poses[i];
    var weight = pose.confidence;
    if weight < 0.0 { weight = 0.0; };

    sum_weight = sum_weight + weight;
    wx = wx + pose.x * weight;
    wy = wy + pose.y * weight;
    wz = wz + pose.z * weight;
    wr = wr + pose.roll * weight;
    wp = wp + pose.pitch * weight;
    wyaw = wyaw + pose.yaw * weight;

    if pose.timestamp > max_ts {
      max_ts = pose.timestamp;
    };

    i = i + 1;
  };

  if sum_weight < 0.0000001 {
    return poses[0];
  };

  var avg_conf = sum_weight / (poses.len() as Float64);

  return FusedPose{
    x: wx / sum_weight,
    y: wy / sum_weight,
    z: wz / sum_weight,
    roll: wr / sum_weight,
    pitch: wp / sum_weight,
    yaw: wyaw / sum_weight,
    confidence: avg_conf,
    timestamp: max_ts,
  };
}

pub fn fusion_predict(pose: &FusedPose, velocity: Float64, heading: Float64, dt: Float64) -> FusedPose
  requires: dt >= 0.0
{
  var heading_rad = heading * 0.017453292519943295;
  var dx = velocity * xiom.math.cos(heading_rad) * dt;
  var dy = velocity * xiom.math.sin(heading_rad) * dt;

  var earth_radius: Float64 = 6371000.0;
  var new_lat = pose.x + rad_to_deg(dy / earth_radius);
  var new_lon = pose.y + rad_to_deg(dx / (earth_radius * xiom.math.cos(pose.x * 0.017453292519943295)));

  var conf_decay: Float64 = 0.95;
  if dt > 0.0 {
    conf_decay = 0.95;
  };

  return FusedPose{
    x: new_lat,
    y: new_lon,
    z: pose.z,
    roll: pose.roll,
    pitch: pose.pitch,
    yaw: heading,
    confidence: pose.confidence * conf_decay,
    timestamp: pose.timestamp + (dt as Int),
  };
}

pub fn confidence_from_hdop(hdop: Float64) -> Float64 {
  if hdop <= 0.0 {
    return 0.0;
  };
  var conf: Float64 = 1.0 / hdop;
  if conf > 1.0 {
    conf = 1.0;
  };
  return conf;
}

fn deg_to_rad(deg: Float64) -> Float64 {
  return deg * 0.017453292519943295;
}

fn rad_to_deg(rad: Float64) -> Float64 {
  return rad * 57.29577951308232;
}

fn imu_compute_orientation(reading: &IMUReading) -> Quaternion {
  var ax = reading.accel_x;
  var ay = reading.accel_y;
  var az = reading.accel_z;
  var mx = reading.mag_x;
  var my = reading.mag_y;
  var mz = reading.mag_z;

  var accel_norm = xiom.math.sqrt(ax * ax + ay * ay + az * az);
  if accel_norm < 0.0000001 {
    var q = Quaternion{ w: 1.0, x: 0.0, y: 0.0, z: 0.0 };
    return q;
  };
  ax = ax / accel_norm;
  ay = ay / accel_norm;
  az = az / accel_norm;

  var roll = xiom.math.atan2(ay, az);
  var pitch = xiom.math.atan2(-ax, xiom.math.sqrt(ay * ay + az * az));

  var mag_norm = xiom.math.sqrt(mx * mx + my * my + mz * mz);
  if mag_norm < 0.0000001 {
    return quat_from_euler(roll, pitch, 0.0);
  };
  mx = mx / mag_norm;
  my = my / mag_norm;
  mz = mz / mag_norm;

  var cr = xiom.math.cos(roll);
  var sr = xiom.math.sin(roll);
  var cp = xiom.math.cos(pitch);
  var sp = xiom.math.sin(pitch);

  var mag_x_tilt = mx * cp + my * sp * sr + mz * sp * cr;
  var mag_y_tilt = my * cr - mz * sr;
  var yaw = xiom.math.atan2(-mag_y_tilt, mag_x_tilt);

  return quat_from_euler(roll, pitch, yaw);
}

fn quat_from_euler(roll: Float64, pitch: Float64, yaw: Float64) -> Quaternion {
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

fn quat_to_euler(q: &Quaternion) -> EulerAngles {
  var sinr_cosp: Float64 = 2.0 * (q.w * q.x + q.y * q.z);
  var cosr_cosp: Float64 = 1.0 - 2.0 * (q.x * q.x + q.y * q.y);
  var roll: Float64 = xiom.math.atan2(sinr_cosp, cosr_cosp);

  var sinp: Float64 = 2.0 * (q.w * q.y - q.z * q.x);
  var pitch: Float64 = 0.0;
  if xiom.math.abs(sinp) >= 1.0 {
    if sinp > 0.0 {
      pitch = 1.5707963267948966;
    } else {
      pitch = -1.5707963267948966;
    };
  } else {
    pitch = xiom.math.asin(sinp);
  };

  var siny_cosp: Float64 = 2.0 * (q.w * q.z + q.x * q.y);
  var cosy_cosp: Float64 = 1.0 - 2.0 * (q.y * q.y + q.z * q.z);
  var yaw: Float64 = xiom.math.atan2(siny_cosp, cosy_cosp);

  return EulerAngles{ roll: roll, pitch: pitch, yaw: yaw };
}

fn gps_is_valid(fix: &GPSFix) -> Bool {
  return fix.fix_quality > 0;
}
