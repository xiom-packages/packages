module xiom.math.mat4

use xiom.math;
use xiom.math.vec3;
use xiom.math.vec4;

pub type Mat4 = {
  m0: Float32;  m1: Float32;  m2: Float32;  m3: Float32;
  m4: Float32;  m5: Float32;  m6: Float32;  m7: Float32;
  m8: Float32;  m9: Float32;  m10: Float32; m11: Float32;
  m12: Float32; m13: Float32; m14: Float32; m15: Float32;
} derive[Clone]

pub fn Mat4.identity() -> Mat4 {
  return Mat4{
    m0: 1.0 as Float32,  m1: 0.0 as Float32,  m2: 0.0 as Float32,  m3: 0.0 as Float32,
    m4: 0.0 as Float32,  m5: 1.0 as Float32,  m6: 0.0 as Float32,  m7: 0.0 as Float32,
    m8: 0.0 as Float32,  m9: 0.0 as Float32,  m10: 1.0 as Float32, m11: 0.0 as Float32,
    m12: 0.0 as Float32, m13: 0.0 as Float32, m14: 0.0 as Float32, m15: 1.0 as Float32,
  };
}

pub fn Mat4.zero() -> Mat4 {
  return Mat4{
    m0: 0.0 as Float32,  m1: 0.0 as Float32,  m2: 0.0 as Float32,  m3: 0.0 as Float32,
    m4: 0.0 as Float32,  m5: 0.0 as Float32,  m6: 0.0 as Float32,  m7: 0.0 as Float32,
    m8: 0.0 as Float32,  m9: 0.0 as Float32,  m10: 0.0 as Float32, m11: 0.0 as Float32,
    m12: 0.0 as Float32, m13: 0.0 as Float32, m14: 0.0 as Float32, m15: 0.0 as Float32,
  };
}

pub fn Mat4.translate(v: Vec3) -> Mat4 {
  return Mat4{
    m0: 1.0 as Float32,  m1: 0.0 as Float32,  m2: 0.0 as Float32,  m3: 0.0 as Float32,
    m4: 0.0 as Float32,  m5: 1.0 as Float32,  m6: 0.0 as Float32,  m7: 0.0 as Float32,
    m8: 0.0 as Float32,  m9: 0.0 as Float32,  m10: 1.0 as Float32, m11: 0.0 as Float32,
    m12: v.x,            m13: v.y,            m14: v.z,            m15: 1.0 as Float32,
  };
}

pub fn Mat4.rotate(axis: Vec3, angle: Float32) -> Mat4 {
  var c = (xiom.math.cos(angle as Float64) as Float32);
  var s = (xiom.math.sin(angle as Float64) as Float32);
  var t = 1.0 as Float32 - c;

  var sq = axis.x * axis.x + axis.y * axis.y + axis.z * axis.z;
  var inv_len: Float32 = 1.0 as Float32;
  if sq > 0.0 as Float32 {
    inv_len = 1.0 as Float32 / (xiom.math.sqrt(sq as Float64) as Float32);
  }
  var nx = axis.x * inv_len;
  var ny = axis.y * inv_len;
  var nz = axis.z * inv_len;

  return Mat4{
    m0: c + nx * nx * t,        m1: ny * nx * t + nz * s,   m2: nz * nx * t - ny * s,   m3: 0.0 as Float32,
    m4: nx * ny * t - nz * s,   m5: c + ny * ny * t,        m6: nz * ny * t + nx * s,   m7: 0.0 as Float32,
    m8: nx * nz * t + ny * s,   m9: ny * nz * t - nx * s,   m10: c + nz * nz * t,       m11: 0.0 as Float32,
    m12: 0.0 as Float32,        m13: 0.0 as Float32,        m14: 0.0 as Float32,        m15: 1.0 as Float32,
  };
}

pub fn Mat4.scale(v: Vec3) -> Mat4 {
  return Mat4{
    m0: v.x,             m1: 0.0 as Float32,  m2: 0.0 as Float32,  m3: 0.0 as Float32,
    m4: 0.0 as Float32,  m5: v.y,             m6: 0.0 as Float32,  m7: 0.0 as Float32,
    m8: 0.0 as Float32,  m9: 0.0 as Float32,  m10: v.z,            m11: 0.0 as Float32,
    m12: 0.0 as Float32, m13: 0.0 as Float32, m14: 0.0 as Float32, m15: 1.0 as Float32,
  };
}

pub fn Mat4.perspective(fov: Float32, aspect: Float32, near: Float32, far: Float32) -> Mat4 {
  var f = 1.0 as Float32 / (xiom.math.tan((fov / 2.0 as Float32) as Float64) as Float32);
  var range_inv = 1.0 as Float32 / (near - far);

  return Mat4{
    m0: f / aspect,      m1: 0.0 as Float32,  m2: 0.0 as Float32,                   m3: 0.0 as Float32,
    m4: 0.0 as Float32,  m5: f,               m6: 0.0 as Float32,                   m7: 0.0 as Float32,
    m8: 0.0 as Float32,  m9: 0.0 as Float32,  m10: (far + near) * range_inv,        m11: -1.0 as Float32,
    m12: 0.0 as Float32, m13: 0.0 as Float32, m14: 2.0 as Float32 * far * near * range_inv, m15: 0.0 as Float32,
  };
}

pub fn Mat4.ortho(left: Float32, right: Float32, bottom: Float32, top: Float32, near: Float32, far: Float32) -> Mat4 {
  var rl = 1.0 as Float32 / (right - left);
  var tb = 1.0 as Float32 / (top - bottom);
  var nf = 1.0 as Float32 / (far - near);

  var t0 = 0.0 as Float32 - (right + left) * rl;
  var t1 = 0.0 as Float32 - (top + bottom) * tb;
  var t2 = 0.0 as Float32 - (far + near) * nf;

  return Mat4{
    m0: 2.0 as Float32 * rl,  m1: 0.0 as Float32,       m2: 0.0 as Float32,        m3: 0.0 as Float32,
    m4: 0.0 as Float32,       m5: 2.0 as Float32 * tb,  m6: 0.0 as Float32,        m7: 0.0 as Float32,
    m8: 0.0 as Float32,       m9: 0.0 as Float32,       m10: -2.0 as Float32 * nf,  m11: 0.0 as Float32,
    m12: t0, m13: t1, m14: t2, m15: 1.0 as Float32,
  };
}

pub fn Mat4.look_at(eye: Vec3, center: Vec3, up: Vec3) -> Mat4 {
  var fx = center.x - eye.x;
  var fy = center.y - eye.y;
  var fz = center.z - eye.z;
  var f_sq = fx * fx + fy * fy + fz * fz;
  var f_inv: Float32 = 1.0 as Float32;
  if f_sq > 0.0 as Float32 {
    f_inv = 1.0 as Float32 / (xiom.math.sqrt(f_sq as Float64) as Float32);
  }
  fx = fx * f_inv;
  fy = fy * f_inv;
  fz = fz * f_inv;

  var up_sq = up.x * up.x + up.y * up.y + up.z * up.z;
  var unx = up.x;
  var uny = up.y;
  var unz = up.z;
  if up_sq > 0.0 as Float32 {
    var up_inv = 1.0 as Float32 / (xiom.math.sqrt(up_sq as Float64) as Float32);
    unx = up.x * up_inv;
    uny = up.y * up_inv;
    unz = up.z * up_inv;
  }

  var sx = fy * unz - fz * uny;
  var sy = fz * unx - fx * unz;
  var sz = fx * uny - fy * unx;

  var ux = sy * fz - sz * fy;
  var uy = sz * fx - sx * fz;
  var uz = sx * fy - sy * fx;

  return Mat4{
    m0: sx,  m1: ux,  m2: -fx, m3: 0.0 as Float32,
    m4: sy,  m5: uy,  m6: -fy, m7: 0.0 as Float32,
    m8: sz,  m9: uz,  m10: -fz, m11: 0.0 as Float32,
    m12: -(sx * eye.x + sy * eye.y + sz * eye.z),
    m13: -(ux * eye.x + uy * eye.y + uz * eye.z),
    m14: (fx * eye.x + fy * eye.y + fz * eye.z),
    m15: 1.0 as Float32,
  };
}

pub fn Mat4.mul_rhs(rhs: Mat4) -> Mat4 {
  return Mat4{
    m0:  m0 * rhs.m0 + m4 * rhs.m1 + m8 * rhs.m2 + m12 * rhs.m3,
    m1:  m1 * rhs.m0 + m5 * rhs.m1 + m9 * rhs.m2 + m13 * rhs.m3,
    m2:  m2 * rhs.m0 + m6 * rhs.m1 + m10 * rhs.m2 + m14 * rhs.m3,
    m3:  m3 * rhs.m0 + m7 * rhs.m1 + m11 * rhs.m2 + m15 * rhs.m3,
    m4:  m0 * rhs.m4 + m4 * rhs.m5 + m8 * rhs.m6 + m12 * rhs.m7,
    m5:  m1 * rhs.m4 + m5 * rhs.m5 + m9 * rhs.m6 + m13 * rhs.m7,
    m6:  m2 * rhs.m4 + m6 * rhs.m5 + m10 * rhs.m6 + m14 * rhs.m7,
    m7:  m3 * rhs.m4 + m7 * rhs.m5 + m11 * rhs.m6 + m15 * rhs.m7,
    m8:  m0 * rhs.m8 + m4 * rhs.m9 + m8 * rhs.m10 + m12 * rhs.m11,
    m9:  m1 * rhs.m8 + m5 * rhs.m9 + m9 * rhs.m10 + m13 * rhs.m11,
    m10: m2 * rhs.m8 + m6 * rhs.m9 + m10 * rhs.m10 + m14 * rhs.m11,
    m11: m3 * rhs.m8 + m7 * rhs.m9 + m11 * rhs.m10 + m15 * rhs.m11,
    m12: m0 * rhs.m12 + m4 * rhs.m13 + m8 * rhs.m14 + m12 * rhs.m15,
    m13: m1 * rhs.m12 + m5 * rhs.m13 + m9 * rhs.m14 + m13 * rhs.m15,
    m14: m2 * rhs.m12 + m6 * rhs.m13 + m10 * rhs.m14 + m14 * rhs.m15,
    m15: m3 * rhs.m12 + m7 * rhs.m13 + m11 * rhs.m14 + m15 * rhs.m15,
  };
}

pub fn Mat4.mul_vec3(v: Vec3) -> Vec3 {
  var x = m0 * v.x + m4 * v.y + m8 * v.z + m12;
  var y = m1 * v.x + m5 * v.y + m9 * v.z + m13;
  var z = m2 * v.x + m6 * v.y + m10 * v.z + m14;
  var w = m3 * v.x + m7 * v.y + m11 * v.z + m15;
  if w != 0.0 as Float32 {
    return Vec3{ x: x / w, y: y / w, z: z / w };
  }
  return Vec3{ x: x, y: y, z: z };
}

pub fn Mat4.mul_vec4(v: Vec4) -> Vec4 {
  var x = m0 * v.x + m4 * v.y + m8 * v.z + m12 * v.w;
  var y = m1 * v.x + m5 * v.y + m9 * v.z + m13 * v.w;
  var z = m2 * v.x + m6 * v.y + m10 * v.z + m14 * v.w;
  var w = m3 * v.x + m7 * v.y + m11 * v.z + m15 * v.w;
  return Vec4{ x: x, y: y, z: z, w: w };
}

pub fn Mat4.transpose() -> Mat4 {
  return Mat4{
    m0: m0,  m1: m4,  m2: m8,  m3: m12,
    m4: m1,  m5: m5,  m6: m9,  m7: m13,
    m8: m2,  m9: m6,  m10: m10, m11: m14,
    m12: m3, m13: m7, m14: m11, m15: m15,
  };
}

pub fn Mat4.determinant() -> Float32 {
  var a0 = m0 * m5 - m1 * m4;
  var a1 = m0 * m6 - m2 * m4;
  var a2 = m0 * m7 - m3 * m4;
  var a3 = m1 * m6 - m2 * m5;
  var a4 = m1 * m7 - m3 * m5;
  var a5 = m2 * m7 - m3 * m6;
  var b0 = m8 * m13 - m9 * m12;
  var b1 = m8 * m14 - m10 * m12;
  var b2 = m8 * m15 - m11 * m12;
  var b3 = m9 * m14 - m10 * m13;
  var b4 = m9 * m15 - m11 * m13;
  var b5 = m10 * m15 - m11 * m14;
  return a0 * b5 - a1 * b4 + a2 * b3 + a3 * b2 - a4 * b1 + a5 * b0;
}

pub fn Mat4.inverse() -> Mat4 {
  var a0 = m0 * m5 - m1 * m4;
  var a1 = m0 * m6 - m2 * m4;
  var a2 = m0 * m7 - m3 * m4;
  var a3 = m1 * m6 - m2 * m5;
  var a4 = m1 * m7 - m3 * m5;
  var a5 = m2 * m7 - m3 * m6;
  var b0 = m8 * m13 - m9 * m12;
  var b1 = m8 * m14 - m10 * m12;
  var b2 = m8 * m15 - m11 * m12;
  var b3 = m9 * m14 - m10 * m13;
  var b4 = m9 * m15 - m11 * m13;
  var b5 = m10 * m15 - m11 * m14;

  var det = a0 * b5 - a1 * b4 + a2 * b3 + a3 * b2 - a4 * b1 + a5 * b0;
  var inv_det: Float32 = 1.0 as Float32;
  if det != 0.0 as Float32 {
    inv_det = 1.0 as Float32 / det;
  }

  return Mat4{
    m0: (m5 * b5 - m6 * b4 + m7 * b3) * inv_det,
    m1: (-m1 * b5 + m2 * b4 - m3 * b3) * inv_det,
    m2: (m13 * a5 - m14 * a4 + m15 * a3) * inv_det,
    m3: (-m9 * a5 + m10 * a4 - m11 * a3) * inv_det,
    m4: (-m4 * b5 + m6 * b2 - m7 * b1) * inv_det,
    m5: (m0 * b5 - m2 * b2 + m3 * b1) * inv_det,
    m6: (-m12 * a5 + m14 * a2 - m15 * a1) * inv_det,
    m7: (m8 * a5 - m10 * a2 + m11 * a1) * inv_det,
    m8: (m4 * b4 - m5 * b2 + m7 * b0) * inv_det,
    m9: (-m0 * b4 + m1 * b2 - m3 * b0) * inv_det,
    m10: (m12 * a4 - m13 * a2 + m15 * a0) * inv_det,
    m11: (-m8 * a4 + m9 * a2 - m11 * a0) * inv_det,
    m12: (-m4 * b3 + m5 * b1 - m6 * b0) * inv_det,
    m13: (m0 * b3 - m1 * b1 + m2 * b0) * inv_det,
    m14: (-m12 * a3 + m13 * a1 - m14 * a0) * inv_det,
    m15: (m8 * a3 - m9 * a1 + m10 * a0) * inv_det,
  };
}

pub fn Mat4.element(row: Int, col: Int) -> Float32 {
  if col == 0 {
    if row == 0 { return m0; }
    if row == 1 { return m1; }
    if row == 2 { return m2; }
    if row == 3 { return m3; }
  }
  if col == 1 {
    if row == 0 { return m4; }
    if row == 1 { return m5; }
    if row == 2 { return m6; }
    if row == 3 { return m7; }
  }
  if col == 2 {
    if row == 0 { return m8; }
    if row == 1 { return m9; }
    if row == 2 { return m10; }
    if row == 3 { return m11; }
  }
  if col == 3 {
    if row == 0 { return m12; }
    if row == 1 { return m13; }
    if row == 2 { return m14; }
    if row == 3 { return m15; }
  }
  return 0.0 as Float32;
}
