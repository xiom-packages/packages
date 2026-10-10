// xiom.jolt -- C bridge over the vendored Jolt Physics core (v5.6.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Scalar returns (no out-param slots; the B-11 family avoidance).  Each
// probe builds a small world, steps it with a single-threaded job system,
// and caches the results:
//   * joltprobe_drop    -- a 1 m dynamic box dropped from y=5 onto a static
//                          ground; returns the settled center y in milli
//                          (>= 0) or a negative error code.
//   * joltprobe_impulse -- a free dynamic box given vx=5 m/s; returns the
//                          velocity after one step in milli (>= 0).
// Registration mirrors the upstream HelloWorld sample
// (RegisterDefaultAllocator + Factory + RegisterTypes).

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

#include <cstring>

using namespace JPH;

namespace {

constexpr ObjectLayer kLayerNonMoving = 0;
constexpr ObjectLayer kLayerMoving = 1;
constexpr uint kNumLayers = 2;

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

int g_final_y_milli;
int g_awake;
int g_impulse_vx_milli;

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

void register_globals() {
  RegisterDefaultAllocator();
  Factory::sInstance = new Factory();
  RegisterTypes();
}

void unregister_globals() {
  UnregisterTypes();
  delete Factory::sInstance;
  Factory::sInstance = nullptr;
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

} // extern "C"
