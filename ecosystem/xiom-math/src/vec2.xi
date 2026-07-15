module xiom.math.vec2

use xiom.math;

pub type Vec2 = { x: Float32; y: Float32; } derive[Clone]

pub fn Vec2.new(x: Float32, y: Float32) -> Vec2 {
  return Vec2{ x: x, y: y };
}

pub fn Vec2.zero() -> Vec2 {
  return Vec2{ x: 0.0 as Float32, y: 0.0 as Float32 };
}

pub fn Vec2.add(rhs: Vec2) -> Vec2 {
  return Vec2{ x: x + rhs.x, y: y + rhs.y };
}

pub fn Vec2.sub(rhs: Vec2) -> Vec2 {
  return Vec2{ x: x - rhs.x, y: y - rhs.y };
}

pub fn Vec2.mul_scalar(s: Float32) -> Vec2 {
  return Vec2{ x: x * s, y: y * s };
}

pub fn Vec2.div_scalar(s: Float32) -> Vec2 {
  return Vec2{ x: x / s, y: y / s };
}

pub fn Vec2.dot(rhs: Vec2) -> Float32 {
  return x * rhs.x + y * rhs.y;
}

pub fn Vec2.length_sq() -> Float32 {
  return x * x + y * y;
}

pub fn Vec2.length() -> Float32 {
  var sq = x * x + y * y;
  return (xiom.math.sqrt(sq as Float64) as Float32);
}

pub fn Vec2.normalize() -> Vec2 {
  var sq = x * x + y * y;
  if sq == 0.0 as Float32 {
    return Vec2{ x: 0.0 as Float32, y: 0.0 as Float32 };
  }
  var inv = 1.0 as Float32 / (xiom.math.sqrt(sq as Float64) as Float32);
  return Vec2{ x: x * inv, y: y * inv };
}

pub fn Vec2.lerp(t: Float32, other: Vec2) -> Vec2 {
  return Vec2{
    x: x + (other.x - x) * t,
    y: y + (other.y - y) * t,
  };
}

pub fn Vec2.distance(other: Vec2) -> Float32 {
  var dx = x - other.x;
  var dy = y - other.y;
  var sq = dx * dx + dy * dy;
  return (xiom.math.sqrt(sq as Float64) as Float32);
}

pub fn Vec2.negate() -> Vec2 {
  return Vec2{ x: -x, y: -y };
}

pub fn Vec2.abs() -> Vec2 {
  return Vec2{
    x: (xiom.math.abs_float(x as Float64) as Float32),
    y: (xiom.math.abs_float(y as Float64) as Float32),
  };
}

pub fn Vec2.min(other: Vec2) -> Vec2 {
  return Vec2{
    x: (xiom.math.min_float(x as Float64, other.x as Float64) as Float32),
    y: (xiom.math.min_float(y as Float64, other.y as Float64) as Float32),
  };
}

pub fn Vec2.max(other: Vec2) -> Vec2 {
  return Vec2{
    x: (xiom.math.max_float(x as Float64, other.x as Float64) as Float32),
    y: (xiom.math.max_float(y as Float64, other.y as Float64) as Float32),
  };
}
