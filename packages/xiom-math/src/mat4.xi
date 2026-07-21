module xiom.math.mat4

use xiom.math;
use xiom.math.vec3;
use xiom.math.vec4;

pub type Mat4 = { m: [16]Float32; } derive[Clone]

pub fn Mat4.identity() -> Mat4 {
  var m: [16]Float32;
  m[0] = 1.0 as Float32;  m[1] = 0.0 as Float32;  m[2] = 0.0 as Float32;  m[3] = 0.0 as Float32;
  m[4] = 0.0 as Float32;  m[5] = 1.0 as Float32;  m[6] = 0.0 as Float32;  m[7] = 0.0 as Float32;
  m[8] = 0.0 as Float32;  m[9] = 0.0 as Float32;  m[10] = 1.0 as Float32; m[11] = 0.0 as Float32;
  m[12] = 0.0 as Float32; m[13] = 0.0 as Float32; m[14] = 0.0 as Float32; m[15] = 1.0 as Float32;
  return Mat4{ m: m };
}

pub fn Mat4.zero() -> Mat4 {
  var m: [16]Float32;
  var i: Int = 0;
  while i < 16 {
    m[i] = 0.0 as Float32;
    i = i + 1;
  }
  return Mat4{ m: m };
}

pub fn Mat4.translate(v: Vec3) -> Mat4 {
  var m = Mat4.identity();
  m.m[12] = v.x;
  m.m[13] = v.y;
  m.m[14] = v.z;
  return m;
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

  var m: [16]Float32;
  m[0] = c + nx * nx * t;        m[1] = ny * nx * t + nz * s;   m[2] = nz * nx * t - ny * s;   m[3] = 0.0 as Float32;
  m[4] = nx * ny * t - nz * s;   m[5] = c + ny * ny * t;        m[6] = nz * ny * t + nx * s;   m[7] = 0.0 as Float32;
  m[8] = nx * nz * t + ny * s;   m[9] = ny * nz * t - nx * s;   m[10] = c + nz * nz * t;       m[11] = 0.0 as Float32;
  m[12] = 0.0 as Float32;        m[13] = 0.0 as Float32;        m[14] = 0.0 as Float32;        m[15] = 1.0 as Float32;
  return Mat4{ m: m };
}

pub fn Mat4.scale(v: Vec3) -> Mat4 {
  var m: [16]Float32;
  m[0] = v.x;             m[1] = 0.0 as Float32;  m[2] = 0.0 as Float32;  m[3] = 0.0 as Float32;
  m[4] = 0.0 as Float32;  m[5] = v.y;             m[6] = 0.0 as Float32;  m[7] = 0.0 as Float32;
  m[8] = 0.0 as Float32;  m[9] = 0.0 as Float32;  m[10] = v.z;            m[11] = 0.0 as Float32;
  m[12] = 0.0 as Float32; m[13] = 0.0 as Float32; m[14] = 0.0 as Float32; m[15] = 1.0 as Float32;
  return Mat4{ m: m };
}

pub fn Mat4.perspective(fov: Float32, aspect: Float32, near: Float32, far: Float32) -> Mat4
  requires: fov > 0.0 as Float32
  requires: aspect > 0.0 as Float32
  requires: near > 0.0 as Float32
  requires: far > near
{
  var f = 1.0 as Float32 / (xiom.math.tan((fov / 2.0 as Float32) as Float64) as Float32);
  var range_inv = 1.0 as Float32 / (near - far);

  var m: [16]Float32;
  m[0] = f / aspect;      m[1] = 0.0 as Float32;  m[2] = 0.0 as Float32;                   m[3] = 0.0 as Float32;
  m[4] = 0.0 as Float32;  m[5] = f;               m[6] = 0.0 as Float32;                   m[7] = 0.0 as Float32;
  m[8] = 0.0 as Float32;  m[9] = 0.0 as Float32;  m[10] = (far + near) * range_inv;        m[11] = -1.0 as Float32;
  m[12] = 0.0 as Float32; m[13] = 0.0 as Float32; m[14] = 2.0 as Float32 * far * near * range_inv; m[15] = 0.0 as Float32;
  return Mat4{ m: m };
}

pub fn Mat4.ortho(left: Float32, right: Float32, bottom: Float32, top: Float32, near: Float32, far: Float32) -> Mat4
  requires: left < right
  requires: bottom < top
  requires: near != far
{
  var rl = 1.0 as Float32 / (right - left);
  var tb = 1.0 as Float32 / (top - bottom);
  var nf = 1.0 as Float32 / (far - near);

  var m: [16]Float32;
  m[0] = 2.0 as Float32 * rl;   m[1] = 0.0 as Float32;       m[2] = 0.0 as Float32;        m[3] = 0.0 as Float32;
  m[4] = 0.0 as Float32;        m[5] = 2.0 as Float32 * tb;  m[6] = 0.0 as Float32;        m[7] = 0.0 as Float32;
  m[8] = 0.0 as Float32;        m[9] = 0.0 as Float32;       m[10] = -2.0 as Float32 * nf;  m[11] = 0.0 as Float32;
  m[12] = -(right + left) * rl; m[13] = -(top + bottom) * tb; m[14] = -(far + near) * nf;  m[15] = 1.0 as Float32;
  return Mat4{ m: m };
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

  var m: [16]Float32;
  m[0] = sx;  m[1] = ux;  m[2] = -fx; m[3] = 0.0 as Float32;
  m[4] = sy;  m[5] = uy;  m[6] = -fy; m[7] = 0.0 as Float32;
  m[8] = sz;  m[9] = uz;  m[10] = -fz; m[11] = 0.0 as Float32;
  m[12] = -(sx * eye.x + sy * eye.y + sz * eye.z);
  m[13] = -(ux * eye.x + uy * eye.y + uz * eye.z);
  m[14] = (fx * eye.x + fy * eye.y + fz * eye.z);
  m[15] = 1.0 as Float32;
  return Mat4{ m: m };
}

pub fn Mat4.mul_rhs(rhs: Mat4) -> Mat4 {
  var out: [16]Float32;
  var col: Int = 0;
  while col < 4 {
    var base = col * 4;
    var row: Int = 0;
    while row < 4 {
      var sum: Float32 = 0.0 as Float32;
      var k: Int = 0;
      while k < 4 {
        sum = sum + m[row + k * 4] * rhs.m[k + base];
        k = k + 1;
      }
      out[row + base] = sum;
      row = row + 1;
    }
    col = col + 1;
  }
  return Mat4{ m: out };
}

pub fn Mat4.mul_vec3(v: Vec3) -> Vec3 {
  var x = m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12];
  var y = m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13];
  var z = m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14];
  var w = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15];
  if w != 0.0 as Float32 {
    return Vec3{ x: x / w, y: y / w, z: z / w };
  }
  return Vec3{ x: x, y: y, z: z };
}

pub fn Mat4.mul_vec4(v: Vec4) -> Vec4 {
  var x = m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12] * v.w;
  var y = m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13] * v.w;
  var z = m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14] * v.w;
  var w = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15] * v.w;
  return Vec4{ x: x, y: y, z: z, w: w };
}

pub fn Mat4.transpose() -> Mat4 {
  var out: [16]Float32;
  var i: Int = 0;
  while i < 16 {
    var col = i / 4;
    var row = i % 4;
    out[i] = m[row * 4 + col];
    i = i + 1;
  }
  return Mat4{ m: out };
}

pub fn Mat4.determinant() -> Float32 {
  var a0 = m[0] * m[5] - m[1] * m[4];
  var a1 = m[0] * m[6] - m[2] * m[4];
  var a2 = m[0] * m[7] - m[3] * m[4];
  var a3 = m[1] * m[6] - m[2] * m[5];
  var a4 = m[1] * m[7] - m[3] * m[5];
  var a5 = m[2] * m[7] - m[3] * m[6];
  var b0 = m[8] * m[13] - m[9] * m[12];
  var b1 = m[8] * m[14] - m[10] * m[12];
  var b2 = m[8] * m[15] - m[11] * m[12];
  var b3 = m[9] * m[14] - m[10] * m[13];
  var b4 = m[9] * m[15] - m[11] * m[13];
  var b5 = m[10] * m[15] - m[11] * m[14];
  return a0 * b5 - a1 * b4 + a2 * b3 + a3 * b2 - a4 * b1 + a5 * b0;
}

pub fn Mat4.inverse() -> Mat4 {
  var a0 = m[0] * m[5] - m[1] * m[4];
  var a1 = m[0] * m[6] - m[2] * m[4];
  var a2 = m[0] * m[7] - m[3] * m[4];
  var a3 = m[1] * m[6] - m[2] * m[5];
  var a4 = m[1] * m[7] - m[3] * m[5];
  var a5 = m[2] * m[7] - m[3] * m[6];
  var b0 = m[8] * m[13] - m[9] * m[12];
  var b1 = m[8] * m[14] - m[10] * m[12];
  var b2 = m[8] * m[15] - m[11] * m[12];
  var b3 = m[9] * m[14] - m[10] * m[13];
  var b4 = m[9] * m[15] - m[11] * m[13];
  var b5 = m[10] * m[15] - m[11] * m[14];

  var det = a0 * b5 - a1 * b4 + a2 * b3 + a3 * b2 - a4 * b1 + a5 * b0;
  var inv_det: Float32 = 1.0 as Float32;
  if det != 0.0 as Float32 {
    inv_det = 1.0 as Float32 / det;
  }

  var out: [16]Float32;
  out[0] = (m[5] * b5 - m[6] * b4 + m[7] * b3) * inv_det;
  out[1] = (-m[1] * b5 + m[2] * b4 - m[3] * b3) * inv_det;
  out[2] = (m[13] * a5 - m[14] * a4 + m[15] * a3) * inv_det;
  out[3] = (-m[9] * a5 + m[10] * a4 - m[11] * a3) * inv_det;
  out[4] = (-m[4] * b5 + m[6] * b2 - m[7] * b1) * inv_det;
  out[5] = (m[0] * b5 - m[2] * b2 + m[3] * b1) * inv_det;
  out[6] = (-m[12] * a5 + m[14] * a2 - m[15] * a1) * inv_det;
  out[7] = (m[8] * a5 - m[10] * a2 + m[11] * a1) * inv_det;
  out[8] = (m[4] * b4 - m[5] * b2 + m[7] * b0) * inv_det;
  out[9] = (-m[0] * b4 + m[1] * b2 - m[3] * b0) * inv_det;
  out[10] = (m[12] * a4 - m[13] * a2 + m[15] * a0) * inv_det;
  out[11] = (-m[8] * a4 + m[9] * a2 - m[11] * a0) * inv_det;
  out[12] = (-m[4] * b3 + m[5] * b1 - m[6] * b0) * inv_det;
  out[13] = (m[0] * b3 - m[1] * b1 + m[2] * b0) * inv_det;
  out[14] = (-m[12] * a3 + m[13] * a1 - m[14] * a0) * inv_det;
  out[15] = (m[8] * a3 - m[9] * a1 + m[10] * a0) * inv_det;

  return Mat4{ m: out };
}

pub fn Mat4.element(row: Int, col: Int) -> Float32
  requires: row >= 0; requires: row < 4; requires: col >= 0; requires: col < 4
{
  return m[col * 4 + row];
}
