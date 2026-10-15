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
//   * typed joints (0.6.0, tier E3): a per-world joint registry holds
//     Ref<Constraint> handles -- fixed/hinge/slider/point constraints between
//     two live bodies or between one live body and Body::sFixedToWorld (the
//     "world" sentinel).  Creation takes world-space anchors/axes in milli;
//     hinge/slider motors (velocity/position targets) and limits
//     (min/max angle or translation) are configured at creation and driven
//     with joltb_joint_set_motor.  State read-back caches the current hinge
//     angle / slider position and the applied total lambda (motor impulse
//     where a motor exists, reaction impulse otherwise).  Typed errors cover
//     bad body ids, unsupported kinds/combos and invalid limits.
//   * convex + compound bodies (0.6.0, tier E6): joltb_body_add_convex
//     builds a ConvexHullShape from a caller-supplied int64 milli xyz
//     triples buffer (copied bridge-side; the XIOM Vec stays owned by the
//     caller); joltb_body_add_compound builds a StaticCompoundShape from a
//     flat part table (kind/extents/vertex-slice/local pose per part,
//     box/sphere/capsule/convex) over the same vertex buffer.  Both body
//     kinds simulate (mass/pose/static as usual) and take part in every E1
//     query and E7 contact/sensor surface with no extra code.
//   * soft bodies (0.7.0, tier E4): joltb_soft_add builds a
//     SoftBodySharedSettings from a preset (cloth grid / rope / volume cube)
//     and a caller-driven size description, optimizes it and creates a soft
//     body in the world; joltb_soft_state / joltb_soft_vertex cache owned
//     scalars (vertex count, world-space particle position/velocity) and
//     joltb_soft_vertices_into writes every world-space particle position
//     into a caller-owned int64 milli buffer (the one out-buffer surface in
//     the package, bounded and capacity-checked).  Typed errors cover bad
//     presets, unknown/removed ids, out-of-range indices and short buffers.
//   * heightfield terrain (0.7.0, tier E5): joltb_body_add_heightfield
//     builds a static HeightFieldShape from a caller-owned int64 milli
//     height-sample grid (square, row major), horizontal scale (sample
//     spacing in milli) and vertical scale (the sample value that equals
//     1.0), with a caller-chosen quantization (8/16 bits; 0 = Jolt default
//     8).  The terrain body then takes part in every existing surface:
//     rigid bodies settle on it, E1 raycasts hit it (height/normal) and
//     contacts report against it.
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
#include "../vendor/Jolt/Physics/Collision/Shape/CompoundShape.h"
#include "../vendor/Jolt/Physics/Collision/Shape/ConvexHullShape.h"
#include "../vendor/Jolt/Physics/Collision/Shape/HeightFieldShape.h"
#include "../vendor/Jolt/Physics/Collision/Shape/SphereShape.h"
#include "../vendor/Jolt/Physics/Collision/Shape/StaticCompoundShape.h"
#include "../vendor/Jolt/Physics/Constraints/Constraint.h"
#include "../vendor/Jolt/Physics/Constraints/FixedConstraint.h"
#include "../vendor/Jolt/Physics/Constraints/HingeConstraint.h"
#include "../vendor/Jolt/Physics/Constraints/PointConstraint.h"
#include "../vendor/Jolt/Physics/Constraints/SliderConstraint.h"
#include "../vendor/Jolt/Physics/Constraints/TwoBodyConstraint.h"
#include "../vendor/Jolt/Physics/SoftBody/SoftBodyCreationSettings.h"
#include "../vendor/Jolt/Physics/SoftBody/SoftBodyMotionProperties.h"
#include "../vendor/Jolt/Physics/SoftBody/SoftBodySharedSettings.h"

#include <algorithm>
#include <cmath>
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
constexpr int kShapeConvex = 3;   // 0.6.0: hull from a vertex set (E6)
constexpr int kShapeCompound = 4; // 0.6.0: multi-shape body (E6)

// Typed joint surface (0.6.0, tier E3).
constexpr int kJointWorld = -1;
constexpr int kJointFixed = 0;
constexpr int kJointHinge = 1;
constexpr int kJointSlider = 2;
constexpr int kJointPoint = 3;
constexpr int kMotorOff = 0;
constexpr int kMotorVelocity = 1;
constexpr int kMotorPosition = 2;

// E6 shape-building limits (compound part table stride matches jolt.xi).
constexpr int kPartStride = 13;
constexpr int kMinHullVertices = 4;
constexpr int kMaxHullVertices = 256;
constexpr int kMaxCompoundParts = 64;

// E4 soft body presets and size limits (0.7.0).
constexpr int kSoftGrid = 0;    // cloth: nx by nz particle grid
constexpr int kSoftRope = 1;    // chain: nx particles along +x
constexpr int kSoftVolume = 2;  // cube: nx^3 particles with volume constraints
constexpr int kMinSoftGridDim = 2;
constexpr int kMaxSoftGridDim = 64;
constexpr int kMinSoftRopeCount = 2;
constexpr int kMaxSoftRopeCount = 256;
constexpr int kMinSoftVolumeDim = 2;
constexpr int kMaxSoftVolumeDim = 8;
constexpr int kMaxSoftSpacingMilli = 100000;

// E5 heightfield limits (0.7.0): square sample grids, 4..257 samples per
// side (Jolt rounds up to its block size internally; 2x2 blocks minimum).
constexpr int kMinHeightfieldSamples = 4;
constexpr int kMaxHeightfieldSamples = 257;

// Hinge limits are [-pi, pi] in milli radians (Jolt asserts this range).
constexpr int kPiMilli = 3142;

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
constexpr int kErrBadJoint = -10;     // unknown/removed joint id
constexpr int kErrBadJointKind = -11; // unsupported joint kind
constexpr int kErrNoMotor = -12;      // motor op on a joint without a motor
constexpr int kErrBadHull = -13;      // hull vertex count/build failure
constexpr int kErrBadCompound = -14;  // invalid compound part table
constexpr int kErrBadLimits = -15;    // out-of-range/inverted limits
constexpr int kErrBadSoft = -16;      // unknown/removed soft body id
constexpr int kErrBadSoftArgs = -17;  // invalid soft body preset/size args
constexpr int kErrBadHeightfield = -18; // invalid heightfield sample grid
constexpr int kErrBadBuffer = -19;    // caller read-back buffer too small

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

// Bridge-owned fetch cache for joint state (0.6.0): joltb_joint_state copies
// the kind/primary/impulse/pair into the scalars below for the module.
int g_joint_kind;
int g_joint_primary_milli;
int g_joint_impulse_milli;
int g_joint_body_a;
int g_joint_body_b;

// Bridge-owned fetch caches for soft bodies (0.7.0): joltb_soft_state copies
// the vertex count / center / awake flag, joltb_soft_vertex copies one
// particle's world-space position and velocity.
int g_soft_vertex_count;
int g_soft_pos[3];
int g_soft_awake;
int g_soft_vtx_pos[3];
int g_soft_vtx_vel[3];

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

// One live typed joint (0.6.0): a bridge-assigned joint id, the kind, the
// packed body ids (kJointWorld for the fixed world) and the owning Ref.
// The Ref keeps the constraint alive while it is registered in the physics
// system; removal drops both.
struct BridgeJoint {
  int id;
  int kind;
  int body_a;
  int body_b;
  Ref<Constraint> constraint;
};

// One live soft body (0.7.0): a bridge-assigned id, the body id and the
// owning shared-settings Ref (kept alive for the body's lifetime; the body's
// motion properties hold their own reference too).
struct BridgeSoft {
  int id;
  BodyID body;
  RefConst<SoftBodySharedSettings> settings;
  int vertex_count;
};

// A registry world: one PhysicsSystem plus its allocator/job system/filters,
// the configured gravity and fixed step, and the live body list.  Member
// declaration order is destruction order reversed: the body/joint lists die
// first, then physics, then the contact listener/job system/allocator
// (physics is destroyed before the listener it points at; joints are removed
// explicitly in joltb_world_destroy so no Ref outlives its bodies).
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
  std::vector<BridgeJoint> joints;
  std::vector<BridgeSoft> soft_bodies;
  int next_joint_id;
  int next_soft_id;

  BridgeWorld(uint inCapacity, Vec3Arg inGravity, int inFixedDtMicros)
      : temp_allocator(8 * 1024 * 1024),
        job_system(cMaxPhysicsJobs),
        gravity(inGravity),
        fixed_dt_micros(inFixedDtMicros),
        capacity(inCapacity),
        dirty(false),
        next_joint_id(0),
        next_soft_id(0) {
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

// Shared body creation from an already-built shape (0.6.0: also used by the
// convex and compound paths).  Sensors are non-physical: forced static on the
// non-moving layer (they report overlaps with dynamic bodies and take no part
// in collision response).
int register_body_with_shape(BridgeWorld* w, const Shape* inShape, int mass_milli,
                             int px_milli, int py_milli, int pz_milli,
                             int rx_milli, int ry_milli, int rz_milli, int rw_milli,
                             bool is_static, bool is_sensor) {
  if (inShape == nullptr) return kErrBadShape;
  if (w->bodies.size() >= w->capacity) return kErrFull;

  Quat rotation = quat_from_milli(rx_milli, ry_milli, rz_milli, rw_milli);

  bool is_static_body = is_static || is_sensor;
  EMotionType motion = is_static_body ? EMotionType::Static : EMotionType::Dynamic;
  ObjectLayer layer = is_static_body ? kLayerNonMoving : kLayerMoving;
  EActivation activation = is_static_body ? EActivation::DontActivate : EActivation::Activate;

  BodyCreationSettings settings(inShape,
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

// Shared body creation for joltb_body_add / joltb_body_add_sensor.
int add_body_impl(BridgeWorld* w, int shape, int ex_milli, int ey_milli, int ez_milli, int mass_milli,
                  int px_milli, int py_milli, int pz_milli,
                  int rx_milli, int ry_milli, int rz_milli, int rw_milli,
                  bool is_static, bool is_sensor) {
  int rc = validate_shape_args(shape, ex_milli, ey_milli, ez_milli);
  if (rc != 0) return rc;

  const Shape* shape_ptr = make_shape(shape, ex_milli, ey_milli, ez_milli);
  return register_body_with_shape(w, shape_ptr, mass_milli,
                                  px_milli, py_milli, pz_milli,
                                  rx_milli, ry_milli, rz_milli, rw_milli,
                                  is_static, is_sensor);
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

// ---- typed joints (0.6.0, tier E3) -----------------------------------------

BridgeJoint* find_joint(BridgeWorld* w, int joint_id) {
  for (size_t i = 0; i < w->joints.size(); i++) {
    if (w->joints[i].id == joint_id) return &w->joints[i];
  }
  return nullptr;
}

// Resolve a packed body id to a Body&, with the world sentinel mapping to
// Body::sFixedToWorld (Jolt's documented "attach to the world" body).
Body* resolve_joint_body(BridgeWorld* w, int packed) {
  if (packed == kJointWorld) return &Body::sFixedToWorld;
  BodyID id = find_body(w, packed);
  if (id.IsInvalid()) return nullptr;
  return w->physics.GetBodyLockInterface().TryGetBody(id);
}

// A normalized world-space axis from milli components; false when degenerate.
bool world_axis_from_milli(int ax_milli, int ay_milli, int az_milli, Vec3& out) {
  Vec3 v(from_milli(ax_milli), from_milli(ay_milli), from_milli(az_milli));
  if (v.LengthSq() <= 1.0e-6f) return false;
  out = v.Normalized();
  return true;
}

// A stable perpendicular to a unit axis (pick the least-aligned basis axis).
Vec3 perpendicular_axis(Vec3Arg inAxis) {
  Vec3 helper = std::fabs(inAxis.GetY()) < 0.99f ? Vec3(0, 1, 0) : Vec3(1, 0, 0);
  return inAxis.Cross(helper).NormalizedOr(Vec3(0, 0, 1));
}

// Joint creation inputs (milli units; psi = world anchor, axis = hinge/slider
// axis in world space).
struct JointArgs {
  int kind;
  int body_a;
  int body_b;
  int px_milli, py_milli, pz_milli;
  int ax_milli, ay_milli, az_milli;
  bool auto_anchor;
  bool has_limits;
  int limits_min_milli;
  int limits_max_milli;
  int motor_frequency_milli;
  int motor_damping_milli;
  int motor_max_force_milli;
  int motor_max_torque_milli;
};

// Motor settings from the desc: Jolt's default (2 Hz, critical damping,
// unlimited force/torque) unless the caller overrides.  Frequency/damping
// overrides must both be sane; limits are mirrored onto both kinds.
bool build_motor_settings(const JointArgs& j, MotorSettings& out) {
  if (j.motor_frequency_milli < 0) return false;
  if (j.motor_damping_milli < 0) return false;
  if (j.motor_damping_milli != 0 && j.motor_frequency_milli <= 0) return false;
  if (j.motor_max_force_milli < 0 || j.motor_max_torque_milli < 0) return false;
  out = MotorSettings();
  if (j.motor_frequency_milli > 0) {
    out.mSpringSettings = SpringSettings(ESpringMode::FrequencyAndDamping,
                                         from_milli(j.motor_frequency_milli),
                                         from_milli(j.motor_damping_milli));
  }
  if (j.motor_max_force_milli > 0) out.SetForceLimit(from_milli(j.motor_max_force_milli));
  if (j.motor_max_torque_milli > 0) out.SetTorqueLimit(from_milli(j.motor_max_torque_milli));
  return out.IsValid();
}

// Create a typed joint; returns the bridge joint id (>= 0) or a negative
// code.  At least one side must be a live dynamic-capable body (Jolt asserts
// on two non-dynamic bodies); the world sentinel may appear on either side.
int add_joint_impl(BridgeWorld* w, const JointArgs& j) {
  if (j.kind < kJointFixed || j.kind > kJointPoint) return kErrBadJointKind;
  if (j.body_a == j.body_b) return kErrBadArg;
  Body* body_a = resolve_joint_body(w, j.body_a);
  Body* body_b = resolve_joint_body(w, j.body_b);
  if (body_a == nullptr || body_b == nullptr) return kErrBadBody;
  if (!body_a->IsDynamic() && !body_b->IsDynamic()) return kErrBadArg;

  const bool has_motor_config = j.motor_frequency_milli != 0 || j.motor_damping_milli != 0 ||
                                j.motor_max_force_milli != 0 || j.motor_max_torque_milli != 0;
  if (has_motor_config && j.kind != kJointHinge && j.kind != kJointSlider) return kErrNoMotor;
  if (j.has_limits && j.kind != kJointHinge && j.kind != kJointSlider) return kErrBadArg;
  if (j.has_limits) {
    if (j.limits_min_milli > 0 || j.limits_max_milli < 0) return kErrBadLimits;
    if (j.kind == kJointHinge &&
        (j.limits_min_milli < -kPiMilli || j.limits_max_milli > kPiMilli)) return kErrBadLimits;
  }
  if (j.auto_anchor && j.kind != kJointFixed && j.kind != kJointSlider) return kErrBadArg;

  MotorSettings motor;
  if ((j.kind == kJointHinge || j.kind == kJointSlider) && !build_motor_settings(j, motor)) {
    return kErrBadArg;
  }

  const RVec3 anchor(from_milli(j.px_milli), from_milli(j.py_milli), from_milli(j.pz_milli));
  Ref<Constraint> constraint;
  switch (j.kind) {
    case kJointFixed: {
      FixedConstraintSettings settings;
      settings.mSpace = EConstraintSpace::WorldSpace;
      if (j.auto_anchor) {
        settings.mAutoDetectPoint = true;
      } else {
        settings.mPoint1 = anchor;
        settings.mPoint2 = anchor;
      }
      constraint = settings.Create(*body_a, *body_b);
      break;
    }
    case kJointHinge: {
      Vec3 axis;
      if (!world_axis_from_milli(j.ax_milli, j.ay_milli, j.az_milli, axis)) return kErrBadArg;
      Vec3 normal = perpendicular_axis(axis);
      HingeConstraintSettings settings;
      settings.mSpace = EConstraintSpace::WorldSpace;
      settings.mPoint1 = anchor;
      settings.mPoint2 = anchor;
      settings.mHingeAxis1 = axis;
      settings.mHingeAxis2 = axis;
      settings.mNormalAxis1 = normal;
      settings.mNormalAxis2 = normal;
      if (j.has_limits) {
        settings.mLimitsMin = from_milli(j.limits_min_milli);
        settings.mLimitsMax = from_milli(j.limits_max_milli);
      }
      settings.mMotorSettings = motor;
      constraint = settings.Create(*body_a, *body_b);
      break;
    }
    case kJointSlider: {
      Vec3 axis;
      if (!world_axis_from_milli(j.ax_milli, j.ay_milli, j.az_milli, axis)) return kErrBadArg;
      Vec3 normal = perpendicular_axis(axis);
      SliderConstraintSettings settings;
      settings.mSpace = EConstraintSpace::WorldSpace;
      settings.mAutoDetectPoint = j.auto_anchor;
      settings.mPoint1 = anchor;
      settings.mPoint2 = anchor;
      settings.mSliderAxis1 = axis;
      settings.mSliderAxis2 = axis;
      settings.mNormalAxis1 = normal;
      settings.mNormalAxis2 = normal;
      if (j.has_limits) {
        settings.mLimitsMin = from_milli(j.limits_min_milli);
        settings.mLimitsMax = from_milli(j.limits_max_milli);
      }
      settings.mMotorSettings = motor;
      constraint = settings.Create(*body_a, *body_b);
      break;
    }
    default: { // kJointPoint
      PointConstraintSettings settings;
      settings.mSpace = EConstraintSpace::WorldSpace;
      settings.mPoint1 = anchor;
      settings.mPoint2 = anchor;
      constraint = settings.Create(*body_a, *body_b);
      break;
    }
  }
  if (constraint == nullptr) return kErrNoBody;

  BridgeJoint joint;
  joint.id = w->next_joint_id++;
  joint.kind = j.kind;
  joint.body_a = j.body_a;
  joint.body_b = j.body_b;
  joint.constraint = constraint;
  w->joints.push_back(joint);
  w->physics.AddConstraint(constraint.GetPtr());
  return joint.id;
}

// Remove every joint that references a packed body id (called before the body
// is destroyed: Jolt forbids removing a body a constraint still references).
void remove_joints_for_body(BridgeWorld* w, int packed) {
  for (size_t i = 0; i < w->joints.size();) {
    if (w->joints[i].body_a == packed || w->joints[i].body_b == packed) {
      w->physics.RemoveConstraint(w->joints[i].constraint.GetPtr());
      w->joints.erase(w->joints.begin() + i);
    } else {
      i++;
    }
  }
}

// ---- convex + compound shapes (0.6.0, tier E6) ------------------------------

// Build a ConvexHullShape from a caller buffer of int64 milli xyz triples
// (copied bridge-side; the caller's Vec is untouched).  `ok` is false when
// the vertex count is out of range or the hull builder rejects the points
// (e.g. all points collinear/coincident).
RefConst<Shape> build_hull_shape(const int64_t* inVerts, int inVertCount, bool& ok) {
  ok = false;
  if (inVertCount < kMinHullVertices || inVertCount > kMaxHullVertices) return RefConst<Shape>();
  std::vector<Vec3> points;
  points.reserve((size_t)inVertCount);
  for (int i = 0; i < inVertCount; i++) {
    points.push_back(Vec3(from_milli((int)inVerts[3 * i + 0]),
                          from_milli((int)inVerts[3 * i + 1]),
                          from_milli((int)inVerts[3 * i + 2])));
  }
  ConvexHullShapeSettings settings(points.data(), (int)points.size());
  ShapeSettings::ShapeResult result = settings.Create();
  if (result.HasError()) return RefConst<Shape>();
  ok = true;
  return result.Get();
}

// Build a StaticCompoundShape from a flat part table (kPartStride int64
// entries per part: kind, ex, ey, ez, vertex offset, vertex count, local
// position (3), local rotation quaternion (4), all milli; the vertex offset/
// count are only read for convex parts).  Convex parts slice the shared
// vertex buffer.  `ok` is false on any malformed part or failed child build.
RefConst<Shape> build_compound_shape(const int64_t* inParts, int inPartCount,
                                     const int64_t* inVerts, int inVertCount, bool& ok) {
  ok = false;
  if (inPartCount <= 0 || inPartCount > kMaxCompoundParts) return RefConst<Shape>();
  StaticCompoundShapeSettings settings;
  for (int i = 0; i < inPartCount; i++) {
    const int64_t* p = inParts + (size_t)i * kPartStride;
    const int kind = (int)p[0];
    const int ex_milli = (int)p[1];
    const int ey_milli = (int)p[2];
    const int ez_milli = (int)p[3];
    const int vtx_offset = (int)p[4];
    const int vtx_count = (int)p[5];
    const Vec3 part_pos(from_milli((int)p[6]), from_milli((int)p[7]), from_milli((int)p[8]));
    const Quat part_rot = quat_from_milli((int)p[9], (int)p[10], (int)p[11], (int)p[12]);

    RefConst<Shape> child;
    if (kind == kShapeBox || kind == kShapeSphere || kind == kShapeCapsule) {
      if (validate_shape_args(kind, ex_milli, ey_milli, ez_milli) != 0) return RefConst<Shape>();
      child = make_shape(kind, ex_milli, ey_milli, ez_milli);
    } else if (kind == kShapeConvex) {
      if (vtx_offset < 0 || vtx_count < kMinHullVertices || vtx_offset + vtx_count > inVertCount) {
        return RefConst<Shape>();
      }
      bool hull_ok = false;
      child = build_hull_shape(inVerts + (size_t)vtx_offset * 3, vtx_count, hull_ok);
      if (!hull_ok) return RefConst<Shape>();
    } else {
      return RefConst<Shape>();
    }
    settings.AddShape(part_pos, part_rot, child.GetPtr());
  }
  ShapeSettings::ShapeResult result = settings.Create();
  if (result.HasError()) return RefConst<Shape>();
  ok = true;
  return result.Get();
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

// ---- soft bodies (0.7.0, tier E4) -------------------------------------------

// Soft body creation inputs (milli units): the preset kind, caller-driven
// size parameters (grid: nx/nz; rope: nx; volume: nx), particle spacing,
// body pose and whether the anchor edge (grid: the z=0 row; rope: the first
// particle) is kinematic (inv mass 0, pinned in place).
struct SoftArgs {
  int kind;
  int nx;
  int nz;
  int spacing_milli;
  int px_milli, py_milli, pz_milli;
  int rx_milli, ry_milli, rz_milli, rw_milli;
  bool pin_edge;
};

// Integer square root (floor) for the heightfield grid check; n is small
// (<= kMaxHeightfieldSamples^2) so the linear loop is fine.
int isqrt_int(int n) {
  int r = 0;
  while ((r + 1) * (r + 1) <= n) r++;
  return r;
}

// Build the shared settings for one soft body preset from the caller's size
// description.  Returns a non-null RefConst on success (`err` = 0) or null
// with a typed negative code.  All presets end with Optimize() so the
// simulation can consume them (Jolt requires the update groups).
RefConst<SoftBodySharedSettings> build_soft_settings(const SoftArgs& a, int& err) {
  err = kErrBadSoftArgs;
  if (a.spacing_milli <= 0 || a.spacing_milli > kMaxSoftSpacingMilli) return RefConst<SoftBodySharedSettings>();
  const float spacing = from_milli(a.spacing_milli);

  if (a.kind == kSoftGrid) {
    // Cloth grid in the x/z plane: nx by nz particles; two triangles per
    // cell; structural + shear edge constraints created from the faces
    // (compliance 0 = inextensible; no bend constraints for a cloth).
    if (a.nx < kMinSoftGridDim || a.nx > kMaxSoftGridDim) return RefConst<SoftBodySharedSettings>();
    if (a.nz < kMinSoftGridDim || a.nz > kMaxSoftGridDim) return RefConst<SoftBodySharedSettings>();
    Ref<SoftBodySharedSettings> s = new SoftBodySharedSettings;
    for (int iz = 0; iz < a.nz; iz++)
      for (int ix = 0; ix < a.nx; ix++) {
        const float inv_mass = (a.pin_edge && iz == 0) ? 0.0f : 1.0f;
        s->mVertices.push_back(SoftBodySharedSettings::Vertex(
            Float3((float)ix * spacing, 0.0f, (float)iz * spacing), Float3(0, 0, 0), inv_mass));
      }
    auto vidx = [&a](int ix, int iz) { return (uint32)(ix + iz * a.nx); };
    for (int iz = 0; iz + 1 < a.nz; iz++)
      for (int ix = 0; ix + 1 < a.nx; ix++) {
        const uint32 v00 = vidx(ix, iz);
        const uint32 v10 = vidx(ix + 1, iz);
        const uint32 v01 = vidx(ix, iz + 1);
        const uint32 v11 = vidx(ix + 1, iz + 1);
        s->AddFace(SoftBodySharedSettings::Face(v00, v10, v11));
        s->AddFace(SoftBodySharedSettings::Face(v00, v11, v01));
      }
    SoftBodySharedSettings::VertexAttributes attrs(0.0f, 0.0f, FLT_MAX);
    s->CreateConstraints(&attrs, 1, SoftBodySharedSettings::EBendType::None);
    s->Optimize();
    err = 0;
    return s;
  }

  if (a.kind == kSoftRope) {
    // Particle chain along +x with edge constraints only (a rope has no
    // faces: it constrains but does not collide).
    if (a.nx < kMinSoftRopeCount || a.nx > kMaxSoftRopeCount) return RefConst<SoftBodySharedSettings>();
    Ref<SoftBodySharedSettings> s = new SoftBodySharedSettings;
    for (int i = 0; i < a.nx; i++) {
      const float inv_mass = (a.pin_edge && i == 0) ? 0.0f : 1.0f;
      s->mVertices.push_back(SoftBodySharedSettings::Vertex(
          Float3((float)i * spacing, 0.0f, 0.0f), Float3(0, 0, 0), inv_mass));
    }
    for (int i = 0; i + 1 < a.nx; i++) {
      s->mEdgeConstraints.push_back(
          SoftBodySharedSettings::Edge((uint32)i, (uint32)(i + 1)));
    }
    s->CalculateEdgeLengths();
    s->Optimize();
    err = 0;
    return s;
  }

  if (a.kind == kSoftVolume) {
    // Cube of particles with edge + volume constraints and faces (Jolt's
    // own sCreateCube helper, which already computes rest lengths/volumes).
    if (a.pin_edge) return RefConst<SoftBodySharedSettings>();
    if (a.nx < kMinSoftVolumeDim || a.nx > kMaxSoftVolumeDim) return RefConst<SoftBodySharedSettings>();
    Ref<SoftBodySharedSettings> s = SoftBodySharedSettings::sCreateCube((uint)a.nx, spacing);
    if (s == nullptr) return RefConst<SoftBodySharedSettings>();
    s->Optimize();
    err = 0;
    return s;
  }

  return RefConst<SoftBodySharedSettings>();
}

BridgeSoft* find_soft(BridgeWorld* w, int soft_id) {
  for (size_t i = 0; i < w->soft_bodies.size(); i++) {
    if (w->soft_bodies[i].id == soft_id) return &w->soft_bodies[i];
  }
  return nullptr;
}

// Create a soft body from the preset description; returns the bridge soft id
// (>= 0) or a negative code.
int add_soft_impl(BridgeWorld* w, const SoftArgs& a) {
  int err = 0;
  RefConst<SoftBodySharedSettings> settings = build_soft_settings(a, err);
  if (settings == nullptr) return err;
  if (w->bodies.size() + w->soft_bodies.size() >= w->capacity) return kErrFull;

  const Quat rotation = quat_from_milli(a.rx_milli, a.ry_milli, a.rz_milli, a.rw_milli);
  SoftBodyCreationSettings settings_creation(
      settings.GetPtr(),
      RVec3(from_milli(a.px_milli), from_milli(a.py_milli), from_milli(a.pz_milli)),
      rotation, kLayerMoving);
  BodyID body = w->physics.GetBodyInterface().CreateAndAddSoftBody(settings_creation, EActivation::Activate);
  if (body.IsInvalid()) return kErrNoBody;

  BridgeSoft soft;
  soft.id = w->next_soft_id++;
  soft.body = body;
  soft.settings = settings;
  soft.vertex_count = (int)settings->mVertices.size();
  w->soft_bodies.push_back(soft);
  w->dirty = true;
  return soft.id;
}

// Cache a soft body's vertex count, center position (the body position) and
// awake flag into owned scalars; 0 or a negative code.
int cache_soft_state(BridgeWorld* w, int soft_id) {
  BridgeSoft* soft = find_soft(w, soft_id);
  if (soft == nullptr) return kErrBadSoft;
  BodyLockRead lock(w->physics.GetBodyLockInterface(), soft->body);
  if (!lock.Succeeded()) return kErrBadSoft;
  const Body& body = lock.GetBody();
  if (!body.IsSoftBody()) return kErrBadSoft;
  const SoftBodyMotionProperties* props =
      static_cast<const SoftBodyMotionProperties*>(body.GetMotionProperties());
  g_soft_vertex_count = (int)props->GetVertices().size();
  const RVec3 p = body.GetPosition();
  g_soft_pos[0] = to_milli(p.GetX());
  g_soft_pos[1] = to_milli(p.GetY());
  g_soft_pos[2] = to_milli(p.GetZ());
  g_soft_awake = body.IsActive() ? 1 : 0;
  return 0;
}

// Cache one particle's world-space position/velocity into owned scalars;
// 0 or a negative code (kErrBadSoft for a bad id, kErrBadArg for a bad
// index).  Vertex data is relative to the soft body's center of mass, so
// both are transformed by the body's COM transform.
int cache_soft_vertex(BridgeWorld* w, int soft_id, int index) {
  BridgeSoft* soft = find_soft(w, soft_id);
  if (soft == nullptr) return kErrBadSoft;
  BodyLockRead lock(w->physics.GetBodyLockInterface(), soft->body);
  if (!lock.Succeeded()) return kErrBadSoft;
  const Body& body = lock.GetBody();
  if (!body.IsSoftBody()) return kErrBadSoft;
  const SoftBodyMotionProperties* props =
      static_cast<const SoftBodyMotionProperties*>(body.GetMotionProperties());
  const Array<SoftBodyMotionProperties::Vertex>& verts = props->GetVertices();
  if (index < 0 || index >= (int)verts.size()) return kErrBadArg;
  const RMat44 com = body.GetCenterOfMassTransform();
  const RVec3 wp = com * verts[(size_t)index].mPosition;
  const Vec3 wv = com.Multiply3x3(verts[(size_t)index].mVelocity);
  g_soft_vtx_pos[0] = to_milli(wp.GetX());
  g_soft_vtx_pos[1] = to_milli(wp.GetY());
  g_soft_vtx_pos[2] = to_milli(wp.GetZ());
  g_soft_vtx_vel[0] = to_milli(wv.GetX());
  g_soft_vtx_vel[1] = to_milli(wv.GetY());
  g_soft_vtx_vel[2] = to_milli(wv.GetZ());
  return 0;
}

// Write every particle's world-space position (int64 milli xyz triples, row
// order) into the caller-owned buffer; returns the vertex count or a
// negative code (kErrBadBuffer when the buffer is shorter than 3 * count).
int soft_vertices_into(BridgeWorld* w, int soft_id, int64_t* out, int capacity) {
  BridgeSoft* soft = find_soft(w, soft_id);
  if (soft == nullptr) return kErrBadSoft;
  if (out == nullptr || capacity < soft->vertex_count * 3) return kErrBadBuffer;
  BodyLockRead lock(w->physics.GetBodyLockInterface(), soft->body);
  if (!lock.Succeeded()) return kErrBadSoft;
  const Body& body = lock.GetBody();
  if (!body.IsSoftBody()) return kErrBadSoft;
  const SoftBodyMotionProperties* props =
      static_cast<const SoftBodyMotionProperties*>(body.GetMotionProperties());
  const Array<SoftBodyMotionProperties::Vertex>& verts = props->GetVertices();
  const RMat44 com = body.GetCenterOfMassTransform();
  for (Array<SoftBodyMotionProperties::Vertex>::size_type i = 0; i < verts.size(); i++) {
    const RVec3 wp = com * verts[i].mPosition;
    out[3 * i + 0] = (int64_t)to_milli(wp.GetX());
    out[3 * i + 1] = (int64_t)to_milli(wp.GetY());
    out[3 * i + 2] = (int64_t)to_milli(wp.GetZ());
  }
  return (int)verts.size();
}

// ---- heightfield terrain (0.7.0, tier E5) -----------------------------------

// Build a static height field body from a caller-owned sample grid:
// square, row major, n = sqrt(sample_count); sample values are heights in
// milli in [0, scale_y_milli] and are normalized to Jolt's [0, 1] ratio
// against scale_y_milli (so the world height is exactly the milli sample).
// scale_x/scale_z are the world-space sample spacings in milli; offset is
// the body pose.  bits_per_sample selects the quantization: 8 or 16, or 0
// for Jolt's default (8).
int add_heightfield_impl(BridgeWorld* w, int sx_milli, int sy_milli, int sz_milli,
                         int px_milli, int py_milli, int pz_milli,
                         int bits_per_sample, const int64_t* samples, int sample_count) {
  if (samples == nullptr || sample_count <= 0) return kErrBadArg;
  if (sample_count > kMaxHeightfieldSamples * kMaxHeightfieldSamples) return kErrBadHeightfield;
  const int n = isqrt_int(sample_count);
  if (n * n != sample_count) return kErrBadHeightfield;
  if (n < kMinHeightfieldSamples || n > kMaxHeightfieldSamples) return kErrBadHeightfield;
  if (sx_milli <= 0 || sy_milli <= 0 || sz_milli <= 0) return kErrBadArg;
  if (bits_per_sample != 0 && bits_per_sample != 8 && bits_per_sample != 16) return kErrBadArg;

  std::vector<float> heights((size_t)n * (size_t)n);
  for (int i = 0; i < sample_count; i++) {
    const int64_t s = samples[i];
    if (s < 0 || s > (int64_t)sy_milli) return kErrBadHeightfield;
    heights[(size_t)i] = (float)((double)s / (double)sy_milli);
  }

  HeightFieldShapeSettings settings(
      heights.data(),
      Vec3(from_milli(px_milli), from_milli(py_milli), from_milli(pz_milli)),
      Vec3(from_milli(sx_milli), from_milli(sy_milli), from_milli(sz_milli)),
      (uint32)n);
  if (bits_per_sample != 0) settings.mBitsPerSample = (uint32)bits_per_sample;
  ShapeSettings::ShapeResult result = settings.Create();
  if (result.HasError()) return kErrBadHeightfield;
  RefConst<Shape> shape = result.Get();

  // A height field can only be static (Jolt MustBeStatic).
  return register_body_with_shape(w, shape.GetPtr(), 0,
                                  px_milli, py_milli, pz_milli,
                                  0, 0, 0, 0, true, false);
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
// destroyed (rigid + soft, >= 0) or a negative code.  Stale handles are
// rejected.  Constraints are unregistered from the physics system before
// destruction so no joint Ref outlives the world; soft bodies are removed
// like rigid bodies before teardown.
int joltb_world_destroy(int handle) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  int destroyed = (int)(w->bodies.size() + w->soft_bodies.size());
  for (size_t i = 0; i < w->joints.size(); i++) {
    w->physics.RemoveConstraint(w->joints[i].constraint.GetPtr());
  }
  BodyInterface& bi = w->physics.GetBodyInterface();
  for (size_t i = 0; i < w->soft_bodies.size(); i++) {
    bi.RemoveBody(w->soft_bodies[i].body);
    bi.DestroyBody(w->soft_bodies[i].body);
  }
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
// negative code.  Removed ids are stale and rejected afterwards.  Joints
// referencing the body are removed first (Jolt forbids removing a body a
// constraint still references).
int joltb_body_remove(int handle, int packed) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  for (size_t i = 0; i < w->bodies.size(); i++) {
    if (packed_id(w->bodies[i]) != packed) continue;
    remove_joints_for_body(w, packed);
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

// ---- convex + compound bodies (0.6.0, tier E6) -----------------------------

// Add a convex hull body from a caller vertex buffer (`verts_addr` points at
// vert_count * 3 int64 milli components: x, y, z per vertex).  The points are
// copied into a bridge-owned hull; the caller buffer is borrowed for the call
// only.  Returns the body id (>= 0) or a negative code.
int joltb_body_add_convex(int handle, int mass_milli,
                          int px_milli, int py_milli, int pz_milli,
                          int rx_milli, int ry_milli, int rz_milli, int rw_milli,
                          int is_static, int64_t verts_addr, int vert_count) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (verts_addr == 0) return kErrBadArg;
  const int64_t* verts = reinterpret_cast<const int64_t*>(verts_addr);
  bool ok = false;
  RefConst<Shape> shape = build_hull_shape(verts, vert_count, ok);
  if (!ok) return kErrBadHull;
  return register_body_with_shape(w, shape.GetPtr(), mass_milli,
                                  px_milli, py_milli, pz_milli,
                                  rx_milli, ry_milli, rz_milli, rw_milli,
                                  is_static != 0, false);
}

// Add a compound body from a flat part table (kPartStride int64 entries per
// part; see build_compound_shape) and a shared vertex buffer for convex
// parts.  Both buffers are borrowed for the call only.  Returns the body id
// (>= 0) or a negative code.
int joltb_body_add_compound(int handle, int mass_milli,
                            int px_milli, int py_milli, int pz_milli,
                            int rx_milli, int ry_milli, int rz_milli, int rw_milli,
                            int is_static, int64_t parts_addr, int part_count,
                            int64_t verts_addr, int vert_count) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (parts_addr == 0 || part_count <= 0) return kErrBadArg;
  if (part_count > kMaxCompoundParts) return kErrBadCompound;
  if (vert_count < 0 || vert_count > kMaxHullVertices * kMaxCompoundParts) return kErrBadCompound;
  if (vert_count > 0 && verts_addr == 0) return kErrBadArg;
  const int64_t* parts = reinterpret_cast<const int64_t*>(parts_addr);
  const int64_t* verts = reinterpret_cast<const int64_t*>(verts_addr);
  bool ok = false;
  RefConst<Shape> shape = build_compound_shape(parts, part_count, verts, vert_count, ok);
  if (!ok) return kErrBadCompound;
  return register_body_with_shape(w, shape.GetPtr(), mass_milli,
                                  px_milli, py_milli, pz_milli,
                                  rx_milli, ry_milli, rz_milli, rw_milli,
                                  is_static != 0, false);
}

// ---- typed joints (0.6.0, tier E3) -----------------------------------------

// Create a fixed/hinge/slider/point joint between two live bodies or between
// one live body and the world sentinel (kJointWorld).  World-space anchor
// (px/py/pz) and axis (ax/ay/az, hinge/slider only) in milli; limits in
// milli rad (hinge) / milli m (slider); motor config in milli Hz, damping,
// milli N and milli N.m (0 = Jolt default).  Returns the joint id (>= 0) or a
// negative code; bad body ids, unsupported combos and invalid limits yield
// typed errors.
int joltb_joint_add(int handle, int kind, int body_a, int body_b,
                    int px_milli, int py_milli, int pz_milli,
                    int ax_milli, int ay_milli, int az_milli,
                    int auto_anchor, int has_limits,
                    int limits_min_milli, int limits_max_milli,
                    int motor_frequency_milli, int motor_damping_milli,
                    int motor_max_force_milli, int motor_max_torque_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  JointArgs j;
  j.kind = kind;
  j.body_a = body_a;
  j.body_b = body_b;
  j.px_milli = px_milli;
  j.py_milli = py_milli;
  j.pz_milli = pz_milli;
  j.ax_milli = ax_milli;
  j.ay_milli = ay_milli;
  j.az_milli = az_milli;
  j.auto_anchor = auto_anchor != 0;
  j.has_limits = has_limits != 0;
  j.limits_min_milli = limits_min_milli;
  j.limits_max_milli = limits_max_milli;
  j.motor_frequency_milli = motor_frequency_milli;
  j.motor_damping_milli = motor_damping_milli;
  j.motor_max_force_milli = motor_max_force_milli;
  j.motor_max_torque_milli = motor_max_torque_milli;
  return add_joint_impl(w, j);
}

// Remove a joint by id; returns the number of joints left (>= 0) or a
// negative code.  The id is stale afterwards.
int joltb_joint_remove(int handle, int joint_id) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  for (size_t i = 0; i < w->joints.size(); i++) {
    if (w->joints[i].id != joint_id) continue;
    w->physics.RemoveConstraint(w->joints[i].constraint.GetPtr());
    w->joints.erase(w->joints.begin() + i);
    return (int)w->joints.size();
  }
  return kErrBadJoint;
}

// Number of live joints in the world (>= 0) or a negative code.
int joltb_joint_count(int handle) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return (int)w->joints.size();
}

// Drive a joint motor: state 0 off, 1 velocity target (milli rad/s for
// hinge, milli m/s for slider) or 2 position target (milli rad / milli m).
// Fixed and point joints have no motor (kErrNoMotor).  Returns the state or
// a negative code.
int joltb_joint_set_motor(int handle, int joint_id, int state, int target_milli) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (state < kMotorOff || state > kMotorPosition) return kErrBadArg;
  BridgeJoint* joint = find_joint(w, joint_id);
  if (joint == nullptr) return kErrBadJoint;
  if (joint->kind == kJointHinge) {
    HingeConstraint* hinge = static_cast<HingeConstraint*>(joint->constraint.GetPtr());
    switch (state) {
      case kMotorOff:
        hinge->SetMotorState(EMotorState::Off);
        break;
      case kMotorVelocity:
        hinge->SetMotorState(EMotorState::Velocity);
        hinge->SetTargetAngularVelocity(from_milli(target_milli));
        break;
      default:
        hinge->SetMotorState(EMotorState::Position);
        hinge->SetTargetAngle(from_milli(target_milli));
        break;
    }
  } else if (joint->kind == kJointSlider) {
    SliderConstraint* slider = static_cast<SliderConstraint*>(joint->constraint.GetPtr());
    switch (state) {
      case kMotorOff:
        slider->SetMotorState(EMotorState::Off);
        break;
      case kMotorVelocity:
        slider->SetMotorState(EMotorState::Velocity);
        slider->SetTargetVelocity(from_milli(target_milli));
        break;
      default:
        slider->SetMotorState(EMotorState::Position);
        slider->SetTargetPosition(from_milli(target_milli));
        break;
    }
  } else {
    return kErrNoMotor;
  }
  // Motor changes must be seen by the solver this step even if both bodies
  // had fallen asleep (Jolt semantics: constraints solve only active bodies).
  BodyInterface& bi = w->physics.GetBodyInterface();
  if (joint->body_a != kJointWorld) {
    BodyID id_a = find_body(w, joint->body_a);
    if (!id_a.IsInvalid()) bi.ActivateBody(id_a);
  }
  if (joint->body_b != kJointWorld) {
    BodyID id_b = find_body(w, joint->body_b);
    if (!id_b.IsInvalid()) bi.ActivateBody(id_b);
  }
  return state;
}

// Cache one joint's state into the owned scalars: kind, primary value
// (hinge angle in milli rad / slider position in milli m; 0 for fixed and
// point) and the applied total lambda in milli (motor impulse for hinge/
// slider, reaction impulse magnitude for fixed/point).  Returns 0 or a
// negative code.
int joltb_joint_state(int handle, int joint_id) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  BridgeJoint* joint = find_joint(w, joint_id);
  if (joint == nullptr) return kErrBadJoint;
  switch (joint->kind) {
    case kJointHinge: {
      HingeConstraint* hinge = static_cast<HingeConstraint*>(joint->constraint.GetPtr());
      g_joint_primary_milli = to_milli(hinge->GetCurrentAngle());
      g_joint_impulse_milli = to_milli(hinge->GetTotalLambdaMotor());
      break;
    }
    case kJointSlider: {
      SliderConstraint* slider = static_cast<SliderConstraint*>(joint->constraint.GetPtr());
      g_joint_primary_milli = to_milli(slider->GetCurrentPosition());
      g_joint_impulse_milli = to_milli(slider->GetTotalLambdaMotor());
      break;
    }
    case kJointFixed: {
      FixedConstraint* fixed = static_cast<FixedConstraint*>(joint->constraint.GetPtr());
      g_joint_primary_milli = 0;
      g_joint_impulse_milli = to_milli(fixed->GetTotalLambdaPosition().Length());
      break;
    }
    default: { // kJointPoint
      PointConstraint* point = static_cast<PointConstraint*>(joint->constraint.GetPtr());
      g_joint_primary_milli = 0;
      g_joint_impulse_milli = to_milli(point->GetTotalLambdaPosition().Length());
      break;
    }
  }
  g_joint_kind = joint->kind;
  g_joint_body_a = joint->body_a;
  g_joint_body_b = joint->body_b;
  return 0;
}

int joltb_joint_state_kind(void) {
  return g_joint_kind;
}

int joltb_joint_state_primary(void) {
  return g_joint_primary_milli;
}

int joltb_joint_state_impulse(void) {
  return g_joint_impulse_milli;
}

int joltb_joint_state_body_a(void) {
  return g_joint_body_a;
}

int joltb_joint_state_body_b(void) {
  return g_joint_body_b;
}

// ---- soft bodies (0.7.0, tier E4) -------------------------------------------

// Create a soft body from a preset description: kind (0 = cloth grid,
// 1 = rope, 2 = volume cube), caller-driven size (nx/nz/count), particle
// spacing in milli, body pose and pin_edge (grid: pin the z=0 row; rope:
// pin the first particle; volume: rejected).  Returns the bridge soft id
// (>= 0) or a negative code.
int joltb_soft_add(int handle, int kind, int nx, int nz, int spacing_milli,
                   int px_milli, int py_milli, int pz_milli,
                   int rx_milli, int ry_milli, int rz_milli, int rw_milli,
                   int pin_edge) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  SoftArgs a;
  a.kind = kind;
  a.nx = nx;
  a.nz = nz;
  a.spacing_milli = spacing_milli;
  a.px_milli = px_milli;
  a.py_milli = py_milli;
  a.pz_milli = pz_milli;
  a.rx_milli = rx_milli;
  a.ry_milli = ry_milli;
  a.rz_milli = rz_milli;
  a.rw_milli = rw_milli;
  a.pin_edge = pin_edge != 0;
  return add_soft_impl(w, a);
}

// Remove a soft body by id; returns the number of soft bodies left (>= 0)
// or a negative code.  The id is stale afterwards.
int joltb_soft_remove(int handle, int soft_id) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  for (size_t i = 0; i < w->soft_bodies.size(); i++) {
    if (w->soft_bodies[i].id != soft_id) continue;
    BodyInterface& bi = w->physics.GetBodyInterface();
    bi.RemoveBody(w->soft_bodies[i].body);
    bi.DestroyBody(w->soft_bodies[i].body);
    w->soft_bodies.erase(w->soft_bodies.begin() + i);
    w->dirty = true;
    return (int)w->soft_bodies.size();
  }
  return kErrBadSoft;
}

// Number of live soft bodies in the world (>= 0) or a negative code.
int joltb_soft_count(int handle) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return (int)w->soft_bodies.size();
}

// Cache one soft body's vertex count/center/awake into owned scalars;
// 0 or a negative code.
int joltb_soft_state(int handle, int soft_id) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return cache_soft_state(w, soft_id);
}

int joltb_soft_state_count(void) {
  return g_soft_vertex_count;
}

int joltb_soft_state_pos(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_soft_pos[axis];
}

int joltb_soft_state_awake(void) {
  return g_soft_awake;
}

// Cache one particle's world-space position/velocity into owned scalars;
// 0 or a negative code.
int joltb_soft_vertex(int handle, int soft_id, int index) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  return cache_soft_vertex(w, soft_id, index);
}

int joltb_soft_vtx_pos(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_soft_vtx_pos[axis];
}

int joltb_soft_vtx_vel(int axis) {
  if (axis < 0 || axis > 2) return 0;
  return g_soft_vtx_vel[axis];
}

// Write all particle world positions into the caller-owned int64 buffer
// (`out_addr`, capacity in int64 entries): returns the vertex count (>= 0)
// or a negative code (kErrBadBuffer when capacity < 3 * vertex count).
int joltb_soft_vertices_into(int handle, int soft_id, int64_t out_addr, int capacity_entries) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (out_addr == 0) return kErrBadArg;
  int64_t* out = reinterpret_cast<int64_t*>(out_addr);
  return soft_vertices_into(w, soft_id, out, capacity_entries);
}

// ---- heightfield terrain (0.7.0, tier E5) -----------------------------------

// Add a static heightfield body from a caller-owned int64 milli height
// sample grid (square, row major; see add_heightfield_impl).  Returns the
// body id (>= 0) or a negative code.
int joltb_body_add_heightfield(int handle, int sx_milli, int sy_milli, int sz_milli,
                               int px_milli, int py_milli, int pz_milli,
                               int bits_per_sample, int64_t samples_addr, int sample_count) {
  BridgeWorld* w = get_world(handle);
  if (w == nullptr) return kErrBadWorld;
  if (samples_addr == 0) return kErrBadArg;
  const int64_t* samples = reinterpret_cast<const int64_t*>(samples_addr);
  return add_heightfield_impl(w, sx_milli, sy_milli, sz_milli,
                              px_milli, py_milli, pz_milli,
                              bits_per_sample, samples, sample_count);
}

} // extern "C"
