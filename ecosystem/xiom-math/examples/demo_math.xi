module xiom.math.examples.demo_math

use xiom.math.vec2.Vec2.new;
use xiom.math.vec2.Vec2.dot;
use xiom.math.vec2.Vec2.length;
use xiom.math.vec3.Vec3.new;
use xiom.math.vec3.Vec3.cross;
use xiom.math.vec3.Vec3.zero;
use xiom.math.vec4.Vec4.from_vec3;
use xiom.math.vec4.Vec4.to_vec3;
use xiom.math.mat4.Mat4.identity;
use xiom.math.mat4.Mat4.translate;
use xiom.math.mat4.Mat4.perspective;
use xiom.math.mat4.Mat4.look_at;
use xiom.math.mat4.Mat4.element;
use xiom.math.mat4.Mat4.mul_vec3;
use xiom.math.quat.Quat.from_axis_angle;
use xiom.math.quat.Quat.rotate_vec;
use xiom.math.quat.Quat.from_euler;
use xiom.math.quat.Quat.slerp;
use xiom.math.quat.Quat.to_mat4;

fn main() -> Int {
  var failed = false;

  var a = Vec2.new(3.0 as Float32, 4.0 as Float32);
  var b = Vec2.new(1.0 as Float32, 2.0 as Float32);
  var dot2 = a.dot(b);
  if dot2 < 10.99 as Float32 || dot2 > 11.01 as Float32 {
    failed = true;
  }
  var len2 = a.length();
  if len2 < 4.99 as Float32 || len2 > 5.01 as Float32 {
    failed = true;
  }

  var v = Vec3.new(1.0 as Float32, 0.0 as Float32, 0.0 as Float32);
  var cross = v.cross(Vec3.new(0.0 as Float32, 1.0 as Float32, 0.0 as Float32));
  if cross.z < 0.99 as Float32 || cross.z > 1.01 as Float32 {
    failed = true;
  }

  var v4 = Vec4.from_vec3(v, 1.0 as Float32);
  var v3back = v4.to_vec3();
  if v3back.x != v.x {
    failed = true;
  }

  var ident = Mat4.identity();
  if ident.element(0, 0) != 1.0 as Float32 {
    failed = true;
  }

  var trans = Mat4.translate(Vec3.new(5.0 as Float32, 0.0 as Float32, 0.0 as Float32));
  var tp = trans.mul_vec3(Vec3.zero());
  if tp.x < 4.99 as Float32 || tp.x > 5.01 as Float32 {
    failed = true;
  }

  var perspective = Mat4.perspective(
    3.14159265 as Float32 * 45.0 as Float32 / 180.0 as Float32,
    16.0 as Float32 / 9.0 as Float32,
    0.1 as Float32,
    100.0 as Float32,
  );
  var _ = perspective;

  var eye = Vec3.new(0.0 as Float32, 0.0 as Float32, 3.0 as Float32);
  var center = Vec3.new(0.0 as Float32, 0.0 as Float32, 0.0 as Float32);
  var up = Vec3.new(0.0 as Float32, 1.0 as Float32, 0.0 as Float32);
  var view = Mat4.look_at(eye, center, up);
  var _ = view;

  var q = Quat.from_axis_angle(
    Vec3.new(0.0 as Float32, 0.0 as Float32, 1.0 as Float32),
    3.14159265 as Float32 * 0.5 as Float32,
  );
  var rotated = q.rotate_vec(Vec3.new(1.0 as Float32, 0.0 as Float32, 0.0 as Float32));
  if rotated.x > -0.01 as Float32 && rotated.x < 0.01 as Float32 {
    if rotated.y < 0.99 as Float32 || rotated.y > 1.01 as Float32 {
      failed = true;
    }
  }

  var q2 = Quat.from_euler(0.0 as Float32, 0.0 as Float32, 3.14159265 as Float32 * 0.5 as Float32);
  var slerped = q.slerp(q2, 0.5 as Float32);
  var _ = slerped;

  var mat = q.to_mat4();
  if mat.element(3, 3) != 1.0 as Float32 {
    failed = true;
  }

  if failed { return 1; }
  return 0;
}
