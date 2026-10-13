// xiom.jolt -- C bridge over the vendored Jolt Physics core (v5.6.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Two layers over one integer ABI (floats cross as milli/micros; XIOM never
// marshals structs or pointers across the boundary):
//   * scalar-return probes (0.2.0): joltprobe_drop / joltprobe_impulse each
//     build a small world, step it with a single-threaded job system and
//     cache the result scalars for the module to read back.
//   * caller-usable world/body surface (0.3.0): a fixed registry of live
//     worlds addressed by slot handles -- never raw pointers (B-25).  The
//     bridge owns every world/body/shape; XIOM passes and receives integers
//     only.  State reads land in bridge-owned scalars (no out-param slots),
//     then are fetched by joltb_state_* (B-20/B-23/B-24 discipline: XIOM
//     never reads through foreign pointers).
// Registration mirrors the upstream HelloWorld sample
// (RegisterDefaultAllocator + Factory + RegisterTypes), ref-counted so probes
// and live worlds can share it.

#include "../vendor/Jolt/Jolt.h"
#include "../vendor/Jolt/RegisterTypes.h"
#include "../vendor/Jolt/Core/Factory.h"
#include "../vendor/Jolt/Core/TempAllocator.h"
#include "../vendor/Jolt/Core/JobSystemSingleThreaded.h"
#include "../vendor/Jolt/Physics/PhysicsSettings.h"
#include "../vendor/Jolt/Physics/PhysicsSystem.h"
#include "../vendor/Jolt/Physics/Body/BodyCreationSettings.h"
#include "../vendor/Jolt/Physics/Body/BodyInterface.h"
#include "../vendor/Jolt/Physics/Collision/BroadPhase/BroadPhaseLayer.h"
#include "../vendor/Jolt/Physics/Collision/Shape/BoxShape.h"
#include "../vendor/Jolt/Physics/Collision/Shape/SphereShape.h"

#include <cstring>
#include <new>
#include <vector>

using namespace JPH;

namespace {

constexpr ObjectLayer kLayerNonMoving = 0;
constexpr ObjectLayer kLayerMoving = 1;
constexpr uint kNumLayers = 2;

// World/body registry limits and boundary error codes (returned negative).
constexpr int kMaxWorlds = 4;
constexpr int kMaxCapacity = 65536;
constexpr int kShapeBox = 0;
constexpr int kShapeSphere = 1;

constexpr int kErrBadArg = -1;
constexpr int kErrNoSlot = -2;
constexpr int kErrBadWorld = -3;
constexpr int kErrFull = -4;
constexpr int kErrBadBody = -5;
constexpr int kErrBadShape = -6;
constexpr int kErrNoBody = -7;
constexpr int kErrNoMem = -8;

class BPLayerInterfaceImpl final : public BroadPhaseLayerInterface {
public:
  BPLayerInterfaceImpl() {
    mObjectToBroadPhase[kLayerNonMoving] = BroadPhaseLayer(0);
    mObjectToBroadPhase[kLayerMoving] = BroadPhaseLayer(1);
  }
  uint GetNumBroadPhaseLayers() const override { return 2; }
  BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer inLayer) const override {
    return mObjectToBroadPhase[inLayer];
  }
#ifdef JPH_TRACK_BROADPHASE_STATS
  const char* GetBroadPhaseLayerName(BroadPhaseLayer inLayer) const override {
    return inLayer == BroadPhaseLayer(0) ? "NON_MOVING" : "MOVING";
  }
#endif

private:
  BroadPhaseLayer mObjectToBroadPhase[kNumLayers];
};

class ObjectVsBroadPhaseLayerFilterImpl final : public ObjectVsBroadPhaseLayerFilter {
public:
  bool ShouldCollide(ObjectLayer inLayer1, BroadPhaseLayer inLayer2) const override {
    if (inLayer1 == kLayerNonMoving) {
      return inLayer2 == BroadPhaseLayer(1);
    }
    return true;
  }
};

class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
public:
  bool ShouldCollide(ObjectLayer inLayer1, ObjectLayer inLayer2) const override {
    if (inLayer1 == kLayerNonMoving) {
      return inLayer2 == kLayerMoving;
    }
    return true;
  }
};

// Ref-counted Jolt registration: probes take a reference for their duration,
// live registry worlds hold one for their whole lifetime.
int g_register_refs = 0;

void register_globals() {
  if (g_register_refs == 0) {
    RegisterDefaultAllocator();
    Factory::sInstance = new Factory();
    RegisterTypes();
  }
  g_register_refs++;
}

void unregister_globals() {
  if (g_register_refs > 0) {
    g_register_refs--;
    if (g_register_refs == 0) {
      UnregisterTypes();
      delete Factory::sInstance;
      Factory::sInstance = nullptr;
    }
  }
}

inline int to_milli(double v) { return (int)(v * 1000.0); }
inline float from_milli(int v) { return (float)v / 1000.0f; }

int g_final_y_milli;
int g_awake;
int g_impulse_vx_milli;

// Bridge-owned state cache for joltb_body_state / joltb_state_* (0.3.0).
int g_state_pos[3];
int g_state_rot[4];
int g_state_vel[3];
int g_state_awake;

struct World {
  TempAllocatorImpl temp_allocator;
  JobSystemSingleThreaded job_system;
  PhysicsSystem physics;
  BPLayerInterfaceImpl bp_layer;
  ObjectVsBroadPhaseLayerFilterImpl ov_bp;
  ObjectLayerPairFilterImpl ov;

  World() : temp_allocator(8 * 1024 * 1024), job_system(cMaxPhysicsJobs) {
    physics.Init(1024, 0, 1024, 1024, bp_layer, ov_bp, ov);
  }
};

// A registry world: one PhysicsSystem plus its allocator/job system/filters,
// the configured gravity and fixed step, and the live body list.  Member
// declaration order is destruction order reversed: the body list and config
// die first, then physics, then the job system and allocator (mirroring the
// probe-local World above).
struct BridgeWorld {
  TempAllocatorImpl temp_allocator;
  JobSystemSingleThreaded job_system;
  PhysicsSystem physics;
  BPLayerInterfaceImpl bp_layer;
  ObjectVsBroadPhaseLayerFilterImpl ov_bp;
  ObjectLayerPairFilterImpl ov;
  Vec3 gravity;
  int fixed_dt_micros;
  uint capacity;
  bool dirty;
  std::vector<BodyID> bodies;

  BridgeWorld(uint inCapacity, Vec3Arg inGravity, int inFixedDtMicros)
      : temp_allocator(8 * 1024 * 1024),
        job_system(cMaxPhysicsJobs),
        gravity(inGravity),
        fixed_dt_micros(inFixedDtMicros),
        capacity(inCapacity),
        dirty(false) {
    physics.Init(inCapacity, 0, inCapacity * 2, inCapacity * 2, bp_layer, ov_bp, ov);
    physics.SetGravity(gravity);
  }
};

BridgeWorld* g_worlds[kMaxWorlds];

BridgeWorld* get_world(int handle) {
  if (handle < 0 || handle >= kMaxWorlds) return nullptr;
  return g_worlds[handle];
}

// Body ids are Jolt's packed index+sequence number: non-negative (sequence
// <= 0xff << 23 plus index <= 0x7fffff fits in int32), stable for the body's
// lifetime, and never reused for a different body, so stale ids are
// rejected by lookup.
int packed_id(const BodyID& inBody) {
  return (int)inBody.GetIndexAndSequenceNumber();
}

BodyID find_body(BridgeWorld* w, int packed) {
  for (size_t i = 0; i < w->bodies.size(); i++) {
    if (packed_id(w->bodies[i]) == packed) return w->bodies[i];
  }
  return BodyID();
}

int run_drop() {
  World w;
  BodyInterface& bi = w.physics.GetBodyInterface();

  BodyCreationSettings ground_settings(new BoxShape(Vec3(20.0f, 0.5f, 20.0f)),
                                       RVec3(0, -0.5, 0), Quat::sIdentity(),
                                       EMotionType::Static, kLayerNonMoving);
  bi.CreateAndAddBody(ground_settings, EActivation::DontActivate);

  BodyCreationSettings box_settings(new BoxShape(Vec3(0.5f, 0.5f, 0.5f)),
                                    RVec3(0, 5, 0), Quat::sIdentity(),
                                    EMotionType::Dynamic, kLayerMoving);
  BodyID box = bi.CreateAndAddBody(box_settings, EActivation::Activate);

  w.physics.OptimizeBroadPhase();
  for (int i = 0; i < 300; i++) {
    w.physics.Update(1.0f / 60.0f, 1, &w.temp_allocator, &w.job_system);
  }

  RVec3 p = bi.GetPosition(box);
  g_final_y_milli = (int)(p.GetY() * 1000.0);
  g_awake = bi.IsActive(box) ? 1 : 0;

  bi.RemoveBody(box);
  bi.DestroyBody(box);
  return 0;
}

int run_impulse() {
  World w;
  BodyInterface& bi = w.physics.GetBodyInterface();

  BodyCreationSettings box_settings(new BoxShape(Vec3(0.5f, 0.5f, 0.5f)),
                                    RVec3(0, 100, 0), Quat::sIdentity(),
                                    EMotionType::Dynamic, kLayerMoving);
  BodyID box = bi.CreateAndAddBody(box_settings, EActivation::Activate);

  bi.SetLinearVelocity(box, Vec3(5.0f, 0, 0));
  w.physics.Update(1.0f / 60.0f, 1, &w.temp_allocator, &w.job_system);

  Vec3 v = bi.GetLinearVelocity(box);
  g_impulse_vx_milli = (int)(v.GetX() * 1000.0f);

  bi.RemoveBody(box);
  bi.DestroyBody(box);
  return 0;
}

} // namespace

extern "C" {

// Drop probe: settled center y in milli (>= 0) or negative error code.
int joltprobe_drop(void) {
  g_final_y_milli = 0;
  g_awake = 0;
  register_globals();
  int rc = run_drop();
  unregister_globals();
  if (rc != 0) return -rc;
  if (g_final_y_milli <= 0) return -90;
  return g_final_y_milli;
}

int joltprobe_awake(void) {
  return g_awake;
}

// Impulse probe: vx in milli after one step (>= 0) or negative error code.
int joltprobe_impulse(void) {
  g_impulse_vx_milli = 0;
  register_globals();
  int rc = run_impulse();
  unregister_globals();
  if (rc != 0) return -rc;
  return g_impulse_vx_milli;
}

// ---- caller-usable world/body surface (0.3.0) ------------------------------

// Create a world (gravity per-axis in milli m/s^2, fixed step in micros, body
// capacity); returns the registry slot handle (>= 0) or a negative code.
int joltb_world_create(int gravity_x_milli, int gravity_y_milli, int gravity_z_milli,
                       int fixed_dt_micros, int capacity) {
  if (fixed_dt_micros <= 0 || capacity <= 0 || capacity > kMaxCapacity) return kErrBadArg;
  int slot = -1;
  for (int i = 0; i < kMaxWorlds; i++) {
    if (g_worlds[i] == nullptr) {
      slot = i;
      break;
    }
  }
  if (slot < 0) return kErrNoSlot;

  register_globals();
  BridgeWorld* w = new (std::nothrow) BridgeWorld(
      (uint)capacity,
      Vec3(from_milli(gravity_x_milli), from_milli(gravity_y_milli), from_milli(gravity_z_milli)),
      fixed_dt_micros);
  if (w == nullptr) {
    unregister_globals();
    return kErrNoMem;
  }
  g_worlds[slot] = w;
  return slot;
}

// Destroy the world and every body in it; returns the number of bodies
// destroyed (>= 0) or a negative code.  Stale handles are rejected.
int joltb_world_destroy(int handle) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  int destroyed = (int)w->bodies.size();
  delete w;
  g_worlds[handle] = nullptr;
  unregister_globals();
  return destroyed;
}

// The world's configured fixed step in microseconds (>= 0) or negative code.
int joltb_world_dt(int handle) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return w->fixed_dt_micros;
}

// Add a box (shape 0: ex/ey/ez half extents in milli) or a sphere (shape 1:
// radius ex in milli); returns the body id (>= 0) or a negative code.
// is_static != 0 creates a static non-moving body.  mass_milli > 0 overrides
// the shape-derived mass on dynamic bodies; 0 keeps Jolt's density default.
// pos in milli; rotation quaternion in milli (all-zero => identity).
int joltb_body_add(int handle, int shape, int ex_milli, int ey_milli, int ez_milli, int mass_milli,
                   int px_milli, int py_milli, int pz_milli,
                   int rx_milli, int ry_milli, int rz_milli, int rw_milli, int is_static) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (shape == kShapeBox) {
    if (ex_milli <= 0 || ey_milli <= 0 || ez_milli <= 0) return kErrBadArg;
  } else if (shape == kShapeSphere) {
    if (ex_milli <= 0) return kErrBadArg;
  } else {
    return kErrBadShape;
  }
  if (w->bodies.size() >= w->capacity) return kErrFull;

  const Shape* shape_ptr = nullptr;
  if (shape == kShapeBox) {
    shape_ptr = new BoxShape(Vec3(from_milli(ex_milli), from_milli(ey_milli), from_milli(ez_milli)));
  } else {
    shape_ptr = new SphereShape(from_milli(ex_milli));
  }

  Quat rotation;
  if (rx_milli == 0 && ry_milli == 0 && rz_milli == 0 && rw_milli == 0) {
    rotation = Quat::sIdentity();
  } else {
    rotation = Quat(from_milli(rx_milli), from_milli(ry_milli), from_milli(rz_milli), from_milli(rw_milli)).Normalized();
  }

  bool is_static_body = is_static != 0;
  EMotionType motion = is_static_body ? EMotionType::Static : EMotionType::Dynamic;
  ObjectLayer layer = is_static_body ? kLayerNonMoving : kLayerMoving;
  EActivation activation = is_static_body ? EActivation::DontActivate : EActivation::Activate;

  BodyCreationSettings settings(shape_ptr,
                                RVec3(from_milli(px_milli), from_milli(py_milli), from_milli(pz_milli)),
                                rotation, motion, layer);
  if (!is_static_body && mass_milli > 0) {
    settings.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
    settings.mMassPropertiesOverride.mMass = from_milli(mass_milli);
  }

  BodyID body = w->physics.GetBodyInterface().CreateAndAddBody(settings, activation);
  if (body.IsInvalid()) return kErrNoBody;
  w->bodies.push_back(body);
  w->dirty = true;
  return packed_id(body);
}

// Remove a body by id; returns the number of bodies left (>= 0) or a
// negative code.  Removed ids are stale and rejected afterwards.
int joltb_body_remove(int handle, int packed) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  for (size_t i = 0; i < w->bodies.size(); i++) {
    if (packed_id(w->bodies[i]) != packed) continue;
    BodyInterface& bi = w->physics.GetBodyInterface();
    bi.RemoveBody(w->bodies[i]);
    bi.DestroyBody(w->bodies[i]);
    w->bodies.erase(w->bodies.begin() + i);
    w->dirty = true;
    return (int)w->bodies.size();
  }
  return kErrBadBody;
}

// Live body count (>= 0) or a negative code.
int joltb_body_count(int handle) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return (int)w->bodies.size();
}

// Advance the world by one fixed step of dt_micros; returns 1 or a negative
// code.  Deterministic: the only clock is dt_micros (no wall time).
int joltb_step(int handle, int dt_micros) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (dt_micros <= 0) return kErrBadArg;
  if (w->dirty) {
    w->physics.OptimizeBroadPhase();
    w->dirty = false;
  }
  w->physics.Update((float)dt_micros / 1000000.0f, 1, &w->temp_allocator, &w->job_system);
  return 1;
}

// Advance the world by `steps` fixed steps of dt_micros; returns the steps
// applied (>= 0) or a negative code.
int joltb_step_n(int handle, int dt_micros, int steps) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (dt_micros <= 0 || steps <= 0) return kErrBadArg;
  if (w->dirty) {
    w->physics.OptimizeBroadPhase();
    w->dirty = false;
  }
  float dt = (float)dt_micros / 1000000.0f;
  for (int i = 0; i < steps; i++) {
    w->physics.Update(dt, 1, &w->temp_allocator, &w->job_system);
  }
  return steps;
}

// Cache one body's state into bridge-owned scalars (no out-param slots);
// joltb_state_* then serve the parts.  Returns 0 or a negative code.
int joltb_body_state(int handle, int packed) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  BodyID body = find_body(w, packed);
  if (body.IsInvalid()) return kErrBadBody;
  BodyInterface& bi = w->physics.GetBodyInterface();
  RVec3 p = bi.GetPosition(body);
  Quat q = bi.GetRotation(body);
  Vec3 v = bi.GetLinearVelocity(body);
  g_state_pos[0] = to_milli(p.GetX());
  g_state_pos[1] = to_milli(p.GetY());
  g_state_pos[2] = to_milli(p.GetZ());
  g_state_rot[0] = to_milli(q.GetX());
  g_state_rot[1] = to_milli(q.GetY());
  g_state_rot[2] = to_milli(q.GetZ());
  g_state_rot[3] = to_milli(q.GetW());
  g_state_vel[0] = to_milli(v.GetX());
  g_state_vel[1] = to_milli(v.GetY());
  g_state_vel[2] = to_milli(v.GetZ());
  g_state_awake = bi.IsActive(body) ? 1 : 0;
  return 0;
}

int joltb_state_pos(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_state_pos[axis];
}

int joltb_state_rot(int axis) {
  if (axis < 0 || axis > 3) return 0;
  return g_state_rot[axis];
}

int joltb_state_vel(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_state_vel[axis];
}

int joltb_state_awake(void) {
  return g_state_awake;
}

} // extern "C"
