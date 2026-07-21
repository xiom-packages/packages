module sensor_tests

use xiom.io;
use xiom.sensor.gps;
use xiom.sensor.imu;
use xiom.sensor.fusion;
use xiom.sensor.calibration;

var failed: Int = 0;
var total: Int = 0;

fn check(ok: Bool, name: Str) {
  total = total + 1;
  if ok { io.println("  [PASS] " + name); return; }
  failed = failed + 1;
  io.println("  [FAIL] " + name);
}

fn f64_eq(a: Float64, b: Float64, eps: Float64) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; };
  return diff < eps;
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = "";
  while num > 0 { var d = num % 10; var ds = "";
    if d == 0 { ds = "0"; } elif d == 1 { ds = "1"; } elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; } elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; } elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  return out;
}

// =============================================================================
// GPS
// =============================================================================

fn test_gps_is_valid() {
  var fix = GPSFix{ lat: 60.0, lon: 25.0, alt: 100.0, hdop: 1.0, satellites: 8, fix_quality: 1, timestamp: 1000 };
  var ok = gps_is_valid(&fix);
  check(ok, "gps_is_valid with quality=1 returns true");
}

fn test_gps_is_valid_zero_quality() {
  var fix = GPSFix{ lat: 60.0, lon: 25.0, alt: 100.0, hdop: 1.0, satellites: 0, fix_quality: 0, timestamp: 0 };
  var ok = gps_is_valid(&fix);
  check(!ok, "gps_is_valid with quality=0 returns false");
}

fn test_gps_distance_zero() {
  var a = GeoPoint{ lat: 0.0, lon: 0.0, alt: 0.0 };
  var b = GeoPoint{ lat: 0.0, lon: 0.0, alt: 0.0 };
  var d = gps_distance_m(&a, &b);
  check(f64_eq(d, 0.0, 1.0), "gps_distance_m same point ~0m");
}

fn test_gps_distance_positive() {
  var a = GeoPoint{ lat: 60.1699, lon: 24.9384, alt: 0.0 };
  var b = GeoPoint{ lat: 61.4978, lon: 23.7610, alt: 0.0 };
  var d = gps_distance_m(&a, &b);
  check(d > 150000.0, "gps_distance_m Helsinki-Tampere >150km");
}

fn test_gps_bearing_east() {
  var a = GeoPoint{ lat: 0.0, lon: 0.0, alt: 0.0 };
  var b = GeoPoint{ lat: 0.0, lon: 1.0, alt: 0.0 };
  var bear = gps_bearing_deg(&a, &b);
  check(f64_eq(bear, 90.0, 0.01), "gps_bearing_deg due east ~90");
}

fn test_gps_bearing_north() {
  var a = GeoPoint{ lat: 0.0, lon: 0.0, alt: 0.0 };
  var b = GeoPoint{ lat: 1.0, lon: 0.0, alt: 0.0 };
  var bear = gps_bearing_deg(&a, &b);
  check(f64_eq(bear, 0.0, 0.01), "gps_bearing_deg due north ~0");
}

fn test_gps_destination_north() {
  var origin = GeoPoint{ lat: 60.0, lon: 25.0, alt: 100.0 };
  var dest = gps_destination(&origin, 0.0, 1000.0);
  check(dest.lat > 60.0, "gps_destination north moves lat up");
}

fn test_gps_destination_east() {
  var origin = GeoPoint{ lat: 60.0, lon: 25.0, alt: 100.0 };
  var dest = gps_destination(&origin, 90.0, 1000.0);
  check(dest.lon > 25.0, "gps_destination east moves lon up");
}

fn test_gps_to_utm_helsinki() {
  var (easting, northing, zone) = gps_to_utm(60.0, 25.0);
  check(zone == 35, "gps_to_utm Helsinki zone=35");
}

fn test_gps_to_utm_equator() {
  var (easting, northing, zone) = gps_to_utm(0.0, 0.0);
  check(zone == 31, "gps_to_utm 0,0 zone=31");
}

fn test_utm_to_gps_roundtrip() {
  var (lat, lon) = utm_to_gps(500000.0, 4649776.0, 31, false);
  check(f64_eq(lat, 42.0, 1.0), "utm_to_gps zone 31 reverse ~42 lat");
}

// =============================================================================
// IMU
// =============================================================================

fn test_quat_identity() {
  var q = quat_identity();
  check(f64_eq(q.w, 1.0, 0.001) && f64_eq(q.x, 0.0, 0.001), "quat_identity w=1 x=0");
}

fn test_quat_normalize_identity() {
  var q = quat_identity();
  var n = quat_normalize(&q);
  check(f64_eq(n.w, 1.0, 0.001), "quat_normalize identity stays identity");
}

fn test_quat_normalize_nonunit() {
  var raw = Quaternion{ w: 2.0, x: 2.0, y: 2.0, z: 2.0 };
  var n = quat_normalize(&raw);
  var mag = n.w * n.w + n.x * n.x + n.y * n.y + n.z * n.z;
  check(f64_eq(mag, 1.0, 0.001), "quat_normalize non-unit -> unit magnitude");
}

fn test_quat_multiply_identity() {
  var a = Quaternion{ w: 1.0, x: 0.0, y: 0.0, z: 0.0 };
  var b = Quaternion{ w: 0.0, x: 1.0, y: 0.0, z: 0.0 };
  var c = quat_multiply(&a, &b);
  check(f64_eq(c.x, 1.0, 0.001), "quat_multiply identity * (0,1,0,0) preserves x");
}

fn test_quat_conjugate() {
  var q = Quaternion{ w: 1.0, x: 2.0, y: 3.0, z: 4.0 };
  var c = quat_conjugate(&q);
  check(f64_eq(c.w, 1.0, 0.001) && f64_eq(c.x, -2.0, 0.001), "quat_conjugate flips vector part");
}

fn test_euler_to_quat_zero() {
  var e = euler_to_quat(0.0, 0.0, 0.0);
  check(f64_eq(e.w, 1.0, 0.001), "euler_to_quat zero -> identity");
}

fn test_quat_to_euler_identity() {
  var q = quat_identity();
  var e = quat_to_euler(&q);
  check(f64_eq(e.roll, 0.0, 0.01) && f64_eq(e.pitch, 0.0, 0.01) && f64_eq(e.yaw, 0.0, 0.01), "quat_to_euler identity -> zero euler");
}

fn test_quat_euler_roundtrip() {
  var q1 = euler_to_quat(0.0, 0.0, 1.5707963267948966);
  var e = quat_to_euler(&q1);
  check(f64_eq(e.yaw, 1.5707963267948966, 0.01), "quat->euler roundtrip yaw=pi/2");
}

fn test_quat_rotate_vector() {
  var q = quat_identity();
  var (rx, ry, rz) = quat_rotate_vector(&q, 1.0, 0.0, 0.0);
  check(f64_eq(rx, 1.0, 0.001), "quat_rotate_vector identity preserves vector");
}

fn test_imu_reading_new() {
  var r = imu_reading_new();
  check(r.accel_x == 0.0 && r.timestamp == 0, "imu_reading_new zeroed");
}

fn test_imu_compute_orientation_flat() {
  var r = IMUReading{ accel_x: 0.0, accel_y: 0.0, accel_z: 1.0,
    gyro_x: 0.0, gyro_y: 0.0, gyro_z: 0.0,
    mag_x: 1.0, mag_y: 0.0, mag_z: 0.0, timestamp: 0 };
  var q = imu_compute_orientation(&r);
  check(f64_eq(q.w, 1.0, 0.01), "imu_compute_orientation flat -> identity");
}

// =============================================================================
// Fusion
// =============================================================================

fn test_fusion_complementary_valid() {
  var imu = IMUReading{ accel_x: 0.0, accel_y: 0.0, accel_z: 1.0,
    gyro_x: 0.0, gyro_y: 0.0, gyro_z: 0.0,
    mag_x: 1.0, mag_y: 0.0, mag_z: 0.0, timestamp: 100 };
  var gps = GPSFix{ lat: 60.0, lon: 25.0, alt: 100.0, hdop: 1.0, satellites: 8, fix_quality: 1, timestamp: 100 };
  var pose = fusion_complementary(&imu, &gps, 0.5);
  check(pose.confidence > 0.0, "fusion_complementary confidence > 0");
}

fn test_fusion_complementary_bad_gps() {
  var imu = IMUReading{ accel_x: 0.0, accel_y: 0.0, accel_z: 1.0,
    gyro_x: 0.0, gyro_y: 0.0, gyro_z: 0.0,
    mag_x: 1.0, mag_y: 0.0, mag_z: 0.0, timestamp: 100 };
  var gps = GPSFix{ lat: 60.0, lon: 25.0, alt: 100.0, hdop: 1.0, satellites: 0, fix_quality: 0, timestamp: 100 };
  var pose = fusion_complementary(&imu, &gps, 1.0);
  check(f64_eq(pose.confidence, 0.7, 0.001), "fusion_complementary alpha=1 ignores bad gps");
}

fn test_fusion_weighted_empty() {
  var poses = Vec[FusedPose].new();
  var w = fusion_weighted(&poses);
  check(w.timestamp == 0, "fusion_weighted empty -> zero timestamp");
}

fn test_fusion_weighted_confident() {
  var poses = Vec[FusedPose].new();
  var p1 = FusedPose{ x: 60.0, y: 25.0, z: 100.0, roll: 0.0, pitch: 0.0, yaw: 0.0, confidence: 1.0, timestamp: 100 };
  var p2 = FusedPose{ x: 60.0, y: 25.0, z: 100.0, roll: 0.0, pitch: 0.0, yaw: 0.0, confidence: 0.0, timestamp: 200 };
  poses.push(p1); poses.push(p2);
  var w = fusion_weighted(&poses);
  check(f64_eq(w.x, 60.0, 0.001), "fusion_weighted confident-only passes");
}

fn test_fusion_predict_decay() {
  var pose = FusedPose{ x: 60.0, y: 25.0, z: 100.0, roll: 0.0, pitch: 0.0, yaw: 0.0, confidence: 1.0, timestamp: 100 };
  var pred = fusion_predict(&pose, 0.0, 0.0, 1.0);
  check(pred.confidence < 1.0, "fusion_predict decays confidence");
}

fn test_confidence_from_hdop_one() {
  var c = confidence_from_hdop(1.0);
  check(f64_eq(c, 1.0, 0.001), "confidence_from_hdop 1.0 -> 1.0");
}

fn test_confidence_from_hdop_ten() {
  var c = confidence_from_hdop(10.0);
  check(f64_eq(c, 0.1, 0.001), "confidence_from_hdop 10.0 -> 0.1");
}

fn test_confidence_from_hdop_zero() {
  var c = confidence_from_hdop(0.0);
  check(f64_eq(c, 0.0, 0.001), "confidence_from_hdop 0.0 -> 0.0");
}

// =============================================================================
// Calibration
// =============================================================================

fn test_calibration_identity() {
  var cal = calibration_identity();
  check(f64_eq(cal.offset_x, 0.0, 0.001) && f64_eq(cal.scale_x, 1.0, 0.001), "calibration_identity offset=0 scale=1");
}

fn test_calibration_compute_offset() {
  var data = Vec[Float64].new();
  data.push(1.0); data.push(2.0); data.push(3.0);
  var off = calibration_compute_offset(&data);
  check(f64_eq(off, 2.0, 0.001), "calibration_compute_offset [1,2,3] -> 2.0");
}

fn test_calibration_compute_offset_empty() {
  var data = Vec[Float64].new();
  var off = calibration_compute_offset(&data);
  check(f64_eq(off, 0.0, 0.001), "calibration_compute_offset empty -> 0.0");
}

fn test_calibration_apply_axis0() {
  var cal = CalibrationData{ offset_x: 1.0, offset_y: 2.0, offset_z: 3.0, scale_x: 2.0, scale_y: 1.0, scale_z: 1.0 };
  var v = calibration_apply(10.0, &cal, 0);
  check(f64_eq(v, 18.0, 0.001), "calibration_apply axis 0: (10-1)*2=18");
}

fn test_calibration_apply_bad_axis() {
  var cal = CalibrationData{ offset_x: 1.0, offset_y: 2.0, offset_z: 3.0, scale_x: 2.0, scale_y: 1.0, scale_z: 1.0 };
  var v = calibration_apply(10.0, &cal, 3);
  check(f64_eq(v, 10.0, 0.001), "calibration_apply axis=3 returns value unchanged");
}

fn test_calibration_apply_identity_axis1() {
  var cal = calibration_identity();
  var v = calibration_apply(5.0, &cal, 1);
  check(f64_eq(v, 3.0, 0.001), "calibration_apply identity axis 1: (5-2)*1=3");
}

fn test_calibration_from_samples() {
  var samples = Vec[(Float64, Float64, Float64)].new();
  samples.push((1.0, 2.0, 3.0)); samples.push((2.0, 4.0, 6.0)); samples.push((3.0, 6.0, 9.0));
  var cal = calibration_from_samples(&samples);
  check(f64_eq(cal.offset_x, 2.0, 0.001), "calibration_from_samples x offset=2");
}

fn test_calibration_from_samples_empty() {
  var samples = Vec[(Float64, Float64, Float64)].new();
  var cal = calibration_from_samples(&samples);
  var id = calibration_identity();
  check(f64_eq(cal.offset_x, id.offset_x, 0.001) && f64_eq(cal.scale_x, id.scale_x, 0.001), "calibration_from_samples empty -> identity");
}

// =============================================================================
// Main runner
// =============================================================================

fn main() -> Int {
  io.println("=== XIOM Sensor Conformance ===");
  failed = 0; total = 0;

  test_gps_is_valid();
  test_gps_is_valid_zero_quality();
  test_gps_distance_zero();
  test_gps_distance_positive();
  test_gps_bearing_east();
  test_gps_bearing_north();
  test_gps_destination_north();
  test_gps_destination_east();
  test_gps_to_utm_helsinki();
  test_gps_to_utm_equator();
  test_utm_to_gps_roundtrip();

  test_quat_identity();
  test_quat_normalize_identity();
  test_quat_normalize_nonunit();
  test_quat_multiply_identity();
  test_quat_conjugate();
  test_euler_to_quat_zero();
  test_quat_to_euler_identity();
  test_quat_euler_roundtrip();
  test_quat_rotate_vector();
  test_imu_reading_new();
  test_imu_compute_orientation_flat();

  test_fusion_complementary_valid();
  test_fusion_complementary_bad_gps();
  test_fusion_weighted_empty();
  test_fusion_weighted_confident();
  test_fusion_predict_decay();
  test_confidence_from_hdop_one();
  test_confidence_from_hdop_ten();
  test_confidence_from_hdop_zero();

  test_calibration_identity();
  test_calibration_compute_offset();
  test_calibration_compute_offset_empty();
  test_calibration_apply_axis0();
  test_calibration_apply_bad_axis();
  test_calibration_apply_identity_axis1();
  test_calibration_from_samples();
  test_calibration_from_samples_empty();

  var passed = total - failed;
  io.println("");
  io.println("XIOM Sensor: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
