module xiom.sensor.gps

use xiom.math;

type F64 = { v: Float64; }

pub type GPSFix = {
  lat: Float64;
  lon: Float64;
  alt: Float64;
  hdop: Float64;
  satellites: Int;
  fix_quality: Int;
  timestamp: Int;
}

pub type GeoPoint = {
  lat: Float64;
  lon: Float64;
  alt: Float64;
}

fn deg_to_rad(deg: Float64) -> Float64 {
  return deg * 0.017453292519943295;
}

fn rad_to_deg(rad: Float64) -> Float64 {
  return rad * 57.29577951308232;
}

pub fn gps_is_valid(fix: &GPSFix) -> Bool {
  return fix.fix_quality > 0;
}

pub fn gps_distance_m(a: &GeoPoint, b: &GeoPoint) -> Float64 {
  var earth_radius: Float64 = 6371000.0;
  var dlat = deg_to_rad(b.lat - a.lat);
  var dlon = deg_to_rad(b.lon - a.lon);
  var lat1 = deg_to_rad(a.lat);
  var lat2 = deg_to_rad(b.lat);

  var a_v = F64{
    v: xiom.math.sin(dlat / 2.0) * xiom.math.sin(dlat / 2.0) +
       xiom.math.cos(lat1) * xiom.math.cos(lat2) *
       xiom.math.sin(dlon / 2.0) * xiom.math.sin(dlon / 2.0)
  };
  var c = 2.0 * xiom.math.atan2(xiom.math.sqrt(a_v.v), xiom.math.sqrt(1.0 - a_v.v));

  return earth_radius * c;
}

pub fn gps_bearing_deg(a: &GeoPoint, b: &GeoPoint) -> Float64 {
  var lat1_v = F64{ v: deg_to_rad(a.lat) };
  var lat2_v = F64{ v: deg_to_rad(b.lat) };
  var dlon_v = F64{ v: deg_to_rad(b.lon - a.lon) };

  var y = xiom.math.sin(dlon_v.v) * xiom.math.cos(lat2_v.v);
  var x = xiom.math.cos(lat1_v.v) * xiom.math.sin(lat2_v.v) -
          xiom.math.sin(lat1_v.v) * xiom.math.cos(lat2_v.v) * xiom.math.cos(dlon_v.v);

  var bearing = rad_to_deg(xiom.math.atan2(y, x));
  if bearing < 0.0 {
    bearing = bearing + 360.0;
  };
  return bearing;
}

pub fn gps_destination(point: &GeoPoint, bearing_deg: Float64, distance_m: Float64) -> GeoPoint
  requires: distance_m >= 0.0
{
  var earth_radius: Float64 = 6371000.0;
  var brng_v = F64{ v: deg_to_rad(bearing_deg) };
  var lat1_v = F64{ v: deg_to_rad(point.lat) };
  var lon1_v = F64{ v: deg_to_rad(point.lon) };

  var angular_dist_v = F64{ v: distance_m / earth_radius };

  var lat2_v = F64{
    v: xiom.math.asin(
      xiom.math.sin(lat1_v.v) * xiom.math.cos(angular_dist_v.v) +
      xiom.math.cos(lat1_v.v) * xiom.math.sin(angular_dist_v.v) * xiom.math.cos(brng_v.v)
    )
  };

  var lon2 = lon1_v.v + xiom.math.atan2(
    xiom.math.sin(brng_v.v) * xiom.math.sin(angular_dist_v.v) * xiom.math.cos(lat1_v.v),
    xiom.math.cos(angular_dist_v.v) - xiom.math.sin(lat1_v.v) * xiom.math.sin(lat2_v.v)
  );

  return GeoPoint{
    lat: rad_to_deg(lat2_v.v),
    lon: rad_to_deg(lon2),
    alt: point.alt,
  };
}

pub fn gps_to_utm(lat: Float64, lon: Float64) -> (Float64, Float64, Int)
  requires: lat >= -90.0
  requires: lat <= 90.0
  requires: lon >= -180.0
  requires: lon <= 180.0
{
  var zone: Int = ((lon + 180.0) / 6.0) as Int + 1;
  if lat >= 56.0 && lat < 64.0 && lon >= 3.0 && lon < 12.0 {
    zone = 32;
  };
  if lat >= 72.0 && lat < 84.0 {
    if lon >= 0.0 && lon < 9.0 {
      zone = 31;
    } elif lon >= 9.0 && lon < 21.0 {
      zone = 33;
    } elif lon >= 21.0 && lon < 33.0 {
      zone = 35;
    } elif lon >= 33.0 && lon < 42.0 {
      zone = 37;
    };
  };

  var a: Float64 = 6378137.0;
  var f: Float64 = 1.0 / 298.257223563;
  var k0: Float64 = 0.9996;

  var lat_rad_v = F64{ v: deg_to_rad(lat) };
  var lon_rad = deg_to_rad(lon);

  var lon_origin = deg_to_rad(((zone as Float64) - 1.0) * 6.0 - 180.0 + 3.0);

  var ecc_sq = f * (2.0 - f);
  var n = f / (2.0 - f);
  var n2 = n * n;
  var n3 = n2 * n;
  var n4 = n3 * n;

  var sin_lat = xiom.math.sin(lat_rad_v.v);
  var cos_lat = xiom.math.cos(lat_rad_v.v);
  var tan_lat = xiom.math.tan(lat_rad_v.v);

  var t = tan_lat * tan_lat;
  var c = ecc_sq / (1.0 - ecc_sq) * cos_lat * cos_lat;

  var A = (lon_rad - lon_origin) * cos_lat;
  var A2 = A * A;
  var A3 = A2 * A;
  var A4 = A3 * A;
  var A5 = A4 * A;
  var A6 = A5 * A;

  var s = (1.0 - ecc_sq / 4.0 - 3.0 * ecc_sq * ecc_sq / 64.0 -
           5.0 * ecc_sq * ecc_sq * ecc_sq / 256.0) * lat_rad_v.v -
          (3.0 * ecc_sq / 8.0 + 3.0 * ecc_sq * ecc_sq / 32.0 +
           45.0 * ecc_sq * ecc_sq * ecc_sq / 1024.0) * xiom.math.sin(2.0 * lat_rad_v.v) +
          (15.0 * ecc_sq * ecc_sq / 256.0 +
           45.0 * ecc_sq * ecc_sq * ecc_sq / 1024.0) * xiom.math.sin(4.0 * lat_rad_v.v) -
          (35.0 * ecc_sq * ecc_sq * ecc_sq / 3072.0) * xiom.math.sin(6.0 * lat_rad_v.v);
  s = a * s * k0;

  var term1 = A - t * A3 / 6.0 - (8.0 - t + 8.0 * c) * t * A5 / 120.0;
  var easting_base_v = F64{
    v: a * k0 * term1 * (1.0 + A2 / 6.0 * (1.0 - t + c) +
       A4 / 120.0 * (5.0 - 18.0 * t + t * t + 72.0 * c - 58.0 * n))
  };
  var easting = easting_base_v.v + 500000.0;

  var term2 = A2 / 2.0 + (5.0 - t + 9.0 * c + 4.0 * c * c) * A4 / 24.0 +
              (61.0 - 58.0 * t + t * t + 600.0 * c - 330.0 * n) * A6 / 720.0;
  var northing_base_v = F64{ v: s + a * k0 * tan_lat * term2 };
  var northing = northing_base_v.v;
  if lat < 0.0 {
    northing = northing_base_v.v + 10000000.0;
  };

  return (easting, northing, zone);
}

pub fn utm_to_gps(easting: Float64, northing: Float64, zone: Int, southern: Bool) -> (Float64, Float64)
  requires: zone >= 1
  requires: zone <= 60
{
  var a: Float64 = 6378137.0;
  var f: Float64 = 1.0 / 298.257223563;
  var k0: Float64 = 0.9996;

  var ecc_sq = f * (2.0 - f);
  var e1 = (1.0 - xiom.math.sqrt(1.0 - ecc_sq)) / (1.0 + xiom.math.sqrt(1.0 - ecc_sq));

  var ev = F64{ v: easting };
  var easting_adj = ev.v - 500000.0;

  var nv = F64{ v: northing };
  var northing_adj = nv.v;
  if southern {
    northing_adj = nv.v - 10000000.0;
  };

  var M = northing_adj / k0;
  var mu_v = F64{
    v: M / (a * (1.0 - ecc_sq / 4.0 - 3.0 * ecc_sq * ecc_sq / 64.0 -
            5.0 * ecc_sq * ecc_sq * ecc_sq / 256.0))
  };

  var e1_2 = e1 * e1;
  var e1_3 = e1_2 * e1;
  var e1_4 = e1_3 * e1;

  var phi1_v = F64{
    v: mu_v.v + (3.0 * e1 / 2.0 - 27.0 * e1_3 / 32.0) * xiom.math.sin(2.0 * mu_v.v) +
       (21.0 * e1_2 / 16.0 - 55.0 * e1_4 / 32.0) * xiom.math.sin(4.0 * mu_v.v) +
       (151.0 * e1_3 / 96.0) * xiom.math.sin(6.0 * mu_v.v) +
       (1097.0 * e1_4 / 512.0) * xiom.math.sin(8.0 * mu_v.v)
  };

  var ep2 = ecc_sq / (1.0 - ecc_sq);

  var sin_phi1 = xiom.math.sin(phi1_v.v);
  var cos_phi1 = xiom.math.cos(phi1_v.v);
  var tan_phi1 = xiom.math.tan(phi1_v.v);

  var N1 = a / xiom.math.sqrt(1.0 - ecc_sq * sin_phi1 * sin_phi1);
  var T1 = tan_phi1 * tan_phi1;
  var C1 = ep2 * cos_phi1 * cos_phi1;
  var R1 = a * (1.0 - ecc_sq) / xiom.math.pow(1.0 - ecc_sq * sin_phi1 * sin_phi1, 1.5);

  var D = easting_adj / (N1 * k0);
  var D2 = D * D;
  var D3 = D2 * D;
  var D4 = D3 * D;
  var D5 = D4 * D;
  var D6 = D5 * D;

  var lat_rad = phi1_v.v - (N1 * tan_phi1 / R1) *
                (D2 / 2.0 - (5.0 + 3.0 * T1 + 10.0 * C1 - 4.0 * C1 * C1 - 9.0 * ep2) *
                D4 / 24.0 +
                (61.0 + 90.0 * T1 + 298.0 * C1 + 45.0 * T1 * T1 -
                252.0 * ep2 - 3.0 * C1 * C1) * D6 / 720.0);

  var lon_rad = deg_to_rad(((zone as Float64) - 1.0) * 6.0 - 180.0 + 3.0) +
                (D - (1.0 + 2.0 * T1 + C1) * D3 / 6.0 +
                (5.0 - 2.0 * C1 + 28.0 * T1 - 3.0 * C1 * C1 +
                8.0 * ep2 + 24.0 * T1 * T1) * D5 / 120.0) / cos_phi1;

  return (rad_to_deg(lat_rad), rad_to_deg(lon_rad));
}
