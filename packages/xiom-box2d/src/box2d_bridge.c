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
