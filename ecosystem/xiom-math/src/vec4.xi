module xiom.math.vec4

use xiom.math;
use xiom.math.vec3;

pub type Vec4 = { x: Float32; y: Float32; z: Float32; w: Float32; } derive[Clone]

pub fn Vec4.new(x: Float32, y: Float32, z: Float32, w: Float32) -> Vec4 {
  return Vec4{ x: x, y: y, z: z, w: w };
}

pub fn Vec4.zero() -> Vec4 {
  return Vec4{ x: 0.0 as Float32, y: 0.0 as Float32, z: 0.0 as Float32, w: 0.0 as Float32 };
}

pub fn Vec4.from_vec3(v: Vec3, w: Float32) -> Vec4 {
  return Vec4{ x: v.x, y: v.y, z: v.z, w: w };
}

pub fn Vec4.add(rhs: Vec4) -> Vec4 {
  return Vec4{ x: x + rhs.x, y: y + rhs.y, z: z + rhs.z, w: w + rhs.w };
}

pub fn Vec4.sub(rhs: Vec4) -> Vec4 {
  return Vec4{ x: x - rhs.x, y: y - rhs.y, z: z - rhs.z, w: w - rhs.w };
}

pub fn Vec4.mul_scalar(s: Float32) -> Vec4 {
  return Vec4{ x: x * s, y: y * s, z: z * s, w: w * s };
}

pub fn Vec4.dot(rhs: Vec4) -> Float32 {
  return x * rhs.x + y * rhs.y + z * rhs.z + w * rhs.w;
}

pub fn Vec4.length_sq() -> Float32 {
  return x * x + y * y + z * z + w * w;
}

pub fn Vec4.length() -> Float32 {
  var sq = x * x + y * y + z * z + w * w;
  return (xiom.math.sqrt(sq as Float64) as Float32);
}

pub fn Vec4.normalize() -> Vec4 {
  var sq = x * x + y * y + z * z + w * w;
  if sq == 0.0 as Float32 {
    return Vec4{ x: 0.0 as Float32, y: 0.0 as Float32, z: 0.0 as Float32, w: 0.0 as Float32 };
  }
  var inv = 1.0 as Float32 / (xiom.math.sqrt(sq as Float64) as Float32);
  return Vec4{ x: x * inv, y: y * inv, z: z * inv, w: w * inv };
}

pub fn Vec4.to_vec3() -> Vec3 {
  return Vec3{ x: x, y: y, z: z };
}
