/*
 * xiom.ozz bridge template -- combined into a single TU with the ozz headers
 * it needs (no include-path support in the xiom link line).  See SPEC.md.
 */
#include "ozz/base/maths/vec_float.h"
#include "ozz/base/maths/quaternion.h"
#include "ozz/base/maths/simd_math.h"
#include "ozz/base/maths/soa_transform.h"
#include "ozz/base/maths/soa_float4x4.h"
#include "ozz/base/containers/vector.h"
#include "ozz/base/span.h"
#include "ozz/base/memory/unique_ptr.h"
#include "ozz/animation/runtime/skeleton.h"
#include "ozz/animation/runtime/local_to_model_job.h"
#include "ozz/animation/offline/raw_skeleton.h"
#include "ozz/animation/offline/skeleton_builder.h"

extern "C" {

int ozz_probe_math() {
  using namespace ozz::math;
  Float3 a(1.f, 2.f, 3.f);
  Float3 b(4.f, 5.f, 6.f);
  const float d = Dot(a, b);
  const Float3 c = Cross(a, b);
  if (d != 32.f) return 0;
  if (c.x != -3.f || c.y != 6.f || c.z != -3.f) return 0;
  const Quaternion q = Quaternion::FromAxisAngle(Float3(0.f, 0.f, 1.f), 1.57079632679f);
  const Float3 r = TransformVector(q, Float3(1.f, 0.f, 0.f));
  if (r.x < -0.01f || r.x > 0.01f) return 0;
  if (r.y < 0.99f || r.y > 1.01f) return 0;
  return 1;
}

static ozz::unique_ptr<ozz::animation::Skeleton> ozz_build_probe_skeleton() {
  ozz::animation::offline::RawSkeleton raw;
  raw.roots.resize(1);
  raw.roots[0].name = "root";
  raw.roots[0].children.resize(1);
  raw.roots[0].children[0].name = "child";
  raw.roots[0].children[0].transform.translation = ozz::math::Float3(0.f, 1.f, 0.f);
  ozz::animation::offline::SkeletonBuilder builder;
  return builder(raw);
}

int ozz_probe_skeleton() {
  ozz::unique_ptr<ozz::animation::Skeleton> skel = ozz_build_probe_skeleton();
  if (!skel) return 0;
  if (skel->num_joints() != 2) return 0;
  ozz::span<const int16_t> parents = skel->joint_parents();
  if (parents[0] != -1) return 0;
  if (parents[1] != 0) return 0;
  return 1;
}

int ozz_probe_local_to_model() {
  using namespace ozz::math;
  ozz::unique_ptr<ozz::animation::Skeleton> skel = ozz_build_probe_skeleton();
  if (!skel) return 0;
  ozz::vector<SoaTransform> locals(skel->num_soa_joints(), SoaTransform::identity());
  locals[0].translation.y = simd_float4::Load(0.f, 1.f, 0.f, 0.f);
  ozz::vector<Float4x4> models(skel->num_joints());
  ozz::animation::LocalToModelJob job;
  job.skeleton = skel.get();
  job.input = ozz::make_span(locals);
  job.output = ozz::make_span(models);
  if (!job.Run()) return 0;
  if (GetX(models[0].cols[3]) != 0.f || GetY(models[0].cols[3]) != 0.f || GetZ(models[0].cols[3]) != 0.f) return 0;
  if (GetY(models[1].cols[3]) < 0.99f || GetY(models[1].cols[3]) > 1.01f) return 0;
  return 1;
}

int ozz_probe_all() {
  int r = 0;
  if (!ozz_probe_math()) r |= 1;
  if (!ozz_probe_skeleton()) r |= 2;
  if (!ozz_probe_local_to_model()) r |= 4;
  return r;
}

} /* extern "C" */
