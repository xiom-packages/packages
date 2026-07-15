module xiom.sensor.fusion

use xiom.math;
use xiom.sensor.imu;
use xiom.sensor.gps;

type FloatHolder = { v: Float64; }

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

    var ts_snap = pose.timestamp;
    if ts_snap > max_ts {
      max_ts = ts_snap;
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
  var hr = FloatHolder{ v: heading * 0.017453292519943295 };
  var dx = velocity * xiom.math.cos(hr.v) * dt;
  var dy = velocity * xiom.math.sin(hr.v) * dt;

  var earth_radius: Float64 = 6371000.0;
  var lat_rad = pose.x * 0.017453292519943295;
  var new_lat = pose.x + (dy / earth_radius) * 57.29577951308232;
  var new_lon = pose.y + (dx / (earth_radius * xiom.math.cos(lat_rad))) * 57.29577951308232;

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
