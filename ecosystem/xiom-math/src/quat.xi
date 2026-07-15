module xiom.math.quat

use xiom.math;
use xiom.math.vec3;
use xiom.math.mat4;

pub type Quat = { x: Float32; y: Float32; z: Float32; w: Float32; } derive[Clone]

pub fn Quat.identity() -> Quat {
  return Quat{ x: 0.0 as Float32, y: 0.0 as Float32, z: 0.0 as Float32, w: 1.0 as Float32 };
}

pub fn Quat.from_axis_angle(axis: Vec3, angle: Float32) -> Quat {
  var half = angle * 0.5 as Float32;
  var s = (xiom.math.sin(half as Float64) as Float32);
  var sq = axis.x * axis.x + axis.y * axis.y + axis.z * axis.z;
  var inv_len: Float32 = 1.0 as Float32;
  if sq > 0.0 as Float32 {
    inv_len = 1.0 as Float32 / (xiom.math.sqrt(sq as Float64) as Float32);
  }
  return Quat{
    x: axis.x * inv_len * s,
    y: axis.y * inv_len * s,
    z: axis.z * inv_len * s,
    w: (xiom.math.cos(half as Float64) as Float32),
  };
}

pub fn Quat.from_euler(yaw: Float32, pitch: Float32, roll: Float32) -> Quat {
  var hy = yaw * 0.5 as Float32;
  var hp = pitch * 0.5 as Float32;
  var hr = roll * 0.5 as Float32;

  var cy = (xiom.math.cos(hy as Float64) as Float32);
  var sy = (xiom.math.sin(hy as Float64) as Float32);
  var cp = (xiom.math.cos(hp as Float64) as Float32);
  var sp = (xiom.math.sin(hp as Float64) as Float32);
  var cr = (xiom.math.cos(hr as Float64) as Float32);
  var sr = (xiom.math.sin(hr as Float64) as Float32);

  return Quat{
    x: sr * cp * cy - cr * sp * sy,
    y: cr * sp * cy + sr * cp * sy,
    z: cr * cp * sy - sr * sp * cy,
    w: cr * cp * cy + sr * sp * sy,
  };
}

pub fn Quat.mul_rhs(rhs: Quat) -> Quat {
  return Quat{
    x: w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
    y: w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
    z: w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w,
    w: w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
  };
}

pub fn Quat.normalize() -> Quat {
  var sq = x * x + y * y + z * z + w * w;
  if sq == 0.0 as Float32 {
    return Quat{ x: 0.0 as Float32, y: 0.0 as Float32, z: 0.0 as Float32, w: 1.0 as Float32 };
  }
  var inv = 1.0 as Float32 / (xiom.math.sqrt(sq as Float64) as Float32);
  return Quat{ x: x * inv, y: y * inv, z: z * inv, w: w * inv };
}

pub fn Quat.conjugate() -> Quat {
  return Quat{ x: -x, y: -y, z: -z, w: w };
}

pub fn Quat.inverse() -> Quat {
  var conj = Quat{ x: -x, y: -y, z: -z, w: w };
  var sq = x * x + y * y + z * z + w * w;
  if sq == 0.0 as Float32 {
    return Quat{ x: 0.0 as Float32, y: 0.0 as Float32, z: 0.0 as Float32, w: 1.0 as Float32 };
  }
  var inv = 1.0 as Float32 / sq;
  return Quat{ x: conj.x * inv, y: conj.y * inv, z: conj.z * inv, w: conj.w * inv };
}

pub fn Quat.to_mat4() -> Mat4 {
  var xx = x * x;
  var yy = y * y;
  var zz = z * z;
  var xy = x * y;
  var xz = x * z;
  var yz = y * z;
  var wx = w * x;
  var wy = w * y;
  var wz = w * z;

  var one: Float32 = 1.0 as Float32;
  var two: Float32 = 2.0 as Float32;

  return Mat4{
    m0: one - two * (yy + zz),  m1: two * (xy + wz),        m2: two * (xz - wy),        m3: 0.0 as Float32,
    m4: two * (xy - wz),        m5: one - two * (xx + zz),  m6: two * (yz + wx),        m7: 0.0 as Float32,
    m8: two * (xz + wy),        m9: two * (yz - wx),        m10: one - two * (xx + yy), m11: 0.0 as Float32,
    m12: 0.0 as Float32,        m13: 0.0 as Float32,        m14: 0.0 as Float32,        m15: one,
  };
}

pub fn Quat.slerp(t: Float32, other: Quat) -> Quat {
  var dot = x * other.x + y * other.y + z * other.z + w * other.w;

  var other_x = other.x;
  var other_y = other.y;
  var other_z = other.z;
  var other_w = other.w;
  if dot < 0.0 as Float32 {
    other_x = -other.x;
    other_y = -other.y;
    other_z = -other.z;
    other_w = -other.w;
    dot = -dot;
  }

  var DOT_THRESHOLD: Float32 = 0.9995 as Float32;
  if dot > DOT_THRESHOLD {
    var result = Quat{
      x: x + (other_x - x) * t,
      y: y + (other_y - y) * t,
      z: z + (other_z - z) * t,
      w: w + (other_w - w) * t,
    };
    var sq = result.x * result.x + result.y * result.y + result.z * result.z + result.w * result.w;
    var inv = 1.0 as Float32 / (xiom.math.sqrt(sq as Float64) as Float32);
    return Quat{ x: result.x * inv, y: result.y * inv, z: result.z * inv, w: result.w * inv };
  }

  var theta_0 = (xiom.math.acos(dot as Float64) as Float32);
  var theta = theta_0 * t;
  var sin_theta = (xiom.math.sin(theta as Float64) as Float32);
  var sin_theta_0 = (xiom.math.sin(theta_0 as Float64) as Float32);

  var s0 = (xiom.math.cos(theta as Float64) as Float32) - dot * sin_theta / sin_theta_0;
  var s1 = sin_theta / sin_theta_0;

  return Quat{
    x: x * s0 + other_x * s1,
    y: y * s0 + other_y * s1,
    z: z * s0 + other_z * s1,
    w: w * s0 + other_w * s1,
  };
}

pub fn Quat.rotate_vec(v: Vec3) -> Vec3 {
  var qv = Quat{ x: v.x, y: v.y, z: v.z, w: 0.0 as Float32 };
  var conj = Quat{ x: -x, y: -y, z: -z, w: w };

  var t = Quat{
    x: w * qv.x + x * qv.w + y * qv.z - z * qv.y,
    y: w * qv.y - x * qv.z + y * qv.w + z * qv.x,
    z: w * qv.z + x * qv.y - y * qv.x + z * qv.w,
    w: w * qv.w - x * qv.x - y * qv.y - z * qv.z,
  };

  return Vec3{
    x: t.x * conj.w + t.w * conj.x + t.y * conj.z - t.z * conj.y,
    y: t.y * conj.w - t.x * conj.z + t.w * conj.y + t.z * conj.x,
    z: t.z * conj.w + t.x * conj.y - t.y * conj.x + t.w * conj.z,
  };
}
