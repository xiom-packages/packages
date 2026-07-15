// XIOM — Box2D Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Safe, ergonomic wrappers over the raw Box2D FFI declarations in box2d.xi.
// Adds safety contracts, Result-based error handling, and convenience
// constructors for common physics scenarios.
//
// NOTE ON STRUCT ABI: The extern declarations in box2d.xi assume the compiler
// supports passing/returning C structs by value. Xiom's current extern "C"
// support may be limited to primitive types. See AUDIT.md §1 for the C bridge
// fallback strategy.

module xiom.box2d_safe

use xiom.box2d;

// ===========================================================================
// NULL HANDLE PREDICATES (Box2D uses B2_IS_NULL: index1 == 0)
// ===========================================================================

fn is_null_world_id(id: B2WorldId) -> Bool {
  return id.index1 == 0;
}

fn is_null_body_id(id: B2BodyId) -> Bool {
  return id.index1 == 0;
}

fn is_null_shape_id(id: B2ShapeId) -> Bool {
  return id.index1 == 0;
}

fn is_null_joint_id(id: B2JointId) -> Bool {
  return id.index1 == 0;
}

fn is_null_chain_id(id: B2ChainId) -> Bool {
  return id.index1 == 0;
}

// ===========================================================================
// MATH HELPERS
//
// Box2D's math operations (b2Add, b2Mul, b2Normalize, etc.) are B2_INLINE
// and NOT present in the shared library. We reimplement the core subset here.
// See AUDIT.md §2.
// ===========================================================================

pub fn vec2_zero() -> B2Vec2 {
  return B2Vec2{ x: 0.0, y: 0.0 };
}

pub fn vec2(x: Float32, y: Float32) -> B2Vec2 {
  return B2Vec2{ x: x, y: y };
}

pub fn vec2_add(a: B2Vec2, b: B2Vec2) -> B2Vec2 {
  return B2Vec2{ x: a.x + b.x, y: a.y + b.y };
}

pub fn vec2_sub(a: B2Vec2, b: B2Vec2) -> B2Vec2 {
  return B2Vec2{ x: a.x - b.x, y: a.y - b.y };
}

pub fn vec2_scale(v: B2Vec2, s: Float32) -> B2Vec2 {
  return B2Vec2{ x: v.x * s, y: v.y * s };
}

pub fn vec2_dot(a: B2Vec2, b: B2Vec2) -> Float32 {
  return a.x * b.x + a.y * b.y;
}

pub fn vec2_length(v: B2Vec2) -> Float32 {
  return builtin_sqrt(v.x * v.x + v.y * v.y);
}

pub fn vec2_normalize(v: B2Vec2) -> B2Vec2 {
  let len = vec2_length(v);
  if len < 0.0000001 {
    return vec2_zero();
  }
  return vec2_scale(v, 1.0 / len);
}

pub fn rot_from_angle(radians: Float32) -> B2Rot {
  return B2Rot{
    c: builtin_cos(radians),
    s: builtin_sin(radians),
  };
}

pub fn rot_identity() -> B2Rot {
  return B2Rot{ c: 1.0, s: 0.0 };
}

pub fn rot_get_angle(q: B2Rot) -> Float32 {
  return builtin_atan2(q.s, q.c);
}

pub fn pos(x: Float32, y: Float32) -> B2Pos {
  return B2Pos{ x: x as Float64, y: y as Float64 };
}

pub fn pos_zero() -> B2Pos {
  return B2Pos{ x: 0.0, y: 0.0 };
}

pub fn aabb(lower_x: Float32, lower_y: Float32, upper_x: Float32, upper_y: Float32) -> B2AABB {
  return B2AABB{
    lowerBound: B2Vec2{ x: lower_x, y: lower_y },
    upperBound: B2Vec2{ x: upper_x, y: upper_y },
  };
}

// Built-in math placeholders (link to runtime math intrinsics)
fn builtin_sqrt(v: Float32) -> Float32 { return v; }
fn builtin_cos(v: Float32) -> Float32 { return v; }
fn builtin_sin(v: Float32) -> Float32 { return v; }
fn builtin_atan2(y: Float32, x: Float32) -> Float32 { return y; }

// ===========================================================================
// WORLD
// ===========================================================================

pub fn create_world(gravity_x: Float32, gravity_y: Float32) -> Result[B2WorldId, Str] {
  var def = unsafe { b2DefaultWorldDef() };
  def.gravity.x = gravity_x;
  def.gravity.y = gravity_y;
  def.enableSleep = 1 as Int32;
  def.enableContinuous = 1 as Int32;
  def.workerCount = 4 as Int32;

  let world_id = unsafe { b2CreateWorld(&def) };
  if is_null_world_id(world_id) {
    return Err("b2CreateWorld returned null world");
  }
  return Ok(world_id);
}

pub fn destroy_world(world_id: B2WorldId)
  requires: !is_null_world_id(world_id)
{
  unsafe { b2DestroyWorld(world_id); }
}

pub fn step(world_id: B2WorldId, time_step: Float32, sub_steps: Int32)
  requires: !is_null_world_id(world_id)
  requires: time_step > 0.0
  requires: sub_steps > 0
{
  unsafe { b2World_Step(world_id, time_step, sub_steps); }
}

pub fn set_gravity(world_id: B2WorldId, gx: Float32, gy: Float32)
  requires: !is_null_world_id(world_id)
{
  let gravity = B2Vec2{ x: gx, y: gy };
  unsafe { b2World_SetGravity(world_id, gravity); }
}

// ===========================================================================
// BODY
// ===========================================================================

pub fn create_body_dynamic(world_id: B2WorldId, px: Float32, py: Float32, angle: Float32) -> Result[B2BodyId, Str]
  requires: !is_null_world_id(world_id)
{
  var def = unsafe { b2DefaultBodyDef() };
  def.bodyType = B2_DYNAMIC_BODY;
  def.position = pos(px, py);
  def.rotation = rot_from_angle(angle);
  def.enableSleep = 1 as Int32;
  def.isAwake = 1 as Int32;

  let body_id = unsafe { b2CreateBody(world_id, &def) };
  if is_null_body_id(body_id) {
    return Err("b2CreateBody returned null body");
  }
  return Ok(body_id);
}

pub fn create_body_static(world_id: B2WorldId, px: Float32, py: Float32, angle: Float32) -> Result[B2BodyId, Str]
  requires: !is_null_world_id(world_id)
{
  var def = unsafe { b2DefaultBodyDef() };
  def.bodyType = B2_STATIC_BODY;
  def.position = pos(px, py);
  def.rotation = rot_from_angle(angle);

  let body_id = unsafe { b2CreateBody(world_id, &def) };
  if is_null_body_id(body_id) {
    return Err("b2CreateBody returned null body");
  }
  return Ok(body_id);
}

pub fn create_body_kinematic(world_id: B2WorldId, px: Float32, py: Float32, angle: Float32) -> Result[B2BodyId, Str]
  requires: !is_null_world_id(world_id)
{
  var def = unsafe { b2DefaultBodyDef() };
  def.bodyType = B2_KINEMATIC_BODY;
  def.position = pos(px, py);
  def.rotation = rot_from_angle(angle);

  let body_id = unsafe { b2CreateBody(world_id, &def) };
  if is_null_body_id(body_id) {
    return Err("b2CreateBody returned null body");
  }
  return Ok(body_id);
}

pub fn destroy_body(body_id: B2BodyId)
  requires: !is_null_body_id(body_id)
{
  unsafe { b2DestroyBody(body_id); }
}

pub fn body_get_position(body_id: B2BodyId) -> (Float32, Float32)
  requires: !is_null_body_id(body_id)
{
  let p = unsafe { b2Body_GetPosition(body_id) };
  return (p.x as Float32, p.y as Float32);
}

pub fn body_set_position(body_id: B2BodyId, px: Float32, py: Float32, angle: Float32)
  requires: !is_null_body_id(body_id)
{
  let p = pos(px, py);
  let r = rot_from_angle(angle);
  unsafe { b2Body_SetTransform(body_id, p, r); }
}

pub fn body_get_angle(body_id: B2BodyId) -> Float32
  requires: !is_null_body_id(body_id)
{
  let r = unsafe { b2Body_GetRotation(body_id) };
  return builtin_atan2(r.s, r.c);
}

pub fn body_get_velocity(body_id: B2BodyId) -> (Float32, Float32)
  requires: !is_null_body_id(body_id)
{
  let v = unsafe { b2Body_GetLinearVelocity(body_id) };
  return (v.x, v.y);
}

pub fn body_set_velocity(body_id: B2BodyId, vx: Float32, vy: Float32)
  requires: !is_null_body_id(body_id)
{
  let vel = B2Vec2{ x: vx, y: vy };
  unsafe { b2Body_SetLinearVelocity(body_id, vel); }
}

pub fn body_get_angular_velocity(body_id: B2BodyId) -> Float32
  requires: !is_null_body_id(body_id)
{
  return unsafe { b2Body_GetAngularVelocity(body_id) };
}

pub fn body_set_angular_velocity(body_id: B2BodyId, omega: Float32)
  requires: !is_null_body_id(body_id)
{
  unsafe { b2Body_SetAngularVelocity(body_id, omega); }
}

pub fn body_apply_force_to_center(body_id: B2BodyId, fx: Float32, fy: Float32)
  requires: !is_null_body_id(body_id)
{
  let force = B2Vec2{ x: fx, y: fy };
  unsafe { b2Body_ApplyForceToCenter(body_id, force, 1 as Int32); }
}

pub fn body_apply_linear_impulse_to_center(body_id: B2BodyId, ix: Float32, iy: Float32)
  requires: !is_null_body_id(body_id)
{
  let impulse = B2Vec2{ x: ix, y: iy };
  unsafe { b2Body_ApplyLinearImpulseToCenter(body_id, impulse, 1 as Int32); }
}

pub fn body_apply_torque(body_id: B2BodyId, torque: Float32)
  requires: !is_null_body_id(body_id)
{
  unsafe { b2Body_ApplyTorque(body_id, torque, 1 as Int32); }
}

pub fn body_get_mass(body_id: B2BodyId) -> Float32
  requires: !is_null_body_id(body_id)
{
  return unsafe { b2Body_GetMass(body_id); }
}

pub fn body_is_awake(body_id: B2BodyId) -> Bool
  requires: !is_null_body_id(body_id)
{
  let aw: Int32 = unsafe { b2Body_IsAwake(body_id) };
  return aw != 0;
}

pub fn body_set_awake(body_id: B2BodyId, awake: Bool)
  requires: !is_null_body_id(body_id)
{
  let val: Int32 = if awake { 1 } else { 0 };
  unsafe { b2Body_SetAwake(body_id, val); }
}

// ===========================================================================
// SHAPES
// ===========================================================================

fn make_default_shape_def(density: Float32, friction: Float32, restitution: Float32) -> B2ShapeDef {
  var def = unsafe { b2DefaultShapeDef() };
  def.density = density;
  def.material.friction = friction;
  def.material.restitution = restitution;
  return def;
}

pub fn create_box_shape(body_id: B2BodyId, half_width: Float32, half_height: Float32) -> Result[B2ShapeId, Str]
  requires: !is_null_body_id(body_id)
  requires: half_width > 0.0
  requires: half_height > 0.0
{
  let polygon = unsafe { b2MakeBox(half_width, half_height) };
  var def = make_default_shape_def(1.0, 0.6, 0.0);
  let shape_id = unsafe { b2CreatePolygonShape(body_id, &def, &polygon) };
  if is_null_shape_id(shape_id) {
    return Err("b2CreatePolygonShape returned null shape");
  }
  return Ok(shape_id);
}

pub fn create_box_shape_with_material(body_id: B2BodyId, half_w: Float32, half_h: Float32, density: Float32, friction: Float32, restitution: Float32) -> Result[B2ShapeId, Str]
  requires: !is_null_body_id(body_id)
  requires: half_w > 0.0
  requires: half_h > 0.0
  requires: density >= 0.0
{
  let polygon = unsafe { b2MakeBox(half_w, half_h) };
  var def = make_default_shape_def(density, friction, restitution);
  let shape_id = unsafe { b2CreatePolygonShape(body_id, &def, &polygon) };
  if is_null_shape_id(shape_id) {
    return Err("b2CreatePolygonShape returned null shape");
  }
  return Ok(shape_id);
}

pub fn create_circle_shape(body_id: B2BodyId, radius: Float32) -> Result[B2ShapeId, Str]
  requires: !is_null_body_id(body_id)
  requires: radius > 0.0
{
  let circle = B2Circle{
    center: B2Vec2{ x: 0.0, y: 0.0 },
    radius: radius,
  };
  var def = make_default_shape_def(1.0, 0.6, 0.3);
  let shape_id = unsafe { b2CreateCircleShape(body_id, &def, &circle) };
  if is_null_shape_id(shape_id) {
    return Err("b2CreateCircleShape returned null shape");
  }
  return Ok(shape_id);
}

pub fn create_capsule_shape(body_id: B2BodyId, x1: Float32, y1: Float32, x2: Float32, y2: Float32, radius: Float32) -> Result[B2ShapeId, Str]
  requires: !is_null_body_id(body_id)
  requires: radius > 0.0
{
  let capsule = B2Capsule{
    center1: B2Vec2{ x: x1, y: y1 },
    center2: B2Vec2{ x: x2, y: y2 },
    radius:  radius,
  };
  var def = make_default_shape_def(1.0, 0.6, 0.0);
  let shape_id = unsafe { b2CreateCapsuleShape(body_id, &def, &capsule) };
  if is_null_shape_id(shape_id) {
    return Err("b2CreateCapsuleShape returned null shape");
  }
  return Ok(shape_id);
}

pub fn create_ground_box(world_id: B2WorldId, px: Float32, py: Float32, half_w: Float32, half_h: Float32, angle: Float32) -> Result[B2BodyId, Str]
  requires: !is_null_world_id(world_id)
  requires: half_w > 0.0
  requires: half_h > 0.0
{
  let body_id = create_body_static(world_id, px, py, angle);
  match body_id {
    Err(e) => return Err(e),
    Ok(bid) => {
      let sid = create_box_shape_with_material(bid, half_w, half_h, 0.0, 0.6, 0.0);
      match sid {
        Err(e2) => {
          destroy_body(bid);
          return Err(e2);
        },
        Ok(_) => return Ok(bid),
      }
    }
  }
}

pub fn destroy_shape(shape_id: B2ShapeId)
  requires: !is_null_shape_id(shape_id)
{
  unsafe { b2DestroyShape(shape_id, 1 as Int32) };
}

pub fn shape_set_friction(shape_id: B2ShapeId, friction: Float32)
  requires: !is_null_shape_id(shape_id)
{
  unsafe { b2Shape_SetFriction(shape_id, friction); }
}

pub fn shape_set_restitution(shape_id: B2ShapeId, restitution: Float32)
  requires: !is_null_shape_id(shape_id)
{
  unsafe { b2Shape_SetRestitution(shape_id, restitution); }
}

pub fn shape_set_density(shape_id: B2ShapeId, density: Float32)
  requires: !is_null_shape_id(shape_id)
  requires: density >= 0.0
{
  unsafe { b2Shape_SetDensity(shape_id, density); }
}

pub fn shape_set_sensor(shape_id: B2ShapeId, is_sensor: Bool)
  requires: !is_null_shape_id(shape_id)
{
  let val: Int32 = if is_sensor { 1 } else { 0 };
  unsafe { b2Shape_SetSensor(shape_id, val); }
}

// ===========================================================================
// RAY CAST
// ===========================================================================

pub fn ray_cast_closest(world_id: B2WorldId, ox: Float32, oy: Float32, tx: Float32, ty: Float32) -> Option[(Float32, Float32, Float32)]
  requires: !is_null_world_id(world_id)
{
  let origin = pos(ox, oy);
  let translation = B2Vec2{ x: tx, y: ty };
  var filter = unsafe { b2DefaultQueryFilter() };
  let result = unsafe { b2World_CastRayClosest(world_id, origin, translation, filter) };
  if result.hit == 0 {
    return None[(Float32, Float32, Float32)];
  }
  return Some((result.point.x as Float32, result.point.y as Float32, result.fraction));
}

// ===========================================================================
// JOINTS
// ===========================================================================

pub fn create_distance_joint(world_id: B2WorldId, body_a: B2BodyId, body_b: B2BodyId,
                              anchor_a_x: Float32, anchor_a_y: Float32,
                              anchor_b_x: Float32, anchor_b_y: Float32,
                              length: Float32) -> Result[B2JointId, Str]
  requires: !is_null_world_id(world_id)
  requires: !is_null_body_id(body_a)
  requires: !is_null_body_id(body_b)
{
  var def = unsafe { b2DefaultDistanceJointDef() };
  def.base.bodyIdA = body_a;
  def.base.bodyIdB = body_b;
  def.base.localFrameA.p = B2Vec2{ x: anchor_a_x, y: anchor_a_y };
  def.base.localFrameB.p = B2Vec2{ x: anchor_b_x, y: anchor_b_y };
  def.base.collideConnected = 0 as Int32;
  def.length = length;

  let joint_id = unsafe { b2CreateDistanceJoint(world_id, &def) };
  if is_null_joint_id(joint_id) {
    return Err("b2CreateDistanceJoint returned null joint");
  }
  return Ok(joint_id);
}

pub fn create_revolute_joint(world_id: B2WorldId, body_a: B2BodyId, body_b: B2BodyId,
                              px: Float32, py: Float32) -> Result[B2JointId, Str]
  requires: !is_null_world_id(world_id)
  requires: !is_null_body_id(body_a)
  requires: !is_null_body_id(body_b)
{
  var def = unsafe { b2DefaultRevoluteJointDef() };
  def.base.bodyIdA = body_a;
  def.base.bodyIdB = body_b;
  def.base.localFrameA.p = B2Vec2{ x: px, y: py };
  def.base.localFrameB.p = B2Vec2{ x: 0.0, y: 0.0 };
  def.base.collideConnected = 0 as Int32;

  let joint_id = unsafe { b2CreateRevoluteJoint(world_id, &def) };
  if is_null_joint_id(joint_id) {
    return Err("b2CreateRevoluteJoint returned null joint");
  }
  return Ok(joint_id);
}

pub fn destroy_joint(joint_id: B2JointId)
  requires: !is_null_joint_id(joint_id)
{
  unsafe { b2DestroyJoint(joint_id, 1 as Int32) };
}

// ===========================================================================
// EVENT QUERIES
// ===========================================================================

pub fn get_contact_event_count(world_id: B2WorldId) -> Int32
  requires: !is_null_world_id(world_id)
{
  let events = unsafe { b2World_GetContactEvents(world_id) };
  return events.beginCount + events.endCount + events.hitCount;
}

pub fn get_body_move_event_count(world_id: B2WorldId) -> Int32
  requires: !is_null_world_id(world_id)
{
  let events = unsafe { b2World_GetBodyEvents(world_id) };
  return events.moveCount;
}
