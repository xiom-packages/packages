// xiom.jolt -- C bridge over the vendored Jolt Physics core (v5.6.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Layers over one integer ABI (floats cross as milli/micros; XIOM never
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
//   * per-body external input (0.4.0): joltb_body_apply_force /
//     joltb_body_apply_torque accumulate force/torque for the next Update
//     (Jolt clears both automatically after every step; repeated calls before
//     a step accumulate) and wake sleeping bodies (EActivation::Activate);
//     the state cache gains angular velocity so torque effects read back as
//     owned scalars.  Only the integer ABI grows -- no new pointer surface.
//   * world queries + contacts (0.5.0, tiers E1/E2/E7): raycast
//     (closest + any-hit), sphere/capsule closest sweep and sphere/capsule
//     overlap against the world via NarrowPhaseQuery; CAPSULE bodies join
//     the simulation; a ContactListener caches the last step's contact
//     manifolds (pair, points, normal, penetration depth) and the sensor
//     overlaps of bodies created with mIsSensor (non-physical trigger
//     volumes).  Every list surface is canonicalized (ascending packed body
//     id) so repeated runs are bit-identical; all results land in
//     bridge-owned caches and cross as scalars.
// Registration mirrors the upstream HelloWorld sample
// (RegisterDefaultAllocator + Factory + RegisterTypes), ref-counted so probes
// and live worlds can share it.

#include "../vendor/Jolt/Jolt.h"
#include "../vendor/Jolt/RegisterTypes.h"
#include "../vendor/Jolt/Core/Factory.h"
#include "../vendor/Jolt/Core/Reference.h"
#include "../vendor/Jolt/Core/TempAllocator.h"
#include "../vendor/Jolt/Core/JobSystemSingleThreaded.h"
#include "../vendor/Jolt/Physics/PhysicsSettings.h"
#include "../vendor/Jolt/Physics/PhysicsSystem.h"
#include "../vendor/Jolt/Physics/Body/BodyCreationSettings.h"
#include "../vendor/Jolt/Physics/Body/BodyInterface.h"
#include "../vendor/Jolt/Physics/Body/BodyLock.h"
#include "../vendor/Jolt/Physics/Collision/BroadPhase/BroadPhaseLayer.h"
#include "../vendor/Jolt/Physics/Collision/CastResult.h"
#include "../vendor/Jolt/Physics/Collision/CollideShape.h"
#include "../vendor/Jolt/Physics/Collision/CollisionCollectorImpl.h"
#include "../vendor/Jolt/Physics/Collision/ContactListener.h"
#include "../vendor/Jolt/Physics/Collision/NarrowPhaseQuery.h"
#include "../vendor/Jolt/Physics/Collision/RayCast.h"
#include "../vendor/Jolt/Physics/Collision/ShapeCast.h"
#include "../vendor/Jolt/Physics/Collision/Shape/BoxShape.h"
#include "../vendor/Jolt/Physics/Collision/Shape/CapsuleShape.h"
#include "../vendor/Jolt/Physics/Collision/Shape/SphereShape.h"

#include <algorithm>
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
constexpr int kShapeCapsule = 2;

// Query return codes (non-negative; errors stay negative as above).
constexpr int kHitFound = 0;
constexpr int kHitMiss = 1;

// Per-step contact/sensor caches and the points kept per manifold (Jolt
// prunes manifold points to <= 4 for convex pairs; 8 gives headroom).
constexpr size_t kMaxCachedContacts = 2048;
constexpr size_t kMaxCachedSensorEvents = 1024;
constexpr uint kMaxContactPointsPerManifold = 8;

constexpr int kErrBadArg = -1;
constexpr int kErrNoSlot = -2;
constexpr int kErrBadWorld = -3;
constexpr int kErrFull = -4;
constexpr int kErrBadBody = -5;
constexpr int kErrBadShape = -6;
constexpr int kErrNoBody = -7;
constexpr int kErrNoMem = -8;
constexpr int kErrNotSensor = -9;

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

// Bridge-owned state cache for joltb_body_state / joltb_state_* (0.3.0;
// angular velocity added in 0.4.0).
int g_state_pos[3];
int g_state_rot[4];
int g_state_vel[3];
int g_state_avel[3];
int g_state_awake;

// Bridge-owned cache for the single-hit query surfaces (0.5.0): raycast and
// shape sweep write the hit here, the module fetches it as scalars.
int g_query_hit;
int g_query_body;
int g_query_pos[3];
int g_query_nrm[3];
int g_query_fraction_milli;

// Bridge-owned cache for overlap queries (0.5.0): the shape overlap collects
// into a canonical (ascending body id) POD list; joltb_overlap_fetch copies
// one entry into the scalars below for the module to read.  POD storage on
// purpose: the bridge keeps no non-trivial global state.
constexpr int kMaxOverlapEntries = 1024;
struct OverlapEntry {
  int body;
  int pos[3];
};
OverlapEntry g_overlap[kMaxOverlapEntries];
int g_overlap_count;
int g_overlap_body;
int g_overlap_pos[3];

// Bridge-owned fetch cache for contacts (0.5.0): joltb_contact_fetch copies
// one manifold into the scalars below; joltb_contact_point_fetch copies one
// point of that manifold.
int g_contact_body_a;
int g_contact_body_b;
int g_contact_point_count;
int g_contact_normal[3];
int g_contact_depth_micros;
int g_contact_point[3];

// Bridge-owned fetch cache for sensor events (0.5.0).
int g_sensor_event_sensor;
int g_sensor_event_other;

// One cached contact manifold from the last step (contact listener).
struct CachedContact {
  int body_a;
  int body_b;
  float normal_x;
  float normal_y;
  float normal_z;
  float depth;
  int point_count;
  Vec3 points[kMaxContactPointsPerManifold];
};

// One cached sensor overlap pair from the last step.
struct CachedSensorEvent {
  int sensor;
  int other;
};

// Contact listener: caches the active contact manifolds and the sensor
// overlaps of the last Update.  Jolt calls OnContactAdded/OnContactPersisted
// while all bodies are locked (single-threaded here), so we only copy data.
// Manifold convention: body_a < body_b (Jolt body-id order); the normal
// points along the shortest path to move body_b out of the collision.
class ContactCacheListener final : public ContactListener {
public:
  std::vector<CachedContact> contacts;
  std::vector<CachedSensorEvent> sensor_events;

  // Drop the previous step's data (called before every Update).
  void BeginStep() {
    contacts.clear();
    sensor_events.clear();
  }

  // Canonical ascending order so repeated runs read back bit-identical.
  void SortCaches() {
    std::sort(contacts.begin(), contacts.end(), [](const CachedContact &l, const CachedContact &r) {
      if (l.body_a != r.body_a) return l.body_a < r.body_a;
      return l.body_b < r.body_b;
    });
    std::sort(sensor_events.begin(), sensor_events.end(), [](const CachedSensorEvent &l, const CachedSensorEvent &r) {
      if (l.sensor != r.sensor) return l.sensor < r.sensor;
      return l.other < r.other;
    });
  }

  void OnContactAdded(const Body &inBody1, const Body &inBody2, const ContactManifold &inManifold, ContactSettings &ioSettings) override {
    Record(inBody1, inBody2, inManifold, ioSettings);
  }

  void OnContactPersisted(const Body &inBody1, const Body &inBody2, const ContactManifold &inManifold, ContactSettings &ioSettings) override {
    Record(inBody1, inBody2, inManifold, ioSettings);
  }

private:
  void Record(const Body &inBody1, const Body &inBody2, const ContactManifold &inManifold, const ContactSettings &ioSettings) {
    int a = (int)inBody1.GetID().GetIndexAndSequenceNumber();
    int b = (int)inBody2.GetID().GetIndexAndSequenceNumber();
    bool is_sensor =
        ioSettings.mIsSensor || inBody1.IsSensor() || inBody2.IsSensor();
    if (is_sensor) {
      // Sensor volume: report the overlap pair only (no physical response).
      if (sensor_events.size() < kMaxCachedSensorEvents) {
        CachedSensorEvent e;
        e.sensor = inBody1.IsSensor() ? a : b;
        e.other = inBody1.IsSensor() ? b : a;
        sensor_events.push_back(e);
      }
      return;
    }
    if (contacts.size() >= kMaxCachedContacts) return;
    CachedContact c;
    c.body_a = a;
    c.body_b = b;
    c.normal_x = inManifold.mWorldSpaceNormal.GetX();
    c.normal_y = inManifold.mWorldSpaceNormal.GetY();
    c.normal_z = inManifold.mWorldSpaceNormal.GetZ();
    c.depth = inManifold.mPenetrationDepth;
    uint n = inManifold.mRelativeContactPointsOn1.size();
    if (n > kMaxContactPointsPerManifold) n = kMaxContactPointsPerManifold;
    c.point_count = (int)n;
    for (uint i = 0; i < n; i++) {
      RVec3 p = inManifold.GetWorldSpaceContactPointOn1(i);
      c.points[i] = Vec3((float)p.GetX(), (float)p.GetY(), (float)p.GetZ());
    }
    contacts.push_back(c);
  }
};

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
// die first, then physics, then the contact listener/job system/allocator
// (physics is destroyed before the listener it points at).
struct BridgeWorld {
  TempAllocatorImpl temp_allocator;
  JobSystemSingleThreaded job_system;
  ContactCacheListener contact_listener;
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
    physics.SetContactListener(&contact_listener);
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

// Validate shape-kind arguments; returns 0, kErrBadArg or kErrBadShape.
int validate_shape_args(int shape, int ex_milli, int ey_milli, int ez_milli) {
  if (shape == kShapeBox) {
    if (ex_milli <= 0 || ey_milli <= 0 || ez_milli <= 0) return kErrBadArg;
    return 0;
  }
  if (shape == kShapeSphere) {
    if (ex_milli <= 0) return kErrBadArg;
    return 0;
  }
  if (shape == kShapeCapsule) {
    // Capsule: ex = radius, ey = half height of the cylinder segment.
    if (ex_milli <= 0 || ey_milli <= 0) return kErrBadArg;
    return 0;
  }
  return kErrBadShape;
}

// Create a shape by kind (assumes validate_shape_args passed).
const Shape* make_shape(int shape, int ex_milli, int ey_milli, int ez_milli) {
  if (shape == kShapeBox) {
    return new BoxShape(Vec3(from_milli(ex_milli), from_milli(ey_milli), from_milli(ez_milli)));
  }
  if (shape == kShapeSphere) {
    return new SphereShape(from_milli(ex_milli));
  }
  return new CapsuleShape(from_milli(ey_milli), from_milli(ex_milli));
}

// Quaternion from milli components; all-zero => identity (0.3.0 semantics).
Quat quat_from_milli(int rx_milli, int ry_milli, int rz_milli, int rw_milli) {
  if (rx_milli == 0 && ry_milli == 0 && rz_milli == 0 && rw_milli == 0) {
    return Quat::sIdentity();
  }
  return Quat(from_milli(rx_milli), from_milli(ry_milli), from_milli(rz_milli), from_milli(rw_milli)).Normalized();
}

// Shared body creation for joltb_body_add / joltb_body_add_sensor.  Sensors
// are non-physical: forced static on the non-moving layer (they report
// overlaps with dynamic bodies and take no part in collision response).
int add_body_impl(BridgeWorld* w, int shape, int ex_milli, int ey_milli, int ez_milli, int mass_milli,
                  int px_milli, int py_milli, int pz_milli,
                  int rx_milli, int ry_milli, int rz_milli, int rw_milli,
                  bool is_static, bool is_sensor) {
  int rc = validate_shape_args(shape, ex_milli, ey_milli, ez_milli);
  if (rc != 0) return rc;
  if (w->bodies.size() >= w->capacity) return kErrFull;

  const Shape* shape_ptr = make_shape(shape, ex_milli, ey_milli, ez_milli);
  Quat rotation = quat_from_milli(rx_milli, ry_milli, rz_milli, rw_milli);

  bool is_static_body = is_static || is_sensor;
  EMotionType motion = is_static_body ? EMotionType::Static : EMotionType::Dynamic;
  ObjectLayer layer = is_static_body ? kLayerNonMoving : kLayerMoving;
  EActivation activation = is_static_body ? EActivation::DontActivate : EActivation::Activate;

  BodyCreationSettings settings(shape_ptr,
                                RVec3(from_milli(px_milli), from_milli(py_milli), from_milli(pz_milli)),
                                rotation, motion, layer);
  settings.mIsSensor = is_sensor;
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

// Queries read the broadphase like stepping does: optimize it first when the
// body set changed, so the same construction sequence always sees the same
// broadphase state.
void prepare_queries(BridgeWorld* w) {
  if (w->dirty) {
    w->physics.OptimizeBroadPhase();
    w->dirty = false;
  }
}

void clear_query_hit() {
  g_query_hit = 0;
  g_query_body = 0;
  for (int i = 0; i < 3; i++) {
    g_query_pos[i] = 0;
    g_query_nrm[i] = 0;
  }
  g_query_fraction_milli = 0;
}

void store_query_hit(const BodyID& inBody, Vec3Arg inPos, Vec3Arg inNrm, float inFraction) {
  g_query_hit = 1;
  g_query_body = packed_id(inBody);
  g_query_pos[0] = to_milli(inPos.GetX());
  g_query_pos[1] = to_milli(inPos.GetY());
  g_query_pos[2] = to_milli(inPos.GetZ());
  g_query_nrm[0] = to_milli(inNrm.GetX());
  g_query_nrm[1] = to_milli(inNrm.GetY());
  g_query_nrm[2] = to_milli(inNrm.GetZ());
  g_query_fraction_milli = to_milli(inFraction);
}

// World-space surface normal of one body at a world position (raycast hits).
Vec3 body_surface_normal(BridgeWorld* w, const BodyID& inBody, const SubShapeID& inSubShapeID, RVec3Arg inPosition) {
  BodyLockRead lock(w->physics.GetBodyLockInterface(), inBody);
  if (!lock.Succeeded()) return Vec3::sZero();
  return lock.GetBody().GetWorldSpaceSurfaceNormal(inSubShapeID, inPosition);
}

// Closest sphere/capsule sweep along a fixed direction (milli units).  Range
// checks are the caller's job (joltb_sweep_*).
int sweep_closest(BridgeWorld* w, const Shape* inShape, RMat44Arg inStart, Vec3Arg inDirection) {
  RShapeCast cast = RShapeCast::sFromWorldTransform(inShape, Vec3::sReplicate(1.0f), inStart, inDirection);
  ClosestHitCollisionCollector<CastShapeCollector> collector;
  w->physics.GetNarrowPhaseQuery().CastShape(cast, ShapeCastSettings(), RVec3::sZero(), collector);
  if (!collector.HadHit()) return kHitMiss;
  const ShapeCastResult& hit = collector.mHit;
  // Jolt convention: mPenetrationAxis points from the cast shape to the hit
  // body; the hit body's surface normal opposes the approach.
  Vec3 normal = -hit.mPenetrationAxis.NormalizedOr(Vec3::sZero());
  store_query_hit(hit.mBodyID2, hit.mContactPointOn2, normal, hit.mFraction);
  return kHitFound;
}

// Overlap a query shape with the world; the result list is canonicalized to
// ascending packed body-id order (deterministic across runs).  Entries past
// kMaxOverlapEntries are dropped.
int overlap_shape(BridgeWorld* w, const Shape* inShape, RMat44Arg inTransform) {
  CollideShapeSettings settings;
  AllHitCollisionCollector<CollideShapeCollector> collector;
  w->physics.GetNarrowPhaseQuery().CollideShape(inShape, Vec3::sReplicate(1.0f), inTransform, settings, RVec3::sZero(), collector);
  std::sort(collector.mHits.begin(), collector.mHits.end(), [](const CollideShapeResult& l, const CollideShapeResult& r) {
    return packed_id(l.mBodyID2) < packed_id(r.mBodyID2);
  });
  g_overlap_count = 0;
  for (const CollideShapeResult& h : collector.mHits) {
    if (g_overlap_count >= kMaxOverlapEntries) break;
    OverlapEntry& e = g_overlap[g_overlap_count];
    e.body = packed_id(h.mBodyID2);
    e.pos[0] = to_milli(h.mContactPointOn2.GetX());
    e.pos[1] = to_milli(h.mContactPointOn2.GetY());
    e.pos[2] = to_milli(h.mContactPointOn2.GetZ());
    g_overlap_count++;
  }
  return g_overlap_count;
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

// Add a box (shape 0: ex/ey/ez half extents in milli), a sphere (shape 1:
// radius ex in milli) or a capsule (shape 2: radius ex, half height of the
// cylinder segment ey, both in milli); returns the body id (>= 0) or a
// negative code.  is_static != 0 creates a static non-moving body.
// mass_milli > 0 overrides the shape-derived mass on dynamic bodies; 0 keeps
// Jolt's density default.  pos in milli; rotation quaternion in milli
// (all-zero => identity).
int joltb_body_add(int handle, int shape, int ex_milli, int ey_milli, int ez_milli, int mass_milli,
                   int px_milli, int py_milli, int pz_milli,
                   int rx_milli, int ry_milli, int rz_milli, int rw_milli, int is_static) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return add_body_impl(w, shape, ex_milli, ey_milli, ez_milli, mass_milli,
                       px_milli, py_milli, pz_milli,
                       rx_milli, ry_milli, rz_milli, rw_milli,
                       is_static != 0, false);
}

// Add a sensor body (0.5.0): a non-physical trigger volume.  Static on the
// non-moving layer (reports overlaps with dynamic bodies; no collision
// response).  Same shape/pose inputs as joltb_body_add; mass/static are
// implied.  Returns the body id (>= 0) or a negative code.
int joltb_body_add_sensor(int handle, int shape, int ex_milli, int ey_milli, int ez_milli,
                          int px_milli, int py_milli, int pz_milli,
                          int rx_milli, int ry_milli, int rz_milli, int rw_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return add_body_impl(w, shape, ex_milli, ey_milli, ez_milli, 0,
                       px_milli, py_milli, pz_milli,
                       rx_milli, ry_milli, rz_milli, rw_milli,
                       true, true);
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

// Apply an external force (milli-Newtons per axis) at the body's center of
// mass for the next Update; wakes the body (EActivation::Activate).  Jolt
// clears the accumulated force after every Update, so repeated calls before a
// step accumulate and a call without a following step has no effect.  Static
// bodies are a silent no-op (Jolt semantics).  Returns the packed body id
// (>= 0) or a negative code; unknown/removed ids are rejected.
int joltb_body_apply_force(int handle, int packed, int fx_milli, int fy_milli, int fz_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  BodyID body = find_body(w, packed);
  if (body.IsInvalid()) return kErrBadBody;
  w->physics.GetBodyInterface().AddForce(body,
      Vec3(from_milli(fx_milli), from_milli(fy_milli), from_milli(fz_milli)),
      EActivation::Activate);
  return packed;
}

// Apply an external torque (milli Newton-metres per axis) about the body's
// center of mass for the next Update; same accumulation/clear/activation and
// id-rejection semantics as joltb_body_apply_force.
int joltb_body_apply_torque(int handle, int packed, int tx_milli, int ty_milli, int tz_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  BodyID body = find_body(w, packed);
  if (body.IsInvalid()) return kErrBadBody;
  w->physics.GetBodyInterface().AddTorque(body,
      Vec3(from_milli(tx_milli), from_milli(ty_milli), from_milli(tz_milli)),
      EActivation::Activate);
  return packed;
}

// Advance the world by one fixed step of dt_micros; returns 1 or a negative
// code.  Deterministic: the only clock is dt_micros (no wall time).  Contact
// and sensor caches are rebuilt for this step and canonicalized.
int joltb_step(int handle, int dt_micros) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (dt_micros <= 0) return kErrBadArg;
  if (w->dirty) {
    w->physics.OptimizeBroadPhase();
    w->dirty = false;
  }
  w->contact_listener.BeginStep();
  w->physics.Update((float)dt_micros / 1000000.0f, 1, &w->temp_allocator, &w->job_system);
  w->contact_listener.SortCaches();
  return 1;
}

// Advance the world by `steps` fixed steps of dt_micros; returns the steps
// applied (>= 0) or a negative code.  The contact/sensor caches describe the
// last step only.
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
    w->contact_listener.BeginStep();
    w->physics.Update(dt, 1, &w->temp_allocator, &w->job_system);
  }
  w->contact_listener.SortCaches();
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
  Vec3 av = bi.GetAngularVelocity(body);
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
  g_state_avel[0] = to_milli(av.GetX());
  g_state_avel[1] = to_milli(av.GetY());
  g_state_avel[2] = to_milli(av.GetZ());
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

int joltb_state_wvel(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_state_avel[axis];
}

int joltb_state_awake(void) {
  return g_state_awake;
}

// ---- world queries (0.5.0, tier E1) ----------------------------------------

// Closest-hit raycast against the world: kHitFound (0) or kHitMiss (1), or a
// negative code.  The hit (flag, body id, world position, surface normal,
// fraction) lands in the bridge-owned query cache.
int joltb_raycast_closest(int handle, int ox_milli, int oy_milli, int oz_milli,
                          int dx_milli, int dy_milli, int dz_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (dx_milli == 0 && dy_milli == 0 && dz_milli == 0) return kErrBadArg;
  prepare_queries(w);
  clear_query_hit();
  RRayCast ray(RVec3(from_milli(ox_milli), from_milli(oy_milli), from_milli(oz_milli)),
               Vec3(from_milli(dx_milli), from_milli(dy_milli), from_milli(dz_milli)));
  RayCastResult hit;
  if (!w->physics.GetNarrowPhaseQuery().CastRay(ray, hit)) return kHitMiss;
  RVec3 point = ray.GetPointOnRay(hit.mFraction);
  Vec3 normal = body_surface_normal(w, hit.mBodyID, hit.mSubShapeID2, point);
  store_query_hit(hit.mBodyID,
                  Vec3((float)point.GetX(), (float)point.GetY(), (float)point.GetZ()),
                  normal, hit.mFraction);
  return kHitFound;
}

// Any-hit raycast: stops at the first hit the traversal meets (not
// necessarily the closest).  Same cache and return codes as the closest cast.
int joltb_raycast_any(int handle, int ox_milli, int oy_milli, int oz_milli,
                      int dx_milli, int dy_milli, int dz_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (dx_milli == 0 && dy_milli == 0 && dz_milli == 0) return kErrBadArg;
  prepare_queries(w);
  clear_query_hit();
  RRayCast ray(RVec3(from_milli(ox_milli), from_milli(oy_milli), from_milli(oz_milli)),
               Vec3(from_milli(dx_milli), from_milli(dy_milli), from_milli(dz_milli)));
  AnyHitCollisionCollector<CastRayCollector> collector;
  w->physics.GetNarrowPhaseQuery().CastRay(ray, RayCastSettings(), collector);
  if (!collector.HadHit()) return kHitMiss;
  const RayCastResult& hit = collector.mHit;
  RVec3 point = ray.GetPointOnRay(hit.mFraction);
  Vec3 normal = body_surface_normal(w, hit.mBodyID, hit.mSubShapeID2, point);
  store_query_hit(hit.mBodyID,
                  Vec3((float)point.GetX(), (float)point.GetY(), (float)point.GetZ()),
                  normal, hit.mFraction);
  return kHitFound;
}

// Closest sphere sweep along (dx,dy,dz) (milli): kHitFound/kHitMiss or a
// negative code.  The normal is the hit body's surface normal at the contact.
// The query shape is owned by a RefConst (a freshly new'd Shape starts at
// refcount 0; RefConst AddRef's it and deletes it on scope exit).
int joltb_sweep_sphere_closest(int handle, int radius_milli,
                               int px_milli, int py_milli, int pz_milli,
                               int dx_milli, int dy_milli, int dz_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (radius_milli <= 0) return kErrBadArg;
  if (dx_milli == 0 && dy_milli == 0 && dz_milli == 0) return kErrBadArg;
  prepare_queries(w);
  clear_query_hit();
  RefConst<Shape> shape = new SphereShape(from_milli(radius_milli));
  RMat44 start = RMat44::sTranslation(RVec3(from_milli(px_milli), from_milli(py_milli), from_milli(pz_milli)));
  return sweep_closest(w, shape, start, Vec3(from_milli(dx_milli), from_milli(dy_milli), from_milli(dz_milli)));
}

// Closest capsule sweep: radius + half height of the cylinder segment in
// milli, pose (position + quaternion) and direction.  The capsule's local
// axis is +Y before the rotation is applied.
int joltb_sweep_capsule_closest(int handle, int radius_milli, int half_height_milli,
                                int px_milli, int py_milli, int pz_milli,
                                int rx_milli, int ry_milli, int rz_milli, int rw_milli,
                                int dx_milli, int dy_milli, int dz_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (radius_milli <= 0 || half_height_milli <= 0) return kErrBadArg;
  if (dx_milli == 0 && dy_milli == 0 && dz_milli == 0) return kErrBadArg;
  prepare_queries(w);
  clear_query_hit();
  RefConst<Shape> shape = new CapsuleShape(from_milli(half_height_milli), from_milli(radius_milli));
  Quat rotation = quat_from_milli(rx_milli, ry_milli, rz_milli, rw_milli);
  RMat44 start = RMat44::sRotationTranslation(rotation,
      RVec3(from_milli(px_milli), from_milli(py_milli), from_milli(pz_milli)));
  return sweep_closest(w, shape, start, Vec3(from_milli(dx_milli), from_milli(dy_milli), from_milli(dz_milli)));
}

// Overlap a sphere with the world: number of hit bodies (>= 0) or a negative
// code.  The canonical list (ascending body id) is read back with
// joltb_overlap_fetch / joltb_overlap_body / joltb_overlap_pos.
int joltb_overlap_sphere(int handle, int radius_milli, int px_milli, int py_milli, int pz_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (radius_milli <= 0) return kErrBadArg;
  prepare_queries(w);
  RefConst<Shape> shape = new SphereShape(from_milli(radius_milli));
  return overlap_shape(w, shape, RMat44::sTranslation(RVec3(from_milli(px_milli), from_milli(py_milli), from_milli(pz_milli))));
}

// Overlap a capsule (radius + half height, pose) with the world; same
// canonical read-back as joltb_overlap_sphere.
int joltb_overlap_capsule(int handle, int radius_milli, int half_height_milli,
                          int px_milli, int py_milli, int pz_milli,
                          int rx_milli, int ry_milli, int rz_milli, int rw_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (radius_milli <= 0 || half_height_milli <= 0) return kErrBadArg;
  prepare_queries(w);
  RefConst<Shape> shape = new CapsuleShape(from_milli(half_height_milli), from_milli(radius_milli));
  Quat rotation = quat_from_milli(rx_milli, ry_milli, rz_milli, rw_milli);
  RMat44 transform = RMat44::sRotationTranslation(rotation,
      RVec3(from_milli(px_milli), from_milli(py_milli), from_milli(pz_milli)));
  return overlap_shape(w, shape, transform);
}

// Fetch overlap entry `index` into the owned scalars; 0 or a negative code.
int joltb_overlap_fetch(int handle, int index) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (index < 0 || index >= g_overlap_count) return kErrBadArg;
  g_overlap_body = g_overlap[index].body;
  g_overlap_pos[0] = g_overlap[index].pos[0];
  g_overlap_pos[1] = g_overlap[index].pos[1];
  g_overlap_pos[2] = g_overlap[index].pos[2];
  return 0;
}

int joltb_overlap_body(void) {
  return g_overlap_body;
}

int joltb_overlap_pos(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_overlap_pos[axis];
}

int joltb_query_hit(void) {
  return g_query_hit;
}

int joltb_query_body(void) {
  return g_query_body;
}

int joltb_query_pos(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_query_pos[axis];
}

int joltb_query_nrm(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_query_nrm[axis];
}

int joltb_query_fraction(void) {
  return g_query_fraction_milli;
}

// ---- contacts + sensors (0.5.0, tier E7) -----------------------------------

// Number of cached active contact manifolds from the last step (>= 0) or a
// negative code.  Only active bodies report contacts (sleeping bodies do
// not), and at most one manifold per body/sub-shape pair per step.
int joltb_contact_count(int handle) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return (int)w->contact_listener.contacts.size();
}

// Fetch contact entry `index` into the owned scalars (bodies, point count,
// normal, penetration depth, first point); 0 or a negative code.
int joltb_contact_fetch(int handle, int index) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (index < 0 || index >= (int)w->contact_listener.contacts.size()) return kErrBadArg;
  const CachedContact& c = w->contact_listener.contacts[index];
  g_contact_body_a = c.body_a;
  g_contact_body_b = c.body_b;
  g_contact_point_count = c.point_count;
  g_contact_normal[0] = to_milli(c.normal_x);
  g_contact_normal[1] = to_milli(c.normal_y);
  g_contact_normal[2] = to_milli(c.normal_z);
  g_contact_depth_micros = (int)(c.depth * 1000000.0);
  if (c.point_count > 0) {
    g_contact_point[0] = to_milli(c.points[0].GetX());
    g_contact_point[1] = to_milli(c.points[0].GetY());
    g_contact_point[2] = to_milli(c.points[0].GetZ());
  } else {
    g_contact_point[0] = 0;
    g_contact_point[1] = 0;
    g_contact_point[2] = 0;
  }
  return 0;
}

// Fetch point `point` of contact entry `index` into the owned point scalars;
// 0 or a negative code.
int joltb_contact_point_fetch(int handle, int index, int point) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (index < 0 || index >= (int)w->contact_listener.contacts.size()) return kErrBadArg;
  const CachedContact& c = w->contact_listener.contacts[index];
  if (point < 0 || point >= c.point_count) return kErrBadArg;
  g_contact_point[0] = to_milli(c.points[point].GetX());
  g_contact_point[1] = to_milli(c.points[point].GetY());
  g_contact_point[2] = to_milli(c.points[point].GetZ());
  return 0;
}

// Number of cached manifolds between two live bodies (either order) in the
// last step; unknown or removed ids are rejected (kErrBadBody).
int joltb_contact_pair_count(int handle, int body_a, int body_b) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (find_body(w, body_a).IsInvalid()) return kErrBadBody;
  if (find_body(w, body_b).IsInvalid()) return kErrBadBody;
  int n = 0;
  for (size_t i = 0; i < w->contact_listener.contacts.size(); i++) {
    const CachedContact& c = w->contact_listener.contacts[i];
    if ((c.body_a == body_a && c.body_b == body_b) ||
        (c.body_a == body_b && c.body_b == body_a)) {
      n++;
    }
  }
  return n;
}

int joltb_contact_body_a(void) {
  return g_contact_body_a;
}

int joltb_contact_body_b(void) {
  return g_contact_body_b;
}

int joltb_contact_point_count(void) {
  return g_contact_point_count;
}

int joltb_contact_normal(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_contact_normal[axis];
}

int joltb_contact_depth_micros(void) {
  return g_contact_depth_micros;
}

int joltb_contact_point(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_contact_point[axis];
}

// Number of cached sensor overlap events from the last step (>= 0) or a
// negative code.
int joltb_sensor_event_count(int handle) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return (int)w->contact_listener.sensor_events.size();
}

// Fetch sensor event `index` into the owned scalars (sensor id + other body
// id); 0 or a negative code.
int joltb_sensor_event_fetch(int handle, int index) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (index < 0 || index >= (int)w->contact_listener.sensor_events.size()) return kErrBadArg;
  const CachedSensorEvent& e = w->contact_listener.sensor_events[index];
  g_sensor_event_sensor = e.sensor;
  g_sensor_event_other = e.other;
  return 0;
}

int joltb_sensor_event_sensor(void) {
  return g_sensor_event_sensor;
}

int joltb_sensor_event_other(void) {
  return g_sensor_event_other;
}

// Number of cached overlaps for one sensor in the last step (>= 0) or a
// negative code; unknown/removed ids yield kErrBadBody and a live non-sensor
// id yields kErrNotSensor.
int joltb_sensor_overlap_count(int handle, int sensor_id) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  BodyID body = find_body(w, sensor_id);
  if (body.IsInvalid()) return kErrBadBody;
  BodyLockRead lock(w->physics.GetBodyLockInterface(), body);
  if (!lock.Succeeded()) return kErrBadBody;
  if (!lock.GetBody().IsSensor()) return kErrNotSensor;
  int n = 0;
  for (size_t i = 0; i < w->contact_listener.sensor_events.size(); i++) {
    if (w->contact_listener.sensor_events[i].sensor == sensor_id) n++;
  }
  return n;
}

} // extern "C"
