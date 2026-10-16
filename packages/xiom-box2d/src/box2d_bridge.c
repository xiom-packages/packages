// xiom.box2d -- C bridge over the Box2D v3.1.1 C API (probe subset).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Integer-only ABI: floats cross the boundary as thousandths (milli) so the
// XIOM side needs no struct-by-value or float marshalling.  Out-params are
// XIOM-owned slots (see box2d.xi); every probe returns 0 on success or a
// nonzero diagnostic code.
//
// Compiled into the test binary together with the vendored sources via
// --c-source (port.args.json); no system library, no SDK.

#include "../vendor/box2d/box2d.h"

#define B2PROBE_BAD_ARG 1
#define B2PROBE_WORLD_INVALID 2
#define B2PROBE_BODY_INVALID 3
#define B2PROBE_SHAPE_INVALID 4
#define B2PROBE_JOINT_INVALID 5

// Packed version: major << 16 | minor << 8 | revision.
int b2probe_version(void) {
  b2Version v = b2GetVersion();
  return (v.major << 16) | (v.minor << 8) | v.revision;
}

// Default world gravity in thousandths (expect 0, -10000).
int b2probe_gravity(int* out_gx_milli, int* out_gy_milli) {
  if (out_gx_milli == 0 || out_gy_milli == 0) return B2PROBE_BAD_ARG;
  b2WorldDef def = b2DefaultWorldDef();
  b2WorldId world = b2CreateWorld(&def);
  if (b2World_IsValid(world) == false) return B2PROBE_WORLD_INVALID;
  b2Vec2 g = b2World_GetGravity(world);
  *out_gx_milli = (int)(g.x * 1000.0f);
  *out_gy_milli = (int)(g.y * 1000.0f);
  b2DestroyWorld(world);
  return 0;
}

// Drop a 1x1 dynamic box from `start_y_milli` onto a static ground whose top
// surface is y = 0; step `steps` times at 60 Hz (4 sub-steps).  Writes the
// final body-center y (milli) and the awake flag.
int b2probe_drop(int start_y_milli, int steps, int* out_final_y_milli, int* out_awake) {
  if (out_final_y_milli == 0 || out_awake == 0 || steps <= 0) return B2PROBE_BAD_ARG;

  b2WorldDef wd = b2DefaultWorldDef();
  b2WorldId world = b2CreateWorld(&wd);
  if (b2World_IsValid(world) == false) return B2PROBE_WORLD_INVALID;

  b2BodyDef gdef = b2DefaultBodyDef();
  gdef.position = (b2Vec2){0.0f, -0.5f};
  b2BodyId ground = b2CreateBody(world, &gdef);
  if (b2Body_IsValid(ground) == false) { b2DestroyWorld(world); return B2PROBE_BODY_INVALID; }
  b2ShapeDef gsd = b2DefaultShapeDef();
  b2Polygon gbox = b2MakeBox(20.0f, 0.5f);
  b2ShapeId gshape = b2CreatePolygonShape(ground, &gsd, &gbox);
  if (b2Shape_IsValid(gshape) == false) { b2DestroyWorld(world); return B2PROBE_SHAPE_INVALID; }

  b2BodyDef bdef = b2DefaultBodyDef();
  bdef.type = b2_dynamicBody;
  bdef.position = (b2Vec2){0.0f, (float)start_y_milli / 1000.0f};
  b2BodyId box = b2CreateBody(world, &bdef);
  if (b2Body_IsValid(box) == false) { b2DestroyWorld(world); return B2PROBE_BODY_INVALID; }
  b2ShapeDef sd = b2DefaultShapeDef();
  b2Polygon pbox = b2MakeBox(0.5f, 0.5f);
  b2ShapeId bshape = b2CreatePolygonShape(box, &sd, &pbox);
  if (b2Shape_IsValid(bshape) == false) { b2DestroyWorld(world); return B2PROBE_SHAPE_INVALID; }

  for (int i = 0; i < steps; i++) {
    b2World_Step(world, 1.0f / 60.0f, 4);
  }

  b2Vec2 p = b2Body_GetPosition(box);
  *out_final_y_milli = (int)(p.y * 1000.0f);
  *out_awake = b2Body_IsAwake(box) ? 1 : 0;
  b2DestroyWorld(world);
  return 0;
}

// Apply a horizontal impulse (milli N*s) to a free 1x1 dynamic box (mass 1 kg
// with the default density, no ground) and report the x velocity (milli m/s)
// after one step: dv = J / m, so 5000 in yields ~5000 out.
int b2probe_impulse(int impulse_milli, int* out_vx_milli) {
  if (out_vx_milli == 0) return B2PROBE_BAD_ARG;
  b2WorldDef wd = b2DefaultWorldDef();
  b2WorldId world = b2CreateWorld(&wd);
  if (b2World_IsValid(world) == false) return B2PROBE_WORLD_INVALID;

  b2BodyDef bdef = b2DefaultBodyDef();
  bdef.type = b2_dynamicBody;
  b2BodyId box = b2CreateBody(world, &bdef);
  if (b2Body_IsValid(box) == false) { b2DestroyWorld(world); return B2PROBE_BODY_INVALID; }
  b2ShapeDef sd = b2DefaultShapeDef();
  b2Polygon pbox = b2MakeBox(0.5f, 0.5f);
  b2ShapeId bshape = b2CreatePolygonShape(box, &sd, &pbox);
  if (b2Shape_IsValid(bshape) == false) { b2DestroyWorld(world); return B2PROBE_SHAPE_INVALID; }

  b2Body_ApplyLinearImpulseToCenter(box, (b2Vec2){(float)impulse_milli / 1000.0f, 0.0f}, true);
  b2World_Step(world, 1.0f / 60.0f, 4);

  b2Vec2 v = b2Body_GetLinearVelocity(box);
  *out_vx_milli = (int)(v.x * 1000.0f);
  b2DestroyWorld(world);
  return 0;
}

// Revolute-joint motor probe: a static hub at the origin with a 2.0 x 0.2
// dynamic bar hinged at its center; the motor drives the bar at
// `motor_speed_milli` (rad/s x 1000) with gravity off, so the motor is the
// only torque.  Steps `steps` times at 60 Hz and reports the bar angular
// velocity (milli rad/s) and the joint angle (milli rad).
int b2probe_revolute_motor(int motor_speed_milli, int steps, int* out_w_milli, int* out_angle_milli) {
  if (out_w_milli == 0 || out_angle_milli == 0 || steps <= 0) return B2PROBE_BAD_ARG;

  b2WorldDef wd = b2DefaultWorldDef();
  wd.gravity = (b2Vec2){0.0f, 0.0f};
  b2WorldId world = b2CreateWorld(&wd);
  if (b2World_IsValid(world) == false) return B2PROBE_WORLD_INVALID;

  b2BodyDef hub_def = b2DefaultBodyDef();  // static by default
  b2BodyId hub = b2CreateBody(world, &hub_def);
  if (b2Body_IsValid(hub) == false) { b2DestroyWorld(world); return B2PROBE_BODY_INVALID; }

  b2BodyDef bar_def = b2DefaultBodyDef();
  bar_def.type = b2_dynamicBody;
  b2BodyId bar = b2CreateBody(world, &bar_def);
  if (b2Body_IsValid(bar) == false) { b2DestroyWorld(world); return B2PROBE_BODY_INVALID; }
  b2ShapeDef sd = b2DefaultShapeDef();
  b2Polygon bar_box = b2MakeBox(1.0f, 0.1f);
  b2ShapeId bar_shape = b2CreatePolygonShape(bar, &sd, &bar_box);
  if (b2Shape_IsValid(bar_shape) == false) { b2DestroyWorld(world); return B2PROBE_SHAPE_INVALID; }

  b2RevoluteJointDef jd = b2DefaultRevoluteJointDef();
  jd.bodyIdA = hub;
  jd.bodyIdB = bar;
  jd.localAnchorA = (b2Vec2){0.0f, 0.0f};
  jd.localAnchorB = (b2Vec2){0.0f, 0.0f};
  jd.enableMotor = true;
  jd.motorSpeed = (float)motor_speed_milli / 1000.0f;
  jd.maxMotorTorque = 1000.0f;
  b2JointId joint = b2CreateRevoluteJoint(world, &jd);
  if (b2Joint_IsValid(joint) == false) { b2DestroyWorld(world); return B2PROBE_JOINT_INVALID; }

  for (int i = 0; i < steps; i++) {
    b2World_Step(world, 1.0f / 60.0f, 4);
  }

  *out_w_milli = (int)(b2Body_GetAngularVelocity(bar) * 1000.0f);
  *out_angle_milli = (int)(b2RevoluteJoint_GetAngle(joint) * 1000.0f);
  b2DestroyWorld(world);
  return 0;
}

// Prismatic-joint motor probe: a static base at the origin with a dynamic
// slider attached at world (0, 2) on the +x axis; the motor drives the
// slider at `motor_speed_milli` (m/s x 1000) under default gravity, so the
// constraint must hold the slider's y while it translates.  Reports the
// joint translation and the slider position (milli).
int b2probe_prismatic_motor(int motor_speed_milli, int steps, int* out_translation_milli, int* out_x_milli, int* out_y_milli) {
  if (out_translation_milli == 0 || out_x_milli == 0 || out_y_milli == 0 || steps <= 0) return B2PROBE_BAD_ARG;

  b2WorldDef wd = b2DefaultWorldDef();  // default gravity (0, -10)
  b2WorldId world = b2CreateWorld(&wd);
  if (b2World_IsValid(world) == false) return B2PROBE_WORLD_INVALID;

  b2BodyDef base_def = b2DefaultBodyDef();
  b2BodyId base = b2CreateBody(world, &base_def);
  if (b2Body_IsValid(base) == false) { b2DestroyWorld(world); return B2PROBE_BODY_INVALID; }

  b2BodyDef slider_def = b2DefaultBodyDef();
  slider_def.type = b2_dynamicBody;
  slider_def.position = (b2Vec2){0.0f, 2.0f};
  b2BodyId slider = b2CreateBody(world, &slider_def);
  if (b2Body_IsValid(slider) == false) { b2DestroyWorld(world); return B2PROBE_BODY_INVALID; }
  b2ShapeDef sd = b2DefaultShapeDef();
  b2Polygon slider_box = b2MakeBox(0.25f, 0.25f);
  b2ShapeId slider_shape = b2CreatePolygonShape(slider, &sd, &slider_box);
  if (b2Shape_IsValid(slider_shape) == false) { b2DestroyWorld(world); return B2PROBE_SHAPE_INVALID; }

  b2PrismaticJointDef jd = b2DefaultPrismaticJointDef();
  jd.bodyIdA = base;
  jd.bodyIdB = slider;
  jd.localAnchorA = (b2Vec2){0.0f, 2.0f};
  jd.localAnchorB = (b2Vec2){0.0f, 0.0f};
  jd.localAxisA = (b2Vec2){1.0f, 0.0f};
  jd.enableMotor = true;
  jd.motorSpeed = (float)motor_speed_milli / 1000.0f;
  jd.maxMotorForce = 1000.0f;
  b2JointId joint = b2CreatePrismaticJoint(world, &jd);
  if (b2Joint_IsValid(joint) == false) { b2DestroyWorld(world); return B2PROBE_JOINT_INVALID; }

  for (int i = 0; i < steps; i++) {
    b2World_Step(world, 1.0f / 60.0f, 4);
  }

  b2Vec2 p = b2Body_GetPosition(slider);
  *out_translation_milli = (int)(b2PrismaticJoint_GetTranslation(joint) * 1000.0f);
  *out_x_milli = (int)(p.x * 1000.0f);
  *out_y_milli = (int)(p.y * 1000.0f);
  b2DestroyWorld(world);
  return 0;
}

// ===========================================================================
// 0.4.0 caller surface (by function): world / bodies / step / state read /
// body count / broadphase queries / contact events / joints.
//
// Same integer-only discipline as the probes (values cross as thousandths),
// with a stricter boundary than the probes: NO pointer parameters cross at
// all.  State read-back goes through bridge-owned scalars fetched by
// dedicated accessors (B-20/B-24/B-25 discipline -- no out-param slots, no
// foreign-pointer reads, no pointer casts).  Every entry point returns a
// non-negative payload (handle / id / count / value) or a negative code:
//   -1  bad or destroyed world handle
//   -2  bad argument (shape kind / extents / steps / axis / kind / index)
//   -3  registry full (worlds)
//   -4  world creation failed
//   -5  unknown or removed body id
//   -6  shape or body creation failed
//   -7  joint creation failed / registry full
//   -8  unknown or removed joint id
//   -9  index out of range
// Body ids are per-world bridge ids (monotonic, never reused, so stale ids
// are rejected).  The engine's "world side" of a joint is the hidden static
// anchor body created per world (B2B_WORLD_BODY = -1).
// ===========================================================================

#define B2B_MAX_WORLDS 8
#define B2B_MAX_BODIES 256
#define B2B_MAX_JOINTS 64
#define B2B_MAX_OVERLAP 256
#define B2B_MAX_EVENTS 256

#define B2B_ERR_HANDLE (-1)
#define B2B_ERR_ARG (-2)
#define B2B_ERR_ROOM (-3)
#define B2B_ERR_WORLD (-4)
#define B2B_ERR_BODY (-5)
#define B2B_ERR_SHAPE (-6)
#define B2B_ERR_JOINT (-7)
#define B2B_ERR_JOINT_ID (-8)
#define B2B_ERR_INDEX (-9)

#define B2B_SHAPE_CIRCLE 0
#define B2B_SHAPE_BOX 1

#define B2B_WORLD_BODY (-1)

#define B2B_JOINT_REVOLUTE 0
#define B2B_JOINT_PRISMATIC 1
#define B2B_JOINT_WELD 2
#define B2B_JOINT_DISTANCE 3
#define B2B_JOINT_WHEEL 4
#define B2B_JOINT_MOTOR 5

#define B2B_EVENT_BEGIN 0
#define B2B_EVENT_END 1
#define B2B_EVENT_HIT 2

typedef struct B2BBody {
  int used;
  int bridge_id;
  b2BodyId id;
  b2ShapeId shape;
} B2BBody;

typedef struct B2BJoint {
  int used;
  int bridge_id;
  int kind;
  int body_a;  // bridge body id, or B2B_WORLD_BODY
  int body_b;
  b2JointId id;
} B2BJoint;

typedef struct B2BWorld {
  int used;
  b2WorldId world;
  int dt_micros;
  int capacity;
  b2BodyId anchor;  // hidden static body for B2B_WORLD_BODY joint sides
  B2BBody bodies[B2B_MAX_BODIES];
  int body_count;
  int next_body_id;
  B2BJoint joints[B2B_MAX_JOINTS];
  int joint_count;
  int next_joint_id;
} B2BWorld;

static B2BWorld g_b2b_worlds[B2B_MAX_WORLDS];

// Dedicated state-read cache (fresh values per b2b_body_state call).
static int g_b2b_pos[2];
static int g_b2b_vel[2];
static int g_b2b_angle;
static int g_b2b_wvel;
static int g_b2b_awake;

// Single-hit raycast cache.
static int g_b2b_ray_hit;
static int g_b2b_ray_body;
static int g_b2b_ray_point[2];
static int g_b2b_ray_normal[2];
static int g_b2b_ray_fraction;

// Overlap-query list (canonical ascending body id) + fetch cache.
static int g_b2b_overlap_entries[B2B_MAX_OVERLAP];
static int g_b2b_overlap_count;
static int g_b2b_ov_body;
static int g_b2b_ov_pos[2];

// Contact-event snapshot (canonical ascending pair order) + fetch cache.
typedef struct B2BEventEntry {
  int body_a;
  int body_b;
  int point[2];
  int normal[2];
  int speed;
} B2BEventEntry;

static B2BEventEntry g_b2b_events[B2B_MAX_EVENTS];
static int g_b2b_event_count;
static int g_b2b_event_kind = -1;
static int g_b2b_ev_body_a;
static int g_b2b_ev_body_b;
static int g_b2b_ev_point[2];
static int g_b2b_ev_normal[2];
static int g_b2b_ev_speed;

// Joint-state fetch cache.
static int g_b2b_j_kind;
static int g_b2b_j_primary;
static int g_b2b_j_body_a;
static int g_b2b_j_body_b;

static int b2b_milli(float v) { return (int)(v * 1000.0f); }
static float b2b_units(int milli) { return (float)milli / 1000.0f; }
static float b2b_seconds(int micros) { return (float)micros / 1000000.0f; }

static B2BWorld* b2b_get_world(int handle) {
  if (handle < 0 || handle >= B2B_MAX_WORLDS) return 0;
  if (g_b2b_worlds[handle].used == 0) return 0;
  return &g_b2b_worlds[handle];
}

static int b2b_same_body(b2BodyId a, b2BodyId b) {
  return a.index1 == b.index1 && a.world0 == b.world0 && a.generation == b.generation;
}

static B2BBody* b2b_find_body(B2BWorld* w, int bridge_id) {
  for (int i = 0; i < B2B_MAX_BODIES; i++) {
    if (w->bodies[i].used && w->bodies[i].bridge_id == bridge_id) return &w->bodies[i];
  }
  return 0;
}

// Map a live shape id back to its registry bridge body id (-1 when the shape
// is unknown or already destroyed -- e.g. the removed side of an end event).
static int b2b_body_id_for_shape(B2BWorld* w, b2ShapeId shape) {
  if (b2Shape_IsValid(shape) == false) return -1;
  b2BodyId b = b2Shape_GetBody(shape);
  for (int i = 0; i < B2B_MAX_BODIES; i++) {
    if (w->bodies[i].used && b2b_same_body(w->bodies[i].id, b)) return w->bodies[i].bridge_id;
  }
  return -1;
}

// Drop registry entries for joints Box2D destroyed as a side effect of
// destroying a body.
static void b2b_prune_joints(B2BWorld* w) {
  for (int i = 0; i < B2B_MAX_JOINTS; i++) {
    if (w->joints[i].used && b2Joint_IsValid(w->joints[i].id) == false) {
      w->joints[i].used = 0;
      if (w->joint_count > 0) w->joint_count--;
    }
  }
}

// ---- world -----------------------------------------------------------------

int b2b_world_create(int gx_milli, int gy_milli, int dt_micros, int capacity) {
  if (dt_micros <= 0 || capacity <= 0 || capacity > B2B_MAX_BODIES) return B2B_ERR_ARG;
  int slot = -1;
  for (int i = 0; i < B2B_MAX_WORLDS; i++) {
    if (g_b2b_worlds[i].used == 0) { slot = i; break; }
  }
  if (slot < 0) return B2B_ERR_ROOM;

  B2BWorld* w = &g_b2b_worlds[slot];
  b2WorldDef wd = b2DefaultWorldDef();
  wd.gravity = (b2Vec2){b2b_units(gx_milli), b2b_units(gy_milli)};
  b2WorldId world = b2CreateWorld(&wd);
  if (b2World_IsValid(world) == false) return B2B_ERR_WORLD;

  b2BodyDef adef = b2DefaultBodyDef();  // static at the origin
  b2BodyId anchor = b2CreateBody(world, &adef);
  if (b2Body_IsValid(anchor) == false) {
    b2DestroyWorld(world);
    return B2B_ERR_WORLD;
  }

  for (int i = 0; i < B2B_MAX_BODIES; i++) {
    w->bodies[i].used = 0;
    w->bodies[i].bridge_id = -1;
  }
  for (int i = 0; i < B2B_MAX_JOINTS; i++) w->joints[i].used = 0;
  w->used = 1;
  w->world = world;
  w->dt_micros = dt_micros;
  w->capacity = capacity;
  w->anchor = anchor;
  w->body_count = 0;
  w->next_body_id = 0;
  w->joint_count = 0;
  w->next_joint_id = 0;
  return slot;
}

int b2b_world_destroy(int handle) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  int n = w->body_count;
  b2DestroyWorld(w->world);
  w->used = 0;
  w->body_count = 0;
  w->joint_count = 0;
  return n;
}

int b2b_world_dt(int handle) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  return w->dt_micros;
}

// ---- bodies ----------------------------------------------------------------

int b2b_body_add(int handle, int shape_kind, int ex_milli, int ey_milli,
                 int px_milli, int py_milli, int angle_milli,
                 int mass_milli, int is_static) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (shape_kind != B2B_SHAPE_CIRCLE && shape_kind != B2B_SHAPE_BOX) return B2B_ERR_ARG;
  if (ex_milli <= 0) return B2B_ERR_ARG;
  if (shape_kind == B2B_SHAPE_BOX && ey_milli <= 0) return B2B_ERR_ARG;
  if (w->body_count >= w->capacity) return B2B_ERR_ROOM;

  b2BodyDef bd = b2DefaultBodyDef();
  bd.type = is_static ? b2_staticBody : b2_dynamicBody;
  bd.position = (b2Vec2){b2b_units(px_milli), b2b_units(py_milli)};
  bd.rotation = b2MakeRot(b2b_units(angle_milli));
  b2BodyId body = b2CreateBody(w->world, &bd);
  if (b2Body_IsValid(body) == false) return B2B_ERR_BODY;

  // Contact begin/end and hit events are enabled on every bridge shape so
  // the caller can poll them after a step (Box2D defaults them off).
  b2ShapeDef sd = b2DefaultShapeDef();
  sd.enableContactEvents = true;
  sd.enableHitEvents = true;
  b2ShapeId shape;
  if (shape_kind == B2B_SHAPE_CIRCLE) {
    b2Circle circle = { (b2Vec2){0.0f, 0.0f}, b2b_units(ex_milli) };
    shape = b2CreateCircleShape(body, &sd, &circle);
  } else {
    b2Polygon box = b2MakeBox(b2b_units(ex_milli), b2b_units(ey_milli));
    shape = b2CreatePolygonShape(body, &sd, &box);
  }
  if (b2Shape_IsValid(shape) == false) {
    b2DestroyBody(body);
    return B2B_ERR_SHAPE;
  }

  // Explicit mass (dynamic only): scale the density-derived mass data so the
  // total mass matches and the inertia scales with it (center kept).
  if (is_static == 0 && mass_milli > 0) {
    b2MassData md = b2Body_GetMassData(body);
    if (md.mass > 0.0f) {
      float new_mass = b2b_units(mass_milli);
      md.rotationalInertia *= new_mass / md.mass;
      md.mass = new_mass;
      b2Body_SetMassData(body, md);
    }
  }

  int slot = -1;
  for (int i = 0; i < B2B_MAX_BODIES; i++) {
    if (w->bodies[i].used == 0) { slot = i; break; }
  }
  if (slot < 0) {  // capacity was checked, so only reachable on registry bugs
    b2DestroyBody(body);
    return B2B_ERR_ROOM;
  }
  w->bodies[slot].used = 1;
  w->bodies[slot].bridge_id = w->next_body_id;
  w->bodies[slot].id = body;
  w->bodies[slot].shape = shape;
  w->next_body_id++;
  w->body_count++;
  return w->bodies[slot].bridge_id;
}

int b2b_body_remove(int handle, int body_id) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  B2BBody* b = b2b_find_body(w, body_id);
  if (b == 0) return B2B_ERR_BODY;
  b2DestroyBody(b->id);
  b->used = 0;
  w->body_count--;
  b2b_prune_joints(w);
  return w->body_count;
}

int b2b_body_count(int handle) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  return w->body_count;
}

int b2b_body_mass(int handle, int body_id) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  B2BBody* b = b2b_find_body(w, body_id);
  if (b == 0) return B2B_ERR_BODY;
  return b2b_milli(b2Body_GetMass(b->id));
}

// ---- stepping --------------------------------------------------------------

int b2b_step(int handle) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  b2World_Step(w->world, b2b_seconds(w->dt_micros), 4);
  return 1;
}

int b2b_step_n(int handle, int steps) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (steps <= 0) return B2B_ERR_ARG;
  float dt = b2b_seconds(w->dt_micros);
  for (int i = 0; i < steps; i++) {
    b2World_Step(w->world, dt, 4);
  }
  return steps;
}

// ---- state read (cache + dedicated accessors; no out-param slots) ----------

int b2b_body_state(int handle, int body_id) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  B2BBody* b = b2b_find_body(w, body_id);
  if (b == 0) return B2B_ERR_BODY;
  b2Vec2 p = b2Body_GetPosition(b->id);
  b2Vec2 v = b2Body_GetLinearVelocity(b->id);
  b2Rot r = b2Body_GetRotation(b->id);
  g_b2b_pos[0] = b2b_milli(p.x);
  g_b2b_pos[1] = b2b_milli(p.y);
  g_b2b_vel[0] = b2b_milli(v.x);
  g_b2b_vel[1] = b2b_milli(v.y);
  g_b2b_angle = b2b_milli(b2Rot_GetAngle(r));
  g_b2b_wvel = b2b_milli(b2Body_GetAngularVelocity(b->id));
  g_b2b_awake = b2Body_IsAwake(b->id) ? 1 : 0;
  return 0;
}

int b2b_state_pos_x(void) { return g_b2b_pos[0]; }
int b2b_state_pos_y(void) { return g_b2b_pos[1]; }
int b2b_state_vel_x(void) { return g_b2b_vel[0]; }
int b2b_state_vel_y(void) { return g_b2b_vel[1]; }
int b2b_state_angle(void) { return g_b2b_angle; }
int b2b_state_w(void) { return g_b2b_wvel; }
int b2b_state_awake(void) { return g_b2b_awake; }

// ---- broadphase queries ----------------------------------------------------

// Closest-hit raycast (b2World_CastRayClosest -- no callback crosses).
int b2b_raycast(int handle, int ox_milli, int oy_milli, int dx_milli, int dy_milli) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (dx_milli == 0 && dy_milli == 0) return B2B_ERR_ARG;
  b2QueryFilter filter = b2DefaultQueryFilter();
  b2RayResult r = b2World_CastRayClosest(
      w->world, (b2Vec2){b2b_units(ox_milli), b2b_units(oy_milli)},
      (b2Vec2){b2b_units(dx_milli), b2b_units(dy_milli)}, filter);
  g_b2b_ray_hit = r.hit ? 1 : 0;
  g_b2b_ray_body = r.hit ? b2b_body_id_for_shape(w, r.shapeId) : -1;
  g_b2b_ray_point[0] = b2b_milli(r.point.x);
  g_b2b_ray_point[1] = b2b_milli(r.point.y);
  g_b2b_ray_normal[0] = b2b_milli(r.normal.x);
  g_b2b_ray_normal[1] = b2b_milli(r.normal.y);
  g_b2b_ray_fraction = b2b_milli(r.fraction);
  return 0;
}

int b2b_ray_hit(void) { return g_b2b_ray_hit; }
int b2b_ray_body(void) { return g_b2b_ray_body; }
int b2b_ray_point_x(void) { return g_b2b_ray_point[0]; }
int b2b_ray_point_y(void) { return g_b2b_ray_point[1]; }
int b2b_ray_normal_x(void) { return g_b2b_ray_normal[0]; }
int b2b_ray_normal_y(void) { return g_b2b_ray_normal[1]; }
int b2b_ray_fraction(void) { return g_b2b_ray_fraction; }

// Overlap callback: collect distinct registry body ids.
static bool b2b_overlap_fcn(b2ShapeId shape, void* context) {
  B2BWorld* w = (B2BWorld*)context;
  int id = b2b_body_id_for_shape(w, shape);
  if (id < 0) return true;
  for (int i = 0; i < g_b2b_overlap_count; i++) {
    if (g_b2b_overlap_entries[i] == id) return true;
  }
  if (g_b2b_overlap_count < B2B_MAX_OVERLAP) {
    g_b2b_overlap_entries[g_b2b_overlap_count++] = id;
  }
  return true;
}

// Canonical ascending body-id order so repeated runs read back identical.
static void b2b_sort_overlap(void) {
  for (int i = 1; i < g_b2b_overlap_count; i++) {
    int v = g_b2b_overlap_entries[i];
    int j = i - 1;
    while (j >= 0 && g_b2b_overlap_entries[j] > v) {
      g_b2b_overlap_entries[j + 1] = g_b2b_overlap_entries[j];
      j--;
    }
    g_b2b_overlap_entries[j + 1] = v;
  }
}

static int b2b_run_overlap(B2BWorld* w, b2ShapeProxy proxy) {
  b2QueryFilter filter = b2DefaultQueryFilter();
  g_b2b_overlap_count = 0;
  b2World_OverlapShape(w->world, &proxy, filter, b2b_overlap_fcn, w);
  b2b_sort_overlap();
  return g_b2b_overlap_count;
}

int b2b_overlap_circle(int handle, int radius_milli, int px_milli, int py_milli) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (radius_milli <= 0) return B2B_ERR_ARG;
  b2Vec2 points[1] = { (b2Vec2){b2b_units(px_milli), b2b_units(py_milli)} };
  b2ShapeProxy proxy = b2MakeProxy(points, 1, b2b_units(radius_milli));
  return b2b_run_overlap(w, proxy);
}

int b2b_overlap_box(int handle, int hx_milli, int hy_milli, int px_milli, int py_milli,
                    int angle_milli) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (hx_milli <= 0 || hy_milli <= 0) return B2B_ERR_ARG;
  b2Rot r = b2MakeRot(b2b_units(angle_milli));
  b2Vec2 c = {b2b_units(px_milli), b2b_units(py_milli)};
  b2Vec2 lx = b2Rot_GetXAxis(r);
  b2Vec2 ly = (b2Vec2){-lx.y, lx.x};
  float hx = b2b_units(hx_milli);
  float hy = b2b_units(hy_milli);
  b2Vec2 points[4];
  points[0] = (b2Vec2){c.x + hx * lx.x + hy * ly.x, c.y + hx * lx.y + hy * ly.y};
  points[1] = (b2Vec2){c.x - hx * lx.x + hy * ly.x, c.y - hx * lx.y + hy * ly.y};
  points[2] = (b2Vec2){c.x - hx * lx.x - hy * ly.x, c.y - hx * lx.y - hy * ly.y};
  points[3] = (b2Vec2){c.x + hx * lx.x - hy * ly.x, c.y + hx * lx.y - hy * ly.y};
  b2ShapeProxy proxy = b2MakeProxy(points, 4, 0.0f);
  return b2b_run_overlap(w, proxy);
}

int b2b_overlap_fetch(int handle, int index) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (index < 0 || index >= g_b2b_overlap_count) return B2B_ERR_INDEX;
  B2BBody* b = b2b_find_body(w, g_b2b_overlap_entries[index]);
  if (b == 0) return B2B_ERR_BODY;
  b2Vec2 p = b2Body_GetPosition(b->id);
  g_b2b_ov_body = g_b2b_overlap_entries[index];
  g_b2b_ov_pos[0] = b2b_milli(p.x);
  g_b2b_ov_pos[1] = b2b_milli(p.y);
  return 0;
}

int b2b_overlap_body(void) { return g_b2b_ov_body; }
int b2b_overlap_x(void) { return g_b2b_ov_pos[0]; }
int b2b_overlap_y(void) { return g_b2b_ov_pos[1]; }

// ---- contact events --------------------------------------------------------

// Snapshot the current-step event arrays of one kind into a bridge-owned
// cache, canonicalized to ascending (body_a, body_b) so repeated runs read
// back identical sequences.  Body ids of shapes already destroyed (end
// events) read as -1.
static int b2b_snapshot_contacts(B2BWorld* w, int kind) {
  b2ContactEvents ev = b2World_GetContactEvents(w->world);
  g_b2b_event_count = 0;
  g_b2b_event_kind = kind;
  if (kind == B2B_EVENT_BEGIN) {
    for (int i = 0; i < ev.beginCount && g_b2b_event_count < B2B_MAX_EVENTS; i++) {
      B2BEventEntry* e = &g_b2b_events[g_b2b_event_count++];
      e->body_a = b2b_body_id_for_shape(w, ev.beginEvents[i].shapeIdA);
      e->body_b = b2b_body_id_for_shape(w, ev.beginEvents[i].shapeIdB);
      e->point[0] = 0; e->point[1] = 0;
      e->normal[0] = 0; e->normal[1] = 0;
      e->speed = 0;
    }
  } else if (kind == B2B_EVENT_END) {
    for (int i = 0; i < ev.endCount && g_b2b_event_count < B2B_MAX_EVENTS; i++) {
      B2BEventEntry* e = &g_b2b_events[g_b2b_event_count++];
      e->body_a = b2b_body_id_for_shape(w, ev.endEvents[i].shapeIdA);
      e->body_b = b2b_body_id_for_shape(w, ev.endEvents[i].shapeIdB);
      e->point[0] = 0; e->point[1] = 0;
      e->normal[0] = 0; e->normal[1] = 0;
      e->speed = 0;
    }
  } else {
    for (int i = 0; i < ev.hitCount && g_b2b_event_count < B2B_MAX_EVENTS; i++) {
      B2BEventEntry* e = &g_b2b_events[g_b2b_event_count++];
      e->body_a = b2b_body_id_for_shape(w, ev.hitEvents[i].shapeIdA);
      e->body_b = b2b_body_id_for_shape(w, ev.hitEvents[i].shapeIdB);
      e->point[0] = b2b_milli(ev.hitEvents[i].point.x);
      e->point[1] = b2b_milli(ev.hitEvents[i].point.y);
      e->normal[0] = b2b_milli(ev.hitEvents[i].normal.x);
      e->normal[1] = b2b_milli(ev.hitEvents[i].normal.y);
      e->speed = b2b_milli(ev.hitEvents[i].approachSpeed);
    }
  }
  for (int i = 1; i < g_b2b_event_count; i++) {
    B2BEventEntry v = g_b2b_events[i];
    int j = i - 1;
    while (j >= 0 && (g_b2b_events[j].body_a > v.body_a ||
                      (g_b2b_events[j].body_a == v.body_a && g_b2b_events[j].body_b > v.body_b))) {
      g_b2b_events[j + 1] = g_b2b_events[j];
      j--;
    }
    g_b2b_events[j + 1] = v;
  }
  return g_b2b_event_count;
}

int b2b_contact_count(int handle, int kind) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (kind < B2B_EVENT_BEGIN || kind > B2B_EVENT_HIT) return B2B_ERR_ARG;
  return b2b_snapshot_contacts(w, kind);
}

int b2b_contact_fetch(int handle, int kind, int index) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (kind < B2B_EVENT_BEGIN || kind > B2B_EVENT_HIT) return B2B_ERR_ARG;
  if (g_b2b_event_kind != kind || g_b2b_event_count == 0) b2b_snapshot_contacts(w, kind);
  if (index < 0 || index >= g_b2b_event_count) return B2B_ERR_INDEX;
  B2BEventEntry* e = &g_b2b_events[index];
  g_b2b_ev_body_a = e->body_a;
  g_b2b_ev_body_b = e->body_b;
  g_b2b_ev_point[0] = e->point[0];
  g_b2b_ev_point[1] = e->point[1];
  g_b2b_ev_normal[0] = e->normal[0];
  g_b2b_ev_normal[1] = e->normal[1];
  g_b2b_ev_speed = e->speed;
  return 0;
}

int b2b_contact_body_a(void) { return g_b2b_ev_body_a; }
int b2b_contact_body_b(void) { return g_b2b_ev_body_b; }
int b2b_contact_x(void) { return g_b2b_ev_point[0]; }
int b2b_contact_y(void) { return g_b2b_ev_point[1]; }
int b2b_contact_nx(void) { return g_b2b_ev_normal[0]; }
int b2b_contact_ny(void) { return g_b2b_ev_normal[1]; }
int b2b_contact_speed(void) { return g_b2b_ev_speed; }

// ---- joints ----------------------------------------------------------------

// The world-side body of a joint (-1) is the hidden static anchor.  The world
// anchor (ax, ay) is shared by both sides for revolute/prismatic/weld/wheel;
// the distance joint anchors at the world point on side A and at body B's
// origin (rest length default = creation distance); motor joints ignore the
// anchor.  At least one side must be a live dynamic body.
int b2b_joint_add(int handle, int kind, int body_a, int body_b,
                  int ax_milli, int ay_milli, int axis_x_milli, int axis_y_milli,
                  int collide, int has_motor, int motor_speed_milli,
                  int max_effort_milli, int length_milli) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  if (kind < B2B_JOINT_REVOLUTE || kind > B2B_JOINT_MOTOR) return B2B_ERR_ARG;
  if (body_a == B2B_WORLD_BODY && body_b == B2B_WORLD_BODY) return B2B_ERR_ARG;
  if (body_a != B2B_WORLD_BODY && body_b != B2B_WORLD_BODY && body_a == body_b) return B2B_ERR_ARG;
  if (w->joint_count >= B2B_MAX_JOINTS) return B2B_ERR_ROOM;

  b2BodyId a;
  if (body_a == B2B_WORLD_BODY) {
    a = w->anchor;
  } else {
    B2BBody* ba = b2b_find_body(w, body_a);
    if (ba == 0) return B2B_ERR_BODY;
    a = ba->id;
  }
  b2BodyId b;
  if (body_b == B2B_WORLD_BODY) {
    b = w->anchor;
  } else {
    B2BBody* bb = b2b_find_body(w, body_b);
    if (bb == 0) return B2B_ERR_BODY;
    b = bb->id;
  }
  if (b2Body_GetType(a) != b2_dynamicBody && b2Body_GetType(b) != b2_dynamicBody) {
    return B2B_ERR_ARG;  // Box2D joints need at least one dynamic side
  }

  b2Vec2 anchor = (b2Vec2){b2b_units(ax_milli), b2b_units(ay_milli)};
  b2JointId joint;
  if (kind == B2B_JOINT_REVOLUTE) {
    b2RevoluteJointDef d = b2DefaultRevoluteJointDef();
    d.bodyIdA = a;
    d.bodyIdB = b;
    d.localAnchorA = b2Body_GetLocalPoint(a, anchor);
    d.localAnchorB = b2Body_GetLocalPoint(b, anchor);
    d.collideConnected = collide != 0;
    d.enableMotor = has_motor != 0;
    d.motorSpeed = b2b_units(motor_speed_milli);
    d.maxMotorTorque = b2b_units(max_effort_milli);
    joint = b2CreateRevoluteJoint(w->world, &d);
  } else if (kind == B2B_JOINT_PRISMATIC) {
    if (axis_x_milli == 0 && axis_y_milli == 0) return B2B_ERR_ARG;
    b2PrismaticJointDef d = b2DefaultPrismaticJointDef();
    d.bodyIdA = a;
    d.bodyIdB = b;
    d.localAnchorA = b2Body_GetLocalPoint(a, anchor);
    d.localAnchorB = b2Body_GetLocalPoint(b, anchor);
    d.localAxisA = b2Body_GetLocalVector(a, (b2Vec2){b2b_units(axis_x_milli), b2b_units(axis_y_milli)});
    d.collideConnected = collide != 0;
    d.enableMotor = has_motor != 0;
    d.motorSpeed = b2b_units(motor_speed_milli);
    d.maxMotorForce = b2b_units(max_effort_milli);
    joint = b2CreatePrismaticJoint(w->world, &d);
  } else if (kind == B2B_JOINT_WELD) {
    b2WeldJointDef d = b2DefaultWeldJointDef();
    d.bodyIdA = a;
    d.bodyIdB = b;
    d.localAnchorA = b2Body_GetLocalPoint(a, anchor);
    d.localAnchorB = b2Body_GetLocalPoint(b, anchor);
    d.collideConnected = collide != 0;
    joint = b2CreateWeldJoint(w->world, &d);
  } else if (kind == B2B_JOINT_DISTANCE) {
    b2DistanceJointDef d = b2DefaultDistanceJointDef();
    d.bodyIdA = a;
    d.bodyIdB = b;
    d.localAnchorA = b2Body_GetLocalPoint(a, anchor);
    d.localAnchorB = (b2Vec2){0.0f, 0.0f};
    d.collideConnected = collide != 0;
    if (length_milli > 0) {
      d.length = b2b_units(length_milli);
    } else {
      b2Vec2 pb = b2Body_GetPosition(b);
      float len = b2Distance(anchor, pb);
      d.length = len < 0.005f ? 0.005f : len;
    }
    joint = b2CreateDistanceJoint(w->world, &d);
  } else if (kind == B2B_JOINT_WHEEL) {
    if (axis_x_milli == 0 && axis_y_milli == 0) return B2B_ERR_ARG;
    b2WheelJointDef d = b2DefaultWheelJointDef();
    d.bodyIdA = a;
    d.bodyIdB = b;
    d.localAnchorA = b2Body_GetLocalPoint(a, anchor);
    d.localAnchorB = b2Body_GetLocalPoint(b, anchor);
    d.localAxisA = b2Body_GetLocalVector(a, (b2Vec2){b2b_units(axis_x_milli), b2b_units(axis_y_milli)});
    d.collideConnected = collide != 0;
    d.enableMotor = has_motor != 0;
    d.motorSpeed = b2b_units(motor_speed_milli);
    d.maxMotorTorque = b2b_units(max_effort_milli);
    joint = b2CreateWheelJoint(w->world, &d);
  } else {
    b2MotorJointDef d = b2DefaultMotorJointDef();
    d.bodyIdA = a;
    d.bodyIdB = b;
    d.collideConnected = collide != 0;
    d.maxForce = b2b_units(max_effort_milli);
    d.maxTorque = b2b_units(max_effort_milli);
    joint = b2CreateMotorJoint(w->world, &d);
  }
  if (b2Joint_IsValid(joint) == false) return B2B_ERR_JOINT;

  int slot = -1;
  for (int i = 0; i < B2B_MAX_JOINTS; i++) {
    if (w->joints[i].used == 0) { slot = i; break; }
  }
  if (slot < 0) {
    b2DestroyJoint(joint);
    return B2B_ERR_ROOM;
  }
  w->joints[slot].used = 1;
  w->joints[slot].bridge_id = w->next_joint_id;
  w->joints[slot].kind = kind;
  w->joints[slot].body_a = body_a;
  w->joints[slot].body_b = body_b;
  w->joints[slot].id = joint;
  w->next_joint_id++;
  w->joint_count++;
  return w->joints[slot].bridge_id;
}

int b2b_joint_remove(int handle, int joint_id) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  for (int i = 0; i < B2B_MAX_JOINTS; i++) {
    if (w->joints[i].used && w->joints[i].bridge_id == joint_id) {
      if (b2Joint_IsValid(w->joints[i].id)) b2DestroyJoint(w->joints[i].id);
      w->joints[i].used = 0;
      w->joint_count--;
      return w->joint_count;
    }
  }
  return B2B_ERR_JOINT_ID;
}

int b2b_joint_count(int handle) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  b2b_prune_joints(w);
  return w->joint_count;
}

int b2b_joint_state(int handle, int joint_id) {
  B2BWorld* w = b2b_get_world(handle);
  if (w == 0) return B2B_ERR_HANDLE;
  for (int i = 0; i < B2B_MAX_JOINTS; i++) {
    if (w->joints[i].used && w->joints[i].bridge_id == joint_id) {
      if (b2Joint_IsValid(w->joints[i].id) == false) return B2B_ERR_JOINT_ID;
      int kind = w->joints[i].kind;
      int primary = 0;
      if (kind == B2B_JOINT_REVOLUTE) {
        primary = b2b_milli(b2RevoluteJoint_GetAngle(w->joints[i].id));
      } else if (kind == B2B_JOINT_PRISMATIC) {
        primary = b2b_milli(b2PrismaticJoint_GetTranslation(w->joints[i].id));
      } else if (kind == B2B_JOINT_DISTANCE) {
        primary = b2b_milli(b2DistanceJoint_GetCurrentLength(w->joints[i].id));
      }
      g_b2b_j_kind = kind;
      g_b2b_j_primary = primary;
      g_b2b_j_body_a = w->joints[i].body_a;
      g_b2b_j_body_b = w->joints[i].body_b;
      return 0;
    }
  }
  return B2B_ERR_JOINT_ID;
}

int b2b_joint_state_kind(void) { return g_b2b_j_kind; }
int b2b_joint_state_primary(void) { return g_b2b_j_primary; }
int b2b_joint_state_body_a(void) { return g_b2b_j_body_a; }
int b2b_joint_state_body_b(void) { return g_b2b_j_body_b; }
