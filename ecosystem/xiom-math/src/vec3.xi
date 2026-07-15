module xiom.math.vec3

use xiom.math;

pub type Vec3 = { x: Float32; y: Float32; z: Float32; } derive[Clone]

pub fn Vec3.new(x: Float32, y: Float32, z: Float32) -> Vec3 {
  return Vec3{ x: x, y: y, z: z };
}

pub fn Vec3.zero() -> Vec3 {
  return Vec3{ x: 0.0 as Float32, y: 0.0 as Float32, z: 0.0 as Float32 };
}

pub fn Vec3.add(rhs: Vec3) -> Vec3 {
  return Vec3{ x: x + rhs.x, y: y + rhs.y, z: z + rhs.z };
}

pub fn Vec3.sub(rhs: Vec3) -> Vec3 {
  return Vec3{ x: x - rhs.x, y: y - rhs.y, z: z - rhs.z };
}

pub fn Vec3.mul_scalar(s: Float32) -> Vec3 {
  return Vec3{ x: x * s, y: y * s, z: z * s };
}

pub fn Vec3.div_scalar(s: Float32) -> Vec3 {
  return Vec3{ x: x / s, y: y / s, z: z / s };
}

pub fn Vec3.dot(rhs: Vec3) -> Float32 {
  return x * rhs.x + y * rhs.y + z * rhs.z;
}

pub fn Vec3.cross(rhs: Vec3) -> Vec3 {
  return Vec3{
    x: y * rhs.z - z * rhs.y,
    y: z * rhs.x - x * rhs.z,
    z: x * rhs.y - y * rhs.x,
  };
}

pub fn Vec3.length_sq() -> Float32 {
  return x * x + y * y + z * z;
}

pub fn Vec3.length() -> Float32 {
  var sq = x * x + y * y + z * z;
  return (xiom.math.sqrt(sq as Float64) as Float32);
}

pub fn Vec3.normalize() -> Vec3 {
  var sq = x * x + y * y + z * z;
  if sq == 0.0 as Float32 {
    return Vec3{ x: 0.0 as Float32, y: 0.0 as Float32, z: 0.0 as Float32 };
  }
  var inv = 1.0 as Float32 / (xiom.math.sqrt(sq as Float64) as Float32);
  return Vec3{ x: x * inv, y: y * inv, z: z * inv };
}

pub fn Vec3.lerp(t: Float32, other: Vec3) -> Vec3 {
  return Vec3{
    x: x + (other.x - x) * t,
    y: y + (other.y - y) * t,
    z: z + (other.z - z) * t,
  };
}

pub fn Vec3.distance(other: Vec3) -> Float32 {
  var dx = x - other.x;
  var dy = y - other.y;
  var dz = z - other.z;
  var sq = dx * dx + dy * dy + dz * dz;
  return (xiom.math.sqrt(sq as Float64) as Float32);
}

pub fn Vec3.negate() -> Vec3 {
  return Vec3{ x: -x, y: -y, z: -z };
}

pub fn Vec3.reflect(normal: Vec3) -> Vec3 {
  var d = 2.0 as Float32 * (x * normal.x + y * normal.y + z * normal.z);
  return Vec3{
    x: x - d * normal.x,
    y: y - d * normal.y,
    z: z - d * normal.z,
  };
}

pub fn Vec3.project_onto(normal: Vec3) -> Vec3 {
  var sq = normal.x * normal.x + normal.y * normal.y + normal.z * normal.z;
  if sq == 0.0 as Float32 {
    return Vec3{ x: 0.0 as Float32, y: 0.0 as Float32, z: 0.0 as Float32 };
  }
  var d = (x * normal.x + y * normal.y + z * normal.z) / sq;
  return Vec3{ x: d * normal.x, y: d * normal.y, z: d * normal.z };
}
